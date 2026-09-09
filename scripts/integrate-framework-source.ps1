[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('PREVIEW','APPLY','VERIFY_REFRESH','FINALIZE_CHECK','RECOVER','COMPLETE','REFRESH_PREVIEW','REFRESH')][string]$Operation,
    [Parameter(Mandatory)][string]$ControlRepositoryPath,
    [Parameter(Mandatory)][string]$TransactionPath,
    [string]$AdmitInputPath,
    [string]$ExpectedAdmitInputIdentity,
    [string]$CurrentProcessInputPath,
    [string]$ExpectedCurrentProcessInputIdentity,
    [int]$InterruptAfterWrite = -1,
    [switch]$InterruptAfterRefresh,
    [string]$CandidateRoot,
    [string]$AuthorizationPackagePath,
    [string]$ExpectedAuthorizationPackageIdentity,
    [string]$DiscoverReceiptPath,
    [string]$ExpectedDiscoverReceiptIdentity,
    [string]$AdmitResultPath,
    [string]$ExpectedAdmitResultIdentity,
    [string]$AcceptedFreezePath,
    [string]$ExpectedAcceptedFreezeIdentity,
    [string]$AcceptedEvidencePath,
    [string]$ExpectedAcceptedEvidenceIdentity,
    [string]$ExpectedParent,
    [string]$MaintenanceRefreshPackagePath,
    [string]$ExpectedMaintenanceRefreshPackageIdentity,
    [string]$MaintenanceRefreshResultPath,
    [string]$ExpectedMaintenanceRefreshResultIdentity,
    [string]$ExpectedTransactionIdentity,
    [string]$FinalizeInputPath,
    [string]$FinalizeDecisionIdentity,
    [int]$FailAfterWrite = -1,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'POWERSHELL7_REQUIRED' }
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$utf8Out = [Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionProjection.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1') -Force

function Get-Identity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    return $bytes.Length.ToString() + '|' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Read-StrictJson([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + '_MISSING') }
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw ($Label + '_BOM') }
    try { $text = $utf8.GetString($bytes) } catch { throw ($Label + '_UTF8') }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or -not $text.EndsWith("`n")) { throw ($Label + '_TEXT_FORMAT') }
    $doc=[Text.Json.JsonDocument]::Parse($text)
    try { Assert-UniqueJson $doc.RootElement } finally { $doc.Dispose() }
    try { return $text | ConvertFrom-Json -Depth 100 } catch { throw ($Label + '_JSON') }
}

function Write-State([string]$Path, $State) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    $temp = Join-Path $parent ('.self-update-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($temp, (($State | ConvertTo-Json -Depth 100 -Compress) + "`n"), $utf8Out)
        [IO.File]::Move($temp, $Path, $true)
    }
    finally { if (Test-Path -LiteralPath $temp -PathType Leaf) { [IO.File]::Delete($temp) } }
}

function Set-StateField($State, [string]$Name, $Value) {
    if ($State -is [Collections.IDictionary]) {
        $State[$Name] = $Value
    }
    elseif ($null -eq $State.PSObject.Properties[$Name]) {
        $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $State.$Name = $Value
    }
}

function Assert-Identity([string]$Path, [string]$Expected, [string]$Label) {
    if ($Expected -cnotmatch '^\d+\|[A-F0-9]{64}$' -or (Get-Identity $Path) -cne $Expected) { throw ($Label + '_DRIFT') }
}

function Assert-TransactionPath([string]$ControlRoot, [string]$Path) {
    $control = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ControlRoot))
    $full = [IO.Path]::GetFullPath($Path)
    $runtime = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $control '.ai-workspace/runtime')))
    if (-not $full.StartsWith($runtime + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetExtension($full) -cne '.json') { throw 'SELF_UPDATE_TRANSACTION_PATH' }
    $current = Split-Path -Parent $full
    while (-not [string]::IsNullOrWhiteSpace($current) -and $current.Length -ge $runtime.Length) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'SELF_UPDATE_TRANSACTION_REPARSE' }
        if ([IO.Path]::TrimEndingDirectorySeparator($current) -ceq $runtime) { break }
        $current = Split-Path -Parent $current
    }
    return $full
}

function Resolve-Topology([string]$ControlRoot, [string]$ExpectedConfigIdentity) {
    $resolver = Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
    $output = @(& $resolver -ControlRepositoryPath $ControlRoot -ExpectedProjectConfigIdentity $ExpectedConfigIdentity -AsJson 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) { throw ('SELF_UPDATE_TOPOLOGY|' + ($output -join ';')) }
    return $output[0] | ConvertFrom-Json -Depth 30
}

function Get-TreeFacts([string]$Root) {
    $rootFull = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root)))
    $relative = [Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $rootFull -File -Recurse -Force |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        ForEach-Object { $relative.Add([IO.Path]::GetRelativePath($rootFull, $_.FullName).Replace('\','/')) }
    $relative.Sort([StringComparer]::Ordinal)
    $rows = [Collections.Generic.List[string]]::new()
    $files = [Collections.Generic.List[object]]::new()
    [int64]$total = 0
    foreach ($path in $relative) {
        $full = Join-Path $rootFull ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $item = Get-Item -LiteralPath $full
        $sha = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
        $total += $item.Length
        $rows.Add($path + '|' + $item.Length + '|' + $sha)
        $files.Add([pscustomobject]@{ path = $path; bytes = [int64]$item.Length; sha256 = $sha; identity = $item.Length.ToString() + '|' + $sha })
    }
    $canonical = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $rows))))
    return [pscustomobject]@{ root = $rootFull; fileCount = $relative.Count; totalBytes = $total; canonical = $canonical; files = @($files) }
}

