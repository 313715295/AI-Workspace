[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ControlRepositoryPath,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [switch]$AsJson
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

function Read-StrictUtf8([string]$Path,[string]$Prefix) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "${Prefix}_BOM" }
    try { $text = $utf8Strict.GetString($bytes) } catch { throw "${Prefix}_UTF8" }
    if ($text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or $text.Contains("`r") -or -not $text.EndsWith("`n")) { throw "${Prefix}_TEXT_FORMAT" }
    $cursor=0
    try { Read-JsonValue $text ([ref]$cursor);Skip-JsonWhitespace $text ([ref]$cursor);if ($cursor -ne $text.Length) { throw 'JSON_TRAILING' } }
    catch { throw ($Prefix+'_'+[string]$_.Exception.Message) }
    return $text
}

function ConvertTo-SafeRelativePath([string]$Value,[string]$Prefix) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) { throw "${Prefix}_EMPTY_OR_WHITESPACE" }
    $path = $Value.Replace('\','/')
    if ([regex]::IsMatch($path,'[<>"|?*]') -or [IO.Path]::IsPathRooted($path) -or $path.StartsWith('/') -or $path.Contains(':')) { throw "${Prefix}_ROOTED_OR_META" }
    if (-not [string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw "${Prefix}_NOT_NFC" }
    $parts = $path.Split('/')
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or [regex]::IsMatch($part,'[\x00-\x1F]')) { throw "${Prefix}_COMPONENT" }
        if ($part.Split('.')[0] -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw "${Prefix}_RESERVED" }
    }
    return [string]::Join('/',$parts)
}

function ConvertTo-SafeSibling([string]$Value) {
    $result = ConvertTo-SafeRelativePath $Value 'TARGET_SIBLING'
    if ($result.Contains('/')) { throw 'TARGET_SIBLING_NOT_SINGLE_COMPONENT' }
    return $result
}

function Assert-StrictFields($Object,[string[]]$Expected,[string]$Raw,[string]$Prefix) {
    if (-not ($Object -is [pscustomobject])) { throw "${Prefix}_TYPE" }
    $names = @($Object.PSObject.Properties.Name)
    if ($names.Count -ne $Expected.Count -or @($Expected | Where-Object { $_ -cnotin $names }).Count -ne 0) { throw "${Prefix}_FIELDS" }
    foreach ($name in $Expected) { if ([regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count -lt 1) { throw "${Prefix}_FIELD_MISSING" } }
}

function Assert-StringArray($Value,[string]$Prefix) {
    if (-not ($Value -is [System.Array])) { throw "${Prefix}_TYPE" }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Value)) {
        if (-not ($entry -is [string])) { throw "${Prefix}_ENTRY_TYPE" }
        $path = ConvertTo-SafeRelativePath ([string]$entry) $Prefix
        if (-not $set.Add($path)) { throw "${Prefix}_DUPLICATE" }
    }
}

