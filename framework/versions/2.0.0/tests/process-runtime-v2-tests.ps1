[CmdletBinding()]
param([switch]$FixtureContractOnly,[switch]$ArchiveCasesOnly,[switch]$BoundaryCasesOnly,[switch]$RuleLoadingOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Assert-True([bool]$Value,[string]$Name){if(-not$Value){if($null-ne(Get-Variable LastFixtureResolverText -Scope Script -ErrorAction SilentlyContinue)){Write-Output ('DIAG|'+$script:LastFixtureResolverText)};throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Invoke-Resolver([string]$Resolver,[string]$InputPath){$global:LASTEXITCODE=0;$output=@(& $Resolver -InputPath $InputPath -AsJson 2>&1|ForEach-Object{[string]$_});$resolverExitCode=$global:LASTEXITCODE;$script:LastFixtureResolverText=($output-join"`n");return [pscustomobject]@{Code=$resolverExitCode;Text=($output-join"`n");Value=$(try{$output[-1]|ConvertFrom-Json -Depth 100}catch{$null})}}
function Assert-ResolverSuccess($Run,[string]$Name){$status=if($null-ne$Run.Value-and$null-ne$Run.Value.PSObject.Properties['status']){[string]$Run.Value.status}else{'UNPARSED'};$reason=if($null-ne$Run.Value-and$null-ne$Run.Value.PSObject.Properties['reason']){[string]$Run.Value.reason}else{'NOT_REPORTED'};if($Run.Code-ne0-or$status-cnotin@('PASS','EVALUATION_ONLY')){Write-Output ('DIAG|'+$Name+'|code='+$Run.Code+'|status='+$status+'|reason='+$reason+'|text='+$Run.Text);throw ('RESOLVER_STEP_FAILED|'+$Name+'|code='+$Run.Code+'|status='+$status+'|reason='+$reason)}}
function Write-Json([string]$Path,$Value){Write-Utf8 $Path ($Value|ConvertTo-Json -Depth 100)}
function Refresh-FixtureSourceRevision($Descriptor){
  foreach($document in $Descriptor.documents){$document.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) $fixtureBindings}
  $Descriptor.revision=Get-AiwContentRevision $Descriptor $fixtureBindings
  $Descriptor.itemIdentity=Get-AiwContentItemIdentity $Descriptor
}
function Set-FixtureLegacyRules([object[]]$Rules){
  # Explicitly migrate fixture inputs; the public resolver only receives current objects.
  $policy=$sourcePolicy|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $policy.rules=@($Rules|ForEach-Object{$_|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100})
  $bindings=@(Get-AiwLegacySourceBindings $policy)
  $config=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100
  $config.sourceBindings=$bindings;Write-Json $configPath $config
  foreach($rule in $policy.rules){$rule.source=Convert-AiwLegacyPolicySource $rule.source $rule.ruleId $bindings}
  Write-Json $policyPath $policy
  $script:discover.expectedProjectConfigIdentity=Get-Identity $configPath
  return $policy
}
function New-ContinuationEvidence([string]$Name,[string]$Actor,[string]$TaskId,[int]$ExitCode,[string[]]$Output,[string]$Command=''){
  $requirementsPath=Join-Path $control ($Name+'-requirements.md')
  Write-Utf8 $requirementsPath ('Fixture requirement: '+$(if($Command){'src/file.txt must contain bounded local fix.'}else{'Read the document fixture and its current candidate identity before routing.'}))
  $requirements=[ordered]@{path=$requirementsPath;identity=Get-Identity $requirementsPath}
  $method='MODEL_JUDGMENT';$locators=@($requirements)
  if($Command){
    $method='COMMAND';$outputPath=Join-Path $control ($Name+'-command-output.txt');Write-Utf8 $outputPath ($Output-join"`n")
    $commandPath=Join-Path $control ($Name+'-command.json');Write-Json $commandPath ([ordered]@{command=$Command;exitCode=$ExitCode;output=[ordered]@{path=$outputPath;identity=Get-Identity $outputPath}})
    $locators=@([ordered]@{path=$commandPath;identity=Get-Identity $commandPath})
  }
  $outcome=if($ExitCode-eq0){'PASS'}else{'FAIL'}
  $path=Join-Path $control ($Name+'-self-check.json')
  Write-Json $path ([ordered]@{schemaVersion=1;taskId=$TaskId;actor=$Actor;candidateObjects=@([ordered]@{path='src/file.txt';identity=Get-Identity (Join-Path $temp 'src/file.txt')});requirementsRef=$requirements;outcome=$outcome;checks=@([ordered]@{id=$Name;method=$method;outcome=$outcome;reason='Actual fixture observation, not a claim of external project acceptance.';evidenceLocators=$locators});evidenceLocators=@($requirements)})
  return [ordered]@{kind='SELF_CHECK';path=$path;identity=Get-Identity $path}
}

function Remove-FixtureJunction([string]$Path,[string]$FixtureRoot){$full=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($FixtureRoot));if(-not$full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'JUNCTION_CLEANUP_BOUNDARY'};$entry=Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue;if($null-eq$entry){return};if(($entry.Attributes-band[IO.FileAttributes]::ReparsePoint)-eq0){throw 'REFUSE_REMOVE_NON_JUNCTION'};[IO.Directory]::Delete($full)}
function Get-FixtureDirectoryMoveBinding([string]$TempRoot,[string]$SourcePath,[string]$DestinationPath){$systemTemp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($TempRoot));if([IO.Path]::GetDirectoryName($root)-cne$systemTemp-or[IO.Path]::GetFileName($root)-cnotmatch'^aiw-process-v2-[a-f0-9]{32}$'){throw 'FIXTURE_MOVE_TEMP_BOUNDARY'};$source=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($SourcePath));$destination=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($DestinationPath));$sourceLeaf=[IO.Path]::GetFileName($source);$destinationLeaf=[IO.Path]::GetFileName($destination);if(-not(($sourceLeaf-ceq'docs'-and$destinationLeaf-ceq'docs-hold')-or($sourceLeaf-ceq'docs-hold'-and$destinationLeaf-ceq'docs'))-or[IO.Path]::GetDirectoryName($source)-cne$root-or[IO.Path]::GetDirectoryName($destination)-cne$root-or$source-cne(Join-Path $root $sourceLeaf)-or$destination-cne(Join-Path $root $destinationLeaf)){throw 'FIXTURE_MOVE_PATH_BOUNDARY'};$sourceItem=Get-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue;if($null-eq$sourceItem-or-not$sourceItem.PSIsContainer-or($sourceItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-or[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($sourceItem.FullName))-cne$source){throw 'FIXTURE_MOVE_SOURCE_BOUNDARY'};$destinationItem=Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue;if($null-ne$destinationItem){throw 'FIXTURE_MOVE_DESTINATION_BOUNDARY'};return [pscustomobject]@{Root=$root;Source=$source;Destination=$destination}}

