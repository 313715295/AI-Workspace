[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskPath,

    [string[]]$ObservedActualPath = @()
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

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'PATH_EMPTY' }
    if ($Path -cne $Path.Trim()) { throw "PATH_OUTER_WHITESPACE|$Path" }
    $value = $Path.Replace('\','/')
    if (-not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw "PATH_NOT_NFC|$Path" }
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/')) {
        throw "PATH_INVALID|$Path"
    }
    $parts = $value.Split('/')
    if ($parts.Count -eq 0) { throw "PATH_EMPTY|$Path" }
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..')) { throw "PATH_COMPONENT_INVALID|$Path" }
        if ($part.EndsWith('.') -or $part.EndsWith(' ')) { throw "PATH_TRAILING_DOT_OR_SPACE|$Path" }
        if ([regex]::IsMatch($part, '[\x00-\x1F]')) { throw "PATH_CONTROL_CHAR|$Path" }
        $baseName = $part.Split('.')[0]
        if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw "PATH_RESERVED_NAME|$Path" }
    }
    return [string]::Join('/', $parts)
}

function Parse-PathList([string]$Value, [System.Collections.Generic.List[string]]$Reasons, [string]$Prefix) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($Value)) { return ,$set }
    foreach ($raw in $Value.Split('|')) {
        try { $path = Normalize-RelativePath $raw } catch { Add-Reason $Reasons "${Prefix}_PATH_INVALID"; continue }
        if (-not $set.Add($path)) { Add-Reason $Reasons "${Prefix}_PATH_DUPLICATE" }
    }
    return ,$set
}

function Set-Equals($A, $B) {
    return $A.Count -eq $B.Count -and $A.SetEquals($B)
}

function Test-ResolvedField([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return -not $Value.Trim().StartsWith('<')
}

$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $TaskPath))
$reasons = New-Object 'System.Collections.Generic.List[string]'
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Add-Reason $reasons 'UTF8_BOM' }
try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes) } catch { Write-Output 'FAIL|UTF8_INVALID'; exit 2 }
if ($text.Contains("`r")) { Add-Reason $reasons 'CRLF_OR_CR' }
if ($text.Contains([char]0)) { Add-Reason $reasons 'NUL' }
if ($text.Contains([char]0xFFFD)) { Add-Reason $reasons 'U_FFFD' }
if (-not $text.EndsWith("`n")) { Add-Reason $reasons 'FINAL_LF' }
if ([regex]::IsMatch($text, '(?m)[ \t]+$')) { Add-Reason $reasons 'TRAILING_WHITESPACE' }

