[CmdletBinding()]
param(
    [string]$SeedControlRoot,
    [string]$SeedFrameworkRoot,
    [string]$SeedTransactionPath,
    [string]$ExpectedSeedTransactionIdentity,
    [switch]$ActorStorageOnly,
    [switch]$EntryTemplatesOnly,
    [string]$LegacyRuntimeRoot
)

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
    if($ActorStorageOnly){
        if(-not$LegacyRuntimeRoot){throw 'ACTOR_STORAGE_LEGACY_RUNTIME_REQUIRED'}
        $sourceRoot=Split-Path -Parent $scriptsRoot
        New-Item -ItemType Directory -Path $fixtureRoot -Force|Out-Null
        & git -C $fixtureRoot init -q
        $actors=@('Actor','/root/review_actor','01a0b915-e25c-73c1-96a6-0f6e50b13417')
        function Identity($Path){Get-AiwByteIdentity ([IO.File]::ReadAllBytes($Path))}
        function Expected-Key($Actor){if($Actor-ceq$actors[2]){return $Actor};return 'actor-sha256-'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($Actor))).ToLowerInvariant()}
        # Exercise the exact private Maintenance cleanup body with its original script-root binding.
        $tokens=$null;$errors=$null;$maintenancePath=Join-Path $scriptsRoot 'resolve-framework-maintenance-process-requirements.ps1'
        $ast=[Management.Automation.Language.Parser]::ParseFile($maintenancePath,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'MAINTENANCE_TEST_PARSE'}
        $fn=$ast.Find({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Assert-SelfUpdateCleanupPath'},$true)
        . ([scriptblock]::Create($fn.Extent.Text.Replace('$PSScriptRoot',("'"+$scriptsRoot.Replace("'","''")+"'"))))
        $controlRoot=[IO.Path]::GetFullPath($fixtureRoot)
        $serial=0
        # New -> old -> new detects stale exports from another imported runtime.
        foreach($runtimeRoot in @($sourceRoot,$LegacyRuntimeRoot,$sourceRoot)){
            foreach($actor in $actors){
                $serial++;$modern=$runtimeRoot-ceq$sourceRoot;$expected=if($modern){Expected-Key $actor}else{$actor}
                $reason='';$key='';try{$key=Get-AiwBoundRuntimeActorStorageKey $runtimeRoot '1.16.0' $actor}catch{$reason=$_.Exception.Message}
                if(-not$modern-and$actor.Contains('/')){Assert-True ($reason-ceq'RUNTIME_ACTOR_LEGACY_CONTEXT') 'old-runtime-rejects-slash-without-borrowing-new-export';continue}
                Assert-True ($reason-eq''-and$key-ceq$expected) ('actual-runtime-storage-contract-'+$serial)
                $taskId='ACTOR-STORAGE-001'
                $context=[ordered]@{projectRoot=$controlRoot;frameworkVersion='1.16.0';actor=$actor;taskId=$taskId;authorizedActions=@('CONTROL_WRITE');exactScope=@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/upgrade-recovery/1.16.0/state.json')}
                $intent=[ordered]@{requestedActionKind='CONTROL_WRITE';ambiguityState='CLEAR'}
                $contextIdentity=(Get-AiwByteIdentity ($utf8.GetBytes(($context|ConvertTo-Json -Depth 30 -Compress)+"`n"+($intent|ConvertTo-Json -Depth 30 -Compress)))).Split('|')[1]
                $receipt=[ordered]@{schemaVersion=2;inputContractVersion=3;status='PASS';mode='DISCOVER';receiptType='PROCESS_REQUIREMENTS_DISCOVER';authorityGranted=$false;semanticCorrectnessProven=$false;binding=$context;intentEnvelope=$intent;contextIdentity=$contextIdentity;sourceLocators=@{frameworkRoot=$runtimeRoot}}
                $receiptPath=Join-Path $fixtureRoot ('receipt-'+$serial+'.json');Write-TestText $receiptPath (($receipt|ConvertTo-Json -Depth 30 -Compress)+"`n")
                $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Identity $receiptPath;preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
                $inputFull=Join-Path $fixtureRoot ('.ai-workspace/runtime/'+$taskId+'/'+$expected+'/input.json')
                New-Item -ItemType Directory -Path (Split-Path -Parent $inputFull) -Force|Out-Null
                Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
                Assert-SelfUpdateCleanupPath ($receipt|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30)
                Assert-True (Test-Path $inputFull) ('maintenance-validates-without-deleting-'+$serial)
                # Stop at absent preparation, after the real root API validates cleanup scope.
                $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor $actor -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'ADOPTION_PROCESS_EVIDENCE_REQUIRED|PREPARATION'-and-not(Test-Path $inputFull)) ('root-boundary-cleans-bound-input-on-later-failure-'+$serial)
                Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
                $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor 'wrong-actor' -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'ADOPTION_PROCESS_ACTOR_ROOT'-and(Test-Path $inputFull)) ('root-wrong-actor-keeps-input-'+$serial)
                $inputFull=Join-Path $fixtureRoot ('.ai-workspace/runtime/'+$taskId+'/wrong-storage/input.json');New-Item -ItemType Directory -Path (Split-Path -Parent $inputFull) -Force|Out-Null;Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
                $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor $actor -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'ADOPTION_PROCESS_CLEANUP_SCOPE'-and(Test-Path $inputFull)) ('root-wrong-path-keeps-input-'+$serial)
                $reason='';try{Assert-SelfUpdateCleanupPath ($receipt|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30)}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'MAINTENANCE_CLEANUP_SCOPE'-and(Test-Path $inputFull)) ('maintenance-wrong-path-keeps-input-'+$serial)
            }
        }
        # A junction in the actor directory must not authorize cleanup of its destination.
        $junction=Join-Path $fixtureRoot ('.ai-workspace/runtime/ACTOR-STORAGE-001/'+(Expected-Key $actors[0]))
        $destination=Join-Path $fixtureRoot 'junction-destination';New-Item -ItemType Directory -Path $destination -Force|Out-Null
        if(-not[IO.Path]::GetFullPath($junction).StartsWith([IO.Path]::GetFullPath($fixtureRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ACTOR_JUNCTION_TEST_SCOPE'}
        if(Test-Path $junction){Remove-Item -LiteralPath $junction -Recurse -Force}
        New-Item -ItemType Junction -Path $junction -Target $destination|Out-Null
        try{
            $receipt.binding.actor=$actors[0];$receipt.sourceLocators.frameworkRoot=$sourceRoot
            $receipt.contextIdentity=(Get-AiwByteIdentity ($utf8.GetBytes(($receipt.binding|ConvertTo-Json -Depth 30 -Compress)+"`n"+($receipt.intentEnvelope|ConvertTo-Json -Depth 30 -Compress)))).Split('|')[1]
            Write-TestText $receiptPath (($receipt|ConvertTo-Json -Depth 30 -Compress)+"`n");$boundary.expectedDiscoverReceiptIdentity=Identity $receiptPath
            $inputFull=Join-Path $junction 'input.json';Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
            $reason='';try{Assert-SelfUpdateCleanupPath ($receipt|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30)}catch{$reason=$_.Exception.Message}
            Assert-True ($reason-ceq'MAINTENANCE_CLEANUP_REPARSE'-and(Test-Path $inputFull)) 'maintenance-reparse-keeps-target'
            $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor $actors[0] -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
            Assert-True ($reason.Contains('REPARSE')-and(Test-Path $inputFull)) 'root-reparse-keeps-target'
        }finally{Remove-Item -LiteralPath $junction -Force}
        # Reuse the real source-recovery suite with only its anonymous actor fixture varied.
        $copy=Join-Path $fixtureRoot 'recovery-source';$copyVersion=Join-Path $copy 'framework/versions/1.16.0'
        New-Item -ItemType Directory -Path (Split-Path -Parent $copyVersion) -Force|Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'framework/versions/1.16.0') -Destination $copyVersion -Recurse
        Copy-Item -LiteralPath $scriptsRoot -Destination (Join-Path $copy 'scripts') -Recurse
        $testPath=Join-Path $copyVersion 'tests/source-postimage-transition-tests.ps1'
        $original=[IO.File]::ReadAllText($testPath)
        foreach($actor in $actors){
            [IO.File]::WriteAllText($testPath,$original.Replace('executor-fixture',$actor),$utf8)
            $output=@(& pwsh -NoProfile -NonInteractive -File $testPath 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
            if($code-ne0){throw ('ACTOR_RECOVERY_FAILED|'+$actor+'|'+($output-join';'))}
            Assert-True (@($output|Where-Object{$_-ceq'PASS|authorized-mixed-state-original-action-finalized'}).Count-eq1) ('real-rule-recovery-finalized-'+$actor)
            Write-Output ('PASS|actor-recovery|actor='+$actor+'|'+$output[-1])
        }
        Write-Output ('PASS|actor-storage-root-consumers|'+$passed+'/'+$passed)
        return
    }
    $custom = "# Project conventions`nOnly the approved project goal is delegated.`n"
    Assert-True ((Get-AiwStandingDelegationProjection -Text $custom) -ceq $custom) 'viewing-does-not-create-adoption'
    foreach($templatePath in @((Join-Path (Split-Path -Parent $scriptsRoot) 'framework/versions/1.16.0/project-starter/AGENTS.md'),(Join-Path (Split-Path -Parent $scriptsRoot) 'framework/maintenance-overlay/AGENTS.md'))){
        $delegated=Get-AiwStandingDelegationProjection -Text $custom -AdoptionRequested $true -TemplatePath $templatePath
        $block=Get-AiwAgentsTemplateBlock $delegated
        Assert-True ($delegated.StartsWith($custom)-and$block.Contains('在本项目内，AI 根据当前采用的 Framework、当前生效的项目纠正及永久规则作出的具体工作决定，均视为用户明确决定')-and-not$block.Contains('BOOTSTRAP.md')-and-not$delegated.Contains('AI-WORKSPACE-USER-DECISION')) 'registration-managed-delegation-preserves-outside'
        Assert-True ((Get-AiwStandingDelegationProjection -Text $delegated -AdoptionRequested $true -TemplatePath $templatePath)-ceq$delegated) 'template-projection-idempotent'
        $changed=$delegated.Replace('在本项目内，AI','HAND_EDITED_MANAGED')+"`n用户撤回持续委托。`n"
        $updated=Get-AiwStandingDelegationProjection -Text $changed -AdoptionRequested $true -TemplatePath $templatePath
        Assert-True (-not$updated.Contains('HAND_EDITED_MANAGED')-and$updated.EndsWith("`n用户撤回持续委托。`n")-and$updated.StartsWith($custom)) 'managed-hand-edit-overwritten-outside-revocation-retained'
        $default=@($block-split"`n"|Where-Object{$_-like'在本项目内，AI*'})[0]
        $legacy=$custom+"<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->`nold template`n<!-- AI-WORKSPACE-FRAMEWORK:END -->`n<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->`n$default`n用户将委托收窄为只读分析。`n<!-- AI-WORKSPACE-USER-DECISION:END -->`n"
        $migrated=Get-AiwStandingDelegationProjection -Text $legacy -AdoptionRequested $true -TemplatePath $templatePath
        $managedPattern='(?s)<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->.*?<!-- AI-WORKSPACE-FRAMEWORK:END -->'
        Assert-True ([regex]::Replace($migrated,$managedPattern,'')-ceq[regex]::Replace($legacy,$managedPattern,'')) 'upgrade-keeps-complete-outside-declaration-and-project-restriction'
        Assert-True ((Get-AiwStandingDelegationProjection -Text $migrated -AdoptionRequested $true -TemplatePath $templatePath)-ceq$migrated) 'legacy-migration-idempotent'
        $rejected=$false;try{$null=Get-AiwStandingDelegationProjection -Text ($custom+'<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->') -AdoptionRequested $true -TemplatePath $templatePath}catch{$rejected=$_.ToString().Contains('AGENTS_MANAGED_MARKERS_MALFORMED')}
        Assert-True $rejected 'malformed-managed-markers-rejected'
    }
    if($EntryTemplatesOnly){Write-Output ('PASS|entry-template-projections|'+$passed+'/'+$passed);return}
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
    # A completed historical transaction exercises the legacy self-update route;
    # the same suite separately tests fixed-runtime adoption and relocation.
    $seedArguments=@()
    foreach($name in @('SeedControlRoot','SeedFrameworkRoot','SeedTransactionPath','ExpectedSeedTransactionIdentity')){
        $value=Get-Variable -Name $name -ValueOnly
        if(-not[string]::IsNullOrEmpty($value)){$seedArguments+=@(('-'+$name),$value)}
    }
    $selfUpdateOutput = @(& pwsh -NoProfile -NonInteractive -File $selfUpdateTest @seedArguments 2>&1 | ForEach-Object { [string]$_ })
    $selfUpdateCode = $LASTEXITCODE
    if ($selfUpdateCode -ne 0) { throw ('MAINTENANCE_SELF_UPDATE_FAILED|' + ($selfUpdateOutput -join [Environment]::NewLine)) }
    $selfUpdateFinal=@($selfUpdateOutput|Where-Object{$_-cmatch'^PASS\|maintenance-self-update\|\d+/\d+$'})
    $selfUpdateCounts=if($selfUpdateFinal.Count-eq1){[regex]::Match($selfUpdateFinal[0],'^PASS\|maintenance-self-update\|(\d+)/(\d+)$')}else{$null}
    Assert-True ($selfUpdateCode-eq0-and$selfUpdateFinal.Count-eq1-and$null-ne$selfUpdateCounts-and$selfUpdateCounts.Groups[1].Value-ceq$selfUpdateCounts.Groups[2].Value) 'maintenance-self-update-focused-entrypoint'
    $selfUpdateOutput|Write-Output

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
