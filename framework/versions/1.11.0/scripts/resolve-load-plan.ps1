[CmdletBinding()]
param(
    [string]$TaskPath,

    [ValidateSet('CONTROLLER','DOMAIN_OWNER','EXECUTOR','REVIEWER','FRAMEWORK_MAINTAINER')]
    [string]$Role,

    [ValidateSet('MICRO','STANDARD','CRITICAL')]
    [string]$Profile,

    [ValidateSet('DISCOVER','PLAN','IMPLEMENT','VERIFY','REVIEW','GIT','EXTERNAL','RECOVER')]
    [string[]]$Phase,

    [switch]$IncludeRecovery,

    [ValidateSet('CODEX','GENERIC')]
    [string]$HostName = 'GENERIC',

    [ValidateSet('REPO_LOCAL','FRAMEWORK_MAINTENANCE_SIBLING')]
    [string]$Topology = 'REPO_LOCAL',

    [string[]]$Capability = @(),

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8Strict = New-Object Text.UTF8Encoding($false, $true)

function Read-StrictTask([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'LOAD_TASK_MISSING' }
    $item = Get-Item -LiteralPath $Path -Force
    if (([IO.FileAttributes]$item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'LOAD_TASK_REPARSE' }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'LOAD_TASK_BOM' }
    try { $text = $utf8Strict.GetString($bytes) } catch { throw 'LOAD_TASK_UTF8' }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { throw 'LOAD_TASK_TEXT_FORMAT' }
    return $text
}

function Test-SetEquals([string[]]$Left,[string[]]$Right) {
    $leftSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $rightSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in @($Left)) { if (-not $leftSet.Add([string]$item)) { return $false } }
    foreach ($item in @($Right)) { if (-not $rightSet.Add([string]$item)) { return $false } }
    return $leftSet.SetEquals($rightSet)
}

function Resolve-ExplicitPhases([string[]]$Requested,[bool]$AddRecovery) {
    if ($null -eq $Requested -or @($Requested).Count -eq 0) { throw 'LOAD_EXPLICIT_PHASE_REQUIRED' }
    $phaseSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in @($Requested)) { if (-not $phaseSet.Add([string]$item)) { throw 'LOAD_PHASE_DUPLICATE' } }
    if ($AddRecovery) { [void]$phaseSet.Add('RECOVER') }
    $workPhases = @($phaseSet | Where-Object { $_ -cne 'RECOVER' })
    if ($workPhases.Count -gt 1) { throw 'LOAD_MULTIPLE_WORK_PHASES' }
    $ordered = New-Object 'System.Collections.Generic.List[string]'
    if ($phaseSet.Contains('RECOVER')) { $ordered.Add('RECOVER') }
    if ($workPhases.Count -eq 1) { $ordered.Add([string]$workPhases[0]) }
    if ($ordered.Count -eq 0) { throw 'LOAD_EXPLICIT_PHASE_REQUIRED' }
    return ,@($ordered)
}

$resolvedRole = ''
$resolvedProfile = ''
$resolvedPhases = @()
$workPhase = ''
$routeSource = ''
$evidenceCeiling = 'NONE'
$resolvedTaskPath = ''

