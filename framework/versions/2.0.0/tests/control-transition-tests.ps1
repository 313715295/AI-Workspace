[CmdletBinding()]
param([ValidateSet('All','PlanShape','OriginalRecovery','OrdinaryArchive','NativeIO')][string]$Group='All')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
$Group=@('All','PlanShape','OriginalRecovery','OrdinaryArchive','NativeIO')|Where-Object{$_-ieq$Group}
if($Group-ceq'All'){
 foreach($selected in @('PlanShape','OriginalRecovery')){
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Group',$selected) -GroupId ('control-'+$selected)
  $run.Output|ForEach-Object{Write-Output $_};if($run.Code-ne0){exit $run.Code}
 };return
}
$utf8=[Text.UTF8Encoding]::new($false)
$script:passed=0;$script:fixtureNumber=0
function Assert-True([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Host ('PASS|'+$Name)}
function Write-Text([string]$Path,[string]$Value){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))|Out-Null;[IO.File]::WriteAllText($Path,$Value,$utf8)}
function Write-Json([string]$Path,$Value){Write-Text $Path (($Value|ConvertTo-Json -Depth 100 -Compress)+"`n")}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Image([string]$Text){$b=$utf8.GetBytes($Text);return [ordered]@{identity=($b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)));base64=[Convert]::ToBase64String($b)}}
function Json-Text($Value){return ($Value|ConvertTo-Json -Depth 100 -Compress)+"`n"}
function Run-Process([string]$InputPath,[string[]]$ConsumedRuntimePath=@(),[switch]$DeleteInputOnExit){
 if($ConsumedRuntimePath.Count){Import-Module (Join-Path $script:fixtureVersion 'scripts/WorkflowDelivery.psm1');$value=Invoke-AiwDeliveryBoundary ([pscustomobject]@{path=$InputPath;identity=(Id $InputPath)}) -ConsumedRuntimePath $ConsumedRuntimePath;return [pscustomobject]@{Code=$(if($value.status-ceq'PASS'){0}else{3});Text=($value|ConvertTo-Json -Depth 100 -Compress);Value=$value}}
 $arguments=@('-NoProfile','-File',$script:resolver,'-InputPath',$InputPath,'-AsJson');if($DeleteInputOnExit){$arguments+=@('-DeleteInputOnExit')}
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) $arguments -GroupId ('control-'+$Group);return [pscustomobject]@{Code=$run.Code;Text=$run.Text;Value=$(try{$run.StdoutText|ConvertFrom-Json -Depth 100}catch{$null})}
}
function Must-Pass($Run,[string]$Label){if($Run.Code-ne0-or$null-eq$Run.Value-or$Run.Value.status-cne'PASS'){throw ($Label+'|'+$Run.Text)}}
function Transition($Fixture,[string]$Operation,[string]$Recovery='NOT_APPLICABLE'){
    $request=[pscustomobject][ordered]@{operation=$Operation;projectRoot=$Fixture.Project;planPath=$Fixture.PlanPath;expectedPlanIdentity=(Id $Fixture.PlanPath);recoveryMode=$Recovery}
    return & $script:transitionModule.ExportedFunctions['Invoke-AiwControlTransition'] $request
}
function Expect-Rejected([scriptblock]$Action,[string]$Reason,[string]$Name){$caught=$null;try{$null=& $Action}catch{$caught=$_.Exception.Message};Assert-True ($null-ne$caught-and$caught.Contains($Reason)) ($Name+'|'+$caught)}
function Set-Checkpoint([string]$Point){& $script:transitionModule {param($p) $script:ControlTransitionTestCheckpoint={param($name)if($name-ceq$p){throw ('INJECTED_CRASH|'+$p)}}.GetNewClosure()} $Point}
function Clear-Checkpoint{& $script:transitionModule {$script:ControlTransitionTestCheckpoint=$null}}
function Snapshot($Fixture){return @($Fixture.Plan.objects|ForEach-Object{$_.path+'='+(Id (Join-Path $Fixture.Project $_.path))})-join"`n"}
function Write-Finalize($Fixture,[switch]$OmitTarget,[switch]$OmitTargetPrep){
    $ctx=& $script:transitionModule.ExportedFunctions['Read-AiwControlTransitionPlan'] $Fixture.Project $Fixture.PlanPath (Id $Fixture.PlanPath)
    $results=@($Fixture.Results|Where-Object{-not$OmitTarget-or$_-cne'TARGET_RESULT_REQUIRED'})+@($ctx.Paths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+$ctx.Objects[$_].MARKED_TARGET.Identity})
    $input=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$Fixture.Locators.discoverReceipt;expectedDiscoverReceiptIdentity=(Id $Fixture.Locators.discoverReceipt);preparationReceipts=@($Fixture.Prep|Where-Object{-not$OmitTargetPrep-or$_-cne'TARGET_PREP_REQUIRED'});resultReceipts=$results;deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Json $Fixture.Locators.finalizeInput $input
}
function Set-FixtureSources([string]$Project,$TargetRule){
    # Adopt real source descriptors before constructing the package and original admission.
    Import-Module (Join-Path $script:fixtureVersion 'scripts/ContentSources.psm1')
    $root=Join-Path $Project 'standards'
    foreach($file in @('original.md','target.md','dependency.md')){Write-Text (Join-Path $root $file) ('Complete transition obligation from '+$file+".`n")}
    $binding=[pscustomobject]@{id='transition-standards';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$root};allowedPaths=@('original.md','target.md','dependency.md'|ForEach-Object{[pscustomobject]@{kind='FILE';locator=$_}});decisionLocator='fixture:explicit-transition-source-permission'}
    $configPath=Join-Path $Project '.ai-workspace/project.json';$config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
    $config.sourceBindings=@($binding);Write-Json $configPath $config
    $rules=@()
    foreach($kind in @('original','target')){
        $files=@(if($kind-ceq'original'){'original.md'}else{'target.md';'dependency.md'})
        $documents=@(foreach($file in $files){
            $document=[pscustomobject]@{sourceId=$file;bindingId=$binding.id;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=$file;identity=(Id (Join-Path $root $file));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@(if($file-ceq'target.md'){'dependency.md'})}
            $document.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) @($binding);$document
        })
        $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$binding.id;itemId=$kind;revision=(Get-AiwContentRevision ([pscustomobject]@{documents=$documents}) @($binding));itemIdentity='';rootSourceId=$files[0];documents=$documents}
        $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
        $rule=$TargetRule|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $rule.PSObject.Properties.Remove('effectiveRule');$rule|Add-Member source $descriptor
        if($kind-ceq'original'){$rule.ruleId='TRANSITION_ORIGINAL_SOURCE';$rule.selectors.roles=@('CONTROLLER');$rule.selectors.phases=@('PLAN');$rule.preparationRequirements=@('ORIGINAL_SOURCE_PREP');$rule.resultRequirements=@('ORIGINAL_SOURCE_RESULT')}
        $rules+=$rule
    }
    Write-Json (Join-Path $Project '.ai-workspace/process-policy.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId=$config.id;rules=$rules})
}
function New-Fixture([switch]$TaskOnly,[switch]$ControllerOnly,[switch]$AnotherTask,[switch]$CriticalTarget,[switch]$PreparationOnly,[switch]$SourceClosure,[switch]$ProtectControl){
    $script:fixtureNumber++;$project=Join-Path $script:temp ('project-控制-😀-'+$script:fixtureNumber)
    [IO.Directory]::CreateDirectory($project)|Out-Null
    & git -C $project init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
    $taskId='TRANSITION-001';$taskRelative='.ai-workspace/tasks/active/TRANSITION-001.md';$taskPath=Join-Path $project $taskRelative
    $controllerRelative='.ai-workspace/controller.json';$controllerPath=Join-Path $project $controllerRelative
    $runtime=Join-Path $project '.ai-workspace/runtime/TRANSITION-001/old-actor';[IO.Directory]::CreateDirectory($runtime)|Out-Null
    $loc=[ordered]@{};foreach($name in @('package','discoverInput','discoverReceipt','admitInput','admitResult','finalizeInput','completionProof')){$loc[$name]=Join-Path $runtime ($name+'.json')}
    $projectId='transition-fixture-'+$script:fixtureNumber
    Write-Json (Join-Path $project '.ai-workspace/project.json') ([ordered]@{schemaVersion=7;id=$projectId;displayName='Transition fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
    $beforeController=Json-Text ([ordered]@{schemaVersion=1;projectId=$projectId;controllerId='old-actor';controllerEpoch=1;state='CURRENT'})
    $afterController=Json-Text ([ordered]@{schemaVersion=1;projectId=$projectId;controllerId='new-actor';controllerEpoch=2;state='CURRENT'})
    Write-Text $controllerPath $beforeController
    $beforeTask="# TRANSITION-001 — control transition fixture`n`n- Task schema: 2.0.0`n- Profile: STANDARD; reason=fixture`n- Owner: old-actor`n- Work route: actor=old-actor; role=CONTROLLER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; current_exact=FIXTURE; expected_paths=[]; actual_paths=[]`n"
    $afterTask=$beforeTask.Replace('Owner: old-actor','Owner: new-actor').Replace('actor=old-actor; role=CONTROLLER; phase=PLAN','actor=new-actor; role=TASK_OWNER; phase=IMPLEMENT')
    if($CriticalTarget){$afterTask=$afterTask.Replace('Profile: STANDARD','Profile: CRITICAL').Replace('profile=STANDARD','profile=CRITICAL')}
    Write-Text $taskPath $beforeTask
    Write-Text (Join-Path $project '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
    Write-Json (Join-Path $project '.ai-workspace/corrections.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId=$projectId;corrections=@()})
    $targetRule=[ordered]@{ruleId='TRANSITION_TARGET_GATE';requirementReason='New responsibility must consume its own requirements.';effectiveRule='Prepare and verify the target handoff obligation.';selectors=[ordered]@{profiles=@('STANDARD','CRITICAL');roles=@('TASK_OWNER');phases=@('IMPLEMENT');actionKinds=@('CONTROL_WRITE');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@('TARGET_PREP_REQUIRED');resultRequirements=@('TARGET_RESULT_REQUIRED');decisionLocator='fixture:target-obligation'}
    Write-Json (Join-Path $project '.ai-workspace/process-policy.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId=$projectId;rules=@($targetRule)})
    if($SourceClosure){Set-FixtureSources $project $targetRule}
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
    $discover=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$script:framework;taskPath=$taskPath;expectedProjectConfigIdentity=$package.projectConfigIdentity;expectedCorrectionsIdentity=(Id (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=$package.taskIdentity;observedActor='old-actor';capabilities=@();exactPaths=$paths;forbiddenPaths=@('private/');protectedPaths=@($(if($ProtectControl){'.ai-workspace/'}else{'.ai-workspace/private/'}));authorizationPackagePath=$loc.package;expectedAuthorizationIdentity=(Id $loc.package);userDecision='USER_FIXTURE_HANDOFF';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:controller-handoff')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:configuration')};stage=[ordered]@{state='KNOWN';values=@('aiw:implementation')}};objective='Complete this explicitly authorized responsibility handoff.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('task','control transition','handoff');pathHints=$paths;capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
    Write-Json $loc.discoverInput $discover
    $fixture=[pscustomobject]@{Project=$project;TaskPath=$taskPath;ControllerPath=$controllerPath;Plan=$plan;PlanPath=$planPath;Locators=[pscustomobject]$loc;Prep=@();Results=@();Preview=$null}
    if($PreparationOnly){return $fixture}
    $env:CODEX_THREAD_ID='old-actor';$preview=Transition $fixture 'PREVIEW';$fixture.Preview=$preview
    $run=Run-Process $loc.discoverInput;Must-Pass $run 'FIXTURE_DISCOVER';Write-Json $loc.discoverReceipt $run.Value.compactReceipt
    $fixture.Prep=@(@($run.Value.compactReceipt.selectedObligations.preparationRequirements)+@($preview.targetRuleBlocks.preparationRequirements)|Sort-Object -Unique)
    $fixture.Results=@(@($run.Value.compactReceipt.selectedObligations.resultRequirements)+@($preview.targetRuleBlocks.resultRequirements)|Sort-Object -Unique)
    $admit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$loc.discoverReceipt;expectedDiscoverReceiptIdentity=(Id $loc.discoverReceipt);preparationReceipts=$fixture.Prep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Json $loc.admitInput $admit;$run=Run-Process $loc.admitInput;Must-Pass $run 'FIXTURE_ADMIT';Write-Json $loc.admitResult $run.Value
    Write-Finalize $fixture
    return $fixture
}






function Check-OrdinaryArchivePackage($Fixture,$Package=$null,[string]$Path=''){
 if($null-eq$Package){$Package=Get-Content -LiteralPath $Fixture.Locators.package -Raw|ConvertFrom-Json -Depth 100}
 if(-not$Path){$Path=$Fixture.Locators.package}else{Write-Json $Path $Package}
 $oldLocation=Get-Location;$oldCurrent=[Environment]::CurrentDirectory
 try{
  Set-Location -LiteralPath $Fixture.Project;[Environment]::CurrentDirectory=$Fixture.Project
  $out=@(& (Join-Path $script:fixtureVersion 'scripts/check-authorization.ps1') -PackagePath $Path -ObservedActor old-actor -ObservedTaskId TRANSITION-001 -ObservedOwner old-actor -ObservedAction CONTROL_WRITE -ObservedPath @($Package.exactPaths) -ObservedIdentity @($Package.objectIdentities|ForEach-Object{$_.path+'='+$_.identity}) -TaskPath '.ai-workspace/tasks/active/different-leaf.md' -ExpectedTaskIdentity $Package.taskIdentity -ProjectConfigPath '.ai-workspace/project.json' -ExpectedProjectConfigIdentity $Package.projectConfigIdentity -ControllerControlPath '.ai-workspace/controller.json' 2>&1|ForEach-Object{[string]$_})
  return [pscustomobject]@{Code=$LASTEXITCODE;Text=($out-join"`n")}
 }finally{Set-Location -LiteralPath $oldLocation;[Environment]::CurrentDirectory=$oldCurrent}
}
function New-OrdinaryArchiveFixture([string]$Outcome='SUCCESS',[switch]$MissingUserGate,[string]$BlockedProof=''){
 $f=New-Fixture -TaskOnly -PreparationOnly
 $old=$f.TaskPath;$active='.ai-workspace/tasks/active/different-leaf.md';$archive='.ai-workspace/tasks/archive/different-leaf.md'
 $text=[IO.File]::ReadAllText($old);$new=Join-Path $f.Project $active
 $runtime=[IO.Path]::GetDirectoryName($f.PlanPath)
 $requirements=Join-Path $runtime 'requirements.md';$decision=Join-Path $runtime 'original-user-decision.txt'
 Write-Text $requirements 'Synthetic acceptance requires this exact observed fixture decision.'
 Write-Text $decision 'Synthetic original closure decision; no real human or host delivery is claimed.'
 $stage=[ordered]@{id='closure-user';kind='USER_DECISION';requiredBy=[ordered]@{path=$requirements;identity=(Id $requirements)};dependsOn=@();candidateRef=@([ordered]@{path=$decision;identity=(Id $decision)});evidenceRefs=@()}
 $stages=@($stage)
 if($Outcome-ceq'SUCCESS'){
  # Actual producer input consumption fails on a real open handle. The original
  # final consumer later discovers this known expiry through its validated plan.
  $retryInput=Join-Path $runtime 'producer-consumed-input.json';[IO.File]::Copy($f.Locators.discoverInput,$retryInput)
  $env:CODEX_THREAD_ID='old-actor';$hold=[IO.File]::Open($retryInput,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{$producer=Run-Process $retryInput -DeleteInputOnExit}finally{$hold.Dispose()}
  Must-Pass $producer 'ARCHIVE_ACTUAL_PRODUCER';Assert-True ($producer.Value.inputCleanup.status-ceq'PARTIAL_FAILURE'-and[IO.File]::Exists($retryInput)) 'archive-producer-real-sharing-failure-keeps-known-expired-input'
  $proofLeaf=Join-Path $runtime 'report-required-proof.txt';Write-Text $proofLeaf 'Required by the actual archived acceptance plan via an external report.'
  $producerReport=Join-Path $f.Project '.ai-workspace/reports/archive-producer.json'
  $observed=@([ordered]@{mode=$producer.Value.mode;status=$producer.Value.status;inputCleanup=$producer.Value.inputCleanup})
  $keptInputs=@()
  if(-not$BlockedProof){
   # These two returns come from real native producers. Reusing their filenames
   # must never give a later final consumer permission over the new bytes.
   foreach($variant in @('removed-recreated','remaining-replaced')){
    $p=Join-Path $runtime ($variant+'.json');[IO.File]::Copy($f.Locators.discoverInput,$p)
    $lock=$null
    try{if($variant-ceq'remaining-replaced'){$lock=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)};$actual=Run-Process $p -DeleteInputOnExit}
    finally{if($null-ne$lock){$lock.Dispose()}}
    Must-Pass $actual ('ARCHIVE_ACTUAL_'+$variant)
    Assert-True ($(if($variant-ceq'removed-recreated'){$actual.Value.inputCleanup.removed.Count-eq1}else{$actual.Value.inputCleanup.remaining.Count-eq1})) ('archive-real-producer-'+$variant)
    $observed+=@([ordered]@{mode=$actual.Value.mode;status=$actual.Value.status;inputCleanup=$actual.Value.inputCleanup})
    Write-Json $p ([ordered]@{fixture='A later generation owns these new bytes.';variant=$variant})
    $keptInputs+=@([ordered]@{path=$p;identity=(Id $p)})
   }
   # Historical observations below are labeled synthetic data. Actual original
   # FINALIZE consumes them; no host policy denial or failed command is fabricated.
   foreach($variant in @('FAIL','INCOMPLETE','UNKNOWN','MISSING_OUTCOME','HOST_POLICY_REJECTED','UNKNOWN_FAILURE','MISSING_IDENTITY')){
    $p=Join-Path $runtime ('synthetic-'+$variant+'.json');Write-Json $p ([ordered]@{fixture='Synthetic historical producer observation';variant=$variant})
    $id=Id $p;$kind=if($variant-ceq'HOST_POLICY_REJECTED'){'HOST_POLICY_REJECTED'}elseif($variant-ceq'UNKNOWN_FAILURE'){'UNKNOWN'}else{'IO_ERROR'}
    $cleanup=[ordered]@{status='PARTIAL_FAILURE';removed=@();alreadyAbsent=@();remaining=@($p);failures=@([ordered]@{path=$p;kind=$kind;message='Synthetic historical observation, not an actual host rejection.'})}
    if($variant-cne'MISSING_IDENTITY'){$cleanup.consumedObject=[ordered]@{path=$p;identity=$id}}
    $historical=[ordered]@{fixture='SIMULATED_HISTORY';mode='FINALIZE_OUTPUT';status='PASS';inputCleanup=$cleanup}
    if($variant-cne'MISSING_OUTCOME'){$historical.actionOutcome=if($variant-cin@('FAIL','INCOMPLETE','UNKNOWN')){$variant}else{'PASS'}}
    $observed+=@($historical);$keptInputs+=@([ordered]@{path=$p;identity=$id})
   }
  }
  $report=[ordered]@{producers=$observed;proof=([IO.Path]::GetRelativePath($f.Project,$proofLeaf).Replace('\','/')+'#'+(Id $proofLeaf))}
  if($BlockedProof){
   $sentinel=if($BlockedProof-ceq'PROJECT_EXCLUDED'){Join-Path $f.Project 'private/blocked.json'}else{Join-Path $script:framework 'private/blocked.json'}
   Write-Text $sentinel 'Not JSON: a protected linked sentinel must never be parsed.'
   $f|Add-Member SentinelHold ([IO.File]::Open($sentinel,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None))
   $report.blockedProof=$sentinel
  }
  Write-Json $producerReport $report
  $f|Add-Member KeptInputs $keptInputs
  $stages+=@([ordered]@{id='producer';kind='DESIGN';requiredBy=$stage.requiredBy;dependsOn=@();candidateRef=@([ordered]@{path=$producerReport;identity=(Id $producerReport)});evidenceRefs=@()})
  $f|Add-Member RetryInput $retryInput;$f|Add-Member ProofLeaf $proofLeaf;$f|Add-Member ProofIdentity (Id $proofLeaf);$f|Add-Member ProducerReport $producerReport
 }
 if($Outcome-ceq'SUCCESS'){$text+='```aiw-acceptance-plan'+"`n"+([ordered]@{schemaVersion=1;stages=$stages}|ConvertTo-Json -Depth 30 -Compress)+"`n"+'```'+"`n"}
 Write-Text $new $text
 if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($old))-cne[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($new))){throw 'ARCHIVE_FIXTURE_SCOPE'}
 [IO.File]::Delete($old);$f.TaskPath=$new
 $closed=$text.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+"`n- Closure outcome: $Outcome`n- Closure basis: Exact synthetic decision and retained evidence.`n- Output disposition: Retained in this fixture.`n- Git disposition: DEFERRED; isolated fixture only.`n- Unresolved obligations: NONE`n- Writer: RELEASED`n- Reviewer: RELEASED`n- Authorization: RELEASED`n"
 if($Outcome-cne'SUCCESS'){
  $closed+="- Unfinished work: Explicit fixture cancellation or supersession.`n- Closure decision: $decision#$(Id $decision)`n"
  if($Outcome-ceq'SUPERSEDED'){
   Write-Text (Join-Path $f.Project '.ai-workspace/tasks/active/NEXT-001.md') ($text.Replace('TRANSITION-001','NEXT-001'))
   $closed=$closed.Replace('Unresolved obligations: NONE','Unresolved obligations: TRANSFERRED: .ai-workspace/tasks/active/NEXT-001.md')
  }
 }
 $pkg=Get-Content -LiteralPath $f.Locators.package -Raw|ConvertFrom-Json -Depth 100
 $pkg.PSObject.Properties.Remove('transitionPlan');$pkg.bundle='ORDINARY_CURRENT_TASK_ARCHIVE'
 $pkg.decisionClass='ROUTINE_LOCAL';$pkg.userConfirmation='NOT_REQUIRED'
 $pkg.exactPaths=@($active,$archive);$pkg.objectIdentities=@([pscustomobject]@{path=$active;identity=(Id $new)},[pscustomobject]@{path=$archive;identity='NEW'});$pkg.taskIdentity=Id $new
 if($BlockedProof-ceq'PROJECT_EXCLUDED'){
  $configPath=Join-Path $f.Project '.ai-workspace/project.json';$cfg=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
  $cfg.routineExcludedPaths=@('private');Write-Json $configPath $cfg;$pkg.projectConfigIdentity=Id $configPath
 }
 Write-Json $f.Locators.package $pkg
 # The inherited responsibility-plan construction is fixture setup only.
 # Delete its unused file before calling any ordinary product entry point.
 [IO.File]::Delete($f.PlanPath)
 $discover=Get-Content -LiteralPath $f.Locators.discoverInput -Raw|ConvertFrom-Json -Depth 100
 $discover.schemaVersion=5;$discover|Add-Member ruleLoad ([pscustomobject]@{mode='FULL'})
 if($BlockedProof-ceq'PROJECT_EXCLUDED'){$discover.forbiddenPaths=@();$discover.expectedProjectConfigIdentity=$pkg.projectConfigIdentity}
 $discover.taskPath=$new;$discover.expectedTaskIdentity=$pkg.taskIdentity;$discover.exactPaths=@($active,$archive);$discover.expectedAuthorizationIdentity=Id $f.Locators.package;$discover.userDecision='NOT_REQUIRED'
 $discover.intentEnvelope.objective='Close and archive the exact current task using ordinary ordered writes and original finalization.'
 $discover.intentEnvelope.facets.workType.values=@('aiw:implementation');$discover.intentEnvelope.semanticHints=@('task','close','archive');$discover.intentEnvelope.pathHints=@($active,$archive)
 Write-Json $f.Locators.discoverInput $discover;$env:CODEX_THREAD_ID='old-actor'
 $checked=Check-OrdinaryArchivePackage $f
 Assert-True ($checked.Code-eq0) ('ordinary-current-archive-real-independent-checker|'+$checked.Text)
 $run=Run-Process $f.Locators.discoverInput;Must-Pass $run 'ORDINARY_ARCHIVE_DISCOVER';Write-Json $f.Locators.discoverReceipt $run.Value.compactReceipt
 $f.Prep=@($run.Value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique)
 $f.Results=@($run.Value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)
 $admit=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$f.Locators.discoverReceipt;expectedDiscoverReceiptIdentity=(Id $f.Locators.discoverReceipt);preparationReceipts=$f.Prep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 Write-Json $f.Locators.admitInput $admit;$run=Run-Process $f.Locators.admitInput;Must-Pass $run 'ORDINARY_ARCHIVE_ADMIT';Write-Json $f.Locators.admitResult $run.Value
 $closedBytes=$utf8.GetBytes($closed);$closedIdentity=(Image $closed).identity
 $fin=[ordered]@{schemaVersion=3;mode='FINALIZE_OUTPUT';discoverReceiptPath=$f.Locators.discoverReceipt;expectedDiscoverReceiptIdentity=(Id $f.Locators.discoverReceipt);preparationReceipts=$f.Prep;resultReceipts=@($f.Results)+@(('OBJECT_POSTIMAGE|'+$active+'|MISSING'),('OBJECT_POSTIMAGE|'+$archive+'|'+$closedIdentity));deliveryReceipts=@();publicDecisionIdentity=$(if($MissingUserGate){'NOT_REQUIRED'}else{Id $decision});protectionState='BOUND';evidenceRefs=@()}
 Write-Json $f.Locators.finalizeInput $fin
 $f|Add-Member ActivePath $active;$f|Add-Member ArchivePath $archive
 $f|Add-Member ClosedBytes $closedBytes;$f|Add-Member ClosedIdentity $closedIdentity
 $f|Add-Member ActiveIdentity $pkg.taskIdentity;$f|Add-Member Decision $decision
 return $f
}
function Save-OrdinaryArchive($Fixture,[switch]$SaveOnly){
 $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Fixture.Project))
 $active=[IO.Path]::GetFullPath((Join-Path $root $Fixture.ActivePath));$archive=[IO.Path]::GetFullPath((Join-Path $root $Fixture.ArchivePath))
 foreach($path in @($active,$archive)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ARCHIVE_FIXTURE_WRITE_SCOPE'}}
 if((Id $active)-cne$Fixture.ActiveIdentity){throw 'ARCHIVE_ACTIVE_PREIMAGE_DRIFT'}
 if([IO.File]::Exists($archive)){
  if((Id $archive)-cne$Fixture.ClosedIdentity){throw 'ARCHIVE_EXISTING_DIFFERENT'}
 }else{
  $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive))
  & $script:transitionModule {param($p,$b) Write-TransitionAtomic $p $b 'NEW'} $archive $Fixture.ClosedBytes
 }
 if((Id $archive)-cne$Fixture.ClosedIdentity){throw 'ARCHIVE_READBACK_DRIFT'}
 $receipt=Get-Content -LiteralPath $Fixture.Locators.discoverReceipt -Raw|ConvertFrom-Json -Depth 100
 $package=Get-Content -LiteralPath $Fixture.Locators.package -Raw|ConvertFrom-Json -Depth 100
 $boundary=Get-Content -LiteralPath $Fixture.Locators.finalizeInput -Raw|ConvertFrom-Json -Depth 100
 $evidence=@(Import-Module (Join-Path $script:fixtureVersion 'scripts/ResultEvidence.psm1') -PassThru)[0]
 $ctx=& $evidence.ExportedCommands['New-AiwPackageEvidenceContext'] $root $package $script:framework @($receipt.binding.forbiddenScope) -TaskPath $Fixture.ActivePath -ProtectedPaths @($receipt.binding.protectedScope)
 & $evidence.ExportedCommands['Assert-AiwTaskClosure'] $ctx ([Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($archive))) TRANSITION-001 $boundary -RequireExplicitClosure
 # This deliberate interruption leaves both valid cards, never neither.
 if($SaveOnly){return}
 if((Id $active)-cne$Fixture.ActiveIdentity){throw 'ARCHIVE_ACTIVE_PREIMAGE_DRIFT'}
 [IO.File]::Delete($active)
}
function Test-OrdinaryArchive {
 $f=New-OrdinaryArchiveFixture -MissingUserGate
 Expect-Rejected {Save-OrdinaryArchive $f} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'ordinary-archive-missing-real-success-gate-keeps-active'
 Assert-True ([IO.File]::Exists($f.TaskPath)-and(Id $f.TaskPath)-ceq$f.ActiveIdentity-and[IO.File]::Exists((Join-Path $f.Project $f.ArchivePath))) 'archive-saved-but-not-accepted-never-deletes-active'
 $fin=Get-Content -LiteralPath $f.Locators.finalizeInput -Raw|ConvertFrom-Json -Depth 100
 $fin|Add-Member deliveryContext ([pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'})
 $fin.publicDecisionIdentity=Id $f.Decision;Write-Json $f.Locators.finalizeInput $fin
 $pkg=Get-Content -LiteralPath $f.Locators.package -Raw|ConvertFrom-Json -Depth 100
 $mixed=$pkg|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $extra='.ai-workspace/tasks/active/unrelated.md';Write-Text (Join-Path $f.Project $extra) 'Unrelated fixture card.'
 $mixed.exactPaths+=@($extra);$mixed.objectIdentities+=@([pscustomobject]@{path=$extra;identity=(Id (Join-Path $f.Project $extra))})
 $checked=Check-OrdinaryArchivePackage $f $mixed (Join-Path ([IO.Path]::GetDirectoryName($f.Locators.package)) 'mixed.json')
 Assert-True ($checked.Code-ne0-and$checked.Text.Contains('CONTROL_CURRENT_TASK_MIXED_SCOPE')) 'ordinary-archive-exception-does-not-authorize-unrelated-mixed-write'
 $archive=Join-Path $f.Project $f.ArchivePath;$savedTime=[IO.File]::GetLastWriteTimeUtc($archive)
 Save-OrdinaryArchive $f -SaveOnly
 Assert-True ([IO.File]::Exists($f.TaskPath)-and(Id $archive)-ceq$f.ClosedIdentity-and[IO.File]::GetLastWriteTimeUtc($archive)-eq$savedTime) 'ordinary-archive-interruption-and-identical-archive-reuse-do-not-rewrite'
 Save-OrdinaryArchive $f
 Assert-True (-not[IO.File]::Exists($f.TaskPath)-and(Id $archive)-ceq$f.ClosedIdentity) 'ordinary-archive-body-id-independent-of-basename-save-before-delete'
 # A fresh native boundary process consumes the original receipt after deletion,
 # including execution context, snapshot, task binding and acceptance.
 [IO.File]::AppendAllText($archive,'Third-party bytes.',$utf8)
 $bad=Run-Process $f.Locators.finalizeInput
 Assert-True ($bad.Code-ne0-and$bad.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) 'original-finalize-rejects-third-party-archive-bytes-after-active-delete'
 Assert-True ([IO.File]::Exists($f.RetryInput)-and(Id $f.ProofLeaf)-ceq$f.ProofIdentity) 'archive-failed-finalize-keeps-real-producer-input-and-report-proof-for-recovery'
 [IO.File]::WriteAllBytes($archive,$f.ClosedBytes)
 $done=Run-Process $f.Locators.finalizeInput;Must-Pass $done 'ORDINARY_ARCHIVE_ORIGINAL_FINALIZE'
 Assert-True ($done.Value.runtimeCleanup.status-ceq'RETAINED'-and$done.Value.runtimeCleanup.removed.Count-eq1-and-not[IO.File]::Exists($f.RetryInput)-and[IO.File]::Exists($f.Locators.discoverReceipt)-and[IO.File]::Exists($f.Locators.finalizeInput)-and[IO.File]::Exists($f.Decision)) 'archive-default-production-consumer-collects-real-producer-expiry-with-no-path-array'
 foreach($kept in $f.KeptInputs){Assert-True ([IO.File]::Exists($kept.path)-and(Id $kept.path)-ceq$kept.identity) ('archive-keeps-recreated-changed-failed-unknown-policy-input-'+[IO.Path]::GetFileName($kept.path))}
 Assert-True (@($done.Value.runtimeCleanup.observations|Where-Object {$_.reason-ceq'CONSUMED_OBJECT_CHANGED'}).Count-eq1-and@($done.Value.runtimeCleanup.observations|Where-Object {$_.reason-ceq'HOST_POLICY_REJECTED'}).Count-eq1) 'archive-default-cleanup-reports-changed-bytes-and-original-policy-reason'
 $retained=Run-Process $f.Locators.finalizeInput -ConsumedRuntimePath @($f.ProofLeaf);Must-Pass $retained 'ORDINARY_ARCHIVE_REPORT_RETENTION'
 Assert-True ($retained.Value.runtimeCleanup.status-ceq'RETAINED'-and$f.ProofLeaf-cin$retained.Value.runtimeCleanup.retained-and(Id $f.ProofLeaf)-ceq$f.ProofIdentity) 'archive-plan-report-outside-runtime-retains-listed-runtime-proof'
 Assert-True ($done.Value.actionOutcome-ceq'OBSERVED'-and-not(Test-Path -LiteralPath $f.PlanPath)-and-not(Test-Path -LiteralPath (Join-Path $f.Project '.ai-workspace/runtime/control-transition.active.json'))-and-not(Test-Path -LiteralPath $f.Locators.completionProof)) 'ordinary-archive-original-finalize-completes-without-plan-marker-journal-or-proof'
 foreach($blocked in @('PROJECT_EXCLUDED','FRAMEWORK_RELATIVE_PROTECTED')){
  $guarded=New-OrdinaryArchiveFixture -BlockedProof $blocked
  try{
   $fin=Get-Content -LiteralPath $guarded.Locators.finalizeInput -Raw|ConvertFrom-Json -Depth 100
   $fin|Add-Member deliveryContext ([pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'})
   Write-Json $guarded.Locators.finalizeInput $fin;Save-OrdinaryArchive $guarded
   $guard=Run-Process $guarded.Locators.finalizeInput;Must-Pass $guard ('ORDINARY_ARCHIVE_GUARD_'+$blocked)
   Assert-True ($guard.Value.runtimeCleanup.status-ceq'REJECTED'-and$guard.Value.runtimeCleanup.reason-ceq'EVIDENCE_PATH_FORBIDDEN'-and[IO.File]::Exists($guarded.RetryInput)) ('archive-full-root-aware-guard-before-linked-read-or-delete-'+$blocked)
  }finally{$guarded.SentinelHold.Dispose()}
 }
 foreach($outcome in @('CANCELLED','SUPERSEDED')){
  $f=New-OrdinaryArchiveFixture -Outcome $outcome
  $fin=Get-Content -LiteralPath $f.Locators.finalizeInput -Raw|ConvertFrom-Json -Depth 100
  $fin|Add-Member deliveryContext ([pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'})
  Write-Json $f.Locators.finalizeInput $fin
  Save-OrdinaryArchive $f;$done=Run-Process $f.Locators.finalizeInput -ConsumedRuntimePath @($f.Decision);Must-Pass $done ('ORDINARY_ARCHIVE_'+$outcome)
  Assert-True ($done.Value.runtimeCleanup.status-ceq'RETAINED'-and$f.Decision-cin$done.Value.runtimeCleanup.retained-and[IO.File]::Exists($f.Decision)) ('ordinary-archive-'+$outcome.ToLowerInvariant()+'-without-plan-keeps-real-closure-decision')
  Assert-True (-not[IO.File]::Exists($f.TaskPath)-and$done.Value.actionOutcome-ceq'OBSERVED') ('ordinary-archive-'+$outcome.ToLowerInvariant()+'-keeps-real-decision-and-unfinished-transfer')
 }
}

$versionRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:temp=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('aiw-control-transition-'+[guid]::NewGuid().ToString('N'))))
if($Group-ceq'OrdinaryArchive'-and$env:AIW_TEST_RAW_DIRECTORY){$script:temp=Join-Path $env:AIW_TEST_RAW_DIRECTORY ('aiw-control-transition-'+[guid]::NewGuid().ToString('N'))}
$originalActor=$env:CODEX_THREAD_ID;$complete=$false
try {
    $script:framework=Join-Path $script:temp 'framework-root';$fixtureVersion=Join-Path $script:framework 'framework/versions/2.0.0'
    $sourceRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
    $script:fixtureVersion=New-AiwTestMechanismFixture $sourceRoot $script:framework (Join-Path $PSScriptRoot 'test-groups.json')
    $script:resolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
    $script:transitionModule=@(Import-Module (Join-Path $fixtureVersion 'scripts/ControlTransition.psm1') -Force -PassThru)[0]

    if($Group-cin@('PlanShape','NativeIO')){
        $f=New-Fixture -PreparationOnly;$env:CODEX_THREAD_ID='old-actor';$before=Snapshot $f
        $expected=Transition $f 'PREVIEW';$requestPath=Join-Path ([IO.Path]::GetDirectoryName($f.PlanPath)) 'native-preview.json'
        $request=[ordered]@{operation='PREVIEW';projectRoot=$f.Project;planPath=$f.PlanPath;expectedPlanIdentity=(Id $f.PlanPath);recoveryMode='NOT_APPLICABLE'};Write-Json $requestPath $request
        $entry=Join-Path $script:fixtureVersion 'scripts/resolve-control-transition.ps1'
        $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$entry,'-InputPath',$requestPath,'-AsJson') -WorkingDirectory $f.Project -GroupId 'control-native-preview'
        $value=$native.StdoutText|ConvertFrom-Json -Depth 100
        Assert-True ($native.Code-eq0-and$native.StderrText-ceq''-and$native.StdoutText-notmatch'[^\x00-\x7f]'-and($value|ConvertTo-Json -Depth 100 -Compress)-ceq($expected|ConvertTo-Json -Depth 100 -Compress)-and(Snapshot $f)-ceq$before-and-not(Test-Path -LiteralPath (Join-Path $f.Project '.ai-workspace/runtime/control-transition.active.json'))) 'control-native-preview-complete-unicode-path-result-zero-write'
        $request.expectedPlanIdentity='0|'+('0'*64);Write-Json $requestPath $request
        $rejected=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$entry,'-InputPath',$requestPath,'-AsJson') -WorkingDirectory $f.Project -GroupId 'control-native-rejected'
        $failure=$rejected.StdoutText|ConvertFrom-Json -Depth 100
        Assert-True ($rejected.Code-eq2-and$rejected.StderrText-ceq''-and@($failure.PSObject.Properties).Count-eq2-and$failure.status-ceq'FAIL'-and$failure.reason-ceq'TRANSITION_PLAN_DRIFT'-and(Snapshot $f)-ceq$before) 'control-native-rejects-actual-plan-drift-single-json-zero-write'
        if($Group-ceq'NativeIO'){$complete=$true;Write-Output 'EVIDENCE_CEILING|PARTIAL|control-native-io';return}
    }
    if($Group-ceq'OrdinaryArchive'){Test-OrdinaryArchive;$complete=$true;Write-Output ('CONTROL_TRANSITION_TESTS_PASS|checks='+$script:passed+'|group='+$Group+'|fixture='+$script:temp);return}
    if($Group-ceq'PlanShape'){
    $f=New-Fixture -PreparationOnly;$baselinePlan=[IO.File]::ReadAllBytes($f.PlanPath)
    $valid=& $script:transitionModule.ExportedFunctions['Read-AiwControlTransitionPlan'] $f.Project $f.PlanPath (Id $f.PlanPath)
    Assert-True ($valid.Paths.Count-eq2) 'real-plan-reader-valid-baseline'
    foreach($mutation in @('TASK_ID','CONTROLLER_EPOCH','STEP_ORDER','PROJECT_PIN','EXTRA_FIELD')){
        [IO.File]::WriteAllBytes($f.PlanPath,$baselinePlan);$before=Snapshot $f;$plan=Get-Content $f.PlanPath -Raw|ConvertFrom-Json
        switch($mutation){
            'TASK_ID' {$text=$utf8.GetString([Convert]::FromBase64String($plan.objects[1].after.base64)).Replace('TRANSITION-001','ALIEN-001');$plan.objects[1].after=Image $text}
            'CONTROLLER_EPOCH' {$value=$utf8.GetString([Convert]::FromBase64String($plan.objects[0].after.base64))|ConvertFrom-Json;$value.controllerEpoch=9;$plan.objects[0].after=Image (Json-Text $value)}
            'STEP_ORDER' {$swap=$plan.steps[0];$plan.steps[0]=$plan.steps[1];$plan.steps[1]=$swap}
            'PROJECT_PIN' {$plan.objects[0].path='.ai-workspace/project.json'}
            'EXTRA_FIELD' {$plan|Add-Member -NotePropertyName allowAnything -NotePropertyValue $true}
        }
        Write-Json $f.PlanPath $plan;Expect-Rejected {& $script:transitionModule.ExportedFunctions['Read-AiwControlTransitionPlan'] $f.Project $f.PlanPath (Id $f.PlanPath)} 'TRANSITION_' ('invalid-plan-'+$mutation);Assert-True ((Snapshot $f)-ceq$before) ('invalid-plan-zero-overwrite-'+$mutation)
    }
    [IO.File]::WriteAllBytes($f.PlanPath,$baselinePlan)
    $complete=$true;Write-Output ('CONTROL_TRANSITION_TESTS_PASS|checks='+$script:passed+'|group='+$Group);return
    }
    $f=New-Fixture
    $original=Get-Content -LiteralPath $f.Locators.discoverReceipt -Raw|ConvertFrom-Json -Depth 100
    Assert-True ($f.Preview.status-ceq'PREVIEW'-and$f.Preview.derivedImages.Count-eq2-and'TARGET_PREP_REQUIRED'-cin@($f.Preview.targetRuleBlocks.preparationRequirements)-and'TARGET_RESULT_REQUIRED'-cin@($f.Preview.targetRuleBlocks.resultRequirements)-and'TARGET_PREP_REQUIRED'-cnotin@($original.selectedObligations.preparationRequirements)-and'TARGET_RESULT_REQUIRED'-cnotin@($original.selectedObligations.resultRequirements)) 'preview-freezes-derived-images-and-new-target-obligations-outside-original-selection'
    $applied=Transition $f 'APPLY';Assert-True ($applied.status-ceq'APPLIED'-and-not(Test-Path $f.Locators.completionProof)) 'apply-does-not-claim-finalize-or-completion'
    $ordinary=Run-Process $f.Locators.discoverInput;Assert-True ($ordinary.Code-ne0-and$ordinary.Text.Contains('CONTROL_TRANSITION_RECOVERY_REQUIRED')) 'ordinary-actions-reject-in-progress-controller'
    $old=Snapshot $f;$env:CODEX_THREAD_ID='third-party';Expect-Rejected {Transition $f 'RECOVER' 'CONTINUE'} 'TRANSITION_RECOVERY_ACTOR' 'unauthorized-recovery-actor';Assert-True ((Snapshot $f)-ceq$old) 'wrong-actor-zero-overwrite';$env:CODEX_THREAD_ID='new-actor'
    Write-Finalize $f -OmitTarget;$missing=Run-Process $f.Locators.finalizeInput
    Assert-True ($missing.Code-eq3-and$missing.Value.status-ceq'BLOCKED'-and$missing.Value.reason-ceq'RESULT_INCOMPLETE'-and($missing.Value.missingResult-join',')-ceq'TARGET_RESULT_REQUIRED'-and-not(Test-Path $f.Locators.completionProof)-and(Snapshot $f)-ceq$old) 'original-finalize-enforces-new-target-result-without-cleanup'
    Write-Finalize $f -OmitTargetPrep;$missing=Run-Process $f.Locators.finalizeInput
    Assert-True ($missing.Code-eq3-and$missing.Value.status-ceq'BLOCKED'-and$missing.Value.reason-ceq'PREPARATION_INCOMPLETE'-and($missing.Value.missingPreparation-join',')-ceq'TARGET_PREP_REQUIRED'-and-not(Test-Path $f.Locators.completionProof)-and(Snapshot $f)-ceq$old) 'original-finalize-enforces-new-target-preparation-without-cleanup'
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

    # A protected candidate is a genuine refusal, not a valid handoff prerequisite.
    $f=New-Fixture -ProtectControl;$initial=Snapshot $f;$null=Transition $f 'APPLY';$marked=Snapshot $f;$env:CODEX_THREAD_ID='new-actor'
    $protected=Run-Process $f.Locators.finalizeInput
    Assert-True ($protected.Code-eq2-and$protected.Value.reason-ceq'EVIDENCE_PATH_FORBIDDEN'-and-not(Test-Path $f.Locators.completionProof)-and(Snapshot $f)-ceq$marked) 'protected-control-candidate-refusal-retains-original-markers'
    $rolled=Transition $f 'RECOVER' 'ROLLBACK';Assert-True ($rolled.status-ceq'ROLLED_BACK'-and(Snapshot $f)-ceq$initial) 'protected-control-refusal-can-restore-original-chain'

    foreach($kind in @('TaskOnly','ControllerOnly','AnotherTask','CriticalTarget')){
        $arguments=@{};$arguments[$kind]=$true;$f=New-Fixture @arguments;$null=Transition $f 'APPLY';$env:CODEX_THREAD_ID='new-actor'
        if($kind-ceq'AnotherTask'){
            $marked=Snapshot $f;Write-Finalize $f -OmitTarget;$missing=Run-Process $f.Locators.finalizeInput
            Assert-True ($missing.Code-eq3-and$missing.Value.reason-ceq'RESULT_INCOMPLETE'-and($missing.Value.missingResult-join',')-ceq'TARGET_RESULT_REQUIRED'-and-not(Test-Path $f.Locators.completionProof)-and(Snapshot $f)-ceq$marked) 'second-target-exclusive-result-is-required-when-first-task-is-unchanged'
            Write-Finalize $f
        }
        $null=Transition $f 'FINALIZE';$done=Transition $f 'COMPLETE';Assert-True ($done.status-ceq'COMPLETE') ('directional-transition-'+$kind)
    }
    # These fresh chains distinguish permission drift, original selected bytes,
    # and a dependency selected only by the second target composition.
    foreach($drift in @('PERMISSION','ORIGINAL_BODY','TARGET_DEPENDENCY')){
        $f=New-Fixture -AnotherTask -SourceClosure
        $original=Get-Content -LiteralPath $f.Locators.discoverReceipt -Raw|ConvertFrom-Json -Depth 100
        Assert-True ('ORIGINAL_SOURCE_RESULT'-cin@($original.selectedObligations.resultRequirements)-and'TARGET_RESULT_REQUIRED'-cnotin@($original.selectedObligations.resultRequirements)-and'TARGET_RESULT_REQUIRED'-cin@($f.Preview.targetRuleBlocks.resultRequirements)) ('source-fixture-binds-distinct-original-and-second-target-closures-'+$drift)
        $null=Transition $f 'APPLY';$env:CODEX_THREAD_ID='new-actor';$marked=Snapshot $f
        $path=switch($drift){'PERMISSION'{Join-Path $f.Project '.ai-workspace/project.json'}'ORIGINAL_BODY'{Join-Path $f.Project 'standards/original.md'}'TARGET_DEPENDENCY'{Join-Path $f.Project 'standards/dependency.md'}}
        $before=[IO.File]::ReadAllBytes($path)
        if($drift-ceq'PERMISSION'){
            $config=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 100
            $config.sourceBindings[0].allowedPaths=@($config.sourceBindings[0].allowedPaths|Where-Object locator -CNE 'dependency.md');Write-Json $path $config
            $expected='TRANSITION_SOURCE_DRIFT|projectConfigIdentity'
        }else{[IO.File]::AppendAllText($path,'Unadopted changed bytes.',$utf8);$expected='CONTENT_IDENTITY_DRIFT|DOCUMENT'}
        $rejected=Run-Process $f.Locators.finalizeInput
        Assert-True ($rejected.Code-eq2-and$rejected.Value.status-ceq'FAIL'-and$rejected.Value.reason-ceq$expected-and-not(Test-Path $f.Locators.completionProof)-and(Snapshot $f)-ceq$marked) ('real-original-finalize-rejects-'+$drift+'|'+$rejected.Text)
        [IO.File]::WriteAllBytes($path,$before)
        $restored=Run-Process $f.Locators.finalizeInput;Must-Pass $restored ('RESTORED_SOURCE_'+$drift)
        $done=Transition $f 'COMPLETE';Assert-True ($done.status-ceq'COMPLETE') ('restored-source-completes-same-original-chain-'+$drift)
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
    $complete=$true;Write-Output ('CONTROL_TRANSITION_TESTS_PASS|checks='+$script:passed+'|group='+$Group)
} finally {
    if($null-ne(Get-Variable transitionModule -Scope Script -ErrorAction SilentlyContinue)){Clear-Checkpoint}
    $env:CODEX_THREAD_ID=$originalActor
    if($complete-and$Group-cne'OrdinaryArchive'){
        $root=[IO.Path]::GetFullPath($script:temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
        if([IO.Path]::GetDirectoryName($root)-cne$parent-or[IO.Path]::GetFileName($root)-cnotmatch'^aiw-control-transition-[0-9a-f]{32}$'){throw 'FIXTURE_CLEANUP_SCOPE'}
        Remove-Item -LiteralPath $root -Recurse -Force
    }elseif($complete){Write-Output ('FIXTURE_RETAINED|'+$script:temp)}else{Write-Output ('FAILED_FIXTURE_RETAINED|'+$script:temp)}
}
