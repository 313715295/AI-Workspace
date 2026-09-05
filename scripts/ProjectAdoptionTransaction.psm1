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
        [Parameter(Mandatory)][byte[]]$Bytes
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
        }
        catch {
            $state.state = 'ROLLBACK_BLOCKED'
            $state.transactionComplete = $false
            $state.failure = $failure
            $state.rollbackFailure = [string]$_.Exception.Message
            Write-AiwTransactionState $transactionPath $state
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
