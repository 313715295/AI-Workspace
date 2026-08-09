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
$rootChecker = Join-Path $workspaceRoot 'scripts\check-task-card.ps1'
$powershellExe = Join-Path $PSHOME 'powershell.exe'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-workspace-1.3.2-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
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

    $legacyVersionRoot = Join-Path $versionsRoot '1.3.0'
    $legacyStarterSource = Join-Path $legacyVersionRoot 'project-starter'
    $legacyStarterTarget = Join-Path $Target 'framework\versions\1.3.0\project-starter'
    New-Item -ItemType Directory -Path (Split-Path -Parent $legacyStarterTarget) -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target 'framework\versions\1.3.2\scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target 'projects') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target 'scripts') -Force | Out-Null
    if (Test-Path -LiteralPath $legacyVersionRoot -PathType Container) {
        if (-not (Test-Path -LiteralPath $legacyStarterSource -PathType Container)) {
            throw "Framework 1.3.0 directory is incomplete; test starter is missing: $legacyStarterSource"
        }
        Copy-Item -LiteralPath $legacyStarterSource -Destination $legacyStarterTarget -Recurse
    }
    else {
        throw "Required stable Framework 1.3.0 directory is missing; tags are not runtime fallbacks: $legacyVersionRoot"
    }
    Copy-Item -LiteralPath (Join-Path $versionRoot 'project-starter') -Destination (Join-Path $Target 'framework\versions\1.3.2\project-starter') -Recurse
    Copy-Item -LiteralPath $checker -Destination (Join-Path $Target 'framework\versions\1.3.2\scripts\check-task-card.ps1')
    Copy-Item -LiteralPath $register -Destination (Join-Path $Target 'scripts\register-project.ps1')
    Copy-Item -LiteralPath $upgrade -Destination (Join-Path $Target 'scripts\upgrade-project.ps1')
    Copy-Item -LiteralPath $rootChecker -Destination (Join-Path $Target 'scripts\check-task-card.ps1')
    Write-Utf8NoBom (Join-Path $Target 'framework\CURRENT') $CurrentVersion
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
if (-not (Test-Path -LiteralPath $rootChecker -PathType Leaf)) {
    throw "Root 1.3.0 compatibility checker not found: $rootChecker"
}

