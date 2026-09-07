#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepositoryRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$SeedControlRoot,
    [string]$SeedFrameworkRoot
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
    $controlAuth=Join-Path $runtime 'r1-control-auth.json';Write-Json $controlAuth $controlPackage
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
        Confirm ($controlResult.status-ceq'PASS'-and-not(Test-Path -LiteralPath $controlBoundaryPath)) ('r1-control-schema3-'+$mode+'-and-normal-cleanup')
    }
    $badAdmission=[IO.File]::ReadAllBytes($source.admitResult);$fake=Get-Content -LiteralPath $source.admitResult -Raw|ConvertFrom-Json;$fake.decisionIdentity='F'*64;Write-Json $source.admitResult $fake
    $probe=$common.Clone();$probe.Operation='PREVIEW';$probe.TransactionPath=Join-Path $runtime 'rejected-admission.json';$probe.ExpectedAdmitResultIdentity=Id $source.admitResult
    $rejectedAdmission=Run $integrator $probe -Reject
    Confirm ($rejectedAdmission.code-ne0-and$rejectedAdmission.text.Contains('REAL_ADMISSION_MISMATCH')) 'forged-original-admit-result-rejected-by-real-replay'
    Restore-SourceFile $source.admitResult $badAdmission
    $sentinel=Id (Join-Path $target 'tools/resource-evaluation/independent.txt');$protected=Id (Join-Path $target 'private/protected.txt')
    $oldState=Id (Join-Path $control ($recovery+'/state.json'))
    foreach($scenario in @('interrupt-target','failure-target','reject-refresh-schema','interrupt-refresh','normal')){
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
        Confirm ($writeSet.Count-gt0-and$post.Count-eq$writeSet.Count) ($scenario+'-real-upgrader-preview')
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
        if($scenario-ceq'interrupt-refresh'){
            Confirm ($ready.status-ceq'INTERRUPTED'-and(Id (Join-Path $control ($recovery+'/state.json')))-cne$oldState) 'real-refresh-completed-before-interruption'
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
