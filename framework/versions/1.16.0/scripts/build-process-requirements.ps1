[CmdletBinding()]
param(
    [string]$VersionRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Write,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) { Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'; exit 4 }
if (-not $Write -and -not $Check) { $Check = $true }
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-NoDuplicateJsonMembers($Element) {
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add([string]$property.Name)) { throw ('JSON_DUPLICATE_FIELD|' + [string]$property.Name) }
            Assert-NoDuplicateJsonMembers $property.Value
        }
    } elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-NoDuplicateJsonMembers $item }
    }
}

function Read-StrictJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('FILE_MISSING|' + $Path) }
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw ('TEXT_BOM|' + $Path) }
    $text = $utf8.GetString($bytes)
    if ($text.Contains("`r") -or -not $text.EndsWith("`n")) { throw ('TEXT_FORMAT|' + $Path) }
    $options = [Text.Json.JsonDocumentOptions]::new(); $options.AllowTrailingCommas = $false; $options.CommentHandling = [Text.Json.JsonCommentHandling]::Disallow
    $doc = [Text.Json.JsonDocument]::Parse($text, $options)
    try { Assert-NoDuplicateJsonMembers $doc.RootElement } finally { $doc.Dispose() }
    return $text | ConvertFrom-Json -Depth 100
}

function Read-StrictText([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('FILE_MISSING|' + $Path) }
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw ('TEXT_BOM|' + $Path) }
    $text = $utf8.GetString($bytes)
    if ($text.Contains("`r") -or -not $text.EndsWith("`n")) { throw ('TEXT_FORMAT|' + $Path) }
    return $text
}

function Assert-ExactFields($Object, [string[]]$Fields, [string]$Label) {
    if (-not ($Object -is [pscustomobject])) { throw ($Label + '_OBJECT') }
    $actual = @($Object.PSObject.Properties.Name)
    if ($actual.Count -ne $Fields.Count -or @($Fields | Where-Object { $_ -cnotin $actual }).Count -ne 0) { throw ($Label + '_FIELDS') }
}

function Assert-StringArray($Value, [string]$Label) {
    if (-not ($Value -is [Array])) { throw ($Label + '_ARRAY') }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in @($Value)) {
        if (-not ($item -is [string]) -or [string]::IsNullOrWhiteSpace([string]$item) -or -not $seen.Add([string]$item)) { throw ($Label + '_ITEM') }
    }
}

function Get-OrdinalSortedStrings([string[]]$Values) {
    $copy = [string[]]@($Values)
    [Array]::Sort($copy, [StringComparer]::Ordinal)
    return @($copy)
}

