# @design-contract standards/software/VALIDATION.md
# Private execution evidence; never a release qualification or authorization.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1')
Import-Module (Join-Path $PSScriptRoot '../scripts/StrictJsonInput.psm1')
$script:TestEvidenceOwner=@(Import-Module (Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1') -PassThru)[0]
$script:EvidenceModulePath=$PSCommandPath
$script:TestTargetObservations=@{}
$script:TestLoadedInputs=@(foreach($path in @($PSCommandPath,(Join-Path $PSScriptRoot '../scripts/StrictJsonInput.psm1'),(Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1'))){@{path=$path;identity=(Get-AiwTestFileIdentity $path)}})
function Get-AiwTestLoadedVerifierIdentity {
 foreach($input in $script:TestLoadedInputs){if((Get-AiwTestFileIdentity $input.path)-cne$input.identity){throw 'TEST_EVIDENCE_MODULE_DRIFT'}}
 if($script:TestEvidenceOwner.Path-cne[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1'))){throw 'TEST_VERIFIER_MODULE_OWNER'}
 return & $script:TestEvidenceOwner.ExportedCommands['Get-AiwEvidenceLoadedIdentity']
}
function Assert-TestFields($Value,[string[]]$Fields,[string]$Label){
 if($Value-isnot[pscustomobject]-or@($Value.PSObject.Properties.Name).Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$Value.PSObject.Properties.Name}).Count){throw ('TEST_EVIDENCE_FIELDS|'+$Label)}
}
function Read-AiwTestJson([string]$Path,[string[]]$StringFields=@(),[string[]]$NullableStringFields=@()){
 $null=Get-AiwTestFileIdentity $Path
 $bytes=[IO.File]::ReadAllBytes($Path);if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'TEST_JSON_BOM'}
 $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
 $document=[Text.Json.JsonDocument]::Parse($text)
 function Check-JsonMembers($Element){if($Element.ValueKind-eq[Text.Json.JsonValueKind]::Object){$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($property in $Element.EnumerateObject()){if(-not$seen.Add($property.Name)){throw 'TEST_JSON_DUPLICATE_MEMBER'};Check-JsonMembers $property.Value}}elseif($Element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($entry in $Element.EnumerateArray()){Check-JsonMembers $entry}}}
 try{Check-JsonMembers $document.RootElement}finally{$document.Dispose()}
 if($StringFields.Count-or$NullableStringFields.Count){$value=(ConvertFrom-AiwStrictInputJson $text -StringFields $StringFields -NullableStringFields $NullableStringFields).Value}else{$value=$text|ConvertFrom-Json -Depth 100}
 return Restore-AiwEvidenceContextStrings $text $value
}
function Get-TestCanonical($Value){
  return Get-AiwReleaseCanonical $Value
}
function Get-TestValueIdentity($Value){$text=Get-TestCanonical $Value;return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))}
function Assert-TestLocator([string]$Path){if($Path-cmatch'^[A-Za-z]:|^[/\\]|\\|:|(^|/)\.{1,2}(/|$)' -or[string]::IsNullOrWhiteSpace($Path)){throw ('TEST_DEPENDENCY_LOCATOR|'+$Path)}}
function Read-AiwTestGroupDefinition([string]$Path){
 $definition=Read-AiwTestJson $Path
 if($definition.schemaVersion-isnot[int]-and$definition.schemaVersion-isnot[long]){throw 'TEST_DEFINITION_VERSION_PHASE'}
  $fields=@('schemaVersion','phase','mechanismVersionPaths','rootAdoptionPaths','maintenancePaths','groups')
  if($definition.schemaVersion-in@(2,3)){$fields+=@('inputView','sourceViewPaths');if($definition.phase-cne'PREPACKAGE_AND_POSTBUILD'-or$definition.inputView-cne'SOURCE_PAYLOAD_V1'){throw 'TEST_DEFINITION_VERSION_PHASE'};foreach($path in $definition.sourceViewPaths){Assert-TestLocator $path}}
  elseif($definition.schemaVersion-ne1-or$definition.phase-cne'PREPACKAGE'){throw 'TEST_DEFINITION_VERSION_PHASE'}
  Assert-TestFields $definition $fields 'definition'
 foreach($paths in @($definition.mechanismVersionPaths,$definition.rootAdoptionPaths,$definition.maintenancePaths)){
  $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($locator in $paths){Assert-TestLocator $locator;if($locator-ceq'RELEASE_MANIFEST.json'-or-not$seen.Add($locator)){throw 'TEST_DEFINITION_DUPLICATE_DEPENDENCY'}}
 }
 $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($group in $definition.groups){
    $groupFields=@('id','entry','arguments','phase','requiredFor','casePolicy','requiredCaseIds','completionPattern','dependencies','unknownDependencies','alwaysFresh','fixturePolicy','tools')
  if($definition.schemaVersion-eq3){$groupFields+=@('groupContractVersion','behaviorInputs','fixtureRecipe','environmentPolicy','locationPolicy')}
  Assert-TestFields $group $groupFields 'group'
  if($definition.schemaVersion-eq3){
   if($group.groupContractVersion-isnot[int]-and$group.groupContractVersion-isnot[long]-or$group.groupContractVersion-lt1){throw 'TEST_GROUP_CONTRACT_VERSION'}
   Assert-TestFields $group.behaviorInputs @('files','definitionGroupIds','wholeDefinition','includeCommonSets') 'behavior-inputs'
   Assert-TestFields $group.fixtureRecipe @('version','steps','constructorPaths') 'fixture-recipe'
   Assert-TestFields $group.environmentPolicy @('mode','influentialVariables','negativeToolLookups') 'environment-policy'
   Assert-TestFields $group.locationPolicy @('mode','mappings','conditions') 'location-policy'
   if($group.behaviorInputs.files-isnot[Array]-or$group.behaviorInputs.definitionGroupIds-isnot[Array]-or$group.behaviorInputs.wholeDefinition-isnot[bool]-or$group.behaviorInputs.includeCommonSets-isnot[bool]-or$group.fixtureRecipe.steps-isnot[Array]-or$group.fixtureRecipe.constructorPaths-isnot[Array]-or($group.fixtureRecipe.version-isnot[int]-and$group.fixtureRecipe.version-isnot[long])-or$group.fixtureRecipe.version-ne1-or$group.environmentPolicy.mode-cnotin@('EXACT','EFFECTIVE_TOOLS')-or$group.environmentPolicy.influentialVariables-isnot[Array]-or$group.environmentPolicy.negativeToolLookups-isnot[Array]-or$group.locationPolicy.mode-cnotin@('EXACT','LOGICAL_ROOT')-or$group.locationPolicy.mappings-isnot[Array]-or$group.locationPolicy.conditions-isnot[Array]){throw 'TEST_GROUP_BEHAVIOR_CONTRACT'}
   foreach($path in @($group.behaviorInputs.files)+@($group.fixtureRecipe.constructorPaths)){Assert-TestLocator $path}
   foreach($id in $group.behaviorInputs.definitionGroupIds){if(@($definition.groups|Where-Object id -CEQ $id).Count-ne1){throw 'TEST_GROUP_DEFINITION_DEPENDENCY'}}
  }
   if($group.id-cnotmatch'^[a-z][a-z0-9.-]*$'-or-not$ids.Add($group.id)-or$group.phase-cnotin@('PREPACKAGE','POSTBUILD')-or($definition.schemaVersion-eq1-and$group.phase-cne'PREPACKAGE')-or$group.casePolicy-cne'OBSERVED_NAMED_CASES'-or$group.completionPattern-notmatch'^\^'){throw 'TEST_GROUP_ID_PHASE_CASE_POLICY'}
  Assert-TestLocator $group.entry
  foreach($locator in $group.dependencies){Assert-TestLocator $locator}
  if($group.arguments-isnot[Array]-or$group.requiredCaseIds-isnot[Array]-or$group.unknownDependencies-isnot[Array]-or$group.alwaysFresh-isnot[bool]){throw 'TEST_GROUP_ARRAY_BOOLEAN_TYPE'}
  $cases=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($case in $group.requiredCaseIds){if([string]::IsNullOrWhiteSpace($case)-or-not$cases.Add($case)){throw 'TEST_GROUP_DUPLICATE_CASE'}}
 }
 if($ids.Count-eq0){throw 'TEST_GROUPS_EMPTY'}
 return $definition
}
function Get-AiwTestEnvironment {
 param([string[]]$Tools=@('pwsh'))
 $toolsFound=@()
 foreach($tool in $Tools){$command=Get-Command $tool -CommandType Application -ErrorAction Stop|Select-Object -First 1;$full=$command.Source;$toolsFound+=@{name=$tool;path=$full;identity=(Get-AiwTestFileIdentity $full);fileVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($full).FileVersion}}
 return [ordered]@{platform=[Environment]::OSVersion.VersionString;architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();powerShell=$PSVersionTable.PSVersion.ToString();locale=[Globalization.CultureInfo]::CurrentCulture.Name;uiLocale=[Globalization.CultureInfo]::CurrentUICulture.Name;tools=$toolsFound;variables=@{AIW_TEST_HOST='ISOLATED_GROUP';COMSPEC=$env:COMSPEC;PATH=$env:PATH;PSModulePath=$env:PSModulePath;TEMP=$env:TEMP;TMP=$env:TMP;tempBase=[IO.Path]::GetTempPath()}}
}
function Get-AiwTestGroupArguments([string]$SourceRoot,$Group,$Options){
 $args=@('-NoProfile','-NonInteractive','-File',(Join-Path $SourceRoot $Group.entry))+@($Group.arguments)
 $values=@{};foreach($property in $Options.PSObject.Properties){$values[$property.Name]=$property.Value}
 if($Options-is[Collections.IDictionary]){foreach($key in $Options.Keys){$values[$key]=$Options[$key]}}
 $integrationSkips=if($Group.entry-ceq'framework/versions/2.0.0/tests/integration-surface-tests.ps1'){@('SkipManifest','SkipBaseline')}elseif($Group.entry-ceq'framework/versions/2.0.0/tests/run-framework-tests.ps1'){@('SkipManifest','SkipBaseline','SkipPerformanceSmoke')}else{@()}
 if($Group.id-clike'integration.*'){foreach($name in $integrationSkips){if($values.ContainsKey($name)-and$values[$name]){$args+='-'+$name}}}
 if($Group.id-ceq'governance-contract'-and$values.ContainsKey('SkipPerformanceSmoke')-and$values.SkipPerformanceSmoke){$args+='-SkipPerformanceSmoke'}
  if($Group.id-clike'presets.*'-and$values.ContainsKey('MaintenanceFixture')-and$values.MaintenanceFixture){$args+='-MaintenanceFixture'}
  if($Group.phase-ceq'POSTBUILD'){foreach($name in @('PackagePath','ExtractedPackagePath','BuildCommandPath')){if(-not$values.ContainsKey($name)-or-not$values[$name]){throw 'TEST_POSTBUILD_INPUT_REQUIRED'};$args+=('-'+$name);$args+=[string]$values[$name]}}
 return @($args)
}
function Get-AiwTestDependencySnapshotLegacy {
 param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DefinitionPath,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)]$Group,[Parameter(Mandatory)]$Options)
 $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($SourceRoot));$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($path in @($Group.dependencies)+@($Group.entry,'framework/versions/2.0.0/tests/run-framework-tests.ps1','framework/versions/2.0.0/tests/TestHarness.psm1','framework/versions/2.0.0/tests/TestGroupEvidence.psm1','framework/versions/2.0.0/tests/test-groups.json')){$null=$paths.Add($path)}
 foreach($path in @('framework/versions/2.0.0/scripts/ReleaseValidation.psm1','framework/versions/2.0.0/scripts/StrictJsonInput.psm1')){$null=$paths.Add($path)}
 if($Group.fixturePolicy-ceq'MECHANISM'){
  foreach($path in $Definition.mechanismVersionPaths){$null=$paths.Add('framework/versions/2.0.0/'+$path)}
  foreach($path in @($Definition.rootAdoptionPaths)+@($Definition.maintenancePaths)){$null=$paths.Add($path)}
 }else{
  # A whole-tree consumer really depends on every version member, including tests.
  foreach($item in Get-ChildItem -LiteralPath (Join-Path $root 'framework/versions/2.0.0') -Recurse -File -Force){$null=$paths.Add([IO.Path]::GetRelativePath($root,$item.FullName).Replace('\','/'))}
 }
 [string[]]$sorted=@($paths);[Array]::Sort($sorted,[StringComparer]::Ordinal)
 $rows=@();foreach($path in $sorted){Assert-TestLocator $path;$rows+=@{path=$path;identity=(Get-AiwTestFileIdentity (Join-Path $root $path))}}
 $environment=Get-AiwTestEnvironment $Group.tools
  $snapshot=[ordered]@{root=$root;definitionIdentity=(Get-AiwTestFileIdentity $DefinitionPath);groupIdentity=(Get-TestValueIdentity $Group);validatorIdentity=(Get-AiwTestFileIdentity $script:EvidenceModulePath);inputs=$rows;unknownDependencies=@($Group.unknownDependencies);options=$Options;environment=$environment;commandArguments=@(Get-AiwTestGroupArguments $root $Group $Options);rootSensitive=$true}
  if($Group.phase-ceq'POSTBUILD'){
   $packageMembers=Get-AiwReleaseTreeMembers $root
   $snapshot.packageIdentity=Get-AiwTestFileIdentity $Options.PackagePath
   $snapshot.packageTreeIdentity=Get-AiwReleaseValueIdentity @($packageMembers)
   $snapshot.buildCommandIdentity=Get-AiwTestFileIdentity $Options.BuildCommandPath
  }
  if($Definition.schemaVersion-eq2-and$Group.phase-ceq'PREPACKAGE'){
   $closurePath=Join-Path $root 'source-inputs.json';$closure=Read-AiwTestJson $closurePath
   if($closure.inputView-cne'SOURCE_PAYLOAD_V1'-or$closure.definitionIdentity-cne$snapshot.definitionIdentity){throw 'TEST_SOURCE_VIEW_BINDING'}
   $snapshot.inputView='SOURCE_PAYLOAD_V1';$snapshot.sourceInputsIdentity=Get-TestValueIdentity @(@($closure.inputs)+@($closure.syntheticInputs)|Where-Object{$paths.Contains($_.path)})
   foreach($synthetic in $closure.syntheticInputs){if((Get-AiwTestFileIdentity (Join-Path $root $synthetic.path))-cne$synthetic.identity){throw 'TEST_SYNTHETIC_INPUT_DRIFT'}}
  }
 return [pscustomobject]@{facts=$snapshot;identity=(Get-TestValueIdentity $snapshot)}
}
function Get-AiwTestGroupBehaviorIdentity($Definition,$Group){ return Get-AiwEvidenceGroupBehaviorIdentity $Definition $Group }
function Get-TestExecutionTarget([string]$SourceRoot,$Options,[string]$ControlRoot,[string]$TaskPath,$ExecutionTargetRef,$ExpectedTargetState){
 $optionsObject=$Options|ConvertTo-Json -Depth 50 -Compress|ConvertFrom-Json -Depth 50
 $values=@{ControlRoot=$ControlRoot;TaskPath=$TaskPath;ExecutionTargetRef=$ExecutionTargetRef;ExpectedTargetState=$ExpectedTargetState}
 foreach($name in @($values.Keys)){
  if($null-ne$optionsObject.PSObject.Properties[$name]){
   if($null-ne$values[$name]-and[string]$values[$name]-cne''-and(Get-TestValueIdentity $values[$name])-cne(Get-TestValueIdentity $optionsObject.$name)){throw 'TEST_EXECUTION_TARGET_OPTION_DRIFT'}
   $values[$name]=$optionsObject.$name
  }
 }
 $present=@($values.Keys|Where-Object{$null-ne$values[$_]-and[string]$values[$_]-cne''})
 if($present.Count-eq0){return [pscustomobject][ordered]@{schemaVersion=1;targetKind='SAME_ROOT';controlRoot=$SourceRoot;executionRoot=$SourceRoot;executionTargetRef=$null;targetObservation=$null}}
 if($present.Count-ne4){throw 'TEST_EXECUTION_TARGET_INPUT_COMBINATION'}
 Import-Module (Join-Path $PSScriptRoot '../scripts/ExecutionTargetContext.psm1')
 $cfg=Read-AiwTestJson (Join-Path $values.ControlRoot '.ai-workspace/project.json')
 if($cfg.controlPlaneLayout-cne'repo-local'){throw 'TEST_EXECUTION_TARGET_PROJECT_REQUIRED'}
 $fresh=Resolve-AiwExecutionTargetContext $values.ControlRoot $cfg.id $values.TaskPath $values.ExecutionTargetRef @($cfg.routineExcludedPaths)
 $null=Assert-AiwExecutionTargetState $fresh $values.ExpectedTargetState
 if($fresh.executionRoot-cne$SourceRoot){throw 'TEST_EXECUTION_TARGET_SOURCE_ROOT'}
 # Each call re-observes real Git and descriptor facts. The context is the first
 # bound observation in this loaded producer, revalidated on later calls. Its
 # original observedUtc is preserved, never replaced by a fabricated timestamp.
 $material=$fresh|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -Depth 30
 $material.targetObservation.PSObject.Properties.Remove('observedUtc')
 $key=Get-TestValueIdentity $material
 if(-not$script:TestTargetObservations.ContainsKey($key)){$script:TestTargetObservations[$key]=$fresh}
 return $script:TestTargetObservations[$key]
}
function Get-AiwTestDependencySnapshot {
 param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DefinitionPath,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)]$Group,[Parameter(Mandatory)]$Options,[hashtable]$NativeEnvironment=@{},[string]$ControlRoot,[string]$TaskPath,$ExecutionTargetRef=$null,$ExpectedTargetState=$null)
 if($Definition.schemaVersion-ne3){if($ControlRoot-or$TaskPath-or$null-ne$ExecutionTargetRef-or$null-ne$ExpectedTargetState){throw 'TEST_EXECUTION_TARGET_REQUIRES_SCHEMA3'};$legacy=@{};foreach($name in @('SourceRoot','DefinitionPath','Definition','Group','Options')){$legacy[$name]=$PSBoundParameters[$name]};return Get-AiwTestDependencySnapshotLegacy @legacy}
 $loadedVerifier=Get-AiwTestLoadedVerifierIdentity
 $root=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot))
 $context=Get-TestExecutionTarget $root $Options $ControlRoot $TaskPath $ExecutionTargetRef $ExpectedTargetState
 if($context.targetKind-ceq'GIT_WORKTREE'-and$Group.locationPolicy.mode-cne'EXACT'){throw 'TEST_EXECUTION_TARGET_LOGICAL_ROOT_DENIED'}
 $targetForbidden=@()
 if($context.targetKind-ceq'GIT_WORKTREE'){Import-Module (Join-Path $PSScriptRoot '../scripts/ExecutionTargetContext.psm1');$targetForbidden=@((Read-AiwTestJson (Join-Path $context.controlRoot '.ai-workspace/project.json')).routineExcludedPaths)}
 $versionPaths=@();if($Group.fixturePolicy-ceq'WHOLE_VERSION'){$versionPaths=@(Get-ChildItem -LiteralPath (Join-Path $root 'framework/versions/2.0.0') -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')})}
 $sorted=@(Get-AiwEvidenceDependencyPaths $Definition $Group $versionPaths)
 $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($path in $sorted){$null=$paths.Add($path)}
 $rows=@(foreach($path in $sorted){Assert-TestLocator $path;$full=if($context.targetKind-ceq'GIT_WORKTREE'){Resolve-AiwExecutionTargetCandidatePath $context $path $targetForbidden}else{Join-Path $root $path};[ordered]@{path=$path;identity=(Get-AiwTestFileIdentity $full)}})
 $environment=Get-AiwTestEnvironment $Group.tools
 foreach($name in $Group.environmentPolicy.influentialVariables){if($name-isnot[string]-or$name-cnotmatch'^[A-Za-z_][A-Za-z0-9_]*$'){throw 'TEST_ENVIRONMENT_VARIABLE_NAME'};if($name-cne'tempBase'){$environment.variables[$name]=[Environment]::GetEnvironmentVariable($name)}}
 $negative=@(foreach($name in $Group.environmentPolicy.negativeToolLookups){if($name-isnot[string]-or$name-cnotmatch'^[A-Za-z0-9._-]+$'){throw 'TEST_NEGATIVE_TOOL_NAME'};$found=@(Get-Command $name -CommandType Application -ErrorAction SilentlyContinue);[ordered]@{name=$name;found=($found.Count-gt0);path=$(if($found.Count){$found[0].Source}else{$null});identity=$(if($found.Count){Get-AiwTestFileIdentity $found[0].Source}else{$null})}})
 $environment['negativeToolLookups']=$negative
 $environment['modules']=@($rows|Where-Object{$_.path.EndsWith('.psm1',[StringComparison]::Ordinal)}|ForEach-Object{@{path=$_.path;identity=$_.identity}})
 $native=[ordered]@{};foreach($name in @(@('COMSPEC','PATH','PSModulePath','TEMP','TMP')+@($NativeEnvironment.Keys)|Sort-Object -Unique)){$native[$name]=if($NativeEnvironment.ContainsKey($name)){$NativeEnvironment[$name]}else{[Environment]::GetEnvironmentVariable($name)}}
 $location=$Group.locationPolicy|ConvertTo-Json -Depth 40 -Compress|ConvertFrom-Json -Depth 40
 if($location.mode-ceq'LOGICAL_ROOT'){
  foreach($mapping in $location.mappings){if($mapping.logicalRoot-cne'SOURCE_VIEW'-or$mapping.physicalRoot-cne'CURRENT_SOURCE_VIEW'){throw 'TEST_LOCATION_MAP_DECLARATION'};$mapping.physicalRoot=$root}
  if(-not[OperatingSystem]::IsWindows()){throw 'TEST_LOCATION_OBSERVATION_UNSUPPORTED'}
  if(-not('AiwTestLocationObservation' -as[type])){Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class AiwTestLocationObservation {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint access,uint share,IntPtr security,uint mode,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandleEx(SafeFileHandle h,int c,out uint value,uint size);
 public static uint CaseFlags(string p) {
  using(var h=CreateFile(p,0,7,IntPtr.Zero,3,0x02000000,IntPtr.Zero)) {
   uint value;if(h.IsInvalid || !GetFileInformationByHandleEx(h,23,out value,4)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());return value;
  }
 }
}
'@}
  $acl=Get-Acl -LiteralPath $root;$drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
  $maximum=(@($rows|ForEach-Object{(Join-Path $root $_.path).Length})+@($root.Length)|Measure-Object -Maximum).Maximum
  $observed=@{volume=($drive.Name+'|'+$drive.DriveFormat+'|'+$drive.VolumeLabel);caseSensitivity=([AiwTestLocationObservation]::CaseFlags($root)).ToString();pathLengthClass=$(if($maximum-lt240){'LT240'}elseif($maximum-lt260){'LT260'}else{'LONG'});permissions=(Get-TestValueIdentity $acl.Sddl);ownership=$acl.Owner;reparse='ABSENT_ON_ROOT_AND_ALL_DECLARED_INPUT_PATHS'}
  if($location.conditions.Count-ne6-or@($location.conditions.name|Select-Object -Unique).Count-ne6){throw 'TEST_LOCATION_CONDITIONS_DECLARATION'}
  foreach($condition in $location.conditions){if(-not$observed.ContainsKey($condition.name)-or$condition.value-cne'OBSERVE') {throw 'TEST_LOCATION_CONDITIONS_DECLARATION'};$condition.value=[string]$observed[$condition.name]}
 }
 if($context.targetKind-ceq'GIT_WORKTREE'-and'framework/versions/2.0.0/scripts/ExecutionTargetContext.psm1'-cnotin$sorted){throw 'TEST_EXECUTION_TARGET_OBSERVER_DEPENDENCY_REQUIRED'}
 $constructors=@(foreach($path in $Group.fixtureRecipe.constructorPaths){@{path=$path;identity=(Get-AiwTestFileIdentity (Join-Path $root $path))}})
 $facts=[ordered]@{root=$root;definitionIdentity=(Get-AiwTestFileIdentity $DefinitionPath);groupIdentity=(Get-AiwTestGroupBehaviorIdentity $Definition $Group);validatorIdentity=(Get-AiwTestFileIdentity $script:EvidenceModulePath);verifierIdentity=$loadedVerifier;inputs=$rows;unknownDependencies=@($Group.unknownDependencies);options=$Options;environment=$environment;commandArguments=@(Get-AiwTestGroupArguments $root $Group $Options);rootSensitive=$true;fixtureRecipeIdentity=(Get-TestValueIdentity @{recipe=$Group.fixtureRecipe;constructors=$constructors});environmentPolicy=$Group.environmentPolicy;locationPolicy=$location;executionContext=$context;nativeEnvironment=$native}
 if($Group.phase-ceq'POSTBUILD'){$facts.packageIdentity=Get-AiwTestFileIdentity $Options.PackagePath;$facts.packageTreeIdentity=Get-AiwReleaseValueIdentity @(Get-AiwReleaseTreeMembers $root);$facts.buildCommandIdentity=Get-AiwTestFileIdentity $Options.BuildCommandPath}
 if($Group.phase-ceq'PREPACKAGE'){$closure=Read-AiwTestJson (Join-Path $root 'source-inputs.json');if($closure.schemaVersion-ne2-or$closure.inputView-cne'SOURCE_PAYLOAD_V1'-or$closure.definitionIdentity-cne$facts.definitionIdentity){throw 'TEST_SOURCE_VIEW_BINDING'};$facts.inputView='SOURCE_PAYLOAD_V1';$facts.sourceInputsIdentity=Get-TestValueIdentity @(@($closure.inputs)+@($closure.syntheticInputs)|Where-Object{$paths.Contains($_.path)})}
 $wire=($facts|ConvertTo-Json -Depth 100 -Compress)|ConvertFrom-Json -Depth 100
 if($context.targetKind-ceq'GIT_WORKTREE'){
  if($context.targetObservation.observedUtc-isnot[string]){throw 'TEST_EXECUTION_TARGET_OBSERVATION_TIME_TOKEN'}
  $wire.executionContext.targetObservation.observedUtc=$context.targetObservation.observedUtc
 }
 $wire|Add-Member behaviorContractIdentity (Get-AiwEvidenceBehaviorIdentity $wire)
 return [pscustomobject]@{facts=$wire;identity=(Get-TestValueIdentity $wire)}
}
function Assert-AiwTestSourceViewReadClosure {
 # @design-contract framework/FRAMEWORK_RELEASE.md (actual P/T/D read closure)
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DefinitionPath,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)][string[]]$GroupIds,[ValidateSet('BeforeEnter','AfterConstruction','BeforeExport')][string]$Stage='BeforeEnter',[string]$ViewRoot)
 $source=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot));$vp='framework/versions/2.0.0/';$version=Join-Path $source $vp
 if($Definition.schemaVersion-notin@(2,3)){throw 'TEST_SOURCE_READ_DEFINITION_REQUIRED'}
 $current=Read-AiwTestGroupDefinition $DefinitionPath
 if((Get-TestValueIdentity $current)-cne(Get-TestValueIdentity $Definition)){throw 'TEST_SOURCE_READ_DEFINITION_DRIFT'}
 $facts=Get-AiwReleasePayloadFacts $version -SourceView;$tools=@(Get-AiwReleaseRuntimeToolPaths $version -Maintenance)
 $declared=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($path in $Definition.sourceViewPaths){Assert-TestLocator $path;if($path-ceq($vp+'RELEASE_MANIFEST.json')-or$path-cmatch'(^|/)\.git(/|$)'-or-not$declared.Add($path)){throw ('TEST_SOURCE_READ_DECLARATION|'+$path)}}
 $expected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($path in @($Definition.sourceViewPaths)+@($facts.Files|ForEach-Object{$vp+$_})){$null=$expected.Add($path)}
 $outside=@($expected|Where-Object{-not$_.StartsWith($vp,[StringComparison]::Ordinal)})
 $mainRoots=@(@($Definition.rootAdoptionPaths)+@($Definition.maintenancePaths)+@('README.md','LICENSE','framework/FRAMEWORK_RELEASE.md','.gitattributes','framework/ROADMAP.md','skills/ai-workspace-router/SKILL.md')|Select-Object -Unique)
 $selected=@();$resolvedTools=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($id in $GroupIds){
  $match=@($Definition.groups|Where-Object id -CEQ $id);if($match.Count-ne1-or$match[0].phase-cne'PREPACKAGE'){throw 'TEST_SOURCE_READ_GROUP'}
  $group=$match[0];$selected+=@($group);$requiredRoots=@();$requiredTools=@()
  # A same-ID finite child is not the actual main consumer.
  if($group.entry-ceq($vp+'tests/run-framework-tests.ps1')){
   $consumerArguments=@($group.arguments);$branches=@('MainIntegrationOnly','ToolContractOnly','SelectorOnly'|Where-Object{('-'+$_)-cin$consumerArguments})
   if('-InternalLegacyRun'-cnotin$consumerArguments-or$branches.Count-ne1-or$consumerArguments.Count-ne2){throw 'TEST_SOURCE_READ_CONSUMER_ARGUMENTS'}
   switch($branches[0]){
    'MainIntegrationOnly'{$requiredRoots=$mainRoots;$requiredTools=@('pwsh','git','powershell.exe')}
    'ToolContractOnly'{$requiredRoots=@('.gitattributes');$requiredTools=@('pwsh','git','powershell.exe')}
    'SelectorOnly'{$requiredTools=@('pwsh','git')}
   }
   }elseif($group.entry-cin@(($vp+'tests/integration-surface-tests.ps1'),($vp+'tests/integration-maintenance-tests.ps1'),($vp+'tests/integration-authorization-tests.ps1'),($vp+'tests/integration-process-tests.ps1'),($vp+'tests/integration-flow-tests.ps1'))){
    # Check the actual entry branch and private helper rather than trusting an ID.
    if(@($group.arguments).Count){throw 'TEST_SOURCE_READ_CONSUMER_ARGUMENTS'}
    $requiredRoots=@($mainRoots)+@($vp+'tests/IntegrationFixture.psm1')
    $requiredTools=if($group.entry-ceq($vp+'tests/integration-surface-tests.ps1')){@('pwsh','git','powershell.exe')}else{@('pwsh','git')}
   }elseif($group.entry-ceq($vp+'tests/release-validation-tests.ps1')){
   $consumerArguments=@($group.arguments);if($consumerArguments.Count-eq2-and$consumerArguments[0]-ceq'-Group'-and$consumerArguments[1]-cin@('ProofSchema','Mechanism')){$requiredRoots=$outside;$requiredTools=@('pwsh')}
  }
  foreach($path in $requiredRoots){if(-not$expected.Contains($path)){throw ('TEST_SOURCE_READ_REQUIRED_DECLARATION|'+$path)};if($path-cnotin$group.dependencies){throw ('TEST_SOURCE_READ_DEPENDENCY|'+$group.id+'|'+$path)}}
  foreach($tool in $requiredTools){if($tool-cnotin$group.tools){throw ('TEST_SOURCE_READ_TOOL|'+$group.id+'|'+$tool)}}
  foreach($tool in $group.tools){$null=$resolvedTools.Add($tool)}
  foreach($path in @($group.entry)+@($group.dependencies)){Assert-TestLocator $path;if($path-ceq($vp+'RELEASE_MANIFEST.json')){continue};if(-not$expected.Contains($path)){throw ('TEST_SOURCE_READ_UNDECLARED_DEPENDENCY|'+$group.id+'|'+$path)}}
 }
 # Root existence is a construction/freeze observation, not a persisted ledger.
 foreach($path in @('.github/workflows/framework-toolchain-conformance.yml','PACKAGE_MANIFEST.json')){if(Test-Path -LiteralPath (Assert-AiwTestPath (Join-Path $source $path))){throw ('TEST_SOURCE_READ_FORBIDDEN_ROOT|'+$path)}}
 foreach($path in @('AGENTS.md','CLAUDE.md','INITIALIZATION.md')){
  if(Test-Path -LiteralPath (Assert-AiwTestPath (Join-Path $source $path))){
   if(-not$expected.Contains($path)){throw ('TEST_SOURCE_READ_OPTIONAL_UNBOUND|'+$path)}
   foreach($group in $selected|Where-Object{($_.entry-ceq($vp+'tests/run-framework-tests.ps1')-and'-MainIntegrationOnly'-cin$_.arguments)-or$_.entry-ceq($vp+'tests/integration-surface-tests.ps1')}){if($path-cnotin$group.dependencies){throw ('TEST_SOURCE_READ_OPTIONAL_DEPENDENCY|'+$path)}}
  }
 }
 foreach($path in $expected){if(-not(Test-Path -LiteralPath (Assert-AiwTestPath (Join-Path $source $path)) -PathType Leaf)){throw ('TEST_SOURCE_READ_INPUT_MISSING|'+$path)}}
 $environment=Get-AiwTestEnvironment @($resolvedTools)
 if($Stage-cne'BeforeEnter'-and-not$ViewRoot){throw 'TEST_SOURCE_VIEW_REQUIRED'}
 if($ViewRoot){
  $view=Assert-AiwTestPath $ViewRoot
  foreach($path in @('.github/workflows/framework-toolchain-conformance.yml','PACKAGE_MANIFEST.json','.git')){if(Test-Path -LiteralPath (Assert-AiwTestPath (Join-Path $view $path))){throw ('TEST_SOURCE_VIEW_FORBIDDEN_ROOT|'+$path)}}
  foreach($path in @('AGENTS.md','CLAUDE.md','INITIALIZATION.md')){if((Test-Path -LiteralPath (Assert-AiwTestPath (Join-Path $source $path)))-ne(Test-Path -LiteralPath (Assert-AiwTestPath (Join-Path $view $path)))){throw ('TEST_SOURCE_VIEW_ROOT_PROJECTION|'+$path)}}
  $closure=Read-AiwTestJson (Join-Path $view 'source-inputs.json');Assert-TestFields $closure (@('schemaVersion','kind','inputView','sourceRoot','definitionIdentity','payloadCanonical','inputs','syntheticInputs')+$(if($closure.schemaVersion-eq2){@('recipeIdentity','locationPolicy')}else{@()})) 'source-read-closure'
  if($closure.schemaVersion-notin@(1,2)-or$closure.kind-cne'SOURCE_INPUT_CLOSURE'-or$closure.inputView-cne'SOURCE_PAYLOAD_V1'-or$closure.sourceRoot-cne$source-or$closure.definitionIdentity-cne(Get-AiwTestFileIdentity $DefinitionPath)-or$closure.payloadCanonical-cne$facts.Canonical){throw 'TEST_SOURCE_VIEW_BINDING'}
  $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($input in $closure.inputs){
   Assert-TestFields $input @('path','identity','logicalRole','distributionLocator') 'source-read-input';Assert-TestLocator $input.path
   if(-not$seen.Add($input.path)-or$input.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'TEST_SOURCE_VIEW_DUPLICATE_IDENTITY'}
   $role=if($input.path.StartsWith($vp,[StringComparison]::Ordinal)){'CURRENT_PAYLOAD'}elseif($input.path-cin$tools){'CURRENT_RUNTIME_TOOL'}else{'SOURCE_ONLY_BUILD_OR_TEST_INPUT'}
   if($input.logicalRole-cne$role){throw 'RELEASE_INPUT_ROLE_DOWNGRADE'}
   if($role-ceq'SOURCE_ONLY_BUILD_OR_TEST_INPUT'){if($null-ne$input.distributionLocator){throw 'RELEASE_SOURCE_ONLY_DISTRIBUTION_MAPPING'}}elseif($input.distributionLocator-cne$input.path){throw 'TEST_SOURCE_VIEW_DISTRIBUTION_MAPPING'}
   $to=Assert-AiwTestPath (Join-Path $view $input.path);if(-not(Test-Path -LiteralPath $to -PathType Leaf)){throw ('TEST_SOURCE_VIEW_INPUT_MISSING|'+$input.path)}
   if((Get-AiwTestFileIdentity $to)-cne$input.identity-or(Get-AiwTestFileIdentity (Join-Path $source $input.path))-cne$input.identity){throw ('TEST_SOURCE_VIEW_INPUT_DRIFT|'+$input.path)}
  }
  if(-not$seen.SetEquals($expected)){throw 'RELEASE_SOURCE_INPUT_SET'}
  if(@($closure.syntheticInputs).Count-ne1){throw 'TEST_SOURCE_VIEW_SYNTHETIC_SET'}
  $synthetic=$closure.syntheticInputs[0];Assert-TestFields $synthetic @('path','identity','logicalRole','distributionLocator','constructorIdentity') 'source-read-synthetic'
  if($synthetic.path-cne($vp+'RELEASE_MANIFEST.json')-or$synthetic.logicalRole-cne'SYNTHETIC_FIXTURE_INPUT'-or$null-ne$synthetic.distributionLocator-or$synthetic.constructorIdentity-cne(Get-AiwTestFileIdentity (Join-Path $view ($vp+'tests/TestHarness.psm1')))-or$synthetic.identity-cne(Get-AiwTestFileIdentity (Join-Path $view $synthetic.path))){throw 'RELEASE_SYNTHETIC_CONSTRUCTOR'}
  $actual=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($item in (Get-AiwTestFixtureSnapshot $view -IdentityOnly).Files){$null=$actual.Add($item.path)}
  $allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($path in $expected){$null=$allowed.Add($path)};$null=$allowed.Add($synthetic.path);$null=$allowed.Add('source-inputs.json')
  if(-not$actual.SetEquals($allowed)){throw 'TEST_SOURCE_VIEW_FILE_SET'}
 }
 return [pscustomobject]@{stage=$Stage;inputCount=$expected.Count;outsideVersionCount=$outside.Count;environment=$environment}
}
function Get-AiwTestObservedCases([string[]]$Output,[string]$GroupId){
 $counts=@{};$cases=@()
 foreach($line in $Output){
  if($line-cmatch'^PASS\|(.+)$'){
   $name=$Matches[1].Split('|')[0];if(-not$counts.ContainsKey($name)){$counts[$name]=0};$counts[$name]++
   # Repeated names are explicit parameter occurrences, never collapsed counts.
   $cases+=@{id=($GroupId+'/'+$name+'#'+$counts[$name].ToString('D4'));name=$name;occurrence=$counts[$name];outcome='PASS'}
  }
 }
 return @($cases)
}
function Get-AiwTestOmissions([string]$Stdout,[string]$Stderr,[string]$GroupId){return @(@($Stdout,$Stderr)|ForEach-Object{$_-split'\r?\n'}|Where-Object{$_-cmatch'^(SKIP|NOT_RUN|UNKNOWN)\|'-and-not($GroupId-cin@('integration.surface','integration.full-source')-and$_-ceq'NOT_RUN|historical-baseline-executable-regression|reason=retired-executable-suite-history-only')})}
function Assert-AiwTestRequestedOmissions([string[]]$Omissions,$Group,$Options){
 foreach($line in $Omissions){
  if($Group.id-cin@('integration.surface','integration.full-source')-and$line-ceq'NOT_RUN|historical-baseline-executable-regression|reason=retired-executable-suite-history-only'){continue}
  $allowed=$false
  foreach($pair in @(@('SkipManifest','SKIP|release-manifest-payload-validation|reason=SkipManifest'),@('SkipBaseline','SKIP|historical-baseline-executable-regression|reason=SkipBaseline'),@('SkipPerformanceSmoke','SKIP|process-budget-six-fixtures-replay-selected-pack|reason=SkipPerformanceSmoke'))){
   if($line-ceq$pair[1]-and$null-ne$Options.PSObject.Properties[$pair[0]]-and$Options.($pair[0])){$allowed=$true}
  }
  if(-not$allowed){throw 'TEST_SKIPPED_OR_UNKNOWN_COVERAGE'}
 }
}
function Get-AiwTestLocalArtifacts($Record,$Snapshot){
 $resultPath=Assert-AiwTestPath $Record.processResult.path
 if([IO.Path]::GetFileName($resultPath)-cne'result.json'-or(Get-AiwTestFileIdentity $resultPath)-cne$Record.processResult.identity){throw 'TEST_PROCESS_RESULT_DRIFT'}
 $process=Read-AiwTestJson $resultPath -StringFields @('startedUtc','endedUtc') -NullableStringFields @('creationUtc','processExitedUtc')
 $run=[IO.Path]::GetDirectoryName($resultPath)
 foreach($name in @('stdout','stderr')){if([IO.Path]::GetFullPath($process.$name.path)-cne(Join-Path $run ($name+'.raw'))){throw 'TEST_RAW_LOCATOR'}}
 $launch=Read-AiwTestJson (Join-Path $run 'launch.json') -StringFields @('startedUtc') -NullableStringFields @('creationUtc')
 $descriptor=$null;$currentDescriptor=$null
 foreach($pair in @(@($Record.executionContext,'original'),@($Snapshot.facts.executionContext,'current'))){$ctx=$pair[0];if($ctx.targetKind-ceq'GIT_WORKTREE'){$ref=$ctx.executionTargetRef;Assert-AiwEvidenceReference $ref 'execution-target-ref';$p=Assert-AiwTestPath $ref.path;if(-not$p.StartsWith($ctx.controlRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or(Get-AiwTestFileIdentity $p)-cne$ref.identity){throw 'TEST_EXECUTION_TARGET_REF_SCOPE'};if($pair[1]-ceq'original'){$descriptor=[IO.File]::ReadAllBytes($p)}else{$currentDescriptor=[IO.File]::ReadAllBytes($p)}}}
 return [pscustomobject]@{process=$process;launch=$launch;stdoutBytes=[IO.File]::ReadAllBytes($process.stdout.path);stderrBytes=[IO.File]::ReadAllBytes($process.stderr.path);phaseBytes=[IO.File]::ReadAllBytes((Join-Path $run 'phases.jsonl'));descriptorBytes=$descriptor;currentDescriptorBytes=$currentDescriptor}
}
function Assert-AiwTestGroupEvidence {
 param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)]$Group,[Parameter(Mandatory)]$CurrentSnapshot,[switch]$ForReuse,[switch]$AllowPartial)
 if($Record.schemaVersion-eq2){
  if($ForReuse-and($Group.alwaysFresh-or@($CurrentSnapshot.facts.unknownDependencies).Count)){throw 'TEST_FRESH_REQUIRED'}
  $artifacts=Get-AiwTestLocalArtifacts $Record $CurrentSnapshot
  $null=Assert-AiwEvidenceNativeRecord $Record $Group $CurrentSnapshot $artifacts -ForReuse:$ForReuse -AllowPartial:$AllowPartial
  if($Record.cleanup.root-isnot[string]){throw 'TEST_CLEANUP_ROOT'}
  if(Test-Path -LiteralPath (Assert-AiwTestPath $Record.cleanup.root)){if(@(Get-ChildItem -LiteralPath $Record.cleanup.root -Force).Count){throw 'TEST_RESET_CURRENTLY_DIRTY'}}
  return $true
 } Assert-TestFields $Record @('schemaVersion','executionKind','groupId','phase','before','after','processResult','startedUtc','endedUtc','outcome','cases','completion','cleanup','validatorIdentity','omissions') 'executed'
  if($Record.schemaVersion-ne1-or$Record.executionKind-cne'EXECUTED'-or$Record.groupId-cne$Group.id-or$Record.phase-cne$Group.phase){throw 'TEST_RECORD_BINDING'}
 if($Record.validatorIdentity-cne$CurrentSnapshot.facts.validatorIdentity){throw 'TEST_VALIDATOR_DRIFT'}
 if(($Record.outcome-cne'PASS'-and(-not$AllowPartial-or$ForReuse-or$Record.outcome-cne'PARTIAL'))-or$Record.before.identity-cne$Record.after.identity-or$Record.after.identity-cne$CurrentSnapshot.identity){throw 'TEST_RECORD_FAILED_PARTIAL_OR_INPUT_DRIFT'}
 if((Get-TestValueIdentity $Record.before.facts)-cne$Record.before.identity-or(Get-TestValueIdentity $Record.after.facts)-cne$Record.after.identity){throw 'TEST_SNAPSHOT_CORRUPT'}
 if([DateTime]::Parse($Record.endedUtc)-lt[DateTime]::Parse($Record.startedUtc)){throw 'TEST_RECORD_DATE_ORDER'}
 Assert-TestFields $Record.processResult @('path','identity') 'process-ref'
 $resultPath=Assert-AiwTestPath $Record.processResult.path
 if([IO.Path]::GetFileName($resultPath)-cne'result.json'){throw 'TEST_PROCESS_RESULT_LOCATOR'}
 if((Get-AiwTestFileIdentity $Record.processResult.path)-cne$Record.processResult.identity){throw 'TEST_PROCESS_RESULT_DRIFT'}
 $process=Read-AiwTestJson $Record.processResult.path
 if($process.status-cne'PASS'-or$process.exitCode-ne0-or$null-eq$process.exitCode-or[DateTime]::Parse($process.endedUtc)-lt[DateTime]::Parse($process.startedUtc)){throw 'TEST_PROCESS_NOT_PASS'}
 $runRoot=[IO.Path]::GetDirectoryName($resultPath)
 foreach($name in @('stdout','stderr')){$stream=$process.$name;Assert-TestFields $stream @('path','identity') 'raw-ref';if([IO.Path]::GetFullPath($stream.path)-cne(Join-Path $runRoot ($name+'.raw'))){throw 'TEST_RAW_LOCATOR'};if((Get-AiwTestFileIdentity $stream.path)-cne$stream.identity){throw 'TEST_RAW_CORRUPT'}}
 $pwsh=@($CurrentSnapshot.facts.environment.tools|Where-Object name -CEQ 'pwsh')
 if($pwsh.Count-ne1-or$process.command.cwd-cne$CurrentSnapshot.facts.root-or$process.command.executable-cne$pwsh[0].path-or$process.command.executableIdentity-cne$pwsh[0].identity-or$process.command.executableVersion-cne$pwsh[0].fileVersion-or(Get-TestValueIdentity @($process.command.arguments))-cne(Get-TestValueIdentity @($CurrentSnapshot.facts.commandArguments))){throw 'TEST_COMMAND_ENVIRONMENT_DRIFT'}
 $launch=Read-AiwTestJson (Join-Path $runRoot 'launch.json')
 if($launch.runId-cne$process.runId-or$launch.pid-ne$process.pid-or$launch.creationUtc-cne$process.creationUtc-or$launch.resultPath-cne$resultPath-or$launch.cwd-cne$process.command.cwd-or(Get-TestValueIdentity @($launch.arguments))-cne(Get-TestValueIdentity @($process.command.arguments))){throw 'TEST_LAUNCH_BINDING'}
 $stdout=[IO.File]::ReadAllText($process.stdout.path,[Text.UTF8Encoding]::new($false,$true));$stderr=[IO.File]::ReadAllText($process.stderr.path,[Text.UTF8Encoding]::new($false,$true))
 $omissions=@(Get-AiwTestOmissions $stdout $stderr $Group.id)
 if((Get-TestValueIdentity $omissions)-cne(Get-TestValueIdentity @($Record.omissions))-or($omissions.Count-and($Record.outcome-cne'PARTIAL'-or-not$AllowPartial-or$ForReuse))-or(-not$omissions.Count-and$Record.outcome-cne'PASS')){throw 'TEST_SKIPPED_OR_UNKNOWN_COVERAGE'}
 if($omissions.Count){Assert-AiwTestRequestedOmissions $omissions $Group $Record.after.facts.options}
 $observed=@(Get-AiwTestObservedCases @($stdout.TrimEnd([char]13,[char]10)-split'\r?\n') $Group.id)
 if((Get-TestValueIdentity $observed)-cne(Get-TestValueIdentity @($Record.cases))-or$observed.Count-eq0){throw 'TEST_CASE_RAW_MISMATCH'}
 $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($case in $Record.cases){if($case.outcome-cne'PASS'-or-not$ids.Add($case.id)){throw 'TEST_CASE_DUPLICATE_OR_FAILED'}}
 foreach($id in $Group.requiredCaseIds){if($id-cnotin@($Record.cases.name)){throw ('TEST_REQUIRED_CASE_MISSING|'+$id)}}
 $terminal=@($stdout-split'\r?\n'|Where-Object{$_-cmatch$Group.completionPattern})
 if($terminal.Count-ne1-or$Record.completion-cne$terminal[0]){throw 'TEST_GROUP_COMPLETION_MISSING_DUPLICATE'}
 Assert-TestFields $Record.cleanup @('status','root','entries','workers') 'cleanup'
 if($Record.cleanup.status-cne'CLEAN'-or@($Record.cleanup.entries).Count-or@($Record.cleanup.workers).Count){throw 'TEST_CLEANUP_DIRTY'}
 if(Test-Path -LiteralPath $Record.cleanup.root){if(@(Get-ChildItem -LiteralPath $Record.cleanup.root -Force).Count){throw 'TEST_RESET_CURRENTLY_DIRTY'}}
 if($ForReuse-and($Group.alwaysFresh-or@($CurrentSnapshot.facts.unknownDependencies).Count)){throw 'TEST_FRESH_REQUIRED'}
 return $true
}
function Complete-AiwTestGroupEvidence {
 param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Group,[Parameter(Mandatory)]$Before,[Parameter(Mandatory)]$After,[Parameter(Mandatory)]$Process,[Parameter(Mandatory)]$Cleanup)
 $terminal=@($Process.StdoutText-split'\r?\n'|Where-Object{$_-cmatch$Group.completionPattern});$cases=@(Get-AiwTestObservedCases $Process.Output $Group.id)
 $omissions=@(Get-AiwTestOmissions $Process.StdoutText $Process.StderrText $Group.id)
 $outcome=if($Process.Status-ceq'STOPPED'){'INTERRUPTED'}elseif($Process.Code-ne0){'FAIL'}elseif($Before.identity-cne$After.identity-or$terminal.Count-ne1-or$Cleanup.status-cne'CLEAN'){'INCOMPLETE'}elseif($omissions.Count){'PARTIAL'}else{'PASS'}
  $record=[ordered]@{schemaVersion=1;executionKind='EXECUTED';groupId=$Group.id;phase=$Group.phase;before=$Before;after=$After;processResult=@{path=$Process.ResultPath;identity=(Get-AiwTestFileIdentity $Process.ResultPath)};startedUtc=$Process.Record.startedUtc;endedUtc=$Process.Record.endedUtc;outcome=$outcome;cases=$cases;completion=$(if($terminal.Count-eq1){$terminal[0]}else{'MISSING'});cleanup=$Cleanup;validatorIdentity=$After.facts.validatorIdentity;omissions=$omissions}
 if($null-ne$After.facts.PSObject.Properties['behaviorContractIdentity']){
  $record.schemaVersion=2;$record.producer=@{name='TestGroupEvidence';contractVersion=2;moduleRef=@{path=$script:EvidenceModulePath;identity=$After.facts.validatorIdentity}};$record.executionContext=$After.facts.executionContext;$record.behaviorContractIdentity=$After.facts.behaviorContractIdentity
 }
 Write-AiwTestJson $Path $record
 return Read-AiwTestJson $Path -StringFields @('startedUtc','endedUtc')
}
function Select-AiwTestGroupExecution {
 param([Parameter(Mandatory)]$Group,[Parameter(Mandatory)]$CurrentSnapshot,[string[]]$ResumeEvidence=@(),[string]$RevalidationPath,[switch]$PlanOnly)
 if($null-ne$CurrentSnapshot.facts.PSObject.Properties['behaviorContractIdentity']-and$CurrentSnapshot.facts.verifierIdentity-cne(Get-AiwTestLoadedVerifierIdentity)){throw 'RELEASE_CURRENT_VERIFIER_BINDING'}
 if($Group.alwaysFresh-or@($CurrentSnapshot.facts.unknownDependencies).Count){return [pscustomobject]@{selection='EXECUTE';reason='FRESH_REQUIRED';original=$null}}
 $matches=@()
 foreach($path in $ResumeEvidence){$record=Read-AiwTestJson $path -StringFields @('startedUtc','endedUtc');if($record.groupId-ceq$Group.id){$matches+=@([pscustomobject]@{path=$path;record=$record})}}
 if($matches.Count-gt1){throw 'TEST_DUPLICATE_RESUME_GROUP'}
 if($matches.Count-eq0){return [pscustomobject]@{selection='EXECUTE';reason='NO_COMPLETE_ORIGINAL';original=$null}}
 if($null-ne$CurrentSnapshot.facts.PSObject.Properties['behaviorContractIdentity']-and$matches[0].record.schemaVersion-ne2){return [pscustomobject]@{selection='EXECUTE';reason='LEGACY_BEHAVIOR_FACTS_UNPROVEN';original=@{path=$matches[0].path;identity=(Get-AiwTestFileIdentity $matches[0].path)}}}
 try{$null=Assert-AiwTestGroupEvidence $matches[0].record $Group $CurrentSnapshot -ForReuse}catch{return [pscustomobject]@{selection='EXECUTE';reason=$_.Exception.Message;original=@{path=$matches[0].path;identity=(Get-AiwTestFileIdentity $matches[0].path)}}}
 $ref=@{path=$matches[0].path;identity=(Get-AiwTestFileIdentity $matches[0].path)}
 if($PlanOnly){return [pscustomobject]@{selection='REUSE_WITH_REVALIDATION';reason='EXACT_INPUTS_AND_ORIGINAL';original=$ref}}
 if([string]::IsNullOrWhiteSpace($RevalidationPath)){throw 'TEST_REVALIDATION_PATH_REQUIRED'}
 $rv=[ordered]@{schemaVersion=1;executionKind='REVALIDATED';groupId=$Group.id;original=$ref;currentSnapshot=$CurrentSnapshot;validatorIdentity=$CurrentSnapshot.facts.validatorIdentity;checkedUtc=[DateTime]::UtcNow.ToString('o');outcome='PASS';reason='Original execution, raw, cleanup, command and current complete closure verified'}
 if($matches[0].record.schemaVersion-eq2){$rv.schemaVersion=2;$rv.validatorIdentity=$CurrentSnapshot.facts.verifierIdentity;$rv.reason='Original native facts verified against current behavior contract';$rv.verifierRef=@{path='scripts/TestEvidenceValidation.psm1';identity=$CurrentSnapshot.facts.verifierIdentity};$rv.originalRecordSchemaVersion=2;$rv.verifiedBehaviorIdentity=$CurrentSnapshot.facts.behaviorContractIdentity;$rv.derivations=@()}
 if($rv.schemaVersion-eq2-and$rv.verifierRef.identity-cne(Get-AiwTestLoadedVerifierIdentity)){throw 'RELEASE_CURRENT_VERIFIER_BINDING'}
 Write-AiwTestJson $RevalidationPath $rv
 return [pscustomobject]@{selection='REUSE_WITH_REVALIDATION';reason='EXACT_INPUTS_AND_ORIGINAL';original=$ref;revalidation=@{path=$RevalidationPath;identity=(Get-AiwTestFileIdentity $RevalidationPath)}}
}
function Assert-AiwTestRevalidation($Validation,$Original,$Group,$CurrentSnapshot,$Suite,[switch]$CurrentCoverage){
 if($Suite.schemaVersion-eq3){if($Validation.schemaVersion-isnot[int]-and$Validation.schemaVersion-isnot[long]-or$Validation.schemaVersion-ne2){throw 'RELEASE_CURRENT_REVALIDATION_SCALAR'};Assert-AiwEvidenceRevalidation $Validation $Original $Group $CurrentSnapshot $Suite;return}
 if($Validation.schemaVersion-eq2){Assert-AiwEvidenceRevalidation $Validation $Original $Group $CurrentSnapshot $Suite;return}
 if($CurrentCoverage){Assert-AiwReleaseCurrentRevalidation $Validation $Original $Group $CurrentSnapshot $Suite;return}
 # Legacy Export/v1 retains its original local acceptance. The v1 release
 # reader separately enforces its original accepted FULL_RUN baseline branch.
 if($Validation.original.identity-cne$Original.identity-or$Validation.currentSnapshot.identity-cne$CurrentSnapshot.identity-or$Validation.validatorIdentity-cne$CurrentSnapshot.facts.validatorIdentity){throw 'TEST_REVALIDATION_DRIFT'}
}
function Assert-AiwTestSuiteEvidence {
 param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DefinitionPath,[switch]$AllowPartial,[switch]$CurrentCoverage)
 $suite=if($CurrentCoverage){Read-AiwTestJson $Path -StringFields @('startedUtc','endedUtc')}else{Read-AiwTestJson $Path}
 # Schema3 carries current coverage semantics through every public caller.
 if($suite.schemaVersion-eq3-and-not$CurrentCoverage){
  $suite=Read-AiwTestJson $Path -StringFields @('startedUtc','endedUtc')
  if($suite.phase-ceq'PREPACKAGE'){$CurrentCoverage=[Management.Automation.SwitchParameter]::new($true)}
 }
  $fields=@('schemaVersion','phase','definitionIdentity','requestedGroupIds','requiredGroupIds','records','outcome','coverage','options','startedUtc','endedUtc','qualification')
  if($suite.schemaVersion-in@(2,3)){$fields+=@('sourceRoot','sourceInputsRef');if($suite.phase-ceq'PREPACKAGE'){if((Get-AiwTestFileIdentity $suite.sourceInputsRef.path)-cne$suite.sourceInputsRef.identity){throw 'TEST_SUITE_SOURCE_INPUT_DRIFT'}};$SourceRoot=Assert-AiwTestPath $suite.sourceRoot;$DefinitionPath=Join-Path $SourceRoot 'framework/versions/2.0.0/tests/test-groups.json';$qualification=if($suite.phase-ceq'PREPACKAGE'){'SOURCE_VALIDATION_ONLY'}else{'PACKAGE_VALIDATION_ONLY'};if($suite.qualification-cne$qualification){throw 'TEST_SUITE_QUALIFICATION'}}
  if($suite.schemaVersion-eq3){$fields+='verifierRef'}
  Assert-TestFields $suite $fields 'suite'
  if($suite.schemaVersion-eq3){Assert-AiwEvidenceReference $suite.verifierRef 'suite-verifier';if($suite.verifierRef.path-cne'scripts/TestEvidenceValidation.psm1'-or$suite.verifierRef.identity-cne(Get-AiwTestLoadedVerifierIdentity)){throw 'RELEASE_CURRENT_VERIFIER_BINDING'}}
  if($suite.schemaVersion-notin@(1,2,3)-or$suite.phase-cnotin@('PREPACKAGE','POSTBUILD')-or$suite.definitionIdentity-cne(Get-AiwTestFileIdentity $DefinitionPath)-or($suite.outcome-cne'PASS'-and(-not$AllowPartial-or$suite.outcome-cne'PARTIAL'))-or($suite.schemaVersion-eq1-and$suite.qualification-cne'SCHEMA2_PENDING')){throw 'TEST_SUITE_NOT_COMPLETE'}
 $definition=Read-AiwTestGroupDefinition $DefinitionPath;$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $required=@($definition.groups|Where-Object{$_.phase-ceq$suite.phase-and'FULL'-cin$_.requiredFor}|ForEach-Object id)
 if($CurrentCoverage){Assert-AiwReleaseCurrentSuiteShape $suite (Get-AiwTestFileIdentity $DefinitionPath) $required -Complete:($suite.coverage-ceq'COMPLETE')}
 if((Get-TestValueIdentity @($suite.requiredGroupIds))-cne(Get-TestValueIdentity $required)){throw 'TEST_SUITE_REQUIRED_DEFINITION_DRIFT'}
 $requested=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($id in $suite.requestedGroupIds){if(-not$requested.Add($id)-or$id-cnotin@($definition.groups.id)){throw 'TEST_SUITE_DUPLICATE_UNKNOWN_GROUP'}}
 $complete=@($required|Where-Object{-not$requested.Contains($_)}).Count-eq0
 if($suite.coverage-cnotin@('COMPLETE','PARTIAL')-or($suite.coverage-ceq'COMPLETE'-and(-not$complete-or@($suite.options.PSObject.Properties|Where-Object{$_.Name-clike'Skip*'-and$_.Value}).Count))){throw 'TEST_SUITE_COVERAGE_OVERCLAIM'}
 foreach($ref in $suite.records){Assert-TestFields $ref @('groupId','path','identity','executionKind','revalidation') 'suite-ref';if(-not$seen.Add($ref.groupId)-or$ref.groupId-cnotin$suite.requestedGroupIds){throw 'TEST_SUITE_DUPLICATE_UNKNOWN_GROUP'}
  $groups=@($definition.groups|Where-Object id -CEQ $ref.groupId);if($groups.Count-ne1-or(Get-AiwTestFileIdentity $ref.path)-cne$ref.identity){throw 'TEST_SUITE_RECORD_BINDING'}
  $record=if($CurrentCoverage-or$suite.schemaVersion-eq3){Read-AiwTestJson $ref.path -StringFields @('startedUtc','endedUtc')}else{Read-AiwTestJson $ref.path}
  if(($suite.schemaVersion-eq3-and$record.schemaVersion-ne2)-or($suite.schemaVersion-ne3-and$record.schemaVersion-eq2)){throw 'TEST_EXECUTION_SUITE_VERSION_MISMATCH'}
  $native=@{}
  if($suite.schemaVersion-eq3){
   $observed=$record.after.facts.nativeEnvironment
   if($ref.executionKind-ceq'REVALIDATED'){$rvCurrent=Read-AiwTestJson $ref.revalidation.path -StringFields @('checkedUtc');$observed=$rvCurrent.currentSnapshot.facts.nativeEnvironment}
   foreach($property in $observed.PSObject.Properties){$native[$property.Name]=$property.Value}
  }
  $current=Get-AiwTestDependencySnapshot $SourceRoot $DefinitionPath $definition $groups[0] $suite.options -NativeEnvironment $native
  $null=Assert-AiwTestGroupEvidence $record $groups[0] $current -ForReuse:($ref.executionKind-ceq'REVALIDATED') -AllowPartial:$AllowPartial
  if(($CurrentCoverage-or$suite.schemaVersion-eq3)-and$record.schemaVersion-eq2-and$ref.executionKind-ceq'EXECUTED'){$null=Assert-AiwEvidenceNativeRecord $record $groups[0] $current (Get-AiwTestLocalArtifacts $record $current) -AllowPartial:$AllowPartial -Suite $suite}

  if($record.outcome-ceq'PARTIAL'-and($suite.outcome-cne'PARTIAL'-or$suite.coverage-cne'PARTIAL')){throw 'TEST_SUITE_COVERAGE_OVERCLAIM'}
  if($ref.executionKind-ceq'REVALIDATED'){if($CurrentCoverage-or$suite.schemaVersion-eq3){Assert-TestFields $ref.revalidation @('path','identity') 'revalidation-ref'};$validation=if($CurrentCoverage-or$suite.schemaVersion-eq3){Read-AiwTestJson $ref.revalidation.path -StringFields @('checkedUtc')}else{Read-AiwTestJson $ref.revalidation.path};if((Get-AiwTestFileIdentity $ref.revalidation.path)-cne$ref.revalidation.identity){throw 'TEST_REVALIDATION_DRIFT'};Assert-AiwTestRevalidation $validation $ref $groups[0] $current $suite -CurrentCoverage:$CurrentCoverage}elseif($ref.executionKind-cne'EXECUTED'-or($CurrentCoverage-and$null-ne$ref.revalidation)){throw 'TEST_EXECUTION_KIND_UNKNOWN'}
  if($CurrentCoverage-and$ref.executionKind-ceq'EXECUTED'-and$record.outcome-ceq'PASS'-and$record.schemaVersion-eq1){
   $process=Read-AiwTestJson $record.processResult.path -StringFields @('startedUtc','endedUtc') -NullableStringFields @('creationUtc','processExitedUtc')
   $launch=Read-AiwTestJson (Join-Path ([IO.Path]::GetDirectoryName($record.processResult.path)) 'launch.json') -StringFields @('startedUtc') -NullableStringFields @('creationUtc')
   Assert-AiwReleaseCurrentExecution $record $process $launch $groups[0] $suite
  }
 }
 if($seen.Count-ne@($suite.requestedGroupIds).Count){throw 'TEST_SUITE_REQUESTED_GROUP_MISSING'}
 if($suite.coverage-ceq'COMPLETE'){foreach($id in $required){if(-not$seen.Contains($id)){throw 'TEST_SUITE_REQUIRED_GROUP_MISSING'}}}
  return $suite
}
function Assert-AiwTestPrepackageProofRoute {
 param([ValidateSet(1,2,3)][int]$ProofSchemaVersion,[object[]]$Reused=@(),[string]$AcceptedBaselinePath,[string]$ExpectedAcceptedBaselineIdentity)
 $reused=@($Reused);if($ProofSchemaVersion-in@(2,3)){if($AcceptedBaselinePath-or$ExpectedAcceptedBaselineIdentity){throw "TEST_CURRENT_COVERAGE_BASELINE_FORBIDDEN"};return $null};if(-not$reused.Count){return $null}
  if(-not$AcceptedBaselinePath-or-not$ExpectedAcceptedBaselineIdentity-or(Get-AiwTestFileIdentity $AcceptedBaselinePath)-cne$ExpectedAcceptedBaselineIdentity){throw 'TEST_BUNDLE_ACCEPTED_BASELINE_REQUIRED'}
  $descriptor=Read-AiwTestJson $AcceptedBaselinePath
  Assert-TestFields $descriptor @('schemaVersion','kind','runtimeRoot','packageRef','postBuildRef','acceptanceRef','acceptedBy','proofBundleIdentity') 'accepted-baseline-input'
  if($descriptor.schemaVersion-ne1-or$descriptor.kind-cne'ACCEPTED_FULL_RUN_BASELINE_INPUT'){throw 'TEST_BUNDLE_BASELINE_SCHEMA'}
  foreach($ref in @($descriptor.packageRef,$descriptor.postBuildRef,$descriptor.acceptanceRef)){if((Get-AiwTestFileIdentity $ref.path)-cne$ref.identity){throw 'TEST_BUNDLE_BASELINE_INPUT_DRIFT'}}
  $qualified=Get-AiwReleaseQualification -VersionRoot (Join-Path $descriptor.runtimeRoot 'framework/versions/2.0.0') -RuntimeRoot $descriptor.runtimeRoot
  $baselinePackageFacts=Get-AiwReleasePackageFacts $descriptor.runtimeRoot;$null=Assert-AiwReleaseZipRuntime $descriptor.packageRef.path $descriptor.runtimeRoot
  if($qualified.Manifest.schemaVersion-ne3-or$qualified.Proof.Mode-cne'FULL_RUN'-or$qualified.Manifest.validationProof.proofBundleIdentity-cne$descriptor.proofBundleIdentity){throw 'TEST_BUNDLE_FULL_RUN_BASELINE_REQUIRED'}
  $post=Read-AiwTestJson $descriptor.postBuildRef.path;$accept=Read-AiwTestJson $descriptor.acceptanceRef.path
  if($post.phase-cne'POSTBUILD'-or$post.outcome-cne'PASS'-or$post.packageRef.identity-cne$descriptor.packageRef.identity-or$post.sourceManifestRef.identity-cne$qualified.ManifestIdentity-or$post.prepackageProofRef.identity-cne$qualified.Manifest.validationProof.proofBundleRef.identity-or$accept.schemaVersion-ne1-or$accept.outcome-cne'ACCEPTED'-or$accept.actor-cne$descriptor.acceptedBy-or@($accept.checks|Where-Object outcome -CNE PASS).Count){throw 'TEST_BUNDLE_ACCEPTED_BASELINE_BINDING'}
  if($accept.checks-isnot[Array]-or$accept.checks.Count-eq0-or$post.extractedTreeCanonical-cne$baselinePackageFacts.Canonical-or$post.packageManifestRef.identity-cne$baselinePackageFacts.ManifestIdentity){throw 'TEST_BUNDLE_BASELINE_PACKAGE_BINDING'}
  $baselineDefinition=Read-AiwTestGroupDefinition (Join-Path $descriptor.runtimeRoot 'framework/versions/2.0.0/tests/test-groups.json');$postRequired=@($baselineDefinition.groups|Where-Object{$_.phase-ceq'POSTBUILD'-and'FULL'-cin$_.requiredFor}|ForEach-Object id)
  if((Get-TestValueIdentity $postRequired)-cne(Get-TestValueIdentity @($post.requiredGroupIds))-or@($post.groupRecordRefs).Count-ne$postRequired.Count-or@($post.groupRecordRefs.groupId|Select-Object -Unique).Count-ne$postRequired.Count-or@($post.groupRecordRefs|Where-Object{$_.groupId-cnotin$postRequired-or$_.executionKind-cne'EXECUTED'}).Count){throw 'TEST_BUNDLE_BASELINE_POSTBUILD_COVERAGE'}
  foreach($ref in @($descriptor.packageRef,$descriptor.postBuildRef)){if(@($accept.candidateObjects|Where-Object{$_.path-ceq$ref.path-and$_.identity-ceq$ref.identity}).Count-ne1){throw 'TEST_BUNDLE_ACCEPTANCE_CANDIDATE_BINDING'}}
  $originalIds=@($qualified.Manifest.validationProof.groupRecordRefs.identity)
  foreach($ref in $reused){if($ref.identity-cnotin$originalIds){throw 'TEST_BUNDLE_REUSE_OUTSIDE_ACCEPTED_FULL_RUN'}}
  $baseline=@{schemaVersion=1;kind='ACCEPTED_FULL_RUN_BASELINE';mode='FULL_RUN';outcome='PASS';proofIdentity=$descriptor.proofBundleIdentity;acceptedProofIdentity=$descriptor.proofBundleIdentity;acceptanceRef=$descriptor.acceptanceRef;acceptedBy=$descriptor.acceptedBy;groupRecordIdentities=$originalIds;acceptanceBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($descriptor.acceptanceRef.path));acceptedPackageRef=$descriptor.packageRef;acceptedPostBuildRef=$descriptor.postBuildRef}

 return $baseline
}
function Export-AiwTestPrepackageBundle {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SuitePath,[Parameter(Mandatory)][string]$DestinationRoot,[string]$AcceptedBaselinePath,[string]$ExpectedAcceptedBaselineIdentity,[ValidateSet(1,2,3)][int]$ProofSchemaVersion=1)
 $suite=Read-AiwTestJson $SuitePath
 if($suite.schemaVersion-notin@(2,3)-or$suite.phase-cne'PREPACKAGE'-or$suite.outcome-cne'PASS'-or$suite.coverage-cne'COMPLETE'){throw 'TEST_BUNDLE_REQUIRES_COMPLETE_PREPACKAGE'}
 $definitionPath=Join-Path $suite.sourceRoot 'framework/versions/2.0.0/tests/test-groups.json'
 $definition=Read-AiwTestGroupDefinition $definitionPath
 if(($definition.schemaVersion-eq3-and($suite.schemaVersion-ne3-or$ProofSchemaVersion-ne3))-or($definition.schemaVersion-ne3-and($suite.schemaVersion-ne2-or$ProofSchemaVersion-eq3))){throw 'TEST_BUNDLE_VERSION_MISMATCH'}
 $suite=Assert-AiwTestSuiteEvidence $SuitePath $suite.sourceRoot $definitionPath -CurrentCoverage:($ProofSchemaVersion-in@(2,3))
 $reused=@($suite.records|Where-Object executionKind -CEQ REVALIDATED);$baseline=$null
 if($ProofSchemaVersion-in@(2,3)-and($AcceptedBaselinePath-or$ExpectedAcceptedBaselineIdentity)){throw 'TEST_CURRENT_COVERAGE_BASELINE_FORBIDDEN'}
 $baseline=Assert-AiwTestPrepackageProofRoute $ProofSchemaVersion $reused $AcceptedBaselinePath $ExpectedAcceptedBaselineIdentity
 $root=Assert-AiwTestPath $DestinationRoot;if(Test-Path -LiteralPath $root){throw 'TEST_BUNDLE_DESTINATION_EXISTS'}
 $members=[Collections.Generic.List[object]]::new();$aliases=[Collections.Generic.List[object]]::new();$bindings=[Collections.Generic.List[object]]::new();$refs=@();$revalidations=@();$baselineRef=$null
 function CopyBundleMember([string]$Id,[string]$Kind,[string]$Original){$identity=Get-AiwTestFileIdentity $Original;$relative='validation-evidence/prepackage/'+$Id+'.'+$(if($Kind-cin@('STDOUT','STDERR')){'raw'}elseif($Kind-ceq'PHASE_EVENTS'){'jsonl'}else{'json'});$path=Assert-AiwTestPath (Join-Path $root $relative);$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::Copy($Original,$path,$false);if((Get-AiwTestFileIdentity $path)-cne$identity){throw 'TEST_BUNDLE_COPY_DRIFT'};$member=@{id=$Id;kind=$Kind;path=$relative;identity=$identity};$members.Add($member);return $member}
 $closure=Read-AiwTestJson $suite.sourceInputsRef.path;$null=CopyBundleMember 'source-inputs' INPUT_CLOSURE $suite.sourceInputsRef.path
 $suiteMember=$null
 if($ProofSchemaVersion-in@(2,3)){$suiteMember=CopyBundleMember 'current-suite' CURRENT_SUITE $SuitePath;$aliases.Add(@{ownerMemberId=$suiteMember.id;slot='/sourceInputsRef';originalLocator=$suite.sourceInputsRef.path;originalIdentity=$suite.sourceInputsRef.identity;targetMemberId='source-inputs'})}
 $suiteOrdinal=0
 foreach($ref in $suite.records){
  $record=Read-AiwTestJson $ref.path;$id=$ref.groupId;$gm=CopyBundleMember ($id+'.executed') GROUP_RECORD $ref.path;$pm=CopyBundleMember ($id+'.process') PROCESS_RESULT $record.processResult.path
  $aliases.Add(@{ownerMemberId=$gm.id;slot='/processResult';originalLocator=$record.processResult.path;originalIdentity=$record.processResult.identity;targetMemberId=$pm.id})
  if($record.schemaVersion-eq2-and$record.executionContext.targetKind-ceq'GIT_WORKTREE'){$tm=CopyBundleMember ($id+'.target') EXECUTION_TARGET_DESCRIPTOR $record.executionContext.executionTargetRef.path;$aliases.Add(@{ownerMemberId=$gm.id;slot='/executionTargetRef';originalLocator=$record.executionContext.executionTargetRef.path;originalIdentity=$record.executionContext.executionTargetRef.identity;targetMemberId=$tm.id})}
  $process=Read-AiwTestJson $record.processResult.path
  foreach($name in @('stdout','stderr')){$raw=CopyBundleMember ($id+'.'+$name) $name.ToUpperInvariant() $process.$name.path;$aliases.Add(@{ownerMemberId=$pm.id;slot=('/'+$name);originalLocator=$process.$name.path;originalIdentity=$process.$name.identity;targetMemberId=$raw.id})}
  $runRoot=[IO.Path]::GetDirectoryName($record.processResult.path)
  foreach($extra in @(@{name='launch';kind='PROCESS_LAUNCH';slot='PROCESS_LAUNCH_FOR_RUN';file='launch.json'},@{name='phases';kind='PHASE_EVENTS';slot='PHASE_EVENTS_FOR_RUN';file='phases.jsonl'})){$original=Join-Path $runRoot $extra.file;$member=CopyBundleMember ($id+'.'+$extra.name) $extra.kind $original;$aliases.Add(@{ownerMemberId=$pm.id;slot=$extra.slot;originalLocator=$original;originalIdentity=$member.identity;targetMemberId=$member.id})}
  for($i=0;$i -lt @($record.after.facts.inputs).Count;$i++){$input=$record.after.facts.inputs[$i];$known=@(@($closure.inputs)+@($closure.syntheticInputs)|Where-Object path -CEQ $input.path);if($known.Count-ne1-or$known[0].identity-cne$input.identity){throw ('TEST_BUNDLE_UNDECLARED_INPUT|'+$input.path)};$bindings.Add(@{ownerMemberId=$gm.id;inputOrdinal=$i;logicalRole=$known[0].logicalRole;sourceRelativePath=$input.path;identity=$input.identity;distributionLocator=$known[0].distributionLocator;provenanceRef='source-inputs'})}
  $refs+=@{groupId=$id;path=$gm.path;identity=$gm.identity}
  if($suiteMember){$aliases.Add(@{ownerMemberId=$suiteMember.id;slot=('/records/'+$suiteOrdinal.ToString()+'/original');originalLocator=$ref.path;originalIdentity=$ref.identity;targetMemberId=$gm.id})}
  if($ref.executionKind-ceq'REVALIDATED'){$rv=Read-AiwTestJson $ref.revalidation.path;$rm=CopyBundleMember ($id+'.revalidated') REVALIDATION $ref.revalidation.path;$aliases.Add(@{ownerMemberId=$rm.id;slot='/original';originalLocator=$rv.original.path;originalIdentity=$rv.original.identity;targetMemberId=$gm.id});$revalidations+=@{path=$rm.path;identity=$rm.identity};if($suiteMember){$aliases.Add(@{ownerMemberId=$suiteMember.id;slot=('/records/'+$suiteOrdinal.ToString()+'/revalidation');originalLocator=$ref.revalidation.path;originalIdentity=$ref.revalidation.identity;targetMemberId=$rm.id})}}
  $suiteOrdinal++
 }
 if($baseline){$bp=Join-Path $root 'accepted-baseline.json';Write-AiwTestJson $bp $baseline;$bm=CopyBundleMember 'accepted-baseline' BASELINE_CLOSURE $bp;Remove-Item -LiteralPath $bp;$baselineRef=@{path=$bm.path;identity=$bm.identity}}
 $indexPath=Join-Path $root 'validation-evidence/prepackage/index.json';Write-AiwTestJson $indexPath @{schemaVersion=$(if($ProofSchemaVersion-eq3){2}else{1});kind='PREPACKAGE_EVIDENCE_BUNDLE';members=$members.ToArray();aliases=$aliases.ToArray();inputBindings=$bindings.ToArray();sourceInputClosureMemberId='source-inputs'}
 $indexRef=@{path='validation-evidence/prepackage/index.json';identity=(Get-AiwTestFileIdentity $indexPath)}
 $proof=[ordered]@{schemaVersion=1;phase='PREPACKAGE';mode=$(if($baseline){'VERIFIED_GROUP_COVERAGE'}else{'FULL_RUN'});status='PASS';currentPayloadCanonical=$closure.payloadCanonical;suiteDefinitionIdentity=$suite.definitionIdentity;proofBundleRef=$indexRef;proofBundleIdentity=(Get-AiwReleaseMemberFacts (@(@{path=$indexRef.path;identity=$indexRef.identity})+$members.ToArray())).Canonical;requiredGroupIds=@($suite.requiredGroupIds);groupRecordRefs=$refs;baselineRef=$baselineRef;revalidationRefs=$revalidations;prepackageIntegrationRefs=@($refs|Where-Object groupId -CEQ 'integration.full-source'|ForEach-Object{@{path=$_.path;identity=$_.identity}})}
 if($ProofSchemaVersion-in@(2,3)){$proof.schemaVersion=$ProofSchemaVersion;$proof.mode='CURRENT_GROUP_COVERAGE';$proof.currentSuiteRef=@{path=$suiteMember.path;identity=$suiteMember.identity};if($ProofSchemaVersion-eq3){if($suite.schemaVersion-ne3){throw 'TEST_PROOF3_SUITE3_REQUIRED'};$proof.verifierRef=$suite.verifierRef}}
 $proofPath=Join-Path $root 'validation-proof.json';Write-AiwTestJson $proofPath $proof
 return [pscustomobject]@{ProofPath=$proofPath;ProofIdentity=(Get-AiwTestFileIdentity $proofPath);BundleRoot=$root;Proof=$proof}
}
Export-ModuleMember -Function Read-AiwTestJson,Read-AiwTestGroupDefinition,Get-AiwTestGroupArguments,Get-AiwTestDependencySnapshot,Get-AiwTestEnvironment,Get-AiwTestObservedCases,Assert-AiwTestGroupEvidence,Complete-AiwTestGroupEvidence,Select-AiwTestGroupExecution,Assert-AiwTestPrepackageProofRoute,Assert-AiwTestSuiteEvidence,Export-AiwTestPrepackageBundle,Get-TestValueIdentity,Assert-AiwTestSourceViewReadClosure
