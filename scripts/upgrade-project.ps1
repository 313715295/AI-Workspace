[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$ToVersion,

    [string]$RepositoryPath,

    [switch]$Apply,

    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Join-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $result = $Root
    foreach ($segment in ($RelativePath -split '/')) {
        $result = Join-Path $result $segment
    }
    return $result
}

function Normalize-Text {
    param([Parameter(Mandatory = $true)][string]$Content)

    $normalized = $Content -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    return $normalized
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
        throw "File must be UTF-8 without BOM: $Source"
    }
    try {
        $content = $utf8Strict.GetString($Bytes)
    }
    catch {
        throw "File is not strict UTF-8: $Source"
    }
    if ($content.Contains([char]0) -or $content.Contains([char]0xFFFD)) {
        throw "File contains a forbidden text code point: $Source"
    }
    if ($content.Contains("`r")) {
        throw "File must use LF line endings: $Source"
    }
    if (-not $content.EndsWith("`n")) {
        throw "File must end with LF: $Source"
    }
    return $content
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, (Normalize-Text $Content), $utf8NoBom)
}

function Invoke-GitCapture {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git @Arguments 2>$null | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{ Output = $output; ExitCode = $exitCode }
}

function Render-Bootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)]$ProjectConfig,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion
    )

    $tokens = [ordered]@{
        '{{PROJECT_ID}}' = [string]$ProjectConfig.id
        '{{DISPLAY_NAME}}' = [string]$ProjectConfig.displayName
        '{{FRAMEWORK_VERSION}}' = $FrameworkVersion
    }
    if ($ProjectConfig.PSObject.Properties.Name -contains 'repositoryPath') {
        $tokens['{{REPOSITORY_PATH}}'] = [string]$ProjectConfig.repositoryPath
    }
    $rendered = $Template
    foreach ($token in $tokens.GetEnumerator()) {
        $rendered = $rendered.Replace($token.Key, $token.Value)
    }
    if ($rendered -match '\{\{[A-Z0-9_]+\}\}') {
        throw "Bootstrap template contains an unresolved token for Framework $FrameworkVersion."
    }
    return Normalize-Text $rendered
}

function Assert-TargetBootstrapContract {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion,
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$TargetFramework,
        [Parameter(Mandatory = $true)][ValidateSet('central-legacy', 'repo-local')][string]$Layout
    )

    if ($Layout -eq 'repo-local') {
        $versionedChecker = Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1'
        if (-not (Test-Path -LiteralPath $versionedChecker -PathType Leaf)) {
            throw "Target Framework checker does not exist: $versionedChecker"
        }
        if (-not $Content.Contains('<!-- FRAMEWORK-MANAGED:BEGIN -->') -or
            -not $Content.Contains('<!-- FRAMEWORK-MANAGED:END -->') -or
            -not $Content.Contains("framework/versions/$FrameworkVersion/scripts/check-task-card.ps1")) {
            throw "Target repo-local Bootstrap does not contain its managed block and versioned checker locator."
        }
        if ($Content -match '(?i)[A-Z]:\\[^\r\n]*framework\\versions') {
            throw 'Target repo-local Bootstrap contains a machine-absolute Framework locator.'
        }
        return
    }

    $legacyRootLocator = '`scripts/check-task-card.ps1`'
    if ($FrameworkVersion -eq '1.3.0') {
        throw 'Framework 1.3.0 runtime compatibility is retired; it is retained for history and as an upgrade source, but cannot be selected as an upgrade target.'
    }

    $versionedChecker = Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1'
    $versionedLocator = "../../framework/versions/$FrameworkVersion/scripts/check-task-card.ps1"
    if (-not (Test-Path -LiteralPath $versionedChecker -PathType Leaf)) {
        throw "Target Framework checker does not exist: $versionedChecker"
    }
    if (-not $Content.Contains($versionedLocator)) {
        throw "Target Bootstrap does not locate its versioned checker: $versionedLocator"
    }
    if ($Content.Contains($legacyRootLocator)) {
        throw 'Target Bootstrap still contains the legacy root checker locator.'
    }
}

function Get-GitRepositoryRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = Invoke-GitCapture @('-C', $Path, 'rev-parse', '--show-toplevel')
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) {
        throw "Repository path is not a Git work tree: $Path"
    }
    $root = [System.IO.Path]::GetFullPath([string]$result.Output[-1]).TrimEnd('\')
    $requested = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $root.Equals($requested, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "RepositoryPath must be the Git top level: $requested"
    }
    return $root
}

function Assert-NoReparseTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = Get-Item -LiteralPath $Path -Force
    if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed in a project control plane: $Path"
    }
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in a project control plane: $($item.FullName)"
        }
    }
}

function Get-ManagedBootstrapBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $begin = '<!-- FRAMEWORK-MANAGED:BEGIN -->'
    $end = '<!-- FRAMEWORK-MANAGED:END -->'
    $customBegin = '<!-- PROJECT-CUSTOM:BEGIN -->'
    $customEnd = '<!-- PROJECT-CUSTOM:END -->'
    foreach ($marker in @($begin, $end, $customBegin, $customEnd)) {
        if ([regex]::Matches($Content, [regex]::Escape($marker)).Count -ne 1) {
            throw "Repo-local Bootstrap markers must each appear exactly once: $Source"
        }
    }
    $beginIndex = $Content.IndexOf($begin, [System.StringComparison]::Ordinal)
    $endIndex = $Content.IndexOf($end, [System.StringComparison]::Ordinal)
    $customBeginIndex = $Content.IndexOf($customBegin, [System.StringComparison]::Ordinal)
    $customEndIndex = $Content.IndexOf($customEnd, [System.StringComparison]::Ordinal)
    if (-not ($beginIndex -lt $endIndex -and
              $endIndex -lt $customBeginIndex -and
              $customBeginIndex -lt $customEndIndex)) {
        throw "Repo-local Bootstrap markers must be paired and ordered managed-then-custom: $Source"
    }
    $blockEnd = $endIndex + $end.Length
    return [pscustomobject]@{
        Start = $beginIndex
        End = $blockEnd
        Text = $Content.Substring($beginIndex, $blockEnd - $beginIndex)
    }
}

