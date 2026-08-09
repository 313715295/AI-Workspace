[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryPath,

    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$FrameworkVersion,

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

function Read-StrictUtf8Template {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "File must be UTF-8 without BOM: $Path"
    }
    try {
        $content = $utf8Strict.GetString($bytes)
    }
    catch {
        throw "File is not strict UTF-8: $Path"
    }
    if ($content.Contains([char]0) -or $content.Contains([char]0xFFFD)) {
        throw "File contains a forbidden text code point: $Path"
    }
    if ($content.Contains("`r")) {
        throw "File must use LF line endings: $Path"
    }
    if (-not $content.EndsWith("`n")) {
        throw "File must end with LF: $Path"
    }
    return $content
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $normalized = $Content -replace "`r`n", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
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

function Assert-NoReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed for the project control plane: $Path"
    }
}

function Assert-NoReparseTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-NoReparsePoint $Path
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed for the project control plane: $($item.FullName)"
        }
    }
}

function Get-RepoLocalBootstrapRegions {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $managedBegin = '<!-- FRAMEWORK-MANAGED:BEGIN -->'
    $managedEnd = '<!-- FRAMEWORK-MANAGED:END -->'
    $customBegin = '<!-- PROJECT-CUSTOM:BEGIN -->'
    $customEnd = '<!-- PROJECT-CUSTOM:END -->'
    foreach ($marker in @($managedBegin, $managedEnd, $customBegin, $customEnd)) {
        if ([regex]::Matches($Content, [regex]::Escape($marker)).Count -ne 1) {
            throw "Repo-local Bootstrap markers must each appear exactly once: $Source"
        }
    }

    $managedBeginIndex = $Content.IndexOf($managedBegin, [System.StringComparison]::Ordinal)
    $managedEndIndex = $Content.IndexOf($managedEnd, [System.StringComparison]::Ordinal)
    $customBeginIndex = $Content.IndexOf($customBegin, [System.StringComparison]::Ordinal)
    $customEndIndex = $Content.IndexOf($customEnd, [System.StringComparison]::Ordinal)
    if (-not ($managedBeginIndex -lt $managedEndIndex -and
              $managedEndIndex -lt $customBeginIndex -and
              $customBeginIndex -lt $customEndIndex)) {
        throw "Repo-local Bootstrap markers must be paired and ordered managed-then-custom: $Source"
    }

    $managedBlockEnd = $managedEndIndex + $managedEnd.Length
    return [pscustomobject]@{
        ManagedText = $Content.Substring($managedBeginIndex, $managedBlockEnd - $managedBeginIndex)
    }
}

function Render-RepoLocalBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)]$ProjectConfig,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $rendered = $Template
    $rendered = $rendered.Replace('{{PROJECT_ID}}', [string]$ProjectConfig.id)
    $rendered = $rendered.Replace('{{DISPLAY_NAME}}', [string]$ProjectConfig.displayName)
    $rendered = $rendered.Replace('{{FRAMEWORK_VERSION}}', $FrameworkVersion)
    if ($rendered -match '\{\{[A-Z0-9_]+\}\}') {
        throw "Repo-local Bootstrap template contains an unresolved token: $Source"
    }
    return $rendered
}

