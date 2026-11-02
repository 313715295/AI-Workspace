Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Utf8Strict = [Text.UTF8Encoding]::new($false, $true)
$script:RootReadContext = $null

# Private to one native root invocation. Every read still observes the actual
# path and bytes; only strict parsing of identical bytes is shared.
function Copy-AiwRootJsonValue($Value) {
    if($null-eq$Value){return $null}
    if($Value-is[Array]){
        $copy=[object[]]::new($Value.Length)
        for($index=0;$index-lt$Value.Length;$index++){$copy[$index]=Copy-AiwRootJsonValue $Value[$index]}
        return ,$copy
    }
    if($Value-is[pscustomobject]){
        $copy=[ordered]@{}
        foreach($property in $Value.PSObject.Properties){$copy[$property.Name]=Copy-AiwRootJsonValue $property.Value}
        return [pscustomobject]$copy
    }
    return $Value
}

function Enter-AiwRootReadContext {
    if($null-eq$script:RootReadContext){
        $script:RootReadContext=[pscustomobject]@{depth=0;documents=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)}
    }
    $script:RootReadContext.depth++
    return $script:RootReadContext
}

function Exit-AiwRootReadContext($Context) {
    if($null-eq$Context){return}
    $Context.depth--
    if($Context.depth-eq0){$Context.documents.Clear();if([object]::ReferenceEquals($Context,$script:RootReadContext)){$script:RootReadContext=$null}}
}

function Test-AiwRootJsonSame($Left,$Right) {
    $path=Get-AiwContainedPath (Split-Path -Parent $PSScriptRoot) 'framework/versions/2.0.0/scripts/ContentSources.psm1'
    $module=@(Import-Module $path -PassThru -ErrorAction Stop)[0]
    return (& $module.ExportedCommands['ConvertTo-AiwContentCanonicalJson'] $Left)-ceq(& $module.ExportedCommands['ConvertTo-AiwContentCanonicalJson'] $Right)
}

# Root-entry representation only. These private helpers do not execute an
# adoption body or change its in-process object/error contract.
function Initialize-AiwRootNativeOutput($Invocation,[string]$EntryPath) {
    $native=$false
    if([string]::IsNullOrEmpty($Invocation.ScriptName)-and$Invocation.InvocationName-cnotin@('&','.')){
        $arguments=[Environment]::GetCommandLineArgs();$profile=$false;$noninteractive=$false
        for($i=1;$i-lt$arguments.Length;$i++){
            $option=$arguments[$i]
            if($option-ieq'-File'){
                if($profile-and$noninteractive-and$i+1-lt$arguments.Length){
                    try{$native=[IO.Path]::GetFullPath($arguments[$i+1]).Equals([IO.Path]::GetFullPath($EntryPath),[StringComparison]::OrdinalIgnoreCase)}catch{$native=$false}
                }
                break
            }
            if($option-ieq'-NoProfile'){$profile=$true;continue}
            if($option-ieq'-NonInteractive'){$noninteractive=$true;continue}
            if($option-ieq'-NoLogo'){continue}
            if($option-ieq'-OutputFormat'-or$option-ieq'-InputFormat'){
                if($i+1-ge$arguments.Length-or$arguments[$i+1]-ine'Text'){break};$i++;continue
            }
            if($option-ieq'-ExecutionPolicy'){
                if($i+1-ge$arguments.Length-or$arguments[$i+1]-inotmatch'^(Bypass|RemoteSigned|AllSigned|Restricted|Unrestricted|Undefined|Default)$'){break};$i++;continue
            }
            # NoExit, abbreviations, Command, host APIs and unknown options
            # retain the host's original representation and writer lifetime.
            break
        }
    }
    if($native){
        $encoding=[Text.UTF8Encoding]::new($false,$true)
        if([Console]::IsOutputRedirected){$writer=[IO.StreamWriter]::new([Console]::OpenStandardOutput(),$encoding,4096,$true);$writer.AutoFlush=$true;[Console]::SetOut($writer)}
        if([Console]::IsErrorRedirected){$writer=[IO.StreamWriter]::new([Console]::OpenStandardError(),$encoding,4096,$true);$writer.AutoFlush=$true;[Console]::SetError($writer)}
    }
    return [pscustomobject]@{NativeFile=$native;RedirectedError=($native-and[Console]::IsErrorRedirected)}
}
function ConvertTo-AiwRootOutputRecord($Record) {
    if($Record-is[string]){return $Record}
    return ConvertTo-Json -InputObject $Record -Depth 100 -Compress -WarningAction Stop
}
function ConvertTo-AiwRootErrorData([Management.Automation.ErrorRecord]$Record,[Collections.Generic.List[object]]$Ancestors) {
    $result=[ordered]@{
        reason=$Record.Exception.Message;exceptionType=$Record.Exception.GetType().FullName
        exception=$Record.Exception.ToString();errorDetails=$(if($null-ne$Record.ErrorDetails){$Record.ErrorDetails.Message}else{$null})
        exceptionStackTrace=$Record.Exception.StackTrace;scriptStackTrace=$Record.ScriptStackTrace
        fullyQualifiedErrorId=$Record.FullyQualifiedErrorId;categoryInfo=$Record.CategoryInfo.ToString()
        invocation=[ordered]@{scriptName=$Record.InvocationInfo.ScriptName;scriptLineNumber=$Record.InvocationInfo.ScriptLineNumber;offsetInLine=$Record.InvocationInfo.OffsetInLine;line=$Record.InvocationInfo.Line;positionMessage=$Record.InvocationInfo.PositionMessage}
    }
    if($null-eq$Ancestors){$Ancestors=[Collections.Generic.List[object]]::new()}
    if(@($Ancestors|Where-Object{[object]::ReferenceEquals($_,$Record)}).Count-eq0){
        $Ancestors.Add($Record)
        try{
            foreach($name in @('registrationError','cleanupError','sourceScopeCleanupError')){
                if($Record.Exception.Data.Contains($name)-and$Record.Exception.Data[$name]-is[Management.Automation.ErrorRecord]){
                    $result[$name]=ConvertTo-AiwRootErrorData $Record.Exception.Data[$name] $Ancestors
                }
            }
        }finally{$Ancestors.RemoveAt($Ancestors.Count-1)}
    }
    return $result
}
function Write-AiwRootNativeError([Management.Automation.ErrorRecord]$Record) {
    $data=ConvertTo-AiwRootErrorData $Record $null
    [Console]::Error.WriteLine((ConvertTo-Json -InputObject $data -Depth 100 -Compress -WarningAction Stop))
    [Console]::Error.Flush()
}

function Enter-AiwRootProjectSourceScope {
    param([Parameter(Mandatory)][string]$ProjectRoot,[ValidateSet('OBSERVE','WRITE','PUBLICATION')][string]$Mode='OBSERVE')
    $readContext=Enter-AiwRootReadContext
    if($Mode-ceq'OBSERVE'){return [pscustomobject]@{ReadContext=$readContext;ObservationOnly=$true}}
    # This known root implementation is resolved before reading project config.
    # Historical packages without the capability retain their original path.
    $path=Join-Path $PSScriptRoot '../framework/versions/2.0.0/scripts/ProjectSourcePublication.psm1'
    try {
        if(-not[IO.File]::Exists($path)){return [pscustomobject]@{ReadContext=$readContext;ObservationOnly=$true}}
        $module=@(Import-Module $path -PassThru -ErrorAction Stop)[0]
        $scope=& $module.ExportedCommands['Enter-AiwProjectSourceScope'] -ProjectRoot $ProjectRoot -Mode $Mode
        if($null-eq$scope){return [pscustomobject]@{ReadContext=$readContext;ObservationOnly=$true}}
        $scope|Add-Member -NotePropertyName OwnerModule -NotePropertyValue $module -Force
        $scope|Add-Member -NotePropertyName ReadContext -NotePropertyValue $readContext -Force
        $scope|Add-Member -NotePropertyName ObservationOnly -NotePropertyValue $false -Force
        return $scope
    }catch{Exit-AiwRootReadContext $readContext;throw}
}
function Exit-AiwRootProjectSourceScope($Scope){
    if($null-ne$Scope){
        try{if(-not$Scope.ObservationOnly){& $Scope.OwnerModule.ExportedCommands['Exit-AiwProjectSourceScope'] $Scope}}
        finally{Exit-AiwRootReadContext $Scope.ReadContext}
    }
}
Export-ModuleMember -Function Enter-AiwRootProjectSourceScope,Exit-AiwRootProjectSourceScope

function Invoke-AiwRootProjectSourceScope {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[ValidateSet('OBSERVE','WRITE','PUBLICATION')][string]$Mode='OBSERVE',[Parameter(Mandatory)][scriptblock]$Body,[object[]]$ArgumentList=@())
    if($Mode-ceq'OBSERVE'){
        $lease=Enter-AiwRootProjectSourceScope -ProjectRoot $ProjectRoot -Mode OBSERVE
        try{return & $Body @ArgumentList}finally{Exit-AiwRootProjectSourceScope $lease}
    }
 $readContext=Enter-AiwRootReadContext
 try {
 $path=Join-Path $PSScriptRoot '../framework/versions/2.0.0/scripts/ProjectSourcePublication.psm1'
 if(-not[IO.File]::Exists($path)){return & $Body @ArgumentList}
 $module=@(Import-Module $path -PassThru -ErrorAction Stop)[0]
 if(-not$module.ExportedCommands.ContainsKey("Invoke-AiwProjectSourceScope")){throw "SOURCE_PUBLICATION_FIXED_IMPLEMENTATION_REQUIRED"}
 & $module.ExportedCommands['Invoke-AiwProjectSourceScope'] -ProjectRoot $ProjectRoot -Mode $Mode -Body $Body -ArgumentList $ArgumentList
 } finally {Exit-AiwRootReadContext $readContext}
}
Export-ModuleMember -Function Invoke-AiwRootProjectSourceScope




# Root adoption alone chooses the original implementation. This bootstrap is
# observational; the normal admission/transaction still rechecks all authority
# and complete source observations before its first write.
function Get-AiwRootAdoptionOwnerProof($Root,$Parameters){
    $root=Resolve-AiwRepositoryRoot $Root
    $reads=[Collections.Generic.List[object]]::new()
    function Read-OwnerEvidence($path,$expected){
        $d=Read-AiwProjectJson $path 'ADOPTION_SCOPE_ORIGIN'
        if($expected-and$d.Identity-cne$expected){throw 'ADOPTION_SCOPE_ORIGIN_DRIFT'}
        $reads.Add([pscustomobject]@{path=$d.Path;identity=$d.Identity})
        return $d
    }
    $binding=$null;$version=$null
    if($Parameters.ContainsKey('RecoverRuntimeAdoption')-and$Parameters['RecoverRuntimeAdoption']){
        $matches=@(foreach($relative in @('.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
            $path=Get-AiwContainedPath $root $relative
            if([IO.File]::Exists($path)){
                $d=Read-AiwProjectJson $path 'ADOPTION_SCOPE_TRANSACTION'
                if($d.Identity-ceq$Parameters['ExpectedAdoptionTransactionIdentity']){$d}
            }
        })
        if($matches.Count-ne1){throw 'ADOPTION_TRANSACTION_DRIFT'}
        $d=Read-OwnerEvidence $matches[0].Path $matches[0].Identity;$t=$d.Value
        if($t.repositoryRoot-cne$root-or$t.metadata.operation-cnotin@('UPGRADE_RUNTIME_REFRESH','UPGRADE_FORMAT_TRANSITION','UPGRADE_SNAPSHOT12_TO_2')){throw 'ADOPTION_TRANSACTION_BINDING'}
        $binding=$t.metadata.previousDistribution;$version=$t.metadata.originalContext.frameworkVersion
        if($version-cne'2.0.0'){return $null}
        $old=@($t.projection.objects|Where-Object path -CEQ ('.ai-workspace/upgrade-recovery/'+$version+'/state.json'))
        if($old.Count-ne1-or-not$old[0].oldExists){throw 'ADOPTION_SCOPE_ORIGINAL_STATE_REQUIRED'}
        $bytes=[Convert]::FromBase64String($old[0].oldBase64)
        if((Get-AiwByteIdentity $bytes)-cne$old[0].oldIdentity){throw 'ADOPTION_SCOPE_ORIGINAL_STATE_DRIFT'}
        $origin=ConvertFrom-AiwAdoptionBytes $bytes
        if(-not(Test-AiwRootJsonSame $origin.distributionBinding $binding)){throw 'ADOPTION_SCOPE_ORIGINAL_DISTRIBUTION_DRIFT'}
    }elseif($Parameters.ContainsKey('AdoptionProcessMode')-and$Parameters['AdoptionProcessMode']-ceq'FINALIZE_OUTPUT'){
        $d=Read-OwnerEvidence $Parameters['CurrentProcessInputPath'] $Parameters['ExpectedCurrentProcessInputIdentity']
        $r=Read-OwnerEvidence $d.Value.discoverReceiptPath $d.Value.expectedDiscoverReceiptIdentity
        $ad=Read-OwnerEvidence $Parameters['AdmitResultPath'] $Parameters['ExpectedAdmitResultIdentity']
        $c=if($r.Value.schemaVersion-eq1){$r.Value.authorityContext}else{$r.Value.binding}
        if($c.projectRoot-cne$root-or$ad.Value.adoptionPreparation.discoverReceiptIdentity-cne$r.Identity){throw 'ADOPTION_SCOPE_ORIGINAL_RECEIPT_DRIFT'}
        $binding=$ad.Value.adoptionPreparation.previousDistribution;$version=$c.frameworkVersion
        if([IO.Path]::GetFullPath($binding.runtimeRoot)-cne[IO.Path]::GetFullPath($r.Value.sourceLocators.frameworkRoot)){throw 'ADOPTION_SCOPE_ORIGINAL_DISTRIBUTION_DRIFT'}
    }else{
        $config=Read-OwnerEvidence (Get-AiwContainedPath $root '.ai-workspace/project.json') $null
        $version=[string]$config.Value.frameworkVersion
        if($version-cne'2.0.0'){return $null}
        $binding=Get-AiwAdoptedDistributionBinding $root $version
        if($null-eq$binding){return $null} # Preserve the existing unnamed/stable path.
        foreach($relative in @('.ai-workspace/upgrade-recovery/2.0.0/state.json','.ai-workspace/runtime/project-adoption/register/state.json','.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
            $originPath=Get-AiwContainedPath $root $relative
            if([IO.File]::Exists($originPath)){$null=Read-OwnerEvidence $originPath $null}
        }
    }
    if($version-cne'2.0.0'){return $null}
    $binding=Assert-AiwDistributionBinding $binding $binding.runtimeRoot $version
    $path=Get-AiwContainedPath $binding.runtimeRoot ('framework/versions/'+$version+'/scripts/ProjectSourcePublication.psm1')
    if(-not[IO.File]::Exists($path)){return $null} # Earlier declared runtimes have no publication scope.
    return [pscustomobject]@{root=$root;version=$version;distribution=$binding;modulePath=$path;moduleIdentity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($path)));reads=$reads.ToArray()}
}
function Invoke-AiwRootAdoptionSourceScope {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[ValidateSet('OBSERVE','WRITE','PUBLICATION')][string]$Mode='OBSERVE',[Parameter(Mandatory)]$EntryContext,[Parameter(Mandatory)][scriptblock]$Body,[object[]]$ArgumentList=@())
 $readContext=Enter-AiwRootReadContext
 try {
    if($Mode-ceq'OBSERVE'){return & $Body @ArgumentList}
 $parameters=$EntryContext.BoundParameters
 $adoption=($parameters.ContainsKey('AdoptionProcessMode')-and$parameters['AdoptionProcessMode']-cin@('PREPARE','ADMIT_ACTION','FINALIZE_OUTPUT'))-or($parameters.ContainsKey('RecoverRuntimeAdoption')-and$parameters['RecoverRuntimeAdoption'])-or($parameters.ContainsKey('Apply')-and$parameters['Apply']-and$parameters.ContainsKey('CurrentProcessInputPath')-and$parameters.ContainsKey('AdmitResultPath'))
 $otherOperation=@('ProjectRuleRecoveryPlanPath','ProjectCorrectionLifecyclePath','OriginalTaskArchiveFinalizePlanPath'|Where-Object{$parameters.ContainsKey($_)-and$parameters[$_]})
 $eligible=$Mode-cne'PUBLICATION'-and$parameters['ToVersion']-ceq'2.0.0'-and$adoption-and$otherOperation.Count-eq0
 if(-not$eligible){return Invoke-AiwRootProjectSourceScope -ProjectRoot $ProjectRoot -Mode $Mode -Body $Body -ArgumentList $ArgumentList}
 $entryPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'upgrade-project.ps1'))
 $entries=@(Get-PSCallStack|Where-Object{[object]::ReferenceEquals($_.InvocationInfo,$EntryContext.Invocation)-and$_.InvocationInfo.MyCommand-is[Management.Automation.ExternalScriptInfo]-and[IO.Path]::GetFullPath($_.InvocationInfo.MyCommand.Path)-ceq$entryPath})
 if($entries.Count-ne1){throw 'ADOPTION_SCOPE_ROOT_ENTRY_REQUIRED'}
 $proof=Invoke-AiwRootProjectSourceScope -ProjectRoot $ProjectRoot -Mode OBSERVE -ArgumentList @($ProjectRoot,$parameters) -Body {param($r,$p) Get-AiwRootAdoptionOwnerProof $r $p}
 if($null-eq$proof){return Invoke-AiwRootProjectSourceScope -ProjectRoot $ProjectRoot -Mode $Mode -Body $Body -ArgumentList $ArgumentList}
 $path=Join-Path $PSScriptRoot '../framework/versions/2.0.0/scripts/ProjectSourcePublication.psm1'
 $module=@(Import-Module $path -PassThru -ErrorAction Stop)[0]
 & $module {
  param($proof,$mode,$body,$arguments)
  Invoke-PubOriginalAdoptionScope -Proof $proof -Mode $mode -Body $body -ArgumentList $arguments
 } $proof $Mode $Body $ArgumentList
 } finally {Exit-AiwRootReadContext $readContext}
}
Export-ModuleMember -Function Invoke-AiwRootAdoptionSourceScope

