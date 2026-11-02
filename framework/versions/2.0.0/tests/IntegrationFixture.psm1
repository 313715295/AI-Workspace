# Private integration fixtures. Each child owns a new short mutable root;
# only immutable Source payload bytes are shared. No completed journal or
# authorization package crosses a domain boundary.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
$script:pwshExecutable=[Environment]::ProcessPath
$script:passed=0
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

# Tests explicitly project supported old object inputs before current invocation.
# This is isolated fixture preparation, not a live adoption or resolver fallback.
function Write-CurrentFixtureObject([string]$Type,[string]$Path,$Value,[switch]$PassThru) {
    Import-Module (Join-Path $candidateRoot 'scripts/ObjectFormats.psm1') -Force
    $legacyPath=$Path+'.fixture-source.json'
    Write-Utf8 $legacyPath ($Value|ConvertTo-Json -Depth 100)
    $context=[pscustomobject]@{SourceBindings=@();ForbiddenPaths=@();TargetProcessContractVersion='2.0.0'}
    $projection=Read-AiwCurrentObject -ObjectType $Type -Locator $legacyPath -ExpectedIdentity (Get-Identity $legacyPath) -Context $context
    [IO.File]::WriteAllBytes($Path,$projection.CurrentBytes)
    if($PassThru){return $projection}
}
function New-CurrentFixtureIntent($Value) {
    $intent=$Value|ConvertTo-Json -Depth 30|ConvertFrom-Json
    $intent.schemaVersion=2
    $intent|Add-Member facets ([pscustomobject]@{
        domain=[pscustomobject]@{state='UNKNOWN';values=@()}
        workType=[pscustomobject]@{state='UNKNOWN';values=@()}
        deliverableType=[pscustomobject]@{state='UNKNOWN';values=@()}
        stage=[pscustomobject]@{state='UNKNOWN';values=@()}
    })
    return $intent
}
function Get-BytesIdentity([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return $Bytes.Length.ToString() + '|' + ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
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
    $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
    return & $reader.ExportedCommands['Get-AiwReleasePayloadFacts'] $VersionRoot
}

function Get-ReleaseValidationState($Version,$Manifest,$Facts,[bool]$SkipManifestValidation) {
    $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
    if($Manifest.schemaVersion-eq2){return & $reader.ExportedCommands['Get-AiwReleaseSchema2State'] $Version $Manifest $Facts $SkipManifestValidation}
    throw 'PREPACKAGE_SCHEMA3_REQUIRES_SOURCE_PAYLOAD_VIEW'
}

function Seal-ReleaseFixture([string]$VersionRoot,[string]$Integration) {
    $versionPath=Join-Path $VersionRoot 'VERSION.json';$version=Get-Content -Raw -Encoding utf8 -LiteralPath $versionPath|ConvertFrom-Json
    $version.lifecycle='STABLE';$version.consumable=$true;$version.projectPinEligible=$true
    Write-Utf8 $versionPath ($version|ConvertTo-Json -Depth 20)
    $loadPath=Join-Path $VersionRoot 'LOAD_MANIFEST.json';$load=Get-Content -Raw -Encoding utf8 -LiteralPath $loadPath|ConvertFrom-Json
    $load.lifecycle='STABLE';Write-Utf8 $loadPath ($load|ConvertTo-Json -Depth 30)
    $facts=Get-ReleasePayloadFacts $VersionRoot
    $manifestPath=Join-Path $VersionRoot 'RELEASE_MANIFEST.json';$reviewedManifestIdentity=Get-Identity $manifestPath;$manifest=Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath|ConvertFrom-Json
    $manifest.PSObject.Properties.Remove('validationProof');$manifest.schemaVersion=2;$manifest.scope='all release payload files except RELEASE_MANIFEST.json';$manifest.lifecycle='STABLE';$manifest.fileCount=$facts.FileCount;$manifest.totalBytes=$facts.TotalBytes;$manifest.canonical=$facts.Canonical;$manifest.sourceReview='APPROVED';$manifest.sourceCandidate='TEST_FIXTURE_CANDIDATE'
    $manifest|Add-Member -NotePropertyName completeSuite -NotePropertyValue ([pscustomobject][ordered]@{status='PASS';passed=1;total=1;payloadCanonical=$facts.Canonical;evidenceIdentity=('1|'+('A'*64))}) -Force
    $manifest|Add-Member -NotePropertyName sourceReviewEvidence -NotePropertyValue ([pscustomobject][ordered]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$facts.Canonical;reviewedManifestIdentity=$reviewedManifestIdentity}) -Force
    $manifest.releaseIntegration=$Integration
    Write-Utf8 $manifestPath ($manifest|ConvertTo-Json -Depth 20)
    return $facts
}

