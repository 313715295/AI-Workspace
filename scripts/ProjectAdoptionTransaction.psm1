Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
$script:Utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-AiwBoundRuntimeActorStorageKey([string]$FrameworkRoot,[string]$Version,[string]$Actor) {
    if($Version-cnotmatch'^\d+\.\d+\.\d+$'){throw 'RUNTIME_ACTOR_VERSION'}
    $path=Get-AiwContainedPath $FrameworkRoot ('framework/versions/'+$Version+'/scripts/ProcessRequirementComposition.psm1')
    $module=@(Import-Module $path -Force -PassThru -ErrorAction Stop)[0]
    if([IO.Path]::GetFullPath($module.Path)-cne[IO.Path]::GetFullPath($path)){throw 'RUNTIME_ACTOR_MODULE_BINDING'}
    # Query this exact module's exports, never an ambient command left by another runtime.
    if($module.ExportedFunctions.ContainsKey('Get-AiwRuntimeActorStorageKey')){
        return & $module.ExportedFunctions['Get-AiwRuntimeActorStorageKey'] -Actor $Actor
    }
    # A prior runtime owns its original single-segment contract; do not relocate its evidence.
    if($Actor-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){throw 'RUNTIME_ACTOR_LEGACY_CONTEXT'}
    return $Actor
}
Export-ModuleMember -Function Get-AiwBoundRuntimeActorStorageKey

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
        [scriptblock]$RollbackPostcheck,
        [switch]$ReverseWriteOrder
    )

    $root = Assert-AiwProjectionContract $RepositoryRoot $Projection
    $changed = @($Projection.objects | Where-Object changed)
    $order=if($ReverseWriteOrder){$copy=@($changed);[Array]::Reverse($copy);$copy}else{Get-AiwRollbackOrder $changed}
    foreach ($entry in @($order)) {
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

function Assert-AiwProjectionTransactionPath {
    param([string]$RepositoryRoot,[string]$TransactionRelativePath)
    Assert-AiwRelativePath $TransactionRelativePath
    if((-not $TransactionRelativePath.StartsWith('.ai-workspace/upgrade-recovery/',[StringComparison]::Ordinal)-and
        -not $TransactionRelativePath.StartsWith('.ai-workspace/runtime/project-adoption/',[StringComparison]::Ordinal))-or
       -not $TransactionRelativePath.EndsWith('/state.json',[StringComparison]::Ordinal)){throw 'TRANSACTION_PATH_INVALID'}
    return Get-AiwContainedPath $RepositoryRoot $TransactionRelativePath
}
Export-ModuleMember -Function Assert-AiwProjectionTransactionPath

function Invoke-AiwProjectProjectionTransaction {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Projection,
        [Parameter(Mandatory)][string]$TransactionRelativePath,
        [Parameter(Mandatory)][scriptblock]$Postcheck,
        [Parameter(Mandatory)][scriptblock]$RollbackPostcheck,
        [int]$FailAfterWrite = -1,
        [int]$InterruptAfterWrite = -1,
        [int]$InterruptBeforeJournalWrite = -1,
        [scriptblock]$Preflight = { param($Root, $Candidate) $true },
        [hashtable]$Metadata = @{}
    )

    $root = Assert-AiwProjectionContract $RepositoryRoot $Projection
    $transactionPath = Assert-AiwProjectionTransactionPath $root $TransactionRelativePath

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
    if($InterruptAfterWrite-eq0){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=0}}

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
            if($InterruptBeforeJournalWrite-eq[int]$state.completedWrites){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
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
            if($InterruptBeforeJournalWrite-eq[int]$state.completedWrites){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
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
            $majorRollback=$Metadata.ContainsKey('operation')-and$Metadata.operation-ceq'UPGRADE_SNAPSHOT12_TO_2'
            if($majorRollback){$state.state='ROLLING_BACK';Write-AiwTransactionState $transactionPath $state}
            Restore-AiwProjectProjection $root $Projection @($createdDirectories) $RollbackPostcheck -ReverseWriteOrder:$majorRollback
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
    $transactionPath = Assert-AiwProjectionTransactionPath $root $TransactionRelativePath
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

    $majorRollback=$null-ne$state.metadata.PSObject.Properties['operation']-and$state.metadata.operation-ceq'UPGRADE_SNAPSHOT12_TO_2'
    if($majorRollback){$state.state='ROLLING_BACK';Write-AiwTransactionState $transactionPath $state}
    Restore-AiwProjectProjection $root $state.projection @($state.createdDirectories) $RollbackPostcheck -ReverseWriteOrder:$majorRollback
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
    if([string]$context.gitTop-cne'NOT_APPLICABLE'){
        $gitTop=@(& git -C $root rev-parse --show-toplevel 2>$null)
        if($LASTEXITCODE-ne0-or$gitTop.Count-ne1-or[IO.Path]::GetFullPath([string]$gitTop[0])-cne[IO.Path]::GetFullPath([string]$context.gitTop)){throw 'RULE_RECOVERY_GIT_TOP'}
    }
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
    if($null-ne$admit.PSObject.Properties['deliveryContext']){$material+=($admit.deliveryContext|ConvertTo-Json -Compress)}
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
        candidatePilotStateIdentity=(Join-Path $root ".ai-workspace/upgrade-recovery/$version/state.json")
    }
    # Only the original fixed-runtime receipt may bind its historical coverage file.
    if($null-ne$receipt.sourceBindings.PSObject.Properties['correctionCoverageIdentity']){$static.correctionCoverageIdentity=Join-Path $framework "framework/versions/$version/CORRECTION_COVERAGE.json"}
    foreach($name in $static.Keys){
        $actual=Get-AiwCurrentIdentity ([string]$static[$name])
        if($actual-cne[string]$receipt.sourceBindings.$name){throw ('RULE_RECOVERY_UNAUTHORIZED_SOURCE_DRIFT|'+$name)}
    }
    $originalDelivery=Get-AiwBoundaryDeliveryObservation $admit $framework $version
    if($null-ne$originalDelivery){
        if($null-eq$result.PSObject.Properties['delivery']){throw 'RULE_RECOVERY_ADMIT_DELIVERY_RESULT'}
        Assert-AiwAdoptionSame $originalDelivery $result.delivery 'RULE_RECOVERY_ADMIT_DELIVERY_RESULT'
    }elseif($null-ne$result.PSObject.Properties['delivery']){throw 'RULE_RECOVERY_ADMIT_DELIVERY_RESULT'}
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
    $actorStorage=Get-AiwBoundRuntimeActorStorageKey $framework $version $ObservedActor
    $runtime=Get-AiwContainedPath $root ('.ai-workspace/runtime/'+[string]$context.taskId+'/'+$actorStorage)
    [IO.Directory]::CreateDirectory($runtime)|Out-Null
    $finalInput=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=[string]$plan.discoverReceiptPath;expectedDiscoverReceiptIdentity=[string]$plan.discoverReceiptIdentity;preparationReceipts=@($plan.preparationReceipts)+@('BOOTSTRAP_PREIMAGE|'+[string]$bootstrapPreimage.preimagePath+'|'+[string]$bootstrapPreimage.preimageIdentity);resultReceipts=@($plan.resultReceipts);deliveryReceipts=@();publicDecisionIdentity=[string]$admit.publicDecisionIdentity;protectionState=[string]$admit.protectionState}
    $finalResolver=Join-Path $framework "framework/versions/$version/scripts/resolve-process-requirements.ps1"
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
    param([string]$Root,$Projection,[string]$VersionRoot,[string]$Version,[string]$ProjectConfigIdentity,$ExpectedPreparation,$OriginalReceipt)

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
        $null=$paths.Add('.ai-workspace/controller.json')
        foreach($record in $pilot.projectionObjects){$null=$paths.Add([string]$record.relative)}
        foreach($entry in $Projection.objects){$null=$paths.Add([string]$entry.path)}
        $observed=@{}
        foreach($relative in $paths){
            $live=Get-AiwContainedPath $Root $relative
            $target=Get-AiwContainedPath $stage $relative
            $observed[$relative]=Get-AiwCurrentIdentity $live
            $entry=@($Projection.objects|Where-Object{[string]$_.path-ceq$relative})
            # This prospective state was minted from the current admission, not
            # the historical installation. Bind unchanged AGENTS raw bytes only
            # for this pending transaction, including edits outside its block.
            if($relative-ceq'AGENTS.md'-and$entry.Count-eq0){
                $record=@($pilot.projectionObjects|Where-Object{[string]$_.relative-ceq$relative})
                if($record.Count-ne1-or$observed[$relative]-cne[string]$record[0].identity){throw ('ADOPTION_RECOVERY_UNCHANGED_OBJECT_DRIFT|'+$relative)}
            }
            if($entry.Count-eq1){
                if($entry[0].kind-cne'FILE'){throw 'ADOPTION_RECOVERY_PROJECTED_KIND'}
                if($entry[0].newExists){Write-AiwAtomicBytes $target ([Convert]::FromBase64String($entry[0].newBase64))}
            }elseif(Test-Path -LiteralPath $live -PathType Leaf){
                Write-AiwAtomicBytes $target ([IO.File]::ReadAllBytes($live))
            }elseif(Test-Path -LiteralPath $live){
                throw ('ADOPTION_RECOVERY_PROJECTED_KIND|'+$relative)
            }
        }
        $arguments=@{ProjectRoot=$stage;VersionDirectory=$VersionRoot;Version=$Version;ExpectedProjectConfigIdentity=$ProjectConfigIdentity;ExpectedCandidatePilotStateIdentity=[string]$stateEntry[0].newIdentity}
        if($Version-ceq'2.0.0'){$arguments.ProspectiveAdoptionProjection=$true}
        $null=Get-AiwLocalCandidateSupportBinding @arguments
        if($null-ne$ExpectedPreparation){
            $context=Get-AiwAdoptionProcessContext $OriginalReceipt
            $policy=(Read-AiwProjectJson (Get-AiwContainedPath $stage '.ai-workspace/process-policy.json') 'PROJECTED_POLICY').Value
            $closure=Get-AiwProjectPolicySourceClosure -ProjectRoot $Root -Rules @($policy.rules) -ForbiddenPaths @($context.forbiddenScope)
            foreach($document in $closure.Documents){
                if($document.locatorKind-ceq'PROJECT_RELATIVE'){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $document.relativePath) $document.bytes}
            }
            $composition=Get-AiwAdoptionComposition $stage $ExpectedPreparation.targetDistribution.runtimeRoot $OriginalReceipt -EvaluationOnly
            Assert-AiwAdoptionSame @($composition.selectedRequirements) @($ExpectedPreparation.selectedRuleBlocks) 'RECOVERY_TARGET_RULE_DRIFT'
            foreach($field in $ExpectedPreparation.projectedSourceBindings.PSObject.Properties){
                $actual=if($field.Name-ceq'taskIdentity'){Get-AiwCurrentIdentity (Get-AiwContainedPath $stage $OriginalReceipt.sourceLocators.taskRelativePath)}else{[string]$composition.($field.Name)}
                if($actual-cne[string]$field.Value){throw ('ADOPTION_PROCESS_SOURCE_DRIFT|'+$field.Name)}
            }
            foreach($document in $closure.Documents){if((Get-AiwCurrentIdentity $document.sourcePath)-cne$document.identity){throw 'ADOPTION_RECOVERY_EXTERNAL_SOURCE_DRIFT'}}
        }
        foreach($relative in $observed.Keys){
            if((Get-AiwCurrentIdentity (Get-AiwContainedPath $Root $relative))-cne$observed[$relative]){throw ('ADOPTION_RECOVERY_PREFLIGHT_DRIFT|'+$relative)}
        }
    } finally {
        $full=[IO.Path]::GetFullPath($stage)
        if(-not$full.StartsWith($tempRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-adoption-recovery-',[StringComparison]::Ordinal)){throw 'ADOPTION_RECOVERY_PREFLIGHT_CLEANUP_BOUNDARY'}
        [IO.Directory]::Delete($full,$true)
    }
}

Export-ModuleMember -Function Assert-AiwRuntimeAdoptionProjection
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
    $matches=@(foreach($candidate in @('.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
        $candidatePath=Get-AiwContainedPath $root $candidate
        if(Test-Path -LiteralPath $candidatePath -PathType Leaf){
            $candidateDoc=Read-AiwProjectJson $candidatePath 'ADOPTION_TRANSACTION'
            if($candidateDoc.Identity-ceq$ExpectedTransactionIdentity){[pscustomobject]@{relative=$candidate;document=$candidateDoc}}
        }
    })
    if($matches.Count-ne1){throw 'ADOPTION_TRANSACTION_DRIFT'}
    $relative=$matches[0].relative;$doc=$matches[0].document;$path=$doc.Path
    $state=$doc.Value;$metadata=$state.metadata
    if($state.schemaVersion-ne1-or[string]$state.repositoryRoot-cne$root-or[string]$state.transactionRelativePath-cne$relative-or[string]$metadata.operation-cnotin@('UPGRADE_RUNTIME_REFRESH','UPGRADE_SNAPSHOT12_TO_2')){throw 'ADOPTION_TRANSACTION_BINDING'}
    if($state.transactionComplete-isnot[bool]-or($state.completedWrites-isnot[int]-and$state.completedWrites-isnot[long])-or$state.completedWrites-lt0){throw 'ADOPTION_TRANSACTION_STATE_SCHEMA'}
    if($state.transactionComplete-and$state.state-cnotin@('COMPLETE','ROLLED_BACK')){throw 'ADOPTION_TRANSACTION_STATE_SCHEMA'}
    $major=$metadata.operation-ceq'UPGRADE_SNAPSHOT12_TO_2'
    if($major-and$relative-cne'.ai-workspace/runtime/project-adoption/upgrade/state.json'){throw 'ADOPTION_TRANSACTION_BINDING'}
    $packageDoc=Read-AiwProjectJson $AuthorizationPackagePath 'ADOPTION_AUTHORIZATION';$package=$packageDoc.Value
    if($packageDoc.Identity-cne$ExpectedAuthorizationPackageIdentity-or$packageDoc.Identity-cne[string]$metadata.authorizationIdentity-or
       [int]$package.schemaVersion-ne3-or[string]$package.bundle-cne'ACTOR_BOUND_PROJECT_UPGRADE'-or[string]$package.grantee-cne$ObservedActor-or
       [string]$metadata.actor-cne$ObservedActor){throw 'ADOPTION_RECOVERY_AUTHORIZATION'}
    $null=Assert-AiwProjectionContract $root $state.projection
    if($major){
        if($package.frameworkVersion-cne'2.0.0'-or(Get-AiwAdoptionTargetVersion $state.projection)-cne'2.0.0'){throw 'ADOPTION_PROCESS_VERSION_PAIR'}
        Assert-AiwMajorAdoptionProjection $state.projection $metadata.originalContext $metadata.taskPath $metadata.previousDistribution
        $null=Assert-AiwDistributionBinding $metadata.previousDistribution $metadata.previousDistribution.runtimeRoot '1.16.0'
        $admitBytes=[Convert]::FromBase64String($metadata.originalAdmitBase64)
        if((Get-AiwByteIdentity $admitBytes)-cne$metadata.originalAdmitIdentity){throw 'ADOPTION_RECOVERY_ORIGINAL_ADMIT_DRIFT'}
        $proof=Get-AiwMajorAdoptionAdmission ([pscustomobject]@{Value=($script:Utf8NoBom.GetString($admitBytes)|ConvertFrom-Json -Depth 100)}) $root
        Assert-AiwAdoptionSame $proof.preparation.projection $state.projection 'RECOVERY_PROJECTION'
        Assert-AiwAdoptionSame $proof.context $metadata.originalContext 'RECOVERY_CONTEXT'
        Assert-AiwAdoptionSame $proof.preparation.targetDistribution $metadata.distributionBinding 'RECOVERY_DISTRIBUTION'
        $null=Assert-AiwDistributionBinding $metadata.distributionBinding $metadata.distributionBinding.runtimeRoot '2.0.0'
        $targetStateEntry=@($state.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'})[0]
        $targetState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($targetStateEntry.newBase64))|ConvertFrom-Json -Depth 100
        Assert-AiwMajorUpgradeAuthorization $package $proof ([pscustomobject]@{canonical=$targetState.targetReleaseCanonical;manifestIdentity=$targetState.targetReleaseManifestIdentity})
    }
    foreach($pair in @(@('.ai-workspace/project.json',$metadata.projectConfigIdentity),@('.ai-workspace/controller.json',$metadata.controllerIdentity),@([string]$metadata.taskPath,$metadata.taskIdentity))){
        $accepted=@([string]$pair[1]);$projected=@($state.projection.objects|Where-Object{$_.path-ceq$pair[0]})
        if($major-and$projected.Count-eq1){
            if($projected[0].oldIdentity-cne$pair[1]){throw 'ADOPTION_RECOVERY_CONTEXT_PREIMAGE'}
            $accepted+=[string]$projected[0].newIdentity
        }
        if((Get-AiwCurrentIdentity (Get-AiwContainedPath $root $pair[0]))-cnotin$accepted){throw ('ADOPTION_RECOVERY_CONTEXT_DRIFT|'+$pair[0])}
    }
    $changed=@($state.projection.objects|Where-Object changed)
    if($state.completedWrites-gt$changed.Count){throw 'ADOPTION_TRANSACTION_STATE_SCHEMA'}
    if(@($state.projection.objects).Count-ne@($package.exactPaths).Count){throw 'ADOPTION_RECOVERY_SCOPE'}
    foreach($entry in $state.projection.objects){
        $pre=@($package.objectIdentities|Where-Object{[string]$_.path-ceq[string]$entry.path})
        $post=@($package.postObjectIdentities|Where-Object{[string]$_.path-ceq[string]$entry.path})
        $old=if($pre.Count-eq1-and[string]$pre[0].identity-ceq'NEW'){'MISSING'}elseif($pre.Count-eq1){[string]$pre[0].identity}else{''}
        $new=if($post.Count-eq1-and[string]$post[0].identity-ceq'ABSENT'){'MISSING'}elseif($post.Count-eq1){[string]$post[0].identity}else{''}
        if($old-cne[string]$entry.oldIdentity-or$new-cne[string]$entry.newIdentity-or[string]$entry.path-cnotin@($package.exactPaths)){throw 'ADOPTION_RECOVERY_PROJECTION_BINDING'}
        $live=Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path)
        if($live-cne$old-and$live-cne$new){throw ('ADOPTION_RECOVERY_THIRD_PARTY_OBJECT|'+$entry.path)}
    }
    if($major-and-not$state.transactionComplete){
        # An interrupted sequential apply has exactly one new-image prefix.
        # A crash between the object rename and journal rename permits one
        # additional write; no other old/new combination is reachable.
        $prefix=0;$oldSeen=$false
        foreach($entry in $changed){
            $new=(Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))-ceq$entry.newIdentity
            if($new-and$oldSeen){throw 'ADOPTION_RECOVERY_UNREACHABLE_STATE'}
            if($new){$prefix++}else{$oldSeen=$true}
        }
        if($state.state-cnotin@('APPLYING','ROLLING_BACK','ROLLBACK_BLOCKED')-or$state.completedWrites-lt0-or$state.completedWrites-gt$changed.Count-or
           ($state.state-ceq'APPLYING'-and$prefix-cnotin@([int]$state.completedWrites,([int]$state.completedWrites+1)))-or
           ($state.state-cin@('ROLLING_BACK','ROLLBACK_BLOCKED')-and($prefix-gt([int]$state.completedWrites+1)-or$Direction-cne'ROLLBACK'))){throw 'ADOPTION_RECOVERY_UNREACHABLE_STATE'}
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
    $projectIdentity=[string]$metadata.projectConfigIdentity
    if($major){$projectIdentity=[string](@($state.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})[0].newIdentity)}
    $preparation=$null;$originalReceipt=$null
    if($major){$preparation=$proof.preparation;$originalReceipt=$proof.receipt}
    Assert-AiwRuntimeAdoptionProjection $root $state.projection $versionRoot ([string]$package.frameworkVersion) $projectIdentity $preparation $originalReceipt
    if((Get-AiwCurrentIdentity $path)-cne$doc.Identity){throw 'ADOPTION_TRANSACTION_DRIFT'}
    $written=[Collections.Generic.List[object]]::new()
    $lastTransactionIdentity=$doc.Identity
    try {
        $completed=0
        foreach($entry in $changed){
            $completed++
            $livePath=Get-AiwContainedPath $root $entry.path
            $live=Get-AiwCurrentIdentity $livePath
            if($live-cne$entry.oldIdentity-and$live-cne$entry.newIdentity){throw ('ADOPTION_RECOVERY_THIRD_PARTY_OBJECT|'+$entry.path)}
            if($live-cne$entry.newIdentity){
                if($entry.newExists){Write-AiwAtomicBytes $livePath ([Convert]::FromBase64String($entry.newBase64))}else{[IO.File]::Delete($livePath)}
                $written.Add($entry)
                if((Get-AiwCurrentIdentity $livePath)-cne$entry.newIdentity){throw ('ADOPTION_RECOVERY_POSTIMAGE|'+$entry.path)}
                if((Get-AiwCurrentIdentity $path)-cne$lastTransactionIdentity){throw 'ADOPTION_TRANSACTION_DRIFT'}
                $state.completedWrites=$completed;Write-AiwTransactionState $path $state
                $lastTransactionIdentity=Get-AiwCurrentIdentity $path
            }
        }
        $state.completedWrites=$changed.Count
        Assert-AiwRuntimeAdoptionProjection $root $state.projection $versionRoot ([string]$package.frameworkVersion) $projectIdentity $preparation $originalReceipt
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

# Prospective closeout for one named-runtime refresh. The existing upgrade plan
# supplies the projection; the version composer remains the only rule selector.
function Assert-AiwAdoptionSame($Left,$Right,[string]$Label) {
    if(($Left|ConvertTo-Json -Depth 100 -Compress)-cne($Right|ConvertTo-Json -Depth 100 -Compress)){throw ('ADOPTION_PROCESS_'+$Label)}
}
function Get-AiwBoundaryDeliveryObservation($Boundary,[string]$FrameworkRoot,[string]$Version='1.16.0') {
    if($null-eq$Boundary.PSObject.Properties['deliveryContext']){return $null}
    Import-Module (Join-Path $FrameworkRoot ('framework/versions/'+$Version+'/scripts/ProcessRequirementComposition.psm1')) -Force
    $observation=Get-AiwDeliveryObservation $Boundary.deliveryContext
    if($Boundary.deliveryContext.stage-ceq'PREPARE'-and@($Boundary.deliveryReceipts).Count){throw 'DELIVERY_FUTURE_EVIDENCE'}
    return $observation
}
Export-ModuleMember -Function Get-AiwBoundaryDeliveryObservation
function Read-AiwAdoptionEvidence([string]$Path,[string]$Identity,[string]$Label) {
    if([string]::IsNullOrWhiteSpace($Path)-or$Identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('ADOPTION_PROCESS_EVIDENCE_REQUIRED|'+$Label)}
    $doc=Read-AiwProjectJson $Path $Label
    if($doc.Identity-cne$Identity){throw ('ADOPTION_PROCESS_EVIDENCE_DRIFT|'+$Label)}
    return $doc
}
function Get-AiwAdoptionProcessPackage($Receipt,$Context,[string]$Root) {
    $doc=Read-AiwAdoptionEvidence $Receipt.sourceLocators.authorizationPackagePath $Context.authorizationIdentity 'PROCESS_PACKAGE'
    $pkg=$doc.Value
    $config=(Read-AiwProjectJson (Get-AiwContainedPath $Root '.ai-workspace/project.json') 'PROJECT').Value
    $maintenance=$null-ne$config.PSObject.Properties['controlPlaneLayout']-and$config.controlPlaneLayout-ceq'framework-maintenance-sibling'
    if($pkg.schemaVersion-notin@(1,2)-or($maintenance-and$pkg.schemaVersion-ne2)-or
       $pkg.grantee-cne$Context.actor-or$pkg.owner-cne$Context.taskOwner-or$pkg.taskIdentity-cne$Context.taskIdentity-or
       $pkg.taskId-cne$Context.taskId-or$pkg.projectConfigIdentity-cne$Receipt.sourceBindings.projectConfigIdentity-or
       $pkg.userConfirmation-cne$Context.userDecision-or$null-ne$pkg.PSObject.Properties['continuationPlan']){throw 'ADOPTION_PROCESS_PACKAGE_BINDING'}
    Assert-AiwAdoptionSame @($pkg.actions) @('CONTROL_WRITE') 'PACKAGE_ACTION'
    Assert-AiwAdoptionSame @($pkg.exactPaths|Sort-Object) @($Context.exactScope|Sort-Object) 'PACKAGE_SCOPE'
    return $doc
}
function Get-AiwAdoptionProcessContext($Receipt) {
    if(($Receipt.schemaVersion-eq1-and$Receipt.inputContractVersion-eq2)){$c=$Receipt.authorityContext}
    elseif($Receipt.schemaVersion-eq2-and$Receipt.inputContractVersion-eq3){$c=$Receipt.binding}
    else{throw 'ADOPTION_PROCESS_RECEIPT_LAYOUT'}
    if($Receipt.status-cne'PASS'-or$Receipt.mode-cne'DISCOVER'-or$Receipt.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or$Receipt.authorityGranted-ne$false-or$Receipt.semanticCorrectnessProven-ne$false){throw 'ADOPTION_PROCESS_RECEIPT_CONTRACT'}
    $intent=$Receipt.intentEnvelope
    $hash=Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes(($c|ConvertTo-Json -Depth 30 -Compress)+"`n"+($intent|ConvertTo-Json -Depth 30 -Compress)))
    if($hash.Split('|')[1]-cne$Receipt.contextIdentity){throw 'ADOPTION_PROCESS_CONTEXT_IDENTITY'}
    if($Receipt.schemaVersion-eq1){
        # Legacy authorityContext omits these task labels. Normalize a private
        # view only, after hashing the original context; never mutate the receipt.
        $c=$c|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $c|Add-Member -NotePropertyName taskId -NotePropertyValue ([string]$Receipt.taskId)
        $c|Add-Member -NotePropertyName taskOwner -NotePropertyValue ([string]$Receipt.taskOwner)
    }
    $sourceVersion=[string]$c.frameworkVersion
    if($sourceVersion-cnotin@('1.16.0','2.0.0')){throw 'ADOPTION_PROCESS_VERSION_PAIR'}
    $sourceState='.ai-workspace/upgrade-recovery/'+$sourceVersion+'/state.json'
    $allowed=@('AGENTS.md','.ai-workspace/BOOTSTRAP.md',$sourceState)
    if($sourceVersion-ceq'2.0.0'){$allowed+=@('.ai-workspace/process-policy.json','.ai-workspace/corrections.json')}
    $correctionPaths=@($c.exactScope|Where-Object{$_-ceq'.ai-workspace/corrections.json'-or$_-cmatch'^\.ai-workspace/upgrade-recovery/corrections/[A-Z][A-Z0-9_]*/[A-Za-z0-9._-]+/history\.json$'})
    if($correctionPaths.Count-and'.ai-workspace/corrections.json'-cnotin$correctionPaths){throw 'ADOPTION_PROCESS_CORRECTION_SCOPE'}
    # The major pair is validated against the actual projection and named old
    # distribution below. A receipt alone cannot widen the allowed write set.
    $major=$sourceVersion-ceq'1.16.0'-and'.ai-workspace/upgrade-recovery/2.0.0/state.json'-cin@($c.exactScope)
    if($intent.requestedActionKind-cne'CONTROL_WRITE'-or$intent.ambiguityState-cne'CLEAR'-or'CONTROL_WRITE'-cnotin@($c.authorizedActions)-or@($c.exactScope).Count-eq0-or(-not$major-and@($c.exactScope|Where-Object{$_-cnotin$allowed-and$_-cnotin$correctionPaths}).Count-ne0)-or$sourceState-cnotin@($c.exactScope)){throw 'ADOPTION_PROCESS_CONTEXT_SCOPE'}
    return $c
}
function Get-AiwAdoptionTargetVersion($Projection) {
    $entries=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})
    if($entries.Count-eq0){return '1.16.0'}
    if($entries.Count-ne1-or-not$entries[0].oldExists-or-not$entries[0].newExists){throw 'ADOPTION_PROCESS_PROJECT_PROJECTION'}
    $old=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entries[0].oldBase64))|ConvertFrom-Json -Depth 100
    $new=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entries[0].newBase64))|ConvertFrom-Json -Depth 100
    if($old.frameworkVersion-cne'1.16.0'-or$old.schemaVersion-ne4-or$new.frameworkVersion-cne'2.0.0'-or$new.schemaVersion-ne5-or
       $old.id-cne$new.id-or$old.controlPlaneLayout-cne$new.controlPlaneLayout-or$old.repositoryRoot-cne$new.repositoryRoot-or
       $old.frameworkToolBackend-cne$new.frameworkToolBackend){throw 'ADOPTION_PROCESS_VERSION_PAIR'}
    Assert-AiwAdoptionSame @($old.routineExcludedPaths) @($new.routineExcludedPaths) 'PROTECTED_PATHS'
    if($old.controlPlaneLayout-ceq'framework-maintenance-sibling'){
        Assert-AiwAdoptionSame $old.frameworkTarget $new.frameworkTarget 'MAINTENANCE_TARGET'
    }
    return '2.0.0'
}
function Assert-AiwMajorAdoptionProjection($Projection,$Context,[string]$TaskRelativePath,$PreviousDistribution) {
    if((Get-AiwAdoptionTargetVersion $Projection)-cne'2.0.0'-or$PreviousDistribution.distributionId-cne'1.16.0-snapshot.12'){throw 'ADOPTION_PROCESS_VERSION_PAIR'}
    $required=@('.ai-workspace/project.json','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','AGENTS.md','.ai-workspace/BOOTSTRAP.md',
        '.ai-workspace/upgrade-recovery/1.16.0/state.json','.ai-workspace/upgrade-recovery/2.0.0/state.json',$TaskRelativePath)
    $configEntry=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})[0]
    $old=$script:Utf8NoBom.GetString([Convert]::FromBase64String($configEntry.oldBase64))|ConvertFrom-Json -Depth 100
    $allowed=@($required)
    if($null-ne$old.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']){
        $knowledge=$old.frameworkCapabilities.KNOWLEDGE_REFERENCE
        if($null-ne$knowledge.PSObject.Properties['indexLocator']){$allowed+=[string]$knowledge.indexLocator}
    }
    foreach($path in $required){if(@($Projection.objects|Where-Object{$_.path-ceq$path}).Count-ne1){throw ('ADOPTION_PROCESS_MAJOR_OBJECT_REQUIRED|'+$path)}}
    foreach($entry in $Projection.objects){
        if($entry.path-cnotin$allowed-or$entry.kind-cne'FILE'-or-not$entry.newExists){throw ('ADOPTION_PROCESS_MAJOR_SCOPE|'+$entry.path)}
        foreach($forbidden in @($Context.forbiddenScope)+@($old.routineExcludedPaths)){
            if($entry.path.Equals($forbidden,[StringComparison]::OrdinalIgnoreCase)-or$entry.path.StartsWith($forbidden.TrimEnd('/')+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'ADOPTION_PROCESS_PROTECTED_PROJECTION'}
        }
    }
    $changed=@($Projection.objects|Where-Object changed)
    if($changed.Count-lt3-or$changed[0].path-cne'.ai-workspace/upgrade-recovery/1.16.0/state.json'-or$changed[-1].path-cne$TaskRelativePath){throw 'ADOPTION_PROCESS_MAJOR_WRITE_ORDER'}
    $link=[ordered]@{fromVersion='1.16.0';fromDistributionId='1.16.0-snapshot.12';toVersion='2.0.0';transactionRelativePath='.ai-workspace/runtime/project-adoption/upgrade/state.json'}
    foreach($version in @('1.16.0','2.0.0')){
        $entry=@($Projection.objects|Where-Object{$_.path-ceq('.ai-workspace/upgrade-recovery/'+$version+'/state.json')})[0]
        $state=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entry.newBase64))|ConvertFrom-Json -Depth 100
        if($null-eq$state.PSObject.Properties['majorTransition']){throw 'ADOPTION_PROCESS_MAJOR_RECOVERY_LINK'}
        Assert-AiwAdoptionSame $state.majorTransition $link 'MAJOR_RECOVERY_LINK'
        if($version-ceq'1.16.0'){
            $prior=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entry.oldBase64))|ConvertFrom-Json -Depth 100
            Assert-AiwAdoptionSame $prior.distributionBinding $PreviousDistribution 'OLD_DISTRIBUTION'
            $state.PSObject.Properties.Remove('majorTransition')
            Assert-AiwAdoptionSame $state $prior 'OLD_STATE_PRESERVED'
        }elseif($entry.oldExists-or$state.schemaVersion-ne6-or$state.fromVersion-cne'1.16.0'-or$state.toVersion-cne'2.0.0'-or$state.transactionComplete-ne$true){throw 'ADOPTION_PROCESS_MAJOR_TARGET_STATE'}
    }
}
function Get-AiwAdoptionComposition([string]$Root,[string]$Runtime,$Receipt,[switch]$EvaluationOnly) {
    $c=Get-AiwAdoptionProcessContext $Receipt
    $config=(Read-AiwProjectJson (Get-AiwContainedPath $Root '.ai-workspace/project.json') 'PROJECT').Value
    $version=[string]$config.frameworkVersion
    if($version-cnotin@('1.16.0','2.0.0')){throw 'ADOPTION_PROCESS_TARGET_VERSION'}
    $role=[string]$c.role;$taskIdentity=[string]$c.taskIdentity;$capabilities=@($c.observedCapabilities)
    if($version-ceq'2.0.0'){
        $task=Get-AiwContainedPath $Root $Receipt.sourceLocators.taskRelativePath
        $text=[IO.File]::ReadAllText($task)
        $route=[regex]::Matches($text,'(?m)^- Work route: actor=(?<actor>[^;\s]+); role=(?<role>CONTROLLER|TASK_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER); phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
        $owner=[regex]::Matches($text,'(?m)^- Owner:\s*`?(?<owner>[^`\r\n]+?)`?\s*$')
        $header=[regex]::Matches($text,'(?m)^#\s+(?<id>[0-9A-Za-z][0-9A-Za-z._-]*)\s+[-—]')
        $range=[regex]::Matches($text,'(?m)^- Range summary: profile=(?<profile>MICRO|STANDARD|CRITICAL); lifecycle=ACTIVE;')
        $expectedRole=if($c.role-ceq'DOMAIN_OWNER'){'TASK_OWNER'}else{[string]$c.role}
        if($route.Count-ne1-or$owner.Count-ne1-or$header.Count-ne1-or$header[0].Groups['id'].Value-cne$c.taskId-or$range.Count-ne1-or$range[0].Groups['profile'].Value-cne$c.profile-or$owner[0].Groups['owner'].Value-cne$c.taskOwner-or
           $route[0].Groups['actor'].Value-cne$c.actor-or$route[0].Groups['phase'].Value-cne$c.phase-or$route[0].Groups['role'].Value-cne$expectedRole-or
           [regex]::Matches($text,'(?m)^- Task schema: 2\.0\.0\s*$').Count-ne1){throw 'ADOPTION_PROCESS_TARGET_TASK_BINDING'}
        $role=$expectedRole;$taskIdentity=Get-AiwCurrentIdentity $task
        $capabilities=@($config.frameworkCapabilities.PSObject.Properties|Where-Object{$_.Value.enabled-eq$true}|ForEach-Object{$_.Name})
        Import-Module (Join-Path $Runtime 'framework/versions/2.0.0/scripts/ResultEvidence.psm1') -Force
        $null=Get-AiwAcceptancePlan $text
    }
    Import-Module (Join-Path $Runtime ('framework/versions/'+$version+'/scripts/ProcessRequirementComposition.psm1')) -Force
    $result=Invoke-ProcessRequirementComposition -ProjectRoot $Root -FrameworkRoot $Runtime -TargetVersion $version -ExpectedProjectConfigIdentity (Get-AiwCurrentIdentity (Get-AiwContainedPath $Root '.ai-workspace/project.json')) -ExpectedCorrectionsIdentity (Get-AiwCurrentIdentity (Get-AiwContainedPath $Root '.ai-workspace/corrections.json')) -Profile $c.profile -Role $role -Phase $c.phase -Actor $c.actor -TaskIdentity $taskIdentity -Capabilities $capabilities -Objective (Get-AiwProcessSemanticText $Receipt.intentEnvelope) -ActionKind 'CONTROL_WRITE' -ResultKind $Receipt.intentEnvelope.requestedResultKind -ExactPaths @($c.exactScope) -ForbiddenPaths @($c.forbiddenScope) -EvaluationOnly:$EvaluationOnly
    if($version-ceq'2.0.0'){
        $prefix=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))+[IO.Path]::DirectorySeparatorChar
        foreach($block in $result.selectedRequirements){foreach($part in $block.displayParts){
            if($part.sourceLocator.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$part.sourceLocator='PROJECT_RELATIVE:'+([IO.Path]::GetRelativePath($Root,$part.sourceLocator).Replace('\','/'))}
        }}
    }
    $size=$script:Utf8NoBom.GetByteCount((@($result.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress))
    # Measured bytes are observational; source and adoption proofs remain mandatory.
    return $result
}
function Get-AiwMajorAdoptionAdmission($AdmitDocument,[string]$Root,[switch]$VerifyCurrent) {
    $ad=$AdmitDocument.Value
    if($null-eq$ad.PSObject.Properties['originalAdmissionInput']-or$null-eq$ad.PSObject.Properties['adoptionPreparation']){throw 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED'}
    $a=$ad.originalAdmissionInput;$p=$ad.adoptionPreparation
    $rd=Read-AiwAdoptionEvidence $a.discoverReceiptPath $a.expectedDiscoverReceiptIdentity 'DISCOVER'
    $r=$rd.Value;$c=Get-AiwAdoptionProcessContext $r
    if((Resolve-AiwRepositoryRoot $c.projectRoot)-cne(Resolve-AiwRepositoryRoot $Root)){throw 'ADOPTION_PROCESS_ACTOR_ROOT'}
    if($ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or$a.mode-cne'ADMIT_ACTION'-or$a.schemaVersion-ne2-or
       $ad.selectionIdentity-cne$r.selectionIdentity-or$ad.authorityGranted-ne$false-or$ad.semanticCorrectnessProven-ne$false-or
       @($ad.missingPreparation).Count-or@($ad.missingResult).Count-or$p.discoverReceiptIdentity-cne$rd.Identity-or$a.protectionState-cne'BOUND'){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
    $bytes=[Convert]::FromBase64String($ad.adoptionPreparationBase64)
    if((Get-AiwByteIdentity $bytes)-cne$ad.adoptionPreparationIdentity){throw 'ADOPTION_PROCESS_PREPARATION_IDENTITY'}
    Assert-AiwAdoptionSame ($script:Utf8NoBom.GetString($bytes)|ConvertFrom-Json -Depth 100) $p 'PREPARATION_CONTENT'
    Assert-AiwMajorAdoptionProjection $p.projection $c $r.sourceLocators.taskRelativePath $p.previousDistribution
    foreach($field in $r.sourceBindings.PSObject.Properties){
        if($null-eq$p.oldSourceBindings.PSObject.Properties[$field.Name]-or[string]$p.oldSourceBindings.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}
    }
    $material=@($r.sourceCompositionIdentity,$r.selectionIdentity,$r.contextIdentity,'ADMIT_ACTION',$r.intentEnvelope.objective,'CONTROL_WRITE',$r.intentEnvelope.requestedResultKind,[string]::Join(',',@($c.exactScope)),$c.authorizationIdentity,[string]::Join(',',@($a.preparationReceipts)),[string]::Join(',',@($a.resultReceipts)),[string]::Join(',',@($a.deliveryReceipts)),$a.publicDecisionIdentity,$a.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join"`n"
    if($null-ne$a.PSObject.Properties['deliveryContext']){$material+=($a.deliveryContext|ConvertTo-Json -Compress)}
    if((Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes($material))).Split('|')[1]-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
    $required=@(@($r.selectedObligations|ForEach-Object{$_.preparationRequirements})+@($p.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements})|Sort-Object -Unique)
    if(@($required|Where-Object{$_-cnotin@($a.preparationReceipts)}).Count-or('ADOPTION_TARGET_RULES_LOADED|'+$ad.adoptionPreparationIdentity)-cnotin@($a.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
    $pkg=Get-AiwAdoptionProcessPackage $r $c $Root
    if($pkg.Value.issuerRole-cne'PROJECT_CONTROLLER'-or$pkg.Value.profile-cne'CRITICAL'-or$pkg.Value.decisionClass-cne'MAJOR_ARCHITECTURE'-or$pkg.Value.delegatedGitCloser-ne$false){throw 'ADOPTION_PROCESS_MAJOR_AUTHORITY'}
    if($VerifyCurrent){
        $current=New-AiwAdoptionProcessPreparation -RepositoryRoot $Root -TargetRuntimeRoot $p.targetDistribution.runtimeRoot -Projection $p.projection -ObservedActor $c.actor -OriginalBoundary $a
        Assert-AiwAdoptionSame $current $p 'PREPARATION_DRIFT'
    }
    return [pscustomobject]@{admission=$ad;receipt=$r;context=$c;preparation=$p;package=$pkg.Value}
}
function Assert-AiwMajorUpgradeAuthorization($Package,$Proof,$Snapshot) {
    # A closed schema-3 projection of the already admitted CONTROL package.
    # No changed issuer, decision, actor, task, scope or preimage is permitted.
    $expected=$Proof.package|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
    $expected.PSObject.Properties.Remove('repositoryId')
    $expected.schemaVersion=3;$expected.frameworkVersion='2.0.0';$expected.bundle='ACTOR_BOUND_PROJECT_UPGRADE'
    $expected.invalidatesOn=@($expected.invalidatesOn|Where-Object{$_-cne'REPOSITORY_CHANGE'})+@('POST_OBJECT_DRIFT')
    $expected|Add-Member postObjectIdentities @($Proof.preparation.projection.objects|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$_.newIdentity}})
    $expected|Add-Member targetFrameworkSnapshot ([pscustomobject]@{canonical=$Snapshot.canonical;manifestIdentity=$Snapshot.manifestIdentity})
    # Compare closed fields and set-valued scope independently of JSON member order.
    Assert-AiwAdoptionSame @($Package.PSObject.Properties.Name|Sort-Object) @($expected.PSObject.Properties.Name|Sort-Object) 'MAJOR_PACKAGE_FIELDS'
    foreach($field in $expected.PSObject.Properties.Name){
        if($field-cin@('exactPaths','invalidatesOn')){Assert-AiwAdoptionSame @($Package.$field|Sort-Object) @($expected.$field|Sort-Object) ('MAJOR_PACKAGE_'+$field)}
        elseif($field-cin@('objectIdentities','postObjectIdentities')){Assert-AiwAdoptionSame @($Package.$field|Sort-Object path) @($expected.$field|Sort-Object path) ('MAJOR_PACKAGE_'+$field)}
        elseif($field-ceq'targetFrameworkSnapshot'){
            $actual=$Package.$field;$wanted=$expected.$field
            if($actual-isnot[pscustomobject]){throw ('ADOPTION_PROCESS_MAJOR_PACKAGE_'+$field)}
            Assert-AiwAdoptionSame @($actual.PSObject.Properties.Name|Sort-Object) @($wanted.PSObject.Properties.Name|Sort-Object) ('MAJOR_PACKAGE_'+$field)
            foreach($member in $wanted.PSObject.Properties.Name){
                if($actual.$member-isnot[string]-or$wanted.$member-isnot[string]){throw ('ADOPTION_PROCESS_MAJOR_PACKAGE_'+$field)}
                Assert-AiwAdoptionSame $actual.$member $wanted.$member ('MAJOR_PACKAGE_'+$field)
            }
        }
        else{Assert-AiwAdoptionSame $Package.$field $expected.$field ('MAJOR_PACKAGE_'+$field)}
    }
}
Export-ModuleMember -Function Get-AiwMajorAdoptionAdmission,Assert-AiwMajorUpgradeAuthorization,Get-AiwAdoptionTargetVersion,Assert-AiwMajorAdoptionProjection,Assert-AiwAdoptionSame,Assert-AiwProjectionContract
function New-AiwAdoptionProcessPreparation {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[string]$InputPath,[string]$ExpectedInputIdentity,[string]$TargetRuntimeRoot,$Projection,[string]$ObservedActor,$OriginalBoundary)
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    if($null-ne$OriginalBoundary){$boundary=$OriginalBoundary}else{$inputDoc=Read-AiwAdoptionEvidence $InputPath $ExpectedInputIdentity 'PREPARE_INPUT';$boundary=$inputDoc.Value}
    if($boundary.schemaVersion-ne2-or$boundary.mode-cne'ADMIT_ACTION'){throw 'ADOPTION_PROCESS_PREPARE_INPUT'}
    $receiptDoc=Read-AiwAdoptionEvidence $boundary.discoverReceiptPath $boundary.expectedDiscoverReceiptIdentity 'DISCOVER';$receipt=$receiptDoc.Value
    $c=Get-AiwAdoptionProcessContext $receipt
    if((Resolve-AiwRepositoryRoot $c.projectRoot)-cne$root-or$c.actor-cne$ObservedActor){throw 'ADOPTION_PROCESS_ACTOR_ROOT'}
    $null=Assert-AiwProjectionContract $root $Projection
    $null=Get-AiwAdoptionProcessPackage $receipt $c $root
    Assert-AiwAdoptionSame @($Projection.objects.path|Sort-Object) @($c.exactScope|Sort-Object) 'PROJECTION_SCOPE'
    $sourceVersion=[string]$c.frameworkVersion
    $targetVersion=if($sourceVersion-ceq'2.0.0'){'2.0.0'}else{Get-AiwAdoptionTargetVersion $Projection}
    foreach($entry in $Projection.objects){
        $newHistory=$entry.path-cmatch'^\.ai-workspace/upgrade-recovery/corrections/[A-Z][A-Z0-9_]*/[A-Za-z0-9._-]+/history\.json$'
        $newMajorState=$sourceVersion-ceq'1.16.0'-and$targetVersion-ceq'2.0.0'-and$entry.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'
        if($entry.kind-cne'FILE'-or(-not$entry.oldExists-and-not$newHistory-and-not$newMajorState)-or(($newHistory-or$newMajorState)-and$entry.oldExists)-or-not$entry.newExists-or(Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))-cne$entry.oldIdentity){throw 'ADOPTION_PROCESS_PROJECTION_PREIMAGE'}
    }
    $oldBinding=Get-AiwAdoptedDistributionBinding $root $sourceVersion
    $null=Assert-AiwDistributionBinding $oldBinding $receipt.sourceLocators.frameworkRoot $sourceVersion
    if($sourceVersion-ceq'1.16.0'-and$targetVersion-ceq'2.0.0'){Assert-AiwMajorAdoptionProjection $Projection $c $receipt.sourceLocators.taskRelativePath $oldBinding}
    $newBinding=Get-AiwDistributionBinding $TargetRuntimeRoot $targetVersion -Required
    Import-Module (Join-Path $receipt.sourceLocators.frameworkRoot ('framework/versions/'+$sourceVersion+'/scripts/ProcessRequirementComposition.psm1')) -Force
    $oldSources=Get-AiwProcessBindingSnapshot -ProjectRoot $root -FrameworkRoot $receipt.sourceLocators.frameworkRoot -TargetVersion $sourceVersion -TaskRelativePath $receipt.sourceLocators.taskRelativePath -ForbiddenPaths @($c.forbiddenScope)
    foreach($field in $receipt.sourceBindings.PSObject.Properties){if($null-eq$oldSources.PSObject.Properties[$field.Name]-or[string]$oldSources.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}}
    $policy=(Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/process-policy.json') 'POLICY').Value
    $closure=Get-AiwProjectPolicySourceClosure -ProjectRoot $root -Rules @($policy.rules) -ForbiddenPaths @($c.forbiddenScope)
    $targetClosure=$null
    if($targetVersion-ceq'2.0.0'){
        $policyEntry=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/process-policy.json'})
        $targetPolicy=if($policyEntry.Count-eq1){$script:Utf8NoBom.GetString([Convert]::FromBase64String($policyEntry[0].newBase64))|ConvertFrom-Json -Depth 100}else{$policy}
        Import-Module (Join-Path $TargetRuntimeRoot 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -Force
        $targetClosure=Get-AiwProjectPolicySourceClosure -ProjectRoot $root -Rules @($targetPolicy.rules) -ForbiddenPaths @($c.forbiddenScope)
    }
    $stage=Join-Path ([IO.Path]::GetTempPath()) ('aiw-adoption-process-'+[guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($stage)
    try {
        $paths=@('.ai-workspace/project.json','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md',[string]$receipt.sourceLocators.taskRelativePath)
        foreach($path in $paths){$source=Get-AiwContainedPath $root $path;if(Test-Path -LiteralPath $source -PathType Leaf){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $path) ([IO.File]::ReadAllBytes($source))}}
        foreach($doc in $closure.Documents){if($doc.locatorKind-ceq'PROJECT_RELATIVE'){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $doc.relativePath) $doc.bytes}elseif((Get-AiwCurrentIdentity $doc.sourcePath)-cne$doc.identity){throw 'ADOPTION_PROCESS_EXTERNAL_SOURCE_DRIFT'}}
        if($null-ne$targetClosure){foreach($doc in $targetClosure.Documents){if($doc.locatorKind-ceq'PROJECT_RELATIVE'){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $doc.relativePath) $doc.bytes}elseif((Get-AiwCurrentIdentity $doc.sourcePath)-cne$doc.identity){throw 'ADOPTION_PROCESS_EXTERNAL_SOURCE_DRIFT'}}}
        foreach($entry in $Projection.objects){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $entry.path) ([Convert]::FromBase64String($entry.newBase64))}
        $composition=Get-AiwAdoptionComposition $stage $TargetRuntimeRoot $receipt -EvaluationOnly
        $projectedSources=[ordered]@{}
        foreach($name in @('projectConfigIdentity','controllerIdentity','correctionsIdentity','policyIdentity','bootstrapManagedIdentity','projectCustomIdentity','projectAgentsIdentity','projectStandardsIdentity','frameworkVersionIdentity','releaseManifestIdentity','nativeCatalogIdentity','correctionCoverageIdentity')){
            if($null-ne$composition.PSObject.Properties[$name]){$projectedSources[$name]=[string]$composition.$name}
        }
        if($targetVersion-ceq'2.0.0'){$projectedSources.taskIdentity=Get-AiwCurrentIdentity (Get-AiwContainedPath $stage $receipt.sourceLocators.taskRelativePath)}
        return [ordered]@{schemaVersion=1;status='PREPARED';discoverReceiptIdentity=$receiptDoc.Identity;previousDistribution=$oldBinding;targetDistribution=$newBinding;projection=$Projection;oldSourceBindings=$oldSources;projectedSourceBindings=$projectedSources;selectedRuleBlocks=@($composition.selectedRequirements);selectedPackCeilingBytes=$composition.selectedRulePackBytes;authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}
    }finally{
        $base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar
        $full=[IO.Path]::GetFullPath($stage)
        if(-not$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-adoption-process-')){throw 'ADOPTION_PROCESS_CLEANUP_SCOPE'}
        [IO.Directory]::Delete($full,$true)
    }
}
function Get-AiwSamePinAdoptionAdmission($AdmitDocument,[string]$Root,$ExpectedProjection,$TargetDistribution,[string]$ObservedActor) {
    $ad=$AdmitDocument.Value
    if($null-eq$ad.PSObject.Properties['originalAdmissionInput']-or$null-eq$ad.PSObject.Properties['adoptionPreparation']){throw 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED'}
    $a=$ad.originalAdmissionInput;$p=$ad.adoptionPreparation
    $rd=Read-AiwAdoptionEvidence $a.discoverReceiptPath $a.expectedDiscoverReceiptIdentity 'DISCOVER'
    $r=$rd.Value;$c=Get-AiwAdoptionProcessContext $r
    if($c.frameworkVersion-cne'2.0.0'-or$c.actor-cne$ObservedActor-or(Resolve-AiwRepositoryRoot $c.projectRoot)-cne(Resolve-AiwRepositoryRoot $Root)){throw 'ADOPTION_PROCESS_SAME_PIN_CONTEXT'}
    if($ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or$a.schemaVersion-ne2-or$a.mode-cne'ADMIT_ACTION'-or
       $ad.selectionIdentity-cne$r.selectionIdentity-or@($ad.missingPreparation).Count-or@($ad.missingResult).Count-or
       $ad.authorityGranted-ne$false-or$ad.semanticCorrectnessProven-ne$false-or$ad.hostInvocationProven-ne$false-or
       $a.protectionState-cne'BOUND'-or$p.discoverReceiptIdentity-cne$rd.Identity){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
    $bytes=[Convert]::FromBase64String([string]$ad.adoptionPreparationBase64)
    if((Get-AiwByteIdentity $bytes)-cne$ad.adoptionPreparationIdentity){throw 'ADOPTION_PROCESS_PREPARATION_IDENTITY'}
    Assert-AiwAdoptionSame ($script:Utf8NoBom.GetString($bytes)|ConvertFrom-Json -Depth 100) $p 'PREPARATION_CONTENT'
    Assert-AiwAdoptionSame $p.projection $ExpectedProjection 'SAME_PIN_ADMISSION_PROJECTION'
    Assert-AiwAdoptionSame $p.targetDistribution $TargetDistribution 'SAME_PIN_ADMISSION_TARGET'
    $oldModule=@(Import-Module (Join-Path $r.sourceLocators.frameworkRoot 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -Force -PassThru -ErrorAction Stop)[0]
    $decision=& $oldModule.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $r $a
    if($decision-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
    $required=@(@($r.selectedObligations|ForEach-Object{$_.preparationRequirements})+@($p.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements})|Sort-Object -Unique)
    if(@($required|Where-Object{$_-cnotin@($a.preparationReceipts)}).Count-or('ADOPTION_TARGET_RULES_LOADED|'+$ad.adoptionPreparationIdentity)-cnotin@($a.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
    $current=New-AiwAdoptionProcessPreparation -RepositoryRoot $Root -TargetRuntimeRoot $TargetDistribution.runtimeRoot -Projection $ExpectedProjection -ObservedActor $ObservedActor -OriginalBoundary $a
    Assert-AiwAdoptionSame $current $p 'PREPARATION_DRIFT'
    return [pscustomobject]@{admission=$ad;receipt=$r;context=$c;preparation=$p;package=(Get-AiwAdoptionProcessPackage $r $c $Root).Value}
}
Export-ModuleMember -Function Get-AiwSamePinAdoptionAdmission
function Invoke-AiwSamePinRefreshFinalize($Root,$InputDoc,$ReceiptDoc,$Context,[string]$AdmitInputPath,[string]$ExpectedAdmitInputIdentity,[string]$AdmitResultPath,[string]$ExpectedAdmitResultIdentity,[string]$AuthorizationPackagePath,[string]$ExpectedAuthorizationPackageIdentity,[string]$ExpectedTransactionIdentity,[string]$ObservedActor) {
    $b=$InputDoc.Value;$r=$ReceiptDoc.Value
    if($b.mode-cne'FINALIZE_OUTPUT'-or$Context.frameworkVersion-cne'2.0.0'-or$Context.actor-cne$ObservedActor-or
       (Resolve-AiwRepositoryRoot $Context.projectRoot)-cne$Root){throw 'ADOPTION_PROCESS_SAME_PIN_CONTEXT'}
    $statePath='.ai-workspace/upgrade-recovery/2.0.0/state.json'
    if($statePath-cnotin@($Context.exactScope)){throw 'ADOPTION_PROCESS_SAME_PIN_SCOPE'}
    $adDoc=Read-AiwAdoptionEvidence $AdmitResultPath $ExpectedAdmitResultIdentity 'ADMIT_RESULT'
    $ad=$adDoc.Value;$aDoc=$null
    if($null-ne$ad.PSObject.Properties['originalAdmissionInput']){
        $a=$ad.originalAdmissionInput
        if(-not[string]::IsNullOrWhiteSpace($AdmitInputPath)){
            $aDoc=Read-AiwAdoptionEvidence $AdmitInputPath $ExpectedAdmitInputIdentity 'ORIGINAL_ADMIT_INPUT'
            Assert-AiwAdoptionSame $aDoc.Value $a 'ORIGINAL_ADMIT_INPUT'
        }
    }else{
        $aDoc=Read-AiwAdoptionEvidence $AdmitInputPath $ExpectedAdmitInputIdentity 'ORIGINAL_ADMIT_INPUT'
        $a=$aDoc.Value
    }
    $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')
    if($null-ne$a.PSObject.Properties['deliveryContext']){$fields+='deliveryContext'}
    if($null-ne$a.PSObject.Properties['evidenceRefs']){$fields+='evidenceRefs'}
    Assert-AiwAdoptionSame @($a.PSObject.Properties.Name|Sort-Object) @($fields|Sort-Object) 'ORIGINAL_ADMIT_FIELDS'
    if($a.schemaVersion-ne2-or$a.mode-cne'ADMIT_ACTION'-or$a.discoverReceiptPath-cne$b.discoverReceiptPath-or
       $a.expectedDiscoverReceiptIdentity-cne$ReceiptDoc.Identity-or$a.publicDecisionIdentity-cne$b.publicDecisionIdentity-or
       $a.protectionState-cne$b.protectionState-or$ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or
       $ad.selectionIdentity-cne$r.selectionIdentity-or@($ad.missingPreparation).Count-or@($ad.missingResult).Count-or
       $ad.authorityGranted-ne$false-or$ad.semanticCorrectnessProven-ne$false-or$ad.hostInvocationProven-ne$false){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
    foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){
        if($a.$name-isnot[array]-or@($a.$name|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ADOPTION_PROCESS_ORIGINAL_ADMIT_ARRAY'}
    }
    $oldRuntime=[string]$r.sourceLocators.frameworkRoot
    $oldModule=@(Import-Module (Join-Path $oldRuntime 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -Force -PassThru -ErrorAction Stop)[0]
    $decision=& $oldModule.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $r $a
    if($decision-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
    $processPackage=Get-AiwAdoptionProcessPackage $r $Context $Root
    if($processPackage.Value.frameworkVersion-cne'2.0.0'){throw 'ADOPTION_PROCESS_SAME_PIN_PACKAGE'}
    $txnPath=Get-AiwContainedPath $Root '.ai-workspace/runtime/project-adoption/refresh/state.json'
    $txnDoc=Read-AiwAdoptionEvidence $txnPath $ExpectedTransactionIdentity 'TRANSACTION';$txn=$txnDoc.Value
    if($txn.schemaVersion-ne1-or$txn.transactionComplete-isnot[bool]-or-not$txn.transactionComplete-or$txn.state-cne'COMPLETE'-or
       $txn.metadata.operation-cne'UPGRADE_RUNTIME_REFRESH'-or$txn.metadata.taskPath-cne$r.sourceLocators.taskRelativePath-or
       $txn.metadata.taskIdentity-cne$Context.taskIdentity-or$txn.metadata.projectConfigIdentity-cne$r.sourceBindings.projectConfigIdentity-or
       $txn.metadata.controllerIdentity-cne$r.sourceBindings.controllerIdentity-or$txn.metadata.actor-cne$ObservedActor-or
       @($txn.projection.objects).Count-ne@($Context.exactScope).Count-or$txn.completedWrites-ne@($txn.projection.objects|Where-Object changed).Count){throw 'ADOPTION_PROCESS_SAME_PIN_TRANSACTION'}
    $null=Assert-AiwProjectionContract $Root $txn.projection
    Assert-AiwAdoptionSame @($txn.projection.objects.path|Sort-Object) @($Context.exactScope|Sort-Object) 'SAME_PIN_PROJECTION_SCOPE'
    $stateEntries=@($txn.projection.objects|Where-Object{$_.path-ceq$statePath})
    if($stateEntries.Count-ne1-or-not$stateEntries[0].oldExists-or-not$stateEntries[0].newExists){throw 'ADOPTION_PROCESS_SAME_PIN_STATE'}
    $entry=$stateEntries[0]
    if($entry.oldIdentity-cne$r.sourceBindings.candidatePilotStateIdentity){throw 'ADOPTION_PROCESS_SAME_PIN_PREIMAGE'}
    $oldState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entry.oldBase64))|ConvertFrom-Json -Depth 100
    $newState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entry.newBase64))|ConvertFrom-Json -Depth 100
    if($oldState.schemaVersion-ne6-or$newState.schemaVersion-ne6-or$oldState.transactionComplete-ne$true-or$newState.transactionComplete-ne$true-or
       $oldState.toVersion-cne'2.0.0'-or$newState.toVersion-cne'2.0.0'){throw 'ADOPTION_PROCESS_SAME_PIN_STATE'}
    $oldBinding=Assert-AiwDistributionBinding $oldState.distributionBinding $oldRuntime '2.0.0'
    $newBinding=Assert-AiwDistributionBinding $newState.distributionBinding $txn.metadata.distributionBinding.runtimeRoot '2.0.0'
    Assert-AiwAdoptionSame $txn.metadata.distributionBinding $newBinding 'SAME_PIN_TARGET_DISTRIBUTION'
    Assert-AiwAdoptionSame (Get-AiwAdoptedDistributionBinding $Root '2.0.0') $newBinding 'SAME_PIN_LIVE_DISTRIBUTION'
    $authorization=Read-AiwAdoptionEvidence $AuthorizationPackagePath $ExpectedAuthorizationPackageIdentity 'ADOPTION_AUTHORIZATION'
    if($authorization.Identity-cne$txn.metadata.authorizationIdentity){throw 'ADOPTION_PROCESS_SAME_PIN_AUTHORIZATION'}
    $proof=[pscustomobject]@{package=$processPackage.Value;preparation=[pscustomobject]@{projection=$txn.projection}}
    Assert-AiwMajorUpgradeAuthorization $authorization.Value $proof ([pscustomobject]@{canonical=$newState.targetReleaseCanonical;manifestIdentity=$newState.targetReleaseManifestIdentity})
    $prepared=$null
    if($null-ne$ad.PSObject.Properties['adoptionPreparation']){
        if($null-eq$txn.metadata.PSObject.Properties['admitResultIdentity']-or$txn.metadata.admitResultIdentity-cne$adDoc.Identity){throw 'ADOPTION_PROCESS_SAME_PIN_ADMISSION_BINDING'}
        $prepared=$ad.adoptionPreparation
        $bytes=[Convert]::FromBase64String([string]$ad.adoptionPreparationBase64)
        if((Get-AiwByteIdentity $bytes)-cne$ad.adoptionPreparationIdentity){throw 'ADOPTION_PROCESS_PREPARATION_IDENTITY'}
        Assert-AiwAdoptionSame ($script:Utf8NoBom.GetString($bytes)|ConvertFrom-Json -Depth 100) $prepared 'PREPARATION_CONTENT'
        Assert-AiwAdoptionSame $prepared.projection $txn.projection 'SAME_PIN_PREPARATION_PROJECTION'
        Assert-AiwAdoptionSame $prepared.previousDistribution $oldBinding 'SAME_PIN_PREPARATION_OLD_PACKAGE'
        Assert-AiwAdoptionSame $prepared.targetDistribution $newBinding 'SAME_PIN_PREPARATION_NEW_PACKAGE'
        if($prepared.discoverReceiptIdentity-cne$ReceiptDoc.Identity){throw 'ADOPTION_PROCESS_PREPARATION_RECEIPT'}
        foreach($field in $r.sourceBindings.PSObject.Properties){
            if($null-eq$prepared.oldSourceBindings.PSObject.Properties[$field.Name]-or
               [string]$prepared.oldSourceBindings.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}
        }
        if(('ADOPTION_TARGET_RULES_LOADED|'+$ad.adoptionPreparationIdentity)-cnotin@($a.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
    }else{
        # Only a transaction written by the retained pre-bridge root may use
        # this recovery path. New roots bind PREPARE and ADMIT before Apply.
        $legacyRootRevision='3D708668F30BEB70310A033CB3674D6675CCEA6AA6D483D793ABC0EE24AE65AD'
        $observedRoot=Get-AiwRootToolRevision $oldRuntime @($oldState.rootToolDependencies|ForEach-Object{[string]$_.path})
        if($null-ne$txn.metadata.PSObject.Properties['admitResultIdentity']-or
           $oldState.rootToolRevision-cne$legacyRootRevision-or$observedRoot.revision-cne$legacyRootRevision){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_REQUIRED'}
        # The legacy exception is state-only and cannot change version payload,
        # project authority or selected obligations.
        if(@($txn.projection.objects).Count-ne1-or$oldState.targetReleaseCanonical-cne$newState.targetReleaseCanonical-or
           $oldState.targetReleaseManifestIdentity-cne$newState.targetReleaseManifestIdentity){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_REQUIRED'}
        $left=$oldState|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $right=$newState|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $oldProjection=@($left.projectionObjects);$newProjection=@($right.projectionObjects)
        if($oldProjection.Count-ne$newProjection.Count){throw 'ADOPTION_PROCESS_SAME_PIN_UNPREPARED_STATE_CHANGE'}
        for($i=0;$i-lt$oldProjection.Count;$i++){
            $before=$oldProjection[$i];$after=$newProjection[$i]
            if($before.relative-cne$after.relative){throw 'ADOPTION_PROCESS_SAME_PIN_UNPREPARED_STATE_CHANGE'}
            if($before.relative-ceq'.ai-workspace/process-policy.json'){
                if($after.identity-cne$r.sourceBindings.policyIdentity-or
                   (Get-AiwCurrentIdentity (Get-AiwContainedPath $Root $after.relative))-cne$after.identity){throw 'ADOPTION_PROCESS_SAME_PIN_POLICY_PROJECTION'}
            }else{Assert-AiwAdoptionSame $before $after 'SAME_PIN_UNPREPARED_PROJECTION_CHANGE'}
        }
        foreach($name in @('distributionBinding','rootToolRevision','rootToolDependencies','projectionObjects')){$left.PSObject.Properties.Remove($name);$right.PSObject.Properties.Remove($name)}
        Assert-AiwAdoptionSame $left $right 'SAME_PIN_UNPREPARED_STATE_CHANGE'
    }
    $verified=Resume-AiwRuntimeAdoption -RepositoryRoot $Root -ExpectedTransactionIdentity $txnDoc.Identity -AuthorizationPackagePath $AuthorizationPackagePath -ExpectedAuthorizationPackageIdentity $ExpectedAuthorizationPackageIdentity -ObservedActor $ObservedActor
    if($verified.status-cne'COMPLETE'-or$verified.writes-ne0){throw 'ADOPTION_PROCESS_TRANSACTION_INCOMPLETE'}
    foreach($object in $txn.projection.objects){
        $pre=@($authorization.Value.objectIdentities|Where-Object{$_.path-ceq$object.path})
        $expectedPre=if($object.oldExists){[string]$object.oldIdentity}else{'NEW'}
        $post='OBJECT_POSTIMAGE|'+$object.path+'|'+$object.newIdentity
        if($pre.Count-ne1-or$pre[0].identity-cne$expectedPre-or(Get-AiwCurrentIdentity (Get-AiwContainedPath $Root $object.path))-cne$object.newIdentity-or
           @($b.resultReceipts|Where-Object{$_-ceq$post}).Count-ne1){throw ('ADOPTION_PROCESS_OBJECT_PROOF|'+$object.path)}
    }
    if(@($authorization.Value.objectIdentities).Count-ne@($txn.projection.objects).Count-or
       @($b.resultReceipts|Where-Object{$_-clike'OBJECT_POSTIMAGE|*'}).Count-ne@($txn.projection.objects).Count){throw 'ADOPTION_PROCESS_OBJECT_SCOPE'}
    $composition=Get-AiwAdoptionComposition $Root $newBinding.runtimeRoot $r
    # WorkflowDelivery consumes the old version's exported composition helpers.
    # Load that exact module into the command scope before invoking it.
    Import-Module (Join-Path $oldRuntime 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -Global -Force -ErrorAction Stop
    $deliveryModule=@(Import-Module (Join-Path $oldRuntime 'framework/versions/2.0.0/scripts/WorkflowDelivery.psm1') -Force -PassThru -ErrorAction Stop)[0]
    $boundAdmit=& $deliveryModule.ExportedFunctions['Get-AiwBoundDelivery'] $r $a
    $admitDelivery=if($null-ne$boundAdmit){$boundAdmit.delivery}else{$null}
    if($null-ne$admitDelivery){
        if($null-eq$ad.PSObject.Properties['delivery']){throw 'ADOPTION_PROCESS_ADMIT_DELIVERY_RESULT'}
        Assert-AiwAdoptionSame $admitDelivery $ad.delivery 'ADMIT_DELIVERY_RESULT'
    }elseif($null-ne$ad.PSObject.Properties['delivery']){throw 'ADOPTION_PROCESS_ADMIT_DELIVERY_RESULT'}
    $boundDelivery=& $deliveryModule.ExportedFunctions['Get-AiwBoundDelivery'] $r $b
    $delivery=if($null-ne$boundDelivery){$boundDelivery.delivery}else{$null}
    if($null-ne$boundDelivery-and-not$boundDelivery.closureSatisfied){throw 'ADOPTION_PROCESS_DELIVERY_NOT_CONFIRMED'}
    if($null-ne$prepared){
        Assert-AiwAdoptionSame @($composition.selectedRequirements) @($prepared.selectedRuleBlocks) 'TARGET_RULE_DRIFT'
        if($composition.selectedRulePackBytes-ne$prepared.selectedPackCeilingBytes){throw 'ADOPTION_PROCESS_PACK_BUDGET'}
        foreach($field in $prepared.projectedSourceBindings.PSObject.Properties){
            $live=if($field.Name-ceq'taskIdentity'){Get-AiwCurrentIdentity (Get-AiwContainedPath $Root $r.sourceLocators.taskRelativePath)}else{[string]$composition.($field.Name)}
            if($live-cne[string]$field.Value){throw ('ADOPTION_PROCESS_SOURCE_DRIFT|'+$field.Name)}
        }
    }else{
        $obligations=@($composition.selectedRequirements|ForEach-Object{[ordered]@{requirementId=[string]$_.requirementId;preparationRequirements=@($_.preparationRequirements);resultRequirements=@($_.resultRequirements)}})
        Assert-AiwAdoptionSame $obligations @($r.selectedObligations) 'SAME_PIN_UNPREPARED_RULE_DRIFT'
    }
    $bindings=Get-AiwProcessBindingSnapshot -ProjectRoot $Root -FrameworkRoot $newBinding.runtimeRoot -TargetVersion '2.0.0' -TaskRelativePath $r.sourceLocators.taskRelativePath -ForbiddenPaths @($Context.forbiddenScope)
    foreach($field in $r.sourceBindings.PSObject.Properties){
        $expected=if($field.Name-ceq'candidatePilotStateIdentity'){$entry.newIdentity}elseif($null-ne$prepared-and$null-ne$prepared.projectedSourceBindings.PSObject.Properties[$field.Name]){[string]$prepared.projectedSourceBindings.($field.Name)}else{[string]$field.Value}
        if($null-eq$bindings.PSObject.Properties[$field.Name]-or[string]$bindings.($field.Name)-cne$expected){throw ('ADOPTION_PROCESS_SOURCE_DRIFT|'+$field.Name)}
    }
    $requiredPrep=@($r.selectedObligations|ForEach-Object{$_.preparationRequirements})
    $requiredResult=@($r.selectedObligations|ForEach-Object{$_.resultRequirements})
    if($null-ne$prepared){$requiredPrep+=@($prepared.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements});$requiredResult+=@($prepared.selectedRuleBlocks|ForEach-Object{$_.resultRequirements})}
    $requiredPrep=@($requiredPrep|Sort-Object -Unique);$requiredResult=@($requiredResult|Sort-Object -Unique)
    if($null-ne$delivery){$requiredResult=@($requiredResult|Where-Object{$_-cne'DELIVERY_RECEIPT'})}
    if(@($requiredPrep|Where-Object{$_-cnotin@($a.preparationReceipts)-or$_-cnotin@($b.preparationReceipts)}).Count-or
       @($requiredResult|Where-Object{$_-cnotin@($b.resultReceipts)}).Count){throw 'ADOPTION_PROCESS_OBLIGATIONS_INCOMPLETE'}
    if($null-eq$delivery-and$r.intentEnvelope.requestedResultKind-cin@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE')-and
       @($b.deliveryReceipts).Count-eq0){throw 'ADOPTION_PROCESS_DELIVERY_INCOMPLETE'}
    foreach($doc in @($InputDoc,$ReceiptDoc,$aDoc,$adDoc,$processPackage,$authorization,$txnDoc)|Where-Object{$null-ne$_}){
        if((Get-AiwCurrentIdentity $doc.Path)-cne$doc.Identity){throw 'ADOPTION_PROCESS_EVIDENCE_CHANGED_DURING_CHECK'}
    }
    $result=[ordered]@{status='PASS';mode='FINALIZE_OUTPUT';reason='ORIGINAL_SAME_PIN_REFRESH_FINALIZED';originalDiscoverReceiptIdentity=$ReceiptDoc.Identity;originalAdmitDecisionIdentity=$ad.decisionIdentity;adoptionTransactionIdentity=$txnDoc.Identity;previousSourceCompositionIdentity=$r.sourceCompositionIdentity;currentSourceCompositionIdentity=$composition.sourceCompositionIdentity;previousRuntimeRoot=$oldBinding.runtimeRoot;runtimeRoot=$newBinding.runtimeRoot;missingPreparation=@();missingResult=@();authorityGranted=$false;semanticCorrectnessProven=$false;hostInvocationProven=$false;evidenceGrade='INSTRUCTION_BOUND'}
    if($null-ne$delivery){$result.delivery=$delivery;$result.consumer=$boundDelivery.consumer;$result.finalizeInputIdentity=$InputDoc.Identity}
    return $result
}

function Invoke-AiwAdoptionProcessBoundary {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[string]$InputPath,[string]$ExpectedInputIdentity,[string]$PreparationPath,[string]$ExpectedPreparationIdentity,[string]$AdmitInputPath,[string]$ExpectedAdmitInputIdentity,[string]$AdmitResultPath,[string]$ExpectedAdmitResultIdentity,[string]$AuthorizationPackagePath,[string]$ExpectedAuthorizationPackageIdentity,[string]$ExpectedTransactionIdentity,[string]$ObservedActor,[string]$ExpectedMode,[switch]$DeleteInputOnExit)
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $inputDoc=Read-AiwAdoptionEvidence $InputPath $ExpectedInputIdentity 'BOUNDARY';$b=$inputDoc.Value
    $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')
    $boundaryFields=@($fields);if($null-ne$b.PSObject.Properties['deliveryContext']){$boundaryFields+='deliveryContext'};if($null-ne$b.PSObject.Properties['evidenceRefs']){$boundaryFields+='evidenceRefs'}
    Assert-AiwAdoptionSame @($b.PSObject.Properties.Name|Sort-Object) @($boundaryFields|Sort-Object) 'BOUNDARY_FIELDS'
    if($b.schemaVersion-ne2-or$b.mode-cne$ExpectedMode-or$b.mode-cnotin@('ADMIT_ACTION','FINALIZE_OUTPUT')-or$b.protectionState-cne'BOUND'){throw 'ADOPTION_PROCESS_BOUNDARY_CONTRACT'}
    $receiptDoc=Read-AiwAdoptionEvidence $b.discoverReceiptPath $b.expectedDiscoverReceiptIdentity 'DISCOVER';$r=$receiptDoc.Value;$c=Get-AiwAdoptionProcessContext $r
    if((Resolve-AiwRepositoryRoot $c.projectRoot)-cne$root-or$c.actor-cne$ObservedActor){throw 'ADOPTION_PROCESS_ACTOR_ROOT'}
    $cleanup=$false
    if($DeleteInputOnExit){
        if($c.taskId-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){throw 'ADOPTION_PROCESS_CLEANUP_CONTEXT'}
        $actorStorage=Get-AiwBoundRuntimeActorStorageKey $r.sourceLocators.frameworkRoot $c.frameworkVersion $c.actor
        $prefix=(Get-AiwContainedPath $root ('.ai-workspace/runtime/'+$c.taskId+'/'+$actorStorage))+[IO.Path]::DirectorySeparatorChar
        if(-not$inputDoc.Path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'ADOPTION_PROCESS_CLEANUP_SCOPE'}
        $null=Get-AiwContainedPath $root ([IO.Path]::GetRelativePath($root,$inputDoc.Path).Replace('\','/'));$cleanup=$true
    }
    try {
        foreach($field in @('preparationReceipts','resultReceipts','deliveryReceipts')){if($b.$field-isnot[array]-or@($b.$field|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ADOPTION_PROCESS_BOUNDARY_ARRAY'}}
        if($b.mode-ceq'ADMIT_ACTION'){
            $pDoc=Read-AiwAdoptionEvidence $PreparationPath $ExpectedPreparationIdentity 'PREPARATION';$p=$pDoc.Value
            $current=New-AiwAdoptionProcessPreparation $root $InputPath $ExpectedInputIdentity $p.targetDistribution.runtimeRoot $p.projection $ObservedActor
            Assert-AiwAdoptionSame $current $p 'PREPARATION_DRIFT'
            $required=@($p.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique)
            if(@($required|Where-Object{$_-cnotin@($b.preparationReceipts)}).Count-or('ADOPTION_TARGET_RULES_LOADED|'+$pDoc.Identity)-cnotin@($b.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
            # Delegate the actual, unmodified admission exactly once. Retain its
            # exact input before the version resolver's normal cleanup.
            $entry=Join-Path $r.sourceLocators.frameworkRoot ('framework/versions/'+$c.frameworkVersion+'/scripts/resolve-process-requirements.ps1')
            $args=@('-NoProfile','-NonInteractive','-File',$entry,'-InputPath',$InputPath,'-AsJson')
            $config=(Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'PROJECT').Value
            if($null-ne$config.PSObject.Properties['controlPlaneLayout']-and$config.controlPlaneLayout-ceq'framework-maintenance-sibling'){$args+=@('-AuthorizationCheckerPath',(Join-Path $r.sourceLocators.frameworkRoot 'scripts/check-framework-maintenance-authorization.ps1'))}
            if($DeleteInputOnExit){$args+='-DeleteInputOnExit'}
            $output=@(& pwsh @args);if($LASTEXITCODE-ne0-or$output.Count-ne1){throw ('ADOPTION_PROCESS_ORIGINAL_ADMIT|'+($output-join';'))}
            $result=$output[0]|ConvertFrom-Json -Depth 100
            if($result.status-cne'PASS'-or$result.mode-cne'ADMIT_ACTION'){throw 'ADOPTION_PROCESS_ORIGINAL_ADMIT'}
            $result|Add-Member originalAdmissionInput $b
            $result|Add-Member adoptionPreparation $p
            $result|Add-Member adoptionPreparationIdentity $pDoc.Identity
            $result|Add-Member adoptionPreparationBase64 ([Convert]::ToBase64String($pDoc.Bytes))
            return $result
        }
        if($c.frameworkVersion-ceq'2.0.0'){
            return Invoke-AiwSamePinRefreshFinalize $root $inputDoc $receiptDoc $c $AdmitInputPath $ExpectedAdmitInputIdentity $AdmitResultPath $ExpectedAdmitResultIdentity $AuthorizationPackagePath $ExpectedAuthorizationPackageIdentity $ExpectedTransactionIdentity $ObservedActor
        }
        $adDoc=Read-AiwAdoptionEvidence $AdmitResultPath $ExpectedAdmitResultIdentity 'ADMIT_RESULT';$ad=$adDoc.Value
        if($null-eq$ad.PSObject.Properties['originalAdmissionInput']-or$null-eq$ad.PSObject.Properties['adoptionPreparation']){throw 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED'}
        $a=$ad.originalAdmissionInput;$p=$ad.adoptionPreparation
        $targetVersion=Get-AiwAdoptionTargetVersion $p.projection
        if($targetVersion-ceq'2.0.0'){Assert-AiwMajorAdoptionProjection $p.projection $c $r.sourceLocators.taskRelativePath $p.previousDistribution}
        $preparationBytes=[Convert]::FromBase64String($ad.adoptionPreparationBase64)
        if((Get-AiwByteIdentity $preparationBytes)-cne$ad.adoptionPreparationIdentity){throw 'ADOPTION_PROCESS_PREPARATION_IDENTITY'}
        Assert-AiwAdoptionSame ($script:Utf8NoBom.GetString($preparationBytes)|ConvertFrom-Json -Depth 100) $p 'PREPARATION_CONTENT'
        foreach($field in $r.sourceBindings.PSObject.Properties){if($null-eq$p.oldSourceBindings.PSObject.Properties[$field.Name]-or[string]$p.oldSourceBindings.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}}
        $admitFields=@($fields);if($null-ne$a.PSObject.Properties['deliveryContext']){$admitFields+='deliveryContext'};if($null-ne$a.PSObject.Properties['evidenceRefs']){$admitFields+='evidenceRefs'}
        Assert-AiwAdoptionSame @($a.PSObject.Properties.Name|Sort-Object) @($admitFields|Sort-Object) 'ADMIT_FIELDS'
        foreach($field in @('preparationReceipts','resultReceipts','deliveryReceipts')){if($a.$field-isnot[array]-or@($a.$field|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ADOPTION_PROCESS_ADMIT_ARRAY'}}
        if($ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or$a.mode-cne'ADMIT_ACTION'-or$a.schemaVersion-ne2-or$ad.selectionIdentity-cne$r.selectionIdentity-or$a.expectedDiscoverReceiptIdentity-cne$receiptDoc.Identity-or$a.discoverReceiptPath-cne$b.discoverReceiptPath-or$a.protectionState-cne$b.protectionState-or$a.publicDecisionIdentity-cne$b.publicDecisionIdentity-or@($ad.missingPreparation).Count-or@($ad.missingResult).Count-or$p.discoverReceiptIdentity-cne$receiptDoc.Identity){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
        $material=@($r.sourceCompositionIdentity,$r.selectionIdentity,$r.contextIdentity,'ADMIT_ACTION',$r.intentEnvelope.objective,'CONTROL_WRITE',$r.intentEnvelope.requestedResultKind,[string]::Join(',',@($c.exactScope)),$c.authorizationIdentity,[string]::Join(',',@($a.preparationReceipts)),[string]::Join(',',@($a.resultReceipts)),[string]::Join(',',@($a.deliveryReceipts)),$a.publicDecisionIdentity,$a.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join"`n"
        if($null-ne$a.PSObject.Properties['deliveryContext']){$material+=($a.deliveryContext|ConvertTo-Json -Compress)}
        if((Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes($material))).Split('|')[1]-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
        if(('ADOPTION_TARGET_RULES_LOADED|'+$ad.adoptionPreparationIdentity)-cnotin@($a.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
        $pkgDoc=Get-AiwAdoptionProcessPackage $r $c $root;$pkg=$pkgDoc.Value
        $txnPath=Get-AiwContainedPath $root '.ai-workspace/runtime/project-adoption/upgrade/state.json'
        $txnDoc=Read-AiwAdoptionEvidence $txnPath $ExpectedTransactionIdentity 'TRANSACTION';$t=$txnDoc.Value
        if($t.transactionComplete-isnot[bool]-or-not$t.transactionComplete-or$t.state-cne'COMPLETE'-or$t.metadata.taskPath-cne$r.sourceLocators.taskRelativePath-or$t.metadata.taskIdentity-cne$c.taskIdentity-or$t.metadata.projectConfigIdentity-cne$r.sourceBindings.projectConfigIdentity-or$t.metadata.controllerIdentity-cne$r.sourceBindings.controllerIdentity){throw 'ADOPTION_PROCESS_TRANSACTION_INCOMPLETE_OR_CONTEXT'}
        Assert-AiwAdoptionSame $t.projection $p.projection 'TRANSACTION_PROJECTION'
        $verified=Resume-AiwRuntimeAdoption -RepositoryRoot $root -ExpectedTransactionIdentity $txnDoc.Identity -AuthorizationPackagePath $AuthorizationPackagePath -ExpectedAuthorizationPackageIdentity $ExpectedAuthorizationPackageIdentity -ObservedActor $ObservedActor
        if($verified.status-cne'COMPLETE'-or$verified.writes-ne0){throw 'ADOPTION_PROCESS_TRANSACTION_INCOMPLETE'}
        $null=Assert-AiwDistributionBinding $p.previousDistribution $r.sourceLocators.frameworkRoot '1.16.0'
        $null=Assert-AiwDistributionBinding $p.targetDistribution $p.targetDistribution.runtimeRoot $targetVersion
        Assert-AiwAdoptionSame $t.metadata.distributionBinding $p.targetDistribution 'TRANSACTION_DISTRIBUTION'
        Assert-AiwAdoptionSame (Get-AiwAdoptedDistributionBinding $root $targetVersion) $p.targetDistribution 'LIVE_DISTRIBUTION'
        foreach($e in $t.projection.objects){
            $pre=@($pkg.objectIdentities|Where-Object{$_.path-ceq$e.path})
            $expectedPre=if($e.oldExists){[string]$e.oldIdentity}else{'NEW'}
            if($pre.Count-ne1-or$pre[0].identity-cne$expectedPre-or(Get-AiwCurrentIdentity (Get-AiwContainedPath $root $e.path))-cne$e.newIdentity-or('OBJECT_POSTIMAGE|'+$e.path+'|'+$e.newIdentity)-cnotin@($b.resultReceipts)){throw 'ADOPTION_PROCESS_OBJECT_PROOF'}
        }
        if(@($pkg.objectIdentities).Count-ne@($t.projection.objects).Count){throw 'ADOPTION_PROCESS_OBJECT_SCOPE'}
        $stateEntry=@($t.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/1.16.0/state.json'})[0]
        $oldState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($stateEntry.oldBase64))|ConvertFrom-Json -Depth 100
        Assert-AiwAdoptionSame $oldState.distributionBinding $p.previousDistribution 'OLD_DISTRIBUTION'
        if($stateEntry.oldIdentity-cne$r.sourceBindings.candidatePilotStateIdentity){throw 'ADOPTION_PROCESS_OLD_STATE'}
        $composition=Get-AiwAdoptionComposition $root $p.targetDistribution.runtimeRoot $r
        $admitDelivery=Get-AiwBoundaryDeliveryObservation $a $p.previousDistribution.runtimeRoot
        if($null-ne$admitDelivery){
            if($null-eq$ad.PSObject.Properties['delivery']){throw 'ADOPTION_PROCESS_ADMIT_DELIVERY_RESULT'}
            Assert-AiwAdoptionSame $admitDelivery $ad.delivery 'ADMIT_DELIVERY_RESULT'
        }elseif($null-ne$ad.PSObject.Properties['delivery']){throw 'ADOPTION_PROCESS_ADMIT_DELIVERY_RESULT'}
        $delivery=Get-AiwBoundaryDeliveryObservation $b $p.targetDistribution.runtimeRoot $targetVersion
        Assert-AiwAdoptionSame @($composition.selectedRequirements) @($p.selectedRuleBlocks) 'TARGET_RULE_DRIFT'
        if($composition.selectedRulePackBytes-ne$p.selectedPackCeilingBytes){throw 'ADOPTION_PROCESS_PACK_BUDGET'}
        foreach($field in $p.projectedSourceBindings.PSObject.Properties){
            $live=if($field.Name-ceq'taskIdentity'){Get-AiwCurrentIdentity (Get-AiwContainedPath $root $r.sourceLocators.taskRelativePath)}else{[string]$composition.($field.Name)}
            if($live-cne[string]$field.Value){throw ('ADOPTION_PROCESS_SOURCE_DRIFT|'+$field.Name)}
        }
        # All unrelated sources must remain exactly the original sources. The
        # projected managed files and package fields are proved separately above.
        $bindings=Get-AiwProcessBindingSnapshot -ProjectRoot $root -FrameworkRoot $p.targetDistribution.runtimeRoot -TargetVersion $targetVersion -TaskRelativePath $r.sourceLocators.taskRelativePath -ForbiddenPaths @($c.forbiddenScope)
        $projectedFields=@('frameworkVersionIdentity','releaseManifestIdentity','nativeCatalogIdentity','correctionCoverageIdentity','bootstrapManagedIdentity','projectAgentsIdentity')
        if('.ai-workspace/corrections.json'-cin@($t.projection.objects.path)){$projectedFields+='correctionsIdentity'}
        if($targetVersion-ceq'2.0.0'){$projectedFields+=@('projectConfigIdentity','policyIdentity','taskIdentity','projectStandardsIdentity')}
        $targetStateEntry=@($t.projection.objects|Where-Object{$_.path-ceq('.ai-workspace/upgrade-recovery/'+$targetVersion+'/state.json')})[0]
        foreach($field in $bindings.PSObject.Properties){
            $name=$field.Name
            if($name-ceq'candidatePilotStateIdentity'){$expected=[string]$targetStateEntry.newIdentity}
            elseif($name-cin$projectedFields){
                if($null-eq$p.projectedSourceBindings.PSObject.Properties[$name]){throw ('ADOPTION_PROCESS_UNSUPPORTED_SOURCE|'+$name)}
                $expected=[string]$p.projectedSourceBindings.$name
            }else{
                if($null-eq$p.oldSourceBindings.PSObject.Properties[$name]){throw ('ADOPTION_PROCESS_UNSUPPORTED_SOURCE|'+$name)}
                $expected=[string]$p.oldSourceBindings.$name
            }
            if([string]$field.Value-cne$expected){throw ('ADOPTION_PROCESS_SOURCE_DRIFT|'+$name)}
        }
        foreach($name in $p.oldSourceBindings.PSObject.Properties.Name){if($null-eq$bindings.PSObject.Properties[$name]-and$name-cne'correctionCoverageIdentity'){throw ('ADOPTION_PROCESS_UNSUPPORTED_SOURCE|'+$name)}}
        $prep=@(@($r.selectedObligations|ForEach-Object{$_.preparationRequirements})+@($p.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements})|Sort-Object -Unique)
        if(@($prep|Where-Object{$_-cnotin@($a.preparationReceipts)-or$_-cnotin@($b.preparationReceipts)}).Count){throw 'ADOPTION_PROCESS_PREPARATION_INCOMPLETE'}
        $results=@(@($r.selectedObligations|ForEach-Object{$_.resultRequirements})+@($p.selectedRuleBlocks|ForEach-Object{$_.resultRequirements})|Sort-Object -Unique)
        if($null-ne$delivery){$results=@($results|Where-Object{$_-cne'DELIVERY_RECEIPT'})}
        if(@($results|Where-Object{$_-cnotin@($b.resultReceipts)}).Count){throw 'ADOPTION_PROCESS_RESULT_INCOMPLETE'}
        if($null-eq$delivery-and$r.intentEnvelope.requestedResultKind-cin@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE')-and@($b.deliveryReceipts).Count-eq0){throw 'ADOPTION_PROCESS_DELIVERY_INCOMPLETE'}
        foreach($doc in @($inputDoc,$receiptDoc,$adDoc,$pkgDoc,$txnDoc)){if((Get-AiwCurrentIdentity $doc.Path)-cne$doc.Identity){throw 'ADOPTION_PROCESS_EVIDENCE_CHANGED_DURING_CHECK'}}
        $result=[ordered]@{status='PASS';mode='FINALIZE_OUTPUT';reason='ORIGINAL_CROSS_DISTRIBUTION_ADOPTION_FINALIZED';originalDiscoverReceiptIdentity=$receiptDoc.Identity;originalAdmitDecisionIdentity=$ad.decisionIdentity;adoptionTransactionIdentity=$txnDoc.Identity;previousSourceCompositionIdentity=$r.sourceCompositionIdentity;currentSourceCompositionIdentity=$composition.sourceCompositionIdentity;runtimeRoot=$p.targetDistribution.runtimeRoot;missingPreparation=@();missingResult=@();authorityGranted=$false;semanticCorrectnessProven=$false;hostInvocationProven=$false;evidenceGrade='INSTRUCTION_BOUND'}
        if($null-ne$delivery){$result.delivery=$delivery;$result.finalizeInputIdentity=$inputDoc.Identity}
        return $result
    }finally{if($cleanup-and(Test-Path -LiteralPath $inputDoc.Path -PathType Leaf)){[IO.File]::Delete($inputDoc.Path)}}
}
Export-ModuleMember -Function New-AiwAdoptionProcessPreparation,Invoke-AiwAdoptionProcessBoundary