function Get-AiwByteIdentity {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
    return $Bytes.Length.ToString() + '|' + $hash
}

function Assert-AiwRelativePath {
    param([Parameter(Mandatory)][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains(':') -or
        $RelativePath.Contains('\') -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/')) {
        throw 'RELATIVE_PATH_INVALID'
    }

    $parts = @($RelativePath.Split('/'))
    if ($parts.Count -eq 0 -or @($parts | Where-Object { $_ -ceq '' -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
        throw 'RELATIVE_PATH_INVALID'
    }
}

function Resolve-AiwRepositoryRoot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'REPOSITORY_ROOT_MISSING'
    }

    $cursor = [IO.Path]::GetPathRoot($root)
    foreach ($part in @($root.Substring($cursor.Length) -split '[\\/]' | Where-Object { $_.Length -gt 0 })) {
        $cursor = [IO.Path]::Combine($cursor, $part)
        $attributes = [IO.File]::GetAttributes($cursor)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'REPOSITORY_ROOT_REPARSE'
        }
    }
    return $root
}

# The completion frontdoors must check their explicit read carriers before
# opening an input envelope or project config. The receipt still owns authority;
# this caller-supplied root is only a read boundary and must match that receipt.
function Assert-AiwOriginalCompletionReadPaths {
    param([string]$ProjectRoot,[string[]]$Paths,[string[]]$ForbiddenPaths)
    if([string]::IsNullOrWhiteSpace($ProjectRoot)-or-not[IO.Path]::IsPathRooted($ProjectRoot)){throw 'ORIGINAL_SOURCE_REPOSITORY_REQUIRED'}
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))
    $denied=@(foreach($path in $ForbiddenPaths){
        if([string]::IsNullOrWhiteSpace($path)){throw 'ORIGINAL_SOURCE_PROTECTION_PATH'}
        if([IO.Path]::IsPathRooted($path)){[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($path))}
        else{Assert-AiwRelativePath $path;[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $root $path)))}
    })
    foreach($path in @($root)+@($Paths|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})){
        $full=[IO.Path]::GetFullPath($path,$root)
        foreach($prefix in $denied){
            if($full.Equals($prefix,[StringComparison]::OrdinalIgnoreCase)-or$full.StartsWith($prefix+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ORIGINAL_SOURCE_PROTECTED_PATH'}
        }
        if($full-cne$root){$null=Get-AiwContainedPath $root ([IO.Path]::GetRelativePath($root,$full).Replace('\','/'))}
    }
}

function Test-AiwProjectGitMetadata {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    # Presence only controls the optional ignore projection. This does not
    # authenticate a Git root, run Git, or promote an enclosing repository.
    return Test-Path -LiteralPath (Get-AiwContainedPath $RepositoryRoot '.git')
}

function Get-AiwNavigationContract {
    param([Parameter(Mandatory)]$Toolchain)
    $contract=[string]$Toolchain.contractVersion
    if($contract-cnotin@('1','2','3','4')){throw 'FRAMEWORK_TOOLCHAIN_CONTRACT_UNSUPPORTED'}
    if($contract-ceq'4'){
        $top=@('schemaVersion','frameworkVersion','contractVersion','projectSelectionField','navigation','officialBackends','conformance')
        if(@($Toolchain.PSObject.Properties).Count-ne$top.Count-or@($top|Where-Object{$_-cnotin$Toolchain.PSObject.Properties.Name}).Count){throw 'FRAMEWORK_TOOLCHAIN_FIELDS'}
        $n=$Toolchain.navigation
        $fields=@('schemaVersion','kind','navigationContractVersion','bootstrapLocator','requiredOperations','processCatalogSchemaVersion','processCatalogVersion','nativeRuleBodySource')
        if($n-isnot[pscustomobject]-or@($n.PSObject.Properties).Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$n.PSObject.Properties.Name}).Count){throw 'FRAMEWORK_BOOTSTRAP_NAVIGATION_FIELDS'}
        if(($n.schemaVersion-isnot[int]-and$n.schemaVersion-isnot[long])-or$n.schemaVersion-ne1-or$n.kind-cne'PROJECT_BOOTSTRAP'-or$n.navigationContractVersion-cne'3'-or$n.bootstrapLocator-cne'.ai-workspace/BOOTSTRAP.md'-or($n.processCatalogSchemaVersion-isnot[int]-and$n.processCatalogSchemaVersion-isnot[long])-or$n.processCatalogSchemaVersion-ne3-or$n.processCatalogVersion-cne'4'-or$n.nativeRuleBodySource-cne'MARKDOWN_EXACT_BLOCK'-or$n.requiredOperations-isnot[Array]-or[string]::Join('|',@($n.requiredOperations))-cne'LOAD_PLAN_RESOLVE|PROCESS_REQUIREMENTS_RESOLVE|WORKFLOW_ROUTE_RESOLVE'){throw 'FRAMEWORK_BOOTSTRAP_NAVIGATION_CONTRACT'}
        return [pscustomobject]@{ContractVersion='4';NavigationContractVersion='3';Kind='PROJECT_BOOTSTRAP';BootstrapLocator=$n.bootstrapLocator;SkillName='';CanonicalSkillPath='';DiscoverSchema=5}
    }
    if($null-ne$Toolchain.PSObject.Properties['navigation']){throw 'FRAMEWORK_ROUTER_COMPATIBILITY_FIELDS'}
    $router=$Toolchain.routerCompatibility
    if($router-isnot[pscustomobject]){throw 'FRAMEWORK_ROUTER_COMPATIBILITY'}
    $fields=@('schemaVersion','skillName','status','canonicalSkillPath','versionContractPath','requiredOperations','processCatalogSchemaVersion','processCatalogVersion','nativeRuleBodySource')
    $navigation=if($null-ne$router.PSObject.Properties['navigationContractVersion']){[string]$router.navigationContractVersion}elseif($contract-ceq'1'){'1'}else{throw 'FRAMEWORK_ROUTER_NAVIGATION_CONTRACT'}
    if($null-ne$router.PSObject.Properties['navigationContractVersion']){$fields+=@('navigationContractVersion')}
    $actual=@($router.PSObject.Properties.Name)
    if($actual.Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$actual}).Count-ne0){throw 'FRAMEWORK_ROUTER_COMPATIBILITY_FIELDS'}
    if(($contract-ceq'1'-and$navigation-cne'1')-or($contract-cin@('2','3')-and$navigation-cne'2')){throw 'FRAMEWORK_ROUTER_NAVIGATION_CONTRACT'}
    $skill=switch($navigation){'1'{'ai-workspace-router'};'2'{'ai-workspace-router-v2'};default{throw 'FRAMEWORK_ROUTER_NAVIGATION_CONTRACT'}}
    $catalogSchema=if($contract-ceq'3'){3}else{2};$catalogVersion=if($contract-ceq'3'){'4'}else{'3'}
    if(($router.schemaVersion-isnot[int]-and$router.schemaVersion-isnot[long])-or$router.schemaVersion-ne1-or
        [string]$router.skillName-cne$skill-or[string]$router.status-cne'COMPATIBLE'-or
        [string]$router.canonicalSkillPath-cne('skills/'+$skill+'/SKILL.md')-or
        [string]$router.versionContractPath-cne('host/skills/'+$skill+'/SKILL.md')-or
        ($router.processCatalogSchemaVersion-isnot[int]-and$router.processCatalogSchemaVersion-isnot[long])-or$router.processCatalogSchemaVersion-ne$catalogSchema-or
        [string]$router.processCatalogVersion-cne$catalogVersion-or[string]$router.nativeRuleBodySource-cne'MARKDOWN_EXACT_BLOCK'-or
        $router.requiredOperations-isnot[Array]-or[string]::Join('|',@($router.requiredOperations))-cne'LOAD_PLAN_RESOLVE|PROCESS_REQUIREMENTS_RESOLVE|WORKFLOW_ROUTE_RESOLVE') {throw 'FRAMEWORK_ROUTER_COMPATIBILITY'}
    return [pscustomobject]@{ContractVersion=$contract;NavigationContractVersion=$navigation;Kind='SKILL';BootstrapLocator='';SkillName=$skill;CanonicalSkillPath=[string]$router.canonicalSkillPath;DiscoverSchema=$(switch($contract){'1'{2};'2'{3};'3'{4}})}
}
Export-ModuleMember -Function Test-AiwProjectGitMetadata,Get-AiwNavigationContract

function Get-AiwContainedPath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    Assert-AiwRelativePath $RelativePath
    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $full = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'RELATIVE_PATH_OUTSIDE_ROOT'
    }

    $cursor = $root
    foreach ($part in $RelativePath.Split('/')) {
        $cursor = [IO.Path]::Combine($cursor, $part)
        try { $attributes = [IO.File]::GetAttributes($cursor) }
        catch [IO.FileNotFoundException] { continue }
        catch [IO.DirectoryNotFoundException] { continue }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('PATH_REPARSE|' + $RelativePath)
        }
    }
    return $full
}

function Assert-AiwJsonNoDuplicateMember {
    param(
        [Parameter(Mandatory)][System.Text.Json.JsonElement]$Element,
        [Parameter(Mandatory)][string]$Label,
        [string]$JsonPath = '$'
    )

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) {
                $failure = [Management.Automation.RuntimeException]::new($Label + '_DUPLICATE_MEMBER|' + $JsonPath + '.' + $property.Name)
                $failure.Data['AiwJsonDuplicateMember'] = [string]$property.Name
                throw $failure
            }
            Assert-AiwJsonNoDuplicateMember -Element $property.Value -Label $Label -JsonPath ($JsonPath + '.' + $property.Name)
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($child in $Element.EnumerateArray()) {
            Assert-AiwJsonNoDuplicateMember -Element $child -Label $Label -JsonPath ($JsonPath + '[' + $index + ']')
            $index++
        }
    }
}

function Read-AiwProjectJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ($Label + '_MISSING')
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ($Label + '_REPARSE')
    }

    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    $identity=Get-AiwByteIdentity $bytes
    if($null-ne$script:RootReadContext-and$script:RootReadContext.documents.ContainsKey($item.FullName)){
        $cached=$script:RootReadContext.documents[$item.FullName]
        if($cached.Identity-ceq$identity){
            return [pscustomobject]@{Path=$item.FullName;Bytes=$bytes;Text=$cached.Text;Value=(Copy-AiwRootJsonValue $cached.Value);Identity=$identity}
        }
        $script:RootReadContext.documents.Remove($item.FullName)|Out-Null
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        throw ($Label + '_BOM')
    }
    try {
        $text = $script:Utf8Strict.GetString($bytes)
    }
    catch {
        throw ($Label + '_UTF8')
    }
    if ($text.Contains([char]0) -or $text.Contains([char]0xFFFD)) {
        throw ($Label + '_TEXT_FORMAT')
    }

    try {
        $document = [System.Text.Json.JsonDocument]::Parse($text)
        try {
            Assert-AiwJsonNoDuplicateMember -Element $document.RootElement -Label $Label
        }
        finally {
            $document.Dispose()
        }
        # Preserve index verification timestamps as strings during conversion.
        $jsonArgs=@{Depth=64}
        if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$jsonArgs.DateKind='String'}
        $value = $text | ConvertFrom-Json @jsonArgs
    }
    catch {
        if ($_.Exception.Message.StartsWith($Label + '_DUPLICATE_MEMBER')) {
            throw
        }
        throw ($Label + '_JSON')
    }

    if($null-ne$script:RootReadContext){$script:RootReadContext.documents[$item.FullName]=[pscustomobject]@{Identity=$identity;Text=$text;Value=(Copy-AiwRootJsonValue $value)}}
    [pscustomobject]@{
        Path = $item.FullName
        Bytes = $bytes
        Text = $text
        Value = $value
        Identity = $identity
    }
}

function Get-AiwSchemaVersion {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Value.PSObject.Properties['schemaVersion'] -or
        ($Value.schemaVersion -isnot [int] -and $Value.schemaVersion -isnot [long])) {
        throw ($Label + '_SCHEMA_VERSION')
    }
    return [int]$Value.schemaVersion
}

function Get-AiwProjectFormat {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode OBSERVE
try {


    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $project = Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'PROJECT_CONFIG'
    $controller = Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/controller.json') 'CONTROLLER'
    $projectSchema = Get-AiwSchemaVersion $project.Value 'PROJECT_CONFIG'
    $controllerSchema = Get-AiwSchemaVersion $controller.Value 'CONTROLLER'

    $carriers = [ordered]@{
        project = $projectSchema
        controller = $controllerSchema
    }
    $capabilities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    if ($projectSchema -ge 4 -and
        $project.Value.PSObject.Properties.Name -ccontains 'frameworkToolBackend' -and
        -not [string]::IsNullOrWhiteSpace([string]$project.Value.frameworkToolBackend)) {
        $null = $capabilities.Add('PROJECT_BACKEND_SELECTION')
    }
    $processPolicyLocatorShape = $project.Value.PSObject.Properties.Name -ccontains 'processPolicy' -and
        $null -ne $project.Value.processPolicy -and
        $project.Value.processPolicy.PSObject.Properties.Name -ccontains 'schemaVersion' -and
        $project.Value.processPolicy.PSObject.Properties.Name -ccontains 'locator'
    if ($projectSchema -ge 4 -and
        $processPolicyLocatorShape -and
        $project.Value.processPolicy.schemaVersion -in @(1,2) -and
        -not [string]::IsNullOrWhiteSpace([string]$project.Value.processPolicy.locator)) {
        Assert-AiwRelativePath ([string]$project.Value.processPolicy.locator)
        $null = $capabilities.Add('PROCESS_POLICY_LOCATOR')
    }
    if($projectSchema-eq6-and$null-ne$project.Value.PSObject.Properties['sourceBindings']-and$project.Value.sourceBindings-is[Array]){$null=$capabilities.Add('CONTENT_SOURCE_BINDINGS')}

    $correctionsPath = Get-AiwContainedPath $root '.ai-workspace/corrections.json'
    if (Test-Path -LiteralPath $correctionsPath -PathType Leaf) {
        $corrections = Read-AiwProjectJson $correctionsPath 'CORRECTIONS'
        $correctionsSchema = Get-AiwSchemaVersion $corrections.Value 'CORRECTIONS'
        $carriers.corrections = $correctionsSchema
        if ($correctionsSchema -ge 2 -and
            $corrections.Value.PSObject.Properties.Name -ccontains 'corrections' -and
            $corrections.Value.corrections -is [array]) {
            $null = $capabilities.Add('STRUCTURED_CORRECTIONS')
        }
    }

    $policyPath = Get-AiwContainedPath $root '.ai-workspace/process-policy.json'
    if (Test-Path -LiteralPath $policyPath -PathType Leaf) {
        $policy = Read-AiwProjectJson $policyPath 'PROCESS_POLICY'
        $policySchema = Get-AiwSchemaVersion $policy.Value 'PROCESS_POLICY'
        $carriers.processPolicy = $policySchema
        $hasBudget = $policy.Value.PSObject.Properties.Name -ccontains 'selectedRulePackBytes'
        $hasRules = $policy.Value.PSObject.Properties.Name -ccontains 'rules'
        $budgetIsInteger = $hasBudget -and
            ($policy.Value.selectedRulePackBytes -is [int] -or $policy.Value.selectedRulePackBytes -is [long])
        if ($hasRules -and $policy.Value.rules -is [array] -and ($policySchema-eq2-or$budgetIsInteger)) {
            $null = $capabilities.Add('PROCESS_POLICY')
        }
    }

    $bootstrapPath = Get-AiwContainedPath $root '.ai-workspace/BOOTSTRAP.md'
    if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) {
        $bootstrapText = [IO.File]::ReadAllText($bootstrapPath, $script:Utf8Strict)
        if ($bootstrapText.IndexOf('<!-- PROJECT-CUSTOM:BEGIN -->', [StringComparison]::Ordinal) -ge 0 -and
            $bootstrapText.IndexOf('<!-- PROJECT-CUSTOM:END -->', [StringComparison]::Ordinal) -ge 0) {
            $null = $capabilities.Add('LEGACY_PROJECT_CUSTOM_REGION')
        }
    }
    if (Test-Path -LiteralPath (Get-AiwContainedPath $root 'AGENTS.md') -PathType Leaf) {
        $null = $capabilities.Add('ROOT_AGENTS_ENTRY')
    }

    $capabilityArray = @($capabilities)
    [Array]::Sort($capabilityArray, [StringComparer]::Ordinal)
    [pscustomobject]@{
        schemaVersion = 1
        projectFormat = 'repo-local/project-config-' + $projectSchema
        carriers = [pscustomobject]$carriers
        capabilities = $capabilityArray
        projectIdentity = $project.Identity
        controllerIdentity = $controller.Identity
    }

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}

