[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$WorkspaceRoot,
    [Parameter(Mandatory)][string]$FrameworkVersion,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$Provisional,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw 'POWERSHELL7_REQUIRED'
}
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}
$workspace = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $WorkspaceRoot)))
$versionRoot = Join-Path $workspace ('framework/versions/' + $FrameworkVersion)
if (-not (Test-Path -LiteralPath $versionRoot -PathType Container)) {
    throw 'FRAMEWORK_VERSION_MISSING'
}
if ($FrameworkVersion -cnotmatch '^\d+\.\d+\.\d+$') {
    throw 'FRAMEWORK_VERSION_INVALID'
}

function Get-ReleasePayloadFacts([string]$Root, [string]$ExcludedManifestPath) {
    [string[]]$payload = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object { [IO.Path]::GetFullPath($_.FullName) -cne [IO.Path]::GetFullPath($ExcludedManifestPath) } |
        ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\', '/') })
    [Array]::Sort($payload, [StringComparer]::Ordinal)
    $rows = [Collections.Generic.List[string]]::new()
    [int64]$totalBytes = 0
    foreach ($relative in $payload) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $Root $relative))
        $totalBytes += $bytes.Length
        $identity = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        $rows.Add($relative + '|' + $bytes.Length + '|' + $identity)
    }
    $canonicalBytes = [Text.UTF8Encoding]::new($false).GetBytes([string]::Join("`n", $rows))
    [pscustomobject]@{
        FileCount = $payload.Count
        TotalBytes = $totalBytes
        Canonical = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($canonicalBytes))
    }
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Test-Identity([object]$Value) {
    return $Value -is [string] -and [string]$Value -cmatch '^\d+\|[A-F0-9]{64}$'
}

function Assert-ExactJsonObjectFields([Text.Json.JsonElement]$Element, [string[]]$Expected) {
    if ($Element.ValueKind -cne [Text.Json.JsonValueKind]::Object) { throw 'JSON_OBJECT_REQUIRED' }
    $names = @($Element.EnumerateObject() | ForEach-Object { $_.Name })
    if ($names.Count -ne $Expected.Count -or @($names | Select-Object -Unique).Count -ne $names.Count -or
        @($Expected | Where-Object { $_ -cnotin $names }).Count -ne 0) {
        throw 'JSON_FIELD_SET_MISMATCH'
    }
}

$manifestPath = Join-Path $versionRoot 'RELEASE_MANIFEST.json'
$manifestRaw = [IO.File]::ReadAllText($manifestPath, [Text.UTF8Encoding]::new($false, $true))
$manifest = $manifestRaw | ConvertFrom-Json
$versionPath = Join-Path $versionRoot 'VERSION.json'
$versionRaw = [IO.File]::ReadAllText($versionPath, [Text.UTF8Encoding]::new($false, $true))
$version = $versionRaw | ConvertFrom-Json
if ([string]$manifest.version -cne $FrameworkVersion -or
    [string]$version.version -cne $FrameworkVersion -or
    [string]$manifest.lifecycle -cne [string]$version.lifecycle) {
    throw 'FRAMEWORK_MANIFEST_VERSION'
}
$gateError = if ($Provisional) { 'PROVISIONAL_PACKAGE_REVIEW_REQUIRED' } else { 'STABLE_PACKAGE_REQUIRED' }
try {
    $document = [Text.Json.JsonDocument]::Parse($manifestRaw)
    try {
        Assert-ExactJsonObjectFields $document.RootElement @('schemaVersion','version','lifecycle','releaseClass','scope','algorithm','fileCount','totalBytes','canonical','baseline','sourceReview','sourceCandidate','releaseIntegration','completeSuite','sourceReviewEvidence')
        Assert-ExactJsonObjectFields ($document.RootElement.GetProperty('completeSuite')) @('status','passed','total','payloadCanonical','evidenceIdentity')
        Assert-ExactJsonObjectFields ($document.RootElement.GetProperty('sourceReviewEvidence')) @('status','reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity')
    }
    finally { $document.Dispose() }
}
catch { throw $gateError }
$releaseFacts = Get-ReleasePayloadFacts $versionRoot $manifestPath
if ([int]$manifest.fileCount -ne $releaseFacts.FileCount -or
    [int64]$manifest.totalBytes -ne $releaseFacts.TotalBytes -or
    [string]$manifest.canonical -cne $releaseFacts.Canonical) {
    throw 'FRAMEWORK_RELEASE_PAYLOAD_DRIFT'
}
$suite = $manifest.completeSuite
$review = $manifest.sourceReviewEvidence
$commonEvidenceValid =
    (Test-JsonInteger $manifest.schemaVersion) -and [int64]$manifest.schemaVersion -eq 2 -and
    $manifest.version -is [string] -and [string]$manifest.version -ceq $FrameworkVersion -and
    $manifest.lifecycle -is [string] -and $manifest.sourceReview -is [string] -and [string]$manifest.sourceReview -ceq 'APPROVED' -and
    $manifest.sourceCandidate -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.sourceCandidate) -and [string]$manifest.sourceCandidate -cne 'PENDING' -and
    $manifest.releaseIntegration -is [string] -and
    (Test-JsonInteger $manifest.fileCount) -and [int64]$manifest.fileCount -eq [int64]$releaseFacts.FileCount -and
    (Test-JsonInteger $manifest.totalBytes) -and [int64]$manifest.totalBytes -eq [int64]$releaseFacts.TotalBytes -and
    $manifest.canonical -is [string] -and [string]$manifest.canonical -ceq $releaseFacts.Canonical -and
    $suite -is [pscustomobject] -and $suite.status -is [string] -and [string]$suite.status -ceq 'PASS' -and
    (Test-JsonInteger $suite.passed) -and (Test-JsonInteger $suite.total) -and [int64]$suite.passed -ge 1 -and [int64]$suite.passed -eq [int64]$suite.total -and
    $suite.payloadCanonical -is [string] -and [string]$suite.payloadCanonical -ceq $releaseFacts.Canonical -and (Test-Identity $suite.evidenceIdentity) -and
    $review -is [pscustomobject] -and $review.status -is [string] -and [string]$review.status -ceq 'APPROVED' -and
    $review.reviewer -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$review.reviewer) -and [string]$review.reviewer -cnotin @('NONE','PENDING') -and
    (Test-Identity $review.packageIdentity) -and $review.reviewedPayloadCanonical -is [string] -and
    [string]$review.reviewedPayloadCanonical -ceq $releaseFacts.Canonical -and (Test-Identity $review.reviewedManifestIdentity)
