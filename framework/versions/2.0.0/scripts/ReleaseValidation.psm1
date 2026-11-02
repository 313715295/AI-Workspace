# @design-contract ../../../FRAMEWORK_RELEASE.md
# Production qualification integrity. Host Review/acceptance remains a separate gate.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
$script:ReleaseEvidenceOwner=@(Import-Module (Join-Path $PSScriptRoot 'TestEvidenceValidation.psm1') -PassThru)[0]
$script:ReleaseUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:ReleaseScope='all release payload files except RELEASE_MANIFEST.json and exact declared validation evidence members'
$script:ReleaseAlgorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload'
$script:ReleaseDiagnostic=$null
$script:ReleaseNavigationOwner=$null
$script:ReleaseNavigationCommand=$null
$script:ReleaseNavigationBody=$null
function Write-AiwReleaseDiagnostic([string]$Stage,$Facts){
 if($null-ne$script:ReleaseDiagnostic){$null=& $script:ReleaseDiagnostic ([pscustomobject]@{stage=$Stage;facts=$Facts})}
}
function Assert-AiwReleaseFields($Value,[string[]]$Fields,[string]$Label){
 if($Value-isnot[pscustomobject]){throw ('RELEASE_FIELDS|'+$Label)}
 [string[]]$actual=@(foreach($property in $Value.PSObject.Properties){[string]$property.Name})
 if($actual.Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$actual}).Count){throw ('RELEASE_FIELDS|'+$Label)}
}
function Assert-AiwReleaseStringFields($Value,[string[]]$Fields,[string]$Label){
 foreach($field in $Fields){if($Value.$field-isnot[string]){throw ('RELEASE_STRING|'+$Label+'|'+$field)}}
}
function Assert-AiwReleasePath([string]$Path){
 if($Path-match'(?i)[\\/]src[\\/]config[\\/]levels[\\/]level_test2\.js$'){throw 'RELEASE_PROTECTED_PATH'}
 $full=[IO.Path]::GetFullPath($Path);$walk=$full
 while($walk){if(Test-Path -LiteralPath $walk){if((Get-Item -LiteralPath $walk -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'RELEASE_REPARSE'}};$walk=Split-Path -Parent $walk}
 return $full
}
function Assert-AiwReleaseLocator([string]$Path){
 if([string]::IsNullOrWhiteSpace($Path)-or$Path-cmatch'^[A-Za-z]:|^[/\\]|\\|:|(^|/)\.{1,2}(/|$)|//|/$'){throw 'RELEASE_LOCATOR'}
 if($Path-match'(?i)(^|/)src/config/levels/level_test2\.js$'){throw 'RELEASE_PROTECTED_PATH'}
}
function Get-AiwReleaseChild([string]$Root,[string]$Relative){
 Assert-AiwReleaseLocator $Relative
 $full=Assert-AiwReleasePath $Root;$child=Assert-AiwReleasePath (Join-Path $full $Relative)
 if(-not$child.StartsWith([IO.Path]::TrimEndingDirectorySeparator($full)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'RELEASE_OUTSIDE_ROOT'}
 return $child
}
function Get-AiwReleaseByteIdentity([byte[]]$Bytes){return $Bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Get-AiwReleaseFileIdentity([string]$Path){$full=Assert-AiwReleasePath $Path;return Get-AiwReleaseByteIdentity ([IO.File]::ReadAllBytes($full))}
function Read-AiwReleaseJson([string]$Path,[string[]]$StringFields=@(),[string[]]$NullableStringFields=@()){$full=Assert-AiwReleasePath $Path;return (Read-AiwStrictInputJson $full -StringFields $StringFields -NullableStringFields $NullableStringFields).Value}
function ConvertFrom-AiwReleaseBytes([byte[]]$Bytes,[string[]]$StringFields=@(),[string[]]$NullableStringFields=@()){
 # Parse exactly the bytes whose identity was checked, never reopen a member.
 if($Bytes.Length-ge3-and$Bytes[0]-eq239-and$Bytes[1]-eq187-and$Bytes[2]-eq191){throw 'INPUT_BOM'}
 try{$text=$script:ReleaseUtf8.GetString($Bytes)}catch{throw 'INPUT_UTF8'}
 # The shared parser's PowerShell recursion is expensive on the large index.
 # Keep its exact validation/materialization contract, using the platform JSON
 # tree for the duplicate walk. The helper has no mutable state or cache.
 if($null-eq$script:ReleaseJsonValidator){
  $source=@'
using System;
using System.Collections.Generic;
using System.Text.Json;
namespace AIW_RELEASE_JSON_NAMESPACE {
 public static class Validator {
  static void Members(JsonElement element) {
   if(element.ValueKind==JsonValueKind.Object) {
    var seen=new HashSet<string>(StringComparer.Ordinal);
    foreach(var property in element.EnumerateObject()) {
     if(!seen.Add(property.Name)) throw new Exception("INPUT_FIELD_COUNT|"+property.Name);
     Members(property.Value);
    }
   } else if(element.ValueKind==JsonValueKind.Array) {
    foreach(var item in element.EnumerateArray()) Members(item);
   }
  }
  public static Dictionary<string,object> Validate(string text,string[] strings,string[] nullable) {
   if(text.Length>0 && text[0]=='\uFEFF') throw new Exception("INPUT_BOM");
   if(text.IndexOf('\0')>=0 || text.IndexOf('\uFFFD')>=0) throw new Exception("INPUT_TEXT_FORMAT");
   JsonDocument document;
   try { document=JsonDocument.Parse(text); } catch { throw new Exception("INPUT_JSON"); }
   using(document) {
    if(document.RootElement.ValueKind!=JsonValueKind.Object) throw new Exception("INPUT_OBJECT_TYPE");
    Members(document.RootElement);
    var result=new Dictionary<string,object>(StringComparer.Ordinal);
    var nullableSet=new HashSet<string>(nullable,StringComparer.Ordinal);
    foreach(var field in Concat(strings,nullable)) {
     if(String.IsNullOrWhiteSpace(field) || result.ContainsKey(field)) throw new Exception("INPUT_STRING_FIELDS");
     JsonElement token;
     if(!document.RootElement.TryGetProperty(field,out token)) throw new Exception("INPUT_STRING_FIELD_MISSING|"+field);
     if(token.ValueKind==JsonValueKind.String) result.Add(field,token.GetString());
     else if(nullableSet.Contains(field) && token.ValueKind==JsonValueKind.Null) result.Add(field,null);
     else throw new Exception("INPUT_STRING_FIELD_TYPE|"+field);
    }
    return result;
   }
  }
  static IEnumerable<string> Concat(string[] first,string[] second) {
   foreach(var value in first) yield return value;
   foreach(var value in second) yield return value;
  }
 }
}
'@
  $name='AiwReleaseJson'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:ReleaseUtf8.GetBytes($source)))
  $typeName=$name+'.Validator';$script:ReleaseJsonValidator=$typeName-as[type]
  if($null-eq$script:ReleaseJsonValidator){Add-Type -TypeDefinition $source.Replace('AIW_RELEASE_JSON_NAMESPACE',$name);$script:ReleaseJsonValidator=$typeName-as[type]}
 }
 try{$strings=$script:ReleaseJsonValidator::Validate($text,$StringFields,$NullableStringFields)}catch{throw $_.Exception.GetBaseException().Message}
 try{$value=$text|ConvertFrom-Json -Depth 100}catch{throw 'INPUT_JSON'}
 foreach($field in $strings.Keys){$value.PSObject.Properties[$field].Value=$strings[$field]}
 return $value
}
$script:ReleaseJsonValidator=$null
function ConvertTo-AiwReleaseEvidenceTime($Value,[string]$Label,[switch]$Nullable){
 if($Nullable-and$null-eq$Value){return $null}
 $time=[DateTimeOffset]::MinValue
 if($Value-isnot[string]-or$Value-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$'-or-not[DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$time)){throw ('RELEASE_EVIDENCE_TIME|'+$Label)}
 return $time
}
function Assert-AiwReleaseCurrentSuiteShape($Suite,[string]$DefinitionIdentity,[string[]]$Required,[switch]$Complete){
 Assert-AiwReleaseFields $Suite (@('schemaVersion','phase','definitionIdentity','requestedGroupIds','requiredGroupIds','records','outcome','coverage','options','startedUtc','endedUtc','qualification','sourceRoot','sourceInputsRef')+$(if($Suite.schemaVersion-eq3){@('verifierRef')}else{@()})) 'current-suite'
 Assert-AiwReleaseStringFields $Suite @('phase','definitionIdentity','outcome','coverage','qualification','sourceRoot') 'current-suite'
 if($Suite.schemaVersion-isnot[long]-and$Suite.schemaVersion-isnot[int]-or$Suite.schemaVersion-notin@(2,3)-or$Suite.phase-cne'PREPACKAGE'-or$Suite.definitionIdentity-cne$DefinitionIdentity-or$Suite.qualification-cne'SOURCE_VALIDATION_ONLY'-or$Suite.records-isnot[Array]-or$Suite.requestedGroupIds-isnot[Array]-or$Suite.requiredGroupIds-isnot[Array]-or[IO.Path]::IsPathFullyQualified($Suite.sourceRoot)-eq$false){throw 'RELEASE_CURRENT_SUITE_BINDING'}
 Assert-AiwReleaseFields $Suite.sourceInputsRef @('path','identity') 'current-suite-inputs'
 Assert-AiwReleaseStringFields $Suite.sourceInputsRef @('path','identity') 'current-suite-inputs'
 Assert-AiwReleaseFields $Suite.options @('SkipManifest','SkipBaseline','SkipPerformanceSmoke','MaintenanceFixture') 'current-suite-options'
 foreach($field in $Suite.options.PSObject.Properties){if($field.Value-isnot[bool]){throw 'RELEASE_CURRENT_SUITE_OPTIONS'}}
 $start=ConvertTo-AiwReleaseEvidenceTime $Suite.startedUtc 'suite-start';$end=ConvertTo-AiwReleaseEvidenceTime $Suite.endedUtc 'suite-end'
 if($end-lt$start){throw 'RELEASE_CURRENT_SUITE_WINDOW'}
 if((Get-AiwReleaseValueIdentity @($Suite.requiredGroupIds))-cne(Get-AiwReleaseValueIdentity @($Required))){throw 'RELEASE_CURRENT_SUITE_REQUIRED'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($id in $Suite.requestedGroupIds){if($id-isnot[string]-or-not$seen.Add($id)){throw 'RELEASE_CURRENT_SUITE_PARTITION'}}
 if($Complete-and($Suite.outcome-cne'PASS'-or$Suite.coverage-cne'COMPLETE'-or$seen.Count-ne$Required.Count-or@($Required|Where-Object{-not$seen.Contains($_)}).Count-or$Suite.options.SkipManifest-or$Suite.options.SkipBaseline-or$Suite.options.SkipPerformanceSmoke)){throw 'RELEASE_CURRENT_SUITE_NOT_COMPLETE'}
 $records=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($ref in $Suite.records){
  Assert-AiwReleaseFields $ref @('groupId','path','identity','executionKind','revalidation') 'current-suite-record'
  Assert-AiwReleaseStringFields $ref @('groupId','path','identity','executionKind') 'current-suite-record'
  if(-not$records.Add($ref.groupId)-or-not$seen.Contains($ref.groupId)-or$ref.executionKind-cnotin@('EXECUTED','REVALIDATED')-or($ref.executionKind-ceq'EXECUTED'-and$null-ne$ref.revalidation)){throw 'RELEASE_CURRENT_SUITE_PARTITION'}
  if($ref.executionKind-ceq'REVALIDATED'){Assert-AiwReleaseFields $ref.revalidation @('path','identity') 'current-suite-revalidation';Assert-AiwReleaseStringFields $ref.revalidation @('path','identity') 'current-suite-revalidation'}
 }
 if($records.Count-ne$seen.Count){throw 'RELEASE_CURRENT_SUITE_PARTITION'}
}
function Assert-AiwReleaseCurrentRevalidation($Validation,$Original,$Group,$Snapshot,$Suite){
 if($Suite.schemaVersion-eq3){if($Validation.schemaVersion-isnot[int]-and$Validation.schemaVersion-isnot[long]-or$Validation.schemaVersion-ne2){throw 'RELEASE_CURRENT_REVALIDATION_SCALAR'};Assert-AiwEvidenceRevalidation $Validation $Original $Group $Snapshot $Suite;return}
 if($Validation.schemaVersion-eq2){Assert-AiwEvidenceRevalidation $Validation $Original $Group $Snapshot $Suite;return}
 Assert-AiwReleaseFields $Validation @('schemaVersion','executionKind','groupId','original','currentSnapshot','validatorIdentity','checkedUtc','outcome','reason') 'revalidation'
 Assert-AiwReleaseFields $Validation.original @('path','identity') 'revalidation-original';Assert-AiwReleaseStringFields $Validation.original @('path','identity') 'revalidation-original'
 Assert-AiwReleaseFields $Validation.currentSnapshot @('facts','identity') 'revalidation-snapshot'
 Assert-AiwReleaseStringFields $Validation @('executionKind','groupId','validatorIdentity','outcome','reason') 'revalidation'
 if($Validation.schemaVersion-isnot[long]-and$Validation.schemaVersion-isnot[int]-or$Validation.schemaVersion-ne1-or$Validation.executionKind-cne'REVALIDATED'-or$Validation.outcome-cne'PASS'-or$Validation.groupId-cne$Group.id-or$Validation.reason-cne'Original execution, raw, cleanup, command and current complete closure verified'){throw 'RELEASE_CURRENT_REVALIDATION_SCALAR'}
 if($Group.alwaysFresh-or@($Group.unknownDependencies).Count){throw 'RELEASE_CURRENT_REVALIDATION_FRESH_REQUIRED'}
 if($Validation.original.path-cne$Original.path-or$Validation.original.identity-cne$Original.identity-or$Validation.currentSnapshot.identity-cne$Snapshot.identity-or(Get-AiwReleaseValueIdentity $Validation.currentSnapshot.facts)-cne$Snapshot.identity-or$Validation.validatorIdentity-cne$Snapshot.facts.validatorIdentity-or$Validation.currentSnapshot.facts.rootSensitive-isnot[bool]-or-not$Validation.currentSnapshot.facts.rootSensitive){throw 'RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT'}
 if($Suite-and($Validation.currentSnapshot.facts.root-cne$Suite.sourceRoot-or(Get-AiwReleaseValueIdentity $Validation.currentSnapshot.facts.options)-cne(Get-AiwReleaseValueIdentity $Suite.options))){throw 'RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS'}
 $checked=ConvertTo-AiwReleaseEvidenceTime $Validation.checkedUtc 'revalidation-checked'
 if($Suite-and($checked-lt(ConvertTo-AiwReleaseEvidenceTime $Suite.startedUtc 'suite-start')-or$checked-gt(ConvertTo-AiwReleaseEvidenceTime $Suite.endedUtc 'suite-end'))){throw 'RELEASE_CURRENT_REVALIDATION_WINDOW'}
}
function Assert-AiwReleaseCurrentExecution($Record,$Process,$Launch,$Group,$Suite){
 Assert-AiwReleaseFields $Process @('runId','status','command','pid','creationUtc','executor','directConsumer','startedUtc','processExitedUtc','endedUtc','exitCode','stdout','stderr','timing','cancellation','streamOrdering') 'process'
 Assert-AiwReleaseFields $Launch @('runId','pid','creationUtc','startedUtc','executable','executableIdentity','executableVersion','arguments','cwd','environmentNames','raw','resultPath','executor','directConsumer') 'launch'
 Assert-AiwReleaseStringFields $Process @('runId','status','executor','directConsumer','streamOrdering') 'current-process'
 Assert-AiwReleaseStringFields $Launch @('runId','executable','executableIdentity','executableVersion','cwd','resultPath','executor','directConsumer') 'current-launch'
 if(($Process.pid-isnot[long]-and$Process.pid-isnot[int])-or$Process.pid-lt1-or($Launch.pid-isnot[long]-and$Launch.pid-isnot[int])-or$Launch.pid-ne$Process.pid-or$Process.status-cne'PASS'-or($Process.exitCode-isnot[long]-and$Process.exitCode-isnot[int])-or$Process.exitCode-ne0-or$null-ne$Process.cancellation-or$Launch.runId-cne$Process.runId-or$Launch.resultPath-cne$Record.processResult.path-or$Launch.cwd-cne$Process.command.cwd-or$Launch.executable-cne$Process.command.executable-or$Launch.executableIdentity-cne$Process.command.executableIdentity-or$Launch.executableVersion-cne$Process.command.executableVersion-or$Launch.executor-cne$Process.executor-or$Launch.directConsumer-cne$Process.directConsumer-or$Launch.arguments-isnot[Array]-or$Launch.raw-isnot[Array]-or$Launch.environmentNames-isnot[Array]-or(Get-AiwReleaseValueIdentity @($Launch.arguments))-cne(Get-AiwReleaseValueIdentity @($Process.command.arguments))-or(Get-AiwReleaseValueIdentity @($Launch.raw))-cne(Get-AiwReleaseValueIdentity @($Process.stdout.path,$Process.stderr.path))){throw 'RELEASE_CURRENT_EXECUTION_LAUNCH'}
 Assert-AiwReleaseStringFields $Record @('executionKind','groupId','phase','outcome','validatorIdentity') 'current-execution'
 if($Record.schemaVersion-isnot[long]-and$Record.schemaVersion-isnot[int]-or$Record.schemaVersion-ne1-or$Record.executionKind-cne'EXECUTED'-or$Record.groupId-cne$Group.id-or$Record.phase-cne'PREPACKAGE'-or$Record.outcome-cne'PASS'){throw 'RELEASE_CURRENT_EXECUTION_SCALAR'}
 if($Record.after.facts.rootSensitive-isnot[bool]-or-not$Record.after.facts.rootSensitive-or$Record.after.facts.root-isnot[string]-or$Record.after.facts.root-cne$Suite.sourceRoot-or(Get-AiwReleaseValueIdentity $Record.after.facts.options)-cne(Get-AiwReleaseValueIdentity $Suite.options)-or(Get-AiwReleaseValueIdentity @($Record.after.facts.unknownDependencies))-cne(Get-AiwReleaseValueIdentity @($Group.unknownDependencies))){throw 'RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS'}
 $suiteStart=ConvertTo-AiwReleaseEvidenceTime $Suite.startedUtc 'suite-start';$suiteEnd=ConvertTo-AiwReleaseEvidenceTime $Suite.endedUtc 'suite-end'
 $start=ConvertTo-AiwReleaseEvidenceTime $Record.startedUtc 'record-start';$end=ConvertTo-AiwReleaseEvidenceTime $Record.endedUtc 'record-end'
 $processStart=ConvertTo-AiwReleaseEvidenceTime $Process.startedUtc 'process-start';$processEnd=ConvertTo-AiwReleaseEvidenceTime $Process.endedUtc 'process-end'
 $exited=ConvertTo-AiwReleaseEvidenceTime $Process.processExitedUtc 'process-exit' -Nullable
 $created=ConvertTo-AiwReleaseEvidenceTime $Process.creationUtc 'process-creation' -Nullable
 $launchStart=ConvertTo-AiwReleaseEvidenceTime $Launch.startedUtc 'launch-start';$launchCreated=ConvertTo-AiwReleaseEvidenceTime $Launch.creationUtc 'launch-creation' -Nullable
 if($start-lt$suiteStart-or$end-gt$suiteEnd-or$end-lt$start-or$start-ne$processStart-or$end-ne$processEnd-or$launchStart-ne$start-or$null-eq$exited-or$null-eq$created-or$null-eq$launchCreated-or$created-lt$start-or$created-gt$exited-or$exited-gt$end-or$launchCreated-ne$created){throw 'RELEASE_CURRENT_EXECUTION_WINDOW'}
}
function Get-AiwReleaseCanonical($Value){ return Get-AiwEvidenceCanonical $Value }
function Get-AiwReleaseValueIdentity($Value){return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:ReleaseUtf8.GetBytes((Get-AiwReleaseCanonical $Value))))}
function Get-AiwReleaseTreeSnapshot([string]$Root,[string[]]$ExcludePaths=@(),[switch]$CaptureBytes){
 $full=Assert-AiwReleasePath $Root;$stack=[Collections.Generic.Stack[string]]::new();$stack.Push($full)
 $rows=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 $bytesByPath=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 while($stack.Count){
  $dir=$stack.Pop()
  if((Get-Item -LiteralPath $dir -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'RELEASE_REPARSE'}
  foreach($item in Get-ChildItem -LiteralPath $dir -Force){
   # The root's ancestors were checked above. Visit each immediate child and
   # each directory before descending; do not repeatedly walk every ancestor.
   if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'RELEASE_REPARSE'}
   $relative=[IO.Path]::GetRelativePath($full,$item.FullName).Replace('\','/');Assert-AiwReleaseLocator $relative
   if($item.PSIsContainer){$stack.Push($item.FullName);continue}
   if($relative-cin$ExcludePaths){continue}
   if(-not$seen.Add($relative)){throw 'RELEASE_CASE_ALIAS'}
   $raw=[IO.File]::ReadAllBytes($item.FullName)
   $rows.Add($relative,@{path=$relative;identity=(Get-AiwReleaseByteIdentity $raw)})
   if($CaptureBytes){$bytesByPath.Add($relative,$raw)}
  }
 }
 $null=Assert-AiwReleasePath $full
 [string[]]$paths=@($rows.Keys);[Array]::Sort($paths,[StringComparer]::Ordinal)
 return [pscustomobject]@{Members=@(foreach($path in $paths){$rows[$path]});Bytes=$bytesByPath}
}
function Get-AiwReleaseTreeMembers([string]$Root,[string[]]$ExcludePaths=@()){
 return @((Get-AiwReleaseTreeSnapshot $Root $ExcludePaths).Members)
}
function Get-AiwReleaseMemberFacts($Members){
 $byPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($member in $Members){if($byPath.ContainsKey($member.path)-or$member.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'RELEASE_MEMBER_IDENTITY'};$byPath.Add($member.path,$member)}
 [string[]]$paths=@($byPath.Keys);[Array]::Sort($paths,[StringComparer]::Ordinal);$rows=@();[long]$bytes=0
 foreach($path in $paths){$member=$byPath[$path];$bytes+=[long]$member.identity.Split('|')[0];$rows+=($path+'|'+$member.identity)}
 return [pscustomobject]@{FileCount=$paths.Count;TotalBytes=$bytes;Canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:ReleaseUtf8.GetBytes($rows-join"`n")));Files=$paths;Rows=$rows;Members=@($Members)}
}
function Get-AiwReleasePayloadFacts([string]$VersionRoot,[string[]]$EvidenceMembers=@(),[switch]$SourceView){
 if($SourceView){
  $inventory=Read-AiwReleaseJson (Get-AiwReleaseChild $VersionRoot 'NORMATIVE_SURFACE_INVENTORY.json');$members=@();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $paths=@(@($inventory.runtimeNormativeModules|ForEach-Object{$_.document;$_.fragment})+@($inventory.actionRequiredArtifacts)+@($inventory.schemaAndMechanicalInputs)+@($inventory.explanationAndHistory)|Where-Object{$_-cne'RELEASE_MANIFEST.json'})
  foreach($path in $paths){Assert-AiwReleaseLocator $path;if(-not$seen.Add($path)-or$path.StartsWith('validation-evidence/',[StringComparison]::Ordinal)){throw 'RELEASE_SOURCE_VIEW_INVENTORY'};$members+=@{path=$path;identity=(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot $path))}}
  return Get-AiwReleaseMemberFacts $members
 }
 $members=@(Get-AiwReleaseTreeMembers $VersionRoot -ExcludePaths @('RELEASE_MANIFEST.json'));$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($path in $EvidenceMembers){Assert-AiwReleaseLocator $path;if(-not$path.StartsWith('validation-evidence/prepackage/',[StringComparison]::Ordinal)-or-not$seen.Add($path)){throw 'RELEASE_ATTACHMENT_SET'}}
 foreach($member in $members){if($member.path.StartsWith('validation-evidence/',[StringComparison]::Ordinal)-and-not$seen.Contains($member.path)){throw 'RELEASE_UNDECLARED_ATTACHMENT'}}
 return Get-AiwReleaseMemberFacts @($members|Where-Object{$_.path-cne'RELEASE_MANIFEST.json'-and-not$seen.Contains($_.path)})
}
function Assert-AiwReleaseRef($Ref,[string]$Label){Assert-AiwReleaseFields $Ref @('path','identity') $Label;Assert-AiwReleaseLocator $Ref.path;if($Ref.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'RELEASE_REF_IDENTITY'}}
function Get-AiwReleaseBundle([string]$VersionRoot,$Proof){
 Assert-AiwReleaseRef $Proof.proofBundleRef 'bundle-ref'
 if($Proof.proofBundleRef.path-cne'validation-evidence/prepackage/index.json'){throw 'RELEASE_BUNDLE_INDEX_LOCATOR'}
 $tree=Get-AiwReleaseTreeSnapshot (Get-AiwReleaseChild $VersionRoot 'validation-evidence/prepackage') -CaptureBytes
 if(-not$tree.Bytes.ContainsKey('index.json')){throw 'INPUT_MISSING'}
 $indexBytes=$tree.Bytes['index.json']
 if((Get-AiwReleaseByteIdentity $indexBytes)-cne$Proof.proofBundleRef.identity){throw 'RELEASE_BUNDLE_INDEX_DRIFT'}
 $index=ConvertFrom-AiwReleaseBytes $indexBytes
 Assert-AiwReleaseFields $index @('schemaVersion','kind','members','aliases','inputBindings','sourceInputClosureMemberId') 'bundle-index'
 if($index.schemaVersion-ne$(if($Proof.schemaVersion-eq3){2}else{1})-or$index.kind-cne'PREPACKAGE_EVIDENCE_BUNDLE'-or$index.members-isnot[Array]-or$index.aliases-isnot[Array]-or$index.inputBindings-isnot[Array]){throw 'RELEASE_BUNDLE_SCHEMA'}
 $byId=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$byPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$bytesById=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal);$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$members=@(@{path=$Proof.proofBundleRef.path;identity=$Proof.proofBundleRef.identity})
 foreach($member in $index.members){
  Assert-AiwReleaseFields $member @('id','kind','path','identity') 'bundle-member'
  Assert-AiwReleaseLocator $member.path
  if($member.id-cnotmatch'^[a-zA-Z0-9.-]+$'-or$byId.ContainsKey($member.id)-or-not$paths.Add($member.path)-or$member.path-ceq$Proof.proofBundleRef.path-or-not$member.path.StartsWith('validation-evidence/prepackage/',[StringComparison]::Ordinal)-or$member.kind-cnotin@('GROUP_RECORD','PROCESS_RESULT','PROCESS_LAUNCH','STDOUT','STDERR','PHASE_EVENTS','INPUT_CLOSURE','REVALIDATION','BASELINE_CLOSURE','CURRENT_SUITE','EXECUTION_TARGET_DESCRIPTOR')-or($member.kind-ceq'CURRENT_SUITE'-and$Proof.schemaVersion-notin@(2,3))-or($member.kind-ceq'EXECUTION_TARGET_DESCRIPTOR'-and$Proof.schemaVersion-ne3)){throw 'RELEASE_BUNDLE_MEMBER'}
  $relative=$member.path.Substring('validation-evidence/prepackage/'.Length)
  if(-not$tree.Bytes.ContainsKey($relative)){throw 'RELEASE_BUNDLE_MEMBER_DRIFT'}
  $raw=$tree.Bytes[$relative]
  if($member.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-AiwReleaseByteIdentity $raw)-cne$member.identity){throw 'RELEASE_BUNDLE_MEMBER_DRIFT'}
  $byId[$member.id]=$member;$byPath[$member.path]=$member;$bytesById[$member.id]=$raw;$members+=@{path=$member.path;identity=$member.identity}
 }
 $actual=@($tree.Members|ForEach-Object{'validation-evidence/prepackage/'+$_.path})
 if($actual.Count-ne$members.Count-or@($actual|Where-Object{$_-cnotin$members.path}).Count-or(Get-AiwReleaseMemberFacts $members).Canonical-cne$Proof.proofBundleIdentity){throw 'RELEASE_BUNDLE_SET_OR_CANONICAL'}
 $aliases=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($alias in $index.aliases){Assert-AiwReleaseFields $alias @('ownerMemberId','slot','originalLocator','originalIdentity','targetMemberId') 'alias';$key=$alias.ownerMemberId+'|'+$alias.slot;if($aliases.ContainsKey($key)-or-not$byId.ContainsKey($alias.ownerMemberId)-or-not$byId.ContainsKey($alias.targetMemberId)){throw 'RELEASE_ALIAS_DUPLICATE_DANGLING'};$aliases[$key]=$alias}
 return [pscustomobject]@{Root=$VersionRoot;Index=$index;ById=$byId;ByPath=$byPath;Bytes=$bytesById;Parsed=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);Aliases=$aliases;Members=$members;UsedAliases=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);Reached=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);CurrentSnapshots=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)}
}
function Read-AiwReleaseBundleMember($Bundle,[string]$Id,[string]$Kind,[switch]$CurrentCoverage){
 if(-not$Bundle.ById.ContainsKey($Id)-or$Bundle.ById[$Id].kind-cne$Kind){throw 'RELEASE_MEMBER_KIND'}
 $null=$Bundle.Reached.Add($Id)
 $strings=@();$nullable=@()
 if($CurrentCoverage){switch($Kind){
  'CURRENT_SUITE'{$strings=@('startedUtc','endedUtc')}
  'GROUP_RECORD'{$strings=@('startedUtc','endedUtc')}
  'PROCESS_RESULT'{$strings=@('startedUtc','endedUtc');$nullable=@('creationUtc','processExitedUtc')}
  'PROCESS_LAUNCH'{$strings=@('startedUtc');$nullable=@('creationUtc')}
  'REVALIDATION'{$strings=@('checkedUtc')}
 }}
 $key=$Id+'|'+$Bundle.ById[$Id].identity+'|'+$Kind+'|'+[string][bool]$CurrentCoverage
 if(-not$Bundle.Parsed.ContainsKey($key)){
  $value=ConvertFrom-AiwReleaseBytes $Bundle.Bytes[$Id] -StringFields $strings -NullableStringFields $nullable
  $value=Restore-AiwEvidenceContextStrings ($script:ReleaseUtf8.GetString($Bundle.Bytes[$Id])) $value
  $Bundle.Parsed.Add($key,$value)
 }
 # Only private proof operations share these objects; no caller receives them
 # until this proof operation and its final live-byte guard have completed.
 return $Bundle.Parsed[$key]
}
function Resolve-AiwReleaseAlias($Bundle,[string]$Owner,[string]$Slot,$Original,[string]$Kind){
 $key=$Owner+'|'+$Slot
 if(-not$Bundle.Aliases.ContainsKey($key)){throw 'RELEASE_ALIAS_MISSING'}
 $a=$Bundle.Aliases[$key]
 if($a.originalLocator-cne$Original.path-or$a.originalIdentity-cne$Original.identity-or$Bundle.ById[$a.targetMemberId].kind-cne$Kind-or$Bundle.ById[$a.targetMemberId].identity-cne$Original.identity){throw 'RELEASE_ALIAS_BINDING'}
 $null=$Bundle.UsedAliases.Add($key);$null=$Bundle.Reached.Add($a.targetMemberId);return $Bundle.ById[$a.targetMemberId]
}
function Get-AiwReleaseObservedCases([string]$Stdout,[string]$GroupId){
 $counts=@{};$cases=@();foreach($line in $Stdout-split'\r?\n'){if($line-cmatch'^PASS\|(.+)$'){$name=$Matches[1].Split('|')[0];if(-not$counts.ContainsKey($name)){$counts[$name]=0};$counts[$name]++;$cases+=@{id=$GroupId+'/'+$name+'#'+$counts[$name].ToString('D4');name=$name;occurrence=$counts[$name];outcome='PASS'}}};return @($cases)
}
function Get-AiwReleaseGroupBehaviorIdentity($Definition,$Group){ return Get-AiwEvidenceGroupBehaviorIdentity $Definition $Group }
function Assert-AiwReleaseBehaviorSnapshot($Snapshot,$Definition,$Group,$Suite,[string]$VersionRoot){
 Assert-AiwReleaseFields $Snapshot @('facts','identity') 'snapshot'
 $f=$Snapshot.facts
 if($f.root-cne$Suite.sourceRoot-or(Get-AiwReleaseValueIdentity $f.options)-cne(Get-AiwReleaseValueIdentity $Suite.options)){throw 'RELEASE_CURRENT_EXECUTION_ROOT_OPTIONS'}
 if((Get-AiwReleaseValueIdentity $f)-cne$Snapshot.identity-or$f.definitionIdentity-cne$Suite.definitionIdentity-or$f.groupIdentity-cne(Get-AiwReleaseGroupBehaviorIdentity $Definition $Group)-or$f.verifierIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot 'scripts/TestEvidenceValidation.psm1'))-or$f.root-cne$Suite.sourceRoot-or(Get-AiwReleaseValueIdentity $f.options)-cne(Get-AiwReleaseValueIdentity $Suite.options)-or$f.behaviorContractIdentity-cne(Get-AiwEvidenceBehaviorIdentity $f)){throw 'RELEASE_CURRENT_REVALIDATION_INPUT_DRIFT'}
}
function Assert-AiwReleasePortableGroup2($Bundle,[string]$MemberId,$Group,$Suite,[string]$ExecutionKind){
 $record=Read-AiwReleaseBundleMember $Bundle $MemberId GROUP_RECORD -CurrentCoverage
 if(-not$Bundle.CurrentSnapshots.ContainsKey($Group.id)){throw 'RELEASE_CURRENT_SNAPSHOT_REQUIRED'}
 $snapshot=$Bundle.CurrentSnapshots[$Group.id]
 $pm=Resolve-AiwReleaseAlias $Bundle $MemberId '/processResult' $record.processResult PROCESS_RESULT
 $process=Read-AiwReleaseBundleMember $Bundle $pm.id PROCESS_RESULT -CurrentCoverage
 $raw=@{};foreach($name in @('stdout','stderr')){$member=Resolve-AiwReleaseAlias $Bundle $pm.id ('/'+$name) $process.$name $name.ToUpperInvariant();$raw[$name]=$Bundle.Bytes[$member.id]}
 $runLabel=$record.processResult.path.Substring(0,[Math]::Max($record.processResult.path.LastIndexOf('/'),$record.processResult.path.LastIndexOf('\'))+1)
 foreach($extra in @(@{slot='PROCESS_LAUNCH_FOR_RUN';kind='PROCESS_LAUNCH';name='launch.json'},@{slot='PHASE_EVENTS_FOR_RUN';kind='PHASE_EVENTS';name='phases.jsonl'})){
  $key=$pm.id+'|'+$extra.slot;if(-not$Bundle.Aliases.ContainsKey($key)){throw 'RELEASE_ALIAS_MISSING'};$a=$Bundle.Aliases[$key]
  if($a.originalLocator-cne($runLabel+$extra.name)){throw 'RELEASE_ALIAS_BINDING'}
  $ref=[pscustomobject]@{path=$a.originalLocator;identity=$a.originalIdentity};$member=Resolve-AiwReleaseAlias $Bundle $pm.id $extra.slot $ref $extra.kind
  if($extra.kind-ceq'PROCESS_LAUNCH'){$launch=Read-AiwReleaseBundleMember $Bundle $member.id PROCESS_LAUNCH -CurrentCoverage}else{$phases=$Bundle.Bytes[$member.id]}
 }
 $descriptor=$null;$currentDescriptor=$null
 if($record.executionContext.targetKind-ceq'GIT_WORKTREE'){$m=Resolve-AiwReleaseAlias $Bundle $MemberId '/executionTargetRef' $record.executionContext.executionTargetRef EXECUTION_TARGET_DESCRIPTOR;$descriptor=$Bundle.Bytes[$m.id]}
 if($snapshot.facts.executionContext.targetKind-ceq'GIT_WORKTREE'){
  if((Get-AiwReleaseValueIdentity $snapshot.facts.executionContext.executionTargetRef)-ceq(Get-AiwReleaseValueIdentity $record.executionContext.executionTargetRef)){$currentDescriptor=$descriptor}else{throw 'RELEASE_CURRENT_TARGET_BINDING'}
 }
 $artifacts=[pscustomobject]@{process=$process;launch=$launch;stdoutBytes=$raw.stdout;stderrBytes=$raw.stderr;phaseBytes=$phases;descriptorBytes=$descriptor;currentDescriptorBytes=$currentDescriptor}
 $null=Assert-AiwEvidenceNativeRecord $record $Group $snapshot $artifacts -ForReuse:($ExecutionKind-ceq'REVALIDATED') -Suite $Suite
 return $record
}
function Assert-AiwReleasePortableGroup($Bundle,[string]$MemberId,$Group,[switch]$CurrentCoverage,$Suite,[string]$ExecutionKind){
 $record=Read-AiwReleaseBundleMember $Bundle $MemberId GROUP_RECORD -CurrentCoverage:$CurrentCoverage
 if($record.schemaVersion-eq2){if(-not$CurrentCoverage-or$Suite.schemaVersion-ne3){throw 'RELEASE_EXECUTION2_SUITE3_REQUIRED'};return Assert-AiwReleasePortableGroup2 $Bundle $MemberId $Group $Suite $ExecutionKind}
 Assert-AiwReleaseFields $record @('schemaVersion','executionKind','groupId','phase','before','after','processResult','startedUtc','endedUtc','outcome','cases','completion','cleanup','validatorIdentity','omissions') 'executed'
 if($record.schemaVersion-ne1-or$record.executionKind-cne'EXECUTED'-or$record.phase-cne'PREPACKAGE'-or$Group.phase-cne'PREPACKAGE'-or$record.groupId-cne$Group.id-or$record.outcome-cne'PASS'-or@($record.omissions).Count){throw 'RELEASE_GROUP_NOT_PASS'}
 if($record.after.facts.groupIdentity-cne(Get-AiwReleaseValueIdentity $Group)-or$record.after.facts.definitionIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $Bundle.Root 'tests/test-groups.json'))-or$record.after.facts.inputView-cne'SOURCE_PAYLOAD_V1'){throw 'RELEASE_GROUP_DEFINITION_OR_VIEW'}
 if($record.before.identity-cne$record.after.identity-or(Get-AiwReleaseValueIdentity $record.before.facts)-cne$record.before.identity-or(Get-AiwReleaseValueIdentity $record.after.facts)-cne$record.after.identity-or$record.validatorIdentity-cne$record.after.facts.validatorIdentity){throw 'RELEASE_GROUP_INPUT_DRIFT'}
 if($record.validatorIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $Bundle.Root 'tests/TestGroupEvidence.psm1'))-or(@($record.after.facts.unknownDependencies).Count-and(-not$CurrentCoverage-or$ExecutionKind-cne'EXECUTED'))){throw 'RELEASE_GROUP_VALIDATOR_OR_DEPENDENCY'}
 $processMember=Resolve-AiwReleaseAlias $Bundle $MemberId '/processResult' $record.processResult PROCESS_RESULT
 $process=Read-AiwReleaseBundleMember $Bundle $processMember.id PROCESS_RESULT -CurrentCoverage:$CurrentCoverage
 Assert-AiwReleaseFields $process @('runId','status','command','pid','creationUtc','executor','directConsumer','startedUtc','processExitedUtc','endedUtc','exitCode','stdout','stderr','timing','cancellation','streamOrdering') 'process'
 Assert-AiwReleaseFields $process.command @('executable','executableIdentity','executableVersion','arguments','cwd') 'native-command'
 if($process.status-cne'PASS'-or($process.exitCode-isnot[long]-and$process.exitCode-isnot[int])-or$process.exitCode-ne0-or$null-ne$process.cancellation-or$process.streamOrdering-cne'INTRA_STREAM_ONLY'-or$record.startedUtc-cne$process.startedUtc-or$record.endedUtc-cne$process.endedUtc-or[DateTime]::Parse($process.endedUtc)-lt[DateTime]::Parse($process.startedUtc)){throw 'RELEASE_PROCESS_NOT_PASS'}
 $streams=@{}
 foreach($name in @('stdout','stderr')){Assert-AiwReleaseFields $process.$name @('path','identity') 'raw-ref';$raw=Resolve-AiwReleaseAlias $Bundle $processMember.id ('/'+$name) $process.$name $name.ToUpperInvariant();$streams[$name]=$script:ReleaseUtf8.GetString([IO.File]::ReadAllBytes((Get-AiwReleaseChild $Bundle.Root $raw.path)))}
 $pwsh=@($record.after.facts.environment.tools|Where-Object name -CEQ pwsh)
 if($pwsh.Count-ne1-or$process.command.cwd-cne$record.after.facts.root-or$process.command.executable-cne$pwsh[0].path-or$process.command.executableIdentity-cne$pwsh[0].identity-or$process.command.executableVersion-cne$pwsh[0].fileVersion-or(Get-AiwReleaseValueIdentity @($process.command.arguments))-cne(Get-AiwReleaseValueIdentity @($record.after.facts.commandArguments))){throw 'RELEASE_PROCESS_COMMAND'}
 $launchKey=$processMember.id+'|PROCESS_LAUNCH_FOR_RUN'
 if(-not$Bundle.Aliases.ContainsKey($launchKey)){throw 'RELEASE_LAUNCH_ALIAS_MISSING'}
 $la=$Bundle.Aliases[$launchKey];$launchMember=$Bundle.ById[$la.targetMemberId]
 $runLabel=$record.processResult.path.Substring(0,[Math]::Max($record.processResult.path.LastIndexOf('/'),$record.processResult.path.LastIndexOf('\'))+1)
 if($launchMember.kind-cne'PROCESS_LAUNCH'-or$la.originalIdentity-cne$launchMember.identity-or$la.originalLocator-cne($runLabel+'launch.json')){throw 'RELEASE_LAUNCH_ALIAS_BINDING'}
 $null=$Bundle.UsedAliases.Add($launchKey);$launch=Read-AiwReleaseBundleMember $Bundle $launchMember.id PROCESS_LAUNCH -CurrentCoverage:$CurrentCoverage
 if($launch.runId-cne$process.runId-or$launch.pid-ne$process.pid-or$launch.creationUtc-cne$process.creationUtc-or$launch.resultPath-cne$record.processResult.path-or$launch.cwd-cne$process.command.cwd-or(Get-AiwReleaseValueIdentity @($launch.arguments))-cne(Get-AiwReleaseValueIdentity @($process.command.arguments))){throw 'RELEASE_LAUNCH_BINDING'}
 if($launch.startedUtc-cne$process.startedUtc-or$launch.executable-cne$process.command.executable-or$launch.executableIdentity-cne$process.command.executableIdentity-or$launch.executableVersion-cne$process.command.executableVersion-or$launch.executor-cne$process.executor-or$launch.directConsumer-cne$process.directConsumer-or(Get-AiwReleaseValueIdentity @($launch.raw))-cne(Get-AiwReleaseValueIdentity @($process.stdout.path,$process.stderr.path))){throw 'RELEASE_LAUNCH_COMMAND_OR_RAW_BINDING'}
 $phaseKey=$processMember.id+'|PHASE_EVENTS_FOR_RUN'
 if(-not$Bundle.Aliases.ContainsKey($phaseKey)){throw 'RELEASE_PHASE_ALIAS_MISSING'}
 $pa=$Bundle.Aliases[$phaseKey];$phaseMember=$Bundle.ById[$pa.targetMemberId]
 if($phaseMember.kind-cne'PHASE_EVENTS'-or$pa.originalIdentity-cne$phaseMember.identity-or$pa.originalLocator-cne($runLabel+'phases.jsonl')){throw 'RELEASE_PHASE_ALIAS_BINDING'}
 $null=$Bundle.UsedAliases.Add($phaseKey);$null=$Bundle.Reached.Add($phaseMember.id)
 foreach($line in [IO.File]::ReadAllLines((Get-AiwReleaseChild $Bundle.Root $phaseMember.path),$script:ReleaseUtf8)){if($line){$event=(ConvertFrom-AiwStrictInputJson $line).Value;if($event.runId-cne$process.runId){throw 'RELEASE_PHASE_RUN_BINDING'}}}
 $observed=@(Get-AiwReleaseObservedCases $streams.stdout $Group.id)
 if($observed.Count-eq0-or(Get-AiwReleaseValueIdentity $observed)-cne(Get-AiwReleaseValueIdentity @($record.cases))-or@(@($streams.stdout,$streams.stderr)|ForEach-Object{$_-split'\r?\n'}|Where-Object{$_-cmatch'^(SKIP|NOT_RUN|UNKNOWN)\|'-and$_-cne'NOT_RUN|historical-baseline-executable-regression|reason=retired-executable-suite-history-only'}).Count){throw 'RELEASE_CASE_RAW_MISMATCH'}
 foreach($id in $Group.requiredCaseIds){if($id-cnotin@($record.cases.name)){throw 'RELEASE_REQUIRED_CASE_MISSING'}}
 $terminal=@($streams.stdout-split'\r?\n'|Where-Object{$_-cmatch$Group.completionPattern});if($terminal.Count-ne1-or$record.completion-cne$terminal[0]){throw 'RELEASE_GROUP_COMPLETION'}
 Assert-AiwReleaseFields $record.cleanup @('status','root','entries','workers') 'cleanup';if($record.cleanup.status-cne'CLEAN'-or@($record.cleanup.entries).Count-or@($record.cleanup.workers).Count){throw 'RELEASE_CLEANUP_DIRTY'}
 if($CurrentCoverage-and$ExecutionKind-ceq'EXECUTED'){Assert-AiwReleaseCurrentExecution $record $process $launch $Group $Suite}
 # Original roots are opaque provenance labels. Never access their filesystem.
 return $record
}
function Get-AiwReleaseRuntimeToolPaths([string]$VersionRoot,[switch]$Maintenance){
 Assert-AiwReleaseLoadedInputs
 $d=Read-AiwReleaseJson (Get-AiwReleaseChild $VersionRoot 'tests/test-groups.json')
 $base=@('scripts/register-project.ps1','scripts/upgrade-project.ps1','scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/ProjectAdoptionTransaction.psm1','scripts/ProjectCorrectionLifecycle.psm1','scripts/MaintenanceOverlay.psm1')
 # The declaration includes retained source fixtures; target navigation decides
 # which of those inputs must also exist in a distributed runtime.
 if((Get-AiwReleaseValueIdentity @((@($base)+@('skills/ai-workspace-router-v2/SKILL.md'))|Sort-Object))-cne(Get-AiwReleaseValueIdentity @($d.rootAdoptionPaths|Sort-Object))){throw 'RELEASE_RUNTIME_TOOL_DEFINITION_MAPPING'}
 if($null-eq$script:ReleaseNavigationOwner){
  $root=Assert-AiwReleasePath (Join-Path $PSScriptRoot '../../../..')
  $path=Get-AiwReleaseChild $root 'scripts/ProjectAdoptionState.psm1'
  $identity=Get-AiwReleaseFileIdentity $path
  $owner=@(Import-Module $path -PassThru -Scope Local)
  if($owner.Count-ne1-or$owner[0].Path-cne$path-or-not$owner[0].ExportedCommands.ContainsKey('Get-AiwNavigationContract')){throw 'RELEASE_READER_MODULE_OWNER'}
  if((Get-AiwReleaseFileIdentity $path)-cne$identity-or$owner[0].Definition-cne[IO.File]::ReadAllText($path)){throw 'RELEASE_READER_MODULE_DRIFT'}
  $script:ReleaseNavigationOwner=$owner[0]
  $script:ReleaseNavigationCommand=$owner[0].ExportedCommands['Get-AiwNavigationContract']
  $script:ReleaseNavigationBody=$script:ReleaseNavigationCommand.ScriptBlock
  $script:ReleaseLoadedInputs+=@{path=$path;identity=$identity}
 }
 Assert-AiwReleaseLoadedInputs
 $navigation=& $script:ReleaseNavigationCommand (Read-AiwReleaseJson (Get-AiwReleaseChild $VersionRoot 'TOOLCHAIN.json'))
 Assert-AiwReleaseLoadedInputs
 $paths=@($base)+@('LICENSE')
 if($navigation.Kind-ceq'SKILL'){$paths+=@($navigation.CanonicalSkillPath)}
 $maintenanceExpected=@('scripts/resolve-framework-maintenance-target.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1','scripts/check-framework-maintenance-authorization.ps1','scripts/invoke-framework-maintenance-safe-git.ps1','framework/user-package/README.md','framework/user-package/AGENTS.md','framework/maintenance-overlay/AGENTS.md','framework/maintenance-overlay/BOOTSTRAP.md','framework/maintenance-overlay/process-policy.json','framework/maintenance-overlay/PROJECT_CONFIG_SCHEMA.json','framework/maintenance-overlay/OVERLAY.json')
 if((Get-AiwReleaseValueIdentity @($d.maintenancePaths|Sort-Object))-cne(Get-AiwReleaseValueIdentity @($maintenanceExpected|Sort-Object))){throw 'RELEASE_MAINTENANCE_TOOL_DEFINITION_MAPPING'}
 if($Maintenance){$paths+=@($d.maintenancePaths|Where-Object{$_-clike'scripts/*'-or$_-clike'framework/maintenance-overlay/*'})}
 return @($paths)
}
function Assert-AiwReleaseSourceInputs($Bundle,$Facts,$Definition,[string]$SourceRoot,[string]$RuntimeRoot,[switch]$Maintenance){
 $closure=Read-AiwReleaseBundleMember $Bundle $Bundle.Index.sourceInputClosureMemberId INPUT_CLOSURE
 Assert-AiwReleaseFields $closure (@('schemaVersion','kind','inputView','sourceRoot','definitionIdentity','payloadCanonical','inputs','syntheticInputs')+$(if($closure.schemaVersion-eq2){@('recipeIdentity','locationPolicy')}else{@()})) 'input-closure'
 if($closure.schemaVersion-notin@(1,2)-or$closure.kind-cne'SOURCE_INPUT_CLOSURE'-or$closure.inputView-cne'SOURCE_PAYLOAD_V1'-or$closure.definitionIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $Bundle.Root 'tests/test-groups.json'))-or$closure.payloadCanonical-cne$Facts.Canonical){throw 'RELEASE_INPUT_CLOSURE_BINDING'}
 $sourcePaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$payload=@();$tools=Get-AiwReleaseRuntimeToolPaths $Bundle.Root -Maintenance:$Maintenance;$allTools=Get-AiwReleaseRuntimeToolPaths $Bundle.Root -Maintenance
 foreach($input in $closure.inputs){
  Assert-AiwReleaseFields $input @('path','identity','logicalRole','distributionLocator') 'source-input';Assert-AiwReleaseLocator $input.path
  if(-not$sourcePaths.Add($input.path)-or$input.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'RELEASE_INPUT_DUPLICATE_IDENTITY'}
  $expected=if($input.path.StartsWith('framework/versions/2.0.0/',[StringComparison]::Ordinal)){'CURRENT_PAYLOAD'}elseif($input.path-cin$allTools){'CURRENT_RUNTIME_TOOL'}else{'SOURCE_ONLY_BUILD_OR_TEST_INPUT'}
  if($input.logicalRole-cne$expected){throw 'RELEASE_INPUT_ROLE_DOWNGRADE'}
  if($expected-ceq'CURRENT_PAYLOAD'){$relative=$input.path.Substring('framework/versions/2.0.0/'.Length);if($relative-cnotin$Facts.Files-or$input.distributionLocator-cne$input.path){throw 'RELEASE_INPUT_PAYLOAD_SET'};$payload+=@{path=$relative;identity=$input.identity}}
  elseif($expected-ceq'CURRENT_RUNTIME_TOOL'){if($input.distributionLocator-cne$input.path){throw 'RELEASE_RUNTIME_MAPPING'}}
  elseif($null-ne$input.distributionLocator){throw 'RELEASE_SOURCE_ONLY_DISTRIBUTION_MAPPING'}
  if($SourceRoot){if((Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $SourceRoot $input.path))-cne$input.identity){throw 'RELEASE_CURRENT_SOURCE_INPUT_DRIFT'}}
  elseif($expected-ceq'CURRENT_RUNTIME_TOOL'-and$input.path-cin$tools){if(-not$RuntimeRoot-or(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $RuntimeRoot $input.distributionLocator))-cne$input.identity){throw 'RELEASE_CURRENT_RUNTIME_TOOL_DRIFT'}}
 }
 if((Get-AiwReleaseValueIdentity @($payload|Sort-Object path))-cne(Get-AiwReleaseValueIdentity @($Facts.Members|Sort-Object path))){throw 'RELEASE_COMPLETE_PAYLOAD_INPUTS'}
 foreach($tool in $tools){if(-not$sourcePaths.Contains($tool)){throw 'RELEASE_REQUIRED_RUNTIME_TOOL_MISSING'}}
 [string[]]$expectedPaths=@(@($Definition.sourceViewPaths)+@($Facts.Files|ForEach-Object{'framework/versions/2.0.0/'+$_})|Where-Object{$_-cne'framework/versions/2.0.0/RELEASE_MANIFEST.json'}|Select-Object -Unique);[Array]::Sort($expectedPaths,[StringComparer]::Ordinal)
 [string[]]$actualPaths=@($closure.inputs.path);[Array]::Sort($actualPaths,[StringComparer]::Ordinal)
 if((Get-AiwReleaseValueIdentity $actualPaths)-cne(Get-AiwReleaseValueIdentity $expectedPaths)-or@($closure.syntheticInputs).Count-ne1){throw 'RELEASE_SOURCE_INPUT_SET'}
 $closureByPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($input in @($closure.inputs)+@($closure.syntheticInputs)){if($closureByPath.ContainsKey($input.path)){throw 'RELEASE_INPUT_BINDING_ROLE'};$closureByPath.Add($input.path,$input)}
 $bindingKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($binding in $Bundle.Index.inputBindings){
  Assert-AiwReleaseFields $binding @('ownerMemberId','inputOrdinal','logicalRole','sourceRelativePath','identity','distributionLocator','provenanceRef') 'input-binding'
  $key=$binding.ownerMemberId+'|'+$binding.inputOrdinal;if(-not$bindingKeys.Add($key)){throw 'RELEASE_INPUT_BINDING_DUPLICATE'}
  $record=Read-AiwReleaseBundleMember $Bundle $binding.ownerMemberId GROUP_RECORD
  if($binding.inputOrdinal-isnot[long]-and$binding.inputOrdinal-isnot[int]-or$binding.inputOrdinal-lt0-or$binding.inputOrdinal-ge@($record.after.facts.inputs).Count){throw 'RELEASE_INPUT_ORDINAL'}
  $actual=@($record.after.facts.inputs)[$binding.inputOrdinal]
  if($actual.path-cne$binding.sourceRelativePath-or$actual.identity-cne$binding.identity){throw 'RELEASE_INPUT_BINDING_DRIFT'}
  if(-not$closureByPath.ContainsKey($binding.sourceRelativePath)){throw 'RELEASE_INPUT_BINDING_ROLE'}
  $known=$closureByPath[$binding.sourceRelativePath]
  if($known.logicalRole-cne$binding.logicalRole-or$known.identity-cne$binding.identity-or$known.distributionLocator-cne$binding.distributionLocator-or$binding.provenanceRef-cne$Bundle.Index.sourceInputClosureMemberId){throw 'RELEASE_INPUT_BINDING_ROLE'}
 }
 foreach($synthetic in $closure.syntheticInputs){
  Assert-AiwReleaseFields $synthetic @('path','identity','logicalRole','distributionLocator','constructorIdentity') 'synthetic-input'
  if($synthetic.path-cne'framework/versions/2.0.0/RELEASE_MANIFEST.json'-or$synthetic.logicalRole-cne'SYNTHETIC_FIXTURE_INPUT'-or$null-ne$synthetic.distributionLocator-or$synthetic.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$synthetic.constructorIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $Bundle.Root 'tests/TestHarness.psm1'))){throw 'RELEASE_SYNTHETIC_CONSTRUCTOR'}
 }
 foreach($member in $Bundle.Index.members|Where-Object kind -CEQ GROUP_RECORD){$record=Read-AiwReleaseBundleMember $Bundle $member.id GROUP_RECORD;for($i=0;$i -lt @($record.after.facts.inputs).Count;$i++){if(-not$bindingKeys.Contains($member.id+'|'+$i)){throw 'RELEASE_INPUT_BINDING_MISSING'}}}
 if($closure.schemaVersion-eq2){
  $expectedRecipe=Get-AiwReleaseValueIdentity @{constructorIdentity=$closure.syntheticInputs[0].constructorIdentity;definitionIdentity=$closure.definitionIdentity;payloadCanonical=$closure.payloadCanonical;inputs=$closure.inputs;syntheticInputs=$closure.syntheticInputs;locationPolicy=$closure.locationPolicy}
  if($closure.recipeIdentity-cne$expectedRecipe){throw 'RELEASE_FIXTURE_RECIPE_DRIFT'}
  Assert-AiwReleaseFields $closure.locationPolicy @('mode','mappings','conditions') 'closure-location'
  if($closure.locationPolicy.mode-cne'EXACT'-or$closure.locationPolicy.mappings-isnot[Array]-or$closure.locationPolicy.mappings.Count-or$closure.locationPolicy.conditions-isnot[Array]-or$closure.locationPolicy.conditions.Count){throw 'RELEASE_CLOSURE_LOCATION'}
 }
 return $closure
}
function Assert-AiwReleaseProof([string]$VersionRoot,$Manifest,[string]$SourceRoot,[string]$RuntimeRoot,[switch]$Maintenance){
 Assert-AiwReleaseLoadedInputs
 Write-AiwReleaseDiagnostic 'deep-reader-start' @{versionRoot=$VersionRoot;sourceRoot=$SourceRoot;runtimeRoot=$RuntimeRoot;maintenance=[bool]$Maintenance}
 $proof=$Manifest.validationProof
 if($proof.schemaVersion-isnot[long]-and$proof.schemaVersion-isnot[int]){throw 'RELEASE_PROOF_SCHEMA_INTEGER'}
 $proofFields=@('schemaVersion','phase','mode','status','currentPayloadCanonical','suiteDefinitionIdentity','proofBundleRef','proofBundleIdentity','requiredGroupIds','groupRecordRefs','baselineRef','revalidationRefs','prepackageIntegrationRefs');if($proof.schemaVersion-in@(2,3)){$proofFields+='currentSuiteRef'};if($proof.schemaVersion-eq3){$proofFields+='verifierRef'}
 Assert-AiwReleaseFields $proof $proofFields 'validation-proof'
 if($proof.schemaVersion-isnot[long]-and$proof.schemaVersion-isnot[int]){throw 'RELEASE_PROOF_SCHEMA_INTEGER'}
 Assert-AiwReleaseStringFields $proof @('phase','mode','status','currentPayloadCanonical','suiteDefinitionIdentity') 'validation-proof'
 $v1=$proof.schemaVersion-eq1-and$proof.mode-cin@('FULL_RUN','VERIFIED_GROUP_COVERAGE');$v2=$proof.schemaVersion-in@(2,3)-and$proof.mode-ceq'CURRENT_GROUP_COVERAGE'
 if((-not$v1-and-not$v2)-or$proof.phase-cne'PREPACKAGE'-or$proof.status-cne'PASS'){throw 'RELEASE_PROOF_NOT_PASS'}
 if($v2-and$null-ne$proof.baselineRef){throw 'RELEASE_CURRENT_COVERAGE_BASELINE_FORBIDDEN'}
 Assert-AiwReleaseStringFields $proof @('proofBundleIdentity') 'qualified-proof'
 $bundle=Get-AiwReleaseBundle $VersionRoot $proof;$facts=Get-AiwReleasePayloadFacts $VersionRoot @($bundle.Members.path)
 Write-AiwReleaseDiagnostic 'metadata-and-index-complete' @{members=$bundle.Members.Count}
 $inventory=Read-AiwReleaseJson (Get-AiwReleaseChild $VersionRoot 'NORMATIVE_SURFACE_INVENTORY.json')
 [string[]]$expectedPayload=@(@($inventory.runtimeNormativeModules|ForEach-Object{$_.document;$_.fragment})+@($inventory.actionRequiredArtifacts)+@($inventory.schemaAndMechanicalInputs)+@($inventory.explanationAndHistory)|Where-Object{$_-cne'RELEASE_MANIFEST.json'});[Array]::Sort($expectedPayload,[StringComparer]::Ordinal)
 if((Get-AiwReleaseValueIdentity $expectedPayload)-cne(Get-AiwReleaseValueIdentity @($facts.Files))){throw 'RELEASE_PAYLOAD_INVENTORY_SET'}
 if($proof.currentPayloadCanonical-cne$facts.Canonical-or$proof.suiteDefinitionIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot 'tests/test-groups.json'))){throw 'RELEASE_PROOF_CURRENT_INPUT_DRIFT'}
 $definition=Read-AiwReleaseJson (Get-AiwReleaseChild $VersionRoot 'tests/test-groups.json');$required=@($definition.groups|Where-Object{$_.phase-ceq'PREPACKAGE'-and'FULL'-cin$_.requiredFor}|ForEach-Object id)
 $groupsById=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($group in $definition.groups){if($group.id-is[string]){if(-not$groupsById.ContainsKey($group.id)){$groupsById.Add($group.id,[Collections.Generic.List[object]]::new())};$groupsById[$group.id].Add($group)}}
 if((Get-AiwReleaseValueIdentity $required)-cne(Get-AiwReleaseValueIdentity @($proof.requiredGroupIds))){throw 'RELEASE_PROOF_REQUIRED_GROUPS'}
 $currentSuite=$null;$suiteEntries=@{}
 if($v2){
  if($proof.requiredGroupIds-isnot[Array]-or$proof.groupRecordRefs-isnot[Array]-or$proof.revalidationRefs-isnot[Array]-or$proof.prepackageIntegrationRefs-isnot[Array]){throw 'RELEASE_CURRENT_PROOF_ARRAYS'}
  Assert-AiwReleaseRef $proof.currentSuiteRef 'current-suite-ref'
  $sm=@($bundle.Index.members|Where-Object{$_.kind-ceq'CURRENT_SUITE'-and$_.path-ceq$proof.currentSuiteRef.path-and$_.identity-ceq$proof.currentSuiteRef.identity})
  if($sm.Count-ne1-or@($bundle.Index.members|Where-Object kind -CEQ CURRENT_SUITE).Count-ne1){throw 'RELEASE_CURRENT_SUITE_BINDING'}
  $currentSuite=Read-AiwReleaseBundleMember $bundle $sm[0].id CURRENT_SUITE -CurrentCoverage
  Assert-AiwReleaseCurrentSuiteShape $currentSuite $proof.suiteDefinitionIdentity $required -Complete
  if($proof.schemaVersion-eq3){
   if($proof.verifierRef.identity-cne(Get-AiwReleaseFileIdentity (Join-Path $PSScriptRoot 'TestEvidenceValidation.psm1'))){throw 'RELEASE_CURRENT_VERIFIER_BINDING'}
   Assert-AiwReleaseRef $proof.verifierRef 'current-verifier';Assert-AiwReleaseRef $currentSuite.verifierRef 'suite-verifier'
   if($currentSuite.schemaVersion-ne3-or$definition.schemaVersion-ne3-or$proof.verifierRef.path-cne'scripts/TestEvidenceValidation.psm1'-or$proof.verifierRef.identity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot $proof.verifierRef.path))-or(Get-AiwReleaseValueIdentity $proof.verifierRef)-cne(Get-AiwReleaseValueIdentity $currentSuite.verifierRef)){throw 'RELEASE_CURRENT_VERIFIER_BINDING'}
  }elseif($currentSuite.schemaVersion-ne2){throw 'RELEASE_CURRENT_SUITE_BINDING'}
  $inputMember=Resolve-AiwReleaseAlias $bundle $sm[0].id '/sourceInputsRef' $currentSuite.sourceInputsRef INPUT_CLOSURE
  if($inputMember.id-cne$bundle.Index.sourceInputClosureMemberId){throw 'RELEASE_CURRENT_SUITE_INPUTS'}
  $rvUsed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  for($i=0;$i-lt$currentSuite.records.Count;$i++){
   $entry=$currentSuite.records[$i];$group=@(if($groupsById.ContainsKey($entry.groupId)){$groupsById[$entry.groupId].ToArray()})
   if($group.Count-ne1-or$entry.groupId-cnotin$required){throw 'RELEASE_CURRENT_SUITE_PARTITION'}
   $member=Resolve-AiwReleaseAlias $bundle $sm[0].id ('/records/'+$i.ToString()+'/original') ([pscustomobject]@{path=$entry.path;identity=$entry.identity}) GROUP_RECORD
   if(@($proof.groupRecordRefs|Where-Object{$_.groupId-ceq$entry.groupId-and$_.path-ceq$member.path-and$_.identity-ceq$member.identity}).Count-ne1){throw 'RELEASE_CURRENT_SUITE_PROOF_PARTITION'}
   $suiteEntries[$entry.groupId]=$entry
   if($proof.schemaVersion-eq3-and$entry.executionKind-ceq'EXECUTED'){$fresh=Read-AiwReleaseBundleMember $bundle $member.id GROUP_RECORD -CurrentCoverage;if($fresh.schemaVersion-ne2){throw 'RELEASE_EXECUTION2_SUITE3_REQUIRED'};Assert-AiwReleaseBehaviorSnapshot $fresh.after $definition $group[0] $currentSuite $VersionRoot;$bundle.CurrentSnapshots[$entry.groupId]=$fresh.after}
   if($entry.executionKind-ceq'REVALIDATED'){
    $rm=Resolve-AiwReleaseAlias $bundle $sm[0].id ('/records/'+$i.ToString()+'/revalidation') $entry.revalidation REVALIDATION
    if(-not$rvUsed.Add($rm.id)-or@($proof.revalidationRefs|Where-Object{$_.path-ceq$rm.path-and$_.identity-ceq$rm.identity}).Count-ne1){throw 'RELEASE_CURRENT_SUITE_REVALIDATION_PARTITION'}
    $rv=Read-AiwReleaseBundleMember $bundle $rm.id REVALIDATION -CurrentCoverage
    $record=Read-AiwReleaseBundleMember $bundle $member.id GROUP_RECORD -CurrentCoverage
    if($proof.schemaVersion-eq3-and$record.schemaVersion-ne2){throw 'RELEASE_EXECUTION2_SUITE3_REQUIRED'}
    $currentSnapshot=if($proof.schemaVersion-eq3){$rv.currentSnapshot}else{$record.after}
    if($proof.schemaVersion-eq3){Assert-AiwReleaseBehaviorSnapshot $currentSnapshot $definition $group[0] $currentSuite $VersionRoot;$bundle.CurrentSnapshots[$entry.groupId]=$currentSnapshot}
    Assert-AiwReleaseCurrentRevalidation $rv ([pscustomobject]@{path=$entry.path;identity=$entry.identity}) $group[0] $currentSnapshot $currentSuite
    $original=Resolve-AiwReleaseAlias $bundle $rm.id '/original' $rv.original GROUP_RECORD
    if($original.id-cne$member.id){throw 'RELEASE_CURRENT_SUITE_REVALIDATION_ORIGINAL'}
   }
  }
  if($proof.groupRecordRefs.Count-ne$currentSuite.records.Count-or$proof.revalidationRefs.Count-ne$rvUsed.Count){throw 'RELEASE_CURRENT_SUITE_PROOF_PARTITION'}
 }
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($ref in $proof.groupRecordRefs){Assert-AiwReleaseFields $ref @('groupId','path','identity') 'group-ref';$group=@(if($groupsById.ContainsKey($ref.groupId)){$groupsById[$ref.groupId].ToArray()});$member=@(if($bundle.ByPath.ContainsKey($ref.path)){$bundle.ByPath[$ref.path]|Where-Object{$_.identity-ceq$ref.identity-and$_.kind-ceq'GROUP_RECORD'}});if($group.Count-ne1-or$member.Count-ne1-or-not$seen.Add($ref.groupId)-or$ref.groupId-cnotin$required){throw 'RELEASE_PROOF_GROUP_BINDING'};$kind=if($v2){$suiteEntries[$ref.groupId].executionKind}else{'EXECUTED'};$null=Assert-AiwReleasePortableGroup $bundle $member[0].id $group[0] -CurrentCoverage:$v2 -Suite $currentSuite -ExecutionKind $kind}
 if($seen.Count-ne$required.Count){throw 'RELEASE_PROOF_MISSING_GROUP'}
 Write-AiwReleaseDiagnostic 'group-proof-complete' @{groups=$seen.Count}
 if($proof.mode-ceq'FULL_RUN'){if($null-ne$proof.baselineRef-or@($proof.revalidationRefs).Count){throw 'RELEASE_FULL_RUN_BASELINE_CYCLE'}}elseif($proof.mode-ceq'VERIFIED_GROUP_COVERAGE'){
  # A portable hash alone cannot independently prove accepted baseline authority.
  # Require the finite accepted FULL_RUN closure and each current local revalidation.
  Assert-AiwReleaseRef $proof.baselineRef 'baseline-ref';$bm=@($bundle.Index.members|Where-Object{$_.kind-ceq'BASELINE_CLOSURE'-and$_.path-ceq$proof.baselineRef.path-and$_.identity-ceq$proof.baselineRef.identity});if($bm.Count-ne1){throw 'RELEASE_ACCEPTED_BASELINE_MISSING'}
  $baseline=Read-AiwReleaseBundleMember $bundle $bm[0].id BASELINE_CLOSURE
  Assert-AiwReleaseFields $baseline @('schemaVersion','kind','mode','outcome','proofIdentity','acceptedProofIdentity','acceptanceRef','acceptedBy','groupRecordIdentities','acceptanceBase64','acceptedPackageRef','acceptedPostBuildRef') 'accepted-baseline'
  if($baseline.schemaVersion-ne1-or$baseline.kind-cne'ACCEPTED_FULL_RUN_BASELINE'-or$baseline.mode-cne'FULL_RUN'-or$baseline.outcome-cne'PASS'-or$baseline.proofIdentity-cne$baseline.acceptedProofIdentity-or$baseline.acceptanceRef.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]::IsNullOrWhiteSpace($baseline.acceptedBy)){throw 'RELEASE_ACCEPTED_BASELINE_BINDING'}
  if($baseline.proofIdentity-cnotmatch'^[A-F0-9]{64}$'-or$baseline.groupRecordIdentities-isnot[Array]-or@($baseline.groupRecordIdentities).Count-eq0-or@($baseline.groupRecordIdentities|Select-Object -Unique).Count-ne$baseline.groupRecordIdentities.Count-or@($baseline.groupRecordIdentities|Where-Object{$_-cnotmatch'^\d+\|[A-F0-9]{64}$'}).Count){throw 'RELEASE_ACCEPTED_BASELINE_GROUPS'}
  try{$acceptanceBytes=[Convert]::FromBase64String($baseline.acceptanceBase64);$accepted=(ConvertFrom-AiwStrictInputJson $script:ReleaseUtf8.GetString($acceptanceBytes)).Value}catch{throw 'RELEASE_BASELINE_ACCEPTANCE_ENCODING'}
  if((Get-AiwReleaseByteIdentity $acceptanceBytes)-cne$baseline.acceptanceRef.identity-or$accepted.schemaVersion-ne1-or$accepted.outcome-cne'ACCEPTED'-or$accepted.actor-cne$baseline.acceptedBy-or@($accepted.checks|Where-Object outcome -CNE PASS).Count){throw 'RELEASE_BASELINE_ACCEPTANCE_BINDING'}
  if($accepted.checks-isnot[Array]-or$accepted.checks.Count-eq0-or$accepted.candidateObjects-isnot[Array]){throw 'RELEASE_BASELINE_ACCEPTANCE_INCOMPLETE'}
  foreach($ref in @($baseline.acceptedPackageRef,$baseline.acceptedPostBuildRef)){if(@($accepted.candidateObjects|Where-Object{$_.path-ceq$ref.path-and$_.identity-ceq$ref.identity}).Count-ne1){throw 'RELEASE_BASELINE_ACCEPTANCE_CANDIDATE'}}
  if(@($proof.revalidationRefs).Count-eq0){throw 'RELEASE_REVALIDATION_MISSING'}
 }
 if($proof.mode-ceq'VERIFIED_GROUP_COVERAGE'){
  $revalidated=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($ref in $proof.revalidationRefs){
   Assert-AiwReleaseRef $ref 'revalidation-ref';$m=@($bundle.Index.members|Where-Object{$_.kind-ceq'REVALIDATION'-and$_.path-ceq$ref.path-and$_.identity-ceq$ref.identity});if($m.Count-ne1){throw 'RELEASE_REVALIDATION_BINDING'}
   $rv=Read-AiwReleaseBundleMember $bundle $m[0].id REVALIDATION;Assert-AiwReleaseFields $rv @('schemaVersion','executionKind','groupId','original','currentSnapshot','validatorIdentity','checkedUtc','outcome','reason') 'revalidation'
   if($rv.schemaVersion-ne1-or$rv.executionKind-cne'REVALIDATED'-or$rv.outcome-cne'PASS'-or$rv.original.identity-cnotin$baseline.groupRecordIdentities-or(Get-AiwReleaseValueIdentity $rv.currentSnapshot.facts)-cne$rv.currentSnapshot.identity-or-not$revalidated.Add($rv.groupId)){throw 'RELEASE_REVALIDATION_NOT_PASS'}
   $original=Resolve-AiwReleaseAlias $bundle $m[0].id '/original' $rv.original GROUP_RECORD;$rec=Read-AiwReleaseBundleMember $bundle $original.id GROUP_RECORD;$group=@($definition.groups|Where-Object id -CEQ $rv.groupId)
   if($group.Count-ne1-or$group[0].alwaysFresh-or@($group[0].unknownDependencies).Count-or$rec.groupId-cne$rv.groupId-or@($proof.groupRecordRefs|Where-Object{$_.groupId-ceq$rv.groupId-and$_.identity-ceq$rv.original.identity}).Count-ne1-or$rec.after.identity-cne$rv.currentSnapshot.identity-or$rv.validatorIdentity-cne$rec.validatorIdentity){throw 'RELEASE_REVALIDATION_INPUT_DRIFT'}
  }
 }
 if(@($proof.prepackageIntegrationRefs).Count-ne1){throw 'RELEASE_PREPACKAGE_INTEGRATION_MISSING'}
 $integration=$proof.prepackageIntegrationRefs[0];if(@($proof.groupRecordRefs|Where-Object{$_.groupId-ceq'integration.full-source'-and$_.path-ceq$integration.path-and$_.identity-ceq$integration.identity}).Count-ne1){throw 'RELEASE_PREPACKAGE_INTEGRATION_BINDING'}
 $closure=Assert-AiwReleaseSourceInputs $bundle $facts $definition $SourceRoot $RuntimeRoot -Maintenance:$Maintenance
 if($proof.schemaVersion-eq3){
  $available=@($closure.inputs)+@($closure.syntheticInputs)
  foreach($id in $required){$group=$groupsById[$id].ToArray()[0];$snapshotFacts=$bundle.CurrentSnapshots[$id].facts;Assert-AiwEvidenceSnapshotInputs $snapshotFacts $definition $group $available}
 }
 Write-AiwReleaseDiagnostic 'source-bindings-complete' @{bindings=$bundle.Index.inputBindings.Count}
 if($v2){foreach($ref in $proof.groupRecordRefs){$member=@($bundle.Index.members|Where-Object path -CEQ $ref.path)[0];$record=Read-AiwReleaseBundleMember $bundle $member.id GROUP_RECORD;$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($input in $record.after.facts.inputs){$null=$paths.Add($input.path)};$subset=@(@($closure.inputs)+@($closure.syntheticInputs)|Where-Object{$paths.Contains($_.path)});if($record.after.facts.rootSensitive-isnot[bool]-or-not$record.after.facts.rootSensitive-or$record.after.facts.sourceInputsIdentity-cne(Get-AiwReleaseValueIdentity $subset)){throw 'RELEASE_CURRENT_COVERAGE_SNAPSHOT_CLOSURE'}}}
 if($bundle.UsedAliases.Count-ne$bundle.Aliases.Count-or$bundle.Reached.Count-ne$bundle.ById.Count){throw 'RELEASE_UNUSED_ALIAS_OR_MEMBER'}
 # Observations are not a filesystem lock. Recheck the exact finite set and
 # every relevant byte after all consumers, including paths and reparse guards.
 $live=@(Get-AiwReleaseTreeMembers (Get-AiwReleaseChild $VersionRoot 'validation-evidence/prepackage')|ForEach-Object{@{path=('validation-evidence/prepackage/'+$_.path);identity=$_.identity}})
 if((Get-AiwReleaseMemberFacts $live).Canonical-cne(Get-AiwReleaseMemberFacts $bundle.Members).Canonical){throw 'RELEASE_BUNDLE_FINAL_DRIFT'}
 if((Get-AiwReleasePayloadFacts $VersionRoot @($bundle.Members.path)).Canonical-cne$facts.Canonical){throw 'RELEASE_PAYLOAD_DRIFT'}
 $finalRuntimeTools=@(Get-AiwReleaseRuntimeToolPaths $VersionRoot -Maintenance:$Maintenance)
 foreach($input in $closure.inputs){
  if($SourceRoot){if((Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $SourceRoot $input.path))-cne$input.identity){throw 'RELEASE_CURRENT_SOURCE_INPUT_DRIFT'}}
  elseif($input.logicalRole-ceq'CURRENT_RUNTIME_TOOL'-and$input.path-cin$finalRuntimeTools){if(-not$RuntimeRoot-or(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $RuntimeRoot $input.distributionLocator))-cne$input.identity){throw 'RELEASE_CURRENT_RUNTIME_TOOL_DRIFT'}}
 }
 Write-AiwReleaseDiagnostic 'deep-reader-complete' @{memberParseCount=$bundle.Parsed.Count;groupRecordCount=@($bundle.Index.members|Where-Object kind -CEQ GROUP_RECORD).Count;inputBindingCount=$bundle.Index.inputBindings.Count}
 $bundle.Bytes.Clear();$bundle.Parsed.Clear()
 return [pscustomobject]@{Facts=$facts;Bundle=$bundle;Inputs=$closure;Mode=$proof.mode;BaselineAuthority=$(if($v2){'CURRENT_FINITE_GROUP_COVERAGE'}else{'SOURCE_REVIEW_BOUND_PROVENANCE'});ExecutionReusable=$false}
}
function Assert-AiwReleaseReviewProjection($Manifest){
 $review=$Manifest.sourceReviewEvidence
 Assert-AiwReleaseFields $review @('status','reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity','reviewedManifestBase64') 'source-review'
 Assert-AiwReleaseStringFields $Manifest @('sourceReview') 'review-manifest'
 Assert-AiwReleaseStringFields $review @('status') 'source-review'
 if($Manifest.sourceReview-cne'APPROVED'-or$review.status-cne'APPROVED'){throw 'RELEASE_SOURCE_REVIEW_REQUIRED'}
 Assert-AiwReleaseStringFields $review @('reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity','reviewedManifestBase64') 'qualified-source-review'
 if($Manifest.sourceReview-cne'APPROVED'-or$review.status-cne'APPROVED'-or[string]::IsNullOrWhiteSpace($review.reviewer)-or$review.reviewer-cin@('NONE','PENDING')-or$review.packageIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$review.reviewedPayloadCanonical-cne$Manifest.canonical){throw 'RELEASE_SOURCE_REVIEW_REQUIRED'}
 try{$bytes=[Convert]::FromBase64String($review.reviewedManifestBase64);$text=$script:ReleaseUtf8.GetString($bytes);$before=(ConvertFrom-AiwStrictInputJson $text).Value}catch{throw 'RELEASE_REVIEW_PREIMAGE_INVALID'}
 if((Get-AiwReleaseByteIdentity $bytes)-cne$review.reviewedManifestIdentity){throw 'RELEASE_REVIEW_PREIMAGE_DRIFT'}
 Assert-AiwReleaseManifestShape $before
 if($before.schemaVersion-ne3-or$before.sourceReview-cne'PENDING'-or$before.sourceReviewEvidence.status-cne'PENDING'-or@($before.sourceReviewEvidence.PSObject.Properties|Where-Object{$_.Name-cne'status'-and$null-ne$_.Value}).Count-or$before.validationProof.status-cne'PASS'){throw 'RELEASE_REVIEW_PREIMAGE_STATE_OR_CYCLE'}
 $a=$Manifest|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$b=$before|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 foreach($key in @('sourceReview','sourceReviewEvidence')){$a.PSObject.Properties.Remove($key);$b.PSObject.Properties.Remove($key)}
 if((Get-AiwReleaseCanonical $a)-cne(Get-AiwReleaseCanonical $b)){throw 'RELEASE_REVIEW_PROJECTION_DRIFT'}
 return $before
}
function Assert-AiwReleaseManifestShape($Manifest){
 if($Manifest.schemaVersion-isnot[long]-and$Manifest.schemaVersion-isnot[int]){throw 'RELEASE_SCHEMA_INTEGER'}
 $base=@('schemaVersion','version','lifecycle','releaseClass','scope','algorithm','fileCount','totalBytes','canonical','baseline','sourceReview','sourceCandidate','releaseIntegration','sourceReviewEvidence')
 if($Manifest.schemaVersion-eq2){Assert-AiwReleaseFields $Manifest ($base+@('completeSuite')) 'manifest2';Assert-AiwReleaseFields $Manifest.completeSuite @('status','passed','total','payloadCanonical','evidenceIdentity') 'suite2';Assert-AiwReleaseFields $Manifest.sourceReviewEvidence @('status','reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity') 'review2'}
 elseif($Manifest.schemaVersion-eq3){if($Manifest.validationProof.schemaVersion-isnot[long]-and$Manifest.validationProof.schemaVersion-isnot[int]){throw 'RELEASE_PROOF_SCHEMA_INTEGER'};Assert-AiwReleaseFields $Manifest ($base+@('validationProof')) 'manifest3';Assert-AiwReleaseFields $Manifest.sourceReviewEvidence @('status','reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity','reviewedManifestBase64') 'review3';Assert-AiwReleaseFields $Manifest.validationProof (@('schemaVersion','phase','mode','status','currentPayloadCanonical','suiteDefinitionIdentity','proofBundleRef','proofBundleIdentity','requiredGroupIds','groupRecordRefs','baselineRef','revalidationRefs','prepackageIntegrationRefs')+$(if($Manifest.validationProof.schemaVersion-in@(2,3)){@('currentSuiteRef')}else{@()})+$(if($Manifest.validationProof.schemaVersion-eq3){@('verifierRef')}else{@()})) 'proof3'}else{throw 'RELEASE_SCHEMA_UNSUPPORTED'}
 Assert-AiwReleaseStringFields $Manifest @('version','lifecycle','releaseClass','scope','algorithm','canonical','baseline','sourceReview','sourceCandidate','releaseIntegration') 'manifest'
 Assert-AiwReleaseStringFields $Manifest.sourceReviewEvidence @('status') 'review-state'
 if($Manifest.schemaVersion-eq2){Assert-AiwReleaseStringFields $Manifest.completeSuite @('status') 'suite-state'}else{
  if($Manifest.validationProof.schemaVersion-isnot[long]-and$Manifest.validationProof.schemaVersion-isnot[int]){throw 'RELEASE_PROOF_SCHEMA_INTEGER'}
  Assert-AiwReleaseStringFields $Manifest.validationProof @('phase','mode','status','currentPayloadCanonical','suiteDefinitionIdentity') 'proof-state'
 }
 if($Manifest.version-cne'2.0.0'-or$Manifest.lifecycle-cnotin@('CANDIDATE','STABLE')-or$Manifest.canonical-cnotmatch'^[A-F0-9]{64}$'-or($Manifest.fileCount-isnot[long]-and$Manifest.fileCount-isnot[int])-or($Manifest.totalBytes-isnot[long]-and$Manifest.totalBytes-isnot[int])-or$Manifest.fileCount-lt1-or$Manifest.totalBytes-lt1-or$Manifest.algorithm-cne$script:ReleaseAlgorithm){throw 'RELEASE_MANIFEST_VALUES'}
}
function Get-AiwReleaseSchema2State($Version,$Manifest,$Facts,[bool]$SkipManifestValidation=$false){
 Assert-AiwReleaseManifestShape $Manifest
 if($Manifest.schemaVersion-ne2){throw 'RELEASE_SCHEMA2_REQUIRED'}
 Assert-AiwReleaseStringFields $Version @('version','lifecycle') 'version'
 $candidate=$Version.version-ceq'2.0.0'-and$Version.lifecycle-ceq'CANDIDATE'-and$Version.consumable-is[bool]-and-not$Version.consumable-and$Version.projectPinEligible-is[bool]-and-not$Version.projectPinEligible
 $stable=$Version.version-ceq'2.0.0'-and$Version.lifecycle-ceq'STABLE'-and$Version.consumable-is[bool]-and$Version.consumable-and$Version.projectPinEligible-is[bool]-and$Version.projectPinEligible
 $pending=$candidate-and$Manifest.lifecycle-ceq'CANDIDATE'-and$Manifest.sourceReview-ceq'PENDING'-and$Manifest.completeSuite.status-ceq'PENDING'-and$Manifest.sourceReviewEvidence.status-ceq'PENDING'-and$Manifest.releaseIntegration-ceq'PENDING'
 if($SkipManifestValidation){if($pending){return 'PENDING_CANDIDATE'};throw 'RELEASE_VALIDATION_SKIP_REQUIRES_PENDING_CANDIDATE'}
 $suite=$Manifest.completeSuite;$review=$Manifest.sourceReviewEvidence
 Assert-AiwReleaseStringFields $suite @('payloadCanonical','evidenceIdentity') 'qualified-suite'
 Assert-AiwReleaseStringFields $review @('reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity') 'qualified-review'
 $bound=$Manifest.fileCount-eq$Facts.FileCount-and$Manifest.totalBytes-eq$Facts.TotalBytes-and$Manifest.canonical-ceq$Facts.Canonical-and$Manifest.scope-ceq'all release payload files except RELEASE_MANIFEST.json'-and$Manifest.sourceReview-ceq'APPROVED'-and$suite.status-ceq'PASS'-and($suite.passed-is[long]-or$suite.passed-is[int])-and($suite.total-is[long]-or$suite.total-is[int])-and$suite.passed-gt0-and$suite.passed-eq$suite.total-and$suite.payloadCanonical-ceq$Facts.Canonical-and$suite.evidenceIdentity-cmatch'^\d+\|[A-F0-9]{64}$'-and$review.status-ceq'APPROVED'-and-not[string]::IsNullOrWhiteSpace($review.reviewer)-and$review.reviewer-cnotin@('NONE','PENDING')-and$review.packageIdentity-cmatch'^\d+\|[A-F0-9]{64}$'-and$review.reviewedPayloadCanonical-ceq$Facts.Canonical-and$review.reviewedManifestIdentity-cmatch'^\d+\|[A-F0-9]{64}$'-and-not[string]::IsNullOrWhiteSpace($Manifest.sourceCandidate)-and$Manifest.sourceCandidate-cne'PENDING'
 if($bound-and$stable-and$Manifest.lifecycle-ceq'STABLE'-and-not[string]::IsNullOrWhiteSpace($Manifest.releaseIntegration)-and$Manifest.releaseIntegration-cne'PENDING'){return 'STABLE'}
 if($bound-and$candidate-and$Manifest.lifecycle-ceq'CANDIDATE'-and$Manifest.releaseIntegration-ceq'PENDING'){return 'REVIEWED_CANDIDATE'}
 throw 'RELEASE_VALIDATION_STATE_UNSUPPORTED'
}
function Get-AiwReleaseQualificationCore {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$VersionRoot,[string]$SourceRoot,[string]$RuntimeRoot,[switch]$Maintenance,[switch]$AllowPending)
 Write-AiwReleaseDiagnostic 'qualification-core-start' @{versionRoot=$VersionRoot}
 $manifestPath=Get-AiwReleaseChild $VersionRoot 'RELEASE_MANIFEST.json';$manifestBytes=[IO.File]::ReadAllBytes($manifestPath);$manifestIdentity=Get-AiwReleaseByteIdentity $manifestBytes
 $versionPath=Get-AiwReleaseChild $VersionRoot 'VERSION.json';$versionBytes=[IO.File]::ReadAllBytes($versionPath);$versionIdentity=Get-AiwReleaseByteIdentity $versionBytes
 $manifest=ConvertFrom-AiwReleaseBytes $manifestBytes;$version=ConvertFrom-AiwReleaseBytes $versionBytes;Assert-AiwReleaseManifestShape $manifest
 Assert-AiwReleaseStringFields $version @('version','lifecycle') 'version'
 if($version.version-cne$manifest.version-or$version.lifecycle-cne$manifest.lifecycle-or$version.consumable-isnot[bool]-or$version.projectPinEligible-isnot[bool]-or($manifest.lifecycle-ceq'STABLE'-and(-not$version.consumable-or-not$version.projectPinEligible))-or($manifest.lifecycle-ceq'CANDIDATE'-and($version.consumable-or$version.projectPinEligible))){throw 'RELEASE_VERSION_LIFECYCLE'}
 $pending=$manifest.sourceReview-ceq'PENDING'-and$manifest.sourceReviewEvidence.status-ceq'PENDING'-and$manifest.lifecycle-ceq'CANDIDATE'
 $proofResult=$null
 if($manifest.schemaVersion-eq3){
  if($manifest.scope-cne$script:ReleaseScope){throw 'RELEASE_PAYLOAD_SCOPE'}
  if($AllowPending-and$pending-and$manifest.validationProof.status-ceq'PENDING'){
   if($manifest.releaseIntegration-cne'PENDING'-or$null-ne$manifest.validationProof.proofBundleRef-or$null-ne$manifest.validationProof.proofBundleIdentity-or@($manifest.validationProof.groupRecordRefs).Count-or$null-ne$manifest.sourceReviewEvidence.reviewedManifestBase64){throw 'RELEASE_PENDING_MIXED_EVIDENCE'};$facts=Get-AiwReleasePayloadFacts $VersionRoot;$state='PENDING_CANDIDATE'
   if($manifest.validationProof.schemaVersion-eq3){Assert-AiwReleaseRef $manifest.validationProof.verifierRef 'pending-verifier';if($manifest.validationProof.verifierRef.path-cne'scripts/TestEvidenceValidation.psm1'-or$manifest.validationProof.verifierRef.identity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot 'scripts/TestEvidenceValidation.psm1'))){throw 'RELEASE_PENDING_MIXED_EVIDENCE'}}
   $pendingMode=($manifest.validationProof.schemaVersion-eq1-and$manifest.validationProof.mode-ceq'FULL_RUN')-or($manifest.validationProof.schemaVersion-in@(2,3)-and$manifest.validationProof.mode-ceq'CURRENT_GROUP_COVERAGE')
   if(($manifest.validationProof.schemaVersion-in@(2,3)-and$null-ne$manifest.validationProof.currentSuiteRef)-or-not$pendingMode-or$manifest.validationProof.phase-cne'PREPACKAGE'-or$manifest.validationProof.currentPayloadCanonical-cne$facts.Canonical-or$manifest.validationProof.suiteDefinitionIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot 'tests/test-groups.json'))-or$null-ne$manifest.validationProof.baselineRef-or@($manifest.validationProof.requiredGroupIds).Count-or@($manifest.validationProof.revalidationRefs).Count-or@($manifest.validationProof.prepackageIntegrationRefs).Count-or@($manifest.sourceReviewEvidence.PSObject.Properties|Where-Object{$_.Name-cne'status'-and$null-ne$_.Value}).Count){throw 'RELEASE_PENDING_MIXED_EVIDENCE'}
  }else{$proofResult=Assert-AiwReleaseProof $VersionRoot $manifest $SourceRoot $RuntimeRoot -Maintenance:$Maintenance;$facts=$proofResult.Facts;$null=Assert-AiwReleaseReviewProjection $manifest;if($manifest.releaseIntegration-cne'PREPACKAGE_PASS'){throw 'RELEASE_PREPACKAGE_INTEGRATION_REQUIRED'};$state='SOURCE_QUALIFIED'}
 }else{
  $facts=Get-AiwReleasePayloadFacts $VersionRoot
  if($manifest.scope-cne'all release payload files except RELEASE_MANIFEST.json'){throw 'RELEASE_PAYLOAD_SCOPE'}
  if($AllowPending-and$pending-and$manifest.completeSuite.status-ceq'PENDING'-and$manifest.releaseIntegration-ceq'PENDING'){$state='PENDING_CANDIDATE'}else{
   $null=Get-AiwReleaseSchema2State $version $manifest $facts;$state='SOURCE_QUALIFIED'
  }
 }
 if($manifest.fileCount-ne$facts.FileCount-or$manifest.totalBytes-ne$facts.TotalBytes-or$manifest.canonical-cne$facts.Canonical){throw 'RELEASE_PAYLOAD_DRIFT'}
 if((Get-AiwReleaseFileIdentity $manifestPath)-cne$manifestIdentity-or(Get-AiwReleaseFileIdentity $versionPath)-cne$versionIdentity){throw 'RELEASE_METADATA_FINAL_DRIFT'}
 Write-AiwReleaseDiagnostic 'qualification-core-complete' @{versionRoot=$VersionRoot;state=$state}
 return [pscustomobject]@{State=$state;DistributionState='DISTRIBUTION_NOT_BUILT';Manifest=$manifest;Version=$version;Facts=$facts;Proof=$proofResult;ManifestIdentity=$manifestIdentity}
}
$script:ReleaseAction=$null
$script:ReleaseModulePath=$PSCommandPath
function Invoke-AiwReleaseQualificationScope {
 [CmdletBinding()]param([Parameter(Mandatory)][scriptblock]$Body,[object[]]$ArgumentList=@(),[scriptblock]$DiagnosticCallback)
 $owned=$null-eq$script:ReleaseAction;$priorDiagnostic=$script:ReleaseDiagnostic
 if($owned){$script:ReleaseAction=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);if($PSBoundParameters.ContainsKey('DiagnosticCallback')){$script:ReleaseDiagnostic=$DiagnosticCallback}}
 try{& $Body @ArgumentList}
 catch{if($null-ne$script:ReleaseAction){$script:ReleaseAction.Clear()};throw}
 finally{if($owned){$script:ReleaseAction.Clear();$script:ReleaseAction=$null;$script:ReleaseDiagnostic=$priorDiagnostic}}
}
function Assert-AiwReleaseConsumptionSnapshot($Snapshot){
 $actual=@(Get-AiwReleaseTreeMembers $Snapshot.versionRoot)
 if((Get-AiwReleaseMemberFacts $actual).Canonical-cne$Snapshot.versionCanonical){throw 'RELEASE_CONSUMPTION_DRIFT'}
 foreach($entry in $Snapshot.otherInputs){if((Get-AiwReleaseFileIdentity $entry.path)-cne$entry.identity){throw 'RELEASE_CONSUMPTION_DRIFT'}}
 foreach($entry in $Snapshot.packages){$current=Get-AiwReleasePackageFacts $entry.root;if($current.ManifestIdentity-cne$entry.manifestIdentity-or$current.Canonical-cne$entry.canonical){throw 'RELEASE_CONSUMPTION_DRIFT'}}
}
function Get-AiwReleaseQualification {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$VersionRoot,[string]$SourceRoot,[string]$RuntimeRoot,[switch]$Maintenance,[switch]$AllowPending)
 $versionPath=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwReleasePath $VersionRoot))
 $sourcePath=if($SourceRoot){[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwReleasePath $SourceRoot))}else{''}
 $runtimePath=if($RuntimeRoot){[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwReleasePath $RuntimeRoot))}else{''}
 $key=@($versionPath,$sourcePath,$runtimePath,[string][bool]$Maintenance)-join'|'
 try{
  Assert-AiwReleaseLoadedInputs
  if($null-ne$script:ReleaseAction-and$script:ReleaseAction.ContainsKey($key)){
   $entry=$script:ReleaseAction[$key]
   Assert-AiwReleaseConsumptionSnapshot $entry.snapshot
   if($entry.state-ceq'SOURCE_QUALIFIED'-or$AllowPending){
    Write-AiwReleaseDiagnostic 'qualification-context-hit' @{versionRoot=$versionPath;state=$entry.state}
    return [Management.Automation.PSSerializer]::Deserialize($entry.wire)
   }
  }
  $moduleInputs=@($script:ReleaseLoadedInputs)
  $packages=@()
  if($null-ne$script:ReleaseAction){foreach($root in @($sourcePath,$runtimePath)|Where-Object{$_}|Select-Object -Unique){
   if([IO.File]::Exists((Join-Path $root 'PACKAGE_MANIFEST.json'))){$package=Get-AiwReleasePackageFacts $root;$packages+=@{root=$root;manifestIdentity=$package.ManifestIdentity;canonical=$package.Canonical}}
  }}
  $q=Get-AiwReleaseQualificationCore -VersionRoot $versionPath -SourceRoot $sourcePath -RuntimeRoot $runtimePath -Maintenance:$Maintenance -AllowPending:$AllowPending
  foreach($input in $moduleInputs){if((Get-AiwReleaseFileIdentity $input.path)-cne$input.identity){throw 'RELEASE_READER_MODULE_DRIFT'}}
  # The first core read may bind navigation lazily. Keep its original identity
  # in both the first verification and the complete action snapshot.
  Assert-AiwReleaseLoadedInputs
  $moduleInputs=@($script:ReleaseLoadedInputs)
  if($null-eq$script:ReleaseAction){return $q}
  $members=@($q.Facts.Members)+@{path='RELEASE_MANIFEST.json';identity=$q.ManifestIdentity}
  if($null-ne$q.Proof){$members+=@($q.Proof.Bundle.Members)}
  $others=@($moduleInputs)
  if($null-ne$q.Proof){
   $tools=@(Get-AiwReleaseRuntimeToolPaths $versionPath -Maintenance:$Maintenance)
   foreach($input in $q.Proof.Inputs.inputs){
    if($sourcePath){$others+=@{path=(Get-AiwReleaseChild $sourcePath $input.path);identity=$input.identity}}
    elseif($input.logicalRole-ceq'CURRENT_RUNTIME_TOOL'-and$input.path-cin$tools){$others+=@{path=(Get-AiwReleaseChild $runtimePath $input.distributionLocator);identity=$input.identity}}
   }
  }
  $snapshot=@{versionRoot=$versionPath;versionCanonical=(Get-AiwReleaseMemberFacts $members).Canonical;otherInputs=$others;packages=$packages}
  Assert-AiwReleaseConsumptionSnapshot $snapshot
  # CLIXML retains nested arrays, numbers and dates. Every consumer receives
  # its own object graph; the private original cannot be polluted by a caller.
  $wire=[Management.Automation.PSSerializer]::Serialize($q,100)
  $script:ReleaseAction[$key]=@{snapshot=$snapshot;wire=$wire;state=$q.State}
  return [Management.Automation.PSSerializer]::Deserialize($wire)
 }catch{if($null-ne$script:ReleaseAction){$script:ReleaseAction.Clear()};throw}
}
function Get-AiwFixedReleaseProjection([string]$VersionRoot,[string]$RuntimeRoot,$ExpectedBinding){
 # Adoption calls this only after proving the actual completed origin/current
 # transaction. It neither issues qualification nor accepts a skip switch.
 $package=Get-AiwReleasePackageFacts $RuntimeRoot
 if($package.Manifest.schemaVersion-ne2-or$package.Manifest.distributionId-cne$ExpectedBinding.distributionId-or$package.Canonical-cne$ExpectedBinding.contentIdentity-or$package.ManifestIdentity-cne$ExpectedBinding.manifestIdentity-or[IO.Path]::GetFullPath($ExpectedBinding.runtimeRoot)-cne[IO.Path]::GetFullPath($RuntimeRoot)){throw 'RELEASE_FIXED_DISTRIBUTION_DRIFT'}
 $manifestPath=Get-AiwReleaseChild $VersionRoot 'RELEASE_MANIFEST.json';$manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
 $manifest=ConvertFrom-AiwReleaseBytes $manifestBytes;$version=Read-AiwReleaseJson (Get-AiwReleaseChild $VersionRoot 'VERSION.json')
 Assert-AiwReleaseManifestShape $manifest;Assert-AiwReleaseStringFields $version @('version','lifecycle') 'version'
 if($version.version-cne$manifest.version-or$version.lifecycle-cne$manifest.lifecycle-or$version.consumable-isnot[bool]-or$version.projectPinEligible-isnot[bool]-or($manifest.lifecycle-ceq'STABLE'-and(-not$version.consumable-or-not$version.projectPinEligible))-or($manifest.lifecycle-ceq'CANDIDATE'-and($version.consumable-or$version.projectPinEligible))){throw 'RELEASE_VERSION_LIFECYCLE'}
 if($manifest.schemaVersion-eq3){
  $facts=Get-AiwReleasePayloadFacts $VersionRoot -SourceView
  $proof=$manifest.validationProof
  $v1=$proof.schemaVersion-eq1-and$proof.mode-cin@('FULL_RUN','VERIFIED_GROUP_COVERAGE');$v2=$proof.schemaVersion-in@(2,3)-and$proof.mode-ceq'CURRENT_GROUP_COVERAGE'
  if((-not$v1-and-not$v2)-or$manifest.sourceReview-cne'APPROVED'-or$proof.proofBundleIdentity-isnot[string]-or$proof.proofBundleIdentity-cnotmatch'^[A-F0-9]{64}$'-or$proof.revalidationRefs-isnot[Array]-or$proof.prepackageIntegrationRefs-isnot[Array]){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}
  if($proof.schemaVersion-eq3){Assert-AiwReleaseRef $proof.verifierRef 'fixed-verifier';if($proof.verifierRef.path-cne'scripts/TestEvidenceValidation.psm1'-or$proof.verifierRef.identity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot $proof.verifierRef.path))){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}}
  Assert-AiwReleaseRef $proof.proofBundleRef 'fixed-proof-bundle'
  if($v2){Assert-AiwReleaseRef $proof.currentSuiteRef 'fixed-current-suite';if($null-ne$proof.baselineRef){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}}
  elseif($proof.mode-ceq'FULL_RUN'){if($null-ne$proof.baselineRef-or$proof.revalidationRefs.Count){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}}
  else{Assert-AiwReleaseRef $proof.baselineRef 'fixed-baseline'}
  if($manifest.scope-cne$script:ReleaseScope-or$proof.status-cne'PASS'-or$proof.phase-cne'PREPACKAGE'-or$proof.currentPayloadCanonical-cne$facts.Canonical-or$proof.suiteDefinitionIdentity-cne(Get-AiwReleaseFileIdentity (Get-AiwReleaseChild $VersionRoot 'tests/test-groups.json'))-or$manifest.releaseIntegration-cne'PREPACKAGE_PASS'-or$proof.groupRecordRefs-isnot[Array]-or$proof.requiredGroupIds-isnot[Array]-or$proof.groupRecordRefs.Count-lt1-or$proof.requiredGroupIds.Count-ne$proof.groupRecordRefs.Count){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}
  $definition=Read-AiwReleaseJson (Get-AiwReleaseChild $VersionRoot 'tests/test-groups.json');$required=@($definition.groups|Where-Object{$_.phase-ceq'PREPACKAGE'-and'FULL'-cin$_.requiredFor}|ForEach-Object id)
  if((Get-AiwReleaseValueIdentity $required)-cne(Get-AiwReleaseValueIdentity $proof.requiredGroupIds)){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}
  $groups=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($ref in $proof.groupRecordRefs){Assert-AiwReleaseFields $ref @('groupId','path','identity') 'fixed-group-ref';Assert-AiwReleaseStringFields $ref @('groupId','path','identity') 'fixed-group-ref';Assert-AiwReleaseLocator $ref.path;if($ref.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$ref.groupId-cnotin$required-or-not$groups.Add($ref.groupId)){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}}
  $null=Assert-AiwReleaseReviewProjection $manifest
 }else{$facts=Get-AiwReleasePayloadFacts $VersionRoot;$null=Get-AiwReleaseSchema2State $version $manifest $facts}
 if($manifest.fileCount-ne$facts.FileCount-or$manifest.totalBytes-ne$facts.TotalBytes-or$manifest.canonical-cne$facts.Canonical){throw 'RELEASE_PAYLOAD_DRIFT'}
 $final=Get-AiwReleasePackageFacts $RuntimeRoot
 if($final.ManifestIdentity-cne$package.ManifestIdentity-or$final.Canonical-cne$package.Canonical){throw 'RELEASE_FIXED_DISTRIBUTION_DRIFT'}
 Write-AiwReleaseDiagnostic 'fixed-adopted-source' @{runtimeRoot=$RuntimeRoot;deepReaderCount=0}
 return [pscustomobject]@{Manifest=$manifest;Version=$version;Facts=$facts;ManifestIdentity=(Get-AiwReleaseByteIdentity $manifestBytes)}
}
# Current adopted-package declarations and actual consumed members. This is
# neither a complete package observation nor a qualification result.
function Get-AiwReleasePackageObservation([string]$PackageRoot,$ExpectedBinding,[string[]]$ConsumedPaths=@()){
 Assert-AiwReleaseFields $ExpectedBinding @('distributionId','contentIdentity','manifestIdentity','runtimeRoot') 'adopted-binding'
 $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($PackageRoot))
 if($root-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ExpectedBinding.runtimeRoot))){throw 'RELEASE_FIXED_DISTRIBUTION_DRIFT'}
 $null=Assert-AiwReleasePath $root
 if([IO.Directory]::Exists((Join-Path $root '.git'))-or[IO.File]::Exists((Join-Path $root '.git'))){throw 'RELEASE_FIXED_DEVELOPMENT_ROOT'}
 $path=Get-AiwReleaseChild $root 'PACKAGE_MANIFEST.json';$bytes=[IO.File]::ReadAllBytes($path);$identity=Get-AiwReleaseByteIdentity $bytes
 if($identity-cne$ExpectedBinding.manifestIdentity){throw 'RELEASE_FIXED_DISTRIBUTION_DRIFT'}
 $manifest=ConvertFrom-AiwReleaseBytes $bytes
 Assert-AiwReleaseFields $manifest @('schemaVersion','frameworkVersion','provisional','canonical','files','distributionId') 'package-manifest'
 if($manifest.schemaVersion-ne2-or$manifest.frameworkVersion-cne'2.0.0'-or$manifest.provisional-isnot[bool]-or$manifest.files-isnot[Array]-or$manifest.canonical-cnotmatch'^[A-F0-9]{64}$'-or$manifest.distributionId-cnotmatch'^2\.0\.0-(snapshot\.[1-9][0-9]*|release)$'-or($manifest.distributionId.EndsWith('-release')-and$manifest.provisional)){throw 'RELEASE_PACKAGE_VALUES'}
 $declared=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$rows=@()
 foreach($file in $manifest.files){
  Assert-AiwReleaseRef $file 'package-member'
  if($file.path-ceq'PACKAGE_MANIFEST.json'-or$file.path.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase)-or$file.path.StartsWith('.ai-workspace/',[StringComparison]::OrdinalIgnoreCase)-or-not$seen.Add($file.path)){throw 'RELEASE_PACKAGE_MEMBER_DRIFT'}
  $declared.Add($file.path,$file.identity);$rows+=($file.path+'='+$file.identity)
 }
 $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:ReleaseUtf8.GetBytes(($rows-join[char]10)+[char]10)))
 if($canonical-cne$manifest.canonical-or$canonical-cne$ExpectedBinding.contentIdentity-or$manifest.distributionId-cne$ExpectedBinding.distributionId){throw 'RELEASE_FIXED_DISTRIBUTION_DRIFT'}
 $observed=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 $observation=[pscustomobject]@{RuntimeRoot=$root;PackageManifest=$manifest;PackageManifestIdentity=$identity;DeclaredCanonical=$canonical;DeclaredMembers=$declared;ObservedMembers=$observed}
 foreach($relative in $ConsumedPaths){$null=Read-AiwReleaseObservedMember $observation $relative}
 if((Get-AiwReleaseFileIdentity $path)-cne$identity){throw 'RELEASE_PACKAGE_MANIFEST_DRIFT'}
 Write-AiwReleaseDiagnostic 'adopted-package-observation' @{runtimeRoot=$root;observedMembers=$observed.Count;treeEnumeration=$false;wholePackageObserved=$false}
 return $observation
}
function Read-AiwReleaseObservedMember($Observation,[string]$RelativePath){
 Assert-AiwReleaseLocator $RelativePath
 if($Observation.ObservedMembers.ContainsKey($RelativePath)){return $Observation.ObservedMembers[$RelativePath]}
 if(-not$Observation.DeclaredMembers.ContainsKey($RelativePath)){throw ('RELEASE_PACKAGE_CONSUMED_MEMBER_MISSING|'+$RelativePath)}
 $full=Get-AiwReleaseChild $Observation.RuntimeRoot $RelativePath;$bytes=[IO.File]::ReadAllBytes($full);$actual=Get-AiwReleaseByteIdentity $bytes
 if($actual-cne$Observation.DeclaredMembers[$RelativePath]){throw ('RELEASE_PACKAGE_CONSUMED_MEMBER_DRIFT|'+$RelativePath)}
 $member=[pscustomobject]@{path=$RelativePath;identity=$actual;bytes=$bytes}
 $Observation.ObservedMembers.Add($RelativePath,$member)
 return $member
}
function Read-AiwObservedPackageJson($Observation,[string]$RelativePath){
 $member=Read-AiwReleaseObservedMember $Observation $RelativePath
 return ConvertFrom-AiwReleaseBytes $member.bytes
}
function Get-AiwFixedReleaseProcessObservation([string]$VersionRoot,[string]$RuntimeRoot,$ExpectedBinding,[string[]]$ConsumedPaths=@()){
 if([IO.Path]::GetFullPath($VersionRoot)-cne[IO.Path]::GetFullPath((Join-Path $RuntimeRoot 'framework/versions/2.0.0'))){throw 'RELEASE_FIXED_VERSION_ROOT'}
 $prefix='framework/versions/2.0.0/'
 $required=@($ConsumedPaths)+@(
  ($prefix+'VERSION.json'),($prefix+'RELEASE_MANIFEST.json'),($prefix+'TOOLCHAIN.json'),($prefix+'ADOPTION_PROFILE.json'),($prefix+'PROCESS_REQUIREMENTS.json'),
  ($prefix+'scripts/ReleaseValidation.psm1'),($prefix+'scripts/StrictJsonInput.psm1'),($prefix+'scripts/TestEvidenceValidation.psm1'),
  'scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionTransaction.psm1','scripts/ProjectAdoptionProjection.psm1'
 )
 $package=Get-AiwReleasePackageObservation $RuntimeRoot $ExpectedBinding $required
 $manifest=Read-AiwObservedPackageJson $package ($prefix+'RELEASE_MANIFEST.json')
 $version=Read-AiwObservedPackageJson $package ($prefix+'VERSION.json')
 Assert-AiwReleaseManifestShape $manifest
 if($version.version-cne$manifest.version-or$version.lifecycle-cne$manifest.lifecycle-or$version.consumable-isnot[bool]-or$version.projectPinEligible-isnot[bool]-or($manifest.lifecycle-ceq'STABLE'-and(-not$version.consumable-or-not$version.projectPinEligible))-or($manifest.lifecycle-ceq'CANDIDATE'-and($version.consumable-or$version.projectPinEligible))){throw 'RELEASE_VERSION_LIFECYCLE'}
 if($manifest.sourceReview-cne'APPROVED'-or$manifest.sourceReviewEvidence.status-cne'APPROVED'){throw 'RELEASE_FIXED_QUALIFICATION_SHAPE'}
 # The real completed adoption binds these manifest bytes. Daily use does not
 # reopen suite definitions, Qpre/history attachments or a SourceView.
 $manifestIdentity=$package.ObservedMembers[$prefix+'RELEASE_MANIFEST.json'].identity
 return [pscustomobject]@{Manifest=$manifest;Version=$version;ManifestIdentity=$manifestIdentity;DeclaredPayloadCanonical=$manifest.canonical;PackageObservation=$package}
}