function Get-RepoLocalStarter {
    param(
        [Parameter(Mandatory = $true)][string]$FrameworkRoot,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$TemplateMap,
        [Parameter(Mandatory = $true)][string]$Selection
    )

    $frameworkPath = Join-ChildPath $FrameworkRoot "versions/$FrameworkVersion"
    $templateRoot = Join-ChildPath $frameworkPath 'project-starter'
    if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
        throw "Framework project starter does not exist: $templateRoot"
    }
    Assert-NoReparseTree $templateRoot
    foreach ($relativeTemplate in $TemplateMap.Keys) {
        $templatePath = Join-ChildPath $templateRoot $relativeTemplate
        if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
            throw "Required project template is missing: $templatePath"
        }
    }
    $projectTemplateText = Read-StrictUtf8Template (Join-ChildPath $templateRoot 'project.json')
    if (-not $projectTemplateText.Contains('"schemaVersion": 2') -or
        -not $projectTemplateText.Contains('"controlPlaneLayout": "repo-local"') -or
        -not $projectTemplateText.Contains('"repositoryRoot": ".."')) {
        throw "$Selection does not publish a repo-local project starter. Select Framework 1.4.0 or later explicitly until CURRENT is activated."
    }
    $bootstrapTemplate = Read-StrictUtf8Template (Join-ChildPath $templateRoot 'BOOTSTRAP.md')
    $null = Get-RepoLocalBootstrapRegions $bootstrapTemplate (Join-ChildPath $templateRoot 'BOOTSTRAP.md')
    return [pscustomobject]@{
        TemplateRoot = $templateRoot
        BootstrapTemplate = $bootstrapTemplate
    }
}

