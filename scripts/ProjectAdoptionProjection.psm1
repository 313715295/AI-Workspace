Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop

function Get-AiwTargetBytes {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $hasBytes = $Target.PSObject.Properties.Name -ccontains 'bytes'
    $hasText = $Target.PSObject.Properties.Name -ccontains 'text'
    if ($hasBytes -eq $hasText) {
        throw ('TARGET_CONTENT_SHAPE|' + $RelativePath)
    }
    if ($hasBytes) {
        if ($null -eq $Target.bytes) {
            throw ('TARGET_CONTENT_NULL|' + $RelativePath)
        }
        return [byte[]]$Target.bytes
    }
    return [Text.UTF8Encoding]::new($false).GetBytes([string]$Target.text)
}

function New-AiwProjectProjection {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][object[]]$TargetObject
    )

    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $objects = [Collections.Generic.List[object]]::new()

    foreach ($target in @($TargetObject)) {
        if ($null -eq $target.PSObject.Properties['path']) {
            throw 'TARGET_PATH_MISSING'
        }
        $relative = [string]$target.path
        Assert-AiwRelativePath $relative
        if (-not $seen.Add($relative)) {
            throw ('MANAGED_PATH_DUPLICATE|' + $relative)
        }

        $path = Get-AiwContainedPath $root $relative
        $kind = if ($target.PSObject.Properties.Name -ccontains 'kind') {
            [string]$target.kind
        }
        else {
            'FILE'
        }
        if ($kind -cnotin @('FILE', 'DIRECTORY')) {
            throw ('TARGET_KIND|' + $relative)
        }
        $existing = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing -and
            (($kind -ceq 'FILE' -and $existing.PSIsContainer) -or
             ($kind -ceq 'DIRECTORY' -and -not $existing.PSIsContainer))) {
            throw ('MANAGED_PATH_KIND_CONFLICT|' + $relative)
        }
        if ($null -ne $existing -and
            ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('MANAGED_PATH_REPARSE|' + $relative)
        }
        $oldExists = $null -ne $existing
        [byte[]]$oldBytes = [byte[]]::new(0)
        if ($oldExists -and $kind -ceq 'FILE') {
            $oldBytes = [IO.File]::ReadAllBytes($path)
        }

        $newExists = $true
        if ($target.PSObject.Properties.Name -ccontains 'exists') {
            if ($target.exists -isnot [bool]) {
                throw ('TARGET_EXISTS_NOT_BOOLEAN|' + $relative)
            }
            $newExists = [bool]$target.exists
        }

        if ($kind -ceq 'DIRECTORY' -and -not $newExists) {
            throw ('TARGET_DIRECTORY_DELETE_UNSUPPORTED|' + $relative)
        }
        [byte[]]$newBytes = [byte[]]::new(0)
        if ($newExists -and $kind -ceq 'FILE') {
            $newBytes = Get-AiwTargetBytes $target $relative
        }
        elseif ($kind -ceq 'DIRECTORY' -and
                (($target.PSObject.Properties.Name -ccontains 'bytes') -or
                 ($target.PSObject.Properties.Name -ccontains 'text'))) {
            throw ('TARGET_DIRECTORY_HAS_CONTENT|' + $relative)
        }
        elseif (($target.PSObject.Properties.Name -ccontains 'bytes') -or
                ($target.PSObject.Properties.Name -ccontains 'text')) {
            throw ('TARGET_DELETE_HAS_CONTENT|' + $relative)
        }

        $oldIdentity = if (-not $oldExists) { 'MISSING' } elseif ($kind -ceq 'DIRECTORY') { 'DIRECTORY' } else { Get-AiwByteIdentity $oldBytes }
        $newIdentity = if (-not $newExists) { 'MISSING' } elseif ($kind -ceq 'DIRECTORY') { 'DIRECTORY' } else { Get-AiwByteIdentity $newBytes }
        $objects.Add([pscustomobject]@{
            path = $relative
            kind = $kind
            oldExists = $oldExists
            newExists = $newExists
            oldIdentity = $oldIdentity
            newIdentity = $newIdentity
            changed = $oldIdentity -cne $newIdentity
            oldBase64 = [Convert]::ToBase64String($oldBytes)
            newBase64 = [Convert]::ToBase64String($newBytes)
        })
    }

    $changed = @($objects | Where-Object changed)
    [pscustomobject]@{
        schemaVersion = 1
        repositoryRoot = $root
        objects = @($objects)
        changeCount = $changed.Count
        noOp = $changed.Count -eq 0
    }
}

function Get-AiwProjectProjectionDiff {
    param([Parameter(Mandatory)]$Projection)

    @($Projection.objects | ForEach-Object {
        $change = if (-not $_.changed) {
            'UNCHANGED'
        }
        elseif (-not $_.newExists) {
            'DELETE'
        }
        elseif ($_.oldExists) {
            'REPLACE'
        }
        else {
            'CREATE'
        }
        [pscustomobject]@{
            path = $_.path
            kind = $_.kind
            change = $change
            oldIdentity = $_.oldIdentity
            newIdentity = $_.newIdentity
        }
    })
}

Export-ModuleMember -Function New-AiwProjectProjection, Get-AiwProjectProjectionDiff