function Get-AiwProjectedProjectFormat {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Projection
    )
    $aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode OBSERVE
    try{
    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('aiw-project-format-' + [guid]::NewGuid().ToString('N'))
    $known = @(
        '.ai-workspace/project.json',
        '.ai-workspace/controller.json',
        '.ai-workspace/corrections.json',
        '.ai-workspace/process-policy.json',
        '.ai-workspace/BOOTSTRAP.md',
        'AGENTS.md'
    )
    try {
        $null = New-Item -ItemType Directory -Path $fixture
        foreach ($relative in $known) {
            $source = Get-AiwContainedPath $root $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                continue
            }
            $destination = Join-Path $fixture $relative
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            [IO.File]::Copy($source, $destination, $false)
        }
        foreach ($entry in @($Projection.objects)) {
            if ([string]$entry.path -cnotin $known) {
                continue
            }
            $destination = Join-Path $fixture ([string]$entry.path)
            if ([string]$entry.kind -cne 'FILE') {
                throw ('PROJECT_FORMAT_TARGET_KIND|' + [string]$entry.path)
            }
            if (-not [bool]$entry.newExists) {
                if (Test-Path -LiteralPath $destination -PathType Leaf) {
                    [IO.File]::Delete($destination)
                }
                continue
            }
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            [IO.File]::WriteAllBytes($destination, [Convert]::FromBase64String([string]$entry.newBase64))
        }
        return Get-AiwProjectFormat $fixture
    }
    finally {
        if (Test-Path -LiteralPath $fixture -PathType Container) {
            $tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
            if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($fixture))-cne$tempRoot-or[IO.Path]::GetFileName($fixture)-cnotmatch'^aiw-project-format-[a-f0-9]{32}$'){throw 'FORMAT_FIXTURE_CLEANUP_BOUNDARY'}
            [IO.Directory]::Delete($fixture, $true)
        }
    }
    }finally{Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease}
}

function Get-AiwRootToolRevision {
    param(
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][string[]]$DependencyPath
    )

    $root = Resolve-AiwRepositoryRoot $FrameworkRoot
    $relativePaths = @($DependencyPath)
    if ($relativePaths.Count -eq 0) {
        throw 'TOOL_DEPENDENCY_SET_EMPTY'
    }
    $provided=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($relative in $relativePaths){if(-not$provided.Add($relative)){throw ('TOOL_DEPENDENCY_DUPLICATE|'+$relative)}}
    foreach($relative in @($relativePaths)){
        if($relative-cnotmatch'^framework/versions/[^/]+/ADOPTION_PROFILE\.json$'){continue}
        $profile=(Read-AiwProjectJson (Get-AiwContainedPath $root $relative) 'ADOPTION_PROFILE').Value
        if($profile.schemaVersion-ne3){continue}
        $versionRelative=$relative.Substring(0,$relative.LastIndexOf('/'))
        $versionRoot=Get-AiwContainedPath $root $versionRelative
        Import-Module (Join-Path $versionRoot 'scripts/ObjectFormats.psm1')
        $assembly=Get-AiwObjectFormatAssembly (Join-Path $versionRoot $profile.objectFormats.assemblyLocator)
        $declared=@('scripts/ObjectFormats.psm1','scripts/ContentSources.psm1','scripts/StrictJsonInput.psm1','PROJECT_CONFIG_SCHEMA.json','PROCESS_POLICY_SCHEMA.json','PROJECT_CORRECTIONS_SCHEMA.json','KNOWLEDGE_SCHEMA.json',$profile.objectFormats.assemblyLocator)
        if([IO.File]::Exists((Join-Path $versionRoot 'scripts/ProjectSourcePublication.psm1'))){$declared+=@('scripts/ProjectSourcePublication.psm1','scripts/AuthorizationCheck.psm1','scripts/ProcessRequirementBoundary.psm1')}
        foreach($type in $assembly.Value.objectTypes){foreach($segment in $type.adapters){$declared+='object-formats/'+$segment.implementationLocator}}
        foreach($dependency in $declared){$exact=$versionRelative+'/'+$dependency;if($provided.Add($exact)){$relativePaths+=$exact}}
    }
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $records = [Collections.Generic.List[object]]::new()
    foreach ($relative in $relativePaths) {
        Assert-AiwRelativePath $relative
        if (-not $seen.Add($relative)) {
            throw ('TOOL_DEPENDENCY_DUPLICATE|' + $relative)
        }
        $path = Get-AiwContainedPath $root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ('TOOL_DEPENDENCY_MISSING|' + $relative)
        }
        $records.Add([pscustomobject]@{
            path = $relative
            identity = Get-AiwByteIdentity ([IO.File]::ReadAllBytes($path))
        })
    }

    $canonical = (@($records | ForEach-Object { $_.path + '=' + $_.identity }) -join "`n") + "`n"
    $revision = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))
    )
    [pscustomobject]@{
        schemaVersion = 1
        revision = $revision
        dependencies = @($records)
    }
}

function Assert-AiwRootToolRevision {
    param([Parameter(Mandatory)][string]$FrameworkRoot,[Parameter(Mandatory)][string]$ExpectedRevision,[Parameter(Mandatory)][object[]]$ExpectedDependencies)
    if($ExpectedRevision-cnotmatch'^[A-F0-9]{64}$'-or$ExpectedDependencies.Count-eq0){throw 'ROOT_TOOL_REVISION_REQUIRED'}
    foreach($dependency in $ExpectedDependencies){
        if(@($dependency.PSObject.Properties).Count-ne2-or$null-eq$dependency.PSObject.Properties['path']-or$null-eq$dependency.PSObject.Properties['identity']-or
           [string]$dependency.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ROOT_TOOL_DEPENDENCY_FIELDS'}
    }
    $observed=Get-AiwRootToolRevision $FrameworkRoot @($ExpectedDependencies|ForEach-Object{[string]$_.path})
    if($observed.revision-cne$ExpectedRevision-or$observed.dependencies.Count-ne$ExpectedDependencies.Count){throw 'ROOT_TOOL_REVISION_DRIFT'}
    foreach($dependency in $ExpectedDependencies){
        $match=@($observed.dependencies|Where-Object path -ceq $dependency.path)
        if($match.Count-ne1-or$match[0].identity-cne$dependency.identity){throw 'ROOT_TOOL_DEPENDENCY_DRIFT'}
    }
    return $observed
}
Export-ModuleMember -Function Assert-AiwRootToolRevision

function Get-AiwProjectAdoptionToolDependency {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('REGISTER', 'UPGRADE')]
        [string]$Operation,
        [string[]]$AdditionalDependencyPath = @()
    )

    $entry = if ($Operation -ceq 'REGISTER') {
        'scripts/register-project.ps1'
    }
    else {
        'scripts/upgrade-project.ps1'
    }
    $paths = @(
        $entry,
        'scripts/MaintenanceOverlay.psm1',
        'scripts/ProjectAdoptionState.psm1',
        'scripts/ProjectAdoptionProjection.psm1',
        'scripts/ProjectAdoptionTransaction.psm1'
    )
    if($Operation-ceq'UPGRADE'){$paths+=@('scripts/ProjectCorrectionLifecycle.psm1')}
    $paths+=@($AdditionalDependencyPath)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $result = [Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
        Assert-AiwRelativePath ([string]$path)
        if (-not $seen.Add([string]$path)) {
            throw ('TOOL_DEPENDENCY_DUPLICATE|' + [string]$path)
        }
        $result.Add([string]$path)
    }
    $array = @($result)
    [Array]::Sort($array, [StringComparer]::Ordinal)
    return $array
}

function Get-AiwProjectAdoptionRuntimeIdentity {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)]
        [ValidateSet('REGISTER', 'UPGRADE')]
        [string]$Operation,
        [string[]]$AdditionalDependencyPath = @()
    )

    $format = Get-AiwProjectFormat $ProjectRoot
    $root = Resolve-AiwRepositoryRoot $ProjectRoot
    $project = Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'PROJECT_CONFIG'
    if ($null -eq $project.Value.PSObject.Properties['frameworkVersion'] -or
        -not ($project.Value.frameworkVersion -is [string]) -or
        [string]$project.Value.frameworkVersion -cnotmatch '^\d+\.\d+\.\d+$') {
        throw 'PROJECT_FRAMEWORK_PIN'
    }
    $distribution=Get-AiwAdoptedDistributionBinding $ProjectRoot ([string]$project.Value.frameworkVersion)
    if($null-ne$distribution){$null=Assert-AiwDistributionBinding $distribution $FrameworkRoot ([string]$project.Value.frameworkVersion)}
    $dependencies = Get-AiwProjectAdoptionToolDependency $Operation $AdditionalDependencyPath
    $tool = Get-AiwRootToolRevision $FrameworkRoot $dependencies
    return [pscustomobject]@{
        schemaVersion = 1
        frameworkPin = [string]$project.Value.frameworkVersion
        projectFormat = [string]$format.projectFormat
        projectCapabilities = @($format.capabilities)
        rootToolRevision = [string]$tool.revision
        rootToolDependencies = @($tool.dependencies)
        distributionBinding = $distribution
    }
}

Export-ModuleMember -Function Get-AiwByteIdentity, Assert-AiwRelativePath, Resolve-AiwRepositoryRoot, Get-AiwContainedPath, Read-AiwProjectJson, Get-AiwProjectFormat, Get-AiwProjectedProjectFormat, Get-AiwRootToolRevision, Get-AiwProjectAdoptionToolDependency, Get-AiwProjectAdoptionRuntimeIdentity

