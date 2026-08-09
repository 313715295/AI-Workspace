[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [Alias('FullName')]
    [string[]]$Path,

    [Parameter()]
    [string]$ObservedActualPath
)

# This checker validates only declarations inside one task card and, when supplied,
# their equality with an observed path manifest. It never discovers Git ownership,
# approves design, grants permissions, or scans a repository for task attribution.

Set-StrictMode -Version Latest
$script:HasFailure = $false
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$allowedActors = @('OWNER', 'EXECUTOR', 'REVIEWER', 'USER', 'EXTERNAL', 'NONE')
$inactiveExternalValues = @(
    'NONE',
    [regex]::Unescape('\u65e0'),
    [regex]::Unescape('\u5173\u95ed'),
    [regex]::Unescape('\u672a\u6388\u6743'),
    [regex]::Unescape('\u4e0d\u9002\u7528')
)

function Add-Reason {
    param(
        [System.Collections.Generic.List[string]]$Reasons,
        [string]$Reason
    )

    if (-not $Reasons.Contains($Reason)) {
        [void]$Reasons.Add($Reason)
    }
}

function Get-LogicalField {
    param(
        [string]$Text,
        [string]$LabelPattern,
        [string]$ReasonName,
        [System.Collections.Generic.List[string]]$Reasons,
        [bool]$Required = $true
    )

    $matches = [regex]::Matches(
        $Text,
        "(?m)^-\s*(?:$LabelPattern)\s*\uFF1A\s*(?<value>.*?)\s*$"
    )
    if ($matches.Count -eq 0 -and -not $Required) {
        return $null
    }
    if ($matches.Count -ne 1) {
        Add-Reason $Reasons ("{0}_COUNT" -f $ReasonName)
        return $null
    }

    $value = $matches[0].Groups['value'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        Add-Reason $Reasons ("{0}_EMPTY" -f $ReasonName)
        return $null
    }

    return $value
}

function Test-RequiredHeading {
    param(
        [string]$Text,
        [string]$HeadingPattern,
        [string]$ReasonName,
        [System.Collections.Generic.List[string]]$Reasons
    )

    $matches = [regex]::Matches($Text, "(?m)^##\s+(?:$HeadingPattern)\s*$")
    if ($matches.Count -ne 1) {
        Add-Reason $Reasons ("{0}_COUNT" -f $ReasonName)
    }
}

function Get-NextActionCount {
    param(
        [string]$Text,
        [System.Collections.Generic.List[string]]$Reasons
    )

    $labelMatches = [regex]::Matches(
        $Text,
        '(?m)^(?:-\s*)?\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\s*\uFF1A\s*(?<value>.*?)\s*$'
    )
    foreach ($match in $labelMatches) {
        if ([string]::IsNullOrWhiteSpace($match.Groups['value'].Value)) {
            Add-Reason $Reasons 'NEXT_ACTION_EMPTY'
        }
    }

    $headingMatches = [regex]::Matches(
        $Text,
        '(?m)^#{2,6}\s+(?:\d+\.\s*)?\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\s*$'
    )
    foreach ($match in $headingMatches) {
        $contentStart = $match.Index + $match.Length
        $remaining = $Text.Substring($contentStart)
        $nextHeading = [regex]::Match($remaining, '(?m)^#{1,6}\s+')
        if ($nextHeading.Success) {
            $remaining = $remaining.Substring(0, $nextHeading.Index)
        }
        if ([string]::IsNullOrWhiteSpace($remaining)) {
            Add-Reason $Reasons 'NEXT_ACTION_EMPTY'
        }
    }

    return $labelMatches.Count + $headingMatches.Count
}

