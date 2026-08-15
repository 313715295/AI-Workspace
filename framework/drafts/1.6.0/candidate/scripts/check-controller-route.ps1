[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ControllerControlPath,

    [string]$RoutePath,

    [string]$OriginalEnvelopePath,

    [string]$ObservedOriginalEnvelopeIdentity,

    [string]$CurrentTaskPath,

    [string]$PreviousControllerControlPath,

    [string]$RotationPath,

    [string[]]$SeenStateKey = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Fail([string]$Reason) {
    Write-Output "FAIL|$Reason"
    exit 2
}

function Read-StrictJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail 'JSON_NOT_FOUND' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Fail 'TEXT_BOM' }
    try { $text = $utf8Strict.GetString($bytes) } catch { Fail 'TEXT_UTF8' }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { Fail 'TEXT_STRICT' }
    try { $value = $text | ConvertFrom-Json } catch { Fail 'JSON_INVALID' }
    $sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','')
    return [pscustomobject]@{ Value = $value; Text = $text; Bytes = $bytes; Identity = "$($bytes.Length)|$sha" }
}

function Read-StrictText([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail 'TEXT_NOT_FOUND' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Fail 'TEXT_BOM' }
    try { $text = $utf8Strict.GetString($bytes) } catch { Fail 'TEXT_UTF8' }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { Fail 'TEXT_STRICT' }
    $sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','')
    return [pscustomobject]@{ Text = $text; Identity = "$($bytes.Length)|$sha" }
}

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cne $Path.Trim()) { Fail 'LOCATOR_INVALID' }
    $value = $Path.Replace('\','/')
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/') -or
        -not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { Fail 'LOCATOR_INVALID' }
    foreach ($part in $value.Split('/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ')) { Fail 'LOCATOR_INVALID' }
    }
    return $value
}

