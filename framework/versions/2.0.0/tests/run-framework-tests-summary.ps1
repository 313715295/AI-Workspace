[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$EvidencePath,
 [switch]$SkipManifest,[switch]$SkipBaseline,[switch]$SkipPerformanceSmoke,
 [switch]$ToolContractOnly,[switch]$SelectorOnly,[switch]$MainIntegrationOnly,
 [ValidateSet('All','RuleSelection','SourceChangeRecovery','KnowledgeEnable')][string]$StandardPresetsGroup,
 [switch]$MaintenanceFixture,[string[]]$Groups=@(),[string[]]$ResumeEvidence=@(),
 [string]$EvidenceDirectory,[string]$SourceViewPath,[ValidateSet('PREPACKAGE','POSTBUILD')][string]$Phase='PREPACKAGE',[string]$PackagePath,[string]$ExtractedPackagePath,[string]$BuildCommandPath,[string]$AcceptedBaselinePath,[string]$ExpectedAcceptedBaselineIdentity,[ValidateSet(1,2,3,4)][int]$ProofSchemaVersion=3,[string]$ChangePlanPath,[string]$ExpectedChangePlanIdentity
)
$summaryStage='INITIALIZATION';$summaryProcess=$null
try {
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
Import-Module (Join-Path $PSScriptRoot 'TestGroupEvidence.psm1')
$full=Assert-AiwTestPath $EvidencePath
if(Test-Path -LiteralPath $full){throw 'EVIDENCE_PATH_EXISTS'}
if(Test-Path -LiteralPath ($full+'.stderr.raw')){throw 'EVIDENCE_PATH_EXISTS'}
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
$processRoot=$full+'.process-'+[guid]::NewGuid().ToString('N');$null=[IO.Directory]::CreateDirectory($processRoot)
$parameters=@{};foreach($name in $PSBoundParameters.Keys){if($name-cne'EvidencePath'){$value=$PSBoundParameters[$name];$parameters[$name]=if($value-is[Management.Automation.SwitchParameter]){[bool]$value}else{$value}}}
if(-not$EvidenceDirectory){$parameters.EvidenceDirectory=$full+'.groups-'+[guid]::NewGuid().ToString('N')}
$payload=Join-Path $processRoot 'input.json';$wrapper=Join-Path $processRoot 'invoke.ps1'
Write-AiwTestJson $payload @{runner=(Join-Path $PSScriptRoot 'run-framework-tests.ps1');parameters=$parameters}
$wrapperText=(@'
param([string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
try {
 $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
 $inputValue=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
 $parameters=$inputValue.parameters
 $LASTEXITCODE=0
 & $inputValue.runner @parameters
 exit $LASTEXITCODE
}catch{
 $failure=$_
 [Console]::Error.WriteLine(([ordered]@{kind='SUMMARY_WRAPPER_FAILURE';status='FAIL';reason=[string]$failure.Exception.Message;exceptionType=$failure.Exception.GetType().FullName;scriptStackTrace=[string]$failure.ScriptStackTrace;fullyQualifiedErrorId=[string]$failure.FullyQualifiedErrorId;position=[string]$failure.InvocationInfo.PositionMessage}|ConvertTo-Json -Depth 20 -Compress -EscapeHandling EscapeNonAscii))
 exit 1
}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput'))
[IO.File]::WriteAllText($wrapper,$wrapperText,[Text.UTF8Encoding]::new($false))
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$summaryStage='WRAPPER_EXECUTION'
$process=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$wrapper,'-InputPath',$payload) -WorkingDirectory $sourceRoot -EvidenceDirectory $processRoot -GroupId 'summary-direct-consumer'
$summaryProcess=$process;$summaryStage='EVIDENCE_COPY_AND_SUMMARY'
[IO.File]::Copy($process.Record.stdout.path,$full,$false)
[IO.File]::Copy($process.Record.stderr.path,($full+'.stderr.raw'),$false)
$status='FAIL';$coverage='PARTIAL';$suite=$null;$executed=0;$revalidated=0;$targetedCases=0;$historicalGroups=0;$targeted=@()
try{
 if($process.Code-ne0){throw ('RUNNER_EXIT|'+$process.Code)}
 $references=@($process.StdoutText-split'\r?\n'|Where-Object{$_-cmatch'^SUITE_EVIDENCE\|path=(.+)\|identity=(\d+\|[A-F0-9]{64})$'})
 if($references.Count-ne1){throw 'STRUCTURED_SUITE_REQUIRED'}
 $match=[regex]::Match($references[0],'^SUITE_EVIDENCE\|path=(.+)\|identity=(\d+\|[A-F0-9]{64})$')
 $suitePath=$match.Groups[1].Value
 if((Get-AiwTestFileIdentity $suitePath)-cne$match.Groups[2].Value){throw 'SUITE_IDENTITY_DRIFT'}
 if($ChangePlanPath){
  $proofRefs=@($process.StdoutText-split'\r?\n'|Where-Object{$_-cmatch'^PREPACKAGE_PROOF\|path=(.+)\|identity=(\d+\|[A-F0-9]{64})$'})
  if($proofRefs.Count-ne1){throw 'STRUCTURED_CHANGE_PROOF_REQUIRED'}
  $proofMatch=[regex]::Match($proofRefs[0],'^PREPACKAGE_PROOF\|path=(.+)\|identity=(\d+\|[A-F0-9]{64})$')
  $proofPath=$proofMatch.Groups[1].Value
  $proof=Read-AiwTestJson $proofPath
  if((Get-AiwTestFileIdentity $proofPath)-cne$proofMatch.Groups[2].Value-or$proof.schemaVersion-ne4-or$proof.changePlanRef.identity-cne$ExpectedChangePlanIdentity-or$proof.currentSuiteRef.identity-cne$match.Groups[2].Value){throw 'STRUCTURED_CHANGE_PROOF_DRIFT'}
  $planPath=Join-Path (Split-Path -Parent $proofPath) $proof.changePlanRef.path
  $plan=Read-AiwTestJson $planPath
  if((Get-AiwTestFileIdentity $planPath)-cne$ExpectedChangePlanIdentity){throw 'TEST_CHANGE_PLAN_DRIFT'}
  $targeted=@($plan.targetedGroupIds)
  $historicalGroups=$proof.requiredGroupIds.Count-$plan.freshGroupIds.Count
 }
 $suite=Assert-AiwTestSuiteEvidence $suitePath $sourceRoot (Join-Path $PSScriptRoot 'test-groups.json') -AllowPartial -TargetedGroupIds $targeted
 if($suite.phase-ceq'POSTBUILD'){
  $postRefs=@($process.StdoutText-split'\r?\n'|Where-Object{$_-cmatch'^POSTBUILD_PROOF\|path=(.+)\|identity=(\d+\|[A-F0-9]{64})$'})
  if($postRefs.Count-ne1){throw 'STRUCTURED_POSTBUILD_REQUIRED'}
  $postMatch=[regex]::Match($postRefs[0],'^POSTBUILD_PROOF\|path=(.+)\|identity=(\d+\|[A-F0-9]{64})$')
  if((Get-AiwTestFileIdentity $postMatch.Groups[1].Value)-cne$postMatch.Groups[2].Value){throw 'POSTBUILD_IDENTITY_DRIFT'}
  $readerPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1'));$reader=@(Import-Module $readerPath -PassThru)[0];$consume=$reader.ExportedCommands['Get-AiwReleasePostbuildQualification']
  if($null-eq$consume-or$consume.Module.Path-cne$readerPath){throw 'POSTBUILD_READER_OWNER'}
  $postQualified=& $consume -Path $postMatch.Groups[1].Value -PackagePath $suite.options.PackagePath -ExtractedPackagePath $suite.sourceRoot -BuildCommandPath $suite.options.BuildCommandPath -AllowPartial
  if($suite.coverage-ceq'COMPLETE'-and$postQualified.State-cne'PACKAGE_VALIDATED'){throw 'POSTBUILD_QUALIFICATION_REQUIRED'}
 }
 foreach($ref in $suite.records){
  $record=Read-AiwTestJson $ref.path
  switch -CaseSensitive ($ref.executionKind){
   'EXECUTED'{
    if($ref.groupId-cin$targeted){$targetedCases+=@($record.cases).Count}
    else{$executed+=@($record.cases).Count}
   }
   'REVALIDATED'{$revalidated+=@($record.cases).Count}
   default{throw 'TEST_EXECUTION_KIND_UNKNOWN'}
  }
 }
 $status=$suite.outcome;$coverage=$suite.coverage
}catch{
 # Keep the existing DETAIL framing; escape only non-ASCII UTF-16 code units.
 $detail=[regex]::Replace([string]$_.Exception.Message,'[^\x00-\x7F]',{param($m) '\u{0:x4}' -f [int][char]$m.Value})
 Write-Output ('DETAIL|'+$detail)
}
Write-Output ('SUMMARY|status='+$status+'|coverage='+$coverage+'|exit='+$process.Code+'|executedCases='+$executed+'|revalidatedOriginalCases='+$revalidated+'|phase='+$Phase+'|qualification='+$(if($suite){$suite.qualification}else{'UNKNOWN'})+'|targetedCases='+$targetedCases+'|historicalGroups='+$historicalGroups)
Write-Output ('FULL_EVIDENCE|path='+$full+'|identity='+(Get-AiwTestFileIdentity $full))
Write-Output ('PROCESS_EVIDENCE|path='+$process.ResultPath+'|identity='+(Get-AiwTestFileIdentity $process.ResultPath))
if($null-ne$suite){Write-Output ('SUMMARY_SUITE|path='+$suitePath+'|identity='+(Get-AiwTestFileIdentity $suitePath))}
if($status-cnotin@('PASS','PARTIAL')){exit 1}

}catch{
 $failure=$_
 $native=if($null-ne$summaryProcess){@{code=$summaryProcess.Code;resultPath=$summaryProcess.ResultPath;stdout=$summaryProcess.Record.stdout;stderr=$summaryProcess.Record.stderr}}else{$null}
 [Console]::Error.WriteLine(([ordered]@{kind='SUMMARY_ENTRY_FAILURE';status='FAIL';stage=$summaryStage;reason=[string]$failure.Exception.Message;exceptionType=$failure.Exception.GetType().FullName;scriptStackTrace=[string]$failure.ScriptStackTrace;fullyQualifiedErrorId=[string]$failure.FullyQualifiedErrorId;position=[string]$failure.InvocationInfo.PositionMessage;native=$native}|ConvertTo-Json -Depth 30 -Compress -EscapeHandling EscapeNonAscii))
 exit 1
}
