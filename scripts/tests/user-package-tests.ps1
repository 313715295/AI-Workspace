[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$builder = Join-Path $workspace 'scripts/build-user-package.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('aiw-package-test-' + [guid]::NewGuid().ToString('N'))
$zip = Join-Path $fixture 'AI-Workspace-1.16.0.zip'
$extract = Join-Path $fixture 'extract'
$passed = 0

function Write-Utf8Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-ReleasePayloadFacts([string]$Root, [string]$ManifestPath) {
    [string[]]$payload = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object { [IO.Path]::GetFullPath($_.FullName) -cne [IO.Path]::GetFullPath($ManifestPath) } |
        ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\', '/') })
    [Array]::Sort($payload, [StringComparer]::Ordinal)
    $rows = [Collections.Generic.List[string]]::new()
    [int64]$totalBytes = 0
    foreach ($relative in $payload) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $Root $relative))
        $totalBytes += $bytes.Length
        $rows.Add($relative + '|' + $bytes.Length + '|' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))
    }
    $canonical = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes([string]::Join("`n", $rows))))
    [pscustomobject]@{ FileCount = $payload.Count; TotalBytes = $totalBytes; Canonical = $canonical }
}

function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('ASSERT_FAIL|' + $Name) }
    $script:passed++
}

function Assert-Rejected([scriptblock]$Action, [string]$ExpectedReason, [string]$Name) {
    $actual = ''
    try { & $Action | Out-Null }
    catch { $actual = [string]$_.Exception.Message }
    Assert-True ($actual.Contains($ExpectedReason, [StringComparison]::Ordinal)) $Name
}

