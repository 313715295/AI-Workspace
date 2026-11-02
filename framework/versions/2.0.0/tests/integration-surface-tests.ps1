[CmdletBinding()]
param([switch]$SkipManifest,[switch]$SkipBaseline,[switch]$ToolContractOnly,[switch]$SelectorOnly,[switch]$NativeIO)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'IntegrationFixture.psm1') -Force
$integrationContext=$null
try {
 $integrationContext=New-IntegrationContext (Join-Path $PSScriptRoot '..') 'surface'
 foreach($key in $integrationContext.Keys){if($key-ceq'script:testJunctions'){$script:testJunctions=$integrationContext[$key]}else{Set-Variable -Name $key -Value $integrationContext[$key]}}
function Test-IntegrationLoaderNativeIo {
$runtimeCandidateRoot=New-IntegrationRuntimeFixture (Join-Path $temp 'sealed-runtime')
$loader = Join-Path $runtimeCandidateRoot 'scripts\resolve-load-plan.ps1'
$normalLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX')
$maintenanceLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','CODEX','-Topology','FRAMEWORK_MAINTENANCE_SIBLING')
$fallbackLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','REVIEW_AND_EVIDENCE.md')
$unknownFallbackLoad = Invoke-Ps $loader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','README.md')
Assert-True ($normalLoad.Code -eq 0 -and $normalLoad.Text.Contains('routeSource=EXPLICIT_NO_TASK') -and $normalLoad.Text.Contains('topology=REPO_LOCAL') -and -not $normalLoad.Text.Contains('FRAMEWORK_MAINTENANCE.md')) 'loader-explicit-no-task-compatible-with-evidence-ceiling'
Assert-True ($maintenanceLoad.Code -ne 0) 'version-loader-rejects-root-owned-maintenance-topology'
Assert-True ($fallbackLoad.Code-eq0-and$fallbackLoad.Text.Contains('fallback=REVIEW_AND_EVIDENCE.md')-and$fallbackLoad.Text.Contains('AFFECTED_MODULE_FALLBACK')-and$fallbackLoad.Text.Contains('REVIEW_AND_EVIDENCE.md')-and$unknownFallbackLoad.Code-ne0-and$unknownFallbackLoad.Text.Contains('LOAD_FALLBACK_MODULE_UNKNOWN')) 'loader-bounded-affected-normative-module-fallback-only'

$candidateLoadRoot=Join-Path $temp 'candidate-runtime\2.0.0';New-Item -ItemType Directory -Path (Split-Path -Parent $candidateLoadRoot) -Force|Out-Null;Copy-Item -LiteralPath $candidateRoot -Destination $candidateLoadRoot -Recurse
$candidateLoadFacts=Approve-CandidateReleaseFixture $candidateLoadRoot
$candidateLoadProject=Join-Path $temp 'candidate-load-项目-😀';$candidateLoadControl=Join-Path $candidateLoadProject '.ai-workspace';New-Item -ItemType Directory -Path $candidateLoadControl -Force|Out-Null
$candidateLoadConfigPath=Join-Path $candidateLoadControl 'project.json';$candidateLoadConfig=[ordered]@{schemaVersion=7;id='candidate-load-fixture';displayName='Candidate Load Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}};Write-Utf8 $candidateLoadConfigPath ($candidateLoadConfig|ConvertTo-Json -Depth 20)
$candidateLoadBootstrapPath=Join-Path $candidateLoadControl 'BOOTSTRAP.md';$candidateLoadBootstrap="<!-- FRAMEWORK-MANAGED:BEGIN -->`nProject ID=``candidate-load-fixture``；repo-local control plane=``.ai-workspace/``；pinned Framework=``2.0.0``。`n<!-- FRAMEWORK-MANAGED:END -->`n<!-- PROJECT-CUSTOM:BEGIN -->`n`n<!-- PROJECT-CUSTOM:END -->`n";Write-Utf8 $candidateLoadBootstrapPath $candidateLoadBootstrap
$candidateLoadCustomBegin='<!-- PROJECT-CUSTOM:BEGIN -->';$candidateLoadCustomEnd='<!-- PROJECT-CUSTOM:END -->';$candidateLoadCustomStart=$candidateLoadBootstrap.IndexOf($candidateLoadCustomBegin,[StringComparison]::Ordinal)+$candidateLoadCustomBegin.Length;$candidateLoadCustomFinish=$candidateLoadBootstrap.IndexOf($candidateLoadCustomEnd,[StringComparison]::Ordinal);$candidateLoadManagedText=$candidateLoadBootstrap.Substring(0,$candidateLoadCustomStart)+$candidateLoadBootstrap.Substring($candidateLoadCustomFinish);$candidateLoadManagedIdentity=Get-BytesIdentity ($utf8.GetBytes($candidateLoadManagedText))
$candidateLoadTaskRelative='.ai-workspace/tasks/active/CANDIDATE-LOAD-001.md';$candidateLoadTaskPath=Join-Path $candidateLoadProject $candidateLoadTaskRelative;$candidateLoadActor='读取者-😀';Write-Utf8 $candidateLoadTaskPath "# CANDIDATE-LOAD-001 - candidate load fixture`n`n- Task schema: 2.0.0`n- Owner: candidate-load-owner`n- Work route: actor=$candidateLoadActor; role=EXECUTOR; phase=DISCOVER`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
$candidateLoadManifestPath=Join-Path $candidateLoadRoot 'RELEASE_MANIFEST.json';$candidateLoadStatePath=Join-Path $candidateLoadControl 'upgrade-recovery\2.0.0\state.json'
$candidateLoadState=[ordered]@{schemaVersion=4;projectId='candidate-load-fixture';fromVersion='1.15.1';toVersion='2.0.0';targetReleaseCanonical=$candidateLoadFacts.Canonical;targetReleaseManifestIdentity=(Get-Identity $candidateLoadManifestPath);actor='candidate-load-actor';taskId='CANDIDATE-LOAD-001';taskOwner='candidate-load-owner';taskRelative=$candidateLoadTaskRelative;authorizationIdentity=('1|'+('D'*64));objects=@([ordered]@{relative='.ai-workspace/project.json';oldIdentity='MISSING';newIdentity=(Get-Identity $candidateLoadConfigPath)},[ordered]@{relative='.ai-workspace/BOOTSTRAP.md';oldIdentity='MISSING';newIdentity=(Get-Identity $candidateLoadBootstrapPath)},[ordered]@{relative=$candidateLoadTaskRelative;oldIdentity='MISSING';newIdentity=(Get-Identity $candidateLoadTaskPath)});projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=@([ordered]@{relative='.ai-workspace/project.json';identity=(Get-Identity $candidateLoadConfigPath)},[ordered]@{relative='.ai-workspace/BOOTSTRAP.md';identity=(Get-Identity $candidateLoadBootstrapPath);managedIdentity=$candidateLoadManagedIdentity},[ordered]@{relative=$candidateLoadTaskRelative;identity=(Get-Identity $candidateLoadTaskPath)});transactionComplete=$true};Write-Utf8 $candidateLoadStatePath ($candidateLoadState|ConvertTo-Json -Depth 20)
$candidateLoader=Join-Path $candidateLoadRoot 'scripts\resolve-load-plan.ps1';$candidateLoadConfigIdentity=Get-Identity $candidateLoadConfigPath;$candidateLoadStateIdentity=Get-Identity $candidateLoadStatePath
$candidateLoaderArgs=@('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','REVIEW_AND_EVIDENCE.md','-ProjectRoot',$candidateLoadProject,'-ExpectedProjectConfigIdentity',$candidateLoadConfigIdentity,'-ExpectedCandidatePilotStateIdentity',$candidateLoadStateIdentity,'-AsJson','-TaskPath',$candidateLoadTaskPath,'-ObservedActor',$candidateLoadActor)
$candidateBoundLoad=Invoke-Ps $candidateLoader $candidateLoaderArgs
$candidateMissingBinding=Invoke-Ps $candidateLoader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','REVIEW_AND_EVIDENCE.md')
$candidateDriftedBinding=Invoke-Ps $candidateLoader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','REVIEW_AND_EVIDENCE.md','-ProjectRoot',$candidateLoadProject,'-ExpectedProjectConfigIdentity',$candidateLoadConfigIdentity,'-ExpectedCandidatePilotStateIdentity',('0|'+('0'*64)))
$candidateIncompleteState=[ordered]@{schemaVersion=3;projectId='candidate-load-fixture';fromVersion='1.15.1';toVersion='2.0.0';targetReleaseCanonical=$candidateLoadFacts.Canonical;targetReleaseManifestIdentity=(Get-Identity $candidateLoadManifestPath);actor='candidate-load-actor';taskId='CANDIDATE-LOAD-001';taskOwner='candidate-load-owner';taskRelative=$candidateLoadTaskRelative;authorizationIdentity=('1|'+('D'*64));objects=@([ordered]@{relative='.ai-workspace/project.json';oldIdentity='MISSING';newIdentity=(Get-Identity $candidateLoadConfigPath)},[ordered]@{relative='.ai-workspace/BOOTSTRAP.md';oldIdentity='MISSING';newIdentity=(Get-Identity $candidateLoadBootstrapPath)},[ordered]@{relative=$candidateLoadTaskRelative;oldIdentity='MISSING';newIdentity=(Get-Identity $candidateLoadTaskPath)});projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=@([ordered]@{relative='.ai-workspace/project.json';identity=(Get-Identity $candidateLoadConfigPath)},[ordered]@{relative='.ai-workspace/BOOTSTRAP.md';identity=(Get-Identity $candidateLoadBootstrapPath)},[ordered]@{relative=$candidateLoadTaskRelative;identity=(Get-Identity $candidateLoadTaskPath)})};Write-Utf8 $candidateLoadStatePath ($candidateIncompleteState|ConvertTo-Json -Depth 20)
$candidateIncompleteStateIdentity=Get-Identity $candidateLoadStatePath;$candidateIncompleteBinding=Invoke-Ps $candidateLoader @('-Role','EXECUTOR','-Profile','STANDARD','-Phase','DISCOVER','-HostName','GENERIC','-AffectedModuleFallback','REVIEW_AND_EVIDENCE.md','-ProjectRoot',$candidateLoadProject,'-ExpectedProjectConfigIdentity',$candidateLoadConfigIdentity,'-ExpectedCandidatePilotStateIdentity',$candidateIncompleteStateIdentity)
$candidateBoundReceipt=if($candidateBoundLoad.Code-eq0){$candidateBoundLoad.Text|ConvertFrom-Json}else{$null}
Assert-True ($candidateBoundLoad.Code-eq0-and[string]$candidateBoundReceipt.lifecycle-ceq'CANDIDATE'-and[string]$candidateBoundReceipt.candidatePilotStateIdentity-ceq$candidateLoadStateIdentity-and[string]$candidateBoundReceipt.evidenceCeiling-cmatch'LOCAL_CANDIDATE_PILOT'-and@($candidateBoundReceipt.affectedModuleFallback)-contains'REVIEW_AND_EVIDENCE.md') 'loader-candidate-fallback-reuses-bound-local-pilot-state'
Write-Utf8 $candidateLoadStatePath ($candidateLoadState|ConvertTo-Json -Depth 20)
Assert-True ($candidateBoundReceipt.routeSource-ceq'TASK_CARD'-and$candidateBoundReceipt.taskPath-ceq$candidateLoadTaskPath-and$candidateBoundReceipt.actor-ceq$candidateLoadActor) 'loader-native-complete-unicode-task-path-and-actor'
Assert-True ($candidateBoundLoad.Stderr-ceq''-and$candidateBoundLoad.Stdout-notmatch'[^\x00-\x7f]'-and@($candidateBoundReceipt.PSObject.Properties).Count-eq18-and$candidateBoundReceipt.modules-is[Array]-and$candidateBoundReceipt.phases-is[Array]-and$candidateBoundReceipt.capabilities-is[Array]) 'loader-native-complete-json-array-shapes'
$loaderOut=[Console]::Out;$loaderErr=[Console]::Error;$loaderEncoding=[Console]::OutputEncoding
$loaderInProcessArguments=@{TaskPath=$candidateLoadTaskPath;ObservedActor=$candidateLoadActor;Role='EXECUTOR';Profile='STANDARD';Phase='DISCOVER';HostName='GENERIC';AffectedModuleFallback='REVIEW_AND_EVIDENCE.md';ProjectRoot=$candidateLoadProject;ExpectedProjectConfigIdentity=$candidateLoadConfigIdentity;ExpectedCandidatePilotStateIdentity=$candidateLoadStateIdentity;AsJson=$true}
$loaderInProcess=@(& $candidateLoader @loaderInProcessArguments)
$loaderParsed=($loaderInProcess-join"`n")|ConvertFrom-Json -Depth 100
Assert-True (($loaderParsed|ConvertTo-Json -Depth 100 -Compress)-ceq($candidateBoundReceipt|ConvertTo-Json -Depth 100 -Compress)-and[object]::ReferenceEquals($loaderOut,[Console]::Out)-and[object]::ReferenceEquals($loaderErr,[Console]::Error)-and[object]::ReferenceEquals($loaderEncoding,[Console]::OutputEncoding)) 'loader-native-inprocess-all-fields-equal-writers-preserved'
Write-Utf8 $candidateLoadStatePath ($candidateIncompleteState|ConvertTo-Json -Depth 20)
Assert-True ($candidateMissingBinding.Code-ne0-and$candidateMissingBinding.Text.Contains('LOAD_CANDIDATE_BINDING_REQUIRED')-and$candidateDriftedBinding.Code-ne0-and$candidateDriftedBinding.Text.Contains('LOCAL_CANDIDATE_PILOT_STATE_DRIFT')) 'loader-candidate-fallback-rejects-missing-or-drifted-pilot-binding'
Assert-True ($candidateIncompleteBinding.Code-ne0-and$candidateIncompleteBinding.Text.Contains('LOCAL_CANDIDATE_SUPPORT_COMPLETION_REQUIRED')) 'loader-candidate-fallback-requires-complete-current-projection-state'

}
if($NativeIO){. Test-IntegrationLoaderNativeIo;Write-Output 'EVIDENCE_CEILING|PARTIAL|surface-native-io';return}
function Test-RouterSkillContract([string]$Text,[int64]$ByteLength) {
    if($ByteLength-lt1-or$ByteLength-ne[Text.Encoding]::UTF8.GetByteCount($Text)){return $false}
    foreach($required in @('name: ai-workspace-router-v2','NON_AUTHORITY','BOOTSTRAP','TOOLCHAIN','navigationContractVersion `2`','RECOVERY_CORE','PROJECT_READ_ONLY','PROCESS_REQUIREMENTS_RESOLVE','ADMIT_ACTION','FINALIZE_OUTPUT','pinned TOOLCHAIN/TOOL_CONTRACT','CONTROL_TRANSITION','各自门禁')){if(-not$Text.Contains($required)){return $false}}
    return $true
}
function Test-OrdinaryReplyBoundary([string]$VersionRoot) {
    $tempParent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    $fixtureTemp=Join-Path $tempParent ('aiw-selector-delivery-'+[guid]::NewGuid().ToString('N'))
    $fixtureCleanup=Get-PrivateFixtureCleanupPath $fixtureTemp $tempParent '^aiw-selector-delivery-[0-9a-f]{32}$' 'SELECTOR_DELIVERY'
    New-Item -ItemType Directory -Path $fixtureTemp|Out-Null
    try{
        $fixtureFramework=Join-Path $fixtureTemp 'framework-repo'
        $fixtureVersion=Join-Path $fixtureFramework 'framework/versions/2.0.0'
        New-Item -ItemType Directory -Path $fixtureVersion -Force|Out-Null
        Get-ChildItem -LiteralPath $VersionRoot -Force|Copy-Item -Destination $fixtureVersion -Recurse -Force
        $null=Seal-ReleaseFixture $fixtureVersion 'SELECTOR_DELIVERY_FIXTURE'
        $project=Join-Path $fixtureTemp 'project'
        New-Item -ItemType Directory -Path (Join-Path $project '.ai-workspace/tasks/active') -Force|Out-Null
        & git -C $project init --quiet
        if($LASTEXITCODE-ne0){throw 'DELIVERY_FIXTURE_GIT_INIT'}
        $config=[ordered]@{schemaVersion=7;id='reply-fixture';displayName='Reply Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[pscustomobject]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}
        $configPath=Join-Path $project '.ai-workspace/project.json'
        $correctionsPath=Join-Path $project '.ai-workspace/corrections.json'
        Write-Utf8 $configPath ($config|ConvertTo-Json -Depth 12)
        Write-Utf8 $correctionsPath (([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='reply-fixture';corrections=@()})|ConvertTo-Json -Depth 8)
        Write-Utf8 (Join-Path $project '.ai-workspace/process-policy.json') (([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='reply-fixture';rules=@()})|ConvertTo-Json -Depth 8)
        Write-Utf8 (Join-Path $project '.ai-workspace/controller.json') (([ordered]@{schemaVersion=1;projectId='reply-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})|ConvertTo-Json)
        Write-Utf8 (Join-Path $project '.ai-workspace/BOOTSTRAP.md') (@('<!-- PROJECT-CUSTOM:BEGIN -->','<!-- PROJECT-CUSTOM:END -->')-join[char]10)
        $taskPath=Join-Path $project '.ai-workspace/tasks/active/REPLY-FIXTURE-001.md'
        Write-Utf8 $taskPath (@('# REPLY-FIXTURE-001 - reply fixture','','- Task schema: 2.0.0','- Owner: owner-fixture','- Work route: actor=owner-fixture; role=TASK_OWNER; phase=PLAN','- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[docs/config.md]; actual_paths=[docs/config.md]')-join[char]10)
        Write-Utf8 (Join-Path $project 'docs/config.md') 'Example project configuration.'
        $runtime=Join-Path $project '.ai-workspace/runtime/REPLY-FIXTURE-001/owner-fixture'
        $inputPath=Join-Path $runtime 'discover.json';$receiptPath=Join-Path $runtime 'receipt.json';$boundaryPath=Join-Path $runtime 'boundary.json'
        $resolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
        $facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software')};workType=[ordered]@{state='KNOWN';values=@('aiw:discussion')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:report')};stage=[ordered]@{state='KNOWN';values=@('aiw:discussion')}}
        $intent=[ordered]@{schemaVersion=2;objective='解释此配置的含义';requestedActionKind='NONE';requestedResultKind='USER_RESPONSE';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=$facets}
        $input=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$fixtureFramework;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity $configPath;expectedCorrectionsIdentity=Get-Identity $correctionsPath;expectedTaskIdentity=Get-Identity $taskPath;observedActor='owner-fixture';capabilities=@();exactPaths=@('docs/config.md');forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
        Write-Utf8 $inputPath ($input|ConvertTo-Json -Depth 25)
        $run=Invoke-Ps $resolver @('-InputPath',$inputPath,'-AsJson')
        if($run.Code-ne0){throw ('DELIVERY_FIXTURE_DISCOVER|'+$run.Text)}
        $receipt=($run.Output[-1]|ConvertFrom-Json).compactReceipt
        $prep=@($receipt.selectedObligations|ForEach-Object preparationRequirements|Sort-Object -Unique)
        $results=@($receipt.selectedObligations|ForEach-Object resultRequirements|Sort-Object -Unique)
        Assert-True ('framework:PR_COMPACT_NON_INTERRUPT_DELIVERY'-cnotin@($receipt.selectedObligations.requirementId)-and'AUTHENTICATED_DELIVERY_ROUTE_BOUND'-cnotin$prep) 'ordinary-reply-discover-does-not-invent-host-route'
        Write-Utf8 $receiptPath ($receipt|ConvertTo-Json -Depth 40)
        $boundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;objective=$intent.objective;actionKind='NONE';resultKind='USER_RESPONSE';exactPaths=@('docs/config.md');authorizationIdentity='NOT_REQUIRED';preparationReceipts=@($prep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
        Write-Utf8 $boundaryPath ($boundary|ConvertTo-Json -Depth 30)
        $run=Invoke-Ps $resolver @('-InputPath',$boundaryPath,'-AsJson')
        Assert-True ($run.Code-eq0) 'ordinary-reply-admit-without-host-routing-proof'
        $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($results);$boundary.deliveryReceipts=@('CURRENT_USER_RESPONSE')
        Write-Utf8 $boundaryPath ($boundary|ConvertTo-Json -Depth 30)
        $run=Invoke-Ps $resolver @('-InputPath',$boundaryPath,'-AsJson')
        Assert-True ($run.Code-eq0) 'ordinary-reply-finalize-with-current-user-delivery'
        $input.intentEnvelope.requestedResultKind='TERMINAL'
        Write-Utf8 $inputPath ($input|ConvertTo-Json -Depth 25);$run=Invoke-Ps $resolver @('-InputPath',$inputPath,'-AsJson')
        if($run.Code-ne0){throw ('DELIVERY_FIXTURE_TERMINAL|'+$run.Text)}
        $terminal=($run.Output[-1]|ConvertFrom-Json).compactReceipt
        $terminalPrep=@($terminal.selectedObligations|ForEach-Object preparationRequirements|Sort-Object -Unique)
        Assert-True ('AUTHENTICATED_DELIVERY_ROUTE_BOUND'-cin$terminalPrep) 'strong-terminal-keeps-authenticated-delivery-obligation'
        Write-Utf8 $receiptPath ($terminal|ConvertTo-Json -Depth 40)
        $boundary.mode='ADMIT_ACTION';$boundary.resultKind='TERMINAL';$boundary.expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;$boundary.preparationReceipts=@($terminalPrep|Where-Object{$_-cne'AUTHENTICATED_DELIVERY_ROUTE_BOUND'});$boundary.resultReceipts=@();$boundary.deliveryReceipts=@()
        Write-Utf8 $boundaryPath ($boundary|ConvertTo-Json -Depth 30)
        $run=Invoke-Ps $resolver @('-InputPath',$boundaryPath,'-AsJson')
        Assert-True ($run.Code-eq3-and$run.Text.Contains('AUTHENTICATED_DELIVERY_ROUTE_BOUND')) 'strong-terminal-still-rejects-missing-host-route'
    }finally{Remove-Item -LiteralPath $fixtureCleanup -Recurse -Force}
}

function Test-SelectorMatching([string]$VersionRoot) {
    $result=Invoke-Ps (Join-Path $VersionRoot 'tests/facets-selection-tests.ps1') @()
    if($result.Code-ne0){throw ('FACETS_SELECTION_TESTS|'+$result.Text)}
    foreach($line in @($result.Output|Where-Object{[string]$_-clike'PASS|*'})){Assert-True $true ('selector-'+([string]$line).Substring(5))}
    $module=Import-Module (Join-Path $VersionRoot 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru
    $catalog=Get-Content -LiteralPath (Join-Path $VersionRoot 'PROCESS_REQUIREMENTS.json') -Raw|ConvertFrom-Json
    $lenses=@($catalog.requirements|Where-Object requirementId -CEQ 'PR_REVIEW_QUALIFICATION_AND_PLANNING')[0].selectors|ConvertTo-Json -Depth 30|ConvertFrom-Json
    $lenses.actionKinds=@('REVIEW_EXECUTE');$lenses.resultKinds=@('REVIEW_VERDICT')
    $lenses.deterministicTriggers=[pscustomobject]@{actionKinds=@('REVIEW_EXECUTE');resultKinds=@('REVIEW_VERDICT')}
    foreach($bad in @('wildcard','none','outside','empty','duplicate','unknown-field','unknown-mode')){
        $invalid=$lenses|ConvertTo-Json -Depth 20|ConvertFrom-Json
        switch($bad){'wildcard'{$invalid.deterministicTriggers.actionKinds=@('*')};'none'{$invalid.deterministicTriggers.actionKinds=@('NONE')};'outside'{$invalid.deterministicTriggers.actionKinds=@('PUSH')};'empty'{$invalid.deterministicTriggers.actionKinds=@();$invalid.deterministicTriggers.resultKinds=@()};'duplicate'{$invalid.deterministicTriggers.actionKinds=@('REVIEW_EXECUTE','REVIEW_EXECUTE')};'unknown-field'{$invalid.deterministicTriggers|Add-Member bogus @('REVIEW_EXECUTE')};'unknown-mode'{$invalid.semanticMatch='REGEX'}}
        $rejected=$false;try{& $module {param($s)Assert-AiwSelectorContract $s 'UNIT'} $invalid}catch{$rejected=$true}
        Assert-True $rejected ('selector-invalid-'+$bad)
    }
    $oneAxis=$lenses|ConvertTo-Json -Depth 20|ConvertFrom-Json;$oneAxis.deterministicTriggers.actionKinds=@()
    & $module {param($s)Assert-AiwSelectorContract $s 'UNIT'} $oneAxis
    Assert-True ($oneAxis.deterministicTriggers.resultKinds.Count-eq1) 'selector-single-trigger-axis-remains-valid'
    foreach($rule in $catalog.requirements){& $module {param($s)Assert-AiwSelectorContract $s 'NATIVE'} $rule.selectors}
    Assert-True ($catalog.requirements.Count-eq40-and@($catalog.requirements.requirementId|Sort-Object -Unique).Count-eq40) 'selector-all-original-native-contracts-valid'
}
$candidateRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
Test-SelectorMatching $candidateRoot
Test-OrdinaryReplyBoundary $candidateRoot
if($SelectorOnly){Write-Output 'EVIDENCE_CEILING|selector-group-only';Write-Output ('RESULT|'+(Get-IntegrationCheckCount)+'/'+(Get-IntegrationCheckCount)+' passed|scope=selector-matching');exit 0}
$actual = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($candidateRoot.Length + 1).Replace('\','/') })
[Array]::Sort($actual,[StringComparer]::Ordinal)
$inventoryPath=Join-Path $candidateRoot 'NORMATIVE_SURFACE_INVENTORY.json';$inventory=Get-Content -Raw -Encoding utf8 -LiteralPath $inventoryPath|ConvertFrom-Json
$inventoryFields=@($inventory.PSObject.Properties.Name)
$declared=New-Object 'System.Collections.Generic.List[string]'
foreach($pair in @($inventory.runtimeNormativeModules)){$declared.Add([string]$pair.document);$declared.Add([string]$pair.fragment)}
foreach($category in @('actionRequiredArtifacts','schemaAndMechanicalInputs','explanationAndHistory')){foreach($relative in @($inventory.$category)){$declared.Add([string]$relative)}}
$declaredArray=@($declared);$declaredUnique=@($declaredArray|Sort-Object -Unique);[Array]::Sort($declaredArray,[StringComparer]::Ordinal)
Assert-True ([int]$inventory.schemaVersion-eq1-and[string]$inventory.frameworkVersion-ceq'2.0.0'-and$inventoryFields.Count-eq6-and$declaredArray.Count-eq$declaredUnique.Count-and$actual.Count-eq$declaredArray.Count-and($actual-join"`n")-ceq($declaredArray-join"`n")) 'normative-surface-inventory-exact-set-classified-once'
$initialPayloadFacts=Get-ReleasePayloadFacts $candidateRoot
$independentOrdinalFiles=New-Object 'System.Collections.Generic.List[string]';foreach($relative in $actual){if($relative-cne'RELEASE_MANIFEST.json'){$independentOrdinalFiles.Add($relative)}};$independentOrdinalFiles.Sort([StringComparer]::Ordinal)
$initialManifestPath=Join-Path $candidateRoot 'RELEASE_MANIFEST.json';$initialManifestIdentity=Get-Identity $initialManifestPath;$initialManifest=Get-Content -LiteralPath $initialManifestPath -Raw -Encoding utf8|ConvertFrom-Json
$initialVersion=Get-Content -LiteralPath (Join-Path $candidateRoot 'VERSION.json') -Raw -Encoding utf8|ConvertFrom-Json
$initialReleaseState=Get-ReleaseValidationState $initialVersion $initialManifest $initialPayloadFacts ([bool]$SkipManifest)
Assert-True ([string]::Join("`n",$initialPayloadFacts.Files)-ceq[string]::Join("`n",$independentOrdinalFiles.ToArray())-and$initialReleaseState-in@('PENDING_CANDIDATE','REVIEWED_CANDIDATE','STABLE')) 'release-payload-and-manifest-state-classified'

$reviewedCandidateVersion=$initialVersion|ConvertTo-Json -Depth 20|ConvertFrom-Json;$reviewedCandidateVersion.lifecycle='CANDIDATE';$reviewedCandidateVersion.consumable=$false;$reviewedCandidateVersion.projectPinEligible=$false
$reviewedCandidateManifest=$initialManifest|ConvertTo-Json -Depth 20|ConvertFrom-Json;$reviewedCandidateManifest.lifecycle='CANDIDATE';$reviewedCandidateManifest.fileCount=$initialPayloadFacts.FileCount;$reviewedCandidateManifest.totalBytes=$initialPayloadFacts.TotalBytes;$reviewedCandidateManifest.canonical=$initialPayloadFacts.Canonical;$reviewedCandidateManifest.sourceReview='APPROVED';$reviewedCandidateManifest.releaseIntegration='PENDING';$reviewedCandidateManifest.completeSuite=[pscustomobject][ordered]@{status='PASS';passed=1;total=1;payloadCanonical=$initialPayloadFacts.Canonical;evidenceIdentity=('1|'+('A'*64))};$reviewedCandidateManifest.sourceReviewEvidence=[pscustomobject][ordered]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$initialPayloadFacts.Canonical;reviewedManifestIdentity=('1|'+('C'*64))}
Assert-True ((Get-ReleaseValidationState $reviewedCandidateVersion $reviewedCandidateManifest $initialPayloadFacts $false)-ceq'REVIEWED_CANDIDATE') 'reviewed-candidate-default-validation-state-admitted'
$mixedCandidateManifest=$reviewedCandidateManifest|ConvertTo-Json -Depth 20|ConvertFrom-Json;$mixedCandidateManifest.completeSuite.status='PENDING';$mixedCandidateRejected=$false
try{Get-ReleaseValidationState $reviewedCandidateVersion $mixedCandidateManifest $initialPayloadFacts $false|Out-Null}catch{$mixedCandidateRejected=$_.Exception.Message-ceq'RELEASE_VALIDATION_STATE_UNSUPPORTED'}
Assert-True $mixedCandidateRejected 'reviewed-candidate-mixed-evidence-state-rejected'

foreach ($relative in $actual) {
    $path = Join-Path $candidateRoot $relative
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no-bom|' + $relative)
    try { $text = $utf8Strict.GetString($bytes) } catch { throw "STRICT_UTF8_FAIL|$relative" }
    Assert-True (-not $text.Contains("`r") -and -not $text.Contains([char]0) -and -not $text.Contains([char]0xFFFD) -and $text.EndsWith("`n")) ('strict-text|' + $relative)
    if ([IO.Path]::GetExtension($relative) -ceq '.json' -and -not $text.Contains('{{')) {
        try { $null = $text | ConvertFrom-Json } catch { throw "JSON_FAIL|$relative|$($_.Exception.Message)" }
    }
    if ([IO.Path]::GetExtension($relative) -in @('.ps1','.psm1')) {
        $tokens=$null; $errors=$null
        [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) ('powershell-syntax|' + $relative)
    }
}

$version = $initialVersion
$loadManifest = Get-Content -LiteralPath (Join-Path $candidateRoot 'LOAD_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
$expectedLifecycle=if($initialReleaseState-ceq'STABLE'){'STABLE'}else{'CANDIDATE'}
$versionLifecycleState=if($initialReleaseState-ceq'STABLE'){[string]$version.lifecycle-ceq'STABLE'-and[bool]$version.consumable-and[bool]$version.projectPinEligible}else{[string]$version.lifecycle-ceq'CANDIDATE'-and-not[bool]$version.consumable-and-not[bool]$version.projectPinEligible}
Assert-True ([string]$version.version -ceq '2.0.0' -and $versionLifecycleState -and [string]$version.releaseClass -ceq 'MAJOR' -and [string]$version.baseline -ceq '1.16.0' -and $null -eq $version.PSObject.Properties['currentEligible']) 'version-lifecycle-fields-major-baseline-1.16.0-no-global-selector-field'
Assert-True ([string]$loadManifest.lifecycle -ceq $expectedLifecycle -and @($loadManifest.topologies.PSObject.Properties.Name).Count -eq 1 -and @($loadManifest.topologies.PSObject.Properties.Name)-contains'REPO_LOCAL' -and @($loadManifest.core)-cnotcontains'PROCESS_REQUIREMENTS.json' -and @($loadManifest.order)-cnotcontains'PROCESS_REQUIREMENTS.json' -and @($loadManifest.order)-cnotcontains'FRAMEWORK_RELEASE.md' -and @($loadManifest.requirementFragments.ownerModule)-cnotcontains'FRAMEWORK_RELEASE.md' -and @($loadManifest.requirementFragments.ownerModule)-cnotcontains'FRAMEWORK_MAINTENANCE.md') 'load-manifest-generic-runtime-and-release-governance-exclusion-contract'
$loadResolverText=Get-Content -LiteralPath (Join-Path $candidateRoot 'scripts\resolve-load-plan.ps1') -Raw -Encoding utf8
Assert-True ($loadResolverText.Contains('LOAD_MANIFEST_NOT_STABLE_OR_ADMITTED_CANDIDATE_1_16_0')-and$loadResolverText.Contains('Get-AiwLocalCandidateSupportBinding')-and$loadResolverText.Contains('ExpectedCandidatePilotStateIdentity')-and-not$loadResolverText.Contains('LOAD_MANIFEST_NOT_STABLE_1_15_1')) 'load-resolver-stable-or-bound-candidate-contract-current'

$liveFrameworkRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $candidateRoot '../..')))
$liveRepositoryRoot = Split-Path -Parent $liveFrameworkRoot
$rootAttributesText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $liveRepositoryRoot '.gitattributes')
Assert-True ([regex]::Matches($rootAttributesText,'(?m)^\*\.psm1 text eol=lf$').Count-eq1-and[regex]::Matches($rootAttributesText,'(?m)^\*\.mjs text eol=lf$').Count-eq1) 'root-checkout-policy-pins-psm1-and-mjs-lf'
$toolchain=Get-Content -LiteralPath (Join-Path $candidateRoot 'TOOLCHAIN.json') -Raw -Encoding utf8|ConvertFrom-Json
$toolContract=Get-Content -LiteralPath (Join-Path $candidateRoot 'TOOL_CONTRACT.md') -Raw -Encoding utf8
$backend=@($toolchain.officialBackends)[0]
$declaredPlatforms=@($backend.platforms|ForEach-Object{[string]$_})
$expectedOperations=@('CONTROL_TRANSITION','AUTHORIZATION_CHECK','AUTHORIZATION_RECEIVER_BIND','CORRECTIONS_CHECK','KNOWLEDGE_IMPACT_CHECK','KNOWLEDGE_QUERY','LOAD_PLAN_RESOLVE','PROCESS_REQUIREMENTS_RESOLVE','PROTECTED_SAFE_GIT','TASK_CARD_CHECK','WORKFLOW_ROUTE_RESOLVE')
$actualOperations=@($backend.entrypoints.PSObject.Properties.Name);[Array]::Sort($expectedOperations,[StringComparer]::Ordinal);[Array]::Sort($actualOperations,[StringComparer]::Ordinal)
Assert-True ([int]$toolchain.schemaVersion-eq1-and[string]$toolchain.frameworkVersion-ceq'2.0.0'-and[string]$toolchain.contractVersion-ceq'4'-and[string]$toolchain.projectSelectionField-ceq'frameworkToolBackend'-and@($toolchain.officialBackends).Count-eq1) 'toolchain-single-project-selected-backend'
Assert-True ($null-eq$toolchain.PSObject.Properties['routerCompatibility']-and[int]$toolchain.navigation.schemaVersion-eq1-and[string]$toolchain.navigation.kind-ceq'PROJECT_BOOTSTRAP'-and[string]$toolchain.navigation.navigationContractVersion-ceq'3'-and[string]$toolchain.navigation.bootstrapLocator-ceq'.ai-workspace/BOOTSTRAP.md'-and[string]::Join('|',@($toolchain.navigation.requiredOperations))-ceq'LOAD_PLAN_RESOLVE|PROCESS_REQUIREMENTS_RESOLVE|WORKFLOW_ROUTE_RESOLVE'-and[int]$toolchain.navigation.processCatalogSchemaVersion-eq3-and[string]$toolchain.navigation.processCatalogVersion-ceq'4'-and[string]$toolchain.navigation.nativeRuleBodySource-ceq'MARKDOWN_EXACT_BLOCK'-and@($toolchain.navigation.PSObject.Properties).Count-eq8) 'toolchain-project-bootstrap-navigation-exact'
Assert-True ([string]$backend.id-ceq'powershell7'-and[string]$backend.status-ceq'OFFICIAL'-and[string]$backend.runtime.command-ceq'pwsh'-and[string]$backend.runtime.edition-ceq'Core'-and[int]$backend.runtime.minimumMajorVersion-eq7-and($actualOperations-join"`n")-ceq($expectedOperations-join"`n")-and$declaredPlatforms.Count-eq1-and$declaredPlatforms[0]-ceq'windows') 'toolchain-powershell7-operation-set-windows-only'
foreach($entry in $backend.entrypoints.PSObject.Properties){$relative=[string]$entry.Value;$entryPath=Join-Path $candidateRoot $relative;Assert-True ($relative-ceq$relative.Replace('\','/')-and-not[IO.Path]::IsPathRooted($relative)-and-not$relative.Contains('..')-and(Test-Path -LiteralPath $entryPath -PathType Leaf)) ('toolchain-entrypoint|'+$entry.Name);$entryText=Get-Content -LiteralPath $entryPath -Raw -Encoding utf8;Assert-True ($entryText.Contains('POWERSHELL7_REQUIRED')-and-not$entryText.Contains('powershell.exe')) ('toolchain-runtime-guard|'+$entry.Name)}
$conformanceArguments=@($toolchain.conformance.arguments|ForEach-Object{[string]$_})
Assert-True ($conformanceArguments.Count-eq1-and$conformanceArguments[0]-ceq'-SkipBaseline') 'toolchain-conformance-runs-full-no-baseline-suite'
Assert-True (-not(Test-Path -LiteralPath (Join-Path $liveRepositoryRoot '.github\workflows\framework-toolchain-conformance.yml'))) 'three-platform-ci-not-selected-for-windows-only-1.15-scope'
$projectSchemaText=Get-Content -LiteralPath (Join-Path $candidateRoot 'PROJECT_CONFIG_SCHEMA.json') -Raw -Encoding utf8
$maintenanceSchemaText=Get-Content -LiteralPath (Join-Path $liveFrameworkRoot 'maintenance-overlay/PROJECT_CONFIG_SCHEMA.json') -Raw -Encoding utf8
$maintenanceSchema=$maintenanceSchemaText|ConvertFrom-Json
$currentProjectFormat=[int]((Get-Content -LiteralPath (Join-Path $candidateRoot 'ADOPTION_PROFILE.json') -Raw|ConvertFrom-Json).projectControl.schemaVersion)
$currentProjectArms=@(($projectSchemaText|ConvertFrom-Json).oneOf|Where-Object{$_.properties.schemaVersion.const-eq$currentProjectFormat})
$currentMaintenanceArms=@($maintenanceSchema.oneOf|Where-Object{$_.properties.schemaVersion.const-eq$currentProjectFormat})
Assert-True ($currentProjectArms.Count-eq1-and$currentMaintenanceArms.Count-eq1) 'ordinary-and-maintenance-current-schema-arm-unique'
$projectStarterText=Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter/project.json') -Raw -Encoding utf8
Assert-True ($projectSchemaText.Contains('frameworkToolBackend')-and$maintenanceSchemaText.Contains('frameworkToolBackend')-and@($currentMaintenanceArms[0].required)-contains'processPolicy'-and$projectStarterText.Contains('"frameworkToolBackend": "powershell7"')-and$toolContract.Contains('projectConfigIdentity')) 'tool-backend-schema-starter-package-binding'

$platform=if($IsWindows){'windows'}elseif($IsMacOS){'macos'}else{'linux'}
if($platform-notin$declaredPlatforms){
    Write-Output ('EVIDENCE_CEILING|PLATFORM_NOT_DECLARED|'+$platform)
    Assert-True $true 'tool-contract-undeclared-platform-evidence-ceiling-recorded'
}else{
  $platformTempParent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$platformTemp=Join-Path $platformTempParent ('aiw-tool-platform-'+[guid]::NewGuid().ToString('N'));$platformTempCleanup=Get-PrivateFixtureCleanupPath $platformTemp $platformTempParent '^aiw-tool-platform-[0-9a-f]{32}$' 'TOOL_PLATFORM';New-Item -ItemType Directory -Path $platformTemp|Out-Null
  try{
    if($IsWindows){
      # Exercise rejection before either extracted core can import or inspect a
      # project. A guard string alone cannot detect the import-order regression.
      $legacyPowerShell=(Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
      $guardProject=Join-Path $platformTemp 'runtime-guard-project';New-Item -ItemType Directory -Path $guardProject|Out-Null
      $guardSentinel=Join-Path $guardProject 'preserved.txt';Write-Utf8 $guardSentinel 'preserve original project bytes'
      $guardSentinelIdentity=Get-Identity $guardSentinel
      $guardEmptyInput=Join-Path $platformTemp 'runtime-guard-empty.json';Write-Utf8 $guardEmptyInput '{}'
      $guardProjectInput=Join-Path $platformTemp 'runtime-guard-project.json';Write-Utf8 $guardProjectInput (@{projectRoot=$guardProject}|ConvertTo-Json -Compress)
      $guardChecker=Join-Path $candidateRoot 'scripts/check-authorization.ps1'
      $guardResolver=Join-Path $candidateRoot 'scripts/resolve-process-requirements.ps1'
      $guardCheckerArguments=@('-PackagePath',(Join-Path $platformTemp 'absent-package.json'),'-ObservedActor','runtime-guard','-ObservedTaskId','RUNTIME-GUARD','-ObservedOwner','runtime-guard','-ObservedAction','SOURCE_WRITE','-ObservedPath','sample.txt')
      $guardCases=@(
        @{Name='authorization-no-root';Entry=$guardChecker;Arguments=$guardCheckerArguments},
        @{Name='authorization-with-root';Entry=$guardChecker;Arguments=@($guardCheckerArguments)+@('-ProjectConfigPath',(Join-Path $guardProject '.ai-workspace/project.json'))},
        @{Name='process-no-root';Entry=$guardResolver;Arguments=@('-InputPath',$guardEmptyInput)},
        @{Name='process-with-root';Entry=$guardResolver;Arguments=@('-InputPath',$guardProjectInput)}
      )
      foreach($guardCase in $guardCases){
        $guardResult=Invoke-PsHost $legacyPowerShell $guardCase.Entry $guardCase.Arguments $guardProject
        Assert-True ($guardResult.Code-eq4-and$guardResult.Output.Count-eq1-and$guardResult.Text-ceq'FAIL|tool-runtime|POWERSHELL7_REQUIRED') ('tool-contract-rejects-legacy-before-import|'+$guardCase.Name)
        $guardEntries=@(Get-ChildItem -LiteralPath $guardProject -Force)
        Assert-True ($guardEntries.Count-eq1-and$guardEntries[0].FullName-ceq$guardSentinel-and-not$guardEntries[0].PSIsContainer-and($guardEntries[0].Attributes-band[IO.FileAttributes]::ReparsePoint)-eq0-and(Get-Identity $guardSentinel)-ceq$guardSentinelIdentity) ('tool-contract-legacy-rejection-preserves-project|'+$guardCase.Name)
      }
    }
    $casePath=Join-Path $platformTemp 'CaseProbe';Write-Utf8 $casePath 'case'
    $caseVariantPath=Join-Path $platformTemp 'caseprobe'
    $caseInsensitive=Test-Path -LiteralPath $caseVariantPath
    $caseBehaviorConsistent=if($caseInsensitive){(Get-Identity $caseVariantPath)-ceq(Get-Identity $casePath)}else{-not(Test-Path -LiteralPath $caseVariantPath)}
    Assert-True $caseBehaviorConsistent 'tool-contract-case-behavior-explicit-and-consistent'
    if($IsLinux){Assert-True (-not$caseInsensitive) 'tool-contract-linux-case-sensitive'}else{Assert-True $true 'tool-contract-platform-reported-case-behavior-accepted'}
    $linkTarget=Join-Path $platformTemp 'link-target';$linkPath=Join-Path $platformTemp 'link-probe';New-Item -ItemType Directory -Path $linkTarget|Out-Null;New-TestJunction $linkPath $linkTarget
    Assert-True (((Get-Item -LiteralPath $linkPath -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0) 'tool-contract-link-probe'
    $normalized=[IO.Path]::GetRelativePath($platformTemp,$casePath).Replace('\','/')
    Assert-True ($normalized-ceq'CaseProbe'-and-not$normalized.Contains('\')) 'tool-contract-relative-path-normalized'
    if(-not$IsWindows){
        $mode=[IO.File]::GetUnixFileMode($casePath)
        $executableMode=$mode-bor[IO.UnixFileMode]::UserExecute
        [IO.File]::SetUnixFileMode($casePath,$executableMode)
        Assert-True (([IO.File]::GetUnixFileMode($casePath)-band[IO.UnixFileMode]::UserExecute)-ne0) 'tool-contract-unix-user-execute-permission'
        [IO.File]::SetUnixFileMode($casePath,$mode)
        Assert-True ([IO.File]::GetUnixFileMode($casePath)-eq$mode) 'tool-contract-unix-permission-restored'
    }else{Assert-True $true 'tool-contract-windows-permission-ceiling-explicit'}
    Write-Output ('CONFORMANCE|platform='+$platform+'|caseInsensitive='+$caseInsensitive.ToString().ToLowerInvariant()+'|runtime='+$PSVersionTable.PSVersion.ToString())
  }finally{foreach($link in @($script:testJunctions)){Remove-TestJunction $link};Remove-Item -LiteralPath $platformTempCleanup -Recurse -Force -ErrorAction SilentlyContinue}
}

if($ToolContractOnly){
    Write-Output 'EVIDENCE_CEILING|tool-contract-group-only'
    $contractTempParent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$contractTemp=Join-Path $contractTempParent ('aiw-tool-contract-'+[guid]::NewGuid().ToString('N'));$contractTempCleanup=Get-PrivateFixtureCleanupPath $contractTemp $contractTempParent '^aiw-tool-contract-[0-9a-f]{32}$' 'TOOL_CONTRACT';New-Item -ItemType Directory -Path $contractTemp|Out-Null
    try{
        $gitRoot=Join-Path $contractTemp 'git-probe';New-GitRepo $gitRoot
        $gitConfigPath=Join-Path $gitRoot '.ai-workspace/project.json'
        $gitConfig=[ordered]@{schemaVersion=7;id='tool-contract-git';displayName='Tool Contract Git';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{KNOWLEDGE_REFERENCE=[ordered]@{enabled=$false;sources=@()}};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}
        Write-Utf8 $gitConfigPath ($gitConfig|ConvertTo-Json -Depth 20)
        $gitVisible=Join-Path $gitRoot 'visible.txt';Write-Utf8 $gitVisible 'baseline';Commit-All $gitRoot 'tool contract baseline';Write-Utf8 $gitVisible 'changed'
        $safeGitEntry=Join-Path $candidateRoot ([string]$backend.entrypoints.PROTECTED_SAFE_GIT)
        $safeGitProbe=Invoke-Ps $safeGitEntry @('-ProjectRoot',$gitRoot,'-Operation','STATUS','-AllowPath','visible.txt','-ExpectedProjectConfigIdentity',(Get-Identity $gitConfigPath))
        Assert-True ($safeGitProbe.Code-eq0-and$safeGitProbe.Text.Contains('visible.txt')-and$safeGitProbe.Text.Contains('"operation":"STATUS"')) 'tool-contract-safe-git-normalized-path'
    }finally{Remove-Item -LiteralPath $contractTempCleanup -Recurse -Force -ErrorAction SilentlyContinue}
    Write-Output "RESULT|$((Get-IntegrationCheckCount)) passed|scope=Framework-2.0.0-tool-contract"
    return
}
$selectorScope = @(
    (Join-Path $liveRepositoryRoot '.gitattributes'),(Join-Path $liveRepositoryRoot 'AGENTS.md'),(Join-Path $liveRepositoryRoot 'CLAUDE.md'),
    (Join-Path $liveRepositoryRoot 'INITIALIZATION.md'),(Join-Path $liveRepositoryRoot 'README.md'),(Join-Path $liveFrameworkRoot 'ROADMAP.md'),
    (Join-Path $liveRepositoryRoot 'scripts\register-project.ps1'),(Join-Path $liveRepositoryRoot 'scripts\upgrade-project.ps1')
) + @($actual | Where-Object { $_ -cne 'tests/run-framework-tests.ps1' } | ForEach-Object { Join-Path $candidateRoot $_ })
$forbiddenVersionSelectorTerms = @(
    ('framework' + '/' + 'CURRENT'),('framework' + '\' + 'CURRENT'),('CURRENT' + '-default'),
    ('live roots/' + 'CURRENT'),('CURRENT' + ' is not authority')
)
$selectorHits = @()
foreach ($path in $selectorScope) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
    foreach ($term in $forbiddenVersionSelectorTerms) {
        if ($text.Contains($term)) { $selectorHits += ($path + '|' + $term) }
    }
}
Assert-True ($selectorHits.Count -eq 0) 'version-selector-terminology-absent-from-live-root-and-1.11-runtime'

. Test-IntegrationLoaderNativeIo

$normalProjectTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\project.json') -Raw -Encoding utf8
$normalControllerTemplate = Get-Content -LiteralPath (Join-Path $candidateRoot 'project-starter\controller.json') -Raw -Encoding utf8
try {
    $null = $normalProjectTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{DISPLAY_NAME_JSON}}','"Fixture"').Replace('{{FRAMEWORK_VERSION_JSON}}','"2.0.0"') | ConvertFrom-Json
    $null = $normalControllerTemplate.Replace('{{PROJECT_ID_JSON}}','"fixture"').Replace('{{CONTROLLER_ID_JSON}}','"controller"') | ConvertFrom-Json
    $normalStarterRendered = $true
} catch { $normalStarterRendered = $false }
Assert-True $normalStarterRendered 'repo-local-starter-json-renders'

$maintenanceOverlayRoot=Join-Path $liveRepositoryRoot 'framework\maintenance-overlay';$overlayManifest=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $maintenanceOverlayRoot 'OVERLAY.json')|ConvertFrom-Json
Assert-True (-not(Test-Path -LiteralPath (Join-Path $candidateRoot 'framework-maintenance-starter'))-and[string]$overlayManifest.overlayId-ceq'framework-maintenance-sibling'-and[string]$overlayManifest.baseStarter-ceq'project-starter'-and[string]$overlayManifest.targetControlPlanePolicy-ceq'ABSENT'-and$null-eq$overlayManifest.PSObject.Properties['legacySourceVersions']) 'maintenance-starter-removed-root-overlay-has-no-legacy-source-list'
foreach($template in @([pscustomobject]@{Name='project-starter';Path=(Join-Path $candidateRoot 'project-starter\BOOTSTRAP.md')},[pscustomobject]@{Name='maintenance-overlay';Path=(Join-Path $maintenanceOverlayRoot 'BOOTSTRAP.md')})){$templateText=Get-Content -Raw -Encoding utf8 -LiteralPath $template.Path;$templateRegion=[regex]::Match($templateText,'(?s)<!-- PROJECT-CUSTOM:BEGIN -->(.*?)<!-- PROJECT-CUSTOM:END -->');Assert-True ($templateRegion.Success-and[string]::IsNullOrWhiteSpace($templateRegion.Groups[1].Value)) ('starter-project-custom-region-structurally-empty-'+$template.Name)}
$budgetContractRaw=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'tests\PROCESS_REQUIREMENTS_BUDGETS.json');$budgetContract=$budgetContractRaw|ConvertFrom-Json
$authoritySchema=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'AUTHORITY_CONTEXT_SCHEMA.json')|ConvertFrom-Json
$intentSchema=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'INTENT_ENVELOPE_SCHEMA.json')|ConvertFrom-Json
$fixtureContractPath=Join-Path $candidateRoot 'tests\PROCESS_REQUIREMENTS_FIXTURES.json';$measurementHarnessPath=Join-Path $candidateRoot 'tests\measure-process-requirements.ps1';$fixtureContract=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureContractPath|ConvertFrom-Json
$adoptionProfile=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'ADOPTION_PROFILE.json')|ConvertFrom-Json
Assert-True ([string]$adoptionProfile.frameworkVersion-ceq'2.0.0'-and[bool]$adoptionProfile.registrationEligible-and[bool]$adoptionProfile.localCandidatePilotEligible-and(@($adoptionProfile.sourceCompatibility.projectFormats)-join'|')-ceq'repo-local/project-config-4|repo-local/project-config-5|repo-local/project-config-6|repo-local/project-config-7'-and@($adoptionProfile.sourceCompatibility.requiredCapabilities).Count-eq0-and$null-eq$adoptionProfile.PSObject.Properties['directSourceVersions']-and[int]$adoptionProfile.projectControl.schemaVersion-eq7-and[string]$adoptionProfile.projectControl.processCarrierContractVersion-ceq'2.0.0'-and[string]$adoptionProfile.projectControl.frameworkToolBackend-ceq'powershell7'-and[string]$adoptionProfile.projectControl.navigationProjection-ceq'PROJECT_BOOTSTRAP_MANAGED_AGENTS'-and[string]$adoptionProfile.projectControl.runtimeArtifactRoot-ceq'.ai-workspace/runtime'-and[string]$adoptionProfile.projectControl.runtimeGitIgnoreRule-ceq'/.ai-workspace/runtime/'-and[bool]$adoptionProfile.projectControl.taskLastWriteRequired-and[string]$adoptionProfile.projectControl.capabilityBinding-ceq'EXACT_ENABLED_IDS'-and$null-eq$adoptionProfile.PSObject.Properties['processBudget']) 'adoption-profile-current-formats-without-rule-pack-quota'
Assert-True (@($authoritySchema.oneOf).Count-eq3-and(@($authoritySchema.oneOf|ForEach-Object{$_.properties.schemaVersion.const})-join'|')-ceq'1|2|3'-and(@($authoritySchema.oneOf|ForEach-Object{@($_.required).Count})-join'|')-ceq'25|29|33'-and[int]$budgetContract.candidate.legacyAuthorityContextFieldCount-eq25-and[int]$budgetContract.candidate.compactAuthorityBindingFieldCount-eq33-and@($intentSchema.required).Count-eq11-and[int]$budgetContract.candidate.intentEnvelopeFieldCount-eq11-and[int]$budgetContract.candidate.receiptSourceBindingFieldCount-eq16-and[int]$budgetContract.candidate.compactBoundaryInputFieldCount-eq9-and[int]$budgetContract.candidate.toolContractVersion-eq4-and[int]$budgetContract.candidate.discoverInputVersion-eq5-and[int]$budgetContract.candidate.compactReceiptVersion-eq4) 'process-current-contract-field-counts'
$fixtureIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$fixtureBudgetsValid=$true;foreach($fixture in @($budgetContract.fixtures)){if(-not$fixtureIds.Add([string]$fixture.fixtureId)-or[int]$fixture.selectedPackEstimatedTokens-ne[int][math]::Ceiling([int]$fixture.selectedPackBytes/4.0)-or[int]$fixture.selectedPackBytes-lt1-or[int]$fixture.selectedRequirementCount-lt1){$fixtureBudgetsValid=$false};foreach($modeName in @('DISCOVER','ADMIT_ACTION','FINALIZE_OUTPUT')){$runtime=$fixture.observedRuntimeMs.$modeName;if([double]$runtime.median-le0-or[double]$runtime.p95-lt[double]$runtime.median){$fixtureBudgetsValid=$false}}}
Assert-True ($fixtureBudgetsValid-and$fixtureIds.Count-eq6-and[string]$budgetContract.fixtureObservationsContract-ceq'TC2_HISTORICAL'-and[string]$budgetContract.candidate.measurementObservation.status-ceq'PENDING'-and@($budgetContract.measurementContract.statistics)-contains'median'-and@($budgetContract.measurementContract.statistics)-contains'nearest-rank-p95'-and[int]$budgetContract.measurementContract.warmupsPerModeAndFixture-eq1-and[int]$budgetContract.measurementContract.measuredRunsPerModeAndFixture-eq5-and[string]$budgetContract.candidate.fixtureContractIdentity-ceq(Get-Identity $fixtureContractPath)-and[string]$budgetContract.candidate.measurementHarnessIdentity-ceq(Get-Identity $measurementHarnessPath)-and[int]$budgetContract.historicalCandidate.measurementObservation.warmups-eq1-and[int]$budgetContract.historicalCandidate.measurementObservation.measuredRuns-eq1) 'current-fixture-contract-and-historical-observations-remain-separate'
$fixtureIdentitiesValid=$true;foreach($fixture in @($fixtureContract.fixtures)){$ordered=[ordered]@{};foreach($property in @($fixture.PSObject.Properties)){if($property.Name-cne'fixtureIdentity'){$ordered[$property.Name]=$property.Value}};$computed=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($ordered|ConvertTo-Json -Depth 30 -Compress))));if([string]$fixture.fixtureIdentity-cne$computed){$fixtureIdentitiesValid=$false}}
Assert-True ($fixtureIdentitiesValid-and@($fixtureContract.fixtures).Count-eq6) 'process-budget-fixture-record-identities-reproducible'
$contextBudgetsValid=$true
$rootRouterPath=Join-Path $liveRepositoryRoot 'skills\ai-workspace-router-v2\SKILL.md';$versionRouterContractPath=Join-Path $candidateRoot 'host\skills\ai-workspace-router-v2\SKILL.md';$routerBytes=[int64](Get-Item -LiteralPath $rootRouterPath).Length;$routerIdentity=Get-Identity $rootRouterPath;$routerSkillText=Get-Content -Raw -Encoding utf8 -LiteralPath $rootRouterPath;$versionRouterContract=Get-Content -Raw -Encoding utf8 -LiteralPath $versionRouterContractPath
foreach($context in @($budgetContract.endToEndContexts)){
    $fixture=@($budgetContract.fixtures|Where-Object{[string]$_.fixtureId-ceq[string]$context.caseId})
    $contextFields=@($context.PSObject.Properties.Name);$loadPlanBytes=0L;foreach($module in @($context.loadPlanModules)){$modulePath=Join-Path $candidateRoot ([string]$module);if(-not(Test-Path -LiteralPath $modulePath -PathType Leaf)){$contextBudgetsValid=$false}else{$loadPlanBytes+=[int64](Get-Item -LiteralPath $modulePath).Length}}
    $total=$routerBytes+$loadPlanBytes+[int64]$fixture[0].selectedPackBytes;$estimated=[int][math]::Ceiling($total/4.0)
    if($fixture.Count-ne1-or$contextFields.Count-ne4-or@(@('caseId','loadPlanModules','catalogModelLoaded','projectTaskFactsExcluded')|Where-Object{$_-cnotin$contextFields}).Count-ne0-or@($context.loadPlanModules).Count-ne0-or[bool]$context.catalogModelLoaded-or-not[bool]$context.projectTaskFactsExcluded){$contextBudgetsValid=$false}
}
Assert-True ($contextBudgetsValid-and@($budgetContract.endToEndContexts).Count-eq3-and[string]$budgetContract.evidenceCeiling-like'*project/task facts*excluded*') 'process-budget-normal-path-derived-router-plus-selected-blocks-without-load-plan-modules'
Assert-True ($routerIdentity-ceq(Get-Identity $rootRouterPath)-and$versionRouterContract.Contains('REFERENCE_ONLY / NON_INSTALLABLE / NON_AUTHORITY')-and$versionRouterContract.Contains('旧nav2固定来源')-and$versionRouterContract.Contains('本目标nav3/TC4直接使用PROJECT_BOOTSTRAP')-and-not$versionRouterContract.StartsWith('---')-and-not(Test-Path -LiteralPath (Join-Path $candidateRoot 'project-starter\.agents\skills\ai-workspace-router-v2'))-and-not(Test-Path -LiteralPath (Join-Path $maintenanceOverlayRoot '.agents\skills\ai-workspace-router-v2'))) 'legacy-router-source-preserved-and-current-bootstrap-history-noninstallable'
$plusRouterText=$routerSkillText.Insert($routerSkillText.Length-1,' ');$minusIndex=$routerSkillText.IndexOf('本 Skill 是 ',[StringComparison]::Ordinal)+1
Assert-True ($minusIndex-gt1-and$routerSkillText[$minusIndex]-ceq' ') 'router-v2-harmless-whitespace-fixture-anchor'
$minusRouterText=$routerSkillText.Remove($minusIndex,1)
Assert-True ($minusIndex-gt0-and$utf8.GetByteCount($plusRouterText)-eq$routerBytes+1-and$utf8.GetByteCount($minusRouterText)-eq$routerBytes-1-and(Test-RouterSkillContract $plusRouterText ($utf8.GetByteCount($plusRouterText)))-and(Test-RouterSkillContract $minusRouterText ($utf8.GetByteCount($minusRouterText)))) 'router-derived-byte-measurement-allows-harmless-whitespace-without-quota'
$semanticDeletion=$routerSkillText.Replace('FINALIZE_OUTPUT','FINALIZE_OMITTED');$largerRouter=$routerSkillText+("`n<!--"+(' '*([int]$budgetContract.ceilings.routerSkillBytes+1))+"-->`n")
Assert-True (-not(Test-RouterSkillContract $semanticDeletion ($utf8.GetByteCount($semanticDeletion)))-and-not(Test-RouterSkillContract $routerSkillText ($routerBytes+1))) 'router-required-semantics-and-byte-identity-remain-checked'
Assert-True ($utf8.GetByteCount($largerRouter)-gt[int]$budgetContract.ceilings.routerSkillBytes-and(Test-RouterSkillContract $largerRouter ($utf8.GetByteCount($largerRouter)))) 'router-historical-byte-ceiling-is-not-a-current-length-gate'
foreach($starterEntry in @([pscustomobject]@{Name='project-starter';Path=(Join-Path $candidateRoot 'project-starter\AGENTS.md')},[pscustomobject]@{Name='maintenance-overlay';Path=(Join-Path $maintenanceOverlayRoot 'AGENTS.md')})){
    Import-Module (Join-Path $liveRepositoryRoot 'scripts\ProjectAdoptionState.psm1') -Prefix Entry -Force
    $entryNavigation=Get-EntryAiwNavigationContract -Toolchain $toolchain
    $outsideEntryText="# Existing project instructions`nKeep project-specific authority.`n"
    $agentsText=Get-EntryAiwStandingDelegationProjection -Text $outsideEntryText -AdoptionRequested $true -TemplatePath $starterEntry.Path -RouterSkillName $entryNavigation.SkillName -NavigationKind $entryNavigation.Kind
    Assert-True (Test-RouterSkillContract $routerSkillText $routerBytes) ('host-global-router-skill-navigation-contract|'+$starterEntry.Name)
    $managedEntry=[regex]::Match($agentsText,'(?s)<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->.*?<!-- AI-WORKSPACE-FRAMEWORK:END -->').Value
    $bootstrapNavigation=$entryNavigation.Kind-ceq'PROJECT_BOOTSTRAP'-and$managedEntry.Contains('.ai-workspace/BOOTSTRAP.md')-and-not$managedEntry.Contains('Skill')-and-not$agentsText.Contains('{{ROUTER_SKILL_NAME}}')
    Assert-True ([regex]::Matches($agentsText,'AI-WORKSPACE-FRAMEWORK:BEGIN').Count-eq1-and[regex]::Matches($agentsText,'AI-WORKSPACE-FRAMEWORK:END').Count-eq1-and$bootstrapNavigation) ('agents-existing-entry-managed-bootstrap-block-exact|'+$starterEntry.Name)
    Assert-True ($agentsText.StartsWith($outsideEntryText,[StringComparison]::Ordinal)-and-not$agentsText.Contains('在本项目内，AI')-and-not$agentsText.Contains('AI-WORKSPACE-USER-DECISION:BEGIN')) ('agents-existing-entry-preserves-instructions-without-default-grant|'+$starterEntry.Name)
    $newAgentsText=Get-EntryAiwStandingDelegationProjection -Text '' -AdoptionRequested $true -TemplatePath $starterEntry.Path -RouterSkillName $entryNavigation.SkillName -NavigationKind $entryNavigation.Kind
    $newManagedEntry=[regex]::Match($newAgentsText,'(?s)<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->.*?<!-- AI-WORKSPACE-FRAMEWORK:END -->').Value
    $starterUserDecision=[regex]::Match((Get-Content -Raw -Encoding utf8 -LiteralPath $starterEntry.Path),'(?s)<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->.*?<!-- AI-WORKSPACE-USER-DECISION:END -->').Value
    $newUserDecision=[regex]::Match($newAgentsText,'(?s)<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->.*?<!-- AI-WORKSPACE-USER-DECISION:END -->').Value
    Assert-True ([regex]::Matches($newAgentsText,'AI-WORKSPACE-FRAMEWORK:BEGIN').Count-eq1-and[regex]::Matches($newAgentsText,'AI-WORKSPACE-FRAMEWORK:END').Count-eq1-and$newManagedEntry-ceq$managedEntry) ('agents-new-entry-managed-bootstrap-block-exact|'+$starterEntry.Name)
    Assert-True ($starterUserDecision.Contains('在本项目内，AI')-and$newUserDecision-ceq$starterUserDecision-and[regex]::Matches($newAgentsText,'AI-WORKSPACE-USER-DECISION:BEGIN').Count-eq1-and[regex]::Matches($newAgentsText,'AI-WORKSPACE-USER-DECISION:END').Count-eq1-and$newAgentsText.IndexOf($newUserDecision,[StringComparison]::Ordinal)-gt$newAgentsText.IndexOf('<!-- AI-WORKSPACE-FRAMEWORK:END -->',[StringComparison]::Ordinal)-and-not$newManagedEntry.Contains('在本项目内，AI')) ('agents-new-entry-adopts-complete-starter-decision-outside-managed-block|'+$starterEntry.Name)
}
$duplicateOwnerRoot=Join-Path $temp 'catalog-duplicate-owner-fixture';Copy-Item -LiteralPath $candidateRoot -Destination $duplicateOwnerRoot -Recurse
$duplicateOwnerManifestPath=Join-Path $duplicateOwnerRoot 'LOAD_MANIFEST.json';$duplicateOwnerManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $duplicateOwnerManifestPath|ConvertFrom-Json;$duplicateOwnerManifest.requirementFragments[1].ownerModule=$duplicateOwnerManifest.requirementFragments[0].ownerModule;Write-Utf8 $duplicateOwnerManifestPath ($duplicateOwnerManifest|ConvertTo-Json -Depth 40)
$duplicateOwnerRun=Invoke-Ps (Join-Path $duplicateOwnerRoot 'scripts\build-process-requirements.ps1') @('-Check')
Assert-True ($duplicateOwnerRun.Code-ne0-and$duplicateOwnerRun.Text.Contains('REQUIREMENT_FRAGMENT_ENTRY_VALUES')) 'process-requirements-generator-rejects-duplicate-owner-module'
$missingOwnerRoot=Join-Path $temp 'catalog-missing-owner-fixture';Copy-Item -LiteralPath $candidateRoot -Destination $missingOwnerRoot -Recurse
$missingOwnerManifestPath=Join-Path $missingOwnerRoot 'LOAD_MANIFEST.json';$missingOwnerManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $missingOwnerManifestPath|ConvertFrom-Json;$missingOwnerEntry=$missingOwnerManifest.requirementFragments[0];$missingOwnerEntry.ownerModule='MISSING_OWNER.md';Write-Utf8 $missingOwnerManifestPath ($missingOwnerManifest|ConvertTo-Json -Depth 40);$missingOwnerFragmentPath=Join-Path $missingOwnerRoot ([string]$missingOwnerEntry.sidecar);$missingOwnerFragment=Get-Content -Raw -Encoding utf8 -LiteralPath $missingOwnerFragmentPath|ConvertFrom-Json;$missingOwnerFragment.ownerModule='MISSING_OWNER.md';Write-Utf8 $missingOwnerFragmentPath ($missingOwnerFragment|ConvertTo-Json -Depth 40)
$missingOwnerRun=Invoke-Ps (Join-Path $missingOwnerRoot 'scripts\build-process-requirements.ps1') @('-Check')
Assert-True ($missingOwnerRun.Code-ne0-and$missingOwnerRun.Text.Contains('REQUIREMENT_OWNER_MODULE_MISSING|MISSING_OWNER.md')) 'process-requirements-generator-rejects-missing-normative-owner-module'

$reviewEvidenceText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'REVIEW_AND_EVIDENCE.md')
$projectControlText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROJECT_CONTROL.md')
$evaluationText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROCESS_REQUIREMENTS_EVALUATION.md')
$processCatalogText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'PROCESS_REQUIREMENTS.json')
# Document guards check their complete owning rule blocks. These are presence
# checks; actual repair/rereview behavior remains covered by integration tests.
$documentGuardBlocks=@{}
foreach($documentRule in @(@{Id='PR_CORRECTION_ADOPTION_ANALYSIS';Text=$projectControlText},@{Id='PR_REVIEW_QUALIFICATION_AND_PLANNING';Text=$reviewEvidenceText})){
    $ruleBegin='<!-- AIW-REQUIREMENT:'+$documentRule.Id+':BEGIN -->'
    $ruleEnd='<!-- AIW-REQUIREMENT:'+$documentRule.Id+':END -->'
    $beginMatches=[regex]::Matches($documentRule.Text,[regex]::Escape($ruleBegin))
    $endMatches=[regex]::Matches($documentRule.Text,[regex]::Escape($ruleEnd))
    if($beginMatches.Count-ne1-or$endMatches.Count-ne1-or$endMatches[0].Index-le$beginMatches[0].Index){throw ('INTEGRATION_DOCUMENT_RULE_BLOCK|'+$documentRule.Id)}
    $ruleStart=$beginMatches[0].Index+$ruleBegin.Length
    $documentGuardBlocks[$documentRule.Id]=$documentRule.Text.Substring($ruleStart,$endMatches[0].Index-$ruleStart)
}
$correctionAdoptionText=$documentGuardBlocks['PR_CORRECTION_ADOPTION_ANALYSIS']
$reviewQualificationText=$documentGuardBlocks['PR_REVIEW_QUALIFICATION_AND_PLANNING']
Assert-True ($correctionAdoptionText.Contains('规则ID、近似文案、changelog或对象hash本身不证明覆盖')-and$correctionAdoptionText.Contains('工具只检查精确投影，不能替代语义判断')-and$reviewQualificationText.Contains('提出finding不自动成为贡献者，测试通过不取消有效质量问题。')) 'correction-adoption-identities-and-tests-do-not-prove-semantic-coverage'
Assert-True ($correctionAdoptionText.Contains('不登记消费者纠正ID或hash来抑制项目规则')-and$correctionAdoptionText.Contains('完整覆盖退出重复，部分覆盖保留增量，未覆盖保留，冲突明确解决')-and$correctionAdoptionText.Contains('旧有效、旧抑制及停用历史都要承接')-and$correctionAdoptionText.Contains('需要新版本才能成立的退出与目标运行绑定同一采用事务')-and$correctionAdoptionText.Contains('失败回到匹配旧包及完整前像')-and$correctionAdoptionText.Contains('不建中央/本地吸收台账')-and$reviewQualificationText.Contains('真实finding直接交仍负责修复的writer，finding本身不授写权；当前修复包准入后修复，由原仍独立Reviewer按受影响范围复审。')-and$reviewQualificationText.Contains('实际修正、直接消费者和必要相邻回归须复证，未变完整Review与有效证据保留；扩面或决定/主体变化回Owner。')) 'correction-adoption-project-analysis-atomic-migration-history-and-independent-review-without-registry'
Assert-True ($evaluationText.Contains('显式采用 stable `2.0.0` 后才开始 observation')-and$evaluationText.Contains('使用正常 project task')-and$evaluationText.Contains('来源 task 保留一条 compact record')-and$evaluationText.Contains('不规定固定 sample count/time window')-and$evaluationText.Contains('不是 release gate')-and$evaluationText.Contains('不替代 conformance、independent Review、`RESULT_ACCEPT` 或 release sealing')-and-not$evaluationText.Contains('exactly 20 admitted samples')-and-not$evaluationText.Contains('INSUFFICIENT_SAMPLE / NO_ADVANCE')) 'post-release-project-observation-nonblocking-no-synthetic-work'
Assert-True (-not$processCatalogText.Contains('level_test2')-and-not$processCatalogText.Contains('Pocket')) 'process-catalog-generic-no-consumer-paths'
    $timedGroup='workflowFocused';$timedEntry=(Join-Path $candidateRoot 'tests/workflow-route-tests.ps1');$timedArgs=@(@())
    Write-Output ('TIMING|START|group='+$timedGroup+'|entry='+$timedEntry+'|arguments='+($timedArgs -join ' ')+'|utc='+[DateTime]::UtcNow.ToString('o'))
    $groupTimer=[Diagnostics.Stopwatch]::StartNew();$workflowFocused=$null
    try{$workflowFocused=Invoke-Ps $timedEntry $timedArgs}finally{
        $groupTimer.Stop();$timedExit=if($null-ne$workflowFocused){[string]$workflowFocused.Code}else{'UNKNOWN'}
        Write-Output ('TIMING|END|group='+$timedGroup+'|elapsedMs='+$groupTimer.ElapsedMilliseconds+'|exitCode='+$timedExit+'|utc='+[DateTime]::UtcNow.ToString('o'))
    }
    if($workflowFocused.Code-ne0){throw ('WORKFLOW_FOCUSED|'+$workflowFocused.Text)}
    foreach($line in @($workflowFocused.Output|Where-Object{$_-clike'PASS|*'})){Assert-True $true ([string]$line).Substring(5)}

    $taskChecker = Join-Path $candidateRoot 'scripts\check-task-card.ps1'
    $criticalTaskPath = Join-Path $temp 'TASK-PROPORTIONALITY-001.md'
    $criticalTask = @'
