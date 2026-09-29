[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$versionRoot=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $versionRoot 'scripts/ResultEvidence.psm1') -Force
$utf8=[Text.UTF8Encoding]::new($false)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-result-evidence-'+[guid]::NewGuid().ToString('N'))
$savedLocation=(Get-Location).Path;$savedCurrent=[Environment]::CurrentDirectory
$script:passed=0;$script:serial=0;$completed=$false
function Put([string]$Relative,[string]$Text){$p=Join-Path $temp $Relative;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$Text,$utf8);return $p}
function Json([string]$Relative,$Value){return Put $Relative (($Value|ConvertTo-Json -Depth 70 -Compress)+"`n")}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Ref([string]$Relative){return [pscustomobject]@{path=$Relative;identity=(Id (Join-Path $temp $Relative))}}
function Clone($Value){return $Value|ConvertTo-Json -Depth 70 -Compress|ConvertFrom-Json -Depth 70}
function Good([scriptblock]$Action,[string]$Name){$null=& $Action;$script:passed++;Write-Output ('PASS|'+$Name)}
function True([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Bad([scriptblock]$Action,[string]$Reason,[string]$Name){$caught='';try{$null=& $Action}catch{$caught=$_.Exception.Message};if(-not$caught.Contains($Reason)){throw ('ASSERT|'+$Name+'|expected='+$Reason+'|actual='+$caught)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Typed($Value,[string]$Kind){$script:serial++;$path='.ai-workspace/reports/evidence-'+$script:serial+'.json';$null=Json $path $Value;$ref=Ref $path;$ref|Add-Member kind $Kind;return $ref}
function Record([string]$Actor='owner',[string]$Outcome='PASS'){
    return [pscustomobject]@{schemaVersion=1;taskId='EVIDENCE-001';actor=$Actor;candidateObjects=@($candidate);requirementsRef=$requirements;outcome=$Outcome;checks=@([pscustomobject]@{id='semantic';method='MODEL_JUDGMENT';outcome='PASS';reason='Read the actual document against its bound requirements; semantic judgment remains instruction-bound.';evidenceLocators=@($requirements)});evidenceLocators=@($requirements)}
}
function Package([string]$Actor='owner'){
    return [pscustomobject]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='EVIDENCE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner';issuer='owner';issuerRole='TASK_OWNER';grantee=$Actor;bundle='RESULT_ACCEPT';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id $taskPath);actions=@('RESULT_ACCEPT');exactPaths=@($candidate.path);objectIdentities=@($candidate);invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Id $configPath)}
}
function Binding($Package){$Package|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=@($candidate);requirementsRef=$requirements;prerequisiteEvidenceRefs=@($self);reservedUserDecisionRefs=@()})}
function Stage([string]$Id,[string]$Kind,[string[]]$Dependencies,$Candidates,$Evidence){return [pscustomobject]@{id=$Id;kind=$Kind;requiredBy=$requirements;dependsOn=$Dependencies;candidateRef=@($Candidates);evidenceRefs=@($Evidence)}}
function Plan($Stages){return Get-AiwAcceptancePlan ('```aiw-acceptance-plan'+"`n"+([pscustomobject]@{schemaVersion=1;stages=@($Stages)}|ConvertTo-Json -Depth 50 -Compress)+"`n"+'```'+"`n")}
function Check-Package($Package){
    $path=Json '.ai-workspace/runtime/EVIDENCE-001/owner/package.json' $Package
    $lines=@(& (Join-Path $versionRoot 'scripts/check-authorization.ps1') -PackagePath $path -ObservedActor $Package.grantee -ObservedTaskId 'EVIDENCE-001' -ObservedOwner 'owner' -ObservedAction RESULT_ACCEPT -ObservedPath $candidate.path -ObservedIdentity ($candidate.path+'='+$candidate.identity) -TaskPath '.ai-workspace/tasks/active/EVIDENCE-001.md' -ExpectedTaskIdentity $Package.taskIdentity -ControllerControlPath '.ai-workspace/controller.json' 2>&1|ForEach-Object{[string]$_})
    return [pscustomobject]@{Code=$LASTEXITCODE;Text=($lines-join"`n")}
}
try{
    [IO.Directory]::CreateDirectory($temp)|Out-Null;Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp
    & git init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
    $configPath=Json '.ai-workspace/project.json' ([pscustomobject]@{schemaVersion=5;id='evidence-fixture';displayName='Evidence fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('protected.txt');frameworkCapabilities=[pscustomobject]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
    $controllerPath=Json '.ai-workspace/controller.json' ([pscustomobject]@{schemaVersion=1;projectId='evidence-fixture';controllerId='controller';controllerEpoch=1;state='CURRENT'})
    $taskText="# EVIDENCE-001 — result evidence`n- Task schema: 2.0.0`n- Profile: STANDARD; reason=fixture`n- Owner: owner`n- Work route: actor=owner; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[result.md]; actual_paths=[result.md]`n"
    $taskPath=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
    $null=Put 'result.md' "# Document result`nRequired content.`n";$candidate=Ref 'result.md'
    $null=Put 'requirements.md' "<!-- approved:BEGIN -->`nRequired content and concrete acceptance.`n<!-- approved:END -->`n";$requirements=Ref 'requirements.md'
    $ctx=New-AiwEvidenceContext $temp
    $record=Record;$self=Typed $record SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'document-model-judgment-no-fictional-exit-code'
    $commandOutput=@(& ([Environment]::ProcessPath) -NoProfile -Command "Write-Output 'actual-command-observation'");$exitCode=$LASTEXITCODE
    $null=Put 'command-output.txt' (($commandOutput-join"`n")+"`n")
    $null=Json 'command.json' ([pscustomobject]@{command='pwsh -NoProfile -Command Write-Output actual-command-observation';exitCode=$exitCode;output=(Ref 'command-output.txt')})
    $commandRecord=Record;$commandRecord.checks[0].method='COMMAND';$commandRecord.checks[0].evidenceLocators=@((Ref 'command.json'))
    $commandEvidence=Typed $commandRecord SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $commandEvidence EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'software-command-reads-actual-exit-and-output'
    $failure=Clone $commandRecord;$failure.outcome='FAIL';$failure.checks[0].outcome='FAIL'
    $null=Json 'failed-command.json' ([pscustomobject]@{command='observed failing command fixture';exitCode=2;output=(Ref 'command-output.txt')})
    $failure.checks[0].evidenceLocators=@((Ref 'failed-command.json'));$failedRef=Typed $failure SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $failedRef EVIDENCE-001 @($candidate) $requirements} 'failure-record-remains-observable'
    Bad {Read-AiwResultEvidence $ctx $failedRef EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'EVIDENCE_NOT_SUCCESSFUL' 'failed-test-cannot-satisfy-success-gate'
    $falsePass=Clone $commandRecord;$falsePass.checks[0].evidenceLocators=@((Ref 'failed-command.json'));$falseRef=Typed $falsePass SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $falseRef EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_COMMAND_FAILURE' 'nonzero-exit-cannot-be-pass'
    $mut=Clone $record;$mut|Add-Member fabricated $true;$ref=Typed $mut SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_FIELD_SET' 'unknown-evidence-field'
    $mut=Clone $record;$mut.checks[0]|Add-Member exitCode 0;$ref=Typed $mut SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_FIELD_SET' 'model-judgment-cannot-invent-exit-code'
    $mut=Clone $record;$mut.candidateObjects+=@($candidate);$ref=Typed $mut SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_DUPLICATE_REF' 'duplicate-candidates'
    $ref=Clone $self;$ref.kind='USER_DECISION'
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_KIND' 'no-self-reported-user-evidence-kind'
    Bad {Read-AiwResultEvidence $ctx $self OTHER-TASK @($candidate) $requirements} 'EVIDENCE_TASK_DRIFT' 'wrong-task-evidence'
    Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements -ExpectedActor stranger} 'EVIDENCE_ACTOR_DRIFT' 'wrong-actor-evidence'
    $null=Put 'result.md' 'changed candidate'
    Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_IDENTITY_DRIFT' 'candidate-change-invalidates-evidence'
    $null=Put 'result.md' "# Document result`nRequired content.`n"
    $null=Put 'requirements.md' 'changed requirements'
    Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_IDENTITY_DRIFT' 'requirements-change-invalidates-evidence'
    $null=Put 'requirements.md' "<!-- approved:BEGIN -->`nRequired content and concrete acceptance.`n<!-- approved:END -->`n"
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' ($taskText+"`nProgress: updated without changing requirements.`n")
    Good {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'ordinary-task-progress-does-not-invalidate-evidence'
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
    $section=Clone $record;$section.requirementsRef|Add-Member section approved;$sectionRef=Typed $section SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $sectionRef EVIDENCE-001 @($candidate) $section.requirementsRef} 'marked-requirements-section'
    $section.requirementsRef.section='missing';$sectionRef=Typed $section SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $sectionRef EVIDENCE-001 @($candidate) $section.requirementsRef} 'EVIDENCE_SECTION_UNBOUND' 'missing-marked-section'
    $protected=Clone $record;$protected.candidateObjects[0].path='protected.txt';$protectedRef=Typed $protected SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $protectedRef EVIDENCE-001 $protected.candidateObjects $requirements} 'EVIDENCE_PATH_FORBIDDEN' 'forbidden-before-missing-file-hash'
    $escape=Clone $record;$escape.candidateObjects[0].path='../outside.txt';$escapeRef=Typed $escape SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $escapeRef EVIDENCE-001 $escape.candidateObjects $requirements} 'EVIDENCE_PATH_INVALID' 'candidate-path-traversal'
    $duplicatePath='.ai-workspace/reports/duplicate.json';$null=Put $duplicatePath '{"schemaVersion":1,"schemaVersion":1}';$ref=Ref $duplicatePath;$ref|Add-Member kind SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_DUPLICATE_MEMBER' 'duplicate-json-members'

    $ownerPackage=Package
    Good {Assert-AiwAcceptanceBinding $ctx $ownerPackage $null} 'owner-default-acceptance'
    $delegated=Package delegate;Binding $delegated
    Good {Assert-AiwAcceptanceBinding $ctx $delegated $null} 'owner-delegated-pure-acceptance'
    $noDelegation=Package delegate
    Bad {Assert-AiwAcceptanceBinding $ctx $noDelegation $null} 'RESULT_ACCEPT_DELEGATION_REQUIRED' 'nonowner-without-delegation'
    $controller=Clone $delegated;$controller.issuer='controller';$controller.issuerRole='PROJECT_CONTROLLER'
    Bad {Assert-AiwAcceptanceBinding $ctx $controller $null} 'RESULT_ACCEPT_OWNER_OR_USER_DECISION_REQUIRED' 'controller-title-cannot-override-owner'
    $null=Put 'user-original.txt' 'Original fixture user explicitly grants delegate acceptance for the bound result.';$user=Ref 'user-original.txt'
    $userPackage=Clone $controller;$userPackage.userConfirmation=$user.identity;$userPackage.acceptanceBinding.reservedUserDecisionRefs=@($user)
    Good {Assert-AiwAcceptanceBinding $ctx $userPackage $null} 'explicit-user-source-identity-bound-ceiling'
    $mixed=Clone $delegated;$mixed.actions+=@('SOURCE_WRITE')
    Bad {Assert-AiwAcceptanceBinding $ctx $mixed $null} 'RESULT_ACCEPT_PURE_PACKAGE_REQUIRED' 'acceptance-no-write-authority'
    foreach($field in @('continuationPlan','repairReviewPlan','repairReviewBinding','receiverBinding','transitionPlan')){
        $mixed=Clone $delegated;$mixed|Add-Member $field ([pscustomobject]@{})
        Bad {Assert-AiwAcceptanceBinding $ctx $mixed $null} 'RESULT_ACCEPT_CANNOT_REDELEGATE' ('acceptance-no-redelegation-'+$field)
    }
    $badCandidate=Clone $delegated;$badCandidate.acceptanceBinding.candidateObjects[0].identity='1|'+('A'*64)
    Bad {Assert-AiwAcceptanceBinding $ctx $badCandidate $null} 'EVIDENCE_CANDIDATE_DRIFT' 'delegation-wrong-candidate'
    $badEvidence=Clone $delegated;$badEvidence.acceptanceBinding.prerequisiteEvidenceRefs=@($failedRef)
    Bad {Assert-AiwAcceptanceBinding $ctx $badEvidence $null} 'EVIDENCE_NOT_SUCCESSFUL' 'delegation-failed-prerequisite'
    $reviewPackage=Package reviewer;$reviewPackage.actions=@('REVIEW_EXECUTE');$reviewPackage.profile='CRITICAL';$reviewPackage.reviewIndependence='INDEPENDENT';$reviewPackage|Add-Member candidateWriter owner;$reviewPackage|Add-Member materialContributors @('contributor')
    $null=Json '.ai-workspace/reports/review-package.json' $reviewPackage
    $reviewRecord=Record reviewer APPROVED;$reviewRecord|Add-Member authorizationRef (Ref '.ai-workspace/reports/review-package.json')
    $review=Typed $reviewRecord REVIEW_VERDICT
    Good {Read-AiwResultEvidence $ctx $review EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'independent-review-original-package-bound'
    $badReview=Clone $reviewPackage;$badReview.candidateWriter='reviewer';$null=Json '.ai-workspace/reports/bad-review-package.json' $badReview
    $badReviewRecord=Clone $reviewRecord;$badReviewRecord.authorizationRef=Ref '.ai-workspace/reports/bad-review-package.json';$badReviewRef=Typed $badReviewRecord REVIEW_VERDICT
    Bad {Read-AiwResultEvidence $ctx $badReviewRef EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_REVIEW_INDEPENDENCE' 'writer-cannot-review-own-critical-candidate'
    $critical=Clone $delegated;$critical.profile='CRITICAL'
    Bad {Assert-AiwAcceptanceBinding $ctx $critical $null} 'RESULT_ACCEPT_CRITICAL_REVIEW_REQUIRED' 'critical-acceptance-needs-real-review'
    $critical.acceptanceBinding.prerequisiteEvidenceRefs+=@($review)
    Good {Assert-AiwAcceptanceBinding $ctx $critical $null} 'critical-acceptance-with-bound-independent-review'

    $selfStage=Stage self SELF_CHECK @() @($candidate) @($self)
    $acceptStage=Stage accept RESULT_ACCEPT @('self') @($candidate) @()
    $userStage=Stage user USER_DECISION @('accept') @() @()
    $plan=Plan @($selfStage,$acceptStage,$userStage)
    Good {Assert-AiwAcceptanceBinding $ctx $delegated $plan} 'later-user-gate-does-not-block-internal-acceptance'
    Bad {Assert-AiwAcceptanceStages $ctx $plan EVIDENCE-001} 'ACCEPTANCE_STAGE_INCOMPLETE' 'unfinished-stages-block-final-success'
    $beforeUser=Clone $userStage;$beforeUser.dependsOn=@();$beforeAccept=Clone $acceptStage;$beforeAccept.dependsOn=@('self','user')
    $beforePlan=Plan @($selfStage,$beforeUser,$beforeAccept)
    Bad {Assert-AiwAcceptanceBinding $ctx $delegated $beforePlan} 'ACCEPTANCE_STAGE_INCOMPLETE' 'prior-user-gate-blocks-internal-acceptance'
    $beforeUser.candidateRef=@($user);$beforePlan=Plan @($selfStage,$beforeUser,$beforeAccept)
    Bad {Assert-AiwAcceptanceBinding $ctx $delegated $beforePlan} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'user-text-reference-alone-is-not-current-binding'
    $withUser=Clone $delegated;$withUser.acceptanceBinding.reservedUserDecisionRefs=@($user)
    Good {Assert-AiwAcceptanceBinding $ctx $withUser $beforePlan} 'prior-user-source-reserved-in-original-package'
    $plainPlan=Plan @($selfStage,$acceptStage)
    Good {Assert-AiwAcceptanceBinding $ctx $delegated $plainPlan} 'requirements-with-no-user-gate-do-not-invent-one'
    $cycle=Clone $selfStage;$cycle.dependsOn=@('accept')
    Bad {Plan @($cycle,$acceptStage)} 'ACCEPTANCE_PLAN_CYCLE' 'cycle-rejected'
    Bad {Plan @($selfStage,$selfStage)} 'ACCEPTANCE_PLAN_STAGE_ID' 'duplicate-stage-rejected'
    $wrong=Clone $acceptStage;$wrong.dependsOn=@('unknown')
    Bad {Plan @($selfStage,$wrong)} 'ACCEPTANCE_PLAN_UNKNOWN_DEPENDENCY' 'unknown-stage-rejected'
    $wrong=Clone $selfStage;$wrong.evidenceRefs=@($review)
    Bad {Plan @($wrong,$acceptStage)} 'ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND' 'review-not-self-check-stage-evidence'
    $wrong=Clone $userStage;$wrong.evidenceRefs=@($self)
    Bad {Plan @($selfStage,$acceptStage,$wrong)} 'ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND' 'user-gate-no-synthetic-fourth-evidence-kind'
    $wrong=Clone $acceptStage;$wrong|Add-Member status PASS
    Bad {Plan @($selfStage,$wrong)} 'EVIDENCE_FIELD_SET' 'no-duplicated-stage-pass-state'
    $missing=Clone $selfStage;$missing.candidateRef[0].path='not-created.md'
    Good {Plan @($missing,$acceptStage)} 'structure-check-does-not-read-historical-evidence'
    $null=Put 'design.md' '# Existing design artifact';$design=Ref 'design.md'
    $designStage=Stage design DESIGN @() @($design) @()
    $designPlan=Plan @($designStage)
    Good {Assert-AiwAcceptanceStages $ctx $designPlan EVIDENCE-001} 'design-stage-reads-actual-design-artifact'
    $null=Put 'knowledge.md' 'Knowledge material with bound original source.';$knowledge=Ref 'knowledge.md'
    $knowledgeRecord=Record;$knowledgeRecord.candidateObjects=@($knowledge);$knowledgeRef=Typed $knowledgeRecord SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $knowledgeRef EVIDENCE-001 @($knowledge) $requirements -RequireSuccess} 'knowledge-semantic-check-does-not-require-code-tests'
    Good {Assert-AiwReviewSelfCheck $ctx @($self) EVIDENCE-001 @($candidate) $plan} 'document-review-route-without-test-run'
    Bad {Assert-AiwReviewSelfCheck $ctx @() EVIDENCE-001 @($candidate)} 'REVIEW_SELF_CHECK_REQUIRED' 'review-route-needs-actual-self-check'
    Bad {Assert-AiwReviewSelfCheck $ctx @($failedRef) EVIDENCE-001 @($candidate)} 'EVIDENCE_NOT_SUCCESSFUL' 'review-route-rejects-failed-self-check'

    $acceptPath=Json '.ai-workspace/reports/accept-package.json' $delegated
    $accepted=Record delegate ACCEPTED;$accepted|Add-Member authorizationRef (Ref '.ai-workspace/reports/accept-package.json')
    $acceptedRef=Typed $accepted RESULT_ACCEPTANCE
    Good {Read-AiwResultEvidence $ctx $acceptedRef EVIDENCE-001 @($candidate) $requirements -RequireSuccess -AuthorizationIdentity (Id $acceptPath)} 'delegated-result-links-original-package'
    Bad {Read-AiwResultEvidence $ctx $acceptedRef EVIDENCE-001 @($candidate) $requirements -AuthorizationIdentity ('1|'+('F'*64))} 'EVIDENCE_AUTHORIZATION_DRIFT' 'wrong-original-package-rejected'
    $completeAccept=Clone $acceptStage;$completeAccept.evidenceRefs=@($acceptedRef);$completeUser=Clone $userStage;$completeUser.candidateRef=@($user)
    $complete=Plan @($selfStage,$completeAccept,$completeUser)
    Bad {Assert-AiwAcceptanceStages $ctx $complete EVIDENCE-001} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'accepted-internally-still-needs-later-user-gate'
    Good {Assert-AiwAcceptanceStages $ctx $complete EVIDENCE-001 '' @($user)} 'all-required-stages-complete'
    $run=Check-Package $ownerPackage;True ($run.Code-eq0) ('actual-checker-owner-'+$run.Text)
    $run=Check-Package $delegated;True ($run.Code-eq0) ('actual-checker-delegate-'+$run.Text)
    $currentUser=Clone $userPackage;$currentUser.decisionClass='PRODUCT_RESULT'
    $currentUser|Add-Member issuerControllerId controller;$currentUser|Add-Member issuerControllerEpoch 1;$currentUser|Add-Member controllerControlIdentity (Id $controllerPath);$currentUser.invalidatesOn+=@('CONTROLLER_EPOCH_CHANGE')
    $run=Check-Package $currentUser;True ($run.Code-eq0) ('actual-checker-explicit-user-source-'+$run.Text)
    $foreign=Clone $delegated;$foreign.issuer='unrelated-parent-owner';$run=Check-Package $foreign;True ($run.Code-ne0-and$run.Text.Contains('TASK_OWNER_MUST_OWN_TASK')) 'actual-checker-parent-is-not-child-authority'

    $receipt=[pscustomobject]@{taskId='EVIDENCE-001';actor='owner';actionKind='REVIEW_ROUTE';exactPaths=@($candidate.path);sourceLocators=[pscustomobject]@{projectRoot=$temp;frameworkRoot=$temp;taskRelativePath='.ai-workspace/tasks/active/EVIDENCE-001.md';authorizationPackagePath=$acceptPath};authorityContext=[pscustomobject]@{forbiddenScope=@();authorizationIdentity=(Id $acceptPath)}}
    $boundary=[pscustomobject]@{mode='ADMIT_ACTION';evidenceRefs=@();publicDecisionIdentity='NOT_REQUIRED'}
    Bad {Get-AiwBoundaryEvidence $receipt $boundary} 'TYPED_EVIDENCE_REQUIRED' 'boundary-rejects-obligation-strings-without-record'
    $boundary.evidenceRefs=@($self)
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'boundary-route-consumes-real-self-check'
    $receipt.actionKind='TEST_RUN';$boundary.mode='FINALIZE_OUTPUT';$boundary.evidenceRefs=@($failedRef)
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'boundary-reports-real-test-failure-without-blessing-success'
    $receipt.actionKind='RESULT_ACCEPT';$receipt.actor='delegate';$boundary.evidenceRefs=@($acceptedRef)
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'boundary-finalizes-delegated-acceptance'
    $receipt.actionKind='CONTROL_WRITE';$receipt.actor='owner';$boundary.evidenceRefs=@()
    $receipt.exactPaths=@('.ai-workspace/tasks/active/EVIDENCE-001.md')
    $closedText=$taskText.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+"`n- Closure outcome: SUCCESS`n"+'```aiw-acceptance-plan'+"`n"+($complete|ConvertTo-Json -Depth 50 -Compress)+"`n"+'```'+"`n"
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $closedText
    Bad {Get-AiwBoundaryEvidence $receipt $boundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'actual-boundary-close-rejects-pending-user-source'
    $boundary.publicDecisionIdentity=$user.identity
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'actual-boundary-close-with-user-identity'
    $boundary.publicDecisionIdentity='NOT_REQUIRED'
    $legacyClosed=$closedText.Replace("- Closure outcome: SUCCESS`n",'')
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $legacyClosed
    Bad {Get-AiwBoundaryEvidence $receipt $boundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'omitting-closure-outcome-cannot-bypass-stage-evidence'
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $closedText
    $parentText="# PARENT-001 — controller coordination`n- Owner: owner`n"
    $null=Put '.ai-workspace/tasks/active/PARENT-001.md' $parentText
    $parentReceipt=Clone $receipt;$parentReceipt.taskId='PARENT-001';$parentReceipt.sourceLocators.taskRelativePath='.ai-workspace/tasks/active/PARENT-001.md'
    Bad {Get-AiwBoundaryEvidence $parentReceipt $boundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'controller-closing-other-task-still-checks-its-user-gate'
    $boundary.publicDecisionIdentity=$user.identity
    Good {Get-AiwBoundaryEvidence $parentReceipt $boundary} 'controller-closing-other-task-with-complete-stage-evidence'
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
    $userGrantPath=Json '.ai-workspace/reports/user-grant-package.json' $currentUser
    $userReceipt=Clone $receipt;$userReceipt.actionKind='RESULT_ACCEPT';$userReceipt.actor='delegate';$userReceipt.exactPaths=@($candidate.path);$userReceipt.sourceLocators.authorizationPackagePath=$userGrantPath;$userReceipt.authorityContext.authorizationIdentity=Id $userGrantPath
    $boundary.mode='ADMIT_ACTION';$boundary.publicDecisionIdentity='NOT_REQUIRED'
    Bad {Get-AiwBoundaryEvidence $userReceipt $boundary} 'RESULT_ACCEPT_CURRENT_USER_DECISION_UNBOUND' 'user-exception-needs-current-boundary-decision'
    $boundary.publicDecisionIdentity=$user.identity
    Good {Get-AiwBoundaryEvidence $userReceipt $boundary} 'user-exception-current-boundary-decision-bound'
    $committed=Clone $accepted;$committed|Add-Member acceptedCommit ('A'*40);$committedRef=Typed $committed RESULT_ACCEPTANCE
    Good {Assert-AiwPushAcceptance $ctx $committedRef EVIDENCE-001 @($candidate) ('A'*40)} 'push-consumes-typed-accepted-commit'
    Bad {Assert-AiwPushAcceptance $ctx $committedRef EVIDENCE-001 @($candidate) ('B'*40)} 'PUSH_ACCEPTED_COMMIT_DRIFT' 'push-wrong-commit-rejected'
    Bad {Assert-AiwPushAcceptance $ctx $acceptedRef EVIDENCE-001 @($candidate) ('A'*40)} 'PUSH_ACCEPTED_COMMIT_DRIFT' 'design-acceptance-no-fictional-commit-for-push'
    $originalCandidate=$candidate;$originalSelf=$self
    foreach($case in @('delete-only','mixed')){
        $removedPath=Join-Path $temp 'removed.md';$null=Put 'removed.md' 'Candidate removed by the fixture action.';[IO.File]::Delete($removedPath)
        $absent=[pscustomobject]@{path='removed.md';identity='MISSING'}
        $candidate=@(if($case-ceq'mixed'){$originalCandidate;$absent}else{$absent})
        function Candidate-Package([string]$Actor,[string]$Action){
            $p=Package $Actor;$p.actions=@($Action)
            $p.objectIdentities=@($candidate|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$(if($_.identity-ceq'MISSING'){'NEW'}else{$_.identity})}})
            return $p
        }
        $selfRecord=Record;$self=Typed $selfRecord SELF_CHECK
        $selfPackage=Candidate-Package owner TEST_RUN;$selfPackagePath=Json ".ai-workspace/reports/$case-self-package.json" $selfPackage
        $caseReceipt=Clone $receipt;$caseReceipt.exactPaths=@($candidate.path);$caseReceipt.actor='owner';$caseReceipt.actionKind='TEST_RUN'
        $caseReceipt.sourceLocators.authorizationPackagePath=$selfPackagePath;$caseReceipt.authorityContext.authorizationIdentity=Id $selfPackagePath
        $caseBoundary=[pscustomobject]@{mode='FINALIZE_OUTPUT';evidenceRefs=@($self);publicDecisionIdentity='NOT_REQUIRED'}
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-self-check-preserves-absent-candidate')
        $routePackage=Candidate-Package owner REVIEW_ROUTE;$routePath=Json ".ai-workspace/reports/$case-route-package.json" $routePackage
        $caseReceipt.actionKind='REVIEW_ROUTE';$caseReceipt.sourceLocators.authorizationPackagePath=$routePath;$caseReceipt.authorityContext.authorizationIdentity=Id $routePath;$caseBoundary.mode='ADMIT_ACTION'
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-route-consumes-full-candidate-self-check')
        $reviewPackage=Candidate-Package reviewer REVIEW_EXECUTE;$reviewPackage.reviewIndependence='INDEPENDENT';$reviewPackage|Add-Member candidateWriter owner;$reviewPackage|Add-Member materialContributors @()
        $reviewPath=Json ".ai-workspace/reports/$case-review-package.json" $reviewPackage
        $reviewRecord=Record reviewer APPROVED;$reviewRecord|Add-Member authorizationRef ([pscustomobject]@{path=$reviewPath;identity=(Id $reviewPath)})
        $caseReview=Typed $reviewRecord REVIEW_VERDICT
        $caseReceipt.actionKind='REVIEW_EXECUTE';$caseReceipt.actor='reviewer';$caseReceipt.sourceLocators.authorizationPackagePath=$reviewPath;$caseReceipt.authorityContext.authorizationIdentity=Id $reviewPath
        $caseBoundary.mode='FINALIZE_OUTPUT';$caseBoundary.evidenceRefs=@($caseReview)
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-review-binds-original-NEW-to-observed-MISSING')
        $acceptPackage=Candidate-Package delegate RESULT_ACCEPT;Binding $acceptPackage;$acceptPackage.acceptanceBinding.prerequisiteEvidenceRefs+=@($caseReview)
        $acceptPathForCase=Json ".ai-workspace/reports/$case-accept-package.json" $acceptPackage
        $acceptRecord=Record delegate ACCEPTED;$acceptRecord|Add-Member authorizationRef ([pscustomobject]@{path=$acceptPathForCase;identity=(Id $acceptPathForCase)})
        $caseAcceptance=Typed $acceptRecord RESULT_ACCEPTANCE
        $caseReceipt.actionKind='RESULT_ACCEPT';$caseReceipt.actor='delegate';$caseReceipt.sourceLocators.authorizationPackagePath=$acceptPathForCase;$caseReceipt.authorityContext.authorizationIdentity=Id $acceptPathForCase
        $caseBoundary.mode='ADMIT_ACTION';$caseBoundary.evidenceRefs=@()
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-delegated-acceptance-admission')
        $caseBoundary.mode='FINALIZE_OUTPUT';$caseBoundary.evidenceRefs=@($caseAcceptance)
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-acceptance-finalizes-full-candidate-set')
        $casePlan=Plan @((Stage self SELF_CHECK @() $candidate @($self)),(Stage review RESULT_REVIEW @('self') $candidate @($caseReview)),(Stage accept RESULT_ACCEPT @('review') $candidate @($caseAcceptance)))
        Good {Assert-AiwAcceptanceStages $ctx $casePlan EVIDENCE-001} ($case+'-all-result-stages-consume-absent-state')
        True (Test-Json -Json ($selfRecord|ConvertTo-Json -Depth 50) -SchemaFile (Join-Path $versionRoot 'EVIDENCE_RECORD_SCHEMA.json')) ($case+'-record-schema-describes-absent-state')
        True (Test-Json -Json ($casePlan|ConvertTo-Json -Depth 50) -SchemaFile (Join-Path $versionRoot 'ACCEPTANCE_PLAN_SCHEMA.json')) ($case+'-plan-schema-describes-absent-state')
        if($case-ceq'mixed'){
            $omitted=Clone $selfRecord;$omitted.candidateObjects=@($originalCandidate);$omittedRef=Typed $omitted SELF_CHECK
            Bad {Read-AiwResultEvidence $ctx $omittedRef EVIDENCE-001 $candidate $requirements} 'EVIDENCE_CANDIDATE_SET' 'mixed-candidate-cannot-omit-deletion'
        }
        $null=Put 'removed.md' 'Unexpected reappearance.'
        Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 $candidate $requirements} 'EVIDENCE_IDENTITY_DRIFT' ($case+'-unexpected-reappearance-rejected')
        [IO.File]::Delete($removedPath);$null=[IO.Directory]::CreateDirectory($removedPath)
        Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 $candidate $requirements} 'EVIDENCE_NOT_FILE' ($case+'-directory-replacement-rejected')
        [IO.Directory]::Delete($removedPath)
    }
    $missingRecord=Record;$missingRecord.candidateObjects=@([pscustomobject]@{path='absent-parent/child.md';identity='MISSING'});$missingRef=Typed $missingRecord SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $missingRef EVIDENCE-001 $missingRecord.candidateObjects $requirements} 'missing-parent-remains-observable-candidate-absence'
    $forgedMissing=Clone $missingRecord;$forgedMissing.candidateObjects[0].path='result.md';$forgedMissingRef=Typed $forgedMissing SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $forgedMissingRef EVIDENCE-001 $forgedMissing.candidateObjects $requirements} 'EVIDENCE_IDENTITY_DRIFT' 'present-file-cannot-be-reported-missing'
    $forbiddenMissing=Clone $missingRecord;$forbiddenMissing.candidateObjects[0].path='protected.txt';$forbiddenMissingRef=Typed $forbiddenMissing SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $forbiddenMissingRef EVIDENCE-001 $forbiddenMissing.candidateObjects $requirements} 'EVIDENCE_PATH_FORBIDDEN' 'missing-candidate-still-checks-protection-before-existence'
    $badRequirement=Clone $missingRecord;$badRequirement.requirementsRef.identity='MISSING';$badRequirementRef=Typed $badRequirement SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $badRequirementRef EVIDENCE-001 $badRequirement.candidateObjects $badRequirement.requirementsRef} 'EVIDENCE_IDENTITY_FORMAT' 'requirements-cannot-use-missing-candidate-sentinel'
    $missingCarrier=[pscustomobject]@{kind='SELF_CHECK';path='missing-evidence.json';identity='MISSING'}
    Bad {Read-AiwResultEvidence $ctx $missingCarrier EVIDENCE-001 $candidate $requirements} 'EVIDENCE_IDENTITY_FORMAT' 'evidence-carrier-must-have-real-bytes'
    Bad {Plan @((Stage user USER_DECISION @() $missingRecord.candidateObjects @()))} 'EVIDENCE_IDENTITY_FORMAT' 'user-decision-is-not-a-deleted-candidate'
    $linkTarget=Join-Path $temp 'junction-target';$linkPath=Join-Path $temp 'removed.md';$null=[IO.Directory]::CreateDirectory($linkTarget)
    $null=New-Item -ItemType Junction -Path $linkPath -Target $linkTarget
    try{Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 $candidate $requirements} 'EVIDENCE_PATH_REPARSE' 'reparse-replacement-is-not-absence'}finally{[IO.Directory]::Delete($linkPath)}
    $candidate=$originalCandidate;$self=$originalSelf
    $completed=$true
    Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=result-acceptance|evidenceCeiling=INSTRUCTION_BOUND')
}catch{Write-Output ('DIAG|fixture='+$temp);Write-Output $_.ScriptStackTrace;throw}finally{
    Set-Location -LiteralPath $savedLocation;[Environment]::CurrentDirectory=$savedCurrent
    if($completed){$full=[IO.Path]::GetFullPath($temp);$root=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/');if([IO.Path]::GetDirectoryName($full)-cne$root-or[IO.Path]::GetFileName($full)-cnotmatch '^aiw-result-evidence-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'};Remove-Item -LiteralPath $full -Recurse -Force}
}