$schemaMatches = [regex]::Matches($text, '(?m)^- Task schema:\s*(?<version>[^\s]+)\s*$')
if ($schemaMatches.Count -eq 0) {
    if ($reasons.Count -gt 0) {
        Write-Output ('FAIL|' + [IO.Path]::GetFileName($TaskPath) + '|' + ($reasons -join ','))
        exit 2
    }

    $legacyCandidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($match in [regex]::Matches($text, '(?m)\x60(?<summary>[^\x60\r\n]+)\x60')) {
        $candidate = $match.Groups['summary'].Value
        if ($candidate.Contains('lifecycle=') -and $candidate.Contains('expected_paths=[') -and $candidate.Contains('actual_paths=[')) {
            $legacyCandidates.Add($candidate)
        }
    }
    if ($legacyCandidates.Count -eq 0) {
        Write-Output ('LEGACY_UNCHECKED|' + [IO.Path]::GetFileName($TaskPath) + '|RANGE_SUMMARY_MISSING')
        exit 0
    }
    if ($legacyCandidates.Count -ne 1) {
        Write-Output ('FAIL|' + [IO.Path]::GetFileName($TaskPath) + '|LEGACY_RANGE_SUMMARY_COUNT')
        exit 2
    }

    $legacySummary = $legacyCandidates[0]
    $legacyLifecycleMatch = [regex]::Match($legacySummary, '(?:^|;\s*)lifecycle=(?<value>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED)(?:;|$)')
    $legacyProfileMatch = [regex]::Match($legacySummary, '(?:^|;\s*)profile=(?<value>MICRO|STANDARD|CRITICAL)(?:;|$)')
    $legacyExpectedMatch = [regex]::Match($legacySummary, '(?:^|;\s*)expected_paths=\[(?<value>[^\]]*)\](?:;|$)')
    $legacyActualMatch = [regex]::Match($legacySummary, '(?:^|;\s*)actual_paths=\[(?<value>[^\]]*)\](?:;|$)')
    if (-not $legacyLifecycleMatch.Success -or -not $legacyExpectedMatch.Success -or -not $legacyActualMatch.Success) {
        Write-Output ('FAIL|' + [IO.Path]::GetFileName($TaskPath) + '|LEGACY_RANGE_SUMMARY_FORMAT')
        exit 2
    }

    $legacyLifecycle = $legacyLifecycleMatch.Groups['value'].Value
    $legacyProfile = if ($legacyProfileMatch.Success) { $legacyProfileMatch.Groups['value'].Value } else { 'LEGACY' }
    $legacyExpected = Parse-PathList $legacyExpectedMatch.Groups['value'].Value $reasons 'LEGACY_EXPECTED'
    $legacyActual = Parse-PathList $legacyActualMatch.Groups['value'].Value $reasons 'LEGACY_ACTUAL'
    $legacyObserved = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($raw in $ObservedActualPath) {
        try { $path = Normalize-RelativePath $raw } catch { Add-Reason $reasons 'LEGACY_OBSERVED_PATH_INVALID'; continue }
        if (-not $legacyObserved.Add($path)) { Add-Reason $reasons 'LEGACY_OBSERVED_PATH_DUPLICATE' }
    }

    if ($legacyLifecycle -ceq 'ACTIVE_WRITE') {
        if (-not $legacyActual.IsSubsetOf($legacyExpected)) { Add-Reason $reasons 'LEGACY_ACTUAL_OUTSIDE_EXPECTED' }
        if ($PSBoundParameters.ContainsKey('ObservedActualPath')) {
            if (-not $legacyObserved.IsSubsetOf($legacyExpected)) { Add-Reason $reasons 'LEGACY_OBSERVED_OUTSIDE_EXPECTED' }
            if (-not (Set-Equals $legacyActual $legacyObserved)) { Add-Reason $reasons 'LEGACY_DECLARED_ACTUAL_OBSERVED_MISMATCH' }
        }
    } else {
        if (-not (Set-Equals $legacyExpected $legacyActual)) { Add-Reason $reasons 'LEGACY_EXPECTED_ACTUAL_MISMATCH' }
        if ($PSBoundParameters.ContainsKey('ObservedActualPath') -and -not (Set-Equals $legacyActual $legacyObserved)) {
            Add-Reason $reasons 'LEGACY_DECLARED_ACTUAL_OBSERVED_MISMATCH'
        }
    }

    if ($reasons.Count -gt 0) {
        Write-Output ('FAIL|' + [IO.Path]::GetFileName($TaskPath) + '|' + ($reasons -join ','))
        exit 2
    }
    Write-Output ('PASS_LEGACY_SCOPE|' + [IO.Path]::GetFileName($TaskPath) + '|profile=' + $legacyProfile + '|lifecycle=' + $legacyLifecycle + '|paths=' + $legacyActual.Count)
    exit 0
}
$taskSchema = if ($schemaMatches.Count -eq 1) { $schemaMatches[0].Groups['version'].Value } else { '' }
if ($schemaMatches.Count -ne 1 -or $taskSchema -notin @('1.5','1.5.2','1.6.0')) { Add-Reason $reasons 'TASK_SCHEMA' }

