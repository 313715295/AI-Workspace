[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [string]$ObservedActor,

    [Parameter(Mandatory = $true)]
    [string]$ObservedTaskId,

    [Parameter(Mandatory = $true)]
    [string]$ObservedOwner,

    [Parameter(Mandatory = $true)]
    [ValidateSet('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','BROWSER_RUN','DEVICE_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')]
    [string]$ObservedAction,

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedPath,

    [string[]]$ObservedIdentity = @(),

    [string]$ControllerControlPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Add-Reason([System.Collections.Generic.List[string]]$Reasons, [string]$Reason) {
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Get-FileIdentity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return $bytes.Length.ToString() + '|' + ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Read-StrictUtf8([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'CONTROLLER_BOM' }
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $encoding.GetString($bytes) } catch { throw 'CONTROLLER_UTF8' }
    if ($text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or $text.Contains("`r") -or -not $text.EndsWith("`n")) { throw 'CONTROLLER_TEXT_FORMAT' }
    return $text
}

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'PATH_EMPTY' }
    if ($Path -cne $Path.Trim()) { throw "PATH_OUTER_WHITESPACE|$Path" }
    $value = $Path.Replace('\','/')
    if (-not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw "PATH_NOT_NFC|$Path" }
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/')) {
        throw "PATH_INVALID|$Path"
    }
    $parts = $value.Split('/')
    if ($parts.Count -eq 0) { throw "PATH_EMPTY|$Path" }
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..')) { throw "PATH_COMPONENT_INVALID|$Path" }
        if ($part.EndsWith('.') -or $part.EndsWith(' ')) { throw "PATH_TRAILING_DOT_OR_SPACE|$Path" }
        if ([regex]::IsMatch($part, '[\x00-\x1F]')) { throw "PATH_CONTROL_CHAR|$Path" }
        $baseName = $part.Split('.')[0]
        if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw "PATH_RESERVED_NAME|$Path" }
    }
    return [string]::Join('/', $parts)
}

$reasons = New-Object 'System.Collections.Generic.List[string]'
$packageText = Get-Content -LiteralPath $PackagePath -Raw -Encoding utf8
if ([IO.Path]::GetExtension($PackagePath) -ieq '.md') {
    $matches = [regex]::Matches($packageText, '(?ms)^```authorization-package[ \t]*\n(?<json>.*?)\n```[ \t]*$')
    if ($matches.Count -ne 1) {
        Write-Output ('FAIL|AUTHORIZATION_PACKAGE_BLOCK_COUNT_' + $matches.Count)
        exit 2
    }
    $packageText = $matches[0].Groups['json'].Value
}
try {
    $package = $packageText | ConvertFrom-Json
} catch {
    Write-Output 'FAIL|PACKAGE_JSON'
    exit 2
}
if ($null -eq $package) {
    Write-Output 'FAIL|PACKAGE_JSON'
    exit 2
}

$requiredFields = @('schemaVersion','frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','delegatedGitCloser','actions','exactPaths','objectIdentities','invalidatesOn')
foreach ($field in $requiredFields) {
    if ($null -eq $package.PSObject.Properties[$field]) { Add-Reason $reasons "FIELD_MISSING_$field" }
}
if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

$baseFields = @('schemaVersion','frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','delegatedGitCloser','actions','exactPaths','objectIdentities','invalidatesOn')
$controllerFields = @('issuerControllerId','issuerControllerEpoch','controllerControlIdentity')
$actualFields = @($package.PSObject.Properties.Name)
$expectedFields = if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') { @($baseFields + $controllerFields) } else { @($baseFields) }
if ($actualFields.Count -ne $expectedFields.Count -or @($expectedFields | Where-Object { $_ -cnotin $actualFields }).Count -ne 0) {
    Add-Reason $reasons 'PACKAGE_FIELD_SET'
}

$stringFields = @('frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence')
foreach ($field in $stringFields) {
    if (-not ($package.$field -is [string])) { Add-Reason $reasons "FIELD_TYPE_${field}_STRING" }
}
if (-not (Test-JsonInteger $package.schemaVersion)) { Add-Reason $reasons 'FIELD_TYPE_schemaVersion_INTEGER' }
if (-not ($package.delegatedGitCloser -is [bool])) { Add-Reason $reasons 'FIELD_TYPE_delegatedGitCloser_BOOLEAN' }
foreach ($field in @('actions','exactPaths','objectIdentities','invalidatesOn')) {
    if (-not ($package.$field -is [System.Array])) { Add-Reason $reasons "FIELD_TYPE_${field}_ARRAY" }
}
if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

