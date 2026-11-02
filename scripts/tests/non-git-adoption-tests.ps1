#requires -Version 7.0
[CmdletBinding()]
param([string]$BaselineRegisterScript,[switch]$CandidateRegistrationOnly,[switch]$NestedSelectorsOnly,[ValidateSet('All','NestedSelectors','CandidateRegistration','Transactions','PreflightAst','OriginalSourceAgents')][string]$Group='All',[switch]$FixtureContractOnly,[ValidateSet('Mechanism','Races','Preflight')][string]$ConfirmationPhase,[string]$RegisteredRuntimeRoot,[switch]$RegisteredMaintenance,[switch]$PositiveUpgradeOnly,[switch]$PreparationRecheck,[switch]$KeepFixture)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$sourceRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestHarness.psm1')
if($CandidateRegistrationOnly-and$NestedSelectorsOnly){throw 'NON_GIT_GROUP_FLAGS_CONFLICT'}
if(($CandidateRegistrationOnly-or$NestedSelectorsOnly)-and$PSBoundParameters.ContainsKey('Group')){throw 'NON_GIT_GROUP_FLAGS_CONFLICT'}
$Group=@('All','NestedSelectors','CandidateRegistration','Transactions','PreflightAst','OriginalSourceAgents')|Where-Object{$_-ieq$Group}
if($NestedSelectorsOnly){$Group='NestedSelectors'}
if($RegisteredRuntimeRoot-and($Group-cne'CandidateRegistration'-or$FixtureContractOnly-or$BaselineRegisterScript-or$PSBoundParameters.ContainsKey('ConfirmationPhase'))){throw 'DECLARED_REGISTER_ORIGIN_SELECTOR'}
if($PositiveUpgradeOnly-and-not$RegisteredRuntimeRoot){throw 'POSITIVE_UPGRADE_REQUIRES_DECLARED_OLD_ORIGIN'}
if($PreparationRecheck-and(-not$PositiveUpgradeOnly-or$RegisteredMaintenance)){throw 'PREPARATION_RECHECK_REQUIRES_POSITIVE_REGISTERED_ORIGIN'}
if($RegisteredMaintenance-and(-not$RegisteredRuntimeRoot-or$PositiveUpgradeOnly)){throw 'MAINTENANCE_SOURCE_REQUIRES_COMPLETE_DECLARED_ORIGIN_CASE'}
if($KeepFixture-and-not$RegisteredRuntimeRoot){throw 'KEEP_FIXTURE_REQUIRES_DECLARED_OLD_ORIGIN'}
if($BaselineRegisterScript-and$Group-cne'All'-and$Group-cne'Transactions'){throw 'BASELINE_REQUIRES_TRANSACTIONS'}
$pwsh=(Get-Command pwsh -CommandType Application).Source
$git=(Get-Command git -CommandType Application -ErrorAction SilentlyContinue).Source
$oldPath=$env:PATH;$utf8=[Text.UTF8Encoding]::new($false);$passed=0
$preflightModule=$null;$confirmationLibrary=$null;$confirmationRunner=$null;$safeGitReader=$null
if($PSBoundParameters.ContainsKey('ConfirmationPhase')-and(-not$FixtureContractOnly-or$Group-cne'CandidateRegistration'-or$BaselineRegisterScript-or$CandidateRegistrationOnly-or$NestedSelectorsOnly)){throw 'CONFIRMATION_PHASE_REQUIRES_PRIVATE_CANDIDATE_FIXTURE'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-nongit-adoption-'+[guid]::NewGuid().ToString('N'))
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 80 -Compress)}
function Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw "ASSERT_FAIL|$Name"};$script:passed++;Write-Output "PASS|$Name"}
function InvokeTool([string]$Tool,[hashtable]$Parameters,[string]$WorkingDirectory){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $invocation=Join-Path $temp ('call-'+[guid]::NewGuid().ToString('N')+'.json');SaveJson $invocation @{tool=$Tool;parameters=$Parameters;workingDirectory=$WorkingDirectory}
 $run=Invoke-AiwTestProcess $pwsh @('-NoProfile','-NonInteractive','-File',$runner,'-InputPath',$invocation) -GroupId ('non-git-'+$Group);$lines=@($run.Output);$code=$run.Code
 $value=$null;if($code-eq0){$value=$lines[-1]|ConvertFrom-Json -Depth 100;if($value-is[string]-and$value.StartsWith('{')){$value=$value|ConvertFrom-Json -Depth 100}}
 $watch.Stop()
 return [pscustomobject]@{code=$code;value=$value;text=($lines-join"`n");wallSeconds=$watch.Elapsed.TotalSeconds}
}
function RunTool([string]$Tool,[hashtable]$Parameters){$result=InvokeTool $Tool $Parameters;if($result.code-ne0){throw ('TOOL_FAILED|'+[IO.Path]::GetFileName($Tool)+'|'+$result.text)};return $result.value}
function Invoke-RegistrationNative([string]$Tool,[hashtable]$Parameters){
 $arguments=[Collections.Generic.List[string]]::new()
 foreach($argument in @('-NoProfile','-NonInteractive','-File',$Tool)){$arguments.Add($argument)}
 foreach($name in $Parameters.Keys|Sort-Object){
  $value=$Parameters[$name]
  if($value-is[bool]-or$value-is[Management.Automation.SwitchParameter]){if($value){$arguments.Add('-'+$name)}}
  else{$arguments.Add('-'+$name);$arguments.Add([string]$value)}
 }
 $run=Invoke-AiwTestProcess $pwsh $arguments.ToArray() -GroupId ('non-git-'+$Group+'-registrar-native')
 $evidence=@{exitCode=$run.Code;resultPath=$run.ResultPath;stdout=$run.Record.stdout;stderr=$run.Record.stderr;stdoutText=$run.StdoutText;stderrText=$run.StderrText}|ConvertTo-Json -Depth 100 -Compress
 if($run.Code-ne0-or$run.StderrText-cne''){throw ('REGISTRATION_NATIVE_FAILED|'+$evidence)}
 $lines=@($run.StdoutText -split '\r?\n'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
 $records=@($lines|Where-Object{$_.StartsWith('{')})
 $unknown=@($lines|Where-Object{-not$_.StartsWith('{')-and$_-cnotmatch'^PROJECT_ADOPTION_(PREVIEW|WRITESET|RECOVERY_PREVIEW)\|'})
 if($records.Count-ne1-or$unknown.Count){throw ('REGISTRATION_NATIVE_RESPONSE_REQUIRED|'+$evidence)}
 try{$reply=ConvertFrom-Json -InputObject $records[0] -Depth 100 -ErrorAction Stop}catch{throw ('REGISTRATION_NATIVE_JSON_INVALID|'+$_.Exception.Message+'|'+$evidence)}
 if($reply-isnot[pscustomobject]-or$null-eq$reply.PSObject.Properties['status']-or$reply.status-isnot[string]){throw ('REGISTRATION_NATIVE_RESPONSE_SHAPE|'+$evidence)}
 $run|Add-Member -NotePropertyName Reply -NotePropertyValue $reply
 return $run
}
function Get-SafeGitRejection($Result,$Reader){
 if($Result.code-ne3-or$null-ne$Result.value){return $null}
 try{$reply=& $Reader.ExportedCommands['ConvertFrom-AiwStrictInputJson'] -Text $Result.text -StringFields @('status','operation','repositoryId','reason')}catch{return $null}
 # Required names are exact; additional producer fields are not a closed contract.
 if(@(@('status','operation','repositoryId','reason','launched')|Where-Object{$_-cnotin$reply.MemberNames}).Count){return $null}
 $descriptor=$reply.Value
 if($descriptor.status-cne'UNVERIFIED'-or$descriptor.operation-cne'STATUS'-or$descriptor.repositoryId-cne'PROJECT'-or[string]::IsNullOrWhiteSpace($descriptor.reason)-or$descriptor.launched-isnot[bool]-or$descriptor.launched){return $null}
 return $descriptor
}
function New-NonGitTargetPreflightFixture([string]$UpgradeScript){
 $tokens=$null;$parseErrors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($UpgradeScript,[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw 'UPGRADE_PARSE'}
 # The public action now owns a private qualification scope outside the source
 # scope. Extract the same unique real source body through that lexical wrapper.
 $entries=@($ast.FindAll({param($node) $node-is[Management.Automation.Language.CommandAst]-and$node.GetCommandName()-ceq'Invoke-AiwRootAdoptionSourceScope'},$true))
 if($entries.Count-ne1){throw 'NONGIT_PREFLIGHT_ENTRY_REQUIRED'}
 $bodyArguments=@(for($index=0;$index-lt$entries[0].CommandElements.Count-1;$index++){
  $element=$entries[0].CommandElements[$index]
  if($element-is[Management.Automation.Language.CommandParameterAst]-and$element.ParameterName-ceq'Body'){$entries[0].CommandElements[$index+1]}
 })
 if($bodyArguments.Count-ne1-or$bodyArguments[0]-isnot[Management.Automation.Language.ScriptBlockExpressionAst]){throw 'NONGIT_PREFLIGHT_BODY_REQUIRED'}
 # Preserve each first-level function's nested definitions and lexical owner.
 $functions=@($bodyArguments[0].ScriptBlock.EndBlock.Statements|Where-Object{$_-is[Management.Automation.Language.FunctionDefinitionAst]})
 $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($function in $functions){if(-not$names.Add($function.Name)){throw ('NONGIT_PREFLIGHT_FUNCTION_DUPLICATE|'+$function.Name)}}
 if(@($functions|Where-Object Name -CEQ 'Get-TargetProjectedProcessPreflight').Count-ne1){throw 'NONGIT_PREFLIGHT_HELPER_REQUIRED'}
 $definitions=@($functions|ForEach-Object{$_.Extent.Text})-join"`n"
 $fixture=New-Module -Name NonGitPreflightFixture -ScriptBlock ([scriptblock]::Create($definitions))
 try{
  if(-not$fixture.ExportedFunctions.ContainsKey('Get-TargetProjectedProcessPreflight')-or-not[object]::ReferenceEquals($fixture.ExportedFunctions['Get-TargetProjectedProcessPreflight'].Module,$fixture)){throw 'NONGIT_PREFLIGHT_CONSTRUCTED_HELPER_REQUIRED'}
  return $fixture
 }catch{Remove-Module -ModuleInfo $fixture;throw}
}
function Snapshot([string]$Root){
 # Inspect each directory before descending; never hash through a reparse.
 $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Root)
 $rows=[Collections.Generic.List[string]]::new()
 while($pending.Count){
  $directory=$pending.Pop()
  if((Get-Item -LiteralPath $directory -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'SNAPSHOT_REPARSE'}
  foreach($entry in Get-ChildItem -LiteralPath $directory -Force){
   if($entry.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'SNAPSHOT_REPARSE'}
   $relative=[IO.Path]::GetRelativePath($Root,$entry.FullName).Replace('\','/')
   $rows.Add($relative+'|'+$(if($entry.PSIsContainer){'DIRECTORY'}else{Identity $entry.FullName}))
   if($entry.PSIsContainer){$pending.Push($entry.FullName)}
  }
 }
 return [string]::Join("`n",@($rows|Sort-Object -CaseSensitive))
}
function Test-PristineSnapshotPreserved([string]$Root,[string]$Before){
 return (Snapshot $Root)-ceq$Before-and-not(Test-Path -LiteralPath (Join-Path $Root '.ai-workspace'))
}
function Test-SnapshotPreserved([string]$Root,[string]$Before){
 try{$after=Snapshot $Root}catch{if($_.Exception.Message-ceq'SNAPSHOT_REPARSE'){return $false};throw}
 if($after-ceq$Before){return $true}
 $beforeRows=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 $afterRows=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($row in ($Before-split"`n")){if($row.Length){$null=$beforeRows.Add($row)}}
 foreach($row in ($after-split"`n")){if($row.Length){$null=$afterRows.Add($row)}}
 # Every old row, including directory presence and file identity, must survive.
 foreach($row in $beforeRows){if(-not$afterRows.Contains($row)){return $false}}
 $added=@($afterRows|Where-Object{-not$beforeRows.Contains($_)})
 $lockRow='.ai-workspace/runtime/source-publication.lock|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
 if($lockRow-cnotin$added){return $false}
 $allowed=@($lockRow,'.ai-workspace|DIRECTORY','.ai-workspace/runtime|DIRECTORY')
 return @($added|Where-Object{$_-cnotin$allowed}).Count-eq0
}
function Test-SnapshotSynchronizationAllowance {
 # These counterexamples protect the test oracle itself: accepting the carrier
 # must not hide unrelated writes, removals or traversal through a link.
 foreach($kind in @('lock-only','existing-parents','parents-only','nonempty-lock','directory-lock','extra-file','extra-directory','changed-file','removed-file','reparse-lock','reparse-parent')){
  $root=Join-Path $temp ('snapshot-'+$kind);$null=[IO.Directory]::CreateDirectory($root)
  $existing=Join-Path $root 'existing.bin';SaveText $existing 'Preserve these exact bytes.'
  $runtime=Join-Path $root '.ai-workspace/runtime';$lock=Join-Path $runtime 'source-publication.lock'
  if($kind-ceq'existing-parents'){$null=[IO.Directory]::CreateDirectory($runtime)}
  $before=Snapshot $root
  $null=[IO.Directory]::CreateDirectory($runtime)
  if($kind-cnotin@('parents-only','directory-lock','reparse-lock','reparse-parent')){[IO.File]::WriteAllBytes($lock,[byte[]]@())}
  switch($kind){
   'nonempty-lock' {SaveText $lock 'not empty'}
   'directory-lock' {$null=[IO.Directory]::CreateDirectory($lock)}
   'extra-file' {SaveText (Join-Path $runtime 'unexpected.json') '{}'}
   'extra-directory' {$null=[IO.Directory]::CreateDirectory((Join-Path $runtime 'unexpected'))}
   'changed-file' {SaveText $existing 'Changed bytes must fail.'}
   'removed-file' {[IO.File]::Delete($existing)}
   'reparse-lock' {$outside=Join-Path $temp 'snapshot-outside-lock';$null=[IO.Directory]::CreateDirectory($outside);$null=New-Item -ItemType Junction -Path $lock -Target $outside}
   'reparse-parent' {$outside=Join-Path $temp 'snapshot-outside-parent';$null=[IO.Directory]::CreateDirectory($outside);[IO.Directory]::Delete($runtime);$null=New-Item -ItemType Junction -Path $runtime -Target $outside}
  }
  $expected=$kind-cin@('lock-only','existing-parents')
  Check ((Test-SnapshotPreserved $root $before)-eq$expected) ('snapshot-sync-allowance-'+$kind)
 }
}
# @design-contract CONFIRMATION-RACE-SYNCHRONIZATION-20261011.md
# Test-local host and one continuous reader per stream. The full registrar
# still owns preparation, ShouldProcess, scope entry and locked commit.
function Initialize-ConfirmationHost {
 if($script:confirmationLibrary){return}
 $script:confirmationLibrary=Join-Path $temp 'confirmation-host.cs'
 SaveText $script:confirmationLibrary @'
using System;
using System.IO;
using System.Text;
using System.Globalization;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Security;
using System.Threading.Tasks;
using System.Management.Automation;
using System.Management.Automation.Host;
public sealed class AiwConfirmationCapture {
 readonly object gate = new object(); readonly StringBuilder content = new StringBuilder();
 readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
 public Task Completion { get; private set; } public bool Eof { get; private set; }
 public string ReadError { get; private set; }
 public AiwConfirmationCapture(StreamReader reader) { Completion = Drain(reader); }
 async Task Drain(StreamReader reader) {
  var line = new StringBuilder(); var buffer = new char[4096];
  try {
   int count;
   while ((count = await reader.ReadAsync(buffer,0,buffer.Length).ConfigureAwait(false)) > 0) {
    lock(gate) { content.Append(buffer,0,count); }
    for(int i=0;i<count;i++) {
     if(buffer[i]=='\n') { lines.Enqueue(line.ToString().TrimEnd('\r')); line.Clear(); }
     else line.Append(buffer[i]);
    }
   }
   if(line.Length>0) lines.Enqueue(line.ToString()); Eof=true;
  } catch(Exception error) { ReadError=error.ToString(); }
 }
 public string Text { get { lock(gate) { return content.ToString(); } } }
 public string[] TakeLines() { var result=new List<string>(); string line; while(lines.TryDequeue(out line)) result.Add(line); return result.ToArray(); }
}
public sealed class AiwConfirmationHost : PSHost {
 readonly Guid instance=Guid.NewGuid(); readonly AiwConfirmationUi choiceUi;
 public int? RequestedExit { get; private set; }
 public AiwConfirmationHost(string token,string target,string action) { choiceUi=new AiwConfirmationUi(token,target,action); }
 public override Guid InstanceId { get { return instance; } }
 public override string Name { get { return "AIW isolated confirmation test"; } }
 public override Version Version { get { return new Version(1,0); } }
 public override CultureInfo CurrentCulture { get { return CultureInfo.CurrentCulture; } }
 public override CultureInfo CurrentUICulture { get { return CultureInfo.CurrentUICulture; } }
 public override PSHostUserInterface UI { get { return choiceUi; } }
 public override void SetShouldExit(int exitCode) { RequestedExit=exitCode; }
 public override void EnterNestedPrompt() { throw new NotSupportedException("AIW_CONFIRM_NESTED_PROMPT"); }
 public override void ExitNestedPrompt() { throw new NotSupportedException("AIW_CONFIRM_NESTED_PROMPT"); }
 public override void NotifyBeginApplication() { }
 public override void NotifyEndApplication() { }
}
public sealed class AiwConfirmationUi : PSHostUserInterface {
 readonly string caseToken, expectedTarget, expectedAction; int promptCount;
 public AiwConfirmationUi(string token,string target,string action) { caseToken=token; expectedTarget=target; expectedAction=action; }
 static string Enc(string value) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(value)); }
 public override PSHostRawUserInterface RawUI { get { return null; } }
 public override int PromptForChoice(string caption,string message,Collection<ChoiceDescription> choices,int defaultChoice) {
  promptCount++;
  var labels=new List<string>(); foreach(var choice in choices) labels.Add(choice.Label);
  string actualLabels=string.Join(";",labels);
  Console.Out.WriteLine("AIW_CONFIRM|"+caseToken+"|"+Enc(caption)+"|"+Enc(message)+"|"+Enc(actualLabels)+"|"+defaultChoice.ToString(CultureInfo.InvariantCulture)); Console.Out.Flush();
  string expectedMessage="Are you sure you want to perform this action?\nPerforming the operation \""+expectedAction+"\" on target \""+expectedTarget+"\".";
  if(promptCount!=1 || caption!="Confirm" || message.Replace("\r\n","\n")!=expectedMessage || actualLabels!="&Yes;Yes to &All;&No;No to A&ll;&Suspend" || defaultChoice!=0) throw new InvalidOperationException("AIW_CONFIRM_SHAPE_MISMATCH");
  string reply=Console.In.ReadLine();
  if(reply==null) throw new InvalidOperationException("AIW_CONFIRM_REPLY_EOF");
  if(reply!="AIW_REPLY|"+caseToken+"|YES") throw new InvalidOperationException("AIW_CONFIRM_REPLY_MISMATCH");
  Console.Out.WriteLine("AIW_ACK|"+caseToken); Console.Out.Flush(); return 0;
 }
 public override string ReadLine() { throw new NotSupportedException("AIW_CONFIRM_READ_LINE"); }
 public override SecureString ReadLineAsSecureString() { throw new NotSupportedException("AIW_CONFIRM_SECRET"); }
 public override Dictionary<string,PSObject> Prompt(string caption,string message,Collection<FieldDescription> descriptions) { throw new NotSupportedException("AIW_CONFIRM_FIELDS"); }
 public override PSCredential PromptForCredential(string caption,string message,string userName,string targetName) { throw new NotSupportedException("AIW_CONFIRM_CREDENTIAL"); }
 public override PSCredential PromptForCredential(string caption,string message,string userName,string targetName,PSCredentialTypes allowed,PSCredentialUIOptions options) { throw new NotSupportedException("AIW_CONFIRM_CREDENTIAL"); }
 public override void Write(string value) { Console.Out.Write(value); Console.Out.Flush(); }
 public override void Write(ConsoleColor foreground,ConsoleColor background,string value) { Write(value); }
 public override void WriteLine(string value) { Console.Out.WriteLine(value); Console.Out.Flush(); }
 public override void WriteErrorLine(string value) { Console.Error.WriteLine(value); Console.Error.Flush(); }
 public override void WriteDebugLine(string value) { WriteErrorLine("DEBUG: "+value); }
 public override void WriteVerboseLine(string value) { WriteErrorLine("VERBOSE: "+value); }
 public override void WriteWarningLine(string value) { WriteErrorLine("WARNING: "+value); }
 public override void WriteProgress(long sourceId,ProgressRecord record) { }
}
'@
 Add-Type -Path $script:confirmationLibrary
 $script:confirmationRunner=Join-Path $temp 'confirmation-runner.ps1'
 SaveText $script:confirmationRunner ((@'
param([string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop';$runspace=$null;$pipeline=$null
try {
 $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
 Add-Type -Path $call.library
 Set-Location -LiteralPath $call.workingDirectory;[Environment]::CurrentDirectory=$call.workingDirectory
 $confirmationHost=[AiwConfirmationHost]::new($call.token,$call.target,$call.action)
 $runspace=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($confirmationHost);$runspace.Open()
 $null=$runspace.SessionStateProxy.Path.SetLocation($call.workingDirectory)
 $runspace.SessionStateProxy.SetVariable('ErrorActionPreference','Stop')
 $pipeline=[Management.Automation.PowerShell]::Create();$pipeline.Runspace=$runspace
 $null=$pipeline.AddCommand($call.tool).AddParameters($call.parameters)
 $output=@($pipeline.Invoke())
 if($pipeline.HadErrors){foreach($record in $pipeline.Streams.Error){[Console]::Error.WriteLine($record.ToString());[Console]::Error.WriteLine($record.Exception.ToString())};exit 1}
 if($output.Count-eq1){$output[0]|ConvertTo-Json -Depth 100 -Compress}else{ConvertTo-Json -InputObject $output -Depth 100 -Compress}
 $native=$runspace.SessionStateProxy.GetVariable('LASTEXITCODE')
 if($null-ne$confirmationHost.RequestedExit){exit $confirmationHost.RequestedExit}
 if($null-ne$native-and$native-ne0){exit $native}
}catch{[Console]::Error.WriteLine($_.ToString());[Console]::Error.WriteLine($_.Exception.ToString());exit 1}
finally{if($pipeline){$pipeline.Dispose()};if($runspace){$runspace.Dispose()}}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
}
function Invoke-ConfirmationProcess([string]$Tool,[hashtable]$Parameters,[string]$Case,[string]$Target,[string]$Action,[scriptblock]$OnCallback,[ValidateSet('Reply','Eof','Deadline','Decline')][string]$Mode='Reply') {
 Initialize-ConfirmationHost
 $token=[guid]::NewGuid().ToString('N');$invocationPath=Join-Path $temp ('confirmation-'+$token+'.json')
 $workingDirectory=(Get-Location).Path;$childRunner=if($Mode-ceq'Decline'){$runner}else{$script:confirmationRunner}
 $call=@{tool=$Tool;parameters=$Parameters;workingDirectory=$workingDirectory}
 if($Mode-cne'Decline'){$call.library=$script:confirmationLibrary;$call.token=$token;$call.target=$Target;$call.action=$Action}
 SaveJson $invocationPath $call
 $rawRoot=if($env:AIW_TEST_RAW_DIRECTORY){$env:AIW_TEST_RAW_DIRECTORY}else{Join-Path ([IO.Path]::GetTempPath()) ('aiw-confirmation-raw-'+$token)}
 $raw=Join-Path $rawRoot ('confirmation-'+$token);$null=[IO.Directory]::CreateDirectory($raw)
 $arguments=@('-NoProfile','-File',$childRunner,'-InputPath',$invocationPath)
 $environment=@{};foreach($name in @('PATH','PSModulePath','TEMP','TMP','COMSPEC')){$environment[$name]=[Environment]::GetEnvironmentVariable($name)}
 $launch=@{case=$Case;mode=$Mode;token=$token;executable=$pwsh;executableIdentity=(Identity $pwsh);arguments=$arguments;cwd=$workingDirectory;environment=$environment;tool=$Tool;toolIdentity=(Identity $Tool);runnerIdentity=(Identity $childRunner);libraryIdentity=(Identity $script:confirmationLibrary);parameters=$Parameters;invocation=$call;startDeadlineMilliseconds=60000;replyDeadlineMilliseconds=$(if($Mode-ceq'Deadline'){1000}else{60000})}
 Write-AiwTestJson (Join-Path $raw 'confirmation-start.json') $launch
 $timer=[Diagnostics.Stopwatch]::StartNew();$stages=[Collections.Generic.List[object]]::new()
 function Stage([string]$Name,$Data){$stages.Add(@{name=$Name;milliseconds=$timer.Elapsed.TotalMilliseconds;utc=[DateTime]::UtcNow.ToString('o');data=$Data})}
 $process=$null;$stdout=$null;$stderr=$null;$started=$false;$created=$null;$native=$null;$failure=$null;$termination=$false;$deadline=$false;$callback=$false;$ack=$false;$mutation=$null;$replyAt=$null;$stdinClosed=$false;$streamComplete=$false
 $start=[Diagnostics.ProcessStartInfo]::new($pwsh);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WorkingDirectory=$workingDirectory
 $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $start.StandardOutputEncoding=$utf8;$start.StandardErrorEncoding=$utf8
 foreach($argument in $arguments){$start.ArgumentList.Add($argument)}
 try {
  Stage 'STARTING' $null;$process=[Diagnostics.Process]::new();$process.StartInfo=$start
  if(-not$process.Start()){throw 'AIW_CONFIRM_START_FAILED'};$started=$true;$created=$process.StartTime.ToUniversalTime().ToString('o');Stage 'STARTED' @{pid=$process.Id;creationUtc=$created}
  $stdout=[AiwConfirmationCapture]::new($process.StandardOutput);$stderr=[AiwConfirmationCapture]::new($process.StandardError)
  if($Mode-ceq'Decline'){$process.StandardInput.WriteLine('N');$process.StandardInput.Close();$stdinClosed=$true;Stage 'REPLY_SENT' 'N';Stage 'STDIN_CLOSED' $null}
  while(-not$process.HasExited){
   foreach($line in $stdout.TakeLines()){
    if($line.StartsWith('AIW_CONFIRM|',[StringComparison]::Ordinal)){
     $fields=$line.Split('|');if($callback-or$fields.Count-ne6-or$fields[1]-cne$token-or$Mode-ceq'Decline'){throw 'AIW_CONFIRM_UNEXPECTED_CALLBACK'}
     $caption=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fields[2]));$message=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fields[3]));$choices=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fields[4]))
     $expected="Are you sure you want to perform this action?`nPerforming the operation `"$Action`" on target `"$Target`"."
     if($caption-cne'Confirm'-or$message.Replace("`r`n","`n")-cne$expected-or$choices-cne'&Yes;Yes to &All;&No;No to A&ll;&Suspend'-or$fields[5]-cne'0'){throw 'AIW_CONFIRM_SHAPE_MISMATCH'}
     $callback=$true;Stage 'CALLBACK_REACHED' @{caption=$caption;message=$message;choices=$choices;defaultChoice=$fields[5]}
     if($process.HasExited){throw 'AIW_CONFIRM_EXITED_BEFORE_MUTATION'}
     $mutation=& $OnCallback;Stage 'PARENT_MUTATION_COMMITTED' $mutation;$replyAt=$timer.Elapsed.TotalMilliseconds
     if($Mode-ceq'Reply'){$process.StandardInput.WriteLine('AIW_REPLY|'+$token+'|YES');$process.StandardInput.Flush();Stage 'REPLY_SENT' @{token=$token;choice='YES'}}
     if($Mode-cin@('Reply','Eof')){$process.StandardInput.Close();$stdinClosed=$true;Stage 'STDIN_CLOSED' $null}
    }elseif($line.StartsWith('AIW_ACK|',[StringComparison]::Ordinal)){
     if(-not$callback-or$ack-or$Mode-cne'Reply'-or$line-cne('AIW_ACK|'+$token)){throw 'AIW_CONFIRM_UNEXPECTED_ACK'};$ack=$true;Stage 'ACK_ACCEPTED' $token
    }
   }
   if($stdout.ReadError-or$stderr.ReadError){throw 'AIW_CONFIRM_STREAM_READ_FAILED'}
   $limit=if($null-ne$replyAt){$launch.replyDeadlineMilliseconds}else{$launch.startDeadlineMilliseconds}
   $since=if($null-ne$replyAt){$timer.Elapsed.TotalMilliseconds-$replyAt}else{$timer.Elapsed.TotalMilliseconds}
   if($since-ge$limit){$deadline=$true;Stage 'DEADLINE' @{stage=$(if($callback){'REPLY'}else{'CALLBACK'});limitMilliseconds=$limit};break}
   $null=$process.WaitForExit(20)
  }
 }catch{$failure=$_.ToString();Stage $(if($started){'PARENT_ERROR'}else{'START_FAILED'}) $failure}
 finally {
  if($started){
   if(-not$process.HasExited){
    if($process.StartTime.ToUniversalTime().ToString('o')-cne$created-or$process.StartInfo.FileName-cne$pwsh){$failure='AIW_CONFIRM_OWNERSHIP_DRIFT'}
    else{try{$process.Kill($true);$termination=$true;Stage 'FORCED_TERMINATION' @{pid=$process.Id};$null=$process.WaitForExit(10000)}catch{$failure=$_.ToString();Stage 'CLEANUP_ERROR' $failure}}
   }
   if(-not$stdinClosed){try{$process.StandardInput.Close();$stdinClosed=$true;Stage 'STDIN_CLOSED' $null}catch{Stage 'STDIN_CLOSE_ERROR' $_.ToString()}}
   if($process.HasExited){$native=$process.ExitCode;Stage 'EXITED' @{nativeCode=$native}}
   if($stdout-and$stderr){
    $streamComplete=$stdout.Completion.Wait(10000)-and$stderr.Completion.Wait(10000)-and$stdout.Eof-and$stderr.Eof-and-not$stdout.ReadError-and-not$stderr.ReadError
    # ACK can arrive in the final drain after native exit; there is still only
    # one reader. A second prompt after exit is rejected without mutation.
    foreach($line in $stdout.TakeLines()){
     if($line.StartsWith('AIW_ACK|',[StringComparison]::Ordinal)){
      if(-not$callback-or$ack-or$Mode-cne'Reply'-or$line-cne('AIW_ACK|'+$token)){$failure='AIW_CONFIRM_UNEXPECTED_ACK'}else{$ack=$true;Stage 'ACK_ACCEPTED' $token}
     }elseif($line.StartsWith('AIW_CONFIRM|',[StringComparison]::Ordinal)){$failure='AIW_CONFIRM_UNCONSUMED_CALLBACK'}
    }
   }
  }
  $stdoutText=if($stdout){$stdout.Text}else{''};$stderrText=if($stderr){$stderr.Text}else{''}
  [IO.File]::WriteAllText((Join-Path $raw 'stdout.raw'),$stdoutText,$utf8);[IO.File]::WriteAllText((Join-Path $raw 'stderr.raw'),$stderrText,$utf8)
  Stage 'STREAMS' @{complete=$streamComplete;stdoutEof=$(if($stdout){$stdout.Eof}else{$false});stderrEof=$(if($stderr){$stderr.Eof}else{$false})}
  $result=[pscustomobject]@{case=$Case;mode=$Mode;token=$token;launch=$launch;pid=$(if($started){$process.Id}else{$null});creationUtc=$created;nativeCode=$native;callbackReached=$callback;ackAccepted=$ack;mutation=$mutation;deadline=$deadline;forcedTermination=$termination;stdinClosed=$stdinClosed;streamsComplete=$streamComplete;stdout=$stdoutText;stderr=$stderrText;stdoutReadError=$(if($stdout){$stdout.ReadError}else{$null});stderrReadError=$(if($stderr){$stderr.ReadError}else{$null});failure=$failure;stages=@($stages.ToArray());cleanup=$(if(-not$started-or$process.HasExited){'COMPLETE'}else{'INCOMPLETE'});wallMilliseconds=$timer.Elapsed.TotalMilliseconds;rawDirectory=$raw}
  Write-AiwTestJson (Join-Path $raw 'confirmation-result.json') $result
  if($process){$process.Dispose()}
 }
 if($failure){throw ('AIW_CONFIRM_PARENT_FAILED|'+$failure+'|'+$raw)}
 if(-not$streamComplete){throw ('AIW_CONFIRM_STREAMS_INCOMPLETE|'+$raw)}
 if($deadline-and$Mode-cne'Deadline'){throw ('AIW_CONFIRM_DEADLINE|'+$raw)}
 return $result
}
function DeclineTool([string]$Tool,[hashtable]$Parameters){
 $result=Invoke-ConfirmationProcess $Tool $Parameters 'native-console-decline' '' '' {} 'Decline'
 $text=$result.stdout+$result.stderr
 if($result.nativeCode-ne0){throw ('CONFIRM_DECLINE_FAILED|'+$text)}
 return $text
}
function Invoke-ConfirmationMechanismTests {
 $probe=Join-Path $temp 'confirmation-mechanism.ps1';$sentinel=Join-Path $temp 'confirmation-sentinel.txt'
 SaveText $probe @'
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([string]$Sentinel)
$ErrorActionPreference='Stop';$prepared=[IO.File]::ReadAllText($Sentinel).Trim()
if($PSCmdlet.ShouldProcess($Sentinel,'Apply isolated confirmation mechanism')){
 [pscustomobject]@{prepared=$prepared;after=[IO.File]::ReadAllText($Sentinel).Trim();decision=$true}
}
'@
 foreach($mode in @('Reply','Eof','Deadline')){
  SaveText $sentinel 'original'
  $onCallback={SaveText $sentinel 'changed';@{sentinelIdentity=(Identity $sentinel)}}
  $result=Invoke-ConfirmationProcess $probe @{Sentinel=$sentinel;Confirm=$true} ('mechanism-'+$mode) $sentinel 'Apply isolated confirmation mechanism' $onCallback $mode
  if($mode-ceq'Reply'){
   $value=@($result.stdout.Trim()-split'\r?\n')[-1]|ConvertFrom-Json
   Check ($result.nativeCode-eq0-and$result.callbackReached-and$result.ackAccepted-and$value.prepared-ceq'original'-and$value.after-ceq'changed'-and$value.decision) 'confirmation-mechanism-prepare-callback-parent-change-reply-real-result'
  }elseif($mode-ceq'Eof'){
   Check ($result.nativeCode-ne0-and$result.callbackReached-and-not$result.ackAccepted-and-not$result.deadline-and$result.stderr.Contains('AIW_CONFIRM_REPLY_EOF')-and$result.streamsComplete-and$result.cleanup-ceq'COMPLETE') 'confirmation-mechanism-eof-fails-with-complete-native-streams'
  }else{
   Check ($result.callbackReached-and$result.deadline-and$result.forcedTermination-and-not$result.ackAccepted-and$null-ne$result.nativeCode-and$result.streamsComplete-and$result.cleanup-ceq'COMPLETE') 'confirmation-mechanism-finite-deadline-preserves-native-streams-and-owned-cleanup'
  }
 }
}
function SealFixture([string]$Root,[switch]$Candidate){
 if([IO.Path]::GetFileName($Root)-ceq'2.0.0'){Set-AiwTestFixtureQualification $Root -Candidate:$Candidate;return}
 # Synthetic qualification exists only in this isolated fixture. It is not
 # source Review or release evidence for the working candidate.
 $p=Join-Path $Root 'VERSION.json';$o=Get-Content $p -Raw|ConvertFrom-Json;$o.lifecycle=$(if($Candidate){'CANDIDATE'}else{'STABLE'});$o.consumable=-not[bool]$Candidate;$o.projectPinEligible=-not[bool]$Candidate;SaveJson $p $o
 $p=Join-Path $Root 'LOAD_MANIFEST.json';$o=Get-Content $p -Raw|ConvertFrom-Json;$o.lifecycle=$(if($Candidate){'CANDIDATE'}else{'STABLE'});SaveJson $p $o
 [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'});[Array]::Sort($paths,[StringComparer]::Ordinal)
 $rows=@();[long]$bytes=0;foreach($relative in $paths){$id=Identity (Join-Path $Root $relative);$bytes+=[long]$id.Split('|')[0];$rows+=($relative+'|'+$id)}
 $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($rows-join"`n")))
 $p=Join-Path $Root 'RELEASE_MANIFEST.json';$before=Identity $p;$o=Get-Content $p -Raw|ConvertFrom-Json
 $o.lifecycle=$(if($Candidate){'CANDIDATE'}else{'STABLE'});$o.fileCount=$paths.Count;$o.totalBytes=$bytes;$o.canonical=$canonical;$o.sourceReview='APPROVED';$o.sourceCandidate='TEST_FIXTURE_NON_GIT'
 $o.completeSuite=[pscustomobject]@{status='PASS';passed=1;total=1;payloadCanonical=$canonical;evidenceIdentity=('1|'+('A'*64))}
 $o.sourceReviewEvidence=[pscustomobject]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$canonical;reviewedManifestIdentity=$before};$o.releaseIntegration=$(if($Candidate){'PENDING'}else{'ISOLATED_TEST_FIXTURE'});SaveJson $p $o
}
function SealRuntimeFixture([string]$Root,[switch]$Candidate,[int]$Snapshot=91){
 # A separate immutable directory models the actual Maintenance runtime.
 # Its synthetic qualification is fixture-only, never a distributable release.
 [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'PACKAGE_MANIFEST.json'})
 [Array]::Sort($paths,[StringComparer]::Ordinal);$files=@();$rows=@()
 foreach($path in $paths){$id=Identity (Join-Path $Root $path);$files+=@(@{path=$path;identity=$id});$rows+=($path+'='+$id)}
 $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n")+"`n")))
 SaveJson (Join-Path $Root 'PACKAGE_MANIFEST.json') @{schemaVersion=2;frameworkVersion='2.0.0';provisional=[bool]$Candidate;canonical=$canonical;files=$files;distributionId=$(if($Candidate){'2.0.0-snapshot.'+$Snapshot}else{'2.0.0-release'})}
}
function CloneFixture($Value){return $Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -AsHashtable}
function Invoke-NestedSelectorAdoptionTests([string]$Runtime) {
 $root=Join-Path $temp 'nested-selector-project';$versionRoot=Join-Path $Runtime 'framework/versions/2.0.0'
 foreach($name in @('ProjectAdoptionState.psm1','ProjectAdoptionProjection.psm1','ProjectAdoptionTransaction.psm1','ProjectCorrectionLifecycle.psm1')){Import-Module (Join-Path $Runtime ('scripts/'+$name)) -Force}
 $probe=Join-Path $temp 'nested-selector-reader-probe.ps1'
 SaveText $probe @'
param([string]$Runtime,[string]$Root,[string]$Carrier,[ValidateSet('UNCONVERTED','READER')][string]$Mode,[switch]$ShadowReader)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$versionRoot=Join-Path $Runtime 'framework/versions/2.0.0'
if(Get-Command Read-AiwCurrentObject -ErrorAction SilentlyContinue){throw 'AMBIENT_FORMAT_READER_PRESENT'}
$context=[pscustomobject]@{ProjectId='selector-fixture';TargetProcessContractVersion='2.0.0'}
if($Mode-ceq'UNCONVERTED'){
 $module=@(Import-Module (Join-Path $versionRoot 'scripts/ObjectFormats.psm1') -PassThru -ErrorAction Stop)[0]
 $bytes=[IO.File]::ReadAllBytes($Carrier);$identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
 $reason='';try{& $module.ExportedCommands['Read-AiwCurrentObject'] -ObjectType PROJECT_CORRECTIONS -Locator $Carrier -ExpectedIdentity $identity -Context $context|Out-Null}catch{$reason=$_.Exception.Message}
 [ordered]@{reason=$reason}|ConvertTo-Json -Compress;return
}
Import-Module (Join-Path $Runtime 'scripts/ProjectAdoptionProjection.psm1') -ErrorAction Stop
if(Get-Command Read-AiwCurrentObject -ErrorAction SilentlyContinue){throw 'PROJECTION_EXPOSED_AMBIENT_READER'}
if($ShadowReader){function global:Read-AiwCurrentObject {throw 'UNRELATED_FORMAT_READER_USED'}}
$read=Read-AiwAdoptionCorrectionsFormatObject -Root $Root -Projection $null -Context $context -TargetVersionRoot $versionRoot
[ordered]@{schemaVersion=$read.Value.schemaVersion;count=@($read.Value.corrections).Count;oldEnums=@($read.Value.corrections|Where-Object{$_.selectors.roles-ccontains'DOMAIN_OWNER'-or$_.selectors.actionKinds-ccontains'OWNER_ACCEPT'-or$_.selectors.deterministicTriggers.actionKinds-ccontains'OWNER_ACCEPT'}).Count}|ConvertTo-Json -Compress
'@
 SaveJson (Join-Path $root '.ai-workspace/project.json') @{schemaVersion=5;id='selector-fixture';displayName='Selector fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=@{};processPolicy=@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}
 SaveJson (Join-Path $root '.ai-workspace/process-policy.json') @{schemaVersion=1;contractVersion='1.16.0';projectId='selector-fixture';rules=@()}
 SaveText (Join-Path $root 'AGENTS.md') 'Preserve user text and literal OWNER_ACCEPT.'
 $records=@();$changes=@();$impact=@{stoppedObligations=@('fixture legacy obligation');independentObligations=@('user text and exact history');inFlightEffects=@();recovery='original adoption journal';semanticAssessment='no installed effects'}
 foreach($number in 1..14){
  $id='SELECTOR_N'+$number.ToString('00')
  $selectors=@{profiles=@('CRITICAL');roles=@('DOMAIN_OWNER');phases=@('IMPLEMENT');actionKinds=@('SOURCE_WRITE','OWNER_ACCEPT');resultKinds=@('IMPLEMENTATION_RESULT','OWNER_ACCEPTANCE');pathPrefixes=@('owned/');capabilities=@();semanticTerms=@('fixture');semanticMatch='TOKEN';deterministicTriggers=@{actionKinds=@('SOURCE_WRITE','OWNER_ACCEPT');resultKinds=@('IMPLEMENTATION_RESULT','OWNER_ACCEPTANCE')}}
  $record=@{correctionId=$id;introducedAgainstFramework='1.16.0';requirementReason='anonymous legacy selector';effectiveRule='Keep literal OWNER_ACCEPT in this rule text.';applicability='isolated migration';decisionLocator='fixture:source';selectors=$selectors;preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@();lifecycle=@{state='ACTIVE';installation='NOT_APPLICABLE';decisionLocator='fixture:source'}}
  $records+=@($record);$revision=CloneFixture $record;$revision.Remove('lifecycle')
  $revision.effectiveRule='Keep literal OWNER_ACCEPT, with a narrower source obligation.';$revision.selectors.actionKinds=@('SOURCE_WRITE');$revision.selectors.resultKinds=@('IMPLEMENTATION_RESULT');$revision.selectors.deterministicTriggers.actionKinds=@('SOURCE_WRITE');$revision.selectors.deterministicTriggers.resultKinds=@('IMPLEMENTATION_RESULT')
  $changes+=@(@{correctionId=$id;operation=$(if($number-eq14){'REVISE'}else{'UNINSTALL'});decisionLocator='fixture:adoption';record=$(if($number-eq14){$revision}else{'NOT_APPLICABLE'});installation='NOT_APPLICABLE';installationRelativePath='NOT_APPLICABLE';historyRelativePath=('.ai-workspace/upgrade-recovery/corrections/'+$id+'/adoption/history.json');effectPaths=@();impact=$impact})
 }
 $carrierPath=Join-Path $root '.ai-workspace/corrections.json';SaveJson $carrierPath @{schemaVersion=2;contractVersion='1.16.0';projectId='selector-fixture';corrections=$records}
 $planPath=Join-Path $root '.ai-workspace/runtime/native-group-plan.json';SaveJson $planPath @{schemaVersion=2;expectedCorrectionsIdentity=(Identity $carrierPath);changes=$changes}
 $plan=Get-Content $planPath -Raw|ConvertFrom-Json -Depth 100;$scope=@(Get-AiwCorrectionAdoptionScope $root $plan @())
 $before=Snapshot $root;$group=New-AiwCorrectionAdoptionGroupProjection $root $plan @() $scope @()
 $native=@($group.projection.objects|Where-Object path -CEQ '.ai-workspace/corrections.json')[0]
 $raw=Join-Path $temp 'native-legacy-group.json';[IO.File]::WriteAllBytes($raw,[Convert]::FromBase64String($native.newBase64))
 $context=[pscustomobject]@{ProjectId='selector-fixture';TargetProcessContractVersion='2.0.0'}
 $unconverted=RunTool $probe @{Runtime=$Runtime;Carrier=$raw;Mode='UNCONVERTED'}
 Check ($unconverted.reason-ceq'FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CORRECTIONS') 'native-nested-old-enums-reproduce-unconverted-target-validation-blocker'
 $independent=RunTool $probe @{Runtime=$Runtime;Root=$root;Mode='READER'}
 Check ($independent.schemaVersion-eq3-and$independent.count-eq14-and$independent.oldEnums-eq0-and(Test-SnapshotPreserved $root $before)) 'independent-reader-loads-exact-target-without-ambient-import-and-keeps-preimages'
 $shadowed=RunTool $probe @{Runtime=$Runtime;Root=$root;Mode='READER';ShadowReader=$true}
 Check ($shadowed.schemaVersion-eq3-and$shadowed.count-eq14-and$shadowed.oldEnums-eq0-and(Test-SnapshotPreserved $root $before)) 'independent-reader-ignores-unrelated-same-name-ambient-command'
 $prepared=New-AiwBootstrapFormatProjection -RepositoryRoot $root -TargetVersionRoot $versionRoot -SourceProjection $group.projection
 $converted=$prepared.corrections
 Check ($converted.schemaVersion-eq3-and@($converted.corrections).Count-eq14-and@($converted.corrections|Where-Object{$_.lifecycle.state-ceq'UNINSTALLED'}).Count-eq13) 'native-group-preparation-retains-thirteen-exits-and-one-revision'
 Check (@($converted.corrections|Where-Object{$_.selectors.roles-ccontains'DOMAIN_OWNER'-or$_.selectors.actionKinds-ccontains'OWNER_ACCEPT'-or$_.selectors.resultKinds-ccontains'OWNER_ACCEPTANCE'-or$_.selectors.deterministicTriggers.actionKinds-ccontains'OWNER_ACCEPT'-or$_.selectors.deterministicTriggers.resultKinds-ccontains'OWNER_ACCEPTANCE'}).Count-eq0) 'native-group-preparation-converts-top-level-and-nested-selector-vocabulary-before-validation'
 $last=@($converted.corrections|Where-Object correctionId -CEQ SELECTOR_N14)[0]
 Check ($last.lifecycle.state-ceq'ACTIVE'-and($last.selectors.actionKinds-join'|')-ceq'SOURCE_WRITE'-and($last.selectors.pathPrefixes-join'|')-ceq'owned/') 'native-group-preparation-preserves-narrow-revision-scope'
 Check ((Test-SnapshotPreserved $root $before)) 'native-group-and-format-preparation-keep-all-live-preimages-and-history-zero-write'
 Check (@($converted.corrections|Where-Object{$_.lifecycle.installation-cne'NOT_APPLICABLE'-or-not$_.effectiveRule.Contains('literal OWNER_ACCEPT')}).Count-eq0) 'native-selector-conversion-preserves-installation-references-and-rule-text'
 $history=@($group.projection.objects|Where-Object{$_.path.EndsWith('/history.json')})
 Check ($history.Count-eq14-and@($history|Where-Object{($utf8.GetString([Convert]::FromBase64String($_.newBase64))|ConvertFrom-Json -Depth 100).priorRecord.selectors.deterministicTriggers.actionKinds-cnotcontains'OWNER_ACCEPT'}).Count-eq0) 'native-history-keeps-original-nested-vocabulary-in-all-fourteen-prior-records'
 $prepared.project.frameworkVersion='2.0.0';$targets=@([pscustomobject]@{path='.ai-workspace/project.json';text=($prepared.project|ConvertTo-Json -Depth 100 -Compress)})+@($prepared.targets|Where-Object path -CNE '.ai-workspace/project.json')+@($group.projection.objects|Where-Object path -CNE '.ai-workspace/corrections.json'|ForEach-Object{[pscustomobject]@{path=$_.path;bytes=[Convert]::FromBase64String($_.newBase64)}})
 $projection=New-AiwProjectProjection $root $targets
 $evidence=[pscustomobject]@{schemaVersion=1;planIdentity=(Identity $planPath);planBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($planPath));scope=$scope;sourceReferences=@($group.sourceReferences)}
 $authority=[pscustomobject]@{exactScope=@($projection.objects.path);forbiddenScope=@()}
 $module=@(Get-Module|Where-Object{$_.Path-ceq(Join-Path $Runtime 'scripts/ProjectAdoptionTransaction.psm1')})[0]
 $replayed=& $module {param($e,$root,$p,$c) Assert-AiwCorrectionAdoptionEvidence $e $root $p $c} $evidence $root $projection $authority
 Check (@($replayed).Count-eq$scope.Count-and(Test-SnapshotPreserved $root $before)) 'saved-native-group-candidate-replay-validates-same-conversion-with-zero-live-write'
 $tampered=$projection|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $entry=@($tampered.objects|Where-Object path -CEQ '.ai-workspace/corrections.json')[0];$value=$utf8.GetString([Convert]::FromBase64String($entry.newBase64))|ConvertFrom-Json -Depth 100
 $value.corrections[0].effectiveRule='Unrelated replacement';$entry.newBase64=[Convert]::ToBase64String($utf8.GetBytes(($value|ConvertTo-Json -Depth 100 -Compress)+"`n"));$entry.newIdentity=Get-AiwByteIdentity ([Convert]::FromBase64String($entry.newBase64))
 $reason='';try{& $module {param($e,$root,$p,$c) Assert-AiwCorrectionAdoptionEvidence $e $root $p $c} $evidence $root $tampered $authority|Out-Null}catch{$reason=$_.Exception.Message}
 Check ($reason-like'*CORRECTION_FINAL_CARRIER*'-and(Test-SnapshotPreserved $root $before)) 'saved-native-group-replay-rejects-unrelated-carrier-without-dropping-history-or-bypassing-schema'
 $currentBytes=@($prepared.targets|Where-Object path -CEQ '.ai-workspace/corrections.json')[0].bytes;[IO.File]::WriteAllBytes($carrierPath,$currentBytes)
 $current=Read-AiwAdoptionCorrectionsFormatObject -Root $root -Projection $null -Context $context -TargetVersionRoot $versionRoot
 Check ($current.Status-ceq'CURRENT'-and$current.Segments.Count-eq0-and$current.CurrentIdentity-ceq(Identity $carrierPath)) 'healthy-schema3-corrections-keep-original-bytes-without-new-adapter-segment'
}
function Invoke-DeclaredRegisteredOriginTests([string]$SourceRuntime) {
 $source=[IO.Path]::GetFullPath($SourceRuntime)
 if($PreparationRecheck){$copy=Join-Path $temp 'preparation-original-runtime';Copy-Item -LiteralPath $source -Destination $copy -Recurse;$source=$copy}
 Import-Module (Join-Path $workspace 'scripts/ProjectAdoptionState.psm1') -ErrorAction Stop
 $binding=Get-AiwDistributionBinding $source '2.0.0' -Required
 if($binding.distributionId-cnotin@('2.0.0-snapshot.16','2.0.0-snapshot.17')){throw 'DECLARED_REGISTER_ORIGIN_RUNTIME_REQUIRED'}
 $consumer=Join-Path $temp 'aiw-declared-register-consumer';$null=[IO.Directory]::CreateDirectory($consumer)
 if($RegisteredMaintenance){
  $consumer=Join-Path $temp 'maintenance/control';$target=Join-Path $temp 'maintenance/framework-target'
  foreach($directory in @($consumer,$target)){$null=[IO.Directory]::CreateDirectory($directory);& $git -C $directory init -q;if($LASTEXITCODE-ne0){throw 'ORIGINAL_SOURCE_MAINTENANCE_FIXTURE_GIT'}}
 }
 $initial=Join-Path $temp 'DECLARED-REGISTER-001.md';$taskRelative='.ai-workspace/tasks/active/DECLARED-REGISTER-001.md'
 SaveText $initial @'
# DECLARED-REGISTER-001 — Real old fixed registration
- Task schema: 2.0.0
- Status: ACTIVE
- Profile: CRITICAL; reason=Actual unchanged fixed source registration and upgrade.
- Owner: owner-fixture
- Work route: actor=owner-fixture; role=CONTROLLER; phase=IMPLEMENT
- Phase gate: FALSE
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=DECLARED_REGISTER; expected_paths=[.ai-workspace/PROJECT.md]; actual_paths=[.ai-workspace/PROJECT.md]
- Writer / reviewer / authorization: isolated fixture / NONE / separate exact actions
- Git / push / external: DEFERRED
## Current
- Goal: Register under the declared old fixed package, then upgrade and recover through the original process.
- Acceptance: Actual REGISTER origin, original admission, Apply, rollback, unchanged old resolver and re-upgrade.
'@
 $register=@{ProjectId='registration-fixture';DisplayName='Declared source registration';RepositoryPath=$consumer;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$source;LocalCandidatePilot=$true;InitialTaskPath=$initial;ExpectedInitialTaskIdentity=(Identity $initial);InitialTaskRelativePath=$taskRelative;Apply=$true}
 if($RegisteredMaintenance){$register.ControlPlaneLayout='framework-maintenance-sibling';$register.FrameworkTargetRepositoryId='fixture-framework';$register.FrameworkTargetSiblingDirectory='framework-target'}
 $created=RunTool (Join-Path $source 'scripts/register-project.ps1') $register
 $statePath=Join-Path $consumer '.ai-workspace/upgrade-recovery/2.0.0/state.json';$originPath=Join-Path $consumer '.ai-workspace/runtime/project-adoption/register/state.json'
 $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -Depth 100
 $origin=Get-Content -LiteralPath $originPath -Raw|ConvertFrom-Json -Depth 100
 Check (@($created)[-1].status-ceq'CREATED'-and$state.schemaVersion-eq7-and$state.originKind-ceq'REGISTER'-and$origin.state-ceq'COMPLETE'-and$origin.transactionComplete-and$state.distributionBinding.runtimeRoot-ceq$source) 'declared-fixed-runtime-real-register-origin'
 $chain=Get-Content -LiteralPath (Join-Path $source 'framework/versions/2.0.0/TOOLCHAIN.json') -Raw|ConvertFrom-Json
 $template=[ordered]@{schemaVersion=$(if($chain.contractVersion-ceq'4'){5}else{4});mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$consumer;frameworkRoot=$source;taskPath=(Join-Path $consumer $taskRelative);expectedProjectConfigIdentity=(Identity (Join-Path $consumer '.ai-workspace/project.json'));expectedCorrectionsIdentity=(Identity (Join-Path $consumer '.ai-workspace/corrections.json'));expectedTaskIdentity=(Identity (Join-Path $consumer $taskRelative));observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private');protectedPaths=@('private');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=[ordered]@{schemaVersion=2;objective='Plan the explicit upgrade of a genuinely registered fixed source';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:planning')};deliverableType=@{state='KNOWN';values=@('aiw:plan')};stage=@{state='KNOWN';values=@('aiw:planning')}}}}
 if($chain.contractVersion-ceq'4'){$template.ruleLoad=@{mode='FULL'}}
 $watch=[Diagnostics.Stopwatch]::StartNew()
 Invoke-RegisteredRefreshTests $consumer $source $template (Identity $originPath) $workspace
 $watch.Stop();Write-Output ('B1_TIMING|phase=REGISTER_ORIGIN_UPGRADE_WITH_ROLLBACK_AND_REUPGRADE|wallSeconds='+$watch.Elapsed.TotalSeconds)
 Check ((Get-AiwDistributionBinding $source '2.0.0' -Required).contentIdentity-ceq$binding.contentIdentity) 'declared-old-runtime-remains-original-bytes'
}