if (-not [string]::IsNullOrWhiteSpace($TaskPath)) {
    $taskText = Read-StrictTask $TaskPath
    $resolvedTaskPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TaskPath).ProviderPath)
    $schemaMatches = [regex]::Matches($taskText, '(?m)^- Task schema:\s*(?<version>[^\s]+)\s*$')
    if ($schemaMatches.Count -ne 1) { throw 'LOAD_TASK_SCHEMA' }
    $taskSchema = $schemaMatches[0].Groups['version'].Value
    $profileMatches = [regex]::Matches($taskText, '(?m)^- Range summary:\s*profile=(?<value>MICRO|STANDARD|CRITICAL);')
    if ($profileMatches.Count -ne 1) { throw 'LOAD_TASK_PROFILE' }
    $taskProfile = $profileMatches[0].Groups['value'].Value
    $routeLines = [regex]::Matches($taskText, '(?m)^- Work route:\s*.+$')
    $routeMatches = [regex]::Matches($taskText, '(?m)^- Work route:\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')

    if ($routeLines.Count -eq 1 -and $routeMatches.Count -eq 1) {
        $resolvedRole = $routeMatches[0].Groups['role'].Value
        $resolvedProfile = $taskProfile
        $workPhase = $routeMatches[0].Groups['phase'].Value
        $resolvedPhases = if ($IncludeRecovery -and $workPhase -cne 'RECOVER') { @('RECOVER',$workPhase) } else { @($workPhase) }
        $routeSource = 'TASK_CARD'
        if ($PSBoundParameters.ContainsKey('Role') -and $Role -cne $resolvedRole) { throw 'LOAD_TASK_ROLE_DRIFT' }
        if ($PSBoundParameters.ContainsKey('Profile') -and $Profile -cne $resolvedProfile) { throw 'LOAD_TASK_PROFILE_DRIFT' }
        if ($PSBoundParameters.ContainsKey('Phase') -and -not (Test-SetEquals @($Phase) @($resolvedPhases))) { throw 'LOAD_TASK_PHASE_DRIFT' }
    } else {
        if ($routeLines.Count -ne 0 -or $routeMatches.Count -ne 0) { throw 'LOAD_TASK_WORK_ROUTE_FORMAT' }
        if ($taskSchema -ceq '1.11.0') { throw 'LOAD_TASK_WORK_ROUTE_REQUIRED' }
        if (-not $PSBoundParameters.ContainsKey('Role') -or -not $PSBoundParameters.ContainsKey('Profile') -or -not $PSBoundParameters.ContainsKey('Phase')) { throw 'LOAD_LEGACY_ROUTE_INPUT_REQUIRED' }
        if ($Profile -cne $taskProfile) { throw 'LOAD_TASK_PROFILE_DRIFT' }
        $resolvedRole = $Role
        $resolvedProfile = $Profile
        $resolvedPhases = Resolve-ExplicitPhases @($Phase) ([bool]$IncludeRecovery)
        $nonRecovery = @($resolvedPhases | Where-Object { $_ -cne 'RECOVER' })
        $workPhase = if ($nonRecovery.Count -eq 1) { [string]$nonRecovery[0] } else { 'RECOVER' }
        $routeSource = 'LEGACY_LOAD_CONTEXT'
        $evidenceCeiling = 'ROLE_PHASE_EXPLICITLY_INFERRED_FROM_LEGACY_TASK'
    }
} else {
    if (-not $PSBoundParameters.ContainsKey('Role') -or -not $PSBoundParameters.ContainsKey('Profile') -or -not $PSBoundParameters.ContainsKey('Phase')) { throw 'LOAD_TASK_OR_EXPLICIT_ROUTE_REQUIRED' }
    $resolvedRole = $Role
    $resolvedProfile = $Profile
    $resolvedPhases = Resolve-ExplicitPhases @($Phase) ([bool]$IncludeRecovery)
    $nonRecovery = @($resolvedPhases | Where-Object { $_ -cne 'RECOVER' })
    $workPhase = if ($nonRecovery.Count -eq 1) { [string]$nonRecovery[0] } else { 'RECOVER' }
    $routeSource = 'EXPLICIT_NO_TASK'
    $evidenceCeiling = 'NO_TASK_BINDING'
}

$versionRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $versionRoot 'LOAD_MANIFEST.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json

if ($manifest.frameworkVersion -cne '1.11.0' -or $manifest.lifecycle -cne 'STABLE') { throw 'LOAD_MANIFEST_NOT_STABLE_1_11_0' }

