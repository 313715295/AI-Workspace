[CmdletBinding()]
param([switch]$SkipPerformanceSmoke,[switch]$FixtureContractOnly,[switch]$RuleLoadingOnly)

$script:govPrimaryError=$null
$script:govCleanupError=$null
$script:govFailureChild=$null
$script:govLastNative=$null
$script:govFailureStage='INITIALIZATION'
try {
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
Import-Module (Join-Path $PSScriptRoot 'TestGroupEvidence.psm1')
$releaseReader=Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru
$utf8=[Text.UTF8Encoding]::new($false)
$script:passed=0

function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Invoke-Ps([string]$Script,[string[]]$Arguments,[hashtable]$Environment=@{}){
 $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) @(@('-NoProfile','-NonInteractive','-File',$Script)+$Arguments) -Environment $Environment -GroupId 'governance-direct-consumer'
 $script:govLastNative=[ordered]@{script=$Script;arguments=@($Arguments);exitCode=$native.Code;stdout=$native.StdoutText;stderr=$native.StderrText;nativeResult=[ordered]@{path=$native.ResultPath;identity=(Get-Identity $native.ResultPath)}}
 return $native
}
function Get-RequirementBlock([string]$Path,[string]$Id){$text=Get-Content -Raw -Encoding utf8 -LiteralPath $Path;$begin='<!-- AIW-REQUIREMENT:'+$Id+':BEGIN -->';$end='<!-- AIW-REQUIREMENT:'+$Id+':END -->';$first=$text.IndexOf($begin,[StringComparison]::Ordinal);$last=$text.IndexOf($end,[StringComparison]::Ordinal);if($first-lt0-or$last-le$first-or$text.IndexOf($begin,$first+1,[StringComparison]::Ordinal)-ge0-or$text.IndexOf($end,$last+1,[StringComparison]::Ordinal)-ge0){throw ('REQUIREMENT_BLOCK_CARDINALITY|'+$Id)};return $text.Substring($first+$begin.Length,$last-($first+$begin.Length)).Trim()}

$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$repositoryRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $versionRoot '..\..\..')))
Assert-True ($releaseReader.ExportedCommands.ContainsKey('Get-AiwReleasePayloadFacts')-and$releaseReader.ExportedCommands['Get-AiwReleasePayloadFacts'].Module.Path-ceq$releaseReader.Path) 'governance-cold-consumer-binds-owned-release-reader'
function Test-CurrentRuleLoadingContract {
 $catalogPath=Join-Path $versionRoot 'PROCESS_REQUIREMENTS.json'
 $catalog=Get-Content $catalogPath -Raw|ConvertFrom-Json -Depth 100
 $budget=Get-Content (Join-Path $PSScriptRoot 'PROCESS_REQUIREMENTS_BUDGETS.json') -Raw|ConvertFrom-Json -Depth 100
 $body=Get-RequirementBlock (Join-Path $versionRoot 'RECOVERY_CORE.md') 'PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES'
 $tool=Get-Content (Join-Path $versionRoot 'TOOL_CONTRACT.md') -Raw
 Assert-True ($budget.candidate.catalogIdentity-ceq(Get-Identity $catalogPath)) 'rule-loading-budget-binds-current-generated-catalog'
 Assert-True (@($catalog.requirements|Where-Object requirementId -CEQ 'PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES').Count-eq1-and$body.Contains('同次去重')-and$body.Contains('不调用正文装配或显示')-and$body.Contains('summary、hash、旧receipt或机械PASS不能替代实际缺失正文')-and$tool.Contains('RULE_LOAD_PRELOAD_RETIRED')-and$tool.Contains('actionRebind')) 'rule-loading-contract-preserves-complete-body-and-current-action-boundary'
}
Test-CurrentRuleLoadingContract
if($RuleLoadingOnly){Write-Output 'GOVERNANCE_RULE_LOADING_PASS|scope=current-contract-and-generated-catalog-consumer';return}
if($FixtureContractOnly){
 $measurement=Invoke-Ps (Join-Path $PSScriptRoot 'measure-process-requirements.ps1') @('-Warmups','1','-MeasuredRuns','1','-AsJson','-FixtureContractOnly')
 if($measurement.Code-ne0-or-not$measurement.Text.Contains('PARTIAL|FIXTURE_CONTRACT_ONLY|measurement|code=0|status=PASS|')){throw ('FIXTURE_PREFIX_FAILED|governance|native='+$measurement.Code+'|stdout='+$measurement.StdoutText+'|stderr='+$measurement.StderrText)}
 Assert-True ($true) 'finite-governance-direct-measurement-consumer'
 Write-Output 'PARTIAL|FIXTURE_CONTRACT_ONLY|governance|code=0|status=PASS|reason=REAL_MEASUREMENT_CONSUMER_REACHED';return
}
$catalogPath=Join-Path $versionRoot 'PROCESS_REQUIREMENTS.json'
$catalogGenerator=Join-Path $versionRoot 'scripts\build-process-requirements.ps1'
$catalogText=Get-Content -Raw -Encoding utf8 -LiteralPath $catalogPath
$catalog=$catalogText|ConvertFrom-Json
$inventory=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'NORMATIVE_SURFACE_INVENTORY.json')|ConvertFrom-Json
$budget=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'tests\PROCESS_REQUIREMENTS_BUDGETS.json')|ConvertFrom-Json

