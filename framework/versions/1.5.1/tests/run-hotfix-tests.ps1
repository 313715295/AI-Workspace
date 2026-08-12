[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$versionRoot = Split-Path -Parent $PSScriptRoot
$frameworkRoot = Split-Path -Parent (Split-Path -Parent $versionRoot)
$repoRoot = Split-Path -Parent $frameworkRoot
$baselineRoot = Join-Path $frameworkRoot 'versions\1.5.0'
$failures = New-Object 'System.Collections.Generic.List[string]'
$checkCount = 0

function Assert-Hotfix([bool]$Condition, [string]$Name) {
    $script:checkCount++
    if (-not $Condition) { $script:failures.Add($Name) }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function Get-RelativeInventory([string]$Root, [string[]]$Excluded) {
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    return @(
        Get-ChildItem -LiteralPath $resolved -Recurse -File |
            ForEach-Object { $_.FullName.Substring($resolved.Length + 1).Replace('\','/') } |
            Where-Object { $_ -notin $Excluded } |
            Sort-Object
    )
}

function Initialize-TestGit([string]$Repository) {
    & git -C $Repository init --quiet
    & git -C $Repository config user.email framework-hotfix@example.invalid
    & git -C $Repository config user.name Framework-Hotfix
}

function Commit-TestRepository([string]$Repository, [string]$Message) {
    & git -C $Repository add -- .ai-workspace
    & git -C $Repository commit --quiet -m $Message
}

$metadata = Get-Content -LiteralPath (Join-Path $versionRoot 'VERSION.json') -Raw -Encoding utf8 | ConvertFrom-Json
Assert-Hotfix ([string]$metadata.version -ceq '1.5.1' -and [string]$metadata.lifecycle -ceq 'STABLE' -and [string]$metadata.releaseClass -ceq 'PATCH_HOTFIX' -and
    [string]$metadata.baseline -ceq '1.5.0' -and [bool]$metadata.consumable -and [bool]$metadata.projectPinEligible) 'metadata-patch-stable'
Assert-Hotfix (Test-Path -LiteralPath $baselineRoot -PathType Container) 'baseline-stable-present'
Assert-Hotfix (Test-Path -LiteralPath (Join-Path $versionRoot 'RELEASE_MANIFEST.json') -PathType Leaf) 'stable-release-manifest-present'

$rootReadme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw -Encoding utf8
$initialization = Get-Content -LiteralPath (Join-Path $repoRoot 'INITIALIZATION.md') -Raw -Encoding utf8
Assert-Hotfix ($rootReadme.Contains('[INITIALIZATION.md](INITIALIZATION.md)') -and $rootReadme.Contains('.ai-workspace/BOOTSTRAP.md') -and $initialization.Contains('.ai-workspace/BOOTSTRAP.md')) 'root-initialization-on-demand-route'
Assert-Hotfix (-not $rootReadme.Contains('scripts/register-project.ps1') -and $initialization.Contains('scripts/register-project.ps1')) 'root-readme-keeps-initialization-out-of-default-entry'

$baselineInventory = Get-RelativeInventory $baselineRoot @('RELEASE_MANIFEST.json')
$draftInventory = Get-RelativeInventory $versionRoot @('tests/run-hotfix-tests.ps1','RELEASE_MANIFEST.json')
Assert-Hotfix (($baselineInventory -join "`n") -ceq ($draftInventory -join "`n")) 'inventory-topology-unchanged'

$baselineLoad = Get-Content -LiteralPath (Join-Path $baselineRoot 'LOAD_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
$draftLoad = Get-Content -LiteralPath (Join-Path $versionRoot 'LOAD_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
$baselineTopology = [ordered]@{ core=$baselineLoad.core; roles=$baselineLoad.roles; profiles=$baselineLoad.profiles; phases=$baselineLoad.phases; hosts=$baselineLoad.hosts; order=$baselineLoad.order } | ConvertTo-Json -Depth 10 -Compress
$draftTopology = [ordered]@{ core=$draftLoad.core; roles=$draftLoad.roles; profiles=$draftLoad.profiles; phases=$draftLoad.phases; hosts=$draftLoad.hosts; order=$draftLoad.order } | ConvertTo-Json -Depth 10 -Compress
Assert-Hotfix ($baselineTopology -ceq $draftTopology) 'load-topology-unchanged'

$recoveryCore = Get-Content -LiteralPath (Join-Path $versionRoot 'RECOVERY_CORE.md') -Raw -Encoding utf8
$taskScope = Get-Content -LiteralPath (Join-Path $versionRoot 'TASK_AND_SCOPE.md') -Raw -Encoding utf8
$hostCodex = Get-Content -LiteralPath (Join-Path $versionRoot 'HOST_CODEX.md') -Raw -Encoding utf8
Assert-Hotfix ($recoveryCore.Contains('DIRECT_USER_FEEDBACK_REQUIRES_OWNER_REBIND') -and
    $taskScope.Contains('DIRECT_USER_FEEDBACK_REQUIRES_OWNER_REBIND')) 'direct-user-feedback-requires-owner-rebind'
Assert-Hotfix ($hostCodex.Contains('PEER_THREAD_ROUTE_IS_APP_LEVEL') -and $hostCodex.Contains('send_message_to_thread / read_thread')) 'codex-peer-thread-route-is-app-level'

$strictText = $true
foreach ($file in @(Get-ChildItem -LiteralPath $versionRoot -Recurse -File)) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $strictText = $false; continue }
    try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes) } catch { $strictText = $false; continue }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n") -or [regex]::IsMatch($text, '(?m)[ \t]+$')) { $strictText = $false }
}
Assert-Hotfix $strictText 'strict-utf8-lf'

$loader = Join-Path $versionRoot 'scripts\resolve-load-plan.ps1'
$corePlan = & $loader -Role EXECUTOR -Profile MICRO -Phase DISCOVER -HostName GENERIC -AsJson | ConvertFrom-Json
$ownerPlan = & $loader -Role DOMAIN_OWNER -Profile STANDARD -Phase PLAN,IMPLEMENT,VERIFY -HostName CODEX -AsJson | ConvertFrom-Json
$controllerPlan = & $loader -Role CONTROLLER -Profile CRITICAL -Phase RECOVER,PLAN -HostName CODEX -AsJson | ConvertFrom-Json
Assert-Hotfix ($corePlan.frameworkVersion -ceq '1.5.1' -and $corePlan.lifecycle -ceq 'STABLE' -and @($corePlan.modules).Count -eq 1 -and $corePlan.modules[0].path -ceq 'RECOVERY_CORE.md') 'core-only-load-plan'
Assert-Hotfix (@($ownerPlan.modules | Select-Object -ExpandProperty path) -join '|' -ceq 'RECOVERY_CORE.md|TASK_AND_SCOPE.md|REVIEW_AND_EVIDENCE.md|AUTHORIZATION_MODEL.md|HOST_CODEX.md') 'owner-load-plan'
Assert-Hotfix (@($controllerPlan.modules | Select-Object -ExpandProperty path) -join '|' -ceq 'RECOVERY_CORE.md|TASK_AND_SCOPE.md|REVIEW_AND_EVIDENCE.md|PROJECT_CONTROL.md|AUTHORIZATION_MODEL.md|HOST_CODEX.md') 'controller-load-plan'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('framework-hotfix-1.5.1-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $taskChecker = Join-Path $versionRoot 'scripts\check-task-card.ps1'
    $legacyPath = Join-Path $tempRoot 'LEGACY-15.md'
    Write-Utf8NoBom $legacyPath "# LEGACY-15 - compatible`n`n- Task schema: 1.5`n- Owner: controller-1`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=candidate-1; expected_paths=[]; actual_paths=[]`n"
    $legacyResult = & $taskChecker -TaskPath $legacyPath
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $legacyResult -like 'PASS|*') 'schema-1.5-compatible'

    $standardPath = Join-Path $tempRoot 'STANDARD-151.md'
    Write-Utf8NoBom $standardPath "# STANDARD-151 - no phase tax`n`n- Task schema: 1.5.1`n- Owner: owner-1`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $standardResult = & $taskChecker -TaskPath $standardPath
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $standardResult -like 'PASS|*') 'standard-no-phase-matrix'

    $phaseFalsePath = Join-Path $tempRoot 'CRITICAL-FALSE.md'
    Write-Utf8NoBom $phaseFalsePath "# CRITICAL-FALSE - no phase transition`n`n- Task schema: 1.5.1`n- Owner: controller-1`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=candidate-1; expected_paths=[]; actual_paths=[]`n- Phase gate: FALSE`n"
    $phaseFalseResult = & $taskChecker -TaskPath $phaseFalsePath
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $phaseFalseResult -like 'PASS|*') 'critical-false-no-matrix'

    $phasePendingPath = Join-Path $tempRoot 'PHASE-PENDING.md'
    $phasePending = @"
