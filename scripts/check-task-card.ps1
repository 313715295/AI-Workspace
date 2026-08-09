[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [Alias('FullName')]
    [string[]]$Path,

    [Parameter()]
    [string]$ObservedActualPath
)

$script:HasFailure = $false
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$allowedActors = @('OWNER', 'EXECUTOR', 'REVIEWER', 'USER', 'EXTERNAL', 'NONE')

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
            [System.Collections.Generic.List[string]]$Reasons
        )

        $matches = [regex]::Matches(
            $Text,
            "(?m)^-\s*(?:$LabelPattern)\s*\uFF1A\s*(?<value>.*?)\s*$"
        )
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
            if ($bytes.Length -ge 3 -and
                $bytes[0] -eq 0xEF -and
                $bytes[1] -eq 0xBB -and
                $bytes[2] -eq 0xBF) {
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
            '(?m)^-\s*\u673a\u68b0\u6458\u8981\s*\uFF1A\s*(?<value>.*?)\s*$'
        )
        if ($summaryMatches.Count -eq 0) {
            if ($reasons.Count -gt 0) {
                $script:HasFailure = $true
                "FAIL|$displayName|$($reasons -join ',')"
            }
            else {
                "LEGACY_UNCHECKED|$displayName|MECHANICAL_SUMMARY_MISSING"
            }
            return
        }
        if ($summaryMatches.Count -ne 1) {
            Add-Reason $reasons 'MECHANICAL_SUMMARY_COUNT'
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
        $h1Matches = [regex]::Matches(
            $text,
            '(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)\s+.+$'
        )
        if ($h1Matches.Count -ne 1) {
            Add-Reason $reasons 'H1_TASK_ID_COUNT'
        }
        elseif ($h1Matches[0].Groups['id'].Value -cne $baseName) {
            Add-Reason $reasons 'H1_FILENAME_MISMATCH'
        }

        $statusField = Get-LogicalField $text '\u72b6\u6001' 'STATUS' $reasons
        [void](Get-LogicalField $text '\u552f\u4e00\u957f\u671fowner/\u8c03\u5ea6\u8005' 'OWNER' $reasons)
        [void](Get-LogicalField $text '(?:\u72ec\u7acb)?\u5ba1\u6838\u4eba' 'REVIEWER' $reasons)
        [void](Get-LogicalField $text 'Git\s*\u6536\u53e3\u8005' 'GIT_CLOSER' $reasons)
        [void](Get-LogicalField $text '\u5916\u90e8\u52a8\u4f5c\u6388\u6743' 'EXTERNAL_AUTH' $reasons)
        $currentActorField = Get-LogicalField $text '\u5f53\u524dactor' 'CURRENT_ACTOR' $reasons
        $nextActorField = Get-LogicalField $text '\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005' 'NEXT_ACTOR' $reasons
        $notifierField = Get-LogicalField $text 'Review\u5f00\u59cb\u901a\u77e5\u65b9' 'REVIEW_START_NOTIFIER' $reasons

        $nextActionCount = Get-NextActionCount $text $reasons
        if ($nextActionCount -ne 1) {
            Add-Reason $reasons 'NEXT_ACTION_COUNT'
        }

        $summaryText = $summaryMatches[0].Groups['value'].Value.Trim().Trim('`')
        $summary = [regex]::Match(
            $summaryText,
            '^lifecycle=(?<lifecycle>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED); current_actor=(?<current>[A-Z][A-Z0-9_]*); next_actor=(?<next>[A-Z][A-Z0-9_]*); current_exact=(?<exact>[^;]+); expected_paths=\[(?<expected>[^\]]*)\]; actual_paths=\[(?<actual>[^\]]*)\]; review_start_notifier=(?<notifier>[A-Z][A-Z0-9_]*)$'
        )
        if (-not $summary.Success) {
            Add-Reason $reasons 'MECHANICAL_SUMMARY_FORMAT'
        }
        else {
            $lifecycle = $summary.Groups['lifecycle'].Value
            $currentActor = $summary.Groups['current'].Value
            $nextActor = $summary.Groups['next'].Value
            $currentExactText = $summary.Groups['exact'].Value
            $currentExact = [int64]0
            if ($currentExactText -notmatch '^[1-9][0-9]*$' -or
                -not [int64]::TryParse($currentExactText, [ref]$currentExact)) {
                Add-Reason $reasons 'CURRENT_EXACT_VALUE'
            }
            $expectedRaw = $summary.Groups['expected'].Value
            $actualRaw = $summary.Groups['actual'].Value
            $expectedItems = if ($expectedRaw.Length -eq 0) { @() } else { @($expectedRaw.Split('|')) }
            $actualItems = if ($actualRaw.Length -eq 0) { @() } else { @($actualRaw.Split('|')) }
            $expectedPaths = @(ConvertTo-NormalizedPathSet $expectedItems 'EXPECTED_PATH' $false $reasons)
            $actualPaths = @(ConvertTo-NormalizedPathSet $actualItems 'ACTUAL_PATH' $true $reasons)
            $notifier = $summary.Groups['notifier'].Value

            if ($currentExact -ne $expectedPaths.Count) {
                Add-Reason $reasons 'CURRENT_EXACT_EXPECTED_PATH_COUNT_MISMATCH'
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

            if ($null -ne $currentActorField -and
                $currentActorField.Trim('`') -cne $currentActor) {
                Add-Reason $reasons 'CURRENT_ACTOR_FIELD_MISMATCH'
            }
            if ($null -ne $nextActorField -and
                $nextActorField.Trim('`') -cne $nextActor) {
                Add-Reason $reasons 'NEXT_ACTOR_FIELD_MISMATCH'
            }
            if ($null -ne $notifierField -and
                $notifierField.Trim('`') -cne $notifier) {
                Add-Reason $reasons 'REVIEW_START_NOTIFIER_FIELD_MISMATCH'
            }

            if ($allowedActors -notcontains $currentActor) {
                Add-Reason $reasons 'CURRENT_ACTOR_VALUE'
            }
            if ($allowedActors -notcontains $nextActor) {
                Add-Reason $reasons 'NEXT_ACTOR_VALUE'
            }
            if ($currentActor -ne $nextActor -and
                $nextActor -notin @('USER', 'EXTERNAL')) {
                Add-Reason $reasons 'ACTOR_NEXT_MISMATCH'
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

            $ownerMediatedStopline = $false
            if ($null -ne $statusField) {
                $statusTokens = @($statusField.Trim('`').Split('/') | ForEach-Object { $_.Trim() })
                foreach ($statusToken in $statusTokens) {
                    if ($statusToken -in @('DIRECT_LOOP_STOPPED', 'RANGE_GATE_REQUIRED', 'OWNER_MEDIATED_REVIEW') -or
                        $statusToken -match '^OWNER_FOCUSED_REVIEW(?:_[A-Z0-9]+)*$') {
                        $ownerMediatedStopline = $true
                        break
                    }
                }
            }
            if ($notifier -eq 'REVIEWER') {
                if ($currentActor -ne 'REVIEWER' -or $nextActor -ne 'REVIEWER') {
                    Add-Reason $reasons 'REVIEWER_NOTIFIER_REQUIRES_REVIEWER_ACTOR'
                }
                if ($text -notmatch '\u65e0\u6267\u884c\u8005' -or
                    $text -notmatch '\u7a33\u5b9a\u5bf9\u8c61') {
                    Add-Reason $reasons 'REVIEWER_NOTIFIER_REQUIRES_NO_EXECUTOR_STABLE_OBJECT'
                }
            }
            elseif ($notifier -eq 'NONE') {
                if ($currentActor -ne 'OWNER' -or $nextActor -ne 'OWNER') {
                    Add-Reason $reasons 'NONE_NOTIFIER_REQUIRES_OWNER_ACTOR'
                }
                if (-not $ownerMediatedStopline) {
                    Add-Reason $reasons 'NONE_NOTIFIER_REQUIRES_OWNER_MEDIATED_STOPLINE'
                }
            }
            elseif ($notifier -eq 'EXECUTOR') {
                if ($currentActor -eq 'OWNER' -and $nextActor -eq 'OWNER' -and $ownerMediatedStopline) {
                    Add-Reason $reasons 'OWNER_MEDIATED_STOPLINE_REQUIRES_NONE_NOTIFIER'
                }
            }
            else {
                Add-Reason $reasons 'REVIEW_START_NOTIFIER_VALUE'
            }

            $writerMatches = [regex]::Matches(
                $text,
                '(?m)^-\s*\u5f53\u524d\u5199\u5165\u8005\s*\uFF1A\s*(?<value>.*?)\s*$'
            )
            if ($writerMatches.Count -eq 1 -and
                $writerMatches[0].Groups['value'].Value -match '\u65e0.*\u91ca\u653e' -and
                $nextActor -eq 'EXECUTOR') {
                Add-Reason $reasons 'RELEASED_EXECUTOR_IS_NEXT_ACTOR'
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