function ConvertTo-NormalizedPathSet {
    param(
        [string[]]$RawItems,
        [string]$ReasonPrefix,
        [bool]$AllowEmptySet,
        [System.Collections.Generic.List[string]]$Reasons
    )

    $normalizedItems = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $RawItems -or $RawItems.Count -eq 0) {
        if (-not $AllowEmptySet) {
            Add-Reason $Reasons ("{0}_EMPTY" -f $ReasonPrefix)
        }
        return $normalizedItems.ToArray()
    }

    foreach ($rawItem in $RawItems) {
        if ([string]::IsNullOrWhiteSpace($rawItem)) {
            Add-Reason $Reasons ("{0}_EMPTY_ITEM" -f $ReasonPrefix)
            continue
        }

        $normalized = $rawItem.Trim().Replace('\', '/')
        if ($normalized -match '(^/|^[A-Za-z]:|//|/$|(?:^|/)\.{1,2}(?:/|$)|[\[\]|;])') {
            Add-Reason $Reasons ("{0}_INVALID" -f $ReasonPrefix)
            continue
        }
        if ($normalizedItems.Contains($normalized)) {
            Add-Reason $Reasons ("{0}_DUPLICATE_OR_NORMALIZATION_COLLISION[{1}]" -f $ReasonPrefix, $normalized)
            continue
        }

        [void]$normalizedItems.Add($normalized)
    }

    return $normalizedItems.ToArray()
}

function ConvertFrom-BracketedPathField {
    param(
        [string]$Value,
        [string]$ReasonPrefix,
        [bool]$AllowEmptySet,
        [System.Collections.Generic.List[string]]$Reasons
    )

    $match = [regex]::Match($Value.Trim('`'), '^\[(?<items>[^\]]*)\]$')
    if (-not $match.Success) {
        Add-Reason $Reasons ("{0}_FORMAT" -f $ReasonPrefix)
        return @()
    }
    $raw = $match.Groups['items'].Value
    $items = if ($raw.Length -eq 0) { @() } else { @($raw.Split('|')) }
    return @(ConvertTo-NormalizedPathSet $items $ReasonPrefix $AllowEmptySet $Reasons)
}

function Compare-NormalizedPathSets {
    param(
        [string[]]$Expected,
        [string[]]$Actual,
        [bool]$RequireEquality,
        [string]$MissingPrefix,
        [string]$ExtraPrefix,
        [System.Collections.Generic.List[string]]$Reasons
    )

    if ($RequireEquality) {
        foreach ($expectedPath in @($Expected | Sort-Object)) {
            if ($Actual -cnotcontains $expectedPath) {
                Add-Reason $Reasons ("{0}[{1}]" -f $MissingPrefix, $expectedPath)
            }
        }
    }
    foreach ($actualPath in @($Actual | Sort-Object)) {
        if ($Expected -cnotcontains $actualPath) {
            Add-Reason $Reasons ("{0}[{1}]" -f $ExtraPrefix, $actualPath)
        }
    }
}

function Test-ActorAndNotifier {
    param(
        [string]$Text,
        [string]$StatusField,
        [string]$CurrentActor,
        [string]$NextActor,
        [string]$Notifier,
        [System.Collections.Generic.List[string]]$Reasons
    )

    if ($allowedActors -notcontains $CurrentActor) {
        Add-Reason $Reasons 'CURRENT_ACTOR_VALUE'
    }
    if ($allowedActors -notcontains $NextActor) {
        Add-Reason $Reasons 'NEXT_ACTOR_VALUE'
    }
    if ($CurrentActor -ne $NextActor -and $NextActor -notin @('USER', 'EXTERNAL')) {
        Add-Reason $Reasons 'ACTOR_NEXT_MISMATCH'
    }

    $ownerMediatedStopline = $false
    if ($null -ne $StatusField) {
        $statusTokens = @($StatusField.Trim('`').Split('/') | ForEach-Object { $_.Trim() })
        foreach ($statusToken in $statusTokens) {
            if ($statusToken -in @('DIRECT_LOOP_STOPPED', 'RANGE_GATE_REQUIRED', 'OWNER_MEDIATED_REVIEW') -or
                $statusToken -match '^OWNER_FOCUSED_REVIEW(?:_[A-Z0-9]+)*$') {
                $ownerMediatedStopline = $true
                break
            }
        }
    }

    if ($Notifier -eq 'REVIEWER') {
        if ($CurrentActor -ne 'REVIEWER' -or $NextActor -ne 'REVIEWER') {
            Add-Reason $Reasons 'REVIEWER_NOTIFIER_REQUIRES_REVIEWER_ACTOR'
        }
        if ($Text -notmatch '\u65e0\u6267\u884c\u8005' -or $Text -notmatch '\u7a33\u5b9a\u5bf9\u8c61') {
            Add-Reason $Reasons 'REVIEWER_NOTIFIER_REQUIRES_NO_EXECUTOR_STABLE_OBJECT'
        }
    }
    elseif ($Notifier -eq 'NONE') {
        if ($CurrentActor -ne 'OWNER' -or $NextActor -ne 'OWNER') {
            Add-Reason $Reasons 'NONE_NOTIFIER_REQUIRES_OWNER_ACTOR'
        }
        if (-not $ownerMediatedStopline) {
            Add-Reason $Reasons 'NONE_NOTIFIER_REQUIRES_OWNER_MEDIATED_STOPLINE'
        }
    }
    elseif ($Notifier -eq 'EXECUTOR') {
        if ($CurrentActor -eq 'OWNER' -and $NextActor -eq 'OWNER' -and $ownerMediatedStopline) {
            Add-Reason $Reasons 'OWNER_MEDIATED_STOPLINE_REQUIRES_NONE_NOTIFIER'
        }
    }
    else {
        Add-Reason $Reasons 'REVIEW_START_NOTIFIER_VALUE'
    }
}

