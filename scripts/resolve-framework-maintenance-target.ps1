[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ControlRepositoryPath,
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [switch]$AsJson
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
$utf8=[Text.UTF8Encoding]::new($false,$true)

function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Test-Integer($Value){return $Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]}
function Assert-Fields($Object,[string[]]$Expected,[string]$Label){if(-not($Object-is[pscustomobject])){throw "${Label}_TYPE"};$actual=@($Object.PSObject.Properties.Name);if($actual.Count-ne$Expected.Count-or@($Expected|Where-Object{$_-cnotin$actual}).Count-ne0){throw "${Label}_FIELDS"}}
function Assert-NoDuplicate($Element){if($Element.ValueKind-eq[Text.Json.JsonValueKind]::Object){$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($property in $Element.EnumerateObject()){if(-not$seen.Add([string]$property.Name)){throw ('JSON_DUPLICATE_MEMBER|'+[string]$property.Name)};Assert-NoDuplicate $property.Value}}elseif($Element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($item in $Element.EnumerateArray()){Assert-NoDuplicate $item}}}
function Read-Json([string]$Path,[string]$Label){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "${Label}_MISSING"};if(((Get-Item -LiteralPath $Path -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "${Label}_REPARSE"};$bytes=[IO.File]::ReadAllBytes($Path);if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw "${Label}_BOM"};try{$text=$utf8.GetString($bytes)}catch{throw "${Label}_UTF8"};if($text.Contains("`r")-or$text.Contains([char]0)-or$text.Contains([char]0xFFFD)-or-not$text.EndsWith("`n")){throw "${Label}_TEXT_FORMAT"};$options=[Text.Json.JsonDocumentOptions]::new();$options.AllowTrailingCommas=$false;$options.CommentHandling=[Text.Json.JsonCommentHandling]::Disallow;try{$doc=[Text.Json.JsonDocument]::Parse($text,$options)}catch{throw "${Label}_JSON"};try{Assert-NoDuplicate $doc.RootElement}finally{$doc.Dispose()};try{return $text|ConvertFrom-Json -Depth 50}catch{throw "${Label}_JSON"}}
function Assert-ControlPathWithoutReparse([string]$Root,[string]$RelativePath,[string]$Label){$current=$Root;$walked='';foreach($part in $RelativePath.Replace('\','/').Split('/')){$walked=if([string]::IsNullOrEmpty($walked)){$part}else{$walked+'/'+$part};$current=Join-Path $current $part;$item=Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue;if($null-eq$item){return};if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw ($Label+'|'+$walked)}}}
function Assert-TargetPathWithoutReparse([string]$Root,[string]$RelativePath){$current=$Root;$walked='';foreach($part in $RelativePath.Replace('\','/').Split('/')){$walked=if([string]::IsNullOrEmpty($walked)){$part}else{$walked+'/'+$part};$current=Join-Path $current $part;$item=Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue;if($null-eq$item){return};if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw ('TARGET_REQUIRED_FILE_REPARSE|'+$walked)}}}

try{
    $frameworkWorkspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)))
    Import-Module (Join-Path $PSScriptRoot 'MaintenanceOverlay.psm1') -Force
    $overlay=Get-AiwMaintenanceOverlay -FrameworkWorkspace $frameworkWorkspace
    $control=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ControlRepositoryPath)))
    Assert-ControlPathWithoutReparse $control '.ai-workspace/project.json' 'PROJECT_CONFIG_REPARSE'
    $configPath=Join-Path $control '.ai-workspace/project.json'
    if((Get-Identity $configPath)-cne$ExpectedProjectConfigIdentity){throw 'PROJECT_CONFIG_DRIFT'}
    $config=Read-Json $configPath 'PROJECT_CONFIG'
    Assert-Fields $config @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy','frameworkTarget') 'PROJECT_CONFIG'
    Assert-Fields $config.processPolicy @('schemaVersion','locator') 'PROCESS_POLICY_LOCATOR'
    Assert-Fields $config.frameworkTarget @('repositoryId','siblingDirectory','routineExcludedPaths') 'FRAMEWORK_TARGET'
    if(-not(Test-Integer $config.schemaVersion)-or[int]$config.schemaVersion-ne4-or[string]$config.id-cnotmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'-or[string]::IsNullOrWhiteSpace([string]$config.displayName)-or[string]$config.controlPlaneLayout-cne'framework-maintenance-sibling'-or[string]$config.repositoryRoot-cne'..'-or[string]$config.frameworkVersion-cnotmatch'^\d+\.\d+\.\d+$'-or[string]$config.frameworkToolBackend-cne'powershell7'-or-not($config.routineExcludedPaths-is[Array])-or@($config.frameworkCapabilities.PSObject.Properties).Count-ne0-or[int]$config.processPolicy.schemaVersion-ne1-or[string]$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'-or-not($config.frameworkTarget.routineExcludedPaths-is[Array])){throw 'PROJECT_CONFIG_VALUES'}
    $topology=Resolve-AiwMaintenanceTopology -ControlRepositoryPath $control -TargetRepositoryId ([string]$config.frameworkTarget.repositoryId) -TargetSiblingDirectory ([string]$config.frameworkTarget.siblingDirectory) -TargetRoutineExcludedPaths @($config.frameworkTarget.routineExcludedPaths)
    Assert-ControlPathWithoutReparse $control '.ai-workspace/process-policy.json' 'PROCESS_POLICY_REPARSE';$policyPath=Join-Path $control '.ai-workspace/process-policy.json';$policy=Read-Json $policyPath 'PROCESS_POLICY'
    Assert-Fields $policy @('schemaVersion','contractVersion','projectId','selectedRulePackBytes','rules') 'PROCESS_POLICY'
    if(-not(Test-Integer $policy.schemaVersion)-or[int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne[string]$config.frameworkVersion-or[string]$policy.projectId-cne[string]$config.id-or-not(Test-Integer $policy.selectedRulePackBytes)-or[int64]$policy.selectedRulePackBytes-lt1-or-not($policy.rules-is[Array])-or@($policy.rules|Where-Object{[string]$_.ruleId-ceq'FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY'}).Count-ne1){throw 'PROCESS_POLICY_VALUES'}
    Assert-ControlPathWithoutReparse $control '.ai-workspace/controller.json' 'CONTROLLER_REPARSE';$controllerPath=Join-Path $control '.ai-workspace/controller.json';$controller=Read-Json $controllerPath 'CONTROLLER'
    Assert-Fields $controller @('schemaVersion','projectId','controllerId','controllerEpoch','state') 'CONTROLLER'
    if(-not(Test-Integer $controller.schemaVersion)-or[int]$controller.schemaVersion-ne1-or[string]$controller.projectId-cne[string]$config.id-or[string]::IsNullOrWhiteSpace([string]$controller.controllerId)-or-not(Test-Integer $controller.controllerEpoch)-or[int64]$controller.controllerEpoch-lt1-or[string]$controller.state-cne'CURRENT'){throw 'CONTROLLER_VALUES'}
    $versionRoot=Join-Path $topology.TargetRoot ('framework\versions\'+[string]$config.frameworkVersion)
    foreach($required in @('VERSION.json','RELEASE_MANIFEST.json','RECOVERY_CORE.md','LOAD_MANIFEST.json','TOOLCHAIN.json','scripts/resolve-process-requirements.ps1','scripts/check-authorization.ps1')){$relative='framework/versions/'+[string]$config.frameworkVersion+'/'+$required.Replace('\','/');Assert-TargetPathWithoutReparse $topology.TargetRoot $relative;if(-not(Test-Path -LiteralPath (Join-Path $versionRoot $required) -PathType Leaf)){throw ('TARGET_VERSION_FILE_MISSING|'+$required)}}
    foreach($required in @('README.md','AGENTS.md','scripts/resolve-framework-maintenance-target.ps1','scripts/check-framework-maintenance-authorization.ps1','scripts/invoke-framework-maintenance-safe-git.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1')){Assert-TargetPathWithoutReparse $topology.TargetRoot $required.Replace('\','/');if(-not(Test-Path -LiteralPath (Join-Path $topology.TargetRoot $required) -PathType Leaf)){throw ('TARGET_ROOT_FILE_MISSING|'+$required)}}
    $result=[ordered]@{status='PASS';layout='framework-maintenance-sibling';projectId=[string]$config.id;frameworkVersion=[string]$config.frameworkVersion;projectConfigIdentity=$ExpectedProjectConfigIdentity;controlRepositoryId='CONTROL';controlRoot=$topology.ControlRoot;targetRepositoryId=$topology.TargetRepositoryId;targetRoot=$topology.TargetRoot;controllerId=[string]$controller.controllerId;controllerEpoch=[int64]$controller.controllerEpoch;controllerState=[string]$controller.state}
    if($AsJson){$result|ConvertTo-Json -Depth 5 -Compress}else{Write-Output ('PASS|framework-maintenance-target|project='+$result.projectId+'|control=CONTROL|target='+$result.targetRepositoryId+'|controllerState='+$result.controllerState)}
    exit 0
}catch{if($AsJson){[ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|framework-maintenance-target|'+[string]$_.Exception.Message)};exit 2}
