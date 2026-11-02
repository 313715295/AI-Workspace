[CmdletBinding()]
param([switch]$KeepFixture,[switch]$MaintenanceFixture,[ValidateSet('All','RuleSelection','SourceChangeRecovery','KnowledgeEnable')][string]$Group='All')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Group=@('All','RuleSelection','SourceChangeRecovery','KnowledgeEnable')|Where-Object{$_-ieq$Group}
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')

if($Group-ceq'All'){
 $total=0
 foreach($selected in @('RuleSelection','SourceChangeRecovery','KnowledgeEnable')){
  $arguments=@('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Group',$selected)
  if($KeepFixture){$arguments+='-KeepFixture'};if($MaintenanceFixture){$arguments+='-MaintenanceFixture'}
  $process=Invoke-AiwTestProcess ([Environment]::ProcessPath) $arguments;$raw=@($process.Output);$code=$process.Code
  foreach($line in $raw){Write-Output $line}
  if($code-ne0){exit $code}
  $results=@($raw|Where-Object{$_-cmatch'^STANDARD_PRESETS_TESTS_PASS\|checks=(\d+)\|'})
  if($results.Count-ne1){throw 'PRESET_GROUP_RESULT_REQUIRED'}
  $total+=[int]([regex]::Match($results[0],'^STANDARD_PRESETS_TESTS_PASS\|checks=(\d+)\|').Groups[1].Value)
 }
 Write-Output ('STANDARD_PRESETS_TESTS_PASS|checks='+$total+'|group=All|evidence=ISOLATED_GROUPS')
 return
}

$bodyTimer=$null;$passed=0;$utf8=[Text.UTF8Encoding]::new($false);$sourceNegativesDone=$false;$sourceGroupNegativesDone=$false
$versionRoot=Split-Path -Parent $PSScriptRoot
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-standard-presets-'+[guid]::NewGuid().ToString('N'))
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 60)}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw "ASSERT_FAIL|$Name"};$script:passed++;Write-Output "PASS|$Name"}
function Reject([scriptblock]$Action,[string]$Pattern,[string]$Name){$reason='';try{& $Action|Out-Null}catch{$reason=$_.Exception.Message};Check ($reason-match$Pattern) ($Name+'|'+$reason)}