try {
    $null = New-Item -ItemType Directory -Path $fixture
    $packageWorkspace = Join-Path $fixture 'workspace'
    foreach ($relative in @('AGENTS.md','INITIALIZATION.md','LICENSE','README.md','framework/PROJECT_ADOPTION.md','scripts/MaintenanceOverlay.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionTransaction.psm1','scripts/register-project.ps1','scripts/upgrade-project.ps1','skills/ai-workspace-router/SKILL.md')) {
        $destination = Join-Path $packageWorkspace $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        [IO.File]::Copy((Join-Path $workspace $relative), $destination, $false)
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $packageWorkspace 'framework/versions') -Force
    Copy-Item -LiteralPath (Join-Path $workspace 'framework/versions/1.16.0') -Destination (Join-Path $packageWorkspace 'framework/versions/1.16.0') -Recurse
    $fixtureManifestPath = Join-Path $packageWorkspace 'framework/versions/1.16.0/RELEASE_MANIFEST.json'
    $fixtureVersionRoot = Split-Path -Parent $fixtureManifestPath
    $fixtureManifest = Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureManifestPath | ConvertFrom-Json
    $facts = Get-ReleasePayloadFacts $fixtureVersionRoot $fixtureManifestPath
    $fixtureManifest.fileCount = $facts.FileCount
    $fixtureManifest.totalBytes = $facts.TotalBytes
    $fixtureManifest.canonical = $facts.Canonical
    $fixtureManifest.sourceReview = 'APPROVED'
    $fixtureManifest.completeSuite.status = 'PASS'
    $fixtureManifest.completeSuite.passed = 1
    $fixtureManifest.completeSuite.total = 1
    $fixtureManifest.completeSuite.payloadCanonical = $facts.Canonical
    $fixtureManifest.completeSuite.evidenceIdentity = '1|' + ('A' * 64)
    $fixtureManifest.sourceReviewEvidence.status = 'APPROVED'
    $fixtureManifest.sourceReviewEvidence.reviewer = 'fixture-reviewer'
    $fixtureManifest.sourceReviewEvidence.packageIdentity = '1|' + ('B' * 64)
    $fixtureManifest.sourceReviewEvidence.reviewedPayloadCanonical = $facts.Canonical
    $fixtureManifest.sourceReviewEvidence.reviewedManifestIdentity = '1|' + ('C' * 64)
    $fixtureManifest.releaseIntegration = 'PENDING'
    Write-Utf8Json $fixtureManifestPath $fixtureManifest
    $validManifestRaw = [IO.File]::ReadAllText($fixtureManifestPath, [Text.UTF8Encoding]::new($false, $true))
    $fixtureVersionPath = Join-Path $fixtureVersionRoot 'VERSION.json'
    $validVersionRaw = [IO.File]::ReadAllText($fixtureVersionPath, [Text.UTF8Encoding]::new($false, $true))

    $case = $validManifestRaw | ConvertFrom-Json
    $case.completeSuite.total = 2
    Write-Utf8Json $fixtureManifestPath $case
    Assert-Rejected { & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip -Provisional } 'PROVISIONAL_PACKAGE_REVIEW_REQUIRED' 'suite-count-mismatch-rejected'

    $case = $validManifestRaw | ConvertFrom-Json
    $case.completeSuite.evidenceIdentity = 'PENDING'
    Write-Utf8Json $fixtureManifestPath $case
    Assert-Rejected { & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip -Provisional } 'PROVISIONAL_PACKAGE_REVIEW_REQUIRED' 'suite-evidence-identity-rejected'

    $case = $validManifestRaw | ConvertFrom-Json
    $case.sourceReviewEvidence.reviewer = 'PENDING'
    Write-Utf8Json $fixtureManifestPath $case
    Assert-Rejected { & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip -Provisional } 'PROVISIONAL_PACKAGE_REVIEW_REQUIRED' 'pending-reviewer-rejected'

    $case = $validManifestRaw | ConvertFrom-Json
    $case.sourceReviewEvidence.packageIdentity = 'PENDING'
    Write-Utf8Json $fixtureManifestPath $case
    Assert-Rejected { & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip -Provisional } 'PROVISIONAL_PACKAGE_REVIEW_REQUIRED' 'pending-review-package-identity-rejected'

    $case = $validManifestRaw | ConvertFrom-Json
    $case.sourceReviewEvidence.reviewedManifestIdentity = 'PENDING'
    Write-Utf8Json $fixtureManifestPath $case
    Assert-Rejected { & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip -Provisional } 'PROVISIONAL_PACKAGE_REVIEW_REQUIRED' 'pending-reviewed-manifest-identity-rejected'

    $stableVersion = $validVersionRaw | ConvertFrom-Json
    $stableVersion.lifecycle = 'STABLE'
    $stableVersion.consumable = $true
    $stableVersion.projectPinEligible = $true
    Write-Utf8Json $fixtureVersionPath $stableVersion
    $stable = $validManifestRaw | ConvertFrom-Json
    $stable.lifecycle = 'STABLE'
    $stableFacts = Get-ReleasePayloadFacts $fixtureVersionRoot $fixtureManifestPath
    $stable.fileCount = $stableFacts.FileCount
    $stable.totalBytes = $stableFacts.TotalBytes
    $stable.canonical = $stableFacts.Canonical
    $stable.completeSuite.payloadCanonical = $stableFacts.Canonical
    $stable.sourceReviewEvidence.reviewedPayloadCanonical = $stableFacts.Canonical
    $stable.releaseIntegration = 'PENDING'
    Write-Utf8Json $fixtureManifestPath $stable
    Assert-Rejected { & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip } 'STABLE_PACKAGE_REQUIRED' 'stable-release-integration-required'

    [IO.File]::WriteAllText($fixtureVersionPath, $validVersionRaw, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($fixtureManifestPath, $validManifestRaw, [Text.UTF8Encoding]::new($false))

    $preview = & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip -Provisional
    Assert-True ($preview.status -ceq 'WHAT_IF' -and -not (Test-Path -LiteralPath $zip)) 'preview-zero-write'

    $created = & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $zip -Provisional -Apply -Confirm:$false
    Assert-True ($created.status -ceq 'CREATED' -and (Test-Path -LiteralPath $zip -PathType Leaf)) 'provisional-package-created'

    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
    $manifestPath = Join-Path $extract 'PACKAGE_MANIFEST.json'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $allMatch = $true
    foreach ($record in @($manifest.files)) {
        $path = Join-Path $extract ([string]$record.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $allMatch = $false; break }
        $bytes = [IO.File]::ReadAllBytes($path)
        $identity = $bytes.Length.ToString() + '|' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        if ($identity -cne [string]$record.identity) { $allMatch = $false; break }
    }
    Assert-True ($allMatch) 'package-manifest-identities-match'
    Assert-True (
        -not (Test-Path -LiteralPath (Join-Path $extract '.git')) -and
        -not (Test-Path -LiteralPath (Join-Path $extract '.ai-workspace')) -and
        (Test-Path -LiteralPath (Join-Path $extract 'framework/versions/1.16.0')) -and
        @(Get-ChildItem -LiteralPath (Join-Path $extract 'framework/versions') -Directory).Count -eq 1
    ) 'package-whitelist-excludes-repository-state-and-old-versions'
    Assert-True (
        (Test-Path -LiteralPath (Join-Path $extract 'scripts/register-project.ps1')) -and
        (Test-Path -LiteralPath (Join-Path $extract 'scripts/upgrade-project.ps1')) -and
        (Test-Path -LiteralPath (Join-Path $extract 'skills/ai-workspace-router/SKILL.md'))
    ) 'package-includes-user-entrypoints'

    Write-Output ('PASS|user-package-tests|' + $passed + '/' + $passed)
}
finally {
    if (Test-Path -LiteralPath $fixture -PathType Container) {
        [IO.Directory]::Delete($fixture, $true)
    }
}
