Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1')
function New-AiwPrivateToolExit([int]$Code){$e=[InvalidOperationException]::new('Private tool return');$e.Data['AIW_PRIVATE_TOOL_EXIT']=$Code;return $e}
function Invoke-AiwProcessRequirementBoundary {
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson,[switch]$DeleteInputOnExit,[string]$AuthorizationCheckerPath,[string]$CompactReceiptPath,[string]$DisplayPath,
 [string[]]$ConsumedRuntimePath=@(),[string]$ConsumedRuntimePathList,[string[]]$EmptyRuntimeDirectory=@(),[string[]]$RetainedRuntimePath=@(),
 [string]$PublicationSourceInputPath,[string]$ExpectedPublicationSourceInputIdentity)
 if($PSBoundParameters.ContainsKey('PublicationSourceInputPath')-or$PSBoundParameters.ContainsKey('ExpectedPublicationSourceInputIdentity')){
  if([string]::IsNullOrWhiteSpace($PublicationSourceInputPath)-or[string]::IsNullOrWhiteSpace($ExpectedPublicationSourceInputIdentity)){
   return [pscustomobject]@{exitCode=2;output=@('{"status":"FAIL","reason":"SOURCE_PUBLICATION_PAIR_REFERENCE_REQUIRED"}')}
  }
 }
 $owner=$ExecutionContext.SessionState.Module
 $publication=@(Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1') -PassThru)[0]
 & $publication {
  param($boundaryOwner,$arguments)
  Invoke-PubClosureObservationScope -Body {
   param($boundaryOwner,$arguments)
   & $boundaryOwner {
    param($arguments)
    if($arguments.ContainsKey('PublicationSourceInputPath')){Invoke-AiwPublicationBoundaryPairCore @arguments}
    else{Invoke-AiwProcessRequirementBoundaryCore @arguments}
   } $arguments
  } -Arguments @($boundaryOwner,$arguments)
 } $owner $PSBoundParameters
}
function Invoke-AiwProcessRequirementBoundaryCore {
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson,[switch]$DeleteInputOnExit,[string]$AuthorizationCheckerPath,[string]$CompactReceiptPath,[string]$DisplayPath,
 [string[]]$ConsumedRuntimePath=@(),[string]$ConsumedRuntimePathList,[string[]]$EmptyRuntimeDirectory=@(),[string[]]$RetainedRuntimePath=@(),$PublicationContext=$null)