if ([int]$package.schemaVersion -ne 1) { Add-Reason $reasons 'SCHEMA_VERSION' }
if ([string]$package.frameworkVersion -cne '1.6.1') { Add-Reason $reasons 'FRAMEWORK_VERSION' }
if ([string]$package.lifecycle -cne 'ACTIVE') { Add-Reason $reasons 'LIFECYCLE_NOT_ACTIVE' }
if ([string]$package.profile -notin @('MICRO','STANDARD','CRITICAL')) { Add-Reason $reasons 'PROFILE' }
if ([string]$package.issuerRole -notin @('PROJECT_CONTROLLER','DOMAIN_OWNER')) { Add-Reason $reasons 'ISSUER_ROLE' }
if ([string]$package.decisionClass -notin @('ROUTINE_LOCAL','PRODUCT_RESULT','MAJOR_ARCHITECTURE','EXTERNAL_ACTION')) { Add-Reason $reasons 'DECISION_CLASS' }
if ([string]$package.grantee -cne $ObservedActor) { Add-Reason $reasons 'GRANTEE_DRIFT' }
if ([string]$package.taskId -cne $ObservedTaskId) { Add-Reason $reasons 'TASK_DRIFT' }
if ([string]$package.owner -cne $ObservedOwner) { Add-Reason $reasons 'OWNER_DRIFT' }
if ([string]::IsNullOrWhiteSpace([string]$package.taskId) -or [string]::IsNullOrWhiteSpace([string]$package.owner)) { Add-Reason $reasons 'TASK_OR_OWNER_EMPTY' }
if ([string]::IsNullOrWhiteSpace([string]$package.issuer)) { Add-Reason $reasons 'ISSUER_EMPTY' }
if ([string]::IsNullOrWhiteSpace([string]$package.grantee)) { Add-Reason $reasons 'GRANTEE_EMPTY' }

$allowedActions = @('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','BROWSER_RUN','DEVICE_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')
$actions = @($package.actions)
foreach ($actionValue in $actions) {
    if (-not ($actionValue -is [string])) { Add-Reason $reasons 'ACTION_TYPE'; continue }
    $action = [string]$actionValue
    if ($action -cnotin $allowedActions) { Add-Reason $reasons 'ACTION_UNKNOWN' }
}
if ($ObservedAction -cnotin $actions) { Add-Reason $reasons 'ACTION_NOT_GRANTED' }
if ($actions.Count -ne @($actions | Select-Object -Unique).Count) { Add-Reason $reasons 'ACTION_DUPLICATE' }

$externalActions = @('PUSH','EXTERNAL','DEVICE_RUN')
$requiresUser = [string]$package.decisionClass -ne 'ROUTINE_LOCAL' -or @($actions | Where-Object { $_ -in $externalActions }).Count -gt 0
if ($requiresUser -and ([string]::IsNullOrWhiteSpace([string]$package.userConfirmation) -or [string]$package.userConfirmation -ceq 'NOT_REQUIRED')) {
    Add-Reason $reasons 'USER_CONFIRMATION_REQUIRED'
}
if (-not $requiresUser -and [string]$package.userConfirmation -cne 'NOT_REQUIRED') {
    Add-Reason $reasons 'ROUTINE_USER_CONFIRMATION_SHOULD_NOT_BE_REQUIRED'
}

if ([string]$package.issuerRole -ceq 'DOMAIN_OWNER') {
    if ([string]$package.issuer -cne [string]$package.owner) { Add-Reason $reasons 'DOMAIN_OWNER_MUST_OWN_TASK' }
    if (@($actions | Where-Object { $_ -in @('PUSH','EXTERNAL') }).Count -gt 0) { Add-Reason $reasons 'DOMAIN_OWNER_EXTERNAL_DENIED' }
    if (@($actions | Where-Object { $_ -in @('GIT_STAGE','GIT_COMMIT') }).Count -gt 0 -and -not [bool]$package.delegatedGitCloser) {
        Add-Reason $reasons 'DOMAIN_OWNER_GIT_NOT_DELEGATED'
    }
}