# Package identity is carried by the existing adoption record, never a latest selector.
function Get-AiwDistributionBinding {
    param([Parameter(Mandatory)][string]$FrameworkRoot,[Parameter(Mandatory)][string]$FrameworkVersion,[switch]$Required)
    $root=Resolve-AiwRepositoryRoot $FrameworkRoot
    $manifestPath=Get-AiwContainedPath $root 'PACKAGE_MANIFEST.json'
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){
        if($Required){throw 'DISTRIBUTION_MANIFEST_REQUIRED'}
        return $null
    }
    if(Test-Path -LiteralPath (Join-Path $root '.git')){throw 'DISTRIBUTION_DEVELOPMENT_ROOT'}
    $doc=Read-AiwProjectJson $manifestPath 'DISTRIBUTION_MANIFEST';$m=$doc.Value
    if($m.schemaVersion-eq1-and$null-eq$m.PSObject.Properties['distributionId']){
        if($Required){throw 'DISTRIBUTION_NAMED_PACKAGE_REQUIRED'}
        return $null
    }
    $fields=@('schemaVersion','frameworkVersion','provisional','canonical','files','distributionId')
    if(@($m.PSObject.Properties).Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$m.PSObject.Properties.Name}).Count-ne0-or
       $m.schemaVersion-ne2-or[string]$m.frameworkVersion-cne$FrameworkVersion-or
       [string]$m.distributionId-cnotmatch('^'+[regex]::Escape($FrameworkVersion)+'-(snapshot\.[1-9][0-9]*|release)$')-or
       $m.provisional-isnot[bool]-or$m.files-isnot[array]-or[string]$m.canonical-cnotmatch'^[A-F0-9]{64}$'){throw 'DISTRIBUTION_MANIFEST_FIELDS'}
    if(([string]$m.distributionId).EndsWith('-release')-and[bool]$m.provisional){throw 'DISTRIBUTION_LIFECYCLE'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$rows=[Collections.Generic.List[string]]::new()
    foreach($entry in $m.files){
        if(@($entry.PSObject.Properties).Count-ne2-or$null-eq$entry.PSObject.Properties['path']-or$null-eq$entry.PSObject.Properties['identity']){throw 'DISTRIBUTION_FILE_FIELDS'}
        $relative=[string]$entry.path;Assert-AiwRelativePath $relative
        if(-not$seen.Add($relative)-or$relative-ceq'PACKAGE_MANIFEST.json'-or$relative.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase)-or$relative.StartsWith('.ai-workspace/',[StringComparison]::OrdinalIgnoreCase)){throw 'DISTRIBUTION_FILE_PATH'}
        $file=Get-AiwContainedPath $root $relative
        if(-not(Test-Path -LiteralPath $file -PathType Leaf)-or(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($file)))-cne[string]$entry.identity){throw ('DISTRIBUTION_CONTENT_DRIFT|'+$relative)}
        $rows.Add($relative+'='+[string]$entry.identity)
    }
    $all=@(Get-ChildItem -LiteralPath $root -Recurse -Force)
    if(@($all|Where-Object{($_.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0}).Count-ne0){throw 'DISTRIBUTION_REPARSE'}
    $actual=@($all|Where-Object{-not$_.PSIsContainer})
    foreach($file in $actual){$relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/');if($relative-cne'PACKAGE_MANIFEST.json'-and-not$seen.Contains($relative)){throw ('DISTRIBUTION_UNLISTED_FILE|'+$relative)}}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(([string]::Join([string][char]10,$rows)+[char]10))))
    if($canonical-cne[string]$m.canonical){throw 'DISTRIBUTION_CANONICAL_DRIFT'}
    return [pscustomobject][ordered]@{distributionId=[string]$m.distributionId;contentIdentity=$canonical;manifestIdentity=[string]$doc.Identity;runtimeRoot=$root}
}

function Assert-AiwDistributionBinding {
    param([Parameter(Mandatory)]$Binding,[Parameter(Mandatory)][string]$FrameworkRoot,[Parameter(Mandatory)][string]$FrameworkVersion)
    $fields=@('distributionId','contentIdentity','manifestIdentity','runtimeRoot')
    if(@($Binding.PSObject.Properties).Count-ne4-or@($fields|Where-Object{$_-cnotin$Binding.PSObject.Properties.Name}).Count-ne0){throw 'DISTRIBUTION_BINDING_FIELDS'}
    if([IO.Path]::GetFullPath($FrameworkRoot)-cne[IO.Path]::GetFullPath([string]$Binding.runtimeRoot)){throw 'DISTRIBUTION_RUNTIME_ROOT_DRIFT'}
    $current=Get-AiwDistributionBinding $FrameworkRoot $FrameworkVersion -Required
    foreach($name in $fields){if([string]$Binding.$name-cne[string]$current.$name){throw ('DISTRIBUTION_BINDING_DRIFT|'+$name)}}
    return $current
}
Export-ModuleMember -Function Get-AiwDistributionBinding,Assert-AiwDistributionBinding
function Assert-AiwMajorRecoveryOrigin {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$Transaction)
    # A later same-version refresh changes the live projection, not the
    # historical major-adoption objects or their original recovery material.
    $records=@($Transaction.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'})
    if($records.Count-ne1-or$records[0].kind-cne'FILE'-or$records[0].newExists-ne$true){throw 'MAJOR_RECOVERY_ORIGIN_STATE'}
    $record=$records[0]
    try {
        $bytes=[Convert]::FromBase64String([string]$record.newBase64)
        if((Get-AiwByteIdentity $bytes)-cne$record.newIdentity){throw 'MAJOR_RECOVERY_ORIGIN_IDENTITY'}
        if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'MAJOR_RECOVERY_ORIGIN_BOM'}
        $text=$script:Utf8Strict.GetString($bytes)
        if($text.Contains([char]0)-or$text.Contains([char]0xFFFD)){throw 'MAJOR_RECOVERY_ORIGIN_TEXT'}
        $document=[System.Text.Json.JsonDocument]::Parse($text)
        try { Assert-AiwJsonNoDuplicateMember $document.RootElement 'MAJOR_RECOVERY_ORIGIN' }
        finally { $document.Dispose() }
        $origin=$text|ConvertFrom-Json -Depth 100
    } catch { throw ('MAJOR_RECOVERY_ORIGIN_INVALID|'+$_.Exception.Message) }
    foreach($field in @('schemaVersion','projectId','fromVersion','toVersion','actor','taskId','taskOwner','taskRelative','authorizationIdentity','objects','majorTransition')){
        if($null-eq$origin.PSObject.Properties[$field]-or$null-eq$State.PSObject.Properties[$field]-or
           -not(Test-AiwRootJsonSame $origin.$field $State.$field)){
            throw ('MAJOR_RECOVERY_ORIGIN_DRIFT|'+$field)
        }
    }
}
Export-ModuleMember -Function Assert-AiwMajorRecoveryOrigin
function Assert-AiwOriginalFormatFinalize {
    param([Parameter(Mandatory)]$Transaction)
    Assert-AiwAdoptionMembers $Transaction @('metadata','projection') 'ADOPTION_ORIGINAL_FINALIZE'
    Assert-AiwAdoptionStringFields $Transaction.metadata @('operation') 'ADOPTION_ORIGINAL_FINALIZE'
    if($Transaction.metadata.operation-cne'UPGRADE_FORMAT_TRANSITION'-or$null-eq$Transaction.metadata.PSObject.Properties['originalFinalize']){throw 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED'}
    $proof=$Transaction.metadata.originalFinalize
    Assert-AiwAdoptionMembers $proof @('schemaVersion') 'ADOPTION_ORIGINAL_FINALIZE'
    Assert-AiwAdoptionStringFields $proof @('inputBase64','resultBase64','discoverBase64','inputIdentity','resultIdentity') 'ADOPTION_ORIGINAL_FINALIZE'
    if(-not(Test-AiwAdoptionInteger $proof.schemaVersion)-or$proof.schemaVersion-ne1){throw 'ADOPTION_ORIGINAL_FINALIZE_INVALID'}
    $inputBytes=[Convert]::FromBase64String($proof.inputBase64);$resultBytes=[Convert]::FromBase64String($proof.resultBase64)
    if((Get-AiwByteIdentity $inputBytes)-cne$proof.inputIdentity-or(Get-AiwByteIdentity $resultBytes)-cne$proof.resultIdentity){throw 'ADOPTION_ORIGINAL_FINALIZE_DRIFT'}
    $input=ConvertFrom-AiwAdoptionBytes $inputBytes
    $result=ConvertFrom-AiwAdoptionBytes $resultBytes
    Assert-AiwAdoptionMembers $input @('schemaVersion','preparationReceipts','resultReceipts') 'ADOPTION_ORIGINAL_FINALIZE_INPUT'
    Assert-AiwAdoptionStringFields $input @('mode','protectionState','expectedDiscoverReceiptIdentity','publicDecisionIdentity') 'ADOPTION_ORIGINAL_FINALIZE_INPUT'
    Assert-AiwAdoptionMembers $result @('authorityGranted','semanticCorrectnessProven','missingPreparation','missingResult') 'ADOPTION_ORIGINAL_FINALIZE_RESULT'
    Assert-AiwAdoptionStringFields $result @('status','mode','originalDiscoverReceiptIdentity','originalAdmitDecisionIdentity') 'ADOPTION_ORIGINAL_FINALIZE_RESULT'
    $discoverBytes=[Convert]::FromBase64String($proof.discoverBase64)
    if((Get-AiwByteIdentity $discoverBytes)-cne$input.expectedDiscoverReceiptIdentity){throw 'ADOPTION_ORIGINAL_FINALIZE_DRIFT'}
    $receipt=ConvertFrom-AiwAdoptionBytes $discoverBytes
    Assert-AiwFixedReceiptShape $receipt
    Assert-AiwAdoptionStringFields $Transaction.metadata @('originalAdmitBase64','originalAdmitIdentity') 'ADOPTION_ORIGINAL_FINALIZE'
    $admitBytes=[Convert]::FromBase64String($Transaction.metadata.originalAdmitBase64)
    if((Get-AiwByteIdentity $admitBytes)-cne$Transaction.metadata.originalAdmitIdentity){throw 'ADOPTION_ORIGINAL_ADMIT_DRIFT'}
    $admit=ConvertFrom-AiwAdoptionBytes $admitBytes;Assert-AiwFixedAdmissionShape $admit
    $a=$admit.originalAdmissionInput;$p=$admit.adoptionPreparation
    if($input.mode-cne'FINALIZE_OUTPUT'-or$input.schemaVersion-notin@(2,3)-or$input.protectionState-cne'BOUND'-or
       $result.status-cne'PASS'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.authorityGranted-ne$false-or$result.semanticCorrectnessProven-ne$false-or
       $result.originalDiscoverReceiptIdentity-cne$input.expectedDiscoverReceiptIdentity-or$result.originalAdmitDecisionIdentity-cne$admit.decisionIdentity-or
       $a.expectedDiscoverReceiptIdentity-cne$input.expectedDiscoverReceiptIdentity-or$a.publicDecisionIdentity-cne$input.publicDecisionIdentity-or
       $admit.status-cne'PASS'-or$admit.mode-cne'ADMIT_ACTION'-or@($result.missingPreparation).Count-or@($result.missingResult).Count){throw 'ADOPTION_ORIGINAL_FINALIZE_INVALID'}
    $context=if($receipt.schemaVersion-eq1){$receipt.authorityContext}else{$receipt.binding}
    $material=@($receipt.sourceCompositionIdentity,$receipt.selectionIdentity,$receipt.contextIdentity,'ADMIT_ACTION',$receipt.intentEnvelope.objective,'CONTROL_WRITE',$receipt.intentEnvelope.requestedResultKind,[string]::Join(',',@($context.exactScope)),$context.authorizationIdentity,[string]::Join(',',@($a.preparationReceipts)),[string]::Join(',',@($a.resultReceipts)),[string]::Join(',',@($a.deliveryReceipts)),$a.publicDecisionIdentity,$a.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join"`n"
    if($null-ne$a.PSObject.Properties['deliveryContext']){$material+=($a.deliveryContext|ConvertTo-Json -Compress)}
    if($null-ne$a.PSObject.Properties['evidenceRefs']){$material+=($a.evidenceRefs|ConvertTo-Json -Depth 30 -Compress)}
    if((Get-AiwByteIdentity $script:Utf8Strict.GetBytes($material)).Split('|')[1]-cne$admit.decisionIdentity){throw 'ADOPTION_ORIGINAL_ADMIT_DECISION'}
    if(-not(Test-AiwRootJsonSame $p.projection $Transaction.projection)){throw 'ADOPTION_ORIGINAL_FINALIZE_PROJECTION'}
    $required=@(@($receipt.selectedObligations)+@($p.selectedRuleBlocks))
    foreach($obligation in $required){
        foreach($name in $obligation.preparationRequirements){if($name-cnotin@($a.preparationReceipts)-or$name-cnotin@($input.preparationReceipts)){throw 'ADOPTION_ORIGINAL_FINALIZE_PREPARATION'}}
        foreach($name in $obligation.resultRequirements){if($name-cne'DELIVERY_RECEIPT'-and$name-cnotin@($input.resultReceipts)){throw 'ADOPTION_ORIGINAL_FINALIZE_RESULT'}}
    }
    foreach($entry in $Transaction.projection.objects){if(('OBJECT_POSTIMAGE|'+$entry.path+'|'+$(if($entry.newExists){$entry.newIdentity}else{'ABSENT'}))-cnotin@($input.resultReceipts)){throw 'ADOPTION_ORIGINAL_FINALIZE_POSTIMAGE'}}
}
Export-ModuleMember -Function Assert-AiwOriginalFormatFinalize
function Get-AiwAdoptedDistributionBinding {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$FrameworkVersion)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $ProjectRoot -Mode OBSERVE
try {

    $root=Resolve-AiwRepositoryRoot $ProjectRoot
    foreach($relative in @('.ai-workspace/runtime/project-adoption/register/state.json','.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
        $pendingPath=Get-AiwContainedPath $root $relative
        if(Test-Path -LiteralPath $pendingPath -PathType Leaf){
            $pending=(Read-AiwProjectJson $pendingPath 'ADOPTION_TRANSACTION').Value
            Assert-AiwAdoptionCompletion $pending
            if($null-ne$pending.PSObject.Properties['metadata']){Assert-AiwAdoptionMembers $pending.metadata @() 'ADOPTION_TRANSACTION_METADATA'}
        }
    }
    $upgrade=Get-AiwContainedPath $root ('.ai-workspace/upgrade-recovery/'+$FrameworkVersion+'/state.json')
    if(Test-Path -LiteralPath $upgrade -PathType Leaf){
        $state=(Read-AiwProjectJson $upgrade 'ADOPTION_STATE').Value
        Assert-AiwAdoptionMembers $state @('schemaVersion') 'ADOPTION_STATE'
        if($state.schemaVersion-eq7){return (Assert-AiwRegistrationOrigin $root $FrameworkVersion).State.distributionBinding}
        if($null-ne$state.PSObject.Properties['distributionBinding']){
            Assert-AiwAdoptionMembers $state @('transactionComplete') 'ADOPTION_STATE'
            if($state.transactionComplete-isnot[bool]-or-not$state.transactionComplete){throw 'ADOPTION_RECOVERY_REQUIRED'}
            return $state.distributionBinding
        }
    }
    $registration=Get-AiwContainedPath $root '.ai-workspace/runtime/project-adoption/register/state.json'
    if(Test-Path -LiteralPath $registration -PathType Leaf){
        $state=(Read-AiwProjectJson $registration 'REGISTRATION_STATE').Value
        Assert-AiwAdoptionMembers $state @() 'REGISTRATION_STATE'
        if($null-ne$state.PSObject.Properties['metadata']){Assert-AiwAdoptionMembers $state.metadata @() 'REGISTRATION_TRANSACTION_METADATA'}
        if($null-ne$state.PSObject.Properties['metadata']-and$null-ne$state.metadata.PSObject.Properties['distributionBinding']-and$null-ne$state.metadata.distributionBinding){
            if($state.transactionComplete-isnot[bool]-or-not$state.transactionComplete-or[string]$state.state-cne'COMPLETE'){throw 'ADOPTION_RECOVERY_REQUIRED'}
            return $state.metadata.distributionBinding
        }
    }
    return $null

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
Export-ModuleMember -Function Get-AiwAdoptedDistributionBinding

function Read-AiwSavedAdoptionDocument($Metadata,[string]$Name){
    Assert-AiwAdoptionStringFields $Metadata @("original${Name}Identity","original${Name}Base64") 'FIXED_ADOPTION_ORIGINAL'
    $identity=[string]$Metadata.('original'+$Name+'Identity')
    $bytes=[Convert]::FromBase64String([string]$Metadata.('original'+$Name+'Base64'))
    if($identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-AiwByteIdentity $bytes)-cne$identity){throw 'FIXED_ADOPTION_ORIGINAL_DRIFT'}
    return [pscustomobject]@{Bytes=$bytes;Identity=$identity;Value=(ConvertFrom-AiwAdoptionBytes $bytes)}
}
function ConvertFrom-AiwAdoptionBytes([byte[]]$Bytes){
    $key='bytes|'+(Get-AiwByteIdentity $Bytes)
    if($null-ne$script:RootReadContext-and$script:RootReadContext.documents.ContainsKey($key)){
        return Copy-AiwRootJsonValue $script:RootReadContext.documents[$key].Value
    }
    $text=$script:Utf8Strict.GetString($Bytes)
    if($text.Contains([char]0)-or$text.Contains([char]0xFFFD)-or($text.Length-and$text[0]-eq[char]0xFEFF)){throw 'FIXED_ADOPTION_ORIGINAL_FORMAT'}
    $json=[Text.Json.JsonDocument]::Parse($text)
    try{Assert-AiwJsonNoDuplicateMember $json.RootElement 'FIXED_ADOPTION_ORIGINAL'}finally{$json.Dispose()}
    $value=$text|ConvertFrom-Json -Depth 100
    Assert-AiwAdoptionMembers $value @() 'FIXED_ADOPTION_ORIGINAL'
    if($null-ne$script:RootReadContext){$script:RootReadContext.documents[$key]=[pscustomobject]@{Value=(Copy-AiwRootJsonValue $value)}}
    return $value
}
function Get-AiwFixedAdoptionAdmission($Transaction,[string]$Root,[switch]$ProcessObservation){
    Assert-AiwAdoptionMembers $Transaction @('metadata','projection') 'FIXED_ADOPTION_TRANSACTION'
    $m=$Transaction.metadata
    Assert-AiwAdoptionStringFields $m @('operation') 'FIXED_ADOPTION_METADATA'
    if($m.operation-cnotin@('UPGRADE_RUNTIME_REFRESH','UPGRADE_FORMAT_TRANSITION','UPGRADE_SNAPSHOT12_TO_2')){return $null}
    foreach($name in @('originalAdmitIdentity','originalAdmitBase64','originalContext','previousDistribution')){
        if($null-eq$m.PSObject.Properties[$name]){return $null}
    }
    Assert-AiwAdoptionStringFields $m @('taskPath','taskIdentity','projectConfigIdentity','controllerIdentity','actor') 'FIXED_ADOPTION_METADATA'
    Assert-AiwAdoptionMembers $m.originalContext @() 'FIXED_ADOPTION_CONTEXT'
    Assert-AiwFixedBindingShape $m.previousDistribution
    Assert-AiwFixedBindingShape $m.distributionBinding
    $admissionModule=@(Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1') -PassThru -ErrorAction Stop)[0]
    $admit=Read-AiwSavedAdoptionDocument $m 'Admit'
    # Some completed legacy origins did not retain the original input. Absence
    # is not a credential; a supplied but malformed input is an invalid one.
    if($null-eq$admit.Value.PSObject.Properties['originalAdmissionInput']){return $null}
    Assert-AiwFixedAdmissionShape $admit.Value
    if($m.operation-ceq'UPGRADE_RUNTIME_REFRESH'){
        if($null-eq$m.PSObject.Properties['originalDiscoverBase64']-or$null-eq$m.PSObject.Properties['originalDiscoverIdentity']){return $null}
        Assert-AiwAdoptionMembers $admit.Value @('hostInvocationProven') 'FIXED_ADOPTION_ADMIT'
        if($admit.Value.hostInvocationProven-isnot[bool]){throw 'FIXED_ADOPTION_ADMIT_BOOLEAN'}
        Assert-AiwAdoptionStringFields $m @('admitResultIdentity') 'FIXED_ADOPTION_METADATA'
        $discover=Read-AiwSavedAdoptionDocument $m 'Discover'
        Assert-AiwFixedReceiptShape $discover.Value
        if($m.admitResultIdentity-cne$admit.Identity){throw 'FIXED_ADOPTION_ORIGINAL_DRIFT'}
        # A cold daily reader has no upgrader script providing the projection
        # exports. Load the real adapter in the admission module's own scope.
        $proof=& $admissionModule {
            param($saved,$project,$transaction,$originalDiscover,$daily)
            Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionProjection.psm1') -Scope Local -ErrorAction Stop
            Get-AiwSamePinAdoptionAdmissionCore $saved $project $transaction.projection $transaction.metadata.distributionBinding $transaction.metadata.actor -Recovery -OriginalDiscoverDocument $originalDiscover -CompletedSourceObservation:$daily
        } $admit $Root $Transaction $discover ([bool]$ProcessObservation)
    }elseif($m.operation-cin@('UPGRADE_FORMAT_TRANSITION','UPGRADE_SNAPSHOT12_TO_2')){
        # Old completed origins without retained admission are supported by the
        # full qualification/recovery path, never by a fabricated fast result.
        $a=$admit.Value.originalAdmissionInput
        if(-not[IO.File]::Exists($a.discoverReceiptPath)){return $null}
        $discover=Read-AiwProjectJson $a.discoverReceiptPath 'FIXED_ADOPTION_DISCOVER'
        if($discover.Identity-cne$a.expectedDiscoverReceiptIdentity){throw 'FIXED_ADOPTION_ORIGINAL_DRIFT'}
        Assert-AiwFixedReceiptShape $discover.Value
        $proof=& $admissionModule {
            param($saved,$project)
            Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionProjection.psm1') -Scope Local -ErrorAction Stop
            Get-AiwMajorAdoptionAdmission $saved $project
        } $admit $Root
        if($m.operation-ceq'UPGRADE_FORMAT_TRANSITION'){
            if($null-eq$m.PSObject.Properties['originalFinalize']){return $null}
            Assert-AiwOriginalFormatFinalize $Transaction
        }
    }else{return $null}
    Assert-AiwAdoptionSame $proof.context $m.originalContext 'FIXED_ORIGINAL_CONTEXT'
    Assert-AiwAdoptionSame $proof.preparation.projection $Transaction.projection 'FIXED_ORIGINAL_PROJECTION'
    Assert-AiwAdoptionSame $proof.preparation.previousDistribution $m.previousDistribution 'FIXED_PREVIOUS_DISTRIBUTION'
    Assert-AiwAdoptionSame $proof.preparation.targetDistribution $m.distributionBinding 'FIXED_TARGET_DISTRIBUTION'
    if($m.taskPath-cne$proof.receipt.sourceLocators.taskRelativePath-or$m.taskIdentity-cne$proof.context.taskIdentity-or$m.projectConfigIdentity-cne$proof.receipt.sourceBindings.projectConfigIdentity-or$m.controllerIdentity-cne$proof.receipt.sourceBindings.controllerIdentity-or$m.actor-cne$proof.context.actor){throw 'FIXED_ADOPTION_ORIGINAL_CONTEXT_DRIFT'}
    return $proof
}
function Assert-AiwStableRegistrationTools($Transaction,$Config,[string]$Runtime,$PackageObservation=$null){
    $version='framework/versions/2.0.0/';$additional=[Collections.Generic.List[string]]::new();$additional.Add($version+'ADOPTION_PROFILE.json')
    $initial=if($null-ne$Transaction.metadata.PSObject.Properties['initialTask']){$Transaction.metadata.initialTask}else{$null}
    if($null-ne$initial){Assert-AiwAdoptionStringFields $initial @('relativePath','identity') 'REGISTRATION_INITIAL_TASK'}
    Assert-AiwAdoptionStringFields $Config @('controlPlaneLayout') 'FIXED_REGISTRATION_PROJECT'
    foreach($entry in $Transaction.projection.objects){
        if($entry.kind-cne'FILE'-or-not$entry.path.StartsWith('.ai-workspace/',[StringComparison]::Ordinal)-or($null-ne$initial-and$entry.path-ceq$initial.relativePath)){continue}
        $suffix=$entry.path.Substring('.ai-workspace/'.Length)
        $relative=if($Config.controlPlaneLayout-ceq'framework-maintenance-sibling'-and$suffix-cin@('BOOTSTRAP.md','process-policy.json')){'framework/maintenance-overlay/'+$suffix}else{$version+'project-starter/'+$suffix}
        if($null-ne$PackageObservation){
            if(-not$PackageObservation.DeclaredMembers.ContainsKey($relative)){return $false}
        }elseif(-not[IO.File]::Exists((Get-AiwContainedPath $Runtime $relative))){return $false}
        if(-not$additional.Contains($relative)){$additional.Add($relative)}
    }
    if($null-ne$initial){$additional.Add($version+'scripts/check-task-card.ps1');$additional.Add($version+'scripts/ResultEvidence.psm1')}
    $dependencies=Get-AiwProjectAdoptionToolDependency REGISTER @($additional.ToArray())
    if($null-ne$PackageObservation){
        $declarations=Get-AiwAdoptedToolDependencyDeclarations $PackageObservation $dependencies
        Assert-AiwAdoptedToolDeclarations $PackageObservation $Transaction.metadata.rootToolRevision $declarations
        return $true
    }
    $tools=Get-AiwRootToolRevision $Runtime $dependencies
    if($tools.revision-cne$Transaction.metadata.rootToolRevision){throw 'FIXED_REGISTRATION_TOOLS_DRIFT'}
    return $true
}
function Get-AiwFixedAdoptedRelease {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$FrameworkRoot,[string]$FrameworkVersion='2.0.0')
    return Get-AiwFixedAdoptionSourceCore @PSBoundParameters
}
function Get-AiwFixedAdoptedProcessSource {
    [CmdletBinding()]param([string]$ProjectRoot,[string]$FrameworkRoot,[string]$FrameworkVersion='2.0.0',[string[]]$ConsumedPaths=@())
    try{return Get-AiwFixedAdoptionSourceCore @PSBoundParameters -ProcessObservation}
    catch{if($_.Exception.Message-ceq'FIXED_ADOPTION_OBSERVATION_UNSUPPORTED'){return $null};throw}
}
function Get-AiwAdoptedReleaseReader([string]$Runtime,[string]$Version='2.0.0') {
    if(Test-AiwProjectGitMetadata $Runtime){throw 'RELEASE_FIXED_DEVELOPMENT_ROOT'}
    $path=Get-AiwContainedPath $Runtime ('framework/versions/'+$Version+'/scripts/ReleaseValidation.psm1')
    $modules=@(Import-Module $path -PassThru -ErrorAction Stop)
    if($modules.Count-ne1-or[IO.Path]::GetFullPath($modules[0].Path)-cne[IO.Path]::GetFullPath($path)){throw 'ADOPTED_READER_MODULE_BINDING'}
    return $modules[0]
}
function Test-AiwAdoptedReaderCommand($Reader,[string]$Name) {
    $command=& $Reader {param($n) Get-Command $n -ErrorAction SilentlyContinue} $Name
    return $null-ne$command-and$null-ne$command.Module-and[IO.Path]::GetFullPath($command.Module.Path)-ceq[IO.Path]::GetFullPath($Reader.Path)
}
function Assert-AiwAdoptedRuntimeDeclaration {
    param([string]$ProjectRoot,[string]$FrameworkRoot,[string]$FrameworkVersion='2.0.0',[string[]]$ConsumedPaths=@())
    $binding=Get-AiwAdoptedDistributionBinding $ProjectRoot $FrameworkVersion
    if($null-eq$binding){return $null}
    if($FrameworkVersion-cne'2.0.0'){$null=Assert-AiwDistributionBinding $binding $FrameworkRoot $FrameworkVersion;return $null}
    Assert-AiwFixedBindingShape $binding
    $reader=Get-AiwAdoptedReleaseReader $FrameworkRoot $FrameworkVersion
    if(-not(Test-AiwAdoptedReaderCommand $reader 'Get-AiwReleasePackageObservation')){
        # Older origins keep their own complete reader and original contract.
        $null=& $reader {param($root,$expected) Get-AiwFixedReleaseProjection (Join-Path $root 'framework/versions/2.0.0') $root $expected} $FrameworkRoot $binding
        return $null
    }
    return & $reader {param($root,$expected,$paths) Get-AiwReleasePackageObservation $root $expected $paths} $FrameworkRoot $binding $ConsumedPaths
}

# Validate the historical relationship to the adopted manifest's declarations.
# This does not observe or certify unused historical tool bytes today.
function Assert-AiwAdoptedToolDeclarations($Observation,[string]$Revision,[object[]]$Dependencies){
 if($Revision-cnotmatch'^[A-F0-9]{64}$'-or$Dependencies.Count-eq0){throw 'ROOT_TOOL_REVISION_REQUIRED'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$rows=[Collections.Generic.List[string]]::new()
 foreach($dependency in $Dependencies){
  Assert-AiwAdoptionFields $dependency @('path','identity') 'TOOL_DEPENDENCY'
  Assert-AiwRelativePath $dependency.path
  if(-not$seen.Add($dependency.path)-or$dependency.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not$Observation.DeclaredMembers.ContainsKey($dependency.path)-or$Observation.DeclaredMembers[$dependency.path]-cne$dependency.identity){throw 'ROOT_TOOL_DECLARATION_DRIFT'}
  $rows.Add($dependency.path)
 }
 [string[]]$sorted=$rows.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal)
 $canonical=@($sorted|ForEach-Object{$_+'='+$Observation.DeclaredMembers[$_]})-join[char]10
 $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical+[char]10)))
 if($actual-cne$Revision){throw 'ROOT_TOOL_DECLARATION_REVISION_DRIFT'}
}
function Get-AiwAdoptedToolDependencyDeclarations($Observation,[string[]]$Paths){
 $reader=Get-AiwAdoptedReleaseReader $Observation.RuntimeRoot
 $all=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($path in $Paths){Assert-AiwRelativePath $path;if(-not$all.Add($path)){throw 'TOOL_DEPENDENCY_DUPLICATE'}}
 foreach($relative in @($Paths)){
  if($relative-cnotmatch'^framework/versions/[^/]+/ADOPTION_PROFILE\.json$'){continue}
  $profile=& $reader {param($o,$p) Read-AiwObservedPackageJson $o $p} $Observation $relative
  if($profile.schemaVersion-ne3){continue}
  $version=$relative.Substring(0,$relative.LastIndexOf('/'))
  $assembly=& $reader {param($o,$p) Read-AiwObservedPackageJson $o $p} $Observation ($version+'/'+$profile.objectFormats.assemblyLocator)
  $declared=@('scripts/ObjectFormats.psm1','scripts/ContentSources.psm1','scripts/StrictJsonInput.psm1','PROJECT_CONFIG_SCHEMA.json','PROCESS_POLICY_SCHEMA.json','PROJECT_CORRECTIONS_SCHEMA.json','KNOWLEDGE_SCHEMA.json',$profile.objectFormats.assemblyLocator)
  if($Observation.DeclaredMembers.ContainsKey($version+'/scripts/ProjectSourcePublication.psm1')){$declared+=@('scripts/ProjectSourcePublication.psm1','scripts/AuthorizationCheck.psm1','scripts/ProcessRequirementBoundary.psm1')}
  foreach($type in $assembly.objectTypes){foreach($adapter in $type.adapters){$declared+=('object-formats/'+$adapter.implementationLocator)}}
  foreach($path in $declared){$null=$all.Add($version+'/'+$path)}
 }
 [string[]]$paths=$all|ForEach-Object{[string]$_};[Array]::Sort($paths,[StringComparer]::Ordinal)
 return @(foreach($path in $paths){if(-not$Observation.DeclaredMembers.ContainsKey($path)){throw 'ROOT_TOOL_DECLARATION_MISSING'};[pscustomobject]@{path=$path;identity=$Observation.DeclaredMembers[$path]}})
}

