[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ControlRepositoryPath,
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [switch]$AsJson
)
# @project-source-entry-scope
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
$aiwPublicationScopeLease=$null
try {
$aiwPublicationEntryRoot=$ControlRepositoryPath
if($aiwPublicationEntryRoot){$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot ([IO.Path]::GetFullPath($aiwPublicationEntryRoot,$PWD.ProviderPath)) -Mode OBSERVE}


$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
$utf8=[Text.UTF8Encoding]::new($false,$true)

function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Test-Integer($Value){return $Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]}
function Assert-Fields($Object,[string[]]$Expected,[string]$Label){if(-not($Object-is[pscustomobject])){throw "${Label}_TYPE"};$actual=@($Object.PSObject.Properties.Name);if($actual.Count-ne$Expected.Count-or@($Expected|Where-Object{$_-cnotin$actual}).Count-ne0){throw "${Label}_FIELDS"}}
function Assert-NoDuplicate($Element){if($Element.ValueKind-eq[Text.Json.JsonValueKind]::Object){$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($property in $Element.EnumerateObject()){if(-not$seen.Add([string]$property.Name)){throw ('JSON_DUPLICATE_MEMBER|'+[string]$property.Name)};Assert-NoDuplicate $property.Value}}elseif($Element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($item in $Element.EnumerateArray()){Assert-NoDuplicate $item}}}
function Read-Json([string]$Path,[string]$Label){
    try{return (Read-AiwProjectJson -Path $Path -Label $Label).Value}
    catch{
        if($_.Exception.Message.StartsWith($Label+'_DUPLICATE_MEMBER|')-and$_.Exception.Data.Contains('AiwJsonDuplicateMember')){
            throw ('JSON_DUPLICATE_MEMBER|'+[string]$_.Exception.Data['AiwJsonDuplicateMember'])
        }
        throw
    }
}
function Assert-ControlPathWithoutReparse([string]$Root,[string]$RelativePath,[string]$Label){$current=$Root;$walked='';foreach($part in $RelativePath.Replace('\','/').Split('/')){$walked=if([string]::IsNullOrEmpty($walked)){$part}else{$walked+'/'+$part};$current=Join-Path $current $part;$item=Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue;if($null-eq$item){return};if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw ($Label+'|'+$walked)}}}
function Assert-TargetPathWithoutReparse([string]$Root,[string]$RelativePath){$current=$Root;$walked='';foreach($part in $RelativePath.Replace('\','/').Split('/')){$walked=if([string]::IsNullOrEmpty($walked)){$part}else{$walked+'/'+$part};$current=Join-Path $current $part;$item=Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue;if($null-eq$item){return};if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw ('TARGET_REQUIRED_FILE_REPARSE|'+$walked)}}}

try{
    $frameworkWorkspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)))
    Import-Module (Join-Path $PSScriptRoot 'MaintenanceOverlay.psm1') -Force
    # Daily topology uses the actual overlay module, not unused install templates.
    $control=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ControlRepositoryPath)))
    Assert-ControlPathWithoutReparse $control '.ai-workspace/project.json' 'PROJECT_CONFIG_REPARSE'
    $configPath=Join-Path $control '.ai-workspace/project.json'
    if((Get-Identity $configPath)-cne$ExpectedProjectConfigIdentity){throw 'PROJECT_CONFIG_DRIFT'}
    $config=Read-Json $configPath 'PROJECT_CONFIG'
    $configFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy','frameworkTarget')
    if($config.schemaVersion-in@(6,7)){$configFields+='sourceBindings'}
    Assert-Fields $config $configFields 'PROJECT_CONFIG'
    Assert-Fields $config.processPolicy @('schemaVersion','locator') 'PROCESS_POLICY_LOCATOR'
    Assert-Fields $config.frameworkTarget @('repositoryId','siblingDirectory','routineExcludedPaths') 'FRAMEWORK_TARGET'
    $policySchema=if($config.schemaVersion-eq7){3}elseif($config.schemaVersion-eq6){2}else{1}
    if(-not(Test-Integer $config.schemaVersion)-or[int]$config.schemaVersion-notin@(4,5,6,7)-or[string]$config.id-cnotmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'-or[string]::IsNullOrWhiteSpace([string]$config.displayName)-or[string]$config.controlPlaneLayout-cne'framework-maintenance-sibling'-or[string]$config.repositoryRoot-cne'..'-or[string]$config.frameworkVersion-cnotmatch'^\d+\.\d+\.\d+$'-or[string]$config.frameworkToolBackend-cne'powershell7'-or-not($config.routineExcludedPaths-is[Array])-or-not($config.frameworkCapabilities-is[pscustomobject])-or([int]$config.schemaVersion-eq4-and@($config.frameworkCapabilities.PSObject.Properties).Count-ne0)-or[int]$config.processPolicy.schemaVersion-ne$policySchema-or[string]$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'-or-not($config.frameworkTarget.routineExcludedPaths-is[Array])){throw 'PROJECT_CONFIG_VALUES'}
    $topology=Resolve-AiwMaintenanceTopology -ControlRepositoryPath $control -TargetRepositoryId ([string]$config.frameworkTarget.repositoryId) -TargetSiblingDirectory ([string]$config.frameworkTarget.siblingDirectory) -TargetRoutineExcludedPaths @($config.frameworkTarget.routineExcludedPaths)
    Assert-ControlPathWithoutReparse $control '.ai-workspace/process-policy.json' 'PROCESS_POLICY_REPARSE';$policyPath=Join-Path $control '.ai-workspace/process-policy.json';$policy=Read-Json $policyPath 'PROCESS_POLICY'
    $policyFields=@('schemaVersion','contractVersion','projectId','rules');if($policySchema-eq1){$policyFields+='selectedRulePackBytes'};if($null-ne$policy.PSObject.Properties['facetVocabulary']){$policyFields+='facetVocabulary'}
    if($null-ne$policy.PSObject.Properties['qualityAssurance']){if($policySchema-ne3){throw 'QUALITY_POLICY_SCHEMA'};$policyFields+='qualityAssurance'}
    Assert-Fields $policy $policyFields 'PROCESS_POLICY'
    if($null-ne$policy.PSObject.Properties['qualityAssurance']-or@($policy.rules|Where-Object{$null-ne$_.PSObject.Properties['qualityStages']}).Count){
        if($policySchema-ne3){throw 'QUALITY_POLICY_SCHEMA'}
        $policySchemaPath=Join-Path $frameworkWorkspace ('framework/versions/'+[string]$config.frameworkVersion+'/PROCESS_POLICY_SCHEMA.json')
        if(-not(Test-Json -Json ($policy|ConvertTo-Json -Depth 100 -Compress) -SchemaFile $policySchemaPath -ErrorAction SilentlyContinue)){throw 'PROCESS_POLICY_QUALITY_INVALID'}
        if($null-ne$policy.PSObject.Properties['qualityAssurance']-and-not(Test-Integer $policy.qualityAssurance.schemaVersion)){throw 'PROCESS_POLICY_QUALITY_INVALID'}
    }
    if(-not(Test-Integer $policy.schemaVersion)-or[int]$policy.schemaVersion-ne$policySchema-or[string]$policy.contractVersion-cne[string]$config.frameworkVersion-or[string]$policy.projectId-cne[string]$config.id-or($policySchema-eq1-and(-not(Test-Integer $policy.selectedRulePackBytes)-or[int64]$policy.selectedRulePackBytes-lt1))-or-not($policy.rules-is[Array])-or@($policy.rules|Where-Object{[string]$_.ruleId-ceq'FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY'}).Count-ne1){throw 'PROCESS_POLICY_VALUES'}
    Assert-ControlPathWithoutReparse $control '.ai-workspace/controller.json' 'CONTROLLER_REPARSE';$controllerPath=Join-Path $control '.ai-workspace/controller.json';$controller=Read-Json $controllerPath 'CONTROLLER'
    Assert-Fields $controller @('schemaVersion','projectId','controllerId','controllerEpoch','state') 'CONTROLLER'
    if(-not(Test-Integer $controller.schemaVersion)-or[int]$controller.schemaVersion-ne1-or[string]$controller.projectId-cne[string]$config.id-or[string]::IsNullOrWhiteSpace([string]$controller.controllerId)-or-not(Test-Integer $controller.controllerEpoch)-or[int64]$controller.controllerEpoch-lt1-or[string]$controller.state-cne'CURRENT'){throw 'CONTROLLER_VALUES'}
    Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
    $binding=Get-AiwAdoptedDistributionBinding $control ([string]$config.frameworkVersion)
    if($null-eq$binding){throw 'MAINTENANCE_FIXED_RUNTIME_BINDING_REQUIRED'}
    $runtimeRoot=[string]$binding.runtimeRoot
    if([string]$config.frameworkVersion-ceq'2.0.0'){
        $stateOwner=@(Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -PassThru)[0]
        $consumed=@('scripts/resolve-framework-maintenance-target.ps1','scripts/MaintenanceOverlay.psm1')
        # Only the known root entry points actually on this invocation's stack
        # are code consumers; historical register/upgrade files are not.
        foreach($relative in @('scripts/check-framework-maintenance-authorization.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1','scripts/invoke-framework-maintenance-safe-git.ps1')){
            $expected=[IO.Path]::GetFullPath((Join-Path $runtimeRoot $relative))
            if(@(Get-PSCallStack|Where-Object{$_.ScriptName-and[IO.Path]::GetFullPath($_.ScriptName)-ceq$expected}).Count){$consumed+=@($relative)}
        }
        $processSource=& $stateOwner {param($p,$r,$paths) Get-AiwFixedAdoptedProcessSource -ProjectRoot $p -FrameworkRoot $r -ConsumedPaths $paths} $control $runtimeRoot $consumed
        if($null-eq$processSource){$null=Assert-AiwDistributionBinding $binding $runtimeRoot ([string]$config.frameworkVersion)}
    }else{$null=Assert-AiwDistributionBinding $binding $runtimeRoot ([string]$config.frameworkVersion)}
    $versionRoot=Join-Path $runtimeRoot ('framework\versions\'+[string]$config.frameworkVersion)
    foreach($required in @('VERSION.json','RELEASE_MANIFEST.json','RECOVERY_CORE.md','LOAD_MANIFEST.json','TOOLCHAIN.json','scripts/resolve-process-requirements.ps1','scripts/check-authorization.ps1')){$relative='framework/versions/'+[string]$config.frameworkVersion+'/'+$required.Replace('\','/');Assert-TargetPathWithoutReparse $runtimeRoot $relative;if(-not(Test-Path -LiteralPath (Join-Path $versionRoot $required) -PathType Leaf)){throw ('TARGET_VERSION_FILE_MISSING|'+$required)}}
    $requiredRootFiles=@('README.md','scripts/resolve-framework-maintenance-target.ps1','scripts/check-framework-maintenance-authorization.ps1','scripts/invoke-framework-maintenance-safe-git.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1')
    # Packaged entry comes from the package template; the development source has no host entry.
    if($null-ne$binding){$requiredRootFiles+= 'AGENTS.md'}
    foreach($required in $requiredRootFiles){Assert-TargetPathWithoutReparse $runtimeRoot $required.Replace('\','/');if(-not(Test-Path -LiteralPath (Join-Path $runtimeRoot $required) -PathType Leaf)){throw ('TARGET_ROOT_FILE_MISSING|'+$required)}}
    Assert-TargetPathWithoutReparse $runtimeRoot ('framework/versions/'+[string]$config.frameworkVersion+'/ADOPTION_PROFILE.json')
    $profile=Read-Json (Join-Path $versionRoot 'ADOPTION_PROFILE.json') 'ADOPTION_PROFILE'
    if([int]$profile.projectControl.schemaVersion-ne[int]$config.schemaVersion-or[string]$profile.frameworkVersion-cne[string]$config.frameworkVersion){throw 'PROJECT_CONFIG_PIN_SCHEMA_MISMATCH'}
    if([int]$config.schemaVersion-in@(5,6,7)){
        foreach($required in @('scripts/KnowledgeSources.psm1','scripts/StrictJsonInput.psm1')){Assert-TargetPathWithoutReparse $runtimeRoot ('framework/versions/'+[string]$config.frameworkVersion+'/'+$required)}
        $validator=Import-Module (Join-Path $versionRoot 'scripts/KnowledgeSources.psm1') -PassThru
        $null=& $validator {param($value) Assert-AiwFrameworkCapabilities $value} $config.frameworkCapabilities
    }
    if($config.schemaVersion-in@(6,7)){Import-Module (Join-Path $versionRoot 'scripts/ObjectFormats.psm1');$current=Read-AiwCurrentObject -ObjectType PROJECT_CONFIG -Locator $configPath -ExpectedIdentity $ExpectedProjectConfigIdentity -Context ([pscustomobject]@{});if($current.Status-cne'CURRENT'){throw 'FORMAT_WRITE_REQUIRED|PROJECT_CONFIG'}}
    $result=[ordered]@{status='PASS';layout='framework-maintenance-sibling';projectId=[string]$config.id;frameworkVersion=[string]$config.frameworkVersion;projectConfigIdentity=$ExpectedProjectConfigIdentity;controlRepositoryId='CONTROL';controlRoot=$topology.ControlRoot;targetRepositoryId=$topology.TargetRepositoryId;targetRoot=$topology.TargetRoot;runtimeRoot=$runtimeRoot;controllerId=[string]$controller.controllerId;controllerEpoch=[int64]$controller.controllerEpoch;controllerState=[string]$controller.state}
    if($AsJson){$result|ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii}else{Write-Output ('PASS|framework-maintenance-target|project='+$result.projectId+'|control=CONTROL|target='+$result.targetRepositoryId+'|controllerState='+$result.controllerState)}
    exit 0
}catch{if($AsJson){[ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii}else{Write-Output ('FAIL|framework-maintenance-target|'+[string]$_.Exception.Message)};exit 2}

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
