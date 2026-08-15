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

    [string]$ResourceBindingPath,

    [string]$ResourceTaskPath,

    [string]$ResourceAdapterPolicyPath,

    [string]$ResourceCapabilityPath,

    [string]$ObservedPhase,

    [string]$ObservedHost,

    [string]$ObservedContextIdentity,

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
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    return $file.Length.ToString() + '|' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-TextSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-TextIdentity([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return $bytes.Length.ToString() + '|' + (Get-TextSha256 $Text)
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

$resourceQualityNames = @('MECHANICAL_LOW','ROUTINE_BALANCED','FOCUSED_HIGH','OWNER_FRONTIER')

function Get-CanonicalStringArray($Value, [string]$Label) {
    if (-not ($Value -is [System.Array])) { throw "$Label must be an array." }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in @($Value)) {
        if (-not ($item -is [string]) -or [string]::IsNullOrWhiteSpace([string]$item) -or -not $seen.Add([string]$item)) { throw "$Label contains an invalid or duplicate item." }
    }
    $result = [string[]]@($seen)
    [Array]::Sort($result,[StringComparer]::Ordinal)
    return ,$result
}

function Read-CurrentResourceRequirement([string]$TaskPath) {
    $taskText = Get-Content -LiteralPath $TaskPath -Raw -Encoding utf8
    $matches = [regex]::Matches($taskText,'(?m)^- Resource requirement: (?<value>[^\r\n]+)$')
    if ($matches.Count -ne 1) { throw 'Task must contain exactly one Resource requirement field.' }
    $raw = $matches[0].Groups['value'].Value.Trim()
    if ($raw -ceq 'DEFAULT') {
        $requirement = [ordered]@{mode='DEFAULT';minimumQuality='ROUTINE_BALANCED';requiredTools=@();continuity='ANY'}
    }
    else {
        try { $parsed = $raw | ConvertFrom-Json } catch { throw 'Resource requirement JSON is invalid.' }
        if (-not ($parsed -is [pscustomobject])) { throw 'Resource requirement must be an object.' }
        $names=@($parsed.PSObject.Properties.Name)
        if ($names.Count -ne 3 -or @(@('minimumQuality','requiredTools','continuity') | Where-Object { $_ -cnotin $names }).Count -ne 0) { throw 'Resource requirement schema mismatch.' }
        if (-not ($parsed.minimumQuality -is [string]) -or [string]$parsed.minimumQuality -cnotin $resourceQualityNames -or -not ($parsed.continuity -is [string]) -or [string]$parsed.continuity -cnotin @('ANY','SAME_CONTEXT','FRESH')) { throw 'Resource requirement enum mismatch.' }
        $requiredTools=Get-CanonicalStringArray $parsed.requiredTools 'requiredTools'
        $requirement=[ordered]@{mode='EXCEPTION';minimumQuality=[string]$parsed.minimumQuality;requiredTools=@($requiredTools);continuity=[string]$parsed.continuity}
    }
    $canonical=$requirement|ConvertTo-Json -Compress -Depth 10
    return [pscustomobject]@{Value=$requirement;Identity=(Get-TextIdentity $canonical)}
}

function Read-CurrentTaskHeader([string]$TaskPath) {
    $taskText = Get-Content -LiteralPath $TaskPath -Raw -Encoding utf8
    $header = [regex]::Match($taskText, '\A# (?<id>[A-Za-z0-9][A-Za-z0-9._-]*) (?:\u2014|-) [^\r\n]+(?:\r?\n|\z)')
    $owners = [regex]::Matches($taskText, '(?m)^- Owner: (?<value>[^\r\n]+)$')
    if (-not $header.Success) { throw 'Task header must declare exactly one Task ID.' }
    if ($owners.Count -ne 1) { throw 'Task header must declare exactly one Owner.' }
    $owner = $owners[0].Groups['value'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($owner)) { throw 'Task Owner is invalid.' }
    return [pscustomobject]@{TaskId=$header.Groups['id'].Value;Owner=$owner}
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
if ([string]$package.frameworkVersion -cne '1.6.0') { Add-Reason $reasons 'FRAMEWORK_VERSION' }
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
    $controllerFields = @('issuerControllerId','issuerControllerEpoch','controllerControlIdentity')
    $controllerFieldFailure = $false
    foreach ($field in $controllerFields) {
        if ($null -eq $package.PSObject.Properties[$field]) { $controllerFieldFailure = $true }
    }
    if (-not $controllerFieldFailure) {
        if (-not ($package.issuerControllerId -is [string]) -or
            -not (Test-JsonInteger $package.issuerControllerEpoch) -or
            -not ($package.controllerControlIdentity -is [string]) -or
            [string]$package.controllerControlIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') {
            $controllerFieldFailure = $true
        }
    }
    if ([string]::IsNullOrWhiteSpace($ControllerControlPath)) { $controllerFieldFailure = $true }
    else {
        try { if ((Normalize-RelativePath $ControllerControlPath) -cne '.ai-workspace/controller.json') { $controllerFieldFailure = $true } }
        catch { $controllerFieldFailure = $true }
    }
    if (-not $controllerFieldFailure) {
        try {
            $controllerIdentity = Get-FileIdentity $ControllerControlPath
            $controllerRaw = Get-Content -LiteralPath $ControllerControlPath -Raw -Encoding utf8
            $controller = $controllerRaw | ConvertFrom-Json
            $controllerNames = @($controller.PSObject.Properties.Name)
            if ($controllerNames.Count -ne 5 -or
                @(@('schemaVersion','projectId','controllerId','controllerEpoch','state') | Where-Object { $_ -cnotin $controllerNames }).Count -ne 0) {
                $controllerFieldFailure = $true
            }
            elseif (-not (Test-JsonInteger $controller.schemaVersion) -or [int]$controller.schemaVersion -ne 1 -or
                -not (Test-JsonInteger $controller.controllerEpoch) -or [int64]$controller.controllerEpoch -lt 1 -or
                [string]$controller.state -cne 'CURRENT' -or
                [string]$package.issuer -cne [string]$package.issuerControllerId -or
                [string]$package.issuerControllerId -cne [string]$controller.controllerId -or
                [int64]$package.issuerControllerEpoch -ne [int64]$controller.controllerEpoch -or
                [string]$package.controllerControlIdentity -cne $controllerIdentity) {
                $controllerFieldFailure = $true
            }
        }
        catch { $controllerFieldFailure = $true }
    }
    if ($controllerFieldFailure) { Add-Reason $reasons 'STALE_CONTROLLER_AUTHORIZATION' }
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
$invalidators = @($package.invalidatesOn)
foreach ($item in $invalidators) {
    if (-not ($item -is [string])) { Add-Reason $reasons 'INVALIDATOR_TYPE' }
}
foreach ($item in $requiredInvalidators) {
    if ($item -cnotin $invalidators) { Add-Reason $reasons "INVALIDATOR_MISSING_$item" }
}

if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER' -and 'CONTROLLER_EPOCH_CHANGE' -cnotin $invalidators) {
    Add-Reason $reasons 'INVALIDATOR_MISSING_CONTROLLER_EPOCH_CHANGE'
}

$resourceActions = @('SOURCE_WRITE','TEST_WRITE','TEST_RUN','BROWSER_RUN','DEVICE_RUN','REVIEW_EXECUTE')
$requiresResourceBinding = @($actions | Where-Object { $_ -in $resourceActions }).Count -gt 0
if ($requiresResourceBinding) {
    if ([string]::IsNullOrWhiteSpace($ObservedPhase)) { Add-Reason $reasons 'RESOURCE_OBSERVED_PHASE_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace($ObservedHost)) { Add-Reason $reasons 'RESOURCE_OBSERVED_HOST_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace($ObservedContextIdentity) -or $ObservedContextIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'RESOURCE_OBSERVED_CONTEXT_REQUIRED' }
    foreach ($field in @('resourceBindingLocator','resourceBindingIdentity','resourceBindingDigest')) {
        if ($null -eq $package.PSObject.Properties[$field] -or -not ($package.$field -is [string]) -or [string]::IsNullOrWhiteSpace([string]$package.$field)) {
            Add-Reason $reasons "RESOURCE_BINDING_FIELD_$field"
        }
    }
    if ('RESOURCE_BINDING_CHANGE' -cnotin $invalidators) { Add-Reason $reasons 'INVALIDATOR_MISSING_RESOURCE_BINDING_CHANGE' }
    if ([string]::IsNullOrWhiteSpace($ResourceBindingPath)) {
        Add-Reason $reasons 'RESOURCE_BINDING_PATH_REQUIRED'
    }
    elseif ($null -ne $package.PSObject.Properties['resourceBindingLocator'] -and $package.resourceBindingLocator -is [string]) {
        try {
            $normalizedBindingPath = Normalize-RelativePath $ResourceBindingPath
            if ([string]$package.resourceBindingLocator -cne $normalizedBindingPath) { Add-Reason $reasons 'RESOURCE_BINDING_LOCATOR_DRIFT' }
            $bindingIdentity = Get-FileIdentity $ResourceBindingPath
            if ([string]$package.resourceBindingIdentity -cne $bindingIdentity) { Add-Reason $reasons 'RESOURCE_BINDING_IDENTITY_DRIFT' }
            $binding = Get-Content -LiteralPath $ResourceBindingPath -Raw -Encoding utf8 | ConvertFrom-Json
            $bindingRequired = @('schemaVersion','taskId','taskLocator','taskIdentity','resourceRequirementIdentity','adapterPolicyLocator','adapterPolicyIdentity','actualCapabilitySet','selectedQuality','selectedTools','continuity','phase','host','contextIdentity','bindingDigest')
            $bindingNames = @($binding.PSObject.Properties.Name)
            if ($bindingNames.Count -ne $bindingRequired.Count -or @($bindingRequired | Where-Object { $_ -cnotin $bindingNames }).Count -ne 0) {
                Add-Reason $reasons 'RESOURCE_BINDING_SCHEMA'
            }
            elseif (-not (Test-JsonInteger $binding.schemaVersion) -or [int]$binding.schemaVersion -ne 1 -or
                -not ($binding.taskId -is [string]) -or [string]$binding.taskId -cne [string]$package.taskId -or
                -not ($binding.taskLocator -is [string]) -or -not ($binding.taskIdentity -is [string]) -or [string]$binding.taskIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or
                -not ($binding.resourceRequirementIdentity -is [string]) -or [string]$binding.resourceRequirementIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or
                -not ($binding.adapterPolicyLocator -is [string]) -or -not ($binding.adapterPolicyIdentity -is [string]) -or [string]$binding.adapterPolicyIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or
                -not ($binding.selectedQuality -is [string]) -or [string]$binding.selectedQuality -cnotin $resourceQualityNames -or
                -not ($binding.selectedTools -is [System.Array]) -or -not ($binding.continuity -is [string]) -or [string]$binding.continuity -cnotin @('ANY','SAME_CONTEXT','FRESH') -or
                -not ($binding.phase -is [string]) -or [string]::IsNullOrWhiteSpace([string]$binding.phase) -or -not ($binding.host -is [string]) -or [string]::IsNullOrWhiteSpace([string]$binding.host) -or
                -not ($binding.contextIdentity -is [string]) -or [string]$binding.contextIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or
                -not ($binding.actualCapabilitySet -is [pscustomobject]) -or @($binding.actualCapabilitySet.PSObject.Properties.Name).Count -ne 4 -or
                @(@('locator','identity','qualities','tools') | Where-Object { $_ -cnotin @($binding.actualCapabilitySet.PSObject.Properties.Name) }).Count -ne 0 -or
                -not ($binding.actualCapabilitySet.locator -is [string]) -or -not ($binding.actualCapabilitySet.identity -is [string]) -or [string]$binding.actualCapabilitySet.identity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or
                [string]$binding.bindingDigest -cnotmatch '^[A-F0-9]{64}$') {
                Add-Reason $reasons 'RESOURCE_BINDING_SCHEMA'
            }
            else {
                if (-not [string]::IsNullOrWhiteSpace($ObservedPhase) -and [string]$binding.phase -cne $ObservedPhase) { Add-Reason $reasons 'RESOURCE_PHASE_DRIFT' }
                if (-not [string]::IsNullOrWhiteSpace($ObservedHost) -and [string]$binding.host -cne $ObservedHost) { Add-Reason $reasons 'RESOURCE_HOST_DRIFT' }
                if ($ObservedContextIdentity -match '^\d+\|[A-F0-9]{64}$' -and [string]$binding.contextIdentity -cne $ObservedContextIdentity) { Add-Reason $reasons 'RESOURCE_CONTEXT_DRIFT' }
                if ([string]::IsNullOrWhiteSpace($ResourceTaskPath) -or [string]::IsNullOrWhiteSpace($ResourceAdapterPolicyPath) -or [string]::IsNullOrWhiteSpace($ResourceCapabilityPath)) {
                    Add-Reason $reasons 'RESOURCE_DEPENDENCY_PATH_REQUIRED'
                }
                else {
                    try {
                        if ([string]$binding.taskLocator -cne (Normalize-RelativePath $ResourceTaskPath) -or (Get-FileIdentity $ResourceTaskPath) -cne [string]$binding.taskIdentity) { Add-Reason $reasons 'RESOURCE_TASK_DRIFT' }
                        if ([string]$binding.adapterPolicyLocator -cne (Normalize-RelativePath $ResourceAdapterPolicyPath) -or (Get-FileIdentity $ResourceAdapterPolicyPath) -cne [string]$binding.adapterPolicyIdentity) { Add-Reason $reasons 'RESOURCE_POLICY_DRIFT' }
                        if ([string]$binding.actualCapabilitySet.locator -cne (Normalize-RelativePath $ResourceCapabilityPath) -or (Get-FileIdentity $ResourceCapabilityPath) -cne [string]$binding.actualCapabilitySet.identity) { Add-Reason $reasons 'RESOURCE_CAPABILITY_DRIFT' }

                        $taskHeader=Read-CurrentTaskHeader $ResourceTaskPath
                        if ([string]$taskHeader.TaskId -cne [string]$package.taskId) { Add-Reason $reasons 'RESOURCE_TASK_ID_MISMATCH' }
                        if ([string]$taskHeader.Owner -cne [string]$package.owner) { Add-Reason $reasons 'RESOURCE_TASK_OWNER_MISMATCH' }
                        $requirementResult=Read-CurrentResourceRequirement $ResourceTaskPath
                        if ([string]$binding.resourceRequirementIdentity -cne [string]$requirementResult.Identity) { Add-Reason $reasons 'RESOURCE_REQUIREMENT_DRIFT' }
                        try { $policy=Get-Content -LiteralPath $ResourceAdapterPolicyPath -Raw -Encoding utf8|ConvertFrom-Json } catch { throw 'Adapter policy JSON is invalid.' }
                        try { $capability=Get-Content -LiteralPath $ResourceCapabilityPath -Raw -Encoding utf8|ConvertFrom-Json } catch { throw 'Capability JSON is invalid.' }
                        if (-not ($policy -is [pscustomobject]) -or -not ($capability -is [pscustomobject]) -or
                            -not (Test-JsonInteger $policy.schemaVersion) -or [int]$policy.schemaVersion -ne 1 -or -not ($policy.policyId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$policy.policyId) -or
                            -not ($policy.host -is [string]) -or [string]$policy.host -cne [string]$binding.host -or
                            -not (Test-JsonInteger $capability.schemaVersion) -or [int]$capability.schemaVersion -ne 1 -or -not ($capability.host -is [string]) -or [string]$capability.host -cne [string]$binding.host) { throw 'Resource policy/capability schema mismatch.' }
                        $policyOrder=Get-CanonicalStringArray $policy.qualityOrder 'qualityOrder'
                        if (@(Compare-Object -ReferenceObject ($resourceQualityNames|Sort-Object) -DifferenceObject ($policyOrder|Sort-Object) -CaseSensitive).Count -ne 0) { throw 'Resource policy quality order mismatch.' }
                        $availableQualities=Get-CanonicalStringArray $capability.qualities 'qualities'
                        $availableTools=Get-CanonicalStringArray $capability.tools 'tools'
                        $boundQualities=Get-CanonicalStringArray $binding.actualCapabilitySet.qualities 'bound qualities'
                        $boundTools=Get-CanonicalStringArray $binding.actualCapabilitySet.tools 'bound tools'
                        $selectedTools=Get-CanonicalStringArray $binding.selectedTools 'selected tools'
                        if (@(Compare-Object -ReferenceObject $availableQualities -DifferenceObject $boundQualities -CaseSensitive).Count -ne 0 -or @(Compare-Object -ReferenceObject $availableTools -DifferenceObject $boundTools -CaseSensitive).Count -ne 0) { Add-Reason $reasons 'RESOURCE_CAPABILITY_SNAPSHOT_DRIFT' }
                        if ([string]$binding.selectedQuality -cnotin $availableQualities) { Add-Reason $reasons 'RESOURCE_SELECTED_QUALITY_UNAVAILABLE' }
                        $minimumIndex=[Array]::IndexOf($resourceQualityNames,[string]$requirementResult.Value.minimumQuality)
                        $selectedIndex=[Array]::IndexOf($resourceQualityNames,[string]$binding.selectedQuality)
                        if ($selectedIndex -lt $minimumIndex) { Add-Reason $reasons 'RESOURCE_SILENT_QUALITY_DOWNGRADE' }
                        foreach($tool in @($requirementResult.Value.requiredTools)){if($tool -cnotin $availableTools -or $tool -cnotin $selectedTools){Add-Reason $reasons 'RESOURCE_REQUIRED_TOOL_MISSING'}}
                        foreach($tool in $selectedTools){if($tool -cnotin $availableTools){Add-Reason $reasons 'RESOURCE_SELECTED_TOOL_UNAVAILABLE'}}
                        if ([string]$requirementResult.Value.continuity -ceq 'FRESH' -and [string]$binding.continuity -cne 'FRESH') { Add-Reason $reasons 'RESOURCE_CONTINUITY_DOWNGRADE' }
                        if ([string]$requirementResult.Value.continuity -ceq 'SAME_CONTEXT' -and [string]$binding.continuity -cne 'SAME_CONTEXT') { Add-Reason $reasons 'RESOURCE_CONTINUITY_DOWNGRADE' }
                    }
                    catch { Add-Reason $reasons 'RESOURCE_DEPENDENCY_UNREADABLE' }
                }
                $core = [ordered]@{
                    schemaVersion=$binding.schemaVersion
                    taskId=$binding.taskId
                    taskLocator=$binding.taskLocator
                    taskIdentity=$binding.taskIdentity
                    resourceRequirementIdentity=$binding.resourceRequirementIdentity
                    adapterPolicyLocator=$binding.adapterPolicyLocator
                    adapterPolicyIdentity=$binding.adapterPolicyIdentity
                    actualCapabilitySet=$binding.actualCapabilitySet
                    selectedQuality=$binding.selectedQuality
                    selectedTools=@($binding.selectedTools)
                    continuity=$binding.continuity
                    phase=$binding.phase
                    host=$binding.host
                    contextIdentity=$binding.contextIdentity
                }
                $digest = Get-TextSha256 ($core | ConvertTo-Json -Compress -Depth 20)
                if ([string]$binding.bindingDigest -cne $digest -or [string]$package.resourceBindingDigest -cne $digest) {
                    Add-Reason $reasons 'RESOURCE_BINDING_DIGEST_DRIFT'
                }
            }
        }
        catch { Add-Reason $reasons 'RESOURCE_BINDING_UNREADABLE' }
    }
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
