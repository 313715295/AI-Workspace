[CmdletBinding()]
param(
    [Parameter(Mandatory,ParameterSetName='Path')][string]$InputPath,
    [Parameter(Mandatory,ParameterSetName='Json')][string]$InputJson,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}

Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1') -Force

function Assert-ExactFields($Object, [string[]]$MemberNames, [string[]]$Fields) {
    if (-not ($Object -is [pscustomobject])) { throw 'INPUT_OBJECT_TYPE' }
    $actual = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    if ($actual.Count -ne $Fields.Count) { throw 'INPUT_FIELDS' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($name in $MemberNames) {
        if (-not $seen.Add($name)) { throw "INPUT_FIELD_COUNT|$name" }
        if ($Fields -cnotcontains $name) { throw 'INPUT_FIELDS' }
    }
    if ($MemberNames.Count -ne $Fields.Count) { throw 'INPUT_FIELDS' }
    foreach ($field in $Fields) {
        if ($actual -cnotcontains $field) { throw 'INPUT_FIELDS' }
        if (-not $seen.Contains($field)) { throw 'INPUT_FIELDS' }
    }
}

function Assert-Bool($Value, [string]$Name) {
    if (-not ($Value -is [bool])) { throw "INPUT_BOOL|$Name" }
}

function Assert-String($Value, [string]$Name) {
    if (-not ($Value -is [string]) -or [string]::IsNullOrWhiteSpace([string]$Value)) { throw "INPUT_STRING|$Name" }
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

try {
$inputDocument = if($PSCmdlet.ParameterSetName -ceq 'Json'){ConvertFrom-AiwStrictInputJson $InputJson}else{Read-AiwStrictInputJson $InputPath}
$inputMemberNames = [string[]]@($inputDocument.MemberNames)
$inputObject = $inputDocument.Value
if (-not ($inputObject -is [pscustomobject]) -or $inputObject.PSObject.Properties.Name -cnotcontains 'operation') { throw 'INPUT_OPERATION' }
if (@($inputMemberNames | Where-Object { $_ -ceq 'operation' }).Count -ne 1) { throw 'INPUT_FIELD_COUNT|operation' }
Assert-String $inputObject.operation 'operation'
$operation = [string]$inputObject.operation
$result = $null

switch ($operation) {
    'RUNTIME_MAINTENANCE' {
        Assert-ExactFields $inputObject $inputMemberNames @('operation','projectRoot','admitInputRef','retainedRefs','retainedPaths')
        Assert-String $inputObject.projectRoot 'projectRoot'
        Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1')
        $requestPath=if($PSCmdlet.ParameterSetName-ceq'Path'){[IO.Path]::GetFullPath($InputPath)}else{''}
        $result=Invoke-AiwRuntimeMaintenance $inputObject $requestPath
    }
    'QUALITY_PLAN_PREPARE' {
        Assert-ExactFields $inputObject $inputMemberNames @('operation','schemaVersion','projectRoot','taskPath','expectedTaskIdentity','projectConfigRef','policyRef','subject','requirementsRef')
        if(-not(Test-JsonInteger $inputObject.schemaVersion)-or$inputObject.schemaVersion-ne1){throw 'QUALITY_PREPARE_SCHEMA'}
        Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
        Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
        $evidenceModule=@(Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1') -PassThru)[0]
        $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $inputObject.projectRoot)))
        $framework=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
        $ctx=New-AiwEvidenceContext $root '' $framework
        $config=Read-AiwEvidenceReference $ctx $inputObject.projectConfigRef -Json
        $configFull=Resolve-AiwEvidenceObservationPath $ctx $inputObject.projectConfigRef.path
        if(-not$configFull.Equals((Join-Path $root '.ai-workspace/project.json'),[StringComparison]::OrdinalIgnoreCase)){throw 'QUALITY_CONFIG_REF_CANONICAL'}
        $policy=Read-AiwEvidenceReference $ctx $inputObject.policyRef -Json
        $policyFull=Resolve-AiwEvidenceObservationPath $ctx $inputObject.policyRef.path
        if(-not$policyFull.Equals((Join-Path $root '.ai-workspace/process-policy.json'),[StringComparison]::OrdinalIgnoreCase)){throw 'QUALITY_POLICY_REF_CANONICAL'}
        $taskRelative=[IO.Path]::GetRelativePath($root,[IO.Path]::GetFullPath($inputObject.taskPath,$root)).Replace('\','/')
        if($taskRelative-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'){throw 'QUALITY_ACTIVE_TASK_REQUIRED'}
        $task=Read-AiwControlTransitionTask $root $taskRelative
        if($task.Identity-cne$inputObject.expectedTaskIdentity){throw 'QUALITY_TASK_DRIFT'}
        $profile=[regex]::Match($task.Text,'(?m)^- Range summary:\s*profile=(MICRO|STANDARD|CRITICAL);').Groups[1].Value
        $owner=[regex]::Match($task.Text,'(?m)^- Owner:\s*([^\s]+)\s*$').Groups[1].Value
        if(-not$profile-or-not$owner-or$task.Text-cmatch'(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;'){throw 'QUALITY_ACTIVE_TASK_REQUIRED'}
        $null=Invoke-ProcessRequirementComposition -ProjectRoot $root -FrameworkRoot $framework -TargetVersion $config.frameworkVersion -ExpectedProjectConfigIdentity $inputObject.projectConfigRef.identity -ExpectedCorrectionsIdentity $(if([IO.File]::Exists((Join-Path $root '.ai-workspace/corrections.json'))){Get-AiwFileIdentity (Join-Path $root '.ai-workspace/corrections.json')}else{'MISSING'}) -Profile $profile -Role TASK_OWNER -Phase PLAN -Actor $owner -TaskIdentity $task.Identity -Objective 'Prepare stable finite outcome quality plan without authority or persistence' -ActionKind NONE -ResultKind PLAN -ExactPaths @() -UseDeclaredCapabilities -ValidateCompleteAdoptedSet
        $selection=Get-AiwQualitySelection $policy $inputObject.policyRef.identity $profile $inputObject.subject
        if($selection.mode-ceq'LEGACY'){$result=[ordered]@{status='READY';authorityGranted=$false;mode='LEGACY';plan=$null;limits=@('No policy qualityAssurance is enabled; original LEGACY gates apply.')} ;break}
        $repo=$inputObject.subject.repositoryId
        if($config.controlPlaneLayout-ceq'repo-local'){
            Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
            $execution=Resolve-AiwExecutionTargetContext -ProjectRoot $root -ProjectId $config.id -TaskPath $taskRelative
            if($execution.targetKind-ceq'GIT_WORKTREE'){
                if($repo-cne'PROJECT'){throw 'QUALITY_SUBJECT_REPOSITORY_DRIFT'}
                $package=[pscustomobject]@{schemaVersion=4;repositoryId='PROJECT';controlRoot=$root;executionTargetRef=$execution.executionTargetRef;expectedTargetState=(Get-AiwExecutionTargetState $execution)}
            }else{
                if($repo-cne'REPO_LOCAL'){throw 'QUALITY_SUBJECT_REPOSITORY_DRIFT'}
                $package=[pscustomobject]@{schemaVersion=1}
            }
        }elseif($config.controlPlaneLayout-ceq'framework-maintenance-sibling'){
            if($repo-cne'CONTROL'-and$repo-cne$config.frameworkTarget.repositoryId){throw 'QUALITY_SUBJECT_REPOSITORY_DRIFT'}
            $package=[pscustomobject]@{schemaVersion=2;repositoryId=$repo}
        }else{throw 'QUALITY_PREPARE_EXECUTION_TARGET_UNSUPPORTED'}
        $subjectContext=New-AiwPackageEvidenceContext $root $package $framework -TaskPath $taskRelative
        foreach($path in $inputObject.subject.exactPaths){$null=& $evidenceModule {param($c,$p) Resolve-EvPath $c $p -Candidate -AllowMissing} $subjectContext $path}
        $requirementsFull=Resolve-AiwEvidenceObservationPath $ctx $inputObject.requirementsRef.path
        if($requirementsFull.Equals($policyFull,[StringComparison]::OrdinalIgnoreCase)-or$requirementsFull.Equals($task.Path,[StringComparison]::OrdinalIgnoreCase)-or$requirementsFull.Replace('\','/')-cmatch'/\.ai-workspace/tasks/'){throw 'QUALITY_IMMUTABLE_REQUIREMENTS_REQUIRED'}
        $null=& $evidenceModule {param($c,$r) Read-EvRef $c $r -Section} $ctx $inputObject.requirementsRef
        $stages=@();$preceding=@()
        foreach($kind in $selection.effectiveStages){
            $id='quality-'+$kind.ToLowerInvariant().Replace('_','-')
            $stages+=[pscustomobject]@{id=$id;kind=$kind;requiredBy=$inputObject.requirementsRef;dependsOn=@($preceding);candidateRef=@();evidenceRefs=@()}
            $preceding+=@($id)
        }
        $result=[ordered]@{status='READY';authorityGranted=$false;mode='EXPLICIT';effectiveStages=$selection.effectiveStages;qualityBinding=$selection.qualityBinding;plan=[ordered]@{schemaVersion=2;qualityBinding=$selection.qualityBinding;stages=$stages};limits=@('Read-only candidate; original CONTROL authorization must bind the task.','Owner must retain real user/professional stages and dependencies.','Pending candidate/evidence arrays do not satisfy Review, acceptance or SUCCESS.','No SELF, verdict, acceptance or permission is generated.')}
    }

    'REPAIR_REVIEW' {
        Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1') -Force
        $fields=@('operation','repositoryRoot','binding')
        $explicitControl=$null-ne$inputObject.PSObject.Properties['controlRoot'];$explicitTask=$null-ne$inputObject.PSObject.Properties['taskPath']
        if($explicitControl-ne$explicitTask){throw 'REPAIR_REVIEW_CONTROL_TASK_PAIR_REQUIRED'}
        if($explicitControl){$fields+=@('controlRoot','taskPath')}
        Assert-ExactFields $inputObject $inputMemberNames $fields
        $binding=$inputObject.binding
        $parentDoc=Read-AiwStrictInputJson $binding.parentPackagePath
        $bytes=[IO.File]::ReadAllBytes($binding.parentPackagePath)
        $identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        if($identity-cne$binding.parentPackageIdentity){throw 'REPAIR_REVIEW_PARENT_DRIFT'}
        $candidate=$parentDoc.Value
        if($null-eq$candidate.PSObject.Properties['repairReviewPlan']-or$binding.phase-cnotin@('INITIAL_REVIEW','REPAIR','REREVIEW')){throw 'REPAIR_REVIEW_PLAN_REQUIRED'}
        $plan=$candidate.repairReviewPlan
        $parent=$candidate|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $null=@(Get-AiwReviewExcludedActors $candidate.owner $candidate.issuer $plan.writer $plan.materialContributors)
        if($candidate.schemaVersion-eq4-and-not$explicitControl){throw 'REPAIR_REVIEW_CONTROL_TASK_PAIR_REQUIRED'}
        $writeScope=@($candidate.exactPaths)
        $reviewScope=@(Get-AiwPlannedReviewScope $candidate)
        # A child is anchored to the original through repairReviewBinding. Its
        # parent-only receiver binding cannot be reused by another grantee.
        $candidate.PSObject.Properties.Remove('receiverBinding')
        $reviewerActor=[string]$plan.reviewer
        if($reviewerActor-ceq'DEFERRED_VISIBLE_REVIEWER'){
            if($null-eq$binding.PSObject.Properties['reviewerAssignment']){throw 'REVIEWER_ASSIGNMENT_REQUIRED'}
            $assignment=$binding.reviewerAssignment
            Assert-ExactFields $assignment @($assignment.PSObject.Properties.Name) @('source','createdBy','threadId','hostId','taskId','parentPackageIdentity')
            foreach($name in @('source','createdBy','threadId','hostId','taskId','parentPackageIdentity')){Assert-String $assignment.$name $name}
            $hostAssigned=$assignment.source-ceq'HOST_CREATE_THREAD_RESULT'
            $initialDelegation=$assignment.source-ceq'HOST_INITIAL_DELEGATION'-and(($assignment.threadId-ceq'UNBOUND_RECEIVER'-and$binding.phase-ceq'INITIAL_REVIEW')-or($assignment.threadId-cne'UNBOUND_RECEIVER'-and$binding.phase-cin@('REPAIR','REREVIEW')))
            if(-not($hostAssigned-or$initialDelegation)-or$assignment.createdBy-cne$plan.writer-or$assignment.taskId-cne$candidate.taskId-or$assignment.parentPackageIdentity-cne$identity-or$assignment.threadId-cin@($candidate.owner,$candidate.issuer,$plan.writer)-or$assignment.threadId-cin@($plan.materialContributors)){throw 'REVIEWER_ASSIGNMENT_BINDING'}
            $reviewerActor=[string]$assignment.threadId
        }elseif($null-ne$binding.PSObject.Properties['reviewerAssignment']){throw 'REVIEWER_ASSIGNMENT_UNEXPECTED'}
        $candidate.PSObject.Properties.Remove('repairReviewPlan')
        $candidate.grantee=if($binding.phase-ceq'REPAIR'){$plan.writer}else{$reviewerActor}
        if($binding.phase-cin@('INITIAL_REVIEW','REREVIEW')){
            $candidate.PSObject.Properties.Remove('continuationPlan')
            $candidate.PSObject.Properties.Remove('selfCheckRepairLimit')
            $candidate.actions=@('REVIEW_EXECUTE');$candidate.reviewIndependence='INDEPENDENT'
            if('CONTRIBUTOR_SET_CHANGE'-cnotin$candidate.invalidatesOn){$candidate.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE')}
            $candidate|Add-Member candidateWriter $plan.writer
            $candidate|Add-Member materialContributors @($plan.materialContributors)
        }
        $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($inputObject.repositoryRoot))
        if($explicitControl){
            $evidenceContext=New-AiwEvidenceContext $inputObject.controlRoot '' ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..')))
            $scopeInputRef=if($binding.phase-ceq'REPAIR'){[pscustomobject]@{path=$binding.verdictFinalizeInputPath;identity=$binding.verdictFinalizeInputIdentity}}else{[pscustomobject]@{path=$binding.repairFinalizeInputPath;identity=$binding.repairFinalizeInputIdentity}}
            $scopeInput=Read-AiwEvidenceReference $evidenceContext $scopeInputRef -Json
            $scopeSource=Read-AiwEvidenceReference $evidenceContext ([pscustomobject]@{path=$scopeInput.discoverReceiptPath;identity=$scopeInput.expectedDiscoverReceiptIdentity}) -Json
            $scopeAuthority=if($scopeSource.schemaVersion-eq1){$scopeSource.authorityContext}else{$scopeSource.binding}
            if($scopeAuthority.projectRoot-cne$inputObject.controlRoot-or$scopeAuthority.taskIdentity-cne$parent.taskIdentity){throw 'REPAIR_REVIEW_CONTROL_AUTHORITY_DRIFT'}
            $evidenceContext=New-AiwPackageEvidenceContext $inputObject.controlRoot $parent ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))) $scopeAuthority.forbiddenScope -TaskPath $inputObject.taskPath -ProtectedPaths $scopeAuthority.protectedScope
            if($evidenceContext.RepositoryRoot-cne$root){throw 'REPAIR_REVIEW_OBJECT_ROOT_DRIFT'}
        }else{$evidenceContext=New-AiwEvidenceContext (Get-Location).Path $root ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..')))}
        if($binding.phase-ceq'REPAIR'){
            $null=Assert-AiwFinalizedReviewFinding $evidenceContext $parent $binding
            $verdict=Read-AiwEvidenceReference $evidenceContext ([pscustomobject]@{path=$binding.verdictPath;identity=$binding.verdictIdentity}) -Json
            if(@($verdict.findingPaths|Where-Object{$_-cnotin$writeScope}).Count){throw 'REPAIR_REVIEW_FINDING_OUTSIDE_WRITE_SCOPE'}
            # Repair preimages come from the original finding, not a new live
            # snapshot that could silently accept a third-party change.
            $candidate.objectIdentities=@($verdict.objectIdentities|Where-Object{$_.path-cin$writeScope})
            if($candidate.objectIdentities.Count-ne$writeScope.Count){throw 'REPAIR_REVIEW_PRODUCTION_SCOPE_DRIFT'}
        }else{
            $finalInput=Read-AiwEvidenceReference $evidenceContext ([pscustomobject]@{path=$binding.repairFinalizeInputPath;identity=$binding.repairFinalizeInputIdentity}) -Json
            $finalResult=Read-AiwEvidenceReference $evidenceContext ([pscustomobject]@{path=$binding.repairFinalizeResultPath;identity=$binding.repairFinalizeResultIdentity}) -Json
            if($finalInput.mode-cne'FINALIZE_OUTPUT'-or$finalResult.mode-cne'FINALIZE_OUTPUT'-or$finalResult.status-cne'PASS'){throw 'REPAIR_REVIEW_FINALIZE_REQUIRED'}
            $source=Read-AiwEvidenceReference $evidenceContext ([pscustomobject]@{path=$finalInput.discoverReceiptPath;identity=$finalInput.expectedDiscoverReceiptIdentity}) -Json
            $sourceContext=if($source.schemaVersion-eq1){$source.authorityContext}else{$source.binding}
            $sourceAction=if($source.schemaVersion-eq1){$source.actionKind}else{$source.intentEnvelope.requestedActionKind}
            $producer=Read-AiwEvidenceReference $evidenceContext ([pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$sourceContext.authorizationIdentity}) -Json
            $projectRoot=if($source.schemaVersion-eq1){$source.sourceLocators.projectRoot}else{$sourceContext.projectRoot}
            $evidenceContext=New-AiwPackageEvidenceContext $projectRoot $producer $source.sourceLocators.frameworkRoot $sourceContext.forbiddenScope -TaskPath $source.sourceLocators.taskRelativePath -ProtectedPaths $sourceContext.protectedScope
            if($producer.grantee-cne$plan.writer-or$sourceAction-cnotin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN','CONTROL_WRITE')-or
               (@($producer.exactPaths|Sort-Object)-join'|')-cne(@($writeScope|Sort-Object)-join'|')){throw 'REPAIR_REVIEW_PRODUCTION_SCOPE_DRIFT'}
            $postimages=@(Get-AiwFinalizedObjectPostimages $finalInput $writeScope)
            if($sourceAction-ceq'TEST_RUN'){
                Assert-AiwReviewSelfCheck $evidenceContext $finalInput.evidenceRefs $producer.taskId @(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=$postimages}))
            }
            if($binding.phase-ceq'REREVIEW'){
                foreach($field in @('verdictFinalizeInputPath','verdictFinalizeInputIdentity','verdictFinalizeResultPath','verdictFinalizeResultIdentity')){if($null-eq$binding.PSObject.Properties[$field]-or$null-eq$producer.repairReviewBinding.PSObject.Properties[$field]-or$binding.$field-cne$producer.repairReviewBinding.$field){throw 'REPAIR_REVIEW_VERDICT_FINALIZE_LINK_DRIFT'}}
                $null=Assert-AiwFinalizedReviewFinding $evidenceContext $parent $binding -FrozenCandidates
            }
            if($candidate.schemaVersion-eq4){
                if($null-eq$finalResult.PSObject.Properties['postTargetState']){throw 'REPAIR_REVIEW_PRODUCTION_TARGET_STATE_REQUIRED'}
                $candidate.expectedTargetState=$finalResult.postTargetState
            }
            $candidate.exactPaths=@($reviewScope.path)
            $candidate.objectIdentities=@(Get-AiwComposedReviewCandidate $evidenceContext $producer $postimages)
        }
        $candidate|Add-Member repairReviewBinding $binding
        $result=[ordered]@{status='PREPARED';authorityGranted=$false;requiresCurrentAdmission=$true;package=$candidate}
    }
    'DELIVERY' {
        Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -Force
        if($null-ne$inputObject.PSObject.Properties['boundaryInputRef']){
            Assert-ExactFields $inputObject $inputMemberNames @('operation','boundaryInputRef')
            Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1') -Force
            $result=Invoke-AiwDeliveryBoundary $inputObject.boundaryInputRef
        }else{
            Assert-ExactFields $inputObject $inputMemberNames @('operation','deliveryContext')
            $result=Get-AiwDeliveryObservation $inputObject.deliveryContext
            $result|Add-Member consumerBound $false
            $result|Add-Member userAuthorizationProven $false
        }
    }
    'LAUNCH' {
        Assert-ExactFields $inputObject $inputMemberNames @('operation','recoveryComplete','packageValid','bindingsMatch')
        Assert-Bool $inputObject.recoveryComplete 'recoveryComplete'
        Assert-Bool $inputObject.packageValid 'packageValid'
        Assert-Bool $inputObject.bindingsMatch 'bindingsMatch'
        $ready = [bool]$inputObject.recoveryComplete -and [bool]$inputObject.packageValid -and [bool]$inputObject.bindingsMatch
        $result = [ordered]@{
            operation = $operation
            status = $(if ($ready) { 'IMPLEMENTATION_READY' } else { 'RECOVERY_READY' })
            writerActive = $ready
            recoveryIsAuthority = $false
        }
    }
    'ROUTE' {
        $rootField=if($inputMemberNames -ccontains 'cwdProjectRootMatch'){'cwdProjectRootMatch'}else{'cwdGitTopMatch'}
        $fields = @('operation','projectMatch',$rootField,'outcomeMatch','taskOwnerMatch','actorEligible','lineageMatch','resourceRouteAvailable','protectionBoundaryMatch','gitDeviceExternalMatch','publicDecisionMatch','requiresDistinctOutcome','requiresIndependentContext','standingCreateAuthorized')
        Assert-ExactFields $inputObject $inputMemberNames $fields
        foreach ($field in $fields[1..($fields.Count - 1)]) { Assert-Bool $inputObject.$field $field }
        $boundaryMatch = [bool]$inputObject.projectMatch -and [bool]$inputObject.$rootField -and [bool]$inputObject.taskOwnerMatch -and
            [bool]$inputObject.actorEligible -and [bool]$inputObject.lineageMatch -and [bool]$inputObject.protectionBoundaryMatch -and
            [bool]$inputObject.gitDeviceExternalMatch -and [bool]$inputObject.publicDecisionMatch
        if (-not $boundaryMatch) {
            $decision = 'BLOCKED'
            $standingCreate = $false
            if (-not [bool]$inputObject.$rootField) { $reason = $(if($rootField-ceq'cwdGitTopMatch'){'CWD_GIT_TOP_MISMATCH'}else{'CWD_PROJECT_ROOT_MISMATCH'}) }
            elseif (-not [bool]$inputObject.publicDecisionMatch) { $reason = 'PUBLIC_DECISION_MISMATCH' }
            elseif (-not [bool]$inputObject.taskOwnerMatch) { $reason = 'TASK_OWNER_MISMATCH' }
            elseif (-not [bool]$inputObject.actorEligible) { $reason = 'ACTOR_NOT_ELIGIBLE' }
            else { $reason = 'BOUNDARY_MISMATCH' }
        }
        elseif ([bool]$inputObject.requiresDistinctOutcome -or -not [bool]$inputObject.outcomeMatch -or
            [bool]$inputObject.requiresIndependentContext -or -not [bool]$inputObject.resourceRouteAvailable) {
            $decision = 'MUST_NEW'
            $standingCreate = [bool]$inputObject.standingCreateAuthorized
            if (-not [bool]$inputObject.resourceRouteAvailable) { $reason = 'RESOURCE_ROUTE_REQUIRES_NEW_CONTEXT' }
            elseif ([bool]$inputObject.requiresIndependentContext) { $reason = 'INDEPENDENT_CONTEXT_REQUIRED' }
            else { $reason = $(if ($standingCreate) { 'STANDING_CREATE_AUTHORIZED' } else { 'CREATE_AUTHORIZATION_REQUIRED' }) }
        }
        else {
            $decision = 'REUSE'
            $standingCreate = $false
            $reason = 'SAME_AUTHORITY_AND_OUTCOME'
        }
        $result = [ordered]@{ operation=$operation; decision=$decision; reason=$reason; standingCreate=$standingCreate }
    }
    'TERMINAL' {
        Assert-ExactFields $inputObject $inputMemberNames @('operation','boundaryInputRef')
        Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1') -Force
        $result=Invoke-AiwDeliveryBoundary $inputObject.boundaryInputRef
    }
    'MESSAGE' {
        $fields = @('operation','hostAuthenticated','expectedTaskId','observedTaskId','expectedSender','observedSender','expectedControllerEpoch','observedControllerEpoch','expectedEnvelope','observedEnvelope')
        Assert-ExactFields $inputObject $inputMemberNames $fields
        Assert-Bool $inputObject.hostAuthenticated 'hostAuthenticated'
        foreach ($field in @('expectedTaskId','observedTaskId','expectedSender','observedSender','expectedEnvelope','observedEnvelope')) { Assert-String $inputObject.$field $field }
        foreach ($field in @('expectedControllerEpoch','observedControllerEpoch')) { if (-not (Test-JsonInteger $inputObject.$field) -or [int64]$inputObject.$field -lt 1) { throw "INPUT_INTEGER|$field" } }
        $matches = [string]$inputObject.expectedTaskId -ceq [string]$inputObject.observedTaskId -and
            [string]$inputObject.expectedSender -ceq [string]$inputObject.observedSender -and
            [int64]$inputObject.expectedControllerEpoch -eq [int64]$inputObject.observedControllerEpoch -and
            [string]$inputObject.expectedEnvelope -ceq [string]$inputObject.observedEnvelope
        if (-not [bool]$inputObject.hostAuthenticated) { $status='REJECT'; $reason='HOST_AUTHENTICITY_UNAVAILABLE' }
        elseif (-not $matches) { $status='REJECT'; $reason='STALE_OR_MISROUTED_ENVELOPE' }
        else { $status='ACCEPT'; $reason='HOST_ENVELOPE_MATCH' }
        $result = [ordered]@{ operation=$operation; status=$status; reason=$reason }
    }
    'HANDOFF' {
        $fields = @('operation','predecessorControllerId','successorControllerId','previousEpoch','newEpoch','controllerWrittenLast','controllerState','takeoverRecorded','retirementAuthorized')
        Assert-ExactFields $inputObject $inputMemberNames $fields
        foreach ($field in @('predecessorControllerId','successorControllerId','controllerState')) { Assert-String $inputObject.$field $field }
        foreach ($field in @('previousEpoch','newEpoch')) { if (-not (Test-JsonInteger $inputObject.$field) -or [int64]$inputObject.$field -lt 1) { throw "INPUT_INTEGER|$field" } }
        foreach ($field in @('controllerWrittenLast','takeoverRecorded','retirementAuthorized')) { Assert-Bool $inputObject.$field $field }
        $valid = [string]$inputObject.predecessorControllerId -cne [string]$inputObject.successorControllerId -and
            [int64]$inputObject.newEpoch -eq ([int64]$inputObject.previousEpoch + 1) -and [bool]$inputObject.controllerWrittenLast -and
            [string]$inputObject.controllerState -ceq 'CURRENT' -and [bool]$inputObject.takeoverRecorded
        $result = [ordered]@{
            operation = $operation
            status = $(if ($valid) { 'TAKEOVER_COMPLETE' } else { 'REJECT' })
            reason = $(if ($valid) { 'HANDOFF_BOUNDARIES_CLOSED' } else { 'INVALID_HANDOFF' })
            readOnlyGrace = $valid
            retired = $valid -and [bool]$inputObject.retirementAuthorized
        }
    }
    'HOT_STATE' {
        $fields = @('operation','currentCardCurrentOnly','supersededHistoryArchived','taskLifecycleChanged','routingChanged','stableProjectPhaseChanged','longLivedOwnerChanged','protectedSetChanged','uniqueNextActionChanged','routineActorChanged')
        Assert-ExactFields $inputObject $inputMemberNames $fields
        foreach ($field in $fields[1..($fields.Count - 1)]) { Assert-Bool $inputObject.$field $field }
        $valid = [bool]$inputObject.currentCardCurrentOnly -and [bool]$inputObject.supersededHistoryArchived
        $result = [ordered]@{
            operation = $operation
            status = $(if ($valid) { 'ACCEPT' } else { 'REJECT' })
            reason = $(if ($valid) { 'LAYERED_HOT_STATE' } else { 'ACTIVE_ARCHIVE_BOUNDARY_INVALID' })
            taskCardUpdate = $valid -and ([bool]$inputObject.taskLifecycleChanged -or [bool]$inputObject.routingChanged -or [bool]$inputObject.uniqueNextActionChanged -or [bool]$inputObject.routineActorChanged)
            taskIndexUpdate = $valid -and ([bool]$inputObject.taskLifecycleChanged -or [bool]$inputObject.routingChanged)
            statusUpdate = $valid -and ([bool]$inputObject.stableProjectPhaseChanged -or [bool]$inputObject.longLivedOwnerChanged -or [bool]$inputObject.protectedSetChanged -or [bool]$inputObject.uniqueNextActionChanged)
        }
    }
    default { throw 'INPUT_OPERATION_UNSUPPORTED' }
}

if ($AsJson) { Write-Output ($result | ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii) }
else {
    if ($result -is [System.Collections.IDictionary]) {
        foreach ($entry in $result.GetEnumerator()) { Write-Output ($entry.Key + '=' + [string]$entry.Value) }
    } else {
        foreach ($entry in $result.PSObject.Properties) { Write-Output ($entry.Name + '=' + [string]$entry.Value) }
    }
}
} catch {
    if(-not$AsJson){throw}
    Write-Output ([ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii)
    exit 2
}
