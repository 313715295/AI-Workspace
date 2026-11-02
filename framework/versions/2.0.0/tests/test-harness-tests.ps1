[CmdletBinding()]
param([switch]$NativeOutputOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('hv-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$null=[IO.Directory]::CreateDirectory($temp);$passed=0
$rawRoot=if($env:AIW_TEST_RAW_DIRECTORY){Join-Path $env:AIW_TEST_RAW_DIRECTORY ('hn-'+[guid]::NewGuid().ToString('N').Substring(0,8))}else{Join-Path ([IO.Path]::GetTempPath()) ('aiw-harness-raw-'+[guid]::NewGuid().ToString('N'))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Reject([scriptblock]$Body,[string]$Pattern,[string]$Name){$caught='';try{$null=& $Body}catch{$caught=$_.Exception.Message};Check ($caught-match$Pattern) $Name}
function Put([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
$handles=[Collections.Generic.List[object]]::new()
try{
 $helper=Join-Path $PSScriptRoot 'TestNativeOutput.psm1'
 $bootstrap='Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($helper))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput'
 $sample=([string][char]0x4E2D)+[char]0x6587+[char]0x00E9+'e'+[char]0x0301+[char]::ConvertFromUtf32(0x1F642)+'\u4e2d'
 $nested=Join-Path $temp 'native-nested.ps1'
 Put $nested ($bootstrap+"`n"+@'
$sample=([string][char]0x4E2D)+[char]0x6587+[char]0x00E9+'e'+[char]0x0301+[char]::ConvertFromUtf32(0x1F642)+'\u4e2d'
Write-Output ('nested-write|'+$sample)
[Console]::Out.WriteLine('nested-console|'+$sample)
[Console]::Error.WriteLine('nested-error|'+$sample)
'@)
 $producer=Join-Path $temp 'native-output.ps1'
 Put $producer ((@'
param([string]$Mode,[string]$Nested,[string]$Harness,[string]$Raw)
$beforeOut=[Console]::OutputEncoding.CodePage;$beforeIn=[Console]::InputEncoding.CodePage;$beforeCulture=[Globalization.CultureInfo]::CurrentCulture.Name
$newlineOut=[Console]::Out.NewLine;$newlineErr=[Console]::Error.NewLine;$ErrorActionPreference='Stop';$LASTEXITCODE=73
__BOOTSTRAP__
$installedOut=[Console]::Out;$installedErr=[Console]::Error
$initOutput=@(Initialize-AiwTestNativeOutput;Initialize-AiwTestNativeOutput)
if($initOutput.Count-ne0-or$LASTEXITCODE-ne73-or$ErrorActionPreference-cne'Stop'-or-not[object]::ReferenceEquals([Console]::Out,$installedOut)-or-not[object]::ReferenceEquals([Console]::Error,$installedErr)){throw 'NATIVE_INITIALIZER_POLLUTION'}
if([Console]::OutputEncoding.CodePage-ne$beforeOut-or[Console]::InputEncoding.CodePage-ne$beforeIn-or[Globalization.CultureInfo]::CurrentCulture.Name-cne$beforeCulture-or[Console]::Out.NewLine-cne$newlineOut-or[Console]::Error.NewLine-cne$newlineErr){throw 'NATIVE_OUTPUT_AMBIENT_CHANGE'}
$sample=([string][char]0x4E2D)+[char]0x6587+[char]0x00E9+'e'+[char]0x0301+[char]::ConvertFromUtf32(0x1F642)+'\u4e2d'
if($Mode-ceq'Invalid'){$stream=[Console]::OpenStandardOutput();$stream.WriteByte(255);$stream.Flush();exit 0}
if($Mode-ceq'Custom'){
 $custom=[IO.StringWriter]::new();[Console]::SetOut($custom)
 try{Initialize-AiwTestNativeOutput;throw 'CUSTOM_WRITER_WAS_OVERWRITTEN'}catch{if($_.Exception.Message-cne'TEST_NATIVE_OUTPUT_WRITER_CHANGED'){throw}}finally{[Console]::SetOut($installedOut);$custom.Dispose()}
 Write-Output 'custom-writer-preserved';exit 0
}
try{
 if($Mode-ceq'Throw'){throw ('native-primary|'+$sample)}
 if($Mode-ceq'Exit'){Write-Output ('exit-before|'+$sample);exit 7}
 $values=@(& {Write-Output $sample;[pscustomobject]@{value=$sample};return 'return-sentinel';throw 'RETURN_FELL_THROUGH'})
 if($values.Count-ne3-or$values[0]-isnot[string]-or$values[1].GetType().Name-cne'PSCustomObject'-or$values[1].value-cne$sample-or$values[2]-cne'return-sentinel'){throw 'NATIVE_OBJECT_RETURN_POLLUTION'}
 Write-Output ('write|'+$sample)
 [Console]::Out.WriteLine('console|'+$sample)
 [Console]::Error.WriteLine('error|'+$sample)
 Write-Output 'objects-and-return-preserved'
 if($Mode-ceq'Nested'){
  Import-Module $Harness
  $child=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$Nested) -WorkingDirectory (Get-Location).Path -EvidenceDirectory $Raw -GroupId 'native-output-nested'
  if($child.Code-ne0){throw 'NESTED_NATIVE_FAILED'}
  [Console]::Out.Write($child.StdoutText);[Console]::Error.Write($child.StderrText)
 }
}finally{[Console]::Error.WriteLine('cleanup|'+$sample)}
'@).Replace('__BOOTSTRAP__',$bootstrap))
 foreach($mode in @('Direct','Nested')){
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$producer,'-Mode',$mode,'-Nested',$nested,'-Harness',(Join-Path $PSScriptRoot 'TestHarness.psm1'),'-Raw',$rawRoot) -WorkingDirectory $temp -EvidenceDirectory $rawRoot -GroupId ('native-output-'+$mode)
  $expectedOut=@(('write|'+$sample),('console|'+$sample),'objects-and-return-preserved')
  $expectedErr=@(('error|'+$sample))
  if($mode-ceq'Nested'){$expectedOut+=@(('nested-write|'+$sample),('nested-console|'+$sample));$expectedErr+=@(('nested-error|'+$sample))}
  $expectedErr+=@('cleanup|'+$sample)
  Check ($run.Code-eq0-and($run.StdoutText.TrimEnd()-split'\r?\n'-join"`n")-ceq($expectedOut-join"`n")-and($run.StderrText.TrimEnd()-split'\r?\n'-join"`n")-ceq($expectedErr-join"`n")) ('native-utf8-dual-stream-order-and-object-return-'+$mode)
  Check ($run.Record.stdout.identity-ceq(Get-AiwTestFileIdentity $run.Record.stdout.path)-and$run.Record.stderr.identity-ceq(Get-AiwTestFileIdentity $run.Record.stderr.path)-and[IO.File]::ReadAllBytes($run.Record.stdout.path)[0]-ne239) ('native-utf8-original-raw-no-bom-'+$mode)
 }
 foreach($mode in @('Throw','Exit','Custom')){
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$producer,'-Mode',$mode) -WorkingDirectory $temp -EvidenceDirectory $rawRoot -GroupId ('native-output-'+$mode)
  if($mode-ceq'Throw'){Check ($run.Code-ne0-and$run.StderrText.Contains('native-primary|'+$sample)-and$run.StderrText.Contains('cleanup|'+$sample)) 'native-utf8-real-host-error-and-finally'}
  elseif($mode-ceq'Exit'){Check ($run.Code-eq7-and$run.StdoutText.Contains('exit-before|'+$sample)-and$run.StderrText.Contains('cleanup|'+$sample)) 'native-utf8-real-exit-and-finally'}
  else{Check ($run.Code-eq0-and$run.StdoutText.TrimEnd()-ceq'custom-writer-preserved') 'native-utf8-reentry-rejects-unknown-custom-writer'}
 }
 $invalidRoot=Join-Path $rawRoot 'invalid-utf8';$decodeError=''
 try{$null=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$producer,'-Mode','Invalid') -WorkingDirectory $temp -EvidenceDirectory $invalidRoot -GroupId 'native-output-invalid'}catch{$decodeError=$_.Exception.ToString()}
 $invalidRecords=@(Get-ChildItem -LiteralPath $invalidRoot -Filter result.json -Recurse -File)
 $invalid=if($invalidRecords.Count-eq1){Get-Content -LiteralPath $invalidRecords[0].FullName -Raw|ConvertFrom-Json}else{$null}
 Check ($decodeError-match'UTF-8|Unicode|Unable to translate|无法转换'-and$null-ne$invalid-and$invalid.exitCode-eq0-and[IO.File]::ReadAllBytes($invalid.stdout.path)[0]-eq255) 'native-utf8-invalid-raw-still-rejected-with-original-native-result'
 Write-Output 'EVIDENCE_CEILING|SHARED_CONSOLE_NOT_OBSERVED|redirected-owned-processes-only;no-encoding-setter'

 if($NativeOutputOnly){Write-Output ('PARTIAL|NATIVE_OUTPUT_ONLY|checks='+$passed);return}
 $scriptPath=Join-Path $temp 'stream.ps1'
 Put $scriptPath ((@'
__AIW_TEST_NATIVE_OUTPUT__
Write-Output 'stdout-start'
[Console]::Error.WriteLine('stderr-start')
Start-Sleep -Milliseconds 1300
for($i=0;$i-lt80;$i++){[Console]::Out.WriteLine(('o'*4096));[Console]::Error.WriteLine(('e'*4096))}
Write-Output 'stdout-end'
[Console]::Error.WriteLine('stderr-end')
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $handle=Start-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$scriptPath) -WorkingDirectory $temp -EvidenceDirectory $rawRoot -GroupId 'harness-stream';$handles.Add($handle)
 $visible=$false;$deadline=[DateTime]::UtcNow.AddSeconds(5)
 do{
  $state=Wait-AiwTestProcess $handle -WaitMilliseconds 100 -SoftDiagnosticMilliseconds 0
  if([IO.File]::Exists($handle.Stdout)-and[IO.File]::Exists($handle.Stderr)){$visible=(Get-Item -LiteralPath $handle.Stdout).Length-gt0-and(Get-Item -LiteralPath $handle.Stderr).Length-gt0-and$state.Status-ceq'RUNNING'}
 }while(-not$visible-and$state.Status-ceq'RUNNING'-and[DateTime]::UtcNow-lt$deadline)
 Check $visible 'both-raw-streams-grow-before-process-exit'
 if($state.Status-ceq'RUNNING'){do{$state=Wait-AiwTestProcess $handle}while($state.Status-ceq'RUNNING')}
 Check ($state.Code-eq0-and$state.StdoutText.StartsWith('stdout-start')-and$state.StdoutText.Contains('stdout-end')-and$state.StderrText.StartsWith('stderr-start')-and$state.StderrText.Contains('stderr-end')) 'large-both-streams-drain-without-deadlock-and-preserve-stream-order'
 Check ([IO.File]::Exists($state.ResultPath)-and$state.Record.streamOrdering-ceq'INTRA_STREAM_ONLY'-and$state.Record.stdout.identity-ceq(Get-AiwTestFileIdentity $handle.Stdout)) 'actual-exit-raw-identity-and-result-are-retained'
 Reject {Wait-AiwTestProcess $handle} 'ALREADY_CONSUMED' 'completed-result-cannot-be-consumed-as-a-new-run'
 $scriptPath=Join-Path $temp 'typed.ps1';$payloadPath=Join-Path $temp 'typed.json'
 Put $payloadPath '{"value":"space and quote \"","array":["first","second value"]}'
 Put $scriptPath ((@'
param([string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
$v=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json
function Target([string]$Value,[string[]]$Array){[ordered]@{value=$Value;array=@($Array);cwd=(Get-Location).Path;processCwd=[Environment]::CurrentDirectory;env=$env:AIW_HARNESS_SAMPLE}|ConvertTo-Json -Compress}
Target -Value $v.value -Array @($v.array)
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $before=$env:AIW_HARNESS_SAMPLE
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$scriptPath,'-InputPath',$payloadPath) -WorkingDirectory $temp -Environment @{AIW_HARNESS_SAMPLE='isolated value'} -EvidenceDirectory $rawRoot
 $value=$run.StdoutText|ConvertFrom-Json
 Check ($run.Code-eq0-and$value.value-ceq'space and quote "'-and$value.array.Count-eq2-and$value.array[1]-ceq'second value'-and$value.cwd-ceq$temp-and$value.processCwd-ceq$temp-and$value.env-ceq'isolated value'-and$env:AIW_HARNESS_SAMPLE-ceq$before) 'typed-scalar-array-argv-cwd-and-child-only-environment'
 $facade=Get-Module TestHarness
 $runtime=@(Get-Module -All TestExecutionRuntime)
 $publicStart=Get-Command Start-AiwTestProcess
 Check ($runtime.Count-eq1-and$publicStart.Module.Path-ceq$facade.Path-and$publicStart.ScriptBlock.Module.Path-ceq$runtime[0].Path-and$facade.ExportedCommands.ContainsKey('Start-AiwTestProcess')) 'one-native-owner-reexported-by-harness-facade'
 $cross=& $facade.ExportedCommands['Start-AiwTestProcess'] ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-Command',"Write-Output 'cross-owner'") -WorkingDirectory $temp -EvidenceDirectory $rawRoot
 $handles.Add($cross)
 do{$crossResult=& $runtime[0].ExportedCommands['Wait-AiwTestProcess'] $cross}while($crossResult.Status-ceq'RUNNING')
 Check ($crossResult.Code-eq0-and$crossResult.StdoutText.Contains('cross-owner')-and$cross.Completed) 'facade-start-native-wait-consume-the-same-owned-handle'

 $run2=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$scriptPath,'-InputPath',$payloadPath) -WorkingDirectory $temp -Environment @{AIW_HARNESS_SAMPLE='observed native v2'} -EvidenceDirectory $rawRoot -EvidenceContractVersion 2
 $launch2=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $run2.ResultPath) 'launch.json') -Raw|ConvertFrom-Json
 $value2=$run2.StdoutText|ConvertFrom-Json
 Check ($run2.Code-eq0-and$run2.Record.schemaVersion-eq2-and$launch2.schemaVersion-eq2-and$run2.Record.environment.AIW_HARNESS_SAMPLE-ceq$value2.env-and$launch2.environment.AIW_HARNESS_SAMPLE-ceq$value2.env-and$env:AIW_HARNESS_SAMPLE-ceq$before) 'native2-retains-actual-child-environment-and-original-legacy-shape'
 $forged=$run2.Record|ConvertTo-Json -Depth 100|ConvertFrom-Json
 Reject {Wait-AiwTestProcess $forged -WaitMilliseconds 0} 'OWNERSHIP_DRIFT' 'native-owner-rejects-unowned-fabricated-handle'
 $silent=Join-Path $temp 'silent.ps1';Put $silent 'Start-Sleep -Milliseconds 900; exit 0'
 $handle=Start-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$silent) -WorkingDirectory $temp -EvidenceDirectory $rawRoot;$handles.Add($handle)
 $state=Wait-AiwTestProcess $handle -WaitMilliseconds 20 -SoftDiagnosticMilliseconds 0
 Check ($state.Status-ceq'RUNNING'-and$null-eq$handle.Cancellation) 'silent-process-and-soft-diagnostic-do-not-trigger-cancellation'
 do{$state=Wait-AiwTestProcess $handle}while($state.Status-ceq'RUNNING')
 $events=@(Get-Content -LiteralPath $handle.Phases|ForEach-Object{$_|ConvertFrom-Json})
 Check ($state.Code-eq0-and@($events|Where-Object event -CEQ DIAGNOSTIC).Count-eq1) 'native-wait-continuation-consumes-result-with-one-useful-diagnostic'
 $cpu=Join-Path $temp 'cpu.ps1';Put $cpu '$watch=[Diagnostics.Stopwatch]::StartNew(); while($watch.ElapsedMilliseconds-lt400){$null=[Math]::Sqrt(99999)}; exit 7'
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$cpu) -WorkingDirectory $temp -EvidenceDirectory $rawRoot
 Check ($run.Code-eq7-and$run.Status-ceq'FAIL'-and$run.Record.timing.cpuMilliseconds-gt0) 'cpu-and-nonzero-exit-have-distinct-actual-results'
 $cancel=Join-Path $temp 'cancel.ps1';Put $cancel "Write-Output 'owned-cancel-sample-ready'; Start-Sleep -Seconds 20"
 $handle=Start-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$cancel) -WorkingDirectory $temp -EvidenceDirectory $rawRoot;$handles.Add($handle)
 Reject {Stop-AiwTestProcess $handle -AuthorizedRunId 'not-this-run' -Reason 'sample'} 'BINDING' 'cancellation-rejects-another-run-identity'
 # B1 explicitly authorizes this isolated cancellation sample only.
 Stop-AiwTestProcess $handle -AuthorizedRunId $handle.RunId -Reason 'B1 independently authorized isolated owned-process cancellation sample'
 do{$state=Wait-AiwTestProcess $handle}while($state.Status-ceq'RUNNING')
 Check ($state.Status-ceq'STOPPED'-and$null-ne$state.Record.cancellation-and$state.Code-ne0) 'authorized-owned-cancellation-retains-partial-raw-real-exit-and-reason'
 $inputRoot=Join-Path $temp 'allow-input';Put (Join-Path $inputRoot 'a.txt') 'a';Put (Join-Path $inputRoot 'unlisted.txt') 'unlisted'
 $outputRoot=Join-Path $temp 'allow-output'
 Copy-AiwTestAllowlist $inputRoot $outputRoot @('a.txt')
 Check ([IO.File]::Exists((Join-Path $outputRoot 'a.txt'))-and-not(Test-Path -LiteralPath (Join-Path $outputRoot 'unlisted.txt'))) 'explicit-allowlist-is-applied-before-copy'
 Reject {Copy-AiwTestAllowlist $inputRoot (Join-Path $temp 'bad-copy') @('a.txt','../unlisted.txt')} 'ALLOWLIST' 'all-locators-validated-before-any-source-copy'
 Check (-not(Test-Path -LiteralPath (Join-Path $temp 'bad-copy/a.txt'))) 'invalid-allowlist-has-zero-copy'
  $snapshot=Get-AiwTestFixtureSnapshot $outputRoot
  $identitySnapshot=Get-AiwTestFixtureSnapshot $outputRoot -IdentityOnly
  Check ($identitySnapshot.Files[0].identity-ceq$snapshot.Files[0].identity-and-not$identitySnapshot.Files[0].ContainsKey('base64')-and$snapshot.Files[0].ContainsKey('base64')) 'identity-only-snapshot-preserves-byte-identity-without-restore-payload'
  # Reject malformed restoration plans before deleting or restoring any live byte.
  Put (Join-Path $outputRoot 'sentinel.txt') 'must survive rejection'
  $sentinel=Get-AiwTestFileIdentity (Join-Path $outputRoot 'sentinel.txt')
  foreach($fault in @('escape','duplicate','corrupt')){
   $bad=$snapshot|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
   switch($fault){escape{$bad.Files[0].path='../outside.txt'} duplicate{$bad.Files+=@($bad.Files[0])} corrupt{$bad.Files[0].base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('different'))}}
   Reject {Reset-AiwTestFixture $bad $outputRoot} 'TEST_RESET_(LOCATOR|DUPLICATE|SNAPSHOT_CORRUPT)' ('invalid-reset-plan-rejects-before-mutation-'+$fault)
   Check ((Get-AiwTestFileIdentity (Join-Path $outputRoot 'sentinel.txt'))-ceq$sentinel) ('invalid-reset-preserves-unlisted-live-byte-'+$fault)
  }
  Remove-Item -LiteralPath (Join-Path $outputRoot 'sentinel.txt')
  $null=[IO.Directory]::CreateDirectory((Join-Path $outputRoot 'expected-empty'))
  $directorySnapshot=Get-AiwTestFixtureSnapshot $outputRoot
  Remove-Item -LiteralPath (Join-Path $outputRoot 'expected-empty')
  $null=[IO.Directory]::CreateDirectory((Join-Path $outputRoot 'wrong-empty'))
  $null=Reset-AiwTestFixture $directorySnapshot $outputRoot
  Check ([IO.Directory]::Exists((Join-Path $outputRoot 'expected-empty'))-and-not[IO.Directory]::Exists((Join-Path $outputRoot 'wrong-empty'))) 'reset-restores-exact-empty-directory-set-when-count-is-unchanged'
  $null=Reset-AiwTestFixture $snapshot $outputRoot
 Put (Join-Path $outputRoot 'a.txt') 'changed';Put (Join-Path $outputRoot 'extra/nested.txt') 'extra'
 Reject {Reset-AiwTestFixture $snapshot (Join-Path $temp 'other')} 'ROOT_DRIFT' 'reset-rejects-another-canonical-root'
 Put (Join-Path $outputRoot 'active-marker') 'active'
 Reject {Reset-AiwTestFixture $snapshot $outputRoot -ActiveMarkerPaths @('active-marker')} 'ACTIVE_MARKER' 'reset-refuses-an-active-original-action-marker'
 Remove-Item -LiteralPath (Join-Path $outputRoot 'active-marker')
 $reset=Reset-AiwTestFixture $snapshot $outputRoot
 Check ($reset.status-ceq'CLEAN'-and(Get-AiwTestFileIdentity (Join-Path $outputRoot 'a.txt'))-ceq$snapshot.Files[0].identity-and-not(Test-Path -LiteralPath (Join-Path $outputRoot 'extra'))) 'complete-same-root-reset-restores-bytes-and-removes-extra-tree'
 $handle=Start-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$cancel) -WorkingDirectory $outputRoot -EvidenceDirectory $rawRoot;$handles.Add($handle)
 $unfinished=@(Get-AiwTestRawProcessStates $rawRoot|Where-Object state -CNE 'COMPLETE')
 Check (@($unfinished|Where-Object runId -CEQ $handle.RunId).Count-eq1) 'raw-cleanup-observation-detects-actual-unconsumed-worker'
 Reject {Reset-AiwTestFixture $snapshot $outputRoot} 'ACTIVE_WORKER' 'reset-refuses-actual-owned-worker-before-mutation'
 Stop-AiwTestProcess $handle $handle.RunId 'Explicit B1 active-reset sample completed'
 do{$state=Wait-AiwTestProcess $handle}while($state.Status-ceq'RUNNING')
 Check (@(Get-AiwTestRawProcessStates $rawRoot|Where-Object state -CNE 'COMPLETE').Count-eq0) 'raw-cleanup-complete-only-after-actual-worker-exit-and-result'
 $null=Reset-AiwTestFixture $snapshot $outputRoot
 $sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'));$versionRoot=Split-Path -Parent $PSScriptRoot
 $definition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
 $small=Join-Path $temp 'allowlist-runtime';$full=Join-Path $temp 'full-runtime'
 $null=New-AiwTestRuntimeFixture $sourceRoot $small $definition.mechanismVersionPaths
 [string[]]$allPaths=@(Get-ChildItem -LiteralPath $versionRoot -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($versionRoot,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'})
 $null=New-AiwTestRuntimeFixture $sourceRoot $full $allPaths
 $probe=Join-Path $temp 'actual-format-probe.ps1';Put $probe ((@'
param([string]$Module,[string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
try{
 $owner=@(Import-Module $Module -PassThru)[0]
 $value=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -Depth 100
 & $owner.ExportedCommands['Assert-AiwCurrentObjectValue'] 'CONTROLLER' $value
 Write-Output '{"status":"PASS"}'
}catch{[ordered]@{status='FAIL';reason=$_.Exception.Message}|ConvertTo-Json -Compress;exit 2}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $inputPath=Join-Path $temp 'controller.json'
 foreach($valid in @($true,$false)){
  Put $inputPath $(if($valid){'{"schemaVersion":1,"projectId":"fixture","controllerId":"actor","controllerEpoch":1,"state":"CURRENT"}'}else{'{"schemaVersion":1,"projectId":"fixture","controllerId":"actor","controllerEpoch":0,"state":"CURRENT"}'})
  $observed=@()
  foreach($runtime in @($full,$small)){
   $module=Join-Path $runtime 'framework/versions/2.0.0/scripts/ObjectFormats.psm1'
   $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$probe,'-Module',$module,'-InputPath',$inputPath) -WorkingDirectory $temp -EvidenceDirectory $rawRoot
   $observed+=@{code=$run.Code;value=($run.StdoutText|ConvertFrom-Json -Depth 100)}
  }
  Check ($observed[0].code-eq$observed[1].code-and$observed[0].value.status-ceq$observed[1].value.status-and$observed[0].code-eq$(if($valid){0}else{2})) ('full-and-allowlist-cold-real-format-target-parity-'+$valid)
  if(-not$valid){Check ($observed[0].value.reason-ceq$observed[1].value.reason-and$observed[0].value.reason-clike'FORMAT_CURRENT_VALIDATION_FAILED*') 'allowlist-negative-reaches-same-real-schema-guard'}
 }
 Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=test-harness')
}finally{
 foreach($handle in $handles){if(-not$handle.Completed){Stop-AiwTestProcess $handle -AuthorizedRunId $handle.RunId -Reason 'Isolated helper sample failed; remaining owned sample has no verification value';$null=Wait-AiwTestProcess $handle}}
 $full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
 if([IO.Path]::GetDirectoryName($full)-cne$parent-or[IO.Path]::GetFileName($full)-cnotmatch'^hv-[a-f0-9]{8}$'){throw 'HARNESS_TEST_CLEANUP_SCOPE'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
