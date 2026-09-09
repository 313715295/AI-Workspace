Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
$script:Utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-AiwCurrentIdentity {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-AiwByteIdentity ([IO.File]::ReadAllBytes($Path))
    }
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.PSIsContainer -and
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            return 'DIRECTORY'
        }
        return 'NON_FILE'
    }
    return 'MISSING'
}

function Write-AiwAtomicBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent
    }
    $temporary = $Path + '.aiw-tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            [IO.File]::Delete($temporary)
        }
    }
}

function Write-AiwTransactionState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    $json = ($Value | ConvertTo-Json -Depth 64 -Compress) + "`n"
    Write-AiwAtomicBytes $Path ($script:Utf8NoBom.GetBytes($json))
}

function Assert-AiwProjectionContract {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Projection
    )

    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    if ($Projection.schemaVersion -ne 1 -or $Projection.objects -isnot [array]) {
        throw 'PROJECTION_SCHEMA'
    }
    if ($root -cne [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$Projection.repositoryRoot))) {
        throw 'PROJECTION_ROOT_MISMATCH'
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Projection.objects)) {
        foreach ($field in @('path', 'kind', 'oldExists', 'newExists', 'oldIdentity', 'newIdentity', 'changed', 'oldBase64', 'newBase64')) {
            if ($null -eq $entry.PSObject.Properties[$field]) {
                throw ('PROJECTION_FIELD_MISSING|' + $field)
            }
        }
        Assert-AiwRelativePath ([string]$entry.path)
        $null = Get-AiwContainedPath $root ([string]$entry.path)
        if ([string]$entry.kind -cnotin @('FILE', 'DIRECTORY')) {
            throw ('PROJECTION_KIND_INVALID|' + [string]$entry.path)
        }
        if (-not $seen.Add([string]$entry.path)) {
            throw ('PROJECTION_PATH_DUPLICATE|' + [string]$entry.path)
        }
        if ($entry.oldExists -isnot [bool] -or $entry.newExists -isnot [bool] -or $entry.changed -isnot [bool]) {
            throw ('PROJECTION_BOOLEAN_FIELD|' + [string]$entry.path)
        }
        $oldBytes = [Convert]::FromBase64String([string]$entry.oldBase64)
        $newBytes = [Convert]::FromBase64String([string]$entry.newBase64)
        if ([string]$entry.kind -ceq 'DIRECTORY' -and
            ($oldBytes.Length -ne 0 -or $newBytes.Length -ne 0 -or -not [bool]$entry.newExists)) {
            throw ('PROJECTION_DIRECTORY_INVALID|' + [string]$entry.path)
        }
        $expectedOld = if (-not [bool]$entry.oldExists) { 'MISSING' } elseif ([string]$entry.kind -ceq 'DIRECTORY') { 'DIRECTORY' } else { Get-AiwByteIdentity $oldBytes }
        $expectedNew = if (-not [bool]$entry.newExists) { 'MISSING' } elseif ([string]$entry.kind -ceq 'DIRECTORY') { 'DIRECTORY' } else { Get-AiwByteIdentity $newBytes }
        if ($expectedOld -cne [string]$entry.oldIdentity -or $expectedNew -cne [string]$entry.newIdentity) {
            throw ('PROJECTION_IDENTITY_INVALID|' + [string]$entry.path)
        }
        if (([string]$entry.oldIdentity -cne [string]$entry.newIdentity) -ne [bool]$entry.changed) {
            throw ('PROJECTION_CHANGE_FLAG_INVALID|' + [string]$entry.path)
        }
    }
    return $root
}

function Get-AiwMissingParentDirectory {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $parts = @($RelativePath.Split('/'))
    $missing = [Collections.Generic.List[string]]::new()
    if ($parts.Count -le 1) {
        return @()
    }
    for ($index = 1; $index -lt $parts.Count; $index++) {
        $relative = [string]::Join('/', $parts[0..($index - 1)])
        $full = Get-AiwContainedPath $RepositoryRoot $relative
        if (-not (Test-Path -LiteralPath $full)) {
            $missing.Add($relative)
        }
        elseif (-not (Test-Path -LiteralPath $full -PathType Container)) {
            throw ('PARENT_NOT_DIRECTORY|' + $relative)
        }
    }
    return @($missing)
}

function Get-AiwProjectionMissingParentDirectory {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Projection
    )

    $root = Assert-AiwProjectionContract $RepositoryRoot $Projection
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Projection.objects | Where-Object { $_.changed -and $_.newExists })) {
        foreach ($relative in @(Get-AiwMissingParentDirectory $root ([string]$entry.path))) {
            $null = $seen.Add($relative)
        }
    }
    return @($seen)
}

function Remove-AiwCreatedDirectory {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RelativePath
    )

    $ordered = @($RelativePath | Sort-Object { $_.Split('/').Count } -Descending)
    foreach ($relative in $ordered) {
        $path = Get-AiwContainedPath $RepositoryRoot $relative
        if (Test-Path -LiteralPath $path -PathType Container) {
            if ([IO.Directory]::EnumerateFileSystemEntries($path).GetEnumerator().MoveNext()) {
                continue
            }
            [IO.Directory]::Delete($path, $false)
        }
    }
}

function Get-AiwRollbackOrder {
    param([Parameter(Mandatory)][object[]]$ChangedObject)

    $project = @($ChangedObject | Where-Object { [string]$_.path -ceq '.ai-workspace/project.json' })
    $other = @($ChangedObject | Where-Object { [string]$_.path -cne '.ai-workspace/project.json' })
    [Array]::Reverse($other)
    return @($project + $other)
}

