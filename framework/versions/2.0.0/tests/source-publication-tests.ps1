[CmdletBinding()]
param([ValidateSet('All','Scope','ModuleIsolation','Publication','PublicationScale','SingleRule','EmptyPolicy','Singleton','Synchronization','SharedPerformance','DailySources','HistoricalAssurance','RecoveryContext','JointBoundary','TargetStandards')][string]$Group='All',[switch]$KeepFixture,[ValidateSet('All','Ordinary','Maintenance')][string]$PublicationLayout='All',[switch]$ProfileHotPath,[ValidateRange(1,2147483647)][int]$SingleRuleProtectionSeconds=60,[ValidateSet('LEGACY','JOINT')][string]$PublicationBoundaryMode='JOINT')
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
Import-Module (Join-Path $PSScriptRoot '../scripts/StrictJsonInput.psm1')
Import-Module (Join-Path $PSScriptRoot '../scripts/ReleaseValidation.psm1')
$ErrorActionPreference='Stop'
if(-not$IsWindows-or$PSVersionTable.PSVersion.Major-lt7){throw 'SOURCE_PUBLICATION_TEST_PLATFORM_UNSUPPORTED'}
$versionRoot=Split-Path -Parent $PSScriptRoot
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
$utf8=[Text.UTF8Encoding]::new($false,$true)
$script:checks=0
$script:crashSceneTracking=$false
$script:crashSceneHandles=[Collections.Generic.List[object]]::new()
$script:preserveFailedCrash=$false
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-source-publication-tests-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
$oldHostActor=[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')
$script:publicationPhaseRunId=[guid]::NewGuid().ToString('N')
$phaseDirectory=if($env:AIW_TEST_RAW_DIRECTORY){$env:AIW_TEST_RAW_DIRECTORY}else{Join-Path ([IO.Path]::GetTempPath()) ('aiw-publication-phases-'+$script:publicationPhaseRunId)}
$script:publicationPhasePath=Assert-AiwTestPath (Join-Path $phaseDirectory ('publication-'+$script:publicationPhaseRunId+'.jsonl'))
$script:publicationProfilePath=Assert-AiwTestPath (Join-Path $phaseDirectory ('publication-functions-'+$script:publicationPhaseRunId+'.jsonl'))
# Engineering acceptance budgets for this isolated daily-update scenario,
# not runtime quotas or proof that the current implementation meets them.
$script:singleRuleBudgets=[ordered]@{
 PLAN_CONSTRUCTION=@(3,5);SOURCE_CHECKER_DISCOVER=@(5,10);CONTROL_CHECKER_DISCOVER=@(5,10)
 COMMON_TARGET_PREPARATION=@(5,10);SOURCE_ADMIT=@(3,5);CONTROL_ADMIT=@(3,5);PUBLIC_ACTION=@(6,15);TOTAL=@(30,60)
}
if($PublicationBoundaryMode-ceq'JOINT'){
 $script:singleRuleBudgets.Remove('SOURCE_ADMIT');$script:singleRuleBudgets.Remove('CONTROL_ADMIT')
 $script:singleRuleBudgets.PUBLICATION_ADMIT=@(6,10)
}
Write-Output ('PUBLICATION_PHASE_PATH|'+$script:publicationPhasePath)
if($ProfileHotPath){$global:AiwPublicationProfilePhase='SETUP'}
$script:singleRuleClock=$null
function AssertSingleRuleBudget([string]$Stage,[double]$Seconds){
 if($Group-cne'SingleRule'){return}
 if($Stage-cne'TOTAL'-and$script:singleRuleBudgets.Contains($Stage)-and$Seconds-gt$script:singleRuleBudgets[$Stage][1]){
  Write-Host ('SINGLE_RULE_STAGE_BUDGET_EXCEEDED|'+$Stage+'|observedSeconds='+$Seconds+'|allocationSeconds='+$script:singleRuleBudgets[$Stage][1]+'|DIAGNOSTIC_ONLY')
 }
 $totalSeconds=if($Stage-ceq'TOTAL'){$Seconds}elseif($null-ne$script:singleRuleClock){$script:singleRuleClock.Elapsed.TotalSeconds}else{$null}
 if($Stage-ceq'TOTAL'-and$Seconds-gt$script:singleRuleBudgets.TOTAL[1]){
  throw ('SINGLE_RULE_TOTAL_LIMIT|observedSeconds='+$totalSeconds+'|limitSeconds='+$script:singleRuleBudgets.TOTAL[1]+'|STOP_REMAINING_CHAIN')
 }
 if($Stage-cne'TOTAL'-and$null-ne$totalSeconds-and$totalSeconds-gt$SingleRuleProtectionSeconds){
  throw ('SINGLE_RULE_PROTECTION_LIMIT|observedSeconds='+$totalSeconds+'|protectionSeconds='+$SingleRuleProtectionSeconds+'|STOP_REMAINING_CHAIN')
 }
}
function InvokePublicationPhase([string]$PhaseCase,[string]$PhaseStep,[scriptblock]$PhaseBody){
 $step=$PhaseStep+':'+[guid]::NewGuid().ToString('N');$outcome='THREW';$errorText='';$stageValue=$null
 $aiwPriorProfilePhase=if($ProfileHotPath){[string]$global:AiwPublicationProfilePhase}else{''};if($ProfileHotPath){$global:AiwPublicationProfilePhase=$PhaseStep}
 $stageClock=[Diagnostics.Stopwatch]::StartNew()
 $data=@{caseId=$PhaseCase;stage=$PhaseStep;observation='PARENT_STAGE_ENTRY'}
 Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) $step START $data
 try{
  Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) $step REACHED $data
  $stageValue=& $PhaseBody;$outcome='RETURNED';return $stageValue
 }catch{$errorText=$_.Exception.Message;throw}finally{
  $stageClock.Stop()
  $end=@{caseId=$PhaseCase;stage=$PhaseStep;outcome=$outcome;error=$errorText;wallSeconds=$stageClock.Elapsed.TotalSeconds;returnedCount=$(if($null-eq$stageValue){0}else{@($stageValue).Count})}
  if($PhaseStep-ceq'PUBLIC_ACTION'){$end.returnValue=$stageValue}
  Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) $step END $end
  if($ProfileHotPath){$global:AiwPublicationProfilePhase=$aiwPriorProfilePhase}
  # Stop only at a completed boundary. This is not an in-flight watchdog.
  # PUBLIC_ACTION returns its actual completion before performance is judged.
  if($outcome-ceq'RETURNED'-and$PhaseStep-cne'PUBLIC_ACTION'){
   AssertSingleRuleBudget $PhaseStep $stageClock.Elapsed.TotalSeconds
  }
 }
}