$selected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($item in @($manifest.core)) { [void]$selected.Add([string]$item) }
foreach ($item in @($manifest.topologies.$Topology)) { [void]$selected.Add([string]$item) }
foreach ($item in @($manifest.roles.$resolvedRole)) { [void]$selected.Add([string]$item) }
foreach ($item in @($manifest.profiles.$resolvedProfile)) { [void]$selected.Add([string]$item) }
foreach ($phaseName in $resolvedPhases) { foreach ($item in @($manifest.phases.$phaseName)) { [void]$selected.Add([string]$item) } }
foreach ($item in @($manifest.hosts.$HostName)) { [void]$selected.Add([string]$item) }

$capabilitySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$knownCapabilities = @($manifest.capabilities.PSObject.Properties.Name)
foreach ($capabilityNameValue in @($Capability)) {
    if (-not ($capabilityNameValue -is [string]) -or [string]::IsNullOrWhiteSpace([string]$capabilityNameValue)) { throw 'LOAD_CAPABILITY_EMPTY' }
    $capabilityName = [string]$capabilityNameValue
    if (-not $capabilitySet.Add($capabilityName)) { throw "LOAD_CAPABILITY_DUPLICATE|$capabilityName" }
    if ($knownCapabilities -cnotcontains $capabilityName) { throw "LOAD_CAPABILITY_UNKNOWN|$capabilityName" }
    $definition = $manifest.capabilities.$capabilityName
    if (@($definition.hosts) -cnotcontains $HostName) { throw "LOAD_CAPABILITY_HOST_UNSUPPORTED|$capabilityName|$HostName" }
    foreach ($item in @($definition.modules)) { [void]$selected.Add([string]$item) }
}

$result = @()
foreach ($relativePath in @($manifest.order)) {
    $relative = [string]$relativePath
    if (-not $selected.Contains($relative)) { continue }
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..')) { throw "LOAD_PATH_INVALID|$relative" }
    $fullPath = Join-Path $versionRoot $relative
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "LOAD_MODULE_MISSING|$relative" }
    $bytes = (Get-Item -LiteralPath $fullPath).Length
    $result += [pscustomobject]@{
        path = $relative.Replace('\','/')
        bytes = $bytes
        estimatedTokens = [int][Math]::Ceiling($bytes / 4.0)
    }
}

if ($result.Count -ne $selected.Count) {
    $ordered = @($result | ForEach-Object { $_.path })
    $missing = @($selected | Where-Object { $_.Replace('\','/') -notin $ordered })
    throw ('LOAD_ORDER_INCOMPLETE|' + ($missing -join ','))
}

$output = [pscustomobject]@{
    frameworkVersion = '1.11.0'
    lifecycle = 'STABLE'
    routeSource = $routeSource
    evidenceCeiling = $evidenceCeiling
    taskPath = $resolvedTaskPath
    topology = $Topology
    role = $resolvedRole
    profile = $resolvedProfile
    workPhase = $workPhase
    phases = @($resolvedPhases)
    host = $HostName
    capabilities = @($capabilitySet | Sort-Object)
    modules = @($result)
    totalBytes = [long](($result | Measure-Object -Property bytes -Sum).Sum)
    estimatedTokens = [int][Math]::Ceiling((($result | Measure-Object -Property bytes -Sum).Sum) / 4.0)
}

if ($AsJson) {
    $output | ConvertTo-Json -Depth 6
} else {
    Write-Output ('PASS|load-plan|routeSource=' + $routeSource + '|role=' + $resolvedRole + '|profile=' + $resolvedProfile + '|workPhase=' + $workPhase + '|phases=' + ($resolvedPhases -join ',') + '|host=' + $HostName + '|topology=' + $Topology + '|capabilities=' + (@($capabilitySet | Sort-Object) -join ',') + '|modules=' + $result.Count + '|paths=' + (@($result | ForEach-Object { $_.path }) -join '|') + '|bytes=' + $output.totalBytes + '|estimatedTokens=' + $output.estimatedTokens + '|evidenceCeiling=' + $evidenceCeiling)
}
