[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$versionRoot = Split-Path -Parent $PSScriptRoot
$versionsRoot = Split-Path -Parent $versionRoot
$frameworkRoot = Split-Path -Parent $versionsRoot
$workspaceRoot = Split-Path -Parent $frameworkRoot
$checker = Join-Path $versionRoot 'scripts\check-task-card.ps1'
$register = Join-Path $workspaceRoot 'scripts\register-project.ps1'
$upgrade = Join-Path $workspaceRoot 'scripts\upgrade-project.ps1'
$powershellExe = Join-Path $PSHOME 'powershell.exe'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-workspace-1.4.1-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
$script:Passed = 0
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $normalized = $Content -replace "`r`n", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Read-StrictUtf8NoBom {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ConvertFrom-StrictUtf8NoBomBytes $bytes $Path
}

function ConvertFrom-StrictUtf8NoBomBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Source
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        throw "Unexpected UTF-8 BOM: $Source"
    }
    try {
        return $utf8Strict.GetString($Bytes)
    }
    catch {
        throw "Content is not strict UTF-8: $Source"
    }
}

function Get-UpgradeResidue {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    return ,@(Get-ChildItem -LiteralPath $ProjectRoot -Force | Where-Object {
        $_.Name -like '.framework-upgrade-transaction*' -or $_.Name -like '.fwu-*' -or $_.Name -like '.*.upgrade.*'
    })
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Detail = ''
    )

    if (-not $Condition) {
        throw "FAIL $Name $Detail"
    }
    $script:Passed++
    Write-Output "PASS $Name"
}

function Invoke-IsolatedPowerShell {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $powershellExe @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join "`n")
    }
}

function Invoke-InterruptedUpgrade {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot
    )

    $previousTestMode = [Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE', 'Process')
    $previousInterrupt = [Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_PROJECT_REPLACE', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE', '1', 'Process')
        [Environment]::SetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_PROJECT_REPLACE', '1', 'Process')
        return Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, '-ProjectId', $ProjectId, '-ToVersion', '1.3.2', '-WorkspaceRoot', $WorkspaceRoot, '-Apply')
    }
    finally {
        [Environment]::SetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE', $previousTestMode, 'Process')
        [Environment]::SetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_PROJECT_REPLACE', $previousInterrupt, 'Process')
    }
}

function Invoke-Checker {
    param(
        [Parameter(Mandatory = $true)][string]$CardPath,
        [string]$ObservedActualPath,
        [bool]$ProvideObserved = $true
    )

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $checker, '-Path', $CardPath)
    if ($ProvideObserved) {
        $arguments += @('-ObservedActualPath', $ObservedActualPath)
    }
    return Invoke-IsolatedPowerShell $arguments
}

function New-Card {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Content,
        [ValidateSet('active', 'archive')][string]$Location = 'active'
    )

    $directory = Join-Path (Join-Path $testRoot 'tasks') $Location
    $path = Join-Path $directory "$Name.md"
    Write-Utf8NoBom $path $Content
    return $path
}

function Expand-UnicodeText {
    param([Parameter(Mandatory = $true)][string]$Text)

    return [regex]::Replace(
        $Text,
        '\\u(?<code>[0-9A-Fa-f]{4})',
        { param($match) [char][Convert]::ToInt32($match.Groups['code'].Value, 16) }
    )
}

function Get-MicroCard {
    return Expand-UnicodeText @'
# TEST-MICRO - Micro positive

- \u72b6\u6001\uFF1AACTIVE_WRITE
- \u4efb\u52a1\u6863\u4f4d\uFF1AMICRO
- \u98ce\u9669\uFF1A\u4f4e; direct single file
- \u552f\u4e00\u957f\u671fowner/\u8c03\u5ea6\u8005\uFF1Adocs owner
- Exact\u8def\u5f84\uFF1A[docs/a.md]
- Forbidden\u8def\u5f84\uFF1A[src/a.js]
- Git \u6743\u9650\uFF1A\u5173\u95ed
- \u5916\u90e8\u52a8\u4f5c\u6388\u6743\uFF1A\u65e0
- \u8303\u56f4\u6458\u8981\uFF1A`profile=MICRO; lifecycle=ACTIVE_WRITE; expected_paths=[docs/a.md]; actual_paths=[docs/a.md]`

## \u76ee\u6807

Fix one link.

## \u8303\u56f4\u4e0e\u4fdd\u62a4

Write exact only.

## \u9a8c\u6536\u4e0e\u9a8c\u8bc1

Check target and diff.

## \u4ea4\u63a5/\u4e0b\u4e00\u6b65

\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\uFF1Aowner records the result.
'@
}

function Get-StandardCard {
    return Expand-UnicodeText @'
# TEST-STANDARD - Standard positive

- \u72b6\u6001\uFF1AACTIVE_WRITE
- \u4efb\u52a1\u6863\u4f4d\uFF1ASTANDARD
- \u98ce\u9669\uFF1A\u4e2d; simple module behavior
- \u552f\u4e00\u957f\u671fowner/\u8c03\u5ea6\u8005\uFF1Amodule owner
- Exact\u8def\u5f84\uFF1A[src/a.js|test/a.test.js]
- Forbidden\u8def\u5f84\uFF1A[src/schema.js]
- Git \u6743\u9650\uFF1A\u5173\u95ed
- \u5916\u90e8\u52a8\u4f5c\u6388\u6743\uFF1A\u65e0
- \u8303\u56f4\u6458\u8981\uFF1A`profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js|test/a.test.js]; actual_paths=[src/a.js|test/a.test.js]`

## \u76ee\u6807

Preserve explicit false.

## \u975e\u76ee\u6807

Do not change schema.

## \u8303\u56f4\u4e0e\u4fdd\u62a4

Implementation and direct test are exact.

## \u9a8c\u6536\u4e0e\u9a8c\u8bc1

Run direct and related tests.

## \u4ea4\u63a5/\u4e0b\u4e00\u6b65

\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\uFF1Aowner performs focused review.
'@
}

function Get-CriticalCard {
    return Expand-UnicodeText @'
# TEST-CRITICAL - Critical positive

- \u72b6\u6001\uFF1AACTIVE_WRITE
- \u4efb\u52a1\u6863\u4f4d\uFF1ACRITICAL
- \u98ce\u9669\uFF1A\u9ad8; public persistent lifecycle
- \u552f\u4e00\u957f\u671fowner/\u8c03\u5ea6\u8005\uFF1Adomain owner
- \u5f53\u524d\u5199\u5165\u8005\uFF1Aexecutor
- \u5f53\u524dactor\uFF1AEXECUTOR
- \u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005\uFF1AEXECUTOR
- Review\u5f00\u59cb\u901a\u77e5\u65b9\uFF1AEXECUTOR
- \u5ba1\u6838\u4eba\uFF1Aindependent reviewer
- \u76f4\u63a5\u5ba1\u6838\u95ed\u73af\uFF1Atwo exact repair rounds
- Git \u6536\u53e3\u8005\uFF1Adomain owner
- Git \u6743\u9650\uFF1A\u5173\u95ed
- \u5916\u90e8\u52a8\u4f5c\u6388\u6743\uFF1A\u65e0
- Exact\u8def\u5f84\uFF1A[src/state.js]
- Forbidden\u8def\u5f84\uFF1A[secrets/data]
- \u8303\u56f4\u6458\u8981\uFF1A`profile=CRITICAL; lifecycle=ACTIVE_WRITE; current_actor=EXECUTOR; next_actor=EXECUTOR; current_exact=1; expected_paths=[src/state.js]; actual_paths=[src/state.js]; review_start_notifier=EXECUTOR`

## \u76ee\u6807

Migrate persistent lifecycle.

## \u975e\u76ee\u6807

Do not deploy.

## \u8303\u56f4\u4e0e\u4fdd\u62a4

Freeze the complete scope closure.

## \u9a8c\u6536\u4e0e\u9a8c\u8bc1

Run migration and recovery tests.

## \u4ea4\u63a5/\u4e0b\u4e00\u6b65

\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\uFF1Aexecutor stabilizes candidate.
'@
}

function Get-CompatCard {
    return Expand-UnicodeText @'
# TEST-COMPAT - Version 1.3.0 summary compatibility

- \u72b6\u6001\uFF1AACTIVE_WRITE
- \u552f\u4e00\u957f\u671fowner/\u8c03\u5ea6\u8005\uFF1Adomain owner
- \u5f53\u524d\u5199\u5165\u8005\uFF1Aexecutor
- \u5f53\u524dactor\uFF1AEXECUTOR
- \u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005\uFF1AEXECUTOR
- Review\u5f00\u59cb\u901a\u77e5\u65b9\uFF1AEXECUTOR
- \u5ba1\u6838\u4eba\uFF1Areviewer
- Git \u6536\u53e3\u8005\uFF1Adomain owner
- Git \u6743\u9650\uFF1A\u5173\u95ed
- \u5916\u90e8\u52a8\u4f5c\u6388\u6743\uFF1A\u65e0
- \u673a\u68b0\u6458\u8981\uFF1A`lifecycle=ACTIVE_WRITE; current_actor=EXECUTOR; next_actor=EXECUTOR; current_exact=1; expected_paths=[src/compat.js]; actual_paths=[src/compat.js]; review_start_notifier=EXECUTOR`

\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\uFF1Aexecutor continues.
'@
}

function Copy-StarterWorkspace {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$CurrentVersion
    )

    New-Item -ItemType Directory -Path (Join-Path $Target 'framework\versions') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target 'projects') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target 'scripts') -Force | Out-Null
    foreach ($version in @('1.3.0', '1.3.2', '1.4.0', '1.4.1')) {
        $source = Join-Path $versionsRoot $version
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "Required Framework test version is missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $Target "framework\versions\$version") -Recurse
    }
    Copy-Item -LiteralPath $register -Destination (Join-Path $Target 'scripts\register-project.ps1')
    Copy-Item -LiteralPath $upgrade -Destination (Join-Path $Target 'scripts\upgrade-project.ps1')
    Write-Utf8NoBom (Join-Path $Target 'framework\CURRENT') $CurrentVersion
}