function Assert-CompatibleCentralCollision {
    param(
        [Parameter(Mandatory = $true)][string]$LegacyRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId,
        [Parameter(Mandatory = $true)][string]$ExpectedRepository
    )

    if (-not (Test-Path -LiteralPath $LegacyRoot -PathType Container)) {
        throw "A central legacy collision exists but is not a directory; refusing to ignore it: $LegacyRoot"
    }
    Assert-NoReparseTree $LegacyRoot
    foreach ($relativeFile in @('project.json', 'BOOTSTRAP.md', 'PROJECT.md', 'REVIEW_PROFILE.md', 'RELATIONSHIPS.md', 'STATUS.md', 'tasks/README.md')) {
        if (-not (Test-Path -LiteralPath (Join-ChildPath $LegacyRoot $relativeFile) -PathType Leaf)) {
            throw "Repo-local and central legacy control planes coexist, but the central control plane is partial: $LegacyRoot"
        }
    }
    foreach ($relativeDirectory in @('tasks', 'tasks/active', 'tasks/archive')) {
        if (-not (Test-Path -LiteralPath (Join-ChildPath $LegacyRoot $relativeDirectory) -PathType Container)) {
            throw "Repo-local and central legacy control planes coexist, but the central control plane is partial: $LegacyRoot"
        }
    }
    $legacyProjectFile = Join-Path $LegacyRoot 'project.json'
    if (-not (Test-Path -LiteralPath $legacyProjectFile -PathType Leaf)) {
        throw "Repo-local and central legacy control planes coexist, but the central identity is incomplete: $LegacyRoot"
    }
    try {
        $legacyConfig = (Read-StrictUtf8Template $legacyProjectFile) | ConvertFrom-Json
    }
    catch {
        throw "Repo-local and central legacy control planes coexist, but the central identity is invalid: $legacyProjectFile"
    }
    if ($legacyConfig.PSObject.Properties.Name -notcontains 'repositoryPath' -or
        [string]::IsNullOrWhiteSpace([string]$legacyConfig.repositoryPath)) {
        throw 'Repo-local and central legacy identities conflict; refusing to choose an authority.'
    }
    $legacyRepository = [System.IO.Path]::GetFullPath([string]$legacyConfig.repositoryPath).TrimEnd('\')
    if ([string]$legacyConfig.id -cne $ExpectedProjectId -or
        -not $legacyRepository.Equals($ExpectedRepository, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Repo-local and central legacy identities conflict; refusing to choose an authority.'
    }
}

function Assert-RepoLocalProject {
    param(
        [Parameter(Mandatory = $true)][string]$ControlRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId,
        [Parameter(Mandatory = $true)][string]$ExpectedDisplayName,
        [Parameter(Mandatory = $true)][string]$ExpectedFrameworkVersion,
        [Parameter(Mandatory = $true)][string[]]$RequiredFiles,
        [Parameter(Mandatory = $true)][string[]]$RequiredDirectories,
        [Parameter(Mandatory = $true)][string]$ExpectedBootstrapTemplate
    )

    Assert-NoReparseTree $ControlRoot
    $actualFiles = @(Get-ChildItem -LiteralPath $ControlRoot -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($ControlRoot.Length + 1).Replace('\', '/')
    })
    $actualDirectories = @(Get-ChildItem -LiteralPath $ControlRoot -Recurse -Directory -Force | ForEach-Object {
        $_.FullName.Substring($ControlRoot.Length + 1).Replace('\', '/')
    })
    $fileDifference = @(Compare-Object -ReferenceObject @($RequiredFiles) -DifferenceObject $actualFiles -CaseSensitive)
    $directoryDifference = @(Compare-Object -ReferenceObject @($RequiredDirectories) -DifferenceObject $actualDirectories -CaseSensitive)
    if ($fileDifference.Count -ne 0 -or $directoryDifference.Count -ne 0) {
        throw "Existing .ai-workspace inventory conflicts with a complete registration; refusing to merge, overwrite, or treat unknown live bytes as registered: $ControlRoot"
    }
    foreach ($relativeFile in $RequiredFiles) {
        $null = Read-StrictUtf8Template (Join-ChildPath $ControlRoot $relativeFile)
    }
    $projectFile = Join-Path $ControlRoot 'project.json'
    $bootstrapFile = Join-Path $ControlRoot 'BOOTSTRAP.md'
    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf) -or
        -not (Test-Path -LiteralPath $bootstrapFile -PathType Leaf)) {
        throw "Existing .ai-workspace is partial; refusing to merge or overwrite: $ControlRoot"
    }
    try {
        $config = (Read-StrictUtf8Template $projectFile) | ConvertFrom-Json
    }
    catch {
        throw "Existing repo-local project.json is invalid: $projectFile"
    }
    if ([int]$config.schemaVersion -ne 2 -or
        [string]$config.controlPlaneLayout -cne 'repo-local' -or
        [string]$config.repositoryRoot -cne '..' -or
        [string]$config.id -cne $ExpectedProjectId -or
        [string]$config.displayName -cne $ExpectedDisplayName -or
        [string]$config.frameworkVersion -cne $ExpectedFrameworkVersion) {
        throw "Existing .ai-workspace identity conflicts with the requested project: $ControlRoot"
    }
    $bootstrap = Read-StrictUtf8Template $bootstrapFile
    $actualRegions = Get-RepoLocalBootstrapRegions $bootstrap $bootstrapFile
    $expectedBootstrap = Render-RepoLocalBootstrap $ExpectedBootstrapTemplate $config $ExpectedFrameworkVersion 'pinned Framework starter'
    $expectedRegions = Get-RepoLocalBootstrapRegions $expectedBootstrap 'pinned Framework starter'
    if ($actualRegions.ManagedText -cne $expectedRegions.ManagedText) {
        throw "Existing repo-local Bootstrap managed block was customized; refusing ALREADY_REGISTERED: $bootstrapFile"
    }
}

function Remove-SafeInitializationDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId,
        [Parameter(Mandatory = $true)][string[]]$AllowedRelativeFiles
    )

    $resolvedRepo = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $prefix = $resolvedRepo + [System.IO.Path]::DirectorySeparatorChar
    $name = Split-Path -Leaf $resolvedPath
    $pattern = '^\.' + [regex]::Escape($ExpectedProjectId) + '\.ai-workspace-init\.[0-9a-f]{32}$'
    if (-not $resolvedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $name -notmatch $pattern) {
        throw "Refusing to remove an unexpected initialization path: $resolvedPath"
    }
    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        foreach ($directory in Get-ChildItem -LiteralPath $resolvedPath -Recurse -Directory -Force) {
            if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Unknown reparse point appeared in initialization staging; preserving bytes: $($directory.FullName)"
            }
        }
        foreach ($file in Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -Force) {
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Unknown reparse point appeared in initialization staging; preserving bytes: $($file.FullName)"
            }
            $relative = $file.FullName.Substring($resolvedPath.Length + 1).Replace('\', '/')
            if ($relative -notin $AllowedRelativeFiles) {
                throw "Unknown live bytes appeared in initialization staging; preserving bytes: $relative"
            }
        }
        [System.IO.Directory]::Delete($resolvedPath, $true)
    }
}

