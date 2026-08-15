[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$ToVersion,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 256)]
    [string]$ControllerId,

    [string[]]$LegacyControllerAuthorizationLocator = @(),

    [switch]$LegacyControllerInventoryConfirmed,

    [switch]$AllowDraftCandidate,

    [switch]$Apply,

    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Join-ChildPath([string]$Root, [string]$RelativePath) {
    $result = $Root
    foreach ($segment in $RelativePath.Split('/')) { $result = Join-Path $result $segment }
    return $result
}

function Read-StrictMaterial([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF8_BOM|$Path" }
    $text = $utf8Strict.GetString($bytes)
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { throw "TEXT_NOT_STRICT|$Path" }
    $sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','')
    return [pscustomobject]@{Text=$text;Identity="$($bytes.Length)|$sha"}
}

function Read-StrictText([string]$Path) {
    return (Read-StrictMaterial $Path).Text
}

function Write-StrictText([string]$Path, [string]$Content) {
    $normalized = $Content.Replace("`r`n","`n").Replace("`r","`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    [IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Get-Identity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','')
    return "$($bytes.Length)|$sha"
}

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cne $Path.Trim()) { throw 'PATH_EMPTY' }
    $value = $Path.Replace('\','/')
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/') -or
        -not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw "PATH_INVALID|$Path" }
    foreach ($part in $value.Split('/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw "PATH_COMPONENT|$Path" }
    }
    return $value
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Invoke-Git([string[]]$Arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& git @Arguments 2>$null | ForEach-Object { [string]$_ }); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Output=$output; ExitCode=$code }
}

function Get-GitRoot([string]$Path) {
    $result = Invoke-Git @('-C',$Path,'rev-parse','--show-toplevel')
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) { throw "NOT_GIT_ROOT|$Path" }
    $root = [IO.Path]::GetFullPath([string]$result.Output[-1]).TrimEnd('\')
    $requested = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $root.Equals($requested,[StringComparison]::OrdinalIgnoreCase)) { throw "REPOSITORY_PATH_NOT_TOPLEVEL|$requested" }
    return $root
}

function Assert-NoReparseTree([string]$Path) {
    foreach ($item in @(Get-Item -LiteralPath $Path -Force) + @(Get-ChildItem -LiteralPath $Path -Force -Recurse)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "REPARSE_POINT|$($item.FullName)" }
    }
}

function Get-ManagedBlock([string]$Text, [string]$Source) {
    $begin='<!-- FRAMEWORK-MANAGED:BEGIN -->'; $end='<!-- FRAMEWORK-MANAGED:END -->'
    if ([regex]::Matches($Text,[regex]::Escape($begin)).Count -ne 1 -or [regex]::Matches($Text,[regex]::Escape($end)).Count -ne 1) { throw "BOOTSTRAP_MARKERS|$Source" }
    $start=$Text.IndexOf($begin,[StringComparison]::Ordinal); $endStart=$Text.IndexOf($end,[StringComparison]::Ordinal)
    if ($start -lt 0 -or $endStart -le $start) { throw "BOOTSTRAP_MARKER_ORDER|$Source" }
    return [pscustomobject]@{ Start=$start; Length=($endStart+$end.Length-$start); Text=$Text.Substring($start,$endStart+$end.Length-$start) }
}

function Render-Bootstrap([string]$Template, $Config, [string]$Version) {
    $text=$Template.Replace('{{PROJECT_ID}}',[string]$Config.id).Replace('{{DISPLAY_NAME}}',[string]$Config.displayName).Replace('{{FRAMEWORK_VERSION}}',$Version)
    if ($text -match '\{\{[A-Z0-9_]+\}\}') { throw 'BOOTSTRAP_TOKEN_UNRESOLVED' }
    return $text
}

function Get-CanonicalController([string]$Project, [string]$Controller) {
    return ([ordered]@{schemaVersion=1;projectId=$Project;controllerId=$Controller;controllerEpoch=1;state='CURRENT'} | ConvertTo-Json -Compress) + "`n"
}

