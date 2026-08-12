[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$versionRoot = Split-Path -Parent $PSScriptRoot
$frameworkRoot = Split-Path -Parent (Split-Path -Parent $versionRoot)
$repoRoot = Split-Path -Parent $frameworkRoot
$failures = New-Object 'System.Collections.Generic.List[string]'

function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Output "PASS|$Name" } else { $script:failures.Add($Name); Write-Output "FAIL|$Name" }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function Get-TreeIdentity([string]$Root) {
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    $items = New-Object 'System.Collections.Generic.List[string]'
    $sha = [Security.Cryptography.SHA256]::Create()
    foreach ($file in @(Get-ChildItem -LiteralPath $resolved -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($resolved.Length + 1).Replace('\','/')
        $hash = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($file.FullName)))).Replace('-','')
        $items.Add($relative + '|' + $file.Length + '|' + $hash)
    }
    $payload = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $items))
    return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-','')
}

function Initialize-TestGit([string]$Repository) {
    & git -C $Repository init --quiet
    if ($LASTEXITCODE -ne 0) { throw "GIT_INIT_FAILED|$Repository" }
    & git -C $Repository config user.email framework-test@example.invalid
    & git -C $Repository config user.name Framework-Test
}

function Commit-TestRepository([string]$Repository, [string]$Message) {
    & git -C $Repository add -- .ai-workspace
    if ($LASTEXITCODE -ne 0) { throw "GIT_ADD_FAILED|$Repository" }
    & git -C $Repository commit --quiet -m $Message
    if ($LASTEXITCODE -ne 0) { throw "GIT_COMMIT_FAILED|$Repository" }
}

$current = (Get-Content -LiteralPath (Join-Path $frameworkRoot 'CURRENT') -Raw -Encoding utf8).Trim()
Assert-True ($current -ceq '1.4.1') 'current-remains-1.4.1'
$versionMetadata = Get-Content -LiteralPath (Join-Path $versionRoot 'VERSION.json') -Raw -Encoding utf8 | ConvertFrom-Json
Assert-True ([string]$versionMetadata.version -ceq '1.5.0' -and [string]$versionMetadata.lifecycle -ceq 'STABLE' -and [bool]$versionMetadata.consumable -and -not [bool]$versionMetadata.currentEligible -and [bool]$versionMetadata.projectPinEligible) 'version-metadata-stable-opt-in'
$releaseManifest = Get-Content -LiteralPath (Join-Path $versionRoot 'RELEASE_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
$releaseFiles = @([IO.Directory]::GetFiles($versionRoot,'*',[IO.SearchOption]::AllDirectories) | Where-Object { [IO.Path]::GetFileName($_) -cne 'RELEASE_MANIFEST.json' })
[Array]::Sort($releaseFiles,[StringComparer]::Ordinal)
$releaseEntries = New-Object 'System.Collections.Generic.List[string]'
$releaseTotal = [int64]0
$releaseSha = [Security.Cryptography.SHA256]::Create()
foreach ($releaseFile in $releaseFiles) {
    $releaseBytes = [IO.File]::ReadAllBytes($releaseFile)
    $releaseTotal += $releaseBytes.Length
    $releaseRelative = $releaseFile.Substring($versionRoot.Length + 1).Replace('\','/')
    $releaseHash = ([BitConverter]::ToString($releaseSha.ComputeHash($releaseBytes))).Replace('-','')
    $releaseEntries.Add($releaseRelative + '|' + $releaseBytes.Length + '|' + $releaseHash)
}
$releasePayload = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $releaseEntries))
$releaseCanonical = ([BitConverter]::ToString($releaseSha.ComputeHash($releasePayload))).Replace('-','')
Assert-True ([string]$releaseManifest.lifecycle -ceq 'STABLE' -and [int]$releaseManifest.fileCount -eq $releaseFiles.Count -and
    [int64]$releaseManifest.totalBytes -eq $releaseTotal -and [string]$releaseManifest.canonical -ceq $releaseCanonical -and
    [string]$releaseManifest.current -ceq '1.4.1' -and -not [bool]$releaseManifest.projectPinsChanged) 'release-manifest-matches-payload'