if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') {
    foreach ($field in $controllerFields) {
        if ($null -eq $package.PSObject.Properties[$field]) { Add-Reason $reasons "FIELD_MISSING_$field" }
    }
    if ($null -ne $package.PSObject.Properties['issuerControllerId'] -and -not ($package.issuerControllerId -is [string])) { Add-Reason $reasons 'FIELD_TYPE_issuerControllerId_STRING' }
    if ($null -ne $package.PSObject.Properties['issuerControllerEpoch'] -and -not (Test-JsonInteger $package.issuerControllerEpoch)) { Add-Reason $reasons 'FIELD_TYPE_issuerControllerEpoch_INTEGER' }
    if ($null -ne $package.PSObject.Properties['controllerControlIdentity'] -and -not ($package.controllerControlIdentity -is [string])) { Add-Reason $reasons 'FIELD_TYPE_controllerControlIdentity_STRING' }
    try {
        if ([string]::IsNullOrWhiteSpace($ControllerControlPath)) { throw 'CONTROLLER_PATH_REQUIRED' }
        $normalizedControllerPath = Normalize-RelativePath $ControllerControlPath
        if ($normalizedControllerPath -cne '.ai-workspace/controller.json') { throw 'CONTROLLER_PATH_NOT_CANONICAL' }
        if (-not (Test-Path -LiteralPath $ControllerControlPath -PathType Leaf)) { throw 'CONTROLLER_MISSING' }
        if (((Get-Item -LiteralPath $ControllerControlPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'CONTROLLER_REPARSE' }
        $controllerIdentity = Get-FileIdentity $ControllerControlPath
        if ([string]$package.controllerControlIdentity -cne $controllerIdentity) { throw 'CONTROLLER_OBJECT_DRIFT' }
        $controllerRaw = Read-StrictUtf8 $ControllerControlPath
        try { $controller = $controllerRaw | ConvertFrom-Json } catch { throw 'CONTROLLER_JSON' }
        $controllerExpected = @('schemaVersion','projectId','controllerId','controllerEpoch','state')
        $controllerNames = @($controller.PSObject.Properties.Name)
        if (-not ($controller -is [pscustomobject]) -or $controllerNames.Count -ne $controllerExpected.Count -or @($controllerExpected | Where-Object { $_ -cnotin $controllerNames }).Count -ne 0) { throw 'CONTROLLER_FIELDS' }
        foreach ($name in $controllerExpected) { if ([regex]::Matches($controllerRaw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw 'CONTROLLER_DUPLICATE_FIELD' } }
        if (-not (Test-JsonInteger $controller.schemaVersion) -or [int]$controller.schemaVersion -ne 1 -or
            -not ($controller.projectId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$controller.projectId) -or
            -not ($controller.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$controller.controllerId) -or
            -not (Test-JsonInteger $controller.controllerEpoch) -or [int64]$controller.controllerEpoch -lt 1 -or
            -not ($controller.state -is [string]) -or [string]$controller.state -cne 'CURRENT') { throw 'CONTROLLER_VALUES' }
        if ([string]$package.issuer -cne [string]$controller.controllerId -or
            [string]$package.issuerControllerId -cne [string]$controller.controllerId -or
            [int64]$package.issuerControllerEpoch -ne [int64]$controller.controllerEpoch) { throw 'STALE_CONTROLLER_AUTHORIZATION' }
    } catch {
        Add-Reason $reasons ([string]$_.Exception.Message)
    }
}

if ('REVIEW_EXECUTE' -in $actions -and [string]$package.profile -ceq 'CRITICAL') {
    if ([string]$package.reviewIndependence -cne 'INDEPENDENT' -or [string]$package.grantee -ceq [string]$package.owner -or [string]$package.grantee -ceq [string]$package.issuer) {
        Add-Reason $reasons 'CRITICAL_REVIEW_NOT_INDEPENDENT'
    }
}

$candidateMutationActions = @('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')
if ('REVIEW_EXECUTE' -in $actions -and @($actions | Where-Object { $_ -in $candidateMutationActions }).Count -gt 0) {
    Add-Reason $reasons 'REVIEW_WRITE_ACTION_CONFLICT'
}

$requiredInvalidators = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE')
if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') { $requiredInvalidators += 'CONTROLLER_EPOCH_CHANGE' }
$invalidators = @($package.invalidatesOn)
foreach ($item in $invalidators) {
    if (-not ($item -is [string])) { Add-Reason $reasons 'INVALIDATOR_TYPE' }
}
foreach ($item in $requiredInvalidators) {
    if ($item -cnotin $invalidators) { Add-Reason $reasons "INVALIDATOR_MISSING_$item" }
}

$exact = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in @($package.exactPaths)) {
    if (-not ($path -is [string])) { Add-Reason $reasons 'EXACT_PATH_TYPE'; continue }
    try { $normalized = Normalize-RelativePath ([string]$path) } catch { Add-Reason $reasons 'EXACT_PATH_INVALID'; continue }
    if (-not $exact.Add($normalized)) { Add-Reason $reasons 'EXACT_PATH_DUPLICATE' }
}

$identityMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($package.objectIdentities)) {
    if (-not ($entry -is [pscustomobject]) -or $null -eq $entry.PSObject.Properties['path'] -or $null -eq $entry.PSObject.Properties['identity']) {
        Add-Reason $reasons 'IDENTITY_ENTRY_FIELD_MISSING'
        continue
    }
    if (-not ($entry.path -is [string]) -or -not ($entry.identity -is [string])) {
        Add-Reason $reasons 'IDENTITY_ENTRY_TYPE'
        continue
    }
    try { $path = Normalize-RelativePath ([string]$entry.path) } catch { Add-Reason $reasons 'IDENTITY_PATH_INVALID'; continue }
    $identity = [string]$entry.identity
    if ($identityMap.ContainsKey($path)) { Add-Reason $reasons 'IDENTITY_PATH_DUPLICATE'; continue }
    if ($identity -cne 'NEW' -and $identity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'IDENTITY_FORMAT' }
    $identityMap[$path] = $identity
}
foreach ($path in $exact) {
    if (-not $identityMap.ContainsKey($path)) { Add-Reason $reasons 'IDENTITY_MISSING' }
}
foreach ($path in $identityMap.Keys) {
    if (-not $exact.Contains($path)) { Add-Reason $reasons 'IDENTITY_OUTSIDE_EXACT' }
}

$observedIdentityMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($pair in $ObservedIdentity) {
    $split = $pair.IndexOf('=')
    if ($split -lt 1) { Add-Reason $reasons 'OBSERVED_IDENTITY_FORMAT'; continue }
    try { $path = Normalize-RelativePath $pair.Substring(0, $split) } catch { Add-Reason $reasons 'OBSERVED_IDENTITY_PATH_INVALID'; continue }
    $identity = $pair.Substring($split + 1)
    if ($identity -cne 'NEW' -and $identity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'OBSERVED_IDENTITY_FORMAT'; continue }
    if ($observedIdentityMap.ContainsKey($path)) { Add-Reason $reasons 'OBSERVED_IDENTITY_DUPLICATE'; continue }
    $observedIdentityMap[$path] = $identity
}

$observedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($pathValue in $ObservedPath) {
    try { $path = Normalize-RelativePath $pathValue } catch { Add-Reason $reasons 'OBSERVED_PATH_INVALID'; continue }
    if (-not $observedPaths.Add($path)) { Add-Reason $reasons 'OBSERVED_PATH_DUPLICATE'; continue }
    if (-not $exact.Contains($path)) { Add-Reason $reasons 'OBSERVED_PATH_OUTSIDE_EXACT'; continue }
    if (-not $identityMap.ContainsKey($path)) { Add-Reason $reasons 'OBSERVED_PATH_WITHOUT_IDENTITY'; continue }
    $expectedIdentity = [string]$identityMap[$path]
    if (-not $observedIdentityMap.ContainsKey($path)) { Add-Reason $reasons 'OBSERVED_IDENTITY_MISSING'; continue }
    $observedIdentity = [string]$observedIdentityMap[$path]
    if ($expectedIdentity -ceq 'NEW') {
        if ($observedIdentity -cne 'NEW') { Add-Reason $reasons 'NEW_OBJECT_EXISTS' }
    } elseif ($observedIdentity -cne $expectedIdentity) {
        Add-Reason $reasons 'OBJECT_DRIFT'
    }
}

if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

Write-Output ('PASS|task=' + [string]$package.taskId + '|actor=' + $ObservedActor + '|action=' + $ObservedAction + '|paths=' + $ObservedPath.Count)
exit 0
