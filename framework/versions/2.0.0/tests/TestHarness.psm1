# @design-contract standards/software/VALIDATION.md
# Fixture construction and compatible native facade; native state has one owner.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestNativeOutput.psm1')
Initialize-AiwTestNativeOutput
Import-Module (Join-Path $PSScriptRoot 'TestExecutionRuntime.psm1')
$script:TestUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:TestHarnessModulePath=$PSCommandPath
function Copy-AiwTestAllowlist([string]$SourceRoot,[string]$DestinationRoot,[string[]]$Paths){
 $source=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot));$destination=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $DestinationRoot))
 if($destination-ceq$source-or$source.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_ALLOWLIST_DESTINATION_OVERLAP'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($path in $Paths){if($path-cmatch'^[A-Za-z]:|^[/\\]|\\|(^|/)\.{1,2}(/|$)|:|(^|/)RELEASE_MANIFEST\.json$'-or-not$seen.Add($path)){throw ('TEST_ALLOWLIST_PATH|'+$path)}}
 # Validate every locator before touching any source bytes.
 foreach($path in $Paths){$from=Join-Path $source $path;$identity=Get-AiwTestFileIdentity $from;$to=Assert-AiwTestPath (Join-Path $destination $path);$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to));[IO.File]::Copy($from,$to,$false);if((Get-AiwTestFileIdentity $to)-cne$identity){throw 'TEST_ALLOWLIST_COPY_DRIFT'}}
}
function New-AiwTestMechanismFixture([string]$SourceRoot,[string]$DestinationRoot,[string]$DefinitionPath,[switch]$Maintenance){
 $null=Get-AiwTestFileIdentity $DefinitionPath
 $definition=Get-Content -LiteralPath $DefinitionPath -Raw|ConvertFrom-Json -Depth 100
 if($definition.schemaVersion-notin@(1,2,3)-or$definition.phase-cnotin@('PREPACKAGE','PREPACKAGE_AND_POSTBUILD')){throw 'TEST_FIXTURE_DEFINITION_VERSION'}
 $rootPaths=@($definition.rootAdoptionPaths)
 if($Maintenance){$rootPaths+=@($definition.maintenancePaths)}
 $version=New-AiwTestRuntimeFixture $SourceRoot $DestinationRoot $definition.mechanismVersionPaths $rootPaths
 if($Maintenance){foreach($name in @('README.md','AGENTS.md')){[IO.File]::Copy((Join-Path $DestinationRoot ('framework/user-package/'+$name)),(Join-Path $DestinationRoot $name),$false)}}
 return $version
}
function New-AiwTestRuntimeFixture {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][string[]]$VersionPaths,[string[]]$RootPaths=@())
 $version='framework/versions/2.0.0'
 Copy-AiwTestAllowlist $SourceRoot $DestinationRoot @(@($VersionPaths|ForEach-Object{$version+'/'+$_})+@($RootPaths))
 $root=Join-Path $DestinationRoot $version
 Set-AiwTestFixtureQualification $root
 return $root
}
function Set-AiwTestFixtureQualification([string]$VersionRoot,[switch]$Candidate){
 $root=[IO.Path]::GetFullPath($VersionRoot);$lifecycle=if($Candidate){'CANDIDATE'}else{'STABLE'}
 foreach($name in @('VERSION.json','LOAD_MANIFEST.json')){$path=Join-Path $root $name;$value=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 100;$value.lifecycle=$lifecycle;if($name-ceq'VERSION.json'){$value.consumable=-not$Candidate;$value.projectPinEligible=-not$Candidate};[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 100 -Compress)+"`n",$script:TestUtf8)}
 [string[]]$paths=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'});[Array]::Sort($paths,[StringComparer]::Ordinal)
 $rows=@();[long]$bytes=0;foreach($path in $paths){$identity=Get-AiwTestFileIdentity (Join-Path $root $path);$rows+=($path+'|'+$identity);$bytes+=[long]$identity.Split('|')[0]}
 $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:TestUtf8.GetBytes($rows-join"`n")))
 $manifest=[ordered]@{schemaVersion=2;version='2.0.0';lifecycle=$lifecycle;releaseClass='MAJOR';scope='all release payload files except RELEASE_MANIFEST.json';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$paths.Count;totalBytes=$bytes;canonical=$canonical;baseline='1.16.0';sourceReview='PENDING';sourceCandidate='SYNTHETIC_TEST_FIXTURE_ONLY';completeSuite=@{status='PASS';passed=1;total=1;payloadCanonical=$canonical;evidenceIdentity=('1|'+('A'*64))};sourceReviewEvidence=@{status='APPROVED';reviewer='synthetic-fixture';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$canonical;reviewedManifestIdentity=('1|'+('C'*64))};releaseIntegration=$(if($Candidate){'PENDING'}else{'SYNTHETIC_TEST_FIXTURE_ONLY'})}
 $manifestPath=Join-Path $root 'RELEASE_MANIFEST.json'
 [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 100 -Compress)+"`n",$script:TestUtf8)
 $manifest.sourceReviewEvidence.reviewedManifestIdentity=Get-AiwTestFileIdentity $manifestPath
 $manifest.sourceReview='APPROVED'
 [IO.File]::WriteAllText((Join-Path $root 'RELEASE_MANIFEST.json'),($manifest|ConvertTo-Json -Depth 100 -Compress)+"`n",$script:TestUtf8)
}
function Get-AiwTestFixtureSnapshot([string]$Root,[switch]$IdentityOnly){
 $full=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $Root));$rows=@();$directories=@()
 foreach($item in Get-ChildItem -LiteralPath $full -Recurse -Force){
  if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'TEST_RESET_REPARSE'}
  $relative=[IO.Path]::GetRelativePath($full,$item.FullName).Replace('\','/')
  if($item.PSIsContainer){$directories+=$relative}else{
   $path=Assert-AiwTestPath $item.FullName
   $bytes=[IO.File]::ReadAllBytes($path)
   $row=@{path=$relative;identity=($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))}
   if(-not$IdentityOnly){$row.base64=[Convert]::ToBase64String($bytes)}
   $rows+=$row
  }
 }
 return [pscustomobject]@{Root=$full;Files=@($rows);Directories=@($directories)}
}
function New-AiwTestSourceView {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)]$Definition)
 $source=Assert-AiwTestPath $SourceRoot;$destination=Assert-AiwTestPath $DestinationRoot
 if($destination.StartsWith([IO.Path]::TrimEndingDirectorySeparator($source)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$source.StartsWith([IO.Path]::TrimEndingDirectorySeparator($destination)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$source.Equals($destination,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_SOURCE_VIEW_OVERLAP'}
 if(Test-Path -LiteralPath $destination){throw 'TEST_SOURCE_VIEW_EXISTS'}
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 $versionRelative='framework/versions/2.0.0/';$versionRoot=Join-Path $source $versionRelative
 $facts=& $reader.ExportedCommands['Get-AiwReleasePayloadFacts'] $versionRoot -SourceView
 $toolPaths=@(& $reader.ExportedCommands['Get-AiwReleaseRuntimeToolPaths'] $versionRoot -Maintenance)
 $paths=@($Definition.sourceViewPaths)+@($facts.Files|ForEach-Object{$versionRelative+$_})
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$inputs=@()
 # Freeze and validate the entire finite set before allocating/copying the view.
 foreach($path in $paths){if($path-ceq($versionRelative+'RELEASE_MANIFEST.json')-or-not$seen.Add($path)){continue};& $reader.ExportedCommands['Assert-AiwReleaseLocator'] $path;$identity=Get-AiwTestFileIdentity (Join-Path $source $path);$role=if($path.StartsWith($versionRelative,[StringComparison]::Ordinal)){'CURRENT_PAYLOAD'}elseif($path-cin$toolPaths){'CURRENT_RUNTIME_TOOL'}else{'SOURCE_ONLY_BUILD_OR_TEST_INPUT'};$inputs+=@{path=$path;identity=$identity;logicalRole=$role;distributionLocator=$(if($role-cin@('CURRENT_PAYLOAD','CURRENT_RUNTIME_TOOL')){$path}else{$null})}}
 foreach($input in $inputs){$from=Assert-AiwTestPath (Join-Path $source $input.path);$to=Assert-AiwTestPath (Join-Path $destination $input.path);$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to));[IO.File]::Copy($from,$to,$false);if((Get-AiwTestFileIdentity $to)-cne$input.identity){throw 'TEST_SOURCE_VIEW_COPY_DRIFT'}}
 $viewVersion=Join-Path $destination $versionRelative;$version=Get-Content -LiteralPath (Join-Path $viewVersion 'VERSION.json') -Raw|ConvertFrom-Json -Depth 100
 # Build from frozen P/VERSION/D and constants. Never read the live manifest or Qpre.
 $manifest=[ordered]@{schemaVersion=2;version='2.0.0';lifecycle=$version.lifecycle;releaseClass=$version.releaseClass;scope='all release payload files except RELEASE_MANIFEST.json';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$facts.FileCount;totalBytes=$facts.TotalBytes;canonical=$facts.Canonical;baseline=$version.baseline;sourceReview='APPROVED';sourceCandidate='SYNTHETIC_SOURCE_VIEW_ONLY';releaseIntegration=$(if($version.lifecycle-ceq'CANDIDATE'){'PENDING'}else{'SYNTHETIC_TEST_FIXTURE_ONLY'});completeSuite=@{status='PASS';passed=1;total=1;payloadCanonical=$facts.Canonical;evidenceIdentity=('1|'+('A'*64))};sourceReviewEvidence=@{status='APPROVED';reviewer='synthetic-source-view';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$facts.Canonical;reviewedManifestIdentity=('1|'+('C'*64))}}
 $manifestPath=Join-Path $viewVersion 'RELEASE_MANIFEST.json';Write-AiwTestJson $manifestPath $manifest
 $closure=[ordered]@{schemaVersion=1;kind='SOURCE_INPUT_CLOSURE';inputView='SOURCE_PAYLOAD_V1';sourceRoot=$source;definitionIdentity=(Get-AiwTestFileIdentity (Join-Path $source ($versionRelative+'tests/test-groups.json')));payloadCanonical=$facts.Canonical;inputs=$inputs;syntheticInputs=@(@{path=($versionRelative+'RELEASE_MANIFEST.json');identity=(Get-AiwTestFileIdentity $manifestPath);logicalRole='SYNTHETIC_FIXTURE_INPUT';distributionLocator=$null;constructorIdentity=(Get-AiwTestFileIdentity $script:TestHarnessModulePath)})}
 if($Definition.schemaVersion-eq3){
  $closure.schemaVersion=2;$closure.locationPolicy=@{mode='EXACT';mappings=@();conditions=@()}
  $closure.recipeIdentity=Get-AiwReleaseValueIdentity @{constructorIdentity=(Get-AiwTestFileIdentity $script:TestHarnessModulePath);definitionIdentity=$closure.definitionIdentity;payloadCanonical=$closure.payloadCanonical;inputs=$closure.inputs;syntheticInputs=$closure.syntheticInputs;locationPolicy=$closure.locationPolicy}
 }
 $closurePath=Join-Path $destination 'source-inputs.json';Write-AiwTestJson $closurePath $closure
 return [pscustomobject]@{Root=$destination;ClosurePath=$closurePath;ClosureIdentity=(Get-AiwTestFileIdentity $closurePath);ManifestIdentity=(Get-AiwTestFileIdentity $manifestPath);PayloadCanonical=$facts.Canonical}
}
function Enter-AiwTestSourceView {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)][string]$EvidenceRoot,[string[]]$ResumeEvidence=@())
 $source=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot));$destination=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $DestinationRoot));$evidence=Assert-AiwTestPath $EvidenceRoot
 foreach($other in @($source,$evidence)+@($ResumeEvidence|ForEach-Object{Assert-AiwTestPath $_})){
  if($destination.Equals($other,[StringComparison]::OrdinalIgnoreCase)-or$destination.StartsWith($other+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$other.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_SOURCE_VIEW_OVERLAP'}
 }
 $ownerPath=Assert-AiwTestPath ($destination+'.owner.json');$lockPath=Assert-AiwTestPath ($destination+'.lock')
 $principal=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $owner=$principal+'|'+[string]$env:CODEX_THREAD_ID
 $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
 if((Test-Path -LiteralPath $lockPath)-and(Get-Item -LiteralPath $lockPath).Length-ne0){throw 'TEST_SOURCE_VIEW_LOCK_CONTENT'}
 try{$lease=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'TEST_SOURCE_VIEW_ACTIVE'}
 try{
  foreach($handle in @(Get-AiwTestOwnedHandles)){if(-not$handle.Completed-and($handle.Cwd-ceq$destination-or$handle.Cwd.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'TEST_SOURCE_VIEW_ACTIVE'}}
  $exists=Test-Path -LiteralPath $destination;$ownerExists=Test-Path -LiteralPath $ownerPath;$ownerIdentity=$null
  if($exists-ne$ownerExists){throw 'TEST_SOURCE_VIEW_OWNERSHIP_UNKNOWN'}
  $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
  if($exists){
   if(-not(Get-Item -LiteralPath $destination).PSIsContainer-or(Get-Item -LiteralPath $ownerPath).PSIsContainer){throw 'TEST_SOURCE_VIEW_OWNERSHIP_UNKNOWN'}
   $receipt=& $reader.ExportedCommands['Read-AiwReleaseJson'] $ownerPath
   if(@($receipt.PSObject.Properties).Count-ne6-or@('schemaVersion','kind','owner','sourceRoot','destinationRoot','snapshot'|Where-Object{$_-cnotin$receipt.PSObject.Properties.Name}).Count){throw 'TEST_SOURCE_VIEW_OWNERSHIP_UNKNOWN'}
   $ownerParts=@(if($receipt.owner-is[string]){$receipt.owner.Split('|')})
   if($receipt.schemaVersion-ne1-or$receipt.kind-cne'OWNED_TEST_SOURCE_VIEW'-or$ownerParts.Count-ne2-or-not[StringComparer]::Ordinal.Equals($ownerParts[0],$principal)-or$receipt.sourceRoot-cne$source-or$receipt.destinationRoot-cne$destination){throw 'TEST_SOURCE_VIEW_OWNER_DRIFT'}
   $ownerIdentity=Get-AiwTestFileIdentity $ownerPath
   # Inspect each child before descending; a new reparse/unknown item never authorizes replacement.
   $stack=[Collections.Generic.Stack[string]]::new();$stack.Push($destination)
   while($stack.Count){$dir=$stack.Pop();foreach($item in Get-ChildItem -LiteralPath $dir -Force){$path=Assert-AiwTestPath $item.FullName;if($item.PSIsContainer){$stack.Push($path)}}}
   $current=Get-AiwTestFixtureSnapshot $destination -IdentityOnly;$expected=$receipt.snapshot
   if(@($expected.PSObject.Properties).Count-ne3-or@('Root','Files','Directories'|Where-Object{$_-cnotin$expected.PSObject.Properties.Name}).Count){throw 'TEST_SOURCE_VIEW_OWNERSHIP_UNKNOWN'}
   if($current.Root-cne$expected.Root-or$current.Files.Count-ne$expected.Files.Count-or$current.Directories.Count-ne$expected.Directories.Count-or@($current.Directories|Where-Object{$_-cnotin$expected.Directories}).Count){throw 'TEST_SOURCE_VIEW_UNKNOWN_CONTENT'}
   foreach($row in $current.Files){$prior=@($expected.Files|Where-Object path -CEQ $row.path);if($prior.Count-ne1-or$prior[0].identity-cne$row.identity){throw 'TEST_SOURCE_VIEW_UNKNOWN_CONTENT'}}
   # Reuse preparation only when the owned complete view and every frozen input
   # still match this exact recipe. This is neither a cached PASS nor authority.
   $closurePath=Join-Path $destination 'source-inputs.json'
   $closure=Read-AiwReleaseJson $closurePath
   $sourceFacts=& $reader.ExportedCommands['Get-AiwReleasePayloadFacts'] (Join-Path $source 'framework/versions/2.0.0') -SourceView
   $canReuse=$closure.sourceRoot-ceq$source-and$closure.definitionIdentity-ceq(Get-AiwTestFileIdentity (Join-Path $source 'framework/versions/2.0.0/tests/test-groups.json'))-and$closure.payloadCanonical-ceq$sourceFacts.Canonical-and$closure.syntheticInputs.Count-eq1-and$closure.syntheticInputs[0].constructorIdentity-ceq(Get-AiwTestFileIdentity $script:TestHarnessModulePath)
   $expectedPaths=@(@($Definition.sourceViewPaths)+@($sourceFacts.Files|ForEach-Object{'framework/versions/2.0.0/'+$_})|Where-Object{$_-cne'framework/versions/2.0.0/RELEASE_MANIFEST.json'}|Sort-Object -Unique)
   if($closure.inputs.Count-ne$expectedPaths.Count-or@($expectedPaths|Where-Object{$_-cnotin$closure.inputs.path}).Count){$canReuse=$false}
   if($canReuse-and$Definition.schemaVersion-eq3){
    $recipe=& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] @{constructorIdentity=(Get-AiwTestFileIdentity $script:TestHarnessModulePath);definitionIdentity=$closure.definitionIdentity;payloadCanonical=$closure.payloadCanonical;inputs=$closure.inputs;syntheticInputs=$closure.syntheticInputs;locationPolicy=$closure.locationPolicy}
    if($closure.schemaVersion-ne2-or$closure.recipeIdentity-cne$recipe-or$closure.locationPolicy.mode-cne'EXACT'){$canReuse=$false}
   }
   if($canReuse){foreach($input in $closure.inputs){if((Get-AiwTestFileIdentity (Join-Path $source $input.path))-cne$input.identity){$canReuse=$false;break}}}
   if($canReuse){return [pscustomobject]@{View=[pscustomobject]@{Root=$destination;ClosurePath=$closurePath;ClosureIdentity=(Get-AiwTestFileIdentity $closurePath);ManifestIdentity=(Get-AiwTestFileIdentity (Join-Path $destination 'framework/versions/2.0.0/RELEASE_MANIFEST.json'));PayloadCanonical=$closure.payloadCanonical;PreparationReuse='EXACT_OWNED_RECIPE'};Lease=$lease;OwnerPath=$ownerPath}}
   # The exact destination has been resolved, ownership/content verified and exclusively leased.
   Remove-Item -LiteralPath $destination -Recurse
  }
  $view=New-AiwTestSourceView -SourceRoot $source -DestinationRoot $destination -Definition $Definition
  $snapshot=Get-AiwTestFixtureSnapshot $destination -IdentityOnly
  $receiptTemporary=Assert-AiwTestPath ($ownerPath+'.writing-'+[guid]::NewGuid().ToString('N'))
  try{
   Write-AiwTestJson $receiptTemporary @{schemaVersion=1;kind='OWNED_TEST_SOURCE_VIEW';owner=$owner;sourceRoot=$source;destinationRoot=$destination;snapshot=$snapshot}
   if($exists-and(Get-AiwTestFileIdentity $ownerPath)-cne$ownerIdentity){throw 'TEST_SOURCE_VIEW_OWNER_DRIFT'}
   [IO.File]::Move($receiptTemporary,$ownerPath,[bool]$exists)
  }finally{if(Test-Path -LiteralPath $receiptTemporary){Remove-Item -LiteralPath $receiptTemporary}}
  return [pscustomobject]@{View=$view;Lease=$lease;OwnerPath=$ownerPath}
 }catch{$lease.Dispose();throw}
}
function Get-AiwTestResetChild([string]$Root,[string]$Relative){
 if([string]::IsNullOrWhiteSpace($Relative)-or$Relative-cmatch'^[A-Za-z]:|^[/\\]|\\|:|(^|/)\.{1,2}(/|$)'){throw 'TEST_RESET_LOCATOR'}
 $path=Assert-AiwTestPath (Join-Path $Root $Relative)
 if(-not$path.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_RESET_OUTSIDE_ROOT'}
 return $path
}
function Reset-AiwTestFixture($Snapshot,[string]$Root,$Handles=@(),[string[]]$ActiveMarkerPaths=@()){
 $full=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $Root));if($full-cne$Snapshot.Root){throw 'TEST_RESET_ROOT_DRIFT'}
 foreach($handle in @($Handles)+@(Get-AiwTestOwnedHandles)){
  if(-not$handle.Completed-and($handle.Cwd-ceq$full-or$handle.Cwd.StartsWith($full+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or@($Handles).Contains($handle))){throw 'TEST_RESET_ACTIVE_WORKER'}
 }
 foreach($marker in $ActiveMarkerPaths){if(Test-Path -LiteralPath (Get-AiwTestResetChild $full $marker)){throw 'TEST_RESET_ACTIVE_MARKER'}}
 $null=Get-AiwTestFixtureSnapshot $full -IdentityOnly
 $files=@($Snapshot.Files.path);$directories=@($Snapshot.Directories)
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$decoded=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($row in $Snapshot.Files){
  $null=Get-AiwTestResetChild $full $row.path
  if(-not$seen.Add($row.path)){throw 'TEST_RESET_DUPLICATE'}
  $bytes=[Convert]::FromBase64String($row.base64)
  if(($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))-cne$row.identity){throw 'TEST_RESET_SNAPSHOT_CORRUPT'}
  $decoded[$row.path]=$bytes
 }
 $directorySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($directory in $directories){$null=Get-AiwTestResetChild $full $directory;if(-not$directorySet.Add($directory)){throw 'TEST_RESET_DUPLICATE'}}
 foreach($path in @($files)+@($directories)){$parts=$path.Split('/');if($directorySet.Contains($path)-and$seen.Contains($path)){throw 'TEST_RESET_FILE_DIRECTORY_CONFLICT'};for($i=1;$i -lt $parts.Count;$i++){if($seen.Contains(($parts[0..($i-1)]-join'/'))){throw 'TEST_RESET_FILE_DIRECTORY_CONFLICT'}}}
 foreach($item in Get-ChildItem -LiteralPath $full -Recurse -File -Force){$relative=[IO.Path]::GetRelativePath($full,$item.FullName).Replace('\','/');if($relative-cnotin$files){Remove-Item -LiteralPath (Get-AiwTestResetChild $full $relative) -Force}}
 foreach($item in Get-ChildItem -LiteralPath $full -Recurse -Directory -Force|Sort-Object {$_.FullName.Length} -Descending){$relative=[IO.Path]::GetRelativePath($full,$item.FullName).Replace('\','/');if($relative-cnotin$directories){Remove-Item -LiteralPath (Get-AiwTestResetChild $full $relative) -Force}}
 foreach($directory in $directories){$null=[IO.Directory]::CreateDirectory((Get-AiwTestResetChild $full $directory))}
 foreach($row in $Snapshot.Files){[IO.File]::WriteAllBytes((Get-AiwTestResetChild $full $row.path),$decoded[$row.path])}
 $after=Get-AiwTestFixtureSnapshot $full -IdentityOnly
 if(@($after.Files).Count-ne@($Snapshot.Files).Count-or@($after.Directories).Count-ne$directories.Count-or@($after.Directories|Where-Object{$_-cnotin$directories}).Count){throw 'TEST_RESET_INCOMPLETE'}
 foreach($row in $Snapshot.Files){$actual=@($after.Files|Where-Object path -CEQ $row.path);if($actual.Count-ne1-or$actual[0].identity-cne$row.identity){throw 'TEST_RESET_IDENTITY'}}
 return [pscustomobject]@{status='CLEAN';root=$full;files=$after.Files.Count;directories=$after.Directories.Count}
}
Export-ModuleMember -Function Assert-AiwTestPath,Get-AiwTestFileIdentity,Write-AiwTestJson,Write-AiwTestPhase,Start-AiwTestProcess,Wait-AiwTestProcess,Stop-AiwTestProcess,Invoke-AiwTestProcess,Get-AiwTestRawProcessStates,Copy-AiwTestAllowlist,New-AiwTestRuntimeFixture,New-AiwTestMechanismFixture,New-AiwTestSourceView,Enter-AiwTestSourceView,Set-AiwTestFixtureQualification,Get-AiwTestFixtureSnapshot,Reset-AiwTestFixture
