[CmdletBinding()]param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../scripts/ProcessRequirementComposition.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../scripts/WorkflowDelivery.psm1') -Force
$passed=0;$utf8=[Text.UTF8Encoding]::new($false)
function Save([string]$Path,$Value){[IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 70 -Compress)+"`n"),$utf8)}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Reject([scriptblock]$Action,[string]$Name){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Check $rejected $Name}
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
 $package.grantee='writer';$package.actions=@('REVIEW_ROUTE');$package|Add-Member repairReviewPlan ([pscustomobject]@{reviewer='reviewer';writer='writer';materialContributors=@('contributor')});Save $authPath $package
 $route=Clone $receipt;$route.actor='writer';$route.actionKind='REVIEW_ROUTE';$route.authorityContext.authorizationIdentity=Id $authPath
 Save $hostPath (HostResult reviewer);$sent=Clone $boundary;$sent.deliveryContext.expectedRecipient='reviewer';$sent.deliveryContext.observedRecipient='reviewer';$sent.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 Check ((Get-AiwBoundDelivery $route $sent).consumer.recipient-ceq'reviewer') 'known-reviewer-bound-to-original-plan'
 $sent.deliveryContext.expectedRecipient='other';$sent.deliveryContext.observedRecipient='other';Save $hostPath (HostResult other);$sent.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
 Reject {Get-AiwBoundDelivery $route $sent} 'dispatch-cannot-substitute-another-reviewer'
 $package.repairReviewPlan.reviewer='DEFERRED_VISIBLE_REVIEWER';Save $authPath $package;$route.authorityContext.authorizationIdentity=Id $authPath
 Reject {Get-AiwBoundDelivery $route $sent} 'deferred-reviewer-needs-real-creation-binding'
 $sent.deliveryContext|Add-Member reviewerAssignment ([pscustomobject]@{source='HOST_CREATE_THREAD_RESULT';createdBy='writer';threadId='other';hostId='fixture';taskId=$route.taskId;parentPackageIdentity=Id $authPath})
 Check ((Get-AiwBoundDelivery $route $sent).consumer.recipient-ceq'other') 'original-deferred-plan-binds-observed-reviewer'
 $sent.deliveryContext.reviewerAssignment.createdBy='imposter'
 Reject {Get-AiwBoundDelivery $route $sent} 'deferred-assignment-wrong-creator-rejected'
 $sent.deliveryContext.reviewerAssignment.createdBy='writer';$sent.deliveryContext.reviewerAssignment.threadId='contributor';$sent.deliveryContext.expectedRecipient='contributor'
 Reject {Get-AiwBoundDelivery $route $sent} 'deferred-assignment-excludes-contributors'
 $sent.deliveryContext.PSObject.Properties.Remove('reviewerAssignment');$package.PSObject.Properties.Remove('repairReviewPlan');Save $authPath $package;$route.authorityContext.authorizationIdentity=Id $authPath
 $review=Clone $package;$review.grantee='other';$review.actions=@('REVIEW_EXECUTE');$review|Add-Member reviewIndependence 'INDEPENDENT';$reviewPath=Join-Path $temp 'pure-review-package.json';Save $reviewPath $review
 $sent.deliveryContext.expectedRecipient='other';$sent.deliveryContext.observedRecipient='other';$sent.deliveryContext|Add-Member reviewPackageRef ([pscustomobject]@{path=$reviewPath;identity=Id $reviewPath})
 Check ((Get-AiwBoundDelivery $route $sent).consumer.recipient-ceq'other') 'owner-direct-dispatch-binds-existing-pure-review-package'
 $validReview=Clone $review;$review.objectIdentities=@();Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'direct-review-package-missing-candidate-rejected'
 $review=Clone $validReview;$review|Add-Member materialContributors @('other');Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'direct-review-package-contributor-as-reviewer-rejected'
 $review=Clone $validReview
 $review.owner='someone-else';Save $reviewPath $review;$sent.deliveryContext.reviewPackageRef.identity=Id $reviewPath
 Reject {Get-AiwBoundDelivery $route $sent} 'review-package-other-owner-rejected'
 $sent.deliveryContext.reviewPackageRef.path=Join-Path $temp 'private/missing.json'
 Reject {Get-AiwBoundDelivery $route $sent} 'forbidden-reference-stops-before-read'
 Write-Output ('WORKFLOW_DELIVERY_TESTS_PASS|checks='+$passed+'|evidence=ISOLATED_PROTOCOL_NOT_HOST_INVOCATION')
}finally{
 $full=[IO.Path]::GetFullPath($temp);$root=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($full)-cne$root-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-delivery-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