function Assert-Freeze([string]$Root, $Freeze, [string]$Label) {
    $facts = Get-TreeFacts $Root
    if (-not ($Freeze.files -is [Array]) -or [int]$Freeze.fileCount -ne $facts.fileCount -or [int64]$Freeze.totalBytes -ne $facts.totalBytes -or [string]$Freeze.canonical -cne $facts.canonical) { throw ($Label + '_TREE') }
    $expected = @{}; foreach ($entry in @($Freeze.files)) { if ($expected.ContainsKey([string]$entry.path)) { throw ($Label + '_DUPLICATE') }; $expected[[string]$entry.path] = [string]$entry.bytes + '|' + [string]$entry.sha256 }
    foreach ($entry in @($facts.files)) { if (-not $expected.ContainsKey([string]$entry.path) -or [string]$expected[[string]$entry.path] -cne [string]$entry.identity) { throw ($Label + '_OBJECT|' + [string]$entry.path) } }
    return $facts
}

function Get-ReceiptView($Receipt) {
    if ([int]$Receipt.schemaVersion -eq 1) {
        return [pscustomobject]@{ actionKind = [string]$Receipt.actionKind; resultKind = [string]$Receipt.resultKind; exactPaths = @($Receipt.exactPaths); authorizationIdentity = [string]$Receipt.authorityContext.authorizationIdentity; taskIdentity = [string]$Receipt.taskIdentity; taskId = [string]$Receipt.taskId; taskOwner = [string]$Receipt.taskOwner; taskActor = [string]$Receipt.taskActor; actor = [string]$Receipt.actor; projectConfigIdentity = [string]$Receipt.sourceBindings.projectConfigIdentity; controllerIdentity = [string]$Receipt.sourceBindings.controllerIdentity; frameworkRoot = [string]$Receipt.sourceLocators.frameworkRoot; taskRelativePath = [string]$Receipt.sourceLocators.taskRelativePath; selectionIdentity = [string]$Receipt.selectionIdentity; selectedObligations = @($Receipt.selectedObligations) }
    }
    if ([int]$Receipt.schemaVersion -eq 2) {
        throw 'MAINTENANCE_TARGET_RECEIPT_SCHEMA_UNSUPPORTED|USE_SCHEMA2_DISCOVER_SCHEMA1_COMPACT'
    }
    throw 'SELF_UPDATE_RECEIPT_SCHEMA'
}

function Assert-SamePaths([object[]]$Left, [object[]]$Right, [string]$Label) {
    if ([string]::Join("`n", @($Left | ForEach-Object { [string]$_ })) -cne [string]::Join("`n", @($Right | ForEach-Object { [string]$_ }))) { throw $Label }
}

function Get-CurrentIdentity([string]$Root, [string]$Relative) {
    $path = Get-AiwContainedPath $Root $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'MISSING' }
    return Get-Identity $path
}

