Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1') -Force
$script:TransitionUtf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-TransitionFields($Value, [string[]]$Fields, [string]$Label) {
    if ($Value -isnot [pscustomobject] -or @($Value.PSObject.Properties).Count -ne $Fields.Count -or @($Fields | Where-Object { $_ -cnotin @($Value.PSObject.Properties.Name) }).Count) { throw "TRANSITION_${Label}_FIELDS" }
}
function Get-TransitionBytesIdentity([byte[]]$Bytes) { return $Bytes.Length.ToString() + '|' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }
function Get-TransitionIdentity([string]$Path) { return Get-TransitionBytesIdentity ([IO.File]::ReadAllBytes($Path)) }
function Read-TransitionJson([string]$Path) { return (Read-AiwStrictInputJson $Path).Value }
function ConvertTo-TransitionJsonBytes($Value) { return ,$script:TransitionUtf8.GetBytes(($Value | ConvertTo-Json -Depth 100 -Compress) + "`n") }
function Assert-TransitionStrings($Values, [string]$Label) {
    if ($Values -isnot [Array]) { throw "TRANSITION_${Label}_ARRAY" }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in $Values) { if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or -not $seen.Add($value)) { throw "TRANSITION_${Label}_ITEM" } }
}
function Resolve-TransitionPath([string]$Root, [string]$Path, [switch]$Relative) {
    $rootFull = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
    if ($Relative) {
        if ([IO.Path]::IsPathRooted($Path) -or $Path.Contains(':') -or $Path.Contains('\') -or $Path -cne $Path.Trim() -or $Path -cmatch '[\x00-\x1F*?]') { throw 'TRANSITION_PATH' }
        foreach ($part in $Path.Split('/')) { if ([string]::IsNullOrEmpty($part) -or $part -in @('.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'TRANSITION_PATH' } }
        $full = [IO.Path]::GetFullPath((Join-Path $rootFull $Path))
    } else { if (-not [IO.Path]::IsPathRooted($Path)) { throw 'TRANSITION_ABSOLUTE_PATH' }; $full = [IO.Path]::GetFullPath($Path) }
    if (-not $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'TRANSITION_PATH_ESCAPE' }
    $cursor = $full
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'TRANSITION_REPARSE' }
        $next = Split-Path -Parent $cursor
        if ($next -ceq $cursor) { break }; $cursor = $next
    }
    return $full
}
function Assert-AiwNoControlTransition([string]$ProjectRoot, [string]$TaskPath = '') {
    $controllerPath = Resolve-TransitionPath $ProjectRoot '.ai-workspace/controller.json' -Relative
    if (Test-Path -LiteralPath $controllerPath -PathType Leaf) {
        $controller = Read-TransitionJson $controllerPath
        if (@($controller.PSObject.Properties.Name) -icontains 'transitionRef') { throw 'CONTROL_TRANSITION_RECOVERY_REQUIRED|controller' }
    }
    if ($TaskPath) {
        $full = if ([IO.Path]::IsPathRooted($TaskPath)) { Resolve-TransitionPath $ProjectRoot $TaskPath } else { Resolve-TransitionPath $ProjectRoot $TaskPath -Relative }
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $text = $script:TransitionUtf8.GetString([IO.File]::ReadAllBytes($full))
            if ($text -cmatch '(?m)^```aiw-transition') { throw 'CONTROL_TRANSITION_RECOVERY_REQUIRED|task' }
        }
    }
}
function Get-TransitionTaskFacts([string]$Text) {
    $patterns = [ordered]@{
        taskId = '(?m)^#\s+([A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)'
        owner = '(?m)^- Owner:\s*([^\s]+)\s*$'
        route = '(?m)^- Work route:\s*actor=([^;\s]+);\s*role=(CONTROLLER|TASK_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$'
        profile = '(?m)^- Range summary:\s*profile=(MICRO|STANDARD|CRITICAL);'
    }
    $found = @{}
    foreach ($entry in $patterns.GetEnumerator()) { $matches = [regex]::Matches($Text, $entry.Value); if ($matches.Count -ne 1) { throw ('TRANSITION_TASK_FIELD|' + $entry.Key) }; $found[$entry.Key] = $matches[0] }
    return [pscustomobject]@{ TaskId=$found.taskId.Groups[1].Value; Owner=$found.owner.Groups[1].Value; TaskActor=$found.route.Groups[1].Value; Role=$found.route.Groups[2].Value; Phase=$found.route.Groups[3].Value; Profile=$found.profile.Groups[1].Value }
}
function Get-TransitionTaskInvariant([string]$Text, [string[]]$Fields) {
    $facts = Get-TransitionTaskFacts $Text
    $value = $Text
    if ('Owner' -cin $Fields) { $value = [regex]::Replace($value, '(?m)^- Owner:\s*[^\s]+\s*$', '- Owner: <BOUND>') }
    $route = '- Work route: actor=' + $(if ('Actor' -cin $Fields) { '<BOUND>' } else { $facts.TaskActor }) + '; role=' + $(if ('Role' -cin $Fields) { '<BOUND>' } else { $facts.Role }) + '; phase=' + $(if ('Phase' -cin $Fields) { '<BOUND>' } else { $facts.Phase })
    $value = [regex]::Replace($value, '(?m)^- Work route:[^\r\n]*', [Text.RegularExpressions.MatchEvaluator]{param($m) $route})
    if ('Profile' -cin $Fields) {
        $value = [regex]::Replace($value, '(?m)(^- Range summary:\s*profile=)(MICRO|STANDARD|CRITICAL)(;)', '${1}<BOUND>${3}')
        $value = [regex]::Replace($value, '(?m)(^- Profile:\s*)(MICRO|STANDARD|CRITICAL)(;)', '${1}<BOUND>${3}')
    }
    if ('HandoffFacts' -cin $Fields) {
        $blocks = [regex]::Matches($value, '(?ms)^<!-- AIW-HANDOFF:BEGIN -->\r?\n.*?^<!-- AIW-HANDOFF:END -->')
        if ($blocks.Count -ne 1) { throw 'TRANSITION_HANDOFF_BLOCK' }
        $value = $value.Remove($blocks[0].Index, $blocks[0].Length).Insert($blocks[0].Index, '<BOUND_HANDOFF_FACTS>')
    }
    return $value
}
function Read-AiwControlTransitionPlan([string]$ProjectRoot, [string]$PlanPath, [string]$ExpectedPlanIdentity) {
    $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))
    $full = Resolve-TransitionPath $root $PlanPath
    if ($ExpectedPlanIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or (Get-TransitionIdentity $full) -cne $ExpectedPlanIdentity) { throw 'TRANSITION_PLAN_DRIFT' }
    $plan = Read-TransitionJson $full
    Assert-TransitionFields $plan @('schemaVersion','taskId','projectRoot','repositoryId','objects','allowedChanges','steps','recoveryActors','originalProcessLocators') 'PLAN'
    if ($plan.schemaVersion -isnot [long] -and $plan.schemaVersion -isnot [int]) { throw 'TRANSITION_SCHEMA' }
    if ($plan.schemaVersion -ne 1 -or $plan.taskId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or [IO.Path]::GetFullPath([string]$plan.projectRoot) -cne $root -or $plan.repositoryId -cnotin @('CONTROL','REPO_LOCAL')) { throw 'TRANSITION_PLAN_BINDING' }
    $runtime = Join-Path $root ('.ai-workspace/runtime/' + $plan.taskId)
    $null = Resolve-TransitionPath $runtime $full
    $directory = [IO.Path]::GetDirectoryName($full)
    if ([IO.Path]::GetDirectoryName($directory) -cne $runtime) { throw 'TRANSITION_RUNTIME_SCOPE' }
    Assert-TransitionFields $plan.originalProcessLocators @('package','discoverInput','discoverReceipt','admitInput','admitResult','finalizeInput','completionProof') 'LOCATORS'
    $locators = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null = $locators.Add($full)
    foreach ($property in $plan.originalProcessLocators.PSObject.Properties) {
        if ($property.Value -isnot [string]) { throw 'TRANSITION_LOCATOR_TYPE' }
        $path = Resolve-TransitionPath $directory $property.Value
        if ([IO.Path]::GetDirectoryName($path) -cne $directory -or [IO.Path]::GetExtension($path) -cne '.json' -or -not $locators.Add($path)) { throw 'TRANSITION_LOCATOR_SCOPE' }
    }
    Assert-TransitionStrings $plan.recoveryActors 'RECOVERY_ACTORS'
    if ($plan.recoveryActors.Count -eq 0 -or $plan.objects -isnot [Array] -or $plan.objects.Count -eq 0 -or $plan.allowedChanges -isnot [Array] -or $plan.allowedChanges.Count -ne $plan.objects.Count -or $plan.steps -isnot [Array]) { throw 'TRANSITION_PLAN_COLLECTIONS' }
    $objects = [ordered]@{}; $allowedActors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ref = [ordered]@{planPath=$full;planIdentity=$ExpectedPlanIdentity}
    $config=Read-TransitionJson (Resolve-TransitionPath $root '.ai-workspace/project.json' -Relative)
    $forbidden=@($config.routineExcludedPaths)
    if(Test-Path -LiteralPath $plan.originalProcessLocators.discoverInput -PathType Leaf){$observation=Read-TransitionJson $plan.originalProcessLocators.discoverInput;if($null-ne$observation.PSObject.Properties['forbiddenPaths']){$forbidden+=@($observation.forbiddenPaths)}}
    foreach ($item in $plan.objects) {
        Assert-TransitionFields $item @('path','before','after') 'OBJECT'
        $path = [string]$item.path
        if ($path -cne '.ai-workspace/controller.json' -and $path -cnotmatch '^\.ai-workspace/tasks/active/[A-Za-z0-9][A-Za-z0-9._-]*\.md$') { throw 'TRANSITION_OBJECT_SCOPE' }
        foreach($prefix in $forbidden){if($prefix-isnot[string]){throw 'TRANSITION_FORBIDDEN_TYPE'};$normalized=$prefix.TrimEnd('/');if([string]::Equals($path,$normalized,[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith($normalized+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'TRANSITION_FORBIDDEN_READ'}}
        if ($objects.Contains($path)) { throw 'TRANSITION_OBJECT_DUPLICATE' }
        $null = Resolve-TransitionPath $root $path -Relative
        $changes = @($plan.allowedChanges | Where-Object { $_.path -ceq $path })
        if ($changes.Count -ne 1) { throw 'TRANSITION_CHANGE_PATH' }
        Assert-TransitionFields $changes[0] @('path','fields') 'CHANGE'
        Assert-TransitionStrings $changes[0].fields 'CHANGE_FIELDS'
        $images = [ordered]@{}
        foreach ($name in @('before','after')) {
            Assert-TransitionFields $item.$name @('identity','base64') 'IMAGE'
            if ($item.$name.base64 -isnot [string] -or $item.$name.identity -isnot [string]) { throw 'TRANSITION_IMAGE_TYPE' }
            $bytes = [Convert]::FromBase64String($item.$name.base64)
            if ((Get-TransitionBytesIdentity $bytes) -cne $item.$name.identity) { throw 'TRANSITION_IMAGE_IDENTITY' }
            $text = $script:TransitionUtf8.GetString($bytes)
            if ($text.Contains([char]0) -or $text.Contains([char]0xFEFF) -or $text -cmatch '(?m)^```aiw-transition') { throw 'TRANSITION_PREEXISTING_MARKER_OR_ENCODING' }
            $images[$name.ToUpperInvariant()] = [pscustomobject]@{Identity=[string]$item.$name.identity;Bytes=$bytes;Text=$text}
        }
        if ($images.BEFORE.Identity -ceq $images.AFTER.Identity) { throw 'TRANSITION_NO_CHANGE' }
        if ($path -ceq '.ai-workspace/controller.json') {
            if (@($changes[0].fields).Count -ne 2 -or 'ControllerId' -cnotin $changes[0].fields -or 'ControllerEpoch' -cnotin $changes[0].fields) { throw 'TRANSITION_CONTROLLER_FIELDS' }
            $before = (ConvertFrom-AiwStrictInputJson $images.BEFORE.Text).Value; $after = (ConvertFrom-AiwStrictInputJson $images.AFTER.Text).Value
            foreach ($value in @($before,$after)) {
                Assert-TransitionFields $value @('schemaVersion','projectId','controllerId','controllerEpoch','state') 'CONTROLLER'
                if ($value.schemaVersion -ne 1 -or $value.state -cne 'CURRENT' -or $value.controllerId -isnot [string] -or [string]::IsNullOrWhiteSpace($value.controllerId) -or $value.controllerEpoch -isnot [long] -or $value.controllerEpoch -lt 1) { throw 'TRANSITION_CONTROLLER_VALUES' }
                $null = $allowedActors.Add($value.controllerId)
            }
            if ($before.projectId -cne $after.projectId -or $before.controllerId -ceq $after.controllerId -or $before.controllerEpoch -ge [long]::MaxValue -or $after.controllerEpoch -ne ($before.controllerEpoch + 1)) { throw 'TRANSITION_CONTROLLER_DELTA' }
            foreach ($pair in @(@('MARKED_BEFORE',$before),@('MARKED_TARGET',$after))) {
                $value = $pair[1] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                $value | Add-Member -NotePropertyName transitionRef -NotePropertyValue $ref
                $bytes = ConvertTo-TransitionJsonBytes $value
                $images[$pair[0]] = [pscustomobject]@{Identity=(Get-TransitionBytesIdentity $bytes);Bytes=$bytes}
            }
        } else {
            if ($changes[0].fields.Count -eq 0 -or @($changes[0].fields | Where-Object { $_ -cnotin @('Owner','Actor','Role','Phase','Profile','HandoffFacts') }).Count) { throw 'TRANSITION_TASK_FIELDS' }
            if ((Get-TransitionTaskInvariant $images.BEFORE.Text $changes[0].fields) -cne (Get-TransitionTaskInvariant $images.AFTER.Text $changes[0].fields)) { throw 'TRANSITION_UNAUTHORIZED_TASK_DELTA' }
            foreach ($value in @($images.BEFORE.Text,$images.AFTER.Text)) { $facts = Get-TransitionTaskFacts $value; $null=$allowedActors.Add($facts.Owner); $null=$allowedActors.Add($facts.TaskActor) }
            $marker = "`n" + '```aiw-transition' + "`n" + ($ref | ConvertTo-Json -Compress) + "`n" + '```' + "`n"
            foreach ($pair in @(@('MARKED_BEFORE','BEFORE'),@('MARKED_TARGET','AFTER'))) { $bytes=$script:TransitionUtf8.GetBytes($images[$pair[1]].Text+$marker); $images[$pair[0]]=[pscustomobject]@{Identity=(Get-TransitionBytesIdentity $bytes);Bytes=$bytes} }
        }
        $objects[$path] = $images
    }
    $paths = @($objects.Keys); $controllerPaths = @($paths | Where-Object { $_ -ceq '.ai-workspace/controller.json' }); $taskPaths = @($paths | Where-Object { $_ -cne '.ai-workspace/controller.json' })
    $expectedSteps = @()
    foreach ($path in @($controllerPaths+$taskPaths)) { $expectedSteps += [pscustomobject]@{path=$path;image='MARKED_BEFORE'} }
    foreach ($path in @($taskPaths+$controllerPaths)) { $expectedSteps += [pscustomobject]@{path=$path;image='MARKED_TARGET'} }
    foreach ($path in @($taskPaths+$controllerPaths)) { $expectedSteps += [pscustomobject]@{path=$path;image='AFTER'} }
    if ($plan.steps.Count -ne $expectedSteps.Count) { throw 'TRANSITION_STEP_COUNT' }
    $states = [Collections.Generic.List[object]]::new(); $state = [ordered]@{}
    foreach ($path in $paths) { $state[$path]='BEFORE' }; $states.Add($state)
    for ($i=0;$i -lt $expectedSteps.Count;$i++) {
        Assert-TransitionFields $plan.steps[$i] @('path','image') 'STEP'
        if ($plan.steps[$i].path -cne $expectedSteps[$i].path -or $plan.steps[$i].image -cne $expectedSteps[$i].image) { throw 'TRANSITION_STEP_ORDER' }
        $next=[ordered]@{};foreach($path in $paths){$next[$path]=$state[$path]};$next[$expectedSteps[$i].path]=$expectedSteps[$i].image;$states.Add($next);$state=$next
    }
    return [pscustomobject]@{Root=$root;Path=$full;Identity=$ExpectedPlanIdentity;Plan=$plan;Ref=$ref;Objects=$objects;Paths=$paths;States=$states;MarkedIndex=2*$paths.Count;FinalIndex=3*$paths.Count;AllowedActors=$allowedActors}
}
function Get-TransitionState($Context) {
    $actual=[ordered]@{}
    foreach($path in $Context.Paths){$full=Resolve-TransitionPath $Context.Root $path -Relative;if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'TRANSITION_OBJECT_MISSING'};$actual[$path]=Get-TransitionIdentity $full}
    $matches=@()
    for($i=0;$i -lt $Context.States.Count;$i++){$ok=$true;foreach($path in $Context.Paths){if($actual[$path]-cne$Context.Objects[$path][$Context.States[$i][$path]].Identity){$ok=$false;break}};if($ok){$matches+=$i}}
    if($matches.Count -ne 1){throw 'TRANSITION_UNREACHABLE_STATE'}
    return [int]$matches[0]
}
function Assert-AiwControlTransitionPackage($Package,[string]$ProjectRoot) {
    Assert-TransitionFields $Package.transitionPlan @('path','identity') 'PACKAGE_REF'
    if (@($Package.actions).Count -ne 1 -or $Package.actions[0] -cne 'CONTROL_WRITE' -or $null -ne $Package.PSObject.Properties['continuationPlan'] -or $null -ne $Package.PSObject.Properties['repairReviewPlan'] -or $Package.schemaVersion -notin @(1,2)) { throw 'TRANSITION_PURE_CONTROL_WRITE_REQUIRED' }
    $context=Read-AiwControlTransitionPlan $ProjectRoot $Package.transitionPlan.path $Package.transitionPlan.identity
    $repo=if($Package.schemaVersion-eq1){'REPO_LOCAL'}else{[string]$Package.repositoryId}
    if($repo-cne$context.Plan.repositoryId-or$Package.taskId-cne$context.Plan.taskId-or($Package.exactPaths-join"`n")-cne($context.Paths-join"`n")){throw 'TRANSITION_PACKAGE_BINDING'}
    if(@($Package.objectIdentities).Count-ne$context.Paths.Count){throw 'TRANSITION_PACKAGE_PREIMAGES'}
    foreach($path in $context.Paths){$entry=@($Package.objectIdentities|Where-Object{$_.path-ceq$path});if($entry.Count-ne1-or$entry[0].identity-cne$context.Objects[$path].BEFORE.Identity){throw 'TRANSITION_PACKAGE_PREIMAGES'}}
    $null=$context.AllowedActors.Add([string]$Package.grantee)
    foreach($actor in $context.Plan.recoveryActors){if(-not$context.AllowedActors.Contains($actor)){throw 'TRANSITION_RECOVERY_ACTOR_SCOPE'}}
    if([string]$Package.grantee-cnotin$context.Plan.recoveryActors){throw 'TRANSITION_ORIGINAL_ACTOR_REQUIRED'}
    return $context
}
function Get-TransitionOriginalChain($Context) {
    $l=$Context.Plan.originalProcessLocators;$package=Read-TransitionJson $l.package
    $bound=Assert-AiwControlTransitionPackage $package $Context.Root
    if($bound.Identity-cne$Context.Identity-or$bound.Path-cne$Context.Path){throw 'TRANSITION_CHAIN_PLAN'}
    $discover=Read-TransitionJson $l.discoverInput;$rawReceipt=Read-TransitionJson $l.discoverReceipt;$admit=Read-TransitionJson $l.admitInput;$result=Read-TransitionJson $l.admitResult
    if($rawReceipt.schemaVersion-ne2){throw 'TRANSITION_REQUIRES_COMPACT_2'}
    $binding=$rawReceipt.binding
    if(($discover.intentEnvelope|ConvertTo-Json -Depth 30 -Compress)-cne($rawReceipt.intentEnvelope|ConvertTo-Json -Depth 30 -Compress)-or($discover.forbiddenPaths-join"`n")-cne($binding.forbiddenScope-join"`n")-or($discover.protectedPaths-join"`n")-cne($binding.protectedScope-join"`n")){throw 'TRANSITION_ORIGINAL_CONTEXT_DRIFT'}
    if($discover.mode-cne'DISCOVER'-or$discover.schemaVersion-ne3-or$discover.contextType-cne'TASK'-or$discover.evaluationOnly-or$rawReceipt.status-cne'PASS'-or$rawReceipt.mode-cne'DISCOVER'-or$rawReceipt.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or$binding.frameworkVersion-cne'2.0.0'-or$binding.projectRoot-cne$Context.Root-or$binding.taskId-cne$Context.Plan.taskId-or$binding.actor-cne$package.grantee-or$binding.taskOwner-cne$package.owner-or$binding.taskIdentity-cne$package.taskIdentity-or$binding.authorizationIdentity-cne(Get-TransitionIdentity $l.package)-or$rawReceipt.sourceLocators.authorizationPackagePath-cne$l.package-or$discover.authorizationPackagePath-cne$l.package-or$discover.expectedAuthorizationIdentity-cne$binding.authorizationIdentity-or$discover.observedActor-cne$binding.actor-or$discover.expectedTaskIdentity-cne$binding.taskIdentity-or$discover.projectRoot-cne$Context.Root){throw 'TRANSITION_ORIGINAL_DISCOVER_BINDING'}
    if($rawReceipt.intentEnvelope.requestedActionKind-cne'CONTROL_WRITE'-or($binding.exactScope-join"`n")-cne($Context.Paths-join"`n")-or($discover.exactPaths-join"`n")-cne($Context.Paths-join"`n")-or$binding.userDecision-cne$package.userConfirmation){throw 'TRANSITION_ORIGINAL_SCOPE'}
    if($admit.mode-cne'ADMIT_ACTION'-or$admit.discoverReceiptPath-cne$l.discoverReceipt-or$admit.expectedDiscoverReceiptIdentity-cne(Get-TransitionIdentity $l.discoverReceipt)-or$result.status-cne'PASS'-or$result.mode-cne'ADMIT_ACTION'-or$result.selectionIdentity-cne$rawReceipt.selectionIdentity-or$result.decisionIdentity-cnotmatch'^[A-F0-9]{64}$'-or$result.authorityGranted-ne$false){throw 'TRANSITION_ORIGINAL_ADMIT_REQUIRED'}
    $required=@($rawReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Select-Object -Unique)
    if(@($required|Where-Object{$_-cnotin$admit.preparationReceipts}).Count){throw 'TRANSITION_ORIGINAL_ADMIT_INCOMPLETE'}
    # Snapshots observe bytes only. Ordinary entry points separately reject markers;
    # this path permits exactly the plan-derived task/controller images, nothing else.
    $composer=Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru
    $decision=& $composer.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $rawReceipt $admit
    if($decision-cne$result.decisionIdentity){throw 'TRANSITION_ORIGINAL_ADMIT_DECISION'}
    $snapshot=& $composer.ExportedFunctions['Get-AiwProcessBindingSnapshot'] -ProjectRoot $Context.Root -FrameworkRoot $rawReceipt.sourceLocators.frameworkRoot -TargetVersion '2.0.0' -TaskRelativePath $rawReceipt.sourceLocators.taskRelativePath -ForbiddenPaths @($binding.forbiddenScope)
    foreach($name in $rawReceipt.sourceBindings.PSObject.Properties.Name){
        $path=if($name-ceq'controllerIdentity'){'.ai-workspace/controller.json'}elseif($name-ceq'taskIdentity'){[string]$rawReceipt.sourceLocators.taskRelativePath}else{''}
        $expected=if($path-and$Context.Objects.Contains($path)){$Context.Objects[$path].BEFORE.Identity}else{[string]$snapshot.$name}
        if($expected-cne[string]$rawReceipt.sourceBindings.$name){throw ('TRANSITION_SOURCE_DRIFT|'+$name)}
    }
    $identities=[ordered]@{}
    foreach($name in @('package','discoverInput','discoverReceipt','admitInput','admitResult')){$identities[$name]=[ordered]@{path=[string]$l.$name;identity=(Get-TransitionIdentity $l.$name)}}
    return [pscustomobject]@{Package=$package;Discover=$discover;Receipt=$rawReceipt;Admit=$admit;AdmitResult=$result;References=$identities;Snapshot=$snapshot}
}
function Invoke-TransitionCheckpoint([string]$Name) {
    # Private fixture seam; not an input field, environment contract or public mode.
    $point=Get-Variable -Name ControlTransitionTestCheckpoint -Scope Script -ErrorAction SilentlyContinue
    if($null-ne$point-and$null-ne$point.Value){& $point.Value $Name}
}
function Write-TransitionAtomic([string]$Path,[byte[]]$Bytes,[string]$ExpectedIdentity) {
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if($ExpectedIdentity-ceq'NEW'){
            if(Test-Path -LiteralPath $Path){throw 'TRANSITION_ATOMIC_DESTINATION_EXISTS'}
            [IO.File]::Move($temporary,$Path,$false)
        }else{
            if((Get-TransitionIdentity $Path)-cne$ExpectedIdentity){throw 'TRANSITION_ATOMIC_PREIMAGE_DRIFT'}
            [IO.File]::Move($temporary,$Path,$true)
        }
        if((Get-TransitionIdentity $Path)-cne(Get-TransitionBytesIdentity $Bytes)){throw 'TRANSITION_ATOMIC_READBACK'}
    }finally{if(Test-Path -LiteralPath $temporary -PathType Leaf){Remove-Item -LiteralPath $temporary}}
}
function Get-TransitionProof($Context,$Chain) {
    $path=$Context.Plan.originalProcessLocators.completionProof
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    $proof=Read-TransitionJson $path
    Assert-TransitionFields $proof @('schemaVersion','kind','status','planRef','originalProcess','finalizeInput','finalizeResult','verifiedPostimages','finalPostimages','cleanupSteps','evidenceGrade') 'PROOF'
    if($proof.schemaVersion-ne1-or$proof.kind-cne'CONTROL_TRANSITION_COMPLETION'-or$proof.status-cne'COMMITTED'-or$proof.evidenceGrade-cne'INSTRUCTION_BOUND'-or$proof.planRef.planPath-cne$Context.Path-or$proof.planRef.planIdentity-cne$Context.Identity){throw 'TRANSITION_PROOF_BINDING'}
    if(($proof.originalProcess|ConvertTo-Json -Depth 30 -Compress)-cne($Chain.References|ConvertTo-Json -Depth 30 -Compress)){throw 'TRANSITION_PROOF_PROCESS_DRIFT'}
    if($proof.finalizeInput.path-cne$Context.Plan.originalProcessLocators.finalizeInput-or$proof.finalizeInput.identity-cne(Get-TransitionIdentity $proof.finalizeInput.path)-or$proof.finalizeResult.status-cne'PASS'-or$proof.finalizeResult.mode-cne'FINALIZE_OUTPUT'-or$proof.finalizeResult.selectionIdentity-cne$Chain.Receipt.selectionIdentity-or$proof.finalizeResult.decisionIdentity-cnotmatch'^[A-F0-9]{64}$'){throw 'TRANSITION_PROOF_FINALIZE'}
    $finalInput=Read-TransitionJson $proof.finalizeInput.path
    if($finalInput.mode-cne'FINALIZE_OUTPUT'-or$finalInput.discoverReceiptPath-cne$Context.Plan.originalProcessLocators.discoverReceipt-or$finalInput.expectedDiscoverReceiptIdentity-cne(Get-TransitionIdentity $finalInput.discoverReceiptPath)){throw 'TRANSITION_PROOF_INPUT_BINDING'}
    $changed=@();if($Context.Objects.Contains('.ai-workspace/controller.json')){$changed+='controllerIdentity'};if($Context.Objects.Contains([string]$Chain.Receipt.sourceLocators.taskRelativePath)){$changed+='taskIdentity'}
    $composer=Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru
    $expectedDecision=& $composer.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $Chain.Receipt $finalInput ([string]$proof.finalizeResult.sourcePostimageTransition.currentSourceCompositionIdentity) $changed
    if($expectedDecision-cne$proof.finalizeResult.decisionIdentity){throw 'TRANSITION_PROOF_DECISION'}
    foreach($pair in @(@('verifiedPostimages','MARKED_TARGET'),@('finalPostimages','AFTER'))){
        $entries=@($proof.($pair[0]));if($entries.Count-ne$Context.Paths.Count){throw 'TRANSITION_PROOF_IMAGES'}
        foreach($p in $Context.Paths){$entry=@($entries|Where-Object{$_.path-ceq$p});if($entry.Count-ne1-or$entry[0].identity-cne$Context.Objects[$p][$pair[1]].Identity){throw 'TRANSITION_PROOF_IMAGES'}}
    }
    $cleanup=@($Context.Plan.steps|Select-Object -Skip $Context.MarkedIndex)
    if(($proof.cleanupSteps|ConvertTo-Json -Compress)-cne($cleanup|ConvertTo-Json -Compress)){throw 'TRANSITION_PROOF_CLEANUP'}
    return $proof
}
function Get-AiwControlTransitionFinalization($Package,$Receipt,[string]$InputPath) {
    $context=Assert-AiwControlTransitionPackage $Package $Receipt.sourceLocators.projectRoot
    $chain=Get-TransitionOriginalChain $context
    if([IO.Path]::GetFullPath($InputPath)-cne$context.Plan.originalProcessLocators.finalizeInput-or$Receipt.selectionIdentity-cne$chain.Receipt.selectionIdentity){throw 'TRANSITION_FINALIZE_ORIGINAL_PROCESS_REQUIRED'}
    if(Get-TransitionProof $context $chain){throw 'TRANSITION_ALREADY_COMMITTED_USE_COMPLETE'}
    if((Get-TransitionState $context)-ne$context.MarkedIndex){throw 'TRANSITION_TARGET_MARKERS_REQUIRED'}
    $actor=[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')
    if($actor-cnotin$context.Plan.recoveryActors){throw 'TRANSITION_RECOVERY_ACTOR'}
    $taskPath=[string]$chain.Receipt.sourceLocators.taskRelativePath
    $taskText=if($context.Objects.Contains($taskPath)){$context.Objects[$taskPath].AFTER.Text}else{$script:TransitionUtf8.GetString([IO.File]::ReadAllBytes((Join-Path $context.Root $taskPath)))}
    return [pscustomobject]@{Context=$context;Chain=$chain;Task=(Get-TransitionTaskFacts $taskText)}
}
function Get-AiwControlTransitionCompositions($Context,$Discover) {
    $module=Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru
    $taskRelative=[IO.Path]::GetRelativePath($Context.Root,[string]$Discover.taskPath).Replace('\','/')
    $tasks=@($taskRelative)+@($Context.Paths|Where-Object{$_-cne'.ai-workspace/controller.json'-and$_-cne$taskRelative})
    $results=@()
    foreach($relative in $tasks){
        $full=Resolve-TransitionPath $Context.Root $relative -Relative
        $text=if($Context.Objects.Contains($relative)){$Context.Objects[$relative].AFTER.Text}else{$script:TransitionUtf8.GetString([IO.File]::ReadAllBytes($full))}
        $facts=Get-TransitionTaskFacts $text
        $results+=& $module.ExportedFunctions['Invoke-ProcessRequirementComposition'] -ProjectRoot $Context.Root -FrameworkRoot $Discover.frameworkRoot -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity $Discover.expectedProjectConfigIdentity -ExpectedCorrectionsIdentity $Discover.expectedCorrectionsIdentity -Profile $facts.Profile -Role $facts.Role -Phase $facts.Phase -Actor $facts.TaskActor -TaskIdentity (Get-TransitionIdentity $full) -Capabilities @($Discover.capabilities) -Objective ([string]::Join(' ',@($Discover.intentEnvelope.semanticHints))) -ActionKind 'CONTROL_WRITE' -ResultKind $Discover.intentEnvelope.requestedResultKind -ExactPaths @($Context.Paths) -ForbiddenPaths @($Discover.forbiddenPaths)
    }
    return $results
}
function Save-AiwControlTransitionCompletion($Finalization,$Result,[string]$InputPath) {
    if($Result.status-cne'PASS'-or$Result.mode-cne'FINALIZE_OUTPUT'){throw 'TRANSITION_FINALIZE_NOT_SUCCESSFUL'}
    $context=$Finalization.Context;$lock=Open-TransitionLock $context
    try {
    $chain=Get-TransitionOriginalChain $context
    if((Get-TransitionState $context)-ne$context.MarkedIndex){throw 'TRANSITION_FINALIZE_STATE_DRIFT'}
    $proof=[ordered]@{schemaVersion=1;kind='CONTROL_TRANSITION_COMPLETION';status='COMMITTED';planRef=$context.Ref;originalProcess=$chain.References;finalizeInput=[ordered]@{path=$InputPath;identity=(Get-TransitionIdentity $InputPath)};finalizeResult=$Result;verifiedPostimages=@($context.Paths|ForEach-Object{[ordered]@{path=$_;identity=$context.Objects[$_].MARKED_TARGET.Identity}});finalPostimages=@($context.Paths|ForEach-Object{[ordered]@{path=$_;identity=$context.Objects[$_].AFTER.Identity}});cleanupSteps=@($context.Plan.steps|Select-Object -Skip $context.MarkedIndex);evidenceGrade='INSTRUCTION_BOUND'}
    Invoke-TransitionCheckpoint 'BEFORE_PROOF'
    Write-TransitionAtomic $context.Plan.originalProcessLocators.completionProof (ConvertTo-TransitionJsonBytes $proof) 'NEW'
    $null=Get-TransitionProof $context $chain
    Invoke-TransitionCheckpoint 'AFTER_PROOF'
    return [ordered]@{path=$context.Plan.originalProcessLocators.completionProof;identity=(Get-TransitionIdentity $context.Plan.originalProcessLocators.completionProof);status='COMMITTED';cleanup='PENDING'}
    }finally{$lock.Dispose()}
}
function Open-TransitionLock($Context){
    $lockPath=Resolve-TransitionPath ([IO.Path]::GetDirectoryName($Context.Path)) ($Context.Path+'.lock')
    $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if($lock.Length-ne0){$lock.Dispose();throw 'TRANSITION_LOCK_CONTENT'}
    return $lock
}
function Move-TransitionState($Context,[int]$From,[int]$To) {
    if((Get-TransitionState $Context)-ne$From-or[math]::Abs($To-$From)-ne1){throw 'TRANSITION_STEP_PREIMAGE'}
    $stepIndex=[math]::Min($From,$To);$path=[string]$Context.Plan.steps[$stepIndex].path
    $before=$Context.Objects[$path][$Context.States[$From][$path]];$after=$Context.Objects[$path][$Context.States[$To][$path]]
    Invoke-TransitionCheckpoint ('BEFORE_STEP_'+$From+'_'+$To)
    Write-TransitionAtomic (Resolve-TransitionPath $Context.Root $path -Relative) $after.Bytes $before.Identity
    if((Get-TransitionState $Context)-ne$To){throw 'TRANSITION_STEP_READBACK'}
    Invoke-TransitionCheckpoint ('AFTER_STEP_'+$From+'_'+$To)
}
function Invoke-AiwControlTransition($InputObject) {
    Assert-TransitionFields $InputObject @('operation','projectRoot','planPath','expectedPlanIdentity','recoveryMode') 'INPUT'
    if($InputObject.operation-cnotin@('PREVIEW','APPLY','FINALIZE','COMPLETE','RECOVER')-or$InputObject.recoveryMode-cnotin@('NOT_APPLICABLE','CONTINUE','ROLLBACK')-or(($InputObject.operation-ceq'RECOVER')-ne($InputObject.recoveryMode-cne'NOT_APPLICABLE'))){throw 'TRANSITION_OPERATION'}
    $context=Read-AiwControlTransitionPlan $InputObject.projectRoot $InputObject.planPath $InputObject.expectedPlanIdentity
    if($InputObject.operation-ceq'PREVIEW'){
        if((Get-TransitionState $context)-ne0){throw 'TRANSITION_PREVIEW_REQUIRES_PREIMAGES'}
        $discover=Read-TransitionJson $context.Plan.originalProcessLocators.discoverInput
        if($discover.projectRoot-cne$context.Root-or$discover.schemaVersion-ne3-or$discover.intentEnvelope.requestedActionKind-cne'CONTROL_WRITE'){throw 'TRANSITION_PREVIEW_CONTEXT'}
        $targetCompositions=@(Get-AiwControlTransitionCompositions $context $discover)
        return [ordered]@{status='PREVIEW';planRef=$context.Ref;steps=$context.Plan.steps;derivedImages=@($context.Paths|ForEach-Object{$p=$_;[ordered]@{path=$p;markedBeforeIdentity=$context.Objects[$p].MARKED_BEFORE.Identity;markedTargetIdentity=$context.Objects[$p].MARKED_TARGET.Identity}});targetRuleBlocks=@($targetCompositions.selectedRequirements);authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}
    }
    $actor=[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')
    if([string]::IsNullOrWhiteSpace($actor)-or$actor-cnotin$context.Plan.recoveryActors){throw 'TRANSITION_RECOVERY_ACTOR'}
    # The original FINALIZE process acquires this same lock when persisting its
    # completion point. Do not hold it across that child process invocation.
    $lock=if($InputObject.operation-ceq'FINALIZE'){$null}else{Open-TransitionLock $context}
    try {
        $chain=Get-TransitionOriginalChain $context;$state=Get-TransitionState $context;$proof=Get-TransitionProof $context $chain
        if($null-ne$proof-and$state-lt$context.MarkedIndex){throw 'TRANSITION_COMMITTED_STATE_REGRESSION'}
        if($null-eq$proof-and$state-gt$context.MarkedIndex){throw 'TRANSITION_CLEANUP_WITHOUT_PROOF'}
        if($InputObject.operation-ceq'APPLY'){
            if($actor-cne$chain.Package.grantee-or$state-ne0-or$null-ne$proof){throw 'TRANSITION_APPLY_REQUIRES_ORIGINAL_START'}
        }
        if($InputObject.operation-ceq'APPLY'-or($InputObject.operation-ceq'RECOVER'-and$state-eq0-and$InputObject.recoveryMode-ceq'CONTINUE')){
            $resolver=Join-Path $PSScriptRoot 'resolve-process-requirements.ps1'
            $raw=@(& ([Environment]::ProcessPath) -NoProfile -File $resolver -InputPath $context.Plan.originalProcessLocators.admitInput -AsJson)
            if($LASTEXITCODE-ne0){throw ('TRANSITION_ORIGINAL_READMIT_FAILED|'+($raw-join';'))}
            $verified=($raw-join"`n")|ConvertFrom-Json
            if($verified.status-cne'PASS'-or$verified.decisionIdentity-cne$chain.AdmitResult.decisionIdentity){throw 'TRANSITION_ORIGINAL_READMIT_DRIFT'}
        }
        if($InputObject.operation-ceq'FINALIZE'){
            if($null-ne$proof){return [ordered]@{status='COMMITTED';planRef=$context.Ref;cleanup='PENDING';authorityGranted=$false}}
            if($state-ne$context.MarkedIndex){throw 'TRANSITION_FINALIZE_STATE'}
            $raw=@(& ([Environment]::ProcessPath) -NoProfile -File (Join-Path $PSScriptRoot 'resolve-process-requirements.ps1') -InputPath $context.Plan.originalProcessLocators.finalizeInput -AsJson)
            if($LASTEXITCODE-ne0){throw ('TRANSITION_FINALIZE_FAILED|'+($raw-join';'))}
            $result=($raw-join"`n")|ConvertFrom-Json;$proof=Get-TransitionProof $context $chain
            if($null-eq$proof-or$result.status-cne'PASS'){throw 'TRANSITION_PROOF_MISSING'}
            return [ordered]@{status='COMMITTED';planRef=$context.Ref;completionProof=[ordered]@{path=$context.Plan.originalProcessLocators.completionProof;identity=(Get-TransitionIdentity $context.Plan.originalProcessLocators.completionProof)};cleanup='PENDING';authorityGranted=$false}
        }
        if($InputObject.operation-ceq'RECOVER'-and$InputObject.recoveryMode-ceq'ROLLBACK'){
            if($null-ne$proof){throw 'TRANSITION_COMMITTED_NO_ROLLBACK'}
            while($state-gt0){Move-TransitionState $context $state ($state-1);$state--}
            return [ordered]@{status='ROLLED_BACK';planRef=$context.Ref;authorityGranted=$false}
        }
        if($InputObject.operation-ceq'COMPLETE'-and$null-eq$proof){throw 'TRANSITION_COMPLETION_PROOF_REQUIRED'}
        if($null-eq$proof){
            while($state-lt$context.MarkedIndex){Move-TransitionState $context $state ($state+1);$state++}
            return [ordered]@{status='APPLIED';planRef=$context.Ref;finalizeRequired=$true;authorityGranted=$false}
        }
        while($state-lt$context.FinalIndex){$null=Get-TransitionProof $context (Get-TransitionOriginalChain $context);Move-TransitionState $context $state ($state+1);$state++}
        $null=Get-TransitionProof $context (Get-TransitionOriginalChain $context)
        if((Get-TransitionState $context)-ne$context.FinalIndex){throw 'TRANSITION_FINAL_READBACK'}
        Invoke-TransitionCheckpoint 'BEFORE_COMPLETE_RETURN'
        return [ordered]@{status='COMPLETE';planRef=$context.Ref;completionProof=[ordered]@{path=$context.Plan.originalProcessLocators.completionProof;identity=(Get-TransitionIdentity $context.Plan.originalProcessLocators.completionProof)};authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}
    } finally { if($null-ne$lock){$lock.Dispose()} }
}
Export-ModuleMember -Function Assert-AiwNoControlTransition,Read-AiwControlTransitionPlan,Assert-AiwControlTransitionPackage,Get-AiwControlTransitionFinalization,Get-AiwControlTransitionCompositions,Save-AiwControlTransitionCompletion,Invoke-AiwControlTransition