function Get-AiwFixedAdoptionSourceCore {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$FrameworkRoot,[string]$FrameworkVersion='2.0.0',[switch]$ProcessObservation,[string[]]$ConsumedPaths=@())
    if($FrameworkVersion-cne'2.0.0'){return $null}
    $root=Resolve-AiwRepositoryRoot $ProjectRoot;$runtime=Resolve-AiwRepositoryRoot $FrameworkRoot
    # Initial registration has no adoption to consume. Do not open its source
    # synchronization scope: that would create control directories during PREPARE.
    if(-not[IO.Directory]::Exists((Get-AiwContainedPath $root '.ai-workspace'))){return $null}
    # A prospective stage has no completed adoption of its own, including the
    # private InitialRegistration projection whose completed flag is planned.
    if($null-ne$script:RegistrationProjectionContext-and($script:RegistrationProjectionContext.ProjectRoot-ceq$root-or$script:RegistrationProjectionContext.SourceRoot-ceq$root)){return $null}
    $lease=Enter-AiwRootProjectSourceScope -ProjectRoot $root -Mode OBSERVE
    try{
        Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1') -ErrorAction Stop
        $configPath=Get-AiwContainedPath $root '.ai-workspace/project.json'
        if(-not[IO.File]::Exists($configPath)){return $null}
        $configDocument=Read-AiwProjectJson $configPath 'FIXED_ADOPTION_PROJECT'
        $config=$configDocument.Value
        Assert-AiwAdoptionStringFields $config @('frameworkVersion') 'FIXED_ADOPTION_PROJECT'
        if($config.frameworkVersion-cne$FrameworkVersion){return $null}
        Assert-AiwAdoptionStringFields $config @('id','controlPlaneLayout') 'FIXED_ADOPTION_PROJECT'
        $journals=@{}
        foreach($kind in @('register','upgrade','refresh')){
            $relative='.ai-workspace/runtime/project-adoption/'+$kind+'/state.json';$path=Get-AiwContainedPath $root $relative
            if([IO.File]::Exists($path)){
                $doc=Read-AiwProjectJson $path 'FIXED_ADOPTION_TRANSACTION';$t=$doc.Value
                Assert-AiwAdoptionCompletion $t
                $supported=Test-AiwFixedJournal $t $root $relative
                # A completed rollback is not an adopted source. The restored
                # current origin/postimage below must prove the source instead.
                if($t.state-ceq'ROLLED_BACK'){continue}
                if($supported){$null=Assert-AiwRegistrationJournal $doc $root $relative $t.metadata.operation}
                $journals[$kind]=@{relative=$relative;document=$doc;supported=$supported}
            }
        }
        $stateRelative='.ai-workspace/upgrade-recovery/'+$FrameworkVersion+'/state.json';$statePath=Get-AiwContainedPath $root $stateRelative
        $state=$null;$stateDoc=$null;$binding=$null;$latest=$null;$majorAdmission=$null;$majorAdmissionIdentity=$null
        if([IO.File]::Exists($statePath)){
            $stateDoc=Read-AiwProjectJson $statePath 'FIXED_ADOPTION_STATE';$state=$stateDoc.Value
            Assert-AiwAdoptionMembers $state @('transactionComplete') 'FIXED_ADOPTION_STATE'
            if($state.transactionComplete-isnot[bool]-or-not$state.transactionComplete){throw 'ADOPTION_RECOVERY_REQUIRED'}
            if($null-eq$state.PSObject.Properties['schemaVersion']){return $null}
            if(-not(Test-AiwAdoptionInteger $state.schemaVersion)){throw 'FIXED_ADOPTION_STATE_SCHEMA'}
            if($state.schemaVersion-notin@(6,7)){return $null}
            Assert-AiwAdoptionStringFields $state @('projectId','toVersion','targetReleaseCanonical','targetReleaseManifestIdentity','rootToolRevision') 'FIXED_ADOPTION_STATE'
            Assert-AiwAdoptionMembers $state @('distributionBinding','rootToolDependencies') 'FIXED_ADOPTION_STATE'
            if($state.rootToolDependencies-isnot[array]){throw 'FIXED_ADOPTION_STATE_TOOLS'}
            if($state.projectId-cne$config.id-or$state.toVersion-cne$FrameworkVersion){throw 'FIXED_ADOPTION_PROJECT_DRIFT'}
            $binding=$state.distributionBinding
            if($state.schemaVersion-eq7){
                $origin=Assert-AiwRegistrationOrigin $root $FrameworkVersion
                $kind=if($origin.State.currentTransactionRelativePath-ceq'.ai-workspace/runtime/project-adoption/register/state.json'){'register'}else{'refresh'}
                if(-not$journals.ContainsKey($kind)){throw 'FIXED_ADOPTION_CURRENT_TRANSACTION_MISSING'}
                $latest=$journals[$kind]
            }else{
                $matches=@(foreach($kind in @('upgrade','refresh')){
                    if($journals.ContainsKey($kind)){
                        $candidate=$journals[$kind]
                        # The current state demands an actual supported origin;
                        # a weak locator cannot stand in for this projection.
                        $ct=$candidate.document.Value
                        Assert-AiwAdoptionMembers $ct @('metadata') 'REGISTRATION_TRANSACTION'
                        Assert-AiwAdoptionStringFields $ct.metadata @('operation') 'REGISTRATION_TRANSACTION_METADATA'
                        if($ct.metadata.operation-cnotin@('UPGRADE_RUNTIME_REFRESH','UPGRADE_FORMAT_TRANSITION','UPGRADE_SNAPSHOT12_TO_2')){throw 'FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT'}
                        $null=Assert-AiwRegistrationJournal $candidate.document $root $candidate.relative $ct.metadata.operation
                        $entries=@($ct.projection.objects|Where-Object{$_.path-ceq$stateRelative-and$_.newIdentity-ceq$stateDoc.Identity})
                        if($entries.Count-eq1){$candidate}
                    }
                })
                if($matches.Count-ne1){throw 'FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT'}
                $latest=$matches[0]
                if($null-ne$state.PSObject.Properties['majorTransition']){
                    Assert-AiwAdoptionStringFields $state.majorTransition @('fromVersion','fromDistributionId','toVersion','transactionRelativePath') 'FIXED_ADOPTION_MAJOR_ORIGIN'
                    $major=@($journals.Values|Where-Object{$_.relative-ceq$state.majorTransition.transactionRelativePath})
                    if($major.Count-ne1){throw 'FIXED_ADOPTION_ORIGIN_MISSING'}
                    $majorTxn=$major[0].document.Value
                    Assert-AiwAdoptionMembers $majorTxn @('metadata') 'REGISTRATION_TRANSACTION'
                    Assert-AiwAdoptionStringFields $majorTxn.metadata @('operation') 'REGISTRATION_TRANSACTION_METADATA'
                    if($majorTxn.metadata.operation-cnotin@('UPGRADE_FORMAT_TRANSITION','UPGRADE_SNAPSHOT12_TO_2')){throw 'FIXED_ADOPTION_ORIGIN_OPERATION'}
                    $null=Assert-AiwRegistrationJournal $major[0].document $root $major[0].relative $majorTxn.metadata.operation
                    Assert-AiwMajorRecoveryOrigin $state $majorTxn
                    $majorAdmission=Get-AiwFixedAdoptionAdmission $majorTxn $root -ProcessObservation:$ProcessObservation
                    if($null-eq$majorAdmission){return $null}
                    $majorAdmissionIdentity=$major[0].document.Identity
                }
            }
        }else{
            if(-not$journals.ContainsKey('register')){return $null}
            $latest=$journals['register'];if(-not$latest.supported){return $null}
            Assert-AiwAdoptionMembers $latest.document.Value.metadata @('distributionBinding') 'FIXED_ADOPTION_METADATA'
            $binding=$latest.document.Value.metadata.distributionBinding
            # Unnamed stable registration has no fixed distribution credential.
            if($null-eq$binding){return $null}
        }
        Assert-AiwFixedBindingShape $binding
        if([IO.Path]::GetFullPath($binding.runtimeRoot)-cne$runtime){return $null}
        $txn=$latest.document.Value
        Assert-AiwAdoptionMembers $txn @('metadata') 'REGISTRATION_TRANSACTION'
        Assert-AiwAdoptionStringFields $txn.metadata @('operation') 'REGISTRATION_TRANSACTION_METADATA'
        $operation=$txn.metadata.operation
        $null=Assert-AiwRegistrationJournal $latest.document $root $latest.relative $operation
        Assert-AiwAdoptionMembers $txn.metadata @('distributionBinding') 'FIXED_ADOPTION_METADATA'
        Assert-AiwFixedBindingShape $txn.metadata.distributionBinding
        if($operation-ceq'REGISTER'){
            Assert-AiwAdoptionStringFields $txn.metadata @('frameworkPin','rootToolRevision') 'FIXED_REGISTRATION_METADATA'
            if($txn.metadata.frameworkPin-cne$FrameworkVersion-or$latest.relative-cne'.ai-workspace/runtime/project-adoption/register/state.json'){throw 'FIXED_REGISTRATION_METADATA_DRIFT'}
            $project=@($txn.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'-and$_.kind-ceq'FILE'-and$_.newExists})
            if($project.Count-ne1){throw 'FIXED_REGISTRATION_PROJECT_MISSING'}
            $original=ConvertFrom-AiwAdoptionBytes ([Convert]::FromBase64String($project[0].newBase64))
            Assert-AiwAdoptionStringFields $original @('id','frameworkVersion','controlPlaneLayout') 'FIXED_REGISTRATION_PROJECT'
            if($original.id-cne$config.id-or$original.frameworkVersion-cne$FrameworkVersion-or$original.controlPlaneLayout-cne$config.controlPlaneLayout-or$txn.metadata.rootToolRevision-cnotmatch'^[A-F0-9]{64}$'){throw 'FIXED_REGISTRATION_METADATA_DRIFT'}
            foreach($path in @('.ai-workspace/project.json','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md')){
                if(@($txn.projection.objects|Where-Object{$_.path-ceq$path-and$_.kind-ceq'FILE'-and$_.newExists}).Count-ne1){throw 'FIXED_REGISTRATION_PROJECTION_MISSING'}
            }
            if($null-eq$state-and-not$ProcessObservation-and-not(Assert-AiwStableRegistrationTools $txn $original $runtime)){return $null}
        }elseif($operation-cin@('UPGRADE_RUNTIME_REFRESH','UPGRADE_FORMAT_TRANSITION','UPGRADE_SNAPSHOT12_TO_2')){
            # This exact major transaction was already validated above in this
            # call. Reobserve its finite external inputs instead of rebuilding
            # the same immutable proof. A distinct refresh, or correction
            # replay with an opaque live closure, keeps its original check.
            $reuseMajor=$null-ne$majorAdmission-and$majorAdmissionIdentity-ceq$latest.document.Identity-and
                ($null-eq$majorAdmission.preparation.PSObject.Properties['correctionAdoption']-or$null-eq$majorAdmission.preparation.correctionAdoption)
            if($reuseMajor){
                $originalInput=$majorAdmission.admission.originalAdmissionInput
                if((Read-AiwProjectJson $originalInput.discoverReceiptPath 'FIXED_ADOPTION_DISCOVER').Identity-cne$originalInput.expectedDiscoverReceiptIdentity-or
                   (Read-AiwProjectJson $majorAdmission.receipt.sourceLocators.authorizationPackagePath 'FIXED_ADOPTION_PACKAGE').Identity-cne$majorAdmission.context.authorizationIdentity-or
                   (Read-AiwProjectJson $configPath 'FIXED_ADOPTION_PROJECT').Identity-cne$configDocument.Identity){throw 'FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT'}
            }elseif($null-eq(Get-AiwFixedAdoptionAdmission $txn $root -ProcessObservation:$ProcessObservation)){return $null}
        }else{return $null}
        Assert-AiwAdoptionSame $txn.metadata.distributionBinding $binding 'FIXED_CURRENT_DISTRIBUTION'
        $reader=Get-AiwAdoptedReleaseReader $runtime $FrameworkVersion
        $lightObservation=$ProcessObservation-and(Test-AiwAdoptedReaderCommand $reader 'Get-AiwFixedReleaseProcessObservation')
        if($lightObservation){
            $projection=& $reader {param($v,$rt,$expected,$paths) Get-AiwFixedReleaseProcessObservation $v $rt $expected $paths} (Join-Path $runtime 'framework/versions/2.0.0') $runtime $binding $ConsumedPaths
            if($null-ne$state){
                if($state.targetReleaseCanonical-cne$projection.DeclaredPayloadCanonical-or$state.targetReleaseManifestIdentity-cne$projection.ManifestIdentity){throw 'FIXED_ADOPTION_SNAPSHOT_DRIFT'}
                Assert-AiwAdoptedToolDeclarations $projection.PackageObservation $state.rootToolRevision @($state.rootToolDependencies)
            }elseif(-not(Assert-AiwStableRegistrationTools $txn $original $runtime $projection.PackageObservation)){return $null}
        }else{
        $projection=& $reader {param($v,$rt,$expected) Get-AiwFixedReleaseProjection $v $rt $expected} (Join-Path $runtime 'framework/versions/2.0.0') $runtime $binding
        }
        if($null-ne$state-and-not$lightObservation){
            if($state.targetReleaseCanonical-cne$projection.Facts.Canonical-or$state.targetReleaseManifestIdentity-cne$projection.ManifestIdentity){throw 'FIXED_ADOPTION_SNAPSHOT_DRIFT'}
            $null=Assert-AiwRootToolRevision $runtime $state.rootToolRevision @($state.rootToolDependencies)
        }
        if($null-eq$state-and$projection.Version.lifecycle-cne'STABLE'){throw 'FIXED_REGISTRATION_STABLE_REQUIRED'}
        # Re-read the actual completion and state after the byte checks. Project
        # facts are deliberately not part of the reader's in-memory context.
        if((Read-AiwProjectJson (Get-AiwContainedPath $root $latest.relative) 'FIXED_ADOPTION_TRANSACTION').Identity-cne$latest.document.Identity-or($null-ne$stateDoc-and(Read-AiwProjectJson $statePath 'FIXED_ADOPTION_STATE').Identity-cne$stateDoc.Identity)){throw 'FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT'}
        if($ProcessObservation){
            return [pscustomobject]@{State='FIXED_ADOPTED_PROCESS_SOURCE';Manifest=$projection.Manifest;Version=$projection.Version;ManifestIdentity=$projection.ManifestIdentity;DeclaredPayloadCanonical=$(if($lightObservation){$projection.DeclaredPayloadCanonical}else{$projection.Facts.Canonical});PackageObservation=$(if($lightObservation){$projection.PackageObservation}else{$null});AdoptionIdentity=$latest.document.Identity;AdoptionStateIdentity=$(if($null-ne$stateDoc){$stateDoc.Identity}else{'MISSING'});AdoptionStateSchemaVersion=$(if($null-ne$state){$state.schemaVersion}else{0});DistributionBinding=$binding}
        }
        return [pscustomobject]@{State='FIXED_ADOPTED_SOURCE';Manifest=$projection.Manifest;Version=$projection.Version;Facts=$projection.Facts;ManifestIdentity=$projection.ManifestIdentity;AdoptionIdentity=$latest.document.Identity;DistributionBinding=$binding}
    }finally{Exit-AiwRootProjectSourceScope $lease}
}
Export-ModuleMember -Function Get-AiwFixedAdoptedRelease