function Replace-ManagedBootstrapBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Current,
        [Parameter(Mandatory = $true)][string]$TargetManaged,
        [Parameter(Mandatory = $true)]$CurrentBlock
    )

    return Normalize-Text ($Current.Substring(0, $CurrentBlock.Start) + $TargetManaged + $Current.Substring($CurrentBlock.End))
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Remove-SafeTransactionDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId
    )

    $resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $prefix = $resolvedProject + [System.IO.Path]::DirectorySeparatorChar
    $name = Split-Path -Leaf $resolvedPath
    if (-not $resolvedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        ($name -ne '.framework-upgrade-transaction' -and
         $name -notmatch '^\.fwu-prep-[0-9a-f]{32}$' -and
         $name -notmatch '^\.fwu-done-[0-9a-f]{32}$')) {
        throw "Refusing to remove an unexpected transaction path: $resolvedPath"
    }
    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        $null = Assert-KnownUpgradeTransactionDirectory $resolvedPath $resolvedProject $ExpectedProjectId
        $lastDeleteError = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                foreach ($file in [System.IO.Directory]::GetFiles($resolvedPath, '*', [System.IO.SearchOption]::AllDirectories)) {
                    [System.IO.File]::SetAttributes($file, [System.IO.FileAttributes]::Normal)
                }
                [System.IO.Directory]::Delete($resolvedPath, $true)
                return
            }
            catch {
                $lastDeleteError = $_
                if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
                    return
                }
                if ($attempt -lt 3) {
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        throw $lastDeleteError
    }
}

function Finalize-TransactionDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$TransactionId,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId
    )

    if ($TransactionId -notmatch '^[0-9a-f]{32}$') {
        throw "Invalid transaction id during cleanup: $TransactionId"
    }
    $completedRoot = Join-Path $ProjectRoot ".fwu-done-$TransactionId"
    if (Test-Path -LiteralPath $completedRoot) {
        throw "Completed transaction cleanup path already exists: $completedRoot"
    }
    [System.IO.Directory]::Move($TransactionRoot, $completedRoot)
    Remove-SafeTransactionDirectory $completedRoot $ProjectRoot $ExpectedProjectId
}

function Write-TransactionState {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Phase,
        [string]$LastError = ''
    )

    if ($Phase -notmatch '^[A-Z][A-Z0-9_]*$') {
        throw "Invalid transaction phase: $Phase"
    }
    $sequence = [int]$State.sequence + 1
    $snapshot = [ordered]@{
        schemaVersion = 1
        transactionId = [string]$State.transactionId
        sequence = $sequence
        phase = $Phase
        projectId = [string]$State.projectId
        fromVersion = [string]$State.fromVersion
        toVersion = [string]$State.toVersion
        oldProjectSha256 = [string]$State.oldProjectSha256
        oldBootstrapSha256 = [string]$State.oldBootstrapSha256
        newProjectSha256 = [string]$State.newProjectSha256
        newBootstrapSha256 = [string]$State.newBootstrapSha256
        lastError = $LastError
    }
    $statesRoot = Join-Path $TransactionRoot 'states'
    if (-not (Test-Path -LiteralPath $statesRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $statesRoot -Force | Out-Null
    }
    $baseName = 'state-{0:D4}-{1}.json' -f $sequence, $Phase
    $finalPath = Join-Path $statesRoot $baseName
    $temporaryPath = $finalPath + '.tmp'
    Write-Utf8NoBom $temporaryPath ($snapshot | ConvertTo-Json -Depth 5)
    [System.IO.File]::Move($temporaryPath, $finalPath)
    return [pscustomobject]$snapshot
}

function Read-TransactionState {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId
    )

    $statesRoot = Join-Path $TransactionRoot 'states'
    $candidates = @(Get-ChildItem -LiteralPath $statesRoot -File -Filter 'state-*.json' -ErrorAction SilentlyContinue |
        Sort-Object -Property Name -Descending)
    foreach ($candidate in $candidates) {
        try {
            $state = Read-StrictUtf8NoBom $candidate.FullName | ConvertFrom-Json
            if ([int]$state.schemaVersion -ne 1 -or
                [string]$state.projectId -cne $ExpectedProjectId -or
                [string]::IsNullOrWhiteSpace([string]$state.transactionId) -or
                [string]::IsNullOrWhiteSpace([string]$state.fromVersion) -or
                [string]::IsNullOrWhiteSpace([string]$state.toVersion)) {
                continue
            }
            $validHashes = $true
            foreach ($property in @('oldProjectSha256', 'oldBootstrapSha256', 'newProjectSha256', 'newBootstrapSha256')) {
                if ([string]$state.$property -notmatch '^[0-9A-F]{64}$') {
                    $validHashes = $false
                }
            }
            if ($validHashes) {
                return $state
            }
        }
        catch {
            continue
        }
    }
    throw "Upgrade transaction has no valid state; recovery materials were preserved: $TransactionRoot"
}