function Read-CanonicalController([string]$Path,[string]$ExpectedProject,[string]$ExpectedController) {
    $text=Read-StrictText $Path
    try{$controller=$text|ConvertFrom-Json}catch{throw 'CONTROLLER_JSON_INVALID'}
    $required=@('schemaVersion','projectId','controllerId','controllerEpoch','state')
    if(@(Compare-Object $required @($controller.PSObject.Properties.Name) -CaseSensitive).Count-ne0-or
        [int]$controller.schemaVersion-ne1-or[string]$controller.projectId-cne$ExpectedProject-or
        [string]$controller.controllerId-cne$ExpectedController-or[string]$controller.controllerId-cne([string]$controller.controllerId).Trim()-or([string]$controller.controllerId).Length-gt256-or
        -not($controller.controllerEpoch-is[int32]-or$controller.controllerEpoch-is[int64])-or[int64]$controller.controllerEpoch-lt1-or[string]$controller.state-cne'CURRENT'){throw'CONTROLLER_IDENTITY'}
    $canonical=([ordered]@{schemaVersion=1;projectId=$ExpectedProject;controllerId=$ExpectedController;controllerEpoch=[int64]$controller.controllerEpoch;state='CURRENT'}|ConvertTo-Json -Compress)+"`n"
    if($text-cne$canonical){throw'CONTROLLER_NOT_CANONICAL'}
    return $controller
}

