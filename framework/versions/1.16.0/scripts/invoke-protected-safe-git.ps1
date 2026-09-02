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

if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}
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

function Test-JsonWhitespace([char]$Character) {
    return $Character -eq [char]0x20 -or $Character -eq [char]0x09 -or $Character -eq [char]0x0A -or $Character -eq [char]0x0D
}

function Skip-JsonWhitespace([string]$Text,[ref]$Index) {
    while ($Index.Value -lt $Text.Length -and (Test-JsonWhitespace $Text[$Index.Value])) { $Index.Value++ }
}

function Read-JsonStringToken([string]$Text,[ref]$Index) {
    if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne [char]0x22) { throw 'JSON_STRING' }
    $start=$Index.Value;$cursor=$start+1
    while ($cursor -lt $Text.Length) {
        $character=$Text[$cursor]
        if ([int]$character -lt 0x20) { throw 'JSON_STRING' }
        if ($character -eq [char]0x5C) {
            $cursor++;if ($cursor -ge $Text.Length) { throw 'JSON_STRING' }
            $escape=$Text[$cursor]
            if ($escape -eq [char]0x75) {
                if ($cursor+4 -ge $Text.Length) { throw 'JSON_STRING' }
                for ($offset=1;$offset -le 4;$offset++) { if ($Text[$cursor+$offset] -notmatch '^[0-9A-Fa-f]$') { throw 'JSON_STRING' } }
                $cursor+=5;continue
            }
            if ('"\/bfnrt'.IndexOf($escape) -lt 0) { throw 'JSON_STRING' }
            $cursor++;continue
        }
        if ($character -eq [char]0x22) {
            $cursor++;$token=$Text.Substring($start,$cursor-$start);$Index.Value=$cursor
            try { return [string]($token | ConvertFrom-Json) } catch { throw 'JSON_STRING' }
        }
        $cursor++
    }
    throw 'JSON_STRING'
}

function Read-JsonValue([string]$Text,[ref]$Index) {
    Skip-JsonWhitespace $Text $Index
    if ($Index.Value -ge $Text.Length) { throw 'JSON_VALUE' }
    $character=$Text[$Index.Value]
    if ($character -eq [char]0x22) { $null=Read-JsonStringToken $Text $Index;return }
    if ($character -eq [char]0x7B) { Read-JsonObject $Text $Index;return }
    if ($character -eq [char]0x5B) { Read-JsonArray $Text $Index;return }
    $start=$Index.Value
    while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -notin @([char]0x2C,[char]0x5D,[char]0x7D) -and -not (Test-JsonWhitespace $Text[$Index.Value])) { $Index.Value++ }
    if ($Index.Value -eq $start) { throw 'JSON_VALUE' }
    $token=$Text.Substring($start,$Index.Value-$start)
    if ($token -cnotmatch '^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$') { throw 'JSON_VALUE' }
}

function Read-JsonObject([string]$Text,[ref]$Index) {
    if ($Text[$Index.Value] -ne [char]0x7B) { throw 'JSON_OBJECT' }
    $Index.Value++;Skip-JsonWhitespace $Text $Index
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq [char]0x7D) { $Index.Value++;return }
    while ($Index.Value -lt $Text.Length) {
        $name=Read-JsonStringToken $Text $Index
        if (-not $seen.Add($name)) { throw ('JSON_DUPLICATE_FIELD|'+$name) }
        Skip-JsonWhitespace $Text $Index
        if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne [char]0x3A) { throw 'JSON_OBJECT' }
        $Index.Value++;Read-JsonValue $Text $Index;Skip-JsonWhitespace $Text $Index
        if ($Index.Value -ge $Text.Length) { throw 'JSON_OBJECT' }
        if ($Text[$Index.Value] -eq [char]0x2C) { $Index.Value++;Skip-JsonWhitespace $Text $Index;continue }
        if ($Text[$Index.Value] -eq [char]0x7D) { $Index.Value++;return }
        throw 'JSON_OBJECT'
    }
    throw 'JSON_OBJECT'
}

function Read-JsonArray([string]$Text,[ref]$Index) {
    if ($Text[$Index.Value] -ne [char]0x5B) { throw 'JSON_ARRAY' }
    $Index.Value++;Skip-JsonWhitespace $Text $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq [char]0x5D) { $Index.Value++;return }
    while ($Index.Value -lt $Text.Length) {
        Read-JsonValue $Text $Index;Skip-JsonWhitespace $Text $Index
        if ($Index.Value -ge $Text.Length) { throw 'JSON_ARRAY' }
        if ($Text[$Index.Value] -eq [char]0x2C) { $Index.Value++;Skip-JsonWhitespace $Text $Index;continue }
        if ($Text[$Index.Value] -eq [char]0x5D) { $Index.Value++;return }
        throw 'JSON_ARRAY'
    }
    throw 'JSON_ARRAY'
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
    $cursor=0
    try { Read-JsonValue $raw ([ref]$cursor);Skip-JsonWhitespace $raw ([ref]$cursor);if ($cursor -ne $raw.Length) { throw 'JSON_TRAILING' } }
    catch { throw ('PROJECT_CONFIG_'+[string]$_.Exception.Message) }
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
    $gitTop = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$gitTopOutput[0]))
    if ([IO.Path]::GetRelativePath($gitTop,$Root) -cne '.') { throw "${Prefix}_ROOT_NOT_GIT_TOP" }
}

