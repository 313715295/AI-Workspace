[CmdletBinding()]
param([switch]$SkipRootMigration,[switch]$SkipManifest,[switch]$SkipBaseline,[switch]$ToolContractOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'POWERSHELL7_REQUIRED' }
$script:pwshExecutable=[Environment]::ProcessPath
if([string]::IsNullOrWhiteSpace($script:pwshExecutable)){throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE'}
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

function Get-ReleasePayloadFacts([string]$VersionRoot) {
    [string[]]$payload=@(Get-ChildItem -LiteralPath $VersionRoot -Recurse -Force -File|ForEach-Object{$_.FullName.Substring($VersionRoot.Length+1).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'})
    [Array]::Sort($payload,[StringComparer]::Ordinal)
    $rows=@();[int64]$total=0
    foreach($relative in $payload){$full=Join-Path $VersionRoot $relative;$identity=(Get-Identity $full).Split('|');$total+=[int64]$identity[0];$rows+=($relative+'|'+$identity[0]+'|'+$identity[1])}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$canonical=([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes(($rows-join"`n"))))).Replace('-','')}finally{$sha.Dispose()}
    return [pscustomobject]@{Files=$payload;Rows=$rows;FileCount=$payload.Count;TotalBytes=$total;Canonical=$canonical}
}

function Seal-ReleaseFixture([string]$VersionRoot,[string]$Integration) {
    $facts=Get-ReleasePayloadFacts $VersionRoot
    $versionPath=Join-Path $VersionRoot 'VERSION.json';$version=Get-Content -Raw -Encoding utf8 -LiteralPath $versionPath|ConvertFrom-Json
    $version.lifecycle='STABLE';$version.consumable=$true;$version.projectPinEligible=$true
    Write-Utf8 $versionPath ($version|ConvertTo-Json -Depth 20)
    $facts=Get-ReleasePayloadFacts $VersionRoot
    $manifestPath=Join-Path $VersionRoot 'RELEASE_MANIFEST.json';$manifest=Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath|ConvertFrom-Json
    $manifest.lifecycle='STABLE';$manifest.fileCount=$facts.FileCount;$manifest.totalBytes=$facts.TotalBytes;$manifest.canonical=$facts.Canonical;$manifest.sourceReview='APPROVED';$manifest.sourceCandidate='TEST_FIXTURE_CANDIDATE';$manifest.releaseIntegration=$Integration
    Write-Utf8 $manifestPath ($manifest|ConvertTo-Json -Depth 20)
    return $facts
}

function Invoke-Ps([string]$Script,[string[]]$Arguments,[string]$WorkingDirectory='') {
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = @(& $script:pwshExecutable -NoProfile -NonInteractive -File $Script @Arguments 2>&1 | ForEach-Object { [string]$_ }); $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
        return [pscustomobject]@{ Code=$code; Output=$output; Text=($output -join "`n") }
    } finally {
        if ($WorkingDirectory) { Pop-Location }
    }
}

function Invoke-PsHost([string]$Executable,[string]$Script,[string[]]$Arguments,[string]$WorkingDirectory='') {
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = @(& $Executable -NoProfile -NonInteractive -File $Script @Arguments 2>&1 | ForEach-Object { [string]$_ }); $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
        return [pscustomobject]@{ Code=$code; Output=$output; Text=($output -join "`n") }
    } finally {
        if ($WorkingDirectory) { Pop-Location }
    }
}