function Read-CanonicalRevocation([string]$Path,[string]$ExpectedProject,[string]$ControlRoot) {
    $text=Read-StrictText $Path
    try{$ledger=$text|ConvertFrom-Json}catch{throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
    $required=@('schemaVersion','projectId','migration','controllerId','controllerEpoch','legacyProjectControllerPackages','domainOwnerPackages','successorAuthorization')
    if(@(Compare-Object $required @($ledger.PSObject.Properties.Name) -CaseSensitive).Count-ne0-or
        -not(Test-JsonInteger $ledger.schemaVersion)-or[int64]$ledger.schemaVersion-ne1-or
        [string]$ledger.projectId-cne$ExpectedProject-or[string]$ledger.migration-cne'1.6.0'-or
        -not($ledger.controllerId-is[string])-or[string]::IsNullOrWhiteSpace([string]$ledger.controllerId)-or
        [string]$ledger.controllerId-cne([string]$ledger.controllerId).Trim()-or([string]$ledger.controllerId).Length-gt256-or
        -not(Test-JsonInteger $ledger.controllerEpoch)-or[int64]$ledger.controllerEpoch-ne1-or
        [string]$ledger.domainOwnerPackages-cne'PRESERVE_BY_ORIGINAL_INVALIDATORS'-or
        [string]$ledger.successorAuthorization-cne'REISSUE_FROM_CURRENT_TASK_ONLY'){throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
    if($null-eq$ledger.legacyProjectControllerPackages-or$ledger.legacyProjectControllerPackages-is[string]){throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $canonicalLegacy=@()
    foreach($entry in @($ledger.legacyProjectControllerPackages)){
        $entryRequired=@('locator','identity','disposition')
        if($null-eq$entry-or@(Compare-Object $entryRequired @($entry.PSObject.Properties.Name) -CaseSensitive).Count-ne0){throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
        try{$locator=Normalize-RelativePath ([string]$entry.locator)}catch{throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
        if([string]$entry.locator-cne$locator-or-not$seen.Add($locator)-or[string]$entry.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$entry.disposition-cne'STALE_AUDIT_ONLY_NO_ACTION'){throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
        try{$legacyPath=Join-ChildPath $ControlRoot $locator}catch{throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
        if(-not(Test-Path -LiteralPath $legacyPath -PathType Leaf)-or(Get-Identity $legacyPath)-cne[string]$entry.identity){throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
        $canonicalLegacy += [ordered]@{locator=$locator;identity=[string]$entry.identity;disposition='STALE_AUDIT_ONLY_NO_ACTION'}
    }
    $ordered=[ordered]@{schemaVersion=1;projectId=$ExpectedProject;migration='1.6.0';controllerId=[string]$ledger.controllerId;controllerEpoch=1;legacyProjectControllerPackages=@($canonicalLegacy);domainOwnerPackages='PRESERVE_BY_ORIGINAL_INVALIDATORS';successorAuthorization='REISSUE_FROM_CURRENT_TASK_ONLY'}
    $canonical=(($ordered|ConvertTo-Json -Depth 8).Replace("`r`n","`n").Replace("`r","`n"))+"`n"
    if($text-cne$canonical){throw'ALREADY_UPGRADED_REVOCATION_DRIFT'}
    return $ledger
}

function Assert-LegacyInventory([string]$ControlRoot,$Inventory) {
    foreach($entry in @($Inventory)){
        try{$full=Join-ChildPath $ControlRoot ([string]$entry.locator)}catch{throw "LEGACY_AUTHORIZATION_PREIMAGE_DRIFT|$([string]$entry.locator)"}
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)-or(Get-Identity $full)-cne[string]$entry.identity){throw "LEGACY_AUTHORIZATION_PREIMAGE_DRIFT|$([string]$entry.locator)"}
    }
}

function Get-TransactionPaths([string]$Root) {
    return [pscustomobject]@{
        State=Join-ChildPath $Root 'state.json'; OldProject=Join-ChildPath $Root 'old/project.json'; OldBootstrap=Join-ChildPath $Root 'old/BOOTSTRAP.md'
        NewProject=Join-ChildPath $Root 'new/project.json'; NewBootstrap=Join-ChildPath $Root 'new/BOOTSTRAP.md'; NewController=Join-ChildPath $Root 'new/controller.json'; NewRevocation=Join-ChildPath $Root 'new/revocation.json'
    }
}

function Write-State([string]$Root, $State, [string]$Phase) {
    $State.phase=$Phase; Write-StrictText (Join-ChildPath $Root 'state.json') ($State | ConvertTo-Json -Depth 8)
}

function Assert-Transaction([string]$Root, [string]$ExpectedProject) {
    $resolved=[IO.Path]::GetFullPath($Root).TrimEnd('\'); $project=[IO.Path]::GetFullPath((Split-Path -Parent $Root)).TrimEnd('\')
    if (-not $resolved.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -cne '.framework-upgrade-transaction') { throw 'TRANSACTION_BOUNDARY' }
    Assert-NoReparseTree $Root
    $paths=Get-TransactionPaths $Root; $state=(Read-StrictText $paths.State)|ConvertFrom-Json
    if ([int]$state.schemaVersion -ne 1 -or [string]$state.projectId -cne $ExpectedProject -or
        [string]::IsNullOrWhiteSpace([string]$state.controllerId) -or [string]$state.toVersion -cne '1.6.0') { throw 'TRANSACTION_STATE' }
    foreach($pair in @(@('OldProject','oldProjectIdentity'),@('OldBootstrap','oldBootstrapIdentity'),@('NewProject','newProjectIdentity'),@('NewBootstrap','newBootstrapIdentity'),@('NewController','newControllerIdentity'),@('NewRevocation','newRevocationIdentity'))){
        $path=[string]$paths.($pair[0]); if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-Identity $path)-cne[string]$state.($pair[1])){throw "TRANSACTION_MATERIAL|$($pair[0])"}
    }
    $expectedDirectories=@('old','new')
    $actualDirectories=@(Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force|ForEach-Object{$_.FullName.Substring($Root.Length+1).Replace('\','/')})
    if(@(Compare-Object $expectedDirectories $actualDirectories -CaseSensitive).Count-ne0){throw'TRANSACTION_DIRECTORY_INVENTORY'}
    $requiredFiles=@('state.json','old/project.json','old/BOOTSTRAP.md','new/project.json','new/BOOTSTRAP.md','new/controller.json','new/revocation.json')
    $knownIdentities=@([string]$state.oldProjectIdentity,[string]$state.oldBootstrapIdentity,[string]$state.newProjectIdentity,[string]$state.newBootstrapIdentity,[string]$state.newControllerIdentity,[string]$state.newRevocationIdentity)
    foreach($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force){
        $relative=$file.FullName.Substring($Root.Length+1).Replace('\','/')
        if($relative -in $requiredFiles){continue}
        if($relative -match '^(?:swap|backup)-(?:project|bootstrap|controller|revocation)\.(?:tmp|bak)$' -and (Get-Identity $file.FullName) -in $knownIdentities){continue}
        throw "TRANSACTION_UNKNOWN_BYTES|$relative"
    }
    return [pscustomobject]@{Paths=$paths;State=$state}
}

function Replace-Existing([string]$TransactionRoot,[string]$Label,[string]$Source,[string]$Destination,[string]$ExpectedCurrentIdentity,[string]$ExpectedResultIdentity) {
    if(-not(Test-Path -LiteralPath $Destination -PathType Leaf)-or(Get-Identity $Destination)-cne$ExpectedCurrentIdentity){throw "REPLACE_PREIMAGE_DRIFT|$Destination"}
    $temporary=Join-Path $TransactionRoot "swap-$Label.tmp"; $backup=Join-Path $TransactionRoot "backup-$Label.bak"
    [IO.File]::Copy($Source,$temporary,$false); [IO.File]::Replace($temporary,$Destination,$backup,$true)
    if((Get-Identity $Destination)-cne $ExpectedResultIdentity){throw "REPLACE_IDENTITY|$Destination"}
    if(Test-Path -LiteralPath $backup){[IO.File]::Delete($backup)}
}

function Create-New([string]$TransactionRoot,[string]$Label,[string]$Source,[string]$Destination,[string]$ExpectedIdentity) {
    if(Test-Path -LiteralPath $Destination){throw "NEW_DESTINATION_EXISTS|$Destination"}
    $temporary=Join-Path $TransactionRoot "swap-$Label.tmp"; [IO.File]::Copy($Source,$temporary,$false); [IO.File]::Move($temporary,$Destination)
    if((Get-Identity $Destination)-cne $ExpectedIdentity){throw "CREATE_IDENTITY|$Destination"}
}

function Restore-Old([string]$TransactionRoot,[string]$Label,[string]$Material,[string]$Destination,[string]$OldIdentity,[string]$NewIdentity) {
    if(-not(Test-Path -LiteralPath $Destination -PathType Leaf)){throw "RESTORE_DESTINATION_MISSING|$Destination"}
    $current=Get-Identity $Destination
    if($current -ceq $OldIdentity){return}
    if($current -cne $NewIdentity){throw "RESTORE_UNKNOWN_IDENTITY|$Destination"}
    Replace-Existing $TransactionRoot $Label $Material $Destination $NewIdentity $OldIdentity
}

function Remove-NewIfKnown([string]$Path,[string]$Identity) {
    if(-not(Test-Path -LiteralPath $Path)){return}
    if((Get-Identity $Path)-cne $Identity){throw "NEW_FILE_DRIFT|$Path"}
    [IO.File]::Delete($Path)
}

function Remove-Transaction([string]$Root,[string]$ExpectedProject) {
    $null=Assert-Transaction $Root $ExpectedProject
    [IO.Directory]::Delete([IO.Path]::GetFullPath($Root),$true)
}

function Recover-Transaction([string]$Root,[string]$ControlRoot,[string]$ExpectedProject,[string]$ExpectedVersion,[string]$ExpectedController) {
    $checked=Assert-Transaction $Root $ExpectedProject; $p=$checked.Paths; $s=$checked.State
    if([string]$s.toVersion-cne$ExpectedVersion-or[string]$s.controllerId-cne$ExpectedController){throw'TRANSACTION_REQUEST_DRIFT'}
    $project=Join-Path $ControlRoot 'project.json'; $bootstrap=Join-Path $ControlRoot 'BOOTSTRAP.md'; $controller=Join-Path $ControlRoot 'controller.json'; $revocation=Join-ChildPath $ControlRoot 'tasks/archive/FRAMEWORK-1.6.0-CONTROLLER-REVOCATION.json'
    $allNew=(Test-Path $controller -PathType Leaf)-and(Test-Path $revocation -PathType Leaf)-and(Get-Identity $project)-ceq[string]$s.newProjectIdentity-and(Get-Identity $bootstrap)-ceq[string]$s.newBootstrapIdentity-and(Get-Identity $controller)-ceq[string]$s.newControllerIdentity-and(Get-Identity $revocation)-ceq[string]$s.newRevocationIdentity
    if($allNew){Remove-Transaction $Root $ExpectedProject; return 'RECOVERED_COMMITTED'}
    Restore-Old $Root 'project' $p.OldProject $project ([string]$s.oldProjectIdentity) ([string]$s.newProjectIdentity)
    Restore-Old $Root 'bootstrap' $p.OldBootstrap $bootstrap ([string]$s.oldBootstrapIdentity) ([string]$s.newBootstrapIdentity)
    Remove-NewIfKnown $controller ([string]$s.newControllerIdentity); Remove-NewIfKnown $revocation ([string]$s.newRevocationIdentity)
    Remove-Transaction $Root $ExpectedProject; return 'RECOVERED_ROLLED_BACK'
}

if(-not $WorkspaceRoot){$WorkspaceRoot=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)}
$workspace=[IO.Path]::GetFullPath($WorkspaceRoot); $repo=Get-GitRoot ([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).Path))
$controlRoot=Join-Path $repo '.ai-workspace'; if(-not(Test-Path -LiteralPath $controlRoot -PathType Container)){throw 'REPO_LOCAL_CONTROL_MISSING'}
Assert-NoReparseTree $controlRoot
$projectFile=Join-Path $controlRoot 'project.json'; $bootstrapFile=Join-Path $controlRoot 'BOOTSTRAP.md'; $controllerFile=Join-Path $controlRoot 'controller.json'; $revocationFile=Join-ChildPath $controlRoot 'tasks/archive/FRAMEWORK-1.6.0-CONTROLLER-REVOCATION.json'; $transactionRoot=Join-Path $controlRoot '.framework-upgrade-transaction'
if($Apply -and (Test-Path -LiteralPath $transactionRoot -PathType Container)){Write-Output (Recover-Transaction $transactionRoot $controlRoot $ProjectId $ToVersion $ControllerId); return}
if(Test-Path -LiteralPath $transactionRoot){throw 'UPGRADE_TRANSACTION_PENDING'}

$targetRoot=Join-ChildPath $workspace "framework/versions/$ToVersion"; if(-not(Test-Path -LiteralPath $targetRoot -PathType Container)){throw 'TARGET_FRAMEWORK_MISSING'}
$targetVersion=(Read-StrictText (Join-Path $targetRoot 'VERSION.json'))|ConvertFrom-Json
if([string]$targetVersion.version -cne $ToVersion){throw 'TARGET_VERSION_IDENTITY'}
if([string]$targetVersion.lifecycle -cne 'STABLE' -and -not($AllowDraftCandidate -and [string]$targetVersion.lifecycle -ceq 'DRAFT')){throw 'TARGET_NOT_CONSUMABLE'}
if($ToVersion -cne '1.6.0'){throw 'THIS_CANDIDATE_ONLY_SUPPORTS_1_6_0'}

$initialProject=Read-StrictMaterial $projectFile
$config=$initialProject.Text|ConvertFrom-Json
if([string]$config.id -cne $ProjectId -or [int]$config.schemaVersion -notin @(2,3) -or [string]$config.controlPlaneLayout -cne 'repo-local' -or [string]$config.repositoryRoot -cne '..'){throw 'PROJECT_IDENTITY_OR_LAYOUT'}
$fromVersion=[string]$config.frameworkVersion
if($fromVersion -ceq '1.6.0'){
    if([int]$config.schemaVersion-ne3-or$null-eq$config.PSObject.Properties['frameworkCapabilities']-or-not(Test-Path -LiteralPath $controllerFile -PathType Leaf)-or-not(Test-Path -LiteralPath $revocationFile -PathType Leaf)){throw 'ALREADY_UPGRADED_CONTROL_DRIFT'}
    $currentController=Read-CanonicalController $controllerFile $ProjectId $ControllerId
    $existingRevocation=Read-CanonicalRevocation $revocationFile $ProjectId $controlRoot
    Write-Output "ALREADY_UPGRADED|project=$ProjectId|framework=1.6.0|controller=$ControllerId|epoch=$([int64]$currentController.controllerEpoch)"
    return
}
if(-not $LegacyControllerInventoryConfirmed){throw 'LEGACY_CONTROLLER_INVENTORY_NOT_FROZEN'}
if($fromVersion -notin @('1.4.1','1.5.0','1.5.1','1.5.2')){throw 'DIRECT_SOURCE_VERSION_UNSUPPORTED'}
if(Test-Path -LiteralPath $controllerFile){throw 'CONTROLLER_OBJECT_DRIFT'}
if(Test-Path -LiteralPath $revocationFile){throw 'REVOCATION_LEDGER_DRIFT'}

$status=Invoke-Git @('-C',$repo,'-c','core.excludesFile=','status','--porcelain=v1','--untracked-files=all')
if($status.ExitCode -ne 0 -or $status.Output.Count -ne 0){throw 'UPGRADE_REQUIRES_CLEAN_GIT'}

$sourceBootstrapTemplate=Join-ChildPath $workspace "framework/versions/$fromVersion/project-starter/BOOTSTRAP.md"; $targetBootstrapTemplate=Join-Path $targetRoot 'project-starter/BOOTSTRAP.md'
$initialBootstrap=Read-StrictMaterial $bootstrapFile; $currentBootstrap=$initialBootstrap.Text; $sourceRendered=Render-Bootstrap (Read-StrictText $sourceBootstrapTemplate) $config $fromVersion
$currentBlock=Get-ManagedBlock $currentBootstrap $bootstrapFile; $sourceBlock=Get-ManagedBlock $sourceRendered $sourceBootstrapTemplate
if($currentBlock.Text -cne $sourceBlock.Text){throw 'BOOTSTRAP_MANAGED_DRIFT'}
$targetRendered=Render-Bootstrap (Read-StrictText $targetBootstrapTemplate) $config $ToVersion; $targetBlock=Get-ManagedBlock $targetRendered $targetBootstrapTemplate
$targetBootstrap=$currentBootstrap.Substring(0,$currentBlock.Start)+$targetBlock.Text+$currentBootstrap.Substring($currentBlock.Start+$currentBlock.Length)

$config.schemaVersion=3; $config.frameworkVersion=$ToVersion
if($config.PSObject.Properties.Name -notcontains 'frameworkCapabilities'){$config|Add-Member -NotePropertyName frameworkCapabilities -NotePropertyValue ([pscustomobject]@{})}
$targetConfig=($config|ConvertTo-Json -Depth 100)+"`n"; $targetController=Get-CanonicalController $ProjectId $ControllerId
$legacyInventory=@(); $seenLegacy=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach($locator in $LegacyControllerAuthorizationLocator){
    $relative=Normalize-RelativePath $locator
    if(-not$seenLegacy.Add($relative)){throw "LEGACY_AUTHORIZATION_DUPLICATE|$relative"}
    $full=Join-ChildPath $controlRoot $relative
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "LEGACY_AUTHORIZATION_NOT_FOUND|$relative"}
    try{$legacyPackage=(Read-StrictText $full)|ConvertFrom-Json}catch{throw "LEGACY_AUTHORIZATION_INVALID|$relative"}
    if([string]$legacyPackage.issuerRole-ceq'DOMAIN_OWNER'){throw "DOMAIN_OWNER_REVOCATION_FORBIDDEN|$relative"}
    if([string]$legacyPackage.issuerRole-cne'PROJECT_CONTROLLER'-or[string]$legacyPackage.lifecycle-cne'ACTIVE'){throw "LEGACY_CONTROLLER_AUTHORIZATION_NOT_ACTIVE|$relative"}
    $legacyInventory += [ordered]@{locator=$relative;identity=Get-Identity $full;disposition='STALE_AUDIT_ONLY_NO_ACTION'}
}
$revocation=[ordered]@{schemaVersion=1;projectId=$ProjectId;migration='1.6.0';controllerId=$ControllerId;controllerEpoch=1;legacyProjectControllerPackages=@($legacyInventory);domainOwnerPackages='PRESERVE_BY_ORIGINAL_INVALIDATORS';successorAuthorization='REISSUE_FROM_CURRENT_TASK_ONLY'}
$targetRevocation=($revocation|ConvertTo-Json -Depth 8)+"`n"

Write-Output "PREVIEW|project=$ProjectId|framework=$fromVersion->$ToVersion|controller=$ControllerId|epoch=1|legacyControllerPackages=$($legacyInventory.Count)|domainOwnerDisposition=PRESERVE_BY_ORIGINAL_INVALIDATORS"
if(-not $Apply -or -not $PSCmdlet.ShouldProcess($controlRoot,'Apply recoverable Framework 1.6.0 controller migration')){return}

if([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE')-eq'1'-and[Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_MUTATE_PROJECT_AFTER_INITIAL_READ')-eq'1'){
    $currentProjectText=Read-StrictText $projectFile; Write-StrictText $projectFile ($currentProjectText.TrimEnd("`n")+' '+"`n")
}
if([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE')-eq'1'-and[Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_MUTATE_LEGACY_AFTER_INVENTORY')-eq'1'-and$legacyInventory.Count-gt0){
    $testLegacy=Join-ChildPath $controlRoot ([string]$legacyInventory[0].locator);$testLegacyText=Read-StrictText $testLegacy;Write-StrictText $testLegacy ($testLegacyText.TrimEnd("`n")+' '+"`n")
}
Assert-LegacyInventory $controlRoot $legacyInventory
if((Get-Identity $projectFile)-cne$initialProject.Identity-or(Get-Identity $bootstrapFile)-cne$initialBootstrap.Identity){throw'INITIAL_PREIMAGE_DRIFT'}

$p=Get-TransactionPaths $transactionRoot
try{
    New-Item -ItemType Directory -Path (Join-ChildPath $transactionRoot 'old') -Force|Out-Null; New-Item -ItemType Directory -Path (Join-ChildPath $transactionRoot 'new') -Force|Out-Null
    [IO.File]::Copy($projectFile,$p.OldProject,$false); [IO.File]::Copy($bootstrapFile,$p.OldBootstrap,$false)
    if((Get-Identity $p.OldProject)-cne$initialProject.Identity-or(Get-Identity $p.OldBootstrap)-cne$initialBootstrap.Identity){throw'INITIAL_PREIMAGE_COPY_DRIFT'}
    Write-StrictText $p.NewProject $targetConfig; Write-StrictText $p.NewBootstrap $targetBootstrap; Write-StrictText $p.NewController $targetController; Write-StrictText $p.NewRevocation $targetRevocation
    $state=[pscustomobject]@{schemaVersion=1;projectId=$ProjectId;controllerId=$ControllerId;fromVersion=$fromVersion;toVersion=$ToVersion;phase='INITIALIZING';oldProjectIdentity=$initialProject.Identity;oldBootstrapIdentity=$initialBootstrap.Identity;newProjectIdentity=Get-Identity $p.NewProject;newBootstrapIdentity=Get-Identity $p.NewBootstrap;newControllerIdentity=Get-Identity $p.NewController;newRevocationIdentity=Get-Identity $p.NewRevocation}
    Write-State $transactionRoot $state 'PREPARED'; $null=Assert-Transaction $transactionRoot $ProjectId
    if([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE')-eq'1'-and[Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_MUTATE_PROJECT_AFTER_PREPARE')-eq'1'){
        $currentProjectText=Read-StrictText $projectFile; Write-StrictText $projectFile ($currentProjectText.TrimEnd("`n")+' '+"`n")
    }
    Replace-Existing $transactionRoot 'project' $p.NewProject $projectFile $state.oldProjectIdentity $state.newProjectIdentity; Write-State $transactionRoot $state 'PROJECT_REPLACED'
    Replace-Existing $transactionRoot 'bootstrap' $p.NewBootstrap $bootstrapFile $state.oldBootstrapIdentity $state.newBootstrapIdentity; Write-State $transactionRoot $state 'BOOTSTRAP_REPLACED'
    Create-New $transactionRoot 'controller' $p.NewController $controllerFile $state.newControllerIdentity; Write-State $transactionRoot $state 'CONTROLLER_CREATED'
    if([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE') -eq '1' -and [Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_CONTROLLER_CREATE') -eq '1'){[Diagnostics.Process]::GetCurrentProcess().Kill()}
    if([Environment]::GetEnvironmentVariable('AI_WORKSPACE_FRAMEWORK_TEST_MODE')-eq'1'-and[Environment]::GetEnvironmentVariable('AI_WORKSPACE_UPGRADE_TEST_MUTATE_LEGACY_BEFORE_REVOCATION')-eq'1'-and$legacyInventory.Count-gt0){
        $testLegacy=Join-ChildPath $controlRoot ([string]$legacyInventory[0].locator);$testLegacyText=Read-StrictText $testLegacy;Write-StrictText $testLegacy ($testLegacyText.TrimEnd("`n")+' '+"`n")
    }
    Assert-LegacyInventory $controlRoot $legacyInventory
    Create-New $transactionRoot 'revocation' $p.NewRevocation $revocationFile $state.newRevocationIdentity; Write-State $transactionRoot $state 'COMMITTED'
    Remove-Transaction $transactionRoot $ProjectId
}catch{
    $originalFailure=$_.Exception.Message
    if(Test-Path -LiteralPath $transactionRoot -PathType Container){
        try{$recovered=Recover-Transaction $transactionRoot $controlRoot $ProjectId $ToVersion $ControllerId}
        catch{throw "UPGRADE_FAILED|PRESERVED_UNKNOWN_BYTES|$originalFailure|$($_.Exception.Message)"}
        throw "UPGRADE_FAILED|$recovered|$originalFailure"
    }
    throw
}
Write-Output "UPDATED|project=$ProjectId|framework=$ToVersion|controller=$ControllerId|epoch=1|revocations=$($legacyInventory.Count)|git=UNCHANGED"