try {
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

    $starterProject = [System.IO.File]::ReadAllText((Join-Path $versionRoot 'project-starter\project.json'), (New-Object System.Text.UTF8Encoding($false, $true)))
    $starterBootstrap = [System.IO.File]::ReadAllText((Join-Path $versionRoot 'project-starter\BOOTSTRAP.md'), (New-Object System.Text.UTF8Encoding($false, $true)))
    Assert-True ($starterProject -match '\{\{FRAMEWORK_VERSION_JSON\}\}' -and $starterBootstrap -match 'framework/versions/\{\{FRAMEWORK_VERSION\}\}/scripts/check-task-card\.ps1') 'starter-pin-and-bootstrap-locator'

    $governanceText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'GOVERNANCE.md')
    $workflowText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'WORKFLOW_PLAYBOOK.md')
    $promptsText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'PROMPTS.md')
    $reviewText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'REVIEW_CHECKLIST.md')
    $templateText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'TASK_TEMPLATE.md')
    $adapterText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'HOST_ADAPTER_CODEX.md')
    $readmeText = Read-StrictUtf8NoBom (Join-Path $workspaceRoot 'README.md')
    $changelogText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'CHANGELOG.md')
    $upgradeSource = Read-StrictUtf8NoBom $upgrade
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

    $releaseDocuments = @($readmeText, $changelogText, $governanceText, $workflowText)
    $releaseContractPresent = @($releaseDocuments | Where-Object { -not $_.Contains('framework/versions/') -or -not $_.Contains('CURRENT') }).Count -eq 0 -and
        @($releaseDocuments | Where-Object { $_.Contains('AI-Workspace-Releases') }).Count -eq 0 -and
        $readmeText.Contains('tag') -and $readmeText.Contains((Expand-UnicodeText '\u53ef\u9009\u5ba1\u8ba1')) -and
        $changelogText.Contains('DRAFT') -and $changelogText.Contains('REVIEW') -and $changelogText.Contains('STABLE') -and $changelogText.Contains('RETIRED') -and
        @($releaseDocuments | Where-Object { -not $_.Contains((Expand-UnicodeText '\u8fdb\u5165STABLE\u5373\u4e0d\u53ef\u539f\u4f4d\u4fee\u6539')) }).Count -eq 0
    Assert-True $releaseContractPresent 'single-repository-multi-version-release-contract'

    $upgradeHasNoTagFallback = $upgradeSource -notmatch '(?i)Read-PinnedBootstrapFromLocalTag|refs/tags|cat-file|rev-parse|fetch|pull|clone|remote|ls-remote' -and
        $upgradeSource.Contains('tags and current HEAD are not runtime fallbacks')
    Assert-True $upgradeHasNoTagFallback 'upgrade-requires-version-directory-no-tag-fallback'

    $whatIfProjectId = "framework-test-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $whatIf = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $register, '-ProjectId', $whatIfProjectId, '-DisplayName', 'Framework Test', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.2', '-WorkspaceRoot', $workspaceRoot, '-WhatIf')
    Assert-True ($whatIf.ExitCode -eq 0 -and $whatIf.Output -match 'WHAT_IF' -and -not (Test-Path -LiteralPath (Join-Path $workspaceRoot "projects\$whatIfProjectId"))) 'register-explicit-1.3.2-whatif' $whatIf.Output

    $explicitWorkspace = Join-Path $testRoot 'workspace-explicit'
    Copy-StarterWorkspace $explicitWorkspace '1.3.0'
    $explicitCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $explicitWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'explicit-project', '-DisplayName', 'Explicit Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.2', '-WorkspaceRoot', $explicitWorkspace)
    $explicitRoot = Join-Path $explicitWorkspace 'projects\explicit-project'
    $explicitConfig = [System.IO.File]::ReadAllText((Join-Path $explicitRoot 'project.json'), (New-Object System.Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
    $explicitBootstrap = [System.IO.File]::ReadAllText((Join-Path $explicitRoot 'BOOTSTRAP.md'), (New-Object System.Text.UTF8Encoding($false, $true)))
    Assert-True ($explicitCreated.ExitCode -eq 0 -and $explicitConfig.frameworkVersion -eq '1.3.2' -and $explicitBootstrap -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1') 'register-explicit-1.3.2-actual-create' $explicitCreated.Output

    $upgradeWorkspace = Join-Path $testRoot 'workspace-upgrade'
    Copy-StarterWorkspace $upgradeWorkspace '1.3.0'
    $upgradeRegister = Join-Path $upgradeWorkspace 'scripts\register-project.ps1'
    $upgradeScript = Join-Path $upgradeWorkspace 'scripts\upgrade-project.ps1'
    $upgradeCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-project', '-DisplayName', 'Upgrade Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeRoot = Join-Path $upgradeWorkspace 'projects\upgrade-project'
    $upgraded = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-project', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $upgradedConfigText = Read-StrictUtf8NoBom (Join-Path $upgradeRoot 'project.json')
    $upgradedConfig = $upgradedConfigText | ConvertFrom-Json
    $upgradedBootstrap = Read-StrictUtf8NoBom (Join-Path $upgradeRoot 'BOOTSTRAP.md')
    $legacyRootLocator = '`scripts/check-task-card.ps1`'
    $upgradeResidue = Get-UpgradeResidue $upgradeRoot
    Assert-True ($upgradeCreated.ExitCode -eq 0 -and $upgraded.ExitCode -eq 0 -and $upgradedConfig.frameworkVersion -eq '1.3.2' -and $upgradedBootstrap -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1' -and -not $upgradedBootstrap.Contains($legacyRootLocator) -and $upgradeResidue.Count -eq 0) 'upgrade-1.3.0-to-1.3.2-recoverable-transaction-utf8-no-bom' ($upgradeCreated.Output + "`n" + $upgraded.Output)

    $missingVersionWorkspace = Join-Path $testRoot 'workspace-missing-version'
    Copy-StarterWorkspace $missingVersionWorkspace '1.3.0'
    $missingVersionRegister = Join-Path $missingVersionWorkspace 'scripts\register-project.ps1'
    $missingVersionUpgrade = Join-Path $missingVersionWorkspace 'scripts\upgrade-project.ps1'
    $missingVersionCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $missingVersionRegister, '-ProjectId', 'missing-version', '-DisplayName', 'Missing Version', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $missingVersionWorkspace)
    $missingVersionRoot = Join-Path $missingVersionWorkspace 'projects\missing-version'
    $missingVersionProject = Join-Path $missingVersionRoot 'project.json'
    $missingVersionBootstrap = Join-Path $missingVersionRoot 'BOOTSTRAP.md'
    $missingVersionProjectBefore = (Get-FileHash -LiteralPath $missingVersionProject -Algorithm SHA256).Hash
    $missingVersionBootstrapBefore = (Get-FileHash -LiteralPath $missingVersionBootstrap -Algorithm SHA256).Hash
    Remove-Item -LiteralPath (Join-Path $missingVersionWorkspace 'framework\versions\1.3.0') -Recurse -Force
    $missingVersionResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $missingVersionUpgrade, '-ProjectId', 'missing-version', '-ToVersion', '1.3.2', '-WorkspaceRoot', $missingVersionWorkspace, '-Apply')
    $missingVersionProjectAfter = (Get-FileHash -LiteralPath $missingVersionProject -Algorithm SHA256).Hash
    $missingVersionBootstrapAfter = (Get-FileHash -LiteralPath $missingVersionBootstrap -Algorithm SHA256).Hash
    $missingVersionResidue = Get-UpgradeResidue $missingVersionRoot
    Assert-True ($missingVersionCreated.ExitCode -eq 0 -and $missingVersionResult.ExitCode -ne 0 -and $missingVersionResult.Output -match 'tags and current HEAD are not runtime fallbacks' -and $missingVersionProjectBefore -eq $missingVersionProjectAfter -and $missingVersionBootstrapBefore -eq $missingVersionBootstrapAfter -and $missingVersionResidue.Count -eq 0) 'upgrade-missing-version-directory-fails-without-tag-fallback' ($missingVersionCreated.Output + "`n" + $missingVersionResult.Output)

    $upgradeFailureCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-failure', '-DisplayName', 'Upgrade Failure', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeFailureRoot = Join-Path $upgradeWorkspace 'projects\upgrade-failure'
    $upgradeFailureProject = Join-Path $upgradeFailureRoot 'project.json'
    $upgradeFailureBootstrap = Join-Path $upgradeFailureRoot 'BOOTSTRAP.md'
    Write-Utf8NoBom $upgradeFailureBootstrap ((Read-StrictUtf8NoBom $upgradeFailureBootstrap) + "`nProject-specific Bootstrap edit.`n")
    $failureProjectBefore = (Get-FileHash -LiteralPath $upgradeFailureProject -Algorithm SHA256).Hash
    $failureBootstrapBefore = (Get-FileHash -LiteralPath $upgradeFailureBootstrap -Algorithm SHA256).Hash
    $upgradeFailure = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-failure', '-ToVersion', '1.3.2', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $failureConfig = Read-StrictUtf8NoBom $upgradeFailureProject | ConvertFrom-Json
    $failureProjectAfter = (Get-FileHash -LiteralPath $upgradeFailureProject -Algorithm SHA256).Hash
    $failureBootstrapAfter = (Get-FileHash -LiteralPath $upgradeFailureBootstrap -Algorithm SHA256).Hash
    $failureResidue = Get-UpgradeResidue $upgradeFailureRoot
    Assert-True ($upgradeFailureCreated.ExitCode -eq 0 -and $upgradeFailure.ExitCode -ne 0 -and $upgradeFailure.Output -match 'refusing an incomplete migration' -and $failureConfig.frameworkVersion -eq '1.3.0' -and $failureProjectBefore -eq $failureProjectAfter -and $failureBootstrapBefore -eq $failureBootstrapAfter -and $failureResidue.Count -eq 0) 'upgrade-failure-no-partial-write-or-residue' ($upgradeFailureCreated.Output + "`n" + $upgradeFailure.Output)

    $upgradeRollbackCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-rollback', '-DisplayName', 'Upgrade Rollback', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeRollbackRoot = Join-Path $upgradeWorkspace 'projects\upgrade-rollback'
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
    Assert-True ($upgradeRollbackCreated.ExitCode -eq 0 -and $upgradeRollback.ExitCode -ne 0 -and $rollbackConfig.frameworkVersion -eq '1.3.0' -and $rollbackProjectBefore -eq $rollbackProjectAfter -and $rollbackBootstrapBefore -eq $rollbackBootstrapAfter -and $rollbackResidue.Count -eq 0) 'upgrade-commit-failure-rolls-back-without-residue' ($upgradeRollbackCreated.Output + "`n" + $upgradeRollback.Output)

    $upgradeInterruptCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-interrupt', '-DisplayName', 'Upgrade Interrupt', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeInterruptRoot = Join-Path $upgradeWorkspace 'projects\upgrade-interrupt'
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
    Assert-True ($upgradeInterruptCreated.ExitCode -eq 0 -and $upgradeInterrupted.ExitCode -ne 0 -and $interruptedConfig.frameworkVersion -eq '1.3.2' -and $interruptedBootstrap.Contains($legacyRootLocator) -and $interruptedStates.Count -ge 1 -and $interruptedMaterialsPresent -and $interruptRecovered.ExitCode -eq 0 -and $interruptRecovered.Output -match 'Recovered previous Framework upgrade transaction: COMMITTED' -and $interruptRecoveredConfig.frameworkVersion -eq '1.3.2' -and $interruptRecoveredBootstrap -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1' -and -not $interruptRecoveredBootstrap.Contains($legacyRootLocator) -and $interruptRecoveredResidue.Count -eq 0) 'upgrade-first-replace-interruption-recovers-on-next-invocation' ($upgradeInterruptCreated.Output + "`n" + $upgradeInterrupted.Output + "`n" + $interruptRecovered.Output)

    $upgradeRetainedCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-retained', '-DisplayName', 'Upgrade Retained', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeRetainedRoot = Join-Path $upgradeWorkspace 'projects\upgrade-retained'
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
    Assert-True ($upgradeRetainedCreated.ExitCode -eq 0 -and $upgradeRetainedInterrupted.ExitCode -ne 0 -and $upgradeRecoveryFailed.ExitCode -ne 0 -and $upgradeRecoveryFailed.Output -match 'Recovery materials were preserved' -and $retainedStates.Count -ge 1 -and $retainedMaterialsPresent -and $retainedRecovery.ExitCode -eq 0 -and $retainedRecovery.Output -match 'Recovered previous Framework upgrade transaction: COMMITTED' -and $retainedConfig.frameworkVersion -eq '1.3.2' -and $retainedBootstrap -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1' -and $retainedResidue.Count -eq 0) 'upgrade-rollback-failure-retains-materials-and-later-recovers' ($upgradeRetainedCreated.Output + "`n" + $upgradeRetainedInterrupted.Output + "`n" + $upgradeRecoveryFailed.Output + "`n" + $retainedRecovery.Output)

    $temporaryWorkspace = Join-Path $testRoot 'workspace-default'
    Copy-StarterWorkspace $temporaryWorkspace '1.3.2'
    $defaultWhatIf = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $temporaryWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'default-project', '-DisplayName', 'Default Project', '-RepositoryPath', $repositoryPath, '-WorkspaceRoot', $temporaryWorkspace, '-WhatIf')
    Assert-True ($defaultWhatIf.ExitCode -eq 0 -and $defaultWhatIf.Output -match 'WHAT_IF' -and $defaultWhatIf.Output -match '1\.3\.2') 'register-default-current-whatif' $defaultWhatIf.Output

    $created = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $temporaryWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'created-project', '-DisplayName', 'Created Project', '-RepositoryPath', $repositoryPath, '-WorkspaceRoot', $temporaryWorkspace)
    $createdRoot = Join-Path $temporaryWorkspace 'projects\created-project'
    $createdConfig = [System.IO.File]::ReadAllText((Join-Path $createdRoot 'project.json'), (New-Object System.Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
    $createdBootstrap = [System.IO.File]::ReadAllText((Join-Path $createdRoot 'BOOTSTRAP.md'), (New-Object System.Text.UTF8Encoding($false, $true)))
    Assert-True ($created.ExitCode -eq 0 -and $createdConfig.frameworkVersion -eq '1.3.2' -and $createdBootstrap -match 'framework/versions/1\.3\.2/scripts/check-task-card\.ps1') 'register-default-current-actual-create' $created.Output

    $duplicate = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $temporaryWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'created-project', '-DisplayName', 'Created Project', '-RepositoryPath', $repositoryPath, '-WorkspaceRoot', $temporaryWorkspace)
    Assert-True ($duplicate.ExitCode -ne 0 -and $duplicate.Output -match 'refusing to overwrite') 'register-duplicate-refusal' $duplicate.Output

    $brokenWorkspace = Join-Path $testRoot 'workspace-broken'
    Copy-StarterWorkspace $brokenWorkspace '1.3.2'
    $brokenProjectTemplate = Join-Path $brokenWorkspace 'framework\versions\1.3.2\project-starter\PROJECT.md'
    $brokenContent = [System.IO.File]::ReadAllText($brokenProjectTemplate, (New-Object System.Text.UTF8Encoding($false, $true))) + "`n{{UNRESOLVED_TOKEN}}`n"
    Write-Utf8NoBom $brokenProjectTemplate $brokenContent
    $broken = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $brokenWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'broken-project', '-DisplayName', 'Broken Project', '-RepositoryPath', $repositoryPath, '-WorkspaceRoot', $brokenWorkspace)
    $brokenTarget = Join-Path $brokenWorkspace 'projects\broken-project'
    $stagingResidue = @(Get-ChildItem -LiteralPath (Join-Path $brokenWorkspace 'projects') -Force | Where-Object { $_.Name -like '.broken-project.init.*' })
    Assert-True ($broken.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $brokenTarget) -and $stagingResidue.Count -eq 0) 'register-failure-no-target-residue' $broken.Output

    Write-Output ("ALL PASS ({0} assertions)" -f $script:Passed)
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        $resolvedTest -match 'ai-workspace-1\.3\.2-tests-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