function Write-Unverified([string]$Reason,[bool]$Launched=$false) {
    [pscustomobject][ordered]@{ status='UNVERIFIED'; operation=$Operation; repositoryId=$RepositoryId; reason=$Reason; launched=$Launched } | ConvertTo-Json -Compress
    exit 3
}

try {
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw 'PROJECT_ROOT_MISSING' }
    $controlRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).ProviderPath))
    if ((Get-Item -LiteralPath $controlRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'PROJECT_ROOT_REPARSE' }

    $configPath = Join-Path $controlRoot '.ai-workspace/project.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'PROJECT_CONFIG_MISSING' }
    if ((Get-Item -LiteralPath $configPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'PROJECT_CONFIG_REPARSE' }
    if ((Get-FileIdentity $configPath) -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
    $raw = Read-StrictConfig $configPath
    try { $config = $raw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
    if (-not ($config -is [pscustomobject]) -or -not (Test-JsonInteger $config.schemaVersion)) { throw 'PROJECT_CONFIG_VALUES' }

    $root = $controlRoot
    $selectedExclusions = @()
    $configSchemaVersion = [int]$config.schemaVersion
    $repoLocalLayout = $config.controlPlaneLayout -is [string] -and [string]$config.controlPlaneLayout -ceq 'repo-local'
    if ($configSchemaVersion -in @(3,4) -and $repoLocalLayout) {
        if ($RepositoryId -cne 'PROJECT') { throw 'REPOSITORY_ID_REQUIRES_MAINTENANCE_LAYOUT' }
        $expectedFields = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities')
        if ($configSchemaVersion -eq 4) { $expectedFields += 'processPolicy' }
        $names = @($config.PSObject.Properties.Name)
        if ($names.Count -ne $expectedFields.Count -or @($expectedFields | Where-Object { $_ -cnotin $names }).Count -ne 0) { throw 'PROJECT_CONFIG_FIELDS' }
        foreach ($name in @($expectedFields | Where-Object { $_ -cne 'schemaVersion' })) { if ([regex]::Matches($raw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw 'PROJECT_CONFIG_DUPLICATE_FIELD' } }
        $expectedSchemaFieldCount = if ($configSchemaVersion -eq 4) { 2 } else { 1 }
        if ([regex]::Matches($raw,'"schemaVersion"\s*:').Count -ne $expectedSchemaFieldCount) { throw 'PROJECT_CONFIG_DUPLICATE_FIELD' }
        if (-not ($config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.id) -or
            -not ($config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.displayName) -or
            -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne 'repo-local' -or
            -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
            -not ($config.frameworkVersion -is [string]) -or [string]$config.frameworkVersion -cne '1.16.0' -or
            -not ($config.frameworkToolBackend -is [string]) -or [string]$config.frameworkToolBackend -cne 'powershell7' -or
            -not ($config.routineExcludedPaths -is [System.Array])) { throw 'PROJECT_CONFIG_VALUES' }
        if ($configSchemaVersion -eq 4) {
            if (-not ($config.processPolicy -is [pscustomobject])) { throw 'PROJECT_CONFIG_PROCESS_POLICY' }
            $policyFields = @($config.processPolicy.PSObject.Properties.Name)
            if ($policyFields.Count -ne 2 -or $policyFields -cnotcontains 'schemaVersion' -or $policyFields -cnotcontains 'locator' -or
                -not (Test-JsonInteger $config.processPolicy.schemaVersion) -or [int]$config.processPolicy.schemaVersion -ne 1 -or
                -not ($config.processPolicy.locator -is [string]) -or [string]$config.processPolicy.locator -cne '.ai-workspace/process-policy.json' -or
                [regex]::Matches($raw,'"locator"\s*:').Count -ne 1) { throw 'PROJECT_CONFIG_PROCESS_POLICY' }
        }
        Assert-FrameworkCapabilities $config.frameworkCapabilities $raw
        $selectedExclusions = @($config.routineExcludedPaths)
    } elseif ($configSchemaVersion -eq 4) {
        $resolver = Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
        $resolverArguments = @('-NoProfile','-NonInteractive','-File',$resolver,'-ControlRepositoryPath',$controlRoot,'-ExpectedProjectConfigIdentity',$ExpectedProjectConfigIdentity,'-AsJson')
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $pwshExecutable = [Environment]::ProcessPath
            if ([string]::IsNullOrWhiteSpace($pwshExecutable)) { throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE' }
            $resolverOutput = @(& $pwshExecutable @resolverArguments 2>&1 | ForEach-Object { [string]$_ }); $resolverCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $oldPreference }
        if ($resolverCode -ne 0 -or $resolverOutput.Count -ne 1) { throw ('MAINTENANCE_TARGET_RESOLUTION_FAILED|' + ($resolverOutput -join ';')) }
        try { $resolved = $resolverOutput[0] | ConvertFrom-Json } catch { throw 'MAINTENANCE_TARGET_RESOLUTION_JSON' }
        if ($RepositoryId -ceq 'CONTROL') {
            $root = $controlRoot
            $selectedExclusions = @($config.routineExcludedPaths)
        } elseif ($RepositoryId -ceq [string]$resolved.targetRepositoryId) {
            $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$resolved.targetRoot))
            $selectedExclusions = @($config.frameworkTarget.routineExcludedPaths)
        } else {
            throw 'REPOSITORY_ID_UNKNOWN'
        }
    } else {
        throw 'PROJECT_CONFIG_SCHEMA_UNSUPPORTED'
    }

    Assert-GitTop $controlRoot 'PROJECT'

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
