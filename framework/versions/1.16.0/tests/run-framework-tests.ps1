[CmdletBinding()]
param([switch]$SkipRootMigration,[switch]$SkipManifest,[switch]$SkipBaseline,[switch]$SkipPerformanceSmoke,[switch]$ToolContractOnly)

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

function Test-RouterSkillContract([string]$Text,[int64]$ByteLength,[int64]$Ceiling) {
    if($ByteLength-lt1-or$ByteLength-gt$Ceiling){return $false}
    foreach($required in @('NON_AUTHORITY','BOOTSTRAP.md','TOOLCHAIN.json','1.14.0','1.14.1','1.15.0','自然边界','上下文不确定','PROCESS_REQUIREMENTS_RESOLVE/DISCOVER','ADMIT_ACTION','FINALIZE_OUTPUT','.ai-workspace/runtime/<task>/<actor>/','保持 gate 独立')){if(-not$Text.Contains($required)){return $false}}
    return $true
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

function Get-OptionalIdentity([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return Get-Identity $Path }
    return 'MISSING'
}

function Get-ExactObjectRows([string]$Root,[string[]]$RelativePaths) {
    return @($RelativePaths | ForEach-Object { $_ + '=' + (Get-OptionalIdentity (Join-Path $Root $_.Replace('/','\'))) })
}

function Get-ReleasePayloadFacts([string]$VersionRoot) {
    [string[]]$payload=@(Get-ChildItem -LiteralPath $VersionRoot -Recurse -Force -File|ForEach-Object{$_.FullName.Substring($VersionRoot.Length+1).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'})
    [Array]::Sort($payload,[StringComparer]::Ordinal)
    $rows=@();[int64]$total=0
    foreach($relative in $payload){$full=Join-Path $VersionRoot $relative;$identity=(Get-Identity $full).Split('|');$total+=[int64]$identity[0];$rows+=($relative+'|'+$identity[0]+'|'+$identity[1])}
    $payloadEncoding=New-Object Text.UTF8Encoding($false)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$canonical=([BitConverter]::ToString($sha.ComputeHash($payloadEncoding.GetBytes(($rows-join"`n"))))).Replace('-','')}finally{$sha.Dispose()}
    return [pscustomobject]@{Files=$payload;Rows=$rows;FileCount=$payload.Count;TotalBytes=$total;Canonical=$canonical}
}

function Seal-ReleaseFixture([string]$VersionRoot,[string]$Integration) {
    $versionPath=Join-Path $VersionRoot 'VERSION.json';$version=Get-Content -Raw -Encoding utf8 -LiteralPath $versionPath|ConvertFrom-Json
    $version.lifecycle='STABLE';$version.consumable=$true;$version.projectPinEligible=$true
    Write-Utf8 $versionPath ($version|ConvertTo-Json -Depth 20)
    $loadPath=Join-Path $VersionRoot 'LOAD_MANIFEST.json';$load=Get-Content -Raw -Encoding utf8 -LiteralPath $loadPath|ConvertFrom-Json
    $load.lifecycle='STABLE';Write-Utf8 $loadPath ($load|ConvertTo-Json -Depth 30)
    $facts=Get-ReleasePayloadFacts $VersionRoot
    $manifestPath=Join-Path $VersionRoot 'RELEASE_MANIFEST.json';$reviewedManifestIdentity=Get-Identity $manifestPath;$manifest=Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath|ConvertFrom-Json
    $manifest.lifecycle='STABLE';$manifest.fileCount=$facts.FileCount;$manifest.totalBytes=$facts.TotalBytes;$manifest.canonical=$facts.Canonical;$manifest.sourceReview='APPROVED';$manifest.sourceCandidate='TEST_FIXTURE_CANDIDATE'
    $manifest|Add-Member -NotePropertyName completeSuite -NotePropertyValue ([pscustomobject][ordered]@{status='PASS';passed=1;total=1;payloadCanonical=$facts.Canonical;evidenceIdentity=('1|'+('A'*64))}) -Force
    $manifest|Add-Member -NotePropertyName sourceReviewEvidence -NotePropertyValue ([pscustomobject][ordered]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$facts.Canonical;reviewedManifestIdentity=$reviewedManifestIdentity}) -Force
    $manifest.releaseIntegration=$Integration
    Write-Utf8 $manifestPath ($manifest|ConvertTo-Json -Depth 20)
    return $facts
}

function Invoke-Ps([string]$Script,[string[]]$Arguments,[string]$WorkingDirectory='') {
    $effectiveArguments=@($Arguments)
    if ([IO.Path]::GetFileName($Script) -ceq 'check-authorization.ps1' -and '-TaskPath' -cnotin $effectiveArguments -and -not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $packageIndex=[Array]::IndexOf($effectiveArguments,'-PackagePath')
        if($packageIndex-ge0-and$packageIndex+1-lt$effectiveArguments.Count){
            $packageFixture=Get-Content -LiteralPath $effectiveArguments[$packageIndex+1] -Raw -Encoding utf8|ConvertFrom-Json
            $taskRelative='.ai-workspace/tasks/active/'+[string]$packageFixture.taskId+'.md'
            $taskFull=Join-Path $WorkingDirectory $taskRelative
            $effectiveArguments+=@('-TaskPath',$taskRelative,'-ExpectedTaskIdentity',(Get-Identity $taskFull))
        }
    }
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = @(& $script:pwshExecutable -NoProfile -NonInteractive -File $Script @effectiveArguments 2>&1 | ForEach-Object { [string]$_ }); $code = $LASTEXITCODE }
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
        $hostArguments=@('-NoProfile','-NonInteractive')
        if([IO.Path]::GetFileName($Executable)-ieq'powershell.exe'){$hostArguments+=@('-ExecutionPolicy','Bypass')}
        try { $output = @(& $Executable @hostArguments -File $Script @Arguments 2>&1 | ForEach-Object { [string]$_ }); $code = $LASTEXITCODE }
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

function Render-MaintenanceStarter([string]$Starter,[string]$OverlayRoot,[string]$ControlRoot) {
    $destination = Join-Path $ControlRoot '.ai-workspace'
    Copy-Item -LiteralPath $Starter -Destination $destination -Recurse
    Remove-Item -LiteralPath (Join-Path $destination 'AGENTS.md') -Force
    Copy-Item -LiteralPath (Join-Path $OverlayRoot 'BOOTSTRAP.md') -Destination (Join-Path $destination 'BOOTSTRAP.md') -Force
    Copy-Item -LiteralPath (Join-Path $OverlayRoot 'process-policy.json') -Destination (Join-Path $destination 'process-policy.json') -Force
    Copy-Item -LiteralPath (Join-Path $OverlayRoot 'AGENTS.md') -Destination (Join-Path $ControlRoot 'AGENTS.md') -Force
    Get-ChildItem -LiteralPath $destination -Recurse -Force -File | ForEach-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8
        $text = $text.Replace('{{PROJECT_ID}}','framework-maintenance-fixture')
        $text = $text.Replace('{{DISPLAY_NAME}}','Framework Maintenance Fixture')
        $text = $text.Replace('{{FRAMEWORK_VERSION}}','1.16.0')
        $text = $text.Replace('{{CONTROLLER_ID}}','controller-fixture')
        $text = $text.Replace('{{PROCESS_CONTRACT_VERSION_JSON}}','"1.16.0"')
        $text = $text.Replace('{{PROJECT_ID_JSON}}','"framework-maintenance-fixture"')
        $text = $text.Replace('{{CONTROLLER_ID_JSON}}','"controller-fixture"')
        $text = $text.Replace('{{SELECTED_RULE_PACK_BYTES}}','32768')
        $text = $text.Replace('{{CREATED_DATE}}','2026-09-03')
        Write-Utf8 $_.FullName $text
    }
    $config=[ordered]@{schemaVersion=4;id='framework-maintenance-fixture';displayName='Framework Maintenance Fixture';controlPlaneLayout='framework-maintenance-sibling';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'};frameworkTarget=[ordered]@{repositoryId='ai-workspace-framework';siblingDirectory='AI-Workspace';routineExcludedPaths=@()}}
    Write-Utf8 (Join-Path $destination 'project.json') ($config|ConvertTo-Json -Depth 20)
    $agentsPath=Join-Path $ControlRoot 'AGENTS.md';$agents=Get-Content -LiteralPath $agentsPath -Raw -Encoding utf8;$agents=$agents.Replace('{{PROJECT_ID}}','framework-maintenance-fixture').Replace('{{DISPLAY_NAME}}','Framework Maintenance Fixture').Replace('{{FRAMEWORK_VERSION}}','1.16.0');Write-Utf8 $agentsPath $agents
    return $destination
}

function New-AuthorizationPackage(
    [string]$Path,[int]$Schema,[string]$RepositoryId,[string]$ConfigIdentity,
    [string[]]$Actions,[string]$ExactPath,[string]$ObjectIdentity,[switch]$DomainOwner
) {
    $issuer = if ($DomainOwner) { 'owner-fixture' } else { 'controller-fixture' }
    $taskId = if ($DomainOwner) { 'FIXTURE-OWNER-001' } else { 'FIXTURE-001' }
    $taskRelative='.ai-workspace/tasks/active/'+$taskId+'.md'
    $controlRoot=Split-Path -Parent $Path
    $taskFull=Join-Path (Split-Path -Parent $controlRoot) $taskRelative
    Write-Utf8 $taskFull ("# $taskId - authorization fixture`n`n- Task schema: 1.16.0`n- Owner: $issuer`n- Work route: actor=$issuer; role="+$(if($DomainOwner){'DOMAIN_OWNER'}else{'CONTROLLER'})+"; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n")
    $taskIdentity=Get-Identity $taskFull
    $package = [ordered]@{
        schemaVersion=$Schema; frameworkVersion='1.16.0'; taskId=$taskId; taskIdentity=$taskIdentity; profile='STANDARD'; lifecycle='ACTIVE'
        owner=$issuer; issuer=$issuer; issuerRole=$(if($DomainOwner){'DOMAIN_OWNER'}else{'PROJECT_CONTROLLER'})
        grantee=$issuer; bundle='IMPLEMENT_LOCAL'; decisionClass='ROUTINE_LOCAL'; userConfirmation='NOT_REQUIRED'
        reviewIndependence='NOT_APPLICABLE'; delegatedGitCloser=$false; actions=@($Actions); exactPaths=@($ExactPath)
        objectIdentities=@([ordered]@{path=$ExactPath;identity=$ObjectIdentity})
        projectConfigIdentity=$ConfigIdentity
        invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')
    }
    if (-not $DomainOwner) {
        $package.issuerControllerId='controller-fixture'
        $package.issuerControllerEpoch=1
        $package.controllerControlIdentity=Get-Identity (Join-Path (Split-Path -Parent $Path) 'controller.json')
        $package.invalidatesOn += 'CONTROLLER_EPOCH_CHANGE'
    }
    if ($Schema -eq 2) {
        $package.repositoryId=$RepositoryId
        $package.invalidatesOn += 'REPOSITORY_CHANGE'
    }
    Write-Utf8 $Path ($package | ConvertTo-Json -Depth 20)
}

function Set-PackageProjectConfigIdentity([string]$Path,[string]$Identity) {
    $package=Get-Content -LiteralPath $Path -Raw -Encoding utf8|ConvertFrom-Json
    $package.projectConfigIdentity=$Identity
    Write-Utf8 $Path ($package|ConvertTo-Json -Depth 20)
}

function New-MaintenanceUpgradeAuthorizationPackage([string]$Path,[string]$ConfigIdentity,[string]$ObjectPath,[string]$ObjectIdentity) {
    $taskPath=Join-Path (Split-Path -Parent (Split-Path -Parent $Path)) '.ai-workspace/tasks/active/FIXTURE-001.md'
    $package=[ordered]@{schemaVersion=3;frameworkVersion='1.16.0';taskId='FIXTURE-001';taskIdentity=(Get-Identity $taskPath);profile='CRITICAL';lifecycle='ACTIVE';owner='controller-fixture';issuer='controller-fixture';issuerRole='PROJECT_CONTROLLER';grantee='controller-fixture';bundle='ACTOR_BOUND_PROJECT_UPGRADE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='USER_FIXTURE_APPROVED_MAINTENANCE_UPGRADE';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;actions=@('CONTROL_WRITE');exactPaths=@($ObjectPath);objectIdentities=@([ordered]@{path=$ObjectPath;identity=$ObjectIdentity});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE','POST_OBJECT_DRIFT');projectConfigIdentity=$ConfigIdentity;issuerControllerId='controller-fixture';issuerControllerEpoch=1;controllerControlIdentity=(Get-Identity (Join-Path (Split-Path -Parent $Path) 'controller.json'));postObjectIdentities=@([ordered]@{path=$ObjectPath;identity=('1|'+('A'*64))});targetFrameworkSnapshot=[ordered]@{canonical=('B'*64);manifestIdentity=('1|'+('C'*64))}}
    Write-Utf8 $Path ($package|ConvertTo-Json -Depth 20)
}

function Invoke-FixtureSchema2Authorization(
    [string]$Checker,[string]$Package,[string]$WorkingDirectory,[string]$Actor,
    [string]$Action,[string]$ObjectPath,[string]$ObjectIdentity,[string]$RepositoryId,[string]$ConfigIdentity
) {
    $taskId=if($Actor-ceq'owner-fixture'){'FIXTURE-OWNER-001'}else{'FIXTURE-001'}
    $taskPath='.ai-workspace/tasks/active/'+$taskId+'.md'
    return Invoke-Ps $Checker @(
        '-PackagePath',$Package,
        '-ObservedActor',$Actor,
        '-ObservedTaskId',$taskId,
        '-ObservedOwner',$Actor,
        '-ObservedAction',$Action,
        '-ObservedPath',$ObjectPath,
        '-ObservedIdentity',($ObjectPath+'='+$ObjectIdentity),
        '-ControllerControlPath','.ai-workspace/controller.json',
        '-ObservedRepositoryId',$RepositoryId,
        '-ProjectConfigPath','.ai-workspace/project.json',
        '-ExpectedProjectConfigIdentity',$ConfigIdentity,
        '-TaskPath',$taskPath,
        '-ExpectedTaskIdentity',(Get-Identity (Join-Path $WorkingDirectory $taskPath))
    ) $WorkingDirectory
}

$candidateRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$actual = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($candidateRoot.Length + 1).Replace('\','/') })
[Array]::Sort($actual,[StringComparer]::Ordinal)
$inventoryPath=Join-Path $candidateRoot 'NORMATIVE_SURFACE_INVENTORY.json';$inventory=Get-Content -Raw -Encoding utf8 -LiteralPath $inventoryPath|ConvertFrom-Json
$inventoryFields=@($inventory.PSObject.Properties.Name)
$declared=New-Object 'System.Collections.Generic.List[string]'
foreach($pair in @($inventory.runtimeNormativeModules)){$declared.Add([string]$pair.document);$declared.Add([string]$pair.fragment)}
foreach($category in @('actionRequiredArtifacts','schemaAndMechanicalInputs','explanationAndHistory')){foreach($relative in @($inventory.$category)){$declared.Add([string]$relative)}}
$declaredArray=@($declared);$declaredUnique=@($declaredArray|Sort-Object -Unique);[Array]::Sort($declaredArray,[StringComparer]::Ordinal)
Assert-True ([int]$inventory.schemaVersion-eq1-and[string]$inventory.frameworkVersion-ceq'1.16.0'-and$inventoryFields.Count-eq6-and$declaredArray.Count-eq$declaredUnique.Count-and$actual.Count-eq71-and($actual-join"`n")-ceq($declaredArray-join"`n")) 'normative-surface-inventory-exact71-classified-once'
$initialPayloadFacts=Get-ReleasePayloadFacts $candidateRoot
$independentOrdinalFiles=New-Object 'System.Collections.Generic.List[string]';foreach($relative in $actual){if($relative-cne'RELEASE_MANIFEST.json'){$independentOrdinalFiles.Add($relative)}};$independentOrdinalFiles.Sort([StringComparer]::Ordinal)
$initialManifest=Get-Content -LiteralPath (Join-Path $candidateRoot 'RELEASE_MANIFEST.json') -Raw -Encoding utf8|ConvertFrom-Json
if($SkipManifest){Assert-True ([string]::Join("`n",$initialPayloadFacts.Files)-ceq[string]::Join("`n",$independentOrdinalFiles.ToArray())-and[int]$initialManifest.schemaVersion-eq2-and[string]$initialManifest.lifecycle-ceq'CANDIDATE'-and[string]$initialManifest.sourceReview-ceq'PENDING'-and[string]$initialManifest.completeSuite.status-ceq'PENDING'-and[string]$initialManifest.sourceReviewEvidence.status-ceq'PENDING'-and[string]$initialManifest.releaseIntegration-ceq'PENDING') 'release-candidate-payload-enumerated-manifest-freeze-deferred'}else{Assert-True ([string]::Join("`n",$initialPayloadFacts.Files)-ceq[string]::Join("`n",$independentOrdinalFiles.ToArray())-and[int]$initialManifest.fileCount-eq$initialPayloadFacts.FileCount-and[int64]$initialManifest.totalBytes-eq$initialPayloadFacts.TotalBytes-and[string]$initialManifest.canonical-ceq$initialPayloadFacts.Canonical-and[string]$initialManifest.algorithm-clike'Ordinal relative path*') 'release-candidate-manifest-independent-ordinal-canonical'}

foreach ($relative in $actual) {
    $path = Join-Path $candidateRoot $relative
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no-bom|' + $relative)
    try { $text = $utf8Strict.GetString($bytes) } catch { throw "STRICT_UTF8_FAIL|$relative" }
    Assert-True (-not $text.Contains("`r") -and -not $text.Contains([char]0) -and -not $text.Contains([char]0xFFFD) -and $text.EndsWith("`n")) ('strict-text|' + $relative)
    if ([IO.Path]::GetExtension($relative) -ceq '.json' -and -not $text.Contains('{{')) {
        try { $null = $text | ConvertFrom-Json } catch { throw "JSON_FAIL|$relative|$($_.Exception.Message)" }
    }
    if ([IO.Path]::GetExtension($relative) -in @('.ps1','.psm1')) {
        $tokens=$null; $errors=$null
        [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) ('powershell-syntax|' + $relative)
    }
}

$version = Get-Content -LiteralPath (Join-Path $candidateRoot 'VERSION.json') -Raw -Encoding utf8 | ConvertFrom-Json
$loadManifest = Get-Content -LiteralPath (Join-Path $candidateRoot 'LOAD_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
$expectedLifecycle=if($SkipManifest){'CANDIDATE'}else{'STABLE'}
$versionLifecycleState=if($SkipManifest){[string]$version.lifecycle-ceq'CANDIDATE'-and-not[bool]$version.consumable-and-not[bool]$version.projectPinEligible}else{[string]$version.lifecycle-ceq'STABLE'-and[bool]$version.consumable-and[bool]$version.projectPinEligible}
Assert-True ([string]$version.version -ceq '1.16.0' -and $versionLifecycleState -and [string]$version.releaseClass -ceq 'MINOR' -and [string]$version.baseline -ceq '1.15.1' -and $null -eq $version.PSObject.Properties['currentEligible']) 'version-lifecycle-fields-minor-baseline-1.15.1-no-global-selector-field'
Assert-True ([string]$loadManifest.lifecycle -ceq $expectedLifecycle -and @($loadManifest.topologies.PSObject.Properties.Name).Count -eq 1 -and @($loadManifest.topologies.PSObject.Properties.Name)-contains'REPO_LOCAL' -and @($loadManifest.core)-cnotcontains'PROCESS_REQUIREMENTS.json' -and @($loadManifest.order)-cnotcontains'PROCESS_REQUIREMENTS.json' -and @($loadManifest.order)-cnotcontains'FRAMEWORK_RELEASE.md' -and @($loadManifest.requirementFragments.ownerModule)-cnotcontains'FRAMEWORK_RELEASE.md' -and @($loadManifest.requirementFragments.ownerModule)-cnotcontains'FRAMEWORK_MAINTENANCE.md') 'load-manifest-generic-runtime-and-release-governance-exclusion-contract'
$loadResolverText=Get-Content -LiteralPath (Join-Path $candidateRoot 'scripts\resolve-load-plan.ps1') -Raw -Encoding utf8
Assert-True ($loadResolverText.Contains('LOAD_MANIFEST_NOT_STABLE_1_16_0') -and -not $loadResolverText.Contains('LOAD_MANIFEST_NOT_STABLE_1_15_1')) 'load-resolver-diagnostic-version-current'

$liveFrameworkRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $candidateRoot '../..')))
$liveRepositoryRoot = Split-Path -Parent $liveFrameworkRoot
$rootAttributesText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $liveRepositoryRoot '.gitattributes')
Assert-True ([regex]::Matches($rootAttributesText,'(?m)^\*\.psm1 text eol=lf$').Count-eq1-and[regex]::Matches($rootAttributesText,'(?m)^\*\.mjs text eol=lf$').Count-eq1) 'root-checkout-policy-pins-psm1-and-mjs-lf'
$toolchain=Get-Content -LiteralPath (Join-Path $candidateRoot 'TOOLCHAIN.json') -Raw -Encoding utf8|ConvertFrom-Json
$toolContract=Get-Content -LiteralPath (Join-Path $candidateRoot 'TOOL_CONTRACT.md') -Raw -Encoding utf8
$backend=@($toolchain.officialBackends)[0]
$declaredPlatforms=@($backend.platforms|ForEach-Object{[string]$_})
$expectedOperations=@('AUTHORIZATION_CHECK','CORRECTIONS_CHECK','KNOWLEDGE_IMPACT_CHECK','KNOWLEDGE_QUERY','LOAD_PLAN_RESOLVE','PROCESS_REQUIREMENTS_RESOLVE','PROTECTED_SAFE_GIT','TASK_CARD_CHECK','WORKFLOW_ROUTE_RESOLVE')
$actualOperations=@($backend.entrypoints.PSObject.Properties.Name);[Array]::Sort($expectedOperations,[StringComparer]::Ordinal);[Array]::Sort($actualOperations,[StringComparer]::Ordinal)
Assert-True ([int]$toolchain.schemaVersion-eq1-and[string]$toolchain.frameworkVersion-ceq'1.16.0'-and[string]$toolchain.contractVersion-ceq'1'-and[string]$toolchain.projectSelectionField-ceq'frameworkToolBackend'-and@($toolchain.officialBackends).Count-eq1) 'toolchain-single-project-selected-backend'
Assert-True ([int]$toolchain.routerCompatibility.schemaVersion-eq1-and[string]$toolchain.routerCompatibility.skillName-ceq'ai-workspace-router'-and[string]$toolchain.routerCompatibility.status-ceq'COMPATIBLE'-and[string]$toolchain.routerCompatibility.canonicalSkillPath-ceq'skills/ai-workspace-router/SKILL.md'-and[string]$toolchain.routerCompatibility.versionContractPath-ceq'host/skills/ai-workspace-router/SKILL.md'-and[string]::Join('|',@($toolchain.routerCompatibility.requiredOperations))-ceq'LOAD_PLAN_RESOLVE|PROCESS_REQUIREMENTS_RESOLVE|WORKFLOW_ROUTE_RESOLVE'-and[int]$toolchain.routerCompatibility.processCatalogSchemaVersion-eq2-and[string]$toolchain.routerCompatibility.processCatalogVersion-ceq'3'-and[string]$toolchain.routerCompatibility.nativeRuleBodySource-ceq'MARKDOWN_EXACT_BLOCK') 'toolchain-router-compatibility-exact'
Assert-True ([string]$backend.id-ceq'powershell7'-and[string]$backend.status-ceq'OFFICIAL'-and[string]$backend.runtime.command-ceq'pwsh'-and[string]$backend.runtime.edition-ceq'Core'-and[int]$backend.runtime.minimumMajorVersion-eq7-and($actualOperations-join"`n")-ceq($expectedOperations-join"`n")-and$declaredPlatforms.Count-eq1-and$declaredPlatforms[0]-ceq'windows') 'toolchain-powershell7-operation-set-windows-only'
foreach($entry in $backend.entrypoints.PSObject.Properties){$relative=[string]$entry.Value;$entryPath=Join-Path $candidateRoot $relative;Assert-True ($relative-ceq$relative.Replace('\','/')-and-not[IO.Path]::IsPathRooted($relative)-and-not$relative.Contains('..')-and(Test-Path -LiteralPath $entryPath -PathType Leaf)) ('toolchain-entrypoint|'+$entry.Name);$entryText=Get-Content -LiteralPath $entryPath -Raw -Encoding utf8;Assert-True ($entryText.Contains('POWERSHELL7_REQUIRED')-and-not$entryText.Contains('powershell.exe')) ('toolchain-runtime-guard|'+$entry.Name)}
$conformanceArguments=@($toolchain.conformance.arguments|ForEach-Object{[string]$_})
Assert-True ($conformanceArguments.Count-eq1-and$conformanceArguments[0]-ceq'-SkipBaseline') 'toolchain-conformance-runs-full-no-baseline-suite'
Assert-True (-not(Test-Path -LiteralPath (Join-Path $liveRepositoryRoot '.github\workflows\framework-toolchain-conformance.yml'))) 'three-platform-ci-not-selected-for-windows-only-1.15-scope'
$projectSchemaText=Get-Content -LiteralPath (Join-Path $candidateRoot 'PROJECT_CONFIG_SCHEMA.json') -Raw -Encoding utf8
$maintenanceSchemaText=Get-Content -LiteralPath (Join-Path $liveFrameworkRoot 'maintenance-overlay/PROJECT_CONFIG_SCHEMA.json') -Raw -Encoding utf8
$maintenanceSchema=$maintenanceSchemaText|ConvertFrom-Json
$projectStarterText=Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter/project.json') -Raw -Encoding utf8
Assert-True ($projectSchemaText.Contains('frameworkToolBackend')-and$maintenanceSchemaText.Contains('frameworkToolBackend')-and@($maintenanceSchema.required)-contains'processPolicy'-and$projectStarterText.Contains('"frameworkToolBackend": "powershell7"')-and$toolContract.Contains('projectConfigIdentity')) 'tool-backend-schema-starter-package-binding'

$platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
if($platform-notin$declaredPlatforms){
    Write-Output ('EVIDENCE_CEILING|PLATFORM_NOT_DECLARED|'+$platform)
    Assert-True $true 'tool-contract-undeclared-platform-evidence-ceiling-recorded'
}else{
  $platformTemp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-tool-platform-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $platformTemp|Out-Null
  try{
    $casePath=Join-Path $platformTemp 'CaseProbe';Write-Utf8 $casePath 'case'
    $caseVariantPath=Join-Path $platformTemp 'caseprobe'
    $caseInsensitive=Test-Path -LiteralPath $caseVariantPath
    $caseBehaviorConsistent=if($caseInsensitive){(Get-Identity $caseVariantPath)-ceq(Get-Identity $casePath)}else{-not(Test-Path -LiteralPath $caseVariantPath)}
    Assert-True $caseBehaviorConsistent 'tool-contract-case-behavior-explicit-and-consistent'
    if($IsLinux){Assert-True (-not$caseInsensitive) 'tool-contract-linux-case-sensitive'}else{Assert-True $true 'tool-contract-platform-reported-case-behavior-accepted'}
    $linkTarget=Join-Path $platformTemp 'link-target';$linkPath=Join-Path $platformTemp 'link-probe';New-Item -ItemType Directory -Path $linkTarget|Out-Null;New-TestJunction $linkPath $linkTarget
    Assert-True (((Get-Item -LiteralPath $linkPath -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0) 'tool-contract-link-probe'
    $normalized=[IO.Path]::GetRelativePath($platformTemp,$casePath).Replace('\','/')
    Assert-True ($normalized-ceq'CaseProbe'-and-not$normalized.Contains('\')) 'tool-contract-relative-path-normalized'
    if(-not$IsWindows){
        $mode=[IO.File]::GetUnixFileMode($casePath)
        $executableMode=$mode-bor[IO.UnixFileMode]::UserExecute
        [IO.File]::SetUnixFileMode($casePath,$executableMode)
        Assert-True (([IO.File]::GetUnixFileMode($casePath)-band[IO.UnixFileMode]::UserExecute)-ne0) 'tool-contract-unix-user-execute-permission'
        [IO.File]::SetUnixFileMode($casePath,$mode)
        Assert-True ([IO.File]::GetUnixFileMode($casePath)-eq$mode) 'tool-contract-unix-permission-restored'
    }else{Assert-True $true 'tool-contract-windows-permission-ceiling-explicit'}
    Write-Output ('CONFORMANCE|platform='+$platform+'|caseInsensitive='+$caseInsensitive.ToString().ToLowerInvariant()+'|runtime='+$PSVersionTable.PSVersion.ToString())
  }finally{foreach($link in @($script:testJunctions)){Remove-TestJunction $link};Remove-Item -LiteralPath $platformTemp -Recurse -Force -ErrorAction SilentlyContinue}
}

if($ToolContractOnly){
    $contractTemp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-tool-contract-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $contractTemp|Out-Null
    try{
        $gitRoot=Join-Path $contractTemp 'git-probe';New-GitRepo $gitRoot
        $gitConfigPath=Join-Path $gitRoot '.ai-workspace/project.json'
        $gitConfig=[ordered]@{schemaVersion=3;id='tool-contract-git';displayName='Tool Contract Git';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$false}}}
        Write-Utf8 $gitConfigPath ($gitConfig|ConvertTo-Json -Depth 20)
        $gitVisible=Join-Path $gitRoot 'visible.txt';Write-Utf8 $gitVisible 'baseline';Commit-All $gitRoot 'tool contract baseline';Write-Utf8 $gitVisible 'changed'
        $safeGitEntry=Join-Path $candidateRoot ([string]$backend.entrypoints.PROTECTED_SAFE_GIT)
        $safeGitProbe=Invoke-Ps $safeGitEntry @('-ProjectRoot',$gitRoot,'-Operation','STATUS','-AllowPath','visible.txt','-ExpectedProjectConfigIdentity',(Get-Identity $gitConfigPath))
        Assert-True ($safeGitProbe.Code-eq0-and$safeGitProbe.Text.Contains('visible.txt')-and$safeGitProbe.Text.Contains('"operation":"STATUS"')) 'tool-contract-safe-git-normalized-path'
    }finally{Remove-Item -LiteralPath $contractTemp -Recurse -Force -ErrorAction SilentlyContinue}
    Write-Output "RESULT|$($script:passed) passed|scope=Framework-1.16.0-tool-contract"
    return
}

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

$temp = Join-Path ([IO.Path]::GetTempPath()) ('aiw-framework-113-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$runtimeCandidateRoot=Join-Path $temp 'sealed-runtime\1.16.0'
New-Item -ItemType Directory -Path (Split-Path -Parent $runtimeCandidateRoot) -Force|Out-Null
Copy-Item -LiteralPath $candidateRoot -Destination $runtimeCandidateRoot -Recurse
$null=Seal-ReleaseFixture $runtimeCandidateRoot 'RUNTIME_TEST_FIXTURE'
$loader = Join-Path $runtimeCandidateRoot 'scripts\resolve-load-plan.ps1'
$normalLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX')
$maintenanceLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX','-Topology','FRAMEWORK_MAINTENANCE_SIBLING')
$fallbackLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','PERSPECTIVE_LENSES.md')
$unknownFallbackLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','README.md')
Assert-True ($normalLoad.Code -eq 0 -and $normalLoad.Text.Contains('routeSource=EXPLICIT_NO_TASK') -and $normalLoad.Text.Contains('topology=REPO_LOCAL') -and -not $normalLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md')) 'loader-explicit-no-task-compatible-with-evidence-ceiling'
Assert-True ($maintenanceLoad.Code -ne 0) 'version-loader-rejects-root-owned-maintenance-topology'
Assert-True ($fallbackLoad.Code-eq0-and$fallbackLoad.Text.Contains('fallback=PERSPECTIVE_LENSES.md')-and$fallbackLoad.Text.Contains('AFFECTED_MODULE_FALLBACK')-and$fallbackLoad.Text.Contains('PERSPECTIVE_LENSES.md')-and$unknownFallbackLoad.Code-ne0-and$unknownFallbackLoad.Text.Contains('LOAD_FALLBACK_MODULE_UNKNOWN')) 'loader-bounded-affected-normative-module-fallback-only'

$normalProjectTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\project.json') -Raw -Encoding utf8
$normalControllerTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\controller.json') -Raw -Encoding utf8
try {
    $null = $normalProjectTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{DISPLAY_NAME_JSON}}','"Fixture"').Replace('{{FRAMEWORK_VERSION_JSON}}','"1.16.0"') | ConvertFrom-Json
    $null = $normalControllerTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{CONTROLLER_ID_JSON}}','"controller"') | ConvertFrom-Json
    $normalStarterRendered = $true
} catch { $normalStarterRendered = $false }
Assert-True $normalStarterRendered 'repo-local-starter-json-renders'

$maintenanceOverlayRoot=Join-Path $liveRepositoryRoot 'framework\maintenance-overlay';$overlayManifest=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $maintenanceOverlayRoot 'OVERLAY.json')|ConvertFrom-Json
Assert-True (-not(Test-Path -LiteralPath (Join-Path $candidateRoot 'framework-maintenance-starter'))-and[string]$overlayManifest.overlayId-ceq'framework-maintenance-sibling'-and[string]$overlayManifest.baseStarter-ceq'project-starter'-and[string]$overlayManifest.targetControlPlanePolicy-ceq'ABSENT'-and[string]::Join('|',@($overlayManifest.legacySourceVersions))-ceq'1.15.0|1.15.1') 'maintenance-starter-removed-root-overlay-closed'
$budgetContractRaw=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'tests\PROCESS_REQUIREMENTS_BUDGETS.json');$budgetContract=$budgetContractRaw|ConvertFrom-Json
$authoritySchema=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'AUTHORITY_CONTEXT_SCHEMA.json')|ConvertFrom-Json
$intentSchema=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'INTENT_ENVELOPE_SCHEMA.json')|ConvertFrom-Json
$catalogBudgetIdentity=Get-Identity (Join-Path $candidateRoot 'PROCESS_REQUIREMENTS.json')
$fixtureContractPath=Join-Path $candidateRoot 'tests\PROCESS_REQUIREMENTS_FIXTURES.json';$measurementHarnessPath=Join-Path $candidateRoot 'tests\measure-process-requirements.ps1';$fixtureContract=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureContractPath|ConvertFrom-Json
$adoptionProfile=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'ADOPTION_PROFILE.json')|ConvertFrom-Json
Assert-True ([string]$budgetContract.baseline.version-ceq'1.15.1'-and[string]$budgetContract.baseline.catalogIdentity-ceq'48098|547BBC615BCFC0A281723A1B84AEFD36FECD5CA421C7155C1897D8F4F0CC74C5'-and[string]$budgetContract.candidate.catalogIdentity-ceq$catalogBudgetIdentity) 'process-budget-minor-baseline-and-candidate-catalog-identities-exact'
Assert-True ([string]$adoptionProfile.frameworkVersion-ceq'1.16.0'-and[bool]$adoptionProfile.registrationEligible-and[bool]$adoptionProfile.localCandidatePilotEligible-and[string]::Join('|',@($adoptionProfile.directSourceVersions))-ceq'1.14.1|1.15.0|1.15.1'-and[int]$adoptionProfile.projectControl.schemaVersion-eq4-and[string]$adoptionProfile.projectControl.processCarrierContractVersion-ceq'1.16.0'-and[string]$adoptionProfile.projectControl.frameworkToolBackend-ceq'powershell7'-and[string]$adoptionProfile.projectControl.navigationProjection-ceq'ROOT_CANONICAL_SKILL_MANAGED_AGENTS'-and[string]$adoptionProfile.projectControl.runtimeArtifactRoot-ceq'.ai-workspace/runtime'-and[string]$adoptionProfile.projectControl.runtimeGitIgnoreRule-ceq'/.ai-workspace/runtime/'-and[bool]$adoptionProfile.projectControl.taskLastWriteRequired-and[string]$adoptionProfile.projectControl.capabilityBinding-ceq'EXACT_ENABLED_IDS'-and[int]$adoptionProfile.processBudget.defaultSelectedRulePackBytes-eq32768-and[int]$adoptionProfile.processBudget.absoluteSelectedRulePackBytes-eq98304-and[int]$budgetContract.ceilings.absoluteSelectedRulePackBytes-eq98304) 'adoption-profile-project-policy-budget-and-runtime-contract-exact'
Assert-True (@($authoritySchema.required).Count-eq25-and[int]$budgetContract.candidate.authorityContextFieldCount-eq25-and@($intentSchema.required).Count-eq10-and[int]$budgetContract.candidate.intentEnvelopeFieldCount-eq10-and[int]$budgetContract.candidate.receiptSourceBindingFieldCount-eq11) 'process-budget-schema-field-counts-match-runtime-contract'
$fixtureIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$fixtureBudgetsValid=$true;foreach($fixture in @($budgetContract.fixtures)){if(-not$fixtureIds.Add([string]$fixture.fixtureId)-or[int]$fixture.selectedPackEstimatedTokens-ne[int][math]::Ceiling([int]$fixture.selectedPackBytes/4.0)-or[int]$fixture.selectedPackBytes-lt1-or[int]$fixture.selectedPackBytes-gt[int]$budgetContract.ceilings.absoluteSelectedRulePackBytes-or[int]$fixture.selectedRequirementCount-lt1){$fixtureBudgetsValid=$false};foreach($modeName in @('DISCOVER','ADMIT_ACTION','FINALIZE_OUTPUT')){$runtime=$fixture.observedRuntimeMs.$modeName;if([double]$runtime.median-le0-or[double]$runtime.p95-lt[double]$runtime.median-or[double]$runtime.p95-gt[double]$budgetContract.ceilings.p95Ms.$modeName){$fixtureBudgetsValid=$false}}}
Assert-True ($fixtureBudgetsValid-and$fixtureIds.Count-eq6-and@($budgetContract.measurementContract.statistics)-contains'median'-and@($budgetContract.measurementContract.statistics)-contains'nearest-rank-p95'-and[int]$budgetContract.measurementContract.warmupsPerModeAndFixture-eq1-and[int]$budgetContract.measurementContract.measuredRunsPerModeAndFixture-eq5-and[string]$budgetContract.measurementContract.toleranceFormula-ceq'ceiling(max(2.0 * baselineP95Ms, baselineP95Ms + 250))'-and[string]$budgetContract.candidate.fixtureContractIdentity-ceq(Get-Identity $fixtureContractPath)-and[string]$budgetContract.candidate.measurementHarnessIdentity-ceq(Get-Identity $measurementHarnessPath)-and[string]$budgetContract.evidenceCeiling-like'Bounded five-run*not a statistical performance certification*') 'process-budget-six-exact-fixtures-and-proportional-measurement-protocol-bound'
$fixtureIdentitiesValid=$true;foreach($fixture in @($fixtureContract.fixtures)){$ordered=[ordered]@{};foreach($property in @($fixture.PSObject.Properties)){if($property.Name-cne'fixtureIdentity'){$ordered[$property.Name]=$property.Value}};$computed=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($ordered|ConvertTo-Json -Depth 30 -Compress))));$budgetFixture=@($budgetContract.fixtures|Where-Object{[string]$_.fixtureId-ceq[string]$fixture.fixtureId});if($budgetFixture.Count-ne1-or[string]$fixture.fixtureIdentity-cne$computed-or[string]$budgetFixture[0].fixtureIdentity-cne$computed){$fixtureIdentitiesValid=$false}}
Assert-True ($fixtureIdentitiesValid-and@($fixtureContract.fixtures).Count-eq6) 'process-budget-fixture-record-identities-reproducible'
if($SkipPerformanceSmoke){Assert-True $true 'process-budget-six-fixtures-replay-selected-pack-skipped-for-affected-run'}else{
    $measurementSmoke=Invoke-Ps $measurementHarnessPath @('-Warmups','1','-MeasuredRuns','1','-AsJson');$measurementSmokeValue=if($measurementSmoke.Code-eq0){$measurementSmoke.Text|ConvertFrom-Json}else{$null};$measurementSmokeMatches=$measurementSmoke.Code-eq0-and@($measurementSmokeValue.fixtures).Count-eq6
    if($measurementSmokeMatches){foreach($fixture in @($measurementSmokeValue.fixtures)){$budgetFixture=@($budgetContract.fixtures|Where-Object{[string]$_.fixtureId-ceq[string]$fixture.fixtureId});if($budgetFixture.Count-ne1-or[int]$budgetFixture[0].selectedPackBytes-ne[int]$fixture.selectedPackBytes-or[int]$budgetFixture[0].selectedPackEstimatedTokens-ne[int]$fixture.selectedPackEstimatedTokens-or[int]$budgetFixture[0].selectedRequirementCount-ne[int]$fixture.selectedRequirementCount){$measurementSmokeMatches=$false}}}
    Assert-True $measurementSmokeMatches 'process-budget-six-fixtures-replay-selected-pack'
}
$contextBudgetsValid=$true
$rootRouterPath=Join-Path $liveRepositoryRoot 'skills\ai-workspace-router\SKILL.md';$versionRouterContractPath=Join-Path $candidateRoot 'host\skills\ai-workspace-router\SKILL.md';$routerBytes=[int64](Get-Item -LiteralPath $rootRouterPath).Length;$routerIdentity=Get-Identity $rootRouterPath;$routerSkillText=Get-Content -Raw -Encoding utf8 -LiteralPath $rootRouterPath;$versionRouterContract=Get-Content -Raw -Encoding utf8 -LiteralPath $versionRouterContractPath
foreach($context in @($budgetContract.endToEndContexts)){
    $fixture=@($budgetContract.fixtures|Where-Object{[string]$_.fixtureId-ceq[string]$context.caseId})
    $contextFields=@($context.PSObject.Properties.Name);$loadPlanBytes=0L;foreach($module in @($context.loadPlanModules)){$modulePath=Join-Path $candidateRoot ([string]$module);if(-not(Test-Path -LiteralPath $modulePath -PathType Leaf)){$contextBudgetsValid=$false}else{$loadPlanBytes+=[int64](Get-Item -LiteralPath $modulePath).Length}}
    $total=$routerBytes+$loadPlanBytes+[int64]$fixture[0].selectedPackBytes;$estimated=[int][math]::Ceiling($total/4.0)
    if($fixture.Count-ne1-or$contextFields.Count-ne4-or@(@('caseId','loadPlanModules','catalogModelLoaded','projectTaskFactsExcluded')|Where-Object{$_-cnotin$contextFields}).Count-ne0-or@($context.loadPlanModules).Count-ne0-or[bool]$context.catalogModelLoaded-or-not[bool]$context.projectTaskFactsExcluded-or$total-gt[int64]$budgetContract.ceilings.frameworkControlledContextBytes-or$estimated-gt[int]$budgetContract.ceilings.frameworkControlledContextEstimatedTokens){$contextBudgetsValid=$false}
}
Assert-True ($contextBudgetsValid-and@($budgetContract.endToEndContexts).Count-eq3-and[string]$budgetContract.evidenceCeiling-like'*project/task facts*excluded*') 'process-budget-normal-path-derived-router-plus-selected-blocks-without-load-plan-modules'
Assert-True ($routerIdentity-ceq(Get-Identity $rootRouterPath)-and$versionRouterContract.Contains('REFERENCE_ONLY / VERSION_CONTRACT / NON_INSTALLABLE / NON_AUTHORITY')-and$versionRouterContract.Contains('skills/ai-workspace-router/SKILL.md')-and-not$versionRouterContract.StartsWith('---')-and-not(Test-Path -LiteralPath (Join-Path $candidateRoot 'project-starter\.agents\skills\ai-workspace-router'))-and-not(Test-Path -LiteralPath (Join-Path $maintenanceOverlayRoot '.agents\skills\ai-workspace-router'))) 'router-skill-single-root-canonical-source-and-version-contract-history'
$plusRouterText=$routerSkillText.Insert($routerSkillText.Length-1,' ');$minusIndex=$routerSkillText.IndexOf(' Skill 是 Framework',[StringComparison]::Ordinal);$minusRouterText=$routerSkillText.Remove($minusIndex,1)
Assert-True ($minusIndex-gt0-and$utf8.GetByteCount($plusRouterText)-eq$routerBytes+1-and$utf8.GetByteCount($minusRouterText)-eq$routerBytes-1-and(Test-RouterSkillContract $plusRouterText ($utf8.GetByteCount($plusRouterText)) ([int64]$budgetContract.ceilings.routerSkillBytes))-and(Test-RouterSkillContract $minusRouterText ($utf8.GetByteCount($minusRouterText)) ([int64]$budgetContract.ceilings.routerSkillBytes))) 'router-derived-byte-measurement-allows-harmless-plus-minus-one-under-ceiling'
$semanticDeletion=$routerSkillText.Replace('FINALIZE_OUTPUT','FINALIZE_OMITTED');$oversizedRouter=$routerSkillText+('x'*([int]$budgetContract.ceilings.routerSkillBytes-$routerBytes+1))
Assert-True (-not(Test-RouterSkillContract $semanticDeletion ($utf8.GetByteCount($semanticDeletion)) ([int64]$budgetContract.ceilings.routerSkillBytes))-and-not(Test-RouterSkillContract $oversizedRouter ($utf8.GetByteCount($oversizedRouter)) ([int64]$budgetContract.ceilings.routerSkillBytes))) 'router-required-semantic-deletion-and-maximum-ceiling-independently-rejected'
foreach($starterEntry in @([pscustomobject]@{Name='project-starter';Path=(Join-Path $candidateRoot 'project-starter\AGENTS.md')},[pscustomobject]@{Name='maintenance-overlay';Path=(Join-Path $maintenanceOverlayRoot 'AGENTS.md')})){
    $agentsText=Get-Content -Raw -Encoding utf8 -LiteralPath $starterEntry.Path
    Assert-True (Test-RouterSkillContract $routerSkillText $routerBytes ([int64]$budgetContract.ceilings.routerSkillBytes)) ('host-global-router-skill-bounded-natural-reactivation-no-per-tool|'+$starterEntry.Name)
    Assert-True ([regex]::Matches($agentsText,'AI-WORKSPACE-FRAMEWORK:BEGIN').Count-eq1-and[regex]::Matches($agentsText,'AI-WORKSPACE-FRAMEWORK:END').Count-eq1-and$agentsText.Contains('ai-workspace-router')) ('agents-managed-router-block-exact|'+$starterEntry.Name)
}
$catalogGenerator=Join-Path $candidateRoot 'scripts\build-process-requirements.ps1'
$catalogCheck=Invoke-Ps $catalogGenerator @('-Check')
Assert-True ($catalogCheck.Code-eq0-and$catalogCheck.Text.Contains('PASS|requirements=35|fragments=9')) 'process-requirements-canonical-fragments-match-generated-catalog'
$catalogText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROCESS_REQUIREMENTS.json');$catalog=$catalogText|ConvertFrom-Json
$blockProjectionValid=-not$catalogText.Contains('"fullText"')
foreach($fragmentPath in Get-ChildItem -LiteralPath (Join-Path $candidateRoot 'requirements\fragments') -File -Filter '*.json'){
    $fragmentText=Get-Content -Raw -Encoding utf8 -LiteralPath $fragmentPath.FullName
    if($fragmentText.Contains('"fullText"')){$blockProjectionValid=$false}
}
foreach($requirement in @($catalog.requirements)){
    $requirementId=[string]$requirement.requirementId;$locator='AIW-REQUIREMENT:'+$requirementId
    if([string]$requirement.exactBlockLocator-cne$locator){$blockProjectionValid=$false;continue}
    $ownerText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot ([string]$requirement.ownerModule))
    $begin='<!-- '+$locator+':BEGIN -->';$end='<!-- '+$locator+':END -->'
    $beginMatches=[regex]::Matches($ownerText,[regex]::Escape($begin));$endMatches=[regex]::Matches($ownerText,[regex]::Escape($end))
    if($beginMatches.Count-ne1-or$endMatches.Count-ne1-or$endMatches[0].Index-le($beginMatches[0].Index+$begin.Length)){$blockProjectionValid=$false;continue}
    $body=$ownerText.Substring($beginMatches[0].Index+$begin.Length,$endMatches[0].Index-($beginMatches[0].Index+$begin.Length)).Trim()
    if([string]::IsNullOrWhiteSpace($body)){$blockProjectionValid=$false}
}
Assert-True ($blockProjectionValid-and@($catalog.requirements).Count-eq35) 'process-requirements-metadata-only-catalog-exact-markdown-blocks-nonempty'
$catalogDriftRoot=Join-Path $temp 'catalog-drift-fixture';Copy-Item -LiteralPath $candidateRoot -Destination $catalogDriftRoot -Recurse
$catalogDriftPath=Join-Path $catalogDriftRoot 'PROCESS_REQUIREMENTS.json';Write-Utf8 $catalogDriftPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $catalogDriftPath).Replace('Independent action authorization','Drifted title'))
$catalogDriftCheck=Invoke-Ps (Join-Path $catalogDriftRoot 'scripts\build-process-requirements.ps1') @('-Check')
Assert-True ($catalogDriftCheck.Code-ne0-and$catalogDriftCheck.Text.Contains('PROCESS_REQUIREMENTS_PROJECTION_DRIFT')) 'process-requirements-generated-catalog-drift-rejected'
$duplicateOwnerRoot=Join-Path $temp 'catalog-duplicate-owner-fixture';Copy-Item -LiteralPath $candidateRoot -Destination $duplicateOwnerRoot -Recurse
$duplicateOwnerManifestPath=Join-Path $duplicateOwnerRoot 'LOAD_MANIFEST.json';$duplicateOwnerManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $duplicateOwnerManifestPath|ConvertFrom-Json;$duplicateOwnerManifest.requirementFragments[1].ownerModule=$duplicateOwnerManifest.requirementFragments[0].ownerModule;Write-Utf8 $duplicateOwnerManifestPath ($duplicateOwnerManifest|ConvertTo-Json -Depth 40)
$duplicateOwnerRun=Invoke-Ps (Join-Path $duplicateOwnerRoot 'scripts\build-process-requirements.ps1') @('-Check')
Assert-True ($duplicateOwnerRun.Code-ne0-and$duplicateOwnerRun.Text.Contains('REQUIREMENT_FRAGMENT_ENTRY_VALUES')) 'process-requirements-generator-rejects-duplicate-owner-module'
$missingOwnerRoot=Join-Path $temp 'catalog-missing-owner-fixture';Copy-Item -LiteralPath $candidateRoot -Destination $missingOwnerRoot -Recurse
$missingOwnerManifestPath=Join-Path $missingOwnerRoot 'LOAD_MANIFEST.json';$missingOwnerManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $missingOwnerManifestPath|ConvertFrom-Json;$missingOwnerEntry=$missingOwnerManifest.requirementFragments[0];$missingOwnerEntry.ownerModule='MISSING_OWNER.md';Write-Utf8 $missingOwnerManifestPath ($missingOwnerManifest|ConvertTo-Json -Depth 40);$missingOwnerFragmentPath=Join-Path $missingOwnerRoot ([string]$missingOwnerEntry.sidecar);$missingOwnerFragment=Get-Content -Raw -Encoding utf8 -LiteralPath $missingOwnerFragmentPath|ConvertFrom-Json;$missingOwnerFragment.ownerModule='MISSING_OWNER.md';Write-Utf8 $missingOwnerFragmentPath ($missingOwnerFragment|ConvertTo-Json -Depth 40)
$missingOwnerRun=Invoke-Ps (Join-Path $missingOwnerRoot 'scripts\build-process-requirements.ps1') @('-Check')
Assert-True ($missingOwnerRun.Code-ne0-and$missingOwnerRun.Text.Contains('REQUIREMENT_OWNER_MODULE_MISSING|MISSING_OWNER.md')) 'process-requirements-generator-rejects-missing-normative-owner-module'

$workflowEntryDocuments = @((Join-Path $candidateRoot 'TASK_AND_SCOPE.md'),(Join-Path $candidateRoot 'HOST_CODEX.md'),(Join-Path $candidateRoot 'PROMPTS.md'),(Join-Path $candidateRoot 'project-starter/BOOTSTRAP.md'),(Join-Path $maintenanceOverlayRoot 'BOOTSTRAP.md'))
foreach ($entryPath in $workflowEntryDocuments) {
    $entryText = Get-Content -LiteralPath $entryPath -Raw -Encoding utf8
    Assert-True ($entryText.Contains('WORKFLOW_ROUTE_RESOLVE') -and $entryText.Contains('TOOLCHAIN.json') -and $entryText.Contains('ephemeral') -and $entryText.Contains('fail closed')) ('workflow-live-entry-fail-closed|' + $entryPath)
}

$rootReleaseGovernancePath=Join-Path $liveFrameworkRoot 'FRAMEWORK_RELEASE.md'
$releaseGovernanceText=Get-Content -Raw -Encoding utf8 -LiteralPath $rootReleaseGovernancePath
$reviewEvidenceText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'REVIEW_AND_EVIDENCE.md')
$projectControlText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROJECT_CONTROL.md')
$examplesText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'EXAMPLES.md')
$evaluationText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROCESS_REQUIREMENTS_EVALUATION.md')
$processCatalogText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROCESS_REQUIREMENTS.json')
Assert-True ($projectControlText.Contains('coverage metadata 不是 semantic proof')-and$reviewEvidenceText.Contains('coverage ID、changelog 声明或近似措辞本身不是 acceptance evidence')) 'correction-incorporation-coverage-metadata-alone-insufficient'
Assert-True ($projectControlText.Contains('project-scoped alias、native requirement、catalog identity 与 canonical source-record identity')-and$projectControlText.Contains('load manifest 可达的 applicable normative modules')-and$projectControlText.Contains('被 behavior tests 覆盖')-and$reviewEvidenceText.Contains('原始 correction reason、effective rule 与 applicability boundary 对照实际 normative modules 与 behavior tests')-and$projectControlText.Contains('不创建 correction-to-module registry 或 absorption ledger')) 'correction-incorporation-binds-native-rule-source-tests-review-without-registry'
Assert-True ($evaluationText.Contains('显式采用 stable `1.16.0` 后才开始 observation')-and$evaluationText.Contains('使用正常 project task')-and$evaluationText.Contains('来源 task 保留一条 compact record')-and$evaluationText.Contains('不规定固定 sample count/time window')-and$evaluationText.Contains('不是 release gate')-and$evaluationText.Contains('不替代 conformance、independent Review、`OWNER_ACCEPT` 或 release sealing')-and-not$evaluationText.Contains('exactly 20 admitted samples')-and-not$evaluationText.Contains('INSUFFICIENT_SAMPLE / NO_ADVANCE')) 'post-release-project-observation-nonblocking-no-synthetic-work'
Assert-True ((Test-Path -LiteralPath $rootReleaseGovernancePath -PathType Leaf)-and-not(Test-Path -LiteralPath (Join-Path $candidateRoot 'FRAMEWORK_RELEASE.md'))-and@($inventory.explanationAndHistory)-cnotcontains'FRAMEWORK_RELEASE.md'-and-not$reviewEvidenceText.Contains('PR_REVIEW_CANDIDATE_FREEZE_AND_SEQUENCE')-and-not$processCatalogText.Contains('"requirementId": "PR_REVIEW_CANDIDATE_FREEZE_AND_SEQUENCE"')-and(Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $liveRepositoryRoot 'AGENTS.md')).Contains('framework/FRAMEWORK_RELEASE.md')) 'release-governance-root-owned-and-absent-from-version-payload'
Assert-True ($releaseGovernanceText.Contains('final candidate freeze 只跑一次 complete current-version suite')-and$releaseGovernanceText.Contains('只有 shared root tools、upgrade compatibility、Tool Contract 或 baseline execution boundary 受影响时，才重跑 baseline executable suite')-and$releaseGovernanceText.Contains('一个 independent CRITICAL Source Review')-and$releaseGovernanceText.Contains('Maintenance `OWNER_ACCEPT` 独立接受 exact approved candidate')-and$releaseGovernanceText.Contains('没有未 Review 的 free-form/executable change 时，不需要第二次 semantic post-seal Review')-and$releaseGovernanceText.Contains('deterministic publication preflight')-and$releaseGovernanceText.Contains('publication 顺序为 `github/main` 后 `origin/main`')-and$releaseGovernanceText.Contains('失败即停止')-and$reviewEvidenceText.Contains('same-scope repair 使用新 writer package')-and$reviewEvidenceText.Contains('focused rereview')) 'release-sequence-proportional-review-owner-accept-seal-git-review-and-two-remote-stopline'
Assert-True (-not$processCatalogText.Contains('level_test2')-and-not$processCatalogText.Contains('Pocket')) 'process-catalog-generic-no-consumer-paths'

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

- Task schema: 1.16.0
- Owner: owner-fixture
- Work route: actor=owner-fixture; role=DOMAIN_OWNER; phase=PLAN
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
    Write-Utf8 $standardTaskPath "# TASK-STANDARD-001 - fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=executor-fixture; role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $standardTaskValid = Invoke-Ps $taskChecker @('-TaskPath',$standardTaskPath)
    Assert-True ($standardTaskValid.Code -eq 0 -and $standardTaskValid.Text.Contains('loadContext=ACTOR_BOUND') -and $standardTaskValid.Text.Contains('actor=executor-fixture') -and $standardTaskValid.Text.Contains('role=EXECUTOR') -and $standardTaskValid.Text.Contains('phase=IMPLEMENT')) 'task-card-standard-actor-bound-work-route'
    $taskBoundLoad=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','executor-fixture','-IncludeRecovery','-HostName','CODEX')
    Assert-True ($taskBoundLoad.Code-eq0-and$taskBoundLoad.Text.Contains('routeSource=TASK_CARD')-and$taskBoundLoad.Text.Contains('phases=RECOVER,IMPLEMENT')-and$taskBoundLoad.Text.Contains('PROJECT_CONTROL.md')-and$taskBoundLoad.Text.Contains('TASK_AND_SCOPE.md')) 'loader-task-bound-recover-plus-work-phase'
    $taskRouteDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','executor-fixture','-Role','REVIEWER','-Profile','STANDARD','-Phase','IMPLEMENT','-HostName','CODEX')
    Assert-True ($taskRouteDrift.Code-ne0-and$taskRouteDrift.Text.Contains('LOAD_TASK_ROLE_DRIFT')) 'loader-rejects-caller-role-drift'
    Write-Utf8 $standardTaskPath "# TASK-STANDARD-001 - fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=reviewer-fixture; role=REVIEWER; phase=REVIEW`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $reviewTaskLoad=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','reviewer-fixture','-HostName','CODEX')
    Assert-True ($reviewTaskLoad.Code-eq0-and$reviewTaskLoad.Text.Contains('routeSource=TASK_CARD')-and$reviewTaskLoad.Text.Contains('phases=REVIEW')-and$reviewTaskLoad.Text.Contains('TASK_AND_SCOPE.md')-and$reviewTaskLoad.Text.Contains('REVIEW_AND_EVIDENCE.md')-and-not$reviewTaskLoad.Text.Contains('PROJECT_CONTROL.md')) 'loader-task-bound-review-transition-workset'
    $taskPhaseDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','reviewer-fixture','-Role','REVIEWER','-Profile','STANDARD','-Phase','IMPLEMENT','-HostName','CODEX')
    Assert-True ($taskPhaseDrift.Code-ne0-and$taskPhaseDrift.Text.Contains('LOAD_TASK_PHASE_DRIFT')) 'loader-rejects-caller-phase-drift'
    $taskProfileDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','reviewer-fixture','-Role','REVIEWER','-Profile','CRITICAL','-Phase','REVIEW','-HostName','CODEX')
    Assert-True ($taskProfileDrift.Code-ne0-and$taskProfileDrift.Text.Contains('LOAD_TASK_PROFILE_DRIFT')) 'loader-rejects-caller-profile-drift'
    $schema111TaskPath=Join-Path $temp 'TASK-SCHEMA-1.11-ROUTE-001.md'
    Write-Utf8 $schema111TaskPath "# TASK-SCHEMA-1.11-ROUTE-001 - fixture`n`n- Task schema: 1.11.0`n- Owner: owner-fixture`n- Work route: role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $schema111TaskCheck=Invoke-Ps $taskChecker @('-TaskPath',$schema111TaskPath)
    $schema111TaskLoad=Invoke-Ps $loader @('-TaskPath',$schema111TaskPath,'-HostName','CODEX')
    Assert-True ($schema111TaskCheck.Code-eq0-and$schema111TaskCheck.Text.Contains('evidenceCeiling=LEGACY_ACTOR_CONTEXT_UNBOUND')-and$schema111TaskLoad.Code-eq0-and$schema111TaskLoad.Text.Contains('routeSource=LEGACY_ACTOR_CONTEXT_UNBOUND')-and$schema111TaskLoad.Text.Contains('evidenceCeiling=LEGACY_ACTOR_CONTEXT_UNBOUND')-and$schema111TaskLoad.Text.Contains('phases=IMPLEMENT')) 'schema-1.11-two-field-work-route-readable-with-actor-ceiling'
    $missingRouteTaskPath=Join-Path $temp 'TASK-MISSING-ROUTE-001.md'
    Write-Utf8 $missingRouteTaskPath "# TASK-MISSING-ROUTE-001 - fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $missingRouteCheck=Invoke-Ps $taskChecker @('-TaskPath',$missingRouteTaskPath)
    $missingRouteLoad=Invoke-Ps $loader @('-TaskPath',$missingRouteTaskPath,'-Role','EXECUTOR','-Profile','STANDARD','-Phase','IMPLEMENT')
    Assert-True ($missingRouteCheck.Code-ne0-and$missingRouteCheck.Text.Contains('WORK_ROUTE_ACTOR_FIELD')-and$missingRouteLoad.Code-ne0-and$missingRouteLoad.Text.Contains('LOAD_TASK_WORK_ROUTE_REQUIRED')) 'schema-1.13-actor-work-route-required'
    $missing111RouteTaskPath=Join-Path $temp 'TASK-SCHEMA-1.11-MISSING-ROUTE-001.md'
    Write-Utf8 $missing111RouteTaskPath "# TASK-SCHEMA-1.11-MISSING-ROUTE-001 - fixture`n`n- Task schema: 1.11.0`n- Owner: owner-fixture`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $missing111RouteCheck=Invoke-Ps $taskChecker @('-TaskPath',$missing111RouteTaskPath)
    $missing111RouteLoad=Invoke-Ps $loader @('-TaskPath',$missing111RouteTaskPath,'-Role','EXECUTOR','-Profile','STANDARD','-Phase','IMPLEMENT')
    Assert-True ($missing111RouteCheck.Code-ne0-and$missing111RouteCheck.Text.Contains('WORK_ROUTE_FIELD')-and$missing111RouteLoad.Code-ne0-and$missing111RouteLoad.Text.Contains('LOAD_TASK_WORK_ROUTE_REQUIRED')) 'schema-1.11-work-route-required'
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
    $controlPlane = Render-MaintenanceStarter (Join-Path $candidateRoot 'project-starter') $maintenanceOverlayRoot $control
    $renderedFiles = Get-ChildItem -LiteralPath $controlPlane -Recurse -Force -File
    Assert-True (@($renderedFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8).Contains('{{') }).Count -eq 0) 'maintenance-starter-placeholders-closed'
    $renderedMaintenancePolicy=Get-Content -LiteralPath (Join-Path $controlPlane 'process-policy.json') -Raw -Encoding utf8|ConvertFrom-Json
    Assert-True (@($renderedMaintenancePolicy.rules|Where-Object{[string]$_.ruleId-ceq'FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY'}).Count-eq1) 'maintenance-root-overlay-project-policy-projected-once'

    $configPath = Join-Path $controlPlane 'project.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
    $config.routineExcludedPaths = @('.ai-workspace/private.txt')
    $config.frameworkTarget.routineExcludedPaths = @('private/secret.txt')
    Write-Utf8 $configPath ($config | ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $control '.ai-workspace\private.txt') 'control private'
    Write-Utf8 (Join-Path $target 'README.md') '# AI-Workspace fixture'
    Write-Utf8 (Join-Path $target 'AGENTS.md') '# Fixture instructions'
    New-Item -ItemType Directory -Path (Join-Path $target 'scripts'),(Join-Path $target 'framework') -Force|Out-Null
    foreach($rootScript in @('MaintenanceOverlay.psm1','resolve-framework-maintenance-target.ps1','check-framework-maintenance-authorization.ps1','invoke-framework-maintenance-safe-git.ps1','resolve-framework-maintenance-process-requirements.ps1')){Copy-Item -LiteralPath (Join-Path $liveRepositoryRoot ('scripts\'+$rootScript)) -Destination (Join-Path $target ('scripts\'+$rootScript)) -Force}
    Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'maintenance-overlay') -Destination (Join-Path $target 'framework\maintenance-overlay') -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $target 'framework\versions') -Force | Out-Null
    foreach($sourceVersionFixture in @('1.14.1','1.15.0','1.15.1')){Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot ('versions\'+$sourceVersionFixture)) -Destination (Join-Path $target ('framework\versions\'+$sourceVersionFixture)) -Recurse}
    Copy-Item -LiteralPath $candidateRoot -Destination (Join-Path $target 'framework\versions\1.16.0') -Recurse
    $null=Seal-ReleaseFixture (Join-Path $target 'framework\versions\1.16.0') 'MAINTENANCE_TARGET_TEST_FIXTURE'
    Write-Utf8 (Join-Path $target 'docs\public.txt') 'public target'
    Write-Utf8 (Join-Path $target 'private\secret.txt') 'private target'
    $configIdentity = Get-Identity $configPath

    $installedFramework = Join-Path $target 'framework\versions\1.16.0'
    $installedActual = @(Get-ChildItem -LiteralPath $installedFramework -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($installedFramework.Length + 1).Replace('\','/') })
    [Array]::Sort($installedActual,[StringComparer]::Ordinal)
    Assert-True ($installedActual.Count -eq $actual.Count -and ($installedActual -join "`n") -ceq ($actual -join "`n")) 'maintenance-target-full-sealed-fixture-installed'
    $controllerSchema = Get-Content -LiteralPath (Join-Path $installedFramework 'CONTROLLER_SCHEMA.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ([string]$controllerSchema.properties.state.const -ceq 'CURRENT' -and $null -eq $controllerSchema.properties.state.PSObject.Properties['enum']) 'controller-schema-current-only'

    $resolver = Join-Path $target 'scripts\resolve-framework-maintenance-target.ps1'
    $checker = Join-Path $target 'scripts\check-framework-maintenance-authorization.ps1'
    $controlObject = '.ai-workspace/tasks/README.md'
    $targetObject = 'docs/public.txt'
    $controllerPath = Join-Path $controlPlane 'controller.json'
    $resolve = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
    if($resolve.Code-ne0){Write-Output ('DIAG|maintenance-resolver|code='+$resolve.Code+'|'+$resolve.Text)}
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
    New-AuthorizationPackage $maintenanceSchema1Package 1 '' $configIdentity @('SOURCE_WRITE') $targetObject $targetObjectIdentity -DomainOwner
    $maintenanceSchema1Steady = Invoke-Ps $checker @('-PackagePath',$maintenanceSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+$targetObjectIdentity),'-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity,'-TaskPath','.ai-workspace/tasks/active/FIXTURE-OWNER-001.md','-ExpectedTaskIdentity',(Get-Identity (Join-Path $control '.ai-workspace/tasks/active/FIXTURE-OWNER-001.md'))) $control
    Assert-True ($maintenanceSchema1Steady.Code -ne 0 -and $maintenanceSchema1Steady.Text.Contains('SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3')) 'authorization-schema1-maintenance-steady-state-rejected'

    $maintenance116ConfigRaw=Get-Content -LiteralPath $configPath -Raw -Encoding utf8;$maintenance116Config=$maintenance116ConfigRaw|ConvertFrom-Json
    $maintenancePolicyPath=Join-Path $controlPlane 'process-policy.json';$maintenance116PolicyRaw=Get-Content -LiteralPath $maintenancePolicyPath -Raw -Encoding utf8
    foreach($sourceVersion in @('1.15.0','1.15.1')){
        $sourceConfig=$maintenance116ConfigRaw|ConvertFrom-Json;$sourceConfig.frameworkVersion=$sourceVersion;Write-Utf8 $configPath ($sourceConfig|ConvertTo-Json -Depth 20)
        $sourcePolicy=[ordered]@{schemaVersion=1;contractVersion='1.14.0';projectId=[string]$maintenance116Config.id;rules=@()};Write-Utf8 $maintenancePolicyPath ($sourcePolicy|ConvertTo-Json -Depth 30)
        $sourceIdentity=Get-Identity $configPath;$upgradePackage=Join-Path $controlPlane ('maintenance-schema3-'+$sourceVersion+'.json');New-MaintenanceUpgradeAuthorizationPackage $upgradePackage $sourceIdentity $controlObject $controlObjectIdentity
        $upgradeAuthorization=Invoke-FixtureSchema2Authorization $checker $upgradePackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $sourceIdentity
        if($upgradeAuthorization.Code-ne0){Write-Output ('DIAG|authorization-schema3-maintenance-exact-source|'+$sourceVersion+'|'+$upgradeAuthorization.Code+'|'+$upgradeAuthorization.Text)}
        Assert-True ($upgradeAuthorization.Code-eq0-and$upgradeAuthorization.Text.Contains('action=CONTROL_WRITE')) ('authorization-schema3-maintenance-exact-source-pass|'+$sourceVersion)
    }

    function Invoke-MaintenanceSchema3Rejected($Config,[string]$Name) {
        Write-Utf8 $configPath ($Config|ConvertTo-Json -Depth 30);$policy=[ordered]@{schemaVersion=1;contractVersion='1.14.0';projectId=[string]$maintenance116Config.id;rules=@()};Write-Utf8 $maintenancePolicyPath ($policy|ConvertTo-Json -Depth 30);$identity=Get-Identity $configPath;$packagePath=Join-Path $controlPlane ('maintenance-schema3-reject-'+$Name+'.json');New-MaintenanceUpgradeAuthorizationPackage $packagePath $identity $controlObject $controlObjectIdentity
        $run=Invoke-FixtureSchema2Authorization $checker $packagePath $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $identity
        Assert-True ($run.Code-ne0-and($run.Text.Contains('SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3')-or$run.Text.Contains('FAIL|framework-maintenance-authorization|'))) ('authorization-schema3-maintenance-rejects-'+$Name)
    }
    $badSource=$maintenance116ConfigRaw|ConvertFrom-Json;$badSource.frameworkVersion='1.14.1';Invoke-MaintenanceSchema3Rejected $badSource 'unlisted-source'
    $extraTarget=$maintenance116ConfigRaw|ConvertFrom-Json;$extraTarget.frameworkVersion='1.15.0';$extraTarget.frameworkTarget|Add-Member -NotePropertyName extra -NotePropertyValue 'forbidden';Invoke-MaintenanceSchema3Rejected $extraTarget 'extra-target-field'
    $unsafeSibling=$maintenance116ConfigRaw|ConvertFrom-Json;$unsafeSibling.frameworkVersion='1.15.0';$unsafeSibling.frameworkTarget.siblingDirectory='../AI-Workspace';Invoke-MaintenanceSchema3Rejected $unsafeSibling 'unsafe-sibling'
    $controlTarget=$maintenance116ConfigRaw|ConvertFrom-Json;$controlTarget.frameworkVersion='1.15.0';$controlTarget.frameworkTarget.repositoryId='CONTROL';Invoke-MaintenanceSchema3Rejected $controlTarget 'control-target-id'
    $missingTarget=$maintenance116ConfigRaw|ConvertFrom-Json;$missingTarget.frameworkVersion='1.15.0';$missingTarget.frameworkTarget.siblingDirectory='Missing-Target';Invoke-MaintenanceSchema3Rejected $missingTarget 'wrong-target-git-top'
    $linkPath=Join-Path $pair 'AI-Workspace-Link';New-TestJunction $linkPath $target;try{$linkedTarget=$maintenance116ConfigRaw|ConvertFrom-Json;$linkedTarget.frameworkVersion='1.15.0';$linkedTarget.frameworkTarget.siblingDirectory='AI-Workspace-Link';Invoke-MaintenanceSchema3Rejected $linkedTarget 'target-reparse'}finally{Remove-TestJunction $linkPath}
    New-Item -ItemType Directory -Path (Join-Path $target '.ai-workspace')|Out-Null;try{$targetControl=$maintenance116ConfigRaw|ConvertFrom-Json;$targetControl.frameworkVersion='1.15.0';Invoke-MaintenanceSchema3Rejected $targetControl 'target-control-plane'}finally{Remove-Item -LiteralPath (Join-Path $target '.ai-workspace') -Recurse -Force}
    & git -C $pair init -q;try{$parentGit=$maintenance116ConfigRaw|ConvertFrom-Json;$parentGit.frameworkVersion='1.15.0';Invoke-MaintenanceSchema3Rejected $parentGit 'workspace-parent-git'}finally{Remove-Item -LiteralPath (Join-Path $pair '.git') -Recurse -Force}
    Write-Utf8 $configPath $maintenance116ConfigRaw;Write-Utf8 $maintenancePolicyPath $maintenance116PolicyRaw;$configIdentity=Get-Identity $configPath

    $invalidStatePackage = Join-Path $controlPlane 'invalid-state-auth.json'
    $invalidStateDomainPackage = Join-Path $controlPlane 'invalid-state-domain-auth.json'
    New-AuthorizationPackage $invalidStatePackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject))
    New-AuthorizationPackage $invalidStateDomainPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject)) -DomainOwner
    $controllerRawBeforeInvalidState = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $invalidController = $controllerRawBeforeInvalidState | ConvertFrom-Json
    $invalidController.state = 'NOT_CURRENT'
    Write-Utf8 $controllerPath ($invalidController | ConvertTo-Json -Depth 10)
    $invalidStateResolve = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
    $invalidStateAuth = Invoke-FixtureSchema2Authorization $checker $invalidStatePackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject (Get-Identity (Join-Path $control $controlObject)) 'CONTROL' $configIdentity
    $invalidStateDomainAuth = Invoke-FixtureSchema2Authorization $checker $invalidStateDomainPackage $control 'owner-fixture' 'CONTROL_WRITE' $controlObject (Get-Identity (Join-Path $control $controlObject)) 'CONTROL' $configIdentity
    Write-Utf8 $controllerPath $controllerRawBeforeInvalidState
    Assert-True ($invalidStateResolve.Code -ne 0 -and $invalidStateResolve.Text.Contains('CONTROLLER_VALUES')) 'non-current-controller-rejected-by-resolver'
    Assert-True ($invalidStateAuth.Code -ne 0 -and $invalidStateAuth.Text.Contains('CONTROLLER_VALUES') -and $invalidStateDomainAuth.Code -ne 0 -and $invalidStateDomainAuth.Text.Contains('CONTROLLER_VALUES')) 'non-current-controller-cannot-authorize-any-issuer-role'

    $targetControl = Join-Path $target '.ai-workspace'
    New-Item -ItemType Directory -Path $targetControl -Force | Out-Null
    Write-Utf8 (Join-Path $targetControl 'controller.json') (@{schemaVersion=1;projectId='foreign';controllerId='foreign';controllerEpoch=1;state='CURRENT'} | ConvertTo-Json)
    $completeTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $completeControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $completeTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    $completeSchema1Auth = Invoke-FixtureSchema2Authorization $checker $maintenanceSchema1Package $control 'owner-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Recurse -Force
    Assert-True ($completeTargetControl.Code -ne 0 -and $completeTargetControl.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'maintenance-resolver-complete-target-control-plane-rejected'
    Assert-True ($completeControlAuth.Code -ne 0 -and $completeTargetAuth.Code -ne 0 -and $completeControlAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN') -and $completeTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema2-complete-target-control-plane-denies-control-and-target'
    Assert-True ($completeSchema1Auth.Code -ne 0 -and $completeSchema1Auth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema1-maintenance-nonsteady-rejected'

    New-Item -ItemType Directory -Path $targetControl -Force | Out-Null
    $partialTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $partialControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $partialTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Recurse -Force
    Assert-True ($partialTargetControl.Code -ne 0 -and $partialTargetControl.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'maintenance-resolver-partial-target-control-plane-rejected'
    Assert-True ($partialControlAuth.Code -ne 0 -and $partialTargetAuth.Code -ne 0 -and $partialControlAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN') -and $partialTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema2-partial-target-control-plane-denies-control-and-target'

    Write-Utf8 $targetControl 'foreign leaf'
    $foreignTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $foreignControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $foreignTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Force
    Assert-True ($foreignTargetControl.Code -ne 0 -and $foreignTargetControl.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'maintenance-resolver-foreign-target-control-plane-rejected'
    Assert-True ($foreignControlAuth.Code -ne 0 -and $foreignTargetAuth.Code -ne 0 -and $foreignControlAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN') -and $foreignTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema2-foreign-target-control-plane-denies-control-and-target'

    $installedLoader = Join-Path $installedFramework 'scripts\resolve-load-plan.ps1'
    $fullColdLoad = Invoke-Ps $installedLoader @('-Role','CONTROLLER','-Profile','CRITICAL','-Phase','RECOVER','-HostName','CODEX','-Topology','FRAMEWORK_MAINTENANCE_SIBLING')
    $renderedBootstrap = Get-Content -LiteralPath (Join-Path $controlPlane 'BOOTSTRAP.md') -Raw -Encoding utf8
    Assert-True ($fullColdLoad.Code -ne 0 -and $renderedBootstrap.Contains('state=CURRENT') -and -not $renderedBootstrap.Contains('AllowLegacyTargetControlPlane') -and $renderedBootstrap.Contains('显式读取 `<TARGET>/AGENTS.md`') -and $renderedBootstrap.Contains('resolve-framework-maintenance-target.ps1') -and $renderedBootstrap.Contains('resolve-framework-maintenance-process-requirements.ps1')) 'maintenance-bootstrap-root-owned-full-cold-route'

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
    Assert-True ($duplicateResult.Code -ne 0 -and $duplicateResult.Text.Contains('JSON_DUPLICATE_MEMBER|id')) 'maintenance-schema4-duplicate-field-rejected'

    $unicodeTopConfigRaw=[regex]::Replace($configRaw,'("routineExcludedPaths"\s*:\s*\[[^\]]*\])','$1, "\u0072outineExcludedPaths": []',1)
    Write-Utf8 $configPath $unicodeTopConfigRaw
    $unicodeTopConfigResult=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($unicodeTopConfigResult.Code-ne0-and$unicodeTopConfigResult.Text.Contains('JSON_DUPLICATE_MEMBER|routineExcludedPaths')) 'maintenance-schema4-unicode-top-level-duplicate-rejected'

    $unicodeNestedConfigRaw=[regex]::Replace($configRaw,'("locator"\s*:\s*"\.ai-workspace/process-policy\.json")','$1, "\u006cocator": ".ai-workspace/process-policy.json"',1)
    Write-Utf8 $configPath $unicodeNestedConfigRaw
    $unicodeNestedConfigResult=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($unicodeNestedConfigResult.Code-ne0-and$unicodeNestedConfigResult.Text.Contains('JSON_DUPLICATE_MEMBER|locator')) 'maintenance-schema4-unicode-nested-policy-duplicate-rejected'
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
    Assert-True ($missingPin.Code -ne 0 -and $missingPin.Text.Contains('TARGET_VERSION_FILE_MISSING|RECOVERY_CORE.md')) 'maintenance-resolver-pin-entry-missing-rejected'

    $controllerRaw = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $staleController = $controllerRaw | ConvertFrom-Json
    $staleController.projectId = 'wrong-project'
    Write-Utf8 $controllerPath ($staleController | ConvertTo-Json -Depth 10)
    $staleControllerResult = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Write-Utf8 $controllerPath $controllerRaw
    Assert-True ($staleControllerResult.Code -ne 0 -and $staleControllerResult.Text.Contains('CONTROLLER_VALUES')) 'maintenance-resolver-stale-controller-rejected'

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
    Assert-True ($junctionControlAuth.Code -ne 0 -and $junctionTargetAuth.Code -ne 0 -and $junctionControlAuth.Text.Contains('TARGET_CONTROL_PLANE_REPARSE') -and $junctionTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_REPARSE')) 'authorization-schema2-target-control-junction-denies-control-and-target'

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
    Assert-True ($missingAgents.Code -ne 0 -and $missingAgents.Text.Contains('TARGET_ROOT_FILE_MISSING|AGENTS.md')) 'maintenance-resolver-target-agents-required'

    $badSiblingConfig = $configRaw | ConvertFrom-Json
    $badSiblingConfig.frameworkTarget.siblingDirectory = '..\AI-Workspace'
    Write-Utf8 $configPath ($badSiblingConfig | ConvertTo-Json -Depth 20)
    $badSiblingIdentity = Get-Identity $configPath
    $badSibling = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$badSiblingIdentity)
    Write-Utf8 $configPath $configRaw
    Assert-True ($badSibling.Code -ne 0 -and $badSibling.Text.Contains('TARGET_SIBLING_COMPONENT')) 'maintenance-resolver-parent-traversal-rejected'
    Assert-True ((Get-Identity $configPath) -ceq $configIdentity) 'maintenance-fixture-config-restored'

    $versionChecker = Join-Path $installedFramework 'scripts\check-authorization.ps1'
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
    $directSchema2 = Invoke-Ps $versionChecker @('-PackagePath',$controlPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity,'-TaskPath','.ai-workspace/tasks/active/FIXTURE-001.md','-ExpectedTaskIdentity',(Get-Identity (Join-Path $control '.ai-workspace/tasks/active/FIXTURE-001.md'))) $control
    Assert-True ($directSchema2.Code-ne0-and$directSchema2.Text.Contains('ROOT_REPOSITORY_BINDING_REQUIRED')) 'authorization-schema2-requires-root-repository-adapter'

    $controlAuth = Invoke-Ps $checker @('-PackagePath',$controlPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    $targetAuth = Invoke-Ps $checker @('-PackagePath',$targetPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    if($controlAuth.Code-ne0-or$targetAuth.Code-ne0){Write-Output ('DIAG|authorization-root-adapter|control='+$controlAuth.Text+'|target='+$targetAuth.Text)}
    Assert-True ($controlAuth.Code -eq 0 -and $targetAuth.Code -eq 0) 'authorization-schema2-control-and-target-pass'
    $duplicateAuthPath=Join-Path $controlPlane 'duplicate-auth.json';$duplicateAuthRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $targetPackage;$duplicateAuthRaw=[regex]::Replace($duplicateAuthRaw,'"actions"\s*:\s*\[','"actions": ["SOURCE_WRITE"], "\u0061ctions": [',1);Write-Utf8 $duplicateAuthPath $duplicateAuthRaw
    $duplicateAuthRun=Invoke-Ps $checker @('-PackagePath',$duplicateAuthPath,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($duplicateAuthRun.Code-ne0-and$duplicateAuthRun.Text.Contains('PACKAGE_DUPLICATE_MEMBER|actions')) 'authorization-recursive-json-rejects-unicode-top-level-duplicate'

    $maintenanceProcessResolver=Join-Path $target 'scripts\resolve-framework-maintenance-process-requirements.ps1';$maintenanceProcessTask=Join-Path $control '.ai-workspace\tasks\active\FIXTURE-001.md';$maintenanceProcessInputPath=Join-Path $controlPlane 'maintenance-target-process.json'
    $maintenanceProcessIntent=[ordered]@{schemaVersion=1;objective='Modify one bounded Framework target object';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('implementation');pathHints=@($targetObject);capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'}
    $maintenanceProcessInput=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$control;frameworkRoot=$target;taskPath=$maintenanceProcessTask;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity=(Get-Identity $maintenanceProcessTask);observedActor='controller-fixture';capabilities=@();exactPaths=@($targetObject);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$targetPackage;expectedAuthorizationIdentity=(Get-Identity $targetPackage);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$maintenanceProcessIntent;evaluationOnly=$false}
    Write-Utf8 $maintenanceProcessInputPath ($maintenanceProcessInput|ConvertTo-Json -Depth 30);$maintenanceProcessRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceProcessInputPath,'-AsJson');$maintenanceProcessResult=if($maintenanceProcessRun.Code-eq0){$maintenanceProcessRun.Output[-1]|ConvertFrom-Json}else{$null};$maintenanceProcessValue=if($null-ne$maintenanceProcessResult){$maintenanceProcessResult.compactReceipt}else{$null}
    $expectedTargetGitTop=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($target))
    if($maintenanceProcessRun.Code-ne0-or[string]$maintenanceProcessValue.authorityContext.repositoryGitTop-cne$expectedTargetGitTop){Write-Output ('DIAG|process-maintenance-target|code='+$maintenanceProcessRun.Code+'|expected='+$expectedTargetGitTop+'|output='+$maintenanceProcessRun.Text)}
    Assert-True ($maintenanceProcessRun.Code-eq0-and[string]$maintenanceProcessValue.authorityContext.projectRoot-ceq$expectedTargetGitTop-and[string]$maintenanceProcessValue.authorityContext.repositoryGitTop-ceq$expectedTargetGitTop) 'process-maintenance-target-authority-context-uses-target-git-top'

    $batchWrapper = Join-Path $controlPlane 'invoke-batch-authorization.ps1'
    Write-Utf8 $batchWrapper @'
param([string]$Checker,[string]$Package,[string]$ObjectPath,[string]$ObjectIdentity,[string]$ConfigIdentity,[string]$TaskIdentity,[switch]$Duplicate)
$actions=if($Duplicate){@('SOURCE_WRITE','SOURCE_WRITE')}else{@('SOURCE_WRITE','TEST_RUN')}
& $Checker -PackagePath $Package -ObservedActor 'controller-fixture' -ObservedTaskId 'FIXTURE-001' -ObservedOwner 'controller-fixture' -ObservedAction $actions -ObservedPath @($ObjectPath) -ObservedIdentity @($ObjectPath+'='+$ObjectIdentity) -ControllerControlPath '.ai-workspace/controller.json' -ObservedRepositoryId 'ai-workspace-framework' -ProjectConfigPath '.ai-workspace/project.json' -ExpectedProjectConfigIdentity $ConfigIdentity -TaskPath '.ai-workspace/tasks/active/FIXTURE-001.md' -ExpectedTaskIdentity $TaskIdentity
exit $LASTEXITCODE
'@
    $batchArgs=@('-Checker',$checker,'-Package',$targetPackage,'-ObjectPath',$targetObject,'-ObjectIdentity',(Get-Identity (Join-Path $target $targetObject)),'-ConfigIdentity',$configIdentity,'-TaskIdentity',(Get-Identity (Join-Path $control '.ai-workspace/tasks/active/FIXTURE-001.md')))
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

    $controlTaskRelative='.ai-workspace/tasks/active/FIXTURE-001.md';$controlTaskPackage=Join-Path $controlPlane 'control-task-finalize-auth.json'
    New-AuthorizationPackage $controlTaskPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlTaskRelative (Get-Identity (Join-Path $control $controlTaskRelative))
    $controlTaskPath=Join-Path $control $controlTaskRelative;$controlTaskIntent=[ordered]@{schemaVersion=1;objective='Finalize one bounded control task record';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('task','control');pathHints=@($controlTaskRelative);capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'}
    $controlTaskDiscoverInput=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$control;frameworkRoot=$target;taskPath=$controlTaskPath;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity=(Get-Identity $controlTaskPath);observedActor='controller-fixture';capabilities=@();exactPaths=@($controlTaskRelative);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$controlTaskPackage;expectedAuthorizationIdentity=(Get-Identity $controlTaskPackage);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$controlTaskIntent;evaluationOnly=$false}
    $controlTaskInputPath=Join-Path $controlPlane 'control-task-process.json';Write-Utf8 $controlTaskInputPath ($controlTaskDiscoverInput|ConvertTo-Json -Depth 30)
    $controlTaskDiscoverRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson');$controlTaskDiscoverResult=$controlTaskDiscoverRun.Output[-1]|ConvertFrom-Json;$controlTaskReceipt=$controlTaskDiscoverResult.compactReceipt
    $controlTaskReceiptPath=Join-Path $controlPlane 'control-task-discover-receipt.json';Write-Utf8 $controlTaskReceiptPath ($controlTaskReceipt|ConvertTo-Json -Depth 40)
    $controlTaskPrep=@($controlTaskReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$controlTaskResults=@($controlTaskReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $controlTaskBoundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$controlTaskReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $controlTaskReceiptPath);objective=$controlTaskIntent.objective;actionKind='CONTROL_WRITE';resultKind='IMPLEMENTATION_RESULT';exactPaths=@($controlTaskRelative);authorizationIdentity=(Get-Identity $controlTaskPackage);preparationReceipts=@($controlTaskPrep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Utf8 $controlTaskInputPath ($controlTaskBoundary|ConvertTo-Json -Depth 30);$controlTaskAdmitRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    if($controlTaskDiscoverRun.Code-ne0-or$controlTaskAdmitRun.Code-ne0){throw ('ASSERT_FAIL|process-control-task-admit-binds-exact-preimage|discover='+$controlTaskDiscoverRun.Code+'|'+$controlTaskDiscoverRun.Text+'|admit='+$controlTaskAdmitRun.Code+'|'+$controlTaskAdmitRun.Text)}
    Assert-True ($controlTaskDiscoverRun.Code-eq0-and$controlTaskAdmitRun.Code-eq0) 'process-control-task-admit-binds-exact-preimage'
    $controlTaskPreText=Get-Content -Raw -Encoding utf8 -LiteralPath $controlTaskPath;$controlTaskPostText=$controlTaskPreText.TrimEnd("`n")+"`n`n- Completion: STRUCTURALLY_FINALIZED`n";Write-Utf8 $controlTaskPath $controlTaskPostText
    $controlTaskFinalize=$controlTaskBoundary|ConvertTo-Json -Depth 40|ConvertFrom-Json;$controlTaskFinalize.mode='FINALIZE_OUTPUT';$controlTaskFinalize.resultReceipts=@($controlTaskResults+@('OBJECT_POSTIMAGE|'+$controlTaskRelative+'|'+(Get-Identity $controlTaskPath)));Write-Utf8 $controlTaskInputPath ($controlTaskFinalize|ConvertTo-Json -Depth 40)
    $controlTaskFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    Assert-True ($controlTaskFinalizeRun.Code-eq0-and$controlTaskFinalizeRun.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) 'process-control-task-finalize-allows-narrow-preimage-to-postimage-transition'
    $wrongOwnerText=$controlTaskPostText-replace '(?m)^- Owner: controller-fixture$','- Owner: wrong-owner';Write-Utf8 $controlTaskPath $wrongOwnerText;$wrongOwnerFinalize=$controlTaskFinalize|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongOwnerFinalize.resultReceipts=@($controlTaskResults+@('OBJECT_POSTIMAGE|'+$controlTaskRelative+'|'+(Get-Identity $controlTaskPath)));Write-Utf8 $controlTaskInputPath ($wrongOwnerFinalize|ConvertTo-Json -Depth 40)
    $wrongOwnerFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    Assert-True ($wrongOwnerFinalizeRun.Code-ne0-and$wrongOwnerFinalizeRun.Text.Contains('CONTROL_TASK_POSTIMAGE_BINDING_DRIFT')) 'process-control-task-finalize-rejects-owner-or-task-id-drift'
    Write-Utf8 $controlTaskPath $controlTaskPostText
    $wrongPathReceipt=$controlTaskReceipt|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPathReceipt.exactPaths=@($controlObject);$wrongPathReceiptPath=Join-Path $controlPlane 'control-task-wrong-path-receipt.json';Write-Utf8 $wrongPathReceiptPath ($wrongPathReceipt|ConvertTo-Json -Depth 40);$wrongPathBoundary=$controlTaskFinalize|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPathBoundary.discoverReceiptPath=$wrongPathReceiptPath;$wrongPathBoundary.expectedDiscoverReceiptIdentity=Get-Identity $wrongPathReceiptPath;$wrongPathBoundary.exactPaths=@($controlObject);Write-Utf8 $controlTaskInputPath ($wrongPathBoundary|ConvertTo-Json -Depth 40)
    $wrongPathFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    Assert-True ($wrongPathFinalizeRun.Code-ne0-and$wrongPathFinalizeRun.Text.Contains('DISCOVER_SOURCE_DRIFT|taskIdentity')) 'process-control-task-finalize-rejects-non-task-exact-path-transition'
    $wrongPackageReceipt=$controlTaskReceipt|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPackageReceipt.sourceLocators.authorizationPackagePath=$targetPackage;$wrongPackageReceipt.authorityContext.authorizationIdentity=Get-Identity $targetPackage;$wrongPackageReceiptPath=Join-Path $controlPlane 'control-task-wrong-package-receipt.json';Write-Utf8 $wrongPackageReceiptPath ($wrongPackageReceipt|ConvertTo-Json -Depth 40);$wrongPackageBoundary=$controlTaskFinalize|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPackageBoundary.discoverReceiptPath=$wrongPackageReceiptPath;$wrongPackageBoundary.expectedDiscoverReceiptIdentity=Get-Identity $wrongPackageReceiptPath;$wrongPackageBoundary.authorizationIdentity=Get-Identity $targetPackage;Write-Utf8 $controlTaskInputPath ($wrongPackageBoundary|ConvertTo-Json -Depth 40)
    $wrongPackageFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    Assert-True ($wrongPackageFinalizeRun.Code-ne0-and$wrongPackageFinalizeRun.Text.Contains('CONTROL_TASK_POSTIMAGE_TRANSITION_NOT_AUTHORIZED')) 'process-control-task-finalize-rejects-non-control-package-transition'
    $controlCorrectionsPath=Join-Path $controlPlane 'corrections.json';$controlCorrectionsRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $controlCorrectionsPath;Write-Utf8 $controlCorrectionsPath ($controlCorrectionsRaw.TrimEnd("`n")+"`n`n");Write-Utf8 $controlTaskInputPath ($controlTaskFinalize|ConvertTo-Json -Depth 40)
    $controlTaskOtherSourceDrift=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson');[IO.File]::WriteAllText($controlCorrectionsPath,$controlCorrectionsRaw,[Text.UTF8Encoding]::new($false))
    Assert-True ($controlTaskOtherSourceDrift.Code-ne0-and$controlTaskOtherSourceDrift.Text.Contains('DISCOVER_SOURCE_DRIFT|correctionsIdentity')) 'process-control-task-finalize-rejects-all-other-source-drift'

    Commit-All $control 'control baseline'
    Commit-All $target 'target baseline'
    Write-Utf8 (Join-Path $control $controlObject) '# changed control task index'
    Write-Utf8 (Join-Path $target $targetObject) 'changed public target'
    Write-Utf8 (Join-Path $target 'private\secret.txt') 'changed private target'

    $safeGit = Join-Path $target 'scripts\invoke-framework-maintenance-safe-git.ps1'
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

    $checker = $versionChecker
    $safeGit = Join-Path $installedFramework 'scripts\invoke-protected-safe-git.ps1'
    $repoLocal = Join-Path $temp 'repo-local-fixture'
    New-GitRepo $repoLocal
    $repoLocalConfigPath = Join-Path $repoLocal '.ai-workspace\project.json'
    $repoLocalConfig = [ordered]@{schemaVersion=3;id='repo-local-fixture';displayName='Repo Local Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('private/secret.txt');frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false}}}
    Write-Utf8 $repoLocalConfigPath ($repoLocalConfig | ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $repoLocal 'src\public.txt') 'repo local public'
    Write-Utf8 (Join-Path $repoLocal 'private\secret.txt') 'repo local private'
    $repoLocalIdentity = Get-Identity $repoLocalConfigPath
    $repoLocalSchema1Package = Join-Path $repoLocal '.ai-workspace\schema1-auth.json'
    $repoLocalObject = 'src/public.txt'
    $repoLocalObjectIdentity = Get-Identity (Join-Path $repoLocal $repoLocalObject)
    New-AuthorizationPackage $repoLocalSchema1Package 1 '' $repoLocalIdentity @('SOURCE_WRITE') $repoLocalObject $repoLocalObjectIdentity -DomainOwner
    $repoLocalSchema1Auth = Invoke-Ps $checker @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity)) $repoLocal
    $repoLocalStatus = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    $repoLocalExcluded = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    Assert-True ($repoLocalStatus.Code -eq 0 -and $repoLocalStatus.Text.Contains('src/public.txt') -and $repoLocalStatus.Text.Contains('"repositoryId":"PROJECT"')) 'safe-git-repo-local-default-compatible'
    Assert-True ($repoLocalExcluded.Code -eq 0 -and -not ((@($repoLocalExcluded.Output)[-1] | ConvertFrom-Json).output -join "`n").Contains('private/secret.txt')) 'safe-git-repo-local-exclusion-compatible'
    Assert-True ($repoLocalSchema1Auth.Code -eq 0) 'authorization-schema1-repo-local-schema3-compatible'

    $repoLocal4=Join-Path $temp 'repo-local-schema4-starter-fixture';New-GitRepo $repoLocal4
    $repoLocal4ConfigPath=Join-Path $repoLocal4 '.ai-workspace\project.json'
    $repoLocal4Raw=$projectStarterText.Replace('{{PROJECT_ID_JSON}}','"repo-local-schema4-fixture"').Replace('{{DISPLAY_NAME_JSON}}','"Repo Local Schema4 Fixture"').Replace('{{FRAMEWORK_VERSION_JSON}}','"1.16.0"')
    $repoLocal4Config=$repoLocal4Raw|ConvertFrom-Json;$repoLocal4Config.routineExcludedPaths=@('private/secret.txt');$repoLocal4Raw=$repoLocal4Config|ConvertTo-Json -Depth 20
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4Raw;Write-Utf8 (Join-Path $repoLocal4 'src\public.txt') 'schema4 public baseline';Write-Utf8 (Join-Path $repoLocal4 'private\secret.txt') 'schema4 private baseline';Commit-All $repoLocal4 'schema4 repo-local baseline'
    Write-Utf8 (Join-Path $repoLocal4 'src\public.txt') 'schema4 public changed';Write-Utf8 (Join-Path $repoLocal4 'private\secret.txt') 'schema4 private changed'
    $repoLocal4Identity=Get-Identity $repoLocal4ConfigPath
    $repoLocal4Status=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4Diff=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','DIFF','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4Excluded=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4Override=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','private/secret.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity,'-IncludeRoutineExcluded')
    & git -C $repoLocal4 add -- 'src/public.txt';if($LASTEXITCODE-ne0){throw 'SCHEMA4_REPO_LOCAL_STAGE_FAILED'}
    $repoLocal4Index=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','INDEX','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4ExcludedOutput=((@($repoLocal4Excluded.Output)[-1]|ConvertFrom-Json).output-join"`n");$repoLocal4OverrideOutput=((@($repoLocal4Override.Output)[-1]|ConvertFrom-Json).output-join"`n")
    Assert-True ($repoLocal4Status.Code-eq0-and$repoLocal4Status.Text.Contains('src/public.txt')-and$repoLocal4Status.Text.Contains('"repositoryId":"PROJECT"')) 'safe-git-repo-local-schema4-starter-status'
    Assert-True ($repoLocal4Diff.Code-eq0-and$repoLocal4Diff.Text.Contains('schema4 public changed')) 'safe-git-repo-local-schema4-starter-diff'
    Assert-True ($repoLocal4Index.Code-eq0-and$repoLocal4Index.Text.Contains('src/public.txt')) 'safe-git-repo-local-schema4-starter-index'
    Assert-True ($repoLocal4Excluded.Code-eq0-and-not$repoLocal4ExcludedOutput.Contains('private/secret.txt')) 'safe-git-repo-local-schema4-starter-exclusion'
    Assert-True ($repoLocal4Override.Code-eq0-and$repoLocal4OverrideOutput.Contains('private/secret.txt')) 'safe-git-repo-local-schema4-starter-exclusion-override'
    $repoLocal4WrongRepository=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity,'-RepositoryId','CONTROL')
    Assert-True ($repoLocal4WrongRepository.Code-ne0-and$repoLocal4WrongRepository.Text.Contains('REPOSITORY_ID_PROJECT_ONLY')-and$repoLocal4WrongRepository.Text.Contains('"launched":false')) 'safe-git-repo-local-schema4-rejects-non-project-repository-id'
    $repoLocal4Invalid=$repoLocal4Raw|ConvertFrom-Json;$repoLocal4Invalid.processPolicy.locator='.ai-workspace/other-policy.json';Write-Utf8 $repoLocal4ConfigPath ($repoLocal4Invalid|ConvertTo-Json -Depth 20)
    $repoLocal4InvalidRun=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath))
    Assert-True ($repoLocal4InvalidRun.Code-ne0-and$repoLocal4InvalidRun.Text.Contains('PROJECT_CONFIG_PROCESS_POLICY')-and$repoLocal4InvalidRun.Text.Contains('"launched":false')) 'safe-git-repo-local-schema4-invalid-policy-fails-before-git-command'
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4Raw

    $repoLocal4UnicodeTop=[regex]::Replace($repoLocal4Raw,'("routineExcludedPaths"\s*:\s*\[[^\]]*\])','$1, "\u0072outineExcludedPaths": []',1)
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4UnicodeTop
    $gitShimRoot=Join-Path $temp 'safe-git-zero-invocation-shim';$gitShimLog=Join-Path $gitShimRoot 'git-invocations.log'
    Write-Utf8 (Join-Path $gitShimRoot 'git.cmd') "@echo off`necho invoked>>`"%AIW_GIT_SHIM_LOG%`"`nexit /b 97"
    $gitShimEnvironment=@{PATH=($gitShimRoot+';'+[Environment]::GetEnvironmentVariable('PATH','Process'));AIW_GIT_SHIM_LOG=$gitShimLog}
    $repoLocal4UnicodeTopRun=Invoke-PsWithProcessEnvironment $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath)) $repoLocal4 $gitShimEnvironment
    Assert-True ($repoLocal4UnicodeTopRun.Code-ne0-and$repoLocal4UnicodeTopRun.Text.Contains('PROJECT_CONFIG_JSON_DUPLICATE_FIELD|routineExcludedPaths')-and$repoLocal4UnicodeTopRun.Text.Contains('"launched":false')-and-not(Test-Path -LiteralPath $gitShimLog)) 'safe-git-schema4-unicode-top-level-exclusion-duplicate-zero-git-invocation'

    Write-Utf8 $repoLocal4ConfigPath '{"schemaVersion":4,}'
    $repoLocal4MalformedRun=Invoke-PsWithProcessEnvironment $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath)) $repoLocal4 $gitShimEnvironment
    Assert-True ($repoLocal4MalformedRun.Code-ne0-and$repoLocal4MalformedRun.Text.Contains('PROJECT_CONFIG_JSON_STRING')-and$repoLocal4MalformedRun.Text.Contains('"launched":false')-and-not(Test-Path -LiteralPath $gitShimLog)) 'safe-git-schema4-malformed-config-zero-git-invocation'

    $repoLocal4UnicodePolicy=[regex]::Replace($repoLocal4Raw,'("locator"\s*:\s*"\.ai-workspace/process-policy\.json")','$1, "\u006cocator": ".ai-workspace/process-policy.json"',1)
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4UnicodePolicy
    $repoLocal4UnicodePolicyRun=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath))
    Assert-True ($repoLocal4UnicodePolicyRun.Code-ne0-and$repoLocal4UnicodePolicyRun.Text.Contains('PROJECT_CONFIG_JSON_DUPLICATE_FIELD|locator')-and$repoLocal4UnicodePolicyRun.Text.Contains('"launched":false')) 'safe-git-schema4-unicode-nested-policy-duplicate-not-launched'
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4Raw

    $domainExternalTaskPath=Join-Path $repoLocal '.ai-workspace\tasks\active\FIXTURE-EXTERNAL-001.md'
    Write-Utf8 $domainExternalTaskPath "# FIXTURE-EXTERNAL-001 - external authorization fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=DOMAIN_OWNER; phase=EXTERNAL`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[src/public.txt]; actual_paths=[]`n"
    $zeroEscalation=[ordered]@{paymentOrSubscription=$false;commercialLicensing=$false;accountOrCredentialChange=$false;publicPublication=$false;installation=$false;protectedOrSecretUpload=$false;crossDomain=$false;formalAssetActivation=$false;projectPhaseChange=$false;gitOrPush=$false;sharedQuotaOrResource=$false;unknownScope=$false}
    $externalBinding=[ordered]@{schemaVersion=1;route='DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL';provider='fixture-provider';orderedOperations=@(
        [ordered]@{operationId='OP-1';operationKind='PROVIDER_PUBLIC_METADATA_READ';declaredInputClass='ZERO_PROJECT_DATA';payloads=@()},
        [ordered]@{operationId='OP-2';operationKind='bounded-transform';declaredInputClass='EXACT_PAYLOADS';payloads=@([ordered]@{payloadKind='normalized-text';normalizedIdentity=$repoLocalObjectIdentity;canonicalizationVersion='UTF8_LF_V1'})}
    );outputUse='project-local reviewed candidate only';totalQuantity=2;perOperationRetryCeiling=1;totalRetryCeiling=2;costClass='FREE';costCeiling=0;stopConditions=@('stop on provider error','stop on ambiguous consumption');batchExecutionMode='ONE_LOGICAL_ATOMIC_EXECUTION';reissuable=$false;ambiguousConsumptionPolicy='BLOCK';escalationFlags=$zeroEscalation}
    $domainExternalPackage=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';taskId='FIXTURE-EXTERNAL-001';taskIdentity=(Get-Identity $domainExternalTaskPath);profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='DOMAIN_OWNER';grantee='owner-fixture';bundle='EXTERNAL_LOCAL';decisionClass='EXTERNAL_ACTION';userConfirmation='USER_FIXTURE_EXTERNAL_APPROVED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;actions=@('EXTERNAL');exactPaths=@($repoLocalObject);objectIdentities=@([ordered]@{path=$repoLocalObject;identity=$repoLocalObjectIdentity});projectConfigIdentity=$repoLocalIdentity;invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');externalBinding=$externalBinding}
    $domainExternalPackagePath=Join-Path $repoLocal '.ai-workspace\domain-external-auth.json';Write-Utf8 $domainExternalPackagePath ($domainExternalPackage|ConvertTo-Json -Depth 40)
    $domainExternalArgs=@('-PackagePath',$domainExternalPackagePath,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-EXTERNAL-001','-ObservedOwner','owner-fixture','-ObservedAction','EXTERNAL','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $domainExternalPass=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($domainExternalPass.Code-eq0) 'authorization-domain-owner-exact-free-atomic-external-batch-pass'
    $duplicateNestedExternalRaw=$domainExternalPackage|ConvertTo-Json -Depth 40;$duplicateNestedExternalRaw=[regex]::Replace($duplicateNestedExternalRaw,'"publicPublication"\s*:\s*false','"publicPublication": false, "\u0070ublicPublication": false',1);Write-Utf8 $domainExternalPackagePath $duplicateNestedExternalRaw
    $duplicateNestedExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($duplicateNestedExternalRun.Code-ne0-and$duplicateNestedExternalRun.Text.Contains('PACKAGE_DUPLICATE_MEMBER|publicPublication')) 'authorization-recursive-json-rejects-unicode-nested-external-duplicate'
    $paidExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$paidExternal.externalBinding.costClass='PAID';$paidExternal.externalBinding.costCeiling=1;Write-Utf8 $domainExternalPackagePath ($paidExternal|ConvertTo-Json -Depth 40)
    $paidExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($paidExternalRun.Code-ne0-and$paidExternalRun.Text.Contains('DOMAIN_EXTERNAL_BINDING_VALUES')) 'authorization-domain-owner-paid-external-rejected'
    $escalatedExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$escalatedExternal.externalBinding.escalationFlags.publicPublication=$true;Write-Utf8 $domainExternalPackagePath ($escalatedExternal|ConvertTo-Json -Depth 40)
    $escalatedExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($escalatedExternalRun.Code-ne0-and$escalatedExternalRun.Text.Contains('DOMAIN_EXTERNAL_ESCALATION_REQUIRED|publicPublication')) 'authorization-domain-owner-controller-bound-external-rejected'
    $commercialExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$commercialExternal.externalBinding.escalationFlags.commercialLicensing=$true;Write-Utf8 $domainExternalPackagePath ($commercialExternal|ConvertTo-Json -Depth 40)
    $commercialExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($commercialExternalRun.Code-ne0-and$commercialExternalRun.Text.Contains('DOMAIN_EXTERNAL_ESCALATION_REQUIRED|commercialLicensing')) 'authorization-domain-owner-commercial-licensing-escalates'
    $phaseExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$phaseExternal.externalBinding.escalationFlags.projectPhaseChange=$true;Write-Utf8 $domainExternalPackagePath ($phaseExternal|ConvertTo-Json -Depth 40)
    $phaseExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($phaseExternalRun.Code-ne0-and$phaseExternalRun.Text.Contains('DOMAIN_EXTERNAL_ESCALATION_REQUIRED|projectPhaseChange')) 'authorization-domain-owner-project-phase-change-escalates'
    $zeroDataLeak=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$zeroDataLeak.externalBinding.orderedOperations[0].payloads=@([ordered]@{payloadKind='unexpected';normalizedIdentity=$repoLocalObjectIdentity;canonicalizationVersion='UTF8_LF_V1'});Write-Utf8 $domainExternalPackagePath ($zeroDataLeak|ConvertTo-Json -Depth 40)
    $zeroDataLeakRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($zeroDataLeakRun.Code-ne0-and$zeroDataLeakRun.Text.Contains('DOMAIN_EXTERNAL_ZERO_DATA_HAS_PAYLOAD')) 'authorization-domain-owner-zero-project-data-declaration-enforced'
    $unknownZeroData=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$unknownZeroData.externalBinding.orderedOperations[0].operationKind='ARBITRARY_ZERO_DATA_OPERATION';Write-Utf8 $domainExternalPackagePath ($unknownZeroData|ConvertTo-Json -Depth 40)
    $unknownZeroDataRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($unknownZeroDataRun.Code-ne0-and$unknownZeroDataRun.Text.Contains('DOMAIN_EXTERNAL_ZERO_DATA_OPERATION_NOT_CLOSED')) 'authorization-domain-owner-zero-data-operation-closed-set-enforced'
    $reissuableExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$reissuableExternal.externalBinding.reissuable=$true;$reissuableExternal.externalBinding.ambiguousConsumptionPolicy='RETRY';Write-Utf8 $domainExternalPackagePath ($reissuableExternal|ConvertTo-Json -Depth 40)
    $reissuableExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($reissuableExternalRun.Code-ne0-and$reissuableExternalRun.Text.Contains('DOMAIN_EXTERNAL_BINDING_VALUES')) 'authorization-domain-owner-reissue-or-ambiguous-retry-rejected'
    $mixedExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$mixedExternal.actions=@('EXTERNAL','SOURCE_WRITE');Write-Utf8 $domainExternalPackagePath ($mixedExternal|ConvertTo-Json -Depth 40)
    $mixedExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($mixedExternalRun.Code-ne0-and$mixedExternalRun.Text.Contains('DOMAIN_EXTERNAL_ACTION_MUST_BE_PURE')) 'authorization-domain-owner-external-batch-cannot-split-actions'
    Write-Utf8 $domainExternalTaskPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $domainExternalTaskPath).Replace('phase=EXTERNAL','phase=IMPLEMENT'))
    $routeDriftExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$routeDriftExternal.taskIdentity=Get-Identity $domainExternalTaskPath;Write-Utf8 $domainExternalPackagePath ($routeDriftExternal|ConvertTo-Json -Depth 40)
    $routeDriftExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($routeDriftExternalRun.Code-ne0-and$routeDriftExternalRun.Text.Contains('DOMAIN_EXTERNAL_TASK_ROUTE')) 'authorization-domain-owner-external-requires-domain-owner-external-route'
    Write-Utf8 $domainExternalPackagePath ($domainExternalPackage|ConvertTo-Json -Depth 40)

    $criticalReviewPackagePath = Join-Path $repoLocal '.ai-workspace\critical-review-auth.json'
    $criticalReviewTaskPath=Join-Path $repoLocal '.ai-workspace\tasks\active\FIXTURE-REVIEW-001.md'
    Write-Utf8 $criticalReviewTaskPath "# FIXTURE-REVIEW-001 - review authorization fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=cross-domain-writer; role=EXECUTOR; phase=VERIFY`n- Range summary: profile=CRITICAL; lifecycle=REVIEW; current_exact=src/public.txt; expected_paths=[src/public.txt]; actual_paths=[src/public.txt]`n- Proportionality: existing=sufficient; classification=execution_deviation; minimum_sufficient_fix=independent review; added_machinery=NONE; escalation_trigger=NONE`n- Stable candidate: src/public.txt`n"
    $criticalReviewPackage = [ordered]@{
        schemaVersion=1;frameworkVersion='1.16.0';taskId='FIXTURE-REVIEW-001';taskIdentity=(Get-Identity $criticalReviewTaskPath);profile='CRITICAL';lifecycle='ACTIVE'
        owner='owner-fixture';issuer='owner-fixture';issuerRole='DOMAIN_OWNER';grantee='reviewer-fixture';bundle='REVIEW_LOCAL'
        decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='INDEPENDENT';delegatedGitCloser=$false
        actions=@('REVIEW_EXECUTE');exactPaths=@($repoLocalObject);objectIdentities=@([ordered]@{path=$repoLocalObject;identity=$repoLocalObjectIdentity})
        projectConfigIdentity=$repoLocalIdentity
        invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','CONTRIBUTOR_SET_CHANGE','PROJECT_CONFIG_DRIFT')
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

    $repoLocalSchema1Args = @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $gitOverrideValues = [ordered]@{GIT_DIR=(Join-Path $repoLocal '.git');GIT_WORK_TREE=$repoLocal;GIT_COMMON_DIR=(Join-Path $repoLocal '.git')}
    foreach ($gitEnvironmentName in $gitOverrideValues.Keys) {
        $schema1EnvironmentOverride = Invoke-PsWithProcessEnvironment $checker @('-PackagePath',$maintenanceSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+$targetObjectIdentity),'-TaskPath','.ai-workspace/tasks/active/FIXTURE-OWNER-001.md','-ExpectedTaskIdentity',(Get-Identity (Join-Path $control '.ai-workspace/tasks/active/FIXTURE-OWNER-001.md'))) $control @{ $gitEnvironmentName=$gitOverrideValues[$gitEnvironmentName] }
        Assert-True ($schema1EnvironmentOverride.Code -ne 0 -and $schema1EnvironmentOverride.Text.Contains('GIT_ENVIRONMENT_OVERRIDE_'+$gitEnvironmentName)) ('authorization-schema1-rejects-process-'+$gitEnvironmentName.ToLowerInvariant())
    }

    $repoLocalConfigRaw = Get-Content -LiteralPath $repoLocalConfigPath -Raw -Encoding utf8
    $driftedSchema1Config=$repoLocalConfigRaw|ConvertFrom-Json
    $driftedSchema1Config.routineExcludedPaths=@('private/secret.txt','private/additional.txt')
    Write-Utf8 $repoLocalConfigPath ($driftedSchema1Config|ConvertTo-Json -Depth 20)
    $repoLocalSchema1ConfigDrift=Invoke-Ps $checker $repoLocalSchema1Args $repoLocal
    Write-Utf8 $repoLocalConfigPath $repoLocalConfigRaw
    Assert-True ($repoLocalSchema1ConfigDrift.Code-ne0-and$repoLocalSchema1ConfigDrift.Text.Contains('PROJECT_CONFIG_DRIFT')) 'authorization-schema1-binds-project-config-identity'
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
        Set-PackageProjectConfigIdentity $repoLocalSchema1Package (Get-Identity $repoLocalConfigPath)
        $invalidSchema1 = Invoke-Ps $checker $repoLocalSchema1Args $repoLocal
        if ($invalidSchema1.Code -eq 0 -or -not $invalidSchema1.Text.Contains([string]$case.Reason)) { Write-Output ('DIAG|schema1-invalid-'+[string]$case.Name+'|'+$invalidSchema1.Code+'|'+$invalidSchema1.Text) }
        Assert-True ($invalidSchema1.Code -ne 0 -and $invalidSchema1.Text.Contains([string]$case.Reason)) ('authorization-schema1-rejects-'+[string]$case.Name)
    }
    Write-Utf8 $repoLocalConfigPath $repoLocalConfigRaw
    Set-PackageProjectConfigIdentity $repoLocalSchema1Package $repoLocalIdentity

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
    Copy-Item -LiteralPath $candidateRoot -Destination (Join-Path $correctionFrameworkRoot 'framework\versions\1.16.0') -Recurse
    $pilotVersionRoot=Join-Path $correctionFrameworkRoot 'framework\versions\1.16.0';$pilotManifestPath=Join-Path $pilotVersionRoot 'RELEASE_MANIFEST.json';$pilotFacts=Get-ReleasePayloadFacts $pilotVersionRoot;$pilotManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $pilotManifestPath|ConvertFrom-Json
    $pilotManifest.lifecycle='CANDIDATE';$pilotManifest.fileCount=$pilotFacts.FileCount;$pilotManifest.totalBytes=$pilotFacts.TotalBytes;$pilotManifest.canonical=$pilotFacts.Canonical;$pilotManifest.sourceReview='APPROVED';$pilotManifest.completeSuite.status='PASS';$pilotManifest.completeSuite.passed=1;$pilotManifest.completeSuite.total=1;$pilotManifest.completeSuite.payloadCanonical=$pilotFacts.Canonical;Write-Utf8 $pilotManifestPath ($pilotManifest|ConvertTo-Json -Depth 20)
    $pilotProject=Join-Path $temp 'local-candidate-recovery-fixture';New-GitRepo $pilotProject;New-Item -ItemType Directory -Path (Join-Path $pilotProject '.ai-workspace\tasks\active') -Force|Out-Null
    $pilotConfig=[ordered]@{schemaVersion=4;id='local-candidate-recovery-fixture';displayName='Local Candidate Recovery Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}};$pilotConfigPath=Join-Path $pilotProject '.ai-workspace\project.json';Write-Utf8 $pilotConfigPath ($pilotConfig|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $pilotProject '.ai-workspace\controller.json') (([ordered]@{schemaVersion=1;projectId='local-candidate-recovery-fixture';controllerId='pilot-controller';controllerEpoch=1;state='CURRENT'})|ConvertTo-Json -Depth 10)
    Write-Utf8 (Join-Path $pilotProject '.ai-workspace\corrections.json') (([ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='local-candidate-recovery-fixture';corrections=@()})|ConvertTo-Json -Depth 10)
    Write-Utf8 (Join-Path $pilotProject '.ai-workspace\process-policy.json') (([ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='local-candidate-recovery-fixture';selectedRulePackBytes=32768;rules=@()})|ConvertTo-Json -Depth 10)
    Write-Utf8 (Join-Path $pilotProject '.ai-workspace\BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n此 legacy region 当前没有 permanent project process rule。structured rules 位于 `.ai-workspace/process-policy.json`。`n<!-- PROJECT-CUSTOM:END -->`n"
    $pilotTaskPath=Join-Path $pilotProject '.ai-workspace\tasks\active\PILOT-RECOVERY-001.md';Write-Utf8 $pilotTaskPath "# PILOT-RECOVERY-001 - candidate recovery fixture`n`n- Task schema: 1.16.0`n- Owner: pilot-controller`n- Work route: actor=pilot-controller; role=CONTROLLER; phase=RECOVER`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $pilotResolver=Join-Path $pilotVersionRoot 'scripts\resolve-process-requirements.ps1';$pilotInputPath=Join-Path $temp 'local-candidate-recovery-discover.json';$pilotInput=[ordered]@{schemaVersion=1;mode='DISCOVER';projectRoot=$pilotProject;frameworkRoot=$correctionFrameworkRoot;taskPath=$pilotTaskPath;expectedProjectConfigIdentity=(Get-Identity $pilotConfigPath);expectedCorrectionsIdentity=(Get-Identity (Join-Path $pilotProject '.ai-workspace\corrections.json'));expectedTaskIdentity=(Get-Identity $pilotTaskPath);observedActor='pilot-controller';capabilities=@();objective='Recover the already admitted local candidate pilot';actionKind='NONE';resultKind='PLAN';exactPaths=@();hostEnforcementGrade='FRAMEWORK_GATED';evaluationOnly=$false};Write-Utf8 $pilotInputPath ($pilotInput|ConvertTo-Json -Depth 20)
    $pilotMissingState=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotMissingState.Code-ne0-and$pilotMissingState.Text.Contains('LOCAL_CANDIDATE_PILOT_STATE_MISSING')) 'local-candidate-recovery-rejects-unproven-pilot-mode'
    $pilotStateRoot=Join-Path $pilotProject '.ai-workspace\upgrade-recovery\1.16.0';New-Item -ItemType Directory -Path $pilotStateRoot -Force|Out-Null;$pilotTaskUpgradeIdentity=Get-Identity $pilotTaskPath;$pilotManifestIdentity=Get-Identity $pilotManifestPath
    $pilotState=[ordered]@{schemaVersion=2;projectId='local-candidate-recovery-fixture';fromVersion='1.15.1';toVersion='1.16.0';targetReleaseCanonical=$pilotFacts.Canonical;targetReleaseManifestIdentity=$pilotManifestIdentity;actor='pilot-controller';taskId='PILOT-RECOVERY-001';taskOwner='pilot-controller';taskRelative='.ai-workspace/tasks/active/PILOT-RECOVERY-001.md';authorizationIdentity=('1|'+('A'*64));objects=@([ordered]@{relative='.ai-workspace/project.json';oldIdentity='MISSING';newIdentity=(Get-Identity $pilotConfigPath)},[ordered]@{relative='.ai-workspace/tasks/active/PILOT-RECOVERY-001.md';oldIdentity='MISSING';newIdentity=$pilotTaskUpgradeIdentity})};$pilotStatePath=Join-Path $pilotStateRoot 'state.json';Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    Write-Utf8 $pilotTaskPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $pilotTaskPath)+"- Pilot progress: task changed after the one-time upgrade transaction.`n");$pilotInput.expectedTaskIdentity=Get-Identity $pilotTaskPath;Write-Utf8 $pilotInputPath ($pilotInput|ConvertTo-Json -Depth 20)
    $pilotRecovery=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');if($pilotRecovery.Code-ne0){throw ('ASSERT_FAIL|local-candidate-recovery-reuses-admission-without-task-postimage-lock|'+$pilotRecovery.Code+'|'+$pilotRecovery.Text)};$pilotRecoveryResult=$pilotRecovery.Output[-1]|ConvertFrom-Json;$pilotReceipt=$pilotRecoveryResult.compactReceipt
    Assert-True ($pilotRecovery.Code-eq0-and[string]$pilotReceipt.status-ceq'PASS'-and[string]$pilotReceipt.sourceBindings.candidatePilotStateIdentity-ceq(Get-Identity $pilotStatePath)-and@($pilotReceipt.evidenceCeilings)-contains'LOCAL_CANDIDATE_PILOT') 'local-candidate-recovery-reuses-admission-without-task-postimage-lock'
    $pilotState.schemaVersion=3;$pilotState['projectionMode']='LOCAL_CANDIDATE_MANAGED';$pilotState['projectionObjects']=@([ordered]@{relative='.ai-workspace/project.json';identity=(Get-Identity $pilotConfigPath)},[ordered]@{relative='.ai-workspace/process-policy.json';identity=(Get-Identity (Join-Path $pilotProject '.ai-workspace\process-policy.json'))},[ordered]@{relative='.ai-workspace/tasks/active/PILOT-RECOVERY-001.md';identity=$pilotTaskUpgradeIdentity});Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    $pilotSchema3Recovery=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');if($pilotSchema3Recovery.Code-ne0){throw ('ASSERT_FAIL|local-candidate-schema3-managed-projection-recovery|'+$pilotSchema3Recovery.Code+'|'+$pilotSchema3Recovery.Text)};$pilotSchema3Result=$pilotSchema3Recovery.Output[-1]|ConvertFrom-Json;$pilotReceipt=$pilotSchema3Result.compactReceipt
    Assert-True ($pilotSchema3Recovery.Code-eq0-and[string]$pilotReceipt.sourceBindings.candidatePilotStateIdentity-ceq(Get-Identity $pilotStatePath)) 'local-candidate-schema3-managed-projection-recovery-allows-current-task-progress'
    $pilotPolicyPath=Join-Path $pilotProject '.ai-workspace\process-policy.json';$pilotPolicyBytes=[IO.File]::ReadAllBytes($pilotPolicyPath);Write-Utf8 $pilotPolicyPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $pilotPolicyPath)+"`n")
    $pilotProjectionDrift=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');[IO.File]::WriteAllBytes($pilotPolicyPath,$pilotPolicyBytes)
    Assert-True ($pilotProjectionDrift.Code-ne0-and$pilotProjectionDrift.Text.Contains('LOCAL_CANDIDATE_PILOT_PROJECTION_DRIFT|.ai-workspace/process-policy.json')) 'local-candidate-schema3-rejects-managed-projection-drift'
    $pilotProjectionObjects=@($pilotState.projectionObjects);$pilotState.projectionObjects=@($pilotProjectionObjects|Where-Object{[string]$_.relative-cne'.ai-workspace/project.json'});Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    $pilotProjectionMissing=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');$pilotState.projectionObjects=$pilotProjectionObjects;Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    Assert-True ($pilotProjectionMissing.Code-ne0-and$pilotProjectionMissing.Text.Contains('LOCAL_CANDIDATE_PILOT_PROJECTION_OBJECT_MISSING|.ai-workspace/project.json')) 'local-candidate-schema3-requires-original-object-projection-coverage'
    $pilotReceiptPath=Join-Path $temp 'local-candidate-recovery-receipt.json';Write-Utf8 $pilotReceiptPath ($pilotReceipt|ConvertTo-Json -Depth 30);$pilotState.authorizationIdentity='1|'+('B'*64);Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    $pilotBoundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$pilotReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $pilotReceiptPath);objective=$pilotInput.objective;actionKind='NONE';resultKind='PLAN';exactPaths=@();authorizationIdentity='NOT_REQUIRED';preparationReceipts=@($pilotReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'};$pilotBoundaryPath=Join-Path $temp 'local-candidate-recovery-admit.json';Write-Utf8 $pilotBoundaryPath ($pilotBoundary|ConvertTo-Json -Depth 20)
    $pilotStateDrift=Invoke-Ps $pilotResolver @('-InputPath',$pilotBoundaryPath,'-AsJson')
    Assert-True ($pilotStateDrift.Code-ne0-and$pilotStateDrift.Text.Contains('DISCOVER_SOURCE_DRIFT|candidatePilotStateIdentity')) 'local-candidate-recovery-state-is-bound-across-action-boundary'
    $pilotState.authorizationIdentity='1|'+('A'*64);Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20);$pilotCorePath=Join-Path $pilotVersionRoot 'RECOVERY_CORE.md';$pilotCoreOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $pilotCorePath;Write-Utf8 $pilotCorePath ($pilotCoreOriginal+"`n")
    $pilotPayloadDrift=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotPayloadDrift.Code-ne0-and$pilotPayloadDrift.Text.Contains('FRAMEWORK_LOCAL_CANDIDATE_MANIFEST_DRIFT')) 'local-candidate-recovery-rejects-candidate-payload-drift'
    [IO.File]::WriteAllText($pilotCorePath,$pilotCoreOriginal,[Text.UTF8Encoding]::new($false))
    $null=Seal-ReleaseFixture (Join-Path $correctionFrameworkRoot 'framework\versions\1.16.0') 'CORRECTION_TEST_FIXTURE'
    $correctionRoot=Join-Path $temp 'correction-fixture'
    New-GitRepo $correctionRoot
    New-Item -ItemType Directory -Path (Join-Path $correctionRoot '.ai-workspace') -Force|Out-Null
    $correctionConfig=[ordered]@{schemaVersion=4;id='correction-fixture';displayName='Correction Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}
    $correctionConfigPath=Join-Path $correctionRoot '.ai-workspace\project.json';Write-Utf8 $correctionConfigPath ($correctionConfig|ConvertTo-Json -Depth 20)
    $correctionControllerPath=Join-Path $correctionRoot '.ai-workspace\controller.json';Write-Utf8 $correctionControllerPath (([ordered]@{schemaVersion=1;projectId='correction-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})|ConvertTo-Json -Depth 10)
    $policyPath=Join-Path $correctionRoot '.ai-workspace\process-policy.json';$defaultPolicy=[ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='correction-fixture';selectedRulePackBytes=32768;rules=@()};$routineFixturePolicy=$defaultPolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$routineFixturePolicy.selectedRulePackBytes=98304;Write-Utf8 $policyPath ($routineFixturePolicy|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $correctionRoot '.ai-workspace\BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nProject-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.`n<!-- PROJECT-CUSTOM:END -->`n"
    $correctionRecords=[ordered]@{schemaVersion=1;contractVersion='1.10.0';projectId='correction-fixture';corrections=@(
        [ordered]@{correctionId='OWNER_FIRST_DIRECT_DOMAIN_ROUTE';introducedAgainstFramework='<=1.8.0';requirementReason='Observed unnecessary Controller relay';effectiveRule='Domain owner routes directly';applicability='Unchanged domain task';decisionLocator='task:owner-first'},
        [ordered]@{correctionId='PROJECT_CORRECTION_LIFECYCLE';introducedAgainstFramework='1.9.0';requirementReason='No deterministic cross-version retention';effectiveRule='Retain and evaluate project correction records';applicability='Framework pin adoption and recovery';decisionLocator='task:correction-lifecycle'}
    )}
    $correctionPath=Join-Path $correctionRoot '.ai-workspace\corrections.json';Write-Utf8 $correctionPath ($correctionRecords|ConvertTo-Json -Depth 20)
    $sealedCoveragePath=Join-Path $correctionFrameworkRoot 'framework\versions\1.16.0\CORRECTION_COVERAGE.json';$sealedCoverageOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $sealedCoveragePath
    $sealedCatalogPath=Join-Path $correctionFrameworkRoot 'framework\versions\1.16.0\PROCESS_REQUIREMENTS.json'
    $catalogFixture=Get-Content -Raw -Encoding utf8 -LiteralPath $sealedCatalogPath|ConvertFrom-Json
    $ownerNative=@($catalogFixture.requirements|Where-Object{[string]$_.requirementId-ceq'PR_TASK_SCOPE_AND_FORBIDDEN'})[0]
    $ownerAlias='correction:correction-fixture:OWNER_FIRST_DIRECT_DOMAIN_ROUTE'
    $ownerNative.legacyAliases=@($ownerAlias)
    Write-Utf8 $sealedCatalogPath ($catalogFixture|ConvertTo-Json -Depth 30)
    Import-Module (Join-Path $candidateRoot 'scripts\ProcessRequirementComposition.psm1') -Force
    $ownerRecord=$correctionRecords.corrections[0]|ConvertTo-Json -Depth 10|ConvertFrom-Json
    $ownerSourceIdentity=Get-AiwCanonicalCorrectionRecordIdentityV1 $ownerRecord
    $coverageFixture=$sealedCoverageOriginal|ConvertFrom-Json
    $entry113=@($coverageFixture.versions|Where-Object{[string]$_.version-ceq'1.16.0'})[0]
    $entry113.incorporationMappings=@([ordered]@{correctionId='OWNER_FIRST_DIRECT_DOMAIN_ROUTE';legacyRequirementId=$ownerAlias;nativeRequirementId='framework:PR_TASK_SCOPE_AND_FORBIDDEN';coverageState='INCORPORATED';nativeCatalogIdentity=(Get-Identity $sealedCatalogPath);sourceSchemaVersion=1;legacySourceRecordIdentity=$ownerSourceIdentity;v2WholeRecordIdentity='NOT_APPLICABLE'})
    Write-Utf8 $sealedCoveragePath ($coverageFixture|ConvertTo-Json -Depth 30)
    $null=Seal-ReleaseFixture (Split-Path -Parent $sealedCoveragePath) 'EXACT_CORRECTION_MAPPING_FIXTURE'
    $correctionArgs=@('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.16.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')
    $correctionMatched=Invoke-Ps $correctionChecker $correctionArgs
    $correctionMatchedValue=$correctionMatched.Output[-1]|ConvertFrom-Json
    if($correctionMatched.Code-ne0-or@($correctionMatchedValue.incorporated).Count-ne1){Write-Output ('DIAG|corrections-exact-mapping|code='+$correctionMatched.Code+'|'+$correctionMatched.Text)}
    Assert-True ($correctionMatched.Code-eq0-and[string]$correctionMatchedValue.coverageStatus-ceq'MATCHED_EXACT_MAPPING'-and@($correctionMatchedValue.incorporated).Count-eq1-and[string]$correctionMatchedValue.incorporated[0].correctionId-ceq'OWNER_FIRST_DIRECT_DOMAIN_ROUTE'-and@($correctionMatchedValue.stillEffective).Count-eq1) 'corrections-exact-alias-native-source-mapping-incorporates-once'
    $correctionDrift=$correctionRecords|ConvertTo-Json -Depth 20|ConvertFrom-Json;$correctionDrift.corrections[0].effectiveRule='Changed rule must remain effective';Write-Utf8 $correctionPath ($correctionDrift|ConvertTo-Json -Depth 20)
    $driftArgs=@('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.16.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')
    $driftRun=Invoke-Ps $correctionChecker $driftArgs;$driftValue=$driftRun.Output[-1]|ConvertFrom-Json
    Assert-True ($driftRun.Code-eq0-and@($driftValue.incorporated).Count-eq0-and@($driftValue.stillEffective).Count-eq2) 'corrections-source-record-drift-retained-not-suppressed'
    Write-Utf8 $correctionPath ($correctionRecords|ConvertTo-Json -Depth 20)
    $invalidMapping=$coverageFixture|ConvertTo-Json -Depth 30|ConvertFrom-Json;$invalidEntry=@($invalidMapping.versions|Where-Object{[string]$_.version-ceq'1.16.0'})[0];$invalidEntry.incorporationMappings[0].nativeCatalogIdentity='0|'+('0'*64);Write-Utf8 $sealedCoveragePath ($invalidMapping|ConvertTo-Json -Depth 30);$null=Seal-ReleaseFixture (Split-Path -Parent $sealedCoveragePath) 'INVALID_MAPPING_FIXTURE'
    $invalidRun=Invoke-Ps $correctionChecker $correctionArgs;$invalidValue=$invalidRun.Output[-1]|ConvertFrom-Json
    Assert-True ($invalidRun.Code-eq0-and[string]$invalidValue.coverageStatus-ceq'INVALID_RETAINED'-and@($invalidValue.incorporated).Count-eq0-and@($invalidValue.stillEffective).Count-eq2) 'corrections-invalid-mapping-retains-all'
    Write-Utf8 $sealedCoveragePath ($coverageFixture|ConvertTo-Json -Depth 30);$null=Seal-ReleaseFixture (Split-Path -Parent $sealedCoveragePath) 'EXACT_CORRECTION_MAPPING_FIXTURE'
    $correctionOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionPath
    $correctionDuplicate=$correctionOriginal-replace '"projectId"\s*:\s*"correction-fixture"',('"projectId": "correction-fixture",'+"`n"+'  "\u0070rojectId": "correction-fixture"')
    Write-Utf8 $correctionPath $correctionDuplicate
    $correctionDuplicateRun=Invoke-Ps $correctionChecker @('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.16.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')
    Assert-True ($correctionDuplicateRun.Code-ne0-and$correctionDuplicateRun.Text.Contains('JSON_DUPLICATE_FIELD')) 'corrections-unicode-duplicate-field-fails-closed'
    Write-Utf8 $correctionPath $correctionOriginal
    $missingCorrectionRoot=Join-Path $temp 'correction-missing-fixture';New-Item -ItemType Directory -Path (Join-Path $missingCorrectionRoot '.ai-workspace') -Force|Out-Null
    $missingCorrectionConfigPath=Join-Path $missingCorrectionRoot '.ai-workspace\project.json';Write-Utf8 $missingCorrectionConfigPath (($correctionConfig|ConvertTo-Json -Depth 20).Replace('correction-fixture','correction-missing-fixture'))
    $missingCorrectionPolicy=$routineFixturePolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$missingCorrectionPolicy.projectId='correction-missing-fixture';Write-Utf8 (Join-Path $missingCorrectionRoot '.ai-workspace\process-policy.json') ($missingCorrectionPolicy|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $missingCorrectionRoot '.ai-workspace\BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nProject-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.`n<!-- PROJECT-CUSTOM:END -->`n"
    $missingCorrectionRun=Invoke-Ps $correctionChecker @('-ProjectRoot',$missingCorrectionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.16.0','-ExpectedProjectConfigIdentity',(Get-Identity $missingCorrectionConfigPath),'-Operation','PRECHECK','-AllowMissingCorrections','-AsJson')
    $missingCorrectionValue=$missingCorrectionRun.Output[-1]|ConvertFrom-Json
    Assert-True ($missingCorrectionRun.Code-eq0-and[string]$missingCorrectionValue.correctionsIdentity-ceq'MISSING'-and@($missingCorrectionValue.stillEffective).Count-eq0) 'corrections-legacy-missing-is-empty-set'

    $processResolver=Join-Path $correctionFrameworkRoot 'framework\versions\1.16.0\scripts\resolve-process-requirements.ps1'
    $processTaskPath=Join-Path $correctionRoot '.ai-workspace\tasks\active\PROCESS-FIXTURE-001.md'
    Write-Utf8 $processTaskPath "# PROCESS-FIXTURE-001 - process fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=DOMAIN_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[src/public.txt]; actual_paths=[]`n"
    $discoverInputPath=Join-Path $temp 'process-discover.json'
    $discoverInput=[ordered]@{schemaVersion=1;mode='DISCOVER';projectRoot=$correctionRoot;frameworkRoot=$correctionFrameworkRoot;taskPath=$processTaskPath;expectedProjectConfigIdentity=(Get-Identity $correctionConfigPath);expectedCorrectionsIdentity=(Get-Identity $correctionPath);expectedTaskIdentity=(Get-Identity $processTaskPath);observedActor='owner-fixture';capabilities=@();objective='Implement the bounded source change';actionKind='SOURCE_WRITE';resultKind='USER_RESPONSE';exactPaths=@('src/public.txt');hostEnforcementGrade='FRAMEWORK_GATED';evaluationOnly=$false}
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $discoverRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    $discoverResult=$discoverRun.Output[-1]|ConvertFrom-Json;$discoverValue=$discoverResult.compactReceipt;$discoverBlocks=@($discoverResult.selectedRuleBlocks)
    Assert-True ($discoverRun.Code-eq0-and[string]$discoverValue.status-ceq'PASS'-and-not[bool]$discoverValue.authorityGranted-and-not[bool]$discoverValue.semanticCorrectnessProven-and[string]$discoverValue.actor-ceq'owner-fixture'-and@($discoverBlocks.requirementId)-contains'framework:PR_ACTION_AUTHORIZATION_INDEPENDENT'-and@($discoverBlocks.requirementId)-contains'correction:correction-fixture:PROJECT_CORRECTION_LIFECYCLE'-and@($discoverBlocks.requirementId)-notcontains$ownerAlias) 'process-discover-composes-three-sources-with-exact-absorption'
    $discoverResultJson=$discoverResult|ConvertTo-Json -Depth 50 -Compress;$discoverReceiptJson=$discoverValue|ConvertTo-Json -Depth 50 -Compress
    Assert-True ($discoverResultJson.Contains('"fullText"')-and-not$discoverReceiptJson.Contains('"fullText"')-and[Text.Encoding]::UTF8.GetByteCount($discoverReceiptJson)-lt[Text.Encoding]::UTF8.GetByteCount($discoverResultJson)) 'process-discover-emits-full-blocks-once-and-reusable-compact-receipt'
    $projectCapabilityConfigOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionConfigPath
    $projectCapabilityCases=@(
        [pscustomobject]@{Name='unknown-id';TestName='process-resolver-capability-unknown-id-fails-closed';Capabilities=[ordered]@{UNKNOWN=[ordered]@{enabled=$false}};Expected='PROJECT_CAPABILITIES_ID'},
        [pscustomobject]@{Name='disabled-extra-field';TestName='process-resolver-capability-disabled-extra-field-fails-closed';Capabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$false;indexLocator='knowledge/index.json'}};Expected='PROJECT_CAPABILITY_KNOWLEDGE_REFERENCE_FIELDS'},
        [pscustomobject]@{Name='enabled-missing-field';TestName='process-resolver-capability-enabled-missing-field-fails-closed';Capabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$true}};Expected='PROJECT_CAPABILITY_KNOWLEDGE_REFERENCE_FIELDS'},
        [pscustomobject]@{Name='enabled-extra-field';TestName='process-resolver-capability-enabled-extra-field-fails-closed';Capabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$true;indexLocator='knowledge/index.json';extra='unexpected'}};Expected='PROJECT_CAPABILITY_KNOWLEDGE_REFERENCE_FIELDS'}
    )
    foreach($capabilityCase in $projectCapabilityCases){
        $projectCapabilityConfig=$projectCapabilityConfigOriginal|ConvertFrom-Json;$projectCapabilityConfig.frameworkCapabilities=$capabilityCase.Capabilities;Write-Utf8 $correctionConfigPath ($projectCapabilityConfig|ConvertTo-Json -Depth 20)
        $projectCapabilityInput=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$projectCapabilityInput.expectedProjectConfigIdentity=Get-Identity $correctionConfigPath;$projectCapabilityInputPath=Join-Path $temp ('process-capability-'+$capabilityCase.Name+'.json');Write-Utf8 $projectCapabilityInputPath ($projectCapabilityInput|ConvertTo-Json -Depth 20)
        $projectCapabilityRun=Invoke-Ps $processResolver @('-InputPath',$projectCapabilityInputPath,'-AsJson')
        Assert-True ($projectCapabilityRun.Code-ne0-and$projectCapabilityRun.Text.Contains([string]$capabilityCase.Expected)) ([string]$capabilityCase.TestName)
    }
    Write-Utf8 $correctionConfigPath $projectCapabilityConfigOriginal
    $cleanupSuccessPath=Join-Path ([IO.Path]::GetTempPath()) ('aiw-'+[guid]::NewGuid().ToString('N')+'.json');Write-Utf8 $cleanupSuccessPath ($discoverInput|ConvertTo-Json -Depth 20)
    $cleanupSuccessRun=Invoke-Ps $processResolver @('-InputPath',$cleanupSuccessPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($cleanupSuccessRun.Code-eq0-and-not(Test-Path -LiteralPath $cleanupSuccessPath)) 'process-temp-input-cleanup-removes-exact-safe-file-after-success'
    $cleanupFailurePath=Join-Path ([IO.Path]::GetTempPath()) ('aiw-'+[guid]::NewGuid().ToString('N')+'.json');Write-Utf8 $cleanupFailurePath '{'
    $cleanupFailureRun=Invoke-Ps $processResolver @('-InputPath',$cleanupFailurePath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($cleanupFailureRun.Code-ne0-and$cleanupFailureRun.Text.Contains('INPUT_JSON')-and(Test-Path -LiteralPath $cleanupFailurePath)) 'process-temp-input-cleanup-retains-file-when-strict-parse-fails'
    Remove-Item -LiteralPath $cleanupFailurePath -Force
    $projectRuntimeDir=Join-Path $correctionRoot '.ai-workspace\runtime\PROCESS-FIXTURE-001\owner-fixture';New-Item -ItemType Directory -Path $projectRuntimeDir -Force|Out-Null
    $projectRuntimePath=Join-Path $projectRuntimeDir 'discover.json';Write-Utf8 $projectRuntimePath ($discoverInput|ConvertTo-Json -Depth 20)
    $projectRuntimeRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimePath,'-AsJson','-DeleteInputOnExit');$projectRuntimeValue=$projectRuntimeRun.Output[-1]|ConvertFrom-Json
    Assert-True ($projectRuntimeRun.Code-eq0-and[string]$projectRuntimeValue.artifactStorage-ceq'PROJECT_RUNTIME'-and-not(Test-Path -LiteralPath $projectRuntimePath)) 'process-project-runtime-input-is-task-actor-bound-and-cleaned'
    $projectRuntimeDriftDir=Join-Path $correctionRoot '.ai-workspace\runtime\PROCESS-FIXTURE-001\different-actor';New-Item -ItemType Directory -Path $projectRuntimeDriftDir -Force|Out-Null
    $projectRuntimeDriftPath=Join-Path $projectRuntimeDriftDir 'discover.json';Write-Utf8 $projectRuntimeDriftPath ($discoverInput|ConvertTo-Json -Depth 20)
    $projectRuntimeDriftRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeDriftPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($projectRuntimeDriftRun.Code-ne0-and$projectRuntimeDriftRun.Text.Contains('INPUT_RUNTIME_BINDING_DRIFT')-and(Test-Path -LiteralPath $projectRuntimeDriftPath)) 'process-project-runtime-input-binding-drift-fails-closed-and-retains'
    Remove-Item -LiteralPath $projectRuntimeDriftPath -Force
    $unrelatedRuntimeDir=Join-Path $temp 'unrelated-cleanup-project\.ai-workspace\runtime\PROCESS-FIXTURE-001\owner-fixture';New-Item -ItemType Directory -Path $unrelatedRuntimeDir -Force|Out-Null
    $unrelatedRuntimePath=Join-Path $unrelatedRuntimeDir 'discover.json';Write-Utf8 $unrelatedRuntimePath ($discoverInput|ConvertTo-Json -Depth 20)
    $unrelatedRuntimeRun=Invoke-Ps $processResolver @('-InputPath',$unrelatedRuntimePath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($unrelatedRuntimeRun.Code-ne0-and$unrelatedRuntimeRun.Text.Contains('INPUT_RUNTIME_PROJECT_ROOT_DRIFT')-and(Test-Path -LiteralPath $unrelatedRuntimePath)) 'process-unrelated-project-runtime-input-binding-fails-closed-and-retains'
    $unrelatedMalformedRuntimePath=Join-Path $unrelatedRuntimeDir 'malformed.json';Write-Utf8 $unrelatedMalformedRuntimePath '{'
    $unrelatedMalformedRuntimeRun=Invoke-Ps $processResolver @('-InputPath',$unrelatedMalformedRuntimePath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($unrelatedMalformedRuntimeRun.Code-ne0-and$unrelatedMalformedRuntimeRun.Text.Contains('INPUT_JSON')-and(Test-Path -LiteralPath $unrelatedMalformedRuntimePath)) 'process-unrelated-project-malformed-runtime-input-retained-before-binding'
    Remove-Item -LiteralPath $unrelatedRuntimePath,$unrelatedMalformedRuntimePath -Force
    $cleanupUnsafeRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($cleanupUnsafeRun.Code-ne0-and$cleanupUnsafeRun.Text.Contains('INPUT_CLEANUP_PATH_UNSAFE')-and(Test-Path -LiteralPath $discoverInputPath)) 'process-temp-input-cleanup-rejects-unsafe-name-without-deletion'

    $budgetBootstrapPath=Join-Path $correctionRoot '.ai-workspace\BOOTSTRAP.md';$budgetBootstrapOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $budgetBootstrapPath
    $largeLegacyRule='L'*40000
    $largeLegacyCorrections=[ordered]@{schemaVersion=1;contractVersion='1.10.0';projectId='correction-fixture';corrections=@([ordered]@{correctionId='LEGACY_LARGE_COMPATIBILITY';introducedAgainstFramework='1.15.1';requirementReason='Preserve one verified legacy correction during direct adoption';effectiveRule=$largeLegacyRule;applicability='All governed work until converted';decisionLocator='test:legacy-large'})}
    Write-Utf8 $policyPath ($defaultPolicy|ConvertTo-Json -Depth 20)
    Write-Utf8 $correctionPath ($largeLegacyCorrections|ConvertTo-Json -Depth 20);$largeLegacyInput=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$largeLegacyInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($largeLegacyInput|ConvertTo-Json -Depth 20)
    $largeDefaultRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($largeDefaultRun.Code-ne0-and$largeDefaultRun.Text.Contains('SELECTED_RULE_PACK_BUDGET_EXCEEDED')-and$largeDefaultRun.Text.Contains('ceiling=32768')) 'process-budget-default-project-selected-ceiling-enforced'
    $highBudgetPolicy=$defaultPolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$highBudgetPolicy.selectedRulePackBytes=98304;Write-Utf8 $policyPath ($highBudgetPolicy|ConvertTo-Json -Depth 20)
    $largeRaisedRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$largeRaisedResult=$largeRaisedRun.Output[-1]|ConvertFrom-Json;$largeRaisedReceipt=$largeRaisedResult.compactReceipt
    Assert-True ($largeRaisedRun.Code-eq0-and[int]$largeRaisedReceipt.selectedPackBytes-gt[int]$budgetContract.ceilings.defaultSelectedRulePackBytes-and[int]$largeRaisedReceipt.selectedPackBytes-le[int]$budgetContract.ceilings.absoluteSelectedRulePackBytes-and[int]$largeRaisedReceipt.selectedPackCeilingBytes-eq98304) 'process-budget-project-selected-ceiling-can-rise-to-framework-absolute-cap'
    $invalidBudgetPolicy=$defaultPolicy|ConvertTo-Json -Depth 20|ConvertFrom-Json;$invalidBudgetPolicy.selectedRulePackBytes=98305;Write-Utf8 $policyPath ($invalidBudgetPolicy|ConvertTo-Json -Depth 20)
    $invalidBudgetRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($invalidBudgetRun.Code-ne0-and$invalidBudgetRun.Text.Contains('PROCESS_POLICY_VALUES')) 'process-budget-project-policy-cannot-exceed-framework-absolute-cap'
    Write-Utf8 $policyPath ($defaultPolicy|ConvertTo-Json -Depth 20)
    $largeV2Corrections=[ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='correction-fixture';corrections=@([ordered]@{correctionId='CURRENT_LARGE_RULE';introducedAgainstFramework='1.15.1';requirementReason='Exercise the project-selected ceiling';effectiveRule=$largeLegacyRule;applicability='Bounded source work';decisionLocator='test:current-large';selectors=[ordered]@{profiles=@('STANDARD');roles=@('DOMAIN_OWNER');phases=@('IMPLEMENT');actionKinds=@('SOURCE_WRITE');resultKinds=@('*');pathPrefixes=@('src/');capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@()})}
    Write-Utf8 $correctionPath ($largeV2Corrections|ConvertTo-Json -Depth 30);$largeV2Input=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$largeV2Input.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($largeV2Input|ConvertTo-Json -Depth 20)
    $largeV2Run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($largeV2Run.Code-ne0-and$largeV2Run.Text.Contains('SELECTED_RULE_PACK_BUDGET_EXCEEDED')-and$largeV2Run.Text.Contains('ceiling=32768')) 'process-budget-correction-schema-does-not-change-project-selected-ceiling'
    Write-Utf8 $budgetBootstrapPath $budgetBootstrapOriginal;Write-Utf8 $correctionPath $correctionOriginal;Write-Utf8 $policyPath ($routineFixturePolicy|ConvertTo-Json -Depth 20);$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $discoverRaw=$discoverInput|ConvertTo-Json -Depth 20
    $duplicateDiscover=[regex]::Replace($discoverRaw,'"mode"\s*:\s*"DISCOVER"','"mode": "DISCOVER", "mode": "FINALIZE_OUTPUT"',1);Write-Utf8 $discoverInputPath $duplicateDiscover
    $duplicateDiscoverRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($duplicateDiscoverRun.Code-ne0-and$duplicateDiscoverRun.Text.Contains('INPUT_FIELD_COUNT|mode')) 'process-input-rejects-duplicate-mode-before-json-collapse'
    $wrongDiscoverSchema=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$wrongDiscoverSchema.schemaVersion=3;Write-Utf8 $discoverInputPath ($wrongDiscoverSchema|ConvertTo-Json -Depth 20)
    $wrongDiscoverSchemaRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($wrongDiscoverSchemaRun.Code-ne0-and$wrongDiscoverSchemaRun.Text.Contains('INPUT_SCHEMA_VERSION')) 'process-discover-rejects-unknown-input-schema'
    $invalidCorrectionsIdentity=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$invalidCorrectionsIdentity.expectedCorrectionsIdentity='UNBOUND';Write-Utf8 $discoverInputPath ($invalidCorrectionsIdentity|ConvertTo-Json -Depth 20)
    $invalidCorrectionsIdentityRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($invalidCorrectionsIdentityRun.Code-ne0-and$invalidCorrectionsIdentityRun.Text.Contains('INPUT_IDENTITY|expectedCorrectionsIdentity')) 'process-discover-rejects-malformed-corrections-identity'
    $alternateDiscover=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$alternateDiscover.actionKind='TEST_RUN';Write-Utf8 $discoverInputPath ($alternateDiscover|ConvertTo-Json -Depth 20)
    $alternateDiscoverRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$alternateDiscoverResult=$alternateDiscoverRun.Output[-1]|ConvertFrom-Json;$alternateDiscoverValue=$alternateDiscoverResult.compactReceipt
    Assert-True ($alternateDiscoverRun.Code-eq0-and[string]$alternateDiscoverValue.sourceCompositionIdentity-ceq[string]$discoverValue.sourceCompositionIdentity-and[string]$alternateDiscoverValue.selectionIdentity-cne[string]$discoverValue.selectionIdentity) 'process-source-composition-and-boundary-selection-identities-separated'
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $discoverReceiptPath=Join-Path $temp 'process-discover-receipt.json';Write-Utf8 $discoverReceiptPath ($discoverValue|ConvertTo-Json -Depth 30)
    $requiredPrep=@($discoverValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $requiredResult=@($discoverValue.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $boundaryBase=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$discoverReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $discoverReceiptPath);objective=$discoverInput.objective;actionKind=$discoverInput.actionKind;resultKind=$discoverInput.resultKind;exactPaths=@($discoverInput.exactPaths);authorizationIdentity='100|'+('A'*64);preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    $admitInputPath=Join-Path $temp 'process-admit.json';Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $boundaryRaw=$boundaryBase|ConvertTo-Json -Depth 20
    $duplicateBoundary=[regex]::Replace($boundaryRaw,'"authorizationIdentity"\s*:\s*"[^"]+"','"authorizationIdentity": "100|'+('A'*64)+'", "authorizationIdentity": "100|'+('B'*64)+'"',1);Write-Utf8 $admitInputPath $duplicateBoundary
    $duplicateBoundaryRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($duplicateBoundaryRun.Code-ne0-and$duplicateBoundaryRun.Text.Contains('INPUT_FIELD_COUNT|authorizationIdentity')) 'process-boundary-rejects-duplicate-authorization-identity'
    $wrongBoundarySchema=$boundaryBase|ConvertTo-Json -Depth 20|ConvertFrom-Json;$wrongBoundarySchema.schemaVersion=2;Write-Utf8 $admitInputPath ($wrongBoundarySchema|ConvertTo-Json -Depth 20)
    $wrongBoundarySchemaRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($wrongBoundarySchemaRun.Code-ne0-and$wrongBoundarySchemaRun.Text.Contains('INPUT_SCHEMA_VERSION')) 'process-boundary-rejects-unknown-input-schema'
    $receiptRaw=$discoverValue|ConvertTo-Json -Depth 30
    $duplicateReceiptRaw=[regex]::Replace($receiptRaw,'("projectConfigIdentity"\s*:\s*"[^"]+")','$1, "projectConfigIdentity": "MISSING"',1)
    $duplicateReceiptPath=Join-Path $temp 'process-discover-receipt-duplicate.json';Write-Utf8 $duplicateReceiptPath $duplicateReceiptRaw
    $duplicateReceiptBoundary=$boundaryBase|ConvertTo-Json -Depth 20|ConvertFrom-Json;$duplicateReceiptBoundary.discoverReceiptPath=$duplicateReceiptPath;$duplicateReceiptBoundary.expectedDiscoverReceiptIdentity=Get-Identity $duplicateReceiptPath;Write-Utf8 $admitInputPath ($duplicateReceiptBoundary|ConvertTo-Json -Depth 20)
    $duplicateReceiptRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($duplicateReceiptRun.Code-ne0-and$duplicateReceiptRun.Text.Contains('INPUT_FIELD_COUNT|projectConfigIdentity')) 'process-receipt-rejects-nested-duplicate-binding'
    Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $admitBlocked=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$admitBlockedValue=$admitBlocked.Output[-1]|ConvertFrom-Json
    if($admitBlocked.Code-ne3){Write-Output ('DIAG|process-admit-blocked|code='+$admitBlocked.Code+'|'+$admitBlocked.Text)}
    Assert-True ($admitBlocked.Code-eq3-and[string]$admitBlockedValue.reason-ceq'PREPARATION_INCOMPLETE'-and@($admitBlockedValue.missingPreparation)-contains'LEGACY_AUTHORITY_CONTEXT_UNBOUND') 'process-legacy-schema1-admit-blocks-unbound-authority'
    $boundaryBase.preparationReceipts=@($requiredPrep);Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $admitPass=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$admitPassValue=$admitPass.Output[-1]|ConvertFrom-Json
    if($admitPass.Code-ne3){Write-Output ('DIAG|process-legacy-admit|code='+$admitPass.Code+'|'+$admitPass.Text)}
    Assert-True ($admitPass.Code-eq3-and[string]$admitPassValue.status-ceq'BLOCKED'-and@($admitPassValue.missingPreparation)-contains'LEGACY_AUTHORITY_CONTEXT_UNBOUND'-and[int]$admitPassValue.sourceBuildCount-eq1-and[int]$admitPassValue.decisionBuildCount-eq1) 'process-legacy-schema1-categorical-action-cannot-pass-with-fabricated-authorization-identity'
    $boundaryBase.mode='FINALIZE_OUTPUT';Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $finalBlocked=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$finalBlockedValue=$finalBlocked.Output[-1]|ConvertFrom-Json
    if($finalBlocked.Code-ne3){Write-Output ('DIAG|process-final-blocked|code='+$finalBlocked.Code+'|'+$finalBlocked.Text)}
    Assert-True ($finalBlocked.Code-eq3-and[string]$finalBlockedValue.reason-ceq'PREPARATION_INCOMPLETE'-and@($finalBlockedValue.missingPreparation)-contains'LEGACY_AUTHORITY_CONTEXT_UNBOUND'-and@($finalBlockedValue.missingResult)-contains'DELIVERY_RECEIPT') 'process-legacy-schema1-finalize-blocks-authority-and-missing-delivery'
    $boundaryBase.resultReceipts=@($requiredResult);$boundaryBase.deliveryReceipts=@('DIRECT_USER_DELIVERY');Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $finalPass=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$finalPassValue=$finalPass.Output[-1]|ConvertFrom-Json
    if($finalPass.Code-ne3){Write-Output ('DIAG|process-legacy-finalize|code='+$finalPass.Code+'|'+$finalPass.Text)}
    Assert-True ($finalPass.Code-eq3-and[string]$finalPassValue.status-ceq'BLOCKED'-and@($finalPassValue.missingPreparation)-contains'LEGACY_AUTHORITY_CONTEXT_UNBOUND'-and[int]$finalPassValue.sourceBuildCount-eq1-and[int]$finalPassValue.decisionBuildCount-eq1-and-not[bool]$finalPassValue.authorityGranted-and-not[bool]$finalPassValue.semanticCorrectnessProven) 'process-legacy-schema1-finalize-cannot-pass-with-fabricated-authorization-identity'
    $contextDrift=$boundaryBase|ConvertTo-Json -Depth 20|ConvertFrom-Json;$contextDrift.actionKind='TEST_RUN';Write-Utf8 $admitInputPath ($contextDrift|ConvertTo-Json -Depth 20)
    $contextDriftRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($contextDriftRun.Code-ne0-and$contextDriftRun.Text.Contains('DISCOVER_CONTEXT_DRIFT')) 'process-boundary-rejects-stale-discover-selection'
    Write-Utf8 $admitInputPath ($boundaryBase|ConvertTo-Json -Depth 20)
    $correctionSourceBefore=Get-Content -LiteralPath $correctionPath -Raw -Encoding utf8
    Write-Utf8 $correctionPath ($correctionSourceBefore.TrimEnd("`n")+"`n`n")
    $sourceDriftRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($sourceDriftRun.Code-ne0-and$sourceDriftRun.Text.Contains('DISCOVER_SOURCE_DRIFT|correctionsIdentity')) 'process-boundary-rejects-source-drift-before-action-or-output'
    [IO.File]::WriteAllText($correctionPath,$correctionSourceBefore,[Text.UTF8Encoding]::new($false))
    $actorDrift=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$actorDrift.observedActor='other-actor';Write-Utf8 $discoverInputPath ($actorDrift|ConvertTo-Json -Depth 20)
    $actorDriftRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($actorDriftRun.Code-ne0-and$actorDriftRun.Text.Contains('CONFLICT_ACTOR_ROLE_PHASE')) 'process-discover-rejects-host-task-actor-drift'
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $unknownAction=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$unknownAction.actionKind='UNKNOWN_ACTION';Write-Utf8 $discoverInputPath ($unknownAction|ConvertTo-Json -Depth 20)
    $unknownActionRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($unknownActionRun.Code-ne0-and$unknownActionRun.Text.Contains('ACTION_KIND')) 'process-discover-rejects-unknown-action-kind'
    $capabilityDrift=$discoverInput|ConvertTo-Json -Depth 20|ConvertFrom-Json;$capabilityDrift.capabilities=@('KNOWLEDGE_REFERENCE');Write-Utf8 $discoverInputPath ($capabilityDrift|ConvertTo-Json -Depth 20)
    $capabilityDriftRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($capabilityDriftRun.Code-ne0-and$capabilityDriftRun.Text.Contains('PROJECT_CAPABILITY_DRIFT')) 'process-discover-rejects-caller-capability-drift'
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)

    $v2AuthorizationPath=Join-Path $temp 'process-v2-authorization.json'
    $v2Authorization=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';taskId='PROCESS-FIXTURE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='DOMAIN_OWNER';grantee='owner-fixture';bundle='IMPLEMENT_LOCAL';decisionClass='PRODUCT_RESULT';userConfirmation='USER_FIXTURE_SOURCE_APPROVED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Get-Identity $processTaskPath);actions=@('SOURCE_WRITE');exactPaths=@('src/public.txt');objectIdentities=@([ordered]@{path='src/public.txt';identity='NEW'});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Get-Identity $correctionConfigPath)}
    Write-Utf8 $v2AuthorizationPath ($v2Authorization|ConvertTo-Json -Depth 20)
    $v2Intent=[ordered]@{schemaVersion=1;objective='Implement the bounded source change';requestedActionKind='SOURCE_WRITE';requestedResultKind='USER_RESPONSE';semanticHints=@('implementation');pathHints=@('src/public.txt');capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'}
    $discoverV2=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$correctionRoot;frameworkRoot=$correctionFrameworkRoot;taskPath=$processTaskPath;expectedProjectConfigIdentity=(Get-Identity $correctionConfigPath);expectedCorrectionsIdentity=(Get-Identity $correctionPath);expectedTaskIdentity=(Get-Identity $processTaskPath);observedActor='owner-fixture';capabilities=@();exactPaths=@('src/public.txt');forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$v2AuthorizationPath;expectedAuthorizationIdentity=(Get-Identity $v2AuthorizationPath);userDecision='USER_FIXTURE_SOURCE_APPROVED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$v2Intent;evaluationOnly=$false}
    Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    $discoverV2Run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$discoverV2Result=$discoverV2Run.Output[-1]|ConvertFrom-Json;$discoverV2Value=$discoverV2Result.compactReceipt;$discoverV2Blocks=@($discoverV2Result.selectedRuleBlocks)
    if($discoverV2Run.Code-ne0){Write-Output ('DIAG|process-v2-discover|code='+$discoverV2Run.Code+'|'+$discoverV2Run.Text)}
    Assert-True ($discoverV2Run.Code-eq0-and[int]$discoverV2Value.inputContractVersion-eq2-and[string]$discoverV2Value.authorityContext.authorizationIdentity-ceq(Get-Identity $v2AuthorizationPath)-and@($discoverV2Value.authorityContext.authorizedActions)-contains'SOURCE_WRITE'-and[string]$discoverV2Value.authorityContext.repositoryGitTop-cne'UNPROVEN'-and[string]$discoverV2Value.invocationState-ceq'PROVEN_EXPLICIT'-and[int]$discoverV2Value.selectedPackBytes-le[int]$budgetContract.ceilings.defaultSelectedRulePackBytes-and[int]$discoverV2Value.selectedPackCeilingBytes-eq98304-and-not(@($discoverV2Value.evidenceCeilings)-contains'INVOCATION_UNPROVEN')) 'process-v2-discover-binds-authority-intent-package-and-project-budget'
    Write-Utf8 $policyPath ($defaultPolicy|ConvertTo-Json -Depth 20)
    Write-Utf8 $correctionPath ($largeLegacyCorrections|ConvertTo-Json -Depth 20);$largeAmbiguousInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$largeAmbiguousInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;$largeAmbiguousInput.intentEnvelope.ambiguityState='UNKNOWN';Write-Utf8 $discoverInputPath ($largeAmbiguousInput|ConvertTo-Json -Depth 30)
    $largeAmbiguousRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($largeAmbiguousRun.Code-ne0-and$largeAmbiguousRun.Text.Contains('SELECTED_RULE_PACK_BUDGET_EXCEEDED')-and$largeAmbiguousRun.Text.Contains('ceiling=32768')) 'process-budget-ambiguous-intent-disables-legacy-compatibility'
    Write-Utf8 $correctionPath $correctionOriginal;Write-Utf8 $policyPath ($routineFixturePolicy|ConvertTo-Json -Depth 20);$discoverV2.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    foreach($intentMismatchCase in @(
        [pscustomobject]@{Name='path';Mutate={param($v)$v.intentEnvelope.pathHints=@('outside/')};Reason='PATH_HINT_OUTSIDE_EXACT_SCOPE'},
        [pscustomobject]@{Name='capability';Mutate={param($v)$v.intentEnvelope.capabilityHints=@('UNOBSERVED_CAPABILITY')};Reason='CAPABILITY_HINT_UNOBSERVED'},
        [pscustomobject]@{Name='mutation';Mutate={param($v)$v.intentEnvelope.mutationHints=@('test')};Reason='MUTATION_HINT_ACTION_MISMATCH'},
        [pscustomobject]@{Name='external';Mutate={param($v)$v.intentEnvelope.externalHints=@('provider')};Reason='EXTERNAL_HINT_ACTION_MISMATCH'}
    )){
        $mismatchInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;& $intentMismatchCase.Mutate $mismatchInput;Write-Utf8 $discoverInputPath ($mismatchInput|ConvertTo-Json -Depth 30)
        $mismatchRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($mismatchRun.Code-ne0-and$mismatchRun.Text.Contains('INTENT_FACT_MISMATCH')-and$mismatchRun.Text.Contains([string]$intentMismatchCase.Reason)) ('process-v2-clear-intent-reconciles-'+[string]$intentMismatchCase.Name+'-fact')
    }
    $semanticIdentityInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$semanticIdentityInput.intentEnvelope.semanticHints=@('implementation','identity-drift');Write-Utf8 $discoverInputPath ($semanticIdentityInput|ConvertTo-Json -Depth 30)
    $semanticIdentityRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$semanticIdentityResult=$semanticIdentityRun.Output[-1]|ConvertFrom-Json;$semanticIdentityValue=$semanticIdentityResult.compactReceipt
    Assert-True ($semanticIdentityRun.Code-eq0-and[string]$semanticIdentityValue.selectionIdentity-cne[string]$discoverV2Value.selectionIdentity-and[string]$semanticIdentityValue.contextIdentity-cne[string]$discoverV2Value.contextIdentity) 'process-v2-full-intent-envelope-binds-selection-and-context-identities'
    $unknownMismatchInput=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$unknownMismatchInput.intentEnvelope.ambiguityState='UNKNOWN';$unknownMismatchInput.intentEnvelope.mutationHints=@('test');Write-Utf8 $discoverInputPath ($unknownMismatchInput|ConvertTo-Json -Depth 30)
    $unknownMismatchRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');if($unknownMismatchRun.Code-ne0){throw ('ASSERT_FAIL|process-v2-unknown-intent-fact-mismatch-loads-conservatively|'+$unknownMismatchRun.Code+'|'+$unknownMismatchRun.Text)};$unknownMismatchResult=$unknownMismatchRun.Output[-1]|ConvertFrom-Json;$unknownMismatchValue=$unknownMismatchResult.compactReceipt
    Assert-True ($unknownMismatchRun.Code-eq0-and[int]$unknownMismatchValue.selectedPackCeilingBytes-eq98304-and@($unknownMismatchValue.evidenceCeilings)-contains'INTENT_FACT_MISMATCH_CONSERVATIVE_LOAD') 'process-v2-unknown-intent-fact-mismatch-loads-conservatively'
    Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    $malformedAuthorization=$v2Authorization|ConvertTo-Json -Depth 30|ConvertFrom-Json;$malformedAuthorization.PSObject.Properties.Remove('taskIdentity');Write-Utf8 $v2AuthorizationPath ($malformedAuthorization|ConvertTo-Json -Depth 30)
    $malformedDiscover=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$malformedDiscover.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;Write-Utf8 $discoverInputPath ($malformedDiscover|ConvertTo-Json -Depth 30)
    $malformedAuthorizationRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($malformedAuthorizationRun.Code-ne0-and$malformedAuthorizationRun.Text.Contains('AUTHORIZATION_CHECK_FAILED')-and$malformedAuthorizationRun.Text.Contains('FIELD_MISSING_taskIdentity')) 'process-v2-discover-consumes-complete-authorization-package'
    Write-Utf8 $v2AuthorizationPath ($v2Authorization|ConvertTo-Json -Depth 30);$discoverV2.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;Write-Utf8 $discoverInputPath ($discoverV2|ConvertTo-Json -Depth 30)
    $discoverV2ReceiptPath=Join-Path $temp 'process-v2-discover-receipt.json';Write-Utf8 $discoverV2ReceiptPath ($discoverV2Value|ConvertTo-Json -Depth 40)
    $v2Prep=@($discoverV2Value.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $v2Result=@($discoverV2Value.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $v2Boundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$discoverV2ReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $discoverV2ReceiptPath);objective=$v2Intent.objective;actionKind=$v2Intent.requestedActionKind;resultKind=$v2Intent.requestedResultKind;exactPaths=@('src/public.txt');authorizationIdentity=(Get-Identity $v2AuthorizationPath);preparationReceipts=@($v2Prep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Utf8 $admitInputPath ($v2Boundary|ConvertTo-Json -Depth 30)
    $v2Admit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$v2AdmitValue=$v2Admit.Output[-1]|ConvertFrom-Json
    Assert-True ($v2Admit.Code-eq0-and$v2Admit.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) 'process-v2-admit-valid-package-and-preparation-pass'
    $projectRuntimeV2ReceiptPath=Join-Path $projectRuntimeDir 'v2-receipt.json';Write-Utf8 $projectRuntimeV2ReceiptPath ($discoverV2Value|ConvertTo-Json -Depth 40)
    $projectRuntimeV2Boundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$projectRuntimeV2Boundary.discoverReceiptPath=$projectRuntimeV2ReceiptPath;$projectRuntimeV2Boundary.expectedDiscoverReceiptIdentity=Get-Identity $projectRuntimeV2ReceiptPath
    $projectRuntimeV2AdmitPath=Join-Path $projectRuntimeDir 'admit.json';Write-Utf8 $projectRuntimeV2AdmitPath ($projectRuntimeV2Boundary|ConvertTo-Json -Depth 30)
    $projectRuntimeV2Admit=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeV2AdmitPath,'-AsJson','-DeleteInputOnExit');$projectRuntimeV2AdmitValue=$projectRuntimeV2Admit.Output[-1]|ConvertFrom-Json
    Assert-True ($projectRuntimeV2Admit.Code-eq0-and[string]$projectRuntimeV2AdmitValue.artifactStorage-ceq'PROJECT_RUNTIME'-and-not(Test-Path -LiteralPath $projectRuntimeV2AdmitPath)) 'process-project-runtime-admit-derives-binding-from-exact-receipt-and-cleans'
    $projectRuntimeV2DriftPath=Join-Path $projectRuntimeDir 'admit-receipt-drift.json';$projectRuntimeV2Drift=$projectRuntimeV2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$projectRuntimeV2Drift.expectedDiscoverReceiptIdentity='0|'+('0'*64);Write-Utf8 $projectRuntimeV2DriftPath ($projectRuntimeV2Drift|ConvertTo-Json -Depth 30)
    $projectRuntimeV2DriftRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeV2DriftPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($projectRuntimeV2DriftRun.Code-ne0-and$projectRuntimeV2DriftRun.Text.Contains('DISCOVER_RECEIPT_DRIFT')-and(Test-Path -LiteralPath $projectRuntimeV2DriftPath)) 'process-project-runtime-boundary-retains-input-on-receipt-identity-drift'
    Remove-Item -LiteralPath $projectRuntimeV2DriftPath -Force
    $v2ObjectPath=Join-Path $correctionRoot 'src\public.txt';Write-Utf8 $v2ObjectPath "post-discover drift`n"
    $v2ObjectDriftAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($v2ObjectDriftAdmit.Code-ne0-and$v2ObjectDriftAdmit.Text.Contains('AUTHORIZATION_CHECK_FAILED')-and$v2ObjectDriftAdmit.Text.Contains('NEW_OBJECT_EXISTS')) 'process-v2-admit-revalidates-exact-object-bytes'
    $v2PostimageIdentity=Get-Identity $v2ObjectPath
    $v2Finalize=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$v2Finalize.mode='FINALIZE_OUTPUT';$v2Finalize.resultReceipts=@($v2Result+@('OBJECT_POSTIMAGE|src/public.txt|'+$v2PostimageIdentity));$v2Finalize.deliveryReceipts=@('DIRECT_USER_DELIVERY');Write-Utf8 $admitInputPath ($v2Finalize|ConvertTo-Json -Depth 30)
    $v2FinalizePass=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    if($v2FinalizePass.Code-ne0){Write-Output ('DIAG|process-v2-finalize-pass|code='+$v2FinalizePass.Code+'|'+$v2FinalizePass.Text)}
    Assert-True ($v2FinalizePass.Code-eq0-and$v2FinalizePass.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) 'process-v2-finalize-validates-exact-postimage-receipt'
    $projectRuntimeV2Finalize=$v2Finalize|ConvertTo-Json -Depth 30|ConvertFrom-Json;$projectRuntimeV2Finalize.discoverReceiptPath=$projectRuntimeV2ReceiptPath;$projectRuntimeV2Finalize.expectedDiscoverReceiptIdentity=Get-Identity $projectRuntimeV2ReceiptPath
    $projectRuntimeV2FinalizePath=Join-Path $projectRuntimeDir 'finalize.json';Write-Utf8 $projectRuntimeV2FinalizePath ($projectRuntimeV2Finalize|ConvertTo-Json -Depth 30)
    $projectRuntimeV2FinalizeRun=Invoke-Ps $processResolver @('-InputPath',$projectRuntimeV2FinalizePath,'-AsJson','-DeleteInputOnExit');$projectRuntimeV2FinalizeValue=$projectRuntimeV2FinalizeRun.Output[-1]|ConvertFrom-Json
    Assert-True ($projectRuntimeV2FinalizeRun.Code-eq0-and[string]$projectRuntimeV2FinalizeValue.artifactStorage-ceq'PROJECT_RUNTIME'-and-not(Test-Path -LiteralPath $projectRuntimeV2FinalizePath)) 'process-project-runtime-finalize-derives-binding-from-exact-receipt-and-cleans'
    $unrelatedBoundaryPath=Join-Path $unrelatedRuntimeDir 'boundary.json';Write-Utf8 $unrelatedBoundaryPath ($projectRuntimeV2Boundary|ConvertTo-Json -Depth 30)
    $unrelatedBoundaryRun=Invoke-Ps $processResolver @('-InputPath',$unrelatedBoundaryPath,'-AsJson','-DeleteInputOnExit')
    Assert-True ($unrelatedBoundaryRun.Code-ne0-and$unrelatedBoundaryRun.Text.Contains('INPUT_RUNTIME_PROJECT_ROOT_DRIFT')-and(Test-Path -LiteralPath $unrelatedBoundaryPath)) 'process-unrelated-project-runtime-boundary-fails-closed-and-retains'
    Remove-Item -LiteralPath $unrelatedBoundaryPath,$projectRuntimeV2ReceiptPath -Force
    Write-Utf8 $v2ObjectPath "postimage drift`n"
    $v2FinalizeDrift=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($v2FinalizeDrift.Code-ne0-and$v2FinalizeDrift.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED|src/public.txt')) 'process-v2-finalize-rejects-stale-postimage-receipt'
    Remove-Item -LiteralPath $v2ObjectPath -Force
    Write-Utf8 $admitInputPath ($v2Boundary|ConvertTo-Json -Depth 30)
    $controllerOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionControllerPath;$controllerDrift=$controllerOriginal|ConvertFrom-Json;$controllerDrift.controllerEpoch=2;Write-Utf8 $correctionControllerPath ($controllerDrift|ConvertTo-Json -Depth 10)
    $controllerDriftRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($controllerDriftRun.Code-ne0-and$controllerDriftRun.Text.Contains('DISCOVER_SOURCE_DRIFT|controllerIdentity')) 'process-boundary-rejects-controller-epoch-drift'
    [IO.File]::WriteAllText($correctionControllerPath,$controllerOriginal,[Text.UTF8Encoding]::new($false))
    $spoofedV2Boundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$spoofedV2Boundary.authorizationIdentity='100|'+('B'*64);Write-Utf8 $admitInputPath ($spoofedV2Boundary|ConvertTo-Json -Depth 30)
    $spoofedV2Run=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($spoofedV2Run.Code-ne0-and$spoofedV2Run.Text.Contains('AUTHORIZATION_CONTEXT_DRIFT')) 'process-v2-boundary-rejects-unbound-authorization-identity'
    $v2AuthorizationOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $v2AuthorizationPath;Write-Utf8 $v2AuthorizationPath ($v2AuthorizationOriginal.TrimEnd("`n")+" `n")
    Write-Utf8 $admitInputPath ($v2Boundary|ConvertTo-Json -Depth 30)
    $driftedV2Authorization=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($driftedV2Authorization.Code-ne0-and$driftedV2Authorization.Text.Contains('DISCOVER_SOURCE_DRIFT|authorizationIdentity')) 'process-v2-boundary-revalidates-authorization-package-identity'
    [IO.File]::WriteAllText($v2AuthorizationPath,$v2AuthorizationOriginal,[Text.UTF8Encoding]::new($false))
    $clearNoMatchV2=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$clearNoMatchV2.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;$clearNoMatchV2.intentEnvelope.objective='Observe bounded quasar state';$clearNoMatchV2.intentEnvelope.semanticHints=@('quasar');Write-Utf8 $discoverInputPath ($clearNoMatchV2|ConvertTo-Json -Depth 30)
    $clearNoMatchDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$clearNoMatchResult=$clearNoMatchDiscover.Output[-1]|ConvertFrom-Json;$clearNoMatchValue=$clearNoMatchResult.compactReceipt;$clearNoMatchBlocks=@($clearNoMatchResult.selectedRuleBlocks)
    $ambiguousV2=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$ambiguousV2.expectedAuthorizationIdentity=Get-Identity $v2AuthorizationPath;$ambiguousV2.intentEnvelope.ambiguityState='UNKNOWN';Write-Utf8 $discoverInputPath ($ambiguousV2|ConvertTo-Json -Depth 30)
    $ambiguousDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$ambiguousResult=$ambiguousDiscover.Output[-1]|ConvertFrom-Json;$ambiguousValue=$ambiguousResult.compactReceipt;$ambiguousBlocks=@($ambiguousResult.selectedRuleBlocks)
    Assert-True ($clearNoMatchDiscover.Code-eq0-and-not(@($clearNoMatchValue.evidenceCeilings)-contains'INTENT_AMBIGUITY_CONSERVATIVE_LOAD')-and@($clearNoMatchBlocks).Count-lt@($ambiguousBlocks).Count) 'process-v2-clear-description-no-match-does-not-trigger-conservative-load'
    Assert-True ($ambiguousDiscover.Code-eq0-and@($ambiguousValue.evidenceCeilings)-contains'INTENT_AMBIGUITY_CONSERVATIVE_LOAD') 'process-v2-ambiguous-intent-loads-conservatively'
    $ambiguousReceipt=Join-Path $temp 'process-v2-ambiguous-receipt.json';Write-Utf8 $ambiguousReceipt ($ambiguousValue|ConvertTo-Json -Depth 40)
    $ambiguousBoundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$ambiguousBoundary.discoverReceiptPath=$ambiguousReceipt;$ambiguousBoundary.expectedDiscoverReceiptIdentity=Get-Identity $ambiguousReceipt;Write-Utf8 $admitInputPath ($ambiguousBoundary|ConvertTo-Json -Depth 30)
    $ambiguousAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson');$ambiguousAdmitValue=$ambiguousAdmit.Output[-1]|ConvertFrom-Json
    Assert-True ($ambiguousAdmit.Code-eq3-and$ambiguousAdmit.Text.Contains('INTENT_AMBIGUOUS')-and[string]$ambiguousAdmitValue.decisionIdentity-cne[string]$v2AdmitValue.decisionIdentity) 'process-v2-ambiguous-intent-blocks-governed-action-and-binds-decision-context'
    $oversizedIntent=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$oversizedIntent.intentEnvelope.semanticHints=@(1..65|ForEach-Object{'hint-'+$_});Write-Utf8 $discoverInputPath ($oversizedIntent|ConvertTo-Json -Depth 30)
    $oversizedIntentRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($oversizedIntentRun.Code-ne0-and$oversizedIntentRun.Text.Contains('INPUT_ARRAY_COUNT|intent_semanticHints')) 'process-v2-intent-schema-item-ceiling-enforced-at-runtime'
    $oversizedScope=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$oversizedScope.exactPaths=@(1..257|ForEach-Object{'src/file-'+$_.ToString()+'.txt'});Write-Utf8 $discoverInputPath ($oversizedScope|ConvertTo-Json -Depth 30)
    $oversizedScopeRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($oversizedScopeRun.Code-ne0-and$oversizedScopeRun.Text.Contains('INPUT_ARRAY_COUNT|exactPaths')) 'process-v2-authority-scope-item-ceiling-enforced-at-runtime'
    $noAuthV2=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json;$noAuthV2.authorizationPackagePath='NOT_REQUIRED';$noAuthV2.expectedAuthorizationIdentity='NOT_REQUIRED';$noAuthV2.userDecision='NOT_REQUIRED';Write-Utf8 $discoverInputPath ($noAuthV2|ConvertTo-Json -Depth 30)
    $noAuthDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$noAuthResult=$noAuthDiscover.Output[-1]|ConvertFrom-Json;$noAuthValue=$noAuthResult.compactReceipt
    $noAuthReceipt=Join-Path $temp 'process-v2-no-auth-receipt.json';Write-Utf8 $noAuthReceipt ($noAuthValue|ConvertTo-Json -Depth 40)
    $noAuthBoundary=$v2Boundary|ConvertTo-Json -Depth 30|ConvertFrom-Json;$noAuthBoundary.discoverReceiptPath=$noAuthReceipt;$noAuthBoundary.expectedDiscoverReceiptIdentity=Get-Identity $noAuthReceipt;$noAuthBoundary.authorizationIdentity='NOT_REQUIRED';Write-Utf8 $admitInputPath ($noAuthBoundary|ConvertTo-Json -Depth 30)
    $noAuthAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
    Assert-True ($noAuthDiscover.Code-eq0-and$noAuthAdmit.Code-eq3-and$noAuthAdmit.Text.Contains('ACTION_NOT_AUTHORIZED_IN_CONTEXT')) 'process-v2-categorical-action-without-package-blocked'
# 接受动作复用真实包与当前 Owner，不把无包、写入或结果标签当作接受权限。
    $ownerTaskOriginal=Get-Content -LiteralPath $processTaskPath -Raw -Encoding utf8
    $ownerAcceptedPath=Join-Path $correctionRoot 'src/owner-accepted.txt'
    Write-Utf8 $ownerAcceptedPath "Frozen reviewed result."
    $ownerAcceptedIdentity=Get-Identity $ownerAcceptedPath
    $ownerPackagePath=Join-Path $temp 'owner-accept-authorization.json'
    $ownerReceiptPath=Join-Path $temp 'owner-accept-receipt.json'
    try {
        foreach($ownerPhase in @('VERIFY','IMPLEMENT','PLAN')){
            Write-Utf8 $processTaskPath ($ownerTaskOriginal.Replace('phase=IMPLEMENT','phase='+$ownerPhase))
            $ownerPackage=$v2Authorization|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerPackage.actions=@('OWNER_ACCEPT')
            $ownerPackage.taskIdentity=Get-Identity $processTaskPath
            $ownerPackage.exactPaths=@('src/owner-accepted.txt')
            $ownerPackage.objectIdentities=@([pscustomobject]@{path='src/owner-accepted.txt';identity=$ownerAcceptedIdentity})
            Write-Utf8 $ownerPackagePath ($ownerPackage|ConvertTo-Json -Depth 30)
            $ownerDiscover=$discoverV2|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerDiscover.expectedTaskIdentity=$ownerPackage.taskIdentity
            $ownerDiscover.exactPaths=@($ownerPackage.exactPaths)
            $ownerDiscover.authorizationPackagePath=$ownerPackagePath
            $ownerDiscover.expectedAuthorizationIdentity=Get-Identity $ownerPackagePath
            $ownerDiscover.intentEnvelope.objective='Accept the frozen reviewed result'
            $ownerDiscover.intentEnvelope.requestedActionKind='OWNER_ACCEPT'
            $ownerDiscover.intentEnvelope.requestedResultKind='OWNER_ACCEPTANCE'
            $ownerDiscover.intentEnvelope.semanticHints=@()
            $ownerDiscover.intentEnvelope.mutationHints=@()
            $ownerDiscover.intentEnvelope.pathHints=@($ownerPackage.exactPaths)
            Write-Utf8 $discoverInputPath ($ownerDiscover|ConvertTo-Json -Depth 30)
            $ownerRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
            if($ownerRun.Code-ne0){throw ('ASSERT_FAIL|owner-accept-discover-'+$ownerPhase+'|'+$ownerRun.Text)}
            $ownerValue=($ownerRun.Output[-1]|ConvertFrom-Json).compactReceipt
            Assert-True (@($ownerValue.selectedObligations.requirementId)-contains'framework:PR_OWNER_ACCEPT_SEPARATE') ('owner-accept-rule-selected-by-action-'+$ownerPhase)
            Write-Utf8 $ownerReceiptPath ($ownerValue|ConvertTo-Json -Depth 40)
            $ownerPrep=@($ownerValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
            $ownerResult=@($ownerValue.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
            $ownerBoundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$ownerReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $ownerReceiptPath);objective=$ownerDiscover.intentEnvelope.objective;actionKind='OWNER_ACCEPT';resultKind='OWNER_ACCEPTANCE';exactPaths=@($ownerPackage.exactPaths);authorizationIdentity=(Get-Identity $ownerPackagePath);preparationReceipts=@($ownerPrep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
            Write-Utf8 $admitInputPath ($ownerBoundary|ConvertTo-Json -Depth 30)
            $ownerAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
            Assert-True ($ownerAdmit.Code-eq0-and$ownerAdmit.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) ('owner-accept-current-owner-exact-package-admitted-'+$ownerPhase)
        }
        $ownerMissingEvidence=$ownerBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerMissingEvidence.preparationReceipts=@($ownerPrep|Where-Object{$_-cne'REVIEW_OR_DIRECT_EVIDENCE_BOUND'})
        Write-Utf8 $admitInputPath ($ownerMissingEvidence|ConvertTo-Json -Depth 30)
        $ownerMissingEvidenceRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($ownerMissingEvidenceRun.Code-eq3-and$ownerMissingEvidenceRun.Text.Contains('REVIEW_OR_DIRECT_EVIDENCE_BOUND')) 'owner-accept-missing-review-or-direct-evidence-blocked'

        $ownerBoundary.mode='FINALIZE_OUTPUT'
        $ownerBoundary.resultReceipts=@($ownerResult)+@('OBJECT_POSTIMAGE|src/owner-accepted.txt|'+$ownerAcceptedIdentity)
        $ownerBoundary.deliveryReceipts=@('FIXTURE_OWNER_ACCEPTANCE_RECORD')
        Write-Utf8 $admitInputPath ($ownerBoundary|ConvertTo-Json -Depth 30)
        $ownerFinal=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($ownerFinal.Code-eq0-and$ownerFinal.Text.Contains('"authorityGranted":false')-and(Get-Identity $ownerAcceptedPath)-ceq$ownerAcceptedIdentity) 'owner-accept-finalize-exact-unchanged-result-without-write-authority'
        $ownerMissingRecord=$ownerBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerMissingRecord.resultReceipts=@($ownerBoundary.resultReceipts|Where-Object{$_-cne'OWNER_ACCEPT_RECORDED'})
        Write-Utf8 $admitInputPath ($ownerMissingRecord|ConvertTo-Json -Depth 30)
        $ownerMissingRecordRun=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($ownerMissingRecordRun.Code-eq3-and$ownerMissingRecordRun.Text.Contains('OWNER_ACCEPT_RECORDED')) 'owner-accept-finalize-missing-acceptance-record-blocked'

        $ownerNoAuth=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerNoAuth.authorizationPackagePath='NOT_REQUIRED';$ownerNoAuth.expectedAuthorizationIdentity='NOT_REQUIRED';$ownerNoAuth.userDecision='NOT_REQUIRED'
        Write-Utf8 $discoverInputPath ($ownerNoAuth|ConvertTo-Json -Depth 30)
        $ownerNoAuthRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($ownerNoAuthRun.Code-eq0) 'owner-accept-no-package-discover-is-not-admission'
        $ownerNoAuthValue=($ownerNoAuthRun.Output[-1]|ConvertFrom-Json).compactReceipt
        Write-Utf8 $ownerReceiptPath ($ownerNoAuthValue|ConvertTo-Json -Depth 40)
        $ownerNoAuthBoundary=$ownerBoundary|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerNoAuthBoundary.mode='ADMIT_ACTION';$ownerNoAuthBoundary.expectedDiscoverReceiptIdentity=Get-Identity $ownerReceiptPath;$ownerNoAuthBoundary.authorizationIdentity='NOT_REQUIRED'
        Write-Utf8 $admitInputPath ($ownerNoAuthBoundary|ConvertTo-Json -Depth 30)
        $ownerNoAuthAdmit=Invoke-Ps $processResolver @('-InputPath',$admitInputPath,'-AsJson')
        Assert-True ($ownerNoAuthAdmit.Code-eq3-and$ownerNoAuthAdmit.Text.Contains('ACTION_NOT_AUTHORIZED_IN_CONTEXT')) 'owner-accept-no-package-remains-blocked'

        foreach($ownerOtherAction in @('NONE','CONTROL_WRITE')){
            $ownerWrongKind=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerWrongKind.intentEnvelope.requestedActionKind=$ownerOtherAction
            Write-Utf8 $discoverInputPath ($ownerWrongKind|ConvertTo-Json -Depth 30)
            $ownerWrongKindRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
            Assert-True ($ownerWrongKindRun.Code-ne0-and$ownerWrongKindRun.Text.Contains('OWNER_ACCEPT_ACTION_REQUIRED')) ('owner-acceptance-result-cannot-bypass-with-'+$ownerOtherAction)
        }
        foreach($ownerOtherAction in @('SOURCE_WRITE','GIT_COMMIT','PUSH')){
            $ownerNoEscalation=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
            $ownerNoEscalation.intentEnvelope.requestedActionKind=$ownerOtherAction
            $ownerNoEscalation.intentEnvelope.requestedResultKind='USER_RESPONSE'
            Write-Utf8 $discoverInputPath ($ownerNoEscalation|ConvertTo-Json -Depth 30)
            $ownerNoEscalationRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
            Assert-True ($ownerNoEscalationRun.Code-ne0-and$ownerNoEscalationRun.Text.Contains('ACTION_NOT_GRANTED')) ('owner-accept-package-does-not-grant-'+$ownerOtherAction)
        }
        Write-Utf8 $ownerAcceptedPath "Changed after review."
        Write-Utf8 $discoverInputPath ($ownerDiscover|ConvertTo-Json -Depth 30)
        $ownerObjectDrift=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($ownerObjectDrift.Code-ne0-and$ownerObjectDrift.Text.Contains('OBJECT_DRIFT')) 'owner-accept-rejects-reviewed-object-drift'
        Write-Utf8 $ownerAcceptedPath "Frozen reviewed result."

        Write-Utf8 $processTaskPath ($ownerTaskOriginal.Replace('actor=owner-fixture','actor=executor-fixture'))
        $ownerPackage.grantee='executor-fixture';$ownerPackage.taskIdentity=Get-Identity $processTaskPath
        Write-Utf8 $ownerPackagePath ($ownerPackage|ConvertTo-Json -Depth 30)
        $ownerNotOwner=$ownerDiscover|ConvertTo-Json -Depth 30|ConvertFrom-Json
        $ownerNotOwner.observedActor='executor-fixture';$ownerNotOwner.expectedTaskIdentity=$ownerPackage.taskIdentity;$ownerNotOwner.expectedAuthorizationIdentity=Get-Identity $ownerPackagePath
        Write-Utf8 $discoverInputPath ($ownerNotOwner|ConvertTo-Json -Depth 30)
        $ownerNotOwnerRun=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
        Assert-True ($ownerNotOwnerRun.Code-ne0-and$ownerNotOwnerRun.Text.Contains('OWNER_ACCEPT_REQUIRES_CURRENT_TASK_OWNER')) 'owner-accept-rejects-current-actor-who-is-not-task-owner'
    } finally {
        Write-Utf8 $processTaskPath $ownerTaskOriginal
        if(Test-Path -LiteralPath $ownerAcceptedPath){Remove-Item -LiteralPath $ownerAcceptedPath -Force}
    }
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)

    $processConfigOriginal=Get-Content -LiteralPath $correctionConfigPath -Raw -Encoding utf8
    $processBootstrapPath=Join-Path $correctionRoot '.ai-workspace\BOOTSTRAP.md';$processBootstrapOriginal=Get-Content -LiteralPath $processBootstrapPath -Raw -Encoding utf8
    $policy=[ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='correction-fixture';selectedRulePackBytes=98304;rules=@([ordered]@{ruleId='PROJECT_SOURCE_PREP';requirementReason='Project requires one source preparation receipt';effectiveRule='Bind the project source preparation receipt before source work.';selectors=[ordered]@{profiles=@('STANDARD');roles=@('DOMAIN_OWNER');phases=@('IMPLEMENT');actionKinds=@('SOURCE_WRITE');resultKinds=@('*');pathPrefixes=@('src/');capabilities=@();semanticTerms=@()};preparationRequirements=@('PROJECT_SOURCE_PREPARED');resultRequirements=@('PROJECT_SOURCE_READBACK');decisionLocator='project:policy-fixture'})}
    Write-Utf8 $policyPath ($policy|ConvertTo-Json -Depth 30)
    $schema4=$processConfigOriginal|ConvertFrom-Json;Write-Utf8 $correctionConfigPath ($schema4|ConvertTo-Json -Depth 30)
    $discoverInput.expectedProjectConfigIdentity=Get-Identity $correctionConfigPath
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`nA permanent legacy project rule remains active.`n<!-- PROJECT-CUSTOM:END -->`n"
    Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $doubleCarrier=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($doubleCarrier.Code-eq0) 'process-distinct-policy-and-legacy-custom-carriers-compose-without-false-conflict'
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`nBind the project source preparation receipt before source work.`n<!-- PROJECT-CUSTOM:END -->`n"
    $policyCustomDuplicate=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($policyCustomDuplicate.Code-ne0-and$policyCustomDuplicate.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'process-policy-custom-duplicate-effective-rule-rejected'
    Write-Utf8 $processBootstrapPath $processBootstrapOriginal
    $correctionPolicy=$policy|ConvertTo-Json -Depth 30|ConvertFrom-Json;$correctionPolicy.rules[0].effectiveRule='Retain and evaluate project correction records';Write-Utf8 $policyPath ($correctionPolicy|ConvertTo-Json -Depth 30)
    $correctionPolicyDuplicate=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($correctionPolicyDuplicate.Code-ne0-and$correctionPolicyDuplicate.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'process-correction-policy-duplicate-effective-rule-rejected'
    $emptyPolicy=$policy|ConvertTo-Json -Depth 30|ConvertFrom-Json;$emptyPolicy.rules=@();Write-Utf8 $policyPath ($emptyPolicy|ConvertTo-Json -Depth 30)
    Write-Utf8 $processBootstrapPath "<!-- PROJECT-CUSTOM:BEGIN -->`nRetain and evaluate project correction records`n<!-- PROJECT-CUSTOM:END -->`n"
    $correctionCustomDuplicate=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($correctionCustomDuplicate.Code-ne0-and$correctionCustomDuplicate.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'process-correction-custom-duplicate-effective-rule-rejected'
    Write-Utf8 $policyPath ($policy|ConvertTo-Json -Depth 30)
    Write-Utf8 $processBootstrapPath $processBootstrapOriginal
    $policyDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$policyDiscoverResult=$policyDiscover.Output[-1]|ConvertFrom-Json;$policyDiscoverValue=$policyDiscoverResult.compactReceipt;$policyDiscoverBlocks=@($policyDiscoverResult.selectedRuleBlocks)
    if($policyDiscover.Code-ne0){Write-Output ('DIAG|process-policy-discover|code='+$policyDiscover.Code+'|'+$policyDiscover.Text)}
    Assert-True ($policyDiscover.Code-eq0-and@($policyDiscoverBlocks.requirementId)-contains'project:correction-fixture:PROJECT_SOURCE_PREP'-and@($policyDiscoverValue.evidenceCeilings)-notcontains'LEGACY_PROJECT_CUSTOM_FULL_LOAD') 'process-policy-structured-rule-selected-with-single-carrier'
    Write-Utf8 $correctionConfigPath $processConfigOriginal;Write-Utf8 $processBootstrapPath $processBootstrapOriginal
    $discoverInput.expectedProjectConfigIdentity=Get-Identity $correctionConfigPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)

    $v2SelectorSource=[ordered]@{profiles=@('STANDARD');roles=@('DOMAIN_OWNER');phases=@('IMPLEMENT');actionKinds=@('SOURCE_WRITE');resultKinds=@('*');pathPrefixes=@('src/');capabilities=@();semanticTerms=@()}
    $v2SelectorExternal=[ordered]@{profiles=@('STANDARD');roles=@('DOMAIN_OWNER');phases=@('EXTERNAL');actionKinds=@('EXTERNAL');resultKinds=@('EXTERNAL_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@()}
    $v2Corrections=[ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='correction-fixture';corrections=@(
        [ordered]@{correctionId='V2_SOURCE_ONLY';introducedAgainstFramework='1.13.0';requirementReason='Source work requires the project receipt.';effectiveRule='Bind the project source preparation and readback.';applicability='Bounded source changes';decisionLocator='test:v2-source';selectors=$v2SelectorSource;preparationRequirements=@('V2_SOURCE_PREPARED');resultRequirements=@('V2_SOURCE_READBACK');requiredFacts=@('TASK_SCOPE_CURRENT');mechanicalCheckRefs=@('ACTION_PACKAGE_VALID')},
        [ordered]@{correctionId='V2_EXTERNAL_ONLY';introducedAgainstFramework='1.13.0';requirementReason='External work needs a separate project boundary.';effectiveRule='Bind the external project boundary.';applicability='External domain work';decisionLocator='test:v2-external';selectors=$v2SelectorExternal;preparationRequirements=@('V2_EXTERNAL_PREPARED');resultRequirements=@('V2_EXTERNAL_READBACK');requiredFacts=@();mechanicalCheckRefs=@('EXTERNAL_BOUNDARY_AUTHORIZED')}
    )}
    Write-Utf8 $correctionPath ($v2Corrections|ConvertTo-Json -Depth 40);$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $v2CorrectionDiscover=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson');$v2CorrectionResult=$v2CorrectionDiscover.Output[-1]|ConvertFrom-Json;$v2CorrectionValue=$v2CorrectionResult.compactReceipt;$v2CorrectionBlocks=@($v2CorrectionResult.selectedRuleBlocks)
    Assert-True ($v2CorrectionDiscover.Code-eq0-and@($v2CorrectionBlocks.requirementId)-contains'correction:correction-fixture:V2_SOURCE_ONLY'-and@($v2CorrectionBlocks.requirementId)-notcontains'correction:correction-fixture:V2_EXTERNAL_ONLY'-and[int]$v2CorrectionValue.legacyCorrectionsFullReadCount-eq0-and@($v2CorrectionValue.evidenceCeilings)-notcontains'LEGACY_CORRECTIONS_FULL_LOAD') 'corrections-v2-progressive-selection-without-legacy-full-load-claim'
    Import-Module (Join-Path $candidateRoot 'scripts\ProcessRequirementComposition.psm1') -Force
    $v2RecordA=$v2Corrections.corrections[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json;$v2RecordB=$v2RecordA|ConvertTo-Json -Depth 30|ConvertFrom-Json;$v2RecordB.selectors.semanticTerms=@('changed')
    $v2HistoricalA=[pscustomobject][ordered]@{correctionId=$v2RecordA.correctionId;introducedAgainstFramework=$v2RecordA.introducedAgainstFramework;requirementReason=$v2RecordA.requirementReason;effectiveRule=$v2RecordA.effectiveRule;applicability=$v2RecordA.applicability;decisionLocator=$v2RecordA.decisionLocator}
    $v2HistoricalB=[pscustomobject][ordered]@{correctionId=$v2RecordB.correctionId;introducedAgainstFramework=$v2RecordB.introducedAgainstFramework;requirementReason=$v2RecordB.requirementReason;effectiveRule=$v2RecordB.effectiveRule;applicability=$v2RecordB.applicability;decisionLocator=$v2RecordB.decisionLocator}
    Assert-True ((Get-AiwCanonicalCorrectionRecordIdentityV1 $v2HistoricalA)-ceq(Get-AiwCanonicalCorrectionRecordIdentityV1 $v2HistoricalB)-and(Get-AiwCanonicalCorrectionRecordIdentityV2 $v2RecordA)-cne(Get-AiwCanonicalCorrectionRecordIdentityV2 $v2RecordB)) 'corrections-v2-whole-identity-binds-progressive-fields'
    $invalidV2=$v2Corrections|ConvertTo-Json -Depth 40|ConvertFrom-Json;$invalidV2.corrections[0].mechanicalCheckRefs=@('UNREGISTERED_CHECK');Write-Utf8 $correctionPath ($invalidV2|ConvertTo-Json -Depth 40);$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)
    $invalidV2Run=Invoke-Ps $processResolver @('-InputPath',$discoverInputPath,'-AsJson')
    Assert-True ($invalidV2Run.Code-ne0-and$invalidV2Run.Text.Contains('CORRECTION_V2_MECHANICAL_CHECK_UNREGISTERED')) 'corrections-v2-unregistered-mechanical-check-fails-closed'
    Write-Utf8 $correctionPath $correctionOriginal;$discoverInput.expectedCorrectionsIdentity=Get-Identity $correctionPath;Write-Utf8 $discoverInputPath ($discoverInput|ConvertTo-Json -Depth 20)

    $canonicalFixtures=@(
        [pscustomobject]@{Name='nfc';Record=[pscustomobject]@{correctionId='fixture-normalization';introducedAgainstFramework='1.0.0';requirementReason=[string][char]0x00E9;effectiveRule='';applicability='';decisionLocator=''};Expected='180|758F09804FBA0E117DDE12BFA8DF98D9DEA39CB5D1284034F947648AE255B291'},
        [pscustomobject]@{Name='nfd';Record=[pscustomobject]@{correctionId='fixture-normalization';introducedAgainstFramework='1.0.0';requirementReason=('e'+[char]0x0301);effectiveRule='';applicability='';decisionLocator=''};Expected='181|5869256A7DE43667C60E640082745A746FF1C062653020C073F2E0BC84AB130E'},
        [pscustomobject]@{Name='lf';Record=[pscustomobject]@{correctionId='fixture-newline';introducedAgainstFramework='1.0.0';requirementReason="line1`nline2";effectiveRule='';applicability='';decisionLocator=''};Expected='184|45F962EF1E3DE36B0B0464F045A7959712F1FAE06023B32376AA7A4F65C23EF8'},
        [pscustomobject]@{Name='crlf';Record=[pscustomobject]@{correctionId='fixture-newline';introducedAgainstFramework='1.0.0';requirementReason="line1`r`nline2";effectiveRule='';applicability='';decisionLocator=''};Expected='185|285EAA0990442125E3DC64CCB303B51C59D3FAC5CCBD460D8058A095F8E457CE'}
    )
    $node=Get-Command node -ErrorAction SilentlyContinue
    Assert-True ($null-ne$node) 'canonical-non-powershell-reference-runtime-available'
    foreach($fixture in $canonicalFixtures){
        $psIdentity=Get-AiwCanonicalCorrectionRecordIdentityV1 $fixture.Record
        $nodeJson=$fixture.Record|ConvertTo-Json -Compress
        $nodeIdentity=(& $node.Source (Join-Path $candidateRoot 'tests\canonical-identity-reference.mjs') $nodeJson)
        Assert-True ($psIdentity-ceq$fixture.Expected-and[string]$nodeIdentity-ceq$fixture.Expected) ('canonical-identity-pwsh7-node-'+$fixture.Name)
    }
    Assert-True ((Get-AiwCanonicalCorrectionRecordIdentityV1 $canonicalFixtures[0].Record)-cne(Get-AiwCanonicalCorrectionRecordIdentityV1 $canonicalFixtures[1].Record)-and(Get-AiwCanonicalCorrectionRecordIdentityV1 $canonicalFixtures[2].Record)-cne(Get-AiwCanonicalCorrectionRecordIdentityV1 $canonicalFixtures[3].Record)) 'canonical-identity-preserves-unicode-and-newlines'
    if($IsWindows){
        $windowsPowerShellCanonical=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $canonicalWrapper=Join-Path $temp 'canonical-ps51.ps1'
        Write-Utf8 $canonicalWrapper "param([string]`$Module,[string]`$RecordPath)`nImport-Module `$Module -Force`n`$record=Get-Content -LiteralPath `$RecordPath -Raw -Encoding utf8|ConvertFrom-Json`nGet-AiwCanonicalCorrectionRecordIdentityV1 `$record`n"
        foreach($fixture in $canonicalFixtures){$recordPath=Join-Path $temp ('canonical-ps51-'+$fixture.Name+'.json');Write-Utf8 $recordPath ($fixture.Record|ConvertTo-Json -Compress);$run=Invoke-PsHost $windowsPowerShellCanonical $canonicalWrapper @('-Module',(Join-Path $candidateRoot 'scripts\ProcessRequirementComposition.psm1'),'-RecordPath',$recordPath);if($run.Code-ne0-or[string]$run.Output[-1]-cne$fixture.Expected){Write-Output ('DIAG|canonical-identity-powershell51-'+$fixture.Name+'|code='+$run.Code+'|'+$run.Text)};Assert-True ($run.Code-eq0-and[string]$run.Output[-1]-ceq$fixture.Expected) ('canonical-identity-powershell51-'+$fixture.Name)}
    }else{Write-Output 'EVIDENCE_CEILING|POWERSHELL51_CANONICAL_RUNTIME_NOT_AVAILABLE'}

    $liveUpgradePath=Join-Path $liveRepositoryRoot 'scripts\upgrade-project.ps1'
    $liveUpgradeText=Get-Content -LiteralPath $liveUpgradePath -Raw -Encoding utf8
    $runtimeVersionListOffset=$liveUpgradeText.IndexOf("`$powershell7Versions=@('1.12.0','1.13.0','1.14.0','1.14.1','1.15.0','1.15.1','1.16.0')",[StringComparison]::Ordinal)
    $runtimeGuardOffset=$liveUpgradeText.IndexOf("if(`$ToVersion-in`$powershell7Versions-and(`$PSVersionTable.PSEdition-cne'Core'",[StringComparison]::Ordinal)
    $maintenanceModuleOffset=$liveUpgradeText.IndexOf("`$maintenanceModulePath=Join-Path `$PSScriptRoot 'MaintenanceOverlay.psm1'",[StringComparison]::Ordinal)
    $runtimeGuardProfileOffset=$liveUpgradeText.IndexOf("if(`$null-ne`$script:ActiveAdoptionProfile-and(`$PSVersionTable.PSEdition-cne'Core'",[StringComparison]::Ordinal)
    $transactionRuntimeOffset=$liveUpgradeText.LastIndexOf("`$transactionRoot = Join-Path `$projectRoot '.framework-upgrade-transaction'",[StringComparison]::Ordinal)
    Assert-True ($runtimeVersionListOffset-ge0-and$runtimeGuardOffset-gt$runtimeVersionListOffset-and$maintenanceModuleOffset-gt$runtimeGuardOffset-and$runtimeGuardProfileOffset-ge0-and$transactionRuntimeOffset-gt$runtimeGuardProfileOffset) 'upgrade-powershell7-guard-precedes-transaction-recovery'

    if (-not $SkipRootMigration) {
        $rootFlow = Join-Path $temp 'root-flow-workspace'
        New-Item -ItemType Directory -Path (Join-Path $rootFlow 'scripts'),(Join-Path $rootFlow 'framework\versions') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $liveRepositoryRoot 'scripts\register-project.ps1') -Destination (Join-Path $rootFlow 'scripts\register-project.ps1')
        Copy-Item -LiteralPath (Join-Path $liveRepositoryRoot 'scripts\upgrade-project.ps1') -Destination (Join-Path $rootFlow 'scripts\upgrade-project.ps1')
        Copy-Item -LiteralPath (Join-Path $liveRepositoryRoot 'scripts\MaintenanceOverlay.psm1') -Destination (Join-Path $rootFlow 'scripts\MaintenanceOverlay.psm1')
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'maintenance-overlay') -Destination (Join-Path $rootFlow 'framework\maintenance-overlay') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.7.0') -Destination (Join-Path $rootFlow 'framework\versions\1.7.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.8.0') -Destination (Join-Path $rootFlow 'framework\versions\1.8.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.9.0') -Destination (Join-Path $rootFlow 'framework\versions\1.9.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.10.0') -Destination (Join-Path $rootFlow 'framework\versions\1.10.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.11.0') -Destination (Join-Path $rootFlow 'framework\versions\1.11.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.12.0') -Destination (Join-Path $rootFlow 'framework\versions\1.12.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.13.0') -Destination (Join-Path $rootFlow 'framework\versions\1.13.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.14.0') -Destination (Join-Path $rootFlow 'framework\versions\1.14.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.14.1') -Destination (Join-Path $rootFlow 'framework\versions\1.14.1') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.15.0') -Destination (Join-Path $rootFlow 'framework\versions\1.15.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $liveFrameworkRoot 'versions\1.15.1') -Destination (Join-Path $rootFlow 'framework\versions\1.15.1') -Recurse
        Copy-Item -LiteralPath $candidateRoot -Destination (Join-Path $rootFlow 'framework\versions\1.16.0') -Recurse
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $rootFlow 'framework\CURRENT'))) 'root-global-version-selector-absent'

        if($IsWindows){
            $windowsPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $runtimeGuardRepo=Join-Path $rootFlow 'runtime-guard-fixture'
            $runtimeGuardTransaction=Join-Path $runtimeGuardRepo '.ai-workspace\.framework-upgrade-transaction'
            $runtimeGuardMarker=Join-Path $runtimeGuardTransaction 'marker.txt'
            Write-Utf8 $runtimeGuardMarker 'must remain exact'
            $runtimeGuardBefore=Get-Identity $runtimeGuardMarker
            $runtimeGuardFilesBefore=@(Get-ChildItem -LiteralPath $runtimeGuardRepo -Recurse -Force -File).Count
            $runtimeGuardOutput=@(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $rootFlow 'scripts\upgrade-project.ps1') -ProjectId 'runtime-guard-fixture' -ToVersion '1.16.0' -RepositoryPath $runtimeGuardRepo -Apply 2>&1|ForEach-Object{[string]$_})
            $runtimeGuardRun=[pscustomobject]@{Code=$LASTEXITCODE;Text=($runtimeGuardOutput-join"`n")}
            $runtimeGuardFilesAfter=@(Get-ChildItem -LiteralPath $runtimeGuardRepo -Recurse -Force -File).Count
            if($runtimeGuardRun.Code-eq0-or-not$runtimeGuardRun.Text.Contains('FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE')-or(Get-Identity $runtimeGuardMarker)-cne$runtimeGuardBefore-or$runtimeGuardFilesAfter-ne$runtimeGuardFilesBefore){Write-Output ('DIAG|upgrade-windows-powershell5-runtime-guard|code='+$runtimeGuardRun.Code+'|before='+$runtimeGuardBefore+'|after='+(Get-Identity $runtimeGuardMarker)+'|filesBefore='+$runtimeGuardFilesBefore+'|filesAfter='+$runtimeGuardFilesAfter+'|output='+$runtimeGuardRun.Text)}
            Assert-True ($runtimeGuardRun.Code-ne0-and$runtimeGuardRun.Text.Contains('FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE')-and(Get-Identity $runtimeGuardMarker)-ceq$runtimeGuardBefore-and$runtimeGuardFilesAfter-eq$runtimeGuardFilesBefore) 'upgrade-windows-powershell5-runtime-guard-zero-write-before-recovery'
        }else{
            Write-Output 'EVIDENCE_CEILING|WINDOWS_POWERSHELL5_DIRECT_GUARD_NOT_AVAILABLE'
            Assert-True $true 'upgrade-windows-powershell5-runtime-guard-evidence-ceiling-recorded'
        }

        $fixtureManifestPath=Join-Path $rootFlow 'framework\versions\1.16.0\RELEASE_MANIFEST.json'
        $fixtureVersionPath=Join-Path $rootFlow 'framework\versions\1.16.0\VERSION.json';$fixtureVersion=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureVersionPath|ConvertFrom-Json;$fixtureVersion.lifecycle='STABLE';$fixtureVersion.consumable=$true;$fixtureVersion.projectPinEligible=$true;Write-Utf8 $fixtureVersionPath ($fixtureVersion|ConvertTo-Json -Depth 20)
        $fixtureLoadPath=Join-Path $rootFlow 'framework\versions\1.16.0\LOAD_MANIFEST.json';$fixtureLoad=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureLoadPath|ConvertFrom-Json;$fixtureLoad.lifecycle='STABLE';Write-Utf8 $fixtureLoadPath ($fixtureLoad|ConvertTo-Json -Depth 20)
        $fixtureManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureManifestPath|ConvertFrom-Json
        $fixtureManifest.lifecycle='STABLE'
        $fixtureManifest.sourceReview='PENDING';$fixtureManifest.releaseIntegration='PENDING'
        Write-Utf8 $fixtureManifestPath ($fixtureManifest|ConvertTo-Json -Depth 20)

        $register = Join-Path $rootFlow 'scripts\register-project.ps1'
        $consumer = Join-Path $rootFlow 'consumer-explicit'
        New-GitRepo $consumer
        $consumerAgentsPrefix="# Project-owned instructions remain authoritative outside managed blocks.`n`nProject-owned blank-line grouping stays exact.`n`n";Write-Utf8 (Join-Path $consumer 'AGENTS.md') $consumerAgentsPrefix
        $baseRegisterArgs=@('-ProjectId','explicit-fixture','-DisplayName','Explicit Fixture','-RepositoryPath',$consumer,'-ControllerId','controller-explicit')
        $missingVersion=Invoke-Ps $register $baseRegisterArgs
        Assert-True ($missingVersion.Code -ne 0 -and $missingVersion.Text.Contains('FrameworkVersion')) 'register-missing-explicit-version-rejected'
        $pendingRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0'))
        Assert-True ($pendingRegister.Code -ne 0 -and $pendingRegister.Text.Contains('FRAMEWORK_RELEASE_NOT_SEALED|1.16.0')) 'register-pending-release-rejected-before-project-write'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $consumer '.ai-workspace'))) 'register-pending-release-zero-project-write'

        $fixtureVersionRoot=Split-Path -Parent $fixtureManifestPath
        $fixtureFacts=Seal-ReleaseFixture $fixtureVersionRoot 'TEST_FIXTURE_SEALED'
        $fixturePayload=$fixtureFacts.Files;$fixtureTotal=$fixtureFacts.TotalBytes;$fixtureCanonical=$fixtureFacts.Canonical
        $fixtureCoveragePath=Join-Path $fixtureVersionRoot 'CORRECTION_COVERAGE.json'
        $fixtureManifestCheck=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureManifestPath|ConvertFrom-Json
        if([int]$fixtureManifestCheck.fileCount-ne$fixturePayload.Count-or[int64]$fixtureManifestCheck.totalBytes-ne$fixtureTotal-or[string]$fixtureManifestCheck.canonical-cne$fixtureCanonical){Write-Output ('DIAG|root-flow-manifest|actual='+$fixturePayload.Count+'|'+$fixtureTotal+'|'+$fixtureCanonical+'|declared='+$fixtureManifestCheck.fileCount+'|'+$fixtureManifestCheck.totalBytes+'|'+$fixtureManifestCheck.canonical)}

        $patchSourceRepo=Join-Path $rootFlow 'consumer-1.14.0-patch-source';New-GitRepo $patchSourceRepo
        $patchSourceRegister=Invoke-Ps $register @('-ProjectId','patch-source-fixture','-DisplayName','Patch Source Fixture','-RepositoryPath',$patchSourceRepo,'-ControllerId','controller-patch-source','-FrameworkVersion','1.14.0','-Apply')
        $patchUpgrade=Join-Path $rootFlow 'scripts\upgrade-project.ps1'
        $patchPolicyPath=Join-Path $patchSourceRepo '.ai-workspace\process-policy.json';$patchCorrectionsPath=Join-Path $patchSourceRepo '.ai-workspace\corrections.json';$patchPolicyBefore=Get-Identity $patchPolicyPath;$patchCorrectionsBefore=Get-Identity $patchCorrectionsPath
        $patchSourceUpgrade=Invoke-Ps $patchUpgrade @('-ProjectId','patch-source-fixture','-ToVersion','1.14.1','-RepositoryPath',$patchSourceRepo,'-ControllerId','controller-patch-source')
        $patchSourceApply=Invoke-Ps $patchUpgrade @('-ProjectId','patch-source-fixture','-ToVersion','1.14.1','-RepositoryPath',$patchSourceRepo,'-ControllerId','controller-patch-source','-Apply');$patchConfig=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $patchSourceRepo '.ai-workspace\project.json')|ConvertFrom-Json
        Assert-True ($patchSourceRegister.Code-eq0-and$patchSourceUpgrade.Code-eq0-and$patchSourceUpgrade.Text.Contains('WHAT_IF|from=1.14.0|to=1.14.1|objects=6')-and$patchSourceUpgrade.Text.Contains('conflicts=0')-and$patchSourceApply.Code-eq0-and[string]$patchConfig.frameworkVersion-ceq'1.14.1'-and(Get-Identity $patchPolicyPath)-ceq$patchPolicyBefore-and(Get-Identity $patchCorrectionsPath)-ceq$patchCorrectionsBefore) 'root-tools-preserve-1.14.0-registration-and-direct-patch-upgrade-process-carrier-bytes'

        $legacyPatchRepo=Join-Path $rootFlow 'consumer-1.14.0-empty-legacy-patch-source';New-GitRepo $legacyPatchRepo
        $legacyPatchRegister=Invoke-Ps $register @('-ProjectId','legacy-patch-source-fixture','-DisplayName','Legacy Patch Source Fixture','-RepositoryPath',$legacyPatchRepo,'-ControllerId','controller-legacy-patch-source','-FrameworkVersion','1.14.0','-Apply')
        $legacyPatchPolicyPath=Join-Path $legacyPatchRepo '.ai-workspace\process-policy.json';$legacyPatchCorrectionsPath=Join-Path $legacyPatchRepo '.ai-workspace\corrections.json';Write-Utf8 $legacyPatchCorrectionsPath (([ordered]@{schemaVersion=1;contractVersion='1.10.0';projectId='legacy-patch-source-fixture';corrections=@()})|ConvertTo-Json -Depth 20);$legacyPatchPolicyBefore=Get-Identity $legacyPatchPolicyPath;$legacyPatchCorrectionsBefore=Get-Identity $legacyPatchCorrectionsPath
        $legacyPatchPreview=Invoke-Ps $patchUpgrade @('-ProjectId','legacy-patch-source-fixture','-ToVersion','1.14.1','-RepositoryPath',$legacyPatchRepo,'-ControllerId','controller-legacy-patch-source')
        $legacyPatchApply=Invoke-Ps $patchUpgrade @('-ProjectId','legacy-patch-source-fixture','-ToVersion','1.14.1','-RepositoryPath',$legacyPatchRepo,'-ControllerId','controller-legacy-patch-source','-Apply');$legacyPatchConfig=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $legacyPatchRepo '.ai-workspace\project.json')|ConvertFrom-Json
        Assert-True ($legacyPatchRegister.Code-eq0-and$legacyPatchPreview.Code-eq0-and$legacyPatchPreview.Text.Contains('WHAT_IF|from=1.14.0|to=1.14.1|objects=6')-and$legacyPatchApply.Code-eq0-and[string]$legacyPatchConfig.frameworkVersion-ceq'1.14.1'-and(Get-Identity $legacyPatchPolicyPath)-ceq$legacyPatchPolicyBefore-and(Get-Identity $legacyPatchCorrectionsPath)-ceq$legacyPatchCorrectionsBefore) 'direct-patch-preserves-empty-schema1-corrections-and-policy-bytes'

        $missingControllerRepo=Join-Path $rootFlow 'consumer-missing-controller'
        New-GitRepo $missingControllerRepo
        $missingControllerRegister=Invoke-Ps $register @('-ProjectId','missing-controller-fixture','-DisplayName','Missing Controller Fixture','-RepositoryPath',$missingControllerRepo,'-FrameworkVersion','1.16.0')
        Assert-True ($missingControllerRegister.Code-ne0-and$missingControllerRegister.Text.Contains('ControllerId')-and-not(Test-Path -LiteralPath (Join-Path $missingControllerRepo '.ai-workspace'))) 'register-1.14-requires-controller-id-before-project-write'

        $fixtureToolchainPath=Join-Path $fixtureVersionRoot 'TOOLCHAIN.json';$fixtureToolchainOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureToolchainPath
        $unsupportedToolchain=$fixtureToolchainOriginal|ConvertFrom-Json;$unsupportedToolchain.officialBackends[0].platforms=@('linux');Write-Utf8 $fixtureToolchainPath ($unsupportedToolchain|ConvertTo-Json -Depth 20);$null=Seal-ReleaseFixture $fixtureVersionRoot 'UNSUPPORTED_PLATFORM_TEST_FIXTURE'
        $unsupportedRegisterRepo=Join-Path $rootFlow 'consumer-unsupported-platform';New-GitRepo $unsupportedRegisterRepo
        $unsupportedRegister=Invoke-Ps $register @('-ProjectId','unsupported-platform-fixture','-DisplayName','Unsupported Platform Fixture','-RepositoryPath',$unsupportedRegisterRepo,'-ControllerId','controller-unsupported','-FrameworkVersion','1.16.0','-Apply')
        if(-not($unsupportedRegister.Code-ne0-and$unsupportedRegister.Text.Contains('FRAMEWORK_TOOL_PLATFORM_UNSUPPORTED|backend=powershell7|platform=windows')-and-not(Test-Path -LiteralPath (Join-Path $unsupportedRegisterRepo '.ai-workspace')))){Write-Output ('DIAG|register-unsupported-platform|code='+$unsupportedRegister.Code+'|output='+$unsupportedRegister.Text)}
        Assert-True ($unsupportedRegister.Code-ne0-and$unsupportedRegister.Text.Contains('FRAMEWORK_TOOL_PLATFORM_UNSUPPORTED|backend=powershell7|platform=windows')-and-not(Test-Path -LiteralPath (Join-Path $unsupportedRegisterRepo '.ai-workspace'))) 'register-unsupported-declared-platform-zero-write'
        Write-Utf8 $fixtureToolchainPath $fixtureToolchainOriginal;$null=Seal-ReleaseFixture $fixtureVersionRoot 'TEST_FIXTURE_SEALED'

        foreach($agentsFormatCase in @(
            [pscustomobject]@{Name='crlf';Bytes=[Text.UTF8Encoding]::new($false).GetBytes("# CRLF project instructions`r`n")},
            [pscustomobject]@{Name='no-final-lf';Bytes=[Text.UTF8Encoding]::new($false).GetBytes('# no final LF project instructions')}
        )){
            $formatRepo=Join-Path $rootFlow ('consumer-agents-'+$agentsFormatCase.Name);New-GitRepo $formatRepo;$formatAgents=Join-Path $formatRepo 'AGENTS.md';[IO.File]::WriteAllBytes($formatAgents,$agentsFormatCase.Bytes);$formatIdentity=Get-Identity $formatAgents
            $formatRegister=Invoke-Ps $register @('-ProjectId',('agents-'+$agentsFormatCase.Name+'-fixture'),'-DisplayName','Agents Format Fixture','-RepositoryPath',$formatRepo,'-ControllerId','controller-agents-format','-FrameworkVersion','1.16.0','-Apply')
            Assert-True ($formatRegister.Code-ne0-and$formatRegister.Text.Contains('AGENTS_MANAGED_BLOCK_TEXT_FORMAT')-and(Get-Identity $formatAgents)-ceq$formatIdentity-and-not(Test-Path -LiteralPath (Join-Path $formatRepo '.ai-workspace'))) ('register-agents-'+$agentsFormatCase.Name+'-fails-before-project-write')
        }

        $skillCollisionRepo=Join-Path $rootFlow 'consumer-skill-collision';New-GitRepo $skillCollisionRepo
        $skillCollisionPath=Join-Path $skillCollisionRepo '.agents\skills\ai-workspace-router\SKILL.md';Write-Utf8 $skillCollisionPath 'project-owned colliding skill'
        $skillCollisionIdentity=Get-Identity $skillCollisionPath
        $skillCollisionRegister=Invoke-Ps $register @('-ProjectId','skill-collision-fixture','-DisplayName','Skill Collision Fixture','-RepositoryPath',$skillCollisionRepo,'-ControllerId','controller-skill-collision','-FrameworkVersion','1.14.0','-Apply')
        Assert-True ($skillCollisionRegister.Code-ne0-and$skillCollisionRegister.Text.Contains('ROUTER_SKILL_COLLISION')-and(Get-Identity $skillCollisionPath)-ceq$skillCollisionIdentity-and-not(Test-Path -LiteralPath (Join-Path $skillCollisionRepo '.ai-workspace'))-and-not(Test-Path -LiteralPath (Join-Path $skillCollisionRepo 'AGENTS.md'))) 'register-router-skill-collision-fails-before-project-write'

        $registerReparseRepo=Join-Path $rootFlow 'consumer-router-reparse';$registerReparseExternal=Join-Path $rootFlow 'external-register-agents';New-GitRepo $registerReparseRepo;New-Item -ItemType Directory -Path $registerReparseExternal -Force|Out-Null
        $registerReparseLink=Join-Path $registerReparseRepo '.agents';New-TestJunction $registerReparseLink $registerReparseExternal
        try{$registerReparseRun=Invoke-Ps $register @('-ProjectId','register-reparse-fixture','-DisplayName','Register Reparse Fixture','-RepositoryPath',$registerReparseRepo,'-ControllerId','controller-register-reparse','-FrameworkVersion','1.14.0','-Apply')}
        finally{Remove-TestJunction $registerReparseLink}
        Assert-True ($registerReparseRun.Code-ne0-and$registerReparseRun.Text.Contains('MANAGED_ROUTER_DESTINATION_REPARSE')-and-not(Test-Path -LiteralPath (Join-Path $registerReparseExternal 'skills\ai-workspace-router\SKILL.md'))-and-not(Test-Path -LiteralPath (Join-Path $registerReparseRepo '.ai-workspace'))) 'register-router-reparse-rejected-with-zero-external-write'

        $shadowRepo=Join-Path $rootFlow 'consumer-shadow-record'
        New-GitRepo $shadowRepo
        $shadowRecord=Join-Path $rootFlow 'projects\shadow-fixture\project.json'
        Write-Utf8 $shadowRecord (([ordered]@{id='shadow-fixture';repositoryPath=$shadowRepo})|ConvertTo-Json -Depth 5)
        $shadowIdentity=Get-Identity $shadowRecord
        $shadowRegisterArgs=@('-ProjectId','shadow-fixture','-DisplayName','Shadow Fixture','-RepositoryPath',$shadowRepo,'-ControllerId','controller-shadow','-FrameworkVersion','1.7.0','-Apply')
        $shadowRegister=Invoke-Ps $register $shadowRegisterArgs
        Assert-True ($shadowRegister.Code -eq 0 -and $shadowRegister.Text.Contains('CREATED') -and (Get-Identity $shadowRecord) -ceq $shadowIdentity) 'register-explicit-repository-ignores-framework-owned-consumer-record'
        $upgrade=Join-Path $rootFlow 'scripts\upgrade-project.ps1'
        $installReparseRepo=Join-Path $rootFlow 'consumer-upgrade-router-reparse';New-GitRepo $installReparseRepo
        $installReparseRegister=Invoke-Ps $register @('-ProjectId','upgrade-router-reparse-fixture','-DisplayName','Upgrade Router Reparse Fixture','-RepositoryPath',$installReparseRepo,'-ControllerId','controller-upgrade-reparse','-FrameworkVersion','1.11.0','-Apply')
        $installReparseConfig=Join-Path $installReparseRepo '.ai-workspace\project.json';$installReparseConfigIdentity=Get-Identity $installReparseConfig;$installReparseExternal=Join-Path $rootFlow 'external-upgrade-agents';New-Item -ItemType Directory -Path $installReparseExternal -Force|Out-Null
        $installReparseLink=Join-Path $installReparseRepo '.agents';New-TestJunction $installReparseLink $installReparseExternal
        try{$installReparseRun=Invoke-Ps $upgrade @('-ProjectId','upgrade-router-reparse-fixture','-ToVersion','1.14.0','-RepositoryPath',$installReparseRepo,'-ControllerId','controller-upgrade-reparse','-Apply')}
        finally{Remove-TestJunction $installReparseLink}
        Assert-True ($installReparseRegister.Code-eq0-and$installReparseRun.Code-ne0-and$installReparseRun.Text.Contains('MANAGED_ROUTER_DESTINATION_REPARSE')-and(Get-Identity $installReparseConfig)-ceq$installReparseConfigIdentity-and-not(Test-Path -LiteralPath (Join-Path $installReparseExternal 'skills\ai-workspace-router\SKILL.md'))-and-not(Test-Path -LiteralPath (Join-Path $installReparseRepo '.framework-1.14-upgrade-transaction'))) 'upgrade-install-router-reparse-rejected-with-zero-external-write'

        $downgradeReparseRepo=Join-Path $rootFlow 'consumer-downgrade-router-reparse';New-GitRepo $downgradeReparseRepo
        $downgradeReparseRegister=Invoke-Ps $register @('-ProjectId','downgrade-router-reparse-fixture','-DisplayName','Downgrade Router Reparse Fixture','-RepositoryPath',$downgradeReparseRepo,'-ControllerId','controller-downgrade-reparse','-FrameworkVersion','1.14.0','-Apply')
        $downgradeReparseConfig=Join-Path $downgradeReparseRepo '.ai-workspace\project.json';$downgradeReparseConfigIdentity=Get-Identity $downgradeReparseConfig;$downgradeReparseExternal=Join-Path $rootFlow 'external-downgrade-agents';Copy-Item -LiteralPath (Join-Path $downgradeReparseRepo '.agents') -Destination $downgradeReparseExternal -Recurse
        Remove-Item -LiteralPath (Join-Path $downgradeReparseRepo '.agents') -Recurse -Force;$downgradeReparseLink=Join-Path $downgradeReparseRepo '.agents';New-TestJunction $downgradeReparseLink $downgradeReparseExternal;$downgradeExternalSkill=Join-Path $downgradeReparseExternal 'skills\ai-workspace-router\SKILL.md';$downgradeExternalIdentity=Get-Identity $downgradeExternalSkill
        try{$downgradeReparseRun=Invoke-Ps $upgrade @('-ProjectId','downgrade-router-reparse-fixture','-ToVersion','1.13.0','-RepositoryPath',$downgradeReparseRepo,'-ControllerId','controller-downgrade-reparse','-Apply')}
        finally{Remove-TestJunction $downgradeReparseLink}
        Assert-True ($downgradeReparseRegister.Code-eq0-and$downgradeReparseRun.Code-ne0-and$downgradeReparseRun.Text.Contains('MANAGED_ROUTER_DESTINATION_REPARSE')-and(Get-Identity $downgradeReparseConfig)-ceq$downgradeReparseConfigIdentity-and(Get-Identity $downgradeExternalSkill)-ceq$downgradeExternalIdentity-and-not(Test-Path -LiteralPath (Join-Path $downgradeReparseRepo '.framework-1.14-upgrade-transaction'))) 'downgrade-router-reparse-rejected-with-zero-external-delete'
        $shadowControlIdentity=Get-Identity (Join-Path $shadowRepo '.ai-workspace\project.json')
        $shadowUpgradeWithoutRepository=Invoke-Ps $upgrade @('-ProjectId','shadow-fixture','-ToVersion','1.16.0','-ControllerId','controller-shadow')
        Assert-True ($shadowUpgradeWithoutRepository.Code -ne 0 -and $shadowUpgradeWithoutRepository.Text.Contains('RepositoryPath') -and (Get-Identity (Join-Path $shadowRepo '.ai-workspace\project.json')) -ceq $shadowControlIdentity -and (Get-Identity $shadowRecord) -ceq $shadowIdentity) 'upgrade-missing-repository-rejected-even-when-framework-owned-record-exists'

        $duplicateRegisterRepo=Join-Path $rootFlow 'consumer-registration-runtime-ignore-duplicate';New-GitRepo $duplicateRegisterRepo;$duplicateRegisterGitIgnorePath=Join-Path $duplicateRegisterRepo '.gitignore';Write-Utf8 $duplicateRegisterGitIgnorePath "/.ai-workspace/runtime/`n.ai-workspace/runtime`n";$duplicateRegisterGitIgnoreIdentity=Get-Identity $duplicateRegisterGitIgnorePath
        $duplicateRegisterRun=Invoke-Ps $register @('-ProjectId','registration-runtime-ignore-duplicate-fixture','-DisplayName','Registration Runtime Ignore Duplicate Fixture','-RepositoryPath',$duplicateRegisterRepo,'-ControllerId','controller-registration-runtime-ignore-duplicate','-FrameworkVersion','1.16.0','-Apply')
        Assert-True ($duplicateRegisterRun.Code-ne0-and$duplicateRegisterRun.Text.Contains('RUNTIME_GITIGNORE_DUPLICATE_CONFLICT')-and(Get-Identity $duplicateRegisterGitIgnorePath)-ceq$duplicateRegisterGitIgnoreIdentity-and-not(Test-Path -LiteralPath (Join-Path $duplicateRegisterRepo '.ai-workspace'))) 'register-runtime-gitignore-duplicate-conflict-preserves-bytes'

        $previewRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0'))
        if ($previewRegister.Code -ne 0 -or -not $previewRegister.Text.Contains('WHAT_IF')) { Write-Output ('DIAG|register-explicit-1.16.0-preview|' + $previewRegister.Code + '|' + $previewRegister.Text) }
        $registrationWriteSet=@('AGENTS.md','.gitignore','.ai-workspace/.gitattributes','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/PROJECT.md','.ai-workspace/REVIEW_PROFILE.md','.ai-workspace/RELATIONSHIPS.md','.ai-workspace/STATUS.md','.ai-workspace/tasks/README.md','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json')
        $expectedRegistrationWriteSet='REGISTRATION_WRITESET|'+[string]::Join('|',$registrationWriteSet)
        $previewLocator=[regex]::Match($previewRegister.Text,'REGISTRATION_LOCATORS\|preparation=(?<preparation>[^|\r\n]+)\|transaction=(?<transaction>[^|\r\n]+)\|recovery=(?<recovery>[^\r\n]+)')
        Assert-True ($previewRegister.Code -eq 0 -and $previewRegister.Text.Contains('WHAT_IF')-and$previewLocator.Success-and$previewRegister.Text.Contains($expectedRegistrationWriteSet)-and-not$previewRegister.Text.Contains('.ai-workspace-init.')-and-not$previewLocator.Groups['preparation'].Value.StartsWith(($consumer+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)-and$previewLocator.Groups['transaction'].Value-ceq(Join-Path $consumer '.framework-registration-transaction')) 'register-explicit-1.16.0-preview-binds-deterministic-locators-and-exact-write-set'

        $registrationStartCollisionRepo=Join-Path $rootFlow 'consumer-registration-start-collision';New-GitRepo $registrationStartCollisionRepo
        $registrationStartCollisionAgents=Join-Path $registrationStartCollisionRepo 'AGENTS.md';Write-Utf8 $registrationStartCollisionAgents '# unchanged project instructions'
        $registrationStartCollisionArgs=@('-ProjectId','registration-start-collision-fixture','-DisplayName','Registration Start Collision Fixture','-RepositoryPath',$registrationStartCollisionRepo,'-ControllerId','controller-registration-start-collision','-FrameworkVersion','1.16.0')
        $registrationStartCollisionPreview=Invoke-Ps $register $registrationStartCollisionArgs;$registrationStartCollisionLocator=[regex]::Match($registrationStartCollisionPreview.Text,'REGISTRATION_LOCATORS\|preparation=(?<preparation>[^|\r\n]+)\|transaction=(?<transaction>[^|\r\n]+)\|recovery=(?<recovery>[^\r\n]+)')
        New-Item -ItemType Directory -Path $registrationStartCollisionLocator.Groups['recovery'].Value -Force|Out-Null;$registrationStartCollisionMarker=Join-Path $registrationStartCollisionLocator.Groups['recovery'].Value 'project-owned.txt';Write-Utf8 $registrationStartCollisionMarker 'preexisting recovery name'
        $registrationStartAgentsBefore=Get-Identity $registrationStartCollisionAgents;$registrationStartMarkerBefore=Get-Identity $registrationStartCollisionMarker
        $registrationStartCollisionRun=Invoke-Ps $register @($registrationStartCollisionArgs+'-Apply')
        Assert-True ($registrationStartCollisionLocator.Success-and$registrationStartCollisionRun.Code-ne0-and$registrationStartCollisionRun.Text.Contains('REGISTRATION_TRANSACTION_RECOVERY_COLLISION')-and(Get-Identity $registrationStartCollisionAgents)-ceq$registrationStartAgentsBefore-and(Get-Identity $registrationStartCollisionMarker)-ceq$registrationStartMarkerBefore-and-not(Test-Path -LiteralPath (Join-Path $registrationStartCollisionRepo '.ai-workspace'))-and-not(Test-Path -LiteralPath $registrationStartCollisionLocator.Groups['transaction'].Value)-and-not(Test-Path -LiteralPath $registrationStartCollisionLocator.Groups['preparation'].Value)) 'register-start-recovery-collision-zero-project-or-preparation-write'

        $failureRepo=Join-Path $rootFlow 'consumer-registration-pretransaction-failure';New-GitRepo $failureRepo
        $failureArgs=@('-ProjectId','registration-failure-fixture','-DisplayName','Registration Failure Fixture','-RepositoryPath',$failureRepo,'-ControllerId','controller-registration-failure','-FrameworkVersion','1.16.0')
        $failurePreview=Invoke-Ps $register $failureArgs;$failureLocator=[regex]::Match($failurePreview.Text,'REGISTRATION_LOCATORS\|preparation=(?<preparation>[^|\r\n]+)\|transaction=(?<transaction>[^|\r\n]+)\|recovery=(?<recovery>[^\r\n]+)')
        $failureTemplatePath=Join-Path $fixtureVersionRoot 'project-starter\STATUS.md';$failureTemplateOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $failureTemplatePath
        Write-Utf8 $failureTemplatePath ($failureTemplateOriginal.TrimEnd("`n")+"`n{{UNRESOLVED_TEST_TOKEN}}`n");$null=Seal-ReleaseFixture $fixtureVersionRoot 'PRETRANSACTION_FAILURE_FIXTURE'
        $failureApply=Invoke-Ps $register @($failureArgs+'-Apply')
        Assert-True ($failureLocator.Success-and$failureApply.Code-ne0-and$failureApply.Text.Contains('Unresolved template token')-and(Test-Path -LiteralPath $failureLocator.Groups['preparation'].Value -PathType Container)-and-not(Test-Path -LiteralPath (Join-Path $failureRepo '.framework-registration-transaction'))-and-not(Test-Path -LiteralPath (Join-Path $failureRepo '.ai-workspace'))-and-not(Test-Path -LiteralPath (Join-Path $failureRepo 'AGENTS.md'))) 'register-pretransaction-render-failure-writes-only-deterministic-outside-repository-preparation'
        Remove-Item -LiteralPath $failureLocator.Groups['preparation'].Value -Recurse -Force
        Write-Utf8 $failureTemplatePath $failureTemplateOriginal;$null=Seal-ReleaseFixture $fixtureVersionRoot 'TEST_FIXTURE_SEALED'

        $applyRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        if($applyRegister.Code-ne0-or-not$applyRegister.Text.Contains('CREATED')){Write-Output ('DIAG|register-explicit-1.16.0-apply|code='+$applyRegister.Code+'|'+$applyRegister.Text)}
        Assert-True ($applyRegister.Code -eq 0 -and $applyRegister.Text.Contains('CREATED')) 'register-explicit-1.16.0-apply'
        $registrationRecovery=@(Get-ChildItem -LiteralPath $consumer -Directory -Force -Filter '.framework-registration-recovery-*')
        Assert-True ($registrationRecovery.Count-eq1-and[IO.Path]::GetFullPath($registrationRecovery[0].FullName)-ceq[IO.Path]::GetFullPath($previewLocator.Groups['recovery'].Value)) 'register-actual-recovery-locator-matches-deterministic-preview'
        $registrationActive=Join-Path $consumer '.framework-registration-transaction';[IO.Directory]::Move($registrationRecovery[0].FullName,$registrationActive)
        [IO.File]::Copy((Join-Path $registrationActive 'old\AGENTS.md'),(Join-Path $consumer 'AGENTS.md'),$true)
        $registrationCollisionState=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $registrationActive 'state.json')|ConvertFrom-Json;$registrationCollisionRelatives=@($registrationCollisionState.objects|ForEach-Object{[string]$_.relative});$registrationCollisionBefore=Get-ExactObjectRows $consumer $registrationCollisionRelatives
        New-Item -ItemType Directory -Path $previewLocator.Groups['recovery'].Value -Force|Out-Null;$registrationCollisionMarker=Join-Path $previewLocator.Groups['recovery'].Value 'project-owned.txt';Write-Utf8 $registrationCollisionMarker 'preexisting recovery name';$registrationCollisionMarkerBefore=Get-Identity $registrationCollisionMarker
        $registrationCollisionRun=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'));$registrationCollisionAfter=Get-ExactObjectRows $consumer $registrationCollisionRelatives
        Assert-True ($registrationCollisionRun.Code-ne0-and$registrationCollisionRun.Text.Contains('REGISTRATION_TRANSACTION_RECOVERY_COLLISION')-and[string]::Join("`n",$registrationCollisionAfter)-ceq[string]::Join("`n",$registrationCollisionBefore)-and(Get-Identity $registrationCollisionMarker)-ceq$registrationCollisionMarkerBefore-and(Test-Path -LiteralPath $registrationActive -PathType Container)) 'register-resume-recovery-collision-preserves-all-live-objects'
        Remove-Item -LiteralPath $previewLocator.Groups['recovery'].Value -Recurse -Force
        $registrationStatePath=Join-Path $registrationActive 'state.json';$registrationStateOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $registrationStatePath;$registrationPreflightIdentity=Get-Identity (Join-Path $consumer 'AGENTS.md')
        $registrationIdDrift=$registrationStateOriginal|ConvertFrom-Json;$registrationIdDrift.transactionId='0'*32;Write-Utf8 $registrationStatePath ($registrationIdDrift|ConvertTo-Json -Depth 20)
        $registrationIdDriftRun=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        Assert-True ($registrationIdDriftRun.Code-ne0-and$registrationIdDriftRun.Text.Contains('REGISTRATION_TRANSACTION_STATE_VALUES')-and(Get-Identity (Join-Path $consumer 'AGENTS.md'))-ceq$registrationPreflightIdentity-and-not(Test-Path -LiteralPath $previewLocator.Groups['recovery'].Value)) 'register-recovery-rejects-transaction-id-drift-before-write'
        Write-Utf8 $registrationStatePath $registrationStateOriginal
        $registrationPhysicalExtra=Join-Path $registrationActive 'new\undeclared.bin';Write-Utf8 $registrationPhysicalExtra 'undeclared transaction material'
        $registrationPhysicalExtraRun=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        Assert-True ($registrationPhysicalExtraRun.Code-ne0-and$registrationPhysicalExtraRun.Text.Contains('REGISTRATION_TRANSACTION_TREE_CLOSURE')-and(Get-Identity (Join-Path $consumer 'AGENTS.md'))-ceq$registrationPreflightIdentity-and(Test-Path -LiteralPath $registrationPhysicalExtra)) 'register-recovery-rejects-undeclared-physical-material-before-write'
        Remove-Item -LiteralPath $registrationPhysicalExtra -Force
        $registrationTraversal=$registrationStateOriginal|ConvertFrom-Json;$registrationTraversal.objects[0].relative='../outside.txt';Write-Utf8 $registrationStatePath ($registrationTraversal|ConvertTo-Json -Depth 20)
        $registrationTraversalRun=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        Assert-True ($registrationTraversalRun.Code-ne0-and$registrationTraversalRun.Text.Contains('REGISTRATION_TRANSACTION_OBJECT_PATH')-and(Get-Identity (Join-Path $consumer 'AGENTS.md'))-ceq$registrationPreflightIdentity) 'register-recovery-rejects-traversal-state-before-write'
        Write-Utf8 $registrationStatePath $registrationStateOriginal;$registrationExtra=$registrationStateOriginal|ConvertFrom-Json;$registrationExtra.objects=@($registrationExtra.objects)+@([ordered]@{relative='.ai-workspace/extra.json';oldIdentity='MISSING';newIdentity='1|'+('A'*64)});Write-Utf8 $registrationStatePath ($registrationExtra|ConvertTo-Json -Depth 20)
        $registrationExtraRun=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        Assert-True ($registrationExtraRun.Code-ne0-and$registrationExtraRun.Text.Contains('REGISTRATION_TRANSACTION_OBJECT_SET')-and(Get-Identity (Join-Path $consumer 'AGENTS.md'))-ceq$registrationPreflightIdentity) 'register-recovery-rejects-extra-state-object-before-write'
        Write-Utf8 $registrationStatePath $registrationStateOriginal
        New-Item -ItemType Directory -Path $previewLocator.Groups['preparation'].Value -Force|Out-Null
        $registrationResume=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        Assert-True ($registrationRecovery.Count-eq1-and$registrationResume.Code-eq0-and$registrationResume.Text.Contains('RECOVERED_CREATED')-and-not(Test-Path -LiteralPath $registrationActive)-and-not(Test-Path -LiteralPath $previewLocator.Groups['preparation'].Value)) 'register-1.14-mixed-transaction-resumes-forward-and-reconciles-empty-preparation'
        $registrationRecovery=@(Get-ChildItem -LiteralPath $consumer -Directory -Force -Filter '.framework-registration-recovery-*');[IO.Directory]::Move($registrationRecovery[0].FullName,$registrationActive)
        $registrationUnknownPath=Join-Path $consumer '.ai-workspace\STATUS.md';Write-Utf8 $registrationUnknownPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $registrationUnknownPath).TrimEnd("`n")+"`nunknown transaction drift`n");$registrationUnknownIdentity=Get-Identity $registrationUnknownPath
        $registrationUnknown=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        Assert-True ($registrationUnknown.Code-ne0-and$registrationUnknown.Text.Contains('REGISTRATION_TRANSACTION_UNKNOWN_LIVE_BYTES|.ai-workspace/STATUS.md')-and(Get-Identity $registrationUnknownPath)-ceq$registrationUnknownIdentity-and(Test-Path -LiteralPath $registrationActive)) 'register-1.14-unknown-live-bytes-stop-without-overwrite'
        [IO.File]::Copy((Join-Path $registrationActive 'new\.ai-workspace\STATUS.md'),$registrationUnknownPath,$true);$registrationCleanup=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0','-Apply'))
        Assert-True ($registrationCleanup.Code-eq0-and$registrationCleanup.Text.Contains('RECOVERED_CREATED')) 'register-1.14-known-new-transaction-finalizes-after-manual-rebind'
        $registeredConfigPath=Join-Path $consumer '.ai-workspace\project.json'
        $registeredConfigOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $registeredConfigPath
        $registeredConfigBeforeMissingController=Get-Identity $registeredConfigPath
        $existingMissingController=Invoke-Ps $register @('-ProjectId','explicit-fixture','-DisplayName','Explicit Fixture','-RepositoryPath',$consumer,'-FrameworkVersion','1.16.0')
        Assert-True ($existingMissingController.Code-ne0-and$existingMissingController.Text.Contains('ControllerId')-and(Get-Identity $registeredConfigPath)-ceq$registeredConfigBeforeMissingController) 'register-existing-1.14-requires-controller-id-zero-write'
        $repeatRegister=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0'))
        Assert-True ($repeatRegister.Code -eq 0 -and $repeatRegister.Text.Contains('ALREADY_REGISTERED')) 'register-explicit-1.16.0-repeat'
        $registeredCapabilityConfig=$registeredConfigOriginal|ConvertFrom-Json;$registeredCapabilityConfig.frameworkCapabilities=[pscustomobject][ordered]@{KNOWLEDGE_REFERENCE=[pscustomobject][ordered]@{enabled=$true;indexLocator='knowledge/index.json'}};Write-Utf8 $registeredConfigPath ($registeredCapabilityConfig|ConvertTo-Json -Depth 20);$registeredKnowledgeRepeat=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0'))
        $registeredCapabilityConfig.frameworkCapabilities=[pscustomobject][ordered]@{UNKNOWN=[pscustomobject][ordered]@{enabled=$false}};Write-Utf8 $registeredConfigPath ($registeredCapabilityConfig|ConvertTo-Json -Depth 20);$registeredUnknownRepeat=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0'))
        $registeredCapabilityConfig.frameworkCapabilities=[pscustomobject][ordered]@{};Write-Utf8 $registeredConfigPath ($registeredCapabilityConfig|ConvertTo-Json -Depth 20);$registeredEmptyRepeat=Invoke-Ps $register @($baseRegisterArgs + @('-FrameworkVersion','1.16.0'));Write-Utf8 $registeredConfigPath $registeredConfigOriginal
        Assert-True ($registeredKnowledgeRepeat.Code-eq0-and$registeredKnowledgeRepeat.Text.Contains('ALREADY_REGISTERED')-and$registeredUnknownRepeat.Code-ne0-and$registeredUnknownRepeat.Text.Contains('FRAMEWORK_CAPABILITIES_UNKNOWN_OR_DUPLICATE')-and$registeredEmptyRepeat.Code-eq0-and$registeredEmptyRepeat.Text.Contains('ALREADY_REGISTERED')-and(Get-Identity $registeredConfigPath)-ceq$registeredConfigBeforeMissingController) 'register-target-capability-contract-accepts-empty-and-knowledge-rejects-unknown'
        $registeredConfig=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.ai-workspace\project.json')|ConvertFrom-Json
        $registeredBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.ai-workspace\BOOTSTRAP.md')
        $registeredFiles=@(Get-ChildItem -LiteralPath (Join-Path $consumer '.ai-workspace') -Recurse -File -Force)
        $registeredCorrections=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.ai-workspace\corrections.json')|ConvertFrom-Json
        $registeredPolicy=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.ai-workspace\process-policy.json')|ConvertFrom-Json
        $registeredAgents=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer 'AGENTS.md')
        $registeredGitIgnore=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $consumer '.gitignore')
        Assert-True ([string]$registeredConfig.frameworkVersion -ceq '1.16.0' -and [int]$registeredConfig.schemaVersion-eq4 -and [string]$registeredConfig.frameworkToolBackend -ceq 'powershell7' -and [string]$registeredConfig.processPolicy.locator-ceq'.ai-workspace/process-policy.json' -and $registeredFiles.Count -eq 11 -and $registeredBootstrap.Contains('要求 schema4') -and-not$registeredBootstrap.Contains('要求 schema3') -and $registeredBootstrap.Contains('TOOLCHAIN.json') -and $registeredBootstrap.Contains('PROJECT-CORRECTIONS:BEGIN') -and [int]$registeredCorrections.schemaVersion-eq2 -and [string]$registeredCorrections.projectId -ceq 'explicit-fixture' -and [string]$registeredCorrections.contractVersion -ceq'1.16.0' -and @($registeredCorrections.corrections).Count -eq 0 -and[string]$registeredPolicy.projectId-ceq'explicit-fixture'-and[string]$registeredPolicy.contractVersion-ceq'1.16.0'-and[int]$registeredPolicy.selectedRulePackBytes-eq32768-and@($registeredPolicy.rules).Count-eq0-and([regex]::Matches($registeredGitIgnore,'(?m)^/\.ai-workspace/runtime/$')).Count-eq1-and$registeredAgents.StartsWith($consumerAgentsPrefix)-and$registeredAgents.Contains('AI-WORKSPACE-FRAMEWORK:BEGIN')-and-not(Test-Path -LiteralPath (Join-Path $consumer '.agents\skills\ai-workspace-router\SKILL.md'))) 'register-materializes-1.16-starter-project-budget-runtime-ignore-corrections-and-preserves-project-bytes'

        $upgrade=Join-Path $rootFlow 'scripts\upgrade-project.ps1'
        $source112Repo=Join-Path $rootFlow 'consumer-source-1.12';New-GitRepo $source112Repo
        $source112Register=Invoke-Ps $register @('-ProjectId','source-112-fixture','-DisplayName','Source 1.12 Fixture','-RepositoryPath',$source112Repo,'-ControllerId','controller-source-112','-FrameworkVersion','1.12.0','-Apply')
        $source112Upgrade=Invoke-Ps $upgrade @('-ProjectId','source-112-fixture','-ToVersion','1.14.0','-RepositoryPath',$source112Repo,'-ControllerId','controller-source-112','-Apply')
        $source112Projected=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $source112Repo '.ai-workspace\project.json')|ConvertFrom-Json
        Assert-True ($source112Register.Code-eq0-and$source112Upgrade.Code-eq0-and[int]$source112Projected.schemaVersion-eq4-and[string]$source112Projected.frameworkVersion-ceq'1.14.0'-and[string]$source112Projected.processPolicy.locator-ceq'.ai-workspace/process-policy.json') 'upgrade-healthy-1.12-schema3-to-1.14'

        $source113Schema3Repo=Join-Path $rootFlow 'consumer-source-1.13-schema3';New-GitRepo $source113Schema3Repo
        $source113Schema3Register=Invoke-Ps $register @('-ProjectId','source-113-schema3-fixture','-DisplayName','Source 1.13 Schema3 Fixture','-RepositoryPath',$source113Schema3Repo,'-ControllerId','controller-source-113-schema3','-FrameworkVersion','1.12.0','-Apply')
        $source113Schema3Projection=Invoke-Ps $upgrade @('-ProjectId','source-113-schema3-fixture','-ToVersion','1.13.0','-RepositoryPath',$source113Schema3Repo,'-ControllerId','controller-source-113-schema3','-Apply')
        $source113Schema3Pre=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $source113Schema3Repo '.ai-workspace\project.json')|ConvertFrom-Json
        $source113Schema3Upgrade=Invoke-Ps $upgrade @('-ProjectId','source-113-schema3-fixture','-ToVersion','1.14.0','-RepositoryPath',$source113Schema3Repo,'-ControllerId','controller-source-113-schema3','-Apply')
        $source113Schema3Post=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $source113Schema3Repo '.ai-workspace\project.json')|ConvertFrom-Json
        Assert-True ($source113Schema3Register.Code-eq0-and$source113Schema3Projection.Code-eq0-and[int]$source113Schema3Pre.schemaVersion-eq3-and$null-eq$source113Schema3Pre.PSObject.Properties['processPolicy']-and$source113Schema3Upgrade.Code-eq0-and[int]$source113Schema3Post.schemaVersion-eq4-and[string]$source113Schema3Post.frameworkVersion-ceq'1.14.0'-and[string]$source113Schema3Post.processPolicy.locator-ceq'.ai-workspace/process-policy.json') 'upgrade-healthy-1.13-schema3-to-1.14'

        $source113Schema4Repo=Join-Path $rootFlow 'consumer-source-1.13-schema4';New-GitRepo $source113Schema4Repo
        $source113Schema4Register=Invoke-Ps $register @('-ProjectId','source-113-schema4-fixture','-DisplayName','Source 1.13 Schema4 Fixture','-RepositoryPath',$source113Schema4Repo,'-ControllerId','controller-source-113-schema4','-FrameworkVersion','1.13.0','-Apply')
        $source113Schema4Pre=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $source113Schema4Repo '.ai-workspace\project.json')|ConvertFrom-Json
        $source113Schema4Upgrade=Invoke-Ps $upgrade @('-ProjectId','source-113-schema4-fixture','-ToVersion','1.14.0','-RepositoryPath',$source113Schema4Repo,'-ControllerId','controller-source-113-schema4','-Apply')
        $source113Schema4Post=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $source113Schema4Repo '.ai-workspace\project.json')|ConvertFrom-Json
        Assert-True ($source113Schema4Register.Code-eq0-and[int]$source113Schema4Pre.schemaVersion-eq4-and[string]$source113Schema4Pre.processPolicy.locator-ceq'.ai-workspace/process-policy.json'-and$source113Schema4Upgrade.Code-eq0-and[int]$source113Schema4Post.schemaVersion-eq4-and[string]$source113Schema4Post.frameworkVersion-ceq'1.14.0') 'upgrade-healthy-1.13-schema4-to-1.14'

        foreach($upgradeAgentsFormatCase in @(
            [pscustomobject]@{Name='crlf';Bytes=[Text.UTF8Encoding]::new($false).GetBytes("# CRLF upgrade instructions`r`n")},
            [pscustomobject]@{Name='no-final-lf';Bytes=[Text.UTF8Encoding]::new($false).GetBytes('# no final LF upgrade instructions')}
        )){
            $upgradeFormatRepo=Join-Path $rootFlow ('consumer-upgrade-agents-'+$upgradeAgentsFormatCase.Name);New-GitRepo $upgradeFormatRepo;Write-Utf8 (Join-Path $upgradeFormatRepo 'AGENTS.md') '# initial project instructions'
            $upgradeFormatRegister=Invoke-Ps $register @('-ProjectId',('upgrade-agents-'+$upgradeAgentsFormatCase.Name+'-fixture'),'-DisplayName','Upgrade Agents Fixture','-RepositoryPath',$upgradeFormatRepo,'-ControllerId','controller-upgrade-agents','-FrameworkVersion','1.11.0','-Apply')
            $upgradeFormatAgents=Join-Path $upgradeFormatRepo 'AGENTS.md';[IO.File]::WriteAllBytes($upgradeFormatAgents,$upgradeAgentsFormatCase.Bytes);$upgradeFormatIdentity=Get-Identity $upgradeFormatAgents;$upgradeFormatConfig=Get-Identity (Join-Path $upgradeFormatRepo '.ai-workspace\project.json')
            $upgradeFormatRun=Invoke-Ps $upgrade @('-ProjectId',('upgrade-agents-'+$upgradeAgentsFormatCase.Name+'-fixture'),'-ToVersion','1.14.0','-RepositoryPath',$upgradeFormatRepo,'-ControllerId','controller-upgrade-agents','-Apply')
            Assert-True ($upgradeFormatRegister.Code-eq0-and$upgradeFormatRun.Code-ne0-and$upgradeFormatRun.Text.Contains('AGENTS_MANAGED_BLOCK_TEXT_FORMAT')-and(Get-Identity $upgradeFormatAgents)-ceq$upgradeFormatIdentity-and(Get-Identity (Join-Path $upgradeFormatRepo '.ai-workspace\project.json'))-ceq$upgradeFormatConfig-and-not(Test-Path -LiteralPath (Join-Path $upgradeFormatRepo '.framework-1.14-upgrade-transaction'))) ('upgrade-agents-'+$upgradeAgentsFormatCase.Name+'-fails-before-project-write')
        }
        $downgradeFormatRepo=Join-Path $rootFlow 'consumer-downgrade-agents-crlf';New-GitRepo $downgradeFormatRepo;Write-Utf8 (Join-Path $downgradeFormatRepo 'AGENTS.md') '# downgrade project instructions'
        $downgradeFormatRegister=Invoke-Ps $register @('-ProjectId','downgrade-agents-crlf-fixture','-DisplayName','Downgrade Agents Fixture','-RepositoryPath',$downgradeFormatRepo,'-ControllerId','controller-downgrade-agents','-FrameworkVersion','1.14.0','-Apply')
        $downgradeFormatAgents=Join-Path $downgradeFormatRepo 'AGENTS.md';$downgradeLf=Get-Content -Raw -Encoding utf8 -LiteralPath $downgradeFormatAgents;[IO.File]::WriteAllText($downgradeFormatAgents,$downgradeLf.Replace("`n","`r`n"),[Text.UTF8Encoding]::new($false));$downgradeFormatIdentity=Get-Identity $downgradeFormatAgents;$downgradeFormatConfig=Get-Identity (Join-Path $downgradeFormatRepo '.ai-workspace\project.json')
        $downgradeFormatRun=Invoke-Ps $upgrade @('-ProjectId','downgrade-agents-crlf-fixture','-ToVersion','1.13.0','-RepositoryPath',$downgradeFormatRepo,'-ControllerId','controller-downgrade-agents','-Apply')
        Assert-True ($downgradeFormatRegister.Code-eq0-and$downgradeFormatRun.Code-ne0-and$downgradeFormatRun.Text.Contains('AGENTS_MANAGED_BLOCK_TEXT_FORMAT')-and(Get-Identity $downgradeFormatAgents)-ceq$downgradeFormatIdentity-and(Get-Identity (Join-Path $downgradeFormatRepo '.ai-workspace\project.json'))-ceq$downgradeFormatConfig-and-not(Test-Path -LiteralPath (Join-Path $downgradeFormatRepo '.framework-1.14-upgrade-transaction'))) 'downgrade-agents-crlf-fails-before-project-write'

        $sameVersionArgs=@('-ProjectId','explicit-fixture','-ToVersion','1.16.0','-RepositoryPath',$consumer,'-ControllerId','controller-explicit')
        $sameVersionPreview=Invoke-Ps $upgrade $sameVersionArgs
        $sameVersionApply=Invoke-Ps $upgrade @($sameVersionArgs+'-Apply')
        Assert-True ($sameVersionPreview.Code-eq0-and$sameVersionPreview.Text.Contains('WHAT_IF|from=1.16.0|to=1.16.0|objects=0|transaction=none')) 'upgrade-schema4-1.15-to-1.15-preview-validates-noop'
        Assert-True ($sameVersionApply.Code-eq0-and$sameVersionApply.Text.Contains('ALREADY_UPGRADED|objects=0|host-router=UNCHANGED')) 'upgrade-schema4-1.15-to-1.15-apply-noop'
        $schema4DowngradeArgs=@('-ProjectId','explicit-fixture','-ToVersion','1.13.0','-RepositoryPath',$consumer,'-ControllerId','controller-explicit')
        $schema4DowngradeConfigBefore=Get-Identity $registeredConfigPath
        $schema4DowngradePreview=Invoke-Ps $upgrade $schema4DowngradeArgs
        $schema4DowngradeApply=Invoke-Ps $upgrade @($schema4DowngradeArgs+'-Apply')
        Assert-True ($schema4DowngradePreview.Code-ne0-and$schema4DowngradeApply.Code-ne0-and$schema4DowngradePreview.Text.Contains('direct upgrade requires')-and(Get-Identity $registeredConfigPath)-ceq$schema4DowngradeConfigBefore) 'downgrade-1.15-to-older-version-is-not-an-implicit-reverse-migration'

        $activePolicyRepo=Join-Path $rootFlow 'consumer-active-policy';New-GitRepo $activePolicyRepo
        $activePolicyRegister=Invoke-Ps $register @('-ProjectId','active-policy-fixture','-DisplayName','Active Policy Fixture','-RepositoryPath',$activePolicyRepo,'-ControllerId','controller-active-policy','-FrameworkVersion','1.14.0','-Apply')
        $activePolicyConfigPath=Join-Path $activePolicyRepo '.ai-workspace\project.json';$activeCorrectionsPath=Join-Path $activePolicyRepo '.ai-workspace\corrections.json'
        $activeCorrections=Get-Content -Raw -Encoding utf8 -LiteralPath $activeCorrectionsPath|ConvertFrom-Json
        $activeCorrections.corrections=@([ordered]@{correctionId='ACTIVE_V2_DOWNGRADE_BOUNDARY';introducedAgainstFramework='1.13.0';requirementReason='The older correction carrier cannot represent progressive selectors.';effectiveRule='Retain the v2 correction until an explicit reverse migration is reviewed.';applicability='Framework downgrade';decisionLocator='test:active-v2-correction';selectors=[ordered]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@()})
        Write-Utf8 $activeCorrectionsPath ($activeCorrections|ConvertTo-Json -Depth 30);$activePolicyConfigBefore=Get-Identity $activePolicyConfigPath
        $activePolicyDowngrade=Invoke-Ps $upgrade @('-ProjectId','active-policy-fixture','-ToVersion','1.13.0','-RepositoryPath',$activePolicyRepo,'-ControllerId','controller-active-policy')
        Assert-True ($activePolicyRegister.Code-eq0-and$activePolicyDowngrade.Code-ne0-and$activePolicyDowngrade.Text.Contains('CORRECTIONS_V2_DOWNGRADE_REVERSE_MIGRATION_REQUIRED')-and(Get-Identity $activePolicyConfigPath)-ceq$activePolicyConfigBefore) 'downgrade-nonempty-corrections-v2-fails-before-write'

        $upgradeRepo=Join-Path $rootFlow 'consumer-upgrade'
        New-GitRepo $upgradeRepo
        Write-Utf8 (Join-Path $upgradeRepo 'AGENTS.md') '# Existing project agent instructions.'
        $sourceRegisterArgs=@('-ProjectId','upgrade-fixture','-DisplayName','Upgrade Fixture','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade','-FrameworkVersion','1.11.0','-Apply')
        $sourceRegister=Invoke-Ps $register $sourceRegisterArgs
        Assert-True ($sourceRegister.Code -eq 0 -and $sourceRegister.Text.Contains('CREATED')) 'upgrade-fixture-registers-explicit-1.11.0'

        $actorRouteRepo=Join-Path $rootFlow 'consumer-actor-route-upgrade';New-GitRepo $actorRouteRepo
        $actorRouteRegister=Invoke-Ps $register @('-ProjectId','actor-route-fixture','-DisplayName','Actor Route Fixture','-RepositoryPath',$actorRouteRepo,'-ControllerId','controller-actor-route','-FrameworkVersion','1.11.0','-Apply')
        $actorRouteTaskRelative='.ai-workspace/tasks/active/ACTOR-ROUTE-001.md';$actorRouteTaskPath=Join-Path $actorRouteRepo ($actorRouteTaskRelative.Replace('/','\'))
        Write-Utf8 $actorRouteTaskPath "# ACTOR-ROUTE-001 - fixture`n`n- Task schema: 1.11.0`n- Owner: owner-fixture`n- Work route: role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
        $actorRouteIdentity=Get-Identity $actorRouteTaskPath
        $actorRouteArgs=@('-ProjectId','actor-route-fixture','-ToVersion','1.13.0','-RepositoryPath',$actorRouteRepo,'-ControllerId','controller-actor-route','-ActorRouteTaskPath',$actorRouteTaskRelative,'-ExpectedActorRouteTaskIdentity',$actorRouteIdentity,'-ActorRouteActor','executor-current')
        $actorWrongTask=Invoke-Ps $upgrade @('-ProjectId','actor-route-fixture','-ToVersion','1.13.0','-RepositoryPath',$actorRouteRepo,'-ControllerId','controller-actor-route','-ActorRouteTaskPath','.ai-workspace/tasks/archive/ACTOR-ROUTE-001.md','-ExpectedActorRouteTaskIdentity',$actorRouteIdentity,'-ActorRouteActor','executor-current')
        Assert-True ($actorWrongTask.Code-ne0-and$actorWrongTask.Text.Contains('ACTOR_ROUTE_CURRENT_ACTIVE_TASK_REQUIRED')) 'upgrade-actor-route-rejects-noncurrent-task'
        $actorRoutePreview=Invoke-Ps $upgrade $actorRouteArgs
        $writeLine=@($actorRoutePreview.Output|Where-Object{$_-clike'UPGRADE_WRITESET|*'})[-1];$actorWritePaths=@($writeLine.Split('|')[1..($writeLine.Split('|').Count-1)])
        $preimageMap=@{};foreach($line in @($actorRoutePreview.Output|Where-Object{$_-clike'UPGRADE_PREIMAGE|*'})){$pair=$line.Substring('UPGRADE_PREIMAGE|'.Length);$split=$pair.IndexOf('=');$preimageMap[$pair.Substring(0,$split)]=$pair.Substring($split+1)}
        Assert-True ($actorRouteRegister.Code-eq0-and$actorRoutePreview.Code-eq0-and$actorRoutePreview.Text.Contains('transaction=actor-bound-forward')-and$actorRoutePreview.Text.Contains('.framework-actor-bound-upgrade-recovery-1.13.0/state.json')-and$actorRoutePreview.Text.Contains($actorRouteTaskRelative)-and$actorRoutePreview.Text.Contains('.ACTOR-ROUTE-001.md.actor-route-new')-and-not$actorRoutePreview.Text.Contains('.fwu-prep-')) 'upgrade-actor-bound-preview-exposes-deterministic-complete-write-set'
        $actorAuthPath=Join-Path $actorRouteRepo '.ai-workspace/tmp/actor-bound-upgrade-authorization.json';$actorObjects=@($actorWritePaths|ForEach-Object{[ordered]@{path=$_;identity=[string]$preimageMap[$_]}})
        $actorPackage=[ordered]@{schemaVersion=1;frameworkVersion='1.11.0';taskId='ACTOR-ROUTE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='controller-actor-route';issuerRole='PROJECT_CONTROLLER';grantee='executor-current';bundle='PLAN_LOCAL';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='USER_FIXTURE_ACTOR_BOUND_UPGRADE';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;actions=@('CONTROL_WRITE');exactPaths=$actorWritePaths;objectIdentities=$actorObjects;invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','CONTROLLER_EPOCH_CHANGE');issuerControllerId='controller-actor-route';issuerControllerEpoch=1;controllerControlIdentity=Get-Identity (Join-Path $actorRouteRepo '.ai-workspace/controller.json')}
        Write-Utf8 $actorAuthPath ($actorPackage|ConvertTo-Json -Depth 20);$actorAuthIdentity=Get-Identity $actorAuthPath
        $wrongActorApply=Invoke-Ps $upgrade @($actorRouteArgs[0..12]+@('executor-wrong','-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($wrongActorApply.Code-ne0-and$wrongActorApply.Text.Contains('ACTOR_BOUND_UPGRADE_AUTHORITY_BINDING')-and-not(Test-Path -LiteralPath (Join-Path $actorRouteRepo '.framework-actor-bound-upgrade-recovery-1.13.0'))) 'upgrade-actor-bound-rejects-wrong-actor-before-write'
        $actorDuplicateAuthPath=Join-Path $actorRouteRepo '.ai-workspace/tmp/actor-bound-upgrade-duplicate-authorization.json';$actorDuplicateRaw=$actorPackage|ConvertTo-Json -Depth 20;$actorDuplicateRaw=[regex]::Replace($actorDuplicateRaw,'"userConfirmation"\s*:\s*"[^"]+"','"userConfirmation": "USER_FIXTURE_ACTOR_BOUND_UPGRADE", "\u0075serConfirmation": "USER_FIXTURE_ACTOR_BOUND_UPGRADE"',1);Write-Utf8 $actorDuplicateAuthPath $actorDuplicateRaw;$actorDuplicateIdentity=Get-Identity $actorDuplicateAuthPath
        $actorDuplicateRun=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorDuplicateAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorDuplicateIdentity,'-Apply'))
        Assert-True ($actorDuplicateRun.Code-ne0-and$actorDuplicateRun.Text.Contains('ACTOR_BOUND_UPGRADE_AUTHORIZATION_DUPLICATE_MEMBER|userConfirmation')-and-not(Test-Path -LiteralPath (Join-Path $actorRouteRepo '.framework-actor-bound-upgrade-recovery-1.13.0'))) 'upgrade-actor-wrapper-rejects-unicode-duplicate-authorization-before-write'
        $actorRouteApply=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        $actorRouteText=Get-Content -Raw -Encoding utf8 -LiteralPath $actorRouteTaskPath;$actorRouteUpgradedConfig=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $actorRouteRepo '.ai-workspace/project.json')|ConvertFrom-Json
        if(-not($actorRouteApply.Code-eq0-and$actorRouteApply.Text.Contains('writes-after-task=ZERO')-and[string]$actorRouteUpgradedConfig.frameworkVersion-ceq'1.13.0'-and$actorRouteText.Contains('Task schema: 1.13.0')-and$actorRouteText.Contains('Work route: actor=executor-current; role=EXECUTOR; phase=IMPLEMENT'))){throw ('ASSERT_FAIL|upgrade-actor-bound-projects-new-pin-and-writes-current-task-last|code='+$actorRouteApply.Code+'|config='+[string]$actorRouteUpgradedConfig.frameworkVersion+'|task='+($actorRouteText.Replace("`r",'').Replace("`n",'\n'))+'|output='+$actorRouteApply.Text)}
        Assert-True $true 'upgrade-actor-bound-projects-new-pin-and-writes-current-task-last'
        $target113Root=Join-Path $liveFrameworkRoot 'versions/1.13.0'
        $actorTargetCheck=Invoke-Ps (Join-Path $target113Root 'scripts/check-task-card.ps1') @('-TaskPath',$actorRouteTaskPath);$actorTargetLoad=Invoke-Ps (Join-Path $target113Root 'scripts/resolve-load-plan.ps1') @('-TaskPath',$actorRouteTaskPath,'-ObservedActor','executor-current','-IncludeRecovery','-HostName','CODEX')
        Assert-True ($actorTargetCheck.Code-eq0-and$actorTargetLoad.Code-eq0-and$actorTargetLoad.Text.Contains('routeSource=TASK_CARD')-and$actorTargetLoad.Text.Contains('actor=executor-current')) 'upgrade-actor-bound-immediate-full-cold-uses-new-pin-route'
        $actorRouteDocs=(Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $liveRepositoryRoot 'README.md'))+(Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'CHANGELOG.md'))+(Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'MIGRATION_MATRIX.md'))+(Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'TASK_AND_SCOPE.md'))
        Assert-True (-not$actorRouteDocs.Contains('FULL_COLD_THEN_UPGRADE')-and-not$actorRouteDocs.Contains('单对象路由迁移并停止')-and$actorRouteDocs.Contains('全部 exact path/preimage')-and$actorRouteDocs.Contains('完整 path/preimage set')-and$actorRouteDocs.Contains('live non-task objects，最后写 current task')-and$actorRouteDocs.Contains('最后原子写 task，之后不再写')-and$actorRouteDocs.Contains('不得随后 cleanup、改 status 或写 recovery')) 'upgrade-actor-bound-docs-match-schema3-forward-transaction'
        $actorRecovery=Join-Path $actorRouteRepo '.framework-actor-bound-upgrade-recovery-1.13.0';[IO.File]::Copy((Join-Path $actorRecovery 'old/.ai-workspace/project.json'),(Join-Path $actorRouteRepo '.ai-workspace/project.json'),$true);[IO.File]::Copy((Join-Path $actorRecovery 'old/.ai-workspace/BOOTSTRAP.md'),(Join-Path $actorRouteRepo '.ai-workspace/BOOTSTRAP.md'),$true);[IO.File]::Copy((Join-Path $actorRecovery 'old/.ai-workspace/tasks/active/ACTOR-ROUTE-001.md'),$actorRouteTaskPath,$true)
        $actorControllerPath=Join-Path $actorRouteRepo '.ai-workspace/controller.json';$actorControllerOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $actorControllerPath;$actorTaskOldIdentity=Get-Identity $actorRouteTaskPath
        Write-Utf8 $actorControllerPath ($actorControllerOriginal.TrimEnd("`n")+"`n`n");$actorControllerObjectDrift=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($actorControllerObjectDrift.Code-ne0-and$actorControllerObjectDrift.Text.Contains('ACTOR_BOUND_UPGRADE_CONTROLLER_AUTHORITY_DRIFT')-and(Get-Identity $actorRouteTaskPath)-ceq$actorTaskOldIdentity) 'upgrade-actor-recovery-rejects-controller-object-drift-before-write'
        Write-Utf8 $actorControllerPath $actorControllerOriginal;$actorEpochController=$actorControllerOriginal|ConvertFrom-Json;$actorEpochController.controllerEpoch=2;Write-Utf8 $actorControllerPath ($actorEpochController|ConvertTo-Json -Depth 10);$actorEpochDrift=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($actorEpochDrift.Code-ne0-and$actorEpochDrift.Text.Contains('ACTOR_BOUND_UPGRADE_CONTROLLER_AUTHORITY_DRIFT')-and(Get-Identity $actorRouteTaskPath)-ceq$actorTaskOldIdentity) 'upgrade-actor-recovery-rejects-controller-epoch-drift-before-write'
        Write-Utf8 $actorControllerPath $actorControllerOriginal;$actorIdController=$actorControllerOriginal|ConvertFrom-Json;$actorIdController.controllerId='controller-actor-route-next';Write-Utf8 $actorControllerPath ($actorIdController|ConvertTo-Json -Depth 10);$actorIdArgs=@($actorRouteArgs);$actorIdArgs[7]='controller-actor-route-next';$actorIdDrift=Invoke-Ps $upgrade @($actorIdArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($actorIdDrift.Code-ne0-and$actorIdDrift.Text.Contains('ACTOR_BOUND_UPGRADE_CONTROLLER_AUTHORITY_DRIFT')-and(Get-Identity $actorRouteTaskPath)-ceq$actorTaskOldIdentity) 'upgrade-actor-recovery-rejects-controller-id-drift-before-write'
        Write-Utf8 $actorControllerPath $actorControllerOriginal
        $actorStatePath=Join-Path $actorRecovery 'state.json';$actorStateOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $actorStatePath;$actorTraversalState=$actorStateOriginal|ConvertFrom-Json;$actorTraversalState.objects[0].relative='../escape.txt';Write-Utf8 $actorStatePath ($actorTraversalState|ConvertTo-Json -Depth 20)
        $actorTraversalRun=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($actorTraversalRun.Code-ne0-and($actorTraversalRun.Text.Contains('CHILD_PATH_INVALID')-or$actorTraversalRun.Text.Contains('ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'))-and(Get-Identity $actorRouteTaskPath)-ceq$actorTaskOldIdentity) 'upgrade-actor-recovery-rejects-traversal-state-before-write'
        Write-Utf8 $actorStatePath $actorStateOriginal;$actorExtraState=$actorStateOriginal|ConvertFrom-Json;$actorExtraState.objects=@($actorExtraState.objects)+@([ordered]@{relative='.ai-workspace/extra.md';oldIdentity='MISSING';newIdentity='1|'+('A'*64)});Write-Utf8 $actorStatePath ($actorExtraState|ConvertTo-Json -Depth 20)
        $actorExtraRun=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($actorExtraRun.Code-ne0-and($actorExtraRun.Text.Contains('ACTOR_BOUND_UPGRADE_RECOVERY_AUTHORIZATION_PREIMAGE_DRIFT')-or$actorExtraRun.Text.Contains('ACTOR_BOUND_UPGRADE_RECOVERY_AUTHORIZATION_PATHSET_DRIFT'))-and(Get-Identity $actorRouteTaskPath)-ceq$actorTaskOldIdentity) 'upgrade-actor-recovery-rejects-extra-state-object-before-write'
        Write-Utf8 $actorStatePath $actorStateOriginal
        $actorPhysicalExtra=Join-Path $actorRecovery 'new\undeclared.bin';Write-Utf8 $actorPhysicalExtra 'undeclared actor recovery material'
        $actorPhysicalExtraRun=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($actorPhysicalExtraRun.Code-ne0-and$actorPhysicalExtraRun.Text.Contains('ACTOR_BOUND_UPGRADE_RECOVERY_TREE_CLOSURE')-and(Get-Identity $actorRouteTaskPath)-ceq$actorTaskOldIdentity-and(Test-Path -LiteralPath $actorPhysicalExtra)) 'upgrade-actor-recovery-rejects-undeclared-physical-material-before-write'
        Remove-Item -LiteralPath $actorPhysicalExtra -Force
        $actorResume=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'))
        Assert-True ($actorResume.Code-eq0-and$actorResume.Text.Contains('RECOVERED_UPGRADE|to=1.13.0')-and(Get-Content -Raw -Encoding utf8 $actorRouteTaskPath).Contains('actor=executor-current')) 'upgrade-actor-bound-restart-resumes-forward-task-last'
        Write-Utf8 $actorRouteTaskPath '# partial task bytes';$actorPartial=Invoke-Ps $upgrade @($actorRouteArgs+@('-AuthorizationPackagePath',$actorAuthPath,'-ExpectedAuthorizationPackageIdentity',$actorAuthIdentity,'-Apply'));[IO.File]::Copy((Join-Path $actorRecovery 'new/.ai-workspace/tasks/active/ACTOR-ROUTE-001.md'),$actorRouteTaskPath,$true)
        Assert-True ($actorPartial.Code-ne0-and$actorPartial.Text.Contains('ACTOR_ROUTE_TASK_DRIFT')) 'upgrade-actor-bound-partial-task-bytes-fail-closed'

        $actor114Repo=Join-Path $rootFlow 'consumer-actor-route-114-upgrade';New-GitRepo $actor114Repo
        $actor114Register=Invoke-Ps $register @('-ProjectId','actor-route-114-fixture','-DisplayName','Actor Route 1.14.1 Fixture','-RepositoryPath',$actor114Repo,'-ControllerId','controller-actor-route-114','-FrameworkVersion','1.14.1','-Apply')
        $actor114TaskRelative='.ai-workspace/tasks/active/ACTOR-ROUTE-114-001.md';$actor114TaskPath=Join-Path $actor114Repo ($actor114TaskRelative.Replace('/','\'))
        Write-Utf8 $actor114TaskPath "# ACTOR-ROUTE-114-001 - fixture`n`n- Task schema: 1.14.1`n- Owner: owner-fixture`n- Work route: actor=executor-current; role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=fixture-v1; expected_paths=[]; actual_paths=[]`n- Phase gate: FALSE`n- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=target-projected schema3 upgrade; added_machinery=NONE; escalation_trigger=Framework pin changes`n"
        $actor114BootstrapPath=Join-Path $actor114Repo '.ai-workspace/BOOTSTRAP.md';$actor114Bootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath $actor114BootstrapPath;$actor114Bootstrap=[regex]::Replace($actor114Bootstrap,'(?s)(<!-- PROJECT-CUSTOM:BEGIN -->\n).*?(\n<!-- PROJECT-CUSTOM:END -->)','$1'+('current-pin bridge fixture rule '+('x'*12288))+'$2');Write-Utf8 $actor114BootstrapPath $actor114Bootstrap
        $actor114OldTaskIdentity=Get-Identity $actor114TaskPath;$actor114BaseArgs=@('-ProjectId','actor-route-114-fixture','-ToVersion','1.16.0','-RepositoryPath',$actor114Repo,'-ControllerId','controller-actor-route-114','-ActorRouteTaskPath',$actor114TaskRelative,'-ExpectedActorRouteTaskIdentity',$actor114OldTaskIdentity,'-ActorRouteActor','executor-current')
        $actor114Intent=[ordered]@{schemaVersion=1;objective='Carry the project user decision into target-projected adoption preflight';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('Framework adoption','target-projected preflight');pathHints=@($actor114TaskRelative);capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
        $actor114ProcessPath=Join-Path $actor114Repo '.ai-workspace/tmp/current-pin-process-input.json';$actor114Process=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$actor114Repo;frameworkRoot=$rootFlow;taskPath=$actor114TaskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $actor114Repo '.ai-workspace/project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $actor114Repo '.ai-workspace/corrections.json');expectedTaskIdentity=$actor114OldTaskIdentity;observedActor='executor-current';capabilities=@();exactPaths=@($actor114TaskRelative);forbiddenPaths=@('src/','tests/','assets/','docs/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='USER_FIXTURE_ACTOR_BOUND_114_UPGRADE';recoveryState='FULL_COLD';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$actor114Intent;evaluationOnly=$true};Write-Utf8 $actor114ProcessPath ($actor114Process|ConvertTo-Json -Depth 20);$actor114ProcessIdentity=Get-Identity $actor114ProcessPath
        $actor114MissingProcess=Invoke-Ps $upgrade $actor114BaseArgs
        Assert-True ($actor114MissingProcess.Code-ne0-and$actor114MissingProcess.Text.Contains('TARGET_PROJECTED_PROCESS_USER_DECISION')) 'upgrade-1.14.1-to-1.16.0-requires-target-projected-user-decision'
        $actor114Args=@($actor114BaseArgs+@('-CurrentProcessInputPath',$actor114ProcessPath,'-ExpectedCurrentProcessInputIdentity',$actor114ProcessIdentity))
        $actor114SourceRoot=Join-Path $rootFlow 'framework/versions/1.14.1';$actor114ResolverPath=Join-Path $actor114SourceRoot 'scripts/resolve-process-requirements.ps1';$actor114ResolverOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $actor114ResolverPath
        Write-Utf8 $actor114ResolverPath "[CmdletBinding()]`nparam([string]`$InputPath,[switch]`$AsJson)`nWrite-Output '{`"status`":`"FAIL`",`"reason`":`"SELECTED_RULE_PACK_BUDGET_EXCEEDED`"}'`nexit 2";$null=Seal-ReleaseFixture $actor114SourceRoot 'CURRENT_PIN_RESOLVER_FAILURE_IGNORED_FIXTURE';$actor114TargetProjectedBypass=Invoke-Ps $upgrade $actor114Args
        Assert-True ($actor114TargetProjectedBypass.Code-eq0-and$actor114TargetProjectedBypass.Text.Contains('TARGET_PROJECTED_PROCESS_PREFLIGHT|to=1.16.0|resolver=PASS|')-and$actor114TargetProjectedBypass.Text.Contains('|budget=PROJECT_SELECTED|')) 'upgrade-target-projected-process-bypasses-current-resolver-failure'
        Write-Utf8 $actor114ResolverPath $actor114ResolverOriginal;$null=Seal-ReleaseFixture $actor114SourceRoot 'CURRENT_PIN_REAL_SOURCE_RESTORED'
        $actor114Preview=Invoke-Ps $upgrade $actor114Args;$actor114WriteLines=@($actor114Preview.Output|Where-Object{$_-clike'UPGRADE_WRITESET|*'});if($actor114Preview.Code-ne0-or$actor114WriteLines.Count-ne1){throw ('ASSERT_FAIL|upgrade-actor-bound-1.14-to-1.16.0-preview|code='+$actor114Preview.Code+'|output='+$actor114Preview.Text)};$actor114WriteLine=$actor114WriteLines[0];$actor114WritePaths=@($actor114WriteLine.Split('|')[1..($actor114WriteLine.Split('|').Count-1)]);$actor114PreimageMap=@{};$actor114PostimageMap=@{}
        foreach($line in @($actor114Preview.Output|Where-Object{$_-clike'UPGRADE_PREIMAGE|*'})){$pair=$line.Substring('UPGRADE_PREIMAGE|'.Length);$split=$pair.IndexOf('=');$actor114PreimageMap[$pair.Substring(0,$split)]=$pair.Substring($split+1)}
        foreach($line in @($actor114Preview.Output|Where-Object{$_-clike'UPGRADE_POSTIMAGE|*'})){$pair=$line.Substring('UPGRADE_POSTIMAGE|'.Length);$split=$pair.IndexOf('=');$actor114PostimageMap[$pair.Substring(0,$split)]=$pair.Substring($split+1)}
        $actor114AuthPath=Join-Path $actor114Repo '.ai-workspace/tmp/actor-bound-114-authorization.json';$actor114Objects=@($actor114WritePaths|ForEach-Object{[ordered]@{path=$_;identity=[string]$actor114PreimageMap[$_]}});$actor114PostObjects=@($actor114PostimageMap.Keys|Sort-Object|ForEach-Object{[ordered]@{path=$_;identity=[string]$actor114PostimageMap[$_]}});$actor114ControllerPath=Join-Path $actor114Repo '.ai-workspace/controller.json';$actor114ProjectPath=Join-Path $actor114Repo '.ai-workspace/project.json'
        $actor114Package=[ordered]@{schemaVersion=3;frameworkVersion='1.16.0';taskId='ACTOR-ROUTE-114-001';profile='CRITICAL';lifecycle='ACTIVE';owner='owner-fixture';issuer='controller-actor-route-114';issuerRole='PROJECT_CONTROLLER';grantee='executor-current';bundle='ACTOR_BOUND_PROJECT_UPGRADE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='USER_FIXTURE_ACTOR_BOUND_114_UPGRADE';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=$actor114OldTaskIdentity;actions=@('CONTROL_WRITE');exactPaths=$actor114WritePaths;objectIdentities=$actor114Objects;postObjectIdentities=$actor114PostObjects;projectConfigIdentity=Get-Identity $actor114ProjectPath;invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','POST_OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');issuerControllerId='controller-actor-route-114';issuerControllerEpoch=1;controllerControlIdentity=Get-Identity $actor114ControllerPath}
        Write-Utf8 $actor114AuthPath ($actor114Package|ConvertTo-Json -Depth 20);$actor114AuthIdentity=Get-Identity $actor114AuthPath
        $actor114Apply=Invoke-Ps $upgrade @($actor114Args+@('-AuthorizationPackagePath',$actor114AuthPath,'-ExpectedAuthorizationPackageIdentity',$actor114AuthIdentity,'-Apply'))
        $actor114Recovery=Join-Path $actor114Repo '.ai-workspace/upgrade-recovery/1.16.0';$actor114State=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $actor114Recovery 'state.json')|ConvertFrom-Json
        foreach($entry in @($actor114State.objects)){$live=Join-Path $actor114Repo (([string]$entry.relative).Replace('/','\'));if([string]$entry.oldIdentity-ceq'MISSING'){Remove-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue}else{[IO.File]::Copy((Join-Path $actor114Recovery ('old\'+([string]$entry.relative).Replace('/','\'))),$live,$true)}}
        Remove-Item -LiteralPath (Join-Path $actor114Repo '.agents') -Recurse -Force -ErrorAction SilentlyContinue;$actor114External=Join-Path $rootFlow 'external-actor-114-agents';New-Item -ItemType Directory -Path $actor114External -Force|Out-Null;$actor114Link=Join-Path $actor114Repo '.agents';New-TestJunction $actor114Link $actor114External;$actor114ConfigPreimage=Get-Identity (Join-Path $actor114Repo '.ai-workspace/project.json')
        try{$actor114DriftRun=Invoke-Ps $upgrade @($actor114Args+@('-AuthorizationPackagePath',$actor114AuthPath,'-ExpectedAuthorizationPackageIdentity',$actor114AuthIdentity,'-Apply'))}
        finally{Remove-TestJunction $actor114Link}
        if(-not($actor114Register.Code-eq0-and$actor114Preview.Code-eq0-and$actor114Apply.Code-eq0-and$actor114DriftRun.Code-ne0-and$actor114DriftRun.Text.Contains('MANAGED_ROUTER_DESTINATION_REPARSE')-and(Get-Identity (Join-Path $actor114Repo '.ai-workspace/project.json'))-ceq$actor114ConfigPreimage-and(Get-Identity $actor114TaskPath)-ceq$actor114OldTaskIdentity-and-not(Test-Path -LiteralPath (Join-Path $actor114External 'skills\ai-workspace-router\SKILL.md'))-and(Test-Path -LiteralPath $actor114Recovery -PathType Container))){Write-Output ('DIAG|actor-114-router-drift|register='+$actor114Register.Code+'|preview='+$actor114Preview.Code+'|apply='+$actor114Apply.Code+'|drift='+$actor114DriftRun.Code+'|applyOutput='+$actor114Apply.Text+'|driftOutput='+$actor114DriftRun.Text)}
        Assert-True ($actor114Register.Code-eq0-and$actor114Preview.Code-eq0-and$actor114Preview.Text.Contains('TARGET_PROJECTED_PROCESS_PREFLIGHT|to=1.16.0|resolver=PASS|')-and$actor114Preview.Text.Contains('|budget=PROJECT_SELECTED|')-and$actor114Apply.Code-eq0-and$actor114DriftRun.Code-ne0-and$actor114DriftRun.Text.Contains('MANAGED_ROUTER_DESTINATION_REPARSE')-and(Get-Identity (Join-Path $actor114Repo '.ai-workspace/project.json'))-ceq$actor114ConfigPreimage-and(Get-Identity $actor114TaskPath)-ceq$actor114OldTaskIdentity-and-not(Test-Path -LiteralPath (Join-Path $actor114External 'skills\ai-workspace-router\SKILL.md'))-and(Test-Path -LiteralPath $actor114Recovery -PathType Container)) 'upgrade-target-projected-process-router-reparse-drift-retains-recovery-zero-external-write'

        $actor1141Repo=Join-Path $rootFlow 'consumer-actor-route-1150-upgrade';New-GitRepo $actor1141Repo
        $actor1141Register=Invoke-Ps $register @('-ProjectId','actor-route-1150-fixture','-DisplayName','Actor Route 1.15.0 Fixture','-RepositoryPath',$actor1141Repo,'-ControllerId','controller-actor-route-1150','-FrameworkVersion','1.15.0','-Apply');$actor1141TaskRelative='.ai-workspace/tasks/active/ACTOR-ROUTE-1150-001.md';$actor1141TaskPath=Join-Path $actor1141Repo ($actor1141TaskRelative.Replace('/','\'));Write-Utf8 $actor1141TaskPath "# ACTOR-ROUTE-1150-001 - fixture`n`n- Task schema: 1.15.0`n- Owner: owner-fixture`n- Work route: actor=executor-current; role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=fixture-v1; expected_paths=[]; actual_paths=[]`n- Phase gate: FALSE`n- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=target-projected preview; added_machinery=NONE; escalation_trigger=Framework pin changes`n"
        $actor1141TaskIdentity=Get-Identity $actor1141TaskPath
        $actor1141Intent=[ordered]@{schemaVersion=1;objective='Carry the project user decision into target-projected adoption preflight';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('Framework adoption','target-projected preflight');pathHints=@($actor1141TaskRelative);capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'};$actor1141ProcessPath=Join-Path $actor1141Repo '.ai-workspace/tmp/current-pin-process-input.json';$actor1141Process=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$actor1141Repo;frameworkRoot=$rootFlow;taskPath=$actor1141TaskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $actor1141Repo '.ai-workspace/project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $actor1141Repo '.ai-workspace/corrections.json');expectedTaskIdentity=$actor1141TaskIdentity;observedActor='executor-current';capabilities=@();exactPaths=@($actor1141TaskRelative);forbiddenPaths=@('src/','test/','assets/','docs/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='USER_FIXTURE_ACTOR_BOUND_1150_UPGRADE';recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$actor1141Intent;evaluationOnly=$true};Write-Utf8 $actor1141ProcessPath ($actor1141Process|ConvertTo-Json -Depth 20);$actor1141Preview=Invoke-Ps $upgrade @('-ProjectId','actor-route-1150-fixture','-ToVersion','1.16.0','-RepositoryPath',$actor1141Repo,'-ControllerId','controller-actor-route-1150','-ActorRouteTaskPath',$actor1141TaskRelative,'-ExpectedActorRouteTaskIdentity',$actor1141TaskIdentity,'-ActorRouteActor','executor-current','-CurrentProcessInputPath',$actor1141ProcessPath,'-ExpectedCurrentProcessInputIdentity',(Get-Identity $actor1141ProcessPath))
        if($actor1141Preview.Code-ne0-or-not$actor1141Preview.Text.Contains('TARGET_PROJECTED_PROCESS_PREFLIGHT|to=1.16.0|resolver=PASS|')){Write-Output ('DIAG|upgrade-target-projected-1.15.0|code='+$actor1141Preview.Code+'|'+$actor1141Preview.Text)}
        Assert-True ($actor1141Register.Code-eq0-and$actor1141Preview.Code-eq0-and$actor1141Preview.Text.Contains('TARGET_PROJECTED_PROCESS_PREFLIGHT|to=1.16.0|resolver=PASS|')-and$actor1141Preview.Text.Contains('|budget=PROJECT_SELECTED|')) 'upgrade-target-projected-process-success-preview-from-1.15.0'

        $actor1151Repo=Join-Path $rootFlow 'consumer-actor-route-1151-upgrade';New-GitRepo $actor1151Repo
        $actor1151Register=Invoke-Ps $register @('-ProjectId','actor-route-1151-fixture','-DisplayName','Actor Route 1.15.1 Fixture','-RepositoryPath',$actor1151Repo,'-ControllerId','controller-actor-route-1151','-FrameworkVersion','1.15.1','-Apply');$actor1151ProjectPath=Join-Path $actor1151Repo '.ai-workspace/project.json';$actor1151Project=Get-Content -Raw -Encoding utf8 -LiteralPath $actor1151ProjectPath|ConvertFrom-Json;$actor1151Project.frameworkCapabilities=[pscustomobject][ordered]@{KNOWLEDGE_REFERENCE=[pscustomobject][ordered]@{enabled=$true;indexLocator='knowledge/index.json'}};Write-Utf8 $actor1151ProjectPath ($actor1151Project|ConvertTo-Json -Depth 20)
        $actor1151TaskRelative='.ai-workspace/tasks/active/ACTOR-ROUTE-1151-001.md';$actor1151TaskPath=Join-Path $actor1151Repo ($actor1151TaskRelative.Replace('/','\'));Write-Utf8 $actor1151TaskPath "# ACTOR-ROUTE-1151-001 - fixture`n`n- Task schema: 1.15.1`n- Owner: owner-fixture`n- Work route: actor=executor-current; role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=fixture-v1; expected_paths=[]; actual_paths=[]`n- Phase gate: FALSE`n- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=target-projected capability preflight; added_machinery=NONE; escalation_trigger=Framework pin changes`n";$actor1151TaskIdentity=Get-Identity $actor1151TaskPath
        $actor1151Intent=[ordered]@{schemaVersion=1;objective='Carry the project user decision into target-projected adoption preflight';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('Framework adoption','target-projected preflight');pathHints=@($actor1151TaskRelative);capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'};$actor1151ProcessPath=Join-Path $actor1151Repo '.ai-workspace/tmp/current-pin-process-input.json';$actor1151Process=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$actor1151Repo;frameworkRoot=$rootFlow;taskPath=$actor1151TaskPath;expectedProjectConfigIdentity=Get-Identity $actor1151ProjectPath;expectedCorrectionsIdentity=Get-Identity (Join-Path $actor1151Repo '.ai-workspace/corrections.json');expectedTaskIdentity=$actor1151TaskIdentity;observedActor='executor-current';capabilities=@();exactPaths=@($actor1151TaskRelative);forbiddenPaths=@('src/','tests/','assets/','docs/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='USER_FIXTURE_ACTOR_BOUND_1151_UPGRADE';recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$actor1151Intent;evaluationOnly=$true}
        Write-Utf8 $actor1151ProcessPath ($actor1151Process|ConvertTo-Json -Depth 20);$actor1151Preview=Invoke-Ps $upgrade @('-ProjectId','actor-route-1151-fixture','-ToVersion','1.16.0','-RepositoryPath',$actor1151Repo,'-ControllerId','controller-actor-route-1151','-ActorRouteTaskPath',$actor1151TaskRelative,'-ExpectedActorRouteTaskIdentity',$actor1151TaskIdentity,'-ActorRouteActor','executor-current','-CurrentProcessInputPath',$actor1151ProcessPath,'-ExpectedCurrentProcessInputIdentity',(Get-Identity $actor1151ProcessPath))
        if($actor1151Preview.Code-ne0-or-not$actor1151Preview.Text.Contains('TARGET_PROJECTED_PROCESS_PREFLIGHT|to=1.16.0|resolver=PASS|')){Write-Output ('DIAG|upgrade-target-projected-1.15.1|code='+$actor1151Preview.Code+'|'+$actor1151Preview.Text)}
        Assert-True ($actor1151Register.Code-eq0-and$actor1151Preview.Code-eq0-and$actor1151Preview.Text.Contains('TARGET_PROJECTED_PROCESS_PREFLIGHT|to=1.16.0|resolver=PASS|')-and$actor1151Preview.Text.Contains('|capabilities=KNOWLEDGE_REFERENCE|budget=PROJECT_SELECTED|')) 'upgrade-target-projected-process-binds-project-capabilities-from-1.15.1'
        $actor1151DuplicateGitIgnorePath=Join-Path $actor1151Repo '.gitignore';Write-Utf8 $actor1151DuplicateGitIgnorePath "/.ai-workspace/runtime/`n.ai-workspace/runtime`n";$actor1151DuplicateGitIgnoreIdentity=Get-Identity $actor1151DuplicateGitIgnorePath
        $actor1151DuplicateRun=Invoke-Ps $upgrade @('-ProjectId','actor-route-1151-fixture','-ToVersion','1.16.0','-RepositoryPath',$actor1151Repo,'-ControllerId','controller-actor-route-1151','-ActorRouteTaskPath',$actor1151TaskRelative,'-ExpectedActorRouteTaskIdentity',$actor1151TaskIdentity,'-ActorRouteActor','executor-current','-CurrentProcessInputPath',$actor1151ProcessPath,'-ExpectedCurrentProcessInputIdentity',(Get-Identity $actor1151ProcessPath))
        Assert-True ($actor1151DuplicateRun.Code-ne0-and$actor1151DuplicateRun.Text.Contains('RUNTIME_GITIGNORE_DUPLICATE_CONFLICT')-and(Get-Identity $actor1151DuplicateGitIgnorePath)-ceq$actor1151DuplicateGitIgnoreIdentity) 'upgrade-runtime-gitignore-duplicate-conflict-preserves-bytes'
        Remove-Item -LiteralPath $actor1151DuplicateGitIgnorePath -Force
        $actor1151ProjectOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $actor1151ProjectPath;$actor1151Unknown=$actor1151ProjectOriginal|ConvertFrom-Json;$actor1151Unknown.frameworkCapabilities=[pscustomobject][ordered]@{UNKNOWN=[pscustomobject][ordered]@{enabled=$false}};Write-Utf8 $actor1151ProjectPath ($actor1151Unknown|ConvertTo-Json -Depth 20);$actor1151UnknownRun=Invoke-Ps $upgrade @('-ProjectId','actor-route-1151-fixture','-ToVersion','1.16.0','-RepositoryPath',$actor1151Repo,'-ControllerId','controller-actor-route-1151','-ActorRouteTaskPath',$actor1151TaskRelative,'-ExpectedActorRouteTaskIdentity',$actor1151TaskIdentity,'-ActorRouteActor','executor-current','-CurrentProcessInputPath',$actor1151ProcessPath,'-ExpectedCurrentProcessInputIdentity',(Get-Identity $actor1151ProcessPath));Write-Utf8 $actor1151ProjectPath $actor1151ProjectOriginal
        Assert-True ($actor1151UnknownRun.Code-ne0-and$actor1151UnknownRun.Text.Contains('FRAMEWORK_CAPABILITIES_UNKNOWN_OR_DUPLICATE')) 'upgrade-target-capability-contract-rejects-unknown-capability'

        $upgradeControl=Join-Path $upgradeRepo '.ai-workspace'
        $upgradeConfigPath=Join-Path $upgradeControl 'project.json';$upgradeBootstrapPath=Join-Path $upgradeControl 'BOOTSTRAP.md';$upgradeControllerPath=Join-Path $upgradeControl 'controller.json'
        $upgradeConfigBeforeUnsupportedPlatform=Get-Identity $upgradeConfigPath
        $unsupportedToolchain=$fixtureToolchainOriginal|ConvertFrom-Json;$unsupportedToolchain.officialBackends[0].platforms=@('linux');Write-Utf8 $fixtureToolchainPath ($unsupportedToolchain|ConvertTo-Json -Depth 20);$null=Seal-ReleaseFixture $fixtureVersionRoot 'UNSUPPORTED_PLATFORM_TEST_FIXTURE'
        $unsupportedUpgrade=Invoke-Ps $upgrade @('-ProjectId','upgrade-fixture','-ToVersion','1.16.0','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade','-Apply')
        Assert-True ($unsupportedUpgrade.Code-ne0-and$unsupportedUpgrade.Text.Contains('FRAMEWORK_TOOL_PLATFORM_UNSUPPORTED|backend=powershell7|platform=windows')-and(Get-Identity $upgradeConfigPath)-ceq$upgradeConfigBeforeUnsupportedPlatform-and-not(Test-Path -LiteralPath (Join-Path $upgradeControl '.framework-upgrade-transaction'))) 'upgrade-unsupported-declared-platform-zero-write-before-transaction'
        Write-Utf8 $fixtureToolchainPath $fixtureToolchainOriginal;$null=Seal-ReleaseFixture $fixtureVersionRoot 'TEST_FIXTURE_SEALED'
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
        $upgradeArgs=@('-ProjectId','upgrade-fixture','-ToVersion','1.14.0','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade')
        $inactivePolicyPath=Join-Path $upgradeControl 'process-policy.json';Write-Utf8 $inactivePolicyPath (([ordered]@{schemaVersion=1;contractVersion='1.13.0';projectId='upgrade-fixture';rules=@()})|ConvertTo-Json -Depth 20);$inactiveConfigIdentity=Get-Identity $upgradeConfigPath
        $inactivePolicyRun=Invoke-Ps $upgrade $upgradeArgs
        Assert-True ($inactivePolicyRun.Code-ne0-and$inactivePolicyRun.Text.Contains('FRAMEWORK_1_14_INACTIVE_POLICY_COLLISION')-and(Get-Identity $upgradeConfigPath)-ceq$inactiveConfigIdentity) 'upgrade-1.11-inactive-unowned-policy-collision-fails-before-write'
        Remove-Item -LiteralPath $inactivePolicyPath -Force
        $upgradeConfig.controlPlaneLayout='invalid-layout';Write-Utf8 $upgradeConfigPath ($upgradeConfig|ConvertTo-Json -Depth 20)
        $invalidLayoutUpgrade=Invoke-Ps $upgrade $upgradeArgs
        Assert-True ($invalidLayoutUpgrade.Code -ne 0 -and $invalidLayoutUpgrade.Text.Contains('PROJECT_CONTROL_PLANE_LAYOUT') -and -not$invalidLayoutUpgrade.Text.Contains('Framework 1.8')) 'upgrade-invalid-layout-diagnostic-is-version-neutral'
        $upgradeConfig.controlPlaneLayout='repo-local';Write-Utf8 $upgradeConfigPath ($upgradeConfig|ConvertTo-Json -Depth 20)
        $conflictReleaseRoot=Join-Path $rootFlow 'framework\versions\1.14.0';$conflictCoveragePath=Join-Path $conflictReleaseRoot 'CORRECTION_COVERAGE.json'
        $coverageOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $conflictCoveragePath
        $conflictCoverage=$coverageOriginal|ConvertFrom-Json
        $conflictEntry=@($conflictCoverage.versions|Where-Object{[string]$_.version-ceq'1.14.0'})[0]
        $conflictEntry.conflictingCorrectionIds=@('TEST_UNINCORPORATED_REQUIREMENT')
        Write-Utf8 $conflictCoveragePath ($conflictCoverage|ConvertTo-Json -Depth 20)
        $null=Seal-ReleaseFixture $conflictReleaseRoot 'CONFLICT_TEST_FIXTURE'
        $conflictUpgrade=Invoke-Ps $upgrade $upgradeArgs
        $conflictVersion=[string](Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeConfigPath|ConvertFrom-Json).frameworkVersion
        $conflictCorrectionsIdentity=Get-Identity $upgradeCorrectionsPath
        $conflictBlocked=$conflictUpgrade.Code-ne0-and$conflictUpgrade.Text.Contains('PROJECT_CORRECTION_CONFLICT')-and$conflictVersion-ceq'1.11.0'-and$conflictCorrectionsIdentity-ceq$upgradeCorrectionsBefore
        if(-not$conflictBlocked){Write-Output ('DIAG|upgrade-correction-conflict|code='+$conflictUpgrade.Code+'|version='+$conflictVersion+'|corrections='+$conflictCorrectionsIdentity+'|expected='+$upgradeCorrectionsBefore+'|output='+$conflictUpgrade.Text)}
        Assert-True $conflictBlocked 'upgrade-correction-conflict-blocks-before-pin-write'
        Write-Utf8 $conflictCoveragePath $coverageOriginal
        $null=Seal-ReleaseFixture $conflictReleaseRoot 'TEST_FIXTURE_SEALED'
        $upgradePreview=Invoke-Ps $upgrade $upgradeArgs
        Assert-True ($upgradePreview.Code -eq 0 -and $upgradePreview.Text.Contains('WHAT_IF|from=1.11.0|to=1.14.0|objects=6') -and $upgradePreview.Text.Contains('incorporated=0') -and $upgradePreview.Text.Contains('still-effective=3') -and $upgradePreview.Text.Contains('conflicts=0')) 'upgrade-1.11-to-1.14-preview-retains-unmapped-corrections'
        $upgradeObjectRelatives=@('.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','AGENTS.md','.agents/skills/ai-workspace-router/SKILL.md');$upgradeStartCollisionPath=Join-Path $upgradeRepo '.framework-1.14-upgrade-recovery-1.14.0';New-Item -ItemType Directory -Path $upgradeStartCollisionPath -Force|Out-Null;$upgradeStartCollisionMarker=Join-Path $upgradeStartCollisionPath 'project-owned.txt';Write-Utf8 $upgradeStartCollisionMarker 'preexisting recovery name'
        $upgradeStartCollisionBefore=Get-ExactObjectRows $upgradeRepo $upgradeObjectRelatives;$upgradeStartMarkerBefore=Get-Identity $upgradeStartCollisionMarker
        $upgradeStartCollisionRun=Invoke-Ps $upgrade @($upgradeArgs+'-Apply');$upgradeStartCollisionAfter=Get-ExactObjectRows $upgradeRepo $upgradeObjectRelatives
        Assert-True ($upgradeStartCollisionRun.Code-ne0-and$upgradeStartCollisionRun.Text.Contains('FRAMEWORK_1_14_TRANSACTION_RECOVERY_COLLISION')-and[string]::Join("`n",$upgradeStartCollisionAfter)-ceq[string]::Join("`n",$upgradeStartCollisionBefore)-and(Get-Identity $upgradeStartCollisionMarker)-ceq$upgradeStartMarkerBefore-and-not(Test-Path -LiteralPath (Join-Path $upgradeRepo '.framework-1.14-upgrade-transaction'))) 'upgrade-start-recovery-collision-preserves-six-live-objects'
        Remove-Item -LiteralPath $upgradeStartCollisionPath -Recurse -Force
        $upgradeApply=Invoke-Ps $upgrade @($upgradeArgs+'-Apply')
        if($upgradeApply.Code-ne0-or-not$upgradeApply.Text.Contains('UPGRADED|objects=6')){Write-Output ('DIAG|upgrade-1.11-to-1.14-apply|code='+$upgradeApply.Code+'|output='+$upgradeApply.Text)}
        Assert-True ($upgradeApply.Code -eq 0 -and $upgradeApply.Text.Contains('UPGRADED|objects=6')) 'upgrade-1.11-to-1.14-apply'
        $upgradeRecoveryMatch=[regex]::Match($upgradeApply.Text,'recovery=(?<path>[^\r\n]+)');$upgradeRecoveryPath=$upgradeRecoveryMatch.Groups['path'].Value.Trim();$upgradeActiveTransaction=Join-Path $upgradeRepo '.framework-1.14-upgrade-transaction'
        [IO.Directory]::Move($upgradeRecoveryPath,$upgradeActiveTransaction);[IO.File]::Copy((Join-Path $upgradeActiveTransaction 'old\.ai-workspace\project.json'),$upgradeConfigPath,$true)
        New-Item -ItemType Directory -Path $upgradeRecoveryPath -Force|Out-Null;$upgradeResumeCollisionMarker=Join-Path $upgradeRecoveryPath 'project-owned.txt';Write-Utf8 $upgradeResumeCollisionMarker 'preexisting recovery name';$upgradeResumeCollisionBefore=Get-ExactObjectRows $upgradeRepo $upgradeObjectRelatives;$upgradeResumeMarkerBefore=Get-Identity $upgradeResumeCollisionMarker
        $upgradeResumeCollisionRun=Invoke-Ps $upgrade @($upgradeArgs+'-Apply');$upgradeResumeCollisionAfter=Get-ExactObjectRows $upgradeRepo $upgradeObjectRelatives
        Assert-True ($upgradeResumeCollisionRun.Code-ne0-and$upgradeResumeCollisionRun.Text.Contains('FRAMEWORK_1_14_TRANSACTION_RECOVERY_COLLISION')-and[string]::Join("`n",$upgradeResumeCollisionAfter)-ceq[string]::Join("`n",$upgradeResumeCollisionBefore)-and(Get-Identity $upgradeResumeCollisionMarker)-ceq$upgradeResumeMarkerBefore-and(Test-Path -LiteralPath $upgradeActiveTransaction -PathType Container)) 'upgrade-resume-recovery-collision-preserves-six-live-objects'
        Remove-Item -LiteralPath $upgradeRecoveryPath -Recurse -Force
        $upgradePhysicalExtra=Join-Path $upgradeActiveTransaction 'new\undeclared.bin';Write-Utf8 $upgradePhysicalExtra 'undeclared cross-root material';$upgradePhysicalPreimage=Get-Identity $upgradeConfigPath
        $upgradePhysicalExtraRun=Invoke-Ps $upgrade @($upgradeArgs+'-Apply')
        Assert-True ($upgradePhysicalExtraRun.Code-ne0-and$upgradePhysicalExtraRun.Text.Contains('FRAMEWORK_1_14_TRANSACTION_TREE_CLOSURE')-and(Get-Identity $upgradeConfigPath)-ceq$upgradePhysicalPreimage-and(Test-Path -LiteralPath $upgradePhysicalExtra)) 'upgrade-cross-root-recovery-rejects-undeclared-physical-material-before-write'
        Remove-Item -LiteralPath $upgradePhysicalExtra -Force
        $upgradeResume=Invoke-Ps $upgrade @($upgradeArgs+'-Apply')
        Assert-True ($upgradeRecoveryMatch.Success-and$upgradeResume.Code-eq0-and$upgradeResume.Text.Contains('RECOVERED_UPGRADE|objects=6|initial=MIXED')-and-not(Test-Path -LiteralPath $upgradeActiveTransaction)) 'upgrade-1.14-mixed-transaction-resumes-forward'
        [IO.Directory]::Move($upgradeRecoveryPath,$upgradeActiveTransaction);$upgradeUnknownPath=Join-Path $upgradeRepo 'AGENTS.md';Write-Utf8 $upgradeUnknownPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeUnknownPath).TrimEnd("`n")+"`nunknown transaction drift`n");$upgradeUnknownIdentity=Get-Identity $upgradeUnknownPath
        $upgradeUnknown=Invoke-Ps $upgrade @($upgradeArgs+'-Apply')
        Assert-True ($upgradeUnknown.Code-ne0-and$upgradeUnknown.Text.Contains('FRAMEWORK_1_14_TRANSACTION_UNKNOWN_LIVE_BYTES|AGENTS.md')-and(Get-Identity $upgradeUnknownPath)-ceq$upgradeUnknownIdentity-and(Test-Path -LiteralPath $upgradeActiveTransaction)) 'upgrade-1.14-unknown-live-bytes-stop-without-overwrite'
        [IO.File]::Copy((Join-Path $upgradeActiveTransaction 'new\AGENTS.md'),$upgradeUnknownPath,$true);$upgradeRecoveryCleanup=Invoke-Ps $upgrade @($upgradeArgs+'-Apply')
        Assert-True ($upgradeRecoveryCleanup.Code-eq0-and$upgradeRecoveryCleanup.Text.Contains('RECOVERED_UPGRADE|objects=6|initial=NEW')) 'upgrade-1.14-known-new-transaction-finalizes-after-manual-rebind'
        $upgradedConfig=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeConfigPath|ConvertFrom-Json
        $upgradedBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeBootstrapPath
        $upgradedPolicy=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $upgradeControl 'process-policy.json')|ConvertFrom-Json
        Assert-True ([string]$upgradedConfig.frameworkVersion -ceq '1.14.0' -and[int]$upgradedConfig.schemaVersion-eq4-and[string]$upgradedConfig.processPolicy.locator-ceq'.ai-workspace/process-policy.json'-and[string]$upgradedPolicy.contractVersion-ceq'1.14.0'-and@($upgradedPolicy.rules).Count-eq0-and [string]$upgradedConfig.frameworkToolBackend -ceq 'powershell7' -and @($upgradedConfig.routineExcludedPaths).Count -eq 1 -and [string]$upgradedConfig.routineExcludedPaths[0] -ceq 'private/keep.txt' -and $upgradedConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled -eq $false -and $upgradedBootstrap.Contains('fixture-custom-preserved') -and $upgradedBootstrap.Contains('TOOLCHAIN.json') -and $upgradedBootstrap.Contains('PROJECT-CORRECTIONS:BEGIN') -and (Get-Identity $upgradeControllerPath) -ceq $controllerBefore -and (Get-Identity $upgradeCorrectionsPath) -ceq $upgradeCorrectionsBefore -and (Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $upgradeRepo 'AGENTS.md')).StartsWith('# Existing project agent instructions.') -and (Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $upgradeRepo 'AGENTS.md')).Contains('AI-WORKSPACE-FRAMEWORK:BEGIN') -and (Test-Path -LiteralPath (Join-Path $upgradeRepo '.agents\skills\ai-workspace-router\SKILL.md') -PathType Leaf)) 'upgrade-1.11-to-1.14-preserves-custom-authority-adds-compatible-structured-empty-policy-and-router'
        $repeatPreservedV1=Invoke-Ps $register @('-ProjectId','upgrade-fixture','-DisplayName','Upgrade Fixture','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade','-FrameworkVersion','1.14.0')
        Assert-True ($repeatPreservedV1.Code-eq0-and$repeatPreservedV1.Text.Contains('ALREADY_REGISTERED')-and(Get-Identity $upgradeCorrectionsPath)-ceq$upgradeCorrectionsBefore) 'register-existing-1.14-accepts-supported-preserved-schema1-corrections'
        $agentsBeforeDowngrade=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $upgradeRepo 'AGENTS.md');$agentsBegin=$agentsBeforeDowngrade.IndexOf('<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->',[StringComparison]::Ordinal);$agentsEnd=$agentsBeforeDowngrade.IndexOf('<!-- AI-WORKSPACE-FRAMEWORK:END -->',[StringComparison]::Ordinal)+'<!-- AI-WORKSPACE-FRAMEWORK:END -->'.Length;$agentsOutsideBeforeDowngrade=$agentsBeforeDowngrade.Substring(0,$agentsBegin)+$agentsBeforeDowngrade.Substring($agentsEnd)
        $downgradeArgs=@('-ProjectId','upgrade-fixture','-ToVersion','1.13.0','-RepositoryPath',$upgradeRepo,'-ControllerId','controller-upgrade')
        $downgradePreview=Invoke-Ps $upgrade $downgradeArgs
        if($downgradePreview.Code-ne0-or-not$downgradePreview.Text.Contains('coverage=NO_EXACT_MAPPING_RETAINED')-or-not$downgradePreview.Text.Contains('STILL_EFFECTIVE PROJECT_CORRECTION_LIFECYCLE')-or-not$downgradePreview.Text.Contains('STILL_EFFECTIVE OWNER_FIRST_DIRECT_DOMAIN_ROUTE')){Write-Output ('DIAG|downgrade-re-evaluation|code='+$downgradePreview.Code+'|'+$downgradePreview.Text)}
        Assert-True ($downgradePreview.Code-eq0-and$downgradePreview.Text.Contains('WHAT_IF|from=1.14.0|to=1.13.0|objects=6')-and$downgradePreview.Text.Contains('STILL_EFFECTIVE PROJECT_CORRECTION_LIFECYCLE')-and$downgradePreview.Text.Contains('STILL_EFFECTIVE OWNER_FIRST_DIRECT_DOMAIN_ROUTE')) 'downgrade-1.14-to-1.13-re-evaluates-and-retains-v1-corrections'
        $downgradeApply=Invoke-Ps $upgrade @($downgradeArgs+'-Apply')
        $downgradedConfig=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeConfigPath|ConvertFrom-Json
        $downgradedBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath $upgradeBootstrapPath
        $downgradeBackendAbsent=$null-eq$downgradedConfig.PSObject.Properties['frameworkToolBackend']
        $downgradeCorrectionLocatorPresent=$downgradedBootstrap.Contains('framework/versions/1.14.0/scripts/check-project-corrections.ps1')
        $downgradeCorrectionsPreserved=(Get-Identity $upgradeCorrectionsPath)-ceq$upgradeCorrectionsBefore
        $downgradeCorrectionBlockPresent=$downgradedBootstrap.Contains('PROJECT-CORRECTIONS:BEGIN')
        Assert-True ($downgradeApply.Code-eq0) 'downgrade-apply-succeeds'
        Assert-True ([string]$downgradedConfig.frameworkVersion-ceq'1.13.0') 'downgrade-projects-target-version'
        Assert-True (-not$downgradeBackendAbsent) 'downgrade-1.13-preserves-backend-field'
        Assert-True $downgradeCorrectionBlockPresent 'downgrade-preserves-correction-bootstrap-block'
        Assert-True $downgradeCorrectionLocatorPresent 'downgrade-preserves-newest-correction-evaluator-locator'
        Assert-True $downgradeCorrectionsPreserved 'downgrade-preserves-correction-records'
        $agentsAfterDowngrade=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $upgradeRepo 'AGENTS.md')
        Assert-True (-not(Test-Path -LiteralPath (Join-Path $upgradeRepo '.agents\skills\ai-workspace-router\SKILL.md'))-and-not$agentsAfterDowngrade.Contains('AI-WORKSPACE-FRAMEWORK:BEGIN')-and$agentsAfterDowngrade-ceq$agentsOutsideBeforeDowngrade) 'downgrade-1.13-removes-only-framework-router-block-preserves-outside-bytes-exactly'
    }

    $knowledgeRoot=Join-Path $temp 'knowledge-fixture'
    New-Item -ItemType Directory -Path (Join-Path $knowledgeRoot '.ai-workspace'),(Join-Path $knowledgeRoot 'knowledge') -Force|Out-Null
    foreach($name in @('reference-1','reference-2','reference-history')){Write-Utf8 (Join-Path $knowledgeRoot ('knowledge\'+$name+'.md')) $name}
    Write-Utf8 (Join-Path $knowledgeRoot 'authority-1.md') 'authority-1'
    Write-Utf8 (Join-Path $knowledgeRoot 'authority-2.md') 'authority-2'
    Write-Utf8 (Join-Path $knowledgeRoot 'unrelated.md') 'unrelated'
    $knowledgeConfig=[ordered]@{schemaVersion=4;id='knowledge-fixture';displayName='Knowledge Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$true;indexLocator='knowledge/index.json'}};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}
    $knowledgeConfigRaw=$knowledgeConfig|ConvertTo-Json -Depth 20;$knowledgeConfigPath=Join-Path $knowledgeRoot '.ai-workspace\project.json';Write-Utf8 $knowledgeConfigPath $knowledgeConfigRaw
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
    Assert-True ($primaryPwshDiscover.Code-eq0-and$primaryPwshQuery.Code-eq0) 'knowledge-schema4-starter-shape-discover-and-query'

    $knowledgeUnicodePolicy=[regex]::Replace($knowledgeConfigRaw,'("locator"\s*:\s*"\.ai-workspace/process-policy\.json")','$1, "\u006cocator": ".ai-workspace/process-policy.json"',1)
    Write-Utf8 $knowledgeConfigPath $knowledgeUnicodePolicy
    $knowledgeUnicodePolicyArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',(Get-Identity $knowledgeConfigPath),'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-Operation','DISCOVER','-AsJson')
    $knowledgeUnicodePolicyRun=Invoke-PsHost $script:pwshExecutable $knowledgeChecker $knowledgeUnicodePolicyArgs
    Assert-True ($knowledgeUnicodePolicyRun.Code-ne0-and$knowledgeUnicodePolicyRun.Text.Contains('PROJECT_CONFIG_JSON_DUPLICATE_FIELD|locator')) 'knowledge-entry-unicode-nested-policy-duplicate-fails-closed'
    Write-Utf8 $knowledgeConfigPath $knowledgeConfigRaw

    $knowledgeUnicodeIndex=[regex]::Replace(($schema2Index|ConvertTo-Json -Depth 20),'("projectId"\s*:\s*"knowledge-fixture")','$1, "\u0070rojectId": "knowledge-fixture"',1)
    Write-Utf8 $knowledgeIndexPath $knowledgeUnicodeIndex
    $knowledgeUnicodeIndexArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',(Get-Identity $knowledgeConfigPath),'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-Operation','DISCOVER','-AsJson')
    $knowledgeUnicodeIndexRun=Invoke-PsHost $script:pwshExecutable $knowledgeChecker $knowledgeUnicodeIndexArgs
    Assert-True ($knowledgeUnicodeIndexRun.Code-ne0-and$knowledgeUnicodeIndexRun.Text.Contains('INDEX_JSON_DUPLICATE_FIELD|projectId')) 'knowledge-entry-unicode-top-level-index-duplicate-fails-closed'

    $knowledgeUnicodeDependency=[regex]::Replace(($schema2Index|ConvertTo-Json -Depth 20),'("locator"\s*:\s*"authority-1\.md")','$1, "\u006cocator": "authority-1.md"',1)
    Write-Utf8 $knowledgeIndexPath $knowledgeUnicodeDependency
    $knowledgeUnicodeDependencyArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',(Get-Identity $knowledgeConfigPath),'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath),'-Operation','QUERY','-EntryId','REF-1','-AsJson')
    $knowledgeUnicodeDependencyRun=Invoke-PsHost $script:pwshExecutable $knowledgeChecker $knowledgeUnicodeDependencyArgs
    Assert-True ($knowledgeUnicodeDependencyRun.Code-ne0-and$knowledgeUnicodeDependencyRun.Text.Contains('INDEX_JSON_DUPLICATE_FIELD|locator')) 'knowledge-entry-unicode-nested-dependency-duplicate-fails-closed'
    Write-Utf8 $knowledgeIndexPath ($schema2Index|ConvertTo-Json -Depth 20)

    $knowledgeInvalidPolicy=$knowledgeConfigRaw|ConvertFrom-Json;$knowledgeInvalidPolicy.processPolicy.locator='.ai-workspace/other-policy.json';Write-Utf8 $knowledgeConfigPath ($knowledgeInvalidPolicy|ConvertTo-Json -Depth 20)
    $knowledgeInvalidPolicyArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',(Get-Identity $knowledgeConfigPath),'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath))
    $knowledgeInvalidEntry=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeInvalidPolicyArgs+@('-Operation','DISCOVER','-AsJson'))
    $knowledgeInvalidImpact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact @($knowledgeInvalidPolicyArgs+@('-ChangedAuthorityPath','authority-1.md','-AsJson'))
    Assert-True ($knowledgeInvalidEntry.Code-ne0-and$knowledgeInvalidEntry.Text.Contains('PROJECT_CONFIG_PROCESS_POLICY')) 'knowledge-schema4-invalid-policy-entry-fails-closed'
    Assert-True ($knowledgeInvalidImpact.Code-ne0-and$knowledgeInvalidImpact.Text.Contains('PROJECT_CONFIG_PROCESS_POLICY')) 'knowledge-schema4-invalid-policy-impact-fails-closed'
    Write-Utf8 $knowledgeConfigPath $knowledgeConfigRaw;$knowledgeConfigIdentity=Get-Identity $knowledgeConfigPath;$knowledgeBaseArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath))
    $knowledgeSchema3=$knowledgeConfigRaw|ConvertFrom-Json;$knowledgeSchema3.schemaVersion=3;$knowledgeSchema3.PSObject.Properties.Remove('processPolicy');Write-Utf8 $knowledgeConfigPath ($knowledgeSchema3|ConvertTo-Json -Depth 20)
    $knowledgeSchema3Args=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',(Get-Identity $knowledgeConfigPath),'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath))
    $knowledgeSchema3Entry=Invoke-PsHost $script:pwshExecutable $knowledgeChecker @($knowledgeSchema3Args+@('-Operation','DISCOVER','-AsJson'))
    $knowledgeSchema3Impact=Invoke-PsHost $script:pwshExecutable $knowledgeImpact @($knowledgeSchema3Args+@('-ChangedAuthorityPath','authority-1.md','-AsJson'))
    Assert-True ($knowledgeSchema3Entry.Code-eq0-and$knowledgeSchema3Impact.Code-eq0) 'knowledge-schema3-project-entry-and-impact-compatible'
    Write-Utf8 $knowledgeConfigPath $knowledgeConfigRaw;$knowledgeConfigIdentity=Get-Identity $knowledgeConfigPath;$knowledgeBaseArgs=@('-ProjectRoot',$knowledgeRoot,'-ExpectedProjectConfigIdentity',$knowledgeConfigIdentity,'-ExpectedIndexIdentity',(Get-Identity $knowledgeIndexPath))
    $pwsh=[pscustomobject]@{Source=$script:pwshExecutable}
    if($null-ne$pwsh){
        $ps7Correction=Invoke-PsHost $pwsh.Source $correctionChecker $correctionArgs
        Assert-True ($ps7Correction.Code-eq0-and$ps7Correction.Text.Contains('"coverageStatus":"MATCHED_EXACT_MAPPING"')) 'corrections-ps7-incorporated-vs-still-effective'
        Write-Utf8 $correctionPath $correctionDuplicate
        try{$ps7CorrectionDuplicate=Invoke-PsHost $pwsh.Source $correctionChecker @('-ProjectRoot',$correctionRoot,'-FrameworkRoot',$correctionFrameworkRoot,'-TargetVersion','1.16.0','-ExpectedProjectConfigIdentity',(Get-Identity $correctionConfigPath),'-ExpectedCorrectionsIdentity',(Get-Identity $correctionPath),'-Operation','PRECHECK','-AsJson')}
        finally{Write-Utf8 $correctionPath $correctionOriginal}
        Assert-True ($ps7CorrectionDuplicate.Code-ne0-and$ps7CorrectionDuplicate.Text.Contains('JSON_DUPLICATE_FIELD')) 'corrections-ps7-unicode-duplicate-field-fails-closed'
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
        $stableBaselineRoot=Join-Path $frameworkRoot 'versions\1.15.1'
        $stableBaselineManifest=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $stableBaselineRoot 'RELEASE_MANIFEST.json')|ConvertFrom-Json
        $stableBaselineFacts=Get-ReleasePayloadFacts $stableBaselineRoot
        Assert-True ([string]$stableBaselineManifest.lifecycle-ceq'STABLE'-and[int]$stableBaselineManifest.fileCount-eq$stableBaselineFacts.FileCount-and[int64]$stableBaselineManifest.totalBytes-eq$stableBaselineFacts.TotalBytes-and[string]$stableBaselineManifest.canonical-ceq$stableBaselineFacts.Canonical-and[string]$stableBaselineManifest.canonical-ceq'AC808DA9653FA7B731D1AF02328FF9F6931F80B48437FF31CBD6DECA90018E82') 'baseline-1.15.1-immutable-stable-seal'
        $directBaselineRoot=Join-Path $frameworkRoot 'versions\1.15.0'
        $directBaselineManifest=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $directBaselineRoot 'RELEASE_MANIFEST.json')|ConvertFrom-Json
        $directBaselineFacts=Get-ReleasePayloadFacts $directBaselineRoot
        Assert-True ([string]$directBaselineManifest.lifecycle-ceq'STABLE'-and[int]$directBaselineManifest.fileCount-eq$directBaselineFacts.FileCount-and[int64]$directBaselineManifest.totalBytes-eq$directBaselineFacts.TotalBytes-and[string]$directBaselineManifest.canonical-ceq$directBaselineFacts.Canonical-and[string]$directBaselineManifest.canonical-ceq'1408C9555955482651DD3EFD544A8AD36797CB04DFC52990E861C151220B076F') 'direct-source-1.15.0-immutable-stable-seal'
        $compatBaselineRoot=Join-Path $frameworkRoot 'versions\1.14.1'
        $compatBaselineManifest=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $compatBaselineRoot 'RELEASE_MANIFEST.json')|ConvertFrom-Json
        $compatBaselineFacts=Get-ReleasePayloadFacts $compatBaselineRoot
        Assert-True ([string]$compatBaselineManifest.lifecycle-ceq'STABLE'-and[int]$compatBaselineManifest.fileCount-eq$compatBaselineFacts.FileCount-and[int64]$compatBaselineManifest.totalBytes-eq$compatBaselineFacts.TotalBytes-and[string]$compatBaselineManifest.canonical-ceq$compatBaselineFacts.Canonical-and[string]$compatBaselineManifest.canonical-ceq'547422DE8C0FE8214CA7B1B4980B97FEF065061B8146CA913650613F241693A6') 'compatibility-baseline-1.14.1-immutable-stable-seal'
    }

    if (-not $SkipManifest) {
        $manifest = Get-Content -LiteralPath (Join-Path $candidateRoot 'RELEASE_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $facts=Get-ReleasePayloadFacts $candidateRoot
        $payloadRowsStable=($facts.Rows-join"`n")-ceq($initialPayloadFacts.Rows-join"`n")
        $manifestOk = $payloadRowsStable -and [int]$manifest.fileCount -eq $initialPayloadFacts.FileCount -and [int64]$manifest.totalBytes -eq $initialPayloadFacts.TotalBytes -and [string]$manifest.canonical -ceq $initialPayloadFacts.Canonical
        if (-not $manifestOk) { Write-Output ('DIAG|manifest|initial=' + $initialPayloadFacts.FileCount + '|' + $initialPayloadFacts.TotalBytes + '|' + $initialPayloadFacts.Canonical + '|finalRowsStable=' + $payloadRowsStable + '|declared=' + $manifest.fileCount + '|' + $manifest.totalBytes + '|' + $manifest.canonical) }
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
$resultScope=if($resultSealed){'Framework-1.16.0-stable'}else{'Framework-1.16.0-candidate'}
$resultLifecycle=if($resultSealed){'SEALED'}else{'PENDING_SEAL'}
Write-Output ("RESULT|" + $script:passed + "/" + $script:passed + " passed|scope="+$resultScope+"|lifecycle="+$resultLifecycle)