# PHASE-PENDING - active phase

- Task schema: 1.5.1
- Owner: controller-1
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=candidate-1; expected_paths=[]; actual_paths=[]
- Phase gate: TRUE

## Phase acceptance

- Technical evidence: PENDING
- Domain contract check: PENDING
- Runtime/platform check: PENDING
- Project phase signoff: PENDING
- User final gate: PENDING
- Acceptance order: TECHNICAL_EVIDENCE > DOMAIN_CONTRACT > RUNTIME_PLATFORM > PROJECT_SIGNOFF > USER_FINAL_GATE
"@
    Write-Utf8NoBom $phasePendingPath $phasePending
    $phasePendingResult = & $taskChecker -TaskPath $phasePendingPath
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $phasePendingResult -like 'PASS|*') 'phase-pending-valid'

    $priorPlaytestPendingPath = Join-Path $tempRoot 'PHASE-PRIOR-PLAYTEST-PENDING.md'
    $priorPlaytestPending = $phasePending.Replace('# PHASE-PENDING - active phase','# PHASE-PRIOR-PLAYTEST-PENDING - reusable user evidence').Replace('- Phase gate: TRUE',"- Phase gate: TRUE`n- User playtest evidence: PASSED; candidate=candidate-1; evidence=user-1")
    Write-Utf8NoBom $priorPlaytestPendingPath $priorPlaytestPending
    $priorPlaytestPendingResult = & $taskChecker -TaskPath $priorPlaytestPendingPath
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $priorPlaytestPendingResult -like 'PASS|*') 'prior-user-evidence-may-precede-phase-signoff'

    $phaseReadyPath = Join-Path $tempRoot 'PHASE-READY.md'
    $phaseReady = $phasePending.Replace('# PHASE-PENDING - active phase','# PHASE-READY - complete phase').Replace('- Technical evidence: PENDING','- Technical evidence: READY; producer=executor-1; evidence=manifest-1').Replace('- Domain contract check: PENDING','- Domain contract check: ACCEPTED; owner=design-owner-1; evidence=contract-1').Replace('- Runtime/platform check: PENDING','- Runtime/platform check: NOT_APPLICABLE; reason=no-runtime-boundary').Replace('- Project phase signoff: PENDING','- Project phase signoff: READY; controller=controller-1; evidence=signoff-1').Replace('- User final gate: PENDING','- User final gate: CONFIRMED; candidate=candidate-1; evidence=user-1')
    Write-Utf8NoBom $phaseReadyPath $phaseReady
    $phaseReadyResult = & $taskChecker -TaskPath $phaseReadyPath
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $phaseReadyResult -like 'PASS|*') 'phase-ready-valid'

    $priorPlaytestBoundPath = Join-Path $tempRoot 'PHASE-PRIOR-PLAYTEST-BOUND.md'
    $priorPlaytestBound = $priorPlaytestPending.Replace('# PHASE-PRIOR-PLAYTEST-PENDING - reusable user evidence','# PHASE-PRIOR-PLAYTEST-BOUND - reused user evidence').Replace('- Technical evidence: PENDING','- Technical evidence: READY; producer=executor-1; evidence=manifest-1').Replace('- Domain contract check: PENDING','- Domain contract check: ACCEPTED; owner=design-owner-1; evidence=contract-1').Replace('- Runtime/platform check: PENDING','- Runtime/platform check: NOT_APPLICABLE; reason=no-runtime-boundary').Replace('- Project phase signoff: PENDING','- Project phase signoff: READY; controller=controller-1; evidence=signoff-1').Replace('- User final gate: PENDING','- User final gate: CONFIRMED; candidate=candidate-1; evidence=user-1')
    Write-Utf8NoBom $priorPlaytestBoundPath $priorPlaytestBound
    $priorPlaytestBoundResult = & $taskChecker -TaskPath $priorPlaytestBoundPath
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $priorPlaytestBoundResult -like 'PASS|*') 'prior-user-evidence-reused-after-phase-signoff'

    $missingUserCandidatePath = Join-Path $tempRoot 'PHASE-USER-CANDIDATE-MISSING.md'
    Write-Utf8NoBom $missingUserCandidatePath $phaseReady.Replace('# PHASE-READY - complete phase','# PHASE-USER-CANDIDATE-MISSING - invalid').Replace('CONFIRMED; candidate=candidate-1; evidence=user-1','CONFIRMED; evidence=user-1')
    $missingUserCandidateResult = & $taskChecker -TaskPath $missingUserCandidatePath 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $missingUserCandidateResult -like '*PHASE_USER_FINAL_GATE*') 'user-gate-candidate-required'

    $mismatchedUserCandidatePath = Join-Path $tempRoot 'PHASE-USER-CANDIDATE-MISMATCH.md'
    Write-Utf8NoBom $mismatchedUserCandidatePath $phaseReady.Replace('# PHASE-READY - complete phase','# PHASE-USER-CANDIDATE-MISMATCH - invalid').Replace('candidate=candidate-1','candidate=candidate-old')
    $mismatchedUserCandidateResult = & $taskChecker -TaskPath $mismatchedUserCandidatePath 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $mismatchedUserCandidateResult -like '*USER_GATE_CANDIDATE_MISMATCH*') 'user-gate-candidate-must-match-current-exact'

    $wrongSignerPath = Join-Path $tempRoot 'PHASE-WRONG-SIGNER.md'
    Write-Utf8NoBom $wrongSignerPath $phaseReady.Replace('# PHASE-READY - complete phase','# PHASE-WRONG-SIGNER - invalid').Replace('controller=controller-1','controller=other-controller')
    $wrongSignerResult = & $taskChecker -TaskPath $wrongSignerPath 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $wrongSignerResult -like '*PROJECT_SIGNOFF_OWNER*') 'phase-owner-rejected'

    $earlySignoffPath = Join-Path $tempRoot 'PHASE-EARLY-SIGNOFF.md'
    Write-Utf8NoBom $earlySignoffPath $phasePending.Replace('# PHASE-PENDING - active phase','# PHASE-EARLY-SIGNOFF - invalid').Replace('- Project phase signoff: PENDING','- Project phase signoff: READY; controller=controller-1; evidence=signoff-1')
    $earlySignoffResult = & $taskChecker -TaskPath $earlySignoffPath 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $earlySignoffResult -like '*PHASE_SIGNOFF_PREREQUISITES*') 'phase-prerequisites-rejected'

    $badNaPath = Join-Path $tempRoot 'PHASE-BAD-NA.md'
    Write-Utf8NoBom $badNaPath $phasePending.Replace('# PHASE-PENDING - active phase','# PHASE-BAD-NA - invalid').Replace('- Runtime/platform check: PENDING','- Runtime/platform check: NOT_APPLICABLE; reason=<reason>')
    $badNaResult = & $taskChecker -TaskPath $badNaPath 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $badNaResult -like '*PHASE_RUNTIME_PLATFORM*') 'phase-na-reason-required'

    $earlyDomainPath = Join-Path $tempRoot 'PHASE-EARLY-DOMAIN.md'
    Write-Utf8NoBom $earlyDomainPath $phasePending.Replace('# PHASE-PENDING - active phase','# PHASE-EARLY-DOMAIN - invalid').Replace('- Domain contract check: PENDING','- Domain contract check: ACCEPTED; owner=design-owner-1; evidence=contract-1')
    $earlyDomainResult = & $taskChecker -TaskPath $earlyDomainPath 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $earlyDomainResult -like '*PHASE_DOMAIN_BEFORE_TECHNICAL*') 'domain-waits-for-technical-evidence'

    $earlyRuntimePath = Join-Path $tempRoot 'PHASE-EARLY-RUNTIME.md'
    Write-Utf8NoBom $earlyRuntimePath $phasePending.Replace('# PHASE-PENDING - active phase','# PHASE-EARLY-RUNTIME - invalid').Replace('- Technical evidence: PENDING','- Technical evidence: READY; producer=executor-1; evidence=manifest-1').Replace('- Runtime/platform check: PENDING','- Runtime/platform check: NOT_APPLICABLE; reason=no-runtime-boundary')
    $earlyRuntimeResult = & $taskChecker -TaskPath $earlyRuntimePath 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $earlyRuntimeResult -like '*PHASE_RUNTIME_BEFORE_DOMAIN*') 'runtime-waits-for-domain-check'

    $sha = ('A' * 64)
    $package = [ordered]@{
        schemaVersion=1; frameworkVersion='1.5.1'; taskId='FW-HOTFIX-AUTH'; profile='STANDARD'; lifecycle='ACTIVE';
        owner='owner-1'; issuer='owner-1'; issuerRole='DOMAIN_OWNER'; grantee='executor-1'; bundle='IMPLEMENT_LOCAL';
        decisionClass='ROUTINE_LOCAL'; userConfirmation='NOT_REQUIRED'; reviewIndependence='NOT_APPLICABLE'; delegatedGitCloser=$false;
        actions=@('SOURCE_WRITE'); exactPaths=@('src/a.js'); objectIdentities=@([ordered]@{path='src/a.js'; identity="10|$sha"});
        invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE')
    }
    $authPath = Join-Path $tempRoot 'auth.json'
    Write-Utf8NoBom $authPath ($package | ConvertTo-Json -Depth 8)
    $authChecker = Join-Path $versionRoot 'scripts\check-authorization.ps1'
    $authPass = & $authChecker -PackagePath $authPath -ObservedActor executor-1 -ObservedTaskId FW-HOTFIX-AUTH -ObservedOwner owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$sha"
    Assert-Hotfix ($LASTEXITCODE -eq 0 -and $authPass -like 'PASS|*') 'authorization-1.5.1-valid'
    $package.invalidatesOn = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT')
    Write-Utf8NoBom $authPath ($package | ConvertTo-Json -Depth 8)
    $authFeedbackStale = & $authChecker -PackagePath $authPath -ObservedActor executor-1 -ObservedTaskId FW-HOTFIX-AUTH -ObservedOwner owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$sha" 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $authFeedbackStale -like '*INVALIDATOR_MISSING_USER_DECISION_CHANGE*') 'authorization-user-decision-change-invalidates-old-package'
    $package.invalidatesOn = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE')
    $package.frameworkVersion = '1.5.0'
    Write-Utf8NoBom $authPath ($package | ConvertTo-Json -Depth 8)
    $authOld = & $authChecker -PackagePath $authPath -ObservedActor executor-1 -ObservedTaskId FW-HOTFIX-AUTH -ObservedOwner owner-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity "src/a.js=10|$sha" 2>$null
    Assert-Hotfix ($LASTEXITCODE -eq 2 -and $authOld -like '*FRAMEWORK_VERSION*') 'authorization-old-version-invalidated'

    $isolatedWorkspace = Join-Path $tempRoot 'workspace'
    New-Item -ItemType Directory -Path (Join-Path $isolatedWorkspace 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $isolatedWorkspace 'framework\versions') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\register-project.ps1') -Destination (Join-Path $isolatedWorkspace 'scripts\register-project.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\upgrade-project.ps1') -Destination (Join-Path $isolatedWorkspace 'scripts\upgrade-project.ps1')
    Copy-Item -LiteralPath $baselineRoot -Destination (Join-Path $isolatedWorkspace 'framework\versions\1.5.0') -Recurse
    Copy-Item -LiteralPath $versionRoot -Destination (Join-Path $isolatedWorkspace 'framework\versions\1.5.1') -Recurse
    Write-Utf8NoBom (Join-Path $isolatedWorkspace 'framework\CURRENT') '1.4.1'
    $projectRepo = Join-Path $tempRoot 'project'
    New-Item -ItemType Directory -Path $projectRepo | Out-Null
    Initialize-TestGit $projectRepo
    $register = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $isolatedWorkspace 'scripts\register-project.ps1') -ProjectId hotfix-smoke -DisplayName 'Hotfix Smoke' -RepositoryPath $projectRepo -FrameworkVersion 1.5.0 -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    if ($LASTEXITCODE -eq 0) { Commit-TestRepository $projectRepo 'register baseline' }
    $headBefore = if ($LASTEXITCODE -eq 0) { (& git -C $projectRepo rev-parse HEAD).Trim() } else { '' }
    $upgrade = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $isolatedWorkspace 'scripts\upgrade-project.ps1') -ProjectId hotfix-smoke -RepositoryPath $projectRepo -ToVersion 1.5.1 -WorkspaceRoot $isolatedWorkspace -Apply 2>&1
    $upgradeCode = $LASTEXITCODE
    $config = if (Test-Path -LiteralPath (Join-Path $projectRepo '.ai-workspace\project.json')) { Get-Content -LiteralPath (Join-Path $projectRepo '.ai-workspace\project.json') -Raw -Encoding utf8 | ConvertFrom-Json } else { $null }
    $headAfter = if ($headBefore) { (& git -C $projectRepo rev-parse HEAD).Trim() } else { '' }
    $cached = @(& git -C $projectRepo diff --cached --name-only)
    Assert-Hotfix ($upgradeCode -eq 0 -and $null -ne $config -and [string]$config.frameworkVersion -ceq '1.5.1' -and $headAfter -ceq $headBefore -and $cached.Count -eq 0) 'upgrade-1.5.0-to-1.5.1-smoke'
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

if ($failures.Count -gt 0) {
    Write-Output ('HOTFIX_TESTS_FAILED|checks=' + $checkCount + '|failures=' + ($failures -join ','))
    exit 1
}

Write-Output ('HOTFIX_TESTS_PASS|checks=' + $checkCount)
exit 0