# Match the existing non-git-adoption test builder: all runtime bytes belong
# to one named package, with no developer Git or project control plane.
function Seal-MaintenanceRuntimeFixture([string]$Root) {
    [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'PACKAGE_MANIFEST.json'})
    [Array]::Sort($paths,[StringComparer]::Ordinal)
    $files=@();$rows=@()
    foreach($relative in $paths){$identity=Get-Identity (Join-Path $Root $relative);$files+=@([ordered]@{path=$relative;identity=$identity});$rows+=($relative+'='+$identity)}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join[char]10)+[char]10)))
    Write-Utf8 (Join-Path $Root 'PACKAGE_MANIFEST.json') ([ordered]@{schemaVersion=2;frameworkVersion='2.0.0';provisional=$false;canonical=$canonical;files=$files;distributionId='2.0.0-release'}|ConvertTo-Json -Depth 20)
}
function Approve-CandidateReleaseFixture([string]$VersionRoot) {
    $versionPath=Join-Path $VersionRoot 'VERSION.json';$version=Get-Content -Raw -Encoding utf8 -LiteralPath $versionPath|ConvertFrom-Json
    $version.lifecycle='CANDIDATE';$version.consumable=$false;$version.projectPinEligible=$false
    Write-Utf8 $versionPath ($version|ConvertTo-Json -Depth 20)
    $loadPath=Join-Path $VersionRoot 'LOAD_MANIFEST.json';$load=Get-Content -Raw -Encoding utf8 -LiteralPath $loadPath|ConvertFrom-Json
    $load.lifecycle='CANDIDATE';Write-Utf8 $loadPath ($load|ConvertTo-Json -Depth 30)
    $facts=Get-ReleasePayloadFacts $VersionRoot
    $manifestPath=Join-Path $VersionRoot 'RELEASE_MANIFEST.json';$reviewedManifestIdentity=Get-Identity $manifestPath;$manifest=Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath|ConvertFrom-Json
    $manifest.PSObject.Properties.Remove('validationProof');$manifest.schemaVersion=2;$manifest.scope='all release payload files except RELEASE_MANIFEST.json';$manifest.lifecycle='CANDIDATE';$manifest.fileCount=$facts.FileCount;$manifest.totalBytes=$facts.TotalBytes;$manifest.canonical=$facts.Canonical;$manifest.sourceReview='APPROVED';$manifest.sourceCandidate='TEST_FIXTURE_REVIEWED_CANDIDATE';$manifest.releaseIntegration='PENDING'
    $manifest.completeSuite=[pscustomobject][ordered]@{status='PASS';passed=1;total=1;payloadCanonical=$facts.Canonical;evidenceIdentity=('1|'+('A'*64))}
    $manifest.sourceReviewEvidence=[pscustomobject][ordered]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$facts.Canonical;reviewedManifestIdentity=$reviewedManifestIdentity}
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
        try { $run=Invoke-AiwTestProcess $script:pwshExecutable @(@('-NoProfile','-NonInteractive','-File',$Script)+$effectiveArguments) -WorkingDirectory $(if($WorkingDirectory){$WorkingDirectory}else{(Get-Location).Path});$output=@($run.Output);$code=$run.Code }
        finally { $ErrorActionPreference = $old }
        return [pscustomobject]@{ Code=$code; Output=$output; Text=($output -join "`n"); Record=$run.Record; ResultPath=$run.ResultPath; Stdout=$run.StdoutText; Stderr=$run.StderrText }
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
        try { $run=Invoke-AiwTestProcess $Executable @($hostArguments+@('-File',$Script)+$Arguments) -WorkingDirectory $(if($WorkingDirectory){$WorkingDirectory}else{(Get-Location).Path});$output=@($run.Output);$code=$run.Code }
        finally { $ErrorActionPreference = $old }
        return [pscustomobject]@{ Code=$code; Output=$output; Text=($output -join "`n"); Record=$run.Record; ResultPath=$run.ResultPath; Stdout=$run.StdoutText; Stderr=$run.StderrText }
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
    $wrapper=(@'
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PayloadPath)
__AIW_TEST_NATIVE_OUTPUT__
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
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput'))
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

