Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8Strict = [Text.UTF8Encoding]::new($false,$true)
$script:Utf8NoBom = [Text.UTF8Encoding]::new($false)

function Read-AiwStrictText([string]$Path,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label}_MISSING" }
    if(((Get-Item -LiteralPath $Path -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "${Label}_REPARSE"}
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw "${Label}_BOM"}
    try{$text=$script:Utf8Strict.GetString($bytes)}catch{throw "${Label}_UTF8"}
    if($text.Contains([char]0)-or$text.Contains([char]0xFFFD)-or$text.Contains("`r")-or-not$text.EndsWith("`n")){throw "${Label}_TEXT_FORMAT"}
    return $text
}

function Assert-AiwExactFields($Object,[string[]]$Expected,[string]$Label) {
    if(-not($Object-is[pscustomobject])){throw "${Label}_TYPE"}
    $actual=@($Object.PSObject.Properties.Name)
    if($actual.Count-ne$Expected.Count-or@($Expected|Where-Object{$_-cnotin$actual}).Count-ne0){throw "${Label}_FIELDS"}
}

function Assert-AiwNoDuplicateJsonMembers($Element) {
    if($Element.ValueKind-eq[Text.Json.JsonValueKind]::Object){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($property in $Element.EnumerateObject()){if(-not$seen.Add([string]$property.Name)){throw ('MAINTENANCE_OVERLAY_DUPLICATE_MEMBER|'+[string]$property.Name)};Assert-AiwNoDuplicateJsonMembers $property.Value}
    }elseif($Element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($item in $Element.EnumerateArray()){Assert-AiwNoDuplicateJsonMembers $item}}
}

function Assert-AiwStrictJson([string]$Text) {
    $options=[Text.Json.JsonDocumentOptions]::new();$options.AllowTrailingCommas=$false;$options.CommentHandling=[Text.Json.JsonCommentHandling]::Disallow
    try{$document=[Text.Json.JsonDocument]::Parse($Text,$options)}catch{throw 'MAINTENANCE_OVERLAY_JSON'}
    try{Assert-AiwNoDuplicateJsonMembers $document.RootElement}finally{$document.Dispose()}
}

function ConvertTo-AiwSafeRelativePath([string]$Value,[string]$Label) {
    if([string]::IsNullOrWhiteSpace($Value)-or$Value-cne$Value.Trim()){throw "${Label}_EMPTY_OR_WHITESPACE"}
    $path=$Value.Replace('\','/')
    if([regex]::IsMatch($path,'[<>"|?*]')-or[IO.Path]::IsPathRooted($path)-or$path.StartsWith('/')-or$path.Contains(':')){throw "${Label}_ROOTED_OR_META"}
    if(-not[string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)){throw "${Label}_NOT_NFC"}
    foreach($part in $path.Split('/')){
        if([string]::IsNullOrEmpty($part)-or$part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or[regex]::IsMatch($part,'[\x00-\x1F]')){throw "${Label}_COMPONENT"}
        if($part.Split('.')[0]-match'^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw "${Label}_RESERVED"}
    }
    return [string]::Join('/',$path.Split('/'))
}

function ConvertTo-AiwSafeSibling([string]$Value) {
    $value=ConvertTo-AiwSafeRelativePath $Value 'TARGET_SIBLING'
    if($value.Contains('/')){throw 'TARGET_SIBLING_NOT_SINGLE_COMPONENT'}
    return $value
}

function ConvertTo-AiwRoutinePaths([string[]]$Values,[string]$Label) {
    $result=New-Object 'System.Collections.Generic.List[string]'
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in @($Values)){
        $path=ConvertTo-AiwSafeRelativePath ([string]$entry) $Label
        if(-not$seen.Add($path)){throw "${Label}_DUPLICATE"}
        $result.Add($path)
    }
    return @($result)
}

function Assert-AiwNoReparse([string]$Path,[string]$Label) {
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){throw "${Label}_MISSING"}
    if(((Get-Item -LiteralPath $Path -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "${Label}_REPARSE"}
}

function Get-AiwGitTop([string]$Path,[string]$Label) {
    foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR')){if(-not[string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name,'Process'))){throw ('GIT_ENVIRONMENT_OVERRIDE_'+$name)}}
    Assert-AiwNoReparse $Path $Label
    $output=@(& git -C $Path rev-parse --show-toplevel 2>$null)
    if($LASTEXITCODE-ne0-or$output.Count-ne1){throw "${Label}_GIT_TOP_UNAVAILABLE"}
    $top=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$output[0]))
    $resolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath))
    if($top-cne$resolved){throw "${Label}_NOT_GIT_TOP"}
    Assert-AiwNoReparse $top $Label
    return $top
}

