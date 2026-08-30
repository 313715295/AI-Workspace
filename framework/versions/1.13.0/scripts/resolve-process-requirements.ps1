[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -Force
$utf8=[Text.UTF8Encoding]::new($false,$true)

function Get-Identity([string]$Path){$b=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path));return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
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
function Assert-StringArray($v,[string]$name){if(-not($v-is[Array])){throw "INPUT_ARRAY|$name"};$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($i in @($v)){if(-not($i-is[string])-or[string]::IsNullOrWhiteSpace([string]$i)-or-not$seen.Add([string]$i)){throw "INPUT_ARRAY_ITEM|$name"}}}
function Assert-InputString($v,[string]$name){if(-not($v-is[string])-or[string]::IsNullOrWhiteSpace([string]$v)){throw "INPUT_STRING|$name"}}
function Assert-ActionAndResult([string]$action,[string]$result){if($action-cnotin@('NONE','CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','OWNER_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')){throw 'ACTION_KIND'};if($result-cnotin@('NONE','PLAN','USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE','IMPLEMENTATION_RESULT','TEST_RESULT','GIT_RESULT','EXTERNAL_RESULT')){throw 'RESULT_KIND'}}
function Assert-ExactPaths($paths){Assert-StringArray $paths 'exactPaths';foreach($path in @($paths)){if([string]$path-cne([string]$path).Replace('\','/')-or[IO.Path]::IsPathRooted([string]$path)-or([string]$path).Contains(':')){throw 'EXACT_PATH'};foreach($part in ([string]$path).Split('/')){if([string]::IsNullOrWhiteSpace($part)-or$part-in@('.','..')){throw 'EXACT_PATH'}}}}
function Get-Receipt([string]$Path){
  $r=Read-Input $Path
  Assert-Fields $r @('schemaVersion','receiptType','status','mode','sourceCompositionIdentity','selectionIdentity','projectId','frameworkVersion','taskIdentity','actor','role','phase','profile','objective','actionKind','resultKind','exactPaths','selectedRequirements','sourceLocators','sourceBindings','evidenceCeilings','sourceBuildCount','legacyCorrectionsFullReadCount','legacyProjectCustomFullReadCount','hostEnforcementGrade','authorityGranted','semanticCorrectnessProven')
  if(-not(Test-JsonInteger $r.schemaVersion)-or[int]$r.schemaVersion-ne1-or-not($r.authorityGranted-is[bool])-or-not($r.semanticCorrectnessProven-is[bool])-or[string]$r.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or[string]$r.mode-cne'DISCOVER'-or[string]$r.status-cnotin@('PASS','EVALUATION_ONLY')-or[string]$r.frameworkVersion-cne'1.13.0'-or[bool]$r.authorityGranted-or[bool]$r.semanticCorrectnessProven){throw 'DISCOVER_RECEIPT_TYPE'}
  foreach($countName in @('sourceBuildCount','legacyCorrectionsFullReadCount','legacyProjectCustomFullReadCount')){if(-not(Test-JsonInteger $r.$countName)-or[int]$r.$countName-lt0){throw ('DISCOVER_RECEIPT_COUNT|'+$countName)}}
  foreach($name in @('sourceCompositionIdentity','selectionIdentity','projectId','taskIdentity','actor','role','phase','profile','objective','actionKind','resultKind','hostEnforcementGrade')){Assert-InputString $r.$name $name}
  Assert-StringArray $r.exactPaths 'receiptExactPaths';Assert-StringArray $r.evidenceCeilings 'receiptEvidenceCeilings'
  if(-not($r.selectedRequirements-is[Array])){throw 'DISCOVER_RECEIPT_REQUIREMENTS'}
  foreach($requirement in @($r.selectedRequirements)){
    if(-not($requirement-is[pscustomobject])){throw 'DISCOVER_RECEIPT_REQUIREMENT_TYPE'}
    $requirementFields=@($requirement.PSObject.Properties.Name)
    $requiredFields=@('requirementId','source','semanticApplicability','fullText','preparationRequirements','resultRequirements')
    if(@($requiredFields|Where-Object{$_-cnotin$requirementFields}).Count-ne0-or@($requirementFields|Where-Object{$_-cnotin@($requiredFields+'sourceAliases')}).Count-ne0){throw 'DISCOVER_RECEIPT_REQUIREMENT_FIELDS'}
    foreach($name in @('requirementId','source','semanticApplicability','fullText')){Assert-InputString $requirement.$name $name}
    Assert-StringArray $requirement.preparationRequirements 'receiptPreparationRequirements';Assert-StringArray $requirement.resultRequirements 'receiptResultRequirements'
    if($requirementFields-ccontains'sourceAliases'){
      if(-not($requirement.sourceAliases-is[Array])){throw 'DISCOVER_RECEIPT_SOURCE_ALIASES'}
      $seenAliases=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      foreach($alias in @($requirement.sourceAliases)){Assert-Fields $alias @('legacyRequirementId','legacySourceRecordIdentity');Assert-InputString $alias.legacyRequirementId 'legacyRequirementId';Assert-InputString $alias.legacySourceRecordIdentity 'legacySourceRecordIdentity';if(-not$seenAliases.Add([string]$alias.legacyRequirementId)-or[string]$alias.legacySourceRecordIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'DISCOVER_RECEIPT_SOURCE_ALIAS'}}
    }
  }
  Assert-Fields $r.sourceLocators @('projectRoot','frameworkRoot','taskRelativePath')
  foreach($name in @('projectRoot','frameworkRoot','taskRelativePath')){Assert-InputString $r.sourceLocators.$name $name}
  Assert-Fields $r.sourceBindings @('projectConfigIdentity','correctionsIdentity','policyIdentity','projectCustomIdentity','taskIdentity','frameworkVersionIdentity','releaseManifestIdentity','nativeCatalogIdentity','correctionCoverageIdentity')
  foreach($name in @($r.sourceBindings.PSObject.Properties.Name)){Assert-InputString $r.sourceBindings.$name $name;if([string]$r.sourceBindings.$name-cne'MISSING'-and[string]$r.sourceBindings.$name-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('DISCOVER_RECEIPT_BINDING|'+$name)}}
  return $r
}
try{
  $input=Read-Input $InputPath
  if(-not($input-is[pscustomobject])-or$null-eq$input.PSObject.Properties['mode']-or-not($input.mode-is[string])){throw 'INPUT_MODE'}
  $mode=[string]$input.mode
  if($mode-ceq'DISCOVER'){
    $fields=@('schemaVersion','mode','projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities','objective','actionKind','resultKind','exactPaths','hostEnforcementGrade','evaluationOnly')
    Assert-Fields $input $fields
    if(-not(Test-JsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-ne1){throw 'INPUT_SCHEMA_VERSION'}
    foreach($n in @('projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedTaskIdentity','observedActor','objective','actionKind','resultKind','hostEnforcementGrade')){if(-not($input.$n-is[string])-or[string]::IsNullOrWhiteSpace([string]$input.$n)){throw "INPUT_STRING|$n"}}
    Assert-InputString $input.expectedCorrectionsIdentity 'expectedCorrectionsIdentity'
    foreach($n in @('expectedProjectConfigIdentity','expectedTaskIdentity')){if([string]$input.$n-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('INPUT_IDENTITY|'+$n)}}
    if([string]$input.expectedCorrectionsIdentity-cne'MISSING'-and[string]$input.expectedCorrectionsIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INPUT_IDENTITY|expectedCorrectionsIdentity'}
    Assert-StringArray $input.capabilities 'capabilities';Assert-ExactPaths $input.exactPaths;Assert-ActionAndResult ([string]$input.actionKind) ([string]$input.resultKind)
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
    $actor=[string]$route[0].Groups['actor'].Value;if($actor-cne[string]$input.observedActor){throw 'CONFLICT_ACTOR_ROLE_PHASE'}
    $profileMatch=[regex]::Matches($taskText,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL);');if($profileMatch.Count-ne1){throw 'TASK_PROFILE'}
    $composition=Invoke-ProcessRequirementComposition -ProjectRoot ([string]$input.projectRoot) -FrameworkRoot ([string]$input.frameworkRoot) -TargetVersion '1.13.0' -ExpectedProjectConfigIdentity ([string]$input.expectedProjectConfigIdentity) -ExpectedCorrectionsIdentity ([string]$input.expectedCorrectionsIdentity) -Profile ([string]$profileMatch[0].Groups['profile'].Value) -Role ([string]$route[0].Groups['role'].Value) -Phase ([string]$route[0].Groups['phase'].Value) -Actor $actor -TaskIdentity $taskIdentity -Capabilities @($input.capabilities) -Objective ([string]$input.objective) -ActionKind ([string]$input.actionKind) -ResultKind ([string]$input.resultKind) -ExactPaths @($input.exactPaths) -EvaluationOnly:([bool]$input.evaluationOnly)
    $selectionMaterial=@($composition.sourceCompositionIdentity,[string]$input.objective,[string]$input.actionKind,[string]$input.resultKind,[string]::Join("`n",@($input.exactPaths)))-join"`n"
    $selectionIdentity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($selectionMaterial)))
    $ceilings=@($composition.evidenceCeilings);if([string]$input.hostEnforcementGrade-ceq'INSTRUCTION_BOUND'){$ceilings+='INVOCATION_UNPROVEN'};if([bool]$input.evaluationOnly){$ceilings+='NON_AUTHORITY_EVALUATION_ONLY'}
    $result=[ordered]@{schemaVersion=1;receiptType='PROCESS_REQUIREMENTS_DISCOVER';status=[string]$composition.status;mode=$mode;sourceCompositionIdentity=$composition.sourceCompositionIdentity;selectionIdentity=$selectionIdentity;projectId=$composition.projectId;frameworkVersion='1.13.0';taskIdentity=$taskIdentity;actor=$actor;role=[string]$route[0].Groups['role'].Value;phase=[string]$route[0].Groups['phase'].Value;profile=[string]$profileMatch[0].Groups['profile'].Value;objective=[string]$input.objective;actionKind=[string]$input.actionKind;resultKind=[string]$input.resultKind;exactPaths=@($input.exactPaths);selectedRequirements=@($composition.selectedRequirements);sourceLocators=[ordered]@{projectRoot=$projectResolved;frameworkRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.frameworkRoot))));taskRelativePath=$taskRelative};sourceBindings=[ordered]@{projectConfigIdentity=$composition.projectConfigIdentity;correctionsIdentity=$composition.correctionsIdentity;policyIdentity=$composition.policyIdentity;projectCustomIdentity=$composition.projectCustomIdentity;taskIdentity=$taskIdentity;frameworkVersionIdentity=$composition.frameworkVersionIdentity;releaseManifestIdentity=$composition.releaseManifestIdentity;nativeCatalogIdentity=$composition.nativeCatalogIdentity;correctionCoverageIdentity=$composition.correctionCoverageIdentity};evidenceCeilings=@($ceilings);sourceBuildCount=$composition.sourceBuildCount;legacyCorrectionsFullReadCount=$composition.legacyCorrectionsFullReadCount;legacyProjectCustomFullReadCount=$composition.legacyProjectCustomFullReadCount;hostEnforcementGrade=[string]$input.hostEnforcementGrade;authorityGranted=$false;semanticCorrectnessProven=$false}
  }elseif($mode-in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
    $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','objective','actionKind','resultKind','exactPaths','authorizationIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')
    Assert-Fields $input $fields
    if(-not(Test-JsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-ne1){throw 'INPUT_SCHEMA_VERSION'}
    foreach($n in @('discoverReceiptPath','expectedDiscoverReceiptIdentity','objective','actionKind','resultKind','authorizationIdentity','publicDecisionIdentity','protectionState')){Assert-InputString $input.$n $n}
    if([string]$input.expectedDiscoverReceiptIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INPUT_IDENTITY|expectedDiscoverReceiptIdentity'}
    Assert-ExactPaths $input.exactPaths;foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){Assert-StringArray $input.$name $name};Assert-ActionAndResult ([string]$input.actionKind) ([string]$input.resultKind)
    $categoricalActions=@('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','OWNER_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')
    if([string]$input.actionKind-in$categoricalActions-and[string]$input.authorizationIdentity-cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'AUTHORIZATION_RECEIPT_IDENTITY'}
    if([string]$input.actionKind-cnotin$categoricalActions-and[string]$input.authorizationIdentity-cne'NOT_REQUIRED'-and[string]$input.authorizationIdentity-cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'AUTHORIZATION_RECEIPT_IDENTITY'}
    if([string]$input.publicDecisionIdentity-cne'NOT_REQUIRED'-and[string]$input.publicDecisionIdentity-cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'PUBLIC_DECISION_IDENTITY'}
    if([string]$input.protectionState-cnotin@('BOUND','NOT_APPLICABLE')){throw 'PROTECTION_STATE'}
    $receiptIdentity=Get-Identity ([string]$input.discoverReceiptPath);if($receiptIdentity-cne[string]$input.expectedDiscoverReceiptIdentity){throw 'DISCOVER_RECEIPT_DRIFT'}
    $receipt=Get-Receipt ([string]$input.discoverReceiptPath)
    $currentBindings=Get-AiwProcessBindingSnapshot -ProjectRoot ([string]$receipt.sourceLocators.projectRoot) -FrameworkRoot ([string]$receipt.sourceLocators.frameworkRoot) -TargetVersion '1.13.0' -TaskRelativePath ([string]$receipt.sourceLocators.taskRelativePath)
    foreach($name in @($receipt.sourceBindings.PSObject.Properties.Name)){if([string]$currentBindings.$name-cne[string]$receipt.sourceBindings.$name){throw ('DISCOVER_SOURCE_DRIFT|'+$name)}}
    if([string]$input.objective-cne[string]$receipt.objective-or[string]$input.actionKind-cne[string]$receipt.actionKind-or[string]$input.resultKind-cne[string]$receipt.resultKind-or[string]::Join("`n",@($input.exactPaths))-cne[string]::Join("`n",@($receipt.exactPaths))){throw 'DISCOVER_CONTEXT_DRIFT'}
    $requiredPrep=@($receipt.selectedRequirements|ForEach-Object{if($_.PSObject.Properties['preparationRequirements']){@($_.preparationRequirements)}}|Sort-Object -Unique)
    $requiredResult=@($receipt.selectedRequirements|ForEach-Object{if($_.PSObject.Properties['resultRequirements']){@($_.resultRequirements)}}|Sort-Object -Unique)
    $providedPrep=@($input.preparationReceipts);$providedResult=@($input.resultReceipts)
    $missingPrep=@($requiredPrep|Where-Object{$_-cnotin$providedPrep})
    $missingResult=@()
    if($mode-ceq'FINALIZE_OUTPUT'){$missingResult=@($requiredResult|Where-Object{$_-cnotin$providedResult})}
    if($mode-ceq'FINALIZE_OUTPUT'-and[string]$input.resultKind-in@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE')-and@($input.deliveryReceipts).Count-eq0){$missingResult+=@('DELIVERY_RECEIPT')}
    $status=if($missingPrep.Count-gt0-or$missingResult.Count-gt0){'BLOCKED'}else{'PASS'}
    $reason=if($missingPrep.Count-gt0){'PREPARATION_INCOMPLETE'}elseif($missingResult.Count-gt0){'RESULT_INCOMPLETE'}else{'STRUCTURAL_REQUIREMENTS_COMPLETE'}
    $material=@($receipt.sourceCompositionIdentity,$receipt.selectionIdentity,$mode,[string]$input.objective,[string]$input.actionKind,[string]$input.resultKind,[string]::Join(',',@($input.exactPaths)),[string]$input.authorizationIdentity,[string]::Join(',',@($input.preparationReceipts)),[string]::Join(',',@($input.resultReceipts)),[string]::Join(',',@($input.deliveryReceipts)),[string]$input.publicDecisionIdentity,[string]$input.protectionState)-join"`n"
    $decision=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($material)))
    $result=[ordered]@{status=$status;mode=$mode;reason=$reason;sourceCompositionIdentity=$receipt.sourceCompositionIdentity;selectionIdentity=$receipt.selectionIdentity;decisionIdentity=$decision;selectedRequirementIds=@($receipt.selectedRequirements.requirementId);missingPreparation=@($missingPrep);missingResult=@($missingResult);sourceBuildCount=$receipt.sourceBuildCount;decisionBuildCount=1;authorityGranted=$false;semanticCorrectnessProven=$false;hostInvocationProven=$false}
  }else{throw 'INPUT_MODE'}
  if($AsJson){$result|ConvertTo-Json -Depth 30 -Compress}else{Write-Output ($result.status+'|'+$mode+'|requirements='+@($result.selectedRequirements).Count)}
  if([string]$result.status-cnotin @('PASS','EVALUATION_ONLY')){exit 3}
}catch{if($AsJson){[ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|'+[string]$_.Exception.Message)};exit 2}