function Get-PrivateFixtureCleanupPath([string]$Path,[string]$ExpectedParent,[string]$LeafPattern,[string]$Label) {
    $full=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
    $parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ExpectedParent))
    if([IO.Path]::GetDirectoryName($full)-cne$parent-or[IO.Path]::GetFileName($full)-cnotmatch$LeafPattern){throw ('FIXTURE_CLEANUP_BOUNDARY|'+$Label)}
    return $full
}

# Walk only physical entries in this test's isolated fixture, never through a junction.
function Get-PhysicalFixtureTree([string]$Root) {
    $full=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
    $fixture=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp))
    if(-not$full.StartsWith($fixture+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'FIXTURE_TREE_BOUNDARY'}
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($full)
    $rows=[Collections.Generic.List[string]]::new()
    while($pending.Count){
        $directory=$pending.Pop();$item=Get-Item -LiteralPath $directory -Force
        if(-not$item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'FIXTURE_TREE_NOT_PHYSICAL'}
        $rows.Add('D|'+[IO.Path]::GetRelativePath($full,$directory).Replace('\','/')+'|'+[string]$item.Attributes)
        foreach($child in @(Get-ChildItem -LiteralPath $directory -Force)){
            if($child.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'FIXTURE_TREE_REPARSE'}
            if($child.PSIsContainer){$pending.Push($child.FullName)}
            else{$rows.Add('F|'+[IO.Path]::GetRelativePath($full,$child.FullName).Replace('\','/')+'|'+[string]$child.Attributes+'|'+(Get-Identity $child.FullName))}
        }
    }
    [string[]]$ordered=$rows.ToArray();[Array]::Sort($ordered,[StringComparer]::Ordinal)
    return ($ordered-join "`n")
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
        $text = $text.Replace('{{FRAMEWORK_VERSION}}','2.0.0')
        $text = $text.Replace('{{CONTROL_PLANE_LAYOUT}}','framework-maintenance-sibling')
        $text = $text.Replace('{{CONTROLLER_ID}}','controller-fixture')
        $text = $text.Replace('{{PROCESS_CONTRACT_VERSION_JSON}}','"2.0.0"')
        $text = $text.Replace('{{PROJECT_ID_JSON}}','"framework-maintenance-fixture"')
        $text = $text.Replace('{{CONTROLLER_ID_JSON}}','"controller-fixture"')
        $text = $text.Replace('{{SELECTED_RULE_PACK_BYTES}}','32768')
        $text = $text.Replace('{{CREATED_DATE}}','2026-09-03')
        Write-Utf8 $_.FullName $text
    }
    $config=[ordered]@{schemaVersion=7;id='framework-maintenance-fixture';displayName='Framework Maintenance Fixture';controlPlaneLayout='framework-maintenance-sibling';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'};frameworkTarget=[ordered]@{repositoryId='ai-workspace-framework';siblingDirectory='AI-Workspace';routineExcludedPaths=@()}}
    Write-Utf8 (Join-Path $destination 'project.json') ($config|ConvertTo-Json -Depth 20)
    $agentsPath=Join-Path $ControlRoot 'AGENTS.md';$agents=Get-Content -LiteralPath $agentsPath -Raw -Encoding utf8;$agents=$agents.Replace('{{PROJECT_ID}}','framework-maintenance-fixture').Replace('{{DISPLAY_NAME}}','Framework Maintenance Fixture').Replace('{{FRAMEWORK_VERSION}}','2.0.0');Write-Utf8 $agentsPath $agents
    return $destination
}

function New-AuthorizationPackage(
    [string]$Path,[int]$Schema,[string]$RepositoryId,[string]$ConfigIdentity,
    [string[]]$Actions,[string]$ExactPath,[string]$ObjectIdentity,[switch]$DomainOwner,[string[]]$ContinuationPlan=@()
) {
    $issuer = if ($DomainOwner) { 'owner-fixture' } else { 'controller-fixture' }
    $taskId = if ($DomainOwner) { 'FIXTURE-OWNER-001' } else { 'FIXTURE-001' }
    $taskRelative='.ai-workspace/tasks/active/'+$taskId+'.md'
    $controlRoot=Split-Path -Parent $Path
    $taskFull=Join-Path (Split-Path -Parent $controlRoot) $taskRelative
    Write-Utf8 $taskFull ("# $taskId - authorization fixture`n`n- Task schema: 2.0.0`n- Owner: $issuer`n- Work route: actor=$issuer; role="+$(if($DomainOwner){'TASK_OWNER'}else{'CONTROLLER'})+"; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n")
    $taskIdentity=Get-Identity $taskFull
    $package = [ordered]@{
        schemaVersion=$Schema; frameworkVersion='2.0.0'; taskId=$taskId; taskIdentity=$taskIdentity; profile='STANDARD'; lifecycle='ACTIVE'
        owner=$issuer; issuer=$issuer; issuerRole=$(if($DomainOwner){'TASK_OWNER'}else{'PROJECT_CONTROLLER'})
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
    if($ContinuationPlan.Count-gt0){$package.continuationPlan=@($ContinuationPlan);$package.invalidatesOn+='CONTINUATION_RESULT_DRIFT'}
    Write-Utf8 $Path ($package | ConvertTo-Json -Depth 20)
}

function Set-PackageProjectConfigIdentity([string]$Path,[string]$Identity) {
    $package=Get-Content -LiteralPath $Path -Raw -Encoding utf8|ConvertFrom-Json
    $package.projectConfigIdentity=$Identity
    Write-Utf8 $Path ($package|ConvertTo-Json -Depth 20)
}

function New-MaintenanceUpgradeAuthorizationPackage([string]$Path,[string]$ConfigIdentity,[string]$ObjectPath,[string]$ObjectIdentity) {
    $taskPath=Join-Path (Split-Path -Parent (Split-Path -Parent $Path)) '.ai-workspace/tasks/active/FIXTURE-001.md'
    $package=[ordered]@{schemaVersion=3;frameworkVersion='2.0.0';taskId='FIXTURE-001';taskIdentity=(Get-Identity $taskPath);profile='CRITICAL';lifecycle='ACTIVE';owner='controller-fixture';issuer='controller-fixture';issuerRole='PROJECT_CONTROLLER';grantee='controller-fixture';bundle='ACTOR_BOUND_PROJECT_UPGRADE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='USER_FIXTURE_APPROVED_MAINTENANCE_UPGRADE';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;actions=@('CONTROL_WRITE');exactPaths=@($ObjectPath);objectIdentities=@([ordered]@{path=$ObjectPath;identity=$ObjectIdentity});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE','POST_OBJECT_DRIFT');projectConfigIdentity=$ConfigIdentity;issuerControllerId='controller-fixture';issuerControllerEpoch=1;controllerControlIdentity=(Get-Identity (Join-Path (Split-Path -Parent $Path) 'controller.json'));postObjectIdentities=@([ordered]@{path=$ObjectPath;identity=('1|'+('A'*64))});targetFrameworkSnapshot=[ordered]@{canonical=('B'*64);manifestIdentity=('1|'+('C'*64))}}
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
function Get-IntegrationCheckCount { return $script:passed }
function New-IntegrationContext([string]$VersionRoot,[ValidateSet('surface','maintenance','authorization','process','flow')][string]$Domain) {
 $script:candidateRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($VersionRoot))
 $script:utf8=[Text.UTF8Encoding]::new($false);$script:utf8Strict=[Text.UTF8Encoding]::new($false,$true)
 $script:testJunctions=[Collections.Generic.List[string]]::new()
 $parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
 $script:temp=Join-Path $parent ('aiw-int-'+(@{surface='s';maintenance='m';authorization='a';process='p';flow='f'}[$Domain])+'-'+[guid]::NewGuid().ToString('N'))
 $cleanup=Get-PrivateFixtureCleanupPath $script:temp $parent '^aiw-int-[smapf]-[0-9a-f]{32}$' 'INTEGRATION'
 $framework=[IO.Path]::GetFullPath((Join-Path $script:candidateRoot '../..'))
 $root=Split-Path -Parent $framework
 $actual=@(Get-ChildItem -LiteralPath $script:candidateRoot -Recurse -Force -File|ForEach-Object{[IO.Path]::GetRelativePath($script:candidateRoot,$_.FullName).Replace('\','/')});[Array]::Sort($actual,[StringComparer]::Ordinal)
 $manifestPath=Join-Path $script:candidateRoot 'RELEASE_MANIFEST.json'
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
 $version=Get-Content -LiteralPath (Join-Path $script:candidateRoot 'VERSION.json') -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
 if($manifest.schemaVersion-ne2){throw 'PREPACKAGE_SCHEMA3_REQUIRES_SOURCE_PAYLOAD_VIEW'}
 $facts=Get-ReleasePayloadFacts $script:candidateRoot
 $state=Get-ReleaseValidationState $version $manifest $facts $false
 $starterText=Get-Content -LiteralPath (Join-Path $script:candidateRoot 'project-starter/project.json') -Raw -Encoding utf8
 $budget=Get-Content -LiteralPath (Join-Path $script:candidateRoot 'tests/PROCESS_REQUIREMENTS_BUDGETS.json') -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
 New-Item -ItemType Directory -Path $script:temp|Out-Null
 return @{candidateRoot=$script:candidateRoot;liveFrameworkRoot=$framework;liveRepositoryRoot=$root;maintenanceOverlayRoot=(Join-Path $framework 'maintenance-overlay');temp=$script:temp;tempCleanup=$cleanup;tempParent=$parent;utf8=$script:utf8;utf8Strict=$script:utf8Strict;'script:testJunctions'=$script:testJunctions;actual=$actual;initialManifestPath=$manifestPath;initialManifestIdentity=(Get-Identity $manifestPath);initialManifest=$manifest;initialVersion=$version;version=$version;initialPayloadFacts=$facts;initialReleaseState=$state;projectStarterText=$starterText;budgetContract=$budget}
}
function Close-IntegrationContext($Context) {
 foreach($junction in @($script:testJunctions.ToArray())){Remove-TestJunction $junction}
 $bound=Get-PrivateFixtureCleanupPath $Context.temp $Context.tempParent '^aiw-int-[smapf]-[0-9a-f]{32}$' 'INTEGRATION'
 if(Test-Path -LiteralPath $bound){
  # Reject any surviving link before the physical cleanup walk.
  $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($bound)
  while($pending.Count){$directory=$pending.Pop();foreach($entry in Get-ChildItem -LiteralPath $directory -Force){if($entry.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'INTEGRATION_CLEANUP_REPARSE'};if($entry.PSIsContainer){$pending.Push($entry.FullName)};$entry.Attributes=[IO.FileAttributes]::Normal}}
  Remove-Item -LiteralPath $bound -Recurse -Force
 }
 if(Test-Path -LiteralPath $bound){throw 'INTEGRATION_CLEANUP_INCOMPLETE'}
 Write-Output 'FIXTURE_CLEAN|integration-private-root'
}
function New-IntegrationRuntimeFixture([string]$Destination,[switch]$Maintenance) {
 $source=Split-Path -Parent ([IO.Path]::GetFullPath((Join-Path $script:candidateRoot '../..')))
 $definition=Get-Content -LiteralPath (Join-Path $script:candidateRoot 'tests/test-groups.json') -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
 $paths=@((Get-ReleasePayloadFacts $script:candidateRoot).Files)
 $rootPaths=if($Maintenance){@($definition.rootAdoptionPaths)+@($definition.maintenancePaths)+@('README.md','skills/ai-workspace-router/SKILL.md')}else{@()}
 $rootPaths=@($rootPaths|Select-Object -Unique)
 $fixture=New-AiwTestRuntimeFixture -SourceRoot $source -DestinationRoot $Destination -VersionPaths $paths -RootPaths $rootPaths
 if($Maintenance){
  Copy-Item -LiteralPath (Join-Path $source 'framework/user-package/AGENTS.md') -Destination (Join-Path $Destination 'AGENTS.md')
  Seal-MaintenanceRuntimeFixture $Destination
 }
 return [string]$fixture
}
function Assert-IntegrationRegistrationResult($Run,$Context) {
 if($Run.Code-ne0-or$Run.Stderr-cne''){throw ('INTEGRATION_REGISTER_NATIVE|'+$Run.Code+'|'+$Run.Text)}
 $reply=$Run.Stdout.Trim()|ConvertFrom-Json -Depth 100
 $fields=@('status','projectRoot','frameworkVersion','controlPlaneLayout','projectFormat','rootToolRevision','transaction','createdFiles','nextAction')
 if(@($reply.PSObject.Properties).Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$reply.PSObject.Properties.Name}).Count){throw 'INTEGRATION_REGISTER_COMPLETE_FIELDS'}
 $journalPath=Join-Path $Context.control '.ai-workspace/runtime/project-adoption/register/state.json'
 $journal=Get-Content -LiteralPath $journalPath -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
 $paths=@($journal.projection.objects|Where-Object kind -CEQ FILE|ForEach-Object path)
 if($reply.status-cne'CREATED'-or$reply.projectRoot-cne(Join-Path $Context.control '.ai-workspace')-or$reply.frameworkVersion-cne'2.0.0'-or$reply.controlPlaneLayout-cne'framework-maintenance-sibling'){throw 'INTEGRATION_REGISTER_COMPLETE_VALUES'}
 $config=Get-Content -LiteralPath (Join-Path $Context.control '.ai-workspace/project.json') -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
 if($reply.projectFormat-cne('repo-local/project-config-'+$config.schemaVersion)-or$reply.rootToolRevision-cne$journal.metadata.rootToolRevision-or$reply.nextAction-cne'AI session completes project-specific facts, validates FULL_COLD_RECOVERY for the selected layout, then reports READY or NEEDS_INPUT.'){throw 'INTEGRATION_REGISTER_COMPLETE_METADATA'}
 if($reply.createdFiles-isnot[Array]-or$reply.createdFiles.Count-le4-or($reply.createdFiles-join"`n")-cne($paths-join"`n")){throw 'INTEGRATION_REGISTER_COMPLETE_ARRAY'}
 if(@($reply.transaction.PSObject.Properties).Count-ne4-or$reply.transaction.status-cne'COMPLETE'-or-not$reply.transaction.transactionCreated-or$reply.transaction.writes-ne$journal.completedWrites-or$reply.transaction.transactionIdentity-cne(Get-Identity $journalPath)-or$journal.state-cne'COMPLETE'-or-not$journal.transactionComplete){throw 'INTEGRATION_REGISTER_COMPLETE_TRANSACTION'}
 foreach($path in $paths){if(-not[IO.File]::Exists((Join-Path $Context.control $path))){throw ('INTEGRATION_REGISTER_PROJECTION_MEMBER|'+$path)}}
 # Keep constructor success output as its original single context object.
 Assert-True $true 'maintenance-register-complete-native-JSON-fields-arrays-and-transaction' | ForEach-Object {Write-Host $_}
}
function New-IntegrationMaintenanceFixture([switch]$Register) {
    $pair = Join-Path $temp 'Framework-Workspace'
    $control = Join-Path $pair 'AI-Workspace-Maintenance'
    $target = Join-Path $pair 'AI-Workspace'
    $targetControlFixturePath=Get-PrivateFixtureCleanupPath (Join-Path $target '.ai-workspace') $target '^\.ai-workspace$' 'TARGET_CONTROL'
    $pairGitFixturePath=Get-PrivateFixtureCleanupPath (Join-Path $pair '.git') $pair '^\.git$' 'WORKSPACE_PARENT_GIT'
    $pairControlFixturePath=Get-PrivateFixtureCleanupPath (Join-Path $pair '.ai-workspace') $pair '^\.ai-workspace$' 'WORKSPACE_PARENT_CONTROL'
    New-GitRepo $control
    New-GitRepo $target
 Write-Utf8 (Join-Path $target 'README.md') '# AI-Workspace fixture'
 $fixedRuntime=Join-Path $temp 'maintenance-runtime'
 $installedFramework=New-IntegrationRuntimeFixture $fixedRuntime -Maintenance
 $maintenanceRegister=Join-Path $fixedRuntime 'scripts/register-project.ps1'
 $registerArgs=@('-ProjectId','framework-maintenance-fixture','-DisplayName','Framework Maintenance Fixture','-RepositoryPath',$control,'-FrameworkVersion','2.0.0','-ControllerId','controller-fixture','-WorkspaceRoot',$fixedRuntime,'-ControlPlaneLayout','framework-maintenance-sibling','-FrameworkTargetRepositoryId','ai-workspace-framework','-FrameworkTargetSiblingDirectory','AI-Workspace','-Apply')
 $runtimeManifestPath=Join-Path $fixedRuntime 'PACKAGE_MANIFEST.json'
 $context=@{pair=$pair;control=$control;target=$target;targetControlFixturePath=$targetControlFixturePath;pairGitFixturePath=$pairGitFixturePath;pairControlFixturePath=$pairControlFixturePath;fixedRuntime=$fixedRuntime;installedFramework=$installedFramework;maintenanceRegister=$maintenanceRegister;registerArgs=$registerArgs;runtimeManifestPath=$runtimeManifestPath;runtimeManifestBytes=[IO.File]::ReadAllBytes($runtimeManifestPath)}
 if($Register){
  $registered=Invoke-Ps $maintenanceRegister $registerArgs
  Assert-IntegrationRegistrationResult $registered $context
  $context.registeredMaintenance=$registered
  $completed=Complete-IntegrationMaintenanceFixture $context
  foreach($key in $completed.Keys){$context[$key]=$completed[$key]}
 }
 return $context
}
Export-ModuleMember -Function Assert-IntegrationRegistrationResult
function Complete-IntegrationMaintenanceFixture($Context) {
 $control=$Context.control;$target=$Context.target;$fixedRuntime=$Context.fixedRuntime
    $controlPlane=Join-Path $control '.ai-workspace'
    $adoptionStatePath=Join-Path $controlPlane 'runtime/project-adoption/register/state.json'
    $adoptionState=Get-Content -LiteralPath $adoptionStatePath -Raw -Encoding utf8|ConvertFrom-Json
    $configPath = Join-Path $controlPlane 'project.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
    $config.routineExcludedPaths = @('.ai-workspace/private.txt')
    $config.frameworkTarget.routineExcludedPaths = @('private/secret.txt')
    Write-Utf8 $configPath ($config | ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $control '.ai-workspace\private.txt') 'control private'
    # Source objects stay separate from the registered runtime bytes.
    Write-Utf8 (Join-Path $target 'docs\public.txt') 'public target'
    Write-Utf8 (Join-Path $target 'private\secret.txt') 'private target'
    $configIdentity = Get-Identity $configPath

    $installedFramework = Join-Path $fixedRuntime 'framework\versions\2.0.0'
    $installedActual = @(Get-ChildItem -LiteralPath $installedFramework -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($installedFramework.Length + 1).Replace('\','/') })
    [Array]::Sort($installedActual,[StringComparer]::Ordinal)
    $resolver = Join-Path $fixedRuntime 'scripts\resolve-framework-maintenance-target.ps1'
    $checker = Join-Path $fixedRuntime 'scripts\check-framework-maintenance-authorization.ps1'
    $controlObject = '.ai-workspace/tasks/README.md'
    $targetObject = 'docs/public.txt'
    $controllerPath = Join-Path $controlPlane 'controller.json'
 if(-not$adoptionState.transactionComplete-or$adoptionState.state-cne'COMPLETE'-or$adoptionState.metadata.distributionBinding.runtimeRoot-cne$fixedRuntime-or$adoptionState.metadata.distributionBinding.manifestIdentity-cne(Get-Identity $Context.runtimeManifestPath)){throw 'INTEGRATION_REGISTER_JOURNAL_BASELINE'}
 return @{controlPlane=$controlPlane;adoptionStatePath=$adoptionStatePath;adoptionState=$adoptionState;configPath=$configPath;config=$config;configIdentity=$configIdentity;installedFramework=$installedFramework;installedActual=$installedActual;resolver=$resolver;checker=$checker;controlObject=$controlObject;targetObject=$targetObject;controllerPath=$controllerPath}
}
function Assert-IntegrationMaintenanceBaseline($Fixture,[string]$Stage) {
 $run=Invoke-Ps $Fixture.resolver @('-ControlRepositoryPath',$Fixture.control,'-ExpectedProjectConfigIdentity',$Fixture.configIdentity,'-AsJson')
 if($run.Code-ne0){throw ('INTEGRATION_MAINTENANCE_BASELINE|'+$Stage+'|'+$run.Text)}
 $value=$run.Text|ConvertFrom-Json -Depth 100
 if($value.status-cne'PASS'-or$value.targetRepositoryId-cne'ai-workspace-framework'){throw ('INTEGRATION_MAINTENANCE_BASELINE_SHAPE|'+$Stage)}
 Write-Output ('BASELINE|maintenance|'+$Stage)
}
function Get-IntegrationResolverFailure($Run,[string]$Name) {
 $raw=$Run.Text.Trim();$prefix='FAIL|framework-maintenance-target|'
 # This is the supported outer FAIL result; the reason diagnoses the reached
 # stage. It does not claim that a particular inner guard was reached.
 if($Run.Code-ne2-or$Run.Output.Count-ne1-or-not$raw.StartsWith($prefix,[StringComparison]::Ordinal)-or$raw.Substring($prefix.Length)-cnotmatch'^[A-Z][A-Z0-9_]*(?:\|[^\r\n]+)*$'-or$raw.Contains('PASS|')){throw ('INTEGRATION_RESOLVER_FAILURE_SHAPE|'+$Name+'|'+$Run.Code+'|'+$raw)}
 $reason=$raw.Substring($prefix.Length)
 Write-Host ('OBSERVE|maintenance-stage|case='+$Name+'|reason='+$reason)
 return $reason
}
Export-ModuleMember -Function Assert-True,Write-Utf8,Get-Identity,Write-CurrentFixtureObject,New-CurrentFixtureIntent,Get-BytesIdentity,Get-OptionalIdentity,Get-ExactObjectRows,Get-ReleasePayloadFacts,Get-ReleaseValidationState,Seal-ReleaseFixture,Seal-MaintenanceRuntimeFixture,Approve-CandidateReleaseFixture,Invoke-Ps,Invoke-PsHost,Invoke-PsHostEntryIdArray,Invoke-PsWithProcessEnvironment,Invoke-WorkflowCase,Invoke-WorkflowRawCase,New-GitRepo,Commit-All,New-TestJunction,Remove-TestJunction,Get-PrivateFixtureCleanupPath,Get-PhysicalFixtureTree,Render-MaintenanceStarter,New-AuthorizationPackage,Set-PackageProjectConfigIdentity,New-MaintenanceUpgradeAuthorizationPackage,Invoke-FixtureSchema2Authorization,Get-IntegrationCheckCount,New-IntegrationContext,Close-IntegrationContext,New-IntegrationRuntimeFixture,New-IntegrationMaintenanceFixture,Complete-IntegrationMaintenanceFixture,Assert-IntegrationMaintenanceBaseline,Get-IntegrationResolverFailure
