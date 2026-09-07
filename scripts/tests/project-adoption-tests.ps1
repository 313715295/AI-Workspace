[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptsRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $scriptsRoot 'ProjectAdoptionState.psm1') -Force
Import-Module (Join-Path $scriptsRoot 'ProjectAdoptionProjection.psm1') -Force
Import-Module (Join-Path $scriptsRoot 'ProjectAdoptionTransaction.psm1') -Force

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('aiw-adoption-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)

    if (-not $Condition) {
        throw ('ASSERT_FAIL|' + $Name)
    }
    $script:passed++
}

function Write-TestText {
    param([string]$Path, [string]$Text)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent
    }
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}

function Write-TestJson {
    param([string]$RelativePath, $Value)

    Write-TestText (Join-Path $script:fixtureRoot $RelativePath) (($Value | ConvertTo-Json -Depth 20 -Compress) + "`n")
}

function Reset-TestProject {
    if (Test-Path -LiteralPath $script:fixtureRoot) {
        [IO.Directory]::Delete($script:fixtureRoot, $true)
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $script:fixtureRoot '.ai-workspace')
    Write-TestJson '.ai-workspace/project.json' ([ordered]@{
        schemaVersion = 4
        id = 'fixture'
        frameworkVersion = '1.16.0'
        frameworkToolBackend = 'powershell7'
        processPolicy = [ordered]@{ schemaVersion = 1; locator = '.ai-workspace/process-policy.json' }
    })
    Write-TestJson '.ai-workspace/controller.json' ([ordered]@{
        schemaVersion = 1
        projectId = 'fixture'
        controllerId = 'fixture-controller'
        controllerEpoch = 1
        state = 'CURRENT'
    })
    Write-TestJson '.ai-workspace/corrections.json' ([ordered]@{
        schemaVersion = 2
        projectId = 'fixture'
        corrections = @()
    })
    Write-TestJson '.ai-workspace/process-policy.json' ([ordered]@{
        schemaVersion = 1
        selectedRulePackBytes = 65536
        rules = @()
    })
    Write-TestText (Join-Path $script:fixtureRoot '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nfixture`n<!-- PROJECT-CUSTOM:END -->`n"
    Write-TestText (Join-Path $script:fixtureRoot 'AGENTS.md') "fixture`n"
}

try {
    Reset-TestProject
    $format = Get-AiwProjectFormat $fixtureRoot
    Assert-True (
        $format.projectFormat -ceq 'repo-local/project-config-4' -and
        $format.capabilities -ccontains 'PROJECT_BACKEND_SELECTION' -and
        $format.capabilities -ccontains 'PROCESS_POLICY_LOCATOR' -and
        $format.capabilities -ccontains 'STRUCTURED_CORRECTIONS' -and
        $format.capabilities -ccontains 'PROCESS_POLICY' -and
        $format.capabilities -ccontains 'LEGACY_PROJECT_CUSTOM_REGION' -and
        $format.capabilities -ccontains 'ROOT_AGENTS_ENTRY'
    ) 'format-from-observed-structure'

    $policyPath = Join-Path $fixtureRoot '.ai-workspace/process-policy.json'
    Write-TestJson '.ai-workspace/process-policy.json' ([ordered]@{ schemaVersion = 1; rules = @() })
    $format = Get-AiwProjectFormat $fixtureRoot
    Assert-True ($format.capabilities -cnotcontains 'PROCESS_POLICY') 'capability-not-inferred-from-schema-alone'

    Write-TestText (Join-Path $fixtureRoot '.ai-workspace/project.json') "{`"schemaVersion`":4,`"SchemaVersion`":4}`n"
    $duplicateRejected = $false
    try {
        Read-AiwProjectJson (Join-Path $fixtureRoot '.ai-workspace/project.json') 'PROJECT_CONFIG' | Out-Null
    }
    catch {
        $duplicateRejected = $_.Exception.Message -cmatch '^PROJECT_CONFIG_DUPLICATE_MEMBER'
    }
    Assert-True $duplicateRejected 'duplicate-json-member-rejected'

    Reset-TestProject
    $tool = Get-AiwRootToolRevision (Split-Path -Parent $scriptsRoot) @(
        'scripts/ProjectAdoptionTransaction.psm1',
        'scripts/ProjectAdoptionProjection.psm1',
        'scripts/ProjectAdoptionState.psm1'
    )
    $toolReordered = Get-AiwRootToolRevision (Split-Path -Parent $scriptsRoot) @(
        'scripts/ProjectAdoptionState.psm1',
        'scripts/ProjectAdoptionTransaction.psm1',
        'scripts/ProjectAdoptionProjection.psm1'
    )
    Assert-True (
        $tool.dependencies.Count -eq 3 -and
        $tool.revision -cmatch '^[A-F0-9]{64}$' -and
        $tool.revision -ceq $toolReordered.revision
    ) 'tool-revision-ordinal-and-order-independent'

    $declaredDependencies = Get-AiwProjectAdoptionToolDependency UPGRADE
    $runtimeIdentity = Get-AiwProjectAdoptionRuntimeIdentity $fixtureRoot (Split-Path -Parent $scriptsRoot) UPGRADE
    Assert-True (
        $declaredDependencies -ccontains 'scripts/upgrade-project.ps1' -and
        $declaredDependencies -ccontains 'scripts/ProjectAdoptionTransaction.psm1' -and
        $runtimeIdentity.frameworkPin -ceq '1.16.0' -and
        $runtimeIdentity.projectFormat -ceq 'repo-local/project-config-4' -and
        $runtimeIdentity.rootToolRevision -cmatch '^[A-F0-9]{64}$'
    ) 'runtime-identity-binds-pin-format-and-root-tool'

    $projectedText = "{`"schemaVersion`":5,`"id`":`"fixture`",`"frameworkVersion`":`"1.16.0`",`"frameworkToolBackend`":`"powershell7`",`"processPolicy`":{`"schemaVersion`":1,`"locator`":`".ai-workspace/process-policy.json`"}}`n"
    $projected = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = '.ai-workspace/project.json'; text = $projectedText })
    $projectedFormat = Get-AiwProjectedProjectFormat $fixtureRoot $projected
    Assert-True ($projectedFormat.projectFormat -ceq 'repo-local/project-config-5') 'projected-format-uses-target-bytes'

    $duplicateDependencyRejected = $false
    try {
        Get-AiwRootToolRevision (Split-Path -Parent $scriptsRoot) @(
            'scripts/ProjectAdoptionState.psm1',
            'scripts/ProjectAdoptionState.psm1'
        ) | Out-Null
    }
    catch {
        $duplicateDependencyRejected = $_.Exception.Message -cmatch '^TOOL_DEPENDENCY_DUPLICATE'
    }
    Assert-True $duplicateDependencyRejected 'tool-dependency-duplicate-rejected'

    $invalidPathRejected = $false
    try {
        New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = '../escape.txt'; text = 'bad' }) | Out-Null
    }
    catch {
        $invalidPathRejected = $_.Exception.Message -ceq 'RELATIVE_PATH_INVALID'
    }
    Assert-True $invalidPathRejected 'projection-path-escape-rejected'

    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $transactionRelative = '.ai-workspace/upgrade-recovery/test/state.json'
    $transactionPath = Join-Path $fixtureRoot $transactionRelative

    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    Write-TestText $fileA 'drift'
    $preflightRejected = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true } | Out-Null
    }
    catch {
        $preflightRejected = $_.Exception.Message -cmatch '^PREFLIGHT_OBJECT_DRIFT'
    }
    Assert-True ($preflightRejected -and -not (Test-Path -LiteralPath $transactionPath)) 'preflight-failure-zero-transaction-write'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    $semanticPreflightRejected = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true } -Preflight { $false } | Out-Null
    }
    catch {
        $semanticPreflightRejected = $_.Exception.Message -ceq 'PREFLIGHT_FAILED'
    }
    Assert-True (
        $semanticPreflightRejected -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'old' -and
        -not (Test-Path -LiteralPath $transactionPath)
    ) 'semantic-preflight-failure-zero-managed-write'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = 'a.txt'; text = 'new' },
        [pscustomobject]@{ path = 'nested/new.txt'; text = 'created' }
    )
    $applyFailed = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true } -FailAfterWrite 1 | Out-Null
    }
    catch {
        $applyFailed = $_.Exception.Message -cmatch '^TRANSACTION_ROLLED_BACK'
    }
    Assert-True (
        $applyFailed -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'old' -and
        -not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'nested'))
    ) 'apply-failure-restores-bytes-and-created-directories'

    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    $postcheckFailed = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $false } { $true } | Out-Null
    }
    catch {
        $postcheckFailed = $_.Exception.Message -cmatch '^TRANSACTION_ROLLED_BACK'
    }
    Assert-True ($postcheckFailed -and (Get-Content -LiteralPath $fileA -Raw) -ceq 'old') 'postcheck-failure-restores-old-behavior'

    $result = Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true }
    Assert-True (
        $result.status -ceq 'COMPLETE' -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'new' -and
        $result.transactionIdentity -cmatch '^\d+\|[A-F0-9]{64}$'
    ) 'apply-complete'

    $deleteProjection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; exists = $false })
    $deleteResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $deleteProjection '.ai-workspace/upgrade-recovery/delete/state.json' { $true } { $true }
    Assert-True ($deleteResult.status -ceq 'COMPLETE' -and -not (Test-Path -LiteralPath $fileA)) 'managed-delete-complete'

    Reset-TestProject
    $existingEmptyPath = Join-Path $fixtureRoot 'existing-empty.txt'
    $existingNonemptyPath = Join-Path $fixtureRoot 'existing-nonempty.txt'
    $createdEmptyPath = Join-Path $fixtureRoot 'created-empty.bin'
    [IO.File]::WriteAllBytes($existingEmptyPath, [byte[]]::new(0))
    Write-TestText $existingNonemptyPath 'preserve-on-rollback'
    $emptyIdentity = '0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
    $zeroByteProjection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = 'existing-empty.txt'; text = 'filled-after-apply' },
        [pscustomobject]@{ path = 'existing-nonempty.txt'; text = '' },
        [pscustomobject]@{ path = 'created-empty.bin'; bytes = [byte[]]::new(0) }
    )
    Assert-True (
        [string]$zeroByteProjection.objects[0].oldIdentity -ceq $emptyIdentity -and
        [string]$zeroByteProjection.objects[1].newIdentity -ceq $emptyIdentity -and
        [string]$zeroByteProjection.objects[2].oldIdentity -ceq 'MISSING' -and
        [string]$zeroByteProjection.objects[2].newIdentity -ceq $emptyIdentity
    ) 'zero-byte-projection-distinguishes-empty-files-from-missing'

    $zeroByteRollback = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $zeroByteProjection '.ai-workspace/upgrade-recovery/zero-byte/state.json' { $false } { $true } | Out-Null
    }
    catch {
        $zeroByteRollback = $_.Exception.Message -ceq 'TRANSACTION_ROLLED_BACK|POSTCHECK_FAILED'
    }
    Assert-True (
        $zeroByteRollback -and
        (Test-Path -LiteralPath $existingEmptyPath -PathType Leaf) -and
        [IO.File]::ReadAllBytes($existingEmptyPath).Length -eq 0 -and
        (Get-Content -LiteralPath $existingNonemptyPath -Raw) -ceq 'preserve-on-rollback' -and
        -not (Test-Path -LiteralPath $createdEmptyPath)
    ) 'zero-byte-postcheck-failure-restores-existing-empty-and-nonempty-and-removes-created-empty'

    $zeroByteResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $zeroByteProjection '.ai-workspace/upgrade-recovery/zero-byte/state.json' {
        param($root)
        (Get-Content -LiteralPath (Join-Path $root 'existing-empty.txt') -Raw) -ceq 'filled-after-apply' -and
        [IO.File]::ReadAllBytes((Join-Path $root 'existing-nonempty.txt')).Length -eq 0 -and
        (Test-Path -LiteralPath (Join-Path $root 'created-empty.bin') -PathType Leaf) -and
        [IO.File]::ReadAllBytes((Join-Path $root 'created-empty.bin')).Length -eq 0
    } { $true }
    Assert-True (
        $zeroByteResult.status -ceq 'COMPLETE' -and
        (Get-Content -LiteralPath $existingEmptyPath -Raw) -ceq 'filled-after-apply' -and
        (Test-Path -LiteralPath $existingNonemptyPath -PathType Leaf) -and
        [IO.File]::ReadAllBytes($existingNonemptyPath).Length -eq 0 -and
        (Test-Path -LiteralPath $createdEmptyPath -PathType Leaf) -and
        [IO.File]::ReadAllBytes($createdEmptyPath).Length -eq 0
    ) 'zero-byte-apply-preserves-empty-target-files-as-existing'

    Reset-TestProject
    $directoryProjection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = '.ai-workspace/tasks/active'; kind = 'DIRECTORY' },
        [pscustomobject]@{ path = '.ai-workspace/tasks/archive'; kind = 'DIRECTORY' }
    )
    $directoryResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $directoryProjection '.ai-workspace/upgrade-recovery/directories/state.json' { $true } { $true }
    Assert-True (
        $directoryResult.status -ceq 'COMPLETE' -and
        (Test-Path -LiteralPath (Join-Path $fixtureRoot '.ai-workspace/tasks/active') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $fixtureRoot '.ai-workspace/tasks/archive') -PathType Container)
    ) 'managed-directories-created'

    Reset-TestProject
    $directoryProjection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = '.ai-workspace/generated/nested'; kind = 'DIRECTORY' })
    $directoryFailure = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $directoryProjection '.ai-workspace/upgrade-recovery/directory-failure/state.json' { $true } { $true } -FailAfterWrite 1 | Out-Null
    }
    catch {
        $directoryFailure = $_.Exception.Message -cmatch '^TRANSACTION_ROLLED_BACK'
    }
    Assert-True ($directoryFailure -and -not (Test-Path -LiteralPath (Join-Path $fixtureRoot '.ai-workspace/generated'))) 'directory-failure-restores-created-tree'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projectPath = Join-Path $fixtureRoot '.ai-workspace/project.json'
    $oldProject = [IO.File]::ReadAllBytes($projectPath)
    $newProject = [Text.UTF8Encoding]::new($false).GetBytes("{`"schemaVersion`":4,`"id`":`"fixture`",`"frameworkVersion`":`"target`"}`n")
    $projection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = 'a.txt'; text = 'new' },
        [pscustomobject]@{ path = '.ai-workspace/project.json'; bytes = $newProject }
    )
    $rollbackBlocked = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection '.ai-workspace/upgrade-recovery/drift/state.json' {
            param($root)
            Write-TestText (Join-Path $root 'a.txt') 'third-party'
            return $false
        } { $true } | Out-Null
    }
    catch {
        $rollbackBlocked = $_.Exception.Message -cmatch '^ROLLBACK_BLOCKED\|ROLLBACK_THIRD_PARTY_DRIFT'
    }
    Assert-True (
        $rollbackBlocked -and
        (Get-AiwByteIdentity ([IO.File]::ReadAllBytes($projectPath))) -ceq (Get-AiwByteIdentity $oldProject) -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'third-party'
    ) 'rollback-restores-pin-before-third-party-drift-stop'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    $resumeRelative = '.ai-workspace/upgrade-recovery/resume/state.json'
    $resumePath = Join-Path $fixtureRoot $resumeRelative
    $behaviorBlocked = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $resumeRelative { $false } { $false } | Out-Null
    }
    catch {
        $behaviorBlocked = $_.Exception.Message -ceq 'ROLLBACK_BLOCKED|ROLLBACK_BEHAVIOR_POSTCHECK_FAILED'
    }
    $resumeIdentity = Get-AiwByteIdentity ([IO.File]::ReadAllBytes($resumePath))
    $reuseBlocked = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $resumeRelative { $true } { $true } | Out-Null
    }
    catch {
        $reuseBlocked = $_.Exception.Message -cmatch '^TRANSACTION_RECOVERY_REQUIRED\|'
    }
    Assert-True $reuseBlocked 'incomplete-transaction-must-resume-before-reuse'
    $resumed = Resume-AiwProjectProjectionRollback $fixtureRoot $resumeRelative $resumeIdentity { $true }
    Assert-True (
        $behaviorBlocked -and
        $resumed.status -ceq 'ROLLED_BACK' -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'old'
    ) 'interrupted-rollback-resume'

    $runtimeProjection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'runtime-fixture.txt'; text = 'runtime' })
    $runtimeTransactionRelative = '.ai-workspace/runtime/project-adoption/register/state.json'
    $runtimeResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $runtimeProjection $runtimeTransactionRelative { $true } { $true }
    Assert-True (
        $runtimeResult.status -ceq 'COMPLETE' -and
        (Get-Content -LiteralPath (Join-Path $fixtureRoot 'runtime-fixture.txt') -Raw) -ceq 'runtime' -and
        (Test-Path -LiteralPath (Join-Path $fixtureRoot $runtimeTransactionRelative) -PathType Leaf)
    ) 'runtime-transaction-root-supported'

    $noOp = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'old' })
    $noTransactionRelative = '.ai-workspace/upgrade-recovery/noop/state.json'
    $noTransactionPath = Join-Path $fixtureRoot $noTransactionRelative
    $noOpResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $noOp $noTransactionRelative { $true } { $true }
    Assert-True (
        $noOpResult.status -ceq 'NO_CHANGE' -and
        -not (Test-Path -LiteralPath $noTransactionPath)
    ) 'no-op-no-transaction'

    $selfUpdateTest = Join-Path $PSScriptRoot 'maintenance-self-update-tests.ps1'
    $selfUpdateOutput = @(& pwsh -NoProfile -NonInteractive -File $selfUpdateTest 2>&1 | ForEach-Object { [string]$_ })
    $selfUpdateCode = $LASTEXITCODE
    if ($selfUpdateCode -ne 0) { throw ('MAINTENANCE_SELF_UPDATE_FAILED|' + ($selfUpdateOutput -join [Environment]::NewLine)) }
    Assert-True ($selfUpdateCode -eq 0 -and $selfUpdateOutput.Count -eq 1 -and $selfUpdateOutput[0] -cmatch '^PASS\|maintenance-self-update\|\d+/\d+$') 'maintenance-self-update-focused-entrypoint'

    Write-Output ('PASS|project-adoption-tests|' + $passed + '/' + $passed)
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
        $resolvedTemp = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
        if (-not $resolvedFixture.StartsWith($resolvedTemp + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolvedFixture)).StartsWith('aiw-adoption-', [StringComparison]::Ordinal)) {
            throw 'TEST_FIXTURE_CLEANUP_SCOPE_INVALID'
        }
        [IO.Directory]::Delete($resolvedFixture, $true)
    }
}
