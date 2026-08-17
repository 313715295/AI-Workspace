[CmdletBinding()]
param([switch]$SkipRootMigration,[switch]$SkipManifest,[switch]$SkipBaseline)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8 = New-Object Text.UTF8Encoding($false)
$utf8Strict = New-Object Text.UTF8Encoding($false,$true)
$script:passed = 0
$script:testJunctions = New-Object 'System.Collections.Generic.List[string]'

function Assert-True([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "ASSERT_FAIL|$Name" }
    $script:passed++
    Write-Output "PASS|$Name"
}

function Write-Utf8([string]$Path,[string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $value = $Text.Replace("`r`n","`n").Replace("`r","`n")
    if (-not $value.EndsWith("`n")) { $value += "`n" }
    [IO.File]::WriteAllText($Path,$value,$utf8)
}

function Get-Identity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return $bytes.Length.ToString() + '|' + ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Invoke-Ps([string]$Script,[string[]]$Arguments,[string]$WorkingDirectory='') {
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | ForEach-Object { [string]$_ }); $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
        return [pscustomobject]@{ Code=$code; Output=$output; Text=($output -join "`n") }
    } finally {
        if ($WorkingDirectory) { Pop-Location }
    }
}

function Invoke-PsWithProcessEnvironment([string]$Script,[string[]]$Arguments,[string]$WorkingDirectory,[hashtable]$Environment) {
    $previous = @{}
    foreach ($name in $Environment.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable([string]$name,'Process')
        [Environment]::SetEnvironmentVariable([string]$name,[string]$Environment[$name],'Process')
    }
    try { return Invoke-Ps $Script $Arguments $WorkingDirectory }
    finally {
        foreach ($name in $Environment.Keys) {
            $oldValue = $previous[$name]
            if ([string]::IsNullOrEmpty([string]$oldValue)) { Remove-Item -LiteralPath ('Env:\'+[string]$name) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable([string]$name,[string]$oldValue,'Process') }
        }
    }
}

function New-GitRepo([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    & git -C $Path init -q
    if ($LASTEXITCODE -ne 0) { throw 'GIT_INIT_FAILED' }
    & git -C $Path config user.email framework-test@example.invalid
    & git -C $Path config user.name FrameworkTest
    & git -C $Path config core.autocrlf false
    & git -C $Path config core.safecrlf false
    & git -C $Path config core.excludesFile (Join-Path $Path '.git\info\exclude')
}

function Commit-All([string]$Path,[string]$Message) {
    & git -C $Path add --all
    if ($LASTEXITCODE -ne 0) { throw 'GIT_ADD_FAILED' }
    & git -C $Path commit -q -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'GIT_COMMIT_FAILED' }
}

function New-TestJunction([string]$Path,[string]$Target) {
    $item = New-Item -ItemType Junction -Path $Path -Target $Target -Force
    if (([IO.FileAttributes]$item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'JUNCTION_CREATE_FAILED' }
    $script:testJunctions.Add([IO.Path]::GetFullPath($Path))
}

function Remove-TestJunction([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $entry = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($null -ne $entry) {
        if (([IO.FileAttributes]$entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'REFUSE_REMOVE_NON_JUNCTION' }
        [IO.Directory]::Delete($full)
    }
    $null = $script:testJunctions.Remove($full)
}

function Render-MaintenanceStarter([string]$Starter,[string]$ControlRoot) {
    $destination = Join-Path $ControlRoot '.ai-workspace'
    Copy-Item -LiteralPath $Starter -Destination $destination -Recurse
    Get-ChildItem -LiteralPath $destination -Recurse -Force -File | ForEach-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8
        $text = $text.Replace('{{PROJECT_ID}}','framework-maintenance-fixture')
        $text = $text.Replace('{{DISPLAY_NAME}}','Framework Maintenance Fixture')
        $text = $text.Replace('{{FRAMEWORK_VERSION}}','1.7.0')
        $text = $text.Replace('{{CONTROLLER_ID}}','controller-fixture')
        Write-Utf8 $_.FullName $text
    }
    return $destination
}

function New-AuthorizationPackage(
    [string]$Path,[int]$Schema,[string]$RepositoryId,[string]$ConfigIdentity,
    [string[]]$Actions,[string]$ExactPath,[string]$ObjectIdentity,[switch]$DomainOwner
) {
    $issuer = if ($DomainOwner) { 'owner-fixture' } else { 'controller-fixture' }
    $package = [ordered]@{
        schemaVersion=$Schema; frameworkVersion='1.7.0'; taskId='FIXTURE-001'; profile='STANDARD'; lifecycle='ACTIVE'
        owner=$issuer; issuer=$issuer; issuerRole=$(if($DomainOwner){'DOMAIN_OWNER'}else{'PROJECT_CONTROLLER'})
        grantee=$issuer; bundle='IMPLEMENT_LOCAL'; decisionClass='ROUTINE_LOCAL'; userConfirmation='NOT_REQUIRED'
        reviewIndependence='NOT_APPLICABLE'; delegatedGitCloser=$false; actions=@($Actions); exactPaths=@($ExactPath)
        objectIdentities=@([ordered]@{path=$ExactPath;identity=$ObjectIdentity})
        invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE')
    }
    if (-not $DomainOwner) {
        $package.issuerControllerId='controller-fixture'
        $package.issuerControllerEpoch=1
        $package.controllerControlIdentity=Get-Identity (Join-Path (Split-Path -Parent $Path) 'controller.json')
        $package.invalidatesOn += 'CONTROLLER_EPOCH_CHANGE'
    }
    if ($Schema -eq 2) {
        $package.repositoryId=$RepositoryId
        $package.projectConfigIdentity=$ConfigIdentity
        $package.invalidatesOn += @('REPOSITORY_CHANGE','PROJECT_CONFIG_DRIFT')
    }
    Write-Utf8 $Path ($package | ConvertTo-Json -Depth 20)
}

function Invoke-FixtureSchema2Authorization(
    [string]$Checker,[string]$Package,[string]$WorkingDirectory,[string]$Actor,
    [string]$Action,[string]$ObjectPath,[string]$ObjectIdentity,[string]$RepositoryId,[string]$ConfigIdentity
) {
    return Invoke-Ps $Checker @(
        '-PackagePath',$Package,
        '-ObservedActor',$Actor,
        '-ObservedTaskId','FIXTURE-001',
        '-ObservedOwner',$Actor,
        '-ObservedAction',$Action,
        '-ObservedPath',$ObjectPath,
        '-ObservedIdentity',($ObjectPath+'='+$ObjectIdentity),
        '-ControllerControlPath','.ai-workspace/controller.json',
        '-ObservedRepositoryId',$RepositoryId,
        '-ProjectConfigPath','.ai-workspace/project.json',
        '-ExpectedProjectConfigIdentity',$ConfigIdentity
    ) $WorkingDirectory
}

$candidateRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$expected = @(
    'AUTHORIZATION_MODEL.md','CHANGELOG.md','CONTROLLER_SCHEMA.json','EXAMPLES.md','FRAMEWORK_MAINTENANCE_CONFIG_SCHEMA.json',
    'FRAMEWORK_MAINTENANCE.md','FRAMEWORK_RELEASE.md','framework-maintenance-starter/.gitattributes','framework-maintenance-starter/BOOTSTRAP.md',
    'framework-maintenance-starter/controller.json','framework-maintenance-starter/project.json','framework-maintenance-starter/PROJECT.md',
    'framework-maintenance-starter/RELATIONSHIPS.md','framework-maintenance-starter/REVIEW_PROFILE.md','framework-maintenance-starter/STATUS.md',
    'framework-maintenance-starter/tasks/README.md','GIT_AND_EXTERNAL.md','HOST_CODEX.md','KNOWLEDGE_AND_REFERENCE.md','KNOWLEDGE_SCHEMA.json',
    'LOAD_MANIFEST.json','MIGRATION_MATRIX.md','PERSPECTIVE_LENSES.md','PROJECT_CONFIG_SCHEMA.json','PROJECT_CONTROL.md',
    'project-starter/.gitattributes','project-starter/BOOTSTRAP.md','project-starter/controller.json','project-starter/project.json',
    'project-starter/PROJECT.md','project-starter/RELATIONSHIPS.md','project-starter/REVIEW_PROFILE.md','project-starter/STATUS.md',
    'project-starter/tasks/README.md','PROMPTS.md','README.md','RECOVERY_CORE.md','RELEASE_MANIFEST.json','REVIEW_AND_EVIDENCE.md',
    'scripts/check-authorization.ps1','scripts/check-knowledge-entry.ps1','scripts/check-task-card.ps1',
    'scripts/invoke-protected-safe-git.ps1','scripts/resolve-framework-maintenance-target.ps1','scripts/resolve-load-plan.ps1',
    'STATIC_COMPARISON.md','TASK_AND_SCOPE.md','TASK_TEMPLATE.md','tests/run-framework-tests.ps1','VERSION.json'
)
[Array]::Sort($expected,[StringComparer]::Ordinal)
$actual = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($candidateRoot.Length + 1).Replace('\','/') })
[Array]::Sort($actual,[StringComparer]::Ordinal)
Assert-True ($actual.Count -eq 50 -and ($actual -join "`n") -ceq ($expected -join "`n")) 'inventory-exact50'

foreach ($relative in $actual) {
    $path = Join-Path $candidateRoot $relative
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no-bom|' + $relative)
    try { $text = $utf8Strict.GetString($bytes) } catch { throw "STRICT_UTF8_FAIL|$relative" }
    Assert-True (-not $text.Contains("`r") -and -not $text.Contains([char]0) -and -not $text.Contains([char]0xFFFD) -and $text.EndsWith("`n")) ('strict-text|' + $relative)
    if ([IO.Path]::GetExtension($relative) -ceq '.json' -and -not $text.Contains('{{')) {
        try { $null = $text | ConvertFrom-Json } catch { throw "JSON_FAIL|$relative|$($_.Exception.Message)" }
    }
    if ([IO.Path]::GetExtension($relative) -ceq '.ps1') {
        $tokens=$null; $errors=$null
        [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) ('powershell-syntax|' + $relative)
    }
}

$version = Get-Content -LiteralPath (Join-Path $candidateRoot 'VERSION.json') -Raw -Encoding utf8 | ConvertFrom-Json
$loadManifest = Get-Content -LiteralPath (Join-Path $candidateRoot 'LOAD_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
Assert-True ([string]$version.version -ceq '1.7.0' -and [string]$version.lifecycle -ceq 'STABLE' -and [string]$version.releaseClass -ceq 'MINOR' -and [bool]$version.consumable -and [string]$version.baseline -ceq '1.6.1' -and -not [bool]$version.currentEligible -and [bool]$version.projectPinEligible) 'version-stable-minor-baseline-1.6.1'
Assert-True ([string]$loadManifest.lifecycle -ceq 'STABLE' -and @($loadManifest.topologies.PSObject.Properties.Name).Count -eq 2 -and @($loadManifest.topologies.FRAMEWORK_MAINTENANCE_SIBLING) -contains 'FRAMEWORK_MAINTENANCE.md') 'load-manifest-topology-contract'

$loader = Join-Path $candidateRoot 'scripts\resolve-load-plan.ps1'
$normalLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX')
$maintenanceLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX','-Topology','FRAMEWORK_MAINTENANCE_SIBLING')
Assert-True ($normalLoad.Code -eq 0 -and $normalLoad.Text.Contains('topology=REPO_LOCAL') -and -not $normalLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md')) 'loader-default-repo-local-unchanged'
Assert-True ($maintenanceLoad.Code -eq 0 -and $maintenanceLoad.Text.Contains('topology=FRAMEWORK_MAINTENANCE_SIBLING') -and $maintenanceLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md')) 'loader-maintenance-module-mandatory'

$normalProjectTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\project.json') -Raw -Encoding utf8
$normalControllerTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\controller.json') -Raw -Encoding utf8
try {
    $null = $normalProjectTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{DISPLAY_NAME_JSON}}','"Fixture"').Replace('{{FRAMEWORK_VERSION_JSON}}','"1.7.0"') | ConvertFrom-Json
    $null = $normalControllerTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{CONTROLLER_ID_JSON}}','"controller"') | ConvertFrom-Json
    $normalStarterRendered = $true
} catch { $normalStarterRendered = $false }
Assert-True $normalStarterRendered 'repo-local-starter-json-renders'

$starterActual = @(Get-ChildItem -LiteralPath (Join-Path $candidateRoot 'framework-maintenance-starter') -Recurse -Force -File | ForEach-Object { $_.FullName.Substring((Join-Path $candidateRoot 'framework-maintenance-starter').Length + 1).Replace('\','/') })
Assert-True ($starterActual.Count -eq 9) 'maintenance-starter-exact9'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('aiw-framework-170-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $pair = Join-Path $temp 'Framework-Workspace'
    $control = Join-Path $pair 'AI-Workspace-Maintenance'
    $target = Join-Path $pair 'AI-Workspace'
    New-GitRepo $control
    New-GitRepo $target
    $controlPlane = Render-MaintenanceStarter (Join-Path $candidateRoot 'framework-maintenance-starter') $control
    $renderedFiles = Get-ChildItem -LiteralPath $controlPlane -Recurse -Force -File
    Assert-True (@($renderedFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8).Contains('{{') }).Count -eq 0) 'maintenance-starter-placeholders-closed'

    $configPath = Join-Path $controlPlane 'project.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
    $config.routineExcludedPaths = @('.ai-workspace/private.txt')
    $config.frameworkTarget.routineExcludedPaths = @('private/secret.txt')
    Write-Utf8 $configPath ($config | ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $control '.ai-workspace\private.txt') 'control private'
    Write-Utf8 (Join-Path $target 'README.md') '# AI-Workspace fixture'
    Write-Utf8 (Join-Path $target 'AGENTS.md') '# Fixture instructions'
    New-Item -ItemType Directory -Path (Join-Path $target 'framework\versions') -Force | Out-Null
    Copy-Item -LiteralPath $candidateRoot -Destination (Join-Path $target 'framework\versions\1.7.0') -Recurse
    Write-Utf8 (Join-Path $target 'docs\public.txt') 'public target'
    Write-Utf8 (Join-Path $target 'private\secret.txt') 'private target'
    $configIdentity = Get-Identity $configPath

    $installedFramework = Join-Path $target 'framework\versions\1.7.0'
    $installedActual = @(Get-ChildItem -LiteralPath $installedFramework -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($installedFramework.Length + 1).Replace('\','/') })
    [Array]::Sort($installedActual,[StringComparer]::Ordinal)
    Assert-True ($installedActual.Count -eq 50 -and ($installedActual -join "`n") -ceq ($actual -join "`n")) 'maintenance-target-full-candidate-installed'
    $controllerSchema = Get-Content -LiteralPath (Join-Path $installedFramework 'CONTROLLER_SCHEMA.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ([string]$controllerSchema.properties.state.const -ceq 'CURRENT' -and $null -eq $controllerSchema.properties.state.PSObject.Properties['enum']) 'controller-schema-current-only'

    $resolver = Join-Path $installedFramework 'scripts\resolve-framework-maintenance-target.ps1'
    $checker = Join-Path $installedFramework 'scripts\check-authorization.ps1'
    $controlObject = '.ai-workspace/tasks/README.md'
    $targetObject = 'docs/public.txt'
    $controllerPath = Join-Path $controlPlane 'controller.json'
    $resolve = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
    Assert-True ($resolve.Code -eq 0 -and $resolve.Text.Contains('"targetRepositoryId":"ai-workspace-framework"') -and $resolve.Text.Contains('"controllerState":"CURRENT"') -and -not $resolve.Text.Contains('migrationState') -and -not $resolve.Text.Contains('activeAuthority')) 'maintenance-resolver-final-current-two-real-git-tops'

    $steadyStateControlPackage = Join-Path $controlPlane 'steady-state-control-auth.json'
    $steadyStateTargetPackage = Join-Path $controlPlane 'steady-state-target-auth.json'
    $controlObjectIdentity = Get-Identity (Join-Path $control $controlObject)
    $targetObjectIdentity = Get-Identity (Join-Path $target $targetObject)
    New-AuthorizationPackage $steadyStateControlPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject $controlObjectIdentity
    New-AuthorizationPackage $steadyStateTargetPackage 2 'ai-workspace-framework' $configIdentity @('SOURCE_WRITE') $targetObject $targetObjectIdentity
    $steadyStateControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $steadyStateTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Assert-True ($steadyStateControlAuth.Code -eq 0 -and $steadyStateTargetAuth.Code -eq 0) 'authorization-schema2-steady-state-resolver-bound-pass'

    $maintenanceSchema1Package = Join-Path $controlPlane 'maintenance-schema1-auth.json'
    New-AuthorizationPackage $maintenanceSchema1Package 1 '' '' @('SOURCE_WRITE') $targetObject $targetObjectIdentity -DomainOwner
    $maintenanceSchema1Steady = Invoke-Ps $checker @('-PackagePath',$maintenanceSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+$targetObjectIdentity)) $control
    Assert-True ($maintenanceSchema1Steady.Code -ne 0 -and $maintenanceSchema1Steady.Text.Contains('SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3')) 'authorization-schema1-maintenance-steady-state-rejected'

    $invalidStatePackage = Join-Path $controlPlane 'invalid-state-auth.json'
    $invalidStateDomainPackage = Join-Path $controlPlane 'invalid-state-domain-auth.json'
    New-AuthorizationPackage $invalidStatePackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject))
    New-AuthorizationPackage $invalidStateDomainPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject)) -DomainOwner
    $controllerRawBeforeInvalidState = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $invalidController = $controllerRawBeforeInvalidState | ConvertFrom-Json
    $invalidController.state = 'NOT_CURRENT'
    Write-Utf8 $controllerPath ($invalidController | ConvertTo-Json -Depth 10)
    $invalidStateResolve = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
    $invalidStateAuth = Invoke-Ps $checker @('-PackagePath',$invalidStatePackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    $invalidStateDomainAuth = Invoke-Ps $checker @('-PackagePath',$invalidStateDomainPackage,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','owner-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Write-Utf8 $controllerPath $controllerRawBeforeInvalidState
    Assert-True ($invalidStateResolve.Code -ne 0 -and $invalidStateResolve.Text.Contains('CONTROLLER_VALUES')) 'non-current-controller-rejected-by-resolver'
    Assert-True ($invalidStateAuth.Code -ne 0 -and $invalidStateAuth.Text.Contains('CONTROLLER_VALUES') -and $invalidStateDomainAuth.Code -ne 0 -and $invalidStateDomainAuth.Text.Contains('CONTROLLER_VALUES')) 'non-current-controller-cannot-authorize-any-issuer-role'

    $targetControl = Join-Path $target '.ai-workspace'
    New-Item -ItemType Directory -Path $targetControl -Force | Out-Null
    Write-Utf8 (Join-Path $targetControl 'controller.json') (@{schemaVersion=1;projectId='foreign';controllerId='foreign';controllerEpoch=1;state='CURRENT'} | ConvertTo-Json)
    $completeTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $completeControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $completeTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    $completeSchema1Auth = Invoke-Ps $checker @('-PackagePath',$maintenanceSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+$targetObjectIdentity)) $control
    Remove-Item -LiteralPath $targetControl -Recurse -Force
    Assert-True ($completeTargetControl.Code -ne 0 -and $completeTargetControl.Text.Contains('TARGET_CONTROL_PLANE_PRESENT')) 'maintenance-resolver-complete-target-control-plane-rejected'
    Assert-True ($completeControlAuth.Code -ne 0 -and $completeTargetAuth.Code -ne 0 -and $completeControlAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED') -and $completeTargetAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED')) 'authorization-schema2-complete-target-control-plane-denies-control-and-target'
    Assert-True ($completeSchema1Auth.Code -ne 0 -and $completeSchema1Auth.Text.Contains('SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3')) 'authorization-schema1-maintenance-nonsteady-rejected'

    New-Item -ItemType Directory -Path $targetControl -Force | Out-Null
    $partialTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $partialControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $partialTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Recurse -Force
    Assert-True ($partialTargetControl.Code -ne 0 -and $partialTargetControl.Text.Contains('TARGET_CONTROL_PLANE_PRESENT')) 'maintenance-resolver-partial-target-control-plane-rejected'
    Assert-True ($partialControlAuth.Code -ne 0 -and $partialTargetAuth.Code -ne 0 -and $partialControlAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED') -and $partialTargetAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED')) 'authorization-schema2-partial-target-control-plane-denies-control-and-target'

    Write-Utf8 $targetControl 'foreign leaf'
    $foreignTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $foreignControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $foreignTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Force
    Assert-True ($foreignTargetControl.Code -ne 0 -and $foreignTargetControl.Text.Contains('TARGET_CONTROL_PLANE_PRESENT')) 'maintenance-resolver-foreign-target-control-plane-rejected'
    Assert-True ($foreignControlAuth.Code -ne 0 -and $foreignTargetAuth.Code -ne 0 -and $foreignControlAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED') -and $foreignTargetAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED')) 'authorization-schema2-foreign-target-control-plane-denies-control-and-target'

    $installedLoader = Join-Path $installedFramework 'scripts\resolve-load-plan.ps1'
    $fullColdLoad = Invoke-Ps $installedLoader @('-Role','CONTROLLER','-Profile','CRITICAL','-Phase','RECOVER','-HostName','CODEX','-Topology','FRAMEWORK_MAINTENANCE_SIBLING')
    $renderedBootstrap = Get-Content -LiteralPath (Join-Path $controlPlane 'BOOTSTRAP.md') -Raw -Encoding utf8
    Assert-True ($fullColdLoad.Code -eq 0 -and $fullColdLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md') -and $renderedBootstrap.Contains('state=CURRENT') -and -not $renderedBootstrap.Contains('AllowLegacyTargetControlPlane') -and $renderedBootstrap.Contains('Explicitly read `<TARGET>/AGENTS.md`')) 'maintenance-bootstrap-final-full-cold-route-from-installed-framework'

    $drift = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',('0|' + ('0' * 64)),'-AsJson')
    Assert-True ($drift.Code -ne 0 -and $drift.Text.Contains('PROJECT_CONFIG_DRIFT')) 'maintenance-resolver-config-drift-fails-closed'

    New-Item -ItemType Directory -Path (Join-Path $pair '.git') -Force | Out-Null
    $parentGit = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Assert-True ($parentGit.Code -ne 0 -and $parentGit.Text.Contains('WORKSPACE_PARENT_GIT_FORBIDDEN')) 'maintenance-resolver-parent-git-forbidden'
    Remove-Item -LiteralPath (Join-Path $pair '.git') -Recurse -Force

    New-Item -ItemType Directory -Path (Join-Path $pair '.ai-workspace') -Force | Out-Null
    $parentControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Assert-True ($parentControl.Code -ne 0 -and $parentControl.Text.Contains('WORKSPACE_PARENT_CONTROL_FORBIDDEN')) 'maintenance-resolver-parent-control-forbidden'
    Remove-Item -LiteralPath (Join-Path $pair '.ai-workspace') -Recurse -Force

    $configRaw = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
    $typedConfig = $configRaw | ConvertFrom-Json
    $typedConfig.schemaVersion = '4'
    Write-Utf8 $configPath ($typedConfig | ConvertTo-Json -Depth 20)
    $typedResult = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($typedResult.Code -ne 0 -and $typedResult.Text.Contains('PROJECT_CONFIG_VALUES')) 'maintenance-schema4-type-rejected'

    $duplicateRaw = [regex]::Replace($configRaw,'(?m)^(\s*"id"\s*:\s*.+,)$',"`$1`n`$1",1)
    Write-Utf8 $configPath $duplicateRaw
    $duplicateResult = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($duplicateResult.Code -ne 0 -and $duplicateResult.Text.Contains('PROJECT_CONFIG_DUPLICATE_OR_MISSING_FIELD')) 'maintenance-schema4-duplicate-field-rejected'
    Assert-True ((Get-Identity $configPath) -ceq $configIdentity) 'maintenance-fixture-config-restored-after-schema-negatives'

    $controlGitHold = Join-Path $control '.git.fixture-hold'
    Move-Item -LiteralPath (Join-Path $control '.git') -Destination $controlGitHold
    $controlNonGit = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Move-Item -LiteralPath $controlGitHold -Destination (Join-Path $control '.git')
    Assert-True ($controlNonGit.Code -ne 0) 'maintenance-resolver-control-non-git-rejected'

    $targetGitHold = Join-Path $target '.git.fixture-hold'
    Move-Item -LiteralPath (Join-Path $target '.git') -Destination $targetGitHold
    $targetNonGit = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Move-Item -LiteralPath $targetGitHold -Destination (Join-Path $target '.git')
    Assert-True ($targetNonGit.Code -ne 0) 'maintenance-resolver-target-non-git-rejected'

    $missingTargetConfig = $configRaw | ConvertFrom-Json
    $missingTargetConfig.frameworkTarget.siblingDirectory = 'AI-Workspace-Missing'
    Write-Utf8 $configPath ($missingTargetConfig | ConvertTo-Json -Depth 20)
    $missingTarget = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($missingTarget.Code -ne 0 -and $missingTarget.Text.Contains('TARGET_ROOT_MISSING')) 'maintenance-resolver-target-missing-rejected'

    $recoveryPath = Join-Path $installedFramework 'RECOVERY_CORE.md'
    $recoveryHold = Join-Path $installedFramework 'RECOVERY_CORE.fixture-hold'
    Move-Item -LiteralPath $recoveryPath -Destination $recoveryHold
    $missingPin = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Move-Item -LiteralPath $recoveryHold -Destination $recoveryPath
    Assert-True ($missingPin.Code -ne 0 -and $missingPin.Text.Contains('TARGET_REQUIRED_FILE_MISSING|framework/versions/1.7.0/RECOVERY_CORE.md')) 'maintenance-resolver-pin-entry-missing-rejected'

    $controllerRaw = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $staleController = $controllerRaw | ConvertFrom-Json
    $staleController.projectId = 'wrong-project'
    Write-Utf8 $controllerPath ($staleController | ConvertTo-Json -Depth 10)
    $staleControllerResult = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Write-Utf8 $controllerPath $controllerRaw
    Assert-True ($staleControllerResult.Code -ne 0 -and $staleControllerResult.Text.Contains('CONTROLLER_PROJECT_ID')) 'maintenance-resolver-stale-controller-rejected'

    $controlPlaneHold = Join-Path $control '.ai-workspace-real'
    Move-Item -LiteralPath $controlPlane -Destination $controlPlaneHold
    New-TestJunction $controlPlane $controlPlaneHold
    $configJunction = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Remove-TestJunction $controlPlane
    Move-Item -LiteralPath $controlPlaneHold -Destination $controlPlane
    Assert-True ($configJunction.Code -ne 0 -and $configJunction.Text.Contains('PROJECT_CONFIG_REPARSE|.ai-workspace')) 'maintenance-resolver-control-intermediate-junction-rejected'

    $frameworkPath = Join-Path $target 'framework'
    $frameworkHold = Join-Path $target 'framework-real'
    Move-Item -LiteralPath $frameworkPath -Destination $frameworkHold
    New-TestJunction $frameworkPath $frameworkHold
    $pinJunction = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Remove-TestJunction $frameworkPath
    Move-Item -LiteralPath $frameworkHold -Destination $frameworkPath
    Assert-True ($pinJunction.Code -ne 0 -and $pinJunction.Text.Contains('TARGET_REQUIRED_FILE_REPARSE|framework')) 'maintenance-resolver-target-intermediate-junction-rejected'

    $frameworkDanglingHold = Join-Path $target 'framework-dangling-hold'
    $frameworkLinkTarget = Join-Path $target 'framework-link-target'
    Move-Item -LiteralPath $frameworkPath -Destination $frameworkDanglingHold
    New-Item -ItemType Directory -Path $frameworkLinkTarget -Force | Out-Null
    New-TestJunction $frameworkPath $frameworkLinkTarget
    Remove-Item -LiteralPath $frameworkLinkTarget -Force
    $danglingPin = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Remove-TestJunction $frameworkPath
    Move-Item -LiteralPath $frameworkDanglingHold -Destination $frameworkPath
    Assert-True ($danglingPin.Code -ne 0) 'maintenance-resolver-target-dangling-junction-rejected'

    $targetControlBacking = Join-Path $temp 'target-control-backing'
    New-Item -ItemType Directory -Path $targetControlBacking -Force | Out-Null
    New-TestJunction $targetControl $targetControlBacking
    $targetControlJunction = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $junctionControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $junctionTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-TestJunction $targetControl
    Remove-Item -LiteralPath $targetControlBacking -Recurse -Force
    Assert-True ($targetControlJunction.Code -ne 0 -and $targetControlJunction.Text.Contains('TARGET_CONTROL_PLANE_REPARSE')) 'maintenance-resolver-target-control-junction-rejected'
    Assert-True ($junctionControlAuth.Code -ne 0 -and $junctionTargetAuth.Code -ne 0 -and $junctionControlAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED') -and $junctionTargetAuth.Text.Contains('MAINTENANCE_STEADY_STATE_REQUIRED')) 'authorization-schema2-target-control-junction-denies-control-and-target'

    $danglingTargetControlBacking = Join-Path $temp 'target-control-dangling-backing'
    New-Item -ItemType Directory -Path $danglingTargetControlBacking -Force | Out-Null
    New-TestJunction $targetControl $danglingTargetControlBacking
    Remove-Item -LiteralPath $danglingTargetControlBacking -Force
    $danglingTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $danglingControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $danglingTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-TestJunction $targetControl
    Assert-True ($danglingTargetControl.Code -ne 0) 'maintenance-resolver-target-control-dangling-junction-rejected'
    Assert-True ($danglingControlAuth.Code -ne 0 -and $danglingTargetAuth.Code -ne 0) 'authorization-schema2-target-control-dangling-junction-denies-control-and-target'

    $agentsPath = Join-Path $target 'AGENTS.md'
    $agentsHold = Join-Path $target 'AGENTS.fixture-hold'
    Move-Item -LiteralPath $agentsPath -Destination $agentsHold
    $missingAgents = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Move-Item -LiteralPath $agentsHold -Destination $agentsPath
    Assert-True ($missingAgents.Code -ne 0 -and $missingAgents.Text.Contains('TARGET_REQUIRED_FILE_MISSING|AGENTS.md')) 'maintenance-resolver-target-agents-required'

    $badSiblingConfig = $configRaw | ConvertFrom-Json
    $badSiblingConfig.frameworkTarget.siblingDirectory = '..\AI-Workspace'
    Write-Utf8 $configPath ($badSiblingConfig | ConvertTo-Json -Depth 20)
    $badSiblingIdentity = Get-Identity $configPath
    $badSibling = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$badSiblingIdentity)
    Write-Utf8 $configPath $configRaw
    Assert-True ($badSibling.Code -ne 0 -and $badSibling.Text.Contains('TARGET_SIBLING_COMPONENT')) 'maintenance-resolver-parent-traversal-rejected'
    Assert-True ((Get-Identity $configPath) -ceq $configIdentity) 'maintenance-fixture-config-restored'

    $controllerIdentity = Get-Identity (Join-Path $controlPlane 'controller.json')
    Assert-True ($controllerIdentity -match '^\d+\|[A-F0-9]{64}$') 'fixture-controller-identity'
    $controlPackage = Join-Path $controlPlane 'control-auth.json'
    $targetPackage = Join-Path $controlPlane 'target-auth.json'
    $badTargetActionPackage = Join-Path $controlPlane 'bad-target-action-auth.json'
    $badControlActionPackage = Join-Path $controlPlane 'bad-control-action-auth.json'
    New-AuthorizationPackage $controlPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject))
    New-AuthorizationPackage $targetPackage 2 'ai-workspace-framework' $configIdentity @('SOURCE_WRITE','TEST_RUN') $targetObject (Get-Identity (Join-Path $target $targetObject))
    New-AuthorizationPackage $badTargetActionPackage 2 'ai-workspace-framework' $configIdentity @('CONTROL_WRITE') $targetObject (Get-Identity (Join-Path $target $targetObject))
    New-AuthorizationPackage $badControlActionPackage 2 'CONTROL' $configIdentity @('SOURCE_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject))

    $controlAuth = Invoke-Ps $checker @('-PackagePath',$controlPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    $targetAuth = Invoke-Ps $checker @('-PackagePath',$targetPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($controlAuth.Code -eq 0 -and $targetAuth.Code -eq 0) 'authorization-schema2-control-and-target-pass'

    $wrongRepository = Invoke-Ps $checker @('-PackagePath',$targetPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($wrongRepository.Code -ne 0 -and $wrongRepository.Text.Contains('REPOSITORY_DRIFT')) 'authorization-schema2-repository-drift-rejected'
    $wrongConfig = Invoke-Ps $checker @('-PackagePath',$controlPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',('0|' + ('0' * 64))) $control
    Assert-True ($wrongConfig.Code -ne 0 -and $wrongConfig.Text.Contains('PROJECT_CONFIG_DRIFT')) 'authorization-schema2-config-drift-rejected'
    $badTargetAction = Invoke-Ps $checker @('-PackagePath',$badTargetActionPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    $badControlAction = Invoke-Ps $checker @('-PackagePath',$badControlActionPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($badTargetAction.Code -ne 0 -and $badTargetAction.Text.Contains('TARGET_REPOSITORY_CONTROL_WRITE_DENIED')) 'authorization-target-control-write-denied'
    Assert-True ($badControlAction.Code -ne 0 -and $badControlAction.Text.Contains('CONTROL_REPOSITORY_ACTION_DENIED')) 'authorization-control-source-write-denied'

    $objectDrift = Invoke-Ps $checker @('-PackagePath',$targetPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'=0|'+('0' * 64)),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($objectDrift.Code -ne 0 -and $objectDrift.Text.Contains('OBJECT_DRIFT')) 'authorization-schema2-object-drift-rejected'

    $crossPackage = Join-Path $controlPlane 'cross-repository-auth.json'
    $crossData = Get-Content -LiteralPath $targetPackage -Raw -Encoding utf8 | ConvertFrom-Json
    $crossPath = '../AI-Workspace-Maintenance/.ai-workspace/tasks/README.md'
    $crossData.exactPaths = @($crossPath)
    $crossData.objectIdentities = @([ordered]@{path=$crossPath;identity=(Get-Identity (Join-Path $target $targetObject))})
    Write-Utf8 $crossPackage ($crossData | ConvertTo-Json -Depth 20)
    $crossRepository = Invoke-Ps $checker @('-PackagePath',$crossPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$crossPath,'-ObservedIdentity',($crossPath+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($crossRepository.Code -ne 0 -and $crossRepository.Text.Contains('EXACT_PATH_INVALID')) 'authorization-schema2-cross-repository-path-rejected'

    $stalePackage = Join-Path $controlPlane 'stale-controller-auth.json'
    Copy-Item -LiteralPath $targetPackage -Destination $stalePackage
    $currentControllerRaw = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $epochController = $currentControllerRaw | ConvertFrom-Json
    $epochController.controllerEpoch = 2
    Write-Utf8 $controllerPath ($epochController | ConvertTo-Json -Depth 10)
    $staleData = Get-Content -LiteralPath $stalePackage -Raw -Encoding utf8 | ConvertFrom-Json
    $staleData.controllerControlIdentity = Get-Identity $controllerPath
    Write-Utf8 $stalePackage ($staleData | ConvertTo-Json -Depth 20)
    $staleAuthorization = Invoke-Ps $checker @('-PackagePath',$stalePackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Write-Utf8 $controllerPath $currentControllerRaw
    Assert-True ($staleAuthorization.Code -ne 0 -and $staleAuthorization.Text.Contains('STALE_CONTROLLER_AUTHORIZATION')) 'authorization-schema2-stale-controller-rejected'

    Commit-All $control 'control baseline'
    Commit-All $target 'target baseline'
    Write-Utf8 (Join-Path $control $controlObject) '# changed control task index'
    Write-Utf8 (Join-Path $target $targetObject) 'changed public target'
    Write-Utf8 (Join-Path $target 'private\secret.txt') 'changed private target'

    $safeGit = Join-Path $installedFramework 'scripts\invoke-protected-safe-git.ps1'
    $controlStatus = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath',$controlObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','CONTROL')
    $targetStatus = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    $controlDiff = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','DIFF','-AllowPath',$controlObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','CONTROL')
    $targetDiff = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','DIFF','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    $targetExcluded = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    $targetOverride = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath','private/secret.txt','-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework','-IncludeRoutineExcluded')
    try { $targetStatusJson = @($targetStatus.Output)[-1] | ConvertFrom-Json } catch { throw ('TARGET_STATUS_JSON|' + $targetStatus.Code + '|' + $targetStatus.Text) }
    try { $targetExcludedJson = @($targetExcluded.Output)[-1] | ConvertFrom-Json } catch { throw ('TARGET_EXCLUDED_JSON|' + $targetExcluded.Code + '|' + $targetExcluded.Text) }
    try { $targetOverrideJson = @($targetOverride.Output)[-1] | ConvertFrom-Json } catch { throw ('TARGET_OVERRIDE_JSON|' + $targetOverride.Code + '|' + $targetOverride.Text) }
    if (-not ($targetStatusJson -is [pscustomobject]) -or $null -eq $targetStatusJson.PSObject.Properties['output']) { throw ('TARGET_STATUS_NO_OUTPUT|' + $targetStatus.Code + '|' + $targetStatus.Text) }
    if (-not ($targetExcludedJson -is [pscustomobject]) -or $null -eq $targetExcludedJson.PSObject.Properties['output']) { throw ('TARGET_EXCLUDED_NO_OUTPUT|' + $targetExcluded.Code + '|' + $targetExcluded.Text) }
    if (-not ($targetOverrideJson -is [pscustomobject]) -or $null -eq $targetOverrideJson.PSObject.Properties['output']) { throw ('TARGET_OVERRIDE_NO_OUTPUT|' + $targetOverride.Code + '|' + $targetOverride.Text) }
    $targetOutput = @($targetStatusJson.output) -join "`n"
    $excludedOutput = @($targetExcludedJson.output) -join "`n"
    $overrideOutput = @($targetOverrideJson.output) -join "`n"
    Assert-True ($controlStatus.Code -eq 0 -and $controlStatus.Text.Contains($controlObject) -and $controlStatus.Text.Contains('"repositoryId":"CONTROL"')) 'safe-git-maintenance-control-selected'
    Assert-True ($targetStatus.Code -eq 0 -and $targetOutput.Contains($targetObject) -and $targetStatus.Text.Contains('"repositoryId":"ai-workspace-framework"')) 'safe-git-maintenance-target-selected'
    Assert-True ($targetExcluded.Code -eq 0 -and -not $excludedOutput.Contains('private/secret.txt')) 'safe-git-maintenance-target-exclusions'
    Assert-True ($targetOverride.Code -eq 0 -and $overrideOutput.Contains('private/secret.txt')) 'safe-git-maintenance-exact-exclusion-override'
    Assert-True ($controlDiff.Code -eq 0 -and $controlDiff.Text.Contains($controlObject) -and $controlDiff.Text.Contains('"operation":"DIFF"')) 'safe-git-maintenance-control-diff'
    Assert-True ($targetDiff.Code -eq 0 -and $targetDiff.Text.Contains($targetObject) -and $targetDiff.Text.Contains('"operation":"DIFF"')) 'safe-git-maintenance-target-diff'

    & git -C $control add -- $controlObject
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_FIXTURE_STAGE_FAILED' }
    & git -C $target add -- $targetObject
    if ($LASTEXITCODE -ne 0) { throw 'TARGET_FIXTURE_STAGE_FAILED' }
    $controlIndex = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','INDEX','-AllowPath',$controlObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','CONTROL')
    $targetIndex = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','INDEX','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    Assert-True ($controlIndex.Code -eq 0 -and $controlIndex.Text.Contains($controlObject) -and $controlIndex.Text.Contains('"operation":"INDEX"')) 'safe-git-maintenance-control-index'
    Assert-True ($targetIndex.Code -eq 0 -and $targetIndex.Text.Contains($targetObject) -and $targetIndex.Text.Contains('"operation":"INDEX"')) 'safe-git-maintenance-target-index'

    $unknownRepository = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','UNKNOWN')
    Assert-True ($unknownRepository.Code -ne 0 -and $unknownRepository.Text.Contains('REPOSITORY_ID_UNKNOWN') -and $unknownRepository.Text.Contains('"launched":false')) 'safe-git-maintenance-unknown-repository-not-launched'

    $repoLocal = Join-Path $temp 'repo-local-fixture'
    New-GitRepo $repoLocal
    $repoLocalConfigPath = Join-Path $repoLocal '.ai-workspace\project.json'
    $repoLocalConfig = [ordered]@{schemaVersion=3;id='repo-local-fixture';displayName='Repo Local Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.7.0';routineExcludedPaths=@('private/secret.txt');frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false}}}
    Write-Utf8 $repoLocalConfigPath ($repoLocalConfig | ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $repoLocal 'src\public.txt') 'repo local public'
    Write-Utf8 (Join-Path $repoLocal 'private\secret.txt') 'repo local private'
    $repoLocalIdentity = Get-Identity $repoLocalConfigPath
    $repoLocalSchema1Package = Join-Path $repoLocal '.ai-workspace\schema1-auth.json'
    $repoLocalObject = 'src/public.txt'
    $repoLocalObjectIdentity = Get-Identity (Join-Path $repoLocal $repoLocalObject)
    New-AuthorizationPackage $repoLocalSchema1Package 1 '' '' @('SOURCE_WRITE') $repoLocalObject $repoLocalObjectIdentity -DomainOwner
    $repoLocalSchema1Auth = Invoke-Ps $checker @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity)) $repoLocal
    $repoLocalStatus = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    $repoLocalExcluded = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    Assert-True ($repoLocalStatus.Code -eq 0 -and $repoLocalStatus.Text.Contains('src/public.txt') -and $repoLocalStatus.Text.Contains('"repositoryId":"PROJECT"')) 'safe-git-repo-local-default-compatible'
    Assert-True ($repoLocalExcluded.Code -eq 0 -and -not ((@($repoLocalExcluded.Output)[-1] | ConvertFrom-Json).output -join "`n").Contains('private/secret.txt')) 'safe-git-repo-local-exclusion-compatible'
    Assert-True ($repoLocalSchema1Auth.Code -eq 0) 'authorization-schema1-repo-local-schema3-compatible'

    $repoLocalSchema1Args = @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $gitOverrideValues = [ordered]@{GIT_DIR=(Join-Path $repoLocal '.git');GIT_WORK_TREE=$repoLocal;GIT_COMMON_DIR=(Join-Path $repoLocal '.git')}
    foreach ($gitEnvironmentName in $gitOverrideValues.Keys) {
        $schema1EnvironmentOverride = Invoke-PsWithProcessEnvironment $checker @('-PackagePath',$maintenanceSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+$targetObjectIdentity)) $control @{ $gitEnvironmentName=$gitOverrideValues[$gitEnvironmentName] }
        Assert-True ($schema1EnvironmentOverride.Code -ne 0 -and $schema1EnvironmentOverride.Text.Contains('GIT_ENVIRONMENT_OVERRIDE_'+$gitEnvironmentName)) ('authorization-schema1-rejects-process-'+$gitEnvironmentName.ToLowerInvariant())
    }

    $repoLocalConfigRaw = Get-Content -LiteralPath $repoLocalConfigPath -Raw -Encoding utf8
    $invalidSchema1Configs = @(
        [pscustomobject]@{Name='wrong-framework-version';Mutate={param($c) $c.frameworkVersion='1.6.1'};Reason='PROJECT_CONFIG_VALUES'},
        [pscustomobject]@{Name='non-string-exclusion';Mutate={param($c) $c.routineExcludedPaths=@(42)};Reason='ROUTINE_EXCLUSION_TYPE'},
        [pscustomobject]@{Name='unsafe-exclusion';Mutate={param($c) $c.routineExcludedPaths=@('../escape')};Reason='ROUTINE_PATH_COMPONENT'},
        [pscustomobject]@{Name='duplicate-exclusion';Mutate={param($c) $c.routineExcludedPaths=@('private/secret.txt','PRIVATE/SECRET.TXT')};Reason='ROUTINE_EXCLUSION_DUPLICATE'},
        [pscustomobject]@{Name='unknown-capability';Mutate={param($c) $c.frameworkCapabilities=[pscustomobject]@{UNKNOWN=[pscustomobject]@{}}};Reason='FRAMEWORK_CAPABILITIES_UNKNOWN_OR_DUPLICATE'},
        [pscustomobject]@{Name='malformed-knowledge-capability';Mutate={param($c) $c.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true}}};Reason='KNOWLEDGE_CAPABILITY_FIELDS'}
    )
    foreach ($case in $invalidSchema1Configs) {
        $invalidConfig = $repoLocalConfigRaw | ConvertFrom-Json
        $null = & ([scriptblock]$case.Mutate) $invalidConfig
        Write-Utf8 $repoLocalConfigPath ($invalidConfig | ConvertTo-Json -Depth 20)
        $invalidSchema1 = Invoke-Ps $checker $repoLocalSchema1Args $repoLocal
        if ($invalidSchema1.Code -eq 0 -or -not $invalidSchema1.Text.Contains([string]$case.Reason)) { Write-Output ('DIAG|schema1-invalid-'+[string]$case.Name+'|'+$invalidSchema1.Code+'|'+$invalidSchema1.Text) }
        Assert-True ($invalidSchema1.Code -ne 0 -and $invalidSchema1.Text.Contains([string]$case.Reason)) ('authorization-schema1-rejects-'+[string]$case.Name)
    }
    Write-Utf8 $repoLocalConfigPath $repoLocalConfigRaw

    $missingConfigPath = $repoLocalConfigPath + '.missing'
    [IO.File]::Move($repoLocalConfigPath,$missingConfigPath)
    try { $missingSchema1Config = Invoke-Ps $checker $repoLocalSchema1Args $repoLocal }
    finally { [IO.File]::Move($missingConfigPath,$repoLocalConfigPath) }
    Assert-True ($missingSchema1Config.Code -ne 0 -and $missingSchema1Config.Text.Contains('PROJECT_CONFIG_MISSING')) 'authorization-schema1-rejects-missing-project-config'

    $reparseRepoLocal = Join-Path $temp 'repo-local-reparse-fixture'
    New-GitRepo $reparseRepoLocal
    New-TestJunction (Join-Path $reparseRepoLocal '.ai-workspace') (Join-Path $repoLocal '.ai-workspace')
    try { $reparseSchema1Control = Invoke-Ps $checker $repoLocalSchema1Args $reparseRepoLocal }
    finally { Remove-TestJunction (Join-Path $reparseRepoLocal '.ai-workspace') }
    Assert-True ($reparseSchema1Control.Code -ne 0 -and $reparseSchema1Control.Text.Contains('PROJECT_CONTROL_PLANE_REPARSE')) 'authorization-schema1-rejects-reparse-control-plane'

    if (-not $SkipBaseline) {
        $frameworkRoot = [IO.Path]::GetFullPath((Join-Path $candidateRoot '..\..')).TrimEnd('\')
        $workspaceRoot = Split-Path -Parent $frameworkRoot
        $baselineWorkspace = Join-Path $temp 'baseline-workspace'
        New-Item -ItemType Directory -Path (Join-Path $baselineWorkspace 'framework\versions'),(Join-Path $baselineWorkspace 'scripts') -Force | Out-Null
        foreach ($baselineVersion in @('1.4.1','1.5.0','1.5.1','1.5.2','1.6.0','1.6.1')) {
            Copy-Item -LiteralPath (Join-Path $frameworkRoot ('versions\' + $baselineVersion)) -Destination (Join-Path $baselineWorkspace ('framework\versions\' + $baselineVersion)) -Recurse
        }
        Write-Utf8 (Join-Path $baselineWorkspace 'framework\CURRENT') '1.6.1'
        Copy-Item -LiteralPath (Join-Path $frameworkRoot 'drafts\1.6.0\minimal-root\INITIALIZATION.md') -Destination (Join-Path $baselineWorkspace 'INITIALIZATION.md')
        Copy-Item -LiteralPath (Join-Path $frameworkRoot 'drafts\1.6.0\minimal-root\scripts\register-project.ps1') -Destination (Join-Path $baselineWorkspace 'scripts\register-project.ps1')
        Copy-Item -LiteralPath (Join-Path $frameworkRoot 'drafts\1.6.0\minimal-root\scripts\upgrade-project.ps1') -Destination (Join-Path $baselineWorkspace 'scripts\upgrade-project.ps1')
        $baselineRunner = Join-Path $baselineWorkspace 'framework\versions\1.6.1\tests\run-framework-tests.ps1'
        $baseline = Invoke-Ps $baselineRunner @('-SkipRootMigration')
        if ($baseline.Code -ne 0) { Write-Output ('DIAG|baseline-1.6.1|' + $baseline.Text) }
        Assert-True ($baseline.Code -eq 0 -and $baseline.Text.Contains('RESULT|')) 'baseline-1.6.1-regression-suite'
    }

    if (-not $SkipManifest) {
        $manifest = Get-Content -LiteralPath (Join-Path $candidateRoot 'RELEASE_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
        [string[]]$payload = @($actual | Where-Object { $_ -cne 'RELEASE_MANIFEST.json' })
        [Array]::Sort($payload,[StringComparer]::Ordinal)
        $rows = @(); $total = [int64]0
        foreach ($relative in $payload) {
            $full = Join-Path $candidateRoot $relative
            $bytes = [IO.File]::ReadAllBytes($full)
            $total += $bytes.Length
            $rows += ($relative + '|' + $bytes.Length + '|' + (Get-Identity $full).Split('|')[1])
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $canonical = ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes(($rows -join "`n"))))).Replace('-','') }
        finally { $sha.Dispose() }
        $manifestOk = [int]$manifest.fileCount -eq $payload.Count -and [int64]$manifest.totalBytes -eq $total -and [string]$manifest.canonical -ceq $canonical
        if (-not $manifestOk) { Write-Output ('DIAG|manifest|actual=' + $payload.Count + '|' + $total + '|' + $canonical + '|declared=' + $manifest.fileCount + '|' + $manifest.totalBytes + '|' + $manifest.canonical) }
        Assert-True $manifestOk 'release-manifest-canonical'
    }
} finally {
    foreach ($junction in @($script:testJunctions.ToArray())) {
        try { Remove-TestJunction $junction } catch {}
    }
    if (Test-Path -LiteralPath $temp) {
        Get-ChildItem -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes=[IO.FileAttributes]::Normal } catch {} }
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output ("RESULT|" + $script:passed + "/" + $script:passed + " passed|scope=Framework-1.7.0-stable|lifecycle=STABLE")