function Restore-AiwProjectProjection {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Projection,
        [string[]]$CreatedDirectory = @(),
        [scriptblock]$RollbackPostcheck
    )

    $root = Assert-AiwProjectionContract $RepositoryRoot $Projection
    $changed = @($Projection.objects | Where-Object changed)
    foreach ($entry in @(Get-AiwRollbackOrder $changed)) {
        $path = Get-AiwContainedPath $root ([string]$entry.path)
        $actual = Get-AiwCurrentIdentity $path
        if ($actual -cne [string]$entry.newIdentity -and $actual -cne [string]$entry.oldIdentity) {
            throw ('ROLLBACK_THIRD_PARTY_DRIFT|' + [string]$entry.path + '|' + $actual)
        }
        if ($actual -ceq [string]$entry.oldIdentity) {
            continue
        }

        if ([string]$entry.kind -ceq 'DIRECTORY') {
            if ([IO.Directory]::GetFileSystemEntries($path).Count -ne 0) {
                throw ('ROLLBACK_THIRD_PARTY_DRIFT|' + [string]$entry.path + '|DIRECTORY_NOT_EMPTY')
            }
            [IO.Directory]::Delete($path, $false)
        }
        elseif ([bool]$entry.oldExists) {
            Write-AiwAtomicBytes $path ([Convert]::FromBase64String([string]$entry.oldBase64))
        }
        elseif (Test-Path -LiteralPath $path -PathType Leaf) {
            [IO.File]::Delete($path)
        }
        if ((Get-AiwCurrentIdentity $path) -cne [string]$entry.oldIdentity) {
            throw ('ROLLBACK_POSTIMAGE_MISMATCH|' + [string]$entry.path)
        }
    }

    Remove-AiwCreatedDirectory $root $CreatedDirectory
    if ($null -ne $RollbackPostcheck) {
        $rollbackResult = & $RollbackPostcheck $root $Projection
        if ($rollbackResult -isnot [bool] -or -not $rollbackResult) {
            throw 'ROLLBACK_BEHAVIOR_POSTCHECK_FAILED'
        }
    }
}

