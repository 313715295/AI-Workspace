[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TransactionPath,

    [string]$PreviousLedgerPath,

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedRemoteHead = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedLocalHead = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedEndpointFingerprint = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedRefspec = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedAuthorizationLocator = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedAuthorizationIdentity = @(),

    [string[]]$ObservedCompensationAuthorizationLocator = @(),

    [string[]]$ObservedCompensationAuthorizationIdentity = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedEvidencePath = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedProtectedExclude = @(),

    [Parameter(Mandatory = $true)]
    [string]$ObservedEvidenceReceipt,

    [string[]]$RequiredProtectedExclude = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$reasons = New-Object 'System.Collections.Generic.List[string]'

function Add-Reason([string]$Reason) {
    if (-not $reasons.Contains($Reason)) { $reasons.Add($Reason) }
}

function Is-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Read-StrictJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'JSON_NOT_FOUND' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'TEXT_BOM' }
    $text = $utf8Strict.GetString($bytes)
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { throw 'TEXT_STRICT' }
    return $text | ConvertFrom-Json
}

function Normalize-RepoPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cne $Path.Trim()) { throw 'PATH_EMPTY_OR_SPACE' }
    $value = $Path.Replace('\','/')
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/') -or $value.Contains('://')) { throw 'PATH_ABSOLUTE_OR_ENDPOINT' }
    if (-not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw 'PATH_NOT_NFC' }
    foreach ($part in $value.Split('/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw 'PATH_COMPONENT' }
    }
    return $value
}

function Has-Secret([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return $false }
    return $Value -match '(?i)(?:https?|ssh)://[^/\s]*@|(?:token|password|passwd|secret|authorization)\s*[:=]|gh[pousr]_[A-Za-z0-9]{12,}|-----BEGIN [A-Z ]+PRIVATE KEY-----'
}

function Get-RemoteIdempotencyKey($Transaction, $Remote) {
    $hasCompensationLocator = $Remote.PSObject.Properties.Name -contains 'compensationAuthorizationLocator'
    $hasCompensationIdentity = $Remote.PSObject.Properties.Name -contains 'compensationAuthorizationIdentity'
    $input = [ordered]@{
        schemaVersion = 1
        taskId = [string]$Transaction.taskId
        candidate = [string]$Transaction.candidate
        remoteId = [string]$Remote.remoteId
        endpointFingerprint = [string]$Remote.endpointFingerprint
        action = [string]$Remote.action
        refspec = [string]$Remote.refspec
        authorizationLocator = [string]$Remote.authorizationLocator
        authorizationIdentity = [string]$Remote.authorizationIdentity
        compensationAuthorizationLocatorPresent = $hasCompensationLocator
        compensationAuthorizationLocator = if ($hasCompensationLocator) { [string]$Remote.compensationAuthorizationLocator } else { '' }
        compensationAuthorizationIdentityPresent = $hasCompensationIdentity
        compensationAuthorizationIdentity = if ($hasCompensationIdentity) { [string]$Remote.compensationAuthorizationIdentity } else { '' }
        expectedLocalHead = [string]$Remote.expectedLocalHead
        expectedRemoteHead = [string]$Remote.expectedRemoteHead
    }
    $canonical = $input | ConvertTo-Json -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Map-Pairs([string[]]$Pairs, [string]$ReasonPrefix) {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($pair in $Pairs) {
        $split = $pair.IndexOf('=')
        if ($split -lt 1) { Add-Reason "${ReasonPrefix}_FORMAT"; continue }
        $key = $pair.Substring(0,$split)
        $value = $pair.Substring($split+1)
        if ($map.ContainsKey($key)) { Add-Reason "${ReasonPrefix}_DUPLICATE"; continue }
        $map[$key] = $value
    }
    return $map
}

try { $transaction = Read-StrictJson $TransactionPath } catch { Write-Output "FAIL|$($_.Exception.Message)"; exit 2 }
$requiredTop = @('schemaVersion','transactionId','transactionKind','projectId','taskId','candidate','gitCloser','authorizationLocator','evidenceReceipt','protectedExcludes','evidencePaths','aggregateStatus','remotes')
foreach ($field in $requiredTop) { if ($transaction.PSObject.Properties.Name -notcontains $field) { Add-Reason "FIELD_MISSING_$field" } }
$allowedTop = @($requiredTop) + @('sourceTransactionId')
foreach ($field in @($transaction.PSObject.Properties.Name)) { if ($field -cnotin $allowedTop) { Add-Reason 'FIELD_UNKNOWN' } }
if ($reasons.Count -gt 0) { Write-Output ('FAIL|' + ($reasons -join ',')); exit 2 }

if (-not (Is-JsonInteger $transaction.schemaVersion) -or [int64]$transaction.schemaVersion -ne 1) { Add-Reason 'SCHEMA_VERSION' }
foreach ($field in @('transactionId','transactionKind','projectId','taskId','candidate','gitCloser','authorizationLocator','evidenceReceipt','aggregateStatus')) {
    if (-not ($transaction.$field -is [string]) -or [string]::IsNullOrWhiteSpace([string]$transaction.$field)) { Add-Reason "FIELD_TYPE_${field}_STRING" }
}
foreach ($field in @('protectedExcludes','evidencePaths','remotes')) { if (-not ($transaction.$field -is [System.Array])) { Add-Reason "FIELD_TYPE_${field}_ARRAY" } }
if ([string]$transaction.transactionKind -notin @('PRIMARY','COMPENSATION')) { Add-Reason 'TRANSACTION_KIND' }
if ([string]$transaction.transactionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { Add-Reason 'TRANSACTION_ID' }
if ([string]$transaction.projectId -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { Add-Reason 'PROJECT_ID' }
try { $null = Normalize-RepoPath ([string]$transaction.authorizationLocator) } catch { Add-Reason 'AUTHORIZATION_LOCATOR' }
if ([string]$transaction.evidenceReceipt -and ([string]$transaction.evidenceReceipt).Length -gt 2048) { Add-Reason 'EVIDENCE_RECEIPT_LENGTH' }
if (Has-Secret ([string]$transaction.evidenceReceipt)) { Add-Reason 'SECRET_IN_EVIDENCE_RECEIPT' }
if ([string]$transaction.evidenceReceipt -cne $ObservedEvidenceReceipt) { Add-Reason 'EVIDENCE_RECEIPT_DRIFT' }

$protected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$evidence = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($value in @($transaction.protectedExcludes)) {
    if (-not ($value -is [string])) { Add-Reason 'PROTECTED_EXCLUDE_TYPE'; continue }
    try { $path = Normalize-RepoPath ([string]$value) } catch { Add-Reason 'PROTECTED_EXCLUDE_PATH'; continue }
    if (-not $protected.Add($path)) { Add-Reason 'PROTECTED_EXCLUDE_DUPLICATE' }
}
foreach ($value in @($transaction.evidencePaths)) {
    if (-not ($value -is [string])) { Add-Reason 'EVIDENCE_PATH_TYPE'; continue }
    try { $path = Normalize-RepoPath ([string]$value) } catch { Add-Reason 'EVIDENCE_PATH_INVALID'; continue }
    if (-not $evidence.Add($path)) { Add-Reason 'EVIDENCE_PATH_DUPLICATE' }
    foreach ($protectedPath in $protected) {
        if ($path.Equals($protectedPath,[StringComparison]::OrdinalIgnoreCase) -or
            $path.StartsWith($protectedPath+'/',[StringComparison]::OrdinalIgnoreCase) -or
            $protectedPath.StartsWith($path+'/',[StringComparison]::OrdinalIgnoreCase)) { Add-Reason 'PROTECTED_PATH_EXPOSED' }
    }
}
foreach ($required in $RequiredProtectedExclude) {
    try { $normalized = Normalize-RepoPath $required } catch { Add-Reason 'REQUIRED_PROTECTED_PATH_INVALID'; continue }
    if (-not $protected.Contains($normalized)) { Add-Reason 'PROTECTED_EXCLUDE_MISSING' }
}

$observedEvidence = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($value in $ObservedEvidencePath) {
    try { $path = Normalize-RepoPath $value } catch { Add-Reason 'OBSERVED_EVIDENCE_PATH_INVALID'; continue }
    if (-not $observedEvidence.Add($path)) { Add-Reason 'OBSERVED_EVIDENCE_PATH_DUPLICATE' }
}
$observedProtected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($value in $ObservedProtectedExclude) {
    try { $path = Normalize-RepoPath $value } catch { Add-Reason 'OBSERVED_PROTECTED_PATH_INVALID'; continue }
    if (-not $observedProtected.Add($path)) { Add-Reason 'OBSERVED_PROTECTED_PATH_DUPLICATE' }
}
if (-not $evidence.SetEquals($observedEvidence)) { Add-Reason 'EVIDENCE_SCOPE_DRIFT' }
if (-not $protected.SetEquals($observedProtected)) { Add-Reason 'PROTECTED_EXCLUDE_SCOPE_DRIFT' }

$observedHeads = Map-Pairs $ObservedRemoteHead 'OBSERVED_HEAD'
$observedLocalHeads = Map-Pairs $ObservedLocalHead 'OBSERVED_LOCAL_HEAD'
$observedFingerprints = Map-Pairs $ObservedEndpointFingerprint 'OBSERVED_ENDPOINT_FINGERPRINT'
$observedRefspecs = Map-Pairs $ObservedRefspec 'OBSERVED_REFSPEC'
$observedAuthorizationLocators = Map-Pairs $ObservedAuthorizationLocator 'OBSERVED_AUTHORIZATION_LOCATOR'
$observedAuthorizationIdentities = Map-Pairs $ObservedAuthorizationIdentity 'OBSERVED_AUTHORIZATION_IDENTITY'
$observedCompensationAuthorizationLocators = Map-Pairs $ObservedCompensationAuthorizationLocator 'OBSERVED_COMPENSATION_AUTHORIZATION_LOCATOR'
$observedCompensationAuthorizationIdentities = Map-Pairs $ObservedCompensationAuthorizationIdentity 'OBSERVED_COMPENSATION_AUTHORIZATION_IDENTITY'
$remoteMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
$statuses = @()
foreach ($remote in @($transaction.remotes)) {
    if ($null -eq $remote -or $remote -isnot [pscustomobject]) { Add-Reason 'REMOTE_RECORD_TYPE'; continue }
    $requiredRemote = @('remoteId','endpointFingerprint','action','refspec','authorizationLocator','authorizationIdentity','expectedLocalHead','expectedRemoteHead','idempotencyKey','attempted','status','observedHead','receipt','errorClass')
    foreach ($field in $requiredRemote) { if ($remote.PSObject.Properties.Name -notcontains $field) { Add-Reason "REMOTE_FIELD_MISSING_$field" } }
    $allowedRemote = @($requiredRemote) + @('originalReceipt','compensationAuthorizationLocator','compensationAuthorizationIdentity')
    foreach ($field in @($remote.PSObject.Properties.Name)) { if ($field -cnotin $allowedRemote) { Add-Reason 'REMOTE_FIELD_UNKNOWN' } }
    if (@($requiredRemote | Where-Object { $remote.PSObject.Properties.Name -notcontains $_ }).Count -ne 0) { continue }
    foreach ($field in @('remoteId','endpointFingerprint','action','refspec','authorizationLocator','authorizationIdentity','expectedLocalHead','expectedRemoteHead','idempotencyKey','status','observedHead','receipt','errorClass')) {
        if (-not ($remote.$field -is [string])) { Add-Reason "REMOTE_FIELD_TYPE_${field}_STRING" }
    }
    if (-not ($remote.attempted -is [bool])) { Add-Reason 'REMOTE_FIELD_TYPE_attempted_BOOLEAN' }
    $remoteId = [string]$remote.remoteId
    if ($remoteId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { Add-Reason 'REMOTE_ID' }
    if ($remoteMap.ContainsKey($remoteId)) { Add-Reason 'REMOTE_ID_DUPLICATE' } else { $remoteMap[$remoteId] = $remote }
    if ([string]$remote.endpointFingerprint -cnotmatch '^[A-F0-9]{64}$') { Add-Reason 'REMOTE_FINGERPRINT' }
    if ([string]$remote.authorizationIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason 'REMOTE_AUTHORIZATION_IDENTITY' }
    if ([string]$remote.action -notin @('PUSH_REF','CREATE_TAG','DELETE_REF','COMPENSATE_REF')) { Add-Reason 'REMOTE_ACTION' }
    if ([string]$transaction.transactionKind -ceq 'PRIMARY' -and [string]$remote.action -ceq 'COMPENSATE_REF') { Add-Reason 'PRIMARY_COMPENSATION_ACTION_FORBIDDEN' }
    foreach ($field in @('expectedLocalHead','expectedRemoteHead')) { if ([string]$remote.$field -cnotmatch '^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{64}|ABSENT)$') { Add-Reason "REMOTE_$($field.ToUpperInvariant())" } }
    if ([string]::IsNullOrWhiteSpace([string]$remote.refspec) -or ([string]$remote.refspec).Length -gt 512 -or [string]$remote.refspec -match '://|\s') { Add-Reason 'REMOTE_REFSPEC' }
    try { $null = Normalize-RepoPath ([string]$remote.authorizationLocator) } catch { Add-Reason 'REMOTE_AUTHORIZATION_LOCATOR' }
    $expectedKey = Get-RemoteIdempotencyKey $transaction $remote
    if ([string]$remote.idempotencyKey -cne $expectedKey) { Add-Reason 'IDEMPOTENCY_KEY' }
    if ([string]$remote.idempotencyKey -cnotmatch '^[A-F0-9]{64}$') { Add-Reason 'IDEMPOTENCY_KEY_FORMAT' }
    if ([string]$remote.status -notin @('PENDING','SUCCEEDED','FAILED','UNKNOWN','COMPENSATION_REQUIRED')) { Add-Reason 'REMOTE_STATUS' }
    if ([string]$remote.observedHead -cnotmatch '^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{64}|ABSENT|UNVERIFIED)$') { Add-Reason 'REMOTE_OBSERVED_HEAD' }
    if (Has-Secret ([string]$remote.receipt)) { Add-Reason 'SECRET_IN_RECEIPT' }
    if (($remote.receipt -is [string]) -and ([string]$remote.receipt).Length -gt 2048) { Add-Reason 'RECEIPT_LENGTH' }
    if ([string]$remote.errorClass -cnotmatch '^(?:NONE|[A-Z][A-Z0-9_]*)$') { Add-Reason 'REMOTE_ERROR_CLASS' }
    if ([string]$remote.status -ceq 'SUCCEEDED' -and ([string]::IsNullOrWhiteSpace([string]$remote.receipt) -or [string]$remote.errorClass -cne 'NONE')) { Add-Reason 'SUCCEEDED_LEDGER_INCOMPLETE' }
    if ([string]$remote.status -in @('FAILED','UNKNOWN') -and [string]$remote.errorClass -ceq 'NONE') { Add-Reason 'FAILED_LEDGER_ERROR_CLASS' }
    if ([string]$remote.status -ceq 'PENDING' -and (-not [string]::IsNullOrEmpty([string]$remote.receipt) -or [string]$remote.errorClass -cne 'NONE')) { Add-Reason 'PENDING_LEDGER_NOT_EMPTY' }
    $hasCompensationLocator = $remote.PSObject.Properties.Name -contains 'compensationAuthorizationLocator'
    $hasCompensationIdentity = $remote.PSObject.Properties.Name -contains 'compensationAuthorizationIdentity'
    $hasOriginalReceipt = $remote.PSObject.Properties.Name -contains 'originalReceipt'
    if ([string]$remote.status -ceq 'COMPENSATION_REQUIRED' -and
        (-not $hasOriginalReceipt -or -not ($remote.originalReceipt -is [string]) -or [string]::IsNullOrWhiteSpace([string]$remote.originalReceipt) -or
         -not $hasCompensationLocator -or -not $hasCompensationIdentity)) { Add-Reason 'COMPENSATION_EVIDENCE_MISSING' }
    if ($hasOriginalReceipt) {
        if (-not ($remote.originalReceipt -is [string])) { Add-Reason 'REMOTE_FIELD_TYPE_originalReceipt_STRING' }
        elseif ([string]::IsNullOrWhiteSpace([string]$remote.originalReceipt) -or ([string]$remote.originalReceipt).Length -gt 2048) { Add-Reason 'ORIGINAL_RECEIPT_LENGTH' }
        elseif (Has-Secret ([string]$remote.originalReceipt)) { Add-Reason 'SECRET_IN_ORIGINAL_RECEIPT' }
    }
    if ($hasCompensationLocator -or $hasCompensationIdentity) {
        if (-not $hasCompensationLocator -or -not $hasCompensationIdentity) { Add-Reason 'COMPENSATION_EVIDENCE_MISSING' }
        else {
            if (-not ($remote.compensationAuthorizationLocator -is [string])) { Add-Reason 'REMOTE_FIELD_TYPE_compensationAuthorizationLocator_STRING' }
            else { try { $null = Normalize-RepoPath $remote.compensationAuthorizationLocator } catch { Add-Reason 'COMPENSATION_AUTHORIZATION_LOCATOR' } }
            if (-not ($remote.compensationAuthorizationIdentity -is [string]) -or [string]$remote.compensationAuthorizationIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason 'COMPENSATION_AUTHORIZATION_IDENTITY' }
            if (-not $observedCompensationAuthorizationLocators.ContainsKey($remoteId) -or [string]$observedCompensationAuthorizationLocators[$remoteId] -cne [string]$remote.compensationAuthorizationLocator) { Add-Reason 'COMPENSATION_AUTHORIZATION_LOCATOR_DRIFT' }
            if (-not $observedCompensationAuthorizationIdentities.ContainsKey($remoteId) -or [string]$observedCompensationAuthorizationIdentities[$remoteId] -cne [string]$remote.compensationAuthorizationIdentity) { Add-Reason 'COMPENSATION_AUTHORIZATION_IDENTITY_DRIFT' }
        }
    }
    if ($observedHeads.ContainsKey($remoteId) -and [string]$observedHeads[$remoteId] -cne [string]$remote.expectedRemoteHead) { Add-Reason 'REMOTE_HEAD_DRIFT' }
    if (-not $observedHeads.ContainsKey($remoteId)) { Add-Reason 'OBSERVED_REMOTE_HEAD_MISSING' }
    if (-not $observedLocalHeads.ContainsKey($remoteId) -or [string]$observedLocalHeads[$remoteId] -cne [string]$remote.expectedLocalHead) { Add-Reason 'LOCAL_HEAD_DRIFT' }
    if (-not $observedFingerprints.ContainsKey($remoteId) -or [string]$observedFingerprints[$remoteId] -cne [string]$remote.endpointFingerprint) { Add-Reason 'ENDPOINT_FINGERPRINT_DRIFT' }
    if (-not $observedRefspecs.ContainsKey($remoteId) -or [string]$observedRefspecs[$remoteId] -cne [string]$remote.refspec) { Add-Reason 'REFSPEC_DRIFT' }
    if (-not $observedAuthorizationLocators.ContainsKey($remoteId) -or [string]$observedAuthorizationLocators[$remoteId] -cne [string]$remote.authorizationLocator) { Add-Reason 'AUTHORIZATION_LOCATOR_DRIFT' }
    if (-not $observedAuthorizationIdentities.ContainsKey($remoteId) -or [string]$observedAuthorizationIdentities[$remoteId] -cne [string]$remote.authorizationIdentity) { Add-Reason 'AUTHORIZATION_IDENTITY_DRIFT' }
    $statuses += [string]$remote.status
}
if ($remoteMap.Count -eq 0) { Add-Reason 'REMOTE_EMPTY' }
foreach ($key in $observedHeads.Keys) { if (-not $remoteMap.ContainsKey($key)) { Add-Reason 'OBSERVED_REMOTE_UNKNOWN' } }
foreach ($map in @($observedLocalHeads,$observedFingerprints,$observedRefspecs,$observedAuthorizationLocators,$observedAuthorizationIdentities,$observedCompensationAuthorizationLocators,$observedCompensationAuthorizationIdentities)) {
    foreach ($key in $map.Keys) { if (-not $remoteMap.ContainsKey($key)) { Add-Reason 'OBSERVED_REMOTE_UNKNOWN' } }
}

$derived = if ($statuses -contains 'COMPENSATION_REQUIRED') { 'COMPENSATION_REQUIRED' }
    elseif (@($statuses | Where-Object { $_ -ceq 'SUCCEEDED' }).Count -eq $statuses.Count -and $statuses.Count -gt 0) { 'SUCCEEDED' }
    elseif (($statuses -contains 'SUCCEEDED') -and @($statuses | Where-Object { $_ -cne 'SUCCEEDED' }).Count -gt 0) { 'PARTIAL' }
    elseif ($statuses -contains 'UNKNOWN') { 'UNKNOWN' }
    elseif ($statuses -contains 'FAILED') { 'FAILED' }
    else { 'PENDING' }
if ([string]$transaction.aggregateStatus -cne $derived) { Add-Reason 'AGGREGATE_STATUS' }

if ([string]$transaction.transactionKind -ceq 'COMPENSATION') {
    if ($transaction.PSObject.Properties.Name -notcontains 'sourceTransactionId' -or -not ($transaction.sourceTransactionId -is [string]) -or [string]$transaction.sourceTransactionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { Add-Reason 'COMPENSATION_SOURCE_INVALID' }
    foreach ($remote in @($transaction.remotes)) {
        if ([string]$remote.action -cne 'COMPENSATE_REF' -or
            $remote.PSObject.Properties.Name -notcontains 'originalReceipt' -or -not ($remote.originalReceipt -is [string]) -or [string]::IsNullOrWhiteSpace([string]$remote.originalReceipt) -or ([string]$remote.originalReceipt).Length -gt 2048 -or
            $remote.PSObject.Properties.Name -notcontains 'compensationAuthorizationLocator' -or [string]::IsNullOrWhiteSpace([string]$remote.compensationAuthorizationLocator) -or
            $remote.PSObject.Properties.Name -notcontains 'compensationAuthorizationIdentity' -or [string]$remote.compensationAuthorizationIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or
            [string]$remote.compensationAuthorizationLocator -ceq [string]$remote.authorizationLocator -or
            [string]$remote.compensationAuthorizationIdentity -ceq [string]$remote.authorizationIdentity) { Add-Reason 'COMPENSATION_RECORD_INVALID' }
    }
}

if (-not [string]::IsNullOrWhiteSpace($PreviousLedgerPath)) {
    try { $previous = Read-StrictJson $PreviousLedgerPath } catch { Add-Reason 'PREVIOUS_LEDGER_INVALID'; $previous = $null }
    if ($null -ne $previous) {
        foreach ($field in @('projectId','taskId','candidate','gitCloser','authorizationLocator')) { if ([string]$previous.$field -cne [string]$transaction.$field) { Add-Reason 'RETRY_TRANSACTION_DRIFT' } }
        $previousMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($item in @($previous.remotes)) { if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'remoteId') { $previousMap[[string]$item.remoteId] = $item } }
        if ($previousMap.Count -ne $remoteMap.Count) { Add-Reason 'RETRY_REMOTE_SET_DRIFT' }
        foreach ($remoteId in $previousMap.Keys) {
            if (-not $remoteMap.ContainsKey($remoteId)) { Add-Reason 'RETRY_REMOTE_SET_DRIFT'; continue }
            $old = $previousMap[$remoteId]; $now = $remoteMap[$remoteId]
            foreach ($field in @('endpointFingerprint','action','refspec','authorizationLocator','authorizationIdentity','expectedLocalHead','expectedRemoteHead','idempotencyKey')) {
                if ([string]$old.$field -cne [string]$now.$field) { Add-Reason 'RETRY_REMOTE_CONFIG_DRIFT' }
            }
            foreach ($field in @('compensationAuthorizationLocator','compensationAuthorizationIdentity')) {
                $oldHas = $old.PSObject.Properties.Name -contains $field
                $nowHas = $now.PSObject.Properties.Name -contains $field
                if ($oldHas -ne $nowHas -or ($oldHas -and [string]$old.$field -cne [string]$now.$field)) { Add-Reason 'RETRY_REMOTE_CONFIG_DRIFT' }
            }
            if ([string]$old.status -ceq 'SUCCEEDED') {
                if ([bool]$now.attempted -or [string]$now.status -cne 'SUCCEEDED' -or [string]$now.observedHead -cne [string]$old.observedHead -or [string]$now.receipt -cne [string]$old.receipt -or [string]$now.errorClass -cne [string]$old.errorClass) { Add-Reason 'SUCCEEDED_REMOTE_MUTATED' }
            }
            elseif ([string]$old.status -notin @('FAILED','UNKNOWN') -and
                ([bool]$now.attempted -or [string]$now.status -cne [string]$old.status -or [string]$now.observedHead -cne [string]$old.observedHead -or [string]$now.receipt -cne [string]$old.receipt -or [string]$now.errorClass -cne [string]$old.errorClass)) {
                Add-Reason 'RETRY_STATUS_NOT_ELIGIBLE'
            }
        }
    }
}

if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}
Write-Output "PASS|remote-transaction|id=$([string]$transaction.transactionId)|remotes=$($remoteMap.Count)|aggregate=$derived|protectedExcludes=$($protected.Count)"
exit 0