function Get-AiwReleasePackageFacts {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$PackageRoot)
 $manifestPath=Get-AiwReleaseChild $PackageRoot 'PACKAGE_MANIFEST.json';$manifestBytes=[IO.File]::ReadAllBytes($manifestPath);$manifestIdentity=Get-AiwReleaseByteIdentity $manifestBytes
 $manifest=ConvertFrom-AiwReleaseBytes $manifestBytes
 $fields=@('schemaVersion','frameworkVersion','provisional','canonical','files');if($manifest.schemaVersion-eq2){$fields+=@('distributionId')}elseif($manifest.schemaVersion-ne1){throw 'RELEASE_PACKAGE_SCHEMA'}
 Assert-AiwReleaseFields $manifest $fields 'package-manifest'
 if($manifest.frameworkVersion-cne'2.0.0'-or$manifest.provisional-isnot[bool]-or$manifest.files-isnot[Array]-or$manifest.canonical-cnotmatch'^[A-F0-9]{64}$'){throw 'RELEASE_PACKAGE_VALUES'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$rows=@()
 foreach($file in $manifest.files){Assert-AiwReleaseRef $file 'package-member';if($file.path-ceq'PACKAGE_MANIFEST.json'-or-not$seen.Add($file.path)){throw 'RELEASE_PACKAGE_MEMBER_DRIFT'};$rows+=($file.path+'='+$file.identity)}
 # Package manifests bind files in their listed order, as the builder and adoption reader do.
 $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:ReleaseUtf8.GetBytes(($rows-join"`n")+"`n")))
 $actual=@(Get-AiwReleaseTreeMembers $PackageRoot|Where-Object path -CNE PACKAGE_MANIFEST.json)
 if($actual.Count-ne$seen.Count-or@($actual|Where-Object{-not$seen.Contains($_.path)}).Count-or$canonical-cne$manifest.canonical){throw 'RELEASE_PACKAGE_SET_OR_CANONICAL'}
 $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 foreach($file in $manifest.files){$expected.Add($file.path,$file.identity)}
 foreach($file in $actual){if(-not$expected.ContainsKey($file.path)-or$expected[$file.path]-cne$file.identity){throw 'RELEASE_PACKAGE_MEMBER_DRIFT'}}
 if((Get-AiwReleaseFileIdentity $manifestPath)-cne$manifestIdentity){throw 'RELEASE_PACKAGE_MANIFEST_DRIFT'}
 return [pscustomobject]@{Canonical=$canonical;Manifest=$manifest;ManifestIdentity=$manifestIdentity;Members=$actual}
}
function Assert-AiwReleaseZipRuntime([string]$PackagePath,[string]$PackageRoot){
 $zip=Assert-AiwReleasePath $PackagePath;$archive=[IO.Compression.ZipFile]::OpenRead($zip);$members=@();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 try{
  foreach($entry in $archive.Entries){$path=$entry.FullName.TrimEnd('/');Assert-AiwReleaseLocator $path;if(-not$seen.Add($path)-or(($entry.ExternalAttributes-shr16)-band0xF000)-eq0xA000){throw 'RELEASE_ZIP_DUPLICATE_OR_SYMLINK'};if($entry.FullName.EndsWith('/')){continue};$stream=$entry.Open();$buffer=[IO.MemoryStream]::new();try{$stream.CopyTo($buffer);$members+=@{path=$path;identity=(Get-AiwReleaseByteIdentity $buffer.ToArray())}}finally{$buffer.Dispose();$stream.Dispose()}}
 }finally{$archive.Dispose()}
 if((Get-AiwReleaseMemberFacts $members).Canonical-cne(Get-AiwReleaseMemberFacts (Get-AiwReleaseTreeMembers $PackageRoot)).Canonical){throw 'RELEASE_ZIP_RUNTIME_BINDING'}
}
function Assert-AiwReleaseBuildEvidence([string]$BuildCommandPath,[string]$PackagePath,$PackageFacts,$Qualification){
 $command=Read-AiwReleaseJson $BuildCommandPath
 Assert-AiwReleaseFields $command @('runId','status','command','pid','creationUtc','executor','directConsumer','startedUtc','processExitedUtc','endedUtc','exitCode','stdout','stderr','timing','cancellation','streamOrdering') 'build-command'
 Assert-AiwReleaseFields $command.command @('executable','executableIdentity','executableVersion','arguments','cwd') 'build-native-command'
 if($command.status-cne'PASS'-or$command.exitCode-ne0-or$null-ne$command.cancellation-or$command.streamOrdering-cne'INTRA_STREAM_ONLY'){throw 'RELEASE_BUILD_COMMAND_NOT_PASS'}
 foreach($name in @('stdout','stderr')){Assert-AiwReleaseFields $command.$name @('path','identity') 'build-raw';if((Get-AiwReleaseFileIdentity $command.$name.path)-cne$command.$name.identity){throw 'RELEASE_BUILD_RAW_DRIFT'}}
 try{$values=(ConvertFrom-AiwStrictInputJson ([IO.File]::ReadAllText((Assert-AiwReleasePath $command.stdout.path),$script:ReleaseUtf8))).Value;$result=@($values);if($result.Count-ne1){throw 'count'};$result=$result[0]}catch{throw 'RELEASE_BUILD_RESULT_REQUIRED'}
 if($result.status-cne'BUILT_UNVERIFIED'-or$result.frameworkVersion-cne'2.0.0'-or$result.outputPath-cne[IO.Path]::GetFullPath($PackagePath)-or$result.canonical-cne$PackageFacts.Canonical-or$result.fileCount-ne$PackageFacts.Members.Count-or$result.sourceManifestIdentity-cne$Qualification.ManifestIdentity-or$result.sourcePayloadCanonical-cne$Qualification.Facts.Canonical){throw 'RELEASE_BUILD_RESULT_BINDING'}
 return $command
}
function Expand-AiwReleasePackage {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$PackagePath,[Parameter(Mandatory)][string]$DestinationRoot)
 $zip=Assert-AiwReleasePath $PackagePath;$destination=Assert-AiwReleasePath $DestinationRoot
 if(Test-Path -LiteralPath $destination){throw 'RELEASE_EXTRACT_DESTINATION_EXISTS'}
 $archive=[IO.Compression.ZipFile]::OpenRead($zip)
 try{
  $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $fileNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach($entry in $archive.Entries){$path=$entry.FullName;if($path.EndsWith('/')){$path=$path.TrimEnd('/')}else{$null=$fileNames.Add($path)};Assert-AiwReleaseLocator $path;if(-not$seen.Add($path)){throw 'RELEASE_ZIP_DUPLICATE'};$null=Get-AiwReleaseChild $destination $path;$type=($entry.ExternalAttributes-shr16)-band0xF000;if($type-eq0xA000){throw 'RELEASE_ZIP_SYMLINK'}}
  foreach($entry in $archive.Entries){$parts=$entry.FullName.TrimEnd('/').Split('/');for($i=1;$i -lt $parts.Count;$i++){if($fileNames.Contains(($parts[0..($i-1)]-join'/'))){throw 'RELEASE_ZIP_FILE_DIRECTORY_CONFLICT'}}}
  foreach($entry in $archive.Entries){if($entry.FullName.EndsWith('/')){continue};$path=Get-AiwReleaseChild $destination $entry.FullName;$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$path,$false)}
 }finally{$archive.Dispose()}
 return Get-AiwReleasePackageFacts $destination
}
function Assert-AiwReleaseLoadedInputs {
 foreach($input in $script:ReleaseLoadedInputs){if((Get-AiwReleaseFileIdentity $input.path)-cne$input.identity){throw 'RELEASE_READER_MODULE_DRIFT'}}
 if($null-ne$script:ReleaseNavigationOwner){
  $path=Get-AiwReleaseChild (Assert-AiwReleasePath (Join-Path $PSScriptRoot '../../../..')) 'scripts/ProjectAdoptionState.psm1'
  $command=$script:ReleaseNavigationOwner.ExportedCommands['Get-AiwNavigationContract']
  $body=& $script:ReleaseNavigationOwner {(Get-Item Function:Get-AiwNavigationContract).ScriptBlock}
  if($script:ReleaseNavigationOwner.Path-cne$path-or$null-eq$command-or-not[object]::ReferenceEquals($command.Module,$script:ReleaseNavigationOwner)-or-not[object]::ReferenceEquals($command,$script:ReleaseNavigationCommand)-or-not[object]::ReferenceEquals($body,$script:ReleaseNavigationBody)-or-not[object]::ReferenceEquals($command.ScriptBlock,$script:ReleaseNavigationBody)){throw 'RELEASE_READER_MODULE_OWNER'}
 }
 if($script:ReleaseEvidenceOwner.Path-cne[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'TestEvidenceValidation.psm1'))){throw 'RELEASE_READER_MODULE_OWNER'}
 $null=& $script:ReleaseEvidenceOwner.ExportedCommands['Get-AiwEvidenceLoadedIdentity']
}
$script:ReleaseLoadedInputs=@(foreach($path in @($script:ReleaseModulePath,(Join-Path $PSScriptRoot 'StrictJsonInput.psm1'),(Join-Path $PSScriptRoot 'TestEvidenceValidation.psm1'))){@{path=$path;identity=(Get-AiwReleaseFileIdentity $path)}})
Export-ModuleMember -Function ConvertTo-AiwReleaseEvidenceTime,Assert-AiwReleaseCurrentSuiteShape,Assert-AiwReleaseCurrentRevalidation,Assert-AiwReleaseCurrentExecution,Assert-AiwReleasePath,Assert-AiwReleaseLocator,Get-AiwReleaseChild,Get-AiwReleaseFileIdentity,Get-AiwReleaseByteIdentity,Read-AiwReleaseJson,Get-AiwReleaseCanonical,Get-AiwReleaseValueIdentity,Get-AiwReleaseTreeMembers,Get-AiwReleaseMemberFacts,Get-AiwReleasePayloadFacts,Get-AiwReleaseRuntimeToolPaths,Get-AiwReleaseQualification,Invoke-AiwReleaseQualificationScope,Get-AiwReleaseSchema2State,Assert-AiwReleaseManifestShape,Assert-AiwReleaseReviewProjection,Assert-AiwReleaseProof,Get-AiwReleasePackageFacts,Assert-AiwReleaseZipRuntime,Assert-AiwReleaseBuildEvidence,Expand-AiwReleasePackage
