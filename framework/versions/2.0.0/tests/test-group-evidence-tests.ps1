[CmdletBinding()]
param([ValidateSet('All','Core','CurrentCoverage','FinalSuiteAndOwnership')][string]$Group='All',[string]$V1ReaderPath,[switch]$FixtureContractOnly,[switch]$PublicSuiteConsumerContractOnly,[switch]$FocusedReviewRepairOnly,[switch]$ToolResolutionContractOnly,[switch]$IntegrationConsumerContractOnly,[string]$GuardFixturePath,[switch]$ExecutionTargetOnly,[switch]$FailureTransportOnly,[switch]$WorkerCompletionOnly)
$ErrorActionPreference='Stop'
$groupEvidenceFirstFailure=$null;$groupEvidenceCleanupFailure=$null
try {
Set-StrictMode -Version Latest
if($WorkerCompletionOnly-and($Group-cne'CurrentCoverage'-or$FixtureContractOnly-or$PublicSuiteConsumerContractOnly-or$FocusedReviewRepairOnly-or$ToolResolutionContractOnly-or$IntegrationConsumerContractOnly-or$GuardFixturePath-or$ExecutionTargetOnly-or$FailureTransportOnly)){throw 'WORKER_COMPLETION_FLAGS'}
if($FailureTransportOnly-and($Group-cne'CurrentCoverage'-or$FixtureContractOnly-or$PublicSuiteConsumerContractOnly-or$FocusedReviewRepairOnly-or$ToolResolutionContractOnly-or$IntegrationConsumerContractOnly-or$GuardFixturePath-or$ExecutionTargetOnly)){throw 'FAILURE_TRANSPORT_FLAGS'}
if($FocusedReviewRepairOnly-and($Group-cne'CurrentCoverage'-or$FixtureContractOnly-or$PublicSuiteConsumerContractOnly-or$ToolResolutionContractOnly-or$IntegrationConsumerContractOnly-or$GuardFixturePath)){throw 'FOCUSED_REVIEW_REPAIR_FLAGS'}
if($PublicSuiteConsumerContractOnly-and($Group-cne'CurrentCoverage'-or$FixtureContractOnly-or$ToolResolutionContractOnly-or$IntegrationConsumerContractOnly-or$GuardFixturePath)){throw 'PUBLIC_SUITE_CONSUMER_CONTRACT_FLAGS'}
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
Import-Module (Join-Path $PSScriptRoot 'TestGroupEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot '../scripts/StrictJsonInput.psm1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gev-'+[guid]::NewGuid().ToString('N').Substring(0,8));$null=[IO.Directory]::CreateDirectory($temp)
$passed=0;$root=Join-Path $temp 'source';$tests=Join-Path $root 'framework/versions/2.0.0/tests';$null=[IO.Directory]::CreateDirectory($tests)
$rawRoot=if($env:AIW_TEST_RAW_DIRECTORY){Join-Path $env:AIW_TEST_RAW_DIRECTORY ('ev-'+[guid]::NewGuid().ToString('N').Substring(0,8))}else{Join-Path ([IO.Path]::GetTempPath()) ('aiw-evidence-raw-'+[guid]::NewGuid().ToString('N'))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Reject([scriptblock]$Body,[string]$Pattern,[string]$Name){$caught='';try{$null=& $Body}catch{$caught=$_.Exception.Message};Check ($caught-match$Pattern) ($Name+'|reason='+$caught)}
function Put([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Clone($Value){return $Value|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100}
function TestNativeErrorTransport {
 $probe=Join-Path $temp '错误出口';$null=[IO.Directory]::CreateDirectory($probe)
 $entry=Join-Path $probe 'actual-evidence-tests.ps1';[IO.File]::Copy($PSCommandPath,$entry)
 $init=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$entry,'-Group','All') -WorkingDirectory $probe -EvidenceDirectory $rawRoot -GroupId 'outer-initialization-error'
 $initial=(ConvertFrom-AiwStrictInputJson $init.StderrText.Trim()).Value
 Check ($init.Code-ne0-and$initial.reason.Contains('TestHarness.psm1')-and$initial.scriptStackTrace.Contains('错误出口')-and$init.StderrText-cnotmatch'[^\x00-\x7F]') 'actual-All-initialization-error-preserves-unicode-stack-in-ASCII-json'
 $missing=Join-Path $probe '原始缺失.json';$wrapper=Join-Path $probe 'first-and-cleanup.ps1';$cleanupMarker=Join-Path $probe 'cleanup-root.txt'
 $body=@'
param([string]$Entry,[string]$Missing,[string]$CleanupMarker)
$global:AiwCleanupMarker=$CleanupMarker
function global:Remove-Item {[CmdletBinding()]param([string]$LiteralPath,[switch]$Recurse,[switch]$Force);[IO.File]::WriteAllText($global:AiwCleanupMarker,$LiteralPath,[Text.UTF8Encoding]::new($false));throw '次级清理失败'}
& $Entry -Group All -GuardFixturePath $Missing
exit $LASTEXITCODE
'@
 Put $wrapper $body
 try{
  $both=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$wrapper,'-Entry',$PSCommandPath,'-Missing',$missing,'-CleanupMarker',$cleanupMarker) -WorkingDirectory $probe -EvidenceDirectory $rawRoot -GroupId 'outer-first-and-cleanup-error'
  $errors=(ConvertFrom-AiwStrictInputJson $both.StderrText.Trim()).Value
  Check ($both.Code-ne0-and$errors.reason.Contains('原始缺失')-and$errors.scriptStackTrace.Contains('test-group-evidence-tests.ps1')-and$errors.cleanupError.reason-ceq'次级清理失败'-and$errors.cleanupError.scriptStackTrace.Contains('first-and-cleanup.ps1')-and$both.StderrText-cnotmatch'[^\x00-\x7F]') 'actual-All-first-failure-survives-secondary-cleanup-error'
 }finally{
  # The injected cleanup failure must be observed, then its exact ended child
  # fixture is cleaned by the parent. Do not leave a false DIRTY suite result.
  if(Test-Path -LiteralPath $cleanupMarker){
   $child=[IO.Path]::GetFullPath([IO.File]::ReadAllText($cleanupMarker));$owner=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
   if([IO.Path]::GetDirectoryName($child)-cne$owner-or[IO.Path]::GetFileName($child)-cnotmatch'^gev-[a-f0-9]{8}$'-or((Get-Item -LiteralPath $child -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'ERROR_PROBE_CLEANUP_SCOPE'}
   Microsoft.PowerShell.Management\Remove-Item -LiteralPath $child -Recurse -Force
  }
 }
}
function CloneEvidence($Value,[string[]]$StringFields){return (ConvertFrom-AiwStrictInputJson ($Value|ConvertTo-Json -Depth 100 -Compress) -StringFields $StringFields).Value}
function TestIntegrationConsumerContracts {
 $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
 $definition=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
 $options=[pscustomobject]@{SkipManifest=$true;SkipBaseline=$true;SkipPerformanceSmoke=$true;MaintenanceFixture=$false}
 foreach($spec in @(@{id='integration.surface';flags=@('-SkipManifest','-SkipBaseline')},@{id='integration.maintenance';flags=@()},@{id='integration.authorization';flags=@()},@{id='integration.process';flags=@()},@{id='integration.full-source';flags=@()},@{id='integration.tool-contract';flags=@('-SkipManifest','-SkipBaseline','-SkipPerformanceSmoke')},@{id='integration.selectors';flags=@('-SkipManifest','-SkipBaseline','-SkipPerformanceSmoke')})){
  $g=@($definition.groups|Where-Object id -CEQ $spec.id)[0]
  $args=@(Get-AiwTestGroupArguments $source $g $options)
  $flags=@($args|Where-Object{$_-cin@('-SkipManifest','-SkipBaseline','-SkipPerformanceSmoke')})
  Check (($flags-join',')-ceq($spec.flags-join',')) ('consumer-skip-owned-entry-'+$spec.id)
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source $g.entry),[ref]$tokens,[ref]$errors)
  $parameters=@($ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
  Check ($errors.Count-eq0-and@($args|Select-Object -Skip 4|Where-Object{$_-clike'-*'-and$_.TrimStart('-')-cnotin$parameters}).Count-eq0) ('consumer-real-param-binding-'+$spec.id)
 }
 $gov=@($definition.groups|Where-Object id -CEQ 'governance-contract')[0]
 Check ('-SkipPerformanceSmoke'-cin@(Get-AiwTestGroupArguments $source $gov $options)) 'consumer-performance-skip-real-governance-owner'
 $noFlags=[pscustomobject]@{SkipManifest=$false;SkipBaseline=$false;SkipPerformanceSmoke=$false;MaintenanceFixture=$false}
 foreach($g in @($definition.groups|Where-Object id -CLike 'integration.*')){
  Check (@(Get-AiwTestGroupArguments $source $g $noFlags|Where-Object{$_-cin@('-SkipManifest','-SkipBaseline','-SkipPerformanceSmoke')}).Count-eq0) ('consumer-false-skips-omitted-'+$g.id)
 }
 Check ('-SkipPerformanceSmoke'-cnotin@(Get-AiwTestGroupArguments $source $gov $noFlags)) 'consumer-false-governance-skip-omitted'
 foreach($g in @($definition.groups|Where-Object id -CLike 'presets.*')){
  Check (@(Get-AiwTestGroupArguments $source $g ([pscustomobject]@{MaintenanceFixture=$true})|Where-Object{$_-ceq'-MaintenanceFixture'}).Count-eq1) ('consumer-preset-fixture-owned-'+$g.id)
  Check ('-MaintenanceFixture'-cnotin@(Get-AiwTestGroupArguments $source $g $noFlags)) ('consumer-preset-false-fixture-omitted-'+$g.id)
 }
 Check ('-MaintenanceFixture'-cnotin@(Get-AiwTestGroupArguments $source $gov ([pscustomobject]@{MaintenanceFixture=$true}))) 'consumer-fixture-not-leaked-to-governance'
 $prepackage=@(Get-AiwTestGroupArguments $source $gov ([pscustomobject]@{}))
 Check ($prepackage.Count-ge4-and@($prepackage|Where-Object{$_-cin@('-PackagePath','-ExtractedPackagePath','-BuildCommandPath')}).Count-eq0) 'consumer-prepackage-no-postbuild-values-required'
 $argumentRoot=Join-Path $temp '参数 样本';$null=[IO.Directory]::CreateDirectory($argumentRoot)
 $postValues=[ordered]@{PackagePath=(Join-Path $argumentRoot '用户 包.zip');ExtractedPackagePath=(Join-Path $argumentRoot '解压 树');BuildCommandPath=(Join-Path $argumentRoot '构建 结果.json')}
 $postSpecs=@(@{id='postbuild.package-integrity';group='PackageIntegrity'},@{id='postbuild.adoption-smoke';group='AdoptionSmoke'})
 $argumentCases=@();$argumentResults=@()
 try{
  foreach($spec in $postSpecs){
   $g=@($definition.groups|Where-Object id -CEQ $spec.id)[0]
   foreach($kind in @('PSCustomObject','Ordered')){
    $postOptions=if($kind-ceq'PSCustomObject'){[pscustomobject]$postValues}else{$postValues}
    $argv=@(Get-AiwTestGroupArguments $source $g $postOptions)
    $expected=@('-NoProfile','-NonInteractive','-File',(Join-Path $source $g.entry),'-Group',$spec.group,'-PackagePath',$postValues.PackagePath,'-ExtractedPackagePath',$postValues.ExtractedPackagePath,'-BuildCommandPath',$postValues.BuildCommandPath)
    Check ($argv.Count-eq12) ('consumer-postbuild-argv-count-'+$spec.id+'-'+$kind)
    for($i=0;$i-lt$expected.Count;$i++){
     Check ($argv[$i]-is[string]-and[string]::Equals($argv[$i],$expected[$i],[StringComparison]::Ordinal)) ('consumer-postbuild-argv-item-'+$spec.id+'-'+$kind+'-'+$i)
    }
    $argumentCases+=@{groupId=$spec.id;optionsKind=$kind;arguments=@($argv)}
    foreach($name in @('PackagePath','ExtractedPackagePath','BuildCommandPath')){
     $missing=[ordered]@{};$empty=[ordered]@{}
     foreach($key in $postValues.Keys){if($key-cne$name){$missing[$key]=$postValues[$key]};$empty[$key]=if($key-ceq$name){''}else{$postValues[$key]}}
     $missingOptions=if($kind-ceq'PSCustomObject'){[pscustomobject]$missing}else{$missing}
     $emptyOptions=if($kind-ceq'PSCustomObject'){[pscustomobject]$empty}else{$empty}
     Reject {Get-AiwTestGroupArguments $source $g $missingOptions} '^TEST_POSTBUILD_INPUT_REQUIRED$' ('consumer-postbuild-missing-'+$spec.id+'-'+$kind+'-'+$name)
     Reject {Get-AiwTestGroupArguments $source $g $emptyOptions} '^TEST_POSTBUILD_INPUT_REQUIRED$' ('consumer-postbuild-empty-'+$spec.id+'-'+$kind+'-'+$name)
    }
   }
  }
  $releaseEntry=Join-Path $source 'framework/versions/2.0.0/tests/release-validation-tests.ps1'
  $tokens=$null;$errors=$null;$releaseAst=[Management.Automation.Language.Parser]::ParseFile($releaseEntry,[ref]$tokens,[ref]$errors)
  $binding=@($releaseAst.ParamBlock.Attributes|Where-Object{$_.TypeName.Name-ceq'CmdletBinding'})
  Check ($errors.Count-eq0-and$releaseAst.ParamBlock.Attributes.Count-eq1-and$binding.Count-eq1) 'consumer-postbuild-real-parameter-declaration'
  $binderEntry=Join-Path $argumentRoot '参数 回显.ps1'
  $binderBody=@'
$ErrorActionPreference='Stop'
if($PSBoundParameters.Count-ne4-or$args.Count-ne0){throw 'PRIVATE_BINDER_UNEXPECTED_PARAMETERS'}
$values=[ordered]@{}
foreach($name in @('Group','PackagePath','ExtractedPackagePath','BuildCommandPath')){$values[$name]=$PSBoundParameters[$name]}
$values|ConvertTo-Json -Compress
'@
  Put $binderEntry ($binding[0].Extent.Text+"`n"+$releaseAst.ParamBlock.Extent.Text+"`n"+$binderBody)
  $binderAst=[Management.Automation.Language.Parser]::ParseFile($binderEntry,[ref]$tokens,[ref]$errors)
  Check ($errors.Count-eq0-and$binderAst.ParamBlock.Extent.Text-ceq$releaseAst.ParamBlock.Extent.Text-and@($binderAst.ParamBlock.Attributes|Where-Object{$_.TypeName.Name-ceq'CmdletBinding'}).Count-eq1) 'consumer-postbuild-private-binder-same-declaration-once'
  for($caseIndex=0;$caseIndex-lt$postSpecs.Count;$caseIndex++){
   $spec=$postSpecs[$caseIndex];$kind=if($caseIndex-eq0){'PSCustomObject'}else{'Ordered'}
   $argv=@($argumentCases|Where-Object{$_.groupId-ceq$spec.id-and$_.optionsKind-ceq$kind})[0].arguments
   $nativeArgs=[string[]]$argv.Clone();$nativeArgs[3]=$binderEntry
   Check ($nativeArgs.Count-eq12-and@((0..11)|Where-Object{$_-ne3-and-not[string]::Equals($nativeArgs[$_],$argv[$_],[StringComparison]::Ordinal)}).Count-eq0) ('consumer-postbuild-native-only-file-target-changed-'+$spec.id)
   $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) $nativeArgs -WorkingDirectory $argumentRoot -EvidenceDirectory (Join-Path $rawRoot 'postbuild-argument-binders') -GroupId ('private-postbuild-arguments-'+$spec.group)
   Check ($native.Code-eq0-and$native.Status-ceq'PASS'-and$native.StderrText.Length-eq0) ('consumer-postbuild-real-native-binding-'+$spec.id)
   $bound=$native.StdoutText|ConvertFrom-Json
   Check ((@($bound.PSObject.Properties.Name|Sort-Object)-join',')-ceq'BuildCommandPath,ExtractedPackagePath,Group,PackagePath') ('consumer-postbuild-native-four-values-'+$spec.id)
   Check ([string]::Equals($bound.Group,$spec.group,[StringComparison]::Ordinal)) ('consumer-postbuild-native-group-'+$spec.id)
   foreach($name in @('PackagePath','ExtractedPackagePath','BuildCommandPath')){
    Check ([string]::Equals($bound.$name,$postValues[$name],[StringComparison]::Ordinal)) ('consumer-postbuild-native-value-'+$spec.id+'-'+$name)
   }
   $argumentResults+=@{groupId=$spec.id;optionsKind=$kind;generatedArguments=@($argv);nativeArguments=@($nativeArgs);native=@{path=$native.ResultPath;identity=(Get-AiwTestFileIdentity $native.ResultPath)};observed=$bound}
  }
 }finally{
  $full=[IO.Path]::GetFullPath($argumentRoot)
  if([IO.Path]::GetDirectoryName($full)-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp))-or[IO.Path]::GetFileName($full)-cne'参数 样本'){throw 'POSTBUILD_ARGUMENT_FIXTURE_CLEANUP_SCOPE'}
  if([IO.Directory]::Exists($full)){Remove-Item -LiteralPath $full -Recurse -Force}
 }
 $argumentWorkers=@(Get-AiwTestRawProcessStates (Join-Path $rawRoot 'postbuild-argument-binders')|Where-Object state -CNE 'COMPLETE')
 Check (-not(Test-Path -LiteralPath $argumentRoot)-and$argumentWorkers.Count-eq0) 'consumer-postbuild-native-fixtures-clean'
 $module=Get-Module TestGroupEvidence
 $retired='NOT_RUN|historical-baseline-executable-regression|reason=retired-executable-suite-history-only'
 foreach($id in @('integration.surface','integration.full-source')){
  $omissions=@(& $module {param($line,$id) Get-AiwTestOmissions $line '' $id} $retired $id)
  Check ($omissions.Count-eq0) ('consumer-retired-history-owner-'+$id)
 }
 $wrong=@(& $module {param($line) Get-AiwTestOmissions $line '' 'integration.authorization'} $retired)
 Check ($wrong.Count-eq1-and$wrong[0]-ceq$retired) 'consumer-retired-history-not-general-integration-exemption'
 $other=@(& $module {Get-AiwTestOmissions "NOT_RUN|required-work|reason=omitted`nUNKNOWN|required-work" '' 'integration.surface'})
 Check ($other.Count-eq2) 'consumer-real-omissions-and-unknown-retained'
 $g=@($definition.groups|Where-Object id -CEQ 'integration.surface')[0]
 $skip='SKIP|historical-baseline-executable-regression|reason=SkipBaseline'
 $actualSkip=@(& $module {param($line) Get-AiwTestOmissions $line '' 'integration.surface'} $skip)
 Check ($actualSkip.Count-eq1) 'consumer-real-skip-is-partial'
 $null=& $module {param($lines,$g,$opts) Assert-AiwTestRequestedOmissions $lines $g $opts} $actualSkip $g $options
 Reject {& $module {param($lines,$g) Assert-AiwTestRequestedOmissions $lines $g ([pscustomobject]@{SkipBaseline=$false})} $actualSkip $g} 'TEST_SKIPPED_OR_UNKNOWN_COVERAGE' 'consumer-unrequested-skip-rejected'
 Reject {& $module {param($lines,$g,$opts) Assert-AiwTestRequestedOmissions $lines $g $opts} $other $g $options} 'TEST_SKIPPED_OR_UNKNOWN_COVERAGE' 'consumer-unknown-and-real-omission-rejected'
 $consumerRoot=Join-Path $temp 'completion-consumer';[IO.Directory]::CreateDirectory($consumerRoot)|Out-Null
 $entry=Join-Path $consumerRoot 'completion-fixture.ps1'
 Put $entry @'
param([string]$Scope)
Write-Output 'PASS|private-completion-target'
Write-Output ('RESULT|1 passed|scope='+$Scope)
'@
 $tool=@($definition.groups|Where-Object id -CEQ 'integration.tool-contract')[0]
 $snapshot=@{identity='PRIVATE_COMPLETION_FIXTURE';facts=@{validatorIdentity=(Get-AiwTestFileIdentity $module.Path)}}
 foreach($spec in @(@{scope='Framework-2.0.0-tool-contract';expected='PASS'},@{scope='tool-contract';expected='INCOMPLETE'},@{scope='Framework-2.0.0-tool-contract-other';expected='INCOMPLETE'})){
  $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$entry,'-Scope',$spec.scope) -WorkingDirectory $consumerRoot -EvidenceDirectory (Join-Path $rawRoot 'integration-consumer-completion') -GroupId 'private-completion-consumer'
  $recordPath=Join-Path $rawRoot ('private-completion-'+[guid]::NewGuid().ToString('N')+'.json')
  $record=Complete-AiwTestGroupEvidence $recordPath $tool $snapshot $snapshot $native @{status='CLEAN';root=(Join-Path $consumerRoot 'unused-clean-root');entries=@();workers=@()}
  Check ($native.Code-eq0-and$record.outcome-ceq$spec.expected) ('consumer-exact-completion-'+$spec.scope)
 }
 Write-AiwTestJson (Join-Path $rawRoot 'integration-consumer-contracts.json') @{kind='PRIVATE_CURRENT_ENTRY_ARGUMENT_OMISSION_COMPLETION_CONSUMERS';definitionIdentity=(Get-AiwTestFileIdentity (Join-Path $PSScriptRoot 'test-groups.json'));formalGroupQualification=$false;nativeCompletionFixtures=3;nativeArgumentFixtures=2;argumentCases=$argumentCases;nativeArgumentResults=$argumentResults;argumentCleanup=@{status='CLEAN';root=$argumentRoot;entries=@();workers=$argumentWorkers};ceiling='PARTIAL consumer mechanisms and actual native parameter binding; no package, release qualification or complete domain/suite qualification'}
}


function TestFiniteDependencyMappings {
 param([switch]$ToolResolutionContractOnly)
 # Actual current D and snapshot reader, with finite owned copies only.
 $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
 $vp='framework/versions/2.0.0/';$dp=$vp+'tests/test-groups.json'
 $d=Read-AiwTestGroupDefinition (Join-Path $source $dp)
 $ids=@('evidence.current-coverage','efficiency-regression','governance-contract','non-git.transactions')
 $groups=@($ids|ForEach-Object{$id=$_;@($d.groups|Where-Object id -CEQ $id)[0]})
 foreach($g in $groups){Check ($g.fixturePolicy-ceq'MECHANISM'-and-not$g.alwaysFresh-and@($g.unknownDependencies).Count-eq0) ('mapping-closed-policy-'+$g.id)}
 # Keep the finite four-group copy aligned with current declared behavior files
 # and constructors; mutation expectations below remain independently specified.
 $dependencyReader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1') -PassThru)[0]
 $members=@(@($d.mechanismVersionPaths|ForEach-Object{$vp+$_})+@($d.rootAdoptionPaths)+@($d.maintenancePaths)+@($groups|ForEach-Object{& $dependencyReader.ExportedCommands['Get-AiwEvidenceDependencyPaths'] $d $_})+@($dp,($vp+'tests/run-framework-tests.ps1'),($vp+'tests/TestHarness.psm1'),($vp+'tests/TestGroupEvidence.psm1'),($vp+'tests/process-runtime-v2-tests.ps1'))|Sort-Object -Unique)
 $seed=Join-Path $temp 'mapping-seed';$map=Join-Path $temp 'mapping-view';$other=Join-Path $temp 'mapping-other'
 $manifestMembers=@($members|Where-Object{$_-clike'*/RELEASE_MANIFEST.json'})
 Copy-AiwTestAllowlist $source $seed @($members|Where-Object{$_-cnotin$manifestMembers})
 foreach($p in $manifestMembers){$from=Assert-AiwTestPath (Join-Path $source $p);$to=Assert-AiwTestPath (Join-Path $seed $p);[IO.File]::Copy($from,$to,$false)}
 $inventory=Read-AiwTestJson (Join-Path $seed ($vp+'NORMATIVE_SURFACE_INVENTORY.json'))
 $inventory.runtimeNormativeModules=@();$inventory.actionRequiredArtifacts=@();$inventory.explanationAndHistory=@()
 $inventory.schemaAndMechanicalInputs=@($members|Where-Object{$_.StartsWith($vp,[StringComparison]::Ordinal)-and$_-cne($vp+'RELEASE_MANIFEST.json')}|ForEach-Object{$_.Substring($vp.Length)})
 Put (Join-Path $seed ($vp+'NORMATIVE_SURFACE_INVENTORY.json')) (($inventory|ConvertTo-Json -Depth 100 -Compress)+"`n")
 $construction=Clone $d;$construction.sourceViewPaths=@($members|Where-Object{$_-cnotin$manifestMembers})
 # The definition bytes remain the real D; this private argument limits copying.
 $null=New-AiwTestSourceView $seed $map $construction
 foreach($p in $manifestMembers){[IO.File]::Copy((Join-Path $seed $p),(Join-Path ([IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Join-Path $map $p)))).FullName ([IO.Path]::GetFileName($p))),$false)}
 if(-not$ToolResolutionContractOnly){$null=New-AiwTestSourceView $seed $other $construction
 foreach($p in $manifestMembers){[IO.File]::Copy((Join-Path $seed $p),(Join-Path ([IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Join-Path $other $p)))).FullName ([IO.Path]::GetFileName($p))),$false)}
 }
 $options=[ordered]@{SkipManifest=$false;SkipBaseline=$false;SkipPerformanceSmoke=$false;MaintenanceFixture=$false}
 function MappingSnapshots([string]$At=$map,$Opt=$options){$result=@{};foreach($g in $groups){$result[$g.id]=Get-AiwTestDependencySnapshot $At (Join-Path $At $dp) $d $g $Opt};return $result}
 if($ToolResolutionContractOnly){
  $originalPath=$env:PATH;$toolDir=Join-Path $temp 'mapping-tools';$null=[IO.Directory]::CreateDirectory($toolDir)
  $actualPwsh=Get-Command pwsh -CommandType Application|Select-Object -First 1
  [IO.File]::Copy($actualPwsh.Source,(Join-Path $toolDir 'pwsh.exe'),$false)
  try{
   $env:PATH=$toolDir+[IO.Path]::PathSeparator+$originalPath
   $resolved=Get-Command pwsh -CommandType Application|Select-Object -First 1
   if($resolved.Source-cne(Join-Path $toolDir 'pwsh.exe')){throw 'MAPPING_TOOL_RESOLUTION_FIRST_ITEM'}
   Write-Output ('TOOL_RESOLUTION_PRECHECK|PASS|actualFirst='+$resolved.Source)
  }finally{$env:PATH=$originalPath}
 }
 $base=MappingSnapshots
 $observations=@()
 function CheckMapping([string]$Name,[string[]]$Affected,[scriptblock]$Change,[scriptblock]$Restore){
  try{& $Change;$now=MappingSnapshots;foreach($id in $ids){$changed=$now[$id].identity-cne$base[$id].identity;Check ($changed-eq($id-cin$Affected)) ('mapping-'+$Name+'-'+$id);$script:mappingRows+=@{case=$Name;groupId=$id;expectedChange=($id-cin$Affected);changed=$changed;before=$base[$id].identity;after=$now[$id].identity}}}finally{& $Restore}
  $restored=MappingSnapshots;foreach($id in $ids){Check ($restored[$id].identity-ceq$base[$id].identity) ('mapping-restored-'+$Name+'-'+$id)}
 }
 $script:mappingRows=@()
 if(-not$ToolResolutionContractOnly){
 foreach($spec in @(
  @{name='summary';path=$vp+'tests/run-framework-tests-summary.ps1';affected=@($ids[0],$ids[2])},
  @{name='measurement';path=$vp+'tests/measure-process-requirements.ps1';affected=$ids},
  @{name='fixture-json';path=$vp+'tests/PROCESS_REQUIREMENTS_FIXTURES.json';affected=$ids},
  @{name='prompts';path=$vp+'PROMPTS.md';affected=$ids},
  @{name='content-sources';path=$vp+'scripts/ContentSources.psm1';affected=$ids},
  @{name='legacy-runtime';path='framework/versions/1.16.0/scripts/ProcessRequirementComposition.psm1';affected=@($ids[3])},
  @{name='upgrade';path='scripts/upgrade-project.ps1';affected=$ids},
  @{name='validator';path=$vp+'scripts/ReleaseValidation.psm1';affected=$ids},
  @{name='unrelated-m4-test';path=$vp+'tests/process-runtime-v2-tests.ps1';affected=@()}
 )){
  $path=Join-Path $map $spec.path;$bytes=[IO.File]::ReadAllBytes($path)
  CheckMapping $spec.name $spec.affected {[IO.File]::AppendAllText($path,"`n ")} {[IO.File]::WriteAllBytes($path,$bytes)}
 }
 foreach($g in $groups){$path=Join-Path $map $g.entry;$bytes=[IO.File]::ReadAllBytes($path);CheckMapping ('entry-'+$g.id) @($g.id) {[IO.File]::AppendAllText($path,"`n# owned entry mutation")} {[IO.File]::WriteAllBytes($path,$bytes)}}
 $path=Join-Path $map $dp;$bytes=[IO.File]::ReadAllBytes($path);$cp=Join-Path $map 'source-inputs.json';$closureBytes=[IO.File]::ReadAllBytes($cp)
 CheckMapping 'definition' $ids {[IO.File]::AppendAllText($path,"`n ");$closure=Read-AiwTestJson $cp;$closure.definitionIdentity=Get-AiwTestFileIdentity $path;Put $cp (($closure|ConvertTo-Json -Depth 100 -Compress)+"`n")} {[IO.File]::WriteAllBytes($path,$bytes);[IO.File]::WriteAllBytes($cp,$closureBytes)}
 $different=MappingSnapshots $other;foreach($id in $ids){Check ($different[$id].identity-cne$base[$id].identity) ('mapping-root-'+$id)}
 $changedOptions=Clone $options;$changedOptions.SkipPerformanceSmoke=$true;$different=MappingSnapshots $map $changedOptions;foreach($id in $ids){Check ($different[$id].identity-cne$base[$id].identity) ('mapping-options-'+$id)}
 $originalPath=$env:PATH;$empty=Join-Path $temp 'mapping-empty-path';$null=[IO.Directory]::CreateDirectory($empty)
 CheckMapping 'parent-path' $ids {$env:PATH=$empty+[IO.Path]::PathSeparator+$originalPath} {$env:PATH=$originalPath}
 }
 if(-not$ToolResolutionContractOnly){
 $toolDir=Join-Path $temp 'mapping-tools';$null=[IO.Directory]::CreateDirectory($toolDir)
 $actualPwsh=@($base[$ids[0]].facts.environment.tools|Where-Object name -CEQ pwsh)[0]
 [IO.File]::Copy($actualPwsh.path,(Join-Path $toolDir 'pwsh.exe'),$false)
 }
 CheckMapping 'tool-path' $ids {$env:PATH=$toolDir+[IO.Path]::PathSeparator+$originalPath;$resolved=Get-Command pwsh -CommandType Application|Select-Object -First 1;Check ($resolved.Source-ceq(Join-Path $toolDir 'pwsh.exe')) 'mapping-real-tool-resolution-changes'} {$env:PATH=$originalPath}
 Reject {Copy-AiwTestAllowlist $seed (Join-Path $temp 'mapping-path-reject') @('../outside')} 'ALLOWLIST|LOCATOR' 'mapping-allowlist-rejects-parent-path'
 $link=Join-Path $seed 'mapping-link';$null=New-Item -ItemType Junction -Path $link -Target $map
 try{Reject {Copy-AiwTestAllowlist $seed (Join-Path $temp 'mapping-reparse-reject') @('mapping-link/README.md')} 'REPARSE' 'mapping-allowlist-rejects-reparse'}finally{Remove-Item -LiteralPath $link}
 Write-AiwTestJson (Join-Path $rawRoot 'finite-dependency-mappings.json') @{kind='ACTUAL_CURRENT_D_SNAPSHOT_COUNTEREXAMPLES';formalFourGroupExecution=$false;coverage=$(if($ToolResolutionContractOnly){'PARTIAL_TOOL_PATH_SUFFIX'}else{'DEFAULT_MAPPING_CASES'});skippedPrefixExecuted=(-not$ToolResolutionContractOnly);definitionIdentity=(Get-AiwTestFileIdentity (Join-Path $source $dp));members=(Get-AiwTestFixtureSnapshot $map -IdentityOnly).Files;cases=$script:mappingRows;rootAndOptions=(-not$ToolResolutionContractOnly);parentPathPrefixExecuted=(-not$ToolResolutionContractOnly);actualPathAndToolResolution=$true;restoration=$true}
}