$script:govFailureStage='GENERATOR_CHECK'
$catalogCheck=Invoke-Ps $catalogGenerator @('-Check')
if($catalogCheck.Code-ne0){
 $script:govFailureChild=$script:govLastNative
 throw ('GOVERNANCE_GENERATOR_CHECK_FAILED|native='+$catalogCheck.Code+'|'+$catalogCheck.StdoutText.Trim())
}
Assert-True ($catalogCheck.Code-eq0-and$catalogCheck.Text.Contains('PASS|requirements=40|fragments=8')) 'process-requirements-canonical-fragments-match-generated-catalog'
$script:govFailureStage='CONTRACT_BODY'
$blockProjectionValid=-not$catalogText.Contains('"fullText"')
foreach($fragmentPath in Get-ChildItem -LiteralPath (Join-Path $versionRoot 'requirements\fragments') -File -Filter '*.json'){if((Get-Content -Raw -Encoding utf8 -LiteralPath $fragmentPath.FullName).Contains('"fullText"')){$blockProjectionValid=$false}}
foreach($requirement in @($catalog.requirements)){$ownerPath=Join-Path $versionRoot ([string]$requirement.ownerModule);try{$body=Get-RequirementBlock $ownerPath ([string]$requirement.requirementId)}catch{$blockProjectionValid=$false;continue};if([string]$requirement.exactBlockLocator-cne('AIW-REQUIREMENT:'+[string]$requirement.requirementId)-or[string]::IsNullOrWhiteSpace($body)){$blockProjectionValid=$false}}
Assert-True ($blockProjectionValid-and@($catalog.requirements).Count-eq40) 'process-requirements-metadata-only-catalog-exact-markdown-blocks-nonempty'

