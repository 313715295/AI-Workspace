[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][ValidateSet('STATUS','DIFF','INDEX')][string]$Operation,
    [Parameter(Mandatory = $true)][string[]]$AllowPath,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [string]$RepositoryId = 'PROJECT',
    [switch]$IncludeRoutineExcluded
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8Strict = New-Object Text.UTF8Encoding($false, $true)

function Get-FileIdentity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return $bytes.Length.ToString() + '|' + ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function ConvertTo-RoutinePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) { throw 'ROUTINE_PATH_EMPTY_OR_WHITESPACE' }
    $path = $Value.Replace('\','/')
    if ([regex]::IsMatch($path,'[<>"|?*]')) { throw 'ROUTINE_PATH_LITERAL_METACHAR' }
    if ([IO.Path]::IsPathRooted($path) -or $path.StartsWith('/') -or $path.Contains(':')) { throw 'ROUTINE_PATH_ROOTED' }
    if (-not [string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw 'ROUTINE_PATH_NOT_NFC' }
    $parts = $path.Split('/')
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..')) { throw 'ROUTINE_PATH_COMPONENT' }
        if ($part.EndsWith('.') -or $part.EndsWith(' ') -or [regex]::IsMatch($part,'[\x00-\x1F]')) { throw 'ROUTINE_PATH_COMPONENT' }
        if ($part.Split('.')[0] -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw 'ROUTINE_PATH_RESERVED' }
    }
    return [string]::Join('/',$parts)
}

function Read-StrictConfig([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'PROJECT_CONFIG_BOM' }
    try { $raw = $utf8Strict.GetString($bytes) } catch { throw 'PROJECT_CONFIG_UTF8' }
    if ($raw.Contains([char]0) -or $raw.Contains([char]0xFFFD) -or $raw.Contains("`r") -or -not $raw.EndsWith("`n")) { throw 'PROJECT_CONFIG_TEXT_FORMAT' }
    return $raw
}