$titleMatches = [regex]::Matches($text, '(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
if ($titleMatches.Count -ne 1) { Add-Reason $reasons 'TASK_ID' }
$taskId = if ($titleMatches.Count -eq 1) { $titleMatches[0].Groups['id'].Value } else { '' }

$ownerMatches = [regex]::Matches($text, '(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$')
if ($ownerMatches.Count -ne 1) { Add-Reason $reasons 'OWNER_FIELD' }
$taskOwner = if ($ownerMatches.Count -eq 1) { $ownerMatches[0].Groups['owner'].Value } else { '' }

$summaryMatches = [regex]::Matches($text, '(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL); lifecycle=(?<lifecycle>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED);(?: current_exact=(?<exact>[^;]+);)? expected_paths=\[(?<expected>[^\]]*)\]; actual_paths=\[(?<actual>[^\]]*)\]\s*$')
if ($summaryMatches.Count -ne 1) {
    Add-Reason $reasons 'RANGE_SUMMARY'
    $profile = ''
    $lifecycle = ''
    $currentExact = ''
    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $actual = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
} else {
    $profile = $summaryMatches[0].Groups['profile'].Value
    $lifecycle = $summaryMatches[0].Groups['lifecycle'].Value
    $currentExact = $summaryMatches[0].Groups['exact'].Value.Trim()
    $expected = Parse-PathList $summaryMatches[0].Groups['expected'].Value $reasons 'EXPECTED'
    $actual = Parse-PathList $summaryMatches[0].Groups['actual'].Value $reasons 'ACTUAL'
}

if ($profile -ceq 'CRITICAL' -and [string]::IsNullOrWhiteSpace($currentExact)) { Add-Reason $reasons 'CRITICAL_CURRENT_EXACT' }

if ($taskSchema -in @('1.5.2','1.6.0') -and $profile -ceq 'CRITICAL') {
    $phaseGateMatches = [regex]::Matches($text, '(?m)^- Phase gate:\s*(?<value>TRUE|FALSE)\s*$')
    if ($phaseGateMatches.Count -ne 1) {
        Add-Reason $reasons 'PHASE_GATE_FIELD'
    } elseif ($phaseGateMatches[0].Groups['value'].Value -ceq 'TRUE') {
        $technicalMatches = [regex]::Matches($text, '(?m)^- Technical evidence:\s*(?<value>PENDING|READY;\s*producer=(?<actor>[^;\s]+);\s*evidence=(?<evidence>.+))\s*$')
        $domainMatches = [regex]::Matches($text, '(?m)^- Domain contract check:\s*(?<value>PENDING|ACCEPTED;\s*owner=(?<actor>[^;\s]+);\s*evidence=(?<evidence>.+)|NOT_APPLICABLE;\s*reason=(?<reason>.+))\s*$')
        $runtimeMatches = [regex]::Matches($text, '(?m)^- Runtime/platform check:\s*(?<value>PENDING|ACCEPTED;\s*owner=(?<actor>[^;\s]+);\s*evidence=(?<evidence>.+)|NOT_APPLICABLE;\s*reason=(?<reason>.+))\s*$')
        $projectMatches = [regex]::Matches($text, '(?m)^- Project phase signoff:\s*(?<value>PENDING|READY;\s*controller=(?<actor>[^;\s]+);\s*evidence=(?<evidence>.+))\s*$')
        $userMatches = [regex]::Matches($text, '(?m)^- User final gate:\s*(?<value>PENDING|CONFIRMED;\s*candidate=(?<candidate>[^;]+);\s*evidence=(?<evidence>.+)|NOT_APPLICABLE;\s*reason=(?<reason>.+))\s*$')
        $orderMatches = [regex]::Matches($text, '(?m)^- Acceptance order:\s*TECHNICAL_EVIDENCE > DOMAIN_CONTRACT > RUNTIME_PLATFORM > PROJECT_SIGNOFF > USER_FINAL_GATE\s*$')

        if ($technicalMatches.Count -ne 1) { Add-Reason $reasons 'PHASE_TECHNICAL_EVIDENCE' }
        if ($domainMatches.Count -ne 1) { Add-Reason $reasons 'PHASE_DOMAIN_CONTRACT' }
        if ($runtimeMatches.Count -ne 1) { Add-Reason $reasons 'PHASE_RUNTIME_PLATFORM' }
        if ($projectMatches.Count -ne 1) { Add-Reason $reasons 'PHASE_PROJECT_SIGNOFF' }
        if ($userMatches.Count -ne 1) { Add-Reason $reasons 'PHASE_USER_FINAL_GATE' }
        if ($orderMatches.Count -ne 1) { Add-Reason $reasons 'PHASE_ACCEPTANCE_ORDER' }

        if ($technicalMatches.Count -eq 1 -and $domainMatches.Count -eq 1 -and $runtimeMatches.Count -eq 1 -and $projectMatches.Count -eq 1 -and $userMatches.Count -eq 1 -and $orderMatches.Count -eq 1) {
            $indices = @($technicalMatches[0].Index, $domainMatches[0].Index, $runtimeMatches[0].Index, $projectMatches[0].Index, $userMatches[0].Index, $orderMatches[0].Index)
            for ($index = 1; $index -lt $indices.Count; $index++) {
                if ($indices[$index] -le $indices[$index - 1]) { Add-Reason $reasons 'PHASE_ACCEPTANCE_ORDER'; break }
            }

            $technicalValue = $technicalMatches[0].Groups['value'].Value
            $domainValue = $domainMatches[0].Groups['value'].Value
            $runtimeValue = $runtimeMatches[0].Groups['value'].Value
            $projectValue = $projectMatches[0].Groups['value'].Value
            $userValue = $userMatches[0].Groups['value'].Value

            $technicalReady = $technicalValue.StartsWith('READY;')
            $domainReady = $domainValue.StartsWith('ACCEPTED;') -or $domainValue.StartsWith('NOT_APPLICABLE;')
            $runtimeReady = $runtimeValue.StartsWith('ACCEPTED;') -or $runtimeValue.StartsWith('NOT_APPLICABLE;')
            $projectReady = $projectValue.StartsWith('READY;')
            $userReady = $userValue.StartsWith('CONFIRMED;') -or $userValue.StartsWith('NOT_APPLICABLE;')

            if ($technicalReady -and (-not (Test-ResolvedField $technicalMatches[0].Groups['actor'].Value) -or -not (Test-ResolvedField $technicalMatches[0].Groups['evidence'].Value))) { Add-Reason $reasons 'PHASE_TECHNICAL_EVIDENCE' }
            if ($domainReady) {
                if ($domainValue.StartsWith('ACCEPTED;') -and (-not (Test-ResolvedField $domainMatches[0].Groups['actor'].Value) -or -not (Test-ResolvedField $domainMatches[0].Groups['evidence'].Value))) { Add-Reason $reasons 'PHASE_DOMAIN_CONTRACT' }
                if ($domainValue.StartsWith('NOT_APPLICABLE;') -and -not (Test-ResolvedField $domainMatches[0].Groups['reason'].Value)) { Add-Reason $reasons 'PHASE_DOMAIN_CONTRACT' }
            }
            if ($runtimeReady) {
                if ($runtimeValue.StartsWith('ACCEPTED;') -and (-not (Test-ResolvedField $runtimeMatches[0].Groups['actor'].Value) -or -not (Test-ResolvedField $runtimeMatches[0].Groups['evidence'].Value))) { Add-Reason $reasons 'PHASE_RUNTIME_PLATFORM' }
                if ($runtimeValue.StartsWith('NOT_APPLICABLE;') -and -not (Test-ResolvedField $runtimeMatches[0].Groups['reason'].Value)) { Add-Reason $reasons 'PHASE_RUNTIME_PLATFORM' }
            }
            if ($domainReady -and -not $technicalReady) { Add-Reason $reasons 'PHASE_DOMAIN_BEFORE_TECHNICAL' }
            if ($runtimeReady -and -not ($technicalReady -and $domainReady)) { Add-Reason $reasons 'PHASE_RUNTIME_BEFORE_DOMAIN' }
            if ($projectReady) {
                if ($projectMatches[0].Groups['actor'].Value -cne $taskOwner) { Add-Reason $reasons 'PROJECT_SIGNOFF_OWNER' }
                if (-not (Test-ResolvedField $projectMatches[0].Groups['evidence'].Value)) { Add-Reason $reasons 'PHASE_PROJECT_SIGNOFF' }
                if (-not ($technicalReady -and $domainReady -and $runtimeReady)) { Add-Reason $reasons 'PHASE_SIGNOFF_PREREQUISITES' }
            }
            if ($userReady) {
                if ($userValue.StartsWith('CONFIRMED;')) {
                    $userCandidate = $userMatches[0].Groups['candidate'].Value.Trim()
                    if (-not (Test-ResolvedField $userCandidate) -or -not (Test-ResolvedField $userMatches[0].Groups['evidence'].Value)) { Add-Reason $reasons 'PHASE_USER_FINAL_GATE' }
                    if ($userCandidate -cne $currentExact) { Add-Reason $reasons 'USER_GATE_CANDIDATE_MISMATCH' }
                }
                if ($userValue.StartsWith('NOT_APPLICABLE;') -and -not (Test-ResolvedField $userMatches[0].Groups['reason'].Value)) { Add-Reason $reasons 'PHASE_USER_FINAL_GATE' }
                if (-not $projectReady) { Add-Reason $reasons 'USER_GATE_BEFORE_PROJECT_SIGNOFF' }
            }
            if ($lifecycle -ceq 'CLOSED' -and (-not $projectReady -or -not $userReady)) { Add-Reason $reasons 'CLOSED_PHASE_ACCEPTANCE_INCOMPLETE' }
        }
    }
}

if ($taskSchema -ceq '1.6.0') {
    $resourceMatches = [regex]::Matches($text, '(?m)^- Resource requirement:\s*(?<value>[^\r\n]+)\s*$')
    if ($resourceMatches.Count -ne 1) {
        Add-Reason $reasons 'RESOURCE_REQUIREMENT_FIELD'
    }
    else {
        $resourceValue = $resourceMatches[0].Groups['value'].Value.Trim()
        if ($resourceValue -cne 'DEFAULT') {
            try { $requirement = $resourceValue | ConvertFrom-Json }
            catch { $requirement = $null; Add-Reason $reasons 'RESOURCE_REQUIREMENT_JSON' }
            if ($null -ne $requirement) {
                $requiredResourceFields = @('minimumQuality','requiredTools','continuity')
                $resourceNames = @($requirement.PSObject.Properties.Name)
                if (-not ($requirement -is [pscustomobject]) -or $resourceNames.Count -ne $requiredResourceFields.Count -or @($requiredResourceFields | Where-Object { $_ -cnotin $resourceNames }).Count -ne 0) {
                    Add-Reason $reasons 'RESOURCE_REQUIREMENT_SCHEMA'
                }
                elseif (-not ($requirement.minimumQuality -is [string]) -or [string]$requirement.minimumQuality -cnotin @('OWNER_FRONTIER','FOCUSED_HIGH','ROUTINE_BALANCED','MECHANICAL_LOW') -or
                    -not ($requirement.requiredTools -is [System.Array]) -or -not ($requirement.continuity -is [string]) -or [string]$requirement.continuity -cnotin @('ANY','SAME_CONTEXT','FRESH')) {
                    Add-Reason $reasons 'RESOURCE_REQUIREMENT_SCHEMA'
                }
                else {
                    $toolSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
                    foreach ($tool in @($requirement.requiredTools)) {
                        if (-not ($tool -is [string]) -or [string]::IsNullOrWhiteSpace([string]$tool) -or -not $toolSet.Add([string]$tool)) { Add-Reason $reasons 'RESOURCE_REQUIREMENT_TOOLS' }
                    }
                }
            }
        }
    }

    $coordinationMatches = [regex]::Matches($text, '(?m)^- Coordination exception:\s*(?<value>[^\r\n]+)\s*$')
    if ($coordinationMatches.Count -gt 1) { Add-Reason $reasons 'COORDINATION_EXCEPTION_COUNT' }
    elseif ($coordinationMatches.Count -eq 1) {
        try { $coordination = $coordinationMatches[0].Groups['value'].Value | ConvertFrom-Json }
        catch { $coordination = $null; Add-Reason $reasons 'COORDINATION_EXCEPTION_JSON' }
        if ($null -ne $coordination) {
            $allowedCoordinationFields = @('mode','waitPolicy','reportTarget','userDecisionHandoff')
            $coordinationNames = @($coordination.PSObject.Properties.Name)
            if (-not ($coordination -is [pscustomobject]) -or $coordinationNames.Count -eq 0 -or @($coordinationNames | Where-Object { $_ -cnotin $allowedCoordinationFields }).Count -ne 0) {
                Add-Reason $reasons 'COORDINATION_EXCEPTION_SCHEMA'
            }
            if ('mode' -cin $coordinationNames -and (-not ($coordination.mode -is [string]) -or [string]$coordination.mode -cne 'INDEPENDENT_TASK')) { Add-Reason $reasons 'COORDINATION_MODE' }
            if ('reportTarget' -cin $coordinationNames -and (-not ($coordination.reportTarget -is [string]) -or [string]::IsNullOrWhiteSpace([string]$coordination.reportTarget) -or [string]$coordination.reportTarget -ceq 'OWNER')) { Add-Reason $reasons 'COORDINATION_REPORT_TARGET' }
            if ('waitPolicy' -cin $coordinationNames) {
                $wait = $coordination.waitPolicy
                if (-not ($wait -is [pscustomobject]) -or @($wait.PSObject.Properties.Name).Count -ne 3 -or
                    @(@('kind','timeoutSeconds','trigger') | Where-Object { $_ -cnotin @($wait.PSObject.Properties.Name) }).Count -ne 0 -or
                    [string]$wait.kind -cne 'BOUNDED_EVENT' -or -not (Test-JsonInteger $wait.timeoutSeconds) -or [int]$wait.timeoutSeconds -lt 1 -or [int]$wait.timeoutSeconds -gt 3600 -or
                    -not ($wait.trigger -is [string]) -or [string]::IsNullOrWhiteSpace([string]$wait.trigger)) {
                    Add-Reason $reasons 'COORDINATION_WAIT_POLICY'
                }
            }
            if ('userDecisionHandoff' -cin $coordinationNames) {
                $handoff = $coordination.userDecisionHandoff
                $handoffFields = @('sourceTaskId','boundCandidateOrEvidence','userQuoteOrTurnLocator','invalidatesOn')
                if (-not ($handoff -is [pscustomobject]) -or @($handoff.PSObject.Properties.Name).Count -ne $handoffFields.Count -or
                    @($handoffFields | Where-Object { $_ -cnotin @($handoff.PSObject.Properties.Name) }).Count -ne 0 -or
                    -not ($handoff.invalidatesOn -is [System.Array])) {
                    Add-Reason $reasons 'USER_DECISION_HANDOFF'
                }
                else {
                    foreach ($name in @('sourceTaskId','boundCandidateOrEvidence','userQuoteOrTurnLocator')) {
                        if (-not ($handoff.$name -is [string]) -or [string]::IsNullOrWhiteSpace([string]$handoff.$name)) { Add-Reason $reasons 'USER_DECISION_HANDOFF' }
                    }
                    if (@($handoff.invalidatesOn).Count -eq 0) { Add-Reason $reasons 'USER_DECISION_HANDOFF' }
                }
            }
        }
    }
}

$observed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($raw in $ObservedActualPath) {
    try { $path = Normalize-RelativePath $raw } catch { Add-Reason $reasons 'OBSERVED_PATH_INVALID'; continue }
    if (-not $observed.Add($path)) { Add-Reason $reasons 'OBSERVED_PATH_DUPLICATE' }
}

if ($lifecycle -ceq 'ACTIVE_WRITE') {
    if (-not $actual.IsSubsetOf($expected)) { Add-Reason $reasons 'ACTUAL_OUTSIDE_EXPECTED' }
    if (-not $observed.IsSubsetOf($expected)) { Add-Reason $reasons 'OBSERVED_OUTSIDE_EXPECTED' }
    if (-not (Set-Equals $actual $observed)) { Add-Reason $reasons 'DECLARED_ACTUAL_OBSERVED_MISMATCH' }
} elseif ($lifecycle -in @('ACTIVE','REVIEW','CLOSED')) {
    if (-not (Set-Equals $expected $actual)) { Add-Reason $reasons 'EXPECTED_ACTUAL_MISMATCH' }
    if (-not (Set-Equals $actual $observed)) { Add-Reason $reasons 'DECLARED_ACTUAL_OBSERVED_MISMATCH' }
}

$authMatches = [regex]::Matches($text, '(?ms)^```authorization-package[ \t]*\n(?<json>.*?)\n```[ \t]*$')
if ($lifecycle -ceq 'ACTIVE_WRITE') {
    if ($authMatches.Count -ne 1) {
        Add-Reason $reasons 'ACTIVE_WRITE_AUTHORIZATION_COUNT'
    } else {
        try { $auth = $authMatches[0].Groups['json'].Value | ConvertFrom-Json } catch { $auth = $null; Add-Reason $reasons 'AUTHORIZATION_JSON' }
        if ($null -ne $auth) {
            $requiredAuthFields = @('schemaVersion','frameworkVersion','taskId','profile','lifecycle','owner','issuer','grantee','actions','exactPaths','objectIdentities','invalidatesOn')
            $authFieldsComplete = $true
            foreach ($field in $requiredAuthFields) {
                if ($null -eq $auth.PSObject.Properties[$field]) {
                    Add-Reason $reasons "AUTHORIZATION_FIELD_MISSING_$field"
                    $authFieldsComplete = $false
                }
            }
            if ($authFieldsComplete) {
                if ([string]$auth.taskId -cne $taskId) { Add-Reason $reasons 'AUTHORIZATION_TASK' }
                if ([string]$auth.owner -cne $taskOwner) { Add-Reason $reasons 'AUTHORIZATION_OWNER' }
                if ([string]$auth.profile -cne $profile) { Add-Reason $reasons 'AUTHORIZATION_PROFILE' }
                if ([string]$auth.lifecycle -cne 'ACTIVE') { Add-Reason $reasons 'AUTHORIZATION_NOT_ACTIVE' }
                $authPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($raw in @($auth.exactPaths)) {
                    try { $path = Normalize-RelativePath ([string]$raw) } catch { Add-Reason $reasons 'AUTHORIZATION_PATH_INVALID'; continue }
                    if (-not $authPaths.Add($path)) { Add-Reason $reasons 'AUTHORIZATION_PATH_DUPLICATE' }
                }
                if (-not (Set-Equals $expected $authPaths)) { Add-Reason $reasons 'AUTHORIZATION_EXPECTED_MISMATCH' }
            }
        }
    }
} elseif ($authMatches.Count -gt 0) {
    foreach ($match in $authMatches) {
        try { $auth = $match.Groups['json'].Value | ConvertFrom-Json } catch { Add-Reason $reasons 'AUTHORIZATION_JSON'; continue }
        if ($null -eq $auth -or $null -eq $auth.PSObject.Properties['lifecycle']) {
            Add-Reason $reasons 'AUTHORIZATION_FIELD_MISSING_lifecycle'
        } elseif ([string]$auth.lifecycle -ceq 'ACTIVE') {
            Add-Reason $reasons 'NON_WRITE_ACTIVE_AUTHORIZATION'
        }
    }
}

if ($lifecycle -ceq 'REVIEW') {
    $candidateMatches = [regex]::Matches($text, '(?m)^- Stable candidate:\s*(?<value>.+?)\s*$')
    if ($candidateMatches.Count -ne 1 -or $candidateMatches[0].Groups['value'].Value -match '^(NONE|<)') { Add-Reason $reasons 'REVIEW_STABLE_CANDIDATE' }
}

if ($lifecycle -ceq 'CLOSED' -and $TaskPath.Replace('/','\') -notmatch '(?i)\\tasks\\archive\\') { Add-Reason $reasons 'CLOSED_NOT_ARCHIVE' }

if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + [IO.Path]::GetFileName($TaskPath) + '|' + ($reasons -join ','))
    exit 2
}

Write-Output ('PASS|' + [IO.Path]::GetFileName($TaskPath) + '|profile=' + $profile + '|lifecycle=' + $lifecycle + '|paths=' + $actual.Count)
exit 0
