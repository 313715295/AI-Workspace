Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')

# These are observations of supplied bytes. User provenance and host origin
# remain instruction-bound; neither a file nor a matching ID grants authority.
function Get-AiwCodexSendOutcome($HostResult,[string]$ExpectedRecipient) {
    $outcome='UNKNOWN';$recipient='NOT_APPLICABLE'
    if($HostResult-is[pscustomobject]){
        $errorField=$HostResult.PSObject.Properties['isError']
        if($null-ne$errorField-and$errorField.Value-isnot[bool]){throw 'DELIVERY_HOST_ERROR_TYPE'}
        if($null-ne$errorField-and$errorField.Value){$outcome='FAILURE'}
        elseif($null-ne$HostResult.PSObject.Properties['content']-and$HostResult.content-is[Array]){
            $ids=@(foreach($part in $HostResult.content){
                if($part-isnot[pscustomobject]-or$null-eq$part.PSObject.Properties['type']-or$part.type-cne'text'-or$null-eq$part.PSObject.Properties['text']-or$part.text-isnot[string]){continue}
                try{$value=(ConvertFrom-AiwStrictInputJson $part.text).Value}catch{continue}
                if($value-is[pscustomobject]-and$null-ne$value.PSObject.Properties['threadId']-and$value.threadId-is[string]-and-not[string]::IsNullOrWhiteSpace($value.threadId)){$value.threadId}
            })
            if($ids.Count-eq1){$recipient=$ids[0];if($recipient-ceq$ExpectedRecipient){$outcome='SUCCESS'}else{$outcome='WRONG_RECIPIENT'}}
        }
    }
    [pscustomobject]@{outcome=$outcome;observedRecipient=$recipient;hostAccepted=($outcome-ceq'SUCCESS');recipientWorkProven=$false;userAuthorizationProven=$false}
}
function Get-DeliveryReceiptView($Receipt) {
    if($null-eq$Receipt.PSObject.Properties['binding']){return $Receipt}
    $b=$Receipt.binding
    [pscustomobject]@{taskId=$b.taskId;taskIdentity=$b.taskIdentity;taskOwner=$b.taskOwner;taskActor=$b.taskActor;actor=$b.actor;actionKind=$Receipt.intentEnvelope.requestedActionKind;resultKind=$Receipt.intentEnvelope.requestedResultKind;exactPaths=@($b.exactScope);authorityContext=$b;sourceLocators=[pscustomobject]@{projectRoot=$b.projectRoot;frameworkRoot=$Receipt.sourceLocators.frameworkRoot;taskRelativePath=$Receipt.sourceLocators.taskRelativePath;authorizationPackagePath=$Receipt.sourceLocators.authorizationPackagePath}}
}
function Get-AiwBoundDelivery($Receipt,$Boundary,$Evidence=$null) {
    $r=Get-DeliveryReceiptView $Receipt
    $isReview=$r.actionKind-cin@('REVIEW_ROUTE','REVIEW_EXECUTE')
    if($null-eq$Boundary.PSObject.Properties['deliveryContext']){
        if($isReview){throw 'DELIVERY_CONTEXT_REQUIRED'}
        return $null
    }
    $context=$Boundary.deliveryContext
    $observation=Get-AiwDeliveryObservation $context
    $base=New-AiwEvidenceContext $r.sourceLocators.projectRoot '' $r.sourceLocators.frameworkRoot $r.authorityContext.forbiddenScope
    $package=$null
    if($r.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){
        $package=Read-AiwEvidenceReference $base ([pscustomobject]@{path=$r.sourceLocators.authorizationPackagePath;identity=$r.authorityContext.authorizationIdentity}) -Json
        if($package.owner-cne$r.taskOwner-or$package.taskId-cne$r.taskId-or$package.grantee-cne$r.actor){throw 'DELIVERY_PACKAGE_CONTEXT_DRIFT'}
    }
    $ctx=New-AiwPackageEvidenceContext $r.sourceLocators.projectRoot $package $r.sourceLocators.frameworkRoot $r.authorityContext.forbiddenScope
    $recipient=[string]$r.taskOwner;$reason='TASK_OWNER'
    if($r.taskOwner-ceq'NOT_APPLICABLE'-or$r.actor-ceq$r.taskOwner){$recipient='USER';$reason='CURRENT_USER_RESPONSE'}
    if($r.actionKind-ceq'REVIEW_EXECUTE'){
        if($null-eq$Evidence){$Evidence=Get-AiwBoundaryEvidence $r $Boundary}
        $verdicts=@(for($i=0;$i-lt$Evidence.references.Count;$i++){if($Evidence.references[$i].kind-ceq'REVIEW_VERDICT'){$Evidence.records[$i]}})
        if($verdicts.Count-ne1){throw 'DELIVERY_VERDICT_REQUIRED'}
        $recipient=[string]$package.owner;$reason='REVIEW_TO_OWNER'
        if($verdicts[0].outcome-cin@('CHANGES_REQUESTED','REJECTED')){
            if($null-eq$package.PSObject.Properties['candidateWriter']-or[string]::IsNullOrWhiteSpace($package.candidateWriter)){throw 'DELIVERY_REPAIR_WRITER_REQUIRED'}
            $recipient=[string]$package.candidateWriter;$reason='FINDING_TO_WRITER'
        }
    }elseif($r.actionKind-ceq'REVIEW_ROUTE'){
        $recipient='UNBOUND_RECEIVER';$reason='ROUTE_TO_REVIEWER'
        if($null-ne$package.PSObject.Properties['repairReviewPlan']){$recipient=[string]$package.repairReviewPlan.reviewer}
        if($null-ne$context.PSObject.Properties['reviewPackageRef']){
            $review=Read-AiwEvidenceReference $ctx $context.reviewPackageRef -Json
            foreach($field in @('taskId','taskIdentity','owner','projectConfigIdentity','userConfirmation')){if($review.$field-cne$package.$field){throw 'DELIVERY_REVIEW_PACKAGE_DRIFT'}}
            if($review.actions-isnot[Array]-or$review.actions.Count-ne1-or$review.actions[0]-cne'REVIEW_EXECUTE'-or$review.reviewIndependence-cne'INDEPENDENT'-or$review.candidateWriter-cne$package.grantee){throw 'DELIVERY_REVIEW_PACKAGE_BOUNDARY'}
            if((@($review.exactPaths|Sort-Object)-join"`n")-cne(@($r.exactPaths|Sort-Object)-join"`n")){throw 'DELIVERY_REVIEW_SCOPE_DRIFT'}
            if($review.objectIdentities-isnot[Array]-or(@($review.objectIdentities.path|Sort-Object)-join"`n")-cne(@($r.exactPaths|Sort-Object)-join"`n")){throw 'DELIVERY_REVIEW_CANDIDATE_SET'}
            if($null-ne$review.PSObject.Properties['materialContributors']-and$review.grantee-cin@($review.materialContributors)){throw 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'}
            foreach($candidate in @(Get-AiwPackageCandidateReferences $review)){$null=Read-AiwEvidenceReference $ctx $candidate -Candidate}
            if($recipient-cnotin@('UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')-and$recipient-cne$review.grantee){throw 'DELIVERY_REVIEWER_DRIFT'}
            $recipient=[string]$review.grantee
        }
        if($null-ne$context.PSObject.Properties['reviewerAssignment']){
            $a=$context.reviewerAssignment
            if($null-eq$package.PSObject.Properties['repairReviewPlan']-or$package.repairReviewPlan.reviewer-cne'DEFERRED_VISIBLE_REVIEWER'){throw 'DELIVERY_ASSIGNMENT_NOT_DEFERRED'}
            if((@($a.PSObject.Properties.Name|Sort-Object)-join'|')-cne(@('source','createdBy','threadId','hostId','taskId','parentPackageIdentity'|Sort-Object)-join'|')){throw 'DELIVERY_ASSIGNMENT_FIELDS'}
            if($a.source-cne'HOST_CREATE_THREAD_RESULT'-or$a.createdBy-cne$package.grantee-or$a.taskId-cne$r.taskId-or$a.parentPackageIdentity-cne$r.authorityContext.authorizationIdentity-or[string]::IsNullOrWhiteSpace($a.hostId)){throw 'DELIVERY_ASSIGNMENT_DRIFT'}
            if($recipient-cnotin@('UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')-and$recipient-cne$a.threadId){throw 'DELIVERY_ASSIGNMENT_RECIPIENT_DRIFT'}
            $recipient=[string]$a.threadId
        }
        $excluded=@($package.owner,$package.issuer,$package.grantee)
        if($null-ne$package.PSObject.Properties['repairReviewPlan']){$excluded+=@($package.repairReviewPlan.materialContributors)}
        if([string]::IsNullOrWhiteSpace($recipient)-or$recipient-cin(@('USER','UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')+$excluded)){throw 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'}
    }
    foreach($field in @('reviewPackageRef','reviewerAssignment')){if($r.actionKind-cne'REVIEW_ROUTE'-and$null-ne$context.PSObject.Properties[$field]){throw 'DELIVERY_ROUTE_REFERENCE_UNEXPECTED'}}
    $userDecision='NOT_REQUIRED'
    if($null-ne$context.PSObject.Properties['userDecisionRef']){
        if($Boundary.publicDecisionIdentity-cne$context.userDecisionRef.identity){throw 'DELIVERY_USER_DECISION_UNBOUND'}
        $null=Read-AiwEvidenceReference $ctx $context.userDecisionRef
        $userDecision=$context.userDecisionRef.identity;$recipient='USER';$reason='EXPLICIT_USER_NATIVE_DELIVERY'
    }
    $channel=if($recipient-ceq'USER'){'NATIVE_RESPONSE'}else{'TASK_MESSAGE'}
    if($context.expectedRecipient-cne$recipient-or$context.channel-cne$channel){throw 'DELIVERY_CONSUMER_CHANNEL_MISMATCH'}
    if($context.stage-ceq'OBSERVE'){
        if($context.evidence-cnotmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){throw 'DELIVERY_HOST_REFERENCE_REQUIRED'}
        $hostResult=Read-AiwEvidenceReference $ctx ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) -Json
        $actual=Get-AiwCodexSendOutcome $hostResult $recipient
        if($actual.outcome-ceq'WRONG_RECIPIENT'-or$actual.outcome-cne$context.outcome-or$actual.observedRecipient-cne$context.observedRecipient){throw 'DELIVERY_HOST_RESULT_MISMATCH'}
    }
    [pscustomobject]@{delivery=$observation;consumer=[pscustomobject]@{recipient=$recipient;channel=$channel;reason=$reason;authorizationIdentity=$r.authorityContext.authorizationIdentity;userDecisionIdentity=$userDecision;userAuthorizationProven=$false;recipientWorkProven=$false;evidenceCeiling='INSTRUCTION_BOUND'};closureSatisfied=($channel-ceq'NATIVE_RESPONSE'-or$observation.delivered)}
}
function Invoke-AiwDeliveryBoundary($Reference) {
    if($Reference-isnot[pscustomobject]-or(@($Reference.PSObject.Properties.Name|Sort-Object)-join'|')-cne'identity|path'-or$Reference.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not[IO.Path]::IsPathRooted($Reference.path)){throw 'DELIVERY_BOUNDARY_REFERENCE'}
    $path=[IO.Path]::GetFullPath($Reference.path);$cursor=Get-Item -LiteralPath $path -Force
    while($null-ne$cursor){if($cursor.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'DELIVERY_BOUNDARY_REPARSE'};$cursor=if($cursor-is[IO.FileInfo]){$cursor.Directory}else{$cursor.Parent}}
    $bytes=[IO.File]::ReadAllBytes($path);$id=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if($id-cne$Reference.identity){throw 'DELIVERY_BOUNDARY_DRIFT'}
    $inputValue=(Read-AiwStrictInputJson $path).Value
    if($inputValue.mode-cne'FINALIZE_OUTPUT'-or$null-eq$inputValue.PSObject.Properties['deliveryContext']){throw 'DELIVERY_FINAL_BOUNDARY_REQUIRED'}
    # Reuse the exact current final-boundary validator, including source drift,
    # typed evidence and the same consumer resolver. No second authority model.
    $lines=@(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'resolve-process-requirements.ps1') -InputPath $path -AsJson)
    $value=($lines-join"`n")|ConvertFrom-Json -Depth 70
    $value|Add-Member ackRequired $false;$value|Add-Member polling $false
    return $value
}
Export-ModuleMember -Function Get-AiwCodexSendOutcome,Get-AiwBoundDelivery,Invoke-AiwDeliveryBoundary