$modeEvidenceValid = if ($Provisional) {
    [string]$manifest.lifecycle -ceq 'CANDIDATE' -and
    $version.consumable -is [bool] -and -not [bool]$version.consumable -and
    $version.projectPinEligible -is [bool] -and -not [bool]$version.projectPinEligible -and
    [string]$manifest.releaseIntegration -ceq 'PENDING'
}
else {
    [string]$manifest.lifecycle -ceq 'STABLE' -and
    $version.consumable -is [bool] -and [bool]$version.consumable -and
    $version.projectPinEligible -is [bool] -and [bool]$version.projectPinEligible -and
    -not [string]::IsNullOrWhiteSpace([string]$manifest.releaseIntegration) -and [string]$manifest.releaseIntegration -cne 'PENDING'
}
if (-not $commonEvidenceValid -or -not $modeEvidenceValid) {
    throw $gateError
}

$rootFiles = @(
    'AGENTS.md',
    'INITIALIZATION.md',
    'LICENSE',
    'README.md',
    'framework/PROJECT_ADOPTION.md',
    'scripts/MaintenanceOverlay.psm1',
    'scripts/ProjectAdoptionProjection.psm1',
    'scripts/ProjectAdoptionState.psm1',
    'scripts/ProjectAdoptionTransaction.psm1',
    'scripts/register-project.ps1',
    'scripts/upgrade-project.ps1',
    'skills/ai-workspace-router/SKILL.md'
)
$relativeFiles = [Collections.Generic.List[string]]::new()
foreach ($relative in $rootFiles) {
    $path = Join-Path $workspace $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('PACKAGE_DEPENDENCY_MISSING|' + $relative)
    }
    $relativeFiles.Add($relative)
}
foreach ($file in @(Get-ChildItem -LiteralPath $versionRoot -Recurse -File -Force)) {
    $relative = [IO.Path]::GetRelativePath($workspace, $file.FullName).Replace('\', '/')
    $relativeFiles.Add($relative)
}
$files = @($relativeFiles | Sort-Object -Unique)
$records = [Collections.Generic.List[object]]::new()
foreach ($relative in $files) {
    if ($relative.StartsWith('.git/', [StringComparison]::OrdinalIgnoreCase) -or
        $relative.Contains('/runtime/', [StringComparison]::OrdinalIgnoreCase)) {
        throw ('PACKAGE_PATH_FORBIDDEN|' + $relative)
    }
    $path = Join-Path $workspace $relative
    $bytes = [IO.File]::ReadAllBytes($path)
    $identity = $bytes.Length.ToString() + '|' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $records.Add([ordered]@{ path = $relative; identity = $identity })
}
$canonicalText = (@($records | ForEach-Object { [string]$_.path + '=' + [string]$_.identity }) -join [char]10) + [char]10
$canonical = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonicalText)))
$packageManifest = [ordered]@{
    schemaVersion = 1
    frameworkVersion = $FrameworkVersion
    provisional = [bool]$Provisional
    canonical = $canonical
    files = @($records)
}
$outputFull = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($outputFull) -cne '.zip') {
    throw 'PACKAGE_OUTPUT_EXTENSION'
}
$result = [pscustomobject]@{
    status = if ($Apply) { 'READY_TO_WRITE' } else { 'WHAT_IF' }
    frameworkVersion = $FrameworkVersion
    provisional = [bool]$Provisional
    canonical = $canonical
    fileCount = $files.Count
    outputPath = $outputFull
}
if (-not $Apply -or -not $PSCmdlet.ShouldProcess($outputFull, 'Build ordinary-user Framework package')) {
    return $result
}
if (Test-Path -LiteralPath $outputFull) {
    throw 'PACKAGE_OUTPUT_EXISTS'
}
$outputParent = Split-Path -Parent $outputFull
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outputParent
}
$stage = Join-Path ([IO.Path]::GetTempPath()) ('aiw-user-package-' + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $stage
    foreach ($relative in $files) {
        $destination = Join-Path $stage $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $parent -Force
        }
        [IO.File]::Copy((Join-Path $workspace $relative), $destination, $false)
    }
    [IO.File]::WriteAllText(
        (Join-Path $stage 'PACKAGE_MANIFEST.json'),
        ($packageManifest | ConvertTo-Json -Depth 100 -Compress) + [char]10,
        [Text.UTF8Encoding]::new($false)
    )
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $outputFull, [IO.Compression.CompressionLevel]::Optimal, $false)
}
finally {
    if (Test-Path -LiteralPath $stage -PathType Container) {
        [IO.Directory]::Delete($stage, $true)
    }
}
$result.status = 'CREATED'
$result