function Initialize-GitRepository {
    param([Parameter(Mandatory = $true)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    & git -C $Path init --quiet
    if ($LASTEXITCODE -ne 0) { throw "git init failed: $Path" }
    & git -C $Path config user.name 'Framework Test'
    & git -C $Path config user.email 'framework-test@example.invalid'
    & git -C $Path config core.excludesFile (Join-Path $Path '.git\info\exclude')
    & git -C $Path config core.autocrlf false
    Write-Utf8NoBom (Join-Path $Path '.gitignore') "*.log`n"
    & git -C $Path add -- .gitignore
    & git -C $Path commit --quiet -m 'test baseline'
    if ($LASTEXITCODE -ne 0) { throw "git baseline commit failed: $Path" }
}

function New-LegacyProject {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [string]$FrameworkVersion = '1.3.0'
    )

    $starter = Join-Path $Workspace "framework\versions\$FrameworkVersion\project-starter"
    $projectRoot = Join-Path $Workspace "projects\$ProjectId"
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'tasks\active') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'tasks\archive') -Force | Out-Null
    $map = @('project.json','BOOTSTRAP.md','PROJECT.md','REVIEW_PROFILE.md','RELATIONSHIPS.md','STATUS.md','tasks\README.md')
    foreach ($relative in $map) {
        $source = Join-Path $starter $relative
        $destination = Join-Path $projectRoot $relative
        $content = Read-StrictUtf8NoBom $source
        $content = $content.Replace('{{PROJECT_ID}}', $ProjectId)
        $content = $content.Replace('{{DISPLAY_NAME}}', $DisplayName)
        $content = $content.Replace('{{REPOSITORY_PATH}}', $RepositoryPath)
        $content = $content.Replace('{{FRAMEWORK_VERSION}}', $FrameworkVersion)
        $content = $content.Replace('{{CREATED_DATE}}', '2026-08-09')
        $content = $content.Replace('{{PROJECT_ID_JSON}}', ($ProjectId | ConvertTo-Json -Compress))
        $content = $content.Replace('{{DISPLAY_NAME_JSON}}', ($DisplayName | ConvertTo-Json -Compress))
        $content = $content.Replace('{{REPOSITORY_PATH_JSON}}', ($RepositoryPath | ConvertTo-Json -Compress))
        $content = $content.Replace('{{FRAMEWORK_VERSION_JSON}}', ($FrameworkVersion | ConvertTo-Json -Compress))
        Write-Utf8NoBom $destination $content
    }
    return $projectRoot
}

function Get-DirectoryHashManifest {
    param([Parameter(Mandatory = $true)][string]$Root)

    $entries = @()
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object -Property FullName) {
        $entries += [ordered]@{
            path = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    return ($entries | ConvertTo-Json -Depth 5 -Compress)
}

if (-not (Test-Path -LiteralPath $powershellExe -PathType Leaf)) {
    throw "PowerShell 5.1 executable not found: $powershellExe"
}
if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) {
    throw "Versioned checker not found: $checker"
}
if (-not (Test-Path -LiteralPath $register -PathType Leaf)) {
    throw "Root register script not found: $register"
}
if (-not (Test-Path -LiteralPath $upgrade -PathType Leaf)) {
    throw "Root upgrade script not found: $upgrade"
}

try {
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $workspaceRoot 'scripts\check-task-card.ps1'))) 'retired-root-1.3.0-checker-not-packaged'
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'tasks\active') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'tasks\archive') -Force | Out-Null
    $repositoryPath = Join-Path $testRoot 'source-repository'
    New-Item -ItemType Directory -Path $repositoryPath | Out-Null

    $microPath = New-Card 'TEST-MICRO' (Get-MicroCard)
    $result = Invoke-Checker $microPath 'docs/a.md'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-MICRO\.md\|OK$') 'profile-micro-positive' $result.Output

    $standardPath = New-Card 'TEST-STANDARD' (Get-StandardCard)
    $result = Invoke-Checker $standardPath 'src/a.js|test/a.test.js'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-STANDARD\.md\|OK$') 'profile-standard-positive' $result.Output

    $criticalPath = New-Card 'TEST-CRITICAL' (Get-CriticalCard)
    $result = Invoke-Checker $criticalPath 'src/state.js'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-CRITICAL\.md\|OK$') 'profile-critical-1.3.1-host-order-compatibility' $result.Output

    $criticalCore = Get-CriticalCard
    $criticalHostLabelPattern = Expand-UnicodeText '(?m)^-\s*(?:\u5f53\u524dactor|\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005|Review\u5f00\u59cb\u901a\u77e5\u65b9|\u76f4\u63a5\u5ba1\u6838\u95ed\u73af)\s*\uFF1A.*\r?\n'
    $criticalCore = [regex]::Replace($criticalCore, $criticalHostLabelPattern, '')
    $criticalCore = $criticalCore.Replace('profile=CRITICAL; lifecycle=ACTIVE_WRITE; current_actor=EXECUTOR; next_actor=EXECUTOR; current_exact=1; expected_paths=[src/state.js]; actual_paths=[src/state.js]; review_start_notifier=EXECUTOR', 'profile=CRITICAL; lifecycle=ACTIVE_WRITE; current_exact=1; expected_paths=[src/state.js]; actual_paths=[src/state.js]')
    $criticalCorePath = New-Card 'TEST-CRITICAL-CORE' ($criticalCore.Replace('# TEST-CRITICAL -', '# TEST-CRITICAL-CORE -'))
    $result = Invoke-Checker $criticalCorePath 'src/state.js'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-CRITICAL-CORE\.md\|OK$') 'profile-critical-core-without-host-extension' $result.Output

    $criticalHostTail = Get-CriticalCard
    $criticalHostTail = $criticalHostTail.Replace('profile=CRITICAL; lifecycle=ACTIVE_WRITE; current_actor=EXECUTOR; next_actor=EXECUTOR; current_exact=1; expected_paths=[src/state.js]; actual_paths=[src/state.js]; review_start_notifier=EXECUTOR', 'profile=CRITICAL; lifecycle=ACTIVE_WRITE; current_exact=1; expected_paths=[src/state.js]; actual_paths=[src/state.js]; current_actor=EXECUTOR; next_actor=EXECUTOR; review_start_notifier=EXECUTOR')
    $criticalHostTailPath = New-Card 'TEST-CRITICAL-HOST-TAIL' ($criticalHostTail.Replace('# TEST-CRITICAL -', '# TEST-CRITICAL-HOST-TAIL -'))
    $result = Invoke-Checker $criticalHostTailPath 'src/state.js'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-CRITICAL-HOST-TAIL\.md\|OK$') 'profile-critical-1.3.2-optional-host-tail' $result.Output

    $standardRoleSummary = Expand-UnicodeText '- \u8303\u56f4\u6458\u8981\uFF1A`profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js|test/a.test.js]; actual_paths=[src/a.js|test/a.test.js]`'
    $standardRoleBlock = Expand-UnicodeText @'