function Get-TransactionMaterialPaths {
    param([Parameter(Mandatory = $true)][string]$TransactionRoot)

    return [pscustomobject]@{
        OldProject = Join-ChildPath $TransactionRoot 'old/project.json'
        OldBootstrap = Join-ChildPath $TransactionRoot 'old/BOOTSTRAP.md'
        NewProject = Join-ChildPath $TransactionRoot 'new/project.json'
        NewBootstrap = Join-ChildPath $TransactionRoot 'new/BOOTSTRAP.md'
    }
}

function Assert-TransactionMaterials {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)]$State
    )

    $material = Get-TransactionMaterialPaths $TransactionRoot
    $expected = [ordered]@{
        OldProject = [string]$State.oldProjectSha256
        OldBootstrap = [string]$State.oldBootstrapSha256
        NewProject = [string]$State.newProjectSha256
        NewBootstrap = [string]$State.newBootstrapSha256
    }
    foreach ($name in $expected.Keys) {
        $path = [string]$material.$name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Upgrade recovery material is missing; transaction was preserved: $path"
        }
        $null = Read-StrictUtf8NoBom $path
        if ((Get-Sha256 $path) -cne $expected[$name]) {
            throw "Upgrade recovery material hash mismatch; transaction was preserved: $path"
        }
    }
    return $material
}

function Assert-KnownUpgradeTransactionDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId
    )

    $resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $resolvedTransaction = [System.IO.Path]::GetFullPath($TransactionRoot).TrimEnd('\')
    $prefix = $resolvedProject + [System.IO.Path]::DirectorySeparatorChar
    $name = Split-Path -Leaf $resolvedTransaction
    if (-not $resolvedTransaction.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Upgrade recovery material is outside the project boundary; preserving bytes: $resolvedTransaction"
    }
    Assert-NoReparseTree $resolvedTransaction

    $state = Read-TransactionState $resolvedTransaction $ExpectedProjectId
    if ([string]$state.transactionId -notmatch '^[0-9a-f]{32}$') {
        throw "Upgrade recovery material has an invalid transaction identity; preserving bytes: $resolvedTransaction"
    }
    if (($name -match '^\.fwu-(?:prep|done)-([0-9a-f]{32})$') -and
        [string]$state.transactionId -cne [string]$Matches[1]) {
        throw "Upgrade recovery directory name conflicts with its transaction identity; preserving bytes: $resolvedTransaction"
    }
    $material = Assert-TransactionMaterials $resolvedTransaction $state

    $requiredDirectories = @('old', 'new', 'states', 's', 'r')
    $actualDirectories = @(Get-ChildItem -LiteralPath $resolvedTransaction -Recurse -Directory -Force | ForEach-Object {
        $_.FullName.Substring($resolvedTransaction.Length + 1).Replace('\', '/')
    })
    if (@(Compare-Object -ReferenceObject $requiredDirectories -DifferenceObject $actualDirectories -CaseSensitive).Count -ne 0) {
        throw "Unknown or missing directory in upgrade recovery material; preserving bytes: $resolvedTransaction"
    }

    $requiredMaterialPaths = @('old/project.json', 'old/BOOTSTRAP.md', 'new/project.json', 'new/BOOTSTRAP.md')
    $allowedHashes = @(
        [string]$state.oldProjectSha256,
        [string]$state.oldBootstrapSha256,
        [string]$state.newProjectSha256,
        [string]$state.newBootstrapSha256
    )
    foreach ($file in Get-ChildItem -LiteralPath $resolvedTransaction -Recurse -File -Force) {
        $relative = $file.FullName.Substring($resolvedTransaction.Length + 1).Replace('\', '/')
        if ($relative -in $requiredMaterialPaths) {
            continue
        }
        if ($relative -match '^states/state-([0-9]{4})-([A-Z][A-Z0-9_]*)\.json$') {
            $snapshot = Read-StrictUtf8NoBom $file.FullName | ConvertFrom-Json
            if ([int]$snapshot.schemaVersion -ne 1 -or
                [int]$snapshot.sequence -ne [int]$Matches[1] -or
                [string]$snapshot.phase -cne [string]$Matches[2] -or
                [string]$snapshot.transactionId -cne [string]$state.transactionId -or
                [string]$snapshot.projectId -cne $ExpectedProjectId -or
                [string]$snapshot.fromVersion -cne [string]$state.fromVersion -or
                [string]$snapshot.toVersion -cne [string]$state.toVersion) {
                throw "Upgrade recovery state identity or schema is invalid; preserving bytes: $relative"
            }
            foreach ($property in @('oldProjectSha256', 'oldBootstrapSha256', 'newProjectSha256', 'newBootstrapSha256')) {
                if ([string]$snapshot.$property -cne [string]$state.$property) {
                    throw "Upgrade recovery state hash identity is invalid; preserving bytes: $relative"
                }
            }
            continue
        }
        if ($relative -match '^[sr]/[pb]-[0-9a-f]{32}\.(?:tmp|bak)$') {
            $null = Read-StrictUtf8NoBom $file.FullName
            if ((Get-Sha256 $file.FullName) -notin $allowedHashes) {
                throw "Upgrade recovery swap or backup hash is unknown; preserving bytes: $relative"
            }
            continue
        }
        throw "Unknown file in upgrade recovery material; preserving bytes: $relative"
    }
    return $material
}

function Get-TransactionPairState {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectFile,
        [Parameter(Mandatory = $true)][string]$BootstrapFile,
        [Parameter(Mandatory = $true)]$State
    )

    if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf) -or
        -not (Test-Path -LiteralPath $BootstrapFile -PathType Leaf)) {
        return [pscustomobject]@{ Status = 'UNKNOWN'; ProjectHash = ''; BootstrapHash = '' }
    }
    $projectHash = Get-Sha256 $ProjectFile
    $bootstrapHash = Get-Sha256 $BootstrapFile
    if ($projectHash -ceq [string]$State.oldProjectSha256 -and
        $bootstrapHash -ceq [string]$State.oldBootstrapSha256) {
        $status = 'OLD'
    }
    elseif ($projectHash -ceq [string]$State.newProjectSha256 -and
            $bootstrapHash -ceq [string]$State.newBootstrapSha256) {
        $status = 'NEW'
    }
    elseif (($projectHash -ceq [string]$State.oldProjectSha256 -or $projectHash -ceq [string]$State.newProjectSha256) -and
            ($bootstrapHash -ceq [string]$State.oldBootstrapSha256 -or $bootstrapHash -ceq [string]$State.newBootstrapSha256)) {
        $status = 'MIXED'
    }
    else {
        $status = 'UNKNOWN'
    }
    return [pscustomobject]@{
        Status = $status
        ProjectHash = $projectHash
        BootstrapHash = $bootstrapHash
    }
}

