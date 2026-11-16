# @design-contract standards/software/VALIDATION.md
# Fixture construction and compatible native facade; native state has one owner.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestNativeOutput.psm1')
Initialize-AiwTestNativeOutput
Import-Module (Join-Path $PSScriptRoot 'TestExecutionRuntime.psm1')
$script:TestUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:TestHarnessModulePath=$PSCommandPath
function Copy-TestAllowlistCore([string]$SourceRoot,[string]$DestinationRoot,[string[]]$Paths){
 $source=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot));$destination=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $DestinationRoot))
 if($destination-ceq$source-or$source.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_ALLOWLIST_DESTINATION_OVERLAP'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($path in $Paths){if($path-cmatch'^[A-Za-z]:|^[/\\]|\\|(^|/)\.{1,2}(/|$)|:|(^|/)RELEASE_MANIFEST\.json$'-or-not$seen.Add($path)){throw ('TEST_ALLOWLIST_PATH|'+$path)}}
 # Validate every locator before touching any source bytes.
 $copied=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($path in $Paths){
  $from=Assert-AiwTestPath (Join-Path $source $path);$to=Assert-AiwTestPath (Join-Path $destination $path)
  $bytes=[IO.File]::ReadAllBytes($from);$identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
  $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
  $stream=[IO.File]::Open($to,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($bytes)}finally{$stream.Dispose()}
  if((Get-AiwTestFileIdentity $to)-cne$identity){throw 'TEST_ALLOWLIST_COPY_DRIFT'}
  $copied.Add($to,$identity)
 }
 return ,$copied
}
function Copy-AiwTestAllowlist([string]$SourceRoot,[string]$DestinationRoot,[string[]]$Paths){
 $null=Copy-TestAllowlistCore $SourceRoot $DestinationRoot $Paths
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
 $copied=Copy-TestAllowlistCore $SourceRoot $DestinationRoot @(@($VersionPaths|ForEach-Object{$version+'/'+$_})+@($RootPaths))
 $root=Join-Path $DestinationRoot $version
 Set-TestFixtureQualificationCore $root -CopiedIdentities $copied
 return $root
}
function Set-TestFixtureQualificationCore([string]$VersionRoot,[switch]$Candidate,$CopiedIdentities=$null){
 $root=[IO.Path]::GetFullPath($VersionRoot);$lifecycle=if($Candidate){'CANDIDATE'}else{'STABLE'}
 foreach($name in @('VERSION.json','LOAD_MANIFEST.json')){$path=Join-Path $root $name;$value=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 100;$value.lifecycle=$lifecycle;if($name-ceq'VERSION.json'){$value.consumable=-not$Candidate;$value.projectPinEligible=-not$Candidate};[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 100 -Compress)+"`n",$script:TestUtf8)}
 [string[]]$paths=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'});[Array]::Sort($paths,[StringComparer]::Ordinal)
 $rows=@();[long]$bytes=0;foreach($path in $paths){$full=Assert-AiwTestPath (Join-Path $root $path);$identity=if($null-ne$CopiedIdentities-and$path-cnotin@('VERSION.json','LOAD_MANIFEST.json')-and$CopiedIdentities.ContainsKey($full)){$CopiedIdentities[$full]}else{Get-AiwTestFileIdentity $full};$rows+=($path+'|'+$identity);$bytes+=[long]$identity.Split('|')[0]}
 $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:TestUtf8.GetBytes($rows-join"`n")))
 $manifest=[ordered]@{schemaVersion=2;version='2.0.0';lifecycle=$lifecycle;releaseClass='MAJOR';scope='all release payload files except RELEASE_MANIFEST.json';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$paths.Count;totalBytes=$bytes;canonical=$canonical;baseline='1.16.0';sourceReview='PENDING';sourceCandidate='SYNTHETIC_TEST_FIXTURE_ONLY';completeSuite=@{status='PASS';passed=1;total=1;payloadCanonical=$canonical;evidenceIdentity=('1|'+('A'*64))};sourceReviewEvidence=@{status='APPROVED';reviewer='synthetic-fixture';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$canonical;reviewedManifestIdentity=('1|'+('C'*64))};releaseIntegration=$(if($Candidate){'PENDING'}else{'SYNTHETIC_TEST_FIXTURE_ONLY'})}
 $manifestPath=Join-Path $root 'RELEASE_MANIFEST.json'
 [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 100 -Compress)+"`n",$script:TestUtf8)
 $manifest.sourceReviewEvidence.reviewedManifestIdentity=Get-AiwTestFileIdentity $manifestPath
 $manifest.sourceReview='APPROVED'
 [IO.File]::WriteAllText((Join-Path $root 'RELEASE_MANIFEST.json'),($manifest|ConvertTo-Json -Depth 100 -Compress)+"`n",$script:TestUtf8)
}
function Set-AiwTestFixtureQualification([string]$VersionRoot,[switch]$Candidate){
 # Existing arbitrary-fixture callers still observe every actual member.
 Set-TestFixtureQualificationCore $VersionRoot -Candidate:$Candidate
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
function New-TestSourcePreparation([string]$SourceRoot,$Definition){
 $source=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot))
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 $vp='framework/versions/2.0.0/';$version=Join-Path $source $vp
 $payload=& $reader {param($root)Get-ReleaseSourcePayloadSnapshot $root -CaptureBytes} $version
 $tools=@(& $reader.ExportedCommands['Get-AiwReleaseRuntimeToolPaths'] $version -Maintenance)
 $payloadIndex=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 foreach($member in $payload.Facts.Members){$payloadIndex.Add($member.path,$member.identity)}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 $inputs=@();$bytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
 $index=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($path in @($Definition.sourceViewPaths)+@($payload.Facts.Files|ForEach-Object{$vp+$_})){
  if($path-ceq($vp+'RELEASE_MANIFEST.json')-or-not$seen.Add($path)){continue}
  & $reader.ExportedCommands['Assert-AiwReleaseLocator'] $path
  $full=Assert-AiwTestPath (Join-Path $source $path)
  if($path.StartsWith($vp,[StringComparison]::Ordinal)-and$payload.Bytes.ContainsKey($path.Substring($vp.Length))){$raw=$payload.Bytes[$path.Substring($vp.Length)]}else{$raw=[IO.File]::ReadAllBytes($full)}
  $identity=if($path.StartsWith($vp,[StringComparison]::Ordinal)-and$payloadIndex.ContainsKey($path.Substring($vp.Length))){$payloadIndex[$path.Substring($vp.Length)]}else{& $reader.ExportedCommands['Get-AiwReleaseByteIdentity'] $raw}
  $role=if($path.StartsWith($vp,[StringComparison]::Ordinal)){'CURRENT_PAYLOAD'}elseif($path-cin$tools){'CURRENT_RUNTIME_TOOL'}else{'SOURCE_ONLY_BUILD_OR_TEST_INPUT'}
  $input=@{path=$path;identity=$identity;logicalRole=$role;distributionLocator=$(if($role-cin@('CURRENT_PAYLOAD','CURRENT_RUNTIME_TOOL')){$path}else{$null})}
  $inputs+=,$input;$index.Add($path,$input);$bytes.Add($path,$raw)
 }
 $dp=Join-Path $version 'tests/test-groups.json'
 $definitionIdentity=if($index.ContainsKey($vp+'tests/test-groups.json')){$index[$vp+'tests/test-groups.json'].identity}else{Get-AiwTestFileIdentity $dp}
 return [pscustomobject]@{Source=$source;Facts=$payload.Facts;Tools=$tools;Inputs=$inputs;Index=$index;Bytes=$bytes;DefinitionPath=$dp;DefinitionIdentity=$definitionIdentity;ConstructorIdentity=(Get-AiwTestFileIdentity $script:TestHarnessModulePath);Reader=$reader}
}
function Assert-TestSourcePreparationStable($Preparation){
 # A new independent byte guard closes the preparation window. Native execution
 # and BeforeExport retain their separate observations after this call ends.
 foreach($input in $Preparation.Inputs){if((Get-AiwTestFileIdentity (Join-Path $Preparation.Source $input.path))-cne$input.identity){throw ('TEST_SOURCE_PREPARATION_DRIFT|'+$input.path)}}
 if((Get-AiwTestFileIdentity $Preparation.DefinitionPath)-cne$Preparation.DefinitionIdentity-or(Get-AiwTestFileIdentity $script:TestHarnessModulePath)-cne$Preparation.ConstructorIdentity){throw 'TEST_SOURCE_PREPARATION_CONSTRUCTOR_DRIFT'}
}
function Invoke-TestPreparedReadClosure($Preparation,$Definition,[string[]]$GroupIds,[string]$Stage,[string]$ViewRoot='',$ViewSnapshot=$null){
 $evidence=@(Import-Module (Join-Path $PSScriptRoot 'TestGroupEvidence.psm1') -PassThru)[0]
 & $evidence {param($p,$d,$ids,$stage,$view,$snapshot) Assert-TestSourceViewReadClosureCore -SourceRoot $p.Source -DefinitionPath $p.DefinitionPath -Definition $d -GroupIds $ids -Stage $stage -ViewRoot $view -Preparation $p -ViewSnapshot $snapshot} $Preparation $Definition $GroupIds $Stage $ViewRoot $ViewSnapshot
}
function New-AiwTestSourceView {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)]$Definition)
 $preparation=New-TestSourcePreparation $SourceRoot $Definition
 $built=New-TestSourceViewCore $SourceRoot $DestinationRoot $Definition $preparation
 Assert-TestSourcePreparationStable $preparation
 return $built.View
}
function New-TestSourceViewCore {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)]$Preparation)
 $source=Assert-AiwTestPath $SourceRoot;$destination=Assert-AiwTestPath $DestinationRoot
 if($destination.StartsWith([IO.Path]::TrimEndingDirectorySeparator($source)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$source.StartsWith([IO.Path]::TrimEndingDirectorySeparator($destination)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$source.Equals($destination,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_SOURCE_VIEW_OVERLAP'}
 if(Test-Path -LiteralPath $destination){throw 'TEST_SOURCE_VIEW_EXISTS'}
 if($Preparation.Source-cne[IO.Path]::TrimEndingDirectorySeparator($source)){throw 'TEST_SOURCE_PREPARATION_ROOT'}
 $versionRelative='framework/versions/2.0.0/';$facts=$Preparation.Facts;$inputs=$Preparation.Inputs
 foreach($input in $inputs){
  $to=Assert-AiwTestPath (Join-Path $destination $input.path);$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
  $stream=[IO.File]::Open($to,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($Preparation.Bytes[$input.path])}finally{$stream.Dispose()}
 }
 $viewVersion=Join-Path $destination $versionRelative;$version=Get-Content -LiteralPath (Join-Path $viewVersion 'VERSION.json') -Raw|ConvertFrom-Json -Depth 100
 # Build from frozen P/VERSION/D and constants. Never read the live manifest or Qpre.
 $manifest=[ordered]@{schemaVersion=2;version='2.0.0';lifecycle=$version.lifecycle;releaseClass=$version.releaseClass;scope='all release payload files except RELEASE_MANIFEST.json';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$facts.FileCount;totalBytes=$facts.TotalBytes;canonical=$facts.Canonical;baseline=$version.baseline;sourceReview='APPROVED';sourceCandidate='SYNTHETIC_SOURCE_VIEW_ONLY';releaseIntegration=$(if($version.lifecycle-ceq'CANDIDATE'){'PENDING'}else{'SYNTHETIC_TEST_FIXTURE_ONLY'});completeSuite=@{status='PASS';passed=1;total=1;payloadCanonical=$facts.Canonical;evidenceIdentity=('1|'+('A'*64))};sourceReviewEvidence=@{status='APPROVED';reviewer='synthetic-source-view';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$facts.Canonical;reviewedManifestIdentity=('1|'+('C'*64))}}
 $manifestPath=Join-Path $viewVersion 'RELEASE_MANIFEST.json';Write-AiwTestJson $manifestPath $manifest
 $closure=[ordered]@{schemaVersion=1;kind='SOURCE_INPUT_CLOSURE';inputView='SOURCE_PAYLOAD_V1';sourceRoot=$source;definitionIdentity=$Preparation.DefinitionIdentity;payloadCanonical=$facts.Canonical;inputs=$inputs;syntheticInputs=@(@{path=($versionRelative+'RELEASE_MANIFEST.json');identity=(Get-AiwTestFileIdentity $manifestPath);logicalRole='SYNTHETIC_FIXTURE_INPUT';distributionLocator=$null;constructorIdentity=$Preparation.ConstructorIdentity})}
 if($Definition.schemaVersion-eq3){
  $closure.schemaVersion=2;$closure.locationPolicy=@{mode='EXACT';mappings=@();conditions=@()}
  $closure.recipeIdentity=& $Preparation.Reader.ExportedCommands['Get-AiwReleaseValueIdentity'] @{constructorIdentity=$Preparation.ConstructorIdentity;definitionIdentity=$closure.definitionIdentity;payloadCanonical=$closure.payloadCanonical;inputs=$closure.inputs;syntheticInputs=$closure.syntheticInputs;locationPolicy=$closure.locationPolicy}
 }
 $closurePath=Join-Path $destination 'source-inputs.json';Write-AiwTestJson $closurePath $closure
 $snapshot=Get-AiwTestFixtureSnapshot $destination -IdentityOnly
 $actual=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 foreach($row in $snapshot.Files){$actual.Add($row.path,$row.identity)}
 if($actual.Count-ne($inputs.Count+2)-or-not$actual.ContainsKey('source-inputs.json')-or-not$actual.ContainsKey($versionRelative+'RELEASE_MANIFEST.json')){throw 'TEST_SOURCE_VIEW_FILE_SET'}
 foreach($input in $inputs){if(-not$actual.ContainsKey($input.path)-or$actual[$input.path]-cne$input.identity){throw ('TEST_SOURCE_VIEW_COPY_DRIFT|'+$input.path)}}
 $expectedDirectories=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($path in $actual.Keys){$parent=[IO.Path]::GetDirectoryName($path).Replace('\','/');while($parent){$null=$expectedDirectories.Add($parent);$parent=[IO.Path]::GetDirectoryName($parent).Replace('\','/')}}
 if(-not$expectedDirectories.SetEquals([string[]]@($snapshot.Directories))){throw 'TEST_SOURCE_VIEW_DIRECTORY_SET'}
 $view=[pscustomobject]@{Root=$destination;ClosurePath=$closurePath;ClosureIdentity=$actual['source-inputs.json'];ManifestIdentity=$actual[$versionRelative+'RELEASE_MANIFEST.json'];PayloadCanonical=$facts.Canonical}
 return [pscustomobject]@{View=$view;Snapshot=$snapshot}
}
function Enter-AiwTestSourceView {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)][string]$EvidenceRoot,[string[]]$ResumeEvidence=@(),[string[]]$ReadClosureGroupIds=@())
 $source=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot));$destination=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $DestinationRoot));$evidence=Assert-AiwTestPath $EvidenceRoot
 foreach($other in @($source,$evidence)+@($ResumeEvidence|ForEach-Object{Assert-AiwTestPath $_})){
  if($destination.Equals($other,[StringComparison]::OrdinalIgnoreCase)-or$destination.StartsWith($other+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$other.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_SOURCE_VIEW_OVERLAP'}
 }
 $preparation=New-TestSourcePreparation $source $Definition
 if($ReadClosureGroupIds.Count){$null=Invoke-TestPreparedReadClosure $preparation $Definition $ReadClosureGroupIds 'BeforeEnter'}
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
   $sourceFacts=$preparation.Facts
   $canReuse=$closure.sourceRoot-ceq$source-and$closure.definitionIdentity-ceq$preparation.DefinitionIdentity-and$closure.payloadCanonical-ceq$sourceFacts.Canonical-and$closure.syntheticInputs.Count-eq1-and$closure.syntheticInputs[0].constructorIdentity-ceq$preparation.ConstructorIdentity
   $expectedPaths=@(@($Definition.sourceViewPaths)+@($sourceFacts.Files|ForEach-Object{'framework/versions/2.0.0/'+$_})|Where-Object{$_-cne'framework/versions/2.0.0/RELEASE_MANIFEST.json'}|Sort-Object -Unique)
   if($closure.inputs.Count-ne$expectedPaths.Count-or@($expectedPaths|Where-Object{$_-cnotin$closure.inputs.path}).Count){$canReuse=$false}
   if($canReuse-and$Definition.schemaVersion-eq3){
    $recipe=& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] @{constructorIdentity=$preparation.ConstructorIdentity;definitionIdentity=$closure.definitionIdentity;payloadCanonical=$closure.payloadCanonical;inputs=$closure.inputs;syntheticInputs=$closure.syntheticInputs;locationPolicy=$closure.locationPolicy}
    if($closure.schemaVersion-ne2-or$closure.recipeIdentity-cne$recipe-or$closure.locationPolicy.mode-cne'EXACT'){$canReuse=$false}
   }
   if($canReuse){foreach($input in $closure.inputs){if(-not$preparation.Index.ContainsKey($input.path)-or$preparation.Index[$input.path].identity-cne$input.identity){$canReuse=$false;break}}}
   if($canReuse){
    if($ReadClosureGroupIds.Count){$null=Invoke-TestPreparedReadClosure $preparation $Definition $ReadClosureGroupIds 'AfterConstruction' $destination $current}
    Assert-TestSourcePreparationStable $preparation
    return [pscustomobject]@{View=[pscustomobject]@{Root=$destination;ClosurePath=$closurePath;ClosureIdentity=(Get-AiwTestFileIdentity $closurePath);ManifestIdentity=(Get-AiwTestFileIdentity (Join-Path $destination 'framework/versions/2.0.0/RELEASE_MANIFEST.json'));PayloadCanonical=$closure.payloadCanonical;PreparationReuse='EXACT_OWNED_RECIPE'};Lease=$lease;OwnerPath=$ownerPath}}
   # The exact destination has been resolved, ownership/content verified and exclusively leased.
   Remove-Item -LiteralPath $destination -Recurse
  }
  $built=New-TestSourceViewCore $source $destination $Definition $preparation
  $view=$built.View;$snapshot=$built.Snapshot
  if($ReadClosureGroupIds.Count){$null=Invoke-TestPreparedReadClosure $preparation $Definition $ReadClosureGroupIds 'AfterConstruction' $destination $snapshot}
  Assert-TestSourcePreparationStable $preparation
  $receiptTemporary=Assert-AiwTestPath ($ownerPath+'.writing-'+[guid]::NewGuid().ToString('N'))
  try{
   Write-AiwTestJson $receiptTemporary @{schemaVersion=1;kind='OWNED_TEST_SOURCE_VIEW';owner=$owner;sourceRoot=$source;destinationRoot=$destination;snapshot=$snapshot}
   if($exists-and(Get-AiwTestFileIdentity $ownerPath)-cne$ownerIdentity){throw 'TEST_SOURCE_VIEW_OWNER_DRIFT'}
   [IO.File]::Move($receiptTemporary,$ownerPath,[bool]$exists)
  }finally{if(Test-Path -LiteralPath $receiptTemporary){Remove-Item -LiteralPath $receiptTemporary}}
  return [pscustomobject]@{View=$view;Lease=$lease;OwnerPath=$ownerPath}
 }catch{$lease.Dispose();throw}
}
function Get-TestPackageViewSnapshot([string]$Root){
 $full=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $Root));$files=[Collections.Generic.List[object]]::new();$directories=[Collections.Generic.List[string]]::new();$pending=[Collections.Generic.Stack[string]]::new();$pending.Push($full)
 while($pending.Count){
  $at=Assert-AiwTestPath $pending.Pop()
  foreach($item in Get-ChildItem -LiteralPath $at -Force){
   $path=Assert-AiwTestPath $item.FullName;$relative=[IO.Path]::GetRelativePath($full,$path).Replace('\','/')
   if($item.PSIsContainer){$directories.Add($relative);$pending.Push($path)}else{$files.Add(@{path=$relative;identity=(Get-AiwTestFileIdentity $path)})}
  }
 }
 $index=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);foreach($file in $files){$index.Add($file.path,$file)}
 [string[]]$paths=@($index.Keys);[Array]::Sort($paths,[StringComparer]::Ordinal);[string[]]$dirs=$directories.ToArray();[Array]::Sort($dirs,[StringComparer]::Ordinal)
 return [pscustomobject]@{Root=$full;Files=@(foreach($path in $paths){$index[$path]});Directories=@($dirs)}
}
function Assert-TestPackageWorkersEnded([string]$EvidenceRoot){
 $root=Assert-AiwTestPath $EvidenceRoot
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 if(-not[IO.Directory]::Exists($root)){throw 'TEST_PACKAGE_WORKER_STATE_UNKNOWN'}
 $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
 while($pending.Count){
  $at=Assert-AiwTestPath $pending.Pop();$items=@(Get-ChildItem -LiteralPath $at -Force)
  # Native transport allocates this directory before starting its process.
  # A crash before launch.json leaves no provable PID, even if raw is empty.
  if([IO.Path]::GetFileName($at)-cmatch'^[a-f0-9]{32}$'-and-not[IO.File]::Exists((Join-Path $at 'launch.json'))){
   # NativeTool call containers also use GUIDs and hold input/invoke files;
   # actual native allocations are empty before launch or hold transport files.
   if($items.Count-eq0-or@($items|Where-Object{-not$_.PSIsContainer-and$_.Name-cin@('stdout.raw','stderr.raw','phases.jsonl','result.json')}).Count){throw 'TEST_PACKAGE_WORKER_STATE_UNKNOWN'}
  }
  foreach($item in $items){$path=Assert-AiwTestPath $item.FullName;if($item.PSIsContainer){$pending.Push($path)}}
 }
 foreach($state in @(Get-AiwTestRawProcessStates $root)){
  $launch=& $reader.ExportedCommands['Read-AiwReleaseJson'] $state.launchPath -StringFields @('creationUtc')
  if(($state.pid-isnot[int]-and$state.pid-isnot[long])-or$state.pid-lt1-or$launch.creationUtc-isnot[string]){throw 'TEST_PACKAGE_WORKER_STATE_UNKNOWN'}
  $created=[DateTimeOffset]::MinValue
  if(-not[DateTimeOffset]::TryParse($launch.creationUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$created)){throw 'TEST_PACKAGE_WORKER_STATE_UNKNOWN'}
  $process=$null
  try{$process=[Diagnostics.Process]::GetProcessById([int]$state.pid)}catch [ArgumentException]{continue}catch{throw 'TEST_PACKAGE_WORKER_STATE_UNKNOWN'}
  try{
   if(-not$process.HasExited-and$process.StartTime.ToUniversalTime().Ticks-eq$created.UtcTicks){throw 'TEST_PACKAGE_VIEW_ACTIVE_WORKER'}
  }catch{if($_.Exception.Message-ceq'TEST_PACKAGE_VIEW_ACTIVE_WORKER'){throw};throw 'TEST_PACKAGE_WORKER_STATE_UNKNOWN'}finally{$process.Dispose()}
 }
}
function Enter-AiwTestPackageView {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$PackagePath,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][string]$EvidenceRoot,[string[]]$ResumeEvidence=@())
 $source=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $SourceRoot));$zip=Assert-AiwTestPath $PackagePath;$destination=[IO.Path]::TrimEndingDirectorySeparator((Assert-AiwTestPath $DestinationRoot));$evidence=Assert-AiwTestPath $EvidenceRoot
 foreach($other in @($source,$zip)+@($ResumeEvidence|ForEach-Object{Assert-AiwTestPath $_})){
  if($destination.Equals($other,[StringComparison]::OrdinalIgnoreCase)-or$destination.StartsWith($other+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$other.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_PACKAGE_VIEW_OVERLAP'}
 }
 if($evidence.Equals($destination,[StringComparison]::OrdinalIgnoreCase)-or$evidence.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_PACKAGE_VIEW_OVERLAP'}
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 $ownerPath=Assert-AiwTestPath ($destination+'.owner.json');$lockPath=Assert-AiwTestPath ($destination+'.lock');$principal=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
 if((Test-Path -LiteralPath $lockPath)-and(Get-Item -LiteralPath $lockPath).Length-ne0){throw 'TEST_PACKAGE_VIEW_LOCK_CONTENT'}
 try{$lease=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'TEST_PACKAGE_VIEW_ACTIVE'}
 $handles=[Collections.Generic.List[object]]::new()
 try{
  $packageRef=@{path=$zip;identity=(Get-AiwTestFileIdentity $zip)};$exists=Test-Path -LiteralPath $destination;$ownerExists=Test-Path -LiteralPath $ownerPath;$ownerIdentity=$null
  if($exists-ne$ownerExists){throw 'TEST_PACKAGE_VIEW_OWNERSHIP_UNKNOWN'}
  if($exists){
   $receipt=& $reader.ExportedCommands['Read-AiwReleaseJson'] $ownerPath
   & $reader {param($v)Assert-AiwReleaseFields $v @('schemaVersion','kind','owner','destinationRoot','packageRef','snapshot','evidenceRoot') 'package-view-owner'} $receipt
   $parts=@(if($receipt.owner-is[string]){$receipt.owner.Split('|')})
   if(($receipt.schemaVersion-isnot[int]-and$receipt.schemaVersion-isnot[long])-or$receipt.schemaVersion-ne1-or$receipt.kind-cne'OWNED_TEST_PACKAGE_VIEW'-or$parts.Count-ne2-or$parts[0]-cne$principal-or$receipt.destinationRoot-cne$destination){throw 'TEST_PACKAGE_VIEW_OWNER_DRIFT'}
   if((& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] $receipt.packageRef)-cne(& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] $packageRef)){throw 'TEST_PACKAGE_VIEW_PACKAGE_DRIFT'}
   Assert-TestPackageWorkersEnded $receipt.evidenceRoot
   $ownerIdentity=Get-AiwTestFileIdentity $ownerPath;$snapshot=Get-TestPackageViewSnapshot $destination
   if((& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] $snapshot)-cne(& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] $receipt.snapshot)){throw 'TEST_PACKAGE_VIEW_CONTENT_DRIFT'}
  }else{
   $null=& $reader.ExportedCommands['Expand-AiwReleasePackage'] $zip $destination
   $snapshot=Get-TestPackageViewSnapshot $destination
  }
  # Read-only handles exclude existing and future writers/deletes for every
  # bound file. Membership and directory changes are independently reobserved.
  foreach($file in $snapshot.Files){$path=Assert-AiwTestPath (Join-Path $destination $file.path);$handles.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))}
  if((& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] (Get-TestPackageViewSnapshot $destination))-cne(& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] $snapshot)){throw 'TEST_PACKAGE_VIEW_CONTENT_DRIFT'}
  $null=& $reader.ExportedCommands['Assert-AiwReleaseZipRuntime'] $zip $destination
  $facts=& $reader.ExportedCommands['Get-AiwReleasePackageFacts'] $destination
  if((Get-AiwTestFileIdentity $zip)-cne$packageRef.identity){throw 'TEST_PACKAGE_VIEW_PACKAGE_DRIFT'}
  $temporary=Assert-AiwTestPath ($ownerPath+'.writing-'+[guid]::NewGuid().ToString('N'))
  try{
   Write-AiwTestJson $temporary @{schemaVersion=1;kind='OWNED_TEST_PACKAGE_VIEW';owner=($principal+'|'+[string]$env:CODEX_THREAD_ID);destinationRoot=$destination;packageRef=$packageRef;snapshot=$snapshot;evidenceRoot=$evidence}
   if($exists-and(Get-AiwTestFileIdentity $ownerPath)-cne$ownerIdentity){throw 'TEST_PACKAGE_VIEW_OWNER_DRIFT'}
   [IO.File]::Move($temporary,$ownerPath,[bool]$exists)
  }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
  return [pscustomobject]@{Root=$destination;Facts=$facts;Snapshot=$snapshot;Lease=$lease;Handles=$handles;OwnerPath=$ownerPath}
 }catch{foreach($handle in $handles){$handle.Dispose()};$lease.Dispose();throw}
}
function Assert-AiwTestPackageView($View){
 $reader=@(Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru)[0]
 if((& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] (Get-TestPackageViewSnapshot $View.Root))-cne(& $reader.ExportedCommands['Get-AiwReleaseValueIdentity'] $View.Snapshot)){throw 'TEST_PACKAGE_VIEW_CONTENT_DRIFT'}
}
function Exit-AiwTestPackageView($View){
 try{foreach($handle in $View.Handles){$handle.Dispose()}}finally{$View.Lease.Dispose()}
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
Export-ModuleMember -Function Assert-AiwTestPath,Get-AiwTestFileIdentity,Write-AiwTestJson,Write-AiwTestPhase,Start-AiwTestProcess,Wait-AiwTestProcess,Stop-AiwTestProcess,Invoke-AiwTestProcess,Get-AiwTestRawProcessStates,Copy-AiwTestAllowlist,New-AiwTestRuntimeFixture,New-AiwTestMechanismFixture,New-AiwTestSourceView,Enter-AiwTestSourceView,Set-AiwTestFixtureQualification,Get-AiwTestFixtureSnapshot,Reset-AiwTestFixture,Enter-AiwTestPackageView,Assert-AiwTestPackageView,Exit-AiwTestPackageView