- \u5f53\u524dactor\uFF1AEXECUTOR
- \u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005\uFF1AEXECUTOR
- Review\u5f00\u59cb\u901a\u77e5\u65b9\uFF1AEXECUTOR
- \u5ba1\u6838\u4eba\uFF1Areviewer
- \u76f4\u63a5\u5ba1\u6838\u95ed\u73af\uFF1Aone exact repair round
- \u8303\u56f4\u6458\u8981\uFF1A`profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/a.js|test/a.test.js]; actual_paths=[src/a.js|test/a.test.js]; current_actor=EXECUTOR; next_actor=EXECUTOR; review_start_notifier=EXECUTOR`
'@
    $standardRole = (Get-StandardCard).Replace($standardRoleSummary, $standardRoleBlock)
    $standardRolePath = New-Card 'TEST-STANDARD-ROLE' ($standardRole.Replace('# TEST-STANDARD -', '# TEST-STANDARD-ROLE -'))
    $result = Invoke-Checker $standardRolePath 'src/a.js|test/a.test.js'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-STANDARD-ROLE\.md\|OK$') 'profile-standard-optional-role-block' $result.Output

    $compatPath = New-Card 'TEST-COMPAT' (Get-CompatCard)
    $result = Invoke-Checker $compatPath 'src/compat.js'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-COMPAT\.md\|OK$') 'version-1.3.0-summary-compatibility' $result.Output

    $checkerSource = [System.IO.File]::ReadAllText($checker, [System.Text.Encoding]::ASCII)
    Assert-True ($checkerSource -match 'never discovers Git ownership' -and $checkerSource -notmatch '(?im)^\s*(?:&\s*)?git(?:\.exe)?\s' -and $checkerSource -notmatch '(?i)Start-Process\s+git') 'checker-capability-boundary-no-git-owner-discovery'

    $riskMedium = Expand-UnicodeText '\u98ce\u9669\uFF1A\u4e2d; simple module behavior'
    $riskHigh = Expand-UnicodeText '\u98ce\u9669\uFF1A\u9ad8; declared critical risk'
    $escalation = (Get-StandardCard).Replace($riskMedium, $riskHigh)
    $escalationPath = New-Card 'TEST-STANDARD-ESCALATION' ($escalation.Replace('# TEST-STANDARD -', '# TEST-STANDARD-ESCALATION -'))
    $result = Invoke-Checker $escalationPath 'src/a.js|test/a.test.js'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output -match 'PROFILE_ESCALATION_REQUIRED\[DECLARED_HIGH_RISK\]') 'profile-declared-escalation' $result.Output

    $forbiddenLinePattern = Expand-UnicodeText '(?m)^- Forbidden\u8def\u5f84\uFF1A\[src/schema\.js\]\r?\n'
    $missing = [regex]::Replace((Get-StandardCard), $forbiddenLinePattern, '')
    $missingPath = New-Card 'TEST-STANDARD-MISSING' ($missing.Replace('# TEST-STANDARD -', '# TEST-STANDARD-MISSING -'))
    $result = Invoke-Checker $missingPath 'src/a.js|test/a.test.js'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output -match 'FORBIDDEN_PATH') 'profile-required-field-missing' $result.Output

    $overflow = (Get-MicroCard).Replace('actual_paths=[docs/a.md]', 'actual_paths=[docs/a.md|docs/extra.md]')
    $overflowPath = New-Card 'TEST-MICRO-OVERFLOW' ($overflow.Replace('# TEST-MICRO -', '# TEST-MICRO-OVERFLOW -'))
    $result = Invoke-Checker $overflowPath 'docs/a.md|docs/extra.md'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output -match 'DECLARED_PATH_EXTRA\[docs/extra\.md\]') 'path-declared-overflow' $result.Output

    $observedPath = New-Card 'TEST-STANDARD-OBSERVED' ((Get-StandardCard).Replace('# TEST-STANDARD -', '# TEST-STANDARD-OBSERVED -'))
    $result = Invoke-Checker $observedPath 'src/a.js|test/other.test.js'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output -match 'OBSERVED_PATH_MISSING\[test/a\.test\.js\]' -and $result.Output -match 'OBSERVED_PATH_EXTRA\[test/other\.test\.js\]') 'observed-identity-mismatch' $result.Output

    $criticalNextAction = Expand-UnicodeText '\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\uFF1Aexecutor stabilizes candidate.'
    $history = (Get-CriticalCard).Replace($criticalNextAction, "$criticalNextAction`n`nHistory: candidate exact99 and closure exact101 are not range summary inputs.")
    $historyPath = New-Card 'TEST-CRITICAL-HISTORY' ($history.Replace('# TEST-CRITICAL -', '# TEST-CRITICAL-HISTORY -'))
    $result = Invoke-Checker $historyPath 'src/state.js'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-CRITICAL-HISTORY\.md\|OK$') 'history-text-does-not-pollute-summary' $result.Output

    $notifier = Get-CriticalCard
    $notifier = $notifier.Replace((Expand-UnicodeText '\u5f53\u524dactor\uFF1AEXECUTOR'), (Expand-UnicodeText '\u5f53\u524dactor\uFF1AOWNER'))
    $notifier = $notifier.Replace((Expand-UnicodeText '\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005\uFF1AEXECUTOR'), (Expand-UnicodeText '\u552f\u4e00\u4e0b\u4e00\u52a8\u4f5c\u6267\u884c\u8005\uFF1AOWNER'))
    $notifier = $notifier.Replace((Expand-UnicodeText 'Review\u5f00\u59cb\u901a\u77e5\u65b9\uFF1AEXECUTOR'), (Expand-UnicodeText 'Review\u5f00\u59cb\u901a\u77e5\u65b9\uFF1ANONE'))
    $notifier = $notifier.Replace('current_actor=EXECUTOR; next_actor=EXECUTOR', 'current_actor=OWNER; next_actor=OWNER')
    $notifier = $notifier.Replace('review_start_notifier=EXECUTOR', 'review_start_notifier=NONE')
    $notifierPath = New-Card 'TEST-CRITICAL-NOTIFIER' ($notifier.Replace('# TEST-CRITICAL -', '# TEST-CRITICAL-NOTIFIER -'))
    $result = Invoke-Checker $notifierPath 'src/state.js'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output -match 'NONE_NOTIFIER_REQUIRES_OWNER_MEDIATED_STOPLINE') 'notifier-none-boundary' $result.Output

    $starterProject = Read-StrictUtf8NoBom (Join-Path $versionRoot 'project-starter\project.json')
    $starterBootstrap = Read-StrictUtf8NoBom (Join-Path $versionRoot 'project-starter\BOOTSTRAP.md')
    Assert-True ($starterProject -match '"schemaVersion"\s*:\s*2' -and $starterProject.Contains('"controlPlaneLayout": "repo-local"') -and $starterProject.Contains('"repositoryRoot": ".."') -and $starterProject -match '\{\{FRAMEWORK_VERSION_JSON\}\}' -and $starterBootstrap.Contains('<!-- FRAMEWORK-MANAGED:BEGIN -->') -and $starterBootstrap.Contains('<!-- PROJECT-CUSTOM:BEGIN -->') -and $starterBootstrap -match 'framework/versions/\{\{FRAMEWORK_VERSION\}\}/scripts/check-task-card\.ps1' -and $starterBootstrap -notmatch '(?i)[A-Z]:\\[^\r\n]*framework\\versions') 'repo-local-starter-schema-and-relative-bootstrap-contract'

    $governanceText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'GOVERNANCE.md')
    $workflowText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'WORKFLOW_PLAYBOOK.md')
    $promptsText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'PROMPTS.md')
    $reviewText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'REVIEW_CHECKLIST.md')
    $templateText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'TASK_TEMPLATE.md')
    $adapterText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'HOST_ADAPTER_CODEX.md')
    $readmeText = Read-StrictUtf8NoBom (Join-Path $workspaceRoot 'README.md')
    $changelogText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'CHANGELOG.md')
    $currentVersionText = (Read-StrictUtf8NoBom (Join-Path $frameworkRoot 'CURRENT')).Trim()
    $upgradeSource = Read-StrictUtf8NoBom $upgrade
    $registerSource = Read-StrictUtf8NoBom $register
    $coreDocuments = @($governanceText, $workflowText, $promptsText, $reviewText, $templateText)
    $hostAdapterSeparated = @($coreDocuments | Where-Object { $_.Contains('wait_threads') -or $_.Contains('send_message_to_thread') -or [regex]::IsMatch($_, '(?<![A-Za-z])ACK(?![A-Za-z])') }).Count -eq 0 -and
        $adapterText.Contains('wait_threads') -and $adapterText.Contains('ACK') -and $adapterText.Contains('idle') -and
        $adapterText.Contains((Expand-UnicodeText '\u7528\u6237\u660e\u786e\u8981\u6c42\u540c\u6b65\u7b49\u5f85')) -and
        $adapterText -match ((Expand-UnicodeText '\u5f53\u524d') + '\s*turn\s*' + (Expand-UnicodeText '\u5fc5\u987b\u6d88\u8d39')) -and
        $adapterText.Contains((Expand-UnicodeText '\u4e3b\u52a8\u56de\u4f20'))
    Assert-True $hostAdapterSeparated 'host-communication-adapter-separated-from-core'

    $reachabilityDocuments = @($governanceText, $workflowText, $promptsText, $reviewText, $templateText)
    $reachabilityContractPresent = @($reachabilityDocuments | Where-Object {
        -not $_.Contains('CURRENT_REACHABLE') -or -not $_.Contains('CONTRACT_REACHABLE') -or -not $_.Contains('FUTURE_ONLY') -or -not $_.Contains('UNVERIFIED')
    }).Count -eq 0 -and $workflowText.Contains((Expand-UnicodeText '\u4e0d\u4e3a\u5b83\u5236\u9020\u5047UI'))
    Assert-True $reachabilityContractPresent 'reachability-grades-and-proportional-evidence'

    $repoLocalDocuments = @($governanceText, $workflowText, $promptsText, $reviewText, $templateText)
    $repoLocalContractPresent = @($repoLocalDocuments | Where-Object { -not $_.Contains('.ai-workspace') -or -not $_.Contains('repo-local') }).Count -eq 0 -and
        $governanceText.Contains('ALREADY_REGISTERED') -and $workflowText.Contains((Expand-UnicodeText '\u4e00\u6b21\u6027\u4e13\u5c5e\u4efb\u52a1')) -and
        $reviewText.Contains('.fwu-prep-*') -and $reviewText.Contains('.fwu-done-*')
    Assert-True $repoLocalContractPresent 'repo-local-discovery-register-and-same-layout-upgrade-contract'

    $migrationProductDocuments = @($readmeText, $changelogText, $governanceText, $workflowText, $promptsText, $reviewText, $registerSource, $upgradeSource)
    $migrationProductPatterns = ('migrate-project-' + 'control-plane|sourceManifest' + 'Sha256|MIGRATED_' + 'CANDIDATE|\.ai-workspace-migration-' + 'transaction')
    $removedMigrationTool = Join-Path $workspaceRoot ('scripts\migrate-project-' + 'control-plane.ps1')
    $genericMigrationProductAbsent = -not (Test-Path -LiteralPath $removedMigrationTool) -and
        @($migrationProductDocuments | Where-Object { $_ -match $migrationProductPatterns }).Count -eq 0
    Assert-True $genericMigrationProductAbsent 'generic-cross-repository-migration-product-absent'

    $releaseDocuments = @($readmeText, $changelogText, $governanceText, $workflowText)
    $releaseContractPresent = @($releaseDocuments | Where-Object { -not $_.Contains('framework/versions/') -or -not $_.Contains('CURRENT') }).Count -eq 0 -and
        @($releaseDocuments | Where-Object { $_.Contains('AI-Workspace-Releases') }).Count -eq 0 -and
        $readmeText.Contains('tag') -and $readmeText.Contains((Expand-UnicodeText '\u53ef\u9009\u5ba1\u8ba1')) -and
        $changelogText.Contains('DRAFT') -and $changelogText.Contains('REVIEW') -and $changelogText.Contains('STABLE') -and $changelogText.Contains('RETIRED') -and
        @($releaseDocuments | Where-Object { -not $_.Contains((Expand-UnicodeText '\u8fdb\u5165STABLE\u5373\u4e0d\u53ef\u539f\u4f4d\u4fee\u6539')) }).Count -eq 0
    Assert-True $releaseContractPresent 'single-repository-multi-version-release-contract'

    $releaseCurrentMatches = $currentVersionText -ceq '1.4.1'
    $releaseMetadataIsStable = $changelogText.Contains((Expand-UnicodeText 'Framework 1.4.1\u662f1.4.0\u53d1\u5e03\u540e\u7684STABLE patch'))
    $releaseMetadataIsCandidate = $changelogText.Contains((Expand-UnicodeText 'repo-local\u9879\u76ee\u63a7\u5236\u9762\u80fd\u529b\u5019\u9009'))
    $releaseMetadataDeniesActivation = $changelogText.Contains((Expand-UnicodeText '\u4e0d\u6388\u6743CURRENT\u6fc0\u6d3b'))
    $releaseStateConsistent = $releaseCurrentMatches -and $releaseMetadataIsStable -and -not $releaseMetadataIsCandidate -and -not $releaseMetadataDeniesActivation
    Assert-True $releaseStateConsistent 'current-and-stable-release-metadata-consistent'

    $entrypointsHaveNoRemoteFallback = @($registerSource, $upgradeSource | Where-Object { $_ -match '(?i)Read-PinnedBootstrapFromLocalTag|refs/tags|cat-file|fetch|pull|clone|remote|ls-remote' }).Count -eq 0 -and
        $upgradeSource.Contains('tags and current HEAD are not runtime fallbacks') -and
        @($registerSource, $upgradeSource | Where-Object { $_ -match '(?im)^\s*(?:&\s*)?git(?:\.exe)?\s+(?:add|commit|checkout|switch|tag|push|reset|rm|mv)\b' }).Count -eq 0
    Assert-True $entrypointsHaveNoRemoteFallback 'root-entrypoints-no-tag-head-remote-or-git-write-fallback'

    $stableVersionNames = @(Get-ChildItem -LiteralPath $versionsRoot -Directory | Where-Object { $_.Name -ne '1.4.1' } | Sort-Object -Property Name | ForEach-Object { $_.Name })
    $stableManifestBefore = @($stableVersionNames | ForEach-Object { [ordered]@{ version = $_; manifest = Get-DirectoryHashManifest (Join-Path $versionsRoot $_) } }) | ConvertTo-Json -Depth 5 -Compress

    $registerWorkspace = Join-Path $testRoot 'register-workspace'
    Copy-StarterWorkspace $registerWorkspace '1.3.2'
    $registerScript = Join-Path $registerWorkspace 'scripts\register-project.ps1'
    $registerRepo = Join-Path $testRoot 'register-repository'
    Initialize-GitRepository $registerRepo
    $registerPreview = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'new-project', '-DisplayName', 'New Project', '-RepositoryPath', $registerRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace)
    Assert-True ($registerPreview.ExitCode -eq 0 -and $registerPreview.Output -match 'WHAT_IF' -and -not (Test-Path -LiteralPath (Join-Path $registerRepo '.ai-workspace'))) 'register-default-preview-zero-write' $registerPreview.Output

    $registerApply = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'new-project', '-DisplayName', 'New Project', '-RepositoryPath', $registerRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    $registeredRoot = Join-Path $registerRepo '.ai-workspace'
    $registeredConfig = Read-StrictUtf8NoBom (Join-Path $registeredRoot 'project.json') | ConvertFrom-Json
    $registeredFiles = @(Get-ChildItem -LiteralPath $registeredRoot -Recurse -File -Force)
    $strictRegisteredFiles = @($registeredFiles | Where-Object { try { $null = Read-StrictUtf8NoBom $_.FullName; $true } catch { $false } }).Count
    Assert-True ($registerApply.ExitCode -eq 0 -and $registerApply.Output -match 'CREATED' -and $registeredConfig.schemaVersion -eq 2 -and $registeredConfig.controlPlaneLayout -ceq 'repo-local' -and $registeredConfig.repositoryRoot -ceq '..' -and $registeredConfig.frameworkVersion -ceq '1.4.1' -and $strictRegisteredFiles -eq $registeredFiles.Count -and (Test-Path -LiteralPath (Join-Path $registeredRoot '.gitattributes') -PathType Leaf)) 'register-explicit-1.4.1-apply-schema2-strict-lf' $registerApply.Output

    $registerAgain = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'new-project', '-DisplayName', 'New Project', '-RepositoryPath', $registerRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($registerAgain.ExitCode -eq 0 -and $registerAgain.Output -match 'ALREADY_REGISTERED') 'register-idempotent-complete-same-identity' $registerAgain.Output

    $registerAgainWithoutVersion = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'new-project', '-DisplayName', 'New Project', '-RepositoryPath', $registerRepo, '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($registerAgainWithoutVersion.ExitCode -eq 0 -and $registerAgainWithoutVersion.Output -match 'ALREADY_REGISTERED' -and $registerAgainWithoutVersion.Output -match '1\.4\.1') 'register-existing-repo-local-pin-precedes-current-default' $registerAgainWithoutVersion.Output

    $registerExplicitPinConflict = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'new-project', '-DisplayName', 'New Project', '-RepositoryPath', $registerRepo, '-FrameworkVersion', '1.4.2', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($registerExplicitPinConflict.ExitCode -ne 0 -and $registerExplicitPinConflict.Output -match 'Framework pin conflicts' -and $registerExplicitPinConflict.Output -notmatch 'ALREADY_REGISTERED') 'register-explicit-version-conflict-with-existing-pin-refused-before-starter-selection' $registerExplicitPinConflict.Output

    $managedRegisterRepo = Join-Path $testRoot 'register-managed-customization-repository'
    Initialize-GitRepository $managedRegisterRepo
    $managedRegisterCreate = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'managed-register', '-DisplayName', 'Managed Register', '-RepositoryPath', $managedRegisterRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    $managedRegisterRoot = Join-Path $managedRegisterRepo '.ai-workspace'
    $managedRegisterBootstrap = Join-Path $managedRegisterRoot 'BOOTSTRAP.md'
    $managedRegisterText = (Read-StrictUtf8NoBom $managedRegisterBootstrap).Replace("<!-- FRAMEWORK-MANAGED:BEGIN -->`n", "<!-- FRAMEWORK-MANAGED:BEGIN -->`nmanaged owner edit that keeps the locator`n")
    Write-Utf8NoBom $managedRegisterBootstrap $managedRegisterText
    $managedRegisterBefore = Get-DirectoryHashManifest $managedRegisterRoot
    $managedRegisterAgain = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'managed-register', '-DisplayName', 'Managed Register', '-RepositoryPath', $managedRegisterRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($managedRegisterCreate.ExitCode -eq 0 -and $managedRegisterAgain.ExitCode -ne 0 -and $managedRegisterAgain.Output -match 'managed\s+block was customized' -and (Get-DirectoryHashManifest $managedRegisterRoot) -ceq $managedRegisterBefore) 'register-managed-body-customization-with-locator-conflicts-and-is-preserved' $managedRegisterAgain.Output

    foreach ($markerCase in @(
        [pscustomobject]@{ Id = 'register-custom-missing'; Name = 'missing'; Transform = 'missing' },
        [pscustomobject]@{ Id = 'register-custom-duplicate'; Name = 'duplicate'; Transform = 'duplicate' },
        [pscustomobject]@{ Id = 'register-custom-wrong-order'; Name = 'wrong-order'; Transform = 'wrong-order' }
    )) {
        $markerRepo = Join-Path $testRoot "$($markerCase.Id)-repository"
        Initialize-GitRepository $markerRepo
        $markerCreate = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', $markerCase.Id, '-DisplayName', "Register Custom $($markerCase.Name)", '-RepositoryPath', $markerRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
        $markerRoot = Join-Path $markerRepo '.ai-workspace'
        $markerBootstrap = Join-Path $markerRoot 'BOOTSTRAP.md'
        $markerText = Read-StrictUtf8NoBom $markerBootstrap
        if ($markerCase.Transform -ceq 'missing') {
            $markerText = $markerText.Replace('<!-- PROJECT-CUSTOM:END -->', '')
        }
        elseif ($markerCase.Transform -ceq 'duplicate') {
            $markerText = $markerText.Replace('<!-- PROJECT-CUSTOM:BEGIN -->', "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:BEGIN -->")
        }
        else {
            $markerText = $markerText.Replace('<!-- PROJECT-CUSTOM:BEGIN -->', '<!-- PROJECT-CUSTOM:TEMP -->').Replace('<!-- PROJECT-CUSTOM:END -->', '<!-- PROJECT-CUSTOM:BEGIN -->').Replace('<!-- PROJECT-CUSTOM:TEMP -->', '<!-- PROJECT-CUSTOM:END -->')
        }
        Write-Utf8NoBom $markerBootstrap $markerText
        $markerBefore = Get-DirectoryHashManifest $markerRoot
        $markerAgain = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', $markerCase.Id, '-DisplayName', "Register Custom $($markerCase.Name)", '-RepositoryPath', $markerRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
        Assert-True ($markerCreate.ExitCode -eq 0 -and $markerAgain.ExitCode -ne 0 -and $markerAgain.Output -match 'markers must' -and $markerAgain.Output -notmatch 'ALREADY_REGISTERED' -and (Get-DirectoryHashManifest $markerRoot) -ceq $markerBefore) "register-project-custom-$($markerCase.Name)-conflicts-and-is-preserved" $markerAgain.Output
    }

    Remove-Item -LiteralPath (Join-Path $registeredRoot 'PROJECT.md') -Force
    Write-Utf8NoBom (Join-Path $registeredRoot 'unknown-live.md') "unknown owner bytes`n"
    $registerIncompleteIdentity = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'new-project', '-DisplayName', 'New Project', '-RepositoryPath', $registerRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($registerIncompleteIdentity.ExitCode -ne 0 -and $registerIncompleteIdentity.Output -match 'inventory conflicts' -and -not (Test-Path -LiteralPath (Join-Path $registeredRoot 'PROJECT.md')) -and (Test-Path -LiteralPath (Join-Path $registeredRoot 'unknown-live.md') -PathType Leaf)) 'register-valid-identity-with-missing-and-unknown-live-conflicts-preserved' $registerIncompleteIdentity.Output

    $defaultOldRepo = Join-Path $testRoot 'register-current-old-repository'
    Initialize-GitRepository $defaultOldRepo
    $defaultOld = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'current-old', '-DisplayName', 'Current Old', '-RepositoryPath', $defaultOldRepo, '-WorkspaceRoot', $registerWorkspace)
    Assert-True ($defaultOld.ExitCode -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $defaultOldRepo '.ai-workspace'))) 'register-current-1.3.2-fails-closed-no-topology-guess' $defaultOld.Output

    $registerCurrentWorkspace = Join-Path $testRoot 'register-current-workspace'
    Copy-StarterWorkspace $registerCurrentWorkspace '1.4.1'
    $defaultNewRepo = Join-Path $testRoot 'register-current-new-repository'
    Initialize-GitRepository $defaultNewRepo
    $defaultNew = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $registerCurrentWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'current-new', '-DisplayName', 'Current New', '-RepositoryPath', $defaultNewRepo, '-WorkspaceRoot', $registerCurrentWorkspace)
    Assert-True ($defaultNew.ExitCode -eq 0 -and $defaultNew.Output -match 'WHAT_IF' -and $defaultNew.Output -match '1\.4\.1') 'register-current-default-when-current-is-repo-local-capable' $defaultNew.Output

    $dirtyRepo = Join-Path $testRoot 'register-dirty-repository'
    Initialize-GitRepository $dirtyRepo
    Write-Utf8NoBom (Join-Path $dirtyRepo 'dirty.txt') "dirty`n"
    $dirtyRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'dirty-project', '-DisplayName', 'Dirty Project', '-RepositoryPath', $dirtyRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($dirtyRegister.ExitCode -ne 0 -and $dirtyRegister.Output -match 'working tree must be clean' -and -not (Test-Path -LiteralPath (Join-Path $dirtyRepo '.ai-workspace'))) 'register-dirty-repository-refusal' $dirtyRegister.Output

    $nonGitRepo = Join-Path $testRoot 'register-nongit'
    New-Item -ItemType Directory -Path $nonGitRepo | Out-Null
    $nonGitRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'nongit-project', '-DisplayName', 'NonGit Project', '-RepositoryPath', $nonGitRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($nonGitRegister.ExitCode -ne 0 -and $nonGitRegister.Output -match 'not a Git work tree') 'register-non-git-refusal' $nonGitRegister.Output

    $nestedRegisterRepo = Join-Path $testRoot 'register-nested-repository'
    Initialize-GitRepository $nestedRegisterRepo
    $nestedRegisterPath = Join-Path $nestedRegisterRepo 'nested'
    New-Item -ItemType Directory -Path $nestedRegisterPath | Out-Null
    $nestedRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'nested-project', '-DisplayName', 'Nested Project', '-RepositoryPath', $nestedRegisterPath, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($nestedRegister.ExitCode -ne 0 -and $nestedRegister.Output -match 'must be the Git top level') 'register-non-root-path-refusal' $nestedRegister.Output

    $brokenRegisterWorkspace = Join-Path $testRoot 'register-broken-workspace'
    Copy-StarterWorkspace $brokenRegisterWorkspace '1.4.1'
    $brokenTemplate = Join-Path $brokenRegisterWorkspace 'framework\versions\1.4.1\project-starter\PROJECT.md'
    Write-Utf8NoBom $brokenTemplate ((Read-StrictUtf8NoBom $brokenTemplate) + "{{UNRESOLVED_TOKEN}}`n")
    $brokenRegisterRepo = Join-Path $testRoot 'register-broken-repository'
    Initialize-GitRepository $brokenRegisterRepo
    $brokenRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $brokenRegisterWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'broken-project', '-DisplayName', 'Broken Project', '-RepositoryPath', $brokenRegisterRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $brokenRegisterWorkspace, '-Apply')
    $brokenResidue = @(Get-ChildItem -LiteralPath $brokenRegisterRepo -Directory -Force | Where-Object { $_.Name -like '.broken-project.ai-workspace-init.*' })
    Assert-True ($brokenRegister.ExitCode -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $brokenRegisterRepo '.ai-workspace')) -and $brokenResidue.Count -eq 0) 'register-template-failure-no-live-or-staging-residue' $brokenRegister.Output

    $partialRepo = Join-Path $testRoot 'register-partial-repository'
    Initialize-GitRepository $partialRepo
    New-Item -ItemType Directory -Path (Join-Path $partialRepo '.ai-workspace') | Out-Null
    Write-Utf8NoBom (Join-Path $partialRepo '.ai-workspace\unknown.md') "unknown`n"
    $partialRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'partial-project', '-DisplayName', 'Partial Project', '-RepositoryPath', $partialRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($partialRegister.ExitCode -ne 0 -and $partialRegister.Output -match 'partial') 'register-partial-target-preserved' $partialRegister.Output

    $registerFileRepo = Join-Path $testRoot 'register-file-repository'
    Initialize-GitRepository $registerFileRepo
    $registerFileTarget = Join-Path $registerFileRepo '.ai-workspace'
    Write-Utf8NoBom $registerFileTarget "file conflict`n"
    $registerFile = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'file-project', '-DisplayName', 'File Project', '-RepositoryPath', $registerFileRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($registerFile.ExitCode -ne 0 -and $registerFile.Output -match 'not a directory' -and (Test-Path -LiteralPath $registerFileTarget -PathType Leaf)) 'register-file-target-conflict-preserved' $registerFile.Output

    $registerReparseRepo = Join-Path $testRoot 'register-reparse-repository'
    Initialize-GitRepository $registerReparseRepo
    $registerReparseExternal = Join-Path $testRoot 'register-reparse-external'
    New-Item -ItemType Directory -Path $registerReparseExternal | Out-Null
    Write-Utf8NoBom (Join-Path $registerReparseExternal 'unknown-owner-byte.md') "external bytes`n"
    $null = New-Item -ItemType Junction -Path (Join-Path $registerReparseRepo '.ai-workspace') -Target $registerReparseExternal
    $registerReparse = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'reparse-project', '-DisplayName', 'Reparse Project', '-RepositoryPath', $registerReparseRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($registerReparse.ExitCode -ne 0 -and $registerReparse.Output -match 'Reparse points are not allowed' -and (Test-Path -LiteralPath (Join-Path $registerReparseExternal 'unknown-owner-byte.md') -PathType Leaf)) 'register-reparse-target-conflict-preserved' $registerReparse.Output

    $registerIdentityRepo = Join-Path $testRoot 'register-identity-repository'
    Initialize-GitRepository $registerIdentityRepo
    $registerIdentityCreate = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'identity-one', '-DisplayName', 'Identity One', '-RepositoryPath', $registerIdentityRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    $registerIdentityConflict = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'identity-two', '-DisplayName', 'Identity Two', '-RepositoryPath', $registerIdentityRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    $registerIdentityConfig = Read-StrictUtf8NoBom (Join-Path $registerIdentityRepo '.ai-workspace\project.json') | ConvertFrom-Json
    Assert-True ($registerIdentityCreate.ExitCode -eq 0 -and $registerIdentityConflict.ExitCode -ne 0 -and $registerIdentityConflict.Output -match 'identity conflicts' -and [string]$registerIdentityConfig.id -ceq 'identity-one') 'register-existing-target-identity-conflict-preserved' $registerIdentityConflict.Output

    foreach ($centralCollisionCase in @(
        [pscustomobject]@{ Id = 'register-central-file'; Kind = 'file' },
        [pscustomobject]@{ Id = 'register-central-partial'; Kind = 'partial' },
        [pscustomobject]@{ Id = 'register-central-reparse'; Kind = 'reparse' }
    )) {
        $centralCollisionRepo = Join-Path $testRoot "$($centralCollisionCase.Id)-repository"
        Initialize-GitRepository $centralCollisionRepo
        $centralCollisionCreate = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', $centralCollisionCase.Id, '-DisplayName', "Central $($centralCollisionCase.Kind)", '-RepositoryPath', $centralCollisionRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
        $centralCollisionRoot = Join-Path $registerWorkspace "projects\$($centralCollisionCase.Id)"
        $centralCollisionWitness = $centralCollisionRoot
        if ($centralCollisionCase.Kind -ceq 'file') {
            Write-Utf8NoBom $centralCollisionRoot "central file collision`n"
        }
        elseif ($centralCollisionCase.Kind -ceq 'partial') {
            $null = New-LegacyProject $registerWorkspace $centralCollisionCase.Id "Central $($centralCollisionCase.Kind)" $centralCollisionRepo '1.3.0'
            Remove-Item -LiteralPath (Join-Path $centralCollisionRoot 'BOOTSTRAP.md') -Force
            $centralCollisionWitness = Join-Path $centralCollisionRoot 'project.json'
        }
        else {
            $centralCollisionExternal = Join-Path $testRoot "$($centralCollisionCase.Id)-external"
            New-Item -ItemType Directory -Path $centralCollisionExternal | Out-Null
            $centralCollisionWitness = Join-Path $centralCollisionExternal 'unknown-owner-byte.md'
            Write-Utf8NoBom $centralCollisionWitness "central reparse collision`n"
            $null = New-Item -ItemType Junction -Path $centralCollisionRoot -Target $centralCollisionExternal
        }
        $centralCollisionAgain = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', $centralCollisionCase.Id, '-DisplayName', "Central $($centralCollisionCase.Kind)", '-RepositoryPath', $centralCollisionRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
        Assert-True ($centralCollisionCreate.ExitCode -eq 0 -and $centralCollisionAgain.ExitCode -ne 0 -and $centralCollisionAgain.Output -match 'central|Reparse' -and $centralCollisionAgain.Output -notmatch 'ALREADY_REGISTERED' -and (Test-Path -LiteralPath $centralCollisionWitness)) "register-existing-repo-local-central-$($centralCollisionCase.Kind)-collision-fails-closed-and-preserves-bytes" $centralCollisionAgain.Output
    }

    $legacyConflictRepo = Join-Path $testRoot 'register-legacy-conflict-repository'
    Initialize-GitRepository $legacyConflictRepo
    $null = New-LegacyProject $registerWorkspace 'legacy-conflict' 'Legacy Conflict' $legacyConflictRepo '1.3.0'
    $legacyConflict = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $registerScript, '-ProjectId', 'legacy-conflict', '-DisplayName', 'Legacy Conflict', '-RepositoryPath', $legacyConflictRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $registerWorkspace, '-Apply')
    Assert-True ($legacyConflict.ExitCode -ne 0 -and $legacyConflict.Output -match 'central legacy project') 'register-central-same-id-refusal' $legacyConflict.Output

    $upgradeWorkspace = Join-Path $testRoot 'upgrade-workspace'
    Copy-StarterWorkspace $upgradeWorkspace '1.3.2'
    $upgradeScript = Join-Path $upgradeWorkspace 'scripts\upgrade-project.ps1'
    $centralUpgradeRepo = Join-Path $testRoot 'central-upgrade-repository'
    Initialize-GitRepository $centralUpgradeRepo
    $legacyUpgradeRoot = New-LegacyProject $upgradeWorkspace 'legacy-upgrade' 'Legacy Upgrade' $centralUpgradeRepo '1.3.0'
    $legacyUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'legacy-upgrade', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $legacyUpgradeConfig = Read-StrictUtf8NoBom (Join-Path $legacyUpgradeRoot 'project.json') | ConvertFrom-Json
    Assert-True ($legacyUpgrade.ExitCode -eq 0 -and $legacyUpgradeConfig.frameworkVersion -ceq '1.3.2' -and (Read-StrictUtf8NoBom (Join-Path $legacyUpgradeRoot 'BOOTSTRAP.md')) -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1' -and (Get-UpgradeResidue $legacyUpgradeRoot).Count -eq 0) 'upgrade-central-1.3.0-to-1.3.2-compatibility' $legacyUpgrade.Output

    $retiredTargetRoot = New-LegacyProject $upgradeWorkspace 'retired-target' 'Retired Target' $centralUpgradeRepo '1.3.2'
    $retiredTargetBefore = Get-DirectoryHashManifest $retiredTargetRoot
    $retiredTarget = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'retired-target', '-ToVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    Assert-True ($retiredTarget.ExitCode -ne 0 -and $retiredTarget.Output -match '1\.3\.0 runtime compatibility is retired' -and (Get-DirectoryHashManifest $retiredTargetRoot) -ceq $retiredTargetBefore) 'upgrade-retired-1.3.0-target-refused-without-write' $retiredTarget.Output

    $upgradeRollbackRoot = New-LegacyProject $upgradeWorkspace 'upgrade-rollback' 'Upgrade Rollback' $centralUpgradeRepo '1.3.0'
    $upgradeRollbackProject = Join-Path $upgradeRollbackRoot 'project.json'
    $upgradeRollbackBootstrap = Join-Path $upgradeRollbackRoot 'BOOTSTRAP.md'
    $rollbackProjectBefore = (Get-FileHash -LiteralPath $upgradeRollbackProject -Algorithm SHA256).Hash
    $rollbackBootstrapBefore = (Get-FileHash -LiteralPath $upgradeRollbackBootstrap -Algorithm SHA256).Hash
    (Get-Item -LiteralPath $upgradeRollbackBootstrap).IsReadOnly = $true
    try {
        $upgradeRollback = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-rollback', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    }
    finally {
        (Get-Item -LiteralPath $upgradeRollbackBootstrap).IsReadOnly = $false
    }
    $rollbackConfig = Read-StrictUtf8NoBom $upgradeRollbackProject | ConvertFrom-Json
    $rollbackProjectAfter = (Get-FileHash -LiteralPath $upgradeRollbackProject -Algorithm SHA256).Hash
    $rollbackBootstrapAfter = (Get-FileHash -LiteralPath $upgradeRollbackBootstrap -Algorithm SHA256).Hash
    $rollbackResidue = Get-UpgradeResidue $upgradeRollbackRoot
    Assert-True ($upgradeRollback.ExitCode -ne 0 -and $rollbackConfig.frameworkVersion -ceq '1.3.0' -and $rollbackProjectBefore -ceq $rollbackProjectAfter -and $rollbackBootstrapBefore -ceq $rollbackBootstrapAfter -and $rollbackResidue.Count -eq 0) 'upgrade-commit-failure-rolls-back-without-residue' $upgradeRollback.Output

    $upgradeInterruptRoot = New-LegacyProject $upgradeWorkspace 'upgrade-interrupt' 'Upgrade Interrupt' $centralUpgradeRepo '1.3.0'
    $upgradeInterrupted = Invoke-InterruptedUpgrade $upgradeScript 'upgrade-interrupt' $upgradeWorkspace
    $interruptTransaction = Join-Path $upgradeInterruptRoot '.framework-upgrade-transaction'
    $interruptedConfig = Read-StrictUtf8NoBom (Join-Path $upgradeInterruptRoot 'project.json') | ConvertFrom-Json
    $interruptedBootstrap = Read-StrictUtf8NoBom (Join-Path $upgradeInterruptRoot 'BOOTSTRAP.md')
    $interruptedStates = @(Get-ChildItem -LiteralPath (Join-Path $interruptTransaction 'states') -File -Filter 'state-*-PROJECT_REPLACED.json' -ErrorAction SilentlyContinue)
    $interruptedMaterialsPresent = (Test-Path -LiteralPath (Join-Path $interruptTransaction 'old\project.json') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $interruptTransaction 'old\BOOTSTRAP.md') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $interruptTransaction 'new\project.json') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $interruptTransaction 'new\BOOTSTRAP.md') -PathType Leaf)
    $interruptRecovered = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-interrupt', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $interruptRecoveredConfig = Read-StrictUtf8NoBom (Join-Path $upgradeInterruptRoot 'project.json') | ConvertFrom-Json
    $interruptRecoveredBootstrap = Read-StrictUtf8NoBom (Join-Path $upgradeInterruptRoot 'BOOTSTRAP.md')
    $interruptRecoveredResidue = Get-UpgradeResidue $upgradeInterruptRoot
    $legacyRootLocator = '`scripts/check-task-card.ps1`'
    Assert-True ($upgradeInterrupted.ExitCode -ne 0 -and $interruptedConfig.frameworkVersion -ceq '1.3.2' -and $interruptedBootstrap.Contains($legacyRootLocator) -and $interruptedStates.Count -ge 1 -and $interruptedMaterialsPresent -and $interruptRecovered.ExitCode -eq 0 -and $interruptRecovered.Output -match 'Recovered previous Framework upgrade transaction: COMMITTED' -and $interruptRecoveredConfig.frameworkVersion -ceq '1.3.2' -and $interruptRecoveredBootstrap -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1' -and -not $interruptRecoveredBootstrap.Contains($legacyRootLocator) -and $interruptRecoveredResidue.Count -eq 0) 'upgrade-first-replace-interruption-recovers-on-next-invocation' ($upgradeInterrupted.Output + "`n" + $interruptRecovered.Output)

    $upgradeRetainedRoot = New-LegacyProject $upgradeWorkspace 'upgrade-retained' 'Upgrade Retained' $centralUpgradeRepo '1.3.0'
    $upgradeRetainedInterrupted = Invoke-InterruptedUpgrade $upgradeScript 'upgrade-retained' $upgradeWorkspace
    $upgradeRetainedProject = Join-Path $upgradeRetainedRoot 'project.json'
    $upgradeRetainedBootstrap = Join-Path $upgradeRetainedRoot 'BOOTSTRAP.md'
    $upgradeRetainedTransaction = Join-Path $upgradeRetainedRoot '.framework-upgrade-transaction'
    (Get-Item -LiteralPath $upgradeRetainedProject).IsReadOnly = $true
    (Get-Item -LiteralPath $upgradeRetainedBootstrap).IsReadOnly = $true
    try {
        $upgradeRecoveryFailed = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-retained', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    }
    finally {
        (Get-Item -LiteralPath $upgradeRetainedProject).IsReadOnly = $false
        (Get-Item -LiteralPath $upgradeRetainedBootstrap).IsReadOnly = $false
    }
    $retainedStates = @(Get-ChildItem -LiteralPath (Join-Path $upgradeRetainedTransaction 'states') -File -Filter 'state-*-RECOVERY_REQUIRED.json' -ErrorAction SilentlyContinue)
    $retainedMaterialsPresent = (Test-Path -LiteralPath (Join-Path $upgradeRetainedTransaction 'old\project.json') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $upgradeRetainedTransaction 'old\BOOTSTRAP.md') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $upgradeRetainedTransaction 'new\project.json') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $upgradeRetainedTransaction 'new\BOOTSTRAP.md') -PathType Leaf)
    $retainedRecovery = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-retained', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $retainedConfig = Read-StrictUtf8NoBom $upgradeRetainedProject | ConvertFrom-Json
    $retainedBootstrap = Read-StrictUtf8NoBom $upgradeRetainedBootstrap
    $retainedResidue = Get-UpgradeResidue $upgradeRetainedRoot
    Assert-True ($upgradeRetainedInterrupted.ExitCode -ne 0 -and $upgradeRecoveryFailed.ExitCode -ne 0 -and $upgradeRecoveryFailed.Output -match 'Recovery materials were preserved' -and $retainedStates.Count -ge 1 -and $retainedMaterialsPresent -and $retainedRecovery.ExitCode -eq 0 -and $retainedRecovery.Output -match 'Recovered previous Framework upgrade transaction: COMMITTED' -and $retainedConfig.frameworkVersion -ceq '1.3.2' -and $retainedBootstrap -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1' -and $retainedResidue.Count -eq 0) 'upgrade-rollback-failure-retains-materials-and-later-recovers' ($upgradeRetainedInterrupted.Output + "`n" + $upgradeRecoveryFailed.Output + "`n" + $retainedRecovery.Output)

    foreach ($residueCase in @(
        [pscustomobject]@{ Kind = 'prep'; Id = 'upgrade-unknown-prep'; TransactionId = '11111111111111111111111111111111' },
        [pscustomobject]@{ Kind = 'done'; Id = 'upgrade-unknown-done'; TransactionId = '22222222222222222222222222222222' }
    )) {
        $residueProjectRoot = New-LegacyProject $upgradeWorkspace $residueCase.Id "Upgrade $($residueCase.Kind)" $centralUpgradeRepo '1.3.0'
        $residueRoot = Join-Path $residueProjectRoot ".fwu-$($residueCase.Kind)-$($residueCase.TransactionId)"
        New-Item -ItemType Directory -Path $residueRoot | Out-Null
        $unknownResiduePath = Join-Path $residueRoot 'unknown-owner-byte.md'
        Write-Utf8NoBom $unknownResiduePath "unknown owner recovery byte`n"
        $residueBefore = Get-DirectoryHashManifest $residueProjectRoot
        $residueUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', $residueCase.Id, '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
        Assert-True ($residueUpgrade.ExitCode -ne 0 -and $residueUpgrade.Output -match 'no valid state|Unknown file in upgrade recovery material' -and (Test-Path -LiteralPath $unknownResiduePath -PathType Leaf) -and (Get-DirectoryHashManifest $residueProjectRoot) -ceq $residueBefore) "upgrade-unknown-$($residueCase.Kind)-residue-conflicts-and-is-preserved" $residueUpgrade.Output
    }

    $centralTopologyRoot = New-LegacyProject $upgradeWorkspace 'central-topology' 'Central Topology' $centralUpgradeRepo '1.3.2'
    $centralTopologyBefore = Get-DirectoryHashManifest $centralTopologyRoot
    $centralTopology = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'central-topology', '-ToVersion', '1.4.1', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    Assert-True ($centralTopology.ExitCode -ne 0 -and $centralTopology.Output -match 'cannot change topology' -and (Get-DirectoryHashManifest $centralTopologyRoot) -ceq $centralTopologyBefore) 'upgrade-central-to-repo-local-topology-refusal' $centralTopology.Output

    $fallbackFileRepo = Join-Path $testRoot 'upgrade-fallback-file-repository'
    Initialize-GitRepository $fallbackFileRepo
    $fallbackFileRoot = New-LegacyProject $upgradeWorkspace 'fallback-file' 'Fallback File' $fallbackFileRepo '1.3.0'
    $fallbackFileBefore = Get-DirectoryHashManifest $fallbackFileRoot
    Write-Utf8NoBom (Join-Path $fallbackFileRepo '.ai-workspace') "repo-local file conflict`n"
    $fallbackFileUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $upgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'fallback-file', '-RepositoryPath', $fallbackFileRepo, '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    Assert-True ($fallbackFileUpgrade.ExitCode -ne 0 -and $fallbackFileUpgrade.Output -match 'refusing central fallback' -and (Get-DirectoryHashManifest $fallbackFileRoot) -ceq $fallbackFileBefore) 'upgrade-repo-local-file-never-falls-back-central' $fallbackFileUpgrade.Output

    $customLegacyRoot = New-LegacyProject $upgradeWorkspace 'custom-legacy' 'Custom Legacy' $centralUpgradeRepo '1.3.0'
    $customLegacyBootstrap = Join-Path $customLegacyRoot 'BOOTSTRAP.md'
    Write-Utf8NoBom $customLegacyBootstrap ((Read-StrictUtf8NoBom $customLegacyBootstrap) + "custom legacy Bootstrap bytes`n")
    $customLegacyBefore = Get-DirectoryHashManifest $customLegacyRoot
    $customLegacyUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'custom-legacy', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    Assert-True ($customLegacyUpgrade.ExitCode -ne 0 -and $customLegacyUpgrade.Output -match 'does not match its pinned Framework starter' -and (Get-DirectoryHashManifest $customLegacyRoot) -ceq $customLegacyBefore) 'upgrade-unmarked-custom-legacy-bootstrap-refusal' $customLegacyUpgrade.Output

    $missingSourceRoot = New-LegacyProject $upgradeWorkspace 'missing-source' 'Missing Source' $centralUpgradeRepo '1.3.0'
    $missingSourceBefore = Get-DirectoryHashManifest $missingSourceRoot
    Remove-Item -LiteralPath (Join-Path $upgradeWorkspace 'framework\versions\1.3.0') -Recurse -Force
    $missingSource = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'missing-source', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    Assert-True ($missingSource.ExitCode -ne 0 -and $missingSource.Output -match 'tags and current HEAD are not runtime fallbacks' -and (Get-DirectoryHashManifest $missingSourceRoot) -ceq $missingSourceBefore) 'upgrade-missing-pinned-version-no-fallback-no-write' $missingSource.Output

    $repoUpgradeWorkspace = Join-Path $testRoot 'repo-upgrade-workspace'
    Copy-StarterWorkspace $repoUpgradeWorkspace '1.4.1'
    Copy-Item -LiteralPath (Join-Path $repoUpgradeWorkspace 'framework\versions\1.4.1') -Destination (Join-Path $repoUpgradeWorkspace 'framework\versions\1.4.2') -Recurse

    $dualAuthorityRepo = Join-Path $testRoot 'dual-authority-repository'
    Initialize-GitRepository $dualAuthorityRepo
    $dualRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'dual-authority', '-DisplayName', 'Dual Authority', '-RepositoryPath', $dualAuthorityRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    & git -C $dualAuthorityRepo add -- .ai-workspace
    & git -C $dualAuthorityRepo commit --quiet -m 'repo-local authority baseline'
    $dualRepoLocalRoot = Join-Path $dualAuthorityRepo '.ai-workspace'
    $dualCentralRoot = New-LegacyProject $repoUpgradeWorkspace 'dual-authority' 'Dual Authority' $dualAuthorityRepo '1.3.0'
    $dualCentralBefore = Get-DirectoryHashManifest $dualCentralRoot
    $dualRepoLocalBefore = Get-DirectoryHashManifest $dualRepoLocalRoot
    $dualCentralTargetAttempt = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'dual-authority', '-ToVersion', '1.3.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    Assert-True ($dualRegister.ExitCode -eq 0 -and $dualCentralTargetAttempt.ExitCode -ne 0 -and $dualCentralTargetAttempt.Output -match 'repo-local project can only upgrade' -and (Get-DirectoryHashManifest $dualCentralRoot) -ceq $dualCentralBefore -and (Get-DirectoryHashManifest $dualRepoLocalRoot) -ceq $dualRepoLocalBefore) 'upgrade-omitted-repository-valid-dual-layout-never-mutates-central-for-central-target' $dualCentralTargetAttempt.Output

    $dualRepoLocalUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'dual-authority', '-ToVersion', '1.4.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    $dualRepoLocalConfig = Read-StrictUtf8NoBom (Join-Path $dualRepoLocalRoot 'project.json') | ConvertFrom-Json
    Assert-True ($dualRepoLocalUpgrade.ExitCode -eq 0 -and $dualRepoLocalConfig.frameworkVersion -ceq '1.4.2' -and (Get-DirectoryHashManifest $dualCentralRoot) -ceq $dualCentralBefore) 'upgrade-omitted-repository-valid-dual-layout-selects-repo-local-authority' $dualRepoLocalUpgrade.Output

    $omittedPartialRepo = Join-Path $testRoot 'omitted-partial-repository'
    Initialize-GitRepository $omittedPartialRepo
    $omittedPartialCentral = New-LegacyProject $repoUpgradeWorkspace 'omitted-partial' 'Omitted Partial' $omittedPartialRepo '1.3.0'
    $omittedPartialCentralBefore = Get-DirectoryHashManifest $omittedPartialCentral
    New-Item -ItemType Directory -Path (Join-Path $omittedPartialRepo '.ai-workspace') | Out-Null
    $omittedPartialWitness = Join-Path $omittedPartialRepo '.ai-workspace\unknown-owner-byte.md'
    Write-Utf8NoBom $omittedPartialWitness "partial repo-local collision`n"
    $omittedPartialUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'omitted-partial', '-ToVersion', '1.3.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    Assert-True ($omittedPartialUpgrade.ExitCode -ne 0 -and (Get-DirectoryHashManifest $omittedPartialCentral) -ceq $omittedPartialCentralBefore -and (Test-Path -LiteralPath $omittedPartialWitness -PathType Leaf)) 'upgrade-omitted-repository-partial-repo-local-fails-closed-and-freezes-central' $omittedPartialUpgrade.Output

    foreach ($upgradeCentralCollisionCase in @(
        [pscustomobject]@{ Id = 'upgrade-central-file'; Kind = 'file' },
        [pscustomobject]@{ Id = 'upgrade-central-partial'; Kind = 'partial' },
        [pscustomobject]@{ Id = 'upgrade-central-reparse'; Kind = 'reparse' }
    )) {
        $upgradeCentralCollisionRepo = Join-Path $testRoot "$($upgradeCentralCollisionCase.Id)-repository"
        Initialize-GitRepository $upgradeCentralCollisionRepo
        $upgradeCentralCollisionRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\register-project.ps1'), '-ProjectId', $upgradeCentralCollisionCase.Id, '-DisplayName', "Upgrade Central $($upgradeCentralCollisionCase.Kind)", '-RepositoryPath', $upgradeCentralCollisionRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
        & git -C $upgradeCentralCollisionRepo add -- .ai-workspace
        & git -C $upgradeCentralCollisionRepo commit --quiet -m 'repo-local baseline'
        $upgradeCentralCollisionRoot = Join-Path $repoUpgradeWorkspace "projects\$($upgradeCentralCollisionCase.Id)"
        $upgradeCentralCollisionWitness = $upgradeCentralCollisionRoot
        if ($upgradeCentralCollisionCase.Kind -ceq 'file') {
            Write-Utf8NoBom $upgradeCentralCollisionRoot "central owner file`n"
        }
        elseif ($upgradeCentralCollisionCase.Kind -ceq 'partial') {
            $null = New-LegacyProject $repoUpgradeWorkspace $upgradeCentralCollisionCase.Id "Upgrade Central $($upgradeCentralCollisionCase.Kind)" $upgradeCentralCollisionRepo '1.3.0'
            Remove-Item -LiteralPath (Join-Path $upgradeCentralCollisionRoot 'BOOTSTRAP.md') -Force
            $upgradeCentralCollisionWitness = Join-Path $upgradeCentralCollisionRoot 'project.json'
        }
        else {
            $upgradeCentralCollisionExternal = Join-Path $testRoot "$($upgradeCentralCollisionCase.Id)-external"
            New-Item -ItemType Directory -Path $upgradeCentralCollisionExternal | Out-Null
            $upgradeCentralCollisionWitness = Join-Path $upgradeCentralCollisionExternal 'unknown-owner-byte.md'
            Write-Utf8NoBom $upgradeCentralCollisionWitness "central owner reparse byte`n"
            $null = New-Item -ItemType Junction -Path $upgradeCentralCollisionRoot -Target $upgradeCentralCollisionExternal
        }
        $upgradeCentralCollisionResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', $upgradeCentralCollisionCase.Id, '-RepositoryPath', $upgradeCentralCollisionRepo, '-ToVersion', '1.4.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
        Assert-True ($upgradeCentralCollisionRegister.ExitCode -eq 0 -and $upgradeCentralCollisionResult.ExitCode -ne 0 -and $upgradeCentralCollisionResult.Output -match 'central|Reparse' -and (Test-Path -LiteralPath $upgradeCentralCollisionWitness)) "upgrade-repo-local-central-$($upgradeCentralCollisionCase.Kind)-collision-fails-closed-and-preserves-bytes" $upgradeCentralCollisionResult.Output
    }

    foreach ($upgradeMarkerCase in @(
        [pscustomobject]@{ Id = 'upgrade-custom-missing'; Name = 'missing'; Transform = 'missing' },
        [pscustomobject]@{ Id = 'upgrade-custom-duplicate'; Name = 'duplicate'; Transform = 'duplicate' },
        [pscustomobject]@{ Id = 'upgrade-custom-wrong-order'; Name = 'wrong-order'; Transform = 'wrong-order' }
    )) {
        $upgradeMarkerRepo = Join-Path $testRoot "$($upgradeMarkerCase.Id)-repository"
        Initialize-GitRepository $upgradeMarkerRepo
        $upgradeMarkerRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\register-project.ps1'), '-ProjectId', $upgradeMarkerCase.Id, '-DisplayName', "Upgrade Custom $($upgradeMarkerCase.Name)", '-RepositoryPath', $upgradeMarkerRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
        $upgradeMarkerRoot = Join-Path $upgradeMarkerRepo '.ai-workspace'
        $upgradeMarkerBootstrap = Join-Path $upgradeMarkerRoot 'BOOTSTRAP.md'
        $upgradeMarkerText = Read-StrictUtf8NoBom $upgradeMarkerBootstrap
        if ($upgradeMarkerCase.Transform -ceq 'missing') {
            $upgradeMarkerText = $upgradeMarkerText.Replace('<!-- PROJECT-CUSTOM:END -->', '')
        }
        elseif ($upgradeMarkerCase.Transform -ceq 'duplicate') {
            $upgradeMarkerText = $upgradeMarkerText.Replace('<!-- PROJECT-CUSTOM:BEGIN -->', "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:BEGIN -->")
        }
        else {
            $upgradeMarkerText = $upgradeMarkerText.Replace('<!-- PROJECT-CUSTOM:BEGIN -->', '<!-- PROJECT-CUSTOM:TEMP -->').Replace('<!-- PROJECT-CUSTOM:END -->', '<!-- PROJECT-CUSTOM:BEGIN -->').Replace('<!-- PROJECT-CUSTOM:TEMP -->', '<!-- PROJECT-CUSTOM:END -->')
        }
        Write-Utf8NoBom $upgradeMarkerBootstrap $upgradeMarkerText
        & git -C $upgradeMarkerRepo add -- .ai-workspace
        & git -C $upgradeMarkerRepo commit --quiet -m "malformed custom markers $($upgradeMarkerCase.Name)"
        $upgradeMarkerBefore = Get-DirectoryHashManifest $upgradeMarkerRoot
        $upgradeMarkerResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', $upgradeMarkerCase.Id, '-RepositoryPath', $upgradeMarkerRepo, '-ToVersion', '1.4.1', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
        Assert-True ($upgradeMarkerRegister.ExitCode -eq 0 -and $upgradeMarkerResult.ExitCode -ne 0 -and $upgradeMarkerResult.Output -match 'markers must' -and $upgradeMarkerResult.Output -notmatch 'Already on requested version' -and (Get-DirectoryHashManifest $upgradeMarkerRoot) -ceq $upgradeMarkerBefore) "upgrade-same-version-project-custom-$($upgradeMarkerCase.Name)-conflicts-and-is-preserved" $upgradeMarkerResult.Output
    }

    $repoToCentralRepo = Join-Path $testRoot 'repo-to-central-repository'
    Initialize-GitRepository $repoToCentralRepo
    $repoToCentralRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'repo-to-central', '-DisplayName', 'Repo To Central', '-RepositoryPath', $repoToCentralRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    & git -C $repoToCentralRepo add -- .ai-workspace
    & git -C $repoToCentralRepo commit --quiet -m 'repo-local baseline'
    $repoToCentralRoot = Join-Path $repoToCentralRepo '.ai-workspace'
    $repoToCentralBefore = Get-DirectoryHashManifest $repoToCentralRoot
    $repoToCentralUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'repo-to-central', '-RepositoryPath', $repoToCentralRepo, '-ToVersion', '1.3.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    Assert-True ($repoToCentralRegister.ExitCode -eq 0 -and $repoToCentralUpgrade.ExitCode -ne 0 -and $repoToCentralUpgrade.Output -match 'can only upgrade to a repo-local Framework starter' -and (Get-DirectoryHashManifest $repoToCentralRoot) -ceq $repoToCentralBefore) 'upgrade-repo-local-to-central-topology-refusal' $repoToCentralUpgrade.Output

    $repoUpgradeRepo = Join-Path $testRoot 'repo-upgrade-repository'
    Initialize-GitRepository $repoUpgradeRepo
    $repoRegister = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'repo-upgrade', '-DisplayName', 'Repo Upgrade', '-RepositoryPath', $repoUpgradeRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    & git -C $repoUpgradeRepo add -- .ai-workspace
    & git -C $repoUpgradeRepo commit --quiet -m 'repo-local control plane'
    $repoBootstrapPath = Join-Path $repoUpgradeRepo '.ai-workspace\BOOTSTRAP.md'
    $repoBootstrap = Read-StrictUtf8NoBom $repoBootstrapPath
    $repoBootstrap = $repoBootstrap.Replace("<!-- PROJECT-CUSTOM:BEGIN -->`n", "<!-- PROJECT-CUSTOM:BEGIN -->`nproject custom suffix`n")
    Write-Utf8NoBom $repoBootstrapPath $repoBootstrap
    & git -C $repoUpgradeRepo add -- .ai-workspace/BOOTSTRAP.md
    & git -C $repoUpgradeRepo commit --quiet -m 'custom bootstrap suffix'
    $managedEnd = '<!-- FRAMEWORK-MANAGED:END -->'
    $customSuffixBefore = $repoBootstrap.Substring($repoBootstrap.IndexOf($managedEnd, [System.StringComparison]::Ordinal) + $managedEnd.Length)
    $repoUpgrade = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'repo-upgrade', '-RepositoryPath', $repoUpgradeRepo, '-ToVersion', '1.4.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    $repoUpgradedBootstrap = Read-StrictUtf8NoBom $repoBootstrapPath
    $customSuffixAfter = $repoUpgradedBootstrap.Substring($repoUpgradedBootstrap.IndexOf($managedEnd, [System.StringComparison]::Ordinal) + $managedEnd.Length)
    $repoUpgradedConfig = Read-StrictUtf8NoBom (Join-Path $repoUpgradeRepo '.ai-workspace\project.json') | ConvertFrom-Json
    Assert-True ($repoRegister.ExitCode -eq 0 -and $repoUpgrade.ExitCode -eq 0 -and $repoUpgradedConfig.frameworkVersion -ceq '1.4.2' -and $customSuffixAfter -ceq $customSuffixBefore -and $repoUpgradedBootstrap -match 'framework/versions/1\.4\.2/scripts/check-task-card\.ps1' -and (Get-UpgradeResidue (Join-Path $repoUpgradeRepo '.ai-workspace')).Count -eq 0) 'upgrade-repo-local-managed-block-preserves-custom-suffix-byte-for-byte' ($repoRegister.Output + "`n" + $repoUpgrade.Output)

    & git -C $repoUpgradeRepo add -- .ai-workspace
    & git -C $repoUpgradeRepo commit --quiet -m 'upgrade result'
    $repoUpgradeAgain = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'repo-upgrade', '-RepositoryPath', $repoUpgradeRepo, '-ToVersion', '1.4.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    Assert-True ($repoUpgradeAgain.ExitCode -eq 0 -and $repoUpgradeAgain.Output -match 'Already on requested version') 'upgrade-repo-local-idempotent-after-commit' $repoUpgradeAgain.Output

    $managedConflictRepo = Join-Path $testRoot 'managed-conflict-repository'
    Initialize-GitRepository $managedConflictRepo
    $managedRegistered = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'managed-conflict', '-DisplayName', 'Managed Conflict', '-RepositoryPath', $managedConflictRepo, '-FrameworkVersion', '1.4.1', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    $managedConflictPath = Join-Path $managedConflictRepo '.ai-workspace\BOOTSTRAP.md'
    $managedConflictText = (Read-StrictUtf8NoBom $managedConflictPath).Replace('framework/versions/1.4.1/scripts/check-task-card.ps1', 'framework/versions/1.4.1/scripts/check-task-card.changed.ps1')
    Write-Utf8NoBom $managedConflictPath $managedConflictText
    & git -C $managedConflictRepo add -- .ai-workspace
    & git -C $managedConflictRepo commit --quiet -m 'invalid managed customization'
    $managedConflict = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoUpgradeWorkspace 'scripts\upgrade-project.ps1'), '-ProjectId', 'managed-conflict', '-RepositoryPath', $managedConflictRepo, '-ToVersion', '1.4.2', '-WorkspaceRoot', $repoUpgradeWorkspace, '-Apply')
    Assert-True ($managedRegistered.ExitCode -eq 0 -and $managedConflict.ExitCode -ne 0 -and $managedConflict.Output -match 'managed block was customized') 'upgrade-repo-local-managed-customization-refusal' $managedConflict.Output

    $stableManifestAfter = @($stableVersionNames | ForEach-Object { [ordered]@{ version = $_; manifest = Get-DirectoryHashManifest (Join-Path $versionsRoot $_) } }) | ConvertTo-Json -Depth 5 -Compress
    Assert-True ($stableManifestAfter -ceq $stableManifestBefore) 'framework-1.4.0-and-earlier-zero-drift-during-suite'

    Write-Output ("ALL PASS ({0} assertions)" -f $script:Passed)
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        $resolvedTest -match 'ai-workspace-1\.4\.1-tests-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