function PresetTiming([string]$Stage,[string]$Operation,[double]$Milliseconds){
 Write-Host ('PRESET_TIMING|group='+$Group+'|layout='+$(if($MaintenanceFixture){'Maintenance'}else{'Ordinary'})+'|stage='+$Stage+'|operation='+$Operation+'|elapsedMs='+$Milliseconds.ToString('F3',[Globalization.CultureInfo]::InvariantCulture))
}
function InvokePresetProcess([string]$Tool,[hashtable]$Parameters,[string]$Operation,[switch]$JsonOutput){
 $prepareTimer=[Diagnostics.Stopwatch]::StartNew()
 $runner=Join-Path $temp 'timed-tool-runner.ps1'
 if(-not(Test-Path -LiteralPath $runner)){
  SaveText $runner ((@'
param([string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
Write-Output ('PRESET_CHILD|READY|'+[DateTime]::UtcNow.ToString('o'))
$targetTimer=$null;$code=0
try{
 $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
 $parameters=$call.parameters;$LASTEXITCODE=0
 $targetTimer=[Diagnostics.Stopwatch]::StartNew()
 $output=@(& $call.tool @parameters)
 $code=$LASTEXITCODE
 if($call.jsonOutput-and$code-eq0){ConvertTo-Json -InputObject $output -Depth 100 -Compress}else{$output|ForEach-Object{Write-Output $_}}
}catch{Write-Output ($_.Exception.Message+'|'+$_.ScriptStackTrace);$code=2}
finally{
 if($null-ne$targetTimer){$targetTimer.Stop();Write-Output ('PRESET_CHILD|TARGET|'+$targetTimer.Elapsed.TotalMilliseconds.ToString('F3',[Globalization.CultureInfo]::InvariantCulture))}
}
exit $code
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 }
 $callPath=Join-Path $temp ('timed-call-'+[guid]::NewGuid().ToString('N')+'.json')
 SaveJson $callPath @{tool=$Tool;parameters=$Parameters;jsonOutput=[bool]$JsonOutput}
 $prepareTimer.Stop();PresetTiming 'preparation' $Operation $prepareTimer.Elapsed.TotalMilliseconds
 $started=[DateTime]::UtcNow;$processTimer=[Diagnostics.Stopwatch]::StartNew()
 $process=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$runner,'-InputPath',$callPath) -GroupId ('preset-'+$Group+'-'+$Operation);$raw=@($process.Output);$code=$process.Code
 $processTimer.Stop();$ready=@($raw|Where-Object{$_-clike'PRESET_CHILD|READY|*'});$target=@($raw|Where-Object{$_-clike'PRESET_CHILD|TARGET|*'})
 $startup=0.0;$targetMs=0.0
 if($ready.Count-eq1){$startup=([DateTime]::Parse($ready[0].Substring(19),[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)-$started).TotalMilliseconds;PresetTiming 'process-start' $Operation $startup}
 if($target.Count-eq1){$targetMs=[double]::Parse($target[0].Substring(20),[Globalization.CultureInfo]::InvariantCulture);PresetTiming 'target-child' $Operation $targetMs}
 PresetTiming 'process-exit-capture' $Operation ([Math]::Max(0,$processTimer.Elapsed.TotalMilliseconds-$startup-$targetMs))
 $output=@($raw|Where-Object{$_-cnotlike'PRESET_CHILD|*'})
 return [pscustomobject]@{code=$code;output=$output;text=($output-join"`n")}
}

function RegisterFixture {
 $callPath=Join-Path $temp 'register-call.json';$runnerPath=Join-Path $temp 'register-runner.ps1'
 $registration=@{ProjectId='standards-fixture';DisplayName='Standards fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId='fixture-actor';WorkspaceRoot=$frameworkRoot;Apply=$true}
 if($MaintenanceFixture){$registration.ControlPlaneLayout='framework-maintenance-sibling';$registration.FrameworkTargetRepositoryId='source-fixture';$registration.FrameworkTargetSiblingDirectory='target'}
 SaveJson $callPath @{tool=(Join-Path $frameworkRoot 'scripts/register-project.ps1');parameters=$registration}
 SaveText $runnerPath @'
param([string]$InputPath)
$ErrorActionPreference='Stop'
try{
 $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
 $arguments=$call.parameters;$LASTEXITCODE=0
 $output=@(& $call.tool @arguments)
 if($LASTEXITCODE-ne0){$output|ForEach-Object{Write-Output $_};exit $LASTEXITCODE}
 ConvertTo-Json -InputObject $output -Depth 100 -Compress
}catch{Write-Output ($_.Exception.Message+'|'+$_.ScriptStackTrace);exit 2}
'@
 $process=InvokePresetProcess (Join-Path $frameworkRoot 'scripts/register-project.ps1') $registration 'Register' -JsonOutput
 $raw=@($process.output);$code=$process.code
 $parsed=$null;if($code-eq0){$parsed=($raw-join"`n")|ConvertFrom-Json -Depth 100}
 SaveJson (Join-Path $temp 'register-result.json') @{invocation=$callPath;exitCode=$code;output=($raw-join"`n");parsed=$parsed}
 if($code-ne0){throw ('PUBLIC_PRESET_REGISTER_FAILED|'+($raw-join"`n"))}
 return $parsed
}
function Compose([string]$Role,[string]$Action,[string]$Hints,[string[]]$WorkTypes=@('aiw:design','aiw:implementation','aiw:verification'),[string[]]$Domains=@('aiw:software'),[switch]$ValidateCompleteAdoptedSet){
 $phase=if($Action-ceq'REVIEW_EXECUTE'){'REVIEW'}elseif($Action-ceq'RESULT_ACCEPT'){'VERIFY'}else{'IMPLEMENT'}
 $result=if($Action-ceq'REVIEW_EXECUTE'){'REVIEW_VERDICT'}elseif($Action-ceq'RESULT_ACCEPT'){'RESULT_ACCEPTANCE'}else{'IMPLEMENTATION_RESULT'}
 if(-not$PSBoundParameters.ContainsKey('WorkTypes')){if($Action-ceq'REVIEW_EXECUTE'){$WorkTypes=@('aiw:review')}elseif($Action-ceq'RESULT_ACCEPT'){$WorkTypes=@('aiw:acceptance')}}
 $intent=[pscustomobject]@{schemaVersion=2;objective=$Hints;requestedActionKind=$Action;requestedResultKind=$result;semanticHints=@($Hints);pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=[pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=$Domains};workType=[pscustomobject]@{state='KNOWN';values=$WorkTypes};deliverableType=[pscustomobject]@{state='KNOWN';values=@(if($Action-ceq'REVIEW_EXECUTE'){'aiw:review-verdict'}elseif($Action-ceq'RESULT_ACCEPT'){'aiw:acceptance-result'}else{'aiw:code'})};stage=[pscustomobject]@{state='KNOWN';values=@(if($Action-ceq'REVIEW_EXECUTE'){'aiw:review'}elseif($Action-ceq'RESULT_ACCEPT'){'aiw:acceptance'}else{'aiw:implementation'})}}}
 return Invoke-ProcessRequirementComposition -ProjectRoot $project -FrameworkRoot $frameworkRoot -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity (Get-AiwFileIdentity $configPath) -ExpectedCorrectionsIdentity (Get-AiwFileIdentity $correctionsPath) -Profile STANDARD -Role $Role -Phase $phase -Actor fixture-actor -TaskIdentity (Get-AiwFileIdentity $taskPath) -ActionKind $Action -ResultKind $result -Objective $Hints -IntentEnvelope $intent -ExactPaths @() -UseDeclaredCapabilities -EvaluationOnly -ValidateCompleteAdoptedSet:$ValidateCompleteAdoptedSet
}
function ProjectRules($Result){return @($Result.selectedRequirements|Where-Object{$_.requirementId.StartsWith('project:')})}
function RunSourceBoundary([string]$Path){
 $entry=if($MaintenanceFixture){Join-Path $frameworkRoot 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $copy 'scripts/resolve-process-requirements.ps1'}
 $process=InvokePresetProcess $entry @{InputPath=$Path;AsJson=$true} 'Boundary'
 $raw=@($process.output)
 $code=$process.code;$value=$null;try{$value=($raw-join"`n")|ConvertFrom-Json -Depth 100}catch{}
 return [pscustomobject]@{code=$code;value=$value;text=($raw-join"`n")}
}
function AdoptFixturePreset($Preparation,[string]$Interruption='DIRECT',[string]$Direction='COMPLETE',[string]$OfflineSource='',[string]$CapabilityIssuer='PROJECT_CONTROLLER'){
 $caseRoot=Join-Path $project ('.ai-workspace/runtime/STANDARDS-001/fixture-actor/'+[guid]::NewGuid().ToString('N'))
 $null=[IO.Directory]::CreateDirectory($caseRoot)
 $config=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100;$config.sourceBindings=@($Preparation.sourceBindings)
 $oldCapabilities=@($config.frameworkCapabilities.PSObject.Properties|Where-Object{$_.Value.enabled}|ForEach-Object Name)
 $firstEnable=$null-ne$Preparation.PSObject.Properties['knowledgeCapability']-and'KNOWLEDGE_REFERENCE'-cnotin$oldCapabilities
 if($null-ne$Preparation.PSObject.Properties['knowledgeCapability']){$config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=$Preparation.knowledgeCapability}}
 if($null-ne$Preparation.PSObject.Properties['knowledgeSources']){$config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources=@($Preparation.knowledgeSources)}
 $nextPolicy=$policy|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$nextPolicy.rules=@($Preparation.rules)
 if($MaintenanceFixture){$nextPolicy.rules+=@($policy.rules|Where-Object ruleId -CEQ 'FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY')}
 $configCandidate=Join-Path $caseRoot 'config.json';$policyCandidate=Join-Path $caseRoot 'policy.json'
 $originalConfig=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
 $originalPolicy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
 if((ConvertTo-AiwContentCanonicalJson $config)-ceq(ConvertTo-AiwContentCanonicalJson $originalConfig)){[IO.File]::Copy($configPath,$configCandidate)}else{SaveJson $configCandidate $config}
 if((ConvertTo-AiwContentCanonicalJson $nextPolicy)-ceq(ConvertTo-AiwContentCanonicalJson $originalPolicy)){[IO.File]::Copy($policyPath,$policyCandidate)}else{SaveJson $policyCandidate $nextPolicy}
 $paths=@(if((Get-AiwFileIdentity $policyPath)-cne(Get-AiwFileIdentity $policyCandidate)){'.ai-workspace/process-policy.json'};if((Get-AiwFileIdentity $configPath)-cne(Get-AiwFileIdentity $configCandidate)){'.ai-workspace/project.json'})
 if($paths.Count-eq0){throw 'FIXTURE_NO_ACTUAL_SOURCE_CHANGE'}
 $decisionPath=Join-Path $caseRoot 'decision.md';SaveText $decisionPath 'Fixture decision explicitly adopts the exact source permissions and complete config/policy candidate.'
 $decision=[pscustomobject]@{path=$decisionPath;identity=Get-AiwFileIdentity $decisionPath}
 $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='STANDARDS-001';profile='STANDARD';lifecycle='ACTIVE';owner='fixture-actor';issuer='fixture-actor';issuerRole='TASK_OWNER';grantee='fixture-actor';bundle='SOURCE_ADOPTION_FIXTURE';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-AiwFileIdentity $taskPath;actions=@('CONTROL_WRITE');exactPaths=$paths;objectIdentities=@($paths|ForEach-Object{@{path=$_;identity=Get-AiwFileIdentity (Join-Path $project $_)}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=Get-AiwFileIdentity $configPath}
 $packagePath=Join-Path $caseRoot 'package.json';SaveJson $packagePath $package
 if($firstEnable-and$CapabilityIssuer-ceq'PROJECT_CONTROLLER'){
  $package.issuerRole='PROJECT_CONTROLLER';$package.issuerControllerId='fixture-actor';$package.issuerControllerEpoch=1
  $package.controllerControlIdentity=Get-AiwFileIdentity (Join-Path $project '.ai-workspace/controller.json')
  $package.invalidatesOn+='CONTROLLER_EPOCH_CHANGE'
  SaveJson $packagePath $package
 }
 if($MaintenanceFixture){$package.schemaVersion=2;$package.repositoryId='CONTROL';$package.invalidatesOn+='REPOSITORY_CHANGE';SaveJson $packagePath $package}
 $location=Get-Location;$currentDirectory=[Environment]::CurrentDirectory
 try{
  Set-Location -LiteralPath $project;[Environment]::CurrentDirectory=$project
  $check=@{PackagePath=$packagePath;ObservedActor='fixture-actor';ObservedTaskId='STANDARDS-001';ObservedOwner='fixture-actor';ObservedAction='CONTROL_WRITE';ObservedPath=$paths;ObservedIdentity=@($package.objectIdentities|ForEach-Object{$_.path+'='+$_.identity});TaskPath='.ai-workspace/tasks/active/STANDARDS-001.md';ExpectedTaskIdentity=$package.taskIdentity;ControllerControlPath='.ai-workspace/controller.json'}
  $checker=Join-Path $copy 'scripts/check-authorization.ps1'
  if($MaintenanceFixture){$checker=Join-Path $frameworkRoot 'scripts/check-framework-maintenance-authorization.ps1';$check.ControlRepositoryPath=$project;$check.ObservedRepositoryId='CONTROL';$check.ExpectedProjectConfigIdentity=$package.projectConfigIdentity}
  $raw=@(& $checker @check 2>&1)
  if($LASTEXITCODE-ne0){throw ('SOURCE_ADOPTION_CHECKER|'+($raw-join';'))}
 }finally{Set-Location $location;[Environment]::CurrentDirectory=$currentDirectory}
 $intent=[ordered]@{schemaVersion=2;objective='Adopt the explicitly selected project sources';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('software source adoption');pathHints=$paths;capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=@{state='KNOWN';values=@('aiw:design','aiw:implementation','aiw:verification')};deliverableType=@{state='KNOWN';values=@('aiw:code')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}
 $discoverPath=Join-Path $caseRoot 'discover.json'
 SaveJson $discoverPath @{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=(Get-AiwFileIdentity $configPath);expectedCorrectionsIdentity=(Get-AiwFileIdentity $correctionsPath);expectedTaskIdentity=(Get-AiwFileIdentity $taskPath);observedActor='fixture-actor';capabilities=$oldCapabilities;exactPaths=$paths;forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Get-AiwFileIdentity $packagePath);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
 $run=RunSourceBoundary $discoverPath;if($run.code-ne0){throw ('SOURCE_ADOPTION_DISCOVER|'+$run.text)}
 $receiptPath=Join-Path $caseRoot 'compact.json';SaveJson $receiptPath $run.value.compactReceipt
 $prepareArgs=@{DiscoverReceiptPath=$receiptPath;ExpectedDiscoverReceiptIdentity=(Get-AiwFileIdentity $receiptPath);ConfigPostimagePath=$configCandidate;PolicyPostimagePath=$policyCandidate;DecisionRef=$decision;OutputDirectory=(Join-Path $caseRoot 'candidate')}
 if($Group-ceq'SourceChangeRecovery'-and-not$script:sourceNegativesDone){
  $validConfig=[IO.File]::ReadAllBytes($configCandidate)
  foreach($field in @('frameworkToolBackend','frameworkVersion','id','displayName','repositoryRoot','controlPlaneLayout','schemaVersion','routineExcludedPaths','processPolicy','frameworkCapabilities')){
   $bad=Get-Content $configCandidate -Raw|ConvertFrom-Json -Depth 100
   switch($field){schemaVersion{$bad.$field=5} routineExcludedPaths{$bad.$field=@('new-exclusion/')} processPolicy{$bad.processPolicy.locator='.ai-workspace/other.json'} frameworkCapabilities{$bad.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled=$false} default{$bad.$field='changed'}}
   SaveJson $configCandidate $bad
   Reject {New-AiwProjectSourceChangePreparation @prepareArgs} 'SOURCE_CHANGE_CONFIG_FIELDS|SOURCE_CHANGE_CURRENT_FORMAT|FORMAT_|CAPABILITY|SCHEMA|PROJECT_CONFIG' ('immutable-config-field-rejected-'+$field)
   [IO.File]::WriteAllBytes($configCandidate,$validConfig)
  }
  $bad=Get-Content $configCandidate -Raw|ConvertFrom-Json -Depth 100
  $bad.sourceBindings[0].locator.root=Join-Path $project 'private'
  SaveJson $configCandidate $bad
  $validPolicy=[IO.File]::ReadAllBytes($policyCandidate);$deniedPolicy=Get-Content $policyCandidate -Raw|ConvertFrom-Json -Depth 100
  foreach($rule in @($deniedPolicy.rules|Where-Object{$null-ne$_.PSObject.Properties['source']})){foreach($doc in $rule.source.documents){$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $bad.sourceBindings};$rule.source.revision=Get-AiwContentRevision $rule.source $bad.sourceBindings;$rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source};SaveJson $policyCandidate $deniedPolicy
  Reject {New-AiwProjectSourceChangePreparation @prepareArgs} 'FORBIDDEN' 'protected-source-rejected-before-missing-file-access'
  [IO.File]::WriteAllBytes($configCandidate,$validConfig)
  [IO.File]::WriteAllBytes($policyCandidate,$validPolicy)
  # A denied candidate may have allocated its private evidence directory.
  $prepareArgs.OutputDirectory=Join-Path $caseRoot 'allowed-candidate'
  $script:sourceNegativesDone=$true
 }
 $source=New-AiwProjectSourceChangePreparation @prepareArgs
 if($firstEnable){
  Check ('KNOWLEDGE_REFERENCE'-cnotin@($run.value.compactReceipt.binding.observedCapabilities)) 'first-enable-original-admission-keeps-old-capabilities'
  if(@($Preparation.rules|Where-Object ruleId -CEQ 'R2_KNOWLEDGE_GATE').Count){
   Check ('R2_KNOWLEDGE_PREPARED'-cin@($source.preparationRequirements)-and'R2_KNOWLEDGE_RESULT'-cin@($source.resultRequirements)-and'R2_KNOWLEDGE_GATE'-cnotin@($run.value.compactReceipt.selectedObligations.requirementId|ForEach-Object{($_ -split ':')[-1]})) 'first-enable-target-composition-selects-new-capability-obligations'
  }
 }
 $candidate=Get-Content $source.candidate.path -Raw|ConvertFrom-Json -Depth 100
 $prep=@(@($run.value.compactReceipt.selectedObligations|ForEach-Object preparationRequirements)+@($source.preparationRequirements)|Sort-Object -Unique)+@($source.preparationReceipt)
 $results=@(@($run.value.compactReceipt.selectedObligations|ForEach-Object resultRequirements)+@($source.resultRequirements)|Sort-Object -Unique)
 $admit=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-AiwFileIdentity $receiptPath;preparationReceipts=$prep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 $admitPath=Join-Path $caseRoot 'admit.json';SaveJson $admitPath $admit;$admission=RunSourceBoundary $admitPath
 if($admission.code-ne0){throw ('SOURCE_ADOPTION_ADMIT|'+$admission.text)}
 $admitResultPath=Join-Path $caseRoot 'admit-result.json';SaveJson $admitResultPath $admission.value
 Check ($admission.value.projectSourcePreparation.outcome-ceq'PREPARED') ('real-source-admission-'+$Interruption+'-'+$Direction)
 foreach($gate in @($source.preparationRequirements|Where-Object{$_-cmatch'^(F01_|R2_KNOWLEDGE_)'})){
  $bad=$admit|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.preparationReceipts=@($bad.preparationReceipts|Where-Object{$_-cne$gate});$badPath=Join-Path $caseRoot ('missing-'+$gate+'.json');SaveJson $badPath $bad;$badRun=RunSourceBoundary $badPath
  Check ($badRun.code-ne0-and$gate-cin@($badRun.value.missingPreparation)) ('target-preparation-obligation-enforced-'+$gate)
 }
 $side=if($Direction-ceq'ROLLBACK'){'preimage'}else{'postimage'}
 $selfPath=Join-Path $caseRoot 'self.json'
 SaveJson $selfPath @{schemaVersion=1;taskId='STANDARDS-001';actor='fixture-actor';candidateObjects=@($candidate.objects|Where-Object{$_.path-cin$paths}|ForEach-Object{@{path=$_.path;identity=$_.$side.identity}});requirementsRef=$decision;outcome='PASS';checks=@(@{id='source-candidate';method='MODEL_JUDGMENT';outcome='PASS';reason='Isolated fixture validates the exact candidate restoration or adoption; no production acceptance is claimed.';evidenceLocators=@($decision)});evidenceLocators=@($decision)}
 $self=@{kind='SELF_CHECK';path=$selfPath;identity=Get-AiwFileIdentity $selfPath}
 $final=$admit|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$final.mode='FINALIZE_OUTPUT';$final.evidenceRefs=@($self);$final.resultReceipts=$results
 $final.preparationReceipts+=('PROJECT_SOURCE_ADMISSION|'+$admitPath+'|'+(Get-AiwFileIdentity $admitPath)+'|'+$admitResultPath+'|'+(Get-AiwFileIdentity $admitResultPath))
 if($Group-ceq'SourceChangeRecovery'-and-not$script:sourceGroupNegativesDone){
  $oldPolicy=[IO.File]::ReadAllBytes($policyPath);$oldConfig=[IO.File]::ReadAllBytes($configPath)
  [IO.File]::WriteAllBytes($configPath,[IO.File]::ReadAllBytes($candidate.objects[1].postimage.path))
  Reject {Get-AiwProjectSourceChange -Receipt $run.value.compactReceipt -Boundary $final -Stage RECOVERY} 'SOURCE_CHANGE_UNREACHABLE_GROUP' 'config-first-unreachable-group-rejects-before-source-access'
  [IO.File]::WriteAllBytes($configPath,$oldConfig);SaveText $policyPath '{"thirdParty":true}'
  Reject {Get-AiwProjectSourceChange -Receipt $run.value.compactReceipt -Boundary $final -Stage RECOVERY} 'SOURCE_CHANGE_THIRD_PARTY_OBJECT' 'third-party-group-rejects-without-restoring-other-carrier'
  Check ((Get-AiwFileIdentity $configPath)-ceq$candidate.objects[1].preimage.identity) 'rejected-group-left-config-unmodified'
  [IO.File]::WriteAllBytes($policyPath,$oldPolicy);$script:sourceGroupNegativesDone=$true
 }
 if($Interruption-ceq'DIRECT'){
  foreach($entry in $candidate.objects|Where-Object{$_.path-cin$paths}){[IO.File]::WriteAllBytes((Join-Path $project $entry.path),[IO.File]::ReadAllBytes($entry.postimage.path))}
  $final.resultReceipts+=@($candidate.objects|Where-Object{$_.path-cin$paths}|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.postimage.identity})
  $finalPath=Join-Path $caseRoot 'finalize.json';SaveJson $finalPath $final;$closed=RunSourceBoundary $finalPath
  if($closed.code-ne0){throw ('SOURCE_ADOPTION_FINALIZE|'+$closed.text)}
  Check ($closed.value.projectSourcePreparation.outcome-ceq'COMPLETED') 'original-finalize-closes-exact-config-policy-candidate'
  foreach($gate in @($results|Where-Object{$_-cmatch'^(F01_|R2_KNOWLEDGE_)'})){
   $bad=$final|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.resultReceipts=@($bad.resultReceipts|Where-Object{$_-cne$gate});$badPath=Join-Path $caseRoot ('missing-'+$gate+'.json');SaveJson $badPath $bad;$badRun=RunSourceBoundary $badPath
   Check ($badRun.code-ne0-and$gate-cin@($badRun.value.missingResult)) ('old-or-new-result-obligation-enforced-'+$gate)
  }
   # The first real RuleSelection adoption covers these two admission guards.
   # Full adoption and explicit rebind still execute their real positive gates.
   if($Group-cne'RuleSelection'-or-not$script:originalAdmissionNegativesDone){
   $badFinal=$final|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badFinal.preparationReceipts=@($badFinal.preparationReceipts|Where-Object{$_-cnotlike'PROJECT_SOURCE_ADMISSION|*'})
  $badPath=Join-Path $caseRoot 'missing-admission.json';SaveJson $badPath $badFinal;$badRun=RunSourceBoundary $badPath
  Check ($badRun.code-ne0-and$badRun.text-match'SOURCE_CHANGE_ORIGINAL_ADMISSION_REQUIRED') 'whole-postimage-needs-actual-original-admission'
  $savedAdmission=[IO.File]::ReadAllBytes($admitPath);$badAdmit=$admit|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badAdmit.evidenceRefs=@($self);SaveJson $admitPath $badAdmit
  $badFinal=$final|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badFinal.preparationReceipts=@($badFinal.preparationReceipts|Where-Object{$_-cnotlike'PROJECT_SOURCE_ADMISSION|*'})+@('PROJECT_SOURCE_ADMISSION|'+$admitPath+'|'+(Get-AiwFileIdentity $admitPath)+'|'+$admitResultPath+'|'+(Get-AiwFileIdentity $admitResultPath));SaveJson $badPath $badFinal;$badRun=RunSourceBoundary $badPath
  Check ($badRun.code-ne0-and$badRun.text-match'SOURCE_CHANGE_ORIGINAL_ADMISSION_DECISION') 'boundary3-evidence-change-invalidates-original-decision'
   [IO.File]::WriteAllBytes($admitPath,$savedAdmission)
   $script:originalAdmissionNegativesDone=$true
   }
 }else{
  $changedObjects=@($candidate.objects|Where-Object{$_.path-cin$paths})
  $count=switch($Interruption){OLD{0} POLICY{1} NEW{$changedObjects.Count} JOURNAL{if($Direction-ceq'ROLLBACK'){$changedObjects.Count}else{0}} default{throw 'FIXTURE_INTERRUPTION'}}
  for($i=0;$i-lt$count;$i++){$entry=$changedObjects[$i];[IO.File]::WriteAllBytes((Join-Path $project $entry.path),[IO.File]::ReadAllBytes($entry.postimage.path))}
  $plan=@{schemaVersion=2;discoverReceiptPath=$receiptPath;discoverReceiptIdentity=Get-AiwFileIdentity $receiptPath;admitInputPath=$admitPath;admitInputIdentity=Get-AiwFileIdentity $admitPath;admitResultPath=$admitResultPath;admitResultIdentity=Get-AiwFileIdentity $admitResultPath;preparationReceipts=$prep;resultReceipts=$results;evidenceRefs=@($self);transactionRelativePath=('.ai-workspace/upgrade-recovery/project-rules/STANDARDS-001/'+[IO.Path]::GetFileName($caseRoot)+'/state.json')}
  $planPath=Join-Path $caseRoot 'recovery.json';SaveJson $planPath $plan
  $transactionModule=@(Import-Module (Join-Path $frameworkRoot 'scripts/ProjectAdoptionTransaction.psm1') -PassThru -Force)[0]
  $recover=$transactionModule.ExportedCommands['Invoke-AiwProjectRuleActionRecovery']
  $args=@{RepositoryRoot=$project;PlanPath=$planPath;ExpectedPlanIdentity=(Get-AiwFileIdentity $planPath);ObservedActor='fixture-actor';Direction=$Direction;Apply=$true}
  if($OfflineSource){
   if($Direction-cne'ROLLBACK'-or-not[IO.Path]::GetFullPath($OfflineSource).StartsWith([IO.Path]::GetFullPath($temp)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFullPath($OfflineSource).StartsWith([IO.Path]::GetFullPath($frameworkRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'OFFLINE_FIXTURE_SCOPE'}
   # A valid PINNED cache is an available source. Remove only the exact
   # target document and its provider-returned cache entry for this test.
   $offlineContext=New-AiwContentContext -ProjectRoot $project -ExpectedProjectConfigIdentity $candidate.objects[1].postimage.identity -ForbiddenPaths @('private/')
   $offlineSnapshot=Resolve-AiwContentSnapshot -Context $offlineContext -Descriptor $Preparation.rules[0].source
   $offlineRead=Read-AiwContentExact -Context $offlineContext -Snapshot $offlineSnapshot -Document $offlineSnapshot.facts.documents[0].document
   $offlineCachePath=[IO.Path]::GetFullPath($offlineRead.cachePath)
   $cachePrefix=[IO.Path]::GetFullPath((Join-Path $project '.ai-workspace/runtime/content-sources'))+[IO.Path]::DirectorySeparatorChar
   if(-not$offlineCachePath.StartsWith($cachePrefix,[StringComparison]::OrdinalIgnoreCase)-or-not($offlineCachePath+'.offline').StartsWith($cachePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'OFFLINE_CACHE_FIXTURE_SCOPE'}
   Check ([IO.Path]::GetFullPath($offlineRead.physicalSource)-ceq[IO.Path]::GetFullPath($OfflineSource)) 'offline-fixture-target-and-exact-cache-bound'
   [IO.File]::Move($OfflineSource,$OfflineSource+'.offline');[IO.File]::Move($offlineCachePath,$offlineCachePath+'.offline')
   $before=@($paths|ForEach-Object{Get-AiwFileIdentity (Join-Path $project $_)})
   # COMPLETE gets its own correctly bound result evidence, so a mismatch
   # in the rollback SELF cannot be mistaken for unavailable-target proof.
   $completeSelf=Get-Content -LiteralPath $selfPath -Raw|ConvertFrom-Json -Depth 100
   $completeSelf.candidateObjects=@($candidate.objects|Where-Object{$_.path-cin$paths}|ForEach-Object{@{path=$_.path;identity=$_.postimage.identity}})
   $completeSelfPath=Join-Path $caseRoot 'offline-complete-self.json';SaveJson $completeSelfPath $completeSelf
   $completePlan=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
   $completePlan.evidenceRefs=@(@{kind='SELF_CHECK';path=$completeSelfPath;identity=Get-AiwFileIdentity $completeSelfPath})
   $completePlanPath=Join-Path $caseRoot 'offline-complete-recovery.json';SaveJson $completePlanPath $completePlan
   $completeArgs=$args.Clone();$completeArgs.Direction='COMPLETE';$completeArgs.PlanPath=$completePlanPath;$completeArgs.ExpectedPlanIdentity=Get-AiwFileIdentity $completePlanPath
   Reject {& $recover @completeArgs} '^(SOURCE_UNAVAILABLE(?:\||$)|EFFECTIVE_SET_UNPROVEN\|)' 'offline-target-complete-refuses-before-any-write'
   Check ((@($paths|ForEach-Object{Get-AiwFileIdentity (Join-Path $project $_)})-join'!')-ceq($before-join'!')) 'offline-complete-rejection-leaves-whole-group-unchanged'
  }
  if($Interruption-ceq'JOURNAL'){
   $callerCommand=Get-Command Get-AiwFileIdentity
   $interrupted=& $recover @args -InterruptAfterWrite 1
   Check ($interrupted.status-ceq'INTERRUPTED') ('actual-recovery-journal-interruption-'+$Direction)
   $afterCommand=Get-Command Get-AiwFileIdentity -ErrorAction SilentlyContinue
   Check ($null-ne$afterCommand-and$afterCommand.Module.Path-ceq$callerCommand.Module.Path-and$afterCommand.Definition-ceq$callerCommand.Definition) 'in-process-recovery-preserves-caller-composer-command'
  }
  # Exercise the public CLI. Only interruption injection uses the module above.
  $call=Join-Path $caseRoot 'root-call.ps1';SaveText $call @'
param($Tool,$Project,$Plan,$Identity,$Direction)
$ErrorActionPreference='Stop'
try{$r=& $Tool -ProjectId standards-fixture -ToVersion 2.0.0 -RepositoryPath $Project -ProjectRuleRecoveryPlanPath $Plan -ExpectedProjectRuleRecoveryPlanIdentity $Identity -ActorRouteActor fixture-actor -ProjectRuleRecoveryDirection $Direction -Apply;$r|ConvertTo-Json -Depth 100 -Compress}catch{Write-Output ($_.Exception.Message+'|'+$_.ScriptStackTrace);exit 2}
'@
  $process=InvokePresetProcess $call @{Tool=(Join-Path $frameworkRoot 'scripts/upgrade-project.ps1');Project=$project;Plan=$planPath;Identity=(Get-AiwFileIdentity $planPath);Direction=$Direction} 'Recovery'
  $raw=@($process.output);$LASTEXITCODE=$process.code
  if($LASTEXITCODE-ne0){throw ('PUBLIC_SOURCE_RECOVERY|'+($raw-join';'))};$closed=($raw-join"`n")|ConvertFrom-Json -Depth 100
  $actualFinalInput=Get-Content -LiteralPath $closed.finalizeEvidence.inputPath -Raw|ConvertFrom-Json -Depth 100
  $actualFinalResult=Get-Content -LiteralPath $closed.finalizeEvidence.resultPath -Raw|ConvertFrom-Json -Depth 100
  Check ($actualFinalInput.schemaVersion-eq3-and@($actualFinalInput.evidenceRefs).Count-eq1-and$actualFinalInput.evidenceRefs[0].kind-ceq'SELF_CHECK'-and$actualFinalInput.evidenceRefs[0].identity-ceq$self.identity) 'recovery-finalize-retains-actual-boundary3-typed-self'
  Check ($actualFinalResult.status-ceq'PASS'-and$actualFinalResult.projectSourcePreparation.outcome-ceq$(if($Direction-ceq'ROLLBACK'){'ROLLED_BACK'}else{'COMPLETED'})) ('original-finalize-observes-recovery-outcome-'+$Direction)
  if($OfflineSource){[IO.File]::Move($OfflineSource+'.offline',$OfflineSource);[IO.File]::Move($offlineCachePath+'.offline',$offlineCachePath)}
  Check ($closed.originalActionFinalized-and$closed.status-ceq$(if($Direction-ceq'ROLLBACK'){'ROLLED_BACK'}else{'COMPLETED'})) ('original-recovery-finalize-'+$Interruption+'-'+$Direction)
  if($Interruption-ceq'NEW'-and$Direction-ceq'COMPLETE'){Check ($closed.transactionIdentity-ceq'MISSING') 'whole-postimage-does-not-invent-journal'}
 }
 foreach($entry in $candidate.objects){Check ((Get-AiwFileIdentity (Join-Path $project $entry.path))-ceq$entry.$side.identity) ('exact-final-carrier-'+$entry.path)}
 $script:policy=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100
 $script:lastSourceCase=@{root=$caseRoot;receipt=$run.value.compactReceipt;boundary=$final;candidate=$candidate;source=$source;prepareArgs=$prepareArgs}
}
function SealFixture {Set-AiwTestFixtureQualification $copy}
function PublicDiscover([string]$Role){
 # Read-only discovery uses its declared phase while preserving the actual
 # producer/reviewer role. Action-phase composition is checked separately.
 $phase='DISCOVER'
 $intent=[pscustomobject]@{schemaVersion=2;objective='Inspect adopted software design implementation and validation.';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('software');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=[pscustomobject]@{domain=@{state='KNOWN';values=@('aiw:software')};workType=@{state='KNOWN';values=@('aiw:design','aiw:implementation','aiw:verification')};deliverableType=@{state='NOT_APPLICABLE';values=@()};stage=@{state='NOT_APPLICABLE';values=@()}}}
 $inputPath=Join-Path $temp ('discover-'+$Role+'.json');SaveJson $inputPath @{schemaVersion=4;mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=@{sessionId='preset-observer';requestId=$Role;role=$Role;phase=$phase;profile='STANDARD'};projectRoot=$project;frameworkRoot=$frameworkRoot;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=(Get-AiwFileIdentity $configPath);expectedCorrectionsIdentity=(Get-AiwFileIdentity $correctionsPath);expectedTaskIdentity='NOT_APPLICABLE';observedActor='preset-observer';capabilities=@('KNOWLEDGE_REFERENCE');exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
 $entry=if($MaintenanceFixture){Join-Path $frameworkRoot 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $copy 'scripts/resolve-process-requirements.ps1'}
 $process=InvokePresetProcess $entry @{InputPath=$inputPath;AsJson=$true} 'PublicDiscover';$raw=@($process.output);$code=$process.code
 $parsed=$null;try{$parsed=($raw-join"`n")|ConvertFrom-Json -Depth 100}catch{}
 SaveJson (Join-Path $temp ('discover-result-'+[guid]::NewGuid().ToString('N')+'.json')) @{input=$inputPath;role=$Role;exitCode=$code;output=($raw-join"`n");parsed=$parsed}
 if($code-ne0){throw ('PUBLIC_PRESET_DISCOVER_FAILED|'+($raw-join"`n"))};return $parsed
}
$fixtureTimer=[Diagnostics.Stopwatch]::StartNew()
try{
 $project=Join-Path $temp 'project';$frameworkRoot=Join-Path $temp 'bundle';$copy=Join-Path $frameworkRoot 'framework/versions/2.0.0'
 $copy=New-AiwTestMechanismFixture $sourceRoot $frameworkRoot (Join-Path $PSScriptRoot 'test-groups.json') -Maintenance:$MaintenanceFixture
  $script:originalAdmissionNegativesDone=$false
  $composer=@(Import-Module (Join-Path $copy 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru)[0]
 Import-Module (Join-Path $copy 'scripts/ObjectFormats.psm1') -Force
 Import-Module (Join-Path $copy 'scripts/ContentSources.psm1') -Force
 if($MaintenanceFixture){
  [string[]]$packagePaths=@(Get-ChildItem -LiteralPath $frameworkRoot -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($frameworkRoot,$_.FullName).Replace('\','/')});[Array]::Sort($packagePaths,[StringComparer]::Ordinal)
  $entries=@($packagePaths|ForEach-Object{@{path=$_;identity=Get-AiwFileIdentity (Join-Path $frameworkRoot $_)}});$rows=@($entries|ForEach-Object{$_.path+'='+$_.identity})
  $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n")+"`n")))
  SaveJson (Join-Path $frameworkRoot 'PACKAGE_MANIFEST.json') @{schemaVersion=2;frameworkVersion='2.0.0';provisional=$false;canonical=$canonical;files=$entries;distributionId='2.0.0-release'}
  $null=[IO.Directory]::CreateDirectory($project);$target=Join-Path $temp 'target';$null=[IO.Directory]::CreateDirectory($target)
  & git -C $project init -q;& git -C $target init -q
 }
 $null=[IO.Directory]::CreateDirectory($project)
 $registered=RegisterFixture
 $configPath=Join-Path $project '.ai-workspace/project.json';$correctionsPath=Join-Path $project '.ai-workspace/corrections.json';$policyPath=Join-Path $project '.ai-workspace/process-policy.json';$taskPath=Join-Path $project '.ai-workspace/tasks/active/STANDARDS-001.md'
 $config=Get-Content $configPath -Raw|ConvertFrom-Json
 Check ($config.schemaVersion-eq7-and$config.processPolicy.schemaVersion-eq3-and$config.sourceBindings.Count-eq0) 'actual-public-registration-produces-current-empty-adoption'
 # Existing source-update regressions keep their enabled fixture. Maintenance
 # exercises first enable directly from its real empty registration instead.
 if(-not$MaintenanceFixture-or$Group-cne'KnowledgeEnable'){$config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@()}};SaveJson $configPath $config}
 SaveText $taskPath "# STANDARDS-001`n- Owner: fixture-actor`n- Work route: actor=fixture-actor; role=TASK_OWNER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]"
 $registeredPolicy=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100
 $policy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='standards-fixture';rules=@($(if($MaintenanceFixture){$registeredPolicy.rules|Where-Object ruleId -CEQ 'FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY'}))};SaveJson $policyPath $policy
 $fixtureTimer.Stop();PresetTiming 'preparation' 'Fixture' $fixtureTimer.Elapsed.TotalMilliseconds
 $bodyTimer=[Diagnostics.Stopwatch]::StartNew()
 $policyBefore=Get-AiwFileIdentity $policyPath
 $rules=@(Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:adopt-fixed-software')
 $applicability=@{SOFTWARE_DESIGN=@{domain=@('aiw:software');workType=@('aiw:design','aiw:review','aiw:acceptance')};SOFTWARE_IMPLEMENTATION=@{domain=@('aiw:software');workType=@('aiw:implementation','aiw:review','aiw:acceptance')};SOFTWARE_VALIDATION=@{domain=@('aiw:software');workType=@('aiw:verification','aiw:review','aiw:acceptance')}}
 $configBefore=Get-AiwFileIdentity $configPath
 $partial=New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator fixture -RuleIds SOFTWARE_DESIGN -Applicability $applicability -ForbiddenPaths @((Join-Path $copy 'standards/software/IMPLEMENTATION.md'))
 $prepared=New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:adopt-fixed-software' -RuleIds SOFTWARE_DESIGN,SOFTWARE_IMPLEMENTATION,SOFTWARE_VALIDATION -Applicability $applicability

 $emptyConfig=[IO.File]::ReadAllBytes($configPath);$emptyPolicy=[IO.File]::ReadAllBytes($policyPath)
 $baselineProject=[IO.Path]::GetFullPath($project)
 $emptyProjectSnapshot=Get-AiwTestFixtureSnapshot $project
 function RestoreEmptyFixture {
  $timer=[Diagnostics.Stopwatch]::StartNew()
  if([IO.Path]::GetFullPath($project)-cne$baselineProject-or-not$baselineProject.StartsWith([IO.Path]::GetFullPath($temp)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PRESET_RESET_ABSOLUTE_SCOPE'}
  $active=@(Get-ChildItem -LiteralPath $project -Recurse -File -Force|Where-Object{$_.Name-clike'*.transaction.json'}|ForEach-Object{[IO.Path]::GetRelativePath($project,$_.FullName).Replace('\','/')})
  $null=Reset-AiwTestFixture $emptyProjectSnapshot $project -ActiveMarkerPaths $active
  $script:policy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
  if((Get-AiwFileIdentity $configPath)-cne(FixtureBytesIdentity $emptyConfig)-or(Get-AiwFileIdentity $policyPath)-cne(FixtureBytesIdentity $emptyPolicy)){throw 'PRESET_RESET_IDENTITY'}
  $timer.Stop();PresetTiming 'preparation' 'EmptyBaselineReset' $timer.Elapsed.TotalMilliseconds
 }
 function FixtureBytesIdentity([byte[]]$Bytes){$Bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
 $gate=[pscustomobject]@{ruleId='F01_GATES';requirementReason='Preserve old and new action obligations';effectiveRule='Both the admitted preparation and its result remain required until the original action closes.';selectors=@{profiles=@();roles=@();phases=@();actionKinds=@('CONTROL_WRITE');resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@('F01_PREPARED');resultRequirements=@('F01_RESULT');decisionLocator='fixture:obligation-union'}
 if($Group-ceq'RuleSelection'){
 Check ($rules.Count-eq3-and(Get-AiwFileIdentity $policyPath)-ceq$policyBefore) 'expansion-does-not-adopt-or-write-policy'
 Check (@(ProjectRules (Compose EXECUTOR SOURCE_WRITE 'API implementation software test')).Count-eq0) 'unadopted-standards-not-selected'
 Check (@($rules|Where-Object{$_.decisionLocator-cne'fixture:adopt-fixed-software'}).Count-eq0) 'original-project-decision-bound'
 foreach($rule in $rules){$doc=$rule.source.documents[0];Check ($doc.locatorKind-ceq'ABSOLUTE_FILE'-and$doc.identity-ceq(Get-AiwFileIdentity $doc.locator)-and$doc.locator.StartsWith($copy)) ('exact-source-'+$rule.ruleId)}
 Reject {New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator fixture -RuleIds SOFTWARE_DESIGN -Applicability @{}} 'PRESET_APPLICABILITY_REQUIRED' 'public-preparation-requires-project-applicability'
 Check ($partial.rules.Count-eq1-and$partial.rules[0].source.kind-ceq'BOUND_SOURCE_ITEM'-and$partial.sourceBindings.Count-eq1-and$partial.sourceBindings[0].allowedPaths.Count-eq1) 'partial-public-preparation-does-not-read-or-permit-unselected-protected-standard'
 Reject {New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator fixture -RuleIds SOFTWARE_DESIGN -Applicability $applicability -ForbiddenPaths @((Join-Path $copy 'standards/software/DESIGN.md'))} 'FORBIDDEN' 'public-preparation-enforces-selected-source-protection'
 Check (-not$prepared.authority-and-not$prepared.projectWritePerformed-and$prepared.permissionChanges.Count-gt0-and(Get-AiwFileIdentity $configPath)-ceq$configBefore-and(Get-AiwFileIdentity $policyPath)-ceq$policyBefore) 'public-preparation-proposes-complete-current-adoption-with-zero-project-write'
 if(-not$MaintenanceFixture){
 $conflictingConfig=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100;$conflictingConfig.sourceBindings=@($partial.sourceBindings|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100);$conflictingConfig.sourceBindings[0].locator.root=Join-Path $temp 'different-source';SaveJson $configPath $conflictingConfig
 Reject {New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator fixture -RuleIds SOFTWARE_DESIGN -Applicability $applicability} 'PRESET_BINDING_CONFLICT' 'public-preparation-rejects-same-binding-repointed-to-another-source'
 $conflictingConfig.sourceBindings=@();SaveJson $configPath $conflictingConfig
 AdoptFixturePreset $partial
 Check (@((PublicDiscover EXECUTOR).selectedRuleBlocks|Where-Object{$_.requirementId.StartsWith('project:')}).Count-eq1) 'public-discover-loads-only-explicit-partial-adoption'
 AdoptFixturePreset $prepared
 $publicAuthor=PublicDiscover EXECUTOR;$publicReview=PublicDiscover REVIEWER
 $publicAuthorRules=@($publicAuthor.selectedRuleBlocks|Where-Object{$_.requirementId.StartsWith('project:')});$publicReviewRules=@($publicReview.selectedRuleBlocks|Where-Object{$_.requirementId.StartsWith('project:')})
 Check ($publicAuthorRules.Count-eq3-and$publicReviewRules.Count-eq3-and($publicAuthorRules.fullText-join'|')-ceq($publicReviewRules.fullText-join'|')) 'actual-public-discover-author-and-reviewer-consume-same-adopted-fulltext'
 $author=Compose EXECUTOR SOURCE_WRITE 'API implementation software test'
 $review=Compose REVIEWER REVIEW_EXECUTE 'review API implementation software test'
 $authorRules=@(ProjectRules $author);$reviewRules=@(ProjectRules $review)
 $accept=Compose TASK_OWNER RESULT_ACCEPT 'Accept the frozen software result and its validation evidence'
 $acceptRules=@(ProjectRules $accept)
 Check ($acceptRules.Count-eq3-and($acceptRules.fullText-join'|')-ceq($reviewRules.fullText-join'|')) 'true-acceptance-and-review-classifications-consume-same-complete-professional-requirements'
 Check ($authorRules.Count-eq3-and$reviewRules.Count-eq3-and($authorRules.requirementId-join'|')-ceq($reviewRules.requirementId-join'|')) 'true-review-worktype-selects-adopted-quality-without-implementation-facet'
 foreach($rule in $rules){$body=[IO.File]::ReadAllText($rule.source.documents[0].locator).TrimEnd("`n");$selected=@($reviewRules|Where-Object{$_.requirementId.EndsWith(':'+$rule.ruleId)})[0];Check ($selected.fullText.Contains($body)) ('review-loads-complete-body-'+$rule.ruleId)}
  # Pure selector distinctions use the real module kernel. Full composition,
  # source validation and author/reviewer/acceptance parity remain above/below.
  foreach($selectorCase in @(@{domain='aiw:visual-art';work=@('aiw:review');count=0;name='unrelated-profession-does-not-load-software'},@{domain='aiw:software';work=@('aiw:review','aiw:design');count=3;name='no-path-design-review-retains-real-review-classification-and-project-selected-standards'})){
   $facets=[pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=@($selectorCase.domain)};workType=[pscustomobject]@{state='KNOWN';values=$selectorCase.work};deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:code')};stage=[pscustomobject]@{state='KNOWN';values=@('aiw:closure')}}
   $matches=@($policy.rules|Where-Object{& $composer {param($selectors,$f)(Test-AiwRuleMatch $selectors STANDARD REVIEWER REVIEW REVIEW_EXECUTE REVIEW_VERDICT @() @('KNOWLEDGE_REFERENCE') '' $false $f).Match} $_.selectors $facets})
   Check ($matches.Count-eq$selectorCase.count) $selectorCase.name
  }
 $beforeChange=$review.sourceCompositionIdentity
 $source=$rules[0].source.documents[0].locator;$oldBody=[IO.File]::ReadAllText($source)
 SaveText $source ($oldBody+"`nExplicit changed source for drift evidence.")
 SealFixture
 $unrelated=Compose REVIEWER REVIEW_EXECUTE 'review illustration layout' -Domains @('aiw:visual-art')
 Check (@(ProjectRules $unrelated).Count-eq0-and@($unrelated.readTrace|Where-Object event -CEQ SOURCE_BODY_READ).Count-eq0) 'unrelated-profession-does-not-read-or-certify-damaged-software-body'
 Reject {Compose REVIEWER REVIEW_EXECUTE 'review changed design source' -WorkTypes @('aiw:design')} 'CONTENT_IDENTITY_DRIFT|EFFECTIVE_SET_UNPROVEN' 'selected-adopted-source-drift-still-rejected'
 Reject {Compose REVIEWER REVIEW_EXECUTE 'validate complete target adoption' -Domains @('aiw:visual-art') -ValidateCompleteAdoptedSet} 'CONTENT_IDENTITY_DRIFT|EFFECTIVE_SET_UNPROVEN' 'complete-adoption-rejects-damaged-unselected-body' 
 $prepared=New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:authorized-follow-update' -RuleIds SOFTWARE_DESIGN,SOFTWARE_IMPLEMENTATION,SOFTWARE_VALIDATION -Applicability $applicability
 # Restore the still-adopted fixed source for the original admission, and bind
 # the new revision from a separate explicit directory. Never fresh-discover a
 # broken old source and claim that it authorized the preceding update.
 $updatedBody=[IO.File]::ReadAllText($source);SaveText $source $oldBody;SealFixture
 $updatedDirectory=Join-Path $temp 'updated-standards';$null=[IO.Directory]::CreateDirectory($updatedDirectory)
 foreach($entry in $prepared.sourceBindings){$file=$entry.allowedPaths[0].locator;Copy-Item -LiteralPath (Join-Path $entry.locator.root $file) -Destination (Join-Path $updatedDirectory $file);$entry.locator.root=$updatedDirectory}
 SaveText (Join-Path $updatedDirectory 'DESIGN.md') $updatedBody
 Import-Module (Join-Path $copy 'scripts/ContentSources.psm1') -Force
 foreach($rule in $prepared.rules){foreach($doc in $rule.source.documents){$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $prepared.sourceBindings};$rule.source.revision=Get-AiwContentRevision $rule.source $prepared.sourceBindings;$rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source}
 AdoptFixturePreset $prepared
 Check (@(ProjectRules (Compose REVIEWER REVIEW_EXECUTE 'review illustration layout' -Domains @('aiw:visual-art'))).Count-eq0) 'explicit-rebind-restores-normal-selection'
 $replacementRules=@([ordered]@{ruleId='PROJECT_DESIGN';requirementReason='Project replaces the adopted design standard';effectiveRule='Replacement-only design requirement.';selectors=$policy.rules[0].selectors;preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:replace-standard'})+@($policy.rules|Where-Object ruleId -cne SOFTWARE_DESIGN)
  # Replacement-only risk is effective-set uniqueness and composition. The
  # unchanged source permissions already passed the real rebind immediately above.
  $custom=Get-AiwProjectCustomRegion (Join-Path $project '.ai-workspace/BOOTSTRAP.md')
  # The real owned reader validates the current adopted file. Install this
  # fixture replacement before checking it; a not-yet-current request must fail.
  $policy.rules=$replacementRules;SaveJson $policyPath $policy
  $effective=Test-AiwEffectiveRuleSet -ProjectRoot $project -Corrections @() -PolicyRules $replacementRules -Custom $custom
  Check ($effective.status-ceq'PASS'-and@($effective.members|Where-Object id -CEQ SOFTWARE_DESIGN).Count-eq0-and@($effective.members|Where-Object id -CEQ PROJECT_DESIGN).Count-eq1) 'replacement-real-effective-set-has-one-design-owner'
  $replacementComposition=Compose REVIEWER REVIEW_EXECUTE 'review API design' -WorkTypes @('aiw:review','aiw:design')
  $replacement=@(ProjectRules $replacementComposition)
 Check ($replacement.Count-eq3-and@($replacement|Where-Object {$_.requirementId-ceq('project:'+$policy.projectId+':PROJECT_DESIGN')-and$_.fullText-ceq'Replacement-only design requirement.'}).Count-eq1-and@($replacement|Where-Object {$_.requirementId-match':SOFTWARE_DESIGN$'}).Count-eq0-and@($replacement|Where-Object {$_.requirementId-match':SOFTWARE_(IMPLEMENTATION|VALIDATION)$'}).Count-eq2) 'one-policy-change-replaces-without-duplicate-must'
  Check (@($replacementComposition.selectedRequirements|Where-Object requirementId -ceq 'framework:PR_ACTION_AUTHORIZATION_INDEPENDENT').Count-eq1) 'optional-replacement-does-not-suppress-core'
 Reject {Expand-AiwProcessPreset -PresetId '../software' -ProjectRoot $project -DecisionLocator fixture} 'ValidatePattern|pattern|模式|匹配' 'preset-id-cannot-traverse'
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator ' '} 'PRESET_DECISION_REQUIRED' 'missing-project-decision-rejected'
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $temp -DecisionLocator fixture -ForbiddenPaths @('bundle/framework/versions/2.0.0/standards/software')} 'FORBIDDEN' 'source-protection-before-hash'
 $presetPath=Join-Path $copy 'standards/presets/software.json';$originalPreset=[IO.File]::ReadAllText($presetPath)
 function FaultPreset([scriptblock]$Change){$p=$originalPreset|ConvertFrom-Json;& $Change $p;SaveJson $presetPath $p}
 FaultPreset {param($p)$p.rules[0].source.documents[0].locator='standards/software/../../../outside.md'}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'COMPONENT' 'document-cannot-escape-version'
 FaultPreset {param($p)$p.rules[0].source.documents[0].dependencies=@('MISSING_SOURCE')}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'DEPENDENCY_UNKNOWN' 'incomplete-source-closure-rejected'
 FaultPreset {param($p)$p.rules[1].ruleId=$p.rules[0].ruleId}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'PRESET_RULE_VALUES' 'duplicate-rule-id-rejected'
 FaultPreset {param($p)$p.rules[0]|Add-Member -NotePropertyName effectiveRule -NotePropertyValue 'second authority'}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'PRESET_RULE_FIELDS' 'preset-cannot-add-second-rule-body'
 SaveText $presetPath $originalPreset
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.git'))-and-not(Test-Path -LiteralPath (Join-Path $project '.gitignore'))) 'standards-expansion-and-composition-require-no-git'
 }
 }
 if($Group-ceq'SourceChangeRecovery'){
 if($MaintenanceFixture){
 AdoptFixturePreset $prepared
 AdoptFixturePreset ([pscustomobject]@{sourceBindings=@();rules=@()}) POLICY COMPLETE
 AdoptFixturePreset $partial POLICY ROLLBACK
 }else{
 # Complete and rollback each reachable direct-write interruption. Each case
 # obtains its own actual admission, and retains the actual boundary3 inputs.
 $empty=[pscustomobject]@{sourceBindings=@();rules=@()}
 foreach($state in @('OLD','POLICY','NEW','JOURNAL')){
  RestoreEmptyFixture
  AdoptFixturePreset $partial $state COMPLETE
 }
 foreach($state in @('OLD','POLICY','NEW','JOURNAL')){
  RestoreEmptyFixture
  AdoptFixturePreset $partial $state ROLLBACK
 }
 RestoreEmptyFixture
 AdoptFixturePreset ([pscustomobject]@{sourceBindings=@();rules=@($gate)})
 AdoptFixturePreset $empty
 $source=$rules[0].source.documents[0].locator;$oldBody=[IO.File]::ReadAllText($source)
 $updatedBody=$oldBody+"`nExplicit changed source for drift evidence.`n"
 # Freeze the new preparation against the actual changed bytes, then restore
 # the original fixed source before the independently authorized adoption.
 SaveText $source $updatedBody;SealFixture
 $prepared=New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:authorized-follow-update' -RuleIds SOFTWARE_DESIGN,SOFTWARE_IMPLEMENTATION,SOFTWARE_VALIDATION -Applicability $applicability
 SaveText $source $oldBody;SealFixture
 $updatedDirectory=Join-Path $temp 'updated-standards';$null=[IO.Directory]::CreateDirectory($updatedDirectory)
 foreach($entry in $prepared.sourceBindings){$file=$entry.allowedPaths[0].locator;Copy-Item -LiteralPath (Join-Path $entry.locator.root $file) -Destination (Join-Path $updatedDirectory $file);$entry.locator.root=$updatedDirectory}
 SaveText (Join-Path $updatedDirectory 'DESIGN.md') $updatedBody
 Import-Module (Join-Path $copy 'scripts/ContentSources.psm1') -Force
 foreach($rule in $prepared.rules){foreach($doc in $rule.source.documents){$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $prepared.sourceBindings};$rule.source.revision=Get-AiwContentRevision $rule.source $prepared.sourceBindings;$rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source}
 AdoptFixturePreset $prepared NEW ROLLBACK (Join-Path $updatedDirectory 'DESIGN.md')
 $three=New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:three-from-empty' -RuleIds SOFTWARE_DESIGN,SOFTWARE_IMPLEMENTATION,SOFTWARE_VALIDATION -Applicability $applicability
 AdoptFixturePreset $three
 Check (@((PublicDiscover EXECUTOR).selectedRuleBlocks|Where-Object{$_.requirementId.StartsWith('project:')}).Count-eq3) 'empty-permissions-to-three-standards-through-real-original-boundaries'
 }
 }
 if($Group-ceq'KnowledgeEnable'){
 if($MaintenanceFixture){
 $first=$prepared|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $first|Add-Member knowledgeCapability ([pscustomobject]@{enabled=$true;sources=@()})
 AdoptFixturePreset $first
 Check ((Get-Content $configPath -Raw|ConvertFrom-Json).frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled) 'maintenance-first-enable-through-original-public-boundary'
 }else{
 $three=New-AiwProcessPresetPreparation -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:three-from-empty' -RuleIds SOFTWARE_DESIGN,SOFTWARE_IMPLEMENTATION,SOFTWARE_VALIDATION -Applicability $applicability
 AdoptFixturePreset $three
 $referenceRoot=Join-Path $temp 'offline-reference-library'
 $knowledgeBinding=[pscustomobject]@{id='reference-methods';provider='LOCAL_DIRECTORY';locator=@{root=$referenceRoot};allowedPaths=@(@{kind='FILE';locator='index.json'},@{kind='FILE';locator='one.md'},@{kind='FILE';locator='two.md'},@{kind='FILE';locator='three.md'},@{kind='FILE';locator='four.md'});decisionLocator='fixture:reference-only-methods'}
 $knowledgeSource=[pscustomobject]@{id='methods';bindingId='reference-methods';indexLocator='index.json';selectionHints=@('methods');updatePolicy='FOLLOW';revisionSelector='index.json'}
 $knowledgePreparation=[pscustomobject]@{sourceBindings=@($three.sourceBindings)+@($knowledgeBinding);rules=@($three.rules);knowledgeSources=@($knowledgeSource)}
 $policyIdentity=Get-AiwFileIdentity $policyPath;AdoptFixturePreset $knowledgePreparation
 Check ((Get-AiwFileIdentity $policyPath)-ceq$policyIdentity-and-not(Test-Path $referenceRoot)) 'knowledge-only-source-change-preserves-policy-without-reading-offline-methods'
 # R2 adds only capability selection and its reachable recovery differences.
 # The earlier F01 matrix retains the unchanged transaction coverage.
 $enabledConfig=[IO.File]::ReadAllBytes($configPath);$enabledPolicy=[IO.File]::ReadAllBytes($policyPath)
 $oldGate=$gate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $capGate=[pscustomobject]@{ruleId='R2_KNOWLEDGE_GATE';requirementReason='First enable selects a previously inactive obligation';effectiveRule='The selected reference capability requires its own preparation and result.';selectors=@{profiles=@();roles=@();phases=@();actionKinds=@('CONTROL_WRITE');resultKinds=@();pathPrefixes=@();capabilities=@('KNOWLEDGE_REFERENCE');semanticTerms=@()};preparationRequirements=@('R2_KNOWLEDGE_PREPARED');resultRequirements=@('R2_KNOWLEDGE_RESULT');decisionLocator='fixture:first-enable'}
 $first=$knowledgePreparation|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $first.rules=@($three.rules)+@($oldGate,$capGate)
 $first|Add-Member knowledgeCapability ([pscustomobject]@{enabled=$true;sources=@($knowledgeSource)})
 $before=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100;$before.frameworkCapabilities=[pscustomobject]@{};SaveJson $configPath $before
 $policy.rules=@($first.rules);SaveJson $policyPath $policy
 $missingConfig=Get-AiwFileIdentity $configPath
 Reject {AdoptFixturePreset $first -CapabilityIssuer TASK_OWNER} '^SOURCE_CHANGE_CAPABILITY_CONTROLLER_REQUIRED$' 'first-enable-needs-controller-package'
 $denied=$first|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$denied.PSObject.Properties.Remove('knowledgeSources')
 @($denied.sourceBindings|Where-Object{$_.id-ceq'reference-methods'})[0].locator.root=Join-Path $project 'private'
 Reject {AdoptFixturePreset $denied} 'FORBIDDEN' 'first-enable-denied-index-rejected-before-read'
 Check ((Get-AiwFileIdentity $configPath)-ceq$missingConfig) 'first-enable-negative-candidates-leave-live-config-unchanged'
 AdoptFixturePreset $first
 Check ((Get-Content $configPath -Raw|ConvertFrom-Json).frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled-and-not(Test-Path $referenceRoot)) 'first-enable-from-missing-closes-without-reading-unselected-index'
 # Disabled is an independently valid original state. Policy is unchanged;
 # NEW represents only the real config change, then exact rollback.
 $before.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false;sources=@()}};SaveJson $configPath $before
 $disabledIdentity=Get-AiwFileIdentity $configPath
 AdoptFixturePreset $first NEW ROLLBACK
 Check ((Get-AiwFileIdentity $configPath)-ceq$disabledIdentity) 'first-enable-disabled-origin-restored-by-original-rollback'
 # Here policy really changes before config, so POLICY is a reachable gap.
 $policy.rules=@($three.rules)+@($oldGate);SaveJson $policyPath $policy
 AdoptFixturePreset $first POLICY COMPLETE
 Check ((Get-Content $configPath -Raw|ConvertFrom-Json).frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled) 'first-enable-policy-first-interruption-completes-new-capabilities'
 [IO.File]::WriteAllBytes($configPath,$enabledConfig);[IO.File]::WriteAllBytes($policyPath,$enabledPolicy)
 $policy=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100
 }
 }
 Write-Output ('STANDARD_PRESETS_TESTS_PASS|checks='+$passed+'|group='+$Group+'|evidence=PROJECT_POLICY_AND_SOURCE_BINDINGS')
}finally{
 if($null-ne$bodyTimer){$bodyTimer.Stop();PresetTiming 'target-group-wall-nested' 'Cases' $bodyTimer.Elapsed.TotalMilliseconds}
 $cleanupTimer=[Diagnostics.Stopwatch]::StartNew()
 $resolved=[IO.Path]::GetFullPath($temp);$systemTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($resolved)-cne$systemTemp-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-standard-presets-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if($KeepFixture){Write-Output ('FIXTURE_RETAINED|'+$resolved)}
 elseif(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
 $cleanupTimer.Stop();PresetTiming 'cleanup' 'Fixture' $cleanupTimer.Elapsed.TotalMilliseconds
}