function Invoke-AiwProjectProjectionTransaction {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Projection,
        [Parameter(Mandatory)][string]$TransactionRelativePath,
        [Parameter(Mandatory)][scriptblock]$Postcheck,
        [Parameter(Mandatory)][scriptblock]$RollbackPostcheck,
        [int]$FailAfterWrite = -1,
        [int]$InterruptAfterWrite = -1,
        [scriptblock]$Preflight = { param($Root, $Candidate) $true },
        [hashtable]$Metadata = @{}
    )

    $root = Assert-AiwProjectionContract $RepositoryRoot $Projection
    Assert-AiwRelativePath $TransactionRelativePath
    $transactionRootAllowed =
        $TransactionRelativePath.StartsWith('.ai-workspace/upgrade-recovery/', [StringComparison]::Ordinal) -or
        $TransactionRelativePath.StartsWith('.ai-workspace/runtime/project-adoption/', [StringComparison]::Ordinal)
    if (-not $transactionRootAllowed -or
        -not $TransactionRelativePath.EndsWith('/state.json', [StringComparison]::Ordinal)) {
        throw 'TRANSACTION_PATH_INVALID'
    }
    $transactionPath = Get-AiwContainedPath $root $TransactionRelativePath

    if ([bool]$Projection.noOp) {
        return [pscustomobject]@{ status = 'NO_CHANGE'; transactionCreated = $false; writes = 0 }
    }
    if (Test-Path -LiteralPath $transactionPath -PathType Leaf) {
        $existing = Read-AiwProjectJson $transactionPath 'TRANSACTION_STATE'
        if ($existing.Value.schemaVersion -ne 1 -or
            [string]$existing.Value.repositoryRoot -cne $root -or
            [string]$existing.Value.transactionRelativePath -cne $TransactionRelativePath -or
            $existing.Value.transactionComplete -isnot [bool]) {
            throw 'TRANSACTION_STATE_SCHEMA'
        }
        if (-not [bool]$existing.Value.transactionComplete) {
            throw ('TRANSACTION_RECOVERY_REQUIRED|' + $existing.Identity)
        }
    }
    foreach ($entry in @($Projection.objects | Where-Object changed)) {
        $path = Get-AiwContainedPath $root ([string]$entry.path)
        if ((Get-AiwCurrentIdentity $path) -cne [string]$entry.oldIdentity) {
            throw ('PREFLIGHT_OBJECT_DRIFT|' + [string]$entry.path)
        }
    }
    $preflightResult = & $Preflight $root $Projection
    if ($preflightResult -isnot [bool] -or -not $preflightResult) {
        throw 'PREFLIGHT_FAILED'
    }

    $createdDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Projection.objects | Where-Object { $_.changed -and $_.newExists })) {
        foreach ($relative in @(Get-AiwMissingParentDirectory $root ([string]$entry.path))) {
            $null = $createdDirectories.Add($relative)
        }
    }

    $metadataObject = [ordered]@{}
    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $metadataObject[[string]$key] = $Metadata[$key]
    }
    $state = [ordered]@{
        schemaVersion = 1
        state = 'APPLYING'
        repositoryRoot = $root
        transactionRelativePath = $TransactionRelativePath
        projection = $Projection
        metadata = $metadataObject
        createdDirectories = @($createdDirectories)
        completedWrites = 0
        transactionComplete = $false
    }
    Write-AiwTransactionState $transactionPath $state

    try {
        foreach ($entry in @($Projection.objects | Where-Object { $_.changed -and [string]$_.kind -ceq 'DIRECTORY' })) {
            $path = Get-AiwContainedPath $root ([string]$entry.path)
            if ((Get-AiwCurrentIdentity $path) -cne [string]$entry.oldIdentity) {
                throw ('APPLY_OBJECT_DRIFT|' + [string]$entry.path)
            }
            $null = New-Item -ItemType Directory -Path $path
            if ((Get-AiwCurrentIdentity $path) -cne [string]$entry.newIdentity) {
                throw ('APPLY_POSTIMAGE_MISMATCH|' + [string]$entry.path)
            }
            $state.completedWrites = [int]$state.completedWrites + 1
            Write-AiwTransactionState $transactionPath $state
            if($InterruptAfterWrite-ge0-and[int]$state.completedWrites-ge$InterruptAfterWrite){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
            if ($FailAfterWrite -ge 0 -and [int]$state.completedWrites -ge $FailAfterWrite) {
                throw 'INJECTED_APPLY_FAILURE'
            }
        }
        foreach ($entry in @($Projection.objects | Where-Object { $_.changed -and [string]$_.kind -ceq 'FILE' })) {
            $path = Get-AiwContainedPath $root ([string]$entry.path)
            if ((Get-AiwCurrentIdentity $path) -cne [string]$entry.oldIdentity) {
                throw ('APPLY_OBJECT_DRIFT|' + [string]$entry.path)
            }
            if ([bool]$entry.newExists) {
                Write-AiwAtomicBytes $path ([Convert]::FromBase64String([string]$entry.newBase64))
            }
            elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                [IO.File]::Delete($path)
            }
            if ((Get-AiwCurrentIdentity $path) -cne [string]$entry.newIdentity) {
                throw ('APPLY_POSTIMAGE_MISMATCH|' + [string]$entry.path)
            }

            $state.completedWrites = [int]$state.completedWrites + 1
            Write-AiwTransactionState $transactionPath $state
            if($InterruptAfterWrite-ge0-and[int]$state.completedWrites-ge$InterruptAfterWrite){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
            if ($FailAfterWrite -ge 0 -and [int]$state.completedWrites -ge $FailAfterWrite) {
                throw 'INJECTED_APPLY_FAILURE'
            }
        }

        $postcheckResult = & $Postcheck $root $Projection
        if ($postcheckResult -isnot [bool] -or -not $postcheckResult) {
            throw 'POSTCHECK_FAILED'
        }

        $state.state = 'COMPLETE'
        $state.transactionComplete = $true
        Write-AiwTransactionState $transactionPath $state
        return [pscustomobject]@{
            status = 'COMPLETE'
            transactionCreated = $true
            writes = [int]$state.completedWrites
            transactionIdentity = Get-AiwCurrentIdentity $transactionPath
        }
    }
    catch {
        $failure = [string]$_.Exception.Message
        try {
            Restore-AiwProjectProjection $root $Projection @($createdDirectories) $RollbackPostcheck
            $state.state = 'ROLLED_BACK'
            $state.transactionComplete = $true
            $state.failure = $failure
            Write-AiwTransactionState $transactionPath $state
            if($InterruptAfterWrite-ge0-and[int]$state.completedWrites-ge$InterruptAfterWrite){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
        }
        catch {
            $state.state = 'ROLLBACK_BLOCKED'
            $state.transactionComplete = $false
            $state.failure = $failure
            $state.rollbackFailure = [string]$_.Exception.Message
            Write-AiwTransactionState $transactionPath $state
            if($InterruptAfterWrite-ge0-and[int]$state.completedWrites-ge$InterruptAfterWrite){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
            throw ('ROLLBACK_BLOCKED|' + $state.rollbackFailure)
        }
        throw ('TRANSACTION_ROLLED_BACK|' + $failure)
    }
}

function Resume-AiwProjectProjectionRollback {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$TransactionRelativePath,
        [Parameter(Mandatory)][string]$ExpectedTransactionIdentity,
        [Parameter(Mandatory)][scriptblock]$RollbackPostcheck
    )

    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    Assert-AiwRelativePath $TransactionRelativePath
    $transactionRootAllowed =
        $TransactionRelativePath.StartsWith('.ai-workspace/upgrade-recovery/', [StringComparison]::Ordinal) -or
        $TransactionRelativePath.StartsWith('.ai-workspace/runtime/project-adoption/', [StringComparison]::Ordinal)
    if (-not $transactionRootAllowed -or
        -not $TransactionRelativePath.EndsWith('/state.json', [StringComparison]::Ordinal)) {
        throw 'TRANSACTION_PATH_INVALID'
    }
    $transactionPath = Get-AiwContainedPath $root $TransactionRelativePath
    if ((Get-AiwCurrentIdentity $transactionPath) -cne $ExpectedTransactionIdentity) {
        throw 'TRANSACTION_STATE_DRIFT'
    }

    $record = Read-AiwProjectJson $transactionPath 'TRANSACTION_STATE'
    $state = $record.Value
    if ($state.schemaVersion -ne 1 -or
        [string]$state.repositoryRoot -cne $root -or
        [string]$state.transactionRelativePath -cne $TransactionRelativePath -or
        $state.transactionComplete -isnot [bool]) {
        throw 'TRANSACTION_STATE_SCHEMA'
    }
    if ([bool]$state.transactionComplete) {
        return [pscustomobject]@{ status = [string]$state.state; changed = $false }
    }

    Restore-AiwProjectProjection $root $state.projection @($state.createdDirectories) $RollbackPostcheck
    $state.state = 'ROLLED_BACK'
    $state.transactionComplete = $true
    Write-AiwTransactionState $transactionPath $state
    [pscustomobject]@{
        status = 'ROLLED_BACK'
        changed = $true
        transactionIdentity = Get-AiwCurrentIdentity $transactionPath
    }
}

Export-ModuleMember -Function Invoke-AiwProjectProjectionTransaction, Resume-AiwProjectProjectionRollback, Restore-AiwProjectProjection, Get-AiwProjectionMissingParentDirectory

function Invoke-AiwProjectRuleActionRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$ExpectedPlanIdentity,
        [Parameter(Mandatory)][string]$ObservedActor,
        [ValidateSet('COMPLETE','ROLLBACK')][string]$Direction='COMPLETE',
        [switch]$Apply,
        [int]$InterruptAfterWrite=-1
    )
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $planDoc=Read-AiwProjectJson $PlanPath 'RULE_RECOVERY_PLAN'
    if($planDoc.Identity-cne$ExpectedPlanIdentity){throw 'RULE_RECOVERY_PLAN_DRIFT'}
    $plan=$planDoc.Value
    function Assert-RecoveryFields($Value,[string[]]$Names,[string]$Label){
        if($Value-isnot[pscustomobject]-or@($Value.PSObject.Properties).Count-ne$Names.Count-or@($Names|Where-Object{$_-cnotin$Value.PSObject.Properties.Name}).Count-ne0){throw ($Label+'_FIELDS')}
    }
    Assert-RecoveryFields $plan @('schemaVersion','discoverReceiptPath','discoverReceiptIdentity','admitInputPath','admitInputIdentity','admitResultPath','admitResultIdentity','objects','preparationReceipts','resultReceipts','transactionRelativePath') 'RULE_RECOVERY_PLAN'
    if($plan.schemaVersion-ne1-or$plan.objects-isnot[array]-or$plan.preparationReceipts-isnot[array]-or$plan.resultReceipts-isnot[array]){throw 'RULE_RECOVERY_PLAN_SCHEMA'}
    $documents=@{}
    foreach($kind in @('discoverReceipt','admitInput','admitResult')){
        $doc=Read-AiwProjectJson ([string]$plan.($kind+'Path')) ('RULE_RECOVERY_'+$kind)
        if($doc.Identity-cne[string]$plan.($kind+'Identity')){throw ('RULE_RECOVERY_EVIDENCE_DRIFT|'+$kind)}
        $documents[$kind]=$doc.Value
    }
    $receipt=$documents.discoverReceipt;$admit=$documents.admitInput;$result=$documents.admitResult
    if([int]$receipt.schemaVersion-eq2){
        $binding=$receipt.binding;$intent=$receipt.intentEnvelope
        $context=[pscustomobject]@{actor=$binding.actor;taskId=$binding.taskId;taskOwner=$binding.taskOwner;taskActor=$binding.taskActor;taskIdentity=$binding.taskIdentity;projectRoot=$binding.projectRoot;gitTop=$binding.repositoryGitTop;paths=@($binding.exactScope);authorizationIdentity=$binding.authorizationIdentity;objective=$intent.objective;action=$intent.requestedActionKind;result=$intent.requestedResultKind}
    }elseif([int]$receipt.schemaVersion-eq1){
        $binding=$receipt.authorityContext
        $context=[pscustomobject]@{actor=$receipt.actor;taskId=$receipt.taskId;taskOwner=$receipt.taskOwner;taskActor=$receipt.taskActor;taskIdentity=$receipt.taskIdentity;projectRoot=$receipt.sourceLocators.projectRoot;gitTop=$binding.repositoryGitTop;paths=@($receipt.exactPaths);authorizationIdentity=$binding.authorizationIdentity;objective=$receipt.objective;action=$receipt.actionKind;result=$receipt.resultKind}
    }else{throw 'RULE_RECOVERY_RECEIPT_SCHEMA'}
    if([string]$receipt.status-cne'PASS'-or[string]$receipt.mode-cne'DISCOVER'-or[string]$context.action-cne'CONTROL_WRITE'-or[string]$context.actor-cne$ObservedActor-or[IO.Path]::GetFullPath([string]$context.projectRoot)-cne$root){throw 'RULE_RECOVERY_CONTEXT'}
    $gitTop=@(& git -C $root rev-parse --show-toplevel 2>$null)
    if($LASTEXITCODE-ne0-or$gitTop.Count-ne1-or[IO.Path]::GetFullPath([string]$gitTop[0])-cne[IO.Path]::GetFullPath([string]$context.gitTop)){throw 'RULE_RECOVERY_GIT_TOP'}
    $allowed=@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json')
    if($context.paths.Count-ne2-or@($context.paths|Select-Object -Unique).Count-ne2-or@($context.paths|Where-Object{$_-cnotin$allowed}).Count-ne0){throw 'RULE_RECOVERY_EXACT_SCOPE'}
    $packageDoc=Read-AiwProjectJson ([string]$receipt.sourceLocators.authorizationPackagePath) 'RULE_RECOVERY_AUTHORIZATION'
    $package=$packageDoc.Value
    if($packageDoc.Identity-cne[string]$context.authorizationIdentity-or$package.schemaVersion-notin@(1,2)-or
       ($package.schemaVersion-eq2-and[string]$package.repositoryId-cne'CONTROL')-or
       [string]$package.grantee-cne$ObservedActor-or[string]$package.owner-cne[string]$context.taskOwner-or
       [string]$package.taskId-cne[string]$context.taskId-or[string]$package.taskIdentity-cne[string]$context.taskIdentity-or
       'CONTROL_WRITE'-cnotin@($package.actions)-or
       [string]::Join('|',@($package.exactPaths))-cne[string]::Join('|',@($context.paths))){throw 'RULE_RECOVERY_AUTHORIZATION_BINDING'}
    # This narrow entry covers an original admitted source action. A continuation
    # needs its own existing predecessor proof and is never inferred here.
    if($null-ne$package.PSObject.Properties['continuationPlan']){throw 'RULE_RECOVERY_CONTINUATION_PROOF_REQUIRED'}
    if([int]$admit.schemaVersion-notin@(1,2)-or[string]$admit.mode-cne'ADMIT_ACTION'-or
       [string]$admit.expectedDiscoverReceiptIdentity-cne[string]$plan.discoverReceiptIdentity-or
       [IO.Path]::GetFullPath([string]$admit.discoverReceiptPath)-cne[IO.Path]::GetFullPath([string]$plan.discoverReceiptPath)-or
       [string]$result.status-cne'PASS'-or[string]$result.mode-cne'ADMIT_ACTION'-or
       [string]$result.selectionIdentity-cne[string]$receipt.selectionIdentity-or
       @($result.missingPreparation).Count-ne0-or@($result.missingResult).Count-ne0){throw 'RULE_RECOVERY_ORIGINAL_ADMISSION_REQUIRED'}
    $required=@($receipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique)
    if(@($required|Where-Object{$_-cnotin@($admit.preparationReceipts)}).Count-ne0){throw 'RULE_RECOVERY_ORIGINAL_PREPARATION'}
    if([int]$admit.schemaVersion-eq1-and([string]$admit.objective-cne[string]$context.objective-or[string]$admit.actionKind-cne'CONTROL_WRITE'-or[string]$admit.resultKind-cne[string]$context.result-or[string]$admit.authorizationIdentity-cne[string]$context.authorizationIdentity-or[string]::Join('|',@($admit.exactPaths))-cne[string]::Join('|',@($context.paths)))){throw 'RULE_RECOVERY_ORIGINAL_ADMISSION_CONTEXT'}
    $material=@($receipt.sourceCompositionIdentity,$receipt.selectionIdentity,$receipt.contextIdentity,'ADMIT_ACTION',$context.objective,$context.action,$context.result,[string]::Join(',',@($context.paths)),$context.authorizationIdentity,[string]::Join(',',@($admit.preparationReceipts)),[string]::Join(',',@($admit.resultReceipts)),[string]::Join(',',@($admit.deliveryReceipts)),$admit.publicDecisionIdentity,$admit.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join[string][char]10
    $decision=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($material)))
    if($decision-cne[string]$result.decisionIdentity){throw 'RULE_RECOVERY_ORIGINAL_ADMISSION_DECISION'}
    $framework=[IO.Path]::GetFullPath([string]$receipt.sourceLocators.frameworkRoot)
    $version=[string]$package.frameworkVersion
    $static=@{
        projectConfigIdentity=(Join-Path $root '.ai-workspace/project.json')
        controllerIdentity=(Join-Path $root '.ai-workspace/controller.json')
        correctionsIdentity=(Join-Path $root '.ai-workspace/corrections.json')
        taskIdentity=(Join-Path $root ([string]$receipt.sourceLocators.taskRelativePath))
        frameworkVersionIdentity=(Join-Path $framework "framework/versions/$version/VERSION.json")
        releaseManifestIdentity=(Join-Path $framework "framework/versions/$version/RELEASE_MANIFEST.json")
        nativeCatalogIdentity=(Join-Path $framework "framework/versions/$version/PROCESS_REQUIREMENTS.json")
        correctionCoverageIdentity=(Join-Path $framework "framework/versions/$version/CORRECTION_COVERAGE.json")
        candidatePilotStateIdentity=(Join-Path $root ".ai-workspace/upgrade-recovery/$version/state.json")
    }
    foreach($name in $static.Keys){
        $actual=Get-AiwCurrentIdentity ([string]$static[$name])
        if($actual-cne[string]$receipt.sourceBindings.$name){throw ('RULE_RECOVERY_UNAUTHORIZED_SOURCE_DRIFT|'+$name)}
    }
    $entries=@{};$oldObjects=@{};$desired=@();$bootstrapPreimage=$null
    if($plan.objects.Count-ne2){throw 'RULE_RECOVERY_OBJECT_COUNT'}
    foreach($entry in $plan.objects){
        Assert-RecoveryFields $entry @('path','preimagePath','preimageIdentity','postimagePath','postimageIdentity') 'RULE_RECOVERY_OBJECT'
        $relative=[string]$entry.path
        if($relative-cnotin$allowed-or$entries.ContainsKey($relative)){throw 'RULE_RECOVERY_OBJECT_SCOPE'}
        $authorized=@($package.objectIdentities|Where-Object{[string]$_.path-ceq$relative})
        if($authorized.Count-ne1-or[string]$authorized[0].identity-cne[string]$entry.preimageIdentity){throw 'RULE_RECOVERY_PREIMAGE_NOT_AUTHORIZED'}
        foreach($side in @('preimage','postimage')){
            $file=[IO.Path]::GetFullPath([string]$entry.($side+'Path'))
            $controlPrefix=Join-Path $root '.ai-workspace'
            if(-not$file.StartsWith($controlPrefix+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'RULE_RECOVERY_MATERIAL_PATH'}
            $relativeMaterial=$file.Substring($root.Length+1).Replace('\','/')
            $file=Get-AiwContainedPath $root $relativeMaterial
            if((Get-AiwCurrentIdentity $file)-cne[string]$entry.($side+'Identity')){throw ('RULE_RECOVERY_MATERIAL_DRIFT|'+$relative+'|'+$side)}
        }
        $live=Get-AiwCurrentIdentity (Get-AiwContainedPath $root $relative)
        if($live-cne[string]$entry.preimageIdentity-and$live-cne[string]$entry.postimageIdentity){throw ('RULE_RECOVERY_THIRD_PARTY_OBJECT|'+$relative)}
        $entries[$relative]=$entry
        if($relative-ceq'.ai-workspace/BOOTSTRAP.md'){$bootstrapPreimage=$entry}
        $source=if($Direction-ceq'COMPLETE'){[string]$entry.postimagePath}else{[string]$entry.preimagePath}
        $desired += [pscustomobject]@{path=$relative;bytes=[IO.File]::ReadAllBytes($source)}
    }
    Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionProjection.psm1') -ErrorAction Stop
    $transactionRelative=[string]$plan.transactionRelativePath
    Assert-AiwRelativePath $transactionRelative
    $prefix='.ai-workspace/upgrade-recovery/project-rules/'+[string]$context.taskId+'/'
    if(-not$transactionRelative.StartsWith($prefix,[StringComparison]::Ordinal)-or-not$transactionRelative.EndsWith('/state.json',[StringComparison]::Ordinal)){throw 'RULE_RECOVERY_TRANSACTION_PATH'}
    $transactionPath=Get-AiwContainedPath $root $transactionRelative
    $projection=New-AiwProjectProjection $root $desired
    if(-not$Apply){return [pscustomobject]@{status='WHAT_IF';direction=$Direction;source='ORIGINAL_ADMISSION';transactionPath=$transactionPath;exactPaths=@($context.paths);changes=@(Get-AiwProjectProjectionDiff $projection);authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}}
    $runtime=Join-Path $root ('.ai-workspace/runtime/'+[string]$context.taskId+'/'+$ObservedActor)
    [IO.Directory]::CreateDirectory($runtime)|Out-Null
    $finalInput=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=[string]$plan.discoverReceiptPath;expectedDiscoverReceiptIdentity=[string]$plan.discoverReceiptIdentity;preparationReceipts=@($plan.preparationReceipts)+@('BOOTSTRAP_PREIMAGE|'+[string]$bootstrapPreimage.preimagePath+'|'+[string]$bootstrapPreimage.preimageIdentity);resultReceipts=@($plan.resultReceipts);deliveryReceipts=@();publicDecisionIdentity=[string]$admit.publicDecisionIdentity;protectionState=[string]$admit.protectionState}
    $finalResolver=Join-Path (Split-Path -Parent $PSScriptRoot) "framework/versions/$version/scripts/resolve-process-requirements.ps1"
    $finalResult=$null
    $postcheck={
        param($checkRoot,$checkProjection)
        $inputCopy=$finalInput|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64
        foreach($relative in $context.paths){$inputCopy.resultReceipts+=('OBJECT_POSTIMAGE|'+$relative+'|'+(Get-AiwCurrentIdentity (Get-AiwContainedPath $root $relative)))}
        $inputPath=Join-Path $runtime ('rule-recovery-finalize-'+[guid]::NewGuid().ToString('N')+'.json')
        [IO.File]::WriteAllText($inputPath,($inputCopy|ConvertTo-Json -Depth 64 -Compress)+[char]10,$script:Utf8NoBom)
        $output=@(& $finalResolver -InputPath $inputPath -AsJson -DeleteInputOnExit 2>&1|ForEach-Object{[string]$_})
        if($LASTEXITCODE-ne0-or$output.Count-ne1){throw ('RULE_RECOVERY_ORIGINAL_FINALIZE|'+($output-join';'))}
        $parsed=$output[0]|ConvertFrom-Json -Depth 64
        if([string]$parsed.status-cne'PASS'){throw ('RULE_RECOVERY_ORIGINAL_FINALIZE|'+$output[0])}
        return $true
    }
    if(Test-Path -LiteralPath $transactionPath -PathType Leaf){
        $saved=(Read-AiwProjectJson $transactionPath 'RULE_RECOVERY_STATE').Value
        if([string]$saved.metadata.operation-cne'PROJECT_RULE_ACTION_RECOVERY'-or[string]$saved.metadata.planIdentity-cne$ExpectedPlanIdentity-or[string]$saved.metadata.direction-cne$Direction){throw 'RULE_RECOVERY_TRANSACTION_BINDING'}
        if(@($saved.projection.objects).Count-ne2){throw 'RULE_RECOVERY_SAVED_SCOPE'}
        foreach($object in $saved.projection.objects){
            if([string]$object.path-cnotin$allowed){throw 'RULE_RECOVERY_SAVED_SCOPE'}
            $sourceEntry=$entries[[string]$object.path]
            $expected=if($Direction-ceq'COMPLETE'){[string]$sourceEntry.postimageIdentity}else{[string]$sourceEntry.preimageIdentity}
            if([string]$object.newIdentity-cne$expected-or[string]$object.oldIdentity-cnotin@([string]$sourceEntry.preimageIdentity,[string]$sourceEntry.postimageIdentity)){throw 'RULE_RECOVERY_SAVED_OBJECT'}
        }
        $projection=$saved.projection
        $null=Assert-AiwProjectionContract $root $projection
        # All objects are checked before any resumed write.
        foreach($entry in $projection.objects){$live=Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path);if($live-cne$entry.oldIdentity-and$live-cne$entry.newIdentity){throw ('RULE_RECOVERY_THIRD_PARTY_OBJECT|'+$entry.path)}}
        foreach($entry in $projection.objects|Where-Object changed){$path=Get-AiwContainedPath $root $entry.path;if((Get-AiwCurrentIdentity $path)-cne$entry.newIdentity){Write-AiwAtomicBytes $path ([Convert]::FromBase64String($entry.newBase64));$saved.completedWrites++;Write-AiwTransactionState $transactionPath $saved}}
        if(-not(& $postcheck $root $projection)){throw 'RULE_RECOVERY_POSTCHECK'}
        $saved.state='COMPLETE';$saved.transactionComplete=$true;Write-AiwTransactionState $transactionPath $saved
    }elseif([bool]$projection.noOp){
        if(-not(& $postcheck $root $projection)){throw 'RULE_RECOVERY_POSTCHECK'}
    }else{
        $null=Invoke-AiwProjectProjectionTransaction $root $projection $transactionRelative $postcheck {param($r,$p) $true} -InterruptAfterWrite $InterruptAfterWrite -Metadata @{operation='PROJECT_RULE_ACTION_RECOVERY';planIdentity=$ExpectedPlanIdentity;direction=$Direction;origin='RECOVERY_CREATED_NOW_FROM_ORIGINAL_ADMISSION';admissionIdentity=[string]$plan.admitResultIdentity}
        $saved=(Read-AiwProjectJson $transactionPath 'RULE_RECOVERY_STATE').Value
        if(-not$saved.transactionComplete){return [pscustomobject]@{status='INTERRUPTED';direction=$Direction;transactionPath=$transactionPath;transactionIdentity=Get-AiwCurrentIdentity $transactionPath;evidenceGrade='INSTRUCTION_BOUND'}}
    }
    return [pscustomobject]@{status=$(if($Direction-ceq'COMPLETE'){'COMPLETED'}else{'ROLLED_BACK'});originalActionFinalized=$true;source='ORIGINAL_ADMISSION';transactionPath=$transactionPath;transactionIdentity=Get-AiwCurrentIdentity $transactionPath;authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}
}
Export-ModuleMember -Function Invoke-AiwProjectRuleActionRecovery
function Assert-AiwRuntimeAdoptionProjection {
    param([string]$Root,$Projection,[string]$VersionRoot,[string]$Version,[string]$ProjectConfigIdentity)

    # Validate the prospective complete adoption using the existing version
    # validator. Copy only its declared project closure, with authorized changed
    # objects overlaid; unchanged objects must come from their actual live bytes.
    $stateRelative='.ai-workspace/upgrade-recovery/'+$Version+'/state.json'
    $stateEntry=@($Projection.objects|Where-Object{[string]$_.path-ceq$stateRelative})
    if($stateEntry.Count-ne1-or-not$stateEntry[0].newExists){throw 'ADOPTION_RECOVERY_STATE_PROJECTION_REQUIRED'}
    $tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    $stage=Join-Path $tempRoot ('aiw-adoption-recovery-'+[guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($stage)
    try {
        $stagedState=Get-AiwContainedPath $stage $stateRelative
        Write-AiwAtomicBytes $stagedState ([Convert]::FromBase64String($stateEntry[0].newBase64))
        $pilot=(Read-AiwProjectJson $stagedState 'ADOPTION_RECOVERY_PROJECTED_STATE').Value
        $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $null=$paths.Add('.ai-workspace/project.json')
        foreach($record in $pilot.projectionObjects){$null=$paths.Add([string]$record.relative)}
        foreach($entry in $Projection.objects){$null=$paths.Add([string]$entry.path)}
        $observed=@{}
        foreach($relative in $paths){
            $live=Get-AiwContainedPath $Root $relative
            $target=Get-AiwContainedPath $stage $relative
            $observed[$relative]=Get-AiwCurrentIdentity $live
            $entry=@($Projection.objects|Where-Object{[string]$_.path-ceq$relative})
            if($entry.Count-eq1){
                if($entry[0].kind-cne'FILE'){throw 'ADOPTION_RECOVERY_PROJECTED_KIND'}
                if($entry[0].newExists){Write-AiwAtomicBytes $target ([Convert]::FromBase64String($entry[0].newBase64))}
            }elseif(Test-Path -LiteralPath $live -PathType Leaf){
                Write-AiwAtomicBytes $target ([IO.File]::ReadAllBytes($live))
            }elseif(Test-Path -LiteralPath $live){
                throw ('ADOPTION_RECOVERY_PROJECTED_KIND|'+$relative)
            }
        }
        $null=Get-AiwLocalCandidateSupportBinding -ProjectRoot $stage -VersionDirectory $VersionRoot -Version $Version -ExpectedProjectConfigIdentity $ProjectConfigIdentity -ExpectedCandidatePilotStateIdentity ([string]$stateEntry[0].newIdentity)
        foreach($relative in $observed.Keys){
            if((Get-AiwCurrentIdentity (Get-AiwContainedPath $Root $relative))-cne$observed[$relative]){throw ('ADOPTION_RECOVERY_PREFLIGHT_DRIFT|'+$relative)}
        }
    } finally {
        $full=[IO.Path]::GetFullPath($stage)
        if(-not$full.StartsWith($tempRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-adoption-recovery-',[StringComparison]::Ordinal)){throw 'ADOPTION_RECOVERY_PREFLIGHT_CLEANUP_BOUNDARY'}
        [IO.Directory]::Delete($full,$true)
    }
}

function Resume-AiwRuntimeAdoption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ExpectedTransactionIdentity,
        [Parameter(Mandatory)][string]$AuthorizationPackagePath,
        [Parameter(Mandatory)][string]$ExpectedAuthorizationPackageIdentity,
        [Parameter(Mandatory)][string]$ObservedActor,
        [ValidateSet('COMPLETE','ROLLBACK')][string]$Direction='COMPLETE',
        [switch]$Apply
    )
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $relative='.ai-workspace/runtime/project-adoption/upgrade/state.json'
    $path=Get-AiwContainedPath $root $relative
    $doc=Read-AiwProjectJson $path 'ADOPTION_TRANSACTION'
    if($doc.Identity-cne$ExpectedTransactionIdentity){throw 'ADOPTION_TRANSACTION_DRIFT'}
    $state=$doc.Value;$metadata=$state.metadata
    if($state.schemaVersion-ne1-or[string]$state.repositoryRoot-cne$root-or[string]$state.transactionRelativePath-cne$relative-or[string]$metadata.operation-cne'UPGRADE_RUNTIME_REFRESH'){throw 'ADOPTION_TRANSACTION_BINDING'}
    $packageDoc=Read-AiwProjectJson $AuthorizationPackagePath 'ADOPTION_AUTHORIZATION';$package=$packageDoc.Value
    if($packageDoc.Identity-cne$ExpectedAuthorizationPackageIdentity-or$packageDoc.Identity-cne[string]$metadata.authorizationIdentity-or
       [int]$package.schemaVersion-ne3-or[string]$package.bundle-cne'ACTOR_BOUND_PROJECT_UPGRADE'-or[string]$package.grantee-cne$ObservedActor-or
       [string]$metadata.actor-cne$ObservedActor){throw 'ADOPTION_RECOVERY_AUTHORIZATION'}
    foreach($pair in @(@('.ai-workspace/project.json',$metadata.projectConfigIdentity),@('.ai-workspace/controller.json',$metadata.controllerIdentity),@([string]$metadata.taskPath,$metadata.taskIdentity))){
        if((Get-AiwCurrentIdentity (Get-AiwContainedPath $root $pair[0]))-cne[string]$pair[1]){throw ('ADOPTION_RECOVERY_CONTEXT_DRIFT|'+$pair[0])}
    }
    $null=Assert-AiwProjectionContract $root $state.projection
    $changed=@($state.projection.objects|Where-Object changed)
    if($changed.Count-ne@($package.exactPaths).Count){throw 'ADOPTION_RECOVERY_SCOPE'}
    foreach($entry in $changed){
        $pre=@($package.objectIdentities|Where-Object{[string]$_.path-ceq[string]$entry.path})
        $post=@($package.postObjectIdentities|Where-Object{[string]$_.path-ceq[string]$entry.path})
        $old=if($pre.Count-eq1-and[string]$pre[0].identity-ceq'NEW'){'MISSING'}elseif($pre.Count-eq1){[string]$pre[0].identity}else{''}
        $new=if($post.Count-eq1-and[string]$post[0].identity-ceq'ABSENT'){'MISSING'}elseif($post.Count-eq1){[string]$post[0].identity}else{''}
        if($old-cne[string]$entry.oldIdentity-or$new-cne[string]$entry.newIdentity-or[string]$entry.path-cnotin@($package.exactPaths)){throw 'ADOPTION_RECOVERY_PROJECTION_BINDING'}
        $live=Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path)
        if($live-cne$old-and$live-cne$new){throw ('ADOPTION_RECOVERY_THIRD_PARTY_OBJECT|'+$entry.path)}
    }
    if($state.transactionComplete){
        foreach($entry in $changed){
            $expected=if($state.state-ceq'COMPLETE'){$entry.newIdentity}else{$entry.oldIdentity}
            if((Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))-cne$expected){throw 'ADOPTION_RECOVERY_CLOSED_OBJECT_DRIFT'}
        }
        if($state.state-ceq'COMPLETE'-and$Direction-ceq'COMPLETE'){return [pscustomobject]@{status='COMPLETE';writes=0;transactionIdentity=$doc.Identity}}
        if($state.state-ceq'ROLLED_BACK'-and$Direction-ceq'ROLLBACK'){return [pscustomobject]@{status='ROLLED_BACK';writes=0;transactionIdentity=$doc.Identity}}
        throw 'ADOPTION_RECOVERY_TRANSACTION_ALREADY_CLOSED'
    }
    if(-not$Apply){return [pscustomobject]@{status='RECOVERY_REQUIRED';direction=$Direction;paths=@($changed.path);transactionIdentity=$doc.Identity}}
    if($Direction-ceq'ROLLBACK'){
        return Resume-AiwProjectProjectionRollback $root $relative $doc.Identity {param($r,$p) $true}
    }
    $binding=$metadata.distributionBinding
    if($null-eq$binding){throw 'ADOPTION_RECOVERY_DISTRIBUTION_REQUIRED'}
    $null=Assert-AiwDistributionBinding $binding ([string]$binding.runtimeRoot) ([string]$package.frameworkVersion)
    $versionRoot=Join-Path ([string]$binding.runtimeRoot) ('framework/versions/'+[string]$package.frameworkVersion)
    Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
    Assert-AiwRuntimeAdoptionProjection $root $state.projection $versionRoot ([string]$package.frameworkVersion) ([string]$metadata.projectConfigIdentity)
    if((Get-AiwCurrentIdentity $path)-cne$doc.Identity){throw 'ADOPTION_TRANSACTION_DRIFT'}
    $written=[Collections.Generic.List[object]]::new()
    $lastTransactionIdentity=$doc.Identity
    try {
        foreach($entry in $changed){
            $livePath=Get-AiwContainedPath $root $entry.path
            $live=Get-AiwCurrentIdentity $livePath
            if($live-cne$entry.oldIdentity-and$live-cne$entry.newIdentity){throw ('ADOPTION_RECOVERY_THIRD_PARTY_OBJECT|'+$entry.path)}
            if($live-cne$entry.newIdentity){
                if($entry.newExists){Write-AiwAtomicBytes $livePath ([Convert]::FromBase64String($entry.newBase64))}else{[IO.File]::Delete($livePath)}
                $written.Add($entry)
                if((Get-AiwCurrentIdentity $livePath)-cne$entry.newIdentity){throw ('ADOPTION_RECOVERY_POSTIMAGE|'+$entry.path)}
                if((Get-AiwCurrentIdentity $path)-cne$lastTransactionIdentity){throw 'ADOPTION_TRANSACTION_DRIFT'}
                $state.completedWrites++;Write-AiwTransactionState $path $state
                $lastTransactionIdentity=Get-AiwCurrentIdentity $path
            }
        }
        $null=Get-AiwLocalCandidateSupportBinding -ProjectRoot $root -VersionDirectory $versionRoot -Version ([string]$package.frameworkVersion) -ExpectedProjectConfigIdentity ([string]$metadata.projectConfigIdentity) -ExpectedCandidatePilotStateIdentity (Get-AiwCurrentIdentity (Join-Path $root (".ai-workspace/upgrade-recovery/"+[string]$package.frameworkVersion+"/state.json")))
        foreach($entry in $changed){
            if((Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))-cne$entry.newIdentity){throw ('ADOPTION_RECOVERY_POSTIMAGE|'+$entry.path)}
        }
        if((Get-AiwCurrentIdentity $path)-cne$lastTransactionIdentity){throw 'ADOPTION_TRANSACTION_DRIFT'}
        $state.state='COMPLETE';$state.transactionComplete=$true;Write-AiwTransactionState $path $state
    } catch {
        $failure=$_.Exception.Message
        $rollbackErrors=[Collections.Generic.List[string]]::new()
        # Undo only this invocation's writes. Keep earlier interrupted writes and
        # any third-party bytes; a conflict on one object must not suppress safe
        # compensation of the other objects.
        $undo=@($written.ToArray());[Array]::Reverse($undo)
        foreach($entry in $undo){
            try {
                $livePath=Get-AiwContainedPath $root $entry.path
                $live=Get-AiwCurrentIdentity $livePath
                if($live-ceq$entry.oldIdentity){continue}
                if($live-cne$entry.newIdentity){throw ('ROLLBACK_THIRD_PARTY_DRIFT|'+$entry.path)}
                if($entry.oldExists){Write-AiwAtomicBytes $livePath ([Convert]::FromBase64String($entry.oldBase64))}else{[IO.File]::Delete($livePath)}
                if((Get-AiwCurrentIdentity $livePath)-cne$entry.oldIdentity){throw ('ROLLBACK_POSTIMAGE_MISMATCH|'+$entry.path)}
            } catch {$rollbackErrors.Add($_.Exception.Message)}
        }
        if((Get-AiwCurrentIdentity $path)-cne$lastTransactionIdentity){$rollbackErrors.Add('ADOPTION_TRANSACTION_DRIFT')}
        if($rollbackErrors.Count-eq0){Write-AiwAtomicBytes $path $doc.Bytes}
        if($rollbackErrors.Count-gt0){throw ($failure+'|ADOPTION_RECOVERY_COMPENSATION_INCOMPLETE|'+[string]::Join(';',$rollbackErrors))}
        throw ($failure+'|ADOPTION_RECOVERY_RESUMED_WRITES_RESTORED')
    }
    return [pscustomobject]@{status='COMPLETE';transactionIdentity=Get-AiwCurrentIdentity $path;distributionBinding=$binding}
}
Export-ModuleMember -Function Resume-AiwRuntimeAdoption