$starterRoot = Join-Path $versionRoot 'project-starter'
$starterInventory = @('.gitattributes','project.json','BOOTSTRAP.md','PROJECT.md','REVIEW_PROFILE.md','RELATIONSHIPS.md','STATUS.md','tasks\README.md')
$starterComplete = @($starterInventory | Where-Object { -not (Test-Path -LiteralPath (Join-Path $starterRoot $_) -PathType Leaf) }).Count -eq 0
Assert-True $starterComplete 'project-starter-fixed-inventory'
$starterProjectTemplate = Get-Content -LiteralPath (Join-Path $starterRoot 'project.json') -Raw -Encoding utf8
$starterProjectJson = $starterProjectTemplate.Replace('{{PROJECT_ID_JSON}}','"sample-id"').Replace('{{DISPLAY_NAME_JSON}}','"Sample"').Replace('{{FRAMEWORK_VERSION_JSON}}','"1.5.0"')
$starterProject = $starterProjectJson | ConvertFrom-Json
Assert-True ([int]$starterProject.schemaVersion -eq 2 -and [string]$starterProject.id -ceq 'sample-id' -and [string]$starterProject.controlPlaneLayout -ceq 'repo-local' -and [string]$starterProject.repositoryRoot -ceq '..') 'project-starter-keeps-schema2'
Assert-True ($starterProjectTemplate.Contains('{{PROJECT_ID_JSON}}') -and $starterProjectTemplate.Contains('{{DISPLAY_NAME_JSON}}') -and $starterProjectTemplate.Contains('{{FRAMEWORK_VERSION_JSON}}') -and -not $starterProjectTemplate.Contains('"projectId"')) 'project-starter-register-token-contract'
$starterBootstrap = Get-Content -LiteralPath (Join-Path $starterRoot 'BOOTSTRAP.md') -Raw -Encoding utf8
Assert-True ($starterBootstrap.Contains('framework/versions/{{FRAMEWORK_VERSION}}/scripts/check-task-card.ps1') -and $starterBootstrap.Contains('framework/versions/{{FRAMEWORK_VERSION}}/RECOVERY_CORE.md')) 'bootstrap-versioned-runtime-locators'

$versionFiles = Get-ChildItem -LiteralPath $versionRoot -Recurse -File
$strictText = $true
$fencesBalanced = $true
foreach ($file in $versionFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $strictText = $false }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { $strictText = $false }
    if ($file.Extension -ceq '.md') {
        if (([regex]::Matches($text, '(?m)^```').Count % 2) -ne 0 -or ([regex]::Matches($text, '(?m)^~~~~').Count % 2) -ne 0) { $fencesBalanced = $false }
    }
}
Assert-True $strictText 'strict-utf8-lf'
Assert-True $fencesBalanced 'markdown-fences-balanced'
$migrationMatrix = Get-Content -LiteralPath (Join-Path $versionRoot 'MIGRATION_MATRIX.md') -Raw -Encoding utf8
Assert-True (-not $migrationMatrix.Contains('COVERED/PENDING') -and $migrationMatrix.Contains('tests/run-framework-tests.ps1') -and $migrationMatrix.Contains('current_status=RELEASE_INTEGRATION_COMPLETE')) 'migration-matrix-current-state'

$loader = Join-Path $versionRoot 'scripts\resolve-load-plan.ps1'
$executorPlan = & $loader -Role EXECUTOR -Profile STANDARD -Phase IMPLEMENT,VERIFY -HostName CODEX -AsJson | ConvertFrom-Json
Assert-True ($executorPlan.frameworkVersion -ceq '1.5.0' -and $executorPlan.lifecycle -ceq 'STABLE') 'load-plan-stable-version'
Assert-True (@($executorPlan.modules | Select-Object -ExpandProperty path | Select-Object -Unique).Count -eq @($executorPlan.modules).Count) 'load-plan-union-deduplicated'
Assert-True (@($executorPlan.modules | Where-Object { $_.path -ceq 'RECOVERY_CORE.md' }).Count -eq 1) 'load-plan-core-present-once'
Assert-True (@($executorPlan.modules | Where-Object { $_.path -ceq 'TASK_AND_SCOPE.md' }).Count -eq 1) 'implementation-loads-task-scope'
Assert-True (@($executorPlan.modules | Where-Object { $_.path -ceq 'AUTHORIZATION_MODEL.md' }).Count -eq 0) 'executor-consumes-package-without-issuer-module'
Assert-True (@($executorPlan.modules | Where-Object { $_.path -ceq 'HOST_CODEX.md' }).Count -eq 1) 'codex-loads-host-module'
Assert-True ($executorPlan.totalBytes -gt 0 -and $executorPlan.estimatedTokens -gt 0) 'load-plan-cost-visible'
$compactPlan = & $loader -Role EXECUTOR -Profile STANDARD -Phase IMPLEMENT,VERIFY -HostName CODEX
Assert-True ($compactPlan -like 'PASS|load-plan|*' -and @($compactPlan).Count -eq 1 -and $compactPlan -like '*|paths=RECOVERY_CORE.md|*') 'load-plan-default-output-compact'