function Replace-FromTransactionMaterial {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$MaterialPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $swapRoot = Join-Path $TransactionRoot 's'
    $replacedRoot = Join-Path $TransactionRoot 'r'
    New-Item -ItemType Directory -Path $swapRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $replacedRoot -Force | Out-Null
    $attempt = [Guid]::NewGuid().ToString('N')
    $shortLabel = if ($Label.StartsWith('project')) { 'p' } else { 'b' }
    $swapPath = Join-Path $swapRoot "$shortLabel-$attempt.tmp"
    $replacedPath = Join-Path $replacedRoot "$shortLabel-$attempt.bak"
    [System.IO.File]::Copy($MaterialPath, $swapPath, $false)
    [System.IO.File]::Replace($swapPath, $DestinationPath, $replacedPath, $true)
    if ((Get-Sha256 $DestinationPath) -cne $ExpectedHash) {
        throw "Transaction replacement hash mismatch: $DestinationPath"
    }
}

function Set-TransactionPair {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('OLD', 'NEW')][string]$Desired,
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$ProjectFile,
        [Parameter(Mandatory = $true)][string]$BootstrapFile,
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Material
    )

    if ($Desired -eq 'NEW') {
        $desiredProjectHash = [string]$State.newProjectSha256
        $desiredBootstrapHash = [string]$State.newBootstrapSha256
        $alternateProjectHash = [string]$State.oldProjectSha256
        $alternateBootstrapHash = [string]$State.oldBootstrapSha256
        $projectMaterial = [string]$Material.NewProject
        $bootstrapMaterial = [string]$Material.NewBootstrap
    }
    else {
        $desiredProjectHash = [string]$State.oldProjectSha256
        $desiredBootstrapHash = [string]$State.oldBootstrapSha256
        $alternateProjectHash = [string]$State.newProjectSha256
        $alternateBootstrapHash = [string]$State.newBootstrapSha256
        $projectMaterial = [string]$Material.OldProject
        $bootstrapMaterial = [string]$Material.OldBootstrap
    }

    $projectHash = Get-Sha256 $ProjectFile
    if ($projectHash -cne $desiredProjectHash) {
        if ($projectHash -cne $alternateProjectHash) {
            throw "Project file has unknown bytes; recovery materials were preserved: $ProjectFile"
        }
        Replace-FromTransactionMaterial $TransactionRoot $projectMaterial $ProjectFile $desiredProjectHash 'project'
    }

    $bootstrapHash = Get-Sha256 $BootstrapFile
    if ($bootstrapHash -cne $desiredBootstrapHash) {
        if ($bootstrapHash -cne $alternateBootstrapHash) {
            throw "Bootstrap has unknown bytes; recovery materials were preserved: $BootstrapFile"
        }
        Replace-FromTransactionMaterial $TransactionRoot $bootstrapMaterial $BootstrapFile $desiredBootstrapHash 'bootstrap'
    }

    return Get-TransactionPairState $ProjectFile $BootstrapFile $State
}

