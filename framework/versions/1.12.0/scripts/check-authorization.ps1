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
    [string[]]$ObservedAction,

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedPath,

    [string[]]$ObservedIdentity = @(),

    [string]$ControllerControlPath,

    [string]$ObservedRepositoryId,

    [string]$ProjectConfigPath,

    [string]$ExpectedProjectConfigIdentity
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}

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

function Get-FullDirectoryPath([string]$Path) {
    return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
}

function Assert-DirectoryChainWithoutReparse([string]$Root,[string]$Child) {
    $rootPath = Get-FullDirectoryPath $Root
    $childPath = Get-FullDirectoryPath $Child
    $relative = [IO.Path]::GetRelativePath($rootPath,$childPath).Replace('\','/')
    if ($relative -ceq '..' -or $relative.StartsWith('../') -or [IO.Path]::IsPathRooted($relative)) { throw 'GIT_TOP_DOES_NOT_CONTAIN_CWD' }
    $cursor = $rootPath
    if (-not (Test-Path -LiteralPath $cursor -PathType Container)) { throw 'GIT_TOP_MISSING' }
    if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'GIT_TOP_REPARSE' }
    if ($relative -ceq '.') { return }
    foreach ($component in $relative.Split('/')) {
        $cursor = Join-Path $cursor $component
        if (-not (Test-Path -LiteralPath $cursor -PathType Container)) { throw 'CWD_COMPONENT_MISSING' }
        if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'CWD_COMPONENT_REPARSE' }
    }
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

$requiredFields = @('schemaVersion','frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','delegatedGitCloser','actions','exactPaths','objectIdentities','invalidatesOn','projectConfigIdentity')
foreach ($field in $requiredFields) {
    if ($null -eq $package.PSObject.Properties[$field]) { Add-Reason $reasons "FIELD_MISSING_$field" }
}
if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

$baseFields = @('schemaVersion','frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','delegatedGitCloser','actions','exactPaths','objectIdentities','invalidatesOn')
$controllerFields = @('issuerControllerId','issuerControllerEpoch','controllerControlIdentity')
$repositoryFields = @('repositoryId')
$criticalReviewFields = @('candidateWriter','materialContributors')
$criticalReviewPackage = [string]$package.profile -ceq 'CRITICAL' -and 'REVIEW_EXECUTE' -in @($package.actions)
$actualFields = @($package.PSObject.Properties.Name)
$expectedFields = @($baseFields) + @('projectConfigIdentity')
if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') { $expectedFields += $controllerFields }
if ((Test-JsonInteger $package.schemaVersion) -and [int]$package.schemaVersion -eq 2) { $expectedFields += $repositoryFields }
if ($criticalReviewPackage) { $expectedFields += $criticalReviewFields }
if ($actualFields.Count -ne $expectedFields.Count -or @($expectedFields | Where-Object { $_ -cnotin $actualFields }).Count -ne 0) {
    Add-Reason $reasons 'PACKAGE_FIELD_SET'
}

$stringFields = @('frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','projectConfigIdentity')
foreach ($field in $stringFields) {
    if (-not ($package.$field -is [string])) { Add-Reason $reasons "FIELD_TYPE_${field}_STRING" }
}
if (-not (Test-JsonInteger $package.schemaVersion)) { Add-Reason $reasons 'FIELD_TYPE_schemaVersion_INTEGER' }
if (-not ($package.delegatedGitCloser -is [bool])) { Add-Reason $reasons 'FIELD_TYPE_delegatedGitCloser_BOOLEAN' }
foreach ($field in @('actions','exactPaths','objectIdentities','invalidatesOn')) {
    if (-not ($package.$field -is [System.Array])) { Add-Reason $reasons "FIELD_TYPE_${field}_ARRAY" }
}
if ($criticalReviewPackage) {
    if (-not ($package.candidateWriter -is [string]) -or [string]::IsNullOrWhiteSpace([string]$package.candidateWriter)) { Add-Reason $reasons 'FIELD_TYPE_candidateWriter_STRING' }
    if (-not ($package.materialContributors -is [System.Array])) { Add-Reason $reasons 'FIELD_TYPE_materialContributors_ARRAY' }
}
if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

if ([int]$package.schemaVersion -notin @(1,2)) { Add-Reason $reasons 'SCHEMA_VERSION' }
if ([string]$package.frameworkVersion -cne '1.12.0') { Add-Reason $reasons 'FRAMEWORK_VERSION' }
if ([string]$package.projectConfigIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'PROJECT_CONFIG_IDENTITY_FORMAT' }
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