$discoverPlan = & $loader -Role EXECUTOR -Profile MICRO -Phase DISCOVER -HostName GENERIC -AsJson | ConvertFrom-Json
Assert-True (@($discoverPlan.modules).Count -eq 1 -and $discoverPlan.modules[0].path -ceq 'RECOVERY_CORE.md') 'readonly-discover-loads-core-only'

$ownerPlan = & $loader -Role DOMAIN_OWNER -Profile STANDARD -Phase PLAN -HostName CODEX -AsJson | ConvertFrom-Json
Assert-True (@($ownerPlan.modules | Where-Object { $_.path -ceq 'AUTHORIZATION_MODEL.md' }).Count -eq 1) 'domain-owner-loads-issuer-module'

$ownerCostPlan = & $loader -Role DOMAIN_OWNER -Profile STANDARD -Phase PLAN,IMPLEMENT,VERIFY -HostName CODEX -AsJson | ConvertFrom-Json
$controllerCostPlan = & $loader -Role CONTROLLER -Profile CRITICAL -Phase RECOVER,PLAN -HostName CODEX -AsJson | ConvertFrom-Json
$maintainerCostPlan = & $loader -Role FRAMEWORK_MAINTAINER -Profile CRITICAL -Phase RECOVER,PLAN,IMPLEMENT,VERIFY,REVIEW,GIT,EXTERNAL -HostName CODEX -AsJson | ConvertFrom-Json
$staticComparisonNormalized = (Get-Content -LiteralPath (Join-Path $versionRoot 'STATIC_COMPARISON.md') -Raw -Encoding utf8).Replace(',','')
Assert-True ($staticComparisonNormalized.Contains('| 5 | ' + $ownerCostPlan.totalBytes + ' | ' + $ownerCostPlan.estimatedTokens + ' |') -and
    $staticComparisonNormalized.Contains('| 6 | ' + $controllerCostPlan.totalBytes + ' | ' + $controllerCostPlan.estimatedTokens + ' |') -and
    $staticComparisonNormalized.Contains('| 8 | ' + $maintainerCostPlan.totalBytes + ' | ' + $maintainerCostPlan.estimatedTokens + ' |')) 'static-comparison-current-load-costs'

