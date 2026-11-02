Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
$script:Utf8NoBom = [Text.UTF8Encoding]::new($false)
$script:AdoptionPreparationInvocation = $null

# Bind implementation and data root together: named runtimes may export the
# same command names while owning different release and source algorithms.
function Get-AiwAdoptionRuntimeModule([string]$Runtime,[string]$RelativePath,[string[]]$Commands) {
    $path=Get-AiwContainedPath $Runtime $RelativePath
    $modules=@(Import-Module $path -PassThru -ErrorAction Stop)
    if($modules.Count-ne1-or[IO.Path]::GetFullPath($modules[0].Path)-cne[IO.Path]::GetFullPath($path)){throw 'ADOPTION_PROCESS_MODULE_BINDING'}
    $module=$modules[0]
    foreach($name in $Commands){
        if(-not$module.ExportedCommands.ContainsKey($name)){throw ('ADOPTION_PROCESS_MODULE_EXPORT|'+$name)}
        $command=$module.ExportedCommands[$name]
        if($null-eq$command.Module-or[IO.Path]::GetFullPath($command.Module.Path)-cne[IO.Path]::GetFullPath($path)){throw ('ADOPTION_PROCESS_COMMAND_BINDING|'+$name)}
    }
    return $module
}

function Get-AiwBoundRuntimeActorStorageKey([string]$FrameworkRoot,[string]$Version,[string]$Actor) {
    if($Version-cnotmatch'^\d+\.\d+\.\d+$'){throw 'RUNTIME_ACTOR_VERSION'}
    $path=Get-AiwContainedPath $FrameworkRoot ('framework/versions/'+$Version+'/scripts/ProcessRequirementComposition.psm1')
    $module=@(Import-Module $path -PassThru -ErrorAction Stop)[0]
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
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [switch]$CreateOnly
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent
    }
    $temporary = $Path + '.aiw-tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Move($temporary, $Path, (-not $CreateOnly))
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

function Write-AiwBoundTransactionState($Path, $Value, [ref]$ExpectedIdentity) {
    if((Get-AiwCurrentIdentity $Path)-cne$ExpectedIdentity.Value){throw 'TRANSACTION_STATE_DRIFT'}
    Write-AiwTransactionState $Path $Value
    $ExpectedIdentity.Value=Get-AiwCurrentIdentity $Path
}

function Get-AiwPreviousTransactionBytes($State) {
    $present=if($State-is[Collections.IDictionary]){$State.Contains('previousTransaction')}else{$null-ne$State.PSObject.Properties['previousTransaction']}
    if(-not$present){return $null}
    $previous=$State.previousTransaction
    if($previous.identity-ceq'MISSING'){
        if($previous.base64-cne''-or$previous.rollbackHistoryRelativePath-cnotmatch'^\.ai-workspace/upgrade-recovery/project-adoption/rollback/[a-f0-9]{32}/state\.json$'){throw 'PREVIOUS_TRANSACTION_MISSING_PROOF'}
        return $null
    }
    $bytes=[Convert]::FromBase64String([string]$previous.base64)
    if((Get-AiwByteIdentity $bytes)-cne$previous.identity){throw 'PREVIOUS_TRANSACTION_IDENTITY'}
    $value=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)|ConvertFrom-Json -Depth 100
    if($value.schemaVersion-ne1-or$value.repositoryRoot-cne$State.repositoryRoot-or
       $value.transactionRelativePath-cne$State.transactionRelativePath-or
       $value.transactionComplete-isnot[bool]-or-not$value.transactionComplete-or$value.state-cnotin@('COMPLETE','ROLLED_BACK')){
        throw 'PREVIOUS_TRANSACTION_BINDING'
    }
    return ,$bytes
}

function Complete-AiwRollbackJournal($Path, $State, [ref]$ExpectedIdentity, [switch]$InterruptAfterHistory) {
    $previous=Get-AiwPreviousTransactionBytes $State
    if($null-ne$previous){
        # Restore the journal last: before this atomic replacement, the pending
        # transaction retains both the projection and the prior proof for retry.
        if((Get-AiwCurrentIdentity $Path)-cne$ExpectedIdentity.Value){throw 'TRANSACTION_STATE_DRIFT'}
        Write-AiwAtomicBytes $Path $previous
        $ExpectedIdentity.Value=Get-AiwCurrentIdentity $Path
    }elseif($(if($State-is[Collections.IDictionary]){$State.Contains('previousTransaction')}else{$null-ne$State.PSObject.Properties['previousTransaction']})-and$State.previousTransaction.identity-ceq'MISSING'){
        # Persist the retry point on the original transaction before saving its
        # terminal bytes. A crash after history is saved can finish this same
        # plan; the old resolver must finally observe the original absence.
        $history=Get-AiwContainedPath $State.repositoryRoot $State.previousTransaction.rollbackHistoryRelativePath
        if((Get-AiwCurrentIdentity $Path)-cne$ExpectedIdentity.Value){throw 'TRANSACTION_STATE_DRIFT'}
        $State.state='ROLLING_BACK';$State.transactionComplete=$false
        Write-AiwBoundTransactionState $Path $State $ExpectedIdentity
        $closed=$State|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $closed.state='ROLLED_BACK';$closed.transactionComplete=$true
        $bytes=$script:Utf8NoBom.GetBytes(($closed|ConvertTo-Json -Depth 64 -Compress)+"`n")
        $identity=Get-AiwByteIdentity $bytes
        $existing=Get-AiwCurrentIdentity $history
        if($existing-ceq'MISSING'){
            Write-AiwAtomicBytes $history $bytes -CreateOnly
        }elseif($existing-cne$identity){throw 'ROLLBACK_HISTORY_DRIFT'}
        if((Get-AiwCurrentIdentity $history)-cne$identity){throw 'ROLLBACK_HISTORY_READBACK'}
        try{
            if($InterruptAfterHistory){throw 'ROLLBACK_JOURNAL_RETIRE_INTERRUPTED'}
            if((Get-AiwCurrentIdentity $Path)-cne$ExpectedIdentity.Value){throw 'TRANSACTION_STATE_DRIFT'}
            [IO.File]::Delete($Path)
            if((Get-AiwCurrentIdentity $Path)-cne'MISSING'){throw 'ROLLBACK_JOURNAL_RETIRE_FAILED'}
        }catch{$_.Exception.Data['AIW_ROLLBACK_HISTORY_SAVED']=$true;throw}
        $ExpectedIdentity.Value='MISSING'
    }else{
        # Older journals without an explicit absence preimage cannot acquire
        # deletion authority from their missing previousTransaction field.
        $State.state='ROLLED_BACK';$State.transactionComplete=$true
        Write-AiwBoundTransactionState $Path $State $ExpectedIdentity
    }
}