function Test-TaskCard {
    param([string]$CardPath)

    $displayName = Split-Path -Leaf $CardPath
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = $CardPath
    }

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if (-not (Test-Path -LiteralPath $CardPath -PathType Leaf)) {
        Add-Reason $reasons 'FILE_NOT_FOUND'
        $script:HasFailure = $true
        "FAIL|$displayName|$($reasons -join ',')"
        return
    }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $CardPath -ErrorAction Stop).Path
        $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Add-Reason $reasons 'UTF8_BOM'
        }
        $text = $strictUtf8.GetString($bytes)
    }
    catch {
        Add-Reason $reasons 'UTF8_INVALID'
        $script:HasFailure = $true
        "FAIL|$displayName|$($reasons -join ',')"
        return
    }

    if ($text.Contains([char]0)) {
        Add-Reason $reasons 'NUL'
    }
    if ($text.Contains([char]0xFFFD)) {
        Add-Reason $reasons 'U_FFFD'
    }
    if (-not $text.EndsWith("`n")) {
        Add-Reason $reasons 'FINAL_LF'
    }
    if ([regex]::IsMatch($text, '(?m)[ \t]+(?=\r?$)')) {
        Add-Reason $reasons 'TRAILING_WHITESPACE'
    }
    if ([regex]::IsMatch($text, '(?m)^(?:<<<<<<<|=======|>>>>>>>)')) {
        Add-Reason $reasons 'CONFLICT_MARKER'
    }
    $backtickFenceCount = [regex]::Matches($text, '(?m)^\s*`{3,}').Count
    $tildeFenceCount = [regex]::Matches($text, '(?m)^\s*~{3,}').Count
    if (($backtickFenceCount % 2) -ne 0 -or ($tildeFenceCount % 2) -ne 0) {
        Add-Reason $reasons 'MARKDOWN_FENCE'
    }

    $summaryMatches = [regex]::Matches(
        $text,
        '(?m)^-\s*(?:\u8303\u56f4\u6458\u8981|\u673a\u68b0\u6458\u8981)\s*\uFF1A\s*(?<value>.*?)\s*$'
    )
    if ($summaryMatches.Count -eq 0) {
        if ($reasons.Count -gt 0) {
            $script:HasFailure = $true
            "FAIL|$displayName|$($reasons -join ',')"
        }
        else {
            "LEGACY_UNCHECKED|$displayName|RANGE_SUMMARY_MISSING"
        }
        return
    }
    if ($summaryMatches.Count -ne 1) {
        Add-Reason $reasons 'RANGE_SUMMARY_COUNT'
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
    $h1Matches = [regex]::Matches($text, '(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)\s+.+$')
    if ($h1Matches.Count -ne 1) {
        Add-Reason $reasons 'H1_TASK_ID_COUNT'
    }
    elseif ($h1Matches[0].Groups['id'].Value -cne $baseName) {
        Add-Reason $reasons 'H1_FILENAME_MISMATCH'
    }

    $statusField = Get-LogicalField $text '\u72b6\u6001' 'STATUS' $reasons
    $ownerField = Get-LogicalField $text '\u552f\u4e00\u957f\u671fowner/\u8c03\u5ea6\u8005' 'OWNER' $reasons
    $gitPermissionField = Get-LogicalField $text 'Git\s*\u6743\u9650' 'GIT_PERMISSION' $reasons
    $externalField = Get-LogicalField $text '\u5916\u90e8\u52a8\u4f5c\u6388\u6743' 'EXTERNAL_AUTH' $reasons
    $profileField = Get-LogicalField $text '\u4efb\u52a1\u6863\u4f4d' 'PROFILE' $reasons $false
    $riskField = Get-LogicalField $text '\u98ce\u9669' 'RISK' $reasons $false
    $exactField = Get-LogicalField $text 'Exact\s*\u8def\u5f84' 'EXACT_PATH_FIELD' $reasons $false
    [void](Get-LogicalField $text 'Forbidden\s*\u8def\u5f84' 'FORBIDDEN_PATH_FIELD' $reasons $false)
    [void]$ownerField
    [void]$gitPermissionField

    $nextActionCount = Get-NextActionCount $text $reasons
    if ($nextActionCount -ne 1) {
        Add-Reason $reasons 'NEXT_ACTION_COUNT'
    }

    $summaryText = $summaryMatches[0].Groups['value'].Value.Trim().Trim('`')
    $compactSummary = [regex]::Match(
        $summaryText,
        '^profile=(?<profile>MICRO|STANDARD); lifecycle=(?<lifecycle>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED); expected_paths=\[(?<expected>[^\]]*)\]; actual_paths=\[(?<actual>[^\]]*)\](?:; current_actor=(?<current>[A-Z][A-Z0-9_]*); next_actor=(?<next>[A-Z][A-Z0-9_]*); review_start_notifier=(?<notifier>[A-Z][A-Z0-9_]*))?$'
    )
    $criticalSummary = [regex]::Match(
        $summaryText,
        '^profile=CRITICAL; lifecycle=(?<lifecycle>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED); current_actor=(?<current>[A-Z][A-Z0-9_]*); next_actor=(?<next>[A-Z][A-Z0-9_]*); current_exact=(?<exact>[^;]+); expected_paths=\[(?<expected>[^\]]*)\]; actual_paths=\[(?<actual>[^\]]*)\]; review_start_notifier=(?<notifier>[A-Z][A-Z0-9_]*)$'
    )
    $compatSummary = [regex]::Match(
        $summaryText,
        '^lifecycle=(?<lifecycle>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED); current_actor=(?<current>[A-Z][A-Z0-9_]*); next_actor=(?<next>[A-Z][A-Z0-9_]*); current_exact=(?<exact>[^;]+); expected_paths=\[(?<expected>[^\]]*)\]; actual_paths=\[(?<actual>[^\]]*)\]; review_start_notifier=(?<notifier>[A-Z][A-Z0-9_]*)$'
    )

    $profile = $null
    $summary = $null
    $compatibilityMode = $false
    if ($compactSummary.Success) {
        $summary = $compactSummary
        $profile = $summary.Groups['profile'].Value
    }
    elseif ($criticalSummary.Success) {
        $summary = $criticalSummary
        $profile = 'CRITICAL'
    }
    elseif ($compatSummary.Success) {
        $summary = $compatSummary
        $profile = 'CRITICAL'
        $compatibilityMode = $true
    }
    else {
        Add-Reason $reasons 'RANGE_SUMMARY_FORMAT'
    }

    if ($null -ne $summary) {
        $lifecycle = $summary.Groups['lifecycle'].Value
        $expectedRaw = $summary.Groups['expected'].Value
        $actualRaw = $summary.Groups['actual'].Value
        $expectedItems = if ($expectedRaw.Length -eq 0) { @() } else { @($expectedRaw.Split('|')) }
        $actualItems = if ($actualRaw.Length -eq 0) { @() } else { @($actualRaw.Split('|')) }
        $expectedPaths = @(ConvertTo-NormalizedPathSet $expectedItems 'EXPECTED_PATH' $false $reasons)
        $actualPaths = @(ConvertTo-NormalizedPathSet $actualItems 'ACTUAL_PATH' $true $reasons)

        if (-not $compatibilityMode) {
            if ($null -eq $profileField -or $profileField.Trim('`') -cne $profile) {
                Add-Reason $reasons 'PROFILE_FIELD_MISMATCH'
            }
            if ($null -eq $riskField) {
                Add-Reason $reasons 'RISK_COUNT'
            }
            if ($null -eq $exactField) {
                Add-Reason $reasons 'EXACT_PATH_FIELD_COUNT'
            }
            else {
                $declaredExactPaths = @(ConvertFrom-BracketedPathField $exactField 'EXACT_PATH_FIELD' $false $reasons)
                Compare-NormalizedPathSets $expectedPaths $declaredExactPaths $true 'EXACT_FIELD_MISSING' 'EXACT_FIELD_EXTRA' $reasons
            }
            if ($null -eq (Get-LogicalField $text 'Forbidden\s*\u8def\u5f84' 'FORBIDDEN_PATH_FIELD_REQUIRED' $reasons)) {
                Add-Reason $reasons 'FORBIDDEN_PATH_REQUIRED'
            }

            Test-RequiredHeading $text '\u76ee\u6807' 'GOAL_HEADING' $reasons
            Test-RequiredHeading $text '\u8303\u56f4\u4e0e\u4fdd\u62a4' 'SCOPE_HEADING' $reasons
            Test-RequiredHeading $text '\u9a8c\u6536\u4e0e\u9a8c\u8bc1' 'ACCEPTANCE_VALIDATION_HEADING' $reasons
            Test-RequiredHeading $text '\u4ea4\u63a5/\u4e0b\u4e00\u6b65' 'HANDOFF_HEADING' $reasons
            if ($profile -in @('STANDARD', 'CRITICAL')) {
                Test-RequiredHeading $text '\u975e\u76ee\u6807' 'NON_GOAL_HEADING' $reasons
            }

            $normalizedExternal = if ($null -eq $externalField) { '' } else { $externalField.Trim('`').Trim() }
            if ($profile -eq 'MICRO') {
                if ($null -ne $riskField -and $riskField -notmatch '(?:\u4f4e|\u8f7b)') {
                    Add-Reason $reasons 'PROFILE_RISK_MISMATCH'
                }
                if ($inactiveExternalValues -notcontains $normalizedExternal) {
                    Add-Reason $reasons 'PROFILE_ESCALATION_REQUIRED[EXTERNAL_ACTION]'
                }
                if ($summary.Groups['current'].Success -or
                    [regex]::IsMatch($text, '(?m)^-\s*(?:\u5f53\u524dactor|\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005|Review\u5f00\u59cb\u901a\u77e5\u65b9|(?:\u72ec\u7acb)?\u5ba1\u6838\u4eba|\u76f4\u63a5\u5ba1\u6838\u95ed\u73af)\s*\uFF1A')) {
                    Add-Reason $reasons 'PROFILE_ESCALATION_REQUIRED[MULTI_ROLE]'
                }
            }
            elseif ($profile -eq 'STANDARD') {
                if ($null -ne $riskField -and $riskField -match '(?:\u91cd|\u9ad8|\u5173\u952e|CRITICAL)') {
                    Add-Reason $reasons 'PROFILE_ESCALATION_REQUIRED[DECLARED_HIGH_RISK]'
                }
                if ($inactiveExternalValues -notcontains $normalizedExternal) {
                    Add-Reason $reasons 'PROFILE_ESCALATION_REQUIRED[EXTERNAL_ACTION]'
                }

                $roleLabels = [regex]::Matches(
                    $text,
                    '(?m)^-\s*(?:\u5f53\u524dactor|\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005|Review\u5f00\u59cb\u901a\u77e5\u65b9|(?:\u72ec\u7acb)?\u5ba1\u6838\u4eba|\u76f4\u63a5\u5ba1\u6838\u95ed\u73af)\s*\uFF1A'
                )
                $hasRoleSummary = $summary.Groups['current'].Success
                if (($roleLabels.Count -gt 0) -ne $hasRoleSummary) {
                    Add-Reason $reasons 'STANDARD_ROLE_BLOCK_SUMMARY_MISMATCH'
                }
                if ($hasRoleSummary) {
                    $currentActorField = Get-LogicalField $text '\u5f53\u524dactor' 'CURRENT_ACTOR' $reasons
                    $nextActorField = Get-LogicalField $text '\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005' 'NEXT_ACTOR' $reasons
                    $notifierField = Get-LogicalField $text 'Review\u5f00\u59cb\u901a\u77e5\u65b9' 'REVIEW_START_NOTIFIER' $reasons
                    [void](Get-LogicalField $text '(?:\u72ec\u7acb)?\u5ba1\u6838\u4eba' 'REVIEWER' $reasons)
                    [void](Get-LogicalField $text '\u76f4\u63a5\u5ba1\u6838\u95ed\u73af' 'DIRECT_REVIEW_LOOP' $reasons)
                    $currentActor = $summary.Groups['current'].Value
                    $nextActor = $summary.Groups['next'].Value
                    $notifier = $summary.Groups['notifier'].Value
                    if ($null -ne $currentActorField -and $currentActorField.Trim('`') -cne $currentActor) {
                        Add-Reason $reasons 'CURRENT_ACTOR_FIELD_MISMATCH'
                    }
                    if ($null -ne $nextActorField -and $nextActorField.Trim('`') -cne $nextActor) {
                        Add-Reason $reasons 'NEXT_ACTOR_FIELD_MISMATCH'
                    }
                    if ($null -ne $notifierField -and $notifierField.Trim('`') -cne $notifier) {
                        Add-Reason $reasons 'REVIEW_START_NOTIFIER_FIELD_MISMATCH'
                    }
                    Test-ActorAndNotifier $text $statusField $currentActor $nextActor $notifier $reasons
                }
            }
        }

        if ($criticalSummary.Success -or $compatibilityMode) {
            $currentExactText = $summary.Groups['exact'].Value
            $currentExact = [int64]0
            if ($currentExactText -notmatch '^[1-9][0-9]*$' -or -not [int64]::TryParse($currentExactText, [ref]$currentExact)) {
                Add-Reason $reasons 'CURRENT_EXACT_VALUE'
            }
            if ($currentExact -ne $expectedPaths.Count) {
                Add-Reason $reasons 'CURRENT_EXACT_EXPECTED_PATH_COUNT_MISMATCH'
            }

            [void](Get-LogicalField $text '(?:\u72ec\u7acb)?\u5ba1\u6838\u4eba' 'REVIEWER' $reasons)
            [void](Get-LogicalField $text 'Git\s*\u6536\u53e3\u8005' 'GIT_CLOSER' $reasons)
            $currentActorField = Get-LogicalField $text '\u5f53\u524dactor' 'CURRENT_ACTOR' $reasons
            $nextActorField = Get-LogicalField $text '\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005' 'NEXT_ACTOR' $reasons
            $notifierField = Get-LogicalField $text 'Review\u5f00\u59cb\u901a\u77e5\u65b9' 'REVIEW_START_NOTIFIER' $reasons
            $currentActor = $summary.Groups['current'].Value
            $nextActor = $summary.Groups['next'].Value
            $notifier = $summary.Groups['notifier'].Value
            if ($null -ne $currentActorField -and $currentActorField.Trim('`') -cne $currentActor) {
                Add-Reason $reasons 'CURRENT_ACTOR_FIELD_MISMATCH'
            }
            if ($null -ne $nextActorField -and $nextActorField.Trim('`') -cne $nextActor) {
                Add-Reason $reasons 'NEXT_ACTOR_FIELD_MISMATCH'
            }
            if ($null -ne $notifierField -and $notifierField.Trim('`') -cne $notifier) {
                Add-Reason $reasons 'REVIEW_START_NOTIFIER_FIELD_MISMATCH'
            }
            Test-ActorAndNotifier $text $statusField $currentActor $nextActor $notifier $reasons

            $writerMatches = [regex]::Matches($text, '(?m)^-\s*\u5f53\u524d\u5199\u5165\u8005\s*\uFF1A\s*(?<value>.*?)\s*$')
            if ($writerMatches.Count -eq 1 -and $writerMatches[0].Groups['value'].Value -match '\u65e0.*\u91ca\u653e' -and $nextActor -eq 'EXECUTOR') {
                Add-Reason $reasons 'RELEASED_EXECUTOR_IS_NEXT_ACTOR'
            }
        }

        if ($null -ne $statusField) {
            $normalizedStatus = $statusField.Trim('`')
            $hasReviewStatus = $normalizedStatus -match '(?:^|[\s/])REVIEW(?:$|[\s/])'
            $hasClosedStatus = $normalizedStatus -match '(?:^|[\s/])CLOSED(?:$|[\s/])'
            if (($lifecycle -eq 'REVIEW' -and -not $hasReviewStatus) -or
                ($lifecycle -eq 'CLOSED' -and -not $hasClosedStatus) -or
                ($lifecycle -in @('ACTIVE_WRITE', 'ACTIVE') -and ($hasReviewStatus -or $hasClosedStatus))) {
                Add-Reason $reasons 'STATUS_LIFECYCLE_MISMATCH'
            }
        }

        $normalizedPath = $resolvedPath.Replace('\', '/').ToLowerInvariant()
        $isActivePath = $normalizedPath -match '/tasks/active/'
        $isArchivePath = $normalizedPath -match '/tasks/archive/'
        if (-not $isActivePath -and -not $isArchivePath) {
            Add-Reason $reasons 'TASK_LOCATION'
        }
        elseif ($lifecycle -eq 'CLOSED' -and -not $isArchivePath) {
            Add-Reason $reasons 'CLOSED_NOT_ARCHIVE'
        }
        elseif ($lifecycle -ne 'CLOSED' -and -not $isActivePath) {
            Add-Reason $reasons 'OPEN_NOT_ACTIVE'
        }

        if ($lifecycle -eq 'ACTIVE_WRITE') {
            Compare-NormalizedPathSets $expectedPaths $actualPaths $false 'DECLARED_PATH_MISSING' 'DECLARED_PATH_EXTRA' $reasons
        }
        else {
            Compare-NormalizedPathSets $expectedPaths $actualPaths $true 'DECLARED_PATH_MISSING' 'DECLARED_PATH_EXTRA' $reasons
        }

        if ($script:ObservedActualWasProvided) {
            $observedPaths = @(ConvertTo-NormalizedPathSet $script:ObservedActualPathValue 'OBSERVED_PATH' $true $reasons)
            Compare-NormalizedPathSets $actualPaths $observedPaths $true 'OBSERVED_PATH_MISSING' 'OBSERVED_PATH_EXTRA' $reasons
        }
    }

    if ($reasons.Count -gt 0) {
        $script:HasFailure = $true
        "FAIL|$displayName|$($reasons -join ',')"
    }
    else {
        "PASS|$displayName|OK"
    }
}

$script:ObservedActualWasProvided = $PSBoundParameters.ContainsKey('ObservedActualPath')
$script:ObservedActualPathValue = if ($script:ObservedActualWasProvided) {
    @($ObservedActualPath.Split('|'))
}
else {
    @()
}

if ($script:ObservedActualWasProvided -and $Path.Count -ne 1) {
    'FAIL|MULTI_CARD|OBSERVED_ACTUAL_REQUIRES_SINGLE_CARD'
    exit 1
}

foreach ($cardPath in $Path) {
    Test-TaskCard $cardPath
}

if ($script:HasFailure) {
    exit 1
}