# The nested runner supports a temp parent of at most 100 characters. Keep
# this owned directory below that limit before any copying or nested calls.
$script:govFailureStage='TEMP_ALLOCATION'
$tempParent=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath ([IO.Path]::GetTempPath())))
$temp=Assert-AiwTestPath (Join-Path $tempParent ('g-'+[guid]::NewGuid().ToString('N').Substring(0,16)))
$negativeTemp=Assert-AiwTestPath (Join-Path $temp 'n')
if([IO.Path]::GetDirectoryName($temp)-cne$tempParent-or[IO.Path]::GetFileName($temp)-cnotmatch'^g-[a-f0-9]{16}$'-or(Test-Path -LiteralPath $temp)-or[IO.Path]::GetDirectoryName($negativeTemp)-cne$temp-or($negativeTemp+[IO.Path]::DirectorySeparatorChar).Length-gt100){throw 'GOVERNANCE_OWNED_TEMP_ALLOCATION_BOUNDARY'}
try{
    $script:govFailureStage='OWNED_TEMP_BODY'
    $definition=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
    Copy-AiwTestAllowlist $versionRoot $temp @($definition.mechanismVersionPaths)
    $driftCatalog=Join-Path $temp 'PROCESS_REQUIREMENTS.json'
    Write-Utf8 $driftCatalog ((Get-Content -Raw -Encoding utf8 -LiteralPath $driftCatalog).Replace('Independent action authorization','Drifted title'))
    $driftCheck=Invoke-Ps (Join-Path $temp 'scripts\build-process-requirements.ps1') @('-Check')
    Assert-True ($driftCheck.Code-ne0-and$driftCheck.Text.Contains('PROCESS_REQUIREMENTS_PROJECTION_DRIFT')) 'process-requirements-generated-catalog-drift-rejected'


    # Reference drift must fail at the existing cheap generator Check boundary.
    [IO.File]::WriteAllText($driftCatalog,$catalogText,$utf8)
    $candidateBudget=Join-Path $temp 'tests/PROCESS_REQUIREMENTS_BUDGETS.json'
    $candidateFixtures=Join-Path $temp 'tests/PROCESS_REQUIREMENTS_FIXTURES.json'
    $budgetBytes=[IO.File]::ReadAllBytes($candidateBudget);$fixtureBytes=[IO.File]::ReadAllBytes($candidateFixtures)
    $staleBudget=$utf8.GetString($budgetBytes)|ConvertFrom-Json -Depth 100;$staleBudget.candidate.catalogIdentity='1|'+('A'*64)
    Write-Utf8 $candidateBudget ($staleBudget|ConvertTo-Json -Depth 100)
    $staleReference=Invoke-Ps (Join-Path $temp 'scripts/build-process-requirements.ps1') @('-Check')
    Assert-True ($staleReference.Code-ne0-and$staleReference.Text.Contains('PROCESS_REQUIREMENTS_CANDIDATE_REFERENCE_DRIFT')) 'generator-cheap-check-rejects-stale-current-catalog-reference'
    [IO.File]::WriteAllBytes($candidateBudget,$budgetBytes)
    $staleFixtures=$utf8.GetString($fixtureBytes)|ConvertFrom-Json -Depth 100;$staleFixtures.fixtures[0].discoverInputVersion=4
    Write-Utf8 $candidateFixtures ($staleFixtures|ConvertTo-Json -Depth 100)
    $staleFixture=Invoke-Ps (Join-Path $temp 'scripts/build-process-requirements.ps1') @('-Check')
    Assert-True ($staleFixture.Code-ne0-and$staleFixture.Text.Contains('PROCESS_REQUIREMENTS_FIXTURE_REFERENCE_DRIFT')) 'generator-cheap-check-rejects-wrong-current-fixture-version-or-identity'
    [IO.File]::WriteAllBytes($candidateFixtures,$fixtureBytes)
    # A real two-group fixture uses the current runner, summary and validator.
    # Its native children check cwd and actual file bytes before emitting cases.
    $mockRoot=Join-Path $temp 'mock-source';$mockTests=Join-Path $mockRoot 'framework/versions/2.0.0/tests'
    $null=[IO.Directory]::CreateDirectory($mockTests)
    foreach($name in @('run-framework-tests.ps1','run-framework-tests-summary.ps1','TestHarness.psm1','TestNativeOutput.psm1','TestExecutionRuntime.psm1','TestGroupEvidence.psm1')){[IO.File]::Copy((Join-Path $PSScriptRoot $name),(Join-Path $mockTests $name),$false)}
    $mockScripts=Join-Path $mockTests '../scripts';$null=[IO.Directory]::CreateDirectory($mockScripts)
    foreach($name in @('ReleaseValidation.psm1','TestEvidenceValidation.psm1','StrictJsonInput.psm1')){[IO.File]::Copy((Join-Path $PSScriptRoot ('../scripts/'+$name)),(Join-Path $mockScripts $name),$false)}
    Write-Utf8 (Join-Path $mockRoot 'proof/value.txt') 'GOOD'
    Write-Utf8 (Join-Path $mockTests 'proof-target.ps1') ((@'
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
if((Get-Location).Path-cne[Environment]::CurrentDirectory){throw 'ACTUAL_CWD_MISMATCH'}
Write-Output 'PASS|actual-cwd-reached'
if([IO.File]::ReadAllText((Join-Path (Get-Location).Path 'proof/value.txt')).Trim()-cne'GOOD'){[Console]::Error.WriteLine('ACTUAL_INPUT_FAILURE');exit 1}
Write-Output 'PASS|actual-input-value'
Write-Output 'RESULT|2/2 passed|scope=proof-target'
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
    $mockGroups=@();foreach($id in @('proof.second','release.prepackage-readers')){$mockGroups+=@{id=$id;entry='framework/versions/2.0.0/tests/proof-target.ps1';arguments=@();phase='PREPACKAGE';requiredFor=@('FULL');casePolicy='OBSERVED_NAMED_CASES';requiredCaseIds=@('actual-cwd-reached','actual-input-value');completionPattern='^RESULT\|2/2 passed\|scope=proof-target$';dependencies=@('proof/value.txt');unknownDependencies=@();alwaysFresh=$false;fixturePolicy='MECHANISM';tools=@('pwsh')}}
    $mockDefinition=Join-Path $mockTests 'test-groups.json'
    Write-AiwTestJson $mockDefinition @{schemaVersion=1;phase='PREPACKAGE';mechanismVersionPaths=@();rootAdoptionPaths=@();maintenancePaths=@();groups=$mockGroups}
    $mockDefinitionBytes=[IO.File]::ReadAllBytes($mockDefinition)
    $summary=Join-Path $mockTests 'run-framework-tests-summary.ps1';$summaryRunner=Join-Path $mockTests 'run-framework-tests.ps1'
    $rawRoot=if($env:AIW_TEST_RAW_DIRECTORY){Join-Path $env:AIW_TEST_RAW_DIRECTORY ('governance-summary-'+[guid]::NewGuid().ToString('N'))}else{Join-Path ([IO.Path]::GetTempPath()) ('aiw-governance-summary-raw-'+[guid]::NewGuid().ToString('N'))}
    $completeResult=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'complete.txt'))
    Assert-True ($completeResult.Code-eq0-and$completeResult.Text.Contains('SUMMARY|status=PASS|coverage=COMPLETE|exit=0|executedCases=4|revalidatedOriginalCases=0')) 'test-summary-real-structured-required-groups-and-raw-complete'
    $refLine=@($completeResult.Output|Where-Object{$_-cmatch'^SUMMARY_SUITE\|path=(.+)\|identity='})
    Assert-True ($refLine.Count-eq1) 'test-summary-one-bound-structured-suite'
    $suitePath=[regex]::Match($refLine[0],'^SUMMARY_SUITE\|path=(.+)\|identity=').Groups[1].Value
    $suite=Read-AiwTestJson $suitePath
    $completeRaw=[IO.File]::ReadAllText((Join-Path $rawRoot 'complete.txt'))
    # Keep the frozen definition's legacy case ids; the trailing output field
    # identifies their current contract rather than claiming hidden reader priority.
    Assert-True ($completeRaw.IndexOf('GROUP|proof.second|START')-ge0-and$completeRaw.IndexOf('GROUP|proof.second|START')-lt$completeRaw.IndexOf('GROUP|release.prepackage-readers|START')-and$suite.records[0].groupId-ceq'proof.second'-and$suite.records[1].groupId-ceq'release.prepackage-readers') 'full-run-release-prerequisite-runs-before-definition-order|current-contract=stable-equal-priority-definition-order'
    $shuffled=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'shuffled.txt'),'-Groups','release.prepackage-readers,proof.second')
    $shuffledRaw=[IO.File]::ReadAllText((Join-Path $rawRoot 'shuffled.txt'))
    $shuffledRef=@($shuffled.Output|Where-Object{$_-cmatch'^SUMMARY_SUITE\|path=(.+)\|identity='})
    Assert-True ($shuffledRef.Count-eq1) 'test-summary-explicit-selection-one-bound-structured-suite'
    $shuffledSuite=Read-AiwTestJson ([regex]::Match($shuffledRef[0],'^SUMMARY_SUITE\|path=(.+)\|identity=').Groups[1].Value)
    Assert-True ($shuffled.Code-eq0-and$shuffledRaw.IndexOf('GROUP|release.prepackage-readers|START')-ge0-and$shuffledRaw.IndexOf('GROUP|release.prepackage-readers|START')-lt$shuffledRaw.IndexOf('GROUP|proof.second|START')-and($shuffledSuite.requestedGroupIds-join',')-ceq'release.prepackage-readers,proof.second'-and($shuffledSuite.records.groupId-join',')-ceq'release.prepackage-readers,proof.second') 'full-explicit-shuffle-keeps-strict-release-prerequisite-first|current-contract=stable-equal-priority-explicit-input-order'
    $focused=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'focused.txt'),'-Groups','proof.second')
    $focusedRaw=[IO.File]::ReadAllText((Join-Path $rawRoot 'focused.txt'))
    Assert-True ($focused.Code-eq0-and$focusedRaw.Contains('GROUP|proof.second|START')-and-not$focusedRaw.Contains('GROUP|release.prepackage-readers|START')) 'focused-subset-does-not-expand-into-full-prerequisite'
    # Only the two measured cheap IDs have fixed priority. These finite native
    # children verify scheduling; their names do not claim production group PASS.
    $priorityIds=@('proof.second','evidence.current-coverage','non-git.preflight-ast','release.prepackage-readers','publication.phase-evidence','publication.publication')
    $priorityGroups=@();foreach($priorityId in $priorityIds){$g=$mockGroups[0]|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$g.id=$priorityId;$g.unknownDependencies=@(if($priorityId-ceq'publication.publication'){'finite-unknown-producer'});$priorityGroups+=@($g)}
    Write-Utf8 $mockDefinition (@{schemaVersion=1;phase='PREPACKAGE';mechanismVersionPaths=@();rootAdoptionPaths=@();maintenancePaths=@();groups=$priorityGroups}|ConvertTo-Json -Depth 100 -Compress)
    $priority=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'two-prefix-order.txt'),'-Groups',($priorityIds-join','))
    $priorityRef=@($priority.Output|Where-Object{$_-cmatch'^SUMMARY_SUITE\|path=(.+)\|identity='});if($priorityRef.Count-ne1){throw 'SCHEDULER_SUITE_REQUIRED'}
    $prioritySuite=Read-AiwTestJson ([regex]::Match($priorityRef[0],'^SUMMARY_SUITE\|path=(.+)\|identity=').Groups[1].Value)
    Assert-True ($priority.Code-eq0-and($prioritySuite.records.groupId-join',')-ceq'publication.phase-evidence,non-git.preflight-ast,proof.second,evidence.current-coverage,release.prepackage-readers,publication.publication') 'scheduler-only-two-cheap-prefix-rest-explicit-stable-order'
    $cheapFocused=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'cheap-available-focused.txt'),'-Groups','proof.second')
    $cheapFocusedRaw=[IO.File]::ReadAllText((Join-Path $rawRoot 'cheap-available-focused.txt'))
    Assert-True ($cheapFocused.Code-eq0-and$cheapFocusedRaw.Contains('GROUP|proof.second|START')-and-not$cheapFocusedRaw.Contains('GROUP|publication.phase-evidence|START')-and-not$cheapFocusedRaw.Contains('GROUP|non-git.preflight-ast|START')) 'scheduler-focused-does-not-add-available-cheap-prefix'
    [IO.File]::WriteAllBytes($mockDefinition,$mockDefinitionBytes)
    $firstEntry=Join-Path $mockTests 'prerequisite.ps1'
    $mockGroups[1].entry='framework/versions/2.0.0/tests/prerequisite.ps1'
    # Failure fixtures explicitly put the failing reader first. They do not
    # rely on a priority absent from the current default/explicit-order contract.
    $failureGroups=@($mockGroups[1],$mockGroups[0])
    # Deliberate nested failures may leave runner directories before cleanup.
    # Keep those directories inside the tree owned by this test's finally.
    $negativeTemp=Assert-AiwTestPath (Join-Path $temp 'n')
    if([IO.Path]::GetDirectoryName($negativeTemp)-cne$temp-or($negativeTemp+[IO.Path]::DirectorySeparatorChar).Length-gt100){throw 'GOVERNANCE_NEGATIVE_TEMP_BOUNDARY'}
    $null=[IO.Directory]::CreateDirectory($negativeTemp)
    $negativeEnvironment=@{TMP=$negativeTemp;TEMP=$negativeTemp}
    foreach($mode in @('MISSING_COMPLETION','MISSING_CASE','PARTIAL','UNKNOWN','CORRUPT_RAW')){
     $observationPath=Join-Path $rawRoot ($mode+'.temp.json')
     if(Test-Path -LiteralPath $observationPath){throw 'GOVERNANCE_NEGATIVE_OBSERVATION_EXISTS'}
     # The actual child records its allocated temp root before any bad output.
     $body='$observationPath='+[char]39+$observationPath.Replace("'","''")+[char]39+"`n"
     $body+=(@(
      '$ErrorActionPreference=''Stop'''
      '$allocatedRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))'
      '$observation=[ordered]@{tmp=$env:TMP;temp=$env:TEMP;tempPath=[IO.Path]::GetTempPath();allocatedRoot=$allocatedRoot;currentRoot=(Get-Location).Path}'
      '$observationBytes=[Text.UTF8Encoding]::new($false).GetBytes(($observation|ConvertTo-Json -Depth 5)+[Environment]::NewLine)'
      '$observationStream=[IO.File]::Open($observationPath,[IO.FileMode]::CreateNew)'
      'try{$observationStream.Write($observationBytes)}finally{$observationStream.Dispose()}'
     )-join"`n")+"`n"
     $body+="Write-Output 'PASS|actual-cwd-reached'`n"
     if($mode-cne'MISSING_CASE'){$body+="Write-Output 'PASS|actual-input-value'`n"}
     if($mode-cne'MISSING_COMPLETION'){$body+="Write-Output 'RESULT|2/2 passed|scope=proof-target'`n"}
     if($mode-ceq'PARTIAL'){$body+="Write-Output 'SKIP|process-budget-six-fixtures-replay-selected-pack|reason=SkipPerformanceSmoke'`n"}
     if($mode-ceq'UNKNOWN'){$body+="Write-Output 'SKIP|unexplained-work|reason=UNKNOWN'`n"}
     if($mode-ceq'CORRUPT_RAW'){$body+='[Console]::OpenStandardOutput().Write([byte[]]@(255),0,1)'+"`n"}
     Write-Utf8 $firstEntry $body
     Write-Utf8 $mockDefinition (@{schemaVersion=1;phase='PREPACKAGE';mechanismVersionPaths=@();rootAdoptionPaths=@();maintenancePaths=@();groups=$failureGroups}|ConvertTo-Json -Depth 100)
     $failed=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot ($mode+'.txt')),'-SkipPerformanceSmoke') -Environment $negativeEnvironment
     $observed=Read-AiwTestJson $observationPath
     $allocatedRoot=Assert-AiwTestPath ([string]$observed.allocatedRoot)
     $observedTmp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$observed.tmp))
     $observedTemp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$observed.temp))
     $observedTempPath=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$observed.tempPath))
     Assert-True ($allocatedRoot.StartsWith($negativeTemp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-and[IO.Path]::GetDirectoryName($allocatedRoot)-ceq$negativeTemp-and[IO.Path]::GetFileName($allocatedRoot)-cmatch'^g-[a-f0-9]{8}$'-and$observedTmp-ceq$allocatedRoot-and$observedTemp-ceq$allocatedRoot-and$observedTempPath-ceq$allocatedRoot-and[string]$observed.currentRoot-ceq$mockRoot) ('full-release-'+$mode.ToLowerInvariant()+'-actual-temp-owned')
     $failedRaw=[IO.File]::ReadAllText((Join-Path $rawRoot ($mode+'.txt')))
     Assert-True ($failed.Code-ne0-and$failedRaw.Contains('GROUP|release.prepackage-readers|START')-and-not$failedRaw.Contains('GROUP|proof.second|START')-and-not$failedRaw.Contains('PREPACKAGE_PROOF|')) ('full-release-'+$mode.ToLowerInvariant()+'-blocks-successor-and-proof')
    }
    $mockGroups[1].entry='framework/versions/2.0.0/tests/proof-target.ps1'
    [IO.File]::WriteAllBytes($mockDefinition,$mockDefinitionBytes)
    foreach($mode in @('DUPLICATE','MISSING')){
     $bad=$suite|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
     if($mode-ceq'DUPLICATE'){$bad.records+=@($bad.records[0])}else{$bad.records=@($bad.records[0])}
     $badPath=Join-Path $rawRoot ($mode+'.json');Write-AiwTestJson $badPath $bad
     $reason='';try{$null=Assert-AiwTestSuiteEvidence $badPath $mockRoot $mockDefinition}catch{$reason=$_.Exception.Message}
     Assert-True ($reason-cmatch$(if($mode-ceq'DUPLICATE'){'TEST_SUITE_DUPLICATE_UNKNOWN_GROUP'}else{'TEST_SUITE_REQUESTED_GROUP_MISSING'})) ('test-summary-validator-reaches-'+$mode.ToLowerInvariant()+'-group-guard')
    }
    Write-Utf8 (Join-Path $mockRoot 'proof/value.txt') 'BAD'
    $failedRoot=Join-Path $rawRoot 'actual-failed-groups'
    $earlyFailure=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'actual-failure.txt'),'-EvidenceDirectory',$failedRoot) -Environment $negativeEnvironment
    $failedOriginal=Read-AiwTestJson (Join-Path $failedRoot 'proof.second/executed.json')
    $failedProcess=Read-AiwTestJson $failedOriginal.processResult.path
    Assert-True ($earlyFailure.Code-eq1-and$earlyFailure.Text.Contains('SUMMARY|status=FAIL|coverage=PARTIAL|exit=1')-and$failedOriginal.executionKind-ceq'EXECUTED'-and$failedOriginal.outcome-ceq'FAIL'-and$failedProcess.exitCode-eq1-and([IO.File]::ReadAllText($failedProcess.stderr.path)).Contains('ACTUAL_INPUT_FAILURE')-and-not(Test-Path -LiteralPath (Join-Path $failedRoot 'release.prepackage-readers'))) 'test-summary-real-first-group-failure-stops-successor-and-keeps-original'
    Write-Utf8 (Join-Path $mockRoot 'proof/value.txt') 'GOOD'
    Write-Utf8 $summaryRunner "Write-Output 'PASS|fixture-without-result'`nexit 0"
    $missingResult=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'missing-result.txt')) -Environment $negativeEnvironment
    Assert-True ($missingResult.Code-eq1-and$missingResult.Text.Contains('STRUCTURED_SUITE_REQUIRED')) 'test-summary-zero-exit-without-structured-suite-is-incomplete'
    Write-Utf8 $summaryRunner "Write-Output 'PASS|fixture-complete'`nWrite-Output 'RESULT|1/1 passed'`nexit 0"
    $textOnly=Invoke-Ps $summary @('-EvidencePath',(Join-Path $rawRoot 'text-only.txt')) -Environment $negativeEnvironment
    Assert-True ($textOnly.Code-eq1-and$textOnly.Text.Contains('STRUCTURED_SUITE_REQUIRED')) 'test-summary-pass-and-result-text-cannot-mint-complete-proof'
}catch{
    $script:govPrimaryError=$_
    throw
}finally{
    try{
        if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$resolved=Assert-AiwTestPath $temp;if($tempRoot-cne$tempParent-or[IO.Path]::GetDirectoryName($resolved)-cne$tempRoot-or[IO.Path]::GetFileName($resolved)-cnotmatch'^g-[a-f0-9]{16}$'){throw 'GOVERNANCE_TEMP_CLEANUP_BOUNDARY'};Remove-Item -LiteralPath $resolved -Recurse -Force}
    }catch{
        $script:govCleanupError=$_
        if($null-eq$script:govPrimaryError){$script:govFailureStage='OWNED_TEMP_CLEANUP';throw}
    }
}