function Check([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT_FAIL|'+$Name)};$script:checks++;Write-Host ('PASS|'+$Name)}

function Reject([scriptblock]$Body,[string]$Pattern,[string]$Name){$errorText='';try{& $Body|Out-Null}catch{$errorText=$_.Exception.Message};Check ($errorText-match$Pattern) ($Name+'|'+$errorText)}

function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}

function SaveJson([string]$Path,$Value){SaveText $Path (($Value|ConvertTo-Json -Depth 100)+[char]10)}

function SaveFixturePolicy([string]$Path,$Value,[string]$Version){
 if(-not(Test-Json -Json ($Value|ConvertTo-Json -Depth 100) -SchemaFile (Join-Path $Version 'PROCESS_POLICY_SCHEMA.json') -ErrorAction SilentlyContinue)){throw 'TEST_FIXTURE_PROCESS_POLICY_SCHEMA'}
 SaveJson $Path $Value
}

function Identity([string]$Path){if(-not[IO.File]::Exists($Path)){return 'NEW'};$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}

function Reference([string]$Path){return [pscustomobject]@{path=$Path;identity=(Identity $Path)}}

function CopyValue($Value){return $Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100}

function FixtureChecker([string]$Root,[string]$Entry,[hashtable]$Parameters){
 $location=Get-Location;$processDirectory=[Environment]::CurrentDirectory
 try{
  Set-Location -LiteralPath $Root;[Environment]::CurrentDirectory=$Root
  $raw=@(& $Entry @Parameters);$code=$LASTEXITCODE
  return [pscustomobject]@{code=$code;output=$raw}
 }finally{
  Set-Location -LiteralPath $location.Path;[Environment]::CurrentDirectory=$processDirectory
 }
}

function AssertFixturePath([string]$Path){$full=[IO.Path]::GetFullPath($Path);if(-not$full.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_FIXTURE_SCOPE'};return $full}

function TestCanonical {
 $pub=@(Import-Module (Join-Path $versionRoot 'scripts/ProjectSourcePublication.psm1') -PassThru)[0]
 $declared=@('standards/data.md','standards/new.md','.ai-workspace/process-policy.json')
 $wrapped=@($declared|ForEach-Object{[pscustomobject]@{path=$_}}|ForEach-Object path)
 $expected='["standards/data.md","standards/new.md",".ai-workspace/process-policy.json"]'
 $actual=& $pub {param($v)Get-PubCanonical $v} $wrapped
 Check ($actual-ceq$expected) 'pipeline-wrapped-write-order-retains-string-values'
 $nested=[pscustomobject]@{b=$wrapped;a=@($null,$true,7,'x')}
 $actual=& $pub {param($v)Get-PubCanonical $v} $nested
 Check ($actual-ceq('{"a":[null,true,7,"x"],"b":'+$expected+'}')) 'nested-scalars-array-order-and-ordinal-properties'
 foreach($empty in @([pscustomobject]@{},@{})){
  $actual=& $pub {param($v)Get-PubCanonical $v} $empty
  Check ($actual-ceq'{}') ('empty-object-canonical|'+$empty.GetType().Name)
 }
 $actual=& $pub {param($v)Get-PubCanonical $v} @{z=[pscustomobject]@{};a=@()}
 Check ($actual-ceq'{"a":[],"z":{}}') 'nested-empty-capability-and-array-canonical'
 $value=[pscustomobject]@{z=@(@(),@(1),@($null));A="中文`nquote`"slash\";a2=[pscustomobject]@{B=$false;c=1.25}}
 $content=@(Import-Module (Join-Path $versionRoot 'scripts/ContentSources.psm1') -PassThru)[0]
 $expected=& $content.ExportedCommands['ConvertTo-AiwContentCanonicalJson'] $value
 $actual=& $pub {param($v)Get-PubCanonical $v} $value
 Check ($actual-ceq$expected) 'publication-canonical-retains-original-ordinal-scalar-and-nested-array-contract'
}

function TestPathIo {
 $root=AssertFixturePath (Join-Path $temp 'path-io')
 $relative='literal [dir]/中文 [data].md';$file=Join-Path $root $relative
 SaveText $file "# Literal path`nComplete 中文 bytes.`n"
 SaveText (Join-Path $root 'parent-file') 'A file cannot be a directory parent.'
 $pub=@(Import-Module (Join-Path $versionRoot 'scripts/ProjectSourcePublication.psm1') -PassThru)[0]
 $composition=@(Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
 # Independent original provider/identity operations are the success oracle;
 # no expected path or digest is produced by the new attributes walk.
 $reference=(Resolve-Path -LiteralPath $file).ProviderPath
 $expectedIdentity=(Get-Item -LiteralPath $file).Length.ToString()+'|'+(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
 $child=@(& $composition {param($r,$p)Resolve-AiwChildFile $r $p PATH_IO} $root $relative)
 $pubChild=@(& $pub {param($r,$p)Get-PubChild $r $p @()} $root $relative)
 $relativeFile=@(& $composition {param($r,$p)Resolve-AiwProjectStandardFile $r $p PROJECT_RELATIVE PATH_IO @()} $root $relative)
 $absoluteFile=@(& $composition {param($r,$p)Resolve-AiwProjectStandardFile $r $p ABSOLUTE_FILE PATH_IO @()} $root $file)
 Check ($child.Count-eq1-and$pubChild.Count-eq1-and$relativeFile.Count-eq1-and$absoluteFile.Count-eq1-and$child[0]-ceq$reference-and$pubChild[0]-ceq$reference-and$relativeFile[0].Path-ceq$reference-and$absoluteFile[0].Path-ceq$reference) 'path-io-literal-Unicode-brackets-return-original-provider-path'
 $actualIdentity=& $composition.ExportedCommands['Get-AiwFileIdentity'] $child[0]
 Check ($actualIdentity-ceq$expectedIdentity) 'path-io-returned-file-retains-original-whole-byte-identity'
 $missing=& $composition {param($r)Resolve-AiwChildFile $r 'missing.md' PATH_IO -AllowMissing} $root
 Check ($null-eq$missing) 'path-io-AllowMissing-only-final-leaf-returns-null'
 Reject {& $composition {param($r)Resolve-AiwChildFile $r 'missing.md' PATH_IO} $root} '^PATH_IO_MISSING$' 'path-io-missing-required-leaf-rejects'
 Reject {& $composition {param($r)Resolve-AiwChildFile $r 'absent/child.md' PATH_IO -AllowMissing} $root} '^PATH_IO_MISSING$' 'path-io-AllowMissing-does-not-hide-missing-parent'
 Reject {& $composition {param($r)Resolve-AiwChildFile $r 'child.md' PATH_IO -AllowMissing} (Join-Path $root 'absent')} '^PATH_IO_MISSING$' 'path-io-AllowMissing-does-not-trust-missing-root'
 $future=& $pub {param($r)Get-PubChild $r 'absent/child.md' @()} $root
 Check ($future-ceq[IO.Path]::GetFullPath((Join-Path $root 'absent/child.md'))) 'path-io-publication-retains-creatable-missing-parent-path'
 Reject {& $pub {param($r)Get-PubChild $r 'literal [dir]' @()} $root} 'SOURCE_PUBLICATION_NOT_REGULAR_FILE' 'path-io-publication-directory-leaf-rejects'
 Reject {& $composition {param($r)Resolve-AiwChildFile $r 'literal [dir]' PATH_IO -AllowMissing} $root} '^PATH_IO_MISSING$' 'path-io-directory-leaf-is-not-AllowMissing'
 Reject {& $composition {param($r)Resolve-AiwProjectStandardFile $r (Join-Path $r 'literal [dir]') ABSOLUTE_FILE PATH_IO @()} $root} '^PATH_IO_MISSING$' 'path-io-absolute-directory-leaf-rejects'
 Reject {& $pub {param($r)Get-PubChild $r 'parent-file/child.md' @()} $root} 'SOURCE_PUBLICATION_NOT_REGULAR_FILE' 'path-io-publication-nondirectory-parent-rejects'
 Reject {& $composition {param($r)Resolve-AiwChildFile $r 'parent-file/child.md' PATH_IO -AllowMissing} $root} '^PATH_IO_MISSING$' 'path-io-relative-nondirectory-parent-rejects'
 Reject {& $composition {param($r)Resolve-AiwProjectStandardFile $r (Join-Path $r 'parent-file/child.md') ABSOLUTE_FILE PATH_IO @()} $root} '^PATH_IO_MISSING$' 'path-io-absolute-nondirectory-parent-rejects'
 Reject {& $pub {param($r)Get-PubChild $r '../escape.md' @()} $root} '^SOURCE_PUBLICATION_PATH$' 'path-io-publication-escape-rejects-before-resolution'
 Reject {& $composition {param($r)Resolve-AiwChildFile $r '../escape.md' PATH_IO} $root} '^PATH_IO_COMPONENT$' 'path-io-composition-escape-rejects-before-resolution'
 # Reobserve a previously successful path after actual deletion/replacement.
 $saved=[IO.File]::ReadAllBytes($file)
 try{
  [IO.File]::Delete($file)
  Reject {& $composition {param($r,$p)Resolve-AiwChildFile $r $p PATH_IO} $root $relative} '^PATH_IO_MISSING$' 'path-io-new-call-observes-deleted-leaf'
  [IO.Directory]::CreateDirectory($file)|Out-Null
  Reject {& $pub {param($r,$p)Get-PubChild $r $p @()} $root $relative} 'SOURCE_PUBLICATION_NOT_REGULAR_FILE' 'path-io-new-call-observes-file-replaced-by-directory'
 }finally{
  if([IO.Directory]::Exists($file)){[IO.Directory]::Delete($file)}
  [IO.File]::WriteAllBytes($file,$saved)
 }
 # Observe real metadata/read statements without replacing their results.
 # The positive control must hit them; protected inputs must reach none.
 $breakpoints=@();$global:AiwPathIoMetadataHits=@{}
 try{
  foreach($site in @(@{module=$pub;name='Assert-PubPath';member='GetAttributes'},@{module=$pub;name='Get-PubChild';member='GetAttributes'},@{module=$composition;name='Resolve-AiwChildFile';member='GetAttributes'},@{module=$composition;name='Resolve-AiwProjectStandardFile';member='GetAttributes'},@{module=$pub;name='Read-PubRef';member='ReadAllBytes'})){
   $function=& $site.module {param($n)(Get-Command $n -CommandType Function).ScriptBlock} $site.name
   $member=$site.member
   $calls=@($function.Ast.FindAll({param($n)$n-is[Management.Automation.Language.InvokeMemberExpressionAst]-and$n.Member.Extent.Text-ceq$member},$true))
   if($calls.Count-ne1){throw ('TEST_PATH_IO_METADATA_ANCHOR|'+$site.name)}
   $global:AiwPathIoMetadataHits[$site.name]=0
   $action=[scriptblock]::Create('$global:AiwPathIoMetadataHits['''+$site.name+''']++')
   $breakpoints+=Set-PSBreakpoint -Script $site.module.Path -Line $calls[0].Extent.StartLineNumber -Action $action
  }
  $null=& $pub {param($p,$id)Read-PubRef ([pscustomobject]@{path=$p;identity=$id}) @()} $file $expectedIdentity
  $null=& $pub {param($r,$p)Get-PubChild $r $p @()} $root $relative
  $null=& $composition {param($r,$p)Resolve-AiwProjectStandardFile $r $p PROJECT_RELATIVE PATH_IO @()} $root $relative
  $null=& $composition {param($r,$p)Resolve-AiwProjectStandardFile $r $p ABSOLUTE_FILE PATH_IO @()} $root $file
  Check (@($global:AiwPathIoMetadataHits.Values|Where-Object {$_-eq0}).Count-eq0) 'path-io-protection-observer-reaches-every-real-metadata-and-read-site'
  foreach($key in @($global:AiwPathIoMetadataHits.Keys)){$global:AiwPathIoMetadataHits[$key]=0}
  Reject {& $pub {param($r,$p)Get-PubChild $r $p @('literal [dir]')} $root $relative} '^SOURCE_PUBLICATION_FORBIDDEN$' 'path-io-relative-publication-protection-rejects'
  Reject {& $pub {param($p,$id)Read-PubRef ([pscustomobject]@{path=$p;identity=$id}) @($p)} $file $expectedIdentity} '^SOURCE_PUBLICATION_FORBIDDEN$' 'path-io-absolute-publication-protection-rejects'
  Reject {& $composition {param($r,$p)Resolve-AiwProjectStandardFile $r $p PROJECT_RELATIVE PATH_IO @('literal [dir]')} $root $relative} '^PATH_IO_FORBIDDEN$' 'path-io-relative-composition-protection-rejects'
  Reject {& $composition {param($r,$p)Resolve-AiwProjectStandardFile $r $p ABSOLUTE_FILE PATH_IO @($p)} $root $file} '^PATH_IO_FORBIDDEN$' 'path-io-absolute-composition-protection-rejects'
  Check (@($global:AiwPathIoMetadataHits.Values|Where-Object {$_-ne0}).Count-eq0) 'path-io-protected-paths-reject-before-any-observed-metadata-or-content-read'
 }finally{foreach($bp in $breakpoints){Remove-PSBreakpoint $bp};Remove-Variable AiwPathIoMetadataHits -Scope Global}
 $link=AssertFixturePath (Join-Path $root 'junction');$destination=AssertFixturePath (Join-Path $root 'junction-target')
 SaveText (Join-Path $destination 'data.md') 'Only isolated fixture data.'
 $created=$false
 try{
  New-Item -ItemType Junction -Path $link -Target $destination|Out-Null;$created=$true
  Reject {& $pub {param($r)Get-PubChild $r 'junction/data.md' @()} $root} 'SOURCE_PUBLICATION_REPARSE' 'path-io-publication-reparse-ancestor-rejects'
  Reject {& $pub {param($r)Get-PubChild $r 'junction/missing.md' @()} $root} 'SOURCE_PUBLICATION_REPARSE' 'path-io-missing-leaf-cannot-hide-reparse-ancestor'
  Reject {& $composition {param($r)Resolve-AiwChildFile $r 'junction/data.md' PATH_IO} $root} '^PATH_IO_REPARSE$' 'path-io-relative-reparse-ancestor-rejects'
  Reject {& $composition {param($r,$p)Resolve-AiwProjectStandardFile $r $p ABSOLUTE_FILE PATH_IO @()} $root (Join-Path $link 'data.md')} '^PATH_IO_REPARSE$' 'path-io-absolute-reparse-ancestor-rejects'
  Reject {& $composition {param($r)Resolve-AiwChildFile $r 'data.md' PATH_IO} $link} '^PATH_IO_REPARSE$' 'path-io-relative-reparse-root-is-not-trusted'
 }finally{
  if($created){
   if(([IO.File]::GetAttributes($link)-band[IO.FileAttributes]::ReparsePoint)-eq0){throw 'TEST_JUNCTION_CLEANUP_DRIFT'}
   [IO.Directory]::Delete($link)
  }
 }
}

function AddPublicationFunctionTiming([string]$Version){
 # Only the isolated fixture is instrumented, before its qualification.
 # All durations are nested inclusive observations, never additive wall time.
 $selection=@{
  'ProjectSourcePublication.psm1'=@('Get-PubClosure','Get-PubClosureObservationCore','Get-PubClosurePair','Get-PubEligibilityCore','Get-AiwProjectSourcePublicationMembers','Test-PubClosureObservation','Get-PubRecoveryOriginalFacts','Test-PubOriginalFinalization','Set-AiwProjectSourcePublicationContext','Get-AiwProjectSourcePublicationReachability')
  'ProcessRequirementComposition.psm1'=@('Get-AiwProjectStandardsSnapshot','Get-AiwProcessBindingSnapshot','Get-AiwSourceChangeTarget','Get-AiwPublicationTargets','Get-AiwPublicationCandidateCore')
  'ContentSources.psm1'=@('New-AiwContentContext','Register-CsContextInputs','Get-CsContextInputs','Copy-CsOwnedContext','Invoke-CsOwnedStandardsBatch')
  'ProcessRequirementBoundary.psm1'=@('Invoke-AiwProcessRequirementBoundary','Invoke-AiwProcessRequirementBoundaryCore')
  'ProjectAdoptionState.psm1'=@('Invoke-AiwRootAdoptionSourceScope','Get-AiwFixedAdoptedProcessSource','Get-AiwFixedAdoptionSourceCore')
  'ProjectAdoptionTransaction.psm1'=@('Invoke-AiwProjectRuleActionRecovery','Invoke-AiwProjectSourcePublicationRecovery','Assert-AiwPublicationRootOriginals','Write-AiwAtomicBytes')
 }
 $batchOwners=@{'ContentSources.psm1'='Invoke-CsOwnedStandardsBatch';'ProcessRequirementBoundary.psm1'='Invoke-AiwProcessRequirementBoundaryCore';'ProjectAdoptionState.psm1'='Invoke-AiwRootAdoptionSourceScope'}
 $helperSets=@{
  'ContentSources.psm1'=@('ConvertTo-AiwContentCanonicalJson','Get-AiwContentDescriptorIdentity','Assert-CsPath','New-CsOwnedGraph','Read-CsOwnedGraph','Read-CsResolvedExact','Read-CsPinnedCache')
  'ProcessRequirementBoundary.psm1'=@('Read-Input','Get-Receipt')
  'ProjectAdoptionState.psm1'=@('Read-AiwProjectJson','Measure-AiwTestRootJsonCopy')
 }
 $framework=[IO.Path]::GetFullPath((Join-Path $Version '../../..'))
 foreach($name in $selection.Keys){
  $path=if($name-cin@('ProjectAdoptionState.psm1','ProjectAdoptionTransaction.psm1')){Join-Path $framework ('scripts/'+$name)}else{Join-Path $Version ('scripts/'+$name)}
  $text=[IO.File]::ReadAllText($path,$utf8)
  if($name-ceq'ProjectAdoptionState.psm1'){
   # Time the two top-level defensive copies, not every recursive scalar.
   $text=$text.Replace('(Copy-AiwRootJsonValue $cached.Value)','(Measure-AiwTestRootJsonCopy $cached.Value)').Replace('Value=(Copy-AiwRootJsonValue $value)','Value=(Measure-AiwTestRootJsonCopy $value)')
   $text="function Measure-AiwTestRootJsonCopy(`$Value){`$copy=Copy-AiwRootJsonValue `$Value;return ,`$copy}`n"+$text
  }
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw 'TEST_PROFILE_SOURCE_SYNTAX'}
  $changes=[Collections.Generic.List[object]]::new();$functionsToTime=@($selection[$name]);$batchHelpers=@()
  if($batchOwners.ContainsKey($name)){
   $batchHelpers=@($helperSets[$name]);$functionsToTime+=@($batchHelpers)
   $changes.Add(@{offset=0;text="`$script:PublicationBatchFunctionTotals=`$null;`$script:PublicationBatchScopeId='NONE'`n"})
  }
  foreach($functionName in $functionsToTime){
   $functions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$functionName},$true))
   if($functions.Count-ne1){throw ('TEST_PROFILE_FUNCTION|'+$name+'|'+$functionName)}
   $body=$functions[0].Body;$start=if($null-ne$body.ParamBlock){$body.ParamBlock.Extent.EndOffset}else{$body.Extent.StartOffset+1}
   $profileLiteral=$script:publicationProfilePath.Replace("'","''");$labelLiteral=($name+'::'+$functionName).Replace("'","''")
   if($functionName-cin$batchHelpers){
    $head=@'

$aiwBatchClock=if($null-ne$script:PublicationBatchFunctionTotals){[Diagnostics.Stopwatch]::StartNew()}else{$null}
$aiwProfileInput=if($PSBoundParameters.ContainsKey('Path')){[string]$PSBoundParameters['Path']}else{'NOT_APPLICABLE'}
try{
'@
    $tail=@'

}finally{if($null-ne$aiwBatchClock){
 $aiwBatchClock.Stop()
 if(-not$script:PublicationBatchFunctionTotals.ContainsKey('__LABEL__')){$script:PublicationBatchFunctionTotals['__LABEL__']=@{calls=0;seconds=0.0;maxSeconds=0.0;inputs=@{}}}
 $row=$script:PublicationBatchFunctionTotals['__LABEL__'];$row.calls++;$row.seconds+=$aiwBatchClock.Elapsed.TotalSeconds;$row.maxSeconds=[Math]::Max($row.maxSeconds,$aiwBatchClock.Elapsed.TotalSeconds)
 if($aiwProfileInput-cne'NOT_APPLICABLE'){
  $observedIdentity='NOT_CAPTURED';__IDENTITY__
  $key=$aiwProfileInput+'#'+$observedIdentity
  if(-not$row.inputs.ContainsKey($key)){$row.inputs[$key]=@{path=$aiwProfileInput;identity=$observedIdentity;calls=0;inclusiveWallSeconds=0.0}}
  $row.inputs[$key].calls++;$row.inputs[$key].inclusiveWallSeconds+=$aiwBatchClock.Elapsed.TotalSeconds
 }
}}
'@
    $identityCode=if($name-ceq'ProjectAdoptionState.psm1'-and$functionName-ceq'Read-AiwProjectJson'){'$identityVariable=Get-Variable -Name identity -Scope Local -ErrorAction SilentlyContinue;if($null-ne$identityVariable){$observedIdentity=[string]$identityVariable.Value}'}else{''}
    $tail=$tail.Replace('__LABEL__',$labelLiteral).Replace('__IDENTITY__',$identityCode)
   }elseif($batchOwners.ContainsKey($name)-and$functionName-ceq$batchOwners[$name]){
    $head=@'

$aiwPriorBatchTotals=$script:PublicationBatchFunctionTotals;$aiwPriorBatchScope=$script:PublicationBatchScopeId
$script:PublicationBatchFunctionTotals=@{};$script:PublicationBatchScopeId=[guid]::NewGuid().ToString('N')
$aiwFunctionStarted=[DateTime]::UtcNow;$aiwProfilePhase=[string]$global:AiwPublicationProfilePhase;$aiwFunctionClock=[Diagnostics.Stopwatch]::StartNew()
try{
'@
    $tail=@'

}finally{
 $aiwFunctionClock.Stop();$aiwFunctionEnded=[DateTime]::UtcNow
 try{
  $rows=[Collections.Generic.List[string]]::new()
  foreach($key in $script:PublicationBatchFunctionTotals.Keys){$row=$script:PublicationBatchFunctionTotals[$key];$rows.Add((@{function=$key;aggregation='CALL_TOTALS_WITHIN_ONE_BATCH';parentScopeId=$script:PublicationBatchScopeId;phase=$aiwProfilePhase;calls=$row.calls;inclusiveWallSeconds=$row.seconds;maxCallWallSeconds=$row.maxSeconds;inputBreakdown=@($row.inputs.Values);processId=$PID;startUtc=$aiwFunctionStarted.ToString('O');endUtc=$aiwFunctionEnded.ToString('O')}|ConvertTo-Json -Depth 12 -Compress))}
  $rows.Add((@{function='__LABEL__';aggregation='BATCH_OWNER';scopeId=$script:PublicationBatchScopeId;phase=$aiwProfilePhase;inclusiveWallSeconds=$aiwFunctionClock.Elapsed.TotalSeconds;processId=$PID;startUtc=$aiwFunctionStarted.ToString('O');endUtc=$aiwFunctionEnded.ToString('O')}|ConvertTo-Json -Compress))
  [IO.File]::AppendAllText('__PROFILE__',([string]::Join([char]10,$rows)+[char]10),[Text.UTF8Encoding]::new($false))
 }finally{$script:PublicationBatchFunctionTotals=$aiwPriorBatchTotals;$script:PublicationBatchScopeId=$aiwPriorBatchScope}
}
'@
    $tail=$tail.Replace('__LABEL__',$labelLiteral).Replace('__PROFILE__',$profileLiteral)
   }else{
    $head=@'

$aiwFunctionStarted=[DateTime]::UtcNow;$aiwProfilePhase=[string]$global:AiwPublicationProfilePhase
$aiwProfileInput=if($PSBoundParameters.ContainsKey('InputPath')){[string]$PSBoundParameters['InputPath']}elseif($PSBoundParameters.ContainsKey('Path')){[string]$PSBoundParameters['Path']}else{'NOT_APPLICABLE'}
$aiwFunctionClock=[Diagnostics.Stopwatch]::StartNew();try{
'@
    $tail=@'

}finally{$aiwFunctionClock.Stop();$aiwFunctionEnded=[DateTime]::UtcNow;[IO.File]::AppendAllText('__PROFILE__',((@{function='__LABEL__';phase=$aiwProfilePhase;inputPath=$aiwProfileInput;inclusiveWallSeconds=$aiwFunctionClock.Elapsed.TotalSeconds;processId=$PID;startUtc=$aiwFunctionStarted.ToString('O');endUtc=$aiwFunctionEnded.ToString('O')}|ConvertTo-Json -Compress)+[char]10),[Text.UTF8Encoding]::new($false))}
'@
    $tail=$tail.Replace('__LABEL__',$labelLiteral).Replace('__PROFILE__',$profileLiteral)
   }
   $changes.Add(@{offset=$start;text=$head});$changes.Add(@{offset=$body.Extent.EndOffset-1;text=$tail})
  }
  foreach($change in @($changes|Sort-Object offset -Descending)){$text=$text.Insert($change.offset,$change.text)}
  if($name-ceq'ProjectAdoptionTransaction.psm1'){
   $anchor='$writes=0;$lease=$null';$stop='}finally{Exit-AiwRootProjectSourceScope $lease}'
   if($text.Split($anchor,[StringSplitOptions]::None).Count-ne2){throw 'TEST_PROFILE_WRITE_PREFIX_ANCHOR'}
   $text=$text.Replace($anchor,$anchor+";`$aiwWritePrefixStart=[DateTime]::UtcNow;`$aiwWritePrefixClock=[Diagnostics.Stopwatch]::StartNew()")
   $at=$text.IndexOf($anchor,[StringComparison]::Ordinal);$end=$text.IndexOf($stop,$at,[StringComparison]::Ordinal)
   if($end-lt0){throw 'TEST_PROFILE_WRITE_PREFIX_END'}
   $addition=";`$aiwWritePrefixClock.Stop();[IO.File]::AppendAllText('$profileLiteral',((@{function='ProjectAdoptionTransaction.psm1::ORDERED_WRITE_PREFIX_WITH_CONTEXT';phase=[string]`$global:AiwPublicationProfilePhase;inclusiveWallSeconds=`$aiwWritePrefixClock.Elapsed.TotalSeconds;processId=`$PID;startUtc=`$aiwWritePrefixStart.ToString('O');endUtc=[DateTime]::UtcNow.ToString('O')}|ConvertTo-Json -Compress)+[char]10),[Text.UTF8Encoding]::new(`$false))"
   $text=$text.Insert($end+$stop.Length,$addition)
  }
  [IO.File]::WriteAllText($path,$text,$utf8)
 }
 Set-AiwTestFixtureQualification $Version
 Write-Output ('PUBLICATION_FUNCTION_PROFILE|'+$script:publicationProfilePath)
}


function NewFixture([string]$Name,[switch]$Maintenance,[string]$BarrierNode='',[switch]$EmptyPolicy,[switch]$Singleton){
 return InvokePublicationPhase $Name FIXTURE_PREPARATION {NewFixtureBody $Name -Maintenance:$Maintenance -BarrierNode $BarrierNode -EmptyPolicy:$EmptyPolicy -Singleton:$Singleton}
}

function NewFixtureSourceBinding{
 return [pscustomobject]@{id='professional';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator='standards'});decisionLocator='.ai-workspace/runtime/PUBLICATION-001/publication-actor/adoption.md'}
}

function NewFixtureBody([string]$Name,[switch]$Maintenance,[string]$BarrierNode='',[switch]$EmptyPolicy,[switch]$Singleton){
 if($EmptyPolicy-and$Maintenance){throw 'EMPTY_POLICY_ORDINARY_REGISTRATION_ONLY'}
 $case=Join-Path $temp $Name;$frameworkRoot=Join-Path $case 'bundle';$copy=Join-Path $frameworkRoot 'framework/versions/2.0.0';$project=Join-Path $case 'project'
 $null=[IO.Directory]::CreateDirectory($copy);$null=[IO.Directory]::CreateDirectory($project)
 $copy=New-AiwTestMechanismFixture $sourceRoot $frameworkRoot (Join-Path $PSScriptRoot 'test-groups.json') -Maintenance:$Maintenance
 if($ProfileHotPath){AddPublicationFunctionTiming $copy|Write-Host}
 $readyName='Local\AIW-Ready-'+[guid]::NewGuid().ToString('N');$releaseName='Local\AIW-Release-'+[guid]::NewGuid().ToString('N')
 if($BarrierNode){
  if($BarrierNode-cne'SECOND_FINALIZE'){throw 'TEST_UNSUPPORTED_BARRIER'}
  $boundary=Join-Path $copy 'scripts/ProcessRequirementBoundary.psm1'
  $text=[IO.File]::ReadAllText($boundary,$utf8)
  $anchor="    if(`$sourceChangeRollback-and`$null-eq`$sourceChange){throw 'SOURCE_CHANGE_ROLLBACK_UNBOUND'}"
  if($text.Split($anchor,[StringSplitOptions]::None).Count-ne2){throw 'TEST_SECOND_FINALIZE_FAULT_ANCHOR'}
  $text=$text.Replace($anchor,$anchor+"`n"+'    if($env:AIW_TEST_PUBLICATION_SECOND_FINALIZE-ceq''1''-and$mode-ceq''FINALIZE_OUTPUT''-and$receipt.actionKind-ceq''CONTROL_WRITE''-and$null-ne$sourceChange-and$null-ne$sourceChange.PSObject.Properties[''publication'']){throw ''TEST_SECOND_REAL_FINALIZE_FAILURE''}')
  [IO.File]::WriteAllText($boundary,$text,$utf8)
  Set-AiwTestFixtureQualification $copy
 }
 if($Maintenance){
  # Explicit overlay and root-template members were copied by the fixture helper.
  $target=Join-Path $case 'target';$null=[IO.Directory]::CreateDirectory($target)
  & git -C $project init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
  & git -C $target init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
 }
 Import-Module (Join-Path $copy 'scripts/ProcessRequirementComposition.psm1')
 Import-Module (Join-Path $copy 'scripts/ContentSources.psm1')
  # A root-only barrier hook does not change the already sealed version payload.
 if($Maintenance){
  [string[]]$paths=@(Get-ChildItem -LiteralPath $frameworkRoot -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($frameworkRoot,$_.FullName).Replace('\','/')});[Array]::Sort($paths,[StringComparer]::Ordinal)
  $entries=@($paths|ForEach-Object{[pscustomobject]@{path=$_;identity=Identity (Join-Path $frameworkRoot $_)}});$rows=@($entries|ForEach-Object{$_.path+'='+$_.identity})
  $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n")+"`n")))
  SaveJson (Join-Path $frameworkRoot 'PACKAGE_MANIFEST.json') @{schemaVersion=2;frameworkVersion='2.0.0';provisional=$false;canonical=$canonical;files=$entries;distributionId='2.0.0-release'}
 }
 $registration=@{ProjectId='publication-fixture';DisplayName='Source publication fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId='publication-actor';WorkspaceRoot=$frameworkRoot;Apply=$true}
 if($Maintenance){$registration.ControlPlaneLayout='framework-maintenance-sibling';$registration.FrameworkTargetRepositoryId='publication-target';$registration.FrameworkTargetSiblingDirectory='target'}
 $raw=@(& (Join-Path $frameworkRoot 'scripts/register-project.ps1') @registration 2>&1|ForEach-Object{[string]$_})
 $registrationCode=$LASTEXITCODE
 if(-not[IO.File]::Exists((Join-Path $project '.ai-workspace/project.json'))){throw ('ACTUAL_REGISTRATION_FAILED|'+($raw-join';'))}
 $taskRelative='.ai-workspace/tasks/active/PUBLICATION-001.md';$task=Join-Path $project $taskRelative
 SaveText $task "# PUBLICATION-001`n- Owner: publication-actor`n- Work route: actor=publication-actor; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
 $runtime=Join-Path $project '.ai-workspace/runtime/PUBLICATION-001/publication-actor';$null=[IO.Directory]::CreateDirectory($runtime)
 $configPath=Join-Path $project '.ai-workspace/project.json';$policyPath=Join-Path $project '.ai-workspace/process-policy.json'
 SaveText (Join-Path $project 'standards/data.md') "# Data convention`n<!-- FIRST -->`nUse one explicit record.`n<!-- /FIRST -->`n<!-- SECOND -->`nKeep the original identifier.`n<!-- /SECOND -->`n"
 SaveText (Join-Path $project 'standards/noop.md') "# Unchanged convention`nRetain this complete file.`n"
 $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
 SaveText (Join-Path $runtime 'adoption.md') 'Isolated fixture decision adopts exactly the professional standards directory for explicit rule reading.'
 $policy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
 if($EmptyPolicy){
  Check ($registrationCode-eq0-and@($policy.rules).Count-eq0-and@($config.sourceBindings).Count-eq0) 'real-ordinary-REGISTER-produces-empty-rules-and-bindings'
  SaveJson (Join-Path $runtime 'empty-registration.json') @{exitCode=$registrationCode;output=$raw;configRef=(Reference $configPath);policyRef=(Reference $policyPath)}
 }else{
  $config.sourceBindings=@(NewFixtureSourceBinding);SaveJson $configPath $config
  $policy.rules=@($policy.rules|Where-Object ruleId -CEQ FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY)
  foreach($id in @('FIRST','SECOND')+@(if(-not$Singleton){'NOOP'})){$policy.rules+=,(FixtureRule $project $config.sourceBindings $id preimage)}
  SaveFixturePolicy $policyPath $policy $copy
 }
 return [pscustomobject]@{caseId=$Name;root=$project;framework=$frameworkRoot;version=$copy;runtime=$runtime;taskPath=$task;taskRelative=$taskRelative;configPath=$configPath;policyPath=$policyPath;maintenance=[bool]$Maintenance;emptyPolicy=[bool]$EmptyPolicy;singleton=[bool]$Singleton;readyName=$readyName;releaseName=$releaseName}
}

function FixtureRule([string]$Root,$Bindings,[string]$Id,[string]$Side){
 $path=if($Id-ceq'NOOP'){'standards/noop.md'}elseif($Id-ceq'NEW'){'standards/new.md'}else{'standards/data.md'}
 $formal=Join-Path $Root $path;$candidate=if($Side-ceq'postimage'-and$Id-cne'NOOP'){Join-Path $Root ('.ai-workspace/runtime/PUBLICATION-001/publication-actor/'+[IO.Path]::GetFileName($path)+'.after')}else{$formal}
 $identity=Identity $candidate
 $document=[pscustomobject]@{sourceId=$Id;bindingId='professional';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=$identity};locator=$path;identity=$identity;mode=$(if($Id-cin@('FIRST','SECOND')){'MARKED_SECTION'}else{'FULL_FILE'});sectionStart=$(if($Id-cin@('FIRST','SECOND')){'<!-- '+$Id+' -->'}else{'NOT_APPLICABLE'});sectionEnd=$(if($Id-cin@('FIRST','SECOND')){'<!-- /'+$Id+' -->'}else{'NOT_APPLICABLE'});dependencies=@()}
 $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='professional';itemId=$Id;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId=$Id;documents=@($document)}
 $descriptor.revision=Get-AiwContentRevision $descriptor $Bindings;$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
 return [pscustomobject]@{ruleId=$Id;requirementReason='Explicit fixture professional rule';decisionLocator='.ai-workspace/runtime/PUBLICATION-001/publication-actor/adoption.md';source=$descriptor;selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@(if($Id-ceq'SECOND'){'REVIEW_EXECUTE'});resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
}

function PreparePublication($Fixture){
 return InvokePublicationPhase $Fixture.caseId PUBLICATION_PREPARATION {PreparePublicationBody $Fixture}
}

function PreparePublicationBody($Fixture){
 $planClock=[Diagnostics.Stopwatch]::StartNew()
 $singleRule=$null-ne$Fixture.PSObject.Properties['singleRule']-and$Fixture.singleRule
 $root=$Fixture.root;$runtime=$Fixture.runtime;$config=Get-Content -LiteralPath $Fixture.configPath -Raw|ConvertFrom-Json -Depth 100;$policy=Get-Content -LiteralPath $Fixture.policyPath -Raw|ConvertFrom-Json -Depth 100
 $nextConfig=CopyValue $config;if($Fixture.emptyPolicy){$nextConfig.sourceBindings=@(NewFixtureSourceBinding)}
 $human=Join-Path $runtime 'human-decision.md';SaveText $human 'Isolated original fixture decision: publish the exact local professional docs and their complete adopted whole-file references, with forward recovery and inverse recovery before joint completion.';$userDecision=Identity $human
 $nextPolicy=CopyValue $policy
 if(-not$singleRule){
  SaveText (Join-Path $runtime 'data.md.after') "# Data convention`n<!-- FIRST -->`nUse two explicit records.`n<!-- /FIRST -->`n<!-- SECOND -->`nKeep the revised identifier.`n<!-- /SECOND -->`n"
  SaveText (Join-Path $runtime 'new.md.after') "# New convention`nUse the approved complete new file.`n"
  $nextPolicy.rules=@($policy.rules|Where-Object{$_.ruleId-cnotin@('FIRST','SECOND','NOOP','NEW')})
  foreach($id in @('FIRST','SECOND')+@(if(-not$Fixture.singleton){'NOOP';'NEW'})){$nextPolicy.rules+=,(FixtureRule $root $nextConfig.sourceBindings $id postimage)}
 }
 $extra=@();$narrowReview=$null-ne$Fixture.PSObject.Properties['scaleChangedPaths']
 if($narrowReview){
  $extra=@($Fixture.scaleChangedPaths)
  foreach($path in $extra){
   $post=Join-Path $runtime ([IO.Path]::GetFileName($path)+'.after');SaveText $post (([IO.File]::ReadAllText((Join-Path $root $path)))+"`nApply the reviewed revision to this professional rule.`n")
   foreach($rule in $nextPolicy.rules){
    if($null-eq$rule.PSObject.Properties['source']){continue}
    $changed=$false
    foreach($document in $rule.source.documents){
     if($document.locator-ceq$path){$document.identity=Identity $post;$document.revision.value=$document.identity;$changed=$true}
    }
    if($changed){$rule.source.revision=Get-AiwContentRevision $rule.source $nextConfig.sourceBindings;$rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source}
   }
  }
 }
 # Only this dedicated oracle changes target-side selection. Original receipt
 # sourceBindings remain equal; the real plan records this selector change.
 if($null-ne$Fixture.PSObject.Properties['targetStandardsPair']){
  $targetRule=@($nextPolicy.rules|Where-Object ruleId -CEQ TARGET_SIDE_ONLY)
  if($targetRule.Count-ne1){throw 'TEST_TARGET_SIDE_RULE_REQUIRED'}
  $targetCopy=CopyValue $targetRule[0]
  $targetCopy.selectors.actionKinds=@('CONTROL_WRITE')
  if($null-ne$Fixture.PSObject.Properties['jointTargetObligations']){
   $targetCopy.preparationRequirements=@('JOINT_CONTROL_ONLY_PREPARATION')
   $targetCopy.resultRequirements=@('JOINT_CONTROL_ONLY_RESULT')
  }
  $nextPolicy.rules=@($nextPolicy.rules|ForEach-Object{if($_.ruleId-ceq'TARGET_SIDE_ONLY'){$targetCopy}else{$_}})
 }
 $configCandidate=Join-Path $runtime 'project.json.after';$policyCandidate=Join-Path $runtime 'process-policy.json.after';SaveJson $configCandidate $nextConfig;SaveFixturePolicy $policyCandidate $nextPolicy $Fixture.version
 $objects=@()
 $sourcePaths=@(if(-not$singleRule){'standards/data.md';if(-not$Fixture.singleton){'standards/new.md';if(-not$narrowReview){'standards/noop.md'}}})+$extra
 foreach($path in $sourcePaths+@('.ai-workspace/process-policy.json','.ai-workspace/project.json')){
  $formal=Join-Path $root $path;$old=Identity $formal;$member=if($path.StartsWith('.ai-workspace/')){'CONTROL'}else{'SOURCE'}
  $before=if($old-ceq'NEW'){[pscustomobject]@{path=$path;identity='NEW'}}else{$q=Join-Path $runtime ([IO.Path]::GetFileName($path)+'.before');[IO.File]::WriteAllBytes($q,[IO.File]::ReadAllBytes($formal));Reference $q}
  $after=switch($path){'.ai-workspace/project.json' {$configCandidate} '.ai-workspace/process-policy.json' {$policyCandidate} 'standards/noop.md' {$q=Join-Path $runtime 'noop.md.after';[IO.File]::WriteAllBytes($q,[IO.File]::ReadAllBytes($formal));$q} default {Join-Path $runtime ([IO.Path]::GetFileName($path)+'.after')}}
  $objects+=,[pscustomobject]@{path=$path;ownerMember=$member;preimage=$before;postimage=(Reference $after)}
 }
 $decisionPath=Join-Path $runtime 'publication-decision.json'
 SaveJson $decisionPath @{schemaVersion=1;kind='PROJECT_SOURCE_PUBLICATION_DECISION';projectRoot=$root;taskId='PUBLICATION-001';owner='publication-actor';actor='publication-actor';userDecision=$userDecision;documents=@($objects|Where-Object ownerMember -CEQ SOURCE|ForEach-Object{[pscustomobject]@{path=$_.path;write=$true;recoverBeforeCommit=$true;purpose='Owned professional convention explicitly covered by the original fixture decision.'}});forwardRecovery=$true;inverseRecoveryBeforeCommit=$true}
 $pub=@(Import-Module (Join-Path $Fixture.version 'scripts/ProjectSourcePublication.psm1') -PassThru)[0]
 $plan=[pscustomobject]@{schemaVersion=1;kind='PROJECT_SOURCE_PUBLICATION_PLAN';projectRoot=$root;repositoryId=$(if($Fixture.maintenance){'CONTROL'}else{'REPO_LOCAL'});frameworkRoot=$Fixture.framework;taskPath=$Fixture.taskRelative;taskId='PUBLICATION-001';taskIdentity=(Identity $Fixture.taskPath);owner='publication-actor';actor='publication-actor';controllerIdentity=(Identity (Join-Path $root '.ai-workspace/controller.json'));projectConfigIdentity=(Identity $Fixture.configPath);userDecision=$userDecision;decisionRef=(Reference $decisionPath);assuranceEvidence=@();objects=$objects;writeOrder=@($objects|Where-Object{$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object path);permissionChanges=$null;selectorChanges=@();sourceClosure=$null;rootToolDependencies=@(Get-AiwSourceChangeRootTools $Fixture.framework)}
  $documents=InvokePublicationPhase $Fixture.caseId PLAN_DOCUMENTS {& $pub {param($p,$r)Get-PubObjectDocuments $p $r @()} $plan $root}
  $closures=InvokePublicationPhase $Fixture.caseId PLAN_CLOSURES {& $pub {param($p,$d,$r)Get-PubClosurePair $p $d $r @()} $plan $documents.documents $root}
 $plan.sourceClosure=$closures
 $plan.selectorChanges=@(& $pub {param($a,$b)Get-PubSelectorChanges $a $b} $policy $nextPolicy)
 $dummyPackage=[pscustomobject]@{issuerRole='PROJECT_CONTROLLER'};$plan.permissionChanges=Get-AiwProjectSourcePermissionChanges $config $nextConfig $dummyPackage
 if($narrowReview){
  $plan|Add-Member reviewScope @($objects|Where-Object{$_.path-cin$plan.writeOrder}|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$_.postimage.identity}})
  $candidates=@($objects|Where-Object{$_.path-cin$plan.writeOrder}|ForEach-Object{[pscustomobject]@{path=[IO.Path]::GetRelativePath($root,$_.postimage.path).Replace('\','/');identity=$_.postimage.identity}})
  $selfPath=Join-Path $runtime 'publication-self.json'
  SaveJson $selfPath @{schemaVersion=1;taskId='PUBLICATION-001';actor='publication-actor';candidateObjects=$candidates;requirementsRef=(Reference $human);outcome='PASS';checks=@(@{id='fixture-assurance';method='MODEL_JUDGMENT';outcome='PASS';reason='Simulated professional assurance for testing exact M/A/R mechanics; no claim of a real model review.';evidenceLocators=@((Reference $human))});evidenceLocators=@((Reference $human))}
  $self=Reference $selfPath;$self|Add-Member kind SELF_CHECK;$plan.assuranceEvidence=@($self)
 }
 if($null-ne$Fixture.PSObject.Properties['historicalAssurance']-and$Fixture.historicalAssurance){AddHistoricalAssurance $Fixture $plan (Reference $human)}
 $planPath=Join-Path $runtime 'publication-plan.json';SaveJson $planPath $plan;$planRef=Reference $planPath
 $planClock.Stop();Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) 'PLAN_CONSTRUCTION' END @{caseId=$Fixture.caseId;stage='PLAN_CONSTRUCTION';wallSeconds=$planClock.Elapsed.TotalSeconds;planRef=$planRef}
 AssertSingleRuleBudget PLAN_CONSTRUCTION $planClock.Elapsed.TotalSeconds
 $members=@{}
 foreach($member in @('SOURCE','CONTROL')){
  $action=if($member-ceq'SOURCE'){'SOURCE_WRITE'}else{'CONTROL_WRITE'};$paths=@($objects|Where-Object{$_.ownerMember-ceq$member-and$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object path)
  $package=[pscustomobject]@{schemaVersion=$(if($Fixture.maintenance){2}else{1});frameworkVersion='2.0.0';taskId='PUBLICATION-001';profile='STANDARD';lifecycle='ACTIVE';owner='publication-actor';issuer='publication-actor';issuerRole='PROJECT_CONTROLLER';grantee='publication-actor';bundle='LOCAL_BOUNDED';decisionClass='PRODUCT_RESULT';userConfirmation=$userDecision;reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=$plan.taskIdentity;actions=@($action);exactPaths=$paths;objectIdentities=@($objects|Where-Object{$_.ownerMember-ceq$member-and$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$_.preimage.identity}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=$plan.projectConfigIdentity;issuerControllerId='publication-actor';issuerControllerEpoch=1;controllerControlIdentity=$plan.controllerIdentity;sourcePublicationBinding=[pscustomobject]@{planRef=$planRef;member=$member}}
  if($Fixture.maintenance){$package|Add-Member -NotePropertyName repositoryId -NotePropertyValue CONTROL;$package.invalidatesOn+='REPOSITORY_CHANGE'}
  $packagePath=Join-Path $runtime ($member.ToLowerInvariant()+'-package.json');SaveJson $packagePath $package
  $checker=Join-Path $Fixture.version 'scripts/check-authorization.ps1';$check=@{PackagePath=$packagePath;ObservedActor='publication-actor';ObservedTaskId=$plan.taskId;ObservedOwner=$plan.owner;ObservedAction=@($action);ObservedPath=$paths;ObservedIdentity=@($package.objectIdentities|ForEach-Object{$_.path+'='+$_.identity});ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=$plan.projectConfigIdentity;TaskPath=$Fixture.taskRelative;ExpectedTaskIdentity=$plan.taskIdentity;ControllerControlPath='.ai-workspace/controller.json'}
  if($Fixture.maintenance){$checker=Join-Path $Fixture.framework 'scripts/check-framework-maintenance-authorization.ps1';$check.ControlRepositoryPath=$root;$check.ObservedRepositoryId='CONTROL'}
  $memberClock=[Diagnostics.Stopwatch]::StartNew()
  $checked=InvokePublicationPhase $Fixture.caseId ($member+'_CHECKER') {FixtureChecker $root $checker $check};$out=$checked.output;$code=$checked.code
  $checkerRaw=Assert-AiwTestPath (Join-Path $phaseDirectory ($member.ToLowerInvariant()+'-checker-'+[guid]::NewGuid().ToString('N')+'.json'));SaveJson $checkerRaw @{exitCode=$code;output=@($out)}
  Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) ($member+'_CHECKER_RAW') REACHED @{caseId=$Fixture.caseId;outputRef=(Reference $checkerRaw)}
  Check ($code-eq0) ('actual-'+$member+'-checker')
  AssertSingleRuleBudget ($member+'_CHECKER_DISCOVER') $memberClock.Elapsed.TotalSeconds
  $intent=[pscustomobject]@{schemaVersion=2;objective='Publish the explicitly approved owned professional convention and its whole-file adoption.';requestedActionKind=$action;requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('owned professional rule publication');pathHints=$paths;capabilityHints=@();mutationHints=@($(if($member-ceq'SOURCE'){'source'}else{'control'}));externalHints=@();ambiguityState='CLEAR';facets=[pscustomobject]@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:implementation')};deliverableType=@{state='KNOWN';values=@('aiw:rule')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}
  $inputPath=Join-Path $runtime ($member.ToLowerInvariant()+'-discover.json');$compactPath=Join-Path $runtime ($member.ToLowerInvariant()+'-compact.json')
  SaveJson $inputPath @{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$root;frameworkRoot=$Fixture.framework;taskPath=$Fixture.taskPath;expectedProjectConfigIdentity=$plan.projectConfigIdentity;expectedCorrectionsIdentity=(Identity (Join-Path $root '.ai-workspace/corrections.json'));expectedTaskIdentity=$plan.taskIdentity;observedActor='publication-actor';capabilities=@($config.frameworkCapabilities.PSObject.Properties|Where-Object{$_.Value.enabled}|ForEach-Object Name);exactPaths=$paths;forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Identity $packagePath);userDecision=$userDecision;recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
  $run=InvokePublicationPhase $Fixture.caseId ($member+'_DISCOVER') {FixtureBoundary $Fixture $inputPath $compactPath};Check ($run.code-eq0-and$run.value.status-ceq'PASS') ('actual-'+$member+'-old-source-DISCOVER')
  $memberClock.Stop();$memberStage=$member+'_CHECKER_DISCOVER'
  Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) $memberStage END @{caseId=$Fixture.caseId;stage=$memberStage;wallSeconds=$memberClock.Elapsed.TotalSeconds}
  AssertSingleRuleBudget $memberStage $memberClock.Elapsed.TotalSeconds
  $members[$member]=[pscustomobject]@{package=$package;packagePath=$packagePath;checker=$checker;checkerArgs=$check;receipt=$run.value.compactReceipt;receiptRef=(Reference $compactPath)}
 }
 # Invoke the exact fixture module's bound export after the original gates.
 $composer=@(Import-Module (Join-Path $Fixture.version 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
  $prepared=InvokePublicationPhase $Fixture.caseId COMMON_TARGET_PREPARATION {& $composer.ExportedCommands['New-AiwProjectSourceChangePreparation'] -DiscoverReceiptPath $members.CONTROL.receiptRef.path -ExpectedDiscoverReceiptIdentity $members.CONTROL.receiptRef.identity -ConfigPostimagePath $configCandidate -PolicyPostimagePath $policyCandidate -DecisionRef $plan.decisionRef -OutputDirectory (Join-Path $runtime 'prepared') -PublicationPlanRef $planRef -PublicationSourceReceiptRef $members.SOURCE.receiptRef -SourcePostimages @($objects|Where-Object ownerMember -CEQ SOURCE|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$_.postimage.identity}})}
 Check ($prepared.members.Count-eq2-and-not$prepared.projectWritePerformed) 'common-target-preparation-writes-no-formal-object'
 $admitPaths=@{};$admitRuns=@{};$finalPaths=@{}
 foreach($member in @('SOURCE','CONTROL')){
  $m=$members[$member];$target=@($prepared.members|Where-Object member -CEQ $member)[0]
  $input=[pscustomobject]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$m.receiptRef.path;expectedDiscoverReceiptIdentity=$m.receiptRef.identity;preparationReceipts=@($m.receipt.selectedObligations.preparationRequirements+$target.preparationRequirements|Sort-Object -Unique)+@($prepared.preparationReceipt);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity=$userDecision;protectionState='BOUND';evidenceRefs=@()}
  $admitPaths[$member]=Join-Path $runtime ($member.ToLowerInvariant()+'-admit.json');SaveJson $admitPaths[$member] $input
  $final=CopyValue $input;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@($m.receipt.selectedObligations.resultRequirements+$target.resultRequirements|Sort-Object -Unique)+@($objects|Where-Object{$_.ownerMember-ceq$member-and$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.postimage.identity})
  $finalPaths[$member]=Join-Path $runtime ($member.ToLowerInvariant()+'-finalize.json');SaveJson $finalPaths[$member] $final
 }
 if($PublicationBoundaryMode-ceq'JOINT'){
  $joint=InvokePublicationPhase $Fixture.caseId PUBLICATION_ADMIT {FixtureBoundary $Fixture $admitPaths.CONTROL -PublicationSourceInputPath $admitPaths.SOURCE}
  Check ($joint.code-eq0-and$joint.value.status-ceq'PASS'-and$joint.value.kind-ceq'PROJECT_SOURCE_PUBLICATION_BOUNDARY_PAIR'-and($joint.value.members.member-join'|')-ceq'SOURCE|CONTROL') 'actual-joint-publication-ADMIT'
  foreach($result in $joint.value.members){
   $text=[string]::Join("`n",@($result.response.output));$value=$text|ConvertFrom-Json -Depth 100
   $admitRuns[$result.member]=[pscustomobject]@{code=$result.response.exitCode;text=$text;value=$value}
  }
 }else{
  foreach($member in @('SOURCE','CONTROL')){$admitRuns[$member]=InvokePublicationPhase $Fixture.caseId ($member+'_ADMIT') {FixtureBoundary $Fixture $admitPaths[$member]}}
 }
 $recoveryMembers=@()
 foreach($member in @('SOURCE','CONTROL')){
  $run=$admitRuns[$member];Check ($run.code-eq0-and$run.value.status-ceq'PASS'-and$run.value.projectSourcePreparation.outcome-ceq'PREPARED') ('actual-'+$member+'-ADMIT')
  $admitResultPath=Join-Path $runtime ($member.ToLowerInvariant()+'-admit-result.json');SaveJson $admitResultPath $run.value
  $recoveryMembers+=,[pscustomobject]@{member=$member;discoverReceiptRef=$members[$member].receiptRef;admitInputRef=(Reference $admitPaths[$member]);admitResultRef=(Reference $admitResultPath);finalizeInputRef=(Reference $finalPaths[$member])}
 }
 $recovery=[pscustomobject]@{schemaVersion=3;kind='PROJECT_SOURCE_PUBLICATION_RECOVERY';projectRoot=$root;planRef=$planRef;candidateRef=$prepared.candidate;members=$recoveryMembers}
 $recoveryPath=Join-Path $runtime 'recovery.json';SaveJson $recoveryPath $recovery
 return [pscustomobject]@{fixture=$Fixture;plan=$plan;planRef=$planRef;pub=$pub;members=$members;prepared=$prepared;recovery=$recovery;recoveryPath=$recoveryPath;recoveryRef=(Reference $recoveryPath)}
}

function FixtureBoundary($Fixture,[string]$InputPath,[string]$CompactPath='',[string]$PublicationSourceInputPath='',[string]$ExpectedPublicationSourceInputIdentity=''){
 $entry=if($Fixture.maintenance){Join-Path $Fixture.framework 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $Fixture.version 'scripts/resolve-process-requirements.ps1'}
 $args=@{InputPath=$InputPath;AsJson=$true};if($CompactPath){$args.CompactReceiptPath=$CompactPath}
 if($PublicationSourceInputPath){$args.PublicationSourceInputPath=$PublicationSourceInputPath;$args.ExpectedPublicationSourceInputIdentity=if($ExpectedPublicationSourceInputIdentity){$ExpectedPublicationSourceInputIdentity}else{Identity $PublicationSourceInputPath}}
  $raw=@(& $entry @args 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE;$text=$raw-join"`n"
  $rawId=[guid]::NewGuid().ToString('N');$outputPath=Assert-AiwTestPath (Join-Path $phaseDirectory ('boundary-'+$rawId+'.output.txt'));SaveText $outputPath $text
  $inputCopy=Assert-AiwTestPath (Join-Path $phaseDirectory ('boundary-'+$rawId+'.input.json'));[IO.File]::Copy($InputPath,$inputCopy,$false)
  Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) 'BOUNDARY_RAW' REACHED @{caseId=$Fixture.caseId;inputRef=(Reference $InputPath);publicationSourceInputRef=$(if($PublicationSourceInputPath){Reference $PublicationSourceInputPath}else{$null});retainedInputRef=(Reference $inputCopy);outputRef=(Reference $outputPath);exitCode=$code}
 $value=$null;try{$value=$text|ConvertFrom-Json -Depth 100}catch{}
 return [pscustomobject]@{code=$code;text=$text;value=$value}
}

function AddHistoricalAssurance($Fixture,$Plan,$Requirements){
 # The old acceptance covers today's exact A snapshots, but its completed
 # prerequisite covers an earlier AGENTS candidate. All originals are real
 # isolated public boundaries, with no new field in either old typed record.
 $root=$Fixture.root;$runtime=$Fixture.runtime
 $taskBytes=[IO.File]::ReadAllBytes($Fixture.taskPath)
 $agents=Join-Path $root 'AGENTS.md';$oldAgents=[pscustomobject]@{path='AGENTS.md';identity=(Identity $agents)}
 $candidates=@($Plan.objects|ForEach-Object{[pscustomobject]@{path=[IO.Path]::GetRelativePath($root,$_.postimage.path).Replace('\','/');identity=$_.postimage.identity}})
 function FinalizeAssurance([string]$Name,[string]$Kind,$Candidates,$Prerequisites=@()){
  $action=if($Kind-ceq'SELF_CHECK'){'TEST_RUN'}else{'RESULT_ACCEPT'}
  $package=[pscustomobject]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='PUBLICATION-001';profile='STANDARD';lifecycle='ACTIVE';owner='publication-actor';issuer='publication-actor';issuerRole='TASK_OWNER';grantee='publication-actor';bundle='LOCAL_BOUNDED';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Identity $Fixture.taskPath);actions=@($action);exactPaths=@($Candidates.path);objectIdentities=@($Candidates);invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Identity $Fixture.configPath)}
  if($action-ceq'RESULT_ACCEPT'){$package|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=@($Candidates);requirementsRef=$Requirements;prerequisiteEvidenceRefs=@($Prerequisites);reservedUserDecisionRefs=@()})}
  $packagePath=Join-Path $runtime ($Name+'-package.json');SaveJson $packagePath $package
  $checked=FixtureChecker $root (Join-Path $Fixture.version 'scripts/check-authorization.ps1') @{PackagePath=$packagePath;ObservedActor='publication-actor';ObservedTaskId='PUBLICATION-001';ObservedOwner='publication-actor';ObservedAction=@($action);ObservedPath=@($Candidates.path);ObservedIdentity=@($Candidates|ForEach-Object{$_.path+'='+$_.identity});ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=$package.projectConfigIdentity;TaskPath=$Fixture.taskRelative;ExpectedTaskIdentity=$package.taskIdentity;ControllerControlPath='.ai-workspace/controller.json'}
  Check ($checked.code-eq0) ($Name+'-original-checker')
  $intent=@{schemaVersion=2;objective='Create isolated original completed assurance for the real publication consumer.';requestedActionKind=$action;requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=@($Candidates.path);capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:verification')};deliverableType=@{state='KNOWN';values=@('aiw:test-result')};stage=@{state='KNOWN';values=@('aiw:verification')}}}
  $input=@{schemaVersion=5;ruleLoad=@{mode='FULL'};mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$root;frameworkRoot=$Fixture.framework;taskPath=$Fixture.taskPath;expectedProjectConfigIdentity=$package.projectConfigIdentity;expectedCorrectionsIdentity=(Identity (Join-Path $root '.ai-workspace/corrections.json'));expectedTaskIdentity=$package.taskIdentity;observedActor='publication-actor';capabilities=@();exactPaths=@($Candidates.path);forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Identity $packagePath);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
  $discover=Join-Path $runtime ($Name+'-discover.json');$compact=Join-Path $runtime ($Name+'-compact.json');SaveJson $discover $input
  $d=FixtureBoundary $Fixture $discover $compact;Check ($d.code-eq0-and$d.value.status-ceq'PASS') ($Name+'-original-DISCOVER')
  $b=[pscustomobject]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compact;expectedDiscoverReceiptIdentity=(Identity $compact);preparationReceipts=@($d.value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  $admit=Join-Path $runtime ($Name+'-admit.json');SaveJson $admit $b;$a=FixtureBoundary $Fixture $admit
  Check ($a.code-eq0-and$a.value.status-ceq'PASS') ($Name+'-original-ADMIT')
  $record=[pscustomobject]@{schemaVersion=1;taskId='PUBLICATION-001';actor='publication-actor';candidateObjects=@($Candidates);requirementsRef=$Requirements;outcome=$(if($Kind-ceq'SELF_CHECK'){'PASS'}else{'ACCEPTED'});checks=@([pscustomobject]@{id='original-assurance';method='MODEL_JUDGMENT';outcome='PASS';reason='Isolated protocol fixture, not a real product review.';evidenceLocators=@($Requirements)});evidenceLocators=@($Requirements)}
  if($Kind-ceq'SELF_CHECK'){
   $record.evidenceLocators+=@($Candidates)
   $probe=Join-Path $runtime ($Name+'-candidate-command.ps1')
   SaveText $probe @'
param([string]$CandidatePath,[string]$ExpectedIdentity)
$bytes=[IO.File]::ReadAllBytes($CandidatePath)
$actual=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
if($actual-cne$ExpectedIdentity){exit 7}
Write-Output 'Actual original historical candidate bytes verified.'
exit 0
'@
   $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$probe,'-CandidatePath',(Join-Path $root $Candidates[0].path),'-ExpectedIdentity',$Candidates[0].identity) -WorkingDirectory $root -GroupId 'historical-assurance-command'
   $commandOutput=Join-Path $runtime ($Name+'-command-output.txt');SaveText $commandOutput ($run.Output-join"`n")
   $command=Join-Path $runtime ($Name+'-command-evidence.json');SaveJson $command ([pscustomobject]@{command=('pwsh -File '+$probe+' -CandidatePath '+$Candidates[0].path+' -ExpectedIdentity '+$Candidates[0].identity);exitCode=$run.Code;output=(Reference $commandOutput)})
   Check ($run.Code-eq0) ($Name+'-actual-candidate-command')
   $record.checks+=@([pscustomobject]@{id='original-command';method='COMMAND';outcome='PASS';reason='Actual isolated historical TEST command checked original candidate bytes; no synthetic exit is supplied.';evidenceLocators=@((Reference $command))})
  }else{$record|Add-Member authorizationRef (Reference $packagePath)}
  $recordPath=Join-Path $runtime ($Name+'-record.json');SaveJson $recordPath $record;$typed=Reference $recordPath;$typed|Add-Member kind $Kind
  $b.mode='FINALIZE_OUTPUT';$b.evidenceRefs=@($typed);$b.resultReceipts=@($d.value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@($Candidates|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.identity})
  $final=Join-Path $runtime ($Name+'-finalize.json');SaveJson $final $b;$f=FixtureBoundary $Fixture $final
  Check ($f.code-eq0-and$f.value.status-ceq'PASS') ($Name+'-original-FINALIZE')
  $result=Join-Path $runtime ($Name+'-finalize-result.json');SaveJson $result $f.value
  return [pscustomobject]@{typed=$typed;pair=[pscustomobject]@{inputRef=(Reference $final);resultRef=(Reference $result)}}
 }
 try{
  $self=FinalizeAssurance 'historical-self' SELF_CHECK @($oldAgents)
  $stages=@([pscustomobject]@{id='old-self';kind='SELF_CHECK';requiredBy=$Requirements;dependsOn=@();candidateRef=@($oldAgents);evidenceRefs=@($self.typed)},[pscustomobject]@{id='accept';kind='RESULT_ACCEPT';requiredBy=$Requirements;dependsOn=@('old-self');candidateRef=$candidates;evidenceRefs=@()})
  SaveText $Fixture.taskPath ($utf8.GetString($taskBytes)+"`n"+'```aiw-acceptance-plan'+"`n"+(@{schemaVersion=1;stages=$stages}|ConvertTo-Json -Depth 70 -Compress)+"`n"+'```'+"`n")
  $accept=FinalizeAssurance 'historical-accept' RESULT_ACCEPTANCE $candidates @($self.typed)
 }finally{[IO.File]::WriteAllBytes($Fixture.taskPath,$taskBytes)}
 [IO.File]::AppendAllText($agents,"`nLater legitimate isolated project instruction change.`n",$utf8)
 $Plan.assuranceEvidence=@($accept.typed)
 $Plan|Add-Member assuranceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($self.pair,$accept.pair)})
}

function TestHistoricalAssurance {
 $fixture=NewFixture 'historical-assurance' -Singleton;$fixture|Add-Member historicalAssurance $true
 $case=PreparePublication $fixture;$pub=$case.pub
 # PreparePublication has already executed both real member checkers,
 # DISCOVER, common target preparation and ADMIT using only the plan field.
 foreach($mutation in @('ABSENT','CURRENT_REFS','MISSING_ORIGINAL','WRONG_A')){
  $plan=CopyValue $case.plan
  switch($mutation){
   ABSENT {$plan.PSObject.Properties.Remove('assuranceConsumption');$reason='EVIDENCE_IDENTITY_DRIFT'}
   CURRENT_REFS {$plan.assuranceConsumption.purpose='CURRENT_CANDIDATE';$reason='EVIDENCE_CURRENT_HISTORY_REFS'}
   MISSING_ORIGINAL {$plan.assuranceConsumption.originalFinalize=@($plan.assuranceConsumption.originalFinalize[1]);$reason='EVIDENCE_HISTORICAL_FINALIZE_UNBOUND'}
   WRONG_A {$plan|Add-Member reviewScope @($plan.objects|Where-Object{$_.path-cin$plan.writeOrder}|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$_.postimage.identity}});$reason='EVIDENCE_CANDIDATE_SET'}
  }
  $path=Join-Path $fixture.runtime ($mutation+'-plan.json');SaveJson $path $plan
  $package=CopyValue $case.members.SOURCE.package;$package.sourcePublicationBinding.planRef=Reference $path
  Reject {& $pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $fixture.root $package} $reason ('historical-publication-'+$mutation)
 }
 $snapshot=$case.plan.objects[0].postimage.path;$snapshotBytes=[IO.File]::ReadAllBytes($snapshot)
 try{
  [IO.File]::AppendAllText($snapshot,'unaccepted candidate change',$utf8)
  Reject {& $pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $fixture.root $case.members.SOURCE.package} 'SOURCE_PUBLICATION_REF_DRIFT' 'historical-publication-keeps-current-A-bytes-strict'
 }finally{[IO.File]::WriteAllBytes($snapshot,$snapshotBytes)}
 Reject {& $pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $fixture.root $case.members.SOURCE.package @($snapshot)} 'PROTECTED|FORBIDDEN' 'historical-publication-keeps-current-A-protection'
 $completed=InvokePublication $case
 Check ($completed.status-ceq'COMPLETE'-and$completed.validations.Count-eq2) 'historical-plan-assurance-reaches-real-publication-and-both-original-finalizes'
}

function AddPublicationScaleSources($Fixture,[ValidateRange(1,56)][int]$ChangedRuleCount=5){
 $config=Get-Content -LiteralPath $Fixture.configPath -Raw|ConvertFrom-Json -Depth 100
 $policy=Get-Content -LiteralPath $Fixture.policyPath -Raw|ConvertFrom-Json -Depth 100
 foreach($index in 1..21){$binding=NewFixtureSourceBinding;$binding.id='scale-'+$index;$binding.allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator=('standards/scale-'+$index)});$config.sourceBindings+=,$binding}
 SaveJson $Fixture.configPath $config
 $roots=@()
 foreach($index in 1..56){
  $sourceIndex=1+(($index-1)%21);$bindingId='scale-'+$sourceIndex;$id='SCALE_'+$index;$count=if($index-le39){4}else{3};$docs=@();$dependencies=@()
  foreach($part in 1..($count-1)){
   $sourceId=$id+'_CONDITION_'+$part;$path='standards/scale-'+$sourceIndex+'/rule-'+$index+'-condition-'+$part+'.md'
   SaveText (Join-Path $Fixture.root $path) ('# Professional condition '+$sourceId+"`n"+('Preserve the reviewed inputs, declared permission, ordered dependency and bounded recovery for this convention. '*3)+"`n")
   $identity=Identity (Join-Path $Fixture.root $path);$dependencies+=,$sourceId
   $docs+=,[pscustomobject]@{sourceId=$sourceId;bindingId=$bindingId;revision=@{kind='CONTENT_IDENTITY';value=$identity};locator=$path;identity=$identity;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
  }
  $path='standards/scale-'+$sourceIndex+'/rule-'+$index+'.md';$roots+=,$path
  SaveText (Join-Path $Fixture.root $path) ('# Professional rule '+$id+"`n"+('Apply the complete professional convention with its declared conditions and ordered evidence. '*3)+"`n")
  $identity=Identity (Join-Path $Fixture.root $path)
  $docs+=,[pscustomobject]@{sourceId=$id;bindingId=$bindingId;revision=@{kind='CONTENT_IDENTITY';value=$identity};locator=$path;identity=$identity;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=$dependencies}
  $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$bindingId;itemId=$id;revision=@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId=$id;documents=$docs}
  $descriptor.revision=Get-AiwContentRevision $descriptor $config.sourceBindings;$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
  $policy.rules+=,[pscustomobject]@{ruleId=$id;requirementReason='Isolated Media-scale complete professional convention';decisionLocator='.ai-workspace/runtime/PUBLICATION-001/publication-actor/adoption.md';source=$descriptor;selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
 }
 SaveFixturePolicy $Fixture.policyPath $policy $Fixture.version
 $Fixture|Add-Member scaleChangedPaths @($roots|Select-Object -First $ChangedRuleCount)
 Check ($config.sourceBindings.Count-eq22-and$policy.rules.Count-eq59-and@($policy.rules.source.documents).Count-eq210) 'scale-22-bindings-59-rules-210-complete-document-references'
 return [pscustomobject]@{sourceBindings=$config.sourceBindings.Count;rules=$policy.rules.Count;documentReferences=@($policy.rules.source.documents).Count;sourceUtf8Bytes=(@(Get-ChildItem -LiteralPath (Join-Path $Fixture.root 'standards') -Recurse -File)|Measure-Object Length -Sum).Sum}
}

function TestPublicationReviewScope($Case){
 $fixture=$Case.fixture;$package=CopyValue $Case.members.SOURCE.package;$plan=CopyValue $Case.plan
 $planPath=Join-Path $fixture.runtime 'scope-test-plan.json'
 $strict=CopyValue $plan;$strict.PSObject.Properties.Remove('reviewScope');SaveJson $planPath $strict;$package.sourcePublicationBinding.planRef=Reference $planPath
 Reject {& $Case.pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $fixture.root $package} 'EVIDENCE_CANDIDATE_SET' 'legacy-no-reviewScope-still-requires-all-read-candidates'
 foreach($mutation in @('MISSING_WRITE','WRONG_IDENTITY','OUTSIDE_R')){
  $bad=CopyValue $plan
  switch($mutation){
   MISSING_WRITE {$bad.reviewScope=@($bad.reviewScope|Where-Object path -CNE '.ai-workspace/process-policy.json');$reason='REVIEW_WRITE_COVERAGE'}
   WRONG_IDENTITY {$bad.reviewScope[0].identity='1|'+('A'*64);$reason='REVIEW_SCOPE_DRIFT'}
   OUTSIDE_R {$bad.reviewScope+=,[pscustomobject]@{path='standards/noop.md';identity=(Identity (Join-Path $fixture.root 'standards/noop.md'))};$reason='REVIEW_SCOPE_DRIFT'}
  }
  SaveJson $planPath $bad;$package.sourcePublicationBinding.planRef=Reference $planPath
  Reject {& $Case.pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $fixture.root $package} $reason ('MRA-'+$mutation)
 }
 # Reaching an old-source byte change on a new public call disproves a cache
 # that only compares the plan manifest after a prior successful observation.
 $path=Join-Path $fixture.root 'standards/noop.md';$original=[IO.File]::ReadAllBytes($path)
 try{SaveText $path 'A third-party change to an unmodified dependency.';Reject {& $Case.pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $fixture.root $Case.members.SOURCE.package} 'CONTENT_IDENTITY_DRIFT|SOURCE_CLOSURE_DRIFT' 'new-public-request-reobserves-unmodified-source-member-bytes'}finally{[IO.File]::WriteAllBytes($path,$original)}
 # A second use inside one private boundary must still observe bytes, even
 # though its plan/config/permission references have not changed.
 try{
  & $Case.pub {
   param($case,$path)
   Invoke-PubClosureObservationScope -Body {
    param($case,$path)
    $null=Get-AiwProjectSourcePublicationEligibility $case.fixture.root $case.members.SOURCE.package
    [IO.File]::WriteAllText($path,'Unchanged manifest cannot authorize changed member bytes.')
    Get-AiwProjectSourcePublicationEligibility $case.fixture.root $case.members.SOURCE.package
   } -Arguments @($case,$path)
  } $Case $path|Out-Null
  throw 'TEST_EXPECTED_MEMBER_DRIFT'
 }catch{Check ($_.Exception.Message-match'SOURCE_PUBLICATION_REF_DRIFT') 'same-private-boundary-rechecks-unmodified-member-bytes'}finally{[IO.File]::WriteAllBytes($path,$original)}
 Check (& $Case.pub {$null-eq$script:PublicationClosureObservations}) 'private-observations-released-after-failure'
}

function TestPublicationScale {
 $fixture=NewFixture 'publication-scale';$workload=AddPublicationScaleSources $fixture
 $clock=[Diagnostics.Stopwatch]::StartNew();$case=PreparePublication $fixture
 Check ($case.plan.writeOrder.Count-eq8-and$case.plan.objects.Count-eq9-and$case.plan.reviewScope.Count-eq8) 'full-chain-eight-writes-nine-read-bindings-eight-assured-candidates'
 $result=InvokePublication $case;$clock.Stop()
 Check ($result.status-ceq'COMPLETE'-and$result.validations.Count-eq2-and$result.writes-eq8) 'scale-real-ordered-write-and-two-original-FINALIZE-complete'
 foreach($validation in $result.validations){$actual=Get-Content -LiteralPath $validation.outputRef.path -Raw|ConvertFrom-Json -Depth 100;Check ($actual.status-ceq'PASS'-and$actual.actionOutcome-ceq'OBSERVED'-and$actual.projectSourcePreparation.outcome-ceq'COMPLETED') ('scale-'+$validation.member+'-actual-FINALIZE')}
 $measurement=Assert-AiwTestPath (Join-Path $phaseDirectory ('publication-scale-'+$script:publicationPhaseRunId+'.json'))
 SaveJson $measurement @{workload=$workload;wallSeconds=$clock.Elapsed.TotalSeconds;timingScope='plan through actual ordered writes and both original FINALIZE; sequential member calls; fixture registration and negative checks excluded';phases=(Reference $script:publicationPhasePath);validations=$result.validations;targets=@{plan=60;memberCheckerDiscover=120;targetPreparation=180;memberAdmit=120;executionAndDoubleFinalize=240;criticalPath=720};limits=@{plan=120;memberCheckerDiscover=180;targetPreparation=300;memberAdmit=180;executionAndDoubleFinalize=420;criticalPath=1200}}
 Write-Output ('PUBLICATION_SCALE_MEASUREMENT|'+$measurement)
 TestPublicationReviewScope $case
}

function TestPublicationSingleRule {
 # Establish an already populated project separately. This is fixture setup,
 # not a second daily publication or a claimed real project adoption.
 $setup=[Diagnostics.Stopwatch]::StartNew()
 $fixture=NewFixture 'single-rule';$workload=AddPublicationScaleSources $fixture -ChangedRuleCount 1
 $fixture|Add-Member singleRule $true
 # Registration used these modules during setup. Unload that exact fixture's
 # modules so their first daily import is charged below, not hidden in setup.
 $modulePrefix=[IO.Path]::GetFullPath($fixture.framework).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
 $fixtureModules=@(Get-Module -All|Where-Object{$_.Path-and[IO.Path]::GetFullPath($_.Path).StartsWith($modulePrefix,[StringComparison]::OrdinalIgnoreCase)})
 foreach($module in $fixtureModules){Remove-Module -ModuleInfo $module}
 Check (@(Get-Module -All|Where-Object{$_.Path-and[IO.Path]::GetFullPath($_.Path).StartsWith($modulePrefix,[StringComparison]::OrdinalIgnoreCase)}).Count-eq0) 'single-rule-setup-does-not-preload-daily-fixture-modules'
 $setup.Stop()
 $setupRecord=Assert-AiwTestPath (Join-Path $phaseDirectory ('single-rule-world-'+$script:publicationPhaseRunId+'.json'))
 SaveJson $setupRecord @{wallSeconds=$setup.Elapsed.TotalSeconds;scope='isolated package copy/qualification, actual fixture registration and prepopulation of the existing 22-source/59-rule project';projectConfigRef=(Reference $fixture.configPath);policyRef=(Reference $fixture.policyPath);workload=$workload;dailyPublicationPerformed=$false}
 Write-Output ('SINGLE_RULE_PREBUILT_WORLD|'+$setupRecord)

 $clock=[Diagnostics.Stopwatch]::StartNew();$script:singleRuleClock=$clock;$case=$null;$result=$null;$complete=$false;$failure='NONE';$budgetRows=@()
 try{
  Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) SINGLE_RULE_DAILY_SCRIPT START @{caseId=$fixture.caseId;stage='SINGLE_RULE_DAILY_SCRIPT';overallTargetSeconds=$script:singleRuleBudgets.TOTAL[0];overallLimitSeconds=$script:singleRuleBudgets.TOTAL[1];runProtectionSeconds=$SingleRuleProtectionSeconds;processId=$PID}
  Import-Module (Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1')
  Import-Module (Join-Path $fixture.version 'scripts/ContentSources.psm1')
  $case=PreparePublication $fixture
  $changedPath=[string]$fixture.scaleChangedPaths[0]
  Check (($case.plan.writeOrder-join'|')-ceq($changedPath+'|.ai-workspace/process-policy.json')-and$case.plan.objects.Count-eq3-and$case.plan.reviewScope.Count-eq2) 'single-rule-two-actual-writes-three-candidate-read-bindings-two-assured-objects'
  $configObject=@($case.plan.objects|Where-Object path -CEQ '.ai-workspace/project.json')[0]
  Check ($configObject.preimage.identity-ceq$configObject.postimage.identity-and@($case.plan.permissionChanges.sourceBindings).Count-eq0-and@($case.plan.permissionChanges.knowledgeSources).Count-eq0-and@($case.plan.selectorChanges).Count-eq0) 'single-rule-permissions-config-selectors-unchanged-and-config-is-read-only'
  $oldSources=@{};foreach($document in $case.plan.sourceClosure.old.documents){$oldSources[$document.sourcePath]=$document.identity}
  $sourceDelta=@($case.plan.sourceClosure.target.documents|Where-Object{-not$oldSources.ContainsKey($_.sourcePath)-or$oldSources[$_.sourcePath]-cne$_.identity})
  Check ($oldSources.Count-eq209-and$case.plan.sourceClosure.target.documents.Count-eq209-and$sourceDelta.Count-eq1-and$sourceDelta[0].sourcePath-ceq[IO.Path]::GetFullPath((Join-Path $fixture.root $changedPath))) 'single-rule-complete-209-physical-source-members-only-one-body-changes'
  $result=InvokePublication $case
  Check ($result.status-ceq'COMPLETE'-and$result.validations.Count-eq2-and$result.writes-eq2) 'single-rule-real-two-writes-and-two-original-FINALIZE-complete'
  foreach($validation in $result.validations){
   $actual=Get-Content -LiteralPath $validation.outputRef.path -Raw|ConvertFrom-Json -Depth 100
   Check ($actual.status-ceq'PASS'-and$actual.actionOutcome-ceq'OBSERVED'-and$actual.projectSourcePreparation.outcome-ceq'COMPLETED') ('single-rule-'+$validation.member+'-actual-FINALIZE')
  }
  InvokePublicationPhase $fixture.caseId FINAL_LIVE_READBACK {
  foreach($object in $case.plan.objects){Check ((Identity (Join-Path $fixture.root $object.path))-ceq$object.postimage.identity) ('single-rule-usable-live-readback-'+$object.path)}
  $policyObject=@($case.plan.objects|Where-Object path -CEQ '.ai-workspace/process-policy.json')[0]
  $before=Get-Content -LiteralPath $policyObject.preimage.path -Raw|ConvertFrom-Json -Depth 100
  $after=Get-Content -LiteralPath $fixture.policyPath -Raw|ConvertFrom-Json -Depth 100
  $changedRules=@(foreach($rule in $after.rules){$old=@($before.rules|Where-Object ruleId -CEQ $rule.ruleId);if($old.Count-ne1-or($old[0]|ConvertTo-Json -Depth 100 -Compress)-cne($rule|ConvertTo-Json -Depth 100 -Compress)){$rule.ruleId}})
  Check ($after.rules.Count-eq59-and@($after.rules.source.documents).Count-eq210-and($changedRules-join'|')-ceq'SCALE_1') 'single-rule-only-existing-SCALE_1-descriptor-changes-no-rule-added-or-removed'
  }
  $complete=$true
  AssertSingleRuleBudget TOTAL $clock.Elapsed.TotalSeconds
 }catch{$failure=$_.Exception.Message;throw}finally{
  $clock.Stop();$script:singleRuleClock=$null
  Write-AiwTestPhase $script:publicationPhasePath $script:publicationPhaseRunId ('publication-'+$Group) SINGLE_RULE_DAILY_SCRIPT END @{caseId=$fixture.caseId;stage='SINGLE_RULE_DAILY_SCRIPT';observedWallSeconds=$clock.Elapsed.TotalSeconds;fullChainCompleted=$complete;failure=$failure;processId=$PID}
  $events=@(Get-Content -LiteralPath $script:publicationPhasePath|ForEach-Object{$_|ConvertFrom-Json -Depth 100}|Where-Object{$_.runId-ceq$script:publicationPhaseRunId-and$_.data.caseId-ceq$fixture.caseId})
  foreach($stage in $script:singleRuleBudgets.Keys){
   $ends=@($events|Where-Object{$_.event-ceq'END'-and$null-ne$_.data.PSObject.Properties['stage']-and$_.data.stage-ceq$stage})
   $seconds=if($stage-ceq'TOTAL'){if($complete){$clock.Elapsed.TotalSeconds}else{$null}}elseif($ends.Count-eq1){$ends[0].data.wallSeconds}else{$null}
   $budgetRows+=,[pscustomobject]@{stage=$stage;wallSeconds=$seconds;targetSeconds=$script:singleRuleBudgets[$stage][0];limitSeconds=$script:singleRuleBudgets[$stage][1];observation=$(if($null-eq$seconds){'NOT_COMPLETED'}else{'OBSERVED'});targetMet=($null-ne$seconds-and$seconds-le$script:singleRuleBudgets[$stage][0]);limitMet=($null-ne$seconds-and$seconds-le$script:singleRuleBudgets[$stage][1])}
  }
  $planEvents=@($events|Where-Object{$_.event-ceq'END'-and$null-ne$_.data.PSObject.Properties['stage']-and$_.data.stage-ceq'PLAN_CONSTRUCTION'})
  $measurement=Assert-AiwTestPath (Join-Path $phaseDirectory ('single-rule-'+$script:publicationPhaseRunId+'.json'))
  SaveJson $measurement @{
   scenario='ONE_EXISTING_RULE_IN_22_SOURCE_PROJECT';publicationBoundaryMode=$PublicationBoundaryMode;workload=$workload;fixturePreparationRef=(Reference $setupRecord);fixturePreparationWallSeconds=$setup.Elapsed.TotalSeconds
   observedWallSeconds=$clock.Elapsed.TotalSeconds;fullChainWallSeconds=$(if($complete){$clock.Elapsed.TotalSeconds}else{$null});fullChainObservation=$(if($complete){'COMPLETE'}else{'INCOMPLETE_FULL_WALL_UNKNOWN'});failure=$failure
   timingScope='fresh fixture module imports, candidate body/policy/descriptor preparation and plan, independent member checker/DISCOVER, common target preparation, the recorded LEGACY or JOINT admission mode with both actual member decisions, real ordered writes and both original FINALIZE through actual live readback; all calls sequential, no sum of nested timers'
   hostProcessState='WARM_TEST_HOST_WITH_FRESH_FIXTURE_MODULES';coldNativeLaunchWallSeconds='UNKNOWN'
   stages=$budgetRows;performanceQualified=($complete-and$clock.Elapsed.TotalSeconds-le$script:singleRuleBudgets.TOTAL[1]);stageBudgetPolicy='DIAGNOSTIC_ALLOCATIONS_NOT_STOP_CONDITIONS';overallBudgetPolicy='PENDING_ENGINEERING_TARGET_30_SECONDS_AND_LIMIT_60_SECONDS';runProtectionSeconds=$SingleRuleProtectionSeconds;profileHotPath=[bool]$ProfileHotPath;functionTimingSemantics='nested inclusive diagnostic observations; instrumentation overhead remains inside wall'
   functionProfileRef=$(if($ProfileHotPath-and[IO.File]::Exists($script:publicationProfilePath)){Reference $script:publicationProfilePath}else{$null})
   planRef=$(if($planEvents.Count-eq1){$planEvents[0].data.planRef}else{$null});phases=(Reference $script:publicationPhasePath);validations=@(if($null-ne$result){$result.validations})
   scopeExplanation=@('M: one existing professional rule body and its changed whole-file descriptor/revision/itemIdentity inside policy.','A: those same two changed objects; no permission/selector change.','Candidate read objects: body, policy and unchanged project configuration. Complete source read closure additionally retains all 209 physical members/210 ordered document references; R is not reduced to these three objects.')
   gateExplanation=@('PLAN freezes original decision, full old/target read closure and exact candidate.','SOURCE and CONTROL each retain their own independent checker, original-rule DISCOVER and real ADMIT.','Common preparation validates full target adoption without writing formal objects.','Root execution rechecks original pair and writes the admitted prefix; each member must finish its own original FINALIZE before the batch is usable.')
   budgetNature='Owner engineering candidate targets, not user quotas or demonstrated promises';modelAndHostTaskCost='UNKNOWN';heavyEightWriteWorkload='Separate PublicationScale scenario; old 720/1200-second thresholds do not establish daily usability.'
  }
  Write-Output ('SINGLE_RULE_MEASUREMENT|'+$measurement)
 }
 Check ($complete-and@($budgetRows|Where-Object{$_.stage-ceq'TOTAL'-and$_.limitMet}).Count-eq1) 'single-rule-complete-local-script-at-most-60-seconds-stage-budgets-diagnostic'
}

function InvokePublication($Case,[string]$Direction='COMPLETE',[int]$InterruptAfterWrite=-1){
 return InvokePublicationPhase $Case.fixture.caseId PUBLIC_ACTION {InvokePublicationBody $Case $Direction $InterruptAfterWrite}
}

function InvokePublicationBody($Case,[string]$Direction='COMPLETE',[int]$InterruptAfterWrite=-1){
 $args=@{ProjectId='publication-fixture';ToVersion='2.0.0';RepositoryPath=$Case.fixture.root;ProjectRuleRecoveryPlanPath=$Case.recoveryPath;ExpectedProjectRuleRecoveryPlanIdentity=$Case.recoveryRef.identity;ProjectRuleRecoveryDirection=$Direction;ActorRouteActor='publication-actor';Apply=$true}
 if($InterruptAfterWrite-ge0){$args.InterruptAfterAdoptionWrite=$InterruptAfterWrite}
 return & (Join-Path $Case.fixture.framework 'scripts/upgrade-project.ps1') @args
}

function TestPublicationBoundaries($Case){
 $fixture=$Case.fixture;$pub=$Case.pub;$original=$Case.members.SOURCE.package
 foreach($mutation in @('MEMBER','MIXED','TARGET','SCOPE','DECISION','CLOSURE')){
  $package=CopyValue $original
  switch($mutation){
   MEMBER {$package.sourcePublicationBinding.member='CONTROL';$reason='PURE_MEMBER_REQUIRED'}
   MIXED {$package.actions+=@('TEST_RUN');$reason='PURE_MEMBER_REQUIRED'}
   TARGET {if($fixture.maintenance){$package.repositoryId='publication-target'}else{$package.schemaVersion=2;$package|Add-Member repositoryId publication-target};$reason='PROJECT_OWNERSHIP_REQUIRED'}
   SCOPE {$package.exactPaths+=@('standards/outside.md');$reason='EXACT_MEMBER_SCOPE'}
   DECISION {$package.userConfirmation='different';$reason='AUTHORITY_BINDING'}
   CLOSURE {
    $plan=CopyValue $Case.plan;$plan.sourceClosure.target.documents=@();$path=Join-Path $fixture.runtime 'invalid-closure-plan.json';SaveJson $path $plan;$package.sourcePublicationBinding.planRef=Reference $path;$reason='COMPLETE_CLOSURE_DRIFT'
   }
  }
  Reject {& $pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $fixture.root $package} $reason ($mutation+'-reaches-publication-eligibility-rejection')
 }
 # An ordinary Maintenance SOURCE_WRITE package still reaches the original
 # CONTROL repository ban when it has no qualified publication binding.
 if($fixture.maintenance){
  $package=CopyValue $original;$package.PSObject.Properties.Remove('sourcePublicationBinding')
  $path=Join-Path $fixture.runtime 'ordinary-control-source-package.json';SaveJson $path $package
  $args=CopyValue ([pscustomobject]$Case.members.SOURCE.checkerArgs);$params=@{};foreach($property in $args.PSObject.Properties){$params[$property.Name]=$property.Value};$params.PackagePath=$path
  $checked=FixtureChecker $fixture.root $Case.members.SOURCE.checker $params;$out=$checked.output;$code=$checked.code
  Check ($code-ne0-and($out-join';')-match'CONTROL_REPOSITORY_ACTION_DENIED') 'unqualified-Maintenance-CONTROL-source-write-remains-forbidden'
 }
 # Exercise every binary state of the true three-object write set using the
 # real whole-object reachability layer. Noop objects stay frozen in all cases.
 $changed=@($Case.plan.objects|Where-Object{$_.path-cin$Case.plan.writeOrder})
 try{
  for($mask=0;$mask-lt(1-shl$changed.Count);$mask++){
   foreach($i in 0..($changed.Count-1)){$object=$changed[$i];$side=if($mask-band(1-shl$i)){$object.postimage}else{$object.preimage};$formal=Join-Path $fixture.root $object.path;if($side.identity-ceq'NEW'){if([IO.File]::Exists($formal)){[IO.File]::Delete($formal)}}else{[IO.File]::WriteAllBytes($formal,[IO.File]::ReadAllBytes($side.path))}}
   $legal=$mask-in@(0..$changed.Count|ForEach-Object{(1-shl$_)-1})
   if($legal){$state=& $pub.ExportedCommands['Get-AiwProjectSourcePublicationReachability'] $fixture.root $Case.plan;Check ($state.prefix-eq@($changed|Where-Object{(Identity (Join-Path $fixture.root $_.path))-ceq$_.postimage.identity}).Count) ('reachable-prefix-'+$mask)}
   else{Reject {& $pub.ExportedCommands['Get-AiwProjectSourcePublicationReachability'] $fixture.root $Case.plan} 'UNREACHABLE_GROUP' ('unreachable-whole-group-'+$mask)}
  }
  SaveText (Join-Path $fixture.root 'standards/data.md') 'Third-party bytes cannot be interpreted as either frozen image.'
  Reject {& $pub.ExportedCommands['Get-AiwProjectSourcePublicationReachability'] $fixture.root $Case.plan} 'THIRD_PARTY_OBJECT' 'third-party-whole-file-state-is-rejected'
 }finally{
  foreach($object in $Case.plan.objects){$formal=Join-Path $fixture.root $object.path;if($object.preimage.identity-ceq'NEW'){if([IO.File]::Exists($formal)){[IO.File]::Delete($formal)}}else{[IO.File]::WriteAllBytes($formal,[IO.File]::ReadAllBytes($object.preimage.path))}}
 }

}

function StartFixtureWorker($Call,[string]$Directory,[string]$BarrierNode=''){
 $id=[guid]::NewGuid().ToString('N');$callPath=Join-Path $Directory ($id+'-call.json');$workerPath=Join-Path $Directory ($id+'-worker.ps1');SaveJson $callPath $Call
 SaveText $workerPath ((@'
param([string]$CallPath)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
try{
 $call=Get-Content -LiteralPath $CallPath -Raw|ConvertFrom-Json -Depth 100
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','publication-actor','Process')
 switch($call.operation){
  'PARKED_READER' {
   $path=Join-Path $call.version 'scripts/ProcessRequirementComposition.psm1';$lines=[IO.File]::ReadAllLines($path)
   $anchor="        `$ownerPath = Resolve-AiwChildFile `$VersionDirectory `$OwnerModule 'NATIVE_REQUIREMENT_OWNER'"
   $line=1+[array]::IndexOf($lines,$anchor);if($line-le0){throw 'TEST_REAL_READER_ANCHOR'}
   $global:AiwReaderParked=$false;$global:AiwReaderReady=$call.ready;$global:AiwReaderRelease=$call.release
   $bp=Set-PSBreakpoint -Script $path -Line $line -Action {
    if(-not$global:AiwReaderParked){$global:AiwReaderParked=$true;$r=[Threading.EventWaitHandle]::OpenExisting($global:AiwReaderReady);$q=[Threading.EventWaitHandle]::OpenExisting($global:AiwReaderRelease);try{$r.Set()|Out-Null;if(-not$q.WaitOne(600000)){throw 'TEST_READER_RELEASE_TIMEOUT'}}finally{$r.Dispose();$q.Dispose()}}
   }
   try{& (Join-Path $call.version 'scripts/resolve-process-requirements.ps1') -InputPath $call.inputPath -AsJson;if($LASTEXITCODE-ne0){exit $LASTEXITCODE}}finally{Remove-PSBreakpoint $bp}
  }
  'DELIVERY' {
   $module=Import-Module (Join-Path $call.version 'scripts/WorkflowDelivery.psm1') -PassThru
   $receipt=[pscustomobject]@{actionKind='NONE';resultKind='USER_RESPONSE';taskId='ISOLATION';taskIdentity='NOT_APPLICABLE';taskOwner='isolation-owner';taskActor='isolation-owner';actor='isolation-owner';exactPaths=@();authorityContext=[pscustomobject]@{forbiddenScope=@();authorizationIdentity='NOT_REQUIRED'};sourceLocators=[pscustomobject]@{projectRoot=$call.root;frameworkRoot=$call.framework;taskRelativePath='NOT_APPLICABLE';authorizationPackagePath='NOT_REQUIRED'}}
   $boundary=[pscustomobject]@{deliveryContext=[pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}}
   $bound=& $module.ExportedCommands['Get-AiwBoundDelivery'] $receipt $boundary
   if($bound.delivery.status-cne'READY_TO_SEND'-or$bound.consumer.recipient-cne'USER'-or-not$bound.closureSatisfied){throw 'TEST_CLEAN_DELIVERY_RESULT'}
   if(Get-Command Get-AiwDeliveryObservation -ErrorAction SilentlyContinue){throw 'TEST_CLEAN_DELIVERY_AMBIENT_PROVIDER'}
   'CLEAN_DELIVERY_READY'
  }
  'PUBLICATION' {
   if($call.PSObject.Properties['barrier']){[Environment]::SetEnvironmentVariable('AIW_PUBLICATION_TEST_CALL',$CallPath,'Process')}
   $args=@{};foreach($property in $call.parameters.PSObject.Properties){$args[$property.Name]=$property.Value}
   & $call.tool @args|ConvertTo-Json -Depth 100 -Compress
  }
  'OBSERVE' {
   Import-Module $call.pub
   $aiwPublicationScopeLease=Enter-AiwProjectSourceScope $call.root
   try{[pscustomobject]@{status='OBSERVED';identity=(Get-FileHash -LiteralPath $call.document -Algorithm SHA256).Hash}|ConvertTo-Json -Compress}finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
  }
  'CONTENT' {
   Import-Module (Join-Path $call.version 'scripts/ContentSources.psm1')
   $context=New-AiwContentContext -ProjectRoot $call.root -ExpectedProjectConfigIdentity $call.configIdentity
   'CONTENT_OBSERVED'
  }
  'KNOWLEDGE' {
   Import-Module (Join-Path $call.version 'scripts/KnowledgeSources.psm1')
   Invoke-AiwKnowledgeQuery -ProjectRoot $call.root -ExpectedProjectConfigIdentity $call.configIdentity|ConvertTo-Json -Depth 100 -Compress
  }
  'COMPOSER' {
   Import-Module (Join-Path $call.version 'scripts/ProcessRequirementComposition.psm1')
   Get-AiwProcessBindingSnapshot -ProjectRoot $call.root -FrameworkRoot $call.framework -TargetVersion 2.0.0 -TaskRelativePath $call.taskRelative|ConvertTo-Json -Depth 100 -Compress
  }
  'ADOPTION' {
   Import-Module (Join-Path $call.framework 'scripts/ProjectAdoptionState.psm1')
   Get-AiwProjectFormat -RepositoryRoot $call.root|ConvertTo-Json -Depth 100 -Compress
  }
  'TRANSITION' {
   & (Join-Path $call.version 'scripts/resolve-control-transition.ps1') -InputPath $call.inputPath -AsJson
   if($LASTEXITCODE-ne0){exit $LASTEXITCODE}
  }
  'HOLD' {
   Import-Module $call.pub
   $aiwPublicationScopeLease=Enter-AiwProjectSourceScope $call.root -Mode $call.mode
   try{
    [Threading.EventWaitHandle]::OpenExisting($call.ready).Set()|Out-Null
    [Threading.EventWaitHandle]::OpenExisting($call.release).WaitOne()|Out-Null
    'RELEASED'
   }finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
  }
 }
}catch{[pscustomobject]@{status='FAIL';reason=$_.Exception.Message}|ConvertTo-Json -Compress;exit 2}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $handle=Start-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$workerPath,'-CallPath',$callPath) -GroupId ('publication-'+$Group)
 if($script:crashSceneTracking){$script:crashSceneHandles.Add($handle)}
 $caseId=if($Call.ContainsKey('caseId')){$Call.caseId}else{$Directory};$step='worker-'+$Call.operation
 Write-AiwTestPhase $handle.Phases $handle.RunId $handle.GroupId $step START @{caseId=$caseId;operation=$Call.operation;node=$BarrierNode;observation='NATIVE_WORKER_LAUNCHED'}
 return [pscustomobject]@{process=$handle.Process;handle=$handle;finished=$false;callPath=$callPath;workerPath=$workerPath;caseId=$caseId;phaseStep=$step;phaseReached=$false;barrierNode=$BarrierNode}
}

function FinishFixtureWorker($Worker,[string]$Label){
 # Existing per-worker budget. A soft diagnostic never authorizes cancellation.
 $timedOut=$false
 do{
  $run=Wait-AiwTestProcess $Worker.handle -WaitMilliseconds 30000
  if($run.Status-ceq'RUNNING'-and$Worker.handle.Timer.ElapsedMilliseconds-ge600000){
   $timedOut=$true;Stop-AiwTestProcess $Worker.handle $Worker.handle.RunId ('Existing 600000ms per-worker test budget: '+$Label)
  }
 }while($run.Status-ceq'RUNNING')
 $Worker.finished=$true
 $end=@{caseId=$Worker.caseId;node=$Worker.barrierNode;label=$Label;status=$run.Status;exitCode=$run.Code;resultPath=$run.ResultPath;observation='ACTUAL_NATIVE_EXIT_AND_DRAIN'}
 if(-not$Worker.phaseReached){Write-AiwTestPhase $Worker.handle.Phases $Worker.handle.RunId $Worker.handle.GroupId $Worker.phaseStep REACHED $end;$Worker.phaseReached=$true}
 Write-AiwTestPhase $Worker.handle.Phases $Worker.handle.RunId $Worker.handle.GroupId $Worker.phaseStep END $end
 if($Worker.barrierNode){Write-AiwTestPhase $Worker.handle.Phases $Worker.handle.RunId $Worker.handle.GroupId ('barrier-'+$Worker.barrierNode) END $end}
 if($timedOut){throw ('TEST_WORKER_TIMEOUT|'+$Label+'|result='+$run.ResultPath)}
 return [pscustomobject]@{code=$run.Code;text=$run.StdoutText;stderr=$run.StderrText;resultPath=$run.ResultPath}
}

function TransitionPreviewCall($Fixture){
 # A complete, valid controller-only preview reaches the actual public CLI.
 $path='.ai-workspace/controller.json';$before=[IO.File]::ReadAllBytes((Join-Path $Fixture.root $path));$controller=$utf8.GetString($before)|ConvertFrom-Json
 $controller.controllerId='successor-actor';$controller.controllerEpoch++
 $after=$utf8.GetBytes(($controller|ConvertTo-Json -Compress)+"`n")
 $images=@();foreach($bytes in @($before,$after)){$images+=@{identity=($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)));base64=[Convert]::ToBase64String($bytes)}}
 $loc=@{};foreach($name in @('package','discoverInput','discoverReceipt','admitInput','admitResult','finalizeInput','completionProof')){$loc[$name]=Join-Path $Fixture.runtime ('transition-'+$name+'.json')}
 $plan=@{schemaVersion=1;taskId='PUBLICATION-001';projectRoot=$Fixture.root;repositoryId='REPO_LOCAL';objects=@(@{path=$path;before=$images[0];after=$images[1]});allowedChanges=@(@{path=$path;fields=@('ControllerId','ControllerEpoch')});steps=@(@{path=$path;image='MARKED_BEFORE'},@{path=$path;image='MARKED_TARGET'},@{path=$path;image='AFTER'});recoveryActors=@('publication-actor','successor-actor');originalProcessLocators=$loc}
 $planPath=Join-Path $Fixture.runtime 'transition-plan.json';SaveJson $planPath $plan
 $intent=@{schemaVersion=2;objective='Preview the bounded fixture controller handoff.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('controller handoff');pathHints=@($path);capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:controller-handoff')};deliverableType=@{state='KNOWN';values=@('aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}
 SaveJson $loc.discoverInput @{schemaVersion=4;projectRoot=$Fixture.root;frameworkRoot=$Fixture.framework;taskPath=$Fixture.taskPath;expectedProjectConfigIdentity=(Identity $Fixture.configPath);expectedCorrectionsIdentity=(Identity (Join-Path $Fixture.root '.ai-workspace/corrections.json'));capabilities=@();forbiddenPaths=@();intentEnvelope=$intent}
 $inputPath=Join-Path $Fixture.runtime 'transition-request.json'
 SaveJson $inputPath @{operation='PREVIEW';projectRoot=$Fixture.root;planPath=$planPath;expectedPlanIdentity=(Identity $planPath);recoveryMode='NOT_APPLICABLE'}
 return @{operation='TRANSITION';version=$Fixture.version;inputPath=$inputPath}
}

function TestModuleIsolation {
 $case=Join-Path $temp 'module-isolation';$project=Join-Path $case 'project'
 foreach($directory in @($case,$project)){$null=[IO.Directory]::CreateDirectory($directory)}
 # The worker starts without the fixture builder's ambient composer import.
 $delivery=FinishFixtureWorker (StartFixtureWorker @{operation='DELIVERY';version=$versionRoot;framework=$sourceRoot;root=$project} $case) 'clean-delivery'
 Check ($delivery.code-eq0-and$delivery.text-match'CLEAN_DELIVERY_READY') ('clean-process-delivery-resolves-own-provider|'+$delivery.text)
 $owner=@(Import-Module (Join-Path $versionRoot 'scripts/ProjectSourcePublication.psm1') -PassThru)[0]
 $fake=[pscustomobject]@{root=$project;version='2.0.0';modulePath=$owner.Path;moduleIdentity=(Identity $owner.Path)}
 Reject {& $owner {param($p) Invoke-PubOriginalAdoptionScope -Proof $p -Mode WRITE -Body {throw 'UNQUALIFIED_BODY_REACHED'}} $fake} 'SOURCE_PUBLICATION_ADOPTION_ROOT_REQUIRED' 'ordinary-frame-cannot-create-adoption-bridge'
 $state=@(Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionState.psm1') -PassThru)[0]
 $fakeEntry=[pscustomobject]@{Invocation=$MyInvocation;BoundParameters=@{ToVersion='2.0.0';CurrentProcessInputPath='not-read.json';AdoptionProcessMode='PREPARE'}}
 Reject {& $state.ExportedCommands['Invoke-AiwRootAdoptionSourceScope'] -ProjectRoot $project -Mode WRITE -EntryContext $fakeEntry -Body {throw 'UNQUALIFIED_BODY_REACHED'}} 'ADOPTION_SCOPE_ROOT_ENTRY_REQUIRED' 'fake-entry-context-cannot-create-adoption-bridge'
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace'))) 'fake-adoption-rejected-before-source-or-synchronization-read'
 $fixture=NewFixture 'cold-control-transition'
 SaveText $fixture.taskPath ([IO.File]::ReadAllText($fixture.taskPath).Replace('# PUBLICATION-001','# PUBLICATION-001 - Source publication fixture'))
 $call=TransitionPreviewCall $fixture
 $preview=FinishFixtureWorker (StartFixtureWorker $call $fixture.runtime) 'cold-control-preview'
 Check ($preview.code-eq0-and($preview.text|ConvertFrom-Json -Depth 100).status-ceq'PREVIEW') 'cold-public-control-transition-preview-resolves-own-dependencies'
 $holder=& $owner.ExportedCommands['Enter-AiwProjectSourceScope'] $fixture.root WRITE
 try{
  $busy=FinishFixtureWorker (StartFixtureWorker $call $fixture.runtime) 'cold-control-busy'
  Check ($busy.code-eq0-and($busy.text|ConvertFrom-Json -Depth 100).status-ceq'PREVIEW') 'valid-control-preview-is-read-only-under-held-writer'
 }finally{& $owner.ExportedCommands['Exit-AiwProjectSourceScope'] $holder}
}

function TestPublicationClosurePair($Case){
 $fixture=$Case.fixture;$pub=$Case.pub;$root=$fixture.root;$plan=$Case.plan
 $documents=(& $pub {param($p,$r)Get-PubObjectDocuments $p $r @()} $plan $root).documents
 $reference=& $pub {param($p,$d,$r)[pscustomobject]@{old=(Get-PubClosure $p $d preimage $r @());target=(Get-PubClosure $p $d postimage $r @())}} $plan $documents $root
 $paired=& $pub {param($p,$d,$r)Get-PubClosurePair $p $d $r @()} $plan $documents $root
 Check ((Get-AiwContentDescriptorIdentity $paired)-ceq(Get-AiwContentDescriptorIdentity $reference)) 'publication-pair-matches-two-independent-full-projections'
 # Leave NOOP outside the planned objects so its current physical bytes, not
 # a frozen projected object, are the direct consumer of the reuse guard.
 $unlistedPlan=CopyValue $plan;$unlistedPlan.objects=@($unlistedPlan.objects|Where-Object path -CNE 'standards/noop.md')
 $old=& $pub {param($p,$d,$r)Get-PubClosureObservationCore $p $d preimage $r @() $null} $unlistedPlan $documents $root
 $noop=Join-Path $root 'standards/noop.md';$noopBytes=[IO.File]::ReadAllBytes($noop)
 try{
  SaveText $noop 'Unlisted unchanged member drifted after old-side observation.'
  Reject {& $pub {param($p,$d,$r,$m)Get-PubClosureObservationCore $p $d postimage $r @() $m} $unlistedPlan $documents $root $old.material} 'CONTENT_IDENTITY_DRIFT' 'publication-target-reobserves-unlisted-unchanged-member'
 }finally{[IO.File]::WriteAllBytes($noop,$noopBytes)}
 Reject {& $pub {param($p,$d,$r,$m,$ban)Get-PubClosureObservationCore $p $d postimage $r @($ban) $m} $unlistedPlan $documents $root $old.material $noop} 'FORBIDDEN_PATH' 'publication-target-new-protection-rejects-old-material'
 # The target projection has the same physical locator but different bytes.
 # It must not inherit the old side's successful validation of that locator.
 $key='standards/noop.md|postimage';$original=$documents[$key]
 try{
  $badBytes=$utf8.GetBytes('Changed projected whole file without readoption.')
  $documents[$key]=[pscustomobject]@{Bytes=$badBytes;Identity=(Get-AiwContentByteIdentity $badBytes)}
  Reject {& $pub {param($p,$d,$r)Get-PubClosurePair $p $d $r @()} $plan $documents $root} 'CONTENT_IDENTITY_DRIFT' 'publication-different-target-projection-cannot-borrow-old-body'
 }finally{$documents[$key]=$original}
 $afterFailure=& $pub {param($p,$d,$r)Get-PubClosurePair $p $d $r @()} $plan $documents $root
 Check ((Get-AiwContentDescriptorIdentity $afterFailure)-ceq(Get-AiwContentDescriptorIdentity $reference)) 'publication-failed-projection-does-not-poison-next-pair'
 # A nested complete pair must not replace its caller's local material. The
 # fixture hook delegates both real implementations; it supplies no proof.
 & $pub {
  $script:PairTestSavedCore=(Get-Item Function:Get-PubClosureObservationCore).ScriptBlock
  $script:PairTestNestedPending=$true;$script:PairTestNestedResult=$null
  Set-Item Function:script:Get-PubClosureObservationCore -Value {
   param($Plan,$Documents,[string]$Side,[string]$Root,[string[]]$Forbidden,$PreviousMaterial)
   if($script:PairTestNestedPending-and$Side-ceq'postimage'){
    $script:PairTestNestedPending=$false
    $script:PairTestNestedResult=Get-PubClosurePair $Plan $Documents $Root $Forbidden
   }
   & $script:PairTestSavedCore $Plan $Documents $Side $Root $Forbidden $PreviousMaterial
  }
 }
 try{
  $outer=& $pub {param($p,$d,$r)Get-PubClosurePair $p $d $r @()} $plan $documents $root
  $nested=& $pub {$script:PairTestNestedResult}
  Check ((Get-AiwContentDescriptorIdentity $outer)-ceq(Get-AiwContentDescriptorIdentity $reference)-and(Get-AiwContentDescriptorIdentity $nested)-ceq(Get-AiwContentDescriptorIdentity $reference)) 'nested-publication-pairs-keep-independent-old-target-material'
 }finally{
  & $pub {Set-Item Function:script:Get-PubClosureObservationCore -Value $script:PairTestSavedCore;Remove-Variable PairTestSavedCore,PairTestNestedPending,PairTestNestedResult -Scope Script}
 }
}

function TestPublicationSelectedMaterial($Case){
 $fixture=$Case.fixture;$pub=$Case.pub;$root=$fixture.root;$plan=$Case.plan
 $composer=@(Import-Module (Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
 $content=@(Import-Module (Join-Path $fixture.version 'scripts/ContentSources.psm1') -PassThru)[0]
 $inputPath=Join-Path $fixture.runtime 'source-discover.json';$inputValue=Get-Content -LiteralPath $inputPath -Raw|ConvertFrom-Json -Depth 100
 $parameters=@{ProjectRoot=$root;FrameworkRoot=$fixture.framework;TargetVersion='2.0.0';ExpectedProjectConfigIdentity=$inputValue.expectedProjectConfigIdentity;ExpectedCorrectionsIdentity=$inputValue.expectedCorrectionsIdentity;Profile='STANDARD';Role='TASK_OWNER';Phase='IMPLEMENT';Actor='publication-actor';TaskIdentity=$plan.taskIdentity;Capabilities=@($inputValue.capabilities);IntentEnvelope=$inputValue.intentEnvelope;Objective=(Get-AiwProcessSemanticText $inputValue.intentEnvelope);ActionKind='SOURCE_WRITE';ResultKind='IMPLEMENTATION_RESULT';ExactPaths=@($inputValue.exactPaths);ForbiddenPaths=@($inputValue.forbiddenPaths)}
 $documents=(& $pub {param($p,$r)Get-PubObjectDocuments $p $r @()} $plan $root).documents
 $reference=& $pub {param($p,$d,$r)[pscustomobject]@{old=(Get-PubClosure $p $d preimage $r @());target=(Get-PubClosure $p $d postimage $r @())}} $plan $documents $root
 $ordinary=& $composer.ExportedCommands['Invoke-ProcessRequirementComposition'] @parameters
 # Count reached factories while delegating every call to the real body.
 # No graph, bytes, permission result or source identity is mocked.
 & $content {
  $script:SelectedTestGraph=(Get-Item Function:New-CsOwnedGraph).ScriptBlock
  $script:SelectedTestIds=[Collections.Generic.List[string]]::new()
  Set-Item Function:script:New-CsOwnedGraph -Value {
   param($Owner,$Descriptor,[string]$AdoptionIdentity)
   $script:SelectedTestIds.Add([string]$Descriptor.rootSourceId)
   & $script:SelectedTestGraph $Owner $Descriptor $AdoptionIdentity
  }
 }
 function ReadSelectedGraphIds {return @(& $content {$script:SelectedTestIds.ToArray()})}
 function InvokeSelectedProbe([string]$Mode){
  & $pub {
   param($parameters,$content,$root,$package,$plan,$documents,$mode)
   Invoke-PubClosureObservationScope -Body {
    param($parameters,$content,$root,$package,$plan,$documents,$mode)
    $composition=Invoke-PubSelectedComposition $parameters
    $scope=$script:PublicationClosureObservations;$material=$scope['SELECTED_STANDARDS']
    if($null-eq$material-or$material.Rules.Count-ne2-or$material.Rules.ContainsKey('SECOND')){throw 'TEST_SELECTED_MATERIAL_REACHED_SET'}
    & $content {$script:SelectedTestIds.Clear()}
    $noop=[IO.Path]::Combine($root,'standards/noop.md');$saved=[IO.File]::ReadAllBytes($noop)
    $unlisted=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $unlisted.objects=@($unlisted.objects|Where-Object path -CNE 'standards/noop.md')
    $copies=@{};foreach($key in $documents.Keys){$copies[$key]=$documents[$key]}
    try{
     switch($mode){
      ROOT {$material.ProjectRoot=$root+'-different'}
      IMPLEMENTATION {$material.ImplementationIdentity='0|'+('0'*64)}
      FOREIGN {
       $null=Get-PubEligibilityCore $root $package @() @{SELECTED_STANDARDS=$material}
       return [pscustomobject]@{composition=$composition;scopeValid=$true}
      }
      NESTED {
       $caught=$false
       try{Invoke-PubClosureObservationScope -Body {param($p)$null=Invoke-PubSelectedComposition $p;throw 'TEST_NESTED_CAPTURE_FAILURE'} -Arguments @($parameters)}catch{if($_.Exception.Message-cne'TEST_NESTED_CAPTURE_FAILURE'){throw};$caught=$true}
       if(-not$caught-or-not[object]::ReferenceEquals($scope,$script:PublicationClosureObservations)-or-not[object]::ReferenceEquals($material,$scope['SELECTED_STANDARDS'])){throw 'TEST_NESTED_CAPTURE_LEAK'}
       & $content {$script:SelectedTestIds.Clear()}
       $null=Get-PubEligibilityCore $root $package @() $scope
       return [pscustomobject]@{composition=$composition;scopeValid=$true}
      }
      FAILURE {
       $bad=@{};foreach($key in $parameters.Keys){$bad[$key]=$parameters[$key]};$bad.ExpectedProjectConfigIdentity='0|'+('0'*64)
       $caught=$false;try{$null=Invoke-PubSelectedComposition $bad}catch{$caught=$true}
       if(-not$caught-or$scope.ContainsKey('SELECTED_STANDARDS')){throw 'TEST_FAILED_CAPTURE_SURVIVED'}
       & $content {$script:SelectedTestIds.Clear()}
       $null=Get-PubEligibilityCore $root $package @() $scope
       return [pscustomobject]@{composition=$composition;scopeValid=$true}
      }
      PRIVATE_INPUT {
       $bad=@{};foreach($key in $parameters.Keys){$bad[$key]=$parameters[$key]};$bad.PublicationMaterial=$material
       $null=Invoke-PubSelectedComposition $bad
       throw 'TEST_PRIVATE_INPUT_ACCEPTED'
      }
      RAW {[IO.File]::WriteAllText($noop,'A changed unlisted physical member.')}
      MISSING {[IO.File]::Delete($noop)}
      PROTECTED {return Get-PubClosureObservationCore $unlisted $copies preimage $root @($noop) $material}
      CANDIDATE {
       $bytes=[Text.UTF8Encoding]::new($false).GetBytes('Changed projected member without readoption.')
       $copies['standards/noop.md|preimage']=[pscustomobject]@{Bytes=$bytes;Identity=(Get-PubByteIdentity $bytes)}
       return Get-PubClosureObservationCore $plan $copies preimage $root @() $material
      }
      PERMISSION {
       $value=$copies['.ai-workspace/project.json|preimage'].Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
       $value.sourceBindings[0].allowedPaths=@([pscustomobject]@{kind='FILE';locator='standards/data.md'})
       $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Depth 100))
       $copies['.ai-workspace/project.json|preimage']=[pscustomobject]@{Bytes=$bytes;Identity=(Get-PubByteIdentity $bytes);Value=$value}
       return Get-PubClosureObservationCore $plan $copies preimage $root @() $material
      }
      UNSELECTED {
       $value=$copies['.ai-workspace/process-policy.json|preimage'].Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
       $rule=@($value.rules|Where-Object ruleId -CEQ SECOND)[0]
       $rule.source.documents[0].sectionStart='<!-- MISSING_SECOND -->'
       $rule.source.revision=Get-AiwContentRevision $rule.source $copies['.ai-workspace/project.json|preimage'].Value.sourceBindings
       $rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source
       $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Depth 100))
       $copies['.ai-workspace/process-policy.json|preimage']=[pscustomobject]@{Bytes=$bytes;Identity=(Get-PubByteIdentity $bytes);Value=$value}
       return Get-PubClosureObservationCore $plan $copies preimage $root @() $material
      }
     }
     if($mode-cin@('RAW','MISSING')){return Get-PubClosureObservationCore $unlisted $copies preimage $root @() $material}
     $pair=Get-PubClosurePair $plan $copies $root @() $material
     return [pscustomobject]@{composition=$composition;pair=$pair;scopeValid=$true}
    }finally{[IO.File]::WriteAllBytes($noop,$saved)}
   } -Arguments @($parameters,$content,$root,$package,$plan,$documents,$mode)
  } $parameters $content $root $Case.members.SOURCE.package $plan $documents $Mode
 }
 try{
  & $content {$script:SelectedTestIds.Clear()}
  $actual=FixtureBoundary $fixture $inputPath
  $ids=ReadSelectedGraphIds
  Check ($actual.code-eq0-and$actual.value.status-ceq'PASS') 'selected-material-actual-DISCOVER-completes'
  Check ((Get-AiwContentDescriptorIdentity @($actual.value.selectedRuleBlocks))-ceq(Get-AiwContentDescriptorIdentity @($ordinary.selectedRequirements))) 'selected-material-public-DISCOVER-bodies-match-independent-composition'
  $captured=InvokeSelectedProbe PAIR
  Check ((Get-AiwContentDescriptorIdentity $captured.pair)-ceq(Get-AiwContentDescriptorIdentity $reference)) 'selected-material-pair-matches-independent-full-closures'
  Check ((Get-AiwContentDescriptorIdentity $captured.composition)-ceq(Get-AiwContentDescriptorIdentity $ordinary)) 'selected-material-keeps-complete-public-composition-result-unchanged'
  foreach($mode in @('ROOT','IMPLEMENTATION','FOREIGN','FAILURE')){
   $observed=InvokeSelectedProbe $mode
   Check ($observed.scopeValid-and(ReadSelectedGraphIds).Count-eq6) ('selected-material-'+$mode+'-uses-complete-original-pair')
  }
  $nested=InvokeSelectedProbe NESTED
  Check ($nested.scopeValid-and(ReadSelectedGraphIds).Count-eq4) 'selected-material-nested-failure-restores-only-caller-owned-scope'
  foreach($row in @(@('RAW','CONTENT_IDENTITY_DRIFT'),@('MISSING','SOURCE_UNAVAILABLE'),@('PROTECTED','FORBIDDEN_PATH'),@('CANDIDATE','CONTENT_IDENTITY_DRIFT'),@('PERMISSION','OUTSIDE_ALLOWED_PATHS'),@('UNSELECTED','SECTION|MARKER'),@('PRIVATE_INPUT','SOURCE_PUBLICATION_PRIVATE_COMPOSITION_INPUT'))){
   if($row[0]-ceq'MISSING'){
    $missingError=$null
    try{InvokeSelectedProbe MISSING|Out-Null}catch{$missingError=$_}
    $missingPath=[IO.Path]::Combine($root,'standards/noop.md').Replace('\','/')
    $isMissing=$null-ne$missingError-and($missingError.Exception.Message-match'^SOURCE_UNAVAILABLE(?:\||$)'-or($missingError.CategoryInfo.Category-eq[Management.Automation.ErrorCategory]::ObjectNotFound-and([string]$missingError.TargetObject).Replace('\','/')-ieq$missingPath))
    Check $isMissing ('selected-material-MISSING-cannot-bypass-original-reader|'+$missingError)
   }else{
    Reject {InvokeSelectedProbe $row[0]} $row[1] ('selected-material-'+$row[0]+'-cannot-bypass-original-reader')
   }
   if($row[0]-ceq'UNSELECTED'){Check ((ReadSelectedGraphIds)-contains'SECOND') 'selected-material-unselected-rule-reaches-real-graph-before-section-rejection'}
   Check (& $pub {$null-eq$script:PublicationClosureObservations}) ('selected-material-'+$row[0]+'-failure-releases-boundary-scope')
  }
  $injected=$null
  Reject {& $composer.ExportedCommands['Invoke-ProcessRequirementComposition'] @parameters -PublicationMaterial ([ref]$injected)} 'PublicationMaterial' 'selected-material-public-composition-rejects-private-capture-parameter'
  & $content {$script:SelectedTestIds.Clear()}
  $null=& $pub.ExportedCommands['Get-AiwProjectSourcePublicationEligibility'] $root $Case.members.SOURCE.package
  Check ((ReadSelectedGraphIds).Count-eq6-and(& $pub {$null-eq$script:PublicationClosureObservations})) 'selected-material-next-public-eligibility-has-no-previous-capture'
  # Exercise normative raw drift with an independently constructed identity.
  # Change only the owned fixture and restore its exact original carriers.
  $noop=AssertFixturePath (Join-Path $root 'standards/noop.md');$policyPath=AssertFixturePath $fixture.policyPath
  $noopBytes=[IO.File]::ReadAllBytes($noop);$policyBytes=[IO.File]::ReadAllBytes($policyPath)
  try{
   $config=Get-Content -LiteralPath $fixture.configPath -Raw|ConvertFrom-Json -Depth 100
   $policy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
   $body='Keep the complete normative obligation.'
   SaveText $noop ("<NOOP>`n"+$body+"`n</NOOP>`nOutside the unit.`n")
   $doc=[pscustomobject]@{sourceId='NOOP';bindingId='professional';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator='standards/noop.md';mode='NORMATIVE_UNIT';unitId='NOOP';sectionStart='<NOOP>';sectionEnd='</NOOP>';normativeIdentity='';commonConditionSourceIds=@();dependencies=@()}
   $unit=[ordered]@{provider='LOCAL_DIRECTORY';physicalSource=$noop.ToUpperInvariant();permissionIdentity=(Get-AiwContentDescriptorIdentity $config.sourceBindings[0]);mode='NORMATIVE_UNIT';unitId='NOOP';parserVersion='UTF8_LF_COMPLETE_UNIT_V1';sectionStart='<NOOP>';sectionEnd='</NOOP>';bodyIdentity=(Get-AiwContentByteIdentity $utf8.GetBytes($body))}
   $doc.normativeIdentity=Get-AiwContentDescriptorIdentity ([ordered]@{unit=$unit;commonConditions=@();dependencies=@()})
   $doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $config.sourceBindings
   $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='professional';itemId='NOOP';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='NOOP';documents=@($doc)}
   $descriptor.revision=Get-AiwContentRevision $descriptor $config.sourceBindings;$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
   @($policy.rules|Where-Object ruleId -CEQ NOOP)[0].source=$descriptor
   SaveFixturePolicy $policyPath $policy $fixture.version
   $normative=& $pub {
    param($parameters,$content,$root,$noop,$policy,$body)
    Invoke-PubClosureObservationScope -Body {
     param($parameters,$content,$root,$noop,$policy,$body)
     $null=Invoke-PubSelectedComposition $parameters;$material=$script:PublicationClosureObservations['SELECTED_STANDARDS']
     $oldRaw=$material.Rules['NOOP'].Documents[0].identity
     [IO.File]::AppendAllText($noop,'Only unrelated text changed.',[Text.UTF8Encoding]::new($false))
     & $content {$script:SelectedTestIds.Clear()}
     $composer=(Get-Command Get-AiwProjectPolicySourceClosure).Module
     $fresh=& $composer {param($r,$rules,$m)Get-AiwProjectPolicySourceClosureCore -ProjectRoot $r -Rules $rules -PreviousMaterial $m} $root $policy.rules $material
     $ids=@(& $content {$script:SelectedTestIds.ToArray()})
     $newRaw=@($fresh.Closure.Documents|Where-Object sourcePath -CEQ $noop)[0].identity
     [IO.File]::WriteAllText($noop,([IO.File]::ReadAllText($noop).Replace($body,'Changed normative obligation.')),[Text.UTF8Encoding]::new($false))
     $errorText='';try{$null=& $composer {param($r,$rules,$m)Get-AiwProjectPolicySourceClosureCore -ProjectRoot $r -Rules $rules -PreviousMaterial $m} $root $policy.rules $material}catch{$errorText=$_.Exception.Message}
     [pscustomobject]@{oldRaw=$oldRaw;newRaw=$newRaw;graphs=$ids;bodyError=$errorText}
    } -Arguments @($parameters,$content,$root,$noop,$policy,$body)
   } $parameters $content $root $noop $policy $body
   Check ($normative.oldRaw-cne$normative.newRaw-and$normative.graphs.Count-eq2-and$normative.graphs-contains'NOOP'-and$normative.graphs-contains'SECOND') 'selected-material-unrelated-normative-raw-change-rebuilds-real-graph-and-keeps-valid-body'
   Check ($normative.bodyError-match'CONTENT_IDENTITY_DRIFT\|NORMATIVE_UNIT') 'selected-material-normative-body-change-still-rejects'
  }finally{[IO.File]::WriteAllBytes($noop,$noopBytes);[IO.File]::WriteAllBytes($policyPath,$policyBytes)}
  # Real remote transport/fallback coverage remains in the existing remote
  # suite. The unchanged content owner never borrows a remote rule's material.
  # Ordinary's two original FINALIZE and partial recovery continue below after
  # all observation hooks are removed.
 }finally{
  & $content {Set-Item Function:script:New-CsOwnedGraph -Value $script:SelectedTestGraph;Remove-Variable SelectedTestGraph,SelectedTestIds -Scope Script}
 }
}

function TestPublicationTargetStandards {
 # Own real fixture: ordinary's original source/target selections coincide.
 # The original rule is selected identically by both receipts; only the
 # planned target policy makes it CONTROL-only. Independent target results
 # then give a valid distinct-selection oracle after the original gates.
 $fixture=NewFixture 'target-standards-pair';$root=$fixture.root
 $file=AssertFixturePath (Join-Path $root 'standards/target-only.md')
 SaveText $file ("# Target member convention"+[char]10+"Preserve this complete adopted file."+[char]10)
 $config=Get-Content -LiteralPath $fixture.configPath -Raw|ConvertFrom-Json -Depth 100
 $policy=Get-Content -LiteralPath $fixture.policyPath -Raw|ConvertFrom-Json -Depth 100
 $rule=CopyValue @($policy.rules|Where-Object ruleId -CEQ NOOP)[0]
 $rule.ruleId='TARGET_SIDE_ONLY'
 $rule.source.itemId='TARGET_SIDE_ONLY';$rule.source.rootSourceId='TARGET_SIDE_ONLY'
 $rule.source.documents[0].sourceId='TARGET_SIDE_ONLY';$rule.source.documents[0].locator='standards/target-only.md'
 $rule.source.documents[0].identity=Identity $file;$rule.source.documents[0].revision.value=Identity $file
 $rule.source.revision=Get-AiwContentRevision $rule.source $config.sourceBindings
 $rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source
 $policy.rules+=,$rule;SaveFixturePolicy $fixture.policyPath $policy $fixture.version
 $fixture|Add-Member targetStandardsPair $true
 $case=PreparePublication $fixture;$pub=$case.pub
 $composer=@(Import-Module (Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
 $facts=& $pub.ExportedCommands['Get-AiwProjectSourcePublicationMembers'] $case.members.CONTROL.receiptRef $case.members.SOURCE.receiptRef $case.planRef
 $path=Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1'
 $buildLine=@(Select-String -LiteralPath $path -Pattern '^function Get-AiwProjectStandardsSnapshot \{')
 Check ($buildLine.Count-eq1) 'target-standards-real-complete-construction-observation'
 if($null-ne(Get-Variable AiwTargetPairProbe -Scope Global -ErrorAction SilentlyContinue)){throw 'TEST_TARGET_PAIR_PROBE_BUSY'}
 $global:AiwTargetPairProbe=@{fullBuilds=0};$buildBreakpoint=$null;$original=[IO.File]::ReadAllBytes($file)
 function ReadTargetPair {& $composer {param($f)Get-AiwPublicationTargets $f} $facts}
 function CheckTargetPair($Actual,$Expected,[string]$Label){
  foreach($member in @('SOURCE','CONTROL')){
   Check ((Get-AiwContentDescriptorIdentity $Actual.$member.binding)-ceq(Get-AiwContentDescriptorIdentity $Expected.$member.binding)) ($Label+'-'+$member+'-binding-matches-independent-target')
   Check ((Get-AiwContentDescriptorIdentity @($Actual.$member.composition.selectedRequirements))-ceq(Get-AiwContentDescriptorIdentity @($Expected.$member.composition.selectedRequirements))) ($Label+'-'+$member+'-own-complete-selected-bodies-and-metadata')
   # Preserve observation order/identities without labelling shared bodies as
   # fresh physical reads by the second consumer.
   $actualReads=@($Actual.$member.composition.readTrace|Where-Object{$_.event-cin@('SOURCE_BODY_READ','SOURCE_BODY_SHARED')}|Select-Object ruleId,sourceId,path,identity,observation,authority)
   $expectedReads=@($Expected.$member.composition.readTrace|Where-Object event -CEQ SOURCE_BODY_READ|Select-Object ruleId,sourceId,path,identity,observation,authority)
   Check ($actualReads.Count-gt0-and(Get-AiwContentDescriptorIdentity $actualReads)-ceq(Get-AiwContentDescriptorIdentity $expectedReads)) ($Label+'-'+$member+'-source-observations-preserve-order-and-identities')
  }
 }
 try{
  $buildBreakpoint=Set-PSBreakpoint -Script $path -Line ($buildLine[0].LineNumber+2) -Action {$global:AiwTargetPairProbe.fullBuilds++}
  $independent=& $composer {
   param($f)
   $documents=$f.CONTROL.eligibility.documents;$projected=@(Get-AiwPublicationProjectedObjects $f);$targets=@{}
   foreach($member in @('SOURCE','CONTROL')){
    Assert-AiwSourceChangeStaticContext $f.$member.receipt
    $targets[$member]=Get-AiwSourceChangeTarget $f.$member.receipt $documents['.ai-workspace/project.json|postimage'] $documents['.ai-workspace/process-policy.json|postimage'] $projected
   }
   return $targets
  } $facts
  $sourceIds=@($independent.SOURCE.composition.selectedRequirements.requirementId|ForEach-Object{($_-split':')[-1]})
  $controlIds=@($independent.CONTROL.composition.selectedRequirements.requirementId|ForEach-Object{($_-split':')[-1]})
  Check ($independent.SOURCE.binding.selectedRulesIdentity-cne$independent.CONTROL.binding.selectedRulesIdentity-and'TARGET_SIDE_ONLY'-cnotin$sourceIds-and'TARGET_SIDE_ONLY'-cin$controlIds) 'target-standards-oracle-requires-distinct-member-selections'
  $global:AiwTargetPairProbe.fullBuilds=0;$shared=ReadTargetPair
  Check ($global:AiwTargetPairProbe.fullBuilds-eq1) 'target-standards-pair-constructs-complete-set-once'
  CheckTargetPair $shared $independent 'target-standards-shared'
  Check (@($shared.CONTROL.composition.readTrace|Where-Object event -CEQ SOURCE_BODY_SHARED).Count-gt0) 'target-standards-second-selection-consumes-shared-observations'
  try{
   [IO.File]::AppendAllText($file,([char]10+'Changed between public calls.'),[Text.UTF8Encoding]::new($false))
   Reject {ReadTargetPair} 'CONTENT_IDENTITY_DRIFT|SOURCE_CHANGE_TARGET_SOURCE_DRIFT' 'target-standards-next-public-pair-reobserves-changed-source'
  }finally{[IO.File]::WriteAllBytes($file,$original)}
  $next=ReadTargetPair
  CheckTargetPair $next $independent 'target-standards-restored'
 }finally{
  if($null-ne$buildBreakpoint){Remove-PSBreakpoint -Breakpoint $buildBreakpoint}
  [IO.File]::WriteAllBytes($file,$original)
  Remove-Variable AiwTargetPairProbe -Scope Global
 }
}

function TestPublicationJointBoundary {
 foreach($layout in @('Ordinary','Maintenance')){
  if($PublicationLayout-cne'All'-and$PublicationLayout-cne$layout){continue}
  $name='joint-'+$layout.ToLowerInvariant()
  $fixture=NewFixture $name -Maintenance:($layout-ceq'Maintenance') -BarrierNode SECOND_FINALIZE
  # The target changes one real rule from both members to CONTROL-only.
  # This distinguishes each member's actual compiler result and obligations.
  $file=Join-Path $fixture.root 'standards/target-only.md';SaveText $file "# Target member convention`nPreserve this complete adopted file.`n"
  $config=Get-Content -LiteralPath $fixture.configPath -Raw|ConvertFrom-Json -Depth 100
  $policy=Get-Content -LiteralPath $fixture.policyPath -Raw|ConvertFrom-Json -Depth 100
  $rule=CopyValue @($policy.rules|Where-Object ruleId -CEQ NOOP)[0]
  $rule.ruleId='TARGET_SIDE_ONLY';$rule.source.itemId='TARGET_SIDE_ONLY';$rule.source.rootSourceId='TARGET_SIDE_ONLY'
  $rule.source.documents[0].sourceId='TARGET_SIDE_ONLY';$rule.source.documents[0].locator='standards/target-only.md'
  $rule.source.documents[0].identity=Identity $file;$rule.source.documents[0].revision.value=Identity $file
  $rule.source.revision=Get-AiwContentRevision $rule.source $config.sourceBindings;$rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source
  $policy.rules+=,$rule;SaveFixturePolicy $fixture.policyPath $policy $fixture.version
  $fixture|Add-Member targetStandardsPair $true
  $fixture|Add-Member jointTargetObligations $true
  $case=PreparePublication $fixture;$pub=$case.pub
  $boundary=@(Import-Module (Join-Path $fixture.version 'scripts/ProcessRequirementBoundary.psm1') -PassThru)[0]
  $composer=@(Import-Module (Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
  $control=$case.recovery.members[1].admitInputRef.path;$source=$case.recovery.members[0].admitInputRef.path
  function ReadJoint([string]$Peer=$source,[string]$PeerIdentity=''){
   if(-not$PeerIdentity){$PeerIdentity=Identity $Peer}
   $response=& $boundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $control -PublicationSourceInputPath $Peer -ExpectedPublicationSourceInputIdentity $PeerIdentity -AsJson
   $raw=[string]::Join("`n",@($response.output));$value=$raw|ConvertFrom-Json -Depth 100
   return [pscustomobject]@{code=$response.exitCode;value=$value;raw=$raw}
  }
  # Real legacy single inputs are the independent same-input result oracle.
  $legacy=@{}
  foreach($member in @('SOURCE','CONTROL')){
   $path=$case.recovery.members[[Array]::IndexOf(@('SOURCE','CONTROL'),$member)].admitInputRef.path
   $legacy[$member]=FixtureBoundary $fixture $path
   Check ($legacy[$member].code-eq0-and$legacy[$member].value.status-ceq'PASS') ($name+'-legacy-'+$member+'-still-supported')
  }
  $probe=[pscustomobject]@{members=0;targets=0;mode='NONE';rawPath=$file;taskPath=$fixture.taskPath;controlPath=$control}
  $rawBytes=[IO.File]::ReadAllBytes($file);$taskBytes=[IO.File]::ReadAllBytes($fixture.taskPath);$inputBytes=[IO.File]::ReadAllBytes($control)
  $originalMembers=& $pub {(Get-Command Get-AiwProjectSourcePublicationMembers -CommandType Function).ScriptBlock}
  $originalTargets=& $composer {(Get-Command Get-AiwPublicationTargets -CommandType Function).ScriptBlock}
  try{
   & $pub {
    param($p,$original)
    $script:JointBoundaryProbe=$p;$script:JointBoundaryMembers=$original
    Set-Item Function:script:Get-AiwProjectSourcePublicationMembers -Value {
     param($ControlReceiptRef,$SourceReceiptRef,$PlanRef)
     $p=$script:JointBoundaryProbe;$p.members++
     if($p.members-eq2-and$p.mode-ceq'RAW'){[IO.File]::WriteAllText($p.rawPath,'Current source bytes changed between members.')}
     $facts=& $script:JointBoundaryMembers $ControlReceiptRef $SourceReceiptRef $PlanRef
     if($p.members-eq2-and$p.mode-ceq'TASK'){[IO.File]::WriteAllText($p.taskPath,'Current task changed after the second fresh membership check.')}
     if($p.members-eq2-and$p.mode-ceq'INPUT'){[IO.File]::AppendAllText($p.controlPath,"`n ")}
     return $facts
    }
   } $probe $originalMembers
   & $composer {
    param($p,$original)
    $script:JointBoundaryProbe=$p;$script:JointBoundaryTargets=$original
    Set-Item Function:script:Get-AiwPublicationTargets -Value {param($Facts)$script:JointBoundaryProbe.targets++;& $script:JointBoundaryTargets $Facts}
   } $probe $originalTargets
   $joint=ReadJoint
   Check ($joint.code-eq0-and$joint.value.status-ceq'PASS'-and$probe.targets-eq1-and$probe.members-eq2) ($name+'-joint-real-target-once-current-complete-members-twice')
   foreach($entry in $joint.value.members){
    $actual=[string]::Join("`n",@($entry.response.output))|ConvertFrom-Json -Depth 100
    foreach($field in @('status','mode','selectionIdentity','decisionIdentity','projectSourcePreparation')){
     Check ((Get-AiwContentDescriptorIdentity $actual.$field)-ceq(Get-AiwContentDescriptorIdentity $legacy[$entry.member].value.$field)) ($name+'-'+$entry.member+'-'+$field+'-matches-real-single-boundary')
    }
   }
   Check ($legacy.SOURCE.value.projectSourcePreparation.targetIdentity-cne$legacy.CONTROL.value.projectSourcePreparation.targetIdentity) ($name+'-distinct-target-selection-is-preserved')
   foreach($mode in @('RAW','TASK','INPUT')){
    $probe.members=0;$probe.targets=0;$probe.mode=$mode
    try{
     $failed=ReadJoint
     $expectedReached=if($mode-ceq'RAW'){1}else{2}
     $reachedFailure=($mode-ceq'RAW')-or($failed.value.members.Count-eq2-and$failed.value.members[1].response.exitCode-ne0)
     Check ($failed.code-ne0-and$failed.value.status-ceq'FAIL'-and$failed.value.failedMember-ceq'CONTROL'-and$failed.value.members.Count-eq$expectedReached-and$reachedFailure-and$failed.value.members[0].member-ceq'SOURCE'-and$failed.value.members[0].response.exitCode-eq0) ($name+'-late-'+$mode+'-rejects-before-fabricating-control-success')
    }finally{[IO.File]::WriteAllBytes($file,$rawBytes);[IO.File]::WriteAllBytes($fixture.taskPath,$taskBytes);[IO.File]::WriteAllBytes($control,$inputBytes);$probe.mode='NONE'}
   }
   $probe.members=0;$probe.targets=0
   $fresh=ReadJoint
   Check ($fresh.code-eq0-and$probe.targets-eq1-and$probe.members-eq2) ($name+'-failed-call-does-not-leak-trusted-context')
  }finally{
   & $pub {param($original)Set-Item Function:script:Get-AiwProjectSourcePublicationMembers -Value $original;Remove-Variable JointBoundaryProbe,JointBoundaryMembers -Scope Script} $originalMembers
   & $composer {param($original)Set-Item Function:script:Get-AiwPublicationTargets -Value $original;Remove-Variable JointBoundaryProbe,JointBoundaryTargets -Scope Script} $originalTargets
  }
  $badIdentity=ReadJoint $source '1|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  Check ($badIdentity.code-ne0-and$badIdentity.value.status-ceq'FAIL') ($name+'-exact-peer-raw-identity-required')
  $swapped=ReadJoint $control
  Check ($swapped.code-ne0-and$swapped.value.status-ceq'FAIL') ($name+'-control-grant-cannot-substitute-source-grant')
  $bad=Get-Content -LiteralPath $source -Raw|ConvertFrom-Json -Depth 100
  $bad.preparationReceipts=@($bad.preparationReceipts|Where-Object{$_-cnotlike'PROJECT_SOURCE_CHANGE|*'})
  $badPath=Join-Path $fixture.runtime 'joint-no-candidate.json';SaveJson $badPath $bad
  $mismatch=ReadJoint $badPath
  Check ($mismatch.code-ne0-and$mismatch.value.reason-ceq'SOURCE_PUBLICATION_PAIR_CANDIDATE_MISMATCH') ($name+'-both-original-inputs-must-bind-common-candidate')
  $own=Get-Content -LiteralPath $control -Raw|ConvertFrom-Json -Depth 100
  Check ('JOINT_CONTROL_ONLY_PREPARATION'-cin@($own.preparationReceipts)) ($name+'-new-control-only-preparation-is-actually-declared')
  $own.preparationReceipts=@($own.preparationReceipts|Where-Object{$_-cne'JOINT_CONTROL_ONLY_PREPARATION'})
  $ownPath=Join-Path $fixture.runtime 'joint-missing-control-preparation.json';SaveJson $ownPath $own
  $originalControl=$control
  try{
   $control=$ownPath;$missing=ReadJoint
   Check ($missing.code-ne0-and$missing.value.failedMember-ceq'CONTROL'-and$missing.value.members.Count-eq2-and$missing.value.members[0].response.exitCode-eq0-and$missing.value.members[1].response.exitCode-ne0) ($name+'-source-obligations-cannot-substitute-control-new-preparation')
  }finally{$control=$originalControl}
  $grantPath=$case.members.SOURCE.packagePath;$grantBytes=[IO.File]::ReadAllBytes($grantPath)
  try{
   $grant=CopyValue $case.members.SOURCE.package;$grant.grantee='different-current-actor';SaveJson $grantPath $grant
   $revoked=ReadJoint
   Check ($revoked.code-ne0-and$revoked.value.status-ceq'FAIL') ($name+'-other-member-right-does-not-cover-source-permission-drift')
  }finally{[IO.File]::WriteAllBytes($grantPath,$grantBytes)}
  $controlIdentity=Identity $control
  $half=& $boundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $control -PublicationSourceInputPath $source -AsJson
  Check ($half.exitCode-ne0-and(Identity $control)-ceq$controlIdentity) ($name+'-half-peer-reference-fails-without-input-change')
  $cleanup=& $boundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $control -PublicationSourceInputPath $source -ExpectedPublicationSourceInputIdentity (Identity $source) -AsJson -DeleteInputOnExit
  Check ($cleanup.exitCode-ne0-and[IO.File]::Exists($source)-and[IO.File]::Exists($control)) ($name+'-joint-cleanup-options-do-not-delete-originals')
  if($layout-ceq'Maintenance'){
   $entry=Join-Path $fixture.framework 'scripts/resolve-framework-maintenance-process-requirements.ps1'
   $mixed=@(& $entry -InputPath $control -PublicationSourceInputPath $source -ExpectedPublicationSourceInputIdentity (Identity $source) -AsJson -AdoptionProcessBoundary);$mixedCode=$LASTEXITCODE
   $mixedValue=[string]::Join("`n",$mixed)|ConvertFrom-Json -Depth 100
   Check ($mixedCode-ne0-and$mixedValue.reason-ceq'SOURCE_PUBLICATION_PAIR_OPTIONS') ($name+'-joint-front-cannot-bypass-through-special-adoption-route')
  }
  $finalControl=$case.recovery.members[1].finalizeInputRef.path;$finalSource=$case.recovery.members[0].finalizeInputRef.path
  $publicFinal=& $boundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $finalControl -PublicationSourceInputPath $finalSource -ExpectedPublicationSourceInputIdentity (Identity $finalSource) -AsJson
  $publicFinalValue=[string]::Join("`n",@($publicFinal.output))|ConvertFrom-Json -Depth 100
  Check ($publicFinal.exitCode-ne0-and$publicFinalValue.reason-ceq'SOURCE_PUBLICATION_FINALIZE_ROOT_REQUIRED') ($name+'-public-pair-finalize-cannot-drop-durable-result-observer')
  foreach($private in @('PublicationContext','PreparedTargets','OnMemberResult','MemberResultState')){Check (-not$boundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'].Parameters.ContainsKey($private)) ($name+'-public-entry-has-no-trusted-'+$private)}
  Check (-not$composer.ExportedCommands['Get-AiwProjectSourceChange'].Parameters.ContainsKey('PublicationContext')-and-not$composer.ExportedCommands['Get-AiwProjectSourcePublicationCandidate'].Parameters.ContainsKey('TargetsCapture')) ($name+'-public-composition-cannot-supply-or-capture-trusted-targets')
  # Original interruption, immediate SOURCE result, CONTROL failure, retry,
  # completed-result reuse and no-op preservation all use the real root caller.
  TestOriginalPublicationRecovery $case $name
 }
}

function TestPublicationRecoveryContextReuse {
 $fixture=NewFixture 'recovery-context' -BarrierNode SECOND_FINALIZE
 $case=PreparePublication $fixture;$pub=$case.pub
 $probe=[pscustomobject]@{members=0;targets=0;mutation='NONE';root=$fixture.root;path=(Join-Path $fixture.root 'standards/noop.md');directory=(Join-Path $fixture.root 'standards');backup=(Join-Path $fixture.root 'recovery-standards-original')}
 $bytes=[IO.File]::ReadAllBytes($probe.path)
 $members=& $pub {(Get-Command Get-AiwProjectSourcePublicationMembers -CommandType Function).ScriptBlock}
 $breakpoints=@();$global:AiwRecoveryContextProbe=$probe
 try{
  # File entry breakpoints observe actual calls across imported module instances;
  # replacing one module-local function does not count the other real instances.
  foreach($entry in @(@{path=(Join-Path $fixture.version 'scripts/ProjectSourcePublication.psm1');name='Get-AiwProjectSourcePublicationMembers';counter='members'},@{path=(Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1');name='Get-AiwPublicationTargets';counter='targets'})){
   $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($entry.path,[ref]$tokens,[ref]$errors)
   $function=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]},$true)|Where-Object Name -CEQ $entry.name)
   if($errors.Count-or$function.Count-ne1){throw 'TEST_RECOVERY_COUNT_ANCHOR'}
   $breakpoints+=Set-PSBreakpoint -Script $entry.path -Line $function[0].Body.EndBlock.Statements[0].Extent.StartLineNumber -Action ([scriptblock]::Create('$global:AiwRecoveryContextProbe.'+$entry.counter+'++'))
  }
  & $pub {
   param($p,$original)
   $script:RecoveryContextProbe=$p;$script:RecoveryContextMembers=$original
   Set-Item Function:script:Get-AiwProjectSourcePublicationMembers -Value {
    param($ControlReceiptRef,$SourceReceiptRef,$PlanRef)
    $facts=& $script:RecoveryContextMembers $ControlReceiptRef $SourceReceiptRef $PlanRef
    if($script:RecoveryContextProbe.mutation-ceq'RAW'){[IO.File]::WriteAllText($script:RecoveryContextProbe.path,'Late unchanged-member drift after actual current membership.')}
    if($script:RecoveryContextProbe.mutation-ceq'ANCESTOR'){
     foreach($path in @($script:RecoveryContextProbe.directory,$script:RecoveryContextProbe.backup)){if(-not[IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($script:RecoveryContextProbe.root)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_RECOVERY_MOVE_SCOPE'}}
     [IO.Directory]::Move($script:RecoveryContextProbe.directory,$script:RecoveryContextProbe.backup)
     $null=New-Item -ItemType Junction -Path $script:RecoveryContextProbe.directory -Target $script:RecoveryContextProbe.backup
    }
    return $facts
   }
  } $probe $members
  $observations=@()
  foreach($mode in @('REFERENCE','CURRENT','FRESH_CURRENT')){
   $startMembers=$probe.members;$startTargets=$probe.targets;$clock=[Diagnostics.Stopwatch]::StartNew()
   # Use the existing module-owned scope body, as the actual Root consumer does.
   # A raw external handle alone does not establish cross-module caller context.
   $proof=& $pub.ExportedCommands['Invoke-AiwProjectSourceScope'] -ProjectRoot $fixture.root -Mode PUBLICATION -Body {
    param($pub,$root,$recovery,$mode)
    & $pub {
     param($root,$recovery,$mode)
     $scope=Get-PubStackScope $root
     if($null-eq$scope){throw 'TEST_RECOVERY_STRUCTURED_SCOPE_MISSING'}
     if($mode-cne'REFERENCE'){return Set-AiwProjectSourcePublicationContext $scope $recovery}
     $lease=Get-PubLeaseFacts $scope;$original=Get-PubRecoveryOriginalFacts $root $recovery
     $proof=$original.proof;$previous=$lease.Recovery;$lease.Recovery=$proof
     try{
      $facts=Get-AiwProjectSourcePublicationMembers $recovery.members[1].discoverReceiptRef $recovery.members[0].discoverReceiptRef $recovery.planRef
      $null=Get-AiwProjectSourcePublicationCandidate $original.receipts.SOURCE $original.admissions.SOURCE.input $recovery.candidateRef RECOVERY
      $proof|Add-Member facts $facts;return $proof
     }catch{$lease.Recovery=$previous;throw}
    } $root $recovery $mode
   } -ArgumentList @($pub,$fixture.root,$case.recovery,$mode)
   $clock.Stop()
   $observation=[pscustomobject]@{mode=$mode;wallSeconds=$clock.Elapsed.TotalSeconds;members=($probe.members-$startMembers);targetPairs=($probe.targets-$startTargets)}
   $observations+=,$observation
   Write-Host ('RECOVERY_CONTEXT_COUNTS|'+($observation|ConvertTo-Json -Compress))
   Check ($observation.members-eq$(if($mode-ceq'REFERENCE'){2}else{1})-and$observation.targetPairs-eq1) ('recovery-context-'+$mode+'-actual-members-and-complete-target-count')
   Check ($proof.planRef.identity-ceq$case.planRef.identity-and$proof.candidateRef.identity-ceq$case.recovery.candidateRef.identity-and$null-ne$proof.facts.SOURCE-and$null-ne$proof.facts.CONTROL) ('recovery-context-'+$mode+'-retains-original-pair')
   if($mode-cne'REFERENCE'){Check ($proof.targets.ContainsKey('SOURCE')-and$proof.targets.ContainsKey('CONTROL')) ('recovery-context-'+$mode+'-retains-real-complete-targets')}
  }
  foreach($mutation in @('EARLY_RAW','RAW','ANCESTOR')){
   $probe.mutation=if($mutation-ceq'EARLY_RAW'){'NONE'}else{$mutation}
   if($mutation-ceq'EARLY_RAW'){SaveText $probe.path 'A new request must reobserve original source bytes.'}
   try{
    $observed=& $pub.ExportedCommands['Invoke-AiwProjectSourceScope'] -ProjectRoot $fixture.root -Mode PUBLICATION -Body {
     param($pub,$root,$recovery)
     & $pub {
      param($root,$recovery)
      $scope=Get-PubStackScope $root;$errorText=''
      try{$null=Set-AiwProjectSourcePublicationContext $scope $recovery}catch{$errorText=$_.Exception.Message}
      return [pscustomobject]@{error=$errorText;cleared=($null-eq(Get-AiwProjectSourcePublicationContext $root))}
     } $root $recovery
    } -ArgumentList @($pub,$fixture.root,$case.recovery)
    # A changed formal no-op member may be rejected by the earlier complete
    # object reachability guard; late ancestor checks still reject reparse paths.
    Check ($observed.error-match'CONTENT_IDENTITY_DRIFT|SOURCE_CLOSURE_DRIFT|SOURCE_PUBLICATION_REF_DRIFT|SOURCE_PUBLICATION_THIRD_PARTY_OBJECT|REPARSE') ('recovery-context-'+$mutation+'-actual-current-check-rejects|'+$observed.error)
    Check $observed.cleared ('recovery-context-'+$mutation+'-failed-proof-is-released')
   }finally{
    if([IO.Directory]::Exists($probe.backup)){
     foreach($path in @($probe.directory,$probe.backup)){if(-not[IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($fixture.root)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_RECOVERY_RESTORE_SCOPE'}}
     if(Test-Path -LiteralPath $probe.directory){[IO.Directory]::Delete($probe.directory)}
     [IO.Directory]::Move($probe.backup,$probe.directory)
    }
    [IO.File]::WriteAllBytes($probe.path,$bytes);$probe.mutation='NONE'
   }
  }
  $composer=@(Import-Module (Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
  Check (-not$composer.ExportedCommands['Get-AiwProjectSourcePublicationCandidate'].Parameters.ContainsKey('VerifiedFacts')-and-not$pub.ExportedCommands['Set-AiwProjectSourcePublicationContext'].Parameters.ContainsKey('VerifiedFacts')) 'recovery-context-public-input-cannot-supply-trusted-members'
  $measurement=Assert-AiwTestPath (Join-Path $phaseDirectory ('recovery-context-'+$script:publicationPhaseRunId+'.json'))
  SaveJson $measurement @{observations=$observations;scope='Same isolated small fixture; actual original admissions, module-owned native handles and real compilers. File-entry counts cover module instances. Local instrumented correctness observation, no normal performance inference or extrapolation to Media batch.';profileHotPath=[bool]$ProfileHotPath;hostBackground='UNKNOWN'}
  Write-Output ('RECOVERY_CONTEXT_MEASUREMENT|'+$measurement)
 }finally{
  & $pub {param($original)Set-Item Function:script:Get-AiwProjectSourcePublicationMembers -Value $original;Remove-Variable RecoveryContextProbe,RecoveryContextMembers -Scope Script} $members
  if($breakpoints.Count){$breakpoints|Remove-PSBreakpoint}
  Remove-Variable AiwRecoveryContextProbe -Scope Global
 }
 if($Group-ceq'RecoveryContext'){TestOriginalPublicationRecovery $case 'recovery-context'}
}




function TestOrdinaryPublication([string]$Name,[switch]$Maintenance,[switch]$EmptyPolicy,[switch]$Singleton){
 if(-not$Maintenance-and-not$EmptyPolicy-and-not$Singleton){TestPublicationTargetStandards}
 $fixture=NewFixture $Name -Maintenance:$Maintenance -EmptyPolicy:$EmptyPolicy -Singleton:$Singleton -BarrierNode SECOND_FINALIZE
 $case=PreparePublication $fixture;$pub=$case.pub
 if(-not$Maintenance-and-not$EmptyPolicy-and-not$Singleton){TestPublicationClosurePair $case;TestPublicationSelectedMaterial $case}
 TestPublicationBoundaries $case
 Check (@($case.members.CONTROL.package.exactPaths).Count-eq$(if($EmptyPolicy){2}else{1})-and'.ai-workspace/project.json'-cnotin@($case.members.CONTROL.package.exactPaths|Where-Object{-not$EmptyPolicy})) ($Name+'-only-changed-carriers-are-write-objects')
 TestOriginalPublicationRecovery $case $Name
}

function TestOriginalPublicationRecovery($Case,[string]$Name){
 $fixture=$Case.fixture;$pub=$Case.pub
 $journal=Join-Path $fixture.root '.ai-workspace/upgrade-recovery/project-rules/source-publication/state.json'
 $before=@{'standards/noop.md'=(Identity (Join-Path $fixture.root 'standards/noop.md'))};foreach($o in $case.plan.objects){$before[$o.path]=Identity (Join-Path $fixture.root $o.path)}
 Reject {InvokePublication $case COMPLETE 1} 'SOURCE_PUBLICATION_INJECTED_INTERRUPTION' ($Name+'-ordered-prefix-interruption-retains-originals')
 $state=& $pub.ExportedCommands['Get-AiwProjectSourcePublicationReachability'] $fixture.root $case.plan
 Check ($state.prefix-eq1-and-not(Test-Path -LiteralPath $journal)) ($Name+'-actual-prefix-is-recoverable-without-journal')
 # One real original FINALIZE succeeds; a fault in the second real boundary
 # leaves allNew and the first result intact, without a false batch COMPLETE.
 [Environment]::SetEnvironmentVariable('AIW_TEST_PUBLICATION_SECOND_FINALIZE','1','Process')
 try{Reject {InvokePublication $case} 'SOURCE_PUBLICATION_ORIGINAL_FINALIZE_FAILED\|CONTROL' ($Name+'-second-real-finalize-failure-keeps-batch-open')}
 finally{[Environment]::SetEnvironmentVariable('AIW_TEST_PUBLICATION_SECOND_FINALIZE',$null,'Process')}
 $sourceInput=$case.recovery.members[0].finalizeInputRef.path+'.publication-complete-input.json';$sourceResult=$sourceInput+'.result.json'
 Check ((Test-Path -LiteralPath $sourceResult)-and-not(Test-Path -LiteralPath ($case.recovery.members[1].finalizeInputRef.path+'.publication-complete-input.json.result.json'))-and-not(Test-Path -LiteralPath $journal)) ($Name+'-only-first-success-result-exists')
 $saved=Identity $sourceResult;$stamp=[IO.File]::GetLastWriteTimeUtc($sourceResult)
 Reject {InvokePublication $case ROLLBACK} 'FORMAL_RESULT_NO_REVERSE' ($Name+'-first-formal-result-prevents-automatic-rollback')
 $result=InvokePublication $case
 Check ($result.status-ceq'COMPLETE'-and$result.validations.Count-eq2-and$result.writes-eq0-and(Identity $sourceResult)-ceq$saved-and[IO.File]::GetLastWriteTimeUtc($sourceResult)-eq$stamp) ($Name+'-retry-only-finishes-second-member')
 foreach($validation in $result.validations){$actual=Get-Content -LiteralPath $validation.outputRef.path -Raw|ConvertFrom-Json -Depth 100;Check ($actual.status-ceq'PASS'-and$actual.actionOutcome-ceq'OBSERVED'-and$actual.projectSourcePreparation.outcome-ceq'COMPLETED') ($Name+'-'+$validation.member+'-has-real-original-result')}
 $paths=@($result.validations|ForEach-Object{$_.inputRef.path;$_.outputRef.path})+@($case.plan.objects|ForEach-Object{Join-Path $fixture.root $_.path})
 $beforeRetry=@($paths|ForEach-Object{$_+'|'+(Identity $_)})
 $again=InvokePublication $case
 Check ($again.status-ceq'COMPLETE'-and$again.writes-eq0-and($beforeRetry-join'|')-ceq(@($paths|ForEach-Object{$_+'|'+(Identity $_)})-join'|')) ($Name+'-completed-original-results-are-reused')
 Check (-not(Test-Path -LiteralPath $journal)-and(Identity (Join-Path $fixture.root 'standards/noop.md'))-ceq$before['standards/noop.md']) ($Name+'-no-new-journal-or-noop-write')
}

function TestWriterBoundary {
 $root=Join-Path $temp 'writers';$runtime=Join-Path $root '.ai-workspace/runtime';$null=[IO.Directory]::CreateDirectory($runtime)
 $path=Join-Path $versionRoot 'scripts/ProjectSourcePublication.psm1';$pub=@(Import-Module $path -PassThru)[0]
 $readyName='Local\AIW-WriterReady-'+[guid]::NewGuid().ToString('N');$releaseName='Local\AIW-WriterRelease-'+[guid]::NewGuid().ToString('N')
 $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$readyName);$release=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$releaseName)
 $holder=$null
 try{
  $holder=StartFixtureWorker @{operation='HOLD';pub=$path;root=$root;mode='PUBLICATION';ready=$readyName;release=$releaseName} $runtime
  Check ($ready.WaitOne(30000)) 'actual-first-transaction-writer-is-parked'
  Reject {& $pub.ExportedCommands['Enter-AiwProjectSourceScope'] $root PUBLICATION} 'SOURCE_PUBLICATION_BUSY' 'actual-two-transaction-writers-conflict'
  $fake=[pscustomobject]@{Root=$root;Mode='PUBLICATION';Handle=$null;OwnerModule=$pub}
  Reject {& $pub.ExportedCommands['Set-AiwProjectSourcePublicationContext'] $fake @{}} 'SCOPE_INVALID|SCOPE_' 'forged-writer-cannot-activate-original-recovery'
  Check ($null-eq(& $pub.ExportedCommands['Enter-AiwProjectSourceScope'] $root OBSERVE)) 'ordinary-read-does-not-borrow-transaction-writer'
 }finally{
  $release.Set()|Out-Null
  if($null-ne$holder-and-not$holder.finished){$done=FinishFixtureWorker $holder 'actual-writer-release';Check ($done.code-eq0) 'actual-transaction-writer-releases'}
  $ready.Dispose();$release.Dispose()
 }
 $aiwPublicationScopeLease=& $pub.ExportedCommands['Enter-AiwProjectSourceScope'] $root PUBLICATION
 try{Reject {& $pub.ExportedCommands['Set-AiwProjectSourcePublicationContext'] $aiwPublicationScopeLease ([pscustomobject]@{schemaVersion=3;kind='PROJECT_SOURCE_PUBLICATION_RECOVERY';projectRoot=$root;planRef=@{};candidateRef=@{};members=@()})} 'RECOVERY_MEMBERS|TWO_ADMISSIONS' 'real-writer-still-requires-two-original-admissions'}finally{& $pub.ExportedCommands['Exit-AiwProjectSourceScope'] $aiwPublicationScopeLease}
}

function TestDailySources {
 $fixture=NewFixture 'daily-sources';$root=$fixture.root;$runtime=$fixture.runtime
 foreach($kind in @('policy','config','both')){
  $oldConfig=[IO.File]::ReadAllBytes($fixture.configPath);$oldPolicy=[IO.File]::ReadAllBytes($fixture.policyPath)
  $config=Get-Content -LiteralPath $fixture.configPath -Raw|ConvertFrom-Json -Depth 100;$policy=Get-Content -LiteralPath $fixture.policyPath -Raw|ConvertFrom-Json -Depth 100
  if($kind-cin@('config','both')){$config.sourceBindings[0].allowedPaths+=@([pscustomobject]@{kind='FILE';locator='extra-'+$kind+'.md'})}
  if($kind-cin@('policy','both')){$policy.rules[0].requirementReason='Explicit changed '+$kind+' daily source decision.'}
  $nextConfig=Join-Path $runtime ($kind+'-config.json');$nextPolicy=Join-Path $runtime ($kind+'-policy.json')
  if($kind-ceq'policy'){[IO.File]::WriteAllBytes($nextConfig,$oldConfig)}else{SaveJson $nextConfig $config}
  if($kind-ceq'config'){[IO.File]::WriteAllBytes($nextPolicy,$oldPolicy)}else{SaveJson $nextPolicy $policy}
  $paths=@(if($kind-cin@('policy','both')){'.ai-workspace/process-policy.json'};if($kind-cin@('config','both')){'.ai-workspace/project.json'})
  $action=StartCurrentAction $fixture ('daily-'+$kind) $paths
  $decisionPath=Join-Path $runtime ($kind+'-decision.md');SaveText $decisionPath 'Fixture original bounded source adoption decision.'
  $composer=@(Import-Module (Join-Path $fixture.version 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
  $prepared=& $composer.ExportedCommands['New-AiwProjectSourceChangePreparation'] -DiscoverReceiptPath $action.compact -ExpectedDiscoverReceiptIdentity (Identity $action.compact) -ConfigPostimagePath $nextConfig -PolicyPostimagePath $nextPolicy -DecisionRef (Reference $decisionPath) -OutputDirectory (Join-Path $runtime ($kind+'-candidate'))
  $admit=CopyValue $action.boundary;$admit.preparationReceipts=@($admit.preparationReceipts+$prepared.preparationRequirements|Sort-Object -Unique)+@($prepared.preparationReceipt)
  $admitPath=Join-Path $runtime ($kind+'-admit.json');SaveJson $admitPath $admit;$a=FixtureBoundary $fixture $admitPath
  Check ($a.code-eq0-and$a.value.status-ceq'PASS') ($kind+'-actual-write-scope-admitted')
  $resultPath=$admitPath+'.result.json';SaveJson $resultPath $a.value
  $candidate=Get-Content -LiteralPath $prepared.candidate.path -Raw|ConvertFrom-Json -Depth 100
  foreach($entry in $candidate.objects|Where-Object{$_.preimage.identity-cne$_.postimage.identity}){SaveAtomicBytes (Join-Path $root $entry.path) ([IO.File]::ReadAllBytes($entry.postimage.path))}
  $f=CopyValue $admit;$f.mode='FINALIZE_OUTPUT';$f.preparationReceipts+=@('PROJECT_SOURCE_ADMISSION|'+$admitPath+'|'+(Identity $admitPath)+'|'+$resultPath+'|'+(Identity $resultPath));$f.resultReceipts=@($action.receipt.selectedObligations.resultRequirements+$prepared.resultRequirements|Sort-Object -Unique)+@($candidate.objects|Where-Object{$_.path-cin$paths}|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.postimage.identity})
  $fPath=Join-Path $runtime ($kind+'-finalize.json');SaveJson $fPath $f;$closed=FixtureBoundary $fixture $fPath
  Check ($closed.code-eq0-and$closed.value.status-ceq'PASS'-and$closed.value.projectSourcePreparation.outcome-ceq'COMPLETED') ($kind+'-original-finalize-without-noop-companion')
 }
}

function SaveAtomicBytes([string]$Path,[byte[]]$Bytes){
 $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{[IO.File]::WriteAllBytes($temporary,$Bytes);[IO.File]::Move($temporary,$Path,$true)}finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function StartCurrentAction($Fixture,[string]$Name,[string[]]$Paths){
 $root=$Fixture.root;$runtime=$Fixture.runtime;$configIdentity=Identity $Fixture.configPath;$taskIdentity=Identity $Fixture.taskPath
 $package=[pscustomobject]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='PUBLICATION-001';profile='STANDARD';lifecycle='ACTIVE';owner='publication-actor';issuer='publication-actor';issuerRole='TASK_OWNER';grantee='publication-actor';bundle='LOCAL_BOUNDED';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=$taskIdentity;actions=@('CONTROL_WRITE');exactPaths=$Paths;objectIdentities=@($Paths|ForEach-Object{[pscustomobject]@{path=$_;identity=(Identity (Join-Path $root $_))}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=$configIdentity}
 $packagePath=Join-Path $runtime ($Name+'-package.json');SaveJson $packagePath $package
 $checked=FixtureChecker $root (Join-Path $Fixture.version 'scripts/check-authorization.ps1') @{PackagePath=$packagePath;ObservedActor='publication-actor';ObservedTaskId='PUBLICATION-001';ObservedOwner='publication-actor';ObservedAction=@('CONTROL_WRITE');ObservedPath=$Paths;ObservedIdentity=@($package.objectIdentities|ForEach-Object{$_.path+'='+$_.identity});ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=$configIdentity;TaskPath=$Fixture.taskRelative;ExpectedTaskIdentity=$taskIdentity;ControllerControlPath='.ai-workspace/controller.json'}
 Check ($checked.code-eq0) ($Name+'-independent-checker')
 $intent=@{schemaVersion=2;objective='Maintain the original bounded current task or adopted source carrier.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=$Paths;capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:implementation')};deliverableType=@{state='KNOWN';values=@('aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}
 $input=@{schemaVersion=5;ruleLoad=@{mode='FULL'};mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$root;frameworkRoot=$Fixture.framework;taskPath=$Fixture.taskPath;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Identity (Join-Path $root '.ai-workspace/corrections.json'));expectedTaskIdentity=$taskIdentity;observedActor='publication-actor';capabilities=@();exactPaths=$Paths;forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Identity $packagePath);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
 $discover=Join-Path $runtime ($Name+'-discover.json');$compact=Join-Path $runtime ($Name+'-compact.json');SaveJson $discover $input
 $d=FixtureBoundary $Fixture $discover $compact;Check ($d.code-eq0-and$d.value.status-ceq'PASS') ($Name+'-public-DISCOVER')
 $b=[pscustomobject]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compact;expectedDiscoverReceiptIdentity=(Identity $compact);preparationReceipts=@($d.value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 return [pscustomobject]@{receipt=$d.value.compactReceipt;boundary=$b;compact=$compact;discover=$discover;input=$input}
}

function TestSharedPerformance {
 $fixture=NewFixture 'shared-performance';$runtime=$fixture.runtime;$paths=@($fixture.taskRelative)
 $action=StartCurrentAction $fixture current-task $paths
 $admit=Join-Path $runtime 'current-task-admit.json';SaveJson $admit $action.boundary;$a=FixtureBoundary $fixture $admit
 Check ($a.code-eq0-and$a.value.status-ceq'PASS') 'shared-performance-real-current-task-ADMIT'
 $reader=CopyValue $action.input;$reader.contextType='PROJECT_READ_ONLY';$reader.readOnlyContext=[pscustomobject]@{sessionId='publication-actor';requestId='bounded-reader';role='EXECUTOR';phase='PLAN';profile='STANDARD'};$reader.taskPath='NOT_APPLICABLE';$reader.expectedTaskIdentity='NOT_APPLICABLE';$reader.exactPaths=@();$reader.authorizationPackagePath='NOT_REQUIRED';$reader.expectedAuthorizationIdentity='NOT_REQUIRED';$reader.intentEnvelope.requestedActionKind='NONE';$reader.intentEnvelope.requestedResultKind='PLAN';$reader.intentEnvelope.facets.workType.values=@('aiw:planning');$reader.intentEnvelope.facets.deliverableType.values=@('aiw:plan');$reader.intentEnvelope.facets.stage.values=@('aiw:planning');$reader.intentEnvelope.pathHints=@();$reader.intentEnvelope.mutationHints=@();$reader.intentEnvelope.objective='Read the current bounded project rules.'
 $readerPath=Join-Path $runtime 'parked-reader-input.json';SaveJson $readerPath $reader
 $readyName='Local\AIW-ReaderReady-'+[guid]::NewGuid().ToString('N');$releaseName='Local\AIW-ReaderRelease-'+[guid]::NewGuid().ToString('N')
 $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$readyName);$release=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$releaseName);$worker=$null
 try{
  $worker=StartFixtureWorker @{operation='PARKED_READER';version=$fixture.version;root=$fixture.root;inputPath=$readerPath;ready=$readyName;release=$releaseName} $runtime
  Check ($ready.WaitOne(30000)) 'shared-performance-actual-public-reader-is-parked-in-native-rule-read'
  $task=[IO.File]::ReadAllBytes($fixture.taskPath);$after=$utf8.GetBytes($utf8.GetString($task)+"`n- Current result: bounded implementation progress recorded.`n")
  SaveAtomicBytes $fixture.taskPath $after
  $final=CopyValue $action.boundary;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@($action.receipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$fixture.taskRelative+'|'+(Identity $fixture.taskPath))
  $finalPath=Join-Path $runtime 'current-task-finalize.json';SaveJson $finalPath $final
  $selected=Join-Path $fixture.root 'standards/data.md';$selectedBytes=[IO.File]::ReadAllBytes($selected)
  try{SaveText $selected 'Unbound third-party selected source';$bad=FixtureBoundary $fixture $finalPath;Check ($bad.code-ne0) 'shared-performance-selected-source-drift-still-rejected'}finally{[IO.File]::WriteAllBytes($selected,$selectedBytes)}
  $controller=Join-Path $fixture.root '.ai-workspace/controller.json';$controllerBytes=[IO.File]::ReadAllBytes($controller)
  try{$value=$utf8.GetString($controllerBytes)|ConvertFrom-Json;$value.controllerEpoch++;SaveJson $controller $value;$bad=FixtureBoundary $fixture $finalPath;Check ($bad.code-ne0) 'shared-performance-authority-drift-still-rejected'}finally{[IO.File]::WriteAllBytes($controller,$controllerBytes)}
  $boundaryScript=Join-Path $fixture.version 'scripts/ProcessRequirementBoundary.psm1';$lines=[IO.File]::ReadAllLines($boundaryScript);$line=1+[array]::IndexOf($lines,'      $taskPostimageTransition=$true')
  if($line-le0){throw 'TEST_CURRENT_TASK_TRANSITION_LINE_REQUIRED'}
  $global:AiwCurrentTaskTransitionHits=0;$bp=Set-PSBreakpoint -Script $boundaryScript -Line $line -Action {$global:AiwCurrentTaskTransitionHits++}
  try{$closed=FixtureBoundary $fixture $finalPath}finally{Remove-PSBreakpoint $bp}
  Check ($closed.code-eq0-and$closed.value.status-ceq'PASS'-and$global:AiwCurrentTaskTransitionHits-gt0-and-not$worker.handle.Process.HasExited) 'shared-performance-current-card-atomic-update-and-original-F-use-taskPostimageTransition-while-reader-parked'
 }finally{
  $release.Set()|Out-Null
  if($null-ne$worker-and-not$worker.finished){$done=FinishFixtureWorker $worker 'parked-real-reader-release';Check ($done.code-eq0-and$done.text-match'"status":"PASS"') 'shared-performance-actual-public-reader-completes'}
  $ready.Dispose();$release.Dispose()
 }
 TestWriterBoundary
}

$succeeded=$false
try{
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','publication-actor','Process')
 if($Group-cin@('All','Scope')){TestPathIo}
 if($Group-cin@('All','Scope','Synchronization')){TestWriterBoundary}
 if($Group-cin@('All','ModuleIsolation')){TestModuleIsolation}
 if($Group-cin@('All','DailySources')-or($Group-ceq'Publication'-and$PublicationLayout-ceq'All')){TestDailySources}
 if($Group-cin@('All','SharedPerformance')){TestSharedPerformance}
 if($Group-ceq'PublicationScale'){TestPublicationScale}
 if($Group-ceq'SingleRule'){TestPublicationSingleRule}
 if($Group-cin@('All','HistoricalAssurance')){TestHistoricalAssurance}
 if($Group-cin@('All','Publication')){
  TestCanonical
  if($Group-ceq'All'-or$PublicationLayout-cin@('All','Ordinary')){TestOrdinaryPublication ordinary}
  if($Group-ceq'All'-or$PublicationLayout-cin@('All','Maintenance')){TestOrdinaryPublication maintenance -Maintenance}
 }
 if($Group-cin@('All','RecoveryContext')){TestPublicationRecoveryContextReuse}
 if($Group-cin@('All','JointBoundary')){TestPublicationJointBoundary}
 if($Group-ceq'TargetStandards'){TestPublicationTargetStandards;Write-Output 'PARTIAL|TARGET_STANDARDS_ONLY'}
 if($Group-ceq'EmptyPolicy'){TestOrdinaryPublication empty-policy -EmptyPolicy}
 if($Group-ceq'Singleton'){TestOrdinaryPublication singleton -Singleton}
 $succeeded=$true
 if($Group-ceq'Publication'-and$PublicationLayout-cne'All'){Write-Output ('PARTIAL|PUBLICATION_LAYOUT_ONLY|'+$PublicationLayout)}
 Write-Output ('SOURCE_PUBLICATION_TESTS_PASS|checks='+$script:checks+'|group='+$Group+'|scope=ISOLATED_WINDOWS_FIXTURES')
}finally{
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID',$oldHostActor,'Process')
 if($KeepFixture-or-not$succeeded){Write-Output ('FIXTURE|'+$temp)}else{
  $verified=AssertFixturePath (Join-Path $temp 'cleanup-anchor');if([IO.Path]::GetDirectoryName($verified)-cne$temp){throw 'TEST_CLEANUP_SCOPE'}
  [IO.Directory]::Delete($temp,$true)
 }
}
