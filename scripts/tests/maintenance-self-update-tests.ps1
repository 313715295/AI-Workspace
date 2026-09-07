#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepositoryRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$SeedControlRoot,
    [string]$SeedFrameworkRoot,
    [string]$SeedTransactionPath,
    [string]$ExpectedSeedTransactionIdentity
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$utf8=[Text.UTF8Encoding]::new($false);$passes=0;$lf=[string][char]10
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('aiw-maintenance-self-update-'+[guid]::NewGuid().ToString('N'))
function Confirm([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT_FAIL|'+$Name)};$script:passes++}
function Write-Text([string]$Path,[string]$Text){New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force|Out-Null;[IO.File]::WriteAllText($Path,$Text.Replace([string][char]13,'').TrimEnd()+$script:lf,$script:utf8)}
function Write-Json([string]$Path,$Value){Write-Text $Path ($Value|ConvertTo-Json -Depth 100)}
function Id([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return 'MISSING'};$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Copy-Exact([string]$Source,[string]$Destination){New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force|Out-Null;Copy-Item -LiteralPath $Source -Destination $Destination -Force}
function Run([string]$Tool,[hashtable]$Arguments,[switch]$Reject){
    $output=@(& $Tool @Arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
    if($Reject){return [pscustomobject]@{code=$code;text=$output-join$script:lf}}
    if($code-ne0){throw ('TOOL_FAIL|'+[IO.Path]::GetFileName($Tool)+'|'+($output-join$script:lf))}
    return $output
}
function Json([string]$Tool,[hashtable]$Arguments){$out=@(Run $Tool $Arguments);return ($out-join$script:lf)|ConvertFrom-Json -Depth 100}
function Freeze([string]$Root){
    [string[]]$names=@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')})
    [Array]::Sort($names,[StringComparer]::Ordinal);$files=@();[long]$bytes=0;$rows=@()
    foreach($name in $names){$i=(Id (Join-Path $Root $name)).Split('|');$bytes+=[long]$i[0];$files+=[pscustomobject]@{path=$name;bytes=[long]$i[0];sha256=$i[1]};$rows+=$name+'|'+$i[0]+'|'+$i[1]}
    $manifest=Get-Content -LiteralPath (Join-Path $Root 'framework/versions/1.16.0/RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json
    return [ordered]@{fileCount=$files.Count;totalBytes=$bytes;canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:utf8.GetBytes([string]::Join($script:lf,$rows))));files=$files;sourcePayloadCanonical=$manifest.canonical}
}
function Package([string[]]$Paths,[string]$Root,[int]$Schema=2){
    return [ordered]@{
        schemaVersion=$Schema;frameworkVersion='1.16.0';taskId='SELF-UPDATE-001';profile='CRITICAL';lifecycle='ACTIVE'
        owner=$script:owner;issuer=$script:owner;issuerRole='PROJECT_CONTROLLER';grantee=$script:owner;bundle='SELF_UPDATE_FIXTURE'
        decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false
        taskIdentity=Id $script:task;actions=@('SOURCE_WRITE');exactPaths=$Paths
        objectIdentities=@($Paths|ForEach-Object{$observed=Id (Join-Path $Root $_);[ordered]@{path=$_;identity=$(if($observed-ceq'MISSING'){'NEW'}else{$observed})}})
        invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE','REPOSITORY_CHANGE')
        projectConfigIdentity=Id (Join-Path $script:control '.ai-workspace/project.json');issuerControllerId=$script:owner;issuerControllerEpoch=$script:epoch;controllerControlIdentity=Id (Join-Path $script:control '.ai-workspace/controller.json');repositoryId='ai-workspace-framework'
    }
}
function Admission([string]$Name,[string[]]$Paths){
    $auth=Join-Path $script:runtime ($Name+'-auth.json');Write-Json $auth (Package $Paths $script:target)
    $input=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$script:control;frameworkRoot=$script:target;taskPath=$script:task
        expectedProjectConfigIdentity=Id (Join-Path $script:control '.ai-workspace/project.json');expectedCorrectionsIdentity=Id (Join-Path $script:control '.ai-workspace/corrections.json');expectedTaskIdentity=Id $script:task
        observedActor=$script:owner;capabilities=@();exactPaths=$Paths;forbiddenPaths=@('tools/','private/');protectedPaths=@('framework/','scripts/');authorizationPackagePath=$auth;expectedAuthorizationIdentity=Id $auth
        userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT'
        intentEnvelope=[ordered]@{schemaVersion=1;objective='Apply the exact accepted Framework source in an isolated self-update fixture.';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('root source update');pathHints=@();capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
    $ip=Join-Path $script:runtime ($Name+'-discover.json');Write-Json $ip $input
    $d=Json $script:adapter @{InputPath=$ip;AsJson=$true};Confirm ($d.status-ceq'PASS') ($Name+'-discover')
    $rp=Join-Path $script:runtime ($Name+'-receipt.json');Write-Json $rp $d.compactReceipt
    $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$rp;expectedDiscoverReceiptIdentity=Id $rp;preparationReceipts=@($d.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    $bp=Join-Path $script:runtime ($Name+'-admit-input.json');Write-Json $bp $boundary
    $a=Json $script:adapter @{InputPath=$bp;AsJson=$true};Confirm ($a.status-ceq'PASS') ($Name+'-admit')
    $ap=Join-Path $script:runtime ($Name+'-admit-result.json');Write-Json $ap $a
    return [pscustomobject]@{auth=$auth;receipt=$rp;admitInput=$bp;admitResult=$ap;boundary=$boundary;discover=$d}
}
function Restore-SourceFile([string]$Path,[byte[]]$Bytes){[IO.File]::WriteAllBytes($Path,$Bytes)}
function Restore-SeedObject([string]$Root,[string]$Relative,[string]$Expected,[string]$Base64){
    $full=[IO.Path]::GetFullPath((Join-Path $Root $Relative));$prefix=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))+[IO.Path]::DirectorySeparatorChar
    if([IO.Path]::IsPathRooted($Relative)-or-not$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)-or$Relative.Replace('\','/').StartsWith('.git/')){throw 'SEED_OBJECT_SCOPE'}
    if($Expected-ceq'MISSING'){
        if(Test-Path -LiteralPath $full -PathType Leaf){Remove-Item -LiteralPath $full -Force}
        return
    }
    $bytes=[Convert]::FromBase64String($Base64);$actual=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if($actual-cne$Expected){throw ('SEED_OBJECT_BYTES|'+$Relative)}
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force|Out-Null;[IO.File]::WriteAllBytes($full,$bytes)
}
try {
    if(-not$SeedControlRoot){
        $cursor=[IO.Path]::GetFullPath($RepositoryRoot)
        while($cursor){
            $configPath=Join-Path $cursor '.ai-workspace/project.json'
            if(Test-Path -LiteralPath $configPath){$config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json;if($config.controlPlaneLayout-ceq'framework-maintenance-sibling'){$SeedControlRoot=$cursor;break}}
            $cursor=Split-Path -Parent $cursor
        }
        if(-not$SeedControlRoot){$sibling=Join-Path (Split-Path -Parent $RepositoryRoot) 'AI-Workspace-Maintenance';if(Test-Path -LiteralPath (Join-Path $sibling '.ai-workspace/project.json')){$SeedControlRoot=$sibling}}
    }
    if(-not$SeedControlRoot){throw 'HEALTHY_MAINTENANCE_SEED_REQUIRED'}
    if(-not$SeedFrameworkRoot){$seedConfig=Get-Content -LiteralPath (Join-Path $SeedControlRoot '.ai-workspace/project.json') -Raw|ConvertFrom-Json;$SeedFrameworkRoot=Join-Path (Split-Path -Parent $SeedControlRoot) $seedConfig.frameworkTarget.siblingDirectory}
    $control=Join-Path $fixtureRoot 'AI-Workspace-Maintenance';$target=Join-Path $fixtureRoot 'AI-Workspace'
    New-Item -ItemType Directory -Path $control,$target -Force|Out-Null
    # Relocate a real completed old-pilot seed byte-for-byte, not a handwritten pilot.
    foreach($root in @($control,$target)){& git -C $root init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'};& git -C $root config core.autocrlf false}
    foreach($folder in @('scripts','skills','framework/maintenance-overlay','framework/versions/1.16.0')){
        $dest=Join-Path $target $folder;New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $SeedFrameworkRoot $folder) -Destination $dest -Recurse
    }
    foreach($name in @('AGENTS.md','README.md','LICENSE','INITIALIZATION.md')){Copy-Exact (Join-Path $SeedFrameworkRoot $name) (Join-Path $target $name)}
    foreach($relative in @('AGENTS.md','.gitignore','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','.ai-workspace/PROJECT-CUSTOM.md')){
        if(Test-Path -LiteralPath (Join-Path $SeedControlRoot $relative)){Copy-Exact (Join-Path $SeedControlRoot $relative) (Join-Path $control $relative)}
    }
    $recovery='.ai-workspace/upgrade-recovery/1.16.0'
    New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $control $recovery)) -Force|Out-Null
    Copy-Item -LiteralPath (Join-Path $SeedControlRoot $recovery) -Destination (Join-Path $control $recovery) -Recurse
    if($SeedTransactionPath-or$ExpectedSeedTransactionIdentity){
        if(-not$SeedTransactionPath-or-not$ExpectedSeedTransactionIdentity-or(Id $SeedTransactionPath)-cne$ExpectedSeedTransactionIdentity){throw 'SEED_TRANSACTION_IDENTITY'}
        $seed=Get-Content -LiteralPath $SeedTransactionPath -Raw|ConvertFrom-Json -Depth 100
        if($seed.schemaVersion-ne1-or$seed.transactionType-cne'MAINTENANCE_FRAMEWORK_SOURCE_SELF_UPDATE'-or$seed.status-cne'COMPLETE'-or
            -not[StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($seed.controlRoot),[IO.Path]::GetFullPath($SeedControlRoot))-or
            -not[StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($seed.targetRoot),[IO.Path]::GetFullPath($SeedFrameworkRoot))-or
            (Id (Join-Path $control '.ai-workspace/project.json'))-cne$seed.projectConfigIdentity-or(Id (Join-Path $control '.ai-workspace/controller.json'))-cne$seed.controllerIdentity){throw 'SEED_TRANSACTION_BINDING'}
        foreach($dependency in $seed.dependencies){if((Id (Join-Path $target $dependency.path))-cne$dependency.identity){throw ('SEED_DEPENDENCY_DRIFT|'+$dependency.path)}}
        # Restore recorded real preimages only inside this test's already-owned
        # sibling fixture. Never invoke RECOVER against the original live roots.
        foreach($object in $seed.projection.objects){Restore-SeedObject $target $object.path $object.oldIdentity $object.oldBase64}
        $managed=@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','AGENTS.md','.gitignore','.agents/skills/ai-workspace-router/SKILL.md',($recovery+'/state.json'))
        foreach($object in $seed.controlPreimages){if($object.path-cnotin$managed){throw 'SEED_CONTROL_SCOPE'};Restore-SeedObject $control $object.path $object.identity $object.base64}
        Confirm ((Id (Join-Path $control ($recovery+'/state.json')))-ceq(@($seed.controlPreimages|Where-Object {$_.path-ceq($recovery+'/state.json')})[0].identity)) 'historical-completed-seed-restored-from-real-preimages'
    }
    $controller=Get-Content -LiteralPath (Join-Path $control '.ai-workspace/controller.json') -Raw|ConvertFrom-Json
    $owner=[string]$controller.controllerId;$epoch=[int]$controller.controllerEpoch
    $taskRelative='.ai-workspace/tasks/active/SELF-UPDATE-001.md';$task=Join-Path $control $taskRelative
    Write-Text $task (@('# SELF-UPDATE-001 — isolated real-entry self update','','- Task schema: 1.16.0','- Profile: CRITICAL',('- Owner: '+$owner),('- Work route: actor='+$owner+'; role=FRAMEWORK_MAINTAINER; phase=IMPLEMENT'),'- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=SCOPED_PACKAGE; expected_paths=[]; actual_paths=[]','- Proportionality: NOT_APPLICABLE; reason=bounded fixture','- Phase gate: FALSE','')-join$lf)
    $runtime=Join-Path $control ('.ai-workspace/runtime/SELF-UPDATE-001/'+$owner);New-Item -ItemType Directory -Path $runtime -Force|Out-Null
    Write-Text (Join-Path $target 'tools/resource-evaluation/independent.txt') 'unrelated tool bytes'
    Write-Text (Join-Path $target 'private/protected.txt') 'protected unrelated bytes'
    & git -C $target -c user.name=Fixture -c user.email=fixture@example.invalid add README.md
    & git -C $target -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm seed
    if($LASTEXITCODE-ne0){throw 'FIXTURE_PARENT'}
    $parent=(& git -C $target rev-parse HEAD).Trim()
    $adapter=Join-Path $target 'scripts/resolve-framework-maintenance-process-requirements.ps1'
    $installPaths=@('scripts/integrate-framework-source.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1','scripts/upgrade-project.ps1')
    $install=Admission 'root-install' $installPaths
    foreach($path in $installPaths){Copy-Exact (Join-Path $RepositoryRoot $path) (Join-Path $target $path)}
    $final=$install.boundary;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@($install.discover.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)+@($installPaths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+(Id (Join-Path $target $_))})
    $finalPath=Join-Path $runtime 'install-final.json';Write-Json $finalPath $final
    Confirm ((Json $adapter @{InputPath=$finalPath;AsJson=$true}).status-ceq'PASS') 'first-root-install-original-ordinary-finalize'
    $integrator=Join-Path $target 'scripts/integrate-framework-source.ps1'
    $freeze=Freeze $RepositoryRoot;$freezePath=Join-Path $runtime 'accepted-freeze.json';Write-Json $freezePath $freeze
    # Test-issued acceptance only; no executable result is fabricated.
    $evidencePath=Join-Path $runtime 'fixture-acceptance.json';Write-Json $evidencePath ([ordered]@{fixtureOnly=$true;status='OWNER_ACCEPTED_PENDING_RELEASE_INTEGRATION';focusedRereview=@{status='APPROVED'};ownerAcceptance=@{status='PASS'};sourcePayload=@{canonical=$freeze.sourcePayloadCanonical}})
    $paths=@($freeze.files|Where-Object{(Id (Join-Path $target $_.path))-cne($_.bytes.ToString()+'|'+$_.sha256)}|ForEach-Object{$_.path})
    $source=Admission 'source' $paths
    $common=@{ControlRepositoryPath=$control;CandidateRoot=$RepositoryRoot;AuthorizationPackagePath=$source.auth;ExpectedAuthorizationPackageIdentity=Id $source.auth;DiscoverReceiptPath=$source.receipt;ExpectedDiscoverReceiptIdentity=Id $source.receipt;AdmitInputPath=$source.admitInput;ExpectedAdmitInputIdentity=Id $source.admitInput;AdmitResultPath=$source.admitResult;ExpectedAdmitResultIdentity=Id $source.admitResult;AcceptedFreezePath=$freezePath;ExpectedAcceptedFreezeIdentity=Id $freezePath;AcceptedEvidencePath=$evidencePath;ExpectedAcceptedEvidenceIdentity=Id $evidencePath;ExpectedParent=$parent;AsJson=$true}
    # R1: construct a genuine schema3 TARGET receipt through the unchanged version
    # DISCOVER only, then prove the supported root route refuses it before mutation.
    $routeInput=Get-Content -LiteralPath (Join-Path $runtime 'source-discover.json') -Raw|ConvertFrom-Json -AsHashtable
    $routeInput.schemaVersion=3;$routeInput['contextType']='TASK';$routeInput['readOnlyContext']='NOT_APPLICABLE'
    $routeInputPath=Join-Path $runtime 'r1-target-discover.json';Write-Json $routeInputPath $routeInput
    $managedPaths=@($paths|ForEach-Object{Join-Path $target $_})+@(@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','AGENTS.md','.gitignore','.agents/skills/ai-workspace-router/SKILL.md',($recovery+'/state.json'),'.ai-workspace/project.json','.ai-workspace/controller.json','.ai-workspace/corrections.json',$taskRelative)|ForEach-Object{Join-Path $control $_})
    $managedBefore=@($managedPaths|ForEach-Object{Id $_})-join$lf
    $unsupported='MAINTENANCE_TARGET_RECEIPT_SCHEMA_UNSUPPORTED|USE_SCHEMA2_DISCOVER_SCHEMA1_COMPACT'
    foreach($cleanup in @($false,$true)){
        $beforeInput=Id $routeInputPath
        $rejected=Run $adapter @{InputPath=$routeInputPath;AsJson=$true;DeleteInputOnExit=$cleanup} -Reject
        Confirm ($rejected.code-ne0-and(($rejected.text|ConvertFrom-Json).reason-ceq$unsupported)-and(Id $routeInputPath)-ceq$beforeInput) ('r1-target-discover-refuses-and-preserves-input-cleanup-'+$cleanup)
    }
    $versionResolver=Join-Path $target 'framework/versions/1.16.0/scripts/resolve-process-requirements.ps1'
    $targetDiscover=Json $versionResolver @{InputPath=$routeInputPath;AuthorizationCheckerPath=(Join-Path $target 'scripts/check-framework-maintenance-authorization.ps1');AsJson=$true}
    Confirm ($targetDiscover.status-ceq'PASS'-and$targetDiscover.compactReceipt.schemaVersion-eq2-and[IO.Path]::GetFullPath($targetDiscover.compactReceipt.binding.projectRoot)-ceq[IO.Path]::GetFullPath($target)) 'r1-genuine-target-compact-from-version-discover'
    $routeReceiptPath=Join-Path $runtime 'r1-target-receipt.json';Write-Json $routeReceiptPath $targetDiscover.compactReceipt
    $routeReceiptIdentity=Id $routeReceiptPath
    $routeBoundary=($source.boundary|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable
    $routeBoundary.discoverReceiptPath=$routeReceiptPath;$routeBoundary.expectedDiscoverReceiptIdentity=$routeReceiptIdentity
    $routeBoundaryPath=Join-Path $runtime 'r1-target-boundary.json'
    foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
        $routeBoundary.mode=$mode;Write-Json $routeBoundaryPath $routeBoundary
        foreach($cleanup in @($false,$true)){
            $beforeInput=Id $routeBoundaryPath
            $rejected=Run $adapter @{InputPath=$routeBoundaryPath;AsJson=$true;DeleteInputOnExit=$cleanup} -Reject
            Confirm ($rejected.code-ne0-and(($rejected.text|ConvertFrom-Json).reason-ceq$unsupported)-and(Id $routeBoundaryPath)-ceq$beforeInput-and(Id $routeReceiptPath)-ceq$routeReceiptIdentity) ('r1-target-'+$mode+'-refuses-without-rewrite-or-cleanup-'+$cleanup)
        }
    }
    $unsupportedArgs=$common.Clone();$unsupportedArgs.Operation='PREVIEW';$unsupportedArgs.TransactionPath=Join-Path $runtime 'r1-unsupported-transaction.json'
    $unsupportedArgs.DiscoverReceiptPath=$routeReceiptPath;$unsupportedArgs.ExpectedDiscoverReceiptIdentity=$routeReceiptIdentity
    $rejected=Run $integrator $unsupportedArgs -Reject
    Confirm ($rejected.code-ne0-and(($rejected.text|ConvertFrom-Json).reason-ceq$unsupported)-and-not(Test-Path -LiteralPath $unsupportedArgs.TransactionPath)) 'r1-integrator-rejects-unsupported-receipt-before-transaction'
    Confirm ((@($managedPaths|ForEach-Object{Id $_})-join$lf)-ceq$managedBefore) 'r1-unsupported-route-preserves-all-source-and-control-managed-objects'
    # CONTROL's process input schema3 remains supported; this package is schema2.
    # The independent schema3 upgrade package is exercised by the real refresh below.
    $controlPackage=Package @('AGENTS.md') $control
    $controlPackage.repositoryId='CONTROL';$controlPackage.actions=@('CONTROL_WRITE')
    foreach($authLocation in @('runtime','control-plane')){
    $controlAuth=if($authLocation-ceq'runtime'){Join-Path $runtime 'r1-control-auth.json'}else{Join-Path $control '.ai-workspace/control-auth.json'}
    Write-Json $controlAuth $controlPackage
    $controlInput=($routeInput|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable
    $controlInput.authorizationPackagePath=$controlAuth;$controlInput.expectedAuthorizationIdentity=Id $controlAuth;$controlInput.exactPaths=@('AGENTS.md')
    $controlInput.intentEnvelope.objective='Verify the existing CONTROL schema3 process route without changing the managed object.'
    $controlInput.intentEnvelope.requestedActionKind='CONTROL_WRITE';$controlInput.intentEnvelope.mutationHints=@('control')
    $controlInputPath=Join-Path $runtime 'r1-control-discover.json';Write-Json $controlInputPath $controlInput
    $controlDiscover=Json $adapter @{InputPath=$controlInputPath;AsJson=$true;DeleteInputOnExit=$true}
    Confirm ($controlDiscover.status-ceq'PASS'-and$controlDiscover.compactReceipt.schemaVersion-eq2-and[IO.Path]::GetFullPath($controlDiscover.compactReceipt.binding.projectRoot)-ceq[IO.Path]::GetFullPath($control)-and-not(Test-Path -LiteralPath $controlInputPath)) 'r1-control-schema3-discover-and-normal-cleanup'
    $controlReceiptPath=Join-Path $runtime 'r1-control-receipt.json';Write-Json $controlReceiptPath $controlDiscover.compactReceipt
    $controlBoundary=($source.boundary|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable
    $controlBoundary.discoverReceiptPath=$controlReceiptPath;$controlBoundary.expectedDiscoverReceiptIdentity=Id $controlReceiptPath
    $controlBoundary.preparationReceipts=@($controlDiscover.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $controlBoundaryPath=Join-Path $runtime 'r1-control-boundary.json'
    foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
        $controlBoundary.mode=$mode
        if($mode-ceq'FINALIZE_OUTPUT'){$controlBoundary.resultReceipts=@($controlDiscover.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|AGENTS.md|'+(Id (Join-Path $control 'AGENTS.md')))}
        Write-Json $controlBoundaryPath $controlBoundary
        $controlResult=Json $adapter @{InputPath=$controlBoundaryPath;AsJson=$true;DeleteInputOnExit=$true}
        Confirm ($controlResult.status-ceq'PASS'-and-not(Test-Path -LiteralPath $controlBoundaryPath)) ('control-schema3-'+$authLocation+'-'+$mode+'-and-normal-cleanup')
    }
    }
    $controlBoundary.mode='ADMIT_ACTION';$controlBoundary.resultReceipts=@()
    $controlReceiptBytes=[IO.File]::ReadAllBytes($controlReceiptPath)
    $controlAuthBytes=[IO.File]::ReadAllBytes($controlAuth)
    foreach($fault in @('receipt-identity','authorization-identity','wrong-bound-root','wrong-framework-root')){
        $probeBoundary=($controlBoundary|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable
        if($fault-ceq'receipt-identity'){$probeBoundary.expectedDiscoverReceiptIdentity='0|'+('0'*64)}
        elseif($fault-ceq'authorization-identity'){Write-Text $controlAuth ($lf+[IO.File]::ReadAllText($controlAuth))}
        else {
            $badReceipt=Get-Content -LiteralPath $controlReceiptPath -Raw|ConvertFrom-Json
            if($fault-ceq'wrong-bound-root'){$badReceipt.binding.projectRoot=$fixtureRoot}else{$badReceipt.sourceLocators.frameworkRoot=$control}
            Write-Json $controlReceiptPath $badReceipt;$probeBoundary.expectedDiscoverReceiptIdentity=Id $controlReceiptPath
        }
        Write-Json $controlBoundaryPath $probeBoundary
        $rejected=Run $adapter @{InputPath=$controlBoundaryPath;AsJson=$true} -Reject
        Confirm ($rejected.code-ne0-and(Test-Path -LiteralPath $controlBoundaryPath)) ('control-compact-rejects-'+$fault)
        Restore-SourceFile $controlReceiptPath $controlReceiptBytes;Restore-SourceFile $controlAuth $controlAuthBytes
    }
    $badAdmission=[IO.File]::ReadAllBytes($source.admitResult);$fake=Get-Content -LiteralPath $source.admitResult -Raw|ConvertFrom-Json;$fake.decisionIdentity='F'*64;Write-Json $source.admitResult $fake
    $probe=$common.Clone();$probe.Operation='PREVIEW';$probe.TransactionPath=Join-Path $runtime 'rejected-admission.json';$probe.ExpectedAdmitResultIdentity=Id $source.admitResult
    $rejectedAdmission=Run $integrator $probe -Reject
    Confirm ($rejectedAdmission.code-ne0-and$rejectedAdmission.text.Contains('REAL_ADMISSION_MISMATCH')) 'forged-original-admit-result-rejected-by-real-replay'
    Restore-SourceFile $source.admitResult $badAdmission
    $sentinel=Id (Join-Path $target 'tools/resource-evaluation/independent.txt');$protected=Id (Join-Path $target 'private/protected.txt')
    $oldState=Id (Join-Path $control ($recovery+'/state.json'))
    # Current completed seed exercises genuine no-write recovery; the optional
    # byte-bound historical seed keeps the real schema3 write/rollback regression.
    $scenarios=if($SeedTransactionPath){@('interrupt-target','failure-target','reject-refresh-schema','interrupt-refresh','normal')}else{@('interrupt-target','failure-target','noop-drift','interrupt-refresh','normal')}
    foreach($scenario in $scenarios){
        $transaction=Join-Path $runtime ($scenario+'-transaction.json');$args=$common.Clone();$args.TransactionPath=$transaction;$args.Operation='PREVIEW'
        Confirm ((Json $integrator $args).status-ceq'PREVIEW') ($scenario+'-real-preview')
        $args.Operation='APPLY'
        if($scenario-ceq'interrupt-target'){$args.InterruptAfterWrite=1}
        if($scenario-ceq'failure-target'){$args.FailAfterWrite=1}
        if($scenario-ceq'failure-target'){
            $failed=Run $integrator $args -Reject;Confirm ($failed.code-ne0-and$failed.text.Contains('SELF_UPDATE_APPLY_ROLLED_BACK')) 'write-failure-rolls-back'
            Confirm ((Id (Join-Path $control ($recovery+'/state.json')))-ceq$oldState) 'failure-preserves-maintenance'
            continue
        }
        $applied=Json $integrator $args
        if($scenario-ceq'interrupt-target'){
            Confirm ($applied.status-ceq'INTERRUPTED') 'interrupted-process-left-real-partial-writes'
            $originalTransaction=[IO.File]::ReadAllBytes($transaction);$wrongRoot=Get-Content -LiteralPath $transaction -Raw|ConvertFrom-Json;$wrongRoot.controlRoot=Join-Path $fixtureRoot 'UnrelatedControl';Write-Json $transaction $wrongRoot
            $rootRejected=Run $integrator @{Operation='RECOVER';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true} -Reject
            Confirm ($rootRejected.code-ne0-and$rootRejected.text.Contains('SELF_UPDATE_CONTROL_ROOT_DRIFT')) 'transaction-cannot-redirect-recovery-to-another-control-root'
            Restore-SourceFile $transaction $originalTransaction
            $badPath=Join-Path $target $paths[0];$bytes=[IO.File]::ReadAllBytes($badPath);Write-Text $badPath 'third party'
            $rejected=Run $integrator @{Operation='RECOVER';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true} -Reject
            Confirm ($rejected.code-ne0-and$rejected.text.Contains('THIRD_PARTY_TARGET')-and[IO.File]::ReadAllText($badPath).Contains('third party')) 'third-party-target-recovery-refused'
            Restore-SourceFile $badPath $bytes
            $restored=Json $integrator @{Operation='RECOVER';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true}
            Confirm ($restored.status-ceq'ROLLED_BACK'-and$restored.healthyOriginalAdmission) 'interrupted-target-restores-valid-original-admission'
            continue
        }
        $refreshArgs=@{ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true}
        $refreshArgs.Operation='REFRESH_PREVIEW';$preview=Json $integrator $refreshArgs
        $pre=@{};$post=@{};$writeSet=@();$canonical='';$manifest=''
        foreach($line in $preview.output){
            if($line-match'^UPGRADE_PREIMAGE\|(?<path>.+)=(?<id>NEW|\d+\|[A-F0-9]{64})$'){$pre[$Matches.path]=$Matches.id}
            elseif($line-match'^UPGRADE_POSTIMAGE\|(?<path>.+)=(?<id>ABSENT|\d+\|[A-F0-9]{64})$'){$post[$Matches.path]=$Matches.id}
            elseif($line-match'^UPGRADE_WRITESET\|(?<paths>.+)$'){$writeSet=@($Matches.paths-split'\|')}
            elseif($line-match'^UPGRADE_TARGET_RELEASE\|canonical=(?<hash>[A-F0-9]{64})\|manifest=(?<id>\d+\|[A-F0-9]{64})$'){$canonical=$Matches.hash;$manifest=$Matches.id}
        }
        $noWrite=-not[bool]$SeedTransactionPath
        if($noWrite){
            Confirm ($applied.writes-gt0-and$writeSet.Count-eq0-and$preview.output.Count-eq2-and$preview.output[0]-ceq'UPGRADE_RECOVERY_WRITESET|'-and$preview.output[1]-ceq'RECOVERY_COMPLETE|to=1.16.0|writes=ZERO|state=LOCAL_CANDIDATE_MANAGED_PROJECTION') ($scenario+'-real-source-write-and-synchronized-upgrader-preview')
            $beforeRefresh=Get-Content -LiteralPath $transaction -Raw|ConvertFrom-Json -Depth 100
            $transactionBefore=Id $transaction
            $refreshArgs.Operation='REFRESH'
            if($scenario-ceq'noop-drift'){
                $driftPaths=@($task,(Join-Path $control '.ai-workspace/project.json'),(Join-Path $control '.ai-workspace/controller.json'),(Join-Path $control 'AGENTS.md'),(Join-Path $control ($recovery+'/state.json')),(Join-Path $target $paths[0]),(Join-Path $target 'scripts/ProjectAdoptionState.psm1'))
                # Corrupt a real recovery material dependency, not just state.json.
                $material=Get-ChildItem -LiteralPath (Join-Path $control ($recovery+'/new')) -File -Recurse|Select-Object -First 1
                $driftPaths+=$material.FullName
                foreach($driftPath in $driftPaths){
                    $saved=[IO.File]::ReadAllBytes($driftPath);Write-Text $driftPath ([Text.Encoding]::UTF8.GetString($saved)+$lf+'# third-party drift')
                    $rejected=Run $integrator $refreshArgs -Reject
                    Confirm ($rejected.code-ne0-and(Id $transaction)-ceq$transactionBefore-and[IO.File]::ReadAllText($driftPath).Contains('third-party drift')) ('no-write-refresh-refuses-live-drift-'+[IO.Path]::GetRelativePath($fixtureRoot,$driftPath))
                    Restore-SourceFile $driftPath $saved
                }
                $stale=$refreshArgs.Clone();$stale.ExpectedTransactionIdentity='1|'+('A'*64)
                $rejected=Run $integrator $stale -Reject
                Confirm ($rejected.code-ne0-and$rejected.text.Contains('TRANSACTION_DRIFT')) 'no-write-refuses-stale-transaction'
            }
            if($scenario-ceq'interrupt-refresh'){$refreshArgs.InterruptAfterRefresh=$true}
            $ready=Json $integrator $refreshArgs
            $noWriteState=Get-Content -LiteralPath $transaction -Raw|ConvertFrom-Json -Depth 100
            Confirm ($noWriteState.refresh.kind-ceq'VERIFIED_NO_WRITE'-and$noWriteState.refresh.packagePath-ceq'NOT_REQUIRED'-and$noWriteState.refresh.postimages.Count-eq$beforeRefresh.controlPreimages.Count-and@($beforeRefresh.controlPreimages|Where-Object{(Id (Join-Path $control $_.path))-cne$_.identity}).Count-eq0) ($scenario+'-no-write-preserves-all-managed-bytes-without-schema3-package')
            if($scenario-ceq'noop-drift'){
                $transactionBytes=[IO.File]::ReadAllBytes($transaction)
                foreach($fault in @('unknown-output','false-output','postimages','actor','kind','package')){
                    $fake=[Text.Encoding]::UTF8.GetString($transactionBytes)|ConvertFrom-Json -Depth 100
                    switch($fault){
                        'unknown-output' {$fake.refresh.output+=@('UNKNOWN|success')}
                        'false-output' {$fake.refresh.output=@('UPGRADE_RECOVERY_WRITESET|','RECOVERY_COMPLETE|to=1.16.0|writes=ZERO')}
                        'postimages' {$fake.refresh.postimages=@($fake.refresh.postimages|Select-Object -Skip 1)}
                        'actor' {$fake.actor='unrelated-actor'}
                        'kind' {$fake.refresh.kind='CALLER_SUCCESS'}
                        'package' {$fake.refresh.packageIdentity='1|'+('F'*64)}
                    }
                    Write-Json $transaction $fake
                    $rejected=Run $integrator @{Operation='VERIFY_REFRESH';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true} -Reject
                    Confirm ($rejected.code-ne0) ('no-write-finalize-refuses-'+$fault)
                    Restore-SourceFile $transaction $transactionBytes
                }
                $materialBytes=[IO.File]::ReadAllBytes($material.FullName);Write-Text $material.FullName 'late recovery material drift'
                $rejected=Run $integrator @{Operation='VERIFY_REFRESH';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true} -Reject
                Confirm ($rejected.code-ne0-and$rejected.text.Contains('RECOVERY_MATERIAL')) 'no-write-finalize-rechecks-real-upgrader-material'
                Restore-SourceFile $material.FullName $materialBytes
                $restored=Json $integrator @{Operation='RECOVER';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true}
                Confirm ($restored.status-ceq'ROLLED_BACK'-and$restored.healthyOriginalAdmission) 'no-write-ready-can-rollback-source-and-keep-healthy-control'
                continue
            }
        }else{
        Confirm ($writeSet.Count-gt0-and$post.Count-eq$writeSet.Count) ($scenario+'-real-upgrader-preview')
        $withoutPackage=$refreshArgs.Clone();$withoutPackage.Operation='REFRESH'
        $missingPackage=Run $integrator $withoutPackage -Reject
        Confirm ($missingPackage.code-ne0-and$missingPackage.text.Contains('NOT_VERIFIED_NO_WRITE')-and(Id $transaction)-ceq$refreshArgs.ExpectedTransactionIdentity) 'write-required-refresh-cannot-take-no-write-path'
        $pkg=Package $writeSet $control 3;$pkg.Remove('repositoryId');$pkg.bundle='ACTOR_BOUND_PROJECT_UPGRADE';$pkg.actions=@('CONTROL_WRITE');$pkg.decisionClass='MAJOR_ARCHITECTURE';$pkg.userConfirmation='USER_FIXTURE_APPROVED_SELF_UPDATE_REFRESH';$pkg.invalidatesOn+=@('POST_OBJECT_DRIFT')
        if($scenario-ceq'reject-refresh-schema'){$pkg['repositoryId']='CONTROL'}
        $pkg['postObjectIdentities']=@($writeSet|ForEach-Object{[ordered]@{path=$_;identity=$post[$_]}})
        $pkg['targetFrameworkSnapshot']=[ordered]@{canonical=$canonical;manifestIdentity=$manifest}
        $refreshPackage=Join-Path $runtime ($scenario+'-refresh-auth.json');Write-Json $refreshPackage $pkg
        $refreshArgs.Operation='REFRESH';$refreshArgs.MaintenanceRefreshPackagePath=$refreshPackage;$refreshArgs.ExpectedMaintenanceRefreshPackageIdentity=Id $refreshPackage
        if($scenario-ceq'interrupt-refresh'){$refreshArgs.InterruptAfterRefresh=$true}
        if($scenario-ceq'reject-refresh-schema'){
            $rejected=Run $integrator $refreshArgs -Reject
            Confirm ($rejected.code-ne0-and$rejected.text.Contains('PACKAGE_FIELD_SET')-and$rejected.text.Contains('REFRESH_ROLLED_BACK')) 'schema3-extra-field-refused-by-real-checker-and-source-rolled-back'
            Confirm ((Id (Join-Path $control ($recovery+'/state.json')))-ceq$oldState) 'rejected-refresh-preserves-old-maintenance-state'
            continue
        }
        $ready=Json $integrator $refreshArgs
        }
        if($scenario-ceq'interrupt-refresh'){
            $stateChanged=(Id (Join-Path $control ($recovery+'/state.json')))-cne$oldState
            Confirm ($ready.status-ceq'INTERRUPTED'-and$stateChanged-eq(-not$noWrite)) 'real-refresh-completed-before-interruption-with-expected-write-boundary'
            $controlPath=Join-Path $control 'AGENTS.md';$saved=[IO.File]::ReadAllBytes($controlPath);Write-Text $controlPath 'third-party control'
            $rej=Run $integrator @{Operation='RECOVER';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true} -Reject
            Confirm ($rej.code-ne0-and$rej.text.Contains('THIRD_PARTY_CONTROL')) 'third-party-control-prevents-combination-rollback'
            Restore-SourceFile $controlPath $saved
            $recovered=Json $integrator @{Operation='RECOVER';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;AsJson=$true}
            Confirm ($recovered.status-ceq'ROLLED_BACK'-and$recovered.healthyOriginalAdmission-and(Id (Join-Path $control ($recovery+'/state.json')))-ceq$oldState) 'refresh-interruption-restores-old-healthy-combination'
            continue
        }
        $badComplete=Run $integrator @{Operation='COMPLETE';ControlRepositoryPath=$control;TransactionPath=$transaction;ExpectedTransactionIdentity=Id $transaction;FinalizeDecisionIdentity=('C'*64);AsJson=$true} -Reject
        Confirm ($badComplete.code-ne0-and$badComplete.text.Contains('CALLER_DECISION_NOT_ACCEPTED')) 'fake-finalize-hash-refused'
        $final=$source.boundary;$final.mode='FINALIZE_OUTPUT';$final.preparationReceipts=@($ready.preparationRequirements);$final.resultReceipts=@($ready.resultRequirements)+@($paths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+(Id (Join-Path $target $_))})+@('MAINTENANCE_SELF_UPDATE_TRANSITION|'+$transaction+'|'+(Id $transaction))
        $finalPath=Join-Path $runtime 'source-final.json';Write-Json $finalPath $final
        $fullReceipts=@($final.resultReceipts);$required=$ready.resultRequirements[0];$final.resultReceipts=@($fullReceipts|Where-Object{$_-cne$required});Write-Json $finalPath $final
        $missing=Run $adapter @{InputPath=$finalPath;AsJson=$true} -Reject;Confirm ($missing.code-ne0-and$missing.text.Contains('CURRENT_OBLIGATIONS_MISSING')) 'current-and-original-obligations-required-before-complete'
        $final.resultReceipts=@($fullReceipts|Where-Object{$_-cnotlike('OBJECT_POSTIMAGE|'+$paths[0]+'|*')});Write-Json $finalPath $final
        $missingPost=Run $adapter @{InputPath=$finalPath;AsJson=$true} -Reject;Confirm ($missingPost.code-ne0-and$missingPost.text.Contains('FINALIZE_POSTIMAGE')) 'missing-exact-postimage-refused'
        $final.resultReceipts=$fullReceipts;Write-Json $finalPath $final
        $wrongInput=Join-Path $control '.ai-workspace/runtime/SELF-UPDATE-001/wrong-actor/final.json';Write-Json $wrongInput $final
        $unsafeCleanup=Run $adapter @{InputPath=$wrongInput;AsJson=$true;DeleteInputOnExit=$true} -Reject
        Confirm ($unsafeCleanup.code-ne0-and$unsafeCleanup.text.Contains('MAINTENANCE_CLEANUP_SCOPE')-and(Test-Path -LiteralPath $wrongInput)) 'cleanup-refuses-another-actor-input-before-finalize'
        $done=Json $adapter @{InputPath=$finalPath;AsJson=$true;DeleteInputOnExit=$true}
        Confirm (-not(Test-Path -LiteralPath $finalPath)) 'valid-finalize-input-cleaned-exactly'
        Confirm ($done.status-ceq'PASS'-and$done.originalDiscoverIdentity-ceq(Id $source.receipt)-and$done.currentSourceCompositionIdentity-match'^[A-F0-9]{64}$') 'original-source-write-finalizes-through-current-composer'
        $state=Get-Content -LiteralPath $transaction -Raw|ConvertFrom-Json;Confirm ($state.status-ceq'COMPLETE') 'complete-only-after-real-finalize'
    }
    Confirm ((Id (Join-Path $target 'tools/resource-evaluation/independent.txt'))-ceq$sentinel-and(Id (Join-Path $target 'private/protected.txt'))-ceq$protected) 'unrelated-target-and-protected-files-preserved'
    Write-Output ('PASS|maintenance-self-update|'+$passes+'/'+$passes)
} finally {
    if(Test-Path -LiteralPath $fixtureRoot){
        $full=[IO.Path]::GetFullPath($fixtureRoot);$temp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
        if(-not$full.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-maintenance-self-update-',[StringComparison]::Ordinal)){throw 'FIXTURE_CLEANUP_BOUNDARY'}
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