function Recover-UpgradeTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ProjectFile,
        [Parameter(Mandatory = $true)][string]$BootstrapFile,
        [Parameter(Mandatory = $true)][string]$ProjectId
    )

    $state = Read-TransactionState $TransactionRoot $ProjectId
    $pair = Get-TransactionPairState $ProjectFile $BootstrapFile $state
    if ($pair.Status -eq 'UNKNOWN') {
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERY_REQUIRED' "Live files do not match the recorded old or new pair."
        throw "Upgrade transaction found unknown live bytes. Recovery materials were preserved: $TransactionRoot"
    }
    if ($pair.Status -eq 'NEW') {
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERED_COMMITTED'
        Finalize-TransactionDirectory $TransactionRoot $ProjectRoot $state.transactionId $ProjectId
        return 'COMMITTED'
    }
    if ($pair.Status -eq 'OLD') {
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERED_ROLLED_BACK'
        Finalize-TransactionDirectory $TransactionRoot $ProjectRoot $state.transactionId $ProjectId
        return 'ROLLED_BACK'
    }

    $material = Assert-TransactionMaterials $TransactionRoot $state

    $forwardError = $null
    try {
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERING_FORWARD'
        $pair = Set-TransactionPair 'NEW' $TransactionRoot $ProjectFile $BootstrapFile $state $material
        if ($pair.Status -ne 'NEW') {
            throw "Forward recovery did not produce the complete new pair."
        }
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERED_COMMITTED'
        Finalize-TransactionDirectory $TransactionRoot $ProjectRoot $state.transactionId $ProjectId
        return 'COMMITTED'
    }
    catch {
        $forwardError = $_
    }

    $rollbackError = $null
    try {
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERING_ROLLBACK' $forwardError.Exception.Message
        $pair = Set-TransactionPair 'OLD' $TransactionRoot $ProjectFile $BootstrapFile $state $material
        if ($pair.Status -ne 'OLD') {
            throw "Rollback recovery did not produce the complete old pair."
        }
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERED_ROLLED_BACK' $forwardError.Exception.Message
        Finalize-TransactionDirectory $TransactionRoot $ProjectRoot $state.transactionId $ProjectId
        return 'ROLLED_BACK'
    }
    catch {
        $rollbackError = $_
    }

    $combinedError = "forward: $($forwardError.Exception.Message); rollback: $($rollbackError.Exception.Message)"
    try {
        $state = Write-TransactionState $TransactionRoot $state 'RECOVERY_REQUIRED' $combinedError
    }
    catch {
        $combinedError += "; state: $($_.Exception.Message)"
    }
    throw "Upgrade recovery could not complete either pair. Recovery materials were preserved at $TransactionRoot. $combinedError"
}

function New-UpgradeTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ProjectFile,
        [Parameter(Mandatory = $true)][string]$BootstrapFile,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$FromVersion,
        [Parameter(Mandatory = $true)][string]$ToVersion,
        [Parameter(Mandatory = $true)][string]$TargetConfig,
        [Parameter(Mandatory = $true)][string]$TargetBootstrap
    )

    if (Test-Path -LiteralPath $TransactionRoot) {
        throw "An upgrade transaction already exists: $TransactionRoot"
    }
    $transactionId = [Guid]::NewGuid().ToString('N')
    $stagingRoot = Join-Path $ProjectRoot ".fwu-prep-$transactionId"
    try {
        New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'old') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'new') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'states') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 's') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'r') -Force | Out-Null

        [System.IO.File]::Copy($ProjectFile, (Join-ChildPath $stagingRoot 'old/project.json'), $false)
        [System.IO.File]::Copy($BootstrapFile, (Join-ChildPath $stagingRoot 'old/BOOTSTRAP.md'), $false)
        Write-Utf8NoBom (Join-ChildPath $stagingRoot 'new/project.json') $TargetConfig
        Write-Utf8NoBom (Join-ChildPath $stagingRoot 'new/BOOTSTRAP.md') $TargetBootstrap

        $baseState = [pscustomobject]@{
            schemaVersion = 1
            transactionId = $transactionId
            sequence = 0
            phase = 'INITIALIZING'
            projectId = $ProjectId
            fromVersion = $FromVersion
            toVersion = $ToVersion
            oldProjectSha256 = Get-Sha256 (Join-ChildPath $stagingRoot 'old/project.json')
            oldBootstrapSha256 = Get-Sha256 (Join-ChildPath $stagingRoot 'old/BOOTSTRAP.md')
            newProjectSha256 = Get-Sha256 (Join-ChildPath $stagingRoot 'new/project.json')
            newBootstrapSha256 = Get-Sha256 (Join-ChildPath $stagingRoot 'new/BOOTSTRAP.md')
            lastError = ''
        }
        $state = Write-TransactionState $stagingRoot $baseState 'PREPARED'
        $null = Assert-TransactionMaterials $stagingRoot $state
        [System.IO.Directory]::Move($stagingRoot, $TransactionRoot)
        return Read-TransactionState $TransactionRoot $ProjectId
    }
    catch {
        if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
            Remove-SafeTransactionDirectory $stagingRoot $ProjectRoot $ProjectId
        }
        throw
    }
}

if (-not $WorkspaceRoot) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $WorkspaceRoot = Split-Path -Parent $scriptDirectory
}

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$frameworkRoot = Join-ChildPath $workspace 'framework'
$projectsRoot = Join-ChildPath $workspace 'projects'
if (-not (Test-Path -LiteralPath $frameworkRoot -PathType Container)) {
    throw "Workspace root must contain the Framework directory: $workspace"
}

$legacyRoot = Join-ChildPath $projectsRoot $ProjectId
$legacyExists = Test-Path -LiteralPath $legacyRoot
$repoLocalRoot = $null
if ($RepositoryPath) {
    if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
        throw "Repository path does not exist: $RepositoryPath"
    }
    $repo = Get-GitRepositoryRoot ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).ProviderPath))
    $repoLocalRoot = Join-Path $repo '.ai-workspace'
}
elseif ($legacyExists) {
    if (-not (Test-Path -LiteralPath $legacyRoot -PathType Container)) {
        throw "Central legacy project path exists but is not a directory: $legacyRoot"
    }
    Assert-NoReparseTree $legacyRoot
    $discoveryProjectFile = Join-ChildPath $legacyRoot 'project.json'
    if (-not (Test-Path -LiteralPath $discoveryProjectFile -PathType Leaf)) {
        throw "Central legacy project identity is incomplete: $legacyRoot"
    }
    try {
        $discoveryConfig = (Read-StrictUtf8NoBom $discoveryProjectFile) | ConvertFrom-Json
    }
    catch {
        throw "Central legacy project identity is invalid: $discoveryProjectFile"
    }
    if ([string]$discoveryConfig.id -cne $ProjectId -or
        $discoveryConfig.PSObject.Properties.Name -notcontains 'repositoryPath' -or
        [string]::IsNullOrWhiteSpace([string]$discoveryConfig.repositoryPath)) {
        throw "Central legacy project identity is incomplete or conflicts with its directory: $discoveryProjectFile"
    }
    $recordedRepositoryPath = [System.IO.Path]::GetFullPath([string]$discoveryConfig.repositoryPath)
    if (-not (Test-Path -LiteralPath $recordedRepositoryPath -PathType Container)) {
        throw "Central legacy repositoryPath does not exist or is not a directory: $recordedRepositoryPath"
    }
    $repo = Get-GitRepositoryRoot ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $recordedRepositoryPath).ProviderPath))
    $repoLocalRoot = Join-Path $repo '.ai-workspace'
}

