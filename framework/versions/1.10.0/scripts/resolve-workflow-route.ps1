[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-JsonWhitespace([char]$Character) {
    return $Character -eq [char]0x20 -or $Character -eq [char]0x09 -or $Character -eq [char]0x0A -or $Character -eq [char]0x0D
}

function Skip-JsonWhitespace([string]$Text, [ref]$Index) {
    while ($Index.Value -lt $Text.Length -and (Test-JsonWhitespace $Text[$Index.Value])) { $Index.Value++ }
}

function Read-JsonString([string]$Text, [ref]$Index) {
    if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne [char]0x22) { throw 'INPUT_JSON_MEMBER_NAME' }
    $start = $Index.Value
    $cursor = $start + 1
    while ($cursor -lt $Text.Length) {
        $character = $Text[$cursor]
        if ([int]$character -lt 0x20) { throw 'INPUT_JSON_STRING' }
        if ($character -eq [char]0x5C) {
            $cursor++
            if ($cursor -ge $Text.Length) { throw 'INPUT_JSON_STRING' }
            $escape = $Text[$cursor]
            if ($escape -eq [char]0x75) {
                if ($cursor + 4 -ge $Text.Length) { throw 'INPUT_JSON_STRING' }
                for ($offset = 1; $offset -le 4; $offset++) {
                    if ($Text[$cursor + $offset] -notmatch '^[0-9A-Fa-f]$') { throw 'INPUT_JSON_STRING' }
                }
                $cursor += 5
                continue
            }
            if ('"\/bfnrt'.IndexOf($escape) -lt 0) { throw 'INPUT_JSON_STRING' }
            $cursor++
            continue
        }
        if ($character -eq [char]0x22) {
            $cursor++
            $token = $Text.Substring($start,$cursor - $start)
            $Index.Value = $cursor
            try { return [string]($token | ConvertFrom-Json) } catch { throw 'INPUT_JSON_STRING' }
        }
        $cursor++
    }
    throw 'INPUT_JSON_STRING'
}

function Get-JsonTopLevelMemberNames([string]$Text) {
    $index = 0
    Skip-JsonWhitespace $Text ([ref]$index)
    if ($index -ge $Text.Length -or $Text[$index] -ne [char]0x7B) { throw 'INPUT_OBJECT_TYPE' }
    $index++
    Skip-JsonWhitespace $Text ([ref]$index)
    $names = New-Object 'System.Collections.Generic.List[string]'
    if ($index -lt $Text.Length -and $Text[$index] -eq [char]0x7D) {
        $index++
        Skip-JsonWhitespace $Text ([ref]$index)
        if ($index -ne $Text.Length) { throw 'INPUT_JSON' }
        return $names.ToArray()
    }
    while ($index -lt $Text.Length) {
        $name = Read-JsonString $Text ([ref]$index)
        $names.Add($name)
        Skip-JsonWhitespace $Text ([ref]$index)
        if ($index -ge $Text.Length -or $Text[$index] -ne [char]0x3A) { throw 'INPUT_JSON' }
        $index++
        Skip-JsonWhitespace $Text ([ref]$index)
        if ($index -ge $Text.Length) { throw 'INPUT_JSON' }
        if ($Text[$index] -eq [char]0x22) {
            $null = Read-JsonString $Text ([ref]$index)
        } else {
            if ($Text[$index] -eq [char]0x7B -or $Text[$index] -eq [char]0x5B) { throw 'INPUT_JSON_NESTED_VALUE' }
            $valueStart = $index
            while ($index -lt $Text.Length -and $Text[$index] -ne [char]0x2C -and $Text[$index] -ne [char]0x7D -and -not (Test-JsonWhitespace $Text[$index])) { $index++ }
            if ($index -eq $valueStart) { throw 'INPUT_JSON' }
        }
        Skip-JsonWhitespace $Text ([ref]$index)
        if ($index -ge $Text.Length) { throw 'INPUT_JSON' }
        if ($Text[$index] -eq [char]0x2C) {
            $index++
            Skip-JsonWhitespace $Text ([ref]$index)
            continue
        }
        if ($Text[$index] -eq [char]0x7D) {
            $index++
            Skip-JsonWhitespace $Text ([ref]$index)
            if ($index -ne $Text.Length) { throw 'INPUT_JSON' }
            return $names.ToArray()
        }
        throw 'INPUT_JSON'
    }
    throw 'INPUT_JSON'
}

function Read-StrictUtf8Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'INPUT_MISSING' }
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'INPUT_BOM' }
    try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes) } catch { throw 'INPUT_UTF8' }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { throw 'INPUT_TEXT_FORMAT' }
    $memberNames = @(Get-JsonTopLevelMemberNames $text)
    try { $value = $text | ConvertFrom-Json } catch { throw 'INPUT_JSON' }
    return [pscustomobject]@{ MemberNames=[string[]]$memberNames; Value=$value }
}

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

$inputDocument = Read-StrictUtf8Json $InputPath
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
