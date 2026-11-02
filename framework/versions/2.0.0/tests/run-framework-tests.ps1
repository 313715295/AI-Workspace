[CmdletBinding()]
param([switch]$SkipManifest,[switch]$SkipBaseline,[switch]$SkipPerformanceSmoke,[switch]$ToolContractOnly,[switch]$SelectorOnly,[switch]$MainIntegrationOnly,[ValidateSet('All','RuleSelection','SourceChangeRecovery','KnowledgeEnable')][string]$StandardPresetsGroup,[switch]$MaintenanceFixture,[string[]]$Groups=@(),[string[]]$ResumeEvidence=@(),[string]$EvidenceDirectory,[string]$SourceViewPath,[ValidateSet('PREPACKAGE','POSTBUILD')][string]$Phase='PREPACKAGE',[string]$PackagePath,[string]$BuildCommandPath,[string]$AcceptedBaselinePath,[string]$ExpectedAcceptedBaselineIdentity,[ValidateSet(1,2,3)][int]$ProofSchemaVersion=3,[switch]$InternalLegacyRun,[string]$ControlRoot,[string]$TaskPath,[string]$ExecutionTargetRef,[string]$ExpectedTargetState)

# Script-body boundary: keep the original script scope and PSBoundParameters.
$runnerPrimaryError=$null;$runnerPrimaryStage=$null;$runnerCleanupError=$null;$runnerFirstFailureChild=$null;$runnerStage='INITIALIZATION'
try {
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'POWERSHELL7_REQUIRED' }
$script:pwshExecutable=[Environment]::ProcessPath
if([string]::IsNullOrWhiteSpace($script:pwshExecutable)){throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE'}


Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
if(-not$InternalLegacyRun){
 if(-not$PSBoundParameters.ContainsKey('ProofSchemaVersion')-and($AcceptedBaselinePath-or$ExpectedAcceptedBaselineIdentity)){$ProofSchemaVersion=1} # Existing explicit v1 baseline calls, including the summary frontdoor.
 Import-Module (Join-Path $PSScriptRoot 'TestGroupEvidence.psm1')
 $releaseReader=Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru
 foreach($command in @('Get-AiwReleaseFileIdentity','Expand-AiwReleasePackage','Get-AiwReleaseQualification','Assert-AiwReleaseBuildEvidence','Get-AiwReleasePackageFacts')){if(-not$releaseReader.ExportedCommands.ContainsKey($command)-or$releaseReader.ExportedCommands[$command].Module.Path-cne$releaseReader.Path){throw ('RELEASE_READER_OWNER_COMMAND|'+$command)}}
  if($Phase-ceq'PREPACKAGE'-and$PackagePath){throw 'PREPACKAGE_CANNOT_READ_FINAL_PACKAGE'}
  if($Phase-ceq'POSTBUILD'-and-not$PackagePath){throw 'POSTBUILD_ACTUAL_PACKAGE_REQUIRED'}
 $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
 $isolatedRun=$ControlRoot-or$TaskPath-or$ExecutionTargetRef-or$ExpectedTargetState
 $targetOptions=@{}
 if($isolatedRun){
  if(-not($ControlRoot-and$TaskPath-and$ExecutionTargetRef-and$ExpectedTargetState)-or$Phase-cne'PREPACKAGE'-or$SourceViewPath){throw 'TEST_EXECUTION_TARGET_INPUT_COMBINATION'}
  Import-Module (Join-Path $PSScriptRoot '../scripts/StrictJsonInput.psm1')
  Import-Module (Join-Path $PSScriptRoot '../scripts/ExecutionTargetContext.psm1')
  $ref=(ConvertFrom-AiwStrictInputJson $ExecutionTargetRef).Value;$state=(ConvertFrom-AiwStrictInputJson $ExpectedTargetState).Value
  $cfg=Read-AiwTestJson (Join-Path $ControlRoot '.ai-workspace/project.json')
  $execution=Resolve-AiwExecutionTargetContext $ControlRoot $cfg.id $TaskPath $ref @($cfg.routineExcludedPaths)
  $null=Assert-AiwExecutionTargetState $execution $state
  if($execution.executionRoot-cne$root-or$execution.targetKind-cne'GIT_WORKTREE'){throw 'TEST_EXECUTION_TARGET_SOURCE_ROOT'}
  $targetOptions=@{ControlRoot=$execution.controlRoot;TaskPath=[IO.Path]::GetFullPath($TaskPath,$execution.controlRoot);ExecutionTargetRef=$execution.executionTargetRef;ExpectedTargetState=$state}
 }

 $definitionPath=Join-Path $PSScriptRoot 'test-groups.json';$definition=Read-AiwTestGroupDefinition $definitionPath
 if(-not$PSBoundParameters.ContainsKey('ProofSchemaVersion')-and-not($AcceptedBaselinePath-or$ExpectedAcceptedBaselineIdentity)){$ProofSchemaVersion=if($definition.schemaVersion-eq3){3}elseif($definition.schemaVersion-eq2){2}else{1}}
 if($Phase-ceq'PREPACKAGE'-and(($definition.schemaVersion-eq3-and$ProofSchemaVersion-ne3)-or($definition.schemaVersion-ne3-and$ProofSchemaVersion-eq3))){throw 'TEST_DEFINITION_PROOF_VERSION_MISMATCH'}
 $legacy=@(@('ToolContractOnly','SelectorOnly','MainIntegrationOnly','StandardPresetsGroup')|Where-Object{$PSBoundParameters.ContainsKey($_)-and[bool]$PSBoundParameters[$_]})
 if($legacy.Count-gt1-or($Groups.Count-and$legacy.Count)){throw 'TEST_GROUP_SCOPE_FLAGS_CONFLICT'}
 if($StandardPresetsGroup){
  if($SkipManifest-or$SkipBaseline-or$SkipPerformanceSmoke){throw 'STANDARD_PRESETS_SCOPE_FLAGS_CONFLICT'}
  $presets=@{'RuleSelection'='presets.rule-selection';'SourceChangeRecovery'='presets.source-change-recovery';'KnowledgeEnable'='presets.knowledge-enable'}
  $Groups=if($StandardPresetsGroup-ieq'All'){@('presets.rule-selection','presets.source-change-recovery','presets.knowledge-enable')}else{@($presets[$StandardPresetsGroup])}
 }elseif($MainIntegrationOnly){$Groups=@('integration.surface','integration.maintenance','integration.authorization','integration.process','integration.full-source')}elseif($ToolContractOnly){$Groups=@('integration.tool-contract')}elseif($SelectorOnly){$Groups=@('integration.selectors')}
  $required=@($definition.groups|Where-Object{$_.phase-ceq$Phase-and'FULL'-cin$_.requiredFor}|ForEach-Object id)
 if(-not$Groups.Count){$Groups=@($required)}else{$Groups=@($Groups|ForEach-Object{$_-split','})}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($id in $Groups){if(-not$seen.Add($id)-or$id-cnotin@($definition.groups|Where-Object phase -CEQ $Phase|ForEach-Object id)){throw ('TEST_UNKNOWN_DUPLICATE_OR_MIXED_PHASE_GROUP|'+$id)}}
 $fullPrepackage=$Phase-ceq'PREPACKAGE'-and$Groups.Count-eq$required.Count-and@($required|Where-Object{$_-cnotin$Groups}).Count-eq0
 $ResumeEvidence=@($ResumeEvidence|ForEach-Object{$_-split','})
 if($Phase-ceq'PREPACKAGE'-and$definition.schemaVersion-in@(2,3)){
  if($ProofSchemaVersion-in@(2,3)-and($AcceptedBaselinePath-or$ExpectedAcceptedBaselineIdentity)){throw 'TEST_CURRENT_COVERAGE_BASELINE_FORBIDDEN'}
  if($ResumeEvidence.Count-and-not$SourceViewPath){
   $resumeRoots=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
   foreach($resumePath in $ResumeEvidence){$original=Read-AiwTestJson $resumePath;if($original.executionKind-cne'EXECUTED'-or$original.after.facts.rootSensitive-isnot[bool]-or-not$original.after.facts.rootSensitive-or$original.after.facts.root-isnot[string]){throw 'TEST_RESUME_ORIGINAL_ROOT_REQUIRED'};$null=$resumeRoots.Add((Assert-AiwTestPath $original.after.facts.root))}
   if($resumeRoots.Count-ne1){throw 'TEST_RESUME_ROOT_AMBIGUOUS'};$SourceViewPath=@($resumeRoots)[0]
   if(-not(Test-Path -LiteralPath $SourceViewPath -PathType Container)-or-not(Test-Path -LiteralPath ($SourceViewPath+'.owner.json') -PathType Leaf)){throw 'TEST_RESUME_OWNED_ROOT_REQUIRED'}
  }
 }
 if($SourceViewPath-and($Phase-cne'PREPACKAGE'-or$definition.schemaVersion-notin@(2,3))){throw 'TEST_SOURCE_VIEW_PREPACKAGE_SCHEMA2_ONLY'}
 if($MaintenanceFixture-and@($Groups|Where-Object{$_-cnotlike'presets.*'}).Count){throw 'MAINTENANCE_FIXTURE_REQUIRES_PRESET_GROUPS'}
 if(-not$EvidenceDirectory){$EvidenceDirectory=Join-Path ([IO.Path]::GetTempPath()) ('aiw-framework-evidence-'+[guid]::NewGuid().ToString('N'))}
 $evidenceRoot=Assert-AiwTestPath $EvidenceDirectory
 if($evidenceRoot.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_EVIDENCE_MUST_BE_OUTSIDE_SOURCE'}
 if(Test-Path -LiteralPath $evidenceRoot){throw 'TEST_EVIDENCE_DIRECTORY_EXISTS'}
 $null=[IO.Directory]::CreateDirectory($evidenceRoot);$started=[DateTime]::UtcNow.ToString('o');$totalWatch=[Diagnostics.Stopwatch]::StartNew();$viewMilliseconds=0;$planMilliseconds=0;$revalidationMilliseconds=0;$affectedMilliseconds=0;$integrationMilliseconds=0;$newChildCount=0;$records=@();$outcome='PASS'
  $options=[ordered]@{SkipManifest=[bool]$SkipManifest;SkipBaseline=[bool]$SkipBaseline;SkipPerformanceSmoke=[bool]$SkipPerformanceSmoke;MaintenanceFixture=[bool]$MaintenanceFixture}
  foreach($name in $targetOptions.Keys){$options[$name]=$targetOptions[$name]}
  $sourceView=$null
  $sourceViewLease=$null
  $sourceReadRoot=$root;$sourceReadDefinitionPath=$definitionPath
  $runnerStage='SOURCE_VIEW_AND_EXECUTION'
  try{
  $packageInputs=$null
  if($isolatedRun){
   if($definition.schemaVersion-ne3){throw 'TEST_EXECUTION_TARGET_REQUIRES_SCHEMA3'}
   foreach($id in $Groups){$group=@($definition.groups|Where-Object id -CEQ $id)[0];if($group.locationPolicy.mode-cne'EXACT'){throw 'TEST_EXECUTION_TARGET_LOGICAL_ROOT_DENIED'}}
   $closure=Join-Path $root 'source-inputs.json'
   $sourceView=[pscustomobject]@{Root=$root;ClosurePath=$closure;ClosureIdentity=(Get-AiwTestFileIdentity $closure)}
  }elseif($Phase-ceq'PREPACKAGE'-and$definition.schemaVersion-in@(2,3)){
   $null=Assert-AiwTestSourceViewReadClosure $sourceReadRoot $sourceReadDefinitionPath $definition $Groups -Stage BeforeEnter
   $viewWatch=[Diagnostics.Stopwatch]::StartNew()
   if($SourceViewPath){$sourceViewLease=Enter-AiwTestSourceView -SourceRoot $root -DestinationRoot $SourceViewPath -Definition $definition -EvidenceRoot $evidenceRoot -ResumeEvidence $ResumeEvidence;$sourceView=$sourceViewLease.View}
   else{$sourceViewLease=Enter-AiwTestSourceView -SourceRoot $root -DestinationRoot (Join-Path $evidenceRoot 'source-view') -Definition $definition -EvidenceRoot (Join-Path $evidenceRoot 'group-evidence') -ResumeEvidence $ResumeEvidence;$sourceView=$sourceViewLease.View}
   $viewWatch.Stop();$viewMilliseconds=$viewWatch.Elapsed.TotalMilliseconds
   $null=Assert-AiwTestSourceViewReadClosure $sourceReadRoot $sourceReadDefinitionPath $definition $Groups -Stage AfterConstruction -ViewRoot $sourceView.Root
   $root=$sourceView.Root;$definitionPath=Join-Path $root 'framework/versions/2.0.0/tests/test-groups.json'
  }
  if($Phase-ceq'POSTBUILD'){
   if($legacy.Count-or$SkipManifest-or$SkipBaseline-or$SkipPerformanceSmoke-or$MaintenanceFixture-or$ResumeEvidence.Count-or-not$BuildCommandPath){throw 'POSTBUILD_FRESH_EXISTING_INPUTS_REQUIRED'}
   $PackagePath=Assert-AiwTestPath $PackagePath;$BuildCommandPath=Assert-AiwTestPath $BuildCommandPath
   $packageRef=@{path=$PackagePath;identity=(& $releaseReader.ExportedCommands['Get-AiwReleaseFileIdentity'] $PackagePath)};$buildRef=@{path=$BuildCommandPath;identity=(& $releaseReader.ExportedCommands['Get-AiwReleaseFileIdentity'] $BuildCommandPath)}
   $packageRoot=Join-Path $evidenceRoot 'package-view';$packageFacts=& $releaseReader.ExportedCommands['Expand-AiwReleasePackage'] $PackagePath $packageRoot
   $qualified=& $releaseReader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot (Join-Path $packageRoot 'framework/versions/2.0.0') -RuntimeRoot $packageRoot
   $null=& $releaseReader.ExportedCommands['Assert-AiwReleaseBuildEvidence'] $BuildCommandPath $PackagePath $packageFacts $qualified
   $currentSource=& $releaseReader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot (Join-Path $root 'framework/versions/2.0.0') -SourceRoot $root -AllowPending
   if($qualified.Manifest.schemaVersion-ne3-or$qualified.Facts.Canonical-cne$currentSource.Facts.Canonical){throw 'POSTBUILD_CURRENT_SOURCE_PAYLOAD_REQUIRED'}
   if((Get-AiwTestFileIdentity (Join-Path $packageRoot 'framework/versions/2.0.0/tests/test-groups.json'))-cne(Get-AiwTestFileIdentity $definitionPath)){throw 'POSTBUILD_CURRENT_DEFINITION_REQUIRED'}
   $root=$packageRoot;$definitionPath=Join-Path $root 'framework/versions/2.0.0/tests/test-groups.json';$definition=Read-AiwTestGroupDefinition $definitionPath
   $options.PackagePath=$PackagePath;$options.ExtractedPackagePath=$root;$options.BuildCommandPath=$BuildCommandPath
   $options.PackageIdentity=$packageRef.identity;$options.ExtractedTreeCanonical=$packageFacts.Canonical;$options.BuildCommandIdentity=$buildRef.identity
   $packageInputs=@{packageRef=$packageRef;packageManifestRef=@{path=(Join-Path $root 'PACKAGE_MANIFEST.json');identity=$packageFacts.ManifestIdentity};extractedTreeCanonical=$packageFacts.Canonical;sourceManifestRef=@{path=(Join-Path $root 'framework/versions/2.0.0/RELEASE_MANIFEST.json');identity=$qualified.ManifestIdentity};prepackageProofRef=@{path=(Join-Path $root ('framework/versions/2.0.0/'+$qualified.Manifest.validationProof.proofBundleRef.path));identity=$qualified.Manifest.validationProof.proofBundleRef.identity};buildCommandRef=$buildRef}
  }
 $nativeOverrides=@{};$nativeFixtures=@{}
 foreach($id in $Groups){
  $base=Assert-AiwTestPath ([IO.Path]::GetTempPath());$fixture=Assert-AiwTestPath (Join-Path $base ('g-'+[guid]::NewGuid().ToString('N').Substring(0,8)));$nativeFixtures[$id]=$fixture
  $nativeOverrides[$id]=@{TMP=$fixture;TEMP=$fixture;AIW_TEST_RAW_DIRECTORY=(Join-Path (Join-Path $evidenceRoot $id) 'raw');AIW_TEST_HOST='ISOLATED_GROUP';AIW_TEST_GROUP_ID=$id;AIW_TEST_SOURCE_VIEW=$(if($sourceView){'SOURCE_PAYLOAD_V1'}else{'LEGACY_SCHEMA2'})}
 }
  function Get-RunnerOriginalEnvironment($OriginalRef,$Group,$FreshEnvironment){
   if((Get-AiwTestFileIdentity $OriginalRef.path)-cne$OriginalRef.identity){throw 'TEST_PLAN_ORIGINAL_DRIFT'}
   $record=Read-AiwTestJson $OriginalRef.path -StringFields @('startedUtc','endedUtc')
   try{
    if($record.schemaVersion-ne2-or$record.executionKind-cne'EXECUTED'-or$record.groupId-cne$Group.id){return $null}
    $environment=@{}
    foreach($key in @('TMP','TEMP','AIW_TEST_RAW_DIRECTORY','AIW_TEST_HOST','AIW_TEST_GROUP_ID','AIW_TEST_SOURCE_VIEW')){
     $value=$record.after.facts.nativeEnvironment.PSObject.Properties[$key]
     if($null-eq$value-or$value.Value-isnot[string]-or[string]::IsNullOrWhiteSpace($value.Value)-or$record.before.facts.nativeEnvironment.$key-cne$value.Value){return $null}
     $environment[$key]=$value.Value
    }
    foreach($key in @('AIW_TEST_HOST','AIW_TEST_GROUP_ID','AIW_TEST_SOURCE_VIEW')){if($environment[$key]-cne$FreshEnvironment[$key]){return $null}}
    $rawRoot=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($record.processResult.path)))
    if($environment.TMP-cne$environment.TEMP-or$environment.TMP-cne$record.cleanup.root-or$environment.AIW_TEST_RAW_DIRECTORY-cne$rawRoot){return $null}
   }catch{return $null} # Malformed historical context cannot select a launch environment.
   if((Get-AiwTestFileIdentity $OriginalRef.path)-cne$OriginalRef.identity){throw 'TEST_PLAN_ORIGINAL_DRIFT'}
   return $environment
  }
  $selectionEnvironments=@{}
 $planWatch=[Diagnostics.Stopwatch]::StartNew();$executionPlan=@();$shortExit=@('publication.phase-evidence','non-git.preflight-ast')
 foreach($id in $Groups){
   $selectionEnvironments[$id]=$nativeOverrides[$id]
  $plannedGroup=@($definition.groups|Where-Object id -CEQ $id)[0];$snapshot=Get-AiwTestDependencySnapshot $root $definitionPath $definition $plannedGroup $options -NativeEnvironment $nativeOverrides[$id]
  $plannedChoice=Select-AiwTestGroupExecution $plannedGroup $snapshot $ResumeEvidence -PlanOnly
   # Historical comparison never changes the native launch map.
   if($definition.schemaVersion-eq3-and$plannedChoice.selection-ceq'EXECUTE'-and$plannedGroup.environmentPolicy.mode-cin@('EXACT','EFFECTIVE_TOOLS')-and$null-ne$plannedChoice.original){
    $originalRef=$plannedChoice.original;$historicalEnvironment=Get-RunnerOriginalEnvironment $originalRef $plannedGroup $nativeOverrides[$id]
    if($null-ne$historicalEnvironment){
     $historicalSnapshot=Get-AiwTestDependencySnapshot $root $definitionPath $definition $plannedGroup $options -NativeEnvironment $historicalEnvironment
     $historicalChoice=Select-AiwTestGroupExecution $plannedGroup $historicalSnapshot $ResumeEvidence -PlanOnly
     if($null-eq$historicalChoice.original-or$historicalChoice.original.path-cne$originalRef.path-or$historicalChoice.original.identity-cne$originalRef.identity){throw 'TEST_PLAN_ORIGINAL_DRIFT'}
     if($historicalChoice.selection-ceq'REUSE_WITH_REVALIDATION'){$snapshot=$historicalSnapshot;$plannedChoice=$historicalChoice;$selectionEnvironments[$id]=$historicalEnvironment}
     else{
      # A rejected historical execution falls back to newly observed launch facts.
      $snapshot=Get-AiwTestDependencySnapshot $root $definitionPath $definition $plannedGroup $options -NativeEnvironment $nativeOverrides[$id]
      $plannedChoice=Select-AiwTestGroupExecution $plannedGroup $snapshot $ResumeEvidence -PlanOnly
      if($null-eq$plannedChoice.original-or$plannedChoice.original.path-cne$originalRef.path-or$plannedChoice.original.identity-cne$originalRef.identity){throw 'TEST_PLAN_ORIGINAL_DRIFT'}
     }
    }
   }
  $priority=if($id-cin$shortExit){[Array]::IndexOf($shortExit,$id)}else{2}
  $executionPlan+=@{groupId=$id;selection=$plannedChoice.selection;reason=$plannedChoice.reason;priority=$priority;snapshotIdentity=$snapshot.identity;original=$plannedChoice.original}
 }
 if($fullPrepackage){$null=Assert-AiwTestPrepackageProofRoute $ProofSchemaVersion @($executionPlan|Where-Object selection -CEQ REUSE_WITH_REVALIDATION|ForEach-Object original) $AcceptedBaselinePath $ExpectedAcceptedBaselineIdentity}
 $executionPlan=@($executionPlan|Sort-Object priority -Stable);Write-AiwTestJson (Join-Path $evidenceRoot 'execution-plan.json') @{schemaVersion=1;phase=$Phase;proofSchemaVersion=$ProofSchemaVersion;sourceRoot=$root;groups=$executionPlan}
 $planWatch.Stop();$planMilliseconds=$planWatch.Elapsed.TotalMilliseconds
 foreach($planned in $executionPlan){Write-Output ('PLAN|'+$planned.groupId+'|'+$planned.selection+'|reason='+$planned.reason)}
 foreach($planned in $executionPlan){$id=$planned.groupId
  $group=@($definition.groups|Where-Object id -CEQ $id)[0];$groupRoot=Join-Path $evidenceRoot $id;$null=[IO.Directory]::CreateDirectory($groupRoot)
   $before=Get-AiwTestDependencySnapshot $root $definitionPath $definition $group $options -NativeEnvironment $selectionEnvironments[$id]
  if($before.identity-cne$planned.snapshotIdentity){throw 'TEST_PLAN_CURRENT_INPUT_DRIFT'}
  $choiceWatch=[Diagnostics.Stopwatch]::StartNew()
  $choice=Select-AiwTestGroupExecution $group $before $ResumeEvidence (Join-Path $groupRoot 'revalidation.json')
  $choiceWatch.Stop();$revalidationMilliseconds+=$choiceWatch.Elapsed.TotalMilliseconds
  if($choice.selection-cne$planned.selection-or$choice.reason-cne$planned.reason){throw 'TEST_PLAN_SELECTION_DRIFT'}
   if($null-ne$planned.original){if($null-eq$choice.original-or$choice.original.path-cne$planned.original.path-or$choice.original.identity-cne$planned.original.identity){throw 'TEST_PLAN_ORIGINAL_DRIFT'}}elseif($null-ne$choice.original){throw 'TEST_PLAN_ORIGINAL_DRIFT'}
  if($choice.selection-ceq'REUSE_WITH_REVALIDATION'){
   $records+=@{groupId=$id;path=$choice.original.path;identity=$choice.original.identity;executionKind='REVALIDATED';revalidation=$choice.revalidation}
   Write-Output ('GROUP|'+$id+'|REVALIDATED|'+$choice.original.path);continue
  }
  # Keep native cwd below Windows' path limit; durable raw stays in groupRoot.
  $tempBase=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath ([IO.Path]::GetTempPath())))
  $fixtureRoot=$nativeFixtures[$id];if(Test-Path -LiteralPath $fixtureRoot){throw 'TEST_NATIVE_FIXTURE_EXISTS'};$null=[IO.Directory]::CreateDirectory($fixtureRoot)
  Write-Output ('GROUP|'+$id+'|START|reason='+$choice.reason+'|utc='+[DateTime]::UtcNow.ToString('o'))
  $childEnvironment=$nativeOverrides[$id]
  $newChildCount++;$process=Invoke-AiwTestProcess -Executable $script:pwshExecutable -Arguments @(Get-AiwTestGroupArguments $root $group $options) -WorkingDirectory $root -Environment $childEnvironment -EvidenceDirectory (Join-Path $groupRoot 'raw') -GroupId $id -EvidenceContractVersion $(if($definition.schemaVersion-eq3){2}else{1})
   if($process.Code-ne0-and$null-eq$runnerFirstFailureChild){$runnerFirstFailureChild=@{groupId=$id;code=$process.Code;result=@{path=$process.ResultPath;identity=(Get-AiwTestFileIdentity $process.ResultPath)};stdout=$process.Record.stdout;stderr=$process.Record.stderr}}
  if($id.StartsWith('integration.',[StringComparison]::Ordinal)){$integrationMilliseconds+=$process.Record.timing.wallMilliseconds}else{$affectedMilliseconds+=$process.Record.timing.wallMilliseconds}
  foreach($line in $process.Output){Write-Output $line}
  $after=Get-AiwTestDependencySnapshot $root $definitionPath $definition $group $options -NativeEnvironment $nativeOverrides[$id]
  # The root was allocated empty by this invocation, then passed only to this child.
  # The native producer writes completion only after actual exit and stream drain.
  # The raw reader binds run/PID/creation; a later same-number process is unrelated.
  $workerStates=@(Get-AiwTestRawProcessStates (Join-Path $groupRoot 'raw'));$workers=@($workerStates|Where-Object state -CNE 'COMPLETE');$cleanupBlocked=$false
  foreach($worker in $workers){Write-Output ('GROUP_WORKER_UNFINISHED|'+$id+'|'+$worker.runId+'|'+$worker.state)}
  try{
   $null=Assert-AiwTestPath $fixtureRoot
   if($fixtureRoot-cne$nativeFixtures[$id]-or[IO.Path]::GetDirectoryName($fixtureRoot)-cne$tempBase){throw 'GROUP_FIXTURE_CLEANUP_SCOPE'}
   $ownedComplete=$childEnvironment.TMP-ceq$fixtureRoot-and$childEnvironment.TEMP-ceq$fixtureRoot-and$definition.schemaVersion-eq3-and$before.identity-ceq$after.identity-and$process.Status-cin@('PASS','FAIL')-and$process.Record.schemaVersion-eq2-and$process.Record.environment.TMP-ceq$fixtureRoot-and$process.Record.environment.TEMP-ceq$fixtureRoot-and$process.Record.environment.AIW_TEST_RAW_DIRECTORY-ceq$childEnvironment.AIW_TEST_RAW_DIRECTORY-and$workerStates.Count-gt0-and$workers.Count-eq0
   if($ownedComplete){
    foreach($item in @(Get-ChildItem -LiteralPath $fixtureRoot -Force)){
     if(-not$item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){continue}
     $path=Assert-AiwTestPath $item.FullName
     if([IO.Path]::GetDirectoryName($path)-cne$fixtureRoot){throw 'GROUP_EMPTY_DIRECTORY_SCOPE'}
     if(@([IO.Directory]::EnumerateFileSystemEntries($path)).Count-eq0){
      [IO.Directory]::Delete($path,$false)
      if(Test-Path -LiteralPath $path){throw 'GROUP_EMPTY_DIRECTORY_DISPOSAL_INCOMPLETE'}
      Write-Output ('GROUP_EMPTY_DIRECTORY_REMOVED|'+$id+'|'+$path)
     }
    }
   }
  }catch{$cleanupBlocked=$true;Write-Output ('GROUP_FIXTURE_CLEANUP_FAILED|'+$id+'|'+$_.Exception.Message)}
  $entries=@(Get-ChildItem -LiteralPath $fixtureRoot -Force|ForEach-Object FullName)
  $cleanup=@{status=$(if($entries.Count-or$workers.Count-or$cleanupBlocked){'DIRTY'}else{'CLEAN'});root=$fixtureRoot;entries=$entries;workers=$workers}
  if($cleanup.status-ceq'CLEAN'){
   try{[IO.Directory]::Delete($fixtureRoot,$false);if(Test-Path -LiteralPath $fixtureRoot){throw 'GROUP_FIXTURE_DISPOSAL_INCOMPLETE'}}catch{$cleanup.status='DIRTY';Write-Output ('GROUP_FIXTURE_CLEANUP_FAILED|'+$id+'|'+$_.Exception.Message)}
  }
  $path=Join-Path $groupRoot 'executed.json';$record=Complete-AiwTestGroupEvidence $path $group $before $after $process $cleanup
  $records+=@{groupId=$id;path=$path;identity=(Get-AiwTestFileIdentity $path);executionKind='EXECUTED';revalidation=$null}
  try{$null=Assert-AiwTestGroupEvidence $record $group $after -AllowPartial}catch{Write-Output ('GROUP_INVALID|'+$id+'|'+$_.Exception.Message);$outcome=if($record.outcome-ceq'PASS'-or($fullPrepackage-and$id-ceq'release.prepackage-readers'-and$record.outcome-ceq'PARTIAL')){'INCOMPLETE'}else{$record.outcome};break}
  if($record.outcome-ceq'PARTIAL'){$outcome=if($fullPrepackage-and$id-ceq'release.prepackage-readers'){'INCOMPLETE'}else{'PARTIAL'}}
  Write-Output ('GROUP|'+$id+'|END|outcome='+$record.outcome+'|wallMs='+$process.Record.timing.wallMilliseconds+'|record='+$path)
  if($fullPrepackage-and$id-ceq'release.prepackage-readers'-and$record.outcome-cne'PASS'){break}
 }
 $coverage=if($outcome-ceq'PASS'-and@($required|Where-Object{$_-cnotin$Groups}).Count-eq0-and-not($SkipManifest-or$SkipBaseline-or$SkipPerformanceSmoke)){'COMPLETE'}else{'PARTIAL'}
 if($Phase-ceq'POSTBUILD'-and((& $releaseReader.ExportedCommands['Get-AiwReleaseFileIdentity'] $PackagePath)-cne$packageInputs.packageRef.identity-or(& $releaseReader.ExportedCommands['Get-AiwReleasePackageFacts'] $root).Canonical-cne$packageInputs.extractedTreeCanonical-or(& $releaseReader.ExportedCommands['Get-AiwReleaseFileIdentity'] $BuildCommandPath)-cne$packageInputs.buildCommandRef.identity)){$outcome='INCOMPLETE';$coverage='PARTIAL'}
 if($sourceView){$null=Assert-AiwTestSourceViewReadClosure $sourceReadRoot $sourceReadDefinitionPath $definition $Groups -Stage BeforeExport -ViewRoot $sourceView.Root}
 $suitePath=Join-Path $evidenceRoot 'suite.json'
  $suiteValue=[ordered]@{schemaVersion=1;phase=$Phase;definitionIdentity=(Get-AiwTestFileIdentity $definitionPath);requestedGroupIds=@($Groups);requiredGroupIds=$required;records=$records;outcome=$outcome;coverage=$coverage;options=$options;startedUtc=$started;endedUtc=[DateTime]::UtcNow.ToString('o');qualification='SCHEMA2_PENDING'}
  if($definition.schemaVersion-in@(2,3)){$suiteValue.schemaVersion=2;$suiteValue.qualification=$(if($Phase-ceq'PREPACKAGE'){'SOURCE_VALIDATION_ONLY'}else{'PACKAGE_VALIDATION_ONLY'});$suiteValue.sourceRoot=$root;$suiteValue.sourceInputsRef=$(if($sourceView){@{path=$sourceView.ClosurePath;identity=$sourceView.ClosureIdentity}}else{$null})}
  if($definition.schemaVersion-eq3){$suiteValue.schemaVersion=3;$suiteValue.verifierRef=@{path='scripts/TestEvidenceValidation.psm1';identity=(Get-AiwTestFileIdentity (Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1'))}}
  Write-AiwTestJson $suitePath $suiteValue
  $suiteCreatedIdentity=Get-AiwTestFileIdentity $suitePath
 if($outcome-cin@('PASS','PARTIAL')){try{$null=Assert-AiwTestSuiteEvidence $suitePath $root $definitionPath -AllowPartial -CurrentCoverage:($Phase-ceq'PREPACKAGE'-and$definition.schemaVersion-in@(2,3)-and$ProofSchemaVersion-in@(2,3))}catch{Write-Output ('SUITE_INVALID|'+$_.Exception.Message);$outcome='INCOMPLETE';$coverage='PARTIAL';$suiteValue.outcome=$outcome;$suiteValue.coverage=$coverage;if((Get-AiwTestFileIdentity $suitePath)-cne$suiteCreatedIdentity){throw 'TEST_SUITE_UNPUBLISHED_DRIFT'};$suiteReplacementPath=$suitePath+'.finalizing-'+[guid]::NewGuid().ToString('N')+'.json';try{Write-AiwTestJson $suiteReplacementPath $suiteValue;[IO.File]::Move($suiteReplacementPath,$suitePath,$true)}finally{if([IO.File]::Exists($suiteReplacementPath)){[IO.File]::Delete($suiteReplacementPath)}}}}
 Write-Output ('SUITE_EVIDENCE|path='+$suitePath+'|identity='+(Get-AiwTestFileIdentity $suitePath))
  if($Phase-ceq'PREPACKAGE'-and$definition.schemaVersion-in@(2,3)-and$outcome-ceq'PASS'-and$coverage-ceq'COMPLETE'){$bundle=Export-AiwTestPrepackageBundle $suitePath (Join-Path $evidenceRoot 'prepackage-proof') -AcceptedBaselinePath $AcceptedBaselinePath -ExpectedAcceptedBaselineIdentity $ExpectedAcceptedBaselineIdentity -ProofSchemaVersion $ProofSchemaVersion;Write-Output ('PREPACKAGE_PROOF|path='+$bundle.ProofPath+'|identity='+$bundle.ProofIdentity)}
  if($Phase-ceq'POSTBUILD'){
   $post=[ordered]@{schemaVersion=1;phase='POSTBUILD';packageRef=$packageInputs.packageRef;packageManifestRef=$packageInputs.packageManifestRef;extractedTreeCanonical=$packageInputs.extractedTreeCanonical;sourceManifestRef=$packageInputs.sourceManifestRef;prepackageProofRef=$packageInputs.prepackageProofRef;buildCommandRef=$packageInputs.buildCommandRef;postBuildDefinitionIdentity=(Get-AiwTestFileIdentity $definitionPath);requiredGroupIds=$required;groupRecordRefs=$records;runtime=(Get-AiwTestEnvironment);options=$options;outcome=$(if($outcome-ceq'PASS'-and$coverage-ceq'COMPLETE'){'PASS'}else{$outcome});rawRefs=@($records|ForEach-Object{(Read-AiwTestJson $_.path).processResult})}
   if($coverage-cne'COMPLETE'-and$post.outcome-ceq'PASS'){$post.outcome='INCOMPLETE'}
   $postPath=Join-Path $evidenceRoot 'postbuild-proof.json';Write-AiwTestJson $postPath $post;Write-Output ('POSTBUILD_PROOF|path='+$postPath+'|identity='+(Get-AiwTestFileIdentity $postPath))
  }
  Write-Output ('RESULT|outcome='+$outcome+'|coverage='+$coverage+'|phase='+$Phase+'|qualification='+$suiteValue.qualification)
 $totalWatch.Stop();Write-AiwTestJson (Join-Path $evidenceRoot 'execution-cost.json') @{schemaVersion=1;sourceViewMilliseconds=$viewMilliseconds;preflightMilliseconds=$planMilliseconds;revalidationMilliseconds=$revalidationMilliseconds;affectedNativeMilliseconds=$affectedMilliseconds;integrationNativeMilliseconds=$integrationMilliseconds;totalMilliseconds=$totalWatch.Elapsed.TotalMilliseconds;newGroupChildCount=$newChildCount;timingSemantics='Native group times include their nested work; total also includes view, planning, record validation and export. Do not add overlapping parent/child timings.'}
  }catch{$runnerPrimaryError=$_;$runnerPrimaryStage=$runnerStage;throw}finally{
   try{$runnerStage='OWNED_LEASE_CLEANUP';if($sourceViewLease){$sourceViewLease.Lease.Dispose()}}
   catch{$runnerCleanupError=$_;if($null-eq$runnerPrimaryError){throw}}
  }
  if($outcome-cnotin@('PASS','PARTIAL')){exit 1};return
}

if($PSBoundParameters.ContainsKey('StandardPresetsGroup')){
 $StandardPresetsGroup=@('All','RuleSelection','SourceChangeRecovery','KnowledgeEnable')|Where-Object{$_-ieq$StandardPresetsGroup}
 if($SkipManifest-or$SkipBaseline-or$SkipPerformanceSmoke-or$ToolContractOnly-or$SelectorOnly-or$MainIntegrationOnly){throw 'STANDARD_PRESETS_SCOPE_FLAGS_CONFLICT'}
 $entry=Join-Path $PSScriptRoot 'standard-presets-tests.ps1';$arguments=@('-NoProfile','-NonInteractive','-File',$entry,'-Group',$StandardPresetsGroup)
 if($MaintenanceFixture){$arguments+='-MaintenanceFixture'}
 $timer=[Diagnostics.Stopwatch]::StartNew();$output=@(& $script:pwshExecutable @arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE;$timer.Stop()
 foreach($line in $output){Write-Output $line}
 Write-Output ('TIMING|END|group=standard-presets-'+$StandardPresetsGroup+'|elapsedMs='+$timer.ElapsedMilliseconds+'|exitCode='+$code)
 if($code-ne0){exit $code}
 $result=@($output|Where-Object{$_-cmatch'^STANDARD_PRESETS_TESTS_PASS\|checks=(\d+)\|'})
 if($result.Count-lt1){throw 'STANDARD_PRESETS_RESULT_REQUIRED'}
 $count=[int]([regex]::Match($result[-1],'^STANDARD_PRESETS_TESTS_PASS\|checks=(\d+)\|').Groups[1].Value)
 Write-Output 'NOT_RUN|other-framework-suites|reason=StandardPresetsGroup'
 Write-Output ('RESULT|'+$count+'/'+$count+' passed|scope=Framework-2.0.0-standard-presets-'+$StandardPresetsGroup+'|layout='+$(if($MaintenanceFixture){'Maintenance'}else{'Ordinary'}))
 return
}
# Compatibility selectors delegate to the same Source cases used by D.
$legacyEntries=if($ToolContractOnly-or$SelectorOnly){@('surface')}else{@('surface','maintenance','authorization','process','flow')}
foreach($domain in $legacyEntries){
 $argsForDomain=@('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot ('integration-'+$domain+'-tests.ps1')))
 if($domain-ceq'surface'){if($ToolContractOnly){$argsForDomain+='-ToolContractOnly'};if($SelectorOnly){$argsForDomain+='-SelectorOnly'};if($SkipManifest){$argsForDomain+='-SkipManifest'};if($SkipBaseline){$argsForDomain+='-SkipBaseline'}}
 $child=Invoke-AiwTestProcess $script:pwshExecutable $argsForDomain -WorkingDirectory (Get-Location).Path
 $child.Output|Write-Output
 if($child.Code-ne0){exit $child.Code}
}
if($MainIntegrationOnly){Write-Output 'RESULT|all domain children complete|scope=Framework-2.0.0-main-integration-only|'}

}catch{
 $failure=if($null-ne$runnerPrimaryError){$runnerPrimaryError}else{$_}
 $errorEnvelope=[ordered]@{kind='PUBLIC_RUNNER_FAILURE';status='FAIL';stage=$(if($null-ne$runnerPrimaryStage){$runnerPrimaryStage}else{$runnerStage});reason=[string]$failure.Exception.Message;exceptionType=$failure.Exception.GetType().FullName;scriptStackTrace=[string]$failure.ScriptStackTrace;fullyQualifiedErrorId=[string]$failure.FullyQualifiedErrorId;position=[string]$failure.InvocationInfo.PositionMessage;firstFailureChild=$runnerFirstFailureChild;cleanupError=$null}
 if($null-ne$runnerCleanupError){$errorEnvelope.cleanupError=[ordered]@{reason=[string]$runnerCleanupError.Exception.Message;scriptStackTrace=[string]$runnerCleanupError.ScriptStackTrace;fullyQualifiedErrorId=[string]$runnerCleanupError.FullyQualifiedErrorId}}
 [Console]::Error.WriteLine(($errorEnvelope|ConvertTo-Json -Depth 30 -Compress -EscapeHandling EscapeNonAscii))
 exit 1
}