if ($repoLocalRoot -and (Test-Path -LiteralPath $repoLocalRoot)) {
    if (-not (Test-Path -LiteralPath $repoLocalRoot -PathType Container)) {
        throw "Repo-local control-plane path exists but is not a directory; refusing central fallback: $repoLocalRoot"
    }
    $projectRoot = $repoLocalRoot
    $layout = 'repo-local'
}
elseif ($legacyExists) {
    if (-not (Test-Path -LiteralPath $legacyRoot -PathType Container)) {
        throw "Central legacy project path exists but is not a directory: $legacyRoot"
    }
    $projectRoot = $legacyRoot
    $layout = 'central-legacy'
}
else {
    throw "Unknown project. Supply RepositoryPath for repo-local projects: $ProjectId"
}
Assert-NoReparseTree $projectRoot

$projectFile = Join-ChildPath $projectRoot 'project.json'
$bootstrapFile = Join-ChildPath $projectRoot 'BOOTSTRAP.md'
$targetFramework = Join-ChildPath $frameworkRoot "versions/$ToVersion"

if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "Unknown project: $ProjectId"
}
if (-not (Test-Path -LiteralPath $bootstrapFile -PathType Leaf)) {
    throw "Project Bootstrap does not exist: $bootstrapFile"
}

$transactionRoot = Join-Path $projectRoot '.framework-upgrade-transaction'
$completedTransactions = @(Get-ChildItem -LiteralPath $projectRoot -Directory -Force -Filter '.fwu-done-*' -ErrorAction SilentlyContinue)
$abandonedPreparations = @(Get-ChildItem -LiteralPath $projectRoot -Directory -Force -Filter '.fwu-prep-*' -ErrorAction SilentlyContinue)
if ($Apply) {
    foreach ($completedTransaction in $completedTransactions) {
        Remove-SafeTransactionDirectory $completedTransaction.FullName $projectRoot $ProjectId
    }
    if (Test-Path -LiteralPath $transactionRoot -PathType Container) {
        $recoveryResult = Recover-UpgradeTransaction $transactionRoot $projectRoot $projectFile $bootstrapFile $ProjectId
        Write-Host "Recovered previous Framework upgrade transaction: $recoveryResult"
        return
    }
    foreach ($abandonedPreparation in $abandonedPreparations) {
        Remove-SafeTransactionDirectory $abandonedPreparation.FullName $projectRoot $ProjectId
    }
}
elseif ((Test-Path -LiteralPath $transactionRoot -PathType Container) -or
        $completedTransactions.Count -ne 0 -or $abandonedPreparations.Count -ne 0) {
    Write-Host 'Preview only. Existing upgrade recovery material was detected; -Apply will recover it before a new request.'
    return
}

if (-not (Test-Path -LiteralPath $targetFramework -PathType Container)) {
    throw "Framework version does not exist: $ToVersion"
}

