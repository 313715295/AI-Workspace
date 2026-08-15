[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$ProjectId,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')][string]$ToVersion,
    [string]$RepositoryPath,
    [string]$ControllerId,
    [string]$ProtectedPathsMigrationPath,
    [string]$ExpectedProtectedPathsMigrationIdentity,
    [string]$LegacyControllerAuthorizationInventoryPath,
    [string]$ExpectedLegacyControllerAuthorizationInventoryIdentity,
    [switch]$Apply,
    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$utf8Strict = New-Object Text.UTF8Encoding($false, $true)

function Join-ChildPath([string]$Root, [string]$RelativePath) {
    $result = $Root
    foreach ($segment in ($RelativePath -split '/')) { $result = Join-Path $result $segment }
    return $result
}

function Read-StrictBytes([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is forbidden: $Path" }
    try { $text = $utf8Strict.GetString($bytes) } catch { throw "Strict UTF-8 required: $Path" }
    if ($text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or $text.Contains("`r") -or -not $text.EndsWith("`n")) { throw "Strict UTF-8/LF text required: $Path" }
    return [pscustomobject]@{ Bytes=$bytes; Text=$text }
}

function ConvertTo-Utf8Bytes([string]$Text) {
    $normalized = $Text.Replace("`r`n","`n").Replace("`r","`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    return ,([byte[]]$utf8NoBom.GetBytes($normalized))
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-BytesIdentity([byte[]]$Bytes) { return $Bytes.Length.ToString() + '|' + (Get-BytesSha256 $Bytes) }
function Get-FileIdentity([string]$Path) { return Get-BytesIdentity ([IO.File]::ReadAllBytes($Path)) }

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cne $Path.Trim()) { throw 'Relative path is empty or padded.' }
    $value = $Path.Replace('\','/')
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/')) { throw 'Relative path is rooted.' }
    if (-not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw 'Relative path is not NFC.' }
    foreach ($part in $value.Split('/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw 'Relative path contains an invalid component.' }
        if ($part.Split('.')[0] -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw 'Relative path contains a reserved name.' }
    }
    return $value
}

function Assert-NoReparsePoint([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point is forbidden: $Path" }
}

function Assert-PathWithinRootNoReparse([string]$Root,[string]$Path) {
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $pathFull=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath).TrimEnd('\')
    if (-not ($pathFull.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase) -or $pathFull.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase))) { throw "Path escapes the repository root: $Path" }
    Assert-NoReparsePoint $rootFull
    $current=$rootFull
    if (-not $pathFull.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase)) {
        foreach($part in $pathFull.Substring($rootFull.Length+1).Split('\')){$current=Join-Path $current $part;Assert-NoReparsePoint $current}
    }
}

function Assert-ExactJsonObjectFields($Object,[string]$Raw,[string[]]$Expected,[string]$Label) {
    if (-not ($Object -is [pscustomobject])) { throw "$Label must be a JSON object." }
    $names=@($Object.PSObject.Properties.Name)
    if ($names.Count -ne $Expected.Count -or @($Expected|Where-Object{$_ -cnotin $names}).Count -ne 0) { throw "$Label field set mismatch." }
    foreach($name in $Expected){if([regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1){throw "$Label duplicate or missing field: $name"}}
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Assert-CurrentProjectConfig($Config,[string]$Raw,[string]$ExpectedProjectId,[string]$ExpectedVersion) {
    $fields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','protectedPaths','frameworkCapabilities')
    Assert-ExactJsonObjectFields $Config $Raw $fields 'Already-pinned project.json'
    if (-not (Test-JsonInteger $Config.schemaVersion) -or [int]$Config.schemaVersion -ne 3 -or
        -not ($Config.id -is [string]) -or [string]$Config.id -cne $ExpectedProjectId -or
        -not ($Config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$Config.displayName) -or
        -not ($Config.controlPlaneLayout -is [string]) -or [string]$Config.controlPlaneLayout -cne 'repo-local' -or
        -not ($Config.repositoryRoot -is [string]) -or [string]$Config.repositoryRoot -cne '..' -or
        -not ($Config.frameworkVersion -is [string]) -or [string]$Config.frameworkVersion -cne $ExpectedVersion -or
        -not ($Config.protectedPaths -is [System.Array]) -or -not ($Config.frameworkCapabilities -is [pscustomobject]) -or @($Config.frameworkCapabilities.PSObject.Properties).Count -ne 0) {
        throw 'Already-pinned project has invalid schema 3 configuration.'
    }
    $allowedDeny=@('visibility','read','hash','diff','index','write')
    $seenRules=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($rule in @($Config.protectedPaths)) {
        if (-not ($rule -is [pscustomobject]) -or @($rule.PSObject.Properties.Name).Count -ne 2 -or 'path' -cnotin @($rule.PSObject.Properties.Name) -or 'deny' -cnotin @($rule.PSObject.Properties.Name) -or
            -not ($rule.path -is [string]) -or [string]::IsNullOrWhiteSpace([string]$rule.path) -or -not ($rule.deny -is [System.Array]) -or @($rule.deny).Count -lt 1) { throw 'Already-pinned protected path rule is invalid.' }
        $canonicalPath=Normalize-RelativePath ([string]$rule.path)
        if ([string]$rule.path -cne $canonicalPath) { throw 'Already-pinned protected path must use its canonical repo-relative form.' }
        if(-not$seenRules.Add($canonicalPath)){throw 'Already-pinned protected path rules contain a duplicate path.'}
        $denySeen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($capability in @($rule.deny)){if(-not($capability -is [string])-or[string]$capability -cnotin $allowedDeny-or-not$denySeen.Add([string]$capability)){throw 'Already-pinned protected path deny list is invalid.'}}
    }
    if ([regex]::Matches($Raw,'"path"\s*:').Count -ne @($Config.protectedPaths).Count -or [regex]::Matches($Raw,'"deny"\s*:').Count -ne @($Config.protectedPaths).Count) { throw 'Already-pinned protected path rule contains duplicate or missing fields.' }
}

function Assert-CurrentController($Controller,[string]$Raw,[string]$ExpectedProjectId) {
    Assert-ExactJsonObjectFields $Controller $Raw @('schemaVersion','projectId','controllerId','controllerEpoch','state') 'Already-pinned controller.json'
    if (-not (Test-JsonInteger $Controller.schemaVersion) -or [int]$Controller.schemaVersion -ne 1 -or
        -not ($Controller.projectId -is [string]) -or [string]$Controller.projectId -cne $ExpectedProjectId -or
        -not ($Controller.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$Controller.controllerId) -or
        -not (Test-JsonInteger $Controller.controllerEpoch) -or [int64]$Controller.controllerEpoch -lt 1 -or
        -not ($Controller.state -is [string]) -or [string]$Controller.state -cne 'CURRENT') { throw 'Already-pinned controller.json is invalid.' }
}

function Resolve-RepositoryRoot([string]$Path) {
    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath).TrimEnd('\')
    $output = @(& git -C $resolved rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw "RepositoryPath is not a Git worktree: $resolved" }
    $top = [IO.Path]::GetFullPath([string]$output[-1]).TrimEnd('\')
    if (-not $top.Equals($resolved, [StringComparison]::OrdinalIgnoreCase)) { throw "RepositoryPath must be the Git top level: $resolved" }
    return $top
}

function Get-ManagedBlock([string]$Text, [string]$Source) {
    $begin = '<!-- FRAMEWORK-MANAGED:BEGIN -->'; $end = '<!-- FRAMEWORK-MANAGED:END -->';$customBegin='<!-- PROJECT-CUSTOM:BEGIN -->';$customEnd='<!-- PROJECT-CUSTOM:END -->'
    foreach($marker in @($begin,$end,$customBegin,$customEnd)){if([regex]::Matches($Text,[regex]::Escape($marker)).Count -ne 1){throw "Bootstrap markers are invalid: $Source"}}
    $start=$Text.IndexOf($begin,[StringComparison]::Ordinal);$managedEnd=$Text.IndexOf($end,[StringComparison]::Ordinal);$customStart=$Text.IndexOf($customBegin,[StringComparison]::Ordinal);$customFinish=$Text.IndexOf($customEnd,[StringComparison]::Ordinal)
    if(-not($start -lt $managedEnd -and $managedEnd -lt $customStart -and $customStart -lt $customFinish)){throw "Bootstrap markers must be paired and ordered managed-then-custom: $Source"}
    $finish = $managedEnd + $end.Length
    return [pscustomobject]@{ Start=$start; Length=$finish-$start; Text=$Text.Substring($start,$finish-$start) }
}

function Render-Bootstrap([string]$Template, $Config, [string]$Version) {
    $result = $Template.Replace('{{PROJECT_ID}}',[string]$Config.id).Replace('{{DISPLAY_NAME}}',[string]$Config.displayName).Replace('{{FRAMEWORK_VERSION}}',$Version)
    if ($result -match '\{\{[A-Z0-9_]+\}\}') { throw 'Bootstrap template contains an unresolved token.' }
    return $result
}

function Replace-ManagedBlock([string]$Current, $CurrentBlock, [string]$TargetBlock) {
    return $Current.Substring(0,$CurrentBlock.Start) + $TargetBlock + $Current.Substring($CurrentBlock.Start+$CurrentBlock.Length)
}

function Read-ProtectedMigration([string]$Path, [string]$ExpectedIdentity, [string]$ExpectedProjectId) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($ExpectedIdentity)) { throw 'ProtectedPathsMigration path and identity are required.' }
    if ((Get-FileIdentity $Path) -cne $ExpectedIdentity) { throw 'ProtectedPathsMigration identity drift.' }
    $raw = (Read-StrictBytes $Path).Text
    try { $migration = $raw | ConvertFrom-Json } catch { throw 'ProtectedPathsMigration is invalid JSON.' }
    $names = @($migration.PSObject.Properties.Name)
    if ($names.Count -ne 3 -or @('schemaVersion','projectId','protectedPaths' | Where-Object { $_ -cnotin $names }).Count -ne 0 -or
        -not ($migration.schemaVersion -is [int]) -or [int]$migration.schemaVersion -ne 1 -or [string]$migration.projectId -cne $ExpectedProjectId -or
        -not ($migration.protectedPaths -is [System.Array])) { throw 'ProtectedPathsMigration schema mismatch.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $result = @()
    foreach ($entry in @($migration.protectedPaths)) {
        $entryNames = @($entry.PSObject.Properties.Name)
        if (-not ($entry -is [pscustomobject]) -or $entryNames.Count -ne 2 -or 'path' -cnotin $entryNames -or 'deny' -cnotin $entryNames -or -not ($entry.deny -is [System.Array]) -or @($entry.deny).Count -eq 0) { throw 'Protected path entry schema mismatch.' }
        $pathValue = Normalize-RelativePath ([string]$entry.path)
        if (-not $seen.Add($pathValue)) { throw 'Protected path collision.' }
        $denySeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($deny in @($entry.deny)) {
            if (-not ($deny -is [string]) -or [string]$deny -cnotin @('visibility','read','hash','diff','index','write') -or -not $denySeen.Add([string]$deny)) { throw 'Protected deny list is invalid.' }
        }
        $result += [ordered]@{ path=$pathValue; deny=@($denySeen | Sort-Object) }
    }
    return [pscustomobject]@{ Identity=$ExpectedIdentity; ProtectedPaths=@($result) }
}

function Read-LegacyInventory([string]$Path, [string]$ExpectedIdentity, [string]$ExpectedProjectId, [string]$ExpectedControllerId, [string]$RepositoryRoot) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($ExpectedIdentity)) { throw 'Legacy controller authorization inventory path and identity are required.' }
    if ((Get-FileIdentity $Path) -cne $ExpectedIdentity) { throw 'Legacy controller authorization inventory identity drift.' }
    try { $inventory = (Read-StrictBytes $Path).Text | ConvertFrom-Json } catch { throw 'Legacy controller authorization inventory is invalid JSON.' }
    $names = @($inventory.PSObject.Properties.Name)
    if ($names.Count -ne 4 -or @('schemaVersion','projectId','currentControllerId','packages' | Where-Object { $_ -cnotin $names }).Count -ne 0 -or
        -not ($inventory.schemaVersion -is [int]) -or [int]$inventory.schemaVersion -ne 1 -or [string]$inventory.projectId -cne $ExpectedProjectId -or
        [string]$inventory.currentControllerId -cne $ExpectedControllerId -or -not ($inventory.packages -is [System.Array])) { throw 'Legacy controller authorization inventory schema mismatch.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $packages = @()
    foreach ($package in @($inventory.packages)) {
        $packageNames = @($package.PSObject.Properties.Name)
        if (-not ($package -is [pscustomobject]) -or $packageNames.Count -ne 2 -or 'locator' -cnotin $packageNames -or 'identity' -cnotin $packageNames -or [string]$package.identity -cnotmatch '^\d+\|[A-F0-9]{64}$') { throw 'Legacy package entry schema mismatch.' }
        $locator = Normalize-RelativePath ([string]$package.locator)
        if (-not $seen.Add($locator)) { throw 'Legacy package locator collision.' }
        $full = Join-ChildPath $RepositoryRoot $locator
        Assert-PathWithinRootNoReparse $RepositoryRoot $full
        if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or (Get-FileIdentity $full) -cne [string]$package.identity) { throw "Legacy package identity drift: $locator" }
        $packages += [ordered]@{ locator=$locator; identity=[string]$package.identity }
    }
    return [pscustomobject]@{ Identity=$ExpectedIdentity; Packages=@($packages) }
}

function Write-AtomicBytes([string]$Destination, [byte[]]$Bytes, [string]$TransactionId, [string]$BackupRoot) {
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Destination parent missing: $parent" }
    $temp = Join-Path $parent ".$TransactionId.tmp"
    if (Test-Path -LiteralPath $temp) { throw "Unexpected transaction temp exists: $temp" }
    [IO.File]::WriteAllBytes($temp,$Bytes)
    try {
        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            $backup = Join-Path $BackupRoot ((Split-Path -Leaf $Destination) + ".$TransactionId.bak")
            if (Test-Path -LiteralPath $backup) { throw "Unexpected replace backup exists: $backup" }
            [IO.File]::Replace($temp,$Destination,$backup)
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
        }
        else { [IO.File]::Move($temp,$Destination) }
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Read-Transaction([string]$TransactionRoot, [string]$ExpectedProjectId) {
    if (-not (Test-Path -LiteralPath $TransactionRoot -PathType Container)) { throw 'Upgrade transaction directory is missing.' }
    $transactionDirectory = Get-Item -LiteralPath $TransactionRoot -Force
    if (($transactionDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Upgrade transaction directory cannot be a reparse point.' }
    $manifestPath = Join-Path $TransactionRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Upgrade transaction manifest is missing.' }
    $manifestFile = Get-Item -LiteralPath $manifestPath -Force
    if (($manifestFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Upgrade transaction manifest cannot be a reparse point.' }
    try { $manifest = (Read-StrictBytes $manifestPath).Text | ConvertFrom-Json } catch { throw 'Upgrade transaction manifest is invalid.' }
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.projectId -cne $ExpectedProjectId -or [string]$manifest.transactionId -cnotmatch '^[0-9a-f]{32}$' -or -not ($manifest.items -is [System.Array]) -or @($manifest.items).Count -ne 4) { throw 'Upgrade transaction manifest schema mismatch.' }
    $allowed = @('project.json','BOOTSTRAP.md','controller.json','controller-revocations.json')
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $expectedRootEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($name in @('manifest.json','old','new')) { $null = $expectedRootEntries.Add($name) }
    $expectedOldFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $expectedNewFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    for ($i=0;$i -lt @($manifest.items).Count;$i++) {
        $item = $manifest.items[$i]
        if ([string]$item.relativePath -cnotin $allowed -or -not $seen.Add([string]$item.relativePath) -or -not ($item.oldExists -is [bool]) -or
            [string]$item.newIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or ([bool]$item.oldExists -and [string]$item.oldIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$')) { throw 'Upgrade transaction item mismatch.' }
        $null = $expectedNewFiles.Add("$i.bin")
        $newMaterial = Join-Path $TransactionRoot "new/$i.bin"
        if (-not (Test-Path -LiteralPath $newMaterial -PathType Leaf) -or (Get-FileIdentity $newMaterial) -cne [string]$item.newIdentity) { throw 'Upgrade new material drift.' }
        if ([bool]$item.oldExists) {
            $null = $expectedOldFiles.Add("$i.bin")
            $oldMaterial = Join-Path $TransactionRoot "old/$i.bin"
            if (-not (Test-Path -LiteralPath $oldMaterial -PathType Leaf) -or (Get-FileIdentity $oldMaterial) -cne [string]$item.oldIdentity) { throw 'Upgrade old material drift.' }
            $backupName = ([string]$item.relativePath) + "." + ([string]$manifest.transactionId) + '.bak'
            $backupPath = Join-Path $TransactionRoot $backupName
            if (Test-Path -LiteralPath $backupPath) {
                if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-FileIdentity $backupPath) -cne [string]$item.oldIdentity) { throw 'Upgrade transaction backup drift.' }
                $null = $expectedRootEntries.Add($backupName)
            }
        }
    }
    foreach ($directoryName in @('old','new')) {
        $directoryPath = Join-Path $TransactionRoot $directoryName
        if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) { throw "Upgrade transaction $directoryName directory is missing." }
        $directory = Get-Item -LiteralPath $directoryPath -Force
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Upgrade transaction material directory cannot be a reparse point.' }
        $expectedFiles = $(if ($directoryName -ceq 'old') { $expectedOldFiles } else { $expectedNewFiles })
        foreach ($entry in @(Get-ChildItem -LiteralPath $directoryPath -Force)) {
            if (-not $entry.PSIsContainer -and ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and $expectedFiles.Contains($entry.Name)) { continue }
            throw "Unexpected upgrade transaction material: $directoryName/$($entry.Name)"
        }
        if (@(Get-ChildItem -LiteralPath $directoryPath -Force).Count -ne $expectedFiles.Count) { throw "Upgrade transaction $directoryName inventory mismatch." }
    }
    foreach ($entry in @(Get-ChildItem -LiteralPath $TransactionRoot -Force)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $expectedRootEntries.Contains($entry.Name)) { throw "Unexpected upgrade transaction entry: $($entry.Name)" }
        if ($entry.Name -cin @('old','new')) {
            if (-not $entry.PSIsContainer) { throw "Upgrade transaction directory type mismatch: $($entry.Name)" }
        }
        elseif ($entry.PSIsContainer) { throw "Upgrade transaction file type mismatch: $($entry.Name)" }
    }
    if (@(Get-ChildItem -LiteralPath $TransactionRoot -Force).Count -ne $expectedRootEntries.Count) { throw 'Upgrade transaction root inventory mismatch.' }
    return $manifest
}

function Get-ItemState([string]$Destination, $Item) {
    if (-not (Test-Path -LiteralPath $Destination)) { return $(if ([bool]$Item.oldExists) { 'UNKNOWN' } else { 'OLD' }) }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { return 'UNKNOWN' }
    $identity = Get-FileIdentity $Destination
    if ($identity -ceq [string]$Item.newIdentity) { return 'NEW' }
    if ([bool]$Item.oldExists -and $identity -ceq [string]$Item.oldIdentity) { return 'OLD' }
    return 'UNKNOWN'
}

function Remove-Transaction([string]$TransactionRoot, [string]$ProjectRoot, [string]$ExpectedProjectId) {
    $resolved = [IO.Path]::GetFullPath($TransactionRoot).TrimEnd('\'); $expected = [IO.Path]::GetFullPath((Join-Path $ProjectRoot '.framework-upgrade-transaction')).TrimEnd('\')
    if (-not $resolved.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing unexpected transaction cleanup.' }
    if (Test-Path -LiteralPath $resolved) {
        $null = Read-Transaction $resolved $ExpectedProjectId
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

function Recover-Transaction([string]$TransactionRoot, [string]$ProjectRoot, [string]$ExpectedProjectId) {
    $manifest = Read-Transaction $TransactionRoot $ExpectedProjectId
    $states = @()
    for ($i=0;$i -lt @($manifest.items).Count;$i++) { $states += Get-ItemState (Join-Path $ProjectRoot ([string]$manifest.items[$i].relativePath)) $manifest.items[$i] }
    if ('UNKNOWN' -cin $states) { throw 'Upgrade recovery found unknown live bytes; materials were retained.' }
    if (@($states | Where-Object { $_ -ceq 'NEW' }).Count -eq $states.Count) { Remove-Transaction $TransactionRoot $ProjectRoot $ExpectedProjectId; return 'RECOVERED_COMMITTED' }
    for ($i=0;$i -lt @($manifest.items).Count;$i++) {
        $item=$manifest.items[$i]; $destination=Join-Path $ProjectRoot ([string]$item.relativePath); $state=Get-ItemState $destination $item
        if ($state -ceq 'UNKNOWN') { throw 'Upgrade rollback found unknown live bytes.' }
        if ([bool]$item.oldExists) {
            if ($state -cne 'OLD') { Write-AtomicBytes $destination ([IO.File]::ReadAllBytes((Join-Path $TransactionRoot "old/$i.bin"))) ([string]$manifest.transactionId) $TransactionRoot }
            if ((Get-FileIdentity $destination) -cne [string]$item.oldIdentity) { throw 'Upgrade rollback identity mismatch.' }
        }
        elseif ($state -ceq 'NEW') { Remove-Item -LiteralPath $destination -Force }
    }
    Remove-Transaction $TransactionRoot $ProjectRoot $ExpectedProjectId
    return 'RECOVERED_ROLLED_BACK'
}

if (-not $WorkspaceRoot) { $WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$workspace = [IO.Path]::GetFullPath($WorkspaceRoot)
$frameworkRoot = Join-ChildPath $workspace 'framework'
if (-not (Test-Path -LiteralPath $frameworkRoot -PathType Container)) { throw "Workspace root must contain framework/: $workspace" }
if ([string]::IsNullOrWhiteSpace($RepositoryPath)) { throw 'RepositoryPath is required for repo-local 1.6.0 upgrade; central-to-repo-local is a separate project task.' }
$repo = Resolve-RepositoryRoot $RepositoryPath
Assert-NoReparsePoint $repo
$projectRoot = Join-Path $repo '.ai-workspace'
if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) { throw "Repo-local control plane is missing: $projectRoot" }
Assert-PathWithinRootNoReparse $repo $projectRoot
$projectFile = Join-Path $projectRoot 'project.json'; $bootstrapFile = Join-Path $projectRoot 'BOOTSTRAP.md'; $controllerFile = Join-Path $projectRoot 'controller.json'; $revocationFile = Join-Path $projectRoot 'controller-revocations.json'
Assert-PathWithinRootNoReparse $repo $projectFile
Assert-PathWithinRootNoReparse $repo $bootstrapFile
$transactionRoot = Join-Path $projectRoot '.framework-upgrade-transaction'
if ($Apply -and (Test-Path -LiteralPath $transactionRoot -PathType Container)) {
    $result = Recover-Transaction $transactionRoot $projectRoot $ProjectId
    Write-Output $result
    return
}
if (-not $Apply -and (Test-Path -LiteralPath $transactionRoot)) { throw 'Upgrade recovery material exists; Apply must recover it before a new preview.' }

$frozenProject = Read-StrictBytes $projectFile; $frozenBootstrap = Read-StrictBytes $bootstrapFile
try { $config = $frozenProject.Text | ConvertFrom-Json } catch { throw 'Project configuration is invalid JSON.' }
if ([string]$config.id -cne $ProjectId -or [string]$config.controlPlaneLayout -cne 'repo-local' -or [string]$config.repositoryRoot -cne '..') { throw 'Project identity/layout mismatch.' }
$fromVersion = [string]$config.frameworkVersion
if ($fromVersion -cnotin @('1.4.1','1.5.0','1.5.1','1.5.2','1.6.0')) { throw "Unsupported direct source version: $fromVersion" }
$targetFramework = Join-ChildPath $frameworkRoot "versions/$ToVersion"
if (-not (Test-Path -LiteralPath $targetFramework -PathType Container)) { throw "Target Framework is unavailable: $ToVersion" }
$targetVersion = (Read-StrictBytes (Join-ChildPath $targetFramework 'VERSION.json')).Text | ConvertFrom-Json
if ([string]$targetVersion.version -cne $ToVersion -or [string]$targetVersion.lifecycle -cne 'STABLE' -or -not [bool]$targetVersion.consumable) { throw 'Target Framework is not stable and consumable.' }

if ($fromVersion -ceq $ToVersion) {
    Assert-CurrentProjectConfig $config $frozenProject.Text $ProjectId $ToVersion
    if (-not (Test-Path -LiteralPath $controllerFile)) { throw 'Already-pinned project is missing controller.json.' }
    if (-not (Test-Path -LiteralPath $controllerFile -PathType Leaf)) { throw 'Already-pinned controller.json must be a regular file.' }
    Assert-PathWithinRootNoReparse $repo $controllerFile
    $controllerRaw=(Read-StrictBytes $controllerFile).Text
    try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'Already-pinned controller.json is invalid JSON.'}
    Assert-CurrentController $controller $controllerRaw $ProjectId
    if (Test-Path -LiteralPath $revocationFile) {
        if (-not (Test-Path -LiteralPath $revocationFile -PathType Leaf)) { throw 'Already-pinned revocation ledger must be a regular file.' }
        Assert-PathWithinRootNoReparse $repo $revocationFile
        $ledgerRaw=(Read-StrictBytes $revocationFile).Text
        try{$ledger=$ledgerRaw|ConvertFrom-Json}catch{throw 'Already-pinned revocation ledger is invalid JSON.'}
        Assert-ExactJsonObjectFields $ledger $ledgerRaw @('schemaVersion','projectId','controllerId','controllerEpoch','sourceInventoryIdentity','disposition','packages') 'Already-pinned revocation ledger'
        if (-not (Test-JsonInteger $ledger.schemaVersion) -or [int]$ledger.schemaVersion -ne 1 -or -not ($ledger.projectId -is [string]) -or [string]$ledger.projectId -cne $ProjectId -or
            -not ($ledger.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$ledger.controllerId) -or -not (Test-JsonInteger $ledger.controllerEpoch) -or [int64]$ledger.controllerEpoch -ne 1 -or [int64]$controller.controllerEpoch -lt [int64]$ledger.controllerEpoch -or
            -not ($ledger.sourceInventoryIdentity -is [string]) -or [string]$ledger.sourceInventoryIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or -not ($ledger.disposition -is [string]) -or [string]$ledger.disposition -cne 'LEGACY_PROJECT_CONTROLLER_PACKAGES_STALE' -or -not ($ledger.packages -is [System.Array])) { throw 'Already-pinned revocation ledger is invalid.' }
        $ledgerSeen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach($package in @($ledger.packages)){
            if(-not ($package -is [pscustomobject]) -or @($package.PSObject.Properties.Name).Count -ne 2 -or 'locator' -cnotin @($package.PSObject.Properties.Name) -or 'identity' -cnotin @($package.PSObject.Properties.Name) -or -not ($package.locator -is [string]) -or -not ($package.identity -is [string]) -or [string]$package.identity -cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'Already-pinned revocation ledger package schema mismatch.'}
            $locator=Normalize-RelativePath ([string]$package.locator)
            if(-not $ledgerSeen.Add($locator)){throw 'Already-pinned revocation ledger duplicate locator.'}
            $full=Join-ChildPath $repo $locator
            if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'Already-pinned revocation ledger package identity drift.'}
            Assert-PathWithinRootNoReparse $repo $full
            if((Get-FileIdentity $full) -cne [string]$package.identity){throw 'Already-pinned revocation ledger package identity drift.'}
        }
        if([regex]::Matches($ledgerRaw,'"locator"\s*:').Count -ne @($ledger.packages).Count -or [regex]::Matches($ledgerRaw,'"identity"\s*:').Count -ne @($ledger.packages).Count){throw 'Already-pinned revocation ledger package contains duplicate or missing fields.'}
    }
    Write-Output 'ALREADY_UPGRADED'
    return
}
if ([int]$config.schemaVersion -ne 2) { throw 'Direct 1.6.0 migration expects a schema 2 source project.' }
Assert-ExactJsonObjectFields $config $frozenProject.Text @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion') 'Source project.json'
if (-not ($config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.id) -or -not ($config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.displayName) -or
    -not ($config.controlPlaneLayout -is [string]) -or -not ($config.repositoryRoot -is [string]) -or -not ($config.frameworkVersion -is [string])) { throw 'Source project.json field types are invalid.' }
if ([string]::IsNullOrWhiteSpace($ControllerId)) { throw 'ControllerId is required for schema 2 to 3 migration.' }
if ((Test-Path -LiteralPath $controllerFile) -or (Test-Path -LiteralPath $revocationFile)) { throw 'Unexpected controller or revocation object exists before schema 3 migration.' }

Assert-PathWithinRootNoReparse $repo $ProtectedPathsMigrationPath
Assert-PathWithinRootNoReparse $repo $LegacyControllerAuthorizationInventoryPath
$protectedMigration = Read-ProtectedMigration $ProtectedPathsMigrationPath $ExpectedProtectedPathsMigrationIdentity $ProjectId
$legacyInventory = Read-LegacyInventory $LegacyControllerAuthorizationInventoryPath $ExpectedLegacyControllerAuthorizationInventoryIdentity $ProjectId $ControllerId $repo
$sourceFramework = Join-ChildPath $frameworkRoot "versions/$fromVersion"
$sourceTemplateFile = Join-ChildPath $sourceFramework 'project-starter/BOOTSTRAP.md'; $targetTemplateFile = Join-ChildPath $targetFramework 'project-starter/BOOTSTRAP.md'; $targetProjectTemplate = Join-ChildPath $targetFramework 'project-starter/project.json'; $targetControllerTemplate = Join-ChildPath $targetFramework 'project-starter/controller.json'
foreach($required in @($sourceTemplateFile,$targetTemplateFile,$targetProjectTemplate,$targetControllerTemplate)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "Migration template missing: $required"}}
if (-not (Read-StrictBytes $targetProjectTemplate).Text.Contains('"schemaVersion": 3')) { throw 'Target project template is not schema 3.' }
$currentBlock=Get-ManagedBlock $frozenBootstrap.Text $bootstrapFile; $sourceRendered=Render-Bootstrap (Read-StrictBytes $sourceTemplateFile).Text $config $fromVersion; $sourceBlock=Get-ManagedBlock $sourceRendered $sourceTemplateFile
if($currentBlock.Text -cne $sourceBlock.Text){throw 'Current managed Bootstrap differs from the pinned source template.'}
$targetRendered=Render-Bootstrap (Read-StrictBytes $targetTemplateFile).Text $config $ToVersion; $targetBlock=Get-ManagedBlock $targetRendered $targetTemplateFile; $targetBootstrap=Replace-ManagedBlock $frozenBootstrap.Text $currentBlock $targetBlock.Text

$targetConfig=[ordered]@{schemaVersion=3;id=[string]$config.id;displayName=[string]$config.displayName;controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion=$ToVersion;protectedPaths=@($protectedMigration.ProtectedPaths);frameworkCapabilities=[ordered]@{}}
$targetController=[ordered]@{schemaVersion=1;projectId=$ProjectId;controllerId=$ControllerId;controllerEpoch=1;state='CURRENT'}
$targetRevocation=[ordered]@{schemaVersion=1;projectId=$ProjectId;controllerId=$ControllerId;controllerEpoch=1;sourceInventoryIdentity=$legacyInventory.Identity;disposition='LEGACY_PROJECT_CONTROLLER_PACKAGES_STALE';packages=@($legacyInventory.Packages)}
$newBytes = New-Object 'object[]' 4
$newBytes[0] = [byte[]](ConvertTo-Utf8Bytes ($targetConfig|ConvertTo-Json -Depth 30))
$newBytes[1] = [byte[]](ConvertTo-Utf8Bytes $targetBootstrap)
$newBytes[2] = [byte[]](ConvertTo-Utf8Bytes ($targetController|ConvertTo-Json -Depth 10))
$newBytes[3] = [byte[]](ConvertTo-Utf8Bytes ($targetRevocation|ConvertTo-Json -Depth 20))
$relative=@('project.json','BOOTSTRAP.md','controller.json','controller-revocations.json')
$oldBytes = New-Object 'object[]' 4
$oldBytes[0]=[byte[]]$frozenProject.Bytes; $oldBytes[1]=[byte[]]$frozenBootstrap.Bytes; $oldBytes[2]=$null; $oldBytes[3]=$null

Write-Output ("PLAN|project=$ProjectId|from=$fromVersion|to=$ToVersion|files=4|protected=$(@($protectedMigration.ProtectedPaths).Count)|legacyPackages=$(@($legacyInventory.Packages).Count)")
if (-not $Apply -or -not $PSCmdlet.ShouldProcess($projectRoot,'Apply recoverable Framework 1.6.0 control migration')) { return }

if ((Get-FileIdentity $ProtectedPathsMigrationPath) -cne $protectedMigration.Identity -or (Get-FileIdentity $LegacyControllerAuthorizationInventoryPath) -cne $legacyInventory.Identity) { throw 'Migration input identity drift before transaction preparation.' }
foreach($package in @($legacyInventory.Packages)){ $full=Join-ChildPath $repo ([string]$package.locator); if(-not(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-FileIdentity $full) -cne [string]$package.identity){throw 'Legacy authorization carrier drift before transaction preparation.'} }
if ((Get-FileIdentity $projectFile) -cne (Get-BytesIdentity $frozenProject.Bytes) -or (Get-FileIdentity $bootstrapFile) -cne (Get-BytesIdentity $frozenBootstrap.Bytes) -or (Test-Path -LiteralPath $controllerFile) -or (Test-Path -LiteralPath $revocationFile)) { throw 'OBJECT_DRIFT before transaction preparation.' }
$transactionId=[Guid]::NewGuid().ToString('N'); New-Item -ItemType Directory -Path (Join-Path $transactionRoot 'old') -Force|Out-Null;New-Item -ItemType Directory -Path (Join-Path $transactionRoot 'new') -Force|Out-Null
$items=@()
for($i=0;$i -lt 4;$i++){
    if($null -ne $oldBytes[$i]){[IO.File]::WriteAllBytes((Join-Path $transactionRoot "old/$i.bin"),$oldBytes[$i])}
    [IO.File]::WriteAllBytes((Join-Path $transactionRoot "new/$i.bin"),$newBytes[$i])
    $items += [ordered]@{relativePath=$relative[$i];oldExists=($null -ne $oldBytes[$i]);oldIdentity=$(if($null -ne $oldBytes[$i]){Get-BytesIdentity $oldBytes[$i]}else{$null});newIdentity=Get-BytesIdentity $newBytes[$i]}
}
$manifest=[ordered]@{schemaVersion=1;projectId=$ProjectId;transactionId=$transactionId;fromVersion=$fromVersion;toVersion=$ToVersion;phase='PREPARED';items=@($items)}
[IO.File]::WriteAllBytes((Join-Path $transactionRoot 'manifest.json'),(ConvertTo-Utf8Bytes ($manifest|ConvertTo-Json -Depth 20)))
$null=Read-Transaction $transactionRoot $ProjectId
if ([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE') -eq '1' -and [Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_STOP_AFTER_PREPARE') -eq '1') { throw 'TEST_STOP_AFTER_PREPARE' }
$failure=$null
try{
    for($i=0;$i -lt 4;$i++){
        $destination=Join-Path $projectRoot $relative[$i];$state=Get-ItemState $destination $items[$i]
        if($state -cne 'OLD'){throw "OBJECT_DRIFT before replace: $($relative[$i])"}
        Write-AtomicBytes $destination $newBytes[$i] $transactionId $transactionRoot
        if((Get-FileIdentity $destination)-cne [string]$items[$i].newIdentity){throw "Replace verification failed: $($relative[$i])"}
        if($i -eq 0 -and [Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE') -eq '1' -and [Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_PROJECT_REPLACE') -eq '1'){throw 'TEST_INTERRUPT_AFTER_PROJECT_REPLACE'}
    }
    if ([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE') -eq '1' -and [Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_DRIFT_BEFORE_FINAL_SNAPSHOT') -eq '1') { [IO.File]::WriteAllText($projectFile,"test-final-snapshot-drift`n",$utf8NoBom) }
    $finalStates=@()
    for($i=0;$i -lt 4;$i++){$finalStates+=Get-ItemState (Join-Path $projectRoot $relative[$i]) $items[$i]}
    if(@($finalStates|Where-Object{$_ -cne 'NEW'}).Count -ne 0){throw 'OBJECT_DRIFT in final upgrade destination snapshot.'}
}catch{$failure=$_}
if($null -ne $failure){
    try{$recovery=Recover-Transaction $transactionRoot $projectRoot $ProjectId}catch{throw "Upgrade failed and recovery retained materials. commit=$($failure.Exception.Message); recovery=$($_.Exception.Message)"}
    throw "Upgrade failed and was recovered as $recovery. $($failure.Exception.Message)"
}
Remove-Transaction $transactionRoot $projectRoot $ProjectId
Write-Output 'UPGRADED|schema=3|controllerEpoch=1|revocation=RECORDED|git=UNTOUCHED'
