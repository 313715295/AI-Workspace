[CmdletBinding()]
param(
  [ValidateRange(0,100)][int]$Warmups = 1,
  [ValidateRange(1,100)][int]$MeasuredRuns = 5,
  [switch]$AsJson,[switch]$FixtureContractOnly,
  [switch]$SourceObservation,[string]$BeforeSourceRoot,[string]$CompletionFixturePath,
  [string]$CompletionProcessResultPath,[string]$ObservationOutputDirectory,
  [string]$ObservationWorkerInput,
  [ValidateSet('Legacy','MediaShape','SharedPerformance')][string]$SourceObservationProfile = 'Legacy',
  [string]$ObservationResumeDirectory,
  [switch]$InstrumentSourceObservation
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1') -Force
$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$fixturePath=Join-Path $PSScriptRoot 'PROCESS_REQUIREMENTS_FIXTURES.json'
$fixtureContract=Get-Content -Raw -Encoding utf8 -LiteralPath $fixturePath|ConvertFrom-Json
$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
$tempName='aiw-1.14-process-measure-'+[guid]::NewGuid().ToString('N')
$temp=[IO.Path]::GetFullPath((Join-Path $tempRoot $tempName))
if([IO.Path]::GetDirectoryName($temp)-cne$tempRoot-or[IO.Path]::GetFileName($temp)-cne$tempName-or$tempName-cnotmatch'^aiw-1\.14-process-measure-[a-f0-9]{32}$'){throw 'MEASUREMENT_TEMP_SCOPE'}

function Write-Utf8([string]$Path,[string]$Text){
  $parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  $normalized=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$normalized.EndsWith("`n")){$normalized+="`n"}
  [IO.File]::WriteAllText($Path,$normalized,$utf8)
}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Get-FixtureIdentity($Fixture){
  $ordered=[ordered]@{};foreach($property in @($Fixture.PSObject.Properties)){if($property.Name-cne'fixtureIdentity'){$ordered[$property.Name]=$property.Value}}
  $bytes=$utf8.GetBytes(($ordered|ConvertTo-Json -Depth 30 -Compress));return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Invoke-Cold([string]$Script,[string]$InputPath,[int]$ExpectedExit){
  $watch=[Diagnostics.Stopwatch]::StartNew();$output=@(& pwsh -NoLogo -NoProfile -File $Script -InputPath $InputPath -AsJson 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE;$watch.Stop()
  if($code-ne$ExpectedExit){throw ('MEASUREMENT_UNEXPECTED_EXIT|expected='+$ExpectedExit+'|actual='+$code+'|'+($output-join';'))}
  try{$null=$output[-1]|ConvertFrom-Json}catch{throw ('MEASUREMENT_OUTPUT_NOT_JSON|'+($output-join';'))}
  return [pscustomobject]@{Milliseconds=$watch.Elapsed.TotalMilliseconds;ExitCode=$code;Output=$output[-1]}
}
function Get-Statistics([double[]]$Values){
  $sorted=@($Values|Sort-Object);$median=if($sorted.Count%2-eq1){$sorted[[int][math]::Floor($sorted.Count/2)]}else{($sorted[$sorted.Count/2-1]+$sorted[$sorted.Count/2])/2.0};$rank=[math]::Max(1,[math]::Ceiling(0.95*$sorted.Count));return [pscustomobject]@{Median=[math]::Round($median,3);P95=[math]::Round($sorted[$rank-1],3)}
}

# Opt-in observations keep plain wall pairs separate from instrumented samples.
# No source/view bytes or qualification readers are changed by instrumentation.
function Add-ObservationTimer($Module,[string]$Name,[string]$Stage){
  & $Module {
    param($name,$stage)
    $tokens=$null;$errors=$null;$fileAst=[Management.Automation.Language.Parser]::ParseFile($ExecutionContext.SessionState.Module.Path,[ref]$tokens,[ref]$errors)
    $found=@($fileAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
    if($errors.Count-or$found.Count-ne1){throw ('OBSERVATION_FUNCTION_LOCATOR|'+$name)}
    $function=$found[0];$body=$function.Body.Extent.Text;$text=$body.Substring(1,$body.Length-2);$param=$function.Body.ParamBlock
    if($null-eq$param){$prefix='param('+[string]::Join(',',@($function.Parameters|ForEach-Object{$_.Extent.Text}))+')';$text=$prefix+$text;$at=$prefix.Length}else{$at=$text.IndexOf($param.Extent.Text,[StringComparison]::Ordinal)+$param.Extent.Text.Length;if($at-lt$param.Extent.Text.Length){throw 'OBSERVATION_PARAM_LOCATOR'}}
    $wrapped=$text.Substring(0,$at)+';$__aiwObservationStart=$null;try{$__aiwObservationStart=[Diagnostics.Stopwatch]::GetTimestamp()}catch{try{$global:AiwObservationErrors.Add($_.Exception.Message)}catch{}};try{'+$text.Substring($at)+'}finally{if($null-ne$__aiwObservationStart){try{$global:AiwObservationStages.Add([pscustomobject]@{stage='''+$stage+''';milliseconds=([Diagnostics.Stopwatch]::GetTimestamp()-$__aiwObservationStart)*1000.0/[Diagnostics.Stopwatch]::Frequency})}catch{try{$global:AiwObservationErrors.Add($_.Exception.Message)}catch{}}}}'
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($wrapped,$ExecutionContext.SessionState.Module.Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('OBSERVATION_TIMER_PARSE|'+$name)}
    Set-Item ('Function:script:'+$name) ($ExecutionContext.SessionState.Module.NewBoundScriptBlock($ast.GetScriptBlock()))
  } $Name $Stage
}
function Add-ObservationNativeTimer($Pub){
  # These private test functions time the actual native operations, not the
  # Enter/Exit wrappers. Borrowers do not open/close or add hold intervals.
  & $Pub {
    function script:Open-ObservationHandle($Path,$Share){
      $native=[IO.File]::Open($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,$Share)
      try{$global:AiwObservationHandles.Add($native,[Diagnostics.Stopwatch]::GetTimestamp())}catch{try{$global:AiwObservationErrors.Add($_.Exception.Message)}catch{}}
      return $native
    }
    function script:Close-ObservationHandle($Native){
      try{$Native.Dispose()}finally{
        try{if($global:AiwObservationHandles.ContainsKey($Native)){
          $global:AiwObservationHolds.Add(([Diagnostics.Stopwatch]::GetTimestamp()-$global:AiwObservationHandles[$Native])*1000.0/[Diagnostics.Stopwatch]::Frequency)
          $global:AiwObservationHandles.Remove($Native)|Out-Null
        }}catch{try{$global:AiwObservationErrors.Add($_.Exception.Message)}catch{}}
      }
    }
    foreach($name in @('Enter-AiwProjectSourceScope','Exit-AiwProjectSourceScope')){
      $text=(Get-Item ('Function:'+$name)).ScriptBlock.ToString()
      if($name-ceq'Enter-AiwProjectSourceScope'){
        $needle='$handle=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,$share)'
        if(([regex]::Matches($text,[regex]::Escape($needle))).Count-ne1-or-not$text.Contains('$handle.Dispose()')){throw 'OBSERVATION_NATIVE_OPEN_LOCATOR'}
        $text=$text.Replace($needle,'$handle=Open-ObservationHandle $lockPath $share').Replace('$handle.Dispose()','(Close-ObservationHandle $handle)')
      }else{
        if(([regex]::Matches($text,[regex]::Escape('$Scope.Handle.Dispose()'))).Count-ne1){throw 'OBSERVATION_NATIVE_CLOSE_LOCATOR'}
        $text=$text.Replace('$Scope.Handle.Dispose()','(Close-ObservationHandle $Scope.Handle)')
      }
      $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,$ExecutionContext.SessionState.Module.Path,[ref]$tokens,[ref]$errors)
      if($errors.Count){throw 'OBSERVATION_NATIVE_PARSE'}
      Set-Item ('Function:script:'+$name) ($ExecutionContext.SessionState.Module.NewBoundScriptBlock($ast.GetScriptBlock()))
    }
  }
}
function Invoke-ObservationWorker {
  $request=Get-Content -LiteralPath $ObservationWorkerInput -Raw|ConvertFrom-Json -Depth 100
  if($request.kind-ceq'MEDIA_SHAPE'){Invoke-ShapeObservationWorker $request;return}
  $global:AiwObservationStages=[Collections.Generic.List[object]]::new();$global:AiwObservationHolds=[Collections.Generic.List[double]]::new();$global:AiwObservationHandles=[Collections.Generic.Dictionary[object,long]]::new();$global:AiwObservationErrors=[Collections.Generic.List[string]]::new()
  $v=Join-Path $request.frameworkRoot 'framework/versions/2.0.0'
  $boundary=@(Import-Module (Join-Path $v 'scripts/ProcessRequirementBoundary.psm1') -PassThru)[0]
  $pub=& $boundary {(Get-Command Enter-AiwProjectSourceScope).Module}
  if($request.instrumented){
    Add-ObservationNativeTimer $pub;Add-ObservationTimer $pub Assert-PubJournalObservation 'journal-observation-inclusive'
    if($request.kind-ceq'SHARED'){
      $composer=& $boundary {param($path) @(Import-Module $path -PassThru)[0]} (Join-Path $v 'scripts/ProcessRequirementComposition.psm1')
      foreach($item in @(@('Get-AiwCompositionReleaseFacts','release-qualification-inclusive'),@('Get-AiwLocalCandidatePilotBinding','adoption-binding-inclusive'),@('Get-AiwProjectStandardsSnapshot','complete-source-graphs-inclusive'),@('Test-AiwEffectiveRuleSet','effective-set'),@('Get-AiwNativeRuleBlock','selected-native-body'))){Add-ObservationTimer $composer $item[0] $item[1]}
    }
  }
  if($request.instrumented){
    # Imported FunctionInfo objects retain the prior script block. Refresh the
    # existing two exports and their boundary imports without reloading modules
    # or resetting private registries; all source/view bytes remain unchanged.
    & $pub {Export-ModuleMember -Function Enter-AiwProjectSourceScope,Exit-AiwProjectSourceScope}
    & $boundary {param($path) Import-Module $path} $pub.Path
  }
  $watch=[Diagnostics.Stopwatch]::StartNew()
  if($request.kind-ceq'SHARED'){
    $result=& $boundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $request.inputPath -AsJson
    $watch.Stop()
    if($result.exitCode-ne0){throw ('OBSERVATION_BOUNDARY_FAILED|'+($result.output-join' '))}
    $responseText=$result.output-join[char]10
    [IO.File]::WriteAllText($request.responsePath,$responseText,[Text.UTF8Encoding]::new($false))
    $responseRef=@{path=$request.responsePath;identity=(Get-Identity $request.responsePath)}
    $decode=[Diagnostics.Stopwatch]::StartNew();$wire=$responseText|ConvertFrom-Json -Depth 100;$decode.Stop()
    if($request.instrumented){try{$global:AiwObservationStages.Add([pscustomobject]@{stage='response-json-decode';milliseconds=$decode.Elapsed.TotalMilliseconds})}catch{$global:AiwObservationErrors.Add($_.Exception.Message)}}
    if($wire.status-cne'PASS'){throw 'OBSERVATION_DISCOVER_NOT_PASS'}
    $logical=[ordered]@{projectBlocks=@($wire.selectedRuleBlocks|Where-Object requirementId -CLike 'project:measure-source:*'|ForEach-Object{[ordered]@{id=$_.requirementId;fullText=$_.fullText}});projectObligations=@($wire.compactReceipt.selectedObligations|Where-Object requirementId -CLike 'project:measure-source:*'|ForEach-Object{[ordered]@{id=$_.requirementId;preparationRequirements=$_.preparationRequirements;resultRequirements=$_.resultRequirements}});sourceOrder=@($wire.readTrace|Where-Object event -CEQ SOURCE_BODY_READ|ForEach-Object sourceId);allSelectedRuleIds=@($wire.selectedRuleBlocks|ForEach-Object requirementId);allObligations=@($wire.compactReceipt.selectedObligations|ForEach-Object{[ordered]@{id=$_.requirementId;preparationRequirements=$_.preparationRequirements;resultRequirements=$_.resultRequirements}})}
    if($logical.projectBlocks.Count-ne2-or($logical.sourceOrder-join',')-cne'C,D,A,D,C,B,Z'){throw 'OBSERVATION_FULL_SOURCE_OR_ORDER'}
  }elseif($request.kind-ceq'COMPLETED'){
    $responseRef='NOT_APPLICABLE'
    $logical=& $pub {
      param($root)
      Invoke-AiwProjectSourceScope -ProjectRoot $root -Body {
        param($root)
        $states=@()
        foreach($iteration in 1..5){
          $borrow=Enter-AiwProjectSourceScope $root
          try{if((Get-PubLeaseFacts $borrow).Owned){throw 'OBSERVATION_REAL_BORROW_REQUIRED'};$states+=@((Read-AiwProjectSourcePublicationJournal $root).state)}finally{Exit-AiwProjectSourceScope $borrow}
        }
        return [ordered]@{states=$states;borrowCount=5}
      } -ArgumentList @($root)
    } $request.projectRoot
    $watch.Stop()
    if(@($logical.states|Where-Object{$_-cnotin@('COMPLETE','ROLLED_BACK')}).Count){throw 'OBSERVATION_REAL_COMPLETION_REQUIRED'}
  }else{throw 'OBSERVATION_WORKER_KIND'}
  $watch.Stop();if($global:AiwObservationHandles.Count){$global:AiwObservationErrors.Add('OBSERVATION_NATIVE_HANDLE_TRACKING_INCOMPLETE')}
  [ordered]@{kind=$request.kind;instrumented=$request.instrumented;actionStatus='PASS';actionMilliseconds=$watch.Elapsed.TotalMilliseconds;fullResponseRef=$responseRef;logical=$logical;instrumentationErrors=$global:AiwObservationErrors.ToArray();stages=$global:AiwObservationStages.ToArray();nativeOwnedHoldMilliseconds=$global:AiwObservationHolds.ToArray();nativeOwnedIntervals=$global:AiwObservationHolds.Count}|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii
}

function Invoke-SourceObservation {
  if($FixtureContractOnly-or-not$BeforeSourceRoot-or-not$CompletionFixturePath-or-not$CompletionProcessResultPath-or-not$ObservationOutputDirectory){throw 'OBSERVATION_ARGUMENTS'}
  $outRoot=Assert-AiwTestPath $ObservationOutputDirectory
  if(Test-Path -LiteralPath (Join-Path $outRoot 'observation-results.json')){throw 'OBSERVATION_OUTPUT_EXISTS'}
  $null=[IO.Directory]::CreateDirectory($outRoot)
  $completion=Get-Content -LiteralPath $CompletionFixturePath -Raw|ConvertFrom-Json -Depth 100
  $producer=Get-Content -LiteralPath $CompletionProcessResultPath -Raw|ConvertFrom-Json -Depth 100
  if($completion.kind-cne'ACTUAL_COMPLETED_PUBLICATION_FIXTURE'-or-not$completion.retained-or$producer.exitCode-ne0-or$producer.status-cne'PASS'-or(Get-Identity $producer.stdout.path)-cne$producer.stdout.identity-or-not([IO.File]::ReadAllText($producer.stdout.path).Contains('COMPLETION_FIXTURE|'+$CompletionFixturePath))-or(Get-Identity $completion.journalRef.path)-cne$completion.journalRef.identity){throw 'OBSERVATION_ACTUAL_GENERATOR_PROOF'}
  $journal=Get-Content -LiteralPath $completion.journalRef.path -Raw|ConvertFrom-Json -Depth 100
  if($journal.state-cnotin@('COMPLETE','ROLLED_BACK')-or$journal.completionProof.validations.Count-ne2){throw 'OBSERVATION_ACTUAL_COMPLETION_PROOF'}
  $definition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
  $currentSource=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'));$views=[ordered]@{}
  foreach($pair in @(@('before',$BeforeSourceRoot),@('after',$currentSource))){
    $view=Join-Path $outRoot ('runtime-'+$pair[0]);$null=New-AiwTestRuntimeFixture $pair[1] $view $definition.mechanismVersionPaths;$views[$pair[0]]=$view
  }
  . (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly
  $project=Join-Path $outRoot 'shared-project';$configuration=NewTestProject $project 'measure-source'
  $supply=Join-Path $outRoot 'shared-source';$unitPath=Join-Path $supply 'units.md'
  WriteText $unitPath (@('<C>','Shared condition','</C>','<D>','Shared dependency','</D>','<A>','First obligation','</A>','<B>','Second obligation','</B>','<Z>','Unselected obligation','</Z>')-join[char]10)
  $configuration.sourceBindings=@([pscustomobject]@{id='units';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$supply};allowedPaths=@([pscustomobject]@{kind='FILE';locator='units.md'});decisionLocator='fixture:explicit-shared-source'})
  function New-MeasureRule([string]$Id,[string[]]$Order,[string]$Condition,[string]$Dependency,[string]$Stage){
    $documents=@();$ids=@{};$bodies=@{C='Shared condition';D='Shared dependency';A='First obligation';B='Second obligation';Z='Unselected obligation'}
    foreach($node in $Order){
      $isRoot=$node-ceq$Order[-1];[string[]]$conditions=@();[string[]]$dependencies=@()
      if($isRoot-and$Condition){$conditions=@($Condition)};if($isRoot-and$Dependency){$dependencies=@($Dependency)}
      $unit=[ordered]@{provider='LOCAL_DIRECTORY';physicalSource=$unitPath.ToUpperInvariant();permissionIdentity=(Get-AiwContentDescriptorIdentity $configuration.sourceBindings[0]);mode='NORMATIVE_UNIT';unitId=$node;parserVersion='UTF8_LF_COMPLETE_UNIT_V1';sectionStart=('<'+$node+'>');sectionEnd=('</'+$node+'>');bodyIdentity=(Get-AiwContentByteIdentity $utf8.GetBytes($bodies[$node]))}
      $norm=Get-AiwContentDescriptorIdentity ([ordered]@{unit=$unit;commonConditions=@($conditions|ForEach-Object{$ids[$_]});dependencies=@($dependencies|ForEach-Object{$ids[$_]})});$ids[$node]=$norm
      $documents+=@([pscustomobject]@{sourceId=$node;bindingId='units';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator='units.md';mode='NORMATIVE_UNIT';unitId=$node;sectionStart=$unit.sectionStart;sectionEnd=$unit.sectionEnd;normativeIdentity=$norm;commonConditionSourceIds=@($conditions);dependencies=@($dependencies)})
    }
    foreach($doc in $documents){$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $configuration.sourceBindings}
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='units';itemId=$Id;revision=(Get-AiwContentRevision ([pscustomobject]@{documents=$documents}) $configuration.sourceBindings);itemIdentity='';rootSourceId=$Order[-1];documents=$documents};$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    return [pscustomobject]@{ruleId=$Id;requirementReason='Representative shared graph';source=$descriptor;selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@('NONE');resultKinds=@('PLAN');pathPrefixes=@();capabilities=@();semanticTerms=@();facets=[pscustomobject]@{stage=@($Stage)}};preparationRequirements=@('P_'+$Id);resultRequirements=@('R_'+$Id);decisionLocator='fixture:explicit-shared-rules'}
  }
  $rules=@((New-MeasureRule FIRST @('C','D','A') C D 'aiw:planning'),(New-MeasureRule SECOND @('D','C','B') D C 'aiw:planning'),(New-MeasureRule UNSELECTED @('Z') '' '' 'aiw:review'))
  Store (Join-Path $project '.ai-workspace/project.json') $configuration;Store (Join-Path $project '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='measure-source';rules=$rules})
  WriteText (Join-Path $project '.ai-workspace/BOOTSTRAP.md') (@('<!-- FRAMEWORK-MANAGED:BEGIN -->','Fixture entry.','<!-- FRAMEWORK-MANAGED:END -->','<!-- PROJECT-CUSTOM:BEGIN -->','<!-- PROJECT-CUSTOM:END -->','')-join[char]10)
  $facet=[ordered]@{}
  foreach($axis in @('domain','workType','deliverableType','stage')){$facet[$axis]=[ordered]@{state='KNOWN';values=@($(switch($axis){domain{'aiw:governance'}workType{'aiw:planning'}deliverableType{'aiw:plan'}stage{'aiw:planning'}}))}}
  $samples=[Collections.Generic.List[object]]::new();$logical=@{}
  foreach($kind in @('SHARED','COMPLETED')){
    for($iteration=-$Warmups;$iteration-le$MeasuredRuns;$iteration++){
      $instrumented=$iteration-eq$MeasuredRuns
      $labels=if($iteration%2-eq0){@('before','after')}else{@('after','before')}
      foreach($label in $labels){
        $token=$kind.ToLowerInvariant()+'-'+$label+'-'+($iteration+$Warmups);$observationInput=Join-Path $outRoot ($token+'-discover.json')
        if($kind-ceq'SHARED'){
          Store $observationInput ([ordered]@{schemaVersion=5;ruleLoad=[ordered]@{mode='FULL'};mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=[ordered]@{sessionId='measure-observer';requestId='shared-source';role='EXECUTOR';phase='PLAN';profile='STANDARD'};projectRoot=$project;frameworkRoot=$views[$label];taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=(Get-Identity (Join-Path $project '.ai-workspace/project.json'));expectedCorrectionsIdentity=(Get-Identity (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity='NOT_APPLICABLE';observedActor='measure-observer';capabilities=@();exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=2;objective='Observe complete shared source graph and current planning obligations.';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=$facet};evaluationOnly=$false})
        }
        $worker=Join-Path $outRoot ($token+'-worker.json')
        Store $worker ([ordered]@{kind=$kind;frameworkRoot=$views[$label];projectRoot=$completion.projectRoot;inputPath=$observationInput;responsePath=(Join-Path $outRoot ($token+'-full-response.json'));instrumented=$instrumented})
        $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-ObservationWorkerInput',$worker) -WorkingDirectory $outRoot -EvidenceDirectory (Join-Path $outRoot 'raw') -GroupId $token
        if($run.Code-ne0){throw ('OBSERVATION_WORKER_FAILED|'+$token+'|'+$run.StderrText+'|'+$run.StdoutText)}
        $value=$run.StdoutText.Trim()|ConvertFrom-Json -Depth 100;$logic=$value.logical|ConvertTo-Json -Depth 100 -Compress
        if($value.instrumentationErrors.Count){throw ('OBSERVATION_INSTRUMENTATION_INVALID_ACTION_REMAINS_'+$value.actionStatus+'|'+$token)}
        if($logical.ContainsKey($kind)-and$logical[$kind]-cne$logic){throw ('OBSERVATION_LOGICAL_OUTPUT_DRIFT|'+$token)};$logical[$kind]=$logic
        if($instrumented-and$kind-ceq'COMPLETED'-and($value.nativeOwnedIntervals-ne1-or$value.nativeOwnedHoldMilliseconds.Count-ne1)){throw ('OBSERVATION_ACTUAL_OWNED_INTERVAL|'+$token)}
        $samples.Add([pscustomobject]@{kind=$kind;variant=$label;warmup=($iteration-lt0);instrumented=$instrumented;wallMilliseconds=$run.Record.timing.wallMilliseconds;result=$value;nativeResultRef=@{path=$run.ResultPath;identity=(Get-Identity $run.ResultPath)}})
      }
    }
  }
  $summary=@()
  foreach($kind in @('SHARED','COMPLETED')){
    $b=@($samples|Where-Object{$_.kind-ceq$kind-and$_.variant-ceq'before'-and-not$_.warmup-and-not$_.instrumented}|ForEach-Object wallMilliseconds)
    $a=@($samples|Where-Object{$_.kind-ceq$kind-and$_.variant-ceq'after'-and-not$_.warmup-and-not$_.instrumented}|ForEach-Object wallMilliseconds)
    $bm=(Get-Statistics $b).Median;$am=(Get-Statistics $a).Median
    $summary+=@([ordered]@{kind=$kind;beforeMedianWallMilliseconds=$bm;afterMedianWallMilliseconds=$am;observedReductionPercent=[math]::Round(100.0*($bm-$am)/$bm,2);plainPairs=$MeasuredRuns;logicalOutputsEqual=$true})
  }
  $inputViews=@()
  foreach($inputPair in @(@('before',$BeforeSourceRoot),@('after',$currentSource))){
    $closure=Join-Path $inputPair[1] 'source-inputs.json'
    $inputViews+=@([ordered]@{variant=$inputPair[0];root=$inputPair[1];sourceInputsRef=$(if(Test-Path -LiteralPath $closure){@{path=$closure;identity=(Get-Identity $closure)}}else{'NOT_AVAILABLE'})})
  }
  $report=[ordered]@{inputViews=$inputViews;schemaVersion=1;kind='REPRESENTATIVE_SOURCE_OBSERVATION';host=([Environment]::OSVersion.VersionString+' / PowerShell '+$PSVersionTable.PSVersion);warmups=$Warmups;measuredPairs=$MeasuredRuns;summary=$summary;samples=$samples.ToArray();completionFixtureRef=@{path=$CompletionFixturePath;identity=(Get-Identity $CompletionFixturePath)};completionProducerRef=@{path=$CompletionProcessResultPath;identity=(Get-Identity $CompletionProcessResultPath)};limits=@('Small paired samples on this fixture/host only; no p95 or SLA claim.','Plain cold-worker wall includes import, the public boundary API or actual publication-scope action, full-response materialization/decoding, evidence output and drain; it is not direct resolver CLI/model latency. Full DISCOVER responses are retained. Instrumented samples are separate and include timing overhead.','Stage intervals are inclusive and nested, never added. Native hold timestamps immediately follow actual File.Open return and Dispose return; one owned interval, no borrowed intervals.','SHARED is actual public DISCOVER with complete effective sources and selection. COMPLETED is five real nested observations under one actual completed-publication owned lease.','Output serialization is included in action total and not isolated; response JSON decoding is measured separately. Authorization/typed evidence, display/model input cost, consumer and Media behavior are not measured.','Private baseline and retained fixture/runtime/raw evidence stay in this observation directory for direct consumers.')}
  Store (Join-Path $outRoot 'observation-results.json') $report
  [ordered]@{kind=$report.kind;summary=$summary;reportPath=(Join-Path $outRoot 'observation-results.json')}|ConvertTo-Json -Depth 20 -Compress
}
# Private diagnostic profile. Its name describes an anonymous workload only.
# All production modules remain byte-identical; rewritten functions are confined
# to a separate worker and reported as PRIVATE_INSTRUMENTED executed code.
function Initialize-ShapeObservation($Request){
  $global:AiwShape=[ordered]@{counts=@{};events=[Collections.Generic.List[object]]::new();stack=[Collections.Generic.List[object]]::new();reads=@{};locks=[Collections.Generic.List[object]]::new();handles=@{};bindings=[Collections.Generic.List[object]]::new();errors=[Collections.Generic.List[string]]::new();canonicalDepth=0;nextId=0;process=[Diagnostics.Process]::GetCurrentProcess();phase=$Request.phasePath;project=$Request.projectRoot;supply=$Request.supplyRoot}
  $global:AiwShape.phaseWriter=Get-Command Write-AiwTestPhase -CommandType Function -ErrorAction Stop
  function global:Start-AiwShapeSpan([string]$Name){
    $s=$global:AiwShape;$s.process.Refresh();$s.nextId++;$parent=if($s.stack.Count){$s.stack[-1].id}else{0}
    $e=[pscustomobject]@{id=$s.nextId;parent=$parent;name=$Name;start=[Diagnostics.Stopwatch]::GetTimestamp();end=0L;children=0L;cpuStart=$s.process.TotalProcessorTime.TotalMilliseconds;cpuEnd=0.0;workingStart=$s.process.WorkingSet64;workingEnd=0L;privateStart=$s.process.PrivateMemorySize64;privateEnd=0L;gcStart=@([GC]::CollectionCount(0),[GC]::CollectionCount(1),[GC]::CollectionCount(2));gcEnd=@();inclusiveMilliseconds=0.0;exclusiveMilliseconds=0.0}
    $s.stack.Add($e)
    if($Name-cmatch 'StandardsSnapshot|EffectiveRuleSet|BindingSnapshot|ReleaseFacts|BOUNDARY') {& $s.phaseWriter $s.phase 'shape-worker' 'shape' $Name START @{pid=$PID;id=$e.id}}
    return $e
  }
  function global:Stop-AiwShapeSpan($Event){
    $s=$global:AiwShape;$Event.end=[Diagnostics.Stopwatch]::GetTimestamp();$s.process.Refresh();$Event.cpuEnd=$s.process.TotalProcessorTime.TotalMilliseconds;$Event.workingEnd=$s.process.WorkingSet64;$Event.privateEnd=$s.process.PrivateMemorySize64;$Event.gcEnd=@([GC]::CollectionCount(0),[GC]::CollectionCount(1),[GC]::CollectionCount(2))
    $ticks=$Event.end-$Event.start;$Event.inclusiveMilliseconds=$ticks*1000.0/[Diagnostics.Stopwatch]::Frequency;$Event.exclusiveMilliseconds=($ticks-$Event.children)*1000.0/[Diagnostics.Stopwatch]::Frequency
    if(-not$s.stack.Count-or$s.stack[-1].id-ne$Event.id){$s.errors.Add('SPAN_STACK_MISMATCH')}else{$s.stack.RemoveAt($s.stack.Count-1);if($s.stack.Count){$s.stack[-1].children+=$ticks}}
    $s.events.Add($Event)
    if($Event.name-cmatch 'StandardsSnapshot|EffectiveRuleSet|BindingSnapshot|ReleaseFacts|BOUNDARY'){& $s.phaseWriter $s.phase 'shape-worker' 'shape' $Event.name END @{pid=$PID;id=$Event.id;milliseconds=$Event.inclusiveMilliseconds}}
  }
  function global:Read-AiwShapeBytes([string]$Path,[string]$Site){
    $s=$global:AiwShape;$full=[IO.Path]::GetFullPath($Path);$key=$Site+'|'+$full
    if(-not$s.reads.ContainsKey($key)){$s.reads[$key]=[ordered]@{site=$Site;path=$full;calls=0;bytes=0L;failures=0;kind=$(if($full.StartsWith($s.supply,[StringComparison]::OrdinalIgnoreCase)){'ANONYMOUS_SOURCE'}elseif($full.EndsWith('process-policy.json')){'POLICY'}elseif($full.EndsWith('project.json')){'CONFIG'}else{'OTHER_FRAMEWORK_OR_AUTHORITY'})}}
    $row=$s.reads[$key];$row.calls++
    try{[byte[]]$bytes=[IO.File]::ReadAllBytes($Path);$row.bytes+=$bytes.LongLength;return ,$bytes}catch{$row.failures++;throw}
  }
  function global:Read-AiwShapeText([string]$Path,$Encoding,[string]$Site){
    # This counts the real ReadAllText call. Its returned text's UTF-8 size is
    # separately named; it is not claimed as an observed physical byte count.
    $s=$global:AiwShape;$key=$Site+'|'+[IO.Path]::GetFullPath($Path)
    if(-not$s.reads.ContainsKey($key)){$s.reads[$key]=[ordered]@{site=$Site;path=[IO.Path]::GetFullPath($Path);calls=0;textUtf8Bytes=0L;failures=0;kind='READ_ALL_TEXT_PHYSICAL_BYTES_NOT_OBSERVED'}}
    $row=$s.reads[$key];$row.calls++
    try{$text=if($null-eq$Encoding){[IO.File]::ReadAllText($Path)}else{[IO.File]::ReadAllText($Path,$Encoding)};$row.textUtf8Bytes+=[Text.Encoding]::UTF8.GetByteCount($text);return $text}catch{$row.failures++;throw}
  }
  function global:Open-AiwShapeHandle($Path,$Share){
    $s=$global:AiwShape;$event=[ordered]@{attempt=[Diagnostics.Stopwatch]::GetTimestamp();opened=0L;disposeStarted=0L;disposed=0L;outcome='ATTEMPT';share=[string]$Share};$s.locks.Add($event)
    & $s.phaseWriter $s.phase 'shape-worker' 'shape' 'native-owner-open' START @{pid=$PID}
    try{$h=[IO.File]::Open($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,$Share);$event.opened=[Diagnostics.Stopwatch]::GetTimestamp();$event.outcome='OPEN';$s.handles.Add($h,$event);return $h}catch{$event.outcome='FAILED';$event.error=$_.Exception.Message;throw}
  }
  function global:Close-AiwShapeHandle($Handle){
    $s=$global:AiwShape;if(-not$s.handles.ContainsKey($Handle)){$s.errors.Add('DISPOSE_WITHOUT_NATIVE_OPEN');$Handle.Dispose();return}
    $e=$s.handles[$Handle];$e.disposeStarted=[Diagnostics.Stopwatch]::GetTimestamp()
    try{$Handle.Dispose();$e.disposed=[Diagnostics.Stopwatch]::GetTimestamp();$e.outcome='DISPOSED';$null=$s.handles.Remove($Handle);& $s.phaseWriter $s.phase 'shape-worker' 'shape' 'native-owner-dispose' END @{pid=$PID;holdMilliseconds=($e.disposed-$e.opened)*1000.0/[Diagnostics.Stopwatch]::Frequency}}catch{$e.outcome='DISPOSE_FAILED';throw}
  }
}
function Add-ShapeModuleObservation($Module){
  $modulePath=$Module.Path;$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw 'SHAPE_MODULE_AST'}
  $functions=@($ast.FindAll({param($n)if($n-isnot[Management.Automation.Language.FunctionDefinitionAst]){return $false};$p=$n.Parent;while($null-ne$p){if($p-is[Management.Automation.Language.FunctionDefinitionAst]){return $false};$p=$p.Parent};return $true},$true))
  $timed=@('Invoke-CsOwnedStandardsBatch','New-CsOwnedContext','Copy-CsOwnedContext','New-CsOwnedGraph','Read-CsOwnedGraph','Read-CsOwnedExact','Read-CsResolvedExact','Resolve-CsOwnedDocument','Convert-CsObservedText','Get-CsReadUnitFromText','Invoke-AiwProcessRequirementBoundary','Invoke-ProcessRequirementComposition','Get-AiwCompositionReleaseFacts','Get-AiwLocalCandidatePilotBinding','Get-AiwProjectStandardsSnapshot','Test-AiwEffectiveRuleSet','Get-AiwProcessBindingSnapshot','Get-AiwProcessImplementationIdentity','New-AiwContentContext','Register-CsContextInputs','Get-CsContextInputs','Get-CsContextSignature','Copy-CsValue','Resolve-AiwContentSnapshot','Get-CsGraphOrder','New-CsGraphReadFrame','Read-CsExactCore','Get-CsReadUnit','Read-AiwContentUnitGraph','Test-AiwRuleMatch','Get-AiwNativeRuleBlock','Get-AiwReleaseQualification','Get-AiwReleaseQualificationCore','Get-AiwFixedReleaseProjection','Get-AiwReleasePayloadFacts','Get-AiwReleasePackageFacts','Assert-PubJournalObservation','Enter-AiwProjectSourceScope','Exit-AiwProjectSourceScope')
  $exports=@($Module.ExportedCommands.Keys)
  foreach($function in $functions){
    $name=$function.Name;$key=[IO.Path]::GetFileName($modulePath)+'/'+$name
    $global:AiwShape.counts[$key]=0L
    $body=$function.Body.Extent.Text;$text=$body.Substring(1,$body.Length-2);$offset=$function.Body.Extent.StartOffset+1;$edits=[Collections.Generic.List[object]]::new()
    # Insertions at pipeline boundaries allow nested ReadAllBytes expressions to
    # retain their own replacement. No parser or source validation is bypassed.
    foreach($node in @($function.Body.FindAll({param($n)$n-is[Management.Automation.Language.PipelineAst]},$true))){
      if(@($node.PipelineElements|Where-Object{$_-is[Management.Automation.Language.CommandAst]-and$_.GetCommandName()-ceq'ConvertFrom-Json'}).Count){
        $edits.Add(@{at=$node.Extent.StartOffset-$offset;length=0;text='$($global:AiwShape.counts[''ordinary-json-pipeline'']++; '});$edits.Add(@{at=$node.Extent.EndOffset-$offset;length=0;text=')'})
      }
    }
    foreach($node in @($function.Body.FindAll({param($n)$n-is[Management.Automation.Language.InvokeMemberExpressionAst]},$true))){
      if($node.Member-isnot[Management.Automation.Language.StringConstantExpressionAst]){continue}
      $arguments=@($node.Arguments|Where-Object{$null-ne$_})
      $call=$node.Extent.Text;$replacement=$null
      if($node.Static-and$node.Expression.Extent.Text-cmatch '^\[(?:System\.)?IO\.File\]$'-and$node.Member.Value-ceq'ReadAllBytes'-and$arguments.Count-eq1){$replacement='(Read-AiwShapeBytes -Path ('+$arguments[0].Extent.Text+') -Site '''+$key+''')'}
      elseif($node.Static-and$node.Expression.Extent.Text-cmatch '^\[(?:System\.)?IO\.File\]$'-and$node.Member.Value-ceq'ReadAllText'-and$arguments.Count-in@(1,2)){$encoding=if($arguments.Count-eq2){$arguments[1].Extent.Text}else{'$null'};$replacement='(Read-AiwShapeText -Path ('+$arguments[0].Extent.Text+') -Encoding ('+$encoding+') -Site '''+$key+''')'}
      elseif($node.Static-and$node.Expression.Extent.Text-cmatch '^\[(?:System\.)?Text\.Json\.JsonDocument\]$'-and$node.Member.Value-ceq'Parse'){$edits.Add(@{at=$node.Extent.StartOffset-$offset;length=0;text='$($global:AiwShape.counts[''strict-json-native-parse'']++; '});$edits.Add(@{at=$node.Extent.EndOffset-$offset;length=0;text=')'})}
      elseif($node.Member.Value-ceq'GetString'-and$arguments.Count-gt0-and$node.Expression.Extent.Text-cmatch 'Utf8|UTF8Encoding|Encoding.*UTF8'){$edits.Add(@{at=$node.Extent.StartOffset-$offset;length=0;text='$($global:AiwShape.counts[''utf8-get-string'']++; '});$edits.Add(@{at=$node.Extent.EndOffset-$offset;length=0;text=')'})}
      if($replacement){$edits.Add(@{at=$node.Extent.StartOffset-$offset;length=$node.Extent.EndOffset-$node.Extent.StartOffset;text=$replacement})}
    }
    # Reject overlapping method replacements rather than silently changing an
    # expression twice. The current targeted readers have nonnested IO calls.
    $end=-1;foreach($edit in @($edits|Where-Object length -GT 0|Sort-Object at)){if($edit.at-lt$end){throw ('SHAPE_OVERLAPPING_METHODS|'+$key)};$end=$edit.at+$edit.length}
    foreach($edit in @($edits|Sort-Object @{Expression='at';Descending=$true},@{Expression='length';Descending=$true})){$text=$text.Remove($edit.at,$edit.length).Insert($edit.at,$edit.text)}
    if($name-ceq'Read-CsResolvedExact'){$needle='$raw=$PhysicalReadCache[$physicalKey]';if(-not$text.Contains($needle)){throw 'SHAPE_CACHE_LOCATOR'};$text=$text.Replace($needle,'$global:AiwShape.counts[''physical-graph-cache-hit'']++;'+$needle)}
    if($name-ceq'Read-CsResolvedNormativeRaw'){$needle='$cached=$PhysicalReadCache[$key]';if(-not$text.Contains($needle)){throw 'SHAPE_NORMATIVE_CACHE_LOCATOR'};$text=$text.Replace($needle,'$global:AiwShape.counts[''physical-graph-cache-hit'']++;'+$needle)}
    if($name-ceq'Enter-AiwProjectSourceScope'){
      $needle='$handle=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,$share)'
      if(-not$text.Contains($needle)-or-not$text.Contains('$handle.Dispose()')){throw 'SHAPE_NATIVE_OPEN_LOCATOR'}
      $text=$text.Replace($needle,'$handle=Open-AiwShapeHandle $lockPath $share').Replace('$handle.Dispose()','(Close-AiwShapeHandle $handle)')
      $needle='return $scope';if(([regex]::Matches($text,[regex]::Escape($needle))).Count-ne2){throw 'SHAPE_BORROW_LOCATOR'};$at=$text.IndexOf($needle,[StringComparison]::Ordinal);$text=$text.Insert($at,'$global:AiwShape.counts[''borrowed-scope'']++;')
    }
    if($name-ceq'Exit-AiwProjectSourceScope'){if(-not$text.Contains('$Scope.Handle.Dispose()')){throw 'SHAPE_NATIVE_DISPOSE_LOCATOR'};$text=$text.Replace('$Scope.Handle.Dispose()','(Close-AiwShapeHandle $Scope.Handle)')}
    $param=$function.Body.ParamBlock
    if($null-eq$param){$prefix='param('+[string]::Join(',',@($function.Parameters|Where-Object{$null-ne$_}|ForEach-Object{$_.Extent.Text}))+')';$text=$prefix+$text;$at=$prefix.Length}else{$at=$text.IndexOf($param.Extent.Text,[StringComparison]::Ordinal)+$param.Extent.Text.Length}
    $start=';$global:AiwShape.counts['''+$key+''']++;'
    $finish=''
    if($name-cin@('Get-AiwContentByteIdentity','Get-CsObservedByteIdentity')){$start+='$global:AiwShape.counts[''content-sha256-input-bytes'']+=$Bytes.LongLength;'}
    if($name-ceq'ConvertTo-AiwContentCanonicalJson'){
      $start+='$__shapeSpan=$null;$global:AiwShape.canonicalDepth++;if($global:AiwShape.canonicalDepth-eq1){$global:AiwShape.counts[''content-canonical-top'']++;$__shapeSpan=Start-AiwShapeSpan ''content-canonical-top''};try{'
      $finish='}finally{$global:AiwShape.canonicalDepth--;if($null-ne$__shapeSpan){Stop-AiwShapeSpan $__shapeSpan}}'
    }elseif($name-cin$timed){$start+='$__shapeSpan=Start-AiwShapeSpan '''+$name+''';try{';$finish='}finally{Stop-AiwShapeSpan $__shapeSpan}'}
    $text=$text.Substring(0,$at)+$start+$text.Substring($at)+$finish
    $tokens=$null;$errors=$null;$parsed=[Management.Automation.Language.Parser]::ParseInput($text,$modulePath,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('SHAPE_REWRITE_AST|'+$key+'|'+($errors.Message-join';'))}
    & $Module {param($n,$sb) Set-Item ('Function:script:'+$n) ($ExecutionContext.SessionState.Module.NewBoundScriptBlock($sb))} $name $parsed.GetScriptBlock()
    $global:AiwShape.bindings.Add([ordered]@{module=$modulePath;function=$name;sourceIdentity=(Get-Identity $modulePath);originalBodySha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($function.Body.Extent.Text)));executedBodySha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)));methodReplacements=@($edits|Where-Object length -GT 0).Count;counterInsertionPairs=(@($edits|Where-Object length -EQ 0).Count/2)})
  }
  & $Module {param($names) Export-ModuleMember -Function $names} $exports
}
function Invoke-ShapeObservationWorker($Request){
  Initialize-ShapeObservation $Request
  $s=$global:AiwShape;foreach($key in @('ordinary-json-pipeline','strict-json-native-parse','utf8-get-string','physical-graph-cache-hit','borrowed-scope','content-sha256-input-bytes','content-canonical-top')){$s.counts[$key]=0L}
  $v=Join-Path $Request.frameworkRoot 'framework/versions/2.0.0'
  Write-AiwTestPhase $Request.phasePath 'shape-worker' 'shape' 'import' START @{pid=$PID}
  $boundary=@(Import-Module (Join-Path $v 'scripts/ProcessRequirementBoundary.psm1') -PassThru)[0]
  $modules=@(& $boundary {param($v) foreach($name in @('ProcessRequirementComposition','ContentSources','ReleaseValidation','StrictJsonInput','ObjectFormats','ResultEvidence','WorkflowDelivery','ControlTransition')){Import-Module (Join-Path $v ('scripts/'+$name+'.psm1'))};$directory=[IO.Path]::GetFullPath((Join-Path $v 'scripts'));Get-Module -All|Where-Object{$_.Path-and[IO.Path]::GetDirectoryName($_.Path).Equals($directory,[StringComparison]::OrdinalIgnoreCase)}} $v)
  $instances=[Collections.Generic.List[object]]::new()
  foreach($candidate in @($modules+$boundary)){if(-not@($instances|Where-Object{[object]::ReferenceEquals($_,$candidate)}).Count){$instances.Add($candidate)}}
  $modules=$instances.ToArray()
  $imports=@{};foreach($module in $modules){$imports[$module.Path]=@(& $module {param($own) Get-Command -ListImported -CommandType Function|Where-Object{$_.Module-and$_.Module.Path-cne$own}|ForEach-Object{$_.Module.Path}|Sort-Object -Unique} $module.Path)}
  foreach($module in $modules){Add-ShapeModuleObservation $module}
  foreach($module in $modules){foreach($dependency in $imports[$module.Path]){& $module {param($p) Import-Module $p} $dependency}}
  Write-AiwTestPhase $Request.phasePath 'shape-worker' 'shape' 'import' END @{pid=$PID;modules=$modules.Count;functions=$s.bindings.Count}
  $process=[Diagnostics.Process]::GetCurrentProcess();$beforeCpu=$process.TotalProcessorTime.TotalMilliseconds;$watch=[Diagnostics.Stopwatch]::StartNew();$sut='UNKNOWN';$nativeCode=$null;$responseRef='NOT_OBSERVED';$actionError=$null
  try{
    $rootSpan=Start-AiwShapeSpan 'BOUNDARY'
    try{$values=@(& $boundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $Request.inputPath -AsJson)}finally{Stop-AiwShapeSpan $rootSpan}
    if($values.Count-ne1){throw 'SHAPE_BOUNDARY_SINGLE_RESULT'};$value=$values[0];$nativeCode=$value.exitCode
    $wireText=$value.output-join[char]10;Write-Utf8 $Request.responsePath $wireText;$responseRef=@{path=$Request.responsePath;identity=(Get-Identity $Request.responsePath)}
    $decode=Start-AiwShapeSpan 'response-json-decode';try{$wire=$wireText|ConvertFrom-Json -Depth 100}finally{Stop-AiwShapeSpan $decode};$sut=$wire.status
    if($nativeCode-ne0-or$sut-cne'PASS'){throw ('SHAPE_SUT_BOUNDARY|'+$nativeCode+'|'+$sut)}
  }catch{$actionError=$_.Exception.Message}
  $watch.Stop();$process.Refresh()
  if($s.handles.Count-or$s.stack.Count-or$s.canonicalDepth){$s.errors.Add('INSTRUMENTATION_RESOURCE_OR_STACK_INCOMPLETE')}
  $required=@('ProcessRequirementComposition.psm1/Get-AiwProjectStandardsSnapshot','ProcessRequirementComposition.psm1/Test-AiwEffectiveRuleSet','ContentSources.psm1/Invoke-CsOwnedStandardsBatch','ContentSources.psm1/New-CsOwnedContext','ContentSources.psm1/New-CsOwnedGraph','ContentSources.psm1/Read-CsOwnedGraph','ContentSources.psm1/Read-CsOwnedExact','ContentSources.psm1/Read-CsResolvedExact','ContentSources.psm1/Convert-CsObservedText','ContentSources.psm1/Get-CsReadUnitFromText','ProjectSourcePublication.psm1/Enter-AiwProjectSourceScope','ProjectSourcePublication.psm1/Exit-AiwProjectSourceScope')
  if($Request.mode-ceq'FINALIZE_OUTPUT'){$required+='ProcessRequirementComposition.psm1/Get-AiwProcessBindingSnapshot'}
  foreach($key in $required){if(-not$s.counts.ContainsKey($key)-or$s.counts[$key]-le0){$s.errors.Add('UNREACHED_REWRITTEN_FUNCTION|'+$key)}}
  foreach($key in @('ordinary-json-pipeline','strict-json-native-parse','utf8-get-string','content-canonical-top')){if($s.counts[$key]-le0){$s.errors.Add('UNREACHED_METRIC|'+$key)}}
  $exclusive=$false
  try{$probe=[IO.File]::Open((Join-Path $Request.projectRoot '.ai-workspace/runtime/source-publication.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{$exclusive=$true}finally{$probe.Dispose()}}catch{$s.errors.Add('POST_BOUNDARY_EXCLUSIVE_OPEN_FAILED|'+$_.Exception.Message)}
  $result=[ordered]@{schemaVersion=1;kind='PRIVATE_INSTRUMENTED';mode=$Request.mode;pid=$PID;sutStatus=$sut;sutExitCode=$nativeCode;actionError=$actionError;measurementStatus=$(if($actionError-or$s.errors.Count){'INVALID'}else{'PASS'});responseRef=$responseRef;actionWallMilliseconds=$watch.Elapsed.TotalMilliseconds;actionCpuMilliseconds=($process.TotalProcessorTime.TotalMilliseconds-$beforeCpu);workingSetBytes=$process.WorkingSet64;privateBytes=$process.PrivateMemorySize64;workerPeakWorkingSetThroughActionBytes=$process.PeakWorkingSet64;workerPeakPagedThroughActionBytes=$process.PeakPagedMemorySize64;counts=$s.counts;physicalReads=@($s.reads.Values);stages=$s.events.ToArray();locks=$s.locks.ToArray();bindings=$s.bindings.ToArray();instrumentationErrors=$s.errors.ToArray();postBoundaryExclusiveOpen=$exclusive;fixedAdoptedQualification='NOT_EXERCISED';metricLimits=@('Exclusive wall subtracts the union of direct synchronous observed child intervals only; it is not all-function self time.','Stage memory is entry/exit working-set/private bytes, not allocation or a sampled stage peak. Worker peaks are observed at action completion and include import/instrumentation, excluding later metrics serialization/drain. GC collection counts are process-wide entrance/exit observations.','Physical bytes count successful actual ReadAllBytes returns; ReadAllText bytes are not observed. Embedded C# parsing and unrewritten modules are outside call-site counters. Canonical recursive count is actual ContentSources function entries; canonical output-byte allocation is NOT_OBSERVED.','This native worker calls the original boundary API with rewritten private functions, so it is distinct from the plain resolver CLI. No source/view bytes, validation, borrowing semantics or lock scope are changed.')}
  Write-Utf8 $Request.metricsPath ($result|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii)
  [ordered]@{measurementStatus=$result.measurementStatus;sutStatus=$sut;metricsPath=$Request.metricsPath;responseRef=$responseRef}|ConvertTo-Json -Depth 10 -Compress -EscapeHandling EscapeNonAscii
}
function New-ShapeObservationFixture([string]$Root,[switch]$Large){
  $id='measure-shape';$project=Join-Path $Root 'project';$supply=Join-Path $Root 'supply';$config=NewTestProject $project $id
  $sizes=if($Large){@(1,1,1,1,5,6,6,7,8,9,11,12,13,13,14,14,14,15,17,18,18,20,20,20,21,22,24,25,26,28,31,33,45)}else{@(3,3,1)}
  $unitCount=if($Large){178}else{5};$fileCount=if($Large){22}else{1};$units=@{};$texts=@{}
  foreach($index in 0..($fileCount-1)){$texts[$index]=[Text.StringBuilder]::new()}
  foreach($index in 0..($unitCount-1)){
    $name=if($Large){'U'+$index.ToString('D3')}else{@('C','D','A','B','Z')[$index]};$file=$index%$fileCount;$start='<'+$name+'>';$end='</'+$name+'>';$body='Anonymous complete requirement '+$name+'.'
    $null=$texts[$file].Append($start+"`n"+$body+"`n"+$end+"`n")
    $units[$name]=@{file=('source-'+$file.ToString('D2')+'.md');start=$start;end=$end;body=$body}
  }
  foreach($index in 0..($fileCount-1)){WriteText (Join-Path $supply ('source-'+$index.ToString('D2')+'.md')) $texts[$index].ToString()}
  $config.sourceBindings=@([pscustomobject]@{id='units';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$supply};allowedPaths=@(0..($fileCount-1)|ForEach-Object{[pscustomobject]@{kind='FILE';locator=('source-'+$_.ToString('D2')+'.md')}});decisionLocator='fixture:explicit-anonymous-source'})
  $rules=@();$cursor=0
  foreach($index in 0..($sizes.Count-1)){
    $ruleId='RULE'+$index.ToString('D2')
    if($Large){$leafCount=$sizes[$index]-1;$order=@();for($j=0;$j-lt$leafCount;$j++){$order+=('U'+(33+(($cursor+$j)%145)).ToString('D3'))};$cursor+=$leafCount;$rootId='U'+$index.ToString('D3');$order+=@($rootId)}else{$order=@(@('C','D','A'),@('D','C','B'),@('Z'))[$index];$rootId=$order[-1]}
    $documents=@();foreach($node in $order){$unit=$units[$node];$dependencies=if($node-ceq$rootId){@($order|Where-Object{$_-cne$rootId})}else{@()};$doc=[pscustomobject]@{sourceId=$node;bindingId='units';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=$unit.file;mode='MARKED_SECTION';sectionStart=$unit.start;sectionEnd=$unit.end;dependencies=@($dependencies);identity=(Get-Identity (Join-Path $supply $unit.file))};$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $config.sourceBindings;$documents+=@($doc)}
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='units';itemId=$ruleId;revision=(Get-AiwContentRevision ([pscustomobject]@{documents=$documents}) $config.sourceBindings);itemIdentity='';rootSourceId=$rootId;documents=$documents};$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    $rules+=@([pscustomobject]@{ruleId=$ruleId;requirementReason='Anonymous shared graph';source=$descriptor;selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@('NONE');resultKinds=@('PLAN');pathPrefixes=@();capabilities=@();semanticTerms=@();facets=[pscustomobject]@{stage=@($(if(-not$Large-and$index-lt2){'aiw:planning'}else{'aiw:review'}))}};preparationRequirements=@('P_'+$ruleId);resultRequirements=@('R_'+$ruleId);decisionLocator='fixture:explicit-anonymous-adoption'})
  }
  $policy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId=$id;rules=$rules}
  if($Large){$base=[Text.Encoding]::UTF8.GetByteCount(($policy|ConvertTo-Json -Depth 100 -Compress)+"`n");if($base-lt436981){$rules[0].requirementReason+=('x'*(436981-$base))}}
  Store (Join-Path $project '.ai-workspace/project.json') $config;Store (Join-Path $project '.ai-workspace/process-policy.json') $policy
  WriteText (Join-Path $project '.ai-workspace/BOOTSTRAP.md') (@('<!-- FRAMEWORK-MANAGED:BEGIN -->','Fixture entry.','<!-- FRAMEWORK-MANAGED:END -->','<!-- PROJECT-CUSTOM:BEGIN -->','<!-- PROJECT-CUSTOM:END -->','')-join[char]10)
  $sourceRows=@($units.Values|ForEach-Object{$_.file}|Sort-Object -Unique|ForEach-Object{@{path=$_;identity=(Get-Identity (Join-Path $supply $_))}})
  return [ordered]@{project=$project;supply=$supply;projectId=$id;rules=$rules.Count;relations=($sizes|Measure-Object -Sum).Sum;syntheticUniqueUnits=$unitCount;physicalPaths=$fileCount;graphSizes=$sizes;policyIdentity=(Get-Identity (Join-Path $project '.ai-workspace/process-policy.json'));configIdentity=(Get-Identity (Join-Path $project '.ai-workspace/project.json'));sourceFiles=$sourceRows;scope='PRIVATE_SYNTHETIC_PARTIAL';expectedSelectedProjectRules=$(if($Large){0}else{2})}
}
function Invoke-ShapeNative([string[]]$Arguments,[string]$Token,[string]$OutRoot){
  $remaining=$script:ShapeBudgetMilliseconds-$script:ShapeClock.Elapsed.TotalMilliseconds
  if($remaining-le0){throw 'SHAPE_CUMULATIVE_BUDGET_EXHAUSTED'}
  $cap=[math]::Min(600000,$remaining);$handle=Start-AiwTestProcess ([Environment]::ProcessPath) $Arguments -WorkingDirectory $OutRoot -EvidenceDirectory (Join-Path $OutRoot 'raw') -GroupId $Token -EvidenceContractVersion 2
  Write-AiwTestPhase (Join-Path $OutRoot 'profile-phases.jsonl') 'shape-profile' $Token 'native' START @{pid=$handle.Process.Id;runId=$handle.RunId;rawDirectory=$handle.Directory;stopCapMilliseconds=$cap}
  do{$left=$cap-$handle.Timer.Elapsed.TotalMilliseconds;if($left-le0){Stop-AiwTestProcess $handle $handle.RunId 'EP145 native600s or remaining cumulative45m stop cap';$run=Wait-AiwTestProcess $handle -WaitMilliseconds 30000;throw ('SHAPE_NATIVE_STOPPED|'+$run.ResultPath)};$run=Wait-AiwTestProcess $handle -WaitMilliseconds ([int][math]::Min(1000,[math]::Max(1,$left)))}while($run.Status-ceq'RUNNING')
  Write-AiwTestPhase (Join-Path $OutRoot 'profile-phases.jsonl') 'shape-profile' $Token 'native' END @{pid=$run.Record.pid;resultPath=$run.ResultPath;exitCode=$run.Code}
  if($run.Code-ne0){throw ('SHAPE_NATIVE_FAILED|'+$run.ResultPath)}
  return $run
}
function Invoke-ShapeObservation {
  if($FixtureContractOnly-or-not$ObservationOutputDirectory-or$BeforeSourceRoot-or$CompletionFixturePath-or$CompletionProcessResultPath){throw 'SHAPE_ARGUMENTS'}
  $comparison=$SourceObservationProfile-ceq'SharedPerformance'
  if($comparison-and-not$ObservationResumeDirectory){throw 'SHAPE_COMPARISON_BASELINE_REQUIRED'}
  $outRoot=Assert-AiwTestPath $ObservationOutputDirectory;if(Test-Path -LiteralPath $outRoot){throw 'SHAPE_FRESH_OUTPUT_REQUIRED'};$null=[IO.Directory]::CreateDirectory($outRoot)
  # Prior top-level harness records are supplied by the test owner as immutable
  # native evidence, not by a second budget ledger. Parent and child are not added.
  $used=0.0
  if($env:AIW_SHAPE_PRIOR_NATIVE_RESULTS){foreach($path in @($env:AIW_SHAPE_PRIOR_NATIVE_RESULTS-split[IO.Path]::PathSeparator)){if(-not$path){continue};$record=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 100;if($record.command.arguments-cnotcontains'-SourceObservationProfile'-or($record.command.arguments-cnotcontains'MediaShape'-and$record.command.arguments-cnotcontains'SharedPerformance')){throw 'SHAPE_PRIOR_NATIVE_RECORD_MISMATCH'};$used+=[double]$record.timing.wallMilliseconds}}
  $script:ShapeBudgetMilliseconds=2700000-$used;if($script:ShapeBudgetMilliseconds-le0){throw 'SHAPE_CUMULATIVE_BUDGET_EXHAUSTED'};$script:ShapeClock=[Diagnostics.Stopwatch]::StartNew()
  $definition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
  $source=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
  if($ObservationResumeDirectory){
    $resume=Assert-AiwTestPath $ObservationResumeDirectory;$priorBaseline=Get-Content -LiteralPath (Join-Path $resume 'baseline.json') -Raw|ConvertFrom-Json -Depth 100;$runtime=Assert-AiwTestPath $priorBaseline.runtimeRoot
    $runtimeManifest=Join-Path $runtime 'framework/versions/2.0.0/RELEASE_MANIFEST.json';if((Get-Identity $runtimeManifest)-cne$priorBaseline.runtimeManifestIdentity){throw 'SHAPE_RETAINED_B0_MANIFEST_DRIFT'}
    # A mechanism fixture is a declared finite subset, so the full SourceView
    # payload reader is inapplicable. Recheck every actual fixture byte with the
    # existing snapshot helper and the original fixture constructor algorithm.
    $snapshot=Get-AiwTestFixtureSnapshot (Split-Path $runtimeManifest) -IdentityOnly
    [string[]]$rows=@();[long]$totalBytes=0
    foreach($file in $snapshot.Files){if($file.path-ceq'RELEASE_MANIFEST.json'){continue};$rows+=($file.path+'|'+$file.identity);$totalBytes+=[long]$file.identity.Split('|')[0]};[Array]::Sort($rows,[StringComparer]::Ordinal)
    $facts=[pscustomobject]@{Canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($rows-join"`n")));FileCount=$rows.Count;TotalBytes=$totalBytes};$manifest=Get-Content -LiteralPath $runtimeManifest -Raw|ConvertFrom-Json -Depth 100
    if($facts.Canonical-cne$manifest.canonical-or$facts.FileCount-ne$manifest.fileCount-or$facts.TotalBytes-ne$manifest.totalBytes){throw 'SHAPE_RETAINED_B0_BYTES_DRIFT'}
  }else{$runtime=Join-Path $outRoot 'runtime-b0';$null=New-AiwTestRuntimeFixture $source $runtime $definition.mechanismVersionPaths}
  if($comparison){$comparisonRuntime=$runtime;$runtime=Join-Path $outRoot 'runtime-b1';$null=New-AiwTestRuntimeFixture $source $runtime $definition.mechanismVersionPaths}
  . (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly
  $baseline=@{sourceRoot=$source;sourceManifestIdentity=(Get-Identity (Join-Path $versionRoot 'RELEASE_MANIFEST.json'));runtimeRoot=$runtime;runtimeManifestIdentity=(Get-Identity (Join-Path $runtime 'framework/versions/2.0.0/RELEASE_MANIFEST.json'));qualification='PRIVATE_SYNTHETIC_PARTIAL';sourceInputsRef=$(if(Test-Path -LiteralPath (Join-Path $source 'source-inputs.json')){@{path=(Join-Path $source 'source-inputs.json');identity=(Get-Identity (Join-Path $source 'source-inputs.json'))}}else{'NOT_AVAILABLE'})}
  if($ObservationResumeDirectory){$baseline.retainedOriginalBaselineRef=@{path=(Join-Path $resume 'baseline.json');identity=(Get-Identity (Join-Path $resume 'baseline.json'))};$baseline.sourceRootMeaning='Current diagnostic entry source view; retained runtime B0 remains the original frozen SUT, whose complete current payload bytes were rechecked. No valid original plain L0 boundary is rerun.'}
  if($comparison){$baseline.variant='B1';$baseline.comparisonB0Runtime=$comparisonRuntime;$baseline.sourceRootMeaning='Current B1 diagnostic source/view and fresh synthetic mechanism runtime. B0 is retained separately and verified without modification. The same original L1 project/config/policy/source files are reused; implementation/framework-root differences are explicit.'}
  Store (Join-Path $outRoot 'baseline.json') $baseline
  $samples=[Collections.Generic.List[object]]::new();$fixtures=[Collections.Generic.List[object]]::new()
  foreach($shape in $(if($comparison){@('L1')}else{@('L0','L1')})){
    if($comparison-or($ObservationResumeDirectory-and$shape-ceq'L0')){
      $fixture=Get-Content -LiteralPath (Join-Path $resume ($shape+'-fixture.json')) -Raw|ConvertFrom-Json -Depth 100
      if((Get-Identity (Join-Path $fixture.project '.ai-workspace/project.json'))-cne$fixture.configIdentity-or(Get-Identity (Join-Path $fixture.project '.ai-workspace/process-policy.json'))-cne$fixture.policyIdentity){throw 'SHAPE_RETAINED_L0_AUTHORITY_DRIFT'}
      foreach($file in $fixture.sourceFiles){if((Get-Identity (Join-Path $fixture.supply $file.path))-cne$file.identity){throw 'SHAPE_RETAINED_L0_SOURCE_DRIFT'}}
    }else{$fixture=New-ShapeObservationFixture (Join-Path $outRoot $shape) -Large:($shape-ceq'L1')}
    $fixtures.Add($fixture);Store (Join-Path $outRoot ($shape+'-fixture.json')) $fixture
    $facet=[ordered]@{};foreach($axis in @('domain','workType','deliverableType','stage')){$facet[$axis]=@{state='KNOWN';values=@($(switch($axis){domain{'aiw:governance'}workType{'aiw:planning'}deliverableType{'aiw:plan'}stage{'aiw:planning'}}))}}
    $discover=[ordered]@{schemaVersion=5;ruleLoad=@{mode='FULL'};mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=@{sessionId='shape-observer';requestId='shape-source';role='EXECUTOR';phase='PLAN';profile='STANDARD'};projectRoot=$fixture.project;frameworkRoot=$runtime;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=$fixture.configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $fixture.project '.ai-workspace/corrections.json'));expectedTaskIdentity='NOT_APPLICABLE';observedActor='shape-observer';capabilities=@();exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=@{schemaVersion=2;objective='Observe complete anonymous shared source graphs and actual boundary validation.';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=$facet};evaluationOnly=$false}
    foreach($variant in $(if($InstrumentSourceObservation){@('plain','instrumented')}else{@('plain')})){
      if(-not$comparison-and$ObservationResumeDirectory-and$shape-ceq'L0'-and$variant-ceq'plain'){
        foreach($oldMode in @('discover','finalize_output')){
          $oldInput=Join-Path $resume ($(if($oldMode-ceq'discover'){'L0-plain-discover-input.json'}else{'L0-plain-finalize-input.json'}));$oldResponse=Join-Path $resume ('L0-plain-'+$oldMode+'-response.json');$oldWire=Get-Content -LiteralPath $oldResponse -Raw|ConvertFrom-Json -Depth 100
          $matches=@(Get-ChildItem -LiteralPath (Join-Path $resume 'raw') -Filter result.json -File -Recurse|ForEach-Object{$n=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json -Depth 100;if($n.command.arguments-ccontains$oldInput){@{path=$_.FullName;record=$n}}})
          if($matches.Count-ne1-or$matches[0].record.exitCode-ne0-or$oldWire.status-cne'PASS'){throw 'SHAPE_RETAINED_L0_NATIVE_INVALID'};$n=$matches[0].record
          foreach($raw in @($n.stdout,$n.stderr)){if((Get-Identity $raw.path)-cne$raw.identity){throw 'SHAPE_RETAINED_L0_RAW_DRIFT'}}
          if((([IO.File]::ReadAllText($n.stdout.path)|ConvertFrom-Json -Depth 100)|ConvertTo-Json -Depth 100 -Compress)-cne($oldWire|ConvertTo-Json -Depth 100 -Compress)){throw 'SHAPE_RETAINED_L0_FULL_RESPONSE_DRIFT'}
          $samples.Add(@{shape='L0';variant='plain';mode=$oldMode.ToUpperInvariant();reusedOriginal=$true;inputRef=@{path=$oldInput;identity=(Get-Identity $oldInput)};responseRef=@{path=$oldResponse;identity=(Get-Identity $oldResponse)};nativeResultRef=@{path=$matches[0].path;identity=(Get-Identity $matches[0].path)};metricsRef='NOT_APPLICABLE';nativeWallMilliseconds=$n.timing.wallMilliseconds;nativeCpuMilliseconds=$n.timing.cpuMilliseconds;processExited=$true})
          if($oldMode-ceq'discover'){$logic=@{selected=@($oldWire.selectedRuleBlocks|ForEach-Object requirementId);obligations=$oldWire.compactReceipt.selectedObligations}|ConvertTo-Json -Depth 100 -Compress;Write-Utf8 (Join-Path $outRoot 'L0-plain-logical.json') $logic}
        }
        continue
      }
      $token=$shape+'-'+$variant;$inputPath=Join-Path $outRoot ($token+'-discover-input.json');Store $inputPath $discover
      $compactPath=Join-Path $outRoot ($token+'-compact.json');$plainLogic=$null
      foreach($mode in @('DISCOVER','FINALIZE_OUTPUT')){
        $tag=$token+'-'+$mode.ToLowerInvariant();$responsePath=Join-Path $outRoot ($tag+'-response.json')
        if($variant-ceq'plain'){
          $cli=Join-Path $runtime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'
          $run=Invoke-ShapeNative @('-NoLogo','-NoProfile','-NonInteractive','-File',$cli,'-InputPath',$inputPath,'-AsJson') $tag $outRoot
          Write-Utf8 $responsePath $run.StdoutText;$wire=$run.StdoutText.Trim()|ConvertFrom-Json -Depth 100;$metricsRef='NOT_APPLICABLE'
        }else{
          $workerPath=Join-Path $outRoot ($tag+'-worker.json');$metricsPath=Join-Path $outRoot ($tag+'-metrics.json')
          Store $workerPath @{kind='MEDIA_SHAPE';frameworkRoot=$runtime;projectRoot=$fixture.project;supplyRoot=$fixture.supply;inputPath=$inputPath;responsePath=$responsePath;mode=$mode;metricsPath=$metricsPath;phasePath=(Join-Path $outRoot ($tag+'-phases.jsonl'))}
          $run=Invoke-ShapeNative @('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-ObservationWorkerInput',$workerPath) $tag $outRoot
          $worker=$run.StdoutText.Trim()|ConvertFrom-Json -Depth 100;$wire=Get-Content -LiteralPath $responsePath -Raw|ConvertFrom-Json -Depth 100;$metricsRef=@{path=$metricsPath;identity=(Get-Identity $metricsPath)}
          if($worker.measurementStatus-cne'PASS'){throw ('SHAPE_MEASUREMENT_INVALID_SUT_'+$worker.sutStatus+'|'+$metricsPath)}
        }
        if($wire.status-cne'PASS'){throw ('SHAPE_SUT_STATUS|'+$tag+'|'+$wire.status)}
        $probe=[IO.File]::Open((Join-Path $fixture.project '.ai-workspace/runtime/source-publication.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$probe.Dispose()
        $samples.Add(@{shape=$shape;variant=$variant;mode=$mode;inputRef=@{path=$inputPath;identity=(Get-Identity $inputPath)};responseRef=@{path=$responsePath;identity=(Get-Identity $responsePath)};nativeResultRef=@{path=$run.ResultPath;identity=(Get-Identity $run.ResultPath)};metricsRef=$metricsRef;nativeWallMilliseconds=$run.Record.timing.wallMilliseconds;nativeCpuMilliseconds=$run.Record.timing.cpuMilliseconds;processExited=$true;postProcessExclusiveOpen=$true})
        if($mode-ceq'DISCOVER'){
          $projectBlocks=@($wire.selectedRuleBlocks|Where-Object requirementId -CLike 'project:measure-shape:*')
          if($projectBlocks.Count-ne$fixture.expectedSelectedProjectRules){throw ('SHAPE_SELECTION_MISMATCH|'+$tag)}
          if($shape-ceq'L0'-and(@($wire.readTrace|Where-Object event -CEQ SOURCE_BODY_READ|ForEach-Object sourceId)-join',')-cne'C,D,A,D,C,B,Z'){throw 'SHAPE_L0_FULL_ORDER'}
          $logic=@{selected=@($wire.selectedRuleBlocks|ForEach-Object requirementId);obligations=$wire.compactReceipt.selectedObligations}|ConvertTo-Json -Depth 100 -Compress
          $logicPath=Join-Path $outRoot ($shape+'-plain-logical.json');if($variant-ceq'plain'){Write-Utf8 $logicPath $logic}elseif([IO.File]::ReadAllText($logicPath).Trim()-cne$logic){throw 'SHAPE_INSTRUMENTED_LOGICAL_DRIFT'}
          Store $compactPath $wire.compactReceipt
          $final=@{schemaVersion=3;mode='FINALIZE_OUTPUT';discoverReceiptPath=$compactPath;expectedDiscoverReceiptIdentity=(Get-Identity $compactPath);preparationReceipts=@($wire.compactReceipt.selectedObligations|ForEach-Object preparationRequirements|Sort-Object -Unique);resultReceipts=@($wire.compactReceipt.selectedObligations|ForEach-Object resultRequirements|Sort-Object -Unique);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
          $inputPath=Join-Path $outRoot ($token+'-finalize-input.json');Store $inputPath $final
        }
      }
    }
  }
  $report=@{schemaVersion=1;kind='ANONYMOUS_SOURCE_PROFILE';variant=$(if($comparison){'B1'}else{'CURRENT'});status='PASS';baseline=$baseline;fixtures=$fixtures.ToArray();samples=$samples.ToArray();priorTopLevelNativeWallMilliseconds=$used;currentProfileWallMilliseconds=$script:ShapeClock.Elapsed.TotalMilliseconds;nativeStopCapMilliseconds=600000;cumulativeStopCapMilliseconds=2700000;healthySameProcess='NOT_MEASURED';fixedAdoptedQualification='NOT_EXERCISED';realConsumerEffect='NOT_MEASURED';limits=@('One cold plain pair by default; instrumentation is a separate explicit diagnostic after an observed hotspot. No p95, SLA, model latency or production improvement claim.','L1 uses 178 synthetic units,33 rules,519 relations,22 source paths. These are chosen anonymous structural values, not a reconstruction of any consumer project.','L0 preserves three rules,seven ordered source relations,one physical source file and two selected project rules. L1 selects zero project rules; daily validation proves global declarations and the selected closure, without a full unselected-body health claim.','All raw, source fixture and runtime evidence is retained; parent native record measures the diagnostic budget without adding its children.')}
  Store (Join-Path $outRoot 'shape-observation-results.json') $report
  @{status='PASS';reportPath=(Join-Path $outRoot 'shape-observation-results.json')}|ConvertTo-Json -Compress
}
if($ObservationWorkerInput){Invoke-ObservationWorker;return}
if($ObservationResumeDirectory-and$SourceObservationProfile-cnotin@('MediaShape','SharedPerformance')){throw 'SHAPE_RESUME_PROFILE_REQUIRED'}
if($SourceObservationProfile-cin@('MediaShape','SharedPerformance')){if(-not$SourceObservation){throw 'SHAPE_SOURCE_OBSERVATION_REQUIRED'};Invoke-ShapeObservation;return}
if($SourceObservation){Invoke-SourceObservation;return}

try{
  New-Item -ItemType Directory -Path $temp -Force|Out-Null
  $frameworkRoot=Join-Path $temp 'framework-workspace'
  $sourceRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
  $definition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
  $sealedRoot=New-AiwTestRuntimeFixture $sourceRoot $frameworkRoot $definition.mechanismVersionPaths
  $resolver=Join-Path $sealedRoot 'scripts\resolve-process-requirements.ps1'
  Import-Module (Join-Path $sealedRoot 'scripts/ProcessRequirementDisplay.psm1') -Force
  $results=@()
  foreach($fixture in @($fixtureContract.fixtures)){
    $expectedFixtureIdentity=Get-FixtureIdentity $fixture;if([string]$fixture.fixtureIdentity-cne$expectedFixtureIdentity){throw ('FIXTURE_IDENTITY_DRIFT|'+[string]$fixture.fixtureId)}
    $projectRoot=Join-Path $temp ('project-'+[string]$fixture.fixtureId);New-Item -ItemType Directory -Path (Join-Path $projectRoot '.ai-workspace\tasks\active'),(Join-Path $projectRoot 'src'),(Join-Path $projectRoot 'tests'),(Join-Path $projectRoot 'docs') -Force|Out-Null
    & git -C $projectRoot init -q;if($LASTEXITCODE-ne0){throw 'MEASUREMENT_GIT_INIT'}
    $fixtureCapabilities=[ordered]@{};$fixtureBindings=@();if(@($fixture.capabilities)-contains'KNOWLEDGE_REFERENCE'){$fixtureBindings=@([pscustomobject]@{id='project-knowledge';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator='.ai-workspace/knowledge'});decisionLocator='fixture:explicit-knowledge-scope'});$fixtureCapabilities['KNOWLEDGE_REFERENCE']=[ordered]@{enabled=$true;sources=@([pscustomobject]@{id='project';bindingId='project-knowledge';indexLocator='.ai-workspace/knowledge/index.json';selectionHints=@();updatePolicy='FOLLOW';revisionSelector='.ai-workspace/knowledge/index.json'})}}
    $project=[ordered]@{schemaVersion=7;id=('measure-'+([string]$fixture.fixtureId).Replace('_','-'));displayName='Measurement Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=$fixtureCapabilities;sourceBindings=$fixtureBindings;processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}
    $projectPath=Join-Path $projectRoot '.ai-workspace\project.json';Write-Utf8 $projectPath ($project|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\controller.json') (([ordered]@{schemaVersion=1;projectId=$project.id;controllerId='fixture-controller';controllerEpoch=1;state='CURRENT'})|ConvertTo-Json -Depth 10)
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\corrections.json') (([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId=$project.id;corrections=@()})|ConvertTo-Json -Depth 20)
    $fixturePackCeiling=if([string]$fixture.fixtureId-ceq'worst_unknown'){98304}else{32768}
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\process-policy.json') (([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId=$project.id;rules=@()})|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nNo permanent project rule.`n<!-- PROJECT-CUSTOM:END -->`n"
    foreach($relative in @($fixture.exactPaths)){Write-Utf8 (Join-Path $projectRoot $relative) ("fixture object "+$relative+"`n")}
    $taskId=('MEASURE-'+([string]$fixture.fixtureId).ToUpperInvariant().Replace('_','-'))
    $taskOwner=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'fixture-owner'}else{[string]$fixture.actor}
    $taskPath=Join-Path $projectRoot ('.ai-workspace\tasks\active\'+$taskId+'.md')
    $taskActor=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'fixture-writer'}else{[string]$fixture.actor}
    $taskRole=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'EXECUTOR'}else{[string]$fixture.role};$taskPhase=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'VERIFY'}else{[string]$fixture.phase}
    Write-Utf8 $taskPath ("# "+$taskId+" - measurement fixture`n`n- Task schema: 2.0.0`n- Owner: "+$taskOwner+"`n- Work route: actor="+$taskActor+"; role="+$taskRole+"; phase="+$taskPhase+"`n- Range summary: profile="+[string]$fixture.profile+"; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n")
    $authorizationPath='NOT_REQUIRED';$authorizationIdentity='NOT_REQUIRED';$userDecision='NOT_REQUIRED'
    if([string]$fixture.actionKind-cne'NONE'){
      $userDecision=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'NOT_REQUIRED'}else{'USER_MEASUREMENT_BOUNDARY_APPROVED'};$authorizationPath=Join-Path $projectRoot '.ai-workspace\measure-authorization.json'
      $objectIdentities=@($fixture.exactPaths|ForEach-Object{[ordered]@{path=[string]$_;identity=Get-Identity (Join-Path $projectRoot ([string]$_))}})
      $issuerRole=if([string]$fixture.role-ceq'CONTROLLER'){'PROJECT_CONTROLLER'}else{'TASK_OWNER'}
      $issuer=if($issuerRole-ceq'PROJECT_CONTROLLER'){'fixture-controller'}else{$taskOwner}
      $decisionClass=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'ROUTINE_LOCAL'}elseif([string]$fixture.actionKind-ceq'EXTERNAL'){'EXTERNAL_ACTION'}else{'PRODUCT_RESULT'}
      $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId=$taskId;taskIdentity=(Get-Identity $taskPath);profile=[string]$fixture.profile;lifecycle='ACTIVE';owner=$taskOwner;issuer=$issuer;issuerRole=$issuerRole;grantee=[string]$fixture.actor;bundle='MEASUREMENT_LOCAL';decisionClass=$decisionClass;userConfirmation=$userDecision;reviewIndependence=$(if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'INDEPENDENT'}else{'NOT_APPLICABLE'});delegatedGitCloser=$false;actions=@([string]$fixture.actionKind);exactPaths=@($fixture.exactPaths);objectIdentities=$objectIdentities;projectConfigIdentity=(Get-Identity $projectPath);invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')}
      if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){$package.invalidatesOn+='CONTRIBUTOR_SET_CHANGE';$package.candidateWriter='fixture-writer';$package.materialContributors=@('fixture-designer')}
      if($issuerRole-ceq'PROJECT_CONTROLLER'){$package.issuerControllerId='fixture-controller';$package.issuerControllerEpoch=1;$package.controllerControlIdentity=Get-Identity (Join-Path $projectRoot '.ai-workspace\controller.json');$package.invalidatesOn+='CONTROLLER_EPOCH_CHANGE'}
      if([string]$fixture.actionKind-ceq'EXTERNAL'){
        $zeroEscalation=[ordered]@{paymentOrSubscription=$false;commercialLicensing=$false;accountOrCredentialChange=$false;publicPublication=$false;installation=$false;protectedOrSecretUpload=$false;crossDomain=$false;formalAssetActivation=$false;projectPhaseChange=$false;gitOrPush=$false;sharedQuotaOrResource=$false;unknownScope=$false}
        $payload=@([ordered]@{payloadKind='normalized-text';normalizedIdentity=[string]$objectIdentities[0].identity;canonicalizationVersion='UTF8_LF_V1'})
        $package.externalBinding=[ordered]@{schemaVersion=1;route='TASK_OWNER_DIRECT_DOMAIN_EXTERNAL';provider='measurement-provider';orderedOperations=@([ordered]@{operationId='OP-1';operationKind='PROVIDER_PUBLIC_METADATA_READ';declaredInputClass='ZERO_PROJECT_DATA';payloads=@()},[ordered]@{operationId='OP-2';operationKind='bounded-transform';declaredInputClass='EXACT_PAYLOADS';payloads=$payload});outputUse='project-local measurement result';totalQuantity=2;perOperationRetryCeiling=1;totalRetryCeiling=2;costClass='FREE';costCeiling=0;stopConditions=@('stop on provider error','stop on ambiguous consumption');batchExecutionMode='ONE_LOGICAL_ATOMIC_EXECUTION';reissuable=$false;ambiguousConsumptionPolicy='BLOCK';escalationFlags=$zeroEscalation}
      }
      Write-Utf8 $authorizationPath ($package|ConvertTo-Json -Depth 40);$authorizationIdentity=Get-Identity $authorizationPath
    }
    $intent=[ordered]@{schemaVersion=2;objective=[string]$fixture.objective;requestedActionKind=[string]$fixture.actionKind;requestedResultKind=[string]$fixture.resultKind;semanticHints=@($fixture.semanticHints);pathHints=@($fixture.pathHints);capabilityHints=@($fixture.capabilities);mutationHints=@($fixture.mutationHints);externalHints=@($fixture.externalHints);ambiguityState=[string]$fixture.ambiguityState;facets=$fixture.facets}
    $discover=[ordered]@{schemaVersion=5;ruleLoad=[ordered]@{mode='FULL'};mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$projectRoot;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=(Get-Identity $projectPath);expectedCorrectionsIdentity=(Get-Identity (Join-Path $projectRoot '.ai-workspace\corrections.json'));expectedTaskIdentity=(Get-Identity $taskPath);observedActor=[string]$fixture.actor;capabilities=@($fixture.capabilities);exactPaths=@($fixture.exactPaths);forbiddenPaths=@();protectedPaths=@('.ai-workspace/');authorizationPackagePath=$authorizationPath;expectedAuthorizationIdentity=$authorizationIdentity;userDecision=$userDecision;recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
    $discoverPath=Join-Path $projectRoot '.ai-workspace\measure-discover.json';Write-Utf8 $discoverPath ($discover|ConvertTo-Json -Depth 30)
    $initial=Invoke-Cold $resolver $discoverPath ([int]$fixture.expectedExitCodes.DISCOVER);$discover=$initial.Output|ConvertFrom-Json;if($discover.status-cne'PASS'){throw ('FIXTURE_PREFIX_FAILED|measurement|native='+$initial.ExitCode+'|raw='+$initial.Output)};$receipt=$discover.compactReceipt;$receiptPath=Join-Path $projectRoot '.ai-workspace\measure-receipt.json';Write-Utf8 $receiptPath ($receipt|ConvertTo-Json -Depth 50)
    $requiredPrep=@($receipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$requiredResult=@($receipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $admit=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $receiptPath);preparationReceipts=@($requiredPrep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $admitPath=Join-Path $projectRoot '.ai-workspace\measure-admit.json';Write-Utf8 $admitPath ($admit|ConvertTo-Json -Depth 30)
    $postimages=@($fixture.exactPaths|ForEach-Object{'OBJECT_POSTIMAGE|'+[string]$_+'|'+(Get-Identity (Join-Path $projectRoot ([string]$_)))});$final=$admit|ConvertTo-Json -Depth 30|ConvertFrom-Json;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@($requiredResult+$postimages)
    if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){
      # Synthetic evidence exercises the real typed consumer in this isolated
      # measurement fixture. It is never Source Review for the working tree.
      $requirements=[ordered]@{path=('.ai-workspace/tasks/active/'+$taskId+'.md');identity=(Get-Identity $taskPath)}
      $verdict=[ordered]@{schemaVersion=1;taskId=$taskId;actor=[string]$fixture.actor;candidateObjects=$objectIdentities;requirementsRef=$requirements;outcome='APPROVED';checks=@([ordered]@{id='fixture-shape';method='MODEL_JUDGMENT';outcome='PASS';reason='Synthetic measurement fixture only; no production or source review claim.';evidenceLocators=@($requirements)});evidenceLocators=@($requirements);authorizationRef=[ordered]@{path='.ai-workspace/measure-authorization.json';identity=$authorizationIdentity}}
      $verdictPath=Join-Path $projectRoot '.ai-workspace/measure-verdict.json';Write-Utf8 $verdictPath ($verdict|ConvertTo-Json -Depth 30)
      $final.evidenceRefs=@([ordered]@{path='.ai-workspace/measure-verdict.json';identity=(Get-Identity $verdictPath);kind='REVIEW_VERDICT'})
      $hostPath=Join-Path $projectRoot '.ai-workspace/measure-host-fixture.json'
      Write-Utf8 $hostPath (([ordered]@{content=@([ordered]@{type='text';text=([ordered]@{threadId=$taskOwner}|ConvertTo-Json -Compress)});isError=$false})|ConvertTo-Json -Depth 10)
      $final|Add-Member deliveryContext ([ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient=$taskOwner;observedRecipient=$taskOwner;outcome='SUCCESS';evidence=($hostPath+'#'+(Get-Identity $hostPath))})
    }elseif([string]$fixture.resultKind-ceq'USER_RESPONSE'){
      $final|Add-Member deliveryContext ([ordered]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'})
    }
    $finalPath=Join-Path $projectRoot '.ai-workspace\measure-final.json';Write-Utf8 $finalPath ($final|ConvertTo-Json -Depth 30)
    if($FixtureContractOnly){
      $admitted=Invoke-Cold $resolver $admitPath ([int]$fixture.expectedExitCodes.ADmit_ACTION)
      $closed=Invoke-Cold $resolver $finalPath ([int]$fixture.expectedExitCodes.FINALIZE_OUTPUT)
      $admittedValue=$admitted.Output|ConvertFrom-Json;$closedValue=$closed.Output|ConvertFrom-Json
      if($admittedValue.status-cne'PASS'-or$closedValue.status-cnotin@('PASS','READY_TO_SEND')){throw ('FIXTURE_PREFIX_FAILED|measurement-boundary|admit='+$admitted.Output+'|final='+$closed.Output)}
      Write-AiwTestJson (Join-Path $env:AIW_TEST_RAW_DIRECTORY 'fixture-members-measurement.json') @{kind='PRIVATE_FINITE_FIXTURE';status='PASS';declaredVersionInputs=$definition.mechanismVersionPaths;actualMembers=(Get-AiwTestFixtureSnapshot $frameworkRoot -IdentityOnly).Files;fixtureId=$fixture.fixtureId;discover=$initial;admit=$admitted;finalize=$closed;undeclaredOwnedSeedOmitted=(-not(Test-Path -LiteralPath (Join-Path $frameworkRoot 'owned-undeclared-seed.txt')))}
      Write-Output 'PARTIAL|FIXTURE_CONTRACT_ONLY|measurement|code=0|status=PASS|reason=REAL_DISCOVER_ADMIT_FINALIZE_REACHED';return
    }
    $modeResults=[ordered]@{}
    foreach($mode in @([pscustomobject]@{Name='DISCOVER';Path=$discoverPath},[pscustomobject]@{Name='ADMIT_ACTION';Path=$admitPath},[pscustomobject]@{Name='FINALIZE_OUTPUT';Path=$finalPath})){
      $expected=[int]$fixture.expectedExitCodes.($mode.Name);for($run=0;$run-lt$Warmups;$run++){$null=Invoke-Cold $resolver $mode.Path $expected};$samples=@();for($run=0;$run-lt$MeasuredRuns;$run++){$samples+=(Invoke-Cold $resolver $mode.Path $expected).Milliseconds};$modeResults[$mode.Name]=Get-Statistics $samples
    }
    $display=Get-AiwProcessDisplay $discover
    $displayBytes=$utf8.GetByteCount($display.text);$uniqueBodyBytes=0
    foreach($unit in $display.bodyUnits){$uniqueBodyBytes+=$utf8.GetByteCount($unit.fullText)}
    $results+=[ordered]@{fixtureId=[string]$fixture.fixtureId;fixtureIdentity=[string]$fixture.fixtureIdentity;selectedPackBytes=[int]$receipt.pack.bytes;selectedPackEstimatedTokens=[int]$receipt.pack.estimatedTokens;selectedRequirementCount=@($receipt.selectedObligations).Count;uniqueBodyBytes=$uniqueBodyBytes;displayBytes=$displayBytes;modes=$modeResults}
  }
  $output=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';host=([Environment]::OSVersion.VersionString+' / PowerShell '+$PSVersionTable.PSVersion+' / '+[Runtime.InteropServices.RuntimeInformation]::OSArchitecture+' / '+[Environment]::ProcessorCount+' logical processors');process='cold pwsh process';filesystem='warmed after fixture setup';warmups=$Warmups;measuredRuns=$MeasuredRuns;fixtures=$results}
  if($AsJson){$output|ConvertTo-Json -Depth 40}else{$output|ConvertTo-Json -Depth 40}
}finally{
  if(Test-Path -LiteralPath $temp){$tempItem=Get-Item -LiteralPath $temp -Force;$resolvedTemp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($tempItem.FullName));if(-not$tempItem.PSIsContainer-or($tempItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-or$resolvedTemp-cne$temp-or[IO.Path]::GetDirectoryName($resolvedTemp)-cne$tempRoot-or[IO.Path]::GetFileName($resolvedTemp)-cne$tempName-or$tempName-cnotmatch'^aiw-1\.14-process-measure-[a-f0-9]{32}$'){throw 'MEASUREMENT_TEMP_CLEANUP_SCOPE'};Get-ChildItem -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue}
}