function Assert-LocatorMatchesPath([string]$Locator, [string]$Path, [string]$Failure) {
    $normalized = Normalize-RelativePath $Locator
    $full = [IO.Path]::GetFullPath($Path).Replace('\','/')
    if (-not ($full.EndsWith('/' + $normalized, [StringComparison]::OrdinalIgnoreCase) -or
        $full.Equals($normalized, [StringComparison]::OrdinalIgnoreCase))) { Fail $Failure }
}

function Is-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Require-String($Object, [string]$Name) {
    if ($Object.PSObject.Properties.Name -notcontains $Name -or -not ($Object.$Name -is [string]) -or
        [string]::IsNullOrWhiteSpace([string]$Object.$Name)) { Fail "FIELD_${Name}_STRING" }
    return [string]$Object.$Name
}

function Get-Controller([string]$Path) {
    $read = Read-StrictJson $Path
    $controller = $read.Value
    $names = @($controller.PSObject.Properties.Name)
    $required = @('schemaVersion','projectId','controllerId','controllerEpoch','state')
    if (@(Compare-Object -ReferenceObject $required -DifferenceObject $names -CaseSensitive).Count -ne 0) { Fail 'CONTROLLER_FIELDS' }
    if (-not (Is-JsonInteger $controller.schemaVersion) -or [int64]$controller.schemaVersion -ne 1) { Fail 'CONTROLLER_SCHEMA_VERSION' }
    $projectId = Require-String $controller 'projectId'
    $controllerId = Require-String $controller 'controllerId'
    if ($projectId -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { Fail 'CONTROLLER_PROJECT_ID' }
    if ($controllerId -cne $controllerId.Trim() -or $controllerId.Length -gt 256) { Fail 'CONTROLLER_ID' }
    if (-not (Is-JsonInteger $controller.controllerEpoch) -or [int64]$controller.controllerEpoch -lt 1) { Fail 'CONTROLLER_EPOCH' }
    if (-not ($controller.state -is [string]) -or [string]$controller.state -cne 'CURRENT') { Fail 'CONTROLLER_STATE' }
    $ordered = [ordered]@{
        schemaVersion = 1
        projectId = $projectId
        controllerId = $controllerId
        controllerEpoch = [int64]$controller.controllerEpoch
        state = 'CURRENT'
    }
    $canonical = ($ordered | ConvertTo-Json -Compress) + "`n"
    if ($read.Text -cne $canonical) { Fail 'CONTROLLER_NOT_CANONICAL' }
    $sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($read.Bytes)).Replace('-','')
    return [pscustomobject]@{
        ProjectId = $projectId
        ControllerId = $controllerId
        Epoch = [int64]$controller.controllerEpoch
        Identity = "$($read.Bytes.Length)|$sha"
    }
}

$current = Get-Controller $ControllerControlPath

if (-not [string]::IsNullOrWhiteSpace($PreviousControllerControlPath) -or -not [string]::IsNullOrWhiteSpace($RotationPath)) {
    if ([string]::IsNullOrWhiteSpace($PreviousControllerControlPath) -or [string]::IsNullOrWhiteSpace($RotationPath)) { Fail 'ROTATION_INPUT_PAIR' }
    $previous = Get-Controller $PreviousControllerControlPath
    $rotation = (Read-StrictJson $RotationPath).Value
    foreach ($field in @('schemaVersion','projectId','previousControllerId','previousControllerEpoch','previousControlIdentity','successorControllerId','successorControllerEpoch','successorControlIdentity','successorAcceptance','pointerCommit','exceptionTargetsRebound','oldNewTaskEntry','oldGrace','legacyAuthorizationDisposition')) {
        if ($rotation.PSObject.Properties.Name -notcontains $field) { Fail "ROTATION_FIELD_MISSING_$field" }
    }
    if (-not (Is-JsonInteger $rotation.schemaVersion) -or [int64]$rotation.schemaVersion -ne 1) { Fail 'ROTATION_SCHEMA_VERSION' }
    if (-not ($rotation.pointerCommit -is [bool]) -or -not [bool]$rotation.pointerCommit) { Fail 'ROTATION_POINTER_NOT_COMMITTED' }
    if (-not ($rotation.exceptionTargetsRebound -is [bool]) -or -not [bool]$rotation.exceptionTargetsRebound) { Fail 'ROTATION_EXCEPTION_TARGETS_NOT_REBOUND' }
    if ([string]$rotation.projectId -cne $current.ProjectId -or $previous.ProjectId -cne $current.ProjectId) { Fail 'ROTATION_PROJECT_DRIFT' }
    if ([string]$rotation.previousControllerId -cne $previous.ControllerId -or [int64]$rotation.previousControllerEpoch -ne $previous.Epoch -or [string]$rotation.previousControlIdentity -cne $previous.Identity) { Fail 'ROTATION_PREVIOUS_DRIFT' }
    if ([string]$rotation.successorControllerId -cne $current.ControllerId -or [int64]$rotation.successorControllerEpoch -ne $current.Epoch -or [string]$rotation.successorControlIdentity -cne $current.Identity) { Fail 'ROTATION_SUCCESSOR_DRIFT' }
    if ($current.Epoch -ne ($previous.Epoch + 1) -or $current.ControllerId -ceq $previous.ControllerId) { Fail 'ROTATION_EPOCH_NOT_MONOTONIC' }
    if ([string]$rotation.successorAcceptance -cne 'FULL_COLD_ACCEPTED') { Fail 'ROTATION_SUCCESSOR_NOT_ACCEPTED' }
    if ([string]$rotation.oldNewTaskEntry -cne 'CLOSED' -or [string]$rotation.oldGrace -cne 'READ_ONLY' -or [string]$rotation.legacyAuthorizationDisposition -cne 'STALE_AUDIT_ONLY') { Fail 'ROTATION_OLD_CONTROLLER_NOT_CLOSED' }
    Write-Output "PASS|controller-rotation|project=$($current.ProjectId)|epoch=$($current.Epoch)|identity=$($current.Identity)"
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($RoutePath)) {
    $route = (Read-StrictJson $RoutePath).Value
    $requiredFields = @('schemaVersion','projectId','controllerId','controllerEpoch','controllerControlIdentity','sourceTaskId','candidateTransition','responsibleReporter','messageClass','routeClass','queuedControllerId','queuedControllerEpoch','taskPersisted','stateKey')
    foreach ($field in $requiredFields) {
        if ($route.PSObject.Properties.Name -notcontains $field) { Fail "ROUTE_FIELD_MISSING_$field" }
    }
    if (-not (Is-JsonInteger $route.schemaVersion) -or [int64]$route.schemaVersion -ne 1) { Fail 'ROUTE_SCHEMA_VERSION' }
    foreach ($field in @('projectId','controllerId','controllerControlIdentity','sourceTaskId','candidateTransition','responsibleReporter','messageClass','routeClass','queuedControllerId','stateKey')) { $null = Require-String $route $field }
    $messageClass = [string]$route.messageClass
    $routeClass = [string]$route.routeClass
    if ($messageClass -notin @('STATE','EXCEPTION','USER_DECISION','AUTHORIZATION','ACK')) { Fail 'MESSAGE_CLASS_UNKNOWN' }
    if ($routeClass -notin @('ROUTINE_SUMMARY','EXCEPTION','USER_DECISION','AUTHORIZATION')) { Fail 'ROUTE_CLASS_UNKNOWN' }
    if ($messageClass -ceq 'ACK') { Fail 'ACK_CHAIN_FORBIDDEN' }
    $legalPair = ($messageClass -ceq 'STATE' -and $routeClass -ceq 'ROUTINE_SUMMARY') -or
        ($messageClass -ceq 'EXCEPTION' -and $routeClass -ceq 'EXCEPTION') -or
        ($messageClass -ceq 'USER_DECISION' -and $routeClass -ceq 'USER_DECISION') -or
        ($messageClass -ceq 'AUTHORIZATION' -and $routeClass -ceq 'AUTHORIZATION')
    if (-not $legalPair) { Fail 'ROUTE_MESSAGE_CLASS_MISMATCH' }
    if (-not (Is-JsonInteger $route.controllerEpoch) -or -not (Is-JsonInteger $route.queuedControllerEpoch)) { Fail 'ROUTE_EPOCH_TYPE' }
    if (-not ($route.taskPersisted -is [bool]) -or -not [bool]$route.taskPersisted) { Fail 'TASK_CURRENT_NOT_PERSISTED' }
    if ([string]$route.projectId -cne $current.ProjectId -or [string]$route.controllerId -cne $current.ControllerId -or [int64]$route.controllerEpoch -ne $current.Epoch -or [string]$route.controllerControlIdentity -cne $current.Identity) { Fail 'STALE_CONTROLLER_ROUTE' }
    $expectedStateKey = "$($current.ProjectId)|$($current.Epoch)|$([string]$route.sourceTaskId)|$([string]$route.candidateTransition)|$([string]$route.responsibleReporter)"
    if ([string]$route.stateKey -cne $expectedStateKey) { Fail 'STATE_KEY_MISMATCH' }
    if ([int64]$route.queuedControllerEpoch -gt $current.Epoch) { Fail 'QUEUED_EPOCH_FUTURE' }
    if ([int64]$route.queuedControllerEpoch -eq $current.Epoch -and [string]$route.queuedControllerId -cne $current.ControllerId) { Fail 'QUEUED_CONTROLLER_ID_DRIFT' }
    if ([int64]$route.queuedControllerEpoch -lt $current.Epoch) {
        if ([string]$route.queuedControllerId -ceq $current.ControllerId) { Fail 'QUEUED_CONTROLLER_ID_DRIFT' }
        if ($messageClass -ceq 'STATE' -and $routeClass -ceq 'ROUTINE_SUMMARY') {
            Write-Output "PASS|STALE_QUEUED_SUPPRESSED|stateKey=$expectedStateKey"
            exit 0
        }
        if ($messageClass -in @('USER_DECISION','AUTHORIZATION')) { Fail 'STALE_DECISION_OR_AUTHORIZATION' }
        if ($messageClass -cne 'EXCEPTION' -or $routeClass -cne 'EXCEPTION' -or
            $route.PSObject.Properties.Name -notcontains 'revalidatedAgainstCurrentTask' -or -not ($route.revalidatedAgainstCurrentTask -is [bool]) -or -not [bool]$route.revalidatedAgainstCurrentTask -or
            $route.PSObject.Properties.Name -notcontains 'rerouteCount' -or -not (Is-JsonInteger $route.rerouteCount) -or [int64]$route.rerouteCount -ne 1 -or
            $route.PSObject.Properties.Name -notcontains 'authorizationDisposition' -or [string]$route.authorizationDisposition -cne 'NONE_REUSED') {
            Fail 'STALE_EXCEPTION_REVALIDATION_REQUIRED'
        }
        foreach ($field in @('originalEnvelopeLocator','originalEnvelopeIdentity','originalMessageClass','currentTaskLocator','currentTaskIdentity')) {
            if ($route.PSObject.Properties.Name -notcontains $field) { Fail "STALE_EXCEPTION_FIELD_MISSING_$field" }
            $null = Require-String $route $field
        }
        if ([string]::IsNullOrWhiteSpace($OriginalEnvelopePath) -or [string]::IsNullOrWhiteSpace($ObservedOriginalEnvelopeIdentity)) { Fail 'ORIGINAL_ENVELOPE_OBSERVATION_REQUIRED' }
        if ([string]::IsNullOrWhiteSpace($CurrentTaskPath)) { Fail 'CURRENT_TASK_OBSERVATION_REQUIRED' }
        Assert-LocatorMatchesPath ([string]$route.originalEnvelopeLocator) $OriginalEnvelopePath 'ORIGINAL_ENVELOPE_LOCATOR_DRIFT'
        Assert-LocatorMatchesPath ([string]$route.currentTaskLocator) $CurrentTaskPath 'CURRENT_TASK_LOCATOR_DRIFT'
        $originalRead = Read-StrictJson $OriginalEnvelopePath
        if ([string]$route.originalEnvelopeIdentity -cne $ObservedOriginalEnvelopeIdentity -or $originalRead.Identity -cne $ObservedOriginalEnvelopeIdentity) { Fail 'ORIGINAL_ENVELOPE_IDENTITY_DRIFT' }
        $original = $originalRead.Value
        foreach ($field in @('schemaVersion','projectId','sourceTaskId','candidateTransition','responsibleReporter','messageClass','routeClass','queuedControllerId','queuedControllerEpoch')) {
            if ($original.PSObject.Properties.Name -notcontains $field) { Fail "ORIGINAL_ENVELOPE_FIELD_MISSING_$field" }
        }
        if (-not (Is-JsonInteger $original.schemaVersion) -or [int64]$original.schemaVersion -ne 1 -or -not (Is-JsonInteger $original.queuedControllerEpoch)) { Fail 'ORIGINAL_ENVELOPE_SCHEMA' }
        foreach ($field in @('projectId','sourceTaskId','candidateTransition','responsibleReporter','messageClass','routeClass','queuedControllerId')) { $null = Require-String $original $field }
        if ([string]$route.originalMessageClass -cne [string]$original.messageClass) { Fail 'ORIGINAL_MESSAGE_CLASS_DRIFT' }
        foreach ($field in @('projectId','sourceTaskId','candidateTransition','responsibleReporter','queuedControllerId')) {
            if ([string]$original.$field -cne [string]$route.$field) { Fail "ORIGINAL_ENVELOPE_ROUTE_DRIFT_$field" }
        }
        if ([int64]$original.queuedControllerEpoch -ne [int64]$route.queuedControllerEpoch) { Fail 'ORIGINAL_ENVELOPE_ROUTE_DRIFT_queuedControllerEpoch' }
        if ([string]$original.messageClass -ceq 'ACK') { Fail 'STALE_ORIGINAL_ACK_FORBIDDEN' }
        if ([string]$original.messageClass -in @('USER_DECISION','AUTHORIZATION')) { Fail 'STALE_ORIGINAL_DECISION_OR_AUTHORIZATION' }
        if ([string]$original.messageClass -cne 'EXCEPTION' -or [string]$original.routeClass -cne 'EXCEPTION') { Fail 'STALE_ORIGINAL_NOT_EXCEPTION' }
        $currentTask = Read-StrictText $CurrentTaskPath
        if ([string]$route.currentTaskIdentity -cne $currentTask.Identity) { Fail 'CURRENT_TASK_IDENTITY_DRIFT' }
        $taskHeading = [regex]::Match($currentTask.Text, '\A#\s+(?<id>[^\s]+)')
        if (-not $taskHeading.Success -or $taskHeading.Groups['id'].Value -cne [string]$route.sourceTaskId) { Fail 'CURRENT_TASK_ID_DRIFT' }
        Write-Output "PASS|STALE_EXCEPTION_REROUTED_ONCE|stateKey=$expectedStateKey"
        exit 0
    }
    if ($SeenStateKey -contains $expectedStateKey) {
        Write-Output "PASS|STATE_DUPLICATE_SUPPRESSED|stateKey=$expectedStateKey"
        exit 0
    }
    Write-Output "PASS|controller-route|stateKey=$expectedStateKey"
    exit 0
}

Write-Output "PASS|controller-current|project=$($current.ProjectId)|controller=$($current.ControllerId)|epoch=$($current.Epoch)|identity=$($current.Identity)"
exit 0
