[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$builder = Join-Path $workspace 'scripts/build-user-package.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('aiw-package-test-' + [guid]::NewGuid().ToString('N'))
$zip = Join-Path $fixture 'AI-Workspace-1.16.0.zip'
$extract = Join-Path $fixture 'extract'
$stableZip = Join-Path $fixture 'AI-Workspace-1.16.0-stable.zip'
$stableExtract = Join-Path $fixture 'stable-extract'
$candidateConsumer = Join-Path $fixture 'candidate-consumer'
$stableConsumer = Join-Path $fixture 'stable-consumer'
$passed = 0

function Write-Utf8Json([string]$Path, $Value) {
    $json = (($Value | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")).TrimEnd([char]10) + "`n"
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
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

function Get-StatusResult([object[]]$Output, [string]$ExpectedStatus) {
    @($Output | Where-Object {
        $_ -is [pscustomobject] -and
        $null -ne $_.PSObject.Properties['status'] -and
        [string]$_.status -ceq $ExpectedStatus
    })
}

function Remove-TestFixture([string]$Path) {
    $temp = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    $full = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        -not $full.StartsWith($temp + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFileName($full).StartsWith('aiw-package-test-', [StringComparison]::Ordinal)) {
        throw ('TEST_FIXTURE_CLEANUP_BOUNDARY|' + $full)
    }
    [IO.Directory]::Delete($full, $true)
}

try {
    $null = New-Item -ItemType Directory -Path $fixture
    $packageWorkspace = Join-Path $fixture 'workspace'
    foreach ($relative in @('LICENSE','framework/user-package/README.md','framework/user-package/AGENTS.md','scripts/MaintenanceOverlay.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionTransaction.psm1','scripts/register-project.ps1','scripts/upgrade-project.ps1','skills/ai-workspace-router/SKILL.md')) {
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

    $packageReadmePath = Join-Path $extract 'README.md'
    $packageAgentsPath = Join-Path $extract 'AGENTS.md'
    $expectedReadme = [IO.File]::ReadAllText((Join-Path $packageWorkspace 'framework/user-package/README.md'), [Text.UTF8Encoding]::new($false, $true)).Replace('{{FRAMEWORK_VERSION}}', '1.16.0')
    $expectedAgents = [IO.File]::ReadAllText((Join-Path $packageWorkspace 'framework/user-package/AGENTS.md'), [Text.UTF8Encoding]::new($false, $true)).Replace('{{FRAMEWORK_VERSION}}', '1.16.0')
    Assert-True (
        [IO.File]::ReadAllText($packageReadmePath, [Text.UTF8Encoding]::new($false, $true)) -ceq $expectedReadme -and
        [IO.File]::ReadAllText($packageAgentsPath, [Text.UTF8Encoding]::new($false, $true)) -ceq $expectedAgents -and
        -not $expectedReadme.Contains('{{FRAMEWORK_VERSION}}') -and
        -not $expectedAgents.Contains('{{FRAMEWORK_VERSION}}')
    ) 'package-root-entrypoints-render-user-templates'
    Assert-True (
        -not (Test-Path -LiteralPath (Join-Path $extract 'INITIALIZATION.md')) -and
        -not (Test-Path -LiteralPath (Join-Path $extract 'framework/PROJECT_ADOPTION.md')) -and
        -not (Test-Path -LiteralPath (Join-Path $extract 'framework/user-package'))
    ) 'package-excludes-development-and-maintenance-entrypoints'
    $allLinksResolve = $true
    foreach ($document in @($packageReadmePath, $packageAgentsPath)) {
        $documentText = [IO.File]::ReadAllText($document, [Text.UTF8Encoding]::new($false, $true))
        foreach ($match in [regex]::Matches($documentText, '\]\((?<target>[^)#]+)(?:#[^)]*)?\)')) {
            $target = [string]$match.Groups['target'].Value
            if ($target -match '^[a-z]+:') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $extract $target) -PathType Leaf)) { $allLinksResolve = $false; break }
        }
    }
    Assert-True $allLinksResolve 'package-root-relative-links-resolve'
    Assert-True (@($manifest.files).Count -eq 86) 'package-fixed-distribution-file-count'

    $null = New-Item -ItemType Directory -Path $candidateConsumer
    & git -C $candidateConsumer init -q
    Assert-True ($LASTEXITCODE -eq 0) 'candidate-consumer-git-initialized'
    Assert-Rejected {
        & (Join-Path $extract 'scripts/register-project.ps1') -ProjectId 'candidate-package-consumer' -DisplayName 'Candidate Package Consumer' -FrameworkVersion '1.16.0' -RepositoryPath $candidateConsumer -ControllerId 'controller-fixture' -WorkspaceRoot $extract -Apply -Confirm:$false
    } 'FRAMEWORK_VERSION_NOT_CONSUMABLE|1.16.0' 'actual-candidate-package-remains-non-consumable'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $candidateConsumer '.ai-workspace'))) 'candidate-rejection-writes-no-project-control'

    $stableVersion = $validVersionRaw | ConvertFrom-Json
    $stableVersion.lifecycle = 'STABLE'
    $stableVersion.consumable = $true
    $stableVersion.projectPinEligible = $true
    Write-Utf8Json $fixtureVersionPath $stableVersion
    $stable = $validManifestRaw | ConvertFrom-Json
    $stable.lifecycle = 'STABLE'
    $stable.releaseIntegration = 'COMPLETE'
    $stableFacts = Get-ReleasePayloadFacts $fixtureVersionRoot $fixtureManifestPath
    $stable.fileCount = $stableFacts.FileCount
    $stable.totalBytes = $stableFacts.TotalBytes
    $stable.canonical = $stableFacts.Canonical
    $stable.completeSuite.payloadCanonical = $stableFacts.Canonical
    $stable.sourceReviewEvidence.reviewedPayloadCanonical = $stableFacts.Canonical
    Write-Utf8Json $fixtureManifestPath $stable
    $stableCreated = & $builder -WorkspaceRoot $packageWorkspace -FrameworkVersion '1.16.0' -OutputPath $stableZip -Apply -Confirm:$false
    Assert-True ($stableCreated.status -ceq 'CREATED') 'stable-fixture-package-created'
    [IO.Compression.ZipFile]::ExtractToDirectory($stableZip, $stableExtract)
    Assert-True (
        -not (Test-Path -LiteralPath (Join-Path $stableExtract '.git')) -and
        -not (Test-Path -LiteralPath (Join-Path $stableExtract 'AI-Workspace-Maintenance')) -and
        -not (Test-Path -LiteralPath (Join-Path $stableExtract 'framework/user-package'))
    ) 'stable-distribution-extract-needs-no-source-repository'
    $null = New-Item -ItemType Directory -Path $stableConsumer
    & git -C $stableConsumer init -q
    Assert-True ($LASTEXITCODE -eq 0) 'stable-consumer-git-initialized'
    $stablePreview = & (Join-Path $stableExtract 'scripts/register-project.ps1') -ProjectId 'stable-package-consumer' -DisplayName 'Stable Package Consumer' -FrameworkVersion '1.16.0' -RepositoryPath $stableConsumer -ControllerId 'controller-fixture' -WorkspaceRoot $stableExtract
    Assert-True (@(Get-StatusResult $stablePreview 'WHAT_IF').Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $stableConsumer '.ai-workspace'))) 'stable-distribution-registration-preview-zero-write'
    $stableApply = & (Join-Path $stableExtract 'scripts/register-project.ps1') -ProjectId 'stable-package-consumer' -DisplayName 'Stable Package Consumer' -FrameworkVersion '1.16.0' -RepositoryPath $stableConsumer -ControllerId 'controller-fixture' -WorkspaceRoot $stableExtract -Apply -Confirm:$false
    Assert-True (@(Get-StatusResult $stableApply 'CREATED').Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $stableConsumer '.ai-workspace/BOOTSTRAP.md'))) 'stable-distribution-registration-apply'
    $stableRepeat = & (Join-Path $stableExtract 'scripts/register-project.ps1') -ProjectId 'stable-package-consumer' -DisplayName 'Stable Package Consumer' -FrameworkVersion '1.16.0' -RepositoryPath $stableConsumer -ControllerId 'controller-fixture' -WorkspaceRoot $stableExtract
    Assert-True (@(Get-StatusResult $stableRepeat 'ALREADY_REGISTERED').Count -eq 1) 'stable-distribution-registration-reread'
    $stableRecovery = @(& (Join-Path $stableExtract 'scripts/upgrade-project.ps1') -ProjectId 'stable-package-consumer' -ToVersion '1.16.0' -RepositoryPath $stableConsumer -ControllerId 'controller-fixture' -WorkspaceRoot $stableExtract | ForEach-Object { [string]$_ })
    Assert-True (($stableRecovery -join "`n").Contains('WHAT_IF|from=1.16.0|to=1.16.0|objects=0|transaction=none')) 'stable-distribution-same-pin-recovery-preview'

    Write-Output ('PASS|user-package-tests|' + $passed + '/' + $passed)
}
finally {
    Remove-TestFixture $fixture
}
