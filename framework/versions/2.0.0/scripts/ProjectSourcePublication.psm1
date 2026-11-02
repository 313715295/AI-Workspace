Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
$script:PublicationUtf8=[Text.UTF8Encoding]::new($false,$true)
# Registration alone grants no bypass. A borrower must present a real live
# lease from the current PowerShell call stack in this same runspace.
$script:PublicationLeases=[Runtime.CompilerServices.ConditionalWeakTable[object,object]]::new()
$script:PublicationModule=$ExecutionContext.SessionState.Module
$script:PublicationClosureObservations=$null

# Only the boundary's private invocation owns this map. No public input can
# supply an observation; nested/new boundaries start afresh and every exit
# releases it. This is computation reuse, never a coordination/read lease.
function Invoke-PubClosureObservationScope([scriptblock]$Body,[object[]]$Arguments){
 $previous=$script:PublicationClosureObservations
 $script:PublicationClosureObservations=@{}
 try { & $Body @Arguments } finally { $script:PublicationClosureObservations=$previous }
}

function Invoke-PubSelectedComposition([hashtable]$Arguments){
 # This private producer accepts ordinary composition arguments, never supplied
 # material. A nested boundary has its own table; failure cannot leave a prior
 # capture available to a later call in this scope.
 if($null-eq$script:PublicationClosureObservations){throw 'SOURCE_PUBLICATION_COMPOSITION_SCOPE_REQUIRED'}
 $script:PublicationClosureObservations.Remove('SELECTED_STANDARDS')
 if($Arguments.ContainsKey('PublicationMaterial')-or$Arguments.ContainsKey('BindingSnapshotOnly')){throw 'SOURCE_PUBLICATION_PRIVATE_COMPOSITION_INPUT'}
 $composition=@(Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru)[0]
 $captured=& $composition {
  param($parameters)
  $material=$null
  $result=Invoke-AiwProcessCompositionCore @parameters -PublicationMaterial ([ref]$material)
  [pscustomobject]@{result=$result;material=$material}
 } $Arguments
 if($null-ne$captured.material){$script:PublicationClosureObservations['SELECTED_STANDARDS']=$captured.material}
 return $captured.result
}