$script:govFailureStage='CONTRACT_BODY'
$recoveryPath=Join-Path $versionRoot 'RECOVERY_CORE.md'
$recoveryBlock=Get-RequirementBlock $recoveryPath 'PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES'
$taskBlock=Get-RequirementBlock (Join-Path $versionRoot 'TASK_AND_SCOPE.md') 'PR_TASK_SCOPE_AND_FORBIDDEN'
$authorizationBlock=Get-RequirementBlock (Join-Path $versionRoot 'AUTHORIZATION_MODEL.md') 'PR_ACTION_AUTHORIZATION_INDEPENDENT'
$hostBlock=Get-RequirementBlock (Join-Path $versionRoot 'HOST_CODEX.md') 'PR_CODEX_ROUTER_REACTIVATION'
$routerText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot 'skills\ai-workspace-router-v2\SKILL.md')
$starterText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'project-starter\BOOTSTRAP.md')
$maintenanceText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot 'framework\maintenance-overlay\BOOTSTRAP.md')
$toolContractText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'TOOL_CONTRACT.md')
$mainTestText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'tests\run-framework-tests.ps1')
Assert-True ($recoveryBlock.Contains('来源组合、当前动作决定及正文可用性')-and$recoveryBlock.Contains('有序依赖')-and$recoveryBlock.Contains('权限、任务路线、阶段、决定或执行目标')-and$recoveryBlock.Contains('fresh包')-and$recoveryBlock.Contains('完整字节严格核对')) 'recovery-core-owns-composition-decision-and-model-body-availability-contract'
Assert-True ($taskBlock.Contains('按RECOVERY恢复原事务')-and$hostBlock.Contains('PROJECT_BOOTSTRAP')-and$routerText.Contains('pinned RECOVERY_CORE')-and$starterText.Contains('RECOVERY_CORE')-and$maintenanceText.Contains('RECOVERY_CORE')-and$hostBlock.Contains('原FINALIZE完成后')) 'recovery-router-host-task-and-bootstraps-use-one-owner-with-thin-pointers'
Assert-True ($recoveryBlock.Contains('首次、压缩、换主体或正文不确定请求FULL')-and$recoveryBlock.Contains('真实来源拒绝、撤权、保护或未完采用不能以FULL变成PASS')-and$recoveryBlock.Contains('不要求宿主提供不存在的')-and$recoveryBlock.Contains('summary、hash、旧receipt或机械PASS不能替代实际缺失正文')) 'recovery-static-contract-does-not-claim-model-fulltext-read-from-mechanical-evidence'
Assert-True ($taskBlock.Contains('可验收有界批次')-and$taskBlock.Contains('必需诊断、依赖和局部修复不拆成新决定')-and$taskBlock.Contains('Executor自主选择方法、工具和顺序')-and$authorizationBlock.Contains('独立Review、接受、Git、设备、外部、发行和采用不由连续写测自动取得')-and$toolContractText.Contains('continuationPlan')-and$toolContractText.Contains('RESULT_ACCEPT')) 'task-contract-batches-predictable-work-without-merging-independent-gates'
Assert-True ($authorizationBlock.Contains('真实原FINALIZE后像')-and$authorizationBlock.Contains('TOOL_CONTRACT')-and$authorizationBlock.Contains('INSTRUCTION_BOUND')-and$toolContractText.Contains('AUTHORIZED_ACTION_CONTINUATION')-and$toolContractText.Contains('原 package、source action/step、next step 与 current objects')-and$toolContractText.Contains('continuationReceiptPath + expectedContinuationReceiptIdentity')-and$toolContractText.Contains('不保存无法由 checker 复验的 finalize hash')-and-not$toolContractText.Contains('sourceFinalizeDecisionIdentity')-and$maintenanceText.Contains('check-framework-maintenance-authorization.ps1')) 'authorization-continuation-has-one-postimage-bound-consumer-contract'
# The schema owns the optional coordinates. Actual missing-invalidator and
# source-step rejection remain in PackageShape and ContinuationRepair.
$authoritySchema=Get-Content -LiteralPath (Join-Path $versionRoot 'AUTHORITY_CONTEXT_SCHEMA.json') -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
$continuationFields=@('continuationReceiptPath','continuationReceiptIdentity','continuationStepIndex')
$continuationSchemaValid=$authoritySchema.oneOf-is[Array]-and$authoritySchema.oneOf.Count-gt0
foreach($variant in @($authoritySchema.oneOf)){
    $step=$variant.properties.continuationStepIndex
    if($variant.additionalProperties-isnot[bool]-or$variant.additionalProperties-or$step.type-cne'integer'-or$step.minimum-ne0){$continuationSchemaValid=$false}
    foreach($field in $continuationFields){
        $peers=$variant.dependentRequired.$field
        $expected=@($continuationFields|Where-Object{$_-cne$field}|Sort-Object)
        if($peers-isnot[Array]-or$peers.Count-ne2-or(@($peers|Sort-Object)-join'|')-cne($expected-join'|')){$continuationSchemaValid=$false}
    }
}
Assert-True $continuationSchemaValid 'authority-schema-owns-integer-nonnegative-step-and-complete-paired-continuation-fields'
# Dispatch/failure behavior is exercised above; definitions retain all four real authorization groups.
$definition=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
$authorizationIds=@('authorization.package-shape','authorization.binding-independence','authorization.continuation-repair','authorization.delivery-acceptance')
$authorizationConsumers=@{'authorization.package-shape'='PackageShape';'authorization.binding-independence'='BindingIndependence';'authorization.continuation-repair'='ContinuationRepair';'authorization.delivery-acceptance'='DeliveryAcceptance'}
$authorizationGroups=@($definition.groups|Where-Object{$_.id-cin$authorizationIds})
$retainsAuthorizationConsumers=$authorizationGroups.Count-eq4
foreach($group in $authorizationGroups){
    if($group.entry-cne'framework/versions/2.0.0/tests/authorization-receipt-regression-tests.ps1'-or$group.phase-cne'PREPACKAGE'-or($group.arguments-join'|')-cne('-Group|'+$authorizationConsumers[$group.id])){$retainsAuthorizationConsumers=$false}
}
Assert-True $retainsAuthorizationConsumers 'group-definition-retains-four-real-authorization-consumers'