function TestSourceReadClosure {
 # Finite real constructor/snapshot/reader counterexamples for the R9 gap.
 $actual=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'));$vp='framework/versions/2.0.0/'
 $current=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
 $seed=Join-Path $temp 'read-closure-seed';$view=Join-Path $temp 'read-closure-view';$dp=Join-Path $seed ($vp+'tests/test-groups.json')
 $versionPaths=@('VERSION.json','TOOLCHAIN.json','LOAD_MANIFEST.json','NORMATIVE_SURFACE_INVENTORY.json','tests/test-groups.json','tests/run-framework-tests.ps1','tests/run-framework-tests-summary.ps1','tests/TestHarness.psm1','tests/TestNativeOutput.psm1','tests/TestGroupEvidence.psm1','tests/TestExecutionRuntime.psm1','scripts/TestEvidenceValidation.psm1','scripts/ReleaseValidation.psm1','scripts/StrictJsonInput.psm1','tests/release-validation-tests.ps1','tests/IntegrationFixture.psm1','tests/integration-surface-tests.ps1','tests/integration-maintenance-tests.ps1','tests/integration-authorization-tests.ps1','tests/integration-process-tests.ps1','tests/integration-flow-tests.ps1')
 $roots=@(@($current.rootAdoptionPaths)+@($current.maintenancePaths)+@('README.md','LICENSE','framework/FRAMEWORK_RELEASE.md','.gitattributes','framework/ROADMAP.md','skills/ai-workspace-router/SKILL.md')|Select-Object -Unique)
 Check ($roots.Count-eq25) 'read-closure-current-main-conservative-25'
 $outside=@($current.sourceViewPaths|Where-Object{-not$_.StartsWith($vp,[StringComparison]::Ordinal)})
 Check ($outside.Count-eq124-and$current.sourceViewPaths.Count-eq266) 'read-closure-current-declaration-266-outside-124'
 foreach($id in @('release.proof-schema','release.prepackage-readers')){$g=@($current.groups|Where-Object id -CEQ $id)[0];Check (@($outside|Where-Object{$_-cnotin$g.dependencies}).Count-eq0) ('read-closure-current-whole-factory-124-'+$id)}
 Copy-AiwTestAllowlist $actual $seed @(@($versionPaths|ForEach-Object{$vp+$_})+$roots)
 $inventory=Read-AiwTestJson (Join-Path $seed ($vp+'NORMATIVE_SURFACE_INVENTORY.json'))
 $inventory.runtimeNormativeModules=@();$inventory.actionRequiredArtifacts=@();$inventory.explanationAndHistory=@();$inventory.schemaAndMechanicalInputs=$versionPaths
 Put (Join-Path $seed ($vp+'NORMATIVE_SURFACE_INVENTORY.json')) (($inventory|ConvertTo-Json -Depth 100 -Compress)+[char]10)
 $d=Clone $current;$d.mechanismVersionPaths=@();$d.sourceViewPaths=@($roots)+@($versionPaths|ForEach-Object{$vp+$_});$d.groups=@(@('integration.full-source','release.proof-schema','release.prepackage-readers','integration.surface','integration.maintenance','integration.authorization','integration.process')|ForEach-Object{$id=$_;Clone @($current.groups|Where-Object id -CEQ $id)[0]})
 foreach($g in $d.groups){$g.dependencies=@($roots)+@($vp+'tests/IntegrationFixture.psm1');$g.behaviorInputs.files=@($g.dependencies)}
 function SaveReadDefinition($value){Put $dp (($value|ConvertTo-Json -Depth 100 -Compress)+[char]10)}
 SaveReadDefinition $d
 $ids=@($d.groups.id)
 $positive=Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids
 Check ($positive.inputCount-eq46) 'read-closure-finite-consistent-declaration-before-construction'
 $lease=Enter-AiwTestSourceView $seed $view $d (Join-Path $temp 'read-closure-evidence')
 try{
  $positive=Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids -Stage AfterConstruction -ViewRoot $view
  Check ($positive.inputCount-eq46) 'read-closure-real-owned-view-projection'
  $attrs=Join-Path $view '.gitattributes';$attrsBytes=[IO.File]::ReadAllBytes($attrs)
  [IO.File]::Delete($attrs)
  Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids -Stage AfterConstruction -ViewRoot $view} 'TEST_SOURCE_VIEW_INPUT_MISSING\|\.gitattributes' 'read-closure-view-missing-attrs'
  [IO.File]::WriteAllBytes($attrs,$attrsBytes);Put $attrs 'changed attrs'
  Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids -Stage AfterConstruction -ViewRoot $view} 'TEST_SOURCE_VIEW_INPUT_DRIFT\|\.gitattributes' 'read-closure-view-byte-drift'
  [IO.File]::WriteAllBytes($attrs,$attrsBytes)
  $hidden=Join-Path $seed '.github/workflows/framework-toolchain-conformance.yml';Put $hidden 'hidden CI'
  Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids -Stage BeforeExport -ViewRoot $view} 'TEST_SOURCE_READ_FORBIDDEN_ROOT\|\.github' 'read-closure-hidden-source-ci-at-terminal'
  [IO.File]::Delete($hidden)
  $hidden=Join-Path $seed 'PACKAGE_MANIFEST.json';Put $hidden '{}'
  Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids} 'TEST_SOURCE_READ_FORBIDDEN_ROOT\|PACKAGE_MANIFEST' 'read-closure-unsealed-source-root-state'
  [IO.File]::Delete($hidden)
  $optional=Join-Path $seed 'INITIALIZATION.md';Put $optional 'optional input'
  Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids} 'TEST_SOURCE_READ_OPTIONAL_UNBOUND\|INITIALIZATION' 'read-closure-optional-present-unbound'
  [IO.File]::Delete($optional)
  $beforeView=Get-AiwTestFixtureSnapshot $view -IdentityOnly;$ownerBefore=Get-AiwTestFileIdentity ($view+'.owner.json')
  $bad=Clone $d;$bad.sourceViewPaths=@($bad.sourceViewPaths|Where-Object{$_-cne'.gitattributes'});SaveReadDefinition $bad
  Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $bad $ids} 'TEST_SOURCE_READ_REQUIRED_DECLARATION\|\.gitattributes' 'read-closure-missing-declaration-before-enter'
  # The real public runner must reject before refreshing this leased old view or launching a group.
  $process=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $seed ($vp+'tests/run-framework-tests.ps1')),'-Groups','integration.full-source','-SourceViewPath',$view,'-EvidenceDirectory',(Join-Path $rawRoot 'read-closure-preenter-groups')) -WorkingDirectory $seed -EvidenceDirectory (Join-Path $rawRoot 'read-closure-preenter-native') -GroupId 'read-closure-preenter'
  Check ($process.Code-ne0-and$process.StderrText.Contains('TEST_SOURCE_READ_REQUIRED_DECLARATION')-and-not$process.StdoutText.Contains('GROUP|integration.full-source|START')) 'read-closure-real-public-preenter-reject-no-child'
  Check ((Get-TestValueIdentity (Get-AiwTestFixtureSnapshot $view -IdentityOnly))-ceq(Get-TestValueIdentity $beforeView)-and(Get-AiwTestFileIdentity ($view+'.owner.json'))-ceq$ownerBefore) 'read-closure-preenter-keeps-old-owned-view'
  SaveReadDefinition $d
 }finally{$lease.Lease.Dispose()}
 $lock=[IO.File]::Open(($view+'.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$lock.Dispose()
 Check ($true) 'read-closure-real-failure-lease-released-clean'
 $sourceAttrs=Join-Path $seed '.gitattributes';$bytes=[IO.File]::ReadAllBytes($sourceAttrs);[IO.File]::Delete($sourceAttrs)
 Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $d $ids} 'TEST_SOURCE_READ_INPUT_MISSING\|\.gitattributes' 'read-closure-source-missing-attrs'
 [IO.File]::WriteAllBytes($sourceAttrs,$bytes)
 foreach($spec in @(@{path='framework/ROADMAP.md';reason='DEPENDENCY'},@{path='skills/ai-workspace-router/SKILL.md';reason='DEPENDENCY'})){
  $bad=Clone $d;$bad.groups[0].dependencies=@($bad.groups[0].dependencies|Where-Object{$_-cne$spec.path});SaveReadDefinition $bad
  Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $bad $ids} ('TEST_SOURCE_READ_'+$spec.reason) ('read-closure-main-required-'+$spec.path)
 }
  foreach($newEntryId in @('integration.full-source','integration.surface','integration.maintenance','integration.authorization','integration.process')){
   $bad=Clone $d;$targetGroup=@($bad.groups|Where-Object id -CEQ $newEntryId)[0];$targetGroup.dependencies=@($targetGroup.dependencies|Where-Object{$_-cne($vp+'tests/IntegrationFixture.psm1')});SaveReadDefinition $bad
   Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $bad $ids} 'TEST_SOURCE_READ_DEPENDENCY' ('read-closure-private-helper-required-'+$newEntryId)
   $bad=Clone $d;$targetGroup=@($bad.groups|Where-Object id -CEQ $newEntryId)[0];$targetGroup.arguments=@('-Case','Frontdoor');SaveReadDefinition $bad
   Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $bad $ids} 'TEST_SOURCE_READ_CONSUMER_ARGUMENTS' ('read-closure-formal-domain-rejects-partial-arguments-'+$newEntryId)
  }
  $bad=Clone $d;$bad.groups[0].arguments=@('-InternalLegacyRun','-MainIntegrationOnly','-SelectorOnly');SaveReadDefinition $bad
 Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $bad $ids} 'TEST_SOURCE_READ_CONSUMER_ARGUMENTS' 'read-closure-conflicting-real-entry-arguments'
 $bad=Clone $d;$bad.groups[0].tools=@('pwsh');SaveReadDefinition $bad
 Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $bad $ids} 'TEST_SOURCE_READ_TOOL' 'read-closure-real-entry-required-tools'
 $bad=Clone $d;$bad.groups[1].dependencies=@($bad.groups[1].dependencies|Where-Object{$_-cne'framework/ROADMAP.md'});SaveReadDefinition $bad
 Reject {Assert-AiwTestSourceViewReadClosure $seed $dp $bad $ids} 'TEST_SOURCE_READ_DEPENDENCY\|release.proof-schema' 'read-closure-whole-view-factory-dependency'
 SaveReadDefinition $d
 $optional=Join-Path $seed 'INITIALIZATION.md';Put $optional 'optional input'
 $withOptional=Clone $d;$withOptional.sourceViewPaths+=@('INITIALIZATION.md');foreach($g in $withOptional.groups){$g.dependencies+=@('INITIALIZATION.md')};SaveReadDefinition $withOptional
 $optionalView=Join-Path $temp 'read-closure-optional-view';$null=New-AiwTestSourceView $seed $optionalView $withOptional
 Check ($versionPaths.Count-eq21-and@($versionPaths|Sort-Object -Unique).Count-eq21-and$roots.Count-eq25-and'INITIALIZATION.md'-cnotin$d.sourceViewPaths-and@($withOptional.sourceViewPaths|Where-Object{$_-ceq'INITIALIZATION.md'}).Count-eq1) 'read-closure-independent44-plus-unique-initialization-member'
 $optionalResult=Assert-AiwTestSourceViewReadClosure $seed $dp $withOptional @($withOptional.groups.id) -Stage AfterConstruction -ViewRoot $optionalView
 Check ($optionalResult.inputCount-eq47-and[IO.File]::ReadAllText((Join-Path $optionalView 'INITIALIZATION.md'))-ceq'optional input') 'read-closure-optional-declared-bound-projected'
 [IO.File]::Delete($optional);SaveReadDefinition $d
 $snapshotOptions=[ordered]@{SkipManifest=$false;SkipBaseline=$false;SkipPerformanceSmoke=$false;MaintenanceFixture=$false}
 $viewDp=Join-Path $view ($vp+'tests/test-groups.json')
 foreach($spec in @(@{index=0;path='framework/ROADMAP.md'},@{index=0;path='skills/ai-workspace-router/SKILL.md'},@{index=1;path='framework/maintenance-overlay/OVERLAY.json'},@{index=2;path='framework/ROADMAP.md'})){
  $g=$d.groups[$spec.index];$before=Get-AiwTestDependencySnapshot $view $viewDp $d $g $snapshotOptions
  $path=Join-Path $view $spec.path;$bytes=[IO.File]::ReadAllBytes($path);Put $path 'actual input drift'
  try{$after=Get-AiwTestDependencySnapshot $view $viewDp $d $g $snapshotOptions;Check ($before.identity-cne$after.identity) ('read-closure-real-snapshot-'+$g.id+'-'+$spec.path)}finally{[IO.File]::WriteAllBytes($path,$bytes)}
 }
 $mechanism=Clone $d.groups[0];$mechanism.entry=$vp+'tests/test-group-child.ps1';$mechanism.arguments=@();$mechanism.dependencies=@();$mechanism.fixturePolicy='MECHANISM';$mechanism.behaviorInputs.files=@();$mechanism.behaviorInputs.wholeDefinition=$false
 Put (Join-Path $view $mechanism.entry) '# owned synthetic same-ID child'
 $before=Get-AiwTestDependencySnapshot $view $viewDp $d $mechanism $snapshotOptions;Put (Join-Path $view ($vp+'tests/unrelated.txt')) 'unrelated owned input'
 $after=Get-AiwTestDependencySnapshot $view $viewDp $d $mechanism $snapshotOptions
 Check ($before.identity-ceq$after.identity) 'read-closure-mechanism-unrelated-test-excluded'
 $toolBefore=Get-AiwTestDependencySnapshot $view $viewDp $d $d.groups[0] $snapshotOptions;$oldPath=$env:PATH;$toolDir=Join-Path $temp 'read-closure-tools'
 $git=@($toolBefore.facts.environment.tools|Where-Object name -CEQ git)[0];$null=[IO.Directory]::CreateDirectory($toolDir);[IO.File]::Copy($git.path,(Join-Path $toolDir 'git.exe'),$false)
 try{$env:PATH=$toolDir+[IO.Path]::PathSeparator+$oldPath;$toolAfter=Get-AiwTestDependencySnapshot $view $viewDp $d $d.groups[0] $snapshotOptions;Check ($toolAfter.identity-cne$toolBefore.identity-and@($toolAfter.facts.environment.tools|Where-Object{$_.name-ceq'git'-and$_.path-ceq(Join-Path $toolDir 'git.exe')}).Count-eq1) 'read-closure-real-tool-resolution-snapshot-drift'}finally{$env:PATH=$oldPath}
 # Reach the existing private reader through its real bundle index, with every
 # mutated closure/member/index identity rebound in this owned fixture.
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 $version=Join-Path $view $vp;$closure=Read-AiwTestJson (Join-Path $view 'source-inputs.json');$facts=Get-AiwReleasePayloadFacts $version -SourceView
 $memberPath='validation-evidence/prepackage/source-inputs.json';$indexPath=Join-Path $version 'validation-evidence/prepackage/index.json'
 function ReadFixtureClosure($value){
  Put (Join-Path $version $memberPath) (($value|ConvertTo-Json -Depth 100 -Compress)+[char]10)
  $member=@{id='closure';kind='INPUT_CLOSURE';path=$memberPath;identity=(Get-AiwTestFileIdentity (Join-Path $version $memberPath))}
  $index=@{schemaVersion=1;kind='PREPACKAGE_EVIDENCE_BUNDLE';members=@($member);aliases=@();inputBindings=@();sourceInputClosureMemberId='closure'}
  Put $indexPath (($index|ConvertTo-Json -Depth 100 -Compress)+[char]10)
  $bundleRef=[pscustomobject]@{path='validation-evidence/prepackage/index.json';identity=(Get-AiwTestFileIdentity $indexPath)}
  $bundleFacts=Get-AiwReleaseMemberFacts (@($bundleRef)+@($index.members))
  $proof=[pscustomobject]@{schemaVersion=2;proofBundleRef=$bundleRef;proofBundleIdentity=$bundleFacts.Canonical}
  $bundle=& $reader {param($root,$p) Get-AiwReleaseBundle $root $p} $version $proof
  & $reader {param($bundle,$facts,$definition,$source) Assert-AiwReleaseSourceInputs $bundle $facts $definition $source $null -Maintenance} $bundle $facts $d $seed
 }
 $read=ReadFixtureClosure $closure
 Check (@($read.inputs|Where-Object{$_.path-ceq'.gitattributes'-and$_.logicalRole-ceq'SOURCE_ONLY_BUILD_OR_TEST_INPUT'-and$null-eq$_.distributionLocator}).Count-eq1) 'read-closure-real-release-reader-positive-source-only-attrs'
 $bad=Clone $closure;@($bad.inputs|Where-Object path -CEQ '.gitattributes')[0].logicalRole='CURRENT_RUNTIME_TOOL'
 Reject {ReadFixtureClosure $bad} 'RELEASE_INPUT_ROLE_DOWNGRADE' 'read-closure-real-reader-wrong-role'
 $bad=Clone $closure;@($bad.inputs|Where-Object path -CEQ '.gitattributes')[0].distributionLocator='.gitattributes'
 Reject {ReadFixtureClosure $bad} 'RELEASE_SOURCE_ONLY_DISTRIBUTION_MAPPING' 'read-closure-real-reader-source-only-locator'
 $bad=Clone $closure;$bad.inputs=@($bad.inputs|Where-Object path -CNE '.gitattributes')
 Reject {ReadFixtureClosure $bad} 'RELEASE_SOURCE_INPUT_SET' 'read-closure-real-reader-exact-set-omission'
 Put (Join-Path $seed 'read-closure-extra.txt') 'owned extra'
 $bad=Clone $closure;$bad.inputs+=@(@{path='read-closure-extra.txt';identity=(Get-AiwTestFileIdentity (Join-Path $seed 'read-closure-extra.txt'));logicalRole='SOURCE_ONLY_BUILD_OR_TEST_INPUT';distributionLocator=$null})
 Reject {ReadFixtureClosure $bad} 'RELEASE_SOURCE_INPUT_SET' 'read-closure-real-reader-exact-set-extra'
 Write-AiwTestJson (Join-Path $rawRoot 'read-closure-cases.json') @{kind='PRIVATE_FINITE_REAL_SOURCE_READ_CLOSURE';formalSuite=$false;sourceInputs=@($d.sourceViewPaths);actualTools=$positive.environment.tools;preEnterNative=(Get-AiwTestFileIdentity $process.ResultPath);leaseReleased=$true;limits='Constructor/snapshot/reader/public pre-enter only; no full main or qualification.'}
}