$configText = Read-StrictUtf8NoBom $projectFile
try {
    $config = $configText | ConvertFrom-Json
}
catch {
    throw "Project configuration is not valid JSON: $projectFile"
}
foreach ($property in @('id', 'displayName', 'frameworkVersion')) {
    if ($config.PSObject.Properties.Name -notcontains $property -or [string]::IsNullOrWhiteSpace([string]$config.$property)) {
        throw "Project configuration is missing a required property: $property"
    }
}
if ([string]$config.id -cne $ProjectId) {
    throw "Project id does not match its directory: $($config.id)"
}
if ($layout -eq 'repo-local') {
    foreach ($property in @('schemaVersion', 'controlPlaneLayout', 'repositoryRoot')) {
        if ($config.PSObject.Properties.Name -notcontains $property) {
            throw "Repo-local project configuration is missing a required property: $property"
        }
    }
    if ([int]$config.schemaVersion -ne 2 -or
        [string]$config.controlPlaneLayout -cne 'repo-local' -or
        [string]$config.repositoryRoot -cne '..') {
        throw "Repo-local project configuration has an unsupported layout: $projectFile"
    }
    if (Test-Path -LiteralPath $legacyRoot) {
        if (-not (Test-Path -LiteralPath $legacyRoot -PathType Container)) {
            throw "A central legacy collision exists but is not a directory; refusing to ignore it: $legacyRoot"
        }
        Assert-NoReparseTree $legacyRoot
        foreach ($relativeFile in @('project.json', 'BOOTSTRAP.md', 'PROJECT.md', 'REVIEW_PROFILE.md', 'RELATIONSHIPS.md', 'STATUS.md', 'tasks/README.md')) {
            if (-not (Test-Path -LiteralPath (Join-ChildPath $legacyRoot $relativeFile) -PathType Leaf)) {
                throw 'Repo-local and central legacy control planes coexist, but the central control plane is partial.'
            }
        }
        foreach ($relativeDirectory in @('tasks', 'tasks/active', 'tasks/archive')) {
            if (-not (Test-Path -LiteralPath (Join-ChildPath $legacyRoot $relativeDirectory) -PathType Container)) {
                throw 'Repo-local and central legacy control planes coexist, but the central control plane is partial.'
            }
        }
        $legacyConfigFile = Join-Path $legacyRoot 'project.json'
        if (-not (Test-Path -LiteralPath $legacyConfigFile -PathType Leaf)) {
            throw 'Repo-local and central legacy control planes coexist, but the central identity is incomplete.'
        }
        try {
            $legacyConfig = (Read-StrictUtf8NoBom $legacyConfigFile) | ConvertFrom-Json
        }
        catch {
            throw 'Repo-local and central legacy control planes coexist, but the central identity is invalid.'
        }
        if ($legacyConfig.PSObject.Properties.Name -notcontains 'repositoryPath' -or
            [string]::IsNullOrWhiteSpace([string]$legacyConfig.repositoryPath)) {
            throw 'Repo-local and central legacy identities conflict; refusing to choose an authority.'
        }
        $legacyRepository = [System.IO.Path]::GetFullPath([string]$legacyConfig.repositoryPath).TrimEnd('\')
        if ([string]$legacyConfig.id -cne $ProjectId -or
            -not $legacyRepository.Equals($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Repo-local and central legacy identities conflict; refusing to choose an authority.'
        }
    }
    $repoStatusResult = Invoke-GitCapture @('-C', $repo, '-c', 'core.excludesFile=', 'status', '--porcelain=v1', '--untracked-files=all')
    $repoStatus = @($repoStatusResult.Output)
    if ($repoStatusResult.ExitCode -ne 0) {
        throw "Unable to inspect repo-local project status: $repo"
    }
    if ($repoStatus.Count -ne 0) {
        throw "Repo-local project upgrade requires a clean Git working tree: $repo"
    }
}
elseif ($config.PSObject.Properties.Name -notcontains 'repositoryPath' -or
        [string]::IsNullOrWhiteSpace([string]$config.repositoryPath)) {
    throw 'Central legacy project configuration is missing repositoryPath.'
}
elseif ($RepositoryPath) {
    $recordedRepository = [System.IO.Path]::GetFullPath([string]$config.repositoryPath).TrimEnd('\')
    if (-not $recordedRepository.Equals($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Central legacy repositoryPath conflicts with the supplied repository.'
    }
}

$fromVersion = [string]$config.frameworkVersion
if ($fromVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
    throw "Project configuration contains an invalid pinned Framework version: $fromVersion"
}
$sourceFramework = Join-ChildPath $frameworkRoot "versions/$fromVersion"
$sourceBootstrapTemplate = Join-ChildPath $sourceFramework 'project-starter/BOOTSTRAP.md'
$targetBootstrapTemplate = Join-ChildPath $targetFramework 'project-starter/BOOTSTRAP.md'
$targetProjectTemplate = Join-ChildPath $targetFramework 'project-starter/project.json'
if (-not (Test-Path -LiteralPath $targetBootstrapTemplate -PathType Leaf)) {
    throw "Target Framework Bootstrap template does not exist: $targetBootstrapTemplate"
}
if (-not (Test-Path -LiteralPath $targetProjectTemplate -PathType Leaf)) {
    throw "Target Framework project template does not exist: $targetProjectTemplate"
}
$targetProjectTemplateText = Read-StrictUtf8NoBom $targetProjectTemplate
if ($layout -eq 'central-legacy' -and $targetProjectTemplateText.Contains('"controlPlaneLayout": "repo-local"')) {
    throw 'A central legacy project cannot change topology through upgrade-project.ps1; request a separately authorized project-specific relocation.'
}
if ($layout -eq 'repo-local' -and -not $targetProjectTemplateText.Contains('"controlPlaneLayout": "repo-local"')) {
    throw 'A repo-local project can only upgrade to a repo-local Framework starter.'
}

$currentBootstrap = Normalize-Text (Read-StrictUtf8NoBom $bootstrapFile)
if (-not (Test-Path -LiteralPath $sourceFramework -PathType Container)) {
    throw "Pinned Framework directory does not exist in framework/versions; tags and current HEAD are not runtime fallbacks: $sourceFramework"
}
if (-not (Test-Path -LiteralPath $sourceBootstrapTemplate -PathType Leaf)) {
    throw "Pinned Framework directory is incomplete; Bootstrap template does not exist: $sourceBootstrapTemplate"
}
$sourceTemplate = Read-StrictUtf8NoBom $sourceBootstrapTemplate
$targetTemplate = Read-StrictUtf8NoBom $targetBootstrapTemplate
$expectedCurrentBootstrap = Render-Bootstrap $sourceTemplate $config $fromVersion
if ($layout -eq 'central-legacy') {
    if ($currentBootstrap -cne $expectedCurrentBootstrap) {
        throw "Project Bootstrap does not match its pinned Framework starter; refusing an incomplete upgrade: $bootstrapFile"
    }
    $targetBootstrap = Render-Bootstrap $targetTemplate $config $ToVersion
}
else {
    $currentBlock = Get-ManagedBootstrapBlock $currentBootstrap $bootstrapFile
    $expectedBlock = Get-ManagedBootstrapBlock $expectedCurrentBootstrap $sourceBootstrapTemplate
    if ($currentBlock.Text -cne $expectedBlock.Text) {
        throw "Repo-local Bootstrap managed block was customized; refusing to overwrite it: $bootstrapFile"
    }
    $renderedTarget = Render-Bootstrap $targetTemplate $config $ToVersion
    $targetBlock = Get-ManagedBootstrapBlock $renderedTarget $targetBootstrapTemplate
    $targetBootstrap = Replace-ManagedBootstrapBlock $currentBootstrap $targetBlock.Text $currentBlock
}
Assert-TargetBootstrapContract $targetBootstrap $ToVersion $workspace $targetFramework $layout

Write-Host "Project: $ProjectId"
Write-Host "Layout: $layout"
Write-Host "Framework: $fromVersion -> $ToVersion"
Write-Host 'Upgrade: same-topology project pin and managed Bootstrap locator'

if (-not $Apply) {
    Write-Host 'Preview only. Upgrade preconditions passed; rerun with -Apply.'
    return
}

if ($fromVersion -eq $ToVersion) {
    Write-Host 'Already on requested version with a matching Bootstrap; no change.'
    return
}

$config.frameworkVersion = $ToVersion
$targetConfig = Normalize-Text ($config | ConvertTo-Json -Depth 100)
try {
    $validatedConfig = $targetConfig | ConvertFrom-Json
}
catch {
    throw 'Generated project configuration is not valid JSON.'
}
if ([string]$validatedConfig.frameworkVersion -cne $ToVersion) {
    throw 'Generated project configuration does not contain the target Framework version.'
}

$transactionState = New-UpgradeTransaction $transactionRoot $projectRoot $projectFile $bootstrapFile $ProjectId $fromVersion $ToVersion $targetConfig $targetBootstrap
$transactionMaterial = Assert-TransactionMaterials $transactionRoot $transactionState
$commitFailure = $null
$commitComplete = $false

try {
    $transactionState = Write-TransactionState $transactionRoot $transactionState 'COMMITTING_PROJECT'
    Replace-FromTransactionMaterial $transactionRoot $transactionMaterial.NewProject $projectFile $transactionState.newProjectSha256 'project-commit'
    $transactionState = Write-TransactionState $transactionRoot $transactionState 'PROJECT_REPLACED'

    if ([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE') -eq '1' -and
        [Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_PROJECT_REPLACE') -eq '1') {
        [System.Diagnostics.Process]::GetCurrentProcess().Kill()
        throw 'Test interruption did not terminate the process.'
    }

    $transactionState = Write-TransactionState $transactionRoot $transactionState 'COMMITTING_BOOTSTRAP'
    Replace-FromTransactionMaterial $transactionRoot $transactionMaterial.NewBootstrap $bootstrapFile $transactionState.newBootstrapSha256 'bootstrap-commit'
    $pair = Get-TransactionPairState $projectFile $bootstrapFile $transactionState
    if ($pair.Status -ne 'NEW') {
        throw 'Upgrade commit did not produce the complete new pair.'
    }
    $transactionState = Write-TransactionState $transactionRoot $transactionState 'COMMITTED'
    $commitComplete = $true
}
catch {
    $commitFailure = $_
}

if ($commitComplete) {
    try {
        Finalize-TransactionDirectory $transactionRoot $projectRoot $transactionState.transactionId $ProjectId
    }
    catch {
        throw "Upgrade committed both files, but transaction cleanup failed. The next invocation will verify and finalize recovery materials at $transactionRoot. $($_.Exception.Message)"
    }
}
else {
    $rollbackError = $null
    $rollbackComplete = $false
    try {
        $transactionState = Write-TransactionState $transactionRoot $transactionState 'ROLLING_BACK' $commitFailure.Exception.Message
        $pair = Set-TransactionPair 'OLD' $transactionRoot $projectFile $bootstrapFile $transactionState $transactionMaterial
        if ($pair.Status -ne 'OLD') {
            throw 'Rollback did not produce the complete old pair.'
        }
        $transactionState = Write-TransactionState $transactionRoot $transactionState 'ROLLED_BACK' $commitFailure.Exception.Message
        $rollbackComplete = $true
    }
    catch {
        $rollbackError = $_
    }

    if ($rollbackComplete) {
        try {
            Finalize-TransactionDirectory $transactionRoot $projectRoot $transactionState.transactionId $ProjectId
        }
        catch {
            throw "Upgrade failed and both files were rolled back, but transaction cleanup failed. The next invocation will verify and finalize recovery materials at $transactionRoot. Commit: $($commitFailure.Exception.Message); cleanup: $($_.Exception.Message)"
        }
        throw $commitFailure
    }

    $combinedError = "commit: $($commitFailure.Exception.Message); rollback: $($rollbackError.Exception.Message)"
    try {
        $transactionState = Write-TransactionState $transactionRoot $transactionState 'RECOVERY_REQUIRED' $combinedError
    }
    catch {
        $combinedError += "; state: $($_.Exception.Message)"
    }
    throw "Upgrade failed and rollback was incomplete. Recovery materials were retained at $transactionRoot. The next invocation will recover or resume before validating a new request. $combinedError"
}

Write-Host "Updated: $projectFile"
Write-Host "Updated: $bootstrapFile"
Write-Host 'Committed recoverable two-file transaction: project pin and Bootstrap/checker locator.'
Write-Host 'Next: review the version diff, update project exceptions if needed, and commit both upgraded files together.'
