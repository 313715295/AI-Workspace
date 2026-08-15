[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BatchPath,
    [Parameter(Mandatory = $true)][string]$ObservedCandidateIdentity,
    [Parameter(Mandatory = $true)][string]$ObservedGitCloser,
    [Parameter(Mandatory = $true)][string]$ObservedAuthorizationLocator,
    [Parameter(Mandatory = $true)][string]$ObservedAuthorizationIdentity,
    [Parameter(Mandatory = $true)][string]$ObservedProjectConfigIdentity,
    [Parameter(Mandatory = $true)][string]$ObservedRemotePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Add-Reason([System.Collections.Generic.List[string]]$Reasons, [string]$Reason) {
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Test-Identity([object]$Value) {
    return $Value -is [string] -and [string]$Value -cmatch '^\d+\|[A-F0-9]{64}$'
}

function Test-Head([object]$Value, [bool]$AllowAbsent) {
    if (-not ($Value -is [string])) { return $false }
    if ($AllowAbsent -and [string]$Value -ceq 'ABSENT') { return $true }
    return [string]$Value -cmatch '^[A-F0-9]{40}([A-F0-9]{24})?$'
}

function Assert-PropertySet($Object, [string[]]$Required, [string[]]$Optional, [System.Collections.Generic.List[string]]$Reasons, [string]$Prefix) {
    if (-not ($Object -is [pscustomobject])) { Add-Reason $Reasons "${Prefix}_TYPE"; return }
    $names = @($Object.PSObject.Properties.Name)
    foreach ($name in $Required) {
        if ($name -cnotin $names) { Add-Reason $Reasons "${Prefix}_MISSING_$name" }
    }
    foreach ($name in $names) {
        if ($name -cnotin @($Required + $Optional)) { Add-Reason $Reasons "${Prefix}_UNKNOWN_$name" }
    }
}

$reasons = New-Object 'System.Collections.Generic.List[string]'
try {
    $raw = Get-Content -LiteralPath $BatchPath -Raw -Encoding utf8
    $batch = $raw | ConvertFrom-Json
}
catch {
    Write-Output 'FAIL|BATCH_JSON'
    exit 2
}

$topRequired = @('schemaVersion','kind','batchId','projectId','taskId','candidateIdentity','gitCloser','authorizationLocator','authorizationIdentity','projectConfigIdentity','remotes')
Assert-PropertySet $batch $topRequired @() $reasons 'TOP'
if (-not (Test-JsonInteger $batch.schemaVersion) -or [int]$batch.schemaVersion -ne 1) { Add-Reason $reasons 'SCHEMA_VERSION' }
foreach ($field in @('kind','batchId','projectId','taskId','candidateIdentity','gitCloser','authorizationLocator','authorizationIdentity','projectConfigIdentity')) {
    if (-not ($batch.$field -is [string]) -or [string]::IsNullOrWhiteSpace([string]$batch.$field)) { Add-Reason $reasons "FIELD_TYPE_$field" }
}
if ([string]$batch.kind -cne 'REMOTE_BATCH') { Add-Reason $reasons 'KIND' }
if ([string]$batch.batchId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{7,127}$') { Add-Reason $reasons 'BATCH_ID' }
foreach ($field in @('candidateIdentity','authorizationIdentity','projectConfigIdentity')) {
    if (-not (Test-Identity $batch.$field)) { Add-Reason $reasons "IDENTITY_$field" }
}
if ([string]$batch.candidateIdentity -cne $ObservedCandidateIdentity) { Add-Reason $reasons 'CANDIDATE_DRIFT' }
if ([string]$batch.gitCloser -cne $ObservedGitCloser) { Add-Reason $reasons 'GIT_CLOSER_DRIFT' }
if ([string]$batch.authorizationLocator -cne $ObservedAuthorizationLocator) { Add-Reason $reasons 'AUTHORIZATION_LOCATOR_DRIFT' }
if ([string]$batch.authorizationIdentity -cne $ObservedAuthorizationIdentity) { Add-Reason $reasons 'AUTHORIZATION_IDENTITY_DRIFT' }
if ([string]$batch.projectConfigIdentity -cne $ObservedProjectConfigIdentity) { Add-Reason $reasons 'PROJECT_CONFIG_DRIFT' }
if (-not ($batch.remotes -is [System.Array]) -or @($batch.remotes).Count -eq 0) { Add-Reason $reasons 'REMOTES_ARRAY' }

$observed = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
try {
    $parsedObserved = Get-Content -LiteralPath $ObservedRemotePath -Raw -Encoding utf8 | ConvertFrom-Json
    $observedItems = @()
    foreach ($item in $parsedObserved) { $observedItems += $item }
}
catch { $observedItems = @(); Add-Reason $reasons 'OBSERVED_REMOTE_JSON' }
foreach ($entry in $observedItems) {
    $names = @($entry.PSObject.Properties.Name)
    $requiredObserved = @('remoteId','endpointFingerprint','refspec','localHead','remoteHead')
    if (-not ($entry -is [pscustomobject]) -or $names.Count -ne $requiredObserved.Count -or @($requiredObserved | Where-Object { $_ -cnotin $names }).Count -ne 0) { Add-Reason $reasons 'OBSERVED_REMOTE_FORMAT'; continue }
    if ([string]$entry.remoteId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { Add-Reason $reasons 'OBSERVED_REMOTE_FORMAT'; continue }
    if ($observed.ContainsKey([string]$entry.remoteId)) { Add-Reason $reasons 'OBSERVED_REMOTE_DUPLICATE'; continue }
    $observed.Add([string]$entry.remoteId, $entry)
}

$remoteIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$statusValues = @()
$remoteRequired = @('remoteId','endpointFingerprint','action','refspec','expectedLocalHead','expectedRemoteHead','attempted','status')
$remoteOptional = @('observedRemoteHead','receipt','errorClass')
foreach ($remote in @($batch.remotes)) {
    Assert-PropertySet $remote $remoteRequired $remoteOptional $reasons 'REMOTE'
    foreach ($field in @('remoteId','endpointFingerprint','action','refspec','expectedLocalHead','expectedRemoteHead','status')) {
        if (-not ($remote.$field -is [string])) { Add-Reason $reasons "REMOTE_FIELD_TYPE_$field" }
    }
    if (-not ($remote.attempted -is [bool])) { Add-Reason $reasons 'REMOTE_FIELD_TYPE_attempted' }
    $remoteId = [string]$remote.remoteId
    if ($remoteId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or -not $remoteIds.Add($remoteId)) { Add-Reason $reasons 'REMOTE_ID_INVALID_OR_DUPLICATE' }
    if ([string]$remote.endpointFingerprint -cnotmatch '^[A-F0-9]{64}$') { Add-Reason $reasons 'ENDPOINT_FINGERPRINT' }
    if ([string]$remote.action -cne 'PUSH_REF') { Add-Reason $reasons 'DANGEROUS_OR_UNKNOWN_ACTION' }
    $refspec = [string]$remote.refspec
    if ($refspec.StartsWith('+') -or $refspec -cnotmatch '^refs/[A-Za-z0-9._/-]+:refs/[A-Za-z0-9._/-]+$' -or $refspec.Contains('..') -or $refspec.Contains('@{')) {
        Add-Reason $reasons 'REFSPEC_REJECTED'
    }
    if (-not (Test-Head $remote.expectedLocalHead $false)) { Add-Reason $reasons 'LOCAL_HEAD_FORMAT' }
    if (-not (Test-Head $remote.expectedRemoteHead $true)) { Add-Reason $reasons 'REMOTE_HEAD_FORMAT' }
    $status = [string]$remote.status
    if ($status -cnotin @('PENDING','SUCCEEDED','FAILED','UNKNOWN')) { Add-Reason $reasons 'REMOTE_STATUS' }
    $statusValues += $status
    $hasObserved = $remote.PSObject.Properties.Name -ccontains 'observedRemoteHead'
    $hasReceipt = $remote.PSObject.Properties.Name -ccontains 'receipt'
    $hasError = $remote.PSObject.Properties.Name -ccontains 'errorClass'
    if (-not [bool]$remote.attempted) {
        if ($status -cne 'PENDING' -or $hasObserved -or $hasReceipt -or $hasError) { Add-Reason $reasons 'UNATTEMPTED_RESULT_FIELDS' }
    }
    else {
        if ($status -ceq 'PENDING') { Add-Reason $reasons 'ATTEMPTED_PENDING' }
        if ($hasObserved -and -not (Test-Head $remote.observedRemoteHead $true)) { Add-Reason $reasons 'OBSERVED_HEAD_FORMAT' }
        if ($status -ceq 'SUCCEEDED') {
            if (-not $hasReceipt -or -not $hasObserved -or $hasError) { Add-Reason $reasons 'SUCCESS_EVIDENCE' }
        }
        elseif ($status -in @('FAILED','UNKNOWN')) {
            if (-not $hasError -or $hasReceipt) { Add-Reason $reasons 'FAILURE_EVIDENCE' }
        }
    }
    if ($hasReceipt) {
        if (-not ($remote.receipt -is [string]) -or [string]::IsNullOrWhiteSpace([string]$remote.receipt) -or
            [string]$remote.receipt -match '(?i)(https?://|ssh://|password|token|secret|[^\s:]+:[^\s@]+@)') {
            Add-Reason $reasons 'RECEIPT_NOT_SECRET_SAFE'
        }
    }
    if ($hasError -and ([string]$remote.errorClass -cnotin @('AUTHORIZATION_REJECTED','HEAD_DRIFT','REFSPEC_REJECTED','REMOTE_REJECTED','NETWORK_FAILURE','REMOTE_STATE_UNKNOWN'))) {
        Add-Reason $reasons 'ERROR_CLASS'
    }
    if (-not $observed.ContainsKey($remoteId)) { Add-Reason $reasons 'OBSERVED_REMOTE_MISSING' }
    else {
        $actual = $observed[$remoteId]
        if ([string]$actual.endpointFingerprint -cne [string]$remote.endpointFingerprint) { Add-Reason $reasons 'ENDPOINT_DRIFT' }
        if ([string]$actual.refspec -cne $refspec) { Add-Reason $reasons 'REFSPEC_DRIFT' }
        if ([string]$actual.localHead -cne [string]$remote.expectedLocalHead) { Add-Reason $reasons 'LOCAL_HEAD_DRIFT' }
        if ([string]$actual.remoteHead -cne [string]$remote.expectedRemoteHead) { Add-Reason $reasons 'REMOTE_HEAD_DRIFT' }
    }
}
if ($observed.Count -ne $remoteIds.Count) { Add-Reason $reasons 'OBSERVED_REMOTE_SET_DRIFT' }

if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

$successes = @($statusValues | Where-Object { $_ -ceq 'SUCCEEDED' }).Count
$failures = @($statusValues | Where-Object { $_ -ceq 'FAILED' }).Count
$unknowns = @($statusValues | Where-Object { $_ -ceq 'UNKNOWN' }).Count
$pending = @($statusValues | Where-Object { $_ -ceq 'PENDING' }).Count
$aggregate = if ($pending -eq $statusValues.Count) { 'PLANNED' }
    elseif ($pending -gt 0) { 'UNKNOWN' }
    elseif ($successes -eq $statusValues.Count) { 'SUCCEEDED' }
    elseif ($successes -gt 0) { 'PARTIAL' }
    elseif ($unknowns -gt 0) { 'UNKNOWN' }
    else { 'FAILED' }
Write-Output ("PASS|batch=$($batch.batchId)|aggregate=$aggregate|remotes=$($remoteIds.Count)")
exit 0
