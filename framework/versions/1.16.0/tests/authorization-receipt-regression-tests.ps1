[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Write-Json([string]$Path,$Value){Write-Utf8 $Path ($Value|ConvertTo-Json -Depth 50)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}

$checker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\check-authorization.ps1'))
$receiverBinder=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\bind-receiver-authorization.ps1'))
$taskChecker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\check-task-card.ps1'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-authorization-receipt-'+[guid]::NewGuid().ToString('N'))
$control=Join-Path $temp '.ai-workspace'
$taskRelative='.ai-workspace/tasks/active/AUTH-REGRESSION-001.md'
$taskPath=Join-Path $temp $taskRelative
$objectRelative='src/item.txt'
$objectPath=Join-Path $temp $objectRelative
$packagePath=Join-Path $control 'authorization.json'

function Write-Task([string]$Profile,[string]$Phase,[string]$Lifecycle='ACTIVE',[switch]$OwnerRoute){
  $currentExact=if($Profile-ceq'CRITICAL'){" current_exact=$objectRelative;"}else{''}
  $criticalLines=if($Profile-ceq'CRITICAL'){"- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=bind the package profile to the current task; added_machinery=NONE; escalation_trigger=another independent profile-binding defect`n- Phase gate: FALSE`n"}else{''}
  $route=if($OwnerRoute-or$Phase-ceq'GIT'){'actor=owner-fixture; role=DOMAIN_OWNER'}else{'actor=writer-fixture; role=EXECUTOR'}
  Write-Utf8 $taskPath ("# AUTH-REGRESSION-001 - authorization regression fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: $route; phase=$Phase`n- Range summary: profile=$Profile; lifecycle=$Lifecycle;$currentExact expected_paths=[$objectRelative]; actual_paths=[]`n$criticalLines")
}

function New-Package([string]$Profile,[string]$IssuerRole,[string]$Grantee,[string]$Action,[string]$DecisionClass,[string]$Issuer='owner-fixture'){
  $invalidators=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')
  $package=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';taskId='AUTH-REGRESSION-001';profile=$Profile;lifecycle='ACTIVE';owner='owner-fixture';issuer=$Issuer;issuerRole=$IssuerRole;grantee=$Grantee;bundle='PLAN_LOCAL';decisionClass=$DecisionClass;userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@($Action);exactPaths=@($objectRelative);objectIdentities=@([ordered]@{path=$objectRelative;identity=Get-Identity $objectPath});invalidatesOn=$invalidators;projectConfigIdentity=Get-Identity (Join-Path $control 'project.json')}
  if($IssuerRole-ceq'PROJECT_CONTROLLER'){
    $package['issuerControllerId']='controller-fixture';$package['issuerControllerEpoch']=1;$package['controllerControlIdentity']=Get-Identity (Join-Path $control 'controller.json');$package['invalidatesOn']+=@('CONTROLLER_EPOCH_CHANGE')
  }
  if($Profile-ceq'CRITICAL'-and$Action-ceq'REVIEW_EXECUTE'){
    $package['reviewIndependence']='INDEPENDENT';$package['candidateWriter']='writer-fixture';$package['materialContributors']=@();$package['invalidatesOn']+=@('CONTRIBUTOR_SET_CHANGE')
  }
  return $package
}

