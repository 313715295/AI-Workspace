# @design-contract ../../../FRAMEWORK_RELEASE.md
# Private, read-only evidence contract. Adapters supply already-bound original bytes.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
$script:EvidenceUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:EvidenceLoadedInputs=@(foreach($path in @($PSCommandPath,(Join-Path $PSScriptRoot 'StrictJsonInput.psm1'))){$bytes=[IO.File]::ReadAllBytes($path);@{path=$path;identity=($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))}})
function Get-AiwEvidenceLoadedIdentity {
 foreach($input in $script:EvidenceLoadedInputs){$bytes=[IO.File]::ReadAllBytes($input.path);if(($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))-cne$input.identity){throw 'TEST_VERIFIER_MODULE_DRIFT'}}
 return $script:EvidenceLoadedInputs[0].identity
}
function Restore-AiwEvidenceContextStrings([string]$Text,$Value){
 if($Value-isnot[pscustomobject]-or$null-eq$Value.PSObject.Properties['executionKind']-or$Value.executionKind-cnotin@('EXECUTED','REVALIDATED')-or$Value.schemaVersion-ne2){return $Value}
 $doc=[Text.Json.JsonDocument]::Parse($Text)
 try{
  foreach($path in @('executionContext.targetObservation','before.facts.executionContext.targetObservation','after.facts.executionContext.targetObservation','currentSnapshot.facts.executionContext.targetObservation')){
   $element=$doc.RootElement;$target=$Value;$found=$true
   foreach($name in $path.Split('.')){
    $next=[Text.Json.JsonElement]::new()
    if($element.ValueKind-ne[Text.Json.JsonValueKind]::Object-or-not$element.TryGetProperty($name,[ref]$next)){$found=$false;break}
    $element=$next;$target=$target.$name
   }
   if(-not$found-or$element.ValueKind-eq[Text.Json.JsonValueKind]::Null){continue}
   $utc=[Text.Json.JsonElement]::new()
   if($element.ValueKind-ne[Text.Json.JsonValueKind]::Object-or-not$element.TryGetProperty('observedUtc',[ref]$utc)-or$utc.ValueKind-ne[Text.Json.JsonValueKind]::String){throw 'TEST_EXECUTION_TARGET_OBSERVATION_TIME_TOKEN'}
   $target.observedUtc=$utc.GetString()
  }
 }finally{$doc.Dispose()}
 return $Value
}
function Assert-AiwEvidenceFields($Value,[string[]]$Fields,[string]$Label){
 if($Value-isnot[pscustomobject]-or@($Value.PSObject.Properties).Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$Value.PSObject.Properties.Name}).Count){throw ('RELEASE_FIELDS|'+$Label)}
}
function Get-AiwEvidenceCanonical($Value){
 if($null-eq$Value){return 'null'}
 if($Value-is[string]-or$Value-is[bool]-or$Value-is[ValueType]){return ConvertTo-Json -InputObject $Value -Compress -Depth 100}
 if($Value-is[Collections.IDictionary]){[string[]]$keys=@($Value.Keys|ForEach-Object{[string]$_});[Array]::Sort($keys,[StringComparer]::Ordinal);return '{'+(@($keys|ForEach-Object{(Get-AiwEvidenceCanonical $_)+':'+(Get-AiwEvidenceCanonical $Value[$_])})-join',')+'}'}
 if($Value-is[Collections.IEnumerable]){return '['+(@($Value|ForEach-Object{Get-AiwEvidenceCanonical $_})-join',')+']'}
 [string[]]$keys=@(foreach($p in $Value.PSObject.Properties){[string]$p.Name});[Array]::Sort($keys,[StringComparer]::Ordinal)
 return '{'+(@($keys|ForEach-Object{(Get-AiwEvidenceCanonical $_)+':'+(Get-AiwEvidenceCanonical $Value.PSObject.Properties[$_].Value)})-join',')+'}'
}
function Get-AiwEvidenceValueIdentity($Value){return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:EvidenceUtf8.GetBytes((Get-AiwEvidenceCanonical $Value))))}
function Get-AiwEvidenceByteIdentity([byte[]]$Bytes){return $Bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Get-AiwEvidenceTime($Value,[string]$Label){
 if($Value-isnot[string]-or$Value-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$'){throw ('RELEASE_EVIDENCE_TIME|'+$Label)}
 $parsed=[DateTimeOffset]::MinValue
 if(-not[DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)){throw ('RELEASE_EVIDENCE_TIME|'+$Label)}
 return $parsed.ToUniversalTime()
}
function Assert-AiwEvidenceReference($Reference,[string]$Label){
 Assert-AiwEvidenceFields $Reference @('path','identity') $Label
 if($Reference.path-isnot[string]-or[string]::IsNullOrWhiteSpace($Reference.path)-or$Reference.identity-isnot[string]-or$Reference.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('TEST_REFERENCE|'+$Label)}
}
function Assert-AiwEvidenceExecutionContext($Context,[byte[]]$DescriptorBytes=$null){
 Assert-AiwEvidenceFields $Context @('schemaVersion','targetKind','controlRoot','executionRoot','executionTargetRef','targetObservation') 'execution-context'
 if($Context.schemaVersion-isnot[int]-and$Context.schemaVersion-isnot[long]-or$Context.schemaVersion-ne1-or$Context.targetKind-cnotin@('SAME_ROOT','GIT_WORKTREE')){throw 'TEST_EXECUTION_CONTEXT_SCHEMA'}
 foreach($name in @('controlRoot','executionRoot')){if($Context.$name-isnot[string]-or-not[IO.Path]::IsPathFullyQualified($Context.$name)-or[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Context.$name))-cne$Context.$name){throw 'TEST_EXECUTION_CONTEXT_ROOT'}}
 if($Context.targetKind-ceq'SAME_ROOT'){
  if($Context.controlRoot-cne$Context.executionRoot-or$null-ne$Context.executionTargetRef-or$null-ne$Context.targetObservation-or$null-ne$DescriptorBytes){throw 'TEST_EXECUTION_CONTEXT_SAME_ROOT'}
  return
 }
 Assert-AiwEvidenceReference $Context.executionTargetRef 'execution-target-ref'
 $o=$Context.targetObservation;Assert-AiwEvidenceFields $o @('schemaVersion','descriptorIdentity','commonGitDir','worktreeGitDir','gitTop','branch','head','observedUtc','overridesAbsent') 'target-observation'
 if($o.schemaVersion-isnot[int]-and$o.schemaVersion-isnot[long]-or$o.schemaVersion-ne1-or$o.descriptorIdentity-cne$Context.executionTargetRef.identity-or$o.gitTop-cne$Context.executionRoot-or$o.overridesAbsent-isnot[bool]-or-not$o.overridesAbsent-or$o.branch-isnot[string]-or[string]::IsNullOrWhiteSpace($o.branch)-or$o.head-isnot[string]-or$o.head-cnotmatch'^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$'){throw 'TEST_EXECUTION_TARGET_OBSERVATION'}
 foreach($name in @('commonGitDir','worktreeGitDir')){if($o.$name-isnot[string]-or-not[IO.Path]::IsPathFullyQualified($o.$name)){throw 'TEST_EXECUTION_TARGET_OBSERVATION'}}
 $null=Get-AiwEvidenceTime $o.observedUtc 'target-observed'
 if($null-eq$DescriptorBytes-or(Get-AiwEvidenceByteIdentity $DescriptorBytes)-cne$Context.executionTargetRef.identity){throw 'TEST_EXECUTION_TARGET_ORIGINAL_REQUIRED'}
 $descriptor=(ConvertFrom-AiwStrictInputJson ($script:EvidenceUtf8.GetString($DescriptorBytes))).Value
 Assert-AiwEvidenceFields $descriptor @('schemaVersion','kind','projectId','taskId','controlRoot','targetKind','targetRoot','gitBinding','selectionDecisionRef','hostWorktreeRef') 'execution-target'
 if($descriptor.schemaVersion-isnot[int]-and$descriptor.schemaVersion-isnot[long]-or$descriptor.schemaVersion-ne1-or$descriptor.kind-cne'EXECUTION_TARGET'-or$descriptor.targetKind-cne'GIT_WORKTREE'-or$descriptor.controlRoot-cne$Context.controlRoot-or$descriptor.targetRoot-cne$Context.executionRoot){throw 'TEST_EXECUTION_TARGET_BINDING'}
 foreach($name in @('kind','projectId','taskId','controlRoot','targetKind','targetRoot')){if($descriptor.$name-isnot[string]-or[string]::IsNullOrWhiteSpace($descriptor.$name)){throw 'TEST_EXECUTION_TARGET_BINDING'}}
 $g=$descriptor.gitBinding;Assert-AiwEvidenceFields $g @('commonGitDir','worktreeGitDir','gitTop','branch','baselineCommit') 'execution-target-git'
 foreach($name in @('commonGitDir','worktreeGitDir','gitTop','branch','baselineCommit')){if($g.$name-isnot[string]-or[string]::IsNullOrWhiteSpace($g.$name)){throw 'TEST_EXECUTION_TARGET_BINDING'}}
 if($g.commonGitDir-cne$o.commonGitDir-or$g.worktreeGitDir-cne$o.worktreeGitDir-or$g.gitTop-cne$o.gitTop-or$g.baselineCommit-cnotmatch'^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$'){throw 'TEST_EXECUTION_TARGET_BINDING'}
 Assert-AiwEvidenceReference $descriptor.selectionDecisionRef 'target-selectionDecisionRef'
 if($null-ne$descriptor.hostWorktreeRef){Assert-AiwEvidenceReference $descriptor.hostWorktreeRef 'target-hostWorktreeRef'}
 # This is historical relation evidence only. No Git or original absolute-root IO.
}
function Get-AiwEvidenceDependencyPaths($Definition,$Group,[string[]]$VersionPaths=@()){
 $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($path in @($Group.dependencies)+@($Group.behaviorInputs.files)+@($Group.entry)+@($Group.fixtureRecipe.constructorPaths)){$null=$paths.Add($path)}
 if($Group.behaviorInputs.includeCommonSets){foreach($path in @($Definition.mechanismVersionPaths|ForEach-Object{'framework/versions/2.0.0/'+$_})+@($Definition.rootAdoptionPaths)+@($Definition.maintenancePaths)+@('framework/versions/2.0.0/tests/TestHarness.psm1','framework/versions/2.0.0/tests/TestExecutionRuntime.psm1','framework/versions/2.0.0/tests/TestGroupEvidence.psm1')){$null=$paths.Add($path)}}
 if($Group.fixturePolicy-ceq'WHOLE_VERSION'){foreach($path in $VersionPaths){$null=$paths.Add($path)}}
 if($Group.behaviorInputs.wholeDefinition){$null=$paths.Add('framework/versions/2.0.0/tests/test-groups.json')}
 [string[]]$sorted=@($paths);[Array]::Sort($sorted,[StringComparer]::Ordinal);return $sorted
}
function Assert-AiwEvidenceDeclaredInputs($Facts,$Group){
 $mandatory=@($Group.dependencies)+@($Group.behaviorInputs.files)+@($Group.entry)+@($Group.fixtureRecipe.constructorPaths)
 if($Group.behaviorInputs.wholeDefinition){$mandatory+=@('framework/versions/2.0.0/tests/test-groups.json')}
 if($Group.behaviorInputs.includeCommonSets){$mandatory+=@('framework/versions/2.0.0/tests/TestHarness.psm1','framework/versions/2.0.0/tests/TestExecutionRuntime.psm1','framework/versions/2.0.0/tests/TestGroupEvidence.psm1')}
 foreach($path in $mandatory){if(@($Facts.inputs|Where-Object path -CEQ $path).Count-ne1){throw 'TEST_BEHAVIOR_INPUT_CLOSURE'}}
}
function Assert-AiwEvidenceSnapshotInputs($Facts,$Definition,$Group,$AvailableRows){
 Assert-AiwEvidenceDeclaredInputs $Facts $Group
 $byPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($row in $AvailableRows){if(-not$byPath.TryAdd([string]$row.path,$row)){throw 'TEST_BEHAVIOR_AVAILABLE_INPUT_DUPLICATE'}}
 $versionPaths=@($AvailableRows|Where-Object{$_.path.StartsWith('framework/versions/2.0.0/',[StringComparison]::Ordinal)}|ForEach-Object{$_.path})
 $expected=@(foreach($path in @(Get-AiwEvidenceDependencyPaths $Definition $Group $versionPaths)){if(-not$byPath.ContainsKey($path)){throw 'TEST_BEHAVIOR_INPUT_UNBOUND'};[pscustomobject]@{path=$path;identity=$byPath[$path].identity}})
 if((Get-AiwEvidenceValueIdentity $expected)-cne(Get-AiwEvidenceValueIdentity @($Facts.inputs))){throw 'TEST_BEHAVIOR_INPUT_CLOSURE'}
 $constructors=@(foreach($path in $Group.fixtureRecipe.constructorPaths){[pscustomobject]@{path=$path;identity=$byPath[$path].identity}})
 if($Facts.fixtureRecipeIdentity-cne(Get-AiwEvidenceValueIdentity @{recipe=$Group.fixtureRecipe;constructors=$constructors})){throw 'TEST_FIXTURE_RECIPE_CLOSURE'}
 $wanted=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($row in $expected){$null=$wanted.Add($row.path)}
 $subset=@($AvailableRows|Where-Object{$wanted.Contains($_.path)})
 if($Facts.sourceInputsIdentity-cne(Get-AiwEvidenceValueIdentity $subset)){throw 'TEST_BEHAVIOR_ROLE_CLOSURE'}
}
function Get-AiwEvidenceGroupBehaviorIdentity($Definition,$Group){
 $others=@($Group.behaviorInputs.definitionGroupIds|ForEach-Object{$id=$_;@($Definition.groups|Where-Object id -CEQ $id)[0]})
 return Get-AiwEvidenceValueIdentity ([ordered]@{group=$Group;definitionGroups=$others;commonSets=$(if($Group.behaviorInputs.includeCommonSets){@{mechanism=$Definition.mechanismVersionPaths;root=$Definition.rootAdoptionPaths;maintenance=$Definition.maintenancePaths}}else{$null});wholeDefinition=$(if($Group.behaviorInputs.wholeDefinition){$Definition}else{$null})})
}
function Get-AiwEvidenceBehaviorIdentity($Facts){
 $fields=@('root','definitionIdentity','groupIdentity','validatorIdentity','verifierIdentity','inputs','unknownDependencies','options','environment','commandArguments','rootSensitive','fixtureRecipeIdentity','environmentPolicy','locationPolicy','executionContext','nativeEnvironment','behaviorContractIdentity')
 if($null-ne$Facts.PSObject.Properties['inputView']){$fields+=@('inputView','sourceInputsIdentity')}
 if($null-ne$Facts.PSObject.Properties['packageIdentity']){$fields+=@('packageIdentity','packageTreeIdentity','buildCommandIdentity')}
 # During construction the derived hash is not present yet.
 if($null-eq$Facts.PSObject.Properties['behaviorContractIdentity']){$fields=@($fields|Where-Object{$_-cne'behaviorContractIdentity'})}
 Assert-AiwEvidenceFields $Facts $fields 'behavior-facts'
 $required=@('groupIdentity','inputs','unknownDependencies','options','environment','commandArguments','root','rootSensitive','fixtureRecipeIdentity','environmentPolicy','locationPolicy','executionContext','nativeEnvironment')
 foreach($name in $required){if($null-eq$Facts.PSObject.Properties[$name]){throw ('TEST_BEHAVIOR_FACT_MISSING|'+$name)}}
 if($Facts.inputs-isnot[Array]-or$Facts.unknownDependencies-isnot[Array]-or$Facts.commandArguments-isnot[Array]-or$Facts.rootSensitive-isnot[bool]-or-not$Facts.rootSensitive-or$Facts.nativeEnvironment-isnot[pscustomobject]){throw 'TEST_BEHAVIOR_FACT_TYPE'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($input in $Facts.inputs){Assert-AiwEvidenceReference $input 'behavior-input';if(-not$seen.Add($input.path)){throw 'TEST_BEHAVIOR_INPUT_DUPLICATE'}}
 foreach($arg in $Facts.commandArguments){if($arg-isnot[string]){throw 'TEST_COMMAND_ARGUMENT_TYPE'}}
 foreach($item in $Facts.nativeEnvironment.PSObject.Properties){if($null-ne$item.Value-and$item.Value-isnot[string]){throw 'TEST_NATIVE_ENVIRONMENT_TYPE'}}
 $e=$Facts.environment;$ep=$Facts.environmentPolicy
 Assert-AiwEvidenceFields $ep @('mode','influentialVariables','negativeToolLookups') 'environment-policy'
 if($ep.mode-cnotin@('EXACT','EFFECTIVE_TOOLS')-or$ep.influentialVariables-isnot[Array]-or$ep.negativeToolLookups-isnot[Array]){throw 'TEST_ENVIRONMENT_POLICY'}
 $effective=$e;$nativeEffective=$Facts.nativeEnvironment
 if($ep.mode-ceq'EFFECTIVE_TOOLS'){
  $variables=[ordered]@{};foreach($name in @(@('COMSPEC','PSModulePath')+@($ep.influentialVariables)|Select-Object -Unique)){if($name-isnot[string]-or$null-eq$e.variables.PSObject.Properties[$name]){throw 'TEST_ENVIRONMENT_VARIABLE_UNOBSERVED'};$variables[$name]=$e.variables.$name}
  # Tool paths/bytes/versions and observed negative resolutions remain exact.
  $effective=[ordered]@{platform=$e.platform;architecture=$e.architecture;powerShell=$e.powerShell;locale=$e.locale;uiLocale=$e.uiLocale;tools=$e.tools;modules=$e.modules;variables=$variables;negativeToolLookups=$e.negativeToolLookups}
  $nativeEffective=[ordered]@{};foreach($name in @(@('COMSPEC','PSModulePath')+@($ep.influentialVariables)|Select-Object -Unique)){if($null-eq$Facts.nativeEnvironment.PSObject.Properties[$name]){throw 'TEST_NATIVE_ENVIRONMENT_UNOBSERVED'};$nativeEffective[$name]=$Facts.nativeEnvironment.$name}
 }
 $lp=$Facts.locationPolicy;Assert-AiwEvidenceFields $lp @('mode','mappings','conditions') 'location-policy'
 if($lp.mode-cnotin@('EXACT','LOGICAL_ROOT')-or$lp.mappings-isnot[Array]-or$lp.conditions-isnot[Array]){throw 'TEST_LOCATION_POLICY'}
 $root=$Facts.root;$arguments=@($Facts.commandArguments)
 if($lp.mode-ceq'LOGICAL_ROOT'){
  if($Facts.executionContext.targetKind-cne'SAME_ROOT'-or$lp.mappings.Count-ne1-or$lp.conditions.Count-eq0){throw 'TEST_LOGICAL_ROOT_UNPROVEN'}
  $m=$lp.mappings[0];Assert-AiwEvidenceFields $m @('logicalRoot','physicalRoot') 'logical-root-map'
  if($m.logicalRoot-cne'SOURCE_VIEW'-or$m.physicalRoot-cne$root){throw 'TEST_LOGICAL_ROOT_UNPROVEN'}
  foreach($condition in $lp.conditions){Assert-AiwEvidenceFields $condition @('name','value') 'location-condition';if($condition.name-cnotin@('volume','caseSensitivity','pathLengthClass','permissions','ownership','reparse')-or$condition.value-isnot[string]){throw 'TEST_LOGICAL_ROOT_UNPROVEN'}}
  if(@($lp.conditions.name|Select-Object -Unique).Count-ne6-or$lp.conditions.Count-ne6){throw 'TEST_LOGICAL_ROOT_UNPROVEN'}
  $arguments=@($arguments|ForEach-Object{if($_-isnot[string]){throw 'TEST_COMMAND_ARGUMENT_TYPE'};if($_-ceq$root){'@SOURCE_VIEW'}elseif($_.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){('@SOURCE_VIEW/'+$_.Substring($root.Length+1).Replace('\','/'))}else{$_}})
  $root='@SOURCE_VIEW'
 }
 $context=if($lp.mode-ceq'LOGICAL_ROOT'){@{schemaVersion=1;targetKind='SAME_ROOT';controlRoot='@SOURCE_VIEW';executionRoot='@SOURCE_VIEW';executionTargetRef=$null;targetObservation=$null}}else{$Facts.executionContext}
 $location=@{mode=$lp.mode;conditions=$lp.conditions}
 return Get-AiwEvidenceValueIdentity ([ordered]@{groupIdentity=$Facts.groupIdentity;inputs=$Facts.inputs;unknownDependencies=$Facts.unknownDependencies;options=$Facts.options;environment=$effective;commandArguments=$arguments;root=$root;rootSensitive=$Facts.rootSensitive;fixtureRecipeIdentity=$Facts.fixtureRecipeIdentity;locationPolicy=$location;executionContext=$context;nativeEnvironment=$nativeEffective})
}
function Assert-AiwEvidenceNativeRecord($Record,$Group,$Snapshot,$Artifacts,[switch]$ForReuse,[switch]$AllowPartial,$Suite=$null){
 $null=Get-AiwEvidenceLoadedIdentity
 Assert-AiwEvidenceFields $Record @('schemaVersion','executionKind','groupId','phase','before','after','processResult','startedUtc','endedUtc','outcome','cases','completion','cleanup','validatorIdentity','omissions','producer','executionContext','behaviorContractIdentity') 'executed2'
 if($Record.schemaVersion-isnot[int]-and$Record.schemaVersion-isnot[long]-or$Record.schemaVersion-ne2-or$Record.executionKind-cne'EXECUTED'-or$Record.groupId-cne$Group.id-or$Record.phase-cne$Group.phase){throw 'RELEASE_CURRENT_EXECUTION_SCALAR'}
 Assert-AiwEvidenceFields $Record.producer @('name','contractVersion','moduleRef') 'producer'
 Assert-AiwEvidenceReference $Record.producer.moduleRef 'producer-module'
 if($Record.producer.name-cne'TestGroupEvidence'-or($Record.producer.contractVersion-isnot[int]-and$Record.producer.contractVersion-isnot[long])-or$Record.producer.contractVersion-ne2-or$Record.producer.moduleRef.identity-cne$Record.validatorIdentity){throw 'TEST_PRODUCER_PROVENANCE'}
 Assert-AiwEvidenceReference $Record.processResult 'process-ref'
 foreach($snapshotValue in @($Record.before,$Record.after,$Snapshot)){Assert-AiwEvidenceFields $snapshotValue @('facts','identity') 'snapshot';if((Get-AiwEvidenceValueIdentity $snapshotValue.facts)-cne$snapshotValue.identity){throw 'TEST_SNAPSHOT_CORRUPT'}}
 foreach($snapshotValue in @($Record.before,$Record.after,$Snapshot)){Assert-AiwEvidenceDeclaredInputs $snapshotValue.facts $Group}
 foreach($snapshotValue in @($Record.before,$Record.after,$Snapshot)){if($snapshotValue.facts.behaviorContractIdentity-cne(Get-AiwEvidenceBehaviorIdentity $snapshotValue.facts)){throw 'TEST_BEHAVIOR_IDENTITY_CORRUPT'}}
 if($Record.before.identity-cne$Record.after.identity-or$Record.behaviorContractIdentity-cne(Get-AiwEvidenceBehaviorIdentity $Record.after.facts)-or$Record.behaviorContractIdentity-cne(Get-AiwEvidenceBehaviorIdentity $Snapshot.facts)){throw 'TEST_RECORD_FAILED_PARTIAL_OR_INPUT_DRIFT'}
 if((Get-AiwEvidenceValueIdentity $Record.executionContext)-cne(Get-AiwEvidenceValueIdentity $Record.after.facts.executionContext)){throw 'TEST_EXECUTION_CONTEXT_BINDING'}
 Assert-AiwEvidenceExecutionContext $Record.executionContext $Artifacts.descriptorBytes
 Assert-AiwEvidenceExecutionContext $Snapshot.facts.executionContext $Artifacts.currentDescriptorBytes
 if(($Record.outcome-cne'PASS'-and(-not$AllowPartial-or$ForReuse-or$Record.outcome-cne'PARTIAL'))-or($ForReuse-and($Group.alwaysFresh-or@($Group.unknownDependencies).Count))){throw 'TEST_FRESH_REQUIRED_OR_NOT_PASS'}
 $p=$Artifacts.process;$l=$Artifacts.launch
 Assert-AiwEvidenceFields $p @('runId','status','command','pid','creationUtc','executor','directConsumer','startedUtc','processExitedUtc','endedUtc','exitCode','stdout','stderr','timing','cancellation','streamOrdering','schemaVersion','environment') 'process'
 Assert-AiwEvidenceFields $p.command @('executable','executableIdentity','executableVersion','arguments','cwd') 'native-command'
 Assert-AiwEvidenceFields $l @('runId','pid','creationUtc','startedUtc','executable','executableIdentity','executableVersion','arguments','cwd','environmentNames','raw','resultPath','executor','directConsumer','schemaVersion','environment') 'launch'
 if(($p.schemaVersion-isnot[int]-and$p.schemaVersion-isnot[long])-or$p.schemaVersion-ne2-or($l.schemaVersion-isnot[int]-and$l.schemaVersion-isnot[long])-or$l.schemaVersion-ne2-or(Get-AiwEvidenceValueIdentity $p.environment)-cne(Get-AiwEvidenceValueIdentity $l.environment)-or(Get-AiwEvidenceValueIdentity $p.environment)-cne(Get-AiwEvidenceValueIdentity $Record.after.facts.nativeEnvironment)){throw 'TEST_NATIVE_ENVIRONMENT_DRIFT'}
 if($p.status-cne'PASS'-or($p.exitCode-isnot[int]-and$p.exitCode-isnot[long])-or$p.exitCode-ne0-or$null-ne$p.cancellation-or$p.streamOrdering-cne'INTRA_STREAM_ONLY'){throw 'RELEASE_PROCESS_NOT_PASS'}
 if($p.pid-isnot[int]-and$p.pid-isnot[long]-or$p.pid-lt1-or($l.pid-isnot[int]-and$l.pid-isnot[long])-or$l.pid-ne$p.pid-or$l.runId-cne$p.runId-or$l.resultPath-cne$Record.processResult.path-or$l.startedUtc-cne$p.startedUtc-or$l.creationUtc-cne$p.creationUtc-or$l.executor-cne$p.executor-or$l.directConsumer-cne$p.directConsumer){throw 'RELEASE_CURRENT_EXECUTION_LAUNCH'}
 foreach($pair in @(@('cwd','cwd'),@('executable','executable'),@('executableIdentity','executableIdentity'),@('executableVersion','executableVersion'))){if($l.($pair[0])-cne$p.command.($pair[1])){throw 'RELEASE_CURRENT_EXECUTION_LAUNCH'}}
 if($l.arguments-isnot[Array]-or$l.raw-isnot[Array]-or$l.environmentNames-isnot[Array]-or(Get-AiwEvidenceValueIdentity @($l.arguments))-cne(Get-AiwEvidenceValueIdentity @($p.command.arguments))-or(Get-AiwEvidenceValueIdentity @($l.raw))-cne(Get-AiwEvidenceValueIdentity @($p.stdout.path,$p.stderr.path))){throw 'RELEASE_CURRENT_EXECUTION_LAUNCH'}
 $pwsh=@($Record.after.facts.environment.tools|Where-Object name -CEQ pwsh)
 if($pwsh.Count-ne1-or$p.command.cwd-cne$Record.after.facts.root-or$p.command.cwd-cne$Record.executionContext.executionRoot-or$p.command.executable-cne$pwsh[0].path-or$p.command.executableIdentity-cne$pwsh[0].identity-or$p.command.executableVersion-cne$pwsh[0].fileVersion-or(Get-AiwEvidenceValueIdentity @($p.command.arguments))-cne(Get-AiwEvidenceValueIdentity @($Record.after.facts.commandArguments))){throw 'RELEASE_PROCESS_COMMAND'}
 foreach($name in @('stdout','stderr')){Assert-AiwEvidenceReference $p.$name 'raw-ref';if((Get-AiwEvidenceByteIdentity $Artifacts.($name+'Bytes'))-cne$p.$name.identity){throw 'TEST_RAW_CORRUPT'}}
 $stdout=$script:EvidenceUtf8.GetString($Artifacts.stdoutBytes);$stderr=$script:EvidenceUtf8.GetString($Artifacts.stderrBytes)
 $cases=@();$counts=@{}
 foreach($line in $stdout-split'\r?\n'){if($line-cmatch'^PASS\|(.+)$'){$name=$Matches[1].Split('|')[0];if(-not$counts.ContainsKey($name)){$counts[$name]=0};$counts[$name]++;$cases+=@{id=$Group.id+'/'+$name+'#'+$counts[$name].ToString('D4');name=$name;occurrence=$counts[$name];outcome='PASS'}}}
 if(-not$cases.Count-or(Get-AiwEvidenceValueIdentity $cases)-cne(Get-AiwEvidenceValueIdentity @($Record.cases))){throw 'RELEASE_CASE_RAW_MISMATCH'}
 foreach($id in $Group.requiredCaseIds){if($id-cnotin@($Record.cases.name)){throw 'RELEASE_REQUIRED_CASE_MISSING'}}
 $omissions=@(@($stdout,$stderr)|ForEach-Object{$_-split'\r?\n'}|Where-Object{$_-cmatch'^(SKIP|NOT_RUN|UNKNOWN)\|'-and-not($Group.id-cin@('integration.surface','integration.full-source')-and$_-ceq'NOT_RUN|historical-baseline-executable-regression|reason=retired-executable-suite-history-only')})
 if((Get-AiwEvidenceValueIdentity $omissions)-cne(Get-AiwEvidenceValueIdentity @($Record.omissions))-or($omissions.Count-and($ForReuse-or-not$AllowPartial-or$Record.outcome-cne'PARTIAL'))-or(-not$omissions.Count-and$Record.outcome-cne'PASS')){throw 'TEST_SKIPPED_OR_UNKNOWN_COVERAGE'}
 $terminal=@($stdout-split'\r?\n'|Where-Object{$_-cmatch$Group.completionPattern});if($terminal.Count-ne1-or$Record.completion-cne$terminal[0]){throw 'RELEASE_GROUP_COMPLETION'}
 Assert-AiwEvidenceFields $Record.cleanup @('status','root','entries','workers') 'cleanup';if($Record.cleanup.status-cne'CLEAN'-or@($Record.cleanup.entries).Count-or@($Record.cleanup.workers).Count){throw 'RELEASE_CLEANUP_DIRTY'}
 $start=Get-AiwEvidenceTime $Record.startedUtc 'record-start';$end=Get-AiwEvidenceTime $Record.endedUtc 'record-end';$created=Get-AiwEvidenceTime $p.creationUtc 'process-creation';$exited=Get-AiwEvidenceTime $p.processExitedUtc 'process-exit'
 if($end-lt$start-or$start-ne(Get-AiwEvidenceTime $p.startedUtc 'process-start')-or$end-ne(Get-AiwEvidenceTime $p.endedUtc 'process-end')-or$start-ne(Get-AiwEvidenceTime $l.startedUtc 'launch-start')-or$created-lt$start-or$created-gt$exited-or$exited-gt$end){throw 'RELEASE_CURRENT_EXECUTION_WINDOW'}
 $phase=@($script:EvidenceUtf8.GetString($Artifacts.phaseBytes)-split'\r?\n'|Where-Object{$_}|ForEach-Object{(ConvertFrom-AiwStrictInputJson $_ -StringFields @('utc')).Value})
 if(@($phase|Where-Object{$_.runId-cne$p.runId-or$_.groupId-cne$Group.id}).Count-or@($phase|Where-Object{$_.event-ceq'START'-and$_.step-ceq'native-start'}).Count-ne1-or@($phase|Where-Object{$_.event-ceq'END'-and$_.step-ceq'exit-drain'-and$_.data.exitCode-eq0}).Count-ne1){throw 'RELEASE_PHASE_RUN_BINDING'}
 $previous=$start
 foreach($event in $phase){Assert-AiwEvidenceFields $event @('utc','runId','groupId','step','event','data') 'phase-event';$at=Get-AiwEvidenceTime $event.utc 'phase-event';if($at-lt$previous-or$at-gt$end){throw 'RELEASE_PHASE_RUN_BINDING'};$previous=$at}
 if($Suite-and-not$ForReuse){if($start-lt(Get-AiwEvidenceTime $Suite.startedUtc 'suite-start')-or$end-gt(Get-AiwEvidenceTime $Suite.endedUtc 'suite-end')){throw 'RELEASE_CURRENT_EXECUTION_WINDOW'}}
 $null=Get-AiwEvidenceLoadedIdentity
 return $true
}
function Assert-AiwEvidenceRevalidation($Validation,$Original,$Group,$Snapshot,$Suite){
 $null=Get-AiwEvidenceLoadedIdentity
 Assert-AiwEvidenceFields $Validation @('schemaVersion','executionKind','groupId','original','currentSnapshot','validatorIdentity','checkedUtc','outcome','reason','verifierRef','originalRecordSchemaVersion','verifiedBehaviorIdentity','derivations') 'revalidation'
 Assert-AiwEvidenceReference $Validation.original 'revalidation-original';Assert-AiwEvidenceReference $Validation.verifierRef 'verifier-ref'
 Assert-AiwEvidenceFields $Validation.currentSnapshot @('facts','identity') 'revalidation-snapshot'
 if($Validation.groupId-isnot[string]){throw 'RELEASE_STRING|revalidation|groupId'}
 if(($Validation.schemaVersion-isnot[int]-and$Validation.schemaVersion-isnot[long])-or$Validation.schemaVersion-ne2-or$Validation.executionKind-cne'REVALIDATED'-or$Validation.outcome-cne'PASS'-or$Validation.groupId-cne$Group.id-or$Validation.reason-cne'Original native facts verified against current behavior contract'-or($Validation.originalRecordSchemaVersion-isnot[int]-and$Validation.originalRecordSchemaVersion-isnot[long])-or$Validation.originalRecordSchemaVersion-ne2-or$Validation.derivations-isnot[Array]){throw 'RELEASE_CURRENT_REVALIDATION_SCALAR'}
 if($Group.alwaysFresh-or@($Group.unknownDependencies).Count){throw 'RELEASE_CURRENT_REVALIDATION_FRESH_REQUIRED'}
 if($Validation.original.path-cne$Original.path-or$Validation.original.identity-cne$Original.identity-or$Validation.currentSnapshot.identity-cne$Snapshot.identity-or(Get-AiwEvidenceValueIdentity $Validation.currentSnapshot.facts)-cne$Snapshot.identity-or$Validation.validatorIdentity-cne$Snapshot.facts.verifierIdentity-or$Validation.verifierRef.identity-cne$Snapshot.facts.verifierIdentity-or$Validation.verifiedBehaviorIdentity-cne(Get-AiwEvidenceBehaviorIdentity $Snapshot.facts)){throw 'RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT'}
 if($Validation.derivations.Count){throw 'TEST_UNSUPPORTED_DERIVATION'}
 $checked=Get-AiwEvidenceTime $Validation.checkedUtc 'revalidation-checked'
 if($Suite-and($checked-lt(Get-AiwEvidenceTime $Suite.startedUtc 'suite-start')-or$checked-gt(Get-AiwEvidenceTime $Suite.endedUtc 'suite-end'))){throw 'RELEASE_CURRENT_REVALIDATION_WINDOW'}
 $null=Get-AiwEvidenceLoadedIdentity
}
Export-ModuleMember -Function Get-AiwEvidenceLoadedIdentity,Get-AiwEvidenceDependencyPaths,Assert-AiwEvidenceDeclaredInputs,Assert-AiwEvidenceSnapshotInputs,Restore-AiwEvidenceContextStrings,Get-AiwEvidenceGroupBehaviorIdentity,Assert-AiwEvidenceFields,Get-AiwEvidenceCanonical,Get-AiwEvidenceValueIdentity,Get-AiwEvidenceByteIdentity,Get-AiwEvidenceTime,Assert-AiwEvidenceReference,Assert-AiwEvidenceExecutionContext,Get-AiwEvidenceBehaviorIdentity,Assert-AiwEvidenceNativeRecord,Assert-AiwEvidenceRevalidation