function Get-AiwMaintenanceOverlay {
    [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$FrameworkWorkspace)
    $workspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FrameworkWorkspace).ProviderPath))
    $root=Join-Path $workspace 'framework\maintenance-overlay'
    Assert-AiwNoReparse $root 'MAINTENANCE_OVERLAY_ROOT'
    $manifestPath=Join-Path $root 'OVERLAY.json';$raw=Read-AiwStrictText $manifestPath 'MAINTENANCE_OVERLAY'
    Assert-AiwStrictJson $raw
    try{$overlay=$raw|ConvertFrom-Json}catch{throw 'MAINTENANCE_OVERLAY_JSON'}
    Assert-AiwExactFields $overlay @('schemaVersion','overlayId','baseStarter','controlPlaneLayout','targetControlPlanePolicy','managedTemplates') 'MAINTENANCE_OVERLAY'
    Assert-AiwExactFields $overlay.managedTemplates @('bootstrap','agents','projectConfigSchema','processPolicy') 'MAINTENANCE_OVERLAY_TEMPLATES'
    if([int]$overlay.schemaVersion-ne2-or[string]$overlay.overlayId-cne'framework-maintenance-sibling'-or[string]$overlay.baseStarter-cne'project-starter'-or[string]$overlay.controlPlaneLayout-cne'framework-maintenance-sibling'-or[string]$overlay.targetControlPlanePolicy-cne'ABSENT'-or[string]$overlay.managedTemplates.bootstrap-cne'BOOTSTRAP.md'-or[string]$overlay.managedTemplates.agents-cne'AGENTS.md'-or[string]$overlay.managedTemplates.projectConfigSchema-cne'PROJECT_CONFIG_SCHEMA.json'-or[string]$overlay.managedTemplates.processPolicy-cne'process-policy.json'){throw 'MAINTENANCE_OVERLAY_VALUES'}
    $bootstrap=Join-Path $root ([string]$overlay.managedTemplates.bootstrap);$agents=Join-Path $root ([string]$overlay.managedTemplates.agents);$schema=Join-Path $root ([string]$overlay.managedTemplates.projectConfigSchema);$policy=Join-Path $root ([string]$overlay.managedTemplates.processPolicy)
    $null=Read-AiwStrictText $bootstrap 'MAINTENANCE_OVERLAY_BOOTSTRAP';$null=Read-AiwStrictText $agents 'MAINTENANCE_OVERLAY_AGENTS';$null=Read-AiwStrictText $schema 'MAINTENANCE_OVERLAY_PROJECT_CONFIG_SCHEMA';$null=Read-AiwStrictText $policy 'MAINTENANCE_OVERLAY_PROCESS_POLICY'
    return [pscustomobject]@{Root=$root;Manifest=$overlay;BootstrapPath=$bootstrap;AgentsPath=$agents;ProjectConfigSchemaPath=$schema;ProcessPolicyPath=$policy}
}