if (-not $WorkspaceRoot) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $WorkspaceRoot = Split-Path -Parent $scriptDirectory
}

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$frameworkRoot = Join-ChildPath $workspace 'framework'
if (-not (Test-Path -LiteralPath $frameworkRoot -PathType Container)) {
    throw "Workspace root must contain the Framework directory: $workspace"
}
Assert-NoReparsePoint $frameworkRoot

if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
    throw "Repository path does not exist or is not a directory: $RepositoryPath"
}
$repo = Get-GitRepositoryRoot ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).ProviderPath))

$templateMap = [ordered]@{
    '.gitattributes' = '.gitattributes'
    'project.json' = 'project.json'
    'BOOTSTRAP.md' = 'BOOTSTRAP.md'
    'PROJECT.md' = 'PROJECT.md'
    'REVIEW_PROFILE.md' = 'REVIEW_PROFILE.md'
    'RELATIONSHIPS.md' = 'RELATIONSHIPS.md'
    'STATUS.md' = 'STATUS.md'
    'tasks/README.md' = 'tasks/README.md'
}
$requiredProjectFiles = @($templateMap.Values)
$requiredProjectDirectories = @('tasks', 'tasks/active', 'tasks/archive')
$projectRoot = Join-Path $repo '.ai-workspace'
$legacyRoot = Join-ChildPath $workspace "projects/$ProjectId"
$frameworkVersionWasExplicit = -not [string]::IsNullOrWhiteSpace($FrameworkVersion)
if (Test-Path -LiteralPath $projectRoot) {
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Project control-plane target exists but is not a directory: $projectRoot"
    }
    Assert-NoReparseTree $projectRoot
    $existingProjectFile = Join-Path $projectRoot 'project.json'
    if (-not (Test-Path -LiteralPath $existingProjectFile -PathType Leaf)) {
        throw "Existing .ai-workspace is partial; refusing to merge or overwrite: $projectRoot"
    }
    try {
        $existingConfig = (Read-StrictUtf8Template $existingProjectFile) | ConvertFrom-Json
    }
    catch {
        throw "Existing repo-local project.json is invalid: $existingProjectFile"
    }
    $existingVersion = [string]$existingConfig.frameworkVersion
    if ([string]::IsNullOrWhiteSpace($existingVersion) -or $existingVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
        throw "Existing repo-local project.json has an invalid Framework pin: $existingProjectFile"
    }
    if ($frameworkVersionWasExplicit -and $FrameworkVersion -cne $existingVersion) {
        throw "Existing .ai-workspace Framework pin conflicts with the explicitly requested Framework: $projectRoot"
    }
    $FrameworkVersion = $existingVersion
    $existingStarter = Get-RepoLocalStarter $frameworkRoot $FrameworkVersion $templateMap "Framework $FrameworkVersion"
    Assert-RepoLocalProject $projectRoot $ProjectId $DisplayName $FrameworkVersion $requiredProjectFiles $requiredProjectDirectories $existingStarter.BootstrapTemplate
    if (Test-Path -LiteralPath $legacyRoot) {
        Assert-CompatibleCentralCollision $legacyRoot $ProjectId $repo
    }
    [pscustomobject]@{
        status = 'ALREADY_REGISTERED'
        projectRoot = $projectRoot
        frameworkVersion = $FrameworkVersion
    }
    return
}
if (Test-Path -LiteralPath $legacyRoot) {
    throw "A central legacy project with this id already exists; registration cannot change layout. Request a separately authorized project-specific relocation: $legacyRoot"
}