function Assert-AiwAdoptionMembers($Object,[string[]]$Fields,[string]$Label){
    if($Object-isnot[pscustomobject]){throw ($Label+'_FIELDS')}
    foreach($field in $Fields){if($null-eq$Object.PSObject.Properties[$field]){throw ($Label+'_FIELD|'+$field)}}
}
function Assert-AiwAdoptionCompletion($Transaction){
    Assert-AiwAdoptionMembers $Transaction @() 'ADOPTION_TRANSACTION'
    if($null-eq$Transaction.PSObject.Properties['transactionComplete']-or$Transaction.transactionComplete-isnot[bool]-or-not$Transaction.transactionComplete-or
       $null-eq$Transaction.PSObject.Properties['state']-or$Transaction.state-isnot[string]-or$Transaction.state-cnotin@('COMPLETE','ROLLED_BACK')){throw 'ADOPTION_RECOVERY_REQUIRED'}
}
function Test-AiwFixedJournal($Transaction,[string]$Root,[string]$Relative){
    # Completion is checked first even for an unknown old schema. Probe only
    # discriminators here; never manufacture REGISTER from a locator.
    foreach($field in @('repositoryRoot','transactionRelativePath')){
        if($null-ne$Transaction.PSObject.Properties[$field]){
            Assert-AiwAdoptionStringFields $Transaction @($field) 'REGISTRATION_TRANSACTION'
            $expected=if($field-ceq'repositoryRoot'){$Root}else{$Relative}
            if($Transaction.$field-cne$expected){throw 'REGISTRATION_ORIGIN_TRANSACTION_INCOMPLETE'}
        }
    }
    if($null-ne$Transaction.PSObject.Properties['metadata']){
        Assert-AiwAdoptionMembers $Transaction.metadata @() 'REGISTRATION_TRANSACTION_METADATA'
        if($null-ne$Transaction.metadata.PSObject.Properties['operation']){Assert-AiwAdoptionStringFields $Transaction.metadata @('operation') 'REGISTRATION_TRANSACTION_METADATA'}
    }
    if($null-eq$Transaction.PSObject.Properties['schemaVersion']){return $false}
    if(-not(Test-AiwAdoptionInteger $Transaction.schemaVersion)){throw 'REGISTRATION_TRANSACTION_SCHEMA'}
    if($Transaction.schemaVersion-ne1-or$null-eq$Transaction.PSObject.Properties['metadata']-or$null-eq$Transaction.metadata.PSObject.Properties['operation']){return $false}
    $operation=$Transaction.metadata.operation
    if($operation-cnotin@('REGISTER','UPGRADE_RUNTIME_REFRESH','UPGRADE_FORMAT_TRANSITION','UPGRADE_SNAPSHOT12_TO_2')){return $false}
    $slots=if($operation-ceq'REGISTER'){@('register')}elseif($operation-ceq'UPGRADE_RUNTIME_REFRESH'){@('upgrade','refresh')}else{@('upgrade')}
    if($Relative-cnotin@($slots|ForEach-Object{'.ai-workspace/runtime/project-adoption/'+$_+'/state.json'})){throw 'REGISTRATION_ORIGIN_TRANSACTION_INCOMPLETE'}
    return $true
}
function Assert-AiwFixedBindingShape($Binding){
    Assert-AiwAdoptionStringFields $Binding @('distributionId','contentIdentity','manifestIdentity','runtimeRoot') 'FIXED_ADOPTION_DISTRIBUTION'
}
function Assert-AiwFixedAdmissionShape($Admit){
    Assert-AiwAdoptionMembers $Admit @('originalAdmissionInput','adoptionPreparation','authorityGranted','semanticCorrectnessProven','missingPreparation','missingResult') 'FIXED_ADOPTION_ADMIT'
    Assert-AiwAdoptionStringFields $Admit @('status','mode','selectionIdentity','decisionIdentity','adoptionPreparationBase64','adoptionPreparationIdentity') 'FIXED_ADOPTION_ADMIT'
    if($Admit.authorityGranted-isnot[bool]-or$Admit.semanticCorrectnessProven-isnot[bool]-or$Admit.missingPreparation-isnot[array]-or$Admit.missingResult-isnot[array]){throw 'FIXED_ADOPTION_ADMIT_SHAPE'}
    $a=$Admit.originalAdmissionInput;$p=$Admit.adoptionPreparation
    Assert-AiwAdoptionStringFields $a @('mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','publicDecisionIdentity','protectionState') 'FIXED_ADOPTION_ADMISSION_INPUT'
    Assert-AiwAdoptionMembers $a @('schemaVersion','preparationReceipts','resultReceipts','deliveryReceipts') 'FIXED_ADOPTION_ADMISSION_INPUT'
    if(-not(Test-AiwAdoptionInteger $a.schemaVersion)){throw 'FIXED_ADOPTION_ADMISSION_INPUT_SCHEMA'}
    foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){if($a.$name-isnot[array]){throw 'FIXED_ADOPTION_ADMISSION_INPUT_ARRAY'}}
    Assert-AiwAdoptionMembers $p @('projection','previousDistribution','targetDistribution','oldSourceBindings','selectedRuleBlocks') 'FIXED_ADOPTION_PREPARATION'
    Assert-AiwAdoptionStringFields $p @('discoverReceiptIdentity') 'FIXED_ADOPTION_PREPARATION'
    Assert-AiwAdoptionMembers $p.oldSourceBindings @() 'FIXED_ADOPTION_PREPARATION_SOURCES'
    Assert-AiwFixedObligationShape $p.selectedRuleBlocks
    Assert-AiwFixedBindingShape $p.previousDistribution;Assert-AiwFixedBindingShape $p.targetDistribution
}
function Assert-AiwFixedReceiptShape($Receipt){
    Assert-AiwAdoptionMembers $Receipt @('schemaVersion','inputContractVersion','intentEnvelope','sourceLocators','sourceBindings','selectedObligations','authorityGranted','semanticCorrectnessProven') 'FIXED_ADOPTION_DISCOVER'
    Assert-AiwAdoptionStringFields $Receipt @('status','mode','receiptType','sourceCompositionIdentity','selectionIdentity','contextIdentity') 'FIXED_ADOPTION_DISCOVER'
    if(-not(Test-AiwAdoptionInteger $Receipt.schemaVersion)-or-not(Test-AiwAdoptionInteger $Receipt.inputContractVersion)-or$Receipt.authorityGranted-isnot[bool]-or$Receipt.semanticCorrectnessProven-isnot[bool]){throw 'FIXED_ADOPTION_DISCOVER_SHAPE'}
    Assert-AiwFixedObligationShape $Receipt.selectedObligations
    $contextName=if($Receipt.schemaVersion-eq1){'authorityContext'}else{'binding'}
    Assert-AiwAdoptionMembers $Receipt @($contextName) 'FIXED_ADOPTION_DISCOVER'
    Assert-AiwAdoptionMembers $Receipt.$contextName @('exactScope','authorizedActions') 'FIXED_ADOPTION_DISCOVER_CONTEXT'
    Assert-AiwAdoptionStringFields $Receipt.$contextName @('frameworkVersion','actor','projectRoot','authorizationIdentity','taskIdentity') 'FIXED_ADOPTION_DISCOVER_CONTEXT'
    Assert-AiwAdoptionStringFields $Receipt.intentEnvelope @('objective','requestedActionKind','requestedResultKind','ambiguityState') 'FIXED_ADOPTION_DISCOVER_INTENT'
    Assert-AiwAdoptionStringFields $Receipt.sourceLocators @('frameworkRoot','taskRelativePath') 'FIXED_ADOPTION_DISCOVER_LOCATORS'
    Assert-AiwAdoptionStringFields $Receipt.sourceBindings @('projectConfigIdentity','controllerIdentity') 'FIXED_ADOPTION_DISCOVER_SOURCES'
}
function Assert-AiwFixedObligationShape($Obligations){
    if($Obligations-isnot[array]){throw 'FIXED_ADOPTION_OBLIGATIONS'}
    foreach($obligation in $Obligations){
        Assert-AiwAdoptionMembers $obligation @('preparationRequirements','resultRequirements') 'FIXED_ADOPTION_OBLIGATION'
        if($obligation.preparationRequirements-isnot[array]-or$obligation.resultRequirements-isnot[array]){throw 'FIXED_ADOPTION_OBLIGATION_ARRAY'}
    }
}
function Assert-AiwAdoptionFields($Object,[string[]]$Fields,[string]$Label) {
    if($Object-isnot[pscustomobject]-or@($Object.PSObject.Properties).Count-ne$Fields.Count-or
       @($Fields|Where-Object{$_-cnotin$Object.PSObject.Properties.Name}).Count){throw ($Label+'_FIELDS')}
}

function Test-AiwAdoptionInteger($Value) {
    return $Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or
        $Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]
}

function Assert-AiwAdoptionStringFields($Object,[string[]]$Fields,[string]$Label) {
    Assert-AiwAdoptionMembers $Object $Fields $Label
    foreach($field in $Fields){
        if($Object.$field-isnot[string]-or[string]::IsNullOrWhiteSpace($Object.$field)){throw ($Label+'_STRING|'+$field)}
    }
}

# Both registration and upgrade qualify the same current version payload.
# This does not seal a release or authorize a project write.
function Get-AiwLocalCandidateFrameworkSnapshot {
    param([Parameter(Mandatory)][string]$FrameworkPath,[Parameter(Mandatory)][string]$ExpectedVersion,[Parameter(Mandatory)]$AdoptionProfile,[string]$ProjectRoot)
    $root=Resolve-AiwRepositoryRoot $FrameworkPath
    $version=(Read-AiwProjectJson (Get-AiwContainedPath $root 'VERSION.json') 'FRAMEWORK_CANDIDATE_VERSION').Value
    $doc=Read-AiwProjectJson (Get-AiwContainedPath $root 'RELEASE_MANIFEST.json') 'FRAMEWORK_CANDIDATE_MANIFEST';$m=$doc.Value
    Assert-AiwAdoptionStringFields $version @('version','lifecycle') 'FRAMEWORK_CANDIDATE_VERSION'
    if($version.version-cne$ExpectedVersion-or$version.lifecycle-cne'CANDIDATE'-or$version.consumable-isnot[bool]-or$version.consumable-or
       $version.projectPinEligible-isnot[bool]-or$version.projectPinEligible){throw "FRAMEWORK_LOCAL_CANDIDATE_STATE_REQUIRED|$ExpectedVersion"}
    if($AdoptionProfile.frameworkVersion-cne$ExpectedVersion-or$AdoptionProfile.localCandidatePilotEligible-isnot[bool]-or
        -not$AdoptionProfile.localCandidatePilotEligible){throw "FRAMEWORK_LOCAL_CANDIDATE_PROFILE_REQUIRED|$ExpectedVersion"}
    if($ExpectedVersion-ceq'2.0.0'){
        $runtime=[IO.Path]::GetFullPath((Join-Path $root '../../..'))
        $reader=Get-AiwAdoptedReleaseReader $runtime $ExpectedVersion
        try{
            $qualified=if($ProjectRoot){Get-AiwFixedAdoptedRelease -ProjectRoot $ProjectRoot -FrameworkRoot $runtime -FrameworkVersion $ExpectedVersion}else{$null}
            if($null-eq$qualified){$qualified=& $reader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $root -RuntimeRoot $runtime}
        }catch{throw ('FRAMEWORK_LOCAL_CANDIDATE_REVIEW_REQUIRED|'+$ExpectedVersion+'|'+$_.Exception.Message)}
        return [pscustomobject]@{Version=$ExpectedVersion;Lifecycle='CANDIDATE';LocalCandidate=$true;FileCount=$qualified.Facts.FileCount;TotalBytes=$qualified.Facts.TotalBytes;Canonical=$qualified.Facts.Canonical;ManifestIdentity=$doc.Identity}
    }
    Assert-AiwAdoptionFields $m @('schemaVersion','version','lifecycle','releaseClass','scope','algorithm','fileCount','totalBytes','canonical','baseline','sourceReview','sourceCandidate','completeSuite','sourceReviewEvidence','releaseIntegration') 'FRAMEWORK_CANDIDATE_MANIFEST'
    Assert-AiwAdoptionStringFields $m @('version','lifecycle','canonical','sourceReview','sourceCandidate','releaseIntegration') 'FRAMEWORK_CANDIDATE_MANIFEST'
    if(-not(Test-AiwAdoptionInteger $m.schemaVersion)-or$m.schemaVersion-ne2-or$m.version-cne$ExpectedVersion-or$m.lifecycle-cne'CANDIDATE'-or$m.sourceReview-cne'APPROVED'-or
       $m.releaseIntegration-cne'PENDING'-or[string]::IsNullOrWhiteSpace($m.sourceCandidate)){throw "FRAMEWORK_LOCAL_CANDIDATE_REVIEW_REQUIRED|$ExpectedVersion"}
    $paths=[Collections.Generic.List[string]]::new()
    foreach($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force)){
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'FRAMEWORK_CANDIDATE_REPARSE'}
        if(-not$item.PSIsContainer){$relative=[IO.Path]::GetRelativePath($root,$item.FullName).Replace('\','/');if($relative-cne'RELEASE_MANIFEST.json'){$paths.Add($relative)}}
    }
    $ordered=[string[]]@($paths);[Array]::Sort($ordered,[StringComparer]::Ordinal)
    $rows=[Collections.Generic.List[string]]::new();[int64]$bytes=0
    foreach($relative in $ordered){$identity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Get-AiwContainedPath $root $relative)))).Split('|');$bytes+=[int64]$identity[0];$rows.Add($relative+'|'+$identity[0]+'|'+$identity[1])}
    $canonical=(Get-AiwByteIdentity ($script:Utf8Strict.GetBytes([string]::Join("`n",$rows)))).Split('|')[1]
    if(-not(Test-AiwAdoptionInteger $m.fileCount)-or-not(Test-AiwAdoptionInteger $m.totalBytes)-or$m.fileCount-ne$ordered.Count-or$m.totalBytes-ne$bytes-or$m.canonical-cne$canonical){throw "FRAMEWORK_LOCAL_CANDIDATE_MANIFEST_DRIFT|$ExpectedVersion"}
    $suite=$m.completeSuite;Assert-AiwAdoptionFields $suite @('status','passed','total','payloadCanonical','evidenceIdentity') 'FRAMEWORK_CANDIDATE_SUITE'
    Assert-AiwAdoptionStringFields $suite @('status','payloadCanonical','evidenceIdentity') 'FRAMEWORK_CANDIDATE_SUITE'
    if($suite.status-cne'PASS'-or-not(Test-AiwAdoptionInteger $suite.passed)-or-not(Test-AiwAdoptionInteger $suite.total)-or$suite.passed-lt1-or$suite.passed-ne$suite.total-or
       $suite.payloadCanonical-cne$canonical-or$suite.evidenceIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw "FRAMEWORK_LOCAL_CANDIDATE_COMPLETE_SUITE_REQUIRED|$ExpectedVersion"}
    $review=$m.sourceReviewEvidence;Assert-AiwAdoptionFields $review @('status','reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity') 'FRAMEWORK_CANDIDATE_REVIEW'
    Assert-AiwAdoptionStringFields $review @('status','reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity') 'FRAMEWORK_CANDIDATE_REVIEW'
    if($review.status-cne'APPROVED'-or[string]::IsNullOrWhiteSpace($review.reviewer)-or$review.reviewer-ceq'PENDING'-or
       $review.packageIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$review.reviewedPayloadCanonical-cne$canonical-or
       $review.reviewedManifestIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw "FRAMEWORK_LOCAL_CANDIDATE_SOURCE_REVIEW_EVIDENCE_REQUIRED|$ExpectedVersion"}
    return [pscustomobject]@{Version=$ExpectedVersion;Lifecycle='CANDIDATE';LocalCandidate=$true;FileCount=$ordered.Count;TotalBytes=$bytes;Canonical=$canonical;ManifestIdentity=$doc.Identity}
}

