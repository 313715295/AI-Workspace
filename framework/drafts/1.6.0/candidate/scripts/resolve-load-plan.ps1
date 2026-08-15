[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CONTROLLER','DOMAIN_OWNER','EXECUTOR','REVIEWER','FRAMEWORK_MAINTAINER')]
    [string]$Role,

    [Parameter(Mandatory = $true)]
    [ValidateSet('MICRO','STANDARD','CRITICAL')]
    [string]$Profile,

    [Parameter(Mandatory = $true)]
    [ValidateSet('DISCOVER','PLAN','IMPLEMENT','VERIFY','REVIEW','GIT','EXTERNAL','RECOVER')]
    [string[]]$Phase,

    [ValidateSet('CODEX','GENERIC')]
    [string]$HostName = 'GENERIC',

    [switch]$AllowDraftCandidate,

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$versionRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $versionRoot 'LOAD_MANIFEST.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json

if ($manifest.frameworkVersion -cne '1.6.0') {
    throw 'LOAD_MANIFEST_VERSION_MISMATCH'
}
if ($manifest.lifecycle -cne 'STABLE' -and -not ($AllowDraftCandidate -and $manifest.lifecycle -ceq 'DRAFT')) {
    throw 'LOAD_MANIFEST_NOT_CONSUMABLE'
}

$selected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($item in @($manifest.core)) { [void]$selected.Add([string]$item) }
foreach ($item in @($manifest.roles.$Role)) { [void]$selected.Add([string]$item) }
foreach ($item in @($manifest.profiles.$Profile)) { [void]$selected.Add([string]$item) }
foreach ($phaseName in $Phase) {
    foreach ($item in @($manifest.phases.$phaseName)) { [void]$selected.Add([string]$item) }
}
foreach ($item in @($manifest.hosts.$HostName)) { [void]$selected.Add([string]$item) }

$result = @()
foreach ($relativePath in @($manifest.order)) {
    $relative = [string]$relativePath
    if (-not $selected.Contains($relative)) { continue }
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..')) {
        throw "LOAD_PATH_INVALID|$relative"
    }
    $fullPath = Join-Path $versionRoot $relative
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "LOAD_MODULE_MISSING|$relative"
    }
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
    frameworkVersion = '1.6.0'
    lifecycle = [string]$manifest.lifecycle
    role = $Role
    profile = $Profile
    phases = @($Phase)
    host = $HostName
    modules = @($result)
    totalBytes = [long](($result | Measure-Object -Property bytes -Sum).Sum)
    estimatedTokens = [int][Math]::Ceiling((($result | Measure-Object -Property bytes -Sum).Sum) / 4.0)
}

if ($AsJson) {
    $output | ConvertTo-Json -Depth 6
} else {
    Write-Output ('PASS|load-plan|role=' + $Role + '|profile=' + $Profile + '|phases=' + ($Phase -join ',') + '|host=' + $HostName + '|modules=' + $result.Count + '|paths=' + (@($result | ForEach-Object { $_.path }) -join '|') + '|bytes=' + $output.totalBytes + '|estimatedTokens=' + $output.estimatedTokens)
}
