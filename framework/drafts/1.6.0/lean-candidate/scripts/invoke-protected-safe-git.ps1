[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][ValidateSet('STATUS','DIFF','INDEX')][string]$Operation,
    [Parameter(Mandatory = $true)][string[]]$AllowPath,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Identity([string]$Path) {
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    return $file.Length.ToString() + '|' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cne $Path.Trim()) { throw 'PATH_INVALID' }
    $value = $Path.Replace('\','/')
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/') -or $value -match '[*?\[\]]' -or $value.StartsWith(':(')) { throw 'PATH_INVALID' }
    if (-not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw 'PATH_INVALID' }
    $parts = $value.Split('/')
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw 'PATH_INVALID' }
        $base = $part.Split('.')[0]
        if ($base -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw 'PATH_INVALID' }
    }
    return [string]::Join('/', $parts)
}

function Test-Overlap([string]$A, [string]$B) {
    return $A.Equals($B, [StringComparison]::OrdinalIgnoreCase) -or
        $A.StartsWith($B + '/', [StringComparison]::OrdinalIgnoreCase) -or
        $B.StartsWith($A + '/', [StringComparison]::OrdinalIgnoreCase)
}

function Emit-Unverified([string]$Reason, [string]$ConfigIdentity = 'UNVERIFIED') {
    [ordered]@{ operation=$Operation; status='UNVERIFIED'; reason=$Reason; projectConfigIdentity=$ConfigIdentity } | ConvertTo-Json -Compress
    exit 2
}

try {
    $root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).ProviderPath)
    $rootItem=Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Emit-Unverified 'PROJECT_ROOT_REPARSE' }
    $gitTopOutput=@(& git -C $root rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $gitTopOutput.Count -eq 0) { Emit-Unverified 'GIT_TOPLEVEL_UNVERIFIED' }
    $gitTop=[IO.Path]::GetFullPath([string]$gitTopOutput[-1]).TrimEnd('\')
    if (-not $gitTop.Equals($root.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { Emit-Unverified 'GIT_TOPLEVEL_MISMATCH' }
    $configPath = Join-Path $root '.ai-workspace\project.json'
    $schemaPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'PROJECT_CONFIG_SCHEMA.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf) -or -not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { Emit-Unverified 'CONFIG_UNAVAILABLE' }
    $configIdentity = Get-Identity $configPath
    if ($configIdentity -cne $ExpectedProjectConfigIdentity) { Emit-Unverified 'CONFIG_IDENTITY_DRIFT' }
    $raw = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
    $config = $raw | ConvertFrom-Json
    $requiredTop = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','protectedPaths','frameworkCapabilities')
    if (-not ($config -is [pscustomobject]) -or @($config.PSObject.Properties.Name).Count -ne $requiredTop.Count) { Emit-Unverified 'CONFIG_SCHEMA' $configIdentity }
    foreach ($name in $requiredTop) { if ($name -cnotin @($config.PSObject.Properties.Name)) { Emit-Unverified 'CONFIG_SCHEMA' $configIdentity } }
    if (-not ($config.schemaVersion -is [int]) -or [int]$config.schemaVersion -ne 3 -or [string]$config.controlPlaneLayout -cne 'repo-local' -or [string]$config.repositoryRoot -cne '..') { Emit-Unverified 'CONFIG_SCHEMA' $configIdentity }
    if (-not ($config.protectedPaths -is [System.Array]) -or -not ($config.frameworkCapabilities -is [pscustomobject]) -or @($config.frameworkCapabilities.PSObject.Properties).Count -ne 0) { Emit-Unverified 'CONFIG_SCHEMA' $configIdentity }
    foreach ($name in $requiredTop) { if ([regex]::Matches($raw, '"' + [regex]::Escape($name) + '"\s*:').Count -ne 1) { Emit-Unverified 'CONFIG_DUPLICATE_KEY' $configIdentity } }
    $protected = @()
    $protectedSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($config.protectedPaths)) {
        if (-not ($entry -is [pscustomobject]) -or @($entry.PSObject.Properties.Name).Count -ne 2 -or 'path' -cnotin @($entry.PSObject.Properties.Name) -or 'deny' -cnotin @($entry.PSObject.Properties.Name)) { Emit-Unverified 'CONFIG_SCHEMA' $configIdentity }
        $path = Normalize-RelativePath ([string]$entry.path)
        if (-not $protectedSeen.Add($path) -or -not ($entry.deny -is [System.Array]) -or @($entry.deny).Count -eq 0) { Emit-Unverified 'CONFIG_PROTECTED_COLLISION' $configIdentity }
        $denySeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($deny in @($entry.deny)) {
            if (-not ($deny -is [string]) -or [string]$deny -cnotin @('visibility','read','hash','diff','index','write') -or -not $denySeen.Add([string]$deny)) { Emit-Unverified 'CONFIG_SCHEMA' $configIdentity }
        }
        $protected += [pscustomobject]@{ path=$path; deny=@($denySeen) }
    }
    if ([regex]::Matches($raw, '"path"\s*:').Count -ne $protected.Count -or [regex]::Matches($raw, '"deny"\s*:').Count -ne $protected.Count) { Emit-Unverified 'CONFIG_DUPLICATE_KEY' $configIdentity }
    if ($AllowPath.Count -eq 0 -or $AllowPath.Count -gt 128) { Emit-Unverified 'ALLOWLIST_BOUNDS' $configIdentity }
    $allows = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $AllowPath) {
        $path = Normalize-RelativePath $value
        if (-not $allows.Add($path)) { Emit-Unverified 'ALLOWLIST_DUPLICATE' $configIdentity }
    }
    # Git may inspect index metadata and worktree bytes while producing any of
    # these read-only views.  A deny on any read-side capability therefore
    # excludes the object from the command pathset for every operation.
    $requiredDeny = @('visibility','read','hash','diff','index')
    $applicable = @($protected | Where-Object { @($_.deny | Where-Object { $_ -in $requiredDeny }).Count -gt 0 })
    foreach ($allow in $allows) {
        foreach ($deny in $applicable) { if (Test-Overlap $allow $deny.path) { Emit-Unverified 'PROTECTED_OVERLAP' $configIdentity } }
    }
    if ($PlanOnly) {
        [ordered]@{ operation=$Operation; status='VERIFIED_PLAN'; allowCount=$allows.Count; protectedRuleCount=$applicable.Count; projectConfigIdentity=$configIdentity } | ConvertTo-Json -Compress
        exit 0
    }
    $arguments = @('-C',$root,'-c','core.excludesFile=')
    switch ($Operation) {
        'STATUS' { $arguments += @('status','--porcelain=v1','--untracked-files=all') }
        'DIFF' { $arguments += @('diff','--no-ext-diff','--binary') }
        'INDEX' { $arguments += @('ls-files','--cached','--others','--exclude-standard') }
    }
    $arguments += '--'
    $arguments += @($allows)
    foreach ($deny in $applicable) { $arguments += ":(exclude)$($deny.path)" }
    $output = @(& git @arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { Emit-Unverified 'GIT_COMMAND_FAILED' $configIdentity }
    foreach ($line in $output) {
        foreach ($deny in $applicable) { if ([string]$line -match [regex]::Escape($deny.path)) { Emit-Unverified 'PROTECTED_OUTPUT_DETECTED' $configIdentity } }
    }
    [ordered]@{ operation=$Operation; status='VERIFIED'; projectConfigIdentity=$configIdentity; lines=@($output) } | ConvertTo-Json -Compress -Depth 5
    exit 0
}
catch {
    Emit-Unverified 'POLICY_VALIDATION_FAILED'
}