function Invoke-SamePinAgentsSourceTests([switch]$StopIncomplete) {
 $source=$workspace;$consumer=Join-Path $temp $(if($StopIncomplete){'aiw-same-pin-stop-consumer'}else{'aiw-same-pin-consumer'});$null=[IO.Directory]::CreateDirectory($consumer)
 # Existing fixture qualification seals only this isolated mechanism runtime.
 SealFixture (Join-Path $source 'framework/versions/2.0.0') -Candidate
 SealRuntimeFixture $source -Candidate
 $initial=Join-Path $temp 'SAME-PIN-REGISTER-001.md';$initialRelative='.ai-workspace/tasks/active/SAME-PIN-REGISTER-001.md'
 SaveText $initial @'
# SAME-PIN-REGISTER-001 — Isolated same-pin original completion
- Task schema: 2.0.0
- Status: ACTIVE
- Profile: CRITICAL; reason=Actual finite registration and pending SOURCE completion fixture.
- Owner: owner-fixture
- Work route: actor=owner-fixture; role=CONTROLLER; phase=IMPLEMENT
- Phase gate: FALSE
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=SAME_PIN; expected_paths=[.ai-workspace/PROJECT.md]; actual_paths=[.ai-workspace/PROJECT.md]
- Writer / reviewer / authorization: isolated mechanism fixture / NONE / exact actions
- Git / push / external: DEFERRED
## Current
- Goal: Register this isolated project and verify original SOURCE completion after an AGENTS-only change.
- Acceptance: Original actual admission retained, original ordinary refusal retained, explicit bounded completion writes no product or authority bytes.
'@
 $registered=RunTool (Join-Path $source 'scripts/register-project.ps1') @{ProjectId='registration-fixture';DisplayName='Same-pin completion fixture';RepositoryPath=$consumer;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$source;LocalCandidatePilot=$true;InitialTaskPath=$initial;ExpectedInitialTaskIdentity=(Identity $initial);InitialTaskRelativePath=$initialRelative;Apply=$true}
 Check (@($registered)[-1].status-ceq'CREATED') 'same-pin-original-real-isolated-registration'
 # A real selected adopted source and its dependency precede original SOURCE
 # admission. Neither is a candidate, control carrier or canonical evidence.
 $policyPath=Join-Path $consumer '.ai-workspace/process-policy.json'
 $policy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
 $configPath=Join-Path $consumer '.ai-workspace/project.json';$sourceConfig=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
 $sourceConfig.sourceBindings+=@([pscustomobject]@{id='same-pin-rules';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='FILE';locator='rules/completion-root.md'},[pscustomobject]@{kind='FILE';locator='rules/completion-dependency.md'});decisionLocator='fixture:original-source'})
 SaveJson $configPath $sourceConfig
 $completionContent=@(Import-Module (Join-Path $source 'framework/versions/2.0.0/scripts/ContentSources.psm1') -PassThru)[0]
 $sourceDocuments=@(foreach($entry in @(@{id='ROOT';path='rules/completion-root.md';dependencies=@('DEPENDENCY')},@{id='DEPENDENCY';path='rules/completion-dependency.md';dependencies=@()})){
  $path=Join-Path $consumer $entry.path;SaveText $path ('Complete selected fixture source '+$entry.id+'.')
  $document=[pscustomobject]@{sourceId=$entry.id;bindingId='same-pin-rules';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=$entry.path;identity=(Identity $path);mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=$entry.dependencies}
  $document.revision=& $completionContent.ExportedCommands['Get-AiwContentRevision'] ([pscustomobject]@{documents=@($document)}) $sourceConfig.sourceBindings
  $document
 })
 $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='same-pin-rules';itemId='same-pin-completion';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='ROOT';documents=$sourceDocuments}
 $descriptor.revision=& $completionContent.ExportedCommands['Get-AiwContentRevision'] $descriptor $sourceConfig.sourceBindings
 $descriptor.itemIdentity=& $completionContent.ExportedCommands['Get-AiwContentItemIdentity'] $descriptor
 $policy.rules+=@{ruleId='SAME_PIN_SELECTED_SOURCE';requirementReason='Original completion must protect actual adopted source reads.';decisionLocator='fixture:original-source';source=$descriptor;selectors=@{profiles=@();roles=@();phases=@();actionKinds=@('SOURCE_WRITE');resultKinds=@('IMPLEMENTATION_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
 SaveJson $policyPath $policy
 $template=[ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$consumer;frameworkRoot=$source;taskPath=(Join-Path $consumer $initialRelative);expectedProjectConfigIdentity=(Identity (Join-Path $consumer '.ai-workspace/project.json'));expectedCorrectionsIdentity=(Identity (Join-Path $consumer '.ai-workspace/corrections.json'));expectedTaskIdentity=(Identity (Join-Path $consumer $initialRelative));observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private');protectedPaths=@('private');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;ruleLoad=@{mode='FULL'};intentEnvelope=[ordered]@{schemaVersion=2;objective='Prepare the isolated pending SOURCE';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:planning')};deliverableType=@{state='KNOWN';values=@('aiw:plan')};stage=@{state='KNOWN';values=@('aiw:planning')}}}}
 $agentsPath=Join-Path $consumer 'AGENTS.md';$oldAgents=[IO.File]::ReadAllBytes($agentsPath)
 $pending=$null
 foreach($result in @(New-B1PendingSourceAction $consumer $source $template -StopIncomplete:$StopIncomplete)){
  if($result-is[Collections.IDictionary]){if($null-ne$pending){throw 'PENDING_SOURCE_FIXTURE_RESULT_COUNT'};$pending=$result}else{Write-Output $result}
 }
 if($null-eq$pending){throw 'PENDING_SOURCE_FIXTURE_RESULT_REQUIRED'}
 $sourceReceipt=Get-Content -LiteralPath (Join-Path $pending.evidence 'source-compact.json') -Raw|ConvertFrom-Json -Depth 100
 Check ('project:registration-fixture:SAME_PIN_SELECTED_SOURCE'-cin@($sourceReceipt.selectedObligations.requirementId)) 'same-pin-original-admission-actually-selects-adopted-source-and-dependency'
 $preimagePath=Join-Path $pending.evidence 'original-agents.txt';[IO.File]::WriteAllBytes($preimagePath,$oldAgents)
 SaveText $agentsPath (([IO.File]::ReadAllText($agentsPath))+"`n<!-- USER-DECISION:fixture -->`nThe original finite SOURCE may be completed with its unchanged candidate and original admission; no new write, external operation or adoption is allowed.")
 $decisionPath=Join-Path $pending.evidence 'current-human-decision.txt';SaveText $decisionPath 'Isolated instruction-bound original human decision: complete only LEGACY-SOURCE-001 under the retained original SOURCE admission, current complete AGENTS and unchanged candidate. This fixture is not real project authorization.'
 $ordinary=InvokeTool $pending.resolver @{InputPath=$pending.final;AsJson=$true}
 Check ($ordinary.code-ne0-and$ordinary.text-cmatch'SOURCE_(DECLARATION|COMPOSITION)_DRIFT|projectAgentsIdentity') 'same-pin-ordinary-original-finalize-actually-refuses-agents-drift'
 SaveJson (Join-Path $pending.evidence 'ordinary-finalize-failed.json') @{exitCode=$ordinary.code;output=$ordinary.text;inputIdentity=(Identity $pending.final)}
 $common=@{ProjectId='registration-fixture';ToVersion='2.0.0';RepositoryPath=$consumer;ActorRouteActor='owner-fixture';AdoptionProcessMode='FINALIZE_OUTPUT';CurrentProcessInputPath=$pending.final;ExpectedCurrentProcessInputIdentity=(Identity $pending.final);AdmitInputPath=$pending.admitInput;ExpectedAdmitInputIdentity=(Identity $pending.admitInput);AdmitResultPath=$pending.admitResult;ExpectedAdmitResultIdentity=(Identity $pending.admitResult);CompleteOriginalSourceAfterAgentsChange=$true;OriginalAgentsPreimagePath=$preimagePath;ExpectedOriginalAgentsPreimageIdentity=(Identity $preimagePath);ExpectedCurrentAgentsIdentity=(Identity $agentsPath);CurrentCompletionDecisionPath=$decisionPath;ExpectedCurrentCompletionDecisionIdentity=(Identity $decisionPath);CurrentCompletionPermission='CURRENT_AND_COVERED';OriginalSourceForbiddenPath=@('private')}
 if($StopIncomplete){$common.ActorRouteActor=$pending.actor;Test-SamePinStoppedSource $consumer $pending $common $source $agentsPath;return}
 $before=Snapshot $consumer
 $completed=InvokeTool (Join-Path $source 'scripts/upgrade-project.ps1') $common
 Check ($completed.code-eq0-and$completed.value.status-ceq'PASS'-and$completed.value.reason-ceq'ORIGINAL_SOURCE_FINALIZED_AFTER_SAME_PIN_AGENTS_CHANGE'-and$completed.value.successorState-ceq'NONE'-and$completed.value.evidenceGrade-ceq'INSTRUCTION_BOUND') ('same-pin-real-original-completion|'+$completed.text)
 $after=Snapshot $consumer
 if($env:AIW_TEST_RAW_DIRECTORY){SaveJson (Join-Path $env:AIW_TEST_RAW_DIRECTORY 'same-pin-completion-snapshots.json') @{root=$consumer;before=$before;after=$after;equal=($after-ceq$before)}}
 Check ($after-ceq$before) 'same-pin-completion-zero-product-control-or-original-evidence-writes'
 $again=InvokeTool (Join-Path $source 'scripts/upgrade-project.ps1') $common
 Check ($again.code-eq0-and$again.value.decisionIdentity-ceq$completed.value.decisionIdentity-and(Test-SnapshotPreserved $consumer $before)) 'same-pin-repeat-only-revalidates-original-zero-write-result'
 Test-SamePinAdoptedSourceProtection $consumer $common $source $before
 foreach($case in @('missing-preimage','wrong-preimage','missing-admission','withdrawn','unknown','missing-current-decision','stale-current-agents','mixed-adoption')){
  $bad=@{};foreach($key in $common.Keys){$bad[$key]=$common[$key]}
  switch($case){
   missing-preimage {$bad.OriginalAgentsPreimagePath='';$bad.ExpectedOriginalAgentsPreimageIdentity='';$reason='ORIGINAL_SOURCE_AGENTS_PREIMAGE_REQUIRED'}
   wrong-preimage {$bad.ExpectedOriginalAgentsPreimageIdentity='1|'+('A'*64);$reason='ORIGINAL_SOURCE_AGENTS_PREIMAGE_DRIFT'}
   missing-admission {$bad.AdmitInputPath='';$bad.ExpectedAdmitInputIdentity='';$reason='ORIGINAL_SOURCE_ADMISSION_REQUIRED'}
   withdrawn {$bad.CurrentCompletionPermission='WITHDRAWN';$reason='ORIGINAL_SOURCE_COMPLETION_PERMISSION_WITHDRAWN'}
   unknown {$bad.CurrentCompletionPermission='UNKNOWN';$reason='ORIGINAL_SOURCE_COMPLETION_PERMISSION_UNKNOWN'}
   missing-current-decision {$bad.CurrentCompletionDecisionPath='';$bad.ExpectedCurrentCompletionDecisionIdentity='';$reason='ORIGINAL_SOURCE_CURRENT_COMPLETION_DECISION_REQUIRED'}
   stale-current-agents {$bad.ExpectedCurrentAgentsIdentity='1|'+('B'*64);$reason='ORIGINAL_SOURCE_CURRENT_AGENTS_DRIFT'}
   mixed-adoption {$bad.AdoptionFinalizeResultPath=$pending.admitResult;$reason='ORIGINAL_SOURCE_COMPLETION_MODE_CONFLICT'}
  }
  $rejected=InvokeTool (Join-Path $source 'scripts/upgrade-project.ps1') $bad
  Check ($rejected.code-ne0-and$rejected.text.Contains($reason)-and(Test-SnapshotPreserved $consumer $before)) ('same-pin-refuses-'+$case+'|'+$rejected.text)
 }
 foreach($relative in @('.ai-workspace/process-policy.json','.ai-workspace/controller.json','.ai-workspace/tasks/active/LEGACY-SOURCE-001.md')){
  $path=Join-Path $consumer $relative;$saved=[IO.File]::ReadAllBytes($path)
  try{
   [IO.File]::AppendAllText($path,"`n",$utf8)
   $rejected=InvokeTool (Join-Path $source 'scripts/upgrade-project.ps1') $common
   Check ($rejected.code-ne0-and$rejected.text-cmatch'ORIGINAL_SOURCE_CURRENT_(BINDING|AUTHORITY)_DRIFT') ('same-pin-refuses-unrelated-authority-source-drift-'+$relative+'|'+$rejected.text)
  }finally{[IO.File]::WriteAllBytes($path,$saved)}
 }
 $candidate=Join-Path $consumer $pending.candidateRelativePath;$saved=[IO.File]::ReadAllBytes($candidate)
 try{
  SaveText $candidate 'Unrelated later candidate must not be accepted by the original completion.'
  $rejected=InvokeTool (Join-Path $source 'scripts/upgrade-project.ps1') $common
  Check ($rejected.code-ne0-and$rejected.text-cmatch'EVIDENCE_.*(DRIFT|IDENTITY)|RESULT_POSTIMAGE') ('same-pin-refuses-real-candidate-drift|'+$rejected.text)
 }finally{[IO.File]::WriteAllBytes($candidate,$saved)}
 $bad=@{};foreach($key in $common.Keys){$bad[$key]=$common[$key]};$bad.OriginalSourceProtectedPath=@($candidate)
 $rejected=InvokeTool (Join-Path $source 'scripts/upgrade-project.ps1') $bad
 Check ($rejected.code-ne0-and$rejected.text-cmatch'ORIGINAL_SOURCE_PROTECTED_PATH|EVIDENCE_PATH_FORBIDDEN'-and(Test-SnapshotPreserved $consumer $before)) 'same-pin-current-protection-refuses-original-candidate-before-read'
 # No completed adoption or new SOURCE admission was created in this branch.
 Check (-not(Test-Path -LiteralPath (Join-Path $consumer '.ai-workspace/runtime/project-adoption/upgrade/state.json'))-and-not(Test-Path -LiteralPath (Join-Path $consumer '.ai-workspace/runtime/project-adoption/refresh/state.json'))-and(Test-SnapshotPreserved $consumer $before)) 'same-pin-no-fake-adoption-no-original-rewrite'
 Write-Output 'SAME_PIN_AGENTS_SOURCE_TESTS_PASS|scope=ACTUAL_ORIGINAL_ADMISSION_AND_ZERO_WRITE_COMPLETION|ceiling=ISOLATED_INSTRUCTION_BOUND'
}