function Invoke-Check($Package,[string]$Actor,[string]$Action){
  Write-Json $packagePath $Package
  $repositoryId=if([int]$Package.schemaVersion-eq2){[string]$Package.repositoryId}else{'REPO_LOCAL'}
  $observedObjectIdentity=if(Test-Path -LiteralPath $objectPath -PathType Leaf){Get-Identity $objectPath}else{'NEW'}
  $arguments=@('-NoProfile','-NonInteractive','-File',$checker,'-PackagePath',$packagePath,'-ObservedActor',$Actor,'-ObservedTaskId','AUTH-REGRESSION-001','-ObservedOwner','owner-fixture','-ObservedAction',$Action,'-ObservedPath',$objectRelative,'-ObservedIdentity',($objectRelative+'='+$observedObjectIdentity),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId',$repositoryId,'-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',(Get-Identity (Join-Path $control 'project.json')),'-TaskPath',$taskRelative,'-ExpectedTaskIdentity',(Get-Identity $taskPath))
  if([int]$Package.schemaVersion-eq2){$arguments+=@('-RootRepositoryBindingValidated')}
  Push-Location $temp
  try{$output=@(& pwsh @arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{Pop-Location}
  return [pscustomobject]@{Code=$code;Text=($output-join"`n")}
}

function Invoke-TaskCheck(){
  $arguments=@('-NoProfile','-NonInteractive','-File',$taskChecker,'-TaskPath',$taskPath)
  $output=@(& pwsh @arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
  return [pscustomobject]@{Code=$code;Text=($output-join"`n")}
}

New-Item -ItemType Directory -Path (Join-Path $control 'tasks\active') -Force|Out-Null
try{
  & git -C $temp init -q
  if($LASTEXITCODE-ne0){throw 'GIT_INIT_FAILED'}
  Write-Json (Join-Path $control 'project.json') ([ordered]@{schemaVersion=3;id='authorization-receipt-fixture';displayName='Authorization Receipt Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{}})
  Write-Json (Join-Path $control 'controller.json') ([ordered]@{schemaVersion=1;projectId='authorization-receipt-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
  Write-Utf8 $objectPath 'fixture object'

  Write-Task 'STANDARD' 'IMPLEMENT' 'ACTIVE_WRITE'
  $externalTaskCheck=Invoke-TaskCheck
  Assert-True ($externalTaskCheck.Code-eq0) 'task-card-active-write-allows-external-authorization-carrier'
  $externalPackage=New-Package 'STANDARD' 'DOMAIN_OWNER' 'writer-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL'
  $externalAuthorization=Invoke-Check $externalPackage 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($externalAuthorization.Code-eq0) 'external-authorization-package-binds-stable-task-preimage'
  $externalTaskText=Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath
  $fence=[string]::new([char]0x60,3)
  $inlineBlock=$fence+"authorization-package`n"+($externalPackage|ConvertTo-Json -Depth 50)+"`n"+$fence+"`n"
  Write-Utf8 $taskPath ($externalTaskText.TrimEnd("`n")+"`n`n"+$inlineBlock)
  $singleInlineTaskCheck=Invoke-TaskCheck
  Assert-True ($singleInlineTaskCheck.Code-eq0) 'task-card-single-inline-authorization-remains-structurally-compatible'
  Write-Utf8 $taskPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath).TrimEnd("`n")+"`n`n"+$inlineBlock)
  $duplicateInlineTaskCheck=Invoke-TaskCheck
  Assert-True ($duplicateInlineTaskCheck.Code-ne0-and$duplicateInlineTaskCheck.Text.Contains('AUTHORIZATION_BLOCK_COUNT')) 'task-card-rejects-multiple-inline-authorization-blocks'

  Write-Task 'STANDARD' 'IMPLEMENT'
  $standard=Invoke-Check (New-Package 'STANDARD' 'DOMAIN_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($standard.Code-eq0) 'authorization-canonical-standard-package-passes'

  # The original issuer fixes every authorization field before creating a
  # receiver; the receiver supplies only the host ID and initial delegation ID.
  $receiverActor='01a0eeee-1111-7222-8333-444444444444';$delegationId='fixture-initial-implementer-001'
  $pendingTemplate=New-Package 'STANDARD' 'DOMAIN_OWNER' 'UNBOUND_RECEIVER' 'SOURCE_WRITE' 'ROUTINE_LOCAL'
  $pendingTemplate.schemaVersion=2;$pendingTemplate['repositoryId']='REPO_LOCAL';$pendingTemplate.actions=@('SOURCE_WRITE','TEST_RUN');$pendingTemplate['continuationPlan']=@('SOURCE_WRITE','TEST_RUN');$pendingTemplate.invalidatesOn+=@('REPOSITORY_CHANGE','CONTINUATION_RESULT_DRIFT')
  $pending=[ordered]@{schemaVersion=1;delegationId=$delegationId;receiverRole='IMPLEMENTER';authorizationTemplate=$pendingTemplate}
  $pendingPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-implementer.json';Write-Json $pendingPath $pending
  Assert-True ((Invoke-Check $pendingTemplate 'UNBOUND_RECEIVER' 'SOURCE_WRITE').Code-ne0) 'unbound-receiver-template-cannot-execute'
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$receiverActor
    $wrongDelegation=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId 'wrong-initial-delegation' 2>&1|ForEach-Object{[string]$_});$wrongDelegationCode=$LASTEXITCODE
    Assert-True ($wrongDelegationCode-ne0-and($wrongDelegation-join"`n").Contains('INITIAL_DELEGATION_MISMATCH')) 'receiver-rejects-wrong-initial-delegation'
    $wrongIdentity=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity ('1|'+('0'*64)) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$wrongIdentityCode=$LASTEXITCODE
    Assert-True ($wrongIdentityCode-ne0-and($wrongIdentity-join"`n").Contains('PENDING_IDENTITY_DRIFT')) 'receiver-rejects-tampered-pending-authorization'
    $boundResult=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$boundCode=$LASTEXITCODE
    $boundPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$receiverActor+'/receiver-authorization-'+$delegationId+'.json')
    Assert-True ($boundCode-eq0-and(Test-Path -LiteralPath $boundPath -PathType Leaf)-and($boundResult-join"`n").Contains('PASS|package=')) 'receiver-generates-bound-package-in-own-process-directory'
    $bound=Get-Content -LiteralPath $boundPath -Raw|ConvertFrom-Json -Depth 100
    Assert-True ((Invoke-Check $bound $receiverActor 'SOURCE_WRITE').Code-eq0-and[string]::Join(',',@($bound.continuationPlan))-ceq'SOURCE_WRITE,TEST_RUN') 'receiver-bound-implementer-preserves-combined-write-test-continuation'
    $forbiddenTemplate=$pendingTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forbiddenTemplate.actions=@('SOURCE_WRITE','PUSH')
    $forbiddenId='fixture-initial-implementer-push-001';$forbiddenPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-implementer-push.json'
    Write-Json $forbiddenPending ([ordered]@{schemaVersion=1;delegationId=$forbiddenId;receiverRole='IMPLEMENTER';authorizationTemplate=$forbiddenTemplate})
    $forbiddenBind=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $forbiddenPending -ExpectedPendingIdentity (Get-Identity $forbiddenPending) -ReceivedDelegationId $forbiddenId 2>&1|ForEach-Object{[string]$_});$forbiddenCode=$LASTEXITCODE
    Assert-True ($forbiddenCode-ne0-and($forbiddenBind-join"`n").Contains('RECEIVER_ROLE_ACTION')) 'receiver-implementer-rejects-unrelated-push-action'
    $beforeResume=Get-Identity $boundPath
    $resume=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$resumeCode=$LASTEXITCODE
    Assert-True ($resumeCode-eq0-and($resume-join"`n").Contains('PASS|package=')-and(Get-Identity $boundPath)-ceq$beforeResume) 'healthy-receiver-reuses-identical-bound-package'
    $expanded=$bound|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$expanded.exactPaths=@($objectRelative,'src/extra.txt')
    $expandedResult=Invoke-Check $expanded $receiverActor 'SOURCE_WRITE'
    Assert-True ($expandedResult.Code-ne0-and$expandedResult.Text.Contains('RECEIVER_AUTHORITY_EXPANDED')) 'receiver-cannot-expand-original-scope'
    $env:CODEX_THREAD_ID='01a0eeee-9999-7222-8333-444444444444'
    $wrongHost=Invoke-Check $bound $receiverActor 'SOURCE_WRITE'
    Assert-True ($wrongHost.Code-ne0-and$wrongHost.Text.Contains('RECEIVER_HOST_IDENTITY')) 'bound-package-rejects-other-host-actor'
    $redirectActor='01a0eeee-7777-7222-8333-444444444444';$outside=Join-Path $temp 'receiver-redirect-target';New-Item -ItemType Directory -Path $outside|Out-Null
    $redirectPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$redirectActor)
    New-Item -ItemType Junction -Path $redirectPath -Target $outside|Out-Null
    $env:CODEX_THREAD_ID=$redirectActor
    $redirect=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$redirectCode=$LASTEXITCODE
    Assert-True ($redirectCode-ne0-and($redirect-join"`n").Contains('RECEIVER_OUTPUT_REPARSE')-and@(Get-ChildItem -LiteralPath $outside -Force).Count-eq0) 'receiver-rejects-output-junction-before-any-external-write'
  }finally{$env:CODEX_THREAD_ID=$oldHostId}

  $investigatorActor='01a0eeee-2222-7222-8333-444444444444';$investigatorId='fixture-initial-investigator-001'
  $investigatorTemplate=New-Package 'STANDARD' 'DOMAIN_OWNER' 'UNBOUND_RECEIVER' 'TEST_RUN' 'ROUTINE_LOCAL'
  $investigatorTemplate.schemaVersion=2;$investigatorTemplate['repositoryId']='REPO_LOCAL';$investigatorTemplate.invalidatesOn+=@('REPOSITORY_CHANGE')
  $investigatorPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-investigator.json'
  Write-Json $investigatorPending ([ordered]@{schemaVersion=1;delegationId=$investigatorId;receiverRole='INVESTIGATOR';authorizationTemplate=$investigatorTemplate})
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$investigatorActor
    $investigatorBind=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $investigatorPending -ExpectedPendingIdentity (Get-Identity $investigatorPending) -ReceivedDelegationId $investigatorId 2>&1|ForEach-Object{[string]$_});$investigatorCode=$LASTEXITCODE
    $investigatorPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$investigatorActor+'/receiver-authorization-'+$investigatorId+'.json')
    $investigatorBound=if(Test-Path -LiteralPath $investigatorPath -PathType Leaf){Get-Content $investigatorPath -Raw|ConvertFrom-Json -Depth 100}else{$null}
    Assert-True ($investigatorCode-eq0-and$null-ne$investigatorBound-and(Invoke-Check $investigatorBound $investigatorActor TEST_RUN).Code-eq0) 'receiver-bound-investigator-admits-exact-test-run'
  }finally{$env:CODEX_THREAD_ID=$oldHostId}

  $planned=New-Package 'STANDARD' 'DOMAIN_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL';$planned.actions=@('SOURCE_WRITE','TEST_RUN');$planned|Add-Member -NotePropertyName continuationPlan -NotePropertyValue @('SOURCE_WRITE','TEST_RUN','SOURCE_WRITE');$planned.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $plannedInitial=Invoke-Check $planned 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($plannedInitial.Code-eq0) 'authorization-temporary-actor-multi-action-plan-admits-first-step'
  $longPlan=$planned|ConvertTo-Json -Depth 50|ConvertFrom-Json;$longPlan.continuationPlan=@(1..20|ForEach-Object{if($_%2){'SOURCE_WRITE'}else{'TEST_RUN'}})
  Assert-True ((Invoke-Check $longPlan 'executor-fixture' 'SOURCE_WRITE').Code-eq0) 'continuation-accepts-twenty-explicit-bounded-steps'
  $plannedSkip=Invoke-Check $planned 'executor-fixture' 'TEST_RUN'
  Assert-True ($plannedSkip.Code-ne0-and$plannedSkip.Text.Contains('CONTINUATION_ACTION_ORDER_DRIFT')) 'authorization-continuation-plan-rejects-skipped-first-step'
  $missingContinuationInvalidator=$planned|ConvertTo-Json -Depth 50|ConvertFrom-Json;$missingContinuationInvalidator.invalidatesOn=@($missingContinuationInvalidator.invalidatesOn|Where-Object{$_-cne'CONTINUATION_RESULT_DRIFT'});$missingContinuationInvalidatorRun=Invoke-Check $missingContinuationInvalidator 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($missingContinuationInvalidatorRun.Code-ne0-and$missingContinuationInvalidatorRun.Text.Contains('INVALIDATOR_MISSING_CONTINUATION_RESULT_DRIFT')) 'authorization-continuation-plan-requires-result-drift-invalidator'

  $lowerDecision=Invoke-Check (New-Package 'STANDARD' 'DOMAIN_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'routine_local') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($lowerDecision.Code-ne0-and$lowerDecision.Text.Contains('DECISION_CLASS')) 'authorization-decision-class-is-case-sensitive'

  $lowerController=Invoke-Check (New-Package 'STANDARD' 'project_controller' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL' 'controller-fixture') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($lowerController.Code-ne0-and$lowerController.Text.Contains('ISSUER_ROLE')) 'authorization-controller-role-is-case-sensitive'

  # Review dispatch uses the already current task and candidate. When a card
  # still points at the previous freeze, update it before preparing the package.
  Write-Task 'CRITICAL' 'REVIEW'
  $reviewCardBase=Get-Content -Raw -LiteralPath $taskPath
  Write-Utf8 $taskPath ($reviewCardBase.TrimEnd()+"`nCandidate freeze: old-fixture-freeze`n")
  $beforeCardRefresh=New-Package 'CRITICAL' 'DOMAIN_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  Write-Utf8 $taskPath ($reviewCardBase.TrimEnd()+"`nCandidate freeze: current-fixture-freeze`n")
  $currentReview=New-Package 'CRITICAL' 'DOMAIN_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  Assert-True ((Invoke-Check $beforeCardRefresh reviewer-fixture REVIEW_EXECUTE).Code-ne0-and(Invoke-Check $currentReview reviewer-fixture REVIEW_EXECUTE).Code-eq0) 'review-dispatch-refreshes-stale-card-before-binding-current-package'
  $currentCardIdentity=Get-Identity $taskPath
  Assert-True ((Invoke-Check $currentReview reviewer-fixture REVIEW_EXECUTE).Code-eq0-and(Get-Identity $taskPath)-ceq$currentCardIdentity) 'review-dispatch-reuses-already-current-card-without-extra-write'
  Write-Utf8 $taskPath ((Get-Content -Raw -LiteralPath $taskPath).TrimEnd()+"`nCandidate result: changed after dispatch`n")
  Assert-True ((Invoke-Check $currentReview reviewer-fixture REVIEW_EXECUTE).Code-ne0) 'review-dispatch-rejects-real-task-drift-after-send'

  Write-Task 'CRITICAL' 'REVIEW'
  $critical=Invoke-Check (New-Package 'CRITICAL' 'DOMAIN_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL') 'reviewer-fixture' 'REVIEW_EXECUTE'
  Assert-True ($critical.Code-eq0) 'authorization-canonical-independent-critical-review-passes'

  $internal=New-Package 'CRITICAL' 'DOMAIN_OWNER' 'visible-reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  $internalCheck=Invoke-Check $internal 'visible-reviewer-fixture' 'REVIEW_EXECUTE'
  Assert-True ($internalCheck.Code-eq0) 'review-authorization-accepts-distinct-visible-actor-with-bound-identity'
  foreach($excluded in @('owner-fixture','writer-fixture','contributor-fixture')){
    $bad=New-Package 'CRITICAL' 'DOMAIN_OWNER' $excluded 'REVIEW_EXECUTE' 'ROUTINE_LOCAL';$bad.materialContributors=@('contributor-fixture')
    $badCheck=Invoke-Check $bad $excluded 'REVIEW_EXECUTE'
    Assert-True ($badCheck.Code-ne0) ('reviewer-role-does-not-waive-identity-exclusion-'+$excluded)
  }
  $unknownCheck=Invoke-Check $internal 'unknown-reviewer-actor' 'REVIEW_EXECUTE'
  Assert-True ($unknownCheck.Code-ne0) 'review-authorization-rejects-unbound-actual-reviewer-identity'

  $lowerProfile=Invoke-Check (New-Package 'critical' 'DOMAIN_OWNER' 'owner-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL') 'owner-fixture' 'REVIEW_EXECUTE'
  Assert-True ($lowerProfile.Code-ne0-and$lowerProfile.Text.Contains('PROFILE')) 'authorization-critical-profile-is-case-sensitive'

  $profileMismatch=Invoke-Check (New-Package 'STANDARD' 'DOMAIN_OWNER' 'owner-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL') 'owner-fixture' 'REVIEW_EXECUTE'
  Assert-True ($profileMismatch.Code-ne0-and$profileMismatch.Text.Contains('TASK_PROFILE_DRIFT')) 'authorization-package-profile-matches-task-range-profile'
  Write-Task 'CRITICAL' 'IMPLEMENT'
  $parent=New-Package 'CRITICAL' 'DOMAIN_OWNER' 'writer-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL'
  $parent.repairReviewPlan=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@()}
  $parentCheck=Invoke-Check $parent 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($parentCheck.Code-eq0) 'owner-can-preauthorize-bounded-repair-review-without-changing-work-route'
  $largerPlan=$parent|ConvertTo-Json -Depth 50|ConvertFrom-Json;$largerPlan.repairReviewPlan.maxCycles=12
  Assert-True ((Invoke-Check $largerPlan 'writer-fixture' 'SOURCE_WRITE').Code-eq0) 'repair-review-accepts-task-selected-finite-plan-over-eight'
  $largerPlan.repairReviewPlan.maxCycles=0
  Assert-True ((Invoke-Check $largerPlan 'writer-fixture' 'SOURCE_WRITE').Code-ne0) 'repair-review-still-requires-positive-bounded-plan'
  $parentPath=Join-Path $control 'repair-parent.json';Write-Json $parentPath $parent
  $verdict=[ordered]@{taskId='AUTH-REGRESSION-001';owner='owner-fixture';reviewer='reviewer-fixture';writer='writer-fixture';cycle=0;verdict='CHANGES_REQUESTED';exactPaths=@($objectRelative);objectIdentities=@($parent.objectIdentities);findingPaths=@($objectRelative);scopeChanged=$false;decisionChanged=$false}
  $verdictPath=Join-Path $control 'repair-verdict.json';Write-Json $verdictPath $verdict
  $binding=[ordered]@{parentPackagePath=$parentPath;parentPackageIdentity=(Get-Identity $parentPath);phase='REPAIR';cycle=1;verdictPath=$verdictPath;verdictIdentity=(Get-Identity $verdictPath);repairFinalizeInputPath='NOT_APPLICABLE';repairFinalizeInputIdentity='NOT_APPLICABLE';repairFinalizeResultPath='NOT_APPLICABLE';repairFinalizeResultIdentity='NOT_APPLICABLE'}
  $routeInput=Join-Path $control 'repair-route.json';Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  $routeOutput=@(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)
  $routeCode=$LASTEXITCODE;$prepared=($routeOutput-join "`n")|ConvertFrom-Json -Depth 64
  Assert-True ($routeCode-eq0-and$prepared.status-ceq'PREPARED'-and-not$prepared.authorityGranted) 'repair-current-package-prepared-from-real-candidate-without-new-authority'
  $child=$prepared.package
  $childCheck=Invoke-Check $child 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($childCheck.Code-eq0) 'prepared-repair-package-passes-real-checker'
  $badChild=$child|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badChild.repairReviewBinding.cycle=3
  $badCheck=Invoke-Check $badChild 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_CYCLE')) 'repair-cycle-exhaustion-requires-owner'
  $badChild=$child|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badChild.repairReviewBinding.verdictIdentity='1|'+('0'*64)
  $badCheck=Invoke-Check $badChild 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_EVIDENCE_DRIFT')) 'stale-verdict-cannot-authorize-repair'
  $verdict.scopeChanged=$true;Write-Json $verdictPath $verdict
  $badChild=$child|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badChild.repairReviewBinding.verdictIdentity=Get-Identity $verdictPath
  $badCheck=Invoke-Check $badChild 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_VERDICT_BOUNDARY')) 'broadened-impact-does-not-use-focused-repair'
  $badParent=$parent|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badParent.repairReviewPlan.reviewer='writer-fixture'
  $badCheck=Invoke-Check $badParent 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_INDEPENDENCE')) 'bounded-plan-never-waives-reviewer-independence'

  # Exercise actual DISCOVER -> ADMIT -> write -> FINALIZE -> independent rereview.
  # Stable metadata below exists only inside the isolated test fixture.
  $frameworkRoot=Join-Path $temp 'framework-root';$fixtureVersion=[IO.Path]::GetFullPath((Join-Path $frameworkRoot 'framework/versions/1.16.0'))
  New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureVersion) -Force|Out-Null
  Copy-Item -LiteralPath (Split-Path -Parent $PSScriptRoot) -Destination $fixtureVersion -Recurse
  $vpath=Join-Path $fixtureVersion 'VERSION.json';$v=Get-Content $vpath -Raw|ConvertFrom-Json;$v.lifecycle='STABLE';$v.consumable=$true;$v.projectPinEligible=$true;Write-Json $vpath $v
  $mpath=[IO.Path]::GetFullPath((Join-Path $fixtureVersion 'RELEASE_MANIFEST.json'));$m=Get-Content $mpath -Raw|ConvertFrom-Json
  [string[]]$paths=@(Get-ChildItem $fixtureVersion -Recurse -File|Where-Object{$_.FullName-cne$mpath}|ForEach-Object{$_.FullName.Substring($fixtureVersion.Length+1).Replace('\','/')});[Array]::Sort($paths,[StringComparer]::Ordinal)
  $rows=@();[long]$total=0;foreach($p in $paths){$id=(Get-Identity (Join-Path $fixtureVersion $p)).Split('|');$total+=[long]$id[0];$rows+=($p+'|'+$id[0]+'|'+$id[1])}
  $candidateManifestIdentity=Get-Identity $mpath
  $m.lifecycle='STABLE';$m.sourceReview='APPROVED';$m.fileCount=$paths.Count;$m.totalBytes=$total;$m.canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n"))))
  $m.completeSuite=[pscustomobject][ordered]@{status='PASS';passed=1;total=1;payloadCanonical=$m.canonical;evidenceIdentity=('1|'+('A'*64))}
  $m.sourceReviewEvidence=[pscustomobject][ordered]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$m.canonical;reviewedManifestIdentity=$candidateManifestIdentity}
  Write-Json $mpath $m
  Write-Json (Join-Path $control 'corrections.json') ([ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='authorization-receipt-fixture';corrections=@()})
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
  Write-Json (Join-Path $control 'process-policy.json') ([ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='authorization-receipt-fixture';selectedRulePackBytes=98304;rules=@()})
  $cfg=Get-Content (Join-Path $control 'project.json') -Raw|ConvertFrom-Json;$cfg.schemaVersion=4;$cfg|Add-Member -NotePropertyName processPolicy -NotePropertyValue ([pscustomobject]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'});Write-Json (Join-Path $control 'project.json') $cfg
  Write-Task STANDARD IMPLEMENT
  $parent=New-Package STANDARD DOMAIN_OWNER writer-fixture SOURCE_WRITE ROUTINE_LOCAL
  $parent.actions=@('SOURCE_WRITE','TEST_RUN');$parent.continuationPlan=@('SOURCE_WRITE','TEST_RUN');$parent.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $parent.repairReviewPlan=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@()};Write-Json $parentPath $parent
  $verdict.scopeChanged=$false;$verdict.objectIdentities=$parent.objectIdentities;Write-Json $verdictPath $verdict
  $binding.parentPackageIdentity=Get-Identity $parentPath;$binding.verdictIdentity=Get-Identity $verdictPath
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  $prepared=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  $childPath=Join-Path $control 'repair-child.json';Write-Json $childPath $prepared.package
  $resolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
  function Run-Process($Value,[string]$Name){$p=Join-Path $control ($Name+'.json');Write-Json $p $Value;$out=@(& pwsh -NoProfile -File $resolver -InputPath $p -AsJson);if($LASTEXITCODE-ne0){throw ('REAL_PROCESS_FAILED|'+$Name+'|'+($out-join"`n"))};return ($out-join"`n")|ConvertFrom-Json -Depth 100}
  $discover=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='writer-fixture';capabilities=@();exactPaths=@($objectRelative);forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath=$childPath;expectedAuthorizationIdentity=Get-Identity $childPath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Repair the accepted bounded finding and return its terminal result';requestedActionKind='SOURCE_WRITE';requestedResultKind='TERMINAL';semanticHints=@('repair');pathHints=@($objectRelative);capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
  # First submission uses a real producer action and FINALIZE, without inventing a finding.
  $initial=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $initial.authorizationPackagePath=$parentPath;$initial.expectedAuthorizationIdentity=Get-Identity $parentPath
  $initial.intentEnvelope.objective='Produce the candidate for its first independent review'
  $initial.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$initial.intentEnvelope.semanticHints=@('implementation')
  $first=Run-Process $initial 'initial-producer-discover';$firstReceipt=Join-Path $control 'initial-producer-compact.json';Write-Json $firstReceipt $first.compactReceipt
  $firstBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$firstReceipt;expectedDiscoverReceiptIdentity=Get-Identity $firstReceipt;preparationReceipts=@($first.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $firstAdmit=Run-Process $firstBoundary 'initial-producer-admit';Assert-True ($firstAdmit.status-ceq'PASS') 'first-review-producer-is-actually-admitted'
  Write-Utf8 $objectPath 'Initial candidate awaiting independent judgment'
  $firstBoundary.mode='FINALIZE_OUTPUT';$firstBoundary.resultReceipts=@($first.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $firstFinal=Run-Process $firstBoundary 'initial-producer-finalize';$firstFinalPath=Join-Path $control 'initial-producer-finalize-result.json';Write-Json $firstFinalPath $firstFinal
  $firstContinuation=Join-Path $control 'first-continuation.json';Write-Json $firstContinuation $firstFinal.continuationReceipt
  $firstTest=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $firstTest|Add-Member continuationReceiptPath $firstContinuation;$firstTest|Add-Member expectedContinuationReceiptIdentity (Get-Identity $firstContinuation)
  $firstTest.intentEnvelope.requestedActionKind='TEST_RUN';$firstTest.intentEnvelope.requestedResultKind='TEST_RESULT';$firstTest.intentEnvelope.semanticHints=@('test');$firstTest.intentEnvelope.mutationHints=@('test')
  $tested=Run-Process $firstTest 'initial-test-discover';$testReceipt=Join-Path $control 'initial-test-compact.json';Write-Json $testReceipt $tested.compactReceipt
  $testBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$testReceipt;expectedDiscoverReceiptIdentity=Get-Identity $testReceipt;preparationReceipts=@($tested.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $testAdmit=Run-Process $testBoundary 'initial-test-admit'
  Assert-True ($testAdmit.status-ceq'PASS'-and[IO.File]::ReadAllText($objectPath).TrimEnd("`n")-ceq'Initial candidate awaiting independent judgment') 'first-submission-self-test-consumes-real-producer-continuation'
  $testBoundary.mode='FINALIZE_OUTPUT';$testBoundary.resultReceipts=@($tested.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $testedFinal=Run-Process $testBoundary 'initial-test-finalize';$testedFinalPath=Join-Path $control 'initial-test-finalize-result.json';Write-Json $testedFinalPath $testedFinal
  $initialBinding=[ordered]@{parentPackagePath=$parentPath;parentPackageIdentity=Get-Identity $parentPath;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=(Join-Path $control 'initial-test-finalize.json');repairFinalizeInputIdentity=Get-Identity (Join-Path $control 'initial-test-finalize.json');repairFinalizeResultPath=$testedFinalPath;repairFinalizeResultIdentity=Get-Identity $testedFinalPath}
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$initialBinding})
  $firstReview=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  $firstReviewCheck=Invoke-Check $firstReview.package reviewer-fixture REVIEW_EXECUTE
  if($firstReviewCheck.Code-ne0){Write-Output ('DIAG|first-review|'+$firstReviewCheck.Text)}
  Assert-True ($firstReviewCheck.Code-eq0) 'first-review-current-package-binds-real-producer-finalize'
  $firstReviewPath=Join-Path $control 'initial-review-package.json';Write-Json $firstReviewPath $firstReview.package
  $reviewDiscover=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $reviewDiscover.observedActor='reviewer-fixture';$reviewDiscover.authorizationPackagePath=$firstReviewPath;$reviewDiscover.expectedAuthorizationIdentity=Get-Identity $firstReviewPath
  $reviewDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$reviewDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$reviewDiscover.intentEnvelope.semanticHints=@('review');$reviewDiscover.intentEnvelope.mutationHints=@()
  $reviewDiscovered=Run-Process $reviewDiscover 'initial-review-discover';$reviewReceipt=Join-Path $control 'initial-review-compact.json';Write-Json $reviewReceipt $reviewDiscovered.compactReceipt
  $reviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$reviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $reviewReceipt;preparationReceipts=@($reviewDiscovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $reviewAdmit=Run-Process $reviewBoundary 'initial-review-admit';Assert-True ($reviewAdmit.status-ceq'PASS') 'first-review-independent-actor-passes-real-process-admission'
  $reviewBoundary.mode='FINALIZE_OUTPUT';$reviewBoundary.resultReceipts=@($reviewDiscovered.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$reviewBoundary.deliveryReceipts=@('FIXTURE_REVIEW_RETURN')
  $reviewFinal=Run-Process $reviewBoundary 'initial-review-finalize';Assert-True ($reviewFinal.status-ceq'PASS') 'first-review-returns-through-real-finalize'
  $badFirst=$firstReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badFirst.repairReviewBinding.cycle=1
  Assert-True ((Invoke-Check $badFirst reviewer-fixture REVIEW_EXECUTE).Code-ne0) 'first-review-rejects-invented-repair-cycle'
  $verdict.objectIdentities=@([ordered]@{path=$objectRelative;identity=Get-Identity $objectPath});Write-Json $verdictPath $verdict
  $binding.verdictIdentity=Get-Identity $verdictPath
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  $prepared=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  Write-Json $childPath $prepared.package;$discover.expectedAuthorizationIdentity=Get-Identity $childPath
  $d=Run-Process $discover 'repair-discover';$receiptPath=Join-Path $control 'repair-compact.json';Write-Json $receiptPath $d.compactReceipt
  $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;preparationReceipts=@($d.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $admitted=Run-Process $boundary 'repair-admit';Assert-True ($admitted.status-ceq'PASS') 'real-repair-admission-passes'
  Write-Utf8 $objectPath 'Repaired candidate with real postimage'
  $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($d.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $legacyHostResult=Join-Path $temp 'legacy-fixture-host-result.txt';Write-Utf8 $legacyHostResult 'recipient=owner-fixture;outcome=SUCCESS;fixture-only'
  $boundary.deliveryReceipts=@('FIXTURE_HOST_RESULT|'+(Get-Identity $legacyHostResult))
  Assert-True ('DELIVERY_RECEIPT'-cin@($d.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements})) 'repair-terminal-fixture-selects-actual-delivery-obligation'
  $final=Run-Process $boundary 'repair-finalize';$finalResultPath=Join-Path $control 'repair-final-result.json';Write-Json $finalResultPath $final
  Assert-True ($final.status-ceq'PASS') 'real-repair-finalize-binds-written-postimage'
  $binding.phase='REREVIEW';$binding.repairFinalizeInputPath=Join-Path $control 'repair-finalize.json';$binding.repairFinalizeInputIdentity=Get-Identity $binding.repairFinalizeInputPath;$binding.repairFinalizeResultPath=$finalResultPath;$binding.repairFinalizeResultIdentity=Get-Identity $finalResultPath
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  $reviewPrepared=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  $reviewCheck=Invoke-Check $reviewPrepared.package reviewer-fixture REVIEW_EXECUTE
  if($reviewCheck.Code-ne0){Write-Output ('DIAG|rereview|'+$reviewCheck.Text)}
  Assert-True ($reviewCheck.Code-eq0) 'real-finalize-authorizes-prebound-independent-focused-rereview'
  $rereviewPath=Join-Path $control 'rereview-package.json';Write-Json $rereviewPath $reviewPrepared.package
  $reviewDiscover.authorizationPackagePath=$rereviewPath;$reviewDiscover.expectedAuthorizationIdentity=Get-Identity $rereviewPath
  $rereview=Run-Process $reviewDiscover 'rereview-discover';$rereviewReceipt=Join-Path $control 'rereview-compact.json';Write-Json $rereviewReceipt $rereview.compactReceipt
  $rereviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$rereviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $rereviewReceipt;preparationReceipts=@($rereview.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $rereviewAdmit=Run-Process $rereviewBoundary 'rereview-admit'
  Assert-True ($rereviewAdmit.status-ceq'PASS'-and[IO.File]::ReadAllText($objectPath).TrimEnd("`n")-ceq'Repaired candidate with real postimage') 'same-independent-reviewer-actually-admits-and-inspects-repaired-candidate'
  $rereviewBoundary.mode='FINALIZE_OUTPUT';$rereviewBoundary.resultReceipts=@($rereview.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$rereviewBoundary.deliveryReceipts=@('FIXTURE_REREVIEW_RETURN')
  $rereviewFinal=Run-Process $rereviewBoundary 'rereview-finalize'
  Assert-True ($rereviewFinal.status-ceq'PASS') 'repair-to-rereview-chain-finishes-through-real-finalize-without-owner-relay'
  $hostResultPath=Join-Path $temp 'fixture-host-result.txt';Write-Utf8 $hostResultPath 'recipient=owner-fixture;outcome=SUCCESS;fixture-only'
  foreach($deliveryCase in @('NATIVE_PREPARE','TASK_PREPARE','SUCCESS','FAILURE','UNKNOWN')){
    $withDelivery=$boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable
    $withDelivery.deliveryReceipts=@();$withDelivery.resultReceipts=@($withDelivery.resultReceipts|Where-Object{$_-cne'DELIVERY_RECEIPT'})
    $prepare=$deliveryCase.EndsWith('PREPARE')
    $withDelivery.deliveryContext=[ordered]@{channel=$(if($deliveryCase-ceq'NATIVE_PREPARE'){'NATIVE_RESPONSE'}else{'TASK_MESSAGE'});stage=$(if($prepare){'PREPARE'}else{'OBSERVE'});expectedRecipient='owner-fixture';observedRecipient=$(if($prepare){'NOT_APPLICABLE'}else{'owner-fixture'});outcome=$(if($prepare){'NOT_SENT'}else{$deliveryCase});evidence=$(if($prepare){'NOT_APPLICABLE'}else{'FIXTURE_HOST_RESULT|'+(Get-Identity $hostResultPath)})}
    $name='repair-delivery-'+$deliveryCase
    $observed=Run-Process $withDelivery $name;$observedPath=Join-Path $control ($name+'-result.json');Write-Json $observedPath $observed
    $deliveryBinding=$binding|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $deliveryBinding.repairFinalizeInputPath=Join-Path $control ($name+'.json');$deliveryBinding.repairFinalizeInputIdentity=Get-Identity $deliveryBinding.repairFinalizeInputPath
    $deliveryBinding.repairFinalizeResultPath=$observedPath;$deliveryBinding.repairFinalizeResultIdentity=Get-Identity $observedPath
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$deliveryBinding})
    $deliveryPackage=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    $deliveryCheck=Invoke-Check $deliveryPackage.package reviewer-fixture REVIEW_EXECUTE
    $expectedStatus=if($prepare){'READY_TO_SEND'}elseif($deliveryCase-ceq'SUCCESS'){'DELIVERED'}elseif($deliveryCase-ceq'FAILURE'){'NOT_DELIVERED'}else{'UNKNOWN'}
    Assert-True ($deliveryCheck.Code-eq0-and$observed.delivery.status-ceq$expectedStatus-and$observed.delivery.delivered-eq($deliveryCase-ceq'SUCCESS')) ('rereview-consumes-real-finalize-'+$deliveryCase)
    $tampered=$withDelivery|ConvertTo-Json -Depth 100|ConvertFrom-Json;$tampered.deliveryContext.expectedRecipient='another-recipient';Write-Json $deliveryBinding.repairFinalizeInputPath $tampered
    $deliveryPackage.package.repairReviewBinding.repairFinalizeInputIdentity=Get-Identity $deliveryBinding.repairFinalizeInputPath
    $tamperedCheck=Invoke-Check $deliveryPackage.package reviewer-fixture REVIEW_EXECUTE
    Assert-True ($tamperedCheck.Code-ne0) ('rereview-rejects-context-tampering-'+$deliveryCase)
    Write-Json $deliveryBinding.repairFinalizeInputPath $withDelivery;$deliveryPackage.package.repairReviewBinding.repairFinalizeInputIdentity=Get-Identity $deliveryBinding.repairFinalizeInputPath
    $tamperedResult=$observed|ConvertTo-Json -Depth 100|ConvertFrom-Json;$tamperedResult.delivery.delivered=-not$observed.delivery.delivered;Write-Json $observedPath $tamperedResult
    $deliveryPackage.package.repairReviewBinding.repairFinalizeResultIdentity=Get-Identity $observedPath
    $tamperedCheck=Invoke-Check $deliveryPackage.package reviewer-fixture REVIEW_EXECUTE
    Assert-True ($tamperedCheck.Code-ne0-and$tamperedCheck.Text.Contains('DELIVERY_RESULT_DRIFT')) ('rereview-rejects-delivery-result-tampering-'+$deliveryCase)
  }
  $forged=$final|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forged.decisionIdentity='0'*64;Write-Json $finalResultPath $forged
  $reviewPrepared.package.repairReviewBinding.repairFinalizeResultIdentity=Get-Identity $finalResultPath
  $forgedCheck=Invoke-Check $reviewPrepared.package reviewer-fixture REVIEW_EXECUTE
  Assert-True ($forgedCheck.Code-ne0-and$forgedCheck.Text.Contains('FINALIZE_DECISION_DRIFT')) 'rereview-rejects-self-declared-pass-without-real-decision'
  Write-Json $finalResultPath $final;$reviewPrepared.package.repairReviewBinding.repairFinalizeResultIdentity=Get-Identity $finalResultPath
  Write-Utf8 $objectPath 'Third party drift after repair finalization'
  $driftCheck=Invoke-Check $reviewPrepared.package reviewer-fixture REVIEW_EXECUTE
  Assert-True ($driftCheck.Code-ne0) 'rereview-rejects-current-candidate-drift'

  # The Owner preauthorizes an independent visible reviewer before its host ID
  # exists. The writer binds the actual create result after production and test.
  Write-Utf8 $objectPath 'Late reviewer production preimage'
  $lateParent=New-Package STANDARD DOMAIN_OWNER writer-fixture SOURCE_WRITE ROUTINE_LOCAL
  $lateParent.actions=@('SOURCE_WRITE','TEST_RUN');$lateParent.continuationPlan=@('SOURCE_WRITE','TEST_RUN');$lateParent.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $lateParent.repairReviewPlan=[ordered]@{writer='writer-fixture';reviewer='DEFERRED_VISIBLE_REVIEWER';maxCycles=2;materialContributors=@()}
  $lateParentPath=Join-Path $control 'late-review-parent.json';Write-Json $lateParentPath $lateParent
  Assert-True ((Invoke-Check $lateParent writer-fixture SOURCE_WRITE).Code-eq0) 'owner-preauthorizes-temporary-writer-and-deferred-independent-reviewer'
  $lateInitial=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $lateInitial.authorizationPackagePath=$lateParentPath;$lateInitial.expectedAuthorizationIdentity=Get-Identity $lateParentPath
  $lateProducer=Run-Process $lateInitial 'late-producer-discover';$lateProducerReceipt=Join-Path $control 'late-producer-compact.json';Write-Json $lateProducerReceipt $lateProducer.compactReceipt
  $lateBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$lateProducerReceipt;expectedDiscoverReceiptIdentity=Get-Identity $lateProducerReceipt;preparationReceipts=@($lateProducer.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  Assert-True ((Run-Process $lateBoundary 'late-producer-admit').status-ceq'PASS') 'late-reviewer-producer-admits-under-original-owner-package'
  Write-Utf8 $objectPath 'Late reviewer candidate after production'
  $lateBoundary.mode='FINALIZE_OUTPUT';$lateBoundary.resultReceipts=@($lateProducer.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $lateProducerFinal=Run-Process $lateBoundary 'late-producer-finalize';$lateContinuationPath=Join-Path $control 'late-producer-continuation.json';Write-Json $lateContinuationPath $lateProducerFinal.continuationReceipt
  $lateTest=$lateInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $lateTest|Add-Member continuationReceiptPath $lateContinuationPath;$lateTest|Add-Member expectedContinuationReceiptIdentity (Get-Identity $lateContinuationPath)
  $lateTest.intentEnvelope.requestedActionKind='TEST_RUN';$lateTest.intentEnvelope.requestedResultKind='TEST_RESULT';$lateTest.intentEnvelope.semanticHints=@('test');$lateTest.intentEnvelope.mutationHints=@('test')
  $lateTestDiscover=Run-Process $lateTest 'late-test-discover';$lateTestReceipt=Join-Path $control 'late-test-compact.json';Write-Json $lateTestReceipt $lateTestDiscover.compactReceipt
  $lateTestBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$lateTestReceipt;expectedDiscoverReceiptIdentity=Get-Identity $lateTestReceipt;preparationReceipts=@($lateTestDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  Assert-True ((Run-Process $lateTestBoundary 'late-test-admit').status-ceq'PASS') 'late-reviewer-test-reuses-original-continuation'
  $lateTestBoundary.mode='FINALIZE_OUTPUT';$lateTestBoundary.resultReceipts=@($lateTestDiscover.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $lateTestFinal=Run-Process $lateTestBoundary 'late-test-finalize';$lateTestFinalPath=Join-Path $control 'late-test-final-result.json';Write-Json $lateTestFinalPath $lateTestFinal
  $lateAssignment=[ordered]@{source='HOST_CREATE_THREAD_RESULT';createdBy='writer-fixture';threadId='reviewer-late-fixture';hostId='fixture-host';taskId='AUTH-REGRESSION-001';parentPackageIdentity=Get-Identity $lateParentPath}
  $lateBinding=[ordered]@{parentPackagePath=$lateParentPath;parentPackageIdentity=Get-Identity $lateParentPath;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=(Join-Path $control 'late-test-finalize.json');repairFinalizeInputIdentity=Get-Identity (Join-Path $control 'late-test-finalize.json');repairFinalizeResultPath=$lateTestFinalPath;repairFinalizeResultIdentity=Get-Identity $lateTestFinalPath;reviewerAssignment=$lateAssignment}
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$lateBinding})
  $lateReview=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  $lateReviewCheck=Invoke-Check $lateReview.package reviewer-late-fixture REVIEW_EXECUTE
  if($lateReviewCheck.Code-ne0){Write-Output ('DIAG|late-reviewer|'+$lateReviewCheck.Text)}
  Assert-True ($lateReviewCheck.Code-eq0-and$lateReview.package.owner-ceq'owner-fixture'-and$lateReview.package.issuer-ceq'owner-fixture'-and$lateReview.package.grantee-ceq'reviewer-late-fixture') 'late-created-independent-reviewer-admits-with-original-owner-and-production-evidence'
  $missingAssignment=$lateReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$missingAssignment.repairReviewBinding.PSObject.Properties.Remove('reviewerAssignment')
  Assert-True ((Invoke-Check $missingAssignment reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-missing-host-assignment'
  $wrongAssignment=$lateReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongAssignment.repairReviewBinding.reviewerAssignment.createdBy='other-fixture'
  Assert-True ((Invoke-Check $wrongAssignment reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-wrong-creator'
  $wrongParentAssignment=$lateReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongParentAssignment.repairReviewBinding.reviewerAssignment.parentPackageIdentity='1|'+('0'*64)
  Assert-True ((Invoke-Check $wrongParentAssignment reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-wrong-parent-binding'
  Assert-True ((Invoke-Check $lateReview.package reviewer-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-other-actor-reuse'
  $lateCandidateBytes=[IO.File]::ReadAllBytes($objectPath);Write-Utf8 $objectPath 'Unreviewed third-party candidate'
  Assert-True ((Invoke-Check $lateReview.package reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-candidate-drift'
  [IO.File]::WriteAllBytes($objectPath,$lateCandidateBytes)
  $lateReviewPath=Join-Path $control 'late-review-package.json';Write-Json $lateReviewPath $lateReview.package
  $lateReviewDiscover=$lateInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$lateReviewDiscover.observedActor='reviewer-late-fixture';$lateReviewDiscover.authorizationPackagePath=$lateReviewPath;$lateReviewDiscover.expectedAuthorizationIdentity=Get-Identity $lateReviewPath
  $lateReviewDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$lateReviewDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$lateReviewDiscover.intentEnvelope.semanticHints=@('review');$lateReviewDiscover.intentEnvelope.mutationHints=@()
  $lateReviewResult=Run-Process $lateReviewDiscover 'late-review-discover';$lateReviewReceipt=Join-Path $control 'late-review-compact.json';Write-Json $lateReviewReceipt $lateReviewResult.compactReceipt
  $lateReviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$lateReviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $lateReviewReceipt;preparationReceipts=@($lateReviewResult.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  Assert-True ((Run-Process $lateReviewBoundary 'late-review-admit').status-ceq'PASS') 'late-reviewer-real-process-admission-keeps-owner-writer-reviewer-distinct'
  $lateReviewBoundary.mode='FINALIZE_OUTPUT';$lateReviewBoundary.resultReceipts=@($lateReviewResult.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$lateReviewBoundary.deliveryReceipts=@('FIXTURE_APPROVED_TO_OWNER_ONCE')
  Assert-True ((Run-Process $lateReviewBoundary 'late-review-finalize').status-ceq'PASS') 'late-reviewer-finalizes-one-direct-owner-handoff'
  $selfActor='01a0eeee-5555-7222-8333-444444444444';$selfDelegation='fixture-late-reviewer-initial-001'
  $selfBinding=$lateBinding|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $selfBinding.reviewerAssignment.source='HOST_INITIAL_DELEGATION';$selfBinding.reviewerAssignment.threadId='UNBOUND_RECEIVER'
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$selfBinding})
  $selfPrepared=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  Assert-True ($selfPrepared.status-ceq'PREPARED'-and$selfPrepared.package.grantee-ceq'UNBOUND_RECEIVER') 'late-reviewer-prepares-nonactionable-initial-delegation'
  $selfPendingPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-late-reviewer.json'
  Write-Json $selfPendingPath ([ordered]@{schemaVersion=1;delegationId=$selfDelegation;receiverRole='REVIEWER';authorizationTemplate=$selfPrepared.package})
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$selfActor
    $selfBindResult=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $selfPendingPath -ExpectedPendingIdentity (Get-Identity $selfPendingPath) -ReceivedDelegationId $selfDelegation 2>&1|ForEach-Object{[string]$_});$selfBindCode=$LASTEXITCODE
    $selfPackagePath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$selfActor+'/receiver-authorization-'+$selfDelegation+'.json')
    Assert-True ($selfBindCode-eq0-and(Test-Path -LiteralPath $selfPackagePath -PathType Leaf)) 'late-reviewer-self-binds-from-initial-delegation'
    $selfPackage=Get-Content $selfPackagePath -Raw|ConvertFrom-Json -Depth 100
    $selfCheck=Invoke-Check $selfPackage $selfActor REVIEW_EXECUTE
    Assert-True ($selfCheck.Code-eq0-and$selfPackage.owner-ceq'owner-fixture'-and$selfPackage.issuer-ceq'owner-fixture'-and$selfPackage.repairReviewBinding.reviewerAssignment.threadId-ceq$selfActor) 'late-self-bound-reviewer-preserves-owner-and-production-evidence'
    $selfDiscover=$lateReviewDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$selfDiscover.observedActor=$selfActor;$selfDiscover.authorizationPackagePath=$selfPackagePath;$selfDiscover.expectedAuthorizationIdentity=Get-Identity $selfPackagePath
    $selfProcess=Run-Process $selfDiscover 'late-self-review-discover';$selfCompact=Join-Path $control 'late-self-review-compact.json';Write-Json $selfCompact $selfProcess.compactReceipt
    $selfBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$selfCompact;expectedDiscoverReceiptIdentity=Get-Identity $selfCompact;preparationReceipts=@($selfProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $selfBoundary 'late-self-review-admit').status-ceq'PASS') 'late-self-bound-reviewer-enters-original-process-gate'
    $altered=$selfPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$altered.repairReviewBinding.reviewerAssignment.threadId='01a0eeee-6666-7222-8333-444444444444'
    Assert-True ((Invoke-Check $altered $selfActor REVIEW_EXECUTE).Code-ne0) 'late-self-bound-reviewer-rejects-other-assignment'
  }finally{$env:CODEX_THREAD_ID=$oldHostId}
  # One original delegation must compose an unknown writer, its write/test
  # continuation, and a later unknown independent reviewer through rereview.
  $combinedConfigPath=Join-Path $control 'project.json';$combinedConfigOriginal=[IO.File]::ReadAllBytes($combinedConfigPath)
  $combinedConfig=Get-Content $combinedConfigPath -Raw|ConvertFrom-Json
  $combinedConfig|Add-Member -NotePropertyName frameworkTarget -NotePropertyValue ([pscustomobject]@{repositoryId='REPO_LOCAL';siblingDirectory=(Split-Path -Leaf $temp);routineExcludedPaths=@()})
  Write-Json (Join-Path $control 'project.json') $combinedConfig
  Write-Task STANDARD IMPLEMENT
  Write-Utf8 $objectPath 'Combined delegation setup'
  $combinedWriter='01a0eeee-aaaa-7222-8333-444444444444';$combinedReviewer='01a0eeee-bbbb-7222-8333-444444444444'
  $combinedId='fixture-combined-implementer-001';$combinedReviewId='fixture-combined-reviewer-001'
  $combinedTemplate=New-Package STANDARD DOMAIN_OWNER UNBOUND_RECEIVER SOURCE_WRITE ROUTINE_LOCAL
  $combinedTemplate.schemaVersion=2;$combinedTemplate['repositoryId']='REPO_LOCAL';$combinedTemplate.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$combinedTemplate['continuationPlan']=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE')
  $combinedTemplate.invalidatesOn+=@('REPOSITORY_CHANGE','CONTINUATION_RESULT_DRIFT')
  $combinedTemplate['repairReviewPlan']=[ordered]@{writer='UNBOUND_RECEIVER';reviewer='DEFERRED_VISIBLE_REVIEWER';maxCycles=2;materialContributors=@()}
  $combinedTemplate.objectIdentities[0].identity='NEW'
  Remove-Item -LiteralPath $objectPath
  $combinedPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-writer.json'
  Write-Json $combinedPending ([ordered]@{schemaVersion=1;delegationId=$combinedId;receiverRole='IMPLEMENTER';authorizationTemplate=$combinedTemplate})
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$combinedWriter
    $combinedBind=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $combinedPending -ExpectedPendingIdentity (Get-Identity $combinedPending) -ReceivedDelegationId $combinedId 2>&1|ForEach-Object{[string]$_});$combinedBindCode=$LASTEXITCODE
    $combinedParentPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$combinedWriter+'/receiver-authorization-'+$combinedId+'.json')
    Assert-True ($combinedBindCode-eq0-and(Test-Path -LiteralPath $combinedParentPath -PathType Leaf)) 'combined-unknown-writer-self-binds-once'
    $combinedParent=Get-Content $combinedParentPath -Raw|ConvertFrom-Json -Depth 100
    $combinedCheck=Invoke-Check $combinedParent $combinedWriter SOURCE_WRITE
    if($combinedCheck.Code-ne0){Write-Output ('DIAG|combined-writer|'+$combinedCheck.Text)}
    Assert-True ($combinedCheck.Code-eq0-and$combinedParent.repairReviewPlan.writer-ceq$combinedWriter-and$combinedParent.owner-ceq'owner-fixture'-and$combinedParent.issuer-ceq'owner-fixture'-and$combinedParent.objectIdentities[0].identity-ceq'NEW') 'combined-bound-writer-preserves-owner-issuer-and-new-object'
    Assert-True ((Invoke-Check $combinedParent $combinedWriter REVIEW_ROUTE).Code-ne0) 'combined-review-route-rejects-missing-continuation'
    Assert-True ((Invoke-Check $combinedParent 'other-writer' SOURCE_WRITE).Code-ne0) 'combined-delegation-rejects-other-writer'
    $noRoute=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$noRoute.actions=@('SOURCE_WRITE','TEST_RUN');$noRoute.continuationPlan=@('SOURCE_WRITE','TEST_RUN')
    Assert-True ((Invoke-Check $noRoute $combinedWriter REVIEW_ROUTE).Code-ne0) 'combined-route-rejects-absent-owner-pregrant'
    foreach($smuggled in @('REVIEW_EXECUTE','OWNER_ACCEPT','GIT_STAGE')){
      $bad=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.actions+=@($smuggled);$bad.continuationPlan+=@($smuggled)
      Assert-True ((Invoke-Check $bad $combinedWriter SOURCE_WRITE).Code-ne0) ('combined-route-rejects-smuggled-'+$smuggled)
    }
    $tamperedOwner=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedOwner.owner=$combinedWriter
    Assert-True ((Invoke-Check $tamperedOwner $combinedWriter SOURCE_WRITE).Code-ne0) 'combined-bound-writer-rejects-owner-rewrite'
    $tamperedIssuer=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedIssuer.issuer=$combinedWriter
    Assert-True ((Invoke-Check $tamperedIssuer $combinedWriter SOURCE_WRITE).Code-ne0) 'combined-bound-writer-rejects-issuer-rewrite'
    $wrongWriter=$combinedTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongWriter.repairReviewPlan.writer='other-writer'
    $wrongWriterPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-wrong-writer.json';$wrongWriterId='fixture-combined-wrong-writer-001'
    Write-Json $wrongWriterPath ([ordered]@{schemaVersion=1;delegationId=$wrongWriterId;receiverRole='IMPLEMENTER';authorizationTemplate=$wrongWriter})
    $wrongWriterBind=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $wrongWriterPath -ExpectedPendingIdentity (Get-Identity $wrongWriterPath) -ReceivedDelegationId $wrongWriterId 2>&1|ForEach-Object{[string]$_})
    Assert-True ($LASTEXITCODE-ne0-and($wrongWriterBind-join"`n").Contains('PENDING_REPAIR_WRITER')) 'combined-delegation-rejects-fixed-other-writer'
    $wrongRole=$combinedTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongRole.actions=@('TEST_RUN');$wrongRole.continuationPlan=@('TEST_RUN')
    $wrongRolePath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-wrong-role.json';$wrongRoleId='fixture-combined-wrong-role-001'
    Write-Json $wrongRolePath ([ordered]@{schemaVersion=1;delegationId=$wrongRoleId;receiverRole='INVESTIGATOR';authorizationTemplate=$wrongRole})
    $wrongRoleBind=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $wrongRolePath -ExpectedPendingIdentity (Get-Identity $wrongRolePath) -ReceivedDelegationId $wrongRoleId 2>&1|ForEach-Object{[string]$_})
    Assert-True ($LASTEXITCODE-ne0-and($wrongRoleBind-join"`n").Contains('PENDING_REPAIR_WRITER_ROLE')) 'combined-delegation-rejects-plan-on-investigator-role'
    $tamperedWriter=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedWriter.repairReviewPlan.writer='other-writer'
    Assert-True ((Invoke-Check $tamperedWriter $combinedWriter SOURCE_WRITE).Code-ne0) 'combined-bound-writer-rejects-plan-writer-tampering'
    $tamperedScope=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedScope.exactPaths=@($objectRelative,'src/extra.txt')
    $scopeCheck=Invoke-Check $tamperedScope $combinedWriter SOURCE_WRITE
    Assert-True ($scopeCheck.Code-ne0-and$scopeCheck.Text.Contains('RECEIVER_AUTHORITY_EXPANDED')) 'combined-bound-writer-rejects-scope-expansion'
    $combinedInitial=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedInitial.observedActor=$combinedWriter;$combinedInitial.authorizationPackagePath=$combinedParentPath;$combinedInitial.expectedAuthorizationIdentity=Get-Identity $combinedParentPath;$combinedInitial.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json')
    $combinedSource=Run-Process $combinedInitial 'combined-source-discover';$combinedSourceReceipt=Join-Path $control 'combined-source-compact.json';Write-Json $combinedSourceReceipt $combinedSource.compactReceipt
    $combinedSourceBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedSourceReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedSourceReceipt;preparationReceipts=@($combinedSource.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedSourceBoundary 'combined-source-admit').status-ceq'PASS') 'combined-unknown-writer-passes-source-admission'
    Write-Utf8 $objectPath 'Combined candidate awaiting independent judgment'
    $combinedSourceBoundary.mode='FINALIZE_OUTPUT';$combinedSourceBoundary.resultReceipts=@($combinedSource.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
    $combinedSourceFinal=Run-Process $combinedSourceBoundary 'combined-source-finalize';$combinedContinuation=Join-Path $control 'combined-continuation.json';Write-Json $combinedContinuation $combinedSourceFinal.continuationReceipt
    $combinedTest=$combinedInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedTest|Add-Member continuationReceiptPath $combinedContinuation;$combinedTest|Add-Member expectedContinuationReceiptIdentity (Get-Identity $combinedContinuation)
    $combinedTest.intentEnvelope.requestedActionKind='TEST_RUN';$combinedTest.intentEnvelope.requestedResultKind='TEST_RESULT';$combinedTest.intentEnvelope.semanticHints=@('test');$combinedTest.intentEnvelope.mutationHints=@('test')
    $combinedTestDiscover=Run-Process $combinedTest 'combined-test-discover';$combinedTestReceipt=Join-Path $control 'combined-test-compact.json';Write-Json $combinedTestReceipt $combinedTestDiscover.compactReceipt
    $combinedTestBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedTestReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedTestReceipt;preparationReceipts=@($combinedTestDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedTestBoundary 'combined-test-admit').status-ceq'PASS') 'combined-unknown-writer-consumes-source-test-continuation'
    $combinedTestBoundary.mode='FINALIZE_OUTPUT';$combinedTestBoundary.resultReceipts=@($combinedTestDiscover.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
    $combinedTestFinal=Run-Process $combinedTestBoundary 'combined-test-finalize';$combinedTestFinalPath=Join-Path $control 'combined-test-final-result.json';Write-Json $combinedTestFinalPath $combinedTestFinal
    $combinedRouteContinuation=Join-Path $control 'combined-route-continuation.json';Write-Json $combinedRouteContinuation $combinedTestFinal.continuationReceipt
    $combinedRoute=$combinedInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedRoute|Add-Member continuationReceiptPath $combinedRouteContinuation
    $combinedRoute|Add-Member expectedContinuationReceiptIdentity (Get-Identity $combinedRouteContinuation)
    $combinedRoute.intentEnvelope.objective='Route the current candidate to the independent reviewer'
    $combinedRoute.intentEnvelope.requestedActionKind='REVIEW_ROUTE';$combinedRoute.intentEnvelope.requestedResultKind='HANDOFF'
    $combinedRoute.intentEnvelope.semanticHints=@('review','handoff');$combinedRoute.intentEnvelope.mutationHints=@('review')
    $routeCheck=Invoke-Check $combinedParent $combinedWriter REVIEW_ROUTE
    Assert-True ($routeCheck.Code-ne0-and$routeCheck.Text.Contains('CONTINUATION')) 'combined-route-needs-current-continuation-receipt'
    $combinedRouteDiscover=Run-Process $combinedRoute 'combined-route-discover';$combinedRouteReceipt=Join-Path $control 'combined-route-compact.json';Write-Json $combinedRouteReceipt $combinedRouteDiscover.compactReceipt
    $combinedRouteBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedRouteReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedRouteReceipt;preparationReceipts=@($combinedRouteDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedRouteBoundary 'combined-route-admit').status-ceq'PASS'-and$combinedRouteDiscover.compactReceipt.binding.actor-ceq$combinedWriter-and$combinedRouteDiscover.compactReceipt.binding.role-ceq'EXECUTOR'-and$combinedRouteDiscover.compactReceipt.binding.phase-ceq'REVIEW') 'combined-nonowner-route-passes-real-check-discover-admit'
    $oldCandidate=[IO.File]::ReadAllBytes($objectPath);Write-Utf8 $objectPath 'Stale postimage after test'
    $staleRoute=@(& pwsh -NoProfile -File $resolver -InputPath (Join-Path $control 'combined-route-discover.json') -AsJson 2>&1|ForEach-Object{[string]$_});$staleRouteCode=$LASTEXITCODE
    Assert-True ($staleRouteCode-ne0) 'combined-route-rejects-stale-test-postimage'
    [IO.File]::WriteAllBytes($objectPath,$oldCandidate)
    $wrongRoute=$combinedRoute|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongRoute.observedActor='other-writer'
    $wrongRoutePath=Join-Path $control 'combined-route-wrong-actor.json';Write-Json $wrongRoutePath $wrongRoute
    $wrongRouteOut=@(& pwsh -NoProfile -File $resolver -InputPath $wrongRoutePath -AsJson 2>&1|ForEach-Object{[string]$_})
    Assert-True ($LASTEXITCODE-ne0) 'combined-route-rejects-wrong-actor'
    $combinedRouteBoundary.mode='FINALIZE_OUTPUT';$combinedRouteBoundary.resultReceipts=@($combinedRouteDiscover.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedRouteBoundary.deliveryReceipts=@('FIXTURE_ROUTE_TO_REVIEWER')
    $combinedRouteFinal=Run-Process $combinedRouteBoundary 'combined-route-finalize';$combinedRouteFinalPath=Join-Path $control 'combined-route-final-result.json';Write-Json $combinedRouteFinalPath $combinedRouteFinal
    $combinedAssignment=[ordered]@{source='HOST_INITIAL_DELEGATION';createdBy=$combinedWriter;threadId='UNBOUND_RECEIVER';hostId='fixture-host';taskId='AUTH-REGRESSION-001';parentPackageIdentity=Get-Identity $combinedParentPath}
    $combinedBinding=[ordered]@{parentPackagePath=$combinedParentPath;parentPackageIdentity=Get-Identity $combinedParentPath;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=(Join-Path $control 'combined-test-finalize.json');repairFinalizeInputIdentity=Get-Identity (Join-Path $control 'combined-test-finalize.json');repairFinalizeResultPath=$combinedTestFinalPath;repairFinalizeResultIdentity=Get-Identity $combinedTestFinalPath;reviewerAssignment=$combinedAssignment}
    $routeAsProduction=$combinedBinding|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $routeAsProduction.repairFinalizeInputPath=Join-Path $control 'combined-route-finalize.json';$routeAsProduction.repairFinalizeInputIdentity=Get-Identity $routeAsProduction.repairFinalizeInputPath
    $routeAsProduction.repairFinalizeResultPath=$combinedRouteFinalPath;$routeAsProduction.repairFinalizeResultIdentity=Get-Identity $combinedRouteFinalPath
    $routeAsProduction.reviewerAssignment.source='HOST_CREATE_THREAD_RESULT';$routeAsProduction.reviewerAssignment.threadId=$combinedReviewer
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$routeAsProduction})
    $routeOnly=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    Assert-True ((Invoke-Check $routeOnly.package $combinedReviewer REVIEW_EXECUTE).Text.Contains('REPAIR_REVIEW_PRODUCTION_FINALIZE_REQUIRED')) 'combined-route-finalize-cannot-be-production-proof'
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$combinedBinding})
    $combinedReview=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    Assert-True ($combinedReview.status-ceq'PREPARED'-and$combinedReview.package.grantee-ceq'UNBOUND_RECEIVER') 'combined-late-reviewer-prepared-from-original-bound-parent'
    $combinedReviewPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-reviewer.json'
    Write-Json $combinedReviewPending ([ordered]@{schemaVersion=1;delegationId=$combinedReviewId;receiverRole='REVIEWER';authorizationTemplate=$combinedReview.package})
    $env:CODEX_THREAD_ID=$combinedReviewer
    $reviewBind=@(& pwsh -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $combinedReviewPending -ExpectedPendingIdentity (Get-Identity $combinedReviewPending) -ReceivedDelegationId $combinedReviewId 2>&1|ForEach-Object{[string]$_});$reviewBindCode=$LASTEXITCODE
    $combinedReviewPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$combinedReviewer+'/receiver-authorization-'+$combinedReviewId+'.json')
    if($reviewBindCode-ne0){Write-Output ('DIAG|combined-reviewer-bind|'+($reviewBind-join"`n"))}
    Assert-True ($reviewBindCode-eq0-and(Test-Path -LiteralPath $combinedReviewPath -PathType Leaf)) 'combined-late-reviewer-self-binds-once'
    $combinedReviewPackage=Get-Content $combinedReviewPath -Raw|ConvertFrom-Json -Depth 100
    $combinedReviewCheck=Invoke-Check $combinedReviewPackage $combinedReviewer REVIEW_EXECUTE
    if($combinedReviewCheck.Code-ne0){Write-Output ('DIAG|combined-reviewer|'+$combinedReviewCheck.Text)}
    Assert-True ($combinedReviewCheck.Code-eq0-and$combinedReviewPackage.candidateWriter-ceq$combinedWriter-and$combinedReviewPackage.owner-ceq'owner-fixture') 'combined-independent-reviewer-preserves-writer-and-owner'
    $combinedReviewDiscover=$combinedInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedReviewDiscover.observedActor=$combinedReviewer;$combinedReviewDiscover.authorizationPackagePath=$combinedReviewPath;$combinedReviewDiscover.expectedAuthorizationIdentity=Get-Identity $combinedReviewPath
    $combinedReviewDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$combinedReviewDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$combinedReviewDiscover.intentEnvelope.semanticHints=@('review');$combinedReviewDiscover.intentEnvelope.mutationHints=@()
    $combinedReviewProcess=Run-Process $combinedReviewDiscover 'combined-review-discover';$combinedReviewReceipt=Join-Path $control 'combined-review-compact.json';Write-Json $combinedReviewReceipt $combinedReviewProcess.compactReceipt
    $combinedReviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedReviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedReviewReceipt;preparationReceipts=@($combinedReviewProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedReviewBoundary 'combined-review-admit').status-ceq'PASS') 'combined-late-reviewer-passes-initial-review-admission'
    $combinedReviewBoundary.mode='FINALIZE_OUTPUT';$combinedReviewBoundary.resultReceipts=@($combinedReviewProcess.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedReviewBoundary.deliveryReceipts=@('FIXTURE_FINDING_TO_WRITER')
    Assert-True ((Run-Process $combinedReviewBoundary 'combined-review-finalize').status-ceq'PASS') 'combined-late-reviewer-finalizes-initial-finding'
    $combinedVerdict=[ordered]@{taskId='AUTH-REGRESSION-001';owner='owner-fixture';reviewer=$combinedReviewer;writer=$combinedWriter;cycle=0;verdict='CHANGES_REQUESTED';exactPaths=@($objectRelative);objectIdentities=@([ordered]@{path=$objectRelative;identity=Get-Identity $objectPath});findingPaths=@($objectRelative);scopeChanged=$false;decisionChanged=$false}
    $combinedVerdictPath=Join-Path $control 'combined-verdict.json';Write-Json $combinedVerdictPath $combinedVerdict
    $combinedBinding.phase='REPAIR';$combinedBinding.cycle=1;$combinedBinding.verdictPath=$combinedVerdictPath;$combinedBinding.verdictIdentity=Get-Identity $combinedVerdictPath
    $combinedBinding.repairFinalizeInputPath='NOT_APPLICABLE';$combinedBinding.repairFinalizeInputIdentity='NOT_APPLICABLE';$combinedBinding.repairFinalizeResultPath='NOT_APPLICABLE';$combinedBinding.repairFinalizeResultIdentity='NOT_APPLICABLE'
    $combinedBinding.reviewerAssignment.threadId=$combinedReviewer
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$combinedBinding})
    $combinedRepair=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    Assert-True ($combinedRepair.status-ceq'PREPARED'-and(Invoke-Check $combinedRepair.package $combinedWriter SOURCE_WRITE).Code-eq0) 'combined-finding-returns-to-original-bound-writer'
    $combinedRepairPath=Join-Path $control 'combined-repair-package.json';Write-Json $combinedRepairPath $combinedRepair.package
    $combinedRepairDiscover=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$combinedRepairDiscover.observedActor=$combinedWriter;$combinedRepairDiscover.authorizationPackagePath=$combinedRepairPath;$combinedRepairDiscover.expectedAuthorizationIdentity=Get-Identity $combinedRepairPath;$combinedRepairDiscover.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json')
    $combinedRepairProcess=Run-Process $combinedRepairDiscover 'combined-repair-discover';$combinedRepairReceipt=Join-Path $control 'combined-repair-compact.json';Write-Json $combinedRepairReceipt $combinedRepairProcess.compactReceipt
    $combinedRepairBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedRepairReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedRepairReceipt;preparationReceipts=@($combinedRepairProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedRepairBoundary 'combined-repair-admit').status-ceq'PASS') 'combined-finding-repair-passes-real-admission'
    Write-Utf8 $objectPath 'Combined candidate repaired for rereview'
    $combinedRepairBoundary.mode='FINALIZE_OUTPUT';$combinedRepairBoundary.resultReceipts=@($combinedRepairProcess.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedRepairBoundary.deliveryReceipts=@('FIXTURE_REPAIR_RETURN')
    $combinedRepairFinal=Run-Process $combinedRepairBoundary 'combined-repair-finalize';$combinedRepairFinalPath=Join-Path $control 'combined-repair-final-result.json';Write-Json $combinedRepairFinalPath $combinedRepairFinal
    Assert-True ($combinedRepairFinal.status-ceq'PASS') 'combined-finding-repair-binds-real-postimage'
    $combinedBinding.phase='REREVIEW';$combinedBinding.repairFinalizeInputPath=Join-Path $control 'combined-repair-finalize.json';$combinedBinding.repairFinalizeInputIdentity=Get-Identity $combinedBinding.repairFinalizeInputPath;$combinedBinding.repairFinalizeResultPath=$combinedRepairFinalPath;$combinedBinding.repairFinalizeResultIdentity=Get-Identity $combinedRepairFinalPath
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$combinedBinding})
    $combinedRereview=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    Assert-True ($combinedRereview.status-ceq'PREPARED'-and(Invoke-Check $combinedRereview.package $combinedReviewer REVIEW_EXECUTE).Code-eq0) 'combined-rereview-returns-to-same-independent-reviewer'
    $combinedRereviewPath=Join-Path $control 'combined-rereview-package.json';Write-Json $combinedRereviewPath $combinedRereview.package
    $combinedRereviewDiscover=$combinedReviewDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$combinedRereviewDiscover.authorizationPackagePath=$combinedRereviewPath;$combinedRereviewDiscover.expectedAuthorizationIdentity=Get-Identity $combinedRereviewPath
    $combinedRereviewProcess=Run-Process $combinedRereviewDiscover 'combined-rereview-discover';$combinedRereviewReceipt=Join-Path $control 'combined-rereview-compact.json';Write-Json $combinedRereviewReceipt $combinedRereviewProcess.compactReceipt
    $combinedRereviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedRereviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedRereviewReceipt;preparationReceipts=@($combinedRereviewProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedRereviewBoundary 'combined-rereview-admit').status-ceq'PASS') 'combined-rereview-passes-real-admission'
    $combinedRereviewBoundary.mode='FINALIZE_OUTPUT';$combinedRereviewBoundary.resultReceipts=@($combinedRereviewProcess.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedRereviewBoundary.deliveryReceipts=@('FIXTURE_REREVIEW_TO_OWNER')
    Assert-True ((Run-Process $combinedRereviewBoundary 'combined-rereview-finalize').status-ceq'PASS') 'combined-one-delegation-chain-finalizes-without-owner-relay'
  }finally{$env:CODEX_THREAD_ID=$oldHostId;[IO.File]::WriteAllBytes($combinedConfigPath,$combinedConfigOriginal)}
  Write-Json $routeInput ([ordered]@{operation='TERMINAL';terminalStatus='READY';reportChannelAvailable=$true;proposedConsumerRole='TASK_OWNER';controllerEscalationRequired=$false})
  $ownerTerminal=(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json
  Assert-True ($ownerTerminal.status-ceq'READY'-and$ownerTerminal.reason-ceq'DIRECT_CONSUMER_ROUTE'-and-not[bool]$ownerTerminal.ackRequired-and-not[bool]$ownerTerminal.polling) 'approved-review-terminal-routes-once-to-original-owner-without-ack-or-poll'
  $writerAccept=New-Package STANDARD DOMAIN_OWNER writer-fixture OWNER_ACCEPT PRODUCT_RESULT
  $writerAccept.userConfirmation='USER_FIXTURE_ACCEPTED'
  Assert-True ((Invoke-Check $writerAccept writer-fixture OWNER_ACCEPT).Code-ne0) 'temporary-writer-cannot-accept-own-reviewed-result'
  Write-Task STANDARD REVIEW ACTIVE -OwnerRoute
  $ownerAccept=New-Package STANDARD DOMAIN_OWNER owner-fixture OWNER_ACCEPT PRODUCT_RESULT
  $ownerAccept.userConfirmation='USER_FIXTURE_ACCEPTED'
  Assert-True ((Invoke-Check $ownerAccept owner-fixture OWNER_ACCEPT).Code-eq0) 'original-owner-alone-admits-final-acceptance'

  # A domain owner may push one accepted commit to one exact target after a
  # task-scoped user decision. Keep the remote local; this fixture never pushes
  # the second commit.
  & git -C $temp config user.email fixture@example.invalid
  & git -C $temp config user.name 'Fixture Owner'
  & git -C $temp checkout -q -b main
  & git -C $temp add -- $objectRelative
  & git -C $temp commit -qm base
  $remote=Join-Path $temp 'remote.git';& git init -q --bare $remote
  & git -C $temp remote add origin $remote
  & git -C $temp push -q origin main
  $remoteCommit=([string](& git -C $temp rev-parse HEAD)).ToUpperInvariant()
  Write-Utf8 $objectPath 'Accepted second commit'
  & git -C $temp add -- $objectRelative
  & git -C $temp commit -qm accepted
  $localCommit=([string](& git -C $temp rev-parse HEAD)).ToUpperInvariant()
  Write-Task STANDARD GIT
  $decision='USER_FIXTURE_APPROVED_EXACT_PUSH'
  Write-Utf8 $taskPath ((Get-Content -Raw -LiteralPath $taskPath).TrimEnd("`n")+"`nPush authorization: repositoryId=CONTROL; remote=origin; branch=main; decision=$decision`n")
  $evidenceRelative='.ai-workspace/reports/push-acceptance.md';$evidencePath=Join-Path $temp $evidenceRelative
  Write-Utf8 $evidencePath "Review=NOT_REQUIRED; OwnerAccept=ACCEPTED`nAcceptedCommit=$localCommit"
  $remoteUrl=[string](& git -C $temp remote get-url --push origin);$remoteUrlBytes=$utf8.GetBytes($remoteUrl)
  $remoteUrlIdentity=$remoteUrlBytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($remoteUrlBytes))
  $push=New-Package STANDARD DOMAIN_OWNER owner-fixture PUSH EXTERNAL_ACTION
  $push.schemaVersion=2;$push['repositoryId']='CONTROL';$push.delegatedGitCloser=$true;$push.userConfirmation=$decision;$push.invalidatesOn+=@('REPOSITORY_CHANGE')
  $push['gitPushBinding']=[ordered]@{remote='origin';branch='main';remoteUrlIdentity=$remoteUrlIdentity;expectedRemoteCommit=$remoteCommit;localCommit=$localCommit;acceptanceEvidencePath=$evidenceRelative;acceptanceEvidenceIdentity=Get-Identity $evidencePath}
  $push.taskIdentity=Get-Identity $taskPath
  $pushCheck=Invoke-Check $push owner-fixture PUSH
  if($pushCheck.Code-ne0){Write-Output ('DIAG|domain-owner-push|'+$pushCheck.Text)}
  Assert-True ($pushCheck.Code-eq0) 'domain-owner-exact-accepted-push-package-passes'
  $noDecision=$push|ConvertTo-Json -Depth 50|ConvertFrom-Json;$noDecision.userConfirmation='NOT_REQUIRED'
  Assert-True ((Invoke-Check $noDecision owner-fixture PUSH).Code-ne0) 'domain-owner-push-rejects-missing-user-decision'
  $staleRemote=$push|ConvertTo-Json -Depth 50|ConvertFrom-Json;$staleRemote.gitPushBinding.expectedRemoteCommit=$localCommit
  Assert-True ((Invoke-Check $staleRemote owner-fixture PUSH).Code-ne0) 'domain-owner-push-rejects-remote-parent-drift'
  Write-Utf8 $objectPath 'Unreviewed replacement commit'
  & git -C $temp add -- $objectRelative
  & git -C $temp commit -q --amend -m unreviewed
  $unreviewedCommit=([string](& git -C $temp rev-parse HEAD)).ToUpperInvariant()
  $rebound=$push|ConvertTo-Json -Depth 50|ConvertFrom-Json;$rebound.gitPushBinding.localCommit=$unreviewedCommit
  foreach($object in @($rebound.objectIdentities)){if([string]$object.path -ceq $objectRelative){$object.identity=Get-Identity $objectPath}}
  $oldAcceptance=Invoke-Check $rebound owner-fixture PUSH
  Assert-True ($oldAcceptance.Code-ne0 -and $oldAcceptance.Text -match 'DOMAIN_PUSH_ACCEPTED_COMMIT_DRIFT') 'domain-owner-push-rejects-old-acceptance-for-new-same-parent-pathset-commit'
  & git -C $temp reset -q --hard $localCommit
  $foreignIndex=Join-Path $temp 'foreign.txt';Write-Utf8 $foreignIndex 'Other owner';& git -C $temp add -- foreign.txt
  Assert-True ((Invoke-Check $push owner-fixture PUSH).Code-ne0) 'domain-owner-push-rejects-shared-index'
}finally{
  if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$tempResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));$tempPrefix=$tempRoot+[IO.Path]::DirectorySeparatorChar;$tempLeaf=[IO.Path]::GetFileName($tempResolved);if(-not$tempResolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)-or$tempLeaf-cnotmatch'^aiw-authorization-receipt-[a-f0-9]{32}$'){throw 'TEMP_CLEANUP_BOUNDARY'};Get-ChildItem -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue}
}
Write-Output ('RESULT|'+$passed+' passed|scope=authorization-receipt-regression')
