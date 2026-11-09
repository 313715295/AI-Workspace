[CmdletBinding()]
param([ValidateSet('All','NativeIO','RuntimeMaintenance','ExternalCompletion')][string]$Case='All',[string]$OriginalExternalRuntimeRoot='')
if($OriginalExternalRuntimeRoot-and$Case-cne'ExternalCompletion'){throw 'ORIGINAL_EXTERNAL_RUNTIME_REQUIRES_FOCUSED_CASE'}
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
function Invoke-ProcessRuntimeMaintenanceConsumer {
 Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'result-acceptance-tests.ps1'),'-Group','RuntimeMaintenance') -WorkingDirectory (Get-Location).Path -GroupId 'runtime-maintenance-process'
 $run.Output|Write-Output
 if($run.Code-ne0){throw ('RUNTIME_MAINTENANCE_NATIVE|exit='+$run.Code)}
}
if($Case-ceq'RuntimeMaintenance'){
 Invoke-ProcessRuntimeMaintenanceConsumer
 Write-Output 'EVIDENCE_CEILING|PARTIAL|runtime-maintenance-original-admission-delete-finalize|synthetic-qualification-only'
 return
}
Import-Module (Join-Path $PSScriptRoot 'IntegrationFixture.psm1') -Force
$integrationContext=$null
try {
 $integrationContext=New-IntegrationContext (Join-Path $PSScriptRoot '..') 'process'
 foreach($key in $integrationContext.Keys){if($key-ceq'script:testJunctions'){$script:testJunctions=$integrationContext[$key]}else{Set-Variable -Name $key -Value $integrationContext[$key]}}
function Test-IntegrationOriginalExternalCompletion([string]$OriginalRuntimeRoot='') {
 # The portable case uses isolated synthetic qualification. The optional old
 # runtime is an actual immutable package, registered into a new private project.
 $toolRoot=Join-Path $temp 'external-completion-tool'
 $toolVersion=New-IntegrationRuntimeFixture $toolRoot -Maintenance
 $null=Seal-ReleaseFixture $toolVersion 'ORIGINAL_EXTERNAL_TEST_FIXTURE'
 Seal-MaintenanceRuntimeFixture $toolRoot
 $originalRoot=if($OriginalRuntimeRoot){[IO.Path]::GetFullPath($OriginalRuntimeRoot)}else{$toolRoot}
 $originalVersion=Join-Path $originalRoot 'framework/versions/2.0.0'
 $originalResolver=Join-Path $originalVersion 'scripts/resolve-process-requirements.ps1'
 $root=Join-Path $temp 'external-completion-project';$null=[IO.Directory]::CreateDirectory($root)
 $cp=Join-Path $root '.ai-workspace';$projectId='external-completion-fixture';$taskId='EXTERNAL-COMPLETION-001';$actor='owner-fixture'
 $taskRelative='.ai-workspace/tasks/active/'+$taskId+'.md';$taskPath=Join-Path $root $taskRelative
 function External-SaveJson([string]$Path,$Value){Write-Utf8 $Path ($Value|ConvertTo-Json -Depth 100)}
 function External-Ref([string]$Path){[ordered]@{path=$Path;identity=Get-Identity $Path}}
 function External-RunJson([string]$Script,[string[]]$Arguments,[string]$OutputPath){
  $run=Invoke-Ps $Script $Arguments $root
  Write-Utf8 $OutputPath $run.Stdout
  $value=try{$run.Stdout|ConvertFrom-Json -Depth 100}catch{throw ('EXTERNAL_NATIVE_JSON|'+$run.Code+'|'+$run.Text)}
  return [pscustomobject]@{Run=$run;Value=$value;Ref=(External-Ref $OutputPath)}
 }
 $savedHostActor=$env:CODEX_THREAD_ID;$env:CODEX_THREAD_ID=$actor
 try{
  if($OriginalRuntimeRoot){
   $initial=Join-Path $temp 'EXTERNAL-REGISTER-001.md'
   Write-Utf8 $initial @'
# EXTERNAL-REGISTER-001 — Isolated original external compatibility project
- Task schema: 2.0.0
- Status: ACTIVE
- Profile: CRITICAL; reason=Register the immutable original source for a bounded compatibility test.
- Owner: owner-fixture
- Work route: actor=owner-fixture; role=CONTROLLER; phase=IMPLEMENT
- Phase gate: FALSE
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=REGISTER; expected_paths=[.ai-workspace/PROJECT.md]; actual_paths=[.ai-workspace/PROJECT.md]
- Writer / reviewer / authorization: isolated fixture only
- Git / push / external: no real provider
## Current
- Goal: Register this isolated project and inspect one actual local tool result under the unchanged original runtime.
- Acceptance: Real original admission, source-drift failure, new read-only historical completion; no provider replay.
'@
   $registerArgs=@('-ProjectId',$projectId,'-DisplayName','Original external compatibility fixture','-RepositoryPath',$root,'-FrameworkVersion','2.0.0','-ControllerId',$actor,'-WorkspaceRoot',$originalRoot,'-LocalCandidatePilot','-InitialTaskPath',$initial,'-ExpectedInitialTaskIdentity',(Get-Identity $initial),'-InitialTaskRelativePath','.ai-workspace/tasks/active/EXTERNAL-REGISTER-001.md','-Apply')
   $registered=Invoke-Ps (Join-Path $originalRoot 'scripts/register-project.ps1') $registerArgs $root
   Assert-True ($registered.Code-eq0-and(Test-Path -LiteralPath (Join-Path $cp 'upgrade-recovery/2.0.0/state.json'))) ('actual-original-runtime-registration|'+$registered.Text)
  }else{
   External-SaveJson (Join-Path $cp 'project.json') ([ordered]@{schemaVersion=7;id=$projectId;displayName='External completion fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
   External-SaveJson (Join-Path $cp 'controller.json') ([ordered]@{schemaVersion=1;projectId=$projectId;controllerId=$actor;controllerEpoch=1;state='CURRENT'})
   External-SaveJson (Join-Path $cp 'corrections.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId=$projectId;corrections=@()})
   Write-Utf8 (Join-Path $cp 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
  }
  $configPath=Join-Path $cp 'project.json';$policyPath=Join-Path $cp 'process-policy.json'
  $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
  $config.sourceBindings=@([pscustomobject]@{id='fixture-docs';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='FILE';locator='docs/original.md'});decisionLocator='fixture:original-source-scope'})
  External-SaveJson $configPath $config;Write-Utf8 (Join-Path $root 'docs/original.md') 'Original source; unrelated to the external request.'
  $policy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId=$projectId;rules=@()};External-SaveJson $policyPath $policy
  Write-Utf8 $taskPath ("# $taskId - original external fixture`n- Task schema: 2.0.0`n- Owner: $actor`n- Work route: actor=$actor; role=TASK_OWNER; phase=EXTERNAL`n- Status: ACTIVE`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[request.txt]; actual_paths=[]`n")
  $rd=Join-Path $cp ('runtime/'+$taskId+'/'+$actor);$null=[IO.Directory]::CreateDirectory($rd)
  $preimage=Join-Path $rd 'original-project.json';[IO.File]::Copy($configPath,$preimage,$false)
  $request=Join-Path $root 'request.txt';Write-Utf8 $request 'Only this local fixture request is authorized.'
  $grant=Join-Path $rd 'original-grant.txt';Write-Utf8 $grant 'SIMULATED original user permits owner-fixture to perform LOCAL-1 once with this request, isolated-local-tool, zero retries, no account, network, money or publication; only its local result is used.'
  $flags=[ordered]@{};foreach($name in @('paymentOrSubscription','commercialLicensing','accountOrCredentialChange','publicPublication','installation','protectedOrSecretUpload','crossDomain','formalAssetActivation','projectPhaseChange','gitOrPush','sharedQuotaOrResource','unknownScope')){$flags[$name]=$false}
  $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId=$taskId;profile='STANDARD';lifecycle='ACTIVE';owner=$actor;issuer=$actor;issuerRole='TASK_OWNER';grantee=$actor;bundle='EXTERNAL_LOCAL_FIXTURE';decisionClass='EXTERNAL_ACTION';userConfirmation='SIMULATED_ORIGINAL_RESOURCE_GRANT';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@('EXTERNAL');exactPaths=@('request.txt');objectIdentities=@([ordered]@{path='request.txt';identity=Get-Identity $request});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=Get-Identity $configPath;externalBinding=[ordered]@{schemaVersion=2;route='TASK_OWNER_DIRECT_DOMAIN_EXTERNAL';provider='isolated-local-tool';orderedOperations=@([ordered]@{operationId='LOCAL-1';operationKind='LOCAL_COUNTER';declaredInputClass='EXACT_PAYLOADS';payloads=@([ordered]@{payloadKind='normalized-text';normalizedIdentity=Get-Identity $request;canonicalizationVersion='UTF8_LF_V1'})});outputUse='isolated local result';perOperationRetryCeiling=0;totalRetryCeiling=0;stopConditions=@('stop after this call','stop on unknown consumption');batchExecutionMode='ONE_LOGICAL_ATOMIC_EXECUTION';reissuable=$false;ambiguousConsumptionPolicy='BLOCK';escalationFlags=$flags;grantRefs=@((External-Ref $grant));grantAssessment=[ordered]@{status='CURRENT_AND_COVERED';withdrawalOrReplacementObserved=$false;provider='isolated-local-tool';operationIds=@('LOCAL-1');outputUse='isolated local result';paidResourceUse=$false;sharedResourceUse=$false}}}
  $packagePath=Join-Path $rd 'original-package.json';External-SaveJson $packagePath $package
  $inputValue=[ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=[ordered]@{mode='FULL'};projectRoot=$root;frameworkRoot=$originalRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity $configPath;expectedCorrectionsIdentity=Get-Identity (Join-Path $cp 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor=$actor;capabilities=@();exactPaths=@('request.txt');forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=Get-Identity $packagePath;userDecision=$package.userConfirmation;recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=[ordered]@{schemaVersion=2;objective='Observe one original local fixture call and preserve its actual result';requestedActionKind='EXTERNAL';requestedResultKind='EXTERNAL_RESULT';semanticHints=@();pathHints=@('request.txt');capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software')};workType=[ordered]@{state='KNOWN';values=@('aiw:implementation')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:code')};stage=[ordered]@{state='KNOWN';values=@('aiw:implementation')}}}}
  # Valid directory scopes belong to the original real DISCOVER, not a
  # subsequently edited compact. No protected target is created or inspected.
  $inputValue.forbiddenPaths=@('protected-output/','private-evidence/')
  $discoverPath=Join-Path $rd 'original-discover.json';External-SaveJson $discoverPath $inputValue
  $discovered=External-RunJson $originalResolver @('-InputPath',$discoverPath,'-AsJson') (Join-Path $rd 'original-discover-result.json')
  Assert-True ($discovered.Run.Code-eq0-and$discovered.Value.status-ceq'PASS') ('original-external-discover|'+$discovered.Run.Text)
  $compact=$discovered.Value.compactReceipt;$compactPath=Join-Path $rd 'original-compact.json';External-SaveJson $compactPath $compact
  # Preserve the actual older boundary3 shape: no evidenceRefs property.
  $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compactPath;expectedDiscoverReceiptIdentity=Get-Identity $compactPath;preparationReceipts=@($compact.selectedObligations|ForEach-Object preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity=$package.userConfirmation;protectionState='BOUND'}
  # The original protocol binds a public decision identity, not its free-text label.
  $boundary.publicDecisionIdentity=Get-Identity $grant
  $admitPath=Join-Path $rd 'original-admit.json';External-SaveJson $admitPath $boundary
  $admitted=External-RunJson $originalResolver @('-InputPath',$admitPath,'-AsJson') (Join-Path $rd 'original-admit-result.json')
  Assert-True ($admitted.Run.Code-eq0-and$admitted.Value.status-ceq'PASS') ('original-external-real-admit|'+$admitted.Run.Text)
  $tool=Join-Path $root 'local-once.ps1';$observation=Join-Path $rd 'native-observation.json'
  Write-Utf8 $tool @'
param([string]$OutputPath,[string]$RequestPath,[string]$ExpectedRequestIdentity)
$ErrorActionPreference='Stop'
if([IO.File]::Exists($OutputPath)){throw 'LOCAL_CALL_ALREADY_OBSERVED'}
$requestBytes=[IO.File]::ReadAllBytes($RequestPath)
$requestIdentity=$requestBytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($requestBytes))
if($requestIdentity-cne$ExpectedRequestIdentity){throw 'LOCAL_REQUEST_OUTSIDE_ORIGINAL_GRANT'}
$value=[ordered]@{outcome='SUCCESS';calls=1;retries=0;provider='isolated-local-tool';operation='LOCAL_COUNTER';requestIdentity=$requestIdentity;processId=$PID;observedUtc=[DateTimeOffset]::UtcNow.ToString('o')}
[IO.File]::WriteAllText($OutputPath,($value|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
$value|ConvertTo-Json -Compress
'@
  $called=Invoke-Ps $tool @('-OutputPath',$observation,'-RequestPath',$request,'-ExpectedRequestIdentity',$package.externalBinding.orderedOperations[0].payloads[0].normalizedIdentity) $root
  $actual=Get-Content -LiteralPath $observation -Raw|ConvertFrom-Json
  Assert-True ($called.Code-eq0-and$actual.calls-eq1-and$actual.retries-eq0-and$actual.processId-ne$PID-and$actual.requestIdentity-ceq$package.externalBinding.orderedOperations[0].payloads[0].normalizedIdentity) 'original-external-tool-is-one-real-isolated-native-call-with-original-exact-request'
  $originalObservationIdentity=Get-Identity $observation
  $config.sourceBindings[0].allowedPaths+=@([pscustomobject]@{kind='FILE';locator='docs/unrelated.md'});External-SaveJson $configPath $config
  $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($compact.selectedObligations|ForEach-Object resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|request.txt|'+(Get-Identity $request))
  $finalPath=Join-Path $rd 'original-finalize.json';External-SaveJson $finalPath $boundary
  $failed=External-RunJson $originalResolver @('-InputPath',$finalPath,'-AsJson') (Join-Path $rd 'original-finalize-result.json')
  Assert-True ($failed.Run.Code-ne0-and$failed.Value.status-ceq'FAIL'-and$failed.Value.reason-ceq'DISCOVER_SOURCE_DRIFT|projectConfigIdentity') ('original-source-drift-failure-is-real|'+$failed.Run.Text)
  # The old task is now closed and released; today's policy is not the old one.
  Write-Utf8 $taskPath ("# $taskId - original external fixture`n- Task schema: 2.0.0`n- Owner: $actor`n- Work route: actor=$actor; role=TASK_OWNER; phase=EXTERNAL`n- Status: CLOSED`n- Closure outcome: SUCCESS`n- Range summary: profile=STANDARD; lifecycle=CLOSED; expected_paths=[request.txt]; actual_paths=[request.txt]`n- Writer / reviewer / authorization: RELEASED`nOriginal failure and native result retained; this is fixture history, no new execution permission.`n")
  $policy.rules=@([ordered]@{ruleId='LATER_POLICY';requirementReason='Later project policy';effectiveRule='No new local tool request is permitted by this historical completion.';selectors=[ordered]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:later-policy'})
  External-SaveJson $policyPath $policy
  $decision=Join-Path $rd 'completion-decision.txt';Write-Utf8 $decision 'SIMULATED current project decision permits read-only recording of the already observed original result; it does not reopen the closed task or permit another tool call.'
  $change=Join-Path $rd 'later-change.txt';Write-Utf8 $change ('Later policy change observed after native result '+$actual.observedUtc+'; current time '+[DateTimeOffset]::UtcNow.ToString('o'))
  $completion=[ordered]@{schemaVersion=1;kind='ORIGINAL_EXTERNAL_RESULT_COMPLETION';projectId=$projectId;originalAdmission=[ordered]@{inputRef=(External-Ref $admitPath);resultRef=$admitted.Ref};originalFinalize=[ordered]@{inputRef=(External-Ref $finalPath);resultRef=$failed.Ref};originalProjectConfigRef=(External-Ref $preimage);toolObservationRef=(External-Ref $observation);completionDecisionRef=(External-Ref $decision);completionPermission='CURRENT_AND_COVERED';invocationAssessment=[ordered]@{permissionAtInvocation='CURRENT_AND_COVERED';changeTiming='AFTER_EXECUTION';operationIds=@('LOCAL-1');rationale='Original real admission and one local observation precede this later policy change; the original task has closed.';changeEvidenceRef=(External-Ref $change)}}
  $completionPath=Join-Path $rd 'completion.json';External-SaveJson $completionPath $completion
  $upgrader=Join-Path $toolRoot 'scripts/upgrade-project.ps1'
  function External-Complete([string]$Path,[string]$Name){External-RunJson $upgrader @('-ProjectId',$projectId,'-ToVersion','2.0.0','-RepositoryPath',$root,'-ActorRouteActor',$actor,'-CompleteOriginalExternalResult','-OriginalExternalCompletionInputPath',$Path,'-ExpectedOriginalExternalCompletionIdentity',(Get-Identity $Path)) (Join-Path $rd ($Name+'-result.json'))}
  $completed=External-Complete $completionPath 'completion'
  $originalCompactIdentity=Get-Identity $compactPath
  Assert-True ($completed.Run.Code-eq0-and$completed.Value.status-ceq'PASS'-and$completed.Value.actionOutcome-ceq'SUCCESS'-and$completed.Value.configChange-ceq'SOURCE_ALLOWED_PATHS_ADDED_ONLY'-and$completed.Value.originalPolicyIdentity-cne$completed.Value.currentPolicyIdentity) ('historical-completion-after-unrelated-config-addition-closed-task-and-later-policy|'+$completed.Run.Text)
  Assert-True ($completed.Value.successorState-ceq'NONE'-and-not$completed.Value.authorityGranted-and$completed.Value.futureExecution-ceq'NOT_GRANTED'-and-not$completed.Value.taskExecutionReopened-and$null-eq$completed.Value.PSObject.Properties['decisionIdentity']-and(Get-Identity $observation)-ceq$originalObservationIdentity-and(Get-Identity $failed.Ref.path)-ceq$failed.Ref.identity) 'historical-result-preserves-failure-and-native-fact-with-no-replay-or-successor-receipt'
  # Both completion frontdoors share this pre-read guard. An absent carrier
  # beneath a protected prefix must fail here, before any attempted open.
  $blockedCarrier=Join-Path $root 'private-evidence/never-open.json'
  $placeholderIdentity='1|'+('A'*64)
  $protectedExternal=External-RunJson $upgrader @('-ProjectId',$projectId,'-ToVersion','2.0.0','-RepositoryPath',$root,'-ActorRouteActor',$actor,'-CompleteOriginalExternalResult','-OriginalExternalCompletionInputPath',$blockedCarrier,'-ExpectedOriginalExternalCompletionIdentity',$placeholderIdentity,'-OriginalExternalForbiddenPath','private-evidence/') (Join-Path $rd 'protected-external-carrier-result.json')
  Assert-True ($protectedExternal.Run.Code-ne0-and$protectedExternal.Run.Text.Contains('ORIGINAL_SOURCE_PROTECTED_PATH')) 'external-completion-trailing-directory-scope-denies-carrier-before-read'
  $protectedSource=Invoke-Ps $upgrader @('-ProjectId',$projectId,'-ToVersion','2.0.0','-RepositoryPath',$root,'-ActorRouteActor',$actor,'-AdoptionProcessMode','FINALIZE_OUTPUT','-CurrentProcessInputPath',$blockedCarrier,'-ExpectedCurrentProcessInputIdentity',$placeholderIdentity,'-OriginalSourceForbiddenPath','private-evidence/') $root
  Assert-True ($protectedSource.Code-ne0-and$protectedSource.Text.Contains('ORIGINAL_SOURCE_PROTECTED_PATH')) 'source-completion-shares-directory-prefix-pre-read-protection'
  $stateModule=@(Import-Module (Join-Path $toolRoot 'scripts/ProjectAdoptionState.psm1') -PassThru)[0]
  & $stateModule {param($r) Assert-AiwOriginalCompletionReadPaths $r @('private-evidence-peer/input.json') @('private-evidence/')} $root
  Assert-True $true 'directory-protection-retains-segment-boundary-for-sibling-prefix'
  foreach($badPrefix in @('private//evidence/','private/../evidence/','private\evidence/')){
   $reason='';try{& $stateModule {param($r,$p) Assert-AiwOriginalCompletionReadPaths $r @() @($p)} $root $badPrefix}catch{$reason=$_.Exception.Message}
   Assert-True ($reason-ceq'RELATIVE_PATH_INVALID') ('directory-scope-still-refuses-malformed-relative-prefix|'+$badPrefix)
  }
  $reason='';try{& $stateModule {Assert-AiwRelativePath 'ordinary-file/'}}catch{$reason=$_.Exception.Message}
  Assert-True ($reason-ceq'RELATIVE_PATH_INVALID') 'directory-prefix-normalization-does-not-relax-ordinary-file-paths'
  # Negative consumer inputs are new counterexamples, never rewritten history.
  foreach($case in @('MISSING_ADMISSION','MISSING_ORIGINAL_OBLIGATION','WITHDRAWN_BEFORE','UNKNOWN_TIMING','UNKNOWN_OBSERVATION','FAILURE_OBSERVATION')){
   $bad=$completion|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
   switch($case){
    MISSING_ADMISSION{$bad.originalAdmission.resultRef.path=Join-Path $rd 'never-admitted.json'}
    MISSING_ORIGINAL_OBLIGATION{
     $badFinal=$boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badFinal.resultReceipts=@($badFinal.resultReceipts|Where-Object{$_-cne'EXTERNAL_RESULT_OBSERVED'})
     $badFinalPath=Join-Path $rd 'missing-obligation-final.json';External-SaveJson $badFinalPath $badFinal;$bad.originalFinalize.inputRef=External-Ref $badFinalPath
    }
    WITHDRAWN_BEFORE{$bad.invocationAssessment.permissionAtInvocation='WITHDRAWN';$bad.invocationAssessment.changeTiming='BEFORE_EXECUTION';$bad.invocationAssessment.rationale='Counterexample input: alleged withdrawal before execution must not be accepted as a completed authorized action.'}
    UNKNOWN_TIMING{$bad.invocationAssessment.changeTiming='UNKNOWN';$bad.invocationAssessment.PSObject.Properties.Remove('changeEvidenceRef')}
    {$_-cin@('UNKNOWN_OBSERVATION','FAILURE_OBSERVATION')}{
     $counterexampleObservation=$actual|ConvertTo-Json -Depth 20|ConvertFrom-Json
     $counterexampleObservation.outcome=if($case-ceq'UNKNOWN_OBSERVATION'){'UNKNOWN'}else{'FAILURE'}
     $counterexampleObservation|Add-Member fixtureCounterexample $true
     $counterexampleObservationPath=Join-Path $rd ($case+'.json');External-SaveJson $counterexampleObservationPath $counterexampleObservation
     $bad.toolObservationRef=External-Ref $counterexampleObservationPath
    }
   }
   $badPath=Join-Path $rd ('counterexample-'+$case+'.json');External-SaveJson $badPath $bad;$rejected=External-Complete $badPath ('counterexample-'+$case)
   if($case-cin@('WITHDRAWN_BEFORE','UNKNOWN_TIMING')){Assert-True ($rejected.Run.Code-eq3-and$rejected.Value.status-ceq'INCOMPLETE'-and$rejected.Value.actionOutcome-ceq'SUCCESS'-and$rejected.Value.futureExecution-ceq'NOT_GRANTED') ('historical-'+$case+'-preserves-fact-without-claiming-authorized-completion')}
   elseif($case-ceq'UNKNOWN_OBSERVATION'){Assert-True ($rejected.Run.Code-eq3-and$rejected.Value.status-ceq'INCOMPLETE'-and$rejected.Value.actionOutcome-ceq'UNKNOWN'-and$rejected.Value.futureExecution-ceq'NOT_GRANTED') 'historical-unknown-consumption-is-incomplete-without-new-call-right'}
   elseif($case-ceq'FAILURE_OBSERVATION'){Assert-True ($rejected.Run.Code-eq0-and$rejected.Value.status-ceq'PASS'-and$rejected.Value.actionOutcome-ceq'FAILURE'-and$rejected.Value.futureExecution-ceq'NOT_GRANTED') 'historical-completion-status-does-not-relabel-tool-failure-as-success'}
   else{Assert-True ($rejected.Run.Code-ne0-and$rejected.Value.status-ceq'FAIL') ('historical-'+$case+'-refused')}
  }
  Assert-True ((Get-Identity $observation)-ceq$originalObservationIdentity-and(Get-Identity $failed.Ref.path)-ceq$failed.Ref.identity-and(Get-Identity $compactPath)-ceq$originalCompactIdentity) 'all-historical-counterexamples-leave-original-tool-result-failure-and-directory-scopes-unchanged'
  Write-Output ('EVIDENCE_CEILING|historical-external-read-only|original='+$(if($OriginalRuntimeRoot){'ACTUAL_UNCHANGED_FIXED_RUNTIME'}else{'ISOLATED_COMPATIBLE_RUNTIME'})+'|new-tool=SYNTHETIC_QUALIFICATION|host-actor=SIMULATED|paid-provider=NOT_CALLED')
 }finally{$env:CODEX_THREAD_ID=$savedHostActor}
}

 if($Case-cin@('All','ExternalCompletion')){Test-IntegrationOriginalExternalCompletion $OriginalExternalRuntimeRoot}
 if($Case-ceq'ExternalCompletion'){Write-Output 'EVIDENCE_CEILING|PARTIAL|original-external-result-completion';return}
    Import-Module (Join-Path $candidateRoot 'scripts\ProcessRequirementComposition.psm1') -Force
 $correctionChecker=Join-Path $candidateRoot 'scripts/check-project-corrections.ps1'
 $correctionFrameworkRoot=Join-Path $temp 'correction-framework-fixture'
 $null=New-IntegrationRuntimeFixture $correctionFrameworkRoot
    $null=Seal-ReleaseFixture (Join-Path $correctionFrameworkRoot 'framework\versions\2.0.0') 'CORRECTION_TEST_FIXTURE'
    $correctionRoot=Join-Path $temp 'correction-fixture'
    New-GitRepo $correctionRoot
    New-Item -ItemType Directory -Path (Join-Path $correctionRoot '.ai-workspace') -Force|Out-Null
    $correctionConfig=[ordered]@{schemaVersion=7;id='correction-fixture';displayName='Correction Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}
    $correctionConfigPath=Join-Path $correctionRoot '.ai-workspace\project.json';Write-Utf8 $correctionConfigPath ($correctionConfig|ConvertTo-Json -Depth 20)
    $correctionControllerPath=Join-Path $correctionRoot '.ai-workspace\controller.json';Write-Utf8 $correctionControllerPath (([ordered]@{schemaVersion=1;projectId='correction-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})|ConvertTo-Json -Depth 10)
    $policyPath=Join-Path $correctionRoot '.ai-workspace\process-policy.json';$defaultPolicy=[ordered]@{schemaVersion=1;contractVersion='2.0.0';projectId='correction-fixture';selectedRulePackBytes=32768;rules=@()};$routineFixturePolicy=$defaultPolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$routineFixturePolicy.selectedRulePackBytes=98304;Write-CurrentFixtureObject PROCESS_POLICY $policyPath $routineFixturePolicy
    Write-Utf8 (Join-Path $correctionRoot '.ai-workspace\BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nProject-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.`n<!-- PROJECT-CUSTOM:END -->`n"
    $correctionRecords=[ordered]@{schemaVersion=1;contractVersion='1.10.0';projectId='correction-fixture';corrections=@(
        [ordered]@{correctionId='OWNER_FIRST_DIRECT_DOMAIN_ROUTE';introducedAgainstFramework='<=1.8.0';requirementReason="观察到不必要的中转 😀 `"quoted`" C:\reason`n第二行";effectiveRule="领域负责人直接处理 😀 `"quoted`" C:\rule`n`n完整末行";applicability='Unchanged domain task';decisionLocator='task:owner-first'},
        [ordered]@{correctionId='PROJECT_CORRECTION_LIFECYCLE';introducedAgainstFramework='1.9.0';requirementReason='No deterministic cross-version retention';effectiveRule='Retain and evaluate project correction records';applicability='Framework pin adoption and recovery';decisionLocator='task:correction-lifecycle'}
    )}
    # Keep the old authoring records for the explicit adapter test below;
    # normal PRECHECK consumes the current projected carrier.
    $correctionPath=Join-Path $correctionRoot '.ai-workspace\corrections.json';Write-CurrentFixtureObject PROJECT_CORRECTIONS $correctionPath $correctionRecords
    $correctionArgs=@('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','2.0.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')
    $correctionMatched=Invoke-Ps $correctionChecker $correctionArgs
    Write-Output ('OBSERVE|correction-precheck|code='+$correctionMatched.Code+'|text='+$correctionMatched.Text.Trim())
    $correctionMatchedValue=$correctionMatched.Output[-1]|ConvertFrom-Json
    Write-Output ('OBSERVE|correction-precheck-json|'+($correctionMatchedValue|ConvertTo-Json -Depth 12 -Compress))
    Assert-True ($correctionMatched.Code-eq0-and@($correctionMatchedValue.stillEffective).Count-eq2-and$null-eq$correctionMatchedValue.PSObject.Properties['incorporated']) 'project-owned-records-effective-without-central-registration'
    Assert-True ($correctionMatched.Stderr-ceq''-and$correctionMatched.Stdout-notmatch'[^\x00-\x7f]') 'corrections-native-single-ascii-json-transport'
    foreach($record in $correctionRecords.corrections){
        $actualRecord=@($correctionMatchedValue.stillEffective|Where-Object correctionId -CEQ $record.correctionId)
        Assert-True ($actualRecord.Count-eq1-and[string]::Equals($actualRecord[0].requirementReason,$record.requirementReason,[StringComparison]::Ordinal)-and[string]::Equals($actualRecord[0].effectiveRule,$record.effectiveRule,[StringComparison]::Ordinal)) ('corrections-native-complete-text-'+$record.correctionId)
    }
    $outBefore=[Console]::Out;$errBefore=[Console]::Error;$encodingBefore=[Console]::OutputEncoding
    $inProcessCorrectionArguments=@{ProjectRoot=$correctionRoot;FrameworkRoot=$correctionFrameworkRoot;TargetVersion='2.0.0';ExpectedProjectConfigIdentity=(Get-Identity $correctionConfigPath);ExpectedCorrectionsIdentity=(Get-Identity $correctionPath);Operation='PRECHECK';AsJson=$true}
    $inProcessCorrection=@(& $correctionChecker @inProcessCorrectionArguments)
    Assert-True ($LASTEXITCODE-eq0-and$inProcessCorrection.Count-eq1-and(($inProcessCorrection[0]|ConvertFrom-Json -Depth 100|ConvertTo-Json -Depth 100 -Compress)-ceq($correctionMatchedValue|ConvertTo-Json -Depth 100 -Compress))-and[object]::ReferenceEquals($outBefore,[Console]::Out)-and[object]::ReferenceEquals($errBefore,[Console]::Error)-and[object]::ReferenceEquals($encodingBefore,[Console]::OutputEncoding)) 'corrections-inprocess-native-full-semantic-equality-and-writers'
    $correctionOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionPath
    $correctionDuplicate=$correctionOriginal-replace '"projectId"\s*:\s*"correction-fixture"',('"projectId": "correction-fixture",'+"`n"+'  "\u0070rojectId": "correction-fixture"')
    Write-Utf8 $correctionPath $correctionDuplicate
    $correctionDuplicateRun=Invoke-Ps $correctionChecker @('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','2.0.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')
    Assert-True ($correctionDuplicateRun.Code-ne0-and$correctionDuplicateRun.Text.Contains('JSON_DUPLICATE_FIELD')) 'corrections-unicode-duplicate-field-fails-closed'
    Write-Utf8 $correctionPath $correctionOriginal
    $missingCorrectionRoot=Join-Path $temp 'correction-missing-fixture';New-Item -ItemType Directory -Path (Join-Path $missingCorrectionRoot '.ai-workspace') -Force|Out-Null
    $missingCorrectionConfigPath=Join-Path $missingCorrectionRoot '.ai-workspace\project.json';Write-Utf8 $missingCorrectionConfigPath (($correctionConfig|ConvertTo-Json -Depth 20).Replace('correction-fixture','correction-missing-fixture'))
    $missingCorrectionPolicy=$routineFixturePolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$missingCorrectionPolicy.projectId='correction-missing-fixture';Write-CurrentFixtureObject PROCESS_POLICY (Join-Path $missingCorrectionRoot '.ai-workspace\process-policy.json') $missingCorrectionPolicy
    Write-Utf8 (Join-Path $missingCorrectionRoot '.ai-workspace\BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nProject-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.`n<!-- PROJECT-CUSTOM:END -->`n"
    $missingCorrectionRun=Invoke-Ps $correctionChecker @('-ProjectRoot',$missingCorrectionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','2.0.0','-ExpectedProjectConfigIdentity',(Get-Identity $missingCorrectionConfigPath),'-Operation','PRECHECK','-AllowMissingCorrections','-AsJson')
    $missingCorrectionValue=$missingCorrectionRun.Output[-1]|ConvertFrom-Json
    Assert-True ($missingCorrectionRun.Code-eq0-and[string]$missingCorrectionValue.correctionsIdentity-ceq'MISSING'-and@($missingCorrectionValue.stillEffective).Count-eq0) 'corrections-legacy-missing-is-empty-set'
    $correctionProjection=Write-CurrentFixtureObject PROJECT_CORRECTIONS $correctionPath $correctionRecords -PassThru
    Assert-True ($correctionProjection.OriginalFormat-eq1-and$correctionProjection.CurrentFormat-eq3-and$correctionProjection.Segments.Count-eq2-and$correctionProjection.Value.corrections.Count-eq2) 'corrections-legacy-adapter-projects-complete-current-group'
    $correctionOriginal=Get-Content -LiteralPath $correctionPath -Raw -Encoding utf8
    $processResolver=Join-Path $correctionFrameworkRoot 'framework\versions\2.0.0\scripts\resolve-process-requirements.ps1'
    $processTaskPath=Join-Path $correctionRoot '.ai-workspace\tasks\active\PROCESS-FIXTURE-001.md'
    Write-Utf8 $processTaskPath "# PROCESS-FIXTURE-001 - process fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[src/public.txt]; actual_paths=[]`n"
    $discoverInputPath=Join-Path $temp 'process-discover.json'
    $processIntent=New-CurrentFixtureIntent ([ordered]@{schemaVersion=1;objective='Implement the bounded source change';requestedActionKind='SOURCE_WRITE';requestedResultKind='USER_RESPONSE';semanticHints=@('implementation');pathHints=@('src/public.txt');capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'})
    $discoverInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$correctionRoot;frameworkRoot=$correctionFrameworkRoot;taskPath=$processTaskPath;expectedProjectConfigIdentity=(Get-Identity $correctionConfigPath);expectedCorrectionsIdentity=(Get-Identity $correctionPath);expectedTaskIdentity=(Get-Identity $processTaskPath);observedActor='owner-fixture';capabilities=@();exactPaths=@('src/public.txt');forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$processIntent;evaluationOnly=$false}
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $discoverRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    $discoverResult=$discoverRun.Output[-1]|ConvertFrom-Json;$discoverValue=$discoverResult.compactReceipt;$discoverBlocks=@($discoverResult.selectedRuleBlocks)
    Assert-True ($discoverRun.Code-eq0-and[string]$discoverValue.status-ceq'PASS'-and-not[bool]$discoverValue.authorityGranted-and-not[bool]$discoverValue.semanticCorrectnessProven-and[string]$discoverValue.binding.actor-ceq'owner-fixture'-and@($discoverBlocks.requirementId)-contains'framework:PR_ACTION_AUTHORIZATION_INDEPENDENT'-and@($discoverBlocks.requirementId)-contains'correction:correction-fixture:PROJECT_CORRECTION_LIFECYCLE'-and@($discoverBlocks.requirementId)-contains'correction:correction-fixture:OWNER_FIRST_DIRECT_DOMAIN_ROUTE') 'process-discover-composes-three-sources-with-project-owned-current-rules'
    foreach($record in $correctionRecords.corrections){
        $block=@($discoverBlocks|Where-Object requirementId -CEQ ('correction:correction-fixture:'+$record.correctionId))
        Assert-True ($block.Count-eq1-and[string]::Equals($block[0].fullText,$record.effectiveRule,[StringComparison]::Ordinal)) ('process-native-correction-fulltext-'+$record.correctionId)
    }
    $projectCapabilityConfigOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionConfigPath
    $projectCapabilityCases=@(
        [pscustomobject]@{Name='unknown-id';TestName='process-resolver-capability-unknown-id-fails-closed';Capabilities=[ordered]@{UNKNOWN=[ordered]@{enabled=$false}};Expected='FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CONFIG'},
        [pscustomobject]@{Name='disabled-extra-field';TestName='process-resolver-capability-disabled-extra-field-fails-closed';Capabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$false;indexLocator='knowledge/index.json'}};Expected='FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CONFIG'},
        [pscustomobject]@{Name='enabled-missing-field';TestName='process-resolver-capability-enabled-missing-field-fails-closed';Capabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$true}};Expected='FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CONFIG'},
        [pscustomobject]@{Name='enabled-extra-field';TestName='process-resolver-capability-enabled-extra-field-fails-closed';Capabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$true;indexLocator='knowledge/index.json';extra='unexpected'}};Expected='FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CONFIG'}
    )
    foreach($capabilityCase in $projectCapabilityCases){
        $projectCapabilityConfig=$projectCapabilityConfigOriginal|ConvertFrom-Json;$projectCapabilityConfig.frameworkCapabilities=$capabilityCase.Capabilities;Write-Utf8 $correctionConfigPath ($projectCapabilityConfig|ConvertTo-Json -Depth 20)
        $projectCapabilityInput=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$projectCapabilityInput.expectedProjectConfigIdentity=Get-Identity $correctionConfigPath;$projectCapabilityInputPath=Join-Path $temp ('process-capability-'+$capabilityCase.Name+'.json');Write-Utf8 $projectCapabilityInputPath ($projectCapabilityInput|ConvertTo-Json -Depth 20)
        $projectCapabilityRun=Invoke-Ps $processResolver @('-InputPath',$projectCapabilityInputPath,'-AsJson')
        Write-Output ('OBSERVE|correction-capability|case='+$capabilityCase.Name+'|code='+$projectCapabilityRun.Code+'|text='+$projectCapabilityRun.Text.Trim())
        $projectCapabilityValue=$projectCapabilityRun.Output[-1]|ConvertFrom-Json
        Assert-True ($projectCapabilityRun.Code-eq2-and$projectCapabilityValue.status-ceq'FAIL'-and$projectCapabilityValue.reason-ceq[string]$capabilityCase.Expected) ([string]$capabilityCase.TestName)
    }
    Write-Utf8 $correctionConfigPath $projectCapabilityConfigOriginal
    $cleanupSuccessPath=Join-Path ([IO.Path]::GetTempPath()) ('aiw-'+[guid]::NewGuid().ToString('N')+'.json');Write-Utf8 $cleanupSuccessPath ($discoverInput|ConvertTo-Json -Depth 20)
    $cleanupSuccessRun=Invoke-Ps $processResolver @('-InputPath',$cleanupSuccessPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($cleanupSuccessRun.Code-eq0-and-not(Test-Path -LiteralPath $cleanupSuccessPath)) 'process-temp-input-cleanup-removes-exact-safe-file-after-success'
    $cleanupFailurePath=Join-Path ([IO.Path]::GetTempPath()) ('aiw-'+[guid]::NewGuid().ToString('N')+'.json');Write-Utf8 $cleanupFailurePath '{'
    $cleanupFailureRun=Invoke-Ps $processResolver @('-InputPath',$cleanupFailurePath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($cleanupFailureRun.Code-ne0-and$cleanupFailureRun.Text.Contains('INPUT_JSON')-and(Test-Path -LiteralPath $cleanupFailurePath)) 'process-temp-input-cleanup-retains-file-when-strict-parse-fails'
    Remove-Item -LiteralPath $cleanupFailurePath -Force
    $projectRuntimeDir=Join-Path $correctionRoot '.ai-workspace\runtime\PROCESS-FIXTURE-001\owner-fixture';New-Item -ItemType Directory -Path $projectRuntimeDir -Force|Out-Null
    $projectRuntimePath=Join-Path $projectRuntimeDir 'discover.json';Write-Utf8 $projectRuntimePath ($discoverInput|ConvertTo-Json -Depth 20)
    $projectRuntimeRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimePath,'-AsJson','-DeleteInputOnExit');$projectRuntimeValue=$projectRuntimeRun.Output[-1]|ConvertFrom-Json
    Assert-True ($projectRuntimeRun.Code-eq0-and[string]$projectRuntimeValue.artifactStorage-ceq'PROJECT_RUNTIME'-and-not(Test-Path -LiteralPath $projectRuntimePath)) 'process-project-runtime-input-is-task-actor-bound-and-cleaned'
    $projectRuntimeDriftDir=Join-Path $correctionRoot '.ai-workspace\runtime\PROCESS-FIXTURE-001\different-actor';New-Item -ItemType Directory -Path $projectRuntimeDriftDir -Force|Out-Null
    $projectRuntimeDriftPath=Join-Path $projectRuntimeDriftDir 'discover.json';Write-Utf8 $projectRuntimeDriftPath ($discoverInput|ConvertTo-Json -Depth 20)
    $projectRuntimeDriftRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeDriftPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($projectRuntimeDriftRun.Code-ne0-and$projectRuntimeDriftRun.Text.Contains('INPUT_RUNTIME_BINDING_DRIFT')-and(Test-Path -LiteralPath $projectRuntimeDriftPath)) 'process-project-runtime-input-binding-drift-fails-closed-and-retains'
    Remove-Item -LiteralPath $projectRuntimeDriftPath -Force
    $unrelatedRuntimeDir=Join-Path $temp 'unrelated-cleanup-project\.ai-workspace\runtime\PROCESS-FIXTURE-001\owner-fixture';New-Item -ItemType Directory -Path $unrelatedRuntimeDir -Force|Out-Null
    $unrelatedRuntimePath=Join-Path $unrelatedRuntimeDir 'discover.json';Write-Utf8 $unrelatedRuntimePath ($discoverInput|ConvertTo-Json -Depth 20)
    $unrelatedRuntimeRun=Invoke-Ps $processResolver @('-InputPath',$unrelatedRuntimePath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($unrelatedRuntimeRun.Code-ne0-and$unrelatedRuntimeRun.Text.Contains('INPUT_RUNTIME_PROJECT_ROOT_DRIFT')-and(Test-Path -LiteralPath $unrelatedRuntimePath)) 'process-unrelated-project-runtime-input-binding-fails-closed-and-retains'
    $unrelatedMalformedRuntimePath=Join-Path $unrelatedRuntimeDir 'malformed.json';Write-Utf8 $unrelatedMalformedRuntimePath '{'
    $unrelatedMalformedRuntimeRun=Invoke-Ps $processResolver @('-InputPath',$unrelatedMalformedRuntimePath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($unrelatedMalformedRuntimeRun.Code-ne0-and$unrelatedMalformedRuntimeRun.Text.Contains('INPUT_JSON')-and(Test-Path -LiteralPath $unrelatedMalformedRuntimePath)) 'process-unrelated-project-malformed-runtime-input-retained-before-binding'
    Remove-Item -LiteralPath $unrelatedRuntimePath,$unrelatedMalformedRuntimePath -Force
    $cleanupUnsafeRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($cleanupUnsafeRun.Code-ne0-and$cleanupUnsafeRun.Text.Contains('INPUT_CLEANUP_PATH_UNSAFE')-and(Test-Path -LiteralPath $discoverInputPath)) 'process-temp-input-cleanup-rejects-unsafe-name-without-deletion'

    $budgetBootstrapPath=Join-Path $correctionRoot '.ai-workspace\BOOTSTRAP.md';$budgetBootstrapOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $budgetBootstrapPath
    $largeLegacyRule=('L'*55000)+"中文 😀 `"quoted`" C:\large`n`n"+('L'*55000)
    $largeLegacyCorrections=[ordered]@{schemaVersion=1;contractVersion='1.10.0';projectId='correction-fixture';corrections=@([ordered]@{correctionId='LEGACY_LARGE_COMPATIBILITY';introducedAgainstFramework='1.15.1';requirementReason='Preserve one verified legacy correction during direct adoption';effectiveRule=$largeLegacyRule;applicability='All governed work until converted';decisionLocator='test:legacy-large'})}
    Write-CurrentFixtureObject PROCESS_POLICY $policyPath $defaultPolicy
    Write-CurrentFixtureObject PROJECT_CORRECTIONS $correctionPath $largeLegacyCorrections;$largeLegacyInput=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$largeLegacyInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($largeLegacyInput|ConvertTo-Json -Depth 20)
    $largeDefaultRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($largeDefaultRun.Code-eq0-and@((($largeDefaultRun.Stdout|ConvertFrom-Json -Depth 100).selectedRuleBlocks)|Where-Object{[string]::Equals($_.fullText,$largeLegacyRule,[StringComparison]::Ordinal)}).Count-eq1) 'process-bytes-over-old-absolute-limit-return-complete-legacy-rule'
    $highBudgetPolicy=$defaultPolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$highBudgetPolicy.selectedRulePackBytes=98304;Write-CurrentFixtureObject PROCESS_POLICY $policyPath $highBudgetPolicy
    $largeRaisedRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$largeRaisedResult=$largeRaisedRun.Output[-1]|ConvertFrom-Json;$largeRaisedReceipt=$largeRaisedResult.compactReceipt
    Assert-True ($largeRaisedRun.Code-eq0-and[int]$largeRaisedReceipt.pack.bytes-gt[int]$budgetContract.ceilings.defaultSelectedRulePackBytes-and[int]$largeRaisedReceipt.pack.bytes-gt98304-and[int]$largeRaisedReceipt.pack.ceilingBytes-eq0) 'legacy-budget-number-does-not-limit-selected-rule-content'
    $invalidBudgetPolicy=$defaultPolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$invalidBudgetPolicy.selectedRulePackBytes=98305;Write-CurrentFixtureObject PROCESS_POLICY $policyPath $invalidBudgetPolicy
    $invalidBudgetRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($invalidBudgetRun.Code-eq0-and@((($invalidBudgetRun.Stdout|ConvertFrom-Json -Depth 100).selectedRuleBlocks)|Where-Object{[string]::Equals($_.fullText,$largeLegacyRule,[StringComparison]::Ordinal)}).Count-eq1) 'legacy-budget-metadata-above-old-cap-is-compatible'
    Write-CurrentFixtureObject PROCESS_POLICY $policyPath $defaultPolicy
    $largeV2Corrections=[ordered]@{schemaVersion=2;contractVersion='2.0.0';projectId='correction-fixture';corrections=@([ordered]@{correctionId='CURRENT_LARGE_RULE';introducedAgainstFramework='1.15.1';requirementReason='Exercise the project-selected ceiling';effectiveRule=$largeLegacyRule;applicability='Bounded source work';decisionLocator='test:current-large';selectors=[ordered]@{profiles=@('STANDARD');roles=@('TASK_OWNER');phases=@('IMPLEMENT');actionKinds=@('SOURCE_WRITE');resultKinds=@('*');pathPrefixes=@('src/');capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@()})}
    Write-CurrentFixtureObject PROJECT_CORRECTIONS $correctionPath $largeV2Corrections;$largeV2Input=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$largeV2Input.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($largeV2Input|ConvertTo-Json -Depth 20)
    $largeV2Run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($largeV2Run.Code-eq0-and@((($largeV2Run.Stdout|ConvertFrom-Json -Depth 100).selectedRuleBlocks)|Where-Object{[string]::Equals($_.fullText,$largeLegacyRule,[StringComparison]::Ordinal)}).Count-eq1) 'current-correction-schema-returns-complete-large-rule'
    Write-Utf8 $budgetBootstrapPath $budgetBootstrapOriginal;Write-Utf8 $correctionPath $correctionOriginal;Write-CurrentFixtureObject PROCESS_POLICY $policyPath $routineFixturePolicy;$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    if($Case-ceq'NativeIO'){Write-Output 'EVIDENCE_CEILING|PARTIAL|process-native-io';return}
    $discoverRaw=$discoverInput|ConvertTo-Json -Depth 20
    $duplicateDiscover=[regex]::Replace($discoverRaw,'"mode"\s*:\s*"DISCOVER"','"mode": "DISCOVER", "mode": "FINALIZE_OUTPUT"',1);Write-Utf8 $discoverInputPath $duplicateDiscover
    $duplicateDiscoverRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($duplicateDiscoverRun.Code-ne0-and$duplicateDiscoverRun.Text.Contains('INPUT_FIELD_COUNT|mode')) 'process-input-rejects-duplicate-mode-before-json-collapse'
    $wrongDiscoverSchema=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$wrongDiscoverSchema.schemaVersion=99;Write-Utf8 $discoverInputPath ($wrongDiscoverSchema|ConvertTo-Json -Depth 20)
    $wrongDiscoverSchemaRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($wrongDiscoverSchemaRun.Code-ne0-and$wrongDiscoverSchemaRun.Text.Contains('INPUT_SCHEMA_VERSION')) 'process-discover-rejects-unknown-input-schema'
    $invalidCorrectionsIdentity=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$invalidCorrectionsIdentity.expectedCorrectionsIdentity='UNBOUND';Write-Utf8 $discoverInputPath ($invalidCorrectionsIdentity|ConvertTo-Json -Depth 20)
    $invalidCorrectionsIdentityRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($invalidCorrectionsIdentityRun.Code-ne0-and$invalidCorrectionsIdentityRun.Text.Contains('INPUT_IDENTITY|expectedCorrectionsIdentity')) 'process-discover-rejects-malformed-corrections-identity'
    $alternateDiscover=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$alternateDiscover.intentEnvelope.requestedActionKind='TEST_RUN';$alternateDiscover.intentEnvelope.mutationHints=@('test');Write-Utf8 $discoverInputPath ($alternateDiscover|ConvertTo-Json -Depth 20)
    $alternateDiscoverRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$alternateDiscoverResult=$alternateDiscoverRun.Output[-1]|ConvertFrom-Json;$alternateDiscoverValue=$alternateDiscoverResult.compactReceipt
    # Action selection changes the complete selected rule closure, while this
    # fixture keeps raw sources and authority unchanged (TOOL_CONTRACT).
    Assert-True ($alternateDiscoverRun.Code-eq0-and[string]$alternateDiscoverValue.status-ceq'PASS'-and($alternateDiscoverValue.binding|ConvertTo-Json -Depth 30 -Compress)-ceq($discoverValue.binding|ConvertTo-Json -Depth 30 -Compress)) 'process-action-selection-preserves-current-authority-binding'
    $sourceBindingDifferences=@($discoverValue.sourceBindings.PSObject.Properties|Where-Object{[string]$_.Value-cne[string]$alternateDiscoverValue.sourceBindings.($_.Name)}|ForEach-Object{$_.Name})
    Assert-True (($alternateDiscoverValue.sourceBindings.PSObject.Properties.Name-join'|')-ceq($discoverValue.sourceBindings.PSObject.Properties.Name-join'|')-and$sourceBindingDifferences.Count-eq1-and$sourceBindingDifferences[0]-ceq'effectiveSetIdentity') 'process-action-selection-preserves-raw-sources-and-changes-selected-effective-set'
    Assert-True ('SOURCE_VALIDATION_SELECTED_CLOSURE_V1'-cin@($discoverValue.evidence.ceilings)-and'SOURCE_VALIDATION_SELECTED_CLOSURE_V1'-cin@($alternateDiscoverValue.evidence.ceilings)-and'framework:PR_EVIDENCE_CEILING_DISCIPLINE'-cnotin@($discoverValue.selectedObligations.requirementId)-and'framework:PR_EVIDENCE_CEILING_DISCIPLINE'-cin@($alternateDiscoverValue.selectedObligations.requirementId)-and[string]$alternateDiscoverValue.sourceCompositionIdentity-cne[string]$discoverValue.sourceCompositionIdentity-and[string]$alternateDiscoverValue.selectionIdentity-cne[string]$discoverValue.selectionIdentity) 'process-source-composition-and-boundary-bind-action-selected-closure'
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $discoverReceiptPath=Join-Path $temp 'process-discover-receipt.json';Write-Utf8 $discoverReceiptPath ($discoverValue|ConvertTo-Json -Depth 30)
    $requiredPrep=@($discoverValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $requiredResult=@($discoverValue.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $boundaryBase=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$discoverReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $discoverReceiptPath);objective=$discoverInput.intentEnvelope.objective;actionKind=$discoverInput.intentEnvelope.requestedActionKind;resultKind=$discoverInput.intentEnvelope.requestedResultKind;exactPaths=@($discoverInput.exactPaths);authorizationIdentity='100|'+('A'*64);preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    $admitInputPath=Join-Path $temp 'process-admit.json';Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $boundaryRaw=$boundaryBase|ConvertTo-Json -Depth 20
    $duplicateBoundary=[regex]::Replace($boundaryRaw,'"authorizationIdentity"\s*:\s*"[^"]+"','"authorizationIdentity": "100|'+('A'*64)+'", "authorizationIdentity": "100|'+('B'*64)+'"',1);Write-Utf8 $admitInputPath $duplicateBoundary
    $duplicateBoundaryRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($duplicateBoundaryRun.Code-ne0-and$duplicateBoundaryRun.Text.Contains('INPUT_FIELD_COUNT|authorizationIdentity')) 'process-boundary-rejects-duplicate-authorization-identity'
    $wrongBoundarySchema=$boundaryBase|ConvertTo-Json -Depth 20|ConvertFrom-Json;$wrongBoundarySchema.schemaVersion=4;Write-Utf8 $admitInputPath ($wrongBoundarySchema|ConvertTo-Json -Depth 20)
    $wrongBoundarySchemaRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($wrongBoundarySchemaRun.Code-ne0-and$wrongBoundarySchemaRun.Text.Contains('INPUT_SCHEMA_VERSION')) 'process-boundary-rejects-unknown-input-schema'
    $receiptRaw=$discoverValue|ConvertTo-Json -Depth 30
    $duplicateReceiptRaw=[regex]::Replace($receiptRaw,'("projectConfigIdentity"\s*:\s*"[^"]+")','$1, "projectConfigIdentity": "MISSING"',1)
    $duplicateReceiptPath=Join-Path $temp 'process-discover-receipt-duplicate.json';Write-Utf8 $duplicateReceiptPath $duplicateReceiptRaw
    $duplicateReceiptBoundary=$boundaryBase|ConvertTo-Json -Depth 20|ConvertFrom-Json;$duplicateReceiptBoundary.discoverReceiptPath=$duplicateReceiptPath;$duplicateReceiptBoundary.expectedDiscoverReceiptIdentity=Get-Identity $duplicateReceiptPath;Write-Utf8 $admitInputPath ($duplicateReceiptBoundary|ConvertTo-Json -Depth 20)
    $duplicateReceiptRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($duplicateReceiptRun.Code-ne0-and$duplicateReceiptRun.Text.Contains('INPUT_FIELD_COUNT|projectConfigIdentity')) 'process-receipt-rejects-nested-duplicate-binding'
    # Both entrypoints must reject forged authority before obligations. Empty
    # and complete receipts duplicated this same fault; real preparation/result
    # success and missing-obligation paths remain in the valid-package groups.
    $boundaryBase.preparationReceipts=@($requiredPrep)
    $boundaryBase.resultReceipts=@($requiredResult);$boundaryBase.deliveryReceipts=@('DIRECT_USER_DELIVERY')
    foreach($boundaryMode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
        $forgedBoundary=$boundaryBase|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $forgedBoundary.mode=$boundaryMode;Write-Utf8 $admitInputPath ($forgedBoundary|ConvertTo-Json -Depth 20)
        $forgedRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        $forgedResult=$forgedRun.Text|ConvertFrom-Json
        Assert-True ($forgedRun.Code-eq2-and$forgedResult.status-ceq'FAIL'-and$forgedResult.reason-ceq'AUTHORIZATION_CONTEXT_DRIFT') ('process-legacy-'+$boundaryMode+'-rejects-fabricated-authorization')
    }
    $boundaryBase.mode='FINALIZE_OUTPUT'
    $contextDrift=$boundaryBase|ConvertTo-Json -Depth 20|ConvertFrom-Json;$contextDrift.actionKind='TEST_RUN';Write-Utf8 $admitInputPath ($contextDrift|ConvertTo-Json -Depth 20)
    $contextDriftRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($contextDriftRun.Code-ne0-and$contextDriftRun.Text.Contains('DISCOVER_CONTEXT_DRIFT')) 'process-boundary-rejects-stale-discover-selection'
    Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $correctionSourceBefore=Get-Content -LiteralPath $correctionPath -Raw -Encoding utf8
    Write-Utf8 $correctionPath ($correctionSourceBefore.TrimEnd("`n")+"`n`n")
    $sourceDriftRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($sourceDriftRun.Code-ne0-and$sourceDriftRun.Text.Contains('DISCOVER_SOURCE_DRIFT|correctionsIdentity')) 'process-boundary-rejects-source-drift-before-action-or-output'
    [IO.File]::WriteAllText($correctionPath,$correctionSourceBefore,[Text.UTF8Encoding]::new($false))
    $actorDrift=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$actorDrift.observedActor='other-actor';Write-Utf8 $discoverInputPath ($actorDrift|ConvertTo-Json -Depth 20)
    $actorDriftRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($actorDriftRun.Code-ne0-and$actorDriftRun.Text.Contains('CONFLICT_ACTOR_ROLE_PHASE')) 'process-discover-rejects-host-task-actor-drift'
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $unknownAction=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$unknownAction.intentEnvelope.requestedActionKind='UNKNOWN_ACTION';Write-Utf8 $discoverInputPath ($unknownAction|ConvertTo-Json -Depth 20)
    $unknownActionRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($unknownActionRun.Code-ne0-and$unknownActionRun.Text.Contains('ACTION_KIND')) 'process-discover-rejects-unknown-action-kind'
    $capabilityDrift=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$capabilityDrift.capabilities=@('KNOWLEDGE_REFERENCE');Write-Utf8 $discoverInputPath ($capabilityDrift|ConvertTo-Json -Depth 20)
    $capabilityDriftRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($capabilityDriftRun.Code-ne0-and$capabilityDriftRun.Text.Contains('PROJECT_CAPABILITY_DRIFT')) 'process-discover-rejects-caller-capability-drift'
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)

    $v2AuthorizationPath=Join-Path $temp 'process-v2-authorization.json'
    $v2Authorization=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='PROCESS-FIXTURE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='IMPLEMENT_LOCAL';decisionClass='PRODUCT_RESULT';userConfirmation='USER_FIXTURE_SOURCE_APPROVED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Get-Identity $processTaskPath);actions=@('SOURCE_WRITE');exactPaths=@('src/public.txt');objectIdentities=@([ordered]@{path='src/public.txt';identity='NEW'});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Get-Identity $correctionConfigPath)}
    Write-Utf8 $v2AuthorizationPath ($v2Authorization|ConvertTo-Json -Depth 20)
    $v2Intent=(New-CurrentFixtureIntent ([ordered]@{schemaVersion=1;objective='Implement the bounded source change';requestedActionKind='SOURCE_WRITE';requestedResultKind='USER_RESPONSE';semanticHints=@('implementation');pathHints=@('src/public.txt');capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'}))
    $discoverV2=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$correctionRoot;frameworkRoot=$correctionFrameworkRoot;taskPath=$processTaskPath;expectedProjectConfigIdentity=(Get-Identity $correctionConfigPath);expectedCorrectionsIdentity=(Get-Identity $correctionPath);expectedTaskIdentity=(Get-Identity $processTaskPath);observedActor='owner-fixture';capabilities=@();exactPaths=@('src/public.txt');forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$v2AuthorizationPath;expectedAuthorizationIdentity=(Get-Identity $v2AuthorizationPath);userDecision='USER_FIXTURE_SOURCE_APPROVED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$v2Intent;evaluationOnly=$false}
    Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    $discoverV2Run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$discoverV2Result=$discoverV2Run.Output[-1]|ConvertFrom-Json;$discoverV2Value=$discoverV2Result.compactReceipt;$discoverV2Blocks=@($discoverV2Result.selectedRuleBlocks)
    if($discoverV2Run.Code-ne0){Write-Output ('DIAG|process-v2-discover|code='+$discoverV2Run.Code+'|'+$discoverV2Run.Text)}
    Assert-True ($discoverV2Run.Code-eq0-and[int]$discoverV2Value.inputContractVersion-eq4-and[string]$discoverV2Value.binding.authorizationIdentity-ceq(Get-Identity $v2AuthorizationPath)-and@($discoverV2Value.binding.authorizedActions)-contains'SOURCE_WRITE'-and[string]$discoverV2Value.binding.repositoryGitTop-cne'UNPROVEN'-and[string]$discoverV2Value.evidence.invocationState-ceq'PROVEN_EXPLICIT'-and[int]$discoverV2Value.pack.ceilingBytes-eq0-and-not(@($discoverV2Value.evidence.ceilings)-contains'INVOCATION_UNPROVEN')) 'process-v2-discover-binds-authority-intent-package-and-project-budget'
    Write-CurrentFixtureObject PROCESS_POLICY $policyPath $defaultPolicy
    Write-CurrentFixtureObject PROJECT_CORRECTIONS $correctionPath $largeLegacyCorrections;$largeAmbiguousInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$largeAmbiguousInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;$largeAmbiguousInput.intentEnvelope.ambiguityState='UNKNOWN';Write-Utf8 $discoverInputPath ($largeAmbiguousInput|ConvertTo-Json -Depth 30)
    $largeAmbiguousRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($largeAmbiguousRun.Code-eq0-and@((($largeAmbiguousRun.Stdout|ConvertFrom-Json -Depth 100).selectedRuleBlocks)|Where-Object{[string]::Equals($_.fullText,$largeLegacyRule,[StringComparison]::Ordinal)}).Count-eq1) 'unknown-intent-preserves-complete-conservative-content-without-byte-quota'
    Write-Utf8 $correctionPath $correctionOriginal;Write-CurrentFixtureObject PROCESS_POLICY $policyPath $routineFixturePolicy;$discoverV2.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    foreach($intentMismatchCase in @(
        [pscustomobject]@{Name='path';Mutate={param($v)$v.intentEnvelope.pathHints=@('outside/')};Reason='PATH_HINT_OUTSIDE_EXACT_SCOPE'},
        [pscustomobject]@{Name='capability';Mutate={param($v)$v.intentEnvelope.capabilityHints=@('UNOBSERVED_CAPABILITY')};Reason='CAPABILITY_HINT_UNOBSERVED'},
        [pscustomobject]@{Name='mutation';Mutate={param($v)$v.intentEnvelope.mutationHints=@('test')};Reason='MUTATION_HINT_ACTION_MISMATCH'},
        [pscustomobject]@{Name='external';Mutate={param($v)$v.intentEnvelope.externalHints=@('provider')};Reason='EXTERNAL_HINT_ACTION_MISMATCH'}
    )){
        $mismatchInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;& $intentMismatchCase.Mutate $mismatchInput;Write-Utf8 $discoverInputPath ($mismatchInput|ConvertTo-Json -Depth 30)
        $mismatchRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($mismatchRun.Code-ne0-and$mismatchRun.Text.Contains('INTENT_FACT_MISMATCH')-and$mismatchRun.Text.Contains([string]$intentMismatchCase.Reason)) ('process-v2-clear-intent-reconciles-'+[string]$intentMismatchCase.Name+'-fact')
    }
    $semanticIdentityInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$semanticIdentityInput.intentEnvelope.semanticHints=@('implementation','identity-drift');Write-Utf8 $discoverInputPath ($semanticIdentityInput|ConvertTo-Json -Depth 30)
    $semanticIdentityRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$semanticIdentityResult=$semanticIdentityRun.Output[-1]|ConvertFrom-Json;$semanticIdentityValue=$semanticIdentityResult.compactReceipt
    Assert-True ($semanticIdentityRun.Code-eq0-and[string]$semanticIdentityValue.selectionIdentity-cne[string]$discoverV2Value.selectionIdentity-and[string]$semanticIdentityValue.contextIdentity-cne[string]$discoverV2Value.contextIdentity) 'process-v2-full-intent-envelope-binds-selection-and-context-identities'
    $unknownMismatchInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$unknownMismatchInput.intentEnvelope.ambiguityState='UNKNOWN';$unknownMismatchInput.intentEnvelope.mutationHints=@('test');Write-Utf8 $discoverInputPath ($unknownMismatchInput|ConvertTo-Json -Depth 30)
    $unknownMismatchRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');if($unknownMismatchRun.Code-ne0){throw ('ASSERT_FAIL|process-v2-unknown-intent-fact-mismatch-loads-conservatively|'+$unknownMismatchRun.Code+'|'+$unknownMismatchRun.Text)};$unknownMismatchResult=$unknownMismatchRun.Output[-1]|ConvertFrom-Json;$unknownMismatchValue=$unknownMismatchResult.compactReceipt
    Assert-True ($unknownMismatchRun.Code-eq0-and[int]$unknownMismatchValue.pack.ceilingBytes-eq0-and@($unknownMismatchValue.evidence.ceilings)-contains'INTENT_FACT_MISMATCH_CONSERVATIVE_LOAD') 'process-v2-unknown-intent-fact-mismatch-loads-conservatively'
    Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    $malformedAuthorization=$v2Authorization|ConvertTo-Json -Depth 30|ConvertFrom-Json;$malformedAuthorization.PSObject.Properties.Remove('taskIdentity');Write-Utf8 $v2AuthorizationPath ($malformedAuthorization|ConvertTo-Json -Depth 30)
    $malformedDiscover=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$malformedDiscover.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;Write-Utf8 $discoverInputPath ($malformedDiscover|ConvertTo-Json -Depth 30)
    $malformedAuthorizationRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($malformedAuthorizationRun.Code-ne0-and$malformedAuthorizationRun.Text.Contains('AUTHORIZATION_CHECK_FAILED')-and$malformedAuthorizationRun.Text.Contains('FIELD_MISSING_taskIdentity')) 'process-v2-discover-consumes-complete-authorization-package'
    Write-Utf8 $v2AuthorizationPath ($v2Authorization|ConvertTo-Json -Depth 30);$discoverV2.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    $discoverV2ReceiptPath=Join-Path $temp 'process-v2-discover-receipt.json';Write-Utf8 $discoverV2ReceiptPath ($discoverV2Value|ConvertTo-Json -Depth 40)
    $v2Prep=@($discoverV2Value.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $v2Result=@($discoverV2Value.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $v2Boundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$discoverV2ReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $discoverV2ReceiptPath);objective=$v2Intent.objective;actionKind=$v2Intent.requestedActionKind;resultKind=$v2Intent.requestedResultKind;exactPaths=@('src/public.txt');authorizationIdentity=(Get-Identity $v2AuthorizationPath);preparationReceipts=@($v2Prep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Utf8 $admitInputPath ($v2Boundary|ConvertTo-Json -Depth 30)
    $v2Admit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$v2AdmitValue=$v2Admit.Output[-1]|ConvertFrom-Json
    Assert-True ($v2Admit.Code-eq0-and$v2Admit.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) 'process-v2-admit-valid-package-and-preparation-pass'
    $projectRuntimeV2ReceiptPath=Join-Path $projectRuntimeDir 'v2-receipt.json';Write-Utf8 $projectRuntimeV2ReceiptPath ($discoverV2Value|ConvertTo-Json -Depth 40)
    $projectRuntimeV2Boundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$projectRuntimeV2Boundary.discoverReceiptPath=$projectRuntimeV2ReceiptPath;$projectRuntimeV2Boundary.expectedDiscoverReceiptIdentity=Get-Identity $projectRuntimeV2ReceiptPath
    $projectRuntimeV2AdmitPath=Join-Path $projectRuntimeDir 'admit.json';Write-Utf8 $projectRuntimeV2AdmitPath ($projectRuntimeV2Boundary|ConvertTo-Json -Depth 30)
    $projectRuntimeV2Admit=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeV2AdmitPath,'-AsJson','-DeleteInputOnExit');$projectRuntimeV2AdmitValue=$projectRuntimeV2Admit.Output[-1]|ConvertFrom-Json
    Assert-True ($projectRuntimeV2Admit.Code-eq0-and[string]$projectRuntimeV2AdmitValue.artifactStorage-ceq'PROJECT_RUNTIME'-and-not(Test-Path -LiteralPath $projectRuntimeV2AdmitPath)) 'process-project-runtime-admit-derives-binding-from-exact-receipt-and-cleans'
    $projectRuntimeV2DriftPath=Join-Path $projectRuntimeDir 'admit-receipt-drift.json';$projectRuntimeV2Drift=$projectRuntimeV2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$projectRuntimeV2Drift.expectedDiscoverReceiptIdentity='0|'+('0'*64);Write-Utf8 $projectRuntimeV2DriftPath ($projectRuntimeV2Drift|ConvertTo-Json -Depth 30)
    $projectRuntimeV2DriftRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeV2DriftPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($projectRuntimeV2DriftRun.Code-ne0-and$projectRuntimeV2DriftRun.Text.Contains('DISCOVER_RECEIPT_DRIFT')-and(Test-Path -LiteralPath $projectRuntimeV2DriftPath)) 'process-project-runtime-boundary-retains-input-on-receipt-identity-drift'
    Remove-Item -LiteralPath $projectRuntimeV2DriftPath -Force
    $v2ObjectPath=Join-Path $correctionRoot 'src\public.txt';Write-Utf8 $v2ObjectPath "post-discover drift`n"
    $v2ObjectDriftAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($v2ObjectDriftAdmit.Code-ne0-and$v2ObjectDriftAdmit.Text.Contains('AUTHORIZATION_CHECK_FAILED')-and$v2ObjectDriftAdmit.Text.Contains('NEW_OBJECT_EXISTS')) 'process-v2-admit-revalidates-exact-object-bytes'
    $v2PostimageIdentity=Get-Identity $v2ObjectPath
    $v2Finalize=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$v2Finalize.mode='FINALIZE_OUTPUT';$v2Finalize.resultReceipts=@($v2Result+@('OBJECT_POSTIMAGE|src/public.txt|'+$v2PostimageIdentity));$v2Finalize.deliveryReceipts=@('DIRECT_USER_DELIVERY');Write-Utf8 $admitInputPath ($v2Finalize|ConvertTo-Json -Depth 30)
    $v2FinalizePass=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    if($v2FinalizePass.Code-ne0){Write-Output ('DIAG|process-v2-finalize-pass|code='+$v2FinalizePass.Code+'|'+$v2FinalizePass.Text)}
    Assert-True ($v2FinalizePass.Code-eq0-and$v2FinalizePass.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) 'process-v2-finalize-validates-exact-postimage-receipt'
    $projectRuntimeV2Finalize=$v2Finalize|ConvertTo-Json -Depth 30|ConvertFrom-Json;$projectRuntimeV2Finalize.discoverReceiptPath=$projectRuntimeV2ReceiptPath;$projectRuntimeV2Finalize.expectedDiscoverReceiptIdentity=Get-Identity $projectRuntimeV2ReceiptPath
    $projectRuntimeV2FinalizePath=Join-Path $projectRuntimeDir 'finalize.json';Write-Utf8 $projectRuntimeV2FinalizePath ($projectRuntimeV2Finalize|ConvertTo-Json -Depth 30)
    $projectRuntimeV2FinalizeRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeV2FinalizePath,'-AsJson','-DeleteInputOnExit');$projectRuntimeV2FinalizeValue=$projectRuntimeV2FinalizeRun.Output[-1]|ConvertFrom-Json
    Assert-True ($projectRuntimeV2FinalizeRun.Code-eq0-and[string]$projectRuntimeV2FinalizeValue.artifactStorage-ceq'PROJECT_RUNTIME'-and-not(Test-Path -LiteralPath $projectRuntimeV2FinalizePath)) 'process-project-runtime-finalize-derives-binding-from-exact-receipt-and-cleans'
    $unrelatedBoundaryPath=Join-Path $unrelatedRuntimeDir 'boundary.json';Write-Utf8 $unrelatedBoundaryPath ($projectRuntimeV2Boundary|ConvertTo-Json -Depth 30)
    $unrelatedBoundaryRun=Invoke-Ps $processResolver @('-InputPath',$unrelatedBoundaryPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($unrelatedBoundaryRun.Code-ne0-and$unrelatedBoundaryRun.Text.Contains('INPUT_RUNTIME_PROJECT_ROOT_DRIFT')-and(Test-Path -LiteralPath $unrelatedBoundaryPath)) 'process-unrelated-project-runtime-boundary-fails-closed-and-retains'
    Remove-Item -LiteralPath $unrelatedBoundaryPath,$projectRuntimeV2ReceiptPath -Force
    Write-Utf8 $v2ObjectPath "postimage drift`n"
    $v2FinalizeDrift=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($v2FinalizeDrift.Code-ne0-and$v2FinalizeDrift.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED|src/public.txt')) 'process-v2-finalize-rejects-stale-postimage-receipt'
    Remove-Item -LiteralPath $v2ObjectPath -Force
    Write-Utf8 $admitInputPath ($v2Boundary|ConvertTo-Json -Depth 30)
    $controllerOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionControllerPath;$controllerDrift=$controllerOriginal|ConvertFrom-Json;$controllerDrift.controllerEpoch=2;Write-Utf8 $correctionControllerPath ($controllerDrift|ConvertTo-Json -Depth 10)
    $controllerDriftRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($controllerDriftRun.Code-ne0-and$controllerDriftRun.Text.Contains('DISCOVER_SOURCE_DRIFT|controllerIdentity')) 'process-boundary-rejects-controller-epoch-drift'
    [IO.File]::WriteAllText($correctionControllerPath,$controllerOriginal,[Text.UTF8Encoding]::new($false))
    $spoofedV2Boundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$spoofedV2Boundary.authorizationIdentity='100|'+('B'*64);Write-Utf8 $admitInputPath ($spoofedV2Boundary|ConvertTo-Json -Depth 30)
    $spoofedV2Run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($spoofedV2Run.Code-ne0-and$spoofedV2Run.Text.Contains('AUTHORIZATION_CONTEXT_DRIFT')) 'process-v2-boundary-rejects-unbound-authorization-identity'
    $v2AuthorizationOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $v2AuthorizationPath;Write-Utf8 $v2AuthorizationPath ($v2AuthorizationOriginal.TrimEnd("`n")+" `n")
    Write-Utf8 $admitInputPath ($v2Boundary|ConvertTo-Json -Depth 30)
    $driftedV2Authorization=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($driftedV2Authorization.Code-ne0-and$driftedV2Authorization.Text.Contains('DISCOVER_SOURCE_DRIFT|authorizationIdentity')) 'process-v2-boundary-revalidates-authorization-package-identity'
    [IO.File]::WriteAllText($v2AuthorizationPath,$v2AuthorizationOriginal,[Text.UTF8Encoding]::new($false))
    $clearNoMatchV2=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$clearNoMatchV2.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;$clearNoMatchV2.intentEnvelope.objective='Observe bounded quasar state';$clearNoMatchV2.intentEnvelope.semanticHints=@('quasar');Write-Utf8 $discoverInputPath ($clearNoMatchV2|ConvertTo-Json -Depth 30)
    $clearNoMatchDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$clearNoMatchResult=$clearNoMatchDiscover.Output[-1]|ConvertFrom-Json;$clearNoMatchValue=$clearNoMatchResult.compactReceipt;$clearNoMatchBlocks=@($clearNoMatchResult.selectedRuleBlocks)
    $ambiguousV2=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$ambiguousV2.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;$ambiguousV2.intentEnvelope.ambiguityState='UNKNOWN';Write-Utf8 $discoverInputPath ($ambiguousV2|ConvertTo-Json -Depth 30)
    $ambiguousDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$ambiguousResult=$ambiguousDiscover.Output[-1]|ConvertFrom-Json;$ambiguousValue=$ambiguousResult.compactReceipt;$ambiguousBlocks=@($ambiguousResult.selectedRuleBlocks)
    Assert-True ($clearNoMatchDiscover.Code-eq0-and-not(@($clearNoMatchValue.evidence.ceilings)-contains'INTENT_AMBIGUITY_CONSERVATIVE_LOAD')-and@($clearNoMatchBlocks).Count-eq@($ambiguousBlocks).Count) 'process-current-description-words-do-not-override-same-authority-and-unknown-facets'
    Assert-True ($ambiguousDiscover.Code-eq0-and@($ambiguousValue.evidence.ceilings)-contains'INTENT_AMBIGUITY_CONSERVATIVE_LOAD') 'process-v2-ambiguous-intent-loads-conservatively'
    $ambiguousReceipt=Join-Path $temp 'process-v2-ambiguous-receipt.json';Write-Utf8 $ambiguousReceipt ($ambiguousValue|ConvertTo-Json -Depth 40)
    $ambiguousBoundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$ambiguousBoundary.discoverReceiptPath=$ambiguousReceipt;$ambiguousBoundary.expectedDiscoverReceiptIdentity=Get-Identity $ambiguousReceipt;Write-Utf8 $admitInputPath ($ambiguousBoundary|ConvertTo-Json -Depth 30)
    $ambiguousAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$ambiguousAdmitValue=$ambiguousAdmit.Output[-1]|ConvertFrom-Json
    Assert-True ($ambiguousAdmit.Code-eq3-and$ambiguousAdmit.Text.Contains('INTENT_AMBIGUOUS')-and[string]$ambiguousAdmitValue.decisionIdentity-cne[string]$v2AdmitValue.decisionIdentity) 'process-v2-ambiguous-intent-blocks-governed-action-and-binds-decision-context'
    $oversizedIntent=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$oversizedIntent.intentEnvelope.semanticHints=@(1..65|ForEach-Object{'hint-'+$_});Write-Utf8 $discoverInputPath ($oversizedIntent|ConvertTo-Json -Depth 30)
    $oversizedIntentRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($oversizedIntentRun.Code-ne0-and$oversizedIntentRun.Text.Contains('INPUT_ARRAY_COUNT|intent_semanticHints')) 'process-v2-intent-schema-item-ceiling-enforced-at-runtime'
    # Authority scope has no global item quota. Bind a real finite scope to
    # its task, package and path hint so this case reaches the original gate.
    $largeScopeTaskBefore=[IO.File]::ReadAllBytes($processTaskPath)
    try{
        $largeScopePaths=@(1..257|ForEach-Object{'src/file-'+$_.ToString()+'.txt'})
        $largeScopeTask=[Text.Encoding]::UTF8.GetString($largeScopeTaskBefore).Replace('expected_paths=[src/public.txt]',('expected_paths=['+($largeScopePaths-join'|')+']'))
        Write-Utf8 $processTaskPath $largeScopeTask
        $largeScopePackage=$v2Authorization|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $largeScopePackage.taskIdentity=Get-Identity $processTaskPath;$largeScopePackage.exactPaths=$largeScopePaths
        $largeScopePackage.objectIdentities=@($largeScopePaths|ForEach-Object{[pscustomobject]@{path=$_;identity='NEW'}})
        $largeScopePackagePath=Join-Path $temp 'process-v2-large-scope-authorization.json';Write-Utf8 $largeScopePackagePath ($largeScopePackage|ConvertTo-Json -Depth 30)
        $largeScope=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $largeScope.exactPaths=$largeScopePaths;$largeScope.intentEnvelope.pathHints=@('src/')
        $largeScope.expectedTaskIdentity=$largeScopePackage.taskIdentity;$largeScope.authorizationPackagePath=$largeScopePackagePath;$largeScope.expectedAuthorizationIdentity=Get-Identity $largeScopePackagePath
        Write-Utf8 $discoverInputPath ($largeScope|ConvertTo-Json -Depth 30)
        $largeScopeRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        if($largeScopeRun.Code-ne0){throw ('ASSERT_FAIL|process-v2-large-authority-scope-discover|'+$largeScopeRun.Text)}
        $largeScopeValue=($largeScopeRun.Stdout|ConvertFrom-Json -Depth 100).compactReceipt
        Assert-True ($largeScopeValue.status-ceq'PASS'-and$largeScopeValue.binding.exactScope.Count-eq257-and($largeScopeValue.binding.exactScope-join'|')-ceq($largeScopePaths-join'|')-and$largeScopeValue.binding.taskIdentity-ceq$largeScopePackage.taskIdentity-and$largeScopeValue.binding.authorizationIdentity-ceq(Get-Identity $largeScopePackagePath)-and'SOURCE_WRITE'-cin$largeScopeValue.binding.authorizedActions) 'process-v2-authority-scope-over-old256-binds-complete-current-package'
        $largeScopeReceiptPath=Join-Path $temp 'process-v2-large-scope-receipt.json';Write-Utf8 $largeScopeReceiptPath ($largeScopeValue|ConvertTo-Json -Depth 40)
        $largeScopeBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$largeScopeReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $largeScopeReceiptPath;preparationReceipts=@($largeScopeValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();evidenceRefs=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
        $largeScopeAdmitPath=Join-Path $temp 'process-v2-large-scope-admit.json';Write-Utf8 $largeScopeAdmitPath ($largeScopeBoundary|ConvertTo-Json -Depth 40)
        $largeScopeAdmit=Invoke-Ps $processResolver @('-InputPath',$largeScopeAdmitPath,'-AsJson');$largeScopeAdmitted=$largeScopeAdmit.Stdout|ConvertFrom-Json -Depth 100
        Assert-True ($largeScopeAdmit.Code-eq0-and$largeScopeAdmitted.status-ceq'PASS'-and$largeScopeAdmitted.reason-ceq'STRUCTURAL_REQUIREMENTS_COMPLETE'-and$largeScopeAdmitted.missingPreparation.Count-eq0-and$largeScopeAdmitted.missingResult.Count-eq0) 'process-v2-authority-scope-over-old256-admitted-by-original-checker'
    }finally{[IO.File]::WriteAllBytes($processTaskPath,$largeScopeTaskBefore)}
    $noAuthV2=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$noAuthV2.authorizationPackagePath='NOT_REQUIRED';$noAuthV2.expectedAuthorizationIdentity='NOT_REQUIRED';$noAuthV2.userDecision='NOT_REQUIRED';Write-Utf8 $discoverInputPath ($noAuthV2|ConvertTo-Json -Depth 30)
    $noAuthDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$noAuthResult=$noAuthDiscover.Output[-1]|ConvertFrom-Json;$noAuthValue=$noAuthResult.compactReceipt
    $noAuthReceipt=Join-Path $temp 'process-v2-no-auth-receipt.json';Write-Utf8 $noAuthReceipt ($noAuthValue|ConvertTo-Json -Depth 40)
    $noAuthBoundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$noAuthBoundary.discoverReceiptPath=$noAuthReceipt;$noAuthBoundary.expectedDiscoverReceiptIdentity=Get-Identity $noAuthReceipt;$noAuthBoundary.authorizationIdentity='NOT_REQUIRED';Write-Utf8 $admitInputPath ($noAuthBoundary|ConvertTo-Json -Depth 30)
    $noAuthAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($noAuthDiscover.Code-eq0-and$noAuthAdmit.Code-eq3-and$noAuthAdmit.Text.Contains('ACTION_NOT_AUTHORIZED_IN_CONTEXT')) 'process-v2-categorical-action-without-package-blocked'

    # Exact three-source review replay; source fixtures are restored before later tests.
    $selectorTaskBefore=Get-Content -Raw -LiteralPath $processTaskPath
    $selectorPolicyBefore=Get-Content -Raw -LiteralPath $policyPath
    $selectorCorrectionsBefore=Get-Content -Raw -LiteralPath $correctionPath
    $selectorObject=Join-Path $correctionRoot 'src/public.txt'
    $selectorPackagePath=Join-Path $correctionRoot '.ai-workspace/selector-review-authorization.json'
    $selectorReceiptPath=Join-Path $temp 'selector-review-receipt.json'
    try{
        Write-Utf8 $processTaskPath ($selectorTaskBefore.Replace('profile=STANDARD','profile=CRITICAL'))
        Write-Utf8 $selectorObject "Frozen selection review fixture."
        $selectorObjectIdentity=Get-Identity $selectorObject
        $selectorNew=[ordered]@{profiles=@('CRITICAL');roles=@('REVIEWER');phases=@('REVIEW');actionKinds=@('REVIEW_EXECUTE');resultKinds=@('*');pathPrefixes=@('src/');capabilities=@();semanticTerms=@('unmentioned-term');deterministicTriggers=[ordered]@{actionKinds=@('REVIEW_EXECUTE');resultKinds=@()};semanticMatch='TOKEN'}
        $selectorLegacy=$selectorNew|ConvertTo-Json -Depth 20|ConvertFrom-Json;$selectorLegacy.PSObject.Properties.Remove('deterministicTriggers');$selectorLegacy.PSObject.Properties.Remove('semanticMatch')
        $selectorRecord=[ordered]@{correctionId='SELECTOR_REQUIRED_REVIEW';introducedAgainstFramework='2.0.0';requirementReason='Formal review must bind the correction preparation.';effectiveRule='Require correction preparation and result.';applicability='Explicit independent review';decisionLocator='test:selector-correction';selectors=$selectorNew;preparationRequirements=@('CORRECTION_REVIEW_PREPARED');resultRequirements=@('CORRECTION_REVIEW_RESULT');requiredFacts=@();mechanicalCheckRefs=@('REVIEWER_INDEPENDENCE_PROVEN')}
        $selectorOldRecord=$selectorRecord|ConvertTo-Json -Depth 30|ConvertFrom-Json;$selectorOldRecord.correctionId='SELECTOR_LEGACY_CONTENT';$selectorOldRecord.effectiveRule='Legacy text matching remains unchanged.';$selectorOldRecord.selectors=$selectorLegacy;$selectorOldRecord.preparationRequirements=@('LEGACY_CONTENT_PREP');$selectorOldRecord.resultRequirements=@()
        $selectorCorrections=[ordered]@{schemaVersion=2;contractVersion='2.0.0';projectId='correction-fixture';corrections=@($selectorRecord,$selectorOldRecord)}
        Write-CurrentFixtureObject PROJECT_CORRECTIONS $correctionPath $selectorCorrections
        $selectorPolicy=$selectorPolicyBefore|ConvertFrom-Json;$selectorPolicy.rules=@([pscustomobject]@{ruleId='SELECTOR_POLICY_REVIEW';requirementReason='Formal review must bind permanent policy preparation.';effectiveRule='Require policy preparation and result.';selectors=$selectorNew;preparationRequirements=@('POLICY_REVIEW_PREPARED');resultRequirements=@('POLICY_REVIEW_RESULT');decisionLocator='test:selector-policy'})
        Write-CurrentFixtureObject PROCESS_POLICY $policyPath $selectorPolicy
        $selectorCanonical=Get-AiwCanonicalCorrectionRecordIdentityV2 ($selectorRecord|ConvertTo-Json -Depth 30|ConvertFrom-Json)
        $selectorCanonicalLegacy=$selectorRecord|ConvertTo-Json -Depth 30|ConvertFrom-Json;$selectorCanonicalLegacy.selectors=$selectorLegacy
        Assert-True ($selectorCanonical-cne(Get-AiwCanonicalCorrectionRecordIdentityV2 $selectorCanonicalLegacy)) 'selector-optional-fields-change-correction-canonical'
        $selectorPackage=$v2Authorization|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $selectorPackage.profile='CRITICAL';$selectorPackage.grantee='independent-reviewer-fixture';$selectorPackage.actions=@('REVIEW_EXECUTE');$selectorPackage.reviewIndependence='INDEPENDENT';$selectorPackage.taskIdentity=Get-Identity $processTaskPath
        $selectorPackage.objectIdentities=@([pscustomobject]@{path='src/public.txt';identity=$selectorObjectIdentity})
        $selectorPackage|Add-Member candidateWriter 'owner-fixture';$selectorPackage|Add-Member materialContributors @()
        $selectorPackage.invalidatesOn=@($selectorPackage.invalidatesOn)+@('CONTRIBUTOR_SET_CHANGE')
        Write-Utf8 $selectorPackagePath ($selectorPackage|ConvertTo-Json -Depth 30)
        $selectorInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $selectorInput.observedActor='independent-reviewer-fixture';$selectorInput.expectedTaskIdentity=$selectorPackage.taskIdentity;$selectorInput.expectedCorrectionsIdentity=Get-Identity $correctionPath
        $selectorInput.authorizationPackagePath=$selectorPackagePath;$selectorInput.expectedAuthorizationIdentity=Get-Identity $selectorPackagePath
        $selectorInput.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$selectorInput.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$selectorInput.intentEnvelope.semanticHints=@();$selectorInput.intentEnvelope.mutationHints=@()
        foreach($text in @('检查候选并给出结论','Review the candidate','Assess unchanged material','Do not implement; examine candidate')){
            $selectorInput.intentEnvelope.objective=$text
            Write-Utf8 $discoverInputPath ($selectorInput|ConvertTo-Json -Depth 30)
            $selectorRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
            if($selectorRun.Code-ne0){throw ('ASSERT_FAIL|selector-review-discover|'+$selectorRun.Text)}
            $selectorValue=($selectorRun.Output[-1]|ConvertFrom-Json).compactReceipt
            $selectorPrep=@($selectorValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
            $selectorResults=@($selectorValue.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
            Assert-True (@('REVIEWER_INDEPENDENCE_PROVEN','CORRECTION_REVIEW_PREPARED','POLICY_REVIEW_PREPARED'|Where-Object{$_-cnotin$selectorPrep}).Count-eq0-and'LEGACY_CONTENT_PREP'-cin$selectorPrep) ('selector-three-source-obligations-'+$text)
            Assert-True ($selectorValue.binding.taskActor-ceq'owner-fixture'-and$selectorValue.binding.actor-ceq'independent-reviewer-fixture'-and$selectorValue.binding.role-ceq'REVIEWER'-and$selectorValue.binding.phase-ceq'REVIEW') ('selector-intent-keeps-actor-authority-'+$text)
        }
        Write-Utf8 $selectorReceiptPath ($selectorValue|ConvertTo-Json -Depth 40)
        $selectorBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$selectorReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $selectorReceiptPath;preparationReceipts=@($selectorPrep);resultReceipts=@();deliveryReceipts=@();evidenceRefs=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
        foreach($missing in @('CORRECTION_REVIEW_PREPARED','POLICY_REVIEW_PREPARED','REVIEW_CARRIER_QUALIFIED','REVIEW_MATERIALS_BOUND')){
            $negative=$selectorBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$negative.preparationReceipts=@($selectorPrep|Where-Object{$_-cne$missing})
            Write-Utf8 $admitInputPath ($negative|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
            $observed=$run.Text|ConvertFrom-Json
            Assert-True ($run.Code-eq3-and$observed.status-ceq'BLOCKED'-and$observed.reason-ceq'PREPARATION_INCOMPLETE'-and@($observed.missingPreparation).Count-eq1-and$observed.missingPreparation[0]-ceq$missing-and@($observed.missingResult).Count-eq0) ('selector-admit-missing-'+$missing)
        }
        Write-Utf8 $admitInputPath ($selectorBoundary|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        $observed=$run.Text|ConvertFrom-Json
        Assert-True ($run.Code-eq0-and$observed.status-ceq'PASS'-and@($observed.missingPreparation).Count-eq0) 'selector-review-complete-preparation-admitted'
        # Isolated protocol records and mocked host output exercise the typed
        # boundary; they do not represent a real Reviewer or message delivery.
        $selectorRequirementsPath=Join-Path $correctionRoot 'selector-requirements.md'
        Write-Utf8 $selectorRequirementsPath 'Protocol fixture: independently inspect the unchanged candidate and return a verdict to its Owner.'
        $selectorRequirements=[ordered]@{path=$selectorRequirementsPath;identity=Get-Identity $selectorRequirementsPath}
        $selectorEvidencePath=Join-Path $correctionRoot 'selector-review-evidence.json'
        $selectorEvidence=[ordered]@{schemaVersion=1;taskId=$selectorPackage.taskId;actor=$selectorPackage.grantee;candidateObjects=$selectorPackage.objectIdentities;requirementsRef=$selectorRequirements;outcome='APPROVED';checks=@([ordered]@{id='selector-review';method='MODEL_JUDGMENT';outcome='PASS';reason='Anonymous protocol fixture only; no real project review is claimed.';evidenceLocators=@($selectorRequirements)});evidenceLocators=@($selectorRequirements);authorizationRef=[ordered]@{path=$selectorPackagePath;identity=Get-Identity $selectorPackagePath}}
        Write-Utf8 $selectorEvidencePath ($selectorEvidence|ConvertTo-Json -Depth 30)
        $selectorHostPath=Join-Path $correctionRoot 'selector-mock-host.json'
        Write-Utf8 $selectorHostPath ([ordered]@{isError=$false;content=@([ordered]@{type='text';text='{"threadId":"owner-fixture"}'})}|ConvertTo-Json -Depth 10)
        $selectorBoundary.mode='FINALIZE_OUTPUT';$selectorBoundary.resultReceipts=@($selectorResults)+@('OBJECT_POSTIMAGE|src/public.txt|'+$selectorObjectIdentity)
        $selectorBoundary.evidenceRefs=@([ordered]@{kind='REVIEW_VERDICT';path=$selectorEvidencePath;identity=Get-Identity $selectorEvidencePath})
        $selectorBoundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient='owner-fixture';observedRecipient='owner-fixture';outcome='SUCCESS';evidence=($selectorHostPath+'#'+(Get-Identity $selectorHostPath))}
        $selectorMissingTyped=$selectorBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$selectorMissingTyped.evidenceRefs=@()
        Write-Utf8 $admitInputPath ($selectorMissingTyped|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($run.Code-ne0-and$run.Text.Contains('TYPED_EVIDENCE_REQUIRED')) 'selector-finalize-obligation-strings-cannot-replace-typed-review'
        foreach($missing in @('CORRECTION_REVIEW_RESULT','POLICY_REVIEW_RESULT')){
            $negative=$selectorBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$negative.resultReceipts=@($selectorBoundary.resultReceipts|Where-Object{$_-cne$missing})
            Write-Utf8 $admitInputPath ($negative|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
            if($run.Code-ne3-or-not$run.Text.Contains($missing)){Write-Output ('DIAG|selector-finalize|'+$run.Text)}
            $observed=$run.Text|ConvertFrom-Json
            Assert-True ($run.Code-eq3-and$observed.status-ceq'BLOCKED'-and$observed.reason-ceq'RESULT_INCOMPLETE'-and@($observed.missingPreparation).Count-eq0-and@($observed.missingResult).Count-eq1-and$observed.missingResult[0]-ceq$missing) ('selector-finalize-missing-'+$missing)
        }
        Write-Utf8 $admitInputPath ($selectorBoundary|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        if($run.Code-ne0){Write-Output ('DIAG|selector-complete|'+$run.Text)}
        $observed=$run.Text|ConvertFrom-Json
        Assert-True ($run.Code-eq0-and$observed.status-ceq'PASS'-and@($observed.missingPreparation).Count-eq0-and@($observed.missingResult).Count-eq0-and(Get-Identity $selectorObject)-ceq$selectorObjectIdentity) 'selector-finalize-complete-three-source-verdict'
        $selectorInput.intentEnvelope.mutationHints=@('source');Write-Utf8 $discoverInputPath ($selectorInput|ConvertTo-Json -Depth 30)
        $run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($run.Code-ne0-and$run.Text.Contains('INTENT_FACT_MISMATCH')) 'selector-action-trigger-cannot-mask-intent-conflict'
        $selectorInput.intentEnvelope.mutationHints=@();$selectorInput.intentEnvelope.ambiguityState='UNKNOWN'
        Write-Utf8 $discoverInputPath ($selectorInput|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($run.Code-eq0) 'selector-unknown-review-discovers-conservatively'
        $unknownReceipt=($run.Output[-1]|ConvertFrom-Json).compactReceipt;Write-Utf8 $selectorReceiptPath ($unknownReceipt|ConvertTo-Json -Depth 40)
        $selectorBoundary.mode='ADMIT_ACTION';$selectorBoundary.expectedDiscoverReceiptIdentity=Get-Identity $selectorReceiptPath
        Write-Utf8 $admitInputPath ($selectorBoundary|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($run.Code-eq3-and$run.Text.Contains('INTENT_AMBIGUOUS')) 'selector-unknown-trigger-does-not-admit-review'
        $selectorInput.intentEnvelope.ambiguityState='CLEAR';$selectorInput.authorizationPackagePath='NOT_REQUIRED';$selectorInput.expectedAuthorizationIdentity='NOT_REQUIRED';$selectorInput.userDecision='NOT_REQUIRED'
        Write-Utf8 $discoverInputPath ($selectorInput|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($run.Code-ne0-and$run.Text.Contains('CONFLICT_ACTOR_ROLE_PHASE')) 'selector-trigger-cannot-create-temporary-reviewer-without-package'
    }finally{
        Write-Utf8 $processTaskPath $selectorTaskBefore
        Write-Utf8 $policyPath $selectorPolicyBefore
        Write-Utf8 $correctionPath $selectorCorrectionsBefore
        if(Test-Path -LiteralPath $selectorObject){Remove-Item -LiteralPath $selectorObject -Force}
    }

# 接受动作复用真实包与当前 Owner，不把无包、写入或结果标签当作接受权限。
    $ownerTaskOriginal=Get-Content -LiteralPath $processTaskPath -Raw -Encoding utf8
    $ownerAcceptedPath=Join-Path $correctionRoot 'src/owner-accepted.txt'
    Write-Utf8 $ownerAcceptedPath "Frozen reviewed result."
    $ownerAcceptedIdentity=Get-Identity $ownerAcceptedPath
    $ownerPackagePath=Join-Path $correctionRoot '.ai-workspace/owner-accept-authorization.json'
    $ownerReceiptPath=Join-Path $temp 'owner-accept-receipt.json'
    $ownerRequirementsPath=Join-Path $correctionRoot 'owner-accept-requirements.md'
    Write-Utf8 $ownerRequirementsPath 'Protocol fixture: accept the unchanged result after its bound self-check.'
    $ownerRequirements=[ordered]@{path=$ownerRequirementsPath;identity=Get-Identity $ownerRequirementsPath}
    $ownerSelfPath=Join-Path $correctionRoot 'owner-accept-self-check.json'
    $ownerSelf=[ordered]@{schemaVersion=1;taskId=$v2Authorization.taskId;actor='owner-fixture';candidateObjects=@([ordered]@{path='src/owner-accepted.txt';identity=$ownerAcceptedIdentity});requirementsRef=$ownerRequirements;outcome='PASS';checks=@([ordered]@{id='owner-accept';method='MODEL_JUDGMENT';outcome='PASS';reason='Anonymous protocol fixture only; no real product acceptance is claimed.';evidenceLocators=@($ownerRequirements)});evidenceLocators=@($ownerRequirements)}
    Write-Utf8 $ownerSelfPath ($ownerSelf|ConvertTo-Json -Depth 30)
    try {
        foreach($ownerPhase in @('VERIFY','IMPLEMENT','PLAN')){
            Write-Utf8 $processTaskPath ($ownerTaskOriginal.Replace('phase=IMPLEMENT','phase='+$ownerPhase))
            $ownerPackage=$v2Authorization|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerPackage.actions=@('RESULT_ACCEPT')
            $ownerPackage.taskIdentity=Get-Identity $processTaskPath
            $ownerPackage.exactPaths=@('src/owner-accepted.txt')
            $ownerPackage.objectIdentities=@([pscustomobject]@{path='src/owner-accepted.txt';identity=$ownerAcceptedIdentity})
            $ownerPackage|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=$ownerPackage.objectIdentities;requirementsRef=$ownerRequirements;prerequisiteEvidenceRefs=@([ordered]@{kind='SELF_CHECK';path=$ownerSelfPath;identity=Get-Identity $ownerSelfPath});reservedUserDecisionRefs=@()})
            Write-Utf8 $ownerPackagePath ($ownerPackage|ConvertTo-Json -Depth 30)
            $ownerDiscover=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerDiscover.expectedTaskIdentity=$ownerPackage.taskIdentity
            $ownerDiscover.exactPaths=@($ownerPackage.exactPaths)
            $ownerDiscover.authorizationPackagePath=$ownerPackagePath
            $ownerDiscover.expectedAuthorizationIdentity=Get-Identity $ownerPackagePath
            $ownerDiscover.intentEnvelope.objective='Accept the frozen reviewed result'
            $ownerDiscover.intentEnvelope.requestedActionKind='RESULT_ACCEPT'
            $ownerDiscover.intentEnvelope.requestedResultKind='RESULT_ACCEPTANCE'
            $ownerDiscover.intentEnvelope.semanticHints=@()
            $ownerDiscover.intentEnvelope.mutationHints=@()
            $ownerDiscover.intentEnvelope.pathHints=@($ownerPackage.exactPaths)
            Write-Utf8 $discoverInputPath ($ownerDiscover|ConvertTo-Json -Depth 30)
            $ownerRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
            if($ownerRun.Code-ne0){throw ('ASSERT_FAIL|owner-accept-discover-'+$ownerPhase+'|'+$ownerRun.Text)}
            $ownerValue=($ownerRun.Output[-1]|ConvertFrom-Json).compactReceipt
            Assert-True (@($ownerValue.selectedObligations.requirementId)-contains'framework:PR_RESULT_ACCEPT_SEPARATE') ('owner-accept-rule-selected-by-action-'+$ownerPhase)
            Write-Utf8 $ownerReceiptPath ($ownerValue|ConvertTo-Json -Depth 40)
            $ownerPrep=@($ownerValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
            $ownerResult=@($ownerValue.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
            $ownerBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$ownerReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $ownerReceiptPath);preparationReceipts=@($ownerPrep);resultReceipts=@();deliveryReceipts=@();evidenceRefs=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
            Write-Utf8 $admitInputPath ($ownerBoundary|ConvertTo-Json -Depth 30)
            $ownerAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
            if($ownerAdmit.Code-ne0){Write-Output ('DIAG|owner-admit|'+$ownerAdmit.Text)}
            Assert-True ($ownerAdmit.Code-eq0-and$ownerAdmit.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) ('owner-accept-current-owner-exact-package-admitted-'+$ownerPhase)
        }
        $ownerMissingEvidence=$ownerBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerMissingEvidence.preparationReceipts=@($ownerPrep|Where-Object{$_-cne'REVIEW_OR_DIRECT_EVIDENCE_BOUND'})
        Write-Utf8 $admitInputPath ($ownerMissingEvidence|ConvertTo-Json -Depth 30)
        $ownerMissingEvidenceRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($ownerMissingEvidenceRun.Code-eq3-and$ownerMissingEvidenceRun.Text.Contains('REVIEW_OR_DIRECT_EVIDENCE_BOUND')) 'owner-accept-missing-review-or-direct-evidence-blocked'

        $ownerBoundary.mode='FINALIZE_OUTPUT'
        $ownerBoundary.resultReceipts=@($ownerResult)+@('OBJECT_POSTIMAGE|src/owner-accepted.txt|'+$ownerAcceptedIdentity)
        $ownerBoundary.deliveryContext=[ordered]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
        $ownerAcceptedEvidence=$ownerSelf|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerAcceptedEvidence.outcome='ACCEPTED';$ownerAcceptedEvidence|Add-Member authorizationRef ([ordered]@{path=$ownerPackagePath;identity=Get-Identity $ownerPackagePath})
        $ownerAcceptedEvidencePath=Join-Path $correctionRoot 'owner-accept-result.json'
        Write-Utf8 $ownerAcceptedEvidencePath ($ownerAcceptedEvidence|ConvertTo-Json -Depth 30)
        $ownerBoundary.evidenceRefs=@([ordered]@{kind='RESULT_ACCEPTANCE';path=$ownerAcceptedEvidencePath;identity=Get-Identity $ownerAcceptedEvidencePath})
        $ownerMissingTyped=$ownerBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$ownerMissingTyped.evidenceRefs=@()
        Write-Utf8 $admitInputPath ($ownerMissingTyped|ConvertTo-Json -Depth 30);$run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($run.Code-ne0-and$run.Text.Contains('TYPED_EVIDENCE_REQUIRED')) 'owner-accept-obligation-strings-cannot-replace-typed-acceptance'
        Write-Utf8 $admitInputPath ($ownerBoundary|ConvertTo-Json -Depth 30)
        $ownerFinal=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        if($ownerFinal.Code-ne0){Write-Output ('DIAG|owner-finalize|'+$ownerFinal.Text)}
        Assert-True ($ownerFinal.Code-eq0-and$ownerFinal.Text.Contains('"authorityGranted":false')-and$ownerFinal.Text.Contains('"delivered":false')-and(Get-Identity $ownerAcceptedPath)-ceq$ownerAcceptedIdentity) 'owner-accept-finalize-exact-unchanged-result-without-write-authority'
        $ownerWithoutLabel=$ownerBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerWithoutLabel.resultReceipts=@($ownerBoundary.resultReceipts|Where-Object{$_-cne'RESULT_ACCEPT_RECORDED'})
        Write-Utf8 $admitInputPath ($ownerWithoutLabel|ConvertTo-Json -Depth 30)
        $ownerWithoutLabelRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($ownerWithoutLabelRun.Code-eq0) 'owner-accept-typed-record-satisfies-result-without-self-reported-label'

        $ownerNoAuth=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerNoAuth.authorizationPackagePath='NOT_REQUIRED';$ownerNoAuth.expectedAuthorizationIdentity='NOT_REQUIRED';$ownerNoAuth.userDecision='NOT_REQUIRED'
        Write-Utf8 $discoverInputPath ($ownerNoAuth|ConvertTo-Json -Depth 30)
        $ownerNoAuthRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($ownerNoAuthRun.Code-eq0) 'owner-accept-no-package-discover-is-not-admission'
        $ownerNoAuthValue=($ownerNoAuthRun.Output[-1]|ConvertFrom-Json).compactReceipt
        Write-Utf8 $ownerReceiptPath ($ownerNoAuthValue|ConvertTo-Json -Depth 40)
        $ownerNoAuthBoundary=$ownerBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerNoAuthBoundary.mode='ADMIT_ACTION';$ownerNoAuthBoundary.expectedDiscoverReceiptIdentity=Get-Identity $ownerReceiptPath;$ownerNoAuthBoundary.evidenceRefs=@()
        Write-Utf8 $admitInputPath ($ownerNoAuthBoundary|ConvertTo-Json -Depth 30)
        $ownerNoAuthAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($ownerNoAuthAdmit.Code-ne0-and$ownerNoAuthAdmit.Text.Contains('RESULT_ACCEPT_AUTHORIZATION_REQUIRED')) 'owner-accept-no-package-remains-blocked'

        foreach($ownerOtherAction in @('NONE','CONTROL_WRITE')){
            $ownerWrongKind=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerWrongKind.intentEnvelope.requestedActionKind=$ownerOtherAction
            Write-Utf8 $discoverInputPath ($ownerWrongKind|ConvertTo-Json -Depth 30)
            $ownerWrongKindRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
            Assert-True ($ownerWrongKindRun.Code-ne0-and$ownerWrongKindRun.Text.Contains('RESULT_ACCEPT_ACTION_REQUIRED')) ('owner-acceptance-result-cannot-bypass-with-'+$ownerOtherAction)
        }
        foreach($ownerOtherAction in @('SOURCE_WRITE','GIT_COMMIT','PUSH')){
            $ownerNoEscalation=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerNoEscalation.intentEnvelope.requestedActionKind=$ownerOtherAction
            $ownerNoEscalation.intentEnvelope.requestedResultKind='USER_RESPONSE'
            Write-Utf8 $discoverInputPath ($ownerNoEscalation|ConvertTo-Json -Depth 30)
            $ownerNoEscalationRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
            Assert-True ($ownerNoEscalationRun.Code-ne0-and$ownerNoEscalationRun.Text.Contains('ACTION_NOT_GRANTED')) ('owner-accept-package-does-not-grant-'+$ownerOtherAction)
        }
        Write-Utf8 $ownerAcceptedPath "Changed after review."
        Write-Utf8 $discoverInputPath ($ownerDiscover|ConvertTo-Json -Depth 30)
        $ownerObjectDrift=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($ownerObjectDrift.Code-ne0-and$ownerObjectDrift.Text.Contains('OBJECT_DRIFT')) 'owner-accept-rejects-reviewed-object-drift'
        Write-Utf8 $ownerAcceptedPath "Frozen reviewed result."

        Write-Utf8 $processTaskPath ($ownerTaskOriginal.Replace('actor=owner-fixture','actor=executor-fixture'))
        $ownerPackage.grantee='executor-fixture';$ownerPackage.taskIdentity=Get-Identity $processTaskPath
        $ownerPackage.PSObject.Properties.Remove('acceptanceBinding')
        Write-Utf8 $ownerPackagePath ($ownerPackage|ConvertTo-Json -Depth 30)
        $ownerNotOwner=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerNotOwner.observedActor='executor-fixture';$ownerNotOwner.expectedTaskIdentity=$ownerPackage.taskIdentity;$ownerNotOwner.expectedAuthorizationIdentity=Get-Identity $ownerPackagePath
        Write-Utf8 $discoverInputPath ($ownerNotOwner|ConvertTo-Json -Depth 30)
        $ownerNotOwnerRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($ownerNotOwnerRun.Code-ne0-and$ownerNotOwnerRun.Text.Contains('RESULT_ACCEPT_DELEGATION_REQUIRED')) 'owner-accept-rejects-nonowner-without-explicit-delegation'
    } finally {
        Write-Utf8 $processTaskPath $ownerTaskOriginal
        if(Test-Path -LiteralPath $ownerAcceptedPath){Remove-Item -LiteralPath $ownerAcceptedPath -Force}
    }
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)

    $processConfigOriginal=Get-Content -LiteralPath $correctionConfigPath -Raw -Encoding utf8
    $processBootstrapPath=Join-Path $correctionRoot '.ai-workspace\BOOTSTRAP.md';$processBootstrapOriginal=Get-Content -LiteralPath $processBootstrapPath -Raw -Encoding utf8
    $policy=[ordered]@{schemaVersion=1;contractVersion='2.0.0';projectId='correction-fixture';selectedRulePackBytes=98304;rules=@([ordered]@{ruleId='PROJECT_SOURCE_PREP';requirementReason='Project requires one source preparation receipt';effectiveRule='Bind the project source preparation receipt before source work.';selectors=[ordered]@{profiles=@('STANDARD');roles=@('TASK_OWNER');phases=@('IMPLEMENT');actionKinds=@('SOURCE_WRITE');resultKinds=@('*');pathPrefixes=@('src/');capabilities=@();semanticTerms=@()};preparationRequirements=@('PROJECT_SOURCE_PREPARED');resultRequirements=@('PROJECT_SOURCE_READBACK');decisionLocator='project:policy-fixture'})}
    Write-CurrentFixtureObject PROCESS_POLICY $policyPath $policy
    $schema4=$processConfigOriginal|ConvertFrom-Json;Write-Utf8 $correctionConfigPath ($schema4|ConvertTo-Json -Depth 30)
    $discoverInput.expectedProjectConfigIdentity=Get-Identity $correctionConfigPath
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`nA permanent legacy project rule remains active.`n<!-- PROJECT-CUSTOM:END -->`n"
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $doubleCarrier=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($doubleCarrier.Code-eq0-and$doubleCarrier.Text.Contains('A permanent legacy project rule remains active.')) 'process-distinct-policy-and-custom-obligations-coexist'
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`nBind the project source preparation receipt before source work.`n<!-- PROJECT-CUSTOM:END -->`n"
    $policyCustomDuplicate=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($policyCustomDuplicate.Code-ne0-and$policyCustomDuplicate.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'process-identical-policy-and-custom-obligations-reject-duplicate'
    $historicalChinese='此 legacy region 当前没有 permanent project process rule。structured rules 位于 `.ai-workspace/process-policy.json`。'
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`n$historicalChinese`n<!-- PROJECT-CUSTOM:END -->`n"
    $historicalPlaceholder=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$historicalPlaceholderResult=$historicalPlaceholder.Output[-1]|ConvertFrom-Json
    Assert-True ($historicalPlaceholder.Code-eq0-and@($historicalPlaceholderResult.selectedRuleBlocks.requirementId)-contains'project:correction-fixture:PROJECT_SOURCE_PREP'-and@($historicalPlaceholderResult.selectedRuleBlocks.requirementId)-notcontains'project-custom:correction-fixture'-and@($historicalPlaceholderResult.compactReceipt.evidence.ceilings)-notcontains'LEGACY_PROJECT_CUSTOM_FULL_LOAD') 'process-exact-historical-chinese-placeholder-with-policy-is-nonnormative'
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`n$historicalChinese`nA permanent appended rule is active.`n<!-- PROJECT-CUSTOM:END -->`n"
    $historicalAppended=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($historicalAppended.Code-eq0-and$historicalAppended.Text.Contains('A permanent appended rule is active.')) 'process-historical-placeholder-does-not-hide-distinct-appended-rule'
    Write-Utf8 $processBootstrapPath $processBootstrapOriginal
    $correctionPolicy=$policy|ConvertTo-Json -Depth 30|ConvertFrom-Json;$correctionPolicy.rules[0].effectiveRule='Retain and evaluate project correction records';Write-CurrentFixtureObject PROCESS_POLICY $policyPath $correctionPolicy
    $correctionPolicyDuplicate=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($correctionPolicyDuplicate.Code-ne0-and$correctionPolicyDuplicate.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'process-correction-policy-duplicate-effective-rule-rejected'
    $emptyPolicy=$policy|ConvertTo-Json -Depth 30|ConvertFrom-Json;$emptyPolicy.rules=@();Write-CurrentFixtureObject PROCESS_POLICY $policyPath $emptyPolicy
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`nRetain and evaluate project correction records`n<!-- PROJECT-CUSTOM:END -->`n"
    $correctionCustomDuplicate=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($correctionCustomDuplicate.Code-ne0-and$correctionCustomDuplicate.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'process-correction-custom-duplicate-effective-rule-rejected'
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`nA unique permanent legacy rule remains active.`n<!-- PROJECT-CUSTOM:END -->`n"
    $legacyOnly=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$legacyOnlyResult=$legacyOnly.Output[-1]|ConvertFrom-Json
    Assert-True ($legacyOnly.Code-eq0-and@($legacyOnlyResult.selectedRuleBlocks.requirementId)-contains'project-custom:correction-fixture'-and@($legacyOnlyResult.compactReceipt.evidence.ceilings)-contains'LEGACY_PROJECT_CUSTOM_FULL_LOAD') 'process-empty-structured-rule-array-is-not-a-second-carrier'
    Write-CurrentFixtureObject PROCESS_POLICY $policyPath $policy
    Write-Utf8 $processBootstrapPath $processBootstrapOriginal
    $policyDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$policyDiscoverResult=$policyDiscover.Output[-1]|ConvertFrom-Json;$policyDiscoverValue=$policyDiscoverResult.compactReceipt;$policyDiscoverBlocks=@($policyDiscoverResult.selectedRuleBlocks)
    if($policyDiscover.Code-ne0){Write-Output ('DIAG|process-policy-discover|code='+$policyDiscover.Code+'|'+$policyDiscover.Text)}
    Assert-True ($policyDiscover.Code-eq0-and@($policyDiscoverBlocks.requirementId)-contains'project:correction-fixture:PROJECT_SOURCE_PREP'-and@($policyDiscoverValue.evidence.ceilings)-notcontains'LEGACY_PROJECT_CUSTOM_FULL_LOAD') 'process-policy-structured-rule-selected-with-single-carrier'
    Write-Utf8 $correctionConfigPath $processConfigOriginal;Write-Utf8 $processBootstrapPath $processBootstrapOriginal
    $discoverInput.expectedProjectConfigIdentity=Get-Identity $correctionConfigPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)

    $v2SelectorSource=[ordered]@{profiles=@('STANDARD');roles=@('TASK_OWNER');phases=@('IMPLEMENT');actionKinds=@('SOURCE_WRITE');resultKinds=@('*');pathPrefixes=@('src/');capabilities=@();semanticTerms=@()}
    $v2SelectorExternal=[ordered]@{profiles=@('STANDARD');roles=@('TASK_OWNER');phases=@('EXTERNAL');actionKinds=@('EXTERNAL');resultKinds=@('EXTERNAL_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@()}
    $v2Corrections=[ordered]@{schemaVersion=2;contractVersion='2.0.0';projectId='correction-fixture';corrections=@(
        [ordered]@{correctionId='V2_SOURCE_ONLY';introducedAgainstFramework='1.13.0';requirementReason='Source work requires the project receipt.';effectiveRule='Bind the project source preparation and readback.';applicability='Bounded source changes';decisionLocator='test:v2-source';selectors=$v2SelectorSource;preparationRequirements=@('V2_SOURCE_PREPARED');resultRequirements=@('V2_SOURCE_READBACK');requiredFacts=@('TASK_SCOPE_CURRENT');mechanicalCheckRefs=@('ACTION_PACKAGE_VALID')},
        [ordered]@{correctionId='V2_EXTERNAL_ONLY';introducedAgainstFramework='1.13.0';requirementReason='External work needs a separate project boundary.';effectiveRule='Bind the external project boundary.';applicability='External domain work';decisionLocator='test:v2-external';selectors=$v2SelectorExternal;preparationRequirements=@('V2_EXTERNAL_PREPARED');resultRequirements=@('V2_EXTERNAL_READBACK');requiredFacts=@();mechanicalCheckRefs=@('EXTERNAL_BOUNDARY_AUTHORIZED')}
    )}
    Write-CurrentFixtureObject PROJECT_CORRECTIONS $correctionPath $v2Corrections;$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $v2CorrectionDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$v2CorrectionResult=$v2CorrectionDiscover.Output[-1]|ConvertFrom-Json;$v2CorrectionValue=$v2CorrectionResult.compactReceipt;$v2CorrectionBlocks=@($v2CorrectionResult.selectedRuleBlocks)
    Assert-True ($v2CorrectionDiscover.Code-eq0-and@($v2CorrectionBlocks.requirementId)-contains'correction:correction-fixture:V2_SOURCE_ONLY'-and@($v2CorrectionBlocks.requirementId)-notcontains'correction:correction-fixture:V2_EXTERNAL_ONLY'-and[int]$v2CorrectionValue.counts.legacyCorrectionsFullReadCount-eq0-and@($v2CorrectionValue.evidence.ceilings)-notcontains'LEGACY_CORRECTIONS_FULL_LOAD') 'corrections-v2-progressive-selection-without-legacy-full-load-claim'
    $v2RecordA=$v2Corrections.corrections[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json;$v2RecordB=$v2RecordA|ConvertTo-Json -Depth 30|ConvertFrom-Json;$v2RecordB.selectors.semanticTerms=@('changed')
    $v2HistoricalA=[pscustomobject][ordered]@{correctionId=$v2RecordA.correctionId;introducedAgainstFramework=$v2RecordA.introducedAgainstFramework;requirementReason=$v2RecordA.requirementReason;effectiveRule=$v2RecordA.effectiveRule;applicability=$v2RecordA.applicability;decisionLocator=$v2RecordA.decisionLocator}
    $v2HistoricalB=[pscustomobject][ordered]@{correctionId=$v2RecordB.correctionId;introducedAgainstFramework=$v2RecordB.introducedAgainstFramework;requirementReason=$v2RecordB.requirementReason;effectiveRule=$v2RecordB.effectiveRule;applicability=$v2RecordB.applicability;decisionLocator=$v2RecordB.decisionLocator}
    Assert-True ((Get-AiwCanonicalCorrectionRecordIdentityV1 $v2HistoricalA)-ceq(Get-AiwCanonicalCorrectionRecordIdentityV1 $v2HistoricalB)-and(Get-AiwCanonicalCorrectionRecordIdentityV2 $v2RecordA)-cne(Get-AiwCanonicalCorrectionRecordIdentityV2 $v2RecordB)) 'corrections-v2-whole-identity-binds-progressive-fields'
    # Clone the healthy current carrier; malformed inputs bypass fixture projection.
    $invalidV2=Get-Content -LiteralPath $correctionPath -Raw -Encoding utf8|ConvertFrom-Json -Depth 100;$invalidV2.corrections[0].mechanicalCheckRefs=@('UNREGISTERED_CHECK');Write-Utf8 $correctionPath ($invalidV2|ConvertTo-Json -Depth 100);$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    Write-Output ('OBSERVE|correction-unregistered-input|identity='+(Get-Identity $correctionPath)+'|json='+($invalidV2|ConvertTo-Json -Depth 100 -Compress))
    $invalidV2Run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Write-Output ('OBSERVE|correction-unregistered-check|code='+$invalidV2Run.Code+'|text='+$invalidV2Run.Text.Trim())
    $invalidV2Value=$invalidV2Run.Output[-1]|ConvertFrom-Json
    Write-Output ('OBSERVE|correction-unregistered-check-json|'+($invalidV2Value|ConvertTo-Json -Depth 100 -Compress))
    Assert-True ($invalidV2Run.Code-eq2-and$invalidV2Value.status-ceq'FAIL'-and$invalidV2Value.reason-ceq'FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CORRECTIONS') 'corrections-v2-unregistered-mechanical-check-fails-closed'
    Write-Utf8 $correctionPath $correctionOriginal;$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
} finally { if($integrationContext){Close-IntegrationContext $integrationContext} }
if($Case-ceq'All'){Invoke-ProcessRuntimeMaintenanceConsumer}
Write-Output ('RESULT|'+(Get-IntegrationCheckCount)+'/'+(Get-IntegrationCheckCount)+' passed|scope=Framework-2.0.0-process|')
