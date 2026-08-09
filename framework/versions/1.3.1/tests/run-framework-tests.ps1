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
$gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$gitExe = if ($null -eq $gitCommand) { '' } else { [string]$gitCommand.Source }
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-workspace-1.3.1-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
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

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $gitExe -C $Root @Arguments 2>&1 | ForEach-Object { $_.ToString() })
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

function Invoke-TestGitReadBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $allArguments = @('-C', $Root) + $Arguments
    $quotedArguments = foreach ($argument in $allArguments) {
        if ($argument.Contains('"')) {
            throw 'Git read argument contains an unsupported quote.'
        }
        '"' + $argument + '"'
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gitExe
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $standardOutput = New-Object System.IO.MemoryStream
    try {
        if (-not $process.Start()) {
            throw 'Could not start local Git for Framework test fixture lookup.'
        }
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($standardOutput)
        $process.WaitForExit()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Bytes = $standardOutput.ToArray()
            Error = $standardError.Trim()
        }
    }
    finally {
        $standardOutput.Dispose()
        $process.Dispose()
    }
}

function Copy-LegacyStarterFromLocalTag {
    param([Parameter(Mandatory = $true)][string]$Destination)

    $repositoryResult = Invoke-TestGitReadBytes $workspaceRoot @('rev-parse', '--show-toplevel')
    if ($repositoryResult.ExitCode -ne 0) {
        throw 'Framework 1.3.0 is absent and the test workspace is not a Git checkout.'
    }
    $reportedRoot = (ConvertFrom-StrictUtf8NoBomBytes $repositoryResult.Bytes 'local Git repository root').Trim()
    $resolvedRoot = [System.IO.Path]::GetFullPath($reportedRoot).TrimEnd([char[]]@('\', '/'))
    $resolvedWorkspace = [System.IO.Path]::GetFullPath($workspaceRoot).TrimEnd([char[]]@('\', '/'))
    if (-not $resolvedRoot.Equals($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Framework test workspace is not the root of its local Git repository.'
    }

    $tagReference = 'refs/tags/v1.3.0'
    $commitResult = Invoke-TestGitReadBytes $workspaceRoot @('rev-parse', '--verify', '--quiet', "${tagReference}^{commit}")
    if ($commitResult.ExitCode -ne 0) {
        throw 'Framework 1.3.0 is absent and local tag v1.3.0 does not resolve to a commit.'
    }

    $starterFiles = @(
        'BOOTSTRAP.md',
        'project.json',
        'PROJECT.md',
        'RELATIONSHIPS.md',
        'REVIEW_PROFILE.md',
        'STATUS.md',
        'tasks/README.md'
    )
    foreach ($relativePath in $starterFiles) {
        $tagPath = "framework/versions/1.3.0/project-starter/$relativePath"
        $objectSpec = "${tagReference}:$tagPath"
        $typeResult = Invoke-TestGitReadBytes $workspaceRoot @('cat-file', '-t', $objectSpec)
        if ($typeResult.ExitCode -ne 0) {
            throw "Local tag v1.3.0 is missing required Framework test starter file: $tagPath"
        }
        $objectType = (ConvertFrom-StrictUtf8NoBomBytes $typeResult.Bytes "v1.3.0 object type for $tagPath").Trim()
        if ($objectType -cne 'blob') {
            throw "Local tag v1.3.0 test starter path is not a blob: $tagPath"
        }

        $blobResult = Invoke-TestGitReadBytes $workspaceRoot @('cat-file', 'blob', $objectSpec)
        if ($blobResult.ExitCode -ne 0) {
            throw "Could not read Framework test starter file from local tag v1.3.0: $tagPath"
        }
        $content = ConvertFrom-StrictUtf8NoBomBytes $blobResult.Bytes "v1.3.0:$tagPath"
        $targetPath = Join-Path $Destination ($relativePath.Replace('/', '\'))
        $targetParent = Split-Path -Parent $targetPath
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        [System.IO.File]::WriteAllText($targetPath, $content, $utf8NoBom)
    }
}

function Initialize-TestGitRepository {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [bool]$CreateLegacyTag = $true
    )

    $commands = @()
    $commands += ,@('init', '--quiet')
    $commands += ,@('config', 'user.email', 'framework-tests@example.invalid')
    $commands += ,@('config', 'user.name', 'Framework Tests')
    $commands += ,@('config', 'core.autocrlf', 'false')
    $commands += ,@('add', '--all')
    $commands += ,@('commit', '--quiet', '--no-gpg-sign', '-m', 'framework test snapshot')
    foreach ($arguments in $commands) {
        $result = Invoke-TestGit -Root $Root -Arguments $arguments
        if ($result.ExitCode -ne 0) {
            throw "Could not initialize test Git repository. $($result.Output)"
        }
    }
    if ($CreateLegacyTag) {
        $tagged = Invoke-TestGit -Root $Root -Arguments @('tag', '-a', 'v1.3.0', '-m', 'Framework 1.3.0 test snapshot')
        if ($tagged.ExitCode -ne 0) {
            throw "Could not create local Framework test tag. $($tagged.Output)"
        }
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
        return Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, '-ProjectId', $ProjectId, '-ToVersion', '1.3.1', '-WorkspaceRoot', $WorkspaceRoot, '-Apply')
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
    New-Item -ItemType Directory -Path (Join-Path $Target 'framework\versions\1.3.1\scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target 'projects') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target 'scripts') -Force | Out-Null
    if (Test-Path -LiteralPath $legacyVersionRoot -PathType Container) {
        if (-not (Test-Path -LiteralPath $legacyStarterSource -PathType Container)) {
            throw "Framework 1.3.0 directory is incomplete; test starter is missing: $legacyStarterSource"
        }
        Copy-Item -LiteralPath $legacyStarterSource -Destination $legacyStarterTarget -Recurse
    }
    else {
        Copy-LegacyStarterFromLocalTag $legacyStarterTarget
    }
    Copy-Item -LiteralPath (Join-Path $versionRoot 'project-starter') -Destination (Join-Path $Target 'framework\versions\1.3.1\project-starter') -Recurse
    Copy-Item -LiteralPath $checker -Destination (Join-Path $Target 'framework\versions\1.3.1\scripts\check-task-card.ps1')
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
if ([string]::IsNullOrWhiteSpace($gitExe) -or -not (Test-Path -LiteralPath $gitExe -PathType Leaf)) {
    throw 'Local Git executable not found; latest-only Framework upgrade tests require Git.'
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
    Assert-True ($result.ExitCode -eq 0 -and $result.Output -match '^PASS\|TEST-CRITICAL\.md\|OK$') 'profile-critical-positive' $result.Output

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

    $forbiddenLine = (Expand-UnicodeText '- Forbidden\u8def\u5f84\uFF1A[src/schema.js]') + "`n"
    $missing = (Get-StandardCard).Replace($forbiddenLine, '')
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
    $readmeText = Read-StrictUtf8NoBom (Join-Path $workspaceRoot 'README.md')
    $changelogText = Read-StrictUtf8NoBom (Join-Path $versionRoot 'CHANGELOG.md')
    $upgradeSource = Read-StrictUtf8NoBom $upgrade
    $waitDocuments = @($governanceText, $workflowText, $promptsText, $reviewText)
    $waitCombined = $waitDocuments -join "`n"
    $executionDeviation = Expand-UnicodeText '\u6267\u884c\u504f\u5dee'
    $explicitUserWait = Expand-UnicodeText '\u7528\u6237\u660e\u786e\u8981\u6c42\u540c\u6b65\u7b49\u5f85'
    $currentTurnConsumes = Expand-UnicodeText '\u5f53\u524dturn\u5fc5\u987b\u6d88\u8d39\u7ed3\u679c'
    $lostCallback = Expand-UnicodeText '\u4e3b\u52a8\u56de\u4f20'
    $noImmediateRetry = Expand-UnicodeText '\u4e0d\u5f97\u7acb\u5373\u91cd\u8bd5'
    $waitContractPresent = @($waitDocuments | Where-Object { -not $_.Contains('wait_threads') -or -not $_.Contains($executionDeviation) }).Count -eq 0 -and
        $waitCombined.Contains($explicitUserWait) -and $waitCombined.Contains($currentTurnConsumes) -and
        $waitCombined.Contains($lostCallback) -and $waitCombined.Contains($noImmediateRetry) -and
        $waitCombined.Contains('ACK') -and $waitCombined.Contains('idle') -and
        $workflowText -notmatch (Expand-UnicodeText '\u53ea\u6709\u7528\u6237\u8981\u6c42\u3001\u8d85\u65f6\u6216\u7591\u4f3c\u5931\u8054')
    Assert-True $waitContractPresent 'async-wait-default-three-exceptions-and-no-retry'

    $releaseDocuments = @($readmeText, $changelogText, $governanceText, $workflowText)
    $releaseContractPresent = @($releaseDocuments | Where-Object { -not $_.Contains('latest-only') -or -not $_.Contains('annotated tag') }).Count -eq 0 -and
        $readmeText.Contains('AI-Workspace-Releases') -and $changelogText.Contains('AI-Workspace-Releases') -and
        $workflowText.Contains('v<') -and $workflowText.Contains('fail closed')
    Assert-True $releaseContractPresent 'release-default-latest-only-history-by-tag'

    $readOnlyGitFallback = $upgradeSource.Contains('Read-PinnedBootstrapFromLocalTag') -and
        $upgradeSource.Contains("@('cat-file', 'blob', `$objectSpec)") -and
        $upgradeSource -notmatch "(?i)'(?:fetch|pull|clone|remote|ls-remote)'"
    Assert-True $readOnlyGitFallback 'upgrade-local-tag-read-only-no-network-command'

    $whatIfProjectId = "framework-test-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $whatIf = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $register, '-ProjectId', $whatIfProjectId, '-DisplayName', 'Framework Test', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.1', '-WorkspaceRoot', $workspaceRoot, '-WhatIf')
    Assert-True ($whatIf.ExitCode -eq 0 -and $whatIf.Output -match 'WHAT_IF' -and -not (Test-Path -LiteralPath (Join-Path $workspaceRoot "projects\$whatIfProjectId"))) 'register-explicit-1.3.1-whatif' $whatIf.Output

    $explicitWorkspace = Join-Path $testRoot 'workspace-explicit'
    Copy-StarterWorkspace $explicitWorkspace '1.3.0'
    $explicitCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $explicitWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'explicit-project', '-DisplayName', 'Explicit Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.1', '-WorkspaceRoot', $explicitWorkspace)
    $explicitRoot = Join-Path $explicitWorkspace 'projects\explicit-project'
    $explicitConfig = [System.IO.File]::ReadAllText((Join-Path $explicitRoot 'project.json'), (New-Object System.Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
    $explicitBootstrap = [System.IO.File]::ReadAllText((Join-Path $explicitRoot 'BOOTSTRAP.md'), (New-Object System.Text.UTF8Encoding($false, $true)))
    Assert-True ($explicitCreated.ExitCode -eq 0 -and $explicitConfig.frameworkVersion -eq '1.3.1' -and $explicitBootstrap -match 'framework/versions/1\.3\.1/scripts/check-task-card\.ps1') 'register-explicit-1.3.1-actual-create' $explicitCreated.Output

    $upgradeWorkspace = Join-Path $testRoot 'workspace-upgrade'
    Copy-StarterWorkspace $upgradeWorkspace '1.3.0'
    $upgradeRegister = Join-Path $upgradeWorkspace 'scripts\register-project.ps1'
    $upgradeScript = Join-Path $upgradeWorkspace 'scripts\upgrade-project.ps1'
    $upgradeCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-project', '-DisplayName', 'Upgrade Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeRoot = Join-Path $upgradeWorkspace 'projects\upgrade-project'
    $upgraded = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-project', '-ToVersion', '1.3.1', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $upgradedConfigText = Read-StrictUtf8NoBom (Join-Path $upgradeRoot 'project.json')
    $upgradedConfig = $upgradedConfigText | ConvertFrom-Json
    $upgradedBootstrap = Read-StrictUtf8NoBom (Join-Path $upgradeRoot 'BOOTSTRAP.md')
    $legacyRootLocator = '`scripts/check-task-card.ps1`'
    $upgradeResidue = Get-UpgradeResidue $upgradeRoot
    Assert-True ($upgradeCreated.ExitCode -eq 0 -and $upgraded.ExitCode -eq 0 -and $upgradedConfig.frameworkVersion -eq '1.3.1' -and $upgradedBootstrap -match 'framework/versions/1\.3\.1/scripts/check-task-card\.ps1' -and -not $upgradedBootstrap.Contains($legacyRootLocator) -and $upgradeResidue.Count -eq 0) 'upgrade-1.3.0-to-1.3.1-recoverable-transaction-utf8-no-bom' ($upgradeCreated.Output + "`n" + $upgraded.Output)

    $upgradeFailureCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-failure', '-DisplayName', 'Upgrade Failure', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeFailureRoot = Join-Path $upgradeWorkspace 'projects\upgrade-failure'
    $upgradeFailureProject = Join-Path $upgradeFailureRoot 'project.json'
    $upgradeFailureBootstrap = Join-Path $upgradeFailureRoot 'BOOTSTRAP.md'
    Write-Utf8NoBom $upgradeFailureBootstrap ((Read-StrictUtf8NoBom $upgradeFailureBootstrap) + "`nProject-specific Bootstrap edit.`n")
    $failureProjectBefore = (Get-FileHash -LiteralPath $upgradeFailureProject -Algorithm SHA256).Hash
    $failureBootstrapBefore = (Get-FileHash -LiteralPath $upgradeFailureBootstrap -Algorithm SHA256).Hash
    $upgradeFailure = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-failure', '-ToVersion', '1.3.1', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
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
        $upgradeRollback = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-rollback', '-ToVersion', '1.3.1', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
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
    $interruptRecovered = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-interrupt', '-ToVersion', '1.3.1', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $interruptRecoveredConfig = Read-StrictUtf8NoBom (Join-Path $upgradeInterruptRoot 'project.json') | ConvertFrom-Json
    $interruptRecoveredBootstrap = Read-StrictUtf8NoBom (Join-Path $upgradeInterruptRoot 'BOOTSTRAP.md')
    $interruptRecoveredResidue = Get-UpgradeResidue $upgradeInterruptRoot
    Assert-True ($upgradeInterruptCreated.ExitCode -eq 0 -and $upgradeInterrupted.ExitCode -ne 0 -and $interruptedConfig.frameworkVersion -eq '1.3.1' -and $interruptedBootstrap.Contains($legacyRootLocator) -and $interruptedStates.Count -ge 1 -and $interruptedMaterialsPresent -and $interruptRecovered.ExitCode -eq 0 -and $interruptRecovered.Output -match 'Recovered previous Framework upgrade transaction: COMMITTED' -and $interruptRecoveredConfig.frameworkVersion -eq '1.3.1' -and $interruptRecoveredBootstrap -match 'framework/versions/1\.3\.1/scripts/check-task-card\.ps1' -and -not $interruptRecoveredBootstrap.Contains($legacyRootLocator) -and $interruptRecoveredResidue.Count -eq 0) 'upgrade-first-replace-interruption-recovers-on-next-invocation' ($upgradeInterruptCreated.Output + "`n" + $upgradeInterrupted.Output + "`n" + $interruptRecovered.Output)

    $upgradeRetainedCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeRegister, '-ProjectId', 'upgrade-retained', '-DisplayName', 'Upgrade Retained', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $upgradeWorkspace)
    $upgradeRetainedRoot = Join-Path $upgradeWorkspace 'projects\upgrade-retained'
    $upgradeRetainedInterrupted = Invoke-InterruptedUpgrade $upgradeScript 'upgrade-retained' $upgradeWorkspace
    $upgradeRetainedProject = Join-Path $upgradeRetainedRoot 'project.json'
    $upgradeRetainedBootstrap = Join-Path $upgradeRetainedRoot 'BOOTSTRAP.md'
    $upgradeRetainedTransaction = Join-Path $upgradeRetainedRoot '.framework-upgrade-transaction'
    (Get-Item -LiteralPath $upgradeRetainedProject).IsReadOnly = $true
    (Get-Item -LiteralPath $upgradeRetainedBootstrap).IsReadOnly = $true
    try {
        $upgradeRecoveryFailed = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-retained', '-ToVersion', '1.3.1', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
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
    $retainedRecovery = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $upgradeScript, '-ProjectId', 'upgrade-retained', '-ToVersion', '1.3.1', '-WorkspaceRoot', $upgradeWorkspace, '-Apply')
    $retainedConfig = Read-StrictUtf8NoBom $upgradeRetainedProject | ConvertFrom-Json
    $retainedBootstrap = Read-StrictUtf8NoBom $upgradeRetainedBootstrap
    $retainedResidue = Get-UpgradeResidue $upgradeRetainedRoot
    Assert-True ($upgradeRetainedCreated.ExitCode -eq 0 -and $upgradeRetainedInterrupted.ExitCode -ne 0 -and $upgradeRecoveryFailed.ExitCode -ne 0 -and $upgradeRecoveryFailed.Output -match 'Recovery materials were preserved' -and $retainedStates.Count -ge 1 -and $retainedMaterialsPresent -and $retainedRecovery.ExitCode -eq 0 -and $retainedRecovery.Output -match 'Recovered previous Framework upgrade transaction: COMMITTED' -and $retainedConfig.frameworkVersion -eq '1.3.1' -and $retainedBootstrap -match 'framework/versions/1\.3\.1/scripts/check-task-card\.ps1' -and $retainedResidue.Count -eq 0) 'upgrade-rollback-failure-retains-materials-and-later-recovers' ($upgradeRetainedCreated.Output + "`n" + $upgradeRetainedInterrupted.Output + "`n" + $upgradeRecoveryFailed.Output + "`n" + $retainedRecovery.Output)

    $latestWorkspace = Join-Path $testRoot 'workspace-latest-only'
    Copy-StarterWorkspace $latestWorkspace '1.3.1'
    $latestRegister = Join-Path $latestWorkspace 'scripts\register-project.ps1'
    $latestUpgrade = Join-Path $latestWorkspace 'scripts\upgrade-project.ps1'
    $latestCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $latestRegister, '-ProjectId', 'latest-project', '-DisplayName', 'Latest Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $latestWorkspace)
    $latestProjectRoot = Join-Path $latestWorkspace 'projects\latest-project'
    Initialize-TestGitRepository $latestWorkspace
    Remove-Item -LiteralPath (Join-Path $latestWorkspace 'framework\versions\1.3.0') -Recurse -Force
    $latestVersionDirectories = @(Get-ChildItem -LiteralPath (Join-Path $latestWorkspace 'framework\versions') -Directory)
    $latestUpgraded = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $latestUpgrade, '-ProjectId', 'latest-project', '-ToVersion', '1.3.1', '-WorkspaceRoot', $latestWorkspace, '-Apply')
    $latestConfigText = Read-StrictUtf8NoBom (Join-Path $latestProjectRoot 'project.json')
    $latestConfig = $latestConfigText | ConvertFrom-Json
    $latestBootstrap = Read-StrictUtf8NoBom (Join-Path $latestProjectRoot 'BOOTSTRAP.md')
    $latestResidue = Get-UpgradeResidue $latestProjectRoot
    Assert-True ($latestCreated.ExitCode -eq 0 -and $latestVersionDirectories.Count -eq 1 -and $latestVersionDirectories[0].Name -eq '1.3.1' -and $latestUpgraded.ExitCode -eq 0 -and $latestUpgraded.Output -match 'Pinned Framework source: local Git tag v1\.3\.0' -and $latestConfig.frameworkVersion -eq '1.3.1' -and $latestBootstrap -match 'framework/versions/1\.3\.1/scripts/check-task-card\.ps1' -and -not $latestBootstrap.Contains($legacyRootLocator) -and $latestResidue.Count -eq 0) 'upgrade-latest-only-local-tag-success-utf8-no-bom' ($latestCreated.Output + "`n" + $latestUpgraded.Output)

    $lightweightWorkspace = Join-Path $testRoot 'workspace-latest-lightweight-tag'
    Copy-StarterWorkspace $lightweightWorkspace '1.3.1'
    $lightweightRegister = Join-Path $lightweightWorkspace 'scripts\register-project.ps1'
    $lightweightUpgrade = Join-Path $lightweightWorkspace 'scripts\upgrade-project.ps1'
    $lightweightCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $lightweightRegister, '-ProjectId', 'lightweight-project', '-DisplayName', 'Lightweight Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $lightweightWorkspace)
    $lightweightProjectRoot = Join-Path $lightweightWorkspace 'projects\lightweight-project'
    Initialize-TestGitRepository $lightweightWorkspace $false
    $lightweightTagged = Invoke-TestGit -Root $lightweightWorkspace -Arguments @('tag', 'v1.3.0')
    Remove-Item -LiteralPath (Join-Path $lightweightWorkspace 'framework\versions\1.3.0') -Recurse -Force
    $lightweightResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $lightweightUpgrade, '-ProjectId', 'lightweight-project', '-ToVersion', '1.3.1', '-WorkspaceRoot', $lightweightWorkspace, '-Apply')
    $lightweightConfig = Read-StrictUtf8NoBom (Join-Path $lightweightProjectRoot 'project.json') | ConvertFrom-Json
    $lightweightBootstrap = Read-StrictUtf8NoBom (Join-Path $lightweightProjectRoot 'BOOTSTRAP.md')
    $lightweightResidue = Get-UpgradeResidue $lightweightProjectRoot
    Assert-True ($lightweightCreated.ExitCode -eq 0 -and $lightweightTagged.ExitCode -eq 0 -and $lightweightResult.ExitCode -eq 0 -and $lightweightConfig.frameworkVersion -eq '1.3.1' -and $lightweightBootstrap -match 'framework/versions/1\.3\.1/scripts/check-task-card\.ps1' -and $lightweightResidue.Count -eq 0) 'upgrade-latest-only-lightweight-tag-compatible' ($lightweightCreated.Output + "`n" + $lightweightTagged.Output + "`n" + $lightweightResult.Output)

    $noTagWorkspace = Join-Path $testRoot 'workspace-latest-no-tag'
    Copy-StarterWorkspace $noTagWorkspace '1.3.1'
    $noTagRegister = Join-Path $noTagWorkspace 'scripts\register-project.ps1'
    $noTagUpgrade = Join-Path $noTagWorkspace 'scripts\upgrade-project.ps1'
    $noTagCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $noTagRegister, '-ProjectId', 'no-tag-project', '-DisplayName', 'No Tag Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $noTagWorkspace)
    $noTagProjectRoot = Join-Path $noTagWorkspace 'projects\no-tag-project'
    Initialize-TestGitRepository $noTagWorkspace $false
    Remove-Item -LiteralPath (Join-Path $noTagWorkspace 'framework\versions\1.3.0') -Recurse -Force
    $noTagProjectBefore = (Get-FileHash -LiteralPath (Join-Path $noTagProjectRoot 'project.json') -Algorithm SHA256).Hash
    $noTagBootstrapBefore = (Get-FileHash -LiteralPath (Join-Path $noTagProjectRoot 'BOOTSTRAP.md') -Algorithm SHA256).Hash
    $noTagResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $noTagUpgrade, '-ProjectId', 'no-tag-project', '-ToVersion', '1.3.1', '-WorkspaceRoot', $noTagWorkspace, '-Apply')
    $noTagResidue = Get-UpgradeResidue $noTagProjectRoot
    Assert-True ($noTagCreated.ExitCode -eq 0 -and $noTagResult.ExitCode -ne 0 -and $noTagResult.Output -match 'Local Framework tag v1\.3\.0 does not exist' -and $noTagProjectBefore -eq (Get-FileHash -LiteralPath (Join-Path $noTagProjectRoot 'project.json') -Algorithm SHA256).Hash -and $noTagBootstrapBefore -eq (Get-FileHash -LiteralPath (Join-Path $noTagProjectRoot 'BOOTSTRAP.md') -Algorithm SHA256).Hash -and $noTagResidue.Count -eq 0) 'upgrade-latest-only-missing-tag-fails-closed' ($noTagCreated.Output + "`n" + $noTagResult.Output)

    $wrongTagWorkspace = Join-Path $testRoot 'workspace-latest-wrong-tag'
    Copy-StarterWorkspace $wrongTagWorkspace '1.3.1'
    $wrongTagRegister = Join-Path $wrongTagWorkspace 'scripts\register-project.ps1'
    $wrongTagUpgrade = Join-Path $wrongTagWorkspace 'scripts\upgrade-project.ps1'
    $wrongTagCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrongTagRegister, '-ProjectId', 'wrong-tag-project', '-DisplayName', 'Wrong Tag Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $wrongTagWorkspace)
    $wrongTagProjectRoot = Join-Path $wrongTagWorkspace 'projects\wrong-tag-project'
    Remove-Item -LiteralPath (Join-Path $wrongTagWorkspace 'framework\versions\1.3.0') -Recurse -Force
    Initialize-TestGitRepository $wrongTagWorkspace
    $wrongTagProjectBefore = (Get-FileHash -LiteralPath (Join-Path $wrongTagProjectRoot 'project.json') -Algorithm SHA256).Hash
    $wrongTagBootstrapBefore = (Get-FileHash -LiteralPath (Join-Path $wrongTagProjectRoot 'BOOTSTRAP.md') -Algorithm SHA256).Hash
    $wrongTagResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrongTagUpgrade, '-ProjectId', 'wrong-tag-project', '-ToVersion', '1.3.1', '-WorkspaceRoot', $wrongTagWorkspace, '-Apply')
    $wrongTagResidue = Get-UpgradeResidue $wrongTagProjectRoot
    Assert-True ($wrongTagCreated.ExitCode -eq 0 -and $wrongTagResult.ExitCode -ne 0 -and $wrongTagResult.Output -match 'does not contain the pinned Bootstrap starter' -and $wrongTagProjectBefore -eq (Get-FileHash -LiteralPath (Join-Path $wrongTagProjectRoot 'project.json') -Algorithm SHA256).Hash -and $wrongTagBootstrapBefore -eq (Get-FileHash -LiteralPath (Join-Path $wrongTagProjectRoot 'BOOTSTRAP.md') -Algorithm SHA256).Hash -and $wrongTagResidue.Count -eq 0) 'upgrade-latest-only-incomplete-tag-fails-closed' ($wrongTagCreated.Output + "`n" + $wrongTagResult.Output)

    $nonGitWorkspace = Join-Path $testRoot 'workspace-latest-non-git'
    Copy-StarterWorkspace $nonGitWorkspace '1.3.1'
    $nonGitRegister = Join-Path $nonGitWorkspace 'scripts\register-project.ps1'
    $nonGitUpgrade = Join-Path $nonGitWorkspace 'scripts\upgrade-project.ps1'
    $nonGitCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $nonGitRegister, '-ProjectId', 'non-git-project', '-DisplayName', 'Non Git Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $nonGitWorkspace)
    $nonGitProjectRoot = Join-Path $nonGitWorkspace 'projects\non-git-project'
    Remove-Item -LiteralPath (Join-Path $nonGitWorkspace 'framework\versions\1.3.0') -Recurse -Force
    $nonGitProjectBefore = (Get-FileHash -LiteralPath (Join-Path $nonGitProjectRoot 'project.json') -Algorithm SHA256).Hash
    $nonGitBootstrapBefore = (Get-FileHash -LiteralPath (Join-Path $nonGitProjectRoot 'BOOTSTRAP.md') -Algorithm SHA256).Hash
    $nonGitResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $nonGitUpgrade, '-ProjectId', 'non-git-project', '-ToVersion', '1.3.1', '-WorkspaceRoot', $nonGitWorkspace, '-Apply')
    $nonGitResidue = Get-UpgradeResidue $nonGitProjectRoot
    Assert-True ($nonGitCreated.ExitCode -eq 0 -and $nonGitResult.ExitCode -ne 0 -and $nonGitResult.Output -match 'workspace is not a Git checkout' -and $nonGitProjectBefore -eq (Get-FileHash -LiteralPath (Join-Path $nonGitProjectRoot 'project.json') -Algorithm SHA256).Hash -and $nonGitBootstrapBefore -eq (Get-FileHash -LiteralPath (Join-Path $nonGitProjectRoot 'BOOTSTRAP.md') -Algorithm SHA256).Hash -and $nonGitResidue.Count -eq 0) 'upgrade-latest-only-non-git-fails-closed' ($nonGitCreated.Output + "`n" + $nonGitResult.Output)

    $tagMismatchWorkspace = Join-Path $testRoot 'workspace-latest-bootstrap-mismatch'
    Copy-StarterWorkspace $tagMismatchWorkspace '1.3.1'
    $tagMismatchRegister = Join-Path $tagMismatchWorkspace 'scripts\register-project.ps1'
    $tagMismatchUpgrade = Join-Path $tagMismatchWorkspace 'scripts\upgrade-project.ps1'
    $tagMismatchCreated = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tagMismatchRegister, '-ProjectId', 'tag-mismatch-project', '-DisplayName', 'Tag Mismatch Project', '-RepositoryPath', $repositoryPath, '-FrameworkVersion', '1.3.0', '-WorkspaceRoot', $tagMismatchWorkspace)
    $tagMismatchProjectRoot = Join-Path $tagMismatchWorkspace 'projects\tag-mismatch-project'
    Initialize-TestGitRepository $tagMismatchWorkspace
    Remove-Item -LiteralPath (Join-Path $tagMismatchWorkspace 'framework\versions\1.3.0') -Recurse -Force
    $tagMismatchBootstrap = Join-Path $tagMismatchProjectRoot 'BOOTSTRAP.md'
    Write-Utf8NoBom $tagMismatchBootstrap ((Read-StrictUtf8NoBom $tagMismatchBootstrap) + "`nProject-specific Bootstrap edit.`n")
    $tagMismatchProjectBefore = (Get-FileHash -LiteralPath (Join-Path $tagMismatchProjectRoot 'project.json') -Algorithm SHA256).Hash
    $tagMismatchBootstrapBefore = (Get-FileHash -LiteralPath $tagMismatchBootstrap -Algorithm SHA256).Hash
    $tagMismatchResult = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tagMismatchUpgrade, '-ProjectId', 'tag-mismatch-project', '-ToVersion', '1.3.1', '-WorkspaceRoot', $tagMismatchWorkspace, '-Apply')
    $tagMismatchResidue = Get-UpgradeResidue $tagMismatchProjectRoot
    Assert-True ($tagMismatchCreated.ExitCode -eq 0 -and $tagMismatchResult.ExitCode -ne 0 -and $tagMismatchResult.Output -match 'does not match its pinned Framework starter' -and $tagMismatchProjectBefore -eq (Get-FileHash -LiteralPath (Join-Path $tagMismatchProjectRoot 'project.json') -Algorithm SHA256).Hash -and $tagMismatchBootstrapBefore -eq (Get-FileHash -LiteralPath $tagMismatchBootstrap -Algorithm SHA256).Hash -and $tagMismatchResidue.Count -eq 0) 'upgrade-latest-only-bootstrap-mismatch-fails-closed' ($tagMismatchCreated.Output + "`n" + $tagMismatchResult.Output)

    $temporaryWorkspace = Join-Path $testRoot 'workspace-default'
    Copy-StarterWorkspace $temporaryWorkspace '1.3.1'
    $defaultWhatIf = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $temporaryWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'default-project', '-DisplayName', 'Default Project', '-RepositoryPath', $repositoryPath, '-WorkspaceRoot', $temporaryWorkspace, '-WhatIf')
    Assert-True ($defaultWhatIf.ExitCode -eq 0 -and $defaultWhatIf.Output -match 'WHAT_IF' -and $defaultWhatIf.Output -match '1\.3\.1') 'register-default-current-whatif' $defaultWhatIf.Output

    $created = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $temporaryWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'created-project', '-DisplayName', 'Created Project', '-RepositoryPath', $repositoryPath, '-WorkspaceRoot', $temporaryWorkspace)
    $createdRoot = Join-Path $temporaryWorkspace 'projects\created-project'
    $createdConfig = [System.IO.File]::ReadAllText((Join-Path $createdRoot 'project.json'), (New-Object System.Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
    $createdBootstrap = [System.IO.File]::ReadAllText((Join-Path $createdRoot 'BOOTSTRAP.md'), (New-Object System.Text.UTF8Encoding($false, $true)))
    Assert-True ($created.ExitCode -eq 0 -and $createdConfig.frameworkVersion -eq '1.3.1' -and $createdBootstrap -match 'framework/versions/1\.3\.1/scripts/check-task-card\.ps1') 'register-default-current-actual-create' $created.Output

    $duplicate = Invoke-IsolatedPowerShell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $temporaryWorkspace 'scripts\register-project.ps1'), '-ProjectId', 'created-project', '-DisplayName', 'Created Project', '-RepositoryPath', $repositoryPath, '-WorkspaceRoot', $temporaryWorkspace)
    Assert-True ($duplicate.ExitCode -ne 0 -and $duplicate.Output -match 'refusing to overwrite') 'register-duplicate-refusal' $duplicate.Output

    $brokenWorkspace = Join-Path $testRoot 'workspace-broken'
    Copy-StarterWorkspace $brokenWorkspace '1.3.1'
    $brokenProjectTemplate = Join-Path $brokenWorkspace 'framework\versions\1.3.1\project-starter\PROJECT.md'
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
        $resolvedTest -match 'ai-workspace-1\.3\.1-tests-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