$outputs=[Collections.Generic.List[object]]::new();$code=0;$aiwPublicationScopeLease=$null
try {
$scopeRoot=Get-AiwPublicationInputProjectRoot $InputPath
if($scopeRoot){$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $scopeRoot}
& {


$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';throw (New-AiwPrivateToolExit (4))}
$composerModule=@(Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru)[0]
Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1')
$utf8=[Text.UTF8Encoding]::new($false,$true)

function Get-Identity([string]$Path){$b=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path));return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Get-RuntimeActorSegment([string]$Actor){
  return & $composerModule.ExportedFunctions['Get-AiwRuntimeActorStorageKey'] -Actor $Actor
}
function Save-CompactReceipt($Receipt,[string]$Path,[string]$ProjectRoot,[string]$TaskId,[string]$Actor){
  if(-not[IO.Path]::IsPathRooted($Path)){throw 'COMPACT_PATH_ABSOLUTE_REQUIRED'}
  if($TaskId-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){throw 'COMPACT_CONTEXT_UNBOUND'}
  $actorSegment=Get-RuntimeActorSegment $Actor
  $full=[IO.Path]::GetFullPath($Path)
  $expected=[IO.Path]::GetFullPath((Join-Path $ProjectRoot ('.ai-workspace/runtime/'+$TaskId+'/'+$actorSegment)))
  if([IO.Path]::GetDirectoryName($full)-cne$expected-or[IO.Path]::GetFileName($full)-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*\.json$'){throw 'COMPACT_PATH_SCOPE'}
  $cursor=Get-Item -LiteralPath $expected -Force -ErrorAction Stop
  while($null-ne$cursor){if(($cursor.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'COMPACT_PATH_REPARSE'};$cursor=$cursor.Parent}
  $bytes=$utf8.GetBytes((($Receipt|ConvertTo-Json -Depth 100 -Compress)+"`n"))
  # CreateNew refuses the input, an existing receipt, authority, or raced-in file.
  $stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  return [ordered]@{path=$full;identity=Get-Identity $full}
}
function Save-ProcessDisplay([string]$Text,[string]$Path,[string]$ProjectRoot,[string]$TaskId,[string]$Actor,[string[]]$Denied){
  if(-not[IO.Path]::IsPathFullyQualified($Path)){throw 'DISPLAY_PATH_ABSOLUTE_REQUIRED'}
  if($TaskId-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){throw 'DISPLAY_CONTEXT_UNBOUND'}
  $full=[IO.Path]::GetFullPath($Path)
  $expected=[IO.Path]::GetFullPath((Join-Path $ProjectRoot ('.ai-workspace/runtime/'+$TaskId+'/'+(Get-RuntimeActorSegment $Actor))))
  if([IO.Path]::GetDirectoryName($full)-cne$expected-or[IO.Path]::GetFileName($full)-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*\.txt$'){throw 'DISPLAY_PATH_SCOPE'}
  # The existing evidence path guard rejects excluded/protected paths before
  # metadata, including absolute exclusions, ADS and reparse ancestors.
  $context=New-AiwEvidenceContext $ProjectRoot '' '' $Denied
  $null=Resolve-AiwEvidenceObservationPath $context $full
  if(-not[IO.Directory]::Exists($expected)){throw 'DISPLAY_DIRECTORY_REQUIRED'}
  $bytes=$utf8.GetBytes($Text)
  $stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Get-SafeCleanupInput([string]$Path){
  $full=[IO.Path]::GetFullPath($Path);$temp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
  if([IO.Path]::GetExtension($full)-cne'.json'){throw 'INPUT_CLEANUP_PATH_UNSAFE'}
  $current=Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue;if($null-eq$current-or$current.PSIsContainer-or($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'INPUT_CLEANUP_PATH_UNSAFE'}
  $segments=New-Object 'System.Collections.Generic.List[string]';$parent=$current.Directory;$workspace=$null
  while($null-ne$parent){if(($parent.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'INPUT_CLEANUP_PATH_UNSAFE'};$segments.Insert(0,$parent.Name);if($parent.Name-ceq'.ai-workspace'){$workspace=$parent;break};$parent=$parent.Parent}
  if($null-ne$workspace){
    if($segments.Count-ne4-or$segments[1]-cne'runtime'-or$segments[2]-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'-or$segments[3]-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){throw 'INPUT_CLEANUP_PATH_UNSAFE'}
    return [pscustomobject]@{Path=$full;Storage='PROJECT_RUNTIME';WorkspacePath=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($workspace.FullName));TaskSegment=$segments[2];ActorSegment=$segments[3]}
  }
  if($full.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    if(-not[IO.Path]::GetFileName($full).StartsWith('aiw-',[StringComparison]::Ordinal)){throw 'INPUT_CLEANUP_PATH_UNSAFE'}
    $parent=$current.Directory
    while($null-ne$parent-and[IO.Path]::TrimEndingDirectorySeparator($parent.FullName)-cne$temp){if(($parent.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'INPUT_CLEANUP_PATH_UNSAFE'};$parent=$parent.Parent}
    if($null-eq$parent){throw 'INPUT_CLEANUP_PATH_UNSAFE'}
    return [pscustomobject]@{Path=$full;Storage='SYSTEM_TEMP_FALLBACK';WorkspacePath='';TaskSegment='';ActorSegment=''}
  }
  throw 'INPUT_CLEANUP_PATH_UNSAFE'
}
function Assert-ProjectRuntimeCleanupBinding($Observation,[string]$ProjectRoot,[string]$TaskId,[string]$Actor){
  if($null-eq$Observation-or[string]$Observation.Storage-cne'PROJECT_RUNTIME'){return}
  if([string]::IsNullOrWhiteSpace($ProjectRoot)){throw 'INPUT_RUNTIME_PROJECT_ROOT_UNBOUND'}
  try{$projectItem=Get-Item -LiteralPath $ProjectRoot -Force -ErrorAction Stop}catch{if($_.Exception.Data.Contains("AIW_PRIVATE_TOOL_EXIT")){throw};throw 'INPUT_RUNTIME_PROJECT_ROOT_UNBOUND'}
  if(-not$projectItem.PSIsContainer-or($projectItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'INPUT_RUNTIME_PROJECT_ROOT_UNBOUND'}
  $project=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($projectItem.FullName));$expectedWorkspace=Join-Path $project '.ai-workspace'
  try{$expectedWorkspaceItem=Get-Item -LiteralPath $expectedWorkspace -Force -ErrorAction Stop}catch{if($_.Exception.Data.Contains("AIW_PRIVATE_TOOL_EXIT")){throw};throw 'INPUT_RUNTIME_PROJECT_ROOT_UNBOUND'}
  if(-not$expectedWorkspaceItem.PSIsContainer-or($expectedWorkspaceItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-or[string]$Observation.WorkspacePath-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($expectedWorkspaceItem.FullName))){throw 'INPUT_RUNTIME_PROJECT_ROOT_DRIFT'}
  if([string]$Observation.TaskSegment-cne$TaskId-or[string]$Observation.ActorSegment-cne(Get-RuntimeActorSegment $Actor)){throw 'INPUT_RUNTIME_BINDING_DRIFT'}
}
function Get-ProcessBudgetContract {
  $path=Join-Path (Split-Path -Parent $PSScriptRoot) 'ADOPTION_PROFILE.json';$raw=Read-Input $path
  if((Test-JsonInteger $raw.schemaVersion)-and[int]$raw.schemaVersion-eq3){
    Import-Module (Join-Path $PSScriptRoot 'ObjectFormats.psm1') -ErrorAction Stop
    $null=Assert-AiwFormatAdoptionProfile $raw (Split-Path -Parent $PSScriptRoot) '2.0.0'
    # Contract-2 receipt fields remain compatibility observations. Profile3
    # declares no quota and must not be validated as the retired budget carrier.
    return [pscustomobject]@{defaultSelectedRulePackBytes=0;absoluteSelectedRulePackBytes=0}
  }
  Assert-Fields $raw @('schemaVersion','frameworkVersion','registrationEligible','localCandidatePilotEligible','sourceCompatibility','projectControl','processBudget')
  Assert-Fields $raw.sourceCompatibility @('projectFormats','requiredCapabilities')
  Assert-Fields $raw.projectControl @('schemaVersion','processCarrierContractVersion','frameworkToolBackend','navigationProjection','taskLastWriteRequired','capabilityBinding','runtimeArtifactRoot','runtimeGitIgnoreRule')
  Assert-Fields $raw.processBudget @('defaultSelectedRulePackBytes','absoluteSelectedRulePackBytes')
  $formats=@($raw.sourceCompatibility.projectFormats);$capabilities=@($raw.sourceCompatibility.requiredCapabilities)
  if(-not(Test-JsonInteger $raw.schemaVersion)-or[int]$raw.schemaVersion-ne2-or[string]$raw.frameworkVersion-cne'2.0.0'-or-not($raw.registrationEligible-is[bool])-or-not[bool]$raw.registrationEligible-or-not($raw.localCandidatePilotEligible-is[bool])-or-not[bool]$raw.localCandidatePilotEligible-or-not($raw.sourceCompatibility.projectFormats-is[Array])-or@($formats|Select-Object -Unique).Count-ne$formats.Count-or@($formats|Where-Object{-not($_-is[string])-or[string]$_-cnotmatch'^[a-z0-9-]+/[a-z0-9-]+$'}).Count-ne0-or-not($raw.sourceCompatibility.requiredCapabilities-is[Array])-or@($capabilities|Select-Object -Unique).Count-ne$capabilities.Count-or@($capabilities|Where-Object{-not($_-is[string])-or[string]$_-cnotmatch'^[A-Z][A-Z0-9_]*$'}).Count-ne0-or($formats.Count-eq0-and$capabilities.Count-ne0)-or[string]$raw.projectControl.processCarrierContractVersion-cne'2.0.0'-or[string]$raw.projectControl.navigationProjection-cne'ROOT_CANONICAL_SKILL_MANAGED_AGENTS'-or[string]$raw.projectControl.runtimeArtifactRoot-cne'.ai-workspace/runtime'-or[string]$raw.projectControl.runtimeGitIgnoreRule-cne'/.ai-workspace/runtime/'-or-not(Test-JsonInteger $raw.processBudget.defaultSelectedRulePackBytes)-or[int]$raw.processBudget.defaultSelectedRulePackBytes-ne32768-or-not(Test-JsonInteger $raw.processBudget.absoluteSelectedRulePackBytes)-or[int]$raw.processBudget.absoluteSelectedRulePackBytes-ne98304){throw 'ADOPTION_PROFILE_VALUES'}
  return $raw.processBudget
}
function Read-Input([string]$Path,$ReadIdentity=$null){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'INPUT_MISSING'}
  $b=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path));if($b.Length-ge3-and$b[0]-eq239-and$b[1]-eq187-and$b[2]-eq191){throw 'INPUT_BOM'}
  if($null-ne$ReadIdentity){$ReadIdentity.Value=$b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
  try{$t=$utf8.GetString($b)}catch{if($_.Exception.Data.Contains("AIW_PRIVATE_TOOL_EXIT")){throw};throw 'INPUT_UTF8'};if($t.Contains([char]0)-or$t.Contains([char]0xFFFD)){throw 'INPUT_TEXT_FORMAT'}
  $options=[Text.Json.JsonDocumentOptions]::new();$options.AllowTrailingCommas=$false;$options.CommentHandling=[Text.Json.JsonCommentHandling]::Disallow
  try{$document=[Text.Json.JsonDocument]::Parse($t,$options)}catch{if($_.Exception.Data.Contains("AIW_PRIVATE_TOOL_EXIT")){throw};throw 'INPUT_JSON'}
  try{Assert-NoDuplicateJsonMembers $document.RootElement}finally{$document.Dispose()}
  try{return $t|ConvertFrom-Json -Depth 100}catch{if($_.Exception.Data.Contains("AIW_PRIVATE_TOOL_EXIT")){throw};throw 'INPUT_JSON'}
}
function Assert-NoDuplicateJsonMembers($element){
  if($element.ValueKind-eq[Text.Json.JsonValueKind]::Object){
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($property in $element.EnumerateObject()){if(-not$seen.Add([string]$property.Name)){throw ('INPUT_FIELD_COUNT|'+[string]$property.Name)};Assert-NoDuplicateJsonMembers $property.Value}
  }elseif($element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($item in $element.EnumerateArray()){Assert-NoDuplicateJsonMembers $item}}
}
function Test-JsonInteger($v){return $v-is[byte]-or$v-is[sbyte]-or$v-is[int16]-or$v-is[uint16]-or$v-is[int32]-or$v-is[uint32]-or$v-is[int64]-or$v-is[uint64]}
function Assert-Fields($o,[string[]]$fields){if(-not($o-is[pscustomobject])){throw 'INPUT_OBJECT_TYPE'};$a=@($o.PSObject.Properties.Name);if($a.Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$a}).Count-ne0){throw 'INPUT_FIELDS'}}
function Assert-StringArray($v,[string]$name,[Nullable[int]]$MaxItems=$null,[int]$MaxItemLength=1024){if(-not($v-is[Array])){throw "INPUT_ARRAY|$name"};if($null-ne$MaxItems-and@($v).Count-gt$MaxItems){throw "INPUT_ARRAY_COUNT|$name"};$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($i in @($v)){if(-not($i-is[string])-or[string]::IsNullOrWhiteSpace([string]$i)-or([string]$i).Length-gt$MaxItemLength-or-not$seen.Add([string]$i)){throw "INPUT_ARRAY_ITEM|$name"}}}
function Assert-InputString($v,[string]$name){if(-not($v-is[string])-or[string]::IsNullOrWhiteSpace([string]$v)){throw "INPUT_STRING|$name"}}
function Assert-ActionAndResult([string]$action,[string]$result){if($action-cnotin@('NONE','CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')){throw 'ACTION_KIND'};if($result-cnotin@('NONE','PLAN','USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','RESULT_ACCEPTANCE','IMPLEMENTATION_RESULT','TEST_RESULT','GIT_RESULT','EXTERNAL_RESULT')){throw 'RESULT_KIND'};if($result-ceq'RESULT_ACCEPTANCE'-and$action-cne'RESULT_ACCEPT'){throw 'RESULT_ACCEPT_ACTION_REQUIRED'}}
function Assert-ExactPaths($paths){Assert-StringArray $paths 'exactPaths' $null 512;foreach($path in @($paths)){if([string]$path-cne([string]$path).Replace('\','/')-or[IO.Path]::IsPathRooted([string]$path)-or([string]$path).Contains(':')){throw 'EXACT_PATH'};foreach($part in ([string]$path).Split('/')){if([string]::IsNullOrWhiteSpace($part)-or$part-in@('.','..')){throw 'EXACT_PATH'}}}}
function Assert-PathPrefixes($paths,[string]$name,[switch]$AllowAbsolute){
  Assert-StringArray $paths $name $null 512
  foreach($path in @($paths)){
    # Literal protection is validated lexically, without stat/hash of its target.
    if($path-cne$path.Trim()-or$path.Contains('\')-or$path-match'[<>"|*?\x00-\x1f]'-or$path-cne$path.Normalize([Text.NormalizationForm]::FormC)){throw 'PATH_PREFIX'}
    $normalized=$path.TrimEnd('/')
    if($AllowAbsolute-and[IO.Path]::IsPathFullyQualified($path)){
      if($path-cne[IO.Path]::GetFullPath($path).Replace('\','/')){throw 'PATH_PREFIX'}
      $root=[IO.Path]::GetPathRoot($path).Replace('\','/');$normalized=$normalized.Substring($root.TrimEnd('/').Length).TrimStart('/')
      if(-not$normalized){continue}
    }elseif([IO.Path]::IsPathRooted($path)-or$path.Contains(':')){throw 'PATH_PREFIX'}
    foreach($part in $normalized.Split('/')){if([string]::IsNullOrWhiteSpace($part)-or$part-in@('.','..')-or$part.Contains(':')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or$part-match'(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'PATH_PREFIX'}}
  }
}
function Get-ActionEffectiveRoute($WorkRoute,[string]$Actor,[string]$ActionKind,$Package){
 if($Actor-ceq$WorkRoute.actor){
  $phase=$WorkRoute.phase
  if($ActionKind-ceq'EXTERNAL'-and$WorkRoute.role-ceq'TASK_OWNER'-and$null-ne$Package-and$Package.owner-ceq$Actor-and$Package.grantee-ceq$Actor-and$Package.issuerRole-ceq'TASK_OWNER'-and$null-ne$Package.PSObject.Properties['externalBinding']-and$Package.externalBinding.schemaVersion-eq2){$phase='EXTERNAL'}
  return [pscustomobject]@{role=$WorkRoute.role;phase=$phase}
 }
 if($ActionKind-ceq'NONE'-and$null-eq$Package){return [pscustomobject]@{role='EXECUTOR';phase='PLAN'}}
 $routes=@{NONE=@('EXECUTOR','PLAN');CONTROL_WRITE=@('EXECUTOR','IMPLEMENT');SOURCE_WRITE=@('EXECUTOR','IMPLEMENT');TEST_WRITE=@('EXECUTOR','VERIFY');TEST_RUN=@('EXECUTOR','VERIFY');REVIEW_ROUTE=@('EXECUTOR','REVIEW');REVIEW_EXECUTE=@('REVIEWER','REVIEW');RESULT_ACCEPT=@('EXECUTOR','REVIEW');GIT_STAGE=@('EXECUTOR','GIT');GIT_COMMIT=@('EXECUTOR','GIT');PUSH=@('EXECUTOR','GIT');BROWSER_RUN=@('EXECUTOR','EXTERNAL');DEVICE_RUN=@('EXECUTOR','EXTERNAL');EXTERNAL=@('EXECUTOR','EXTERNAL')}
 if($null-eq$Package-or-not$routes.ContainsKey($ActionKind)-or$Package.grantee-cne$Actor-or@($Package.actions|Where-Object{-not$routes.ContainsKey([string]$_)}).Count){throw 'TEMPORARY_ACTION_GRANTEE_DRIFT'}
 if($ActionKind-cnotin$Package.actions){throw 'ACTION_NOT_GRANTED'}
 return [pscustomobject]@{role=$routes[$ActionKind][0];phase=$routes[$ActionKind][1]}
}
function Get-OperationSelectionIdentity($Source,$Intent,$Authority,$Obligations){
 return (Get-AiwContentDescriptorIdentity ([ordered]@{source=$Source;intent=$Intent;capabilities=@($Authority.observedCapabilities);scope=@($Authority.exactScope);actor=$Authority.actor;role=$Authority.role;phase=$Authority.phase;profile=$Authority.profile;obligations=@($Obligations)})).Split('|')[1]
}

function New-ActionRebindCompact($Receipt,$Rebind,[string]$OriginalReceiptPath){
 Assert-Fields $Rebind @('authorizationRef','intentEnvelope','recoveryState')
 Assert-Fields $Rebind.authorizationRef @('path','identity')
 Assert-IntentEnvelope $Rebind.intentEnvelope
 if($Receipt.schemaVersion-ne4-or$Receipt.contextType-cne'TASK'-or$null-eq$Receipt.PSObject.Properties['sourceObservation']-or$Rebind.recoveryState-cnotin@('CURRENT','WARM')){throw 'RULE_LOAD_REQUIRED|ACTION_CONTEXT'}
 $operationV2=$Receipt.sourceObservation.schemaVersion-eq2
 $action=[string]$Rebind.intentEnvelope.requestedActionKind
 if($operationV2){
  if($action-cnotin@('SOURCE_WRITE','TEST_WRITE','CONTROL_WRITE','TEST_RUN')){throw 'RULE_LOAD_REQUIRED|ACTION_KIND'}
  if($action-ceq'TEST_RUN'-and$Receipt.actionKind-cne'TEST_RUN'){throw 'RULE_LOAD_REQUIRED|ACTIVITY_CHANGED'}
  if($Receipt.intentEnvelope.ambiguityState-cne'CLEAR'-or$Rebind.intentEnvelope.ambiguityState-cne'CLEAR'){throw 'RULE_LOAD_REQUIRED|INTENT_UNCERTAIN'}
  foreach($dimension in @('domain','workType','stage')){
   if((Get-AiwContentDescriptorIdentity $Receipt.intentEnvelope.facets.$dimension)-cne(Get-AiwContentDescriptorIdentity $Rebind.intentEnvelope.facets.$dimension)){throw 'RULE_LOAD_REQUIRED|ACTIVITY_CHANGED'}
  }
 }else{
  if($Receipt.actionKind-cnotin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN','CONTROL_WRITE')){throw 'RULE_LOAD_REQUIRED|ACTION_KIND'}
  $oldIntent=$Receipt.intentEnvelope|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30
  $newIntent=$Rebind.intentEnvelope|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30
  $oldIntent.PSObject.Properties.Remove('pathHints');$newIntent.PSObject.Properties.Remove('pathHints')
  if((Get-AiwContentDescriptorIdentity $oldIntent)-cne(Get-AiwContentDescriptorIdentity $newIntent)){throw 'RULE_LOAD_REQUIRED|INTENT_CHANGED'}
 }
 if([Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')-cne$Receipt.actor){throw 'ACTION_REBIND_HOST_ACTOR'}
 $a=$Receipt.authorityContext
 $ctx=New-AiwEvidenceContext $a.projectRoot '' $Receipt.sourceLocators.frameworkRoot @($a.forbiddenScope) @($a.protectedScope)
 $package=Read-AiwEvidenceReference $ctx $Rebind.authorizationRef -Json
 if($package.schemaVersion-notin@(1,2,4)-or$package.grantee-cne$Receipt.actor-or$package.owner-cne$Receipt.taskOwner-or$package.taskId-cne$Receipt.taskId-or$package.profile-cne$Receipt.profile-or$package.projectConfigIdentity-cne$Receipt.sourceBindings.projectConfigIdentity){throw 'ACTION_REBIND_PACKAGE_CONTEXT'}
 foreach($field in @('sourcePublicationBinding','transitionPlan','repairReviewBinding','acceptanceBinding','externalBinding','gitPushBinding')){if($null-ne$package.PSObject.Properties[$field]){throw 'RULE_LOAD_REQUIRED|SPECIAL_ACTION'}}
 $repository=if($package.schemaVersion-eq1){'PROJECT'}else{$package.repositoryId}
 if($repository-cne$a.repositoryId){
  $configuration=Read-Input (Join-Path $a.projectRoot '.ai-workspace/project.json')
  if(-not$operationV2-or$package.schemaVersion-ne2-or$a.executionContext.targetKind-cne'SAME_ROOT'-or$configuration.controlPlaneLayout-cne'framework-maintenance-sibling'-or
     $repository-cnotin@('CONTROL',$configuration.frameworkTarget.repositoryId)-or$a.repositoryId-cnotin@('CONTROL',$configuration.frameworkTarget.repositoryId)){throw 'ACTION_REBIND_REPOSITORY'}
 }
 if($package.schemaVersion-eq4-and(Get-AiwContentDescriptorIdentity $package.executionTargetRef)-cne(Get-AiwContentDescriptorIdentity $a.executionContext.executionTargetRef)){throw 'ACTION_REBIND_EXECUTION_TARGET'}
 $task=Get-TaskBindingObservation $a.projectRoot $Receipt.sourceLocators.taskRelativePath
 if($task.TaskId-cne$Receipt.taskId-or$task.Owner-cne$Receipt.taskOwner-or$task.TaskActor-cne$Receipt.taskActor-or$task.Profile-cne$Receipt.profile){throw 'ACTION_REBIND_TASK_CONTEXT'}
 $workRoute=[pscustomobject]@{actor=$task.TaskActor;role=$task.Role;phase=$task.Phase}
 $effective=Get-ActionEffectiveRoute $workRoute $Receipt.actor $action $package
 $role=$effective.role;$phase=$effective.phase
 if($operationV2){
  if((Get-AiwContentDescriptorIdentity $workRoute)-cne(Get-AiwContentDescriptorIdentity $Receipt.sourceObservation.workRoute)){throw 'RULE_LOAD_REQUIRED|WORK_ROUTE_CHANGED'}
 }elseif($role-cne$Receipt.role-or$phase-cne$Receipt.phase){throw 'RULE_LOAD_REQUIRED|ROLE_PHASE_CHANGED'}
 Assert-ExactPaths $package.exactPaths
 if(@(Get-IntentFactMismatches $Rebind.intentEnvelope @($a.observedCapabilities) @($package.exactPaths) $action).Count){throw 'ACTION_REBIND_INTENT_SCOPE'}
 # Reject protected/new scope before any candidate metadata or hash. The same
 # complete checker below still decides permission, current objects and plan.
 $candidateContext=New-AiwPackageEvidenceContext $a.projectRoot $package $Receipt.sourceLocators.frameworkRoot @($a.forbiddenScope) -TaskPath $Receipt.sourceLocators.taskRelativePath -ProtectedPaths @($a.protectedScope)
 $evidenceOwner=(Get-Command New-AiwPackageEvidenceContext).Module
 foreach($path in $package.exactPaths){$null=& $evidenceOwner {param($c,$p) Resolve-EvPath $c $p -Candidate -AllowMissing} $candidateContext $path}
 $authorization=Get-AuthorizationObservation $Rebind.authorizationRef.path $Rebind.authorizationRef.identity $Receipt.actor @($package.exactPaths) $package.userConfirmation $action $a.projectRoot $Receipt.sourceLocators.taskRelativePath $package.taskIdentity $task.TaskId $task.Owner $Receipt.sourceBindings.projectConfigIdentity 'NOT_REQUIRED' 'NOT_REQUIRED' @($a.forbiddenScope) @($a.protectedScope)
 if($package.schemaVersion-eq2-and$authorization.RepositoryId-cne$repository){throw 'ACTION_REBIND_REPOSITORY'}
 $raw=Read-Input $OriginalReceiptPath
 $raw.binding.exactScope=@($package.exactPaths);$raw.binding.taskIdentity=$package.taskIdentity
 $raw.binding.authorizationIdentity=$Rebind.authorizationRef.identity;$raw.binding.authorizedActions=@($package.actions)
 $raw.binding.userDecision=$package.userConfirmation;$raw.binding.recoveryState=$Rebind.recoveryState
 $raw.binding.role=$role;$raw.binding.phase=$phase
 $raw.binding.repositoryId=$repository;$raw.binding.objectRoot=$authorization.RepositoryRoot;$raw.binding.repositoryGitTop=$authorization.RepositoryGitTop
 foreach($field in @('continuationReceiptPath','continuationReceiptIdentity','continuationStepIndex')){$raw.binding.PSObject.Properties.Remove($field)}
 if($null-ne$package.PSObject.Properties['continuationPlan']){
  if($package.continuationPlan[0]-cne$action){throw 'RULE_LOAD_REQUIRED|CONTINUATION_ACTION'}
  $raw.binding|Add-Member continuationReceiptPath 'NOT_REQUIRED';$raw.binding|Add-Member continuationReceiptIdentity 'NOT_REQUIRED';$raw.binding|Add-Member continuationStepIndex 0
 }
 $raw.sourceBindings.taskIdentity=$package.taskIdentity;$raw.sourceObservation.bindings.taskIdentity=$package.taskIdentity
 $raw.sourceLocators.authorizationPackagePath=$Rebind.authorizationRef.path;$raw.intentEnvelope=$Rebind.intentEnvelope
 $bindings=$null
 if($operationV2){
  $selection=[pscustomobject]@{profile=$Receipt.profile;role=$role;phase=$phase;actor=$Receipt.actor;actionKind=$action;resultKind=$Rebind.intentEnvelope.requestedResultKind;exactPaths=@($package.exactPaths);capabilities=@($a.observedCapabilities);intentEnvelope=$Rebind.intentEnvelope}
  $composer=(Get-Command Get-AiwProcessBindingSnapshot).Module
  $facts=& $composer {param($p,$f,$t,$denied,$s,$o,$previous)Get-AiwProcessBindingSnapshotCore -ProjectRoot $p -FrameworkRoot $f -TargetVersion '2.0.0' -TaskRelativePath $t -ForbiddenPaths $denied -SelectionContext $s -RuleObservation $o -RequireNoBody -PreviousOperation $previous -IncludeOperationFacts} $a.projectRoot $Receipt.sourceLocators.frameworkRoot $Receipt.sourceLocators.taskRelativePath @($a.forbiddenScope) $selection $raw.sourceObservation $Receipt
  $bindings=$facts.bindings;$raw.selectedObligations=@($facts.selectedObligations)
 }
 $raw.sourceCompositionIdentity=Get-RuleSourceIdentity $raw.sourceBindings $raw.sourceObservation
 $raw.contextIdentity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes((($raw.binding|ConvertTo-Json -Depth 30 -Compress)+"`n"+($raw.intentEnvelope|ConvertTo-Json -Depth 30 -Compress)))))
 $raw.selectionIdentity=(Get-AiwContentDescriptorIdentity ([ordered]@{source=$raw.sourceCompositionIdentity;intent=$raw.intentEnvelope;scope=@($raw.binding.exactScope);actor=$Receipt.actor;role=$role;phase=$phase;profile=$Receipt.profile;obligations=@($raw.selectedObligations)})).Split('|')[1]
 if($operationV2){$raw.selectionIdentity=Get-OperationSelectionIdentity $raw.sourceCompositionIdentity $raw.intentEnvelope $raw.binding $raw.selectedObligations}
 $raw.counts.sourceBuildCount=0
 return [pscustomobject]@{compact=$raw;bindings=$bindings;authorization=$authorization}
}
function Convert-ActionRebindView($Receipt,$Raw){
 $Receipt.sourceCompositionIdentity=$Raw.sourceCompositionIdentity;$Receipt.contextIdentity=$Raw.contextIdentity;$Receipt.selectionIdentity=$Raw.selectionIdentity
 $Receipt.authorityContext=$Raw.binding;$Receipt.taskIdentity=$Raw.binding.taskIdentity;$Receipt.exactPaths=@($Raw.binding.exactScope)
 $Receipt.sourceLocators.authorizationPackagePath=$Raw.sourceLocators.authorizationPackagePath;$Receipt.intentEnvelope=$Raw.intentEnvelope
 $Receipt.sourceBindings=$Raw.sourceBindings;$Receipt.sourceObservation=$Raw.sourceObservation;$Receipt.sourceBuildCount=0
 $Receipt.objective=$Raw.intentEnvelope.objective;$Receipt.actionKind=$Raw.intentEnvelope.requestedActionKind;$Receipt.resultKind=$Raw.intentEnvelope.requestedResultKind
 $Receipt.role=$Raw.binding.role;$Receipt.phase=$Raw.binding.phase;$Receipt.selectedObligations=@($Raw.selectedObligations)
 return $Receipt
}
function Get-RuleSourceIdentity($Bindings,$Observation){
 return & $composerModule {param($bindings,$observation) Get-AiwRuleSourceIdentity $bindings $observation} $Bindings $Observation
}
function Get-Receipt([string]$Path){
  $r=Read-Input $Path
  if(-not(Test-JsonInteger $r.schemaVersion)-or[int]$r.schemaVersion-notin@(1,2,3,4)){throw 'DISCOVER_RECEIPT_TYPE'}
  if([int]$r.schemaVersion-eq1){
    Assert-Fields $r @('schemaVersion','receiptType','status','mode','inputContractVersion','sourceCompositionIdentity','selectionIdentity','contextIdentity','projectId','frameworkVersion','taskIdentity','taskId','taskOwner','taskActor','actor','role','phase','profile','objective','actionKind','resultKind','exactPaths','authorityContext','intentEnvelope','selectedObligations','selectedPackBytes','selectedPackCeilingBytes','selectedPackEstimatedTokens','sourceLocators','sourceBindings','evidenceCeilings','sourceBuildCount','legacyCorrectionsFullReadCount','legacyProjectCustomFullReadCount','hostEnforcementGrade','invocationState','authorityGranted','semanticCorrectnessProven')
    $view=$r
  }else{
    $receiptFields=@('schemaVersion','receiptType','status','mode','inputContractVersion','sourceCompositionIdentity','selectionIdentity','contextIdentity','binding','intentEnvelope','selectedObligations','pack','sourceLocators','sourceBindings','evidence','counts','authorityGranted','semanticCorrectnessProven')
    if($r.schemaVersion-eq4){$receiptFields+=@('bodyCoverage','loadDecision')}
    if($null-ne$r.PSObject.Properties['sourceObservation']){$receiptFields+='sourceObservation'}
    Assert-Fields $r $receiptFields
    if($r.schemaVersion-eq4){
      if($r.inputContractVersion-ne5-or$r.binding.schemaVersion-ne3){throw 'DISCOVER_RECEIPT_INPUT_CONTRACT'}
      Assert-Fields $r.bodyCoverage @('schemaVersion','actor','frameworkSourceIdentity','units','rules','anticipatedSteps')
      Assert-Fields $r.loadDecision @('requestedMode','effectiveMode','fallbackReason','requiredUnitKeys','returnedUnitKeys','reusedUnitKeys','anticipatedUnitKeys')
      if($r.loadDecision.effectiveMode-cnotin@('FULL','DELTA','REUSED')-or$r.bodyCoverage.actor-cne$r.binding.actor){throw 'DISCOVER_RECEIPT_COVERAGE'}
    }
    $bindingFields=@('schemaVersion','contextType','contextLocator','projectId','projectRoot','repositoryGitTop','frameworkVersion','frameworkSealIdentity','controllerIdentity','taskIdentity','taskId','taskOwner','taskActor','actor','role','phase','profile','exactScope','forbiddenScope','protectedScope','authorizationIdentity','authorizedActions','observedCapabilities','projectConfigIdentity','correctionsIdentity','policyIdentity','userDecision','recoveryState','hostEnforcementGrade')
    $continuationAuthorityFields=@('continuationReceiptPath','continuationReceiptIdentity','continuationStepIndex');$presentContinuationFields=@($continuationAuthorityFields|Where-Object{$null-ne$r.binding.PSObject.Properties[$_]})
    if($presentContinuationFields.Count-notin@(0,3)){throw 'DISCOVER_RECEIPT_CONTINUATION_FIELDS'};if($presentContinuationFields.Count-eq3){$bindingFields+=$continuationAuthorityFields}
    if($r.schemaVersion-eq4){$bindingFields+=@('controlRoot','objectRoot','repositoryId','executionContext')}
    Assert-Fields $r.binding $bindingFields
    Assert-Fields $r.pack @('bytes','ceilingBytes','estimatedTokens');Assert-Fields $r.sourceLocators @('frameworkRoot','taskRelativePath','authorizationPackagePath');Assert-Fields $r.evidence @('ceilings','invocationState');Assert-Fields $r.counts @('sourceBuildCount','legacyCorrectionsFullReadCount','legacyProjectCustomFullReadCount')
    $view=[pscustomobject][ordered]@{schemaVersion=[int]$r.schemaVersion;receiptType=$r.receiptType;status=$r.status;mode=$r.mode;inputContractVersion=$r.inputContractVersion;sourceCompositionIdentity=$r.sourceCompositionIdentity;selectionIdentity=$r.selectionIdentity;contextIdentity=$r.contextIdentity;contextType=$r.binding.contextType;projectId=$r.binding.projectId;frameworkVersion=$r.binding.frameworkVersion;taskIdentity=$r.binding.taskIdentity;taskId=$r.binding.taskId;taskOwner=$r.binding.taskOwner;taskActor=$r.binding.taskActor;actor=$r.binding.actor;role=$r.binding.role;phase=$r.binding.phase;profile=$r.binding.profile;objective=$r.intentEnvelope.objective;actionKind=$r.intentEnvelope.requestedActionKind;resultKind=$r.intentEnvelope.requestedResultKind;exactPaths=@($r.binding.exactScope);authorityContext=$r.binding;intentEnvelope=$r.intentEnvelope;selectedObligations=@($r.selectedObligations);selectedPackBytes=$r.pack.bytes;selectedPackCeilingBytes=$r.pack.ceilingBytes;selectedPackEstimatedTokens=$r.pack.estimatedTokens;sourceLocators=[pscustomobject][ordered]@{projectRoot=$r.binding.projectRoot;frameworkRoot=$r.sourceLocators.frameworkRoot;taskRelativePath=$r.sourceLocators.taskRelativePath;authorizationPackagePath=$r.sourceLocators.authorizationPackagePath};sourceBindings=$r.sourceBindings;evidenceCeilings=@($r.evidence.ceilings);sourceBuildCount=$r.counts.sourceBuildCount;legacyCorrectionsFullReadCount=$r.counts.legacyCorrectionsFullReadCount;legacyProjectCustomFullReadCount=$r.counts.legacyProjectCustomFullReadCount;hostEnforcementGrade=$r.binding.hostEnforcementGrade;invocationState=$r.evidence.invocationState;authorityGranted=$r.authorityGranted;semanticCorrectnessProven=$r.semanticCorrectnessProven}
  }
  if($null-ne$r.PSObject.Properties['sourceObservation']){
    if($r.schemaVersion-ne4-or(Get-RuleSourceIdentity $r.sourceBindings $r.sourceObservation)-cne$r.sourceCompositionIdentity-or(Get-AiwContentDescriptorIdentity $r.sourceObservation.bindings)-cne(Get-AiwContentDescriptorIdentity $r.sourceBindings)){throw 'DISCOVER_SOURCE_OBSERVATION_DRIFT'}
    $observation=$r.sourceObservation
    $fields=@('schemaVersion','selectionIdentity','bindings','nativeFiles','projectDocuments')
    if($observation.schemaVersion-eq2){
      $fields+=@('loadedRuleIds','workRoute')
      Assert-StringArray $observation.loadedRuleIds 'loadedRuleIds' $null ([int]::MaxValue)
      Assert-Fields $observation.workRoute @('actor','role','phase')
      if($r.binding.contextType-cne'TASK'-or$observation.workRoute.actor-cne$r.binding.taskActor-or$observation.workRoute.role-cnotin@('CONTROLLER','TASK_OWNER','EXECUTOR','REVIEWER','FRAMEWORK_MAINTAINER')-or$observation.workRoute.phase-cnotin@('DISCOVER','PLAN','IMPLEMENT','VERIFY','REVIEW','GIT','EXTERNAL','RECOVER')){throw 'DISCOVER_SOURCE_WORK_ROUTE'}
      if($observation.selectionIdentity-cne(Get-AiwContentDescriptorIdentity @($observation.loadedRuleIds))-or@($r.selectedObligations.requirementId|Where-Object{$_-cnotin$observation.loadedRuleIds}).Count){throw 'DISCOVER_SOURCE_LOADED_SELECTION'}
      Assert-StringArray @($r.selectedObligations.requirementId) 'currentRuleIds' $null ([int]::MaxValue)
      if($r.selectionIdentity-cne(Get-OperationSelectionIdentity $r.sourceCompositionIdentity $r.intentEnvelope $r.binding $r.selectedObligations)){throw 'DISCOVER_CURRENT_SELECTION_IDENTITY'}
    }elseif($observation.schemaVersion-ne1){throw 'DISCOVER_SOURCE_OBSERVATION_VERSION'}
    Assert-Fields $observation $fields
    $view|Add-Member -NotePropertyName sourceObservation -NotePropertyValue $observation
  }
  if(-not($view.authorityGranted-is[bool])-or-not($view.semanticCorrectnessProven-is[bool])-or[string]$view.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or[string]$view.mode-cne'DISCOVER'-or[string]$view.status-cnotin@('PASS','EVALUATION_ONLY')-or[string]$view.frameworkVersion-cne'2.0.0'-or[bool]$view.authorityGranted-or[bool]$view.semanticCorrectnessProven){throw 'DISCOVER_RECEIPT_TYPE'}
  foreach($countName in @('inputContractVersion','sourceBuildCount','legacyCorrectionsFullReadCount','legacyProjectCustomFullReadCount','selectedPackBytes','selectedPackCeilingBytes','selectedPackEstimatedTokens')){if(-not(Test-JsonInteger $view.$countName)-or[int]$view.$countName-lt0){throw ('DISCOVER_RECEIPT_COUNT|'+$countName)}}
  foreach($name in @('sourceCompositionIdentity','selectionIdentity','contextIdentity','projectId','taskIdentity','taskId','taskOwner','taskActor','actor','role','phase','profile','objective','actionKind','resultKind','hostEnforcementGrade','invocationState')){Assert-InputString $view.$name $name}
  Assert-StringArray $view.exactPaths 'receiptExactPaths';Assert-StringArray $view.evidenceCeilings 'receiptEvidenceCeilings'
  if(-not($view.selectedObligations-is[Array])){throw 'DISCOVER_RECEIPT_OBLIGATIONS'}
  foreach($obligation in @($view.selectedObligations)){
    Assert-Fields $obligation @('requirementId','preparationRequirements','resultRequirements')
    Assert-InputString $obligation.requirementId 'requirementId'
    Assert-StringArray $obligation.preparationRequirements 'receiptPreparationRequirements';Assert-StringArray $obligation.resultRequirements 'receiptResultRequirements'
  }
  Assert-Fields $view.sourceLocators @('projectRoot','frameworkRoot','taskRelativePath','authorizationPackagePath')
  foreach($name in @('projectRoot','frameworkRoot','taskRelativePath','authorizationPackagePath')){Assert-InputString $view.sourceLocators.$name $name}
  $bindingNames=@($view.sourceBindings.PSObject.Properties.Name);$requiredBindings=@('projectConfigIdentity','controllerIdentity','correctionsIdentity','policyIdentity','projectCustomIdentity','projectStandardsIdentity','taskIdentity','frameworkVersionIdentity','releaseManifestIdentity','candidatePilotStateIdentity','nativeCatalogIdentity')
  if([int]$r.schemaVersion-in@(3,4)){$requiredBindings+=@('contentSnapshotIdentity','effectiveSetIdentity','implementationIdentity');if(($r.schemaVersion-eq3-and$r.inputContractVersion-ne4)-or($r.schemaVersion-eq4-and$r.inputContractVersion-ne5)){throw 'DISCOVER_RECEIPT_INPUT_CONTRACT'}}
  if($bindingNames -ccontains 'bootstrapManagedIdentity'){$requiredBindings+='bootstrapManagedIdentity'}
  if($bindingNames -ccontains 'projectAgentsIdentity'){$requiredBindings+='projectAgentsIdentity'}
  if(@($requiredBindings|Where-Object{$_-cnotin$bindingNames}).Count-ne0-or@($bindingNames|Where-Object{$_-cnotin$requiredBindings}).Count-ne0){throw 'DISCOVER_RECEIPT_BINDINGS'}
  foreach($name in $bindingNames){Assert-InputString $view.sourceBindings.$name $name;if([string]$view.sourceBindings.$name-cnotin@('MISSING','NOT_APPLICABLE')-and[string]$view.sourceBindings.$name-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('DISCOVER_RECEIPT_BINDING|'+$name)}}
  $authorityFields=@('schemaVersion','projectId','projectRoot','repositoryGitTop','frameworkVersion','frameworkSealIdentity','controllerIdentity','taskIdentity','taskActor','actor','role','phase','profile','exactScope','forbiddenScope','protectedScope','authorizationIdentity','authorizedActions','observedCapabilities','projectConfigIdentity','correctionsIdentity','policyIdentity','userDecision','recoveryState','hostEnforcementGrade')
  if($null-ne$view.authorityContext.PSObject.Properties['contextType']){$authorityFields=@('schemaVersion','contextType','contextLocator')+$authorityFields[1..($authorityFields.Count-1)]+@('taskId','taskOwner')}
  $continuationAuthorityFields=@('continuationReceiptPath','continuationReceiptIdentity','continuationStepIndex');$presentContinuationFields=@($continuationAuthorityFields|Where-Object{$null-ne$view.authorityContext.PSObject.Properties[$_]})
  if($presentContinuationFields.Count-notin@(0,3)){throw 'DISCOVER_RECEIPT_CONTINUATION_FIELDS'};if($presentContinuationFields.Count-eq3){$authorityFields+=$continuationAuthorityFields}
  if($r.schemaVersion-eq4){$authorityFields+=@('controlRoot','objectRoot','repositoryId','executionContext')}
  Assert-Fields $view.authorityContext $authorityFields
  if($presentContinuationFields.Count-eq3){foreach($name in @('continuationReceiptPath','continuationReceiptIdentity')){Assert-InputString $view.authorityContext.$name $name};if([string]$view.authorityContext.continuationReceiptIdentity-cne'NOT_REQUIRED'-and[string]$view.authorityContext.continuationReceiptIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'DISCOVER_RECEIPT_CONTINUATION_IDENTITY'};if(-not(Test-JsonInteger $view.authorityContext.continuationStepIndex)-or[int]$view.authorityContext.continuationStepIndex-lt0){throw 'DISCOVER_RECEIPT_CONTINUATION_STEP'}}
  $intentFields=@('schemaVersion','objective','requestedActionKind','requestedResultKind','semanticHints','pathHints','capabilityHints','mutationHints','externalHints','ambiguityState')
  if([int]$r.schemaVersion-in@(3,4)){$intentFields+='facets';Assert-IntentEnvelope $view.intentEnvelope}
  Assert-Fields $view.intentEnvelope $intentFields
  return $view
}

function Assert-IntentEnvelope($Envelope){
  Assert-Fields $Envelope @('schemaVersion','objective','requestedActionKind','requestedResultKind','semanticHints','pathHints','capabilityHints','mutationHints','externalHints','ambiguityState','facets')
  if(-not(Test-JsonInteger $Envelope.schemaVersion)-or[int]$Envelope.schemaVersion-ne2){throw 'INTENT_SCHEMA_VERSION'}
  Assert-Fields $Envelope.facets @('domain','workType','deliverableType','stage')
  foreach($dimension in @('domain','workType','deliverableType','stage')){
    $facet=$Envelope.facets.$dimension;Assert-Fields $facet @('state','values')
    if($facet.state-isnot[string]-or$facet.state-cnotin@('KNOWN','UNKNOWN','NOT_APPLICABLE')){throw ('INTENT_FACET_STATE|'+$dimension)}
    Assert-StringArray $facet.values ('intent_facets_'+$dimension) ([int]::MaxValue) ([int]::MaxValue)
    if(($facet.state-ceq'KNOWN'-and$facet.values.Count-eq0)-or($facet.state-cne'KNOWN'-and$facet.values.Count-ne0)){throw ('INTENT_FACET_STATE_VALUES_CONTRADICTION|'+$dimension)}
  }
  foreach($name in @('objective','requestedActionKind','requestedResultKind','ambiguityState')){Assert-InputString $Envelope.$name $name}
  Assert-StringArray $Envelope.semanticHints 'intent_semanticHints' 64 256
  Assert-StringArray $Envelope.pathHints 'intent_pathHints' 64 512
  Assert-StringArray $Envelope.capabilityHints 'intent_capabilityHints' 32 128
  Assert-StringArray $Envelope.mutationHints 'intent_mutationHints' 32 128
  Assert-StringArray $Envelope.externalHints 'intent_externalHints' 32 256
  if([string]$Envelope.ambiguityState-cnotin@('CLEAR','UNKNOWN','CONFLICT')){throw 'INTENT_VALUES'}
  Assert-ActionAndResult ([string]$Envelope.requestedActionKind) ([string]$Envelope.requestedResultKind)
}

function Test-IntentPathHint([string]$Hint,[string[]]$ExactPaths){
  $normalized=$Hint.TrimEnd('/')
  if([string]::IsNullOrWhiteSpace($normalized)-or$Hint-cne$Hint.Replace('\','/')-or[IO.Path]::IsPathRooted($Hint)-or$Hint.Contains(':')){throw 'INTENT_PATH_HINT'}
  foreach($part in $normalized.Split('/')){if([string]::IsNullOrWhiteSpace($part)-or$part-in@('.','..')){throw 'INTENT_PATH_HINT'}}
  foreach($path in $ExactPaths){if($path-ceq$normalized-or$path.StartsWith($normalized+'/',[StringComparison]::Ordinal)){return $true}}
  return $false
}

function Get-IntentFactMismatches($Envelope,[string[]]$Capabilities,[string[]]$ExactPaths,[string]$ActionKind){
  $mismatches=New-Object 'System.Collections.Generic.List[string]'
  foreach($hint in @($Envelope.pathHints)){if(-not(Test-IntentPathHint ([string]$hint) $ExactPaths)){$mismatches.Add('PATH_HINT_OUTSIDE_EXACT_SCOPE')}}
  foreach($hint in @($Envelope.capabilityHints)){if([string]$hint-cnotin$Capabilities){$mismatches.Add('CAPABILITY_HINT_UNOBSERVED')}}
  $actionFamilies=@{
    'source'=@('SOURCE_WRITE');'test'=@('TEST_WRITE','TEST_RUN');'control'=@('CONTROL_WRITE');
    'review'=@('REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT');'git'=@('GIT_STAGE','GIT_COMMIT','PUSH');
    'browser'=@('BROWSER_RUN');'device'=@('DEVICE_RUN');'external'=@('EXTERNAL')
  }
  foreach($hint in @($Envelope.mutationHints)){
    $key=([string]$hint).ToLowerInvariant()
    if(-not$actionFamilies.ContainsKey($key)-or$ActionKind-cnotin@($actionFamilies[$key])){$mismatches.Add('MUTATION_HINT_ACTION_MISMATCH')}
  }
  if(@($Envelope.externalHints).Count-gt0-and$ActionKind-cne'EXTERNAL'){$mismatches.Add('EXTERNAL_HINT_ACTION_MISMATCH')}
  return @($mismatches|Sort-Object -Unique)
}

function Get-GitTop([string]$ProjectRoot){
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
  try{$output=@(& git -c ('safe.directory='+$ProjectRoot) -C $ProjectRoot rev-parse --show-toplevel 2>$null|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
  if($code-ne0-or$output.Count-ne1){return 'UNPROVEN'}
  return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($output[0]))
}

function Get-AuthorizationRepositoryRoot([pscustomobject]$Package,[string]$ProjectRoot,[string]$TaskPath='',[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@(),[switch]$AllowCommitPostimage){
  $controlRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
  if($Package.schemaVersion-eq4){
    Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
    $target=Resolve-AiwPackageExecutionTarget $controlRoot $Package $TaskPath $ForbiddenPaths $ProtectedPaths -AllowCommitPostimage:$AllowCommitPostimage
    return $target.executionRoot
  }
  if([int]$Package.schemaVersion-ne2-or[string]$Package.repositoryId-ceq'CONTROL'){return $controlRoot}
  $config=Read-Input (Join-Path $controlRoot '.ai-workspace/project.json')
  if($null-eq$config.PSObject.Properties['frameworkTarget']-or[string]$config.frameworkTarget.repositoryId-cne[string]$Package.repositoryId){throw 'AUTHORIZATION_REPOSITORY_DRIFT'}
  return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $controlRoot) ([string]$config.frameworkTarget.siblingDirectory))))
}

function Get-TaskBindingObservation([string]$ProjectRoot,[string]$TaskRelativePath){
  $taskFull=Join-Path $ProjectRoot $TaskRelativePath
  $taskText=(Read-AiwControlTransitionTask $ProjectRoot $taskFull).Text
  $taskIdMatch=[regex]::Matches($taskText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
  $taskOwnerMatch=[regex]::Matches($taskText,'(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$')
  $taskRouteMatch=[regex]::Matches($taskText,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>[A-Z_]+);\s*phase=(?<phase>[A-Z_]+)\s*$')
  $taskProfileMatch=[regex]::Matches($taskText,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL);')
  if($taskIdMatch.Count-ne1-or$taskOwnerMatch.Count-ne1-or$taskRouteMatch.Count-ne1-or$taskProfileMatch.Count-ne1){throw 'TASK_BINDING_FIELDS'}
  return [pscustomobject]@{TaskId=[string]$taskIdMatch[0].Groups['id'].Value;Owner=[string]$taskOwnerMatch[0].Groups['owner'].Value;TaskActor=[string]$taskRouteMatch[0].Groups['actor'].Value;Role=[string]$taskRouteMatch[0].Groups['role'].Value;Phase=[string]$taskRouteMatch[0].Groups['phase'].Value;Profile=[string]$taskProfileMatch[0].Groups['profile'].Value}
}

function Assert-AuthorizationPostimages([string]$PackagePath,[string]$ProjectRoot,[string[]]$ExactPaths,[string[]]$ResultReceipts,[string]$TaskPath='', [string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@(),[switch]$AllowCommitPostimage){
  if($PackagePath-ceq'NOT_REQUIRED'){return}
  $package=Read-Input $PackagePath
  $repositoryRoot=Get-AuthorizationRepositoryRoot $package $ProjectRoot $TaskPath $ForbiddenPaths $ProtectedPaths -AllowCommitPostimage:$AllowCommitPostimage
  foreach($relative in $ExactPaths){
    $objectPath=Join-Path $repositoryRoot $relative
    if($package.schemaVersion-eq4){$target=Resolve-AiwPackageExecutionTarget $ProjectRoot $package $TaskPath $ForbiddenPaths $ProtectedPaths -AllowCommitPostimage:$AllowCommitPostimage;$objectPath=Resolve-AiwExecutionTargetCandidatePath $target $relative $ForbiddenPaths $ProtectedPaths}
    $postimageIdentity=if(Test-Path -LiteralPath $objectPath -PathType Leaf){Get-Identity $objectPath}else{'MISSING'}
    $expectedReceipt='OBJECT_POSTIMAGE|'+$relative+'|'+$postimageIdentity
    $matches=@($ResultReceipts|Where-Object{$_-ceq$expectedReceipt})
    if($matches.Count-ne1){throw ('RESULT_POSTIMAGE_RECEIPT_REQUIRED|'+$relative)}
  }
}

function New-AuthorizationContinuationReceipt([string]$PackagePath,[string]$ProjectRoot,$Receipt,[string]$DiscoverReceiptPath,[string]$DiscoverReceiptIdentity,[string]$ProtectionState,$EvidenceRefs,[string]$Disposition='ADVANCE',[string]$SelfCheckOutcome='NOT_APPLICABLE'){
  if($PackagePath-ceq'NOT_REQUIRED'-or$null-eq$Receipt.authorityContext.PSObject.Properties['continuationStepIndex']){
    if($Disposition-cin@('REPAIR','RETEST')){throw 'SELF_REPAIR_CONTINUATION_REQUIRED'}
    return [pscustomobject]@{receipt=$null;state='NONE'}
  }
  $package=Read-Input $PackagePath
  if($null-eq$package.PSObject.Properties['continuationPlan']){return [pscustomobject]@{receipt=$null;state='NONE'}}
  $plan=@($package.continuationPlan);$completedStep=[int]$Receipt.authorityContext.continuationStepIndex;$nextStep=$completedStep+1
  if($completedStep-lt0-or$completedStep-ge$plan.Count-or[string]$Receipt.actionKind-cne[string]$plan[$completedStep]){throw 'CONTINUATION_FINALIZE_STEP_DRIFT'}
  $hasSelfLimit=$null-ne$package.PSObject.Properties['selfCheckRepairLimit'];$cycle=0;$transition='ADVANCE'
  if($hasSelfLimit-and$Receipt.authorityContext.continuationReceiptPath-ceq'NOT_REQUIRED'){
    $originContext=New-AiwPackageEvidenceContext $ProjectRoot $package $Receipt.sourceLocators.frameworkRoot $Receipt.authorityContext.forbiddenScope -TaskPath $Receipt.sourceLocators.taskRelativePath -ProtectedPaths $Receipt.authorityContext.protectedScope
    $cycle=Get-AiwSelfRepairOriginCycle $originContext $package
  }
  if($hasSelfLimit-and$Receipt.authorityContext.continuationReceiptPath-cne'NOT_REQUIRED'){
    $previous=Read-Input $Receipt.authorityContext.continuationReceiptPath
    $cycle=[int]$previous.selfRepairCycle
  }
  if($Disposition-ceq'STOP'){return [pscustomobject]@{receipt=$null;state='STOPPED'}}
  if($Disposition-cin@('REPAIR','RETEST')){
    if($Receipt.actionKind-cne'TEST_RUN'-or$SelfCheckOutcome-cne'FAIL'){throw 'SELF_REPAIR_ACTUAL_FAILURE_REQUIRED'}
    if(-not$hasSelfLimit){return [pscustomobject]@{receipt=$null;state='NO_REPAIR_PERMISSION'}}
    if($cycle-ge$package.selfCheckRepairLimit){return [pscustomobject]@{receipt=$null;state='REPAIR_LIMIT_EXHAUSTED'}}
    $cycle++;$transition=$Disposition;$nextStep=if($Disposition-ceq'REPAIR'){0}else{1}
  }elseif($Receipt.actionKind-ceq'TEST_RUN'){
    if($SelfCheckOutcome-ceq'INCOMPLETE'){return [pscustomobject]@{receipt=$null;state='INCOMPLETE'}}
    if($SelfCheckOutcome-ceq'FAIL'-and($nextStep-ge$plan.Count-or$plan[$nextStep]-ceq'REVIEW_ROUTE')){return [pscustomobject]@{receipt=$null;state='SELF_CHECK_FAILED'}}
  }
  if($nextStep-ge$plan.Count){return [pscustomobject]@{receipt=$null;state='FINISHED'}}
  $scopeContext=New-AiwPackageEvidenceContext $ProjectRoot $package $Receipt.sourceLocators.frameworkRoot $Receipt.authorityContext.forbiddenScope -TaskPath $Receipt.sourceLocators.taskRelativePath -ProtectedPaths $Receipt.authorityContext.protectedScope
  $completedScope=@(Get-AiwActionScopeObjects $package $Receipt.actionKind $scopeContext)
  if((@($Receipt.exactPaths|Sort-Object)-join'|')-cne(@($completedScope.path|Sort-Object)-join'|')){throw 'CONTINUATION_FINALIZE_SCOPE_DRIFT'}
  $repositoryRoot=Get-AuthorizationRepositoryRoot $package $ProjectRoot $Receipt.sourceLocators.taskRelativePath $Receipt.authorityContext.forbiddenScope $Receipt.authorityContext.protectedScope
  $postimages=@()
  foreach($relative in @($package.exactPaths)){
    $objectPath=Join-Path $repositoryRoot ([string]$relative)
    $postimageIdentity=if(Test-Path -LiteralPath $objectPath -PathType Leaf){Get-Identity $objectPath}elseif(Test-Path -LiteralPath $objectPath){throw 'CONTINUATION_POSTIMAGE_NOT_FILE'}else{'NEW'}
    $postimages+=[pscustomobject][ordered]@{path=[string]$relative;identity=$postimageIdentity}
  }
  if($plan[$nextStep]-ceq'REVIEW_ROUTE'){
    $ctx=New-AiwPackageEvidenceContext $ProjectRoot $package $Receipt.sourceLocators.frameworkRoot $Receipt.authorityContext.forbiddenScope -TaskPath $Receipt.sourceLocators.taskRelativePath -ProtectedPaths $Receipt.authorityContext.protectedScope
    $planText=[IO.File]::ReadAllText((Join-Path $ProjectRoot $Receipt.sourceLocators.taskRelativePath))
    $candidates=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=$postimages}))
    $qualityPlan=Get-AiwAcceptancePlan $planText
    if(Test-AiwReviewSelfCheckRequired $qualityPlan){Assert-AiwReviewSelfCheck $ctx $EvidenceRefs $Receipt.taskId $candidates $qualityPlan}
    else{
      $null=Get-AiwPackageQuality $ctx $package $qualityPlan
      if($Receipt.actionKind-cnotin@('SOURCE_WRITE','TEST_WRITE','CONTROL_WRITE','TEST_RUN')){throw 'QUALITY_PRODUCTION_FINALIZE_REQUIRED'}
      # The receipt is generated only inside the successful original FINALIZE.
      # Its consumer must supply that actual input/result pair at REVIEW_ROUTE;
      # no future result reference or synthetic SELF is embedded here.
    }
    $postimages=@(Get-AiwComposedReviewCandidate $ctx $package $postimages)
  }
  $repositoryId=if([int]$package.schemaVersion-in@(2,4)){[string]$package.repositoryId}else{'REPO_LOCAL'}
  $continuation=[ordered]@{
    schemaVersion=1;receiptType='AUTHORIZED_ACTION_CONTINUATION';status='PASS';evidenceGrade='INSTRUCTION_BOUND';authorityGranted=$false
    packageIdentity=Get-Identity $PackagePath;taskIdentity=[string]$Receipt.taskIdentity;taskId=[string]$Receipt.taskId;taskOwner=[string]$Receipt.taskOwner;taskActor=[string]$Receipt.taskActor;actor=[string]$Receipt.actor
    repositoryId=$repositoryId;projectConfigIdentity=[string]$Receipt.sourceBindings.projectConfigIdentity;controllerIdentity=[string]$Receipt.sourceBindings.controllerIdentity;userDecision=[string]$Receipt.authorityContext.userDecision;protectionState=$ProtectionState;forbiddenScope=@($Receipt.authorityContext.forbiddenScope);protectedScope=@($Receipt.authorityContext.protectedScope)
    sourceDiscoverReceiptPath=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $DiscoverReceiptPath));sourceDiscoverReceiptIdentity=$DiscoverReceiptIdentity;sourceSelectionIdentity=[string]$Receipt.selectionIdentity;sourceContextIdentity=[string]$Receipt.contextIdentity
    completedStepIndex=$completedStep;completedAction=[string]$plan[$completedStep];nextStepIndex=$nextStep;nextAction=[string]$plan[$nextStep]
    exactPaths=@($postimages.path);postObjectIdentities=@($postimages);evidenceRefs=@($EvidenceRefs)
  }
  if($hasSelfLimit){$continuation.schemaVersion=2;$continuation['transitionKind']=$transition;$continuation['selfRepairCycle']=$cycle}
  if($package.schemaVersion-eq4){
    Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
    $current=Resolve-AiwPackageExecutionTarget $ProjectRoot $package $Receipt.sourceLocators.taskRelativePath $Receipt.authorityContext.forbiddenScope $Receipt.authorityContext.protectedScope
    $continuation.schemaVersion=3
    $continuation['transitionKind']=$transition;$continuation['selfRepairCycle']=$cycle
    $continuation['executionTargetRef']=$current.executionTargetRef
    $continuation['observedTargetState']=Get-AiwExecutionTargetState $Receipt.authorityContext.executionContext
    $continuation['postTargetState']=Get-AiwExecutionTargetState $current
  }

  return [pscustomobject]@{receipt=$continuation;state='AVAILABLE'}
}

function Get-AuthorizationObservation([string]$Path,[string]$ExpectedIdentity,[string]$Actor,[string[]]$ExactPaths,[string]$UserDecision,[string]$ActionKind,[string]$ProjectRoot,[string]$TaskRelativePath,[string]$TaskIdentity,[string]$TaskId,[string]$TaskOwner,[string]$ProjectConfigIdentity,[string]$ContinuationReceiptPath='NOT_REQUIRED',[string]$ExpectedContinuationReceiptIdentity='NOT_REQUIRED',[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@()){
  if([string]$Path-ceq'NOT_REQUIRED'){
    if([string]$ExpectedIdentity-cne'NOT_REQUIRED'){throw 'AUTHORIZATION_INPUT_MISMATCH'}
    $controlRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
    if($ContinuationReceiptPath-cne'NOT_REQUIRED'-or$ExpectedContinuationReceiptIdentity-cne'NOT_REQUIRED'){throw 'CONTINUATION_WITHOUT_AUTHORIZATION'}
    return [pscustomobject]@{Actions=@();Identity='NOT_REQUIRED';UserDecision=$UserDecision;RepositoryId='CONTROL';RepositoryRoot=$controlRoot;RepositoryGitTop='NOT_APPLICABLE';HasContinuationPlan=$false;ContinuationReceiptPath='NOT_REQUIRED';ContinuationReceiptIdentity='NOT_REQUIRED';ContinuationStepIndex=-1}
  }
  if([string]$ExpectedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'AUTHORIZATION_IDENTITY'}
  $identity=Get-Identity $Path;if($identity-cne$ExpectedIdentity){throw 'AUTHORIZATION_DRIFT'}
  $package=Read-Input $Path
  foreach($name in @('schemaVersion','repositoryId','grantee','actions','exactPaths','userConfirmation')){if($name-ceq'repositoryId'-and[int]$package.schemaVersion-eq1){continue};if($null-eq$package.PSObject.Properties[$name]){throw 'AUTHORIZATION_FIELDS'}}
  Assert-StringArray $package.actions 'authorizationActions' 16 64;Assert-ExactPaths $package.exactPaths
  $controlRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
  $repositoryId=if([int]$package.schemaVersion-in@(2,4)){[string]$package.repositoryId}else{'REPO_LOCAL'}
  $repositoryRoot=Get-AuthorizationRepositoryRoot $package $controlRoot $TaskRelativePath $ForbiddenPaths $ProtectedPaths
  $target=$null;if($package.schemaVersion-eq4){$target=Resolve-AiwPackageExecutionTarget $controlRoot $package $TaskRelativePath $ForbiddenPaths $ProtectedPaths}
  $readContext=$null;$evidenceOwner=$null
  if($ActionKind-ceq'NONE'){
    $readContext=New-AiwPackageEvidenceContext $controlRoot $package ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))) $ForbiddenPaths -TaskPath $TaskRelativePath -ProtectedPaths $ProtectedPaths
    $evidenceOwner=(Get-Command New-AiwPackageEvidenceContext).Module
  }
  $observedIdentities=@();foreach($relative in $ExactPaths){
    $candidate=if($null-ne$target){Resolve-AiwExecutionTargetCandidatePath $target $relative $ForbiddenPaths $ProtectedPaths}elseif($ActionKind-ceq'NONE'){
      # Reuse the original evidence path guard before metadata or hashing. A
      # read-only assignment cannot bypass current candidate protection.
      & $evidenceOwner {param($context,$path) Resolve-EvPath $context $path -Candidate -AllowMissing} $readContext $relative
    }else{Join-Path $repositoryRoot $relative}
    $observed=if(Test-Path -LiteralPath $candidate -PathType Leaf){Get-Identity $candidate}elseif(Test-Path -LiteralPath $candidate){throw 'AUTHORIZATION_OBJECT_NOT_FILE'}else{'NEW'};$observedIdentities+=($relative+'='+$observed)
  }
  $checker=if([string]::IsNullOrWhiteSpace($AuthorizationCheckerPath)){Join-Path $PSScriptRoot 'check-authorization.ps1'}else{[IO.Path]::GetFullPath($AuthorizationCheckerPath)}
  if(-not(Test-Path -LiteralPath $checker -PathType Leaf)-or((Get-Item -LiteralPath $checker -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'AUTHORIZATION_CHECKER_UNAVAILABLE'}
  $checkerArgs=@{PackagePath=$Path;ObservedActor=$Actor;ObservedTaskId=$TaskId;ObservedOwner=$TaskOwner;ObservedAction=@($ActionKind);ObservedPath=@($ExactPaths);ObservedIdentity=@($observedIdentities);ControllerControlPath='.ai-workspace/controller.json';ObservedRepositoryId=$repositoryId;ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=$ProjectConfigIdentity;TaskPath=$TaskRelativePath;ExpectedTaskIdentity=$TaskIdentity}
  if($package.schemaVersion-eq4){Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1');$checkerArgs.ControlRoot=$controlRoot;$checkerArgs.ForbiddenPaths=@($ForbiddenPaths);$checkerArgs.ProtectedPaths=@($ProtectedPaths)}
  elseif($ActionKind-ceq'NONE'){$checkerArgs.ForbiddenPaths=@($ForbiddenPaths);$checkerArgs.ProtectedPaths=@($ProtectedPaths)}
  if($ContinuationReceiptPath-cne'NOT_REQUIRED'-or$ExpectedContinuationReceiptIdentity-cne'NOT_REQUIRED'){
    if($ContinuationReceiptPath-ceq'NOT_REQUIRED'-or$ExpectedContinuationReceiptIdentity-ceq'NOT_REQUIRED'){throw 'CONTINUATION_RECEIPT_BINDING_INCOMPLETE'}
    $checkerArgs.ContinuationReceiptPath=$ContinuationReceiptPath;$checkerArgs.ExpectedContinuationReceiptIdentity=$ExpectedContinuationReceiptIdentity
  }
  $gitAction=$ActionKind-cin@('GIT_STAGE','GIT_COMMIT','PUSH');$repositoryGitTop=if($null-ne$target){$target.targetObservation.gitTop}else{'NOT_APPLICABLE'}
  if([int]$package.schemaVersion-eq2){
    if($gitAction-or$repositoryRoot-cne$controlRoot){
      $controlGitTop=Get-GitTop $controlRoot;$repositoryGitTop=Get-GitTop $repositoryRoot
      if($controlGitTop-cne$controlRoot-or$repositoryGitTop-cne$repositoryRoot){throw 'AUTHORIZATION_REPOSITORY_GIT_TOP_DRIFT'}
    }
    $defaultChecker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'check-authorization.ps1'))
    if([IO.Path]::GetFullPath($checker)-ceq$defaultChecker){$checkerArgs.RootRepositoryBindingValidated=$true}
  }
  $previousCurrentDirectory=[Environment]::CurrentDirectory;$legacyCwd=$package.schemaVersion-ne4;if($legacyCwd){Push-Location $controlRoot}
  try{
    if($legacyCwd){[Environment]::CurrentDirectory=$controlRoot}
    if([IO.Path]::GetFullPath($checker).Equals([IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'check-authorization.ps1')),[StringComparison]::OrdinalIgnoreCase)){
      $authorizationCore=@(Import-Module (Join-Path $PSScriptRoot 'AuthorizationCheck.psm1') -PassThru)[0]
      $checked=& $authorizationCore.ExportedCommands['Invoke-AiwAuthorizationCheck'] @checkerArgs
      $checkOutput=@($checked.output);$checkCode=$checked.exitCode
    }else{$checkOutput=@(& $checker @checkerArgs 2>&1|ForEach-Object{[string]$_});$checkCode=$LASTEXITCODE}
  }finally{if($legacyCwd){[Environment]::CurrentDirectory=$previousCurrentDirectory;Pop-Location}}
  if($checkCode-ne0){throw ('AUTHORIZATION_CHECK_FAILED|'+($checkOutput-join';'))}
  if([string]$package.userConfirmation-cne$UserDecision){throw 'AUTHORIZATION_USER_DECISION_DRIFT'}
  $hasContinuationPlan=$null-ne$package.PSObject.Properties['continuationPlan']
  $continuationStep=-1
  if($hasContinuationPlan){
    if($ContinuationReceiptPath-ceq'NOT_REQUIRED'){$continuationStep=0}else{$continuation=Read-Input $ContinuationReceiptPath;$continuationStep=[int]$continuation.nextStepIndex}
  }
  return [pscustomobject]@{Actions=@($package.actions);Identity=$identity;UserDecision=[string]$package.userConfirmation;RepositoryId=$repositoryId;RepositoryRoot=$repositoryRoot;RepositoryGitTop=$repositoryGitTop;HasContinuationPlan=$hasContinuationPlan;ContinuationReceiptPath=$ContinuationReceiptPath;ContinuationReceiptIdentity=$ExpectedContinuationReceiptIdentity;ContinuationStepIndex=$continuationStep}
}
# One flat content-coverage projection; current authority and source selection
# are completed before this helper. Coverage failures cannot swallow those gates.
function Get-AiwRuleLoadProjection($Composition,$Anticipated,[object]$RuleLoad,[string]$Actor,[string]$ProjectRoot,[string[]]$ForbiddenPaths){
 $units=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 $unitOrder=[Collections.Generic.List[string]]::new()
 function Convert-LoadRules([object[]]$Selected){
  $rows=[Collections.Generic.List[object]]::new()
  foreach($rule in $Selected){
   $keys=[Collections.Generic.List[string]]::new()
   foreach($part in $rule.displayParts){
    $textIdentity=Get-AiwContentByteIdentity $utf8.GetBytes([string]$part.fullText)
    $norm=if($null-ne$part.PSObject.Properties['unitIdentity']){[string]$part.unitIdentity}else{Get-AiwContentDescriptorIdentity ([ordered]@{source=$rule.source;locator=$part.sourceLocator;ruleId=$rule.requirementId;textIdentity=$textIdentity})}
    $key=Get-AiwContentDescriptorIdentity ([ordered]@{source=$rule.source;locator=$part.sourceLocator;normativeIdentity=$norm;textIdentity=$textIdentity})
    $deps=@(if($null-ne$part.PSObject.Properties['orderedDependencies']){@($part.orderedDependencies)})
    $row=[pscustomobject]@{unitKey=$key;sourceKind=$rule.source;sourceLocator=$part.sourceLocator;normativeIdentity=$norm;textIdentity=$textIdentity;orderedDependencies=$deps;fullText=[string]$part.fullText}
    if($units.ContainsKey($key)){if($units[$key].fullText-cne$row.fullText){throw 'RULE_LOAD_UNIT_COLLISION'}}else{$units.Add($key,$row);$unitOrder.Add($key)}
    $keys.Add($key)
   }
   $selector=if($null-ne$rule.PSObject.Properties['selectorIdentity']){$rule.selectorIdentity}else{'NOT_APPLICABLE'}
   $metadataMaterial=if($null-ne$rule.PSObject.Properties['declarationIdentity']){[ordered]@{source=$rule.source;declarationIdentity=$rule.declarationIdentity;orderedUnitKeys=$keys.ToArray()}}else{[ordered]@{source=$rule.source;selectorIdentity=$selector;preparationRequirements=@($rule.preparationRequirements);resultRequirements=@($rule.resultRequirements);orderedUnitKeys=$keys.ToArray()}}
   $metadata=Get-AiwContentDescriptorIdentity $metadataMaterial
   $rows.Add([pscustomobject]@{requirementId=$rule.requirementId;orderedUnitKeys=$keys.ToArray();metadataIdentity=$metadata;semanticApplicability=$rule.semanticApplicability;preparationRequirements=@($rule.preparationRequirements);resultRequirements=@($rule.resultRequirements)})
  }
  return $rows.ToArray()
 }
 $bodyRules=@(Convert-LoadRules @($Composition.selectedRequirements))
 $operationIds=@($Composition.selectedObligations.requirementId)
 $currentRules=@($bodyRules|Where-Object{$_.requirementId-cin$operationIds})
 $keys=@($unitOrder)
 $framework=Get-AiwContentDescriptorIdentity ([ordered]@{version=$Composition.frameworkVersionIdentity;seal=$Composition.releaseManifestIdentity;catalog=$Composition.nativeCatalogIdentity;implementation=$Composition.implementationIdentity})
 $coverage=[pscustomobject]@{schemaVersion=1;actor=$Actor;frameworkSourceIdentity=$framework;units=@(@($unitOrder|ForEach-Object{$units[$_]})|Select-Object unitKey,sourceKind,sourceLocator,normativeIdentity,textIdentity,orderedDependencies);rules=@($bodyRules|Select-Object requirementId,orderedUnitKeys,metadataIdentity);anticipatedSteps=@()}
 $decision=[pscustomobject]@{requestedMode=$RuleLoad.mode;effectiveMode='FULL';fallbackReason=$(if($RuleLoad.mode-ceq'REUSE'){'LEGACY_REUSE_RETURNS_FULL'}else{'NONE'});requiredUnitKeys=$keys;returnedUnitKeys=$keys;reusedUnitKeys=@();anticipatedUnitKeys=@()}
 return [pscustomobject]@{bodyCoverage=$coverage;loadDecision=$decision;modelView=[pscustomobject]@{uniqueUnits=@($unitOrder|ForEach-Object{$units[$_]});currentRules=$currentRules;anticipatedSteps=@();loadDecision=$decision;evidenceCeilings=@($Composition.evidenceCeilings)}}
}


function Remove-ConsumedBoundaryInput([string]$Path,[string]$Identity){
  $original=[pscustomobject]@{path=$Path;identity=$Identity}
  $observation=Remove-AiwConsumedRuntimeFiles -ScopeRoot ([IO.Path]::GetDirectoryName($Path)) -LiteralPath @($Path) -ExpectedObject @($original)
  $observation|Add-Member consumedObject $original
  $observation
}
$cleanupInput=$null;$cleanupObservation=$null;$inputReadIdentity=$null;$artifactStorage='CALLER_MANAGED'
try{
  $inputFull=[IO.Path]::GetFullPath($InputPath)
  $input=Read-Input $InputPath ([ref]$inputReadIdentity)
  if($CompactReceiptPath-and[string]$input.mode-cne'DISCOVER'-and$null-eq$input.PSObject.Properties['actionRebind']){throw 'COMPACT_DISCOVER_ONLY'}
  if($DisplayPath -and [string]$input.mode-cne'DISCOVER'){throw 'DISPLAY_DISCOVER_ONLY'}
  if($DeleteInputOnExit){$cleanupObservation=Get-SafeCleanupInput $InputPath;$artifactStorage=[string]$cleanupObservation.Storage;if($artifactStorage-ceq'SYSTEM_TEMP_FALLBACK'){$cleanupInput=[string]$cleanupObservation.Path}}
  if(-not($input-is[pscustomobject])-or$null-eq$input.PSObject.Properties['mode']-or-not($input.mode-is[string])){throw 'INPUT_MODE'}
  $mode=[string]$input.mode
  $reboundCompact=$null;$rebindAuthorization=$null
  if($null-ne$PublicationContext){
   if($mode-cne$PublicationContext.mode-or$inputFull-cne[IO.Path]::GetFullPath($PublicationContext.inputRef.path)-or$inputReadIdentity-cne$PublicationContext.inputRef.identity){throw 'SOURCE_PUBLICATION_PRIVATE_INPUT_DRIFT'}
  }
  if($mode-ceq'DISCOVER'){
    if(-not(Test-JsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-notin@(4,5)){throw 'INPUT_SCHEMA_VERSION'}
    $inputContract=[int]$input.schemaVersion
      $discoverFields=@('schemaVersion','mode','projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities','exactPaths','forbiddenPaths','protectedPaths','authorizationPackagePath','expectedAuthorizationIdentity','userDecision','recoveryState','hostEnforcementGrade','invocationState','intentEnvelope','evaluationOnly')
      if($inputContract-in@(4,5)){$discoverFields+=@('contextType',$(if($inputContract-eq5-and$input.contextType-ceq'PROJECT_EXTERNAL'){'requestContext'}else{'readOnlyContext'}))}
      if($inputContract-eq5){
        $discoverFields+='ruleLoad'
        if($null-ne$input.PSObject.Properties['executionTargetRef']){$discoverFields+='executionTargetRef'}
      }
      $continuationInputFields=@('continuationReceiptPath','expectedContinuationReceiptIdentity');$presentContinuationInputFields=@();foreach($continuationInputField in $continuationInputFields){if($null-ne$input.PSObject.Properties[$continuationInputField]){$presentContinuationInputFields+=$continuationInputField}}
      if($presentContinuationInputFields.Count-notin@(0,2)){throw 'CONTINUATION_RECEIPT_BINDING_INCOMPLETE'};if($presentContinuationInputFields.Count-eq2){$discoverFields+=$continuationInputFields}
      Assert-Fields $input $discoverFields
      $intent=$input.intentEnvelope;Assert-IntentEnvelope $intent
      $input|Add-Member -NotePropertyName objective -NotePropertyValue ([string]$intent.objective)
      $input|Add-Member -NotePropertyName actionKind -NotePropertyValue ([string]$intent.requestedActionKind)
      $input|Add-Member -NotePropertyName resultKind -NotePropertyValue ([string]$intent.requestedResultKind)
      $forbiddenPaths=@($input.forbiddenPaths);$protectedPaths=@($input.protectedPaths);$authorizationPath=[string]$input.authorizationPackagePath;$authorizationIdentity=[string]$input.expectedAuthorizationIdentity;$continuationReceiptPath=if($presentContinuationInputFields.Count-eq2){[string]$input.continuationReceiptPath}else{'NOT_REQUIRED'};$continuationReceiptIdentity=if($presentContinuationInputFields.Count-eq2){[string]$input.expectedContinuationReceiptIdentity}else{'NOT_REQUIRED'};$userDecision=[string]$input.userDecision;$recoveryState=[string]$input.recoveryState;$invocationState=[string]$input.invocationState
      Assert-PathPrefixes $forbiddenPaths 'forbiddenPaths' -AllowAbsolute:($inputContract-eq5);Assert-PathPrefixes $protectedPaths 'protectedPaths' -AllowAbsolute:($inputContract-eq5)
      if($recoveryState-cnotin@('FULL_COLD','WARM','CURRENT','UNKNOWN')-or$invocationState-cnotin@('PROVEN_EXPLICIT','PROVEN_MANAGED','UNPROVEN')){throw 'CONTEXT_STATE'}
      if($continuationReceiptPath-cne'NOT_REQUIRED'-and$continuationReceiptIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'CONTINUATION_RECEIPT_IDENTITY_FORMAT'}
    $contextType=if($inputContract-in@(4,5)){[string]$input.contextType}else{'TASK'}
    if($contextType-cnotin@('TASK','PROJECT_READ_ONLY','PROJECT_EXTERNAL')-or($contextType-ceq'PROJECT_EXTERNAL'-and$inputContract-ne5)){throw 'CONTEXT_TYPE'}
    foreach($n in @('projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedTaskIdentity','observedActor','objective','actionKind','resultKind','hostEnforcementGrade')){if(-not($input.$n-is[string])-or[string]::IsNullOrWhiteSpace([string]$input.$n)){throw "INPUT_STRING|$n"}}
    Assert-InputString $input.expectedCorrectionsIdentity 'expectedCorrectionsIdentity'
    if([string]$input.expectedProjectConfigIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INPUT_IDENTITY|expectedProjectConfigIdentity'}
    if(($contextType-ceq'TASK'-and[string]$input.expectedTaskIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')-or($contextType-cin@('PROJECT_READ_ONLY','PROJECT_EXTERNAL')-and[string]$input.expectedTaskIdentity-cne'NOT_APPLICABLE')){throw 'INPUT_IDENTITY|expectedTaskIdentity'}
    if([string]$input.expectedCorrectionsIdentity-cne'MISSING'-and[string]$input.expectedCorrectionsIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INPUT_IDENTITY|expectedCorrectionsIdentity'}
    Assert-StringArray $input.capabilities 'capabilities' 32 128;Assert-ExactPaths $input.exactPaths;Assert-ActionAndResult ([string]$input.actionKind) ([string]$input.resultKind)
    if(-not($input.evaluationOnly-is[bool])){throw 'INPUT_BOOL|evaluationOnly'}
    if([string]$input.hostEnforcementGrade-cnotin @('HOST_ENFORCED','FRAMEWORK_GATED','INSTRUCTION_BOUND')){throw 'HOST_ENFORCEMENT_GRADE'}
    $projectResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.projectRoot))))
    Assert-AiwNoControlTransition $projectResolved $(if($contextType-ceq'TASK'){[string]$input.taskPath}else{''})
    $actor=[string]$input.observedActor
    $projectExternalLoading=$input.actionKind-ceq'EXTERNAL'-and$authorizationPath-ceq'NOT_REQUIRED'
    if($projectExternalLoading-and$inputContract-ne5){throw 'PROJECT_EXTERNAL_LOAD_REQUIRES_INPUT5'}
    if($contextType-ceq'TASK'){
      if($inputContract-in@(4,5)-and[string]$input.readOnlyContext-cne'NOT_APPLICABLE'){throw 'READ_ONLY_CONTEXT_NOT_APPLICABLE'}
      $taskAbsolute=[IO.Path]::GetFullPath([string]$input.taskPath,$projectResolved)
      $taskDocument=Read-AiwControlTransitionTask $projectResolved $taskAbsolute
      $taskIdentity=$taskDocument.Identity;if($taskIdentity-cne[string]$input.expectedTaskIdentity){throw 'TASK_DRIFT'}
      $taskResolved=$taskDocument.Path;$projectPrefix=$projectResolved+[IO.Path]::DirectorySeparatorChar
      if(-not$taskResolved.StartsWith($projectPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'TASK_LOCATOR_SCOPE'}
      $taskRelative=$taskResolved.Substring($projectPrefix.Length).Replace('\','/');if(-not$taskRelative.StartsWith('.ai-workspace/tasks/',[StringComparison]::Ordinal)){throw 'TASK_LOCATOR_SCOPE'}
      $taskText=$taskDocument.Text
      $route=[regex]::Matches($taskText,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>CONTROLLER|TASK_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
      if($route.Count-ne1){$legacy=[regex]::Matches($taskText,'(?m)^- Work route:\s*role=(?<role>CONTROLLER|TASK_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$');if($legacy.Count-eq1){$result=[ordered]@{status='LEGACY_ACTOR_CONTEXT_UNBOUND';mode=$mode;evidenceCeiling='TASK_ACTOR_CONTEXT_REBIND_REQUIRED';taskIdentity=$taskIdentity};if($AsJson){$result|ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii}else{Write-Output 'LEGACY_ACTOR_CONTEXT_UNBOUND|TASK_ACTOR_CONTEXT_REBIND_REQUIRED'};throw (New-AiwPrivateToolExit (3))};throw 'TASK_WORK_ROUTE'}
      $taskActor=[string]$route[0].Groups['actor'].Value;$effectiveRole=[string]$route[0].Groups['role'].Value;$effectivePhase=[string]$route[0].Groups['phase'].Value
      $workRoute=[pscustomobject]@{actor=$taskActor;role=$effectiveRole;phase=$effectivePhase}
      if($actor-cne$taskActor){
        if($input.actionKind-ceq'NONE'-and$authorizationPath-ceq'NOT_REQUIRED'-and$input.resultKind-cin@('PLAN','USER_RESPONSE')){
          # Ordinary temporary task reading needs no implementation grant.
          # Apply the existing current candidate guard before scoped metadata.
          $readContext=New-AiwEvidenceContext $projectResolved '' ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))) $forbiddenPaths $protectedPaths
          $readOwner=(Get-Command New-AiwEvidenceContext).Module
          & $readOwner {param($context,$paths)foreach($path in $paths){$null=Resolve-EvPath $context $path -Candidate -AllowMissing}} $readContext @($input.exactPaths)
          $effectiveRole='EXECUTOR';$effectivePhase='PLAN'
        }elseif($projectExternalLoading){
          # Loading a declared project grant is not an action admission. The
          # complete selected policy below must explicitly opt into this mode.
          $effectiveRole='EXECUTOR';$effectivePhase='EXTERNAL'
        }else{
          if($inputContract-lt2-or$authorizationPath-ceq'NOT_REQUIRED'){throw 'CONFLICT_ACTOR_ROLE_PHASE'}
          $temporaryPackage=Read-Input $authorizationPath
          $effective=Get-ActionEffectiveRoute $workRoute $actor ([string]$input.actionKind) $temporaryPackage
          $effectiveRole=$effective.role;$effectivePhase=$effective.phase
        }
      }
      $profileMatch=[regex]::Matches($taskText,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL);');$taskIdMatch=[regex]::Matches($taskText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)');$taskOwnerMatch=[regex]::Matches($taskText,'(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$')
      if($profileMatch.Count-ne1-or$taskIdMatch.Count-ne1-or$taskOwnerMatch.Count-ne1){throw 'TASK_BINDING_FIELDS'}
      $profile=[string]$profileMatch[0].Groups['profile'].Value;$taskId=[string]$taskIdMatch[0].Groups['id'].Value;$taskOwner=[string]$taskOwnerMatch[0].Groups['owner'].Value;$runtimeSegment=$taskId
    }elseif($contextType-ceq'PROJECT_EXTERNAL'){
      # This is an honest external-intent rule load with no task or per-call
      # action package. It cannot create an ADMIT/FINALIZE execution chain.
      if($input.taskPath-cne'NOT_APPLICABLE'-or$authorizationPath-cne'NOT_REQUIRED'-or$authorizationIdentity-cne'NOT_REQUIRED'-or$input.actionKind-cne'EXTERNAL'-or$input.resultKind-cnotin@('EXTERNAL_RESULT','USER_RESPONSE')-or$null-ne$input.PSObject.Properties['executionTargetRef']){throw 'PROJECT_EXTERNAL_CONTEXT_BOUNDARY'}
      Assert-Fields $input.requestContext @('sessionId','requestId','role','phase','profile')
      foreach($name in @('sessionId','requestId','role','phase','profile')){Assert-InputString $input.requestContext.$name ('requestContext.'+$name)}
      if($input.requestContext.sessionId-cne$actor-or$input.requestContext.role-cne'EXECUTOR'-or$input.requestContext.phase-cne'EXTERNAL'-or$input.requestContext.profile-cnotin@('MICRO','STANDARD','CRITICAL')){throw 'PROJECT_EXTERNAL_REQUEST_CONTEXT'}
      $taskIdentity='NOT_APPLICABLE';$taskRelative='NOT_APPLICABLE';$taskId='NOT_APPLICABLE';$taskOwner='NOT_APPLICABLE';$taskActor='NOT_APPLICABLE'
      $effectiveRole='EXECUTOR';$effectivePhase='EXTERNAL';$profile=[string]$input.requestContext.profile;$runtimeSegment=[string]$input.requestContext.requestId
    }else{
      if($inputContract-notin@(4,5)-or[string]$input.taskPath-cne'NOT_APPLICABLE'-or[string]$input.authorizationPackagePath-cne'NOT_REQUIRED'-or[string]$input.expectedAuthorizationIdentity-cne'NOT_REQUIRED'-or[string]$input.actionKind-cne'NONE'-or[string]$input.resultKind-cnotin@('PLAN','USER_RESPONSE')){throw 'PROJECT_READ_ONLY_BOUNDARY'}
      Assert-Fields $input.readOnlyContext @('sessionId','requestId','role','phase','profile')
      foreach($name in @('sessionId','requestId','role','phase','profile')){Assert-InputString $input.readOnlyContext.$name ('readOnlyContext.'+$name)}
      if([string]$input.readOnlyContext.role-cnotin@('CONTROLLER','TASK_OWNER','FRAMEWORK_MAINTAINER','EXECUTOR','REVIEWER')-or[string]$input.readOnlyContext.phase-cnotin@('DISCOVER','PLAN','RECOVER')-or[string]$input.readOnlyContext.profile-cnotin@('MICRO','STANDARD','CRITICAL')){throw 'PROJECT_READ_ONLY_CONTEXT'}
      $taskIdentity='NOT_APPLICABLE';$taskRelative='NOT_APPLICABLE';$taskId='NOT_APPLICABLE';$taskOwner='NOT_APPLICABLE';$taskActor='NOT_APPLICABLE';$effectiveRole=[string]$input.readOnlyContext.role;$effectivePhase=[string]$input.readOnlyContext.phase;$profile=[string]$input.readOnlyContext.profile;$runtimeSegment=[string]$input.readOnlyContext.requestId
    }
    [string[]]$intentFactMismatches=@();if($inputContract-ge2){$intentFactMismatches=@(Get-IntentFactMismatches $intent @($input.capabilities) @($input.exactPaths) ([string]$input.actionKind))}
    if($intentFactMismatches.Count-gt0-and[string]$intent.ambiguityState-ceq'CLEAR'){throw ('INTENT_FACT_MISMATCH|'+[string]::Join(',',@($intentFactMismatches)))}
    if($continuationReceiptPath-cne'NOT_REQUIRED'){$continuationInput=Read-Input $continuationReceiptPath;if([string]::Join("`n",@($continuationInput.forbiddenScope))-cne[string]::Join("`n",@($forbiddenPaths))-or[string]::Join("`n",@($continuationInput.protectedScope))-cne[string]::Join("`n",@($protectedPaths))){throw 'CONTINUATION_PROTECTION_SCOPE_DRIFT'}}
    if($inputContract-eq5){
      $loadFields=@('mode')
      foreach($field in @('previousCoverageRef','preloadSteps')){if($null-ne$input.ruleLoad.PSObject.Properties[$field]){$loadFields+=$field}}
      Assert-Fields $input.ruleLoad $loadFields
      if($input.ruleLoad.mode-isnot[string]-or$input.ruleLoad.mode-cnotin@('FULL','REUSE')){throw 'RULE_LOAD_MODE'}
      if($input.ruleLoad.mode-ceq'FULL'-and$null-ne$input.ruleLoad.PSObject.Properties['previousCoverageRef']){throw 'RULE_LOAD_FULL_PREVIOUS_COVERAGE'}
      if($null-ne$input.ruleLoad.PSObject.Properties['preloadSteps']){
        if($input.ruleLoad.preloadSteps-isnot[Array]){throw 'RULE_LOAD_PRELOAD_ARRAY'}
        if($input.ruleLoad.preloadSteps.Count){throw 'RULE_LOAD_PRELOAD_RETIRED'}
      }
    }
    $semanticObjective=Get-AiwProcessSemanticText -IntentEnvelope $intent
    if(-not[bool]$input.evaluationOnly){
      $runtimeModule=Join-Path ([string]$input.frameworkRoot) 'scripts/ProjectAdoptionState.psm1'
      if(Test-Path -LiteralPath $runtimeModule -PathType Leaf){
        Import-Module $runtimeModule -ErrorAction Stop
        if($null-ne(Get-Command Get-AiwAdoptedDistributionBinding -ErrorAction SilentlyContinue)){
          $adopted=Get-AiwAdoptedDistributionBinding ([string]$input.projectRoot) '2.0.0'
          if($null-ne$adopted){$stateOwner=@(Import-Module $runtimeModule -PassThru)[0];$null=& $stateOwner {param($p,$r) Assert-AiwAdoptedRuntimeDeclaration $p $r '2.0.0'} ([string]$input.projectRoot) ([string]$input.frameworkRoot)}
        }
      }
    }
    $auth=$null
    if($projectExternalLoading){
      if($contextType-ceq'TASK'-and$taskText-cnotmatch'(?m)^- Range summary:\s*profile=(MICRO|STANDARD|CRITICAL);\s*lifecycle=ACTIVE;'){throw 'PROJECT_EXTERNAL_ACTIVE_CONTEXT_REQUIRED'}
      if($continuationReceiptPath-cne'NOT_REQUIRED'-or$continuationReceiptIdentity-cne'NOT_REQUIRED'){throw 'CONTINUATION_WITHOUT_AUTHORIZATION'}
      $effectivePhase='EXTERNAL'
    }elseif($contextType-ceq'TASK'-and$input.actionKind-ceq'EXTERNAL'-and$actor-ceq$taskActor-and$effectiveRole-ceq'TASK_OWNER'){
      $auth=Get-AuthorizationObservation $authorizationPath $authorizationIdentity $actor @($input.exactPaths) $userDecision ([string]$input.actionKind) $projectResolved $taskRelative $taskIdentity $taskId $taskOwner ([string]$input.expectedProjectConfigIdentity) $continuationReceiptPath $continuationReceiptIdentity $forbiddenPaths $protectedPaths
      $externalPackage=Read-Input $authorizationPath
      $effective=Get-ActionEffectiveRoute $workRoute $actor 'EXTERNAL' $externalPackage
      $effectiveRole=$effective.role;$effectivePhase=$effective.phase
    }
    $compositionArguments=@{ProjectRoot=[string]$input.projectRoot;FrameworkRoot=[string]$input.frameworkRoot;TargetVersion='2.0.0';ExpectedProjectConfigIdentity=[string]$input.expectedProjectConfigIdentity;ExpectedCorrectionsIdentity=[string]$input.expectedCorrectionsIdentity;Profile=$profile;Role=$effectiveRole;Phase=$effectivePhase;Actor=$actor;TaskIdentity=$taskIdentity;Capabilities=@($input.capabilities);IntentEnvelope=$intent;Objective=$semanticObjective;ActionKind=[string]$input.actionKind;ResultKind=[string]$input.resultKind;ExactPaths=@($input.exactPaths);ForbiddenPaths=@($forbiddenPaths);SemanticApplicabilityUnknown=([string]$intent.ambiguityState-cne'CLEAR');EvaluationOnly=[bool]$input.evaluationOnly}
    $compositionArguments.ObservedContextType=$contextType
    if($inputContract-eq5-and$contextType-ceq'TASK'){$compositionArguments.ObservedWorkRoute=$workRoute}
    if($input.actionKind-cin@('SOURCE_WRITE','CONTROL_WRITE')){
      $publicationOwner=(Get-Command Get-AiwProjectSourcePublicationEligibility).Module
      $composition=& $publicationOwner {param($parameters) Invoke-PubSelectedComposition $parameters} $compositionArguments
    }else{$composition=& $composerModule {param($parameters)Invoke-AiwProcessCompositionCore @parameters} $compositionArguments}
    if($projectExternalLoading-and($composition.projectExternalAuthorization.mode-cne'PROJECT_PREAUTHORIZED'-or$composition.projectExternalAuthorization.selectedGrantRuleIds.Count-eq0)){throw 'EXTERNAL_ACTION_PACKAGE_OR_SELECTED_PROJECT_GRANT_REQUIRED'}
    if($null-ne$cleanupObservation-and[string]$cleanupObservation.Storage-ceq'PROJECT_RUNTIME'){Assert-ProjectRuntimeCleanupBinding $cleanupObservation $projectResolved $runtimeSegment $actor}

    $executionContext=$null
    if($inputContract-eq5){
      Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
      $targetRef=if($null-ne$input.PSObject.Properties['executionTargetRef']){$input.executionTargetRef}else{$null}
      $configuration=Read-Input (Join-Path $projectResolved '.ai-workspace/project.json')
      if($configuration.controlPlaneLayout-ceq'framework-maintenance-sibling'-and$null-ne$targetRef){throw 'EXECUTION_TARGET_MAINTENANCE_PROJECT_DENIED'}
      $executionContext=Resolve-AiwExecutionTargetContext -ProjectRoot $projectResolved -ProjectId $composition.projectId -TaskPath ([string]$input.taskPath) -ExecutionTargetRef $targetRef -ForbiddenPaths $forbiddenPaths -ProtectedPaths $protectedPaths
      if($executionContext.targetKind-ceq'GIT_WORKTREE'-and$input.actionKind-cnotin@('NONE','CONTROL_WRITE')){
        if($authorizationPath-ceq'NOT_REQUIRED'){throw 'EXECUTION_TARGET_PACKAGE4_REQUIRED'}
        $targetPackage=Read-Input $authorizationPath
        $boundTarget=Resolve-AiwPackageExecutionTarget $projectResolved $targetPackage $taskRelative $forbiddenPaths $protectedPaths
        if(($boundTarget.executionTargetRef|ConvertTo-Json -Compress)-cne($executionContext.executionTargetRef|ConvertTo-Json -Compress)){throw 'EXECUTION_TARGET_PACKAGE_REFERENCE_DRIFT'}
      }
      $composition.sourceCompositionIdentity=Get-RuleSourceIdentity $composition $composition.sourceObservation
    }
    if($inputContract-ne5-and$authorizationPath-cne'NOT_REQUIRED'-and(Read-Input $authorizationPath).schemaVersion-eq4){throw 'EXECUTION_TARGET_PACKAGE_REQUIRES_INPUT5'}
    if($null-eq$auth){$auth=Get-AuthorizationObservation $authorizationPath $authorizationIdentity $actor @($input.exactPaths) $userDecision ([string]$input.actionKind) $projectResolved $taskRelative $taskIdentity $taskId $taskOwner ([string]$input.expectedProjectConfigIdentity) $continuationReceiptPath $continuationReceiptIdentity $forbiddenPaths $protectedPaths}
    $projectResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.projectRoot))))
    $controllerPath=Join-Path $projectResolved '.ai-workspace/controller.json';$controllerIdentity=if(Test-Path -LiteralPath $controllerPath -PathType Leaf){Get-Identity $controllerPath}else{'MISSING'}
    $authority=[ordered]@{schemaVersion=1;projectId=$composition.projectId;projectRoot=$auth.RepositoryRoot;repositoryGitTop=$auth.RepositoryGitTop;frameworkVersion='2.0.0';frameworkSealIdentity=$composition.releaseManifestIdentity;controllerIdentity=$controllerIdentity;taskIdentity=$taskIdentity;taskActor=$taskActor;actor=$actor;role=$effectiveRole;phase=$effectivePhase;profile=$profile;exactScope=@($input.exactPaths);forbiddenScope=@($forbiddenPaths);protectedScope=@($protectedPaths);authorizationIdentity=$auth.Identity;authorizedActions=@($auth.Actions);observedCapabilities=@($input.capabilities);projectConfigIdentity=$composition.projectConfigIdentity;correctionsIdentity=$composition.correctionsIdentity;policyIdentity=$composition.policyIdentity;userDecision=$userDecision;recoveryState=$recoveryState;hostEnforcementGrade=[string]$input.hostEnforcementGrade}
    if($inputContract-in@(4,5)){$authority=[ordered]@{schemaVersion=2;contextType=$contextType;contextLocator=$runtimeSegment;projectId=$composition.projectId;projectRoot=$projectResolved;repositoryGitTop=$auth.RepositoryGitTop;frameworkVersion='2.0.0';frameworkSealIdentity=$composition.releaseManifestIdentity;controllerIdentity=$controllerIdentity;taskIdentity=$taskIdentity;taskId=$taskId;taskOwner=$taskOwner;taskActor=$taskActor;actor=$actor;role=$effectiveRole;phase=$effectivePhase;profile=$profile;exactScope=@($input.exactPaths);forbiddenScope=@($forbiddenPaths);protectedScope=@($protectedPaths);authorizationIdentity=$auth.Identity;authorizedActions=@($auth.Actions);observedCapabilities=@($input.capabilities);projectConfigIdentity=$composition.projectConfigIdentity;correctionsIdentity=$composition.correctionsIdentity;policyIdentity=$composition.policyIdentity;userDecision=$userDecision;recoveryState=$recoveryState;hostEnforcementGrade=[string]$input.hostEnforcementGrade}}

    if($inputContract-eq5){
      $authority.schemaVersion=3
      $authority['controlRoot']=$projectResolved
      $authority['objectRoot']=if($executionContext.targetKind-ceq'GIT_WORKTREE'-and$input.actionKind-cne'CONTROL_WRITE'){$executionContext.executionRoot}else{$auth.RepositoryRoot}
      $authority['repositoryId']=if($configuration.controlPlaneLayout-ceq'repo-local'){'PROJECT'}else{$auth.RepositoryId}
      $authority['executionContext']=$executionContext
    }
    if([bool]$auth.HasContinuationPlan){$authority['continuationReceiptPath']=[string]$auth.ContinuationReceiptPath;$authority['continuationReceiptIdentity']=[string]$auth.ContinuationReceiptIdentity;$authority['continuationStepIndex']=[int]$auth.ContinuationStepIndex}
    $intentMaterial=$intent|ConvertTo-Json -Depth 30 -Compress
    $selectionMaterial=@($composition.sourceCompositionIdentity,$intentMaterial,[string]::Join("`n",@($input.capabilities)),[string]::Join("`n",@($input.exactPaths)),[string]::Join("`n",@($intentFactMismatches)))-join"`n"
    if($inputContract-eq5){$selectionMaterial+=Get-AiwContentDescriptorIdentity ([ordered]@{actor=$actor;role=$effectiveRole;phase=$effectivePhase;profile=$profile;selected=@($composition.selectedRequirements|Select-Object requirementId,preparationRequirements,resultRequirements,selectorIdentity)})}
    $selectionIdentity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($selectionMaterial)))
    $budgetContract=Get-ProcessBudgetContract
    $packJson=@($composition.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress;$packBytes=$utf8.GetByteCount($packJson)
    $selectedRulePackBytes=[int]$composition.selectedRulePackBytes;$absoluteSelectedRulePackBytes=[int]$budgetContract.absoluteSelectedRulePackBytes
    # Legacy budget fields remain identity-bound compatibility data, not quotas.
    # Return every selected complete rule regardless of its measured byte count.
    $contextMaterial=(($authority|ConvertTo-Json -Depth 30 -Compress)+"`n"+($intent|ConvertTo-Json -Depth 30 -Compress));$contextIdentity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($contextMaterial)))
    $ceilings=@($composition.evidenceCeilings);if([string]$input.hostEnforcementGrade-ceq'INSTRUCTION_BOUND'-or$invocationState-ceq'UNPROVEN'){$ceilings+='INVOCATION_UNPROVEN'};if([bool]$input.evaluationOnly){$ceilings+='NON_AUTHORITY_EVALUATION_ONLY'};if([string]$intent.ambiguityState-cne'CLEAR'){$ceilings+='INTENT_AMBIGUITY_CONSERVATIVE_LOAD'};if($intentFactMismatches.Count-gt0){$ceilings+='INTENT_FACT_MISMATCH_CONSERVATIVE_LOAD'};if($authority.repositoryGitTop-ceq'UNPROVEN'){$ceilings+='REPOSITORY_GIT_TOP_UNPROVEN'};if($artifactStorage-ceq'SYSTEM_TEMP_FALLBACK'){$ceilings+='SYSTEM_TEMP_FALLBACK'}

    $ruleLoadProjection=$null;$anticipated=@()
    if($inputContract-eq5){
      $ruleLoadProjection=Get-AiwRuleLoadProjection $composition $anticipated $input.ruleLoad $actor $projectResolved $forbiddenPaths
    }
    $selectedObligations=@($composition.selectedObligations|ForEach-Object{[ordered]@{requirementId=[string]$_.requirementId;preparationRequirements=@($_.preparationRequirements);resultRequirements=@($_.resultRequirements)}})
    if($inputContract-eq5-and$composition.sourceObservation.schemaVersion-eq2){$selectionIdentity=Get-OperationSelectionIdentity $composition.sourceCompositionIdentity $intent $authority $selectedObligations}
    $frameworkResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.frameworkRoot))))
    if($inputContract-in@(4,5)){
      $sourceBindings=[ordered]@{projectConfigIdentity=$composition.projectConfigIdentity;controllerIdentity=$composition.controllerIdentity;correctionsIdentity=$composition.correctionsIdentity;policyIdentity=$composition.policyIdentity;bootstrapManagedIdentity=$composition.bootstrapManagedIdentity;projectCustomIdentity=$composition.projectCustomIdentity;projectAgentsIdentity=$composition.projectAgentsIdentity;projectStandardsIdentity=$composition.projectStandardsIdentity;taskIdentity=$taskIdentity;frameworkVersionIdentity=$composition.frameworkVersionIdentity;releaseManifestIdentity=$composition.releaseManifestIdentity;candidatePilotStateIdentity=$composition.candidatePilotStateIdentity;nativeCatalogIdentity=$composition.nativeCatalogIdentity;contentSnapshotIdentity=$composition.contentSnapshotIdentity;effectiveSetIdentity=$composition.effectiveSetIdentity;implementationIdentity=$composition.implementationIdentity}
      $compactReceipt=[ordered]@{schemaVersion=3;receiptType='PROCESS_REQUIREMENTS_DISCOVER';status=[string]$composition.status;mode=$mode;inputContractVersion=$inputContract;sourceCompositionIdentity=$composition.sourceCompositionIdentity;selectionIdentity=$selectionIdentity;contextIdentity=$contextIdentity;binding=$authority;intentEnvelope=$intent;selectedObligations=$selectedObligations;pack=[ordered]@{bytes=$packBytes;ceilingBytes=$selectedRulePackBytes;estimatedTokens=[int][math]::Ceiling($packBytes/4.0)};sourceLocators=[ordered]@{frameworkRoot=$frameworkResolved;taskRelativePath=$taskRelative;authorizationPackagePath=$authorizationPath};sourceBindings=$sourceBindings;evidence=[ordered]@{ceilings=@($ceilings|Sort-Object -Unique);invocationState=$invocationState};counts=[ordered]@{sourceBuildCount=$composition.sourceBuildCount;legacyCorrectionsFullReadCount=$composition.legacyCorrectionsFullReadCount;legacyProjectCustomFullReadCount=$composition.legacyProjectCustomFullReadCount};authorityGranted=$false;semanticCorrectnessProven=$false}
      $result=[ordered]@{schemaVersion=3;resultType='PROCESS_REQUIREMENTS_DISCOVER_RESULT';status=[string]$composition.status;mode=$mode;artifactStorage=$artifactStorage;selectedRuleBlocks=@($composition.selectedRequirements);compactReceipt=$compactReceipt;normalizedFacets=$composition.intentFacets;facetVocabularyIdentity=$composition.facetVocabularyIdentity;selectionTrace=$composition.selectionTrace;legacySelectorDifferences=$composition.legacySelectorDifferences;readTrace=$composition.readTrace}
    }

    if($inputContract-eq5){
      $compactReceipt.schemaVersion=4
      $compactReceipt['sourceObservation']=$composition.sourceObservation
      $compactReceipt['bodyCoverage']=$ruleLoadProjection.bodyCoverage
      $compactReceipt['loadDecision']=$ruleLoadProjection.loadDecision
      $compactReceipt.counts.sourceBuildCount=1+$anticipated.Count
      $result.schemaVersion=4;$result['modelView']=$ruleLoadProjection.modelView
      if($composition.projectExternalAuthorization.configured){$result['projectExternalAuthorization']=$composition.projectExternalAuthorization}
    }
    if($null-ne$cleanupObservation-and[string]$cleanupObservation.Storage-ceq'PROJECT_RUNTIME'){$cleanupInput=[string]$cleanupObservation.Path}
  }elseif($mode-in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
    if(-not(Test-JsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-notin@(1,2,3)){throw 'INPUT_SCHEMA_VERSION'}
    $boundaryContract=[int]$input.schemaVersion
    $fields=if($boundaryContract-eq1){@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','objective','actionKind','resultKind','exactPaths','authorizationIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')}else{@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')}
    $deliveryObservation=$null
    $continuationDisposition='ADVANCE'
    if($null-ne$input.PSObject.Properties['continuationDisposition']){
      if($boundaryContract-ne3-or$mode-cne'FINALIZE_OUTPUT'-or$input.continuationDisposition-isnot[string]-or$input.continuationDisposition-cnotin@('ADVANCE','REPAIR','RETEST','STOP')){throw 'CONTINUATION_DISPOSITION_BOUNDARY'}
      $fields+='continuationDisposition';$continuationDisposition=$input.continuationDisposition
    }
    if($boundaryContract-eq3-and$null-ne$input.PSObject.Properties['evidenceRefs']){$fields+='evidenceRefs'}
    if($null-ne$input.PSObject.Properties['productionFinalizeRef']){
      if($boundaryContract-ne3){throw 'QUALITY_PRODUCTION_REF_BOUNDARY'}
      $fields+='productionFinalizeRef'
      Assert-Fields $input.productionFinalizeRef @('inputRef','resultRef')
      foreach($ref in @($input.productionFinalizeRef.inputRef,$input.productionFinalizeRef.resultRef)){Assert-Fields $ref @('path','identity');if($ref.path-isnot[string]-or$ref.identity-isnot[string]-or$ref.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'QUALITY_PRODUCTION_REF'}}
    }
    if($null-ne$input.PSObject.Properties['deliveryContext']){
      $fields+='deliveryContext';$deliveryObservation=Get-AiwDeliveryObservation $input.deliveryContext
      if($input.deliveryContext.stage-ceq'PREPARE'-and@($input.deliveryReceipts).Count){throw 'DELIVERY_FUTURE_EVIDENCE'}
    }
    if($null-ne$input.PSObject.Properties['actionRebind']){
      if($mode-cne'ADMIT_ACTION'-or$boundaryContract-ne3-or-not$CompactReceiptPath-or$null-ne$PublicationContext){throw 'ACTION_REBIND_BOUNDARY'}
      $fields+='actionRebind'
    }
    Assert-Fields $input $fields
    foreach($n in @('discoverReceiptPath','expectedDiscoverReceiptIdentity','publicDecisionIdentity','protectionState')){Assert-InputString $input.$n $n}
    if([string]$input.expectedDiscoverReceiptIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INPUT_IDENTITY|expectedDiscoverReceiptIdentity'}
    foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){Assert-StringArray $input.$name $name}
    $categoricalActions=@('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')
    if([string]$input.publicDecisionIdentity-cne'NOT_REQUIRED'-and[string]$input.publicDecisionIdentity-cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'PUBLIC_DECISION_IDENTITY'}
    if([string]$input.protectionState-cnotin@('BOUND','NOT_APPLICABLE')){throw 'PROTECTION_STATE'}
    $receiptIdentity=Get-Identity ([string]$input.discoverReceiptPath);if($receiptIdentity-cne[string]$input.expectedDiscoverReceiptIdentity){throw 'DISCOVER_RECEIPT_DRIFT'}
    $receipt=Get-Receipt ([string]$input.discoverReceiptPath)
    if($receipt.contextType-ceq'PROJECT_EXTERNAL'){throw 'PROJECT_EXTERNAL_LOAD_HAS_NO_ACTION_BOUNDARY'}
    if($null-ne$input.PSObject.Properties['actionRebind']){
      $rebound=New-ActionRebindCompact $receipt $input.actionRebind $input.discoverReceiptPath
      $reboundCompact=$rebound.compact
      $rebindAuthorization=$rebound.authorization
      $receipt=Convert-ActionRebindView $receipt $reboundCompact
    }
    if('SOURCE_VALIDATION_SELECTED_CLOSURE_V1'-cnotin@($receipt.evidenceCeilings)){throw 'SOURCE_VALIDATION_SCOPE_UNBOUND|FRESH_DISCOVER_REQUIRED'}
    if([int]$receipt.schemaVersion-notin@(3,4)){throw 'ORIGINAL_PROCESS_RESOLVER_REQUIRED'}
    $controlTransitionFinalization=$null
    if($mode-ceq'FINALIZE_OUTPUT'-and[string]$receipt.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){
      $controlPackage=Read-Input ([string]$receipt.sourceLocators.authorizationPackagePath)
      if($null-ne$controlPackage.PSObject.Properties['transitionPlan']){$controlTransitionFinalization=Get-AiwControlTransitionFinalization $controlPackage $receipt $inputFull}
    }
    if($null-eq$controlTransitionFinalization){Assert-AiwNoControlTransition ([string]$receipt.sourceLocators.projectRoot) $(if([string]$receipt.sourceLocators.taskRelativePath-cne'NOT_APPLICABLE'){[string]$receipt.sourceLocators.taskRelativePath}else{''})}
    if($boundaryContract-eq1){foreach($n in @('objective','actionKind','resultKind','authorizationIdentity')){Assert-InputString $input.$n $n};Assert-ExactPaths $input.exactPaths;Assert-ActionAndResult ([string]$input.actionKind) ([string]$input.resultKind);if([string]$input.authorizationIdentity-cne'NOT_REQUIRED'-and[string]$input.authorizationIdentity-cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'AUTHORIZATION_RECEIPT_IDENTITY'}}
    else{$input|Add-Member -NotePropertyName objective -NotePropertyValue ([string]$receipt.objective);$input|Add-Member -NotePropertyName actionKind -NotePropertyValue ([string]$receipt.actionKind);$input|Add-Member -NotePropertyName resultKind -NotePropertyValue ([string]$receipt.resultKind);$input|Add-Member -NotePropertyName exactPaths -NotePropertyValue @($receipt.exactPaths);$input|Add-Member -NotePropertyName authorizationIdentity -NotePropertyValue ([string]$receipt.authorityContext.authorizationIdentity)}
    if($null-ne$cleanupObservation-and[string]$cleanupObservation.Storage-ceq'PROJECT_RUNTIME'){
      $runtimeBinding=if($null-ne$receipt.authorityContext.PSObject.Properties['contextLocator']){[string]$receipt.authorityContext.contextLocator}else{[string]$receipt.taskId}
      Assert-ProjectRuntimeCleanupBinding $cleanupObservation ([string]$receipt.sourceLocators.projectRoot) $runtimeBinding ([string]$receipt.actor)
      $cleanupInput=[string]$cleanupObservation.Path
    }
    # Prove the admitted, restricted carrier change before the ordinary
    # snapshot can read any newly declared source or content cache.
    $sourceChangeRollback='PROJECT_SOURCE_ROLLBACK'-cin@($input.preparationReceipts)
    if($sourceChangeRollback-and$mode-cne'FINALIZE_OUTPUT'){throw 'SOURCE_CHANGE_ROLLBACK_BOUNDARY'}
    $sourceStage=if($mode-ceq'ADMIT_ACTION'){'ADMIT'}else{'FINALIZE'}
    if($null-ne$PublicationContext){
      $sourceChange=& $composerModule {param($r,$b,$s,$rollback,$context) Get-AiwProjectSourceChangeCore $r $b $s -Rollback:$rollback -PublicationContext $context} $receipt $input $sourceStage $sourceChangeRollback $PublicationContext
    }else{
      $sourceChange=Get-AiwProjectSourceChange -Receipt $receipt -Boundary $input -Stage $sourceStage -Rollback:$sourceChangeRollback
    }
    if($sourceChangeRollback-and$null-eq$sourceChange){throw 'SOURCE_CHANGE_ROLLBACK_UNBOUND'}

    $evidenceModule=@(Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1') -PassThru)[0]
    $archiveObservation=& $evidenceModule {param($r,$b) Get-EvTaskArchiveObservation $r $b} $receipt $input
    $taskObservationPath=if($null-ne$archiveObservation){$archiveObservation.TaskRelativePath}else{[string]$receipt.sourceLocators.taskRelativePath}

    if($receipt.schemaVersion-eq4){
      $a=$receipt.authorityContext
      if($a.controlRoot-cne$a.projectRoot){throw 'EXECUTION_TARGET_CONTROL_BINDING'}
      Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
      $fresh=Resolve-AiwExecutionTargetContext -ProjectRoot $a.controlRoot -ProjectId $a.projectId -TaskPath $taskObservationPath -ExecutionTargetRef $a.executionContext.executionTargetRef -ForbiddenPaths @($a.forbiddenScope) -ProtectedPaths @($a.protectedScope)
      if($fresh.targetKind-cne$a.executionContext.targetKind-or$fresh.executionRoot-cne$a.executionContext.executionRoot){throw 'EXECUTION_TARGET_CONTEXT_DRIFT'}
      if($fresh.targetKind-ceq'GIT_WORKTREE'){
        foreach($key in @('descriptorIdentity','commonGitDir','worktreeGitDir','gitTop','overridesAbsent')){if($fresh.targetObservation.$key-cne$a.executionContext.targetObservation.$key){throw 'EXECUTION_TARGET_STATE_DRIFT'}}
        $allowCommit=$mode-ceq'FINALIZE_OUTPUT'-and$receipt.actionKind-ceq'GIT_COMMIT'
        if($allowCommit){foreach($relative in $receipt.exactPaths){$null=Resolve-AiwExecutionTargetCandidatePath $fresh $relative @($a.forbiddenScope) @($a.protectedScope)}}
        $null=Assert-AiwExecutionTargetState $fresh (Get-AiwExecutionTargetState $a.executionContext) $receipt.actionKind -AllowCommitPostimage:$allowCommit -ExactPaths @($receipt.exactPaths)
        if($receipt.actionKind-ceq'CONTROL_WRITE'){
          if($a.objectRoot-cne$a.controlRoot){throw 'EXECUTION_TARGET_CONTROL_OBJECT_ROOT'}
        }else{
          if($a.objectRoot-cne$fresh.executionRoot){throw 'EXECUTION_TARGET_OBJECT_ROOT_DRIFT'}
          if($receipt.actionKind-cne'NONE'){
            $targetPackage=Read-Input $receipt.sourceLocators.authorizationPackagePath
            $null=Resolve-AiwPackageExecutionTarget $a.controlRoot $targetPackage $receipt.sourceLocators.taskRelativePath $a.forbiddenScope $a.protectedScope -AllowCommitPostimage:$allowCommit
          }
        }
      }elseif($a.objectRoot-cne(Get-AuthorizationRepositoryRoot $(if($receipt.sourceLocators.authorizationPackagePath-ceq'NOT_REQUIRED'){[pscustomobject]@{schemaVersion=1}}else{Read-Input $receipt.sourceLocators.authorizationPackagePath}) $a.controlRoot)){throw 'AUTHORIZATION_REPOSITORY_DRIFT'}
    }
    $selectionContext=[pscustomobject]@{profile=$receipt.profile;role=$receipt.role;phase=$receipt.phase;actor=$receipt.actor;actionKind=$receipt.actionKind;resultKind=$receipt.resultKind;exactPaths=@($receipt.exactPaths);capabilities=@($receipt.authorityContext.observedCapabilities);intentEnvelope=$receipt.intentEnvelope}
    if($mode-ceq'FINALIZE_OUTPUT'-and$null-ne$sourceChange-and-not$sourceChangeRollback){
      # The admitted target projection validated this actual target capability
      # set; it may differ from the original pre-change declaration.
      $selectionContext.capabilities=@($sourceChange.target.composition.declaredCapabilities)
    }
    if($null-ne$controlTransitionFinalization){
      # The original chain already rebuilt and verified this call's original selection.
      $currentBindings=$controlTransitionFinalization.Chain.Snapshot
    }else{
      $observation=if($null-ne$receipt.PSObject.Properties['sourceObservation']-and$null-eq$sourceChange){$receipt.sourceObservation}else{$null}
      if($null-ne$observation-and$observation.schemaVersion-eq2){
        if($null-ne$reboundCompact){$currentBindings=$rebound.bindings}
        else{
          $operationFacts=& $composerModule {param($p,$f,$t,$denied,$s,$o)Get-AiwProcessBindingSnapshotCore -ProjectRoot $p -FrameworkRoot $f -TargetVersion '2.0.0' -TaskRelativePath $t -ForbiddenPaths $denied -SelectionContext $s -RuleObservation $o -IncludeOperationFacts} $receipt.sourceLocators.projectRoot $receipt.sourceLocators.frameworkRoot $taskObservationPath @($receipt.authorityContext.forbiddenScope) $selectionContext $observation
          $currentBindings=$operationFacts.bindings
        }
      }else{
      $currentBindings=Get-AiwProcessBindingSnapshot -ProjectRoot ([string]$receipt.sourceLocators.projectRoot) -FrameworkRoot ([string]$receipt.sourceLocators.frameworkRoot) -TargetVersion '2.0.0' -TaskRelativePath $taskObservationPath -ForbiddenPaths @($receipt.authorityContext.forbiddenScope) -SelectionContext $selectionContext -RuleObservation $observation -RequireNoBody:($null-ne$reboundCompact)
      }
    }
    if($mode-ceq'FINALIZE_OUTPUT'-and$null-ne$sourceChange-and-not$sourceChangeRollback){
      foreach($name in @('projectConfigIdentity','policyIdentity','projectStandardsIdentity','contentSnapshotIdentity','effectiveSetIdentity')){
        if($currentBindings.$name-cne$sourceChange.candidate.target.$name){throw ('SOURCE_CHANGE_CURRENT_TARGET_DRIFT|'+$name)}
      }
    }
    if($null-eq$receipt.sourceBindings.PSObject.Properties['projectAgentsIdentity']-and[string]$currentBindings.projectAgentsIdentity-cne'MISSING'){throw 'PROJECT_AGENTS_BINDING_REQUIRED'}
    $changedBindings=@($receipt.sourceBindings.PSObject.Properties.Name|Where-Object{[string]$currentBindings.$_-cne[string]$receipt.sourceBindings.$_})
    $taskPostimageTransition=$false
    if($null-eq$controlTransitionFinalization-and[string]$receipt.sourceLocators.taskRelativePath-cne'NOT_APPLICABLE'-and$mode-ceq'FINALIZE_OUTPUT'-and[string]$currentBindings.taskIdentity-cne[string]$receipt.sourceBindings.taskIdentity){
      if([int]$receipt.inputContractVersion-lt2-or[string]$receipt.actionKind-cne'CONTROL_WRITE'-or[string]$receipt.sourceLocators.authorizationPackagePath-ceq'NOT_REQUIRED'-or($null-eq$archiveObservation-and(@($receipt.exactPaths).Count-ne1-or[string]$receipt.exactPaths[0]-cne[string]$receipt.sourceLocators.taskRelativePath))){throw 'DISCOVER_SOURCE_DRIFT|taskIdentity'}
      $transitionPackage=Read-Input ([string]$receipt.sourceLocators.authorizationPackagePath)
      $transitionSchema=if(Test-JsonInteger $transitionPackage.schemaVersion){[int]$transitionPackage.schemaVersion}else{0}
      $transitionCarrierAllowed=$transitionSchema-eq1-or($transitionSchema-eq2-and$null-ne$transitionPackage.PSObject.Properties['repositoryId']-and[string]$transitionPackage.repositoryId-ceq'CONTROL')
      if(-not$transitionCarrierAllowed-or@($transitionPackage.actions).Count-ne1-or[string]$transitionPackage.actions[0]-cne'CONTROL_WRITE'-or($null-eq$archiveObservation-and(@($transitionPackage.exactPaths).Count-ne1-or[string]$transitionPackage.exactPaths[0]-cne[string]$receipt.sourceLocators.taskRelativePath))-or[string]$receipt.actor-cne[string]$receipt.taskActor){throw 'CONTROL_TASK_POSTIMAGE_TRANSITION_NOT_AUTHORIZED'}
      $currentTaskBinding=Get-TaskBindingObservation ([string]$receipt.sourceLocators.projectRoot) $taskObservationPath
      if([string]$currentTaskBinding.TaskId-cne[string]$receipt.taskId-or[string]$currentTaskBinding.Owner-cne[string]$receipt.taskOwner-or[string]$currentTaskBinding.TaskActor-cne[string]$receipt.taskActor-or[string]$currentTaskBinding.Role-cne[string]$receipt.role-or[string]$currentTaskBinding.Phase-cne[string]$receipt.phase-or[string]$currentTaskBinding.Profile-cne[string]$receipt.profile){throw 'CONTROL_TASK_POSTIMAGE_BINDING_DRIFT'}
      $taskPostimageTransition=$true
    }
    $sourcePostimageTransition=$null
    $publicationFinalization=$null-ne$sourceChange-and$null-ne$sourceChange.PSObject.Properties['publication']-and$sourceChange.publication
    $sourceTransitionEligible=$mode-ceq'FINALIZE_OUTPUT'-and[int]$receipt.inputContractVersion-ge2-and([string]$receipt.actionKind-ceq'CONTROL_WRITE'-or$publicationFinalization)-and[string]$receipt.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'
    $sourceBindings=@()
    foreach($name in @($changedBindings)){
      if($null-ne$controlTransitionFinalization-and[string]$name-in@('taskIdentity','controllerIdentity')){continue}
      if($taskPostimageTransition){if([string]$name-ceq'taskIdentity'){continue};throw ('DISCOVER_SOURCE_DRIFT|'+[string]$name)}
      if($sourceTransitionEligible-and$null-ne$sourceChange-and-not$sourceChangeRollback-and$name-ceq'projectConfigIdentity'){$sourceBindings+=$name;continue}
      if($sourceTransitionEligible-and[string]$name-in@('correctionsIdentity','policyIdentity','projectStandardsIdentity','projectCustomIdentity','projectAgentsIdentity','contentSnapshotIdentity','effectiveSetIdentity')){$sourceBindings+=[string]$name;continue}
      throw ('DISCOVER_SOURCE_DRIFT|'+[string]$name)
    }
    if($null-eq$sourceChange-and'projectStandardsIdentity'-cin$sourceBindings-and'policyIdentity'-cnotin$sourceBindings){throw 'DISCOVER_SOURCE_DRIFT|projectStandardsIdentity'}
    if($null-eq$sourceChange-and'contentSnapshotIdentity'-cin$sourceBindings-and'policyIdentity'-cnotin$sourceBindings){throw 'DISCOVER_SOURCE_DRIFT|contentSnapshotIdentity'}
    if($null-eq$sourceChange-and'effectiveSetIdentity'-cin$sourceBindings-and@($sourceBindings|Where-Object{$_-cin@('correctionsIdentity','policyIdentity','projectCustomIdentity')}).Count-eq0){throw 'DISCOVER_SOURCE_DRIFT|effectiveSetIdentity'}
    if('projectCustomIdentity'-cin$sourceBindings){
      $oldManaged=''
      if($null-ne$receipt.sourceBindings.PSObject.Properties['bootstrapManagedIdentity']){
        $oldManaged=[string]$receipt.sourceBindings.bootstrapManagedIdentity
      }else{
        # A pre-existing admitted action can use its exact original package-bound
        # Bootstrap bytes. This does not rewrite or replace the original receipt.
        $proofs=@($input.preparationReceipts|Where-Object{$_-clike'BOOTSTRAP_PREIMAGE|*'})
        if($proofs.Count-ne1-or[string]$proofs[0]-cnotmatch'^BOOTSTRAP_PREIMAGE\|([^|]+)\|(\d+\|[A-F0-9]{64})$'){throw 'SOURCE_POSTIMAGE_BOOTSTRAP_PREIMAGE_UNBOUND'}
        $oldPath=[IO.Path]::GetFullPath($Matches[1]);$oldIdentity=$Matches[2]
        $control=[IO.Path]::GetFullPath([string]$receipt.sourceLocators.projectRoot)
        $allowedRoot=Join-Path $control '.ai-workspace'
        if(-not$oldPath.StartsWith($allowedRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_POSTIMAGE_BOOTSTRAP_PREIMAGE_PATH'}
        $cursor=$allowedRoot
        foreach($part in $oldPath.Substring($allowedRoot.Length+1).Split([IO.Path]::DirectorySeparatorChar)){
          $cursor=Join-Path $cursor $part
          if(((Get-Item -LiteralPath $cursor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'SOURCE_POSTIMAGE_BOOTSTRAP_PREIMAGE_REPARSE'}
        }
        $package=Read-Input ([string]$receipt.sourceLocators.authorizationPackagePath)
        $entry=@($package.objectIdentities|Where-Object{[string]$_.path-ceq'.ai-workspace/BOOTSTRAP.md'})
        if($entry.Count-ne1-or[string]$entry[0].identity-cne$oldIdentity-or(Get-Identity $oldPath)-cne$oldIdentity){throw 'SOURCE_POSTIMAGE_BOOTSTRAP_PREIMAGE_IDENTITY'}
        $oldCustom=Get-AiwProjectCustomRegion $oldPath
        if([string]$oldCustom.Identity-cne[string]$receipt.sourceBindings.projectCustomIdentity){throw 'SOURCE_POSTIMAGE_BOOTSTRAP_PREIMAGE_SOURCE'}
        $oldManaged=[string]$oldCustom.ManagedIdentity
      }
      if($oldManaged-cne[string]$currentBindings.bootstrapManagedIdentity){throw 'SOURCE_POSTIMAGE_BOOTSTRAP_MANAGED_DRIFT'}
    }
    if([int]$receipt.inputContractVersion-ge2-and[string]$receipt.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){
      $currentAuthorizationIdentity=Get-Identity ([string]$receipt.sourceLocators.authorizationPackagePath);if($currentAuthorizationIdentity-cne[string]$receipt.authorityContext.authorizationIdentity){throw 'DISCOVER_SOURCE_DRIFT|authorizationIdentity'}
      $boundaryContinuationPath='NOT_REQUIRED';$boundaryContinuationIdentity='NOT_REQUIRED'
      if($null-ne$receipt.authorityContext.PSObject.Properties['continuationReceiptPath']){
        $boundaryContinuationPath=[string]$receipt.authorityContext.continuationReceiptPath;$boundaryContinuationIdentity=[string]$receipt.authorityContext.continuationReceiptIdentity
        if($boundaryContinuationPath-cne'NOT_REQUIRED'){$currentContinuationIdentity=Get-Identity $boundaryContinuationPath;if($currentContinuationIdentity-cne$boundaryContinuationIdentity){throw 'DISCOVER_SOURCE_DRIFT|continuationReceiptIdentity'};$boundaryContinuation=Read-Input $boundaryContinuationPath;if([string]$boundaryContinuation.protectionState-cne[string]$input.protectionState){throw 'CONTINUATION_PROTECTION_STATE_DRIFT'}}
      }
      if($mode-ceq'ADMIT_ACTION'-and$null-eq$rebindAuthorization){
        $taskBinding=Get-TaskBindingObservation ([string]$receipt.sourceLocators.projectRoot) ([string]$receipt.sourceLocators.taskRelativePath)
        $null=Get-AuthorizationObservation ([string]$receipt.sourceLocators.authorizationPackagePath) ([string]$receipt.authorityContext.authorizationIdentity) ([string]$receipt.actor) @($receipt.exactPaths) ([string]$receipt.authorityContext.userDecision) ([string]$receipt.actionKind) ([string]$receipt.sourceLocators.projectRoot) ([string]$receipt.sourceLocators.taskRelativePath) ([string]$receipt.taskIdentity) ([string]$taskBinding.TaskId) ([string]$taskBinding.Owner) ([string]$receipt.sourceBindings.projectConfigIdentity) $boundaryContinuationPath $boundaryContinuationIdentity $receipt.authorityContext.forbiddenScope $receipt.authorityContext.protectedScope
      }
      if($mode-ceq'FINALIZE_OUTPUT'){Assert-AuthorizationPostimages ([string]$receipt.sourceLocators.authorizationPackagePath) ([string]$receipt.sourceLocators.projectRoot) @($receipt.exactPaths) @($input.resultReceipts) $taskObservationPath $receipt.authorityContext.forbiddenScope $receipt.authorityContext.protectedScope -AllowCommitPostimage:($receipt.actionKind-ceq'GIT_COMMIT')}
    }
    $controlTransitionCompositions=@()
    if($sourceBindings.Count-gt0-or$null-ne$controlTransitionFinalization){
      $sourcePathByBinding=@{correctionsIdentity='.ai-workspace/corrections.json';policyIdentity='.ai-workspace/process-policy.json';projectCustomIdentity='.ai-workspace/BOOTSTRAP.md';projectAgentsIdentity='AGENTS.md'}
      foreach($name in @($sourceBindings|Where-Object{$_-in@('correctionsIdentity','policyIdentity','projectCustomIdentity','projectAgentsIdentity')})){
        $publicationCarrier=$publicationFinalization-and$name-ceq'policyIdentity'-and@($sourceChange.candidate.objects|Where-Object{$_.ownerMember-ceq'CONTROL'-and$_.path-ceq'.ai-workspace/process-policy.json'}).Count-eq1
        if(-not$publicationCarrier-and[string]$sourcePathByBinding[[string]$name]-cnotin@($receipt.exactPaths)){throw ('SOURCE_POSTIMAGE_PATH_NOT_AUTHORIZED|'+[string]$name)}
      }
      $semanticObjective=Get-AiwProcessSemanticText -IntentEnvelope $receipt.intentEnvelope
      if($null-ne$controlTransitionFinalization){
        $controlTransitionCompositions=@(Get-AiwControlTransitionCompositions $controlTransitionFinalization.Context $controlTransitionFinalization.Chain.Discover)
        $transitionComposition=$controlTransitionCompositions[0]
      }else{
        $transitionComposition=Invoke-ProcessRequirementComposition -ProjectRoot ([string]$receipt.sourceLocators.projectRoot) -FrameworkRoot ([string]$receipt.sourceLocators.frameworkRoot) -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity ([string]$currentBindings.projectConfigIdentity) -ExpectedCorrectionsIdentity ([string]$currentBindings.correctionsIdentity) -Profile ([string]$receipt.profile) -Role ([string]$receipt.role) -Phase ([string]$receipt.phase) -Actor ([string]$receipt.actor) -TaskIdentity ([string]$currentBindings.taskIdentity) -Capabilities @($receipt.authorityContext.observedCapabilities) -UseDeclaredCapabilities:($null-ne$sourceChange-and-not$sourceChangeRollback) -ValidateCompleteAdoptedSet:($null-eq$sourceChange-and@($sourceBindings|Where-Object{$_-cin@('correctionsIdentity','policyIdentity','projectCustomIdentity')}).Count-gt0) -IntentEnvelope $receipt.intentEnvelope -Objective $semanticObjective -ActionKind ([string]$receipt.actionKind) -ResultKind ([string]$receipt.resultKind) -ExactPaths @($receipt.exactPaths) -ForbiddenPaths @($receipt.authorityContext.forbiddenScope) -SemanticApplicabilityUnknown:([string]$receipt.intentEnvelope.ambiguityState-cne'CLEAR') -EvaluationOnly:([string]$receipt.status-ceq'EVALUATION_ONLY')
      }
      if($null-ne$controlTransitionFinalization){
        # Each target verifies its own selected closure. Only shared raw authority
        # crosses selections; task postimages are bound by the transition plan.
        foreach($composition in $controlTransitionCompositions){
          foreach($name in @($receipt.sourceBindings.PSObject.Properties.Name)){
            if($name-cin@('taskIdentity','projectStandardsIdentity','contentSnapshotIdentity','effectiveSetIdentity')){continue}
            if([string]$composition.$name-cne[string]$currentBindings.$name){throw ('SOURCE_POSTIMAGE_RECOMPOSITION_BINDING_DRIFT|'+[string]$name)}
          }
          if('PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD'-cin@($composition.evidenceCeilings)){throw 'SOURCE_POSTIMAGE_PROJECT_STANDARD_DRIFT'}
        }
      }else{
        foreach($name in @($receipt.sourceBindings.PSObject.Properties.Name)){
          $recomposedBinding=if([string]$name-ceq'taskIdentity'){[string]$currentBindings.taskIdentity}else{[string]$transitionComposition.$name}
          if($recomposedBinding-cne[string]$currentBindings.$name){throw ('SOURCE_POSTIMAGE_RECOMPOSITION_BINDING_DRIFT|'+[string]$name)}
        }
        if('PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD'-cin@($transitionComposition.evidenceCeilings)){throw 'SOURCE_POSTIMAGE_PROJECT_STANDARD_DRIFT'}
      }
      if($null-ne$sourceChange-and-not$sourceChangeRollback-and(Get-AiwSourceChangeSelectionIdentity @($transitionComposition.selectedRequirements) @($transitionComposition.selectedObligations))-cne$sourceChange.candidate.target.selectedRulesIdentity){throw 'SOURCE_CHANGE_CURRENT_SELECTION_DRIFT'}
      $transitionPackJson=@($transitionComposition.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress
      $transitionPackBytes=$utf8.GetByteCount($transitionPackJson)
      # Source identity, complete composition and obligations still gate the transition.
      $sourcePostimageTransition=[ordered]@{status='PASS';previousSourceCompositionIdentity=[string]$receipt.sourceCompositionIdentity;currentSourceCompositionIdentity=[string]$transitionComposition.sourceCompositionIdentity;changedBindings=@($sourceBindings|Sort-Object);selectedPackBytes=$transitionPackBytes;selectedRequirementCount=@($transitionComposition.selectedRequirements).Count}
    }
    if($null-eq$reboundCompact-and$null-eq$sourcePostimageTransition-and$null-eq$sourceChange-and$null-eq$controlTransitionFinalization-and$null-ne$receipt.PSObject.Properties['sourceObservation']-and$receipt.sourceObservation.schemaVersion-eq2){
      if((Get-AiwContentDescriptorIdentity @($operationFacts.selectedObligations))-cne(Get-AiwContentDescriptorIdentity @($receipt.selectedObligations))){throw 'DISCOVER_CURRENT_OBLIGATIONS_DRIFT'}
    }
    if([string]$input.objective-cne[string]$receipt.objective-or[string]$input.actionKind-cne[string]$receipt.actionKind-or[string]$input.resultKind-cne[string]$receipt.resultKind-or[string]::Join("`n",@($input.exactPaths))-cne[string]::Join("`n",@($receipt.exactPaths))){throw 'DISCOVER_CONTEXT_DRIFT'}
    $requiredPrep=@($receipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $requiredResult=@($receipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    if($null-ne$sourceChange-and-not$sourceChangeRollback){
      $requiredPrep=@($requiredPrep+@($sourceChange.target.composition.selectedObligations.preparationRequirements)|Sort-Object -Unique)
      $requiredResult=@($requiredResult+@($sourceChange.target.composition.selectedObligations.resultRequirements)|Sort-Object -Unique)
    }
    if($null-ne$sourcePostimageTransition){
      $requiredPrep=@($requiredPrep+@($transitionComposition.selectedObligations|ForEach-Object{@($_.preparationRequirements)})|Sort-Object -Unique)
      $requiredResult=@($requiredResult+@($transitionComposition.selectedObligations|ForEach-Object{@($_.resultRequirements)})|Sort-Object -Unique)
    }
    foreach($composition in $controlTransitionCompositions){
      $requiredPrep=@($requiredPrep+@($composition.selectedObligations|ForEach-Object{@($_.preparationRequirements)})|Sort-Object -Unique)
      $requiredResult=@($requiredResult+@($composition.selectedObligations|ForEach-Object{@($_.resultRequirements)})|Sort-Object -Unique)
    }
    $finalEvidenceContext=$null
    if($mode-ceq'FINALIZE_OUTPUT'-and$receipt.schemaVersion-eq4-and$receipt.actionKind-ceq'GIT_COMMIT'-and$fresh.targetKind-ceq'GIT_WORKTREE'){
      # The original exact-path commit/tree proof above has already validated
      # this real postcommit state. Carry it into evidence/retention instead of
      # reopening the original precommit HEAD as a new target observation.
      $commitPackage=Read-Input $receipt.sourceLocators.authorizationPackagePath
      $finalEvidenceContext=New-AiwPackageEvidenceContext $receipt.sourceLocators.projectRoot $commitPackage $receipt.sourceLocators.frameworkRoot $receipt.authorityContext.forbiddenScope -TaskPath $taskObservationPath -TargetState (Get-AiwExecutionTargetState $fresh) -ProtectedPaths $receipt.authorityContext.protectedScope
    }
    $evidenceObservation=Get-AiwBoundaryEvidence $receipt $input -EvidenceContext $finalEvidenceContext
    $selfCheckOutcome=Get-AiwSelfCheckOutcome $evidenceObservation.references $evidenceObservation.records
    if($mode-ceq'ADMIT_ACTION'-and$receipt.actionKind-ceq'REVIEW_ROUTE'){$null=Assert-AiwReviewRoutePreparation $receipt $input $evidenceObservation}
    $boundDelivery=$null
    if($mode-ceq'FINALIZE_OUTPUT'){$boundDelivery=Get-AiwBoundDelivery $receipt $input $evidenceObservation}
    # Typed gates cannot be satisfied by copying their obligation names.
    $typedNames=@('SELF_CHECK_BOUND','REVIEW_PREPARATION_BOUND','REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED')
    $providedPrep=@($input.preparationReceipts|Where-Object{$_-cnotin$typedNames});$providedResult=@($input.resultReceipts|Where-Object{$_-cnotin$typedNames})
    $evidenceKinds=@($evidenceObservation.references|ForEach-Object{$_.kind})
    if('SELF_CHECK'-cin$evidenceKinds){$providedPrep+='SELF_CHECK_BOUND'}
    if($receipt.actionKind-ceq'REVIEW_ROUTE'){$providedPrep+='REVIEW_PREPARATION_BOUND'}
    if('REVIEW_VERDICT'-cin$evidenceKinds){$providedResult+='REVIEW_VERDICT_BOUND'}
    if('RESULT_ACCEPTANCE'-cin$evidenceKinds){$providedResult+='RESULT_ACCEPT_RECORDED'}
    $missingPrep=@($requiredPrep|Where-Object{$_-cnotin$providedPrep})
    if([int]$receipt.inputContractVersion-eq1-and[string]$receipt.actionKind-in$categoricalActions){$missingPrep+='LEGACY_AUTHORITY_CONTEXT_UNBOUND'}
    if([int]$receipt.inputContractVersion-ge2-and[string]$receipt.actionKind-in$categoricalActions-and[string]$receipt.actionKind-cnotin@($receipt.authorityContext.authorizedActions)){$missingPrep+='ACTION_NOT_AUTHORIZED_IN_CONTEXT'}
    if([int]$receipt.inputContractVersion-ge2-and[string]$input.authorizationIdentity-cne[string]$receipt.authorityContext.authorizationIdentity){throw 'AUTHORIZATION_CONTEXT_DRIFT'}
    if([int]$receipt.inputContractVersion-ge2-and[string]$receipt.intentEnvelope.ambiguityState-cne'CLEAR'){$missingPrep+='INTENT_AMBIGUOUS'}
    if([int]$receipt.inputContractVersion-ge2-and[string]$receipt.authorityContext.repositoryGitTop-ceq'UNPROVEN'-and[string]$receipt.actionKind-in@('GIT_STAGE','GIT_COMMIT','PUSH')){$missingPrep+='REPOSITORY_GIT_TOP_UNPROVEN'}
    $missingResult=@()
    if($mode-ceq'FINALIZE_OUTPUT'){
      if($null-ne$deliveryObservation){$requiredResult=@($requiredResult|Where-Object{$_-cne'DELIVERY_RECEIPT'})}
      $missingResult=@($requiredResult|Where-Object{$_-cnotin$providedResult})
    }
    if($mode-ceq'FINALIZE_OUTPUT'-and$null-eq$deliveryObservation-and[string]$input.resultKind-in@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','RESULT_ACCEPTANCE')-and@($input.deliveryReceipts).Count-eq0){$missingResult+=@('DELIVERY_RECEIPT')}
    if($null-ne$boundDelivery-and-not$boundDelivery.closureSatisfied){$missingResult+=@('DELIVERY_NOT_CONFIRMED')}
    $status=if($missingPrep.Count-gt0-or$missingResult.Count-gt0){'BLOCKED'}else{'PASS'}
    $reason=if($missingPrep.Count-gt0){'PREPARATION_INCOMPLETE'}elseif($missingResult.Count-gt0){'RESULT_INCOMPLETE'}else{'STRUCTURAL_REQUIREMENTS_COMPLETE'}
    $decision=Get-AiwProcessDecisionIdentity $receipt $input $(if($null-eq$sourcePostimageTransition){'NO_SOURCE_POSTIMAGE_TRANSITION'}else{[string]$sourcePostimageTransition.currentSourceCompositionIdentity}) @($changedBindings)
    $result=[ordered]@{status=$status;mode=$mode;reason=$reason;artifactStorage=$artifactStorage;selectionIdentity=$receipt.selectionIdentity;decisionIdentity=$decision;sourceBuildCount=[int]$receipt.sourceBuildCount;decisionBuildCount=1;missingPreparation=@($missingPrep);missingResult=@($missingResult);authorityGranted=$false;semanticCorrectnessProven=$false;hostInvocationProven=$false}
    if($null-ne$sourceChange){$result['projectSourcePreparation']=[ordered]@{candidateIdentity=$sourceChange.reference.identity;targetIdentity=(Get-AiwContentDescriptorIdentity $sourceChange.candidate.target);outcome=$(if($mode-ceq'ADMIT_ACTION'){'PREPARED'}elseif($sourceChangeRollback){'ROLLED_BACK'}else{'COMPLETED'})}}
    if($null-ne$deliveryObservation){$result['delivery']=$deliveryObservation}
    if($null-ne$boundDelivery){$result['consumer']=$boundDelivery.consumer}
    if($null-ne$sourcePostimageTransition){$result['sourcePostimageTransition']=$sourcePostimageTransition;$result.sourceBuildCount=[int]$receipt.sourceBuildCount+[int]$transitionComposition.sourceBuildCount}
    if($mode-ceq'FINALIZE_OUTPUT'-and$status-ceq'PASS'){
      if($null-ne$controlTransitionFinalization){$result['controlTransitionCompletion']=Save-AiwControlTransitionCompletion $controlTransitionFinalization $result $inputFull}
      $continuation=New-AuthorizationContinuationReceipt ([string]$receipt.sourceLocators.authorizationPackagePath) ([string]$receipt.sourceLocators.projectRoot) $receipt ([string]$input.discoverReceiptPath) $receiptIdentity ([string]$input.protectionState) @($evidenceObservation.references) $continuationDisposition $selfCheckOutcome
      if($receipt.schemaVersion-eq4-and$receipt.authorityContext.executionContext.targetKind-ceq'GIT_WORKTREE'-and$receipt.actionKind-cne'CONTROL_WRITE'){$result['postTargetState']=Get-AiwExecutionTargetState $fresh}
      $result['actionOutcome']=if($receipt.actionKind-ceq'TEST_RUN'){$selfCheckOutcome}else{'OBSERVED'}
      $result['successorState']=$continuation.state
      if($null-ne$continuation.receipt){$result['continuationReceipt']=$continuation.receipt}
    }
  }else{throw 'INPUT_MODE'}
  if($CompactReceiptPath){
    if($mode-ceq'DISCOVER'){$result['savedCompactReceipt']=Save-CompactReceipt $compactReceipt $CompactReceiptPath $projectResolved $runtimeSegment $actor}
    elseif($null-ne$reboundCompact-and$result.status-ceq'PASS'){$result['savedCompactReceipt']=Save-CompactReceipt $reboundCompact $CompactReceiptPath $receipt.authorityContext.projectRoot $receipt.taskId $receipt.actor;$result['ruleBodyLoaded']=$false}
    elseif($null-eq$reboundCompact){throw 'COMPACT_RECEIPT_DISCOVER_OR_REBIND_REQUIRED'}
  }
  try{$consumption=Complete-AiwRuntimeConsumption ([pscustomobject]$result) $input $(if($mode-ceq'DISCOVER'){$compactReceipt}else{$receipt}) $inputFull $ConsumedRuntimePath $ConsumedRuntimePathList $EmptyRuntimeDirectory $RetainedRuntimePath $(if($mode-ceq'DISCOVER'){$null}else{$evidenceObservation});if($null-ne$consumption){$result['runtimeCleanup']=$consumption}}
  catch{$result['runtimeCleanup']=[pscustomobject]@{status='REJECTED';failureKind='FRAMEWORK_REJECTED';reason=$_.Exception.Message;remaining=@($ConsumedRuntimePath)+@($ConsumedRuntimePathList|Where-Object{$_})+@($EmptyRuntimeDirectory)}}
  if($null-ne$cleanupInput){$result['inputCleanup']=Remove-ConsumedBoundaryInput $cleanupInput $inputReadIdentity;$cleanupInput=$null}
  # Lossless JSON escapes keep complete Unicode bodies portable across native
  # Windows console code pages. Internal bytes and receipt identities stay UTF8.
  $display=$null
  if($mode-ceq'DISCOVER'-and(-not$AsJson-or$DisplayPath)){
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementDisplay.psm1')
    $display=Get-AiwProcessDisplay -Result ([pscustomobject]$result)
    if($DisplayPath){
      if([string]$result.status-cnotin@('PASS','EVALUATION_ONLY')){throw 'DISPLAY_SUCCESSFUL_DISCOVER_REQUIRED'}
      Save-ProcessDisplay $display.text $DisplayPath $projectResolved $runtimeSegment $actor @($forbiddenPaths+$protectedPaths)
    }
  }
  if($AsJson){$result|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii}elseif($mode-ceq'DISCOVER'){$display.text|Write-Output}else{$count=if($mode-ceq'DISCOVER'){@($result.selectedRuleBlocks).Count}else{@($receipt.selectedObligations).Count};Write-Output ($result.status+'|'+$mode+'|requirements='+$count);if($CompactReceiptPath){Write-Output ('COMPACT_RECEIPT|'+$result.savedCompactReceipt.path+'|'+$result.savedCompactReceipt.identity)}}
  if(-not$AsJson){Write-AiwRuntimeCleanupObservation ([pscustomobject]$result)}
  if([string]$result.status-cnotin @('PASS','EVALUATION_ONLY')){throw (New-AiwPrivateToolExit (3))}
}catch{if($_.Exception.Data.Contains("AIW_PRIVATE_TOOL_EXIT")){throw};$failure=[ordered]@{status='FAIL';reason=[string]$_.Exception.Message};if($null-ne$cleanupInput){$failure['inputCleanup']=Remove-ConsumedBoundaryInput $cleanupInput $inputReadIdentity;$cleanupInput=$null};if($AsJson){$failure|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii}else{Write-Output ('FAIL|'+$failure.reason);Write-AiwRuntimeCleanupObservation ([pscustomobject]$failure)};throw (New-AiwPrivateToolExit (2))}

} | ForEach-Object { $outputs.Add($_) }
}catch{
if($_.Exception.Data.Contains('AIW_PRIVATE_TOOL_EXIT')){$code=[int]$_.Exception.Data['AIW_PRIVATE_TOOL_EXIT']}else{$code=2;if($AsJson){$outputs.Add(([ordered]@{status="FAIL";reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii))}else{$outputs.Add("FAIL|"+[string]$_.Exception.Message)}}
}finally{if($null-ne$aiwPublicationScopeLease){Exit-AiwProjectSourceScope $aiwPublicationScopeLease}}
return [pscustomobject]@{exitCode=$code;output=$outputs.ToArray()}
}
Export-ModuleMember -Function Invoke-AiwProcessRequirementBoundary

function Invoke-AiwPublicationBoundaryPairCore {
 [CmdletBinding()]param(
  [Parameter(Mandatory)][string]$InputPath,[Parameter(Mandatory)][string]$PublicationSourceInputPath,
  [Parameter(Mandatory)][string]$ExpectedPublicationSourceInputIdentity,[switch]$AsJson,[string]$AuthorizationCheckerPath,
  [switch]$DeleteInputOnExit,[string]$CompactReceiptPath,[string]$DisplayPath,[string[]]$ConsumedRuntimePath=@(),[string]$ConsumedRuntimePathList,
  [string[]]$EmptyRuntimeDirectory=@(),[string[]]$RetainedRuntimePath=@(),[scriptblock]$OnMemberResult=$null,$MemberResultState=$null,$PreparedTargets=$null
 )
 $members=[Collections.Generic.List[object]]::new();$context=$null;$member='GROUP';$code=0;$reason='COMPLETE';$status='PASS'
 try{
  if(-not$AsJson-or$DeleteInputOnExit-or$CompactReceiptPath-or$DisplayPath-or$ConsumedRuntimePath.Count-or$ConsumedRuntimePathList-or$EmptyRuntimeDirectory.Count-or$RetainedRuntimePath.Count){throw 'SOURCE_PUBLICATION_PAIR_OPTIONS'}
  $publication=@(Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1') -PassThru)[0]
  $sourceRef=[pscustomobject]@{path=$PublicationSourceInputPath;identity=$ExpectedPublicationSourceInputIdentity}
  $context=& $publication {param($control,$source)Get-PubBoundaryPairFacts $control $source} $InputPath $sourceRef
  # Only the original root can pass this call's actual under-handle target
  # construction. Every member still obtains fresh authority/raw observations.
  $context.targets=$PreparedTargets
  # Public grouping is admission-only. The root's private completion observer
  # saves each actual success before the next side can fail or be interrupted.
  if($context.mode-ceq'FINALIZE_OUTPUT'-and$null-eq$OnMemberResult){throw 'SOURCE_PUBLICATION_FINALIZE_ROOT_REQUIRED'}
  foreach($member in @('SOURCE','CONTROL')){
   if($member-ceq'CONTROL'){
    $previous=$context.facts
    # New authority and raw-member observations are never borrowed from SOURCE.
    # The existing private scope may reuse graph construction only after those
    # current full closure/ref/path checks succeed again.
    $context.facts=& $publication.ExportedCommands['Get-AiwProjectSourcePublicationMembers'] $previous.CONTROL.receiptRef $previous.SOURCE.receiptRef $previous.planRef
   }
   $context.member=$member;$context.inputRef=$context.inputs[$member]
   $parameters=@{InputPath=$context.inputRef.path;AsJson=$true;PublicationContext=$context}
   if($AuthorizationCheckerPath){$parameters.AuthorizationCheckerPath=$AuthorizationCheckerPath}
   $response=Invoke-AiwProcessRequirementBoundaryCore @parameters
   $members.Add([pscustomobject]@{member=$member;inputRef=$context.inputRef;response=$response})
   if($null-ne$OnMemberResult){& $OnMemberResult $member $context.inputRef.path $response $MemberResultState}
   if($response.exitCode-ne0){$code=$response.exitCode;$status='FAIL';$reason='MEMBER_BOUNDARY_FAILED';break}
  }
 }catch{$code=2;$status='FAIL';$reason=$_.Exception.Message}
 $envelope=[ordered]@{kind='PROJECT_SOURCE_PUBLICATION_BOUNDARY_PAIR';status=$status;mode=$(if($null-ne$context){$context.mode}else{'UNKNOWN'});reason=$reason;members=$members.ToArray();failedMember=$(if($code-ne0){$member}else{'NOT_APPLICABLE'});authorityGranted=$false;semanticCorrectnessProven=$false}
 return [pscustomobject]@{exitCode=$code;output=@(($envelope|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii))}
}
