[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RoutePath,
    [Parameter(Mandatory = $true)][string]$ControllerControlPath,
    [Parameter(Mandatory = $true)][string]$CurrentTaskPath,
    [string[]]$SeenStateKey = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Identity([string]$Path) {
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    return $file.Length.ToString() + '|' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Test-Integer($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Add-Reason([System.Collections.Generic.List[string]]$Reasons, [string]$Reason) {
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

$reasons = New-Object 'System.Collections.Generic.List[string]'
if ($ControllerControlPath.Replace('\','/') -cne '.ai-workspace/controller.json') { Add-Reason $reasons 'CONTROLLER_LOCATOR' }
try { $route = Get-Content -LiteralPath $RoutePath -Raw -Encoding utf8 | ConvertFrom-Json }
catch { Write-Output 'FAIL|ROUTE_JSON'; exit 2 }
try { $controller = Get-Content -LiteralPath $ControllerControlPath -Raw -Encoding utf8 | ConvertFrom-Json }
catch { Write-Output 'FAIL|CONTROLLER_JSON'; exit 2 }

$controllerNames = @($controller.PSObject.Properties.Name)
if ($controllerNames.Count -ne 5 -or @(@('schemaVersion','projectId','controllerId','controllerEpoch','state') | Where-Object { $_ -cnotin $controllerNames }).Count -ne 0) { Add-Reason $reasons 'CONTROLLER_SCHEMA' }
if (-not (Test-Integer $controller.schemaVersion) -or [int]$controller.schemaVersion -ne 1 -or -not (Test-Integer $controller.controllerEpoch) -or [int64]$controller.controllerEpoch -lt 1 -or [string]$controller.state -cne 'CURRENT') { Add-Reason $reasons 'CONTROLLER_SCHEMA' }

$required = @('schemaVersion','projectId','originalControllerId','originalControllerEpoch','targetControllerId','targetControllerEpoch','sourceTaskId','taskIdentity','originalMessageClass','messageClass','candidateOrState','responsibleReporter','rerouteCount','authorizationDisposition','revalidatedAgainstCurrentTask')
$routeNames = @($route.PSObject.Properties.Name)
foreach ($name in $required) { if ($name -cnotin $routeNames) { Add-Reason $reasons "ROUTE_MISSING_$name" } }
foreach ($name in $routeNames) { if ($name -cnotin $required) { Add-Reason $reasons "ROUTE_UNKNOWN_$name" } }
if (-not (Test-Integer $route.schemaVersion) -or [int]$route.schemaVersion -ne 1) { Add-Reason $reasons 'ROUTE_SCHEMA' }
foreach ($name in @('projectId','originalControllerId','targetControllerId','sourceTaskId','taskIdentity','originalMessageClass','messageClass','candidateOrState','responsibleReporter','authorizationDisposition')) {
    if (-not ($route.$name -is [string]) -or [string]::IsNullOrWhiteSpace([string]$route.$name)) { Add-Reason $reasons "ROUTE_FIELD_TYPE_$name" }
}
foreach ($name in @('originalControllerEpoch','targetControllerEpoch','rerouteCount')) { if (-not (Test-Integer $route.$name)) { Add-Reason $reasons "ROUTE_FIELD_TYPE_$name" } }
if ((Test-Integer $route.originalControllerEpoch) -and [int64]$route.originalControllerEpoch -lt 1) { Add-Reason $reasons 'ORIGINAL_CONTROLLER_EPOCH_RANGE' }
if ((Test-Integer $route.targetControllerEpoch) -and [int64]$route.targetControllerEpoch -lt 1) { Add-Reason $reasons 'TARGET_CONTROLLER_EPOCH_RANGE' }
if (-not ($route.revalidatedAgainstCurrentTask -is [bool])) { Add-Reason $reasons 'ROUTE_FIELD_TYPE_revalidatedAgainstCurrentTask' }
$classes = @('ROUTINE','EXCEPTION','ACK','DECISION','AUTHORIZATION')
if ([string]$route.originalMessageClass -cnotin $classes -or [string]$route.messageClass -cnotin $classes) { Add-Reason $reasons 'MESSAGE_CLASS' }
if ([string]$route.originalMessageClass -cne [string]$route.messageClass) { Add-Reason $reasons 'MESSAGE_RECLASSIFICATION' }
if ([string]$route.authorizationDisposition -cnotin @('NOT_APPLICABLE','NONE_REUSED')) { Add-Reason $reasons 'AUTHORIZATION_DISPOSITION' }
if ([string]$route.projectId -cne [string]$controller.projectId -or [string]$route.targetControllerId -cne [string]$controller.controllerId -or [int64]$route.targetControllerEpoch -ne [int64]$controller.controllerEpoch) { Add-Reason $reasons 'TARGET_CONTROLLER_DRIFT' }
$taskIdentity = try { Get-Identity $CurrentTaskPath } catch { 'UNVERIFIED' }
if ($taskIdentity -ceq 'UNVERIFIED' -or [string]$route.taskIdentity -cne $taskIdentity) { Add-Reason $reasons 'CURRENT_TASK_DRIFT' }
try {
    $taskText=Get-Content -LiteralPath $CurrentTaskPath -Raw -Encoding utf8
    $taskIdMatches=[regex]::Matches($taskText,'(?m)^#\s+(?<id>[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)\s+(?:\u2014|-)\s+[^\r\n]+$')
    $ownerMatches=[regex]::Matches($taskText,'(?m)^- Owner: (?<owner>[^\r\n]+)$')
    if ($taskIdMatches.Count -ne 1 -or $ownerMatches.Count -ne 1) { throw 'Current task identity fields are ambiguous.' }
    $currentTaskId=$taskIdMatches[0].Groups['id'].Value
    $currentOwner=$ownerMatches[0].Groups['owner'].Value.Trim()
    if ([string]$route.sourceTaskId -cne $currentTaskId) { Add-Reason $reasons 'SOURCE_TASK_MISMATCH' }
    if ([string]$route.responsibleReporter -cne $currentOwner) { Add-Reason $reasons 'RESPONSIBLE_REPORTER_MISMATCH' }
}
catch { Add-Reason $reasons 'CURRENT_TASK_AUTHORITY_UNREADABLE' }

$isStale = [int64]$route.originalControllerEpoch -ne [int64]$controller.controllerEpoch -or [string]$route.originalControllerId -cne [string]$controller.controllerId
if (-not $isStale) {
    if ([int]$route.rerouteCount -ne 0 -or [bool]$route.revalidatedAgainstCurrentTask -or [string]$route.authorizationDisposition -cne 'NOT_APPLICABLE') { Add-Reason $reasons 'CURRENT_ROUTE_FLAGS' }
}
else {
    if ([int64]$route.originalControllerEpoch -ge [int64]$controller.controllerEpoch) { Add-Reason $reasons 'INVALID_TRANSITION_EPOCH' }
    switch ([string]$route.messageClass) {
        'ROUTINE' {
            if ([int]$route.rerouteCount -ne 0 -or [bool]$route.revalidatedAgainstCurrentTask) { Add-Reason $reasons 'STALE_ROUTINE_FLAGS' }
        }
        'EXCEPTION' {
            if ([int]$route.rerouteCount -ne 1 -or -not [bool]$route.revalidatedAgainstCurrentTask -or [string]$route.authorizationDisposition -cne 'NONE_REUSED') { Add-Reason $reasons 'STALE_EXCEPTION_NOT_REVALIDATED' }
        }
        default { Add-Reason $reasons 'STALE_CONTROL_MESSAGE' }
    }
}

if ($reasons.Count -gt 0) { Write-Output ('FAIL|' + ($reasons -join ',')); exit 2 }

if ([string]$route.messageClass -ceq 'ROUTINE') {
    $disposition = if ($isStale) { 'STALE_QUEUED_AUDIT_ONLY' } else { 'SUPPRESSED_ROUTINE' }
    Write-Output ("PASS|disposition=$disposition")
    exit 0
}

$stateKeyText = [string]$route.projectId + '|' + [string]$controller.controllerEpoch + '|' + [string]$route.sourceTaskId + '|' + [string]$route.candidateOrState + '|' + [string]$route.responsibleReporter
$bytes = [Text.Encoding]::UTF8.GetBytes($stateKeyText)
$sha = [Security.Cryptography.SHA256]::Create()
try { $stateKey = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
finally { $sha.Dispose() }
if ($stateKey -cin @($SeenStateKey)) {
    Write-Output ("PASS|disposition=DEDUPLICATED|stateKey=$stateKey")
    exit 0
}
$disposition = if ($isStale) { 'REROUTE_EXCEPTION_ONCE' } elseif ([string]$route.messageClass -ceq 'EXCEPTION') { 'ROUTE_EXCEPTION' } else { 'ACCEPT_CURRENT_CONTROL' }
Write-Output ("PASS|disposition=$disposition|stateKey=$stateKey")
exit 0