function Assert-FrameworkCapabilities($Capabilities,[string]$Raw) {
    if (-not ($Capabilities -is [pscustomobject])) { throw 'FRAMEWORK_CAPABILITIES_TYPE' }
    $names = @($Capabilities.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { return }
    if ($names.Count -ne 1 -or $names[0] -cne 'KNOWLEDGE_REFERENCE' -or [regex]::Matches($Raw,'"KNOWLEDGE_REFERENCE"\s*:').Count -ne 1) { throw 'FRAMEWORK_CAPABILITIES_UNKNOWN_OR_DUPLICATE' }
    $knowledge = $Capabilities.KNOWLEDGE_REFERENCE
    if (-not ($knowledge -is [pscustomobject])) { throw 'KNOWLEDGE_CAPABILITY_TYPE' }
    $fields = @($knowledge.PSObject.Properties | ForEach-Object { $_.Name })
    if ($fields.Count -eq 1 -and $fields[0] -ceq 'enabled' -and $knowledge.enabled -is [bool] -and -not [bool]$knowledge.enabled) {
        if ([regex]::Matches($Raw,'"enabled"\s*:').Count -ne 1) { throw 'KNOWLEDGE_CAPABILITY_DUPLICATE_FIELD' }
        return
    }
    if ($fields.Count -ne 2 -or $fields -cnotcontains 'enabled' -or $fields -cnotcontains 'indexLocator' -or
        -not ($knowledge.enabled -is [bool]) -or -not [bool]$knowledge.enabled -or
        -not ($knowledge.indexLocator -is [string]) -or
        [regex]::Matches($Raw,'"enabled"\s*:').Count -ne 1 -or [regex]::Matches($Raw,'"indexLocator"\s*:').Count -ne 1) { throw 'KNOWLEDGE_CAPABILITY_FIELDS' }
    $null = ConvertTo-RoutinePath ([string]$knowledge.indexLocator)
}

function Assert-GitTop([string]$Root,[string]$Prefix) {
    $gitTopOutput = @(& git -C $Root rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $gitTopOutput.Count -ne 1) { throw "${Prefix}_GIT_TOP_UNAVAILABLE" }
    $gitTop = [IO.Path]::GetFullPath([string]$gitTopOutput[0]).TrimEnd('\')
    if (-not $gitTop.Equals($Root,[StringComparison]::OrdinalIgnoreCase)) { throw "${Prefix}_ROOT_NOT_GIT_TOP" }
}

function Write-Unverified([string]$Reason,[bool]$Launched=$false) {
    [pscustomobject][ordered]@{ status='UNVERIFIED'; operation=$Operation; repositoryId=$RepositoryId; reason=$Reason; launched=$Launched } | ConvertTo-Json -Compress
    exit 3
}

try {
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw 'PROJECT_ROOT_MISSING' }
    $controlRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).ProviderPath).TrimEnd('\')
    if ((Get-Item -LiteralPath $controlRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'PROJECT_ROOT_REPARSE' }
    Assert-GitTop $controlRoot 'PROJECT'

    $configPath = Join-Path $controlRoot '.ai-workspace\project.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'PROJECT_CONFIG_MISSING' }
    if ((Get-Item -LiteralPath $configPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'PROJECT_CONFIG_REPARSE' }
    if ((Get-FileIdentity $configPath) -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
    $raw = Read-StrictConfig $configPath
    try { $config = $raw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
    if (-not ($config -is [pscustomobject]) -or -not (Test-JsonInteger $config.schemaVersion)) { throw 'PROJECT_CONFIG_VALUES' }

    $root = $controlRoot
    $selectedExclusions = @()
    if ([int]$config.schemaVersion -eq 3) {
        if ($RepositoryId -cne 'PROJECT') { throw 'REPOSITORY_ID_REQUIRES_MAINTENANCE_LAYOUT' }
        $expectedFields = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','routineExcludedPaths','frameworkCapabilities')
        $names = @($config.PSObject.Properties.Name)
        if ($names.Count -ne $expectedFields.Count -or @($expectedFields | Where-Object { $_ -cnotin $names }).Count -ne 0) { throw 'PROJECT_CONFIG_FIELDS' }
        foreach ($name in $expectedFields) { if ([regex]::Matches($raw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw 'PROJECT_CONFIG_DUPLICATE_FIELD' } }
        if (-not ($config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.id) -or
            -not ($config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.displayName) -or
            -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne 'repo-local' -or
            -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
            -not ($config.frameworkVersion -is [string]) -or [string]$config.frameworkVersion -cne '1.10.0' -or
            -not ($config.routineExcludedPaths -is [System.Array])) { throw 'PROJECT_CONFIG_VALUES' }
        Assert-FrameworkCapabilities $config.frameworkCapabilities $raw
        $selectedExclusions = @($config.routineExcludedPaths)
    } elseif ([int]$config.schemaVersion -eq 4) {
        $resolver = Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
        $resolverArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$resolver,'-ControlRepositoryPath',$controlRoot,'-ExpectedProjectConfigIdentity',$ExpectedProjectConfigIdentity,'-AsJson')
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $resolverOutput = @(& powershell.exe @resolverArguments 2>&1 | ForEach-Object { [string]$_ }); $resolverCode = $LASTEXITCODE }
        finally { $ErrorActionPreference = $oldPreference }
        if ($resolverCode -ne 0 -or $resolverOutput.Count -ne 1) { throw ('MAINTENANCE_TARGET_RESOLUTION_FAILED|' + ($resolverOutput -join ';')) }
        try { $resolved = $resolverOutput[0] | ConvertFrom-Json } catch { throw 'MAINTENANCE_TARGET_RESOLUTION_JSON' }
        if ($RepositoryId -ceq 'CONTROL') {
            $root = $controlRoot
            $selectedExclusions = @($config.routineExcludedPaths)
        } elseif ($RepositoryId -ceq [string]$resolved.targetRepositoryId) {
            $root = [IO.Path]::GetFullPath([string]$resolved.targetRoot).TrimEnd('\')
            $selectedExclusions = @($config.frameworkTarget.routineExcludedPaths)
        } else {
            throw 'REPOSITORY_ID_UNKNOWN'
        }
    } else {
        throw 'PROJECT_CONFIG_SCHEMA_UNSUPPORTED'
    }

    $allow = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($pathValue in $AllowPath) { if (-not $allow.Add((ConvertTo-RoutinePath $pathValue))) { throw 'ALLOW_PATH_DUPLICATE' } }
    if ($allow.Count -eq 0) { throw 'ALLOW_PATH_EMPTY' }
    $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($pathValue in $selectedExclusions) {
        if (-not ($pathValue -is [string])) { throw 'ROUTINE_EXCLUSION_TYPE' }
        if (-not $excluded.Add((ConvertTo-RoutinePath ([string]$pathValue)))) { throw 'ROUTINE_EXCLUSION_DUPLICATE' }
    }
    if ($IncludeRoutineExcluded) {
        foreach ($path in $allow) { if (-not $excluded.Contains($path)) { throw 'EXCLUDED_OVERRIDE_MUST_BE_EXACT' } }
    }

    $pathspecs = @($allow | Sort-Object | ForEach-Object { ':(top,literal)' + $_ })
    if (-not $IncludeRoutineExcluded) { $pathspecs += @($excluded | Sort-Object | ForEach-Object { ':(top,exclude,literal)' + $_ }) }
    $emptyExcludes = '.git/info/ai-workspace-empty-excludes-v1'
    if (Test-Path -LiteralPath (Join-Path $root $emptyExcludes)) { Write-Unverified 'RESERVED_EXCLUDES_PATH_EXISTS' }
    $arguments = switch ($Operation) {
        'STATUS' { @('-C',$root,'-c',('core.excludesFile='+$emptyExcludes),'-c','status.renames=false','status','--no-renames','--porcelain=v1','--untracked-files=all','--') + $pathspecs }
        'DIFF' { @('-C',$root,'-c',('core.excludesFile='+$emptyExcludes),'-c','diff.renames=false','diff','--no-renames','--no-ext-diff','--') + $pathspecs }
        'INDEX' { @('-C',$root,'-c',('core.excludesFile='+$emptyExcludes),'-c','diff.renames=false','diff','--cached','--no-renames','--name-status','--') + $pathspecs }
    }
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& git @arguments 2>&1 | ForEach-Object { [string]$_ }); $gitExit = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previousErrorAction }
    if ($gitExit -ne 0) { Write-Unverified ('GIT_COMMAND_FAILED|' + $gitExit) $true }
    if (-not $IncludeRoutineExcluded) {
        foreach ($line in $output) {
            foreach ($path in $excluded) {
                if ([string]$line -match [regex]::Escape($path)) { Write-Unverified 'ROUTINE_EXCLUSION_OUTPUT_DETECTED' $true }
            }
        }
    }
    [pscustomobject][ordered]@{ status='VERIFIED'; operation=$Operation; repositoryId=$RepositoryId; launched=$true; paths=@($allow | Sort-Object); output=@($output) } | ConvertTo-Json -Depth 5 -Compress
    exit 0
} catch {
    Write-Unverified ([string]$_.Exception.Message)
}