if (-not $frameworkVersionWasExplicit) {
    $currentFile = Join-ChildPath $frameworkRoot 'CURRENT'
    $FrameworkVersion = (Read-StrictUtf8Template $currentFile).Trim()
}
$selection = if ($frameworkVersionWasExplicit) { "Framework $FrameworkVersion" } else { "framework/CURRENT ($FrameworkVersion)" }
$starter = Get-RepoLocalStarter $frameworkRoot $FrameworkVersion $templateMap $selection
$templateRoot = $starter.TemplateRoot

$statusResult = Invoke-GitCapture @('-C', $repo, '-c', 'core.excludesFile=', 'status', '--porcelain=v1', '--untracked-files=all')
$dirty = @($statusResult.Output)
if ($statusResult.ExitCode -ne 0) {
    throw "Unable to inspect repository status: $repo"
}
if ($dirty.Count -ne 0) {
    throw "Repository working tree must be clean for new project registration: $repo"
}

$createdDate = Get-Date -Format 'yyyy-MM-dd'
$markdownTokens = [ordered]@{
    '{{PROJECT_ID}}' = $ProjectId
    '{{DISPLAY_NAME}}' = $DisplayName
    '{{FRAMEWORK_VERSION}}' = $FrameworkVersion
    '{{CREATED_DATE}}' = $createdDate
}
$jsonTokens = [ordered]@{
    '{{PROJECT_ID_JSON}}' = ($ProjectId | ConvertTo-Json -Compress)
    '{{DISPLAY_NAME_JSON}}' = ($DisplayName | ConvertTo-Json -Compress)
    '{{FRAMEWORK_VERSION_JSON}}' = ($FrameworkVersion | ConvertTo-Json -Compress)
}

if (-not $Apply -or -not $PSCmdlet.ShouldProcess($projectRoot, 'Create repository-local project control plane')) {
    [pscustomobject]@{
        status = 'WHAT_IF'
        projectRoot = $projectRoot
        frameworkVersion = $FrameworkVersion
        templates = @($templateMap.Keys)
    }
    return
}

$stagingRoot = Join-Path $repo ".$ProjectId.ai-workspace-init.$([Guid]::NewGuid().ToString('N'))"

try {
    New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'tasks/active') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'tasks/archive') -Force | Out-Null

    foreach ($entry in $templateMap.GetEnumerator()) {
        $sourcePath = Join-ChildPath $templateRoot $entry.Key
        $destinationPath = Join-ChildPath $stagingRoot $entry.Value
        $content = Read-StrictUtf8Template $sourcePath

        foreach ($token in $markdownTokens.GetEnumerator()) {
            $content = $content.Replace($token.Key, $token.Value)
        }
        foreach ($token in $jsonTokens.GetEnumerator()) {
            $content = $content.Replace($token.Key, $token.Value)
        }

        if ($content -match '\{\{[A-Z0-9_]+\}\}') {
            throw "Unresolved template token in: $sourcePath"
        }
        if ($entry.Value -eq 'project.json') {
            $null = $content | ConvertFrom-Json
        }

        Write-Utf8NoBom -Path $destinationPath -Content $content
        $null = Read-StrictUtf8Template $destinationPath
    }

    Assert-RepoLocalProject $stagingRoot $ProjectId $DisplayName $FrameworkVersion $requiredProjectFiles $requiredProjectDirectories $starter.BootstrapTemplate
    [System.IO.Directory]::Move($stagingRoot, $projectRoot)
}
catch {
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
        Remove-SafeInitializationDirectory $stagingRoot $repo $ProjectId -AllowedRelativeFiles @($templateMap.Values)
    }
    throw
}

[pscustomobject]@{
    status = 'CREATED'
    projectRoot = $projectRoot
    frameworkVersion = $FrameworkVersion
    createdFiles = @($templateMap.Values)
    nextAction = 'AI session completes project-specific facts, validates repo-local FULL_COLD_RECOVERY, then reports READY or NEEDS_INPUT.'
}
