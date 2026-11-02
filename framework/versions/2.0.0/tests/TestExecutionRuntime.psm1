# @design-contract standards/software/VALIDATION.md
# Private native process lifetime and raw capture.
Set-StrictMode -Version Latest
$script:TestUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:OwnedTestHandles=[Collections.Generic.List[object]]::new()
$script:TestHarnessModulePath=$PSCommandPath
function Assert-AiwTestPath([string]$Path){
 $full=[IO.Path]::GetFullPath($Path)
 if($full-match'(?i)[\\/]src[\\/]config[\\/]levels[\\/]level_test2\.js$'){throw 'TEST_FORBIDDEN_PATH'}
 $walk=$full
 while($walk){if(Test-Path -LiteralPath $walk){if((Get-Item -LiteralPath $walk -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'TEST_REPARSE_PATH'}};$walk=Split-Path -Parent $walk}
 return $full
}
if(-not('AiwTestStreamPump' -as [type])){
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading.Tasks;
public static class AiwTestStreamPump {
 public static async Task Drain(Stream source, string destination) {
  using(var output=new FileStream(destination,FileMode.CreateNew,FileAccess.Write,FileShare.Read,1,true)) {
   byte[] buffer=new byte[8192]; int count;
   while((count=await source.ReadAsync(buffer,0,buffer.Length).ConfigureAwait(false))>0) {
    await output.WriteAsync(buffer,0,count).ConfigureAwait(false);
    await output.FlushAsync().ConfigureAwait(false);
   }
  }
 }
}
'@
}
function Get-AiwTestFileIdentity([string]$Path){
 $full=Assert-AiwTestPath $Path
 if(-not[IO.File]::Exists($full)){throw ('TEST_FILE_MISSING|'+$full)}
 $bytes=[IO.File]::ReadAllBytes($full)
 return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}
function Write-AiwTestJson([string]$Path,$Value){
 $full=Assert-AiwTestPath $Path;if(Test-Path -LiteralPath $full){throw 'TEST_RESULT_EXISTS'}
 $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
 $temporary=$full+'.writing-'+[guid]::NewGuid().ToString('N')
 [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 100 -Compress)+"`n",$script:TestUtf8)
 [IO.File]::Move($temporary,$full,$false)
}
function Write-AiwTestPhase([string]$Path,[string]$RunId,[string]$GroupId,[string]$Step,[ValidateSet('START','REACHED','END','DIAGNOSTIC')][string]$Event,$Data){
 $row=[ordered]@{runId=$RunId;groupId=$GroupId;step=$Step;event=$Event;utc=[DateTime]::UtcNow.ToString('o');data=$Data}
 $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
 [IO.File]::AppendAllText($Path,($row|ConvertTo-Json -Depth 30 -Compress)+"`n",$script:TestUtf8)
}
function Start-AiwTestProcess {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments,[string]$WorkingDirectory=(Get-Location).Path,[hashtable]$Environment=@{},[string]$EvidenceDirectory=$env:AIW_TEST_RAW_DIRECTORY,[string]$GroupId='private-process',[string]$Executor=$env:CODEX_THREAD_ID,[string]$DirectConsumer=$env:CODEX_THREAD_ID,[ValidateSet(1,2)][int]$EvidenceContractVersion=1)
 $runId=[guid]::NewGuid().ToString('N')
 if([string]::IsNullOrWhiteSpace($EvidenceDirectory)){$EvidenceDirectory=Join-Path ([IO.Path]::GetTempPath()) ('aiw-test-raw-'+$runId)}
 $directory=Assert-AiwTestPath (Join-Path ([IO.Path]::GetFullPath($EvidenceDirectory)) $runId)
 $null=[IO.Directory]::CreateDirectory($directory)
 $exe=Assert-AiwTestPath $Executable;$exeIdentity=Get-AiwTestFileIdentity $exe;$cwd=Assert-AiwTestPath $WorkingDirectory
 if(-not[IO.Directory]::Exists($cwd)){throw 'TEST_CWD_MISSING'}
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.WorkingDirectory=$cwd;$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.StandardOutputEncoding=$script:TestUtf8;$info.StandardErrorEncoding=$script:TestUtf8
 foreach($arg in $Arguments){$info.ArgumentList.Add([string]$arg)}
 foreach($key in $Environment.Keys){if($null-eq$Environment[$key]){$null=$info.Environment.Remove([string]$key)}else{$info.Environment[[string]$key]=[string]$Environment[$key]}}
 $observedEnvironment=[ordered]@{}
 if($EvidenceContractVersion-eq2){foreach($name in @(@('COMSPEC','PATH','PSModulePath','TEMP','TMP')+@($Environment.Keys)|Sort-Object -Unique)){$observedEnvironment[$name]=$info.Environment[$name]}}
 $started=[DateTime]::UtcNow;$timer=[Diagnostics.Stopwatch]::StartNew()
 $process=[Diagnostics.Process]::new();$process.StartInfo=$info
 $stdout=Join-Path $directory 'stdout.raw';$stderr=Join-Path $directory 'stderr.raw';$phases=Join-Path $directory 'phases.jsonl';$result=Join-Path $directory 'result.json'
 if(-not$process.Start()){throw 'TEST_PROCESS_START_FAILED'}
 $creation=$process.StartTime.ToUniversalTime().ToString('o')
 $handle=[pscustomobject]@{RunId=$runId;GroupId=$GroupId;Process=$process;CreationUtc=$creation;StartedUtc=$started.ToString('o');Timer=$timer;Stdout=$stdout;Stderr=$stderr;Phases=$phases;ResultPath=$result;Directory=$directory;Executable=$exe;ExecutableIdentity=$exeIdentity;ExecutableVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion;Arguments=@($Arguments);Cwd=$cwd;Executor=$Executor;DirectConsumer=$DirectConsumer;StdoutTask=$null;StderrTask=$null;DiagnosticWritten=$false;Completed=$false;Cancellation=$null;LaunchMilliseconds=$timer.Elapsed.TotalMilliseconds;EvidenceContractVersion=$EvidenceContractVersion;ObservedEnvironment=$observedEnvironment}
 $script:OwnedTestHandles.Add($handle)
 $handle.StdoutTask=[AiwTestStreamPump]::Drain($process.StandardOutput.BaseStream,$stdout)
 $handle.StderrTask=[AiwTestStreamPump]::Drain($process.StandardError.BaseStream,$stderr)
 $launchValue=[ordered]@{runId=$runId;pid=$process.Id;creationUtc=$creation;startedUtc=$handle.StartedUtc;executable=$exe;executableIdentity=$handle.ExecutableIdentity;executableVersion=$handle.ExecutableVersion;arguments=@($Arguments);cwd=$cwd;environmentNames=@($Environment.Keys|Sort-Object);raw=@($stdout,$stderr);resultPath=$result;executor=$Executor;directConsumer=$DirectConsumer}
 if($EvidenceContractVersion-eq2){$launchValue.schemaVersion=2;$launchValue.environment=$observedEnvironment}
 Write-AiwTestJson (Join-Path $directory 'launch.json') $launchValue
 Write-AiwTestPhase $phases $runId $GroupId 'native-start' 'START' @{pid=$process.Id;creationUtc=$creation;launchMilliseconds=$handle.LaunchMilliseconds}
 return $handle
}
function Assert-AiwTestOwnedProcess($Handle){
 if(-not$script:OwnedTestHandles.Contains($Handle)){throw 'TEST_PROCESS_OWNERSHIP_DRIFT'}
 if($Handle.Completed){throw 'TEST_PROCESS_ALREADY_CONSUMED'}
 if($Handle.Process.StartTime.ToUniversalTime().ToString('o')-cne$Handle.CreationUtc-or$Handle.Process.StartInfo.FileName-cne$Handle.Executable){throw 'TEST_PROCESS_OWNERSHIP_DRIFT'}
}
function Stop-AiwTestProcess {
 [CmdletBinding()]param([Parameter(Mandatory)]$Handle,[Parameter(Mandatory)][string]$AuthorizedRunId,[Parameter(Mandatory)][string]$Reason)
 if($AuthorizedRunId-cne$Handle.RunId-or[string]::IsNullOrWhiteSpace($Reason)){throw 'TEST_CANCELLATION_BINDING_REQUIRED'}
 Assert-AiwTestOwnedProcess $Handle
 $Handle.Cancellation=[pscustomobject]@{reason=$Reason;authorizedRunId=$AuthorizedRunId;utc=[DateTime]::UtcNow.ToString('o')}
 Write-AiwTestPhase $Handle.Phases $Handle.RunId $Handle.GroupId 'authorized-cancel' 'REACHED' $Handle.Cancellation
 if(-not$Handle.Process.HasExited){$Handle.Process.Kill($true)}
}
function Wait-AiwTestProcess {
 [CmdletBinding()]param([Parameter(Mandatory)]$Handle,[ValidateRange(0,30000)][int]$WaitMilliseconds=30000,[int]$SoftDiagnosticMilliseconds=60000)
 Assert-AiwTestOwnedProcess $Handle
 if(-not$Handle.Process.WaitForExit($WaitMilliseconds)){
  if(-not$Handle.DiagnosticWritten-and$Handle.Timer.ElapsedMilliseconds-ge$SoftDiagnosticMilliseconds){
   $Handle.DiagnosticWritten=$true
   Write-AiwTestPhase $Handle.Phases $Handle.RunId $Handle.GroupId 'soft-observation' 'DIAGNOSTIC' @{wallMilliseconds=$Handle.Timer.Elapsed.TotalMilliseconds;cpuMilliseconds=$Handle.Process.TotalProcessorTime.TotalMilliseconds;stdoutBytes=$(if([IO.File]::Exists($Handle.Stdout)){(Get-Item -LiteralPath $Handle.Stdout).Length}else{0});stderrBytes=$(if([IO.File]::Exists($Handle.Stderr)){(Get-Item -LiteralPath $Handle.Stderr).Length}else{0});action='CONTINUE';reason='Soft observation is not a cancellation budget'}
  }
  return [pscustomobject]@{Status='RUNNING';RunId=$Handle.RunId;ResultPath=$Handle.ResultPath}
 }
 $exitUtc=[DateTime]::UtcNow;$drain=[Diagnostics.Stopwatch]::StartNew()
 [Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($Handle.StdoutTask,$Handle.StderrTask)).GetAwaiter().GetResult()
 $drain.Stop();$Handle.Timer.Stop()
 $code=$Handle.Process.ExitCode;$status=if($null-ne$Handle.Cancellation){'STOPPED'}elseif($code-eq0){'PASS'}else{'FAIL'}
 $record=[ordered]@{runId=$Handle.RunId;status=$status;command=[ordered]@{executable=$Handle.Executable;executableIdentity=$Handle.ExecutableIdentity;executableVersion=$Handle.ExecutableVersion;arguments=$Handle.Arguments;cwd=$Handle.Cwd};pid=$Handle.Process.Id;creationUtc=$Handle.CreationUtc;executor=$Handle.Executor;directConsumer=$Handle.DirectConsumer;startedUtc=$Handle.StartedUtc;processExitedUtc=$exitUtc.ToString('o');endedUtc=[DateTime]::UtcNow.ToString('o');exitCode=$code;stdout=@{path=$Handle.Stdout;identity=(Get-AiwTestFileIdentity $Handle.Stdout)};stderr=@{path=$Handle.Stderr;identity=(Get-AiwTestFileIdentity $Handle.Stderr)};timing=@{wallMilliseconds=$Handle.Timer.Elapsed.TotalMilliseconds;nativeLaunchMilliseconds=$Handle.LaunchMilliseconds;exitDrainMilliseconds=$drain.Elapsed.TotalMilliseconds;cpuMilliseconds=$Handle.Process.TotalProcessorTime.TotalMilliseconds};cancellation=$Handle.Cancellation;streamOrdering='INTRA_STREAM_ONLY'}
 if($Handle.EvidenceContractVersion-eq2){$record.schemaVersion=2;$record.environment=$Handle.ObservedEnvironment}
 Write-AiwTestPhase $Handle.Phases $Handle.RunId $Handle.GroupId 'exit-drain' 'END' @{exitCode=$code;status=$status;resultPath=$Handle.ResultPath;timing=$record.timing}
 $record.endedUtc=[DateTime]::UtcNow.ToString('o')
 Write-AiwTestJson $Handle.ResultPath $record
 $Handle.Completed=$true;$Handle.Process.Dispose()
 # Native completion remains available even when strict text decoding rejects raw bytes.
 $stdout=[IO.File]::ReadAllText($Handle.Stdout,$script:TestUtf8);$stderr=[IO.File]::ReadAllText($Handle.Stderr,$script:TestUtf8)
 # Preserve each stream's order; no claimed total ordering between streams.
 $lines=@();foreach($streamText in @($stdout,$stderr)){if($streamText.Length){$lines+=@($streamText.TrimEnd([char]13,[char]10)-split'\r?\n')}}
 return [pscustomobject]@{Status=$status;RunId=$Handle.RunId;Code=$code;Output=@($lines);Text=($lines-join"`n");StdoutText=$stdout;StderrText=$stderr;ResultPath=$Handle.ResultPath;Record=$record}
}
function Invoke-AiwTestProcess {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments,[string]$WorkingDirectory=(Get-Location).Path,[hashtable]$Environment=@{},[string]$EvidenceDirectory=$env:AIW_TEST_RAW_DIRECTORY,[string]$GroupId='private-process',[int]$SoftDiagnosticMilliseconds=60000,[ValidateSet(1,2)][int]$EvidenceContractVersion=1)
 $handle=Start-AiwTestProcess -Executable $Executable -Arguments $Arguments -WorkingDirectory $WorkingDirectory -Environment $Environment -EvidenceDirectory $EvidenceDirectory -GroupId $GroupId -EvidenceContractVersion $EvidenceContractVersion
 do{$result=Wait-AiwTestProcess $handle -SoftDiagnosticMilliseconds $SoftDiagnosticMilliseconds}while($result.Status-ceq'RUNNING')
 return $result
}
function Get-AiwTestRawProcessStates([string]$EvidenceDirectory){
 $root=Assert-AiwTestPath $EvidenceDirectory;$rows=@()
 if(-not[IO.Directory]::Exists($root)){return @()}
 $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
 while($pending.Count){
  $directory=$pending.Pop()
  foreach($item in Get-ChildItem -LiteralPath $directory -Force){
   if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'TEST_RAW_PROCESS_REPARSE'}
   if($item.PSIsContainer){$pending.Push($item.FullName);continue}
   if($item.Name-cne'launch.json'){continue}
   $null=Get-AiwTestFileIdentity $item.FullName
   $launch=Get-Content -LiteralPath $item.FullName -Raw|ConvertFrom-Json -Depth 100
   $resultPath=Join-Path $directory 'result.json';$state='INCOMPLETE'
   if([IO.Path]::GetFullPath($launch.resultPath)-cne$resultPath){throw 'TEST_RAW_PROCESS_LOCATOR'}
   if([IO.File]::Exists($resultPath)){
    $null=Get-AiwTestFileIdentity $resultPath
    $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json -Depth 100
    if($result.runId-ceq$launch.runId-and$result.pid-eq$launch.pid-and$result.creationUtc-ceq$launch.creationUtc-and$null-ne$result.exitCode-and$result.status-cin@('PASS','FAIL','STOPPED')){$state='COMPLETE'}
   }
   $rows+=@{runId=$launch.runId;pid=$launch.pid;creationUtc=$launch.creationUtc;launchPath=$item.FullName;resultPath=$resultPath;state=$state}
  }
 }
 return @($rows)
}
function Get-AiwTestOwnedHandles { return @($script:OwnedTestHandles.ToArray()) }
Export-ModuleMember -Function Assert-AiwTestPath,Get-AiwTestFileIdentity,Write-AiwTestJson,Write-AiwTestPhase,Start-AiwTestProcess,Wait-AiwTestProcess,Stop-AiwTestProcess,Invoke-AiwTestProcess,Get-AiwTestRawProcessStates,Get-AiwTestOwnedHandles