$allPlansClose = $true
$roles = @('CONTROLLER','DOMAIN_OWNER','EXECUTOR','REVIEWER','FRAMEWORK_MAINTAINER')
$profiles = @('MICRO','STANDARD','CRITICAL')
$phases = @('DISCOVER','PLAN','IMPLEMENT','VERIFY','REVIEW','GIT','EXTERNAL','RECOVER')
$hosts = @('CODEX','GENERIC')
foreach ($role in $roles) {
    foreach ($profile in $profiles) {
        foreach ($phase in $phases) {
            foreach ($hostName in $hosts) {
                try {
                    $plan = & $loader -Role $role -Profile $profile -Phase $phase -HostName $hostName -AsJson | ConvertFrom-Json
                    if (@($plan.modules).Count -lt 1 -or $plan.totalBytes -lt 1) { $allPlansClose = $false }
                } catch {
                    $allPlansClose = $false
                }
            }
        }
    }
}
Assert-True $allPlansClose 'all-role-profile-phase-host-load-plans-close'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('framework-1.5-stable-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $shaA = ('A' * 64)
    $package = [ordered]@{
        schemaVersion = 1
        frameworkVersion = '1.5.0'
        taskId = 'FW-TEST-001'
        profile = 'STANDARD'
        lifecycle = 'ACTIVE'
        owner = 'domain-owner-1'
        issuer = 'domain-owner-1'
        issuerRole = 'DOMAIN_OWNER'
        grantee = 'executor-1'
        bundle = 'IMPLEMENT_LOCAL'
        decisionClass = 'ROUTINE_LOCAL'
        userConfirmation = 'NOT_REQUIRED'
        reviewIndependence = 'NOT_APPLICABLE'
        delegatedGitCloser = $false
        actions = @('SOURCE_WRITE','TEST_WRITE','TEST_RUN')
        exactPaths = @('src/a.js','test/a.test.js')
        objectIdentities = @(
            [ordered]@{ path = 'src/a.js'; identity = "10|$shaA" },
            [ordered]@{ path = 'test/a.test.js'; identity = 'NEW' }
        )
        invalidatesOn = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE')
    }
    $packagePath = Join-Path $tempRoot 'valid.json'
    Write-Utf8NoBom $packagePath ($package | ConvertTo-Json -Depth 8)
    $checker = Join-Path $versionRoot 'scripts\check-authorization.ps1'

    $valid = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA"
    Assert-True ($LASTEXITCODE -eq 0 -and $valid -like 'PASS|*') 'authorization-valid-stage-package'

    $newValid = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction TEST_WRITE -ObservedPath test/a.test.js -ObservedIdentity 'test/a.test.js=NEW'
    Assert-True ($LASTEXITCODE -eq 0 -and $newValid -like 'PASS|*') 'authorization-new-object-requires-explicit-new'

    $newExisting = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction TEST_WRITE -ObservedPath test/a.test.js -ObservedIdentity "test/a.test.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $newExisting -like '*NEW_OBJECT_EXISTS*') 'authorization-new-cannot-disguise-existing-object'

    $newMissing = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction TEST_WRITE -ObservedPath test/a.test.js 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $newMissing -like '*OBSERVED_IDENTITY_MISSING*') 'authorization-new-still-requires-observed-identity'

    $dotComponent = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/./a.js -ObservedIdentity "src/./a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $dotComponent -like '*OBSERVED_PATH_INVALID*') 'authorization-rejects-dot-component'

    $duplicateSlash = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src//a.js -ObservedIdentity "src//a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $duplicateSlash -like '*OBSERVED_PATH_INVALID*') 'authorization-rejects-empty-component'

    $trailingDot = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src./a.js -ObservedIdentity "src./a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $trailingDot -like '*OBSERVED_PATH_INVALID*') 'authorization-rejects-trailing-dot-component'

    $trailingSpace = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath 'src /a.js' -ObservedIdentity "src /a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $trailingSpace -like '*OBSERVED_PATH_INVALID*') 'authorization-rejects-trailing-space-component'

    $reservedName = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/CON.js -ObservedIdentity "src/CON.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $reservedName -like '*OBSERVED_PATH_INVALID*') 'authorization-rejects-windows-reserved-name'

    $caseCollision = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js,SRC/A.JS -ObservedIdentity "src/a.js=10|$shaA","SRC/A.JS=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $caseCollision -like '*OBSERVED_IDENTITY_DUPLICATE*') 'authorization-rejects-case-normalization-collision'

    $nfdSegment = 'e' + [char]0x0301
    $nfdPath = $nfdSegment + '/a.js'
    $nfdIdentity = $nfdPath + "=10|$shaA"
    $unicodeCollision = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath $nfdPath -ObservedIdentity $nfdIdentity 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $unicodeCollision -like '*OBSERVED_PATH_INVALID*') 'authorization-rejects-non-nfc-path'

    $malformedPackagePath = Join-Path $tempRoot 'malformed.json'
    Write-Utf8NoBom $malformedPackagePath '{"schemaVersion":'
    $malformedPackage = & $checker -PackagePath $malformedPackagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $malformedPackage -ceq 'FAIL|PACKAGE_JSON') 'authorization-malformed-json-is-compact-failure'

    $markdownPackagePath = Join-Path $tempRoot 'task.md'
    Write-Utf8NoBom $markdownPackagePath ("# FW-TEST-001`n`n``````authorization-package`n" + ($package | ConvertTo-Json -Depth 8) + "`n```````n")
    $markdownValid = & $checker -PackagePath $markdownPackagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA"
    Assert-True ($LASTEXITCODE -eq 0 -and $markdownValid -like 'PASS|*') 'authorization-embedded-task-package'

    $outOfRange = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/b.js 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $outOfRange -like '*OBSERVED_PATH_OUTSIDE_EXACT*') 'authorization-rejects-path-expansion'

    $drift = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity ('src/a.js=11|' + ('B' * 64)) 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $drift -like '*OBJECT_DRIFT*') 'authorization-rejects-object-drift'

    $actorDrift = & $checker -PackagePath $packagePath -ObservedActor executor-2 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $actorDrift -like '*GRANTEE_DRIFT*') 'authorization-rejects-actor-drift'

    $taskDrift = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-002 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskDrift -like '*TASK_DRIFT*') 'authorization-rejects-task-drift'

    $ownerDrift = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-2 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $ownerDrift -like '*OWNER_DRIFT*') 'authorization-rejects-owner-drift'

    $actionDrift = & $checker -PackagePath $packagePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction GIT_COMMIT -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $actionDrift -like '*ACTION_NOT_GRANTED*') 'authorization-rejects-action-expansion'

    $package.issuer = ''
    $emptyIssuerPath = Join-Path $tempRoot 'empty-issuer.json'
    Write-Utf8NoBom $emptyIssuerPath ($package | ConvertTo-Json -Depth 8)
    $emptyIssuer = & $checker -PackagePath $emptyIssuerPath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $emptyIssuer -like '*ISSUER_EMPTY*') 'authorization-rejects-empty-issuer'
    $package.issuer = 'domain-owner-1'

    $package.grantee = ''
    $emptyGranteePath = Join-Path $tempRoot 'empty-grantee.json'
    Write-Utf8NoBom $emptyGranteePath ($package | ConvertTo-Json -Depth 8)
    $emptyGrantee = & $checker -PackagePath $emptyGranteePath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $emptyGrantee -like '*GRANTEE_EMPTY*') 'authorization-rejects-empty-grantee'
    $package.grantee = 'executor-1'

    $package.actions = @('SOURCE_WRITE','NOT_A_REAL_ACTION')
    $unknownActionPath = Join-Path $tempRoot 'unknown-action.json'
    Write-Utf8NoBom $unknownActionPath ($package | ConvertTo-Json -Depth 8)
    $unknownAction = & $checker -PackagePath $unknownActionPath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $unknownAction -like '*ACTION_UNKNOWN*') 'authorization-rejects-unknown-package-action'
    $package.actions = @('SOURCE_WRITE','TEST_WRITE','TEST_RUN')

    $package.decisionClass = 'MAJOR_ARCHITECTURE'
    $package.userConfirmation = 'NOT_REQUIRED'
    $majorPath = Join-Path $tempRoot 'major-without-user.json'
    Write-Utf8NoBom $majorPath ($package | ConvertTo-Json -Depth 8)
    $major = & $checker -PackagePath $majorPath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $major -like '*USER_CONFIRMATION_REQUIRED*') 'authorization-requires-major-user-gate'

    $package.decisionClass = 'ROUTINE_LOCAL'
    $package.userConfirmation = 'NOT_REQUIRED'
    $package.invalidatesOn = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT')
    $missingInvalidatorPath = Join-Path $tempRoot 'missing-invalidator.json'
    Write-Utf8NoBom $missingInvalidatorPath ($package | ConvertTo-Json -Depth 8)
    $missingInvalidator = & $checker -PackagePath $missingInvalidatorPath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $missingInvalidator -like '*INVALIDATOR_MISSING_USER_DECISION_CHANGE*') 'authorization-requires-invalidation-closure'

    $package.invalidatesOn = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE')
    $package.actions = @('EXTERNAL')
    $package.exactPaths = @('src/a.js')
    $package.objectIdentities = @([ordered]@{ path = 'src/a.js'; identity = "10|$shaA" })
    $package.decisionClass = 'EXTERNAL_ACTION'
    $package.userConfirmation = 'USER_CONFIRMATION:TEST'
    $externalPath = Join-Path $tempRoot 'domain-external.json'
    Write-Utf8NoBom $externalPath ($package | ConvertTo-Json -Depth 8)
    $externalDenied = & $checker -PackagePath $externalPath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction EXTERNAL -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $externalDenied -like '*DOMAIN_OWNER_EXTERNAL_DENIED*') 'authorization-domain-owner-cannot-sign-external'

    $package.actions = @('GIT_COMMIT')
    $package.decisionClass = 'ROUTINE_LOCAL'
    $package.userConfirmation = 'NOT_REQUIRED'
    $package.delegatedGitCloser = $false
    $gitPath = Join-Path $tempRoot 'domain-git.json'
    Write-Utf8NoBom $gitPath ($package | ConvertTo-Json -Depth 8)
    $gitDenied = & $checker -PackagePath $gitPath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction GIT_COMMIT -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $gitDenied -like '*DOMAIN_OWNER_GIT_NOT_DELEGATED*') 'authorization-domain-git-requires-delegation'

    $package.profile = 'CRITICAL'
    $package.actions = @('REVIEW_EXECUTE')
    $package.reviewIndependence = 'NOT_APPLICABLE'
    $criticalReviewPath = Join-Path $tempRoot 'critical-review.json'
    Write-Utf8NoBom $criticalReviewPath ($package | ConvertTo-Json -Depth 8)
    $criticalReviewDenied = & $checker -PackagePath $criticalReviewPath -ObservedActor executor-1 -ObservedTaskId FW-TEST-001 -ObservedOwner domain-owner-1 -ObservedAction REVIEW_EXECUTE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$shaA" 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $criticalReviewDenied -like '*CRITICAL_REVIEW_NOT_INDEPENDENT*') 'authorization-critical-review-requires-independence'

    $package.profile = 'STANDARD'
    $package.actions = @('SOURCE_WRITE','TEST_WRITE','TEST_RUN')
    $package.exactPaths = @('src/a.js','test/a.test.js')
    $package.objectIdentities = @(
        [ordered]@{ path = 'src/a.js'; identity = "10|$shaA" },
        [ordered]@{ path = 'test/a.test.js'; identity = 'NEW' }
    )
    $package.reviewIndependence = 'NOT_APPLICABLE'
    $package.delegatedGitCloser = $false
    $package.decisionClass = 'ROUTINE_LOCAL'
    $package.userConfirmation = 'NOT_REQUIRED'
    $packageJson = $package | ConvertTo-Json -Depth 8
    $taskPath = Join-Path $tempRoot 'FW-TEST-001.md'
    $taskText = @"