function Write-AiwCommittedTransactionState($Path, $State, [ref]$ExpectedIdentity) {
    # Keep the in-memory preimage until the commit write succeeds; an I/O
    # failure must still be able to restore the prior journal in the catch path.
    $closed=[ordered]@{}
    if($State-is[Collections.IDictionary]){
        foreach($key in $State.Keys){if($key-cne'previousTransaction'){$closed[$key]=$State[$key]}}
    }else{
        foreach($property in $State.PSObject.Properties){if($property.Name-cne'previousTransaction'){$closed[$property.Name]=$property.Value}}
    }
    Write-AiwBoundTransactionState $Path $closed $ExpectedIdentity
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
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode WRITE
try {


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

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
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
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode WRITE
try {


    $root = Assert-AiwProjectionContract $RepositoryRoot $Projection
    $transactionPath = Assert-AiwProjectionTransactionPath $root $TransactionRelativePath

    if ([bool]$Projection.noOp) {
        return [pscustomobject]@{ status = 'NO_CHANGE'; transactionCreated = $false; writes = 0 }
    }
    $journalIdentity=Get-AiwCurrentIdentity $transactionPath
    if($journalIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-and$journalIdentity-cne'MISSING'){throw 'TRANSACTION_STATE_SCHEMA'}
    $previousTransaction=$null
    if($Metadata.ContainsKey('operation')-and$Metadata.operation-cin@('UPGRADE_SNAPSHOT12_TO_2','UPGRADE_FORMAT_TRANSITION')){
        $previousTransaction=[ordered]@{identity='MISSING';base64='';rollbackHistoryRelativePath=('.ai-workspace/upgrade-recovery/project-adoption/rollback/'+[guid]::NewGuid().ToString('N')+'/state.json')}
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
        $previousTransaction=[ordered]@{identity=$existing.Identity;base64=[Convert]::ToBase64String($existing.Bytes)}
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
    if($null-ne$previousTransaction){$state.previousTransaction=$previousTransaction;$null=Get-AiwPreviousTransactionBytes $state}
    Write-AiwBoundTransactionState $transactionPath $state ([ref]$journalIdentity)
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
            Write-AiwBoundTransactionState $transactionPath $state ([ref]$journalIdentity)
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
            Write-AiwBoundTransactionState $transactionPath $state ([ref]$journalIdentity)
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
        # Closed transactions cannot be rolled back. Discard this temporary
        # preimage at commit so successive refreshes do not nest journal copies.
        Write-AiwCommittedTransactionState $transactionPath $state ([ref]$journalIdentity)
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
            $majorRollback=$Metadata.ContainsKey('operation')-and$Metadata.operation-cin@('UPGRADE_SNAPSHOT12_TO_2','UPGRADE_FORMAT_TRANSITION')
            if((Get-AiwCurrentIdentity $transactionPath)-cne$journalIdentity){throw 'TRANSACTION_STATE_DRIFT'}
            if($majorRollback){$state.state='ROLLING_BACK';$state.transactionComplete=$false;Write-AiwBoundTransactionState $transactionPath $state ([ref]$journalIdentity)}
            Restore-AiwProjectProjection $root $Projection @($createdDirectories) $RollbackPostcheck -ReverseWriteOrder:$majorRollback
            $state.failure = $failure
            Complete-AiwRollbackJournal $transactionPath $state ([ref]$journalIdentity)
            if($InterruptAfterWrite-ge0-and[int]$state.completedWrites-ge$InterruptAfterWrite){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
        }
        catch {
            if($_.Exception.Data.Contains('AIW_ROLLBACK_HISTORY_SAVED')){throw ('ROLLBACK_BLOCKED|'+[string]$_.Exception.Message)}
            $state.state = 'ROLLBACK_BLOCKED'
            $state.transactionComplete = $false
            $state.failure = $failure
            $state.rollbackFailure = [string]$_.Exception.Message
            Write-AiwBoundTransactionState $transactionPath $state ([ref]$journalIdentity)
            if($InterruptAfterWrite-ge0-and[int]$state.completedWrites-ge$InterruptAfterWrite){return [pscustomobject]@{status='INTERRUPTED';transactionCreated=$true;writes=$state.completedWrites}}
            throw ('ROLLBACK_BLOCKED|' + $state.rollbackFailure)
        }
        throw ('TRANSACTION_ROLLED_BACK|' + $failure)
    }

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}

function Resume-AiwProjectProjectionRollback {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$TransactionRelativePath,
        [Parameter(Mandatory)][string]$ExpectedTransactionIdentity,
        [Parameter(Mandatory)][scriptblock]$RollbackPostcheck,
        [switch]$InterruptAfterRollbackHistory
    )
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode WRITE
try {


    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $transactionPath = Assert-AiwProjectionTransactionPath $root $TransactionRelativePath
    if ((Get-AiwCurrentIdentity $transactionPath) -cne $ExpectedTransactionIdentity) {
        throw 'TRANSACTION_STATE_DRIFT'
    }

    $record = Read-AiwProjectJson $transactionPath 'TRANSACTION_STATE'
    $state = $record.Value
    $journalIdentity=$record.Identity
    if ($state.schemaVersion -ne 1 -or
        [string]$state.repositoryRoot -cne $root -or
        [string]$state.transactionRelativePath -cne $TransactionRelativePath -or
        $state.transactionComplete -isnot [bool]) {
        throw 'TRANSACTION_STATE_SCHEMA'
    }
    if ([bool]$state.transactionComplete) {
        return [pscustomobject]@{ status = [string]$state.state; changed = $false }
    }
    $null=Get-AiwPreviousTransactionBytes $state
    foreach($entry in $state.projection.objects){
        $current=Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path)
        if($current-cnotin@($entry.oldIdentity,$entry.newIdentity)){throw ('ROLLBACK_OBJECT_DRIFT|'+$entry.path)}
    }

    $majorRollback=$null-ne$state.metadata.PSObject.Properties['operation']-and$state.metadata.operation-cin@('UPGRADE_SNAPSHOT12_TO_2','UPGRADE_FORMAT_TRANSITION')
    if($majorRollback){$state.state='ROLLING_BACK';Write-AiwBoundTransactionState $transactionPath $state ([ref]$journalIdentity)}
    Restore-AiwProjectProjection $root $state.projection @($state.createdDirectories) $RollbackPostcheck -ReverseWriteOrder:$majorRollback
    Complete-AiwRollbackJournal $transactionPath $state ([ref]$journalIdentity) -InterruptAfterHistory:$InterruptAfterRollbackHistory
    [pscustomobject]@{
        status = 'ROLLED_BACK'
        changed = $true
        transactionIdentity = Get-AiwCurrentIdentity $transactionPath
    }

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
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
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode $(if($Apply-and(Read-AiwProjectJson $PlanPath "RULE_RECOVERY_PLAN").Value.schemaVersion-eq3){"PUBLICATION"}elseif($Apply){"WRITE"}else{"OBSERVE"})
try {

    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $planDoc=Read-AiwProjectJson $PlanPath 'RULE_RECOVERY_PLAN'
    if($planDoc.Identity-cne$ExpectedPlanIdentity){throw 'RULE_RECOVERY_PLAN_DRIFT'}
    $plan=$planDoc.Value
    if($plan.schemaVersion-eq3){
        return Invoke-AiwProjectSourcePublicationRecovery -RepositoryRoot $root -PlanDocument $planDoc -ObservedActor $ObservedActor -Direction $Direction -Apply:$Apply -InterruptAfterWrite $InterruptAfterWrite
    }
    if($plan.schemaVersion-eq2){
        return Invoke-AiwProjectSourceActionRecovery -RepositoryRoot $root -Plan $plan -ExpectedPlanIdentity $ExpectedPlanIdentity -ObservedActor $ObservedActor -Direction $Direction -Apply:$Apply -InterruptAfterWrite $InterruptAfterWrite
    }
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
    if([int]$receipt.schemaVersion-in@(2,3)){
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
    if([int]$admit.schemaVersion-notin@(1,2,3)-or[string]$admit.mode-cne'ADMIT_ACTION'-or
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
    if($admit.schemaVersion-eq3){
        $decisionModule=@(Import-Module (Join-Path $receipt.sourceLocators.frameworkRoot ('framework/versions/'+$package.frameworkVersion+'/scripts/ProcessRequirementComposition.psm1')) -PassThru -ErrorAction Stop)[0]
        $decision=& $decisionModule.ExportedCommands['Get-AiwProcessDecisionIdentity'] $receipt $admit
    }
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
    if($admit.schemaVersion-eq3){$finalInput.schemaVersion=3;$finalInput.evidenceRefs=@($admit.evidenceRefs)}
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

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
Export-ModuleMember -Function Invoke-AiwProjectRuleActionRecovery



function Invoke-AiwProjectSourcePublicationRecovery {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$PlanDocument,[Parameter(Mandatory)][string]$ObservedActor,[ValidateSet('COMPLETE','ROLLBACK')][string]$Direction='COMPLETE',[switch]$Apply,[int]$InterruptAfterWrite=-1)
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    if((Get-AiwCurrentIdentity $PlanDocument.Path)-cne$PlanDocument.Identity){throw 'SOURCE_PUBLICATION_RECOVERY_PLAN_DRIFT'}
    $publication=@(Import-Module (Join-Path $PSScriptRoot '../framework/versions/2.0.0/scripts/ProjectSourcePublication.psm1') -PassThru -ErrorAction Stop)[0]
    # Existing journals belong to the original fixed transaction protocol.
    # New batches never create, replace or archive that journal.
    $journalPath=Get-AiwContainedPath $root '.ai-workspace/upgrade-recovery/project-rules/source-publication/state.json'
    if(Test-Path -LiteralPath $journalPath -PathType Leaf){
        $saved=(Read-AiwProjectJson $journalPath 'SOURCE_PUBLICATION_JOURNAL').Value
        if($saved.recoveryRef.identity-ceq$PlanDocument.Identity){throw 'SOURCE_PUBLICATION_EXISTING_JOURNAL_USE_ORIGINAL_FIXED_TOOL'}
        if($saved.state-cnotin@('COMPLETE','ROLLED_BACK')){throw 'SOURCE_PUBLICATION_OTHER_ACTIVE_TRANSACTION_USE_ORIGINAL_FIXED_TOOL'}
    }
    $recovery=$PlanDocument.Value
    $original=& $publication {param($r,$p) Get-PubRecoveryOriginalFacts $r $p} $root $recovery
    $plan=$original.plan;$proof=$original.proof;$state=$proof.reachable
    if($ObservedActor-cne$plan.actor-or[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')-cne$ObservedActor){throw 'SOURCE_PUBLICATION_HOST_ACTOR_DRIFT'}
    if([IO.Path]::GetFullPath($PSScriptRoot)-cne[IO.Path]::GetFullPath((Join-Path $plan.frameworkRoot 'scripts'))){throw 'SOURCE_PUBLICATION_ORIGINAL_FIXED_TOOL_REQUIRED'}
    $composer=@(Import-Module (Join-Path $plan.frameworkRoot 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
    $completed=@{}
    foreach($member in @('SOURCE','CONTROL')){
        foreach($outcome in @('COMPLETE','ROLLBACK')){
            $inputPath=$original.admissions[$member].refs.finalizeInputRef.path+'.publication-'+$outcome.ToLowerInvariant()+'-input.json'
            $outputPath=$inputPath+'.result.json'
            if(Test-Path -LiteralPath $outputPath -PathType Leaf){
                $valid=& $publication {param($r,$p,$m,$i,$o,$direction) Test-PubOriginalFinalization $r $p $m $i $o $direction} $root $original $member $inputPath $outputPath $outcome
                if(-not$valid){throw 'SOURCE_PUBLICATION_SAVED_FINALIZATION_INVALID'}
                $completed[$member]=[pscustomobject]@{direction=$outcome;inputRef=[pscustomobject]@{path=$inputPath;identity=(Get-AiwCurrentIdentity $inputPath)};outputRef=[pscustomobject]@{path=$outputPath;identity=(Get-AiwCurrentIdentity $outputPath)}}
            }
        }
    }
    if($completed.Count-and@($completed.Values|Where-Object direction -CNE $Direction).Count){throw 'SOURCE_PUBLICATION_FORMAL_RESULT_NO_REVERSE'}
    if($completed.Count-and(($Direction-ceq'COMPLETE'-and-not$state.allNew)-or($Direction-ceq'ROLLBACK'-and-not$state.allOld))){throw 'SOURCE_PUBLICATION_COMPLETED_MEMBER_GROUP_DRIFT'}
    if(-not$Apply){return [pscustomobject]@{status='WHAT_IF';direction=$Direction;prefix=$state.prefix;writeOrder=@($plan.writeOrder);completedMembers=@($completed.Keys|Sort-Object);authorityGranted=$false;validationScope='ORIGINAL_DECISIONS_AND_CURRENT_GROUP';recoveryActivated=$false}}
    $needsWrites=($Direction-ceq'COMPLETE'-and-not$state.allNew)-or($Direction-ceq'ROLLBACK'-and-not$state.allOld)
    if(-not$needsWrites-and$completed.Count-eq2){
        # Both saved decisions need current complete validation before reuse.
        # When a decision is pending its real FINALIZE performs this check;
        # real writes validate inside SetContext under the owned guard.
        $boundary=$original.admissions.SOURCE.input|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $boundary.preparationReceipts=@($boundary.preparationReceipts)+@('PROJECT_SOURCE_PUBLICATION_ADMISSIONS|'+$PlanDocument.Path+'|'+$PlanDocument.Identity)
        $null=& $composer.ExportedCommands['Get-AiwProjectSourcePublicationCandidate'] $original.receipts.SOURCE $boundary $recovery.candidateRef RECOVERY -Rollback:($Direction-ceq'ROLLBACK')
    }
    $writes=0;$lease=$null
    try{
        if($needsWrites){
            $lease=Enter-AiwRootProjectSourceScope -ProjectRoot $root -Mode PUBLICATION
            $proof=& $publication.ExportedCommands['Set-AiwProjectSourcePublicationContext'] $lease $recovery
            $state=& $publication.ExportedCommands['Get-AiwProjectSourcePublicationReachability'] $root $plan $proof.facts.CONTROL.eligibility.forbidden
            while(($Direction-ceq'COMPLETE'-and-not$state.allNew)-or($Direction-ceq'ROLLBACK'-and-not$state.allOld)){
                if($InterruptAfterWrite-eq0-or($InterruptAfterWrite-ge0-and$writes-ge$InterruptAfterWrite)){throw 'SOURCE_PUBLICATION_INJECTED_INTERRUPTION'}
                Assert-AiwPublicationRootOriginals $root $PlanDocument $proof
                $index=if($Direction-ceq'COMPLETE'){$state.prefix}else{$state.prefix-1};$relative=$plan.writeOrder[$index]
                $object=@($plan.objects|Where-Object path -CEQ $relative)[0]
                $desired=if($Direction-ceq'COMPLETE'){$object.postimage}else{$object.preimage}
                $expected=if($Direction-ceq'COMPLETE'){$object.preimage.identity}else{$object.postimage.identity}
                $path=Get-AiwContainedPath $root $relative;$live=Get-AiwCurrentIdentity $path;if($live-ceq'MISSING'){$live='NEW'}
                if($live-cne$expected){throw 'SOURCE_PUBLICATION_WRITE_PREIMAGE_DRIFT'}
                if($desired.identity-ceq'NEW'){
                    if($Direction-cne'ROLLBACK'-or$object.preimage.identity-cne'NEW'){throw 'SOURCE_PUBLICATION_DELETE_DENIED'}
                    [IO.File]::Delete($path)
                }else{
                    if((Get-AiwCurrentIdentity $desired.path)-cne$desired.identity){throw 'SOURCE_PUBLICATION_FROZEN_BYTES_DRIFT'}
                    Write-AiwAtomicBytes $path ([IO.File]::ReadAllBytes($desired.path))
                }
                $readback=Get-AiwCurrentIdentity $path;if($readback-ceq'MISSING'){$readback='NEW'}
                if($readback-cne$desired.identity){throw 'SOURCE_PUBLICATION_OBJECT_READBACK'}
                $writes++
                $state=& $publication.ExportedCommands['Get-AiwProjectSourcePublicationReachability'] $root $plan $proof.facts.CONTROL.eligibility.forbidden
            }
        }
    }finally{Exit-AiwRootProjectSourceScope $lease}
    # Each distinct result remains durable before another side can fail. The
    # two pending decisions can share one actual private compiler invocation.
    $pairToken='PROJECT_SOURCE_PUBLICATION_ADMISSIONS|'+$PlanDocument.Path+'|'+$PlanDocument.Identity
    $core=@(Import-Module (Join-Path $plan.frameworkRoot 'framework/versions/2.0.0/scripts/ProcessRequirementBoundary.psm1') -PassThru -ErrorAction Stop)[0]
    $pending=@{};$validations=[Collections.Generic.List[object]]::new()
    foreach($member in @('SOURCE','CONTROL')){
        if($completed.ContainsKey($member)){
            $validations.Add([pscustomobject]@{member=$member;inputRef=$completed[$member].inputRef;outputRef=$completed[$member].outputRef});continue
        }
        $final=$original.admissions[$member].finalize|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $final.preparationReceipts=@($final.preparationReceipts)+@($pairToken)
        if($Direction-ceq'ROLLBACK'){
            $final.preparationReceipts=@($final.preparationReceipts|Where-Object{$_-cne'PROJECT_SOURCE_ROLLBACK'})+@('PROJECT_SOURCE_ROLLBACK')
            $final.resultReceipts=@($final.resultReceipts|Where-Object{$_-cnotlike'OBJECT_POSTIMAGE|*'})+@($plan.objects|Where-Object{$_.ownerMember-ceq$member-and$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.preimage.identity-ceq'NEW'){'MISSING'}else{$_.preimage.identity})})
            $final.evidenceRefs=@()
        }
        $inputPath=$original.admissions[$member].refs.finalizeInputRef.path+'.publication-'+$Direction.ToLowerInvariant()+'-input.json'
        $bytes=$script:Utf8NoBom.GetBytes(($final|ConvertTo-Json -Depth 100)+[char]10)
        if(Test-Path -LiteralPath $inputPath){
            if((Get-AiwCurrentIdentity $inputPath)-cne(Get-AiwByteIdentity $bytes)){throw 'SOURCE_PUBLICATION_FINAL_INPUT_DRIFT'}
        }else{Write-AiwAtomicBytes $inputPath $bytes}
        $pending[$member]=$inputPath
    }
    $resultState=[pscustomobject]@{root=$root;original=$original;direction=$Direction;publication=$publication;validations=$validations}
    $saveResult={
        param($member,$inputPath,$response,$state)
        $raw=[string]::Join([Environment]::NewLine,@($response.output));$result=$null
        try{$result=$raw|ConvertFrom-Json -Depth 100}catch{}
        $outputPath=$inputPath+'.result.json'
        $expected=if($state.direction-ceq'COMPLETE'){'COMPLETED'}else{'ROLLED_BACK'}
        if($response.exitCode-ne0-or$null-eq$result-or$null-eq$result.PSObject.Properties['projectSourcePreparation']-or$result.status-cne'PASS'-or$result.projectSourcePreparation.outcome-cne$expected-or$result.actionOutcome-cne'OBSERVED'){
            $failed=$inputPath+'.'+[guid]::NewGuid().ToString('N')+'.failed.json';Write-AiwAtomicBytes $failed ($script:Utf8NoBom.GetBytes($raw+[char]10))
            throw ('SOURCE_PUBLICATION_ORIGINAL_FINALIZE_FAILED|'+$member+'|'+$failed+'|'+$raw)
        }
        Write-AiwAtomicBytes $outputPath ($script:Utf8NoBom.GetBytes($raw+[char]10))
        if(-not(& $state.publication {param($r,$p,$m,$i,$o,$d) Test-PubOriginalFinalization $r $p $m $i $o $d} $state.root $state.original $member $inputPath $outputPath $state.direction)){throw 'SOURCE_PUBLICATION_FINAL_RESULT_READBACK'}
        $state.validations.Add([pscustomobject]@{member=$member;inputRef=[pscustomobject]@{path=$inputPath;identity=(Get-AiwCurrentIdentity $inputPath)};outputRef=[pscustomobject]@{path=$outputPath;identity=(Get-AiwCurrentIdentity $outputPath)}})
    }
    if($pending.Count-eq2){
        $parameters=@{InputPath=$pending.CONTROL;PublicationSourceInputPath=$pending.SOURCE;ExpectedPublicationSourceInputIdentity=(Get-AiwCurrentIdentity $pending.SOURCE);AsJson=$true}
        # This optional structure came from this call's actual owned write
        # validation. The paired consumer still obtains current member facts
        # and each live binding; no earlier authority is used as live authority.
        if($needsWrites){$parameters.PreparedTargets=$proof.targets}
        $response=& $publication {
            param($owner,$parameters,$observer,$state)
            Invoke-PubClosureObservationScope -Body {
                param($owner,$parameters,$observer,$state)
                & $owner {param($parameters,$observer,$state) Invoke-AiwPublicationBoundaryPairCore @parameters -OnMemberResult $observer -MemberResultState $state} $parameters $observer $state
            } -Arguments @($owner,$parameters,$observer,$state)
        } $core $parameters $saveResult $resultState
        if($response.exitCode-ne0){
            $raw=[string]::Join([Environment]::NewLine,@($response.output));$failure=$raw|ConvertFrom-Json -Depth 100
            $failed=$pending.SOURCE+'.group.'+[guid]::NewGuid().ToString('N')+'.failed.json';Write-AiwAtomicBytes $failed ($script:Utf8NoBom.GetBytes($raw+[char]10))
            throw ('SOURCE_PUBLICATION_ORIGINAL_FINALIZE_FAILED|'+$failure.failedMember+'|'+$failed+'|'+$raw)
        }
    }else{
        foreach($member in @('SOURCE','CONTROL')){
            if(-not$pending.ContainsKey($member)){continue}
            $response=& $core.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $pending[$member] -AsJson
            & $saveResult $member $pending[$member] $response $resultState
        }
    }
    $validations=$resultState.validations.ToArray()
    $last=& $publication {param($r,$p) Get-PubRecoveryOriginalFacts $r $p} $root $recovery
    if(($Direction-ceq'COMPLETE'-and-not$last.proof.reachable.allNew)-or($Direction-ceq'ROLLBACK'-and-not$last.proof.reachable.allOld)){throw 'SOURCE_PUBLICATION_FINAL_GROUP_DRIFT'}
    return [pscustomobject]@{status=$(if($Direction-ceq'COMPLETE'){'COMPLETE'}else{'ROLLED_BACK'});validations=$validations;writes=$writes;authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}
}

function ConvertTo-AiwPublicationRootCanonical($Value){
    $module=Get-AiwAdoptionRuntimeModule (Split-Path -Parent $PSScriptRoot) 'framework/versions/2.0.0/scripts/ContentSources.psm1' @('ConvertTo-AiwContentCanonicalJson')
    return & $module.ExportedCommands['ConvertTo-AiwContentCanonicalJson'] $Value
}
function Assert-AiwPublicationRootOriginals([string]$Root,$PlanDocument,$Proof){
    if((Get-AiwCurrentIdentity $PlanDocument.Path)-cne$PlanDocument.Identity-or(Get-AiwCurrentIdentity $Proof.planRef.path)-cne$Proof.planRef.identity-or(Get-AiwCurrentIdentity $Proof.candidateRef.path)-cne$Proof.candidateRef.identity){throw 'SOURCE_PUBLICATION_ORIGINALS_DRIFT'}
    $plan=$Proof.facts.plan
    if((Get-AiwCurrentIdentity (Get-AiwContainedPath $Root $plan.taskPath))-cne$plan.taskIdentity-or(Get-AiwCurrentIdentity (Get-AiwContainedPath $Root '.ai-workspace/controller.json'))-cne$plan.controllerIdentity){throw 'SOURCE_PUBLICATION_AUTHORITY_DRIFT'}
    foreach($dependency in $plan.rootToolDependencies){if((Get-AiwCurrentIdentity (Join-Path $plan.frameworkRoot $dependency.path))-cne$dependency.identity){throw 'SOURCE_PUBLICATION_FIXED_TOOL_DRIFT'}}
}

# Complete an already admitted TC3 archive action with a separately qualified
# fixed validator. This entry never projects, upgrades, rolls back or re-admits.
function Invoke-AiwOriginalTaskArchiveFinalize {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$ExpectedPlanIdentity,
        [Parameter(Mandatory)][string]$ObservedActor,[string[]]$ForbiddenPaths=@(),[switch]$Complete)
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $config=(Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'ARCHIVE_PROJECT').Value
    if($config.id-cne$ProjectId-or$config.frameworkVersion-cne'2.0.0'){throw 'ORIGINAL_ARCHIVE_PROJECT'}
    $excluded=@($ForbiddenPaths)+@($config.routineExcludedPaths)
    if($null-ne$config.PSObject.Properties['frameworkTarget']){$excluded+=@($config.frameworkTarget.routineExcludedPaths)}
    $retained=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $stateModule=@(Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -PassThru -ErrorAction Stop)[0]
    function Archive-Fields($Object,[string[]]$Fields,[string]$Label){
        # Reuse State's private structural validator within its owning module.
        & $stateModule {param($Object,$Fields,$Label) Assert-AiwAdoptionFields $Object $Fields $Label} $Object $Fields $Label
    }
    function Archive-Path([string]$Path,[switch]$ControlMaterial){
        if(-not[IO.Path]::IsPathRooted($Path)){throw 'ORIGINAL_ARCHIVE_ABSOLUTE_PATH'}
        $full=[IO.Path]::GetFullPath($Path)
        if(-not$full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ORIGINAL_ARCHIVE_PATH_SCOPE'}
        $relative=$full.Substring($root.Length+1).Replace('\','/')
        Assert-AiwRelativePath $relative
        foreach($f in $excluded){Assert-AiwRelativePath ([string]$f);if($relative.Equals($f,[StringComparison]::OrdinalIgnoreCase)-or$relative.StartsWith($f.TrimEnd('/')+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'ORIGINAL_ARCHIVE_PATH_FORBIDDEN'}}
        if($ControlMaterial-and-not$relative.StartsWith('.ai-workspace/',[StringComparison]::Ordinal)){throw 'ORIGINAL_ARCHIVE_MATERIAL_SCOPE'}
        return Get-AiwContainedPath $root $relative
    }
    function Archive-Ref($Reference,[string]$Label,[switch]$Raw){
        Archive-Fields $Reference @('path','identity') ('ARCHIVE_'+$Label)
        if($Reference.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ORIGINAL_ARCHIVE_REF_IDENTITY'}
        $file=Archive-Path $Reference.path -ControlMaterial
        $identity=Get-AiwCurrentIdentity $file
        if($identity-cne$Reference.identity){throw ('ORIGINAL_ARCHIVE_EVIDENCE_DRIFT|'+$Label)}
        $retained[$file]=$identity
        if($Raw){return $file}
        return (Read-AiwProjectJson $file ('ARCHIVE_'+$Label)).Value
    }
    $planFile=Archive-Path $PlanPath -ControlMaterial
    $planDoc=Read-AiwProjectJson $planFile 'ORIGINAL_ARCHIVE_PLAN'
    if($planDoc.Identity-cne$ExpectedPlanIdentity){throw 'ORIGINAL_ARCHIVE_PLAN_DRIFT'}
    $retained[$planFile]=$planDoc.Identity;$plan=$planDoc.Value
    Archive-Fields $plan @('schemaVersion','kind','originals','deletedTasks','completionDecisionRef','oldDistribution','newDistribution','rootToolRevision','rootToolDependencies','outputDirectory') 'ORIGINAL_ARCHIVE_PLAN'
    if($plan.schemaVersion-ne1-or$plan.kind-cne'ORIGINAL_TASK_ARCHIVE_FINALIZE'-or$plan.deletedTasks-isnot[Array]-or$plan.deletedTasks.Count-eq0){throw 'ORIGINAL_ARCHIVE_PLAN_SCHEMA'}
    Archive-Fields $plan.originals @('discoverReceipt','admitInput','admitResult','finalizeInput','finalizeResult','objects') 'ORIGINAL_ARCHIVE_ORIGINALS'
    $docs=@{discoverReceipt=(Archive-Ref $plan.originals.discoverReceipt 'discoverReceipt')}
    $receipt=$docs.discoverReceipt;$c=$receipt.binding;$intent=$receipt.intentEnvelope
    if($receipt.schemaVersion-ne3-or$receipt.inputContractVersion-ne4-or$receipt.status-cne'PASS'-or$receipt.mode-cne'DISCOVER'-or$receipt.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or$receipt.authorityGranted-ne$false-or$receipt.semanticCorrectnessProven-ne$false-or$intent.schemaVersion-ne2){throw 'ORIGINAL_ARCHIVE_RECEIPT'}
    $hash=(Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes(($c|ConvertTo-Json -Depth 30 -Compress)+"`n"+($intent|ConvertTo-Json -Depth 30 -Compress)))).Split('|')[1]
    if($hash-cne$receipt.contextIdentity-or$c.contextType-cne'TASK'-or$c.projectId-cne$ProjectId-or(Resolve-AiwRepositoryRoot $c.projectRoot)-cne$root-or$c.actor-cne$ObservedActor-or$c.taskOwner-cne$ObservedActor-or$c.frameworkVersion-cne'2.0.0'-or$intent.requestedActionKind-cne'CONTROL_WRITE'-or$intent.ambiguityState-cne'CLEAR'-or($null-ne$c.PSObject.Properties['continuationReceiptPath']-and$c.continuationReceiptPath-cne'NOT_REQUIRED')){throw 'ORIGINAL_ARCHIVE_CONTEXT'}
    if($env:CODEX_THREAD_ID-and$env:CODEX_THREAD_ID-cne$ObservedActor){throw 'ORIGINAL_ARCHIVE_HOST_ACTOR'}
    $excluded+=@($c.forbiddenScope)+@($c.protectedScope)
    # Revalidate every previously read material under the original protection.
    foreach($file in @($retained.Keys)){$null=Archive-Path $file -ControlMaterial}
    # Original receipt protection applies before the remaining originals are
    # opened, including caller-provided admission and object evidence paths.
    foreach($name in @('admitInput','admitResult','finalizeInput','finalizeResult','objects')){$docs[$name]=Archive-Ref $plan.originals.$name $name}
    $package=Archive-Ref ([pscustomobject]@{path=$receipt.sourceLocators.authorizationPackagePath;identity=$c.authorizationIdentity}) 'authorization'
    if($package.schemaVersion-notin@(1,2)-or($package.schemaVersion-eq2-and$package.repositoryId-cne'CONTROL')-or$package.lifecycle-cne'ACTIVE'-or$package.taskId-cne$c.taskId-or$package.taskIdentity-cne$c.taskIdentity-or$package.profile-cne$c.profile-or$package.owner-cne$c.taskOwner-or$package.grantee-cne$c.actor-or$package.projectConfigIdentity-cne$c.projectConfigIdentity-or$package.userConfirmation-cne$c.userDecision-or$package.delegatedGitCloser-ne$false){throw 'ORIGINAL_ARCHIVE_AUTHORIZATION'}
    foreach($field in @('continuationPlan','transitionPlan','repairReviewBinding','receiverBinding')){if($null-ne$package.PSObject.Properties[$field]){throw 'ORIGINAL_ARCHIVE_SINGLE_ACTION_REQUIRED'}}
    Assert-AiwAdoptionSame @($package.actions) @('CONTROL_WRITE') 'ARCHIVE_ACTION'
    Assert-AiwAdoptionSame @($package.exactPaths|Sort-Object) @($c.exactScope|Sort-Object) 'ARCHIVE_SCOPE'
    if($receipt.sourceLocators.taskRelativePath-cin$c.exactScope){throw 'ORIGINAL_ARCHIVE_CURRENT_TASK_MIXED_WRITE'}
    $controller=(Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/controller.json') 'ARCHIVE_CONTROLLER').Value
    if($controller.state-cne'CURRENT'-or$null-ne$controller.PSObject.Properties['transitionRef']){throw 'ORIGINAL_ARCHIVE_CONTROLLER_TRANSITION'}
    if($package.issuerRole-ceq'PROJECT_CONTROLLER'){
        if($package.issuer-cne$controller.controllerId-or$package.issuerControllerId-cne$controller.controllerId-or$package.issuerControllerEpoch-ne$controller.controllerEpoch-or$package.controllerControlIdentity-cne$c.controllerIdentity){throw 'ORIGINAL_ARCHIVE_CONTROLLER_BINDING'}
    }elseif($package.issuerRole-cne'TASK_OWNER'-or$package.issuer-cne$package.owner){throw 'ORIGINAL_ARCHIVE_ISSUER'}
    $old=Assert-AiwDistributionBinding $plan.oldDistribution $receipt.sourceLocators.frameworkRoot '2.0.0'
    $adopted=Get-AiwAdoptedDistributionBinding $root '2.0.0'
    Assert-AiwAdoptionSame $adopted $old 'ARCHIVE_OLD_ADOPTED_DISTRIBUTION'
    $newRoot=Resolve-AiwRepositoryRoot (Split-Path -Parent $PSScriptRoot)
    $new=Assert-AiwDistributionBinding $plan.newDistribution $newRoot '2.0.0'
    if($new.contentIdentity-ceq$old.contentIdentity-or$new.distributionId-ceq$old.distributionId){throw 'ORIGINAL_ARCHIVE_NEW_FIXED_TOOL_REQUIRED'}
    $versionPrefix='framework/versions/2.0.0/'
    $profile=(Read-AiwProjectJson (Get-AiwContainedPath $newRoot ($versionPrefix+'ADOPTION_PROFILE.json')) 'ARCHIVE_TOOL_PROFILE').Value
    $snapshot=Get-AiwLocalCandidateFrameworkSnapshot -FrameworkPath (Get-AiwContainedPath $newRoot 'framework/versions/2.0.0') -ExpectedVersion '2.0.0' -AdoptionProfile $profile
    $newManifest=(Read-AiwProjectJson (Get-AiwContainedPath $newRoot 'PACKAGE_MANIFEST.json') 'ARCHIVE_TOOL_PACKAGE').Value
    $oldManifest=(Read-AiwProjectJson (Get-AiwContainedPath $old.runtimeRoot 'PACKAGE_MANIFEST.json') 'ARCHIVE_OLD_PACKAGE').Value
    $releaseReader=@(Import-Module (Join-Path $PSScriptRoot '../framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
    $newQualification=& $releaseReader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot (Get-AiwContainedPath $newRoot $versionPrefix.TrimEnd('/')) -RuntimeRoot $newRoot
    $oldQualification=& $releaseReader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot (Get-AiwContainedPath $old.runtimeRoot $versionPrefix.TrimEnd('/')) -RuntimeRoot $old.runtimeRoot
    $newAttachments=@();$oldAttachments=@()
    if($newQualification.Manifest.schemaVersion-eq3){$newAttachments=@($newQualification.Proof.Bundle.Members.path|ForEach-Object{$versionPrefix+$_})}
    if($oldQualification.Manifest.schemaVersion-eq3){$oldAttachments=@($oldQualification.Proof.Bundle.Members.path|ForEach-Object{$versionPrefix+$_})}
    $runtimePaths=@($newManifest.files.path|Where-Object{($_.StartsWith($versionPrefix,[StringComparison]::Ordinal)-and-not$_.Contains('/tests/')-and($_.EndsWith('.ps1')-or$_.EndsWith('.psm1')-or$_.EndsWith('.json')-and-not$_.EndsWith('/RELEASE_MANIFEST.json')))-or$_-cin@('scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/MaintenanceOverlay.psm1','scripts/ProjectCorrectionLifecycle.psm1')})
    $oldRuntimePaths=@($oldManifest.files.path|Where-Object{($_.StartsWith($versionPrefix,[StringComparison]::Ordinal)-and-not$_.Contains('/tests/')-and($_.EndsWith('.ps1')-or$_.EndsWith('.psm1')-or$_.EndsWith('.json')-and-not$_.EndsWith('/RELEASE_MANIFEST.json')))-or$_-cin@('scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/MaintenanceOverlay.psm1','scripts/ProjectCorrectionLifecycle.psm1')})
    $runtimePaths=@($runtimePaths|Where-Object{$_-cnotin$newAttachments});$oldRuntimePaths=@($oldRuntimePaths|Where-Object{$_-cnotin$oldAttachments})
    Assert-AiwAdoptionSame @($runtimePaths|Sort-Object) @($oldRuntimePaths|Sort-Object) 'ARCHIVE_COMPATIBLE_DEPENDENCY_SET'
    $allowedDelta=@(($versionPrefix+'scripts/ResultEvidence.psm1'),($versionPrefix+'scripts/WorkflowDelivery.psm1'))
    $compatibility=@(foreach($path in $runtimePaths){
        $before=Get-AiwCurrentIdentity (Get-AiwContainedPath $old.runtimeRoot $path);$after=Get-AiwCurrentIdentity (Get-AiwContainedPath $newRoot $path)
        if($path-cnotin$allowedDelta-and$before-cne$after){throw ('ORIGINAL_ARCHIVE_INCOMPATIBLE_DEPENDENCY|'+$path)}
        [pscustomobject]@{path=$path;oldIdentity=$before;newIdentity=$after;changed=($before-cne$after)}
    })
    $dependencies=@($newManifest.files.path|Where-Object{$_.StartsWith($versionPrefix,[StringComparison]::Ordinal)-and-not$_.Contains('/tests/')-and$_-cnotin$newAttachments})
    $tool=Get-AiwRootToolRevision $newRoot (Get-AiwProjectAdoptionToolDependency UPGRADE $dependencies)
    if($plan.rootToolRevision-cne$tool.revision){throw 'ORIGINAL_ARCHIVE_ROOT_TOOL_REVISION'}
    Assert-AiwAdoptionSame @($plan.rootToolDependencies) @($tool.dependencies) 'ARCHIVE_ROOT_TOOL_DEPENDENCIES'
    $oldModule=@(Import-Module (Get-AiwContainedPath $old.runtimeRoot ($versionPrefix+'scripts/ProcessRequirementComposition.psm1')) -PassThru -ErrorAction Stop)[0]
    function Archive-Sources {
        $selectionArguments=Get-AiwAdoptionSelectionArguments $oldModule.ExportedFunctions['Get-AiwProcessBindingSnapshot'] $receipt
        $bindings=& $oldModule.ExportedFunctions['Get-AiwProcessBindingSnapshot'] -ProjectRoot $root -FrameworkRoot $old.runtimeRoot -TargetVersion '2.0.0' -TaskRelativePath $receipt.sourceLocators.taskRelativePath -ForbiddenPaths @($c.forbiddenScope) @selectionArguments
        foreach($field in $receipt.sourceBindings.PSObject.Properties){if($null-eq$bindings.PSObject.Properties[$field.Name]-or[string]$bindings.($field.Name)-cne[string]$field.Value){throw ('ORIGINAL_ARCHIVE_SOURCE_DRIFT|'+$field.Name)}}
    }
    Archive-Sources
    $a=$docs.admitInput;$ar=$docs.admitResult;$f=$docs.finalizeInput;$fr=$docs.finalizeResult
    foreach($pair in @(@($a,'ADMIT_ACTION'),@($f,'FINALIZE_OUTPUT'))){$inputValue=$pair[0];if($inputValue.schemaVersion-ne3-or$inputValue.mode-cne$pair[1]-or$inputValue.expectedDiscoverReceiptIdentity-cne$plan.originals.discoverReceipt.identity-or[IO.Path]::GetFullPath($inputValue.discoverReceiptPath)-cne[IO.Path]::GetFullPath($plan.originals.discoverReceipt.path)){throw 'ORIGINAL_ARCHIVE_BOUNDARY_INPUT'}}
    if($ar.status-cne'PASS'-or$ar.mode-cne'ADMIT_ACTION'-or$ar.selectionIdentity-cne$receipt.selectionIdentity-or@($ar.missingPreparation).Count-or@($ar.missingResult).Count){throw 'ORIGINAL_ARCHIVE_ADMISSION_REQUIRED'}
    $required=@($receipt.selectedObligations.preparationRequirements|Sort-Object -Unique)
    if(@($required|Where-Object{$_-cnotin$a.preparationReceipts}).Count){throw 'ORIGINAL_ARCHIVE_ADMISSION_PREPARATION'}
    $decision=& $oldModule.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $receipt $a
    if($decision-cne$ar.decisionIdentity){throw 'ORIGINAL_ARCHIVE_ADMISSION_DECISION'}
    if($fr.status-cne'FAIL'-or$fr.reason-cne'EVIDENCE_OBJECT_MISSING'){throw 'ORIGINAL_ARCHIVE_FAILURE_REQUIRED'}
    if($f.protectionState-cne$a.protectionState){throw 'ORIGINAL_ARCHIVE_PROTECTION_DRIFT'}
    $null=Archive-Ref $plan.completionDecisionRef 'current-human-completion-decision' -Raw
    # The caller verifies actual human provenance, scope and later withdrawal;
    # this raw identity deliberately does not claim to authenticate a person.
    $objects=$docs.objects
    if($objects-isnot[Array]-or$objects.Count-ne$c.exactScope.Count-or@($objects.path|Select-Object -Unique).Count-ne$objects.Count){throw 'ORIGINAL_ARCHIVE_OBJECT_SET'}
    Assert-AiwAdoptionSame @($objects.path|Sort-Object) @($c.exactScope|Sort-Object) 'ARCHIVE_OBJECT_SCOPE'
    function Archive-Objects {
        foreach($entry in $objects){
            Archive-Fields $entry @('path','operation','oldIdentity','newIdentity','candidatePath','activation') 'ORIGINAL_ARCHIVE_OBJECT'
            if($entry.operation-cnotin@('WRITE','DELETE_AFTER_ARCHIVE_AND_FULL_HISTORY_WRITTEN')-or$entry.activation-isnot[string]-or[string]::IsNullOrWhiteSpace($entry.activation)){throw 'ORIGINAL_ARCHIVE_OBJECT_OPERATION'}
            $relative=[string]$entry.path;Assert-AiwRelativePath $relative
            $live=Archive-Path (Join-Path $root $relative)
            $pre=@($package.objectIdentities|Where-Object{$_.path-ceq$relative})
            $oldIdentity=if($entry.oldIdentity-ceq'MISSING'){'NEW'}else{$entry.oldIdentity}
            if($pre.Count-ne1-or$pre[0].identity-cne$oldIdentity){throw 'ORIGINAL_ARCHIVE_OBJECT_PREIMAGE'}
            if($entry.newIdentity-cne'MISSING'-and$entry.newIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ORIGINAL_ARCHIVE_OBJECT_POSTIMAGE'}
            if((Get-AiwCurrentIdentity $live)-cne$entry.newIdentity){throw ('ORIGINAL_ARCHIVE_THIRD_PARTY_OBJECT|'+$relative)}
            if(@($f.resultReceipts|Where-Object{$_-ceq('OBJECT_POSTIMAGE|'+$relative+'|'+$entry.newIdentity)}).Count-ne1){throw 'ORIGINAL_ARCHIVE_FINAL_POSTIMAGE'}
            if($entry.newIdentity-ceq'MISSING'){
                if($entry.candidatePath-cne'NOT_APPLICABLE'-or$entry.operation-cne'DELETE_AFTER_ARCHIVE_AND_FULL_HISTORY_WRITTEN'){throw 'ORIGINAL_ARCHIVE_MISSING_CANDIDATE'}
            }else{if($entry.operation-cne'WRITE'){throw 'ORIGINAL_ARCHIVE_OBJECT_OPERATION'};$null=Archive-Ref ([pscustomobject]@{path=$entry.candidatePath;identity=$entry.newIdentity}) ('candidate-'+$relative) -Raw}
        }
        if(@($f.resultReceipts|Where-Object{$_-clike'OBJECT_POSTIMAGE|*'}).Count-ne$objects.Count){throw 'ORIGINAL_ARCHIVE_FINAL_POSTIMAGE_SET'}
        $deleted=@($objects|Where-Object{$_.newIdentity-ceq'MISSING'})
        if($deleted.Count-ne$plan.deletedTasks.Count-or@($plan.deletedTasks.activePath|Select-Object -Unique).Count-ne$deleted.Count){throw 'ORIGINAL_ARCHIVE_DELETE_SET'}
        foreach($link in $plan.deletedTasks){
            Archive-Fields $link @('activePath','archivePath','historyRef') 'ORIGINAL_ARCHIVE_DELETE'
            if($link.activePath-cnotmatch'^\.ai-workspace/tasks/active/(?<name>[^/]+)\.md$'){throw 'ORIGINAL_ARCHIVE_DELETE_PATH'}
            $name=$Matches.name
            if($link.archivePath-cne('.ai-workspace/tasks/archive/'+$name+'.md')){throw 'ORIGINAL_ARCHIVE_TARGET_PATH'}
            $from=@($deleted|Where-Object{$_.path-ceq$link.activePath});$to=@($objects|Where-Object{$_.path-ceq$link.archivePath})
            if($from.Count-ne1-or$from[0].oldIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$to.Count-ne1-or$to[0].newIdentity-ceq'MISSING'-or$link.historyRef.identity-cne$from[0].oldIdentity){throw 'ORIGINAL_ARCHIVE_DELETE_BINDING'}
            $null=Archive-Ref $link.historyRef ('history-'+$name) -Raw
            $archiveText=[IO.File]::ReadAllText((Archive-Path (Join-Path $root $link.archivePath)))
            $ids=[regex]::Matches($archiveText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
            if($ids.Count-ne1-or$ids[0].Groups['id'].Value-cne$name-or$archiveText-cnotmatch'(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;'){throw 'ORIGINAL_ARCHIVE_TARGET_CARD'}
        }
    }
    Archive-Objects
    $actorStorage=& $oldModule.ExportedFunctions['Get-AiwRuntimeActorStorageKey'] -Actor $ObservedActor
    $runtime=Get-AiwContainedPath $root ('.ai-workspace/runtime/'+$c.taskId+'/'+$actorStorage)
    $output=Archive-Path $plan.outputDirectory -ControlMaterial
    if([IO.Path]::GetDirectoryName($output)-cne$runtime-or[IO.Path]::GetFileName($output)-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]*$'-or(Test-Path -LiteralPath $output)){throw 'ORIGINAL_ARCHIVE_OUTPUT_DIRECTORY'}
    $resolver=Get-AiwContainedPath $newRoot ($versionPrefix+'scripts/resolve-process-requirements.ps1')
    $summary=[ordered]@{status='WHAT_IF';reason='ORIGINAL_ADMITTED_ARCHIVE_FINALIZED_WITH_COMPATIBLE_FIXED_TOOL';authorityGranted=$false;projectWritePerformed=$false;source='ORIGINAL_ADMISSION';taskId=$c.taskId;actor=$ObservedActor;exactPaths=@($c.exactScope);originalFailure=$plan.originals.finalizeResult;originalFinalize=$plan.originals.finalizeInput;completionDecisionRef=$plan.completionDecisionRef;oldDistribution=$old;newToolDistribution=$new;executionPath=$resolver;rootToolRevision=$tool.revision;rootToolDependencies=@($tool.dependencies);compatibleRuntimeDependencies=$compatibility;userAuthorizationProven=$false;evidenceGrade='INSTRUCTION_BOUND'}
    if(-not$Complete){return [pscustomobject]$summary}
    # The only created objects are fresh evidence. The original input is passed
    # unchanged to an isolated process importing the two new result modules.
    $null=[IO.Directory]::CreateDirectory($output)
    $started=[DateTime]::UtcNow
    $lines=@(& ([Environment]::ProcessPath) -NoProfile -NonInteractive -File $resolver -InputPath $plan.originals.finalizeInput.path -AsJson 2>&1|ForEach-Object{[string]$_});$exitCode=$LASTEXITCODE
    $rawPath=Join-Path $output 'finalize-output.txt';$raw=($lines-join"`n")+"`n"
    function Archive-Create([string]$Path,[byte[]]$Bytes){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($Bytes);$stream.Flush($true)}finally{$stream.Dispose()}}
    Archive-Create $rawPath ($script:Utf8NoBom.GetBytes($raw))
    $commandPath=Join-Path $output 'command.json'
    $command=[ordered]@{command=('pwsh -NoProfile -NonInteractive -File '+$resolver+' -InputPath '+$plan.originals.finalizeInput.path+' -AsJson');exitCode=$exitCode;output=[ordered]@{path=$rawPath;identity=(Get-AiwCurrentIdentity $rawPath)}}
    Archive-Create $commandPath ($script:Utf8NoBom.GetBytes(($command|ConvertTo-Json -Depth 20 -Compress)+"`n"))
    $summary.status='FAIL';$summary['commandRef']=[ordered]@{path=$commandPath;identity=(Get-AiwCurrentIdentity $commandPath)};$summary['startedUtc']=$started.ToString('o');$summary['endedUtc']=[DateTime]::UtcNow.ToString('o')
    try{
        foreach($file in @($retained.Keys)){if((Get-AiwCurrentIdentity $file)-cne$retained[$file]){throw 'ORIGINAL_ARCHIVE_EVIDENCE_CHANGED_DURING_FINALIZE'}}
        Archive-Sources;Archive-Objects
        $null=Assert-AiwDistributionBinding $old $old.runtimeRoot '2.0.0';$null=Assert-AiwDistributionBinding $new $newRoot '2.0.0'
        Import-Module (Get-AiwContainedPath $newRoot ($versionPrefix+'scripts/StrictJsonInput.psm1'))
        $actual=(ConvertFrom-AiwStrictInputJson ($lines-join"`n")).Value
        if($exitCode-ne0-or$actual.status-cne'PASS'-or$actual.mode-cne'FINALIZE_OUTPUT'-or$actual.selectionIdentity-cne$receipt.selectionIdentity){throw 'ORIGINAL_ARCHIVE_REAL_FINALIZE_FAILED'}
        $expectedDecision=& $oldModule.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $receipt $f
        if($actual.decisionIdentity-cne$expectedDecision){throw 'ORIGINAL_ARCHIVE_FINALIZE_DECISION'}
        $summary.status='PASS';$summary['finalizeResult']=$actual
    }catch{$summary.reason=$_.Exception.Message}
    $resultPath=Join-Path $output 'result.json';Archive-Create $resultPath ($script:Utf8NoBom.GetBytes(($summary|ConvertTo-Json -Depth 100 -Compress)+"`n"))
    return [pscustomobject]$summary
}
Export-ModuleMember -Function Invoke-AiwOriginalTaskArchiveFinalize

# Daily source adoption shares the ordinary process proof; this helper only
# resumes the two frozen carriers and invokes their original FINALIZE.
function Invoke-AiwProjectSourceActionRecovery {
    param([string]$RepositoryRoot,$Plan,[string]$ExpectedPlanIdentity,[string]$ObservedActor,[string]$Direction,[switch]$Apply,[int]$InterruptAfterWrite=-1)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode $(if($Apply){"WRITE"}else{"OBSERVE"})
try {

    $root=$RepositoryRoot
    $names=@('schemaVersion','discoverReceiptPath','discoverReceiptIdentity','admitInputPath','admitInputIdentity','admitResultPath','admitResultIdentity','preparationReceipts','resultReceipts','evidenceRefs','transactionRelativePath')
    if(@($Plan.PSObject.Properties).Count-ne$names.Count-or@($names|Where-Object{$_-cnotin$Plan.PSObject.Properties.Name}).Count-or$Plan.schemaVersion-ne2){throw 'SOURCE_RECOVERY_PLAN_SCHEMA'}
    foreach($name in @('preparationReceipts','resultReceipts','evidenceRefs')){if($Plan.$name-isnot[array]){throw 'SOURCE_RECOVERY_PLAN_ARRAY'}}
    $receiptDoc=Read-AiwProjectJson $Plan.discoverReceiptPath 'SOURCE_RECOVERY_DISCOVER'
    if($receiptDoc.Identity-cne$Plan.discoverReceiptIdentity){throw 'SOURCE_RECOVERY_DISCOVER_DRIFT'}
    $receipt=$receiptDoc.Value;$binding=$receipt.binding
    if($receipt.schemaVersion-ne3-or$binding.actor-cne$ObservedActor-or[IO.Path]::GetFullPath($binding.projectRoot)-cne$root){throw 'SOURCE_RECOVERY_CONTEXT'}
    $framework=$receipt.sourceLocators.frameworkRoot
    if(-not[IO.Path]::GetFullPath($PSScriptRoot).Equals([IO.Path]::GetFullPath((Join-Path $framework 'scripts')),[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_RECOVERY_ORIGINAL_ROOT_TOOL_REQUIRED'}
    # Reuse the exact fixed module without unloading its caller-visible exports.
    # The exported command remains bound to this module, not ambient lookup.
    $composer=@(Import-Module (Join-Path $framework 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru -ErrorAction Stop)[0]
    $validator=$composer.ExportedCommands['Get-AiwProjectSourceChange']
    if($null-eq$validator){throw 'SOURCE_RECOVERY_ORIGINAL_TOOL_REQUIRED'}
    $proof='PROJECT_SOURCE_ADMISSION|'+$Plan.admitInputPath+'|'+$Plan.admitInputIdentity+'|'+$Plan.admitResultPath+'|'+$Plan.admitResultIdentity
    if(@($Plan.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_ADMISSION|*'-or$_-ceq'PROJECT_SOURCE_ROLLBACK'}).Count){throw 'SOURCE_RECOVERY_RESERVED_RECEIPT'}
    $boundary=[ordered]@{schemaVersion=3;mode='FINALIZE_OUTPUT';discoverReceiptPath=$Plan.discoverReceiptPath;expectedDiscoverReceiptIdentity=$Plan.discoverReceiptIdentity;preparationReceipts=@($Plan.preparationReceipts)+@($proof);resultReceipts=@($Plan.resultReceipts);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($Plan.evidenceRefs)}
    if($Direction-ceq'ROLLBACK'){$boundary.preparationReceipts+='PROJECT_SOURCE_ROLLBACK'}
    $change=& $validator -Receipt $receipt -Boundary ([pscustomobject]$boundary) -Stage RECOVERY -Rollback:($Direction-ceq'ROLLBACK')
    if($null-eq$change){throw 'SOURCE_RECOVERY_CANDIDATE_REQUIRED'}
    $boundary.publicDecisionIdentity=$change.admission.input.publicDecisionIdentity;$boundary.protectionState=$change.admission.input.protectionState
    if($binding.repositoryGitTop-cne'NOT_APPLICABLE'){
        $top=@(& git -C $root rev-parse --show-toplevel 2>$null)
        if($LASTEXITCODE-ne0-or$top.Count-ne1-or[IO.Path]::GetFullPath($top[0])-cne[IO.Path]::GetFullPath($binding.repositoryGitTop)){throw 'SOURCE_RECOVERY_GIT_TOP'}
    }
    $transactionRelative=$Plan.transactionRelativePath;Assert-AiwRelativePath $transactionRelative
    $prefix='.ai-workspace/upgrade-recovery/project-rules/'+$binding.taskId+'/'
    if(-not$transactionRelative.StartsWith($prefix,[StringComparison]::Ordinal)-or-not$transactionRelative.EndsWith('/state.json',[StringComparison]::Ordinal)){throw 'SOURCE_RECOVERY_TRANSACTION_PATH'}
    $transactionPath=Get-AiwContainedPath $root $transactionRelative
    $saved=$null;$journalIdentity=Get-AiwCurrentIdentity $transactionPath
    $objects=@($change.candidate.objects|Where-Object{$_.preimage.identity-cne$_.postimage.identity})
    if($Direction-ceq'ROLLBACK'){[Array]::Reverse($objects)}
    $desired=@($objects|ForEach-Object{$side=if($Direction-ceq'COMPLETE'){'postimage'}else{'preimage'};[pscustomobject]@{path=$_.path;bytes=[IO.File]::ReadAllBytes($_.$side.path)}})
    Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionProjection.psm1') -ErrorAction Stop
    $projection=New-AiwProjectProjection $root $desired
    if($journalIdentity-cne'MISSING'){
        $saved=(Read-AiwProjectJson $transactionPath 'SOURCE_RECOVERY_TRANSACTION').Value
        if($saved.metadata.operation-cne'PROJECT_SOURCE_ACTION_RECOVERY'-or$saved.metadata.planIdentity-cne$ExpectedPlanIdentity-or$saved.metadata.admissionIdentity-cne$Plan.admitResultIdentity){throw 'SOURCE_RECOVERY_TRANSACTION_BINDING'}
        $null=Assert-AiwProjectionContract $root $saved.projection
        if(@($saved.projection.objects).Count-ne$objects.Count){throw 'SOURCE_RECOVERY_TRANSACTION_SCOPE'}
        foreach($entry in $saved.projection.objects){
            $original=@($change.candidate.objects|Where-Object path -CEQ $entry.path)
            if($original.Count-ne1-or$entry.oldIdentity-cnotin@($original[0].preimage.identity,$original[0].postimage.identity)-or$entry.newIdentity-cnotin@($original[0].preimage.identity,$original[0].postimage.identity)){throw 'SOURCE_RECOVERY_TRANSACTION_OBJECT'}
        }
        if($saved.transactionComplete-and($saved.metadata.direction-cne$Direction-or-not$projection.noOp)){throw 'SOURCE_RECOVERY_ALREADY_CLOSED'}
    }
    if(-not$Apply){return [pscustomobject]@{status='WHAT_IF';direction=$Direction;source='ORIGINAL_ADMISSION';changes=@(Get-AiwProjectProjectionDiff $projection);authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}}
    $runtime=Get-AiwContainedPath $root ('.ai-workspace/runtime/'+$binding.taskId+'/'+(Get-AiwBoundRuntimeActorStorageKey $framework '2.0.0' $ObservedActor))
    $null=[IO.Directory]::CreateDirectory($runtime)
    $resolver=Join-Path $framework 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'
    $config=$change.documents['.ai-workspace/project.json|preimage'].Value
    if($config.controlPlaneLayout-ceq'framework-maintenance-sibling'){$resolver=Join-Path $framework 'scripts/resolve-framework-maintenance-process-requirements.ps1'}
    $observation=@{}
    $postcheck={
        param($checkRoot,$checkProjection)
        $inputCopy=$boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $inputCopy.resultReceipts=@($inputCopy.resultReceipts|Where-Object{$_-cnotlike'OBJECT_POSTIMAGE|*'})
        foreach($entry in $objects){$inputCopy.resultReceipts+='OBJECT_POSTIMAGE|'+$entry.path+'|'+(Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))}
        $inputPath=Join-Path $runtime ('source-recovery-finalize-'+[guid]::NewGuid().ToString('N')+'.json')
        [IO.File]::WriteAllText($inputPath,($inputCopy|ConvertTo-Json -Depth 100)+[char]10,$script:Utf8NoBom)
        $raw=@(& $resolver -InputPath $inputPath -AsJson 2>&1|ForEach-Object{[string]$_})
        $observation.inputPath=$inputPath;$observation.inputIdentity=Get-AiwCurrentIdentity $inputPath
        $resultPath=$inputPath+'.result.json';[IO.File]::WriteAllText($resultPath,($raw-join[char]10)+[char]10,$script:Utf8NoBom)
        $observation.resultPath=$resultPath;$observation.resultIdentity=Get-AiwCurrentIdentity $resultPath
        if($LASTEXITCODE-ne0-or$raw.Count-ne1){throw ('SOURCE_RECOVERY_ORIGINAL_FINALIZE|'+($raw-join';'))}
        $result=$raw[0]|ConvertFrom-Json -Depth 100
        if($result.status-cne'PASS'){throw ('SOURCE_RECOVERY_ORIGINAL_FINALIZE|'+$raw[0])}
        return $true
    }
    $preflight={param($checkRoot,$checkProjection) $null=& $validator -Receipt $receipt -Boundary ([pscustomobject]$boundary) -Stage RECOVERY -Rollback:($Direction-ceq'ROLLBACK');return $true}
    # If a validation fails, the generic transaction restores its actual start
    # image. Revalidate that reachable group without requiring target access.
    $rollbackCheck={param($checkRoot,$checkProjection) $null=& $validator -Receipt $receipt -Boundary ([pscustomobject]$boundary) -Stage RECOVERY -Rollback;return $true}
    if($null-ne$saved-and-not$saved.transactionComplete){
        $null=& $preflight $root $projection
        $saved.projection=$projection;$saved.metadata.direction=$Direction;$saved.completedWrites=0;$saved.state='APPLYING'
        Write-AiwBoundTransactionState $transactionPath $saved ([ref]$journalIdentity)
        $writes=0
        foreach($entry in $projection.objects|Where-Object changed){
            if($InterruptAfterWrite-eq0){break}
            $path=Get-AiwContainedPath $root $entry.path
            if((Get-AiwCurrentIdentity $path)-cne$entry.oldIdentity){throw 'SOURCE_RECOVERY_OBJECT_DRIFT'}
            Write-AiwAtomicBytes $path ([Convert]::FromBase64String($entry.newBase64));$writes++;$saved.completedWrites=$writes
            Write-AiwBoundTransactionState $transactionPath $saved ([ref]$journalIdentity)
            if($InterruptAfterWrite-ge0-and$writes-ge$InterruptAfterWrite){break}
        }
        if($InterruptAfterWrite-ge0-and($writes-ge$InterruptAfterWrite-or$writes-lt$projection.changeCount)){return [pscustomobject]@{status='INTERRUPTED';direction=$Direction;transactionIdentity=Get-AiwCurrentIdentity $transactionPath}}
        $null=& $postcheck $root $projection
        $saved.state='COMPLETE';$saved.transactionComplete=$true;Write-AiwCommittedTransactionState $transactionPath $saved ([ref]$journalIdentity)
    }elseif($projection.noOp){$null=& $postcheck $root $projection}
    else{
        $run=Invoke-AiwProjectProjectionTransaction $root $projection $transactionRelative $postcheck $rollbackCheck -Preflight $preflight -InterruptAfterWrite $InterruptAfterWrite -Metadata @{operation='PROJECT_SOURCE_ACTION_RECOVERY';planIdentity=$ExpectedPlanIdentity;direction=$Direction;origin='RECOVERY_CREATED_NOW_FROM_ORIGINAL_ADMISSION';admissionIdentity=$Plan.admitResultIdentity}
        if($run.status-ceq'INTERRUPTED'){return [pscustomobject]@{status='INTERRUPTED';direction=$Direction;transactionIdentity=Get-AiwCurrentIdentity $transactionPath}}
    }
    return [pscustomobject]@{status=$(if($Direction-ceq'COMPLETE'){'COMPLETED'}else{'ROLLED_BACK'});originalActionFinalized=$true;finalizeEvidence=$observation;transactionPath=$transactionPath;transactionIdentity=Get-AiwCurrentIdentity $transactionPath;authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
function Assert-AiwRuntimeAdoptionProjection {
    param([string]$Root,$Projection,[string]$VersionRoot,[string]$Version,[string]$ProjectConfigIdentity,$ExpectedPreparation,$OriginalReceipt)

    $targetRuntime=[IO.Path]::GetFullPath((Join-Path $VersionRoot '../../..'))
    $targetComposer=Get-AiwAdoptionRuntimeModule $targetRuntime ('framework/versions/'+$Version+'/scripts/ProcessRequirementComposition.psm1') @('Get-AiwLocalCandidateSupportBinding','Get-AiwProjectPolicySourceClosure')
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
        if($null-ne$pilot.PSObject.Properties['majorTransition']){
            # Later refreshes retain the original finalized adoption proof.
            # Include that actual journal so the prospective reader need not
            # freeze a historical task's live bytes or require it to exist.
            $null=$paths.Add([string]$pilot.majorTransition.transactionRelativePath)
        }
        if($pilot.schemaVersion-eq7){$null=$paths.Add([string]$pilot.origin.transactionRelativePath)}
        if($null-ne$ExpectedPreparation-and$null-ne$OriginalReceipt){
            $currentTaskRelative=[string]$OriginalReceipt.sourceLocators.taskRelativePath
            if($currentTaskRelative-cne'NOT_APPLICABLE'){$null=$paths.Add($currentTaskRelative)}
        }
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
        if($pilot.schemaVersion-eq7){
            $targetState=Get-AiwAdoptionRuntimeModule $targetRuntime 'scripts/ProjectAdoptionState.psm1' @('Invoke-AiwRegistrationProjectionContext')
            & $targetState.ExportedCommands['Invoke-AiwRegistrationProjectionContext'] -ProjectRoot $stage -SourceProjectRoot $Root -Projection $Projection -Body { $null=& $targetComposer.ExportedCommands['Get-AiwLocalCandidateSupportBinding'] @arguments }
        }else{$null=& $targetComposer.ExportedCommands['Get-AiwLocalCandidateSupportBinding'] @arguments}
        if($null-ne$ExpectedPreparation){
            $context=Get-AiwAdoptionProcessContext $OriginalReceipt
            $policy=(Read-AiwProjectJson (Get-AiwContainedPath $stage '.ai-workspace/process-policy.json') 'PROJECTED_POLICY').Value
            $sourceArguments=@{ProjectRoot=$Root;Rules=@($policy.rules);ForbiddenPaths=@($context.forbiddenScope)}
            if($policy.schemaVersion-in@(2,3)){
                $targetComposer=Get-AiwAdoptionRuntimeModule $targetRuntime ('framework/versions/'+$Version+'/scripts/ProcessRequirementComposition.psm1') @('New-AiwAdoptionContentContext','Get-AiwProjectPolicySourceClosure','Assert-AiwProjectPolicySourceClosure')
                $sourceArguments.ProjectRoot=$stage
                $sourceArguments.ContentContext=& $targetComposer.ExportedCommands['New-AiwAdoptionContentContext'] -ProjectRoot $stage -ExpectedProjectConfigIdentity (Get-AiwCurrentIdentity (Get-AiwContainedPath $stage '.ai-workspace/project.json')) -ForbiddenPaths @($context.forbiddenScope) -SourceProjectRoot $Root -ProjectedSourceObjects @($Projection.objects)
            }
            $closure=& $targetComposer.ExportedCommands['Get-AiwProjectPolicySourceClosure'] @sourceArguments
            foreach($document in $closure.Documents){
                if($document.locatorKind-ceq'PROJECT_RELATIVE'-and$document.relativePath-cne'NOT_APPLICABLE'){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $document.relativePath) $document.bytes}
            }
            $composition=Get-AiwAdoptionComposition $stage $ExpectedPreparation.targetDistribution.runtimeRoot $OriginalReceipt -EvaluationOnly -SourceProjectRoot $Root -SourceProjection $Projection
            Assert-AiwAdoptionSame @($composition.selectedRequirements) @($ExpectedPreparation.selectedRuleBlocks) 'RECOVERY_TARGET_RULE_DRIFT'
            foreach($field in $ExpectedPreparation.projectedSourceBindings.PSObject.Properties){
                $actual=if($field.Name-ceq'taskIdentity'){Get-AiwCurrentIdentity (Get-AiwContainedPath $stage $OriginalReceipt.sourceLocators.taskRelativePath)}else{[string]$composition.($field.Name)}
                if($actual-cne[string]$field.Value){throw ('ADOPTION_PROCESS_SOURCE_DRIFT|'+$field.Name)}
            }
            Assert-AiwAdoptionPolicySourceClosure $closure $targetComposer
            foreach($document in $closure.Documents){
                $projected=@($Projection.objects|Where-Object{(Get-AiwContainedPath $Root $_.path).Equals($document.sourcePath,[StringComparison]::OrdinalIgnoreCase)})
                if($null-ne$closure.PSObject.Properties['SnapshotChecks']-and($document.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')-or$projected.Count-eq0)){continue}
                $actual=Get-AiwCurrentIdentity $document.sourcePath
                if($projected.Count-eq1){if($document.identity-cne$projected[0].newIdentity-or$actual-cnotin@($projected[0].oldIdentity,$projected[0].newIdentity)){throw 'ADOPTION_RECOVERY_PROJECTED_SOURCE_DRIFT'}}
                elseif($actual-cne$document.identity){throw 'ADOPTION_RECOVERY_EXTERNAL_SOURCE_DRIFT'}
            }
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
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode $(if($Apply){"WRITE"}else{"OBSERVE"})
try {

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
    if($state.schemaVersion-ne1-or[string]$state.repositoryRoot-cne$root-or[string]$state.transactionRelativePath-cne$relative-or[string]$metadata.operation-cnotin@('UPGRADE_RUNTIME_REFRESH','UPGRADE_SNAPSHOT12_TO_2','UPGRADE_FORMAT_TRANSITION')){throw 'ADOPTION_TRANSACTION_BINDING'}
    if($state.transactionComplete-isnot[bool]-or($state.completedWrites-isnot[int]-and$state.completedWrites-isnot[long])-or$state.completedWrites-lt0){throw 'ADOPTION_TRANSACTION_STATE_SCHEMA'}
    if($state.transactionComplete-and$state.state-cnotin@('COMPLETE','ROLLED_BACK')){throw 'ADOPTION_TRANSACTION_STATE_SCHEMA'}
    $major=$metadata.operation-cin@('UPGRADE_SNAPSHOT12_TO_2','UPGRADE_FORMAT_TRANSITION')
    if($metadata.operation-ceq'UPGRADE_SNAPSHOT12_TO_2'-and$relative-cne'.ai-workspace/runtime/project-adoption/upgrade/state.json'){throw 'ADOPTION_TRANSACTION_BINDING'}
    $packageDoc=Read-AiwProjectJson $AuthorizationPackagePath 'ADOPTION_AUTHORIZATION';$package=$packageDoc.Value
    if($packageDoc.Identity-cne$ExpectedAuthorizationPackageIdentity-or$packageDoc.Identity-cne[string]$metadata.authorizationIdentity-or
       [int]$package.schemaVersion-ne3-or[string]$package.bundle-cne'ACTOR_BOUND_PROJECT_UPGRADE'-or[string]$package.grantee-cne$ObservedActor-or
       [string]$metadata.actor-cne$ObservedActor){throw 'ADOPTION_RECOVERY_AUTHORIZATION'}
    $null=Assert-AiwProjectionContract $root $state.projection
    $samePin=$metadata.operation-ceq'UPGRADE_RUNTIME_REFRESH'-and$package.frameworkVersion-ceq'2.0.0'
    if($samePin-and-not$state.transactionComplete){
        # Resume the admitted action, not a newly prepared action against the
        # interrupted mix of old and new objects. Retain the actual evidence
        # bytes so recovery does not depend on a short-lived receipt file.
        foreach($name in @('Admit','Discover')){
            if($null-eq$metadata.PSObject.Properties['original'+$name+'Base64']-or$null-eq$metadata.PSObject.Properties['original'+$name+'Identity']){throw ('ADOPTION_RECOVERY_ORIGINAL_EVIDENCE_REQUIRED|'+$name)}
            $encoded=[string]$metadata.('original'+$name+'Base64')
            $identity=[string]$metadata.('original'+$name+'Identity')
            if([string]::IsNullOrWhiteSpace($encoded)-or$identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('ADOPTION_RECOVERY_ORIGINAL_EVIDENCE_REQUIRED|'+$name)}
            $bytes=[Convert]::FromBase64String($encoded)
            if((Get-AiwByteIdentity $bytes)-cne$identity){throw ('ADOPTION_RECOVERY_ORIGINAL_EVIDENCE_DRIFT|'+$name)}
            $document=[pscustomobject]@{Bytes=$bytes;Identity=$identity;Value=($script:Utf8NoBom.GetString($bytes)|ConvertFrom-Json -Depth 100)}
            if($name-ceq'Admit'){$originalAdmit=$document}else{$originalDiscover=$document}
        }
        if($metadata.admitResultIdentity-cne$originalAdmit.Identity){throw 'ADOPTION_RECOVERY_ORIGINAL_ADMIT_DRIFT'}
        $proof=Get-AiwSamePinAdoptionAdmission $originalAdmit $root $state.projection $metadata.distributionBinding $ObservedActor -Recovery -OriginalDiscoverDocument $originalDiscover
        Assert-AiwAdoptionSame $proof.context $metadata.originalContext 'RECOVERY_CONTEXT'
        Assert-AiwAdoptionSame $proof.preparation.previousDistribution $metadata.previousDistribution 'RECOVERY_PREVIOUS_DISTRIBUTION'
        if($metadata.taskPath-cne$proof.receipt.sourceLocators.taskRelativePath-or$metadata.taskIdentity-cne$proof.context.taskIdentity-or
           $metadata.projectConfigIdentity-cne$proof.receipt.sourceBindings.projectConfigIdentity-or$metadata.controllerIdentity-cne$proof.receipt.sourceBindings.controllerIdentity){throw 'ADOPTION_RECOVERY_ORIGINAL_CONTEXT_DRIFT'}
        $targetStateEntry=@($state.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'})
        if($targetStateEntry.Count-ne1-or-not$targetStateEntry[0].newExists){throw 'ADOPTION_RECOVERY_STATE_PROJECTION_REQUIRED'}
        $targetState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($targetStateEntry[0].newBase64))|ConvertFrom-Json -Depth 100
        Assert-AiwMajorUpgradeAuthorization $package $proof ([pscustomobject]@{canonical=$targetState.targetReleaseCanonical;manifestIdentity=$targetState.targetReleaseManifestIdentity})
        $null=Assert-AiwRootToolRevision (Split-Path -Parent $PSScriptRoot) $targetState.rootToolRevision @($targetState.rootToolDependencies)
    }
    if($major){
        if($package.frameworkVersion-cne'2.0.0'-or(Get-AiwAdoptionTargetVersion $state.projection)-cne'2.0.0'){throw 'ADOPTION_PROCESS_VERSION_PAIR'}
        $null=Assert-AiwDistributionBinding $metadata.previousDistribution $metadata.previousDistribution.runtimeRoot $metadata.originalContext.frameworkVersion
        $admitBytes=[Convert]::FromBase64String($metadata.originalAdmitBase64)
        if((Get-AiwByteIdentity $admitBytes)-cne$metadata.originalAdmitIdentity){throw 'ADOPTION_RECOVERY_ORIGINAL_ADMIT_DRIFT'}
        $proof=Get-AiwMajorAdoptionAdmission ([pscustomobject]@{Value=($script:Utf8NoBom.GetString($admitBytes)|ConvertFrom-Json -Depth 100)}) $root
        Assert-AiwMajorAdoptionProjection $state.projection $metadata.originalContext $metadata.taskPath $metadata.previousDistribution (Get-AiwCorrectionAdoptionEvidence $proof.preparation)
        Assert-AiwAdoptionSame $proof.preparation.projection $state.projection 'RECOVERY_PROJECTION'
        Assert-AiwAdoptionSame $proof.context $metadata.originalContext 'RECOVERY_CONTEXT'
        Assert-AiwAdoptionSame $proof.preparation.targetDistribution $metadata.distributionBinding 'RECOVERY_DISTRIBUTION'
        $targetStateEntry=@($state.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'})[0]
        $targetState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($targetStateEntry.newBase64))|ConvertFrom-Json -Depth 100
        Assert-AiwMajorUpgradeAuthorization $package $proof ([pscustomobject]@{canonical=$targetState.targetReleaseCanonical;manifestIdentity=$targetState.targetReleaseManifestIdentity})
        # The admitted projection already binds the target identity. Recovery
        # runs from the exact compatible tool dependencies saved there; its
        # location may be an intact copy, separate from the damaged target.
        $toolRoot=Split-Path -Parent $PSScriptRoot
        $null=Assert-AiwRootToolRevision $toolRoot $targetState.rootToolRevision @($targetState.rootToolDependencies)
        if($Direction-ceq'COMPLETE'){
            $null=Assert-AiwDistributionBinding $metadata.distributionBinding $metadata.distributionBinding.runtimeRoot '2.0.0'
        }
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
    # Projection validation obtains its own exact target commands.
    $projectIdentity=[string]$metadata.projectConfigIdentity
    if($major){$projectIdentity=[string](@($state.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})[0].newIdentity)}
    $preparation=$null;$originalReceipt=$null
    if($major-or$samePin){$preparation=$proof.preparation;$originalReceipt=$proof.receipt}
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
        $state.state='COMPLETE';$state.transactionComplete=$true;Write-AiwCommittedTransactionState $path $state ([ref]$lastTransactionIdentity)
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

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
Export-ModuleMember -Function Resume-AiwRuntimeAdoption

# Prospective closeout for one named-runtime refresh. The existing upgrade plan
# supplies the projection; the version composer remains the only rule selector.
function Assert-AiwAdoptionSame($Left,$Right,[string]$Label) {
    if((ConvertTo-AiwPublicationRootCanonical $Left)-cne(ConvertTo-AiwPublicationRootCanonical $Right)){throw ('ADOPTION_PROCESS_'+$Label)}
}
function Get-AiwBoundaryDeliveryObservation($Boundary,[string]$FrameworkRoot,[string]$Version='1.16.0') {
    if($null-eq$Boundary.PSObject.Properties['deliveryContext']){return $null}
    $composer=Get-AiwAdoptionRuntimeModule $FrameworkRoot ('framework/versions/'+$Version+'/scripts/ProcessRequirementComposition.psm1') @('Get-AiwDeliveryObservation')
    $observation=& $composer.ExportedCommands['Get-AiwDeliveryObservation'] $Boundary.deliveryContext
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
    elseif($Receipt.schemaVersion-eq3-and$Receipt.inputContractVersion-eq4-and$Receipt.intentEnvelope.schemaVersion-eq2){$c=$Receipt.binding}
    elseif($Receipt.schemaVersion-eq4-and$Receipt.inputContractVersion-eq5-and$Receipt.binding.schemaVersion-eq3-and$Receipt.intentEnvelope.schemaVersion-eq2){$c=$Receipt.binding}
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
    $major='.ai-workspace/project.json'-cin@($c.exactScope)-or($sourceVersion-ceq'1.16.0'-and'.ai-workspace/upgrade-recovery/2.0.0/state.json'-cin@($c.exactScope))
    if($intent.requestedActionKind-cne'CONTROL_WRITE'-or$intent.ambiguityState-cne'CLEAR'-or'CONTROL_WRITE'-cnotin@($c.authorizedActions)-or@($c.exactScope).Count-eq0-or$sourceState-cnotin@($c.exactScope)){throw 'ADOPTION_PROCESS_CONTEXT_SCOPE'}
    return $c
}
function Get-AiwAdoptionTargetVersion($Projection) {
    $entries=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})
    if($entries.Count-eq0){return '1.16.0'}
    if($entries.Count-ne1-or-not$entries[0].oldExists-or-not$entries[0].newExists){throw 'ADOPTION_PROCESS_PROJECT_PROJECTION'}
    $old=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entries[0].oldBase64))|ConvertFrom-Json -Depth 100
    $new=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entries[0].newBase64))|ConvertFrom-Json -Depth 100
    $formatTransition6=$new.schemaVersion-eq6-and($old.schemaVersion-in@(4,5)-or($old.schemaVersion-eq6-and$old.frameworkVersion-ceq'2.0.0'))
    $formatTransition7=$new.schemaVersion-eq7-and($old.schemaVersion-in@(4,5)-or($old.schemaVersion-in@(6,7)-and$old.frameworkVersion-ceq'2.0.0'))
    $formatTransition=$formatTransition6-or$formatTransition7
    $legacyTransition=$old.frameworkVersion-ceq'1.16.0'-and$old.schemaVersion-eq4-and$new.frameworkVersion-ceq'2.0.0'-and$new.schemaVersion-eq5
    if((-not$formatTransition-and-not$legacyTransition)-or$new.frameworkVersion-cne'2.0.0'-or
       $old.id-cne$new.id-or$old.controlPlaneLayout-cne$new.controlPlaneLayout-or$old.repositoryRoot-cne$new.repositoryRoot-or
       $old.frameworkToolBackend-cne$new.frameworkToolBackend){throw 'ADOPTION_PROCESS_VERSION_PAIR'}
    Assert-AiwAdoptionSame @($old.routineExcludedPaths) @($new.routineExcludedPaths) 'PROTECTED_PATHS'
    if($old.controlPlaneLayout-ceq'framework-maintenance-sibling'){
        Assert-AiwAdoptionSame $old.frameworkTarget $new.frameworkTarget 'MAINTENANCE_TARGET'
    }
    return '2.0.0'
}
function Assert-AiwMajorAdoptionProjection($Projection,$Context,[string]$TaskRelativePath,$PreviousDistribution,$CorrectionAdoption=$null) {
    $correctionScope=Assert-AiwCorrectionAdoptionEvidence $CorrectionAdoption $Projection.repositoryRoot $Projection $Context
    $configuration=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})
    if($configuration.Count-eq1){
        $target=$script:Utf8NoBom.GetString([Convert]::FromBase64String($configuration[0].newBase64))|ConvertFrom-Json -Depth 100
        if($target.schemaVersion-in@(6,7)){
            $source=$script:Utf8NoBom.GetString([Convert]::FromBase64String($configuration[0].oldBase64))|ConvertFrom-Json -Depth 100
            $sourceVersion=[string]$source.frameworkVersion;$targetVersion=Get-AiwAdoptionTargetVersion $Projection
            if($Context.frameworkVersion-cne$sourceVersion){throw 'ADOPTION_PROCESS_SOURCE_VERSION'}
            $required=@('.ai-workspace/project.json','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','AGENTS.md','.ai-workspace/BOOTSTRAP.md',('.ai-workspace/upgrade-recovery/'+$sourceVersion+'/state.json'),('.ai-workspace/upgrade-recovery/'+$targetVersion+'/state.json'),$TaskRelativePath)|Select-Object -Unique
            if($sourceVersion-ceq$targetVersion){
                $required=@($required|Where-Object{$_-cne$TaskRelativePath})
                # This validates the immutable projection against its original
                # context. Live task drift is checked by original admission and
                # composition, not by historical completed-projection reads.
            }
            $allowed=@($required)+@($correctionScope)
            if($null-ne$source.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']-and$null-ne$source.frameworkCapabilities.KNOWLEDGE_REFERENCE.PSObject.Properties['indexLocator']){$allowed+=$source.frameworkCapabilities.KNOWLEDGE_REFERENCE.indexLocator}
            foreach($path in $required){if(@($Projection.objects|Where-Object{$_.path-ceq$path}).Count-ne1){throw ('ADOPTION_PROCESS_MAJOR_OBJECT_REQUIRED|'+$path)}}
            foreach($entry in $Projection.objects){
                if($entry.path-cnotin$allowed-or$entry.kind-cne'FILE'-or(-not$entry.newExists-and$entry.path-cnotin$correctionScope)-or($entry.path-cin$required-and-not$entry.newExists)){throw ('ADOPTION_PROCESS_MAJOR_SCOPE|'+$entry.path)}
                foreach($scope in @($Context.forbiddenScope)+@($source.routineExcludedPaths)){if($entry.path.Equals($scope,[StringComparison]::OrdinalIgnoreCase)-or$entry.path.StartsWith($scope.TrimEnd('/')+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'ADOPTION_PROCESS_PROTECTED_PROJECTION'}}
            }
            $lastPath=if($sourceVersion-ceq$targetVersion){'.ai-workspace/upgrade-recovery/'+$targetVersion+'/state.json'}else{$TaskRelativePath}
            if($Projection.objects[-1].path-cne$lastPath){throw 'ADOPTION_PROCESS_MAJOR_WRITE_ORDER'}
            $targetStateEntry=@($Projection.objects|Where-Object{$_.path-ceq('.ai-workspace/upgrade-recovery/'+$targetVersion+'/state.json')})[0]
            $targetState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($targetStateEntry.newBase64))|ConvertFrom-Json -Depth 100
            $transactionRelative='.ai-workspace/runtime/project-adoption/upgrade/state.json'
            $link=[ordered]@{fromVersion=$sourceVersion;fromDistributionId=$PreviousDistribution.distributionId;toVersion=$targetVersion;transactionRelativePath=$transactionRelative}
            if($targetState.schemaVersion-ne6-or$targetState.fromVersion-cne$sourceVersion-or$targetState.toVersion-cne$targetVersion-or$targetState.transactionComplete-ne$true){throw 'ADOPTION_PROCESS_MAJOR_TARGET_STATE'}
            if($sourceVersion-ceq$targetVersion){
                $taskRecord=@($targetState.projectionObjects|Where-Object{$_.relative-ceq$TaskRelativePath})
                $taskObject=@($targetState.objects|Where-Object{$_.relative-ceq$TaskRelativePath})
                if($taskRecord.Count-ne1-or$taskRecord[0].identity-cne$Context.taskIdentity-or$taskObject.Count-ne0){throw 'ADOPTION_PROCESS_UNCHANGED_TASK_BINDING'}
            }
            Assert-AiwAdoptionSame $targetState.majorTransition $link 'MAJOR_RECOVERY_LINK'
            $sourceState=@($Projection.objects|Where-Object{$_.path-ceq('.ai-workspace/upgrade-recovery/'+$sourceVersion+'/state.json')})[0]
            $prior=$script:Utf8NoBom.GetString([Convert]::FromBase64String($sourceState.oldBase64))|ConvertFrom-Json -Depth 100
            Assert-AiwAdoptionSame $prior.distributionBinding $PreviousDistribution 'OLD_DISTRIBUTION'
            if($sourceVersion-cne$targetVersion){
                $changed=@($Projection.objects|Where-Object changed);if($changed[0].path-cne$sourceState.path){throw 'ADOPTION_PROCESS_MAJOR_WRITE_ORDER'}
                $preserved=$script:Utf8NoBom.GetString([Convert]::FromBase64String($sourceState.newBase64))|ConvertFrom-Json -Depth 100
                Assert-AiwAdoptionSame $preserved.majorTransition $link 'MAJOR_RECOVERY_LINK'
                $preserved.PSObject.Properties.Remove('majorTransition');$prior.PSObject.Properties.Remove('majorTransition');Assert-AiwAdoptionSame $preserved $prior 'OLD_STATE_PRESERVED'
            }elseif(-not$targetStateEntry.oldExists){throw 'ADOPTION_PROCESS_OLD_STATE'}
            return
        }
    }
    if((Get-AiwAdoptionTargetVersion $Projection)-cne'2.0.0'-or$PreviousDistribution.distributionId-cne'1.16.0-snapshot.12'){throw 'ADOPTION_PROCESS_VERSION_PAIR'}
    $required=@('.ai-workspace/project.json','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','AGENTS.md','.ai-workspace/BOOTSTRAP.md',
        '.ai-workspace/upgrade-recovery/1.16.0/state.json','.ai-workspace/upgrade-recovery/2.0.0/state.json',$TaskRelativePath)
    $configEntry=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})[0]
    $old=$script:Utf8NoBom.GetString([Convert]::FromBase64String($configEntry.oldBase64))|ConvertFrom-Json -Depth 100
    $allowed=@($required)+@($correctionScope)
    if($null-ne$old.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']){
        $knowledge=$old.frameworkCapabilities.KNOWLEDGE_REFERENCE
        if($null-ne$knowledge.PSObject.Properties['indexLocator']){$allowed+=[string]$knowledge.indexLocator}
    }
    foreach($path in $required){if(@($Projection.objects|Where-Object{$_.path-ceq$path}).Count-ne1){throw ('ADOPTION_PROCESS_MAJOR_OBJECT_REQUIRED|'+$path)}}
    foreach($entry in $Projection.objects){
        if($entry.path-cnotin$allowed-or$entry.kind-cne'FILE'-or(-not$entry.newExists-and$entry.path-cnotin$correctionScope)-or($entry.path-cin$required-and-not$entry.newExists)){throw ('ADOPTION_PROCESS_MAJOR_SCOPE|'+$entry.path)}
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
function Get-AiwAdoptionComposition([string]$Root,[string]$Runtime,$Receipt,[switch]$EvaluationOnly,[string]$SourceProjectRoot,$SourceProjection=$null) {
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
        $expectedTaskActor=if($null-ne$c.PSObject.Properties['taskActor']){[string]$c.taskActor}else{[string]$c.actor}
        if($route.Count-ne1-or$owner.Count-ne1-or$header.Count-ne1-or$header[0].Groups['id'].Value-cne$c.taskId-or$range.Count-ne1-or$range[0].Groups['profile'].Value-cne$c.profile-or$owner[0].Groups['owner'].Value-cne$c.taskOwner-or
           $route[0].Groups['actor'].Value-cne$expectedTaskActor-or$route[0].Groups['phase'].Value-cne$c.phase-or$route[0].Groups['role'].Value-cne$expectedRole-or
           [regex]::Matches($text,'(?m)^- Task schema: 2\.0\.0\s*$').Count-ne1){throw 'ADOPTION_PROCESS_TARGET_TASK_BINDING'}
        $role=$expectedRole;$taskIdentity=Get-AiwCurrentIdentity $task
        $capabilities=@($config.frameworkCapabilities.PSObject.Properties|Where-Object{$_.Value.enabled-eq$true}|ForEach-Object{$_.Name})
        $evidenceModule=Get-AiwAdoptionRuntimeModule $Runtime 'framework/versions/2.0.0/scripts/ResultEvidence.psm1' @('Get-AiwAcceptancePlan')
        $null=& $evidenceModule.ExportedCommands['Get-AiwAcceptancePlan'] $text
    }
    $composer=Get-AiwAdoptionRuntimeModule $Runtime ('framework/versions/'+$version+'/scripts/ProcessRequirementComposition.psm1') @('Invoke-ProcessRequirementComposition','Get-AiwProcessSemanticText')
    $stateModule=Get-AiwAdoptionRuntimeModule $Runtime 'scripts/ProjectAdoptionState.psm1' @('Get-AiwNavigationContract')
    $intentArguments=@{}
    if($composer.ExportedCommands['Invoke-ProcessRequirementComposition'].Parameters.ContainsKey('ValidateCompleteAdoptedSet')){$intentArguments.ValidateCompleteAdoptedSet=$true}
    $navigation=& $stateModule.ExportedCommands['Get-AiwNavigationContract'] (Read-AiwProjectJson (Join-Path $Runtime ('framework/versions/'+$version+'/TOOLCHAIN.json')) 'TOOLCHAIN').Value
    if($navigation.ContractVersion-cin@('3','4')-and$Receipt.intentEnvelope.schemaVersion-eq2){$intentArguments.IntentEnvelope=$Receipt.intentEnvelope}
    if($SourceProjectRoot-and$navigation.ContractVersion-cin@('3','4')){
        $composer=Get-AiwAdoptionRuntimeModule $Runtime ('framework/versions/'+$version+'/scripts/ProcessRequirementComposition.psm1') @('Invoke-ProcessRequirementComposition','Get-AiwProcessSemanticText','New-AiwAdoptionContentContext')
        if(-not$EvaluationOnly-or$null-eq$SourceProjection-or(Resolve-AiwRepositoryRoot $c.projectRoot)-cne(Resolve-AiwRepositoryRoot $SourceProjectRoot)){throw 'ADOPTION_PROCESS_SOURCE_CONTEXT'}
        $null=Assert-AiwProjectionContract $SourceProjectRoot $SourceProjection
        Assert-AiwAdoptionSame @($SourceProjection.objects.path|Sort-Object) @($c.exactScope|Sort-Object) 'SOURCE_PROJECTION_SCOPE'
        $intentArguments.ContentContext=& $composer.ExportedCommands['New-AiwAdoptionContentContext'] -ProjectRoot $Root -SourceProjectRoot $SourceProjectRoot -ExpectedProjectConfigIdentity (Get-AiwCurrentIdentity (Get-AiwContainedPath $Root '.ai-workspace/project.json')) -ForbiddenPaths @($c.forbiddenScope) -ProjectedSourceObjects @($SourceProjection.objects)
    }
    # A legacy envelope stays the original envelope. The private prospective
    # observation is unclassified and cannot create a new process admission.
    $compose={& $composer.ExportedCommands['Invoke-ProcessRequirementComposition'] -ProjectRoot $Root -FrameworkRoot $Runtime -TargetVersion $version -ExpectedProjectConfigIdentity (Get-AiwCurrentIdentity (Get-AiwContainedPath $Root '.ai-workspace/project.json')) -ExpectedCorrectionsIdentity (Get-AiwCurrentIdentity (Get-AiwContainedPath $Root '.ai-workspace/corrections.json')) -Profile $c.profile -Role $role -Phase $c.phase -Actor $c.actor -TaskIdentity $taskIdentity -Capabilities $capabilities -Objective (& $composer.ExportedCommands['Get-AiwProcessSemanticText'] $Receipt.intentEnvelope) -ActionKind 'CONTROL_WRITE' -ResultKind $Receipt.intentEnvelope.requestedResultKind -ExactPaths @($c.exactScope) -ForbiddenPaths @($c.forbiddenScope) -EvaluationOnly:$EvaluationOnly @intentArguments}
    $statePath=Get-AiwContainedPath $Root ('.ai-workspace/upgrade-recovery/'+$version+'/state.json')
    $registered=(Test-Path -LiteralPath $statePath -PathType Leaf)-and(Read-AiwProjectJson $statePath 'ADOPTION_STATE').Value.schemaVersion-eq7
    if($registered-and$EvaluationOnly-and$SourceProjectRoot){
        $stateModule=Get-AiwAdoptionRuntimeModule $Runtime 'scripts/ProjectAdoptionState.psm1' @('Invoke-AiwRegistrationProjectionContext')
        $result=& $stateModule.ExportedCommands['Invoke-AiwRegistrationProjectionContext'] -ProjectRoot $Root -SourceProjectRoot $SourceProjectRoot -Projection $SourceProjection -Body $compose
    }else{$result=& $compose}
    if($version-ceq'2.0.0'){
        $prefix=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))+[IO.Path]::DirectorySeparatorChar
        foreach($block in $result.selectedRequirements){if($block.ownerModule-ceq'PROJECT_STANDARD_SOURCE'){continue};foreach($part in $block.displayParts){
            if($part.sourceLocator.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$part.sourceLocator='PROJECT_RELATIVE:'+([IO.Path]::GetRelativePath($Root,$part.sourceLocator).Replace('\','/'))}
        }}
    }
    $size=$script:Utf8NoBom.GetByteCount((@($result.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress))
    # Measured bytes are observational; source and adoption proofs remain mandatory.
    $result|Add-Member -NotePropertyName bindingSelectionContext -NotePropertyValue ([pscustomobject]@{profile=$c.profile;role=$role;phase=$c.phase;actor=$c.actor;actionKind='CONTROL_WRITE';resultKind=$Receipt.intentEnvelope.requestedResultKind;exactPaths=@($c.exactScope);capabilities=@($capabilities);intentEnvelope=$Receipt.intentEnvelope})
    return $result
}
function Get-AiwMajorAdoptionAdmission($AdmitDocument,[string]$Root,[switch]$VerifyCurrent) {
    $ad=$AdmitDocument.Value
    if($null-eq$ad.PSObject.Properties['originalAdmissionInput']-or$null-eq$ad.PSObject.Properties['adoptionPreparation']){throw 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED'}
    $a=$ad.originalAdmissionInput;$p=$ad.adoptionPreparation
    $rd=Read-AiwAdoptionEvidence $a.discoverReceiptPath $a.expectedDiscoverReceiptIdentity 'DISCOVER'
    $r=$rd.Value;$c=Get-AiwAdoptionProcessContext $r
    if((Resolve-AiwRepositoryRoot $c.projectRoot)-cne(Resolve-AiwRepositoryRoot $Root)){throw 'ADOPTION_PROCESS_ACTOR_ROOT'}
    if($ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or$a.mode-cne'ADMIT_ACTION'-or$a.schemaVersion-notin@(2,3)-or
       $ad.selectionIdentity-cne$r.selectionIdentity-or$ad.authorityGranted-ne$false-or$ad.semanticCorrectnessProven-ne$false-or
       @($ad.missingPreparation).Count-or@($ad.missingResult).Count-or$p.discoverReceiptIdentity-cne$rd.Identity-or$a.protectionState-cne'BOUND'){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
    $bytes=[Convert]::FromBase64String($ad.adoptionPreparationBase64)
    if((Get-AiwByteIdentity $bytes)-cne$ad.adoptionPreparationIdentity){throw 'ADOPTION_PROCESS_PREPARATION_IDENTITY'}
    Assert-AiwAdoptionSame ($script:Utf8NoBom.GetString($bytes)|ConvertFrom-Json -Depth 100) $p 'PREPARATION_CONTENT'
    Assert-AiwMajorAdoptionProjection $p.projection $c $r.sourceLocators.taskRelativePath $p.previousDistribution (Get-AiwCorrectionAdoptionEvidence $p)
    Assert-AiwAdoptionSelectorJudgment $p $ad.adoptionPreparationIdentity $a
    foreach($field in $r.sourceBindings.PSObject.Properties){
        if($null-eq$p.oldSourceBindings.PSObject.Properties[$field.Name]-or[string]$p.oldSourceBindings.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}
    }
    $material=@($r.sourceCompositionIdentity,$r.selectionIdentity,$r.contextIdentity,'ADMIT_ACTION',$r.intentEnvelope.objective,'CONTROL_WRITE',$r.intentEnvelope.requestedResultKind,[string]::Join(',',@($c.exactScope)),$c.authorizationIdentity,[string]::Join(',',@($a.preparationReceipts)),[string]::Join(',',@($a.resultReceipts)),[string]::Join(',',@($a.deliveryReceipts)),$a.publicDecisionIdentity,$a.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join"`n"
    if($null-ne$a.PSObject.Properties['deliveryContext']){$material+=($a.deliveryContext|ConvertTo-Json -Compress)}
    if($null-ne$a.PSObject.Properties['evidenceRefs']){$material+=($a.evidenceRefs|ConvertTo-Json -Depth 30 -Compress)}
        if((Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes($material))).Split('|')[1]-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
    $required=@(@($r.selectedObligations|ForEach-Object{$_.preparationRequirements})+@($p.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements})|Sort-Object -Unique)
    if(@($required|Where-Object{$_-cnotin@($a.preparationReceipts)}).Count-or('ADOPTION_TARGET_RULES_LOADED|'+$ad.adoptionPreparationIdentity)-cnotin@($a.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
    $pkg=Get-AiwAdoptionProcessPackage $r $c $Root
    if($pkg.Value.issuerRole-cne'PROJECT_CONTROLLER'-or$pkg.Value.profile-cne'CRITICAL'-or$pkg.Value.decisionClass-cne'MAJOR_ARCHITECTURE'-or$pkg.Value.delegatedGitCloser-ne$false){throw 'ADOPTION_PROCESS_MAJOR_AUTHORITY'}
    if($VerifyCurrent){
        $current=New-AiwAdoptionProcessPreparation -RepositoryRoot $Root -TargetRuntimeRoot $p.targetDistribution.runtimeRoot -Projection $p.projection -ObservedActor $c.actor -OriginalBoundary $a -CorrectionAdoption (Get-AiwCorrectionAdoptionEvidence $p)
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
    $expected|Add-Member postObjectIdentities @($Proof.preparation.projection.objects|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$(if($_.newExists){$_.newIdentity}else{'ABSENT'})}})
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
function Assert-AiwAdoptionSelectorJudgment($Preparation,[string]$Identity,$Boundary) {
    if($null-ne$Preparation.PSObject.Properties['selectorDifferences']-and@($Preparation.selectorDifferences).Count-gt0-and
       ('ADOPTION_SELECTOR_SEMANTICS_CONFIRMED|'+$Identity)-cnotin@($Boundary.preparationReceipts)){throw 'ADOPTION_SELECTOR_SEMANTIC_JUDGMENT_REQUIRED'}
}
function Assert-AiwAdoptionPolicySourceClosure($Closure,$Composer) {
    if($null-ne$Closure.PSObject.Properties['SnapshotChecks']){
        if($null-eq$Composer-or-not$Composer.ExportedCommands.ContainsKey('Assert-AiwProjectPolicySourceClosure')){throw 'ADOPTION_PROCESS_CLOSURE_MODULE_REQUIRED'}
        & $Composer.ExportedCommands['Assert-AiwProjectPolicySourceClosure'] $Closure
    }
    else{foreach($document in @($Closure.Documents)){
        if($document.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')-or(Get-AiwCurrentIdentity $document.sourcePath)-cne$document.identity){throw 'ADOPTION_PROCESS_EXTERNAL_SOURCE_DRIFT'}
    }}
}
Export-ModuleMember -Function Assert-AiwAdoptionPolicySourceClosure

function Get-AiwAdoptionPolicySourceClosure {
    param($Composer,[string]$ProjectRoot,[object[]]$Rules,[string]$ExpectedProjectConfigIdentity,[string[]]$ForbiddenPaths=@())
    $command=$Composer.ExportedCommands['Get-AiwProjectPolicySourceClosure']
    $arguments=@{ProjectRoot=$ProjectRoot;Rules=$Rules;ForbiddenPaths=$ForbiddenPaths}
    $boundRules=@($Rules|Where-Object{$null-ne$_.PSObject.Properties['source']-and$null-ne$_.source.PSObject.Properties['kind']-and$_.source.kind-ceq'BOUND_SOURCE_ITEM'})
    # Share only a context owned by this original reader. Its full validation
    # and the later original Assert remain responsible for every source rule.
    if($boundRules.Count-gt0-and$command.Parameters.ContainsKey('ContentContext')-and
       $Composer.ExportedCommands.ContainsKey('New-AiwAdoptionContentContext')){
        $arguments.ContentContext=& $Composer.ExportedCommands['New-AiwAdoptionContentContext'] -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -ForbiddenPaths $ForbiddenPaths
    }
    return & $command @arguments
}

function Assert-AiwAdoptionMaterialPath([string]$Root,[string]$Path,[string[]]$ForbiddenPaths) {
    $full=[IO.Path]::GetFullPath($Path,$Root)
    if($full.StartsWith('\\')-or$full.StartsWith('//')){throw 'ADOPTION_PROCESS_MATERIAL_UNC'}
    foreach($denied in $ForbiddenPaths){
        if([string]::IsNullOrWhiteSpace($denied)){throw 'ADOPTION_PROCESS_MATERIAL_PROTECTION'}
        $prefix=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($denied,$Root))
        if($full.Equals($prefix,[StringComparison]::OrdinalIgnoreCase)-or$full.StartsWith($prefix+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_DENIED|FORBIDDEN_PATH'}
    }
    # Check protection before even querying metadata; walk every ancestor so
    # unchanged bytes behind a replaced junction cannot preserve this material.
    $cursor=[IO.Path]::GetPathRoot($full)
    foreach($part in @($full.Substring($cursor.Length)-split'[\\/]'|Where-Object{$_})){ 
        $cursor=[IO.Path]::Combine($cursor,$part)
        if(([IO.File]::GetAttributes($cursor)-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'ADOPTION_PROCESS_MATERIAL_REPARSE'}
    }
    if(([IO.File]::GetAttributes($full)-band[IO.FileAttributes]::Directory)-ne0){throw 'ADOPTION_PROCESS_MATERIAL_NOT_FILE'}
    return $full
}

function Read-AiwAdoptionMaterialBytes([string]$Root,[string]$Path,[string]$Identity,[string[]]$ForbiddenPaths) {
    if($Identity-cnotmatch'^(0|[1-9][0-9]*)\|[A-F0-9]{64}$'){throw 'ADOPTION_PROCESS_MATERIAL_IDENTITY'}
    $length=[long]$Identity.Split('|')[0]
    $full=Assert-AiwAdoptionMaterialPath $Root $Path $ForbiddenPaths
    if($length-gt[int]::MaxValue-or([IO.FileInfo]::new($full)).Length-ne$length){throw 'ADOPTION_PROCESS_MATERIAL_DRIFT'}
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $bytes=[byte[]]::new([int]$length);$offset=0
        while($offset-lt$bytes.Length){$count=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($count-eq0){throw 'ADOPTION_PROCESS_MATERIAL_DRIFT'};$offset+=$count}
        if($stream.ReadByte()-ne-1-or(Get-AiwByteIdentity $bytes)-cne$Identity){throw 'ADOPTION_PROCESS_MATERIAL_DRIFT'}
    }finally{$stream.Dispose()}
    $null=Assert-AiwAdoptionMaterialPath $Root $full $ForbiddenPaths
    return ,$bytes
}

function Assert-AiwAdoptionSourceMaterial($Material,$Composer) {
    if($Material.Mode-ceq'ORIGINAL_CLOSURE'){Assert-AiwAdoptionPolicySourceClosure $Material.Closure $Composer;return}
    if($Material.Mode-cne'PUBLIC_COMPLETE_LOCAL'){throw 'ADOPTION_PROCESS_MATERIAL_MODE'}
    foreach($guard in $Material.Guards){$null=Read-AiwAdoptionMaterialBytes $Material.Root $guard.path $guard.identity $Material.ForbiddenPaths}
    foreach($document in $Material.Documents){
        if((Get-AiwByteIdentity $document.bytes)-cne$document.identity){throw 'ADOPTION_PROCESS_MATERIAL_DRIFT'}
        $null=Read-AiwAdoptionMaterialBytes $Material.Root $document.sourcePath $document.identity $Material.ForbiddenPaths
    }
}

function Get-AiwAdoptionOriginalSourceMaterial($Composer,[string]$Root,$PolicyDocument,$ConfigDocument,[string[]]$ForbiddenPaths) {
    $closure=Get-AiwAdoptionPolicySourceClosure -Composer $Composer -ProjectRoot $Root -Rules @($PolicyDocument.Value.rules) -ExpectedProjectConfigIdentity $ConfigDocument.Identity -ForbiddenPaths $ForbiddenPaths
    return [pscustomobject]@{Mode='ORIGINAL_CLOSURE';Closure=$closure;Identity=$closure.Identity;Documents=@($closure.Documents)}
}

function ConvertTo-AiwAdoptionLocalSourceMaterial($Composition,[string]$Root,$Policy,$Config,[object[]]$Guards,[string[]]$ForbiddenPaths) {
    # This adapter consumes an actual full public invocation. It is private so
    # malformed observations can be tested without a trusted-result input API.
    $trace=@($Composition.readTrace);$positions=@{}
    foreach($name in @('GLOBAL_DECLARATIONS_VALIDATED','SELECTION_STARTED','COMPLETE_ADOPTED_SET_VERIFIED','SELECTED_CLOSURE_VERIFIED')){
        $found=@(for($i=0;$i-lt$trace.Count;$i++){if($trace[$i].event-ceq$name){$i}})
        if($found.Count-ne1){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|MARKER'}
        $positions[$name]=$found[0]
    }
    if($positions.GLOBAL_DECLARATIONS_VALIDATED-ge$positions.SELECTION_STARTED-or$positions.SELECTION_STARTED-ge$positions.COMPLETE_ADOPTED_SET_VERIFIED-or$positions.COMPLETE_ADOPTED_SET_VERIFIED-ge$positions.SELECTED_CLOSURE_VERIFIED){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|ORDER'}
    $expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($rule in $Policy.rules){if($null-ne$rule.PSObject.Properties['source']){foreach($document in $rule.source.documents){
        $key=[string]$rule.ruleId+'|'+[string]$document.sourceId
        if(-not$expected.TryAdd($key,$document)){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|DECLARATION'}
    }}}
    $observed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $files=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$pinned=$false
    for($i=0;$i-lt$trace.Count;$i++){
        $entry=$trace[$i]
        if($entry.sequence-ne$i-or$entry.authority-ne$false){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|TRACE'}
        if($entry.event-cne'SOURCE_BODY_READ'){continue}
        if($i-le$positions.SELECTION_STARTED-or$i-ge$positions.COMPLETE_ADOPTED_SET_VERIFIED){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|SOURCE_ORDER'}
        $key=[string]$entry.ruleId+'|'+[string]$entry.sourceId
        if(-not$expected.ContainsKey($key)-or-not$observed.Add($key)){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|COVERAGE'}
        $document=$expected[$key];$binding=@($Config.sourceBindings|Where-Object{$_.id-ceq$document.bindingId})
        if($binding.Count-ne1-or$binding[0].provider-cne'LOCAL_DIRECTORY'){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|BINDING'}
        $binding=$binding[0];$absolute=[IO.Path]::IsPathRooted($binding.locator.root)
        $source=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($binding.locator.root,$Root)) $document.locator))
        if($entry.path-cne$source-or$entry.identity-cne$document.identity-or$entry.observation-cnotin@('LOCAL','PINNED_CACHE')){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|SOURCE'}
        if($entry.observation-ceq'PINNED_CACHE'){$pinned=$true}
        $kind=if($absolute){'ABSOLUTE_FILE'}else{'PROJECT_RELATIVE'}
        $locator=if($absolute){$source}else{[IO.Path]::GetRelativePath($Root,$source).Replace('\','/')}
        $relative=if(-not$absolute-and$source.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$locator}else{'NOT_APPLICABLE'}
        $fileKey=$kind+'|'+$source
        if($files.ContainsKey($fileKey)){
            if($files[$fileKey].identity-cne$entry.identity){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|CONFLICT'}
        }else{$files.Add($fileKey,[pscustomobject]@{locatorKind=$kind;locator=$locator;relativePath=$relative;sourcePath=$source;identity=[string]$entry.identity;bytes=$null})}
    }
    if($observed.Count-ne$expected.Count){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|COVERAGE'}
    # A validated pinned observation remains valid for the original reader,
    # but its cache transport is deliberately outside this local material path.
    if($pinned){return $null}
    $material=[pscustomobject]@{Mode='PUBLIC_COMPLETE_LOCAL';Root=$Root;Identity='MISSING';Documents=@($files.Values);Guards=$Guards;ForbiddenPaths=@($ForbiddenPaths);DeclarationCount=$observed.Count}
    foreach($guard in $Guards){$null=Read-AiwAdoptionMaterialBytes $Root $guard.path $guard.identity $ForbiddenPaths}
    foreach($document in $material.Documents){$document.bytes=Read-AiwAdoptionMaterialBytes $Root $document.sourcePath $document.identity $ForbiddenPaths}
    [string[]]$rows=@($material.Documents|ForEach-Object{$_.locatorKind+'|'+$_.locator+'|'+$_.identity});[Array]::Sort($rows,[StringComparer]::Ordinal)
    if($rows.Count){$material.Identity=Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes([string]::Join([char]10,$rows)))}
    Assert-AiwAdoptionSourceMaterial $material $null
    return $material
}

function Get-AiwAdoptionSourceMaterial($Composer,[string]$Root,$Receipt,$OldSources,$PolicyDocument,$ConfigDocument) {
    $context=Get-AiwAdoptionProcessContext $Receipt
    $forbidden=@($context.forbiddenScope)
    if($null-ne$ConfigDocument.Value.PSObject.Properties['routineExcludedPaths']){$forbidden+=@($ConfigDocument.Value.routineExcludedPaths)}
    $eligible=$context.frameworkVersion-ceq'2.0.0'-and$Composer.ExportedCommands.ContainsKey('Invoke-ProcessRequirementComposition')-and$Composer.ExportedCommands['Invoke-ProcessRequirementComposition'].Parameters.ContainsKey('ValidateCompleteAdoptedSet')
    $sourceRules=@($PolicyDocument.Value.rules|Where-Object{$null-ne$_.PSObject.Properties['source']})
    if(-not$sourceRules.Count){$eligible=$false}
    foreach($rule in $(if($eligible){$sourceRules}else{@()})){
        if($null-eq$rule.source.PSObject.Properties['kind']-or$rule.source.kind-cne'BOUND_SOURCE_ITEM'){$eligible=$false;continue}
        foreach($document in $rule.source.documents){
            $binding=@($ConfigDocument.Value.sourceBindings|Where-Object{$_.id-ceq$document.bindingId})
            if($document.mode-cnotin@('FULL_FILE','MARKED_SECTION')-or$binding.Count-ne1-or$binding[0].provider-cne'LOCAL_DIRECTORY'){$eligible=$false}
        }
    }
    if(-not$eligible){return Get-AiwAdoptionOriginalSourceMaterial $Composer $Root $PolicyDocument $ConfigDocument $forbidden}
    if($ConfigDocument.Identity-cne$OldSources.projectConfigIdentity-or$PolicyDocument.Identity-cne$OldSources.policyIdentity){throw 'ADOPTION_PROCESS_OLD_SOURCE_DRIFT|MATERIAL_CARRIERS'}
    $fields=@{'.ai-workspace/project.json'='projectConfigIdentity';'.ai-workspace/controller.json'='controllerIdentity';'.ai-workspace/corrections.json'='correctionsIdentity';'.ai-workspace/process-policy.json'='policyIdentity';'AGENTS.md'='projectAgentsIdentity';$Receipt.sourceLocators.taskRelativePath='taskIdentity'}
    $guards=@(foreach($relative in @($fields.Keys)+@('.ai-workspace/BOOTSTRAP.md',('.ai-workspace/upgrade-recovery/'+$context.frameworkVersion+'/state.json'))){
        $path=Assert-AiwAdoptionMaterialPath $Root ([IO.Path]::GetFullPath($relative,$Root)) $forbidden
        $identity=Get-AiwCurrentIdentity $path
        if($fields.ContainsKey($relative)-and$identity-cne$OldSources.($fields[$relative])){throw 'ADOPTION_PROCESS_OLD_SOURCE_DRIFT|MATERIAL_CONTROL'}
        [pscustomobject]@{path=$path;identity=$identity}
    })
    if((Read-AiwProjectJson ([IO.Path]::GetFullPath(('.ai-workspace/upgrade-recovery/'+$context.frameworkVersion+'/state.json'),$Root)) 'ADOPTION_STATE').Value.schemaVersion-eq7){
        $path=Assert-AiwAdoptionMaterialPath $Root ([IO.Path]::GetFullPath('.ai-workspace/runtime/project-adoption/register/state.json',$Root)) $forbidden
        $guards+=,[pscustomobject]@{path=$path;identity=(Get-AiwCurrentIdentity $path)}
    }
    foreach($path in @($Composer.Path,(Join-Path ([IO.Path]::GetDirectoryName($Composer.Path)) 'ContentSources.psm1'))){
        $path=Assert-AiwAdoptionMaterialPath $Root $path $forbidden
        $guards+=,[pscustomobject]@{path=$path;identity=(Get-AiwCurrentIdentity $path)}
    }
    $selection=Get-AiwAdoptionSelectionArguments $Composer.ExportedCommands['Get-AiwProcessBindingSnapshot'] $Receipt
    if(-not$selection.ContainsKey('SelectionContext')){return Get-AiwAdoptionOriginalSourceMaterial $Composer $Root $PolicyDocument $ConfigDocument $forbidden}
    $s=$selection.SelectionContext;$intent=@{}
    if($Receipt.intentEnvelope.schemaVersion-eq2){$intent.IntentEnvelope=$Receipt.intentEnvelope}
    $result=& $Composer.ExportedCommands['Invoke-ProcessRequirementComposition'] -ProjectRoot $Root -FrameworkRoot $Receipt.sourceLocators.frameworkRoot -TargetVersion $context.frameworkVersion -ExpectedProjectConfigIdentity $OldSources.projectConfigIdentity -ExpectedCorrectionsIdentity $OldSources.correctionsIdentity -Profile $s.profile -Role $s.role -Phase $s.phase -Actor $s.actor -TaskIdentity $OldSources.taskIdentity -Capabilities @($s.capabilities) -Objective (& $Composer.ExportedCommands['Get-AiwProcessSemanticText'] $s.intentEnvelope) -ActionKind $s.actionKind -ResultKind $s.resultKind -ExactPaths @($s.exactPaths) -ForbiddenPaths $forbidden -ValidateCompleteAdoptedSet @intent
    if($result.status-cne'PASS'){throw 'ADOPTION_PROCESS_PUBLIC_COMPLETE_OBSERVATION_UNPROVEN|STATUS'}
    foreach($field in $OldSources.PSObject.Properties){
        if($field.Name-ceq'taskIdentity'){continue}
        if($null-eq$result.PSObject.Properties[$field.Name]-or[string]$result.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}
    }
    foreach($guard in $guards){$null=Read-AiwAdoptionMaterialBytes $Root $guard.path $guard.identity $forbidden}
    $material=ConvertTo-AiwAdoptionLocalSourceMaterial $result $Root $PolicyDocument.Value $ConfigDocument.Value $guards $forbidden
    if($null-eq$material){return Get-AiwAdoptionOriginalSourceMaterial $Composer $Root $PolicyDocument $ConfigDocument $forbidden}
    return $material
}

# Own the observation inside one synchronous Apply call. Callers supply inputs,
# never a purportedly trusted preparation or a persistent cache token.
function Invoke-AiwAdoptionPreparedOperation {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[string]$InputPath,[string]$ExpectedInputIdentity,[string]$TargetRuntimeRoot,$Projection,[string]$ObservedActor,$OriginalBoundary,$CorrectionAdoption=$null,[Parameter(Mandatory)][scriptblock]$Body)
    if($null-ne$script:AdoptionPreparationInvocation){throw 'ADOPTION_PROCESS_PREPARATION_SCOPE_NESTED'}
    $arguments=@{};foreach($key in $PSBoundParameters.Keys){if($key-cne'Body'){$arguments[$key]=$PSBoundParameters[$key]}}
    $script:AdoptionPreparationInvocation=@{}
    try{
        $prepared=New-AiwAdoptionProcessPreparation @arguments
        & $Body $prepared
    }finally{$script:AdoptionPreparationInvocation=$null}
}
Export-ModuleMember -Function Invoke-AiwAdoptionPreparedOperation

function New-AiwAdoptionProcessPreparation {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[string]$InputPath,[string]$ExpectedInputIdentity,[string]$TargetRuntimeRoot,$Projection,[string]$ObservedActor,$OriginalBoundary,$CorrectionAdoption=$null)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode OBSERVE
try {

    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    if($null-ne$OriginalBoundary){$boundary=$OriginalBoundary}else{$inputDoc=Read-AiwAdoptionEvidence $InputPath $ExpectedInputIdentity 'PREPARE_INPUT';$boundary=$inputDoc.Value}
    if($boundary.schemaVersion-notin@(2,3)-or$boundary.mode-cne'ADMIT_ACTION'){throw 'ADOPTION_PROCESS_PREPARE_INPUT'}
    $receiptDoc=Read-AiwAdoptionEvidence $boundary.discoverReceiptPath $boundary.expectedDiscoverReceiptIdentity 'DISCOVER';$receipt=$receiptDoc.Value
    $invocationKey=if($null-ne$script:AdoptionPreparationInvocation){ConvertTo-AiwPublicationRootCanonical ([ordered]@{root=$root;target=[IO.Path]::GetFullPath($TargetRuntimeRoot);projection=$Projection;actor=$ObservedActor;boundary=$boundary;correction=$CorrectionAdoption})}else{$null}
    if($null-ne$script:AdoptionPreparationInvocation-and$script:AdoptionPreparationInvocation.ContainsKey('key')){
        $saved=$script:AdoptionPreparationInvocation
        if($saved.key-cne$invocationKey){throw 'ADOPTION_PROCESS_PREPARATION_SCOPE_DRIFT'}
        Assert-AiwAdoptionSourceMaterial $saved.material $saved.composer
        foreach($document in $saved.documents){if((Get-AiwCurrentIdentity $document.path)-cne$document.identity){throw 'ADOPTION_PROCESS_PREPARATION_SOURCE_DRIFT'}}
        foreach($entry in $Projection.objects){if((Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))-cne$entry.oldIdentity){throw 'ADOPTION_PROCESS_PROJECTION_PREIMAGE'}}
        foreach($distribution in $saved.distributions){
            $null=Assert-AiwDistributionBinding $distribution.binding $distribution.binding.runtimeRoot $distribution.version
        }
        return ($saved.json|ConvertFrom-Json -Depth 100)
    }
    $c=Get-AiwAdoptionProcessContext $receipt
    if((Resolve-AiwRepositoryRoot $c.projectRoot)-cne$root-or$c.actor-cne$ObservedActor){throw 'ADOPTION_PROCESS_ACTOR_ROOT'}
    Assert-AiwAdoptionProjectionProtection $root $Projection $c
    $null=Assert-AiwProjectionContract $root $Projection
    $correctionScope=Assert-AiwCorrectionAdoptionEvidence $CorrectionAdoption $root $Projection $c
    $null=Get-AiwAdoptionProcessPackage $receipt $c $root
    Assert-AiwAdoptionSame @($Projection.objects.path|Sort-Object) @($c.exactScope|Sort-Object) 'PROJECTION_SCOPE'
    if(Test-AiwSamePinProcessProjection $Projection){
        $allowed=@('AGENTS.md','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json',('.ai-workspace/upgrade-recovery/'+$c.frameworkVersion+'/state.json'),'.agents/skills/ai-workspace-router/SKILL.md','.gitignore')+@($correctionScope)
        foreach($entry in $Projection.objects){if($entry.path-cnotin$allowed-and$entry.path-cnotmatch'^\.ai-workspace/upgrade-recovery/corrections/[A-Z][A-Z0-9_]*/[A-Za-z0-9._-]+/history\.json$'){throw 'ADOPTION_PROCESS_CONTEXT_SCOPE'}}
    }
    $sourceVersion=[string]$c.frameworkVersion
    $targetVersion=if($sourceVersion-ceq'2.0.0'){'2.0.0'}else{Get-AiwAdoptionTargetVersion $Projection}
    foreach($entry in $Projection.objects){
        $newHistory=$entry.path-cmatch'^\.ai-workspace/upgrade-recovery/corrections/[A-Z][A-Z0-9_]*/[A-Za-z0-9._-]+/history\.json$'
        $groupObject=$entry.path-cin$correctionScope
        $newMajorState=$sourceVersion-ceq'1.16.0'-and$targetVersion-ceq'2.0.0'-and$entry.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'
        if($entry.kind-cne'FILE'-or(-not$entry.oldExists-and-not$newHistory-and-not$newMajorState-and-not$groupObject)-or(($newHistory-or$newMajorState)-and$entry.oldExists)-or(-not$entry.newExists-and-not$groupObject)-or(-not$entry.oldExists-and-not$entry.newExists-and-not$groupObject)-or(Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))-cne$entry.oldIdentity){throw 'ADOPTION_PROCESS_PROJECTION_PREIMAGE'}
    }
    $oldBinding=Get-AiwAdoptedDistributionBinding $root $sourceVersion
    $null=Assert-AiwDistributionBinding $oldBinding $receipt.sourceLocators.frameworkRoot $sourceVersion
    $configuration=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})
    if($configuration.Count-eq1-and-not(Test-AiwSamePinProcessProjection $Projection)){Assert-AiwMajorAdoptionProjection $Projection $c $receipt.sourceLocators.taskRelativePath $oldBinding $CorrectionAdoption}
    $newBinding=Get-AiwDistributionBinding $TargetRuntimeRoot $targetVersion -Required
    $oldComposer=Get-AiwAdoptionRuntimeModule $receipt.sourceLocators.frameworkRoot ('framework/versions/'+$sourceVersion+'/scripts/ProcessRequirementComposition.psm1') @('Get-AiwProcessBindingSnapshot','Get-AiwProjectPolicySourceClosure')
    $selectionArguments=Get-AiwAdoptionSelectionArguments $oldComposer.ExportedCommands['Get-AiwProcessBindingSnapshot'] $receipt
    $oldSources=& $oldComposer.ExportedCommands['Get-AiwProcessBindingSnapshot'] -ProjectRoot $root -FrameworkRoot $receipt.sourceLocators.frameworkRoot -TargetVersion $sourceVersion -TaskRelativePath $receipt.sourceLocators.taskRelativePath -ForbiddenPaths @($c.forbiddenScope) @selectionArguments
    foreach($field in $receipt.sourceBindings.PSObject.Properties){if($null-eq$oldSources.PSObject.Properties[$field.Name]-or[string]$oldSources.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}}
    $policyDocument=Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/process-policy.json') 'POLICY'
    $configDocument=Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'PROJECT'
    $material=Get-AiwAdoptionSourceMaterial $oldComposer $root $receipt $oldSources $policyDocument $configDocument
    $stage=Join-Path ([IO.Path]::GetTempPath()) ('aiw-adoption-process-'+[guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($stage)
    try {
        $paths=@('.ai-workspace/project.json','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md',[string]$receipt.sourceLocators.taskRelativePath)
        $statePath=Get-AiwContainedPath $root ('.ai-workspace/upgrade-recovery/'+$sourceVersion+'/state.json')
        if((Test-Path -LiteralPath $statePath -PathType Leaf)-and(Read-AiwProjectJson $statePath 'ADOPTION_STATE').Value.schemaVersion-eq7){$paths+='.ai-workspace/runtime/project-adoption/register/state.json'}
        Assert-AiwAdoptionSourceMaterial $material $oldComposer
        foreach($path in $paths){$source=Get-AiwContainedPath $root $path;if(Test-Path -LiteralPath $source -PathType Leaf){
            if($material.Mode-ceq'PUBLIC_COMPLETE_LOCAL'){
                $guard=@($material.Guards|Where-Object{$_.path-ceq$source})
                if($guard.Count-ne1){throw 'ADOPTION_PROCESS_MATERIAL_CONTROL_GUARD'}
                $bytes=Read-AiwAdoptionMaterialBytes $root $source $guard[0].identity $material.ForbiddenPaths
            }else{$bytes=[IO.File]::ReadAllBytes($source)}
            Write-AiwAtomicBytes (Get-AiwContainedPath $stage $path) $bytes
        }}
        Assert-AiwAdoptionSourceMaterial $material $oldComposer
        foreach($doc in $material.Documents){if($doc.locatorKind-ceq'PROJECT_RELATIVE'-and$doc.relativePath-cne'NOT_APPLICABLE'){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $doc.relativePath) $doc.bytes}}
        foreach($entry in $Projection.objects){$path=Get-AiwContainedPath $stage $entry.path;if($entry.newExists){Write-AiwAtomicBytes $path ([Convert]::FromBase64String($entry.newBase64))}elseif(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}}
        $composition=Get-AiwAdoptionComposition $stage $TargetRuntimeRoot $receipt -EvaluationOnly -SourceProjectRoot $root -SourceProjection $Projection
        $projectedSources=[ordered]@{}
        foreach($name in @('projectConfigIdentity','controllerIdentity','correctionsIdentity','policyIdentity','bootstrapManagedIdentity','projectCustomIdentity','projectAgentsIdentity','projectStandardsIdentity','frameworkVersionIdentity','releaseManifestIdentity','nativeCatalogIdentity','correctionCoverageIdentity','contentSnapshotIdentity','effectiveSetIdentity','implementationIdentity')){
            if($null-ne$composition.PSObject.Properties[$name]){$projectedSources[$name]=[string]$composition.$name}
        }
        if($targetVersion-ceq'2.0.0'){$projectedSources.taskIdentity=Get-AiwCurrentIdentity (Get-AiwContainedPath $stage $receipt.sourceLocators.taskRelativePath)}
        [object[]]$differences=@()
        if($null-ne$composition.PSObject.Properties['legacySelectorDifferences']){$differences=@($composition.legacySelectorDifferences)}
        $prepared=[ordered]@{schemaVersion=1;status='PREPARED';discoverReceiptIdentity=$receiptDoc.Identity;previousDistribution=$oldBinding;targetDistribution=$newBinding;projection=$Projection;oldSourceBindings=$oldSources;projectedSourceBindings=$projectedSources;selectedRuleBlocks=@($composition.selectedRequirements);selectedPackCeilingBytes=$composition.selectedRulePackBytes;selectorDifferences=$differences;selectorSemanticJudgmentRequired=($differences.Count-gt0);authorityGranted=$false;evidenceGrade='INSTRUCTION_BOUND'}
        if($null-ne$CorrectionAdoption){$prepared.correctionAdoption=$CorrectionAdoption}
        if($null-ne$script:AdoptionPreparationInvocation){
            $sourceIdentityFields=@{'.ai-workspace/project.json'='projectConfigIdentity';'.ai-workspace/controller.json'='controllerIdentity';'.ai-workspace/corrections.json'='correctionsIdentity';'.ai-workspace/process-policy.json'='policyIdentity';'AGENTS.md'='projectAgentsIdentity'}
            $documents=@(foreach($relative in @($paths)+@('.ai-workspace/upgrade-recovery/'+$sourceVersion+'/state.json')){
                $path=Get-AiwContainedPath $root $relative
                $identity=Get-AiwCurrentIdentity $path
                $field=if($sourceIdentityFields.ContainsKey($relative)){$sourceIdentityFields[$relative]}elseif($relative-ceq$receipt.sourceLocators.taskRelativePath){'taskIdentity'}elseif($relative-ceq('.ai-workspace/upgrade-recovery/'+$sourceVersion+'/state.json')){'candidatePilotStateIdentity'}else{$null}
                if($field-and$null-ne$oldSources.PSObject.Properties[$field]-and$identity-cne$oldSources.$field){throw 'ADOPTION_PROCESS_PREPARATION_SOURCE_DRIFT'}
                [pscustomobject]@{path=$path;identity=$identity}
            })+@([pscustomobject]@{path=$receiptDoc.Path;identity=$receiptDoc.Identity},[pscustomobject]@{path=$receipt.sourceLocators.authorizationPackagePath;identity=$c.authorizationIdentity})
            foreach($binding in @($oldBinding,$newBinding)){
                $path=Get-AiwContainedPath $binding.runtimeRoot 'PACKAGE_MANIFEST.json'
                if((Get-AiwCurrentIdentity $path)-cne$binding.manifestIdentity){throw 'ADOPTION_PROCESS_PREPARATION_SOURCE_DRIFT'}
                $documents+=,[pscustomobject]@{path=$path;identity=$binding.manifestIdentity}
            }
            $script:AdoptionPreparationInvocation=@{key=$invocationKey;json=($prepared|ConvertTo-Json -Depth 100 -Compress);documents=$documents;material=$material;composer=$oldComposer;distributions=@(@{binding=$oldBinding;version=$sourceVersion},@{binding=$newBinding;version=$targetVersion})}
        }
        return $prepared
    }finally{
        $base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar
        $full=[IO.Path]::GetFullPath($stage)
        if(-not$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-adoption-process-')){throw 'ADOPTION_PROCESS_CLEANUP_SCOPE'}
        [IO.Directory]::Delete($full,$true)
    }

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
function Get-AiwSamePinAdoptionAdmission($AdmitDocument,[string]$Root,$ExpectedProjection,$TargetDistribution,[string]$ObservedActor,[switch]$Recovery,$OriginalDiscoverDocument=$null) {
    return Get-AiwSamePinAdoptionAdmissionCore @PSBoundParameters
}
function Get-AiwSamePinAdoptionAdmissionCore($AdmitDocument,[string]$Root,$ExpectedProjection,$TargetDistribution,[string]$ObservedActor,[switch]$Recovery,$OriginalDiscoverDocument=$null,[switch]$CompletedSourceObservation) {
    $ad=$AdmitDocument.Value
    if($null-eq$ad.PSObject.Properties['originalAdmissionInput']-or$null-eq$ad.PSObject.Properties['adoptionPreparation']){throw 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED'}
    $a=$ad.originalAdmissionInput;$p=$ad.adoptionPreparation
    if($Recovery){
        if($null-eq$OriginalDiscoverDocument-or$OriginalDiscoverDocument.Identity-cne$a.expectedDiscoverReceiptIdentity-or
           (Get-AiwByteIdentity $OriginalDiscoverDocument.Bytes)-cne$a.expectedDiscoverReceiptIdentity){throw 'ADOPTION_RECOVERY_ORIGINAL_DISCOVER_DRIFT'}
        $rd=$OriginalDiscoverDocument
    }else{$rd=Read-AiwAdoptionEvidence $a.discoverReceiptPath $a.expectedDiscoverReceiptIdentity 'DISCOVER'}
    $r=$rd.Value;$c=Get-AiwAdoptionProcessContext $r
    if($c.frameworkVersion-cne'2.0.0'-or$c.actor-cne$ObservedActor-or(Resolve-AiwRepositoryRoot $c.projectRoot)-cne(Resolve-AiwRepositoryRoot $Root)){throw 'ADOPTION_PROCESS_SAME_PIN_CONTEXT'}
    if($ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or$a.schemaVersion-notin@(2,3)-or$a.mode-cne'ADMIT_ACTION'-or
       $ad.selectionIdentity-cne$r.selectionIdentity-or@($ad.missingPreparation).Count-or@($ad.missingResult).Count-or
       $ad.authorityGranted-ne$false-or$ad.semanticCorrectnessProven-ne$false-or$ad.hostInvocationProven-ne$false-or
       $a.protectionState-cne'BOUND'-or$p.discoverReceiptIdentity-cne$rd.Identity){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
    $bytes=[Convert]::FromBase64String([string]$ad.adoptionPreparationBase64)
    if((Get-AiwByteIdentity $bytes)-cne$ad.adoptionPreparationIdentity){throw 'ADOPTION_PROCESS_PREPARATION_IDENTITY'}
    Assert-AiwAdoptionSame ($script:Utf8NoBom.GetString($bytes)|ConvertFrom-Json -Depth 100) $p 'PREPARATION_CONTENT'
    Assert-AiwAdoptionSame $p.projection $ExpectedProjection 'SAME_PIN_ADMISSION_PROJECTION'
    $null=Assert-AiwCorrectionAdoptionEvidence (Get-AiwCorrectionAdoptionEvidence $p) $Root $p.projection $c
    Assert-AiwAdoptionSame $p.targetDistribution $TargetDistribution 'SAME_PIN_ADMISSION_TARGET'
    foreach($field in $r.sourceBindings.PSObject.Properties){
        if($null-eq$p.oldSourceBindings.PSObject.Properties[$field.Name]-or[string]$p.oldSourceBindings.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}
    }
    Assert-AiwAdoptionSelectorJudgment $p $ad.adoptionPreparationIdentity $a
    if($Recovery){
        # Saved admission bytes prove the original decision, not the continued
        # health of the independent runtime whose code we are about to consume.
        if($CompletedSourceObservation){
            $reader=Get-AiwAdoptionRuntimeModule $r.sourceLocators.frameworkRoot 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1' @('Get-AiwReleasePackageFacts')
            $null=& $reader {
                param($root,$version,$binding,$ownerPath)
                $command=Get-Command Get-AiwReleasePackageObservation -ErrorAction SilentlyContinue
                if($null-ne$command-and$null-ne$command.Module-and$command.Module.Path-ceq$ownerPath){return Get-AiwReleasePackageObservation $root $binding @('framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1')}
                $command=Get-Command Get-AiwFixedReleaseProjection -ErrorAction Stop
                if($null-eq$command.Module-or$command.Module.Path-cne$ownerPath){throw 'ADOPTION_PROCESS_RELEASE_READER_OWNER'}
                Get-AiwFixedReleaseProjection (Join-Path $root ('framework/versions/'+$version)) $root $binding
            } $r.sourceLocators.frameworkRoot $c.frameworkVersion $p.previousDistribution $reader.Path
        }else{
            $null=Assert-AiwDistributionBinding $p.previousDistribution ([string]$r.sourceLocators.frameworkRoot) ([string]$c.frameworkVersion)
        }
    }
    $oldModule=@(Import-Module (Join-Path $r.sourceLocators.frameworkRoot 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru -ErrorAction Stop)[0]
    if($CompletedSourceObservation){
        $actual=& $oldModule {
            param($root,$version)
            $command=Get-Command Get-AiwProcessImplementationIdentity -ErrorAction SilentlyContinue
            $expected=[IO.Path]::GetFullPath((Join-Path $root ('framework/versions/'+$version+'/scripts/ProcessRequirementComposition.psm1')))
            if($null-eq$command-or$null-eq$command.Module-or[IO.Path]::GetFullPath($command.Module.Path)-cne$expected){throw 'FIXED_ADOPTION_OBSERVATION_UNSUPPORTED'}
            & $command -FrameworkRoot $root -TargetVersion $version
        } $r.sourceLocators.frameworkRoot $c.frameworkVersion
        if($actual-cne$r.sourceBindings.implementationIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_IMPLEMENTATION_DRIFT'}
    }
    $decision=& $oldModule.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $r $a
    if($decision-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
    $required=@(@($r.selectedObligations|ForEach-Object{$_.preparationRequirements})+@($p.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements})|Sort-Object -Unique)
    if(@($required|Where-Object{$_-cnotin@($a.preparationReceipts)}).Count-or('ADOPTION_TARGET_RULES_LOADED|'+$ad.adoptionPreparationIdentity)-cnotin@($a.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
    if(-not$Recovery){
        $current=New-AiwAdoptionProcessPreparation -RepositoryRoot $Root -TargetRuntimeRoot $TargetDistribution.runtimeRoot -Projection $ExpectedProjection -ObservedActor $ObservedActor -OriginalBoundary $a -CorrectionAdoption (Get-AiwCorrectionAdoptionEvidence $p)
        Assert-AiwAdoptionSame $current $p 'PREPARATION_DRIFT'
    }
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
    if($a.schemaVersion-notin@(2,3)-or$a.mode-cne'ADMIT_ACTION'-or$a.discoverReceiptPath-cne$b.discoverReceiptPath-or
       $a.expectedDiscoverReceiptIdentity-cne$ReceiptDoc.Identity-or$a.publicDecisionIdentity-cne$b.publicDecisionIdentity-or
       $a.protectionState-cne$b.protectionState-or$ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or
       $ad.selectionIdentity-cne$r.selectionIdentity-or@($ad.missingPreparation).Count-or@($ad.missingResult).Count-or
       $ad.authorityGranted-ne$false-or$ad.semanticCorrectnessProven-ne$false-or$ad.hostInvocationProven-ne$false){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
    foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){
        if($a.$name-isnot[array]-or@($a.$name|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ADOPTION_PROCESS_ORIGINAL_ADMIT_ARRAY'}
    }
    $oldRuntime=[string]$r.sourceLocators.frameworkRoot
    $oldModule=Get-AiwAdoptionRuntimeModule $oldRuntime 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1' @('Get-AiwProcessDecisionIdentity')
    $decision=& $oldModule.ExportedFunctions['Get-AiwProcessDecisionIdentity'] $r $a
    if($decision-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
    $processPackage=Get-AiwAdoptionProcessPackage $r $Context $Root
    if($processPackage.Value.frameworkVersion-cne'2.0.0'){throw 'ADOPTION_PROCESS_SAME_PIN_PACKAGE'}
    # Same-pin refreshes use upgrade or refresh journals according to the
    # original adoption state. Select the exact admitted transaction identity,
    # as recovery does; never infer a journal from the operation name alone.
    $transactions=@(foreach($relative in @('.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
        $candidate=Get-AiwContainedPath $Root $relative
        if(Test-Path -LiteralPath $candidate -PathType Leaf){
            $document=Read-AiwProjectJson $candidate 'TRANSACTION'
            if($document.Identity-ceq$ExpectedTransactionIdentity){[pscustomobject]@{relative=$relative;document=$document}}
        }
    })
    if($transactions.Count-ne1){throw 'ADOPTION_PROCESS_TRANSACTION_DRIFT'}
    $txnDoc=$transactions[0].document;$txnPath=$txnDoc.Path;$txn=$txnDoc.Value
    if($txn.repositoryRoot-cne$Root-or$txn.transactionRelativePath-cne$transactions[0].relative){throw 'ADOPTION_PROCESS_SAME_PIN_TRANSACTION'}
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
    if($oldState.schemaVersion-notin@(6,7)-or$newState.schemaVersion-ne$oldState.schemaVersion-or$oldState.transactionComplete-ne$true-or$newState.transactionComplete-ne$true-or
       $oldState.toVersion-cne'2.0.0'-or$newState.toVersion-cne'2.0.0'){throw 'ADOPTION_PROCESS_SAME_PIN_STATE'}
    if($oldState.schemaVersion-eq7){
        Assert-AiwAdoptionSame $oldState.origin $newState.origin 'SAME_PIN_REGISTER_ORIGIN'
        foreach($field in @('originKind','repositoryRoot','projectId')){Assert-AiwAdoptionSame $oldState.$field $newState.$field ('SAME_PIN_REGISTER_'+$field)}
        $registration=Read-AiwProjectJson (Get-AiwContainedPath $Root $newState.origin.transactionRelativePath) 'REGISTRATION_ORIGIN_TRANSACTION'
        if($newState.registrationTransactionIdentity-cne$registration.Identity-or$newState.currentTransactionRelativePath-cne'.ai-workspace/runtime/project-adoption/refresh/state.json'){throw 'ADOPTION_PROCESS_SAME_PIN_REGISTER_ORIGIN'}
        $null=Assert-AiwRegistrationOrigin $Root '2.0.0'
    }
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
        Assert-AiwAdoptionSelectorJudgment $prepared $ad.adoptionPreparationIdentity $a
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
        $post='OBJECT_POSTIMAGE|'+$object.path+'|'+$(if($object.newExists){$object.newIdentity}else{'ABSENT'})
        if($pre.Count-ne1-or$pre[0].identity-cne$expectedPre-or(Get-AiwCurrentIdentity (Get-AiwContainedPath $Root $object.path))-cne$object.newIdentity-or
           @($b.resultReceipts|Where-Object{$_-ceq$post}).Count-ne1){throw ('ADOPTION_PROCESS_OBJECT_PROOF|'+$object.path)}
    }
    if(@($authorization.Value.objectIdentities).Count-ne@($txn.projection.objects).Count-or
       @($b.resultReceipts|Where-Object{$_-clike'OBJECT_POSTIMAGE|*'}).Count-ne@($txn.projection.objects).Count){throw 'ADOPTION_PROCESS_OBJECT_SCOPE'}
    $composition=Get-AiwAdoptionComposition $Root $newBinding.runtimeRoot $r
    # Resolve delivery through the verified target's existing consumer, as in
    # cross-version finalization. Original receipts and admission stay intact;
    # the recomputed admission delivery must still equal the saved old result.
    $deliveryModule=@(Import-Module (Join-Path $newBinding.runtimeRoot 'framework/versions/2.0.0/scripts/WorkflowDelivery.psm1') -PassThru -ErrorAction Stop)[0]
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
    $targetComposer=Get-AiwAdoptionRuntimeModule $newBinding.runtimeRoot 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1' @('Get-AiwProcessBindingSnapshot')
    $selectionArguments=Get-AiwAdoptionSelectionArguments $targetComposer.ExportedCommands['Get-AiwProcessBindingSnapshot'] $r $composition.bindingSelectionContext $composition
    $bindings=& $targetComposer.ExportedCommands['Get-AiwProcessBindingSnapshot'] -ProjectRoot $Root -FrameworkRoot $newBinding.runtimeRoot -TargetVersion '2.0.0' -TaskRelativePath $r.sourceLocators.taskRelativePath -ForbiddenPaths @($Context.forbiddenScope) @selectionArguments
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
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode OBSERVE
try {

    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $inputDoc=Read-AiwAdoptionEvidence $InputPath $ExpectedInputIdentity 'BOUNDARY';$b=$inputDoc.Value
    $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')
    $boundaryFields=@($fields);if($null-ne$b.PSObject.Properties['deliveryContext']){$boundaryFields+='deliveryContext'};if($null-ne$b.PSObject.Properties['evidenceRefs']){$boundaryFields+='evidenceRefs'}
    Assert-AiwAdoptionSame @($b.PSObject.Properties.Name|Sort-Object) @($boundaryFields|Sort-Object) 'BOUNDARY_FIELDS'
    if($b.schemaVersion-notin@(2,3)-or$b.mode-cne$ExpectedMode-or$b.mode-cnotin@('ADMIT_ACTION','FINALIZE_OUTPUT')-or$b.protectionState-cne'BOUND'){throw 'ADOPTION_PROCESS_BOUNDARY_CONTRACT'}
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
            $current=New-AiwAdoptionProcessPreparation $root $InputPath $ExpectedInputIdentity $p.targetDistribution.runtimeRoot $p.projection $ObservedActor -CorrectionAdoption (Get-AiwCorrectionAdoptionEvidence $p)
            Assert-AiwAdoptionSame $current $p 'PREPARATION_DRIFT'
            Assert-AiwAdoptionSelectorJudgment $p $pDoc.Identity $b
            $required=@($p.selectedRuleBlocks|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique)
            if(@($required|Where-Object{$_-cnotin@($b.preparationReceipts)}).Count-or('ADOPTION_TARGET_RULES_LOADED|'+$pDoc.Identity)-cnotin@($b.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
            # Delegate the actual, unmodified admission exactly once. Retain its
            # exact input before the version resolver's normal cleanup.
            $entry=Join-Path $r.sourceLocators.frameworkRoot ('framework/versions/'+$c.frameworkVersion+'/scripts/resolve-process-requirements.ps1')
            $arguments=@{InputPath=$InputPath;AsJson=$true}
            $config=(Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'PROJECT').Value
            if($null-ne$config.PSObject.Properties['controlPlaneLayout']-and$config.controlPlaneLayout-ceq'framework-maintenance-sibling'){$arguments.AuthorizationCheckerPath=Join-Path $r.sourceLocators.frameworkRoot 'scripts/check-framework-maintenance-authorization.ps1'}
            if($DeleteInputOnExit){$arguments.DeleteInputOnExit=$true}
            if($c.frameworkVersion-ceq'2.0.0'){
                # O owns this admission. X orchestrates and T owns only target
                # preparation/callbacks; never substitute their same-name core.
                $originalCore=Get-AiwAdoptionRuntimeModule $r.sourceLocators.frameworkRoot ('framework/versions/'+$c.frameworkVersion+'/scripts/ProcessRequirementBoundary.psm1') @('Invoke-AiwProcessRequirementBoundary')
                $response=& $originalCore.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] @arguments
                if($null-eq$response-or$response.exitCode-ne0){throw ('ADOPTION_PROCESS_ORIGINAL_ADMIT|'+[string]::Join(';',@($response.output)))}
                $output=@($response.output)
            }else{
                # Older fixed sources own their original script API; they do
                # not acquire a new module contract from a target version.
                $output=@(& $entry @arguments);$exitCode=$LASTEXITCODE
                if($exitCode-ne0){throw ('ADOPTION_PROCESS_ORIGINAL_ADMIT|'+($output-join';'))}
            }
            if($output.Count-ne1){throw ('ADOPTION_PROCESS_ORIGINAL_ADMIT|'+($output-join';'))}
            $result=$output[0]|ConvertFrom-Json -Depth 100
            if($result.status-cne'PASS'-or$result.mode-cne'ADMIT_ACTION'){throw 'ADOPTION_PROCESS_ORIGINAL_ADMIT'}
            $result|Add-Member originalAdmissionInput $b
            $result|Add-Member adoptionPreparation $p
            $result|Add-Member adoptionPreparationIdentity $pDoc.Identity
            $result|Add-Member adoptionPreparationBase64 ([Convert]::ToBase64String($pDoc.Bytes))
            return $result
        }
        if($c.frameworkVersion-ceq'2.0.0'-and$null-ne$AdmitResultPath-and(Test-AiwSamePinProcessProjection (Read-AiwAdoptionEvidence $AdmitResultPath $ExpectedAdmitResultIdentity 'ADMIT_RESULT').Value.adoptionPreparation.projection)){
            return Invoke-AiwSamePinRefreshFinalize $root $inputDoc $receiptDoc $c $AdmitInputPath $ExpectedAdmitInputIdentity $AdmitResultPath $ExpectedAdmitResultIdentity $AuthorizationPackagePath $ExpectedAuthorizationPackageIdentity $ExpectedTransactionIdentity $ObservedActor
        }
        $adDoc=Read-AiwAdoptionEvidence $AdmitResultPath $ExpectedAdmitResultIdentity 'ADMIT_RESULT';$ad=$adDoc.Value
        if($null-eq$ad.PSObject.Properties['originalAdmissionInput']-or$null-eq$ad.PSObject.Properties['adoptionPreparation']){throw 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED'}
        $a=$ad.originalAdmissionInput;$p=$ad.adoptionPreparation
        $targetVersion=Get-AiwAdoptionTargetVersion $p.projection
        if($targetVersion-ceq'2.0.0'){Assert-AiwMajorAdoptionProjection $p.projection $c $r.sourceLocators.taskRelativePath $p.previousDistribution (Get-AiwCorrectionAdoptionEvidence $p)}
        $preparationBytes=[Convert]::FromBase64String($ad.adoptionPreparationBase64)
        if((Get-AiwByteIdentity $preparationBytes)-cne$ad.adoptionPreparationIdentity){throw 'ADOPTION_PROCESS_PREPARATION_IDENTITY'}
        Assert-AiwAdoptionSame ($script:Utf8NoBom.GetString($preparationBytes)|ConvertFrom-Json -Depth 100) $p 'PREPARATION_CONTENT'
        Assert-AiwAdoptionSelectorJudgment $p $ad.adoptionPreparationIdentity $a
        foreach($field in $r.sourceBindings.PSObject.Properties){if($null-eq$p.oldSourceBindings.PSObject.Properties[$field.Name]-or[string]$p.oldSourceBindings.($field.Name)-cne[string]$field.Value){throw ('ADOPTION_PROCESS_OLD_SOURCE_DRIFT|'+$field.Name)}}
        $admitFields=@($fields);if($null-ne$a.PSObject.Properties['deliveryContext']){$admitFields+='deliveryContext'};if($null-ne$a.PSObject.Properties['evidenceRefs']){$admitFields+='evidenceRefs'}
        Assert-AiwAdoptionSame @($a.PSObject.Properties.Name|Sort-Object) @($admitFields|Sort-Object) 'ADMIT_FIELDS'
        foreach($field in @('preparationReceipts','resultReceipts','deliveryReceipts')){if($a.$field-isnot[array]-or@($a.$field|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ADOPTION_PROCESS_ADMIT_ARRAY'}}
        if($ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or$a.mode-cne'ADMIT_ACTION'-or$a.schemaVersion-notin@(2,3)-or$ad.selectionIdentity-cne$r.selectionIdentity-or$a.expectedDiscoverReceiptIdentity-cne$receiptDoc.Identity-or$a.discoverReceiptPath-cne$b.discoverReceiptPath-or$a.protectionState-cne$b.protectionState-or$a.publicDecisionIdentity-cne$b.publicDecisionIdentity-or@($ad.missingPreparation).Count-or@($ad.missingResult).Count-or$p.discoverReceiptIdentity-cne$receiptDoc.Identity){throw 'ADOPTION_PROCESS_ORIGINAL_ADMISSION'}
        $material=@($r.sourceCompositionIdentity,$r.selectionIdentity,$r.contextIdentity,'ADMIT_ACTION',$r.intentEnvelope.objective,'CONTROL_WRITE',$r.intentEnvelope.requestedResultKind,[string]::Join(',',@($c.exactScope)),$c.authorizationIdentity,[string]::Join(',',@($a.preparationReceipts)),[string]::Join(',',@($a.resultReceipts)),[string]::Join(',',@($a.deliveryReceipts)),$a.publicDecisionIdentity,$a.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join"`n"
        if($null-ne$a.PSObject.Properties['deliveryContext']){$material+=($a.deliveryContext|ConvertTo-Json -Compress)}
        if($null-ne$a.PSObject.Properties['evidenceRefs']){$material+=($a.evidenceRefs|ConvertTo-Json -Depth 30 -Compress)}
        if((Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes($material))).Split('|')[1]-cne$ad.decisionIdentity){throw 'ADOPTION_PROCESS_ORIGINAL_DECISION'}
        if(('ADOPTION_TARGET_RULES_LOADED|'+$ad.adoptionPreparationIdentity)-cnotin@($a.preparationReceipts)){throw 'ADOPTION_PROCESS_TARGET_PREPARATION_INCOMPLETE'}
        $pkgDoc=Get-AiwAdoptionProcessPackage $r $c $root;$pkg=$pkgDoc.Value
                $targetState=@($p.projection.objects|Where-Object{$_.path-ceq('.ai-workspace/upgrade-recovery/'+$targetVersion+'/state.json')})[0]
        $stateValue=$script:Utf8NoBom.GetString([Convert]::FromBase64String($targetState.newBase64))|ConvertFrom-Json -Depth 100
        $txnPath=Get-AiwContainedPath $root $stateValue.majorTransition.transactionRelativePath
        $txnDoc=Read-AiwAdoptionEvidence $txnPath $ExpectedTransactionIdentity 'TRANSACTION';$t=$txnDoc.Value
        if($t.transactionComplete-isnot[bool]-or-not$t.transactionComplete-or$t.state-cne'COMPLETE'-or$t.metadata.taskPath-cne$r.sourceLocators.taskRelativePath-or$t.metadata.taskIdentity-cne$c.taskIdentity-or$t.metadata.projectConfigIdentity-cne$r.sourceBindings.projectConfigIdentity-or$t.metadata.controllerIdentity-cne$r.sourceBindings.controllerIdentity){throw 'ADOPTION_PROCESS_TRANSACTION_INCOMPLETE_OR_CONTEXT'}
        Assert-AiwAdoptionSame $t.projection $p.projection 'TRANSACTION_PROJECTION'
        $verified=Resume-AiwRuntimeAdoption -RepositoryRoot $root -ExpectedTransactionIdentity $txnDoc.Identity -AuthorizationPackagePath $AuthorizationPackagePath -ExpectedAuthorizationPackageIdentity $ExpectedAuthorizationPackageIdentity -ObservedActor $ObservedActor
        if($verified.status-cne'COMPLETE'-or$verified.writes-ne0){throw 'ADOPTION_PROCESS_TRANSACTION_INCOMPLETE'}
        $null=Assert-AiwDistributionBinding $p.previousDistribution $r.sourceLocators.frameworkRoot $c.frameworkVersion
        $null=Assert-AiwDistributionBinding $p.targetDistribution $p.targetDistribution.runtimeRoot $targetVersion
        Assert-AiwAdoptionSame $t.metadata.distributionBinding $p.targetDistribution 'TRANSACTION_DISTRIBUTION'
        Assert-AiwAdoptionSame (Get-AiwAdoptedDistributionBinding $root $targetVersion) $p.targetDistribution 'LIVE_DISTRIBUTION'
        foreach($e in $t.projection.objects){
            $pre=@($pkg.objectIdentities|Where-Object{$_.path-ceq$e.path})
            $expectedPre=if($e.oldExists){[string]$e.oldIdentity}else{'NEW'}
            if($pre.Count-ne1-or$pre[0].identity-cne$expectedPre-or(Get-AiwCurrentIdentity (Get-AiwContainedPath $root $e.path))-cne$e.newIdentity-or('OBJECT_POSTIMAGE|'+$e.path+'|'+$(if($e.newExists){$e.newIdentity}else{'ABSENT'}))-cnotin@($b.resultReceipts)){throw 'ADOPTION_PROCESS_OBJECT_PROOF'}
        }
        if(@($pkg.objectIdentities).Count-ne@($t.projection.objects).Count){throw 'ADOPTION_PROCESS_OBJECT_SCOPE'}
        $stateEntry=@($t.projection.objects|Where-Object{$_.path-ceq('.ai-workspace/upgrade-recovery/'+$c.frameworkVersion+'/state.json')})[0]
        $oldState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($stateEntry.oldBase64))|ConvertFrom-Json -Depth 100
        Assert-AiwAdoptionSame $oldState.distributionBinding $p.previousDistribution 'OLD_DISTRIBUTION'
        if($stateEntry.oldIdentity-cne$r.sourceBindings.candidatePilotStateIdentity){throw 'ADOPTION_PROCESS_OLD_STATE'}
        $composition=Get-AiwAdoptionComposition $root $p.targetDistribution.runtimeRoot $r -EvaluationOnly
        # Bind both observations to the original action through the target's
        # existing consumer resolver; the old receipt remains unchanged.
        $deliveryModule=@(Import-Module (Join-Path $p.targetDistribution.runtimeRoot ('framework/versions/'+$targetVersion+'/scripts/WorkflowDelivery.psm1')) -PassThru -ErrorAction Stop)[0]
        $boundAdmit=& $deliveryModule.ExportedFunctions['Get-AiwBoundDelivery'] $r $a
        $admitDelivery=if($null-ne$boundAdmit){$boundAdmit.delivery}else{$null}
        if($null-ne$admitDelivery){
            if($null-eq$ad.PSObject.Properties['delivery']){throw 'ADOPTION_PROCESS_ADMIT_DELIVERY_RESULT'}
            Assert-AiwAdoptionSame $admitDelivery $ad.delivery 'ADMIT_DELIVERY_RESULT'
        }elseif($null-ne$ad.PSObject.Properties['delivery']){throw 'ADOPTION_PROCESS_ADMIT_DELIVERY_RESULT'}
        $boundDelivery=& $deliveryModule.ExportedFunctions['Get-AiwBoundDelivery'] $r $b
        $delivery=if($null-ne$boundDelivery){$boundDelivery.delivery}else{$null}
        if($null-ne$boundDelivery-and-not$boundDelivery.closureSatisfied){throw 'ADOPTION_PROCESS_DELIVERY_NOT_CONFIRMED'}
        Assert-AiwAdoptionSame @($composition.selectedRequirements) @($p.selectedRuleBlocks) 'TARGET_RULE_DRIFT'
        if($composition.selectedRulePackBytes-ne$p.selectedPackCeilingBytes){throw 'ADOPTION_PROCESS_PACK_BUDGET'}
        foreach($field in $p.projectedSourceBindings.PSObject.Properties){
            $live=if($field.Name-ceq'taskIdentity'){Get-AiwCurrentIdentity (Get-AiwContainedPath $root $r.sourceLocators.taskRelativePath)}else{[string]$composition.($field.Name)}
            if($live-cne[string]$field.Value){throw ('ADOPTION_PROCESS_SOURCE_DRIFT|'+$field.Name)}
        }
        # All unrelated sources must remain exactly the original sources. The
        # projected managed files and package fields are proved separately above.
        $targetComposer=Get-AiwAdoptionRuntimeModule $p.targetDistribution.runtimeRoot ('framework/versions/'+$targetVersion+'/scripts/ProcessRequirementComposition.psm1') @('Get-AiwProcessBindingSnapshot')
        $selectionArguments=Get-AiwAdoptionSelectionArguments $targetComposer.ExportedCommands['Get-AiwProcessBindingSnapshot'] $r $composition.bindingSelectionContext $composition
        $bindings=& $targetComposer.ExportedCommands['Get-AiwProcessBindingSnapshot'] -ProjectRoot $root -FrameworkRoot $p.targetDistribution.runtimeRoot -TargetVersion $targetVersion -TaskRelativePath $r.sourceLocators.taskRelativePath -ForbiddenPaths @($c.forbiddenScope) -ProspectiveAdoptionProjection:($t.metadata.operation-ceq'UPGRADE_FORMAT_TRANSITION') @selectionArguments
        $projectedFields=@('frameworkVersionIdentity','releaseManifestIdentity','nativeCatalogIdentity','correctionCoverageIdentity','bootstrapManagedIdentity','projectAgentsIdentity')
        if('.ai-workspace/corrections.json'-cin@($t.projection.objects.path)){$projectedFields+='correctionsIdentity'}
        if($targetVersion-ceq'2.0.0'){$projectedFields+=@('projectConfigIdentity','policyIdentity','taskIdentity','projectStandardsIdentity','contentSnapshotIdentity','effectiveSetIdentity','implementationIdentity')}
        $targetStateEntry=@($t.projection.objects|Where-Object{$_.path-ceq('.ai-workspace/upgrade-recovery/'+$targetVersion+'/state.json')})[0]
        foreach($field in $bindings.PSObject.Properties){
            $name=$field.Name
            if($name-ceq'candidatePilotStateIdentity'){
                # Only this completed FORMAT branch used the prospective
                # reader. Admission, projection, live state and all postimages
                # were proved above; MISSING describes that reader's view.
                $expected=if($t.metadata.operation-ceq'UPGRADE_FORMAT_TRANSITION'-and[string]$field.Value-ceq'MISSING'){'MISSING'}else{[string]$targetStateEntry.newIdentity}
            }
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
        if($null-ne$delivery){$result.delivery=$delivery;$result.consumer=$boundDelivery.consumer;$result.finalizeInputIdentity=$inputDoc.Identity}
        if($t.metadata.operation-ceq'UPGRADE_FORMAT_TRANSITION'){
            $proof=[ordered]@{schemaVersion=1;inputIdentity=$inputDoc.Identity;inputBase64=[Convert]::ToBase64String($inputDoc.Bytes);discoverBase64=[Convert]::ToBase64String($receiptDoc.Bytes);resultIdentity=(Get-AiwByteIdentity ($script:Utf8NoBom.GetBytes(($result|ConvertTo-Json -Depth 100 -Compress)+"`n")));resultBase64=[Convert]::ToBase64String($script:Utf8NoBom.GetBytes(($result|ConvertTo-Json -Depth 100 -Compress)+"`n"))}
            if($null-ne$t.metadata.PSObject.Properties['originalFinalize']){
                # Preserve the first original-runtime result. Its raw input and
                # result bind the admitted projection; the current journal ID
                # changes when that proof is saved and cannot identify itself.
                Assert-AiwOriginalFormatFinalize $t
            }else{
                # Saving this first original result is the actual state write.
                # Recheck its original evidence and whole journal inside the
                # existing writer guard; ordinary final checks stay read-only.
                $save=[pscustomobject]@{root=$root;path=$txnDoc.Path;identity=$txnDoc.Identity;proof=$proof;references=@($inputDoc,$receiptDoc,$adDoc,$pkgDoc)}
                $null=Invoke-AiwRootProjectSourceScope -ProjectRoot $root -Mode WRITE -ArgumentList @($save) -Body {
                    param($save)
                    foreach($reference in $save.references){if((Get-AiwCurrentIdentity $reference.Path)-cne$reference.Identity){throw 'ADOPTION_PROCESS_EVIDENCE_CHANGED_DURING_CHECK'}}
                    $current=Read-AiwProjectJson $save.path 'TRANSACTION'
                    if($current.Identity-cne$save.identity){throw 'ADOPTION_PROCESS_TRANSACTION_DRIFT'}
                    foreach($object in $current.Value.projection.objects){if((Get-AiwCurrentIdentity (Get-AiwContainedPath $save.root $object.path))-cne$object.newIdentity){throw 'ADOPTION_PROCESS_OBJECT_PROOF'}}
                    $current.Value.metadata|Add-Member originalFinalize $save.proof
                    Write-AiwTransactionState $save.path $current.Value
                }
            }
            $result.adoptionTransactionIdentity=Get-AiwCurrentIdentity $txnDoc.Path
        }
        return $result
    }finally{if($cleanup-and(Test-Path -LiteralPath $inputDoc.Path -PathType Leaf)){[IO.File]::Delete($inputDoc.Path)}}

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
Export-ModuleMember -Function New-AiwAdoptionProcessPreparation,Invoke-AiwAdoptionProcessBoundary

# Finish one original SOURCE action after one proved O -> T adoption. O owns
# parsing, composition and evidence; T owns its completed adoption algorithm;
# this qualified root tool X only connects those existing consumers.
function Invoke-AiwOriginalSourceFinalize {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$InputPath,[Parameter(Mandatory)][string]$ExpectedInputIdentity,
        [string]$AdmitInputPath,[string]$ExpectedAdmitInputIdentity,
        [string]$AdmitResultPath,[string]$ExpectedAdmitResultIdentity,
        [string]$AdoptionAuthorizationPackagePath,[string]$ExpectedAdoptionAuthorizationIdentity,
        [string]$AdoptionFinalizeResultPath,[string]$ExpectedAdoptionFinalizeResultIdentity,
        [string]$ExpectedAdoptionTransactionIdentity,[Parameter(Mandatory)][string]$ObservedActor,
        [string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@(),
        [switch]$CompleteOriginalSourceAfterAgentsChange,
        [string]$OriginalAgentsPreimagePath,[string]$ExpectedOriginalAgentsPreimageIdentity,
        [string]$ExpectedCurrentAgentsIdentity,
        [string]$CurrentCompletionDecisionPath,[string]$ExpectedCurrentCompletionDecisionIdentity,
        [ValidateSet('CURRENT_AND_COVERED','WITHDRAWN','UNKNOWN')][string]$CurrentCompletionPermission='UNKNOWN')
    $executionState=Get-AiwAdoptionRuntimeModule (Split-Path -Parent $PSScriptRoot) 'scripts/ProjectAdoptionState.psm1' @('Enter-AiwRootProjectSourceScope','Exit-AiwRootProjectSourceScope')
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $lease=& $executionState.ExportedCommands['Enter-AiwRootProjectSourceScope'] -ProjectRoot $root -Mode OBSERVE
    try{
        if($ObservedActor-cne[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')){throw 'ORIGINAL_SOURCE_HOST_ACTOR'}
        if([string]::IsNullOrWhiteSpace($AdmitInputPath)-or[string]::IsNullOrWhiteSpace($ExpectedAdmitInputIdentity)-or[string]::IsNullOrWhiteSpace($AdmitResultPath)-or[string]::IsNullOrWhiteSpace($ExpectedAdmitResultIdentity)){throw 'ORIGINAL_SOURCE_ADMISSION_REQUIRED'}
        $adoptionValues=@($AdoptionAuthorizationPackagePath,$ExpectedAdoptionAuthorizationIdentity,$AdoptionFinalizeResultPath,$ExpectedAdoptionFinalizeResultIdentity,$ExpectedAdoptionTransactionIdentity)
        $agentsValues=@($OriginalAgentsPreimagePath,$ExpectedOriginalAgentsPreimageIdentity,$ExpectedCurrentAgentsIdentity,$CurrentCompletionDecisionPath,$ExpectedCurrentCompletionDecisionIdentity)
        if($CompleteOriginalSourceAfterAgentsChange){
            if(@($adoptionValues|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ORIGINAL_SOURCE_COMPLETION_MODE_CONFLICT'}
            if([string]::IsNullOrWhiteSpace($OriginalAgentsPreimagePath)-or[string]::IsNullOrWhiteSpace($ExpectedOriginalAgentsPreimageIdentity)){throw 'ORIGINAL_SOURCE_AGENTS_PREIMAGE_REQUIRED'}
            if([string]::IsNullOrWhiteSpace($ExpectedCurrentAgentsIdentity)){throw 'ORIGINAL_SOURCE_CURRENT_AGENTS_BINDING_REQUIRED'}
            if([string]::IsNullOrWhiteSpace($CurrentCompletionDecisionPath)-or[string]::IsNullOrWhiteSpace($ExpectedCurrentCompletionDecisionIdentity)){throw 'ORIGINAL_SOURCE_CURRENT_COMPLETION_DECISION_REQUIRED'}
        }else{
            if(@($agentsValues|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}).Count-or$CurrentCompletionPermission-cne'UNKNOWN'){throw 'ORIGINAL_SOURCE_COMPLETION_MODE_REQUIRED'}
            if(@($adoptionValues|Where-Object{[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ORIGINAL_SOURCE_COMPLETED_ADOPTION_EVIDENCE_REQUIRED'}
        }
        $completionReadRefs=@($InputPath,$AdmitInputPath,$AdmitResultPath)
        if($CompleteOriginalSourceAfterAgentsChange){$completionReadRefs+=@($OriginalAgentsPreimagePath,$CurrentCompletionDecisionPath,(Join-Path $root 'AGENTS.md'))}else{$completionReadRefs+=@($AdoptionAuthorizationPackagePath,$AdoptionFinalizeResultPath)}
        $forbidden=@($ForbiddenPaths)+@($ProtectedPaths)
        $checkPath={param([string]$path)
            $full=[IO.Path]::GetFullPath($path)
            foreach($denied in $forbidden){
                $absolute=if([IO.Path]::IsPathRooted($denied)){[IO.Path]::GetFullPath($denied)}else{[IO.Path]::GetFullPath((Join-Path $root $denied))}
                if($full.Equals($absolute,[StringComparison]::OrdinalIgnoreCase)-or$full.StartsWith($absolute.TrimEnd('/','\')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ORIGINAL_SOURCE_PROTECTED_PATH'}
            }
            $null=Get-AiwContainedPath $root ([IO.Path]::GetRelativePath($root,$full).Replace('\','/'))
        }
        $projectPath=Join-Path $root '.ai-workspace/project.json';& $checkPath $projectPath
        $currentProject=Read-AiwProjectJson $projectPath 'SOURCE_CURRENT_PROJECT'
        $forbidden+=@($currentProject.Value.routineExcludedPaths)
        foreach($path in $completionReadRefs){& $checkPath $path}
        $toolRoot=Split-Path -Parent $PSScriptRoot
        $toolBinding=Get-AiwDistributionBinding $toolRoot '2.0.0' -Required
        $null=Assert-AiwDistributionBinding $toolBinding $toolRoot '2.0.0'
        # This finite completion path does not discover substitute authority,
        # continue a plan, publish standards, migrate a task or choose a target.
        $inputDoc=Read-AiwAdoptionEvidence $InputPath $ExpectedInputIdentity 'SOURCE_FINALIZE'
        $b=$inputDoc.Value
        $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState','evidenceRefs')
        if($null-ne$b.PSObject.Properties['deliveryContext']){$fields+='deliveryContext'}
        $stopOriginalSource=$false
        if($null-ne$b.PSObject.Properties['continuationDisposition']){
            $fields+='continuationDisposition'
            if(-not$CompleteOriginalSourceAfterAgentsChange-or$b.continuationDisposition-isnot[string]-or$b.continuationDisposition-cne'STOP'){throw 'ORIGINAL_SOURCE_STOP_DISPOSITION_REQUIRED'}
            $stopOriginalSource=$true
        }
        Assert-AiwAdoptionSame @($b.PSObject.Properties.Name|Sort-Object) @($fields|Sort-Object) 'ORIGINAL_SOURCE_BOUNDARY_FIELDS'
        if($b.schemaVersion-ne3-or$b.mode-cne'FINALIZE_OUTPUT'-or$b.protectionState-cne'BOUND'){throw 'ORIGINAL_SOURCE_FINALIZE_ONLY'}
        & $checkPath $b.discoverReceiptPath
        $rd=Read-AiwAdoptionEvidence $b.discoverReceiptPath $b.expectedDiscoverReceiptIdentity 'SOURCE_DISCOVER';$raw=$rd.Value
        if($raw.schemaVersion-notin@(3,4)-or$raw.binding.frameworkVersion-cne'2.0.0'){throw 'ORIGINAL_SOURCE_CONTRACT_UNSUPPORTED'}
        $oldRuntime=[string]$raw.sourceLocators.frameworkRoot
        $oldStateModule=Get-AiwAdoptionRuntimeModule $oldRuntime 'scripts/ProjectAdoptionState.psm1' @('Read-AiwProjectJson')
        $originalReceipt=& $oldStateModule.ExportedCommands['Read-AiwProjectJson'] $rd.Path 'SOURCE_DISCOVER'
        if($originalReceipt.Identity-cne$rd.Identity){throw 'ORIGINAL_SOURCE_RECEIPT_DRIFT'}
        & $oldStateModule {param($value) Assert-AiwFixedReceiptShape $value} $originalReceipt.Value
        if(($raw.schemaVersion-eq3-and$raw.inputContractVersion-ne4)-or($raw.schemaVersion-eq4-and$raw.inputContractVersion-ne5)-or
           $raw.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or$raw.mode-cne'DISCOVER'-or$raw.authorityGranted-ne$false-or$raw.semanticCorrectnessProven-ne$false){throw 'ORIGINAL_SOURCE_RECEIPT_CONTRACT'}
        $oldDelivery=Get-AiwAdoptionRuntimeModule $oldRuntime 'framework/versions/2.0.0/scripts/WorkflowDelivery.psm1' @('Get-AiwBoundDelivery')
        # O's delivery module owns this compact-to-consumer view. Its boundary
        # script's nested Get-Receipt is not a callable module API.
        $r=& $oldDelivery {param($value) Get-DeliveryReceiptView $value} $originalReceipt.Value
        foreach($name in @('schemaVersion','status','contextIdentity','selectionIdentity','sourceBindings','intentEnvelope','selectedObligations')){$r|Add-Member -NotePropertyName $name -NotePropertyValue $raw.$name}
        $c=$r.authorityContext
        $contextBytes=$script:Utf8NoBom.GetBytes(($raw.binding|ConvertTo-Json -Depth 30 -Compress)+"`n"+($raw.intentEnvelope|ConvertTo-Json -Depth 30 -Compress))
        if((Get-AiwByteIdentity $contextBytes).Split('|')[1]-cne$r.contextIdentity-or$r.status-cne'PASS'-or$r.actionKind-cne'SOURCE_WRITE'-or$r.intentEnvelope.ambiguityState-cne'CLEAR'-or
           $c.actor-cne$ObservedActor-or(Resolve-AiwRepositoryRoot $c.projectRoot)-cne$root-or'SOURCE_WRITE'-cnotin@($c.authorizedActions)-or
           ($r.schemaVersion-eq4-and$c.executionContext.targetKind-cne'SAME_ROOT')){throw 'ORIGINAL_SOURCE_CONTEXT'}
        $forbidden+=@($c.forbiddenScope)+@($c.protectedScope)
        foreach($path in @($completionReadRefs)+@($rd.Path,$r.sourceLocators.authorizationPackagePath)){& $checkPath $path}
        $packageDoc=Read-AiwAdoptionEvidence $r.sourceLocators.authorizationPackagePath $c.authorizationIdentity 'SOURCE_PACKAGE';$package=$packageDoc.Value
        if($package.schemaVersion-notin@(1,2)-or$package.grantee-cne$c.actor-or$package.owner-cne$c.taskOwner-or$package.taskId-cne$c.taskId-or
           $package.taskIdentity-cne$c.taskIdentity-or$package.projectConfigIdentity-cne$r.sourceBindings.projectConfigIdentity-or$package.userConfirmation-cne$c.userDecision){throw 'ORIGINAL_SOURCE_PACKAGE'}
        foreach($name in @('sourcePublicationBinding','transitionPlan','repairReviewBinding','selfCheckRepairLimit')){if($null-ne$package.PSObject.Properties[$name]){throw ('ORIGINAL_SOURCE_UNSUPPORTED_PACKAGE|'+$name)}}
        if($stopOriginalSource-and$null-ne$package.PSObject.Properties['continuationPlan']){
            # The admitted SOURCE may be stopped, but its future review action
            # is never resumed or derived by this read-only completion.
            Assert-AiwAdoptionSame @($package.actions) @('SOURCE_WRITE','REVIEW_ROUTE') 'ORIGINAL_SOURCE_STOP_ACTIONS'
            Assert-AiwAdoptionSame @($package.continuationPlan) @('SOURCE_WRITE','REVIEW_ROUTE') 'ORIGINAL_SOURCE_STOP_PLAN'
        }else{
            foreach($name in @('continuationPlan','repairReviewPlan')){if($null-ne$package.PSObject.Properties[$name]){throw ('ORIGINAL_SOURCE_UNSUPPORTED_PACKAGE|'+$name)}}
            Assert-AiwAdoptionSame @($package.actions) @('SOURCE_WRITE') 'ORIGINAL_SOURCE_ACTION'
        }
        Assert-AiwAdoptionSame @($package.exactPaths|Sort-Object) @($r.exactPaths|Sort-Object) 'ORIGINAL_SOURCE_SCOPE'
        $oldEvidence=Get-AiwAdoptionRuntimeModule $oldRuntime 'framework/versions/2.0.0/scripts/ResultEvidence.psm1' @('Get-AiwBoundaryEvidence','Get-AiwSelfCheckOutcome','New-AiwPackageEvidenceContext','Get-AiwFinalizedObjectPostimages','Read-AiwEvidenceReference')
        $evidenceArguments=@{ProjectRoot=$root;Package=$package;FrameworkRoot=$oldRuntime;ForbiddenPaths=$forbidden}
        if($oldEvidence.ExportedCommands['New-AiwPackageEvidenceContext'].Parameters.ContainsKey('TaskPath')){$evidenceArguments.TaskPath=$r.sourceLocators.taskRelativePath}
        $evidenceContext=& $oldEvidence.ExportedCommands['New-AiwPackageEvidenceContext'] @evidenceArguments
        # O16 compares exclusions relative to its finite, validated read roots.
        # Keep every original/absolute restriction and add its root-relative
        # spelling in a private consumption view. This can only narrow reads;
        # neither original authority bytes nor O's functions are modified.
        $evidenceForbidden=@($forbidden)+@($evidenceContext.ForbiddenPaths)
        foreach($boundRoot in $evidenceContext.Roots){
            $boundRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($boundRoot))
            foreach($denied in @($evidenceForbidden)){
                if(-not[IO.Path]::IsPathRooted($denied)){continue}
                $absolute=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($denied))
                if($boundRoot.Equals($absolute,[StringComparison]::OrdinalIgnoreCase)-or$boundRoot.StartsWith($absolute+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ORIGINAL_SOURCE_PROTECTED_ROOT'}
                if($absolute.StartsWith($boundRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
                    $evidenceForbidden+=[IO.Path]::GetRelativePath($boundRoot,$absolute).Replace('\','/')
                }
            }
        }
        $evidenceForbidden=@($evidenceForbidden|Select-Object -Unique)
        $evidenceContext.ForbiddenPaths=$evidenceForbidden
        $evidenceReceipt=$r|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $evidenceReceipt.authorityContext.forbiddenScope=$evidenceForbidden
        # Resolve O's actual candidate root and all current exclusions before
        # any composer or postimage consumer can read a candidate's bytes.
        & $oldEvidence {param($context,$paths) foreach($path in $paths){$null=Resolve-EvPath $context $path -Candidate}} $evidenceContext @($r.exactPaths)
        $oldComposer=Get-AiwAdoptionRuntimeModule $oldRuntime 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1' @('Get-AiwProcessDecisionIdentity','Invoke-ProcessRequirementComposition','Get-AiwProcessSemanticText','New-AiwAdoptionContentContext','Get-AiwProcessBindingSnapshot')
        $admitInput=Read-AiwAdoptionEvidence $AdmitInputPath $ExpectedAdmitInputIdentity 'SOURCE_ADMIT_INPUT';$a=$admitInput.Value
        $admitDoc=Read-AiwAdoptionEvidence $AdmitResultPath $ExpectedAdmitResultIdentity 'SOURCE_ADMIT_RESULT';$ad=$admitDoc.Value
        & $oldStateModule {
            param($a,$b)
            foreach($boundary in @($a,$b)){
                $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')
                foreach($optional in @('evidenceRefs','deliveryContext','continuationDisposition')){if($null-ne$boundary.PSObject.Properties[$optional]){$fields+=$optional}}
                Assert-AiwAdoptionFields $boundary $fields 'ORIGINAL_SOURCE_BOUNDARY'
                Assert-AiwAdoptionStringFields $boundary @('mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','publicDecisionIdentity','protectionState') 'ORIGINAL_SOURCE_BOUNDARY'
                foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){
                    if($boundary.$name-isnot[array]-or@($boundary.$name|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace($_)}).Count){throw 'ORIGINAL_SOURCE_BOUNDARY_ARRAY'}
                }
            }
        } $a $b
        foreach($boundary in @($a,$b)){
            if($null-ne$boundary.PSObject.Properties['evidenceRefs']){
                & $oldEvidence {param($context,$refs) Assert-EvRefs $refs -Typed;foreach($ref in $refs){$null=Resolve-EvPath $context $ref.path}} $evidenceContext $boundary.evidenceRefs
            }
        }
        if($null-ne$a.PSObject.Properties['continuationDisposition']-or$a.mode-cne'ADMIT_ACTION'-or$a.schemaVersion-ne3-or$a.discoverReceiptPath-cne$b.discoverReceiptPath-or$a.expectedDiscoverReceiptIdentity-cne$rd.Identity-or
           $a.protectionState-cne$b.protectionState-or$a.publicDecisionIdentity-cne$b.publicDecisionIdentity-or$ad.status-cne'PASS'-or$ad.mode-cne'ADMIT_ACTION'-or
           $ad.selectionIdentity-cne$r.selectionIdentity-or$ad.authorityGranted-ne$false-or$ad.semanticCorrectnessProven-ne$false-or@($ad.missingPreparation).Count-or@($ad.missingResult).Count-or
           (& $oldComposer.ExportedCommands['Get-AiwProcessDecisionIdentity'] $raw $a)-cne$ad.decisionIdentity){throw 'ORIGINAL_SOURCE_ADMISSION'}
        $completionDocuments=@();$completionAdoptionDocuments=@()
        if($CompleteOriginalSourceAfterAgentsChange){
            # This is completion under the original admission, not historical
            # success, a new source action, or an invented adoption transaction.
            $binding=Get-AiwAdoptedDistributionBinding $root '2.0.0'
            if($null-eq$binding-or-not([IO.Path]::GetFullPath($binding.runtimeRoot).Equals([IO.Path]::GetFullPath($oldRuntime),[StringComparison]::OrdinalIgnoreCase))){throw 'ORIGINAL_SOURCE_SAME_PIN_REQUIRED'}
            $targetBinding=Assert-AiwDistributionBinding $binding $oldRuntime '2.0.0'
            $oldReader=Get-AiwAdoptionRuntimeModule $oldRuntime 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1' @('Get-AiwReleasePackageFacts')
            $null=& $oldReader {
                param($root,$binding,$ownerPath)
                $command=Get-Command Get-AiwFixedReleaseProjection -ErrorAction Stop
                if($null-eq$command.Module-or$command.Module.Path-cne$ownerPath){throw 'ORIGINAL_SOURCE_RELEASE_READER_OWNER'}
                Get-AiwFixedReleaseProjection (Join-Path $root 'framework/versions/2.0.0') $root $binding
            } $oldRuntime $targetBinding $oldReader.Path
            $readText={param([string]$path,[string]$identity,[string]$label)
                & $checkPath $path
                if($identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-AiwCurrentIdentity $path)-cne$identity){throw ('ORIGINAL_SOURCE_'+$label+'_DRIFT')}
                $bytes=[IO.File]::ReadAllBytes($path)
                if((Get-AiwByteIdentity $bytes)-cne$identity){throw ('ORIGINAL_SOURCE_'+$label+'_DRIFT')}
                $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
                if([string]::IsNullOrWhiteSpace($text)-or$text.Contains([char]0)){throw ('ORIGINAL_SOURCE_'+$label+'_TEXT')}
                [pscustomobject]@{Path=[IO.Path]::GetFullPath($path);Identity=$identity;Bytes=$bytes;Text=$text}
            }
            $agentsPreimage=& $readText $OriginalAgentsPreimagePath $ExpectedOriginalAgentsPreimageIdentity 'AGENTS_PREIMAGE'
            if($agentsPreimage.Identity-cne$r.sourceBindings.projectAgentsIdentity){throw 'ORIGINAL_SOURCE_AGENTS_PREIMAGE_NOT_ORIGINAL'}
            $currentAgents=& $readText (Join-Path $root 'AGENTS.md') $ExpectedCurrentAgentsIdentity 'CURRENT_AGENTS'
            if($currentAgents.Identity-ceq$agentsPreimage.Identity){throw 'ORIGINAL_SOURCE_AGENTS_CHANGE_REQUIRED_USE_ORIGINAL_FINALIZE'}
            $completionDecision=& $readText $CurrentCompletionDecisionPath $ExpectedCurrentCompletionDecisionIdentity 'COMPLETION_DECISION'
            if($CurrentCompletionPermission-cne'CURRENT_AND_COVERED'){throw ('ORIGINAL_SOURCE_COMPLETION_PERMISSION_'+$CurrentCompletionPermission)}
            # The caller has read both complete AGENTS and the actual decision.
            # This explicit semantic assessment is instruction-bound; hashes
            # cannot infer that a human grant survived or permits completion.
            $selection=[pscustomobject]@{profile=$c.profile;role=$c.role;phase=$c.phase;actor=$c.actor;actionKind=$r.actionKind;resultKind=$r.resultKind;exactPaths=@($r.exactPaths);capabilities=@($c.observedCapabilities);intentEnvelope=$r.intentEnvelope}
            $live=& $oldComposer.ExportedCommands['Get-AiwProcessBindingSnapshot'] -ProjectRoot $root -FrameworkRoot $oldRuntime -TargetVersion '2.0.0' -TaskRelativePath $r.sourceLocators.taskRelativePath -ForbiddenPaths $forbidden -SelectionContext $selection
            foreach($field in $r.sourceBindings.PSObject.Properties){
                # The live read must obey all current restrictions. O includes
                # its forbidden array in effectiveSetIdentity; the protected
                # stage composition below separately verifies that exact
                # original identity using the original array, including order.
                if($field.Name-cin@('projectAgentsIdentity','effectiveSetIdentity')){continue}
                if([string]$live.($field.Name)-cne[string]$field.Value){throw ('ORIGINAL_SOURCE_CURRENT_BINDING_DRIFT|'+$field.Name)}
            }
            $completionDocuments=@($agentsPreimage,$currentAgents,$completionDecision)
        }else{
        $matches=@(foreach($relative in @('.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
            $path=Get-AiwContainedPath $root $relative
            & $checkPath $path
            if((Get-AiwCurrentIdentity $path)-ceq$ExpectedAdoptionTransactionIdentity){Read-AiwProjectJson $path 'SOURCE_ADOPTION_TRANSACTION'}
        })
        if($matches.Count-ne1){throw 'ORIGINAL_SOURCE_ADOPTION_TRANSACTION_DRIFT'}
        $txnDoc=$matches[0];$txn=$txnDoc.Value
        if($txn.state-cne'COMPLETE'-or$txn.transactionComplete-ne$true-or$txn.metadata.operation-cnotin@('UPGRADE_RUNTIME_REFRESH','UPGRADE_FORMAT_TRANSITION')){throw 'ORIGINAL_SOURCE_COMPLETED_ADOPTION_REQUIRED'}
        $null=Assert-AiwProjectionContract $root $txn.projection
        if(@($r.exactPaths|Where-Object{$_-cin@($txn.projection.objects.path)}).Count){throw 'ORIGINAL_SOURCE_ADOPTION_SCOPE_OVERLAP'}
        foreach($entry in $txn.projection.objects){& $checkPath (Join-Path $root $entry.path)}
        $stateEntry=@($txn.projection.objects|Where-Object path -CEQ '.ai-workspace/upgrade-recovery/2.0.0/state.json')
        if($stateEntry.Count-ne1-or-not$stateEntry[0].oldExists-or-not$stateEntry[0].newExists-or$stateEntry[0].oldIdentity-cne$r.sourceBindings.candidatePilotStateIdentity){throw 'ORIGINAL_SOURCE_OLD_STATE_BINDING'}
        $oldState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($stateEntry[0].oldBase64))|ConvertFrom-Json -Depth 100
        $targetState=$script:Utf8NoBom.GetString([Convert]::FromBase64String($stateEntry[0].newBase64))|ConvertFrom-Json -Depth 100
        $oldBinding=Assert-AiwDistributionBinding $oldState.distributionBinding $oldRuntime '2.0.0'
        $targetBinding=Assert-AiwDistributionBinding $targetState.distributionBinding $txn.metadata.distributionBinding.runtimeRoot '2.0.0'
        # Read O through O's own release reader, including pre-observation APIs.
        $oldReader=Get-AiwAdoptionRuntimeModule $oldRuntime 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1' @('Get-AiwReleasePackageFacts')
        $null=& $oldReader {
            param($root,$binding,$ownerPath)
            $command=Get-Command Get-AiwFixedReleaseProjection -ErrorAction Stop
            if($null-eq$command.Module-or$command.Module.Path-cne$ownerPath){throw 'ORIGINAL_SOURCE_RELEASE_READER_OWNER'}
            Get-AiwFixedReleaseProjection (Join-Path $root 'framework/versions/2.0.0') $root $binding
        } $oldRuntime $oldBinding $oldReader.Path
        $targetModule=Get-AiwAdoptionRuntimeModule $targetBinding.runtimeRoot 'scripts/ProjectAdoptionTransaction.psm1' @('Resume-AiwRuntimeAdoption')
        $verified=& $targetModule.ExportedCommands['Resume-AiwRuntimeAdoption'] -RepositoryRoot $root -ExpectedTransactionIdentity $txnDoc.Identity -AuthorizationPackagePath $AdoptionAuthorizationPackagePath -ExpectedAuthorizationPackageIdentity $ExpectedAdoptionAuthorizationIdentity -ObservedActor $txn.metadata.actor
        if($verified.status-cne'COMPLETE'-or$verified.writes-ne0){throw 'ORIGINAL_SOURCE_ADOPTION_INCOMPLETE'}
        if($txn.metadata.operation-ceq'UPGRADE_FORMAT_TRANSITION'){
            $targetReader=Get-AiwAdoptionRuntimeModule $targetBinding.runtimeRoot 'scripts/ProjectAdoptionState.psm1' @('Assert-AiwOriginalFormatFinalize')
            & $targetReader.ExportedCommands['Assert-AiwOriginalFormatFinalize'] $txn
        }
        $adoptionFinal=Read-AiwAdoptionEvidence $AdoptionFinalizeResultPath $ExpectedAdoptionFinalizeResultIdentity 'ADOPTION_FINALIZE_RESULT';$f=$adoptionFinal.Value
        $adoptionAdmitBytes=[Convert]::FromBase64String($txn.metadata.originalAdmitBase64)
        if((Get-AiwByteIdentity $adoptionAdmitBytes)-cne$txn.metadata.originalAdmitIdentity){throw 'ORIGINAL_SOURCE_ADOPTION_ADMIT_DRIFT'}
        $adoptionAdmit=$script:Utf8NoBom.GetString($adoptionAdmitBytes)|ConvertFrom-Json -Depth 100
        if($f.status-cne'PASS'-or$f.mode-cne'FINALIZE_OUTPUT'-or$f.adoptionTransactionIdentity-cne$txnDoc.Identity-or
           $f.originalAdmitDecisionIdentity-cne$adoptionAdmit.decisionIdentity-or$f.originalDiscoverReceiptIdentity-cne$adoptionAdmit.originalAdmissionInput.expectedDiscoverReceiptIdentity-or
           $f.authorityGranted-ne$false-or$f.semanticCorrectnessProven-ne$false-or@($f.missingPreparation).Count-or@($f.missingResult).Count){throw 'ORIGINAL_SOURCE_ADOPTION_FINALIZE_REQUIRED'}
        foreach($entry in $txn.projection.objects){if((Get-AiwCurrentIdentity (Get-AiwContainedPath $root $entry.path))-cne$entry.newIdentity){throw ('ORIGINAL_SOURCE_ADOPTION_POSTIMAGE_DRIFT|'+$entry.path)}}
        Assert-AiwAdoptionSame (Get-AiwAdoptedDistributionBinding $root '2.0.0') $targetBinding 'ORIGINAL_SOURCE_LIVE_DISTRIBUTION'
            $completionAdoptionDocuments=@($txnDoc,$adoptionFinal)
        }

        # Current authority and narrowing remain effective. Stage only exact
        # original carriers from the already proved projection; source bodies
        # stay at their original allowed locations via O's content context.
        $stage=Join-Path ([IO.Path]::GetTempPath()) ('aiw-original-source-'+[guid]::NewGuid().ToString('N'))
        $null=[IO.Directory]::CreateDirectory($stage)
        try{
            foreach($relative in @('.ai-workspace/project.json','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md',$r.sourceLocators.taskRelativePath)){
                $live=Get-AiwContainedPath $root $relative
                foreach($denied in $forbidden){
                    $absolute=if([IO.Path]::IsPathRooted($denied)){[IO.Path]::GetFullPath($denied)}else{[IO.Path]::GetFullPath((Join-Path $root $denied))}
                    if($live.Equals($absolute,[StringComparison]::OrdinalIgnoreCase)-or$live.StartsWith($absolute.TrimEnd('/','\')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ORIGINAL_SOURCE_PROTECTED_CARRIER'}
                }
                if($CompleteOriginalSourceAfterAgentsChange-and$relative-ceq'AGENTS.md'){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $relative) $agentsPreimage.Bytes;continue}
                $projection=@(if(-not$CompleteOriginalSourceAfterAgentsChange){$txn.projection.objects|Where-Object path -CEQ $relative})
                if($projection.Count-eq1){if($projection[0].oldExists){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $relative) ([Convert]::FromBase64String($projection[0].oldBase64))}}
                elseif(Test-Path -LiteralPath $live -PathType Leaf){Write-AiwAtomicBytes (Get-AiwContainedPath $stage $relative) ([IO.File]::ReadAllBytes($live))}
            }
            foreach($pair in @(@('.ai-workspace/controller.json',$r.sourceBindings.controllerIdentity),@($r.sourceLocators.taskRelativePath,$c.taskIdentity))){
                if((Get-AiwCurrentIdentity (Get-AiwContainedPath $root $pair[0]))-cne$pair[1]){throw ('ORIGINAL_SOURCE_CURRENT_AUTHORITY_DRIFT|'+$pair[0])}
            }
            $oldProject=(Read-AiwProjectJson (Get-AiwContainedPath $stage '.ai-workspace/project.json') 'SOURCE_ORIGINAL_PROJECT').Value
            $oldPermission=if($null-ne$oldProject.PSObject.Properties['sourceBindings']){$oldProject.sourceBindings}else{$null}
            $currentPermission=if($null-ne$currentProject.Value.PSObject.Properties['sourceBindings']){$currentProject.Value.sourceBindings}else{$null}
            Assert-AiwAdoptionSame $oldPermission $currentPermission 'ORIGINAL_SOURCE_PERMISSION_CHANGE_UNSUPPORTED'
            # T's proved adoption may relocate the same human grant out of the
            # old managed block. Bind that change to its original full preimage
            # and already checked live postimage, rather than comparing layouts.
            # A later withdrawal/narrowing cannot match that saved postimage.
            $agentsProjection=@(if(-not$CompleteOriginalSourceAfterAgentsChange){$txn.projection.objects|Where-Object path -CEQ 'AGENTS.md'})
            if($agentsProjection.Count-eq1-and$agentsProjection[0].oldIdentity-cne$r.sourceBindings.projectAgentsIdentity){throw 'ORIGINAL_SOURCE_CURRENT_USER_DECISION_CHANGED'}
            $context=& $oldComposer.ExportedCommands['New-AiwAdoptionContentContext'] -ProjectRoot $stage -SourceProjectRoot $root -ExpectedProjectConfigIdentity $r.sourceBindings.projectConfigIdentity -ForbiddenPaths $forbidden
            # O16 includes the exact original forbidden array in its effective
            # set identity. Reproduce that original input, including order;
            # current restrictions independently constrain the already checked
            # carriers and the content context's actual source reads.
            $composition=& $oldComposer.ExportedCommands['Invoke-ProcessRequirementComposition'] -ProjectRoot $stage -FrameworkRoot $oldRuntime -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity $r.sourceBindings.projectConfigIdentity -ExpectedCorrectionsIdentity $r.sourceBindings.correctionsIdentity -Profile $c.profile -Role $c.role -Phase $c.phase -Actor $c.actor -TaskIdentity $c.taskIdentity -Capabilities @($c.observedCapabilities) -Objective (& $oldComposer.ExportedCommands['Get-AiwProcessSemanticText'] $r.intentEnvelope) -ActionKind 'SOURCE_WRITE' -ResultKind $r.resultKind -ExactPaths @($r.exactPaths) -ForbiddenPaths @($c.forbiddenScope) -IntentEnvelope $r.intentEnvelope -EvaluationOnly -ContentContext $context
            foreach($field in $r.sourceBindings.PSObject.Properties){
                if($field.Name-ceq'candidatePilotStateIdentity'){continue}
                $actual=if($field.Name-ceq'taskIdentity'){$c.taskIdentity}else{$composition.($field.Name)}
                if([string]$actual-cne[string]$field.Value){throw ('ORIGINAL_SOURCE_CONTRACT_NOT_PRESERVED|'+$field.Name)}
            }
            $obligations=@($composition.selectedRequirements|ForEach-Object{[pscustomobject]@{requirementId=$_.requirementId;preparationRequirements=@($_.preparationRequirements);resultRequirements=@($_.resultRequirements)}})
            Assert-AiwAdoptionSame $obligations @($r.selectedObligations) 'ORIGINAL_SOURCE_OBLIGATIONS'
        }finally{
            $parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar
            $full=[IO.Path]::GetFullPath($stage)
            if(-not$full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-original-source-')){throw 'ORIGINAL_SOURCE_STAGE_CLEANUP_BOUNDARY'}
            [IO.Directory]::Delete($full,$true)
        }
        # Reuse O's strict postimage and typed evidence consumers, on the actual
        # candidate root. No replacement receipt, new ADMIT or future lease.
        $postimages=@(& $oldEvidence.ExportedCommands['Get-AiwFinalizedObjectPostimages'] $b @($r.exactPaths))
        foreach($postimage in $postimages){
            $ref=[pscustomobject]@{path=$postimage.path;identity=$(if($postimage.identity-ceq'NEW'){'MISSING'}else{$postimage.identity})}
            $token='OBJECT_POSTIMAGE|'+$ref.path+'|'+$ref.identity
            if(@($b.resultReceipts|Where-Object{$_-ceq$token}).Count-ne1){throw ('RESULT_POSTIMAGE_RECEIPT_REQUIRED|'+$ref.path)}
            $null=& $oldEvidence.ExportedCommands['Read-AiwEvidenceReference'] $evidenceContext $ref -Candidate
        }
        $evidenceOptions=@{}
        if($oldEvidence.ExportedCommands['Get-AiwBoundaryEvidence'].Parameters.ContainsKey('EvidenceContext')){$evidenceOptions.EvidenceContext=$evidenceContext}
        $admissionEvidence=& $oldEvidence.ExportedCommands['Get-AiwBoundaryEvidence'] $evidenceReceipt $a @evidenceOptions
        $evidence=& $oldEvidence.ExportedCommands['Get-AiwBoundaryEvidence'] $evidenceReceipt $b @evidenceOptions
        $self=& $oldEvidence.ExportedCommands['Get-AiwSelfCheckOutcome'] $evidence.references $evidence.records
        if($stopOriginalSource){
            if($self-cnotin@('FAIL','INCOMPLETE')){throw 'ORIGINAL_SOURCE_STOP_FAILED_SELF_REQUIRED'}
        }elseif($self-cin@('FAIL','INCOMPLETE')){throw ('ORIGINAL_SOURCE_SELF_CHECK_'+$self)}
        $delivery=& $oldDelivery.ExportedCommands['Get-AiwBoundDelivery'] $evidenceReceipt $b $evidence
        $stopDeliveryPending=$stopOriginalSource-and$null-ne$delivery-and-not$delivery.closureSatisfied
        if($null-ne$delivery-and-not$delivery.closureSatisfied-and-not$stopOriginalSource){throw 'ORIGINAL_SOURCE_DELIVERY_NOT_CONFIRMED'}
        $prepared=@($b.preparationReceipts|Where-Object{$_-cnotin@('SELF_CHECK_BOUND','REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED')})
        if('SELF_CHECK'-cin@($evidence.references|ForEach-Object kind)){$prepared+='SELF_CHECK_BOUND'}
        $originalPrepared=@($a.preparationReceipts|Where-Object{$_-cnotin@('SELF_CHECK_BOUND','REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED')})
        if('SELF_CHECK'-cin@($admissionEvidence.references|ForEach-Object kind)){$originalPrepared+='SELF_CHECK_BOUND'}
        if(@($r.selectedObligations.preparationRequirements|Where-Object{$_-cnotin$originalPrepared}).Count){throw 'ORIGINAL_SOURCE_ADMISSION_PREPARATION_INCOMPLETE'}
        $missingPrep=@($r.selectedObligations.preparationRequirements|Where-Object{$_-cnotin$prepared})
        $requiredResult=@($r.selectedObligations.resultRequirements)
        if($null-ne$delivery){$requiredResult=@($requiredResult|Where-Object{$_-cne'DELIVERY_RECEIPT'})}
        $providedResult=@($b.resultReceipts|Where-Object{$_-cnotin@('SELF_CHECK_BOUND','REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED')})
        if('REVIEW_VERDICT'-cin@($evidence.references|ForEach-Object kind)){$providedResult+='REVIEW_VERDICT_BOUND'}
        if('RESULT_ACCEPTANCE'-cin@($evidence.references|ForEach-Object kind)){$providedResult+='RESULT_ACCEPT_RECORDED'}
        $missingResult=@($requiredResult|Where-Object{$_-cnotin$providedResult})
        if($missingPrep.Count-or$missingResult.Count){throw 'ORIGINAL_SOURCE_OBLIGATIONS_INCOMPLETE'}
        if($null-eq$delivery-and$r.resultKind-cin@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','RESULT_ACCEPTANCE')-and@($b.deliveryReceipts).Count-eq0){throw 'ORIGINAL_SOURCE_DELIVERY_REQUIRED'}
        foreach($doc in @($inputDoc,$rd,$packageDoc,$admitInput,$admitDoc,$currentProject)+@($completionDocuments)+@($completionAdoptionDocuments)){if((Get-AiwCurrentIdentity $doc.Path)-cne$doc.Identity){throw 'ORIGINAL_SOURCE_EVIDENCE_DRIFT_DURING_CHECK'}}
        $result=[ordered]@{status='PASS';mode='FINALIZE_OUTPUT';reason=$(if($CompleteOriginalSourceAfterAgentsChange){'ORIGINAL_SOURCE_FINALIZED_AFTER_SAME_PIN_AGENTS_CHANGE'}else{'ORIGINAL_SOURCE_FINALIZED_AFTER_COMPLETED_ADOPTION'});originalDiscoverReceiptIdentity=$rd.Identity;originalAdmitDecisionIdentity=$ad.decisionIdentity;decisionIdentity=(& $oldComposer.ExportedCommands['Get-AiwProcessDecisionIdentity'] $raw $b);originalRuntimeRoot=$oldRuntime;targetRuntimeRoot=$targetBinding.runtimeRoot;executionRuntimeRoot=$toolRoot;actionOutcome='OBSERVED';successorState='NONE';missingPreparation=@();missingResult=@();authorityGranted=$false;semanticCorrectnessProven=$false;hostInvocationProven=$false;evidenceGrade='INSTRUCTION_BOUND'}
        if($stopOriginalSource){
            $result.actionOutcome=$self
            $result.reason='ORIGINAL_SOURCE_STOPPED_AFTER_SAME_PIN_AGENTS_CHANGE'
            $result.successorState='STOPPED'
            if($stopDeliveryPending){$result.status='BLOCKED';$result.reason='ORIGINAL_SOURCE_STOP_DELIVERY_NOT_CONFIRMED';$result.successorState='NONE';$result.missingResult=@('DELIVERY_NOT_CONFIRMED')}
        }
        if($CompleteOriginalSourceAfterAgentsChange){
            $result.originalAgentsPreimageIdentity=$agentsPreimage.Identity;$result.currentAgentsIdentity=$currentAgents.Identity
            $result.currentCompletionDecisionRef=[ordered]@{path=$completionDecision.Path;identity=$completionDecision.Identity};$result.currentCompletionPermission=$CurrentCompletionPermission
        }else{$result.adoptionTransactionIdentity=$txnDoc.Identity}
        if($null-ne$delivery){$result.delivery=$delivery.delivery;$result.consumer=$delivery.consumer;$result.finalizeInputIdentity=$inputDoc.Identity}
        return $result
    }finally{
        # O/T imports may expose same-name root functions. The scope must be
        # released by X's exact acquiring implementation even on an early O
        # evidence rejection, so cleanup cannot mask the original failure.
        & $executionState.ExportedCommands['Exit-AiwRootProjectSourceScope'] $lease
    }
}
Export-ModuleMember -Function Invoke-AiwOriginalSourceFinalize

function Get-AiwCorrectionAdoptionEvidence($Preparation) {
    if($null-ne$Preparation-and$null-ne$Preparation.PSObject.Properties['correctionAdoption']){return $Preparation.correctionAdoption}
    return $null
}

function Assert-AiwCorrectionAdoptionEvidence($Evidence,[string]$Root,$Projection,$Context) {
    if($null-eq$Evidence){return ,@()}
    Assert-AiwAdoptionSame @($Evidence.PSObject.Properties.Name|Sort-Object) @('schemaVersion','planIdentity','planBase64','scope','sourceReferences'|Sort-Object) 'CORRECTION_EVIDENCE_FIELDS'
    if($Evidence.schemaVersion-ne1-or$Evidence.scope-isnot[array]-or$Evidence.sourceReferences-isnot[array]){throw 'ADOPTION_CORRECTION_EVIDENCE_SHAPE'}
    $planBytes=[Convert]::FromBase64String($Evidence.planBase64)
    if((Get-AiwByteIdentity $planBytes)-cne$Evidence.planIdentity){throw 'ADOPTION_CORRECTION_PLAN_DRIFT'}
    $view=Join-Path ([IO.Path]::GetTempPath()) ('aiw-adoption-correction-proof-'+[guid]::NewGuid().ToString('N'))
    try{
        $null=[IO.Directory]::CreateDirectory($view)
        $planPath=Join-Path $view 'plan.json';Write-AiwAtomicBytes $planPath $planBytes
        $plan=(Read-AiwProjectJson $planPath 'CORRECTION_ADOPTION_PLAN').Value
        Import-Module (Join-Path $PSScriptRoot 'ProjectCorrectionLifecycle.psm1')
        $declared=@(Get-AiwCorrectionAdoptionScope $Root $plan @($Context.forbiddenScope))
        Assert-AiwAdoptionSame @($declared|Sort-Object) @($Evidence.scope|Sort-Object) 'CORRECTION_SCOPE'
        foreach($path in $declared){if($path-cnotin@($Context.exactScope)){throw 'ADOPTION_CORRECTION_UNDECLARED_PATH'}}
        # Rebuild only the saved original working view. Recovery can be midway
        # through the live projection; no current carrier substitutes for it.
        foreach($entry in $Projection.objects){
            if($entry.oldExists){Write-AiwAtomicBytes (Get-AiwContainedPath $view $entry.path) ([Convert]::FromBase64String($entry.oldBase64))}
        }
        foreach($reference in $Evidence.sourceReferences){
            Assert-AiwAdoptionSame @($reference.PSObject.Properties.Name|Sort-Object) @('path','identity'|Sort-Object) 'CORRECTION_SOURCE_REF'
            if($reference.path-cnotmatch'^\.ai-workspace/upgrade-recovery/corrections/[A-Z][A-Z0-9_]*/[A-Za-z0-9._-]+/(history|installation)\.json$'){throw 'ADOPTION_CORRECTION_SOURCE_REF_PATH'}
            Assert-AiwAdoptionProjectionProtection $Root ([pscustomobject]@{objects=@([pscustomobject]@{path=$reference.path})}) $Context
            $doc=Read-AiwAdoptionEvidence (Get-AiwContainedPath $Root $reference.path) $reference.identity 'CORRECTION_SOURCE'
            Write-AiwAtomicBytes (Get-AiwContainedPath $view $reference.path) $doc.Bytes
        }
        if($plan.schemaVersion-eq2){
            $group=New-AiwCorrectionAdoptionGroupProjection $view $plan @() @($Context.exactScope) @($Context.forbiddenScope)
            Assert-AiwAdoptionSame @($group.sourceReferences) @($Evidence.sourceReferences) 'CORRECTION_SOURCE_REFERENCES'
            $expected=$group.projection
        }else{$expected=New-AiwCorrectionAdoptionProjection $view $plan}
        $base=@('.ai-workspace/project.json','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','AGENTS.md','.ai-workspace/BOOTSTRAP.md')
        foreach($entry in $expected.objects){
            $actual=@($Projection.objects|Where-Object path -CEQ $entry.path)
            if($actual.Count-ne1-or$actual[0].oldIdentity-cne$entry.oldIdentity){throw 'ADOPTION_CORRECTION_PROJECTION_SOURCE'}
            if($entry.path-cnotin$base-and$actual[0].newIdentity-cne$entry.newIdentity){throw 'ADOPTION_CORRECTION_PROJECTION_TARGET'}
        }
        # Format conversion cannot replace the group result with an unrelated
        # carrier. Replay the existing adapter and exact selector conversion.
        $expectedCarrier=@($expected.objects|Where-Object path -CEQ '.ai-workspace/corrections.json')[0]
        $carrierPath=Get-AiwContainedPath $view '.ai-workspace/corrections.json'
        Write-AiwAtomicBytes $carrierPath ([Convert]::FromBase64String($expectedCarrier.newBase64))
        $targetVersionRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'framework/versions/2.0.0'
        $formatContext=[pscustomobject]@{ProjectId=($script:Utf8NoBom.GetString([Convert]::FromBase64String($expectedCarrier.newBase64))|ConvertFrom-Json -Depth 100).projectId;TargetProcessContractVersion='2.0.0'}
        $converted=Read-AiwAdoptionCorrectionsFormatObject -Root $view -Projection $null -Context $formatContext -TargetVersionRoot $targetVersionRoot
        if(-not(Test-AiwSamePinProcessProjection $Projection)){Convert-AiwAdoptionSelectors $converted.Value.corrections}
        $finalCarrier=@($Projection.objects|Where-Object path -CEQ '.ai-workspace/corrections.json')[0]
        Assert-AiwAdoptionSame $converted.Value ($script:Utf8NoBom.GetString([Convert]::FromBase64String($finalCarrier.newBase64))|ConvertFrom-Json -Depth 100) 'CORRECTION_FINAL_CARRIER'
        Assert-AiwCorrectionTargetOwnership $Root $Projection $Context
        return ,@($declared)
    }finally{
        $full=[IO.Path]::GetFullPath($view);$temp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
        if([IO.Path]::GetDirectoryName($full)-cne$temp-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-adoption-correction-proof-[a-f0-9]{32}$'){throw 'ADOPTION_CORRECTION_PROOF_CLEANUP_BOUNDARY'}
        if(Test-Path -LiteralPath $full){[IO.Directory]::Delete($full,$true)}
    }
}

function Assert-AiwAdoptionProjectionProtection([string]$Root,$Projection,$Context) {
    # Deny the whole scope before projection containment/reparse or byte I/O.
    $config=(Read-AiwProjectJson (Get-AiwContainedPath $Root '.ai-workspace/project.json') 'ADOPTION_PROJECT').Value
    foreach($entry in $Projection.objects){
        Assert-AiwRelativePath $entry.path
        $path=[IO.Path]::GetFullPath((Join-Path $Root $entry.path))
        foreach($scope in @($Context.forbiddenScope)+@($config.routineExcludedPaths)){
            $deny=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($scope)){$scope}else{Join-Path $Root $scope.TrimEnd('/')}))
            if($path.Equals($deny,[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith($deny.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ADOPTION_PROCESS_PROTECTED_PROJECTION'}
        }
    }
}


function Test-AiwSamePinProcessProjection($Projection) {
    $entries=@($Projection.objects|Where-Object path -CEQ '.ai-workspace/project.json')
    if($entries.Count-eq0){return $true}
    if($entries.Count-ne1-or-not$entries[0].oldExists-or-not$entries[0].newExists){return $false}
    $old=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entries[0].oldBase64))|ConvertFrom-Json -Depth 100
    $new=$script:Utf8NoBom.GetString([Convert]::FromBase64String($entries[0].newBase64))|ConvertFrom-Json -Depth 100
    return $old.schemaVersion-in@(6,7)-and$new.schemaVersion-eq$old.schemaVersion-and$old.frameworkVersion-ceq'2.0.0'-and$new.frameworkVersion-ceq'2.0.0'
}

function Assert-AiwCorrectionTargetOwnership([string]$Root,$Projection,$Context) {
    $carrier=@($Projection.objects|Where-Object path -CEQ '.ai-workspace/corrections.json')
    if($carrier.Count-ne1-or-not$carrier[0].newExists){throw 'ADOPTION_CORRECTION_CARRIER_REQUIRED'}
    $records=($script:Utf8NoBom.GetString([Convert]::FromBase64String($carrier[0].newBase64))|ConvertFrom-Json -Depth 100).corrections
    $active=@($records|Where-Object{$null-eq$_.PSObject.Properties['lifecycle']-or$_.lifecycle.state-ceq'ACTIVE'})
    $lifecycle=@(Import-Module (Join-Path $PSScriptRoot 'ProjectCorrectionLifecycle.psm1') -PassThru)[0]
    foreach($record in $active){
        if($null-eq$record.PSObject.Properties['lifecycle']-or$record.lifecycle.installation-is[string]){continue}
        $ref=$record.lifecycle.installation
        if($ref.locator-cnotmatch'^\.ai-workspace/upgrade-recovery/corrections/[A-Z][A-Z0-9_]*/[A-Za-z0-9._-]+/installation\.json$'){throw 'ADOPTION_CORRECTION_INSTALLATION_PATH'}
        Assert-AiwAdoptionProjectionProtection $Root ([pscustomobject]@{objects=@([pscustomobject]@{path=$ref.locator})}) $Context
        $entry=@($Projection.objects|Where-Object path -CEQ $ref.locator)
        if($entry.Count-eq1){if(-not$entry[0].newExists-or$entry[0].newIdentity-cne$ref.identity){throw 'ADOPTION_CORRECTION_INSTALLATION_DRIFT'};$bytes=[Convert]::FromBase64String($entry[0].newBase64)}
        else{$bytes=(Read-AiwAdoptionEvidence (Get-AiwContainedPath $Root $ref.locator) $ref.identity 'CORRECTION_INSTALLATION').Bytes}
        $install=$script:Utf8NoBom.GetString($bytes)|ConvertFrom-Json -Depth 100
        $install=& $lifecycle {param($Value) ConvertTo-AiwCorrectionEffectView $Value} $install
        foreach($id in $install.dependsOn){if(@($active|Where-Object correctionId -CEQ $id).Count-ne1){throw 'ADOPTION_CORRECTION_DEPENDENCY_INACTIVE'}}
        foreach($effect in $install.changes){
            $target=@($Projection.objects|Where-Object path -CEQ $effect.path)
            if($target.Count-eq0){continue}
            if($target.Count-ne1){throw 'ADOPTION_CORRECTION_EFFECT_DUPLICATE'}
            $bytes=[Convert]::FromBase64String($target[0].newBase64)
            if($effect.kind-ceq'FILE'){
                if($target[0].newExists-ne$effect.afterExists-or(Get-AiwByteIdentity $bytes)-cne(Get-AiwByteIdentity ([Convert]::FromBase64String($effect.afterBase64)))){throw 'ADOPTION_CORRECTION_FINAL_OWNERSHIP_DRIFT'}
            }elseif($effect.kind-ceq'TEXT'){
                if(-not$target[0].newExists){throw 'ADOPTION_CORRECTION_FINAL_OWNERSHIP_DRIFT'}
                $text=$script:Utf8NoBom.GetString($bytes);$needle=$effect.prefix+$effect.after+$effect.suffix
                $index=$text.IndexOf($needle,[StringComparison]::Ordinal)
                if($needle.Length-eq0-or$index-lt0-or$text.IndexOf($needle,$index+1,[StringComparison]::Ordinal)-ge0){throw 'ADOPTION_CORRECTION_FINAL_OWNERSHIP_DRIFT'}
            }else{throw 'ADOPTION_CORRECTION_EFFECT_KIND'}
        }
    }
}

function Get-AiwAdoptionSelectionArguments($Command,$Receipt,$SelectionContext=$null,$ExpectedComposition=$null){
    $context=Get-AiwAdoptionProcessContext $Receipt
    $ceilings=if($Receipt.schemaVersion-in@(3,4)){@($Receipt.evidence.ceilings)}elseif($null-ne$Receipt.PSObject.Properties['evidenceCeilings']){@($Receipt.evidenceCeilings)}else{@()}
    $requiresSelected='SOURCE_VALIDATION_SELECTED_CLOSURE_V1'-cin$ceilings
    if($null-ne$ExpectedComposition-and$null-ne$ExpectedComposition.PSObject.Properties['evidenceCeilings']){$requiresSelected=$requiresSelected-or('SOURCE_VALIDATION_SELECTED_CLOSURE_V1'-cin@($ExpectedComposition.evidenceCeilings))}
    if(-not$Command.Parameters.ContainsKey('SelectionContext')){
        if($requiresSelected){throw 'ADOPTION_SCOPED_BINDING_RUNTIME_UNSUPPORTED'}
        return @{}
    }
    if($null-eq$SelectionContext){
        $SelectionContext=[pscustomobject]@{profile=$context.profile;role=$context.role;phase=$context.phase;actor=$context.actor;actionKind=$Receipt.intentEnvelope.requestedActionKind;resultKind=$Receipt.intentEnvelope.requestedResultKind;exactPaths=@($context.exactScope);capabilities=@($context.observedCapabilities);intentEnvelope=$Receipt.intentEnvelope}
    }
    return @{SelectionContext=$SelectionContext}
}