function Get-PubByteIdentity([byte[]]$Bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return $Bytes.Length.ToString()+'|'+([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','')}
 finally{$sha.Dispose()}
}
function Get-PubIdentity([string]$Path){
 if(-not[IO.File]::Exists($Path)){return 'NEW'}
 return Get-PubByteIdentity ([IO.File]::ReadAllBytes($Path))
}
$script:PublicationImplementationIdentity=Get-PubIdentity $script:PublicationModule.Path
function Assert-PubFields($Value,[string[]]$Fields,[string]$Label){
 if($Value-isnot[pscustomobject]-or@($Value.PSObject.Properties).Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin@($Value.PSObject.Properties.Name)}).Count){throw ('SOURCE_PUBLICATION_FIELDS|'+$Label)}
}
function Assert-PubInteger($Value,[string]$Label){
 if($Value-isnot[int]-and$Value-isnot[long]){throw ('SOURCE_PUBLICATION_INTEGER|'+$Label)}
}
function Assert-PubPath([string]$Path){
 $full=[IO.Path]::GetFullPath($Path);$current=[IO.Path]::GetPathRoot($full)
 $parts=@($full.Substring($current.Length).Split([char[]]@([char]92,[char]47),[StringSplitOptions]::RemoveEmptyEntries))
 for($index=-1;$index-lt$parts.Count;$index++){
  if($index-ge0){$current=[IO.Path]::Combine($current,$parts[$index])}
  # Callers reject protected paths before entering this fresh metadata walk.
  # Missing components may be created by publication; unreadable components
  # and non-directory ancestors cannot be treated as missing destinations.
  # Check ancestors first so a reparse entry is rejected before descending.
  try{
   $attributes=[IO.File]::GetAttributes($current)
   if(($attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'SOURCE_PUBLICATION_REPARSE'}
   if($index-lt($parts.Count-1)-and($attributes-band[IO.FileAttributes]::Directory)-eq0){throw 'SOURCE_PUBLICATION_NOT_REGULAR_FILE'}
  }catch [IO.FileNotFoundException],[IO.DirectoryNotFoundException]{
   if($index-eq-1){throw 'SOURCE_PUBLICATION_PATH'}
  }
 }
}
function Get-PubRoot([string]$Root){
 if(-not[IO.Path]::IsPathFullyQualified($Root)){throw 'SOURCE_PUBLICATION_ROOT_ABSOLUTE'}
 if(-not$IsWindows-or$PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7-or$Root.StartsWith('\\',[StringComparison]::Ordinal)){throw 'SOURCE_PUBLICATION_PLATFORM_UNSUPPORTED'}
 $full=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root));Assert-PubPath $full
 $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
 if(-not$item.PSIsContainer){throw 'SOURCE_PUBLICATION_ROOT_NOT_DIRECTORY'}
 if(-not$IsWindows){throw 'SOURCE_PUBLICATION_PLATFORM_UNSUPPORTED'}
 if($null-eq('AiwPublication.NativeDirectory' -as[type])){
  Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
namespace AiwPublication {
 public static class NativeDirectory {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern SafeFileHandle CreateFileW(string p,uint a,uint s,IntPtr sec,uint c,uint flags,IntPtr t);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern uint GetFinalPathNameByHandleW(SafeFileHandle h,StringBuilder b,uint n,uint f);
  [StructLayout(LayoutKind.Sequential)] struct FileInfo { public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME creation,access,write; public uint volume,sizeHigh,sizeLow,links,indexHigh,indexLow; }
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out FileInfo i);
  public static void SingleLink(SafeFileHandle h) { FileInfo i; if(!GetFileInformationByHandle(h,out i)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); if(i.links!=1) throw new System.IO.IOException("SOURCE_PUBLICATION_LOCK_ALIAS"); }
  public static string Canonical(string p) {
   using(var h=CreateFileW(p,0,7,IntPtr.Zero,3,0x02000000,IntPtr.Zero)) {
    if(h.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    var b=new StringBuilder(32768); uint n=GetFinalPathNameByHandleW(h,b,(uint)b.Capacity,0);
    if(n==0 || n>=b.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    var r=b.ToString(); if(r.StartsWith(@"\\?\UNC\")) return @"\\"+r.Substring(8);
    return r.StartsWith(@"\\?\") ? r.Substring(4) : r;
   }
  }
 }
}
'@
 }
 $canonical=[IO.Path]::TrimEndingDirectorySeparator([AiwPublication.NativeDirectory]::Canonical($item.FullName))
 Assert-PubPath $canonical
 return $canonical
}
function Get-PubChild([string]$Root,[string]$Relative,[string[]]$Forbidden=@()){
 if([string]::IsNullOrWhiteSpace($Relative)-or[IO.Path]::IsPathRooted($Relative)-or$Relative.Contains('\')-or$Relative.Split('/')-contains'..'-or$Relative.Split('/')-contains'.'-or$Relative-match'[:*?\x00-\x1F]'){throw 'SOURCE_PUBLICATION_PATH'}
 if($Relative-cne$Relative.Normalize([Text.NormalizationForm]::FormC)){throw 'SOURCE_PUBLICATION_PATH_ALIAS'}
 foreach($segment in $Relative.Split('/')){if([string]::IsNullOrWhiteSpace($segment)-or$segment.EndsWith('.')-or$segment.EndsWith(' ')-or$segment-match'(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'SOURCE_PUBLICATION_PATH_ALIAS'}}
 $path=[IO.Path]::GetFullPath([IO.Path]::Combine($Root,$Relative));$prefix=$Root+[IO.Path]::DirectorySeparatorChar
 if(-not$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_PUBLICATION_PATH_ESCAPE'}
 foreach($bound in $Forbidden){
  $ban=if([IO.Path]::IsPathFullyQualified($bound)){[IO.Path]::GetFullPath($bound)}else{[IO.Path]::GetFullPath([IO.Path]::Combine($Root,$bound.TrimEnd('/','\')))}
  if($path.Equals($ban,[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith($ban+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_PUBLICATION_FORBIDDEN'}
 }
 Assert-PubPath $path
 try{
  $attributes=[IO.File]::GetAttributes($path)
  if(($attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'SOURCE_PUBLICATION_REPARSE'}
  if(($attributes-band[IO.FileAttributes]::Directory)-ne0){throw 'SOURCE_PUBLICATION_NOT_REGULAR_FILE'}
 }catch [IO.FileNotFoundException],[IO.DirectoryNotFoundException]{}
 return $path
}
function Read-PubRef($Ref,[string[]]$Forbidden=@()){
 Assert-PubFields $Ref @('path','identity') REF
 if($Ref.path-isnot[string]-or-not[IO.Path]::IsPathFullyQualified($Ref.path)-or$Ref.identity-isnot[string]-or$Ref.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'SOURCE_PUBLICATION_REF'}
 $path=[IO.Path]::GetFullPath($Ref.path)
 foreach($ban in $Forbidden){if([IO.Path]::IsPathFullyQualified($ban)-and($path.Equals($ban,[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith($ban.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'SOURCE_PUBLICATION_FORBIDDEN'}}
 Assert-PubPath $path
 if(-not[IO.File]::Exists($path)){throw 'SOURCE_PUBLICATION_REF_DRIFT'}
 $bytes=[IO.File]::ReadAllBytes($path)
 $identity=Get-PubByteIdentity $bytes
 if($identity-cne$Ref.identity){throw 'SOURCE_PUBLICATION_REF_DRIFT'}
 return [pscustomobject]@{Path=$path;Identity=$Ref.identity;Bytes=$bytes;Text=$script:PublicationUtf8.GetString($bytes)}
}
function Read-PubJson($Ref,[string[]]$Forbidden=@()){
 $doc=Read-PubRef $Ref $Forbidden
 $value=(ConvertFrom-AiwStrictInputJson $doc.Text).Value
 $doc|Add-Member Value $value
 return $doc
}
function Get-PubCanonical($Value){
 # Sort the value once and serialize once. Serializing every scalar/property
 # separately made complete publication plans pay thousands of cmdlet calls.
 function Convert-PubOrderedValue($Item){
  if($null-eq$Item){return $null}
  if($Item-is[string]-or$Item-is[bool]-or$Item-is[ValueType]){return $Item}
  if($Item-is[array]-or$Item-is[Collections.IList]){
   $items=[Collections.Generic.List[object]]::new()
   foreach($element in $Item){$items.Add((Convert-PubOrderedValue $element))}
   return ,$items.ToArray()
  }
  $dictionary=$Item-is[Collections.IDictionary]
  [string[]]$keys=@(if($dictionary){$Item.Keys}else{foreach($property in $Item.PSObject.Properties){$property.Name}})
  [Array]::Sort($keys,[StringComparer]::Ordinal);$ordered=[ordered]@{}
  foreach($key in $keys){
   if($dictionary){$ordered[$key]=Convert-PubOrderedValue $Item[$key]}else{$ordered[$key]=Convert-PubOrderedValue $Item.$key}
  }
  return $ordered
 }
 return ConvertTo-Json -InputObject (Convert-PubOrderedValue $Value) -Compress -Depth 100
}
function Get-PubValueIdentity($Value){
 $b=$script:PublicationUtf8.GetBytes((Get-PubCanonical $Value))
 return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))
}
function Get-PubForbidden([string]$Root,[string[]]$Paths){
 return @(foreach($p in $Paths){if([IO.Path]::IsPathFullyQualified($p)){[IO.Path]::GetFullPath($p)}else{[IO.Path]::GetFullPath((Join-Path $Root $p.TrimEnd('/','\')))}})
}
function Read-PubEvidence($Ref,[string]$Root,[string[]]$Forbidden=@(),[switch]$Json){
 Assert-PubFields $Ref @('path','identity') REF
 $prefix=Join-Path $Root '.ai-workspace'
 if($Ref.path-isnot[string]-or-not[IO.Path]::IsPathFullyQualified($Ref.path)-or-not[IO.Path]::GetFullPath($Ref.path).StartsWith($prefix+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_PUBLICATION_EVIDENCE_SCOPE'}
 if($Json){return Read-PubJson $Ref $Forbidden}
 return Read-PubRef $Ref $Forbidden
}
function Get-AiwPublicationInputProjectRoot {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$InputPath)
 # Only the caller-owned envelope/compact locator is read here. No project
 # authority or professional source is observed until the shared handle opens.
 $input=(Read-AiwStrictInputJson $InputPath).Value
 if($null-ne$input.PSObject.Properties['projectRoot']){return Get-PubRoot $input.projectRoot}
 if($null-ne$input.PSObject.Properties['discoverReceiptPath']){
  $input=(Read-AiwStrictInputJson ([string]$input.discoverReceiptPath)).Value
 }
 # Persisted compact2/3 keep authority in binding; only compact1 has the
 # project locator used by the boundary's private normalized in-memory view.
 if($input.schemaVersion-in@(2,3,4)-and$null-ne$input.PSObject.Properties['binding']){return Get-PubRoot $input.binding.projectRoot}
 if($input.schemaVersion-eq1-and$null-ne$input.PSObject.Properties['sourceLocators']){return Get-PubRoot $input.sourceLocators.projectRoot}
 throw 'SOURCE_PUBLICATION_INPUT_ROOT_REQUIRED'
}
function Assert-PubProfessionalPath([string]$Root,[string]$Relative,[string[]]$Forbidden){
 $path=Get-PubChild $Root $Relative $Forbidden
 if([IO.Path]::GetExtension($Relative)-ine'.md'-or$Relative-match'(?i)(^|/)(\.ai-workspace|\.git|\.codex|\.claude|framework|runtimes|node_modules|scripts?|tests?|src|products?|dist|build|target)(/|$)'-or[IO.Path]::GetFileName($Relative)-imatch'^(AGENTS|CLAUDE|CODEX|BOOTSTRAP|SKILL)\.md$'){throw 'SOURCE_PUBLICATION_PROFESSIONAL_TARGET_REQUIRED'}
 return $path
}
function Assert-PubArray($Value,[string]$Label,[switch]$Nonempty){
 if($Value-isnot[array]-or($Nonempty-and$Value.Count-eq0)){throw ('SOURCE_PUBLICATION_ARRAY|'+$Label)}
}
function Get-PubObjectDocuments($Plan,[string]$Root,[string[]]$Forbidden){
 Assert-PubArray $Plan.objects OBJECTS -Nonempty
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 $docs=@{};$source=@();$control=@()
 foreach($object in $Plan.objects){
  Assert-PubFields $object @('path','ownerMember','preimage','postimage') OBJECT
  if($object.path-isnot[string]-or-not$seen.Add($object.path)-or$object.ownerMember-cnotin@('SOURCE','CONTROL')){throw 'SOURCE_PUBLICATION_OBJECT'}
  if($object.ownerMember-ceq'SOURCE'){$null=Assert-PubProfessionalPath $Root $object.path $Forbidden;$source+=,$object.path}
  else{if($object.path-cnotin@('.ai-workspace/process-policy.json','.ai-workspace/project.json')){throw 'SOURCE_PUBLICATION_CONTROL_SCOPE'};$null=Get-PubChild $Root $object.path $Forbidden;$control+=,$object.path}
  foreach($side in @('preimage','postimage')){
   if($side-ceq'preimage'-and$object.preimage.identity-ceq'NEW'){
    Assert-PubFields $object.preimage @('path','identity') NEW_REF
    if($object.ownerMember-cne'SOURCE'-or$object.preimage.path-cne$object.path){throw 'SOURCE_PUBLICATION_NEW_PREIMAGE'}
    $docs[$object.path+'|'+$side]=$null;continue
   }
   $doc=Read-PubEvidence $object.$side $Root $Forbidden -Json:($object.ownerMember-ceq'CONTROL')
   if($object.ownerMember-ceq'SOURCE'-and([string]::IsNullOrWhiteSpace($doc.Text)-or$doc.Text.Contains([char]0))){throw 'SOURCE_PUBLICATION_MARKDOWN_REQUIRED'}
   $docs[$object.path+'|'+$side]=$doc
  }
 }
 if($source.Count-eq0-or$control.Count-ne2){throw 'SOURCE_PUBLICATION_TWO_MEMBER_SCOPE'}
 if(@($Plan.objects|Where-Object{$_.ownerMember-ceq'SOURCE'-and$_.preimage.identity-cne$_.postimage.identity}).Count-eq0-or@($Plan.objects|Where-Object{$_.ownerMember-ceq'CONTROL'-and$_.preimage.identity-cne$_.postimage.identity}).Count-eq0){throw 'SOURCE_PUBLICATION_EMPTY_MEMBER'}
 $expected=@($source)+@('.ai-workspace/process-policy.json','.ai-workspace/project.json')
 if((Get-PubCanonical @($Plan.objects.path))-cne(Get-PubCanonical $expected)){throw 'SOURCE_PUBLICATION_OBJECT_ORDER'}
 Assert-PubArray $Plan.writeOrder WRITE_ORDER
 $changes=@($Plan.objects|Where-Object{$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object path)
 if((Get-PubCanonical $changes)-cne(Get-PubCanonical @($Plan.writeOrder))){throw 'SOURCE_PUBLICATION_WRITE_ORDER'}
 return [pscustomobject]@{documents=$docs;sourcePaths=$source;controlPaths=$control}
}
function Get-AiwProjectSourcePublicationReachability {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Plan,[string[]]$ForbiddenPaths=@())
 $aiwPublicationScopeLease=Enter-AiwProjectSourceScope $ProjectRoot
 try{
  return Get-PubReachability $ProjectRoot $Plan $ForbiddenPaths
 }finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
}
function Get-PubReachability([string]$ProjectRoot,$Plan,[string[]]$ForbiddenPaths){
 $root=Get-PubRoot $ProjectRoot;$forbidden=Get-PubForbidden $root $ForbiddenPaths
 $changed=@($Plan.writeOrder);$prefix=0;$oldSeen=$false;$postimages=@()
 foreach($object in $Plan.objects){
  $path=Get-PubChild $root $object.path $forbidden;$identity=Get-PubIdentity $path
  if($identity-cne$object.preimage.identity-and$identity-cne$object.postimage.identity){throw ('SOURCE_PUBLICATION_THIRD_PARTY_OBJECT|'+$object.path)}
  $postimages+=,[pscustomobject]@{path=$object.path;identity=$identity}
  if($object.path-cnotin$changed){continue}
  if($identity-ceq$object.preimage.identity){$oldSeen=$true}
  else{if($oldSeen){throw 'SOURCE_PUBLICATION_UNREACHABLE_GROUP'};$prefix++}
 }
 return [pscustomobject]@{prefix=$prefix;changedCount=$changed.Count;allOld=($prefix-eq0);allNew=($prefix-eq$changed.Count);objects=$postimages}
}
function Remove-PubProjectionCache([string]$Projection){
    # This namespace belongs to this freshly created projection, never to the
    # caller's mutable Context. Git scratch must already have been released.
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Projection))
    $temporary=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    if([IO.Path]::GetDirectoryName($root)-cne$temporary-or[IO.Path]::GetFileName($root)-cnotmatch'^aiw-publication-[a-f0-9]{32}$'){throw 'SOURCE_PROJECTION_CLEANUP_SCOPE'}
    $control=Join-Path $root '.ai-workspace';$runtime=Join-Path $control 'runtime'
    foreach($path in @($root,$control,$runtime)){
        if(-not[IO.Directory]::Exists($path)){return}
        if([IO.File]::GetAttributes($path)-band[IO.FileAttributes]::ReparsePoint){throw 'SOURCE_PROJECTION_CLEANUP_REPARSE'}
    }
    foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($runtime)){
        if([IO.Path]::GetFileName($entry)-cne'content-sources'){continue}
        $cache=[IO.Path]::GetFullPath($entry)
        if(-not$cache.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or([IO.File]::GetAttributes($cache)-band[IO.FileAttributes]::ReparsePoint)-or-not[IO.Directory]::Exists($cache)){throw 'SOURCE_PROJECTION_CACHE_OWNER'}
        $files=@([IO.Directory]::EnumerateFileSystemEntries($cache))
        foreach($file in $files){$attributes=[IO.File]::GetAttributes($file);if(($attributes-band([IO.FileAttributes]::Directory-bor[IO.FileAttributes]::ReparsePoint))-or[IO.Path]::GetFileName($file)-cnotmatch'^[A-Fa-f0-9]{64}\.bin$'){throw 'SOURCE_PROJECTION_CACHE_UNKNOWN_RESOURCE'}}
        foreach($file in $files){[IO.File]::Delete($file)}
        [IO.Directory]::Delete($cache)
    }
    if(@([IO.Directory]::EnumerateFileSystemEntries($runtime)).Count-eq0){[IO.Directory]::Delete($runtime)}
}
function Invoke-PubSourceProjection($Plan,$Documents,[string]$Side,[string]$Root,[string[]]$Forbidden,[scriptblock]$Consumer){
 $projection=Join-Path ([IO.Path]::GetTempPath()) ('aiw-publication-'+[guid]::NewGuid().ToString('N'))
 $files=[Collections.Generic.List[string]]::new();$directories=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 $projectionFailure=$null
 try{
  $projected=@()
  foreach($object in $Plan.objects){
   $doc=$Documents[$object.path+'|'+$Side];if($null-eq$doc){continue}
   $copy=Get-PubChild ([IO.Path]::GetFullPath($projection)) $object.path
   $parent=[IO.Path]::GetDirectoryName($copy)
   $walk=$parent;while($walk.StartsWith($projection,[StringComparison]::OrdinalIgnoreCase)){$null=$directories.Add($walk);if($walk-ceq$projection){break};$walk=[IO.Path]::GetDirectoryName($walk)}
   [IO.Directory]::CreateDirectory($parent)|Out-Null;[IO.File]::WriteAllBytes($copy,$doc.Bytes);$files.Add($copy)
   if($object.ownerMember-ceq'SOURCE'){$projected+=,[pscustomobject]@{kind='FILE';path=$object.path;newExists=$true;newBase64=[Convert]::ToBase64String($doc.Bytes);newIdentity=$doc.Identity}}
  }
  Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
  Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
  $config=$Documents['.ai-workspace/project.json|'+$Side];$policy=$Documents['.ai-workspace/process-policy.json|'+$Side]
  $ctx=New-AiwContentContext -ProjectRoot $projection -SourceProjectRoot $Root -ExpectedProjectConfigIdentity $config.Identity -ForbiddenPaths $Forbidden -ProjectedSourceObjects $projected
  return & $Consumer $ctx $config $policy
 }catch{$projectionFailure=$_;throw}finally{
  try{
  foreach($file in $files){if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
  Remove-PubProjectionCache $projection
  foreach($directory in @($directories|Sort-Object Length -Descending)){if([IO.Directory]::Exists($directory)){[IO.Directory]::Delete($directory)}}
  }catch{if($null-ne$projectionFailure){$projectionFailure.Exception.Data['PublicationProjectionCleanupFailure']=$_.Exception.Message}else{throw}}
 }
}
function Get-PubClosure($Plan,$Documents,[string]$Side,[string]$Root,[string[]]$Forbidden){
 return (Get-PubClosureObservationCore $Plan $Documents $Side $Root $Forbidden $null).closure
}
function Get-PubClosureObservationCore($Plan,$Documents,[string]$Side,[string]$Root,[string[]]$Forbidden,$PreviousMaterial){
 return Invoke-PubSourceProjection $Plan $Documents $Side $Root $Forbidden {
  param($context,$config,$policy)
  $composition=(Get-Command Get-AiwProjectPolicySourceClosure).Module
  $observation=& $composition {param($r,$rules,$f,$c,$previous)Get-AiwProjectPolicySourceClosureCore -ProjectRoot $r -Rules $rules -ForbiddenPaths $f -ContentContext $c -PreviousMaterial $previous} $Root @($policy.Value.rules) $Forbidden $context $PreviousMaterial
  $closure=$observation.Closure
  $null=Assert-AiwProjectPolicySourceClosure -Closure $closure -ContentContext $context
  return [pscustomobject]@{closure=[pscustomobject]@{identity=$closure.Identity;documents=@($closure.Documents|ForEach-Object{[pscustomobject]@{locatorKind=$_.locatorKind;locator=$_.locator;relativePath=$_.relativePath;sourcePath=$_.sourcePath;identity=$_.identity}})};material=$observation.Material}
 }
}
function Get-PubClosurePair($Plan,$Documents,[string]$Root,[string[]]$Forbidden,$PreviousMaterial=$null){
 # Call-local material only; no state survives failure, cancellation, nesting or
 # a later public request. Each projection retains its original cleanup and
 # current closure assertion. The standalone reader remains independent.
 $old=Get-PubClosureObservationCore $Plan $Documents preimage $Root $Forbidden $PreviousMaterial
 $target=Get-PubClosureObservationCore $Plan $Documents postimage $Root $Forbidden $old.material
 return [pscustomobject]@{old=$old.closure;target=$target.closure}
}
function Get-PubSelectorChanges($OldPolicy,$NewPolicy){
 $changes=@()
 foreach($id in @(@($OldPolicy.rules)+@($NewPolicy.rules)|ForEach-Object{$_.ruleId}|Sort-Object -Unique -CaseSensitive)){
  $before=@($OldPolicy.rules|Where-Object ruleId -CEQ $id);$after=@($NewPolicy.rules|Where-Object ruleId -CEQ $id)
  # Sources change whole identities; all other rule fields, including selectors
  # and obligations, are an independently visible semantic difference.
  $rows=@(foreach($set in @(@{items=$before},@{items=$after})){
   $items=@(foreach($rule in $set.items){$copy=$rule|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$copy.PSObject.Properties.Remove('source');$copy})
   ,$items
  })
  if((Get-PubCanonical $rows[0])-cne(Get-PubCanonical $rows[1])){$changes+=,[pscustomobject]@{ruleId=$id;before=$rows[0];after=$rows[1]}}
 }
 return $changes
}
function Get-AiwProjectSourcePublicationEligibility {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Package,[string[]]$ForbiddenPaths=@())
 return Get-PubEligibilityCore $ProjectRoot $Package $ForbiddenPaths $script:PublicationClosureObservations
}
function Test-PubClosureObservation($Observation,$Plan,$Documents,[string]$Root,[string[]]$Forbidden){
 # The enclosing eligibility call has reread the exact plan/config/policy,
 # decision and permission declarations. Recheck every physical member, even
 # those outside M/R objects, before borrowing either complete graph.
 foreach($side in @('preimage','postimage')){
  $closure=if($side-ceq'preimage'){$Observation.old}else{$Observation.target}
  foreach($document in $closure.documents){
   if($document.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')){return $false}
   $path=$document.sourcePath
   foreach($object in $Plan.objects){
    if($object.ownerMember-ceq'SOURCE'-and$path.Equals([IO.Path]::GetFullPath((Join-Path $Root $object.path)),[StringComparison]::OrdinalIgnoreCase)){
     $doc=$Documents[$object.path+'|'+$side]
     if($null-ne$doc){$path=$doc.Path}
     break
    }
   }
   $null=Read-PubRef ([pscustomobject]@{path=$path;identity=$document.identity}) $Forbidden
  }
 }
 return $true
}
function Get-PubEligibilityCore {
 param([string]$ProjectRoot,$Package,[string[]]$ForbiddenPaths=@(),[hashtable]$ClosureObservation=$null)
 $aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $ProjectRoot
 try{
  $root=Get-PubRoot $ProjectRoot;$forbidden=Get-PubForbidden $root $ForbiddenPaths
  $binding=$Package.sourcePublicationBinding;Assert-PubFields $binding @('planRef','member') BINDING
  if($binding.member-cnotin@('SOURCE','CONTROL')-or$Package.schemaVersion-notin@(1,2)-or@($Package.actions).Count-ne1-or$Package.actions[0]-cne$(if($binding.member-ceq'SOURCE'){'SOURCE_WRITE'}else{'CONTROL_WRITE'})){throw 'SOURCE_PUBLICATION_PURE_MEMBER_REQUIRED'}
  foreach($field in @('continuationPlan','repairReviewPlan','repairReviewBinding','selfCheckRepairLimit','transitionPlan','postObjectIdentities','targetFrameworkSnapshot','acceptanceBinding','externalBinding','gitPushBinding')){if($null-ne$Package.PSObject.Properties[$field]){throw 'SOURCE_PUBLICATION_MIXED_PACKAGE'}}
  if($Package.schemaVersion-eq2-and$Package.repositoryId-cne'CONTROL'){throw 'SOURCE_PUBLICATION_PROJECT_OWNERSHIP_REQUIRED'}
  $planDocument=Read-PubEvidence $binding.planRef $root $forbidden -Json;$plan=$planDocument.Value
  $planFields=@('schemaVersion','kind','projectRoot','repositoryId','frameworkRoot','taskPath','taskId','taskIdentity','owner','actor','controllerIdentity','projectConfigIdentity','userDecision','decisionRef','assuranceEvidence','objects','writeOrder','permissionChanges','selectorChanges','sourceClosure','rootToolDependencies')
  if($null-ne$plan.PSObject.Properties['reviewScope']){$planFields+='reviewScope'}
  if($null-ne$plan.PSObject.Properties['assuranceConsumption']){$planFields+='assuranceConsumption'}
  Assert-PubFields $plan $planFields PLAN
  Assert-PubInteger $plan.schemaVersion PLAN_SCHEMA
  if($plan.schemaVersion-ne1-or$plan.kind-cne'PROJECT_SOURCE_PUBLICATION_PLAN'-or(Get-PubRoot $plan.projectRoot)-cne$root-or$plan.repositoryId-cne$(if($Package.schemaVersion-eq2){$Package.repositoryId}else{'REPO_LOCAL'})){throw 'SOURCE_PUBLICATION_PLAN_ROOT'}
  foreach($pair in @(@('taskId','taskId'),@('taskIdentity','taskIdentity'),@('owner','owner'),@('actor','grantee'),@('projectConfigIdentity','projectConfigIdentity'),@('userDecision','userConfirmation'))){if($plan.($pair[0])-cne$Package.($pair[1])){throw ('SOURCE_PUBLICATION_AUTHORITY_BINDING|'+$pair[0])}}
  # Config-carrier exclusions are established before even inspecting any docs
  # target or candidate body. A protected reference must fail before stat/hash.
  $configObject=@($plan.objects|Where-Object path -CEQ '.ai-workspace/project.json')
  if($configObject.Count-ne1-or$configObject[0].ownerMember-cne'CONTROL'){throw 'SOURCE_PUBLICATION_CONFIG_OBJECT_REQUIRED'}
  $original=(Read-PubEvidence $configObject[0].preimage $root $forbidden -Json).Value
  $prospective=(Read-PubEvidence $configObject[0].postimage $root $forbidden -Json).Value
  $forbidden=@($forbidden)+@(Get-PubForbidden $root @($original.routineExcludedPaths))+@(Get-PubForbidden $root @($prospective.routineExcludedPaths))
  $facts=Get-PubObjectDocuments $plan $root $forbidden;$docs=$facts.documents
  $oldConfig=$docs['.ai-workspace/project.json|preimage'];$newConfig=$docs['.ai-workspace/project.json|postimage'];$oldPolicy=$docs['.ai-workspace/process-policy.json|preimage'];$newPolicy=$docs['.ai-workspace/process-policy.json|postimage']
  $forbidden=@($forbidden)+@(Get-PubForbidden $root @($oldConfig.Value.routineExcludedPaths))+@(Get-PubForbidden $root @($newConfig.Value.routineExcludedPaths))
  # Apply config exclusions before any professional object is statted/read.
  foreach($path in $facts.sourcePaths){$null=Assert-PubProfessionalPath $root $path $forbidden}
  if($oldConfig.Identity-cne$plan.projectConfigIdentity){throw 'SOURCE_PUBLICATION_ORIGINAL_CONFIG_DRIFT'}
  $taskPath=Get-PubChild $root $plan.taskPath $forbidden
  if($plan.taskPath-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'-or(Get-PubIdentity $taskPath)-cne$plan.taskIdentity){throw 'SOURCE_PUBLICATION_TASK_DRIFT'}
  if((Get-PubIdentity (Get-PubChild $root '.ai-workspace/controller.json' $forbidden))-cne$plan.controllerIdentity){throw 'SOURCE_PUBLICATION_CONTROLLER_DRIFT'}
  $maintenance=$oldConfig.Value.controlPlaneLayout-ceq'framework-maintenance-sibling'
  if($maintenance){
   $controller=(Read-AiwStrictInputJson (Get-PubChild $root '.ai-workspace/controller.json' $forbidden)).Value
   if($Package.schemaVersion-ne2-or$Package.repositoryId-cne'CONTROL'-or$Package.issuerRole-cne'PROJECT_CONTROLLER'-or$Package.issuer-cne$controller.controllerId-or$Package.issuerControllerId-cne$controller.controllerId-or$Package.issuerControllerEpoch-ne$controller.controllerEpoch-or$Package.controllerControlIdentity-cne$plan.controllerIdentity){throw 'SOURCE_PUBLICATION_MAINTENANCE_CONTROLLER_REQUIRED'}
  }
  $memberPaths=@($plan.objects|Where-Object{$_.ownerMember-ceq$binding.member-and$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object path)
  if((Get-PubCanonical @($Package.exactPaths|Sort-Object -CaseSensitive))-cne(Get-PubCanonical @($memberPaths|Sort-Object -CaseSensitive))-or@($Package.objectIdentities).Count-ne$memberPaths.Count){throw 'SOURCE_PUBLICATION_EXACT_MEMBER_SCOPE'}
  foreach($path in $memberPaths){$entry=@($Package.objectIdentities|Where-Object path -CEQ $path);$original=@($plan.objects|Where-Object path -CEQ $path);if($entry.Count-ne1-or$entry[0].identity-cne$original[0].preimage.identity){throw 'SOURCE_PUBLICATION_MEMBER_PREIMAGE'}}
  $decision=(Read-PubEvidence $plan.decisionRef $root $forbidden -Json).Value
  Assert-PubFields $decision @('schemaVersion','kind','projectRoot','taskId','owner','actor','userDecision','documents','forwardRecovery','inverseRecoveryBeforeCommit') DECISION
  Assert-PubInteger $decision.schemaVersion DECISION_SCHEMA
  if($decision.schemaVersion-ne1-or$decision.kind-cne'PROJECT_SOURCE_PUBLICATION_DECISION'-or(Get-PubRoot $decision.projectRoot)-cne$root-or$decision.taskId-cne$plan.taskId-or$decision.owner-cne$plan.owner-or$decision.actor-cne$plan.actor-or$decision.userDecision-cne$plan.userDecision-or$decision.forwardRecovery-isnot[bool]-or-not$decision.forwardRecovery-or$decision.inverseRecoveryBeforeCommit-isnot[bool]-or-not$decision.inverseRecoveryBeforeCommit){throw 'SOURCE_PUBLICATION_ORIGINAL_DECISION_REQUIRED'}
  Assert-PubArray $decision.documents DECISION_DOCUMENTS -Nonempty
  if((Get-PubCanonical @($decision.documents.path|Sort-Object -CaseSensitive))-cne(Get-PubCanonical @($facts.sourcePaths|Sort-Object -CaseSensitive))){throw 'SOURCE_PUBLICATION_DECISION_DOC_SCOPE'}
  foreach($item in $decision.documents){Assert-PubFields $item @('path','write','recoverBeforeCommit','purpose') DECISION_DOC;if($item.write-isnot[bool]-or-not$item.write-or$item.recoverBeforeCommit-isnot[bool]-or-not$item.recoverBeforeCommit-or$item.purpose-isnot[string]-or[string]::IsNullOrWhiteSpace($item.purpose)){throw 'SOURCE_PUBLICATION_PROFESSIONAL_DECISION_REQUIRED'}}
  Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
  # The old single-action first-KNOWLEDGE-enable exception is deliberately not
  # part of this two-member protocol.
  $oldCaps=$oldConfig.Value.frameworkCapabilities|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $newCaps=$newConfig.Value.frameworkCapabilities|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  foreach($caps in @($oldCaps,$newCaps)){if($null-ne$caps.PSObject.Properties['KNOWLEDGE_REFERENCE']){$caps.KNOWLEDGE_REFERENCE.PSObject.Properties.Remove('sources')}}
  if((Get-PubCanonical $oldCaps)-cne(Get-PubCanonical $newCaps)){throw 'SOURCE_PUBLICATION_CAPABILITY_CHANGE_DENIED'}
  $changes=Get-AiwProjectSourcePermissionChanges $oldConfig.Value $newConfig.Value $Package
  if((Get-PubCanonical $changes)-cne(Get-PubCanonical $plan.permissionChanges)-or(Get-PubCanonical @(Get-PubSelectorChanges $oldPolicy.Value $newPolicy.Value))-cne(Get-PubCanonical $plan.selectorChanges)){throw 'SOURCE_PUBLICATION_DECLARED_CHANGE_DRIFT'}
  # Members and the boundary's private scope can share a complete graph only
  # after current member bytes/paths are observed again. Public requests never
  # accept a caller-supplied fact, and each new boundary starts an empty scope.
  $closureKey=Get-PubCanonical @($root,$planDocument.Identity,@($forbidden))
  if($null-ne$ClosureObservation-and$ClosureObservation.ContainsKey($closureKey)-and(Test-PubClosureObservation $ClosureObservation[$closureKey] $plan $docs $root $forbidden)){
   $oldClosure=$ClosureObservation[$closureKey].old;$targetClosure=$ClosureObservation[$closureKey].target
  }else{
   # A caller's private dictionary is not the current boundary's producer.
   # Reuse still passes through the content owner's full rule/current-byte gate.
   $selectedMaterial=if($null-ne$ClosureObservation-and[object]::ReferenceEquals($ClosureObservation,$script:PublicationClosureObservations)-and$ClosureObservation.ContainsKey('SELECTED_STANDARDS')){$ClosureObservation['SELECTED_STANDARDS']}else{$null}
   $pair=Get-PubClosurePair $plan $docs $root $forbidden $selectedMaterial;$oldClosure=$pair.old;$targetClosure=$pair.target
   if($null-ne$ClosureObservation){$ClosureObservation[$closureKey]=[pscustomobject]@{old=$oldClosure;target=$targetClosure}}
  }
  Assert-PubFields $plan.sourceClosure @('old','target') CLOSURE
  if((Get-PubCanonical $oldClosure)-cne(Get-PubCanonical $plan.sourceClosure.old)-or(Get-PubCanonical $targetClosure)-cne(Get-PubCanonical $plan.sourceClosure.target)){throw 'SOURCE_PUBLICATION_COMPLETE_CLOSURE_DRIFT'}
  foreach($object in @($plan.objects|Where-Object ownerMember -CEQ SOURCE)){
   $physical=Get-PubChild $root $object.path $forbidden
   $old=@($oldClosure.documents|Where-Object{$_.sourcePath.Equals($physical,[StringComparison]::OrdinalIgnoreCase)})
   $target=@($targetClosure.documents|Where-Object{$_.sourcePath.Equals($physical,[StringComparison]::OrdinalIgnoreCase)})
   if(($old.Count-eq0-and$target.Count-eq0)-or($object.preimage.identity-ceq'NEW'-and$target.Count-eq0)){throw 'SOURCE_PUBLICATION_DOC_OUTSIDE_ADOPTION_CLOSURE'}
   foreach($item in $target){if($item.identity-cne$object.postimage.identity){throw 'SOURCE_PUBLICATION_DOC_TARGET_IDENTITY'}}
  }
  $framework=Get-PubRoot $plan.frameworkRoot
  $localFramework=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
  if($framework-cne(Get-PubRoot $localFramework)){throw 'SOURCE_PUBLICATION_FIXED_IMPLEMENTATION_ROOT'}
  if((Get-PubCanonical @(Get-AiwSourceChangeRootTools $framework))-cne(Get-PubCanonical $plan.rootToolDependencies)){throw 'SOURCE_PUBLICATION_TOOL_DRIFT'}
  Assert-PubArray $plan.assuranceEvidence ASSURANCE
  $evidenceModule=@(Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1') -PassThru)[0]
  $consumption=& $evidenceModule {param($p) Get-EvConsumption $p assuranceConsumption} $plan
  $evidenceContext=New-AiwEvidenceContext $root $root $framework $forbidden
  # R remains the complete objects/closure binding. A is independently frozen,
  # contains every actual write M, and defaults to all of R for old plans.
  $reviewObjects=@($plan.objects)
  if($null-ne$plan.PSObject.Properties['reviewScope']){
   Assert-PubArray $plan.reviewScope REVIEW_SCOPE -Nonempty
   $seenReview=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
   $reviewObjects=@(foreach($entry in $plan.reviewScope){
    Assert-PubFields $entry @('path','identity') REVIEW_OBJECT
    $null=Get-PubChild $root $entry.path $forbidden
    $object=@($plan.objects|Where-Object path -CEQ $entry.path)
    if(-not$seenReview.Add($entry.path)-or$object.Count-ne1-or$entry.identity-cne$object[0].postimage.identity){throw 'SOURCE_PUBLICATION_REVIEW_SCOPE_DRIFT'}
    $object[0]
   })
   if(@($plan.writeOrder|Where-Object{$_-cnotin@($reviewObjects.path)}).Count){throw 'SOURCE_PUBLICATION_REVIEW_WRITE_COVERAGE'}
  }
  $frozenCandidates=@($reviewObjects|ForEach-Object{[pscustomobject]@{path=[IO.Path]::GetRelativePath($root,$_.postimage.path).Replace('\','/');identity=$_.postimage.identity}})
  foreach($ref in $plan.assuranceEvidence){
   Assert-PubFields $ref @('kind','path','identity') ASSURANCE_REF
   $refPath=if([IO.Path]::IsPathFullyQualified($ref.path)){$ref.path}else{Join-Path $root $ref.path}
   $record=(Read-PubEvidence ([pscustomobject]@{path=$refPath;identity=$ref.identity}) $root $forbidden -Json).Value
   $null=Read-AiwResultEvidence $evidenceContext $ref $plan.taskId $frozenCandidates $record.requirementsRef -RequireSuccess -RequireIndependentReview:($ref.kind-ceq'REVIEW_VERDICT') -ExcludedReviewActors @($plan.owner,$plan.actor,$Package.issuer) -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize
  }
  if($Package.profile-ceq'CRITICAL'-and(@($plan.assuranceEvidence|Where-Object kind -CEQ REVIEW_VERDICT).Count-ne1-or@($plan.assuranceEvidence|Where-Object kind -CEQ RESULT_ACCEPTANCE).Count-ne1)){throw 'SOURCE_PUBLICATION_CRITICAL_ASSURANCE_REQUIRED'}
  $reachable=Get-AiwProjectSourcePublicationReachability $root $plan $forbidden
  $recovery=Get-AiwProjectSourcePublicationContext $root
  # Pure eligibility checks the complete candidate and reachable images.
  # ADMIT itself still requires allOld; FINALIZE separately proves both original admissions.
  if($null-ne$recovery-and$recovery.planRef.identity-cne$binding.planRef.identity){throw 'SOURCE_PUBLICATION_RECOVERY_PLAN_DRIFT'}
  return [pscustomobject]@{executionBoundary='PROJECT_SOURCE_PUBLICATION';plan=$plan;planRef=$binding.planRef;documents=$docs;sourcePaths=$facts.sourcePaths;controlPaths=$facts.controlPaths;forbidden=$forbidden;reachable=$reachable;member=$binding.member;root=$root}
 }finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
}
function Get-AiwProjectSourcePublicationMembers {
 [CmdletBinding()]param([Parameter(Mandatory)]$ControlReceiptRef,[Parameter(Mandatory)]$SourceReceiptRef,[Parameter(Mandatory)]$PlanRef)
 # The plan is caller-owned runtime material. Derive its lexical project root
 # before opening either compact or observing any authority/source objects.
 if($PlanRef.path-isnot[string]-or-not[IO.Path]::IsPathFullyQualified($PlanRef.path)){throw 'SOURCE_PUBLICATION_EVIDENCE_SCOPE'}
 $planPath=[IO.Path]::GetFullPath($PlanRef.path)
 $marker=[IO.Path]::DirectorySeparatorChar+'.ai-workspace'+[IO.Path]::DirectorySeparatorChar+'runtime'+[IO.Path]::DirectorySeparatorChar
 $position=$planPath.IndexOf($marker,[StringComparison]::OrdinalIgnoreCase)
 if($position-lt1){throw 'SOURCE_PUBLICATION_EVIDENCE_SCOPE'}
 $root=$planPath.Substring(0,$position)
 $root=Get-PubRoot $root
 $aiwPublicationScopeLease=Enter-AiwProjectSourceScope $root
 try{
  $control=Read-PubEvidence $ControlReceiptRef $root -Json
  $b=if($null-ne$control.Value.PSObject.Properties['binding']){$control.Value.binding}else{$control.Value.authorityContext}
  $forbidden=Get-PubForbidden $root @(@($b.forbiddenScope)+@($b.protectedScope))
  $source=Read-PubEvidence $SourceReceiptRef $root $forbidden -Json
  $receipts=[ordered]@{SOURCE=$source;CONTROL=$control};$eligibilities=@{};$closureObservation=if($null-ne$script:PublicationClosureObservations){$script:PublicationClosureObservations}else{@{}}
  foreach($member in @('SOURCE','CONTROL')){
   $doc=$receipts[$member];$r=$doc.Value
   if($r.schemaVersion-notin@(3,4)-or$r.mode-cne'DISCOVER'-or$r.status-cne'PASS'-or$r.intentEnvelope.requestedActionKind-cne$(if($member-ceq'SOURCE'){'SOURCE_WRITE'}else{'CONTROL_WRITE'})){throw 'SOURCE_PUBLICATION_ORIGINAL_DISCOVER_REQUIRED'}
   $b=$r.binding
   if($b.contextType-cne'TASK'-or(Get-PubRoot $b.projectRoot)-cne$root){throw 'SOURCE_PUBLICATION_MEMBER_PROJECT'}
   $forbidden=Get-PubForbidden $root @(@($b.forbiddenScope)+@($b.protectedScope))
   $p=Read-PubEvidence ([pscustomobject]@{path=$r.sourceLocators.authorizationPackagePath;identity=$b.authorizationIdentity}) $root $forbidden -Json
   if((Get-PubCanonical $p.Value.sourcePublicationBinding.planRef)-cne(Get-PubCanonical $PlanRef)-or$p.Value.sourcePublicationBinding.member-cne$member){throw 'SOURCE_PUBLICATION_MEMBER_PLAN'}
   $e=Get-PubEligibilityCore $root $p.Value $forbidden $closureObservation
   if($b.actor-cne$e.plan.actor-or$b.taskOwner-cne$e.plan.owner-or$b.taskId-cne$e.plan.taskId-or$b.taskIdentity-cne$e.plan.taskIdentity-or$b.userDecision-cne$e.plan.userDecision-or$r.sourceLocators.frameworkRoot-cne$e.plan.frameworkRoot-or$r.sourceBindings.projectConfigIdentity-cne$e.plan.projectConfigIdentity-or$r.sourceBindings.policyIdentity-cne$e.documents['.ai-workspace/process-policy.json|preimage'].Identity-or(Get-PubCanonical @($b.exactScope))-cne(Get-PubCanonical @($p.Value.exactPaths))){throw 'SOURCE_PUBLICATION_ORIGINAL_MEMBER_BINDING'}
   $eligibilities[$member]=[pscustomobject]@{receipt=$r;receiptRef=$(if($member-ceq'SOURCE'){$SourceReceiptRef}else{$ControlReceiptRef});package=$p.Value;authorizationRef=[pscustomobject]@{path=$p.Path;identity=$p.Identity};eligibility=$e}
  }
  if((Get-PubCanonical $source.Value.sourceBindings)-cne(Get-PubCanonical $control.Value.sourceBindings)){throw 'SOURCE_PUBLICATION_ORIGINAL_SNAPSHOT_MISMATCH'}
  return [pscustomobject]@{SOURCE=$eligibilities.SOURCE;CONTROL=$eligibilities.CONTROL;plan=$eligibilities.CONTROL.eligibility.plan;planRef=$PlanRef;root=$root}
 }finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
}
function Get-PubRecoveryOriginalFacts([string]$ProjectRoot,$Recovery){
 $root=Get-PubRoot $ProjectRoot
 Assert-PubFields $Recovery @('schemaVersion','kind','projectRoot','planRef','candidateRef','members') RECOVERY
 Assert-PubInteger $Recovery.schemaVersion RECOVERY_SCHEMA
 if($Recovery.schemaVersion-ne3-or$Recovery.kind-cne'PROJECT_SOURCE_PUBLICATION_RECOVERY'-or(Get-PubRoot $Recovery.projectRoot)-cne$root){throw 'SOURCE_PUBLICATION_RECOVERY_ROOT'}
 Assert-PubArray $Recovery.members RECOVERY_MEMBERS -Nonempty
 if($Recovery.members.Count-ne2-or[string]::Join('|',@($Recovery.members.member))-cne'SOURCE|CONTROL'){throw 'SOURCE_PUBLICATION_RECOVERY_TWO_ADMISSIONS'}
 $candidate=(Read-PubEvidence $Recovery.candidateRef $root -Json).Value
 if($candidate.schemaVersion-ne2-or$candidate.kind-cne'PROJECT_SOURCE_PUBLICATION'-or(Get-PubCanonical $candidate.planRef)-cne(Get-PubCanonical $Recovery.planRef)){throw 'SOURCE_PUBLICATION_RECOVERY_CANDIDATE'}
 $plan=(Read-PubEvidence $Recovery.planRef $root -Json).Value
 $admissions=@{};$receipts=@{};$allForbidden=@()
 Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
 Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
 foreach($member in $Recovery.members){
  Assert-PubFields $member @('member','discoverReceiptRef','admitInputRef','admitResultRef','finalizeInputRef') RECOVERY_MEMBER
  $r=(Read-PubEvidence $member.discoverReceiptRef $root -Json).Value
  $b=if($null-ne$r.PSObject.Properties['binding']){$r.binding}else{$r.authorityContext}
  $forbidden=Get-PubForbidden $root @(@($b.forbiddenScope)+@($b.protectedScope))
  $allForbidden+=@($forbidden)
  $a=(Read-PubEvidence $member.admitInputRef $root $forbidden -Json).Value
  $result=(Read-PubEvidence $member.admitResultRef $root $forbidden -Json).Value
  $final=(Read-PubEvidence $member.finalizeInputRef $root $forbidden -Json).Value
  if($r.schemaVersion-notin@(3,4)-or$r.mode-cne'DISCOVER'-or$r.status-cne'PASS'-or$r.intentEnvelope.requestedActionKind-cne$(if($member.member-ceq'SOURCE'){'SOURCE_WRITE'}else{'CONTROL_WRITE'})-or(Get-PubRoot $b.projectRoot)-cne$root-or$a.schemaVersion-ne3-or$a.mode-cne'ADMIT_ACTION'-or$result.mode-cne'ADMIT_ACTION'-or$result.status-cne'PASS'-or$result.selectionIdentity-cne$r.selectionIdentity-or@($result.missingPreparation).Count-or@($result.missingResult).Count-or$result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $r $a)){throw 'SOURCE_PUBLICATION_ORIGINAL_ADMISSION_REQUIRED'}
  foreach($input in @($a,$final)){
   if($input.expectedDiscoverReceiptIdentity-cne$member.discoverReceiptRef.identity-or[IO.Path]::GetFullPath($input.discoverReceiptPath)-cne[IO.Path]::GetFullPath($member.discoverReceiptRef.path)-or$input.publicDecisionIdentity-cne$a.publicDecisionIdentity-or$input.protectionState-cne$a.protectionState){throw 'SOURCE_PUBLICATION_ORIGINAL_DECISION_OR_PROTECTION'}
   $tokens=@($input.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_CHANGE|*'})
   if($tokens.Count-ne1-or$tokens[0]-cne('PROJECT_SOURCE_CHANGE|'+$Recovery.candidateRef.path+'|'+$Recovery.candidateRef.identity)){throw 'SOURCE_PUBLICATION_ORIGINAL_COMMON_PREPARATION'}
  }
  if($final.schemaVersion-ne3-or$final.mode-cne'FINALIZE_OUTPUT'){throw 'SOURCE_PUBLICATION_ORIGINAL_FINALIZATION_INPUT'}
  $target=@($candidate.targets|Where-Object member -CEQ $member.member)
  $frozenMember=@($candidate.members|Where-Object member -CEQ $member.member)
  if($target.Count-ne1-or$frozenMember.Count-ne1-or(Get-PubCanonical $frozenMember[0].discoverReceiptRef)-cne(Get-PubCanonical $member.discoverReceiptRef)-or$result.projectSourcePreparation.outcome-cne'PREPARED'-or$result.projectSourcePreparation.candidateIdentity-cne$Recovery.candidateRef.identity-or$result.projectSourcePreparation.targetIdentity-cne(Get-AiwContentDescriptorIdentity $target[0].binding)){throw 'SOURCE_PUBLICATION_ORIGINAL_ADMISSION_TARGET'}
  if($b.taskIdentity-cne$plan.taskIdentity-or$b.taskOwner-cne$plan.owner-or$b.actor-cne$plan.actor-or$b.taskId-cne$plan.taskId-or$b.userDecision-cne$plan.userDecision){throw 'SOURCE_PUBLICATION_RECOVERY_AUTHORITY_DRIFT'}
  $receipts[$member.member]=$r;$admissions[$member.member]=[pscustomobject]@{input=$a;result=$result;finalize=$final;refs=$member}
 }
 # A recovery handle is activated only after two real, original decision
 # identities and the exact whole group are verified. This provisional value
 # exists solely inside this validator's call stack and is erased on failure.
 $forbidden=@($allForbidden|Select-Object -Unique)
 $configObject=@($plan.objects|Where-Object path -CEQ '.ai-workspace/project.json')
 if($configObject.Count-ne1-or$configObject[0].ownerMember-cne'CONTROL'){throw 'SOURCE_PUBLICATION_CONFIG_OBJECT_REQUIRED'}
 foreach($side in @('preimage','postimage')){
  $config=(Read-PubEvidence $configObject[0].$side $root $forbidden -Json).Value
  $forbidden=@($forbidden)+@(Get-PubForbidden $root @($config.routineExcludedPaths))
 }
 $objects=Get-PubObjectDocuments $plan $root $forbidden
 $reachable=Get-PubReachability $root $plan $forbidden
 if((Get-PubIdentity (Get-PubChild $root $plan.taskPath $forbidden))-cne$plan.taskIdentity-or(Get-PubIdentity (Get-PubChild $root '.ai-workspace/controller.json' $forbidden))-cne$plan.controllerIdentity){throw 'SOURCE_PUBLICATION_RECOVERY_AUTHORITY_DRIFT'}
 $proof=[pscustomobject]@{planRef=$Recovery.planRef;candidateRef=$Recovery.candidateRef;recovery=$Recovery;admissions=$admissions;reachable=$reachable}
 return [pscustomobject]@{proof=$proof;plan=$plan;admissions=$admissions;receipts=$receipts}
}
function Test-PubOriginalFinalization([string]$Root,$Original,[string]$Member,[string]$InputPath,[string]$OutputPath,[string]$Direction){
 $input=(Read-PubEvidence ([pscustomobject]@{path=$InputPath;identity=(Get-PubIdentity $InputPath)}) $Root -Json).Value
 $result=(Read-PubEvidence ([pscustomobject]@{path=$OutputPath;identity=(Get-PubIdentity $OutputPath)}) $Root -Json).Value
 $r=$Original.receipts[$Member];$a=$Original.admissions[$Member];$expected=if($Direction-ceq'COMPLETE'){'COMPLETED'}else{'ROLLED_BACK'}
 $base=$a.finalize|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $tokens=@($input.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_PUBLICATION_ADMISSIONS|*'})
 if($tokens.Count-ne1-or$tokens[0]-cnotmatch'^PROJECT_SOURCE_PUBLICATION_ADMISSIONS\|([^|]+)\|(\d+\|[A-F0-9]{64})$'){throw 'SOURCE_PUBLICATION_SAVED_PAIR_REQUIRED'}
 $pair=(Read-PubEvidence ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) $Root -Json).Value
 if((Get-PubCanonical $pair)-cne(Get-PubCanonical $Original.proof.recovery)){throw 'SOURCE_PUBLICATION_SAVED_PAIR_DRIFT'}
 $base.preparationReceipts=@($base.preparationReceipts)+@($tokens[0])
 if($Direction-ceq'ROLLBACK'){
  $base.preparationReceipts=@($base.preparationReceipts|Where-Object{$_-cne'PROJECT_SOURCE_ROLLBACK'})+@('PROJECT_SOURCE_ROLLBACK')
  $base.resultReceipts=@($base.resultReceipts|Where-Object{$_-cnotlike'OBJECT_POSTIMAGE|*'})+@($Original.plan.objects|Where-Object{$_.ownerMember-ceq$Member-and$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.preimage.identity-ceq'NEW'){'MISSING'}else{$_.preimage.identity})})
  $base.evidenceRefs=@()
 }
 if((Get-PubCanonical $input)-cne(Get-PubCanonical $base)){throw 'SOURCE_PUBLICATION_SAVED_FINAL_INPUT_DRIFT'}
 $post='NO_SOURCE_POSTIMAGE_TRANSITION';$changed=@()
 if($null-ne$result.PSObject.Properties['sourcePostimageTransition']){$post=$result.sourcePostimageTransition.currentSourceCompositionIdentity;$changed=@($result.sourcePostimageTransition.changedBindings)}
 if($result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or$result.actionOutcome-cne'OBSERVED'-or$result.selectionIdentity-cne$r.selectionIdentity-or$result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $r $input $post $changed)-or$result.projectSourcePreparation.candidateIdentity-cne$Original.proof.candidateRef.identity-or$result.projectSourcePreparation.outcome-cne$expected){throw 'SOURCE_PUBLICATION_SAVED_FINAL_RESULT_DRIFT'}
 return $true
}

function Get-PubBoundaryPairFacts([string]$ControlInputPath,$SourceInputRef){
 $root=Get-AiwPublicationInputProjectRoot $ControlInputPath
 $controlPath=[IO.Path]::GetFullPath($ControlInputPath)
 $controlRef=[pscustomobject]@{path=$controlPath;identity=(Get-PubIdentity $controlPath)}
 $control=(Read-PubEvidence $controlRef $root -Json).Value
 if($control.schemaVersion-ne3-or$control.mode-cnotin@('ADMIT_ACTION','FINALIZE_OUTPUT')){throw 'SOURCE_PUBLICATION_PAIR_BOUNDARY_REQUIRED'}
 $controlReceiptRef=[pscustomobject]@{path=$control.discoverReceiptPath;identity=$control.expectedDiscoverReceiptIdentity}
 $receipt=(Read-PubEvidence $controlReceiptRef $root -Json).Value
 if($receipt.schemaVersion-notin@(3,4)-or$receipt.intentEnvelope.requestedActionKind-cne'CONTROL_WRITE'){throw 'SOURCE_PUBLICATION_PAIR_CONTROL_REQUIRED'}
 $forbidden=Get-PubForbidden $root @(@($receipt.binding.forbiddenScope)+@($receipt.binding.protectedScope))
 $source=(Read-PubEvidence $SourceInputRef $root $forbidden -Json).Value
 if($source.schemaVersion-ne3-or$source.mode-cne$control.mode){throw 'SOURCE_PUBLICATION_PAIR_STAGE_MISMATCH'}
 $sourceReceiptRef=[pscustomobject]@{path=$source.discoverReceiptPath;identity=$source.expectedDiscoverReceiptIdentity}
 $package=(Read-PubEvidence ([pscustomobject]@{path=$receipt.sourceLocators.authorizationPackagePath;identity=$receipt.binding.authorizationIdentity}) $root $forbidden -Json).Value
 if($null-eq$package.PSObject.Properties['sourcePublicationBinding']){throw 'SOURCE_PUBLICATION_PAIR_ONLY'}
 $tokens=@($control.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_CHANGE|*'})
 $sourceTokens=@($source.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_CHANGE|*'})
 if($tokens.Count-ne1-or$sourceTokens.Count-ne1-or$tokens[0]-cne$sourceTokens[0]){throw 'SOURCE_PUBLICATION_PAIR_CANDIDATE_MISMATCH'}
 if(('PROJECT_SOURCE_ROLLBACK'-cin@($source.preparationReceipts))-ne('PROJECT_SOURCE_ROLLBACK'-cin@($control.preparationReceipts))){throw 'SOURCE_PUBLICATION_PAIR_DIRECTION_MISMATCH'}
 $facts=Get-AiwProjectSourcePublicationMembers $controlReceiptRef $sourceReceiptRef $package.sourcePublicationBinding.planRef
 return [pscustomobject]@{root=$root;mode=$control.mode;inputs=@{SOURCE=$SourceInputRef;CONTROL=$controlRef};facts=$facts;targets=$null;member=$null;inputRef=$null}
}

function Get-AiwProjectSourcePublicationRecoveryProof {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Recovery)
 $root=Get-PubRoot $ProjectRoot
 $scope=Get-PubStackScope $root;if($null-eq$scope){throw 'SOURCE_PUBLICATION_RECOVERY_SCOPE_REQUIRED'}
 $lease=Get-PubLeaseFacts $scope
 if(-not$lease.Owned){$lease=Get-PubLeaseFacts $lease.Origin}
 if($lease.Mode-cne'PUBLICATION'-or-not$lease.Owned){throw 'SOURCE_PUBLICATION_RECOVERY_SCOPE_REQUIRED'}
 $original=Get-PubRecoveryOriginalFacts $root $Recovery
 $proof=$original.proof;$admissions=$original.admissions;$receipts=$original.receipts
 $previous=$lease.Recovery;$lease.Recovery=$proof
 try{
  $facts=Get-AiwProjectSourcePublicationMembers $Recovery.members[1].discoverReceiptRef $Recovery.members[0].discoverReceiptRef $Recovery.planRef
  # One candidate validation already rechecks BOTH complete compiler targets,
  # both original admissions and their static bindings. Repeating it for the
  # second member would compile the same two targets again under the same guard.
  $boundary=$admissions.SOURCE.input
  # These complete members were observed above in this actual owned write
  # scope. Keep candidate/target/current reachability validation, while using
  # the existing private compiler input instead of rebuilding those members.
  $composer=@(Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru)[0]
  $targetsCapture=[ref]$null
  $null=& $composer {
   param($receipt,$boundary,$reference,$facts,$targetsCapture)
   Get-AiwPublicationCandidateCore $receipt $boundary $reference RECOVERY -VerifiedFacts $facts -TargetsCapture $targetsCapture
  } $receipts.SOURCE $boundary $Recovery.candidateRef $facts $targetsCapture
  $proof|Add-Member -NotePropertyName facts -NotePropertyValue $facts
  $proof|Add-Member -NotePropertyName targets -NotePropertyValue $targetsCapture.Value
  return $proof
 }catch{$lease.Recovery=$previous;throw}
}

# A foreign original owner is eligible only inside this module-owned adoption
# body. Its actual CWT entry, active invocation and native owner remain O's.
function Get-PubAdoptionOriginFacts($Scope){
 foreach($frame in Get-PSCallStack){
  $module=$frame.InvocationInfo.MyCommand.Module
  if($module-isnot[Management.Automation.PSModuleInfo]-or$module.Definition-cne$script:PublicationModule.Definition){continue}
  $facts=& $module {
   param($origin,$invocation)
   foreach($entry in $script:PublicationLeases){
    $f=$entry.Value
    if($null-eq$f.PSObject.Properties['AdoptionBridgeActive']-or-not$f.AdoptionBridgeActive-or-not[object]::ReferenceEquals($origin,$f.Origin)-or-not[object]::ReferenceEquals($invocation,$f.Invocation)){continue}
    if($f.Runspace-cne[Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId-or(Get-PubIdentity $script:PublicationModule.Path)-cne$script:PublicationImplementationIdentity-or(Get-PubIdentity $f.AdoptionOwner.Path)-cne$f.AdoptionImplementationIdentity){throw 'SOURCE_PUBLICATION_ADOPTION_IMPLEMENTATION_DRIFT'}
    $owner=$f.AdoptionOwner
    if($owner.Definition-cne$f.AdoptionDefinition){throw 'SOURCE_PUBLICATION_ADOPTION_IMPLEMENTATION_DRIFT'}
    $of=& $owner {
     param($scope,$implementation)
     if($script:PublicationImplementationIdentity-cne$implementation){return $null}
     $registered=$null
     if($script:PublicationLeases.TryGetValue($scope,[ref]$registered)){
      $null=Get-PubLeaseFacts $scope
      return $registered
     }
    } $origin $f.AdoptionImplementationIdentity
    if($null-eq$of-or-not$of.Owned-or-not$of.StructuredBodyActive-or-not[object]::ReferenceEquals($of.Origin,$origin)-or-not[object]::ReferenceEquals($origin.OwnerModule,$owner)-or-not[object]::ReferenceEquals($of.Handle,$f.Handle)-or$of.Root-cne$f.Root-or$of.Mode-cne$f.Mode-or$of.Runspace-cne$f.Runspace-or$null-ne$of.Recovery-or$of.Mode-cnotin@('OBSERVE','WRITE')){throw 'SOURCE_PUBLICATION_ADOPTION_OWNER_INVALID'}
    $active=@(Get-PSCallStack|Where-Object{[object]::ReferenceEquals($_.InvocationInfo,$of.Invocation)-and[object]::ReferenceEquals($_.InvocationInfo.MyCommand.Module,$owner)})
    if($active.Count-ne1){throw 'SOURCE_PUBLICATION_ADOPTION_OWNER_INVALID'}
    return $of
   }
   return $null
  } $Scope $frame.InvocationInfo
  if($null-ne$facts){return $facts}
 }
 return $null
}
function Invoke-PubOriginalAdoptionBody($Proof,$Owner,[string]$Mode,[scriptblock]$Body,[object[]]$ArgumentList){
 $origin=& $Owner {param($r) Get-PubStackScope $r} $Proof.root
 $of=& $Owner {param($s) Get-PubLeaseFacts $s} $origin
 if($null-eq$origin-or-not$of.Owned-or-not$of.StructuredBodyActive-or$of.Mode-cne$Mode-or$of.Root-cne$Proof.root-or$null-ne$of.Recovery){throw 'SOURCE_PUBLICATION_ADOPTION_OWNER_INVALID'}
 $lease=[pscustomobject]@{Root=$of.Root;Mode=$of.Mode;Handle=$of.Handle;OwnerModule=$script:PublicationModule}
 $facts=[pscustomobject]@{Root=$of.Root;Mode=$of.Mode;Handle=$of.Handle;Invocation=$MyInvocation;Owned=$false;Runspace=$of.Runspace;Recovery=$null;Origin=$origin;StructuredBodyActive=$true;AdoptionBridgeActive=$true;AdoptionOwner=$Owner;AdoptionImplementationIdentity=$Proof.moduleIdentity;AdoptionDefinition=$Owner.Definition}
 $script:PublicationLeases.Add($lease,$facts)
 try{
  $null=Get-PubLeaseFacts $lease
  # Both implementations inspect the journal; adoption never supplies the
  # separate two-admission publication recovery context.
  Assert-PubJournalObservation $facts
  foreach($r in $Proof.reads){Assert-PubPath $r.path;if((Get-PubIdentity $r.path)-cne$r.identity){throw 'ADOPTION_SCOPE_ORIGIN_DRIFT'}}
  $statePath=Join-Path $PSScriptRoot '../../../../scripts/ProjectAdoptionState.psm1'
  $state=@(Import-Module $statePath -PassThru -ErrorAction Stop)[0]
  $null=& $state.ExportedCommands['Assert-AiwDistributionBinding'] $Proof.distribution $Proof.distribution.runtimeRoot $Proof.version
  & $Body @ArgumentList
 }finally{
  $facts.AdoptionBridgeActive=$false;$facts.StructuredBodyActive=$false
  $script:PublicationLeases.Remove($lease)|Out-Null
 }
}
function Invoke-PubOriginalAdoptionScope($Proof,[ValidateSet('OBSERVE','WRITE')][string]$Mode,[scriptblock]$Body,[object[]]$ArgumentList){
 $statePath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../scripts/ProjectAdoptionState.psm1'))
 $frames=@(Get-PSCallStack|Where-Object{$_.FunctionName-ceq'Invoke-AiwRootAdoptionSourceScope'-and$_.InvocationInfo.MyCommand.Module-is[Management.Automation.PSModuleInfo]-and[IO.Path]::GetFullPath($_.InvocationInfo.MyCommand.Module.Path)-ceq$statePath})
 if($frames.Count-ne1-or$frames[0].InvocationInfo.MyCommand.Module.Definition-cne[IO.File]::ReadAllText($statePath)){throw 'SOURCE_PUBLICATION_ADOPTION_ROOT_REQUIRED'}
 $root=Get-PubRoot $Proof.root
 if($root-cne$Proof.root-or$Proof.version-cne'2.0.0'-or(Get-PubIdentity $Proof.modulePath)-cne$Proof.moduleIdentity){throw 'SOURCE_PUBLICATION_ADOPTION_ORIGIN_INVALID'}
 $owner=@(Import-Module $Proof.modulePath -PassThru -ErrorAction Stop)[0]
 if([IO.Path]::GetFullPath($owner.Path)-cne[IO.Path]::GetFullPath($Proof.modulePath)-or-not$owner.ExportedCommands.ContainsKey('Invoke-AiwProjectSourceScope')-or$owner.Definition-cne[IO.File]::ReadAllText($owner.Path)){throw 'SOURCE_PUBLICATION_ADOPTION_ORIGIN_INVALID'}
 # A new ordinary read does not borrow an original runtime read lease.
 if($Mode-ceq'OBSERVE'){return & $Body @ArgumentList}
 # The unchanged same-implementation route needs no compatibility bridge.
 if($owner.Definition-ceq$script:PublicationModule.Definition){return Invoke-AiwProjectSourceScope -ProjectRoot $root -Mode $Mode -Body $Body -ArgumentList $ArgumentList}
 & $owner.ExportedCommands['Invoke-AiwProjectSourceScope'] -ProjectRoot $root -Mode $Mode -Body {
  param($proof,$owner,$mode,$body,$arguments)
  Invoke-PubOriginalAdoptionBody $proof $owner $mode $body $arguments
 } -ArgumentList @($Proof,$owner,$Mode,$Body,$ArgumentList)
}

function Find-PubLeaseFacts($Scope){
 if($null-eq$Scope){return $null}
 $facts=$null
 if($script:PublicationLeases.TryGetValue($Scope,[ref]$facts)){return $facts}
 if($null-eq$Scope.PSObject.Properties['OwnerModule']){return $null}
 $owner=$Scope.OwnerModule
 # Compatible root tools and the receipt-bound original runtime may be two
 # loaded copies. Ask the identical loaded implementation's private registry
 # for this exact live object; a locator, fake scope or global handle is not
 # a lease. The borrower still has to find the owning invocation on its stack.
 if($owner-isnot[Management.Automation.PSModuleInfo]-or[object]::ReferenceEquals($owner,$script:PublicationModule)-or$owner.ModuleType-cne[Management.Automation.ModuleType]::Script-or[string]::IsNullOrEmpty($owner.Definition)-or$owner.Definition-cne$script:PublicationModule.Definition){return Get-PubAdoptionOriginFacts $Scope}
 return & $owner {
  param($scope,$implementationIdentity)
  if($script:PublicationImplementationIdentity-cne$implementationIdentity){return $null}
  $registered=$null
  if($script:PublicationLeases.TryGetValue($scope,[ref]$registered)){return $registered}
  return $null
 } $Scope $script:PublicationImplementationIdentity
}
function Get-PubLeaseFacts($Scope){
 $facts=Find-PubLeaseFacts $Scope
 if($null-eq$facts-or$facts.Runspace-cne[Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId-or-not[object]::ReferenceEquals($Scope.Handle,$facts.Handle)-or$facts.Handle.SafeFileHandle.IsClosed-or$facts.Handle.SafeFileHandle.IsInvalid){throw 'SOURCE_PUBLICATION_SCOPE_INVALID'}
 if(-not$facts.Owned){$origin=Get-PubLeaseFacts $facts.Origin;if(-not$origin.Owned){throw 'SOURCE_PUBLICATION_SCOPE_INVALID'};$facts.Recovery=$origin.Recovery}
 return $facts
}
function Get-PubStackScope([string]$Root){
 foreach($frame in Get-PSCallStack){
  $variables=$frame.GetFrameVariables()
  if($variables.ContainsKey('aiwPublicationScopeLease')){
   $scope=$variables['aiwPublicationScopeLease'].Value
   if($null-ne$scope){
    $facts=Find-PubLeaseFacts $scope
    if($null-ne$facts-and$facts.Root.Equals($Root,[StringComparison]::OrdinalIgnoreCase)-and[object]::ReferenceEquals($frame.InvocationInfo,$facts.Invocation)){
     $null=Get-PubLeaseFacts $scope
     return $scope
    }
   }
  }
  # A structured body can lend only from its registered, currently executing
  # module-owned invocation. No ordinary Enter record is made eligible here.
  $owner=$frame.InvocationInfo.MyCommand.Module
  if($owner-isnot[Management.Automation.PSModuleInfo]-or$owner.ModuleType-cne[Management.Automation.ModuleType]::Script-or[string]::IsNullOrEmpty($owner.Definition)-or$owner.Definition-cne$script:PublicationModule.Definition){continue}
  $managed=& $owner {
   param($invocation,$root,$implementationIdentity)
   if($script:PublicationImplementationIdentity-cne$implementationIdentity){return $null}
   foreach($entry in $script:PublicationLeases){
    $f=$entry.Value
    if($null-ne$f.PSObject.Properties['StructuredBodyActive']-and$f.StructuredBodyActive-eq$true-and$f.Root.Equals($root,[StringComparison]::OrdinalIgnoreCase)-and[object]::ReferenceEquals($f.Invocation,$invocation)){
     $null=Get-PubLeaseFacts $entry.Key
     return $entry.Key
    }
   }
   return $null
  } $frame.InvocationInfo $Root $script:PublicationImplementationIdentity
  if($null-ne$managed){return $managed}
 }
 return $null
}
function Invoke-AiwProjectSourceScope {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[ValidateSet('OBSERVE','WRITE','PUBLICATION')][string]$Mode='OBSERVE',[Parameter(Mandatory)][scriptblock]$Body,[object[]]$ArgumentList=@())
 if($Mode-ceq'OBSERVE'){return & $Body @ArgumentList}
 $managedFacts=$null;$sourceScopePrimaryError=$null
 $managedLease=Enter-AiwProjectSourceScope -ProjectRoot $ProjectRoot -Mode $Mode
 try{
  $managedFacts=Get-PubLeaseFacts $managedLease
  $managedFacts|Add-Member -NotePropertyName StructuredBodyActive -NotePropertyValue $true
  & $Body @ArgumentList
 }catch{
  $sourceScopePrimaryError=$_
  throw
 }finally{
  # Clear eligibility before disposing; faults still close the same native lease.
  if($null-ne$managedFacts){$managedFacts.StructuredBodyActive=$false}
  try{Exit-AiwProjectSourceScope $managedLease}catch{
   if($null-eq$sourceScopePrimaryError){throw}
   $sourceScopePrimaryError.Exception.Data['sourceScopeCleanupError']=$_
  }
 }
}
Export-ModuleMember -Function Invoke-AiwProjectSourceScope


function Assert-PubJournalObservation($Facts){
 # Only this module's actual owned origin can retain a successful explanation.
 # Foreign/compatibility scopes safely repeat the complete validation.
 $memoFacts=$null
 if($null-ne$Facts.PSObject.Properties['Origin']){
  $owned=$null
  if($script:PublicationLeases.TryGetValue($Facts.Origin,[ref]$owned)-and$owned.Owned){$memoFacts=$owned}
 }
 Assert-PubJournalCurrent $Facts.Root $Facts.Recovery $memoFacts
}
function Assert-PubJournalCurrent([string]$Root,$Recovery,$memoFacts){
 try{
 $journal=Get-PubChild $Root '.ai-workspace/upgrade-recovery/project-rules/source-publication/state.json'
 if(-not[IO.File]::Exists($journal)){
  if($null-ne$memoFacts){$memoFacts|Add-Member -NotePropertyName CompletedJournal -NotePropertyValue $null -Force}
  return
 }
 $journalBytes=[IO.File]::ReadAllBytes($journal)
 $journalIdentity=Get-PubByteIdentity $journalBytes
 if($null-ne$memoFacts-and$null-ne$memoFacts.PSObject.Properties['CompletedJournal']-and$null-ne$memoFacts.CompletedJournal){
  $memo=$memoFacts.CompletedJournal
  if($memo.journalIdentity-ceq$journalIdentity-and$memo.implementationIdentity-ceq$script:PublicationImplementationIdentity){
   # The protocol does not exclude editors or bare writes. Every borrowed
   # observation rechecks all original reference paths and current bytes.
   foreach($ref in $memo.references){$null=Read-PubEvidence $ref $Root}
   return
  }
  $memoFacts.CompletedJournal=$null
 }
 $state=(ConvertFrom-AiwStrictInputJson ($script:PublicationUtf8.GetString($journalBytes))).Value
 Assert-PubFields $state @('schemaVersion','kind','projectRoot','recoveryRef','planRef','candidateRef','members','objects','writeOrder','completedWrites','state','completionProof','previousJournalRef') JOURNAL
 Assert-PubInteger $state.schemaVersion JOURNAL_SCHEMA
 if($state.schemaVersion-ne1-or$state.kind-cne'PROJECT_SOURCE_PUBLICATION_JOURNAL'-or(Get-PubRoot $state.projectRoot)-cne$Root-or$state.state-cnotin@('APPLYING','ROLLING_BACK','COMPLETE','ROLLED_BACK')){throw 'SOURCE_PUBLICATION_JOURNAL_INVALID'}
 Assert-PubArray $state.completedWrites JOURNAL_PROGRESS
 if($state.state-cin@('COMPLETE','ROLLED_BACK')){
  Assert-PubFields $state.completionProof @('outcome','validations','objects') COMPLETION_PROOF
  if($state.completionProof.outcome-cne$state.state-or$state.completionProof.validations-isnot[array]-or$state.completionProof.validations.Count-ne2-or(Get-PubCanonical $state.completionProof.objects)-cne(Get-PubCanonical @($state.objects|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$(if($state.state-ceq'COMPLETE'){$_.postimage.identity}else{$_.preimage.identity})}}))){throw 'SOURCE_PUBLICATION_COMPLETION_PROOF_INVALID'}
  if([string]::Join('|',@($state.completionProof.validations.member))-cne'SOURCE|CONTROL'){throw 'SOURCE_PUBLICATION_COMPLETION_PROOF_INVALID'}
  Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
  $completionRefs=[Collections.Generic.List[object]]::new()
  foreach($validation in $state.completionProof.validations){
   Assert-PubFields $validation @('member','inputRef','outputRef') VALIDATION
   $outputDoc=Read-PubEvidence $validation.outputRef $Root -Json;$v=$outputDoc.Value
   $inputDoc=Read-PubEvidence $validation.inputRef $Root -Json;$input=$inputDoc.Value
   $original=@($state.members|Where-Object member -CEQ $validation.member)
   if($original.Count-ne1){throw 'SOURCE_PUBLICATION_COMPLETION_PROOF_INVALID'}
   $receiptDoc=Read-PubEvidence $original[0].discoverReceiptRef $Root -Json;$receipt=$receiptDoc.Value
   $expected=if($state.state-ceq'COMPLETE'){'VALIDATED_PENDING_PUBLICATION_COMMIT'}else{'VALIDATED_PENDING_PUBLICATION_ROLLBACK'}
   $postIdentity='NO_SOURCE_POSTIMAGE_TRANSITION';$changed=@()
   if($null-ne$v.PSObject.Properties['sourcePostimageTransition']){$postIdentity=$v.sourcePostimageTransition.currentSourceCompositionIdentity;$changed=@($v.sourcePostimageTransition.changedBindings)}
   if($input.schemaVersion-ne3-or$input.mode-cne'FINALIZE_OUTPUT'-or$input.expectedDiscoverReceiptIdentity-cne$original[0].discoverReceiptRef.identity-or$v.selectionIdentity-cne$receipt.selectionIdentity-or$v.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $receipt $input $postIdentity $changed)-or$v.mode-cne'FINALIZE_OUTPUT'-or$v.status-cne'PASS'-or$v.projectSourcePreparation.candidateIdentity-cne$state.candidateRef.identity-or$v.projectSourcePreparation.outcome-cne$expected-or$v.actionOutcome-cne$expected){throw 'SOURCE_PUBLICATION_COMPLETION_PROOF_INVALID'}
   foreach($doc in @($outputDoc,$inputDoc,$receiptDoc)){$completionRefs.Add([pscustomobject]@{path=[string]$doc.Path;identity=[string]$doc.Identity})}
  }
  if($null-ne$memoFacts){$memoFacts|Add-Member -NotePropertyName CompletedJournal -NotePropertyValue ([pscustomobject]@{journalIdentity=$journalIdentity;implementationIdentity=$script:PublicationImplementationIdentity;references=$completionRefs.ToArray()}) -Force}
 }
 if($state.state-cin@('APPLYING','ROLLING_BACK')){
  if($null-eq$Recovery){throw 'SOURCE_PUBLICATION_IN_PROGRESS|upgrade-project -ProjectRuleRecoveryPlanPath'}
  if((Get-PubCanonical $state.planRef)-cne(Get-PubCanonical $Recovery.planRef)-or(Get-PubCanonical $state.candidateRef)-cne(Get-PubCanonical $Recovery.candidateRef)){throw 'SOURCE_PUBLICATION_RECOVERY_JOURNAL_DRIFT'}
 }
 }catch{
  if($null-ne$memoFacts){$memoFacts|Add-Member -NotePropertyName CompletedJournal -NotePropertyValue $null -Force}
  throw
 }
}
function Enter-AiwProjectSourceScope {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[ValidateSet('OBSERVE','WRITE','PUBLICATION')][string]$Mode='OBSERVE')
 # Ordinary reads have no coordination lease or journal side effect.
 if($Mode-ceq'OBSERVE'){return $null}
 $root=Get-PubRoot $ProjectRoot
 $stack=@(Get-PSCallStack);$caller=$stack[1].InvocationInfo
 $rootHelper=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../scripts/ProjectAdoptionState.psm1'))
 if($stack.Count-gt2-and$stack[1].FunctionName-ceq'Enter-AiwRootProjectSourceScope'-and[IO.Path]::GetFullPath($stack[1].ScriptName).Equals($rootHelper,[StringComparison]::OrdinalIgnoreCase)){$caller=$stack[2].InvocationInfo}
 $parent=Get-PubStackScope $root
 if($null-ne$parent){
  $facts=Get-PubLeaseFacts $parent
  if($Mode-cne'OBSERVE'-and$facts.Mode-ceq'OBSERVE'){throw 'SOURCE_PUBLICATION_LOCK_ORDER'}
  if($Mode-cne'PUBLICATION'){Assert-PubJournalObservation $facts}
  $scope=[pscustomobject]@{Root=$root;Mode=$facts.Mode;Handle=$parent.Handle;OwnerModule=$script:PublicationModule}
  $script:PublicationLeases.Add($scope,[pscustomobject]@{Root=$root;Mode=$facts.Mode;Handle=$parent.Handle;Invocation=$caller;Owned=$false;Runspace=$facts.Runspace;Recovery=$facts.Recovery;Origin=$facts.Origin})
  return $scope
 }
 if(-not$IsWindows-or$PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7-or$root.StartsWith('\\',[StringComparison]::Ordinal)){throw 'SOURCE_PUBLICATION_PLATFORM_UNSUPPORTED'}
 $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
 if($drive.DriveType-cnotin@([IO.DriveType]::Fixed,[IO.DriveType]::Removable)){throw 'SOURCE_PUBLICATION_FILESYSTEM_UNSUPPORTED'}
 $lockPath=Get-PubChild $root '.ai-workspace/runtime/source-publication.lock'
 $directory=[IO.Path]::GetDirectoryName($lockPath);[IO.Directory]::CreateDirectory($directory)|Out-Null;Assert-PubPath $directory
 $share=[IO.FileShare]::None
 try{$handle=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,$share)}
 catch [IO.IOException]{
  $native=$_.Exception.HResult-band0xFFFF
  if($native-in@(32,33)){throw ('SOURCE_PUBLICATION_BUSY|requestedMode='+$Mode+'|holder=UNKNOWN|next=DEFER_CURRENT_ATTEMPT')}
  throw
 }
 $scope=$null
 try{
  [AiwPublication.NativeDirectory]::SingleLink($handle.SafeFileHandle)
  if($handle.Length-ne0){throw 'SOURCE_PUBLICATION_LOCK_CONTENT'}
  $scope=[pscustomobject]@{Root=$root;Mode=$Mode;Handle=$handle;OwnerModule=$script:PublicationModule}
  $facts=[pscustomobject]@{Root=$root;Mode=$Mode;Handle=$handle;Invocation=$caller;Owned=$true;Runspace=[Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId;Recovery=$null;Origin=$scope}
  $script:PublicationLeases.Add($scope,$facts)
  if($Mode-cne'PUBLICATION'){Assert-PubJournalObservation $facts}
  return $scope
 }catch{if($null-ne$scope){$script:PublicationLeases.Remove($scope)|Out-Null};$handle.Dispose();throw}
}
function Exit-AiwProjectSourceScope {
 [CmdletBinding()]param([AllowNull()]$Scope)
 if($null-eq$Scope){return}
 $local=$null
 if(-not$script:PublicationLeases.TryGetValue($Scope,[ref]$local)){throw 'SOURCE_PUBLICATION_SCOPE_INVALID'}
 $facts=Get-PubLeaseFacts $Scope
 $script:PublicationLeases.Remove($Scope)|Out-Null
 if($facts.Owned){
  if($null-ne$facts.PSObject.Properties['CompletedJournal']){$facts.CompletedJournal=$null}
  $Scope.Handle.Dispose()
 }
}
function Get-AiwProjectSourcePublicationContext {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot)
 $scope=Get-PubStackScope (Get-PubRoot $ProjectRoot)
 if($null-eq$scope){return $null}
 return (Get-PubLeaseFacts $scope).Recovery
}
function Read-AiwProjectSourcePublicationJournal {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot)
 $root=Get-PubRoot $ProjectRoot
 # This explicit transaction API validates its journal. Ordinary OBSERVE
 # calls do not invoke it or acquire a replacement read lease.
 $scope=Get-PubStackScope $root
 if($null-ne$scope){Assert-PubJournalObservation (Get-PubLeaseFacts $scope)}
 else{Assert-PubJournalCurrent $root $null $null}
 $path=Get-PubChild $root '.ai-workspace/upgrade-recovery/project-rules/source-publication/state.json'
 if([IO.File]::Exists($path)){return (Read-AiwStrictInputJson $path).Value}
 return $null
}
function Set-AiwProjectSourcePublicationContext {
 [CmdletBinding()]param([Parameter(Mandatory)]$Scope,[Parameter(Mandatory)]$Recovery)
 $facts=Get-PubLeaseFacts $Scope
 if(-not$facts.Owned){$facts=Get-PubLeaseFacts $facts.Origin}
 if(-not$facts.Owned-or$facts.Mode-cne'PUBLICATION'){throw 'SOURCE_PUBLICATION_RECOVERY_SCOPE_REQUIRED'}
 # Only the original two actual admissions and exact plan/candidate can create
 # a recovery context. The handle by itself is never authority.
 $proof=Get-AiwProjectSourcePublicationRecoveryProof -ProjectRoot $facts.Root -Recovery $Recovery
 $facts.Recovery=$proof
 return $proof
}

Export-ModuleMember -Function Enter-AiwProjectSourceScope,Exit-AiwProjectSourceScope,Get-AiwProjectSourcePublicationContext,Set-AiwProjectSourcePublicationContext,Get-AiwPublicationInputProjectRoot,Get-AiwProjectSourcePublicationEligibility,Get-AiwProjectSourcePublicationReachability,Get-AiwProjectSourcePublicationMembers,Read-AiwProjectSourcePublicationJournal