function TestEvidenceGuardContracts([string]$RecordPath,[string]$RvPath,[string]$SuitePath,$NativeGroup){
 $shared=@(Import-Module (Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1') -PassThru)[0]
 $local=(Get-Command Get-AiwTestDependencySnapshot).Module
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 $record=Read-AiwTestJson $RecordPath -StringFields @('startedUtc','endedUtc')
 $validation=Read-AiwTestJson $RvPath -StringFields @('checkedUtc')
 $suite=Read-AiwTestJson $SuitePath -StringFields @('startedUtc','endedUtc')
 $g=$NativeGroup
 # The first row directly falsifies the retained Int64 FAILED-RV bypass.
 $bad=CloneEvidence $validation @('checkedUtc');$bad.outcome='FAIL'
 Reject {& $shared.ExportedCommands['Assert-AiwEvidenceRevalidation'] $bad $bad.original $g $bad.currentSnapshot $suite} '^RELEASE_CURRENT_REVALIDATION_SCALAR$' 'guard-rv-failed-int64-first-shared'
 Reject {& $local {param($v,$o,$g,$s,$w) Assert-AiwTestRevalidation $v $o $g $s $w -CurrentCoverage} $bad $bad.original $g $bad.currentSnapshot $suite} '^RELEASE_CURRENT_REVALIDATION_SCALAR$' 'guard-rv-failed-int64-first-local-dispatch'
 foreach($width in @('Int64','Int32')){
  $good=CloneEvidence $validation @('checkedUtc');$good.schemaVersion=if($width-ceq'Int32'){[int]2}else{[long]2};$good.originalRecordSchemaVersion=$good.schemaVersion
  $null=& $shared.ExportedCommands['Assert-AiwEvidenceRevalidation'] $good $good.original $g $good.currentSnapshot $suite
  Check ($true) ('guard-rv-valid-'+$width)
 }
 $rvRows=@(
  @{id='schema-one';change={param($v)$v.schemaVersion=1}},@{id='schema-string';change={param($v)$v.schemaVersion='2'}},
  @{id='kind';change={param($v)$v.executionKind='EXECUTED'}},@{id='wrong-string-group';change={param($v)$v.groupId='proof.other'}},
  @{id='reason';change={param($v)$v.reason='unproven'}},@{id='original-string';change={param($v)$v.originalRecordSchemaVersion='2'}},
  @{id='original-one';change={param($v)$v.originalRecordSchemaVersion=1}},@{id='original-null';change={param($v)$v.originalRecordSchemaVersion=$null}},
  @{id='derivation-shape';change={param($v)$v.derivations='unproven'}})
 foreach($row in $rvRows){$bad=CloneEvidence $validation @('checkedUtc');& $row.change $bad;Reject {& $shared.ExportedCommands['Assert-AiwEvidenceRevalidation'] $bad $bad.original $g $bad.currentSnapshot $suite} '^RELEASE_CURRENT_REVALIDATION_SCALAR$' ('guard-rv-'+$row.id)}
 $bad=CloneEvidence $validation @('checkedUtc');$bad.schemaVersion=1
 Reject {& $local {param($v,$o,$g,$s,$w) Assert-AiwTestRevalidation $v $o $g $s $w -CurrentCoverage} $bad $bad.original $g $bad.currentSnapshot $suite} '^RELEASE_CURRENT_REVALIDATION_SCALAR$' 'guard-suite3-rejects-rv1-local-dispatch'
 Reject {& $reader.ExportedCommands['Assert-AiwReleaseCurrentRevalidation'] $bad $bad.original $g $bad.currentSnapshot $suite} '^RELEASE_CURRENT_REVALIDATION_SCALAR$' 'guard-suite3-rejects-rv1-release-dispatch'
 $artifacts=& $local {param($r) Get-AiwTestLocalArtifacts $r $r.after} $record
 $null=& $shared.ExportedCommands['Assert-AiwEvidenceNativeRecord'] $record $g $record.after $artifacts -ForReuse
 Check ($true) 'guard-native-real-retained-baseline'
 function NativeArtifactsCopy {
  [pscustomobject]@{process=(CloneEvidence $artifacts.process @('startedUtc','endedUtc','creationUtc','processExitedUtc'));launch=(CloneEvidence $artifacts.launch @('startedUtc','creationUtc'));stdoutBytes=$artifacts.stdoutBytes;stderrBytes=$artifacts.stderrBytes;phaseBytes=$artifacts.phaseBytes;descriptorBytes=$artifacts.descriptorBytes;currentDescriptorBytes=$artifacts.currentDescriptorBytes}
 }
 foreach($width in @('Int64','Int32')){
  $good=CloneEvidence $record @('startedUtc','endedUtc');$a=NativeArtifactsCopy
  $good.producer.contractVersion=if($width-ceq'Int32'){[int]2}else{[long]2}
  $a.process.exitCode=if($width-ceq'Int32'){[int]0}else{[long]0}
  $a.process.pid=if($width-ceq'Int32'){[int]$a.process.pid}else{[long]$a.process.pid};$a.launch.pid=$a.process.pid
  $null=& $shared.ExportedCommands['Assert-AiwEvidenceNativeRecord'] $good $g $good.after $a -ForReuse
  Check ($true) ('guard-native-valid-typed-'+$width)
 }
 $nativeRows=@(
  @{id='producer-name';reason='TEST_PRODUCER_PROVENANCE';change={param($r,$a)$r.producer.name='Other'}},
  @{id='producer-version-string';reason='TEST_PRODUCER_PROVENANCE';change={param($r,$a)$r.producer.contractVersion='2'}},
  @{id='process-schema-one';reason='TEST_NATIVE_ENVIRONMENT_DRIFT';change={param($r,$a)$a.process.schemaVersion=1}},
  @{id='process-schema-string';reason='TEST_NATIVE_ENVIRONMENT_DRIFT';change={param($r,$a)$a.process.schemaVersion='2'}},
  @{id='launch-schema-one';reason='TEST_NATIVE_ENVIRONMENT_DRIFT';change={param($r,$a)$a.launch.schemaVersion=1}},
  @{id='launch-schema-string';reason='TEST_NATIVE_ENVIRONMENT_DRIFT';change={param($r,$a)$a.launch.schemaVersion='2'}},
  @{id='status-fail-int64-zero';reason='RELEASE_PROCESS_NOT_PASS';change={param($r,$a)$a.process.status='FAIL'}},
  @{id='exit-string';reason='RELEASE_PROCESS_NOT_PASS';change={param($r,$a)$a.process.exitCode='0'}},
  @{id='exit-null';reason='RELEASE_PROCESS_NOT_PASS';change={param($r,$a)$a.process.exitCode=$null}},
  @{id='exit-one';reason='RELEASE_PROCESS_NOT_PASS';change={param($r,$a)$a.process.exitCode=1}},
  @{id='process-pid-string';reason='RELEASE_CURRENT_EXECUTION_LAUNCH';change={param($r,$a)$a.process.pid=[string]$a.process.pid}},
  @{id='process-pid-zero';reason='RELEASE_CURRENT_EXECUTION_LAUNCH';change={param($r,$a)$a.process.pid=0}},
  @{id='launch-pid-string';reason='RELEASE_CURRENT_EXECUTION_LAUNCH';change={param($r,$a)$a.launch.pid=[string]$a.launch.pid}},
  @{id='launch-environment-names-scalar';reason='RELEASE_CURRENT_EXECUTION_LAUNCH';change={param($r,$a)$a.launch.environmentNames='scalar'}},
  @{id='launch-arguments-scalar';reason='RELEASE_CURRENT_EXECUTION_LAUNCH';change={param($r,$a)$a.launch.arguments='scalar'}},
  @{id='launch-raw-scalar';reason='RELEASE_CURRENT_EXECUTION_LAUNCH';change={param($r,$a)$a.launch.raw='scalar'}})
 foreach($row in $nativeRows){$bad=CloneEvidence $record @('startedUtc','endedUtc');$a=NativeArtifactsCopy;& $row.change $bad $a;Reject {& $shared.ExportedCommands['Assert-AiwEvidenceNativeRecord'] $bad $g $bad.after $a -ForReuse} ('^'+$row.reason+'$') ('guard-native-'+$row.id)}
 $definition=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
 $definitionRows=@('files','definitionGroupIds','wholeDefinition','includeCommonSets','steps','constructorPaths','version-string','version-two','version-null')
 foreach($name in $definitionRows){
  $d=Clone $definition;$q=$d.groups[0]
  switch($name){'files'{$q.behaviorInputs.files='bad'} 'definitionGroupIds'{$q.behaviorInputs.definitionGroupIds='bad'} 'wholeDefinition'{$q.behaviorInputs.wholeDefinition='bad'} 'includeCommonSets'{$q.behaviorInputs.includeCommonSets='bad'} 'steps'{$q.fixtureRecipe.steps='bad'} 'constructorPaths'{$q.fixtureRecipe.constructorPaths='bad'} 'version-string'{$q.fixtureRecipe.version='1'} 'version-two'{$q.fixtureRecipe.version=2} 'version-null'{$q.fixtureRecipe.version=$null}}
  $path=Join-Path $temp ('guard-definition-'+$name+'.json');Write-AiwTestJson $path $d
  Reject {Read-AiwTestGroupDefinition $path} '^TEST_GROUP_BEHAVIOR_CONTRACT$' ('guard-definition-'+$name)
 }
}
function TestManifestGuardContracts($Reader,$Manifest){
 $baseline=Clone $Manifest;$null=& $Reader.ExportedCommands['Assert-AiwReleaseManifestShape'] $baseline;Check ($true) 'guard-manifest-json-int64-baseline'
 $typed=Clone $Manifest;$typed.fileCount=[int]$typed.fileCount;$typed.totalBytes=[int]$typed.totalBytes;$null=& $Reader.ExportedCommands['Assert-AiwReleaseManifestShape'] $typed;Check ($true) 'guard-manifest-typed-int32-baseline'
 foreach($name in @('version','lifecycle','canonical','string-count','null-count')){
  $bad=Clone $Manifest;$bad.fileCount=[int]$bad.fileCount;$bad.totalBytes=[int]$bad.totalBytes
  switch($name){'version'{$bad.version='9.9.9'} 'lifecycle'{$bad.lifecycle='UNKNOWN'} 'canonical'{$bad.canonical='bad'} 'string-count'{$bad.fileCount='1'} 'null-count'{$bad.fileCount=$null}}
  Reject {& $Reader.ExportedCommands['Assert-AiwReleaseManifestShape'] $bad} '^RELEASE_MANIFEST_VALUES$' ('guard-manifest-'+$name)
 }
}
function TestLegacyExecutionGuardContracts($Reader,[string]$RecordPath,$Group,$Suite){
 $record=Read-AiwTestJson $RecordPath -StringFields @('startedUtc','endedUtc')
 $process=Read-AiwTestJson $record.processResult.path -StringFields @('startedUtc','endedUtc') -NullableStringFields @('creationUtc','processExitedUtc')
 $launch=Read-AiwTestJson (Join-Path (Split-Path -Parent $record.processResult.path) 'launch.json') -StringFields @('startedUtc') -NullableStringFields @('creationUtc')
 $null=& $Reader.ExportedCommands['Assert-AiwReleaseCurrentExecution'] $record $process $launch $Group $Suite;Check ($true) 'guard-legacy-json-int64-baseline'
 $p=CloneEvidence $process @('startedUtc','endedUtc','creationUtc','processExitedUtc');$l=CloneEvidence $launch @('startedUtc','creationUtc');$p.pid=[int]$p.pid;$l.pid=$p.pid;$p.exitCode=[int]0
 $null=& $Reader.ExportedCommands['Assert-AiwReleaseCurrentExecution'] $record $p $l $Group $Suite;Check ($true) 'guard-legacy-typed-int32-baseline'
 foreach($name in @('status','process-pid-string','process-pid-zero','launch-pid-string','exit-string','exit-null')){
  $p=CloneEvidence $process @('startedUtc','endedUtc','creationUtc','processExitedUtc');$l=CloneEvidence $launch @('startedUtc','creationUtc');$p.exitCode=[int]0;$p.pid=[int]$p.pid;$l.pid=$p.pid
  switch($name){'status'{$p.status='FAIL'} 'process-pid-string'{$p.pid=[string]$p.pid} 'process-pid-zero'{$p.pid=0} 'launch-pid-string'{$l.pid=[string]$l.pid} 'exit-string'{$p.exitCode='0'} 'exit-null'{$p.exitCode=$null}}
  Reject {& $Reader.ExportedCommands['Assert-AiwReleaseCurrentExecution'] $record $p $l $Group $Suite} '^RELEASE_CURRENT_EXECUTION_LAUNCH$' ('guard-legacy-'+$name)
 }
}
function TestLegacyPortableGuardContracts($Reader,[string]$VersionRoot,$Proof,$Suite){
 $definition=Read-AiwTestGroupDefinition (Join-Path $VersionRoot 'tests/test-groups.json');$group=$definition.groups[0]
 $index=Read-AiwTestJson (Join-Path $VersionRoot $Proof.proofBundleRef.path)
 $recordRef=@($Proof.groupRecordRefs|Where-Object groupId -CEQ $group.id)[0]
 $member=@($index.members|Where-Object path -CEQ $recordRef.path)[0]
 $baseline=& $Reader {param($v,$p) Get-AiwReleaseBundle $v $p} $VersionRoot $Proof
 $null=& $Reader {param($b,$id,$g,$s) Assert-AiwReleasePortableGroup $b $id $g -CurrentCoverage -Suite $s -ExecutionKind EXECUTED} $baseline $member.id $group $Suite
 Check ($true) 'guard-legacy-portable-real-json-baseline'
 foreach($mode in @('status','exit-string')){
  $target=Join-Path $temp ('legacy-portable-guard-'+$mode)
  if(Test-Path -LiteralPath $target){throw 'LEGACY_GUARD_FRESH_ROOT_REQUIRED'}
  # This private graph reader consumes definition/module/evidence inputs; it does not read the release manifest.
  Copy-AiwTestAllowlist $VersionRoot $target @((Get-AiwReleaseTreeMembers $VersionRoot)|Where-Object path -CNE 'RELEASE_MANIFEST.json'|ForEach-Object path)
  $idx=Read-AiwTestJson (Join-Path $target $Proof.proofBundleRef.path);$proofCopy=Clone $Proof
  $gm=@($idx.members|Where-Object id -CEQ $member.id)[0]
  $pa=@($idx.aliases|Where-Object{$_.ownerMemberId-ceq$gm.id-and$_.slot-ceq'/processResult'})[0]
  $pm=@($idx.members|Where-Object id -CEQ $pa.targetMemberId)[0]
  $p=Read-AiwTestJson (Join-Path $target $pm.path) -StringFields @('startedUtc','endedUtc') -NullableStringFields @('creationUtc','processExitedUtc')
  if($mode-ceq'status'){$p.status='FAIL'}else{$p.exitCode='0'}
  Put (Join-Path $target $pm.path) (($p|ConvertTo-Json -Depth 100 -Compress)+"`n");$pm.identity=Get-AiwTestFileIdentity (Join-Path $target $pm.path)
  $r=Read-AiwTestJson (Join-Path $target $gm.path) -StringFields @('startedUtc','endedUtc');$r.processResult.identity=$pm.identity;$pa.originalIdentity=$pm.identity
  Put (Join-Path $target $gm.path) (($r|ConvertTo-Json -Depth 100 -Compress)+"`n");$gm.identity=Get-AiwTestFileIdentity (Join-Path $target $gm.path)
  $sm=@($idx.members|Where-Object kind -CEQ CURRENT_SUITE)[0];$s=Read-AiwTestJson (Join-Path $target $sm.path) -StringFields @('startedUtc','endedUtc')
  @($s.records|Where-Object groupId -CEQ $group.id)[0].identity=$gm.identity
  foreach($a in $idx.aliases|Where-Object{$_.ownerMemberId-ceq$sm.id-and$_.targetMemberId-ceq$gm.id}){$a.originalIdentity=$gm.identity}
  Put (Join-Path $target $sm.path) (($s|ConvertTo-Json -Depth 100 -Compress)+"`n");$sm.identity=Get-AiwTestFileIdentity (Join-Path $target $sm.path)
  @($proofCopy.groupRecordRefs|Where-Object groupId -CEQ $group.id)[0].identity=$gm.identity;$proofCopy.currentSuiteRef.identity=$sm.identity
  Put (Join-Path $target $Proof.proofBundleRef.path) (($idx|ConvertTo-Json -Depth 100 -Compress)+"`n")
  $proofCopy.proofBundleRef.identity=Get-AiwTestFileIdentity (Join-Path $target $Proof.proofBundleRef.path)
  $proofCopy.proofBundleIdentity=(Get-AiwReleaseMemberFacts (@(@{path=$proofCopy.proofBundleRef.path;identity=$proofCopy.proofBundleRef.identity})+@($idx.members))).Canonical
  $bound=& $Reader {param($v,$p) Get-AiwReleaseBundle $v $p} $target $proofCopy
  Reject {& $Reader {param($b,$id,$g,$s) Assert-AiwReleasePortableGroup $b $id $g -CurrentCoverage -Suite $s -ExecutionKind EXECUTED} $bound $gm.id $group $s} '^RELEASE_PROCESS_NOT_PASS$' ('guard-legacy-portable-real-json-'+$mode)
 }
}


function TestActualTargetProducer {
 $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
 $actual=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
 $seed=Join-Path $temp 'target-seed';$controlRoot=Join-Path $temp 'target-control';$targetRoot=Join-Path $temp 'actual-target'
 $vp='framework/versions/2.0.0/'
 $files=@('VERSION.json','TOOLCHAIN.json','NORMATIVE_SURFACE_INVENTORY.json','EXECUTION_TARGET_SCHEMA.json','scripts/ExecutionTargetContext.psm1','scripts/ControlTransition.psm1','scripts/ProjectSourcePublication.psm1','scripts/StrictJsonInput.psm1','scripts/ReleaseValidation.psm1','scripts/TestEvidenceValidation.psm1','tests/test-groups.json','tests/run-framework-tests.ps1','tests/TestHarness.psm1','tests/TestNativeOutput.psm1','tests/TestGroupEvidence.psm1','tests/TestExecutionRuntime.psm1')
 Copy-AiwTestAllowlist $source $seed @($files|ForEach-Object{$vp+$_})
 $entry=$vp+'tests/actual-target-probe.ps1'
 Put (Join-Path $seed $entry) 'param([string]$ExpectedCwd);$ErrorActionPreference="Stop";if((Get-Location).Path-cne$ExpectedCwd){throw "WRONG_TARGET_CWD"};Write-Output "PASS|actual-target-native-cwd";Write-Output "RESULT|1/1 passed|scope=actual-target-probe"'
 $inventory=Read-AiwTestJson (Join-Path $seed ($vp+'NORMATIVE_SURFACE_INVENTORY.json'))
 $inventory.runtimeNormativeModules=@();$inventory.actionRequiredArtifacts=@();$inventory.explanationAndHistory=@();$inventory.schemaAndMechanicalInputs=@($files)+@('tests/actual-target-probe.ps1')
 Put (Join-Path $seed ($vp+'NORMATIVE_SURFACE_INVENTORY.json')) (($inventory|ConvertTo-Json -Depth 100 -Compress)+"`n")
 $group=[pscustomobject]@{id='actual.target';entry=$entry;arguments=@('-ExpectedCwd',$targetRoot);phase='PREPACKAGE';requiredFor=@('FULL');casePolicy='OBSERVED_NAMED_CASES';requiredCaseIds=@('actual-target-native-cwd');completionPattern='^RESULT\|1/1 passed\|scope=actual-target-probe$';dependencies=@($vp+'scripts/ExecutionTargetContext.psm1');unknownDependencies=@();alwaysFresh=$false;fixturePolicy='MECHANISM';tools=@('pwsh');groupContractVersion=1;behaviorInputs=[pscustomobject]@{files=@($vp+'scripts/ExecutionTargetContext.psm1');definitionGroupIds=@();wholeDefinition=$false;includeCommonSets=$false};fixtureRecipe=[pscustomobject]@{version=1;steps=@('real local Git worktree','actual observer before and after native process');constructorPaths=@()};environmentPolicy=[pscustomobject]@{mode='EFFECTIVE_TOOLS';influentialVariables=@('COMSPEC','PSModulePath');negativeToolLookups=@()};locationPolicy=[pscustomobject]@{mode='EXACT';mappings=@();conditions=@()}}
 $definition=Clone $actual;$definition.mechanismVersionPaths=@();$definition.groups=@($group);$definition.sourceViewPaths=@($files|ForEach-Object{$vp+$_})+@($entry)
 Put (Join-Path $seed ($vp+'tests/test-groups.json')) (($definition|ConvertTo-Json -Depth 100 -Compress)+"`n")
 $null=New-AiwTestSourceView $seed $controlRoot $definition
 $task='.ai-workspace/tasks/active/TARGET-PRODUCER.md';$taskId='TARGET-PRODUCER';$configPath=Join-Path $controlRoot '.ai-workspace/project.json'
 Put $configPath (([ordered]@{schemaVersion=7;id='actual-target-producer';displayName='Synthetic target producer';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('private.txt');frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}|ConvertTo-Json -Depth 50 -Compress)+"`n")
 Put (Join-Path $controlRoot '.ai-workspace/controller.json') '{"schemaVersion":1,"projectId":"actual-target-producer","controllerId":"owner","controllerEpoch":1,"state":"CURRENT"}'
 $taskText="# TARGET-PRODUCER - synthetic target evidence`n- Owner: owner`n- Work route: actor=writer; role=EXECUTOR; phase=VERIFY`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
 Put (Join-Path $controlRoot $task) $taskText
 function TargetGit([string]$Root,[string[]]$Arguments){
  $out=@(& git -C $Root @Arguments 2>&1|ForEach-Object{[string]$_})
  if($LASTEXITCODE-ne0){throw ('ACTUAL_TARGET_FIXTURE_GIT|'+($out-join';'))}
  return ($out-join"`n").Trim()
 }
 $null=TargetGit $controlRoot @('init','-q');$null=TargetGit $controlRoot @('config','core.autocrlf','false')
 $closure=Read-AiwTestJson (Join-Path $controlRoot 'source-inputs.json')
 $tracked=@($closure.inputs.path)+@($closure.syntheticInputs.path)+@('source-inputs.json','.ai-workspace/project.json','.ai-workspace/controller.json',$task)
 $null=TargetGit $controlRoot (@('add','--')+$tracked)
 $null=TargetGit $controlRoot @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','Exact synthetic producer baseline')
 $head=TargetGit $controlRoot @('rev-parse','HEAD')
 $null=TargetGit $controlRoot @('worktree','add','-q','-b','actual-target-producer',$targetRoot,'HEAD')
 Put (Join-Path $targetRoot '.ai-workspace/project.json') '{"shadow":"not authority"}'
 $decisionPath=Join-Path $controlRoot '.ai-workspace/runtime/TARGET-PRODUCER/writer/selection.txt';Put $decisionPath 'Synthetic selection only, no actual host worktree claim.'
 $descriptorPath=Join-Path $controlRoot '.ai-workspace/runtime/TARGET-PRODUCER/writer/target.json'
 $descriptor=[ordered]@{schemaVersion=1;kind='EXECUTION_TARGET';projectId='actual-target-producer';taskId=$taskId;controlRoot=$controlRoot;targetKind='GIT_WORKTREE';targetRoot=$targetRoot;gitBinding=[ordered]@{commonGitDir=[IO.Path]::GetFullPath((TargetGit $controlRoot @('rev-parse','--path-format=absolute','--git-common-dir')));worktreeGitDir=[IO.Path]::GetFullPath((TargetGit $targetRoot @('rev-parse','--absolute-git-dir')));gitTop=$targetRoot;branch='actual-target-producer';baselineCommit=$head};selectionDecisionRef=[ordered]@{path=$decisionPath;identity=(Get-AiwTestFileIdentity $decisionPath)};hostWorktreeRef=$null}
 Put $descriptorPath (($descriptor|ConvertTo-Json -Depth 60 -Compress)+"`n")
 $ref=[pscustomobject]@{path=$descriptorPath;identity=(Get-AiwTestFileIdentity $descriptorPath)}
 Put (Join-Path $controlRoot $task) ($taskText+'- Execution target: '+$descriptorPath+'#'+$ref.identity+"`n")
 $state=[pscustomobject]@{branch='actual-target-producer';head=$head.ToUpperInvariant()}
 $definitionPath=Join-Path $targetRoot ($vp+'tests/test-groups.json')
 $opts=[ordered]@{ControlRoot=$controlRoot;TaskPath=(Join-Path $controlRoot $task);ExecutionTargetRef=$ref;ExpectedTargetState=$state}
 $producer=Get-Module TestGroupEvidence
 $originalContext=& $producer {param($r,$o) Get-TestExecutionTarget $r $o '' '' $null $null} $targetRoot $opts
 $before=Get-AiwTestDependencySnapshot $targetRoot $definitionPath $definition $group $opts
 Check ($originalContext.targetObservation.observedUtc-is[string]-and$before.facts.executionContext.targetObservation.observedUtc-is[string]-and$before.facts.executionContext.targetObservation.observedUtc-ceq$originalContext.targetObservation.observedUtc) 'producer-snapshot-preserves-exact-original-observer-time-string'
 Check ((Get-AiwTestFileIdentity (Join-Path $controlRoot $entry))-ceq(Get-AiwTestFileIdentity (Join-Path $targetRoot $entry))) 'producer-wrong-root-counterexample-has-identical-actual-candidate-bytes'
 Reject {Get-AiwTestDependencySnapshot $controlRoot (Join-Path $controlRoot ($vp+'tests/test-groups.json')) $definition $group $opts} '^TEST_EXECUTION_TARGET_SOURCE_ROOT$' 'producer-equal-control-bytes-cannot-substitute-target-root'
 $reset=Join-Path $temp 'actual-target-native-reset';$null=[IO.Directory]::CreateDirectory($reset)
 $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) @(Get-AiwTestGroupArguments $targetRoot $group $opts) -WorkingDirectory $targetRoot -EvidenceDirectory (Join-Path $rawRoot 'actual-target-native') -GroupId $group.id -EvidenceContractVersion 2
 $after=Get-AiwTestDependencySnapshot $targetRoot $definitionPath $definition $group $opts
 Check ($native.Code-eq0-and$native.Record.command.cwd-ceq$targetRoot-and$before.facts.executionContext.targetKind-ceq'GIT_WORKTREE'-and$before.identity-ceq$after.identity) 'producer-real-observer-and-native-worktree-cwd-ignore-shadow-authority'
 $cleanup=[ordered]@{status='CLEAN';root=$reset;entries=@();workers=@()}
 $recordPath=Join-Path $rawRoot 'actual-target-executed.json'
 $record=Complete-AiwTestGroupEvidence $recordPath $group $before $after $native $cleanup
 Check ($record.outcome-ceq'PASS'-and(Assert-AiwTestGroupEvidence $record $group $after)) 'producer-actual-target-record-consumed-by-original-shared-native-reader'
 $shared=Import-Module (Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1') -PassThru
 foreach($time in @([datetime]::Parse($originalContext.targetObservation.observedUtc,[Globalization.CultureInfo]::InvariantCulture),'2026-10-19T12:34:56')){
  $bad=CloneEvidence $before.facts.executionContext @();$bad.targetObservation.observedUtc=$time
  Reject {& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $bad ([IO.File]::ReadAllBytes($descriptorPath))} '^RELEASE_EVIDENCE_TIME\|target-observed$' 'producer-original-reader-rejects-non-string-or-unzoned-target-time'
 }
 Reject {Get-AiwTestDependencySnapshot $targetRoot $definitionPath $definition $group ([ordered]@{}) -ControlRoot $controlRoot} 'INPUT_COMBINATION' 'producer-target-optional-inputs-are-an-atomic-combination'
 $logical=Clone $group;$logical.locationPolicy.mode='LOGICAL_ROOT'
 Reject {Get-AiwTestDependencySnapshot $targetRoot $definitionPath $definition $logical $opts} 'LOGICAL_ROOT_DENIED' 'producer-worktree-cannot-substitute-logical-root-equivalence'
 $shadow=Clone $group;$shadow.dependencies=@('.ai-workspace/project.json')
 Reject {Get-AiwTestDependencySnapshot $targetRoot $definitionPath $definition $shadow $opts} 'CONTROL_OBJECT_DENIED' 'producer-target-shadow-control-is-not-a-candidate-input'
 $badState=Clone $opts;$badState.ExpectedTargetState.head='A'*40
 Reject {Get-AiwTestDependencySnapshot $targetRoot $definitionPath $definition $group $badState} 'HEAD_DRIFT' 'producer-stale-expected-head-rejects-before-native-run'
 $null=TargetGit $targetRoot @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','Actual isolated drift counterexample')
 Reject {Get-AiwTestDependencySnapshot $targetRoot $definitionPath $definition $group $opts} 'HEAD_DRIFT' 'producer-reobserves-git-on-each-call-rather-than-trusting-held-context'
 Write-AiwTestJson (Join-Path $rawRoot 'actual-target-producer-ceiling.json') @{kind='ACTUAL_LOCAL_WORKTREE_OBSERVER_AND_NATIVE_PRODUCER';controlRoot=$controlRoot;executionRoot=$targetRoot;recordRef=@{path=$recordPath;identity=(Get-AiwTestFileIdentity $recordPath)};actualGitObservation=$true;actualTargetNativeExecution=$true;authorizationGranted=$false;hostWorktreeManagementProven=$false;formalSourceOrReleaseQualification=$false}
}

function TestExecutionContextContracts {
 # Synthetic metadata shape fixtures only: no Git observation, worktree or target run.
 $shared=Import-Module (Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1') -PassThru
 $same=[pscustomobject]@{schemaVersion=1;targetKind='SAME_ROOT';controlRoot=$temp;executionRoot=$temp;executionTargetRef=$null;targetObservation=$null}
 $null=& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $same
 Check ($true) 'context-same-root-explicit-null-target-fields'
 foreach($fault in @('TARGET_REF','ROOT','EXTRA','STRING_VERSION')){
  $bad=Clone $same
  switch($fault){'TARGET_REF'{$bad.executionTargetRef=@{path='fixture';identity=('1|'+('A'*64))}} 'ROOT'{$bad.executionRoot=Join-Path $temp 'other'} 'EXTRA'{$bad|Add-Member extra $true} 'STRING_VERSION'{$bad.schemaVersion='1'}}
  Reject {& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $bad} 'TEST_EXECUTION_CONTEXT|RELEASE_FIELDS' ('context-same-root-reject-'+$fault)
 }
 $control=Join-Path $temp 'synthetic-control';$target=Join-Path $temp 'synthetic-target';$common=Join-Path $temp 'synthetic-common';$gitdir=Join-Path $common 'synthetic-worktree'
 $fixtureRef=@{path='shape-fixture-only';identity=('1|'+('A'*64))}
 $descriptor=[pscustomobject]@{schemaVersion=1;kind='EXECUTION_TARGET';projectId='synthetic-shape';taskId='synthetic-shape';controlRoot=$control;targetKind='GIT_WORKTREE';targetRoot=$target;gitBinding=@{commonGitDir=$common;worktreeGitDir=$gitdir;gitTop=$target;branch='synthetic-shape';baselineCommit=('0'*40)};selectionDecisionRef=$fixtureRef;hostWorktreeRef=$fixtureRef}
 $bytes=[Text.Encoding]::UTF8.GetBytes(($descriptor|ConvertTo-Json -Depth 100 -Compress));$identity=(& $shared.ExportedCommands['Get-AiwEvidenceByteIdentity'] $bytes)
 $observation=[pscustomobject]@{schemaVersion=1;descriptorIdentity=$identity;commonGitDir=$common;worktreeGitDir=$gitdir;gitTop=$target;branch='synthetic-shape';head=('0'*40);observedUtc=[DateTime]::UtcNow.ToString('o');overridesAbsent=$true}
 $ctx=[pscustomobject]@{schemaVersion=1;targetKind='GIT_WORKTREE';controlRoot=$control;executionRoot=$target;executionTargetRef=[pscustomobject]@{path='synthetic-descriptor.json';identity=$identity};targetObservation=$observation}
 $null=& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $ctx $bytes
 Check ($true) 'context-git-tagged-shape-binds-original-descriptor-bytes-only'
 $later=CloneEvidence $ctx @();$later.targetObservation.observedUtc=$observation.observedUtc;$later.targetObservation.head='1'*40;$later.targetObservation.branch='authorized-next-branch'
 $null=& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $later $bytes
 Check ($true) 'context-immutable-initial-baseline-does-not-rewrite-later-head-or-branch'
 $unmanaged=Clone $descriptor;$unmanaged.hostWorktreeRef=$null;$unmanagedBytes=[Text.Encoding]::UTF8.GetBytes(($unmanaged|ConvertTo-Json -Depth 100 -Compress))
 $plain=CloneEvidence $later @();$plain.targetObservation.observedUtc=$observation.observedUtc;$plain.executionTargetRef.identity=& $shared.ExportedCommands['Get-AiwEvidenceByteIdentity'] $unmanagedBytes;$plain.targetObservation.descriptorIdentity=$plain.executionTargetRef.identity
 $null=& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $plain $unmanagedBytes
 Check ($true) 'context-no-host-management-claim-allows-explicit-null-host-reference'
 foreach($fault in @('DESCRIPTOR_BYTES','BASELINE_FORMAT','HOST_REF')){
  $bad=CloneEvidence $plain @();$bad.targetObservation.observedUtc=$observation.observedUtc;$raw=$unmanagedBytes
  if($fault-ceq'DESCRIPTOR_BYTES'){$raw=[Text.Encoding]::UTF8.GetBytes(([Text.Encoding]::UTF8.GetString($raw)+' '))}else{
   $badDescriptor=Clone $unmanaged;if($fault-ceq'BASELINE_FORMAT'){$badDescriptor.gitBinding.baselineCommit='invalid'}else{$badDescriptor.hostWorktreeRef=[pscustomobject]@{path='claimed';identity='invalid'}}
   $raw=[Text.Encoding]::UTF8.GetBytes(($badDescriptor|ConvertTo-Json -Depth 100 -Compress));$bad.executionTargetRef.identity=& $shared.ExportedCommands['Get-AiwEvidenceByteIdentity'] $raw;$bad.targetObservation.descriptorIdentity=$bad.executionTargetRef.identity
  }
  Reject {& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $bad $raw} 'TEST_EXECUTION_TARGET|TEST_REFERENCE' ('context-separate-initial-state-reject-'+$fault.ToLowerInvariant())
 }

 foreach($fault in @('MISSING_BYTES','OVERRIDES','COMMON','DESCRIPTOR_TYPE')){
  $bad=CloneEvidence $ctx @();$bad.targetObservation.observedUtc=$observation.observedUtc;$raw=$bytes
  switch($fault){'MISSING_BYTES'{$raw=$null} 'OVERRIDES'{$bad.targetObservation.overridesAbsent=$false} 'COMMON'{$bad.targetObservation.commonGitDir=Join-Path $common 'wrong'} 'DESCRIPTOR_TYPE'{$d=Clone $descriptor;$d.schemaVersion='1';$raw=[Text.Encoding]::UTF8.GetBytes(($d|ConvertTo-Json -Depth 100 -Compress));$bad.executionTargetRef.identity=(& $shared.ExportedCommands['Get-AiwEvidenceByteIdentity'] $raw);$bad.targetObservation.descriptorIdentity=$bad.executionTargetRef.identity}}
  Reject {& $shared.ExportedCommands['Assert-AiwEvidenceExecutionContext'] $bad $raw} 'TEST_EXECUTION_TARGET' ('context-git-shape-reject-'+$fault)
 }
 $wire=@{schemaVersion=2;executionKind='EXECUTED';executionContext=$ctx;before=@{facts=@{executionContext=$ctx}};after=@{facts=@{executionContext=$ctx}}}|ConvertTo-Json -Depth 100 -Compress
 $restored=& $shared.ExportedCommands['Restore-AiwEvidenceContextStrings'] $wire ($wire|ConvertFrom-Json -Depth 100)
 Check ($restored.executionContext.targetObservation.observedUtc-is[string]-and$restored.before.facts.executionContext.targetObservation.observedUtc-ceq$observation.observedUtc) 'context-observation-preserves-nested-original-string-token'
 Write-AiwTestJson (Join-Path $rawRoot 'execution-context-shape-ceiling.json') @{kind='SYNTHETIC_METADATA_SHAPE_ONLY';actualGitObservation=$false;targetExecution=$false;laterW2W4Required=$true}
}
function TestLegacyCurrentCoverage([string]$Seed,$Definition,$Reader){
 # Same finite literal fixture, original schema2/suite2/record1/proof2 branch.
 $legacy=Join-Path $temp 'legacy2-source';$null=New-AiwTestSourceView $Seed $legacy $Definition
 $legacyV=Join-Path $legacy 'framework/versions/2.0.0';$legacyD=Clone $Definition;$legacyD.schemaVersion=2
 foreach($group in $legacyD.groups){foreach($name in @('groupContractVersion','behaviorInputs','fixtureRecipe','environmentPolicy','locationPolicy')){$group.PSObject.Properties.Remove($name)}}
 Put (Join-Path $legacyV 'tests/test-groups.json') (($legacyD|ConvertTo-Json -Depth 100 -Compress)+"`n")
 if($FocusedReviewRepairOnly){
  # This legal old proof1 fixture has only the explicit literal sentinel reads.
  # The integration remains alwaysFresh; normal CurrentCoverage retains unknowns.
  foreach($g in $legacyD.groups){$g.unknownDependencies=@()}
  Put (Join-Path $legacyV 'tests/test-groups.json') (($legacyD|ConvertTo-Json -Depth 100 -Compress)+"`n")
  Check ($legacyD.groups[2].alwaysFresh-and$legacyD.groups[2].unknownDependencies.Count-eq0) 'legacy-proof1-positive-has-closed-literal-inputs-and-retains-fresh-integration'
 }
 $evidence=Join-Path $rawRoot 'legacy2-groups';$owned=Join-Path $temp 'legacy2-owned'
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $legacyV 'tests/run-framework-tests.ps1'),'-EvidenceDirectory',$evidence,'-SourceViewPath',$owned) -WorkingDirectory $legacy -EvidenceDirectory (Join-Path $rawRoot 'legacy2-native') -GroupId 'finite-legacy2-current-reader'
 if($run.Code-ne0){Write-Output ('LEGACY2_DIAGNOSTIC|'+$run.StdoutText+'|'+$run.StderrText)}
 Check ($run.Code-eq0) 'legacy2-default-runner-retains-original-native-and-suite-branch'
 $path=Join-Path $evidence 'prepackage-proof/validation-proof.json';$proof=Read-AiwTestJson $path;$bundle=Split-Path -Parent $path
 $suite=Read-AiwTestJson (Join-Path $evidence 'suite.json') -StringFields @('startedUtc','endedUtc');$index=Read-AiwTestJson (Join-Path $bundle $proof.proofBundleRef.path)
 Check ($proof.schemaVersion-eq2-and$suite.schemaVersion-eq2-and$index.schemaVersion-eq1-and@($suite.records|ForEach-Object{(Read-AiwTestJson $_.path).schemaVersion}|Where-Object{$_-ne1}).Count-eq0) 'legacy2-original-shapes-stay-explicit-without-new-fields'
 Copy-AiwTestAllowlist $bundle $legacyV @((Get-AiwReleaseTreeMembers (Join-Path $bundle 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
 $sourceResult=& $Reader.ExportedCommands['Assert-AiwReleaseProof'] $legacyV ([pscustomobject]@{validationProof=$proof}) -SourceRoot $legacy
 Check ($sourceResult.Mode-ceq'CURRENT_GROUP_COVERAGE') 'legacy2-current-source-reader-still-accepts-original-graph'
 $stage=Join-Path $temp 'legacy2-stage';$moved=Join-Path $temp 'legacy2-moved';$null=New-AiwTestSourceView $legacy $stage $legacyD
 $stageV=Join-Path $stage 'framework/versions/2.0.0';Copy-AiwTestAllowlist $bundle $stageV @((Get-AiwReleaseTreeMembers (Join-Path $bundle 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
 if([IO.Path]::GetDirectoryName($stage)-cne$temp-or[IO.Path]::GetDirectoryName($moved)-cne$temp){throw 'LEGACY2_OWNED_MOVE_SCOPE'};[IO.Directory]::Move($stage,$moved)
 $portable=& $Reader.ExportedCommands['Assert-AiwReleaseProof'] (Join-Path $moved 'framework/versions/2.0.0') ([pscustomobject]@{validationProof=$proof}) -RuntimeRoot $moved
 Check ($portable.Mode-ceq'CURRENT_GROUP_COVERAGE'-and-not(Test-Path -LiteralPath $stage)) 'legacy2-current-portable-reader-still-accepts-moved-original-graph'
 if($FocusedReviewRepairOnly){
  $suitePath=Join-Path $evidence 'suite.json'
  $destination=Join-Path $rawRoot 'must-not-export-suite2-proof3'
  Reject {Export-AiwTestPrepackageBundle $suitePath $destination -ProofSchemaVersion 3} '^TEST_BUNDLE_VERSION_MISMATCH$' 'direct-export-reject-suite2-proof3'
  Check (-not(Test-Path -LiteralPath $destination)) 'direct-export-suite2-proof3-no-output-created'
  foreach($version in @(1,2)){
   $destination=Join-Path $rawRoot ('direct-export-suite2-proof'+$version)
   $export=if($version-eq1){Export-AiwTestPrepackageBundle $suitePath $destination}else{Export-AiwTestPrepackageBundle $suitePath $destination -ProofSchemaVersion $version}
   $exportProof=Read-AiwTestJson $export.ProofPath
   $consume=Join-Path $temp ('legacy2-export-consumer-'+$version);$null=New-AiwTestSourceView $legacy $consume $legacyD;$consumeV=Join-Path $consume 'framework/versions/2.0.0'
   Copy-AiwTestAllowlist $export.BundleRoot $consumeV @((Get-AiwReleaseTreeMembers (Join-Path $export.BundleRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
   $result=& $Reader.ExportedCommands['Assert-AiwReleaseProof'] $consumeV ([pscustomobject]@{validationProof=$exportProof}) -SourceRoot $consume
   Check ($exportProof.schemaVersion-eq$version) ('direct-export-legal-suite2-proof'+$version+'-source-reader')
   $moved=$consume+'-moved';if([IO.Path]::GetDirectoryName($consume)-cne$temp){throw 'LEGACY_EXPORT_MOVE_SCOPE'};[IO.Directory]::Move($consume,$moved)
   $result=& $Reader.ExportedCommands['Assert-AiwReleaseProof'] (Join-Path $moved 'framework/versions/2.0.0') ([pscustomobject]@{validationProof=$exportProof}) -RuntimeRoot $moved
   Check ($true) ('direct-export-legal-suite2-proof'+$version+'-moved-portable-reader')
  }
 }
 TestLegacyExecutionGuardContracts $Reader $suite.records[0].path $legacyD.groups[0] $suite
 TestLegacyPortableGuardContracts $Reader $legacyV $proof $suite
 $badRecord=Read-AiwTestJson $suite.records[0].path -StringFields @('startedUtc','endedUtc');$badRecord.schemaVersion=2
 $recordPath=Join-Path $rawRoot 'legacy2-crossed-native2.json';Write-AiwTestJson $recordPath $badRecord
 $cross=CloneEvidence $suite @('startedUtc','endedUtc');$cross.records[0].path=$recordPath;$cross.records[0].identity=Get-AiwTestFileIdentity $recordPath
 $crossPath=Join-Path $rawRoot 'legacy2-crossed-suite.json';Write-AiwTestJson $crossPath $cross
 Reject {Assert-AiwTestSuiteEvidence $crossPath $owned (Join-Path $owned 'framework/versions/2.0.0/tests/test-groups.json') -CurrentCoverage} '^TEST_EXECUTION_SUITE_VERSION_MISMATCH$' 'guard-suite2-rejects-native2-before-dispatch'
}
function TestCurrentCoverage {
 param([switch]$FinalSuiteAndOwnershipOnly)
 $fixtureContract=$FixtureContractOnly-or$PublicSuiteConsumerContractOnly
 TestExecutionContextContracts
 if(-not($FixtureContractOnly-or$PublicSuiteConsumerContractOnly-or$FocusedReviewRepairOnly-or$FinalSuiteAndOwnershipOnly-or$FailureTransportOnly-or$WorkerCompletionOnly)){TestActualTargetProducer}
 # The complete required set below is a synthetic mechanism fixture. All child
 # commands, natural failures, repair, revalidations and reader calls are real.
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 if($reader.Path-cne(Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../scripts'))) 'ReleaseValidation.psm1')){throw 'COVERAGE_READER_MODULE_PATH'}
 foreach($exportName in @('Get-AiwReleaseTreeMembers','Assert-AiwReleaseProof','Get-AiwReleaseQualification','Get-AiwReleaseMemberFacts','Get-AiwReleaseByteIdentity')){if(-not$reader.ExportedCommands.ContainsKey($exportName)-or$reader.ExportedCommands[$exportName].Module.Path-cne$reader.Path){throw ('COVERAGE_READER_EXPORT_OWNER|'+$exportName)}}
 Check ($true) 'current-reader-five-exports-owned-before-source-view'
 $actualSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'));$actualDefinition=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
 $sample=Join-Path $temp 'coverage-seed'
 $coverageVersionPaths=@('VERSION.json','TOOLCHAIN.json','ADOPTION_PROFILE.json','LOAD_MANIFEST.json','NORMATIVE_SURFACE_INVENTORY.json','tests/test-groups.json','tests/run-framework-tests.ps1','tests/run-framework-tests-summary.ps1','tests/TestHarness.psm1','tests/TestNativeOutput.psm1','tests/TestGroupEvidence.psm1','tests/TestExecutionRuntime.psm1','scripts/TestEvidenceValidation.psm1','scripts/ReleaseValidation.psm1','scripts/StrictJsonInput.psm1')
 $coverageRootPaths=@(@($actualDefinition.rootAdoptionPaths)+@($actualDefinition.maintenancePaths)+@('README.md','LICENSE')|Sort-Object -Unique)
 Copy-AiwTestAllowlist $actualSource $sample @(@($coverageVersionPaths|ForEach-Object{'framework/versions/2.0.0/'+$_})+$coverageRootPaths)
 $sampleTests=Join-Path $sample 'framework/versions/2.0.0/tests';$version=Join-Path $sample 'framework/versions/2.0.0'
 # Explicit replacements affect only existing JSON in mutable fixture copies.
 # Production create-only evidence writes and original raw records stay intact.
 function ReplaceCoverageFixtureJson([string]$Path,$Value){
  $full=Assert-AiwTestPath $Path
  $fixtureManifestPath=[IO.Path]::GetFullPath((Join-Path $version 'RELEASE_MANIFEST.json'))
  $fixtureBundleRoot=[IO.Path]::GetFullPath((Join-Path $version 'validation-evidence/prepackage'))+[IO.Path]::DirectorySeparatorChar
  $fixtureOwnerPath=[IO.Path]::GetFullPath(($stable+'.owner.json'))
  $bundleJson=$full.StartsWith($fixtureBundleRoot,[StringComparison]::OrdinalIgnoreCase)-and[IO.Path]::GetExtension($full)-ceq'.json'
  if($full-cne$fixtureManifestPath-and-not$bundleJson-and$full-cne$fixtureOwnerPath){throw 'COVERAGE_FIXTURE_REPLACE_SCOPE'}
  if(-not[IO.File]::Exists($full)){throw 'COVERAGE_FIXTURE_REPLACE_EXISTING_REQUIRED'}
  Put $full (($Value|ConvertTo-Json -Depth 100 -Compress)+"`n")
 }
 $aEntry='framework/versions/2.0.0/tests/coverage-a.ps1';$bEntry='framework/versions/2.0.0/tests/coverage-b.ps1';$iEntry='framework/versions/2.0.0/tests/coverage-integration.ps1';$aValue='framework/versions/2.0.0/tests/coverage-a.txt';$bValue='framework/versions/2.0.0/tests/coverage-b.txt'
 function New-CoverageNativeBody([string]$Body){
  return 'Import-Module (Join-Path $PSScriptRoot "TestNativeOutput.psm1");Initialize-AiwTestNativeOutput;$ErrorActionPreference="Stop";try{'+$Body+'}catch{$failure=$_;[Console]::Error.WriteLine(([ordered]@{status="FAIL";reason=[string]$failure.Exception.Message;scriptStackTrace=[string]$failure.ScriptStackTrace;fullyQualifiedErrorId=[string]$failure.FullyQualifiedErrorId}|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii));exit 1}'
 }
 Put (Join-Path $sample $aEntry) (New-CoverageNativeBody 'if([IO.File]::ReadAllText((Join-Path $PSScriptRoot "coverage-a.txt"))-cne"A-sentinel"){throw "A_SENTINEL_FAILURE"};Write-Output "PASS|coverage-a";Write-Output "RESULT|1/1 passed|scope=coverage-a"')
 Put (Join-Path $sample $bEntry) (New-CoverageNativeBody 'if([IO.File]::ReadAllText((Join-Path $PSScriptRoot "coverage-b.txt"))-cne"A-sentinel:repaired"){throw "NATURAL_B_FAILURE"};Write-Output "PASS|coverage-b";Write-Output "RESULT|1/1 passed|scope=coverage-b"')
 Put (Join-Path $sample $iEntry) (New-CoverageNativeBody '$a=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "coverage-a.txt"));$b=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "coverage-b.txt"));if($a-cne"A-sentinel"-or$b-cne($a+":repaired")){throw "AB_RELATION_FAILURE"};Write-Output "PASS|coverage-integration";Write-Output "RESULT|1/1 passed|scope=coverage-integration"')
 Put (Join-Path $sample $aValue) 'A-sentinel'
 Put (Join-Path $sample $bValue) 'broken'
 $inventory=Read-AiwTestJson (Join-Path $version 'NORMATIVE_SURFACE_INVENTORY.json');$inventory.runtimeNormativeModules=@();$inventory.actionRequiredArtifacts=@();$inventory.explanationAndHistory=@();$inventory.schemaAndMechanicalInputs=@($coverageVersionPaths)+@('tests/coverage-a.ps1','tests/coverage-b.ps1','tests/coverage-integration.ps1','tests/coverage-a.txt','tests/coverage-b.txt');Put (Join-Path $version 'NORMATIVE_SURFACE_INVENTORY.json') (($inventory|ConvertTo-Json -Depth 100 -Compress)+"`n")
 $d=Read-AiwTestJson (Join-Path $sampleTests 'test-groups.json');$d.mechanismVersionPaths=@();$d.groups=@()
 foreach($spec in @(@{id='proof.a';entry=$aEntry;case='coverage-a';deps=@($aValue);fresh=$false},@{id='proof.b';entry=$bEntry;case='coverage-b';deps=@($bValue);fresh=$false},@{id='integration.full-source';entry=$iEntry;case='coverage-integration';deps=@($aValue,$bValue);fresh=$true})){
  $d.groups+=@{id=$spec.id;entry=$spec.entry;arguments=@();phase='PREPACKAGE';requiredFor=@('FULL');casePolicy='OBSERVED_NAMED_CASES';requiredCaseIds=@($spec.case);completionPattern=('^RESULT\|1/1 passed\|scope='+$spec.case+'$');dependencies=$spec.deps;unknownDependencies=@(if($spec.fresh){'synthetic dynamic A/B integration relationship remains conservatively unclosed'});alwaysFresh=$spec.fresh;fixturePolicy='MECHANISM';tools=@('pwsh')}
 }
 foreach($g in $d.groups){
  $g.groupContractVersion=1
  $g.behaviorInputs=@{files=@($g.dependencies);definitionGroupIds=@();wholeDefinition=$false;includeCommonSets=$false}
  $g.fixtureRecipe=@{version=1;steps=@('read literal sentinel files','emit named case and completion');constructorPaths=@()}
  $g.environmentPolicy=@{mode='EFFECTIVE_TOOLS';influentialVariables=@('COMSPEC','PSModulePath');negativeToolLookups=@()}
  $g.locationPolicy=@{mode='EXACT';mappings=@();conditions=@()}
 }
 $d.sourceViewPaths=@($coverageRootPaths)+@($inventory.schemaAndMechanicalInputs|ForEach-Object{'framework/versions/2.0.0/'+$_})
 Put (Join-Path $sampleTests 'test-groups.json') (($d|ConvertTo-Json -Depth 100 -Compress)+"`n")
 if($fixtureContract){Put (Join-Path $sample 'owned-undeclared-seed.txt') 'Unlisted owned input must not flow into the fixture.'}
 $seed=$sample;$sample=Join-Path $temp 'coverage-source';$null=New-AiwTestSourceView $seed $sample $d
 $sampleTests=Join-Path $sample 'framework/versions/2.0.0/tests';$version=Join-Path $sample 'framework/versions/2.0.0'
 if(-not($fixtureContract-or$FocusedReviewRepairOnly-or$FailureTransportOnly-or$WorkerCompletionOnly)){
  $policyGroup=Clone $d.groups[0];$policyDefinitionPath=Join-Path $sampleTests 'test-groups.json';$policyOptions=[ordered]@{}
  $policyBase=Get-AiwTestDependencySnapshot $sample $policyDefinitionPath $d $policyGroup $policyOptions
  $oldPath=$env:PATH;$oldTemp=$env:TEMP;$oldTmp=$env:TMP;$policyTools=Join-Path $temp 'policy-tools';$null=[IO.Directory]::CreateDirectory($policyTools)
  try{
   $env:PATH=$policyTools+[IO.Path]::PathSeparator+$oldPath;$env:TEMP=$policyTools;$env:TMP=$policyTools
   $irrelevant=Get-AiwTestDependencySnapshot $sample $policyDefinitionPath $d $policyGroup $policyOptions
   Check ($irrelevant.facts.behaviorContractIdentity-ceq$policyBase.facts.behaviorContractIdentity-and$irrelevant.identity-cne$policyBase.identity) 'effective-tools-ignore-irrelevant-path-temp-but-retain-raw-facts'
   $strict=Clone $policyGroup;$strict.environmentPolicy.mode='EXACT'
   $strictChanged=Get-AiwTestDependencySnapshot $sample $policyDefinitionPath $d $strict $policyOptions
   $env:PATH=$oldPath;$env:TEMP=$oldTemp;$env:TMP=$oldTmp
   $strictOriginal=Get-AiwTestDependencySnapshot $sample $policyDefinitionPath $d $strict $policyOptions
   Check ($strictOriginal.facts.behaviorContractIdentity-cne$strictChanged.facts.behaviorContractIdentity) 'exact-environment-retains-path-temp-differences'
   $negative=Clone $policyGroup;$negative.environmentPolicy.negativeToolLookups=@('aiw-fixture-negative-lookup')
   $absent=Get-AiwTestDependencySnapshot $sample $policyDefinitionPath $d $negative $policyOptions
   [IO.File]::Copy([Environment]::ProcessPath,(Join-Path $policyTools 'aiw-fixture-negative-lookup.exe'),$false);$env:PATH=$policyTools+[IO.Path]::PathSeparator+$oldPath
   $found=Get-AiwTestDependencySnapshot $sample $policyDefinitionPath $d $negative $policyOptions
   Check ($absent.facts.behaviorContractIdentity-cne$found.facts.behaviorContractIdentity-and-not$absent.facts.environment.negativeToolLookups[0].found-and$found.facts.environment.negativeToolLookups[0].found) 'effective-tools-bind-actual-negative-resolution-change'
  }finally{$env:PATH=$oldPath;$env:TEMP=$oldTemp;$env:TMP=$oldTmp}
  $recipe=Clone $policyGroup;$recipe.fixtureRecipe.steps+=@('changed semantic recipe')
  $recipeSnapshot=Get-AiwTestDependencySnapshot $sample $policyDefinitionPath $d $recipe $policyOptions
  Check ($recipeSnapshot.facts.behaviorContractIdentity-cne$policyBase.facts.behaviorContractIdentity) 'fixture-recipe-change-invalidates-behavior-reuse'
  $one=New-AiwTestSourceView $sample (Join-Path $temp 'policy-one') $d;$two=New-AiwTestSourceView $sample (Join-Path $temp 'policy-two') $d
  $exactOne=Get-AiwTestDependencySnapshot $one.Root (Join-Path $one.Root 'framework/versions/2.0.0/tests/test-groups.json') $d $policyGroup $policyOptions
  $exactTwo=Get-AiwTestDependencySnapshot $two.Root (Join-Path $two.Root 'framework/versions/2.0.0/tests/test-groups.json') $d $policyGroup $policyOptions
  Check ($exactOne.facts.behaviorContractIdentity-cne$exactTwo.facts.behaviorContractIdentity) 'default-exact-location-rejects-moved-root'
  $logical=Clone $policyGroup;$logical.locationPolicy=[pscustomobject]@{mode='LOGICAL_ROOT';mappings=@(@{logicalRoot='SOURCE_VIEW';physicalRoot='CURRENT_SOURCE_VIEW'});conditions=@(@('volume','caseSensitivity','pathLengthClass','permissions','ownership','reparse')|ForEach-Object{@{name=$_;value='OBSERVE'}})}
  $logicalOne=Get-AiwTestDependencySnapshot $one.Root (Join-Path $one.Root 'framework/versions/2.0.0/tests/test-groups.json') $d $logical $policyOptions
  $logicalTwo=Get-AiwTestDependencySnapshot $two.Root (Join-Path $two.Root 'framework/versions/2.0.0/tests/test-groups.json') $d $logical $policyOptions
  Check ($logicalOne.facts.behaviorContractIdentity-ceq$logicalTwo.facts.behaviorContractIdentity-and$logicalOne.facts.root-cne$logicalTwo.facts.root-and$logicalOne.facts.locationPolicy.conditions.Count-eq6) 'logical-location-uses-six-real-observations-and-retains-physical-facts'
 }
 $stable=Join-Path $temp 'coverage-owned-view';$runner=Join-Path $sampleTests 'run-framework-tests.ps1'
 function RunCoverage([string]$Name,[string[]]$Resume=@(),[string]$View=$stable,[switch]$Summary,[string[]]$Selected=@(),[hashtable]$Environment=@{}){
  $arguments=@('-NoProfile','-NonInteractive','-File',$(if($Summary){Join-Path $sampleTests 'run-framework-tests-summary.ps1'}else{$runner}),'-EvidenceDirectory',(Join-Path $rawRoot ($Name+'-groups')))
  if($View){$arguments+=@('-SourceViewPath',$View)};if($Resume.Count){$arguments+=@('-ResumeEvidence',($Resume-join','))}
  if($Selected.Count){$arguments+=@('-Groups',($Selected-join','))};$transcript=Join-Path $rawRoot ($Name+'-summary.txt');if($Summary){$arguments+=@('-EvidencePath',$transcript)}
  $process=Invoke-AiwTestProcess ([Environment]::ProcessPath) $arguments -WorkingDirectory $sample -Environment $Environment -EvidenceDirectory (Join-Path $rawRoot ($Name+'-native')) -GroupId 'complete-public-runner-coverage'
  $process|Add-Member Transcript $(if($Summary-and(Test-Path -LiteralPath $transcript)){[IO.File]::ReadAllText($transcript)}else{$process.StdoutText});return $process
 }
  function TestPublicExactResume([string[]]$Preserve=@(),[switch]$CleanupOnly){
   $fixtureDefinitionPath=Join-Path $sampleTests 'test-groups.json';$bEntryPath=Join-Path $sample $bEntry;$bValuePath=Join-Path $sample $bValue
   $saved=@{};foreach($path in @($runner,$fixtureDefinitionPath,$bEntryPath,$bValuePath)){$saved[$path]=[IO.File]::ReadAllBytes($path)}
   $originalGraphs=@{}
   function GraphIdentity([string]$Path){Get-TestValueIdentity (Get-AiwTestFixtureSnapshot (Split-Path -Parent $Path) -IdentityOnly).Files}
   foreach($path in $Preserve){$originalGraphs[$path]=GraphIdentity $path}
   function NeedPublicRun($Run,[string]$Name){if($Run.Code-ne0){throw ('EXACT_PUBLIC_RUN_FAILED|'+$Name+'|'+$Run.StdoutText+'|'+$Run.StderrText)}}
   function ExactReused([string]$Name){
    $e=Join-Path $rawRoot ($Name+'-groups');$s=Read-AiwTestJson (Join-Path $e 'suite.json');$cost=Read-AiwTestJson (Join-Path $e 'execution-cost.json')
    return $s.coverage-ceq'COMPLETE'-and$cost.newGroupChildCount-eq1-and@($s.records|Where-Object{$_.groupId-cin@('proof.a','proof.b')-and$_.executionKind-ceq'REVALIDATED'}).Count-eq2-and@($s.records|Where-Object{$_.groupId-ceq'integration.full-source'-and$_.executionKind-ceq'EXECUTED'}).Count-eq1-and-not(Test-Path -LiteralPath (Join-Path $e 'proof.a/raw'))-and-not(Test-Path -LiteralPath (Join-Path $e 'proof.b/raw'))
   }
   function FreshContext([string]$Name,[string]$Id,$Original){
    $record=Read-AiwTestJson (Join-Path $rawRoot ($Name+'-groups/'+$Id+'/executed.json'))
    $native=Read-AiwTestJson $record.processResult.path;$launch=Read-AiwTestJson (Join-Path (Split-Path -Parent $record.processResult.path) 'launch.json')
    $envFacts=$record.before.facts.nativeEnvironment;$raw=Join-Path $rawRoot ($Name+'-groups/'+$Id+'/raw')
    if($native.exitCode-ne0-or$record.outcome-cne'PASS'-or$record.cleanup.status-cne'CLEAN'-or$envFacts.TMP-ceq$Original.after.facts.nativeEnvironment.TMP-or$envFacts.TMP-cne$envFacts.TEMP-or$envFacts.AIW_TEST_RAW_DIRECTORY-cne$raw-or$record.cleanup.root-cne$envFacts.TMP-or$native.command.cwd-cne$record.before.facts.root){return $false}
    foreach($key in @('TMP','TEMP','AIW_TEST_RAW_DIRECTORY','AIW_TEST_HOST','AIW_TEST_GROUP_ID','AIW_TEST_SOURCE_VIEW')){if($native.environment.$key-cne$envFacts.$key-or$launch.environment.$key-cne$envFacts.$key-or$record.after.facts.nativeEnvironment.$key-cne$envFacts.$key){return $false}}
    return (Get-TestValueIdentity $native.command.arguments)-ceq(Get-TestValueIdentity $record.before.facts.commandArguments)
   }
   try{
     Put $bValuePath 'A-sentinel:repaired'
     if(-not$CleanupOnly){
    $exact=Clone (Read-AiwTestJson $fixtureDefinitionPath)
    foreach($g in $exact.groups){$g.environmentPolicy.mode='EXACT';$g.environmentPolicy.influentialVariables=@('COMSPEC','PATH','PSModulePath','TEMP','TMP','tempBase')}
    Put $fixtureDefinitionPath (($exact|ConvertTo-Json -Depth 100 -Compress)+"`n")
    Put $bValuePath 'A-sentinel:repaired'
    $first=RunCoverage 'exact-public-first';NeedPublicRun $first 'first'
    $a=Join-Path $rawRoot 'exact-public-first-groups/proof.a/executed.json';$b=Join-Path $rawRoot 'exact-public-first-groups/proof.b/executed.json';$integration=Join-Path $rawRoot 'exact-public-first-groups/integration.full-source/executed.json'
    $aRecord=Read-AiwTestJson $a;$bRecord=Read-AiwTestJson $b
    foreach($path in @($a,$b,$integration)){$originalGraphs[$path]=GraphIdentity $path}
    $firstSuite=Read-AiwTestJson (Join-Path $rawRoot 'exact-public-first-groups/suite.json')
    Check ($firstSuite.coverage-ceq'COMPLETE'-and@($firstSuite.records|Where-Object executionKind -CEQ EXECUTED).Count-eq3-and$aRecord.after.facts.environmentPolicy.mode-ceq'EXACT') 'exact-public-first-has-three-real-original-executions'
    $second=RunCoverage 'exact-public-resume' @($a,$b,$integration);NeedPublicRun $second 'resume'
    Check (ExactReused 'exact-public-resume') 'exact-public-new-evidence-reuses-a-b-with-zero-native-and-fresh-integration'
    $suitePath=Join-Path $rawRoot 'exact-public-resume-groups/suite.json';$current=Assert-AiwTestSuiteEvidence $suitePath $stable (Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json')
    foreach($id in @('proof.a','proof.b')){$r=@($current.records|Where-Object groupId -CEQ $id)[0];$rv=Read-AiwTestJson $r.revalidation.path;Check ($rv.schemaVersion-eq2-and$rv.derivations.Count-eq0-and$rv.original.identity-ceq(Get-AiwTestFileIdentity $r.path)) ('exact-public-direct-immutable-original-'+$id)}
    # A separate process consumes both the local suite and its portable proof graph.
    $proofPath=Join-Path $rawRoot 'exact-public-resume-groups/prepackage-proof/validation-proof.json';$proofRoot=Split-Path -Parent $proofPath
    $portable=Join-Path $temp 'exact-portable';$null=New-AiwTestSourceView $sample $portable $exact;$portableVersion=Join-Path $portable 'framework/versions/2.0.0'
    Copy-AiwTestAllowlist $proofRoot $portableVersion @((Get-AiwReleaseTreeMembers (Join-Path $proofRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
    $badSuite=CloneEvidence $current @('startedUtc','endedUtc');$rv=Read-AiwTestJson $badSuite.records[0].revalidation.path -StringFields @('checkedUtc');$badRv=CloneEvidence $rv @('checkedUtc');$badRv.currentSnapshot.identity=if($badRv.currentSnapshot.identity-ceq('A'*64)){'B'*64}else{'A'*64}
    $badRvPath=Join-Path $rawRoot 'exact-cold-bad-rv.json';Write-AiwTestJson $badRvPath $badRv;$badSuite.records[0].revalidation=[pscustomobject]@{path=$badRvPath;identity=(Get-AiwTestFileIdentity $badRvPath)};$badSuitePath=Join-Path $rawRoot 'exact-cold-bad-suite.json';Write-AiwTestJson $badSuitePath $badSuite
    $probe=Join-Path $rawRoot 'exact-cold-readers.ps1';Put $probe ((@'
param([string]$View,[string]$Source,[string]$Version,[string]$SuitePath,[string]$Proof,[string]$BadSuite,[string]$BadRv)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
Import-Module (Join-Path $View 'framework/versions/2.0.0/tests/TestHarness.psm1')
Import-Module (Join-Path $View 'framework/versions/2.0.0/tests/TestGroupEvidence.psm1')
$definitionPath=Join-Path $View 'framework/versions/2.0.0/tests/test-groups.json';$definition=Read-AiwTestGroupDefinition $definitionPath
$suite=Assert-AiwTestSuiteEvidence $SuitePath $View $definitionPath
try{$null=Assert-AiwTestSuiteEvidence $BadSuite $View $definitionPath;throw 'BAD_LOCAL_ACCEPTED'}catch{if($_.Exception.Message-cne'RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT'){throw}}
$reader=Import-Module (Join-Path $Source 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru
$wire=Get-Content -LiteralPath $Proof -Raw|ConvertFrom-Json -Depth 100
$consumed=& $reader.ExportedCommands['Assert-AiwReleaseProof'] $Version ([pscustomobject]@{validationProof=$wire}) -SourceRoot $Source
if($consumed.Mode-cne'CURRENT_GROUP_COVERAGE'){throw 'EXACT_COLD_PROOF_MODE'}
$bad=Read-AiwTestJson $BadRv -StringFields @('checkedUtc')
try{$null=& $reader {param($s,$d,$g,$w,$v) Assert-AiwReleaseBehaviorSnapshot $s $d $g $w $v} $bad.currentSnapshot $definition $definition.groups[0] $suite $Version;throw 'BAD_PORTABLE_ACCEPTED'}catch{if($_.Exception.Message-cne'RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT'){throw}}
'PASS|exact-cold-local-and-portable-with-identity-counterexamples'
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
    $cold=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$probe,'-View',$stable,'-Source',$sample,'-Version',$portableVersion,'-SuitePath',$suitePath,'-Proof',$proofPath,'-BadSuite',$badSuitePath,'-BadRv',$badRvPath) -WorkingDirectory $sample -EvidenceDirectory (Join-Path $rawRoot 'exact-cold-native')
    Check ($cold.Code-eq0-and$cold.StdoutText.Contains('PASS|exact-cold-local-and-portable')) 'exact-public-cold-local-and-portable-accept-real-proof-reject-false-snapshot'
    $runnerText=[Text.Encoding]::UTF8.GetString($saved[$runner])
    $guard="if(`$definition.schemaVersion-eq3-and`$plannedChoice.selection-ceq'EXECUTE'-and`$plannedGroup.environmentPolicy.mode-cin@('EXACT','EFFECTIVE_TOOLS')-and`$null-ne`$plannedChoice.original){"
    if($runnerText.Split($guard).Count-ne2){throw 'EXACT_OLD_ORDER_VARIANT_SITE'}
    try{Put $runner ($runnerText.Replace($guard,'if($false){ # isolated original fresh-context ordering'));$oldOrder=RunCoverage 'exact-old-order' @($a,$b,$integration);NeedPublicRun $oldOrder 'old-order-comparison';Check (-not(ExactReused 'exact-old-order')-and(Read-AiwTestJson (Join-Path $rawRoot 'exact-old-order-groups/execution-cost.json')).newGroupChildCount-eq3) 'exact-public-oracle-detects-original-fresh-context-ordering'}finally{[IO.File]::WriteAllBytes($runner,$saved[$runner])}
    # Change only B's actual entry/value inputs; A remains behavior-identical.
    Put $bValuePath 'A-sentinel:repaired:v2'
    Put $bEntryPath (New-CoverageNativeBody 'if([IO.File]::ReadAllText((Join-Path $PSScriptRoot "coverage-b.txt"))-cne"A-sentinel:repaired:v2"){throw "NATURAL_B_FAILURE"};Write-Output "PASS|coverage-b";Write-Output "RESULT|1/1 passed|scope=coverage-b"')
    $changed=RunCoverage 'exact-b-change' @($a,$b) -Selected @('proof.a','proof.b');NeedPublicRun $changed 'B-change'
    Check ($changed.StdoutText.Contains('GROUP|proof.a|REVALIDATED')-and(FreshContext 'exact-b-change' 'proof.b' $bRecord)) 'exact-public-b-input-change-keeps-a-and-launches-b-in-fresh-context'
    # Leak only old TMP/TEMP in an isolated variant. Old raw never becomes a write target.
    $launchSite='$childEnvironment=$nativeOverrides[$id]'
    $leak='$childEnvironment=@{};foreach($key in $nativeOverrides[$id].Keys){$childEnvironment[$key]=$nativeOverrides[$id][$key]};if($null-ne$planned.original){$oldEnvironment=Get-RunnerOriginalEnvironment $planned.original $group $nativeOverrides[$id];if($null-ne$oldEnvironment){$childEnvironment.TMP=$oldEnvironment.TMP;$childEnvironment.TEMP=$oldEnvironment.TEMP}}'
    if($runnerText.Split($launchSite).Count-ne2){throw 'EXACT_OLD_MAP_VARIANT_SITE'}
    # This deliberately wrong launch recreates the first B child's cleaned TMP.
    # Bind disposal to that actual native record and this invocation's outer TMP.
    $wrongMapTemp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($bRecord.after.facts.nativeEnvironment.TMP))
    $wrongMapParent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    $firstBNative=Read-AiwTestJson $bRecord.processResult.path
    if($bRecord.outcome-cne'PASS'-or$bRecord.cleanup.status-cne'CLEAN'-or@($bRecord.cleanup.entries).Count-ne0-or@($bRecord.cleanup.workers).Count-ne0-or$bRecord.cleanup.root-cne$wrongMapTemp-or$bRecord.after.facts.nativeEnvironment.TEMP-cne$wrongMapTemp-or$firstBNative.exitCode-ne0-or$firstBNative.environment.TMP-cne$wrongMapTemp-or$firstBNative.environment.TEMP-cne$wrongMapTemp-or-not[IO.Path]::GetDirectoryName($wrongMapTemp).Equals($wrongMapParent,[StringComparison]::OrdinalIgnoreCase)-or(Test-Path -LiteralPath $wrongMapTemp)){throw 'EXACT_WRONG_MAP_ORIGINAL_TEMP_SCOPE'}
    $walk=$wrongMapParent;while($walk){if(((Get-Item -LiteralPath $walk -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'EXACT_WRONG_MAP_TEMP_REPARSE'};$walk=[IO.Path]::GetDirectoryName($walk)}
    $wrongMapTempOwned=$false
    try{
     Put $runner ($runnerText.Replace($launchSite,$leak));$wrongMap=RunCoverage 'exact-wrong-map' @($b) -Selected @('proof.b')
     $wrongRecord=Read-AiwTestJson (Join-Path $rawRoot 'exact-wrong-map-groups/proof.b/executed.json');$wrongNative=Read-AiwTestJson $wrongRecord.processResult.path
     Check ($wrongMap.Code-ne0-and$wrongMap.StdoutText.Contains('GROUP_INVALID|proof.b|')-and$wrongNative.exitCode-eq0-and$wrongNative.environment.TMP-ceq$bRecord.after.facts.nativeEnvironment.TMP-and$wrongNative.environment.AIW_TEST_RAW_DIRECTORY-cne$bRecord.after.facts.nativeEnvironment.AIW_TEST_RAW_DIRECTORY-and-not(FreshContext 'exact-wrong-map' 'proof.b' $bRecord)) 'exact-public-oracle-detects-historical-map-fallback-after-real-native-success'
     if($wrongNative.environment.TEMP-cne$wrongMapTemp){throw 'EXACT_WRONG_MAP_NATIVE_TEMP_DRIFT'}
     $wrongMapTempOwned=$true
    }finally{
     [IO.File]::WriteAllBytes($runner,$saved[$runner])
     if($wrongMapTempOwned){
      $item=Get-Item -LiteralPath $wrongMapTemp -Force
      if(-not$item.PSIsContainer-or-not[IO.Path]::GetDirectoryName($item.FullName).Equals($wrongMapParent,[StringComparison]::OrdinalIgnoreCase)){throw 'EXACT_WRONG_MAP_RECREATED_TEMP_SCOPE'}
      $walk=$wrongMapTemp;while($walk){if(((Get-Item -LiteralPath $walk -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'EXACT_WRONG_MAP_TEMP_REPARSE'};$walk=[IO.Path]::GetDirectoryName($walk)}
      if(@([IO.Directory]::EnumerateFileSystemEntries($wrongMapTemp)).Count-ne0){throw 'EXACT_WRONG_MAP_TEMP_NOT_EMPTY'}
      [IO.Directory]::Delete($wrongMapTemp,$false)
      Check (-not(Test-Path -LiteralPath $wrongMapTemp)) 'exact-public-wrong-map-recreated-owned-temp-removed-before-return'
     }
    }
    foreach($fault in @('missing-native-raw','failed-original','wrong-host')){
     $bad=CloneEvidence $aRecord @('startedUtc','endedUtc')
     switch($fault){'missing-native-raw'{$bad.processResult.path=Join-Path $rawRoot 'missing-native-raw/result.json'} 'failed-original'{$bad.outcome='FAIL'} 'wrong-host'{$bad.after.facts.nativeEnvironment.AIW_TEST_HOST='FOREIGN_HOST'}}
     $badPath=Join-Path $rawRoot ('exact-'+$fault+'.json');Write-AiwTestJson $badPath $bad;$name='exact-'+$fault
     $run=RunCoverage $name @($badPath) -Selected @('proof.a');NeedPublicRun $run $fault
     Check (FreshContext $name 'proof.a' $aRecord) ('exact-public-'+$fault+'-uses-fresh-native-raw-temp-and-launch')
    }
    $ambient=Join-Path $temp 'exact-ambient';$null=[IO.Directory]::CreateDirectory($ambient)
    foreach($change in @(@{name='path';env=@{PATH=($env:PATH+[IO.Path]::PathSeparator+$ambient)}},@{name='temp';env=@{TEMP=$ambient;TMP=$ambient}},@{name='module-path';env=@{PSModulePath=($env:PSModulePath+[IO.Path]::PathSeparator+$ambient)}})){
     $name='exact-ambient-'+$change.name;$run=RunCoverage $name @($a) -Selected @('proof.a') -Environment $change.env;NeedPublicRun $run $name
     Check (FreshContext $name 'proof.a' $aRecord) ('exact-public-actual-ambient-'+$change.name+'-still-invalidates-reuse')
    }
    $other=RunCoverage 'exact-other-root' @($a) -View (Join-Path $temp 'exact-other-owned') -Selected @('proof.a');NeedPublicRun $other 'other-root'
    Check (FreshContext 'exact-other-root' 'proof.a' $aRecord) 'exact-public-different-physical-root-still-invalidates-reuse'
    $exact.groups[0].fixtureRecipe.steps+=@('changed recipe input');Put $fixtureDefinitionPath (($exact|ConvertTo-Json -Depth 100 -Compress)+"`n")
    $recipe=RunCoverage 'exact-other-recipe' @($a) -Selected @('proof.a');NeedPublicRun $recipe 'other-recipe'
    Check (FreshContext 'exact-other-recipe' 'proof.a' $aRecord) 'exact-public-current-recipe-still-invalidates-reuse'
    $duplicate=RunCoverage 'exact-duplicate-original' @($a,$a) -Selected @('proof.a')
    Check ($duplicate.Code-ne0-and$duplicate.StderrText.Contains('TEST_DUPLICATE_RESUME_GROUP')) 'exact-public-duplicate-original-guard-is-preserved'
    # Use the production policy shape, with real first executions under that policy.
    $effective=Clone (Read-AiwTestJson $fixtureDefinitionPath)
    foreach($g in $effective.groups){$g.environmentPolicy.mode='EFFECTIVE_TOOLS';$g.environmentPolicy.influentialVariables=@('COMSPEC','PSModulePath','TEMP','TMP');$g.tools+=@('git');$g.behaviorInputs.files+=@('framework/versions/2.0.0/tests/TestNativeOutput.psm1')}
    $effective.groups[0].environmentPolicy.negativeToolLookups=@('aiw-fixture-negative-lookup')
    Put $fixtureDefinitionPath (($effective|ConvertTo-Json -Depth 100 -Compress)+"`n")
    [IO.File]::WriteAllBytes($bEntryPath,$saved[$bEntryPath]);Put $bValuePath 'A-sentinel:repaired'
    $effectiveFirst=RunCoverage 'effective-public-first';NeedPublicRun $effectiveFirst 'effective-first'
    $ea=Join-Path $rawRoot 'effective-public-first-groups/proof.a/executed.json';$eb=Join-Path $rawRoot 'effective-public-first-groups/proof.b/executed.json';$ei=Join-Path $rawRoot 'effective-public-first-groups/integration.full-source/executed.json'
    $eaRecord=Read-AiwTestJson $ea;$ebRecord=Read-AiwTestJson $eb
    foreach($path in @($ea,$eb,$ei)){$originalGraphs[$path]=GraphIdentity $path}
    Check ($eaRecord.executionKind-ceq'EXECUTED'-and$ebRecord.executionKind-ceq'EXECUTED'-and$eaRecord.after.facts.environmentPolicy.mode-ceq'EFFECTIVE_TOOLS') 'effective-public-new-policy-has-honest-executed-baseline'
    $noise=Join-Path $temp 'effective-path-noise';$null=[IO.Directory]::CreateDirectory($noise)
    $effectiveResume=RunCoverage 'effective-public-resume' @($ea,$eb,$ei) -Environment @{PATH=($env:PATH+[IO.Path]::PathSeparator+$noise)};NeedPublicRun $effectiveResume 'effective-resume'
    Check (ExactReused 'effective-public-resume') 'effective-public-irrelevant-path-reuses-a-b-with-zero-native-and-fresh-integration'
    $effectiveSuitePath=Join-Path $rawRoot 'effective-public-resume-groups/suite.json';$effectiveSuite=Read-AiwTestJson $effectiveSuitePath
    $effectiveRv=Read-AiwTestJson $effectiveSuite.records[0].revalidation.path -StringFields @('checkedUtc')
    Check ($effectiveRv.currentSnapshot.facts.environment.variables.PATH-cne$eaRecord.after.facts.environment.variables.PATH-and$effectiveRv.currentSnapshot.facts.behaviorContractIdentity-ceq$eaRecord.after.facts.behaviorContractIdentity) 'effective-public-keeps-actual-path-noise-in-raw-observation'
    $effectiveProof=Join-Path $rawRoot 'effective-public-resume-groups/prepackage-proof/validation-proof.json';$effectiveBundle=Split-Path -Parent $effectiveProof
    $effectivePortable=Join-Path $temp 'effective-portable';$null=New-AiwTestSourceView $sample $effectivePortable $effective;$effectiveVersion=Join-Path $effectivePortable 'framework/versions/2.0.0'
    Copy-AiwTestAllowlist $effectiveBundle $effectiveVersion @((Get-AiwReleaseTreeMembers (Join-Path $effectiveBundle 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
    $effectiveBadRv=CloneEvidence $effectiveRv @('checkedUtc');$effectiveBadRv.currentSnapshot.identity=if($effectiveBadRv.currentSnapshot.identity-ceq('A'*64)){'B'*64}else{'A'*64}
    $effectiveBadRvPath=Join-Path $rawRoot 'effective-cold-bad-rv.json';Write-AiwTestJson $effectiveBadRvPath $effectiveBadRv
    $effectiveBadSuite=CloneEvidence $effectiveSuite @('startedUtc','endedUtc');$effectiveBadSuite.records[0].revalidation=[pscustomobject]@{path=$effectiveBadRvPath;identity=(Get-AiwTestFileIdentity $effectiveBadRvPath)}
    $effectiveBadSuitePath=Join-Path $rawRoot 'effective-cold-bad-suite.json';Write-AiwTestJson $effectiveBadSuitePath $effectiveBadSuite
    $effectiveCold=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$probe,'-View',$stable,'-Source',$sample,'-Version',$effectiveVersion,'-SuitePath',$effectiveSuitePath,'-Proof',$effectiveProof,'-BadSuite',$effectiveBadSuitePath,'-BadRv',$effectiveBadRvPath) -WorkingDirectory $sample -EvidenceDirectory (Join-Path $rawRoot 'effective-cold-native') -Environment @{PATH=($env:PATH+[IO.Path]::PathSeparator+$noise)} -EvidenceContractVersion 2
    Check ($effectiveCold.Code-eq0-and$effectiveCold.StdoutText.Contains('PASS|exact-cold-local-and-portable')) 'effective-public-cold-local-portable-and-snapshot-counterexample'
    Check ($effectiveCold.Record.schemaVersion-eq2-and$effectiveCold.Record.environment.PATH-ceq($env:PATH+[IO.Path]::PathSeparator+$noise)) 'effective-public-cold-uses-actual-current-path-noise'
    $effectiveAmbient=Join-Path $temp 'effective-ambient';$null=[IO.Directory]::CreateDirectory($effectiveAmbient)
    foreach($change in @(@{name='temp';env=@{TEMP=$effectiveAmbient;TMP=$effectiveAmbient}},@{name='module-path';env=@{PSModulePath=($env:PSModulePath+[IO.Path]::PathSeparator+$effectiveAmbient)}})){
     $name='effective-ambient-'+$change.name;$run=RunCoverage $name @($ea) -Selected @('proof.a') -Environment $change.env;NeedPublicRun $run $name
     Check (FreshContext $name 'proof.a' $eaRecord) ('effective-public-declared-'+$change.name+'-invalidates-and-launches-fresh')
    }
    $effectiveTools=Join-Path $temp 'effective-tools';$null=[IO.Directory]::CreateDirectory($effectiveTools)
    $actualGit=Get-Command git -CommandType Application|Select-Object -First 1
    [IO.File]::Copy($actualGit.Source,(Join-Path $effectiveTools 'git.exe'),$false)
    $toolChange=RunCoverage 'effective-tool-change' @($ea) -Selected @('proof.a') -Environment @{PATH=($effectiveTools+[IO.Path]::PathSeparator+$env:PATH)};NeedPublicRun $toolChange 'effective-tool-change'
    $toolRecord=Read-AiwTestJson (Join-Path $rawRoot 'effective-tool-change-groups/proof.a/executed.json')
    $originalGit=@($eaRecord.after.facts.environment.tools|Where-Object name -CEQ 'git');$changedGit=@($toolRecord.before.facts.environment.tools|Where-Object name -CEQ 'git')
    Check ((FreshContext 'effective-tool-change' 'proof.a' $eaRecord)-and$originalGit.Count-eq1-and$changedGit.Count-eq1-and$originalGit[0].path-ceq$actualGit.Source-and$changedGit[0].path-ceq(Join-Path $effectiveTools 'git.exe')-and$originalGit[0].path-cne$changedGit[0].path) 'effective-public-actual-resolved-tool-change-invalidates-and-launches-fresh'
    [IO.File]::Copy($actualGit.Source,(Join-Path $effectiveTools 'aiw-fixture-negative-lookup.exe'),$false)
    # Exclude the changed git copy here so only the declared negative lookup changes.
    [IO.File]::Delete((Join-Path $effectiveTools 'git.exe'))
    $negativeChange=RunCoverage 'effective-negative-change' @($ea) -Selected @('proof.a') -Environment @{PATH=($effectiveTools+[IO.Path]::PathSeparator+$env:PATH)};NeedPublicRun $negativeChange 'effective-negative-change'
    $negativeRecord=Read-AiwTestJson (Join-Path $rawRoot 'effective-negative-change-groups/proof.a/executed.json')
    Check ((FreshContext 'effective-negative-change' 'proof.a' $eaRecord)-and$negativeRecord.after.facts.environment.negativeToolLookups[0].found-and-not$eaRecord.after.facts.environment.negativeToolLookups[0].found) 'effective-public-actual-negative-resolution-change-invalidates'
    $modulePath=Join-Path $sampleTests 'TestNativeOutput.psm1';$moduleBytes=[IO.File]::ReadAllBytes($modulePath)
    try{
     Put $modulePath ([Text.Encoding]::UTF8.GetString($moduleBytes)+"`n# isolated required module byte change`n")
     $moduleChange=RunCoverage 'effective-module-change' @($ea) -Selected @('proof.a');NeedPublicRun $moduleChange 'effective-module-change'
     Check (FreshContext 'effective-module-change' 'proof.a' $eaRecord) 'effective-public-required-module-byte-change-invalidates'
    }finally{[IO.File]::WriteAllBytes($modulePath,$moduleBytes)}
    Write-AiwTestJson (Join-Path $rawRoot 'effective-public-resume-ceiling.json') @{kind='REAL_PUBLIC_EFFECTIVE_POLICY_FOCUSED';first=$effectiveFirst.ResultPath;resume=$effectiveResume.ResultPath;cold=$effectiveCold.ResultPath;honestNewPolicyBaseline=$true;immutableOriginals=@($ea,$eb,$ei);fullFrameworkQualification=$false;fiveRealHeavyGroupsRevalidated=$false;performanceAcceptance=$false}
     }
    # Concrete current-run residues: successful empty disposal versus retained data/link.
    $baseBody=[Text.Encoding]::UTF8.GetString($saved[$bEntryPath])
    $linkTarget=Join-Path $temp 'cleanup-link-target';$null=[IO.Directory]::CreateDirectory($linkTarget)
    $cleanupEvidence=@()
    foreach($kind in @('empty','data','reparse')){
     $childName='current-owned-'+$kind
     $quotedTarget=$linkTarget.Replace([string][char]39,([string][char]39+[char]39))
     $body=if($kind-ceq'reparse'){'$null=New-Item -ItemType Junction -Path (Join-Path $env:TEMP '''+$childName+''') -Target '''+$quotedTarget+''''}else{'$null=[IO.Directory]::CreateDirectory((Join-Path $env:TEMP '''+$childName+'''))'}
     if($kind-ceq'data'){$body+=';[IO.File]::WriteAllText((Join-Path $env:TEMP '''+$childName+'/keep.txt''),''owned-data-sentinel'')'}
     Put $bEntryPath ($baseBody+[char]10+$body+[char]10)
     $name='cleanup-public-'+$kind;$run=RunCoverage $name -Selected @('proof.b')
     $caseRecordPath=Join-Path $rawRoot ($name+'-groups/proof.b/executed.json');$caseRecord=Read-AiwTestJson $caseRecordPath;$caseNative=Read-AiwTestJson $caseRecord.processResult.path
     $caseRoot=$caseRecord.cleanup.root;$child=Join-Path $caseRoot $childName
     if($kind-ceq'empty'){
      Check ($run.Code-eq0-and$caseRecord.outcome-ceq'PASS'-and$caseRecord.cleanup.status-ceq'CLEAN'-and$run.StdoutText.Contains('GROUP_EMPTY_DIRECTORY_REMOVED|proof.b|')-and-not(Test-Path -LiteralPath $caseRoot)) 'cleanup-public-actual-owned-empty-directory-disposed-before-clean'
     }else{
      Check ($run.Code-ne0-and$caseNative.exitCode-eq0-and$caseRecord.outcome-ceq'INCOMPLETE'-and$caseRecord.cleanup.status-ceq'DIRTY'-and(Test-Path -LiteralPath $child)) ('cleanup-public-'+$kind+'-retained-with-native-success-visible')
      # Observe and preserve the negative before disposing only this case's known objects.
      if($caseRoot-cne$caseNative.environment.TMP-or$caseRoot-cne$caseNative.environment.TEMP-or[IO.Path]::GetDirectoryName($caseRoot)-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){throw 'CLEANUP_NEGATIVE_CASE_ROOT_SCOPE'}
      $null=Assert-AiwTestPath $caseRoot
      if($kind-ceq'data'){
       $data=Join-Path $child 'keep.txt';$null=Assert-AiwTestPath $data
       Check ([IO.File]::ReadAllText($data)-ceq'owned-data-sentinel') 'cleanup-public-nonempty-data-was-not-deleted'
       [IO.File]::Copy($data,(Join-Path $rawRoot 'cleanup-preserved-data.txt'),$false);[IO.File]::Delete($data)
      }else{
       $link=Get-Item -LiteralPath $child -Force
       Check (($link.Attributes-band[IO.FileAttributes]::ReparsePoint)-and$link.Target-ceq$linkTarget-and(Test-Path -LiteralPath $linkTarget -PathType Container)) 'cleanup-public-reparse-and-target-were-not-followed-or-deleted'
      }
      [IO.Directory]::Delete($child,$false);[IO.Directory]::Delete($caseRoot,$false)
     }
     $cleanupEvidence+=@{kind=$kind;record=$caseRecordPath;native=$caseRecord.processResult;public=$run.ResultPath;observedCleanup=$caseRecord.cleanup;originalNativeOutcome=$caseNative.status;negativeDisposedOnlyAfterObserved=($kind-cne'empty')}
    }
     # Retire direct injection of a COMPLETE row: it bypassed the native producer.
     # test-harness-tests exercises an actual unconsumed worker, refusal to reset,
     # and COMPLETE only after the owned worker exits and its result is consumed.
    Write-AiwTestJson (Join-Path $rawRoot 'public-cleanup-ceiling.json') @{kind='BOUNDED_CURRENT_OWNED_EMPTY_DISPOSAL';cases=$cleanupEvidence;unknownLaunchOwnership=$(if($CleanupOnly){'NOT_RUN_IN_WORKER_SELECTION'}else{'existing wrong-map native0/public-invalid and creator-only disposal retained'});noGenericRecursiveCleanup=$true;functionalAndCleanupOutcomesSeparate=$true;fullFrameworkQualification=$false}
    foreach($path in $originalGraphs.Keys){Check ((GraphIdentity $path)-ceq$originalGraphs[$path]) ('exact-public-original-graph-unchanged-'+(Split-Path -Leaf (Split-Path -Parent $path))+'-'+[Array]::IndexOf(@($originalGraphs.Keys),$path))}
     if(-not$CleanupOnly){    Write-AiwTestJson (Join-Path $rawRoot 'exact-public-resume-ceiling.json') @{kind='REAL_PUBLIC_EXACT_FOCUSED';first=$first.ResultPath;resume=$second.ResultPath;cold=$cold.ResultPath;oldOrdering=$oldOrder.ResultPath;wrongMap=$wrongMap.ResultPath;wrongMapOnlyTempKeys=$true;immutableOriginals=@($originalGraphs.Keys);fullFrameworkQualification=$false;performanceAcceptance=$false}}
   }finally{foreach($path in $saved.Keys){[IO.File]::WriteAllBytes($path,$saved[$path])}}
  }
 if($WorkerCompletionOnly){TestPublicExactResume -CleanupOnly;Write-Output ('PARTIAL|WORKER_COMPLETION_ONLY|checks='+$passed);return}
 if($FailureTransportOnly){
  $first=RunCoverage 'coverage-failure' -Selected @('proof.a','proof.b')
  $aPath=Join-Path $rawRoot 'coverage-failure-groups/proof.a/executed.json';$bPath=Join-Path $rawRoot 'coverage-failure-groups/proof.b/executed.json'
  Check ($first.Code-ne0-and($first.StderrText+' '+$first.StdoutText).Contains('NATURAL_B_FAILURE')) 'complete-chain-real-a-pass-and-natural-b-fail'
  $a=Read-AiwTestJson $aPath;$b=Read-AiwTestJson $bPath
  Check ($a.outcome-ceq'PASS'-and$b.outcome-ceq'FAIL'-and-not(Test-Path -LiteralPath (Join-Path $rawRoot 'coverage-failure-groups/prepackage-proof/validation-proof.json'))) 'failed-complete-suite-has-no-proof-export'
  TestNativeErrorTransport
  Write-Output ('PARTIAL|FAILURE_TRANSPORT_ONLY|checks='+$passed+'|failedRecord='+$bPath);return
 }
 if($FocusedReviewRepairOnly){
  Put (Join-Path $sample $bValue) 'A-sentinel:repaired'
  $first=RunCoverage 'focused-review-baseline'
  if($first.Code-ne0){throw ('FOCUSED_BASELINE_FAILED|'+$first.StdoutText+'|'+$first.StderrText)}
  $suitePath=Join-Path $rawRoot 'focused-review-baseline-groups/suite.json'
  $suite=Assert-AiwTestSuiteEvidence $suitePath $stable (Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json')
  Check ($suite.coverage-ceq'COMPLETE'-and$suite.records.Count-eq3-and@($suite.records|Where-Object executionKind -CNE EXECUTED).Count-eq0) 'focused-review-real-fresh-three-group-suite3'
  foreach($proofVersion in @(1,2)){
   $destination=Join-Path $rawRoot ('must-not-export-suite3-proof'+$proofVersion)
   Reject {Export-AiwTestPrepackageBundle $suitePath $destination -ProofSchemaVersion $proofVersion} '^TEST_BUNDLE_VERSION_MISMATCH$' ('direct-export-reject-suite3-proof'+$proofVersion)
   Check (-not(Test-Path -LiteralPath $destination)) ('direct-export-suite3-proof'+$proofVersion+'-no-output-created')
  }
  $destination=Join-Path $rawRoot 'must-not-export-suite3-default'
  Reject {Export-AiwTestPrepackageBundle $suitePath $destination} '^TEST_BUNDLE_VERSION_MISMATCH$' 'direct-export-reject-suite3-old-default'
  Check (-not(Test-Path -LiteralPath $destination)) 'direct-export-old-default-rejection-no-output'
  $mixedSuite=CloneEvidence $suite @('startedUtc','endedUtc');$mixedSuite.schemaVersion=2;$mixedSuite.PSObject.Properties.Remove('verifierRef')
  $mixedPath=Join-Path $rawRoot 'suite2-with-current-d3.json';Write-AiwTestJson $mixedPath $mixedSuite
  $destination=Join-Path $rawRoot 'must-not-export-definition-suite-mismatch'
  Reject {Export-AiwTestPrepackageBundle $mixedPath $destination -ProofSchemaVersion 2} '^TEST_BUNDLE_VERSION_MISMATCH$' 'direct-export-reject-definition-suite-mismatch'
  Check (-not(Test-Path -LiteralPath $destination)) 'direct-export-definition-suite-mismatch-no-output'
  $destination=Join-Path $rawRoot 'direct-export-suite3-proof3'
  $export=Export-AiwTestPrepackageBundle $suitePath $destination -ProofSchemaVersion 3
  $proof=Read-AiwTestJson $export.ProofPath;$bundleRoot=$export.BundleRoot
  Copy-AiwTestAllowlist $bundleRoot $version @((Get-AiwReleaseTreeMembers (Join-Path $bundleRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
  $consumed=& $reader.ExportedCommands['Assert-AiwReleaseProof'] $version ([pscustomobject]@{validationProof=$proof}) -SourceRoot $sample
  Check ($consumed.Mode-ceq'CURRENT_GROUP_COVERAGE') 'direct-export-suite3-proof3-real-source-reader'
  $fixtureManifest=[ordered]@{schemaVersion=3;version='2.0.0';lifecycle='CANDIDATE';releaseClass='MAJOR';scope='all release payload files except RELEASE_MANIFEST.json and exact declared validation evidence members';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$consumed.Facts.FileCount;totalBytes=$consumed.Facts.TotalBytes;canonical=$consumed.Facts.Canonical;baseline='1.16.0';sourceReview='PENDING';sourceCandidate='SYNTHETIC_CURRENT_COVERAGE_ONLY';releaseIntegration='PREPACKAGE_PASS';validationProof=$proof;sourceReviewEvidence=@{status='PENDING';reviewer=$null;packageIdentity=$null;reviewedPayloadCanonical=$null;reviewedManifestIdentity=$null;reviewedManifestBase64=$null}}
  $reviewed=Join-Path $rawRoot 'focused-synthetic-reviewed-manifest.json';Write-AiwTestJson $reviewed $fixtureManifest
  $fixtureManifest.sourceReview='APPROVED';$fixtureManifest.sourceReviewEvidence=@{status='APPROVED';reviewer='synthetic-mechanism-review-only';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$consumed.Facts.Canonical;reviewedManifestIdentity=(Get-AiwTestFileIdentity $reviewed);reviewedManifestBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($reviewed))}
  ReplaceCoverageFixtureJson (Join-Path $version 'RELEASE_MANIFEST.json') $fixtureManifest
  $portableStage=Join-Path $temp 'focused-portable-stage';$portableMoved=Join-Path $temp 'focused-portable-moved';$null=New-AiwTestSourceView $sample $portableStage $d
  $portableV=Join-Path $portableStage 'framework/versions/2.0.0';Copy-AiwTestAllowlist $bundleRoot $portableV @((Get-AiwReleaseTreeMembers (Join-Path $bundleRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path});[IO.File]::Copy((Join-Path $version 'RELEASE_MANIFEST.json'),(Join-Path $portableV 'RELEASE_MANIFEST.json'),$true)
  if([IO.Path]::GetDirectoryName($portableStage)-cne$temp-or[IO.Path]::GetDirectoryName($portableMoved)-cne$temp){throw 'FOCUSED_PORTABLE_MOVE_SCOPE'};[IO.Directory]::Move($portableStage,$portableMoved)
  Check ((Get-AiwReleaseQualification -VersionRoot (Join-Path $portableMoved 'framework/versions/2.0.0') -RuntimeRoot $portableMoved).State-ceq'SOURCE_QUALIFIED') 'direct-export-suite3-proof3-real-moved-portable-reader'
  TestLegacyCurrentCoverage $sample $d $reader
  $probe=Join-Path $rawRoot 'focused-same-path-verifier.ps1'
  Put $probe ((@'
param([string]$Source,[string]$Owned,[string]$BaselineSuite,[string]$BaselineProof,[string]$EvidenceRoot)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$v=Join-Path $Source 'framework/versions/2.0.0';$dp=Join-Path $v 'tests/test-groups.json'
Import-Module (Join-Path $v 'tests/TestHarness.psm1')
$local=@(Import-Module (Join-Path $v 'tests/TestGroupEvidence.psm1') -PassThru)[0]
$reader=@(Import-Module (Join-Path $v 'scripts/ReleaseValidation.psm1') -PassThru)[0]
$shared=@(Import-Module (Join-Path $v 'scripts/TestEvidenceValidation.psm1') -PassThru)[0]
function Need([bool]$Value,[string]$Name){if(-not$Value){throw ('FOCUSED_ASSERT|'+$Name)};Write-Host ('PASS|'+$Name)}
function RejectExact([scriptblock]$Body,[string]$Reason,[string]$Name){$actual='';try{$null=& $Body}catch{$actual=$_.Exception.Message};Need ($actual-ceq$Reason) ($Name+'|reason='+$actual)}
$d=& $local.ExportedCommands['Read-AiwTestGroupDefinition'] $dp
$suite=& $local.ExportedCommands['Assert-AiwTestSuiteEvidence'] $BaselineSuite $Owned (Join-Path $Owned 'framework/versions/2.0.0/tests/test-groups.json')
$record=$suite.records[0].path;$proof=& $local.ExportedCommands['Read-AiwTestJson'] $BaselineProof
$snapshot=& $local.ExportedCommands['Get-AiwTestDependencySnapshot'] $Owned (Join-Path $Owned 'framework/versions/2.0.0/tests/test-groups.json') $d $d.groups[0] $suite.options
$aIdentity=$snapshot.facts.verifierIdentity;$path=Join-Path $v 'scripts/TestEvidenceValidation.psm1';$original=[IO.File]::ReadAllBytes($path)
$aRecordBytes=[IO.File]::ReadAllBytes($record)
$null=& $reader.ExportedCommands['Assert-AiwReleaseProof'] $v ([pscustomobject]@{validationProof=$proof}) -SourceRoot $Source
Need ($true) 'same-path-a-baseline-local-and-direct-reader'
$text=[Text.Encoding]::UTF8.GetString($original)
$signature='function Assert-AiwEvidenceNativeRecord($Record,$Group,$Snapshot,$Artifacts,[switch]$ForReuse,[switch]$AllowPartial,$Suite=$null){'
if($text.IndexOf($signature)-lt0-or$text.IndexOf($signature)-ne$text.LastIndexOf($signature)){throw 'SEMANTIC_MUTATION_ANCHOR'}
$mutation=$signature+[char]10+' if($Record.groupId-ceq"proof.a"){$script:SemanticBWitness++;if($Record.cases[0].name-cne"coverage-a"){throw "SEMANTIC_B_CASE"}}'
$bText=('$script:SemanticBWitness=0'+[char]10)+$text.Replace($signature,$mutation)
$originals=@($suite.records|Where-Object groupId -CIn @('proof.a','proof.b')|ForEach-Object path)
function RunCurrent([string]$Tag){
 $e=Join-Path $EvidenceRoot ($Tag+'-groups')
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $v 'tests/run-framework-tests.ps1'),'-EvidenceDirectory',$e,'-SourceViewPath',$Owned,'-ResumeEvidence',($originals-join',')) -WorkingDirectory $Source -EvidenceDirectory (Join-Path $EvidenceRoot ($Tag+'-native')) -GroupId ('focused-'+$Tag)
 if($run.Code-ne0){throw ('REAL_CURRENT_RUN_FAILED|'+$Tag+'|'+$run.StdoutText+'|'+$run.StderrText)}
 Need ($run.StdoutText.Contains('GROUP|proof.a|REVALIDATED')-and$run.StdoutText.Contains('GROUP|proof.b|REVALIDATED')-and-not(Test-Path -LiteralPath (Join-Path $e 'proof.a/raw'))-and-not(Test-Path -LiteralPath (Join-Path $e 'proof.b/raw'))) ($Tag+'-real-current-reuses-original-a-b')
 return $e
}
function StageProof([string]$Tag,[string]$Groups){
 $root=Join-Path ([IO.Path]::GetDirectoryName($Source)) ($Tag+'-proof-source')
 $null=New-AiwTestSourceView $Source $root $d
 $version=Join-Path $root 'framework/versions/2.0.0';$bundle=Join-Path $Groups 'prepackage-proof'
 Copy-AiwTestAllowlist $bundle $version @((Get-AiwReleaseTreeMembers (Join-Path $bundle 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
 return [pscustomobject]@{root=$root;version=$version;proof=(Read-AiwTestJson (Join-Path $bundle 'validation-proof.json'));proofPath=(Join-Path $bundle 'validation-proof.json')}
}
try{
 $events=[Collections.Generic.List[string]]::new();$sink={param($event) $events.Add($event.stage)}.GetNewClosure()
 & $reader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {
  $null=& $reader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $v -SourceRoot $Source
  [IO.File]::WriteAllText($path,$bText,[Text.UTF8Encoding]::new($false))
  RejectExact {& $reader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $v -SourceRoot $Source} 'RELEASE_READER_MODULE_DRIFT' 'same-path-warm-qualification-rejects-stale-a'
  [IO.File]::WriteAllBytes($path,$original)
  $null=& $reader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $v -SourceRoot $Source
  [IO.File]::WriteAllText($path,$bText,[Text.UTF8Encoding]::new($false))
 }
 Need (@($events|Where-Object{$_-ceq'qualification-core-start'}).Count-eq2-and@($events|Where-Object{$_-ceq'qualification-context-hit'}).Count-eq0) 'same-path-drift-failure-clears-scope-cache-before-recovered-a'
 RejectExact {& $local.ExportedCommands['Get-AiwTestDependencySnapshot'] $Owned (Join-Path $Owned 'framework/versions/2.0.0/tests/test-groups.json') $d $d.groups[0] $suite.options} 'TEST_VERIFIER_MODULE_DRIFT' 'same-path-old-snapshot-rejects-b-disk'
 $rv=Join-Path $EvidenceRoot 'must-not-write-stale-rv.json'
 RejectExact {& $local.ExportedCommands['Select-AiwTestGroupExecution'] $d.groups[0] $snapshot @($record) $rv} 'TEST_VERIFIER_MODULE_DRIFT' 'same-path-old-select-rejects-before-false-rv'
 Need (-not(Test-Path -LiteralPath $rv)) 'same-path-stale-select-leaves-no-rv'
 RejectExact {& $local.ExportedCommands['Assert-AiwTestSuiteEvidence'] $BaselineSuite $Owned (Join-Path $Owned 'framework/versions/2.0.0/tests/test-groups.json')} 'TEST_VERIFIER_MODULE_DRIFT' 'same-path-old-suite-rejects-b-disk'
 $bGroups=RunCurrent 'semantic-b';$b=StageProof 'semantic-b' $bGroups
 Need ($b.proof.verifierRef.identity-cne$aIdentity) 'semantic-b-proof-label-differs-from-a'
 RejectExact {& $reader.ExportedCommands['Assert-AiwReleaseProof'] $b.version ([pscustomobject]@{validationProof=$b.proof}) -SourceRoot $b.root} 'RELEASE_READER_MODULE_DRIFT' 'same-instance-same-path-old-direct-reader-rejects-real-b-proof'
 # A fresh process imports B from the very same physical module path, consumes
 # its valid proof, then demonstrates B-only rejection on an owned record copy.
 $cold=Join-Path $EvidenceRoot 'semantic-b-cold.ps1'
 $coldText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('cGFyYW0oW3N0cmluZ10kTW9kdWxlUm9vdCxbc3RyaW5nXSRWZXJzaW9uLFtzdHJpbmddJFNvdXJjZSxbc3RyaW5nXSRQcm9vZixbc3RyaW5nXSRSZWNvcmQpCiRFcnJvckFjdGlvblByZWZlcmVuY2U9J1N0b3AnO1NldC1TdHJpY3RNb2RlIC1WZXJzaW9uIExhdGVzdAokcj1AKEltcG9ydC1Nb2R1bGUgKEpvaW4tUGF0aCAkTW9kdWxlUm9vdCAnc2NyaXB0cy9SZWxlYXNlVmFsaWRhdGlvbi5wc20xJykgLVBhc3NUaHJ1KVswXQokcz1AKEltcG9ydC1Nb2R1bGUgKEpvaW4tUGF0aCAkTW9kdWxlUm9vdCAnc2NyaXB0cy9UZXN0RXZpZGVuY2VWYWxpZGF0aW9uLnBzbTEnKSAtUGFzc1RocnUpWzBdCiRwPUdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkUHJvb2YgLVJhd3xDb252ZXJ0RnJvbS1Kc29uIC1EZXB0aCAxMDAKJHJlc3VsdD0mICRyLkV4cG9ydGVkQ29tbWFuZHNbJ0Fzc2VydC1BaXdSZWxlYXNlUHJvb2YnXSAkVmVyc2lvbiAoW3BzY3VzdG9tb2JqZWN0XUB7dmFsaWRhdGlvblByb29mPSRwfSkgLVNvdXJjZVJvb3QgJFNvdXJjZQppZigkcmVzdWx0Lk1vZGUtY25lJ0NVUlJFTlRfR1JPVVBfQ09WRVJBR0UnLW9yKCYgJHMgeyRzY3JpcHQ6U2VtYW50aWNCV2l0bmVzc30pLWx0MSl7dGhyb3cgJ0FDVFVBTF9CX0NPREVfTk9UX0VYRUNVVEVEJ30KJGJhZD1HZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJFJlY29yZCAtUmF3fENvbnZlcnRGcm9tLUpzb24gLURlcHRoIDEwMDskYmFkLmNhc2VzWzBdLm5hbWU9J3NlbWFudGljLWItbmVnYXRpdmUnCiRyZWFzb249Jyc7dHJ5eyRudWxsPSYgJHMuRXhwb3J0ZWRDb21tYW5kc1snQXNzZXJ0LUFpd0V2aWRlbmNlTmF0aXZlUmVjb3JkJ10gJGJhZCAkbnVsbCAkbnVsbCAkbnVsbH1jYXRjaHskcmVhc29uPSRfLkV4Y2VwdGlvbi5NZXNzYWdlfQppZigkcmVhc29uLWNuZSdTRU1BTlRJQ19CX0NBU0UnKXt0aHJvdyAoJ0JfU0VNQU5USUNfTkVHQVRJVkVfTk9UX1JFQUNIRUR8JyskcmVhc29uKX0KJ1BBU1N8Y29sZC1zYW1lLXBoeXNpY2FsLXBhdGgtYWN0dWFsbHktZXhlY3V0ZXMtc2VtYW50aWMtYic='))
 $coldText=$coldText.Insert($coldText.IndexOf([char]10)+1,('Import-Module (Join-Path $ModuleRoot "tests/TestNativeOutput.psm1");Initialize-AiwTestNativeOutput'+[char]10))
 [IO.File]::WriteAllText($cold,$coldText,[Text.UTF8Encoding]::new($false))
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$cold,'-ModuleRoot',$v,'-Version',$b.version,'-Source',$b.root,'-Proof',$b.proofPath,'-Record',$record) -WorkingDirectory $Source -EvidenceDirectory (Join-Path $EvidenceRoot 'semantic-b-cold-native') -GroupId 'actual-same-path-semantic-b'
 if($run.Code-ne0){throw ('SEMANTIC_B_COLD_FAILED|'+$run.StdoutText+'|'+$run.StderrText)}
 Need ($run.StdoutText.Contains('PASS|cold-same-physical-path')) 'new-b-instance-executes-b-semantics-not-a'
 # A behavior-neutral C is actually reloaded by a fresh runner, preserving the
 # same real owned root and all original EXECUTED/raw bytes rather than rewriting them.
 [IO.File]::WriteAllText($path,$text+[char]10+'# owned behavior-neutral verifier C'+[char]10,[Text.UTF8Encoding]::new($false))
 $cGroups=RunCurrent 'equivalent-c';$c=StageProof 'equivalent-c' $cGroups
 $consumer=Join-Path $EvidenceRoot 'equivalent-c-reader.ps1'
 $consumerText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('cGFyYW0oW3N0cmluZ10kTW9kdWxlUm9vdCxbc3RyaW5nXSRWZXJzaW9uLFtzdHJpbmddJFNvdXJjZSxbc3RyaW5nXSRQcm9vZikKJEVycm9yQWN0aW9uUHJlZmVyZW5jZT0nU3RvcCcKJHI9QChJbXBvcnQtTW9kdWxlIChKb2luLVBhdGggJE1vZHVsZVJvb3QgJ3NjcmlwdHMvUmVsZWFzZVZhbGlkYXRpb24ucHNtMScpIC1QYXNzVGhydSlbMF0KJHA9R2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRQcm9vZiAtUmF3fENvbnZlcnRGcm9tLUpzb24gLURlcHRoIDEwMAokeD0mICRyLkV4cG9ydGVkQ29tbWFuZHNbJ0Fzc2VydC1BaXdSZWxlYXNlUHJvb2YnXSAkVmVyc2lvbiAoW3BzY3VzdG9tb2JqZWN0XUB7dmFsaWRhdGlvblByb29mPSRwfSkgLVNvdXJjZVJvb3QgJFNvdXJjZQppZigkeC5Nb2RlLWNuZSdDVVJSRU5UX0dST1VQX0NPVkVSQUdFJyl7dGhyb3cgJ0NfQ1VSUkVOVF9SRUFERVJfRkFJTEVEJ30KJ1BBU1N8YWN0dWFsLWVxdWl2YWxlbnQtY3VycmVudC1jLXJlYWRlci1yZXVzZXMtb3JpZ2luYWxzJw=='))
 $consumerText=$consumerText.Insert($consumerText.IndexOf([char]10)+1,('Import-Module (Join-Path $ModuleRoot "tests/TestNativeOutput.psm1");Initialize-AiwTestNativeOutput'+[char]10))
 [IO.File]::WriteAllText($consumer,$consumerText,[Text.UTF8Encoding]::new($false))
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$consumer,'-ModuleRoot',$v,'-Version',$c.version,'-Source',$c.root,'-Proof',$c.proofPath) -WorkingDirectory $Source -EvidenceDirectory (Join-Path $EvidenceRoot 'equivalent-c-cold-native') -GroupId 'actual-equivalent-c'
 if($run.Code-ne0){throw ('EQUIVALENT_C_READER_FAILED|'+$run.StdoutText+'|'+$run.StderrText)}
 Need ($run.StdoutText.Contains('PASS|actual-equivalent-current-c')) 'new-equivalent-c-instance-preserves-real-native-reuse'
 Need ((Get-AiwTestFileIdentity $record)-ceq(Get-AiwReleaseByteIdentity $aRecordBytes)) 'same-path-mutations-preserve-original-executed-bytes'
}finally{[IO.File]::WriteAllBytes($path,$original)}
Write-Output 'RESULT|same-instance-same-path-current-verifier|PASS'
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$probe,'-Source',$sample,'-Owned',$stable,'-BaselineSuite',$suitePath,'-BaselineProof',$export.ProofPath,'-EvidenceRoot',(Join-Path $rawRoot 'same-path-current-verifier')) -WorkingDirectory $sample -EvidenceDirectory (Join-Path $rawRoot 'same-path-verifier-native') -GroupId 'focused-same-instance-same-path'
  if($run.Code-ne0){throw ('SAME_PATH_VERIFIER_FAILED|'+$run.StdoutText+'|'+$run.StderrText)}
  Check ($run.StdoutText.Contains('RESULT|same-instance-same-path-current-verifier|PASS')) 'focused-same-instance-same-path-semantic-and-equivalent-verifiers'
  Write-AiwTestJson (Join-Path $rawRoot 'focused-review-repair-ceiling.json') @{kind='ACTUAL_FOCUSED_FINDING_REPAIR';samePathNative=$run.ResultPath;initialSuite=$suitePath;initialProof=$export.ProofPath;fullFrameworkQualification=$false;actualGitOrTargetExecution=$false;original185PreservedNotRerun=$true}
  return
 }
 if($fixtureContract){
  $first=RunCoverage 'coverage-contract-prefix' -Selected @('proof.a')
  if($first.Code-ne0){throw ('FIXTURE_PREFIX_FAILED|coverage|native='+$first.Code+'|stdout='+$first.StdoutText+'|stderr='+$first.StderrText)}
  $record=Read-AiwTestJson (Join-Path $rawRoot 'coverage-contract-prefix-groups/proof.a/executed.json')
  Check ($record.outcome-ceq'PASS'-and$record.cleanup.status-ceq'CLEAN') 'finite-coverage-real-public-runner-consumer'
  Check (-not(Test-Path -LiteralPath (Join-Path $sample 'owned-undeclared-seed.txt'))) 'finite-coverage-omits-undeclared-owned-seed'
  $originalPath=Join-Path $rawRoot 'coverage-contract-prefix-groups/proof.a/executed.json'
  $second=RunCoverage 'coverage-contract-snapshot' @($originalPath) -Selected @('proof.a')
  if($second.Code-ne0){throw ('SNAPSHOT_BASELINE_RUN_FAILED|'+$second.StdoutText+'|'+$second.StderrText)}
  $suitePath=Join-Path $rawRoot 'coverage-contract-snapshot-groups/suite.json'
  $definitionPath=Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json'
  $suite=Assert-AiwTestSuiteEvidence $suitePath $stable $definitionPath
  $explicitSuite=Assert-AiwTestSuiteEvidence $suitePath $stable $definitionPath -CurrentCoverage
  Check ($suite.startedUtc-is[string]-and$suite.endedUtc-is[string]-and(Get-TestValueIdentity $suite)-ceq(Get-TestValueIdentity $explicitSuite)) 'schema3-public-default-and-explicit-current-suite-agree'
  $definition=Read-AiwTestGroupDefinition $definitionPath
  $rv=Read-AiwTestJson $suite.records[0].revalidation.path -StringFields @('checkedUtc')
  Check ($suite.records[0].executionKind-ceq'REVALIDATED') 'snapshot-small-fixture-real-native-then-revalidation'
  $null=& $reader {param($s,$d,$g,$w,$v) Assert-AiwReleaseBehaviorSnapshot $s $d $g $w $v} $rv.currentSnapshot $definition $definition.groups[0] $suite (Join-Path $stable 'framework/versions/2.0.0')
  Check ($true) 'snapshot-small-fixture-original-portable-adapter-baseline'
  $bad=CloneEvidence $rv @('checkedUtc');$bad.currentSnapshot.identity=if($bad.currentSnapshot.identity-ceq('A'*64)){'B'*64}else{'A'*64}
  Check ($bad.currentSnapshot.facts.root-ceq$rv.currentSnapshot.facts.root-and(Get-TestValueIdentity $bad.currentSnapshot.facts.options)-ceq(Get-TestValueIdentity $rv.currentSnapshot.facts.options)-and$bad.currentSnapshot.identity-cne$rv.currentSnapshot.identity) 'snapshot-identity-only-keeps-root-options-preconditions'
  $badRvPath=Join-Path $rawRoot 'snapshot-small-negative-rv.json';Write-AiwTestJson $badRvPath $bad
  $badSuite=CloneEvidence $suite @('startedUtc','endedUtc');$badSuite.records[0].revalidation=[pscustomobject]@{path=$badRvPath;identity=(Get-AiwTestFileIdentity $badRvPath)}
  $badSuitePath=Join-Path $rawRoot 'snapshot-small-negative-suite.json';Write-AiwTestJson $badSuitePath $badSuite
  Reject {Assert-AiwTestSuiteEvidence $badSuitePath $stable $definitionPath} '^RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT$' 'snapshot-small-local-identity-drift'
  Reject {& $reader {param($s,$d,$g,$w,$v) Assert-AiwReleaseBehaviorSnapshot $s $d $g $w $v} $bad.currentSnapshot $definition $definition.groups[0] $suite (Join-Path $stable 'framework/versions/2.0.0')} '^RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT$' 'snapshot-small-original-portable-adapter-identity-drift'
  if($PublicSuiteConsumerContractOnly){
   $faults=[ordered]@{NATIVE_MISSING='INPUT_STRING_FIELD_MISSING\|startedUtc';NATIVE_TIME='RELEASE_EVIDENCE_TIME\|record-start';RV_FAILED='RELEASE_CURRENT_REVALIDATION_SCALAR';RV_TIME_TYPE='INPUT_STRING_FIELD_TYPE\|checkedUtc';NATIVE_VERSION='TEST_EXECUTION_SUITE_VERSION_MISMATCH'}
   foreach($kind in $faults.Keys){
    $badSuite=CloneEvidence $suite @('startedUtc','endedUtc')
    if($kind-clike'RV_*'){
     $bad=CloneEvidence $rv @('checkedUtc');if($kind-ceq'RV_FAILED'){$bad.outcome='FAIL'}else{$bad.checkedUtc=$null}
     $path=Join-Path $rawRoot ('public-suite-'+$kind+'-rv.json');Write-AiwTestJson $path $bad
     $badSuite.records[0].revalidation=[pscustomobject]@{path=$path;identity=(Get-AiwTestFileIdentity $path)}
    }else{
     $bad=Read-AiwTestJson $originalPath -StringFields @('startedUtc','endedUtc')
     switch($kind){NATIVE_MISSING{$bad.PSObject.Properties.Remove('startedUtc')} NATIVE_TIME{$bad.startedUtc='2026-10-09T10:00:00'} NATIVE_VERSION{$bad.schemaVersion=1}}
     $path=Join-Path $rawRoot ('public-suite-'+$kind+'-record.json');Write-AiwTestJson $path $bad
     $badSuite.records[0].path=$path;$badSuite.records[0].identity=Get-AiwTestFileIdentity $path
    }
    $path=Join-Path $rawRoot ('public-suite-'+$kind+'-suite.json');Write-AiwTestJson $path $badSuite
    Reject {Assert-AiwTestSuiteEvidence $path $stable $definitionPath} ('^'+$faults[$kind]+'$') ('schema3-public-default-reject-'+$kind.ToLowerInvariant())
   }
   $summary=RunCoverage 'coverage-contract-public-summary' @($originalPath) -Selected @('proof.a') -Summary
   Check ($summary.Code-eq0-and$summary.StdoutText.Contains('SUMMARY|status=PASS|coverage=PARTIAL|exit=0|executedCases=0|revalidatedOriginalCases=1')-and$summary.Transcript.Contains('GROUP|proof.a|REVALIDATED')) 'schema3-public-summary-consumes-real-revalidation-without-caller-opt-in'
    TestPublicExactResume @($originalPath)
  }
  Write-AiwTestJson (Join-Path $rawRoot 'fixture-members-coverage.json') @{kind='PRIVATE_FINITE_FIXTURE';status='PASS';versionInputCount=$inventory.schemaAndMechanicalInputs.Count;declaredInputs=$d.sourceViewPaths;actualMembers=(Get-AiwTestFixtureSnapshot $sample -IdentityOnly).Files;consumer=$first.ResultPath;consumerOutcome=$record.outcome;undeclaredOwnedSeedOmitted=$true}
  Write-Output 'PARTIAL|FIXTURE_CONTRACT_ONLY|coverage|code=0|status=PASS|reason=REAL_PUBLIC_RUNNER_REACHED';return
 }
 # A/B is the shortest failure prefix; the complete repaired run includes the
 # conservatively unknown integration, which the real risk ordering runs first.
 function TestFinalSuiteAndOwnership([string]$freshA,[string]$aPath,[string]$aIdentity){
 $principal=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $principalView=Join-Path $temp 'coverage-principal-view';$principalOwnerPath=$principalView+'.owner.json';$principalClosure=Join-Path $principalView 'source-inputs.json'
 $creatorA=RunCoverage 'ownership-creator-a' -View $principalView -Selected @('proof.a') -Environment @{CODEX_THREAD_ID='fixture-creator-A'}
 $creatorAPath=Join-Path $rawRoot 'ownership-creator-a-groups/proof.a/executed.json'
 Check ($creatorA.Code-eq0-and(Read-AiwTestJson $principalOwnerPath).owner-ceq($principal+'|fixture-creator-A')) 'same-principal-public-child-a-creates-owned-view'
 $principalOwnerBytes=[IO.File]::ReadAllBytes($principalOwnerPath);$principalOwnerIdentity=Get-AiwTestFileIdentity $principalOwnerPath;$principalClosureIdentity=Get-AiwTestFileIdentity $principalClosure
 $creatorB=RunCoverage 'ownership-creator-b' @($creatorAPath) $principalView -Selected @('proof.a') -Environment @{CODEX_THREAD_ID='fixture-creator-B'}
 Check ($creatorB.Code-eq0-and$creatorB.Transcript.Contains('GROUP|proof.a|REVALIDATED')-and(Get-AiwTestFileIdentity $principalOwnerPath)-ceq$principalOwnerIdentity-and(Get-AiwTestFileIdentity $principalClosure)-ceq$principalClosureIdentity) 'same-principal-public-child-b-preserves-original-owner-and-closure'
 $principalLock=[IO.File]::Open(($principalView+'.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 try{$blockedB=RunCoverage 'ownership-creator-b-active' @($creatorAPath) $principalView -Selected @('proof.a') -Environment @{CODEX_THREAD_ID='fixture-creator-B'};Check ($blockedB.Code-ne0-and$blockedB.StderrText.Contains('SOURCE_VIEW_ACTIVE')) 'same-principal-child-b-still-rejects-held-lease'}finally{$principalLock.Dispose()}
 $noHost=Read-AiwTestJson $principalOwnerPath;$noHost.owner=$principal+'|';Put $principalOwnerPath ($noHost|ConvertTo-Json -Depth 100 -Compress);$noHostIdentity=Get-AiwTestFileIdentity $principalOwnerPath
 try{$noHostRun=RunCoverage 'ownership-no-host-creator' @($creatorAPath) $principalView -Selected @('proof.a') -Environment @{CODEX_THREAD_ID=$null};Check ($noHostRun.Code-eq0-and(Get-AiwTestFileIdentity $principalOwnerPath)-ceq$noHostIdentity-and(Get-AiwTestFileIdentity $principalClosure)-ceq$principalClosureIdentity) 'same-principal-empty-creator-remains-valid-without-rewrite'}finally{[IO.File]::WriteAllBytes($principalOwnerPath,$principalOwnerBytes)}
 $constructorPath=Join-Path $sampleTests 'TestHarness.psm1';$constructorBytes=[IO.File]::ReadAllBytes($constructorPath)
 try{
  [IO.File]::AppendAllText($constructorPath,"`n# owned constructor-change regression`n")
  $rebuiltB=RunCoverage 'ownership-constructor-rebuild' @($creatorAPath) $principalView -Selected @('proof.a') -Environment @{CODEX_THREAD_ID='fixture-creator-B'}
  $rebuiltClosure=Read-AiwTestJson $principalClosure
  Check ($rebuiltB.Code-eq0-and(Get-AiwTestFileIdentity $principalOwnerPath)-cne$principalOwnerIdentity-and(Get-AiwTestFileIdentity $principalClosure)-cne$principalClosureIdentity-and$rebuiltClosure.syntheticInputs[0].constructorIdentity-ceq(Get-AiwTestFileIdentity $constructorPath)-and(Read-AiwTestJson $principalOwnerPath).owner-ceq($principal+'|fixture-creator-B')) 'same-principal-real-constructor-change-rebuilds-through-public-runner'
 }finally{[IO.File]::WriteAllBytes($constructorPath,$constructorBytes)}
 # A real later child corrupts the already-written A revalidation. Every child
 # still completes, so the failure reaches final suite validation and summary.
 $bEntryPath=Join-Path $sample $bEntry;$bEntryBytes=[IO.File]::ReadAllBytes($bEntryPath)
 try{
  [IO.File]::AppendAllText($bEntryPath,'; $rv=Join-Path (Split-Path -Parent (Split-Path -Parent $env:AIW_TEST_RAW_DIRECTORY)) "proof.a/revalidation.json";if(Test-Path -LiteralPath $rv){[IO.File]::AppendAllText($rv," ")}')
  $invalidFinal=RunCoverage 'coverage-final-suite-failure' @($freshA) -Summary
  $invalidSuite=Read-AiwTestJson (Join-Path $rawRoot 'coverage-final-suite-failure-groups/suite.json')
  Check ($invalidFinal.StdoutText.Contains('SUMMARY|status=FAIL|coverage=PARTIAL|exit=1')-and$invalidFinal.StdoutText.Contains('DETAIL|RUNNER_EXIT|1')-and$invalidFinal.StdoutText.Contains('PROCESS_EVIDENCE|path=')) 'invalid-final-suite-reaches-normal-summary-and-preserves-native-exit'
 Check ($invalidFinal.Code-ne0-and$invalidFinal.Transcript.Contains('SUITE_INVALID|TEST_REVALIDATION_DRIFT')-and$invalidFinal.Transcript.Contains('RESULT|outcome=INCOMPLETE|coverage=PARTIAL')-and$invalidSuite.outcome-ceq'INCOMPLETE'-and$invalidSuite.coverage-ceq'PARTIAL'-and-not(Test-Path -LiteralPath (Join-Path $rawRoot 'coverage-final-suite-failure-groups/prepackage-proof/validation-proof.json'))) 'actual-final-validation-failure-agrees-with-written-suite-summary-and-exit'
 }finally{[IO.File]::WriteAllBytes($bEntryPath,$bEntryBytes)}
 $different=Join-Path $temp 'coverage-other-root';$moved=RunCoverage 'coverage-explicit-other' @($freshA) $different -Selected @('proof.a')
 Check ($moved.Code-eq0-and$moved.Transcript.Contains('GROUP|proof.a|START')-and-not$moved.Transcript.Contains('GROUP|proof.a|REVALIDATED')) 'explicit-other-root-preserves-strict-fresh-input-identity'
 $ownerPath=$stable+'.owner.json';$ownerBytes=[IO.File]::ReadAllBytes($ownerPath);$owner=Read-AiwTestJson $ownerPath
 $sidParts=$principal.Split('-');$sidParts[-1]=if($sidParts[-1]-ceq'0'){'1'}else{'0'};$foreignSid=[Security.Principal.SecurityIdentifier]::new(($sidParts-join'-')).Value
 $owner.owner=$foreignSid+'|fixture-foreign';ReplaceCoverageFixtureJson $ownerPath $owner
 try{$foreign=RunCoverage 'coverage-foreign' @($freshA) '';Check ($foreign.Code-ne0-and$foreign.StderrText.Contains('OWNER_DRIFT')) 'inferred-root-rejects-foreign-owner'}finally{[IO.File]::WriteAllBytes($ownerPath,$ownerBytes)}
 foreach($badOwner in @(@{name='raw-sid';value=$principal},@{name='multiple-separators';value=($principal+'|fixture|extra')},@{name='non-string';value=42},@{name='empty-sid';value='|fixture'})){
  $owner=Read-AiwTestJson $ownerPath;$owner.owner=$badOwner.value;ReplaceCoverageFixtureJson $ownerPath $owner
  try{$malformed=RunCoverage ('coverage-owner-'+$badOwner.name) @($freshA) '';Check ($malformed.Code-ne0-and$malformed.StderrText.Contains('OWNER_DRIFT')) ('inferred-root-rejects-malformed-owner-'+$badOwner.name)}finally{[IO.File]::WriteAllBytes($ownerPath,$ownerBytes)}
 }
 $lock=[IO.File]::Open(($stable+'.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 try{$active=RunCoverage 'coverage-active' @($freshA) '';Check ($active.Code-ne0-and$active.StderrText.Contains('SOURCE_VIEW_ACTIVE')) 'inferred-root-rejects-active-lease'}finally{$lock.Dispose()}
 $unknown=Join-Path $stable 'unknown.txt';Put $unknown 'foreign';try{$unknownRun=RunCoverage 'coverage-unknown' @($freshA) '';Check ($unknownRun.Code-ne0-and$unknownRun.StderrText.Contains('UNKNOWN_CONTENT')) 'inferred-root-rejects-unknown-content'}finally{Remove-Item -LiteralPath $unknown}
 $corrupt=Join-Path $stable $bValue;$bytes=[IO.File]::ReadAllBytes($corrupt);[IO.File]::AppendAllText($corrupt,'foreign drift');try{$corrupted=RunCoverage 'coverage-corrupt' @($freshA) '';Check ($corrupted.Code-ne0-and$corrupted.StderrText.Contains('UNKNOWN_CONTENT')) 'inferred-root-rejects-corrupt-owned-view'}finally{[IO.File]::WriteAllBytes($corrupt,$bytes)}
 $badRoot=Clone (Read-AiwTestJson $freshA);$badRoot.after.facts.root=Join-Path $rawRoot 'missing-view';$badRootPath=Join-Path $rawRoot 'coverage-missing-root.json';Write-AiwTestJson $badRootPath $badRoot
 $missing=RunCoverage 'coverage-missing-root' @($badRootPath) '';Check ($missing.Code-ne0-and$missing.StderrText.Contains('OWNED_ROOT_REQUIRED')) 'inferred-root-rejects-missing-ownership'
 $missingError=(ConvertFrom-AiwStrictInputJson $missing.StderrText.Trim()).Value
  Check ($missingError.kind-ceq'PUBLIC_RUNNER_FAILURE'-and$missingError.stage-ceq'INITIALIZATION'-and$missingError.reason-ceq'TEST_RESUME_OWNED_ROOT_REQUIRED'-and$missingError.scriptStackTrace.Contains('run-framework-tests.ps1')-and$missing.StderrText-cnotmatch'[^\x00-\x7F]') 'missing-owned-root-retains-target-rejection-through-strict-native-reader'
  $ambiguous=RunCoverage 'coverage-ambiguous-root' @($freshA,$badRootPath) '';Check ($ambiguous.Code-ne0-and$ambiguous.StderrText.Contains('ROOT_AMBIGUOUS')) 'inferred-root-rejects-ambiguous-originals'
 $ambiguousError=(ConvertFrom-AiwStrictInputJson $ambiguous.StderrText.Trim()).Value
  Check ($ambiguousError.reason-ceq'TEST_RESUME_ROOT_AMBIGUOUS'-and$ambiguous.StderrText-cnotmatch'[^\x00-\x7F]') 'ambiguous-original-roots-retain-target-rejection-through-strict-native-reader'
  $junction=Join-Path $stable 'foreign-link';$null=New-Item -ItemType Junction -Path $junction -Target $sample
 try{$linked=RunCoverage 'coverage-reparse' @($freshA) '';Check ($linked.Code-ne0-and$linked.StderrText.Contains('REPARSE')) 'inferred-root-rejects-reparse-before-traversal'}finally{Remove-Item -LiteralPath $junction}
 $overlap=RunCoverage 'coverage-overlap' @() (Join-Path $sample 'overlap');Check ($overlap.Code-ne0-and$overlap.StderrText.Contains('SOURCE_VIEW_OVERLAP')-and(Get-AiwTestFileIdentity $aPath)-ceq$aIdentity) 'public-runner-rejects-source-overlap-and-preserves-original'

  $existingTranscript=Join-Path $rawRoot 'coverage-summary-existing-summary.txt';Put $existingTranscript 'owned original evidence'
  $existingIdentity=Get-AiwTestFileIdentity $existingTranscript
  $existingSummary=RunCoverage 'coverage-summary-existing' -Summary -Selected @('proof.a')
  $existingError=(ConvertFrom-AiwStrictInputJson $existingSummary.StderrText.Trim()).Value
  Check ($existingSummary.Code-ne0-and$existingError.kind-ceq'SUMMARY_ENTRY_FAILURE'-and$existingError.reason-ceq'EVIDENCE_PATH_EXISTS'-and$existingSummary.StderrText-cnotmatch'[^\x00-\x7F]'-and(Get-AiwTestFileIdentity $existingTranscript)-ceq$existingIdentity-and-not(Test-Path -LiteralPath ($existingTranscript+'.stderr.raw'))) 'summary-initialization-rejects-existing-evidence-without-overwrite'
  # Remove only the owned copy of the called entry, then restore its exact bytes.
  # The generated real wrapper must report an invocation error, not a fake suite.
  $runnerBytes=[IO.File]::ReadAllBytes($runner)
  try{
   [IO.File]::Delete($runner)
   $wrapperFailure=RunCoverage 'coverage-summary-call-failure' -Summary -Selected @('proof.a')
   $wrapperError=(ConvertFrom-AiwStrictInputJson ([IO.File]::ReadAllText((Join-Path $rawRoot 'coverage-summary-call-failure-summary.txt.stderr.raw'),[Text.UTF8Encoding]::new($false,$true)))).Value
   Check ($wrapperFailure.Code-ne0-and$wrapperError.kind-ceq'SUMMARY_WRAPPER_FAILURE'-and$wrapperError.reason.Contains('run-framework-tests.ps1')-and$wrapperFailure.StdoutText.Contains('SUMMARY|status=FAIL|coverage=PARTIAL|exit=1')-and$wrapperFailure.StdoutText.Contains('DETAIL|RUNNER_EXIT|1')-and-not(Test-Path -LiteralPath (Join-Path $rawRoot 'coverage-summary-call-failure-groups/suite.json'))) 'summary-real-wrapper-invocation-failure-preserves-raw-and-nonzero-without-suite'
  }finally{[IO.File]::WriteAllBytes($runner,$runnerBytes)}
  $harnessPath=Join-Path $sampleTests 'TestHarness.psm1';$evidenceModulePath=Join-Path $sampleTests 'TestGroupEvidence.psm1'
  $harnessBytes=[IO.File]::ReadAllBytes($harnessPath);$evidenceModuleBytes=[IO.File]::ReadAllBytes($evidenceModulePath)
  foreach($mode in @('primary','primary-cleanup')){
   $probe=Join-Path $rawRoot ($mode+'-lease-probe.json');$faultView=Join-Path $temp ('coverage-'+$mode+'-view')
   # Only copied dependency instrumentation injects an error after an actual
   # exclusive lease. The public runner and strict native reader remain exact.
   $harnessText=[Text.UTF8Encoding]::new($false,$true).GetString($harnessBytes).Replace('function Enter-AiwTestSourceView {','function Enter-CoverageOriginalSourceView {')
   $leaseWrapper=@'
function Enter-AiwTestSourceView {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)][string]$EvidenceRoot,[string[]]$ResumeEvidence=@())
 $result=Enter-CoverageOriginalSourceView @PSBoundParameters
 $proxy=[pscustomobject]@{Original=$result.Lease;Lock=($DestinationRoot+'.lock');Root=$DestinationRoot;Probe=__PROBE__;Fail=__FAIL__}
 $proxy|Add-Member ScriptMethod Dispose {
  $this.Original.Dispose()
  $check=[IO.File]::Open($this.Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$check.Dispose()
  [IO.File]::WriteAllText($this.Probe,(@{released=$true;root=$this.Root;lock=$this.Lock}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  if($this.Fail){throw 'RUNNER_SECONDARY_CLEANUP_次错'}
 }
 $result.Lease=$proxy
 return $result
}
'@
   $leaseWrapper=$leaseWrapper.Replace('__PROBE__',("'"+$probe.Replace("'","''")+"'")).Replace('__FAIL__',$(if($mode-ceq'primary-cleanup'){'$true'}else{'$false'}))
   $harnessText=$harnessText.Replace('Export-ModuleMember -Function',($leaseWrapper+"`nExport-ModuleMember -Function"))
   $evidenceText=[Text.UTF8Encoding]::new($false,$true).GetString($evidenceModuleBytes)
   $evidenceText=$evidenceText.Replace('Export-ModuleMember -Function',"function Get-AiwTestDependencySnapshot {throw 'RUNNER_INTERNAL_PRIMARY_首错'}`nExport-ModuleMember -Function")
   try{
    Put $harnessPath $harnessText;Put $evidenceModulePath $evidenceText
    $failure=RunCoverage ('coverage-'+$mode) -View $faultView -Selected @('proof.a')
    $actual=(ConvertFrom-AiwStrictInputJson $failure.StderrText.Trim()).Value;$released=Read-AiwTestJson $probe
    $lock=[IO.File]::Open(($faultView+'.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$lock.Dispose()
    Check ($failure.Code-ne0-and$actual.kind-ceq'PUBLIC_RUNNER_FAILURE'-and$actual.reason-ceq'RUNNER_INTERNAL_PRIMARY_首错'-and$actual.scriptStackTrace.Contains('TestGroupEvidence.psm1')-and$failure.StderrText-cnotmatch'[^\x00-\x7F]'-and$released.released-and$released.root-ceq$faultView-and-not(Test-Path -LiteralPath (Join-Path $rawRoot ('coverage-'+$mode+'-groups/suite.json')))) ('public-runner-real-lease-released-and-primary-preserved-'+$mode)
    if($mode-ceq'primary-cleanup'){Check ($actual.cleanupError.reason.Contains('RUNNER_SECONDARY_CLEANUP_次错')-and$actual.cleanupError.fullyQualifiedErrorId-ceq'ScriptMethodRuntimeException'-and$actual.cleanupError.scriptStackTrace.Contains('run-framework-tests.ps1')) 'public-runner-primary-survives-actual-finally-secondary-cleanup-error'}else{Check ($null-eq$actual.cleanupError) 'public-runner-primary-with-successful-real-lease-cleanup'}
   }finally{[IO.File]::WriteAllBytes($harnessPath,$harnessBytes);[IO.File]::WriteAllBytes($evidenceModulePath,$evidenceModuleBytes)}
  }
  $summaryPass=RunCoverage 'coverage-summary-focused-pass' -Summary -Selected @('proof.a')
  Check ($summaryPass.Code-eq0-and$summaryPass.StdoutText.Contains('SUMMARY|status=PASS|coverage=PARTIAL|exit=0')-and$summaryPass.StdoutText.Contains('FULL_EVIDENCE|path=')-and$summaryPass.StdoutText.Contains('PROCESS_EVIDENCE|path=')-and$summaryPass.StdoutText.Contains('SUMMARY_SUITE|path=')) 'summary-real-success-retains-partial-coverage-and-evidence-framing'

 # The full chain keeps its actual owned view for the following verifier test.
 $ownedCleanup=@($different,$principalView);if($FinalSuiteAndOwnershipOnly){$ownedCleanup+=@($stable)}
 foreach($owned in $ownedCleanup){$resolved=[IO.Path]::GetFullPath($owned);if([IO.Path]::GetDirectoryName($resolved)-cne[IO.Path]::GetFullPath($temp)){throw 'COVERAGE_OWNED_CLEANUP_SCOPE'};Remove-Item -LiteralPath $resolved -Recurse;foreach($suffix in @('.owner.json','.lock')){Remove-Item -LiteralPath ($resolved+$suffix)}}
 }
 if($FinalSuiteAndOwnershipOnly){
  Put (Join-Path $sample $bValue) 'A-sentinel:repaired'
  $seed=RunCoverage 'coverage-focused-original' -Selected @('proof.a')
  $seedPath=Join-Path $rawRoot 'coverage-focused-original-groups/proof.a/executed.json'
  $seedRecord=Read-AiwTestJson $seedPath
  Check ($seed.Code-eq0-and$seedRecord.outcome-ceq'PASS'-and$seedRecord.executionKind-ceq'EXECUTED'-and$seedRecord.after.facts.root-ceq$stable) 'focused-real-original-a-and-owned-root'
  TestFinalSuiteAndOwnership $seedPath $seedPath (Get-AiwTestFileIdentity $seedPath)
  return
 }
 $first=RunCoverage 'coverage-failure' -Selected @('proof.a','proof.b');$aPath=Join-Path $rawRoot 'coverage-failure-groups/proof.a/executed.json';$bPath=Join-Path $rawRoot 'coverage-failure-groups/proof.b/executed.json'
 if($first.Code-ne0-and-not(($first.StdoutText+' '+$first.StderrText).Contains('NATURAL_B_FAILURE'))){Write-Output ('COVERAGE_FAILURE_PREFIX_UNEXPECTED|'+$first.StdoutText+'|'+$first.StderrText)}
 Check ($first.Code-ne0-and$first.StderrText.Contains('NATURAL_B_FAILURE')-or$first.Code-ne0-and$first.StdoutText.Contains('NATURAL_B_FAILURE')) 'complete-chain-real-a-pass-and-natural-b-fail'
 $a=Read-AiwTestJson $aPath;$aIdentity=Get-AiwTestFileIdentity $aPath;$b=Read-AiwTestJson $bPath
 Check ($a.outcome-ceq'PASS'-and$b.outcome-ceq'FAIL'-and-not(Test-Path -LiteralPath (Join-Path $rawRoot 'coverage-failure-groups/prepackage-proof/validation-proof.json'))) 'failed-complete-suite-has-no-proof-export'
 TestNativeErrorTransport
 Put (Join-Path $sample $bValue) 'A-sentinel:repaired'
 # Freeze valid same-input negative root before the complete repair run. The
 # automatic closure/manifest remain separate from later qualification copies.
 $rootNegativeView=New-AiwTestSourceView $sample (Join-Path $temp 'root-negative-view') $d
 $rootNegativeDefinitionPath=Join-Path $rootNegativeView.Root 'framework/versions/2.0.0/tests/test-groups.json'
 $rootNegativeDefinition=Read-AiwTestGroupDefinition $rootNegativeDefinitionPath
 $rootNegativeClosure=Read-AiwTestJson $rootNegativeView.ClosurePath
 $rootNegativeManifest=Read-AiwTestJson (Join-Path $rootNegativeView.Root 'framework/versions/2.0.0/RELEASE_MANIFEST.json')
 $rootNegativeSnapshot=Get-AiwTestDependencySnapshot $rootNegativeView.Root $rootNegativeDefinitionPath $rootNegativeDefinition $rootNegativeDefinition.groups[0] ([ordered]@{})
 Check ($rootNegativeClosure.definitionIdentity-ceq(Get-AiwTestFileIdentity $rootNegativeDefinitionPath)-and$rootNegativeSnapshot.facts.inputView-ceq'SOURCE_PAYLOAD_V1'-and$rootNegativeManifest.sourceCandidate-ceq'SYNTHETIC_SOURCE_VIEW_ONLY'-and(Get-AiwTestFileIdentity (Join-Path $rootNegativeView.Root 'framework/versions/2.0.0/RELEASE_MANIFEST.json'))-ceq$rootNegativeView.ManifestIdentity) 'root-negative-valid-definition-closure-and-synthetic-inputs'
 $repair=RunCoverage 'coverage-repair' @($aPath,$bPath) ''
 if($repair.Code-ne0){Write-Output ('COVERAGE_EXIT_FAILURE|'+$repair.StdoutText+'|'+$repair.StderrText)}
 Check ($repair.Code-eq0-and$repair.StdoutText.Contains('GROUP|proof.a|REVALIDATED')-and$repair.StdoutText.Contains('GROUP|proof.b|START')-and$repair.StdoutText.Contains('GROUP|integration.full-source|START')) 'complete-chain-infers-owned-root-revalidates-a-and-executes-b-integration'
 $suitePath=Join-Path $rawRoot 'coverage-repair-groups/suite.json';$suite=Assert-AiwTestSuiteEvidence $suitePath $stable (Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json') -CurrentCoverage
 TestEvidenceGuardContracts $aPath (Join-Path $rawRoot 'coverage-repair-groups/proof.a/revalidation.json') $suitePath $d.groups[0]
 Check ($suite.coverage-ceq'COMPLETE'-and-not(Test-Path -LiteralPath (Join-Path $rawRoot 'coverage-repair-groups/proof.a/raw'))-and(Get-AiwTestFileIdentity $aPath)-ceq$aIdentity-and$suite.records.Count-eq3) 'complete-chain-zero-new-a-child-and-immutable-original'
 $proofPath=Join-Path $rawRoot 'coverage-repair-groups/prepackage-proof/validation-proof.json';$proof=Read-AiwTestJson $proofPath
 Check ($proof.schemaVersion-eq3-and$proof.mode-ceq'CURRENT_GROUP_COVERAGE'-and$null-eq$proof.baselineRef-and$proof.revalidationRefs.Count-eq1) 'complete-chain-export-v3-without-accepted-baseline'
 $bundleRoot=Split-Path -Parent $proofPath
 Copy-AiwTestAllowlist $bundleRoot $version @((Get-AiwReleaseTreeMembers (Join-Path $bundleRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
 $manifest=[pscustomobject]@{validationProof=$proof}
 $consumed=& $reader.ExportedCommands['Assert-AiwReleaseProof'] $version $manifest -SourceRoot $sample
 Check ($consumed.Mode-ceq'CURRENT_GROUP_COVERAGE'-and-not$consumed.ExecutionReusable) 'complete-chain-actual-release-reader-consumes-finite-v3-graph'
 $fixtureManifest=[ordered]@{schemaVersion=3;version='2.0.0';lifecycle='CANDIDATE';releaseClass='MAJOR';scope='all release payload files except RELEASE_MANIFEST.json and exact declared validation evidence members';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$consumed.Facts.FileCount;totalBytes=$consumed.Facts.TotalBytes;canonical=$consumed.Facts.Canonical;baseline='1.16.0';sourceReview='PENDING';sourceCandidate='SYNTHETIC_CURRENT_COVERAGE_ONLY';releaseIntegration='PREPACKAGE_PASS';validationProof=$proof;sourceReviewEvidence=@{status='PENDING';reviewer=$null;packageIdentity=$null;reviewedPayloadCanonical=$null;reviewedManifestIdentity=$null;reviewedManifestBase64=$null}}
 TestManifestGuardContracts $reader $fixtureManifest
 $reviewed=Join-Path $rawRoot 'synthetic-v2-reviewed-manifest.json';Write-AiwTestJson $reviewed $fixtureManifest
 $fixtureManifest.sourceReview='APPROVED';$fixtureManifest.sourceReviewEvidence=@{status='APPROVED';reviewer='synthetic-mechanism-review-only';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$consumed.Facts.Canonical;reviewedManifestIdentity=(Get-AiwTestFileIdentity $reviewed);reviewedManifestBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($reviewed))}
 ReplaceCoverageFixtureJson (Join-Path $version 'RELEASE_MANIFEST.json') $fixtureManifest
 Check ((Get-AiwReleaseQualification -VersionRoot $version -SourceRoot $sample).State-ceq'SOURCE_QUALIFIED') 'complete-chain-actual-qualified-v3-fixture-consumer'
 $events=[Collections.Generic.List[string]]::new()
 $scopeSink={param($event) $events.Add($event.stage)}.GetNewClosure()
 Invoke-AiwReleaseQualificationScope -DiagnosticCallback $scopeSink -Body {
  $firstQualification=Get-AiwReleaseQualification -VersionRoot $version -SourceRoot $sample
  $firstQualification.Manifest.sourceCandidate='polluted caller copy'
  $secondQualification=Get-AiwReleaseQualification -VersionRoot $version -SourceRoot $sample
  Check ($secondQualification.State-ceq'SOURCE_QUALIFIED'-and$secondQualification.Manifest.sourceCandidate-cne'polluted caller copy') 'complete-chain-real-qualification-scope-isolates-caller-result'
 }
 Check (@($events|Where-Object{$_-ceq'qualification-core-start'}).Count-eq1-and@($events|Where-Object{$_-ceq'qualification-context-hit'}).Count-eq1) 'complete-chain-real-qualification-scope-reuses-one-deep-validation'

 $portableStage=Join-Path $temp 'portable-stage';$portableMoved=Join-Path $temp 'portable-moved';$null=New-AiwTestSourceView $sample $portableStage $d
 $portableVersion=Join-Path $portableStage 'framework/versions/2.0.0';Copy-AiwTestAllowlist $bundleRoot $portableVersion @((Get-AiwReleaseTreeMembers (Join-Path $bundleRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path});[IO.File]::Copy((Join-Path $version 'RELEASE_MANIFEST.json'),(Join-Path $portableVersion 'RELEASE_MANIFEST.json'),$true)
 if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($portableStage))-cne$temp-or[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($portableMoved))-cne$temp){throw 'PORTABLE_FIXTURE_MOVE_SCOPE'};[IO.Directory]::Move($portableStage,$portableMoved)
 Check ((Get-AiwReleaseQualification -VersionRoot (Join-Path $portableMoved 'framework/versions/2.0.0') -RuntimeRoot $portableMoved).State-ceq'SOURCE_QUALIFIED'-and-not(Test-Path -LiteralPath $portableStage)) 'complete-chain-moved-portable-reader-consumes-original-v3-bytes'
 # The original public root reader is shared by registration and upgrade.
 # Consume the exact new proof graph in a fresh native process, without an
 # unrelated synthetic project registration or a second root implementation.
 $rootRuntime=Join-Path $temp 'proof3-runtime';$null=New-AiwTestSourceView $sample $rootRuntime $d
 $rootVersion=Join-Path $rootRuntime 'framework/versions/2.0.0'
 Copy-AiwTestAllowlist $bundleRoot $rootVersion @((Get-AiwReleaseTreeMembers (Join-Path $bundleRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
 [IO.File]::Copy((Join-Path $version 'RELEASE_MANIFEST.json'),(Join-Path $rootVersion 'RELEASE_MANIFEST.json'),$true)
 $packageFiles=@(Get-AiwReleaseTreeMembers $rootRuntime)
 $packageRows=@($packageFiles|ForEach-Object{$_.path+'='+$_.identity})
 $packageCanonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($packageRows-join"`n")+"`n")))
 Write-AiwTestJson (Join-Path $rootRuntime 'PACKAGE_MANIFEST.json') @{schemaVersion=2;frameworkVersion='2.0.0';provisional=$true;canonical=$packageCanonical;files=$packageFiles;distributionId='2.0.0-snapshot.991'}
 $packageBefore=Get-AiwReleaseFileIdentity (Join-Path $rootRuntime 'PACKAGE_MANIFEST.json')
 $rootProbe=Join-Path $rawRoot 'proof3-original-root-consumer.ps1'
 Put $rootProbe ((@'
param([string]$RuntimeRoot)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$path=Join-Path $RuntimeRoot 'scripts/ProjectAdoptionState.psm1'
$owner=@(Import-Module $path -PassThru)[0]
if($owner.Path-cne$path-or$owner.ExportedCommands['Get-AiwLocalCandidateFrameworkSnapshot'].Module.Path-cne$path){throw 'ORIGINAL_ROOT_CONSUMER_OWNER'}
$version=Join-Path $RuntimeRoot 'framework/versions/2.0.0'
$profile=Get-Content -LiteralPath (Join-Path $version 'ADOPTION_PROFILE.json') -Raw|ConvertFrom-Json -Depth 100
$snapshot=& $owner.ExportedCommands['Get-AiwLocalCandidateFrameworkSnapshot'] -FrameworkPath $version -ExpectedVersion '2.0.0' -AdoptionProfile $profile
$snapshot|ConvertTo-Json -Depth 100 -Compress
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $rootRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$rootProbe,'-RuntimeRoot',$rootRuntime) -WorkingDirectory $rootRuntime -EvidenceDirectory (Join-Path $rawRoot 'proof3-original-root-consumer') -GroupId 'synthetic-proof3-root'
 if($rootRun.Code-ne0){Write-Output ('ROOT_PROOF3_DIAGNOSTIC|'+$rootRun.StdoutText+'|'+$rootRun.StderrText)}
 Check ($rootRun.Code-eq0) 'complete-chain-original-root-reader-native-success'
 $rootSnapshot=$rootRun.StdoutText|ConvertFrom-Json -Depth 100
 Check ($rootSnapshot.Version-ceq'2.0.0'-and$rootSnapshot.LocalCandidate-and$rootSnapshot.Canonical-ceq$consumed.Facts.Canonical-and$rootSnapshot.ManifestIdentity-ceq(Get-AiwReleaseFileIdentity (Join-Path $rootVersion 'RELEASE_MANIFEST.json'))-and(Get-AiwReleaseFileIdentity (Join-Path $rootRuntime 'PACKAGE_MANIFEST.json'))-ceq$packageBefore) 'complete-chain-original-root-state-consumes-current-proof3-without-runtime-write'
 Write-AiwTestJson (Join-Path $rawRoot 'proof3-root-consumer-ceiling.json') @{kind='SYNTHETIC_FIXTURE_ORIGINAL_ROOT_READER_ONLY';nativeResult=$rootRun.ResultPath;rootSnapshot=$rootSnapshot;productionAdoption=$false;productionQualification=$false}
 TestLegacyCurrentCoverage $sample $d $reader
 # Counterexamples keep the original raw/suite immutable. Only isolated bundle
 # copies and new negative files are rebound, so each test reaches its cause.
 $indexPath=Join-Path $version $proof.proofBundleRef.path;$baseIndex=Read-AiwTestJson $indexPath
 $bundleBytes=@{};foreach($member in $baseIndex.members){$bundleBytes[$member.path]=[IO.File]::ReadAllBytes((Join-Path $version $member.path))};$bundleBytes[$proof.proofBundleRef.path]=[IO.File]::ReadAllBytes($indexPath)
 $caseExtras=[Collections.Generic.List[string]]::new()
 function ResetCounterexampleBundle {
  foreach($extra in $caseExtras){$target=[IO.Path]::GetFullPath((Join-Path $version $extra));if(-not$target.StartsWith([IO.Path]::GetFullPath((Join-Path $version 'validation-evidence/prepackage'))+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'COUNTEREXAMPLE_CLEANUP_SCOPE'};[IO.File]::Delete($target)};$caseExtras.Clear()
  foreach($relative in $bundleBytes.Keys){$path=Join-Path $version $relative;[IO.File]::WriteAllBytes($path,$bundleBytes[$relative]);if((Get-AiwTestFileIdentity $path)-cne(Get-AiwReleaseByteIdentity $bundleBytes[$relative])){throw ('COUNTEREXAMPLE_RESET_DRIFT|'+$relative)}}
 }
 function BindCounterexampleBundle($BadSuite,[hashtable]$BadRevalidations=@{},[hashtable]$BadRecords=@{}){
  $index=Clone $baseIndex;$candidate=Clone $proof;$sm=@($index.members|Where-Object kind -CEQ CURRENT_SUITE)[0]
  for($n=0;$n-lt$BadSuite.records.Count;$n++){
   $entry=$BadSuite.records[$n];$gm=@($index.members|Where-Object id -CEQ ($entry.groupId+'.executed'))[0]
   if($BadRecords.ContainsKey($entry.groupId)){ReplaceCoverageFixtureJson (Join-Path $version $gm.path) $BadRecords[$entry.groupId]}
   $slot='/records/'+$n.ToString()+'/original';$alias=@($index.aliases|Where-Object{$_.ownerMemberId-ceq$sm.id-and$_.slot-ceq$slot})[0];$alias.originalLocator=$entry.path;$alias.originalIdentity=$entry.identity
   if($entry.executionKind-ceq'REVALIDATED'){
    $rv=if($BadRevalidations.ContainsKey($entry.groupId)){$BadRevalidations[$entry.groupId]}else{Read-AiwTestJson $entry.revalidation.path -StringFields @('checkedUtc')}
    $rm=@($index.members|Where-Object id -CEQ ($entry.groupId+'.revalidated'))
    if(-not$rm.Count){$relative='validation-evidence/prepackage/'+$entry.groupId+'.revalidated.json';$rm=@([pscustomobject]@{id=($entry.groupId+'.revalidated');kind='REVALIDATION';path=$relative;identity=''});$index.members+=@($rm[0]);$caseExtras.Add($relative);$index.aliases+=@([pscustomobject]@{ownerMemberId=$rm[0].id;slot='/original';originalLocator=$rv.original.path;originalIdentity=$rv.original.identity;targetMemberId=$gm.id},[pscustomobject]@{ownerMemberId=$sm.id;slot=('/records/'+$n.ToString()+'/revalidation');originalLocator=$entry.revalidation.path;originalIdentity=$entry.revalidation.identity;targetMemberId=$rm[0].id})}
    if(Test-Path -LiteralPath (Join-Path $version $rm[0].path)){ReplaceCoverageFixtureJson (Join-Path $version $rm[0].path) $rv}else{Write-AiwTestJson (Join-Path $version $rm[0].path) $rv}
    $alias=@($index.aliases|Where-Object{$_.ownerMemberId-ceq$sm.id-and$_.slot-ceq('/records/'+$n.ToString()+'/revalidation')})[0];$alias.originalLocator=$entry.revalidation.path;$alias.originalIdentity=$entry.revalidation.identity
    $alias=@($index.aliases|Where-Object{$_.ownerMemberId-ceq$rm[0].id-and$_.slot-ceq'/original'})[0];$alias.originalLocator=$rv.original.path;$alias.originalIdentity=$rv.original.identity
   }
  }
  ReplaceCoverageFixtureJson (Join-Path $version $sm.path) $BadSuite
  foreach($member in $index.members){$member.identity=Get-AiwTestFileIdentity (Join-Path $version $member.path)}
  ReplaceCoverageFixtureJson $indexPath $index;$candidate.proofBundleRef.identity=Get-AiwTestFileIdentity $indexPath
  $candidate.proofBundleIdentity=(Get-AiwReleaseMemberFacts (@(@{path=$candidate.proofBundleRef.path;identity=$candidate.proofBundleRef.identity})+@($index.members))).Canonical
  $candidate.currentSuiteRef.identity=@($index.members|Where-Object id -CEQ $sm.id)[0].identity
  $candidate.revalidationRefs=@($BadSuite.records|Where-Object executionKind -CEQ REVALIDATED|ForEach-Object{$id=$_.groupId+'.revalidated';$m=@($index.members|Where-Object id -CEQ $id)[0];@{path=$m.path;identity=$m.identity}})
  foreach($ref in $candidate.groupRecordRefs){$ref.identity=@($index.members|Where-Object path -CEQ $ref.path)[0].identity}
  $candidate.prepackageIntegrationRefs=@($candidate.groupRecordRefs|Where-Object groupId -CEQ 'integration.full-source'|ForEach-Object{@{path=$_.path;identity=$_.identity}})
  return $candidate
 }
 # One fault table reaches the same executed2 contract through local and portable adapters.
 $nativeCauses=[ordered]@{PRODUCER_NAME='TEST_PRODUCER_PROVENANCE';MISSING_INPUT='TEST_BEHAVIOR_INPUT_CLOSURE';PRODUCER_TYPE='TEST_PRODUCER_PROVENANCE';PRODUCER_EXTRA='RELEASE_FIELDS\|producer';RECORD_EXTRA='RELEASE_FIELDS\|executed2';BEHAVIOR='TEST_RECORD_FAILED_PARTIAL_OR_INPUT_DRIFT';CONTEXT='TEST_EXECUTION_CONTEXT_BINDING'}
 foreach($fault in $nativeCauses.Keys){
  $badRecord=Read-AiwTestJson $aPath -StringFields @('startedUtc','endedUtc')
  switch($fault){'PRODUCER_NAME'{$badRecord.producer.name='Other'} 'MISSING_INPUT'{foreach($snap in @($badRecord.before,$badRecord.after)){$snap.facts.inputs=@($snap.facts.inputs|Where-Object path -CNE $aValue);$helper=Import-Module (Join-Path $PSScriptRoot '../scripts/TestEvidenceValidation.psm1') -PassThru;$snap.facts.behaviorContractIdentity=& $helper.ExportedCommands['Get-AiwEvidenceBehaviorIdentity'] $snap.facts;$snap.identity=Get-TestValueIdentity $snap.facts};$badRecord.behaviorContractIdentity=$badRecord.after.facts.behaviorContractIdentity} 'PRODUCER_TYPE'{$badRecord.producer.contractVersion='2'} 'PRODUCER_EXTRA'{$badRecord.producer|Add-Member extra $true} 'RECORD_EXTRA'{$badRecord|Add-Member extra $true} 'BEHAVIOR'{$badRecord.behaviorContractIdentity='A'*64} 'CONTEXT'{$badRecord.executionContext.controlRoot=$sample}}
  $badRecordPath=Join-Path $rawRoot ('native2-'+$fault+'.json');Write-AiwTestJson $badRecordPath $badRecord
  $badSuite=CloneEvidence $suite @('startedUtc','endedUtc');$entry=@($badSuite.records|Where-Object groupId -CEQ proof.a)[0];$entry.path=$badRecordPath;$entry.identity=Get-AiwTestFileIdentity $badRecordPath
  $rv=Read-AiwTestJson (Join-Path $rawRoot 'coverage-repair-groups/proof.a/revalidation.json') -StringFields @('checkedUtc');$rv.original.path=$badRecordPath;$rv.original.identity=$entry.identity
  $rp=Join-Path $rawRoot ('native2-rv-'+$fault+'.json');Write-AiwTestJson $rp $rv;$entry.revalidation=@{path=$rp;identity=(Get-AiwTestFileIdentity $rp)}
  $sp=Join-Path $rawRoot ('native2-suite-'+$fault+'.json');Write-AiwTestJson $sp $badSuite
  Reject {Assert-AiwTestSuiteEvidence $sp $stable (Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json') -CurrentCoverage} ('^'+$nativeCauses[$fault]+'$') ('native2-local-'+$fault)
  try{$badProof=BindCounterexampleBundle $badSuite @{'proof.a'=$rv} @{'proof.a'=$badRecord};Reject {& $reader.ExportedCommands['Assert-AiwReleaseProof'] $version ([pscustomobject]@{validationProof=$badProof}) -SourceRoot $sample} ('^'+$nativeCauses[$fault]+'$') ('native2-portable-'+$fault)}finally{ResetCounterexampleBundle}
 }
 $proofCauses=@{MISSING='RELEASE_CURRENT_SUITE_PROOF_PARTITION';BASELINE='RELEASE_CURRENT_COVERAGE_BASELINE_FORBIDDEN';VERSION='RELEASE_FIELDS\|validation-proof';RECURSIVE='RELEASE_CURRENT_SUITE_PROOF_PARTITION';UNKNOWN='RELEASE_FIELDS\|validation-proof';DELETE_RV='RELEASE_CURRENT_SUITE_REVALIDATION_PARTITION';WRONG_SUITE='RELEASE_CURRENT_SUITE_BINDING'}
 foreach($kind in $proofCauses.Keys){
  $bad=Clone $proof
  switch($kind){'MISSING'{$bad.groupRecordRefs=@($bad.groupRecordRefs|Where-Object groupId -CNE proof.a)} 'BASELINE'{$bad.baselineRef=$bad.proofBundleRef} 'VERSION'{$bad.schemaVersion=1} 'RECURSIVE'{$bad.groupRecordRefs[0].path=$bad.revalidationRefs[0].path;$bad.groupRecordRefs[0].identity=$bad.revalidationRefs[0].identity} 'UNKNOWN'{$bad|Add-Member bypass $true} 'DELETE_RV'{$bad.revalidationRefs=@()} 'WRONG_SUITE'{$bad.currentSuiteRef=$bad.proofBundleRef}}
  Reject {& $reader.ExportedCommands['Assert-AiwReleaseProof'] $version ([pscustomobject]@{validationProof=$bad}) -SourceRoot $sample} ('^'+$proofCauses[$kind]+'$') ('current-reader-reject-'+$kind.ToLowerInvariant())
 }
 $negativeFailures=[Collections.Generic.List[object]]::new()
 function ObserveIndependentNegative([scriptblock]$Body,[string]$Pattern,[string]$Name,[string[]]$KnownPatterns){
  $reason='';try{$null=& $Body}catch{$reason=$_.Exception.Message}
  $matched=$reason-cmatch$Pattern
  $row=@{name=$Name;expected=$Pattern;actual=$reason;outcome=$(if($matched){'PASS'}else{'FAIL'});acceptedWithoutException=([string]::IsNullOrEmpty($reason))}
  Write-AiwTestJson (Join-Path $rawRoot ('observed-'+$Name+'.json')) $row
  if($matched){Check ($true) ($Name+'|reason='+$reason);return}
  $negativeFailures.Add($row);Write-Output ('FAIL|'+$Name+'|expected='+$Pattern+'|reason='+$reason)
  if([string]::IsNullOrEmpty($reason)){throw ('COUNTEREXAMPLE_UNSAFE_ACCEPTANCE|'+$Name)}
  if($reason-cnotmatch('^('+($KnownPatterns-join'|')+')$')){throw ('COUNTEREXAMPLE_UNKNOWN_FAILURE|'+$Name+'|'+$reason)}
 }
 $rvPath=Join-Path $rawRoot 'coverage-repair-groups/proof.a/revalidation.json';$rvOriginal=[IO.File]::ReadAllBytes($rvPath)
 $rvCauses=[ordered]@{FAILED='RELEASE_CURRENT_REVALIDATION_SCALAR';SCHEMA='RELEASE_CURRENT_REVALIDATION_SCALAR';GROUP='RELEASE_STRING\|revalidation\|groupId';REASON='RELEASE_CURRENT_REVALIDATION_SCALAR';PATH='RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT';SNAPSHOT='RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT';VALIDATOR='RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT';RECURSIVE='RELEASE_CURRENT_REVALIDATION_SCALAR';UNKNOWN='RELEASE_FIELDS\|revalidation';TIME='RELEASE_EVIDENCE_TIME\|revalidation-checked';TIME_ZERO='INPUT_STRING_FIELD_TYPE\|checkedUtc';TIME_NULL='INPUT_STRING_FIELD_TYPE\|checkedUtc';TIME_TRUE='INPUT_STRING_FIELD_TYPE\|checkedUtc';TIME_ARRAY='INPUT_STRING_FIELD_TYPE\|checkedUtc';TIME_OBJECT='INPUT_STRING_FIELD_TYPE\|checkedUtc';TIME_WINDOW='RELEASE_CURRENT_REVALIDATION_WINDOW'}
 foreach($kind in $rvCauses.Keys){
  $rv=Read-AiwTestJson $rvPath -StringFields @('checkedUtc')
  switch($kind){'SCHEMA'{$rv.schemaVersion='1'} 'GROUP'{$rv.groupId=@('proof.a')} 'FAILED'{$rv.outcome='FAIL'} 'REASON'{$rv.reason='unproven'} 'PATH'{$rv.original.path=$rvPath} 'SNAPSHOT'{$rv.currentSnapshot.identity=if($rv.currentSnapshot.identity-ceq('A'*64)){'B'*64}else{'A'*64}} 'VALIDATOR'{$rv.validatorIdentity='1|'+('A'*64)} 'RECURSIVE'{$rv.executionKind='EXECUTED'} 'UNKNOWN'{$rv|Add-Member extra $true} 'TIME'{$rv.checkedUtc='2026-10-09T10:00:00'} 'TIME_ZERO'{$rv.checkedUtc=0} 'TIME_NULL'{$rv.checkedUtc=$null} 'TIME_TRUE'{$rv.checkedUtc=$true} 'TIME_ARRAY'{$rv.checkedUtc=@('2026-10-09T10:00:00Z')} 'TIME_OBJECT'{$rv.checkedUtc=@{value='2026-10-09T10:00:00Z'}} 'TIME_WINDOW'{$rv.checkedUtc='2000-01-01T00:00:00Z'}}
  $badRv=Join-Path $rawRoot ('coverage-'+$kind+'.json');Write-AiwTestJson $badRv $rv;$badSuite=CloneEvidence $suite @('startedUtc','endedUtc');@($badSuite.records|Where-Object groupId -CEQ proof.a)[0].revalidation=@{path=$badRv;identity=(Get-AiwTestFileIdentity $badRv)};$badPath=Join-Path $rawRoot ('coverage-suite-'+$kind+'.json');Write-AiwTestJson $badPath $badSuite
  $pattern='^'+$rvCauses[$kind]+'$'
  ObserveIndependentNegative {Assert-AiwTestSuiteEvidence $badPath $stable (Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json') -CurrentCoverage} $pattern ('local-v3-reject-'+$kind.ToLowerInvariant()) @(@($rvCauses.Values)+@('RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS'))
  try{$badProof=BindCounterexampleBundle $badSuite @{ 'proof.a'=$rv };ObserveIndependentNegative {& $reader.ExportedCommands['Assert-AiwReleaseProof'] $version ([pscustomobject]@{validationProof=$badProof}) -SourceRoot $sample} $pattern ('portable-v3-reject-'+$kind.ToLowerInvariant()) @(@($rvCauses.Values)+@('RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS'))}finally{ResetCounterexampleBundle}
 }
 $crossRecord=Read-AiwTestJson $aPath -StringFields @('startedUtc','endedUtc');$crossRecord.schemaVersion=1
 $crossRecordPath=Join-Path $rawRoot 'suite3-crossed-native1.json';Write-AiwTestJson $crossRecordPath $crossRecord
 $crossSuite=CloneEvidence $suite @('startedUtc','endedUtc');$crossRef=@($crossSuite.records|Where-Object groupId -CEQ 'proof.a')[0];$crossRef.path=$crossRecordPath;$crossRef.identity=Get-AiwTestFileIdentity $crossRecordPath
 $crossPath=Join-Path $rawRoot 'suite3-crossed-suite.json';Write-AiwTestJson $crossPath $crossSuite
 Reject {Assert-AiwTestSuiteEvidence $crossPath $stable (Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json') -CurrentCoverage} '^TEST_EXECUTION_SUITE_VERSION_MISMATCH$' 'guard-suite3-rejects-native1-before-dispatch'
 # Same original A relabelled as fresh must fail its current execution window.
 foreach($kind in @('OLD_FRESH','WINDOW','DUPLICATE','MISSING','OPTIONS','ROOT','UNKNOWN_REUSE')){
  $badSuite=CloneEvidence $suite @('startedUtc','endedUtc');$rvMap=@{}
  switch($kind){
   'OLD_FRESH'{$entry=@($badSuite.records|Where-Object groupId -CEQ proof.a)[0];$entry.executionKind='EXECUTED';$entry.revalidation=$null}
   'WINDOW'{$badSuite.startedUtc='2100-01-01T00:00:00Z';$badSuite.endedUtc='2100-01-02T00:00:00Z'}
   'DUPLICATE'{$badSuite.records+=@($badSuite.records[0])}
   'MISSING'{$badSuite.records=@($badSuite.records|Where-Object groupId -CNE proof.b)}
   'OPTIONS'{$badSuite.options.MaintenanceFixture=$true}
   'ROOT'{$badSuite.sourceRoot=$rootNegativeView.Root}
   'UNKNOWN_REUSE'{$entry=@($badSuite.records|Where-Object groupId -CEQ 'integration.full-source')[0];$original=Read-AiwTestJson $entry.path;$rv=Read-AiwTestJson $rvPath -StringFields @('checkedUtc');$rv.groupId=$entry.groupId;$rv.original=[pscustomobject]@{path=$entry.path;identity=$entry.identity};$rv.currentSnapshot=$original.after;$rv.validatorIdentity=$original.after.facts.verifierIdentity;$rv.verifierRef=$suite.verifierRef;$rv.verifiedBehaviorIdentity=$original.behaviorContractIdentity;$rp=Join-Path $rawRoot 'unknown-integration-rv.json';Write-AiwTestJson $rp $rv;$entry.executionKind='REVALIDATED';$entry.revalidation=[pscustomobject]@{path=$rp;identity=(Get-AiwTestFileIdentity $rp)};$rvMap[$entry.groupId]=$rv}
  }
  $badPath=Join-Path $rawRoot ('coverage-partition-'+$kind+'.json');Write-AiwTestJson $badPath $badSuite
  $local=@{OLD_FRESH='RELEASE_CURRENT_EXECUTION_WINDOW';WINDOW='RELEASE_CURRENT_REVALIDATION_WINDOW';DUPLICATE='RELEASE_CURRENT_SUITE_PARTITION';MISSING='RELEASE_CURRENT_SUITE_PARTITION';OPTIONS='TEST_RECORD_FAILED_PARTIAL_OR_INPUT_DRIFT';ROOT='TEST_RECORD_FAILED_PARTIAL_OR_INPUT_DRIFT';UNKNOWN_REUSE='TEST_FRESH_REQUIRED'}
  ObserveIndependentNegative {Assert-AiwTestSuiteEvidence $badPath $stable (Join-Path $stable 'framework/versions/2.0.0/tests/test-groups.json') -CurrentCoverage} ('^('+$local[$kind]+')$') ('local-partition-reject-'+$kind.ToLowerInvariant()) @(@($local.Values)+@('RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT','RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS'))
  # Duplicate/missing membership is rejected before alias traversal; do not
  # fabricate extra aliases just to test an already invalid partition.
  try{
   $badProof=if($kind-cin@('DUPLICATE','MISSING')){BindCounterexampleBundle $suite}else{BindCounterexampleBundle $badSuite $rvMap}
   if($kind-cin@('DUPLICATE','MISSING')){$sm=@($baseIndex.members|Where-Object kind -CEQ CURRENT_SUITE)[0];ReplaceCoverageFixtureJson (Join-Path $version $sm.path) $badSuite;$idx=Read-AiwTestJson $indexPath;@($idx.members|Where-Object id -CEQ $sm.id)[0].identity=Get-AiwTestFileIdentity (Join-Path $version $sm.path);ReplaceCoverageFixtureJson $indexPath $idx;$badProof.currentSuiteRef.identity=Get-AiwTestFileIdentity (Join-Path $version $sm.path);$badProof.proofBundleRef.identity=Get-AiwTestFileIdentity $indexPath;$badProof.proofBundleIdentity=(Get-AiwReleaseMemberFacts (@(@{path=$badProof.proofBundleRef.path;identity=$badProof.proofBundleRef.identity})+@($idx.members))).Canonical}
   $portable=@{OLD_FRESH='RELEASE_CURRENT_EXECUTION_WINDOW';WINDOW='RELEASE_CURRENT_REVALIDATION_WINDOW';DUPLICATE='RELEASE_CURRENT_SUITE_PARTITION';MISSING='RELEASE_CURRENT_SUITE_PARTITION';OPTIONS='RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS';ROOT='RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS';UNKNOWN_REUSE='RELEASE_CURRENT_REVALIDATION_FRESH_REQUIRED'}
   ObserveIndependentNegative {& $reader.ExportedCommands['Assert-AiwReleaseProof'] $version ([pscustomobject]@{validationProof=$badProof}) -SourceRoot $sample} ('^('+$portable[$kind]+')$') ('portable-partition-reject-'+$kind.ToLowerInvariant()) @(@($portable.Values)+@('RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT'))
  }finally{ResetCounterexampleBundle}
 }
 Write-AiwTestJson (Join-Path $rawRoot 'counterexample-table-failures.json') @{count=$negativeFailures.Count;failures=@($negativeFailures.ToArray())}
 Check ($negativeFailures.Count-eq0) 'independent-negative-tables-all-exact-reasons'
 $rawMember=@($baseIndex.members|Where-Object{$_.kind-ceq'STDOUT'-and$_.id-ceq'proof.b.stdout'})[0];[IO.File]::AppendAllText((Join-Path $version $rawMember.path),'corruption')
 try{Reject {& $reader.ExportedCommands['Assert-AiwReleaseProof'] $version $manifest -SourceRoot $sample} '^RELEASE_BUNDLE_MEMBER_DRIFT$' 'portable-original-raw-corruption-is-rejected'}finally{ResetCounterexampleBundle}
 Check ((Get-AiwTestFileIdentity $rvPath)-ceq(Get-AiwReleaseByteIdentity $rvOriginal)-and(Get-AiwTestFileIdentity $aPath)-ceq$aIdentity) 'counterexamples-preserve-original-revalidation-and-execution'
 if($V1ReaderPath){
  $oldPath=Assert-AiwTestPath $V1ReaderPath;$dependency=Join-Path (Split-Path -Parent $oldPath) 'StrictJsonInput.psm1'
  Check ((Get-AiwTestFileIdentity $oldPath)-ceq'50199|8BCC83003D7D5DB972A5355B015326A872ED1181C5AE024BBC1D1CB9FF8E4330'-and(Get-AiwTestFileIdentity $dependency)-ceq'2207|99DFD33C465B52489FCFC760939FE4842AA7E515C1488FA611B08A11855D506A') 'old-reader-and-complete-original-dependency-bound'
  $cold=Join-Path $rawRoot 'old-reader-v2-cold.ps1';Put $cold ((@'
param([string]$Reader,[string]$Version,[string]$Source,[string]$Proof)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop';$module=Import-Module $Reader -PassThru;$dependencies=@(Get-Module -All StrictJsonInput)
if($module.Path-cne$Reader-or$dependencies.Count-ne1-or$dependencies[0].Path-cne(Join-Path (Split-Path -Parent $Reader) 'StrictJsonInput.psm1')){throw 'COLD_READER_OWNER'}
$wire=Get-Content -LiteralPath $Proof -Raw|ConvertFrom-Json -Depth 100
try{$null=& $module.ExportedCommands['Assert-AiwReleaseProof'] $Version ([pscustomobject]@{validationProof=$wire}) -SourceRoot $Source;throw 'OLD_READER_ACCEPTED_V2'}catch{if($_.Exception.Message-cne'RELEASE_FIELDS|validation-proof'){throw};'OLD_READER_REJECTS_EXPLICIT_V2_AFTER_DEPENDENCY_LOAD'}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$cold,'-Reader',$oldPath,'-Version',$version,'-Source',$sample,'-Proof',$proofPath) -WorkingDirectory $sample -EvidenceDirectory (Join-Path $rawRoot 'old-reader-v2-native')
  Check ($run.Code-eq0-and$run.StdoutText.Contains('OLD_READER_REJECTS_EXPLICIT_V2_AFTER_DEPENDENCY_LOAD')) 'actual-cold-v1-reader-rejects-explicit-v2'
 }
 # One same-candidate matched pair: compare this genuine repair/resume with a
 # full fresh run AFTER the local repair, under the same definition/env/root.
 $fresh=RunCoverage 'coverage-matched-fresh';Check ($fresh.Code-eq0) 'matched-current-candidate-real-fresh-complete-run'
 $costRepair=Read-AiwTestJson (Join-Path $rawRoot 'coverage-repair-groups/execution-cost.json');$costFresh=Read-AiwTestJson (Join-Path $rawRoot 'coverage-matched-fresh-groups/execution-cost.json')
 $saved=100*(1-$costRepair.totalMilliseconds/$costFresh.totalMilliseconds);$w=(Read-AiwTestJson $a.processResult.path).timing.wallMilliseconds
 Write-AiwTestJson (Join-Path $rawRoot 'coverage-cost-comparison.json') @{schemaVersion=1;scope='SYNTHETIC_COMPLETE_REQUIRED_SET_ONLY';fresh=$costFresh;repairResume=$costRepair;sampleImprovementPercent=$saved;sampleTargetPercent=20;sampleTargetMet=($saved-ge20);unchangedOriginalNativeMilliseconds=$w;counterfactualAvoidedMilliseconds=($w-$costRepair.preflightMilliseconds-$costRepair.revalidationMilliseconds);counterfactualSemantics='W minus planning/revalidation is an estimate, not measured net total savings';originalSlowGroupAndB3Targets='PENDING'}
 Check ($costRepair.newGroupChildCount-eq2-and$costFresh.newGroupChildCount-eq3) 'cost-records-real-starts-and-no-unexplained-a-reexecution'
 $freshA=Join-Path $rawRoot 'coverage-matched-fresh-groups/proof.a/executed.json';$later=RunCoverage 'coverage-later-original' @($freshA,(Join-Path $rawRoot 'coverage-matched-fresh-groups/proof.b/executed.json')) -Summary
 Check ($later.Code-eq0-and$later.Transcript.Contains('GROUP|proof.a|REVALIDATED')-and$later.Transcript.Contains('GROUP|proof.b|REVALIDATED')) 'later-independent-original-executed-records-and-summary-use-complete-v3'
 TestFinalSuiteAndOwnership $freshA $aPath $aIdentity
 # A current verifier-only byte change may reuse behavior-independent literals.
 # Both runner and reader start in new native processes from that physical fixture.
 Check ((Test-Path -LiteralPath $stable -PathType Container)-and(Test-Path -LiteralPath ($stable+'.owner.json') -PathType Leaf)) 'current-verifier-keeps-existing-owned-view-without-root-recreation'
 $verifierPath=Join-Path $version 'scripts/TestEvidenceValidation.psm1';$verifierBytes=[IO.File]::ReadAllBytes($verifierPath)
 try{
  [IO.File]::AppendAllText($verifierPath,"`n# owned verifier-only non-behavior change`n")
  $reverified=RunCoverage 'coverage-current-verifier' @($freshA,(Join-Path $rawRoot 'coverage-matched-fresh-groups/proof.b/executed.json'))
  Check ($reverified.Code-eq0-and$reverified.StdoutText.Contains('GROUP|proof.a|REVALIDATED')-and$reverified.StdoutText.Contains('GROUP|proof.b|REVALIDATED')) 'current-verifier-change-rechecks-original-native-facts-with-zero-new-a-b'
  $newProofPath=Join-Path $rawRoot 'coverage-current-verifier-groups/prepackage-proof/validation-proof.json';$newProof=Read-AiwTestJson $newProofPath;$newBundle=Split-Path -Parent $newProofPath
  $coldVersion=Join-Path $temp 'verifier-reader-tree';$null=New-AiwTestSourceView $sample $coldVersion $d;$coldV=Join-Path $coldVersion 'framework/versions/2.0.0'
  Copy-AiwTestAllowlist $newBundle $coldV @((Get-AiwReleaseTreeMembers (Join-Path $newBundle 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
  $probe=Join-Path $rawRoot 'current-verifier-reader.ps1';Put $probe ((@'
param([string]$Reader,[string]$Version,[string]$Source,[string]$Proof)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
$owner=Import-Module $Reader -PassThru
if($owner.Path-cne$Reader){throw 'CURRENT_READER_OWNER'}
$wire=Get-Content -LiteralPath $Proof -Raw|ConvertFrom-Json -Depth 100
$result=& $owner.ExportedCommands['Assert-AiwReleaseProof'] $Version ([pscustomobject]@{validationProof=$wire}) -SourceRoot $Source
if($result.Mode-cne'CURRENT_GROUP_COVERAGE'){throw 'CURRENT_READER_RESULT'}
'PASS|current-physical-verifier-consumed-old-native-originals'
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
  $cold=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$probe,'-Reader',(Join-Path $version 'scripts/ReleaseValidation.psm1'),'-Version',$coldV,'-Source',$sample,'-Proof',$newProofPath) -WorkingDirectory $sample -EvidenceDirectory (Join-Path $rawRoot 'current-verifier-cold')
  Check ($cold.Code-eq0-and$cold.StdoutText.Contains('PASS|current-physical-verifier')) 'new-physical-reader-validates-new-proof-and-immutable-originals'
  Reject {& $reader.ExportedCommands['Assert-AiwReleaseProof'] $coldV ([pscustomobject]@{validationProof=$newProof}) -SourceRoot $sample} 'RELEASE_CURRENT_VERIFIER_BINDING' 'stale-loaded-reader-cannot-pretend-to-be-current-verifier'
 }finally{[IO.File]::WriteAllBytes($verifierPath,$verifierBytes)}

 TestPublicExactResume @($aPath,$bPath)
 Write-Output ('CURRENT_COVERAGE_COST|sampleImprovementPercent='+$saved+'|targetMet='+($saved-ge20)+'|originalTargets=PENDING')
}
try{
 if($ExecutionTargetOnly){TestActualTargetProducer;Write-Output ('PARTIAL|EXECUTION_TARGET_ONLY|checks='+$passed+'|fixture='+$temp);return}
 if($GuardFixturePath){
  $fixture=Read-AiwTestJson $GuardFixturePath
  foreach($ref in @($fixture.record,$fixture.revalidation,$fixture.suite,$fixture.legacyRecord,$fixture.legacySuite,$fixture.manifest)){if((Get-AiwTestFileIdentity $ref.path)-cne$ref.identity){throw 'GUARD_RETAINED_REFERENCE_DRIFT'}}
  TestEvidenceGuardContracts $fixture.record.path $fixture.revalidation.path $fixture.suite.path $fixture.group
  $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
  TestManifestGuardContracts $reader (Read-AiwTestJson $fixture.manifest.path)
  TestLegacyExecutionGuardContracts $reader $fixture.legacyRecord.path $fixture.group (Read-AiwTestJson $fixture.legacySuite.path -StringFields @('startedUtc','endedUtc'))
  Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=retained-production-guard-contracts');return
 }
 if($IntegrationConsumerContractOnly){
  if($FixtureContractOnly-or$ToolResolutionContractOnly-or$Group-cnotin@('All','Core')){throw 'INTEGRATION_CONSUMER_CONTRACT_FLAGS'}
  TestIntegrationConsumerContracts
  Write-Output ('PARTIAL|INTEGRATION_CONSUMER_CONTRACT_ONLY|code=0|status=PASS|checks='+$passed);return
 }
 if($Group-cin@('All','Core')){TestIntegrationConsumerContracts}
 if($ToolResolutionContractOnly){
  if($FixtureContractOnly-or$Group-cnotin@('All','Core')){throw 'TOOL_RESOLUTION_CONTRACT_FLAGS'}
  TestFiniteDependencyMappings -ToolResolutionContractOnly
  Write-Output ('PARTIAL|TOOL_RESOLUTION_CONTRACT_ONLY|code=0|status=PASS|scope=tool-path-restoration-and-allowlist|checks='+$passed);return
 }
 if($Group-ceq'CurrentCoverage'-and$FixtureContractOnly){TestSourceReadClosure}
 if($Group-cin@('CurrentCoverage','FinalSuiteAndOwnership')){TestCurrentCoverage -FinalSuiteAndOwnershipOnly:($Group-ceq'FinalSuiteAndOwnership');if($Group-ceq'FinalSuiteAndOwnership'){Write-Output ('PARTIAL|FINAL_SUITE_AND_OWNERSHIP_ONLY|checks='+$passed);return};if(-not($FixtureContractOnly-or$PublicSuiteConsumerContractOnly-or$FailureTransportOnly-or$WorkerCompletionOnly)){Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=test-group-evidence')};return}
 TestSourceReadClosure
 foreach($name in @('TestHarness.psm1','TestNativeOutput.psm1','TestExecutionRuntime.psm1','TestGroupEvidence.psm1')){[IO.File]::Copy((Join-Path $PSScriptRoot $name),(Join-Path $tests $name))}
 foreach($name in @('ReleaseValidation.psm1','TestEvidenceValidation.psm1','StrictJsonInput.psm1')){[IO.File]::Copy((Join-Path $PSScriptRoot ('../scripts/'+$name)),(Join-Path ([IO.Directory]::CreateDirectory((Join-Path $tests '../scripts'))).FullName $name))}
 Put (Join-Path $tests 'run-framework-tests.ps1') '# fixture runner definition'
 $entry=Join-Path $tests 'proof-child.ps1';Put $entry "Write-Output 'PASS|first-target';Write-Output 'PASS|second-target';Write-Output 'RESULT|2/2 passed|scope=proof-child'"
 $fixtureGroup=[ordered]@{id='proof.child';entry='framework/versions/2.0.0/tests/proof-child.ps1';arguments=@();phase='PREPACKAGE';requiredFor=@('FULL');casePolicy='OBSERVED_NAMED_CASES';requiredCaseIds=@('first-target','second-target');completionPattern='^RESULT\|2/2 passed\|scope=proof-child$';dependencies=@();unknownDependencies=@();alwaysFresh=$false;fixturePolicy='MECHANISM';tools=@('pwsh')}
 $definitionPath=Join-Path $tests 'test-groups.json'
 $secondGroup=Clone $fixtureGroup;$secondGroup.id='proof.second'
 Write-AiwTestJson $definitionPath @{schemaVersion=1;phase='PREPACKAGE';mechanismVersionPaths=@();rootAdoptionPaths=@();maintenancePaths=@();groups=@($fixtureGroup,$secondGroup)}
 $definition=Read-AiwTestGroupDefinition $definitionPath;$fixtureGroup=$definition.groups[0];$options=[ordered]@{sample='typed-original'}
 $before=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fixtureGroup $options
 $process=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$entry) -WorkingDirectory $root -EvidenceDirectory $rawRoot -GroupId $fixtureGroup.id
 $after=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fixtureGroup $options
 $cleanRoot=Join-Path $temp 'empty-fixture';$null=[IO.Directory]::CreateDirectory($cleanRoot)
 $cleanup=@{status='CLEAN';root=$cleanRoot;entries=@();workers=@()};$recordPath=Join-Path $rawRoot 'original-executed.json'
 $record=Complete-AiwTestGroupEvidence $recordPath $fixtureGroup $before $after $process $cleanup
 Check (Assert-AiwTestGroupEvidence $record $fixtureGroup $after) 'real-command-raw-inputs-named-cases-and-cleanup-complete'
 $originalIdentity=Get-AiwTestFileIdentity $recordPath
 $selection=Select-AiwTestGroupExecution $fixtureGroup $after @($recordPath) (Join-Path $rawRoot 'revalidation.json')
 Check ($selection.selection-ceq'REUSE_WITH_REVALIDATION'-and(Get-AiwTestFileIdentity $recordPath)-ceq$originalIdentity-and$selection.original.identity-ceq$originalIdentity) 'reuse-keeps-original-command-time-and-record-immutable'
 foreach($mutation in @('FAILED','PARTIAL','DUPLICATE_CASE','MISSING_CASE','BAD_BEFORE','DIRTY_RESET','VALIDATOR_DRIFT','UNKNOWN_FIELD')){
  $bad=Clone $record
  switch($mutation){
   'FAILED' {$bad.outcome='FAIL'}
   'PARTIAL' {$bad.completion='MISSING'}
   'DUPLICATE_CASE' {$bad.cases+=@($bad.cases[0])}
   'MISSING_CASE' {$bad.cases=@($bad.cases[0])}
   'BAD_BEFORE' {$bad.before.identity='0'*64}
   'DIRTY_RESET' {$bad.cleanup.status='DIRTY'}
   'VALIDATOR_DRIFT' {$bad.validatorIdentity='1|'+('E'*64)}
   'UNKNOWN_FIELD' {$bad|Add-Member bypass $true}
  }
  Reject {Assert-AiwTestGroupEvidence $bad $fixtureGroup $after} 'TEST_' ('reject-'+$mutation.ToLowerInvariant())
 }
 $badPath=Join-Path $rawRoot 'duplicate-members.json';Put $badPath '{"schemaVersion":1,"schemaVersion":1}'
 Reject {Read-AiwTestJson $badPath} 'DUPLICATE_MEMBER' 'json-duplicate-member-is-not-normalized-away'
 $copy=Clone $definition;$copy.groups+=@($copy.groups[0]);$badDefinition=Join-Path $temp 'duplicate-group.json';Write-AiwTestJson $badDefinition $copy
 Reject {Read-AiwTestGroupDefinition $badDefinition} 'GROUP_ID' 'duplicate-definition-group-rejected'
 $rawBytes=[IO.File]::ReadAllBytes($process.Record.stdout.path)
 try{
  [IO.File]::AppendAllText($process.Record.stdout.path,'corrupt')
  Reject {Assert-AiwTestGroupEvidence $record $fixtureGroup $after} 'RAW_CORRUPT' 'raw-byte-corruption-invalidates-original-proof'
 }finally{[IO.File]::WriteAllBytes($process.Record.stdout.path,$rawBytes)}
 Put (Join-Path $cleanRoot 'dirty.txt') 'unexpected mutable residue'
 Reject {Assert-AiwTestGroupEvidence $record $fixtureGroup $after} 'CURRENTLY_DIRTY' 'current-reset-state-is-checked-again'
 Remove-Item -LiteralPath (Join-Path $cleanRoot 'dirty.txt')
 $fresh=Clone $fixtureGroup;$fresh.unknownDependencies=@('unclosed generated worker')
 $freshSnapshot=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fresh $options
 Check ((Select-AiwTestGroupExecution $fresh $freshSnapshot @($recordPath)).reason-ceq'FRESH_REQUIRED') 'unknown-real-dependency-forces-fresh-execution'
 $changedOptions=[ordered]@{sample='different'};$changed=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fixtureGroup $changedOptions
 Check ((Select-AiwTestGroupExecution $fixtureGroup $changed @($recordPath)).selection-ceq'EXECUTE') 'changed-options-refuse-old-execution'
 foreach($file in @('proof-child.ps1','TestHarness.psm1','test-groups.json')){
  $path=Join-Path $tests $file;$bytes=[IO.File]::ReadAllBytes($path)
  try{[IO.File]::AppendAllText($path,"`n");$changed=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fixtureGroup $options;Check ((Select-AiwTestGroupExecution $fixtureGroup $changed @($recordPath)).selection-ceq'EXECUTE') ('changed-input-'+$file+'-refuses-old-execution')}finally{[IO.File]::WriteAllBytes($path,$bytes)}
 }
 Reject {Select-AiwTestGroupExecution $fixtureGroup $after @($recordPath,$recordPath) (Join-Path $rawRoot 'duplicate-reuse.json')} 'DUPLICATE_RESUME' 'duplicate-original-records-never-count-twice'
 $driftBefore=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fixtureGroup $options
 [IO.File]::AppendAllText($entry,"`n# changed while group active")
 $driftAfter=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fixtureGroup $options
 $driftRecord=Complete-AiwTestGroupEvidence (Join-Path $rawRoot 'drift-executed.json') $fixtureGroup $driftBefore $driftAfter $process $cleanup
 Check ($driftRecord.outcome-ceq'INCOMPLETE') 'input-drift-during-execution-is-not-pass'
 Put $entry "Write-Output 'PASS|first-target';Write-Output 'PASS|second-target';Write-Output 'RESULT|2/2 passed|scope=proof-child'"
 $before=Get-AiwTestDependencySnapshot $root $definitionPath $definition $fixtureGroup $options
 $stop=Join-Path $temp 'stop.ps1';Put $stop "Write-Output 'PASS|partial-case'; Start-Sleep -Seconds 20"
 $handle=Start-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$stop) -WorkingDirectory $root -EvidenceDirectory $rawRoot -GroupId $fixtureGroup.id
 Stop-AiwTestProcess $handle -AuthorizedRunId $handle.RunId -Reason 'B1 independently authorized second-group interruption sample'
 do{$stopped=Wait-AiwTestProcess $handle}while($stopped.Status-ceq'RUNNING')
 $incomplete=Complete-AiwTestGroupEvidence (Join-Path $rawRoot 'interrupted-executed.json') $fixtureGroup $before $before $stopped $cleanup
 Check ($incomplete.outcome-ceq'INTERRUPTED'-and(Get-AiwTestFileIdentity $recordPath)-ceq$originalIdentity) 'second-group-interruption-preserves-first-original-and-has-no-pass'
 $suitePath=Join-Path $rawRoot 'missing-required-suite.json'
 Write-AiwTestJson $suitePath @{schemaVersion=1;phase='PREPACKAGE';definitionIdentity=(Get-AiwTestFileIdentity $definitionPath);requestedGroupIds=@($fixtureGroup.id,'proof.second');requiredGroupIds=@($fixtureGroup.id,'proof.second');records=@(@{groupId=$fixtureGroup.id;path=$recordPath;identity=$originalIdentity;executionKind='EXECUTED';revalidation=$null});outcome='PASS';coverage='PARTIAL';options=$options;startedUtc=$process.Record.startedUtc;endedUtc=$process.Record.endedUtc;qualification='SCHEMA2_PENDING'}
 Reject {Assert-AiwTestSuiteEvidence $suitePath $root $definitionPath} 'REQUESTED_GROUP_MISSING|REQUIRED_GROUP_MISSING' 'missing-not-run-successor-cannot-complete-suite'
 TestFiniteDependencyMappings
 if($Group-ceq'All'){TestCurrentCoverage}
 Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=test-group-evidence')
}catch{
 $groupEvidenceFirstFailure=$_
 throw
}finally{
 try{
 $full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
 if([IO.Path]::GetDirectoryName($full)-cne$parent-or[IO.Path]::GetFileName($full)-cnotmatch'^gev-[a-f0-9]{8}$'){throw 'GROUP_EVIDENCE_CLEANUP_SCOPE'}
 if($ExecutionTargetOnly){Write-Output ('FIXTURE_RETAINED|'+$full)}else{Remove-Item -LiteralPath $full -Recurse -Force}
 }catch{if($null-eq$groupEvidenceFirstFailure){throw};$groupEvidenceCleanupFailure=$_}
}
}catch{
 $failure=if($null-ne$groupEvidenceFirstFailure){$groupEvidenceFirstFailure}else{$_}
 $errorEnvelope=[ordered]@{status='FAIL';reason=[string]$failure.Exception.Message;scriptStackTrace=[string]$failure.ScriptStackTrace;fullyQualifiedErrorId=[string]$failure.FullyQualifiedErrorId}
 if($null-ne$groupEvidenceCleanupFailure){$errorEnvelope.cleanupError=[ordered]@{reason=[string]$groupEvidenceCleanupFailure.Exception.Message;scriptStackTrace=[string]$groupEvidenceCleanupFailure.ScriptStackTrace;fullyQualifiedErrorId=[string]$groupEvidenceCleanupFailure.FullyQualifiedErrorId}}
 [Console]::Error.WriteLine(($errorEnvelope|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii))
 exit 1
}