function Get-LiteralChild([string]$Parent,[string]$Name,[string]$Prefix) {
    $matches = @(Get-ChildItem -LiteralPath $Parent -Force -ErrorAction Stop | Where-Object {
        [string]::Equals([string]$_.Name,$Name,[StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -gt 1) { throw "${Prefix}_AMBIGUOUS" }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Assert-PathComponents([string]$Root,[string]$Relative,[string]$LeafKind,[string]$Prefix) {
    $normalized = ConvertTo-SafeRelativePath $Relative $Prefix
    $current = $Root
    $walked = New-Object 'System.Collections.Generic.List[string]'
    $parts = $normalized.Split('/')
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $part = [string]$parts[$i]
        $walked.Add($part)
        $entry = Get-LiteralChild $current $part $Prefix
        $walkedText = [string]::Join('/',$walked)
        if ($null -eq $entry) { throw ("${Prefix}_MISSING|" + $normalized) }
        if (([IO.FileAttributes]$entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ("${Prefix}_REPARSE|" + $walkedText) }
        $isLast = $i -eq ($parts.Count - 1)
        if (-not $isLast -and -not [bool]$entry.PSIsContainer) { throw ("${Prefix}_COMPONENT_NOT_DIRECTORY|" + $walkedText) }
        if ($isLast -and $LeafKind -ceq 'LEAF' -and [bool]$entry.PSIsContainer) { throw ("${Prefix}_NOT_LEAF|" + $normalized) }
        if ($isLast -and $LeafKind -ceq 'CONTAINER' -and -not [bool]$entry.PSIsContainer) { throw ("${Prefix}_NOT_CONTAINER|" + $normalized) }
        $current = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$entry.FullName))
    }
    return $current
}

function Read-Controller([string]$Path,[string]$Prefix,[string]$ExpectedProjectId,[string]$ExpectedState) {
    $raw = Read-StrictUtf8 $Path $Prefix
    try { $controller = $raw | ConvertFrom-Json } catch { throw "${Prefix}_JSON" }
    $expected = @('schemaVersion','projectId','controllerId','controllerEpoch','state')
    Assert-StrictFields $controller $expected $raw $Prefix
    foreach ($name in $expected) {
        if ([regex]::Matches($raw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw "${Prefix}_DUPLICATE_FIELD" }
    }
    if (-not (Test-JsonInteger $controller.schemaVersion) -or [int]$controller.schemaVersion -ne 1 -or
        -not ($controller.projectId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$controller.projectId) -or
        -not ($controller.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$controller.controllerId) -or
        -not (Test-JsonInteger $controller.controllerEpoch) -or [int64]$controller.controllerEpoch -lt 1 -or
        -not ($controller.state -is [string]) -or [string]$controller.state -cne $ExpectedState) { throw "${Prefix}_VALUES" }
    if (-not [string]::IsNullOrEmpty($ExpectedProjectId) -and [string]$controller.projectId -cne $ExpectedProjectId) { throw "${Prefix}_PROJECT_ID" }
    return $controller
}

try {
    if (-not (Test-Path -LiteralPath $ControlRepositoryPath -PathType Container)) { throw 'CONTROL_ROOT_MISSING' }
    $controlRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ControlRepositoryPath).ProviderPath))
    if ((Get-Item -LiteralPath $controlRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'CONTROL_ROOT_REPARSE' }
    $controlGit = @(& git -C $controlRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $controlGit.Count -ne 1) { throw 'CONTROL_GIT_TOP_UNAVAILABLE' }
    $controlGitRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$controlGit[0]))
    if ([IO.Path]::GetRelativePath($controlGitRoot,$controlRoot) -cne '.') { throw 'CONTROL_ROOT_NOT_GIT_TOP' }

    $configPath = Assert-PathComponents $controlRoot '.ai-workspace/project.json' 'LEAF' 'PROJECT_CONFIG'
    $configIdentity = Get-FileIdentity $configPath
    if ($configIdentity -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
    $raw = Read-StrictUtf8 $configPath 'PROJECT_CONFIG'
    try { $config = $raw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
    $rootFields = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy','frameworkTarget')
    Assert-StrictFields $config $rootFields $raw 'PROJECT_CONFIG'
    $fieldCounts = [ordered]@{
        schemaVersion = 2; id = 1; displayName = 1; controlPlaneLayout = 1; repositoryRoot = 1
        frameworkVersion = 1; frameworkToolBackend = 1; routineExcludedPaths = 2; frameworkCapabilities = 1; frameworkTarget = 1
        processPolicy = 1; locator = 1; repositoryId = 1; siblingDirectory = 1
    }
    foreach ($entry in $fieldCounts.GetEnumerator()) {
        if ([regex]::Matches($raw,'"'+[regex]::Escape([string]$entry.Key)+'"\s*:').Count -ne [int]$entry.Value) { throw 'PROJECT_CONFIG_DUPLICATE_OR_MISSING_FIELD' }
    }
    if (-not (Test-JsonInteger $config.schemaVersion) -or [int]$config.schemaVersion -ne 4 -or
        -not ($config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.id) -or
        -not ($config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.displayName) -or
        -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne 'framework-maintenance-sibling' -or
        -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
        -not ($config.frameworkVersion -is [string]) -or [string]$config.frameworkVersion -cne '1.14.0' -or
        -not ($config.frameworkToolBackend -is [string]) -or [string]$config.frameworkToolBackend -cne 'powershell7' -or
        -not ($config.frameworkCapabilities -is [pscustomobject])) { throw 'PROJECT_CONFIG_VALUES' }
    Assert-StringArray $config.routineExcludedPaths 'CONTROL_ROUTINE_PATH'
    if (@($config.frameworkCapabilities.PSObject.Properties).Count -ne 0) { throw 'FRAMEWORK_CAPABILITIES_UNSUPPORTED_IN_MAINTENANCE_V1' }
    Assert-StrictFields $config.processPolicy @('schemaVersion','locator') ($config.processPolicy|ConvertTo-Json -Depth 5) 'PROCESS_POLICY_LOCATOR'
    if(-not(Test-JsonInteger $config.processPolicy.schemaVersion)-or[int]$config.processPolicy.schemaVersion-ne1-or[string]$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'){throw 'PROCESS_POLICY_LOCATOR_VALUES'}
    $policyPath=Assert-PathComponents $controlRoot '.ai-workspace/process-policy.json' 'LEAF' 'PROCESS_POLICY'
    $policyRaw=Read-StrictUtf8 $policyPath 'PROCESS_POLICY'
    try{$policy=$policyRaw|ConvertFrom-Json}catch{throw 'PROCESS_POLICY_JSON'}
    Assert-StrictFields $policy @('schemaVersion','contractVersion','projectId','rules') $policyRaw 'PROCESS_POLICY'
    if(-not(Test-JsonInteger $policy.schemaVersion)-or[int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne'1.14.0'-or[string]$policy.projectId-cne[string]$config.id-or-not($policy.rules-is[Array])){throw 'PROCESS_POLICY_VALUES'}

    $targetFields = @('repositoryId','siblingDirectory','routineExcludedPaths')
    Assert-StrictFields $config.frameworkTarget $targetFields ($config.frameworkTarget | ConvertTo-Json -Depth 5) 'FRAMEWORK_TARGET'
    if (-not ($config.frameworkTarget.repositoryId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.frameworkTarget.repositoryId) -or [string]$config.frameworkTarget.repositoryId -ceq 'CONTROL') { throw 'TARGET_REPOSITORY_ID' }
    if (-not ($config.frameworkTarget.siblingDirectory -is [string])) { throw 'TARGET_SIBLING_TYPE' }
    $sibling = ConvertTo-SafeSibling ([string]$config.frameworkTarget.siblingDirectory)
    Assert-StringArray $config.frameworkTarget.routineExcludedPaths 'TARGET_ROUTINE_PATH'

    $controllerPath = Assert-PathComponents $controlRoot '.ai-workspace/controller.json' 'LEAF' 'CONTROLLER'
    $controller = Read-Controller $controllerPath 'CONTROLLER' ([string]$config.id) 'CURRENT'

    $parent = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Split-Path -Parent $controlRoot)))
    if ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'WORKSPACE_PARENT_REPARSE' }
    if ($null -ne (Get-LiteralChild $parent '.git' 'WORKSPACE_PARENT_GIT')) { throw 'WORKSPACE_PARENT_GIT_FORBIDDEN' }
    if ($null -ne (Get-LiteralChild $parent '.ai-workspace' 'WORKSPACE_PARENT_CONTROL')) { throw 'WORKSPACE_PARENT_CONTROL_FORBIDDEN' }
    $targetEntry = Get-LiteralChild $parent $sibling 'TARGET_ROOT'
    if ($null -eq $targetEntry) { throw 'TARGET_ROOT_MISSING' }
    if (([IO.FileAttributes]$targetEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'TARGET_ROOT_REPARSE' }
    if (-not [bool]$targetEntry.PSIsContainer) { throw 'TARGET_ROOT_NOT_DIRECTORY' }
    $targetRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$targetEntry.FullName))
    if ([IO.Path]::GetRelativePath($targetRoot,$controlRoot) -ceq '.') { throw 'TARGET_EQUALS_CONTROL' }
    $targetGit = @(& git -C $targetRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $targetGit.Count -ne 1) { throw 'TARGET_GIT_TOP_UNAVAILABLE' }
    $targetGitRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$targetGit[0]))
    if ([IO.Path]::GetRelativePath($targetGitRoot,$targetRoot) -cne '.') { throw 'TARGET_ROOT_NOT_GIT_TOP' }
    foreach ($required in @('README.md','framework/versions/1.14.0/RECOVERY_CORE.md','framework/versions/1.14.0/LOAD_MANIFEST.json','framework/versions/1.14.0/TOOLCHAIN.json','framework/versions/1.14.0/FRAMEWORK_MAINTENANCE.md','AGENTS.md')) {
        $null = Assert-PathComponents $targetRoot $required 'LEAF' 'TARGET_REQUIRED_FILE'
    }
    $targetControlEntry = Get-LiteralChild $targetRoot '.ai-workspace' 'TARGET_CONTROL'
    if ($null -ne $targetControlEntry) {
        if (([IO.FileAttributes]$targetControlEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'TARGET_CONTROL_PLANE_REPARSE|.ai-workspace' }
        throw 'TARGET_CONTROL_PLANE_PRESENT'
    }

    $result = [pscustomobject][ordered]@{
        status = 'PASS'
        layout = 'framework-maintenance-sibling'
        projectId = [string]$config.id
        frameworkVersion = '1.14.0'
        projectConfigIdentity = $configIdentity
        controlRepositoryId = 'CONTROL'
        controlRoot = $controlRoot
        targetRepositoryId = [string]$config.frameworkTarget.repositoryId
        targetRoot = $targetRoot
        controllerId = [string]$controller.controllerId
        controllerEpoch = [int64]$controller.controllerEpoch
        controllerState = [string]$controller.state
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 4 -Compress }
    else { Write-Output ('PASS|framework-maintenance-target|project=' + $result.projectId + '|control=CONTROL|target=' + $result.targetRepositoryId + '|controllerState=' + $result.controllerState) }
    exit 0
} catch {
    Write-Output ('FAIL|framework-maintenance-target|' + [string]$_.Exception.Message)
    exit 2
}
