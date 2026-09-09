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

$inputDocument = if($PSCmdlet.ParameterSetName -ceq 'Json'){ConvertFrom-AiwStrictInputJson $InputJson}else{Read-AiwStrictInputJson $InputPath}
$inputMemberNames = [string[]]@($inputDocument.MemberNames)
$inputObject = $inputDocument.Value
if (-not ($inputObject -is [pscustomobject]) -or $inputObject.PSObject.Properties.Name -cnotcontains 'operation') { throw 'INPUT_OPERATION' }
if (@($inputMemberNames | Where-Object { $_ -ceq 'operation' }).Count -ne 1) { throw 'INPUT_FIELD_COUNT|operation' }
Assert-String $inputObject.operation 'operation'
$operation = [string]$inputObject.operation
$result = $null

switch ($operation) {
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
        $fields = @('operation','projectMatch','cwdGitTopMatch','outcomeMatch','taskOwnerMatch','actorEligible','lineageMatch','resourceRouteAvailable','protectionBoundaryMatch','gitDeviceExternalMatch','publicDecisionMatch','requiresDistinctOutcome','requiresIndependentContext','standingCreateAuthorized')
        Assert-ExactFields $inputObject $inputMemberNames $fields
        foreach ($field in $fields[1..($fields.Count - 1)]) { Assert-Bool $inputObject.$field $field }
        $boundaryMatch = [bool]$inputObject.projectMatch -and [bool]$inputObject.cwdGitTopMatch -and [bool]$inputObject.taskOwnerMatch -and
            [bool]$inputObject.actorEligible -and [bool]$inputObject.lineageMatch -and [bool]$inputObject.protectionBoundaryMatch -and
            [bool]$inputObject.gitDeviceExternalMatch -and [bool]$inputObject.publicDecisionMatch
        if (-not $boundaryMatch) {
            $decision = 'BLOCKED'
            $standingCreate = $false
            if (-not [bool]$inputObject.cwdGitTopMatch) { $reason = 'CWD_GIT_TOP_MISMATCH' }
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
        Assert-ExactFields $inputObject $inputMemberNames @('operation','terminalStatus','reportChannelAvailable','proposedConsumerRole','controllerEscalationRequired')
        Assert-String $inputObject.terminalStatus 'terminalStatus'
        if ([string]$inputObject.terminalStatus -cnotin @('READY','COMPLETE','BLOCKED','RANGE_GATE_REQUIRED','PROTECTED_EXCEPTION')) { throw 'INPUT_TERMINAL_STATUS' }
        Assert-Bool $inputObject.reportChannelAvailable 'reportChannelAvailable'
        Assert-String $inputObject.proposedConsumerRole 'proposedConsumerRole'
        if ([string]$inputObject.proposedConsumerRole -cnotin @('TASK_OWNER','INDEPENDENT_REVIEWER','EXECUTOR','USER','CONTROLLER','NONE')) { throw 'INPUT_CONSUMER_ROLE' }
        Assert-Bool $inputObject.controllerEscalationRequired 'controllerEscalationRequired'
        $available = [bool]$inputObject.reportChannelAvailable
        $unnecessaryControllerRelay = [string]$inputObject.proposedConsumerRole -ceq 'CONTROLLER' -and -not [bool]$inputObject.controllerEscalationRequired
        $result = [ordered]@{
            operation = $operation
            status = $(if (-not $available) { 'REPORT_CHANNEL_UNAVAILABLE' } elseif ($unnecessaryControllerRelay) { 'REJECT' } else { [string]$inputObject.terminalStatus })
            delivery = $(if (-not $available) { 'UNAVAILABLE' } elseif ($unnecessaryControllerRelay) { 'REJECTED' } else { 'PROACTIVE' })
            reason = $(if (-not $available) { 'REPORT_CHANNEL_UNAVAILABLE' } elseif ($unnecessaryControllerRelay) { 'UNNECESSARY_CONTROLLER_RELAY' } else { 'DIRECT_CONSUMER_ROUTE' })
            ackRequired = $false
            polling = $false
        }
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

if ($AsJson) { Write-Output ($result | ConvertTo-Json -Depth 8 -Compress) }
else {
    foreach ($entry in $result.GetEnumerator()) { Write-Output ($entry.Key + '=' + [string]$entry.Value) }
}