# FW-TEST-001 - task checker sample

- 状态：IN_PROGRESS
- Task schema: 1.5
- 档位：STANDARD；理由=direct
- Owner: domain-owner-1
- 当前actor / writer：EXECUTOR / executor-1
- Range summary: profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js|test/a.test.js]; actual_paths=[src/a.js]
- Stable candidate: NONE
- Git / push / external：CLOSED / CLOSED / CLOSED

## Current

- 唯一下一动作：implement

## Current authorization

``````authorization-package
$packageJson
``````
"@
    Write-Utf8NoBom $taskPath $taskText
    $taskChecker = Join-Path $versionRoot 'scripts\check-task-card.ps1'
    $taskPass = & $taskChecker -TaskPath $taskPath -ObservedActualPath src/a.js
    Assert-True ($LASTEXITCODE -eq 0 -and $taskPass -like 'PASS|*') 'task-checker-active-write-pass'

    $taskOutside = & $taskChecker -TaskPath $taskPath -ObservedActualPath src/b.js 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskOutside -like '*OBSERVED_OUTSIDE_EXPECTED*') 'task-checker-rejects-observed-expansion'

    $taskNoAuthPath = Join-Path $tempRoot 'FW-TEST-NOAUTH.md'
    $taskNoAuth = @"
