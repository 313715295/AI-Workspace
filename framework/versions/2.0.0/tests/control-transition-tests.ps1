[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$script:passed=0;$script:fixtureNumber=0
function Assert-True([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Write-Text([string]$Path,[string]$Value){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))|Out-Null;[IO.File]::WriteAllText($Path,$Value,$utf8)}
function Write-Json([string]$Path,$Value){Write-Text $Path (($Value|ConvertTo-Json -Depth 100 -Compress)+"`n")}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Image([string]$Text){$b=$utf8.GetBytes($Text);return [ordered]@{identity=($b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)));base64=[Convert]::ToBase64String($b)}}
function Json-Text($Value){return ($Value|ConvertTo-Json -Depth 100 -Compress)+"`n"}
function Run-Process([string]$InputPath){$raw=@(& ([Environment]::ProcessPath) -NoProfile -File $script:resolver -InputPath $InputPath -AsJson 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE;return [pscustomobject]@{Code=$code;Text=($raw-join"`n");Value=$(try{($raw-join"`n")|ConvertFrom-Json -Depth 100}catch{$null})}}
function Must-Pass($Run,[string]$Label){if($Run.Code-ne0-or$null-eq$Run.Value-or$Run.Value.status-cne'PASS'){throw ($Label+'|'+$Run.Text)}}
function Transition($Fixture,[string]$Operation,[string]$Recovery='NOT_APPLICABLE'){
    $request=[pscustomobject][ordered]@{operation=$Operation;projectRoot=$Fixture.Project;planPath=$Fixture.PlanPath;expectedPlanIdentity=(Id $Fixture.PlanPath);recoveryMode=$Recovery}
    return & $script:transitionModule.ExportedFunctions['Invoke-AiwControlTransition'] $request
}
function Expect-Rejected([scriptblock]$Action,[string]$Reason,[string]$Name){$caught=$null;try{$null=& $Action}catch{$caught=$_.Exception.Message};Assert-True ($null-ne$caught-and$caught.Contains($Reason)) ($Name+'|'+$caught)}
function Set-Checkpoint([string]$Point){& $script:transitionModule {param($p) $script:ControlTransitionTestCheckpoint={param($name)if($name-ceq$p){throw ('INJECTED_CRASH|'+$p)}}.GetNewClosure()} $Point}
function Clear-Checkpoint{& $script:transitionModule {$script:ControlTransitionTestCheckpoint=$null}}
function Snapshot($Fixture){return @($Fixture.Plan.objects|ForEach-Object{$_.path+'='+(Id (Join-Path $Fixture.Project $_.path))})-join"`n"}
function Write-Finalize($Fixture,[switch]$OmitTarget){
    $ctx=& $script:transitionModule.ExportedFunctions['Read-AiwControlTransitionPlan'] $Fixture.Project $Fixture.PlanPath (Id $Fixture.PlanPath)
    $results=@($Fixture.Results|Where-Object{-not$OmitTarget-or$_-cne'TARGET_RESULT_REQUIRED'})+@($ctx.Paths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+$ctx.Objects[$_].MARKED_TARGET.Identity})
    $input=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$Fixture.Locators.discoverReceipt;expectedDiscoverReceiptIdentity=(Id $Fixture.Locators.discoverReceipt);preparationReceipts=@($Fixture.Prep);resultReceipts=$results;deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Json $Fixture.Locators.finalizeInput $input
}
function New-Fixture([switch]$TaskOnly,[switch]$ControllerOnly,[switch]$AnotherTask,[switch]$CriticalTarget){
    $script:fixtureNumber++;$project=Join-Path $script:temp ('project-'+$script:fixtureNumber)
    [IO.Directory]::CreateDirectory($project)|Out-Null
    & git -C $project init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
    $taskId='TRANSITION-001';$taskRelative='.ai-workspace/tasks/active/TRANSITION-001.md';$taskPath=Join-Path $project $taskRelative
    $controllerRelative='.ai-workspace/controller.json';$controllerPath=Join-Path $project $controllerRelative
    $runtime=Join-Path $project '.ai-workspace/runtime/TRANSITION-001/old-actor';[IO.Directory]::CreateDirectory($runtime)|Out-Null
    $loc=[ordered]@{};foreach($name in @('package','discoverInput','discoverReceipt','admitInput','admitResult','finalizeInput','completionProof')){$loc[$name]=Join-Path $runtime ($name+'.json')}
    $projectId='transition-fixture-'+$script:fixtureNumber
    Write-Json (Join-Path $project '.ai-workspace/project.json') ([ordered]@{schemaVersion=5;id=$projectId;displayName='Transition fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
    $beforeController=Json-Text ([ordered]@{schemaVersion=1;projectId=$projectId;controllerId='old-actor';controllerEpoch=1;state='CURRENT'})
    $afterController=Json-Text ([ordered]@{schemaVersion=1;projectId=$projectId;controllerId='new-actor';controllerEpoch=2;state='CURRENT'})
    Write-Text $controllerPath $beforeController
    $beforeTask="# TRANSITION-001 — control transition fixture`n`n- Task schema: 2.0.0`n- Profile: STANDARD; reason=fixture`n- Owner: old-actor`n- Work route: actor=old-actor; role=CONTROLLER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; current_exact=FIXTURE; expected_paths=[]; actual_paths=[]`n"
    $afterTask=$beforeTask.Replace('Owner: old-actor','Owner: new-actor').Replace('actor=old-actor; role=CONTROLLER; phase=PLAN','actor=new-actor; role=TASK_OWNER; phase=IMPLEMENT')
    if($CriticalTarget){$afterTask=$afterTask.Replace('Profile: STANDARD','Profile: CRITICAL').Replace('profile=STANDARD','profile=CRITICAL')}
    Write-Text $taskPath $beforeTask
    Write-Text (Join-Path $project '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
    Write-Json (Join-Path $project '.ai-workspace/corrections.json') ([ordered]@{schemaVersion=2;contractVersion='2.0.0';projectId=$projectId;corrections=@()})
    $targetRule=[ordered]@{ruleId='TRANSITION_TARGET_GATE';requirementReason='New responsibility must consume its own requirements.';effectiveRule='Prepare and verify the target handoff obligation.';selectors=[ordered]@{profiles=@('STANDARD','CRITICAL');roles=@('TASK_OWNER');phases=@('IMPLEMENT');actionKinds=@('CONTROL_WRITE');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@('TARGET_PREP_REQUIRED');resultRequirements=@('TARGET_RESULT_REQUIRED');decisionLocator='fixture:target-obligation'}
    Write-Json (Join-Path $project '.ai-workspace/process-policy.json') ([ordered]@{schemaVersion=1;contractVersion='2.0.0';projectId=$projectId;selectedRulePackBytes=32768;rules=@($targetRule)})
    $objects=@();$changes=@()
    if(-not$TaskOnly){$objects+=[ordered]@{path=$controllerRelative;before=(Image $beforeController);after=(Image $afterController)};$changes+=[ordered]@{path=$controllerRelative;fields=@('ControllerId','ControllerEpoch')}}
    if(-not$ControllerOnly){
        $changedTaskRelative=$taskRelative
        if($AnotherTask){$changedTaskRelative='.ai-workspace/tasks/active/ANOTHER-001.md';$beforeTask=$beforeTask.Replace('TRANSITION-001','ANOTHER-001');$afterTask=$afterTask.Replace('TRANSITION-001','ANOTHER-001');Write-Text (Join-Path $project $changedTaskRelative) $beforeTask}
        $objects+=[ordered]@{path=$changedTaskRelative;before=(Image $beforeTask);after=(Image $afterTask)};$changes+=[ordered]@{path=$changedTaskRelative;fields=@('Owner','Actor','Role','Phase','Profile')}
    }
    $paths=@($objects.path);$controllers=@($paths|Where-Object{$_-ceq$controllerRelative});$tasks=@($paths|Where-Object{$_-cne$controllerRelative});$steps=@()
    foreach($p in @($controllers+$tasks)){$steps+=[ordered]@{path=$p;image='MARKED_BEFORE'}}
    foreach($p in @($tasks+$controllers)){$steps+=[ordered]@{path=$p;image='MARKED_TARGET'}}
    foreach($p in @($tasks+$controllers)){$steps+=[ordered]@{path=$p;image='AFTER'}}
    $plan=[ordered]@{schemaVersion=1;taskId=$taskId;projectRoot=$project;repositoryId='REPO_LOCAL';objects=$objects;allowedChanges=$changes;steps=$steps;recoveryActors=@('old-actor','new-actor');originalProcessLocators=$loc}
    $planPath=Join-Path $runtime 'plan.json';Write-Json $planPath $plan
    $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId=$taskId;profile='STANDARD';lifecycle='ACTIVE';owner='old-actor';issuer='old-actor';issuerRole='PROJECT_CONTROLLER';issuerControllerId='old-actor';issuerControllerEpoch=1;controllerControlIdentity=(Id $controllerPath);grantee='old-actor';bundle='CONTROL_TRANSITION_FIXTURE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='USER_FIXTURE_HANDOFF';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id $taskPath);actions=@('CONTROL_WRITE');exactPaths=$paths;objectIdentities=@($objects|ForEach-Object{[ordered]@{path=$_.path;identity=$_.before.identity}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Id (Join-Path $project '.ai-workspace/project.json'));transitionPlan=[ordered]@{path=$planPath;identity=(Id $planPath)}}
    Write-Json $loc.package $package
    $discover=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$script:framework;taskPath=$taskPath;expectedProjectConfigIdentity=$package.projectConfigIdentity;expectedCorrectionsIdentity=(Id (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=$package.taskIdentity;observedActor='old-actor';capabilities=@();exactPaths=$paths;forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$loc.package;expectedAuthorizationIdentity=(Id $loc.package);userDecision='USER_FIXTURE_HANDOFF';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Complete this explicitly authorized responsibility handoff.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('task','control transition','handoff');pathHints=$paths;capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
    Write-Json $loc.discoverInput $discover
    $fixture=[pscustomobject]@{Project=$project;TaskPath=$taskPath;ControllerPath=$controllerPath;Plan=$plan;PlanPath=$planPath;Locators=[pscustomobject]$loc;Prep=@();Results=@();Preview=$null}
    $env:CODEX_THREAD_ID='old-actor';$preview=Transition $fixture 'PREVIEW';$fixture.Preview=$preview
    $run=Run-Process $loc.discoverInput;Must-Pass $run 'FIXTURE_DISCOVER';Write-Json $loc.discoverReceipt $run.Value.compactReceipt
    $fixture.Prep=@(@($run.Value.compactReceipt.selectedObligations.preparationRequirements)+@($preview.targetRuleBlocks.preparationRequirements)|Sort-Object -Unique)
    $fixture.Results=@(@($run.Value.compactReceipt.selectedObligations.resultRequirements)+@($preview.targetRuleBlocks.resultRequirements)|Sort-Object -Unique)
    $admit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$loc.discoverReceipt;expectedDiscoverReceiptIdentity=(Id $loc.discoverReceipt);preparationReceipts=$fixture.Prep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Json $loc.admitInput $admit;$run=Run-Process $loc.admitInput;Must-Pass $run 'FIXTURE_ADMIT';Write-Json $loc.admitResult $run.Value
    Write-Finalize $fixture
    return $fixture
}

$versionRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:temp=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('aiw-control-transition-'+[guid]::NewGuid().ToString('N'))))
$originalActor=$env:CODEX_THREAD_ID;$complete=$false
try {
    $script:framework=Join-Path $script:temp 'framework-root';$fixtureVersion=Join-Path $script:framework 'framework/versions/2.0.0'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fixtureVersion))|Out-Null
    Copy-Item -LiteralPath $versionRoot -Destination $fixtureVersion -Recurse
    $version=Get-Content (Join-Path $fixtureVersion 'VERSION.json') -Raw|ConvertFrom-Json;$version.lifecycle='STABLE';$version.consumable=$true;$version.projectPinEligible=$true;Write-Json (Join-Path $fixtureVersion 'VERSION.json') $version
    $load=Get-Content (Join-Path $fixtureVersion 'LOAD_MANIFEST.json') -Raw|ConvertFrom-Json;$load.lifecycle='STABLE';Write-Json (Join-Path $fixtureVersion 'LOAD_MANIFEST.json') $load
    [string[]]$payload=@(Get-ChildItem $fixtureVersion -Recurse -File|Where-Object{$_.Name-cne'RELEASE_MANIFEST.json'}|ForEach-Object{[IO.Path]::GetRelativePath($fixtureVersion,$_.FullName).Replace('\','/')});[Array]::Sort($payload,[StringComparer]::Ordinal)
    $rows=@();[long]$total=0;foreach($p in $payload){$identity=(Id (Join-Path $fixtureVersion $p)).Split('|');$total+=[long]$identity[0];$rows+=($p+'|'+$identity[0]+'|'+$identity[1])}
    $manifest=Get-Content (Join-Path $fixtureVersion 'RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json;$manifest.lifecycle='STABLE';$manifest.sourceReview='APPROVED';$manifest.fileCount=$payload.Count;$manifest.totalBytes=$total;$manifest.canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n"))));Write-Json (Join-Path $fixtureVersion 'RELEASE_MANIFEST.json') $manifest
    $script:resolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
    $script:transitionModule=@(Import-Module (Join-Path $fixtureVersion 'scripts/ControlTransition.psm1') -Force -PassThru)[0]

    $f=New-Fixture
    Assert-True ($f.Preview.status-ceq'PREVIEW'-and$f.Preview.derivedImages.Count-eq2-and'TARGET_PREP_REQUIRED'-cin$f.Prep) 'preview-freezes-derived-images-and-target-rules-without-hash-cycle'
    $applied=Transition $f 'APPLY';Assert-True ($applied.status-ceq'APPLIED'-and-not(Test-Path $f.Locators.completionProof)) 'apply-does-not-claim-finalize-or-completion'
    $ordinary=Run-Process $f.Locators.discoverInput;Assert-True ($ordinary.Code-ne0-and$ordinary.Text.Contains('CONTROL_TRANSITION_RECOVERY_REQUIRED')) 'ordinary-actions-reject-in-progress-controller'
    $old=Snapshot $f;$env:CODEX_THREAD_ID='third-party';Expect-Rejected {Transition $f 'RECOVER' 'CONTINUE'} 'TRANSITION_RECOVERY_ACTOR' 'unauthorized-recovery-actor';Assert-True ((Snapshot $f)-ceq$old) 'wrong-actor-zero-overwrite';$env:CODEX_THREAD_ID='new-actor'
    Write-Finalize $f -OmitTarget;$missing=Run-Process $f.Locators.finalizeInput
    Assert-True ($missing.Code-ne0-and$missing.Text.Contains('TARGET_RESULT_REQUIRED')-and-not(Test-Path $f.Locators.completionProof)) 'original-finalize-enforces-new-target-obligation'
    Write-Finalize $f
    [IO.Directory]::CreateDirectory($f.Locators.completionProof)|Out-Null
    Expect-Rejected {Transition $f 'FINALIZE'} 'TRANSITION_ATOMIC_DESTINATION_EXISTS' 'proof-persistence-failure-retains-markers'
    Remove-Item -LiteralPath $f.Locators.completionProof
    Assert-True ((Snapshot $f)-ceq$old) 'proof-failure-zero-control-cleanup'
    $committed=Transition $f 'FINALIZE';Assert-True ($committed.status-ceq'COMMITTED'-and(Test-Path $f.Locators.completionProof)-and(Snapshot $f)-ceq$old) 'real-original-finalize-persists-proof-before-cleanup'
    Expect-Rejected {Transition $f 'RECOVER' 'ROLLBACK'} 'TRANSITION_COMMITTED_NO_ROLLBACK' 'committed-identity-cannot-roll-back'
    Set-Checkpoint 'BEFORE_COMPLETE_RETURN';Expect-Rejected {Transition $f 'COMPLETE'} 'INJECTED_CRASH' 'crash-after-last-marker-before-cli-return';Clear-Checkpoint
    Assert-True ((Get-Content $f.ControllerPath -Raw)-notmatch'transitionRef'-and(Get-Content $f.TaskPath -Raw)-notmatch'aiw-transition'-and(Test-Path $f.Locators.completionProof)) 'last-marker-gone-only-with-durable-original-proof'
    $finalSnapshot=Snapshot $f;$done=Transition $f 'COMPLETE';Assert-True ($done.status-ceq'COMPLETE'-and(Snapshot $f)-ceq$finalSnapshot) 'repeat-complete-is-idempotent'
    $oldAction=Run-Process $f.Locators.admitInput;Assert-True ($oldAction.Code-ne0) 'old-ordinary-package-remains-invalid-after-handoff'

    foreach($kind in @('TaskOnly','ControllerOnly','AnotherTask','CriticalTarget')){
        $arguments=@{};$arguments[$kind]=$true;$f=New-Fixture @arguments;$null=Transition $f 'APPLY';$env:CODEX_THREAD_ID='new-actor';$null=Transition $f 'FINALIZE';$done=Transition $f 'COMPLETE';Assert-True ($done.status-ceq'COMPLETE') ('directional-transition-'+$kind)
    }
    foreach($edge in 0..5){foreach($side in @('BEFORE','AFTER')){
        $f=New-Fixture;$point=$side+'_STEP_'+$edge+'_'+($edge+1)
        if($edge-ge4){$null=Transition $f 'APPLY';$null=Transition $f 'FINALIZE'}
        Set-Checkpoint $point
        if($edge-lt4){Expect-Rejected {Transition $f 'APPLY'} 'INJECTED_CRASH' ('interrupt-'+$point)}else{Expect-Rejected {Transition $f 'COMPLETE'} 'INJECTED_CRASH' ('interrupt-'+$point)}
        Clear-Checkpoint;$env:CODEX_THREAD_ID='new-actor';$recovered=Transition $f 'RECOVER' 'CONTINUE'
        if($recovered.status-ceq'APPLIED'){$null=Transition $f 'FINALIZE';$recovered=Transition $f 'COMPLETE'}
        Assert-True ($recovered.status-ceq'COMPLETE') ('fresh-successor-resumes-'+$point)
    }}
    $f=New-Fixture;$initial=Snapshot $f;$null=Transition $f 'APPLY';$env:CODEX_THREAD_ID='new-actor';Set-Checkpoint 'AFTER_STEP_4_3'
    Expect-Rejected {Transition $f 'RECOVER' 'ROLLBACK'} 'INJECTED_CRASH' 'rollback-interrupted-after-first-reverse-step';Clear-Checkpoint
    $rolled=Transition $f 'RECOVER' 'ROLLBACK';Assert-True ($rolled.status-ceq'ROLLED_BACK'-and(Snapshot $f)-ceq$initial-and-not(Test-Path $f.Locators.completionProof)) 'rollback-resumes-to-entire-original-state'

    $f=New-Fixture;$null=Transition $f 'APPLY';$ctx=& $script:transitionModule.ExportedFunctions['Read-AiwControlTransitionPlan'] $f.Project $f.PlanPath (Id $f.PlanPath)
    [IO.File]::WriteAllBytes($f.ControllerPath,$ctx.Objects['.ai-workspace/controller.json'].AFTER.Bytes)
    [IO.File]::WriteAllBytes($f.TaskPath,$ctx.Objects['.ai-workspace/tasks/active/TRANSITION-001.md'].MARKED_BEFORE.Bytes)
    $unreachable=Snapshot $f;Expect-Rejected {Transition $f 'RECOVER' 'CONTINUE'} 'TRANSITION_UNREACHABLE_STATE' 'known-images-in-unreachable-combination';Assert-True ((Snapshot $f)-ceq$unreachable) 'unreachable-vector-zero-overwrite'
    [IO.File]::WriteAllBytes($f.ControllerPath,$ctx.Objects['.ai-workspace/controller.json'].MARKED_TARGET.Bytes)
    [IO.File]::WriteAllBytes($f.TaskPath,$ctx.Objects['.ai-workspace/tasks/active/TRANSITION-001.md'].MARKED_TARGET.Bytes)
    [IO.File]::AppendAllText($f.TaskPath,'third party',$utf8);$third=Snapshot $f;Expect-Rejected {Transition $f 'RECOVER' 'ROLLBACK'} 'TRANSITION_UNREACHABLE_STATE' 'third-party-bytes-refused';Assert-True ((Snapshot $f)-ceq$third) 'third-party-zero-overwrite'

    foreach($mutation in @('TASK_ID','CONTROLLER_EPOCH','STEP_ORDER','PROJECT_PIN','EXTRA_FIELD')){
        $f=New-Fixture;$before=Snapshot $f;$plan=Get-Content $f.PlanPath -Raw|ConvertFrom-Json
        switch($mutation){
            'TASK_ID' {$text=$utf8.GetString([Convert]::FromBase64String($plan.objects[1].after.base64)).Replace('TRANSITION-001','ALIEN-001');$plan.objects[1].after=Image $text}
            'CONTROLLER_EPOCH' {$value=$utf8.GetString([Convert]::FromBase64String($plan.objects[0].after.base64))|ConvertFrom-Json;$value.controllerEpoch=9;$plan.objects[0].after=Image (Json-Text $value)}
            'STEP_ORDER' {$swap=$plan.steps[0];$plan.steps[0]=$plan.steps[1];$plan.steps[1]=$swap}
            'PROJECT_PIN' {$plan.objects[0].path='.ai-workspace/project.json'}
            'EXTRA_FIELD' {$plan|Add-Member -NotePropertyName allowAnything -NotePropertyValue $true}
        }
        Write-Json $f.PlanPath $plan;Expect-Rejected {Transition $f 'PREVIEW'} 'TRANSITION_' ('invalid-plan-'+$mutation);Assert-True ((Snapshot $f)-ceq$before) ('invalid-plan-zero-overwrite-'+$mutation)
    }
    $f=New-Fixture;$before=Snapshot $f;$admitBytes=[IO.File]::ReadAllBytes($f.Locators.admitResult);Remove-Item -LiteralPath $f.Locators.admitResult
    Expect-Rejected {Transition $f 'APPLY'} 'INPUT_MISSING' 'missing-original-admission';Assert-True ((Snapshot $f)-ceq$before) 'missing-admission-zero-overwrite'
    [IO.File]::WriteAllBytes($f.Locators.admitResult,$admitBytes)
    $bad=Get-Content $f.Locators.admitResult -Raw|ConvertFrom-Json;$bad.decisionIdentity='A'*64;Write-Json $f.Locators.admitResult $bad
    Expect-Rejected {Transition $f 'APPLY'} 'TRANSITION_ORIGINAL_ADMIT_DECISION' 'tampered-original-decision-rejected';Assert-True ((Snapshot $f)-ceq$before) 'fake-admission-zero-overwrite'
    $env:CODEX_THREAD_ID='new-actor';Expect-Rejected {Transition $f 'RECOVER' 'CONTINUE'} 'TRANSITION_ORIGINAL_ADMIT_DECISION' 'recovery-from-start-requires-real-original-decision';Assert-True ((Snapshot $f)-ceq$before) 'fake-recovery-admission-zero-overwrite'
    [IO.File]::WriteAllBytes($f.Locators.admitResult,$admitBytes)
    $env:CODEX_THREAD_ID='old-actor';Set-Checkpoint 'AFTER_STEP_0_1';Expect-Rejected {Transition $f 'APPLY'} 'INJECTED_CRASH' 'start-before-recovery-decision-negative';Clear-Checkpoint
    Write-Json $f.Locators.admitResult $bad;$partial=Snapshot $f;$env:CODEX_THREAD_ID='new-actor'
    Expect-Rejected {Transition $f 'RECOVER' 'CONTINUE'} 'TRANSITION_ORIGINAL_ADMIT_DECISION' 'partial-recovery-revalidates-original-decision';Assert-True ((Snapshot $f)-ceq$partial) 'partial-fake-admission-zero-overwrite'
    [IO.File]::WriteAllBytes($f.Locators.admitResult,$admitBytes);$null=Transition $f 'RECOVER' 'CONTINUE'
    $lockedBefore=Snapshot $f;$lock=[IO.File]::Open(($f.PlanPath+'.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$locked=Run-Process $f.Locators.finalizeInput;Assert-True ($locked.Code-ne0-and-not(Test-Path $f.Locators.completionProof)-and(Snapshot $f)-ceq$lockedBefore) 'direct-original-finalize-obeys-same-transaction-lock'}finally{$lock.Dispose()}
    $null=Transition $f 'FINALIZE';$proofBytes=[IO.File]::ReadAllBytes($f.Locators.completionProof);$proof=Get-Content $f.Locators.completionProof -Raw|ConvertFrom-Json;$proof.finalizeResult.decisionIdentity='B'*64;Write-Json $f.Locators.completionProof $proof;$marked=Snapshot $f
    Expect-Rejected {Transition $f 'COMPLETE'} 'TRANSITION_PROOF_DECISION' 'tampered-completion-decision-refused';Assert-True ((Snapshot $f)-ceq$marked) 'tampered-proof-zero-cleanup'
    [IO.File]::WriteAllBytes($f.Locators.completionProof,$proofBytes);$null=Transition $f 'COMPLETE'
    $f=New-Fixture -TaskOnly;$before=Snapshot $f;$input=Get-Content $f.Locators.discoverInput -Raw|ConvertFrom-Json;$input.forbiddenPaths+=@('.ai-workspace/tasks/active/TRANSITION-001.md');Write-Json $f.Locators.discoverInput $input
    Expect-Rejected {Transition $f 'PREVIEW'} 'TRANSITION_FORBIDDEN_READ' 'forbidden-object-rejected-before-state-hash';Assert-True ((Snapshot $f)-ceq$before) 'forbidden-preview-zero-overwrite'
    $complete=$true;Write-Output ('PASS|control-transition-total='+$script:passed)
} finally {
    if($null-ne(Get-Variable transitionModule -Scope Script -ErrorAction SilentlyContinue)){Clear-Checkpoint}
    $env:CODEX_THREAD_ID=$originalActor
    if($complete){
        $root=[IO.Path]::GetFullPath($script:temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
        if([IO.Path]::GetDirectoryName($root)-cne$parent-or[IO.Path]::GetFileName($root)-cnotmatch'^aiw-control-transition-[0-9a-f]{32}$'){throw 'FIXTURE_CLEANUP_SCOPE'}
        Remove-Item -LiteralPath $root -Recurse -Force
    }else{Write-Output ('FAILED_FIXTURE_RETAINED|'+$script:temp)}
}