# TASK-PROPORTIONALITY-001 - fixture

- Task schema: 2.0.0
- Owner: owner-fixture
- Work route: actor=owner-fixture; role=TASK_OWNER; phase=PLAN
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=fixture-candidate; expected_paths=[]; actual_paths=[]
- Phase gate: FALSE
- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=clarify existing route and add one narrow rejection; added_machinery=NONE; escalation_trigger=repeated natural deviation across independent sessions
'@
    Write-Utf8 $criticalTaskPath $criticalTask
    $criticalTaskValid = Invoke-Ps $taskChecker @('-TaskPath',$criticalTaskPath)
    if($criticalTaskValid.Code -ne 0 -or -not$criticalTaskValid.Text.Contains('profile=CRITICAL')){Write-Output ('DIAG|task-card-critical-proportionality-valid|code='+$criticalTaskValid.Code+'|text='+$criticalTaskValid.Text)}
    Assert-True ($criticalTaskValid.Code -eq 0 -and $criticalTaskValid.Text.Contains('profile=CRITICAL')) 'task-card-critical-proportionality-valid'
    Write-Utf8 $criticalTaskPath ($criticalTask -replace '(?m)^- Proportionality:.*(?:\n|$)','')
    $criticalTaskMissing = Invoke-Ps $taskChecker @('-TaskPath',$criticalTaskPath)
    Assert-True ($criticalTaskMissing.Code -eq 0) 'task-card-critical-label-does-not-require-proportionality-boilerplate'
    $optionalTask=($criticalTask -replace '(?m)^- Proportionality:.*(?:\n|$)','' -replace '(?m)^- Phase gate:.*(?:\n|$)','').TrimEnd("`r","`n").Replace("`n","`r`n")
    [IO.File]::WriteAllText($criticalTaskPath,$optionalTask,[Text.UTF8Encoding]::new($false));$optionalTaskIdentity=Get-Identity $criticalTaskPath
    $optionalTaskResult=Invoke-Ps $taskChecker @('-TaskPath',$criticalTaskPath)
    Assert-True ($optionalTaskResult.Code-eq0-and(Get-Identity $criticalTaskPath)-ceq$optionalTaskIdentity) 'critical-task-optional-boilerplate-crlf-no-final-newline-preserves-raw-bytes'
    Write-Utf8 $criticalTaskPath ($criticalTask -replace 'existing=partial','existing=sufficient' -replace 'added_machinery=NONE','added_machinery=service:1')
    $criticalTaskContradiction = Invoke-Ps $taskChecker @('-TaskPath',$criticalTaskPath)
    Assert-True ($criticalTaskContradiction.Code -ne 0 -and $criticalTaskContradiction.Text.Contains('PROPORTIONALITY_CONTRADICTION')) 'task-card-proportionality-blocks-machinery-when-existing-sufficient'
    $standardTaskPath = Join-Path $temp 'TASK-STANDARD-001.md'
    Write-Utf8 $standardTaskPath "# TASK-STANDARD-001 - fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=executor-fixture; role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $standardTaskValid = Invoke-Ps $taskChecker @('-TaskPath',$standardTaskPath)
    Assert-True ($standardTaskValid.Code -eq 0 -and $standardTaskValid.Text.Contains('loadContext=ACTOR_BOUND') -and $standardTaskValid.Text.Contains('actor=executor-fixture') -and $standardTaskValid.Text.Contains('role=EXECUTOR') -and $standardTaskValid.Text.Contains('phase=IMPLEMENT')) 'task-card-standard-actor-bound-work-route'
    $taskBoundLoad=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','executor-fixture','-IncludeRecovery','-HostName','CODEX')
    Assert-True ($taskBoundLoad.Code-eq0-and$taskBoundLoad.Text.Contains('routeSource=TASK_CARD')-and$taskBoundLoad.Text.Contains('phases=RECOVER,IMPLEMENT')-and$taskBoundLoad.Text.Contains('PROJECT_CONTROL.md')-and$taskBoundLoad.Text.Contains('TASK_AND_SCOPE.md')) 'loader-task-bound-recover-plus-work-phase'
    $taskRouteDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','executor-fixture','-Role','REVIEWER','-Profile','STANDARD','-Phase','IMPLEMENT','-HostName','CODEX')
    Assert-True ($taskRouteDrift.Code-ne0-and$taskRouteDrift.Text.Contains('LOAD_TASK_ROLE_DRIFT')) 'loader-rejects-caller-role-drift'
    Write-Utf8 $standardTaskPath "# TASK-STANDARD-001 - fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=reviewer-fixture; role=REVIEWER; phase=REVIEW`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $reviewTaskLoad=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','reviewer-fixture','-HostName','CODEX')
    Assert-True ($reviewTaskLoad.Code-eq0-and$reviewTaskLoad.Text.Contains('routeSource=TASK_CARD')-and$reviewTaskLoad.Text.Contains('phases=REVIEW')-and$reviewTaskLoad.Text.Contains('TASK_AND_SCOPE.md')-and$reviewTaskLoad.Text.Contains('REVIEW_AND_EVIDENCE.md')-and-not$reviewTaskLoad.Text.Contains('PROJECT_CONTROL.md')) 'loader-task-bound-review-transition-workset'
    $taskPhaseDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','reviewer-fixture','-Role','REVIEWER','-Profile','STANDARD','-Phase','IMPLEMENT','-HostName','CODEX')
    Assert-True ($taskPhaseDrift.Code-ne0-and$taskPhaseDrift.Text.Contains('LOAD_TASK_PHASE_DRIFT')) 'loader-rejects-caller-phase-drift'
    $taskProfileDrift=Invoke-Ps $loader @('-TaskPath',$standardTaskPath,'-ObservedActor','reviewer-fixture','-Role','REVIEWER','-Profile','CRITICAL','-Phase','REVIEW','-HostName','CODEX')
    Assert-True ($taskProfileDrift.Code-ne0-and$taskProfileDrift.Text.Contains('LOAD_TASK_PROFILE_DRIFT')) 'loader-rejects-caller-profile-drift'
    $schema111TaskPath=Join-Path $temp 'TASK-SCHEMA-1.11-ROUTE-001.md'
    Write-Utf8 $schema111TaskPath "# TASK-SCHEMA-1.11-ROUTE-001 - fixture`n`n- Task schema: 1.11.0`n- Owner: owner-fixture`n- Work route: role=EXECUTOR; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $schema111TaskCheck=Invoke-Ps $taskChecker @('-TaskPath',$schema111TaskPath)
    $schema111TaskLoad=Invoke-Ps $loader @('-TaskPath',$schema111TaskPath,'-HostName','CODEX')
    Assert-True ($schema111TaskCheck.Code-eq0-and$schema111TaskCheck.Text.Contains('evidenceCeiling=LEGACY_ACTOR_CONTEXT_UNBOUND')-and$schema111TaskLoad.Code-eq0-and$schema111TaskLoad.Text.Contains('routeSource=LEGACY_ACTOR_CONTEXT_UNBOUND')-and$schema111TaskLoad.Text.Contains('evidenceCeiling=LEGACY_ACTOR_CONTEXT_UNBOUND')-and$schema111TaskLoad.Text.Contains('phases=IMPLEMENT')) 'schema-1.11-two-field-work-route-readable-with-actor-ceiling'
    $missingRouteTaskPath=Join-Path $temp 'TASK-MISSING-ROUTE-001.md'
    Write-Utf8 $missingRouteTaskPath "# TASK-MISSING-ROUTE-001 - fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $missingRouteCheck=Invoke-Ps $taskChecker @('-TaskPath',$missingRouteTaskPath)
    $missingRouteLoad=Invoke-Ps $loader @('-TaskPath',$missingRouteTaskPath,'-Role','EXECUTOR','-Profile','STANDARD','-Phase','IMPLEMENT')
    Assert-True ($missingRouteCheck.Code-ne0-and$missingRouteCheck.Text.Contains('WORK_ROUTE_ACTOR_FIELD')-and$missingRouteLoad.Code-ne0-and$missingRouteLoad.Text.Contains('LOAD_TASK_WORK_ROUTE_REQUIRED')) 'schema-1.13-actor-work-route-required'
    $missing111RouteTaskPath=Join-Path $temp 'TASK-SCHEMA-1.11-MISSING-ROUTE-001.md'
    Write-Utf8 $missing111RouteTaskPath "# TASK-SCHEMA-1.11-MISSING-ROUTE-001 - fixture`n`n- Task schema: 1.11.0`n- Owner: owner-fixture`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $missing111RouteCheck=Invoke-Ps $taskChecker @('-TaskPath',$missing111RouteTaskPath)
    $missing111RouteLoad=Invoke-Ps $loader @('-TaskPath',$missing111RouteTaskPath,'-Role','EXECUTOR','-Profile','STANDARD','-Phase','IMPLEMENT')
    Assert-True ($missing111RouteCheck.Code-ne0-and$missing111RouteCheck.Text.Contains('WORK_ROUTE_FIELD')-and$missing111RouteLoad.Code-ne0-and$missing111RouteLoad.Text.Contains('LOAD_TASK_WORK_ROUTE_REQUIRED')) 'schema-1.11-work-route-required'
    $legacyTaskPath=Join-Path $temp 'TASK-LEGACY-LOAD-001.md'
    Write-Utf8 $legacyTaskPath "# TASK-LEGACY-LOAD-001 - fixture`n`n- Task schema: 1.10.0`n- Owner: owner-fixture`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $legacyTaskCheck=Invoke-Ps $taskChecker @('-TaskPath',$legacyTaskPath)
    $legacyLoad=Invoke-Ps $loader @('-TaskPath',$legacyTaskPath,'-Role','EXECUTOR','-Profile','STANDARD','-Phase','IMPLEMENT','-IncludeRecovery')
    Assert-True ($legacyTaskCheck.Code-eq0-and$legacyTaskCheck.Text.Contains('loadContext=LEGACY_LOAD_CONTEXT')-and$legacyLoad.Code-eq0-and$legacyLoad.Text.Contains('routeSource=LEGACY_LOAD_CONTEXT')-and$legacyLoad.Text.Contains('ROLE_PHASE_EXPLICITLY_INFERRED_FROM_LEGACY_TASK')) 'legacy-task-explicit-route-fallback-visible'
    $liveUpgradePath=Join-Path $liveRepositoryRoot 'scripts\upgrade-project.ps1'
    $liveUpgradeText=Get-Content -LiteralPath $liveUpgradePath -Raw -Encoding utf8
    $runtimeGuardOffset=$liveUpgradeText.IndexOf("if(`$PSVersionTable.PSEdition-cne'Core'-or`$PSVersionTable.PSVersion.Major-lt7)",[StringComparison]::Ordinal)
    $maintenanceModuleOffset=$liveUpgradeText.IndexOf("`$maintenanceModulePath=Join-Path `$PSScriptRoot 'MaintenanceOverlay.psm1'",[StringComparison]::Ordinal)
    $projectReadOffset=$liveUpgradeText.IndexOf('$initialConfigRaw=Read-StrictUtf8NoBom $projectFile',[StringComparison]::Ordinal)
    $recoveryOffset=$liveUpgradeText.IndexOf('Resume-ActorBoundProjectUpgrade $repo',[StringComparison]::Ordinal)
    Assert-True ($runtimeGuardOffset-ge0-and$maintenanceModuleOffset-gt$runtimeGuardOffset-and$projectReadOffset-gt$maintenanceModuleOffset-and$recoveryOffset-gt$projectReadOffset-and-not$liveUpgradeText.Contains('powershell7Versions')) 'upgrade-powershell7-guard-precedes-project-read-and-recovery-without-release-allowlist'

    # Index3 multi-source and legacy conversion coverage runs in knowledge-sources-tests.

    if ($SkipBaseline) {Write-Output 'SKIP|historical-baseline-executable-regression|reason=SkipBaseline'}
    else {Write-Output 'NOT_RUN|historical-baseline-executable-regression|reason=retired-executable-suite-history-only'}

    if (-not $SkipManifest) {
        $manifest = Get-Content -LiteralPath (Join-Path $candidateRoot 'RELEASE_MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $facts=Get-ReleasePayloadFacts $candidateRoot
        $payloadRowsStable=($facts.Rows-join"`n")-ceq($initialPayloadFacts.Rows-join"`n")
        $manifestOk = $payloadRowsStable -and [int]$manifest.fileCount -eq $initialPayloadFacts.FileCount -and [int64]$manifest.totalBytes -eq $initialPayloadFacts.TotalBytes -and [string]$manifest.canonical -ceq $initialPayloadFacts.Canonical
        if (-not $manifestOk) { Write-Output ('DIAG|manifest|initial=' + $initialPayloadFacts.FileCount + '|' + $initialPayloadFacts.TotalBytes + '|' + $initialPayloadFacts.Canonical + '|finalRowsStable=' + $payloadRowsStable + '|declared=' + $manifest.fileCount + '|' + $manifest.totalBytes + '|' + $manifest.canonical) }
        Assert-True $manifestOk 'release-manifest-canonical'
    } else {Write-Output 'SKIP|release-manifest-payload-validation|reason=SkipManifest'}
$resultManifest=Get-Content -LiteralPath (Join-Path $candidateRoot 'RELEASE_MANIFEST.json') -Raw -Encoding utf8|ConvertFrom-Json
$resultState=Get-ReleaseValidationState $version $resultManifest (Get-ReleasePayloadFacts $candidateRoot) ([bool]$SkipManifest)
Assert-True ($resultState-ceq$initialReleaseState-and(Get-Identity $initialManifestPath)-ceq$initialManifestIdentity) 'result-lifecycle-and-manifest-bytes-preserved'
} finally { if($integrationContext){Close-IntegrationContext $integrationContext} }
Write-Output ('RESULT|'+(Get-IntegrationCheckCount)+'/'+(Get-IntegrationCheckCount)+' passed|scope=Framework-2.0.0-surface|')