function Assert-AiwRegistrationJournal($Document,[string]$Root,[string]$Relative,[string]$Operation) {
    $t=$Document.Value
    Assert-AiwAdoptionMembers $t @('schemaVersion','metadata','transactionComplete','completedWrites','projection') 'REGISTRATION_TRANSACTION'
    Assert-AiwAdoptionStringFields $t @('state','repositoryRoot','transactionRelativePath') 'REGISTRATION_TRANSACTION'
    Assert-AiwAdoptionStringFields $t.metadata @('operation') 'REGISTRATION_TRANSACTION_METADATA'
    Assert-AiwAdoptionMembers $t.projection @('schemaVersion','repositoryRoot','objects') 'REGISTRATION_PROJECTION'
    Assert-AiwAdoptionStringFields $t.projection @('repositoryRoot') 'REGISTRATION_PROJECTION'
    if($t.projection.objects-isnot[array]){throw 'REGISTRATION_PROJECTION_OBJECTS'}
    foreach($entry in $t.projection.objects){
        Assert-AiwAdoptionMembers $entry @('path','kind','oldExists','newExists','oldIdentity','newIdentity','changed','oldBase64','newBase64') 'REGISTRATION_PROJECTION_OBJECT'
        Assert-AiwAdoptionStringFields $entry @('path','kind','oldIdentity','newIdentity') 'REGISTRATION_PROJECTION_OBJECT'
        if($entry.oldBase64-isnot[string]-or$entry.newBase64-isnot[string]){throw 'REGISTRATION_PROJECTION_OBJECT_BYTES'}
    }
    if(-not(Test-AiwAdoptionInteger $t.schemaVersion)-or$t.schemaVersion-ne1-or$t.state-cne'COMPLETE'-or$t.transactionComplete-isnot[bool]-or-not$t.transactionComplete-or
       $t.repositoryRoot-cne$Root-or$t.transactionRelativePath-cne$Relative-or$t.metadata.operation-cne$Operation-or
       -not(Test-AiwAdoptionInteger $t.completedWrites)-or$t.completedWrites-ne@($t.projection.objects|Where-Object changed).Count){throw 'REGISTRATION_ORIGIN_TRANSACTION_INCOMPLETE'}
    # Reuse the transaction contract, including all recorded byte identities.
    Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1') -ErrorAction Stop
    $null=Assert-AiwProjectionContract $Root $t.projection
    return $t
}

