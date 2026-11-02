[CmdletBinding()]
param([ValidateSet('Mechanism','Canonical','Registration','PackageIntegrity','AdoptionSmoke','ProofSchema')][string]$Group='Mechanism',[string]$PackagePath,[string]$ExtractedPackagePath,[string]$BuildCommandPath,[string]$V1ReaderPath,[switch]$WireStringOnly,[switch]$EntryPerformanceOnly,[switch]$DailyProcessOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($WireStringOnly-and$Group-cne'ProofSchema'){throw 'WIRE_STRING_ONLY_REQUIRES_PROOF_SCHEMA'}
if($EntryPerformanceOnly-and$Group-cne'Mechanism'){throw 'ENTRY_PERFORMANCE_ONLY_REQUIRES_MECHANISM'}
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
$evidenceReader=Import-Module (Join-Path $PSScriptRoot 'TestGroupEvidence.psm1') -PassThru
$releaseReader=Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1') -PassThru
Import-Module (Join-Path $PSScriptRoot '../scripts/StrictJsonInput.psm1')
$temp=Assert-AiwTestPath (Join-Path ([IO.Path]::GetTempPath()) ('rv-'+[guid]::NewGuid().ToString('N').Substring(0,8)))
$null=[IO.Directory]::CreateDirectory($temp);$passed=0
$raw=if($env:AIW_TEST_RAW_DIRECTORY){Join-Path $env:AIW_TEST_RAW_DIRECTORY ('release-samples-'+[guid]::NewGuid().ToString('N'))}else{Join-Path ([IO.Path]::GetTempPath()) ('aiw-release-raw-'+[guid]::NewGuid().ToString('N'))}
function Check([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Reject([scriptblock]$Body,[string]$Pattern,[string]$Name){$message='';try{$null=& $Body}catch{$message=$_.Exception.Message};if($message-notmatch$Pattern){throw ('WRONG_RELEASE_REJECTION|'+$Name+'|'+$message)};Check $true $Name}
function Clone($Value){return $Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100}
function Put([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function WriteFixtureJson([string]$Path,$Value){$full=Assert-AiwTestPath $Path;if(-not$full.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'RELEASE_MUTABLE_FIXTURE_SCOPE'};Put $full (($Value|ConvertTo-Json -Depth 100 -Compress)+"`n")}
function NativeTool([string]$Tool,[hashtable]$Parameters,[string]$Cwd=$temp,[string]$Setup='',[switch]$ReleaseDiagnostics){
 $id=[guid]::NewGuid().ToString('N');$callRoot=Join-Path $raw $id;$null=[IO.Directory]::CreateDirectory($callRoot)
 $inputPath=Join-Path $callRoot 'input.json';$wrapper=Join-Path $callRoot 'invoke.ps1';$errorPath=Join-Path $callRoot 'error.json'
 $diagnostics=Join-Path $callRoot 'qualification-phases.jsonl'
 Write-AiwTestJson $inputPath @{tool=$Tool;toolIdentity=(Get-AiwTestFileIdentity $Tool);parameters=$Parameters;stage=[IO.Path]::GetFileName($Tool);errorPath=$errorPath;setup=$Setup;releaseDiagnostics=[bool]$ReleaseDiagnostics;diagnosticsPath=$diagnostics}
 Put $wrapper ((@'
param([string]$InputPath)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
$v=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
try{
 if($v.releaseDiagnostics){
  $readerPath=Join-Path ([IO.Path]::GetDirectoryName($v.tool)) '../framework/versions/2.0.0/scripts/ReleaseValidation.psm1'
  $reader=@(Import-Module $readerPath -PassThru -ErrorAction Stop)[0]
  & $reader {param($path) $script:ReleaseDiagnostic={param($event) $row=@{utc=[DateTime]::UtcNow.ToString('o');stage=$event.stage;facts=$event.facts};[IO.File]::AppendAllText($path,($row|ConvertTo-Json -Depth 10 -Compress)+[char]10,[Text.UTF8Encoding]::new($false))}.GetNewClosure()} $v.diagnosticsPath
 }
 if($v.setup){& ([scriptblock]::Create($v.setup))}
 $p=$v.parameters;$LASTEXITCODE=0;$r=@(& $v.tool @p)
 if($LASTEXITCODE-ne0){$r|Write-Output;exit $LASTEXITCODE}
 if($r.Count-eq1){ConvertTo-Json -InputObject $r[0] -Depth 100 -Compress}else{ConvertTo-Json -InputObject $r -Depth 100 -Compress}
}catch{
 $original=$_;$causes=@()
 foreach($key in @('registrationError','cleanupError')){if($original.Exception.Data.Contains($key)){$cause=$original.Exception.Data[$key];$causes+=@{kind=$key;message=$cause.Exception.Message;position=$cause.InvocationInfo.PositionMessage;stack=$cause.ScriptStackTrace}}}
 $errorValue=@{stage=$v.stage;tool=$v.tool;parameters=$v.parameters;type=$original.Exception.GetType().FullName;message=$original.Exception.Message;fullyQualifiedErrorId=$original.FullyQualifiedErrorId;category=[string]$original.CategoryInfo;script=$original.InvocationInfo.ScriptName;line=$original.InvocationInfo.ScriptLineNumber;position=$original.InvocationInfo.PositionMessage;stack=$original.ScriptStackTrace;causes=$causes}
 try{[IO.File]::WriteAllText($v.errorPath,($errorValue|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))}catch{Write-Output ('FAILURE_EVIDENCE_INCOMPLETE|'+$_.Exception.Message);exit 3}
 Write-Output ($original.Exception.Message+'|'+$original.ScriptStackTrace);exit 2
}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$wrapper,'-InputPath',$inputPath) -WorkingDirectory $Cwd -EvidenceDirectory $callRoot
 $run|Add-Member CallEvidence ([pscustomobject]@{Root=$callRoot;InputPath=$inputPath;WrapperPath=$wrapper;ErrorPath=$errorPath;Stage=[IO.Path]::GetFileName($Tool);DiagnosticsPath=$diagnostics})
 Write-AiwTestJson (Join-Path $callRoot 'call-result.json') @{stage=$run.CallEvidence.Stage;input=@{path=$inputPath;identity=(Get-AiwTestFileIdentity $inputPath)};wrapper=@{path=$wrapper;identity=(Get-AiwTestFileIdentity $wrapper)};nativeResult=@{path=$run.ResultPath;identity=(Get-AiwTestFileIdentity $run.ResultPath)};error=$(if(Test-Path -LiteralPath $errorPath){@{path=$errorPath;identity=(Get-AiwTestFileIdentity $errorPath)}}else{$null});qualificationDiagnostics=$(if(Test-Path -LiteralPath $diagnostics){@{path=$diagnostics;identity=(Get-AiwTestFileIdentity $diagnostics)}}else{$null})}
 return $run
}
function PreservePositiveFailure($Run,[string]$Name,[string]$Zip='',[string]$InitialTask='',[string]$Consumer='',[string]$QualificationRoot='',$Failure=$null){
 $recordPath=Join-Path $Run.CallEvidence.Root 'unexpected-positive-failure.json'
 if([IO.File]::Exists($recordPath)){return}
  try{
   $artifacts=@();foreach($path in @($Zip,$InitialTask)+$(if($Consumer){@(Join-Path $Consumer '.ai-workspace/runtime/project-adoption/register/state.json')}else{@()})){
    if(-not$path){continue};$path=Assert-AiwTestPath $path
    if(Test-Path -LiteralPath $path -PathType Leaf){$identity=Get-AiwTestFileIdentity $path;$to=Join-Path $Run.CallEvidence.Root ('retained-'+[IO.Path]::GetFileName($path));[IO.File]::Copy($path,$to,$false);if((Get-AiwTestFileIdentity $to)-cne$identity){throw 'POSITIVE_FAILURE_COPY_DRIFT'};$artifacts+=@{originalPath=$path;retainedPath=$to;identity=$identity;state='RETAINED'}}else{$artifacts+=@{originalPath=$path;retainedPath=$null;identity=$null;state='ABSENT_AT_FAILURE'}}
   }
   if($QualificationRoot-and(-not$Zip-or-not[IO.File]::Exists($Zip))){
    $version=Assert-AiwTestPath (Join-Path $QualificationRoot 'framework/versions/2.0.0');if(-not$version.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'POSITIVE_FAILURE_FIXTURE_SCOPE'}
    $manifest=Read-AiwReleaseJson (Join-Path $version 'RELEASE_MANIFEST.json');$proofLocator=$manifest.validationProof.proofBundleRef.path;Assert-AiwReleaseLocator $proofLocator;$index=Read-AiwReleaseJson (Join-Path $version $proofLocator)
    $proofPaths=@('RELEASE_MANIFEST.json','tests/test-groups.json',$manifest.validationProof.proofBundleRef.path)+@($index.members.path)
    foreach($relative in $proofPaths){Assert-AiwReleaseLocator $relative;$from=Assert-AiwTestPath (Join-Path $version $relative);$identity=Get-AiwTestFileIdentity $from;$to=Join-Path $Run.CallEvidence.Root ('retained-source-proof/'+$relative);$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to));[IO.File]::Copy($from,$to,$false);if((Get-AiwTestFileIdentity $to)-cne$identity){throw 'POSITIVE_FAILURE_COPY_DRIFT'};$artifacts+=@{originalPath=$from;retainedPath=$to;identity=$identity;state='RETAINED'}}
   }
   $errorFacts=if($Failure){@{type=$Failure.Exception.GetType().FullName;message=$Failure.Exception.Message;fullyQualifiedErrorId=$Failure.FullyQualifiedErrorId;position=$Failure.InvocationInfo.PositionMessage;stack=$Failure.ScriptStackTrace}}else{$null}
   Write-AiwTestJson $recordPath @{stage=$Name;nativeResult=$Run.ResultPath;input=$Run.CallEvidence.InputPath;error=$Run.CallEvidence.ErrorPath;failure=$errorFacts;artifacts=$artifacts;packageMembers='Existing retained ZIP supplies exact proof/package members; if no ZIP exists, retain only current qualification manifest/definition and finite proof graph. Original invocation paths remain labels.'}
  }catch{throw ('FAILURE_EVIDENCE_INCOMPLETE|'+$Name+'|'+$_.Exception.Message)}
}
function RequirePositiveNative($Run,[bool]$Condition,[string]$Name,[string]$Zip='',[string]$InitialTask='',[string]$Consumer='',[string]$QualificationRoot=''){
 if(-not$Condition){
  PreservePositiveFailure $Run $Name -Zip $Zip -InitialTask $InitialTask -Consumer $Consumer -QualificationRoot $QualificationRoot
  Write-Output ('NATIVE_FAILURE|stage='+$Name+'|result='+$Run.ResultPath+'|input='+$Run.CallEvidence.InputPath+'|error='+$Run.CallEvidence.ErrorPath)
 }
 Check $Condition $Name
}
function NewNavigationReader([string]$Name){
 $root=Join-Path $temp $Name;$version=Join-Path $root 'framework/versions/2.0.0'
 $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
 Copy-AiwTestAllowlist $source $root @('scripts/ProjectAdoptionState.psm1','framework/versions/2.0.0/scripts/ReleaseValidation.psm1','framework/versions/2.0.0/scripts/StrictJsonInput.psm1','framework/versions/2.0.0/scripts/TestEvidenceValidation.psm1')
 return @(Import-Module (Join-Path $version 'scripts/ReleaseValidation.psm1') -PassThru -Scope Local)[0]
}
function NewLegacyNavigationToolchain($Current,[ValidateSet('2','3')][string]$Contract){
  $legacy=Clone $Current;$legacy.contractVersion=$Contract;$legacy.PSObject.Properties.Remove('navigation')
  $legacy|Add-Member routerCompatibility ([pscustomobject]@{schemaVersion=1;skillName='ai-workspace-router-v2';status='COMPATIBLE';canonicalSkillPath='skills/ai-workspace-router-v2/SKILL.md';versionContractPath='host/skills/ai-workspace-router-v2/SKILL.md';requiredOperations=@('LOAD_PLAN_RESOLVE','PROCESS_REQUIREMENTS_RESOLVE','WORKFLOW_ROUTE_RESOLVE');processCatalogSchemaVersion=$(if($Contract-ceq'3'){3}else{2});processCatalogVersion=$(if($Contract-ceq'3'){'4'}else{'3'});nativeRuleBodySource='MARKDOWN_EXACT_BLOCK';navigationContractVersion='2'})
 return $legacy
}
function NavigationRuntimeRegression{
 $reader=NewNavigationReader 'navigation-reader';$classify=$reader.ExportedCommands['Get-AiwReleaseRuntimeToolPaths']
 $version=Join-Path $temp 'navigation-target';$toolchain=Read-AiwReleaseJson (Join-Path $PSScriptRoot '../TOOLCHAIN.json');$definition=Read-AiwReleaseJson (Join-Path $PSScriptRoot 'test-groups.json')
 $tp=Join-Path $version 'TOOLCHAIN.json';$dp=Join-Path $version 'tests/test-groups.json'
 WriteFixtureJson $tp $toolchain;WriteFixtureJson $dp $definition
 $common=@('scripts/register-project.ps1','scripts/upgrade-project.ps1','scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/ProjectAdoptionTransaction.psm1','scripts/ProjectCorrectionLifecycle.psm1','scripts/MaintenanceOverlay.psm1','LICENSE')
 $internal=@('scripts/resolve-framework-maintenance-target.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1','scripts/check-framework-maintenance-authorization.ps1','scripts/invoke-framework-maintenance-safe-git.ps1','framework/maintenance-overlay/AGENTS.md','framework/maintenance-overlay/BOOTSTRAP.md','framework/maintenance-overlay/process-policy.json','framework/maintenance-overlay/PROJECT_CONFIG_SCHEMA.json','framework/maintenance-overlay/OVERLAY.json')
 function SamePaths($Actual,$Expected){(Get-AiwReleaseValueIdentity @($Actual|Sort-Object))-ceq(Get-AiwReleaseValueIdentity @($Expected|Sort-Object))}
 Check (SamePaths @(& $classify $version) $common) 'navigation3-runtime-exact-eight-without-source-skill'
 Check (SamePaths @(& $classify $version -Maintenance) @($common+$internal)) 'navigation3-maintenance-exact-seventeen'
 foreach($contract in @('2','3')){
  $legacy=NewLegacyNavigationToolchain $toolchain $contract
  WriteFixtureJson $tp $legacy;$legacyPaths=@($common)+@('skills/ai-workspace-router-v2/SKILL.md')
  Check (SamePaths @(& $classify $version) $legacyPaths) ('navigation2-contract-'+$contract+'-runtime-exact-nine')
  Check (SamePaths @(& $classify $version -Maintenance) @($legacyPaths+$internal)) ('navigation2-contract-'+$contract+'-maintenance-exact-eighteen')
 }
 foreach($fault in @('missing','malformed','mixed','kind','navigation','duplicate-source','duplicate-maintenance')){
  WriteFixtureJson $tp $toolchain;WriteFixtureJson $dp $definition;$pattern=''
  switch($fault){
   missing{[IO.File]::Delete($tp);$pattern='^INPUT_MISSING$'}
   malformed{Put $tp '{';$pattern='INPUT_JSON'}
   mixed{$bad=Clone $toolchain;$bad|Add-Member routerCompatibility $legacy.routerCompatibility;WriteFixtureJson $tp $bad;$pattern='^FRAMEWORK_TOOLCHAIN_FIELDS$'}
   kind{$bad=Clone $toolchain;$bad.navigation.kind='SKILL';WriteFixtureJson $tp $bad;$pattern='^FRAMEWORK_BOOTSTRAP_NAVIGATION_CONTRACT$'}
   navigation{$bad=Clone $toolchain;$bad.navigation.PSObject.Properties.Remove('bootstrapLocator');WriteFixtureJson $tp $bad;$pattern='^FRAMEWORK_BOOTSTRAP_NAVIGATION_FIELDS$'}
   'duplicate-source'{$bad=Clone $definition;$bad.rootAdoptionPaths+=@($bad.rootAdoptionPaths[0]);WriteFixtureJson $dp $bad;$pattern='^RELEASE_RUNTIME_TOOL_DEFINITION_MAPPING$'}
   'duplicate-maintenance'{$bad=Clone $definition;$bad.maintenancePaths+=@($bad.maintenancePaths[0]);WriteFixtureJson $dp $bad;$pattern='^RELEASE_MAINTENANCE_TOOL_DEFINITION_MAPPING$'}
  }
  Reject {& $classify $version} $pattern ('navigation-runtime-rejects-'+$fault)
 }
 WriteFixtureJson $tp $toolchain;WriteFixtureJson $dp $definition
 function Get-AiwNavigationContract {param($Toolchain) [pscustomobject]@{Kind='SKILL';CanonicalSkillPath='ambient-invalid-skill'}}
 Check ((Get-AiwNavigationContract $toolchain).CanonicalSkillPath-ceq'ambient-invalid-skill') 'navigation-ambient-conflict-is-live'
 Check (SamePaths @(& $classify $version) $common) 'navigation-reader-ignores-ambient-conflicting-resolver'
 $owner=& $reader {$script:ReleaseNavigationOwner};$original=$owner.ExportedCommands['Get-AiwNavigationContract'].ScriptBlock
 try{
  & $owner {Set-Item Function:script:Get-AiwNavigationContract {param($Toolchain) throw 'WRONG_NAVIGATION_IMPLEMENTATION'}}
  Reject {& $classify $version} '^RELEASE_READER_MODULE_OWNER$' 'navigation-reader-rejects-owned-function-replacement'
 }finally{& $owner {param($body) Set-Item Function:script:Get-AiwNavigationContract $body} $original}
 $path=$owner.Path;$bytes=[IO.File]::ReadAllBytes($path)
 try{[IO.File]::AppendAllText($path,"`n# owned helper drift");Reject {& $classify $version} '^RELEASE_READER_MODULE_DRIFT$' 'navigation-reader-rejects-retained-helper-byte-drift'}finally{[IO.File]::WriteAllBytes($path,$bytes)}
 Check (SamePaths @(& $classify $version) $common) 'navigation-reader-restored-original-helper-is-usable'
}
function NavigationColdQualificationRegression([string]$Root){
 $reader=NewNavigationReader 'navigation-cold-reader';$qualify=$reader.ExportedCommands['Get-AiwReleaseQualification'];$version=Join-Path $Root 'framework/versions/2.0.0'
 Check (& $reader {$null-eq$script:ReleaseNavigationOwner-and$script:ReleaseLoadedInputs.Count-eq3}) 'navigation-cold-reader-has-no-eager-root-dependency'
 & $reader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -Body {
  Check ((& $qualify -VersionRoot $version -RuntimeRoot $Root).State-ceq'SOURCE_QUALIFIED') 'navigation-cold-first-real-qualification-succeeds'
  $facts=& $reader {
   $helper=$script:ReleaseNavigationOwner.Path;$retained=@($script:ReleaseLoadedInputs|Where-Object path -CEQ $helper);$entries=@($script:ReleaseAction.Values)
   $snap=@($entries[0].snapshot.otherInputs|Where-Object path -CEQ $helper)
   [pscustomobject]@{helper=$helper;loadedCount=$retained.Count;snapshotCount=$snap.Count;identity=$retained[0].identity;snapshotIdentity=$(if($snap.Count){$snap[0].identity}else{''})}
  }
  Check ($facts.loadedCount-eq1-and$facts.snapshotCount-eq1-and$facts.identity-ceq$facts.snapshotIdentity-and$facts.identity-ceq(Get-AiwReleaseFileIdentity $facts.helper)) 'navigation-first-cold-snapshot-retains-exact-helper-identity'
  $bytes=[IO.File]::ReadAllBytes($facts.helper);$mtime=[IO.File]::GetLastWriteTimeUtc($facts.helper)
  try{[IO.File]::AppendAllText($facts.helper,"`n# cold retained drift");[IO.File]::SetLastWriteTimeUtc($facts.helper,$mtime);Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root} '^RELEASE_READER_MODULE_DRIFT$' 'navigation-first-cold-consumption-rejects-retained-helper-drift'}finally{[IO.File]::WriteAllBytes($facts.helper,$bytes);[IO.File]::SetLastWriteTimeUtc($facts.helper,$mtime)}
  Write-AiwTestJson (Join-Path $raw 'navigation-cold-snapshot.json') $facts
 }
}
function NavigationSourceRuntimeRegression([string]$Root){
 $qualify=$releaseReader.ExportedCommands['Get-AiwReleaseQualification'];$version=Join-Path $Root 'framework/versions/2.0.0'
 $q=& $qualify -VersionRoot $version -SourceRoot $Root
 $skill='skills/ai-workspace-router-v2/SKILL.md';$input=@($q.Proof.Inputs.inputs|Where-Object path -CEQ $skill)
 Check ($input.Count-eq1-and$input[0].logicalRole-ceq'SOURCE_ONLY_BUILD_OR_TEST_INPUT'-and$null-eq$input[0].distributionLocator-and$input[0].identity-ceq(Get-AiwReleaseFileIdentity (Join-Path $Root $skill))) 'navigation3-closure-keeps-exact-source-only-legacy-skill'
 $path=Join-Path $Root $skill;$bytes=[IO.File]::ReadAllBytes($path)
 try{
  [IO.File]::AppendAllText($path,'drift');Reject {& $qualify -VersionRoot $version -SourceRoot $Root} '^RELEASE_CURRENT_SOURCE_INPUT_DRIFT$' 'navigation3-source-rejects-legacy-skill-byte-drift'
  [IO.File]::Delete($path);Reject {& $qualify -VersionRoot $version -SourceRoot $Root} 'SKILL\.md' 'navigation3-source-rejects-missing-legacy-skill'
  Check ((& $qualify -VersionRoot $version -RuntimeRoot $Root).State-ceq'SOURCE_QUALIFIED') 'navigation3-runtime-succeeds-without-source-only-skill'
 }finally{[IO.File]::WriteAllBytes($path,$bytes)}
 foreach($spec in @(@{path='scripts/register-project.ps1';maintenance=$false},@{path='scripts/resolve-framework-maintenance-target.ps1';maintenance=$true},@{path='framework/maintenance-overlay/OVERLAY.json';maintenance=$true})){
  $maintenance=[bool]$spec.maintenance
  Check ((& $qualify -VersionRoot $version -RuntimeRoot $Root -Maintenance:$maintenance).State-ceq'SOURCE_QUALIFIED') ('navigation-runtime-required-positive-'+$spec.path)
  $path=Join-Path $Root $spec.path;$bytes=[IO.File]::ReadAllBytes($path)
  try{
   [IO.File]::AppendAllText($path,'drift');Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root -Maintenance:$maintenance} '^RELEASE_CURRENT_RUNTIME_TOOL_DRIFT$' ('navigation-runtime-rejects-required-drift-'+$spec.path)
   [IO.File]::Delete($path);Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root -Maintenance:$maintenance} ([regex]::Escape([IO.Path]::GetFileName($path))) ('navigation-runtime-rejects-required-missing-'+$spec.path)
  }finally{[IO.File]::WriteAllBytes($path,$bytes)}
 }
}
function ComposerColdRegression{
 # PRIVATE/PARTIAL: cold module consumption must not require obsolete live proof.
 $sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
 $view=New-AiwTestSourceView $sourceRoot (Join-Path $temp 'composer-pending-fixture') (Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json'))
 $coldVersion=Join-Path $view.Root 'framework/versions/2.0.0';$pendingPath=Join-Path $coldVersion 'RELEASE_MANIFEST.json'
 $pending=Read-AiwReleaseJson $pendingPath;$pending.sourceReview='PENDING';$pending.releaseIntegration='PENDING'
 $pending.completeSuite=[pscustomobject]@{status='PENDING';passed=0;total=0;payloadCanonical=$null;evidenceIdentity=$null}
 $pending.sourceReviewEvidence=[pscustomobject]@{status='PENDING';reviewer=$null;packageIdentity=$null;reviewedPayloadCanonical=$null;reviewedManifestIdentity=$null}
 WriteFixtureJson $pendingPath $pending
 & $releaseReader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -Body {
  Check ((Get-AiwReleaseQualification -VersionRoot $coldVersion -RuntimeRoot $view.Root -AllowPending).State-ceq'PENDING_CANDIDATE') 'qualification-context-retains-explicit-pending-strength'
  Reject {Get-AiwReleaseQualification -VersionRoot $coldVersion -RuntimeRoot $view.Root} '^RELEASE_STRING\|qualified-suite\|payloadCanonical$' 'qualification-context-pending-cannot-satisfy-qualified-request'
 }
 Write-AiwTestJson (Join-Path $raw 'composer-private-input.json') @{scope='PRIVATE_SYNTHETIC_PARTIAL';versionRoot=$coldVersion;manifest=@{path=$pendingPath;identity=(Get-AiwTestFileIdentity $pendingPath)};constructorClosure='Not consumed after this controlled private manifest mutation; no qualification proof/export';sourceQualification='NOT_PERFORMED'}
 $tool=Join-Path $temp 'composer-cold.ps1'
 Put $tool @'
param([string]$VersionDirectory,[bool]$PreloadReader)
$ErrorActionPreference='Stop'
if($PreloadReader){Import-Module (Join-Path $VersionDirectory 'scripts/ReleaseValidation.psm1')}
$composer=Import-Module (Join-Path $VersionDirectory 'scripts/ProcessRequirementComposition.psm1') -PassThru
$first=& $composer {param($v) Get-AiwCompositionReleaseFacts -VersionDirectory $v} $VersionDirectory
$second=& $composer {param($v) Get-AiwCompositionReleaseFacts -VersionDirectory $v} $VersionDirectory
[pscustomobject]@{same=($first.Facts.Canonical-ceq$second.Facts.Canonical-and$first.Facts.FileCount-eq$second.Facts.FileCount-and$first.Facts.TotalBytes-eq$second.Facts.TotalBytes);canonical=$first.Facts.Canonical;fileCount=$first.Facts.FileCount}
'@
 $ok=$true;foreach($preload in @($false,$true)){$run=NativeTool $tool @{VersionDirectory=$coldVersion;PreloadReader=$preload};if($run.Code-ne0){$ok=$false;Write-Output ('COMPOSER_COLD_FAILURE|'+$run.ResultPath)}else{$value=$run.StdoutText|ConvertFrom-Json;$ok=$ok-and$value.same-and$value.fileCount-gt0}}
 Check $ok 'composer-release-facts-repeat-consumption'
 foreach($locator in @('','../outside',(Join-Path $PSScriptRoot '../RELEASE_MANIFEST.json'))){Reject {& $releaseReader.ExportedCommands['Assert-AiwReleaseLocator'] $locator} '^RELEASE_LOCATOR$' 'relative-escape-rejected-before-filesystem-access'}
}
function CanonicalCase($Value,[string]$Expected,[string]$Name){
 $oracle=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Expected)))
 $canonical=& $releaseReader.ExportedCommands['Get-AiwReleaseCanonical'] $Value
 $identity=& $releaseReader.ExportedCommands['Get-AiwReleaseValueIdentity'] $Value
 $delegated=& $evidenceReader.ExportedCommands['Get-TestValueIdentity'] $Value
 Check ($canonical-ceq$Expected-and$identity-ceq$oracle-and$delegated-ceq$oracle) ('canonical-case-'+$Name)
}
function BuilderByteCaptureRegression{
 $builder=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))) 'scripts/build-user-package.ps1'
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($builder,[ref]$tokens,[ref]$errors)
 if(@($errors).Count){throw 'BUILDER_CAPTURE_PARSE'}
 $captures=@();$identities=@()
 foreach($loop in @($ast.FindAll({param($node) $node-is[Management.Automation.Language.ForEachStatementAst]-and$node.Variable.VariablePath.UserPath-ceq'mapping'-and$node.Condition.Extent.Text-ceq'$orderedMappings'},$true))){
  # Include the old outer assignment when present, so it remains detectable.
  $captures+=@($loop.Body.Statements|Where-Object{$_.Extent.Text-cmatch'^(?:\$bytes\s*=\s*)?if\s*\(\[bool\]\$mapping\.template\)'})
  $identities+=@($loop.Body.Statements|Where-Object{$_-is[Management.Automation.Language.AssignmentStatementAst]-and$_.Left-is[Management.Automation.Language.VariableExpressionAst]-and$_.Left.VariablePath.UserPath-ceq'identity'})
 }
 if($captures.Count-ne1-or$identities.Count-ne1){throw 'BUILDER_CAPTURE_POINT_REQUIRED'}
 $capture=[scriptblock]::Create($captures[0].Extent.Text+"`n"+$identities[0].Extent.Text)
 # Own the empty input independently of the deliberate cold-runner failure.
 $empty=Join-Path $temp 'capture-empty.bin';Put $empty ''
 if([IO.File]::ReadAllBytes($empty).Length-ne0){throw ('BUILDER_EMPTY_INPUT_REQUIRED|'+(Get-AiwTestFileIdentity $empty))}
 $one=Join-Path $temp 'capture-one.bin';$two=Join-Path $temp 'capture-two.bin';Put $one 'A';Put $two 'AB'
 $mapping=@{template=$false};$sourceRelative='validation-evidence/prepackage/owned-byte-case.raw'
 foreach($case in @(
  @{name='empty';path=$empty;expected='0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'},
  @{name='singleton';path=$one;expected='1|559AEAD08264D5795D3909718CDD05ABD49572E84FE55590EEF31A88A08FDFFD'},
  @{name='ordinary';path=$two;expected='2|38164FBD17603D73F696B8B4D72664D735BB6A7C88577687FD2AE33FD6964153'}
 )){
  $sourcePath=$case.path;$inputIdentity=Get-AiwTestFileIdentity $sourcePath;$bytes=$null;$identity=$null
  try{. $capture}finally{
   Write-AiwTestJson (Join-Path $raw ('builder-capture-'+$case.name+'.json')) @{input=@{path=$sourcePath;identity=$inputIdentity};expected=$case.expected;capturedType=$(if($null-eq$bytes){'NULL'}else{$bytes.GetType().FullName});capturedIdentity=$identity}
  }
  Check ($bytes-is[byte[]]-and$identity-ceq$case.expected) ('builder-capture-preserves-'+$case.name+'-byte-array')
 }
 $sourcePath=Join-Path $temp 'capture-template.txt';$sourceRelative='template.txt';$mapping.template=$true
 $FrameworkVersion='2.0.0';$distributionId='2.0.0-snapshot.1';$distributionNotice='私有测试'
 Put $sourcePath '{{FRAMEWORK_VERSION}}|{{DISTRIBUTION_ID}}|{{DISTRIBUTION_NOTICE}}'
 $expected=[Text.Encoding]::UTF8.GetBytes('2.0.0|2.0.0-snapshot.1|私有测试')
 $expectedIdentity=$expected.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expected))
 $bytes=$null;$identity=$null;. $capture
 Check ($bytes-is[byte[]]-and$identity-ceq$expectedIdentity) 'builder-capture-preserves-template-utf8-substitutions'
 Put $sourcePath '{{UNRESOLVED}}'
 Reject {. $capture} '^PACKAGE_TEMPLATE_UNRESOLVED\|template\.txt$' 'builder-capture-rejects-unresolved-template'
 $mapping.template=$false;$sourceRelative='framework/PROJECT_ADOPTION.md'
 Put $sourcePath '采用 versions/1.16.0/ 与 versions/1.16.0/README.md'
 $expected=[Text.Encoding]::UTF8.GetBytes('采用 versions/2.0.0/ 与 versions/2.0.0/README.md')
 $expectedIdentity=$expected.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expected))
 $bytes=$null;$identity=$null;. $capture
 Check ($bytes-is[byte[]]-and$identity-ceq$expectedIdentity) 'builder-capture-preserves-adoption-utf8-rewrite'
}
function PackageCanonicalRegression{
 $root=Join-Path $temp 'package-canonical';Put (Join-Path $root 'AGENTS.md') 'A';Put (Join-Path $root 'README.md') 'AB';Put (Join-Path $root 'framework/a') ''
 # Independent literal identities and rows use the existing builder's mixed-case order.
 $files=@(
  @{path='AGENTS.md';identity='1|559AEAD08264D5795D3909718CDD05ABD49572E84FE55590EEF31A88A08FDFFD'},
  @{path='framework/a';identity='0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'},
  @{path='README.md';identity='2|38164FBD17603D73F696B8B4D72664D735BB6A7C88577687FD2AE33FD6964153'}
 )
 $literalRows=@(
  'AGENTS.md=1|559AEAD08264D5795D3909718CDD05ABD49572E84FE55590EEF31A88A08FDFFD',
  'framework/a=0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
  'README.md=2|38164FBD17603D73F696B8B4D72664D735BB6A7C88577687FD2AE33FD6964153'
 )
 $expected='56B551CD22ADEDB7EE2169C41382DF53E02571F76AECCDF8AF62A133191DF4C2'
 $oracle=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($literalRows-join"`n")+"`n")))
 if($oracle-cne$expected){throw 'PACKAGE_CANONICAL_LITERAL_ORACLE'}
 $manifestPath=Join-Path $root 'PACKAGE_MANIFEST.json'
 $sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
 $adoptionReader=Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionState.psm1') -PassThru
 foreach($schema in @(1,2)){
  $manifest=[ordered]@{schemaVersion=$schema;frameworkVersion='2.0.0';provisional=$true;canonical=$expected;files=$files}
  if($schema-eq2){$manifest.distributionId='2.0.0-snapshot.1'}
  WriteFixtureJson $manifestPath $manifest
  $facts=& $releaseReader.ExportedCommands['Get-AiwReleasePackageFacts'] -PackageRoot $root
  Check ($facts.Canonical-ceq$expected-and$facts.Members.Count-eq3) ('package-canonical-schema'+$schema+'-manifest-order')
  if($schema-eq2){
   $binding=& $adoptionReader.ExportedCommands['Get-AiwDistributionBinding'] -FrameworkRoot $root -FrameworkVersion '2.0.0' -Required
   Check ($binding.contentIdentity-ceq$expected) 'package-canonical-schema2-adoption-parity'
  }
  # Only canonical changes; valid members and their order stay identical.
  $manifest.canonical='EB4F4AE901682A3C56A9BBDADEC8FF5D44985FF6A59C2321CF6BF3444EFE6245'
  WriteFixtureJson $manifestPath $manifest
  Reject {& $releaseReader.ExportedCommands['Get-AiwReleasePackageFacts'] -PackageRoot $root} '^RELEASE_PACKAGE_SET_OR_CANONICAL$' ('package-canonical-schema'+$schema+'-rejects-ordinal-only-hash')
 }
}
function PostbuildOutputRegression{
 # PRIVATE/SYNTHETIC/PARTIAL: exercise the real output consumers, not release qualification.
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$tokens,[ref]$errors)
 if(@($errors).Count){throw 'OUTPUT_CONTRACT_SOURCE_PARSE'}
 $functions=@{};foreach($name in @('Check','Put','NativeTool','PreservePositiveFailure','RequirePositiveNative','AssertPackage','AdoptionSmoke')){
  $nodes=@($ast.FindAll({param($n) $n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
  if($nodes.Count-ne1){throw ('OUTPUT_CONTRACT_FUNCTION_UNIQUE|'+$name)};$functions[$name]=$nodes[0].Extent.Text
 }
 $dispatch=@($ast.EndBlock.Statements|Where-Object{$_-is[Management.Automation.Language.TryStatementAst]})
 if($dispatch.Count-ne1){throw 'OUTPUT_CONTRACT_DISPATCH_UNIQUE'}
 $clauses=@($dispatch[0].Body.FindAll({param($n) $n-is[Management.Automation.Language.IfStatementAst]},$false)|ForEach-Object{$_.Clauses}|Where-Object{$_.Item1.Extent.Text-ceq"`$Group-cnotin@('Mechanism','Registration')"})
 $calls=@($ast.FindAll({param($n) $n-is[Management.Automation.Language.CommandAst]-and$n.GetCommandName()-ceq'AssertPackage'},$true)|Where-Object{$_.Extent.Text-ceq'AssertPackage $packageRoot $zip'})
 if($clauses.Count-ne1-or$calls.Count-ne1){throw 'OUTPUT_CONTRACT_REAL_CALL_UNIQUE'}
 # Keep the full parent statement, including an old AssignmentStatementAst.
 $mechanism=$calls[0];while($mechanism.Parent-isnot[Management.Automation.Language.StatementBlockAst]){$mechanism=$mechanism.Parent;if(-not$mechanism){throw 'OUTPUT_CONTRACT_CALL_PARENT'}}
 $post='if('+$clauses[0].Item1.Extent.Text+')'+$clauses[0].Item2.Extent.Text
 $summary=$dispatch[0].Body.Statements[-1].Extent.Text
 if($summary-cnotmatch"^Write-Output.*RESULT\|"){throw 'OUTPUT_CONTRACT_REAL_COMPLETION_REQUIRED'}
 $finally=$dispatch[0].Finally.Extent.Text
 $evidence=Join-Path $raw 'output-contract';$null=[IO.Directory]::CreateDirectory($evidence)
 $definition=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
 $parts=@{functions=$functions;postbuild=$post;mechanism=$mechanism.Extent.Text;summary=$summary;finally=$finally;paramBlock=$ast.ParamBlock.Extent.Text}
 Write-AiwTestJson (Join-Path $evidence 'extracted-consumers.json') @{kind='PRIVATE_SYNTHETIC_PARTIAL';source=@{path=$PSCommandPath;identity=(Get-AiwTestFileIdentity $PSCommandPath)};parts=$parts;mockBoundary='Only expensive lower package/qualification facts and registrar/upgrade tools. Actual Check, AssertPackage, AdoptionSmoke, NativeTool, RequirePositiveNative, dispatch, completion and finally retained.'}
 $template=@'
__PARAM__
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module '__HARNESS__'
Import-Module '__EVIDENCE__'
$guardReader=Import-Module '__READER__' -PassThru
$config=Get-Content -LiteralPath '__CONFIG__' -Raw|ConvertFrom-Json
$temp=$config.temp;$raw=$config.raw;$passed=0;$script:factsCalls=0;$script:qualificationCalls=0;$script:zipCalls=0
$null=[IO.Directory]::CreateDirectory($temp)
__FUNCTIONS__
function Read-AiwReleaseJson([string]$Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
function Get-AiwReleasePackageFacts([string]$PackageRoot){$script:factsCalls++;[pscustomobject]@{Canonical=$(if($config.fault-ceq'first-check'-and$script:factsCalls-eq2){''}else{'PRIVATE-FACTS'})}}
function Get-AiwReleaseQualification([string]$VersionRoot,[string]$RuntimeRoot){
 $script:qualificationCalls++
 if($script:qualificationCalls-eq1){$script:consumptionSnapshot=@{versionRoot=$VersionRoot;versionCanonical=(Get-AiwReleaseMemberFacts (Get-AiwReleaseTreeMembers $VersionRoot)).Canonical;otherInputs=@();packages=@()}}
 if($config.fault-ceq'qualification-throw'-and$script:qualificationCalls-eq2){throw 'PRIVATE_QUALIFICATION_THROW'}
 if($config.fault-ceq'second-consumption-drift'-and$script:qualificationCalls-eq2){[IO.File]::AppendAllText((Join-Path $VersionRoot 'VERSION.json'),' ')}
 & $guardReader {param($snapshot) Assert-AiwReleaseConsumptionSnapshot $snapshot} $script:consumptionSnapshot
 [pscustomobject]@{State='SOURCE_QUALIFIED';PrivateObject='MUST_NOT_LEAK'}
}
function Assert-AiwReleaseZipRuntime($Zip,$Root){if($config.fault-ceq'zip-throw'){throw 'PRIVATE_ZIP_THROW'};[pscustomobject]@{Private=$true}}
function Assert-AiwReleaseBuildEvidence($Command,$Zip,$Facts,$Qualification){[pscustomobject]@{Private=$true}}
function Get-AiwReleaseFileIdentity($Path){$script:zipCalls++;if($config.fault-ceq'frozen-check'-and$script:zipCalls-eq2){return 'PRIVATE-DRIFT'};Get-AiwTestFileIdentity $Path}
$packageRoot=Join-Path $temp 'package';$zip=Join-Path $temp 'private.zip';$PackagePath=$zip;$ExtractedPackagePath=$packageRoot;$BuildCommandPath=Join-Path $temp 'private-build.json';$script:smokeZip=$zip
Put $zip 'PRIVATE SYNTHETIC ZIP LABEL';Put $BuildCommandPath '{}'
Put (Join-Path $packageRoot 'framework/versions/2.0.0/VERSION.json') '{"lifecycle":"STABLE"}'
$toolParams='param([string]$ProjectId,[string]$DisplayName,[string]$RepositoryPath,[string]$FrameworkVersion,[string]$ToVersion,[string]$ControllerId,[string]$WorkspaceRoot,[bool]$Apply)'
$register=if($config.fault-ceq'registration-native'){'throw "PRIVATE_REGISTRATION_NATIVE"'}else{'$null=[IO.Directory]::CreateDirectory((Join-Path $RepositoryPath ".ai-workspace"));[IO.File]::WriteAllText((Join-Path $RepositoryPath ".ai-workspace/project.json"),"{}");"PRIVATE_REGISTERED"'}
$upgrade=if($config.fault-ceq'upgrade-native'){'throw "PRIVATE_UPGRADE_NATIVE"'}else{'"ALREADY_UPGRADED"'}
Put (Join-Path $packageRoot 'scripts/register-project.ps1') ($toolParams+"`n"+$register)
Put (Join-Path $packageRoot 'scripts/upgrade-project.ps1') ($toolParams+"`n"+$upgrade)
try{
__BODY__
__SUMMARY__
}finally __FINALLY__
'@
 $results=@()
 foreach($case in @(
  @{name='package-positive';group='PackageIntegrity';fault='none';mutation='none';expect=@('actual-zip-members-match-package-manifest','actual-source-qualification-is-preserved','postbuild-leaves-original-zip-and-runtime-bytes-frozen')},
  @{name='mechanism-positive';group='Mechanism';fault='none';mutation='none';expect=@('actual-zip-members-match-package-manifest','actual-source-qualification-is-preserved')},
  @{name='adoption-positive';group='AdoptionSmoke';fault='none';mutation='none';expect=@('actual-package-registration-smoke','actual-package-upgrade-smoke','postbuild-leaves-original-zip-and-runtime-bytes-frozen')},
  @{name='first-check';group='PackageIntegrity';fault='first-check';mutation='none';expect=@();error='ASSERT_FAIL\|actual-zip-members-match-package-manifest'},
  @{name='second-check';group='PackageIntegrity';fault='second-consumption-drift';mutation='none';expect=@('actual-zip-members-match-package-manifest');error='RELEASE_CONSUMPTION_DRIFT'},
  @{name='zip-throw';group='PackageIntegrity';fault='zip-throw';mutation='none';expect=@();error='PRIVATE_ZIP_THROW'},
  @{name='qualification-throw';group='PackageIntegrity';fault='qualification-throw';mutation='none';expect=@('actual-zip-members-match-package-manifest');error='PRIVATE_QUALIFICATION_THROW'},
  @{name='frozen-check';group='PackageIntegrity';fault='frozen-check';mutation='none';expect=@('actual-zip-members-match-package-manifest','actual-source-qualification-is-preserved');error='ASSERT_FAIL\|postbuild-leaves-original-zip-and-runtime-bytes-frozen'},
  @{name='registration-native';group='AdoptionSmoke';fault='registration-native';mutation='none';expect=@();error='ASSERT_FAIL\|actual-package-registration-smoke'},
  @{name='upgrade-native';group='AdoptionSmoke';fault='upgrade-native';mutation='none';expect=@('actual-package-registration-smoke');error='ASSERT_FAIL\|actual-package-upgrade-smoke'},
  @{name='old-postbuild-capture';group='PackageIntegrity';fault='none';mutation='capture';expect=@('postbuild-leaves-original-zip-and-runtime-bytes-frozen')},
  @{name='old-mechanism-capture';group='Mechanism';fault='none';mutation='capture';expect=@()},
  @{name='old-postbuild-return';group='PackageIntegrity';fault='none';mutation='return';expect=@('actual-zip-members-match-package-manifest','actual-source-qualification-is-preserved','postbuild-leaves-original-zip-and-runtime-bytes-frozen')},
  @{name='old-mechanism-return';group='Mechanism';fault='none';mutation='return';expect=@('actual-zip-members-match-package-manifest','actual-source-qualification-is-preserved')},
  @{name='duplicate-case';group='PackageIntegrity';fault='none';mutation='duplicate';expect=@('actual-zip-members-match-package-manifest','actual-source-qualification-is-preserved','postbuild-leaves-original-zip-and-runtime-bytes-frozen','actual-zip-members-match-package-manifest')},
  @{name='wrong-group-completion';group='PackageIntegrity';fault='none';mutation='completion';expect=@('actual-zip-members-match-package-manifest','actual-source-qualification-is-preserved','postbuild-leaves-original-zip-and-runtime-bytes-frozen')}
 )){
  $caseRoot=Join-Path $evidence $case.name;$null=[IO.Directory]::CreateDirectory($caseRoot)
  $childTemp=Assert-AiwTestPath (Join-Path ([IO.Path]::GetTempPath()) ('rv-'+[guid]::NewGuid().ToString('N').Substring(0,8)))
  $configPath=Join-Path $caseRoot 'config.json';Write-AiwTestJson $configPath @{temp=$childTemp;raw=(Join-Path $caseRoot 'native-calls');fault=$case.fault;scope='PRIVATE_SYNTHETIC_PARTIAL'}
  $body=if($case.group-ceq'Mechanism'){$mechanism.Extent.Text}else{$post};$fn=$functions.Values -join"`n";$end=$summary
  if($case.mutation-ceq'capture'){
   $original=if($case.group-ceq'Mechanism'){'AssertPackage $packageRoot $zip'}else{'AssertPackage $ExtractedPackagePath $PackagePath'}
   if([regex]::Matches($body,[regex]::Escape($original)).Count-ne1){throw 'OUTPUT_CONTRACT_MUTATION_TARGET'};$body=$body.Replace($original,'$null='+$original)
  }
  if($case.mutation-ceq'return'){$old=$functions.AssertPackage;$close=$old.LastIndexOf('}');$fn=$fn.Replace($old,$old.Insert($close," return `$qualified`n"))}
  if($case.mutation-ceq'duplicate'){$body+="`nCheck `$true 'actual-zip-members-match-package-manifest'"}
  if($case.mutation-ceq'completion'){$end=$summary.Replace("+`$Group","+'WrongGroup'")}
  $child=$template.Replace('__PARAM__',$parts.paramBlock).Replace('__HARNESS__',(Join-Path $PSScriptRoot 'TestHarness.psm1').Replace("'","''")).Replace('__EVIDENCE__',(Join-Path $PSScriptRoot 'TestGroupEvidence.psm1').Replace("'","''")).Replace('__READER__',(Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1').Replace("'","''")).Replace('__CONFIG__',$configPath.Replace("'","''")).Replace('__FUNCTIONS__',$fn).Replace('__BODY__',$body).Replace('__SUMMARY__',$end).Replace('__FINALLY__',$finally)
  $scriptPath=Join-Path $caseRoot 'consumer.ps1';Put $scriptPath $child
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$scriptPath,'-Group',$case.group) -WorkingDirectory $caseRoot -EvidenceDirectory (Join-Path $caseRoot 'raw')
  $id=if($case.group-ceq'AdoptionSmoke'){'postbuild.adoption-smoke'}else{'postbuild.package-integrity'}
  $groupDef=@($definition.groups|Where-Object id -CEQ $id)[0]
  $observed=@(Get-AiwTestObservedCases $run.Output $id);$lines=@($run.StdoutText-split'\r?\n'|Where-Object{$_});$terminal=@($lines|Where-Object{$_-cmatch'^RESULT\|'})
  $clean=-not(Test-Path -LiteralPath $childTemp);$rejected='NOT_APPLICABLE';$privateRecord=$null
  if(-not$case.ContainsKey('error')){
   $command=$run.Record.command;$facts=@{scope='PRIVATE_SYNTHETIC_PARTIAL';root=$caseRoot;commandArguments=@($command.arguments);environment=@{tools=@(@{name='pwsh';path=$command.executable;identity=$command.executableIdentity;fileVersion=$command.executableVersion})};validatorIdentity=(Get-AiwTestFileIdentity (Join-Path $PSScriptRoot 'TestGroupEvidence.psm1'))}
   $snapshot=[pscustomobject]@{identity=(Get-TestValueIdentity $facts);facts=$facts}
   # Mechanism needs only its actual call's two checks, not the full Mechanism group.
   if($case.group-ceq'Mechanism'){$groupDef=Clone $groupDef;$groupDef.completionPattern='^RESULT\|[0-9]+/[0-9]+ passed\|scope=release-validation\|group=Mechanism$'}
   $privateRecord=Join-Path $caseRoot 'private-executed.json'
   $record=Complete-AiwTestGroupEvidence $privateRecord $groupDef $snapshot $snapshot $run @{status=$(if($clean){'CLEAN'}else{'DIRTY'});root=$childTemp;entries=@();workers=@()}
   try{$null=Assert-AiwTestGroupEvidence $record $groupDef $snapshot;$rejected='NONE'}catch{$rejected=$_.Exception.Message}
  }
  $observedNames=@($observed|ForEach-Object{$_.name});$namesMatch=(($observedNames-join',')-ceq($case.expect-join','))
  $success=$run.Code-eq0-and$terminal.Count-eq1-and$terminal[0]-ceq('RESULT|'+$observed.Count+'/'+$observed.Count+' passed|scope=release-validation|group='+$case.group)-and$lines.Count-eq($observed.Count+1)-and$observed.Count-eq@($observedNames|Select-Object -Unique).Count-and-not$run.StderrText-and$rejected-ceq'NONE'
  $ok=if($case.ContainsKey('error')){$run.Code-ne0-and$terminal.Count-eq0-and$run.Text-cmatch$case.error}else{if($case.mutation-ceq'none'){$success}else{-not$success-and$run.Code-eq0}}
  if($case.mutation-ceq'capture'){$ok=$ok-and$rejected-cmatch'^(TEST_REQUIRED_CASE_MISSING\||TEST_CASE_RAW_MISMATCH$)'}
  if($case.mutation-ceq'completion'){$ok=$ok-and$rejected-ceq'TEST_RECORD_FAILED_PARTIAL_OR_INPUT_DRIFT'}
  if($case.name-cin@('registration-native','upgrade-native')){$retained=@(Get-ChildItem -LiteralPath (Join-Path $caseRoot 'native-calls') -Filter 'unexpected-positive-failure.json' -Recurse);$ok=$ok-and$retained.Count-eq1}
  $row=@{name=$case.name;group=$case.group;scope='PRIVATE_SYNTHETIC_PARTIAL';mutation=$case.mutation;fault=$case.fault;sourceParts=Join-Path $evidence 'extracted-consumers.json';native=@{path=$run.ResultPath;identity=(Get-AiwTestFileIdentity $run.ResultPath)};stdout=$run.Record.stdout;stderr=$run.Record.stderr;observedCases=$observed;completion=$terminal;validatorRejection=$rejected;privateRecord=$privateRecord;cleanup=$(if($clean){'CLEAN'}else{'DIRTY'});assertion=($ok-and$namesMatch-and$clean)}
  Write-AiwTestJson (Join-Path $caseRoot 'observation.json') $row;$results+=$row
  Check $row.assertion ('output-contract-'+$case.name)
 }
 Write-AiwTestJson (Join-Path $evidence 'private-summary.json') @{scope='PRIVATE_SYNTHETIC_PARTIAL';outcome='PASS';results=$results;formalQualification='NOT_PERFORMED';candidateSmokeBranch='STABLE private branch only; CANDIDATE preflight retained in existing formal tests'}
}

function QualificationContextRegression([string]$Root){
 # Scope and calls must share the retained reader after other fixture imports.
 $qualify=$releaseReader.ExportedCommands['Get-AiwReleaseQualification']
 $ambientReaderPath=(Get-Command Get-AiwReleaseQualification).Module.Path
 $version=Join-Path $Root 'framework/versions/2.0.0';$manifest=Read-AiwReleaseJson (Join-Path $version 'RELEASE_MANIFEST.json')
 $modes=& $releaseReader {
  param($v,$proof) $bundle=Get-AiwReleaseBundle $v $proof;$id=@($bundle.Index.members|Where-Object kind -CEQ GROUP_RECORD)[0].id
  $default=Read-AiwReleaseBundleMember $bundle $id GROUP_RECORD;$current=Read-AiwReleaseBundleMember $bundle $id GROUP_RECORD -CurrentCoverage
  $again=Read-AiwReleaseBundleMember $bundle $id GROUP_RECORD
  [pscustomobject]@{count=$bundle.Parsed.Count;defaultDate=($default.startedUtc-is[datetime]);wireString=($current.startedUtc-is[string]);same=[object]::ReferenceEquals($default,$again)}
 } $version $manifest.validationProof
 Check ($modes.count-eq2-and$modes.defaultDate-and$modes.wireString-and$modes.same) 'qualification-member-memo-keeps-exact-parse-modes'
 $events=[Collections.Generic.List[object]]::new();$sink={param($e) $events.Add($e)}.GetNewClosure()
 & $releaseReader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {
  $one=& $qualify -VersionRoot $version -RuntimeRoot $Root;$expected=$one.Facts.Canonical
  $one.Facts.Canonical='POLLUTED';$one.Manifest.sourceReview='POLLUTED';$one.Proof.Inputs.inputs[0].identity='POLLUTED'
  $two=& $qualify -VersionRoot $version -RuntimeRoot $Root
  Write-AiwTestJson (Join-Path $raw 'qualification-context-isolation.json') @{readerPath=$qualify.Module.Path;scopeReaderPath=$releaseReader.Path;ambientReaderPath=$ambientReaderPath;canonicalMatches=($two.Facts.Canonical-ceq$expected);review=$two.Manifest.sourceReview;inputIdentity=$two.Proof.Inputs.inputs[0].identity;deepReaderCount=@($events|Where-Object stage -CEQ 'deep-reader-start').Count;events=@($events.ToArray())}
  Check ($two.Facts.Canonical-ceq$expected-and$two.Manifest.sourceReview-ceq'APPROVED'-and$two.Proof.Inputs.inputs[0].identity-cne'POLLUTED'-and@($events|Where-Object stage -CEQ 'deep-reader-start').Count-eq1) 'qualification-context-isolates-returned-object-graphs'
  $proofMember=@((Read-AiwReleaseJson (Join-Path $version $manifest.validationProof.proofBundleRef.path)).members|Where-Object kind -CEQ GROUP_RECORD)[0].path
  foreach($relative in @('CHANGELOG.md','RECOVERY_CORE.md','RELEASE_MANIFEST.json',$proofMember)){
   $null=& $qualify -VersionRoot $version -RuntimeRoot $Root
   $path=Join-Path $version $relative;$bytes=[IO.File]::ReadAllBytes($path);$mtime=[IO.File]::GetLastWriteTimeUtc($path);$changed=[byte[]]$bytes.Clone();$changed[0]=$changed[0]-bxor1
   try{[IO.File]::WriteAllBytes($path,$changed);[IO.File]::SetLastWriteTimeUtc($path,$mtime);Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root} '^RELEASE_CONSUMPTION_DRIFT$' ('qualification-context-rejects-restored-mtime-'+[IO.Path]::GetFileName($relative))}
   finally{[IO.File]::WriteAllBytes($path,$bytes);[IO.File]::SetLastWriteTimeUtc($path,$mtime)}
  }
  $null=& $qualify -VersionRoot $version -RuntimeRoot $Root
  $tool=Join-Path $Root 'scripts/register-project.ps1';$bytes=[IO.File]::ReadAllBytes($tool);$mtime=[IO.File]::GetLastWriteTimeUtc($tool);$changed=[byte[]]$bytes.Clone();$changed[0]=$changed[0]-bxor1
  try{[IO.File]::WriteAllBytes($tool,$changed);[IO.File]::SetLastWriteTimeUtc($tool,$mtime);Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root} '^RELEASE_CONSUMPTION_DRIFT$' 'qualification-context-rejects-runtime-tool-drift'}finally{[IO.File]::WriteAllBytes($tool,$bytes);[IO.File]::SetLastWriteTimeUtc($tool,$mtime)}
  $null=& $qualify -VersionRoot $version -RuntimeRoot $Root
  $extra=Join-Path $version 'unlisted-context-file.txt'
  try{Put $extra 'extra';Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root} '^RELEASE_CONSUMPTION_DRIFT$' 'qualification-context-rejects-member-addition'}finally{Remove-Item -LiteralPath $extra}
  $null=& $qualify -VersionRoot $version -RuntimeRoot $Root
  $removed=Join-Path $version 'CHANGELOG.md';$held=Join-Path $temp 'held-context-changelog';[IO.File]::Move($removed,$held)
  try{Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root} '^RELEASE_CONSUMPTION_DRIFT$' 'qualification-context-rejects-member-deletion'}finally{[IO.File]::Move($held,$removed)}
  $null=& $qualify -VersionRoot $version -RuntimeRoot $Root
  $target=Join-Path $temp 'context-reparse-target';$null=[IO.Directory]::CreateDirectory($target);$link=Join-Path $version 'context-junction'
  try{$null=New-Item -ItemType Junction -Path $link -Target $target;Reject {& $qualify -VersionRoot $version -RuntimeRoot $Root} '^RELEASE_REPARSE$' 'qualification-context-rejects-reparse-addition'}finally{if(Test-Path -LiteralPath $link){Remove-Item -LiteralPath $link}}
  Check ((& $qualify -VersionRoot $version -RuntimeRoot $Root).State-ceq'SOURCE_QUALIFIED') 'qualification-failure-does-not-cache-success-or-poison-later-call'
  $count=@($events|Where-Object stage -CEQ 'deep-reader-start').Count
  $null=& $qualify -VersionRoot $version -SourceRoot $Root
  Check (@($events|Where-Object stage -CEQ 'deep-reader-start').Count-eq($count+1)) 'qualification-context-separates-source-and-runtime-modes'
  $count=@($events|Where-Object stage -CEQ 'deep-reader-start').Count
  $null=& $qualify -VersionRoot $version -RuntimeRoot $Root -Maintenance
  Check (@($events|Where-Object stage -CEQ 'deep-reader-start').Count-eq($count+1)) 'qualification-context-separates-maintenance-mode'
 }
 $count=@($events|Where-Object stage -CEQ 'deep-reader-start').Count
 & $releaseReader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {$null=& $qualify -VersionRoot $version -RuntimeRoot $Root}
 Check (@($events|Where-Object stage -CEQ 'deep-reader-start').Count-eq($count+1)) 'qualification-context-is-discarded-between-actions'
 $count=@($events|Where-Object stage -CEQ 'deep-reader-start').Count
 try{& $releaseReader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {$null=& $qualify -VersionRoot $version -RuntimeRoot $Root;throw 'CONTROLLED_ACTION_EXCEPTION'}}catch{if($_.Exception.Message-cne'CONTROLLED_ACTION_EXCEPTION'){throw}}
 & $releaseReader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {$null=& $qualify -VersionRoot $version -RuntimeRoot $Root}
 Check (@($events|Where-Object stage -CEQ 'deep-reader-start').Count-eq($count+2)) 'qualification-context-is-discarded-after-action-exception'
 $count=@($events|Where-Object stage -CEQ 'deep-reader-start').Count
 & $releaseReader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {
  $null=& $qualify -VersionRoot $version -RuntimeRoot $Root
  $reloaded=@(Import-Module $releaseReader.Path -Force -PassThru)[0]
  & $reloaded.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {$null=& $reloaded.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $version -RuntimeRoot $Root}
 }
 Check (@($events|Where-Object stage -CEQ 'deep-reader-start').Count-eq($count+2)) 'qualification-module-reload-performs-new-full-consumption'
 Write-AiwTestJson (Join-Path $raw 'qualification-context-events.json') @{scope='PRIVATE_SYNTHETIC_PARTIAL';events=@($events.ToArray());outcome='PASS'}
}
function CanonicalRegression{
 PostbuildOutputRegression
 ComposerColdRegression
 PackageCanonicalRegression
 # Exercise the real native transport and production build-evidence reader.
 # These literal result facts test binding only; this creates no ZIP or qualification.
 $emit=Join-Path $temp 'emit-build-result.ps1';$fakeZip=Join-Path $temp 'binding-only.zip'
 Put $emit 'param([string]$OutputPath);[pscustomobject]@{status="BUILT_UNVERIFIED";frameworkVersion="2.0.0";provisional=$true;canonical=("A"*64);fileCount=3;outputPath=$OutputPath;distributionId="2.0.0-snapshot.1";sourceManifestIdentity=("1|"+("B"*64));sourcePayloadCanonical=("C"*64)}'
 $emitted=NativeTool $emit @{OutputPath=$fakeZip}
 $bound=Assert-AiwReleaseBuildEvidence $emitted.ResultPath $fakeZip ([pscustomobject]@{Canonical=('A'*64);Members=@(1,2,3)}) ([pscustomobject]@{ManifestIdentity=('1|'+('B'*64));Facts=[pscustomobject]@{Canonical=('C'*64)}})
 $failTool=Join-Path $temp 'expected-native-failure.ps1';Put $failTool 'param([string]$Marker);throw ("EXPECTED_NATIVE_FAILURE|"+$Marker)'
 $failed=NativeTool $failTool @{Marker='bound-argument'};$errorValue=Read-AiwReleaseJson $failed.CallEvidence.ErrorPath
 Check ($emitted.Code-eq0-and$bound.runId-ceq$emitted.Record.runId-and$failed.Code-eq2-and$errorValue.parameters.Marker-ceq'bound-argument'-and$errorValue.script-ceq$failTool-and$errorValue.line-eq1-and$errorValue.stack.Contains($failTool)-and[IO.File]::Exists($failed.CallEvidence.InputPath)) 'native-single-build-result-keeps-strict-object-shape'
 CanonicalCase ([pscustomobject]@{}) '{}' 'empty-object'
 CanonicalCase ([ordered]@{}) '{}' 'empty-dictionary'
 Check $true 'canonical-empty-object-and-evidence-identity'
 foreach($case in @(
  @{name='singleton-object';value=[pscustomobject]@{a=1};json='{"a":1}'},
  @{name='ordinal-member-names';value=[pscustomobject]@{Value=$false;Name='n';Count=2};json='{"Count":2,"Name":"n","Value":false}'},
  @{name='nested-options-and-scalars';value=[ordered]@{v=@($null,$true,7,'x');options=[pscustomobject]@{};items=@()};json='{"items":[],"options":{},"v":[null,true,7,"x"]}'},
  @{name='empty-array';value=@();json='[]'},
  @{name='singleton-array';value=@(1);json='[1]'},
  @{name='array-object-order';value=@([pscustomobject]@{},[pscustomobject]@{a=1});json='[{},{"a":1}]'},
  @{name='null';value=$null;json='null'},
  @{name='boolean';value=$true;json='true'},
  @{name='integer';value=7;json='7'},
  @{name='escaped-string';value="quote`"and`nnewline";json='"quote\"and\nnewline"'}
 )){CanonicalCase $case.value $case.json $case.name}
 Reject {& $releaseReader {Assert-AiwReleaseFields ([pscustomobject]@{}) @('needed') 'empty-test'}} '^RELEASE_FIELDS\|empty-test$' 'canonical-field-validation-keeps-empty-shape-rejection'
 Check $true 'canonical-json-shapes-and-ordinal-identity'
 $badZip=Join-Path $temp 'explicitly-invalid.zip';Put $badZip 'This is intentionally not a ZIP archive.'
 $build=Join-Path $temp 'opaque-build-input.json';Put $build 'This readable input only reaches the earlier byte hash; it is not valid build evidence.'
 $run=NativeTool (Join-Path $PSScriptRoot 'run-framework-tests.ps1') @{Phase='POSTBUILD';Groups=@('postbuild.package-integrity');PackagePath=$badZip;BuildCommandPath=$build;EvidenceDirectory=(Join-Path $temp 'cold-postbuild-evidence')}
 Check ($run.Code-ne0-and$run.Text-cmatch'Expand-AiwReleasePackage, [^\r\n]*ReleaseValidation\.psm1: line'-and$run.Text-cmatch'OpenRead'-and$run.Text-cnotmatch'CommandNotFound|TEST_UNKNOWN_DUPLICATE_OR_MIXED_PHASE_GROUP|POSTBUILD_FRESH_EXISTING_INPUTS_REQUIRED') 'postbuild-cold-runner-reaches-owned-reader'
 BuilderByteCaptureRegression
}
function AssertMovedExecutionCannotReuse($Moved,$Definition,$GroupDef,$Options,$Record){
 # A portable qualified sample retains its earlier construction closure.
 # Reconstruct an actual current execution namespace before testing record reuse.
 $reuseView=New-AiwTestSourceView $Moved (Join-Path $temp 'reuse-check-view') $Definition
 $reuseDefinition=Join-Path $reuseView.Root 'framework/versions/2.0.0/tests/test-groups.json'
 $newSnapshot=Get-AiwTestDependencySnapshot $reuseView.Root $reuseDefinition $Definition $GroupDef $Options
 Reject {Assert-AiwTestGroupEvidence $Record $GroupDef $newSnapshot -ForReuse} '^TEST_RECORD_FAILED_PARTIAL_OR_INPUT_DRIFT$' 'portable-consumption-does-not-authorize-cross-root-execution-reuse'
}
function QualifySample([string]$Root,$Proof){
 $version=Join-Path $Root 'framework/versions/2.0.0';$facts=Get-AiwReleasePayloadFacts $version @((Read-AiwReleaseJson (Join-Path $version $Proof.proofBundleRef.path)).members.path+$Proof.proofBundleRef.path)
 $m=[ordered]@{schemaVersion=3;version='2.0.0';lifecycle='CANDIDATE';releaseClass='MAJOR';scope='all release payload files except RELEASE_MANIFEST.json and exact declared validation evidence members';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$facts.FileCount;totalBytes=$facts.TotalBytes;canonical=$facts.Canonical;baseline='1.16.0';sourceReview='PENDING';sourceCandidate='PENDING';releaseIntegration='PREPACKAGE_PASS';validationProof=$Proof;sourceReviewEvidence=@{status='PENDING';reviewer=$null;packageIdentity=$null;reviewedPayloadCanonical=$null;reviewedManifestIdentity=$null;reviewedManifestBase64=$null}}
 $path=Join-Path $version 'RELEASE_MANIFEST.json';WriteFixtureJson $path $m;$before=[IO.File]::ReadAllBytes($path)
 $m.sourceReview='APPROVED';$m.sourceReviewEvidence=@{status='APPROVED';reviewer='synthetic-independent-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$facts.Canonical;reviewedManifestIdentity=(Get-AiwReleaseByteIdentity $before);reviewedManifestBase64=[Convert]::ToBase64String($before)}
 WriteFixtureJson $path $m;return Read-AiwReleaseJson $path
}
function WireStringRegression {
 $wirePath=Join-Path $temp 'wire-time.json';$times=@('2026-10-09T12:34:56Z','2026-10-09T20:34:56.1+08:00','2026-10-09T12:34:56.1234567Z')
 foreach($time in $times){
  $wire='{"utc":"'+$time+'","checkedUtc":"'+$time+'","creationUtc":null,"nested":{"utc":"'+$time+'"},"empty":[],"one":["'+$time+'"]}';Put $wirePath $wire
  $default=ConvertFrom-AiwStrictInputJson $wire;$native=$wire|ConvertFrom-Json -Depth 100
  $converted=@(ConvertFrom-AiwStrictInputJson $wire -StringFields @('utc','checkedUtc') -NullableStringFields @('creationUtc'));$read=@(Read-AiwStrictInputJson $wirePath -StringFields @('utc','checkedUtc') -NullableStringFields @('creationUtc'))
  Check ($converted.Count-eq1-and$read.Count-eq1-and$converted[0].Value.utc-is[string]-and$converted[0].Value.utc-ceq$time-and$read[0].Value.checkedUtc-ceq$time-and$null-eq$read[0].Value.creationUtc-and$read[0].Value.empty-is[Array]-and$read[0].Value.empty.Count-eq0-and$read[0].Value.one-is[Array]-and$read[0].Value.one.Count-eq1) 'wire-string-read-convert-preserve-original-token-and-return-shape'
  Check ($default.Value.utc.GetType()-eq$native.utc.GetType()-and(Get-AiwReleaseCanonical $default.Value.nested)-ceq(Get-AiwReleaseCanonical $converted[0].Value.nested)) 'wire-string-opt-in-preserves-default-and-nested-canonical'
  $local=Read-AiwTestJson $wirePath -StringFields @('utc','checkedUtc') -NullableStringFields @('creationUtc');$portable=Read-AiwReleaseJson $wirePath -StringFields @('utc','checkedUtc') -NullableStringFields @('creationUtc')
  Check ($local.utc-ceq$time-and$portable.utc-ceq$time-and$null-eq$local.creationUtc) 'local-and-portable-wire-readers-keep-same-original-string'
  $culture=[Globalization.CultureInfo]::CurrentCulture
  try{[Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('fr-FR');$parsed=ConvertTo-AiwReleaseEvidenceTime $time 'wire-test';Check ($parsed-is[DateTimeOffset]) 'wire-time-zone-and-fraction-parse-is-invariant'}finally{[Globalization.CultureInfo]::CurrentCulture=$culture}
 }
 foreach($token in @('0','null','true','["2026-10-09T12:34:56Z"]','{"value":"2026-10-09T12:34:56Z"}')){
  Put $wirePath ('{"utc":'+$token+'}');Reject {Read-AiwStrictInputJson $wirePath -StringFields @('utc')} '^INPUT_STRING_FIELD_TYPE\|utc$' 'wire-string-rejects-non-string-token'
  Reject {Read-AiwTestJson $wirePath -StringFields @('utc')} '^INPUT_STRING_FIELD_TYPE\|utc$' 'local-wire-string-rejects-non-string-token'
  Reject {Read-AiwReleaseJson $wirePath -StringFields @('utc')} '^INPUT_STRING_FIELD_TYPE\|utc$' 'portable-wire-string-rejects-non-string-token'
 }
 Put $wirePath '{"checkedUtc":"2026-10-09T12:34:56Z","checkedUtc":"2026-10-09T12:34:56Z"}'
 Reject {Read-AiwTestJson $wirePath -StringFields @('checkedUtc')} '^TEST_JSON_DUPLICATE_MEMBER$' 'local-wire-duplicate-error-is-preserved'
 Reject {Read-AiwReleaseJson $wirePath -StringFields @('checkedUtc')} '^INPUT_FIELD_COUNT\|checkedUtc$' 'portable-wire-duplicate-error-is-preserved'
 foreach($value in @('2026-10-09T12:34:56','2026-99-99T12:34:56Z','2026-10-09T12:34:56.12345678Z')){Reject {ConvertTo-AiwReleaseEvidenceTime $value 'wire-test'} '^RELEASE_EVIDENCE_TIME\|wire-test$' 'wire-time-rejects-missing-zone-invalid-date-or-excess-fraction'}
 Put $wirePath '[0,"plain"]';$old=@((Get-Content -LiteralPath $wirePath -Raw|ConvertFrom-Json -Depth 100));$read=@(Read-AiwTestJson $wirePath);Check ((Get-AiwReleaseCanonical $read)-ceq(Get-AiwReleaseCanonical $old)) 'generic-test-json-array-return-is-unchanged'
 Reject {Read-AiwStrictInputJson $wirePath -StringFields @('utc')} '^INPUT_OBJECT_TYPE$' 'wire-fields-do-not-change-object-root-contract'
 Put $wirePath '{"utc":null}';$nullable=Read-AiwStrictInputJson $wirePath -NullableStringFields @('utc');Check ($null-eq$nullable.Value.utc-and$null-eq(ConvertTo-AiwReleaseEvidenceTime $nullable.Value.utc 'nullable' -Nullable)) 'explicit-nullable-wire-field-retains-null'
 [IO.File]::WriteAllBytes($wirePath,[byte[]]@(255));Reject {Read-AiwStrictInputJson $wirePath -StringFields @('utc')} '^INPUT_UTF8$' 'wire-fields-preserve-strict-invalid-utf8-rejection'
 $decoder=$false;try{$null=Read-AiwTestJson $wirePath -StringFields @('utc')}catch{$decoder=$_.Exception-is[Text.DecoderFallbackException]-or$_.Exception.InnerException-is[Text.DecoderFallbackException]};Check $decoder 'test-json-invalid-utf8-original-cause-is-preserved'
 [IO.File]::WriteAllBytes($wirePath,[byte[]]@(239,187,191,123,125));Reject {Read-AiwStrictInputJson $wirePath} '^INPUT_BOM$' 'wire-fields-preserve-bom-rejection'
 Put $wirePath '{"utc":';Reject {Read-AiwStrictInputJson $wirePath -StringFields @('utc')} '^INPUT_JSON$' 'wire-fields-preserve-invalid-json-rejection'
}
function V1ColdRegression([string]$Source){
 if(-not$V1ReaderPath){return}
 $old=Assert-AiwTestPath $V1ReaderPath;$dependency=Join-Path (Split-Path -Parent $old) 'StrictJsonInput.psm1'
 Check ((Get-AiwTestFileIdentity $old)-ceq'50199|8BCC83003D7D5DB972A5355B015326A872ED1181C5AE024BBC1D1CB9FF8E4330'-and(Get-AiwTestFileIdentity $dependency)-ceq'2207|99DFD33C465B52489FCFC760939FE4842AA7E515C1488FA611B08A11855D506A') 'v1-cold-reader-exact-original-and-dependency'
 $sample=Join-Path $temp 'v1-source';$definition=Read-AiwTestGroupDefinition (Join-Path $Source 'framework/versions/2.0.0/tests/test-groups.json');$null=New-AiwTestSourceView $Source $sample $definition;$v=Join-Path $sample 'framework/versions/2.0.0'
 $entry='framework/versions/2.0.0/tests/v1-sentinel.ps1';Put (Join-Path $sample $entry) '$ErrorActionPreference="Stop";if([IO.File]::ReadAllText((Join-Path $PSScriptRoot "v1-sentinel.txt"))-cne"old-v1-health"){throw "V1_SENTINEL"};"PASS|v1-sentinel";"RESULT|1/1 passed|scope=v1-sentinel"';Put (Join-Path $v 'tests/v1-sentinel.txt') 'old-v1-health'
 $inventory=Read-AiwTestJson (Join-Path $v 'NORMATIVE_SURFACE_INVENTORY.json');$inventory.schemaAndMechanicalInputs+=@('tests/v1-sentinel.ps1','tests/v1-sentinel.txt');WriteFixtureJson (Join-Path $v 'NORMATIVE_SURFACE_INVENTORY.json') $inventory
 $definition.schemaVersion=2;$definition.groups=@([pscustomobject]@{id='integration.full-source';entry=$entry;arguments=@();phase='PREPACKAGE';requiredFor=@('FULL');casePolicy='OBSERVED_NAMED_CASES';requiredCaseIds=@('v1-sentinel');completionPattern='^RESULT\|1/1 passed\|scope=v1-sentinel$';dependencies=@('framework/versions/2.0.0/tests/v1-sentinel.txt');unknownDependencies=@();alwaysFresh=$true;fixturePolicy='MECHANISM';tools=@('pwsh')});$definition.mechanismVersionPaths=@();WriteFixtureJson (Join-Path $v 'tests/test-groups.json') $definition
 $groups=Join-Path $raw 'v1-groups';$run=NativeTool (Join-Path $v 'tests/run-framework-tests.ps1') @{EvidenceDirectory=$groups;SourceViewPath=(Join-Path $raw 'v1-owned-view');ProofSchemaVersion=1} -Cwd $sample
 Check ($run.Code-eq0) 'v1-health-real-original-execution-and-full-export'
 $proof=Read-AiwTestJson (Join-Path $groups 'prepackage-proof/validation-proof.json');Check ($proof.schemaVersion-eq1-and$proof.mode-ceq'FULL_RUN'-and$null-eq$proof.PSObject.Properties['currentSuiteRef']) 'v1-proof-fields-remain-original'
 Copy-AiwTestAllowlist (Join-Path $groups 'prepackage-proof') $v @((Get-AiwReleaseTreeMembers (Join-Path $groups 'prepackage-proof/validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path});$null=QualifySample $sample $proof
 $before=Get-AiwTestFileIdentity (Join-Path $v 'RELEASE_MANIFEST.json');Check ((Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $sample).State-ceq'SOURCE_QUALIFIED') 'new-reader-accepts-healthy-original-v1-semantics'
 $cold=Join-Path $temp 'v1-cold.ps1';Put $cold @'
param([string]$Reader,[string]$Version,[string]$Source)
$ErrorActionPreference='Stop';$module=Import-Module $Reader -PassThru;$dependencies=@(Get-Module -All StrictJsonInput)
if($module.Path-cne$Reader-or$dependencies.Count-ne1-or$dependencies[0].Path-cne(Join-Path (Split-Path -Parent $Reader) 'StrictJsonInput.psm1')){throw 'COLD_READER_OWNER'}
$q=& $module.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $Version -SourceRoot $Source
if($q.State-cne'SOURCE_QUALIFIED'-or$q.Proof.Mode-cne'FULL_RUN'){throw 'OLD_V1_HEALTH'};'OLD_READER_ACCEPTS_HEALTHY_V1'
'@
 $observed=NativeTool $cold @{Reader=$old;Version=$v;Source=$sample} -Cwd $sample
 Check ($observed.Code-eq0-and$observed.StdoutText.Contains('OLD_READER_ACCEPTS_HEALTHY_V1')-and(Get-AiwTestFileIdentity (Join-Path $v 'RELEASE_MANIFEST.json'))-ceq$before) 'actual-cold-old-reader-accepts-same-v1-original-bytes'
}
function ProofSchemaRegression {
 $version=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'));$manifestIdentity=Get-AiwReleaseFileIdentity (Join-Path $version 'RELEASE_MANIFEST.json')
 WireStringRegression
 $fixture=Join-Path $temp 'pending-source';$definition=Read-AiwTestGroupDefinition (Join-Path $version 'tests/test-groups.json');$null=New-AiwTestSourceView $source $fixture $definition;$v=Join-Path $fixture 'framework/versions/2.0.0';$facts=Get-AiwReleasePayloadFacts $v
 $pending=[pscustomobject]@{schemaVersion=3;version='2.0.0';lifecycle='CANDIDATE';releaseClass='MAJOR';scope='all release payload files except RELEASE_MANIFEST.json and exact declared validation evidence members';algorithm='Ordinal relative path; path|byteLength|UPPER_SHA256; UTF-8 LF join without trailing LF; SHA256 payload';fileCount=$facts.FileCount;totalBytes=$facts.TotalBytes;canonical=$facts.Canonical;baseline='1.16.0';sourceReview='PENDING';sourceCandidate='PENDING';releaseIntegration='PENDING';validationProof=[pscustomobject]@{schemaVersion=2;phase='PREPACKAGE';mode='CURRENT_GROUP_COVERAGE';status='PENDING';currentPayloadCanonical=$facts.Canonical;suiteDefinitionIdentity=(Get-AiwReleaseFileIdentity (Join-Path $v 'tests/test-groups.json'));proofBundleRef=$null;proofBundleIdentity=$null;requiredGroupIds=@();groupRecordRefs=@();baselineRef=$null;revalidationRefs=@();prepackageIntegrationRefs=@();currentSuiteRef=$null};sourceReviewEvidence=[pscustomobject]@{status='PENDING';reviewer=$null;packageIdentity=$null;reviewedPayloadCanonical=$null;reviewedManifestIdentity=$null;reviewedManifestBase64=$null}}
 WriteFixtureJson (Join-Path $v 'RELEASE_MANIFEST.json') $pending
 Check ((Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $fixture -AllowPending).State-ceq'PENDING_CANDIDATE') 'proof-v2-explicit-pending-shape-without-future-qualification'
 $causes=@{V1_MODE='RELEASE_PENDING_MIXED_EVIDENCE';V2_MODE='RELEASE_PENDING_MIXED_EVIDENCE';ARRAY_SCHEMA='RELEASE_PROOF_SCHEMA_INTEGER';ARRAY_MODE='RELEASE_STRING\|proof-state\|mode';FAILED='RELEASE_PROOF_NOT_PASS';SUITE_REF='RELEASE_PENDING_MIXED_EVIDENCE';BASELINE='RELEASE_PENDING_MIXED_EVIDENCE';UNKNOWN='RELEASE_FIELDS\|proof3'}
 foreach($kind in $causes.Keys){$bad=Clone $pending;switch($kind){'V1_MODE'{$bad.validationProof.schemaVersion=1;$bad.validationProof.PSObject.Properties.Remove('currentSuiteRef')} 'V2_MODE'{$bad.validationProof.mode='FULL_RUN'} 'ARRAY_SCHEMA'{$bad.validationProof.schemaVersion=@(2)} 'ARRAY_MODE'{$bad.validationProof.mode=@('CURRENT_GROUP_COVERAGE')} 'FAILED'{$bad.validationProof.status='FAIL'} 'SUITE_REF'{$bad.validationProof.currentSuiteRef=@{path='future';identity=('1|'+('A'*64))}} 'BASELINE'{$bad.validationProof.baselineRef=@{path='future';identity=('1|'+('A'*64))}} 'UNKNOWN'{$bad.validationProof|Add-Member bypass $true}};WriteFixtureJson (Join-Path $v 'RELEASE_MANIFEST.json') $bad;Reject {Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $fixture -AllowPending} ('^'+$causes[$kind]+'$') ('proof-schema-reject-'+$kind.ToLowerInvariant())}
 WriteFixtureJson (Join-Path $v 'RELEASE_MANIFEST.json') $pending
 V1ColdRegression $source
 ComposerColdRegression
 Check ((Get-AiwReleaseFileIdentity (Join-Path $version 'RELEASE_MANIFEST.json'))-ceq$manifestIdentity) 'proof-schema-checks-preserve-current-manifest-bytes'
 $new=Clone $pending;$new.validationProof.schemaVersion=3;$new.validationProof|Add-Member verifierRef ([pscustomobject]@{path='scripts/TestEvidenceValidation.psm1';identity=(Get-AiwReleaseFileIdentity (Join-Path $v 'scripts/TestEvidenceValidation.psm1'))})
 WriteFixtureJson (Join-Path $v 'RELEASE_MANIFEST.json') $new
 Check ((Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $fixture -AllowPending).State-ceq'PENDING_CANDIDATE') 'proof3-pending-has-current-known-verifier-and-no-future-results'
 foreach($fault in @('STALE','UNKNOWN','SCHEMA_STRING')){
  $bad=Clone $new
  switch($fault){'STALE'{$bad.validationProof.verifierRef.identity='1|'+('A'*64)} 'UNKNOWN'{$bad.validationProof.verifierRef|Add-Member extra $true} 'SCHEMA_STRING'{$bad.validationProof.schemaVersion='3'}}
  WriteFixtureJson (Join-Path $v 'RELEASE_MANIFEST.json') $bad
  Reject {Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $fixture -AllowPending} 'RELEASE_PENDING_MIXED_EVIDENCE|RELEASE_FIELDS|RELEASE_PROOF_SCHEMA_INTEGER' ('proof3-pending-reject-'+$fault)
 }

}
function RebindBundle([string]$Root,$Proof){
 $version=Join-Path $Root 'framework/versions/2.0.0';$indexPath=Join-Path $version $Proof.proofBundleRef.path;$index=Read-AiwReleaseJson $indexPath
 foreach($member in $index.members){$member.identity=Get-AiwReleaseFileIdentity (Join-Path $version $member.path)}
 foreach($alias in $index.aliases){$target=@($index.members|Where-Object id -CEQ $alias.targetMemberId)[0];if($alias.slot-cin@('PROCESS_LAUNCH_FOR_RUN','PHASE_EVENTS_FOR_RUN')){$alias.originalIdentity=$target.identity}}
 WriteFixtureJson $indexPath $index;$Proof.proofBundleRef.identity=Get-AiwReleaseFileIdentity $indexPath
 $Proof.proofBundleIdentity=(Get-AiwReleaseMemberFacts (@(@{path=$Proof.proofBundleRef.path;identity=$Proof.proofBundleRef.identity})+@($index.members))).Canonical
 foreach($ref in $Proof.groupRecordRefs){$ref.identity=@($index.members|Where-Object path -CEQ $ref.path)[0].identity}
 $Proof.prepackageIntegrationRefs=@($Proof.groupRecordRefs|Where-Object groupId -CEQ 'integration.full-source'|ForEach-Object{@{path=$_.path;identity=$_.identity}})
 return QualifySample $Root $Proof
}
function AssertPackage([string]$Root,[string]$Zip){
 $facts=Get-AiwReleasePackageFacts -PackageRoot $Root
 $null=Assert-AiwReleaseZipRuntime $Zip $Root
 Check ([bool]$facts.Canonical) 'actual-zip-members-match-package-manifest'
 $qualified=Get-AiwReleaseQualification -VersionRoot (Join-Path $Root 'framework/versions/2.0.0') -RuntimeRoot $Root
 Check ($qualified.State-ceq'SOURCE_QUALIFIED') 'actual-source-qualification-is-preserved'
}
function StableEntryRegression([string]$Source,$Definition){
 # New synthetic qualification constructed from current bytes; no historical
 # proof is rewritten or claimed as release qualification.
 $view=New-AiwTestSourceView $Source (Join-Path $temp 'stable-source') $Definition
 Set-AiwTestFixtureQualification (Join-Path $view.Root 'framework/versions/2.0.0')
 $zip=Join-Path $temp 'AI-Workspace-2.0.0-release.zip'
 $build=NativeTool (Join-Path $view.Root 'scripts/build-user-package.ps1') @{WorkspaceRoot=$view.Root;FrameworkVersion='2.0.0';Distribution='release';OutputPath=$zip;Apply=$true}
 RequirePositiveNative $build ($build.Code-eq0-and[IO.File]::Exists($zip)) 'synthetic-stable-entry-package-build' -Zip $zip -QualificationRoot $view.Root
 $root=Join-Path $temp 'stable-package';$null=Expand-AiwReleasePackage $zip $root
 $consumer=Join-Path $temp 'stable-consumer';$null=[IO.Directory]::CreateDirectory($consumer)
 $registration=NativeTool (Join-Path $root 'scripts/register-project.ps1') @{ProjectId='stable-entry';DisplayName='Synthetic stable entry';RepositoryPath=$consumer;FrameworkVersion='2.0.0';ControllerId='stable-actor';WorkspaceRoot=$root;Apply=$true} -ReleaseDiagnostics
 RequirePositiveNative $registration ($registration.Code-eq0) 'synthetic-stable-public-registration' -Zip $zip -Consumer $consumer
 $adoption=@(Import-Module (Join-Path $root 'scripts/ProjectAdoptionState.psm1') -PassThru)[0]
 $fixed=Get-AiwFixedAdoptedRelease -ProjectRoot $consumer -FrameworkRoot $root
 Check ($fixed.State-ceq'FIXED_ADOPTED_SOURCE'-and-not[IO.File]::Exists((Join-Path $consumer '.ai-workspace/upgrade-recovery/2.0.0/state.json'))) 'stable-fixed-adoption-uses-own-register-without-candidate-state'
 $journal=Join-Path $consumer '.ai-workspace/runtime/project-adoption/register/state.json';$saved=[IO.File]::ReadAllBytes($journal)
 $reader=@(Import-Module (Join-Path $root 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
 $composer=@(Import-Module (Join-Path $root 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
 foreach($case in @(
  @{name='missing-metadata';change={param($t) $t.PSObject.Properties.Remove('metadata')}},
  @{name='missing-operation';change={param($t) $t.metadata.PSObject.Properties.Remove('operation')}},
  @{name='unknown-schema';change={param($t) $t.schemaVersion=99}},
  @{name='unknown-operation';change={param($t) $t.metadata.operation='OLD_UNSUPPORTED'}},
  @{name='completed-rollback';change={param($t) $t.state='ROLLED_BACK'}}
 )){
  try{
   $t=Read-AiwReleaseJson $journal;& $case.change $t;WriteFixtureJson $journal $t
   $events=[Collections.Generic.List[object]]::new();$sink={param($e) $events.Add($e)}.GetNewClosure()
   & $reader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {
    Check ($null-eq(Get-AiwFixedAdoptedRelease -ProjectRoot $consumer -FrameworkRoot $root)) ('stable-legacy-'+$case.name+'-has-no-fixed-credential')
    $null=& $composer {param($v,$p) Get-AiwCompositionReleaseFacts -VersionDirectory $v -ProjectRoot $p} (Join-Path $root 'framework/versions/2.0.0') $consumer
    Check (@($events|Where-Object stage -CEQ 'qualification-core-start').Count-eq1-and@($events|Where-Object stage -CEQ 'fixed-adopted-source').Count-eq0) ('stable-legacy-'+$case.name+'-reaches-real-full-qualification')
   }
  }finally{[IO.File]::WriteAllBytes($journal,$saved)}
 }
 Check ((Get-AiwFixedAdoptedRelease -ProjectRoot $consumer -FrameworkRoot $root).State-ceq'FIXED_ADOPTED_SOURCE') 'stable-restored-original-register-remains-fixed'
 $upgrade=NativeTool (Join-Path $root 'scripts/upgrade-project.ps1') @{ProjectId='stable-entry';ToVersion='2.0.0';RepositoryPath=$consumer;ControllerId='stable-actor';WorkspaceRoot=$root;Apply=$true} -ReleaseDiagnostics
 RequirePositiveNative $upgrade ($upgrade.Code-eq0-and$upgrade.Text.Contains('ALREADY_UPGRADED')) 'synthetic-stable-public-same-package-upgrade' -Zip $zip -Consumer $consumer
 $events=@(Get-Content -LiteralPath $upgrade.CallEvidence.DiagnosticsPath|ForEach-Object{$_|ConvertFrom-Json})
 Check (@($events|Where-Object stage -CEQ 'qualification-core-start').Count-eq0-and@($events|Where-Object stage -CEQ 'fixed-adopted-source').Count-ge1) 'stable-same-package-upgrade-has-no-new-deep-qualification'
 Write-AiwTestJson (Join-Path $raw 'stable-entry-performance.json') @{scope='PRIVATE_SYNTHETIC_PARTIAL';registration=@{nativeResult=$registration.ResultPath;phases=$registration.CallEvidence.DiagnosticsPath;wallMilliseconds=$registration.Record.timing.wallMilliseconds};samePackageUpgrade=@{nativeResult=$upgrade.ResultPath;phases=$upgrade.CallEvidence.DiagnosticsPath;wallMilliseconds=$upgrade.Record.timing.wallMilliseconds;deepReaderCount=0}}
 if($EntryPerformanceOnly){Check ($registration.Record.timing.wallMilliseconds-le300000-and$upgrade.Record.timing.wallMilliseconds-le120000) 'stable-isolated-entry-engineering-targets'}
}
function DailyProcessRegression {
 $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'));$runtime=Join-Path $temp 'daily-runtime'
 $version=New-AiwTestMechanismFixture $source $runtime (Join-Path $PSScriptRoot 'test-groups.json') -Maintenance
 # This package is only a synthetic mechanism fixture. Construction scans it
 # once; the public daily calls below must not repeat that complete scan.
 [string[]]$paths=@(Get-ChildItem -LiteralPath $runtime -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($runtime,$_.FullName).Replace('\','/')});[Array]::Sort($paths,[StringComparer]::Ordinal)
 $members=@($paths|ForEach-Object{[pscustomobject]@{path=$_;identity=(Get-AiwTestFileIdentity (Join-Path $runtime $_))}});$rows=@($members|ForEach-Object{$_.path+'='+$_.identity})
 WriteFixtureJson (Join-Path $runtime 'PACKAGE_MANIFEST.json') @{schemaVersion=2;frameworkVersion='2.0.0';provisional=$false;distributionId='2.0.0-release';canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($rows-join"`n")+"`n")));files=$members}
 $control=Join-Path $temp 'daily-control';$target=Join-Path $temp 'daily-target';foreach($directory in @($control,$target)){$null=[IO.Directory]::CreateDirectory($directory);& git -C $directory init -q;if($LASTEXITCODE-ne0){throw 'DAILY_FIXTURE_GIT_INIT'}}
 $registered=NativeTool (Join-Path $runtime 'scripts/register-project.ps1') @{ProjectId='daily-control';DisplayName='Synthetic daily process';RepositoryPath=$control;FrameworkVersion='2.0.0';ControllerId='daily-actor';WorkspaceRoot=$runtime;ControlPlaneLayout='framework-maintenance-sibling';FrameworkTargetRepositoryId='daily-target';FrameworkTargetSiblingDirectory='daily-target';Apply=$true}
 Check ($registered.Code-eq0) ('daily-actual-synthetic-registration|'+$registered.Text)
 $taskRelative='.ai-workspace/tasks/active/DAILY-001.md';$task=Join-Path $control $taskRelative
 Put $task "# DAILY-001`n- Owner: daily-actor`n- Work route: actor=daily-actor; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
 $configPath=Join-Path $control '.ai-workspace/project.json';$configIdentity=Get-AiwTestFileIdentity $configPath;$taskIdentity=Get-AiwTestFileIdentity $task
 $output=Join-Path $control '.ai-workspace/runtime/DAILY-001/daily-actor';$null=[IO.Directory]::CreateDirectory($output);$changed='.ai-workspace/daily-result.md'
 $package=@{schemaVersion=2;frameworkVersion='2.0.0';repositoryId='CONTROL';taskId='DAILY-001';profile='STANDARD';lifecycle='ACTIVE';owner='daily-actor';issuer='daily-actor';issuerRole='TASK_OWNER';grantee='daily-actor';bundle='LOCAL_BOUNDED';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=$taskIdentity;actions=@('CONTROL_WRITE');exactPaths=@($changed);objectIdentities=@(@{path=$changed;identity='NEW'});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','REPOSITORY_CHANGE');projectConfigIdentity=$configIdentity}
 $packagePath=Join-Path $output 'package.json';WriteFixtureJson $packagePath $package
 $checkerParams=@{ControlRepositoryPath=$control;PackagePath=$packagePath;ObservedRepositoryId='CONTROL';ObservedActor='daily-actor';ObservedTaskId='DAILY-001';ObservedOwner='daily-actor';ObservedAction=@('CONTROL_WRITE');ObservedPath=@($changed);ObservedIdentity=@($changed+'=NEW');ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=$configIdentity;TaskPath=$taskRelative;ExpectedTaskIdentity=$taskIdentity;ControllerControlPath='.ai-workspace/controller.json'}
 $intent=@{schemaVersion=2;objective='Record the exact bounded synthetic daily result.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=@($changed);capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:implementation')};deliverableType=@{state='KNOWN';values=@('aiw:report')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}
 $input=@{schemaVersion=5;ruleLoad=@{mode='FULL'};mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$control;frameworkRoot=$runtime;taskPath=$task;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-AiwTestFileIdentity (Join-Path $control '.ai-workspace/corrections.json'));expectedTaskIdentity=$taskIdentity;observedActor='daily-actor';capabilities=@();exactPaths=@($changed);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Get-AiwTestFileIdentity $packagePath);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
 $inputPath=Join-Path $output 'discover.json';WriteFixtureJson $inputPath $input;$resolver=Join-Path $runtime 'scripts/resolve-framework-maintenance-process-requirements.ps1'
 $decode={param($run) $value=$run.Text|ConvertFrom-Json -Depth 100;if($value-is[string]){$value=$value|ConvertFrom-Json -Depth 100};return $value}
 $setup="[Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','daily-actor','Process')"
 # A healthy full qualification must first pass, so the negative below
 # cannot be satisfied by an already-invalid synthetic fixture.
 $reader=@(Import-Module (Join-Path $runtime 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
 $healthyQualification=& $reader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $version -RuntimeRoot $runtime
 Check ($healthyQualification.State-ceq'SOURCE_QUALIFIED'-and$healthyQualification.Version.lifecycle-ceq'STABLE') 'daily-complete-qualification-passes-before-unconsumed-drift'
 $unconsumed=@('framework/versions/2.0.0/tests/measure-process-requirements.ps1','scripts/register-project.ps1','framework/maintenance-overlay/AGENTS.md','framework/maintenance-overlay/BOOTSTRAP.md','framework/maintenance-overlay/PROJECT_CONFIG_SCHEMA.json','framework/maintenance-overlay/process-policy.json');$saved=@{}
 try{
  foreach($relative in $unconsumed){$path=Join-Path $runtime $relative;$saved[$relative]=[IO.File]::ReadAllBytes($path);[IO.File]::AppendAllText($path,"`n# damaged unconsumed member",[Text.Encoding]::UTF8)}
  $check=NativeTool (Join-Path $runtime 'scripts/check-framework-maintenance-authorization.ps1') $checkerParams $control -Setup $setup
  Check ($check.Code-eq0) ('daily-real-maintenance-checker-ignores-unconsumed-history-and-test-bytes|'+$check.Text)
  $dRun=NativeTool $resolver @{InputPath=$inputPath;AsJson=$true} $control -Setup $setup;$d=& $decode $dRun
  Check ($dRun.Code-eq0-and$d.status-ceq'PASS'-and'FIXED_ADOPTED_CONSUMED_MEMBERS'-cin@($d.compactReceipt.evidence.ceilings)) ('daily-real-maintenance-DISCOVER-uses-consumed-members|'+$dRun.Text)
  $reader=@(Import-Module (Join-Path $runtime 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
  Reject {& $reader.ExportedCommands['Get-AiwReleasePackageFacts'] $runtime} 'RELEASE_PACKAGE_MEMBER_DRIFT' 'complete-package-reader-still-rejects-unconsumed-byte-drift'
  Reject {& $reader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $version -RuntimeRoot $runtime} '^RELEASE_VALIDATION_STATE_UNSUPPORTED$' 'complete-new-source-qualification-still-rejects-byte-drift'
  $state=@(Import-Module (Join-Path $runtime 'scripts/ProjectAdoptionState.psm1') -PassThru)[0]
  $partial=& $state {param($p,$r) Get-AiwFixedAdoptedProcessSource $p $r} $control $runtime
  Check ($partial.State-ceq'FIXED_ADOPTED_PROCESS_SOURCE'-and$null-eq$partial.PSObject.Properties['Facts']-and$null-eq$partial.PackageObservation.PSObject.Properties['Members']) 'daily-observation-never-claims-complete-package-facts'
  $compact=Join-Path $output 'compact.json';WriteFixtureJson $compact $d.compactReceipt
  $b=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compact;expectedDiscoverReceiptIdentity=(Get-AiwTestFileIdentity $compact);preparationReceipts=@($d.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  $bPath=Join-Path $output 'boundary.json';WriteFixtureJson $bPath $b;$a=NativeTool $resolver @{InputPath=$bPath;AsJson=$true} $control -Setup $setup
  Check ($a.Code-eq0-and(& $decode $a).status-ceq'PASS') 'daily-real-public-ADMIT-with-unconsumed-drift'
  Put (Join-Path $control $changed) 'Exact synthetic daily result.'
  $b.mode='FINALIZE_OUTPUT';$b.resultReceipts=@($d.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$changed+'|'+(Get-AiwTestFileIdentity (Join-Path $control $changed)));WriteFixtureJson $bPath $b
  $f=NativeTool $resolver @{InputPath=$bPath;AsJson=$true} $control -Setup $setup
  Check ($f.Code-eq0-and(& $decode $f).status-ceq'PASS') ('daily-real-public-original-FINALIZE-with-unconsumed-drift|'+$f.Text)
 }finally{foreach($relative in $saved.Keys){[IO.File]::WriteAllBytes((Join-Path $runtime $relative),$saved[$relative])}}
 foreach($relative in @('framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1','framework/versions/2.0.0/PROCESS_REQUIREMENTS.json','framework/versions/2.0.0/TASK_AND_SCOPE.md','scripts/resolve-framework-maintenance-process-requirements.ps1','scripts/MaintenanceOverlay.psm1')){
  $path=Join-Path $runtime $relative;$bytes=[IO.File]::ReadAllBytes($path)
  try{
   [IO.File]::AppendAllText($path,"`n# actual consumed member drift",[Text.Encoding]::UTF8)
   $bad=NativeTool $resolver @{InputPath=$bPath;AsJson=$true} $control -Setup $setup
   Check ($bad.Code-ne0) ('daily-public-FINALIZE-rejects-consumed-drift-'+[IO.Path]::GetFileName($relative))
  }finally{[IO.File]::WriteAllBytes($path,$bytes)}
 }
}

function FixedSourceRegression([string]$Root,[string]$Consumer){
 $adoption=@(Import-Module (Join-Path $Root 'scripts/ProjectAdoptionState.psm1') -PassThru)[0]
 $reader=@(Import-Module (Join-Path $Root 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
 $events=[Collections.Generic.List[object]]::new();$sink={param($e) $events.Add($e)}.GetNewClosure()
 & $reader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $sink -Body {
  $fixed=Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root
  Check ($fixed.State-ceq'FIXED_ADOPTED_SOURCE'-and$fixed.Manifest.sourceCandidate-ceq'PENDING'-and$null-eq$fixed.PSObject.Properties['Proof']-and@($events|Where-Object stage -CEQ 'deep-reader-start').Count-eq0) 'fixed-adopted-daily-source-has-no-new-qualification'
  $journal=Join-Path $Consumer '.ai-workspace/runtime/project-adoption/register/state.json';$original=[IO.File]::ReadAllBytes($journal)
  foreach($field in @('state','transactionComplete')){
   try{$value=Read-AiwReleaseJson $journal;if($field-ceq'state'){$value.state='APPLYING'}else{$value.transactionComplete=$false};WriteFixtureJson $journal $value;Reject {Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root} '^ADOPTION_RECOVERY_REQUIRED$' ('fixed-adopted-rejects-incomplete-'+$field)}finally{[IO.File]::WriteAllBytes($journal,$original)}
  }
  foreach($case in @(
   @{name='missing-projection';change={param($t) $t.PSObject.Properties.Remove('projection')}},
   @{name='projection-container';change={param($t) $t.projection.objects=$null}},
   @{name='metadata-container';change={param($t) $t.metadata=@()}},
   @{name='missing-operation';change={param($t) $t.metadata.PSObject.Properties.Remove('operation')}},
   @{name='missing-completion';change={param($t) $t.PSObject.Properties.Remove('transactionComplete')}},
   @{name='write-count';change={param($t) $t.completedWrites++}},
   @{name='wrong-root';change={param($t) $t.repositoryRoot=Join-Path $Consumer 'other'}},
   @{name='wrong-slot';change={param($t) $t.transactionRelativePath='.ai-workspace/runtime/project-adoption/refresh/state.json'}},
   @{name='rolled-back-current-origin';change={param($t) $t.state='ROLLED_BACK'}}
  )){
   try{
    $value=Read-AiwReleaseJson $journal;& $case.change $value;WriteFixtureJson $journal $value
    $before=@($events|Where-Object stage -CEQ 'qualification-core-start').Count
    Reject {Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root} '^(ADOPTION_RECOVERY_REQUIRED|REGISTRATION_|FIXED_ADOPTION_)' ('fixed-supported-origin-rejects-'+$case.name)
    Check (@($events|Where-Object stage -CEQ 'qualification-core-start').Count-eq$before) ('fixed-invalid-'+$case.name+'-does-not-fall-through-to-full')
   }finally{[IO.File]::WriteAllBytes($journal,$original)}
  }
  $statePath=Join-Path $Consumer '.ai-workspace/upgrade-recovery/2.0.0/state.json'
  if([IO.File]::Exists($statePath)){
   $stateBytes=[IO.File]::ReadAllBytes($statePath)
   try{$state=Read-AiwReleaseJson $statePath;$state.targetReleaseCanonical='A'*64;WriteFixtureJson $statePath $state;Reject {Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root} 'REGISTRATION_.*(DRIFT|POSTIMAGE)|FIXED_ADOPTION_.*DRIFT' 'fixed-adopted-rejects-self-reported-state-with-wrong-live-postimage'}finally{[IO.File]::WriteAllBytes($statePath,$stateBytes)}
   try{
    $state=Read-AiwReleaseJson $statePath;$state.schemaVersion=6;WriteFixtureJson $statePath $state
    $weak=Get-AiwAdoptedDistributionBinding -ProjectRoot $Consumer -FrameworkVersion '2.0.0'
    Check ($weak.contentIdentity-ceq$state.distributionBinding.contentIdentity) 'schema6-counterexample-is-accepted-by-the-existing-weak-binding-helper'
    Reject {Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root} '^FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT$' 'schema6-self-report-without-latest-upgrade-or-refresh-cannot-use-fixed-source'
   }finally{[IO.File]::WriteAllBytes($statePath,$stateBytes)}
  }
  $transaction=Read-AiwReleaseJson $journal
  $prospective=Invoke-AiwRegistrationProjectionContext -ProjectRoot $Consumer -SourceProjectRoot $Consumer -Projection $transaction.projection -Body {Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root}
  Check ($null-eq$prospective) 'fixed-adopted-prospective-projection-cannot-claim-completion'
  $tool=Join-Path $Root 'scripts/register-project.ps1';$toolBytes=[IO.File]::ReadAllBytes($tool);$mtime=[IO.File]::GetLastWriteTimeUtc($tool)
  $packagePath=Join-Path $Root 'PACKAGE_MANIFEST.json';$packageBytes=[IO.File]::ReadAllBytes($packagePath)
  try{
   $changed=[byte[]]$toolBytes.Clone();$changed[0]=$changed[0]-bxor1;[IO.File]::WriteAllBytes($tool,$changed);[IO.File]::SetLastWriteTimeUtc($tool,$mtime)
   Reject {Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root} '^RELEASE_PACKAGE_MEMBER_DRIFT$|FIXED_REGISTRATION_TOOLS_DRIFT' 'fixed-adopted-rejects-restored-mtime-tool-drift'
   $package=Read-AiwReleaseJson $packagePath;@($package.files|Where-Object path -CEQ 'scripts/register-project.ps1')[0].identity=Get-AiwReleaseFileIdentity $tool
   $rows=@($package.files|ForEach-Object{$_.path+'='+$_.identity});$package.canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes(($rows-join"`n")+"`n")))
   WriteFixtureJson $packagePath $package
   Check ((Get-AiwReleasePackageFacts $Root).Canonical-ceq$package.canonical) 'fixed-swap-counterexample-is-an-internally-consistent-package'
   Reject {Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root} '^RELEASE_FIXED_DISTRIBUTION_DRIFT$|FIXED_REGISTRATION_TOOLS_DRIFT' 'fixed-adopted-rejects-tool-and-package-manifest-rebinding'
  }finally{[IO.File]::WriteAllBytes($tool,$toolBytes);[IO.File]::SetLastWriteTimeUtc($tool,$mtime);[IO.File]::WriteAllBytes($packagePath,$packageBytes)}
  Check ((Get-AiwFixedAdoptedRelease -ProjectRoot $Consumer -FrameworkRoot $Root).State-ceq'FIXED_ADOPTED_SOURCE') 'fixed-adopted-restored-package-remains-usable'
 }
}
function AdoptionSmoke([string]$Root){
 $consumer=Join-Path $temp 'consumer';$null=[IO.Directory]::CreateDirectory($consumer)
 $version=Read-AiwReleaseJson (Join-Path $Root 'framework/versions/2.0.0/VERSION.json');$candidate=$version.lifecycle-ceq'CANDIDATE'
 $registration=@{ProjectId='postbuild-smoke';DisplayName='Isolated actual package smoke';RepositoryPath=$consumer;FrameworkVersion='2.0.0';ControllerId='postbuild-actor';WorkspaceRoot=$Root;Apply=$true}
 if($candidate){
  $registration.LocalCandidatePilot=$true;$initial=Join-Path $temp 'POSTBUILD-001.md'
  Put $initial @'
# POSTBUILD-001 — Validate isolated actual package registration
- Task schema: 2.0.0
- 状态：IN_PROGRESS
- Profile: STANDARD; reason=Finite isolated package smoke.
- Owner: postbuild-actor
- Work route: actor=postbuild-actor; role=CONTROLLER; phase=IMPLEMENT
- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[.ai-workspace/PROJECT.md]; actual_paths=[.ai-workspace/PROJECT.md]
- Writer / reviewer / authorization: postbuild-actor / NONE / isolated test action
- Stable candidate: NONE
- Git / push / external: EXCLUDED / NONE / NONE
## Current
- Goal: Register the actual frozen package in an isolated consumer.
- Scope: Isolated project control plane only; no real consumer or product writes.
- Implementation: Use the current public registrar and original transaction recovery.
- Acceptance: Registration completes and same-version upgrade preserves registered bytes.
- Next action: Run the actual registration smoke.
'@
  $registration.InitialTaskPath=$initial;$registration.ExpectedInitialTaskIdentity=Get-AiwTestFileIdentity $initial;$registration.InitialTaskRelativePath='.ai-workspace/tasks/active/POSTBUILD-001.md'
 }
 # Reach the actual registrar try/catch through a controlled task drift at its
 # real preflight, after all entry checks have accepted the original task.
 if($candidate){
  $negative=@{};foreach($key in $registration.Keys){$negative[$key]=$registration[$key]};$negative.RepositoryPath=Join-Path $temp 'negative-consumer';$null=[IO.Directory]::CreateDirectory($negative.RepositoryPath)
  $negative.InitialTaskPath=Join-Path $temp 'negative-task.md';[IO.File]::Copy($initial,$negative.InitialTaskPath,$false);$negative.ExpectedInitialTaskIdentity=Get-AiwTestFileIdentity $negative.InitialTaskPath
  $setup='$global:AiwDriftTask=$v.parameters.InitialTaskPath; $null=Set-PSBreakpoint -Script $v.tool -Line '+[string]((Select-String -LiteralPath (Join-Path $Root 'scripts/register-project.ps1') -Pattern "if(`$null-ne`$initialTask-and(Get-AiwByteIdentity" -SimpleMatch).LineNumber)+' -Action {[IO.File]::AppendAllText($global:AiwDriftTask,"`n# controlled preflight drift")}'
  $negativeRun=NativeTool (Join-Path $Root 'scripts/register-project.ps1') $negative -Setup $setup;$failure=Read-AiwReleaseJson $negativeRun.CallEvidence.ErrorPath
  PreservePositiveFailure $negativeRun 'controlled-registration-failure-retention' -Zip $script:smokeZip -InitialTask $negative.InitialTaskPath -Consumer $negative.RepositoryPath
  $retention=Read-AiwReleaseJson (Join-Path $negativeRun.CallEvidence.Root 'unexpected-positive-failure.json');$retainedZip=@($retention.artifacts|Where-Object originalPath -CEQ $script:smokeZip);$retainedTask=@($retention.artifacts|Where-Object originalPath -CEQ $negative.InitialTaskPath)
  Check ($negativeRun.Code-eq2-and$failure.message-ceq'REGISTRATION_INITIAL_TASK_DRIFT'-and$failure.stack.Contains('register-project.ps1')-and$failure.stack.Contains('ProjectAdoptionTransaction.psm1')-and$failure.position.Contains('REGISTRATION_INITIAL_TASK_DRIFT')-and-not[IO.File]::Exists((Join-Path $negative.RepositoryPath '.ai-workspace/project.json'))-and$retainedZip.Count-eq1-and$retainedZip[0].identity-ceq(Get-AiwTestFileIdentity $script:smokeZip)-and$retainedTask.Count-eq1-and$retainedTask[0].identity-ceq(Get-AiwTestFileIdentity $negative.InitialTaskPath)) 'registrar-preflight-error-keeps-original-record'
 }
 $diagnosticsAvailable=[IO.File]::Exists((Join-Path $Root 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1'))
 $registrationRun=NativeTool (Join-Path $Root 'scripts/register-project.ps1') $registration -ReleaseDiagnostics:$diagnosticsAvailable
 $run=$registrationRun
 RequirePositiveNative $run ($run.Code-eq0-and[IO.File]::Exists((Join-Path $consumer '.ai-workspace/project.json'))) 'actual-package-registration-smoke' -Zip $script:smokeZip -InitialTask $(if($candidate){$initial}else{''}) -Consumer $consumer
 # Public same-version upgrade revalidates the actual registered package/origin.
 # Changed-version migration mechanisms remain covered by fresh Gpre bridge tests.
 $upgrade=@{ProjectId='postbuild-smoke';ToVersion='2.0.0';RepositoryPath=$consumer;ControllerId='postbuild-actor';WorkspaceRoot=$Root;Apply=$true}
 if($candidate){$upgrade.LocalCandidatePilot=$true}
 $before=Get-AiwTestFixtureSnapshot $consumer -IdentityOnly;$run=NativeTool (Join-Path $Root 'scripts/upgrade-project.ps1') $upgrade -ReleaseDiagnostics:$diagnosticsAvailable
 $after=Get-AiwTestFixtureSnapshot $consumer -IdentityOnly
 RequirePositiveNative $run ($run.Code-eq0-and$run.Text.Contains('ALREADY_UPGRADED')-and(Get-AiwReleaseValueIdentity $before)-ceq(Get-AiwReleaseValueIdentity $after)) 'actual-package-upgrade-smoke' -Zip $script:smokeZip -Consumer $consumer
 if($diagnosticsAvailable){
 $registrationEvents=@(Get-Content -LiteralPath $registrationRun.CallEvidence.DiagnosticsPath|ForEach-Object{$_|ConvertFrom-Json})
 $upgradeEvents=@(Get-Content -LiteralPath $run.CallEvidence.DiagnosticsPath|ForEach-Object{$_|ConvertFrom-Json})
 $registrationDeep=@($registrationEvents|Where-Object stage -CEQ 'deep-reader-start').Count
 $upgradeDeep=@($upgradeEvents|Where-Object stage -CEQ 'deep-reader-start').Count
 $registrationFull=@($registrationEvents|Where-Object{ $_.stage-ceq'qualification-core-complete'-and$_.facts.state-ceq'SOURCE_QUALIFIED' }).Count
 $schema3=(Read-AiwReleaseJson (Join-Path $Root 'framework/versions/2.0.0/RELEASE_MANIFEST.json')).schemaVersion-eq3
 Check ($registrationFull-ge1-and(-not$schema3-or$registrationDeep-ge1)-and$upgradeDeep-eq0-and@($upgradeEvents|Where-Object stage -CEQ 'qualification-core-start').Count-eq0-and@($upgradeEvents|Where-Object stage -CEQ 'fixed-adopted-source').Count-ge1) 'entry-new-source-deep-qualification-and-same-package-fixed-consumption'
 Write-AiwTestJson (Join-Path $raw 'entry-performance.json') @{scope=$(if($Group-ceq'AdoptionSmoke'){'ACTUAL_PACKAGE_ENTRY'}else{'PRIVATE_SYNTHETIC_PARTIAL'});registration=@{nativeResult=$registrationRun.ResultPath;phases=$registrationRun.CallEvidence.DiagnosticsPath;wallMilliseconds=$registrationRun.Record.timing.wallMilliseconds;deepReaderCount=$registrationDeep};samePackageUpgrade=@{nativeResult=$run.ResultPath;phases=$run.CallEvidence.DiagnosticsPath;wallMilliseconds=$run.Record.timing.wallMilliseconds;deepReaderCount=$upgradeDeep};engineeringTargetsOnly=[bool]$EntryPerformanceOnly}
 if($EntryPerformanceOnly){Check ($registrationRun.Record.timing.wallMilliseconds-le300000-and$run.Record.timing.wallMilliseconds-le120000) 'entry-isolated-registration-and-same-package-upgrade-engineering-targets'}
 if($Group-cne'AdoptionSmoke'){FixedSourceRegression $Root $consumer}
 }
}
try{
 $script:smokeZip=$PackagePath
 if($DailyProcessOnly){DailyProcessRegression;Write-Output ('PARTIAL|DAILY_PROCESS_ONLY|checks='+$passed+'|scope=synthetic-adopted-package-public-boundaries');return}
 if($WireStringOnly){WireStringRegression;Write-Output ('PARTIAL|WIRE_STRING_ONLY|code=0|status=PASS|checks='+$passed+'|scope=release-wire-string');return}
 if($Group-ceq'ProofSchema'){ProofSchemaRegression;Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=release-validation|group='+$Group);return}
 if($Group-ceq'Mechanism'-and-not$EntryPerformanceOnly){NavigationRuntimeRegression}
 if($Group-ceq'Mechanism'-and-not$EntryPerformanceOnly){DailyProcessRegression}
 if($Group-cin@('Canonical','Mechanism','Registration')-and-not$EntryPerformanceOnly){CanonicalRegression}
 if($Group-ceq'Canonical'){
  # The same permanent cheap regression precedes all expensive Mechanism fixtures.
 }elseif($Group-cnotin@('Mechanism','Registration')){
  Invoke-AiwReleaseQualificationScope -Body {
  if(-not$PackagePath-or-not$ExtractedPackagePath-or-not$BuildCommandPath){throw 'POSTBUILD_EXISTING_INPUTS_REQUIRED'}
  $beforeZip=Get-AiwReleaseFileIdentity $PackagePath;$beforeTree=Get-AiwReleasePackageFacts $ExtractedPackagePath
  $sourceQualification=Get-AiwReleaseQualification -VersionRoot (Join-Path $ExtractedPackagePath 'framework/versions/2.0.0') -RuntimeRoot $ExtractedPackagePath
  $null=Assert-AiwReleaseBuildEvidence $BuildCommandPath $PackagePath $beforeTree $sourceQualification
  if($Group-ceq'PackageIntegrity'){AssertPackage $ExtractedPackagePath $PackagePath}else{AdoptionSmoke $ExtractedPackagePath}
  Check ((Get-AiwReleaseFileIdentity $PackagePath)-ceq$beforeZip-and(Get-AiwReleasePackageFacts $ExtractedPackagePath).Canonical-ceq$beforeTree.Canonical) 'postbuild-leaves-original-zip-and-runtime-bytes-frozen'
  }
 }else{
  $sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'));$originalDefinition=Read-AiwTestGroupDefinition (Join-Path $PSScriptRoot 'test-groups.json')
  $sample=Join-Path $temp 'sample';$null=New-AiwTestSourceView $sourceRoot $sample $originalDefinition
  $v=Join-Path $sample 'framework/versions/2.0.0'
  $d=Read-AiwTestGroupDefinition (Join-Path $v 'tests/test-groups.json')
  $entry='framework/versions/2.0.0/tests/qualification-child.ps1';Put (Join-Path $sample $entry) "Write-Output 'PASS|qualification-target';Write-Output 'RESULT|1/1 passed|scope=qualification-child'"
  $sampleInventory=Read-AiwReleaseJson (Join-Path $v 'NORMATIVE_SURFACE_INVENTORY.json');$sampleInventory.schemaAndMechanicalInputs+=@('tests/qualification-child.ps1');WriteFixtureJson (Join-Path $v 'NORMATIVE_SURFACE_INVENTORY.json') $sampleInventory
  $d.schemaVersion=2;$d.groups=@([pscustomobject]@{id='integration.full-source';entry=$entry;arguments=@();phase='PREPACKAGE';requiredFor=@('FULL');casePolicy='OBSERVED_NAMED_CASES';requiredCaseIds=@('qualification-target');completionPattern='^RESULT\|1/1 passed\|scope=qualification-child$';dependencies=@();unknownDependencies=@();alwaysFresh=$true;fixturePolicy='WHOLE_VERSION';tools=@('pwsh')})
  WriteFixtureJson (Join-Path $v 'tests/test-groups.json') $d
  $view=New-AiwTestSourceView $sample (Join-Path $temp 'execution-view') $d;$definitionPath=Join-Path $view.Root 'framework/versions/2.0.0/tests/test-groups.json';$options=[pscustomobject]@{};$g=$d.groups[0]
  $before=Get-AiwTestDependencySnapshot $view.Root $definitionPath $d $g $options
  $process=Invoke-AiwTestProcess ([Environment]::ProcessPath) @(Get-AiwTestGroupArguments $view.Root $g $options) -WorkingDirectory $view.Root -EvidenceDirectory $raw -GroupId $g.id
  $after=Get-AiwTestDependencySnapshot $view.Root $definitionPath $d $g $options
  $empty=Join-Path $temp 'empty';$null=[IO.Directory]::CreateDirectory($empty);$recordPath=Join-Path $raw 'qualification-executed.json'
  $record=Complete-AiwTestGroupEvidence $recordPath $g $before $after $process @{status='CLEAN';root=$empty;entries=@();workers=@()}
  $suitePath=Join-Path $raw 'qualification-suite.json';Write-AiwTestJson $suitePath @{schemaVersion=2;phase='PREPACKAGE';definitionIdentity=(Get-AiwTestFileIdentity $definitionPath);requestedGroupIds=@($g.id);requiredGroupIds=@($g.id);records=@(@{groupId=$g.id;path=$recordPath;identity=(Get-AiwTestFileIdentity $recordPath);executionKind='EXECUTED';revalidation=$null});outcome='PASS';coverage='COMPLETE';options=$options;startedUtc=$record.startedUtc;endedUtc=$record.endedUtc;qualification='SOURCE_VALIDATION_ONLY';sourceRoot=$view.Root;sourceInputsRef=@{path=$view.ClosurePath;identity=$view.ClosureIdentity}}
  $bundle=Export-AiwTestPrepackageBundle $suitePath (Join-Path $temp 'export');$proof=Clone $bundle.Proof
  Copy-AiwTestAllowlist $bundle.BundleRoot $v @((Get-AiwReleaseTreeMembers (Join-Path $bundle.BundleRoot 'validation-evidence'))|ForEach-Object{'validation-evidence/'+$_.path})
$fixtureIndex=Read-AiwReleaseJson (Join-Path $v $proof.proofBundleRef.path)
  Check ($proof.schemaVersion-eq1-and$proof.mode-ceq'FULL_RUN'-and@($fixtureIndex.members|Where-Object kind -CIn @('CURRENT_SUITE','REVALIDATION')).Count-eq0) 'ordinary-alias-fixture-is-original-v1-full-run'
  $sealed=QualifySample $sample $proof
  Check ((Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $sample).State-ceq'SOURCE_QUALIFIED') 'schema3-current-reader-validates-real-execution-graph'
  Check ((Get-AiwReleaseValueIdentity (Assert-AiwReleaseReviewProjection $sealed))-ceq(Get-AiwReleaseValueIdentity (([Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($sealed.sourceReviewEvidence.reviewedManifestBase64)))|ConvertFrom-Json -Depth 100))) 'review-projection-preserves-all-nonreview-inputs'
  $moved=Join-Path $temp 'moved';if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($sample))-cne$temp-or[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($moved))-cne$temp){throw 'RELEASE_SAMPLE_MOVE_SCOPE'};[IO.Directory]::Move($sample,$moved);$v=Join-Path $moved 'framework/versions/2.0.0'
  Check ((Get-AiwReleaseQualification -VersionRoot $v -RuntimeRoot $moved).State-ceq'SOURCE_QUALIFIED'-and-not[IO.Directory]::Exists($sample)) 'schema3-portable-current-reader-validates-moved-original-bytes'
  Check ((Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $moved).State-ceq'SOURCE_QUALIFIED') 'ordinary-alias-moved-source-root-validates-original-bytes'
  QualificationContextRegression $moved
   NavigationColdQualificationRegression $moved
   NavigationSourceRuntimeRegression $moved
  $aliasSnapshot=Get-AiwTestFixtureSnapshot $moved
  try{
   $changedProof=Clone $proof;$indexPath=Join-Path $v $changedProof.proofBundleRef.path;$index=Read-AiwReleaseJson $indexPath
   $stderrAlias=@($index.aliases|Where-Object slot -CEQ '/stderr')[0];$stderrMember=@($index.members|Where-Object id -CEQ $stderrAlias.targetMemberId)[0]
   $ownerMember=@($index.members|Where-Object id -CEQ $stderrAlias.ownerMemberId)[0];$ownerPath=Join-Path $v $ownerMember.path
   $ownerIdentity=Get-AiwReleaseFileIdentity $ownerPath;$originalStderr=Clone (Read-AiwReleaseJson $ownerPath).stderr
   $ordinaryAliases=Get-AiwReleaseValueIdentity @($index.aliases|Where-Object slot -CNotIn @('PROCESS_LAUNCH_FOR_RUN','PHASE_EVENTS_FOR_RUN'))
   Put (Join-Path $v $stderrMember.path) 'Ordinary diagnostic text replacing the archived STDERR bytes.'
   $null=RebindBundle $moved $changedProof;$changedIndex=Read-AiwReleaseJson $indexPath
   $changedMember=@($changedIndex.members|Where-Object id -CEQ $stderrMember.id)[0];$owner=Read-AiwReleaseJson $ownerPath
   Check ($changedMember.kind-ceq'STDERR'-and$changedMember.identity-cne$originalStderr.identity-and(Get-AiwReleaseFileIdentity $ownerPath)-ceq$ownerIdentity-and$owner.stderr.path-ceq$originalStderr.path-and$owner.stderr.identity-ceq$originalStderr.identity-and(Get-AiwReleaseValueIdentity @($changedIndex.aliases|Where-Object slot -CNotIn @('PROCESS_LAUNCH_FOR_RUN','PHASE_EVENTS_FOR_RUN')))-ceq$ordinaryAliases) 'same-kind-stderr-counterexample-keeps-original-process-and-alias-references'
   Reject {Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $moved} '^RELEASE_ALIAS_BINDING$' 'ordinary-alias-source-root-rejects-rebound-different-stderr-bytes'
   Reject {Get-AiwReleaseQualification -VersionRoot $v -RuntimeRoot $moved} '^RELEASE_ALIAS_BINDING$' 'ordinary-alias-runtime-root-rejects-rebound-different-stderr-bytes'
  }finally{$null=Reset-AiwTestFixture $aliasSnapshot $moved}
  Check ((Get-AiwReleaseQualification -VersionRoot $v -SourceRoot $moved).State-ceq'SOURCE_QUALIFIED'-and(Get-AiwReleaseQualification -VersionRoot $v -RuntimeRoot $moved).State-ceq'SOURCE_QUALIFIED') 'ordinary-alias-restored-original-bytes-pass-both-public-paths'
  $composer=Import-Module (Join-Path $v 'scripts/ProcessRequirementComposition.psm1') -PassThru
  $compositionFacts=& $composer {param($version) Get-AiwCompositionReleaseFacts -VersionDirectory $version} $v
  Check ($compositionFacts.Facts.Canonical-ceq$sealed.canonical) 'composer-runtime-validates-qualified-proof'
  $damagePath=Join-Path $v 'CHANGELOG.md';$damageBytes=[IO.File]::ReadAllBytes($damagePath)
  try{[IO.File]::AppendAllText($damagePath,'controlled damage');Reject {& $composer {param($version) Get-AiwCompositionReleaseFacts -VersionDirectory $version} $v} 'CURRENT_INPUT_DRIFT' 'composer-runtime-rejects-damaged-proof'}finally{[IO.File]::WriteAllBytes($damagePath,$damageBytes)}
  # These bytes and qualifications are explicitly synthetic; this is a short
  # mechanism test of real builder/package/frontdoors, never a release claim.
  $zip=Join-Path $temp 'AI-Workspace-2.0.0-snapshot.1.zip'
  $build=$null
  try{
  $build=NativeTool (Join-Path $moved 'scripts/build-user-package.ps1') @{WorkspaceRoot=$moved;FrameworkVersion='2.0.0';Provisional=$true;Distribution='snapshot.1';OutputPath=$zip;Apply=$true}
  RequirePositiveNative $build ($build.Code-eq0-and$build.Text.Contains('BUILT_UNVERIFIED')-and[IO.File]::Exists($zip)) 'synthetic-schema3-real-builder-produces-unverified-new-zip' -Zip $zip -QualificationRoot $moved
  $packageRoot=Join-Path $temp 'actual-package';$packageFacts=Expand-AiwReleasePackage $zip $packageRoot
   Check (-not[IO.Directory]::Exists((Join-Path $packageRoot 'skills'))-and@($packageFacts.Manifest.files|Where-Object path -CLike 'skills/*').Count-eq0) 'navigation3-native-zip-has-no-root-skill-members'
  AssertPackage $packageRoot $zip
  $packageQualification=Get-AiwReleaseQualification -VersionRoot (Join-Path $packageRoot 'framework/versions/2.0.0') -RuntimeRoot $packageRoot
  $null=Assert-AiwReleaseBuildEvidence $build.ResultPath $zip $packageFacts $packageQualification
  $script:smokeZip=$zip;$zipBefore=Get-AiwReleaseFileIdentity $zip;AdoptionSmoke $packageRoot
  Check ((Get-AiwReleaseFileIdentity $zip)-ceq$zipBefore-and(Get-AiwReleasePackageFacts $packageRoot).Canonical-ceq$packageFacts.Canonical) 'synthetic-package-smoke-keeps-original-package-frozen'
  }catch{if($build){PreservePositiveFailure $build 'current-qualified-package-pipeline' -Zip $zip -QualificationRoot $moved -Failure $_};throw}
  if($Group-ceq'Mechanism'){StableEntryRegression $sourceRoot $originalDefinition}
  if($EntryPerformanceOnly){Write-Output ('PARTIAL|ENTRY_PERFORMANCE_ONLY|code=0|status=PASS|checks='+$passed+'|scope=synthetic-qualification-and-public-entry');return}
  if($Group-ceq'Mechanism'){
  $oldBuilderBytes=[Convert]::FromBase64String('W0NtZGxldEJpbmRpbmcoU3VwcG9ydHNTaG91bGRQcm9jZXNzPSR0cnVlKV0KcGFyYW0oCiAgICBbc3RyaW5nXSRXb3Jrc3BhY2VSb290LAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtzdHJpbmddJEZyYW1ld29ya1ZlcnNpb24sCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ10kT3V0cHV0UGF0aCwKICAgIFtzdHJpbmddJERpc3RyaWJ1dGlvbiwKICAgIFtzd2l0Y2hdJFByb3Zpc2lvbmFsLAogICAgW3N3aXRjaF0kSW50ZXJuYWxNYWludGVuYW5jZSwKICAgIFtzd2l0Y2hdJEFwcGx5CikKCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcKU2V0LVN0cmljdE1vZGUgLVZlcnNpb24gTGF0ZXN0CmlmICgkUFNWZXJzaW9uVGFibGUuUFNFZGl0aW9uIC1jbmUgJ0NvcmUnIC1vciAkUFNWZXJzaW9uVGFibGUuUFNWZXJzaW9uLk1ham9yIC1sdCA3KSB7CiAgICB0aHJvdyAnUE9XRVJTSEVMTDdfUkVRVUlSRUQnCn0KaWYgKC1ub3QgJFdvcmtzcGFjZVJvb3QpIHsKICAgICRXb3Jrc3BhY2VSb290ID0gU3BsaXQtUGF0aCAtUGFyZW50ICRQU1NjcmlwdFJvb3QKfQokd29ya3NwYWNlID0gW0lPLlBhdGhdOjpUcmltRW5kaW5nRGlyZWN0b3J5U2VwYXJhdG9yKFtJTy5QYXRoXTo6R2V0RnVsbFBhdGgoKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggJFdvcmtzcGFjZVJvb3QpKSkKJHZlcnNpb25Sb290ID0gSm9pbi1QYXRoICR3b3Jrc3BhY2UgKCdmcmFtZXdvcmsvdmVyc2lvbnMvJyArICRGcmFtZXdvcmtWZXJzaW9uKQppZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkdmVyc2lvblJvb3QgLVBhdGhUeXBlIENvbnRhaW5lcikpIHsKICAgIHRocm93ICdGUkFNRVdPUktfVkVSU0lPTl9NSVNTSU5HJwp9CmlmICgkRnJhbWV3b3JrVmVyc2lvbiAtY25vdG1hdGNoICdeXGQrXC5cZCtcLlxkKyQnKSB7CiAgICB0aHJvdyAnRlJBTUVXT1JLX1ZFUlNJT05fSU5WQUxJRCcKfQppZiAoJFBTQm91bmRQYXJhbWV0ZXJzLkNvbnRhaW5zS2V5KCdEaXN0cmlidXRpb24nKSAtYW5kCiAgICAkRGlzdHJpYnV0aW9uIC1jbm90bWF0Y2ggJ14oPzpzbmFwc2hvdFwuWzEtOV1bMC05XSp8cmVsZWFzZSlceicpIHsKICAgIHRocm93ICdQQUNLQUdFX0RJU1RSSUJVVElPTl9JTlZBTElEJwp9CgpmdW5jdGlvbiBHZXQtUmVsZWFzZVBheWxvYWRGYWN0cyhbc3RyaW5nXSRSb290LCBbc3RyaW5nXSRFeGNsdWRlZE1hbmlmZXN0UGF0aCkgewogICAgW3N0cmluZ1tdXSRwYXlsb2FkID0gQChHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkUm9vdCAtUmVjdXJzZSAtRmlsZSAtRm9yY2UgfAogICAgICAgIFdoZXJlLU9iamVjdCB7IFtJTy5QYXRoXTo6R2V0RnVsbFBhdGgoJF8uRnVsbE5hbWUpIC1jbmUgW0lPLlBhdGhdOjpHZXRGdWxsUGF0aCgkRXhjbHVkZWRNYW5pZmVzdFBhdGgpIH0gfAogICAgICAgIEZvckVhY2gtT2JqZWN0IHsgJF8uRnVsbE5hbWUuU3Vic3RyaW5nKCRSb290Lkxlbmd0aCArIDEpLlJlcGxhY2UoJ1wnLCAnLycpIH0pCiAgICBbQXJyYXldOjpTb3J0KCRwYXlsb2FkLCBbU3RyaW5nQ29tcGFyZXJdOjpPcmRpbmFsKQogICAgJHJvd3MgPSBbQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ11dOjpuZXcoKQogICAgW2ludDY0XSR0b3RhbEJ5dGVzID0gMAogICAgZm9yZWFjaCAoJHJlbGF0aXZlIGluICRwYXlsb2FkKSB7CiAgICAgICAgJGJ5dGVzID0gW0lPLkZpbGVdOjpSZWFkQWxsQnl0ZXMoKEpvaW4tUGF0aCAkUm9vdCAkcmVsYXRpdmUpKQogICAgICAgICR0b3RhbEJ5dGVzICs9ICRieXRlcy5MZW5ndGgKICAgICAgICAkaWRlbnRpdHkgPSBbQ29udmVydF06OlRvSGV4U3RyaW5nKFtTZWN1cml0eS5DcnlwdG9ncmFwaHkuU0hBMjU2XTo6SGFzaERhdGEoJGJ5dGVzKSkKICAgICAgICAkcm93cy5BZGQoJHJlbGF0aXZlICsgJ3wnICsgJGJ5dGVzLkxlbmd0aCArICd8JyArICRpZGVudGl0eSkKICAgIH0KICAgICRjYW5vbmljYWxCeXRlcyA9IFtUZXh0LlVURjhFbmNvZGluZ106Om5ldygkZmFsc2UpLkdldEJ5dGVzKFtzdHJpbmddOjpKb2luKCJgbiIsICRyb3dzKSkKICAgIFtwc2N1c3RvbW9iamVjdF1AewogICAgICAgIEZpbGVDb3VudCA9ICRwYXlsb2FkLkNvdW50CiAgICAgICAgVG90YWxCeXRlcyA9ICR0b3RhbEJ5dGVzCiAgICAgICAgQ2Fub25pY2FsID0gW0NvbnZlcnRdOjpUb0hleFN0cmluZyhbU2VjdXJpdHkuQ3J5cHRvZ3JhcGh5LlNIQTI1Nl06Okhhc2hEYXRhKCRjYW5vbmljYWxCeXRlcykpCiAgICB9Cn0KCmZ1bmN0aW9uIFRlc3QtSnNvbkludGVnZXIoJFZhbHVlKSB7CiAgICByZXR1cm4gJFZhbHVlIC1pcyBbYnl0ZV0gLW9yICRWYWx1ZSAtaXMgW3NieXRlXSAtb3IgJFZhbHVlIC1pcyBbaW50MTZdIC1vcgogICAgICAgICRWYWx1ZSAtaXMgW3VpbnQxNl0gLW9yICRWYWx1ZSAtaXMgW2ludDMyXSAtb3IgJFZhbHVlIC1pcyBbdWludDMyXSAtb3IKICAgICAgICAkVmFsdWUgLWlzIFtpbnQ2NF0gLW9yICRWYWx1ZSAtaXMgW3VpbnQ2NF0KfQoKZnVuY3Rpb24gVGVzdC1JZGVudGl0eShbb2JqZWN0XSRWYWx1ZSkgewogICAgcmV0dXJuICRWYWx1ZSAtaXMgW3N0cmluZ10gLWFuZCBbc3RyaW5nXSRWYWx1ZSAtY21hdGNoICdeXGQrXHxbQS1GMC05XXs2NH0kJwp9CgpmdW5jdGlvbiBBc3NlcnQtRXhhY3RKc29uT2JqZWN0RmllbGRzKFtUZXh0Lkpzb24uSnNvbkVsZW1lbnRdJEVsZW1lbnQsIFtzdHJpbmdbXV0kRXhwZWN0ZWQpIHsKICAgIGlmICgkRWxlbWVudC5WYWx1ZUtpbmQgLWNuZSBbVGV4dC5Kc29uLkpzb25WYWx1ZUtpbmRdOjpPYmplY3QpIHsgdGhyb3cgJ0pTT05fT0JKRUNUX1JFUVVJUkVEJyB9CiAgICAkbmFtZXMgPSBAKCRFbGVtZW50LkVudW1lcmF0ZU9iamVjdCgpIHwgRm9yRWFjaC1PYmplY3QgeyAkXy5OYW1lIH0pCiAgICBpZiAoJG5hbWVzLkNvdW50IC1uZSAkRXhwZWN0ZWQuQ291bnQgLW9yIEAoJG5hbWVzIHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKS5Db3VudCAtbmUgJG5hbWVzLkNvdW50IC1vcgogICAgICAgIEAoJEV4cGVjdGVkIHwgV2hlcmUtT2JqZWN0IHsgJF8gLWNub3RpbiAkbmFtZXMgfSkuQ291bnQgLW5lIDApIHsKICAgICAgICB0aHJvdyAnSlNPTl9GSUVMRF9TRVRfTUlTTUFUQ0gnCiAgICB9Cn0KCiRtYW5pZmVzdFBhdGggPSBKb2luLVBhdGggJHZlcnNpb25Sb290ICdSRUxFQVNFX01BTklGRVNULmpzb24nCiRtYW5pZmVzdFJhdyA9IFtJTy5GaWxlXTo6UmVhZEFsbFRleHQoJG1hbmlmZXN0UGF0aCwgW1RleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSwgJHRydWUpKQokbWFuaWZlc3QgPSAkbWFuaWZlc3RSYXcgfCBDb252ZXJ0RnJvbS1Kc29uCiR2ZXJzaW9uUGF0aCA9IEpvaW4tUGF0aCAkdmVyc2lvblJvb3QgJ1ZFUlNJT04uanNvbicKJHZlcnNpb25SYXcgPSBbSU8uRmlsZV06OlJlYWRBbGxUZXh0KCR2ZXJzaW9uUGF0aCwgW1RleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSwgJHRydWUpKQokdmVyc2lvbiA9ICR2ZXJzaW9uUmF3IHwgQ29udmVydEZyb20tSnNvbgppZiAoW3N0cmluZ10kbWFuaWZlc3QudmVyc2lvbiAtY25lICRGcmFtZXdvcmtWZXJzaW9uIC1vcgogICAgW3N0cmluZ10kdmVyc2lvbi52ZXJzaW9uIC1jbmUgJEZyYW1ld29ya1ZlcnNpb24gLW9yCiAgICBbc3RyaW5nXSRtYW5pZmVzdC5saWZlY3ljbGUgLWNuZSBbc3RyaW5nXSR2ZXJzaW9uLmxpZmVjeWNsZSkgewogICAgdGhyb3cgJ0ZSQU1FV09SS19NQU5JRkVTVF9WRVJTSU9OJwp9CiRnYXRlRXJyb3IgPSBpZiAoJFByb3Zpc2lvbmFsKSB7ICdQUk9WSVNJT05BTF9QQUNLQUdFX1JFVklFV19SRVFVSVJFRCcgfSBlbHNlIHsgJ1NUQUJMRV9QQUNLQUdFX1JFUVVJUkVEJyB9CnRyeSB7CiAgICAkZG9jdW1lbnQgPSBbVGV4dC5Kc29uLkpzb25Eb2N1bWVudF06OlBhcnNlKCRtYW5pZmVzdFJhdykKICAgIHRyeSB7CiAgICAgICAgQXNzZXJ0LUV4YWN0SnNvbk9iamVjdEZpZWxkcyAkZG9jdW1lbnQuUm9vdEVsZW1lbnQgQCgnc2NoZW1hVmVyc2lvbicsJ3ZlcnNpb24nLCdsaWZlY3ljbGUnLCdyZWxlYXNlQ2xhc3MnLCdzY29wZScsJ2FsZ29yaXRobScsJ2ZpbGVDb3VudCcsJ3RvdGFsQnl0ZXMnLCdjYW5vbmljYWwnLCdiYXNlbGluZScsJ3NvdXJjZVJldmlldycsJ3NvdXJjZUNhbmRpZGF0ZScsJ3JlbGVhc2VJbnRlZ3JhdGlvbicsJ2NvbXBsZXRlU3VpdGUnLCdzb3VyY2VSZXZpZXdFdmlkZW5jZScpCiAgICAgICAgQXNzZXJ0LUV4YWN0SnNvbk9iamVjdEZpZWxkcyAoJGRvY3VtZW50LlJvb3RFbGVtZW50LkdldFByb3BlcnR5KCdjb21wbGV0ZVN1aXRlJykpIEAoJ3N0YXR1cycsJ3Bhc3NlZCcsJ3RvdGFsJywncGF5bG9hZENhbm9uaWNhbCcsJ2V2aWRlbmNlSWRlbnRpdHknKQogICAgICAgIEFzc2VydC1FeGFjdEpzb25PYmplY3RGaWVsZHMgKCRkb2N1bWVudC5Sb290RWxlbWVudC5HZXRQcm9wZXJ0eSgnc291cmNlUmV2aWV3RXZpZGVuY2UnKSkgQCgnc3RhdHVzJywncmV2aWV3ZXInLCdwYWNrYWdlSWRlbnRpdHknLCdyZXZpZXdlZFBheWxvYWRDYW5vbmljYWwnLCdyZXZpZXdlZE1hbmlmZXN0SWRlbnRpdHknKQogICAgfQogICAgZmluYWxseSB7ICRkb2N1bWVudC5EaXNwb3NlKCkgfQp9CmNhdGNoIHsgdGhyb3cgJGdhdGVFcnJvciB9CiRyZWxlYXNlRmFjdHMgPSBHZXQtUmVsZWFzZVBheWxvYWRGYWN0cyAkdmVyc2lvblJvb3QgJG1hbmlmZXN0UGF0aAppZiAoW2ludF0kbWFuaWZlc3QuZmlsZUNvdW50IC1uZSAkcmVsZWFzZUZhY3RzLkZpbGVDb3VudCAtb3IKICAgIFtpbnQ2NF0kbWFuaWZlc3QudG90YWxCeXRlcyAtbmUgJHJlbGVhc2VGYWN0cy5Ub3RhbEJ5dGVzIC1vcgogICAgW3N0cmluZ10kbWFuaWZlc3QuY2Fub25pY2FsIC1jbmUgJHJlbGVhc2VGYWN0cy5DYW5vbmljYWwpIHsKICAgIHRocm93ICdGUkFNRVdPUktfUkVMRUFTRV9QQVlMT0FEX0RSSUZUJwp9CiRzdWl0ZSA9ICRtYW5pZmVzdC5jb21wbGV0ZVN1aXRlCiRyZXZpZXcgPSAkbWFuaWZlc3Quc291cmNlUmV2aWV3RXZpZGVuY2UKJGNvbW1vbkV2aWRlbmNlVmFsaWQgPQogICAgKFRlc3QtSnNvbkludGVnZXIgJG1hbmlmZXN0LnNjaGVtYVZlcnNpb24pIC1hbmQgW2ludDY0XSRtYW5pZmVzdC5zY2hlbWFWZXJzaW9uIC1lcSAyIC1hbmQKICAgICRtYW5pZmVzdC52ZXJzaW9uIC1pcyBbc3RyaW5nXSAtYW5kIFtzdHJpbmddJG1hbmlmZXN0LnZlcnNpb24gLWNlcSAkRnJhbWV3b3JrVmVyc2lvbiAtYW5kCiAgICAkbWFuaWZlc3QubGlmZWN5Y2xlIC1pcyBbc3RyaW5nXSAtYW5kICRtYW5pZmVzdC5zb3VyY2VSZXZpZXcgLWlzIFtzdHJpbmddIC1hbmQgW3N0cmluZ10kbWFuaWZlc3Quc291cmNlUmV2aWV3IC1jZXEgJ0FQUFJPVkVEJyAtYW5kCiAgICAkbWFuaWZlc3Quc291cmNlQ2FuZGlkYXRlIC1pcyBbc3RyaW5nXSAtYW5kIC1ub3QgW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZShbc3RyaW5nXSRtYW5pZmVzdC5zb3VyY2VDYW5kaWRhdGUpIC1hbmQgW3N0cmluZ10kbWFuaWZlc3Quc291cmNlQ2FuZGlkYXRlIC1jbmUgJ1BFTkRJTkcnIC1hbmQKICAgICRtYW5pZmVzdC5yZWxlYXNlSW50ZWdyYXRpb24gLWlzIFtzdHJpbmddIC1hbmQKICAgIChUZXN0LUpzb25JbnRlZ2VyICRtYW5pZmVzdC5maWxlQ291bnQpIC1hbmQgW2ludDY0XSRtYW5pZmVzdC5maWxlQ291bnQgLWVxIFtpbnQ2NF0kcmVsZWFzZUZhY3RzLkZpbGVDb3VudCAtYW5kCiAgICAoVGVzdC1Kc29uSW50ZWdlciAkbWFuaWZlc3QudG90YWxCeXRlcykgLWFuZCBbaW50NjRdJG1hbmlmZXN0LnRvdGFsQnl0ZXMgLWVxIFtpbnQ2NF0kcmVsZWFzZUZhY3RzLlRvdGFsQnl0ZXMgLWFuZAogICAgJG1hbmlmZXN0LmNhbm9uaWNhbCAtaXMgW3N0cmluZ10gLWFuZCBbc3RyaW5nXSRtYW5pZmVzdC5jYW5vbmljYWwgLWNlcSAkcmVsZWFzZUZhY3RzLkNhbm9uaWNhbCAtYW5kCiAgICAkc3VpdGUgLWlzIFtwc2N1c3RvbW9iamVjdF0gLWFuZCAkc3VpdGUuc3RhdHVzIC1pcyBbc3RyaW5nXSAtYW5kIFtzdHJpbmddJHN1aXRlLnN0YXR1cyAtY2VxICdQQVNTJyAtYW5kCiAgICAoVGVzdC1Kc29uSW50ZWdlciAkc3VpdGUucGFzc2VkKSAtYW5kIChUZXN0LUpzb25JbnRlZ2VyICRzdWl0ZS50b3RhbCkgLWFuZCBbaW50NjRdJHN1aXRlLnBhc3NlZCAtZ2UgMSAtYW5kIFtpbnQ2NF0kc3VpdGUucGFzc2VkIC1lcSBbaW50NjRdJHN1aXRlLnRvdGFsIC1hbmQKICAgICRzdWl0ZS5wYXlsb2FkQ2Fub25pY2FsIC1pcyBbc3RyaW5nXSAtYW5kIFtzdHJpbmddJHN1aXRlLnBheWxvYWRDYW5vbmljYWwgLWNlcSAkcmVsZWFzZUZhY3RzLkNhbm9uaWNhbCAtYW5kIChUZXN0LUlkZW50aXR5ICRzdWl0ZS5ldmlkZW5jZUlkZW50aXR5KSAtYW5kCiAgICAkcmV2aWV3IC1pcyBbcHNjdXN0b21vYmplY3RdIC1hbmQgJHJldmlldy5zdGF0dXMgLWlzIFtzdHJpbmddIC1hbmQgW3N0cmluZ10kcmV2aWV3LnN0YXR1cyAtY2VxICdBUFBST1ZFRCcgLWFuZAogICAgJHJldmlldy5yZXZpZXdlciAtaXMgW3N0cmluZ10gLWFuZCAtbm90IFtzdHJpbmddOjpJc051bGxPcldoaXRlU3BhY2UoW3N0cmluZ10kcmV2aWV3LnJldmlld2VyKSAtYW5kIFtzdHJpbmddJHJldmlldy5yZXZpZXdlciAtY25vdGluIEAoJ05PTkUnLCdQRU5ESU5HJykgLWFuZAogICAgKFRlc3QtSWRlbnRpdHkgJHJldmlldy5wYWNrYWdlSWRlbnRpdHkpIC1hbmQgJHJldmlldy5yZXZpZXdlZFBheWxvYWRDYW5vbmljYWwgLWlzIFtzdHJpbmddIC1hbmQKICAgIFtzdHJpbmddJHJldmlldy5yZXZpZXdlZFBheWxvYWRDYW5vbmljYWwgLWNlcSAkcmVsZWFzZUZhY3RzLkNhbm9uaWNhbCAtYW5kIChUZXN0LUlkZW50aXR5ICRyZXZpZXcucmV2aWV3ZWRNYW5pZmVzdElkZW50aXR5KQokbW9kZUV2aWRlbmNlVmFsaWQgPSBpZiAoJFByb3Zpc2lvbmFsKSB7CiAgICBbc3RyaW5nXSRtYW5pZmVzdC5saWZlY3ljbGUgLWNlcSAnQ0FORElEQVRFJyAtYW5kCiAgICAkdmVyc2lvbi5jb25zdW1hYmxlIC1pcyBbYm9vbF0gLWFuZCAtbm90IFtib29sXSR2ZXJzaW9uLmNvbnN1bWFibGUgLWFuZAogICAgJHZlcnNpb24ucHJvamVjdFBpbkVsaWdpYmxlIC1pcyBbYm9vbF0gLWFuZCAtbm90IFtib29sXSR2ZXJzaW9uLnByb2plY3RQaW5FbGlnaWJsZSAtYW5kCiAgICBbc3RyaW5nXSRtYW5pZmVzdC5yZWxlYXNlSW50ZWdyYXRpb24gLWNlcSAnUEVORElORycKfQplbHNlIHsKICAgIFtzdHJpbmddJG1hbmlmZXN0LmxpZmVjeWNsZSAtY2VxICdTVEFCTEUnIC1hbmQKICAgICR2ZXJzaW9uLmNvbnN1bWFibGUgLWlzIFtib29sXSAtYW5kIFtib29sXSR2ZXJzaW9uLmNvbnN1bWFibGUgLWFuZAogICAgJHZlcnNpb24ucHJvamVjdFBpbkVsaWdpYmxlIC1pcyBbYm9vbF0gLWFuZCBbYm9vbF0kdmVyc2lvbi5wcm9qZWN0UGluRWxpZ2libGUgLWFuZAogICAgLW5vdCBbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKFtzdHJpbmddJG1hbmlmZXN0LnJlbGVhc2VJbnRlZ3JhdGlvbikgLWFuZCBbc3RyaW5nXSRtYW5pZmVzdC5yZWxlYXNlSW50ZWdyYXRpb24gLWNuZSAnUEVORElORycKfQppZiAoLW5vdCAkY29tbW9uRXZpZGVuY2VWYWxpZCAtb3IgLW5vdCAkbW9kZUV2aWRlbmNlVmFsaWQpIHsKICAgIHRocm93ICRnYXRlRXJyb3IKfQoKJGRpc3RyaWJ1dGlvbklkID0gJEZyYW1ld29ya1ZlcnNpb24KJGRpc3RyaWJ1dGlvbk5vdGljZSA9ICfmraTljIXmnKrmjIflrprliIblj5Hkv67orqLmoIfor4bvvJvmlofku7blkI3kuI3or4HmmI7niYjmnKzotYTmoLzjgIInCmlmICgkUFNCb3VuZFBhcmFtZXRlcnMuQ29udGFpbnNLZXkoJ0Rpc3RyaWJ1dGlvbicpKSB7CiAgICBpZiAoKCREaXN0cmlidXRpb24gLWNlcSAncmVsZWFzZScgLWFuZCAkUHJvdmlzaW9uYWwpIC1vcgogICAgICAgICgkRGlzdHJpYnV0aW9uLlN0YXJ0c1dpdGgoJ3NuYXBzaG90LicsIFtTdHJpbmdDb21wYXJpc29uXTo6T3JkaW5hbCkgLWFuZCAtbm90ICRQcm92aXNpb25hbCkpIHsKICAgICAgICB0aHJvdyAnUEFDS0FHRV9ESVNUUklCVVRJT05fTElGRUNZQ0xFX01JU01BVENIJwogICAgfQogICAgJGRpc3RyaWJ1dGlvbklkID0gJEZyYW1ld29ya1ZlcnNpb24gKyAnLScgKyAkRGlzdHJpYnV0aW9uCiAgICAkcGFja2FnZVByZWZpeCA9IGlmICgkSW50ZXJuYWxNYWludGVuYW5jZSkgeyAnQUktV29ya3NwYWNlLU1haW50ZW5hbmNlLScgfSBlbHNlIHsgJ0FJLVdvcmtzcGFjZS0nIH0KICAgICRleHBlY3RlZE5hbWUgPSAkcGFja2FnZVByZWZpeCArICRkaXN0cmlidXRpb25JZCArICcuemlwJwogICAgaWYgKFtJTy5QYXRoXTo6R2V0RmlsZU5hbWUoJE91dHB1dFBhdGgpIC1jbmUgJGV4cGVjdGVkTmFtZSkgewogICAgICAgIHRocm93ICgnUEFDS0FHRV9ESVNUUklCVVRJT05fRklMRU5BTUVfTUlTTUFUQ0h8JyArICRleHBlY3RlZE5hbWUpCiAgICB9CiAgICAkZGlzdHJpYnV0aW9uTm90aWNlID0gaWYgKCRQcm92aXNpb25hbCkgewogICAgICAgICfov5nmmK8gQ0FORElEQVRFIOW/q+eFp+WMhe+8jOS7jeS4jeWPr+aZrumAmuazqOWGjOaIlumHh+eUqO+8m+S7heS+m+aYjuehruaJueWHhueahOacrOWcsOivleeCueOAgicKICAgIH0KICAgIGVsc2UgewogICAgICAgICfov5nmmK/pgJrov4fml6LmnIkgU1RBQkxFIOaJk+WMhei1hOagvOagoemqjOeahOWPkeihjOWMhe+8m+mhueebruS7jeaMieiHqui6q+aOiOadg+aYvuW8j+mHh+eUqOOAgicKICAgIH0KfQoKSW1wb3J0LU1vZHVsZSAoSm9pbi1QYXRoICRQU1NjcmlwdFJvb3QgJ1Byb2plY3RBZG9wdGlvblN0YXRlLnBzbTEnKSAtRm9yY2UKJG5hdmlnYXRpb249R2V0LUFpd05hdmlnYXRpb25Db250cmFjdCAoUmVhZC1BaXdQcm9qZWN0SnNvbiAoSm9pbi1QYXRoICR2ZXJzaW9uUm9vdCAnVE9PTENIQUlOLmpzb24nKSAnUEFDS0FHRV9UT09MQ0hBSU4nKS5WYWx1ZQokZml4ZWRNYXBwaW5ncyA9IEAoCiAgICBbcHNjdXN0b21vYmplY3RdQHsgc291cmNlID0gJ2ZyYW1ld29yay91c2VyLXBhY2thZ2UvUkVBRE1FLm1kJzsgdGFyZ2V0ID0gJ1JFQURNRS5tZCc7IHRlbXBsYXRlID0gJHRydWUgfSwKICAgIFtwc2N1c3RvbW9iamVjdF1AeyBzb3VyY2UgPSAnZnJhbWV3b3JrL3VzZXItcGFja2FnZS9BR0VOVFMubWQnOyB0YXJnZXQgPSAnQUdFTlRTLm1kJzsgdGVtcGxhdGUgPSAkdHJ1ZSB9LAogICAgW3BzY3VzdG9tb2JqZWN0XUB7IHNvdXJjZSA9ICdmcmFtZXdvcmsvUFJPSkVDVF9BRE9QVElPTi5tZCc7IHRhcmdldCA9ICdmcmFtZXdvcmsvUFJPSkVDVF9BRE9QVElPTi5tZCc7IHRlbXBsYXRlID0gJGZhbHNlIH0sCiAgICBbcHNjdXN0b21vYmplY3RdQHsgc291cmNlID0gJ0xJQ0VOU0UnOyB0YXJnZXQgPSAnTElDRU5TRSc7IHRlbXBsYXRlID0gJGZhbHNlIH0sCiAgICBbcHNjdXN0b21vYmplY3RdQHsgc291cmNlID0gJ3NjcmlwdHMvTWFpbnRlbmFuY2VPdmVybGF5LnBzbTEnOyB0YXJnZXQgPSAnc2NyaXB0cy9NYWludGVuYW5jZU92ZXJsYXkucHNtMSc7IHRlbXBsYXRlID0gJGZhbHNlIH0sCiAgICBbcHNjdXN0b21vYmplY3RdQHsgc291cmNlID0gJ3NjcmlwdHMvUHJvamVjdEFkb3B0aW9uUHJvamVjdGlvbi5wc20xJzsgdGFyZ2V0ID0gJ3NjcmlwdHMvUHJvamVjdEFkb3B0aW9uUHJvamVjdGlvbi5wc20xJzsgdGVtcGxhdGUgPSAkZmFsc2UgfSwKICAgIFtwc2N1c3RvbW9iamVjdF1AeyBzb3VyY2UgPSAnc2NyaXB0cy9Qcm9qZWN0QWRvcHRpb25TdGF0ZS5wc20xJzsgdGFyZ2V0ID0gJ3NjcmlwdHMvUHJvamVjdEFkb3B0aW9uU3RhdGUucHNtMSc7IHRlbXBsYXRlID0gJGZhbHNlIH0sCiAgICBbcHNjdXN0b21vYmplY3RdQHsgc291cmNlID0gJ3NjcmlwdHMvUHJvamVjdENvcnJlY3Rpb25MaWZlY3ljbGUucHNtMSc7IHRhcmdldCA9ICdzY3JpcHRzL1Byb2plY3RDb3JyZWN0aW9uTGlmZWN5Y2xlLnBzbTEnOyB0ZW1wbGF0ZSA9ICRmYWxzZSB9LAogICAgW3BzY3VzdG9tb2JqZWN0XUB7IHNvdXJjZSA9ICdzY3JpcHRzL1Byb2plY3RBZG9wdGlvblRyYW5zYWN0aW9uLnBzbTEnOyB0YXJnZXQgPSAnc2NyaXB0cy9Qcm9qZWN0QWRvcHRpb25UcmFuc2FjdGlvbi5wc20xJzsgdGVtcGxhdGUgPSAkZmFsc2UgfSwKICAgIFtwc2N1c3RvbW9iamVjdF1AeyBzb3VyY2UgPSAnc2NyaXB0cy9yZWdpc3Rlci1wcm9qZWN0LnBzMSc7IHRhcmdldCA9ICdzY3JpcHRzL3JlZ2lzdGVyLXByb2plY3QucHMxJzsgdGVtcGxhdGUgPSAkZmFsc2UgfSwKICAgIFtwc2N1c3RvbW9iamVjdF1AeyBzb3VyY2UgPSAnc2NyaXB0cy91cGdyYWRlLXByb2plY3QucHMxJzsgdGFyZ2V0ID0gJ3NjcmlwdHMvdXBncmFkZS1wcm9qZWN0LnBzMSc7IHRlbXBsYXRlID0gJGZhbHNlIH0sCiAgICBbcHNjdXN0b21vYmplY3RdQHsgc291cmNlID0gJG5hdmlnYXRpb24uQ2Fub25pY2FsU2tpbGxQYXRoOyB0YXJnZXQgPSAkbmF2aWdhdGlvbi5DYW5vbmljYWxTa2lsbFBhdGg7IHRlbXBsYXRlID0gJGZhbHNlIH0KKQppZigkSW50ZXJuYWxNYWludGVuYW5jZSl7CiAgICBpZigtbm90JFBTQm91bmRQYXJhbWV0ZXJzLkNvbnRhaW5zS2V5KCdEaXN0cmlidXRpb24nKSl7dGhyb3cgJ0lOVEVSTkFMX0RJU1RSSUJVVElPTl9SRVFVSVJFRCd9CiAgICBmb3JlYWNoKCRyZWxhdGl2ZSBpbiBAKCdzY3JpcHRzL3Jlc29sdmUtZnJhbWV3b3JrLW1haW50ZW5hbmNlLXRhcmdldC5wczEnLCdzY3JpcHRzL2NoZWNrLWZyYW1ld29yay1tYWludGVuYW5jZS1hdXRob3JpemF0aW9uLnBzMScsJ3NjcmlwdHMvcmVzb2x2ZS1mcmFtZXdvcmstbWFpbnRlbmFuY2UtcHJvY2Vzcy1yZXF1aXJlbWVudHMucHMxJywnc2NyaXB0cy9pbnZva2UtZnJhbWV3b3JrLW1haW50ZW5hbmNlLXNhZmUtZ2l0LnBzMScsJ2ZyYW1ld29yay9GUkFNRVdPUktfUkVMRUFTRS5tZCcpKXsKICAgICAgICAkZml4ZWRNYXBwaW5ncyArPSBbcHNjdXN0b21vYmplY3RdQHtzb3VyY2U9JHJlbGF0aXZlO3RhcmdldD0kcmVsYXRpdmU7dGVtcGxhdGU9JGZhbHNlfQogICAgfQogICAgZm9yZWFjaCgkZmlsZSBpbiBHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICR3b3Jrc3BhY2UgJ2ZyYW1ld29yay9tYWludGVuYW5jZS1vdmVybGF5JykgLUZpbGUpewogICAgICAgICRyZWxhdGl2ZT0nZnJhbWV3b3JrL21haW50ZW5hbmNlLW92ZXJsYXkvJyskZmlsZS5OYW1lCiAgICAgICAgJGZpeGVkTWFwcGluZ3MgKz0gW3BzY3VzdG9tb2JqZWN0XUB7c291cmNlPSRyZWxhdGl2ZTt0YXJnZXQ9JHJlbGF0aXZlO3RlbXBsYXRlPSRmYWxzZX0KICAgIH0KfQokbWFwcGluZ3MgPSBbQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W29iamVjdF1dOjpuZXcoKQpmb3JlYWNoICgkbWFwcGluZyBpbiAkZml4ZWRNYXBwaW5ncykgeyAkbWFwcGluZ3MuQWRkKCRtYXBwaW5nKSB9CmZvcmVhY2ggKCRmaWxlIGluIEAoR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJHZlcnNpb25Sb290IC1SZWN1cnNlIC1GaWxlIC1Gb3JjZSkpIHsKICAgICRyZWxhdGl2ZSA9IFtJTy5QYXRoXTo6R2V0UmVsYXRpdmVQYXRoKCR3b3Jrc3BhY2UsICRmaWxlLkZ1bGxOYW1lKS5SZXBsYWNlKCdcJywgJy8nKQogICAgJG1hcHBpbmdzLkFkZChbcHNjdXN0b21vYmplY3RdQHsgc291cmNlID0gJHJlbGF0aXZlOyB0YXJnZXQgPSAkcmVsYXRpdmU7IHRlbXBsYXRlID0gJGZhbHNlIH0pCn0KJG9yZGVyZWRNYXBwaW5ncyA9IEAoJG1hcHBpbmdzIHwgU29ydC1PYmplY3QgLVByb3BlcnR5IHRhcmdldCkKJHRhcmdldHMgPSBbQ29sbGVjdGlvbnMuR2VuZXJpYy5IYXNoU2V0W3N0cmluZ11dOjpuZXcoW1N0cmluZ0NvbXBhcmVyXTo6T3JkaW5hbCkKJHJlY29yZHMgPSBbQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W29iamVjdF1dOjpuZXcoKQpmb3JlYWNoICgkbWFwcGluZyBpbiAkb3JkZXJlZE1hcHBpbmdzKSB7CiAgICAkc291cmNlUmVsYXRpdmUgPSBbc3RyaW5nXSRtYXBwaW5nLnNvdXJjZQogICAgJHRhcmdldFJlbGF0aXZlID0gW3N0cmluZ10kbWFwcGluZy50YXJnZXQKICAgIGlmICgtbm90ICR0YXJnZXRzLkFkZCgkdGFyZ2V0UmVsYXRpdmUpKSB7IHRocm93ICgnUEFDS0FHRV9UQVJHRVRfRFVQTElDQVRFfCcgKyAkdGFyZ2V0UmVsYXRpdmUpIH0KICAgIGlmICgkdGFyZ2V0UmVsYXRpdmUuU3RhcnRzV2l0aCgnLmdpdC8nLCBbU3RyaW5nQ29tcGFyaXNvbl06Ok9yZGluYWxJZ25vcmVDYXNlKSAtb3IKICAgICAgICAkdGFyZ2V0UmVsYXRpdmUuQ29udGFpbnMoJy9ydW50aW1lLycsIFtTdHJpbmdDb21wYXJpc29uXTo6T3JkaW5hbElnbm9yZUNhc2UpKSB7CiAgICAgICAgdGhyb3cgKCdQQUNLQUdFX1BBVEhfRk9SQklEREVOfCcgKyAkdGFyZ2V0UmVsYXRpdmUpCiAgICB9CiAgICAkc291cmNlUGF0aCA9IEpvaW4tUGF0aCAkd29ya3NwYWNlICRzb3VyY2VSZWxhdGl2ZQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHNvdXJjZVBhdGggLVBhdGhUeXBlIExlYWYpKSB7CiAgICAgICAgdGhyb3cgKCdQQUNLQUdFX0RFUEVOREVOQ1lfTUlTU0lOR3wnICsgJHNvdXJjZVJlbGF0aXZlKQogICAgfQogICAgJGJ5dGVzID0gaWYgKFtib29sXSRtYXBwaW5nLnRlbXBsYXRlKSB7CiAgICAgICAgJHRleHQgPSBbSU8uRmlsZV06OlJlYWRBbGxUZXh0KCRzb3VyY2VQYXRoLCBbVGV4dC5VVEY4RW5jb2RpbmddOjpuZXcoJGZhbHNlLCAkdHJ1ZSkpLgogICAgICAgICAgICBSZXBsYWNlKCd7e0ZSQU1FV09SS19WRVJTSU9OfX0nLCAkRnJhbWV3b3JrVmVyc2lvbikuCiAgICAgICAgICAgIFJlcGxhY2UoJ3t7RElTVFJJQlVUSU9OX0lEfX0nLCAkZGlzdHJpYnV0aW9uSWQpLgogICAgICAgICAgICBSZXBsYWNlKCd7e0RJU1RSSUJVVElPTl9OT1RJQ0V9fScsICRkaXN0cmlidXRpb25Ob3RpY2UpCiAgICAgICAgaWYgKCR0ZXh0IC1jbWF0Y2ggJ1x7XHtbQS1aX10rXH1cfScpIHsgdGhyb3cgKCdQQUNLQUdFX1RFTVBMQVRFX1VOUkVTT0xWRUR8JyArICRzb3VyY2VSZWxhdGl2ZSkgfQogICAgICAgIFtUZXh0LlVURjhFbmNvZGluZ106Om5ldygkZmFsc2UpLkdldEJ5dGVzKCR0ZXh0KQogICAgfQogICAgZWxzZWlmKCRzb3VyY2VSZWxhdGl2ZS1jZXEnZnJhbWV3b3JrL1BST0pFQ1RfQURPUFRJT04ubWQnKSB7CiAgICAgICAgJHRleHQ9W0lPLkZpbGVdOjpSZWFkQWxsVGV4dCgkc291cmNlUGF0aCxbVGV4dC5VVEY4RW5jb2RpbmddOjpuZXcoJGZhbHNlLCR0cnVlKSkuUmVwbGFjZSgndmVyc2lvbnMvMS4xNi4wLycsJ3ZlcnNpb25zLycrJEZyYW1ld29ya1ZlcnNpb24rJy8nKQogICAgICAgIFtUZXh0LlVURjhFbmNvZGluZ106Om5ldygkZmFsc2UpLkdldEJ5dGVzKCR0ZXh0KQogICAgfQogICAgZWxzZSB7IFtJTy5GaWxlXTo6UmVhZEFsbEJ5dGVzKCRzb3VyY2VQYXRoKSB9CiAgICAkaWRlbnRpdHkgPSAkYnl0ZXMuTGVuZ3RoLlRvU3RyaW5nKCkgKyAnfCcgKyBbQ29udmVydF06OlRvSGV4U3RyaW5nKFtTZWN1cml0eS5DcnlwdG9ncmFwaHkuU0hBMjU2XTo6SGFzaERhdGEoJGJ5dGVzKSkKICAgICRyZWNvcmRzLkFkZChbb3JkZXJlZF1AeyBwYXRoID0gJHRhcmdldFJlbGF0aXZlOyBpZGVudGl0eSA9ICRpZGVudGl0eSB9KQogICAgJG1hcHBpbmcgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lIGJ5dGVzIC1Ob3RlUHJvcGVydHlWYWx1ZSAkYnl0ZXMKfQokY2Fub25pY2FsVGV4dCA9IChAKCRyZWNvcmRzIHwgRm9yRWFjaC1PYmplY3QgeyBbc3RyaW5nXSRfLnBhdGggKyAnPScgKyBbc3RyaW5nXSRfLmlkZW50aXR5IH0pIC1qb2luIFtjaGFyXTEwKSArIFtjaGFyXTEwCiRjYW5vbmljYWwgPSBbQ29udmVydF06OlRvSGV4U3RyaW5nKFtTZWN1cml0eS5DcnlwdG9ncmFwaHkuU0hBMjU2XTo6SGFzaERhdGEoW1RleHQuRW5jb2RpbmddOjpVVEY4LkdldEJ5dGVzKCRjYW5vbmljYWxUZXh0KSkpCiRwYWNrYWdlTWFuaWZlc3QgPSBbb3JkZXJlZF1AewogICAgc2NoZW1hVmVyc2lvbiA9IDEKICAgIGZyYW1ld29ya1ZlcnNpb24gPSAkRnJhbWV3b3JrVmVyc2lvbgogICAgcHJvdmlzaW9uYWwgPSBbYm9vbF0kUHJvdmlzaW9uYWwKICAgIGNhbm9uaWNhbCA9ICRjYW5vbmljYWwKICAgIGZpbGVzID0gQCgkcmVjb3JkcykKfQppZiAoJFBTQm91bmRQYXJhbWV0ZXJzLkNvbnRhaW5zS2V5KCdEaXN0cmlidXRpb24nKSkgewogICAgJHBhY2thZ2VNYW5pZmVzdC5zY2hlbWFWZXJzaW9uID0gMgogICAgJHBhY2thZ2VNYW5pZmVzdC5kaXN0cmlidXRpb25JZCA9ICRkaXN0cmlidXRpb25JZAp9CiRvdXRwdXRGdWxsID0gW0lPLlBhdGhdOjpHZXRGdWxsUGF0aCgkT3V0cHV0UGF0aCkKaWYgKFtJTy5QYXRoXTo6R2V0RXh0ZW5zaW9uKCRvdXRwdXRGdWxsKSAtY25lICcuemlwJykgewogICAgdGhyb3cgJ1BBQ0tBR0VfT1VUUFVUX0VYVEVOU0lPTicKfQokcmVzdWx0ID0gW3BzY3VzdG9tb2JqZWN0XUB7CiAgICBzdGF0dXMgPSBpZiAoJEFwcGx5KSB7ICdSRUFEWV9UT19XUklURScgfSBlbHNlIHsgJ1dIQVRfSUYnIH0KICAgIGZyYW1ld29ya1ZlcnNpb24gPSAkRnJhbWV3b3JrVmVyc2lvbgogICAgcHJvdmlzaW9uYWwgPSBbYm9vbF0kUHJvdmlzaW9uYWwKICAgIGNhbm9uaWNhbCA9ICRjYW5vbmljYWwKICAgIGZpbGVDb3VudCA9ICRvcmRlcmVkTWFwcGluZ3MuQ291bnQKICAgIG91dHB1dFBhdGggPSAkb3V0cHV0RnVsbAp9CmlmICgkUFNCb3VuZFBhcmFtZXRlcnMuQ29udGFpbnNLZXkoJ0Rpc3RyaWJ1dGlvbicpKSB7CiAgICAkcmVzdWx0IHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSBkaXN0cmlidXRpb25JZCAtTm90ZVByb3BlcnR5VmFsdWUgJGRpc3RyaWJ1dGlvbklkCn0KaWYgKC1ub3QgJEFwcGx5IC1vciAtbm90ICRQU0NtZGxldC5TaG91bGRQcm9jZXNzKCRvdXRwdXRGdWxsLCAnQnVpbGQgRnJhbWV3b3JrIHBhY2thZ2UnKSkgewogICAgcmV0dXJuICRyZXN1bHQKfQppZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkb3V0cHV0RnVsbCkgewogICAgdGhyb3cgJ1BBQ0tBR0VfT1VUUFVUX0VYSVNUUycKfQokb3V0cHV0UGFyZW50ID0gU3BsaXQtUGF0aCAtUGFyZW50ICRvdXRwdXRGdWxsCmlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRvdXRwdXRQYXJlbnQgLVBhdGhUeXBlIENvbnRhaW5lcikpIHsKICAgICRudWxsID0gTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkb3V0cHV0UGFyZW50Cn0KJHN0YWdlID0gSm9pbi1QYXRoIChbSU8uUGF0aF06OkdldFRlbXBQYXRoKCkpICgnYWl3LXVzZXItcGFja2FnZS0nICsgW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkKdHJ5IHsKICAgICRudWxsID0gTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkc3RhZ2UKICAgIGZvcmVhY2ggKCRtYXBwaW5nIGluICRvcmRlcmVkTWFwcGluZ3MpIHsKICAgICAgICAkZGVzdGluYXRpb24gPSBKb2luLVBhdGggJHN0YWdlIChbc3RyaW5nXSRtYXBwaW5nLnRhcmdldCkKICAgICAgICAkcGFyZW50ID0gU3BsaXQtUGF0aCAtUGFyZW50ICRkZXN0aW5hdGlvbgogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwYXJlbnQgLVBhdGhUeXBlIENvbnRhaW5lcikpIHsKICAgICAgICAgICAgJG51bGwgPSBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRwYXJlbnQgLUZvcmNlCiAgICAgICAgfQogICAgICAgIFtJTy5GaWxlXTo6V3JpdGVBbGxCeXRlcygkZGVzdGluYXRpb24sIFtieXRlW11dJG1hcHBpbmcuYnl0ZXMpCiAgICB9CiAgICBbSU8uRmlsZV06OldyaXRlQWxsVGV4dCgKICAgICAgICAoSm9pbi1QYXRoICRzdGFnZSAnUEFDS0FHRV9NQU5JRkVTVC5qc29uJyksCiAgICAgICAgKCRwYWNrYWdlTWFuaWZlc3QgfCBDb252ZXJ0VG8tSnNvbiAtRGVwdGggMTAwIC1Db21wcmVzcykgKyBbY2hhcl0xMCwKICAgICAgICBbVGV4dC5VVEY4RW5jb2RpbmddOjpuZXcoJGZhbHNlKQogICAgKQogICAgW0lPLkNvbXByZXNzaW9uLlppcEZpbGVdOjpDcmVhdGVGcm9tRGlyZWN0b3J5KCRzdGFnZSwgJG91dHB1dEZ1bGwsIFtJTy5Db21wcmVzc2lvbi5Db21wcmVzc2lvbkxldmVsXTo6T3B0aW1hbCwgJGZhbHNlKQp9CmZpbmFsbHkgewogICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHN0YWdlIC1QYXRoVHlwZSBDb250YWluZXIpIHsKICAgICAgICBbSU8uRGlyZWN0b3J5XTo6RGVsZXRlKCRzdGFnZSwgJHRydWUpCiAgICB9Cn0KJHJlc3VsdC5zdGF0dXMgPSAnQ1JFQVRFRCcKJHJlc3VsdAo=')
  $oldHost=New-AiwTestSourceView $sourceRoot (Join-Path $temp 'original-reader-host') $originalDefinition;$oldBuilder=Join-Path $oldHost.Root 'scripts/build-user-package.ps1';[IO.File]::WriteAllBytes($oldBuilder,$oldBuilderBytes)
  Check ((Get-AiwReleaseFileIdentity $oldBuilder)-ceq'16106|406EF30A110C9EE46F7159C829AB6E02A6D43DBA5F2C070FD229E1025A377931') 'original-schema2-reader-bytes-are-unchanged'
  $legacySample=Join-Path $temp 'legacy-schema2';$null=New-AiwTestSourceView $sourceRoot $legacySample $originalDefinition;$legacyVersion=Join-Path $legacySample 'framework/versions/2.0.0'
  $held=[IO.File]::Open((Join-Path $legacyVersion 'RELEASE_MANIFEST.json'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{$withoutManifest=New-AiwTestSourceView $legacySample (Join-Path $temp 'manifest-independent-view') $originalDefinition}finally{$held.Dispose()}
  Check ([bool]$withoutManifest.PayloadCanonical) 'source-view-never-reads-live-manifest-bytes'
  $futurePath=Join-Path $legacyVersion 'validation-evidence/prepackage/future.raw';Put $futurePath 'This is not an existing qualified proof.'
  $held=[IO.File]::Open($futurePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{$withoutFuture=New-AiwTestSourceView $legacySample (Join-Path $temp 'future-independent-view') $originalDefinition}finally{$held.Dispose();Remove-Item -LiteralPath $futurePath}
  Check ($withoutFuture.PayloadCanonical-ceq$withoutManifest.PayloadCanonical) 'source-view-never-reads-future-qualification-attachments'
   # The immutable old builder requires SKILL navigation. Keep this private
   # schema2 format fixture on its supported contract; the current real ZIP
   # above remains navigation3. Its earlier source-view closure is not reused.
   $legacyToolchainPath=Join-Path $legacyVersion 'TOOLCHAIN.json'
   WriteFixtureJson $legacyToolchainPath (NewLegacyNavigationToolchain (Read-AiwReleaseJson $legacyToolchainPath) '3')
   Set-AiwTestFixtureQualification $legacyVersion -Candidate
   $legacyRuntimePaths=@(& $releaseReader.ExportedCommands['Get-AiwReleaseRuntimeToolPaths'] $legacyVersion)
   Check ($legacyRuntimePaths.Count-eq9-and'skills/ai-workspace-router-v2/SKILL.md'-cin$legacyRuntimePaths) 'schema2-original-reader-fixture-uses-supported-navigation2'
   Write-AiwTestJson (Join-Path $raw 'legacy-navigation-fixture.json') @{scope='PRIVATE_SYNTHETIC_SCHEMA2_FORMAT';toolchainIdentity=(Get-AiwReleaseFileIdentity $legacyToolchainPath);contractVersion='3';navigationContractVersion='2';oldBuilderIdentity=(Get-AiwReleaseFileIdentity $oldBuilder);qualification='Existing synthetic schema2 constructor; no release or legacy adoption claim';sourceClosure='Not consumed after intentional private metadata mutation';runtimePaths=$legacyRuntimePaths}
  $qualified2=Get-AiwReleaseQualification -VersionRoot $legacyVersion -RuntimeRoot $legacySample
  Check ($qualified2.State-ceq'SOURCE_QUALIFIED'-and$qualified2.Manifest.schemaVersion-eq2) 'schema2-current-reader-accepts-original-qualified-shape'
  $old2=NativeTool $oldBuilder @{WorkspaceRoot=$legacySample;FrameworkVersion='2.0.0';Provisional=$true;Distribution='snapshot.1';OutputPath=(Join-Path $temp 'AI-Workspace-2.0.0-snapshot.1.zip')}
  Check ($old2.Code-eq0-and$old2.Text.Contains('WHAT_IF')) 'schema2-original-reader-accepts-valid-original-shape'
  $old3=NativeTool $oldBuilder @{WorkspaceRoot=$moved;FrameworkVersion='2.0.0';Provisional=$true;Distribution='snapshot.1';OutputPath=(Join-Path $temp 'AI-Workspace-2.0.0-snapshot.1.zip')}
  Check ($old3.Code-ne0-and$old3.Text.Contains('PROVISIONAL_PACKAGE_REVIEW_REQUIRED')) 'schema3-valid-sample-is-rejected-by-unchanged-original-reader'
  $module=@(Get-Module TestGroupEvidence)[0]
  AssertMovedExecutionCannotReuse $moved $d $g $options $record
  $snapshot=Get-AiwTestFixtureSnapshot $moved
   foreach($fault in @('alias','raw-case','role','legacy-skill-role','missing','extra','phase','cycle','projection','preimage','payload')){
   $p=Clone $proof;$indexPath=Join-Path $v $p.proofBundleRef.path;$index=Read-AiwReleaseJson $indexPath;$pattern='RELEASE_'
   try{
   switch($fault){
    alias{$a=@($index.aliases|Where-Object slot -CEQ '/stdout')[0];$a.targetMemberId=@($index.members|Where-Object kind -CEQ STDERR)[0].id;WriteFixtureJson $indexPath $index;$null=RebindBundle $moved $p;$pattern='^RELEASE_ALIAS_BINDING$'}
    'raw-case'{$gm=@($index.members|Where-Object kind -CEQ GROUP_RECORD)[0];$r=Read-AiwReleaseJson (Join-Path $v $gm.path);$r.cases[0].name='another';WriteFixtureJson (Join-Path $v $gm.path) $r;$null=RebindBundle $moved $p;$pattern='^RELEASE_CASE_RAW_MISMATCH$'}
    role{$cm=@($index.members|Where-Object kind -CEQ INPUT_CLOSURE)[0];$c=Read-AiwReleaseJson (Join-Path $v $cm.path);@($c.inputs|Where-Object logicalRole -CEQ CURRENT_RUNTIME_TOOL)[0].logicalRole='SOURCE_ONLY_BUILD_OR_TEST_INPUT';WriteFixtureJson (Join-Path $v $cm.path) $c;$null=RebindBundle $moved $p;$pattern='^RELEASE_INPUT_ROLE_DOWNGRADE$'}
     'legacy-skill-role'{$cm=@($index.members|Where-Object kind -CEQ INPUT_CLOSURE)[0];$c=Read-AiwReleaseJson (Join-Path $v $cm.path);$skill=@($c.inputs|Where-Object path -CEQ 'skills/ai-workspace-router-v2/SKILL.md')[0];$skill.logicalRole='CURRENT_RUNTIME_TOOL';$skill.distributionLocator=$skill.path;WriteFixtureJson (Join-Path $v $cm.path) $c;$null=RebindBundle $moved $p;$pattern='^RELEASE_INPUT_ROLE_DOWNGRADE$'}
    missing{Remove-Item -LiteralPath (Join-Path $v $index.members[0].path);$pattern='(?s)^(?!.*RELEASE_ALIAS_BINDING).*(?:RELEASE_|Could not find|cannot find|找不到)'}
    extra{Put (Join-Path $v 'validation-evidence/prepackage/extra.raw') 'extra';$pattern='^RELEASE_BUNDLE_SET_OR_CANONICAL$'}
    phase{$p.phase='POSTBUILD';$null=QualifySample $moved $p;$pattern='^RELEASE_PROOF_NOT_PASS$'}
    cycle{$p.baselineRef=@{path=$p.proofBundleRef.path;identity=$p.proofBundleRef.identity};$null=QualifySample $moved $p;$pattern='^RELEASE_FULL_RUN_BASELINE_CYCLE$'}
    projection{$m=Read-AiwReleaseJson (Join-Path $v 'RELEASE_MANIFEST.json');$m.sourceCandidate='changed-after-review';WriteFixtureJson (Join-Path $v 'RELEASE_MANIFEST.json') $m;$pattern='^RELEASE_REVIEW_PROJECTION_DRIFT$'}
    preimage{$m=Read-AiwReleaseJson (Join-Path $v 'RELEASE_MANIFEST.json');$m.sourceReviewEvidence.reviewedManifestBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{}'));WriteFixtureJson (Join-Path $v 'RELEASE_MANIFEST.json') $m;$pattern='^RELEASE_REVIEW_PREIMAGE_DRIFT$'}
    payload{[IO.File]::AppendAllText((Join-Path $v 'CHANGELOG.md'),'changed');$pattern='^RELEASE_PROOF_CURRENT_INPUT_DRIFT$'}
   }
   if($fault-cne'alias'){
    $legalIndex=Read-AiwReleaseJson $indexPath;$legal=$true
    foreach($alias in @($legalIndex.aliases|Where-Object slot -CNotIn @('PROCESS_LAUNCH_FOR_RUN','PHASE_EVENTS_FOR_RUN'))){
     $ownerMember=@($legalIndex.members|Where-Object id -CEQ $alias.ownerMemberId)[0];$target=@($legalIndex.members|Where-Object id -CEQ $alias.targetMemberId)[0];$owner=Read-AiwReleaseJson (Join-Path $v $ownerMember.path)
     $original=if($alias.slot-ceq'/processResult'){$owner.processResult}else{$owner.($alias.slot.TrimStart('/'))}
     $legal=$legal-and$alias.originalLocator-ceq$original.path-and$alias.originalIdentity-ceq$original.identity-and$target.identity-ceq$original.identity
    }
    Check $legal ('qualified-proof-fault-'+$fault+'-keeps-ordinary-alias-preconditions')
   }
   Reject {Get-AiwReleaseQualification -VersionRoot $v -RuntimeRoot $moved} $pattern ('qualified-proof-rejects-'+$fault)
   }finally{$null=Reset-AiwTestFixture $snapshot $moved}
  }
  Reject {Get-AiwReleaseChild $temp 'src/config/levels/level_test2.js'} 'PROTECTED_PATH' 'protected-locator-rejected-before-filesystem-access'
  $junction=Join-Path $temp 'reparse-link';$junctionTarget=Join-Path $temp 'reparse-target';$null=[IO.Directory]::CreateDirectory($junctionTarget)
  $null=New-Item -ItemType Junction -Path $junction -Target $junctionTarget
  try{Reject {Get-AiwReleaseFileIdentity (Join-Path $junction 'unread.txt')} 'REPARSE' 'reparse-ancestor-rejected-before-file-access'}finally{Remove-Item -LiteralPath $junction}
  $badBuild=Read-AiwReleaseJson $build.ResultPath;$badBuild.status='FAIL';$badBuildPath=Join-Path $temp 'failed-build.json';Write-AiwTestJson $badBuildPath $badBuild
  Reject {Assert-AiwReleaseBuildEvidence $badBuildPath $zip $packageFacts $packageQualification} 'BUILD_COMMAND_NOT_PASS' 'postbuild-rejects-failed-real-build-record'
  [IO.File]::AppendAllText((Join-Path $packageRoot 'README.md'),'drift')
  Reject {Assert-AiwReleaseZipRuntime $zip $packageRoot} 'ZIP_RUNTIME_BINDING' 'postbuild-rejects-extracted-tree-unrelated-to-frozen-zip'
  }
 }
 Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=release-validation|group='+$Group)
}finally{
 $full=Assert-AiwTestPath $temp;$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
 if([IO.Path]::GetDirectoryName($full)-cne$parent-or[IO.Path]::GetFileName($full)-cnotmatch'^rv-[a-f0-9]{8}$'){throw 'RELEASE_TEST_CLEANUP_SCOPE'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