function Invoke-RootReadReuseTests {
 $module=@(Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionState.psm1') -PassThru -ErrorAction Stop)[0]
 $root=Join-Path $temp 'root-read-reuse';$null=[IO.Directory]::CreateDirectory($root);$path=Join-Path $root 'input.json'
 SaveText $path '{"items":[null,[],[1,2]],"value":{"text":"original"}}'
 $lease=& $module.ExportedCommands['Enter-AiwRootProjectSourceScope'] -ProjectRoot $root -Mode OBSERVE
 try {
  $first=& $module.ExportedCommands['Read-AiwProjectJson'] $path 'REUSE_TEST';$first.Value.value.text='caller mutation';$first.Value.items[2][0]=9
  $second=& $module.ExportedCommands['Read-AiwProjectJson'] $path 'REUSE_TEST'
  Check ($second.Value.value.text-ceq'original'-and$second.Value.items.Count-eq3-and$null-eq$second.Value.items[0]-and$second.Value.items[1].Count-eq0-and$second.Value.items[2][0]-eq1) 'root-read-reuse-preserves-null-empty-array-order-and-independent-values'
  SaveText $path '{"items":[null,[],[2,1]],"value":{"text":"changed"}}'
  $third=& $module.ExportedCommands['Read-AiwProjectJson'] $path 'REUSE_TEST'
  Check ($third.Identity-cne$second.Identity-and$third.Value.value.text-ceq'changed'-and$third.Value.items[2][0]-eq2) 'root-read-reuse-observes-current-bytes-and-real-array-order-change'
  SaveText $path '{"same":1,"same":2}'
  $reason='';try{$null=& $module.ExportedCommands['Read-AiwProjectJson'] $path 'REUSE_TEST'}catch{$reason=$_.Exception.Message}
  Check ($reason.StartsWith('REUSE_TEST_DUPLICATE_MEMBER')) 'root-read-reuse-never-accepts-duplicate-member-after-valid-read'
 }finally{& $module.ExportedCommands['Exit-AiwRootProjectSourceScope'] $lease}
 Check ($null-eq(& $module {$script:RootReadContext})) 'root-read-reuse-ends-with-native-call-scope'
}

function Test-SamePinStoppedSource([string]$Consumer,[hashtable]$Pending,[hashtable]$Common,[string]$Source,[string]$AgentsPath){
 $package=Get-Content -LiteralPath $Pending.packagePath -Raw|ConvertFrom-Json -Depth 100
 $original=Join-Path $Pending.evidence 'retained-original.bin';$originalIdentity=Identity $original
 $builder=Join-Path $Pending.evidence 'build-after-source-change.ps1'
 SaveText $builder @'
param([string]$Root,[string]$ExpectedAgentsIdentity)
$ErrorActionPreference='Stop'
$bytes=[IO.File]::ReadAllBytes((Join-Path $Root 'AGENTS.md'))
$actual=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
if($actual-cne$ExpectedAgentsIdentity){throw 'FIXTURE_HUMAN_SOURCE_DRIFT'}
[IO.File]::WriteAllText((Join-Path $Root 'product/pending-image.bin'),'Unexpected write: this branch must not execute.')
[IO.File]::WriteAllText((Join-Path $Root 'product/pending-input.json'),'{}')
'@
 $builderArgs=@('-NoProfile','-NonInteractive','-File',$builder,'-Root',$Consumer,'-ExpectedAgentsIdentity',$Common.ExpectedOriginalAgentsPreimageIdentity)
 $build=Invoke-AiwTestProcess $pwsh $builderArgs -GroupId 'same-pin-stopped-source-builder'
 Check ($build.Code-ne0-and($build.Output-join "`n").Contains('FIXTURE_HUMAN_SOURCE_DRIFT')-and@($package.exactPaths|Where-Object{Test-Path -LiteralPath (Join-Path $Consumer $_)}).Count-eq0) 'same-pin-stop-actual-builder-refuses-before-both-formal-writes'
 $output=Join-Path $Pending.evidence 'builder-output.txt';SaveText $output ($build.Output-join "`n")
 $command=Join-Path $Pending.evidence 'builder-command.json';SaveJson $command @{command=([string]::Join(' ',@($pwsh)+$builderArgs));exitCode=$build.Code;output=@{path=$output;identity=(Identity $output)}}
 $objects=@($package.exactPaths|ForEach-Object{@{path=$_;identity='MISSING'}})
 $record=@{schemaVersion=1;taskId=$package.taskId;actor=$package.grantee;candidateObjects=$objects;requirementsRef=@{path=$Pending.packagePath;identity=(Identity $Pending.packagePath)};outcome='INCOMPLETE';checks=@(@{id='ACTUAL_BUILDER_STOP';method='COMMAND';outcome='INCOMPLETE';reason='Retained isolated producer output exists; actual builder refused changed human source before both formal writes. No generation/service or fee claim.';evidenceLocators=@(@{path=$command;identity=(Identity $command)})});evidenceLocators=@(@{path=$original;identity=$originalIdentity})}
 $selfPath=Join-Path $Pending.evidence 'incomplete-self.json';SaveJson $selfPath $record
 $boundary=Get-Content -LiteralPath $Pending.final -Raw|ConvertFrom-Json -Depth 100
 $boundary|Add-Member continuationDisposition STOP
 $boundary|Add-Member deliveryContext @{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient=$package.owner;observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
 $boundary.evidenceRefs=@(@{kind='SELF_CHECK';path=$selfPath;identity=(Identity $selfPath)})
 $prepare=Join-Path $Pending.evidence 'stop-finalize-prepare.json';SaveJson $prepare $boundary
 # A simulated host envelope tests receipt consumption only; no chat is sent.
 $hostResult=Join-Path $Pending.evidence 'simulated-host-send.json';SaveJson $hostResult @{isError=$false;content=@(@{type='text';text=(@{threadId=$package.owner}|ConvertTo-Json -Compress)})}
 $boundary.deliveryContext=@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient=$package.owner;observedRecipient=$package.owner;outcome='SUCCESS';evidence=($hostResult+'#'+(Identity $hostResult))}
 $observe=Join-Path $Pending.evidence 'stop-finalize-observe.json';SaveJson $observe $boundary
 $failedRecord=CloneFixture $record;$failedRecord.outcome='FAIL';$failedRecord.checks[0].outcome='FAIL'
 $failedSelf=Join-Path $Pending.evidence 'failed-self.json';SaveJson $failedSelf $failedRecord
 $failedBoundary=CloneFixture $boundary;$failedBoundary.evidenceRefs[0].path=$failedSelf;$failedBoundary.evidenceRefs[0].identity=Identity $failedSelf
 $failedInput=Join-Path $Pending.evidence 'stop-failed-finalize.json';SaveJson $failedInput $failedBoundary
 $variants=@{}
 foreach($case in @('no-stop','continue','no-self','missing-obligation')){
  $variant=CloneFixture $boundary
  switch($case){
   no-stop {$variant.Remove('continuationDisposition');if($variant.Contains('continuationDisposition')){throw 'STOP_NEGATIVE_FIXTURE_DISPOSITION_NOT_REMOVED'}}
   continue {$variant.continuationDisposition='CONTINUE'}
   no-self {$variant.evidenceRefs=@()}
   missing-obligation {$variant.resultReceipts=@($variant.resultReceipts|Where-Object{$_-cne'ZERO_BOUNDARY_VIOLATION'})}
  }
  $path=Join-Path $Pending.evidence ($case+'-finalize.json');SaveJson $path $variant;$variants[$case]=$path
 }
 $before=Snapshot $Consumer
 $call=$Common.Clone();$call.CurrentProcessInputPath=$prepare;$call.ExpectedCurrentProcessInputIdentity=Identity $prepare
 $prepared=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $call
 Check ($prepared.code-eq0-and$prepared.value.status-ceq'BLOCKED'-and$prepared.value.actionOutcome-ceq'INCOMPLETE'-and$prepared.value.successorState-ceq'NONE'-and-not$prepared.value.delivery.delivered-and$prepared.value.consumer.recipient-ceq$package.owner) ('same-pin-stop-prepare-does-not-invent-delivery-or-continuation|'+$prepared.text)
 $call.CurrentProcessInputPath=$observe;$call.ExpectedCurrentProcessInputIdentity=Identity $observe
 $stopped=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $call
 Check ($stopped.code-eq0-and$stopped.value.status-ceq'PASS'-and$stopped.value.actionOutcome-ceq'INCOMPLETE'-and$stopped.value.reason-ceq'ORIGINAL_SOURCE_STOPPED_AFTER_SAME_PIN_AGENTS_CHANGE'-and$stopped.value.successorState-ceq'STOPPED'-and$null-eq$stopped.value.PSObject.Properties['continuationReceipt']) ('same-pin-stop-original-batch-closes-incomplete-with-no-review-or-successor|'+$stopped.text)
 Check ((Identity $original)-ceq$originalIdentity-and@($package.exactPaths|Where-Object{Test-Path -LiteralPath (Join-Path $Consumer $_)}).Count-eq0-and(Test-SnapshotPreserved $Consumer $before)) 'same-pin-stop-preserves-original-both-missing-outputs-and-all-original-evidence'
 $repeat=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $call
 Check ($repeat.code-eq0-and$repeat.value.decisionIdentity-ceq$stopped.value.decisionIdentity-and(Test-SnapshotPreserved $Consumer $before)) 'same-pin-stop-repeat-only-revalidates-zero-write-terminal'
 Test-SamePinAdoptedSourceProtection $Consumer $call $Source $before
 $failedCall=$call.Clone();$failedCall.CurrentProcessInputPath=$failedInput;$failedCall.ExpectedCurrentProcessInputIdentity=Identity $failedInput
 $failed=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $failedCall
 Check ($failed.code-eq0-and$failed.value.actionOutcome-ceq'FAIL'-and$failed.value.successorState-ceq'STOPPED'-and(Test-SnapshotPreserved $Consumer $before)) 'same-pin-stop-preserves-real-failed-self-outcome'
 foreach($case in $variants.Keys){
  $bad=$call.Clone();$bad.CurrentProcessInputPath=$variants[$case];$bad.ExpectedCurrentProcessInputIdentity=Identity $variants[$case]
  $rejected=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $bad
  $reason=switch($case){no-stop {'ORIGINAL_SOURCE_UNSUPPORTED_PACKAGE'};continue {'ORIGINAL_SOURCE_STOP_DISPOSITION_REQUIRED'};no-self {'ORIGINAL_SOURCE_STOP_FAILED_SELF_REQUIRED'};missing-obligation {'ORIGINAL_SOURCE_OBLIGATIONS_INCOMPLETE'}}
  Check ($rejected.code-ne0-and$rejected.text.Contains($reason)-and(Test-SnapshotPreserved $Consumer $before)) ('same-pin-stop-refuses-'+$case+'|'+$rejected.text)
 }
 $bad=$call.Clone();$bad.CurrentCompletionPermission='WITHDRAWN';$rejected=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $bad
 Check ($rejected.code-ne0-and$rejected.text.Contains('ORIGINAL_SOURCE_COMPLETION_PERMISSION_WITHDRAWN')-and(Test-SnapshotPreserved $Consumer $before)) 'same-pin-stop-does-not-ignore-current-withdrawal'
 $bad=$call.Clone();$bad.OriginalSourceProtectedPath=@($selfPath)
 $locked=[IO.File]::Open($selfPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{$rejected=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $bad}finally{$locked.Dispose()}
 Check ($rejected.code-ne0-and$rejected.text-cmatch'ORIGINAL_SOURCE_PROTECTED_PATH|EVIDENCE_PATH_FORBIDDEN'-and(Test-SnapshotPreserved $Consumer $before)) ('same-pin-stop-current-protection-precedes-real-evidence-read|'+$rejected.text)
 if($env:AIW_TEST_RAW_DIRECTORY){SaveJson (Join-Path $env:AIW_TEST_RAW_DIRECTORY 'same-pin-stop-completion-snapshots.json') @{root=$Consumer;before=$before;after=(Snapshot $Consumer);original=$originalIdentity;outputs=$objects;terminal=$stopped.value}}
 Check (-not(Test-Path -LiteralPath (Join-Path $Consumer '.ai-workspace/runtime/project-adoption/upgrade/state.json'))-and-not(Test-Path -LiteralPath (Join-Path $Consumer '.ai-workspace/runtime/project-adoption/refresh/state.json'))) 'same-pin-stop-creates-no-adoption-or-source-replay'
}

function Test-SamePinAdoptedSourceProtection([string]$Consumer,[hashtable]$Common,[string]$Source,$Before){
 foreach($case in @(@{parameter='OriginalSourceForbiddenPath';relative='rules/completion-root.md';absolute=$true},@{parameter='OriginalSourceForbiddenPath';relative='rules/completion-dependency.md';absolute=$false},@{parameter='OriginalSourceProtectedPath';relative='rules/completion-root.md';absolute=$true},@{parameter='OriginalSourceProtectedPath';relative='rules/completion-dependency.md';absolute=$false})){
  $path=Join-Path $Consumer $case.relative;$bad=$Common.Clone()
  $bad[$case.parameter]=@($(if($case.absolute){$path}else{$case.relative}))
  $locked=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{$rejected=InvokeTool (Join-Path $Source 'scripts/upgrade-project.ps1') $bad}finally{$locked.Dispose()}
  Check ($rejected.code-ne0-and$rejected.text-cmatch'SOURCE_FILE_FORBIDDEN|SOURCE_DENIED\|FORBIDDEN_PATH'-and(Test-SnapshotPreserved $Consumer $Before)) ('same-pin-current-'+$case.parameter+'-'+$(if($case.absolute){'absolute'}else{'relative'})+'-precedes-selected-source-read|'+$rejected.text)
 }
}

function New-B1PendingSourceAction([string]$Consumer,[string]$SourceRuntime,$DiscoverTemplate,[switch]$StopIncomplete){
 $relative='product/pending-source.txt';$taskRelative='.ai-workspace/tasks/active/LEGACY-SOURCE-001.md';$task=Join-Path $Consumer $taskRelative
 $evidence=Join-Path $Consumer '.ai-workspace/runtime/LEGACY-SOURCE-001/owner-fixture'
 SaveText $task ([string]::Join([char]10,@('# LEGACY-SOURCE-001 — Finish the same SOURCE after adoption','- Task schema: 2.0.0','- Status: ACTIVE','- Profile: STANDARD','- Owner: owner-fixture','- Work route: actor=owner-fixture; role=EXECUTOR; phase=IMPLEMENT','- Phase gate: FALSE',('- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=['+$relative+']; actual_paths=['+$relative+']'),'- Writer / reviewer / authorization: isolated original SOURCE fixture','- Git / push / external: DEFERRED','## Current','- Goal: Keep this original SOURCE admission and candidate across a separate completed runtime adoption.','- Acceptance: O original failure retained, original evidence unchanged, explicit new qualified completion, real drift rejected.')))
 $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='LEGACY-SOURCE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='ORIGINAL_SINGLE_SOURCE';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Identity $task);actions=@('SOURCE_WRITE');exactPaths=@($relative);objectIdentities=@(@{path=$relative;identity='NEW'});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Identity (Join-Path $Consumer '.ai-workspace/project.json'))}
 if($StopIncomplete){
  $package.grantee='writer-fixture';$package.actions=@('SOURCE_WRITE','REVIEW_ROUTE');$package.continuationPlan=@('SOURCE_WRITE','REVIEW_ROUTE')
  $package.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $package.exactPaths=@('product/pending-image.bin','product/pending-input.json');$package.objectIdentities=@($package.exactPaths|ForEach-Object{@{path=$_;identity='NEW'}})
  SaveText $task ([IO.File]::ReadAllText($task).Replace('actor=owner-fixture','actor=writer-fixture').Replace($relative,([string]::Join(',',$package.exactPaths))))
  $package.taskIdentity=Identity $task
  $original=Join-Path $evidence 'retained-original.bin';SaveText $original 'Isolated retained producer output, not an image-generation or fee observation.'
  $package.repairReviewPlan=@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@('owner-fixture');reviewScope=@($package.objectIdentities)+@(@{path=[IO.Path]::GetRelativePath($Consumer,$original).Replace('\','/');identity=(Identity $original)})}
 }
 $objectRoot=$Consumer
 if($RegisteredMaintenance){
  SaveText $task ([IO.File]::ReadAllText($task).Replace('role=EXECUTOR','role=FRAMEWORK_MAINTAINER'))
  $package.taskIdentity=Identity $task;$package.schemaVersion=2;$package.repositoryId='fixture-framework'
  $package.invalidatesOn+=@('REPOSITORY_CHANGE')
  $objectRoot=Join-Path (Split-Path -Parent $Consumer) 'framework-target'
 }
 $packagePath=Join-Path $evidence 'source-package.json';SaveJson $packagePath $package
 $checker=@{ProjectConfigPath='.ai-workspace/project.json';ControllerControlPath='.ai-workspace/controller.json';PackagePath=$packagePath;ObservedActor='owner-fixture';ObservedTaskId='LEGACY-SOURCE-001';ObservedOwner='owner-fixture';ObservedAction=@('SOURCE_WRITE');ObservedPath=@($relative);ObservedIdentity=@($relative+'=NEW');ExpectedProjectConfigIdentity=$package.projectConfigIdentity;TaskPath=$taskRelative;ExpectedTaskIdentity=$package.taskIdentity}
 if($StopIncomplete){$checker.ObservedActor=$package.grantee;$checker.ObservedPath=$package.exactPaths;$checker.ObservedIdentity=@($package.exactPaths|ForEach-Object{$_+'=NEW'})}
 $checkerTool=Join-Path $SourceRuntime 'framework/versions/2.0.0/scripts/check-authorization.ps1'
 if($RegisteredMaintenance){$checkerTool=Join-Path $SourceRuntime 'scripts/check-framework-maintenance-authorization.ps1';$checker.ControlRepositoryPath=$Consumer;$checker.ObservedRepositoryId='fixture-framework'}
 $checked=InvokeTool $checkerTool $checker $Consumer
 if($checked.code-ne0){throw ('ORIGINAL_SOURCE_CHECKER_FAILED|'+$checked.text)};Check $true 'original-source-real-old-independent-checker'
 $input=CloneFixture $DiscoverTemplate;$input.taskPath=$task;$input.expectedTaskIdentity=$package.taskIdentity;$input.expectedProjectConfigIdentity=$package.projectConfigIdentity;$input.expectedCorrectionsIdentity=Identity (Join-Path $Consumer '.ai-workspace/corrections.json');$input.exactPaths=@($relative);$input.authorizationPackagePath=$packagePath;$input.expectedAuthorizationIdentity=Identity $packagePath;$input.userDecision='NOT_REQUIRED'
 if($StopIncomplete){$input.observedActor=$package.grantee;$input.exactPaths=$package.exactPaths}
 $input.intentEnvelope.objective='Write one isolated original SOURCE candidate and retain its original admission while a separate runtime adoption completes';$input.intentEnvelope.requestedActionKind='SOURCE_WRITE';$input.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$input.intentEnvelope.mutationHints=@('source');$input.intentEnvelope.facets.domain.values=@('aiw:software');$input.intentEnvelope.facets.workType.values=@('aiw:implementation');$input.intentEnvelope.facets.deliverableType.values=@('aiw:code');$input.intentEnvelope.facets.stage.values=@('aiw:implementation')
 $inputPath=Join-Path $evidence 'source-discover-input.json';SaveJson $inputPath $input
 $resolver=Join-Path $SourceRuntime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'
 if($RegisteredMaintenance){$resolver=Join-Path $SourceRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}
 $discovered=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($discovered.status-ceq'PASS') 'original-source-real-old-discover'
 $receipt=Join-Path $evidence 'source-compact.json';SaveJson $receipt $discovered.compactReceipt
 $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receipt;expectedDiscoverReceiptIdentity=(Identity $receipt);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 $admitInput=Join-Path $evidence 'source-admit-input.json';SaveJson $admitInput $boundary
 $admitted=RunTool $resolver @{InputPath=$admitInput;AsJson=$true};Check ($admitted.status-ceq'PASS') 'original-source-real-old-admit'
 $admitResult=Join-Path $evidence 'source-admit-result.json';SaveJson $admitResult $admitted
 if(-not$StopIncomplete){SaveText (Join-Path $objectRoot $relative) 'This is the candidate written under the unchanged original SOURCE admission.'}
 $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($discovered.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@(foreach($path in $package.exactPaths){'OBJECT_POSTIMAGE|'+$path+'|'+$(if($StopIncomplete){'MISSING'}else{Identity (Join-Path $objectRoot $path)})})
 $final=Join-Path $evidence 'source-finalize-input.json';SaveJson $final $boundary
 return @{candidateRelativePath=$relative;resolver=$resolver;final=$final;admitInput=$admitInput;admitResult=$admitResult;evidence=$evidence;actor=$package.grantee;packagePath=$packagePath;exactPaths=$package.exactPaths}
}

function Invoke-B1PublicOriginalSourceCases([string]$Runtime,[hashtable]$Original){
 $common=@{AdmitInputPath=$Original.AdmitInputPath;ExpectedAdmitInputIdentity=$Original.ExpectedAdmitInputIdentity;AdmitResultPath=$Original.AdmitResultPath;ExpectedAdmitResultIdentity=$Original.ExpectedAdmitResultIdentity;AdoptionFinalizeResultPath=$Original.AdoptionFinalizeResultPath;ExpectedAdoptionFinalizeResultIdentity=$Original.ExpectedAdoptionFinalizeResultIdentity;ExpectedAdoptionTransactionIdentity=$Original.ExpectedAdoptionTransactionIdentity;OriginalSourceForbiddenPath=@('private')}
 $up=$common.Clone();$up.ProjectId='registration-fixture';$up.ToVersion='2.0.0';$up.RepositoryPath=$Original.RepositoryRoot;$up.ActorRouteActor='owner-fixture';$up.AdoptionProcessMode='FINALIZE_OUTPUT';$up.CurrentProcessInputPath=$Original.InputPath;$up.ExpectedCurrentProcessInputIdentity=$Original.ExpectedInputIdentity;$up.AuthorizationPackagePath=$Original.AdoptionAuthorizationPackagePath;$up.ExpectedAuthorizationPackageIdentity=$Original.ExpectedAdoptionAuthorizationIdentity
 $entries=@(@{name='upgrader';tool=(Join-Path $Runtime 'scripts/upgrade-project.ps1');parameters=$up;protected=(Join-Path $Original.RepositoryRoot '.ai-workspace/project.json')})
 if($RegisteredMaintenance){
  $maint=$common.Clone();$maint.InputPath=$Original.InputPath;$maint.AsJson=$true;$maint.OriginalSourceRepositoryPath=$Original.RepositoryRoot;$maint.AdoptionAuthorizationPackagePath=$Original.AdoptionAuthorizationPackagePath;$maint.ExpectedAdoptionAuthorizationIdentity=$Original.ExpectedAdoptionAuthorizationIdentity
  $entries+=@{name='maintenance';tool=(Join-Path $Runtime 'scripts/resolve-framework-maintenance-process-requirements.ps1');parameters=$maint;protected=$Original.InputPath}
 }
 foreach($entry in $entries){
  $result=RunTool $entry.tool $entry.parameters
  Check ($result.reason-ceq'ORIGINAL_SOURCE_FINALIZED_AFTER_COMPLETED_ADOPTION'-and$result.successorState-ceq'NONE') ('original-source-public-'+$entry.name+'-actual-completion')
  $bad=$entry.parameters.Clone();$bad.OriginalSourceProtectedPath=@($entry.protected)
  $locked=[IO.File]::Open($entry.protected,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{$rejected=InvokeTool $entry.tool $bad}finally{$locked.Dispose()}
  Check ($rejected.code-ne0-and$rejected.text.Contains('ORIGINAL_SOURCE_PROTECTED_PATH')) ('original-source-public-'+$entry.name+'-protects-carrier-before-actual-read')
 }
 if($RegisteredMaintenance){
  $input=Get-Content -LiteralPath $Original.InputPath -Raw|ConvertFrom-Json
  $bad=$maint.Clone();$bad.OriginalSourceProtectedPath=@([IO.Path]::GetRelativePath($Original.RepositoryRoot,$input.discoverReceiptPath).Replace('\','/'))
  $locked=[IO.File]::Open($input.discoverReceiptPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{$rejected=InvokeTool $entries[1].tool $bad}finally{$locked.Dispose()}
  Check ($rejected.code-ne0-and$rejected.text.Contains('ORIGINAL_SOURCE_PROTECTED_PATH')) 'original-source-public-maintenance-relative-receipt-protection-before-read'
  $bad=$maint.Clone();$bad.OriginalSourceRepositoryPath=Split-Path -Parent $Original.RepositoryRoot
  $rejected=InvokeTool $entries[1].tool $bad
  Check ($rejected.code-ne0-and$rejected.text.Contains('ORIGINAL_SOURCE_REPOSITORY_BINDING')) 'original-source-public-maintenance-explicit-root-cannot-replace-receipt-authority'
 }
}

function Invoke-PreparationRecheckCases([string]$Consumer,[string]$Target,[string]$AdmitPath){
 Import-Module (Join-Path $Target 'scripts/ProjectAdoptionState.psm1') -Global -ErrorAction Stop
 Import-Module (Join-Path $Target 'scripts/ProjectAdoptionProjection.psm1') -Global -Force -ErrorAction Stop
 $modulePath=[IO.Path]::GetFullPath((Join-Path $Target 'scripts/ProjectAdoptionTransaction.psm1'))
 $module=@(Import-Module $modulePath -Global -Force -PassThru -ErrorAction Stop|Where-Object Path -CEQ $modulePath)[0]
 foreach($side in @('ORIGINAL','TARGET')){
  $before=Snapshot $Consumer
  $result=& $module {
   param($root,$admitPath,$side)
   $doc=Read-AiwAdoptionEvidence $admitPath (Get-AiwByteIdentity ([IO.File]::ReadAllBytes($admitPath))) 'TEST_ORIGINAL_ADMIT'
   $p=$doc.Value.adoptionPreparation;$a=$doc.Value.originalAdmissionInput
   $parameters=@{RepositoryRoot=$root;TargetRuntimeRoot=$p.targetDistribution.runtimeRoot;Projection=$p.projection;ObservedActor='owner-fixture';OriginalBoundary=$a;CorrectionAdoption=(Get-AiwCorrectionAdoptionEvidence $p)}
   $runtime=if($side-ceq'ORIGINAL'){$p.previousDistribution.runtimeRoot}else{$p.targetDistribution.runtimeRoot}
   $member=Join-Path $runtime 'README.md';$bytes=[IO.File]::ReadAllBytes($member);$manifest=Join-Path $runtime 'PACKAGE_MANIFEST.json';$manifestBefore=Get-AiwByteIdentity ([IO.File]::ReadAllBytes($manifest))
   $state=[pscustomobject]@{firstPrepared=$false;cacheReady=$false;secondReturned=$false;reason='';cleared=$false;nextEntered=$false;nextReason='';manifestUnchanged=$false}
   try{
    try{
     $null=Invoke-AiwAdoptionPreparedOperation @parameters -Body {
      param($first)
      $state.firstPrepared=$first.status-ceq'PREPARED'
      $state.cacheReady=$null-ne$script:AdoptionPreparationInvocation-and$script:AdoptionPreparationInvocation.ContainsKey('key')
      [IO.File]::WriteAllBytes($member,[byte[]]($bytes+10))
      $null=Get-AiwMajorAdoptionAdmission $doc $root -VerifyCurrent
      $state.secondReturned=$true
     }
    }catch{$state.reason=$_.Exception.Message}
    $state.cleared=$null-eq$script:AdoptionPreparationInvocation
    $state.manifestUnchanged=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($manifest)))-ceq$manifestBefore
    try{$null=Invoke-AiwAdoptionPreparedOperation @parameters -Body {$state.nextEntered=$true}}catch{$state.nextReason=$_.Exception.Message}
   }finally{[IO.File]::WriteAllBytes($member,$bytes)}
   $state
  } $Consumer $AdmitPath $side
  Write-Output ('PREPARATION_RECHECK_OBSERVED|side='+$side+'|first='+$result.firstPrepared+'|cache='+$result.cacheReady+'|second='+$result.secondReturned+'|reason='+$result.reason)
  Check ($result.firstPrepared-and$result.cacheReady-and-not$result.secondReturned-and$result.reason.Contains('DISTRIBUTION_CONTENT_DRIFT|README.md')-and$result.manifestUnchanged) ('preparation-reuse-'+$side+'-member-only-drift-rejected-at-verify-current')
  Check ((Test-SnapshotPreserved $Consumer $before)) ('preparation-reuse-'+$side+'-member-drift-keeps-entire-project-and-journal-zero-write')
  Check ($result.cleared-and-not$result.nextEntered-and$result.nextReason.Contains('DISTRIBUTION_CONTENT_DRIFT|README.md')) ('preparation-reuse-'+$side+'-exception-clears-scope-next-call-observes-runtime-again')
 }
 $before=Snapshot $Consumer
 $healthy=& $module {
  param($root,$admitPath)
  $doc=Read-AiwAdoptionEvidence $admitPath (Get-AiwByteIdentity ([IO.File]::ReadAllBytes($admitPath))) 'TEST_ORIGINAL_ADMIT';$p=$doc.Value.adoptionPreparation
  $state=[pscustomobject]@{reused=$false;cleared=$false}
  $null=Invoke-AiwAdoptionPreparedOperation -RepositoryRoot $root -TargetRuntimeRoot $p.targetDistribution.runtimeRoot -Projection $p.projection -ObservedActor 'owner-fixture' -OriginalBoundary $doc.Value.originalAdmissionInput -CorrectionAdoption (Get-AiwCorrectionAdoptionEvidence $p) -Body {
   param($first)
   $null=Get-AiwMajorAdoptionAdmission $doc $root -VerifyCurrent
   $state.reused=$first.status-ceq'PREPARED'-and$script:AdoptionPreparationInvocation.ContainsKey('key')
  }
  $state.cleared=$null-eq$script:AdoptionPreparationInvocation;$state
 } $Consumer $AdmitPath
 Check ($healthy.reused-and$healthy.cleared-and(Test-SnapshotPreserved $Consumer $before)) 'preparation-reuse-unchanged-valid-original-admission-and-scope-cleanup'
}

function Invoke-RegisteredRefreshTests([string]$Consumer,[string]$SourceRuntime,$DiscoverTemplate,[string]$OriginIdentity,[string]$TargetSeed=$SourceRuntime){
 $next=Join-Path $temp 'registration-refresh-snapshot';Copy-Item -LiteralPath $TargetSeed -Destination $next -Recurse
 if($TargetSeed-cne$SourceRuntime){SealFixture (Join-Path $next 'framework/versions/2.0.0') -Candidate}
 SealRuntimeFixture $next -Candidate -Snapshot 92
 $originalConfig=Get-Content -LiteralPath (Join-Path $Consumer '.ai-workspace/project.json') -Raw|ConvertFrom-Json
 $targetProfile=Get-Content -LiteralPath (Join-Path $next 'framework/versions/2.0.0/ADOPTION_PROFILE.json') -Raw|ConvertFrom-Json
 $formatTransition=$originalConfig.schemaVersion-ne$targetProfile.projectControl.schemaVersion
 $taskRelative='.ai-workspace/tasks/active/REFRESH-001.md';$task=Join-Path $Consumer $taskRelative
 $stateRelative='.ai-workspace/upgrade-recovery/2.0.0/state.json';$statePath=Join-Path $Consumer $stateRelative
 $originPath=Join-Path $Consumer '.ai-workspace/runtime/project-adoption/register/state.json'
 # A consistent fixture installation is the input to the real REGISTER7
 # adoption chain below; it is not a second registration or fabricated journal.
 $carrierPath=Join-Path $Consumer '.ai-workspace/corrections.json'
 # Correction binary ownership is a separate ordinary-project scenario. The
 # Maintenance SOURCE completion case needs no extra correction or effect path.
 $withEffects=-not[bool]$RegisteredMaintenance
 if($withEffects){
 $effectRelative='owned/register-correction.bin';$effectPath=Join-Path $Consumer $effectRelative
 [IO.Directory]::CreateDirectory((Split-Path -Parent $effectPath))|Out-Null;[IO.File]::WriteAllBytes($effectPath,[byte[]]@(0,255,128))
 $emptyRelative='owned/register-restored-empty.bin';$emptyPath=Join-Path $Consumer $emptyRelative
 [IO.File]::WriteAllBytes($emptyPath,[byte[]]@(255,0,128));$effectBefore=Identity $effectPath;$emptyBefore=Identity $emptyPath
 $evidenceRoot='.ai-workspace/upgrade-recovery/corrections/REGISTER_OWNED/seed/'
 $installation=[ordered]@{schemaVersion=1;correctionId='REGISTER_OWNED';decisionLocator='fixture:owned-seed';dependsOn=@();changes=@([ordered]@{kind='FILE';path=$effectRelative;beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String([byte[]]@(0,255,128))},[ordered]@{kind='FILE';path=$emptyRelative;beforeExists=$true;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String([byte[]]@(255,0,128))})}
 SaveJson (Join-Path $Consumer ($evidenceRoot+'installation.json')) $installation
 SaveJson (Join-Path $Consumer ($evidenceRoot+'history.json')) @{schemaVersion=1;correctionId='REGISTER_OWNED';operation='INSTALL';decisionLocator='fixture:owned-seed';priorRecord=$null}
 $carrier=Get-Content $carrierPath -Raw|ConvertFrom-Json -Depth 100
 $record=[ordered]@{correctionId='REGISTER_OWNED';introducedAgainstFramework='2.0.0';requirementReason='fixture installed correction';effectiveRule='Fixture owns a reversible registration helper.';applicability='isolated REGISTER refresh';decisionLocator='fixture:owned-seed';selectors=[ordered]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@();lifecycle=[ordered]@{state='ACTIVE';installation=@{locator=($evidenceRoot+'installation.json');identity=(Identity (Join-Path $Consumer ($evidenceRoot+'installation.json')))};decisionLocator='fixture:owned-seed'};history=@{locator=($evidenceRoot+'history.json');identity=(Identity (Join-Path $Consumer ($evidenceRoot+'history.json')))}}
 $carrier.corrections=@($carrier.corrections)+@($record);SaveJson $carrierPath $carrier
 }
 $pendingSource=$null
 if($RegisteredRuntimeRoot-and-not$PositiveUpgradeOnly){
  $sourceResults=@(New-B1PendingSourceAction $Consumer $SourceRuntime $DiscoverTemplate)
  foreach($result in $sourceResults){if($result-is[Collections.IDictionary]){if($null-ne$pendingSource){throw 'PENDING_SOURCE_FIXTURE_RESULT_COUNT'};$pendingSource=$result}else{Write-Output $result}}
  if($null-eq$pendingSource){throw 'PENDING_SOURCE_FIXTURE_RESULT_REQUIRED'}
 }
 if($withEffects){
 $groupPlan=@{schemaVersion=2;expectedCorrectionsIdentity=(Identity $carrierPath);changes=@(@{correctionId='REGISTER_OWNED';operation='UNINSTALL';decisionLocator='fixture:refresh-exit';record='NOT_APPLICABLE';installation='NOT_APPLICABLE';installationRelativePath='NOT_APPLICABLE';historyRelativePath='.ai-workspace/upgrade-recovery/corrections/REGISTER_OWNED/refresh/history.json';effectPaths=@($effectRelative,$emptyRelative);impact=@{stoppedObligations=@('fixture helper');independentObligations=@('REGISTER origin and user task');inFlightEffects=@();recovery='original refresh journal';semanticAssessment='exclusive binary ownership'}})}
 $groupPlanPath=Join-Path $Consumer '.ai-workspace/runtime/register-refresh-group-plan.json';SaveJson $groupPlanPath $groupPlan
 }
 SaveText $task ([string]::Join([char]10,@('# REFRESH-001 — Adopt the explicitly chosen next fixed runtime','- Task schema: 2.0.0','- Status: ACTIVE','- Profile: CRITICAL; reason=Fixed runtime adoption changes governance authority.','- Owner: owner-fixture','- Work route: actor=owner-fixture; role=CONTROLLER; phase=IMPLEMENT','- Phase gate: FALSE',('- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=FIXED_RUNTIME_REFRESH; expected_paths=['+$stateRelative+']; actual_paths=['+$stateRelative+']'),'- Writer / reviewer / authorization: isolated current action','- Stable candidate: NONE','- Git / push / external: DEFERRED','## Current','- Goal: Refresh this registered project through the original process and exact current package.','- Acceptance: PREPARE, original ADMIT, actual schema3 Apply, original FINALIZE, and interrupted recovery.')))
 $tool=Join-Path $next 'scripts/upgrade-project.ps1'
 $arguments=@{ProjectId='registration-fixture';ToVersion='2.0.0';RepositoryPath=$Consumer;ControllerId='owner-fixture';WorkspaceRoot=$next;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=(Identity $task);ActorRouteActor='owner-fixture'}
 if($withEffects){$arguments.AdoptionCorrectionsPlanPath=$groupPlanPath;$arguments.ExpectedAdoptionCorrectionsPlanIdentity=Identity $groupPlanPath}
 $preview=RunTool $tool $arguments;$pre=@{};$post=@{};$paths=@();$canonical='';$manifest=''
 foreach($line in $preview){
  if($line-match'^UPGRADE_PREIMAGE\|(?<path>.+)=(?<id>NEW|\d+\|[A-F0-9]{64})$'){$pre[$Matches.path]=$Matches.id}
  elseif($line-match'^UPGRADE_POSTIMAGE\|(?<path>.+)=(?<id>ABSENT|\d+\|[A-F0-9]{64})$'){$post[$Matches.path]=$Matches.id}
  elseif($line-match'^UPGRADE_WRITESET\|(?<paths>.+)$'){$paths=@($Matches.paths-split'\|')}
  elseif($line-match'^UPGRADE_TARGET_RELEASE\|canonical=(?<hash>[A-F0-9]{64})\|manifest=(?<id>\d+\|[A-F0-9]{64})$'){$canonical=$Matches.hash;$manifest=$Matches.id}
 }
 if(-not$paths.Count){
  $scopeLine=@($preview|Where-Object{$_-clike'UPGRADE_SCOPE_ONLY|*'})[0];$paths=@($scopeLine.Substring('UPGRADE_SCOPE_ONLY|'.Length)-split'\|')
  foreach($path in $paths){$file=Join-Path $Consumer $path;$pre[$path]=if(Test-Path -LiteralPath $file -PathType Leaf){Identity $file}else{'NEW'}}
  $canonical=(Get-Content (Join-Path $next 'framework/versions/2.0.0/RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json).canonical;$manifest=Identity (Join-Path $next 'framework/versions/2.0.0/RELEASE_MANIFEST.json')
 }
 Check ($paths.Count-gt0-and$pre.Count-eq$paths.Count-and$canonical-and$manifest) 'registered-refresh-real-scope-navigation-and-preimages'
 $taskText=[IO.File]::ReadAllText($task);$taskText=[regex]::Replace($taskText,'(?m)^- Range summary:.*$',('- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=FIXED_RUNTIME_REFRESH; expected_paths=['+($paths-join'|')+']; actual_paths=['+($paths-join'|')+']'));SaveText $task $taskText
 $arguments.ExpectedActorRouteTaskIdentity=Identity $task
 # Current governance authorization and the root schema3 transaction are distinct.
 $authority=[ordered]@{schemaVersion=3;frameworkVersion='2.0.0';taskId='REFRESH-001';profile='CRITICAL';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='PROJECT_CONTROLLER';issuerControllerId='owner-fixture';issuerControllerEpoch=1;controllerControlIdentity=(Identity (Join-Path $Consumer '.ai-workspace/controller.json'));grantee='owner-fixture';bundle='ACTOR_BOUND_PROJECT_UPGRADE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='ISOLATED_TEST_APPROVED_RUNTIME_REFRESH';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Identity $task);actions=@('CONTROL_WRITE');exactPaths=$paths;objectIdentities=@($paths|ForEach-Object{@{path=$_;identity=$pre[$_]}});postObjectIdentities=@();invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','POST_OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Identity (Join-Path $Consumer '.ai-workspace/project.json'));targetFrameworkSnapshot=@{canonical=$canonical;manifestIdentity=$manifest}}
 $packagePath=Join-Path $Consumer '.ai-workspace/runtime/REFRESH-001/owner-fixture/root-package.json';SaveJson $packagePath $authority
 $process=CloneFixture $authority;$process.schemaVersion=1;$process.bundle='REGISTERED_REFRESH_PROCESS';$process.Remove('postObjectIdentities');$process.Remove('targetFrameworkSnapshot');$process.invalidatesOn=@($process.invalidatesOn|Where-Object{$_-cne'POST_OBJECT_DRIFT'})
 if($RegisteredMaintenance){$process.schemaVersion=2;$process.repositoryId='CONTROL';if('REPOSITORY_CHANGE'-cnotin$process.invalidatesOn){$process.invalidatesOn+=@('REPOSITORY_CHANGE')}}
 $processPath=Join-Path $Consumer '.ai-workspace/runtime/REFRESH-001/owner-fixture/current-package.json';SaveJson $processPath $process
 $current=CloneFixture $DiscoverTemplate;$current.frameworkRoot=$SourceRuntime;$current.taskPath=$task;$current.expectedTaskIdentity=Identity $task;$current.expectedProjectConfigIdentity=$process.projectConfigIdentity;$current.expectedCorrectionsIdentity=Identity (Join-Path $Consumer '.ai-workspace/corrections.json')
 $current.exactPaths=$paths;$current.authorizationPackagePath=$processPath;$current.expectedAuthorizationIdentity=Identity $processPath;$current.userDecision=$process.userConfirmation
 $current.intentEnvelope.objective='Adopt this chosen fixed runtime and close the original registered-project action';$current.intentEnvelope.requestedActionKind='CONTROL_WRITE';$current.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$current.intentEnvelope.facets.workType.values=@('aiw:adoption');$current.intentEnvelope.facets.stage.values=@('aiw:adoption');$current.intentEnvelope.facets.deliverableType.values=@('aiw:configuration');$current.intentEnvelope.semanticHints=@('fixed runtime refresh','project adoption');$current.intentEnvelope.mutationHints=@('control')
 $inputPath=Join-Path $temp 'registered-refresh-discover.json';SaveJson $inputPath $current
 $sourceResolver=Join-Path $SourceRuntime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'
 if($RegisteredMaintenance){$sourceResolver=Join-Path $SourceRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}
 $discovered=RunTool $sourceResolver @{InputPath=$inputPath;AsJson=$true};Check ($discovered.status-ceq'PASS') 'registered-refresh-original-discover'
 $receiptPath=Join-Path $temp 'registered-refresh-compact.json';SaveJson $receiptPath $discovered.compactReceipt
 $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Identity $receiptPath);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 $boundaryPath=Join-Path $temp 'registered-refresh-boundary.json';SaveJson $boundaryPath $boundary
 $processArgs=$arguments.Clone();$processArgs.CurrentProcessInputPath=$boundaryPath;$processArgs.ExpectedCurrentProcessInputIdentity=Identity $boundaryPath;$processArgs.AdoptionProcessMode='PREPARE'
 $before=Identity $statePath;$chainWatch=[Diagnostics.Stopwatch]::StartNew();$timings=[ordered]@{};$phaseWatch=[Diagnostics.Stopwatch]::StartNew();$prepared=RunTool $tool $processArgs;$phaseWatch.Stop();$timings.prepare=$phaseWatch.Elapsed.TotalSeconds;Write-Output ('B1_TIMING|phase=PREPARE|wallSeconds='+$timings.prepare)
 Check ($prepared.status-ceq'PREPARED'-and(Identity $statePath)-ceq$before-and$prepared.previousDistribution.runtimeRoot-ceq$SourceRuntime) 'registered-refresh-real-prepare-zero-write'
 if($withEffects){
 $emptyEntry=@($prepared.projection.objects|Where-Object path -CEQ $emptyRelative)[0];$deletedEntry=@($prepared.projection.objects|Where-Object path -CEQ $effectRelative)[0]
 Check ($emptyEntry.newExists-and$emptyEntry.newIdentity-ceq'0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'-and-not$deletedEntry.newExists) 'registered-refresh-prepares-existing-empty-file-distinct-from-deletion'
 }
 $preparedPath=Join-Path $temp 'registered-refresh-prepared.json';SaveJson $preparedPath $prepared
 $authority.postObjectIdentities=@($prepared.projection.objects|ForEach-Object{[ordered]@{path=$_.path;identity=$(if($_.newExists){$_.newIdentity}else{'ABSENT'})}});SaveJson $packagePath $authority
 $boundary.preparationReceipts=@(@($boundary.preparationReceipts)+@($prepared.selectedRuleBlocks.preparationRequirements)|Sort-Object -Unique)+@('ADOPTION_TARGET_RULES_LOADED|'+(Identity $preparedPath))
 if($prepared.selectorSemanticJudgmentRequired){$boundary.preparationReceipts+=@('ADOPTION_SELECTOR_SEMANTICS_CONFIRMED|'+(Identity $preparedPath))}
 SaveJson $boundaryPath $boundary;$processArgs.ExpectedCurrentProcessInputIdentity=Identity $boundaryPath;$processArgs.AdoptionPreparationPath=$preparedPath;$processArgs.ExpectedAdoptionPreparationIdentity=Identity $preparedPath;$processArgs.AdoptionProcessMode='ADMIT_ACTION'
 $phaseWatch=[Diagnostics.Stopwatch]::StartNew();$admitted=RunTool $tool $processArgs;$phaseWatch.Stop();$timings.admit=$phaseWatch.Elapsed.TotalSeconds;Write-Output ('B1_TIMING|phase=ADMIT|wallSeconds='+$timings.admit);Check ($admitted.status-ceq'PASS') 'registered-refresh-original-admit'
 $admittedPath=Join-Path $temp 'registered-refresh-admitted.json';SaveJson $admittedPath $admitted
 $arguments.Apply=$true;$arguments.AuthorizationPackagePath=$packagePath;$arguments.ExpectedAuthorizationPackageIdentity=Identity $packagePath;$arguments.AdmitResultPath=$admittedPath;$arguments.ExpectedAdmitResultIdentity=Identity $admittedPath
 $arguments.CurrentProcessInputPath=$processArgs.CurrentProcessInputPath;$arguments.ExpectedCurrentProcessInputIdentity=$processArgs.ExpectedCurrentProcessInputIdentity
 $refreshPath=Join-Path $Consumer $(if($formatTransition){'.ai-workspace/runtime/project-adoption/upgrade/state.json'}else{'.ai-workspace/runtime/project-adoption/refresh/state.json'})
 if($PreparationRecheck){Invoke-PreparationRecheckCases $Consumer $next $admittedPath}
 $normal=CloneFixture $current;$normal.authorizationPackagePath='NOT_REQUIRED';$normal.expectedAuthorizationIdentity='NOT_REQUIRED';$normal.userDecision='NOT_REQUIRED';$normal.exactPaths=@();$normal.intentEnvelope.requestedActionKind='NONE';$normal.intentEnvelope.requestedResultKind='PLAN';$normal.intentEnvelope.mutationHints=@();$normal.intentEnvelope.objective='Inspect this registered project after refresh';$normal.intentEnvelope.facets.workType.values=@('aiw:planning');$normal.intentEnvelope.facets.stage.values=@('aiw:planning');$normal.intentEnvelope.facets.deliverableType.values=@('aiw:plan');SaveJson $inputPath $normal
 if(-not$PositiveUpgradeOnly){
 # Change only the root package decision after the real original admission.
 $projectionBefore=@($prepared.projection.objects|ForEach-Object{$file=Join-Path $Consumer $_.path;$_.path+'='+$(if(Test-Path -LiteralPath $file -PathType Leaf){Identity $file}else{'MISSING'})})
 $changedDecision=CloneFixture $authority;$changedDecision.userConfirmation='ISOLATED_TEST_DIFFERENT_RUNTIME_REFRESH_DECISION'
 $changedDecisionPath=Join-Path $temp 'registered-refresh-changed-decision-package.json';SaveJson $changedDecisionPath $changedDecision
 $rejectedArgs=$arguments.Clone();$rejectedArgs.AuthorizationPackagePath=$changedDecisionPath;$rejectedArgs.ExpectedAuthorizationPackageIdentity=Identity $changedDecisionPath
 $rejected=InvokeTool $tool $rejectedArgs
 $projectionAfter=@($prepared.projection.objects|ForEach-Object{$file=Join-Path $Consumer $_.path;$_.path+'='+$(if(Test-Path -LiteralPath $file -PathType Leaf){Identity $file}else{'MISSING'})})
 Check ($rejected.code-ne0-and$rejected.text.Contains('ADOPTION_PROCESS_MAJOR_PACKAGE_userConfirmation')-and[string]::Join("`n",$projectionBefore)-ceq[string]::Join("`n",$projectionAfter)) 'registered-refresh-changed-decision-rejected-with-entire-projection-unchanged'
 # Real public Apply stops after a file write and before its journal update.
 $emptyWrite=1
 if($withEffects){$emptyWrite=0;$writeIndex=0;foreach($entry in @($prepared.projection.objects|Where-Object changed)){$writeIndex++;if($entry.path-ceq$emptyRelative){$emptyWrite=$writeIndex;break}}}
 if($emptyWrite-lt1){throw 'EMPTY_FILE_WRITE_NOT_IN_REAL_PROJECTION'}
 $interrupted=$arguments.Clone();$interrupted.InterruptBeforeAdoptionJournalWrite=$emptyWrite;$stopped=RunTool $tool $interrupted
 Check (($stopped-join[char]10).Contains($(if($formatTransition){'MAJOR_ADOPTION_INTERRUPTED'}else{'RUNTIME_ADOPTION_INTERRUPTED'}))) 'registered-refresh-public-write-before-journal-interruption'
 if($withEffects){Check ((Test-Path -LiteralPath $emptyPath -PathType Leaf)-and(Get-Item -LiteralPath $emptyPath).Length-eq0-and-not(Test-Path -LiteralPath $effectPath)) 'registered-refresh-interruption-has-real-empty-file-and-deletion'}
 $blocked=InvokeTool $sourceResolver @{InputPath=$inputPath;AsJson=$true};Check ($blocked.code-ne0) 'registered-refresh-pending-journal-blocks-normal-load'
 $recover=@{ProjectId='registration-fixture';ToVersion='2.0.0';RepositoryPath=$Consumer;WorkspaceRoot=$next;ActorRouteActor='owner-fixture';RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=(Identity $refreshPath);AuthorizationPackagePath=$packagePath;ExpectedAuthorizationPackageIdentity=(Identity $packagePath);AdoptionRecoveryDirection='ROLLBACK';Apply=$true}
 $rolled=RunTool $tool $recover;Check ($rolled.status-ceq'ROLLED_BACK'-and(Identity $statePath)-ceq$before-and(Identity $originPath)-ceq$OriginIdentity) 'registered-refresh-public-rollback-restores-real-register-origin'
 if($withEffects){Check ((Identity $effectPath)-ceq$effectBefore-and(Identity $emptyPath)-ceq$emptyBefore) 'registered-refresh-rollback-restores-both-original-binary-effects'}
 $afterRollback=RunTool $sourceResolver @{InputPath=$inputPath;AsJson=$true};Check ($afterRollback.status-ceq'PASS') 'registered-refresh-normal-load-after-rollback'
 }
 $phaseWatch=[Diagnostics.Stopwatch]::StartNew();$null=RunTool $tool $arguments;$phaseWatch.Stop();$timings.apply=$phaseWatch.Elapsed.TotalSeconds;Write-Output ('B1_TIMING|phase=APPLY|wallSeconds='+$timings.apply)
 $newState=Get-Content $statePath -Raw|ConvertFrom-Json -Depth 100;$refresh=Get-Content $refreshPath -Raw|ConvertFrom-Json -Depth 100
 $originPreserved=if($formatTransition){$oldStateEntry=@($refresh.projection.objects|Where-Object path -CEQ $stateRelative);$newState.schemaVersion-eq6-and$newState.majorTransition.fromDistributionId-ceq$prepared.previousDistribution.distributionId-and$oldStateEntry.Count-eq1-and$oldStateEntry[0].oldIdentity-ceq$before}else{$newState.schemaVersion-eq7-and$newState.originKind-ceq'REGISTER'-and$newState.registrationTransactionIdentity-ceq$OriginIdentity}
 Check ($originPreserved-and$newState.distributionBinding.runtimeRoot-ceq$next-and$refresh.state-ceq'COMPLETE'-and(Identity $originPath)-ceq$OriginIdentity) 'registered-project-actual-adoption-keeps-original-register-proof'
 if($withEffects){
 Check (-not(Test-Path $effectPath)-and@((Get-Content $carrierPath -Raw|ConvertFrom-Json).corrections|Where-Object correctionId -CEQ REGISTER_OWNED)[0].lifecycle.state-ceq'UNINSTALLED') 'registered-refresh-group-deletes-owned-binary-without-reviving-correction'
 Check ((Test-Path -LiteralPath $emptyPath -PathType Leaf)-and(Get-Item -LiteralPath $emptyPath).Length-eq0) 'registered-refresh-group-restores-existing-zero-byte-file'
 }
 $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@(@($discovered.compactReceipt.selectedObligations.resultRequirements)+@($prepared.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($prepared.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.newExists){$_.newIdentity}else{'ABSENT'})});SaveJson $boundaryPath $boundary
 $finalArgs=$processArgs.Clone();$finalArgs.AdoptionProcessMode='FINALIZE_OUTPUT';$finalArgs.ExpectedCurrentProcessInputIdentity=Identity $boundaryPath;$finalArgs.AdmitResultPath=$admittedPath;$finalArgs.ExpectedAdmitResultIdentity=Identity $admittedPath;$finalArgs.AuthorizationPackagePath=$packagePath;$finalArgs.ExpectedAuthorizationPackageIdentity=Identity $packagePath;$finalArgs.ExpectedAdoptionTransactionIdentity=Identity $refreshPath
 $phaseWatch=[Diagnostics.Stopwatch]::StartNew();$closed=RunTool $tool $finalArgs;$phaseWatch.Stop();$timings.finalize=$phaseWatch.Elapsed.TotalSeconds;Write-Output ('B1_TIMING|phase=FINALIZE|wallSeconds='+$timings.finalize);Check ($closed.status-ceq'PASS'-and$closed.reason-ceq$(if($formatTransition){'ORIGINAL_CROSS_DISTRIBUTION_ADOPTION_FINALIZED'}else{'ORIGINAL_SAME_PIN_REFRESH_FINALIZED'})) 'registered-refresh-original-finalize'
 if($null-ne$pendingSource){
  $adoptionFinal=Join-Path $pendingSource.evidence 'completed-adoption-finalize-result.json';SaveJson $adoptionFinal $closed
  $oldFailure=InvokeTool $pendingSource.resolver @{InputPath=$pendingSource.final;AsJson=$true};SaveJson (Join-Path $pendingSource.evidence 'original-old-finalize-failure.json') $oldFailure
  $oldFailureReason=if($RegisteredMaintenance){'ADOPTION_PROCESS_CONTEXT_SCOPE'}else{'DISTRIBUTION_RUNTIME_ROOT_DRIFT'}
  Check ($oldFailure.code-ne0-and$oldFailure.text.Contains($oldFailureReason)) 'original-source-old-resolver-actual-cross-adoption-failure-retained'
  $sourceArguments=@{RepositoryRoot=$Consumer;InputPath=$pendingSource.final;ExpectedInputIdentity=(Identity $pendingSource.final);AdmitInputPath=$pendingSource.admitInput;ExpectedAdmitInputIdentity=(Identity $pendingSource.admitInput);AdmitResultPath=$pendingSource.admitResult;ExpectedAdmitResultIdentity=(Identity $pendingSource.admitResult);AdoptionAuthorizationPackagePath=$packagePath;ExpectedAdoptionAuthorizationIdentity=(Identity $packagePath);AdoptionFinalizeResultPath=$adoptionFinal;ExpectedAdoptionFinalizeResultIdentity=(Identity $adoptionFinal);ExpectedAdoptionTransactionIdentity=(Identity $refreshPath);ObservedActor='owner-fixture';ForbiddenPaths=@('private');ProtectedPaths=@('private')}
  $sourceFixture=Join-Path $pendingSource.evidence 'original-source-finalize-fixture.json';SaveJson $sourceFixture @{executionRuntimeRoot=$next;candidateRelativePath=$pendingSource.candidateRelativePath;arguments=$sourceArguments}
  if(-not$RegisteredMaintenance){
   $completed=RunTool (Join-Path $PSScriptRoot 'project-adoption-tests.ps1') @{OriginalSourceFinalizeFixturePath=$sourceFixture}
   Check (($completed-join[char]10).Contains('PASS|original-source-finalize|')) 'original-source-positive-repeat-and-real-negative-consumers'
  }
  Invoke-B1PublicOriginalSourceCases $next $sourceArguments
 }
 $normal.frameworkRoot=$next;$normal.expectedProjectConfigIdentity=Identity (Join-Path $Consumer '.ai-workspace/project.json');$normal.expectedCorrectionsIdentity=Identity (Join-Path $Consumer '.ai-workspace/corrections.json');SaveJson $inputPath $normal
 $currentResolver=if($RegisteredMaintenance){Join-Path $next 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $next 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
 $currentRead=RunTool $currentResolver @{InputPath=$inputPath;AsJson=$true};Check ($currentRead.status-ceq'PASS') 'registered-refresh-normal-current-task-rules'
 $completedArgs=$arguments.Clone();foreach($key in @('Apply','AuthorizationPackagePath','ExpectedAuthorizationPackageIdentity','AdmitResultPath','ExpectedAdmitResultIdentity','AdoptionCorrectionsPlanPath','ExpectedAdoptionCorrectionsPlanIdentity','CurrentProcessInputPath','ExpectedCurrentProcessInputIdentity')){$completedArgs.Remove($key)}
 $phaseWatch=[Diagnostics.Stopwatch]::StartNew();$completed=RunTool $tool $completedArgs;$phaseWatch.Stop();$timings.recovery=$phaseWatch.Elapsed.TotalSeconds;Check (($completed-join[char]10).Contains('RECOVERY_COMPLETE|to=2.0.0|writes=ZERO')) 'registered-refreshed-root-normal-recovery-zero-write'
 $chainWatch.Stop();$timings.totalWall=$chainWatch.Elapsed.TotalSeconds;$timings.scope=if($PositiveUpgradeOnly){'POSITIVE_CHAIN_PREPARE_THROUGH_RECOVERY'}else{'FUNCTIONAL_CHAIN_INCLUDING_NEGATIVES_ROLLBACK_AND_SOURCE'};Write-Output ('B1_UPGRADE_TIMINGS|'+($timings|ConvertTo-Json -Compress))
 if($PositiveUpgradeOnly){return}
 if($formatTransition){
  $fixed=Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $next
  Check ($fixed.State-ceq'FIXED_ADOPTED_SOURCE') 'registered-format-complete-original-finalize-and-fixed-source'
  $saved=[IO.File]::ReadAllBytes($statePath)
  try{
   SaveText $statePath '{}';$snapshot=Snapshot $Consumer;$rejected=InvokeTool $tool $completedArgs
   Check ($rejected.code-ne0-and(Test-SnapshotPreserved $Consumer $snapshot)) 'registered-format-damaged-complete-state-zero-write-rejection'
  }finally{[IO.File]::WriteAllBytes($statePath,$saved)}
  return
 }
 # Exercise the completed latest refresh, not only its original REGISTER.
 $fixedModule=@(Import-Module (Join-Path $next 'scripts/ProjectAdoptionState.psm1') -PassThru)[0]
 $reader=@(Import-Module (Join-Path $next 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
 $composer=@(Import-Module (Join-Path $next 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
 $saved=[IO.File]::ReadAllBytes($refreshPath)
 $events=[Collections.Generic.List[object]]::new();$sink={param($e) $events.Add($e)}.GetNewClosure()
 & $reader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {
  $fixed=& $fixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $Consumer -FrameworkRoot $next
  Check ($fixed.State-ceq'FIXED_ADOPTED_SOURCE'-and@($events|Where-Object stage -CEQ 'qualification-core-start').Count-eq0) 'registered-latest-refresh-fixed-source-validates-original-admission-without-deep-replay'
  $saved=[IO.File]::ReadAllBytes($refreshPath)
  try{
   $missing=Get-Content -LiteralPath $refreshPath -Raw|ConvertFrom-Json -Depth 100;$missing.metadata.PSObject.Properties.Remove('originalAdmitBase64');SaveJson $refreshPath $missing
   Check ($null-eq(& $fixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $Consumer -FrameworkRoot $next)) 'registered-latest-refresh-missing-admission-selects-full-fallback'
   $composer=@(Import-Module (Join-Path $next 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
   $count=@($events|Where-Object stage -CEQ 'qualification-core-start').Count
   $null=& $composer {param($v,$p) Get-AiwCompositionReleaseFacts -VersionDirectory $v -ProjectRoot $p} (Join-Path $next 'framework/versions/2.0.0') $Consumer
   Check (@($events|Where-Object stage -CEQ 'qualification-core-start').Count-eq($count+1)) 'registered-latest-refresh-missing-admission-reaches-real-full-qualification'
  }finally{[IO.File]::WriteAllBytes($refreshPath,$saved)}
  try{
   $bad=Get-Content -LiteralPath $refreshPath -Raw|ConvertFrom-Json -Depth 100;$bad.metadata.originalAdmitBase64=[Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes('{}'));SaveJson $refreshPath $bad
   $failure='';try{$null=& $fixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $Consumer -FrameworkRoot $next}catch{$failure=$_.Exception.Message}
   Check ($failure-ceq'FIXED_ADOPTION_ORIGINAL_DRIFT') 'registered-latest-refresh-rejects-changed-original-admission-bytes'
  }finally{[IO.File]::WriteAllBytes($refreshPath,$saved)}
  foreach($case in @(
   @{name='missing-projection';change={param($t) $t.PSObject.Properties.Remove('projection')}},
   @{name='projection-entry-shape';change={param($t) $t.projection.objects[0].PSObject.Properties.Remove('path')}},
   @{name='metadata-shape';change={param($t) $t.metadata=42}},
   @{name='missing-operation';change={param($t) $t.metadata.PSObject.Properties.Remove('operation')}},
   @{name='missing-completion';change={param($t) $t.PSObject.Properties.Remove('transactionComplete')}},
   @{name='binding-shape';change={param($t) $t.metadata.distributionBinding.runtimeRoot=42}},
   @{name='original-context-shape';change={param($t) $t.metadata.originalContext=@()}},
   @{name='original-discover-bytes';change={param($t) $t.metadata.originalDiscoverBase64='e30='}},
   @{name='original-discover-type';change={param($t) $t.metadata.originalDiscoverBase64=@()}},
   @{name='original-input-shape';change={param($t) $a=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($t.metadata.originalAdmitBase64))|ConvertFrom-Json -Depth 100;$a.originalAdmissionInput=42;$b=[Text.UTF8Encoding]::new($false).GetBytes(($a|ConvertTo-Json -Depth 100));$t.metadata.originalAdmitBase64=[Convert]::ToBase64String($b);$t.metadata.originalAdmitIdentity=$b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b));$t.metadata.admitResultIdentity=$t.metadata.originalAdmitIdentity}},
   @{name='original-decision';change={param($t) $a=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($t.metadata.originalAdmitBase64))|ConvertFrom-Json -Depth 100;$a.decisionIdentity='0'*64;$b=[Text.UTF8Encoding]::new($false).GetBytes(($a|ConvertTo-Json -Depth 100));$t.metadata.originalAdmitBase64=[Convert]::ToBase64String($b);$t.metadata.originalAdmitIdentity=$b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b));$t.metadata.admitResultIdentity=$t.metadata.originalAdmitIdentity}},
   @{name='latest-postimage';change={param($t) $e=@($t.projection.objects|Where-Object path -CEQ '.ai-workspace/upgrade-recovery/2.0.0/state.json')[0];$e.newBase64=$e.oldBase64;$e.newIdentity=$e.oldIdentity;$e.newExists=$e.oldExists;$e.changed=$false;$t.completedWrites=@($t.projection.objects|Where-Object changed).Count}}
  )){
   try{
    $bad=Get-Content -LiteralPath $refreshPath -Raw|ConvertFrom-Json -Depth 100;& $case.change $bad;SaveJson $refreshPath $bad
    $count=@($events|Where-Object stage -CEQ 'qualification-core-start').Count
    $failure='';try{$null=& $fixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $Consumer -FrameworkRoot $next}catch{$failure=$_.Exception.Message}
    Check ($failure-cmatch'^(REGISTRATION_|FIXED_ADOPTION_|ADOPTION_(RECOVERY_REQUIRED|PROCESS_))'-and$failure-notmatch'property .*cannot be found'-and@($events|Where-Object stage -CEQ 'qualification-core-start').Count-eq$count) ('registered-latest-refresh-controlled-rejection-'+$case.name)
   }finally{[IO.File]::WriteAllBytes($refreshPath,$saved)}
  }
  Check ((& $fixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $Consumer -FrameworkRoot $next).State-ceq'FIXED_ADOPTED_SOURCE') 'registered-latest-refresh-restored-original-chain-remains-fixed'
 }
 foreach($missingPart in @('originalDiscoverBase64','originalAdmissionInput')){
  try{
   $missing=Get-Content -LiteralPath $refreshPath -Raw|ConvertFrom-Json -Depth 100
   if($missingPart-ceq'originalAdmissionInput'){
    $a=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($missing.metadata.originalAdmitBase64))|ConvertFrom-Json -Depth 100;$a.PSObject.Properties.Remove('originalAdmissionInput')
    $b=[Text.UTF8Encoding]::new($false).GetBytes(($a|ConvertTo-Json -Depth 100));$missing.metadata.originalAdmitBase64=[Convert]::ToBase64String($b);$missing.metadata.originalAdmitIdentity=$b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b));$missing.metadata.admitResultIdentity=$missing.metadata.originalAdmitIdentity
   }else{$missing.metadata.PSObject.Properties.Remove($missingPart)}
   SaveJson $refreshPath $missing;$events.Clear()
   & $reader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {
    Check ($null-eq(& $fixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $Consumer -FrameworkRoot $next)) ('registered-latest-refresh-missing-'+$missingPart+'-has-no-fixed-credential')
    $null=& $composer {param($v,$p) Get-AiwCompositionReleaseFacts -VersionDirectory $v -ProjectRoot $p} (Join-Path $next 'framework/versions/2.0.0') $Consumer
    Check (@($events|Where-Object stage -CEQ 'qualification-core-start').Count-eq1-and@($events|Where-Object stage -CEQ 'fixed-adopted-source').Count-eq0) ('registered-latest-refresh-missing-'+$missingPart+'-reaches-real-full')
   }
  }finally{[IO.File]::WriteAllBytes($refreshPath,$saved)}
 }
}
# @design-contract REGISTRATION-PREFLIGHT-SCOPE-20261011.md
# This finite prefix is shared by the private fixture consumer and the formal
# candidate group. The original Transactions maintenance cases below retain
# their later config/source-consumer checks and use the same strict oracle.
function New-MaintenanceRegistrationFixture {
 $target=Join-Path $temp 'preflight-framework';Copy-Item -LiteralPath $workspace -Destination $target -Recurse
 Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination (Join-Path $target 'README.md')
 $fixed=Join-Path $temp 'preflight-runtime';Copy-Item -LiteralPath $target -Destination $fixed -Recurse
 Copy-Item -LiteralPath (Join-Path $sourceRoot 'framework/user-package/AGENTS.md') -Destination (Join-Path $fixed 'AGENTS.md')
 SealRuntimeFixture $fixed
 $entry=Join-Path $fixed 'scripts/register-project.ps1';$control=Join-Path $temp 'preflight-maintenance'
 $null=[IO.Directory]::CreateDirectory($control)
 & $git -C $target init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_PREFLIGHT_TARGET_GIT_INIT'}
 & $git -C $control init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_PREFLIGHT_CONTROL_GIT_INIT'}
 SaveText (Join-Path $control 'AGENTS.md') 'Preserve original project instructions.'
 $parameters=@{ProjectId='preflight-fixture';DisplayName='Preflight fixture';RepositoryPath=$control;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$fixed;ControlPlaneLayout='framework-maintenance-sibling';FrameworkTargetRepositoryId='fixture-target';FrameworkTargetSiblingDirectory='preflight-framework';Apply=$true}
 return [pscustomobject]@{entry=$entry;parameters=$parameters;runtime=$fixed;target=$target;control=$control}
}
function Invoke-MaintenanceRegistrationPreflightTests($Fixture) {
 if(-not$Fixture){$Fixture=New-MaintenanceRegistrationFixture}
 $entry=$Fixture.entry;$parameters=$Fixture.parameters;$fixed=$Fixture.runtime;$target=$Fixture.target;$control=$Fixture.control
 $before=Snapshot $control;$manifest=Join-Path $fixed 'PACKAGE_MANIFEST.json';$bytes=[IO.File]::ReadAllBytes($manifest)
 try{
  [IO.File]::Delete($manifest);$failure=InvokeTool $entry $parameters
  Check ($failure.code-ne0-and$failure.text.Contains('DISTRIBUTION_MANIFEST_REQUIRED')-and(Test-PristineSnapshotPreserved $control $before)) 'finite-maintenance-missing-fixed-package-strict-zero-write'
 }finally{[IO.File]::WriteAllBytes($manifest,$bytes)}
 $failure=InvokeTool (Join-Path $target 'scripts/register-project.ps1') $parameters
 Check ($failure.code-ne0-and$failure.text.Contains('DISTRIBUTION_MANIFEST_REQUIRED')-and(Test-PristineSnapshotPreserved $control $before)) 'finite-maintenance-development-entry-strict-zero-write'
 $bad=$parameters.Clone();$bad.FrameworkVersion='missing-preflight-version';$failure=InvokeTool $entry $bad
 Check ($failure.code-ne0-and$failure.text.Contains('FRAMEWORK_VERSION_NOT_FOUND')-and(Test-PristineSnapshotPreserved $control $before)) 'finite-maintenance-invalid-version-strict-zero-write'
 $preview=$parameters.Clone();$preview.Apply=$false;$value=RunTool $entry $preview
 Check (@($value)[-1].status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $control $before)) 'finite-maintenance-valid-preview-strict-zero-write'
 $preview.Apply=$true;$preview.WhatIf=$true;$value=RunTool $entry $preview
 Check (@($value)[-1].status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $control $before)) 'finite-maintenance-apply-whatif-strict-zero-write'
 $preview.Remove('WhatIf');$preview.Confirm=$true;$value=DeclineTool $entry $preview
 $decodedDecline=@($value.Trim()-split'\r?\n')[-1]|ConvertFrom-Json -Depth 100
 $reply=@($decodedDecline)[-1]
 if($null-eq$reply-or$reply-isnot[pscustomobject]-or$null-eq$reply.PSObject.Properties['status']-or$reply.status-isnot[string]){throw 'CONFIRM_DECLINE_RESULT_REQUIRED'}
 Check ($reply.status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $control $before)) 'finite-maintenance-declined-confirm-strict-zero-write'
 # A directory-only partial root cannot become legal just because the real
 # existing-state wrapper creates its synchronization carrier.
 $partial=Join-Path $temp 'preflight-parents-only';$null=[IO.Directory]::CreateDirectory((Join-Path $partial '.ai-workspace/runtime'))
 & $git -C $partial init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_PREFLIGHT_PARTIAL_GIT_INIT'}
 $bad=$parameters.Clone();$bad.RepositoryPath=$partial;$failure=InvokeTool $entry $bad
 Check ($failure.code-ne0-and$failure.text.Contains('Existing .ai-workspace is partial; refusing to merge or overwrite')-and-not(Test-Path -LiteralPath (Join-Path $partial '.ai-workspace/project.json'))) 'finite-maintenance-parents-only-refused-after-real-scope'
 # A genuine previous scope remains a legal existing sync-only root.
 $sync=Join-Path $temp 'preflight-sync-only';$null=[IO.Directory]::CreateDirectory($sync)
 & $git -C $sync init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_PREFLIGHT_SYNC_GIT_INIT'}
 Import-Module (Join-Path $fixed 'scripts/ProjectAdoptionState.psm1') -ErrorAction Stop
 Invoke-AiwRootProjectSourceScope -ProjectRoot $sync -Mode WRITE -Body {}
 $syncBefore=Snapshot $sync;$syncParameters=$parameters.Clone();$syncParameters.RepositoryPath=$sync;$syncParameters.Apply=$false
 $syncPreview=RunTool $entry $syncParameters
 Check (@($syncPreview)[-1].status-ceq'WHAT_IF'-and(Snapshot $sync)-ceq$syncBefore) 'finite-maintenance-existing-real-sync-only-preview'
 $value=RunTool $entry $parameters
 Check ($value.status-ceq'CREATED'-and(Test-Path -LiteralPath (Join-Path $control '.ai-workspace/runtime/source-publication.lock'))) 'finite-maintenance-effective-apply-real-transaction'
 $before=Snapshot $control;$value=RunTool $entry $parameters
 Check ($value.status-ceq'ALREADY_REGISTERED'-and(Snapshot $control)-ceq$before) 'finite-maintenance-repeat-original-registration-path'
 $script:MaintenancePreflightFixture=[pscustomobject]@{entry=$entry;parameters=$parameters;runtime=$fixed;target=$target}
}

function Invoke-RegistrationConfirmationRaceTests($Fixture) {
 foreach($kind in @('old-image','competing-registration')){
  $root=Join-Path $temp ('confirm-race-'+$kind);$null=[IO.Directory]::CreateDirectory($root)
  & $git -C $root init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_CONFIRM_RACE_GIT_INIT'}
  SaveText (Join-Path $root 'AGENTS.md') 'Original instructions before preparation.'
  $parameters=$Fixture.parameters.Clone();$parameters.RepositoryPath=$root;$parameters.Confirm=$true
  $onCallback={
   if(Test-Path -LiteralPath (Join-Path $root '.ai-workspace')){throw ('ASSERT_FAIL|confirm-barrier-pristine-'+$kind)}
   if($kind-ceq'old-image'){
    SaveText (Join-Path $root 'AGENTS.md') 'Changed instructions while confirmation is pending.'
    return @{changed=(Identity (Join-Path $root 'AGENTS.md'));controlAbsent=$true}
   }
   $competitor=$parameters.Clone();$competitor.Confirm=$false;$registered=RunTool $Fixture.entry $competitor
   if($registered.status-cne'CREATED'){throw 'ASSERT_FAIL|confirm-barrier-competing-real-registration-completes'}
   return @{competitorStatus=$registered.status;afterCompetitor=(Snapshot $root);controlAbsentBeforeCompetitor=$true}
  }
  $result=Invoke-ConfirmationProcess $Fixture.entry $parameters $kind $root 'Apply unified repository-local project registration' $onCallback
  Check ($result.callbackReached-and$result.ackAccepted) ('confirm-barrier-pristine-'+$kind)
  $text=$result.stdout+$result.stderr
  if($kind-ceq'old-image'){
   Check ($result.nativeCode-ne0-and$text.Contains('REGISTRATION_INITIAL_PLAN_DRIFT')-and(Identity (Join-Path $root 'AGENTS.md'))-ceq$result.mutation.changed-and-not(Test-Path -LiteralPath (Join-Path $root '.ai-workspace/project.json'))) 'locked-apply-refuses-prepared-old-image-drift'
  }else{
   Check ($result.mutation.competitorStatus-ceq'CREATED') 'confirm-barrier-competing-real-registration-completes'
   Check ($result.nativeCode-ne0-and$text.Contains('REGISTRATION_INITIAL_STATE_DRIFT')-and(Snapshot $root)-ceq$result.mutation.afterCompetitor) 'locked-apply-refuses-competing-registration-without-reselection'
  }
 }
}
function Invoke-CandidateRegistrationTests {
 $fixed=Join-Path $temp 'registration-snapshot';$consumer=Join-Path $temp 'registration-consumer';$null=[IO.Directory]::CreateDirectory($consumer)
 foreach($relative in @('scripts','skills','framework/maintenance-overlay','framework/versions/2.0.0')){
  $destination=Join-Path $fixed $relative;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $destination));Copy-Item -LiteralPath (Join-Path $workspace $relative) -Destination $destination -Recurse
 }
 $versionRoot=Join-Path $fixed 'framework/versions/2.0.0';SealFixture $versionRoot -Candidate;SealRuntimeFixture $fixed -Candidate
 $entry=Join-Path $fixed 'scripts/register-project.ps1';$taskRelative='.ai-workspace/tasks/active/REGISTER-001.md';$initial=Join-Path $temp 'REGISTER-001.md'
 SaveText $initial @'
# REGISTER-001 — Complete this project's adoption and first governance round
- Task schema: 2.0.0
- 状态：IN_PROGRESS
- Profile: STANDARD; reason=Finite project initialization and current governance facts.
- Owner: owner-fixture
- Work route: actor=owner-fixture; role=CONTROLLER; phase=IMPLEMENT
- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[.ai-workspace/PROJECT.md|.ai-workspace/process-policy.json|.ai-workspace/project.json]; actual_paths=[.ai-workspace/PROJECT.md|.ai-workspace/process-policy.json|.ai-workspace/project.json]
- Writer / reviewer / authorization: owner-fixture / NONE / separate current action package
- Stable candidate: NONE
- Git / push / external: DEFERRED / NONE / NONE
## Current
- Goal: Complete the explicitly requested project adoption and record its actual project facts.
- Scope: Record project facts and explicitly adopt optional knowledge through the exact config/policy pair; preserve product and private bytes.
- Implementation: Use the registered current task and normal action gates; interruption uses the original transaction.
- Acceptance: Current rule/support loading and a meaningful authorized first control write.
- Next action: Record actual governance facts and close this finite action.
'@
 $candidateArgs=@{ProjectId='registration-fixture';DisplayName='Registration fixture 中文';RepositoryPath=$consumer;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$fixed}
 $before=Snapshot $consumer;$default=InvokeTool $entry $candidateArgs
 Check ($default.code-ne0-and$default.text.Contains('FRAMEWORK_VERSION_NOT_CONSUMABLE')-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-registration-default-stable-and-zero-write'
 $candidateArgs.LocalCandidatePilot=$true;$missing=InvokeTool $entry $candidateArgs
 Check ($missing.code-ne0-and$missing.text.Contains('REGISTRATION_INITIAL_TASK_FIELDS_REQUIRED')-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-first-registration-requires-finite-task-group'
 $candidateArgs.InitialTaskPath=$initial;$candidateArgs.ExpectedInitialTaskIdentity=Identity $initial;$candidateArgs.InitialTaskRelativePath=$taskRelative
 SaveText (Join-Path $consumer 'README.md') 'Project-specific original README.';SaveText (Join-Path $consumer 'AGENTS.md') 'Project-specific instructions outside the managed block.';$before=Snapshot $consumer
 $manifestPath=Join-Path $versionRoot 'RELEASE_MANIFEST.json';$manifestBytes=[IO.File]::ReadAllBytes($manifestPath);$packageManifestPath=Join-Path $fixed 'PACKAGE_MANIFEST.json';$packageBytes=[IO.File]::ReadAllBytes($packageManifestPath)
  $healthy=InvokeTool $entry $candidateArgs
  $healthyReply=@($healthy.value)[-1]
  Check ($healthy.code-eq0-and$healthyReply-is[pscustomobject]-and$null-ne$healthyReply.PSObject.Properties['status']-and$healthyReply.status-is[string]-and$healthyReply.status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-qualification-valid-frontdoor-baseline-before'
  $nativePreview=Invoke-RegistrationNative $entry $candidateArgs
   $nativeReply=$nativePreview.Reply
   Check ($nativeReply.status-ceq'WHAT_IF'-and$null-ne$nativeReply.PSObject.Properties['changes']-and$nativeReply.changes-is[Array]-and$nativeReply.changes.Count-gt4-and$null-ne$nativeReply.PSObject.Properties['registrationId']-and$nativeReply.registrationId-is[string]-and$nativeReply.registrationId-ceq$healthyReply.registrationId-and(ConvertTo-Json -InputObject $nativeReply.changes -Depth 100 -Compress)-ceq(ConvertTo-Json -InputObject $healthyReply.changes -Depth 100 -Compress)-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-native-preview-full-array-matches-original-object-consumer'
  $qualificationCauses=@{'pending-review'='FRAMEWORK_LOCAL_CANDIDATE_REVIEW_REQUIRED|2.0.0|RELEASE_VALIDATION_STATE_UNSUPPORTED';'suite-mismatch'='FRAMEWORK_LOCAL_CANDIDATE_REVIEW_REQUIRED|2.0.0|RELEASE_VALIDATION_STATE_UNSUPPORTED';'suite-string-count'='FRAMEWORK_LOCAL_CANDIDATE_REVIEW_REQUIRED|2.0.0|RELEASE_VALIDATION_STATE_UNSUPPORTED';'array-review-status'='FRAMEWORK_LOCAL_CANDIDATE_REVIEW_REQUIRED|2.0.0|RELEASE_STRING|review-state|status'}
  foreach($case in @('pending-review','suite-mismatch','suite-string-count','array-review-status')){
  $bad=Get-Content $manifestPath -Raw|ConvertFrom-Json -Depth 100
  switch($case){'pending-review'{$bad.sourceReview='PENDING'};'suite-mismatch'{$bad.completeSuite.passed=0};'suite-string-count'{$bad.completeSuite.total='1'};'array-review-status'{$bad.sourceReviewEvidence.status=@('APPROVED','APPROVED')}}
   try {
    SaveJson $manifestPath $bad;SealRuntimeFixture $fixed -Candidate
    $invalidRuntimeBefore=Snapshot $fixed
    $rejected=InvokeTool $entry $candidateArgs
    Write-Output ('OBSERVE|candidate-qualification-stage|case='+$case+'|code='+$rejected.code+'|text='+$rejected.text)
    Check ($rejected.code-eq1-and$rejected.text.Contains($qualificationCauses[$case])-and$null-eq$rejected.value-and(Snapshot $fixed)-ceq$invalidRuntimeBefore-and(Test-PristineSnapshotPreserved $consumer $before)) ('candidate-qualification-rejects-'+$case+'-zero-write')
   } finally {[IO.File]::WriteAllBytes($manifestPath,$manifestBytes);[IO.File]::WriteAllBytes($packageManifestPath,$packageBytes)}
   $restored=InvokeTool $entry $candidateArgs
   $restoredReply=@($restored.value)[-1]
   Check ($restored.code-eq0-and$restoredReply-is[pscustomobject]-and$null-ne$restoredReply.PSObject.Properties['status']-and$restoredReply.status-is[string]-and$restoredReply.status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $consumer $before)) ('candidate-qualification-restored-'+$case)
 }
 $wrongEntry=InvokeTool (Join-Path $workspace 'scripts/register-project.ps1') $candidateArgs
 Check ($wrongEntry.code-ne0-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-registration-rejects-other-executing-runtime'
 $badTask=$candidateArgs.Clone();$badTask.ExpectedInitialTaskIdentity='1|'+('F'*64);$rejected=InvokeTool $entry $badTask
 Check ($rejected.code-ne0-and$rejected.text.Contains('REGISTRATION_INITIAL_TASK_DRIFT')-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-initial-task-byte-drift-zero-write'
 $badTask=$candidateArgs.Clone();$badTask.InitialTaskRelativePath='../REGISTER-001.md';$rejected=InvokeTool $entry $badTask
 Check ($rejected.code-eq1-and$rejected.text.Contains('REGISTRATION_INITIAL_TASK_PATH')-and$null-eq$rejected.value-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-initial-task-traversal-zero-write'
 $preview=RunTool $entry $candidateArgs;Check ($preview[-1].status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $consumer $before)) 'candidate-preview-writes-zero'
 $registrationId=$preview[-1].registrationId;$candidateArgs.Apply=$true;$candidateArgs.WhatIf=$true;$null=RunTool $entry $candidateArgs
 Check ((Test-PristineSnapshotPreserved $consumer $before)) 'candidate-whatif-writes-zero';$candidateArgs.Remove('WhatIf')
 $readmeId=Identity (Join-Path $consumer 'README.md');$created=RunTool $entry $candidateArgs
 $stateRelative='.ai-workspace/upgrade-recovery/2.0.0/state.json';$statePath=Join-Path $consumer $stateRelative;$originRelative='.ai-workspace/runtime/project-adoption/register/state.json';$originPath=Join-Path $consumer $originRelative
 $state=Get-Content $statePath -Raw|ConvertFrom-Json -Depth 100;$journal=Get-Content $originPath -Raw|ConvertFrom-Json -Depth 100
 Check ($created.status-ceq'CREATED'-and$state.schemaVersion-eq7-and$journal.state-ceq'COMPLETE'-and$journal.metadata.registrationId-ceq$registrationId-and$state.origin.registrationId-ceq$registrationId) 'actual-register-state7-and-stable-preview-apply-id'
 Check ($state.registrationTransactionIdentity-ceq'SELF_PROJECTION_BOUND'-and$journal.completedWrites-eq@($journal.projection.objects|Where-Object changed).Count-and@($state.projectionObjects|Where-Object{$_.relative-ceq$stateRelative}).Count-eq0) 'registration-completion-no-self-hash-cycle'
 Check ((Identity (Join-Path $consumer $taskRelative))-ceq(Identity $initial)-and(Identity (Join-Path $consumer 'README.md'))-ceq$readmeId-and[IO.File]::ReadAllText((Join-Path $consumer 'AGENTS.md')).StartsWith('Project-specific instructions')) 'register-preserves-project-and-exact-task-bytes'
 $entryText=[IO.File]::ReadAllText((Join-Path $consumer 'AGENTS.md'))
 Check (-not$entryText.Contains('均视为用户明确决定')-and(Get-AiwAgentsTemplateBlock $entryText).Contains('.ai-workspace/BOOTSTRAP.md')) 'actual-register-preserves-existing-instructions-without-appending-a-new-default-grant'
 Check ([IO.File]::ReadAllText((Join-Path $consumer '.ai-workspace/tasks/README.md')).Contains('| REGISTER-001 | '+$taskRelative+' | owner-fixture | STANDARD | CONTROLLER | IMPLEMENT | owner-fixture |')) 'register-index-locates-real-finite-task'
 $status=[IO.File]::ReadAllText((Join-Path $consumer '.ai-workspace/STATUS.md'))
 Check ($status.Contains('[REGISTER-001](tasks/active/REGISTER-001.md)')-and$status.Contains('[项目配置](project.json)')-and$status.Contains('repo-local')-and-not($status-match'Current phase|Current writer/reviewer|schema4|selectedRulePackBytes|执行 FULL_COLD')) 'register-status-navigates-real-task-and-current-config-without-task-mirrors'
 # Derive interruption input from the real registrar's original projection.
 # The engine is stopped before postcheck/commit; the public registrar must
 # roll it back and recreate the same complete registration.
 $interruptInput=Join-Path $temp 'register-interrupt-input.json';SaveJson $interruptInput @{root=$consumer;runtime=$fixed;projection=$journal.projection;metadata=$journal.metadata;createdDirectories=$journal.createdDirectories;originRelative=$originRelative}
 $interruptTool=Join-Path $temp 'register-interrupt.ps1';SaveText $interruptTool ((@'
param([string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$fixture=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -Depth 100
Import-Module (Join-Path $fixture.runtime 'scripts/ProjectAdoptionTransaction.psm1') -Force
Restore-AiwProjectProjection $fixture.root $fixture.projection @($fixture.createdDirectories) {param($root,$projection) -not(Test-Path -LiteralPath (Join-Path $root '.ai-workspace/project.json'))}
[IO.File]::Delete((Join-Path $fixture.root $fixture.originRelative))
$metadata=@{};foreach($property in $fixture.metadata.PSObject.Properties){$metadata[$property.Name]=$property.Value}
$writes=@($fixture.projection.objects|Where-Object changed).Count
Invoke-AiwProjectProjectionTransaction $fixture.root $fixture.projection $fixture.originRelative {param($root,$projection) throw 'INTERRUPTION_MUST_PRECEDE_POSTCHECK'} {param($root,$projection) $true} -Metadata $metadata -InterruptBeforeJournalWrite $writes
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $stopped=RunTool $interruptTool @{InputPath=$interruptInput}
 Check ($stopped.status-ceq'INTERRUPTED'-and(Test-Path -LiteralPath $statePath)) 'real-register-projection-interrupted-after-last-postimage'
 $pending=RunTool $entry ($candidateArgs.Clone()|ForEach-Object{$_.Apply=$false;$_})
 Check ($pending.status-ceq'RECOVERY_REQUIRED') 'interrupted-register-preview-requires-original-recovery'
 $pendingTree=Snapshot $consumer;$pendingJournal=Identity $originPath;$nativePendingArgs=$candidateArgs.Clone();$nativePendingArgs.Apply=$false
 $nativePending=Invoke-RegistrationNative $entry $nativePendingArgs;$nativePendingReply=$nativePending.Reply
 Check ($nativePendingReply.status-ceq'RECOVERY_REQUIRED'-and$null-ne$nativePendingReply.PSObject.Properties['transactionIdentity']-and$nativePendingReply.transactionIdentity-is[string]-and$nativePendingReply.transactionIdentity-ceq$pending.transactionIdentity-and(Identity $originPath)-ceq$pendingJournal-and(Snapshot $consumer)-ceq$pendingTree) 'candidate-native-recovery-required-preserves-original-journal-and-tree'
 $created=RunTool $entry $candidateArgs;$state=Get-Content $statePath -Raw|ConvertFrom-Json -Depth 100;$journal=Get-Content $originPath -Raw|ConvertFrom-Json -Depth 100
 Check ($created.status-ceq'CREATED'-and$journal.state-ceq'COMPLETE'-and$state.origin.registrationId-ceq$registrationId) 'public-register-rolls-back-and-retries-original-initialization'
 $configPath=Join-Path $consumer '.ai-workspace/project.json';$task=Join-Path $consumer $taskRelative
 $supportArgs=@{ProjectRoot=$consumer;ExpectedProjectConfigIdentity=(Identity $configPath);ExpectedCandidatePilotStateIdentity=(Identity $statePath);TaskPath=$task;ObservedActor='owner-fixture';HostName='CODEX';AsJson=$true}
 $support=RunTool (Join-Path $versionRoot 'scripts/resolve-load-plan.ps1') $supportArgs
 Check ($support.lifecycle-ceq'CANDIDATE'-and$support.candidatePilotStateIdentity-ceq(Identity $statePath)) 'state7-loads-real-support'
 $resolver=Join-Path $versionRoot 'scripts/resolve-process-requirements.ps1'
 $registrationInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$consumer;frameworkRoot=$fixed;taskPath=$task;expectedProjectConfigIdentity=(Identity $configPath);expectedCorrectionsIdentity=(Identity (Join-Path $consumer '.ai-workspace/corrections.json'));expectedTaskIdentity=(Identity $task);observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@('private/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Complete project adoption and its finite governance task';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('project adoption');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}}
 $registrationInputPath=Join-Path $temp 'registration-discover.json';SaveJson $registrationInputPath $registrationInput;$discovered=RunTool $resolver @{InputPath=$registrationInputPath;AsJson=$true}
 Check ($discovered.status-ceq'PASS'-and@($discovered.selectedRuleBlocks|Where-Object{[string]::IsNullOrWhiteSpace($_.fullText)}).Count-eq0) 'actual-registration-task-discovers-full-rules'
 $targetRelative='.ai-workspace/PROJECT.md';$target=Join-Path $consumer $targetRelative
 $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='REGISTER-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='PROJECT_CONTROLLER';issuerControllerId='owner-fixture';issuerControllerEpoch=1;controllerControlIdentity=(Identity (Join-Path $consumer '.ai-workspace/controller.json'));grantee='owner-fixture';bundle='REGISTRATION_FIRST_CONTROL';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Identity $task);actions=@('CONTROL_WRITE');exactPaths=@($targetRelative);objectIdentities=@(@{path=$targetRelative;identity=Identity $target});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Identity $configPath)}
 $packagePath=Join-Path $consumer '.ai-workspace/runtime/REGISTER-001/owner-fixture/first-control-package.json';SaveJson $packagePath $package
 $checked=InvokeTool (Join-Path $versionRoot 'scripts/check-authorization.ps1') @{PackagePath=$packagePath;TaskPath=$taskRelative;ExpectedTaskIdentity=(Identity $task);ObservedActor='owner-fixture';ObservedTaskId='REGISTER-001';ObservedOwner='owner-fixture';ObservedAction=@('CONTROL_WRITE');ObservedPath=@($targetRelative);ObservedIdentity=@($targetRelative+'='+(Identity $target));ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Identity $configPath);ControllerControlPath='.ai-workspace/controller.json'} $consumer
 if($checked.code-ne0){throw ('FIRST_CONTROL_CHECKER_REJECTED|'+$checked.text)}
 Check ($checked.code-eq0) 'registration-first-governance-independent-control-checker'
 $registrationInput.exactPaths=@($targetRelative);$registrationInput.authorizationPackagePath=$packagePath;$registrationInput.expectedAuthorizationIdentity=Identity $packagePath
 $registrationInput.intentEnvelope.requestedActionKind='CONTROL_WRITE';$registrationInput.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$registrationInput.intentEnvelope.facets.workType.values=@('aiw:implementation');$registrationInput.intentEnvelope.facets.deliverableType.values=@('aiw:configuration');$registrationInput.intentEnvelope.facets.stage.values=@('aiw:implementation');$registrationInput.intentEnvelope.mutationHints=@('control');SaveJson $registrationInputPath $registrationInput
 $write=RunTool $resolver @{InputPath=$registrationInputPath;AsJson=$true};$receiptPath=Join-Path $temp 'registration-control-compact.json';SaveJson $receiptPath $write.compactReceipt
 $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Identity $receiptPath;preparationReceipts=@($write.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 SaveJson $registrationInputPath $boundary;$admitted=RunTool $resolver @{InputPath=$registrationInputPath;AsJson=$true};Check ($admitted.status-ceq'PASS') 'registration-first-governance-control-admit'
 SaveText $target ([string]::Join([char]10,@('# Registration fixture','This project adopted the exact fixed candidate for its first finite governance task. Product work is outside this task.')))
 $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($write.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$targetRelative+'|'+(Identity $target));SaveJson $registrationInputPath $boundary
 $closed=RunTool $resolver @{InputPath=$registrationInputPath;AsJson=$true};Check ($closed.status-ceq'PASS') 'registration-first-governance-meaningful-control-write-finalized'
 # Optional first enable starts from this real candidate REGISTER result and
 # its finite task. Existing source-adoption fixtures cover interruption; this
 # public-consumer case proves original admission through selected FULLTEXT.
 $sourceRuntime=Join-Path $consumer '.ai-workspace/runtime/REGISTER-001/owner-fixture/knowledge-first'
 $null=[IO.Directory]::CreateDirectory($sourceRuntime)
 $sourcePaths=@('.ai-workspace/project.json')
 $sourcePackage=$package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $sourcePackage.bundle='REGISTRATION_OPTIONAL_KNOWLEDGE';$sourcePackage.exactPaths=$sourcePaths
 $sourcePackage.objectIdentities=@($sourcePaths|ForEach-Object{@{path=$_;identity=Identity (Join-Path $consumer $_)}})
 $sourcePackagePath=Join-Path $sourceRuntime 'package.json';SaveJson $sourcePackagePath $sourcePackage
 $checked=InvokeTool (Join-Path $versionRoot 'scripts/check-authorization.ps1') @{PackagePath=$sourcePackagePath;TaskPath=$taskRelative;ExpectedTaskIdentity=(Identity $task);ObservedActor='owner-fixture';ObservedTaskId='REGISTER-001';ObservedOwner='owner-fixture';ObservedAction=@('CONTROL_WRITE');ObservedPath=$sourcePaths;ObservedIdentity=@($sourcePackage.objectIdentities|ForEach-Object{$_.path+'='+$_.identity});ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Identity $configPath);ControllerControlPath='.ai-workspace/controller.json'} $consumer
 if($checked.code-ne0){throw ('FIRST_ENABLE_CHECKER_REJECTED|'+$checked.text)}
 $registrationInput.exactPaths=$sourcePaths;$registrationInput.authorizationPackagePath=$sourcePackagePath;$registrationInput.expectedAuthorizationIdentity=Identity $sourcePackagePath
 SaveJson $registrationInputPath $registrationInput
 $sourceDiscover=RunTool $resolver @{InputPath=$registrationInputPath;AsJson=$true}
 Check ($sourceDiscover.status-ceq'PASS'-and@($sourceDiscover.compactReceipt.binding.observedCapabilities).Count-eq0) 'registered-first-enable-original-discover-has-no-capability'
 $sourceReceipt=Join-Path $sourceRuntime 'compact.json';SaveJson $sourceReceipt $sourceDiscover.compactReceipt
 $nextConfig=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100
 $nextConfig.sourceBindings=@([pscustomobject]@{id='methods';provider='LOCAL_DIRECTORY';locator=@{root=$versionRoot};allowedPaths=@(@{kind='FILE';locator='knowledge/index.json'},@{kind='FILE';locator='knowledge/software/BEHAVIOR_SPEC_CHANGE.md'});decisionLocator='fixture:optional-first-knowledge'})
 $nextConfig.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@([pscustomobject]@{id='methods';bindingId='methods';indexLocator='knowledge/index.json';selectionHints=@('software behavior');updatePolicy='FOLLOW';revisionSelector='knowledge/index.json'})}}
 $nextConfigPath=Join-Path $sourceRuntime 'config.json';SaveJson $nextConfigPath $nextConfig
 $policyPath=Join-Path $consumer '.ai-workspace/process-policy.json';$nextPolicyPath=Join-Path $sourceRuntime 'policy.json';[IO.File]::Copy($policyPath,$nextPolicyPath)
 $decisionPath=Join-Path $sourceRuntime 'decision.md';SaveText $decisionPath 'Fixture project explicitly chooses optional reference methods and the exact config/policy source permissions.'
 $decision=[pscustomobject]@{path=$decisionPath;identity=Identity $decisionPath}
 $sourceModule=@(Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru)[0]
 $prepared=& $sourceModule.ExportedCommands['New-AiwProjectSourceChangePreparation'] -DiscoverReceiptPath $sourceReceipt -ExpectedDiscoverReceiptIdentity (Identity $sourceReceipt) -ConfigPostimagePath $nextConfigPath -PolicyPostimagePath $nextPolicyPath -DecisionRef $decision -OutputDirectory (Join-Path $sourceRuntime 'candidate')
 $sourceBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$sourceReceipt;expectedDiscoverReceiptIdentity=Identity $sourceReceipt;preparationReceipts=@(@($sourceDiscover.compactReceipt.selectedObligations.preparationRequirements)+@($prepared.preparationRequirements)|Sort-Object -Unique)+@($prepared.preparationReceipt);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 $sourceAdmitPath=Join-Path $sourceRuntime 'admit.json';SaveJson $sourceAdmitPath $sourceBoundary
 $sourceAdmitted=RunTool $resolver @{InputPath=$sourceAdmitPath;AsJson=$true};$sourceAdmitResult=Join-Path $sourceRuntime 'admit-result.json';SaveJson $sourceAdmitResult $sourceAdmitted
 Check ($sourceAdmitted.status-ceq'PASS'-and$sourceAdmitted.projectSourcePreparation.outcome-ceq'PREPARED') 'registered-first-enable-real-original-admission'
 $sourceCandidate=Get-Content $prepared.candidate.path -Raw|ConvertFrom-Json -Depth 100
 $policyStamp=[IO.File]::GetLastWriteTimeUtc($policyPath)
 foreach($item in $sourceCandidate.objects|Where-Object{$_.preimage.identity-cne$_.postimage.identity}){[IO.File]::WriteAllBytes((Join-Path $consumer $item.path),[IO.File]::ReadAllBytes($item.postimage.path))}
 $sourceBoundary.mode='FINALIZE_OUTPUT'
 $sourceBoundary.preparationReceipts+=('PROJECT_SOURCE_ADMISSION|'+$sourceAdmitPath+'|'+(Identity $sourceAdmitPath)+'|'+$sourceAdmitResult+'|'+(Identity $sourceAdmitResult))
 $sourceBoundary.resultReceipts=@(@($sourceDiscover.compactReceipt.selectedObligations.resultRequirements)+@($prepared.resultRequirements)|Sort-Object -Unique)+@($sourceCandidate.objects|Where-Object{$_.path-cin$sourcePaths}|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.postimage.identity})
 $sourceFinalPath=Join-Path $sourceRuntime 'finalize.json';SaveJson $sourceFinalPath $sourceBoundary
 $sourceClosed=RunTool $resolver @{InputPath=$sourceFinalPath;AsJson=$true}
 Check ($sourceClosed.status-ceq'PASS'-and$sourceClosed.projectSourcePreparation.outcome-ceq'COMPLETED'-and(Identity $policyPath)-ceq(Identity $nextPolicyPath)-and[IO.File]::GetLastWriteTimeUtc($policyPath)-eq$policyStamp-and$sourcePaths.Count-eq1) 'registered-first-enable-original-finalize-preserves-unchanged-policy'
 $selected=RunTool (Join-Path $versionRoot 'scripts/check-knowledge-entry.ps1') @{ProjectRoot=$consumer;ExpectedProjectConfigIdentity=(Identity $configPath);Operation='QUERY';EntryId=@('methods:BEHAVIOR_SPEC_CHANGE');ContentMode='FULLTEXT';ForbiddenPaths=@('private/');AsJson=$true}
 if($selected.entries.Count-ne1-or$selected.entries[0].status-cne'CURRENT'){throw ('FIRST_ENABLE_QUERY_UNAVAILABLE|'+($selected|ConvertTo-Json -Depth 100 -Compress))}
 Check ($selected.entries.Count-eq1-and$selected.entries[0].fullText-ceq[IO.File]::ReadAllText((Join-Path $versionRoot 'knowledge/software/BEHAVIOR_SPEC_CHANGE.md'))-and$selected.referenceOnly-and-not$selected.authority) 'registered-first-enable-selected-fulltext-is-complete-reference-only'
 $supportArgs.ExpectedProjectConfigIdentity=Identity $configPath
 $registrationInput.capabilities=@('KNOWLEDGE_REFERENCE')
 $originId=Identity $originPath;$stateBytes=[IO.File]::ReadAllBytes($statePath);$journalBytes=[IO.File]::ReadAllBytes($originPath)
 foreach($key in @('InitialTaskPath','ExpectedInitialTaskIdentity','InitialTaskRelativePath')){$candidateArgs.Remove($key)}
 [IO.File]::Delete($initial);[IO.File]::Move($task,(Join-Path $consumer '.ai-workspace/tasks/archive/REGISTER-001.md'))
 $repeat=RunTool $entry $candidateArgs;Check ($repeat.status-ceq'ALREADY_REGISTERED'-and(Identity $originPath)-ceq$originId) 'repeat-needs-no-source-or-active-initial-task'
 $supportArgs.Remove('TaskPath');$supportArgs.Role='CONTROLLER';$supportArgs.Profile='STANDARD';$supportArgs.Phase=@('IMPLEMENT')
 foreach($case in @('missing-origin','applying-origin','wrong-registration-id','wrong-root','false-state-completion','pending-foreign-journal')){
  switch($case){
   'missing-origin'{[IO.File]::Delete($originPath)}
   'applying-origin'{$bad=Get-Content $originPath -Raw|ConvertFrom-Json -Depth 100;$bad.state='APPLYING';$bad.transactionComplete=$false;SaveJson $originPath $bad}
   'wrong-registration-id'{$bad=Get-Content $originPath -Raw|ConvertFrom-Json -Depth 100;$bad.metadata.registrationId='F'*64;SaveJson $originPath $bad}
   'wrong-root'{$bad=Get-Content $statePath -Raw|ConvertFrom-Json -Depth 100;$bad.repositoryRoot=$temp;SaveJson $statePath $bad}
   'false-state-completion'{$bad=Get-Content $statePath -Raw|ConvertFrom-Json -Depth 100;$bad.transactionComplete=$false;SaveJson $statePath $bad}
   'pending-foreign-journal'{SaveJson (Join-Path $consumer '.ai-workspace/runtime/project-adoption/refresh/state.json') @{schemaVersion=1;state='APPLYING';transactionComplete=$false}}
  }
  $before=Snapshot $consumer;$supportArgs.ExpectedCandidatePilotStateIdentity=Identity $statePath;$badLoad=InvokeTool (Join-Path $versionRoot 'scripts/resolve-load-plan.ps1') $supportArgs
  Check ($badLoad.code-ne0-and(Test-SnapshotPreserved $consumer $before)) ('registered-runtime-rejects-'+$case+'-zero-write')
  [IO.File]::WriteAllBytes($originPath,$journalBytes);[IO.File]::WriteAllBytes($statePath,$stateBytes)
  if($case-ceq'pending-foreign-journal'){[IO.File]::Delete((Join-Path $consumer '.ai-workspace/runtime/project-adoption/refresh/state.json'))}
 }
 Invoke-RegisteredRefreshTests $consumer $fixed $registrationInput $originId
}

try{
 if($ConfirmationPhase-ceq'Mechanism'){
  Invoke-ConfirmationMechanismTests
  Write-Output 'PARTIAL|FIXTURE_CONTRACT_ONLY|non-git|code=0|status=PASS|reason=CONFIRMATION_Mechanism';return
 }
 if($Group-ceq'PreflightAst'){
  $preflightModule=New-NonGitTargetPreflightFixture (Join-Path $sourceRoot 'scripts/upgrade-project.ps1')
  $helper=$preflightModule.ExportedFunctions['Get-TargetProjectedProcessPreflight']
  Check ([object]::ReferenceEquals($helper.Module,$preflightModule)-and$helper.ScriptBlock.Ast-is[Management.Automation.Language.FunctionDefinitionAst]-and$helper.ScriptBlock.Ast.Body-is[Management.Automation.Language.ScriptBlockAst]-and$helper.ScriptBlock.Ast.Name-ceq'Get-TargetProjectedProcessPreflight') 'actual-root-body-first-level-helper-retains-module-owner'
  $env:PATH=$PSHOME+[IO.Path]::PathSeparator+[Environment]::GetFolderPath('System')
  Check ($null-eq(Get-Command git -ErrorAction SilentlyContinue)) 'early-ast-fixture-constructs-without-git-program'
  Write-Output ('NON_GIT_ADOPTION_TESTS_PASS|checks='+$script:passed+'|group='+$Group+'|scope=actual-root-body-constructor-and-module-owner');return
 }
 $workspace=Join-Path $temp 'framework';$project=Join-Path $temp 'project'
 $null=[IO.Directory]::CreateDirectory($project)
 $null=New-AiwTestMechanismFixture $sourceRoot $workspace (Join-Path $sourceRoot 'framework/versions/2.0.0/tests/test-groups.json') -Maintenance
 if($Group-cnotin@('CandidateRegistration','OriginalSourceAgents')){
  $destination=Join-Path $workspace 'framework/versions/1.16.0'
  $legacyRoot=Join-Path $sourceRoot 'framework/versions/1.16.0'
  $definition=Get-Content -LiteralPath (Join-Path $sourceRoot 'framework/versions/2.0.0/tests/test-groups.json') -Raw|ConvertFrom-Json -Depth 100
  $transaction=@($definition.groups|Where-Object id -CEQ 'non-git.transactions')[0]
  $legacyMembers=@($transaction.dependencies|Where-Object{$_.StartsWith('framework/versions/1.16.0/',[StringComparison]::Ordinal)})
  if($legacyMembers.Count-ne80-or@($legacyMembers|Sort-Object -Unique).Count-ne80){throw 'NON_GIT_LEGACY_DECLARED_MEMBER_SET'}
  [string[]]$legacyPaths=@($legacyMembers|Where-Object{$_-cne'framework/versions/1.16.0/RELEASE_MANIFEST.json'}|ForEach-Object{$_.Substring('framework/versions/1.16.0/'.Length)})
  Copy-AiwTestAllowlist $legacyRoot $destination $legacyPaths
  # The old schema remains confined to this legacy runtime fixture.
  Copy-Item -LiteralPath (Join-Path $legacyRoot 'RELEASE_MANIFEST.json') -Destination (Join-Path $destination 'RELEASE_MANIFEST.json');SealFixture $destination
  Copy-AiwTestAllowlist $sourceRoot $workspace @('skills/ai-workspace-router/SKILL.md')
 }
 $runner=Join-Path $temp 'invoke-tool.ps1'
 SaveText $runner ((@'
param([string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
try {
 $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
 if($call.ContainsKey('workingDirectory')-and$call.workingDirectory){Set-Location -LiteralPath $call.workingDirectory;[Environment]::CurrentDirectory=(Get-Location).Path}
 if($call.parameters.ContainsKey('OriginalSourceFinalizeFixturePath')-or$call.parameters.ContainsKey('AdoptionFinalizeResultPath')-or$call.parameters.ContainsKey('CompleteOriginalSourceAfterAgentsChange')){$env:CODEX_THREAD_ID=if($call.parameters.ContainsKey('ActorRouteActor')){$call.parameters.ActorRouteActor}else{'owner-fixture'}}
 $parameters=$call.parameters;$LASTEXITCODE=0
 $output=@(& $call.tool @parameters)
 if($LASTEXITCODE-ne0){$output|ForEach-Object{Write-Output $_};exit $LASTEXITCODE}
 if($output.Count-eq1){$output[0]|ConvertTo-Json -Depth 100 -Compress}else{ConvertTo-Json -InputObject $output -Depth 100 -Compress}
}catch{Write-Output $_.Exception.Message;exit 1}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 if($FixtureContractOnly){
  $reader=@(Import-Module (Join-Path $workspace 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
  $qualification=& $reader.ExportedCommands['Get-AiwReleaseQualification'] (Join-Path $workspace 'framework/versions/2.0.0')
  Check ($qualification.State-ceq'SOURCE_QUALIFIED') 'finite-non-git-real-release-reader-consumer'
  Write-AiwTestJson (Join-Path $env:AIW_TEST_RAW_DIRECTORY 'fixture-members-non-git.json') @{kind='PRIVATE_FINITE_FIXTURE';status='PASS';actualMembers=(Get-AiwTestFixtureSnapshot $workspace -IdentityOnly).Files;legacyDeclaredMembers=$(if($Group-cnotin@('CandidateRegistration','OriginalSourceAgents')){$legacyMembers}else{@()});legacyMembers=$(if($Group-cnotin@('CandidateRegistration','OriginalSourceAgents')){(Get-AiwTestFixtureSnapshot (Join-Path $workspace 'framework/versions/1.16.0') -IdentityOnly).Files}else{@()});qualificationState=$qualification.State;undeclaredOwnedSeedOmitted=(-not(Test-Path -LiteralPath (Join-Path $workspace 'owned-undeclared-seed.txt')))}
  if($Group-ceq'CandidateRegistration'){
   if($ConfirmationPhase-ceq'Races'){$fixture=New-MaintenanceRegistrationFixture;Invoke-RegistrationConfirmationRaceTests $fixture}
   elseif($ConfirmationPhase-ceq'Preflight'){Invoke-MaintenanceRegistrationPreflightTests}
   else{Invoke-MaintenanceRegistrationPreflightTests;Invoke-RegistrationConfirmationRaceTests $script:MaintenancePreflightFixture}
  }
  if($ConfirmationPhase){Write-Output ('PARTIAL|FIXTURE_CONTRACT_ONLY|non-git|code=0|status=PASS|reason=CONFIRMATION_'+$ConfirmationPhase);return}
  Write-Output 'PARTIAL|FIXTURE_CONTRACT_ONLY|non-git|code=0|status=PASS|reason=REAL_RELEASE_READER_AND_REGISTRATION_PREFLIGHT_REACHED';return
 }
 if($BaselineRegisterScript){Copy-Item -LiteralPath $BaselineRegisterScript -Destination (Join-Path $workspace 'scripts/register-project.ps1') -Force}
 if($Group-ceq'OriginalSourceAgents'){Invoke-SamePinAgentsSourceTests;Invoke-SamePinAgentsSourceTests -StopIncomplete;Write-Output ('NON_GIT_ADOPTION_TESTS_PASS|checks='+$script:passed+'|group='+$Group);return}
 if($RegisteredRuntimeRoot){Invoke-DeclaredRegisteredOriginTests $RegisteredRuntimeRoot;Write-Output ('NON_GIT_ADOPTION_TESTS_PASS|checks='+$script:passed+'|group=DECLARED_REGISTER_ORIGIN');return}
 Invoke-RootReadReuseTests
 if(-not$BaselineRegisterScript-and($Group-cin@('All','NestedSelectors')-or$CandidateRegistrationOnly)){Test-SnapshotSynchronizationAllowance;Invoke-NestedSelectorAdoptionTests $workspace}
 if($Group-ceq'NestedSelectors'){Write-Output ('NON_GIT_ADOPTION_TESTS_PASS|checks='+$script:passed+'|group='+$Group+'|scope=native-nested-selector-preparation-and-saved-replay');return}
 if(-not$BaselineRegisterScript-and$Group-cin@('All','CandidateRegistration')){Invoke-MaintenanceRegistrationPreflightTests;Invoke-RegistrationConfirmationRaceTests $script:MaintenancePreflightFixture;Invoke-CandidateRegistrationTests}
 if($Group-ceq'CandidateRegistration'-or$CandidateRegistrationOnly){Write-Output ('NON_GIT_ADOPTION_TESTS_PASS|checks='+$script:passed+'|group='+$Group+'|scope=actual-candidate-registration-and-first-governance');return}
 if($Group-cin@('All','Transactions')){
  # Candidate cases share this fixture; later ordinary registration needs its exact STABLE preimage.
  $samePinMetadata=@(foreach($relative in @('framework/versions/2.0.0/VERSION.json','framework/versions/2.0.0/LOAD_MANIFEST.json','framework/versions/2.0.0/RELEASE_MANIFEST.json','PACKAGE_MANIFEST.json')){
   $metadataPath=Join-Path $workspace $relative;$exists=[IO.File]::Exists($metadataPath)
   [pscustomobject]@{path=$metadataPath;relative=$relative;exists=$exists;bytes=$(if($exists){[IO.File]::ReadAllBytes($metadataPath)}else{$null});identity=$(if($exists){Identity $metadataPath}else{'ABSENT'})}
  })
  try{
   Invoke-SamePinAgentsSourceTests
   $samePinVersion=Get-Content -LiteralPath (Join-Path $workspace 'framework/versions/2.0.0/VERSION.json') -Raw|ConvertFrom-Json
   Check ($samePinVersion.lifecycle-ceq'CANDIDATE'-and-not$samePinVersion.consumable-and-not$samePinVersion.projectPinEligible) 'same-pin-completion-retains-candidate-fixture'
   Invoke-SamePinAgentsSourceTests -StopIncomplete
   $samePinVersion=Get-Content -LiteralPath (Join-Path $workspace 'framework/versions/2.0.0/VERSION.json') -Raw|ConvertFrom-Json
   Check ($samePinVersion.lifecycle-ceq'CANDIDATE'-and-not$samePinVersion.consumable-and-not$samePinVersion.projectPinEligible) 'same-pin-incomplete-retains-candidate-fixture'
  }finally{
   foreach($metadata in $samePinMetadata){
    if($metadata.exists){[IO.File]::WriteAllBytes($metadata.path,$metadata.bytes)}elseif([IO.File]::Exists($metadata.path)){[IO.File]::Delete($metadata.path)}
   }
   foreach($metadata in $samePinMetadata){
    $restored=[IO.File]::Exists($metadata.path)-eq$metadata.exists
    if($restored-and$metadata.exists){$restored=(Identity $metadata.path)-ceq$metadata.identity}
    Check $restored ('same-pin-restores-metadata-preimage-'+$metadata.relative)
   }
  }
  $samePinVersion=Get-Content -LiteralPath (Join-Path $workspace 'framework/versions/2.0.0/VERSION.json') -Raw|ConvertFrom-Json
  Check ($samePinVersion.lifecycle-ceq'STABLE'-and$samePinVersion.consumable-and$samePinVersion.projectPinEligible) 'same-pin-restores-stable-fixture-before-ordinary-registration'
 }
 $env:PATH=$PSHOME+[IO.Path]::PathSeparator+[Environment]::GetFolderPath('System')
 Check ($null-eq(Get-Command git -ErrorAction SilentlyContinue)) 'git-executable-absent-from-test-environment'
 $register=Join-Path $workspace 'scripts/register-project.ps1';$upgrade=Join-Path $workspace 'scripts/upgrade-project.ps1'
 # Prepare the real fixture before Transactions' expensive registration prefix.
 $preflightModule=New-NonGitTargetPreflightFixture $upgrade
 $parameters=@{ProjectId='nongit-fixture';DisplayName='Non Git fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$workspace}

 # Registration recovery has the same ShouldProcess boundary as registration.
 foreach($module in @('ProjectAdoptionState.psm1','ProjectAdoptionProjection.psm1','ProjectAdoptionTransaction.psm1')){Import-Module (Join-Path $workspace ('scripts/'+$module)) -Force}
 $partialRoot=Join-Path $temp 'partial-registration';$null=[IO.Directory]::CreateDirectory($partialRoot)
 SaveText (Join-Path $partialRoot 'existing.txt') 'Preserve unrelated project bytes.'
 $projection=New-AiwProjectProjection $partialRoot @([pscustomobject]@{path='.ai-workspace/project.json';text='{"partial":true}'})
 $registrationState='.ai-workspace/runtime/project-adoption/register/state.json'
 $interrupted=Invoke-AiwProjectProjectionTransaction $partialRoot $projection $registrationState {$true} {$true} -InterruptAfterWrite 1
 Check ($interrupted.status-ceq'INTERRUPTED') 'partial-registration-created-by-real-interrupted-transaction'
 $partialArgs=$parameters.Clone();$partialArgs.RepositoryPath=$partialRoot
 $before=Snapshot $partialRoot;$preview=RunTool $register $partialArgs
 Check ($preview.status-ceq'RECOVERY_REQUIRED'-and(Test-SnapshotPreserved $partialRoot $before)) 'partial-registration-ordinary-preview-zero-write'
 $partialArgs.Apply=$true;$partialArgs.WhatIf=$true;$null=RunTool $register $partialArgs
 if($BaselineRegisterScript){Check (-not(Test-SnapshotPreserved $partialRoot $before)) 'baseline-counterexample-registration-whatif-mutates-recovery-state';Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=known-baseline-counterexample');return}
 Check ((Test-SnapshotPreserved $partialRoot $before)) 'partial-registration-apply-whatif-zero-write-including-journal-and-directories'
 $partialArgs.Remove('WhatIf');$partialArgs.Confirm=$true;$decline=DeclineTool $register $partialArgs
 $declineLines=@($decline.Trim()-split'\r?\n');$declineResult=$declineLines[-1]|ConvertFrom-Json
 Check ($declineResult.status-ceq'RECOVERY_REQUIRED'-and(Test-SnapshotPreserved $partialRoot $before)) 'partial-registration-declined-confirm-zero-write'
 $partialArgs.Remove('Confirm')
 $rollback=Resume-AiwProjectProjectionRollback $partialRoot $registrationState (Identity (Join-Path $partialRoot $registrationState)) {$true}
 Check ($rollback.status-ceq'ROLLED_BACK') 'completed-registration-rollback-fixture'
 $before=Snapshot $partialRoot;$partialArgs.Remove('Apply');$null=RunTool $register $partialArgs
 Check ((Test-SnapshotPreserved $partialRoot $before)) 'completed-rollback-preview-preserves-cleanup-state'
 $partialArgs.Apply=$true;$partialArgs.WhatIf=$true;$null=RunTool $register $partialArgs
 Check ((Test-SnapshotPreserved $partialRoot $before)) 'completed-rollback-whatif-preserves-cleanup-state'
 $partialArgs.Remove('WhatIf');$null=RunTool $register $partialArgs
 Check ((Test-Path -LiteralPath (Join-Path $partialRoot '.ai-workspace/project.json'))-and[IO.File]::ReadAllText((Join-Path $partialRoot 'existing.txt')).Contains('unrelated')) 'confirmed-registration-recovery-retains-existing-project-data'
 $beforePreview=Snapshot $project
 $preview=RunTool $register $parameters
 Check (Test-PristineSnapshotPreserved $project $beforePreview) 'registration-preview-does-not-write'
 $parameters.Apply=$true;$registered=RunTool $register $parameters
 $configPath=Join-Path $project '.ai-workspace/project.json';$config=Get-Content $configPath -Raw|ConvertFrom-Json
 Check ($config.frameworkVersion-ceq'2.0.0'-and$config.id-ceq'nongit-fixture') 'non-git-registers-selected-version'
 $status=[IO.File]::ReadAllText((Join-Path $project '.ai-workspace/STATUS.md'))
 Check ($status.Contains('- Current task：none。')-and$status.Contains('repo-local')-and$status.Contains('[项目配置](project.json)')-and-not($status-match'schema4|selectedRulePackBytes|Current writer/reviewer|执行 FULL_COLD')) 'stable-no-task-registration-status-remains-truthful'
 $agents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
 Check ($agents.Contains('.ai-workspace/BOOTSTRAP.md')-and-not(Get-AiwAgentsTemplateBlock $agents).Contains('Skill')-and-not$agents.Contains('{{ROUTER_SKILL_NAME}}')) 'non-git-registration-renders-target-router-name'
 Check ((Get-AiwAgentsTemplateBlock $agents -Block USER-DECISION).Contains('在本项目内，AI')-and-not(Get-AiwAgentsTemplateBlock $agents).Contains('在本项目内，AI')) 'real-registration-keeps-user-decision-outside-managed-navigation'
 $agentsProjection=Get-AiwStandingDelegationProjection -Text $agents -AdoptionRequested $true -TemplatePath (Join-Path $workspace 'framework/versions/2.0.0/project-starter/AGENTS.md') -NavigationKind PROJECT_BOOTSTRAP
 Check ($agentsProjection-ceq$agents) 'real-registered-entry-refresh-is-byte-idempotent'
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.git'))-and-not(Test-Path -LiteralPath (Join-Path $project '.gitignore'))) 'registration-creates-no-git-or-ignore-file'
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md'))-and-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace/RELATIONSHIPS.md'))) 'new-starter-removes-special-review-and-relationship-carriers'
 Check ($config.schemaVersion-eq7-and$config.processPolicy.schemaVersion-eq3-and$config.sourceBindings-is[array]) 'new-target-registers-profile-declared-project6'
 $stableRegisterPath=Join-Path $project '.ai-workspace/runtime/project-adoption/register/state.json'
 $stableRegisterBytes=[IO.File]::ReadAllBytes($stableRegisterPath);$stableRegisterIdentity=Identity $stableRegisterPath
 $stableRegister=Get-Content -LiteralPath $stableRegisterPath -Raw|ConvertFrom-Json -Depth 100
 Check ($null-ne$stableRegister.metadata.PSObject.Properties['distributionBinding']-and$null-eq$stableRegister.metadata.distributionBinding-and$null-ne$stableRegister.metadata.PSObject.Properties['initialTask']-and$null-eq$stableRegister.metadata.initialTask-and-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0/state.json'))) 'stable-unnamed-real-register-has-null-optional-credentials'
 $stableFixedModule=@(Import-Module (Join-Path $workspace 'scripts/ProjectAdoptionState.psm1') -Force -PassThru)[0]
 Check ($null-eq(& $stableFixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $project -FrameworkRoot $workspace)) 'stable-unnamed-register-selects-full-qualification-without-fixed-credential'
 foreach($case in @(
  @{name='missing-binding-field';expected='FIXED_ADOPTION_METADATA_FIELD|distributionBinding';change={param($t) $t.metadata.PSObject.Properties.Remove('distributionBinding')}},
  @{name='malformed-nonnull-binding';expected='FIXED_ADOPTION_DISTRIBUTION_FIELD|contentIdentity';change={param($t) $t.metadata.distributionBinding=[pscustomobject]@{distributionId='incomplete'}}}
 )){
  try{
   $badRegister=$utf8.GetString($stableRegisterBytes)|ConvertFrom-Json -Depth 100
   & $case.change $badRegister;SaveJson $stableRegisterPath $badRegister
   $failure='';try{$null=& $stableFixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $project -FrameworkRoot $workspace}catch{$failure=$_.Exception.Message}
   $failureCheckName='stable-unnamed-supported-register-controlled-rejection-'+$case.name
   if($failure-cne$case.expected){$failureCheckName+='|expected='+$case.expected+'|actual='+$failure}
   Check ($failure-ceq$case.expected) $failureCheckName
  }finally{[IO.File]::WriteAllBytes($stableRegisterPath,$stableRegisterBytes)}
 }
 Check ((Identity $stableRegisterPath)-ceq$stableRegisterIdentity-and$null-eq(& $stableFixedModule.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $project -FrameworkRoot $workspace)) 'stable-unnamed-original-register-bytes-restored-without-fixed-credential'
 $config.sourceBindings=@(
  [pscustomobject]@{id='project-binding';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator='.'});decisionLocator='fixture:source-choice'},
  [pscustomobject]@{id='shared-binding';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=(Join-Path $temp 'unavailable-library')};allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator='.'});decisionLocator='fixture:source-choice'}
 )
 $config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@(
  [pscustomobject]@{id='project';bindingId='project-binding';indexLocator='.ai-workspace/knowledge/index.json';selectionHints=@('project facts');updatePolicy='FOLLOW';revisionSelector='.ai-workspace/knowledge/index.json'},
  [pscustomobject]@{id='shared';bindingId='shared-binding';indexLocator='index.json';selectionHints=@('reference');updatePolicy='FOLLOW';revisionSelector='index.json'}
 )}}
 SaveJson $configPath $config
 $repeated=RunTool $register $parameters
 Check ($repeated.status-ceq'ALREADY_REGISTERED') 'non-git-repeat-registration-is-idempotent'
 Check (-not(Test-Path -LiteralPath (Join-Path $temp 'unavailable-library'))-and-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace/knowledge'))) 'registration-validates-multiple-sources-without-opening-or-creating-them'
 $goodConfig=[IO.File]::ReadAllText($configPath)
 $config.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled=$false
 $config.sourceBindings[1].locator.root='C:unsafe'
 SaveJson $configPath $config
 $bad=InvokeTool $register $parameters
 Check ($bad.code-ne0-and$bad.text.Contains('SOURCE_DENIED')) 'registration-validates-disabled-source-structure'
 SaveText $configPath $goodConfig
 $duplicate=$goodConfig.Replace('"id":"shared"','"id":"shared","\u0069d":"duplicate"');SaveText $configPath $duplicate
 $bad=InvokeTool $register $parameters
 Check ($bad.code-ne0-and$bad.text.Contains('_DUPLICATE_MEMBER|$.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].id')) 'registration-rejects-real-nested-unicode-duplicate'
 SaveText $configPath $goodConfig
 SaveText (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md') 'Existing project-owned quality requirements.'
 $preserved=Identity (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md')
 $null=RunTool $register $parameters
 Check ((Identity (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md'))-ceq$preserved) 'old-named-project-document-is-preserved'
 $same=RunTool $upgrade @{ProjectId='nongit-fixture';RepositoryPath=$project;ToVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$workspace}
 Check (($same-join"`n").Contains('objects=0')) 'non-git-upgrade-preview-recognizes-current-state'
 $same=RunTool $upgrade @{ProjectId='nongit-fixture';RepositoryPath=$project;ToVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$workspace;Apply=$true}
 Check (($same-join"`n").Contains('ALREADY_UPGRADED')) 'non-git-same-pin-apply-is-no-op'

 $versionRoot=Join-Path $workspace 'framework/versions/2.0.0';$resolver=Join-Path $versionRoot 'scripts/resolve-process-requirements.ps1'
 $task=Join-Path $project '.ai-workspace/tasks/active/NONGIT-001.md';$source=Join-Path $project 'artifact.txt'
 SaveText $task @'
# NONGIT-001 — Verify the isolated artifact workflow without Git
- Task schema: 2.0.0
- Status: ACTIVE
- Owner: owner-fixture
- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT
- Range summary: profile=STANDARD; lifecycle=ACTIVE; risk=MEDIUM; size=SMALL; uncertainty=LOW; expected_paths=[artifact.txt]; actual_paths=[artifact.txt]
- Writer / reviewer / authorization: writer-fixture / reviewer-fixture / separate current action packages
- Stable candidate: NONE
- Git / push / external: EXCLUDED — isolated non-Git fixture
## Current
- Goal: Write, verify and independently review the isolated artifact through the original action gates without Git.
- Acceptance: Actual source and test finalization, independent review admission and explicit route delivery; original task bytes feed target preflight.
- Next action: Admit the bounded artifact write.
'@
 SaveText $source 'before'
 $input=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$workspace;taskPath=$task;expectedProjectConfigIdentity=(Identity $configPath);expectedCorrectionsIdentity=(Identity (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=(Identity $task);observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Understand the current task';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('task analysis');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}}
 $input.evaluationOnly=$false;$input.capabilities=@('KNOWLEDGE_REFERENCE')
 $inputPath=Join-Path $temp 'process-input.json';SaveJson $inputPath $input
 $loaded=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($loaded.status-ceq'PASS'-and$loaded.compactReceipt.binding.repositoryGitTop-ceq'NOT_APPLICABLE') 'ordinary-recovery-does-not-invent-git-authority'
 Check ($loaded.compactReceipt.schemaVersion-eq3-and$loaded.compactReceipt.intentEnvelope.schemaVersion-eq2) 'non-git-current-compact-and-intent-contract'
 $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='NONGIT-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='PLAN_LOCAL';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Identity $task);actions=@('SOURCE_WRITE');exactPaths=@('artifact.txt');objectIdentities=@(@{path='artifact.txt';identity=(Identity $source)});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Identity $configPath)}
 $packagePath=Join-Path $project '.ai-workspace/runtime/NONGIT-001/owner-fixture/action.json';SaveJson $packagePath $package
 $package.grantee='writer-fixture';SaveJson $packagePath $package;$input.observedActor='writer-fixture'
 $input.intentEnvelope.objective='Write the authorized isolated artifact';$input.intentEnvelope.facets.workType.values=@('aiw:implementation');$input.intentEnvelope.facets.deliverableType.values=@('aiw:code');$input.intentEnvelope.facets.stage.values=@('aiw:implementation');$input.intentEnvelope.mutationHints=@('source')
 $input.authorizationPackagePath=$packagePath;$input.expectedAuthorizationIdentity=Identity $packagePath;$input.exactPaths=@('artifact.txt');$input.intentEnvelope.requestedActionKind='SOURCE_WRITE';$input.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$input.intentEnvelope.semanticHints=@('implementation');$input.intentEnvelope.pathHints=@('artifact.txt');SaveJson $inputPath $input
 $write=RunTool $resolver @{InputPath=$inputPath;AsJson=$true};$receiptPath=Join-Path $temp 'write-receipt.json';SaveJson $receiptPath $write.compactReceipt
 $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Identity $receiptPath);preparationReceipts=@($write.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 SaveJson $inputPath $boundary;$admit=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($admit.status-ceq'PASS') 'ordinary-source-write-admitted-without-git'
 SaveText $source 'after'
 $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($write.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|artifact.txt|'+(Identity $source));SaveJson $inputPath $boundary
 $final=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($final.status-ceq'PASS'-and[IO.File]::ReadAllText($source).Trim()-ceq'after') 'ordinary-source-write-finalizes-without-git'
 $evidenceRoot=Join-Path $project '.ai-workspace/runtime/NONGIT-001/writer-fixture'
 $productionPath=Join-Path $evidenceRoot 'production-finalize.json';SaveJson $productionPath $final
 # An actual author command and original production result bind the candidate.
 # Host JSON below is an isolated protocol fixture, not an actual message send.
 $probe=Join-Path $temp 'check-artifact.ps1'
 SaveText $probe ('param([string]$Path)'+[char]10+'Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestNativeOutput.psm1')))+''')));Initialize-AiwTestNativeOutput'+[char]10+'if([IO.File]::ReadAllText($Path).Trim()-cne"after"){throw "ARTIFACT_CONTENT"};Write-Output "ARTIFACT_PASS"')
 $probeRun=Invoke-AiwTestProcess $pwsh @('-NoProfile','-NonInteractive','-File',$probe,'-Path',$source) -WorkingDirectory (Get-Location).Path -GroupId 'non-git-author-command';$probeOutput=@($probeRun.Output);$probeCode=$probeRun.Code
 Check ($probeCode-eq0) 'non-git-author-command-observes-written-artifact'
 $probeOutputPath=Join-Path $evidenceRoot 'author-command-output.txt';SaveText $probeOutputPath ($probeOutput-join"`n")
 $commandPath=Join-Path $evidenceRoot 'author-command.json';SaveJson $commandPath @{command=('pwsh -NoProfile -NonInteractive -File "'+$probe+'" -Path "'+$source+'"');exitCode=$probeCode;output=@{path=$probeOutputPath;identity=Identity $probeOutputPath}}
 $selfPath=Join-Path $evidenceRoot 'author-self-check.json';$requirements=@{path=$task;identity=Identity $task};$candidates=@(@{path='artifact.txt';identity=Identity $source})
 SaveJson $selfPath @{schemaVersion=1;taskId='NONGIT-001';actor='writer-fixture';candidateObjects=$candidates;requirementsRef=$requirements;outcome='PASS';checks=@(@{id='artifact-readback';method='COMMAND';outcome='PASS';reason='Actual isolated artifact probe; not production project acceptance.';evidenceLocators=@(@{path=$commandPath;identity=Identity $commandPath})});evidenceLocators=@($requirements,@{path=$productionPath;identity=Identity $productionPath})}
 $selfRef=@{kind='SELF_CHECK';path=$selfPath;identity=Identity $selfPath}
 $package.actions=@('TEST_RUN');$package.objectIdentities=$candidates;SaveJson $packagePath $package
 $input.expectedAuthorizationIdentity=Identity $packagePath;$input.intentEnvelope.objective='Verify the isolated written artifact without Git';$input.intentEnvelope.requestedActionKind='TEST_RUN';$input.intentEnvelope.requestedResultKind='TEST_RESULT';$input.intentEnvelope.facets.workType.values=@('aiw:verification');$input.intentEnvelope.facets.deliverableType.values=@('aiw:test-result');$input.intentEnvelope.facets.stage.values=@('aiw:verification');$input.intentEnvelope.semanticHints=@('verification');$input.intentEnvelope.mutationHints=@('test');SaveJson $inputPath $input
 $test=RunTool $resolver @{InputPath=$inputPath;AsJson=$true};$testReceipt=Join-Path $temp 'test-receipt.json';SaveJson $testReceipt $test.compactReceipt
 $boundary.mode='ADMIT_ACTION';$boundary.discoverReceiptPath=$testReceipt;$boundary.expectedDiscoverReceiptIdentity=Identity $testReceipt;$boundary.preparationReceipts=@($test.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);$boundary.resultReceipts=@();$boundary.evidenceRefs=@($selfRef);SaveJson $inputPath $boundary
 $testAdmit=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($test.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|artifact.txt|'+(Identity $source));SaveJson $inputPath $boundary
 $testFinal=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($testAdmit.status-ceq'PASS'-and$testFinal.status-ceq'PASS') 'ordinary-test-admission-and-typed-finalize-without-git'
 $package.grantee='reviewer-fixture';$package.actions=@('REVIEW_EXECUTE');$package.reviewIndependence='INDEPENDENT';$package.objectIdentities=@(@{path='artifact.txt';identity=(Identity $source)});SaveJson $packagePath $package
 $package.candidateWriter='writer-fixture';$package.materialContributors=@('contributor-fixture');$package.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE');SaveJson $packagePath $package
 $reviewPackagePath=Join-Path $evidenceRoot 'pure-review-package.json';SaveJson $reviewPackagePath $package
 $input.intentEnvelope.objective='Independently review the current isolated artifact';$input.intentEnvelope.facets.workType.values=@('aiw:review');$input.intentEnvelope.facets.deliverableType.values=@('aiw:review-verdict');$input.intentEnvelope.facets.stage.values=@('aiw:review');$input.intentEnvelope.mutationHints=@()
 $input.expectedAuthorizationIdentity=Identity $packagePath;$input.observedActor='reviewer-fixture';$input.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$input.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$input.intentEnvelope.semanticHints=@('review');SaveJson $inputPath $input
 $review=RunTool $resolver @{InputPath=$inputPath;AsJson=$true};$receiptPath=Join-Path $temp 'review-receipt.json';SaveJson $receiptPath $review.compactReceipt
 $boundary.mode='ADMIT_ACTION';$boundary.discoverReceiptPath=$receiptPath;$boundary.expectedDiscoverReceiptIdentity=Identity $receiptPath;$boundary.preparationReceipts=@($review.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);$boundary.resultReceipts=@();SaveJson $inputPath $boundary
 $reviewAdmit=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($reviewAdmit.status-ceq'PASS'-and$review.compactReceipt.binding.role-ceq'REVIEWER') 'pure-review-admission-does-not-require-git'
 $routePackage=$package|ConvertTo-Json -Depth 80|ConvertFrom-Json -Depth 80
 $routePackage.grantee='owner-fixture';$routePackage.actions=@('REVIEW_ROUTE');$routePackage.reviewIndependence='NOT_APPLICABLE';$routePackage.PSObject.Properties.Remove('candidateWriter');$routePackage.PSObject.Properties.Remove('materialContributors');SaveJson $packagePath $routePackage
 $input.expectedAuthorizationIdentity=Identity $packagePath;$input.observedActor='owner-fixture';$input.intentEnvelope.objective='Owner routes another writer current candidate to its independent Reviewer';$input.intentEnvelope.requestedActionKind='REVIEW_ROUTE';$input.intentEnvelope.requestedResultKind='HANDOFF';$input.intentEnvelope.facets.workType.values=@('aiw:task-organization','aiw:review');$input.intentEnvelope.facets.deliverableType.values=@('aiw:handoff');SaveJson $inputPath $input
 $route=RunTool $resolver @{InputPath=$inputPath;AsJson=$true};$routeReceipt=Join-Path $temp 'owner-route-receipt.json';SaveJson $routeReceipt $route.compactReceipt
 $boundary.deliveryContext=@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='reviewer-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=@{path=$reviewPackagePath;identity=Identity $reviewPackagePath}}
 $boundary.mode='ADMIT_ACTION';$boundary.discoverReceiptPath=$routeReceipt;$boundary.expectedDiscoverReceiptIdentity=Identity $routeReceipt;$boundary.preparationReceipts=@($route.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);$boundary.resultReceipts=@();$boundary.evidenceRefs=@($selfRef);SaveJson $inputPath $boundary
 $routeAdmit=RunTool $resolver @{InputPath=$inputPath;AsJson=$true};Check ($routeAdmit.status-ceq'PASS') 'owner-routes-other-writer-public-admission-without-git'
 $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($route.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|artifact.txt|'+(Identity $source))
 SaveJson $inputPath $boundary;$routePrepare=InvokeTool $resolver @{InputPath=$inputPath;AsJson=$true};$prepared=$routePrepare.text|ConvertFrom-Json -Depth 100
 Check ($routePrepare.code-ne0-and$prepared.status-ceq'BLOCKED'-and$prepared.delivery.status-ceq'READY_TO_SEND'-and($prepared.missingResult-join'|')-ceq'DELIVERY_NOT_CONFIRMED') 'owner-route-public-prepare-binds-other-writer-and-awaits-host'
 $hostPath=Join-Path $evidenceRoot 'isolated-host-result.json';SaveJson $hostPath @{isError=$false;content=@(@{type='text';text='{"threadId":"reviewer-fixture"}'})}
 $boundary.deliveryContext.stage='OBSERVE';$boundary.deliveryContext.observedRecipient='reviewer-fixture';$boundary.deliveryContext.outcome='SUCCESS';$boundary.deliveryContext.evidence=$hostPath+'#'+(Identity $hostPath);SaveJson $inputPath $boundary
 $routeFinal=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($routeFinal.status-ceq'PASS'-and$routeFinal.delivery.status-ceq'DELIVERED'-and-not$routeFinal.consumer.userAuthorizationProven-and-not$routeFinal.consumer.recipientWorkProven) 'owner-route-public-finalize-validates-isolated-host-protocol-only'
 $safeGitReader=@(Import-Module (Join-Path $versionRoot 'scripts/StrictJsonInput.psm1') -PassThru)[0]
 $gitStatusTool=Join-Path $versionRoot 'scripts/invoke-protected-safe-git.ps1'
 $gitStatusArgs=@{ProjectRoot=$project;Operation='STATUS';AllowPath=@('artifact.txt');ExpectedProjectConfigIdentity=(Identity $configPath)}
 $beforeSafeGit=Snapshot $project
 $gitAction=InvokeTool $gitStatusTool $gitStatusArgs
 $gitRejected=Get-SafeGitRejection $gitAction $safeGitReader
 Check ($null-ne$gitRejected-and(Snapshot $project)-ceq$beforeSafeGit-and(Identity $configPath)-ceq$gitStatusArgs.ExpectedProjectConfigIdentity-and$null-eq(Get-Command git -ErrorAction SilentlyContinue)) 'real-git-operation-still-rejects-unavailable-git'
 $noGitPath=$env:PATH
 try{
  $env:PATH=$oldPath
  $availableGit=Get-Command git -CommandType Application -ErrorAction Stop
  if($availableGit.Source-cne$git-or(Test-Path -LiteralPath (Join-Path $project '.git'))){throw 'PAIRED_GIT_FIXTURE_PRECONDITION'}
  $gitTop=@(& $git -C $project rev-parse --show-toplevel 2>$null)
  if($LASTEXITCODE-eq0){throw 'PAIRED_PROJECT_INHERITS_GIT_REPOSITORY'}
  $gitAvailableAction=InvokeTool $gitStatusTool $gitStatusArgs
  $gitAvailableRejected=Get-SafeGitRejection $gitAvailableAction $safeGitReader
  Check ($null-ne$gitAvailableRejected-and$gitAvailableRejected.reason-ceq'PROJECT_GIT_TOP_UNAVAILABLE'-and(Snapshot $project)-ceq$beforeSafeGit-and(Identity $configPath)-ceq$gitStatusArgs.ExpectedProjectConfigIdentity) 'real-git-operation-rejects-non-repository-with-available-git'
 }finally{$env:PATH=$noGitPath}

 foreach($module in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction','MaintenanceOverlay')){Import-Module (Join-Path $workspace ('scripts/'+$module+'.psm1')) -Force}
 # Exercise the actual target-before-pin implementation without manufacturing
 # a supported cross-version migration. W5 separately owns that bridge.
 $preflight=& $preflightModule {
  param($project,$workspace,$task)
  $AuthorizationPackagePath='';$ExpectedAuthorizationPackageIdentity='';$CurrentProcessInputPath='';$ExpectedCurrentProcessInputIdentity='';$AdoptionProcessMode='';$Apply=$false;$SelectedRulePackBytes=32768
  $script:utf8NoBom=[Text.UTF8Encoding]::new($false);$script:utf8Strict=[Text.UTF8Encoding]::new($false,$true)
  $script:ActiveAdoptionProfile=$null;$script:ActiveTargetCapabilityContract=$null
  $migration=[pscustomobject]@{Relative='.ai-workspace/tasks/active/NONGIT-001.md';Content=[IO.File]::ReadAllText($task);Actor='owner-fixture'}
  Get-TargetProjectedProcessPreflight $project $workspace '2.0.0' 'nongit-fixture' $migration ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/project.json'))) ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/BOOTSTRAP.md'))) ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/corrections.json'))) ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/process-policy.json'))) (Join-Path $project '.ai-workspace/controller.json') -ReadOnlyCandidateRefresh
 } $project $workspace $task
 Check ($preflight.ResolverReason-ceq'PASS'-and$null-eq(Get-Command git -ErrorAction SilentlyContinue)) 'target-before-pin-preflight-needs-no-git-program-or-projection-repository'
 Remove-Module -ModuleInfo $preflightModule
 $preflightModule=$null
 $objects=@([pscustomobject]@{path='artifact.txt';text='transitioned'},[pscustomobject]@{path='new.txt';text='created'})
 foreach($step in @(0,1,2)){
  SaveText $source 'after';$projection=New-AiwProjectProjection $project $objects;$relative='.ai-workspace/upgrade-recovery/nongit-'+$step+'/state.json'
  $interrupted=Invoke-AiwProjectProjectionTransaction $project $projection $relative {$true} {$true} -InterruptAfterWrite $step
  Check ($interrupted.status-ceq'INTERRUPTED') ('non-git-transaction-interruption-'+$step)
  $rollback=Resume-AiwProjectProjectionRollback $project $relative (Identity (Join-Path $project $relative)) {$true}
  Check ($rollback.status-ceq'ROLLED_BACK'-and[IO.File]::ReadAllText($source).Trim()-ceq'after'-and-not(Test-Path -LiteralPath (Join-Path $project 'new.txt'))) ('non-git-transaction-recovery-'+$step)
 }
 $reason='';try{Resolve-AiwMaintenanceTopology -ControlRepositoryPath $project -TargetRepositoryId fixture-target -TargetSiblingDirectory target -TargetRoutineExcludedPaths @()|Out-Null}catch{$reason=$_.Exception.Message}
 Check (-not[string]::IsNullOrWhiteSpace($reason)) 'maintenance-topology-still-requires-real-git-conditions'
 $toolchain=Get-Content (Join-Path $versionRoot 'TOOLCHAIN.json') -Raw|ConvertFrom-Json;$toolchain.navigation.kind='SKILL'
 $reason='';try{Get-AiwNavigationContract $toolchain|Out-Null}catch{$reason=$_.Exception.Message}
 Check ($reason-like'FRAMEWORK_BOOTSTRAP_NAVIGATION_*') 'current-navigation-cannot-use-old-shared-skill'
 $env:PATH=$oldPath
 if([string]::IsNullOrWhiteSpace($git)){throw 'GIT_REGRESSION_TOOL_UNAVAILABLE'}
 $gitProject=Join-Path $temp 'git-project';$null=[IO.Directory]::CreateDirectory($gitProject);& $git -C $gitProject init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_GIT_INIT'}
 $parameters.RepositoryPath=$gitProject;$parameters.FrameworkVersion='1.16.0';$null=RunTool $register $parameters
 Check ([IO.File]::ReadAllText((Join-Path $gitProject '.gitignore')).Contains('/.ai-workspace/runtime/')) 'git-project-keeps-runtime-ignore-projection'
 Check (Test-Path -LiteralPath (Join-Path $gitProject '.ai-workspace/REVIEW_PROFILE.md')) 'old-version-keeps-its-owned-template-contract'
 $nested=Join-Path $gitProject 'nested-project';$null=[IO.Directory]::CreateDirectory($nested);$parameters.RepositoryPath=$nested;$parameters.FrameworkVersion='2.0.0';$null=RunTool $register $parameters
 Check ((Test-Path -LiteralPath (Join-Path $nested '.ai-workspace/project.json'))-and-not(Test-Path -LiteralPath (Join-Path $nested '.git'))) 'explicit-subproject-root-is-not-promoted-to-parent-git-root'
 $gitKnowledge=Join-Path $temp 'git-knowledge';$null=[IO.Directory]::CreateDirectory($gitKnowledge);& $git -C $gitKnowledge init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_GIT_INIT'}
 $parameters.RepositoryPath=$gitKnowledge;$null=RunTool $register $parameters
 $gitConfigPath=Join-Path $gitKnowledge '.ai-workspace/project.json';$gitConfig=Get-Content $gitConfigPath -Raw|ConvertFrom-Json
 $gitConfig.frameworkCapabilities=($goodConfig|ConvertFrom-Json).frameworkCapabilities;$gitConfig.sourceBindings=($goodConfig|ConvertFrom-Json).sourceBindings;SaveJson $gitConfigPath $gitConfig;SaveText (Join-Path $gitKnowledge 'artifact.txt') 'fixture'
 $safeTool=Join-Path $versionRoot 'scripts/invoke-protected-safe-git.ps1'
 $safe=InvokeTool $safeTool @{ProjectRoot=$gitKnowledge;Operation='STATUS';AllowPath=@('artifact.txt');ExpectedProjectConfigIdentity=(Identity $gitConfigPath)}
 Check ($safe.code-eq0-and$safe.value-is[pscustomobject]-and@(@('status','operation','repositoryId','launched','paths','output')|Where-Object{$_-cnotin$safe.value.PSObject.Properties.Name}).Count-eq0-and$safe.value.status-is[string]-and$safe.value.status-ceq'VERIFIED'-and$safe.value.operation-is[string]-and$safe.value.operation-ceq'STATUS'-and$safe.value.repositoryId-is[string]-and$safe.value.repositoryId-ceq'PROJECT'-and$safe.value.launched-is[bool]-and$safe.value.launched-and$safe.value.paths-is[array]-and$safe.value.output-is[array]-and'artifact.txt'-cin$safe.value.paths-and@($safe.value.output|Where-Object{$_-is[string]-and$_-cmatch'^\?\? "?artifact\.txt"?$'}).Count-gt0) 'safe-git-accepts-valid-multi-source-config-with-unavailable-library'
 $gitConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled=$false;$gitConfig.sourceBindings[1].locator.root='C:unsafe';SaveJson $gitConfigPath $gitConfig
 $beforeInvalidGitSource=Snapshot $gitKnowledge
 $safe=InvokeTool $safeTool @{ProjectRoot=$gitKnowledge;Operation='STATUS';AllowPath=@('artifact.txt');ExpectedProjectConfigIdentity=(Identity $gitConfigPath)}
 $invalidSourceRejected=Get-SafeGitRejection $safe $safeGitReader
 Check ($null-ne$invalidSourceRejected-and$invalidSourceRejected.reason.Contains('SOURCE_DENIED')-and(Snapshot $gitKnowledge)-ceq$beforeInvalidGitSource) 'safe-git-rejects-invalid-disabled-source-before-git'

 Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination (Join-Path $workspace 'README.md')
 $fixedRuntime=Join-Path $temp 'maintenance-runtime';Copy-Item -LiteralPath $workspace -Destination $fixedRuntime -Recurse
 Copy-Item -LiteralPath (Join-Path $sourceRoot 'framework/user-package/AGENTS.md') -Destination (Join-Path $fixedRuntime 'AGENTS.md')
 SealRuntimeFixture $fixedRuntime
 $maintenanceRegister=Join-Path $fixedRuntime 'scripts/register-project.ps1'
 & $git -C $workspace init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_TARGET_GIT_INIT'}
 $maintenance=Join-Path $temp 'maintenance';$null=[IO.Directory]::CreateDirectory($maintenance);& $git -C $maintenance init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_CONTROL_GIT_INIT'}
 $maintenanceArgs=@{ProjectId='maintenance-fixture';DisplayName='Maintenance fixture';RepositoryPath=$maintenance;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$fixedRuntime;ControlPlaneLayout='framework-maintenance-sibling';FrameworkTargetRepositoryId='fixture-target';FrameworkTargetSiblingDirectory='framework';Apply=$true}
  $maintenancePreview=$maintenanceArgs.Clone();$maintenancePreview.Remove('Apply')
  $beforeMaintenance=Snapshot $maintenance
  $maintenanceHealthy=InvokeTool $maintenanceRegister $maintenancePreview
  $maintenanceHealthyReply=@($maintenanceHealthy.value)[-1]
  Check ($maintenanceHealthy.code-eq0-and$maintenanceHealthyReply-is[pscustomobject]-and$null-ne$maintenanceHealthyReply.PSObject.Properties['status']-and$maintenanceHealthyReply.status-is[string]-and$maintenanceHealthyReply.status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-package-valid-frontdoor-baseline-before'
 $packageManifestPath=Join-Path $fixedRuntime 'PACKAGE_MANIFEST.json';$packageManifestBytes=[IO.File]::ReadAllBytes($packageManifestPath)
 try{
  [IO.File]::Delete($packageManifestPath)
  $rejected=InvokeTool $maintenanceRegister $maintenanceArgs
  Check ($rejected.code-ne0-and$rejected.text.Contains('DISTRIBUTION_MANIFEST_REQUIRED')-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-missing-fixed-package-rejected-before-write'
 }finally{[IO.File]::WriteAllBytes($packageManifestPath,$packageManifestBytes)}
 $runtimeReadme=Join-Path $fixedRuntime 'README.md';$readmeBytes=[IO.File]::ReadAllBytes($runtimeReadme)
 try{
  SaveText $runtimeReadme 'Damaged isolated runtime payload.'
  $rejected=InvokeTool $maintenanceRegister $maintenanceArgs
  Check ($rejected.code-ne0-and$rejected.text.Contains('DISTRIBUTION_CONTENT_DRIFT|README.md')-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-damaged-fixed-package-rejected-before-write'
  }finally{[IO.File]::WriteAllBytes($runtimeReadme,$readmeBytes)}
  $maintenanceRestored=InvokeTool $maintenanceRegister $maintenancePreview
  $maintenanceRestoredReply=@($maintenanceRestored.value)[-1]
  Check ($maintenanceRestored.code-eq0-and$maintenanceRestoredReply-is[pscustomobject]-and$null-ne$maintenanceRestoredReply.PSObject.Properties['status']-and$maintenanceRestoredReply.status-is[string]-and$maintenanceRestoredReply.status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-package-valid-frontdoor-baseline-after'
 $badTopology=$maintenanceArgs.Clone();$badTopology.FrameworkTargetSiblingDirectory='missing-target'
 $rejected=InvokeTool $maintenanceRegister $badTopology
 Check ($rejected.code-ne0-and$rejected.text.Contains('TARGET_ROOT')-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-wrong-target-topology-rejected-before-write'
 $rejected=InvokeTool $register $maintenanceArgs
 Check ($rejected.code-ne0-and$rejected.text.Contains('DISTRIBUTION_MANIFEST_REQUIRED')-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-source-tool-cannot-claim-selected-fixed-runtime'
 $toolCopy=Join-Path $temp 'maintenance-tool-copy';Copy-Item -LiteralPath $fixedRuntime -Destination $toolCopy -Recurse
 $copyRegister=Join-Path $toolCopy 'scripts/register-project.ps1';$previewMaintenance=$maintenanceArgs.Clone();$previewMaintenance.Apply=$false
 $copyPreview=RunTool $copyRegister $previewMaintenance
 Check (@($copyPreview)[-1].status-ceq'WHAT_IF'-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-exact-fixed-tool-copy-may-preview-selected-runtime'
 SaveText (Join-Path $toolCopy 'README.md') 'A different internally consistent test distribution.';SealRuntimeFixture $toolCopy
 $rejected=InvokeTool $copyRegister $maintenanceArgs
 Check ($rejected.code-ne0-and$rejected.text.Contains('MAINTENANCE_EXECUTING_DISTRIBUTION_DRIFT')-and(Test-PristineSnapshotPreserved $maintenance $beforeMaintenance)) 'maintenance-other-valid-tool-distribution-rejected-before-write'
 $defaultMaintenance=$maintenanceArgs.Clone();$defaultMaintenance.Remove('WorkspaceRoot')
 $null=RunTool $maintenanceRegister $defaultMaintenance
 $maintenancePath=Join-Path $maintenance '.ai-workspace/project.json';$maintenanceConfig=Get-Content $maintenancePath -Raw|ConvertFrom-Json
 Check ($maintenanceConfig.schemaVersion-eq7-and$maintenanceConfig.processPolicy.schemaVersion-eq3-and$maintenanceConfig.sourceBindings-is[array]) 'maintenance-registers-target-profile-project6'
 $status=[IO.File]::ReadAllText((Join-Path $maintenance '.ai-workspace/STATUS.md'))
 Check ($status.Contains('framework-maintenance-sibling')-and$status.Contains('[项目配置](project.json)')-and$status.Contains('- Current task：none。')-and-not$status.Contains('repository root `..`')) 'maintenance-status-uses-actual-layout-and-config-navigation'
 $adopted=Get-AiwAdoptedDistributionBinding $maintenance '2.0.0'
 Check ($adopted.runtimeRoot-ceq$fixedRuntime-and$adopted.manifestIdentity-ceq(Identity $packageManifestPath)) 'maintenance-default-tool-root-records-real-fixed-registration-binding'
 $maintenanceConfig.frameworkCapabilities=($goodConfig|ConvertFrom-Json).frameworkCapabilities;$maintenanceConfig.sourceBindings=($goodConfig|ConvertFrom-Json).sourceBindings;SaveJson $maintenancePath $maintenanceConfig
 $null=RunTool $maintenanceRegister $maintenanceArgs
 $maintenanceResolver=Join-Path $fixedRuntime 'scripts/resolve-framework-maintenance-target.ps1'
 $resolved=RunTool $maintenanceResolver @{ControlRepositoryPath=$maintenance;ExpectedProjectConfigIdentity=(Identity $maintenancePath);AsJson=$true}
 Check ($resolved.status-ceq'PASS'-and$resolved.controlRoot-ceq$maintenance-and$resolved.targetRoot-ceq$workspace-and$resolved.runtimeRoot-ceq$fixedRuntime) 'maintenance-multi-source-config-preserves-real-sibling-topology'
 $maintenanceConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled=$false;$maintenanceConfig.sourceBindings[1].locator.root='C:unsafe';SaveJson $maintenancePath $maintenanceConfig
 $resolved=InvokeTool $maintenanceResolver @{ControlRepositoryPath=$maintenance;ExpectedProjectConfigIdentity=(Identity $maintenancePath);AsJson=$true}
 Check ($resolved.code-ne0-and$resolved.text.Contains('SOURCE_DENIED')) 'maintenance-rejects-invalid-disabled-source-using-common-validator'
 $outside=Join-Path $temp 'outside';$null=[IO.Directory]::CreateDirectory((Join-Path $outside 'child'));$junction=Join-Path $temp 'root-link'
 $beforeOutside=Snapshot $outside
 $null=New-Item -ItemType Junction -Path $junction -Target $outside
 try{
  $parameters.RepositoryPath=Join-Path $junction 'child';$rejected=InvokeTool $register $parameters
  $afterOutside=Snapshot $outside
  Check ($rejected.code-eq1-and$rejected.text.Trim()-ceq'REPOSITORY_ROOT_REPARSE'-and$afterOutside-ceq$beforeOutside-and-not(Test-Path -LiteralPath (Join-Path $outside 'child/.ai-workspace'))) 'intermediate-root-junction-rejected-before-registration'
 }finally{Remove-Item -LiteralPath $junction -Force}
 Write-Output ('NON_GIT_ADOPTION_TESTS_PASS|checks='+$passed+'|group='+$Group+'|evidence=ISOLATED_REGISTER_LOAD_ACTIONS_SAME_PIN_AND_RECOVERY|crossVersionBridge=PENDING_W5')
}finally{
 if($null-ne$preflightModule){Remove-Module -ModuleInfo $preflightModule}
 if($null-ne$safeGitReader){Remove-Module -ModuleInfo $safeGitReader}
 $env:PATH=$oldPath
 $resolved=[IO.Path]::GetFullPath($temp);$systemTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($resolved)-cne$systemTemp-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-nongit-adoption-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if($KeepFixture){Write-Output ('B1_RETAINED_FIXTURE|'+$resolved)}elseif(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