# Private evaluation context: ordinary CLI switches never create it. The
# transaction caller supplies a verified projection and its actual source root.
function Invoke-AiwRegistrationProjectionContext {
    param([string]$ProjectRoot,[string]$SourceProjectRoot,$Projection,[scriptblock]$Body,[switch]$InitialRegistration)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $SourceProjectRoot -Mode OBSERVE
try {

    $source=Resolve-AiwRepositoryRoot $SourceProjectRoot;$stage=Resolve-AiwRepositoryRoot $ProjectRoot
    Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1') -ErrorAction Stop
    $null=Assert-AiwProjectionContract $source $Projection
    $prior=$script:RegistrationProjectionContext
    if($InitialRegistration-and(Test-Path -LiteralPath (Get-AiwContainedPath $source '.ai-workspace/project.json'))){throw 'REGISTRATION_INITIAL_CONTROL_PLANE_REQUIRED'}
    try{$script:RegistrationProjectionContext=[pscustomobject]@{ProjectRoot=$stage;SourceRoot=$source;Projection=$Projection;InitialRegistration=[bool]$InitialRegistration}; & $Body}
    finally{$script:RegistrationProjectionContext=$prior}

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
$script:RegistrationProjectionContext=$null

function Assert-AiwRegistrationOrigin {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$FrameworkVersion,[string]$FrameworkRoot)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $(if($null-ne$script:RegistrationProjectionContext-and$script:RegistrationProjectionContext.ProjectRoot-ceq$ProjectRoot){$script:RegistrationProjectionContext.SourceRoot}else{$ProjectRoot}) -Mode OBSERVE
try {

    $root=Resolve-AiwRepositoryRoot $ProjectRoot;$source=$root;$prospective=$false
    if($null-ne$script:RegistrationProjectionContext-and$script:RegistrationProjectionContext.ProjectRoot-ceq$root){
        $source=$script:RegistrationProjectionContext.SourceRoot;$prospective=$true
    }
    if(-not$prospective){
        foreach($journalPath in @('.ai-workspace/runtime/project-adoption/register/state.json','.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
            $path=Get-AiwContainedPath $root $journalPath
            if(Test-Path -LiteralPath $path -PathType Leaf){
                $journal=(Read-AiwProjectJson $path 'ADOPTION_TRANSACTION').Value
                Assert-AiwAdoptionCompletion $journal
            }
        }
    }
    $relative='.ai-workspace/upgrade-recovery/'+$FrameworkVersion+'/state.json'
    $doc=Read-AiwProjectJson (Get-AiwContainedPath $root $relative) 'REGISTRATION_ORIGIN_STATE';$state=$doc.Value
    Assert-AiwAdoptionFields $state @('schemaVersion','originKind','projectId','repositoryRoot','toVersion','projectionMode','transactionComplete','targetReleaseCanonical','targetReleaseManifestIdentity','distributionBinding','origin','currentTransactionRelativePath','registrationTransactionIdentity','projectFormat','projectCapabilities','rootToolRevision','rootToolDependencies','projectionObjects') 'REGISTRATION_ORIGIN_STATE'
    Assert-AiwAdoptionFields $state.origin @('operation','transactionRelativePath','registrationId') 'REGISTRATION_ORIGIN'
    Assert-AiwAdoptionStringFields $state @('originKind','projectId','repositoryRoot','toVersion','projectionMode','targetReleaseCanonical','targetReleaseManifestIdentity','currentTransactionRelativePath','registrationTransactionIdentity','projectFormat','rootToolRevision') 'REGISTRATION_ORIGIN_STATE'
    Assert-AiwAdoptionStringFields $state.origin @('operation','transactionRelativePath','registrationId') 'REGISTRATION_ORIGIN'
    $registerRelative='.ai-workspace/runtime/project-adoption/register/state.json';$refreshRelative='.ai-workspace/runtime/project-adoption/refresh/state.json'
    if(-not(Test-AiwAdoptionInteger $state.schemaVersion)-or$state.schemaVersion-ne7-or$state.originKind-cne'REGISTER'-or$FrameworkVersion-cne'2.0.0'-or$state.toVersion-cne$FrameworkVersion-or
       $state.repositoryRoot-cne$source-or$state.transactionComplete-isnot[bool]-or-not$state.transactionComplete-or
       $state.projectionMode-cne'LOCAL_CANDIDATE_MANAGED'-or$state.origin.operation-cne'REGISTER'-or
       $state.origin.transactionRelativePath-cne$registerRelative-or$state.origin.registrationId-cnotmatch'^[A-F0-9]{64}$'-or
       $state.currentTransactionRelativePath-cnotin@($registerRelative,$refreshRelative)-or$state.projectionObjects-isnot[array]){throw 'REGISTRATION_ORIGIN_BINDING_DRIFT'}
    if($prospective-and$script:RegistrationProjectionContext.InitialRegistration){
        $projection=$script:RegistrationProjectionContext.Projection
        $planned=@($projection.objects|Where-Object{$_.path-ceq$relative})
        if($planned.Count-ne1-or$planned[0].oldExists-or$planned[0].newIdentity-cne$doc.Identity-or
           $state.registrationTransactionIdentity-cne'SELF_PROJECTION_BOUND'-or$state.currentTransactionRelativePath-cne$registerRelative){throw 'REGISTRATION_PROSPECTIVE_STATE_DRIFT'}
        $files=@($projection.objects|Where-Object{$_.kind-ceq'FILE'-and$_.path-cne$relative})
        if($files.Count-ne$state.projectionObjects.Count){throw 'REGISTRATION_PROSPECTIVE_PROJECTION_DRIFT'}
        foreach($entry in $files){
            $record=@($state.projectionObjects|Where-Object{$_.relative-ceq$entry.path})
            if($record.Count-ne1-or$record[0].identity-cne$entry.newIdentity-or
               (Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Get-AiwContainedPath $root $entry.path))))-cne$entry.newIdentity){throw 'REGISTRATION_PROSPECTIVE_PROJECTION_DRIFT'}
        }
        if($FrameworkRoot){$null=Assert-AiwDistributionBinding $state.distributionBinding $FrameworkRoot $FrameworkVersion}
        return [pscustomobject]@{State=$state;Identity=$doc.Identity;SchemaVersion=7;TransactionComplete=$true;ProjectionMode=$state.projectionMode;Canonical=$state.targetReleaseCanonical}
    }
    $registration=Read-AiwProjectJson (Get-AiwContainedPath $root $registerRelative) 'REGISTRATION_ORIGIN_TRANSACTION'
    $t=Assert-AiwRegistrationJournal $registration $source $registerRelative 'REGISTER'
    Assert-AiwAdoptionMembers $t.metadata @('initialTask','distributionBinding') 'REGISTRATION_TRANSACTION_METADATA'
    Assert-AiwAdoptionStringFields $t.metadata @('registrationId','frameworkPin','targetReleaseCanonical','targetReleaseManifestIdentity','rootToolRevision','targetProjectFormat') 'REGISTRATION_TRANSACTION_METADATA'
    Assert-AiwAdoptionFields $t.metadata.initialTask @('relativePath','identity') 'REGISTRATION_INITIAL_TASK'
    Assert-AiwAdoptionStringFields $t.metadata.initialTask @('relativePath','identity') 'REGISTRATION_INITIAL_TASK'
    if($t.metadata.registrationId-cne$state.origin.registrationId-or$t.metadata.frameworkPin-cne$FrameworkVersion){throw 'REGISTRATION_ORIGIN_METADATA_DRIFT'}
    $entries=@($t.projection.objects|Where-Object{$_.path-ceq$relative})
    if($entries.Count-ne1-or$entries[0].kind-cne'FILE'-or$entries[0].oldExists-or-not$entries[0].newExists){throw 'REGISTRATION_ORIGIN_STATE_PROJECTION'}
    $originBytes=[Convert]::FromBase64String($entries[0].newBase64)
    $original=ConvertFrom-AiwAdoptionBytes $originBytes
    Assert-AiwAdoptionMembers $original @('schemaVersion','origin','distributionBinding','projectionObjects') 'REGISTRATION_ORIGIN_ORIGINAL'
    Assert-AiwAdoptionStringFields $original @('originKind','projectId','repositoryRoot','toVersion','registrationTransactionIdentity','currentTransactionRelativePath','targetReleaseCanonical','targetReleaseManifestIdentity','rootToolRevision','projectFormat') 'REGISTRATION_ORIGIN_ORIGINAL'
    if($original.projectionObjects-isnot[array]){throw 'REGISTRATION_ORIGIN_ORIGINAL_PROJECTION'}
    foreach($record in $original.projectionObjects){Assert-AiwAdoptionStringFields $record @('relative','identity') 'REGISTRATION_ORIGIN_ORIGINAL_PROJECTION'}
    foreach($name in @('schemaVersion','originKind','projectId','repositoryRoot','toVersion','origin')){
        if(-not(Test-AiwRootJsonSame $original.$name $state.$name)){throw ('REGISTRATION_ORIGIN_DRIFT|'+$name)}
    }
    if($original.registrationTransactionIdentity-cne'SELF_PROJECTION_BOUND'-or$original.currentTransactionRelativePath-cne$registerRelative-or
       -not(Test-AiwRootJsonSame $original.distributionBinding $t.metadata.distributionBinding)-or
       $original.targetReleaseCanonical-cne$t.metadata.targetReleaseCanonical-or$original.targetReleaseManifestIdentity-cne$t.metadata.targetReleaseManifestIdentity-or
       $original.rootToolRevision-cne$t.metadata.rootToolRevision-or$original.projectFormat-cne$t.metadata.targetProjectFormat){throw 'REGISTRATION_ORIGIN_METADATA_DRIFT'}
    $required=@('.ai-workspace/project.json','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md',[string]$t.metadata.initialTask.relativePath)
    if($t.metadata.initialTask.relativePath-cnotmatch'^\.ai-workspace/tasks/active/[0-9A-Za-z][0-9A-Za-z._-]*\.md$'){throw 'REGISTRATION_INITIAL_TASK_BINDING'}
    foreach($path in $required){
        $entry=@($t.projection.objects|Where-Object{$_.path-ceq$path})
        $binding=@($original.projectionObjects|Where-Object{$_.relative-ceq$path})
        if($entry.Count-ne1-or$entry[0].kind-cne'FILE'-or-not$entry[0].newExists-or$binding.Count-ne1-or$binding[0].identity-cne$entry[0].newIdentity){throw ('REGISTRATION_ORIGIN_PROJECTION_MISSING|'+$path)}
    }
    if($t.metadata.initialTask.identity-cne@($t.projection.objects|Where-Object{$_.path-ceq$t.metadata.initialTask.relativePath})[0].newIdentity){throw 'REGISTRATION_INITIAL_TASK_BINDING'}
    if($prospective){
        $planned=@($script:RegistrationProjectionContext.Projection.objects|Where-Object{$_.path-ceq$relative})
        if($planned.Count-ne1-or$planned[0].newIdentity-cne$doc.Identity){throw 'REGISTRATION_PROSPECTIVE_STATE_DRIFT'}
        $sourceRegistration=Read-AiwProjectJson (Get-AiwContainedPath $source $registerRelative) 'REGISTRATION_SOURCE_TRANSACTION'
        if($registration.Identity-cne$sourceRegistration.Identity){throw 'REGISTRATION_SOURCE_TRANSACTION_DRIFT'}
    }elseif($state.currentTransactionRelativePath-ceq$registerRelative){
        if($state.registrationTransactionIdentity-cne'SELF_PROJECTION_BOUND'-or$doc.Identity-cne$entries[0].newIdentity){throw 'REGISTRATION_ORIGIN_POSTIMAGE_DRIFT'}
    }else{
        if($state.registrationTransactionIdentity-cne$registration.Identity){throw 'REGISTRATION_ORIGIN_TRANSACTION_DRIFT'}
        $refresh=Read-AiwProjectJson (Get-AiwContainedPath $root $refreshRelative) 'REGISTRATION_REFRESH_TRANSACTION'
        $rt=Assert-AiwRegistrationJournal $refresh $source $refreshRelative 'UPGRADE_RUNTIME_REFRESH'
        Assert-AiwAdoptionMembers $rt.metadata @('distributionBinding') 'REGISTRATION_REFRESH_METADATA'
        $new=@($rt.projection.objects|Where-Object{$_.path-ceq$relative})
        if($new.Count-ne1-or$new[0].newIdentity-cne$doc.Identity-or
           -not(Test-AiwRootJsonSame $rt.metadata.distributionBinding $state.distributionBinding)){throw 'REGISTRATION_REFRESH_POSTIMAGE_DRIFT'}
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $state.projectionObjects){
        Assert-AiwAdoptionStringFields $entry @('relative','identity') 'REGISTRATION_PROJECTION_OBJECT'
        $fields=@('relative','identity')
        if($entry.relative-in@('.ai-workspace/BOOTSTRAP.md','AGENTS.md')-and$null-ne$entry.PSObject.Properties['managedIdentity']){$fields+='managedIdentity';if($entry.managedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'REGISTRATION_PROJECTION_OBJECT_INVALID'}}
        Assert-AiwAdoptionFields $entry $fields 'REGISTRATION_PROJECTION_OBJECT'
        Assert-AiwRelativePath $entry.relative
        if(-not$seen.Add($entry.relative)-or$entry.relative-ceq$relative-or$entry.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'REGISTRATION_PROJECTION_OBJECT_INVALID'}
    }
    if($state.rootToolRevision-cnotmatch'^[A-F0-9]{64}$'-or$state.rootToolDependencies-isnot[array]-or$state.projectCapabilities-isnot[array]-or$state.projectFormat-cnotmatch'^repo-local/project-config-[1-9][0-9]*$'){throw 'REGISTRATION_RUNTIME_IDENTITY'}
    $config=(Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'REGISTERED_PROJECT').Value
    if($config.id-cne$state.projectId-or$config.frameworkVersion-cne$FrameworkVersion){throw 'REGISTRATION_PROJECT_BINDING_DRIFT'}
    if($FrameworkRoot){$null=Assert-AiwDistributionBinding $state.distributionBinding $FrameworkRoot $FrameworkVersion}
    return [pscustomobject]@{State=$state;Identity=$doc.Identity;Registration=$registration;SchemaVersion=7;TransactionComplete=$true;ProjectionMode=$state.projectionMode;Canonical=$state.targetReleaseCanonical}

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
Export-ModuleMember -Function Get-AiwLocalCandidateFrameworkSnapshot,Assert-AiwRegistrationOrigin,Invoke-AiwRegistrationProjectionContext

function Get-AiwAgentsTemplateBlock {
    param([string]$Text,[ValidateSet('FRAMEWORK','USER-DECISION')][string]$Block='FRAMEWORK')
    $begin='<!-- AI-WORKSPACE-'+$Block+':BEGIN -->';$end='<!-- AI-WORKSPACE-'+$Block+':END -->'
    $start=$Text.IndexOf($begin,[StringComparison]::Ordinal);$finish=$Text.IndexOf($end,[StringComparison]::Ordinal)
    if($start-lt0-or$finish-lt$start-or[regex]::Matches($Text,[regex]::Escape($begin)).Count-ne1-or[regex]::Matches($Text,[regex]::Escape($end)).Count-ne1){throw 'AGENTS_TEMPLATE_BLOCK'}
    return $Text.Substring($start,$finish+$end.Length-$start)+"`n"
}
function ConvertTo-AiwAgentsUserRegions {
    param([AllowEmptyString()][string]$Text)
    # Labels identify user-owned text, never whether its decisions are valid.
    # Keep independent regions in their original order instead of moving an old
    # grant behind a later restriction or merging/rewording human paragraphs.
    $regions=[Collections.Generic.List[object]]::new();$open=-1
    foreach($marker in [regex]::Matches($Text,'<!-- AI-WORKSPACE-USER-DECISION:(BEGIN|END) -->')){
        if($marker.Groups[1].Value-ceq'BEGIN'){
            if($open-ge0){throw 'AGENTS_USER_DECISION_MARKERS_MALFORMED|nested'};$open=$marker.Index
        }else{
            if($open-lt0){throw 'AGENTS_USER_DECISION_MARKERS_MALFORMED|unmatched-end'}
            $regions.Add(@{start=$open;end=$marker.Index+$marker.Length});$open=-1
        }
    }
    if($open-ge0){throw 'AGENTS_USER_DECISION_MARKERS_MALFORMED|unmatched-begin'}
    $managed=[regex]::Match($Text,'(?s)<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->.*?<!-- AI-WORKSPACE-FRAMEWORK:END -->')
    $protected=@($regions)+@(@{start=$managed.Index;end=$managed.Index+$managed.Length})
    $wrap=[Collections.Generic.List[object]]::new()
    $patterns=@('(?ms)^## 项目工作约定（用户拥有）\r?\n.*?(?=^#{1,2} |^<!-- AI-WORKSPACE-|\z)',
        '(?m)^(?:在本项目内，|已批准协作工作流内的)[^\r\n]*(?:\r?\n(?!\r?$|#|<!--)[^\r\n]+)*')
    foreach($pattern in $patterns){foreach($part in [regex]::Matches($Text,$pattern)){
        $last=$part.Index+$part.Length
        if(@(@($protected)+@($wrap)|Where-Object{$part.Index-lt$_.end-and$last-gt$_.start}).Count){continue}
        $wrap.Add(@{start=$part.Index;end=$last;text=$part.Value})
    }}
    foreach($part in @($wrap|Sort-Object start -Descending)){
        $nl=if($part.text.Contains("`r`n")){"`r`n"}else{"`n"}
        $endSeparator=if($part.text.EndsWith("`n")){''}else{$nl}
        $value='<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->'+$nl+$part.text+$endSeparator+'<!-- AI-WORKSPACE-USER-DECISION:END -->'+$nl
        $Text=$Text.Substring(0,$part.start)+$value+$Text.Substring($part.end)
    }
    return $Text
}
function Get-AiwAgentsManagedParagraphs([string]$Block) {
    foreach($part in [regex]::Split($Block,'(?:\r?\n){2,}')){
        $body=[regex]::Replace($part,'(?m)^<!-- AI-WORKSPACE-FRAMEWORK:(?:BEGIN|END) -->\r?\n?','')
        $body=[regex]::Replace($body,'(?m)^# AI Workspace Framework(?: Maintenance)?\r?\n?','').Trim("`r","`n")
        if($body.Length){$body}
    }
}
function Test-AiwAgentsGrantParagraph([string]$Text) {
    return $Text.StartsWith('在本项目内，')-or$Text.StartsWith('已批准协作工作流内的')
}
function Get-AiwAgentsSourceNavigation($Source) {
    # These are the original adoption facts supplied by the upgrader, not a
    # caller assertion that today's whole AGENTS file is an installation image.
    $record=$Source.record
    if($record.relative-cne'AGENTS.md'-or$record.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'AGENTS_SOURCE_PROJECTION_REQUIRED'}
    $templateBlock=(Get-AiwAgentsTemplateBlock $Source.templateText).TrimEnd("`r","`n")
    $sourceParts=@(Get-AiwAgentsManagedParagraphs $templateBlock|Where-Object{-not(Test-AiwAgentsGrantParagraph $_)}|ForEach-Object{$_.Replace("`r`n","`n")})
    if($sourceParts.Count-eq0){throw 'AGENTS_SOURCE_NAVIGATION_REQUIRED'}
    $managed=if($null-ne$record.PSObject.Properties['managedIdentity']){[string]$record.managedIdentity}else{''}
    $originalBlock=$templateBlock
    if($null-ne$Source.originalBytes){
        if($Source.originalBytes-isnot[byte[]]-or(Get-AiwByteIdentity $Source.originalBytes)-cne$record.identity){throw 'AGENTS_SOURCE_ORIGINAL_IDENTITY'}
        if($Source.originalBytes.Length-ge3-and$Source.originalBytes[0]-eq239-and$Source.originalBytes[1]-eq187-and$Source.originalBytes[2]-eq191){throw 'AGENTS_SOURCE_ORIGINAL_BOM'}
        $original=[Text.UTF8Encoding]::new($false,$true).GetString($Source.originalBytes)
        if($original.Contains([char]0)-or$original.Contains([char]0xFFFD)){throw 'AGENTS_SOURCE_ORIGINAL_TEXT'}
        $originalBlock=(Get-AiwAgentsTemplateBlock $original).TrimEnd("`r","`n")
        $actual=Get-AiwByteIdentity ([Text.Encoding]::UTF8.GetBytes($originalBlock))
        if($managed-and$actual-cne$managed){throw 'AGENTS_SOURCE_MANAGED_IDENTITY'}
    }elseif(-not$managed-or(Get-AiwByteIdentity ([Text.Encoding]::UTF8.GetBytes($templateBlock)))-cne$managed){
        throw 'AGENTS_SOURCE_ORIGINAL_REQUIRED'
    }
    # An installed image/hash alone does not establish pure navigation. Only
    # navigation present in the corresponding fixed old template may be replaced.
    # Managed grants are never classified as navigation, even in that template.
    $originalParts=@(Get-AiwAgentsManagedParagraphs $originalBlock|Where-Object{-not(Test-AiwAgentsGrantParagraph $_)}|ForEach-Object{$_.Replace("`r`n","`n")})
    if(($originalParts|ConvertTo-Json -Compress)-cne($sourceParts|ConvertTo-Json -Compress)){throw 'AGENTS_SOURCE_TEMPLATE_MISMATCH'}
    return $sourceParts
}

function Get-AiwStandingDelegationProjection {
    param([AllowEmptyString()][string]$Text, [bool]$AdoptionRequested = $false, [string]$TemplatePath, [AllowEmptyString()][string]$RouterSkillName, [ValidateSet('SKILL','PROJECT_BOOTSTRAP')][string]$NavigationKind='SKILL',$SourceNavigation=$null)
    if (-not $AdoptionRequested) { return $Text }
    if([string]::IsNullOrWhiteSpace($TemplatePath)){throw 'DELEGATION_TEMPLATE_REQUIRED'}
    if($NavigationKind-ceq'PROJECT_BOOTSTRAP'){
        $template=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($TemplatePath))
        $block=(Get-AiwAgentsTemplateBlock $template).TrimEnd("`r","`n")
        if(-not$block.Contains('.ai-workspace/BOOTSTRAP.md')-or$block.Contains('{{ROUTER_SKILL_NAME}}')){throw 'AGENTS_BOOTSTRAP_TEMPLATE_MISMATCH'}
        $begin='<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->';$end='<!-- AI-WORKSPACE-FRAMEWORK:END -->'
        $starts=[regex]::Matches($Text,[regex]::Escape($begin)).Count;$ends=[regex]::Matches($Text,[regex]::Escape($end)).Count
        if($starts-eq0-and$ends-eq0){
            $separator=if($Text.Length-eq0){''}elseif($Text.EndsWith("`n")){"`n"}else{"`n`n"}
            # Only a genuinely new entry receives the adopted starter decision.
            # Existing project text may already narrow or withdraw a delegation.
            $addition=if([string]::IsNullOrWhiteSpace($Text)){$template}else{$block+"`n"}
            return ConvertTo-AiwAgentsUserRegions ($Text+$separator+$addition)
        }
        if($starts-ne1-or$ends-ne1-or$Text.IndexOf($begin)-gt$Text.IndexOf($end)){throw 'AGENTS_MANAGED_MARKERS_MALFORMED'}
        $first=$Text.IndexOf($begin);$last=$Text.IndexOf($end)+$end.Length;$old=$Text.Substring($first,$last-$first)
        $grant=@()
        $sourceNavigationParts=@()
        if($null-ne$SourceNavigation){$sourceNavigationParts=@(Get-AiwAgentsSourceNavigation $SourceNavigation)}
        # An already-current target remains idempotent. Different old navigation
        # must be accounted for by original adoption facts or legacy parsing.
        # Only the complete current target block is free of a managed grant.
        # Compare CRLF/LF equivalently; preserve original Text and outside bytes.
        # All other content must pass the existing grant/conflict parser.
        $knownPureNavigation=($old.Replace("`r`n","`n")-ceq$block.Replace("`r`n","`n"))
        if(-not$knownPureNavigation){
            $paragraph=0
            foreach($part in [regex]::Split($old,'(?:\r?\n){2,}')){
                $paragraph++
                $body=[regex]::Replace($part,'(?m)^<!-- AI-WORKSPACE-FRAMEWORK:(?:BEGIN|END) -->\r?\n?','')
                $body=[regex]::Replace($body,'(?m)^# AI Workspace Framework(?: Maintenance)?\r?\n?','').Trim("`r","`n")
                if($body.Length-eq0){continue}
                if(Test-AiwAgentsGrantParagraph $body){$grant+=,$body;continue}
                $knownNavigation=@(
                    ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pys6aG555uu6YeH55SoIEFJIFdvcmtzcGFjZSBGcmFtZXdvcmvvvIzkvb/nlKjlt7LmjqXlhaXnmoQgYGFpLXdvcmtzcGFjZS1yb3V0ZXJgIFNraWxsIOaMiemcgOW8gOWxleayu+eQhuW3peS9nOOAgg=='))),
                    ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pys6aG555uu6YeH55SoIEFJIFdvcmtzcGFjZSBGcmFtZXdvcmvvvIzkvb/nlKjlt7LmjqXlhaXnmoQgYGFpLXdvcmtzcGFjZS1yb3V0ZXJgIFNraWxsIOaMiemcgOW8gOWxlee7tOaKpOayu+eQhu+8m+W8gOWPkea6kOeggeS9jeS6jueLrOeri+eahCBGcmFtZXdvcmsgdGFyZ2V044CC'))),
                    ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pys6aG555uu6YeH55SoIEFJIFdvcmtzcGFjZSBGcmFtZXdvcmvjgILlvIDlsZXpobnnm67ku7vliqHml7bkvb/nlKggYGFpLXdvcmtzcGFjZS1yb3V0ZXItdjJgIFNraWxs77yb5bey5Yqg6L295LiU5pyJ5pWI5pe25aSN55So44CC'))),
                    ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pys6aG555uu6YeH55SoIEFJIFdvcmtzcGFjZSBGcmFtZXdvcmvjgILlvIDlsZXpobnnm67ku7vliqHml7bkvb/nlKggYGFpLXdvcmtzcGFjZS1yb3V0ZXItdjJgIFNraWxs77yb5bey5Yqg6L295LiU5pyJ5pWI5pe25aSN55So44CC5byA5Y+R5rqQ56CB5L2N5LqO54us56uL55qEIEZyYW1ld29yayB0YXJnZXTjgII='))),
                    ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5LiK5LiL5paH5Y6L57yp5oiW5o2i5Li75L2T5ZCO55qE6aaW5qyh5a6e6LSo6aG555uu5Yqo5L2c77yM6YeN6K+76K+lIFNraWxsIOWujOaVtOato+aWh+WPiuW9k+WJjeWRveS4reinhOWImeWFqOaWh++8m+aRmOimgeS4reeahOKAnOW3suWKoOi9veKAneS4jeS9nOS4uuWkjeeUqOivgeaNruOAgg=='))),
                    ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('55So5oi35Y+v55u05o6l57yW6L6R5pys566h55CG5Yy65o6I5p2D5q2j5paH77yM5pel5bi45Lul5b2T5YmN5q2j5paH5Li65YeG44CC5Y2H57qn5oyJ55uu5qCH5qih5p2/5pu05paw566h55CG5Yy65bm25L+d55WZ5Yy65aSW5YaF5a6544CC')))
                )
                if($body-cin$knownNavigation-or$body.Replace("`r`n","`n")-cin$sourceNavigationParts){continue}
                # Preserve the complete live object on unknown mixed custom;
                # there is no best-effort deletion or template grant fallback.
                throw ('AGENTS_AUTHORIZATION_MIGRATION_CONFLICT|managed-paragraph='+$paragraph)
            }
        }
        $migrated=''
        if($grant.Count){
            $nl=if($old.Contains("`r`n")){"`r`n"}else{"`n"}
            $migrated=$nl+$nl+'<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->'+$nl+'## 项目工作约定（用户拥有）'+$nl+$nl+[string]::Join($nl+$nl,$grant)+$nl+'<!-- AI-WORKSPACE-USER-DECISION:END -->'
        }
        return ConvertTo-AiwAgentsUserRegions ($Text.Substring(0,$first)+$block+$migrated+$Text.Substring($last))
    }
    if($RouterSkillName.Length-gt64-or$RouterSkillName-cnotmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'){throw 'AGENTS_ROUTER_NAME_REQUIRED'}
    $template=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($TemplatePath))
    $block=(Get-AiwAgentsTemplateBlock $template).TrimEnd("`n")
    $routerToken='{{ROUTER_SKILL_NAME}}'
    $tokenCount=[regex]::Matches($block,[regex]::Escape($routerToken)).Count
    if($tokenCount-eq1){$block=$block.Replace($routerToken,$RouterSkillName)}
    elseif($tokenCount-ne0-or-not$block.Contains('`'+$RouterSkillName+'`')){throw 'AGENTS_ROUTER_TEMPLATE_MISMATCH'}
    $begin='<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->';$end='<!-- AI-WORKSPACE-FRAMEWORK:END -->'
    $starts=[regex]::Matches($Text,[regex]::Escape($begin)).Count;$ends=[regex]::Matches($Text,[regex]::Escape($end)).Count
    if($starts-eq0-and$ends-eq0){$separator=if($Text.Length-eq0){''}elseif($Text.EndsWith("`n")){"`n"}else{"`n`n"};$Text=$Text+$separator+$block+"`n"}
    elseif($starts-eq1-and$ends-eq1-and$Text.IndexOf($begin)-lt$Text.IndexOf($end)){$first=$Text.IndexOf($begin);$last=$Text.IndexOf($end)+$end.Length;$Text=$Text.Substring(0,$first)+$block+$Text.Substring($last)}
    else{throw 'AGENTS_MANAGED_MARKERS_MALFORMED'}
    return $Text
}
Export-ModuleMember -Function Get-AiwStandingDelegationProjection,Get-AiwAgentsTemplateBlock
