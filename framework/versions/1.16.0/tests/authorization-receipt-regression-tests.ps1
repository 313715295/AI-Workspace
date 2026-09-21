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
$taskChecker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\check-task-card.ps1'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-authorization-receipt-'+[guid]::NewGuid().ToString('N'))
$control=Join-Path $temp '.ai-workspace'
$taskRelative='.ai-workspace/tasks/active/AUTH-REGRESSION-001.md'
$taskPath=Join-Path $temp $taskRelative
$objectRelative='src/item.txt'
$objectPath=Join-Path $temp $objectRelative
$packagePath=Join-Path $control 'authorization.json'

function Write-Task([string]$Profile,[string]$Phase,[string]$Lifecycle='ACTIVE'){
  $currentExact=if($Profile-ceq'CRITICAL'){" current_exact=$objectRelative;"}else{''}
  $criticalLines=if($Profile-ceq'CRITICAL'){"- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=bind the package profile to the current task; added_machinery=NONE; escalation_trigger=another independent profile-binding defect`n- Phase gate: FALSE`n"}else{''}
  Write-Utf8 $taskPath ("# AUTH-REGRESSION-001 - authorization regression fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=writer-fixture; role=EXECUTOR; phase=$Phase`n- Range summary: profile=$Profile; lifecycle=$Lifecycle;$currentExact expected_paths=[$objectRelative]; actual_paths=[]`n$criticalLines")
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
  $arguments=@('-NoProfile','-NonInteractive','-File',$checker,'-PackagePath',$packagePath,'-ObservedActor',$Actor,'-ObservedTaskId','AUTH-REGRESSION-001','-ObservedOwner','owner-fixture','-ObservedAction',$Action,'-ObservedPath',$objectRelative,'-ObservedIdentity',($objectRelative+'='+(Get-Identity $objectPath)),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','REPO_LOCAL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',(Get-Identity (Join-Path $control 'project.json')),'-TaskPath',$taskRelative,'-ExpectedTaskIdentity',(Get-Identity $taskPath))
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
  $m.lifecycle='STABLE';$m.sourceReview='APPROVED';$m.fileCount=$paths.Count;$m.totalBytes=$total;$m.canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n"))));Write-Json $mpath $m
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
}finally{
  if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$tempResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));$tempPrefix=$tempRoot+[IO.Path]::DirectorySeparatorChar;$tempLeaf=[IO.Path]::GetFileName($tempResolved);if(-not$tempResolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)-or$tempLeaf-cnotmatch'^aiw-authorization-receipt-[a-f0-9]{32}$'){throw 'TEMP_CLEANUP_BOUNDARY'};Get-ChildItem -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue}
}
Write-Output ('RESULT|'+$passed+' passed|scope=authorization-receipt-regression')
