[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson,[switch]$DeleteInputOnExit,[string]$AuthorizationCheckerPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -Force
$utf8=[Text.UTF8Encoding]::new($false,$true)

function Get-Identity([string]$Path){$b=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path));return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
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
  try{$projectItem=Get-Item -LiteralPath $ProjectRoot -Force -ErrorAction Stop}catch{throw 'INPUT_RUNTIME_PROJECT_ROOT_UNBOUND'}
  if(-not$projectItem.PSIsContainer-or($projectItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'INPUT_RUNTIME_PROJECT_ROOT_UNBOUND'}
  $project=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($projectItem.FullName));$expectedWorkspace=Join-Path $project '.ai-workspace'
  try{$expectedWorkspaceItem=Get-Item -LiteralPath $expectedWorkspace -Force -ErrorAction Stop}catch{throw 'INPUT_RUNTIME_PROJECT_ROOT_UNBOUND'}
  if(-not$expectedWorkspaceItem.PSIsContainer-or($expectedWorkspaceItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-or[string]$Observation.WorkspacePath-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($expectedWorkspaceItem.FullName))){throw 'INPUT_RUNTIME_PROJECT_ROOT_DRIFT'}
  if([string]$Observation.TaskSegment-cne$TaskId-or[string]$Observation.ActorSegment-cne$Actor){throw 'INPUT_RUNTIME_BINDING_DRIFT'}
}
function Get-ProcessBudgetContract {
  $path=Join-Path (Split-Path -Parent $PSScriptRoot) 'ADOPTION_PROFILE.json';$raw=Read-Input $path
  Assert-Fields $raw @('schemaVersion','frameworkVersion','registrationEligible','localCandidatePilotEligible','directSourceVersions','projectControl','processBudget')
  Assert-Fields $raw.projectControl @('schemaVersion','processCarrierContractVersion','frameworkToolBackend','navigationProjection','taskLastWriteRequired','capabilityBinding','runtimeArtifactRoot','runtimeGitIgnoreRule')
  Assert-Fields $raw.processBudget @('defaultSelectedRulePackBytes','absoluteSelectedRulePackBytes')
  $sources=@($raw.directSourceVersions);$uniqueSources=@($sources|Select-Object -Unique)
  if(-not(Test-JsonInteger $raw.schemaVersion)-or[int]$raw.schemaVersion-ne2-or[string]$raw.frameworkVersion-cne'1.16.0'-or-not($raw.registrationEligible-is[bool])-or-not[bool]$raw.registrationEligible-or-not($raw.localCandidatePilotEligible-is[bool])-or-not[bool]$raw.localCandidatePilotEligible-or-not($raw.directSourceVersions-is[Array])-or$sources.Count-lt1-or$sources.Count-gt32-or$uniqueSources.Count-ne$sources.Count-or@($sources|Where-Object{-not($_-is[string])-or[string]$_-cnotmatch'^\d+\.\d+\.\d+$'-or[string]$_-ceq[string]$raw.frameworkVersion}).Count-ne0-or[string]$raw.projectControl.processCarrierContractVersion-cne'1.16.0'-or[string]$raw.projectControl.navigationProjection-cne'ROOT_CANONICAL_SKILL_MANAGED_AGENTS'-or[string]$raw.projectControl.runtimeArtifactRoot-cne'.ai-workspace/runtime'-or[string]$raw.projectControl.runtimeGitIgnoreRule-cne'/.ai-workspace/runtime/'-or-not(Test-JsonInteger $raw.processBudget.defaultSelectedRulePackBytes)-or[int]$raw.processBudget.defaultSelectedRulePackBytes-ne32768-or-not(Test-JsonInteger $raw.processBudget.absoluteSelectedRulePackBytes)-or[int]$raw.processBudget.absoluteSelectedRulePackBytes-ne98304){throw 'ADOPTION_PROFILE_VALUES'}
  return $raw.processBudget
}
function Read-Input([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'INPUT_MISSING'}
  $b=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path));if($b.Length-ge3-and$b[0]-eq239-and$b[1]-eq187-and$b[2]-eq191){throw 'INPUT_BOM'}
  try{$t=$utf8.GetString($b)}catch{throw 'INPUT_UTF8'};if($t.Contains("`r")-or$t.Contains([char]0)-or$t.Contains([char]0xFFFD)-or-not$t.EndsWith("`n")){throw 'INPUT_TEXT_FORMAT'}
  $options=[Text.Json.JsonDocumentOptions]::new();$options.AllowTrailingCommas=$false;$options.CommentHandling=[Text.Json.JsonCommentHandling]::Disallow
  try{$document=[Text.Json.JsonDocument]::Parse($t,$options)}catch{throw 'INPUT_JSON'}
  try{Assert-NoDuplicateJsonMembers $document.RootElement}finally{$document.Dispose()}
  try{return $t|ConvertFrom-Json -Depth 100}catch{throw 'INPUT_JSON'}
}
function Assert-NoDuplicateJsonMembers($element){
  if($element.ValueKind-eq[Text.Json.JsonValueKind]::Object){
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($property in $element.EnumerateObject()){if(-not$seen.Add([string]$property.Name)){throw ('INPUT_FIELD_COUNT|'+[string]$property.Name)};Assert-NoDuplicateJsonMembers $property.Value}
  }elseif($element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($item in $element.EnumerateArray()){Assert-NoDuplicateJsonMembers $item}}
}
function Test-JsonInteger($v){return $v-is[byte]-or$v-is[sbyte]-or$v-is[int16]-or$v-is[uint16]-or$v-is[int32]-or$v-is[uint32]-or$v-is[int64]-or$v-is[uint64]}
function Assert-Fields($o,[string[]]$fields){if(-not($o-is[pscustomobject])){throw 'INPUT_OBJECT_TYPE'};$a=@($o.PSObject.Properties.Name);if($a.Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$a}).Count-ne0){throw 'INPUT_FIELDS'}}
function Assert-StringArray($v,[string]$name,[int]$MaxItems=256,[int]$MaxItemLength=1024){if(-not($v-is[Array])){throw "INPUT_ARRAY|$name"};if(@($v).Count-gt$MaxItems){throw "INPUT_ARRAY_COUNT|$name"};$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($i in @($v)){if(-not($i-is[string])-or[string]::IsNullOrWhiteSpace([string]$i)-or([string]$i).Length-gt$MaxItemLength-or-not$seen.Add([string]$i)){throw "INPUT_ARRAY_ITEM|$name"}}}
function Assert-InputString($v,[string]$name){if(-not($v-is[string])-or[string]::IsNullOrWhiteSpace([string]$v)){throw "INPUT_STRING|$name"}}
function Assert-ActionAndResult([string]$action,[string]$result){if($action-cnotin@('NONE','CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','OWNER_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')){throw 'ACTION_KIND'};if($result-cnotin@('NONE','PLAN','USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE','IMPLEMENTATION_RESULT','TEST_RESULT','GIT_RESULT','EXTERNAL_RESULT')){throw 'RESULT_KIND'};if($result-ceq'OWNER_ACCEPTANCE'-and$action-cne'OWNER_ACCEPT'){throw 'OWNER_ACCEPT_ACTION_REQUIRED'}}
function Assert-ExactPaths($paths){Assert-StringArray $paths 'exactPaths' 256 512;foreach($path in @($paths)){if([string]$path-cne([string]$path).Replace('\','/')-or[IO.Path]::IsPathRooted([string]$path)-or([string]$path).Contains(':')){throw 'EXACT_PATH'};foreach($part in ([string]$path).Split('/')){if([string]::IsNullOrWhiteSpace($part)-or$part-in@('.','..')){throw 'EXACT_PATH'}}}}
function Assert-PathPrefixes($paths,[string]$name){Assert-StringArray $paths $name 256 512;foreach($path in @($paths)){$normalized=([string]$path).TrimEnd('/');if([string]::IsNullOrWhiteSpace($normalized)-or[string]$path-cne([string]$path).Replace('\','/')-or[IO.Path]::IsPathRooted([string]$path)-or([string]$path).Contains(':')){throw 'PATH_PREFIX'};foreach($part in $normalized.Split('/')){if([string]::IsNullOrWhiteSpace($part)-or$part-in@('.','..')){throw 'PATH_PREFIX'}}}}
function Get-Receipt([string]$Path){
  $r=Read-Input $Path
  Assert-Fields $r @('schemaVersion','receiptType','status','mode','inputContractVersion','sourceCompositionIdentity','selectionIdentity','contextIdentity','projectId','frameworkVersion','taskIdentity','taskId','taskOwner','taskActor','actor','role','phase','profile','objective','actionKind','resultKind','exactPaths','authorityContext','intentEnvelope','selectedObligations','selectedPackBytes','selectedPackCeilingBytes','selectedPackEstimatedTokens','sourceLocators','sourceBindings','evidenceCeilings','sourceBuildCount','legacyCorrectionsFullReadCount','legacyProjectCustomFullReadCount','hostEnforcementGrade','invocationState','authorityGranted','semanticCorrectnessProven')
  if(-not(Test-JsonInteger $r.schemaVersion)-or[int]$r.schemaVersion-ne1-or-not($r.authorityGranted-is[bool])-or-not($r.semanticCorrectnessProven-is[bool])-or[string]$r.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or[string]$r.mode-cne'DISCOVER'-or[string]$r.status-cnotin@('PASS','EVALUATION_ONLY')-or[string]$r.frameworkVersion-cne'1.16.0'-or[bool]$r.authorityGranted-or[bool]$r.semanticCorrectnessProven){throw 'DISCOVER_RECEIPT_TYPE'}
  foreach($countName in @('inputContractVersion','sourceBuildCount','legacyCorrectionsFullReadCount','legacyProjectCustomFullReadCount','selectedPackBytes','selectedPackCeilingBytes','selectedPackEstimatedTokens')){if(-not(Test-JsonInteger $r.$countName)-or[int]$r.$countName-lt0){throw ('DISCOVER_RECEIPT_COUNT|'+$countName)}}
  foreach($name in @('sourceCompositionIdentity','selectionIdentity','contextIdentity','projectId','taskIdentity','taskId','taskOwner','taskActor','actor','role','phase','profile','objective','actionKind','resultKind','hostEnforcementGrade','invocationState')){Assert-InputString $r.$name $name}
  Assert-StringArray $r.exactPaths 'receiptExactPaths';Assert-StringArray $r.evidenceCeilings 'receiptEvidenceCeilings'
  if(-not($r.selectedObligations-is[Array])){throw 'DISCOVER_RECEIPT_OBLIGATIONS'}
  foreach($obligation in @($r.selectedObligations)){
    Assert-Fields $obligation @('requirementId','preparationRequirements','resultRequirements')
    Assert-InputString $obligation.requirementId 'requirementId'
    Assert-StringArray $obligation.preparationRequirements 'receiptPreparationRequirements';Assert-StringArray $obligation.resultRequirements 'receiptResultRequirements'
  }
  Assert-Fields $r.sourceLocators @('projectRoot','frameworkRoot','taskRelativePath','authorizationPackagePath')
  foreach($name in @('projectRoot','frameworkRoot','taskRelativePath','authorizationPackagePath')){Assert-InputString $r.sourceLocators.$name $name}
  Assert-Fields $r.sourceBindings @('projectConfigIdentity','controllerIdentity','correctionsIdentity','policyIdentity','projectCustomIdentity','taskIdentity','frameworkVersionIdentity','releaseManifestIdentity','candidatePilotStateIdentity','nativeCatalogIdentity','correctionCoverageIdentity')
  foreach($name in @($r.sourceBindings.PSObject.Properties.Name)){Assert-InputString $r.sourceBindings.$name $name;if([string]$r.sourceBindings.$name-cne'MISSING'-and[string]$r.sourceBindings.$name-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('DISCOVER_RECEIPT_BINDING|'+$name)}}
  Assert-Fields $r.authorityContext @('schemaVersion','projectId','projectRoot','repositoryGitTop','frameworkVersion','frameworkSealIdentity','controllerIdentity','taskIdentity','taskActor','actor','role','phase','profile','exactScope','forbiddenScope','protectedScope','authorizationIdentity','authorizedActions','observedCapabilities','projectConfigIdentity','correctionsIdentity','policyIdentity','userDecision','recoveryState','hostEnforcementGrade')
  Assert-Fields $r.intentEnvelope @('schemaVersion','objective','requestedActionKind','requestedResultKind','semanticHints','pathHints','capabilityHints','mutationHints','externalHints','ambiguityState')
  return $r
}

function Assert-IntentEnvelope($Envelope){
  Assert-Fields $Envelope @('schemaVersion','objective','requestedActionKind','requestedResultKind','semanticHints','pathHints','capabilityHints','mutationHints','externalHints','ambiguityState')
  if(-not(Test-JsonInteger $Envelope.schemaVersion)-or[int]$Envelope.schemaVersion-ne1){throw 'INTENT_SCHEMA_VERSION'}
  foreach($name in @('objective','requestedActionKind','requestedResultKind','ambiguityState')){Assert-InputString $Envelope.$name $name}
  Assert-StringArray $Envelope.semanticHints 'intent_semanticHints' 64 256
  Assert-StringArray $Envelope.pathHints 'intent_pathHints' 64 512
  Assert-StringArray $Envelope.capabilityHints 'intent_capabilityHints' 32 128
  Assert-StringArray $Envelope.mutationHints 'intent_mutationHints' 32 128
  Assert-StringArray $Envelope.externalHints 'intent_externalHints' 32 256
  if(([string]$Envelope.objective).Length-gt2048-or[string]$Envelope.ambiguityState-cnotin@('CLEAR','UNKNOWN','CONFLICT')){throw 'INTENT_VALUES'}
  Assert-ActionAndResult ([string]$Envelope.requestedActionKind) ([string]$Envelope.requestedResultKind)
  $bytes=$utf8.GetByteCount(($Envelope|ConvertTo-Json -Depth 20 -Compress));if($bytes-gt4096){throw 'INTENT_BUDGET_EXCEEDED'}
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
    'review'=@('REVIEW_ROUTE','REVIEW_EXECUTE','OWNER_ACCEPT');'git'=@('GIT_STAGE','GIT_COMMIT','PUSH');
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
  try{$output=@(& git -C $ProjectRoot rev-parse --show-toplevel 2>$null|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
  if($code-ne0-or$output.Count-ne1){return 'UNPROVEN'}
  return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($output[0]))
}

function Get-AuthorizationRepositoryRoot([pscustomobject]$Package,[string]$ProjectRoot){
  $controlRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
  if([int]$Package.schemaVersion-ne2-or[string]$Package.repositoryId-ceq'CONTROL'){return $controlRoot}
  $config=Read-Input (Join-Path $controlRoot '.ai-workspace/project.json')
  if($null-eq$config.PSObject.Properties['frameworkTarget']-or[string]$config.frameworkTarget.repositoryId-cne[string]$Package.repositoryId){throw 'AUTHORIZATION_REPOSITORY_DRIFT'}
  return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $controlRoot) ([string]$config.frameworkTarget.siblingDirectory))))
}

function Get-TaskBindingObservation([string]$ProjectRoot,[string]$TaskRelativePath){
  $taskFull=Join-Path $ProjectRoot $TaskRelativePath
  $taskText=$utf8.GetString([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $taskFull)))
  $taskIdMatch=[regex]::Matches($taskText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
  $taskOwnerMatch=[regex]::Matches($taskText,'(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$')
  if($taskIdMatch.Count-ne1-or$taskOwnerMatch.Count-ne1){throw 'TASK_BINDING_FIELDS'}
  return [pscustomobject]@{TaskId=[string]$taskIdMatch[0].Groups['id'].Value;Owner=[string]$taskOwnerMatch[0].Groups['owner'].Value}
}

function Assert-AuthorizationPostimages([string]$PackagePath,[string]$ProjectRoot,[string[]]$ExactPaths,[string[]]$ResultReceipts){
  if($PackagePath-ceq'NOT_REQUIRED'){return}
  $package=Read-Input $PackagePath
  $repositoryRoot=Get-AuthorizationRepositoryRoot $package $ProjectRoot
  foreach($relative in $ExactPaths){
    $objectPath=Join-Path $repositoryRoot $relative
    $postimageIdentity=if(Test-Path -LiteralPath $objectPath -PathType Leaf){Get-Identity $objectPath}else{'MISSING'}
    $expectedReceipt='OBJECT_POSTIMAGE|'+$relative+'|'+$postimageIdentity
    $matches=@($ResultReceipts|Where-Object{$_-ceq$expectedReceipt})
    if($matches.Count-ne1){throw ('RESULT_POSTIMAGE_RECEIPT_REQUIRED|'+$relative)}
  }
}

function Get-AuthorizationObservation([string]$Path,[string]$ExpectedIdentity,[string]$Actor,[string[]]$ExactPaths,[string]$UserDecision,[string]$ActionKind,[string]$ProjectRoot,[string]$TaskRelativePath,[string]$TaskIdentity,[string]$TaskId,[string]$TaskOwner,[string]$ProjectConfigIdentity){
  if([string]$Path-ceq'NOT_REQUIRED'){
    if([string]$ExpectedIdentity-cne'NOT_REQUIRED'){throw 'AUTHORIZATION_INPUT_MISMATCH'}
    $controlRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
    return [pscustomobject]@{Actions=@();Identity='NOT_REQUIRED';UserDecision=$UserDecision;RepositoryId='CONTROL';RepositoryRoot=$controlRoot}
  }
  if([string]$ExpectedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'AUTHORIZATION_IDENTITY'}
  $identity=Get-Identity $Path;if($identity-cne$ExpectedIdentity){throw 'AUTHORIZATION_DRIFT'}
  $package=Read-Input $Path
  foreach($name in @('schemaVersion','repositoryId','grantee','actions','exactPaths','userConfirmation')){if($name-ceq'repositoryId'-and[int]$package.schemaVersion-eq1){continue};if($null-eq$package.PSObject.Properties[$name]){throw 'AUTHORIZATION_FIELDS'}}
  Assert-StringArray $package.actions 'authorizationActions' 16 64;Assert-ExactPaths $package.exactPaths
  $controlRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
  $repositoryId=if([int]$package.schemaVersion-eq2){[string]$package.repositoryId}else{'REPO_LOCAL'}
  $repositoryRoot=Get-AuthorizationRepositoryRoot $package $controlRoot
  $observedIdentities=@();foreach($relative in $ExactPaths){$candidate=Join-Path $repositoryRoot $relative;$observed=if(Test-Path -LiteralPath $candidate -PathType Leaf){Get-Identity $candidate}elseif(Test-Path -LiteralPath $candidate){throw 'AUTHORIZATION_OBJECT_NOT_FILE'}else{'NEW'};$observedIdentities+=($relative+'='+$observed)}
  $checker=if([string]::IsNullOrWhiteSpace($AuthorizationCheckerPath)){Join-Path $PSScriptRoot 'check-authorization.ps1'}else{[IO.Path]::GetFullPath($AuthorizationCheckerPath)}
  if(-not(Test-Path -LiteralPath $checker -PathType Leaf)-or((Get-Item -LiteralPath $checker -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'AUTHORIZATION_CHECKER_UNAVAILABLE'}
  $checkerArgs=@{PackagePath=$Path;ObservedActor=$Actor;ObservedTaskId=$TaskId;ObservedOwner=$TaskOwner;ObservedAction=@($ActionKind);ObservedPath=@($ExactPaths);ObservedIdentity=@($observedIdentities);ControllerControlPath='.ai-workspace/controller.json';ObservedRepositoryId=$repositoryId;ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=$ProjectConfigIdentity;TaskPath=$TaskRelativePath;ExpectedTaskIdentity=$TaskIdentity}
  $previousCurrentDirectory=[Environment]::CurrentDirectory;Push-Location $controlRoot
  try{[Environment]::CurrentDirectory=$controlRoot;$checkOutput=@(& $checker @checkerArgs 2>&1|ForEach-Object{[string]$_});$checkCode=$LASTEXITCODE}finally{[Environment]::CurrentDirectory=$previousCurrentDirectory;Pop-Location}
  if($checkCode-ne0){throw ('AUTHORIZATION_CHECK_FAILED|'+($checkOutput-join';'))}
  if([string]$package.userConfirmation-cne$UserDecision){throw 'AUTHORIZATION_USER_DECISION_DRIFT'}
  return [pscustomobject]@{Actions=@($package.actions);Identity=$identity;UserDecision=[string]$package.userConfirmation;RepositoryId=$repositoryId;RepositoryRoot=$repositoryRoot}
}
$cleanupInput=$null;$cleanupObservation=$null;$artifactStorage='CALLER_MANAGED'
try{
  $input=Read-Input $InputPath
  if($DeleteInputOnExit){$cleanupObservation=Get-SafeCleanupInput $InputPath;$artifactStorage=[string]$cleanupObservation.Storage;if($artifactStorage-ceq'SYSTEM_TEMP_FALLBACK'){$cleanupInput=[string]$cleanupObservation.Path}}
  if(-not($input-is[pscustomobject])-or$null-eq$input.PSObject.Properties['mode']-or-not($input.mode-is[string])){throw 'INPUT_MODE'}
  $mode=[string]$input.mode
  if($mode-ceq'DISCOVER'){
    if(-not(Test-JsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-notin@(1,2)){throw 'INPUT_SCHEMA_VERSION'}
    $inputContract=[int]$input.schemaVersion
    if($inputContract-eq1){
      Assert-Fields $input @('schemaVersion','mode','projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities','objective','actionKind','resultKind','exactPaths','hostEnforcementGrade','evaluationOnly')
      $intent=[pscustomobject][ordered]@{schemaVersion=1;objective=[string]$input.objective;requestedActionKind=[string]$input.actionKind;requestedResultKind=[string]$input.resultKind;semanticHints=@();pathHints=@($input.exactPaths);capabilityHints=@($input.capabilities);mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
      $forbiddenPaths=@();$protectedPaths=@();$authorizationPath='NOT_REQUIRED';$authorizationIdentity='NOT_REQUIRED';$userDecision='NOT_REQUIRED';$recoveryState='UNKNOWN';$invocationState='UNPROVEN'
    }else{
      Assert-Fields $input @('schemaVersion','mode','projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities','exactPaths','forbiddenPaths','protectedPaths','authorizationPackagePath','expectedAuthorizationIdentity','userDecision','recoveryState','hostEnforcementGrade','invocationState','intentEnvelope','evaluationOnly')
      $intent=$input.intentEnvelope;Assert-IntentEnvelope $intent
      $input|Add-Member -NotePropertyName objective -NotePropertyValue ([string]$intent.objective)
      $input|Add-Member -NotePropertyName actionKind -NotePropertyValue ([string]$intent.requestedActionKind)
      $input|Add-Member -NotePropertyName resultKind -NotePropertyValue ([string]$intent.requestedResultKind)
      $forbiddenPaths=@($input.forbiddenPaths);$protectedPaths=@($input.protectedPaths);$authorizationPath=[string]$input.authorizationPackagePath;$authorizationIdentity=[string]$input.expectedAuthorizationIdentity;$userDecision=[string]$input.userDecision;$recoveryState=[string]$input.recoveryState;$invocationState=[string]$input.invocationState
      Assert-PathPrefixes $forbiddenPaths 'forbiddenPaths';Assert-PathPrefixes $protectedPaths 'protectedPaths'
      if($recoveryState-cnotin@('FULL_COLD','WARM','CURRENT','UNKNOWN')-or$invocationState-cnotin@('PROVEN_EXPLICIT','PROVEN_MANAGED','UNPROVEN')){throw 'CONTEXT_STATE'}
    }
    foreach($n in @('projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedTaskIdentity','observedActor','objective','actionKind','resultKind','hostEnforcementGrade')){if(-not($input.$n-is[string])-or[string]::IsNullOrWhiteSpace([string]$input.$n)){throw "INPUT_STRING|$n"}}
    Assert-InputString $input.expectedCorrectionsIdentity 'expectedCorrectionsIdentity'
    foreach($n in @('expectedProjectConfigIdentity','expectedTaskIdentity')){if([string]$input.$n-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('INPUT_IDENTITY|'+$n)}}
    if([string]$input.expectedCorrectionsIdentity-cne'MISSING'-and[string]$input.expectedCorrectionsIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INPUT_IDENTITY|expectedCorrectionsIdentity'}
    Assert-StringArray $input.capabilities 'capabilities' 32 128;Assert-ExactPaths $input.exactPaths;Assert-ActionAndResult ([string]$input.actionKind) ([string]$input.resultKind)
    if(-not($input.evaluationOnly-is[bool])){throw 'INPUT_BOOL|evaluationOnly'}
    if([string]$input.hostEnforcementGrade-cnotin @('HOST_ENFORCED','FRAMEWORK_GATED','INSTRUCTION_BOUND')){throw 'HOST_ENFORCEMENT_GRADE'}
    $taskIdentity=Get-Identity ([string]$input.taskPath);if($taskIdentity-cne[string]$input.expectedTaskIdentity){throw 'TASK_DRIFT'}
    $projectResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.projectRoot))))
    $taskResolved=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.taskPath)))
    $projectPrefix=$projectResolved+[IO.Path]::DirectorySeparatorChar
    if(-not$taskResolved.StartsWith($projectPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'TASK_LOCATOR_SCOPE'}
    $taskRelative=$taskResolved.Substring($projectPrefix.Length).Replace('\','/')
    if(-not$taskRelative.StartsWith('.ai-workspace/tasks/',[StringComparison]::Ordinal)){throw 'TASK_LOCATOR_SCOPE'}
    $taskText=$utf8.GetString([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath ([string]$input.taskPath))))
    $route=[regex]::Matches($taskText,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
    if($route.Count-ne1){
      $legacy=[regex]::Matches($taskText,'(?m)^- Work route:\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
      if($legacy.Count-eq1){$result=[ordered]@{status='LEGACY_ACTOR_CONTEXT_UNBOUND';mode=$mode;evidenceCeiling='TASK_ACTOR_CONTEXT_REBIND_REQUIRED';taskIdentity=$taskIdentity};if($AsJson){$result|ConvertTo-Json -Compress}else{Write-Output 'LEGACY_ACTOR_CONTEXT_UNBOUND|TASK_ACTOR_CONTEXT_REBIND_REQUIRED'};exit 3}
      throw 'TASK_WORK_ROUTE'
    }
    $taskActor=[string]$route[0].Groups['actor'].Value;$actor=[string]$input.observedActor;$effectiveRole=[string]$route[0].Groups['role'].Value;$effectivePhase=[string]$route[0].Groups['phase'].Value
    if($actor-cne$taskActor){
      if($inputContract-ne2-or[string]$input.actionKind-cne'REVIEW_EXECUTE'-or$authorizationPath-ceq'NOT_REQUIRED'){throw 'CONFLICT_ACTOR_ROLE_PHASE'}
      $temporaryPackage=Read-Input $authorizationPath
      if([string]$temporaryPackage.grantee-cne$actor-or@($temporaryPackage.actions).Count-ne1-or[string]$temporaryPackage.actions[0]-cne'REVIEW_EXECUTE'){throw 'TEMPORARY_ACTION_GRANTEE_DRIFT'}
      $effectiveRole='REVIEWER';$effectivePhase='REVIEW'
    }
    $profileMatch=[regex]::Matches($taskText,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL);');if($profileMatch.Count-ne1){throw 'TASK_PROFILE'}
    [string[]]$intentFactMismatches=@();if($inputContract-eq2){$intentFactMismatches=@(Get-IntentFactMismatches $intent @($input.capabilities) @($input.exactPaths) ([string]$input.actionKind))}
    if($intentFactMismatches.Count-gt0-and[string]$intent.ambiguityState-ceq'CLEAR'){throw ('INTENT_FACT_MISMATCH|'+[string]::Join(',',@($intentFactMismatches)))}
    $semanticObjective=([string]$input.objective+' '+[string]::Join(' ',@($intent.semanticHints+$intent.externalHints))).Trim()
    $composition=Invoke-ProcessRequirementComposition -ProjectRoot ([string]$input.projectRoot) -FrameworkRoot ([string]$input.frameworkRoot) -TargetVersion '1.16.0' -ExpectedProjectConfigIdentity ([string]$input.expectedProjectConfigIdentity) -ExpectedCorrectionsIdentity ([string]$input.expectedCorrectionsIdentity) -Profile ([string]$profileMatch[0].Groups['profile'].Value) -Role $effectiveRole -Phase $effectivePhase -Actor $actor -TaskIdentity $taskIdentity -Capabilities @($input.capabilities) -Objective $semanticObjective -ActionKind ([string]$input.actionKind) -ResultKind ([string]$input.resultKind) -ExactPaths @($input.exactPaths) -SemanticApplicabilityUnknown:([string]$intent.ambiguityState-cne'CLEAR') -EvaluationOnly:([bool]$input.evaluationOnly)
    $taskIdMatch=[regex]::Matches($taskText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)');$taskOwnerMatch=[regex]::Matches($taskText,'(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$')
    if($taskIdMatch.Count-ne1-or$taskOwnerMatch.Count-ne1){throw 'TASK_BINDING_FIELDS'}
    if($null-ne$cleanupObservation-and[string]$cleanupObservation.Storage-ceq'PROJECT_RUNTIME'){Assert-ProjectRuntimeCleanupBinding $cleanupObservation $projectResolved ([string]$taskIdMatch[0].Groups['id'].Value) $actor}
    $auth=Get-AuthorizationObservation $authorizationPath $authorizationIdentity $actor @($input.exactPaths) $userDecision ([string]$input.actionKind) $projectResolved $taskRelative $taskIdentity ([string]$taskIdMatch[0].Groups['id'].Value) ([string]$taskOwnerMatch[0].Groups['owner'].Value) ([string]$input.expectedProjectConfigIdentity)
    $projectResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.projectRoot))))
    $controllerPath=Join-Path $projectResolved '.ai-workspace/controller.json';$controllerIdentity=if(Test-Path -LiteralPath $controllerPath -PathType Leaf){Get-Identity $controllerPath}else{'MISSING'}
    $authority=[ordered]@{schemaVersion=1;projectId=$composition.projectId;projectRoot=$auth.RepositoryRoot;repositoryGitTop=(Get-GitTop $auth.RepositoryRoot);frameworkVersion='1.16.0';frameworkSealIdentity=$composition.releaseManifestIdentity;controllerIdentity=$controllerIdentity;taskIdentity=$taskIdentity;taskActor=$taskActor;actor=$actor;role=$effectiveRole;phase=$effectivePhase;profile=[string]$profileMatch[0].Groups['profile'].Value;exactScope=@($input.exactPaths);forbiddenScope=@($forbiddenPaths);protectedScope=@($protectedPaths);authorizationIdentity=$auth.Identity;authorizedActions=@($auth.Actions);observedCapabilities=@($input.capabilities);projectConfigIdentity=$composition.projectConfigIdentity;correctionsIdentity=$composition.correctionsIdentity;policyIdentity=$composition.policyIdentity;userDecision=$userDecision;recoveryState=$recoveryState;hostEnforcementGrade=[string]$input.hostEnforcementGrade}
    $authorityBytes=$utf8.GetByteCount(($authority|ConvertTo-Json -Depth 30 -Compress));if($authorityBytes-gt8192){throw 'AUTHORITY_CONTEXT_BUDGET_EXCEEDED'}
    $intentMaterial=$intent|ConvertTo-Json -Depth 30 -Compress
    $selectionMaterial=@($composition.sourceCompositionIdentity,$intentMaterial,[string]::Join("`n",@($input.capabilities)),[string]::Join("`n",@($input.exactPaths)),[string]::Join("`n",@($intentFactMismatches)))-join"`n"
    $selectionIdentity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($selectionMaterial)))
    $budgetContract=Get-ProcessBudgetContract
    $packJson=@($composition.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress;$packBytes=$utf8.GetByteCount($packJson)
    $selectedRulePackBytes=[int]$composition.selectedRulePackBytes;$absoluteSelectedRulePackBytes=[int]$budgetContract.absoluteSelectedRulePackBytes
    if($selectedRulePackBytes-lt1-or$selectedRulePackBytes-gt$absoluteSelectedRulePackBytes-or[int]$composition.absoluteSelectedRulePackBytes-ne$absoluteSelectedRulePackBytes){throw 'PROJECT_SELECTED_RULE_PACK_BUDGET_INVALID'}
    if($packBytes-gt$selectedRulePackBytes){throw ('SELECTED_RULE_PACK_BUDGET_EXCEEDED|bytes='+$packBytes+'|ceiling='+$selectedRulePackBytes)}
    $contextMaterial=(($authority|ConvertTo-Json -Depth 30 -Compress)+"`n"+($intent|ConvertTo-Json -Depth 30 -Compress));$contextIdentity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($contextMaterial)))
    $ceilings=@($composition.evidenceCeilings);if([string]$input.hostEnforcementGrade-ceq'INSTRUCTION_BOUND'-or$invocationState-ceq'UNPROVEN'){$ceilings+='INVOCATION_UNPROVEN'};if([bool]$input.evaluationOnly){$ceilings+='NON_AUTHORITY_EVALUATION_ONLY'};if([string]$intent.ambiguityState-cne'CLEAR'){$ceilings+='INTENT_AMBIGUITY_CONSERVATIVE_LOAD'};if($intentFactMismatches.Count-gt0){$ceilings+='INTENT_FACT_MISMATCH_CONSERVATIVE_LOAD'};if($authority.repositoryGitTop-ceq'UNPROVEN'){$ceilings+='REPOSITORY_GIT_TOP_UNPROVEN'};if($artifactStorage-ceq'SYSTEM_TEMP_FALLBACK'){$ceilings+='SYSTEM_TEMP_FALLBACK'}
    $selectedObligations=@($composition.selectedRequirements|ForEach-Object{[ordered]@{requirementId=[string]$_.requirementId;preparationRequirements=@($_.preparationRequirements);resultRequirements=@($_.resultRequirements)}})
    $compactReceipt=[ordered]@{schemaVersion=1;receiptType='PROCESS_REQUIREMENTS_DISCOVER';status=[string]$composition.status;mode=$mode;inputContractVersion=$inputContract;sourceCompositionIdentity=$composition.sourceCompositionIdentity;selectionIdentity=$selectionIdentity;contextIdentity=$contextIdentity;projectId=$composition.projectId;frameworkVersion='1.16.0';taskIdentity=$taskIdentity;taskId=[string]$taskIdMatch[0].Groups['id'].Value;taskOwner=[string]$taskOwnerMatch[0].Groups['owner'].Value;taskActor=$taskActor;actor=$actor;role=$effectiveRole;phase=$effectivePhase;profile=[string]$profileMatch[0].Groups['profile'].Value;objective=[string]$input.objective;actionKind=[string]$input.actionKind;resultKind=[string]$input.resultKind;exactPaths=@($input.exactPaths);authorityContext=$authority;intentEnvelope=$intent;selectedObligations=$selectedObligations;selectedPackBytes=$packBytes;selectedPackCeilingBytes=$selectedRulePackBytes;selectedPackEstimatedTokens=[int][math]::Ceiling($packBytes/4.0);sourceLocators=[ordered]@{projectRoot=$projectResolved;frameworkRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.frameworkRoot))));taskRelativePath=$taskRelative;authorizationPackagePath=$authorizationPath};sourceBindings=[ordered]@{projectConfigIdentity=$composition.projectConfigIdentity;controllerIdentity=$composition.controllerIdentity;correctionsIdentity=$composition.correctionsIdentity;policyIdentity=$composition.policyIdentity;projectCustomIdentity=$composition.projectCustomIdentity;taskIdentity=$taskIdentity;frameworkVersionIdentity=$composition.frameworkVersionIdentity;releaseManifestIdentity=$composition.releaseManifestIdentity;candidatePilotStateIdentity=$composition.candidatePilotStateIdentity;nativeCatalogIdentity=$composition.nativeCatalogIdentity;correctionCoverageIdentity=$composition.correctionCoverageIdentity};evidenceCeilings=@($ceilings|Sort-Object -Unique);sourceBuildCount=$composition.sourceBuildCount;legacyCorrectionsFullReadCount=$composition.legacyCorrectionsFullReadCount;legacyProjectCustomFullReadCount=$composition.legacyProjectCustomFullReadCount;hostEnforcementGrade=[string]$input.hostEnforcementGrade;invocationState=$invocationState;authorityGranted=$false;semanticCorrectnessProven=$false}
    $result=[ordered]@{schemaVersion=1;resultType='PROCESS_REQUIREMENTS_DISCOVER_RESULT';status=[string]$composition.status;mode=$mode;artifactStorage=$artifactStorage;selectedRuleBlocks=@($composition.selectedRequirements);compactReceipt=$compactReceipt}
    if($null-ne$cleanupObservation-and[string]$cleanupObservation.Storage-ceq'PROJECT_RUNTIME'){$cleanupInput=[string]$cleanupObservation.Path}
  }elseif($mode-in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
    $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','objective','actionKind','resultKind','exactPaths','authorizationIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')
    Assert-Fields $input $fields
    if(-not(Test-JsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-ne1){throw 'INPUT_SCHEMA_VERSION'}
    foreach($n in @('discoverReceiptPath','expectedDiscoverReceiptIdentity','objective','actionKind','resultKind','authorizationIdentity','publicDecisionIdentity','protectionState')){Assert-InputString $input.$n $n}
    if([string]$input.expectedDiscoverReceiptIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INPUT_IDENTITY|expectedDiscoverReceiptIdentity'}
    Assert-ExactPaths $input.exactPaths;foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){Assert-StringArray $input.$name $name};Assert-ActionAndResult ([string]$input.actionKind) ([string]$input.resultKind)
    $categoricalActions=@('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','OWNER_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')
    if([string]$input.authorizationIdentity-cne'NOT_REQUIRED'-and[string]$input.authorizationIdentity-cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'AUTHORIZATION_RECEIPT_IDENTITY'}
    if([string]$input.publicDecisionIdentity-cne'NOT_REQUIRED'-and[string]$input.publicDecisionIdentity-cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'PUBLIC_DECISION_IDENTITY'}
    if([string]$input.protectionState-cnotin@('BOUND','NOT_APPLICABLE')){throw 'PROTECTION_STATE'}
    $receiptIdentity=Get-Identity ([string]$input.discoverReceiptPath);if($receiptIdentity-cne[string]$input.expectedDiscoverReceiptIdentity){throw 'DISCOVER_RECEIPT_DRIFT'}
    $receipt=Get-Receipt ([string]$input.discoverReceiptPath)
    if($null-ne$cleanupObservation-and[string]$cleanupObservation.Storage-ceq'PROJECT_RUNTIME'){
      Assert-ProjectRuntimeCleanupBinding $cleanupObservation ([string]$receipt.sourceLocators.projectRoot) ([string]$receipt.taskId) ([string]$receipt.actor)
      $cleanupInput=[string]$cleanupObservation.Path
    }
    $currentBindings=Get-AiwProcessBindingSnapshot -ProjectRoot ([string]$receipt.sourceLocators.projectRoot) -FrameworkRoot ([string]$receipt.sourceLocators.frameworkRoot) -TargetVersion '1.16.0' -TaskRelativePath ([string]$receipt.sourceLocators.taskRelativePath)
    $taskPostimageTransition=$false
    if($mode-ceq'FINALIZE_OUTPUT'-and[string]$currentBindings.taskIdentity-cne[string]$receipt.sourceBindings.taskIdentity){
      if([int]$receipt.inputContractVersion-ne2-or[string]$receipt.actionKind-cne'CONTROL_WRITE'-or[string]$receipt.sourceLocators.authorizationPackagePath-ceq'NOT_REQUIRED'-or@($receipt.exactPaths|Where-Object{[string]$_-ceq[string]$receipt.sourceLocators.taskRelativePath}).Count-ne1){throw 'DISCOVER_SOURCE_DRIFT|taskIdentity'}
      $transitionPackage=Read-Input ([string]$receipt.sourceLocators.authorizationPackagePath)
      if(-not(Test-JsonInteger $transitionPackage.schemaVersion)-or[int]$transitionPackage.schemaVersion-ne2-or[string]$transitionPackage.repositoryId-cne'CONTROL'-or@($transitionPackage.actions|Where-Object{[string]$_-ceq'CONTROL_WRITE'}).Count-ne1-or@($transitionPackage.exactPaths|Where-Object{[string]$_-ceq[string]$receipt.sourceLocators.taskRelativePath}).Count-ne1){throw 'CONTROL_TASK_POSTIMAGE_TRANSITION_NOT_AUTHORIZED'}
      $currentTaskBinding=Get-TaskBindingObservation ([string]$receipt.sourceLocators.projectRoot) ([string]$receipt.sourceLocators.taskRelativePath)
      if([string]$currentTaskBinding.TaskId-cne[string]$receipt.taskId-or[string]$currentTaskBinding.Owner-cne[string]$receipt.taskOwner){throw 'CONTROL_TASK_POSTIMAGE_BINDING_DRIFT'}
      $taskPostimageTransition=$true
    }
    foreach($name in @($receipt.sourceBindings.PSObject.Properties.Name)){if([string]$currentBindings.$name-cne[string]$receipt.sourceBindings.$name-and-not($taskPostimageTransition-and[string]$name-ceq'taskIdentity')){throw ('DISCOVER_SOURCE_DRIFT|'+$name)}}
    if([int]$receipt.inputContractVersion-eq2-and[string]$receipt.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){
      $currentAuthorizationIdentity=Get-Identity ([string]$receipt.sourceLocators.authorizationPackagePath);if($currentAuthorizationIdentity-cne[string]$receipt.authorityContext.authorizationIdentity){throw 'DISCOVER_SOURCE_DRIFT|authorizationIdentity'}
      if($mode-ceq'ADMIT_ACTION'){
        $taskBinding=Get-TaskBindingObservation ([string]$receipt.sourceLocators.projectRoot) ([string]$receipt.sourceLocators.taskRelativePath)
        $null=Get-AuthorizationObservation ([string]$receipt.sourceLocators.authorizationPackagePath) ([string]$receipt.authorityContext.authorizationIdentity) ([string]$receipt.actor) @($receipt.exactPaths) ([string]$receipt.authorityContext.userDecision) ([string]$receipt.actionKind) ([string]$receipt.sourceLocators.projectRoot) ([string]$receipt.sourceLocators.taskRelativePath) ([string]$receipt.taskIdentity) ([string]$taskBinding.TaskId) ([string]$taskBinding.Owner) ([string]$receipt.sourceBindings.projectConfigIdentity)
      }
      if($mode-ceq'FINALIZE_OUTPUT'){Assert-AuthorizationPostimages ([string]$receipt.sourceLocators.authorizationPackagePath) ([string]$receipt.sourceLocators.projectRoot) @($receipt.exactPaths) @($input.resultReceipts)}
    }
    if([string]$input.objective-cne[string]$receipt.objective-or[string]$input.actionKind-cne[string]$receipt.actionKind-or[string]$input.resultKind-cne[string]$receipt.resultKind-or[string]::Join("`n",@($input.exactPaths))-cne[string]::Join("`n",@($receipt.exactPaths))){throw 'DISCOVER_CONTEXT_DRIFT'}
    $requiredPrep=@($receipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
    $requiredResult=@($receipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $providedPrep=@($input.preparationReceipts);$providedResult=@($input.resultReceipts)
    $missingPrep=@($requiredPrep|Where-Object{$_-cnotin$providedPrep})
    if([int]$receipt.inputContractVersion-eq1-and[string]$receipt.actionKind-in$categoricalActions){$missingPrep+='LEGACY_AUTHORITY_CONTEXT_UNBOUND'}
    if([int]$receipt.inputContractVersion-eq2-and[string]$receipt.actionKind-in$categoricalActions-and[string]$receipt.actionKind-cnotin@($receipt.authorityContext.authorizedActions)){$missingPrep+='ACTION_NOT_AUTHORIZED_IN_CONTEXT'}
    if([int]$receipt.inputContractVersion-eq2-and[string]$input.authorizationIdentity-cne[string]$receipt.authorityContext.authorizationIdentity){throw 'AUTHORIZATION_CONTEXT_DRIFT'}
    if([int]$receipt.inputContractVersion-eq2-and[string]$receipt.intentEnvelope.ambiguityState-cne'CLEAR'){$missingPrep+='INTENT_AMBIGUOUS'}
    if([int]$receipt.inputContractVersion-eq2-and[string]$receipt.authorityContext.repositoryGitTop-ceq'UNPROVEN'-and[string]$receipt.actionKind-in$categoricalActions){$missingPrep+='REPOSITORY_GIT_TOP_UNPROVEN'}
    $missingResult=@()
    if($mode-ceq'FINALIZE_OUTPUT'){$missingResult=@($requiredResult|Where-Object{$_-cnotin$providedResult})}
    if($mode-ceq'FINALIZE_OUTPUT'-and[string]$input.resultKind-in@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE')-and@($input.deliveryReceipts).Count-eq0){$missingResult+=@('DELIVERY_RECEIPT')}
    $status=if($missingPrep.Count-gt0-or$missingResult.Count-gt0){'BLOCKED'}else{'PASS'}
    $reason=if($missingPrep.Count-gt0){'PREPARATION_INCOMPLETE'}elseif($missingResult.Count-gt0){'RESULT_INCOMPLETE'}else{'STRUCTURAL_REQUIREMENTS_COMPLETE'}
    $material=@($receipt.sourceCompositionIdentity,$receipt.selectionIdentity,$receipt.contextIdentity,$mode,[string]$input.objective,[string]$input.actionKind,[string]$input.resultKind,[string]::Join(',',@($input.exactPaths)),[string]$input.authorizationIdentity,[string]::Join(',',@($input.preparationReceipts)),[string]::Join(',',@($input.resultReceipts)),[string]::Join(',',@($input.deliveryReceipts)),[string]$input.publicDecisionIdentity,[string]$input.protectionState)-join"`n"
    $decision=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($material)))
    $result=[ordered]@{status=$status;mode=$mode;reason=$reason;artifactStorage=$artifactStorage;selectionIdentity=$receipt.selectionIdentity;decisionIdentity=$decision;sourceBuildCount=[int]$receipt.sourceBuildCount;decisionBuildCount=1;missingPreparation=@($missingPrep);missingResult=@($missingResult);authorityGranted=$false;semanticCorrectnessProven=$false;hostInvocationProven=$false}
  }else{throw 'INPUT_MODE'}
  if($AsJson){$result|ConvertTo-Json -Depth 50 -Compress}else{$count=if($mode-ceq'DISCOVER'){@($result.selectedRuleBlocks).Count}else{@($receipt.selectedObligations).Count};Write-Output ($result.status+'|'+$mode+'|requirements='+$count)}
  if([string]$result.status-cnotin @('PASS','EVALUATION_ONLY')){exit 3}
}catch{if($AsJson){[ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|'+[string]$_.Exception.Message)};exit 2}finally{if($null-ne$cleanupInput-and(Test-Path -LiteralPath $cleanupInput -PathType Leaf)){Remove-Item -LiteralPath $cleanupInput -Force}}