try {
    $root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $VersionRoot))
    $compositionModule=Import-Module (Join-Path $root 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru
    $version = Read-StrictJson (Join-Path $root 'VERSION.json')
    if ([string]$version.version -cne '1.16.0') { throw 'VERSION_MISMATCH' }
    $manifest = Read-StrictJson (Join-Path $root 'LOAD_MANIFEST.json')
    if ($null -eq $manifest.PSObject.Properties['requirementFragments'] -or -not ($manifest.requirementFragments -is [Array])) { throw 'LOAD_MANIFEST_REQUIREMENT_FRAGMENTS' }
    $expectedSidecars = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $expectedOwners = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $requirements = @()
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($manifest.requirementFragments)) {
        Assert-ExactFields $entry @('ownerModule','sidecar') 'REQUIREMENT_FRAGMENT_ENTRY'
        $owner = [string]$entry.ownerModule; $sidecar = [string]$entry.sidecar
        if ($owner -cnotmatch '^[A-Z0-9_]+\.md$' -or $sidecar -cnotmatch '^requirements/fragments/[A-Z0-9_]+\.json$' -or -not $expectedSidecars.Add($sidecar) -or -not $expectedOwners.Add($owner)) { throw 'REQUIREMENT_FRAGMENT_ENTRY_VALUES' }
        $ownerPath = Join-Path $root $owner
        if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) { throw ('REQUIREMENT_OWNER_MODULE_MISSING|' + $owner) }
        $ownerText = Read-StrictText $ownerPath
        $fragment = Read-StrictJson (Join-Path $root $sidecar)
        Assert-ExactFields $fragment @('schemaVersion','frameworkVersion','ownerModule','requirements') 'REQUIREMENT_FRAGMENT'
        if ([int]$fragment.schemaVersion -ne 2 -or [string]$fragment.frameworkVersion -cne '1.16.0' -or [string]$fragment.ownerModule -cne $owner -or -not ($fragment.requirements -is [Array])) { throw 'REQUIREMENT_FRAGMENT_VALUES' }
        $ownerIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($rule in @($fragment.requirements)) {
            Assert-ExactFields $rule @('requirementId','legacyAliases','title','description','selectors','exactBlockLocator','preparationRequirements','resultRequirements') 'REQUIREMENT_RULE'
            if ([string]$rule.requirementId -cnotmatch '^PR_[A-Z0-9_]+$' -or -not $ids.Add([string]$rule.requirementId)) { throw 'REQUIREMENT_ID' }
            foreach ($field in @('title','description','exactBlockLocator')) { if (-not ($rule.$field -is [string]) -or [string]::IsNullOrWhiteSpace([string]$rule.$field)) { throw ('REQUIREMENT_TEXT|' + $field) } }
            $locator = [string]$rule.exactBlockLocator
            if ($locator -cne ('AIW-REQUIREMENT:' + [string]$rule.requirementId)) { throw ('REQUIREMENT_LOCATOR|' + [string]$rule.requirementId) }
            $beginMarker = '<!-- ' + $locator + ':BEGIN -->'
            $endMarker = '<!-- ' + $locator + ':END -->'
            $begin = $ownerText.IndexOf($beginMarker, [StringComparison]::Ordinal)
            $end = $ownerText.IndexOf($endMarker, [StringComparison]::Ordinal)
            if ($begin -lt 0 -or $end -le $begin -or $ownerText.IndexOf($beginMarker, $begin + 1, [StringComparison]::Ordinal) -ge 0 -or $ownerText.IndexOf($endMarker, $end + 1, [StringComparison]::Ordinal) -ge 0) { throw ('REQUIREMENT_BLOCK_CARDINALITY|' + [string]$rule.requirementId) }
            $bodyStart = $begin + $beginMarker.Length
            if ($bodyStart -ge $ownerText.Length -or $ownerText[$bodyStart] -cne "`n" -or $end -le $bodyStart + 1 -or $ownerText[$end - 1] -cne "`n") { throw ('REQUIREMENT_BLOCK_LAYOUT|' + [string]$rule.requirementId) }
            $blockText = $ownerText.Substring($bodyStart + 1, $end - $bodyStart - 2)
            if ([string]::IsNullOrWhiteSpace($blockText) -or $blockText.Contains('<!-- AIW-REQUIREMENT:')) { throw ('REQUIREMENT_BLOCK_BODY|' + [string]$rule.requirementId) }
            [void]$ownerIds.Add([string]$rule.requirementId)
            Assert-StringArray $rule.legacyAliases 'REQUIREMENT_ALIASES'
            Assert-StringArray $rule.preparationRequirements 'REQUIREMENT_PREPARATION'
            Assert-StringArray $rule.resultRequirements 'REQUIREMENT_RESULT'
            & $compositionModule { param($selectors) Assert-AiwSelectorContract $selectors 'REQUIREMENT_SELECTORS' } $rule.selectors
            $requirements += [ordered]@{
                requirementId = [string]$rule.requirementId
                legacyAliases = @($rule.legacyAliases)
                title = [string]$rule.title
                description = [string]$rule.description
                ownerModule = $owner
                selectors = $rule.selectors
                exactBlockLocator = $locator
                preparationRequirements = @($rule.preparationRequirements)
                resultRequirements = @($rule.resultRequirements)
            }
        }
        $markerMatches = [regex]::Matches($ownerText, '<!-- AIW-REQUIREMENT:(?<id>PR_[A-Z0-9_]+):(?<edge>BEGIN|END) -->')
        $markerCounts = @{}
        foreach ($match in $markerMatches) {
            $markerId = [string]$match.Groups['id'].Value
            if (-not $markerCounts.ContainsKey($markerId)) { $markerCounts[$markerId] = [ordered]@{BEGIN=0;END=0} }
            $markerCounts[$markerId][[string]$match.Groups['edge'].Value]++
        }
        if ($markerCounts.Count -ne $ownerIds.Count) { throw ('REQUIREMENT_BLOCK_ORPHAN|' + $owner) }
        foreach ($markerId in @($markerCounts.Keys)) {
            if (-not $ownerIds.Contains([string]$markerId) -or [int]$markerCounts[$markerId].BEGIN -ne 1 -or [int]$markerCounts[$markerId].END -ne 1) { throw ('REQUIREMENT_BLOCK_ORPHAN|' + $owner + '|' + [string]$markerId) }
        }
    }
    $actualSidecars = Get-OrdinalSortedStrings @(Get-ChildItem -LiteralPath (Join-Path $root 'requirements\fragments') -File -Filter '*.json' | ForEach-Object { 'requirements/fragments/' + $_.Name })
    if ([string]::Join("`n", (Get-OrdinalSortedStrings @($expectedSidecars))) -cne [string]::Join("`n", $actualSidecars)) { throw 'REQUIREMENT_FRAGMENT_ORPHAN_OR_MISSING' }
    $requirementsById=@{};foreach($item in $requirements){$requirementsById[[string]$item.requirementId]=$item}
    $orderedRequirements=@();foreach($id in (Get-OrdinalSortedStrings @($requirementsById.Keys))){$orderedRequirements+=$requirementsById[$id]}
    $projection = [ordered]@{schemaVersion=2;frameworkVersion='1.16.0';catalogVersion='3';requirements=@($orderedRequirements)}
    $text = ($projection | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n") + "`n"
    $catalogPath = Join-Path $root 'PROCESS_REQUIREMENTS.json'
    if ($Write) { [IO.File]::WriteAllText($catalogPath, $text, [Text.UTF8Encoding]::new($false)) }
    if ($Check) {
        if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf) -or [IO.File]::ReadAllText($catalogPath, $utf8) -cne $text) { throw 'PROCESS_REQUIREMENTS_PROJECTION_DRIFT' }
    }
    Write-Output ('PASS|requirements=' + $requirements.Count + '|fragments=' + $expectedSidecars.Count)
} catch {
    Write-Output ('FAIL|' + [string]$_.Exception.Message)
    exit 2
}