function Invoke-PsHostEntryIdArray(
    [string]$Executable,[string]$Checker,[string[]]$BaseArguments,[string[]]$EntryIds,[string]$WrapperRoot,[string]$WorkingDirectory=''
) {
    $suffix=[guid]::NewGuid().ToString('N')
    $payloadPath=Join-Path $WrapperRoot ('knowledge-array-'+$suffix+'.json')
    $wrapperPath=Join-Path $WrapperRoot ('knowledge-array-'+$suffix+'.ps1')
    $payload=[ordered]@{checker=$Checker;baseArguments=@($BaseArguments);entryIds=@($EntryIds)}
    $wrapper=@'
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PayloadPath)
$ErrorActionPreference='Stop'
$payload=Get-Content -LiteralPath $PayloadPath -Raw -Encoding utf8|ConvertFrom-Json
$baseArguments=@($payload.baseArguments|ForEach-Object{[string]$_})
$entryIds=@($payload.entryIds|ForEach-Object{[string]$_})
if($baseArguments.Count%2-ne0){throw 'BASE_ARGUMENT_PAIR_COUNT'}
$named=@{}
for($index=0;$index-lt$baseArguments.Count;$index+=2){
    $token=[string]$baseArguments[$index]
    if(-not$token.StartsWith('-')-or$token.Length-lt2){throw 'BASE_ARGUMENT_NAME'}
    $name=$token.Substring(1)
    if($named.ContainsKey($name)){throw 'BASE_ARGUMENT_DUPLICATE'}
    $named[$name]=[string]$baseArguments[$index+1]
}
$named['Operation']='QUERY'
$named['EntryId']=$entryIds
$named['AsJson']=$true
& ([string]$payload.checker) @named
exit $LASTEXITCODE
'@
    Write-Utf8 $payloadPath ($payload|ConvertTo-Json -Depth 10)
    Write-Utf8 $wrapperPath $wrapper
    try { return Invoke-PsHost $Executable $wrapperPath @('-PayloadPath',$payloadPath) $WorkingDirectory }
    finally {
        Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $wrapperPath -Force -ErrorAction SilentlyContinue
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

function Invoke-WorkflowCase([string]$Resolver,[string]$Root,[string]$Name,$InputObject) {
    $path = Join-Path $Root ('workflow-' + $Name + '.json')
    Write-Utf8 $path ($InputObject | ConvertTo-Json -Depth 12)
    $run = Invoke-Ps $Resolver @('-InputPath',$path,'-AsJson')
    $value = $null
    if ($run.Code -eq 0 -and $run.Output.Count -gt 0) {
        try { $value = @($run.Output)[-1] | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{ Run=$run; Value=$value }
}

function Invoke-WorkflowRawCase([string]$Resolver,[string]$Root,[string]$Name,[string]$RawInput) {
    $path = Join-Path $Root ('workflow-' + $Name + '.json')
    Write-Utf8 $path $RawInput
    return Invoke-Ps $Resolver @('-InputPath',$path,'-AsJson')
}

function New-GitRepo([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    & git -C $Path init -q
    if ($LASTEXITCODE -ne 0) { throw 'GIT_INIT_FAILED' }
    & git -C $Path config user.email framework-test@example.invalid
    & git -C $Path config user.name FrameworkTest
    & git -C $Path config core.autocrlf false
    & git -C $Path config core.safecrlf false
    & git -C $Path config core.excludesFile (Join-Path $Path '.git/info/exclude')
}

function Commit-All([string]$Path,[string]$Message) {
    & git -C $Path add --all
    if ($LASTEXITCODE -ne 0) { throw 'GIT_ADD_FAILED' }
    & git -C $Path commit -q -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'GIT_COMMIT_FAILED' }
}

function New-TestJunction([string]$Path,[string]$Target) {
    $item = if($IsWindows){New-Item -ItemType Junction -Path $Path -Target $Target -Force}else{New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force}
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
        $text = $text.Replace('{{FRAMEWORK_VERSION}}','1.12.0')
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
        schemaVersion=$Schema; frameworkVersion='1.12.0'; taskId='FIXTURE-001'; profile='STANDARD'; lifecycle='ACTIVE'
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

$candidateRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$expected = @(
    'AUTHORIZATION_MODEL.md','CHANGELOG.md','CONTROLLER_SCHEMA.json','CORRECTION_COVERAGE.json','EXAMPLES.md','FRAMEWORK_MAINTENANCE_CONFIG_SCHEMA.json',
    'FRAMEWORK_MAINTENANCE.md','FRAMEWORK_RELEASE.md','framework-maintenance-starter/.gitattributes','framework-maintenance-starter/BOOTSTRAP.md',
    'framework-maintenance-starter/controller.json','framework-maintenance-starter/corrections.json','framework-maintenance-starter/project.json','framework-maintenance-starter/PROJECT.md',
    'framework-maintenance-starter/RELATIONSHIPS.md','framework-maintenance-starter/REVIEW_PROFILE.md','framework-maintenance-starter/STATUS.md',
    'framework-maintenance-starter/tasks/README.md','GIT_AND_EXTERNAL.md','HOST_CODEX.md','KNOWLEDGE_AND_REFERENCE.md','KNOWLEDGE_SCHEMA.json',
    'LOAD_MANIFEST.json','MIGRATION_MATRIX.md','PERSPECTIVE_LENSES.md','PROJECT_CONFIG_SCHEMA.json','PROJECT_CONTROL.md','PROJECT_CORRECTIONS_SCHEMA.json',
    'project-starter/.gitattributes','project-starter/BOOTSTRAP.md','project-starter/controller.json','project-starter/corrections.json','project-starter/project.json',
    'project-starter/PROJECT.md','project-starter/RELATIONSHIPS.md','project-starter/REVIEW_PROFILE.md','project-starter/STATUS.md',
    'project-starter/tasks/README.md','PROMPTS.md','README.md','RECOVERY_CORE.md','RELEASE_MANIFEST.json','REVIEW_AND_EVIDENCE.md',
    'scripts/check-authorization.ps1','scripts/check-knowledge-entry.ps1','scripts/check-knowledge-impact.ps1','scripts/check-project-corrections.ps1','scripts/check-task-card.ps1',
    'scripts/invoke-protected-safe-git.ps1','scripts/resolve-framework-maintenance-target.ps1','scripts/resolve-load-plan.ps1',
    'scripts/resolve-workflow-route.ps1',
    'STATIC_COMPARISON.md','TASK_AND_SCOPE.md','TASK_TEMPLATE.md','tests/run-framework-tests.ps1','TOOLCHAIN.json','TOOL_CONTRACT.md','VERSION.json'
)
[Array]::Sort($expected,[StringComparer]::Ordinal)
$actual = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($candidateRoot.Length + 1).Replace('\','/') })
[Array]::Sort($actual,[StringComparer]::Ordinal)
Assert-True ($actual.Count -eq 59 -and ($actual -join "`n") -ceq ($expected -join "`n")) 'inventory-exact59'

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
$candidateVersionState=[string]$version.lifecycle-ceq'CANDIDATE'-and-not[bool]$version.consumable-and-not[bool]$version.projectPinEligible
$stableVersionState=[string]$version.lifecycle-ceq'STABLE'-and[bool]$version.consumable-and[bool]$version.projectPinEligible
Assert-True ([string]$version.version -ceq '1.12.0' -and ($candidateVersionState-or$stableVersionState) -and [string]$version.releaseClass -ceq 'MINOR' -and [string]$version.baseline -ceq '1.11.0' -and $null -eq $version.PSObject.Properties['currentEligible']) 'version-candidate-or-stable-minor-baseline-1.11.0-no-global-selector-field'
Assert-True ([string]$loadManifest.lifecycle -ceq 'STABLE' -and @($loadManifest.topologies.PSObject.Properties.Name).Count -eq 2 -and @($loadManifest.topologies.FRAMEWORK_MAINTENANCE_SIBLING) -contains 'FRAMEWORK_MAINTENANCE.md') 'load-manifest-topology-contract'
$loadResolverText=Get-Content -LiteralPath (Join-Path $candidateRoot 'scripts\resolve-load-plan.ps1') -Raw -Encoding utf8
Assert-True ($loadResolverText.Contains('LOAD_MANIFEST_NOT_STABLE_1_12_0') -and -not $loadResolverText.Contains('LOAD_MANIFEST_NOT_STABLE_1_7_0')) 'load-resolver-diagnostic-version-current'

$toolchain=Get-Content -LiteralPath (Join-Path $candidateRoot 'TOOLCHAIN.json') -Raw -Encoding utf8|ConvertFrom-Json
$toolContract=Get-Content -LiteralPath (Join-Path $candidateRoot 'TOOL_CONTRACT.md') -Raw -Encoding utf8
$backend=@($toolchain.officialBackends)[0]
$expectedOperations=@('AUTHORIZATION_CHECK','CORRECTIONS_CHECK','KNOWLEDGE_IMPACT_CHECK','KNOWLEDGE_QUERY','LOAD_PLAN_RESOLVE','MAINTENANCE_TARGET_RESOLVE','PROTECTED_SAFE_GIT','TASK_CARD_CHECK','WORKFLOW_ROUTE_RESOLVE')
$actualOperations=@($backend.entrypoints.PSObject.Properties.Name);[Array]::Sort($expectedOperations,[StringComparer]::Ordinal);[Array]::Sort($actualOperations,[StringComparer]::Ordinal)
Assert-True ([int]$toolchain.schemaVersion-eq1-and[string]$toolchain.frameworkVersion-ceq'1.12.0'-and[string]$toolchain.contractVersion-ceq'1'-and[string]$toolchain.projectSelectionField-ceq'frameworkToolBackend'-and@($toolchain.officialBackends).Count-eq1) 'toolchain-single-project-selected-backend'
Assert-True ([string]$backend.id-ceq'powershell7'-and[string]$backend.status-ceq'OFFICIAL'-and[string]$backend.runtime.command-ceq'pwsh'-and[string]$backend.runtime.edition-ceq'Core'-and[int]$backend.runtime.minimumMajorVersion-eq7-and($actualOperations-join"`n")-ceq($expectedOperations-join"`n")) 'toolchain-powershell7-operation-set'
foreach($entry in $backend.entrypoints.PSObject.Properties){$relative=[string]$entry.Value;$entryPath=Join-Path $candidateRoot $relative;Assert-True ($relative-ceq$relative.Replace('\','/')-and-not[IO.Path]::IsPathRooted($relative)-and-not$relative.Contains('..')-and(Test-Path -LiteralPath $entryPath -PathType Leaf)) ('toolchain-entrypoint|'+$entry.Name);$entryText=Get-Content -LiteralPath $entryPath -Raw -Encoding utf8;Assert-True ($entryText.Contains('POWERSHELL7_REQUIRED')-and-not$entryText.Contains('powershell.exe')) ('toolchain-runtime-guard|'+$entry.Name)}
$projectSchemaText=Get-Content -LiteralPath (Join-Path $candidateRoot 'PROJECT_CONFIG_SCHEMA.json') -Raw -Encoding utf8
$maintenanceSchemaText=Get-Content -LiteralPath (Join-Path $candidateRoot 'FRAMEWORK_MAINTENANCE_CONFIG_SCHEMA.json') -Raw -Encoding utf8
$projectStarterText=Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter/project.json') -Raw -Encoding utf8
Assert-True ($projectSchemaText.Contains('frameworkToolBackend')-and$maintenanceSchemaText.Contains('frameworkToolBackend')-and$projectStarterText.Contains('"frameworkToolBackend": "powershell7"')-and$toolContract.Contains('projectConfigIdentity')) 'tool-backend-schema-starter-package-binding'

if($ToolContractOnly){
    $contractTemp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-tool-contract-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $contractTemp|Out-Null
    try{
        $casePath=Join-Path $contractTemp 'CaseProbe';Write-Utf8 $casePath 'case'
        $caseInsensitive=Test-Path -LiteralPath (Join-Path $contractTemp 'caseprobe')
        $linkTarget=Join-Path $contractTemp 'link-target';$linkPath=Join-Path $contractTemp 'link-probe';New-Item -ItemType Directory -Path $linkTarget|Out-Null;New-TestJunction $linkPath $linkTarget
        Assert-True (((Get-Item -LiteralPath $linkPath -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0) 'tool-contract-link-probe'
        $normalized=[IO.Path]::GetRelativePath($contractTemp,$casePath).Replace('\','/')
        Assert-True ($normalized-ceq'CaseProbe'-and-not$normalized.Contains('\')) 'tool-contract-relative-path-normalized'
        if(-not$IsWindows){$mode=[IO.File]::GetUnixFileMode($casePath);[IO.File]::SetUnixFileMode($casePath,$mode);Assert-True ([IO.File]::GetUnixFileMode($casePath)-eq$mode) 'tool-contract-unix-permission-roundtrip'}else{Assert-True $true 'tool-contract-windows-permission-ceiling-explicit'}
        $gitRoot=Join-Path $contractTemp 'git-probe';New-GitRepo $gitRoot
        $gitConfigPath=Join-Path $gitRoot '.ai-workspace/project.json'
        $gitConfig=[ordered]@{schemaVersion=3;id='tool-contract-git';displayName='Tool Contract Git';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.12.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$false}}}
        Write-Utf8 $gitConfigPath ($gitConfig|ConvertTo-Json -Depth 20)
        $gitVisible=Join-Path $gitRoot 'visible.txt';Write-Utf8 $gitVisible 'baseline';Commit-All $gitRoot 'tool contract baseline';Write-Utf8 $gitVisible 'changed'
        $safeGitEntry=Join-Path $candidateRoot ([string]$backend.entrypoints.PROTECTED_SAFE_GIT)
        $safeGitProbe=Invoke-Ps $safeGitEntry @('-ProjectRoot',$gitRoot,'-Operation','STATUS','-AllowPath','visible.txt','-ExpectedProjectConfigIdentity',(Get-Identity $gitConfigPath))
        Assert-True ($safeGitProbe.Code-eq0-and$safeGitProbe.Text.Contains('visible.txt')-and$safeGitProbe.Text.Contains('"operation":"STATUS"')) 'tool-contract-safe-git-normalized-path'
        $platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
        Write-Output ('CONFORMANCE|platform='+$platform+'|caseInsensitive='+$caseInsensitive.ToString().ToLowerInvariant()+'|runtime='+$PSVersionTable.PSVersion.ToString())
    }finally{foreach($link in @($script:testJunctions)){Remove-TestJunction $link};Remove-Item -LiteralPath $contractTemp -Recurse -Force -ErrorAction SilentlyContinue}
    Write-Output "RESULT|$($script:passed) passed|scope=Framework-1.12.0-tool-contract"
    return
}

$liveFrameworkRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $candidateRoot '../..')))
$liveRepositoryRoot = Split-Path -Parent $liveFrameworkRoot
$selectorScope = @(
    (Join-Path $liveRepositoryRoot '.gitattributes'),(Join-Path $liveRepositoryRoot 'AGENTS.md'),(Join-Path $liveRepositoryRoot 'CLAUDE.md'),
    (Join-Path $liveRepositoryRoot 'INITIALIZATION.md'),(Join-Path $liveRepositoryRoot 'README.md'),(Join-Path $liveFrameworkRoot 'ROADMAP.md'),
    (Join-Path $liveRepositoryRoot 'scripts\register-project.ps1'),(Join-Path $liveRepositoryRoot 'scripts\upgrade-project.ps1')
) + @($actual | Where-Object { $_ -cne 'tests/run-framework-tests.ps1' } | ForEach-Object { Join-Path $candidateRoot $_ })
$forbiddenVersionSelectorTerms = @(
    ('framework' + '/' + 'CURRENT'),('framework' + '\' + 'CURRENT'),('CURRENT' + '-default'),
    ('live roots/' + 'CURRENT'),('CURRENT' + ' is not authority')
)
$selectorHits = @()
foreach ($path in $selectorScope) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    foreach ($term in $forbiddenVersionSelectorTerms) {
        if ($text.Contains($term)) { $selectorHits += ($path + '|' + $term) }
    }
}
Assert-True ($selectorHits.Count -eq 0) 'version-selector-terminology-absent-from-live-root-and-1.11-runtime'

$loader = Join-Path $candidateRoot 'scripts\resolve-load-plan.ps1'
$normalLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX')
$maintenanceLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX','-Topology','FRAMEWORK_MAINTENANCE_SIBLING')
Assert-True ($normalLoad.Code -eq 0 -and $normalLoad.Text.Contains('routeSource=EXPLICIT_NO_TASK') -and $normalLoad.Text.Contains('topology=REPO_LOCAL') -and -not $normalLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md')) 'loader-explicit-no-task-compatible-with-evidence-ceiling'
Assert-True ($maintenanceLoad.Code -eq 0 -and $maintenanceLoad.Text.Contains('topology=FRAMEWORK_MAINTENANCE_SIBLING') -and $maintenanceLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md')) 'loader-maintenance-module-mandatory'

$normalProjectTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\project.json') -Raw -Encoding utf8
$normalControllerTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\controller.json') -Raw -Encoding utf8
try {
    $null = $normalProjectTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{DISPLAY_NAME_JSON}}','"Fixture"').Replace('{{FRAMEWORK_VERSION_JSON}}','"1.12.0"') | ConvertFrom-Json
    $null = $normalControllerTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{CONTROLLER_ID_JSON}}','"controller"') | ConvertFrom-Json
    $normalStarterRendered = $true
} catch { $normalStarterRendered = $false }
Assert-True $normalStarterRendered 'repo-local-starter-json-renders'

$starterActual = @(Get-ChildItem -LiteralPath (Join-Path $candidateRoot 'framework-maintenance-starter') -Recurse -Force -File | ForEach-Object { $_.FullName.Substring((Join-Path $candidateRoot 'framework-maintenance-starter').Length + 1).Replace('\','/') })
Assert-True ($starterActual.Count -eq 10 -and $starterActual -contains 'corrections.json') 'maintenance-starter-exact10-with-corrections'

$workflowEntryDocuments = @('TASK_AND_SCOPE.md','HOST_CODEX.md','PROMPTS.md','project-starter/BOOTSTRAP.md','framework-maintenance-starter/BOOTSTRAP.md')
foreach ($relative in $workflowEntryDocuments) {
    $entryText = Get-Content -LiteralPath (Join-Path $candidateRoot $relative) -Raw -Encoding utf8
    Assert-True ($entryText.Contains('WORKFLOW_ROUTE_RESOLVE') -and $entryText.Contains('TOOLCHAIN.json') -and $entryText.Contains('ephemeral') -and $entryText.Contains('fails closed')) ('workflow-live-entry-fail-closed|' + $relative)
}

$releaseGovernanceText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'FRAMEWORK_RELEASE.md')
$reviewEvidenceText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'REVIEW_AND_EVIDENCE.md')
$projectControlText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROJECT_CONTROL.md')
Assert-True ($releaseGovernanceText.Contains('Coverage ID, changelog statement or approximately similar prose is not acceptance evidence by itself')-or$reviewEvidenceText.Contains('coverage ID, changelog statement or approximately similar prose is not acceptance evidence by itself')) 'correction-incorporation-coverage-metadata-alone-insufficient'
Assert-True ($releaseGovernanceText.Contains('applicable normative modules')-and$releaseGovernanceText.Contains('direct behavioral tests')-and$reviewEvidenceText.Contains('original correction reason')-and$projectControlText.Contains('No correction-to-module registry or absorption ledger')) 'correction-incorporation-binds-normative-modules-tests-review-without-registry'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('aiw-framework-111-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $workflowResolver = Join-Path $candidateRoot 'scripts\resolve-workflow-route.ps1'
    $launchRecovery = Invoke-WorkflowCase $workflowResolver $temp 'launch-recovery' ([ordered]@{operation='LAUNCH';recoveryComplete=$true;packageValid=$false;bindingsMatch=$true})
    $launchReady = Invoke-WorkflowCase $workflowResolver $temp 'launch-ready' ([ordered]@{operation='LAUNCH';recoveryComplete=$true;packageValid=$true;bindingsMatch=$true})
    Assert-True ($launchRecovery.Run.Code -eq 0 -and [string]$launchRecovery.Value.status -ceq 'RECOVERY_READY' -and -not [bool]$launchRecovery.Value.writerActive -and -not [bool]$launchRecovery.Value.recoveryIsAuthority) 'workflow-launch-recovery-does-not-open-writer'
    Assert-True ($launchReady.Run.Code -eq 0 -and [string]$launchReady.Value.status -ceq 'IMPLEMENTATION_READY' -and [bool]$launchReady.Value.writerActive) 'workflow-launch-valid-package-and-bindings-open-writer'

    $routeBase = [ordered]@{operation='ROUTE';projectMatch=$true;cwdGitTopMatch=$true;outcomeMatch=$true;taskOwnerMatch=$true;actorEligible=$true;lineageMatch=$true;resourceRouteAvailable=$true;protectionBoundaryMatch=$true;gitDeviceExternalMatch=$true;publicDecisionMatch=$true;requiresDistinctOutcome=$false;requiresIndependentContext=$false;standingCreateAuthorized=$false}
    $routeReuse = Invoke-WorkflowCase $workflowResolver $temp 'route-reuse' $routeBase
    $routeNewInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeNewInput[$key]=$routeBase[$key] }; $routeNewInput.outcomeMatch=$false; $routeNewInput.requiresDistinctOutcome=$true; $routeNewInput.standingCreateAuthorized=$true
    $routeNew = Invoke-WorkflowCase $workflowResolver $temp 'route-new' $routeNewInput
    $routeBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeBlockedInput[$key]=$routeBase[$key] }; $routeBlockedInput.protectionBoundaryMatch=$false
    $routeBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-blocked' $routeBlockedInput
    $routeCwdBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeCwdBlockedInput[$key]=$routeBase[$key] }; $routeCwdBlockedInput.cwdGitTopMatch=$false
    $routeCwdBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-cwd-blocked' $routeCwdBlockedInput
    $routePublicBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routePublicBlockedInput[$key]=$routeBase[$key] }; $routePublicBlockedInput.publicDecisionMatch=$false
    $routePublicBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-public-blocked' $routePublicBlockedInput
    $routeActorBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeActorBlockedInput[$key]=$routeBase[$key] }; $routeActorBlockedInput.actorEligible=$false
    $routeActorBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-actor-blocked' $routeActorBlockedInput
    $routeResourceNewInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeResourceNewInput[$key]=$routeBase[$key] }; $routeResourceNewInput.resourceRouteAvailable=$false
    $routeResourceNew = Invoke-WorkflowCase $workflowResolver $temp 'route-resource-new' $routeResourceNewInput
    $routeIndependentNewInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeIndependentNewInput[$key]=$routeBase[$key] }; $routeIndependentNewInput.requiresIndependentContext=$true
    $routeIndependentNew = Invoke-WorkflowCase $workflowResolver $temp 'route-independent-new' $routeIndependentNewInput
    Assert-True ([string]$routeReuse.Value.decision -ceq 'REUSE' -and -not [bool]$routeReuse.Value.standingCreate) 'workflow-route-reuses-same-authority-and-outcome'
    Assert-True ([string]$routeNew.Value.decision -ceq 'MUST_NEW' -and [bool]$routeNew.Value.standingCreate -and [string]$routeNew.Value.reason -ceq 'STANDING_CREATE_AUTHORIZED') 'workflow-route-must-new-with-standing-create-authorization'
    Assert-True ([string]$routeBlocked.Value.decision -ceq 'BLOCKED' -and -not [bool]$routeBlocked.Value.standingCreate) 'workflow-route-blocks-protection-boundary-mismatch'
    Assert-True ([string]$routeCwdBlocked.Value.decision -ceq 'BLOCKED' -and [string]$routeCwdBlocked.Value.reason -ceq 'CWD_GIT_TOP_MISMATCH') 'workflow-route-blocks-cwd-git-top-mismatch'
    Assert-True ([string]$routePublicBlocked.Value.decision -ceq 'BLOCKED' -and [string]$routePublicBlocked.Value.reason -ceq 'PUBLIC_DECISION_MISMATCH') 'workflow-route-blocks-public-decision-change'
    Assert-True ([string]$routeActorBlocked.Value.decision -ceq 'BLOCKED' -and [string]$routeActorBlocked.Value.reason -ceq 'ACTOR_NOT_ELIGIBLE') 'workflow-route-rejects-ineligible-cross-domain-actor'
    Assert-True ([string]$routeResourceNew.Value.decision -ceq 'MUST_NEW' -and [string]$routeResourceNew.Value.reason -ceq 'RESOURCE_ROUTE_REQUIRES_NEW_CONTEXT') 'workflow-route-resource-unavailable-requires-new-context'
    Assert-True ([string]$routeIndependentNew.Value.decision -ceq 'MUST_NEW' -and [string]$routeIndependentNew.Value.reason -ceq 'INDEPENDENT_CONTEXT_REQUIRED') 'workflow-route-independent-reviewer-full-context'
    Assert-True ($routeReuse.Run.Code -eq 0 -and [string]$routeReuse.Value.decision -ceq 'REUSE') 'workflow-route-owner-self-exec-or-qualified-actor-keeps-task-owner'

    $terminalDelivered = Invoke-WorkflowCase $workflowResolver $temp 'terminal-delivered' ([ordered]@{operation='TERMINAL';terminalStatus='COMPLETE';reportChannelAvailable=$true;proposedConsumerRole='TASK_OWNER';controllerEscalationRequired=$false})
    $terminalReview = Invoke-WorkflowCase $workflowResolver $temp 'terminal-review' ([ordered]@{operation='TERMINAL';terminalStatus='READY';reportChannelAvailable=$true;proposedConsumerRole='INDEPENDENT_REVIEWER';controllerEscalationRequired=$false})
    $terminalControllerRejected = Invoke-WorkflowCase $workflowResolver $temp 'terminal-controller-rejected' ([ordered]@{operation='TERMINAL';terminalStatus='READY';reportChannelAvailable=$true;proposedConsumerRole='CONTROLLER';controllerEscalationRequired=$false})
    $terminalControllerAccepted = Invoke-WorkflowCase $workflowResolver $temp 'terminal-controller-accepted' ([ordered]@{operation='TERMINAL';terminalStatus='BLOCKED';reportChannelAvailable=$true;proposedConsumerRole='CONTROLLER';controllerEscalationRequired=$true})
    $terminalUnavailable = Invoke-WorkflowCase $workflowResolver $temp 'terminal-unavailable' ([ordered]@{operation='TERMINAL';terminalStatus='BLOCKED';reportChannelAvailable=$false;proposedConsumerRole='TASK_OWNER';controllerEscalationRequired=$false})
    Assert-True ([string]$terminalDelivered.Value.status -ceq 'COMPLETE' -and [string]$terminalDelivered.Value.delivery -ceq 'PROACTIVE' -and -not [bool]$terminalDelivered.Value.ackRequired -and -not [bool]$terminalDelivered.Value.polling) 'workflow-terminal-proactive-no-ack-no-poll'
    Assert-True ([string]$terminalReview.Value.status -ceq 'READY' -and [string]$terminalReview.Value.reason -ceq 'DIRECT_CONSUMER_ROUTE') 'workflow-terminal-direct-writer-to-reviewer-route'
    Assert-True ([string]$terminalControllerRejected.Value.status -ceq 'REJECT' -and [string]$terminalControllerRejected.Value.reason -ceq 'UNNECESSARY_CONTROLLER_RELAY') 'workflow-terminal-rejects-unnecessary-controller-relay'
    Assert-True ([string]$terminalControllerAccepted.Value.status -ceq 'BLOCKED' -and [string]$terminalControllerAccepted.Value.delivery -ceq 'PROACTIVE') 'workflow-terminal-allows-real-controller-escalation'
    Assert-True ([string]$terminalUnavailable.Value.status -ceq 'REPORT_CHANNEL_UNAVAILABLE' -and [string]$terminalUnavailable.Value.delivery -ceq 'UNAVAILABLE') 'workflow-terminal-report-channel-unavailable-is-terminal'

    $messageBase = [ordered]@{operation='MESSAGE';hostAuthenticated=$true;expectedTaskId='task-1';observedTaskId='task-1';expectedSender='sender-1';observedSender='sender-1';expectedControllerEpoch=2;observedControllerEpoch=2;expectedEnvelope='envelope-1';observedEnvelope='envelope-1'}
    $messageAccept = Invoke-WorkflowCase $workflowResolver $temp 'message-accept' $messageBase
    $messageStaleInput = [ordered]@{}; foreach ($key in $messageBase.Keys) { $messageStaleInput[$key]=$messageBase[$key] }; $messageStaleInput.observedControllerEpoch=1
    $messageStale = Invoke-WorkflowCase $workflowResolver $temp 'message-stale' $messageStaleInput
    $messageUnauthenticatedInput = [ordered]@{}; foreach ($key in $messageBase.Keys) { $messageUnauthenticatedInput[$key]=$messageBase[$key] }; $messageUnauthenticatedInput.hostAuthenticated=$false
    $messageUnauthenticated = Invoke-WorkflowCase $workflowResolver $temp 'message-unauthenticated' $messageUnauthenticatedInput
    Assert-True ([string]$messageAccept.Value.status -ceq 'ACCEPT' -and [string]$messageAccept.Value.reason -ceq 'HOST_ENVELOPE_MATCH') 'workflow-message-exact-host-envelope-accepted'
    Assert-True ([string]$messageStale.Value.status -ceq 'REJECT' -and [string]$messageStale.Value.reason -ceq 'STALE_OR_MISROUTED_ENVELOPE') 'workflow-message-stale-controller-epoch-rejected'
    Assert-True ([string]$messageUnauthenticated.Value.status -ceq 'REJECT' -and [string]$messageUnauthenticated.Value.reason -ceq 'HOST_AUTHENTICITY_UNAVAILABLE') 'workflow-message-host-authenticity-unavailable-rejected'

    $duplicateLaunch = Invoke-WorkflowRawCase $workflowResolver $temp 'duplicate-launch' '{"operation":"LAUNCH","recoveryComplete":false,"recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    $duplicateMessage = Invoke-WorkflowRawCase $workflowResolver $temp 'duplicate-message' '{"operation":"MESSAGE","hostAuthenticated":false,"hostAuthenticated":true,"expectedTaskId":"task-1","observedTaskId":"task-1","expectedSender":"sender-1","observedSender":"sender-1","expectedControllerEpoch":2,"observedControllerEpoch":2,"expectedEnvelope":"envelope-1","observedEnvelope":"envelope-1"}'
    $duplicateOperation = Invoke-WorkflowRawCase $workflowResolver $temp 'duplicate-operation' '{"operation":"LAUNCH","operation":"LAUNCH","recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    $unicodeDuplicateLaunch = Invoke-WorkflowRawCase $workflowResolver $temp 'unicode-duplicate-launch' '{"operation":"LAUNCH","recoveryComplete":false,"\u0072ecoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    $unicodeDuplicateMessage = Invoke-WorkflowRawCase $workflowResolver $temp 'unicode-duplicate-message' '{"operation":"MESSAGE","hostAuthenticated":false,"\u0068ostAuthenticated":true,"expectedTaskId":"task-1","observedTaskId":"task-1","expectedSender":"sender-1","observedSender":"sender-1","expectedControllerEpoch":2,"observedControllerEpoch":2,"expectedEnvelope":"envelope-1","observedEnvelope":"envelope-1"}'
    $unicodeDuplicateOperation = Invoke-WorkflowRawCase $workflowResolver $temp 'unicode-duplicate-operation' '{"operation":"LAUNCH","\u006fperation":"LAUNCH","recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    Assert-True ($duplicateLaunch.Code -ne 0 -and $duplicateLaunch.Text.Contains('INPUT_FIELD_COUNT|recoveryComplete')) 'workflow-strict-json-rejects-duplicate-launch-field'
    Assert-True ($duplicateMessage.Code -ne 0 -and $duplicateMessage.Text.Contains('INPUT_FIELD_COUNT|hostAuthenticated')) 'workflow-strict-json-rejects-authenticity-sensitive-duplicate-field'
    Assert-True ($duplicateOperation.Code -ne 0 -and $duplicateOperation.Text.Contains('INPUT_FIELD_COUNT|operation')) 'workflow-strict-json-rejects-duplicate-operation'
    Assert-True ($unicodeDuplicateLaunch.Code -ne 0 -and $unicodeDuplicateLaunch.Text.Contains('INPUT_FIELD_COUNT|recoveryComplete')) 'workflow-strict-json-rejects-unicode-equivalent-launch-field'
    Assert-True ($unicodeDuplicateMessage.Code -ne 0 -and $unicodeDuplicateMessage.Text.Contains('INPUT_FIELD_COUNT|hostAuthenticated')) 'workflow-strict-json-rejects-unicode-equivalent-authenticity-field'
    Assert-True ($unicodeDuplicateOperation.Code -ne 0 -and $unicodeDuplicateOperation.Text.Contains('INPUT_FIELD_COUNT|operation')) 'workflow-strict-json-rejects-unicode-equivalent-operation'

    $handoffBase = [ordered]@{operation='HANDOFF';predecessorControllerId='controller-old';successorControllerId='controller-new';previousEpoch=1;newEpoch=2;controllerWrittenLast=$true;controllerState='CURRENT';takeoverRecorded=$true;retirementAuthorized=$false}
    $handoffComplete = Invoke-WorkflowCase $workflowResolver $temp 'handoff-complete' $handoffBase
    $handoffInvalidInput = [ordered]@{}; foreach ($key in $handoffBase.Keys) { $handoffInvalidInput[$key]=$handoffBase[$key] }; $handoffInvalidInput.newEpoch=1
    $handoffInvalid = Invoke-WorkflowCase $workflowResolver $temp 'handoff-invalid' $handoffInvalidInput
    Assert-True ([string]$handoffComplete.Value.status -ceq 'TAKEOVER_COMPLETE' -and [bool]$handoffComplete.Value.readOnlyGrace -and -not [bool]$handoffComplete.Value.retired) 'workflow-handoff-takeover-complete-read-only-grace-no-retirement'
    Assert-True ([string]$handoffInvalid.Value.status -ceq 'REJECT' -and [string]$handoffInvalid.Value.reason -ceq 'INVALID_HANDOFF') 'workflow-handoff-invalid-epoch-rejected'

    $hotState = Invoke-WorkflowCase $workflowResolver $temp 'hot-state-minimal' ([ordered]@{operation='HOT_STATE';currentCardCurrentOnly=$true;supersededHistoryArchived=$true;taskLifecycleChanged=$false;routingChanged=$false;stableProjectPhaseChanged=$false;longLivedOwnerChanged=$false;protectedSetChanged=$false;uniqueNextActionChanged=$false;routineActorChanged=$true})
    $hotStateInvalid = Invoke-WorkflowCase $workflowResolver $temp 'hot-state-invalid' ([ordered]@{operation='HOT_STATE';currentCardCurrentOnly=$false;supersededHistoryArchived=$false;taskLifecycleChanged=$true;routingChanged=$true;stableProjectPhaseChanged=$true;longLivedOwnerChanged=$true;protectedSetChanged=$true;uniqueNextActionChanged=$true;routineActorChanged=$true})
    Assert-True ([string]$hotState.Value.status -ceq 'ACCEPT' -and [bool]$hotState.Value.taskCardUpdate -and -not [bool]$hotState.Value.taskIndexUpdate -and -not [bool]$hotState.Value.statusUpdate) 'workflow-hot-state-routine-actor-stays-on-task-card'
    Assert-True ([string]$hotStateInvalid.Value.status -ceq 'REJECT' -and -not [bool]$hotStateInvalid.Value.taskCardUpdate -and -not [bool]$hotStateInvalid.Value.taskIndexUpdate -and -not [bool]$hotStateInvalid.Value.statusUpdate) 'workflow-hot-state-rejects-active-archive-layer-violation'

    $taskChecker = Join-Path $candidateRoot 'scripts\check-task-card.ps1'
    $criticalTaskPath = Join-Path $temp 'TASK-PROPORTIONALITY-001.md'
    $criticalTask = @'
# TASK-PROPORTIONALITY-001 - fixture

- Task schema: 1.12.0
- Owner: owner-fixture
- Work route: role=DOMAIN_OWNER; phase=PLAN
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=fixture-candidate; expected_paths=[]; actual_paths=[]
- Phase gate: FALSE
- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=clarify existing route and add one narrow rejection; added_machinery=NONE; escalation_trigger=repeated natural deviation across independent sessions
'@
    Write-Utf8 $criticalTaskPath $criticalTask
    $criticalTaskValid = Invoke-Ps $taskChecker @('-TaskPath',$criticalTaskPath)
    if($criticalTaskValid.Code -ne 0 -or -not$criticalTaskValid.Text.Contains('profile=CRITICAL')){Write-Output ('DIAG|task-card-critical-proportionality-valid|code='+$criticalTaskValid.Code+'|text='+$criticalTaskValid.Text)}
    Assert-True ($criticalTaskValid.Code -eq 0 -and $criticalTaskValid.Text.Contains('profile=CRITICAL')) 'task-card-critical-proportionality-valid'
    Write-Utf8 $criticalTaskPath ($criticalTask -replace '(?m)^- Proportionality:.*(?:\n|$)','')
    $criticalTaskMissing = Invoke-Ps $taskChecker @('-TaskPath',$criticalTaskPath)
    Assert-True ($criticalTaskMissing.Code -ne 0 -and $criticalTaskMissing.Text.Contains('PROPORTIONALITY_FIELD')) 'task-card-critical-proportionality-required'
    Write-Utf8 $criticalTaskPath ($criticalTask -replace 'existing=partial','existing=sufficient' -replace 'added_machinery=NONE','added_machinery=service:1')
    $criticalTaskContradiction = Invoke-Ps $taskChecker @('-TaskPath',$criticalTaskPath)
    Assert-True ($criticalTaskContradiction.Code -ne 0 -and $criticalTaskContradiction.Text.Contains('PROPORTIONALITY_CONTRADICTION')) 'task-card-proportionality-blocks-machinery-when-existing-sufficient'
    $standardTaskPath = Join-Path $temp 'TASK-STANDARD-001.md'
    Write-Utf8 $standardTaskPath "# TASK-STANDARD-001 - fixture`n`n- Task schema: 1.12.0`n- Owner: owner-fixture`n- Work route: role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $standardTaskValid = Invoke-Ps $taskChecker @('-TaskPath',$standardTaskPath)
    Assert-True ($standardTaskValid.Code -eq 0 -and $standardTaskValid.Text.Contains('loadContext=DECLARED') -and $standardTaskValid.Text.Contains('role=EXECUTOR') -and $standardTaskValid.Text.Contains('phase=IMPLEMENT')) 'task-card-standard-declared-work-route'
    $taskBoundLoad=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-IncludeRecovery','-HostName','CODEX')
    Assert-True ($taskBoundLoad.Code-eq0-and$taskBoundLoad.Text.Contains('routeSource=TASK_CARD')-and$taskBoundLoad.Text.Contains('phases=RECOVER,IMPLEMENT')-and$taskBoundLoad.Text.Contains('PROJECT_CONTROL.md')-and$taskBoundLoad.Text.Contains('TASK_AND_SCOPE.md')) 'loader-task-bound-recover-plus-work-phase'
    $taskRouteDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-Role','REVIEWER','-Profile','STANDARD','-Phase','IMPLEMENT','-HostName','CODEX')
    Assert-True ($taskRouteDrift.Code-ne0-and$taskRouteDrift.Text.Contains('LOAD_TASK_ROLE_DRIFT')) 'loader-rejects-caller-role-drift'
    Write-Utf8 $standardTaskPath "# TASK-STANDARD-001 - fixture`n`n- Task schema: 1.12.0`n- Owner: owner-fixture`n- Work route: role=REVIEWER; phase=REVIEW`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $reviewTaskLoad=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-HostName','CODEX')
    Assert-True ($reviewTaskLoad.Code-eq0-and$reviewTaskLoad.Text.Contains('routeSource=TASK_CARD')-and$reviewTaskLoad.Text.Contains('phases=REVIEW')-and$reviewTaskLoad.Text.Contains('TASK_AND_SCOPE.md')-and$reviewTaskLoad.Text.Contains('REVIEW_AND_EVIDENCE.md')-and-not$reviewTaskLoad.Text.Contains('PROJECT_CONTROL.md')) 'loader-task-bound-review-transition-workset'
    $taskPhaseDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-Role','REVIEWER','-Profile','STANDARD','-Phase','IMPLEMENT','-HostName','CODEX')
    Assert-True ($taskPhaseDrift.Code-ne0-and$taskPhaseDrift.Text.Contains('LOAD_TASK_PHASE_DRIFT')) 'loader-rejects-caller-phase-drift'
    $taskProfileDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-Role','REVIEWER','-Profile','CRITICAL','-Phase','REVIEW','-HostName','CODEX')
    Assert-True ($taskProfileDrift.Code-ne0-and$taskProfileDrift.Text.Contains('LOAD_TASK_PROFILE_DRIFT')) 'loader-rejects-caller-profile-drift'
    $missingRouteTaskPath=Join-Path $temp 'TASK-MISSING-ROUTE-001.md'
    Write-Utf8 $missingRouteTaskPath "# TASK-MISSING-ROUTE-001 - fixture`n`n- Task schema: 1.12.0`n- Owner: owner-fixture`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $missingRouteCheck=Invoke-Ps $taskChecker @('-TaskPath',$missingRouteTaskPath)
    $missingRouteLoad=Invoke-Ps $loader @('-TaskPath',$missingRouteTaskPath,'-Role','EXECUTOR','-Profile','STANDARD','-Phase','IMPLEMENT')
    Assert-True ($missingRouteCheck.Code-ne0-and$missingRouteCheck.Text.Contains('WORK_ROUTE_FIELD')-and$missingRouteLoad.Code-ne0-and$missingRouteLoad.Text.Contains('LOAD_TASK_WORK_ROUTE_REQUIRED')) 'schema-1.11-work-route-required'
    $legacyTaskPath=Join-Path $temp 'TASK-LEGACY-LOAD-001.md'
    Write-Utf8 $legacyTaskPath "# TASK-LEGACY-LOAD-001 - fixture`n`n- Task schema: 1.10.0`n- Owner: owner-fixture`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $legacyTaskCheck=Invoke-Ps $taskChecker @('-TaskPath',$legacyTaskPath)
    $legacyLoad=Invoke-Ps $loader @('-TaskPath',$legacyTaskPath,'-Role','EXECUTOR','-Profile','STANDARD','-Phase','IMPLEMENT','-IncludeRecovery')
    Assert-True ($legacyTaskCheck.Code-eq0-and$legacyTaskCheck.Text.Contains('loadContext=LEGACY_LOAD_CONTEXT')-and$legacyLoad.Code-eq0-and$legacyLoad.Text.Contains('routeSource=LEGACY_LOAD_CONTEXT')-and$legacyLoad.Text.Contains('ROLE_PHASE_EXPLICITLY_INFERRED_FROM_LEGACY_TASK')) 'legacy-task-explicit-route-fallback-visible'

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
    Copy-Item -LiteralPath $candidateRoot -Destination (Join-Path $target 'framework\versions\1.12.0') -Recurse
    Write-Utf8 (Join-Path $target 'docs\public.txt') 'public target'
    Write-Utf8 (Join-Path $target 'private\secret.txt') 'private target'
    $configIdentity = Get-Identity $configPath

    $installedFramework = Join-Path $target 'framework\versions\1.12.0'
    $installedActual = @(Get-ChildItem -LiteralPath $installedFramework -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($installedFramework.Length + 1).Replace('\','/') })
    [Array]::Sort($installedActual,[StringComparer]::Ordinal)
    Assert-True ($installedActual.Count -eq 59 -and ($installedActual -join "`n") -ceq ($actual -join "`n")) 'maintenance-target-full-candidate-installed'
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
    Assert-True ($fullColdLoad.Code -eq 0 -and $fullColdLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md') -and $renderedBootstrap.Contains('state=CURRENT') -and -not $renderedBootstrap.Contains('AllowLegacyTargetControlPlane') -and $renderedBootstrap.Contains('Explicitly read `<TARGET>/AGENTS.md`') -and $renderedBootstrap.Contains('WORKFLOW_ROUTE_RESOLVE') -and $renderedBootstrap.Contains('TOOLCHAIN.json')) 'maintenance-bootstrap-final-full-cold-route-from-installed-framework'

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
    Assert-True ($missingPin.Code -ne 0 -and $missingPin.Text.Contains('TARGET_REQUIRED_FILE_MISSING|framework/versions/1.12.0/RECOVERY_CORE.md')) 'maintenance-resolver-pin-entry-missing-rejected'

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

    $batchWrapper = Join-Path $controlPlane 'invoke-batch-authorization.ps1'
    Write-Utf8 $batchWrapper @'
param([string]$Checker,[string]$Package,[string]$ObjectPath,[string]$ObjectIdentity,[string]$ConfigIdentity,[switch]$Duplicate)
$actions=if($Duplicate){@('SOURCE_WRITE','SOURCE_WRITE')}else{@('SOURCE_WRITE','TEST_RUN')}
& $Checker -PackagePath $Package -ObservedActor 'controller-fixture' -ObservedTaskId 'FIXTURE-001' -ObservedOwner 'controller-fixture' -ObservedAction $actions -ObservedPath @($ObjectPath) -ObservedIdentity @($ObjectPath+'='+$ObjectIdentity) -ControllerControlPath '.ai-workspace/controller.json' -ObservedRepositoryId 'ai-workspace-framework' -ProjectConfigPath '.ai-workspace/project.json' -ExpectedProjectConfigIdentity $ConfigIdentity
exit $LASTEXITCODE
'@
    $batchArgs=@('-Checker',$checker,'-Package',$targetPackage,'-ObjectPath',$targetObject,'-ObjectIdentity',(Get-Identity (Join-Path $target $targetObject)),'-ConfigIdentity',$configIdentity)
    $batchAuth=Invoke-Ps $batchWrapper $batchArgs $control
    $batchPassCount=@($batchAuth.Output|Where-Object{$_ -like 'PASS|*'}).Count
    Assert-True ($batchAuth.Code -eq 0 -and $batchPassCount -eq 2 -and $batchAuth.Text.Contains('action=SOURCE_WRITE') -and $batchAuth.Text.Contains('action=TEST_RUN')) 'authorization-action-batch-per-action-pass'
    $duplicateBatch=Invoke-Ps $batchWrapper @($batchArgs + '-Duplicate') $control
    Assert-True ($duplicateBatch.Code -ne 0 -and $duplicateBatch.Text.Contains('OBSERVED_ACTION_DUPLICATE')) 'authorization-action-batch-duplicate-rejected'

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
    $repoLocalConfig = [ordered]@{schemaVersion=3;id='repo-local-fixture';displayName='Repo Local Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.12.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('private/secret.txt');frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false}}}
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

    $criticalReviewPackagePath = Join-Path $repoLocal '.ai-workspace\critical-review-auth.json'
    $criticalReviewPackage = [ordered]@{
        schemaVersion=1;frameworkVersion='1.12.0';taskId='FIXTURE-REVIEW-001';profile='CRITICAL';lifecycle='ACTIVE'
        owner='owner-fixture';issuer='owner-fixture';issuerRole='DOMAIN_OWNER';grantee='reviewer-fixture';bundle='REVIEW_LOCAL'
        decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='INDEPENDENT';delegatedGitCloser=$false
        actions=@('REVIEW_EXECUTE');exactPaths=@($repoLocalObject);objectIdentities=@([ordered]@{path=$repoLocalObject;identity=$repoLocalObjectIdentity})
        invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','CONTRIBUTOR_SET_CHANGE')
        candidateWriter='cross-domain-writer';materialContributors=@('material-designer')
    }
    Write-Utf8 $criticalReviewPackagePath ($criticalReviewPackage|ConvertTo-Json -Depth 20)
    $criticalReviewArgs=@('-PackagePath',$criticalReviewPackagePath,'-ObservedActor','reviewer-fixture','-ObservedTaskId','FIXTURE-REVIEW-001','-ObservedOwner','owner-fixture','-ObservedAction','REVIEW_EXECUTE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $criticalReviewDirect=Invoke-Ps $checker $criticalReviewArgs $repoLocal
    Assert-True ($criticalReviewDirect.Code -eq 0) 'authorization-domain-owner-direct-review-package-with-cross-domain-writer-pass'
    foreach($disqualified in @('owner-fixture','cross-domain-writer','material-designer')){
        $badReview=$criticalReviewPackage|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $badReview.grantee=$disqualified
        Write-Utf8 $criticalReviewPackagePath ($badReview|ConvertTo-Json -Depth 20)
        $badReviewArgs=@('-PackagePath',$criticalReviewPackagePath,'-ObservedActor',$disqualified,'-ObservedTaskId','FIXTURE-REVIEW-001','-ObservedOwner','owner-fixture','-ObservedAction','REVIEW_EXECUTE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
        $badReviewRun=Invoke-Ps $checker $badReviewArgs $repoLocal
        Assert-True ($badReviewRun.Code -ne 0 -and $badReviewRun.Text.Contains('CRITICAL_REVIEW_NOT_INDEPENDENT')) ('authorization-critical-review-rejects-'+$disqualified)
    }
    Write-Utf8 $criticalReviewPackagePath ($criticalReviewPackage|ConvertTo-Json -Depth 20)

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

    $correctionChecker=Join-Path $candidateRoot 'scripts\check-project-corrections.ps1'
    $correctionFrameworkRoot=Join-Path $temp 'correction-framework-fixture';New-Item -ItemType Directory -Path (Join-Path $correctionFrameworkRoot 'framework\versions') -Force|Out-Null
    Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.9.0') -Destination (Join-Path $correctionFrameworkRoot 'framework\versions\1.9.0') -Recurse
    Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.10.0') -Destination (Join-Path $correctionFrameworkRoot 'framework\versions\1.10.0') -Recurse
    Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.11.0') -Destination (Join-Path $correctionFrameworkRoot 'framework\versions\1.11.0') -Recurse
    Copy-Item -LiteralPath $candidateRoot -Destination (Join-Path $correctionFrameworkRoot 'framework\versions\1.12.0') -Recurse
    $null=Seal-ReleaseFixture (Join-Path $correctionFrameworkRoot 'framework\versions\1.12.0') 'CORRECTION_TEST_FIXTURE'
    $correctionRoot=Join-Path $temp 'correction-fixture'
    New-Item -ItemType Directory -Path (Join-Path $correctionRoot '.ai-workspace') -Force|Out-Null
    $correctionConfig=[ordered]@{schemaVersion=3;id='correction-fixture';displayName='Correction Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.9.0';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{}}
    $correctionConfigPath=Join-Path $correctionRoot '.ai-workspace\project.json';Write-Utf8 $correctionConfigPath ($correctionConfig|ConvertTo-Json -Depth 20)
    $correctionRecords=[ordered]@{schemaVersion=1;contractVersion='1.10.0';projectId='correction-fixture';corrections=@(
        [ordered]@{correctionId='OWNER_FIRST_DIRECT_DOMAIN_ROUTE';introducedAgainstFramework='<=1.8.0';requirementReason='Observed unnecessary Controller relay';effectiveRule='Domain owner routes directly';applicability='Unchanged domain task';decisionLocator='task:owner-first'},
        [ordered]@{correctionId='PROJECT_CORRECTION_LIFECYCLE';introducedAgainstFramework='1.9.0';requirementReason='No deterministic cross-version retention';effectiveRule='Retain and evaluate project correction records';applicability='Framework pin adoption and recovery';decisionLocator='task:correction-lifecycle'}
    )}
    $correctionPath=Join-Path $correctionRoot '.ai-workspace\corrections.json';Write-Utf8 $correctionPath ($correctionRecords|ConvertTo-Json -Depth 20)
    $correctionArgs=@('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.9.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')
    $correctionMatched=Invoke-Ps $correctionChecker $correctionArgs
    $correctionMatchedValue=$correctionMatched.Output[-1]|ConvertFrom-Json
    Assert-True ($correctionMatched.Code-eq0-and[string]$correctionMatchedValue.coverageStatus-ceq'MATCHED'-and@($correctionMatchedValue.incorporated).Count-eq1-and[string]$correctionMatchedValue.incorporated[0].correctionId-ceq'OWNER_FIRST_DIRECT_DOMAIN_ROUTE'-and@($correctionMatchedValue.stillEffective).Count-eq1-and[string]$correctionMatchedValue.stillEffective[0].correctionId-ceq'PROJECT_CORRECTION_LIFECYCLE') 'corrections-1.9-incorporated-vs-still-effective'
    $sealedCoveragePath=Join-Path $correctionFrameworkRoot 'framework\versions\1.12.0\CORRECTION_COVERAGE.json';$sealedCoverageOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $sealedCoveragePath
    $unboundCoverage=$sealedCoverageOriginal|ConvertFrom-Json;$entry19=@($unboundCoverage.versions|Where-Object{[string]$_.version-ceq'1.9.0'})[0];$entry19.incorporatedCorrectionIds=@($entry19.incorporatedCorrectionIds)+@('PROJECT_CORRECTION_LIFECYCLE');Write-Utf8 $sealedCoveragePath ($unboundCoverage|ConvertTo-Json -Depth 20)
    $unboundRun=Invoke-Ps $correctionChecker $correctionArgs;$unboundValue=$unboundRun.Output[-1]|ConvertFrom-Json
    Assert-True ($unboundRun.Code-eq0-and[string]$unboundValue.coverageStatus-ceq'INVALID_RETAINED'-and@($unboundValue.incorporated).Count-eq0-and@($unboundValue.stillEffective).Count-eq2) 'corrections-unbound-id-set-change-retains-all'
    Write-Utf8 $sealedCoveragePath $sealedCoverageOriginal
    $nonCumulative=$sealedCoverageOriginal|ConvertFrom-Json;$entry110=@($nonCumulative.versions|Where-Object{[string]$_.version-ceq'1.12.0'})[0];$entry110.incorporatedCorrectionIds=@($entry110.incorporatedCorrectionIds|Where-Object{[string]$_-cne'COMPACT_NON_INTERRUPT_DELIVERY'});Write-Utf8 $sealedCoveragePath ($nonCumulative|ConvertTo-Json -Depth 20);$null=Seal-ReleaseFixture (Split-Path -Parent $sealedCoveragePath) 'NONCUMULATIVE_TEST_FIXTURE'
    $nonCumulativeRun=Invoke-Ps $correctionChecker @($correctionArgs[0..4]+@('1.12.0')+$correctionArgs[6..($correctionArgs.Count-1)]);$nonCumulativeValue=$nonCumulativeRun.Output[-1]|ConvertFrom-Json
    Assert-True ($nonCumulativeRun.Code-eq0-and[string]$nonCumulativeValue.coverageStatus-ceq'INVALID_RETAINED'-and@($nonCumulativeValue.stillEffective).Count-eq2) 'corrections-coverage-must-be-cumulative'
    Write-Utf8 $sealedCoveragePath $sealedCoverageOriginal;$null=Seal-ReleaseFixture (Split-Path -Parent $sealedCoveragePath) 'CORRECTION_TEST_FIXTURE'
    $overlapCoverage=$sealedCoverageOriginal|ConvertFrom-Json;$entry110=@($overlapCoverage.versions|Where-Object{[string]$_.version-ceq'1.12.0'})[0];$entry110.conflictingCorrectionIds=@('OWNER_FIRST_DIRECT_DOMAIN_ROUTE');Write-Utf8 $sealedCoveragePath ($overlapCoverage|ConvertTo-Json -Depth 20);$null=Seal-ReleaseFixture (Split-Path -Parent $sealedCoveragePath) 'OVERLAP_TEST_FIXTURE'
    $overlapRun=Invoke-Ps $correctionChecker @($correctionArgs[0..4]+@('1.12.0')+$correctionArgs[6..($correctionArgs.Count-1)]);$overlapValue=$overlapRun.Output[-1]|ConvertFrom-Json
    Assert-True ($overlapRun.Code-eq0-and[string]$overlapValue.coverageStatus-ceq'INVALID_RETAINED'-and@($overlapValue.stillEffective).Count-eq2) 'corrections-coverage-incorporated-conflict-disjoint'
    Write-Utf8 $sealedCoveragePath $sealedCoverageOriginal;$null=Seal-ReleaseFixture (Split-Path -Parent $sealedCoveragePath) 'CORRECTION_TEST_FIXTURE'
    $correctionUnknown=Invoke-Ps $correctionChecker @($correctionArgs[0..4]+@('9.9.9')+$correctionArgs[6..($correctionArgs.Count-1)])
    $correctionUnknownValue=$correctionUnknown.Output[-1]|ConvertFrom-Json
    Assert-True ($correctionUnknown.Code-eq0-and[string]$correctionUnknownValue.coverageStatus-cne'MATCHED'-and@($correctionUnknownValue.incorporated).Count-eq0-and@($correctionUnknownValue.stillEffective).Count-eq2) 'corrections-unknown-coverage-retains-all'
    $correctionOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionPath
    $correctionDuplicate=$correctionOriginal-replace '"projectId"\s*:\s*"correction-fixture"',('"projectId": "correction-fixture",'+"`n"+'  "\u0070rojectId": "correction-fixture"')
    Write-Utf8 $correctionPath $correctionDuplicate
    $correctionDuplicateRun=Invoke-Ps $correctionChecker @('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.9.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')
    Assert-True ($correctionDuplicateRun.Code-ne0-and$correctionDuplicateRun.Text.Contains('CORRECTIONS_JSON_DUPLICATE_FIELD')) 'corrections-unicode-duplicate-field-fails-closed'
    Write-Utf8 $correctionPath $correctionOriginal
    $missingCorrectionRoot=Join-Path $temp 'correction-missing-fixture';New-Item -ItemType Directory -Path (Join-Path $missingCorrectionRoot '.ai-workspace') -Force|Out-Null
    $missingCorrectionConfigPath=Join-Path $missingCorrectionRoot '.ai-workspace\project.json';Write-Utf8 $missingCorrectionConfigPath (($correctionConfig|ConvertTo-Json -Depth 20).Replace('correction-fixture','correction-missing-fixture'))
    $missingCorrectionRun=Invoke-Ps $correctionChecker @('-ProjectRoot',$missingCorrectionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.9.0','-ExpectedProjectConfigIdentity',(Get-Identity $missingCorrectionConfigPath),'-Operation','PRECHECK','-AllowMissingCorrections','-AsJson')
    $missingCorrectionValue=$missingCorrectionRun.Output[-1]|ConvertFrom-Json
    Assert-True ($missingCorrectionRun.Code-eq0-and[string]$missingCorrectionValue.correctionsIdentity-ceq'MISSING'-and@($missingCorrectionValue.stillEffective).Count-eq0) 'corrections-legacy-missing-is-empty-set'

    if (-not $SkipRootMigration) {
        $rootFlow = Join-Path $temp 'root-flow-workspace'
        New-Item -ItemType Directory -Path (Join-Path $rootFlow 'scripts'),(Join-Path $rootFlow 'framework\versions') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $liveRepositoryRoot 'scripts\register-project.ps1') -Destination (Join-Path $rootFlow 'scripts\register-project.ps1')
        Copy-Item -LiteralPath (Join-Path $liveRepositoryRoot 'scripts\upgrade-project.ps1') -Destination (Join-Path $rootFlow 'scripts\upgrade-project.ps1')
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.7.0') -Destination (Join-Path $rootFlow 'framework\versions\1.7.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.8.0') -Destination (Join-Path $rootFlow 'framework\versions\1.8.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.9.0') -Destination (Join-Path $rootFlow 'framework\versions\1.9.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.10.0') -Destination (Join-Path $rootFlow 'framework\versions\1.10.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.11.0') -Destination (Join-Path $rootFlow 'framework\versions\1.11.0') -Recurse
        Copy-Item -LiteralPath $candidateRoot -Destination (Join-Path $rootFlow 'framework\versions\1.12.0') -Recurse
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $rootFlow 'framework\CURRENT'))) 'root-global-version-selector-absent'

        $fixtureManifestPath=Join-Path $rootFlow 'framework\versions\1.12.0\RELEASE_MANIFEST.json'
        $fixtureVersionPath=Join-Path $rootFlow 'framework\versions\1.12.0\VERSION.json'
        $fixtureVersion=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureVersionPath|ConvertFrom-Json
        $fixtureVersion.lifecycle='STABLE';$fixtureVersion.consumable=$true;$fixtureVersion.projectPinEligible=$true
        Write-Utf8 $fixtureVersionPath ($fixtureVersion|ConvertTo-Json -Depth 20)
        $fixtureManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureManifestPath|ConvertFrom-Json
        $fixtureManifest.lifecycle='STABLE'
        $fixtureManifest.sourceReview='PENDING';$fixtureManifest.releaseIntegration='PENDING'
        Write-Utf8 $fixtureManifestPath ($fixtureManifest|ConvertTo-Json -Depth 20)

        $register = Join-Path $rootFlow 'scripts\register-project.ps1'
        $consumer = Join-Path $rootFlow 'consumer-explicit'
        New-GitRepo $consumer
        $baseRegisterArgs=@('-ProjectId','explicit-fixture','-DisplayName','Explicit Fixture','-RepositoryPath',$consumer,'-ControllerId','controller-explicit')
        $missingVersion=Invoke-Ps $register $baseRegisterArgs
        Assert-True ($missingVersion.Code -ne 0 -and $missingVersion.Text.Contains('FrameworkVersion')) 'register-missing-explicit-version-rejected'
        $pendingRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.12.0'))
        Assert-True ($pendingRegister.Code -ne 0 -and $pendingRegister.Text.Contains('FRAMEWORK_RELEASE_NOT_SEALED|1.12.0')) 'register-pending-release-rejected-before-project-write'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $consumer '.ai-workspace'))) 'register-pending-release-zero-project-write'

        $fixtureVersionRoot=Split-Path -Parent $fixtureManifestPath
        $fixtureFacts=Seal-ReleaseFixture $fixtureVersionRoot 'TEST_FIXTURE_SEALED'
        $fixturePayload=$fixtureFacts.Files;$fixtureTotal=$fixtureFacts.TotalBytes;$fixtureCanonical=$fixtureFacts.Canonical;[string[]]$fixtureOrderedRows=@($fixtureFacts.Rows|Where-Object{-not ([string]$_).StartsWith('VERSION.json|',[StringComparison]::Ordinal)})
        $fixtureCoveragePath=Join-Path $fixtureVersionRoot 'CORRECTION_COVERAGE.json'
        $sourceRows=@()
        foreach($relative in @($actual|Where-Object{$_-cne'RELEASE_MANIFEST.json'-and$_-cne'VERSION.json'})){$full=Join-Path $candidateRoot $relative;$bytes=[IO.File]::ReadAllBytes($full);$sourceRows+=($relative+'|'+$bytes.Length+'|'+(Get-Identity $full).Split('|')[1])}
        [string[]]$sourceOrderedRows=@($sourceRows)
        [Array]::Sort($sourceOrderedRows,[StringComparer]::Ordinal)
        if(($sourceOrderedRows-join"`n")-cne($fixtureOrderedRows-join"`n")){
            $rowLimit=[Math]::Min($sourceOrderedRows.Count,$fixtureOrderedRows.Count)
            for($rowIndex=0;$rowIndex-lt$rowLimit;$rowIndex++){if([string]$sourceOrderedRows[$rowIndex]-cne[string]$fixtureOrderedRows[$rowIndex]){Write-Output ('DIAG|root-flow-row-drift|index='+$rowIndex+'|source='+$sourceOrderedRows[$rowIndex]+'|fixture='+$fixtureOrderedRows[$rowIndex]);break}}
        }
        $fixtureManifestCheck=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureManifestPath|ConvertFrom-Json
        if([int]$fixtureManifestCheck.fileCount-ne$fixturePayload.Count-or[int64]$fixtureManifestCheck.totalBytes-ne$fixtureTotal-or[string]$fixtureManifestCheck.canonical-cne$fixtureCanonical){Write-Output ('DIAG|root-flow-manifest|actual='+$fixturePayload.Count+'|'+$fixtureTotal+'|'+$fixtureCanonical+'|declared='+$fixtureManifestCheck.fileCount+'|'+$fixtureManifestCheck.totalBytes+'|'+$fixtureManifestCheck.canonical)}

        $shadowRepo=Join-Path $rootFlow 'consumer-shadow-record'
        New-GitRepo $shadowRepo
        $shadowRecord=Join-Path $rootFlow 'projects\shadow-fixture\project.json'
        Write-Utf8 $shadowRecord (([ordered]@{id='shadow-fixture';repositoryPath=$shadowRepo})|ConvertTo-Json -Depth 5)
        $shadowIdentity=Get-Identity $shadowRecord
        $shadowRegisterArgs=@('-ProjectId','shadow-fixture','-DisplayName','Shadow Fixture','-RepositoryPath',$shadowRepo,'-ControllerId','controller-shadow','-FrameworkVersion','1.7.0','-Apply')
        $shadowRegister=Invoke-Ps $register $shadowRegisterArgs
        Assert-True ($shadowRegister.Code -eq 0 -and $shadowRegister.Text.Contains('CREATED') -and (Get-Identity $shadowRecord) -ceq $shadowIdentity) 'register-explicit-repository-ignores-framework-owned-consumer-record'
        $upgrade=Join-Path $rootFlow 'scripts\upgrade-project.ps1'
        $shadowControlIdentity=Get-Identity (Join-Path $shadowRepo '.ai-workspace\project.json')
        $shadowUpgradeWithoutRepository=Invoke-Ps $upgrade @('-ProjectId','shadow-fixture','-ToVersion','1.12.0','-ControllerId','controller-shadow')
        Assert-True ($shadowUpgradeWithoutRepository.Code -ne 0 -and $shadowUpgradeWithoutRepository.Text.Contains('RepositoryPath') -and (Get-Identity (Join-Path $shadowRepo '.ai-workspace\project.json')) -ceq $shadowControlIdentity -and (Get-Identity $shadowRecord) -ceq $shadowIdentity) 'upgrade-missing-repository-rejected-even-when-framework-owned-record-exists'

        $previewRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.12.0'))
        if ($previewRegister.Code -ne 0 -or -not $previewRegister.Text.Contains('WHAT_IF')) { Write-Output ('DIAG|register-explicit-1.12.0-preview|' + $previewRegister.Code + '|' + $previewRegister.Text) }
        Assert-True ($previewRegister.Code -eq 0 -and $previewRegister.Text.Contains('WHAT_IF')) 'register-explicit-1.12.0-preview'
        $applyRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.12.0','-Apply'))
        Assert-True ($applyRegister.Code -eq 0 -and $applyRegister.Text.Contains('CREATED')) 'register-explicit-1.12.0-apply'
        $repeatRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.12.0'))
        Assert-True ($repeatRegister.Code -eq 0 -and $repeatRegister.Text.Contains('ALREADY_REGISTERED')) 'register-explicit-1.12.0-repeat'
        $registeredConfig=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.ai-workspace\project.json')|ConvertFrom-Json
        $registeredBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.ai-workspace\BOOTSTRAP.md')
        $registeredFiles=@(Get-ChildItem -LiteralPath (Join-Path $consumer '.ai-workspace') -Recurse -File -Force)
        $registeredCorrections=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.ai-workspace\corrections.json')|ConvertFrom-Json
        Assert-True ([string]$registeredConfig.frameworkVersion -ceq '1.12.0' -and [string]$registeredConfig.frameworkToolBackend -ceq 'powershell7' -and $registeredFiles.Count -eq 10 -and $registeredBootstrap.Contains('TOOLCHAIN.json') -and $registeredBootstrap.Contains('PROJECT-CORRECTIONS:BEGIN') -and [string]$registeredCorrections.projectId -ceq 'explicit-fixture' -and [string]$registeredCorrections.contractVersion -ceq '1.10.0' -and @($registeredCorrections.corrections).Count -eq 0) 'register-materializes-1.12-starter-exact10-with-tool-backend-and-corrections'

        $upgradeRepo=Join-Path $rootFlow 'consumer-upgrade'
        New-GitRepo $upgradeRepo
        $sourceRegisterArgs=@('-ProjectId','upgrade-fixture','-DisplayName','Upgrade Fixture','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade','-FrameworkVersion','1.10.0','-Apply')
        $sourceRegister=Invoke-Ps $register $sourceRegisterArgs
        Assert-True ($sourceRegister.Code -eq 0 -and $sourceRegister.Text.Contains('CREATED')) 'upgrade-fixture-registers-explicit-1.10.0'
        $upgradeControl=Join-Path $upgradeRepo '.ai-workspace'
        $upgradeConfigPath=Join-Path $upgradeControl 'project.json';$upgradeBootstrapPath=Join-Path $upgradeControl 'BOOTSTRAP.md';$upgradeControllerPath=Join-Path $upgradeControl 'controller.json'
        $upgradeConfig=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeConfigPath|ConvertFrom-Json
        $upgradeConfig.routineExcludedPaths=@('private/keep.txt')
        $upgradeConfig.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false}}
        Write-Utf8 $upgradeConfigPath ($upgradeConfig|ConvertTo-Json -Depth 20)
        $customBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeBootstrapPath
        $customBootstrap=[regex]::Replace($customBootstrap,'(?s)(<!-- PROJECT-CUSTOM:BEGIN -->\n).*?(\n<!-- PROJECT-CUSTOM:END -->)','$1fixture-custom-preserved$2')
        Write-Utf8 $upgradeBootstrapPath $customBootstrap
        $upgradeCorrectionsPath=Join-Path $upgradeControl 'corrections.json'
        $upgradeCorrections=[ordered]@{schemaVersion=1;contractVersion='1.10.0';projectId='upgrade-fixture';corrections=@(
            [ordered]@{correctionId='OWNER_FIRST_DIRECT_DOMAIN_ROUTE';introducedAgainstFramework='<=1.8.0';requirementReason='Observed relay';effectiveRule='Owner routes directly';applicability='Same domain';decisionLocator='task:owner-first'},
            [ordered]@{correctionId='PROJECT_CORRECTION_LIFECYCLE';introducedAgainstFramework='1.9.0';requirementReason='No lifecycle';effectiveRule='Retain and re-evaluate';applicability='Pin adoption';decisionLocator='task:corrections'},
            [ordered]@{correctionId='TEST_UNINCORPORATED_REQUIREMENT';introducedAgainstFramework='1.10.0';requirementReason='Exercise target conflict handling';effectiveRule='Retain until target conflict is resolved';applicability='Upgrade test fixture';decisionLocator='test:upgrade-conflict'}
        )}
        Write-Utf8 $upgradeCorrectionsPath ($upgradeCorrections|ConvertTo-Json -Depth 20)
        $upgradeCorrectionsBefore=Get-Identity $upgradeCorrectionsPath
        $controllerBefore=Get-Identity $upgradeControllerPath
        $upgradeArgs=@('-ProjectId','upgrade-fixture','-ToVersion','1.12.0','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade')
        $upgradeConfig.controlPlaneLayout='framework-maintenance-sibling';Write-Utf8 $upgradeConfigPath ($upgradeConfig|ConvertTo-Json -Depth 20)
        $invalidLayoutUpgrade=Invoke-Ps $upgrade $upgradeArgs
        Assert-True ($invalidLayoutUpgrade.Code -ne 0 -and $invalidLayoutUpgrade.Text.Contains('is unhealthy') -and -not$invalidLayoutUpgrade.Text.Contains('Framework 1.8')) 'upgrade-invalid-layout-diagnostic-is-version-neutral'
        $upgradeConfig.controlPlaneLayout='repo-local';Write-Utf8 $upgradeConfigPath ($upgradeConfig|ConvertTo-Json -Depth 20)
        $coverageOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureCoveragePath
        $conflictCoverage=$coverageOriginal|ConvertFrom-Json
        $conflictEntry=@($conflictCoverage.versions|Where-Object{[string]$_.version-ceq'1.12.0'})[0]
        $conflictEntry.conflictingCorrectionIds=@('TEST_UNINCORPORATED_REQUIREMENT')
        Write-Utf8 $fixtureCoveragePath ($conflictCoverage|ConvertTo-Json -Depth 20)
        $null=Seal-ReleaseFixture $fixtureVersionRoot 'CONFLICT_TEST_FIXTURE'
        $conflictUpgrade=Invoke-Ps $upgrade $upgradeArgs
        $conflictVersion=[string](Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeConfigPath|ConvertFrom-Json).frameworkVersion
        $conflictCorrectionsIdentity=Get-Identity $upgradeCorrectionsPath
        $conflictBlocked=$conflictUpgrade.Code-ne0-and$conflictUpgrade.Text.Contains('PROJECT_CORRECTION_CONFLICT')-and$conflictVersion-ceq'1.10.0'-and$conflictCorrectionsIdentity-ceq$upgradeCorrectionsBefore
        if(-not$conflictBlocked){Write-Output ('DIAG|upgrade-correction-conflict|code='+$conflictUpgrade.Code+'|version='+$conflictVersion+'|corrections='+$conflictCorrectionsIdentity+'|expected='+$upgradeCorrectionsBefore+'|output='+$conflictUpgrade.Text)}
        Assert-True $conflictBlocked 'upgrade-correction-conflict-blocks-before-pin-write'
        Write-Utf8 $fixtureCoveragePath $coverageOriginal
        $null=Seal-ReleaseFixture $fixtureVersionRoot 'TEST_FIXTURE_SEALED'
        $upgradePreview=Invoke-Ps $upgrade $upgradeArgs
        Assert-True ($upgradePreview.Code -eq 0 -and $upgradePreview.Text.Contains('Preview only') -and $upgradePreview.Text.Contains('incorporated=2') -and $upgradePreview.Text.Contains('conflicts=0')) 'upgrade-schema3-to-1.12.0-preview-with-correction-report'
        $upgradeApply=Invoke-Ps $upgrade @($upgradeArgs+'-Apply')
        if($upgradeApply.Code-ne0-or-not$upgradeApply.Text.Contains('Updated:')){Write-Output ('DIAG|upgrade-schema3-to-1.12.0-apply|code='+$upgradeApply.Code+'|output='+$upgradeApply.Text)}
        Assert-True ($upgradeApply.Code -eq 0 -and $upgradeApply.Text.Contains('Updated:')) 'upgrade-schema3-to-1.12.0-apply'
        $upgradedConfig=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeConfigPath|ConvertFrom-Json
        $upgradedBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeBootstrapPath
        Assert-True ([string]$upgradedConfig.frameworkVersion -ceq '1.12.0' -and [string]$upgradedConfig.frameworkToolBackend -ceq 'powershell7' -and @($upgradedConfig.routineExcludedPaths).Count -eq 1 -and [string]$upgradedConfig.routineExcludedPaths[0] -ceq 'private/keep.txt' -and $upgradedConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled -eq $false -and $upgradedBootstrap.Contains('fixture-custom-preserved') -and $upgradedBootstrap.Contains('TOOLCHAIN.json') -and $upgradedBootstrap.Contains('PROJECT-CORRECTIONS:BEGIN') -and (Get-Identity $upgradeControllerPath) -ceq $controllerBefore -and (Get-Identity $upgradeCorrectionsPath) -ceq $upgradeCorrectionsBefore) 'upgrade-projects-backend-and-preserves-project-facts-custom-controller-and-corrections'
        $downgradeArgs=@('-ProjectId','upgrade-fixture','-ToVersion','1.9.0','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade')
        $downgradePreview=Invoke-Ps $upgrade $downgradeArgs
        Assert-True ($downgradePreview.Code-eq0-and$downgradePreview.Text.Contains('STILL_EFFECTIVE PROJECT_CORRECTION_LIFECYCLE')-and$downgradePreview.Text.Contains('INCORPORATED OWNER_FIRST_DIRECT_DOMAIN_ROUTE')) 'downgrade-re-evaluates-and-reactivates-unmatched-correction'
        $downgradeApply=Invoke-Ps $upgrade @($downgradeArgs+'-Apply')
        $downgradedConfig=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeConfigPath|ConvertFrom-Json
        $downgradedBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeBootstrapPath
        $downgradeBackendAbsent=$null-eq$downgradedConfig.PSObject.Properties['frameworkToolBackend']
        $downgradeCorrectionLocatorPresent=$downgradedBootstrap.Contains('framework/versions/1.12.0/scripts/check-project-corrections.ps1')
        $downgradeCorrectionsPreserved=(Get-Identity $upgradeCorrectionsPath)-ceq$upgradeCorrectionsBefore
        $downgradeCorrectionBlockPresent=$downgradedBootstrap.Contains('PROJECT-CORRECTIONS:BEGIN')
        Assert-True ($downgradeApply.Code-eq0) 'downgrade-apply-succeeds'
        Assert-True ([string]$downgradedConfig.frameworkVersion-ceq'1.9.0') 'downgrade-projects-target-version'
        Assert-True $downgradeBackendAbsent 'downgrade-removes-backend-field'
        Assert-True $downgradeCorrectionBlockPresent 'downgrade-preserves-correction-bootstrap-block'
        Assert-True $downgradeCorrectionLocatorPresent 'downgrade-preserves-correction-evaluator-locator'
        Assert-True $downgradeCorrectionsPreserved 'downgrade-preserves-correction-records'
    }

    $knowledgeRoot=Join-Path $temp 'knowledge-fixture'
    New-Item -ItemType Directory -Path (Join-Path $knowledgeRoot '.ai-workspace'),(Join-Path $knowledgeRoot 'knowledge') -Force|Out-Null
    foreach($name in @('reference-1','reference-2','reference-history')){Write-Utf8 (Join-Path $knowledgeRoot ('knowledge\'+$name+'.md')) $name}
    Write-Utf8 (Join-Path $knowledgeRoot 'authority-1.md') 'authority-1'
    Write-Utf8 (Join-Path $knowledgeRoot 'authority-2.md') 'authority-2'
    Write-Utf8 (Join-Path $knowledgeRoot 'unrelated.md') 'unrelated'
    $knowledgeConfig=[ordered]@{schemaVersion=3;id='knowledge-fixture';displayName='Knowledge Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.12.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$true;indexLocator='knowledge/index.json'}}}
    $knowledgeConfigPath=Join-Path $knowledgeRoot '.ai-workspace\project.json';Write-Utf8 $knowledgeConfigPath ($knowledgeConfig|ConvertTo-Json -Depth 20)
    $schema2Index=[ordered]@{schemaVersion=2;projectId='knowledge-fixture';entries=@(
        [ordered]@{id='REF-1';state='CURRENT';title='Reference One';summary='Reference one only';tags=@('core','route');locator='knowledge/reference-1.md';identity=Get-Identity (Join-Path $knowledgeRoot 'knowledge\reference-1.md');authorityDependencies=@([ordered]@{locator='authority-1.md';identity=Get-Identity (Join-Path $knowledgeRoot 'authority-1.md')});verifiedAt='2026-08-17T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE');tokenEstimate=10},
        [ordered]@{id='REF-2';state='CURRENT';title='Reference Two';summary='Reference two only';tags=@('design');locator='knowledge/reference-2.md';identity=Get-Identity (Join-Path $knowledgeRoot 'knowledge\reference-2.md');authorityDependencies=@([ordered]@{locator='authority-2.md';identity=Get-Identity (Join-Path $knowledgeRoot 'authority-2.md')});verifiedAt='2026-08-17T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE');tokenEstimate=10},
        [ordered]@{id='REF-HISTORY';state='HISTORICAL';title='Old Reference';summary='Historical only';tags=@();locator='knowledge/reference-history.md';identity=Get-Identity (Join-Path $knowledgeRoot 'knowledge\reference-history.md');authorityDependencies=@([ordered]@{locator='authority-1.md';identity=Get-Identity (Join-Path $knowledgeRoot 'authority-1.md')});verifiedAt='2026-08-17T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE');tokenEstimate=10}
    )}
    $knowledgeIndexPath=Join-Path $knowledgeRoot 'knowledge\index.json';Write-Utf8 $knowledgeIndexPath ($schema2Index|ConvertTo-Json -Depth 20)
    $knowledgeChecker=Join-Path $candidateRoot 'scripts\check-knowledge-entry.ps1'
    $knowledgeImpact=Join-Path $candidateRoot 'scripts\check-knowledge-impact.ps1'
    $knowledgeConfigIdentity=Get-Identity $knowledgeConfigPath
    $knowledgeBaseArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath))
    $primaryPwshDiscover=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeBaseArgs+@('-Operation','DISCOVER','-AsJson'))
    $discoverValue=@($primaryPwshDiscover.Output)[-1]|ConvertFrom-Json
    Assert-True ($primaryPwshDiscover.Code -eq 0 -and [string]$discoverValue.status -ceq 'KNOWLEDGE_CATALOG' -and @($discoverValue.entries).Count -eq 3 -and $null-eq$discoverValue.entries[0].PSObject.Properties['summary'] -and [int]$discoverValue.maxQueries -eq 3) 'knowledge-discover-compact-metadata-no-summary'
    $primaryPwshQuery=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeBaseArgs+@('-Operation','QUERY','-EntryId','REF-1','-AsJson'))
    $queryValue=@($primaryPwshQuery.Output)[-1]|ConvertFrom-Json
    Assert-True ($primaryPwshQuery.Code -eq 0 -and [string]$queryValue.entries[0].status -ceq 'AVAILABLE' -and $null-ne$queryValue.entries[0].PSObject.Properties['authorityDependencies']) 'knowledge-query-requested-current-entry-available'
    $multiQuery=Invoke-PsHostEntryIdArray $script:pwshExecutable $knowledgeChecker $knowledgeBaseArgs @('REF-1','REF-2') $temp
    $multiValue=@($multiQuery.Output)[-1]|ConvertFrom-Json
    Assert-True ($multiQuery.Code -eq 0 -and @($multiValue.entries).Count -eq 2 -and @($multiValue.entries|Where-Object{$_.status-ceq'AVAILABLE'}).Count -eq 2) 'knowledge-query-two-current-entries-available'
    $pwsh=[pscustomobject]@{Source=$script:pwshExecutable}
    if($null-ne$pwsh){
        $ps7Correction=Invoke-PsHost $pwsh.Source $correctionChecker $correctionArgs
        Assert-True ($ps7Correction.Code-eq0-and$ps7Correction.Text.Contains('"coverageStatus":"MATCHED"')) 'corrections-ps7-incorporated-vs-still-effective'
        Write-Utf8 $correctionPath $correctionDuplicate
        try{$ps7CorrectionDuplicate=Invoke-PsHost $pwsh.Source $correctionChecker @('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.9.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')}
        finally{Write-Utf8 $correctionPath $correctionOriginal}
        Assert-True ($ps7CorrectionDuplicate.Code-ne0-and$ps7CorrectionDuplicate.Text.Contains('CORRECTIONS_JSON_DUPLICATE_FIELD')) 'corrections-ps7-unicode-duplicate-field-fails-closed'
    }else{Write-Output 'EVIDENCE_CEILING|POWERSHELL_7_UNAVAILABLE';Assert-True $true 'corrections-powershell7-evidence-ceiling-recorded'}
    if($null-ne$pwsh){$ps7Valid=Invoke-PsHost $pwsh.Source $knowledgeChecker @($knowledgeBaseArgs+@('-Operation','QUERY','-EntryId','REF-1','-AsJson'));Assert-True ($ps7Valid.Code -eq 0 -and $ps7Valid.Text.Contains('KNOWLEDGE_QUERY_RESULT')) 'knowledge-ps7-valid-utc-string'}else{Write-Output 'EVIDENCE_CEILING|POWERSHELL_7_UNAVAILABLE';Assert-True $true 'knowledge-powershell7-evidence-ceiling-recorded'}

    Write-Utf8 (Join-Path $knowledgeRoot 'authority-2.md') 'authority-2-drifted'
    $isolatedQuery=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeBaseArgs+@('-Operation','QUERY','-EntryId','REF-1','-AsJson'))
    $isolatedValue=@($isolatedQuery.Output)[-1]|ConvertFrom-Json
    Assert-True ($isolatedQuery.Code -eq 0 -and @($isolatedValue.entries).Count -eq 1 -and [string]$isolatedValue.entries[0].status -ceq 'AVAILABLE') 'knowledge-query-unrelated-stale-does-not-block-fresh-request'
    $staleOnly=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeBaseArgs+@('-Operation','QUERY','-EntryId','REF-2','-AsJson'))
    Assert-True ($staleOnly.Code -eq 0 -and $staleOnly.Text.Contains('UNAVAILABLE')) 'knowledge-query-requested-stale-entry-refused'
    Write-Utf8 (Join-Path $knowledgeRoot 'authority-2.md') 'authority-2'

    $noId=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeBaseArgs+@('-Operation','QUERY','-AsJson'))
    $unknownId=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeBaseArgs+@('-Operation','QUERY','-EntryId','UNKNOWN','-AsJson'))
    $duplicateId=Invoke-PsHostEntryIdArray $script:pwshExecutable $knowledgeChecker $knowledgeBaseArgs @('REF-1','REF-1') $temp
    $overLimit=Invoke-PsHostEntryIdArray $script:pwshExecutable $knowledgeChecker $knowledgeBaseArgs @('REF-1','REF-2','REF-HISTORY','UNKNOWN') $temp
    Assert-True ($noId.Code -eq 3 -and $noId.Text.Contains('ENTRY_ID_EMPTY')) 'knowledge-query-no-id-explicitly-not-requested'
    Assert-True ($unknownId.Code -eq 3 -and $unknownId.Text.Contains('ENTRY_ID_UNKNOWN')) 'knowledge-query-unknown-id-fails-closed'
    Assert-True ($duplicateId.Code -eq 3 -and $duplicateId.Text.Contains('ENTRY_ID_DUPLICATE')) 'knowledge-query-duplicate-id-fails-closed'
    Assert-True ($overLimit.Code -eq 3 -and $overLimit.Text.Contains('ENTRY_ID_LIMIT')) 'knowledge-query-over-three-fails-closed'

    $impactBaseArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-AsJson')
    $directImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact @($impactBaseArgs+@('-ChangedAuthorityPath','authority-1.md'))
    $directImpactValue=@($directImpact.Output)[-1]|ConvertFrom-Json
    if($directImpact.Code-ne0){Write-Output ('DIAG|knowledge-impact-direct|'+$directImpact.Code+'|'+$directImpact.Text)}
    Assert-True ($directImpact.Code -eq 0 -and [string]$directImpactValue.status -ceq 'DIRECT_AFFECTED' -and @($directImpactValue.affectedIds) -contains 'REF-1' -and -not[bool]$directImpactValue.writes) 'knowledge-impact-direct-authority-path-detected-read-only'
    $noneImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact @($impactBaseArgs+@('-ChangedAuthorityPath','unrelated.md'))
    Assert-True ($noneImpact.Code -eq 0 -and $noneImpact.Text.Contains('NONE_DIRECT')) 'knowledge-impact-unrelated-path-none-direct'
    Write-Utf8 (Join-Path $knowledgeRoot 'authority-2.md') 'authority-2-drifted-again'
    $unknownImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact @($impactBaseArgs+@('-ChangedAuthorityPath','unrelated.md'))
    Assert-True ($unknownImpact.Code -eq 0 -and $unknownImpact.Text.Contains('UNKNOWN')) 'knowledge-impact-drifting-dependency-unknown'
    Write-Utf8 (Join-Path $knowledgeRoot 'authority-2.md') 'authority-2'

    $malformedImpactIndex=$schema2Index|ConvertTo-Json -Depth 20|ConvertFrom-Json
    $malformedImpactIndex.entries[0].authorityDependencies=@()
    Write-Utf8 $knowledgeIndexPath ($malformedImpactIndex|ConvertTo-Json -Depth 20)
    $malformedImpactArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-ChangedAuthorityPath','unrelated.md','-AsJson')
    $malformedImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact $malformedImpactArgs
    Assert-True ($malformedImpact.Code -eq 3 -and $malformedImpact.Text.Contains('ENTRY_VALUES')) 'knowledge-impact-pwsh7-primary-malformed-dependency-index-fails-closed'
    if($null-ne$pwsh){$malformedImpact7=Invoke-PsHost $pwsh.Source $knowledgeImpact $malformedImpactArgs;Assert-True ($malformedImpact7.Code -eq 3 -and $malformedImpact7.Text.Contains('ENTRY_VALUES')) 'knowledge-impact-ps7-malformed-dependency-index-fails-closed'}

    $duplicateImpactIndex=$schema2Index|ConvertTo-Json -Depth 20|ConvertFrom-Json
    $duplicateImpactIndex.entries=@($duplicateImpactIndex.entries)+@($duplicateImpactIndex.entries[0])
    Write-Utf8 $knowledgeIndexPath ($duplicateImpactIndex|ConvertTo-Json -Depth 20)
    $duplicateImpactArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-ChangedAuthorityPath','unrelated.md','-AsJson')
    $duplicateImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact $duplicateImpactArgs
    Assert-True ($duplicateImpact.Code -eq 3 -and $duplicateImpact.Text.Contains('ENTRY_ID_DUPLICATE')) 'knowledge-impact-pwsh7-primary-duplicate-id-index-fails-closed'
    if($null-ne$pwsh){$duplicateImpact7=Invoke-PsHost $pwsh.Source $knowledgeImpact $duplicateImpactArgs;Assert-True ($duplicateImpact7.Code -eq 3 -and $duplicateImpact7.Text.Contains('ENTRY_ID_DUPLICATE')) 'knowledge-impact-ps7-duplicate-id-index-fails-closed'}

    $unknownFieldImpactIndex=$schema2Index|ConvertTo-Json -Depth 20|ConvertFrom-Json
    $unknownFieldImpactIndex.entries[0]|Add-Member -NotePropertyName unexpected -NotePropertyValue $true
    Write-Utf8 $knowledgeIndexPath ($unknownFieldImpactIndex|ConvertTo-Json -Depth 20)
    $unknownFieldImpactArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-ChangedAuthorityPath','unrelated.md','-AsJson')
    $unknownFieldImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact $unknownFieldImpactArgs
    Assert-True ($unknownFieldImpact.Code -eq 3 -and $unknownFieldImpact.Text.Contains('ENTRY_FIELDS')) 'knowledge-impact-unknown-index-field-fails-closed'

    $duplicateFieldRaw=$schema2Index|ConvertTo-Json -Depth 20
    $projectIdMatch=[regex]::Match($duplicateFieldRaw,'(?m)^\s*"projectId"\s*:\s*"knowledge-fixture",')
    if(-not$projectIdMatch.Success){throw 'DUPLICATE_FIELD_FIXTURE_MARKER'}
    $duplicateFieldRaw=$duplicateFieldRaw.Insert($projectIdMatch.Index+$projectIdMatch.Length,"`n  `"\u0070rojectId`": `"knowledge-fixture`",")
    Write-Utf8 $knowledgeIndexPath $duplicateFieldRaw
    $duplicateFieldImpactArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-ChangedAuthorityPath','unrelated.md','-AsJson')
    $duplicateFieldImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact $duplicateFieldImpactArgs
    Assert-True ($duplicateFieldImpact.Code -eq 3 -and $duplicateFieldImpact.Text.Contains('INDEX_JSON_DUPLICATE_FIELD|projectId')) 'knowledge-impact-unicode-duplicate-index-field-fails-closed'

    $impactExternalRoot=Join-Path $temp 'knowledge-impact-external';New-Item -ItemType Directory -Path $impactExternalRoot -Force|Out-Null
    $impactExternalFile=Join-Path $impactExternalRoot 'outside.md';Write-Utf8 $impactExternalFile 'outside-authority'
    $impactJunction=Join-Path $knowledgeRoot 'linked-authority';New-TestJunction $impactJunction $impactExternalRoot
    $reparseImpactIndex=$schema2Index|ConvertTo-Json -Depth 20|ConvertFrom-Json
    $reparseImpactIndex.entries[0].authorityDependencies[0].locator='linked-authority/outside.md'
    $reparseImpactIndex.entries[0].authorityDependencies[0].identity=Get-Identity $impactExternalFile
    Write-Utf8 $knowledgeIndexPath ($reparseImpactIndex|ConvertTo-Json -Depth 20)
    $reparseImpactArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-ChangedAuthorityPath','unrelated.md','-AsJson')
    $reparseImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact $reparseImpactArgs
    Assert-True ($reparseImpact.Code -eq 3 -and $reparseImpact.Text.Contains('LOCATOR_REPARSE|linked-authority/outside.md')) 'knowledge-impact-pwsh7-primary-dependency-junction-fails-closed'
    if($null-ne$pwsh){$reparseImpact7=Invoke-PsHost $pwsh.Source $knowledgeImpact $reparseImpactArgs;Assert-True ($reparseImpact7.Code -eq 3 -and $reparseImpact7.Text.Contains('LOCATOR_REPARSE|linked-authority/outside.md')) 'knowledge-impact-ps7-dependency-junction-fails-closed'}
    Remove-TestJunction $impactJunction

    $schema1Index=[ordered]@{schemaVersion=1;projectId='knowledge-fixture';entries=@([ordered]@{id='REF-LEGACY';state='CURRENT';title='Legacy Reference';summary='Legacy reference only';locator='knowledge/reference-1.md';identity=Get-Identity (Join-Path $knowledgeRoot 'knowledge\reference-1.md');authorityLocator='authority-1.md';authorityIdentity=Get-Identity (Join-Path $knowledgeRoot 'authority-1.md');verifiedAt='2026-08-17T00:00:00Z';invalidatesOn=@('LOCATOR_IDENTITY_CHANGE','AUTHORITY_IDENTITY_CHANGE');tokenEstimate=10})}
    Write-Utf8 $knowledgeIndexPath ($schema1Index|ConvertTo-Json -Depth 20)
    $schema1Args=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-Operation','QUERY','-EntryId','REF-LEGACY','-AsJson')
    $schema1Query=Invoke-PsHost $script:pwshExecutable $knowledgeChecker $schema1Args
    Assert-True ($schema1Query.Code -eq 0 -and $schema1Query.Text.Contains('AVAILABLE')) 'knowledge-schema1-single-authority-compatible'

    $typeIndex=$schema1Index|ConvertTo-Json -Depth 20|ConvertFrom-Json;$typeIndex.entries[0].verifiedAt=123;Write-Utf8 $knowledgeIndexPath ($typeIndex|ConvertTo-Json -Depth 20)
    $typeArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-Operation','DISCOVER','-AsJson')
    $primaryPwshType=Invoke-PsHost $script:pwshExecutable $knowledgeChecker $typeArgs
    Assert-True ($primaryPwshType.Code -eq 3 -and $primaryPwshType.Text.Contains('ENTRY_VALUES')) 'knowledge-pwsh7-primary-rejects-timestamp-type-drift'
    if($null-ne$pwsh){$ps7Type=Invoke-PsHost $pwsh.Source $knowledgeChecker $typeArgs;Assert-True ($ps7Type.Code -eq 3 -and $ps7Type.Text.Contains('ENTRY_VALUES')) 'knowledge-ps7-rejects-timestamp-type-drift'}
    $invalidIndex=$schema1Index|ConvertTo-Json -Depth 20|ConvertFrom-Json;$invalidIndex.entries[0].verifiedAt='2026-08-17 00:00:00';Write-Utf8 $knowledgeIndexPath ($invalidIndex|ConvertTo-Json -Depth 20)
    $invalidArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-Operation','DISCOVER','-AsJson')
    $primaryPwshInvalid=Invoke-PsHost $script:pwshExecutable $knowledgeChecker $invalidArgs
    Assert-True ($primaryPwshInvalid.Code -eq 3 -and $primaryPwshInvalid.Text.Contains('ENTRY_VALUES')) 'knowledge-pwsh7-primary-rejects-invalid-timestamp'
    if($null-ne$pwsh){$ps7Invalid=Invoke-PsHost $pwsh.Source $knowledgeChecker $invalidArgs;Assert-True ($ps7Invalid.Code -eq 3 -and $ps7Invalid.Text.Contains('ENTRY_VALUES')) 'knowledge-ps7-rejects-invalid-timestamp'}

    if (-not $SkipBaseline) {
        $frameworkRoot = [IO.Path]::GetFullPath((Join-Path $candidateRoot '..\..')).TrimEnd('\')
        $baselineRunner = Join-Path $frameworkRoot 'versions\1.11.0\tests\run-framework-tests.ps1'
        $baseline = Invoke-Ps $baselineRunner @('-SkipRootMigration')
        if ($baseline.Code -ne 0) { Write-Output ('DIAG|baseline-1.11.0|' + $baseline.Text) }
        Assert-True ($baseline.Code -eq 0 -and $baseline.Text.Contains('RESULT|')) 'baseline-1.11.0-regression-suite'
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

$resultManifest=Get-Content -LiteralPath (Join-Path $candidateRoot 'RELEASE_MANIFEST.json') -Raw -Encoding utf8|ConvertFrom-Json
$resultSealed=[string]$resultManifest.sourceReview-ceq'APPROVED'-and[string]$resultManifest.releaseIntegration-cne'PENDING'
$resultPending=[string]$resultManifest.sourceReview-ceq'PENDING'-and[string]$resultManifest.releaseIntegration-ceq'PENDING'
Assert-True ($resultSealed-or$resultPending) 'result-lifecycle-derived-from-manifest'
$resultScope=if($resultSealed){'Framework-1.12.0-stable'}else{'Framework-1.12.0-candidate'}
$resultLifecycle=if($resultSealed){'SEALED'}else{'PENDING_SEAL'}
Write-Output ("RESULT|" + $script:passed + "/" + $script:passed + " passed|scope="+$resultScope+"|lifecycle="+$resultLifecycle)