# FW-TEST-NOAUTH - no auth

- Task schema: 1.5
- Owner: domain-owner-1
- Range summary: profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js]; actual_paths=[]
"@
    Write-Utf8NoBom $taskNoAuthPath $taskNoAuth
    $taskNoAuthResult = & $taskChecker -TaskPath $taskNoAuthPath 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskNoAuthResult -like '*ACTIVE_WRITE_AUTHORIZATION_COUNT*') 'task-checker-requires-active-authorization'

    $fence = [string]::new([char]96, 3)
    $taskMalformedAuthPath = Join-Path $tempRoot 'FW-TEST-BADAUTH.md'
    $taskMalformedAuth = "# FW-TEST-BADAUTH - bad auth`n`n- Task schema: 1.5`n- Owner: domain-owner-1`n- Range summary: profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js]; actual_paths=[]`n`n$fence" + "authorization-package`n{`"schemaVersion`":`n$fence`n"
    Write-Utf8NoBom $taskMalformedAuthPath $taskMalformedAuth
    $taskMalformedAuthResult = & $taskChecker -TaskPath $taskMalformedAuthPath 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskMalformedAuthResult -like '*AUTHORIZATION_JSON*') 'task-checker-malformed-auth-is-compact-failure'

    $taskCasePath = Join-Path $tempRoot 'FW-TEST-CASE.md'
    $taskCase = "# FW-TEST-CASE - case collision`n`n- Task schema: 1.5`n- Owner: domain-owner-1`n- Range summary: profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js|SRC/A.JS]; actual_paths=[]`n"
    Write-Utf8NoBom $taskCasePath $taskCase
    $taskCaseResult = & $taskChecker -TaskPath $taskCasePath 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskCaseResult -like '*EXPECTED_PATH_DUPLICATE*') 'task-checker-rejects-case-normalization-collision'

    $taskDotResult = & $taskChecker -TaskPath $taskPath -ObservedActualPath src/./a.js 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskDotResult -like '*OBSERVED_PATH_INVALID*') 'task-checker-rejects-dot-component'

    $taskTrailingSpaceResult = & $taskChecker -TaskPath $taskPath -ObservedActualPath 'src /a.js' 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskTrailingSpaceResult -like '*OBSERVED_PATH_INVALID*') 'task-checker-rejects-trailing-space-component'

    $taskNfdSegment = 'e' + [char]0x0301
    $taskNfdResult = & $taskChecker -TaskPath $taskPath -ObservedActualPath ($taskNfdSegment + '/a.js') 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $taskNfdResult -like '*OBSERVED_PATH_INVALID*') 'task-checker-rejects-non-nfc-path'

    $tick = [char]96
    $legacyScopeTaskPath = Join-Path $tempRoot 'LEGACY-SCOPE.md'
    $legacyScopeText = "# LEGACY-SCOPE - sample`n`n- Legacy range: $tick" + "profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js|test/a.test.js]; actual_paths=[src/a.js]$tick`n"
    Write-Utf8NoBom $legacyScopeTaskPath $legacyScopeText
    $legacyScopePass = & $taskChecker -TaskPath $legacyScopeTaskPath -ObservedActualPath src/a.js
    Assert-True ($LASTEXITCODE -eq 0 -and $legacyScopePass -like 'PASS_LEGACY_SCOPE|*') 'task-checker-validates-legacy-scope-without-migration'

    $legacyScopeOutside = & $taskChecker -TaskPath $legacyScopeTaskPath -ObservedActualPath src/b.js 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $legacyScopeOutside -like '*LEGACY_OBSERVED_OUTSIDE_EXPECTED*') 'task-checker-rejects-legacy-scope-expansion'

    $legacyStrictPath = Join-Path $tempRoot 'LEGACY-STRICT.md'
    [IO.File]::WriteAllText($legacyStrictPath, '# LEGACY-STRICT - no final lf', [Text.UTF8Encoding]::new($false))
    $legacyStrict = & $taskChecker -TaskPath $legacyStrictPath 2>$null
    Assert-True ($LASTEXITCODE -eq 2 -and $legacyStrict -like '*FINAL_LF*') 'task-checker-strict-failure-precedes-legacy-unchecked'

    $legacyTaskPath = Join-Path $tempRoot 'LEGACY.md'
    Write-Utf8NoBom $legacyTaskPath "# LEGACY - sample`n"
    $legacyResult = & $taskChecker -TaskPath $legacyTaskPath
    Assert-True ($LASTEXITCODE -eq 0 -and $legacyResult -like 'LEGACY_UNCHECKED|*') 'task-checker-does-not-force-legacy-migration'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