$catalogIdentity=Get-Identity $catalogPath
Assert-True ([string]$budget.baseline.version-ceq'1.15.1'-and[string]$budget.baseline.catalogIdentity-ceq'48098|547BBC615BCFC0A281723A1B84AEFD36FECD5CA421C7155C1897D8F4F0CC74C5'-and[string]$budget.candidate.catalogIdentity-ceq$catalogIdentity) 'process-budget-retains-baseline-and-binds-current-catalog'
Write-Output 'EVIDENCE_CEILING|HISTORICAL_RUNTIME_OBSERVATIONS|CURRENT_COST_MEASUREMENT_NOT_CLAIMED'
Assert-True (-not(Test-Path -LiteralPath (Join-Path $versionRoot 'CORRECTION_COVERAGE.json'))-and'CORRECTION_COVERAGE.json'-cnotin@($inventory.schemaAndMechanicalInputs)-and@($inventory.schemaAndMechanicalInputs)-contains'tests/canonical-identity-tests.ps1'-and@($inventory.schemaAndMechanicalInputs)-contains'tests/governance-contract-tests.ps1') 'governance-catalog-budget-inventory-without-central-project-mapping'
if($SkipPerformanceSmoke){Write-Output 'SKIP|process-budget-six-fixtures-replay-selected-pack|reason=SkipPerformanceSmoke'}else{
    $measurement=Invoke-Ps (Join-Path $PSScriptRoot 'measure-process-requirements.ps1') @('-Warmups','1','-MeasuredRuns','1','-AsJson')
    $measurementValue=if($measurement.Code-eq0){$measurement.Text|ConvertFrom-Json}else{$null}
    $measurementMatches=$measurement.Code-eq0-and@($measurementValue.fixtures).Count-eq6
    $currentFixtureContract=Get-Content -LiteralPath (Join-Path $versionRoot 'tests/PROCESS_REQUIREMENTS_FIXTURES.json') -Raw|ConvertFrom-Json -Depth 100
    if($measurementMatches){foreach($fixture in @($measurementValue.fixtures)){$currentFixture=@($currentFixtureContract.fixtures|Where-Object{[string]$_.fixtureId-ceq[string]$fixture.fixtureId});if($currentFixture.Count-ne1-or[string]$currentFixture[0].fixtureIdentity-cne[string]$fixture.fixtureIdentity-or[int]$fixture.selectedPackBytes-lt1-or[int]$fixture.selectedPackEstimatedTokens-ne[int][math]::Ceiling([int]$fixture.selectedPackBytes/4.0)-or[int]$fixture.selectedRequirementCount-lt1){$measurementMatches=$false}}}
    Assert-True $measurementMatches 'process-six-current-fixtures-measured-without-using-historical-TC2-counts'
}

