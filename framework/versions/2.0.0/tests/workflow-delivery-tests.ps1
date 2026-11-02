[CmdletBinding()]param()
Import-Module (Join-Path $PSScriptRoot 'TestNativeOutput.psm1')
Initialize-AiwTestNativeOutput
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../scripts/ProcessRequirementComposition.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../scripts/WorkflowDelivery.psm1') -Force
$passed=0;$utf8=[Text.UTF8Encoding]::new($false)
function Save([string]$Path,$Value){[IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 70 -Compress)+"`n"),$utf8)}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Reject([scriptblock]$Action,[string]$Name,[string]$Reason=''){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=(-not$Reason-or$_.Exception.Message.Contains($Reason))};Check $rejected $Name}
function Clone($Value){$Value|ConvertTo-Json -Depth 70|ConvertFrom-Json -Depth 70}
function HostResult([string]$Recipient){[pscustomobject]@{content=@([pscustomobject]@{type='text';text=('{"threadId":"'+$Recipient+'"}')});isError=$false}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-delivery-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
try{
 $hostPath=Join-Path $temp 'host.json';$authPath=Join-Path $temp 'authorization.json'
 $candidatePath=Join-Path $temp 'candidate.md';[IO.File]::WriteAllText($candidatePath,'Isolated protocol candidate.',$utf8)
 $package=[pscustomobject]@{schemaVersion=1;taskId='DELIVERY-001';taskIdentity='current-task';projectConfigIdentity='current-config';userConfirmation='fixture-only';owner='owner';issuer='owner';grantee='reviewer';candidateWriter='writer';actions=@('REVIEW_EXECUTE');exactPaths=@('candidate.md');objectIdentities=@([pscustomobject]@{path='candidate.md';identity=Id $candidatePath})}
 Save $authPath $package
 $receipt=[pscustomobject]@{taskId='DELIVERY-001';taskIdentity='current-task';taskOwner='owner';taskActor='writer';actor='reviewer';actionKind='REVIEW_EXECUTE';resultKind='REVIEW_VERDICT';exactPaths=@('candidate.md');sourceLocators=[pscustomobject]@{projectRoot=$temp;frameworkRoot=$temp;taskRelativePath='NOT_APPLICABLE';authorizationPackagePath=$authPath};authorityContext=[pscustomobject]@{authorizationIdentity=Id $authPath;forbiddenScope=@('private')}}
 # Typed records are already checked by process before this private consumer.
 # Real checker/DISCOVER/FINALIZE integration is in authorization-receipt tests.
 $evidence=[pscustomobject]@{references=@([pscustomobject]@{kind='REVIEW_VERDICT'});records=@([pscustomobject]@{outcome='APPROVED'})}
 Save $hostPath (HostResult owner)
 $boundary=[pscustomobject]@{mode='FINALIZE_OUTPUT';publicDecisionIdentity='NOT_REQUIRED';deliveryReceipts=@();deliveryContext=[pscustomobject]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient='owner';observedRecipient='owner';outcome='SUCCESS';evidence=($hostPath+'#'+(Id $hostPath))}}
 $good=Get-AiwBoundDelivery $receipt $boundary $evidence
 Check ($good.consumer.recipient-ceq'owner'-and$good.closureSatisfied-and$good.delivery.delivered-and-not$good.consumer.userAuthorizationProven-and-not$good.consumer.recipientWorkProven) 'approved-host-acceptance-goes-to-owner-with-exact-ceiling'
 $bad=Clone $boundary;$bad.PSObject.Properties.Remove('deliveryContext');$bad.deliveryReceipts=@('DELIVERED')
 Reject {Get-AiwBoundDelivery $receipt $bad $evidence} 'string-receipt-cannot-bypass-review-consumer'
 $bad=Clone $boundary;$bad.deliveryContext.channel='NATIVE_RESPONSE';$bad.deliveryContext.stage='PREPARE';$bad.deliveryContext.expectedRecipient='USER';$bad.deliveryContext.observedRecipient='NOT_APPLICABLE';$bad.deliveryContext.outcome='NOT_SENT';$bad.deliveryContext.evidence='NOT_APPLICABLE'
 Reject {Get-AiwBoundDelivery $receipt $bad $evidence} 'agent-only-native-final-cannot-replace-direct-return'
 $decisionPath=Join-Path $temp 'original-user-message.txt';[IO.File]::WriteAllText($decisionPath,'Fixture original user explicitly requests delivery only in this chat.',$utf8)
 $bad.deliveryContext|Add-Member userDecisionRef ([pscustomobject]@{path=$decisionPath;identity=Id $decisionPath})
 Reject {Get-AiwBoundDelivery $receipt $bad $evidence} 'native-exception-needs-current-user-decision-binding'
 $bad.publicDecisionIdentity=Id $decisionPath;$native=Get-AiwBoundDelivery $receipt $bad $evidence
 Check ($native.consumer.recipient-ceq'USER'-and$native.closureSatisfied-and-not$native.delivery.delivered-and-not$native.consumer.userAuthorizationProven) 'bound-original-user-exception-is-instruction-bound-not-delivered'
 # A human can name an exact task consumer, including for an Owner/NONE result.
 # These private fixtures prove bindings; host JSON is simulated, not a send.
 foreach($actorCase in @('reviewer','owner','no-task')){
  $explicitReceipt=Clone $receipt
  if($actorCase-ceq'owner'){$explicitReceipt.actor='owner';$explicitReceipt.actionKind='NONE';$explicitPackage=Clone $package;$explicitPackage.grantee='owner';Save $authPath $explicitPackage;$explicitReceipt.authorityContext.authorizationIdentity=Id $authPath}
  if($actorCase-ceq'no-task'){$explicitReceipt.taskOwner='NOT_APPLICABLE';$explicitReceipt.actor='observer';$explicitReceipt.actionKind='NONE';$explicitReceipt.sourceLocators.authorizationPackagePath='NOT_REQUIRED'}
  $explicit=Clone $bad;$explicit.deliveryContext.channel='TASK_MESSAGE';$explicit.deliveryContext.expectedRecipient='human-chosen-task'
  $readyExplicit=Get-AiwBoundDelivery $explicitReceipt $explicit $evidence
  Check ($readyExplicit.consumer.reason-ceq'EXPLICIT_USER_TASK_DELIVERY'-and$readyExplicit.consumer.recipient-ceq'human-chosen-task'-and-not$readyExplicit.closureSatisfied-and-not$readyExplicit.consumer.userAuthorizationProven) ($actorCase+'-explicit-task-prepare-preserves-ceiling')
  $withoutDecision=Clone $explicit;$withoutDecision.deliveryContext.PSObject.Properties.Remove('userDecisionRef')
  Reject {Get-AiwBoundDelivery $explicitReceipt $withoutDecision $evidence} ($actorCase+'-no-human-ref-cannot-change-consumer') 'DELIVERY_CONSUMER_CHANNEL_MISMATCH'
  Save $hostPath (HostResult 'human-chosen-task');$explicit.deliveryContext.stage='OBSERVE';$explicit.deliveryContext.observedRecipient='human-chosen-task';$explicit.deliveryContext.outcome='SUCCESS';$explicit.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
  $deliveredExplicit=Get-AiwBoundDelivery $explicitReceipt $explicit $evidence
  Check ($deliveredExplicit.closureSatisfied-and$deliveredExplicit.delivery.delivered-and-not$deliveredExplicit.consumer.recipientWorkProven) ($actorCase+'-exact-simulated-host-closes-process-only')
  Save $hostPath (HostResult 'other');$explicit.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
  Reject {Get-AiwBoundDelivery $explicitReceipt $explicit $evidence} ($actorCase+'-explicit-task-rejects-wrong-host') 'DELIVERY_HOST_RESULT_MISMATCH'
  foreach($placeholder in @('USER','NOT_APPLICABLE','NOT_REQUIRED','UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')){
   $invalid=Clone $bad;$invalid.deliveryContext.channel='TASK_MESSAGE';$invalid.deliveryContext.expectedRecipient=$placeholder
   Reject {Get-AiwBoundDelivery $explicitReceipt $invalid $evidence} ($actorCase+'-rejects-explicit-placeholder-'+$placeholder) 'DELIVERY_EXPLICIT_TASK_RECIPIENT_REQUIRED'
  }
  $invalid=Clone $bad;$invalid.deliveryContext.expectedRecipient='human-chosen-task'
  Reject {Get-AiwBoundDelivery $explicitReceipt $invalid $evidence} ($actorCase+'-native-response-needs-user') 'DELIVERY_CONSUMER_CHANNEL_MISMATCH'
  Save $authPath $package
 }
 $unsafe=Clone $bad;$unsafe.deliveryContext.userDecisionRef.path=Join-Path $temp 'private/forbidden-decision.txt'
 Reject {Get-AiwBoundDelivery $receipt $unsafe $evidence} 'explicit-user-ref-protection-precedes-reading' 'EVIDENCE_PATH_FORBIDDEN'
 $drifted=Clone $bad;$drifted.publicDecisionIdentity=Id $decisionPath;[IO.File]::AppendAllText($decisionPath,' changed',$utf8)
 Reject {Get-AiwBoundDelivery $receipt $drifted $evidence} 'explicit-user-source-byte-drift-rejected' 'EVIDENCE_IDENTITY_DRIFT'
 [IO.File]::WriteAllText($decisionPath,'Fixture original user explicitly requests delivery only in this chat.',$utf8)
 $finding=Clone $evidence;$finding.records[0].outcome='CHANGES_REQUESTED'
 Reject {Get-AiwBoundDelivery $receipt $boundary $finding} 'finding-cannot-be-routed-to-owner-instead-of-writer'
 $toWriter=Clone $boundary;Save $hostPath (HostResult writer);$toWriter.deliveryContext.expectedRecipient='writer';$toWriter.deliveryContext.observedRecipient='writer';$toWriter.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 Check ((Get-AiwBoundDelivery $receipt $toWriter $finding).consumer.recipient-ceq'writer') 'finding-goes-to-bound-candidate-writer'
 Save $hostPath (HostResult owner);$boundary.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 $prepare=Clone $boundary;$prepare.deliveryContext.stage='PREPARE';$prepare.deliveryContext.outcome='NOT_SENT';$prepare.deliveryContext.observedRecipient='NOT_APPLICABLE';$prepare.deliveryContext.evidence='NOT_APPLICABLE'
 $ready=Get-AiwBoundDelivery $receipt $prepare $evidence
 Check ($ready.delivery.status-ceq'READY_TO_SEND'-and-not$ready.closureSatisfied) 'cross-task-prepare-does-not-close-delivery'
 $wrong=Clone $boundary;Save $hostPath (HostResult other);$wrong.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 Reject {Get-AiwBoundDelivery $receipt $wrong $evidence} 'actual-wrong-host-recipient-rejected'
 Reject {Get-AiwBoundDelivery $receipt $boundary $evidence} 'host-byte-drift-rejected'
 foreach($case in @('FAILURE','UNKNOWN')){
  $raw=if($case-ceq'FAILURE'){[pscustomobject]@{isError=$true;content=@([pscustomobject]@{type='text';text='Policy rejected this request.'})}}else{[pscustomobject]@{success=$true;status='sent'}}
  Save $hostPath $raw;$pending=Clone $boundary;$pending.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath);$pending.deliveryContext.outcome=$case;$pending.deliveryContext.observedRecipient='NOT_APPLICABLE'
  $result=Get-AiwBoundDelivery $receipt $pending $evidence
  Check (-not$result.closureSatisfied-and-not$result.delivery.delivered-and-not$result.delivery.retryAllowed) ('actual-'+$case+'-does-not-close-or-retry')
  $pending.deliveryContext.outcome='SUCCESS';$pending.deliveryContext.observedRecipient='owner'
  Reject {Get-AiwBoundDelivery $receipt $pending $evidence} ('self-reported-success-cannot-rewrite-'+$case)
 }
 $ambiguous=HostResult owner;$ambiguous.content+=@([pscustomobject]@{type='text';text='{"threadId":"other"}'})
 Check ((Get-AiwCodexSendOutcome $ambiguous owner).outcome-ceq'UNKNOWN') 'ambiguous-host-result-is-unknown'
 $duplicate=HostResult owner;$duplicate.content[0].text='{"threadId":"owner","threadId":"other"}'
 Check ((Get-AiwCodexSendOutcome $duplicate owner).outcome-ceq'UNKNOWN') 'duplicate-json-member-is-not-success'
 $routeEvidence=[pscustomobject]@{references=@([pscustomobject]@{kind='SELF_CHECK'});records=@([pscustomobject]@{actor='writer';outcome='PASS'})}
 $package.grantee='writer';$package.actions=@('REVIEW_ROUTE');$package|Add-Member repairReviewPlan ([pscustomobject]@{reviewer='reviewer';writer='writer';materialContributors=@('contributor')});Save $authPath $package
 $route=Clone $receipt;$route.actor='writer';$route.actionKind='REVIEW_ROUTE';$route.authorityContext.authorizationIdentity=Id $authPath
 Save $hostPath (HostResult reviewer);$sent=Clone $boundary;$sent.deliveryContext.expectedRecipient='reviewer';$sent.deliveryContext.observedRecipient='reviewer';$sent.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 Check ((Get-AiwBoundDelivery $route $sent $routeEvidence).consumer.recipient-ceq'reviewer') 'known-reviewer-bound-to-original-plan'
 $sent.deliveryContext.expectedRecipient='other';$sent.deliveryContext.observedRecipient='other';Save $hostPath (HostResult other);$sent.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 Reject {Get-AiwBoundDelivery $route $sent $routeEvidence} 'dispatch-cannot-substitute-another-reviewer'
 $package.repairReviewPlan.reviewer='DEFERRED_VISIBLE_REVIEWER';Save $authPath $package;$route.authorityContext.authorizationIdentity=Id $authPath
 Reject {Get-AiwBoundDelivery $route $sent $routeEvidence} 'deferred-reviewer-needs-real-creation-binding'
 # No host result or Reviewer identity is needed to reject a wrong author.
 $early=[pscustomobject]@{mode='ADMIT_ACTION';publicDecisionIdentity='NOT_REQUIRED'}
 $null=Assert-AiwReviewRoutePreparation $route $early $routeEvidence
 Check $true 'deferred-precreation-known-writer-and-self-validated'
 $badAuthor=Clone $routeEvidence;$badAuthor.records[0].actor='owner'
 Reject {Assert-AiwReviewRoutePreparation $route $early $badAuthor} 'deferred-precreation-rejects-wrong-author-before-host' 'DELIVERY_REVIEW_WRITER_DRIFT'
 $failedAuthor=Clone $routeEvidence;$failedAuthor.records[0].outcome='FAIL'
 Reject {Assert-AiwReviewRoutePreparation $route $early $failedAuthor} 'deferred-precreation-rejects-failed-self-before-host' 'DELIVERY_REVIEW_WRITER_DRIFT'
 $missingAuthor=[pscustomobject]@{references=@();records=@()}
 Reject {Assert-AiwReviewRoutePreparation $route $early $missingAuthor} 'deferred-precreation-needs-self-before-host' 'DELIVERY_REVIEW_SELF_CHECK_REQUIRED'
 $sent.deliveryContext|Add-Member reviewerAssignment ([pscustomobject]@{source='HOST_CREATE_THREAD_RESULT';createdBy='writer';threadId='other';hostId='fixture';taskId=$route.taskId;parentPackageIdentity=Id $authPath})
 Check ((Get-AiwBoundDelivery $route $sent $routeEvidence).consumer.recipient-ceq'other') 'original-deferred-plan-binds-observed-reviewer'
 $sent.deliveryContext.reviewerAssignment.createdBy='imposter'
 Reject {Get-AiwBoundDelivery $route $sent $routeEvidence} 'deferred-assignment-wrong-creator-rejected'
 $sent.deliveryContext.reviewerAssignment.createdBy='writer';$sent.deliveryContext.reviewerAssignment.threadId='contributor';$sent.deliveryContext.expectedRecipient='contributor'
 Reject {Get-AiwBoundDelivery $route $sent $routeEvidence} 'deferred-assignment-excludes-contributors'
 $sent.deliveryContext.PSObject.Properties.Remove('reviewerAssignment');$package.PSObject.Properties.Remove('repairReviewPlan');Save $authPath $package;$route.authorityContext.authorizationIdentity=Id $authPath
 $review=Clone $package;$review.grantee='other';$review.actions=@('REVIEW_EXECUTE');$review|Add-Member reviewIndependence 'INDEPENDENT';$review|Add-Member materialContributors @();$reviewPath=Join-Path $temp 'pure-review-package.json';Save $reviewPath $review
 $sent.deliveryContext.expectedRecipient='other';$sent.deliveryContext.observedRecipient='other';$sent.deliveryContext|Add-Member reviewPackageRef ([pscustomobject]@{path=$reviewPath;identity=Id $reviewPath})
 $requirementsPath=Join-Path $temp 'requirements.md';[IO.File]::WriteAllText($requirementsPath,'Read the exact isolated document before routing.',$utf8)
 $requirements=[pscustomobject]@{path=$requirementsPath;identity=Id $requirementsPath}
 $selfPath=Join-Path $temp 'author-self-check.json'
 $self=[pscustomobject]@{schemaVersion=1;taskId=$package.taskId;actor='writer';candidateObjects=$review.objectIdentities;requirementsRef=$requirements;outcome='PASS';checks=@([pscustomobject]@{id='read-candidate';method='MODEL_JUDGMENT';outcome='PASS';reason='Isolated document bytes inspected; not production acceptance.';evidenceLocators=@($requirements)});evidenceLocators=@($requirements)}
 Save $selfPath $self
 $sent|Add-Member evidenceRefs @([pscustomobject]@{kind='SELF_CHECK';path=$selfPath;identity=Id $selfPath})
 Check ((Get-AiwBoundDelivery $route $sent).consumer.recipient-ceq'other') 'writer-direct-dispatch-binds-author-self-check-and-pure-review'
 $review.materialContributors=@('owner');Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Check ((Get-AiwBoundDelivery $route $sent).closureSatisfied) 'delivery-owner-issuer-contributor-overlap-is-legal'
 $review.materialContributors=@('owner','owner');Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'delivery-internal-duplicate-contributor-refused' 'MATERIAL_CONTRIBUTOR_SET'
 $review.materialContributors=@();Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath

 $package.grantee='owner';Save $authPath $package;$route.actor='owner';$route.authorityContext.authorizationIdentity=Id $authPath
 Check ((Get-AiwBoundDelivery $route $sent).closureSatisfied) 'owner-dispatches-other-writer-candidate-with-author-evidence'
 $missing=Clone $sent;$missing.evidenceRefs=@()
 Reject {Get-AiwBoundDelivery $route $missing} 'owner-route-missing-author-evidence-rejected' 'DELIVERY_REVIEW_SELF_CHECK_REQUIRED'
 $validReview=Clone $review
 $review.candidateWriter='imposter';Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'owner-route-wrong-writer-rejected' 'DELIVERY_REVIEW_WRITER_DRIFT'
 $review=Clone $validReview;Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 $self.actor='imposter';Save $selfPath $self;$sent.evidenceRefs[0].identity=Id $selfPath
 Reject {Get-AiwBoundDelivery $route $sent} 'owner-route-wrong-self-check-actor-rejected' 'DELIVERY_REVIEW_WRITER_DRIFT'
 $self.actor='writer';$self.outcome='INCOMPLETE';Save $selfPath $self;$sent.evidenceRefs[0].identity=Id $selfPath
 Reject {Get-AiwBoundDelivery $route $sent} 'owner-route-incomplete-author-evidence-rejected' 'DELIVERY_REVIEW_WRITER_DRIFT'
 $self.outcome='PASS';Save $selfPath $self;$sent.evidenceRefs[0].identity=Id $selfPath
 $wrong=Clone $sent;$wrong.deliveryContext.expectedRecipient='someone-else';$wrong.deliveryContext.observedRecipient='someone-else'
 Reject {Get-AiwBoundDelivery $route $wrong} 'owner-route-wrong-consumer-rejected' 'DELIVERY_CONSUMER_CHANNEL_MISMATCH'
 $package.grantee='unrelated-router';Save $authPath $package;$route.actor=$package.grantee;$route.authorityContext.authorizationIdentity=Id $authPath
 Reject {Get-AiwBoundDelivery $route $sent} 'unrelated-actor-cannot-route-other-writer-candidate' 'DELIVERY_REVIEW_WRITER_DRIFT'
 $package.grantee='owner';Save $authPath $package;$route.actor='owner';$route.authorityContext.authorizationIdentity=Id $authPath
 foreach($actor in @('owner','writer')){
  $review=Clone $validReview;$review.grantee=$actor;Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
  Reject {Get-AiwBoundDelivery $route $sent} ('owner-route-excludes-reviewer-'+$actor) 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'
 }
 $review=Clone $validReview;$review.issuer='other';Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'owner-route-excludes-review-issuer' 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'
 $review=Clone $validReview;$review.exactPaths=@('different.md');Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'owner-route-wrong-review-scope-rejected' 'DELIVERY_REVIEW_SCOPE_DRIFT'
 $review=Clone $validReview;$review.objectIdentities[0].identity='1|'+('A'*64);Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'owner-route-wrong-candidate-bytes-rejected' 'EVIDENCE_IDENTITY_DRIFT'
 $review=Clone $validReview;Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Save $hostPath ([pscustomobject]@{success=$true;status='sent'});$sent.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 Reject {Get-AiwBoundDelivery $route $sent} 'owner-route-invented-host-success-rejected' 'DELIVERY_HOST_RESULT_MISMATCH'
 $sent.deliveryContext.outcome='UNKNOWN';$sent.deliveryContext.observedRecipient='NOT_APPLICABLE'
 Check (-not(Get-AiwBoundDelivery $route $sent).closureSatisfied) 'owner-route-unknown-host-result-remains-open'
 Save $hostPath (HostResult other);$sent.deliveryContext.outcome='SUCCESS';$sent.deliveryContext.observedRecipient='other';$sent.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 $validReview=Clone $review;$review.objectIdentities=@();Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'direct-review-package-missing-candidate-rejected'
 $review=Clone $validReview;$review.materialContributors=@('other');Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'direct-review-package-contributor-as-reviewer-rejected' 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'
 $review=Clone $validReview
 $review.owner='someone-else';Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'review-package-other-owner-rejected'

 # Whole review readiness has a larger scope than finite production. This
 # private consumer observes real fixture bytes and exact host result shapes;
 # authorization/continuation integration is tested by the receipt suite.
 $untouchedPath=Join-Path $temp 'untouched.md';[IO.File]::WriteAllText($untouchedPath,'Original frozen untouched member.',$utf8)
 $wholeObjects=@([pscustomobject]@{path='candidate.md';identity=Id $candidatePath},[pscustomobject]@{path='untouched.md';identity=Id $untouchedPath},[pscustomobject]@{path='retired.md';identity='NEW'})
 $package.grantee='writer';$package.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE')
 $package|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE') -Force
 $package|Add-Member repairReviewPlan ([pscustomobject]@{writer='writer';reviewer='other';maxCycles=2;materialContributors=@();reviewScope=$wholeObjects}) -Force
 Save $authPath $package;$route.actor='writer';$route.exactPaths=@($wholeObjects.path);$route.authorityContext.authorizationIdentity=Id $authPath
 $review=Clone $validReview;$review.exactPaths=@($wholeObjects.path);$review.objectIdentities=Clone $wholeObjects;Save $reviewPath $review
 $sent.deliveryContext.reviewPackageRef=[pscustomobject]@{path=$reviewPath;identity=Id $reviewPath}
 $self.candidateObjects=@($wholeObjects|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$(if($_.identity-ceq'NEW'){'MISSING'}else{$_.identity})}});Save $selfPath $self
 $sent.evidenceRefs=@([pscustomobject]@{kind='SELF_CHECK';path=$selfPath;identity=Id $selfPath})
 Save $hostPath (HostResult other);$sent.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 $whole=Get-AiwBoundDelivery $route $sent
 Check ($whole.closureSatisfied-and$whole.consumer.recipient-ceq'other'-and$package.exactPaths.Count-eq1-and-not$whole.consumer.recipientWorkProven) 'planned-whole-review-delivery-preserves-finite-write-scope-and-host-ceiling'
 $finiteSelf=Clone $self;$finiteSelf.candidateObjects=@($self.candidateObjects[0]);Save $selfPath $finiteSelf;$sent.evidenceRefs[0].identity=Id $selfPath
 Reject {Get-AiwBoundDelivery $route $sent} 'planned-whole-delivery-rejects-finite-self-check'
 Save $selfPath $self;$sent.evidenceRefs[0].identity=Id $selfPath
 $frozenBytes=[IO.File]::ReadAllBytes($untouchedPath);[IO.File]::WriteAllText($untouchedPath,'Drift after readiness.',$utf8)
 Reject {Get-AiwBoundDelivery $route $sent} 'planned-whole-delivery-rejects-current-untouched-drift'
 [IO.File]::WriteAllBytes($untouchedPath,$frozenBytes)
 $retiredPath=Join-Path $temp 'retired.md';[IO.File]::WriteAllText($retiredPath,'Reappeared.',$utf8)
 Reject {Get-AiwBoundDelivery $route $sent} 'planned-whole-delivery-rejects-retired-reappearance'
 Remove-Item -LiteralPath $retiredPath -Force
 $extraPath=Join-Path $temp 'extra.md';[IO.File]::WriteAllText($extraPath,'Unapproved review member.',$utf8)
 $review.exactPaths+=@('extra.md');$review.objectIdentities+=@([pscustomobject]@{path='extra.md';identity=Id $extraPath});$route.exactPaths=@($review.exactPaths)
 $self.candidateObjects+=@([pscustomobject]@{path='extra.md';identity=Id $extraPath});Save $selfPath $self;$sent.evidenceRefs[0].identity=Id $selfPath
 Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'planned-whole-delivery-rejects-unapproved-extra-scope' 'DELIVERY_REVIEW_SCOPE_NOT_GRANTED'
 $sent.deliveryContext.reviewPackageRef.path=Join-Path $temp 'private/missing.json'
 Reject {Get-AiwBoundDelivery $route $sent} 'forbidden-reference-stops-before-read'
 # Execute the documentation's one local organization choice for all three
 # supported outcomes. This is not natural-intent or model-attention evidence.
 $promptText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../PROMPTS.md')).Replace("`r`n","`n")
 $exampleStart=$promptText.IndexOf('$parent=$authorizationTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100',[StringComparison]::Ordinal)
 $exampleEnd=$promptText.IndexOf('```',$exampleStart,[StringComparison]::Ordinal)
 if($exampleStart-lt0-or$exampleEnd-lt$exampleStart){throw 'ORGANIZATION_EXAMPLE_MISSING'}
 $example=[scriptblock]::Create($promptText.Substring($exampleStart,$exampleEnd-$exampleStart))
 $authorizationTemplate=[pscustomobject]@{owner='owner';issuer='owner';grantee='UNBOUND_RECEIVER';actions=@('SOURCE_WRITE');exactPaths=@('candidate.md');objectIdentities=@([pscustomobject]@{path='candidate.md';identity=Id $candidatePath});selfCheckRepairLimit=4}
 $requiresTest=$true;$maxReviewCycles=2;$materialContributors=@('contributor')
 foreach($organization in @('DIRECT_REVIEW','OWNER_INTEGRATION','WRITE_ONLY')){
  $emitted=& $example;$parent=$emitted.authorizationTemplate
  $wanted=switch -CaseSensitive ($organization){DIRECT_REVIEW{@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE')} OWNER_INTEGRATION{@('SOURCE_WRITE','TEST_RUN')} WRITE_ONLY{@('SOURCE_WRITE')}}
  Check ((@($parent.actions)-join'|')-ceq(@($wanted)-join'|')-and$emitted.dispatch.Contains(($parent.actions-join', '))-and$parent.grantee-ceq'UNBOUND_RECEIVER'-and$parent.exactPaths[0]-ceq'candidate.md') ('same-source-organization-parent-and-dispatch-'+$organization)
  Check (($null-ne$parent.PSObject.Properties['repairReviewPlan'])-eq($organization-ceq'DIRECT_REVIEW')) ('same-source-organization-review-authority-'+$organization)
 }
 $organization='UNKNOWN';Reject {& $example} 'organization-unknown-does-not-invent-a-route' 'ORGANIZATION_ROUTE_REQUIRED'
 Write-Output ('WORKFLOW_DELIVERY_TESTS_PASS|checks='+$passed+'|evidence=ISOLATED_PROTOCOL_NOT_HOST_INVOCATION')
}finally{
 $full=[IO.Path]::GetFullPath($temp);$root=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($full)-cne$root-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-delivery-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