$integrationRoot = Join-Path ([IO.Path]::GetTempPath()) ('framework-1.5-integration-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $integrationRoot | Out-Null
try {
    $isolatedWorkspace = Join-Path $integrationRoot 'workspace'
    New-Item -ItemType Directory -Path (Join-Path $isolatedWorkspace 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $isolatedWorkspace 'framework\versions') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\register-project.ps1') -Destination (Join-Path $isolatedWorkspace 'scripts\register-project.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\upgrade-project.ps1') -Destination (Join-Path $isolatedWorkspace 'scripts\upgrade-project.ps1')
    Copy-Item -LiteralPath (Join-Path $frameworkRoot 'versions\1.4.1') -Destination (Join-Path $isolatedWorkspace 'framework\versions\1.4.1') -Recurse
    Copy-Item -LiteralPath $versionRoot -Destination (Join-Path $isolatedWorkspace 'framework\versions\1.5.0') -Recurse
    Write-Utf8NoBom (Join-Path $isolatedWorkspace 'framework\CURRENT') '1.4.1'

    $registerScript = Join-Path $isolatedWorkspace 'scripts\register-project.ps1'
    $upgradeScript = Join-Path $isolatedWorkspace 'scripts\upgrade-project.ps1'

    $newRepo = Join-Path $integrationRoot 'register-150'
    New-Item -ItemType Directory -Path $newRepo | Out-Null
    Initialize-TestGit $newRepo
    $register150 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $registerScript -ProjectId register-150 -DisplayName 'Register 150' -RepositoryPath $newRepo -FrameworkVersion 1.5.0 -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    $register150Code = $LASTEXITCODE
    $register150Config = if (Test-Path -LiteralPath (Join-Path $newRepo '.ai-workspace\project.json')) {
        Get-Content -LiteralPath (Join-Path $newRepo '.ai-workspace\project.json') -Raw -Encoding utf8 | ConvertFrom-Json
    } else { $null }
    Assert-True ($register150Code -eq 0 -and $null -ne $register150Config -and [string]$register150Config.frameworkVersion -ceq '1.5.0') 'register-explicit-1.5.0'

    $defaultRepo = Join-Path $integrationRoot 'register-current'
    New-Item -ItemType Directory -Path $defaultRepo | Out-Null
    Initialize-TestGit $defaultRepo
    $registerCurrent = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $registerScript -ProjectId register-current -DisplayName 'Register Current' -RepositoryPath $defaultRepo -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    $registerCurrentCode = $LASTEXITCODE
    $registerCurrentConfig = if (Test-Path -LiteralPath (Join-Path $defaultRepo '.ai-workspace\project.json')) {
        Get-Content -LiteralPath (Join-Path $defaultRepo '.ai-workspace\project.json') -Raw -Encoding utf8 | ConvertFrom-Json
    } else { $null }
    Assert-True ($registerCurrentCode -eq 0 -and $null -ne $registerCurrentConfig -and [string]$registerCurrentConfig.frameworkVersion -ceq '1.4.1') 'current-default-remains-1.4.1'

    $upgradeRepo = Join-Path $integrationRoot 'upgrade-141-to-150'
    New-Item -ItemType Directory -Path $upgradeRepo | Out-Null
    Initialize-TestGit $upgradeRepo
    $register141 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $registerScript -ProjectId upgrade-141-to-150 -DisplayName 'Upgrade 141 To 150' -RepositoryPath $upgradeRepo -FrameworkVersion 1.4.1 -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('REGISTER_141_FAILED|' + ($register141 -join ' ')) }
    $upgradeBootstrapPath = Join-Path $upgradeRepo '.ai-workspace\BOOTSTRAP.md'
    $upgradeBootstrap = Get-Content -LiteralPath $upgradeBootstrapPath -Raw -Encoding utf8
    Write-Utf8NoBom $upgradeBootstrapPath $upgradeBootstrap.Replace('<!-- PROJECT-CUSTOM:BEGIN -->', "<!-- PROJECT-CUSTOM:BEGIN -->`nCUSTOM_PRESERVE_150")
    Commit-TestRepository $upgradeRepo 'register 1.4.1 baseline'
    $upgradeHeadBefore = (& git -C $upgradeRepo rev-parse HEAD).Trim()
    $upgradePreviewIdentity = Get-TreeIdentity (Join-Path $upgradeRepo '.ai-workspace')
    $upgradePreview = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $upgradeScript -ProjectId upgrade-141-to-150 -RepositoryPath $upgradeRepo -ToVersion 1.5.0 -WorkspaceRoot $isolatedWorkspace 2>&1
    $upgradePreviewCode = $LASTEXITCODE
    Assert-True ($upgradePreviewCode -eq 0 -and (Get-TreeIdentity (Join-Path $upgradeRepo '.ai-workspace')) -ceq $upgradePreviewIdentity) 'upgrade-preview-is-read-only'
    $upgradeApply = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $upgradeScript -ProjectId upgrade-141-to-150 -RepositoryPath $upgradeRepo -ToVersion 1.5.0 -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    $upgradeApplyCode = $LASTEXITCODE
    $upgradeConfig = Get-Content -LiteralPath (Join-Path $upgradeRepo '.ai-workspace\project.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $upgradedBootstrap = Get-Content -LiteralPath $upgradeBootstrapPath -Raw -Encoding utf8
    $upgradeHeadAfter = (& git -C $upgradeRepo rev-parse HEAD).Trim()
    $upgradeCached = @(& git -C $upgradeRepo diff --cached --name-only)
    Assert-True ($upgradeApplyCode -eq 0 -and [string]$upgradeConfig.frameworkVersion -ceq '1.5.0' -and
        $upgradedBootstrap.Contains('framework/versions/1.5.0/RECOVERY_CORE.md') -and
        $upgradedBootstrap.Contains('CUSTOM_PRESERVE_150') -and
        $upgradeHeadAfter -ceq $upgradeHeadBefore -and $upgradeCached.Count -eq 0) 'upgrade-1.4.1-to-1.5.0-preserves-custom-and-git'

    $conflictRepo = Join-Path $integrationRoot 'upgrade-conflict'
    New-Item -ItemType Directory -Path $conflictRepo | Out-Null
    Initialize-TestGit $conflictRepo
    $conflictRegister = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $registerScript -ProjectId upgrade-conflict -DisplayName 'Upgrade Conflict' -RepositoryPath $conflictRepo -FrameworkVersion 1.4.1 -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('REGISTER_CONFLICT_FAILED|' + ($conflictRegister -join ' ')) }
    $conflictBootstrapPath = Join-Path $conflictRepo '.ai-workspace\BOOTSTRAP.md'
    $conflictBootstrap = Get-Content -LiteralPath $conflictBootstrapPath -Raw -Encoding utf8
    Write-Utf8NoBom $conflictBootstrapPath $conflictBootstrap.Replace('framework/versions/1.4.1/scripts/check-task-card.ps1','framework/versions/1.4.1/scripts/check-task-card.changed.ps1')
    Commit-TestRepository $conflictRepo 'commit managed conflict'
    $conflictBefore = Get-TreeIdentity (Join-Path $conflictRepo '.ai-workspace')
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $conflictUpgrade = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $upgradeScript -ProjectId upgrade-conflict -RepositoryPath $conflictRepo -ToVersion 1.5.0 -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    $conflictUpgradeCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    $conflictAfter = Get-TreeIdentity (Join-Path $conflictRepo '.ai-workspace')
    Assert-True ($conflictUpgradeCode -ne 0 -and $conflictAfter -ceq $conflictBefore) 'upgrade-managed-conflict-rolls-back-without-mutation'
} finally {
    if (Test-Path -LiteralPath $integrationRoot) {
        Remove-Item -LiteralPath $integrationRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    Write-Output ('FRAMEWORK_TESTS_FAILED|' + ($failures -join ','))
    exit 1
}

Write-Output 'FRAMEWORK_TESTS_PASS'
exit 0