$releasePath=Join-Path $repositoryRoot 'framework\FRAMEWORK_RELEASE.md'
$releaseText=Get-Content -Raw -Encoding utf8 -LiteralPath $releasePath
$reviewText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'REVIEW_AND_EVIDENCE.md')
Assert-True ((Test-Path -LiteralPath $releasePath -PathType Leaf)-and-not(Test-Path -LiteralPath (Join-Path $versionRoot 'FRAMEWORK_RELEASE.md'))-and@($inventory.explanationAndHistory)-cnotcontains'FRAMEWORK_RELEASE.md'-and-not$reviewText.Contains('PR_REVIEW_CANDIDATE_FREEZE_AND_SEQUENCE')-and-not$catalogText.Contains('"requirementId": "PR_REVIEW_CANDIDATE_FREEZE_AND_SEQUENCE"')-and(Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot 'README.md')).Contains('](framework/FRAMEWORK_RELEASE.md)')-and-not(Test-Path -LiteralPath (Join-Path $repositoryRoot 'AGENTS.md'))-and-not(Test-Path -LiteralPath (Join-Path $repositoryRoot 'CLAUDE.md'))) 'release-governance-root-owned-and-absent-from-version-payload'
Assert-True ($releaseText.Contains('final candidate freeze 运行一次 complete current-version suite')-and$releaseText.Contains('baseline executable regression 只适用于仍声明支持且确被')-and$releaseText.Contains('已退出版本只保留历史 identity 与 recovery evidence，不恢复退役套件')-and$releaseText.Contains('一个 independent CRITICAL Source Review')-and$releaseText.Contains('Maintenance `OWNER_ACCEPT` 独立接受 exact approved candidate')-and$releaseText.Contains('没有未 Review 的 free-form/executable change 时，不需要第二次 semantic post-seal Review')-and$releaseText.Contains('deterministic publication preflight')-and$releaseText.Contains('publication 顺序为 `github/main` 后 `origin/main`')-and$releaseText.Contains('失败即停止')-and$releaseText.Contains('tests/canonical-identity-tests.ps1')-and$releaseText.Contains('tests/governance-contract-tests.ps1')-and$reviewText.Contains('当前修复包准入后修复，由原仍独立Reviewer按受影响范围复审')-and$reviewText.Contains('实际修正、直接消费者和必要相邻回归须复证')-and$reviewText.Contains('未变完整Review与有效证据保留')) 'release-sequence-proportional-review-owner-accept-seal-git-review-and-two-remote-stopline'

