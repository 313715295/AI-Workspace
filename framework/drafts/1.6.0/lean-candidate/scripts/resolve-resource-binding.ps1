[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TaskPath,
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$AdapterPolicyPath,
    [Parameter(Mandatory = $true)][string]$ExpectedAdapterPolicyIdentity,
    [Parameter(Mandatory = $true)][string]$CapabilityPath,
    [Parameter(Mandatory = $true)][string]$ExpectedCapabilityIdentity,
    [Parameter(Mandatory = $true)][ValidateSet('OWNER_FRONTIER','FOCUSED_HIGH','ROUTINE_BALANCED','MECHANICAL_LOW')][string]$SelectedQuality,
    [string[]]$SelectedTool = @(),
    [Parameter(Mandatory = $true)][ValidateSet('ANY','SAME_CONTEXT','FRESH')][string]$ContextMode,
    [Parameter(Mandatory = $true)][string]$HostName,
    [Parameter(Mandatory = $true)][string]$Phase,
    [Parameter(Mandatory = $true)][string]$ContextIdentity,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$qualityNames = @('MECHANICAL_LOW','ROUTINE_BALANCED','FOCUSED_HIGH','OWNER_FRONTIER')

function Get-Identity([string]$Path) {
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    return $file.Length.ToString() + '|' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-TextIdentity([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
    return $bytes.Length.ToString() + '|' + $hash
}

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cne $Path.Trim()) { throw 'Binding locator is invalid.' }
    $value=$Path.Replace('\','/')
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/') -or -not [string]::Equals($value,$value.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw 'Binding locator is invalid.' }
    foreach($part in $value.Split('/')){if([string]::IsNullOrEmpty($part)-or$part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')){throw 'Binding locator is invalid.'}}
    return $value
}

function Assert-NotReparse([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Binding path cannot contain a reparse point.' }
    }
}

function Write-FreshBinding([string]$Path, [string]$Text) {
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Binding output parent is unavailable.' }
    Assert-NotReparse $parent
    if (Test-Path -LiteralPath $Path) { throw 'Binding output must be fresh.' }
    $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, $normalized, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { throw 'Binding output collision.' }
        [IO.File]::Move($temp, $Path)
        Assert-NotReparse $Path
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Assert-StringArray($Value, [string]$Label) {
    if (-not ($Value -is [System.Array])) { throw "$Label must be an array." }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in @($Value)) {
        if (-not ($item -is [string]) -or [string]::IsNullOrWhiteSpace([string]$item) -or -not $seen.Add([string]$item)) { throw "$Label contains an invalid or duplicate item." }
    }
    return @($seen | Sort-Object)
}

function Read-TaskHeader([string]$Text) {
    $header = [regex]::Match($Text, '\A# (?<id>[A-Za-z0-9][A-Za-z0-9._-]*) (?:\u2014|-) [^\r\n]+(?:\r?\n|\z)')
    $owners = [regex]::Matches($Text, '(?m)^- Owner: (?<value>[^\r\n]+)$')
    if (-not $header.Success) { throw 'Task header must declare exactly one Task ID.' }
    if ($owners.Count -ne 1) { throw 'Task header must declare exactly one Owner.' }
    $owner = $owners[0].Groups['value'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($owner)) { throw 'Task Owner is invalid.' }
    return [pscustomobject]@{ TaskId=$header.Groups['id'].Value; Owner=$owner }
}

$repositoryRoot = [IO.Path]::GetFullPath((Get-Location).ProviderPath).TrimEnd('\')
Assert-NotReparse $repositoryRoot
$taskLocator = Normalize-RelativePath $TaskPath
$policyLocator = Normalize-RelativePath $AdapterPolicyPath
$capabilityLocator = Normalize-RelativePath $CapabilityPath
$outputLocator = Normalize-RelativePath $OutputPath
if ($outputLocator -cnotmatch '^\.tmp/resource-bindings/[A-Za-z0-9][A-Za-z0-9._-]*\.json$') { throw 'Binding output must be a direct fresh JSON file under .tmp/resource-bindings/.' }
if ($outputLocator -cin @($taskLocator,$policyLocator,$capabilityLocator)) { throw 'Binding output collides with an input.' }
$bindingRoot = Join-Path $repositoryRoot '.tmp\resource-bindings'
$tmpRoot = Join-Path $repositoryRoot '.tmp'
if (-not (Test-Path -LiteralPath $tmpRoot)) { New-Item -ItemType Directory -Path $tmpRoot | Out-Null }
Assert-NotReparse $tmpRoot
if (-not (Test-Path -LiteralPath $bindingRoot)) { New-Item -ItemType Directory -Path $bindingRoot | Out-Null }
Assert-NotReparse $bindingRoot
$resolvedOutput = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $outputLocator.Replace('/','\')))
if (-not $resolvedOutput.StartsWith($bindingRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Binding output escapes the designated control temp root.' }

$taskText = Get-Content -LiteralPath $taskLocator -Raw -Encoding utf8
$taskHeader = Read-TaskHeader $taskText
if ([string]$taskHeader.TaskId -cne $TaskId) { throw 'Task ID does not match TaskPath.' }
$matches = [regex]::Matches($taskText, '(?m)^- Resource requirement: (?<value>[^\r\n]+)$')
if ($matches.Count -ne 1) { throw 'Task must contain exactly one Resource requirement field.' }
$rawRequirement = $matches[0].Groups['value'].Value.Trim()
if ($rawRequirement -ceq 'DEFAULT') {
    $requirement = [ordered]@{ mode='DEFAULT'; minimumQuality='ROUTINE_BALANCED'; requiredTools=@(); continuity='ANY' }
}
else {
    try { $parsed = $rawRequirement | ConvertFrom-Json }
    catch { throw 'Non-default Resource requirement must be a single-line JSON object.' }
    if (-not ($parsed -is [pscustomobject])) { throw 'Resource requirement must be an object.' }
    $names = @($parsed.PSObject.Properties.Name)
    foreach ($name in $names) { if ($name -cnotin @('minimumQuality','requiredTools','continuity')) { throw "Unknown resource requirement field: $name" } }
    foreach ($name in @('minimumQuality','requiredTools','continuity')) { if ($name -cnotin $names) { throw "Missing resource requirement field: $name" } }
    if (-not ($parsed.minimumQuality -is [string]) -or [string]$parsed.minimumQuality -cnotin $qualityNames) { throw 'Invalid minimumQuality.' }
    if (-not ($parsed.continuity -is [string]) -or [string]$parsed.continuity -cnotin @('ANY','SAME_CONTEXT','FRESH')) { throw 'Invalid continuity.' }
    $requiredTools = Assert-StringArray $parsed.requiredTools 'requiredTools'
    $requirement = [ordered]@{ mode='EXCEPTION'; minimumQuality=[string]$parsed.minimumQuality; requiredTools=@($requiredTools); continuity=[string]$parsed.continuity }
}
$requirementCanonical = $requirement | ConvertTo-Json -Compress -Depth 10
$requirementIdentity = Get-TextIdentity $requirementCanonical

if ((Get-Identity $AdapterPolicyPath) -cne $ExpectedAdapterPolicyIdentity) { throw 'Adapter policy identity drift.' }
if ((Get-Identity $CapabilityPath) -cne $ExpectedCapabilityIdentity) { throw 'Capability identity drift.' }
try { $policy = Get-Content -LiteralPath $AdapterPolicyPath -Raw -Encoding utf8 | ConvertFrom-Json }
catch { throw 'Adapter policy is invalid JSON.' }
try { $capability = Get-Content -LiteralPath $CapabilityPath -Raw -Encoding utf8 | ConvertFrom-Json }
catch { throw 'Capability set is invalid JSON.' }
foreach ($pair in @(@($policy,'adapter policy'), @($capability,'capability set'))) {
    if (-not ($pair[0] -is [pscustomobject])) { throw "$($pair[1]) must be an object." }
}
if (-not ($policy.schemaVersion -is [int]) -or [int]$policy.schemaVersion -ne 1 -or -not ($policy.host -is [string]) -or [string]$policy.host -cne $HostName -or -not ($policy.policyId -is [string])) { throw 'Adapter policy contract mismatch.' }
if (-not ($capability.schemaVersion -is [int]) -or [int]$capability.schemaVersion -ne 1 -or -not ($capability.host -is [string]) -or [string]$capability.host -cne $HostName) { throw 'Capability contract mismatch.' }
$order = Assert-StringArray $policy.qualityOrder 'qualityOrder'
if (@(Compare-Object -ReferenceObject ($qualityNames | Sort-Object) -DifferenceObject ($order | Sort-Object) -CaseSensitive).Count -ne 0) { throw 'Adapter policy must declare every canonical quality exactly once.' }
$availableQualities = Assert-StringArray $capability.qualities 'qualities'
$availableTools = Assert-StringArray $capability.tools 'tools'
$selectedTools = @($SelectedTool | Sort-Object -Unique)
if ($selectedTools.Count -ne @($SelectedTool).Count) { throw 'Selected tools must be unique.' }
if ($SelectedQuality -cnotin $availableQualities) { throw 'Selected quality is unavailable.' }
$minimumIndex = [Array]::IndexOf($qualityNames, [string]$requirement.minimumQuality)
$selectedIndex = [Array]::IndexOf($qualityNames, $SelectedQuality)
if ($selectedIndex -lt $minimumIndex) { throw 'Silent quality downgrade is forbidden.' }
foreach ($tool in @($requirement.requiredTools)) {
    if ($tool -cnotin $availableTools -or $tool -cnotin $selectedTools) { throw "Required tool is unavailable or not selected: $tool" }
}
foreach ($tool in $selectedTools) { if ($tool -cnotin $availableTools) { throw "Selected tool is unavailable: $tool" } }
if ([string]$requirement.continuity -ceq 'FRESH' -and $ContextMode -cne 'FRESH') { throw 'Fresh context is required.' }
if ([string]$requirement.continuity -ceq 'SAME_CONTEXT' -and $ContextMode -cne 'SAME_CONTEXT') { throw 'Same-context continuity is required.' }
if ([string]::IsNullOrWhiteSpace($ContextIdentity) -or $ContextIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { throw 'Context identity is invalid.' }

$bindingCore = [ordered]@{
    schemaVersion = 1
    taskId = $TaskId
    taskLocator = $taskLocator
    taskIdentity = Get-Identity $taskLocator
    resourceRequirementIdentity = $requirementIdentity
    adapterPolicyLocator = $policyLocator
    adapterPolicyIdentity = $ExpectedAdapterPolicyIdentity
    actualCapabilitySet = [ordered]@{ locator=$capabilityLocator; identity=$ExpectedCapabilityIdentity; qualities=@($availableQualities); tools=@($availableTools) }
    selectedQuality = $SelectedQuality
    selectedTools = @($selectedTools)
    continuity = $ContextMode
    phase = $Phase
    host = $HostName
    contextIdentity = $ContextIdentity
}
$coreCanonical = $bindingCore | ConvertTo-Json -Compress -Depth 20
$digest = (Get-TextIdentity $coreCanonical).Split('|')[1]
$binding = [ordered]@{}
foreach ($entry in $bindingCore.GetEnumerator()) { $binding[$entry.Key] = $entry.Value }
$binding['bindingDigest'] = $digest
$output = $binding | ConvertTo-Json -Depth 20
Write-FreshBinding $resolvedOutput $output
$identity = Get-Identity $resolvedOutput
Write-Output ("PASS|binding=$identity|digest=$digest|requirement=$requirementIdentity")
exit 0