$schema2ProjectId = $null
if ([int]$package.schemaVersion -eq 1) {
    try {
        foreach ($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR')) {
            $value = [Environment]::GetEnvironmentVariable($name,'Process')
            if (-not [string]::IsNullOrEmpty($value)) { throw ('GIT_ENVIRONMENT_OVERRIDE_' + $name) }
        }
        $workingDirectory = Get-FullDirectoryPath (Get-Location).Path
        $gitTopOutput = @(& git -C $workingDirectory rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or $gitTopOutput.Count -ne 1) { throw 'GIT_TOP_UNAVAILABLE' }
        $schema1GitTop = Get-FullDirectoryPath ([string]$gitTopOutput[0])
        Assert-DirectoryChainWithoutReparse $schema1GitTop $workingDirectory
        $schema1ControlPlane = Join-Path $schema1GitTop '.ai-workspace'
        if (-not (Test-Path -LiteralPath $schema1ControlPlane -PathType Container)) { throw 'PROJECT_CONTROL_PLANE_MISSING' }
        if (((Get-Item -LiteralPath $schema1ControlPlane -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PROJECT_CONTROL_PLANE_REPARSE' }
        $schema1ConfigPath = Join-Path $schema1ControlPlane 'project.json'
        if (-not (Test-Path -LiteralPath $schema1ConfigPath -PathType Leaf)) { throw 'PROJECT_CONFIG_MISSING' }
        if (((Get-Item -LiteralPath $schema1ConfigPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PROJECT_CONFIG_REPARSE' }
        if ([string]$package.projectConfigIdentity -cne (Get-FileIdentity $schema1ConfigPath)) { throw 'PROJECT_CONFIG_DRIFT' }
        $schema1ConfigRaw = Read-StrictUtf8 $schema1ConfigPath
        try { $schema1Config = $schema1ConfigRaw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
        $schema1Fields = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities')
        $schema1Names = @($schema1Config.PSObject.Properties.Name)
        if (-not ($schema1Config -is [pscustomobject]) -or $schema1Names.Count -ne $schema1Fields.Count -or @($schema1Fields | Where-Object { $_ -cnotin $schema1Names }).Count -ne 0) { throw 'PROJECT_CONFIG_FIELDS' }
        foreach ($name in $schema1Fields) {
            if ([regex]::Matches($schema1ConfigRaw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw 'PROJECT_CONFIG_DUPLICATE_OR_MISSING_FIELD' }
        }
        if (-not (Test-JsonInteger $schema1Config.schemaVersion) -or [int]$schema1Config.schemaVersion -ne 3 -or
            -not ($schema1Config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$schema1Config.id) -or
            -not ($schema1Config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$schema1Config.displayName) -or
            -not ($schema1Config.controlPlaneLayout -is [string]) -or [string]$schema1Config.controlPlaneLayout -cne 'repo-local' -or
            -not ($schema1Config.repositoryRoot -is [string]) -or [string]$schema1Config.repositoryRoot -cne '..' -or
            -not ($schema1Config.frameworkVersion -is [string]) -or [string]$schema1Config.frameworkVersion -cne '1.12.0' -or
            -not ($schema1Config.frameworkToolBackend -is [string]) -or [string]$schema1Config.frameworkToolBackend -cne 'powershell7' -or
            -not ($schema1Config.routineExcludedPaths -is [System.Array])) { throw 'PROJECT_CONFIG_VALUES' }
        $schema1Exclusions = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($pathValue in @($schema1Config.routineExcludedPaths)) {
            if (-not ($pathValue -is [string])) { throw 'ROUTINE_EXCLUSION_TYPE' }
            if (-not $schema1Exclusions.Add((ConvertTo-RoutinePath ([string]$pathValue)))) { throw 'ROUTINE_EXCLUSION_DUPLICATE' }
        }
        Assert-FrameworkCapabilities $schema1Config.frameworkCapabilities $schema1ConfigRaw
    } catch {
        Add-Reason $reasons ('SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3|' + [string]$_.Exception.Message)
    }
}
if ([int]$package.schemaVersion -eq 2) {
    foreach ($field in $repositoryFields) {
        if ($null -eq $package.PSObject.Properties[$field]) { Add-Reason $reasons "FIELD_MISSING_$field" }
        elseif (-not ($package.$field -is [string])) { Add-Reason $reasons "FIELD_TYPE_${field}_STRING" }
    }
    if ([string]::IsNullOrWhiteSpace([string]$package.repositoryId)) { Add-Reason $reasons 'REPOSITORY_ID_EMPTY' }
    if ([string]$package.repositoryId -cne $ObservedRepositoryId) { Add-Reason $reasons 'REPOSITORY_DRIFT' }
    if ([string]::IsNullOrWhiteSpace($ProjectConfigPath) -or [string]::IsNullOrWhiteSpace($ExpectedProjectConfigIdentity)) {
        Add-Reason $reasons 'PROJECT_CONFIG_BINDING_REQUIRED'
    } else {
        try {
            $normalizedConfigPath = Normalize-RelativePath $ProjectConfigPath
            if ($normalizedConfigPath -cne '.ai-workspace/project.json') { throw 'PROJECT_CONFIG_PATH_NOT_CANONICAL' }
            if (-not (Test-Path -LiteralPath $ProjectConfigPath -PathType Leaf)) { throw 'PROJECT_CONFIG_MISSING' }
            if (((Get-Item -LiteralPath $ProjectConfigPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PROJECT_CONFIG_REPARSE' }
            $actualConfigIdentity = Get-FileIdentity $ProjectConfigPath
            if ([string]$package.projectConfigIdentity -cne $ExpectedProjectConfigIdentity -or $actualConfigIdentity -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
            $configRaw = Read-StrictUtf8 $ProjectConfigPath
            try { $config = $configRaw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
            $configFields = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','frameworkTarget')
            $configNames = @($config.PSObject.Properties.Name)
            if (-not ($config -is [pscustomobject]) -or $configNames.Count -ne $configFields.Count -or @($configFields | Where-Object { $_ -cnotin $configNames }).Count -ne 0) { throw 'PROJECT_CONFIG_FIELDS' }
            $configFieldCounts = [ordered]@{
                schemaVersion = 1; id = 1; displayName = 1; controlPlaneLayout = 1; repositoryRoot = 1
                frameworkVersion = 1; frameworkToolBackend = 1; routineExcludedPaths = 2; frameworkCapabilities = 1; frameworkTarget = 1
                repositoryId = 1; siblingDirectory = 1
            }
            foreach ($entry in $configFieldCounts.GetEnumerator()) {
                if ([regex]::Matches($configRaw,'"'+[regex]::Escape([string]$entry.Key)+'"\s*:').Count -ne [int]$entry.Value) { throw 'PROJECT_CONFIG_DUPLICATE_OR_MISSING_FIELD' }
            }
            if (-not (Test-JsonInteger $config.schemaVersion) -or [int]$config.schemaVersion -ne 4 -or
                -not ($config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.id) -or
                -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne 'framework-maintenance-sibling' -or
                -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
                -not ($config.frameworkVersion -is [string]) -or [string]$config.frameworkVersion -cne '1.12.0' -or
                -not ($config.frameworkToolBackend -is [string]) -or [string]$config.frameworkToolBackend -cne 'powershell7' -or
                -not ($config.frameworkTarget -is [pscustomobject]) -or
                -not ($config.frameworkTarget.repositoryId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.frameworkTarget.repositoryId)) { throw 'PROJECT_CONFIG_VALUES' }
            $targetFields = @('repositoryId','siblingDirectory','routineExcludedPaths')
            $targetNames = @($config.frameworkTarget.PSObject.Properties.Name)
            if ($targetNames.Count -ne $targetFields.Count -or @($targetFields | Where-Object { $_ -cnotin $targetNames }).Count -ne 0) { throw 'FRAMEWORK_TARGET_FIELDS' }
            if ([string]$config.frameworkTarget.repositoryId -ceq 'CONTROL' -or
                -not ($config.frameworkTarget.siblingDirectory -is [string]) -or
                -not ($config.frameworkTarget.routineExcludedPaths -is [System.Array]) -or
                -not ($config.routineExcludedPaths -is [System.Array]) -or
                -not ($config.frameworkCapabilities -is [pscustomobject]) -or
                @($config.frameworkCapabilities.PSObject.Properties).Count -ne 0) { throw 'PROJECT_CONFIG_VALUES' }
            $normalizedSibling = Normalize-RelativePath ([string]$config.frameworkTarget.siblingDirectory)
            if ($normalizedSibling.Contains('/')) { throw 'FRAMEWORK_TARGET_SIBLING_NOT_SINGLE_COMPONENT' }
            $allowedRepositoryIds = @('CONTROL',[string]$config.frameworkTarget.repositoryId)
            if ([string]$package.repositoryId -cnotin $allowedRepositoryIds) { throw 'REPOSITORY_ID_UNKNOWN' }
            $schema2ProjectId = [string]$config.id
        } catch {
            Add-Reason $reasons ([string]$_.Exception.Message)
        }
    }
}

$allowedActions = @('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','BROWSER_RUN','DEVICE_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')
$actions = @($package.actions)
foreach ($actionValue in $actions) {
    if (-not ($actionValue -is [string])) { Add-Reason $reasons 'ACTION_TYPE'; continue }
    $action = [string]$actionValue
    if ($action -cnotin $allowedActions) { Add-Reason $reasons 'ACTION_UNKNOWN' }
}
$observedActions = @($ObservedAction)
if ($observedActions.Count -eq 0) { Add-Reason $reasons 'OBSERVED_ACTION_EMPTY' }
foreach ($action in $observedActions) {
    if ($action -cnotin $allowedActions) { Add-Reason $reasons 'OBSERVED_ACTION_UNKNOWN' }
    elseif ($action -cnotin $actions) { Add-Reason $reasons 'ACTION_NOT_GRANTED' }
}
if ($observedActions.Count -ne @($observedActions | Select-Object -Unique).Count) { Add-Reason $reasons 'OBSERVED_ACTION_DUPLICATE' }
if ($actions.Count -ne @($actions | Select-Object -Unique).Count) { Add-Reason $reasons 'ACTION_DUPLICATE' }
if ([int]$package.schemaVersion -eq 2) {
    if ([string]$package.repositoryId -ceq 'CONTROL' -and @($actions | Where-Object { $_ -in @('SOURCE_WRITE','TEST_WRITE','BROWSER_RUN','DEVICE_RUN') }).Count -gt 0) {
        Add-Reason $reasons 'CONTROL_REPOSITORY_ACTION_DENIED'
    }
    if ([string]$package.repositoryId -cne 'CONTROL' -and 'CONTROL_WRITE' -in $actions) {
        Add-Reason $reasons 'TARGET_REPOSITORY_CONTROL_WRITE_DENIED'
    }
}

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

if ([int]$package.schemaVersion -eq 2) {
    try {
        if ([string]::IsNullOrWhiteSpace($ControllerControlPath)) { throw 'CONTROLLER_PATH_REQUIRED' }
        $normalizedSchema2ControllerPath = Normalize-RelativePath $ControllerControlPath
        if ($normalizedSchema2ControllerPath -cne '.ai-workspace/controller.json') { throw 'CONTROLLER_PATH_NOT_CANONICAL' }
        if (-not (Test-Path -LiteralPath $ControllerControlPath -PathType Leaf)) { throw 'CONTROLLER_MISSING' }
        if (((Get-Item -LiteralPath $ControllerControlPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'CONTROLLER_REPARSE' }
        $schema2ControllerRaw = Read-StrictUtf8 $ControllerControlPath
        try { $schema2Controller = $schema2ControllerRaw | ConvertFrom-Json } catch { throw 'CONTROLLER_JSON' }
        $schema2ControllerExpected = @('schemaVersion','projectId','controllerId','controllerEpoch','state')
        $schema2ControllerNames = @($schema2Controller.PSObject.Properties.Name)
        if (-not ($schema2Controller -is [pscustomobject]) -or $schema2ControllerNames.Count -ne $schema2ControllerExpected.Count -or @($schema2ControllerExpected | Where-Object { $_ -cnotin $schema2ControllerNames }).Count -ne 0) { throw 'CONTROLLER_FIELDS' }
        foreach ($name in $schema2ControllerExpected) { if ([regex]::Matches($schema2ControllerRaw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw 'CONTROLLER_DUPLICATE_FIELD' } }
        if (-not (Test-JsonInteger $schema2Controller.schemaVersion) -or [int]$schema2Controller.schemaVersion -ne 1 -or
            -not ($schema2Controller.projectId -is [string]) -or [string]$schema2Controller.projectId -cne [string]$schema2ProjectId -or
            -not ($schema2Controller.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$schema2Controller.controllerId) -or
            -not (Test-JsonInteger $schema2Controller.controllerEpoch) -or [int64]$schema2Controller.controllerEpoch -lt 1 -or
            -not ($schema2Controller.state -is [string]) -or [string]$schema2Controller.state -cne 'CURRENT') { throw 'CONTROLLER_VALUES' }
    } catch {
        Add-Reason $reasons ([string]$_.Exception.Message)
    }
}

if ([int]$package.schemaVersion -eq 2) {
    try {
        if ([string]::IsNullOrWhiteSpace($ProjectConfigPath) -or [string]::IsNullOrWhiteSpace($ExpectedProjectConfigIdentity)) { throw 'PROJECT_CONFIG_BINDING_REQUIRED' }
        $resolverPath = Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
        if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) { throw 'MAINTENANCE_RESOLVER_MISSING' }
        $configFullPath = [IO.Path]::GetFullPath($ProjectConfigPath)
        $controlPlaneRoot = Split-Path -Parent $configFullPath
        $controlRepositoryRoot = Split-Path -Parent $controlPlaneRoot
        $resolverArguments = @(
            '-NoProfile','-NonInteractive','-File',$resolverPath,
            '-ControlRepositoryPath',$controlRepositoryRoot,
            '-ExpectedProjectConfigIdentity',$ExpectedProjectConfigIdentity,
            '-AsJson'
        )
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $pwshExecutable = [Environment]::ProcessPath
            if ([string]::IsNullOrWhiteSpace($pwshExecutable)) { throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE' }
            $resolverOutput = @(& $pwshExecutable @resolverArguments 2>&1 | ForEach-Object { [string]$_ })
            $resolverCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }
        if ($resolverCode -ne 0 -or $resolverOutput.Count -ne 1) {
            throw ('MAINTENANCE_STEADY_STATE_REQUIRED|' + ($resolverOutput -join ';'))
        }
        try { $resolvedMaintenance = $resolverOutput[0] | ConvertFrom-Json } catch { throw 'MAINTENANCE_RESOLVER_RESULT_JSON' }
        if (-not ($resolvedMaintenance -is [pscustomobject]) -or
            [string]$resolvedMaintenance.status -cne 'PASS' -or
            [string]$resolvedMaintenance.projectId -cne [string]$schema2ProjectId -or
            [string]$resolvedMaintenance.projectConfigIdentity -cne $ExpectedProjectConfigIdentity -or
            [string]$resolvedMaintenance.controlRepositoryId -cne 'CONTROL' -or
            [string]$resolvedMaintenance.controllerId -cne [string]$schema2Controller.controllerId -or
            [int64]$resolvedMaintenance.controllerEpoch -ne [int64]$schema2Controller.controllerEpoch -or
            [string]$resolvedMaintenance.controllerState -cne 'CURRENT') { throw 'MAINTENANCE_RESOLVER_RESULT_DRIFT' }
        if ([string]$package.repositoryId -cne 'CONTROL' -and [string]$package.repositoryId -cne [string]$resolvedMaintenance.targetRepositoryId) {
            throw 'MAINTENANCE_RESOLVER_REPOSITORY_DRIFT'
        }
    } catch {
        Add-Reason $reasons ([string]$_.Exception.Message)
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
    $disqualified = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $null = $disqualified.Add([string]$package.owner)
    $null = $disqualified.Add([string]$package.issuer)
    $null = $disqualified.Add([string]$package.candidateWriter)
    $contributorsValid = $true
    foreach ($contributor in @($package.materialContributors)) {
        if (-not ($contributor -is [string]) -or [string]::IsNullOrWhiteSpace([string]$contributor) -or -not $disqualified.Add([string]$contributor)) {
            Add-Reason $reasons 'MATERIAL_CONTRIBUTOR_SET'
            $contributorsValid = $false
        }
    }
    if ([string]$package.reviewIndependence -cne 'INDEPENDENT' -or -not $contributorsValid -or $disqualified.Contains([string]$package.grantee)) {
        Add-Reason $reasons 'CRITICAL_REVIEW_NOT_INDEPENDENT'
    }
}

$candidateMutationActions = @('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')
if ('REVIEW_EXECUTE' -in $actions -and @($actions | Where-Object { $_ -in $candidateMutationActions }).Count -gt 0) {
    Add-Reason $reasons 'REVIEW_WRITE_ACTION_CONFLICT'
}

$requiredInvalidators = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')
if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') { $requiredInvalidators += 'CONTROLLER_EPOCH_CHANGE' }
if ([int]$package.schemaVersion -eq 2) { $requiredInvalidators += 'REPOSITORY_CHANGE' }
if ($criticalReviewPackage) { $requiredInvalidators += 'CONTRIBUTOR_SET_CHANGE' }
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

foreach ($action in $observedActions) {
    Write-Output ('PASS|task=' + [string]$package.taskId + '|actor=' + $ObservedActor + '|action=' + $action + '|paths=' + $ObservedPath.Count)
}
exit 0