function Read-State([string]$Path, [string]$ExpectedIdentity) {
    if(((Get-Item -LiteralPath $Path -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'SELF_UPDATE_TRANSACTION_REPARSE'}
    Assert-Identity $Path $ExpectedIdentity 'SELF_UPDATE_TRANSACTION'
    $state = Read-StrictJson $Path 'SELF_UPDATE_TRANSACTION'
    if ([int]$state.schemaVersion -ne 1 -or [string]$state.transactionType -cne 'MAINTENANCE_FRAMEWORK_SOURCE_SELF_UPDATE') { throw 'SELF_UPDATE_TRANSACTION_SCHEMA' }
    $observedControl=Resolve-AiwRepositoryRoot $ControlRepositoryPath
    if(-not[StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath([string]$state.controlRoot),$observedControl)){throw 'SELF_UPDATE_CONTROL_ROOT_DRIFT'}
    $topology=Resolve-Topology $observedControl ([string]$state.projectConfigIdentity)
    if(-not[StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath([string]$state.targetRoot),[string]$topology.targetRoot)-or[string]$state.targetRepositoryId-cne[string]$topology.targetRepositoryId-or[string]$state.frameworkVersion-cne[string]$topology.frameworkVersion){throw 'SELF_UPDATE_TARGET_ROOT_DRIFT'}
    return $state
}

function Assert-ControlBindings($State) {
    foreach ($pair in @(
        @('.ai-workspace/project.json', [string]$State.projectConfigIdentity, 'PROJECT_CONFIG'),
        @('.ai-workspace/controller.json', [string]$State.controllerIdentity, 'CONTROLLER'),
        @([string]$State.taskRelativePath, [string]$State.taskIdentity, 'TASK')
    )) {
        $actual = Get-CurrentIdentity ([string]$State.controlRoot) ([string]$pair[0])
        if ($actual -cne [string]$pair[1]) { throw ('SELF_UPDATE_' + [string]$pair[2] + '_DRIFT') }
    }
}

function Assert-TransactionSources($State) {
    foreach ($pair in @(
        @([string]$State.authorizationPackagePath, [string]$State.authorizationPackageIdentity, 'AUTHORIZATION'),
        @([string]$State.discoverReceiptPath, [string]$State.discoverReceiptIdentity, 'DISCOVER'),
        @([string]$State.admitResultPath, [string]$State.admitResultIdentity, 'ADMIT'),
        @([string]$State.acceptedFreezePath, [string]$State.acceptedFreezeIdentity, 'FREEZE'),
        @([string]$State.acceptedEvidencePath, [string]$State.acceptedEvidenceIdentity, 'EVIDENCE')
    )) {
        Assert-Identity ([string]$pair[0]) ([string]$pair[1]) ('SELF_UPDATE_' + [string]$pair[2])
    }
}


# These helpers coordinate root operations; selection remains in the version composer.
function Assert-UniqueJson($Element) {
    if($Element.ValueKind-eq[Text.Json.JsonValueKind]::Object){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($p in $Element.EnumerateObject()){if(-not$seen.Add($p.Name)){throw 'SELF_UPDATE_DUPLICATE_JSON'};Assert-UniqueJson $p.Value}
    }elseif($Element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($v in $Element.EnumerateArray()){Assert-UniqueJson $v}}
}
function Invoke-JsonTool([string]$Tool,[hashtable]$Arguments) {
    $output=@(& $Tool @Arguments 2>&1 | ForEach-Object {[string]$_})
    if($LASTEXITCODE-ne0-or$output.Count-ne1){throw ('SELF_UPDATE_TOOL_FAILED|'+($output-join';'))}
    return $output[0] | ConvertFrom-Json -Depth 100
}
function Assert-Parent($State) {
    $head=@(& git -c ('safe.directory='+[string]$State.targetRoot) -C ([string]$State.targetRoot) rev-parse HEAD 2>$null)
    if($LASTEXITCODE-ne0-or$head.Count-ne1-or[string]$head[0]-cne[string]$State.expectedParent){throw 'SELF_UPDATE_PARENT_DRIFT'}
}
function Get-ControlSnapshot([string]$Root,[string]$Version) {
    # Same-pin adoption's existing managed set; never sweep project data or runtime.
    $paths=@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','AGENTS.md','.gitignore','.agents/skills/ai-workspace-router/SKILL.md',('.ai-workspace/upgrade-recovery/'+$Version+'/state.json'))
    return @($paths|ForEach-Object{
        $full=Get-AiwContainedPath $Root $_;$id=Get-CurrentIdentity $Root $_
        [pscustomobject]@{path=$_;identity=$id;base64=$(if($id-ceq'MISSING'){''}else{[Convert]::ToBase64String([IO.File]::ReadAllBytes($full))})}
    })
}
function Assert-SourceState($State,[string]$Side) {
    Assert-ControlBindings $State;Assert-Parent $State;Assert-TransactionSources $State
    Assert-Identity ([string]$State.admitInputPath) ([string]$State.admitInputIdentity) 'SELF_UPDATE_ADMIT_INPUT'
    foreach($entry in @($State.dependencies)){
        if((Get-CurrentIdentity ([string]$State.targetRoot) ([string]$entry.path))-cne[string]$entry.identity){throw ('SELF_UPDATE_DEPENDENCY_DRIFT|'+$entry.path)}
    }
    foreach($entry in @($State.projection.objects)){
        $expected=if($Side-ceq'OLD'){[string]$entry.oldIdentity}else{[string]$entry.newIdentity}
        if((Get-CurrentIdentity ([string]$State.targetRoot) ([string]$entry.path))-cne$expected){throw ('SELF_UPDATE_TARGET_DRIFT|'+$entry.path)}
    }
}
function Invoke-OriginalAdmission($State) {
    Assert-SourceState $State 'OLD'
    $input=Read-StrictJson ([string]$State.admitInputPath) 'SELF_UPDATE_ADMIT_INPUT'
    if([string]$input.mode-cne'ADMIT_ACTION'-or[string]$input.expectedDiscoverReceiptIdentity-cne[string]$State.discoverReceiptIdentity-or
        [IO.Path]::GetFullPath([string]$input.discoverReceiptPath)-cne[IO.Path]::GetFullPath([string]$State.discoverReceiptPath)){throw 'SELF_UPDATE_ADMIT_INPUT_BINDING'}
    $result=Invoke-JsonTool (Join-Path $PSScriptRoot 'resolve-framework-maintenance-process-requirements.ps1') @{InputPath=[string]$State.admitInputPath;AsJson=$true}
    $original=Read-StrictJson ([string]$State.admitResultPath) 'SELF_UPDATE_ADMIT'
    if([string]$result.status-cne'PASS'-or[string]$result.decisionIdentity-cne[string]$original.decisionIdentity){throw 'SELF_UPDATE_REAL_ADMISSION_MISMATCH'}
    return $result
}
function New-Preparation {
    foreach($v in @($CandidateRoot,$AuthorizationPackagePath,$ExpectedAuthorizationPackageIdentity,$DiscoverReceiptPath,$ExpectedDiscoverReceiptIdentity,$AdmitInputPath,$ExpectedAdmitInputIdentity,$AdmitResultPath,$ExpectedAdmitResultIdentity,$AcceptedFreezePath,$ExpectedAcceptedFreezeIdentity,$AcceptedEvidencePath,$ExpectedAcceptedEvidenceIdentity,$ExpectedParent)){if([string]::IsNullOrWhiteSpace($v)){throw 'SELF_UPDATE_PREPARATION_FIELDS'}}
    $control=Resolve-AiwRepositoryRoot $ControlRepositoryPath
    $transaction=Assert-TransactionPath $control $TransactionPath
    foreach($pair in @(@($AuthorizationPackagePath,$ExpectedAuthorizationPackageIdentity),@($DiscoverReceiptPath,$ExpectedDiscoverReceiptIdentity),@($AdmitInputPath,$ExpectedAdmitInputIdentity),@($AdmitResultPath,$ExpectedAdmitResultIdentity),@($AcceptedFreezePath,$ExpectedAcceptedFreezeIdentity),@($AcceptedEvidencePath,$ExpectedAcceptedEvidenceIdentity))){Assert-Identity $pair[0] $pair[1] 'SELF_UPDATE_PREPARATION'}
    $package=Read-StrictJson $AuthorizationPackagePath 'SELF_UPDATE_PACKAGE'
    $receipt=Read-StrictJson $DiscoverReceiptPath 'SELF_UPDATE_DISCOVER';$view=Get-ReceiptView $receipt
    if([int]$package.schemaVersion-ne2-or[string]$view.actionKind-cne'SOURCE_WRITE'-or[string]$view.authorizationIdentity-cne$ExpectedAuthorizationPackageIdentity-or[string]$view.taskIdentity-cne[string]$package.taskIdentity-or[string]$view.actor-cne[string]$package.grantee){throw 'SELF_UPDATE_AUTHORIZATION_BINDING'}
    Assert-SamePaths @($package.exactPaths) @($view.exactPaths) 'SELF_UPDATE_RECEIPT_SCOPE'
    $topology=Resolve-Topology $control ([string]$view.projectConfigIdentity)
    if([string]$package.repositoryId-cne[string]$topology.targetRepositoryId-or[IO.Path]::GetFullPath([string]$view.frameworkRoot)-cne[IO.Path]::GetFullPath([string]$topology.targetRoot)){throw 'SELF_UPDATE_REPOSITORY_BINDING'}
    $target=[string]$topology.targetRoot
    $candidate=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateRoot)))
    if($candidate-ceq$target-or(Test-Path -LiteralPath (Join-Path $target '.ai-workspace'))){throw 'SELF_UPDATE_ROOT_SEPARATION'}
    $freeze=Read-StrictJson $AcceptedFreezePath 'SELF_UPDATE_FREEZE';$facts=Assert-Freeze $candidate $freeze 'SELF_UPDATE_CANDIDATE'
    $evidence=Read-StrictJson $AcceptedEvidencePath 'SELF_UPDATE_EVIDENCE'
    if([string]$evidence.status-cnotin@('OWNER_ACCEPTED_PENDING_RELEASE_INTEGRATION','PASS')-or[string]$evidence.focusedRereview.status-cne'APPROVED'-or[string]$evidence.ownerAcceptance.status-cne'PASS'){throw 'SELF_UPDATE_ACCEPTED_EVIDENCE'}
    $targets=@();$pre=@{};foreach($e in $package.objectIdentities){if($pre.ContainsKey($e.path)){throw 'SELF_UPDATE_DUPLICATE_OBJECT'};$pre[$e.path]=$e.identity}
    foreach($relative in $package.exactPaths){
        Assert-AiwRelativePath $relative
        $source=Get-AiwContainedPath $candidate $relative;$null=Get-AiwContainedPath $target $relative
        $expectedPre=if($pre.ContainsKey($relative)-and$pre[$relative]-ceq'NEW'){'MISSING'}else{$pre[$relative]}
        if(-not$pre.ContainsKey($relative)-or(Get-CurrentIdentity $target $relative)-cne$expectedPre){throw ('SELF_UPDATE_PREIMAGE_DRIFT|'+$relative)}
        $targets+= [pscustomobject]@{path=$relative;bytes=[IO.File]::ReadAllBytes($source)}
    }
    $projection=New-AiwProjectProjection $target $targets
    $manifestPath=Join-Path $candidate ('framework/versions/'+$package.frameworkVersion+'/RELEASE_MANIFEST.json')
    $manifest=Read-StrictJson $manifestPath 'SELF_UPDATE_MANIFEST'
    if([string]$manifest.canonical-cne[string]$freeze.sourcePayloadCanonical-or[string]$manifest.canonical-cne[string]$evidence.sourcePayload.canonical-or[string]$manifest.sourceReview-cne'APPROVED'-or[string]$manifest.releaseIntegration-cne'PENDING'){throw 'SELF_UPDATE_CANDIDATE_RELEASE_BINDING'}
    # Bind relevant current sources, not unrelated target files or Git metadata.
    $dependencies=@($facts.files|Where-Object {($_.path.StartsWith('scripts/')-or$_.path.StartsWith('framework/versions/'+$package.frameworkVersion+'/'))-and$_.path-cnotin@($package.exactPaths)}|ForEach-Object{
        [pscustomobject]@{path=$_.path;identity=Get-CurrentIdentity $target $_.path}
    })
    $state=[ordered]@{
        schemaVersion=1;transactionType='MAINTENANCE_FRAMEWORK_SOURCE_SELF_UPDATE';status='PREPARED'
        controlRoot=$control;targetRoot=$target;candidateRoot=$candidate;targetRepositoryId=$topology.targetRepositoryId;frameworkVersion=$package.frameworkVersion;expectedParent=$ExpectedParent
        projectConfigIdentity=$view.projectConfigIdentity;controllerIdentity=$view.controllerIdentity;taskRelativePath=$view.taskRelativePath;taskIdentity=$view.taskIdentity;taskId=$view.taskId;taskOwner=$view.taskOwner;taskActor=$view.taskActor;actor=$view.actor
        authorizationPackagePath=[IO.Path]::GetFullPath($AuthorizationPackagePath);authorizationPackageIdentity=$ExpectedAuthorizationPackageIdentity;discoverReceiptPath=[IO.Path]::GetFullPath($DiscoverReceiptPath);discoverReceiptIdentity=$ExpectedDiscoverReceiptIdentity
        admitInputPath=[IO.Path]::GetFullPath($AdmitInputPath);admitInputIdentity=$ExpectedAdmitInputIdentity;admitResultPath=[IO.Path]::GetFullPath($AdmitResultPath);admitResultIdentity=$ExpectedAdmitResultIdentity
        acceptedFreezePath=[IO.Path]::GetFullPath($AcceptedFreezePath);acceptedFreezeIdentity=$ExpectedAcceptedFreezeIdentity;acceptedEvidencePath=[IO.Path]::GetFullPath($AcceptedEvidencePath);acceptedEvidenceIdentity=$ExpectedAcceptedEvidenceIdentity
        exactPaths=@($package.exactPaths);projection=$projection;dependencies=$dependencies;controlPreimages=@(Get-ControlSnapshot $control $package.frameworkVersion)
        sourcePayloadCanonical=$manifest.canonical;targetManifestIdentity=Get-Identity $manifestPath;candidateCanonical=$facts.canonical
        completedWrites=0;refresh=$null;completion=$null
    }
    $admission=Invoke-OriginalAdmission ([pscustomobject]$state)
    $state['admitDecisionIdentity']=$admission.decisionIdentity
    return [pscustomobject]@{transactionPath=$transaction;state=$state}
}
function Assert-RecoveryPreflight($State) {
    Assert-ControlBindings $State;Assert-Parent $State
    # Check every root before restoring any object; a conflict must not cause partial rollback.
    foreach($e in $State.projection.objects){
        $id=Get-CurrentIdentity $State.targetRoot $e.path
        if($id-cne$e.oldIdentity-and$id-cne$e.newIdentity){throw ('SELF_UPDATE_THIRD_PARTY_TARGET|'+$e.path)}
    }
    foreach($e in $State.dependencies){if((Get-CurrentIdentity $State.targetRoot $e.path)-cne$e.identity){throw ('SELF_UPDATE_DEPENDENCY_DRIFT|'+$e.path)}}
    $posts=@{};if($null-ne$State.refresh){foreach($e in $State.refresh.postimages){$posts[$e.path]=$(if($e.identity-ceq'ABSENT'){'MISSING'}else{$e.identity})}}
    foreach($e in $State.controlPreimages){
        $id=Get-CurrentIdentity $State.controlRoot $e.path
        if($id-cne$e.identity-and(-not$posts.ContainsKey($e.path)-or$id-cne$posts[$e.path])){throw ('SELF_UPDATE_THIRD_PARTY_CONTROL|'+$e.path)}
    }
}
function Invoke-Recover([string]$Path,[string]$Expected) {
    $s=Read-State $Path $Expected
    if($s.status-ceq'COMPLETE'){throw 'SELF_UPDATE_RECOVERY_COMPLETE'}
    Assert-RecoveryPreflight $s
    $s.status='RECOVERING';Write-State $Path $s
    $objects=@()
    foreach($e in $s.controlPreimages){
        $id=Get-CurrentIdentity $s.controlRoot $e.path
        [byte[]]$bytes=[byte[]]::new(0)
        if($id-cne'MISSING'){$bytes=[IO.File]::ReadAllBytes((Get-AiwContainedPath $s.controlRoot $e.path))}
        $objects+=[pscustomobject]@{path=$e.path;kind='FILE';oldExists=($e.identity-cne'MISSING');newExists=($id-cne'MISSING');oldIdentity=$e.identity;newIdentity=$id;changed=($e.identity-cne$id);oldBase64=$e.base64;newBase64=[Convert]::ToBase64String($bytes)}
    }
    $projection=[pscustomobject]@{schemaVersion=1;repositoryRoot=$s.controlRoot;objects=$objects}
    if(@($objects|Where-Object changed).Count-gt0){Restore-AiwProjectProjection $s.controlRoot $projection}
    Restore-AiwProjectProjection $s.targetRoot $s.projection
    Assert-SourceState $s 'OLD'
    $null=Invoke-OriginalAdmission $s
    $s.status='ROLLED_BACK';Write-State $Path $s
    return [pscustomobject]@{status='ROLLED_BACK';transactionIdentity=Get-Identity $Path;healthyOriginalAdmission=$true}
}
function Invoke-Apply($Prepared) {
    $path=$Prepared.transactionPath;$s=$Prepared.state
    if(Test-Path -LiteralPath $path){throw 'SELF_UPDATE_TRANSACTION_EXISTS'}
    $null=Invoke-OriginalAdmission ([pscustomobject]$s)
    $s.status='APPLYING';Write-State $path $s
    try{
        foreach($e in $s.projection.objects|Where-Object changed){
            if((Get-CurrentIdentity $s.targetRoot $e.path)-cne$e.oldIdentity){throw 'SELF_UPDATE_APPLY_DRIFT'}
            $full=Get-AiwContainedPath $s.targetRoot $e.path
            $parent=Split-Path -Parent $full;New-Item -ItemType Directory -Path $parent -Force|Out-Null
            $temporary=$full+'.self-update-'+[guid]::NewGuid().ToString('N')
            try{[IO.File]::WriteAllBytes($temporary,[Convert]::FromBase64String($e.newBase64));[IO.File]::Move($temporary,$full,$true)}finally{if(Test-Path -LiteralPath $temporary){[IO.File]::Delete($temporary)}}
            $s.completedWrites++;Write-State $path $s
            if($InterruptAfterWrite-ge0-and$s.completedWrites-ge$InterruptAfterWrite){return [pscustomobject]@{status='INTERRUPTED';transactionIdentity=Get-Identity $path;stage='TARGET_WRITE'}}
            if($FailAfterWrite-ge0-and$s.completedWrites-ge$FailAfterWrite){throw 'SELF_UPDATE_INJECTED_FAILURE'}
        }
        Assert-SourceState ([pscustomobject]$s) 'NEW'
        $s.status='TARGET_APPLIED_PENDING_MAINTENANCE_REFRESH';Write-State $path $s
        return [pscustomobject]@{status=$s.status;transactionIdentity=Get-Identity $path;writes=$s.completedWrites}
    }catch{
        $cause=$_.Exception.Message
        $null=Invoke-Recover $path (Get-Identity $path)
        throw ('SELF_UPDATE_APPLY_ROLLED_BACK|'+$cause)
    }
}
function Invoke-Upgrade($State,[bool]$ApplyChange) {
    $config=Read-StrictJson (Join-Path $State.controlRoot '.ai-workspace/project.json') 'PROJECT'
    $controller=Read-StrictJson (Join-Path $State.controlRoot '.ai-workspace/controller.json') 'CONTROLLER'
    $a=@{ProjectId=$config.id;ToVersion=$State.frameworkVersion;RepositoryPath=$State.controlRoot;ControllerId=$controller.controllerId;WorkspaceRoot=$State.targetRoot;ActorRouteTaskPath=$State.taskRelativePath;ExpectedActorRouteTaskIdentity=$State.taskIdentity;ActorRouteActor=$State.actor;LocalCandidatePilot=$true}
    if($CurrentProcessInputPath){Assert-Identity $CurrentProcessInputPath $ExpectedCurrentProcessInputIdentity 'REFRESH_PROCESS_INPUT';$a.CurrentProcessInputPath=$CurrentProcessInputPath;$a.ExpectedCurrentProcessInputIdentity=$ExpectedCurrentProcessInputIdentity}
    if($ApplyChange){$a.Apply=$true;$a.AuthorizationPackagePath=$MaintenanceRefreshPackagePath;$a.ExpectedAuthorizationPackageIdentity=$ExpectedMaintenanceRefreshPackageIdentity}
    $tool=Join-Path $State.targetRoot 'scripts/upgrade-project.ps1'
    $output=@(& $tool @a 2>&1|ForEach-Object{[string]$_})
    if($LASTEXITCODE-ne0){throw ('SELF_UPDATE_UPGRADE_FAILED|'+($output-join';'))}
    return @($output)
}
function Assert-NoWriteRefresh($State,[string[]]$Output) {
    # Only the real completed managed-projection recovery branch is supported.
    # No Apply, caller result, or write package substitutes for its live checks.
    $expectedOutput=@('UPGRADE_RECOVERY_WRITESET|',('RECOVERY_COMPLETE|to='+$State.frameworkVersion+'|writes=ZERO|state=LOCAL_CANDIDATE_MANAGED_PROJECTION'))
    Assert-SamePaths $expectedOutput @($Output) 'SELF_UPDATE_REFRESH_NOT_VERIFIED_NO_WRITE'
    Assert-SourceState $State 'NEW';Assert-RecoveryPreflight $State
    foreach($entry in $State.controlPreimages){
        if((Get-CurrentIdentity $State.controlRoot $entry.path)-cne$entry.identity){throw ('SELF_UPDATE_NO_WRITE_CONTROL_DRIFT|'+$entry.path)}
    }
}
function Invoke-Refresh([string]$Path,[string]$Expected,[bool]$ApplyChange) {
    $s=Read-State $Path $Expected
    if($s.status-cne'TARGET_APPLIED_PENDING_MAINTENANCE_REFRESH'){throw 'SELF_UPDATE_REFRESH_STATE'}
    Assert-SourceState $s 'NEW';Assert-RecoveryPreflight $s
    if(-not$ApplyChange){return [pscustomobject]@{status='PREVIEW';output=@(Invoke-Upgrade $s $false)}}
    if(-not$MaintenanceRefreshPackagePath-and-not$ExpectedMaintenanceRefreshPackageIdentity){
        $output=@(Invoke-Upgrade $s $false)
        Assert-NoWriteRefresh $s $output
        $s.refresh=[pscustomobject]@{kind='VERIFIED_NO_WRITE';packagePath='NOT_REQUIRED';packageIdentity='NOT_REQUIRED';postimages=@($s.controlPreimages|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$_.identity}});output=$output;completed=$true}
        $s.status='READY_FOR_FINALIZE';Write-State $Path $s
        if($InterruptAfterRefresh){return [pscustomobject]@{status='INTERRUPTED';stage='AFTER_REFRESH';transactionIdentity=Get-Identity $Path}}
        return Invoke-FinalizeCheck $Path (Get-Identity $Path) $false
    }
    Assert-Identity $MaintenanceRefreshPackagePath $ExpectedMaintenanceRefreshPackageIdentity 'SELF_UPDATE_REFRESH_PACKAGE'
    $p=Read-StrictJson $MaintenanceRefreshPackagePath 'SELF_UPDATE_REFRESH_PACKAGE'
    # Schema3 has no repositoryId field. The existing upgrader supplies CONTROL
    # topology and ObservedRepositoryId to the root checker, which validates it.
    if([int]$p.schemaVersion-ne3-or$p.taskIdentity-cne$s.taskIdentity-or$p.grantee-cne$s.actor-or$p.targetFrameworkSnapshot.canonical-cne$s.sourcePayloadCanonical-or$p.targetFrameworkSnapshot.manifestIdentity-cne$s.targetManifestIdentity){throw 'SELF_UPDATE_REFRESH_PACKAGE_BINDING'}
    foreach($entry in $p.objectIdentities){
        $old=@($s.controlPreimages|Where-Object path -CEQ $entry.path)
        $expectedOld=if($entry.identity-ceq'NEW'){'MISSING'}else{$entry.identity}
        if($old.Count-ne1-or$old[0].identity-cne$expectedOld-or(Get-CurrentIdentity $s.controlRoot $entry.path)-cne$expectedOld){throw 'SELF_UPDATE_REFRESH_PREIMAGE'}
    }
    $s.refresh=[pscustomobject]@{packagePath=[IO.Path]::GetFullPath($MaintenanceRefreshPackagePath);packageIdentity=$ExpectedMaintenanceRefreshPackageIdentity;postimages=@($p.postObjectIdentities);output=@();completed=$false}
    $s.status='REFRESHING';Write-State $Path $s
    try{
        # Upgrader owns full schema3 validation and its existing adoption transaction.
        $output=@(Invoke-Upgrade $s $true)
        if(@($output|Where-Object{$_-match '^(UPGRADED|LOCAL_CANDIDATE_.*(APPLIED|REBOUND|REFRESHED))\|'}).Count-eq0){throw ('SELF_UPDATE_REFRESH_NO_COMPLETION|'+($output-join';'))}
        foreach($entry in $p.postObjectIdentities){$post=if($entry.identity-ceq'ABSENT'){'MISSING'}else{$entry.identity};if((Get-CurrentIdentity $s.controlRoot $entry.path)-cne$post){throw ('SELF_UPDATE_REFRESH_POSTIMAGE|'+$entry.path)}}
        $s.refresh.output=$output;$s.refresh.completed=$true;$s.status='READY_FOR_FINALIZE';Write-State $Path $s
        if($InterruptAfterRefresh){return [pscustomobject]@{status='INTERRUPTED';stage='AFTER_REFRESH';transactionIdentity=Get-Identity $Path}}
        return Invoke-FinalizeCheck $Path (Get-Identity $Path) $false
    }catch{
        $cause=$_.Exception.Message
        $null=Invoke-Recover $Path (Get-Identity $Path)
        throw ('SELF_UPDATE_REFRESH_ROLLED_BACK|'+$cause)
    }
}
function Invoke-FinalizeCheck([string]$Path,[string]$Expected,[bool]$CheckEvidence) {
    $s=Read-State $Path $Expected
    if($s.status-cne'READY_FOR_FINALIZE'-or$null-eq$s.refresh-or-not$s.refresh.completed){throw 'SELF_UPDATE_FINALIZE_STATE'}
    Assert-SourceState $s 'NEW';Assert-RecoveryPreflight $s
    $noWrite=$null-ne$s.refresh.PSObject.Properties['kind']-and$s.refresh.kind-ceq'VERIFIED_NO_WRITE'
    if($noWrite){
        if($s.refresh.packagePath-cne'NOT_REQUIRED'-or$s.refresh.packageIdentity-cne'NOT_REQUIRED'){throw 'SELF_UPDATE_NO_WRITE_PACKAGE'}
        Assert-SamePaths @($s.controlPreimages|ForEach-Object{$_.path+'|'+$_.identity}) @($s.refresh.postimages|ForEach-Object{$_.path+'|'+$_.identity}) 'SELF_UPDATE_NO_WRITE_POSTIMAGES'
        Assert-NoWriteRefresh $s @($s.refresh.output)
        Assert-NoWriteRefresh $s @(Invoke-Upgrade $s $false)
    }else{
        if($null-ne$s.refresh.PSObject.Properties['kind']){throw 'SELF_UPDATE_REFRESH_KIND'}
        Assert-Identity $s.refresh.packagePath $s.refresh.packageIdentity 'SELF_UPDATE_REFRESH_PACKAGE'
    }
    foreach($entry in $s.refresh.postimages){$post=if($entry.identity-ceq'ABSENT'){'MISSING'}else{$entry.identity};if((Get-CurrentIdentity $s.controlRoot $entry.path)-cne$post){throw 'SELF_UPDATE_REFRESH_POSTIMAGE'}}
    $receipt=Read-StrictJson $s.discoverReceiptPath 'SELF_UPDATE_DISCOVER';$view=Get-ReceiptView $receipt
    $authority=if([int]$receipt.schemaVersion-eq1){$receipt.authorityContext}else{$receipt.binding}
    $context=if([int]$receipt.schemaVersion-eq1){$receipt}else{$receipt.binding}
    $module=Join-Path $s.targetRoot ('framework/versions/'+$s.frameworkVersion+'/scripts/ProcessRequirementComposition.psm1')
    $composerModule=Import-Module $module -Force -PassThru
    $current=Get-AiwProcessBindingSnapshot -ProjectRoot $s.controlRoot -FrameworkRoot $s.targetRoot -TargetVersion $s.frameworkVersion -TaskRelativePath $s.taskRelativePath -ForbiddenPaths @($authority.forbiddenScope)
    $allowed=@('frameworkVersionIdentity','releaseManifestIdentity','nativeCatalogIdentity','correctionCoverageIdentity','candidatePilotStateIdentity')
    if(-not$noWrite-and'.ai-workspace/process-policy.json'-cin@($s.refresh.postimages.path)){$allowed+=@('policyIdentity','projectStandardsIdentity')}
    foreach($property in $receipt.sourceBindings.PSObject.Properties){
        if($current.($property.Name)-cne$property.Value-and$property.Name-cnotin$allowed){throw ('SELF_UPDATE_UNAUTHORIZED_SOURCE_DRIFT|'+$property.Name)}
    }
    if($current.releaseManifestIdentity-cne$s.targetManifestIdentity){throw 'SELF_UPDATE_CURRENT_RELEASE'}
    $intent=$receipt.intentEnvelope
    $semantic=if($composerModule.ExportedCommands.ContainsKey('Get-AiwProcessSemanticText')){
        & $composerModule.ExportedCommands['Get-AiwProcessSemanticText'] -IntentEnvelope $intent
    }else{
        # Retained versions without the projection export use their original contract.
        ([string]$intent.objective+' '+[string]::Join(' ',@($intent.semanticHints+$intent.externalHints))).Trim()
    }
    $composition=Invoke-ProcessRequirementComposition -ProjectRoot $s.controlRoot -FrameworkRoot $s.targetRoot -TargetVersion $s.frameworkVersion -ExpectedProjectConfigIdentity $s.projectConfigIdentity -ExpectedCorrectionsIdentity $current.correctionsIdentity -Profile $context.profile -Role $context.role -Phase $context.phase -Actor $s.actor -TaskIdentity $s.taskIdentity -Capabilities @($authority.observedCapabilities) -Objective $semantic -ActionKind 'SOURCE_WRITE' -ResultKind $view.resultKind -ExactPaths @($s.exactPaths) -ForbiddenPaths @($authority.forbiddenScope)
    foreach($property in $receipt.sourceBindings.PSObject.Properties){
        $value=if($property.Name-ceq'taskIdentity'){$s.taskIdentity}else{$composition.($property.Name)}
        if($value-cne$current.($property.Name)){throw ('SELF_UPDATE_RECOMPOSITION_DRIFT|'+$property.Name)}
    }
    if('PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD'-cin@($composition.evidenceCeilings)){throw 'SELF_UPDATE_STANDARD_DRIFT'}
    $pack=@($composition.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress
    if($utf8.GetByteCount($pack)-gt$composition.selectedRulePackBytes){throw 'SELF_UPDATE_CURRENT_PACK_BUDGET'}
    $all=@($receipt.selectedObligations)+@($composition.selectedRequirements)
    $prep=@($all|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $results=@($all|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $boundaryInput=$null
    if($CheckEvidence){
        $boundaryInput=Read-StrictJson $FinalizeInputPath 'SELF_UPDATE_FINALIZE_INPUT'
        if($boundaryInput.mode-cne'FINALIZE_OUTPUT'-or$boundaryInput.expectedDiscoverReceiptIdentity-cne$s.discoverReceiptIdentity-or[IO.Path]::GetFullPath($boundaryInput.discoverReceiptPath)-cne[IO.Path]::GetFullPath($s.discoverReceiptPath)){throw 'SELF_UPDATE_FINALIZE_BINDING'}
        $originalBoundary=Read-StrictJson $s.admitInputPath 'SELF_UPDATE_ADMIT_INPUT'
        if($boundaryInput.publicDecisionIdentity-cne$originalBoundary.publicDecisionIdentity){throw 'SELF_UPDATE_FINALIZE_DECISION'}
        if($boundaryInput.protectionState-cne$originalBoundary.protectionState){throw 'SELF_UPDATE_FINALIZE_PROTECTION'}
        if(@($prep|Where-Object{$_-cnotin$boundaryInput.preparationReceipts}).Count-or@($results|Where-Object{$_-cnotin$boundaryInput.resultReceipts}).Count){throw 'SELF_UPDATE_CURRENT_OBLIGATIONS_MISSING'}
        if(@($boundaryInput.resultReceipts|Where-Object{$_-clike'OBJECT_POSTIMAGE|*'}).Count-ne@($s.exactPaths).Count){throw 'SELF_UPDATE_FINALIZE_POSTIMAGE_COUNT'}
        foreach($e in $s.projection.objects){$expectedReceipt='OBJECT_POSTIMAGE|'+$e.path+'|'+$e.newIdentity;if(@($boundaryInput.resultReceipts|Where-Object{$_-ceq$expectedReceipt}).Count-ne1){throw ('SELF_UPDATE_FINALIZE_POSTIMAGE|'+$e.path)}}
    }
    return [pscustomobject]@{status=$(if($CheckEvidence){'PASS'}else{'READY_FOR_FINALIZE'});mode=$(if($CheckEvidence){'FINALIZE_OUTPUT'}else{'VERIFY_REFRESH'});originalDiscoverIdentity=$s.discoverReceiptIdentity;originalAdmitDecisionIdentity=$s.admitDecisionIdentity;transactionIdentity=$Expected;currentSourceCompositionIdentity=$composition.sourceCompositionIdentity;currentBindings=$current;preparationRequirements=$prep;resultRequirements=$results;selectedRuleBlocks=@($composition.selectedRequirements);authorityGranted=$false;semanticCorrectnessProven=$false;evidenceGrade='INSTRUCTION_BOUND'}
}
try {
    $control=Resolve-AiwRepositoryRoot $ControlRepositoryPath;$transactionFull=Assert-TransactionPath $control $TransactionPath
    $result=switch($Operation){
        'PREVIEW' {$p=New-Preparation;[pscustomobject]@{status='PREVIEW';exactPaths=@($p.state.exactPaths);candidateCanonical=$p.state.candidateCanonical}}
        'APPLY' {Invoke-Apply (New-Preparation)}
        'REFRESH_PREVIEW' {Invoke-Refresh $transactionFull $ExpectedTransactionIdentity $false}
        'REFRESH' {Invoke-Refresh $transactionFull $ExpectedTransactionIdentity $true}
        'VERIFY_REFRESH' {Invoke-FinalizeCheck $transactionFull $ExpectedTransactionIdentity $false}
        'FINALIZE_CHECK' {Invoke-FinalizeCheck $transactionFull $ExpectedTransactionIdentity $true}
        'RECOVER' {Invoke-Recover $transactionFull $ExpectedTransactionIdentity}
        'COMPLETE' {
            if($FinalizeDecisionIdentity){throw 'SELF_UPDATE_CALLER_DECISION_NOT_ACCEPTED'}
            $checked=Invoke-FinalizeCheck $transactionFull $ExpectedTransactionIdentity $true
            $s=Read-State $transactionFull $ExpectedTransactionIdentity
            $s.completion=[pscustomobject]@{inputIdentity=Get-Identity $FinalizeInputPath;sourceCompositionIdentity=$checked.currentSourceCompositionIdentity;originalDiscoverIdentity=$s.discoverReceiptIdentity;originalAdmitDecisionIdentity=$s.admitDecisionIdentity}
            $s.status='COMPLETE';Write-State $transactionFull $s
            $checked | Add-Member -NotePropertyName completeTransactionIdentity -NotePropertyValue (Get-Identity $transactionFull)
            $checked
        }
    }
    if($AsJson){$result|ConvertTo-Json -Depth 100 -Compress}else{$result}
    exit 0
}catch{if($AsJson){[pscustomobject]@{status='FAIL';reason=$_.Exception.Message;errorLine=$_.InvocationInfo.ScriptLineNumber}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|maintenance-self-update|'+$_.Exception.Message)};exit 2}