Write-Output 'EVIDENCE_CEILING|MECHANICAL_CONTRACT_ONLY|MODEL_FULLTEXT_READ_AND_HOST_ENFORCEMENT_NOT_PROVEN'
Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=governance-contract')

}catch{
 $record=if($null-ne$script:govPrimaryError){$script:govPrimaryError}else{$_}
 $cleanup=if($null-ne$script:govCleanupError){[ordered]@{message=$script:govCleanupError.Exception.Message;scriptStackTrace=$script:govCleanupError.ScriptStackTrace;fullyQualifiedErrorId=$script:govCleanupError.FullyQualifiedErrorId;position=$script:govCleanupError.InvocationInfo.PositionMessage}}else{$null}
 $failure=[ordered]@{kind='GOVERNANCE_CONTRACT_FAILURE';stage=$script:govFailureStage;message=$record.Exception.Message;exceptionType=$record.Exception.GetType().FullName;scriptStackTrace=$record.ScriptStackTrace;fullyQualifiedErrorId=$record.FullyQualifiedErrorId;position=$record.InvocationInfo.PositionMessage;firstFailureChild=$script:govFailureChild;lastNative=$script:govLastNative;cleanupError=$cleanup}
 [Console]::Error.WriteLine((ConvertTo-Json -InputObject $failure -Depth 20 -Compress -EscapeHandling EscapeNonAscii))
 exit 1
}