function New-AiwMaintenanceProjectConfig {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][string]$ProjectId,
        [Parameter(Mandatory=$true)][string]$DisplayName,
        [Parameter(Mandatory=$true)][string]$FrameworkVersion,
        [Parameter(Mandatory=$true)][string]$TargetRepositoryId,
        [Parameter(Mandatory=$true)][string]$TargetSiblingDirectory,
        [string[]]$ControlRoutineExcludedPaths=@(),
        [string[]]$TargetRoutineExcludedPaths=@()
    )
    if($ProjectId-cnotmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'-or[string]::IsNullOrWhiteSpace($DisplayName)-or$FrameworkVersion-cnotmatch'^\d+\.\d+\.\d+$'){throw 'MAINTENANCE_PROJECT_IDENTITY'}
    if($TargetRepositoryId-cnotmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'-or$TargetRepositoryId-ceq'CONTROL'){throw 'TARGET_REPOSITORY_ID'}
    $sibling=ConvertTo-AiwSafeSibling $TargetSiblingDirectory
    $controlPaths=@(ConvertTo-AiwRoutinePaths $ControlRoutineExcludedPaths 'CONTROL_ROUTINE_PATH')
    $targetPaths=@(ConvertTo-AiwRoutinePaths $TargetRoutineExcludedPaths 'TARGET_ROUTINE_PATH')
    $config=[ordered]@{schemaVersion=4;id=$ProjectId;displayName=$DisplayName;controlPlaneLayout='framework-maintenance-sibling';repositoryRoot='..';frameworkVersion=$FrameworkVersion;frameworkToolBackend='powershell7';routineExcludedPaths=$controlPaths;frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'};frameworkTarget=[ordered]@{repositoryId=$TargetRepositoryId;siblingDirectory=$sibling;routineExcludedPaths=$targetPaths}}
    return (($config|ConvertTo-Json -Depth 20)+"`n")
}

function Resolve-AiwMaintenanceTopology {
    [CmdletBinding()]param(
        [Parameter(Mandatory=$true)][string]$ControlRepositoryPath,
        [Parameter(Mandatory=$true)][string]$TargetRepositoryId,
        [Parameter(Mandatory=$true)][string]$TargetSiblingDirectory,
        [string[]]$TargetRoutineExcludedPaths=@()
    )
    if($TargetRepositoryId-cnotmatch'^[a-z0-9]+(?:-[a-z0-9]+)*$'-or$TargetRepositoryId-ceq'CONTROL'){throw 'TARGET_REPOSITORY_ID'}
    $sibling=ConvertTo-AiwSafeSibling $TargetSiblingDirectory
    $paths=@(ConvertTo-AiwRoutinePaths $TargetRoutineExcludedPaths 'TARGET_ROUTINE_PATH')
    $control=Get-AiwGitTop ([IO.Path]::GetFullPath($ControlRepositoryPath)) 'CONTROL_ROOT'
    $parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Split-Path -Parent $control)))
    Assert-AiwNoReparse $parent 'WORKSPACE_PARENT'
    if(Test-Path -LiteralPath (Join-Path $parent '.git')){throw 'WORKSPACE_PARENT_GIT_FORBIDDEN'}
    if(Test-Path -LiteralPath (Join-Path $parent '.ai-workspace')){throw 'WORKSPACE_PARENT_CONTROL_FORBIDDEN'}
    $targetCandidate=Join-Path $parent $sibling
    $target=Get-AiwGitTop $targetCandidate 'TARGET_ROOT'
    if($control-ceq$target){throw 'CONTROL_TARGET_GIT_TOP_CONFLICT'}
    if((Split-Path -Parent $target)-cne$parent-or(Split-Path -Leaf $target)-cne$sibling){throw 'TARGET_SIBLING_CASE_OR_LOCATION'}
    $targetControlPath=Join-Path $target '.ai-workspace'
    $targetControlItem=Get-Item -LiteralPath $targetControlPath -Force -ErrorAction SilentlyContinue
    if($null-ne$targetControlItem){
        if(($targetControlItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'TARGET_CONTROL_PLANE_REPARSE'}
        throw 'TARGET_CONTROL_PLANE_FORBIDDEN'
    }
    return [pscustomobject]@{ControlRoot=$control;TargetRoot=$target;ParentRoot=$parent;TargetRepositoryId=$TargetRepositoryId;TargetSiblingDirectory=$sibling;TargetRoutineExcludedPaths=$paths}
}

Export-ModuleMember -Function Get-AiwMaintenanceOverlay,New-AiwMaintenanceProjectConfig,Resolve-AiwMaintenanceTopology