$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$sourceFrameworkRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $versionRoot '..\..\..')))
$resolver=Join-Path $versionRoot 'scripts\resolve-process-requirements.ps1'
$module=Join-Path $versionRoot 'scripts\ProcessRequirementComposition.psm1'
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1') -Force
if($ArchiveCasesOnly){
  if($FixtureContractOnly){throw 'ARCHIVE_CASES_ARGUMENTS'}
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'control-transition-tests.ps1'),'-Group','OrdinaryArchive') -GroupId 'process-current-task-archive'
  $run.Output|ForEach-Object{Write-Output $_}
  if($run.Code-ne0){exit $run.Code}
  Assert-True ($run.Text.Contains('CONTROL_TRANSITION_TESTS_PASS')) 'actual-current-task-archive-public-checker-discover-admit-original-finalize-chain'
  return
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-process-v2-'+[guid]::NewGuid().ToString('N'))
$outsideTemp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-process-v2-outside-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item -ItemType Directory -Path $temp -Force|Out-Null
  foreach($templatePath in @((Join-Path $sourceFrameworkRoot 'framework\versions\2.0.0\project-starter\BOOTSTRAP.md'),(Join-Path $sourceFrameworkRoot 'framework\maintenance-overlay\BOOTSTRAP.md'))){$templateText=Get-Content -Raw -Encoding utf8 -LiteralPath $templatePath;$templateRegion=[regex]::Match($templateText,'(?s)<!-- PROJECT-CUSTOM:BEGIN -->(.*?)<!-- PROJECT-CUSTOM:END -->');Assert-True ($templateRegion.Success-and[string]::IsNullOrWhiteSpace($templateRegion.Groups[1].Value)) ('template-project-custom-region-structurally-empty-'+[IO.Path]::GetFileName((Split-Path -Parent $templatePath)))}
  & git -C $temp init -q
  # Copy the declared runtime recipe, excluding historical Qpre attachments.
  $fixtureDefinition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
  $frameworkRoot=Join-Path $temp 'framework-root'
  $fixtureVersion=New-AiwTestRuntimeFixture -SourceRoot $sourceFrameworkRoot -DestinationRoot $frameworkRoot -VersionPaths @($fixtureDefinition.mechanismVersionPaths)
  $control=Join-Path $temp '.ai-workspace';New-Item -ItemType Directory -Path (Join-Path $control 'tasks\active') -Force|Out-Null
  Write-Json (Join-Path $control 'project.json') ([ordered]@{schemaVersion=7;id='process-v2-fixture';displayName='Process V2 Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
  Write-Json (Join-Path $control 'controller.json') ([ordered]@{schemaVersion=1;projectId='process-v2-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
  Write-Json (Join-Path $control 'corrections.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='process-v2-fixture';corrections=@()})
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nNo permanent project process rule is active in this legacy region. Structured rules belong to ``.ai-workspace/process-policy.json``.`n<!-- PROJECT-CUSTOM:END -->"
  $taskPath=Join-Path $control 'tasks\active\PROCESS-V2-001.md'
  Write-Utf8 $taskPath "# PROCESS-V2-001 — runtime contract fixture`n`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; risk=MEDIUM; size=SMALL; uncertainty=LOW`n"
  Write-Utf8 (Join-Path $temp 'docs\base.md') "Base project rule dependency."
  Write-Utf8 (Join-Path $temp 'docs\standard.md') "Intro.`n<!-- RULE:BEGIN -->`nSelected project standard rule body.`n<!-- RULE:END -->`nTail."
  $sourcePolicy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='process-v2-fixture';rules=@([ordered]@{ruleId='SOURCE_BOUND_STANDARD';requirementReason='Use the current project standard';selectors=[ordered]@{profiles=@('STANDARD');roles=@('TASK_OWNER');phases=@('PLAN');actionKinds=@('NONE');resultKinds=@('PLAN');pathPrefixes=@();capabilities=@();semanticTerms=@('source-bound')};preparationRequirements=@('PROJECT_STANDARD_READ');resultRequirements=@('PROJECT_STANDARD_APPLIED');decisionLocator='project:fixture';source=[ordered]@{rootSourceId='STANDARD';documents=@([ordered]@{sourceId='BASE';locator='docs/base.md';identity=Get-Identity (Join-Path $temp 'docs\base.md');mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()},[ordered]@{sourceId='STANDARD';locator='docs/standard.md';identity=Get-Identity (Join-Path $temp 'docs\standard.md');mode='MARKED_SECTION';sectionStart='<!-- RULE:BEGIN -->';sectionEnd='<!-- RULE:END -->';dependencies=@('BASE')})}})}
  Import-Module (Join-Path $fixtureVersion 'scripts/ObjectFormats.psm1') -Force
  Import-Module (Join-Path $fixtureVersion 'scripts/ContentSources.psm1')
  $sourcePolicy=$sourcePolicy|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $fixtureBindings=@(Get-AiwLegacySourceBindings $sourcePolicy)
  $fixtureConfig=Get-Content (Join-Path $control 'project.json') -Raw|ConvertFrom-Json -Depth 100
  $fixtureConfig.sourceBindings=$fixtureBindings;Write-Json (Join-Path $control 'project.json') $fixtureConfig
  foreach($rule in $sourcePolicy.rules){$rule.source=Convert-AiwLegacyPolicySource $rule.source $rule.ruleId $fixtureBindings}
  $policyPath=Join-Path $control 'process-policy.json';Write-Json $policyPath $sourcePolicy
  $baseIntent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Plan source-bound project work';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('source-bound');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
  $discover=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$baseIntent;evaluationOnly=$true}
  $discoverPath=Join-Path $temp 'discover.json'
  if($BoundaryCasesOnly){
    Write-Utf8 $taskPath "# PROCESS-V2-001 — bounded capacity and author fixtures`n`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; risk=MEDIUM; size=SMALL; uncertainty=LOW`n"
    $capacityConfig=Get-Content -LiteralPath (Join-Path $control 'project.json') -Raw|ConvertFrom-Json -Depth 100
    $capacityConfig.sourceBindings=@();Write-Json (Join-Path $control 'project.json') $capacityConfig
    $fourteen=@(1..14|ForEach-Object{'CAPACITY_RESULT_'+$_})
    $capacityPolicy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='process-v2-fixture';rules=@([ordered]@{ruleId='CAPACITY_BOUNDARY';requirementReason='Exercise all actual postimages and separate real obligations';effectiveRule='The fixture writes the admitted finite objects and observes their complete postimages.';selectors=[ordered]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('SOURCE_WRITE');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=$fourteen;decisionLocator='fixture:capacity'})}
    Write-Json $policyPath $capacityPolicy
    $writePaths=@(1..251|ForEach-Object{'src/capacity-'+$_.ToString('D3')+'.md'})
    foreach($relative in $writePaths){Write-Utf8 (Join-Path $temp $relative) ('old '+$relative)}
    $capacityPackage=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='PROCESS-V2-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='bounded-capacity';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;projectConfigIdentity=Get-Identity (Join-Path $control 'project.json');actions=@('SOURCE_WRITE');exactPaths=$writePaths;objectIdentities=@($writePaths|ForEach-Object{[ordered]@{path=$_;identity=Get-Identity (Join-Path $temp $_)}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')}
    $capacityAuthPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/capacity-authorization.json';Write-Json $capacityAuthPath $capacityPackage
    $authCore=@(Import-Module (Join-Path $fixtureVersion 'scripts/AuthorizationCheck.psm1') -PassThru)[0]
    $priorCurrent=[Environment]::CurrentDirectory;Push-Location $temp
    try{
      [Environment]::CurrentDirectory=$temp
      $checked=& $authCore.ExportedCommands['Invoke-AiwAuthorizationCheck'] -PackagePath $capacityAuthPath -ObservedActor 'owner-fixture' -ObservedTaskId 'PROCESS-V2-001' -ObservedOwner 'owner-fixture' -ObservedAction @('SOURCE_WRITE') -ObservedPath $writePaths -ObservedIdentity @($capacityPackage.objectIdentities|ForEach-Object{$_.path+'='+$_.identity}) -ProjectConfigPath '.ai-workspace/project.json' -ExpectedProjectConfigIdentity $capacityPackage.projectConfigIdentity -TaskPath '.ai-workspace/tasks/active/PROCESS-V2-001.md' -ExpectedTaskIdentity $capacityPackage.taskIdentity
    }finally{[Environment]::CurrentDirectory=$priorCurrent;Pop-Location}
    Assert-True ($checked.exitCode-eq0) ('capacity-independent-checker-251|'+($checked.output-join';'))
    $capacityInput=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $capacityInput.schemaVersion=5;$capacityInput.evaluationOnly=$false;$capacityInput.expectedTaskIdentity=$capacityPackage.taskIdentity;$capacityInput.expectedProjectConfigIdentity=$capacityPackage.projectConfigIdentity
    $capacityInput.exactPaths=@($writePaths);$capacityInput.protectedPaths=@();$capacityInput.forbiddenPaths=@(($temp.Replace('\','/')+'/never-read-outside-fixture'))
    $capacityInput.authorizationPackagePath=$capacityAuthPath;$capacityInput.expectedAuthorizationIdentity=Get-Identity $capacityAuthPath
    $capacityInput|Add-Member ruleLoad ([pscustomobject]@{mode='FULL'})
    $capacityInput.intentEnvelope.requestedActionKind='SOURCE_WRITE';$capacityInput.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$capacityInput.intentEnvelope.objective='Exercise the exact 251 finite writes and 14 independent result obligations';$capacityInput.intentEnvelope.semanticHints=@();$capacityInput.intentEnvelope.mutationHints=@('source')
    $capacityInput.intentEnvelope.facets.workType=[pscustomobject]@{state='KNOWN';values=@('aiw:implementation')};$capacityInput.intentEnvelope.facets.deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:rule')};$capacityInput.intentEnvelope.facets.stage=[pscustomobject]@{state='KNOWN';values=@('aiw:implementation')}
    Write-Json $discoverPath $capacityInput;$capacityDiscover=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $capacityDiscover 'capacity-source-discover'
    $capacityReceiptPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/capacity-receipt.json';Write-Json $capacityReceiptPath $capacityDiscover.Value.compactReceipt
    $capacityBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$capacityReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $capacityReceiptPath;preparationReceipts=@($capacityDiscover.Value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $capacityBoundaryPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/capacity-admit.json';Write-Json $capacityBoundaryPath $capacityBoundary;Assert-ResolverSuccess (Invoke-Resolver $resolver $capacityBoundaryPath) 'capacity-source-real-admit'
    foreach($relative in $writePaths){Write-Utf8 (Join-Path $temp $relative) ('new '+$relative)}
    $capacityBoundary.mode='FINALIZE_OUTPUT';$capacityBoundary.resultReceipts=@($capacityDiscover.Value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@($writePaths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+(Get-Identity (Join-Path $temp $_))})
    Assert-True ($capacityBoundary.resultReceipts.Count-gt256-and@($capacityBoundary.resultReceipts|Where-Object{$_-clike'CAPACITY_RESULT_*'}).Count-eq14) 'capacity-has-251-real-postimages-plus-14-obligations'
    $capacityFinalPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/capacity-finalize.json';Write-Json $capacityFinalPath $capacityBoundary;$capacityFinal=Invoke-Resolver $resolver $capacityFinalPath;Assert-ResolverSuccess $capacityFinal 'capacity-source-real-original-finalize'
    Assert-True ($capacityFinal.Value.actionOutcome-ceq'OBSERVED') 'capacity-finalize-observes-all-real-postimages'

    # A=257 includes the 251 changed objects and six unchanged read-only members.
    $readPaths=@(252..257|ForEach-Object{'src/capacity-'+$_.ToString('D3')+'.md'});foreach($relative in $readPaths){Write-Utf8 (Join-Path $temp $relative) ('unchanged '+$relative)}
    $reviewPaths=@($writePaths)+@($readPaths)
    $routePackage=$capacityPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$routePackage.actions=@('REVIEW_ROUTE');$routePackage.exactPaths=@($reviewPaths);$routePackage.objectIdentities=@($reviewPaths|ForEach-Object{[pscustomobject]@{path=$_;identity=Get-Identity (Join-Path $temp $_)}})
    $routeAuthPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/route-authorization.json';Write-Json $routeAuthPath $routePackage
    $reviewPackage=$routePackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$reviewPackage.actions=@('REVIEW_EXECUTE');$reviewPackage.grantee='reviewer-fixture';$reviewPackage.reviewIndependence='INDEPENDENT';$reviewPackage|Add-Member candidateWriter 'owner-fixture';$reviewPackage|Add-Member materialContributors @()
    $reviewAuthPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/pure-review.json';Write-Json $reviewAuthPath $reviewPackage
    $routeInput=$capacityInput|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$routeInput.exactPaths=@($reviewPaths);$routeInput.authorizationPackagePath=$routeAuthPath;$routeInput.expectedAuthorizationIdentity=Get-Identity $routeAuthPath;$routeInput.intentEnvelope.requestedActionKind='REVIEW_ROUTE';$routeInput.intentEnvelope.requestedResultKind='HANDOFF';$routeInput.intentEnvelope.objective='Check current author and all 257 candidates before Reviewer creation';$routeInput.intentEnvelope.mutationHints=@();$routeInput.intentEnvelope.facets.workType=[pscustomobject]@{state='KNOWN';values=@('aiw:review')};$routeInput.intentEnvelope.facets.deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:handoff')};$routeInput.intentEnvelope.facets.stage=[pscustomobject]@{state='KNOWN';values=@('aiw:review')}
    Write-Json $discoverPath $routeInput;$routeDiscover=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $routeDiscover 'capacity-review-scope-257-discover'
    Assert-True (Test-Json -Json ($routeDiscover.Value.compactReceipt.binding|ConvertTo-Json -Depth 100) -SchemaFile (Join-Path $fixtureVersion 'AUTHORITY_CONTEXT_SCHEMA.json') -ErrorAction Stop) 'capacity-current-authority-schema-accepts-257-scope'
    $routeReceiptPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/route-receipt.json';Write-Json $routeReceiptPath $routeDiscover.Value.compactReceipt
    $routeBoundary=$capacityBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$routeBoundary.mode='ADMIT_ACTION';$routeBoundary.discoverReceiptPath=$routeReceiptPath;$routeBoundary.expectedDiscoverReceiptIdentity=Get-Identity $routeReceiptPath;$routeBoundary.preparationReceipts=@($routeDiscover.Value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);$routeBoundary.resultReceipts=@();$routeBoundary|Add-Member deliveryContext ([pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='reviewer-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=[pscustomobject]@{path=$reviewAuthPath;identity=Get-Identity $reviewAuthPath}})
    $routeBoundaryPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/route-admit.json';Write-Json $routeBoundaryPath $routeBoundary;$noSelf=Invoke-Resolver $resolver $routeBoundaryPath
    Assert-True ($noSelf.Code-ne0-and$noSelf.Text.Contains('TYPED_EVIDENCE_REQUIRED|SELF_CHECK')) 'real-admit-rejects-missing-author-self-before-creation'
    $requirementsRef=[pscustomobject]@{path=$policyPath;identity=Get-Identity $policyPath}
    $authorSelf=[pscustomobject]@{schemaVersion=1;taskId='PROCESS-V2-001';actor='owner-fixture';candidateObjects=$routePackage.objectIdentities;requirementsRef=$requirementsRef;outcome='PASS';checks=@([pscustomobject]@{id='fixture-current-candidates';method='MODEL_JUDGMENT';outcome='PASS';reason='The isolated fixture actually wrote 251 admitted members and read all 257 current candidate identities; not real model review.';evidenceLocators=@($requirementsRef)});evidenceLocators=@($requirementsRef)}
    $authorSelfPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/author-self.json';Write-Json $authorSelfPath $authorSelf;$routeBoundary.evidenceRefs=@([pscustomobject]@{kind='SELF_CHECK';path=$authorSelfPath;identity=Get-Identity $authorSelfPath})
    Write-Json $routeBoundaryPath $routeBoundary;Assert-ResolverSuccess (Invoke-Resolver $resolver $routeBoundaryPath) 'real-admit-current-author-self-and-257-candidates'
    $authorSelf.actor='wrong-author';Write-Json $authorSelfPath $authorSelf;$routeBoundary.evidenceRefs[0].identity=Get-Identity $authorSelfPath;Write-Json $routeBoundaryPath $routeBoundary;$wrongSelf=Invoke-Resolver $resolver $routeBoundaryPath
    Assert-True ($wrongSelf.Code-ne0-and$wrongSelf.Text.Contains('DELIVERY_REVIEW_WRITER_DRIFT')) 'real-admit-rejects-wrong-author-before-creation'
    $authorSelf.actor='owner-fixture';Write-Json $authorSelfPath $authorSelf;$routeBoundary.evidenceRefs[0].identity=Get-Identity $authorSelfPath
    $routePackage|Add-Member repairReviewPlan ([pscustomobject]@{writer='owner-fixture';reviewer='DEFERRED_VISIBLE_REVIEWER';maxCycles=2;materialContributors=@()});Write-Json $routeAuthPath $routePackage;$routeInput.expectedAuthorizationIdentity=Get-Identity $routeAuthPath
    Write-Json $discoverPath $routeInput;$deferredDiscover=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $deferredDiscover 'deferred-known-writer-discover'
    Write-Json $routeReceiptPath $deferredDiscover.Value.compactReceipt;$routeBoundary.expectedDiscoverReceiptIdentity=Get-Identity $routeReceiptPath;$routeBoundary.PSObject.Properties.Remove('deliveryContext');Write-Json $routeBoundaryPath $routeBoundary;Assert-ResolverSuccess (Invoke-Resolver $resolver $routeBoundaryPath) 'real-admit-validates-known-author-without-reviewer-id-or-host-call'
    Write-Output ('PROCESS_BOUNDARY_CASES_PASS|checks='+$passed+'|scope=251-writes-14-obligations-257-review-members|ceiling=ISOLATED_REAL_BOUNDARIES_NOT_HOST_CREATION')
    return
  }

  Write-Json $discoverPath $discover;$run=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $run 'run'
  $selected=@($run.Value.selectedRuleBlocks|Where-Object{[string]$_.requirementId-ceq'project:process-v2-fixture:SOURCE_BOUND_STANDARD'})
  Assert-True ($run.Code-eq0-and[int]$run.Value.compactReceipt.schemaVersion-eq3-and$selected.Count-eq1-and[string]$selected[0].fullText-clike'*Base project rule dependency*Selected project standard rule body*') 'source-bound-project-standard-loads-selected-section-and-dependency'
  $nativeRoundtrip=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$resolver,'-InputPath',$discoverPath,'-AsJson') -GroupId 'process-native-unicode-roundtrip'
  $nativeValue=$nativeRoundtrip.StdoutText|ConvertFrom-Json -Depth 100
  Assert-True ($nativeRoundtrip.Code-eq0-and$nativeRoundtrip.StdoutText-cnotmatch'[^\x00-\x7f]'-and(@($nativeValue.selectedRuleBlocks.fullText)-join"`n")-ceq(@($run.Value.selectedRuleBlocks.fullText)-join"`n")) 'native-json-roundtrip-retains-complete-unicode-rule-bodies'

  # Keep the cold Input4/compact3 case above as a real compatibility test.
  $loadInput=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $loadInput.schemaVersion=5;$loadInput.evaluationOnly=$false
  $loadInput|Add-Member ruleLoad ([pscustomobject]@{mode='FULL'})
  $loadPath=Join-Path $temp 'load-input.json';Write-Json $loadPath $loadInput
  $full=Invoke-Resolver $resolver $loadPath;Assert-ResolverSuccess $full 'input5-full'
  Assert-True ($full.Value.compactReceipt.schemaVersion-eq4-and$full.Value.compactReceipt.binding.schemaVersion-eq3-and$full.Value.modelView.loadDecision.effectiveMode-ceq'FULL'-and$full.Value.modelView.uniqueUnits.Count-gt0) 'input5-current-full-compact4-authority3-complete-units'
  Assert-True (@($full.Value.compactReceipt.bodyCoverage.units|Where-Object{$_.orderedDependencies-isnot[Array]}).Count-eq0) 'every-complete-unit-preserves-array-dependencies-including-zero-and-singleton'
  $coveragePath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/coverage.json';Write-Json $coveragePath $full.Value.compactReceipt
  $loadInput.ruleLoad=[pscustomobject]@{mode='REUSE';previousCoverageRef=[pscustomobject]@{path=$coveragePath;identity=(Get-Identity $coveragePath)}};Write-Json $loadPath $loadInput
  $locked=[IO.File]::Open($coveragePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{$reuse=Invoke-Resolver $resolver $loadPath;Assert-ResolverSuccess $reuse 'input5-reuse'}finally{$locked.Dispose()}
  Assert-True ($reuse.Value.modelView.loadDecision.effectiveMode-ceq'FULL'-and$reuse.Value.modelView.uniqueUnits.Count-eq$full.Value.modelView.uniqueUnits.Count-and$reuse.Value.compactReceipt.selectedObligations.Count-eq$full.Value.compactReceipt.selectedObligations.Count-and$reuse.Value.compactReceipt.bodyCoverage.PSObject.Properties.Name-cnotcontains'previousCoverageRef') 'legacy-reuse-loads-complete-current-rules-and-obligations'
  $originalLoadPolicy=[IO.File]::ReadAllText($policyPath)
  $loadPolicy=$originalLoadPolicy|ConvertFrom-Json -Depth 100;$loadPolicy.rules[0].resultRequirements+=@('CURRENT_NEW_OBLIGATION');Write-Json $policyPath $loadPolicy
  Write-Json $loadPath $loadInput;$delta=Invoke-Resolver $resolver $loadPath;Assert-ResolverSuccess $delta 'input5-delta'
  Assert-True ($delta.Value.modelView.loadDecision.effectiveMode-ceq'FULL'-and$delta.Value.modelView.uniqueUnits.Count-gt0-and'CURRENT_NEW_OBLIGATION'-cin@($delta.Value.compactReceipt.selectedObligations.resultRequirements)) 'changed-rule-obligation-returns-complete-current-units'
  [IO.File]::WriteAllText($policyPath,$originalLoadPolicy,$utf8)
  $loadInput.ruleLoad.previousCoverageRef.identity='1|'+('A'*64);Write-Json $loadPath $loadInput
  $fallback=Invoke-Resolver $resolver $loadPath;Assert-ResolverSuccess $fallback 'input5-invalid-coverage'
  Assert-True ($fallback.Value.modelView.loadDecision.effectiveMode-ceq'FULL'-and$fallback.Value.modelView.uniqueUnits.Count-eq$full.Value.modelView.uniqueUnits.Count) 'invalid-coverage-falls-back-to-current-full-in-same-call'
  $loadInput.ruleLoad=[pscustomobject]@{mode='REUSE'};Write-Json $loadPath $loadInput
  $missing=Invoke-Resolver $resolver $loadPath;Assert-ResolverSuccess $missing 'input5-missing-coverage'
  Assert-True ($missing.Value.modelView.loadDecision.effectiveMode-ceq'FULL') 'missing-coverage-falls-back-without-another-discover'
  $loadInput.ruleLoad=[pscustomobject]@{mode='FULL';preloadSteps=@([pscustomobject]@{stepId='unapproved';role='EXECUTOR';phase='VERIFY';intentEnvelope=$baseIntent;exactPaths=@()})};Write-Json $loadPath $loadInput
  $unapproved=Invoke-Resolver $resolver $loadPath
  Assert-True ($unapproved.Code-ne0-and$unapproved.Value.reason-clike'*RULE_LOAD_PRELOAD_RETIRED*') 'future-preload-is-retired'

  Import-Module (Join-Path $fixtureVersion 'scripts/ProcessRequirementDisplay.psm1') -Force
  $fullDisplay=Get-AiwProcessDisplay -Result $full.Value
  $reuseDisplay=Get-AiwProcessDisplay -Result $reuse.Value
  Assert-True ($fullDisplay.text.EndsWith('AIW-END')-and$reuseDisplay.contextBodyReuse-ceq'FULL'-and$reuseDisplay.currentRules.Count-eq$fullDisplay.currentRules.Count-and$reuseDisplay.bodyUnits.Count-eq$fullDisplay.bodyUnits.Count-and$reuseDisplay.text.Contains('Current rules')) 'single-complete-model-text-retains-current-rule-map-and-bodies'
  $loadInput.ruleLoad=[pscustomobject]@{mode='REUSE';previousCoverageRef=[pscustomobject]@{path=$coveragePath;identity=(Get-Identity $coveragePath)}}
  $originalLoadConfig=[IO.File]::ReadAllText((Join-Path $control 'project.json'))
  $deniedLoadConfig=$originalLoadConfig|ConvertFrom-Json -Depth 100;$deniedLoadConfig.sourceBindings[0].allowedPaths=@([pscustomobject]@{kind='FILE';locator='never-adopted.md'});Write-Json (Join-Path $control 'project.json') $deniedLoadConfig
  $loadInput.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');Write-Json $loadPath $loadInput
  $deniedLoad=Invoke-Resolver $resolver $loadPath
  Assert-True ($deniedLoad.Code-ne0-and$deniedLoad.Value.status-cne'PASS'-and$deniedLoad.Text-cmatch'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS') 'reuse-does-not-swallow-current-source-permission-denial-as-full-fallback'
  [IO.File]::WriteAllText((Join-Path $control 'project.json'),$originalLoadConfig,$utf8)
  # Real ordinary scope growth: the current checker admits the new exact package;
  # breakpoints observe that neither selected-body assembly nor display ran.
  $savedTask=[IO.File]::ReadAllBytes($taskPath);$savedPolicy=[IO.File]::ReadAllBytes($policyPath)
  $savedActor=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID='owner-fixture'
    Write-Utf8 $taskPath "# PROCESS-V2-001 — current rule loading`n`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; risk=MEDIUM; size=SMALL; uncertainty=LOW`n"
    $rp=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100
    foreach($axis in @('roles','phases','actionKinds','resultKinds')){$rp.rules[0].selectors.$axis=@('*')}
    $rp.rules[0].selectors.semanticTerms=@()
    $rp.rules+=@([pscustomobject]@{ruleId='MIGRATION_ONLY';requirementReason='Additional rule when migration files enter scope';effectiveRule='MIGRATION_COMPLETE_CONDITION_AND_DEPENDENCY';selectors=@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@('migrations/');capabilities=@();semanticTerms=@()};preparationRequirements=@('MIGRATION_PREP');resultRequirements=@('MIGRATION_RESULT');decisionLocator='fixture:migration'})
    Write-Json $policyPath $rp
    Write-Utf8 (Join-Path $temp 'src/base.txt') 'before'
    $pkg=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='PROCESS-V2-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='ordinary-scope';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;projectConfigIdentity=Get-Identity (Join-Path $control 'project.json');actions=@('SOURCE_WRITE');exactPaths=@('src/base.txt');objectIdentities=@(@{path='src/base.txt';identity=Get-Identity (Join-Path $temp 'src/base.txt')});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')}
    $rd=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture';$pa=Join-Path $rd 'scope-original.json';Write-Json $pa $pkg
    $ri=$loadInput|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $ri.ruleLoad=[pscustomobject]@{mode='FULL'};$ri.expectedProjectConfigIdentity=$pkg.projectConfigIdentity;$ri.expectedTaskIdentity=$pkg.taskIdentity;$ri.recoveryState='CURRENT'
    $ri.authorizationPackagePath=$pa;$ri.expectedAuthorizationIdentity=Get-Identity $pa;$ri.exactPaths=@($pkg.exactPaths);$ri.protectedPaths=@('.ai-workspace/');$ri.forbiddenPaths=@('private/')
    $ri.intentEnvelope.requestedActionKind='SOURCE_WRITE';$ri.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$ri.intentEnvelope.objective='Implement the current ordinary source change';$ri.intentEnvelope.semanticHints=@();$ri.intentEnvelope.mutationHints=@('source')
    foreach($axis in @('domain','workType','deliverableType','stage')){$ri.intentEnvelope.facets.$axis=[pscustomobject]@{state='UNKNOWN';values=@()}}
    Write-Json $loadPath $ri;$initial=Invoke-Resolver $resolver $loadPath;Assert-ResolverSuccess $initial 'ordinary-scope-initial-full'
    $observed=$initial.Value.compactReceipt.sourceObservation
    Assert-True ($observed.schemaVersion-eq2-and$observed.workRoute.actor-ceq'owner-fixture'-and$observed.workRoute.role-ceq'TASK_OWNER'-and$observed.workRoute.phase-ceq'IMPLEMENT'-and($observed.loadedRuleIds-join'|')-ceq(@($initial.Value.compactReceipt.selectedObligations.requirementId)-join'|')) 'current-full-observes-real-work-route-and-all-loaded-rule-ids'
    $rr=Join-Path $rd 'scope-receipt.json';Write-Json $rr $initial.Value.compactReceipt
    $rb=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$rr;expectedDiscoverReceiptIdentity=Get-Identity $rr;preparationReceipts=@($initial.Value.compactReceipt.selectedObligations|ForEach-Object preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $bp=Join-Path $rd 'scope-boundary.json';Write-Json $bp $rb;Assert-ResolverSuccess (Invoke-Resolver $resolver $bp) 'ordinary-scope-initial-admit'
    $pkg.exactPaths+=@('src/extra.txt');$pkg.objectIdentities+=@(@{path='src/extra.txt';identity='NEW'});$pb=Join-Path $rd 'scope-expanded.json';Write-Json $pb $pkg
    $rb.actionRebind=@{authorizationRef=@{path=$pb;identity=Get-Identity $pb};intentEnvelope=$ri.intentEnvelope;recoveryState='CURRENT'}
    $next=Join-Path $rd 'scope-rebound.json';Write-Json $bp $rb
    $global:RuleBodyCalls=0;$global:RuleDisplayCalls=0
    $probes=@(Set-PSBreakpoint -Command Get-AiwScopedProjectContent -Action {$global:RuleBodyCalls++};Set-PSBreakpoint -Command Get-AiwProcessDisplay -Action {$global:RuleDisplayCalls++})
    try{$global:LASTEXITCODE=0;$output=@(& $resolver -InputPath $bp -CompactReceiptPath $next -AsJson);$code=$global:LASTEXITCODE;$actual=($output-join"`n")|ConvertFrom-Json -Depth 100}
    finally{$probes|Remove-PSBreakpoint}
    Assert-True ($code-eq0-and$actual.status-ceq'PASS'-and-not$actual.ruleBodyLoaded-and$global:RuleBodyCalls-eq0-and$global:RuleDisplayCalls-eq0) ('ordinary-new-file-admits-with-zero-body-and-display|'+($output-join''))
    $newReceipt=Get-Content $next -Raw|ConvertFrom-Json -Depth 100
    Assert-True ('src/extra.txt'-cin$newReceipt.binding.exactScope-and$newReceipt.binding.authorizationIdentity-ceq(Get-Identity $pb)) 'rebound-receipt-binds-current-exact-scope-and-package'
    Write-Utf8 (Join-Path $temp 'src/base.txt') 'after';Write-Utf8 (Join-Path $temp 'src/extra.txt') 'new ordinary file'
    $final=$rb|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$final.PSObject.Properties.Remove('actionRebind');$final.mode='FINALIZE_OUTPUT';$final.discoverReceiptPath=$next;$final.expectedDiscoverReceiptIdentity=Get-Identity $next
    $final.resultReceipts=@($newReceipt.selectedObligations|ForEach-Object resultRequirements|Sort-Object -Unique)+@($pkg.exactPaths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+(Get-Identity (Join-Path $temp $_))})
    Write-Json $bp $final;Assert-ResolverSuccess (Invoke-Resolver $resolver $bp) 'ordinary-new-file-original-finalize'
    # Writing companion test code is still this implementation activity. The
    # saved current compact, actual checker and original F must all bind TEST_WRITE.
    $testPackage=$pkg|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $testPackage.actions=@('TEST_WRITE');$testPackage.exactPaths=@('tests/companion.ps1');$testPackage.objectIdentities=@([pscustomobject]@{path='tests/companion.ps1';identity='NEW'})
    $testPackagePath=Join-Path $rd 'companion-package.json';Write-Json $testPackagePath $testPackage
    $testIntent=$ri.intentEnvelope|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $testIntent.objective='Add companion test code for this implementation; no test execution yet';$testIntent.requestedActionKind='TEST_WRITE';$testIntent.pathHints=@('tests/companion.ps1');$testIntent.mutationHints=@()
    $testBoundary=$rb|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $testBoundary.discoverReceiptPath=$next;$testBoundary.expectedDiscoverReceiptIdentity=Get-Identity $next
    $testBoundary.actionRebind=[pscustomobject]@{authorizationRef=[pscustomobject]@{path=$testPackagePath;identity=(Get-Identity $testPackagePath)};intentEnvelope=$testIntent;recoveryState='CURRENT'}
    $testCompact=Join-Path $rd 'companion-rebound.json';$testBoundaryPath=Join-Path $rd 'companion-boundary.json';Write-Json $testBoundaryPath $testBoundary
    $global:RuleBodyCalls=0;$global:RuleDisplayCalls=0
    $probes=@(Set-PSBreakpoint -Command Get-AiwScopedProjectContent -Action {$global:RuleBodyCalls++};Set-PSBreakpoint -Command Get-AiwProcessDisplay -Action {$global:RuleDisplayCalls++})
    try{$global:LASTEXITCODE=0;$output=@(& $resolver -InputPath $testBoundaryPath -CompactReceiptPath $testCompact -AsJson);$code=$global:LASTEXITCODE;$testAdmission=($output-join"`n")|ConvertFrom-Json -Depth 100}finally{$probes|Remove-PSBreakpoint}
    Assert-True ($code-eq0-and$testAdmission.status-ceq'PASS'-and$global:RuleBodyCalls-eq0-and$global:RuleDisplayCalls-eq0) ('companion-test-code-current-admit-with-zero-assembly|'+($output-join''))
    $testReceipt=Get-Content -LiteralPath $testCompact -Raw|ConvertFrom-Json -Depth 100
    Assert-True ($testReceipt.intentEnvelope.requestedActionKind-ceq'TEST_WRITE'-and$testReceipt.binding.authorizedActions[0]-ceq'TEST_WRITE'-and$testReceipt.binding.authorizationIdentity-ceq(Get-Identity $testPackagePath)-and$testReceipt.selectionIdentity-cne$newReceipt.selectionIdentity-and($testReceipt.sourceObservation.loadedRuleIds-join'|')-ceq($observed.loadedRuleIds-join'|')) 'companion-code-saved-compact-current-action-and-original-loaded-sources'
    Write-Utf8 (Join-Path $temp 'tests/companion.ps1') "# Companion implementation test code; not executed by this fixture."
    $testFinal=$testBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$testFinal.PSObject.Properties.Remove('actionRebind');$testFinal.mode='FINALIZE_OUTPUT';$testFinal.discoverReceiptPath=$testCompact;$testFinal.expectedDiscoverReceiptIdentity=Get-Identity $testCompact
    $testFinal.resultReceipts=@($testReceipt.selectedObligations|ForEach-Object resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|tests/companion.ps1|'+(Get-Identity (Join-Path $temp 'tests/companion.ps1')))
    Write-Json $testBoundaryPath $testFinal;Assert-ResolverSuccess (Invoke-Resolver $resolver $testBoundaryPath) 'companion-code-original-F-uses-saved-current-compact'
    # Old permission never expands just because the caller supplies a new path.
    $rb.actionRebind.authorizationRef=@{path=$pa;identity=Get-Identity $pa};$rb.actionRebind.intentEnvelope=$ri.intentEnvelope|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$rb.actionRebind.intentEnvelope.pathHints=@('src/extra.txt')
    function Invoke-RebindFailure([string]$Name,[string]$Reason){Write-Json $bp $rb;$global:LASTEXITCODE=0;$lines=@(& $resolver -InputPath $bp -CompactReceiptPath (Join-Path $rd ($Name+'.json')) -AsJson);Assert-True ($global:LASTEXITCODE-ne0-and($lines-join'').Contains($Reason)) $Name}
    Invoke-RebindFailure 'old-package-cannot-expand' 'ACTION_REBIND_INTENT_SCOPE'
    $rb.actionRebind.intentEnvelope=$ri.intentEnvelope;$rb.actionRebind.authorizationRef=@{path=$pb;identity=Get-Identity $pb}
    $rb.actionRebind.recoveryState='FULL_COLD';Invoke-RebindFailure 'recovery-requires-complete-load' 'RULE_LOAD_REQUIRED';$rb.actionRebind.recoveryState='CURRENT'
    $rb.actionRebind.intentEnvelope=$ri.intentEnvelope|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$rb.actionRebind.intentEnvelope.requestedActionKind='TEST_RUN';Invoke-RebindFailure 'actual-test-action-requires-complete-load' 'RULE_LOAD_REQUIRED';$rb.actionRebind.intentEnvelope=$ri.intentEnvelope
    $pkg.objectIdentities=@($pkg.exactPaths|ForEach-Object{@{path=$_;identity=Get-Identity (Join-Path $temp $_)}});$pkg.exactPaths+=@('migrations/change.sql');$pkg.objectIdentities+=@(@{path='migrations/change.sql';identity='NEW'});Write-Json $pb $pkg;$rb.actionRebind.authorizationRef.identity=Get-Identity $pb
    Invoke-RebindFailure 'additional-path-rule-requires-complete-load' 'RULE_LOAD_REQUIRED|SELECTION_CHANGED'
    $ri.exactPaths=@($pkg.exactPaths);$ri.authorizationPackagePath=$pb;$ri.expectedAuthorizationIdentity=Get-Identity $pb;Write-Json $loadPath $ri;$expanded=Invoke-Resolver $resolver $loadPath;Assert-ResolverSuccess $expanded 'migration-current-full'
    Assert-True ($expanded.Value.modelView.loadDecision.effectiveMode-ceq'FULL'-and(@($expanded.Value.modelView.uniqueUnits.fullText)-join'').Contains('MIGRATION_COMPLETE_CONDITION_AND_DEPENDENCY')-and$expanded.Value.modelView.uniqueUnits.Count-gt$initial.Value.modelView.uniqueUnits.Count) 'additional-rule-load-returns-whole-current-closure'
    # The real source reader refuses changed adopted bytes; no reuse fallback.
    $bytes=[IO.File]::ReadAllBytes((Join-Path $temp 'docs/base.md'))
    try{Write-Utf8 (Join-Path $temp 'docs/base.md') 'unadopted bytes';$ri.exactPaths=@('src/base.txt');$rb.actionRebind.authorizationRef=@{path=$pa;identity=Get-Identity $pa};Invoke-RebindFailure 'current-source-byte-drift-refused' 'CONTENT_IDENTITY_DRIFT'}finally{[IO.File]::WriteAllBytes((Join-Path $temp 'docs/base.md'),$bytes)}
  }finally{[IO.File]::WriteAllBytes($taskPath,$savedTask);[IO.File]::WriteAllBytes($policyPath,$savedPolicy);$env:CODEX_THREAD_ID=$savedActor}
  # Exercise both real loading contexts through the public boundary. This
  # is not a provider call or a machine proof of semantic grant coverage.
  $externalSavedPolicy=[IO.File]::ReadAllBytes($policyPath)
  try{
    $externalPolicy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='process-v2-fixture';rules=@([pscustomobject]@{ruleId='LOCAL_TOOL_GRANT';requirementReason='A bounded local integration tool is permitted';effectiveRule='The named fixture executor may call the local fixture tool once, with no network, account changes, publication or retry. Unknown consumption stops.';selectors=[pscustomobject]@{profiles=@('*');roles=@('*');phases=@('EXTERNAL');actionKinds=@('EXTERNAL');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:explicit-project-grant'});externalAuthorization=[pscustomobject]@{schemaVersion=1;mode='PROJECT_PREAUTHORIZED';grantRuleIds=@('LOCAL_TOOL_GRANT')}}
    Write-Json $policyPath $externalPolicy
    $externalInput=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $externalInput.schemaVersion=5;$externalInput.evaluationOnly=$false;$externalInput.protectedPaths=@();$externalInput.expectedTaskIdentity=Get-Identity $taskPath;$externalInput.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json')
    $externalInput|Add-Member ruleLoad ([pscustomobject]@{mode='FULL'})
    $externalInput.intentEnvelope.objective='Load the current complete project grant for a direct local tool request';$externalInput.intentEnvelope.requestedActionKind='EXTERNAL';$externalInput.intentEnvelope.requestedResultKind='EXTERNAL_RESULT';$externalInput.intentEnvelope.semanticHints=@()
    $externalPath=Join-Path $temp 'external-load.json';Write-Json $externalPath $externalInput
    $externalTask=Invoke-Resolver $resolver $externalPath;Assert-ResolverSuccess $externalTask 'existing-task-project-external-load'
    Assert-True ($externalTask.Value.compactReceipt.binding.phase-ceq'EXTERNAL'-and$externalTask.Value.compactReceipt.binding.authorizedActions.Count-eq0-and$externalTask.Value.compactReceipt.sourceObservation.workRoute.phase-ceq'PLAN'-and$externalTask.Value.projectExternalAuthorization.selectedGrantRuleIds[0]-ceq'LOCAL_TOOL_GRANT') 'project-external-load-keeps-real-task-route-and-no-per-call-package'
    $externalInput.contextType='PROJECT_EXTERNAL';$externalInput.PSObject.Properties.Remove('readOnlyContext');$externalInput.taskPath='NOT_APPLICABLE';$externalInput.expectedTaskIdentity='NOT_APPLICABLE'
    $externalInput|Add-Member requestContext ([pscustomobject]@{sessionId='owner-fixture';requestId='external-load-fixture';role='EXECUTOR';phase='EXTERNAL';profile='STANDARD'})
    Write-Json $externalPath $externalInput;$externalNoTask=Invoke-Resolver $resolver $externalPath;Assert-ResolverSuccess $externalNoTask 'taskless-project-external-load'
    Assert-True ($externalNoTask.Value.compactReceipt.binding.contextType-ceq'PROJECT_EXTERNAL'-and$externalNoTask.Value.compactReceipt.binding.taskId-ceq'NOT_APPLICABLE'-and$externalNoTask.Value.compactReceipt.sourceObservation.schemaVersion-eq1-and-not$externalNoTask.Value.compactReceipt.authorityGranted) 'taskless-external-load-keeps-honest-intent-and-no-task-authority'
    Assert-True (Test-Json -Json ($externalNoTask.Value.compactReceipt.binding|ConvertTo-Json -Depth 100) -SchemaFile (Join-Path $fixtureVersion 'AUTHORITY_CONTEXT_SCHEMA.json') -ErrorAction Stop) 'taskless-external-authority3-matches-public-schema'
    $externalCompact=Join-Path $temp 'external-load-compact.json';Write-Json $externalCompact $externalNoTask.Value.compactReceipt
    foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
      $boundary=[ordered]@{schemaVersion=3;mode=$mode;discoverReceiptPath=$externalCompact;expectedDiscoverReceiptIdentity=Get-Identity $externalCompact;preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
      $boundaryPath=Join-Path $temp 'external-invalid-boundary.json';Write-Json $boundaryPath $boundary;$denied=Invoke-Resolver $resolver $boundaryPath
      Assert-True ($denied.Code-ne0-and$denied.Text.Contains('PROJECT_EXTERNAL_LOAD_HAS_NO_ACTION_BOUNDARY')) ('external-load-is-not-'+$mode)
    }
    $externalPolicy.externalAuthorization.grantRuleIds=@('MISSING_GRANT');Write-Json $policyPath $externalPolicy
    $badGrant=Invoke-Resolver $resolver $externalPath
    Assert-True ($badGrant.Code-ne0-and$badGrant.Text.Contains('EXTERNAL_AUTHORIZATION_GRANT_RULE_UNBOUND')) 'unbound-grant-cannot-become-successful-full-load'
    $externalPolicy.externalAuthorization=[pscustomobject]@{schemaVersion=1;mode='PER_ACTION'};Write-Json $policyPath $externalPolicy
    $defaultMode=Invoke-Resolver $resolver $externalPath
    Assert-True ($defaultMode.Code-ne0-and$defaultMode.Text.Contains('EXTERNAL_ACTION_PACKAGE_OR_SELECTED_PROJECT_GRANT_REQUIRED')) 'per-action-mode-cannot-use-taskless-direct-load'
  }finally{[IO.File]::WriteAllBytes($policyPath,$externalSavedPolicy)}
  if($RuleLoadingOnly){Write-Output ('PROCESS_RULE_LOADING_PASS|checks='+$passed+'|scope=current-full-and-real-action-rebind');return}

  # A non-Git SAME_ROOT observer must not touch Git, even with bad overrides.
  Import-Module (Join-Path $fixtureVersion 'scripts/ExecutionTargetContext.psm1') -Force
  $priorGitDir=$env:GIT_DIR
  try{$env:GIT_DIR=Join-Path $temp 'deliberately-missing-git';$same=Resolve-AiwExecutionTargetContext -ProjectRoot $temp -ProjectId 'process-v2-fixture' -TaskPath $taskPath}
  finally{$env:GIT_DIR=$priorGitDir}
  Assert-True ($same.targetKind-ceq'SAME_ROOT'-and$same.executionRoot-ceq$temp-and$null-eq$same.targetObservation) 'same-root-observer-never-probes-git'

  function TargetGit([string]$Root,[string[]]$Arguments){
    $output=@(& git -C $Root @Arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
    if($code-ne0){throw ('TARGET_FIXTURE_GIT_FAILED|'+$code+'|'+($output-join';'))}
    return ($output-join"`n").Trim()
  }
  function RejectTarget([scriptblock]$Operation,[string]$Reason,[string]$Name){
    $rejected=$false;try{$null=& $Operation}catch{if($_.Exception.Message-cnotmatch$Reason){throw};$rejected=$true}
    Assert-True $rejected $Name
  }
  $originalTargetTask=[IO.File]::ReadAllText($taskPath)
  $null=TargetGit $temp @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','Synthetic target baseline')
  $targetRoot=Join-Path $temp 'target-worktree';$null=TargetGit $temp @('worktree','add','-q','-b','w2-target-fixture',$targetRoot,'HEAD')
  Write-Utf8 (Join-Path $targetRoot '.ai-workspace/project.json') '{"shadow":"must never supply authority"}'
  $decisionPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/target-decision.txt';Write-Utf8 $decisionPath 'Fixture selection of this exact same-repository worktree.'
  $descriptorPath=Join-Path $control 'runtime/PROCESS-V2-001/owner-fixture/execution-target.json'
  $baseline=TargetGit $targetRoot @('rev-parse','HEAD')
  $descriptor=[ordered]@{schemaVersion=1;kind='EXECUTION_TARGET';projectId='process-v2-fixture';taskId='PROCESS-V2-001';controlRoot=$temp;targetKind='GIT_WORKTREE';targetRoot=$targetRoot;gitBinding=[ordered]@{commonGitDir=[IO.Path]::GetFullPath((TargetGit $temp @('rev-parse','--path-format=absolute','--git-common-dir')));worktreeGitDir=[IO.Path]::GetFullPath((TargetGit $targetRoot @('rev-parse','--absolute-git-dir')));gitTop=$targetRoot;branch='w2-target-fixture';baselineCommit=$baseline};selectionDecisionRef=[ordered]@{path=$decisionPath;identity=(Get-Identity $decisionPath)};hostWorktreeRef=$null}
  Write-Json $descriptorPath $descriptor;$targetRef=[pscustomobject]@{path=$descriptorPath;identity=(Get-Identity $descriptorPath)}
  Write-Utf8 $taskPath ($originalTargetTask+"`n- Execution target: "+$descriptorPath+'#'+$targetRef.identity)
  $observed=Resolve-AiwExecutionTargetContext -ProjectRoot $temp -ProjectId 'process-v2-fixture' -TaskPath $taskPath -ExecutionTargetRef $targetRef -ProtectedPaths @('.ai-workspace/')
  Assert-True ($observed.targetKind-ceq'GIT_WORKTREE'-and$observed.controlRoot-ceq$temp-and$observed.executionRoot-ceq$targetRoot-and$observed.targetObservation.head-ceq$baseline) 'actual-same-repository-worktree-ignores-target-shadow-control-plane'
  $null=TargetGit $targetRoot @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','Synthetic current head')
  $advanced=Resolve-AiwExecutionTargetContext -ProjectRoot $temp -ProjectId 'process-v2-fixture' -TaskPath $taskPath -ExecutionTargetRef $targetRef
  Assert-True ($advanced.targetObservation.head-cne$baseline-and$descriptor.gitBinding.baselineCommit-ceq$baseline) 'target-initial-baseline-and-current-head-are-separate-observations'
  RejectTarget {Resolve-AiwExecutionTargetContext -ProjectRoot $temp -ProjectId 'process-v2-fixture' -TaskPath $taskPath -ExecutionTargetRef $targetRef -ForbiddenPaths @('target-worktree')} 'EXECUTION_TARGET_PROTECTED_PATH' 'mapped-target-protection-rejects-before-candidate-metadata'
  try{$env:GIT_DIR=Join-Path $temp 'override';RejectTarget {Resolve-AiwExecutionTargetContext -ProjectRoot $temp -ProjectId 'process-v2-fixture' -TaskPath $taskPath -ExecutionTargetRef $targetRef} 'EXECUTION_TARGET_GIT_OVERRIDE' 'worktree-observer-rejects-git-environment-override'}finally{$env:GIT_DIR=$priorGitDir}
  Write-Utf8 $decisionPath 'Changed original selection decision.'
  RejectTarget {Resolve-AiwExecutionTargetContext -ProjectRoot $temp -ProjectId 'process-v2-fixture' -TaskPath $taskPath -ExecutionTargetRef $targetRef} 'EXECUTION_TARGET_EVIDENCE_DRIFT' 'target-original-decision-byte-drift-rejects'
  [IO.File]::WriteAllText($taskPath,$originalTargetTask,$utf8)
  if($FixtureContractOnly){Write-Output ('PARTIAL|FIXTURE_CONTRACT_ONLY|process-runtime-v2|target=first-resolver-selection|code='+$run.Code+'|status='+$run.Value.status+'|reason='+$(if($null-ne$run.Value.PSObject.Properties['reason']){$run.Value.reason}else{'NOT_REPORTED'}));return}
  $originalPolicyText=[IO.File]::ReadAllText($policyPath);$standardPath=Join-Path $temp 'docs/standard.md';$originalStandardText=[IO.File]::ReadAllText($standardPath)
  [IO.File]::WriteAllText($standardPath,$originalStandardText.TrimEnd("`n").Replace("`n","`r`n"),$utf8)
  $sectionPolicy=$sourcePolicy|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$sectionIdentity=Get-Identity $standardPath;$sectionPolicy.rules[0].source.documents[1].identity=$sectionIdentity
  Refresh-FixtureSourceRevision $sectionPolicy.rules[0].source
  Write-Json $policyPath $sectionPolicy;Write-Json $discoverPath $discover;$sectionRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $sectionRun 'sectionRun'
  Assert-True ($sectionRun.Code-eq0-and$sectionRun.Text.Contains('Selected project standard rule body')-and-not$sectionRun.Text.Contains('Intro.')-and(Get-Identity $standardPath)-ceq$sectionIdentity) 'marked-section-crlf-no-final-lf-selects-body-and-keeps-source-bytes'
  [IO.File]::WriteAllText($standardPath,$originalStandardText,$utf8);[IO.File]::WriteAllText($policyPath,$originalPolicyText,$utf8)
  $observer=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $observer.contextType='PROJECT_READ_ONLY';$observer.taskPath='NOT_APPLICABLE';$observer.expectedTaskIdentity='NOT_APPLICABLE';$observer.observedActor='temporary-observer'
  $observer.readOnlyContext=[pscustomobject]@{sessionId='temporary-observer';requestId='bounded-observation';role='EXECUTOR';phase='PLAN';profile='STANDARD'}
  $observer.intentEnvelope.objective='Bounded observation '+('context '*1200)
  $observer.intentEnvelope.semanticHints=@('source-bound')
  $observer.intentEnvelope.pathHints=@('docs/')
  $observer.exactPaths=@(1..110|ForEach-Object{'docs/'+('bounded-'*10)+$_.ToString()+'.md'})
  Write-Json $discoverPath $observer;$observerRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $observerRun 'observerRun'
  Assert-True ($observerRun.Code-eq0-and$observerRun.Value.compactReceipt.binding.actor-ceq'temporary-observer'-and[Text.Encoding]::UTF8.GetByteCount(($observerRun.Value.compactReceipt.binding|ConvertTo-Json -Depth 30 -Compress))-gt8192) 'temporary-taskless-observer-accepts-long-objective-and-large-exact-authority'
  Assert-True ($utf8.GetByteCount(($observer.intentEnvelope|ConvertTo-Json -Depth 30 -Compress))-gt4096-and$observerRun.Value.compactReceipt.intentEnvelope.objective-ceq$observer.intentEnvelope.objective) 'ascii-objective-over-old-envelope-limit-with-normal-hints-preserved'
  $observer.readOnlyContext.role='REVIEWER';$observer.intentEnvelope.objective='核查当前目标与约束：'+('明确目标保持精确范围。'*600)
  Write-Json $discoverPath $observer;$chineseRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $chineseRun 'chineseRun'
  Assert-True ($chineseRun.Code-eq0-and$utf8.GetByteCount(($observer.intentEnvelope|ConvertTo-Json -Depth 30 -Compress))-gt4096-and$chineseRun.Value.compactReceipt.intentEnvelope.objective-ceq$observer.intentEnvelope.objective) 'chinese-objective-over-old-envelope-limit-with-temporary-reviewer-observation'
  $badObserver=$observer|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badObserver.intentEnvelope.objective=42
  Write-Json $discoverPath $badObserver
  Assert-True ((Invoke-Resolver $resolver $discoverPath).Code-ne0) 'large-envelope-still-rejects-objective-type-drift'
  $duplicateIntent=($observer|ConvertTo-Json -Depth 100 -Compress).Replace('"objective":','"objective":"duplicate","objective":')
  [IO.File]::WriteAllText($discoverPath,$duplicateIntent+"`n",$utf8)
  Assert-True ((Invoke-Resolver $resolver $discoverPath).Code-ne0) 'large-envelope-still-rejects-duplicate-objective-key'
  $badObserver=$observer|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badObserver.intentEnvelope.pathHints=@('outside-scope/')
  Write-Json $discoverPath $badObserver
  Assert-True ((Invoke-Resolver $resolver $discoverPath).Code-ne0) 'large-envelope-still-rejects-hint-outside-exact-scope'
  $observer.intentEnvelope.requestedActionKind='SOURCE_WRITE';Write-Json $discoverPath $observer;$observerWrite=Invoke-Resolver $resolver $discoverPath
  Assert-True ($observerWrite.Code-ne0) 'taskless-observation-never-authorizes-write'
  $observer.intentEnvelope.requestedActionKind='NONE';$observer.intentEnvelope.requestedResultKind='REVIEW_VERDICT';Write-Json $discoverPath $observer
  Assert-True ((Invoke-Resolver $resolver $discoverPath).Code-ne0) 'taskless-observation-never-substitutes-formal-review'
  $manyPolicy=$sourcePolicy|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $manyDocuments=@(1..17|ForEach-Object{
    $rel="docs/extra-$_.md";[IO.File]::WriteAllText((Join-Path $temp $rel),"Rule $_`r`nEquivalent format",$utf8)
    [pscustomobject]@{sourceId="DOC_$_";locator=$rel;identity=Get-Identity (Join-Path $temp $rel);mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@($(if($_-gt1){'DOC_'+($_-1)}))}
  })
  $manyPolicy.rules[0].source=[pscustomobject]@{rootSourceId='DOC_17';documents=$manyDocuments}
  $manyBindings=@(Get-AiwLegacySourceBindings $manyPolicy)
  $manyConfigPath=Join-Path $control 'project.json';$manyConfigOriginal=[IO.File]::ReadAllBytes($manyConfigPath)
  $manyConfig=Get-Content $manyConfigPath -Raw|ConvertFrom-Json -Depth 100
  $manyConfig.sourceBindings=$manyBindings;Write-Json $manyConfigPath $manyConfig
  $manyPolicy.rules[0].source=Convert-AiwLegacyPolicySource $manyPolicy.rules[0].source $manyPolicy.rules[0].ruleId $manyBindings
  $discover.expectedProjectConfigIdentity=Get-Identity $manyConfigPath
  Write-Json $policyPath $manyPolicy;Write-Json $discoverPath $discover;$manyRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $manyRun 'manyRun'
  Assert-True ($manyRun.Code-eq0-and$manyRun.Text.Contains('Rule 17')) 'seventeen-explicit-standard-documents-with-crlf-and-no-final-lf'
  [IO.File]::WriteAllBytes($manyConfigPath,$manyConfigOriginal);$discover.expectedProjectConfigIdentity=Get-Identity $manyConfigPath
  [IO.File]::WriteAllText($policyPath,$originalPolicyText,$utf8)
  $configPath=Join-Path $control 'project.json';$configOriginal=[IO.File]::ReadAllText($configPath)
  [IO.File]::WriteAllText($configPath,$configOriginal.Replace("`r`n","`n").TrimEnd("`n").Replace("`n","`r`n"),$utf8)
  $formatted=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$formatted.expectedProjectConfigIdentity=Get-Identity $configPath
  [IO.File]::WriteAllText($discoverPath,($formatted|ConvertTo-Json -Depth 100).Replace("`r`n","`n").TrimEnd("`n").Replace("`n","`r`n"),$utf8)
  $formatIdentity=Get-Identity $configPath;$formattedRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $formattedRun 'formattedRun'
  Assert-True ($formattedRun.Code-eq0-and$formattedRun.Value.compactReceipt.sourceBindings.projectConfigIdentity-ceq$formatIdentity-and(Get-Identity $configPath)-ceq$formatIdentity) 'crlf-config-and-tool-json-keep-actual-byte-identities-without-rewriting'
  [IO.File]::WriteAllText($configPath,$configOriginal,$utf8)
  $largeBody='Necessary fixture content. '*5000
  Write-Utf8 $standardPath ("<!-- RULE:BEGIN -->`n"+$largeBody+"`n<!-- RULE:END -->")
  $largePolicy=$sourcePolicy|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$largePolicy.rules[0].source.documents[1].identity=Get-Identity $standardPath
  Refresh-FixtureSourceRevision $largePolicy.rules[0].source
  Write-Json $policyPath $largePolicy
  Write-Json $discoverPath $discover;$largeRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $largeRun 'largeRun'
  Assert-True ($largeRun.Code-eq0-and$largeRun.Value.compactReceipt.pack.bytes-gt98304-and$largeRun.Text.Contains($largeBody)) 'complete-current-policy-does-not-truncate-or-block-over-96k-rule-pack'
  $largeReceiptPath=Join-Path $temp 'large-receipt.json';Write-Json $largeReceiptPath $largeRun.Value.compactReceipt
  $largeBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$largeReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $largeReceiptPath;preparationReceipts=@($largeRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@($largeRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique);deliveryReceipts=@('FIXTURE_DELIVERY');publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  $largeBoundaryPath=Join-Path $temp 'large-boundary.json'
  foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){$largeBoundary.mode=$mode;Write-Json $largeBoundaryPath $largeBoundary;$largeBoundaryRun=Invoke-Resolver $resolver $largeBoundaryPath;Assert-ResolverSuccess $largeBoundaryRun 'largeBoundaryRun';Assert-True ($largeBoundaryRun.Code-eq0-and$largeBoundaryRun.Value.status-ceq'PASS') ('complete-large-pack-keeps-real-boundary-'+$mode)}
  Write-Utf8 $standardPath 'Independent source drift';Write-Json $largeBoundaryPath $largeBoundary;$largeDrift=Invoke-Resolver $resolver $largeBoundaryPath
  Assert-True ($largeDrift.Code-ne0-and($largeDrift.Text.Contains('DISCOVER_SOURCE_DRIFT')-or$largeDrift.Text.Contains('CONTENT_IDENTITY_DRIFT'))) 'complete-pack-does-not-waive-source-drift'
  [IO.File]::WriteAllText($standardPath,$originalStandardText,$utf8);[IO.File]::WriteAllText($policyPath,$originalPolicyText,$utf8)
  $protectedReadAllowed=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$protectedReadAllowed.protectedPaths=@('docs/');Write-Json $discoverPath $protectedReadAllowed;$protectedReadAllowedRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $protectedReadAllowedRun 'protectedReadAllowedRun'
  Assert-True ($protectedReadAllowedRun.Code-eq0) 'write-protected-path-does-not-become-standard-source-read-forbidden'
  $allowedSourceRule=$sourcePolicy.rules[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json
  $restrictedSource=Join-Path $temp 'docs\restricted-standard.md';[IO.File]::WriteAllBytes($restrictedSource,[byte[]](0xC3,0x28))
  $restrictedRule=$allowedSourceRule|ConvertTo-Json -Depth 30|ConvertFrom-Json;$restrictedRule.source=[pscustomobject]@{rootSourceId='RESTRICTED';documents=@([pscustomobject][ordered]@{sourceId='RESTRICTED';locator='docs/restricted-standard.md';identity=('2|'+('A'*64));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}
  $null=Set-FixtureLegacyRules @($restrictedRule)
  $forbiddenRelative=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$forbiddenRelative.forbiddenPaths=@('docs/restricted-standard.md');Write-Json $discoverPath $forbiddenRelative;$forbiddenRelativeRun=Invoke-Resolver $resolver $discoverPath
  $restrictedRule.source.documents[0]|Add-Member -NotePropertyName locatorKind -NotePropertyValue 'ABSOLUTE_FILE';$restrictedRule.source.documents[0].locator=$restrictedSource;$null=Set-FixtureLegacyRules @($restrictedRule);$forbiddenRelative.expectedProjectConfigIdentity=Get-Identity $configPath
  Write-Json $discoverPath $forbiddenRelative;$forbiddenAbsoluteAliasRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($forbiddenRelativeRun.Code-ne0-and$forbiddenRelativeRun.Text.Contains('SOURCE_DENIED|FORBIDDEN_PATH')-and$forbiddenAbsoluteAliasRun.Code-ne0-and$forbiddenAbsoluteAliasRun.Text.Contains('SOURCE_DENIED|FORBIDDEN_PATH')) 'explicit-forbidden-read-rejects-project-relative-standard-and-absolute-alias-before-content-read'
  [IO.File]::WriteAllText($configPath,$configOriginal,$utf8);$discover.expectedProjectConfigIdentity=Get-Identity $configPath
  $sourcePolicy.rules=@($allowedSourceRule);Write-Json $policyPath $sourcePolicy
  Write-Json $discoverPath $discover
  $discoverResultText=$run.Value|ConvertTo-Json -Depth 100 -Compress;$compactReceiptText=$run.Value.compactReceipt|ConvertTo-Json -Depth 100 -Compress
  Assert-True ($discoverResultText.Contains('"fullText"')-and-not$compactReceiptText.Contains('"fullText"')-and@($run.Value.selectedRuleBlocks|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.fullText)}).Count-eq0-and[Text.Encoding]::UTF8.GetByteCount($compactReceiptText)-lt[Text.Encoding]::UTF8.GetByteCount($discoverResultText)) 'process-discover-emits-full-blocks-once-and-reusable-compact-receipt'
  $receiptPath=Join-Path $temp 'receipt.json';Write-Json $receiptPath $run.Value.compactReceipt
  $prep=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
  $results=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $boundary=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;preparationReceipts=$prep;resultReceipts=$results;deliveryReceipts=@('DELIVERED');publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  $boundaryPath=Join-Path $temp 'finalize.json';Write-Json $boundaryPath $boundary;$boundaryRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $boundaryRun 'boundaryRun'
  if($boundaryRun.Code-ne0){Write-Output ('DIAG|compact-boundary|'+$boundaryRun.Text)}
  Assert-True ($boundaryRun.Code-eq0-and[string]$boundaryRun.Value.status-ceq'PASS') 'compact-boundary-input-reuses-receipt-bound-intent-and-authority'
  Assert-True ($boundaryRun.Code-eq0-and-not$compactReceiptText.Contains('"fullText"')-and-not[bool]$boundaryRun.Value.semanticCorrectnessProven-and-not[bool]$boundaryRun.Value.hostInvocationProven) 'compact-receipt-reuse-is-mechanical-not-model-fulltext-proof'

  $decisionPath=Join-Path $temp 'AGENTS.md'
  Write-Utf8 $decisionPath 'User delegates the approved project goal under current rules.'
  Write-Json $discoverPath $discover;$decisionDiscover=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $decisionDiscover 'decisionDiscover'
  $decisionReceipt=Join-Path $temp 'decision-receipt.json';Write-Json $decisionReceipt $decisionDiscover.Value.compactReceipt
  $decisionBoundary=$boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $decisionBoundary.discoverReceiptPath=$decisionReceipt;$decisionBoundary.expectedDiscoverReceiptIdentity=Get-Identity $decisionReceipt
  Write-Json $boundaryPath $decisionBoundary;$healthyDecision=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $healthyDecision 'healthyDecision'
  Assert-True ($healthyDecision.Code-eq0) 'standing-user-decision-reuses-healthy-source-binding'
  foreach($changedDecision in @('User narrows delegation to read-only analysis.','User revokes standing delegation.')){
    Write-Utf8 $decisionPath $changedDecision
    Write-Json $boundaryPath $decisionBoundary;$decisionDrift=Invoke-Resolver $resolver $boundaryPath
    Assert-True ($decisionDrift.Code-ne0-and$decisionDrift.Text.Contains('DISCOVER_SOURCE_DRIFT|projectAgentsIdentity')) 'user-decision-narrowing-or-revocation-rejects-stale-receipt'
  }
  [IO.File]::Delete($decisionPath)
  Write-Json $boundaryPath $boundary

  $legacyDecisionReceipt=$run.Value.compactReceipt|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $legacyDecisionReceipt.sourceBindings.PSObject.Properties.Remove('projectAgentsIdentity')
  Write-Json $decisionReceipt $legacyDecisionReceipt
  $decisionBoundary.expectedDiscoverReceiptIdentity=Get-Identity $decisionReceipt
  Write-Json $boundaryPath $decisionBoundary;$legacyNoAgents=Invoke-Resolver $resolver $boundaryPath
  Assert-True ($legacyNoAgents.Code-eq0) 'legacy-receipt-with-no-agents-preserves-supported-readonly-entry'
  Write-Utf8 $decisionPath 'Current explicit user restriction.'
  Write-Json $boundaryPath $decisionBoundary;$legacyUnboundAgents=Invoke-Resolver $resolver $boundaryPath
  Assert-True ($legacyUnboundAgents.Code-ne0-and$legacyUnboundAgents.Text.Contains('PROJECT_AGENTS_BINDING_REQUIRED')) 'legacy-receipt-cannot-ignore-present-user-decision-source'
  [IO.File]::Delete($decisionPath)
  Write-Json $boundaryPath $boundary

  $oldInput=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $oldInput.schemaVersion=2;$oldInput.PSObject.Properties.Remove('contextType');$oldInput.PSObject.Properties.Remove('readOnlyContext')
  Write-Json $discoverPath $oldInput;$oldRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($oldRun.Code-ne0-and$oldRun.Text.Contains('INPUT_SCHEMA_VERSION')) 'current-target-rejects-old-discover-contract'
  Write-Utf8 $standardPath 'Changed intro without the adopted section markers.'
  $currentAdmit=$boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json;$currentAdmit.mode='ADMIT_ACTION'
  Write-Json $boundaryPath $currentAdmit;$sourceDrift=Invoke-Resolver $resolver $boundaryPath
  Assert-True ($sourceDrift.Code-ne0-and$sourceDrift.Text.Contains('CONTENT_IDENTITY_DRIFT')) 'current-admit-rejects-fixed-source-drift'
  Write-Json $discoverPath $discover;$driftRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($driftRun.Code-ne0-and$driftRun.Text.Contains('CONTENT_IDENTITY_DRIFT')) 'fixed-adoption-never-loads-unadopted-current-bytes'
  $sourcePolicy.rules[0].source.documents[0].dependencies=@('STANDARD');Write-Json $policyPath $sourcePolicy
  $discover.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');Write-Json $discoverPath $discover;$cycleRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($cycleRun.Code-ne0-and$cycleRun.Text.Contains('DEPENDENCY_CYCLE')) 'project-standard-source-cycle-fails-closed'

  Write-Utf8 (Join-Path $temp 'docs\standard.md') "Intro.`n<!-- RULE:BEGIN -->`nSelected project standard rule body.`n<!-- RULE:END -->`nTail."
  $sourcePolicy.rules[0].source.documents[0].dependencies=@()
  $sourcePolicy.rules[0].source.documents[1].identity=Get-Identity (Join-Path $temp 'docs\standard.md')
  Write-Json $policyPath $sourcePolicy
  $docsPath=Join-Path $temp 'docs';$docsHold=Join-Path $temp 'docs-hold'
  $docsMove=Get-FixtureDirectoryMoveBinding $temp $docsPath $docsHold
  Move-Item -LiteralPath $docsMove.Source -Destination $docsMove.Destination
  try{
    New-Item -ItemType Directory -Path $outsideTemp -Force|Out-Null
    Get-ChildItem -LiteralPath $docsHold -Force|Copy-Item -Destination $outsideTemp -Recurse -Force
    New-Item -ItemType Junction -Path $docsPath -Target $outsideTemp|Out-Null
    try{Write-Json $discoverPath $discover;$parentJunctionRun=Invoke-Resolver $resolver $discoverPath}finally{Remove-FixtureJunction $docsPath $temp}
    Assert-True ($parentJunctionRun.Code-ne0-and$parentJunctionRun.Text.Contains('SOURCE_DENIED|REPARSE')) 'project-standard-source-parent-junction-outside-project-fails-before-read'
    $outsideResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($outsideTemp));$systemTemp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));if(-not$outsideResolved.StartsWith($systemTemp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($outsideResolved)-cnotmatch'^aiw-process-v2-outside-[a-f0-9]{32}$'){throw 'OUTSIDE_TEMP_CLEANUP_BOUNDARY'};Remove-Item -LiteralPath $outsideResolved -Recurse -Force
    New-Item -ItemType Directory -Path $outsideTemp -Force|Out-Null
    New-Item -ItemType Junction -Path $docsPath -Target $outsideTemp|Out-Null
    Remove-Item -LiteralPath $outsideTemp -Force
    try{Write-Json $discoverPath $discover;$danglingParentJunctionRun=Invoke-Resolver $resolver $discoverPath}finally{Remove-FixtureJunction $docsPath $temp}
    $danglingReasons=@('SOURCE_DENIED|REPARSE')
    Assert-True ($danglingParentJunctionRun.Code-ne0-and@($danglingReasons|Where-Object{$danglingParentJunctionRun.Text.Contains($_)}).Count-eq1) 'project-standard-source-dangling-parent-junction-fails-at-source-locator-before-read'
  }finally{
    $remainingDocsLink=Get-Item -LiteralPath $docsPath -Force -ErrorAction SilentlyContinue;if($null-ne$remainingDocsLink-and($remainingDocsLink.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Remove-FixtureJunction $docsPath $temp}
    if(Test-Path -LiteralPath $docsHold){$docsRestore=Get-FixtureDirectoryMoveBinding $temp $docsHold $docsPath;Move-Item -LiteralPath $docsRestore.Source -Destination $docsRestore.Destination}
  }
  New-Item -ItemType Directory -Path $outsideTemp -Force|Out-Null
  $externalShared=Join-Path $outsideTemp 'shared-standard.md';$externalSupplement=Join-Path $temp 'docs\project-supplement.md'
  Write-Utf8 $externalShared "Shared external standard.`n<!-- EXTERNAL-RULE:BEGIN -->`nExternal normative body.`n<!-- EXTERNAL-RULE:END -->"
  Write-Utf8 $externalSupplement 'Project-local supplement.'
  $projectRelativeRule=$sourcePolicy.rules[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json
  $externalRule=[ordered]@{ruleId='SOURCE_BOUND_STANDARD';requirementReason='Use the user-selected external standard with a project supplement';selectors=$sourcePolicy.rules[0].selectors;preparationRequirements=@('PROJECT_STANDARD_READ');resultRequirements=@('PROJECT_STANDARD_APPLIED');decisionLocator='project:fixture-external';source=[ordered]@{rootSourceId='SUPPLEMENT';documents=@([ordered]@{sourceId='SHARED';locatorKind='ABSOLUTE_FILE';locator=$externalShared;identity=Get-Identity $externalShared;mode='MARKED_SECTION';sectionStart='<!-- EXTERNAL-RULE:BEGIN -->';sectionEnd='<!-- EXTERNAL-RULE:END -->';dependencies=@()},[ordered]@{sourceId='SUPPLEMENT';locator='docs/project-supplement.md';identity=Get-Identity $externalSupplement;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@('SHARED')})}}
  $null=Set-FixtureLegacyRules @($externalRule)
  $externalSharedPreimage=Get-Identity $externalShared
  Write-Json $discoverPath $discover;$externalRun=Invoke-Resolver $resolver $discoverPath
  Assert-ResolverSuccess $externalRun 'external-standard'
  $externalSelected=@($externalRun.Value.selectedRuleBlocks|Where-Object{[string]$_.requirementId-ceq'project:process-v2-fixture:SOURCE_BOUND_STANDARD'})
  Assert-True ($externalSelected.Count-eq1-and[string]$externalSelected[0].fullText-clike'*External normative body*Project-local supplement*'-and(Get-Identity $externalShared)-ceq$externalSharedPreimage) 'external-standard-and-project-relative-supplement-load-read-only-with-dependency-order'
  $externalReceiptPath=Join-Path $temp 'external-receipt.json';Write-Json $externalReceiptPath $externalRun.Value.compactReceipt
  $externalAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$externalReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $externalReceiptPath;preparationReceipts=@($externalRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Utf8 $externalShared "Shared external standard changed.`n<!-- EXTERNAL-RULE:BEGIN -->`nCurrent external normative body.`n<!-- EXTERNAL-RULE:END -->"
  Write-Json $boundaryPath $externalAdmit;$externalDrift=Invoke-Resolver $resolver $boundaryPath
  Assert-True ($externalDrift.Code-ne0-and$externalDrift.Text.Contains('CONTENT_IDENTITY_DRIFT')) 'external-standard-drift-invalidates-discover-receipt'
  Write-Json $discoverPath $discover;$externalDriftDiscover=Invoke-Resolver $resolver $discoverPath
  Assert-True ($externalDriftDiscover.Code-ne0-and$externalDriftDiscover.Text.Contains('CONTENT_IDENTITY_DRIFT')) 'external-fixed-source-drift-requires-explicit-readoption'
  $externalRule.source.documents[0].identity=Get-Identity $externalShared;$null=Set-FixtureLegacyRules @($externalRule)
  Write-Json $discoverPath $discover;$externalReadopted=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $externalReadopted 'externalReadopted'
  Assert-True ($externalReadopted.Code-eq0-and$externalReadopted.Text.Contains('Current external normative body')) 'explicit-fixture-readoption-selects-exact-new-external-bytes'
  $badPolicy=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100
  $badPolicy.rules[0].source.documents[0].locator=$externalShared;Write-Json $policyPath $badPolicy
  Write-Json $discoverPath $discover;$invalidExternal=Invoke-Resolver $resolver $discoverPath
  Assert-True ($invalidExternal.Code-ne0-and$invalidExternal.Text.Contains('SOURCE_DENIED|LOCATOR')) 'bound-source-document-rejects-absolute-locator-outside-binding'
  $protectedExternal=Join-Path $temp 'private/protected-standard.md';Write-Utf8 $protectedExternal 'Protected content.'
  $externalRule.source.documents[0].locator=$protectedExternal;$externalRule.source.documents[0].identity=Get-Identity $protectedExternal
  $null=Set-FixtureLegacyRules @($externalRule);Write-Json $discoverPath $discover;$protectedExternalRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($protectedExternalRun.Code-ne0-and$protectedExternalRun.Text.Contains('SOURCE_DENIED|FORBIDDEN_PATH')) 'external-alias-rejects-forbidden-project-source'
  $externalRule.source.documents[0].locator=Join-Path $outsideTemp 'missing-standard.md';$externalRule.source.documents[0].identity=('1|'+('A'*64))
  $null=Set-FixtureLegacyRules @($externalRule);Write-Json $discoverPath $discover;$missingExternal=Invoke-Resolver $resolver $discoverPath
  Assert-True ($missingExternal.Code-ne0-and$missingExternal.Text.Contains('EFFECTIVE_SET_UNPROVEN')) 'selected-external-standard-rejects-missing-uncached-source'
  if($IsWindows){
    $externalSourceDirectory=Join-Path $outsideTemp 'actual';New-Item -ItemType Directory -Path $externalSourceDirectory|Out-Null
    $externalSourceFile=Join-Path $externalSourceDirectory 'standard.md';Write-Utf8 $externalSourceFile 'External reparse target.'
    $externalLink=Join-Path $outsideTemp 'linked';New-Item -ItemType Junction -Path $externalLink -Target $externalSourceDirectory|Out-Null
    try{
      $externalRule.source.documents[0].locator=Join-Path $externalLink 'standard.md';$externalRule.source.documents[0].identity=Get-Identity $externalSourceFile
      $null=Set-FixtureLegacyRules @($externalRule);Write-Json $discoverPath $discover;$reparseExternal=Invoke-Resolver $resolver $discoverPath
    }finally{Remove-FixtureJunction $externalLink $outsideTemp}
    Assert-True ($reparseExternal.Code-ne0-and$reparseExternal.Text.Contains('SOURCE_DENIED|REPARSE')) 'external-standard-rejects-reparse-path-before-read'
  }
  $externalRule.source.documents[0].locator=$externalShared;$externalRule.source.documents[0].identity=Get-Identity $externalShared
  Import-Module $module -Force
  $forbiddenClosureFailure=$null;try{$null=Get-AiwProjectPolicySourceClosure -ProjectRoot $temp -Rules @($restrictedRule) -ForbiddenPaths @('docs/restricted-standard.md')}catch{$forbiddenClosureFailure=[string]$_.Exception.Message}
  Assert-True ($forbiddenClosureFailure-clike'*SOURCE_FILE_FORBIDDEN') 'legacy-source-closure-precheck-keeps-forbidden-read-boundary'
  $secondProject=Join-Path $outsideTemp 'second-project';New-Item -ItemType Directory -Path $secondProject -Force|Out-Null
  $secondSupplement=Join-Path $secondProject 'supplement.md';Write-Utf8 $secondSupplement 'Second project supplement.'
  $firstRule=$externalRule|ConvertTo-Json -Depth 30|ConvertFrom-Json;$secondRule=$externalRule|ConvertTo-Json -Depth 30|ConvertFrom-Json
  $secondRule.source.documents[1].locator='supplement.md';$secondRule.source.documents[1].identity=Get-Identity $secondSupplement
  $firstClosure=Get-AiwProjectPolicySourceClosure -ProjectRoot $temp -Rules @($firstRule)
  $secondClosure=Get-AiwProjectPolicySourceClosure -ProjectRoot $secondProject -Rules @($secondRule)
  $firstShared=@($firstClosure.Documents|Where-Object{[string]$_.locatorKind-ceq'ABSOLUTE_FILE'});$secondShared=@($secondClosure.Documents|Where-Object{[string]$_.locatorKind-ceq'ABSOLUTE_FILE'})
  Assert-True ($firstShared.Count-eq1-and$secondShared.Count-eq1-and[string]$firstShared[0].sourcePath-ceq[string]$secondShared[0].sourcePath-and[string]$firstShared[0].identity-ceq[string]$secondShared[0].identity-and[string]$firstClosure.Identity-cne[string]$secondClosure.Identity) 'multiple-projects-share-original-external-standard-with-independent-local-supplements'
  # Ordinary composition reads only the selected closure. Prime a real PINNED
  # source, remove its live file, then test unmatched and matched revocation separately.
  [IO.File]::WriteAllText($configPath,$configOriginal,$utf8)
  $sourcePolicy=ConvertFrom-Json $originalPolicyText -Depth 100
  $unavailablePath=Join-Path $temp 'docs/offline.md';Write-Utf8 $unavailablePath 'Fixed offline rule.'
  $unavailableRule=$projectRelativeRule|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $unavailableRule.ruleId='UNAVAILABLE_ONLY_WHEN_APPLICABLE';$unavailableRule.selectors.actionKinds=@('SOURCE_WRITE');$unavailableRule.selectors.resultKinds=@('IMPLEMENTATION_RESULT')
  $unavailableRule.source.documents=@($unavailableRule.source.documents[0]);$unavailableRule.source.documents[0].locator='docs/offline.md'
  $unavailableRule.source.documents[0].identity=Get-Identity $unavailablePath;$unavailableRule.source.documents[0].dependencies=@()
  $unavailableRule.source.rootSourceId=$unavailableRule.source.documents[0].sourceId
  $unavailableRule.source.itemId='OFFLINE';$unavailableRule.source.bindingId=$unavailableRule.source.documents[0].bindingId
  $offlineConfig=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100
  $offlineBinding=@($offlineConfig.sourceBindings|Where-Object{$_.id-ceq$unavailableRule.source.bindingId})[0]
  $offlineBinding.allowedPaths+=@([pscustomobject]@{kind='FILE';locator='docs/offline.md'})
  Write-Json $configPath $offlineConfig;$fixtureBindings=$offlineConfig.sourceBindings
  Refresh-FixtureSourceRevision $projectRelativeRule.source;Refresh-FixtureSourceRevision $unavailableRule.source
  $sourcePolicy.rules=@($projectRelativeRule,$unavailableRule);Write-Json $policyPath $sourcePolicy
  $discover.expectedProjectConfigIdentity=Get-Identity $configPath
  $standardArgs=@{ProjectRoot=$temp;FrameworkRoot=$frameworkRoot;TargetVersion='2.0.0';ExpectedProjectConfigIdentity=Get-Identity $configPath;ExpectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');Profile='STANDARD';Role='TASK_OWNER';Phase='PLAN';Actor='owner-fixture';TaskIdentity=Get-Identity $taskPath;Capabilities=@();Objective='Plan source-bound project work';ActionKind='NONE';ResultKind='PLAN';ExactPaths=@();EvaluationOnly=$true}
  $onlineComposition=Invoke-ProcessRequirementComposition @standardArgs
  # A projected deletion is a tombstone even when the original live file and
  # an exact PINNED cache still exist. Exercise the real source reader.
  $originalContext=New-AiwContentContext -ProjectRoot $temp -ExpectedProjectConfigIdentity (Get-Identity $configPath)
  $offlineSnapshot=Resolve-AiwContentSnapshot -Context $originalContext -Descriptor $unavailableRule.source -UpdatePolicy PINNED
  $offlineDocument=$unavailableRule.source.documents[0]
  $liveObservation=Read-AiwContentExact $originalContext $offlineSnapshot $offlineDocument
  $tombstoneStage=Join-Path $temp 'adoption-tombstone-stage'
  foreach($relative in @('.ai-workspace/project.json','.ai-workspace/process-policy.json')){$destination=Join-Path $tombstoneStage $relative;[IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null;[IO.File]::WriteAllBytes($destination,[IO.File]::ReadAllBytes((Join-Path $temp $relative)))}
  $deletion=[pscustomobject]@{path='docs/offline.md';kind='FILE';newExists=$false;newIdentity='MISSING';newBase64=''}
  $deletedContext=New-AiwAdoptionContentContext -ProjectRoot $tombstoneStage -ExpectedProjectConfigIdentity (Get-Identity (Join-Path $tombstoneStage '.ai-workspace/project.json')) -SourceProjectRoot $temp -ProjectedSourceObjects @($deletion)
  $deletedFailure='';try{$null=Read-AiwContentExact $deletedContext $offlineSnapshot $offlineDocument}catch{$deletedFailure=$_.Exception.Message}
  Assert-True ($deletedFailure.Contains('SOURCE_DENIED|FORBIDDEN_PATH')-and(Test-Path $unavailablePath)-and(Test-Path $liveObservation.cachePath)) 'adoption-deleted-source-cannot-fall-back-to-live-or-exact-pinned-cache'
  [IO.File]::Delete($unavailablePath)
  $unrelatedComposition=Invoke-ProcessRequirementComposition @standardArgs
  Assert-True (@($unrelatedComposition.selectedRequirements|Where-Object{[string]$_.requirementId-ceq'project:process-v2-fixture:UNAVAILABLE_ONLY_WHEN_APPLICABLE'}).Count-eq0-and$unrelatedComposition.effectiveSetIdentity-ceq$onlineComposition.effectiveSetIdentity) 'unselected-pinned-offline-source-preserves-selected-closure-only'
  $neutralTaskOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath
  $resourceRequirementIds=@('framework:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE')
  foreach($neutralPhase in @('RECOVER','DISCOVER')){
    Write-Utf8 $taskPath "# PROCESS-V2-001 — runtime contract fixture`n`n- Owner: owner-fixture`n- Work route: actor=reviewer-fixture; role=REVIEWER; phase=$neutralPhase`n- Range summary: profile=MICRO; lifecycle=ACTIVE; risk=LOW; size=MICRO; uncertainty=LOW`n"
    $neutralArgs=@{ProjectRoot=$temp;FrameworkRoot=$frameworkRoot;TargetVersion='2.0.0';ExpectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');ExpectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');Profile='MICRO';Role='REVIEWER';Phase=$neutralPhase;Actor='reviewer-fixture';TaskIdentity=Get-Identity $taskPath;Capabilities=@();Objective='Continue the current bounded work';ActionKind='NONE';ResultKind='PLAN';ExactPaths=@();EvaluationOnly=$true}
    $neutralComposition=Invoke-ProcessRequirementComposition @neutralArgs
    $neutralIntent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Continue the current bounded work';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
    $neutralDiscover=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='reviewer-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$neutralIntent;evaluationOnly=$true}
    Write-Json $discoverPath $neutralDiscover;$neutralRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $neutralRun 'neutralRun'
    $completeBodiesMatch=$true
    foreach($resourceId in $resourceRequirementIds){
      $composerBlock=@($neutralComposition.selectedRequirements|Where-Object{[string]$_.requirementId-ceq$resourceId})
      $resolverBlock=@($neutralRun.Value.selectedRuleBlocks|Where-Object{[string]$_.requirementId-ceq$resourceId})
      if($composerBlock.Count-ne1-or$resolverBlock.Count-ne1-or[string]::IsNullOrWhiteSpace([string]$resolverBlock[0].fullText)-or[string]$resolverBlock[0].fullText-cne[string]$composerBlock[0].fullText){$completeBodiesMatch=$false}
    }
    $neutralBinding=$neutralRun.Value.compactReceipt.binding;$neutralPack=$neutralRun.Value.compactReceipt.pack
    Assert-True ($neutralRun.Code-eq0-and$completeBodiesMatch-and[string]$neutralBinding.profile-ceq'MICRO'-and[string]$neutralBinding.role-ceq'REVIEWER'-and[string]$neutralBinding.phase-ceq$neutralPhase-and[string]$neutralBinding.authorizationIdentity-ceq'NOT_REQUIRED'-and@($neutralBinding.authorizedActions).Count-eq0-and-not[bool]$neutralRun.Value.compactReceipt.authorityGranted-and-not[bool]$neutralRun.Value.compactReceipt.semanticCorrectnessProven-and[int]$neutralPack.ceilingBytes-eq0-and[int]$neutralPack.bytes-gt0-and[int]$neutralComposition.selectedRulePackBytes-eq0) ('neutral-micro-reviewer-retains-role-boundary-without-authority-'+$neutralPhase.ToLowerInvariant())
    Assert-True ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cnotin@($neutralRun.Value.selectedRuleBlocks.requirementId)-and'framework:PR_CODEX_RESOURCE_ROUTE'-cnotin@($neutralRun.Value.selectedRuleBlocks.requirementId)) ('healthy-neutral-reuse-does-not-reopen-creation-resource-'+$neutralPhase)
    $neutralDiscover.intentEnvelope.objective='Assign an independent actor and choose resources for the new work';$neutralDiscover.intentEnvelope.facets.workType.values=@('aiw:task-organization','aiw:resource-selection');$neutralDiscover.intentEnvelope.semanticHints=@('task assignment','resource selection');Write-Json $discoverPath $neutralDiscover;$assignmentRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $assignmentRun 'assignmentRun'
    Assert-True ($assignmentRun.Code-eq0-and'framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($assignmentRun.Value.selectedRuleBlocks.requirementId)-and'framework:PR_TASK_RESOURCE_SELECTION'-cin@($assignmentRun.Value.selectedRuleBlocks.requirementId)-and'framework:PR_CODEX_RESOURCE_ROUTE'-cin@($assignmentRun.Value.selectedRuleBlocks.requirementId)) ('new-assignment-loads-complete-resource-bodies-'+$neutralPhase)
  }
  Write-Utf8 $taskPath $neutralTaskOriginal

  $offlineRuleId='project:process-v2-fixture:UNAVAILABLE_ONLY_WHEN_APPLICABLE'
  $offlineCacheIdentity=Get-Identity $liveObservation.cachePath
  $matchingArgs=$standardArgs.Clone();$matchingArgs.ActionKind='SOURCE_WRITE';$matchingArgs.ResultKind='IMPLEMENTATION_RESULT'
  function Observe-OfflineComposition([string]$Stage,$Arguments,$Composition,$Failure){
    $currentConfig=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100
    $currentBindings=@($currentConfig.sourceBindings|Where-Object{$_.id-ceq$offlineDocument.bindingId})
    $observation=[ordered]@{stage=$Stage;action=$Arguments.ActionKind;result=$Arguments.ResultKind;configIdentity=Get-Identity $configPath;expectedConfigIdentity=$Arguments.ExpectedProjectConfigIdentity;bindingId=$offlineDocument.bindingId;bindings=$currentBindings;liveExists=(Test-Path -LiteralPath $unavailablePath);cachePath=$liveObservation.cachePath;cacheExists=(Test-Path -LiteralPath $liveObservation.cachePath);cacheIdentity=$(if(Test-Path -LiteralPath $liveObservation.cachePath){Get-Identity $liveObservation.cachePath}else{'MISSING'});caughtException=$Failure;compositionReturned=($null-ne$Composition);status=$(if($null-ne$Composition){$Composition.status}else{$null});selectedIds=$(if($null-ne$Composition){@($Composition.selectedRequirements.requirementId)}else{$null});readTrace=$(if($null-ne$Composition){@($Composition.readTrace)}else{$null});ceiling='Selected IDs and composer readTrace describe this returned closure; no complete physical IO interception. A thrown composition has no returned selected IDs or trace.'}
    $script:LastFixtureResolverText=$observation|ConvertTo-Json -Depth 30 -Compress
    Write-Output ('OBSERVE|offline-permission|'+$script:LastFixtureResolverText)
  }
  $matchedBefore=$null;$matchedBeforeFailure=$null
  try{$matchedBefore=Invoke-ProcessRequirementComposition @matchingArgs}catch{$matchedBeforeFailure=[string]$_.Exception.Message}
  Observe-OfflineComposition 'MATCHED_BEFORE_WITHDRAWAL' $matchingArgs $matchedBefore $matchedBeforeFailure
  $matchedBeforeReads=@(if($null-ne$matchedBefore){$matchedBefore.readTrace|Where-Object{$_.event-ceq'SOURCE_BODY_READ'-and$_.ruleId-ceq$unavailableRule.ruleId}})
  Assert-True ($null-eq$matchedBeforeFailure-and$null-ne$matchedBefore-and$offlineRuleId-cin@($matchedBefore.selectedRequirements.requirementId)-and$matchedBeforeReads.Count-eq1-and$matchedBeforeReads[0].path-ceq[IO.Path]::GetFullPath($unavailablePath)-and$matchedBeforeReads[0].observation-ceq'PINNED_CACHE'-and-not(Test-Path -LiteralPath $unavailablePath)-and(Get-Identity $liveObservation.cachePath)-ceq$offlineCacheIdentity) 'selected-pinned-offline-source-uses-existing-cache-before-permission-revocation'

  $offlineBinding.allowedPaths=@($offlineBinding.allowedPaths|Where-Object{$_.locator-cne'docs/offline.md'})
  Write-Json $configPath $offlineConfig;$standardArgs.ExpectedProjectConfigIdentity=Get-Identity $configPath
  $unmatchedAfter=$null;$unmatchedFailure=$null
  try{$unmatchedAfter=Invoke-ProcessRequirementComposition @standardArgs}catch{$unmatchedFailure=[string]$_.Exception.Message}
  Observe-OfflineComposition 'UNMATCHED_AFTER_WITHDRAWAL' $standardArgs $unmatchedAfter $unmatchedFailure
  $unmatchedOfflineReads=@(if($null-ne$unmatchedAfter){$unmatchedAfter.readTrace|Where-Object{$_.event-ceq'SOURCE_BODY_READ'-and($_.ruleId-ceq$unavailableRule.ruleId-or$_.path-ceq[IO.Path]::GetFullPath($unavailablePath))}})
  Assert-True ($null-eq$unmatchedFailure-and$null-ne$unmatchedAfter-and$offlineRuleId-cnotin@($unmatchedAfter.selectedRequirements.requirementId)-and'project:process-v2-fixture:SOURCE_BOUND_STANDARD'-cin@($unmatchedAfter.selectedRequirements.requirementId)-and$unmatchedOfflineReads.Count-eq0-and(Get-Identity $liveObservation.cachePath)-ceq$offlineCacheIdentity) 'unselected-revoked-offline-source-is-absent-from-observed-selected-read-closure'

  $matchingArgs.ExpectedProjectConfigIdentity=Get-Identity $configPath
  $relatedComposition=$null;$relatedFailure=$null
  try{$relatedComposition=Invoke-ProcessRequirementComposition @matchingArgs}catch{$relatedFailure=[string]$_.Exception.Message}
  Observe-OfflineComposition 'MATCHED_AFTER_WITHDRAWAL' $matchingArgs $relatedComposition $relatedFailure
  # Only this adopted one-document rule matches the source-write action, and
  # the pre-withdrawal call proved its missing live source used the real cache.
  Assert-True ($relatedFailure-ceq'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS'-and$null-eq$relatedComposition-and@($offlineBinding.allowedPaths|Where-Object{$_.locator-ceq'docs/offline.md'}).Count-eq0-and-not(Test-Path -LiteralPath $unavailablePath)-and(Get-Identity $liveObservation.cachePath)-ceq$offlineCacheIdentity) 'selected-offline-source-cannot-reuse-cache-after-permission-revocation'
  $offlineBinding.allowedPaths+=@([pscustomobject]@{kind='FILE';locator='docs/offline.md'})
  Write-Json $configPath $offlineConfig;$standardArgs.ExpectedProjectConfigIdentity=Get-Identity $configPath
  $fixtureBindings=$offlineConfig.sourceBindings
  $matchingArgs.ExpectedProjectConfigIdentity=Get-Identity $configPath
  $restoredComposition=$null;$restoredFailure=$null
  try{$restoredComposition=Invoke-ProcessRequirementComposition @matchingArgs}catch{$restoredFailure=[string]$_.Exception.Message}
  Observe-OfflineComposition 'MATCHED_AFTER_RESTORE' $matchingArgs $restoredComposition $restoredFailure
  $restoredReads=@(if($null-ne$restoredComposition){$restoredComposition.readTrace|Where-Object{$_.event-ceq'SOURCE_BODY_READ'-and$_.ruleId-ceq$unavailableRule.ruleId}})
  Assert-True ($null-eq$restoredFailure-and$null-ne$restoredComposition-and$offlineRuleId-cin@($restoredComposition.selectedRequirements.requirementId)-and$restoredReads.Count-eq1-and$restoredReads[0].path-ceq[IO.Path]::GetFullPath($unavailablePath)-and$restoredReads[0].observation-ceq'PINNED_CACHE'-and(Get-Identity $liveObservation.cachePath)-ceq$offlineCacheIdentity) 'restored-offline-permission-restores-matching-cached-source-read'
  Write-Utf8 (Join-Path $temp 'docs\standard.md') "<!-- RULE:BEGIN -->`nFirst.`n<!-- RULE:END -->`n<!-- RULE:BEGIN -->`nSecond.`n<!-- RULE:END -->"
  $sourcePolicy.rules=@($sourcePolicy.rules[0]);$sourcePolicy.rules[0].source.documents[1].identity=Get-Identity (Join-Path $temp 'docs\standard.md');Refresh-FixtureSourceRevision $sourcePolicy.rules[0].source;Write-Json $policyPath $sourcePolicy
  $standardArgs.Objective='Plan source-bound project work';$standardArgs.ActionKind='NONE';$standardArgs.ResultKind='PLAN'
  $sectionFailure=$null;try{$null=Invoke-ProcessRequirementComposition @standardArgs}catch{$sectionFailure=[string]$_.Exception.Message}
  Assert-True ($sectionFailure-clike'*SECTION_CARDINALITY*') 'selected-project-standard-rejects-duplicate-section-markers'

  Write-Utf8 (Join-Path $temp 'docs\standard.md') "Intro.`n<!-- RULE:BEGIN -->`nSelected project standard rule body.`n<!-- RULE:END -->`nTail."
  $sourcePolicy.rules[0].source.documents[1].identity=Get-Identity (Join-Path $temp 'docs\standard.md');Refresh-FixtureSourceRevision $sourcePolicy.rules[0].source;Write-Json $policyPath $sourcePolicy
  $historicalChinese='此 legacy region 当前没有 permanent project process rule。structured rules 位于 `.ai-workspace/process-policy.json`。'
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n$historicalChinese`n<!-- PROJECT-CUSTOM:END -->"
  $historicalPlaceholder=Invoke-ProcessRequirementComposition @standardArgs
  Assert-True (@($historicalPlaceholder.selectedRequirements|Where-Object{[string]$_.requirementId-ceq'project-custom:process-v2-fixture'}).Count-eq0-and@($historicalPlaceholder.evidenceCeilings)-notcontains'LEGACY_PROJECT_CUSTOM_FULL_LOAD') 'exact-historical-chinese-placeholder-with-structured-policy-is-nonnormative'
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n$historicalChinese`nAn actual permanent project rule is active.`n<!-- PROJECT-CUSTOM:END -->"
  $appendedCarrier=Invoke-ProcessRequirementComposition @standardArgs
  Assert-True (@($appendedCarrier.selectedRequirements|Where-Object{$_.fullText.Contains('An actual permanent project rule is active.')}).Count-eq1) 'historical-placeholder-with-distinct-appended-rule-coexists-with-policy'
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nNo permanent project process rule is active in this legacy region. Structured rules belong to ``.ai-workspace/process-policy.json``.`n<!-- PROJECT-CUSTOM:END -->"
  $sourcePolicy.rules=@();Write-Json $policyPath $sourcePolicy
  $readOnlyIntent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Explain the current project process without performing an action';requestedActionKind='NONE';requestedResultKind='USER_RESPONSE';semanticHints=@('project process');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
  $taskless=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=[ordered]@{sessionId='session-fixture';requestId='request-fixture';role='TASK_OWNER';phase='PLAN';profile='STANDARD'};projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity='NOT_APPLICABLE';observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('src/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$readOnlyIntent;evaluationOnly=$true}
  Write-Json $discoverPath $taskless;$tasklessRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $tasklessRun 'tasklessRun'
  if($tasklessRun.Code-ne0){Write-Output ('DIAG|taskless|'+$tasklessRun.Text)}
  Assert-True ($tasklessRun.Code-eq0-and[string]$tasklessRun.Value.compactReceipt.binding.contextType-ceq'PROJECT_READ_ONLY'-and[string]$tasklessRun.Value.compactReceipt.binding.taskIdentity-ceq'NOT_APPLICABLE'-and[string]$tasklessRun.Value.compactReceipt.binding.authorizationIdentity-ceq'NOT_REQUIRED') 'taskless-project-read-only-context-does-not-invent-task-or-authority'
  $deliveryReceipt=Join-Path $temp 'delivery-receipt.json';Write-Json $deliveryReceipt $tasklessRun.Value.compactReceipt
  $deliveryBoundary=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$deliveryReceipt;expectedDiscoverReceiptIdentity=(Get-Identity $deliveryReceipt);preparationReceipts=@($tasklessRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@($tasklessRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Where-Object{$_-cne'DELIVERY_RECEIPT'}|Sort-Object -Unique);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';deliveryContext=[ordered]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}}
  Write-Json $discoverPath $deliveryBoundary;$nativeReady=Invoke-Resolver $resolver $discoverPath
  Assert-True ($nativeReady.Code-eq0-and$nativeReady.Value.status-ceq'PASS'-and$nativeReady.Value.delivery.status-ceq'READY_TO_SEND'-and-not$nativeReady.Value.delivery.delivered) 'native-final-prepares-without-future-delivery-receipt'
  $deliveryBoundary.deliveryContext.outcome='SUCCESS';Write-Json $discoverPath $deliveryBoundary;$future=Invoke-Resolver $resolver $discoverPath
  Assert-True ($future.Code-ne0-and$future.Text.Contains('DELIVERY_FUTURE_EVIDENCE')) 'native-final-rejects-prefilled-send-success'
  $deliveryBoundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient='owner';observedRecipient='owner';outcome='SUCCESS';evidence='fixture:actual-host-return'}
  Write-Json $discoverPath $deliveryBoundary;$sent=Invoke-Resolver $resolver $discoverPath
  Assert-True ($sent.Code-ne0-and$sent.Text.Contains('DELIVERY_CONSUMER_CHANNEL_MISMATCH')) 'taskless-user-response-cannot-invent-task-message-consumer'
  foreach($outcome in @('FAILURE','UNKNOWN')){
    $deliveryBoundary.deliveryContext.outcome=$outcome;Write-Json $discoverPath $deliveryBoundary;$notSent=Invoke-Resolver $resolver $discoverPath
    Assert-True ($notSent.Code-ne0-and$notSent.Text.Contains('DELIVERY_CONSUMER_CHANNEL_MISMATCH')) ('taskless-'+$outcome+'-still-needs-bound-consumer')
  }
  $deliveryBoundary.deliveryContext.outcome='SUCCESS';$deliveryBoundary.deliveryContext.observedRecipient='wrong';Write-Json $discoverPath $deliveryBoundary;$wrong=Invoke-Resolver $resolver $discoverPath
  Assert-True ($wrong.Code-ne0-and$wrong.Text.Contains('DELIVERY_SUCCESS_UNBOUND')) 'send-success-to-wrong-consumer-rejected'
  $taskless.intentEnvelope.requestedActionKind='SOURCE_WRITE';$taskless.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';Write-Json $discoverPath $taskless;$tasklessDenied=Invoke-Resolver $resolver $discoverPath
  Assert-True ($tasklessDenied.Code-ne0-and$tasklessDenied.Text.Contains('PROJECT_READ_ONLY_BOUNDARY')) 'taskless-context-cannot-admit-governed-action'

  $taskless=$null
  Write-Utf8 $taskPath "# PROCESS-V2-001 — runtime contract fixture`n`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; risk=MEDIUM; size=SMALL; uncertainty=LOW`n"
  Write-Utf8 (Join-Path $temp 'src\file.txt') 'old'
  $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='PROCESS-V2-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='executor-fixture';bundle='PLAN_LOCAL';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@('SOURCE_WRITE');exactPaths=@('src/file.txt');objectIdentities=@([ordered]@{path='src/file.txt';identity=Get-Identity (Join-Path $temp 'src\file.txt')});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=Get-Identity (Join-Path $control 'project.json')}
  $packagePath=Join-Path $control 'runtime-package.json';Write-Json $packagePath $package
  $actorIntent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Implement the assigned source change';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('implementation');pathHints=@('src/file.txt');capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'}
  $actorDiscover=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='executor-fixture';capabilities=@();exactPaths=@('src/file.txt');forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=Get-Identity $packagePath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$actorIntent;evaluationOnly=$true}
  Write-Json $discoverPath $actorDiscover;$actorRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $actorRun 'actorRun'
  if($actorRun.Code-ne0){Write-Output ('DIAG|temporary-actor|'+$actorRun.Text)}
  Assert-True ($actorRun.Code-eq0-and[string]$actorRun.Value.compactReceipt.binding.taskActor-ceq'owner-fixture'-and[string]$actorRun.Value.compactReceipt.binding.actor-ceq'executor-fixture'-and[string]$actorRun.Value.compactReceipt.binding.role-ceq'EXECUTOR'-and[string]$actorRun.Value.compactReceipt.binding.phase-ceq'IMPLEMENT') 'temporary-source-actor-uses-package-without-changing-task-owner-or-route'

  $actorReceiptPath=Join-Path $control 'actor-recovery-receipt.json';Write-Json $actorReceiptPath $actorRun.Value.compactReceipt
  $actorPrep=@($actorRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
  $actorBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$actorReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $actorReceiptPath;preparationReceipts=$actorPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $actorBoundary;$actorAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $actorAdmit 'actorAdmit'
  $actorPackageOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $packagePath
  Write-Utf8 $packagePath ($actorPackageOriginal.TrimEnd([char[]]"`r`n")+' ')
  $freshAuthorizationDiscover=$actorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$freshAuthorizationDiscover.expectedAuthorizationIdentity=Get-Identity $packagePath
  Write-Json $discoverPath $freshAuthorizationDiscover;$freshAuthorizationRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $freshAuthorizationRun 'freshAuthorizationRun'
  $freshAuthorizationReceiptPath=Join-Path $control 'fresh-authorization-receipt.json';Write-Json $freshAuthorizationReceiptPath $freshAuthorizationRun.Value.compactReceipt
  $freshAuthorizationPrep=@($freshAuthorizationRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
  $freshAuthorizationBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$freshAuthorizationReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $freshAuthorizationReceiptPath;preparationReceipts=$freshAuthorizationPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $freshAuthorizationBoundary;$freshAuthorizationAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $freshAuthorizationAdmit 'freshAuthorizationAdmit'
  Assert-True ($actorAdmit.Code-eq0-and$freshAuthorizationRun.Code-eq0-and$freshAuthorizationAdmit.Code-eq0-and[string]$freshAuthorizationRun.Value.compactReceipt.sourceCompositionIdentity-ceq[string]$actorRun.Value.compactReceipt.sourceCompositionIdentity-and[string]$freshAuthorizationRun.Value.compactReceipt.selectionIdentity-ceq[string]$actorRun.Value.compactReceipt.selectionIdentity-and[string]$freshAuthorizationRun.Value.compactReceipt.contextIdentity-cne[string]$actorRun.Value.compactReceipt.contextIdentity-and[string]$freshAuthorizationAdmit.Value.decisionIdentity-cne[string]$actorAdmit.Value.decisionIdentity) 'healthy-context-fresh-authorization-rebinds-boundary-without-changing-source-composition-or-selection'
  [IO.File]::WriteAllText($packagePath,$actorPackageOriginal,$utf8)

  $archiveRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'control-transition-tests.ps1'),'-Group','OrdinaryArchive') -GroupId 'process-current-task-archive'
  if($archiveRun.Code-ne0){throw ('CURRENT_TASK_ARCHIVE_REGRESSION|'+$archiveRun.Text)}
  Assert-True ($archiveRun.Text.Contains('CONTROL_TRANSITION_TESTS_PASS')) 'current-task-ordinary-archive-regression-replaces-retired-transition-machine'

  $agentsPath=Join-Path $temp 'AGENTS.md';Write-Utf8 $agentsPath 'Original user decision.'
  $agentsPackage=$package|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $agentsPackage.actions=@('CONTROL_WRITE');$agentsPackage.exactPaths=@('AGENTS.md');$agentsPackage.objectIdentities=@([pscustomobject]@{path='AGENTS.md';identity=Get-Identity $agentsPath})
  $agentsPackagePath=Join-Path $control 'agents-package.json';Write-Json $agentsPackagePath $agentsPackage
  $agentsDiscover=$actorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $agentsDiscover.intentEnvelope.pathHints=@('AGENTS.md')
  $agentsDiscover.authorizationPackagePath=$agentsPackagePath;$agentsDiscover.expectedAuthorizationIdentity=Get-Identity $agentsPackagePath;$agentsDiscover.exactPaths=@('AGENTS.md');$agentsDiscover.intentEnvelope.requestedActionKind='CONTROL_WRITE';$agentsDiscover.intentEnvelope.mutationHints=@('control')
  Write-Json $discoverPath $agentsDiscover;$agentsRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $agentsRun 'agentsRun'
  if($agentsRun.Code-ne0){throw ('AGENTS_DISCOVER|'+$agentsRun.Text)}
  $agentsReceipt=Join-Path $control 'agents-receipt.json';Write-Json $agentsReceipt $agentsRun.Value.compactReceipt
  $agentsBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$agentsReceipt;expectedDiscoverReceiptIdentity=Get-Identity $agentsReceipt;preparationReceipts=@($agentsRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $agentsBoundary;$agentsAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $agentsAdmit 'agentsAdmit'
  Assert-True ($agentsAdmit.Code-eq0) 'explicit-agents-control-write-admits-exact-preimage'
  Write-Utf8 $agentsPath 'User narrows delegation; authorized decision update.'
  $agentsBoundary.mode='FINALIZE_OUTPUT';$agentsBoundary.resultReceipts=@($agentsRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|AGENTS.md|'+(Get-Identity $agentsPath))
  Write-Json $boundaryPath $agentsBoundary;$agentsFinalize=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $agentsFinalize 'agentsFinalize'
  if($agentsFinalize.Code-ne0){Write-Output ('AGENTS_FINALIZE|'+$agentsFinalize.Text)}
  Assert-True ($agentsFinalize.Code-eq0-and$agentsFinalize.Value.sourcePostimageTransition.changedBindings-contains'projectAgentsIdentity') 'authorized-agents-postimage-finalizes-through-existing-source-transition'
  [IO.File]::Delete($agentsPath)

  $continuationPackage=$package|ConvertTo-Json -Depth 100|ConvertFrom-Json;$continuationPackage.actions=@('SOURCE_WRITE','TEST_RUN');$continuationPackage|Add-Member -NotePropertyName continuationPlan -NotePropertyValue @('SOURCE_WRITE','TEST_RUN','SOURCE_WRITE','TEST_RUN');$continuationPackage.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $continuationPackagePath=Join-Path $control 'continuation-package.json';Write-Json $continuationPackagePath $continuationPackage;$continuationPackageIdentity=Get-Identity $continuationPackagePath
  $continuationDiscover=$actorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$continuationDiscover.authorizationPackagePath=$continuationPackagePath;$continuationDiscover.expectedAuthorizationIdentity=Get-Identity $continuationPackagePath
  Write-Json $discoverPath $continuationDiscover;$continuationWriteRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $continuationWriteRun 'continuationWriteRun'

  # Future preload retired; the current-full branch above checks its public refusal.
  $continuationWriteReceiptPath=Join-Path $control 'continuation-write-discover-receipt.json';Write-Json $continuationWriteReceiptPath $continuationWriteRun.Value.compactReceipt
  $continuationWritePrep=@($continuationWriteRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$continuationWriteResults=@($continuationWriteRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $continuationWriteBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$continuationWriteReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $continuationWriteReceiptPath;preparationReceipts=$continuationWritePrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $continuationWriteBoundary;$continuationWriteAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationWriteAdmit 'continuationWriteAdmit'
  Write-Utf8 (Join-Path $temp 'src\file.txt') 'first authorized postimage'
  $continuationWriteFinalize=$continuationWriteBoundary|ConvertTo-Json -Depth 50|ConvertFrom-Json;$continuationWriteFinalize.mode='FINALIZE_OUTPUT';$continuationWriteFinalize.resultReceipts=@($continuationWriteResults+@('OBJECT_POSTIMAGE|src/file.txt|'+(Get-Identity (Join-Path $temp 'src\file.txt'))));Write-Json $boundaryPath $continuationWriteFinalize;$continuationWriteFinalizeRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationWriteFinalizeRun 'continuationWriteFinalizeRun'
  Assert-True ($continuationWriteFinalizeRun.Code-eq0-and[int]$continuationWriteFinalizeRun.Value.continuationReceipt.completedStepIndex-eq0-and[string]$continuationWriteFinalizeRun.Value.continuationReceipt.completedAction-ceq'SOURCE_WRITE'-and$null-eq$continuationWriteFinalizeRun.Value.continuationReceipt.PSObject.Properties['sourceFinalizeDecisionIdentity']) 'continuation-receipt-binds-source-step-without-unverifiable-finalize-hash'
  $continuationReceiptPath=Join-Path $control 'authorized-action-continuation.json';Write-Json $continuationReceiptPath $continuationWriteFinalizeRun.Value.continuationReceipt

  $testIntent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Test the exact authorized source postimage';requestedActionKind='TEST_RUN';requestedResultKind='TEST_RESULT';semanticHints=@('verification');pathHints=@('src/file.txt');capabilityHints=@();mutationHints=@('test');externalHints=@();ambiguityState='CLEAR'}
  $testDiscover=$continuationDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$testDiscover.intentEnvelope=$testIntent;$testDiscover|Add-Member -NotePropertyName continuationReceiptPath -NotePropertyValue $continuationReceiptPath;$testDiscover|Add-Member -NotePropertyName expectedContinuationReceiptIdentity -NotePropertyValue (Get-Identity $continuationReceiptPath)
  $prematureSourceReceiptPath=Join-Path $control 'premature-cleanup-source-receipt.json';Copy-Item -LiteralPath $continuationWriteReceiptPath -Destination $prematureSourceReceiptPath
  $prematureCleanupReceipt=$continuationWriteFinalizeRun.Value.continuationReceipt|ConvertTo-Json -Depth 50|ConvertFrom-Json;$prematureCleanupReceipt.sourceDiscoverReceiptPath=$prematureSourceReceiptPath;$prematureCleanupReceipt.sourceDiscoverReceiptIdentity=Get-Identity $prematureSourceReceiptPath
  $prematureCleanupReceiptPath=Join-Path $control 'premature-cleanup-continuation.json';Write-Json $prematureCleanupReceiptPath $prematureCleanupReceipt
  $prematureCleanupDiscover=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$prematureCleanupDiscover.continuationReceiptPath=$prematureCleanupReceiptPath;$prematureCleanupDiscover.expectedContinuationReceiptIdentity=Get-Identity $prematureCleanupReceiptPath;Write-Json $discoverPath $prematureCleanupDiscover
  $prematureDiscoverIdentity=Get-Identity $discoverPath;$prematurePostIdentity=Get-Identity (Join-Path $temp 'src/file.txt')
  function Observe-ContinuationSource([string]$Stage,$Run){
    $observation=[ordered]@{stage=$Stage;code=$Run.Code;result=$Run.Value;sourceReceiptPath=$prematureSourceReceiptPath;sourceExists=(Test-Path -LiteralPath $prematureSourceReceiptPath);sourceIdentity=$(if(Test-Path -LiteralPath $prematureSourceReceiptPath){Get-Identity $prematureSourceReceiptPath}else{'MISSING'});expectedSourceIdentity=$prematureCleanupReceipt.sourceDiscoverReceiptIdentity;continuationIdentity=Get-Identity $prematureCleanupReceiptPath;expectedContinuationIdentity=$prematureCleanupDiscover.expectedContinuationReceiptIdentity;discoverIdentity=Get-Identity $discoverPath;expectedDiscoverIdentity=$prematureDiscoverIdentity;postIdentity=Get-Identity (Join-Path $temp 'src/file.txt');expectedPostIdentity=$prematurePostIdentity}
    # Only current result metadata is emitted; the full raw result remains in the native evidence.
    $observation.result=[ordered]@{status=$Run.Value.status;reason=$(if($Run.Value.PSObject.Properties['reason']){$Run.Value.reason}else{$null})}
    Write-Output ('OBSERVE|continuation-source-retention|'+($observation|ConvertTo-Json -Depth 30 -Compress))
  }
  $prematureBeforeRun=Invoke-Resolver $resolver $discoverPath;Observe-ContinuationSource 'PRESENT_BEFORE_DELETE' $prematureBeforeRun;Assert-ResolverSuccess $prematureBeforeRun 'continuation-source-present-before-delete'
  Remove-Item -LiteralPath $prematureSourceReceiptPath
  $prematureCleanupRun=Invoke-Resolver $resolver $discoverPath;Observe-ContinuationSource 'MISSING_AFTER_DELETE' $prematureCleanupRun
  $prematureMissing=-not(Test-Path -LiteralPath $prematureSourceReceiptPath)
  $prematureReasons=@();if($prematureCleanupRun.Value.PSObject.Properties['reason']-and$prematureCleanupRun.Value.reason.StartsWith('AUTHORIZATION_CHECK_FAILED|FAIL|')){$prematureReasons=@($prematureCleanupRun.Value.reason.Substring('AUTHORIZATION_CHECK_FAILED|FAIL|'.Length).Split(','))}
  Copy-Item -LiteralPath $continuationWriteReceiptPath -Destination $prematureSourceReceiptPath
  $prematureRestoredRun=Invoke-Resolver $resolver $discoverPath;Observe-ContinuationSource 'PRESENT_AFTER_RESTORE' $prematureRestoredRun;Assert-ResolverSuccess $prematureRestoredRun 'continuation-source-restored-after-delete'
  # Missing evidence is distinct from identity drift. OBJECT_DRIFT is secondary:
  # rejection of the missing source prevents granting its authorized postimage map.
  Assert-True ($prematureBeforeRun.Code-eq0-and$prematureRestoredRun.Code-eq0-and$prematureMissing-and$prematureCleanupRun.Code-ne0-and$prematureCleanupRun.Value.status-ceq'FAIL'-and'EVIDENCE_OBJECT_MISSING'-cin$prematureReasons-and@($prematureReasons|Where-Object{$_-cnotin@('EVIDENCE_OBJECT_MISSING','OBJECT_DRIFT')}).Count-eq0-and(Get-Identity $prematureSourceReceiptPath)-ceq$prematureCleanupReceipt.sourceDiscoverReceiptIdentity-and(Get-Identity $prematureCleanupReceiptPath)-ceq$prematureCleanupDiscover.expectedContinuationReceiptIdentity-and(Get-Identity $discoverPath)-ceq$prematureDiscoverIdentity-and(Get-Identity (Join-Path $temp 'src/file.txt'))-ceq$prematurePostIdentity) 'continuation-source-receipt-cannot-be-cleaned-before-successor-boundary-consumes-it'

  $ungrantedTest=$actorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$ungrantedTest.intentEnvelope=$testIntent;Write-Json $discoverPath $ungrantedTest;$ungrantedTestRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($ungrantedTestRun.Code-ne0-and$ungrantedTestRun.Text.Contains('ACTION_NOT_GRANTED')) 'continuation-ungranted-test-action-rejected'
  $laterStepReceipt=$continuationWriteFinalizeRun.Value.continuationReceipt|ConvertTo-Json -Depth 50|ConvertFrom-Json;$laterStepReceipt.completedStepIndex=1;$laterStepReceipt.completedAction='TEST_RUN';$laterStepReceipt.nextStepIndex=2;$laterStepReceipt.nextAction='SOURCE_WRITE';$laterStepReceiptPath=Join-Path $control 'later-step-continuation.json';Write-Json $laterStepReceiptPath $laterStepReceipt
  $laterStepDiscover=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$laterStepDiscover.continuationReceiptPath=$laterStepReceiptPath;$laterStepDiscover.expectedContinuationReceiptIdentity=Get-Identity $laterStepReceiptPath;Write-Json $discoverPath $laterStepDiscover;$laterStepRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($laterStepRun.Code-ne0-and$laterStepRun.Text.Contains('CONTINUATION_SOURCE_ACTION_DRIFT')) 'continuation-valid-later-plan-pair-cannot-relabel-step-zero-source'
  $thirdParty=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$thirdParty.observedActor='third-party-fixture';Write-Json $discoverPath $thirdParty;$thirdPartyRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($thirdPartyRun.Code-ne0-and$thirdPartyRun.Text.Contains('TEMPORARY_ACTION_GRANTEE_DRIFT')) 'continuation-third-party-actor-rejected'
  $protectionDrift=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$protectionDrift.protectedPaths=@();Write-Json $discoverPath $protectionDrift;$protectionDriftRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($protectionDriftRun.Code-ne0-and$protectionDriftRun.Text.Contains('CONTINUATION_PROTECTION_SCOPE_DRIFT')) 'continuation-protection-scope-drift-rejected'
  Write-Utf8 (Join-Path $temp 'src\outside.txt') 'outside'
  $outsideContinuation=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$outsideContinuation.exactPaths=@('src/outside.txt');$outsideContinuation.intentEnvelope.pathHints=@('src/outside.txt');Write-Json $discoverPath $outsideContinuation;$outsideContinuationRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($outsideContinuationRun.Code-ne0-and$outsideContinuationRun.Text.Contains('OBSERVED_PATH_OUTSIDE_EXACT')) 'continuation-out-of-scope-action-rejected'
  $fabricatedReceipt=$continuationWriteFinalizeRun.Value.continuationReceipt|ConvertTo-Json -Depth 50|ConvertFrom-Json;$fabricatedReceipt.postObjectIdentities[0].identity='0|'+('0'*64);$fabricatedReceiptPath=Join-Path $control 'fabricated-continuation.json';Write-Json $fabricatedReceiptPath $fabricatedReceipt
  $fabricatedDiscover=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$fabricatedDiscover.continuationReceiptPath=$fabricatedReceiptPath;$fabricatedDiscover.expectedContinuationReceiptIdentity=Get-Identity $fabricatedReceiptPath;Write-Json $discoverPath $fabricatedDiscover;$fabricatedRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($fabricatedRun.Code-ne0-and$fabricatedRun.Text.Contains('OBJECT_DRIFT')) 'continuation-self-reported-postimage-cannot-grant-action'
  $mislinkedReceipt=$continuationWriteFinalizeRun.Value.continuationReceipt|ConvertTo-Json -Depth 50|ConvertFrom-Json;$mislinkedReceipt.packageIdentity='0|'+('0'*64);$mislinkedReceiptPath=Join-Path $control 'mislinked-continuation.json';Write-Json $mislinkedReceiptPath $mislinkedReceipt
  $mislinkedDiscover=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$mislinkedDiscover.continuationReceiptPath=$mislinkedReceiptPath;$mislinkedDiscover.expectedContinuationReceiptIdentity=Get-Identity $mislinkedReceiptPath;Write-Json $discoverPath $mislinkedDiscover;$mislinkedRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($mislinkedRun.Code-ne0-and$mislinkedRun.Text.Contains('CONTINUATION_RECEIPT_AUTHORITY_DRIFT')) 'continuation-wrong-package-link-rejected'
  $wrongSourceReceipt=$continuationWriteFinalizeRun.Value.continuationReceipt|ConvertTo-Json -Depth 50|ConvertFrom-Json;$wrongSourceReceipt.sourceDiscoverReceiptIdentity='0|'+('0'*64);$wrongSourceReceiptPath=Join-Path $control 'wrong-source-continuation.json';Write-Json $wrongSourceReceiptPath $wrongSourceReceipt
  $wrongSourceDiscover=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$wrongSourceDiscover.continuationReceiptPath=$wrongSourceReceiptPath;$wrongSourceDiscover.expectedContinuationReceiptIdentity=Get-Identity $wrongSourceReceiptPath;Write-Json $discoverPath $wrongSourceDiscover;$wrongSourceRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($wrongSourceRun.Code-ne0-and$wrongSourceRun.Text.Contains('CONTINUATION_SOURCE_RECEIPT_DRIFT')) 'continuation-wrong-finalized-result-link-rejected'
  Write-Utf8 (Join-Path $temp 'src\file.txt') 'stale postimage';Write-Json $discoverPath $testDiscover;$staleContinuationRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($staleContinuationRun.Code-ne0-and$staleContinuationRun.Text.Contains('OBJECT_DRIFT')) 'continuation-stale-postimage-rejected'
  Write-Utf8 (Join-Path $temp 'src\file.txt') 'first authorized postimage'

  Write-Json $discoverPath $testDiscover;$continuationTestRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $continuationTestRun 'continuation-test-discover'
  $continuationTestReceiptPath=Join-Path $control 'continuation-test-discover-receipt.json';Write-Json $continuationTestReceiptPath $continuationTestRun.Value.compactReceipt
  $continuationTestPrep=@($continuationTestRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$continuationTestResults=@($continuationTestRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $continuationTestBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$continuationTestReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $continuationTestReceiptPath;preparationReceipts=$continuationTestPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $continuationTestBoundary;$continuationTestAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationTestAdmit 'continuation-test-admit'
  $continuationFixturePath=Join-Path $temp 'src\file.txt';$quotedContinuationFixturePath=$continuationFixturePath.Replace("'","''");$continuationCheckCommand='$fixturePath='''+$quotedContinuationFixturePath+''';$actual=[IO.File]::ReadAllText($fixturePath).TrimEnd([char[]]"`r`n");if($actual-cne''bounded local fix''){[Console]::Error.WriteLine((''CONTINUATION_FIXTURE_CHECK_FAILED|actual=''+$actual));exit 17};[Console]::Out.WriteLine(''CONTINUATION_FIXTURE_CHECK_PASS'');exit 0'
  $continuationFirstCheckOutput=@(& pwsh -NoLogo -NoProfile -NonInteractive -Command $continuationCheckCommand 2>&1|ForEach-Object{[string]$_});$continuationFirstCheckExit=$LASTEXITCODE;$continuationFirstCheckFileText=[IO.File]::ReadAllText($continuationFixturePath).TrimEnd([char[]]"`r`n");Write-Output ('OBSERVED|continuation-first-check|exit='+$continuationFirstCheckExit+'|output='+($continuationFirstCheckOutput-join';'))
  $continuationTestFinalize=$continuationTestBoundary|ConvertTo-Json -Depth 50|ConvertFrom-Json;$continuationTestFinalize.mode='FINALIZE_OUTPUT';$continuationTestFinalize.schemaVersion=3
  $continuationTestFinalize|Add-Member evidenceRefs @(New-ContinuationEvidence 'first-check' $continuationTestRun.Value.compactReceipt.binding.actor $continuationPackage.taskId $continuationFirstCheckExit $continuationFirstCheckOutput $continuationCheckCommand)
  $continuationTestFinalize.resultReceipts=@($continuationTestResults);$continuationTestFinalize.resultReceipts+=('TEST_PROCESS_EXIT|'+$continuationFirstCheckExit);$continuationTestFinalize.resultReceipts+=('OBJECT_POSTIMAGE|src/file.txt|'+(Get-Identity $continuationFixturePath));Write-Json $boundaryPath $continuationTestFinalize;$continuationTestFinalizeRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationTestFinalizeRun 'continuation-test-finalize'
  $fixContinuationReceiptPath=Join-Path $control 'authorized-fix-continuation.json';Write-Json $fixContinuationReceiptPath $continuationTestFinalizeRun.Value.continuationReceipt
  Remove-Item -LiteralPath $continuationWriteReceiptPath,$continuationReceiptPath
  Assert-True (-not(Test-Path -LiteralPath $continuationWriteReceiptPath)-and-not(Test-Path -LiteralPath $continuationReceiptPath)-and(Test-Path -LiteralPath $continuationTestReceiptPath)-and(Test-Path -LiteralPath $fixContinuationReceiptPath)) 'continuation-source-pair-cleans-only-after-successor-finalize-and-successor-receipt-save'
  $fixDiscover=$continuationDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$fixDiscover|Add-Member -NotePropertyName continuationReceiptPath -NotePropertyValue $fixContinuationReceiptPath;$fixDiscover|Add-Member -NotePropertyName expectedContinuationReceiptIdentity -NotePropertyValue (Get-Identity $fixContinuationReceiptPath)
  Write-Json $discoverPath $fixDiscover;$continuationFixRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $continuationFixRun 'continuation-fix-discover'
  $continuationFixReceiptPath=Join-Path $control 'continuation-fix-discover-receipt.json';Write-Json $continuationFixReceiptPath $continuationFixRun.Value.compactReceipt
  $continuationFixPrep=@($continuationFixRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$continuationFixResults=@($continuationFixRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $continuationFixBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$continuationFixReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $continuationFixReceiptPath;preparationReceipts=$continuationFixPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $continuationFixBoundary;$continuationFixAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationFixAdmit 'continuation-fix-admit'
  Write-Utf8 $continuationFixturePath 'bounded local fix'
  $continuationFixFinalize=$continuationFixBoundary|ConvertTo-Json -Depth 50|ConvertFrom-Json;$continuationFixFinalize.mode='FINALIZE_OUTPUT';$continuationFixFinalize.resultReceipts=@($continuationFixResults);$continuationFixFinalize.resultReceipts+=('OBJECT_POSTIMAGE|src/file.txt|'+(Get-Identity $continuationFixturePath));Write-Json $boundaryPath $continuationFixFinalize;$continuationFixFinalizeRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationFixFinalizeRun 'continuation-fix-finalize'
  $retestContinuationReceiptPath=Join-Path $control 'authorized-retest-continuation.json';Write-Json $retestContinuationReceiptPath $continuationFixFinalizeRun.Value.continuationReceipt
  $retestDiscover=$testDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$retestDiscover.continuationReceiptPath=$retestContinuationReceiptPath;$retestDiscover.expectedContinuationReceiptIdentity=Get-Identity $retestContinuationReceiptPath
  Write-Json $discoverPath $retestDiscover;$continuationRetestRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $continuationRetestRun 'continuation-retest-discover'
  $continuationRetestReceiptPath=Join-Path $control 'continuation-retest-discover-receipt.json';Write-Json $continuationRetestReceiptPath $continuationRetestRun.Value.compactReceipt
  $continuationRetestPrep=@($continuationRetestRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$continuationRetestResults=@($continuationRetestRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $continuationRetestBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$continuationRetestReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $continuationRetestReceiptPath;preparationReceipts=$continuationRetestPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $continuationRetestBoundary;$continuationRetestAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationRetestAdmit 'continuation-retest-admit'
  $continuationSecondCheckOutput=@(& pwsh -NoLogo -NoProfile -NonInteractive -Command $continuationCheckCommand 2>&1|ForEach-Object{[string]$_});$continuationSecondCheckExit=$LASTEXITCODE;$continuationSecondCheckFileText=[IO.File]::ReadAllText($continuationFixturePath).TrimEnd([char[]]"`r`n");Write-Output ('OBSERVED|continuation-second-check|exit='+$continuationSecondCheckExit+'|output='+($continuationSecondCheckOutput-join';'))
  $continuationRetestFinalize=$continuationRetestBoundary|ConvertTo-Json -Depth 50|ConvertFrom-Json;$continuationRetestFinalize.mode='FINALIZE_OUTPUT';$continuationRetestFinalize.schemaVersion=3
  $continuationRetestFinalize|Add-Member evidenceRefs @(New-ContinuationEvidence 'second-check' $continuationRetestRun.Value.compactReceipt.binding.actor $continuationPackage.taskId $continuationSecondCheckExit $continuationSecondCheckOutput $continuationCheckCommand)
  $continuationRetestFinalize.resultReceipts=@($continuationRetestResults);$continuationRetestFinalize.resultReceipts+=('TEST_PROCESS_EXIT|'+$continuationSecondCheckExit);$continuationRetestFinalize.resultReceipts+=('OBJECT_POSTIMAGE|src/file.txt|'+(Get-Identity $continuationFixturePath));Write-Json $boundaryPath $continuationRetestFinalize;$continuationRetestFinalizeRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $continuationRetestFinalizeRun 'continuation-retest-finalize'
  $retestHasNoSuccessor=$continuationRetestFinalizeRun.Code-eq0-and$null-eq$continuationRetestFinalizeRun.Value.PSObject.Properties['continuationReceipt']
  $continuationPackageStable=(Get-Identity $continuationPackagePath)-ceq$continuationPackageIdentity-and[string]$continuationWriteRun.Value.compactReceipt.binding.authorizationIdentity-ceq$continuationPackageIdentity-and[string]$continuationTestRun.Value.compactReceipt.binding.authorizationIdentity-ceq$continuationPackageIdentity-and[string]$continuationFixRun.Value.compactReceipt.binding.authorizationIdentity-ceq$continuationPackageIdentity-and[string]$continuationRetestRun.Value.compactReceipt.binding.authorizationIdentity-ceq$continuationPackageIdentity
  $continuationContextStable=$true;foreach($cycleRun in @($continuationWriteRun,$continuationTestRun,$continuationFixRun,$continuationRetestRun)){$cycleBinding=$cycleRun.Value.compactReceipt.binding;if([string]$cycleBinding.taskIdentity-cne[string]$continuationPackage.taskIdentity-or[string]$cycleBinding.taskOwner-cne'owner-fixture'-or[string]$cycleBinding.taskActor-cne'owner-fixture'-or[string]$cycleBinding.actor-cne'executor-fixture'-or[string]::Join("`n",@($cycleBinding.exactScope))-cne'src/file.txt'){$continuationContextStable=$false}}
  $continuationStepsExact=[int]$continuationWriteRun.Value.compactReceipt.binding.continuationStepIndex-eq0-and[int]$continuationTestRun.Value.compactReceipt.binding.continuationStepIndex-eq1-and[int]$continuationFixRun.Value.compactReceipt.binding.continuationStepIndex-eq2-and[int]$continuationRetestRun.Value.compactReceipt.binding.continuationStepIndex-eq3-and[int]$continuationWriteFinalizeRun.Value.continuationReceipt.completedStepIndex-eq0-and[int]$continuationTestFinalizeRun.Value.continuationReceipt.completedStepIndex-eq1-and[int]$continuationFixFinalizeRun.Value.continuationReceipt.completedStepIndex-eq2
  Assert-True ($continuationFirstCheckExit-ne0-and($continuationFirstCheckOutput-join"`n").Contains('CONTINUATION_FIXTURE_CHECK_FAILED')-and$continuationFirstCheckFileText-ceq'first authorized postimage') 'continuation-real-check-observes-nonzero-exit-before-bounded-fix'
  Assert-True ($continuationSecondCheckExit-eq0-and($continuationSecondCheckOutput-join"`n").Contains('CONTINUATION_FIXTURE_CHECK_PASS')-and$continuationSecondCheckFileText-ceq'bounded local fix') 'continuation-same-real-check-passes-after-bounded-fix'
  Assert-True ($continuationPackageStable-and$continuationContextStable) 'continuation-real-cycle-keeps-original-package-identity-owner-actor-and-scope'
  Assert-True ($continuationWriteRun.Code-eq0-and$continuationWriteAdmit.Code-eq0-and$continuationWriteFinalizeRun.Code-eq0-and$continuationTestRun.Code-eq0-and$continuationTestAdmit.Code-eq0-and$continuationTestFinalizeRun.Code-eq0-and$continuationFixRun.Code-eq0-and$continuationFixAdmit.Code-eq0-and$continuationFixFinalizeRun.Code-eq0-and$continuationRetestRun.Code-eq0-and$continuationRetestAdmit.Code-eq0-and$continuationStepsExact-and$retestHasNoSuccessor) 'continuation-write-failing-check-bounded-fix-retest-completes-one-preauthorized-plan'
  Write-Utf8 (Join-Path $temp 'src\file.txt') 'old'

  # Actual SOURCE_WRITE -> REVIEW_ROUTE with a document self-check, no TEST_RUN.
  $docPackage=$continuationPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $docPackage.actions=@('SOURCE_WRITE','REVIEW_ROUTE');$docPackage.continuationPlan=@('SOURCE_WRITE','REVIEW_ROUTE')
  $docPackagePath=Join-Path $control 'document-route-package.json';Write-Json $docPackagePath $docPackage
  $docDiscover=$actorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $docDiscover.authorizationPackagePath=$docPackagePath;$docDiscover.expectedAuthorizationIdentity=Get-Identity $docPackagePath
  Write-Json $discoverPath $docDiscover;$docRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $docRun 'document-producer-discover'
  $docReceiptPath=Join-Path $control 'document-producer-receipt.json';Write-Json $docReceiptPath $docRun.Value.compactReceipt
  $docBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$docReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $docReceiptPath;preparationReceipts=@($docRun.Value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  Write-Json $boundaryPath $docBoundary;Assert-ResolverSuccess (Invoke-Resolver $resolver $boundaryPath) 'document-producer-admit'
  Write-Utf8 (Join-Path $temp 'src/file.txt') 'Document candidate with observed local self-check.'
  $docBoundary.mode='FINALIZE_OUTPUT';$docBoundary.resultReceipts=@($docRun.Value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|src/file.txt|'+(Get-Identity (Join-Path $temp 'src/file.txt')))
  Write-Json $boundaryPath $docBoundary;$missingDocEvidence=Invoke-Resolver $resolver $boundaryPath
  Assert-True ($missingDocEvidence.Code-ne0-and$missingDocEvidence.Text.Contains('REVIEW_SELF_CHECK_REQUIRED')) 'document-continuation-does-not-invent-self-check'
  $docBoundary.evidenceRefs=@(New-ContinuationEvidence 'document-self-check' $docRun.Value.compactReceipt.binding.actor $docPackage.taskId 0 @())
  Write-Json $boundaryPath $docBoundary;$docFinal=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $docFinal 'document-producer-finalize'
  $docContinuationPath=Join-Path $control 'document-route-continuation.json';Write-Json $docContinuationPath $docFinal.Value.continuationReceipt
  $docRoute=$docDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $docRoute|Add-Member continuationReceiptPath $docContinuationPath;$docRoute|Add-Member expectedContinuationReceiptIdentity (Get-Identity $docContinuationPath)
  $docRoute.intentEnvelope.requestedActionKind='REVIEW_ROUTE';$docRoute.intentEnvelope.requestedResultKind='HANDOFF';$docRoute.intentEnvelope.semanticHints=@('independent review route');$docRoute.intentEnvelope.mutationHints=@('review')
  Write-Json $discoverPath $docRoute;$docRouted=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $docRouted 'document-review-route-discover'
  Assert-True ('REVIEW_VERDICT_BOUND'-cnotin@($docRouted.Value.compactReceipt.selectedObligations.resultRequirements)) 'review-route-has-no-future-verdict-obligation'
  $docRouteReceiptPath=Join-Path $control 'document-route-receipt.json';Write-Json $docRouteReceiptPath $docRouted.Value.compactReceipt
  $docReviewer=$docPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $docReviewer.PSObject.Properties.Remove('continuationPlan');$docReviewer.grantee='document-reviewer-fixture';$docReviewer.actions=@('REVIEW_EXECUTE');$docReviewer.reviewIndependence='INDEPENDENT'
  $docReviewer|Add-Member candidateWriter $docPackage.grantee;$docReviewer|Add-Member materialContributors @();$docReviewer.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE')
  $docReviewer.objectIdentities=@([pscustomobject]@{path='src/file.txt';identity=Get-Identity (Join-Path $temp 'src/file.txt')})
  $docReviewerPath=Join-Path $control 'document-pure-review-package.json';Write-Json $docReviewerPath $docReviewer
  $docRouteBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$docRouteReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $docRouteReceiptPath;preparationReceipts=@($docRouted.Value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=$docBoundary.evidenceRefs}
  $docRouteBoundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient=$docReviewer.grantee;observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=[ordered]@{path=$docReviewerPath;identity=Get-Identity $docReviewerPath}}
  Write-Json $boundaryPath $docRouteBoundary;$docAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $docAdmit 'docAdmit'
  Assert-True ($docAdmit.Code-eq0) ('document-review-route-admits-without-test-run|'+$docAdmit.Text)
  $docRouteBoundary.mode='FINALIZE_OUTPUT';$docRouteBoundary.resultReceipts=@($docRouted.Value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|src/file.txt|'+(Get-Identity (Join-Path $temp 'src/file.txt')));$docRouteBoundary.deliveryReceipts=@('FIXTURE_REVIEW_ROUTE_OBSERVED')
  $docReviewDiscover=$docDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $docReviewDiscover.observedActor=$docReviewer.grantee;$docReviewDiscover.authorizationPackagePath=$docReviewerPath;$docReviewDiscover.expectedAuthorizationIdentity=Get-Identity $docReviewerPath
  $docReviewDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$docReviewDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$docReviewDiscover.intentEnvelope.semanticHints=@('document review');$docReviewDiscover.intentEnvelope.mutationHints=@()
  Write-Json $discoverPath $docReviewDiscover;$docReviewReady=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $docReviewReady 'docReviewReady'
  if($docReviewReady.Code-ne0){Write-Output ('DIAG|document-pure-review-package|'+$docReviewReady.Text)}
  Assert-True ($docReviewReady.Code-eq0) 'document-pure-review-package-passes-current-authority'
  $docHostPath=Join-Path $control 'document-mock-host-result.json';Write-Json $docHostPath ([ordered]@{isError=$false;content=@([ordered]@{type='text';text='{"threadId":"document-reviewer-fixture"}'})})
  $docRouteBoundary.deliveryReceipts=@();$docRouteBoundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient=$docReviewer.grantee;observedRecipient=$docReviewer.grantee;outcome='SUCCESS';evidence=($docHostPath+'#'+(Get-Identity $docHostPath));reviewPackageRef=[ordered]@{path=$docReviewerPath;identity=Get-Identity $docReviewerPath}}
  Write-Json $boundaryPath $docRouteBoundary;$docClosed=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $docClosed 'docClosed'
  Assert-True ($docClosed.Code-eq0) ('document-review-route-finalizes-without-future-verdict|'+$docClosed.Text)
  Write-Utf8 (Join-Path $temp 'src/file.txt') 'old'

  $ownerPhaseIntent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Plan the current task phase without performing an action';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('task phase');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
  $ownerPhaseDiscover=$actorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$ownerPhaseDiscover.observedActor='owner-fixture';$ownerPhaseDiscover.capabilities=@();$ownerPhaseDiscover.exactPaths=@();$ownerPhaseDiscover.forbiddenPaths=@();$ownerPhaseDiscover.protectedPaths=@();$ownerPhaseDiscover.authorizationPackagePath='NOT_REQUIRED';$ownerPhaseDiscover.expectedAuthorizationIdentity='NOT_REQUIRED';$ownerPhaseDiscover.intentEnvelope=$ownerPhaseIntent
  Write-Json $discoverPath $ownerPhaseDiscover;$ownerPhaseBefore=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $ownerPhaseBefore 'ownerPhaseBefore'
  $actorTaskOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath
  Write-Utf8 $taskPath ($actorTaskOriginal-replace'phase=IMPLEMENT','phase=VERIFY')
  Write-Json $boundaryPath $actorBoundary;$stalePhaseBoundary=Invoke-Resolver $resolver $boundaryPath
  $ownerPhaseAfterDiscover=$ownerPhaseDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$ownerPhaseAfterDiscover.expectedTaskIdentity=Get-Identity $taskPath
  Write-Json $discoverPath $ownerPhaseAfterDiscover;$ownerPhaseAfter=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $ownerPhaseAfter 'ownerPhaseAfter'
  $phasePackage=$package|ConvertTo-Json -Depth 100|ConvertFrom-Json;$phasePackage.taskIdentity=Get-Identity $taskPath
  $phasePackagePath=Join-Path $control 'phase-drift-package.json';Write-Json $phasePackagePath $phasePackage
  $phaseDiscover=$actorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json;$phaseDiscover.expectedTaskIdentity=Get-Identity $taskPath;$phaseDiscover.authorizationPackagePath=$phasePackagePath;$phaseDiscover.expectedAuthorizationIdentity=Get-Identity $phasePackagePath
  Write-Json $discoverPath $phaseDiscover;$phaseRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $phaseRun 'phaseRun'
  $staleTaskPhaseRejected=$stalePhaseBoundary.Code-ne0-and$stalePhaseBoundary.Text.Contains('DISCOVER_SOURCE_DRIFT|taskIdentity')
  $temporaryTaskPhaseRebound=$phaseRun.Code-eq0-and[string]$phaseRun.Value.compactReceipt.binding.taskActor-ceq'owner-fixture'-and[string]$phaseRun.Value.compactReceipt.binding.actor-ceq'executor-fixture'-and[string]$phaseRun.Value.compactReceipt.binding.role-ceq'EXECUTOR'-and[string]$phaseRun.Value.compactReceipt.binding.phase-ceq'IMPLEMENT'-and[string]$phaseRun.Value.compactReceipt.binding.taskIdentity-cne[string]$actorRun.Value.compactReceipt.binding.taskIdentity-and[string]$phaseRun.Value.compactReceipt.sourceCompositionIdentity-cne[string]$actorRun.Value.compactReceipt.sourceCompositionIdentity-and[string]$phaseRun.Value.compactReceipt.selectionIdentity-cne[string]$actorRun.Value.compactReceipt.selectionIdentity-and[string]$phaseRun.Value.compactReceipt.contextIdentity-cne[string]$actorRun.Value.compactReceipt.contextIdentity
  $ownerTaskPhaseRebound=$ownerPhaseBefore.Code-eq0-and$ownerPhaseAfter.Code-eq0-and[string]$ownerPhaseBefore.Value.compactReceipt.binding.phase-ceq'IMPLEMENT'-and[string]$ownerPhaseAfter.Value.compactReceipt.binding.phase-ceq'VERIFY'-and[string]$ownerPhaseAfter.Value.compactReceipt.binding.taskIdentity-cne[string]$ownerPhaseBefore.Value.compactReceipt.binding.taskIdentity-and[string]$ownerPhaseAfter.Value.compactReceipt.sourceCompositionIdentity-cne[string]$ownerPhaseBefore.Value.compactReceipt.sourceCompositionIdentity-and[string]$ownerPhaseAfter.Value.compactReceipt.selectionIdentity-cne[string]$ownerPhaseBefore.Value.compactReceipt.selectionIdentity-and[string]$ownerPhaseAfter.Value.compactReceipt.contextIdentity-cne[string]$ownerPhaseBefore.Value.compactReceipt.contextIdentity
  if(-not($staleTaskPhaseRejected-and$temporaryTaskPhaseRebound-and$ownerTaskPhaseRebound)){
    $phaseBeforeBinding=if($actorRun.Code-eq0){$actorRun.Value.compactReceipt.binding}else{$null};$phaseAfterBinding=if($phaseRun.Code-eq0){$phaseRun.Value.compactReceipt.binding}else{$null}
    $beforeTask=if($null-ne$phaseBeforeBinding){[string]$phaseBeforeBinding.taskIdentity}else{'UNAVAILABLE'};$afterTask=if($null-ne$phaseAfterBinding){[string]$phaseAfterBinding.taskIdentity}else{'UNAVAILABLE'}
    $beforeActor=if($null-ne$phaseBeforeBinding){[string]$phaseBeforeBinding.actor}else{'UNAVAILABLE'};$afterActor=if($null-ne$phaseAfterBinding){[string]$phaseAfterBinding.actor}else{'UNAVAILABLE'}
    $beforeRole=if($null-ne$phaseBeforeBinding){[string]$phaseBeforeBinding.role}else{'UNAVAILABLE'};$afterRole=if($null-ne$phaseAfterBinding){[string]$phaseAfterBinding.role}else{'UNAVAILABLE'}
    $beforePhase=if($null-ne$phaseBeforeBinding){[string]$phaseBeforeBinding.phase}else{'UNAVAILABLE'};$afterPhase=if($null-ne$phaseAfterBinding){[string]$phaseAfterBinding.phase}else{'UNAVAILABLE'}
    Write-Output ('DIAG|task-phase-drift|staleExit='+$stalePhaseBoundary.Code+'|staleReason='+$stalePhaseBoundary.Text+'|freshExit='+$phaseRun.Code+'|freshReason='+$phaseRun.Text+'|beforeTask='+$beforeTask+'|afterTask='+$afterTask+'|beforeActor='+$beforeActor+'|afterActor='+$afterActor+'|beforeRole='+$beforeRole+'|afterRole='+$afterRole+'|beforePhase='+$beforePhase+'|afterPhase='+$afterPhase+'|compositionChanged='+($phaseRun.Code-eq0-and$actorRun.Code-eq0-and[string]$phaseRun.Value.compactReceipt.sourceCompositionIdentity-cne[string]$actorRun.Value.compactReceipt.sourceCompositionIdentity)+'|selectionChanged='+($phaseRun.Code-eq0-and$actorRun.Code-eq0-and[string]$phaseRun.Value.compactReceipt.selectionIdentity-cne[string]$actorRun.Value.compactReceipt.selectionIdentity)+'|contextChanged='+($phaseRun.Code-eq0-and$actorRun.Code-eq0-and[string]$phaseRun.Value.compactReceipt.contextIdentity-cne[string]$actorRun.Value.compactReceipt.contextIdentity))
  }
  Assert-True $staleTaskPhaseRejected 'actual-task-phase-drift-rejects-old-receipt'
  Assert-True $temporaryTaskPhaseRebound 'fresh-temporary-action-keeps-action-phase-and-rebinds-task-identities'
  Assert-True $ownerTaskPhaseRebound 'fresh-task-actor-phase-change-rebinds-source-selection-and-context'

  $taskRelative='.ai-workspace/tasks/active/PROCESS-V2-001.md'
  Write-Utf8 $taskPath "# PROCESS-V2-001 — runtime contract fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[$taskRelative]; actual_paths=[$taskRelative]`n"
  $taskPackage=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='PROCESS-V2-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='PLAN_LOCAL';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@('CONTROL_WRITE');exactPaths=@($taskRelative);objectIdentities=@([ordered]@{path=$taskRelative;identity=Get-Identity $taskPath});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=Get-Identity (Join-Path $control 'project.json')}
  $taskPackagePath=Join-Path $control 'task-write-package.json';Write-Json $taskPackagePath $taskPackage
  $taskIntent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}};objective='Finalize one bounded task record';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('task','control');pathHints=@($taskRelative);capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'}
  $taskDiscover=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='owner-fixture';capabilities=@();exactPaths=@($taskRelative);forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath=$taskPackagePath;expectedAuthorizationIdentity=Get-Identity $taskPackagePath;userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$taskIntent;evaluationOnly=$false}
  $taskPreText=Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath
  $temporaryTaskPackage=$taskPackage|ConvertTo-Json -Depth 50|ConvertFrom-Json;$temporaryTaskPackage.grantee='executor-fixture';$temporaryTaskPackagePath=Join-Path $control 'task-write-temporary-package.json';Write-Json $temporaryTaskPackagePath $temporaryTaskPackage
  $temporaryTaskDiscover=$taskDiscover|ConvertTo-Json -Depth 50|ConvertFrom-Json;$temporaryTaskDiscover.observedActor='executor-fixture';$temporaryTaskDiscover.authorizationPackagePath=$temporaryTaskPackagePath;$temporaryTaskDiscover.expectedAuthorizationIdentity=Get-Identity $temporaryTaskPackagePath
  Write-Json $discoverPath $temporaryTaskDiscover;$temporaryTaskRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $temporaryTaskRun 'temporaryTaskRun';$temporaryTaskReceiptPath=Join-Path $control 'task-write-temporary-receipt.json';Write-Json $temporaryTaskReceiptPath $temporaryTaskRun.Value.compactReceipt
  $temporaryTaskPrep=@($temporaryTaskRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$temporaryTaskResults=@($temporaryTaskRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $temporaryTaskBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$temporaryTaskReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $temporaryTaskReceiptPath;preparationReceipts=$temporaryTaskPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $temporaryTaskBoundary;$temporaryTaskAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $temporaryTaskAdmit 'temporaryTaskAdmit';Write-Utf8 $taskPath ($taskPreText.TrimEnd("`n")+"`n`n- Completion: TEMPORARY_ACTOR_ATTEMPT`n")
  $temporaryTaskFinalize=$temporaryTaskBoundary|ConvertTo-Json -Depth 50|ConvertFrom-Json;$temporaryTaskFinalize.mode='FINALIZE_OUTPUT';$temporaryTaskFinalize.resultReceipts=@($temporaryTaskResults+@('OBJECT_POSTIMAGE|'+$taskRelative+'|'+(Get-Identity $taskPath)));Write-Json $boundaryPath $temporaryTaskFinalize;$temporaryTaskFinalizeRun=Invoke-Resolver $resolver $boundaryPath
  Assert-True ($temporaryTaskRun.Code-eq0-and$temporaryTaskAdmit.Code-eq0-and$temporaryTaskFinalizeRun.Code-ne0-and$temporaryTaskFinalizeRun.Text.Contains('CONTROL_TASK_POSTIMAGE_TRANSITION_NOT_AUTHORIZED')) 'temporary-action-actor-cannot-use-same-receipt-to-rewrite-task-card'
  Write-Utf8 $taskPath $taskPreText
  $closureDocRelative='docs/closure.md';$closureDocPath=Join-Path $temp $closureDocRelative;Write-Utf8 $closureDocPath 'Document before closure.'
  $closurePackage=$taskPackage|ConvertTo-Json -Depth 50|ConvertFrom-Json;$closurePackage.actions=@('SOURCE_WRITE');$closurePackage.exactPaths=@($closureDocRelative);$closurePackage.objectIdentities=@([ordered]@{path=$closureDocRelative;identity=Get-Identity $closureDocPath});$closurePackagePath=Join-Path $control 'document-closure-package.json';Write-Json $closurePackagePath $closurePackage
  $closureDiscover=$taskDiscover|ConvertTo-Json -Depth 50|ConvertFrom-Json;$closureDiscover.exactPaths=@($closureDocRelative);$closureDiscover.authorizationPackagePath=$closurePackagePath;$closureDiscover.expectedAuthorizationIdentity=Get-Identity $closurePackagePath;$closureDiscover.intentEnvelope.requestedActionKind='SOURCE_WRITE';$closureDiscover.intentEnvelope.semanticHints=@('changed output disposition');$closureDiscover.intentEnvelope.pathHints=@($closureDocRelative);$closureDiscover.intentEnvelope.mutationHints=@('source')
  Write-Json $discoverPath $closureDiscover;$closureRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $closureRun 'document-before-card-discover'
  $closureReceiptPath=Join-Path $control 'document-closure-receipt.json';Write-Json $closureReceiptPath $closureRun.Value.compactReceipt
  $closureBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$closureReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $closureReceiptPath;preparationReceipts=@($closureRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $closureBoundary;$closureAdmit=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $closureAdmit 'document-before-card-admit'
  Write-Utf8 $closureDocPath 'Document completed before current task mutation.';$closureDocumentIdentity=Get-Identity $closureDocPath
  $closureBoundary.mode='FINALIZE_OUTPUT';$closureBoundary.resultReceipts=@($closureRun.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$closureDocRelative+'|'+$closureDocumentIdentity);Write-Json $boundaryPath $closureBoundary;$closureFinal=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $closureFinal 'closureFinal'
  Assert-True ($closureFinal.Code-eq0-and(Get-Identity $taskPath)-ceq$taskPackage.taskIdentity) 'document-finalizes-before-current-card-without-task-restore'
  Write-Json $discoverPath $taskDiscover;$taskDiscoverRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $taskDiscoverRun 'taskDiscoverRun'
  $taskReceiptPath=Join-Path $control 'task-write-receipt.json';Write-Json $taskReceiptPath $taskDiscoverRun.Value.compactReceipt
  $taskPrep=@($taskDiscoverRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
  $taskResults=@($taskDiscoverRun.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $taskBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$taskReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $taskReceiptPath;preparationReceipts=$taskPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  Write-Json $boundaryPath $taskBoundary;$taskAdmitRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $taskAdmitRun 'taskAdmitRun'
  Assert-True ($taskDiscoverRun.Code-eq0-and$taskAdmitRun.Code-eq0) 'repo-local-self-card-control-write-admits-exact-task-preimage'
  $taskPostText=(Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath).TrimEnd("`n")+"`n`n- Completion: STRUCTURALLY_FINALIZED`n";Write-Utf8 $taskPath $taskPostText
  $taskFinalize=$taskBoundary|ConvertTo-Json -Depth 50|ConvertFrom-Json;$taskFinalize.mode='FINALIZE_OUTPUT';$taskFinalize.resultReceipts=@($taskResults+@('OBJECT_POSTIMAGE|'+$taskRelative+'|'+(Get-Identity $taskPath)));Write-Json $boundaryPath $taskFinalize;$taskFinalizeRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $taskFinalizeRun 'taskFinalizeRun'
  Assert-True ($taskFinalizeRun.Code-eq0-and(Get-Identity $closureDocPath)-ceq$closureDocumentIdentity) 'repo-local-document-then-self-card-finalize-preserves-completed-document'
  $taskBindingDrifts=@(
    [pscustomobject]@{Name='task-id';Text=$taskPostText-replace '^# PROCESS-V2-001 ','# PROCESS-V2-OTHER '},
    [pscustomobject]@{Name='owner';Text=$taskPostText-replace '(?m)^- Owner: owner-fixture$','- Owner: other-owner'},
    [pscustomobject]@{Name='actor';Text=$taskPostText-replace 'actor=owner-fixture','actor=successor-fixture'},
    [pscustomobject]@{Name='role';Text=$taskPostText-replace 'role=TASK_OWNER','role=EXECUTOR'},
    [pscustomobject]@{Name='phase';Text=$taskPostText-replace 'phase=IMPLEMENT','phase=PLAN'},
    [pscustomobject]@{Name='profile';Text=$taskPostText-replace 'profile=STANDARD','profile=CRITICAL'}
  )
  foreach($drift in $taskBindingDrifts){
    Write-Utf8 $taskPath $drift.Text
    $driftFinalize=$taskFinalize|ConvertTo-Json -Depth 50|ConvertFrom-Json;$driftFinalize.resultReceipts=@($taskResults+@('OBJECT_POSTIMAGE|'+$taskRelative+'|'+(Get-Identity $taskPath)));Write-Json $boundaryPath $driftFinalize;$driftRun=Invoke-Resolver $resolver $boundaryPath
    Assert-True ($driftRun.Code-ne0-and$driftRun.Text.Contains('CONTROL_TASK_POSTIMAGE_BINDING_DRIFT')) ('repo-local-self-card-finalize-rejects-'+$drift.Name+'-drift')
  }
  $successorTaskText=$taskPostText-replace 'actor=owner-fixture; role=TASK_OWNER','actor=successor-fixture; role=EXECUTOR';Write-Utf8 $taskPath $successorTaskText
  $successorPackage=$taskPackage|ConvertTo-Json -Depth 50|ConvertFrom-Json;$successorPackage.grantee='successor-fixture';$successorPackage.taskIdentity=Get-Identity $taskPath;$successorPackage.objectIdentities[0].identity=Get-Identity $taskPath
  $successorPackagePath=Join-Path $control 'task-write-successor-package.json';Write-Json $successorPackagePath $successorPackage
  $successorDiscover=$taskDiscover|ConvertTo-Json -Depth 50|ConvertFrom-Json;$successorDiscover.expectedTaskIdentity=Get-Identity $taskPath;$successorDiscover.observedActor='successor-fixture';$successorDiscover.authorizationPackagePath=$successorPackagePath;$successorDiscover.expectedAuthorizationIdentity=Get-Identity $successorPackagePath
  Write-Json $discoverPath $successorDiscover;$successorRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $successorRun 'successorRun'
  Assert-True ($successorRun.Code-eq0-and[string]$successorRun.Value.compactReceipt.binding.taskActor-ceq'successor-fixture'-and[string]$successorRun.Value.compactReceipt.binding.actor-ceq'successor-fixture'-and[string]$successorRun.Value.compactReceipt.binding.role-ceq'EXECUTOR'-and[string]$successorRun.Value.compactReceipt.binding.phase-ceq'IMPLEMENT'-and[string]$successorRun.Value.compactReceipt.binding.profile-ceq'STANDARD') 'fresh-package-and-discover-rebind-current-task-route-without-permanent-actor-lock'

  $compositionArgs=@{ProjectRoot=$temp;FrameworkRoot=$frameworkRoot;TargetVersion='2.0.0';ExpectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');ExpectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');Profile='CRITICAL';Role='FRAMEWORK_MAINTAINER';Phase='IMPLEMENT';Actor='owner-fixture';TaskIdentity=Get-Identity $taskPath;Capabilities=@();Objective='Edit the upgrade-project tool implementation';ActionKind='CONTROL_WRITE';ResultKind='IMPLEMENTATION_RESULT';ExactPaths=@('scripts/upgrade-project.ps1');EvaluationOnly=$true}
  $toolingComposition=Invoke-ProcessRequirementComposition @compositionArgs
  $toolingIds=@($toolingComposition.selectedRequirements|ForEach-Object{[string]$_.requirementId})
  $compositionArgs.Objective='Upgrade the project pin and managed control projection';$compositionArgs.ExactPaths=@('.ai-workspace/project.json');$adoptionComposition=Invoke-ProcessRequirementComposition @compositionArgs;$adoptionIds=@($adoptionComposition.selectedRequirements|ForEach-Object{[string]$_.requirementId})
  Assert-True ('framework:PR_PROJECT_UPGRADE_ACTOR_BOUND'-cnotin$toolingIds-and'framework:PR_PROJECT_UPGRADE_ACTOR_BOUND'-cin$adoptionIds) 'project-upgrade-rule-is-bound-to-project-control-path-not-tool-source-edit'

  $gitDirectory=Join-Path $temp '.git';$heldGitDirectory=Join-Path $temp '.git-held'
  if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($gitDirectory))-cne[IO.Path]::GetFullPath($temp)-or[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($heldGitDirectory))-cne[IO.Path]::GetFullPath($temp)-or-not(Test-Path -LiteralPath $gitDirectory -PathType Container)-or(Test-Path -LiteralPath $heldGitDirectory)){throw 'NON_GIT_FIXTURE_BOUNDARY'}
  Move-Item -LiteralPath $gitDirectory -Destination $heldGitDirectory
  $originalPath=$env:Path;$env:Path=''
  try{
    $nonGitRead=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $nonGitRead.expectedTaskIdentity=Get-Identity $taskPath;$nonGitRead.observedActor='successor-fixture';$nonGitRead.recoveryState='CURRENT';$nonGitRead.evaluationOnly=$false
    Write-Json $discoverPath $nonGitRead;$nonGitReadRun=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $nonGitReadRun 'nonGitReadRun'
    Assert-True ($nonGitReadRun.Code-eq0-and[string]$nonGitReadRun.Value.compactReceipt.binding.repositoryGitTop-ceq'NOT_APPLICABLE') 'ordinary-read-only-governance-without-git-repository'
    $nonGitPackage=$successorPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$nonGitPackage.schemaVersion=2;$nonGitPackage|Add-Member -NotePropertyName repositoryId -NotePropertyValue 'CONTROL';$nonGitPackage.invalidatesOn=@($nonGitPackage.invalidatesOn)+@('REPOSITORY_CHANGE')
    $nonGitPackagePath=Join-Path $control 'non-git-control-package.json';Write-Json $nonGitPackagePath $nonGitPackage
    $nonGitWrite=$successorDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$nonGitWrite.authorizationPackagePath=$nonGitPackagePath;$nonGitWrite.expectedAuthorizationIdentity=Get-Identity $nonGitPackagePath;$nonGitWrite.recoveryState='CURRENT'
    Write-Json $discoverPath $nonGitWrite;$nonGitWriteRun=Invoke-Resolver $resolver $discoverPath
    if($nonGitWriteRun.Code-ne0){Write-Output ('DIAG|ordinary-authorized-control-write-without-git|'+$nonGitWriteRun.Text)}
    Assert-True ($nonGitWriteRun.Code-eq0-and[string]$nonGitWriteRun.Value.compactReceipt.binding.repositoryGitTop-ceq'NOT_APPLICABLE') 'ordinary-authorized-control-write-without-git-repository'
  }finally{
    $env:Path=$originalPath
    Move-Item -LiteralPath $heldGitDirectory -Destination $gitDirectory
  }
}finally{
  $docsLink=Join-Path $temp 'docs';$remainingDocsLink=Get-Item -LiteralPath $docsLink -Force -ErrorAction SilentlyContinue;if($null-ne$remainingDocsLink-and($remainingDocsLink.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Remove-FixtureJunction $docsLink $temp}
  if(Test-Path -LiteralPath $outsideTemp){$outsideRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$outsideResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($outsideTemp));if(-not$outsideResolved.StartsWith($outsideRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($outsideResolved)-cnotmatch'^aiw-process-v2-outside-[a-f0-9]{32}$'){throw 'OUTSIDE_TEMP_CLEANUP_BOUNDARY'};Remove-Item -LiteralPath $outsideResolved -Recurse -Force -ErrorAction SilentlyContinue}
  if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$tempResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));$tempPrefix=$tempRoot+[IO.Path]::DirectorySeparatorChar;$tempLeaf=[IO.Path]::GetFileName($tempResolved);if(-not$tempResolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)-or$tempLeaf-cnotmatch'^aiw-process-v2-[a-f0-9]{32}$'){throw 'TEMP_CLEANUP_BOUNDARY'};Get-ChildItem -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue}
}
Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=process-runtime-v2')
