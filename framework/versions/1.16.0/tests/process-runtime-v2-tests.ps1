[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Invoke-Resolver([string]$Resolver,[string]$InputPath){$output=@(& $Resolver -InputPath $InputPath -AsJson 2>&1|ForEach-Object{[string]$_});return [pscustomobject]@{Code=$LASTEXITCODE;Text=($output-join"`n");Value=$(try{$output[-1]|ConvertFrom-Json -Depth 100}catch{$null})}}
function Write-Json([string]$Path,$Value){Write-Utf8 $Path ($Value|ConvertTo-Json -Depth 100)}
function Get-ReleaseFacts([string]$Root,[string]$ManifestPath){[string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|Where-Object{$_.FullName-cne$ManifestPath}|ForEach-Object{$_.FullName.Substring($Root.Length+1).Replace('\','/')});[Array]::Sort($paths,[StringComparer]::Ordinal);$rows=@();[int64]$total=0;foreach($relative in $paths){$full=Join-Path $Root $relative;$identity=(Get-Identity $full).Split('|');$total+=[int64]$identity[0];$rows+=($relative+'|'+$identity[0]+'|'+$identity[1])};$bytes=$utf8.GetBytes(($rows-join"`n"));return [pscustomobject]@{FileCount=$paths.Count;TotalBytes=$total;Canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}}

$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$sourceFrameworkRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $versionRoot '..\..\..')))
$resolver=Join-Path $versionRoot 'scripts\resolve-process-requirements.ps1'
$module=Join-Path $versionRoot 'scripts\ProcessRequirementComposition.psm1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-process-v2-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item -ItemType Directory -Path $temp -Force|Out-Null
  & git -C $temp init -q
  $frameworkRoot=Join-Path $temp 'framework-root';$fixtureVersion=Join-Path $frameworkRoot 'framework\versions\1.16.0';New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureVersion) -Force|Out-Null;Copy-Item -LiteralPath $versionRoot -Destination $fixtureVersion -Recurse
  $fixtureVersionObject=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $fixtureVersion 'VERSION.json')|ConvertFrom-Json;$fixtureVersionObject.lifecycle='STABLE';$fixtureVersionObject.consumable=$true;$fixtureVersionObject.projectPinEligible=$true;Write-Json (Join-Path $fixtureVersion 'VERSION.json') $fixtureVersionObject
  $fixtureManifestPath=Join-Path $fixtureVersion 'RELEASE_MANIFEST.json';$facts=Get-ReleaseFacts $fixtureVersion $fixtureManifestPath;$fixtureManifest=Get-Content -Raw -Encoding utf8 -LiteralPath $fixtureManifestPath|ConvertFrom-Json;$fixtureManifest.lifecycle='STABLE';$fixtureManifest.sourceReview='APPROVED';$fixtureManifest.fileCount=$facts.FileCount;$fixtureManifest.totalBytes=$facts.TotalBytes;$fixtureManifest.canonical=$facts.Canonical;Write-Json $fixtureManifestPath $fixtureManifest
  $control=Join-Path $temp '.ai-workspace';New-Item -ItemType Directory -Path (Join-Path $control 'tasks\active') -Force|Out-Null
  Write-Json (Join-Path $control 'project.json') ([ordered]@{schemaVersion=4;id='process-v2-fixture';displayName='Process V2 Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
  Write-Json (Join-Path $control 'controller.json') ([ordered]@{schemaVersion=1;projectId='process-v2-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
  Write-Json (Join-Path $control 'corrections.json') ([ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='process-v2-fixture';corrections=@()})
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nNo permanent project process rule is active in this legacy region. Structured rules belong to ``.ai-workspace/process-policy.json``.`n<!-- PROJECT-CUSTOM:END -->"
  $taskPath=Join-Path $control 'tasks\active\PROCESS-V2-001.md'
  Write-Utf8 $taskPath "# PROCESS-V2-001 — runtime contract fixture`n`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=DOMAIN_OWNER; phase=PLAN`n- Range summary: profile=STANDARD; risk=MEDIUM; size=SMALL; uncertainty=LOW`n"
  Write-Utf8 (Join-Path $temp 'docs\base.md') "Base project rule dependency."
  Write-Utf8 (Join-Path $temp 'docs\standard.md') "Intro.`n<!-- RULE:BEGIN -->`nSelected project standard rule body.`n<!-- RULE:END -->`nTail."
  $sourcePolicy=[ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='process-v2-fixture';selectedRulePackBytes=98304;rules=@([ordered]@{ruleId='SOURCE_BOUND_STANDARD';requirementReason='Use the current project standard';selectors=[ordered]@{profiles=@('STANDARD');roles=@('DOMAIN_OWNER');phases=@('PLAN');actionKinds=@('NONE');resultKinds=@('PLAN');pathPrefixes=@();capabilities=@();semanticTerms=@('source-bound')};preparationRequirements=@('PROJECT_STANDARD_READ');resultRequirements=@('PROJECT_STANDARD_APPLIED');decisionLocator='project:fixture';source=[ordered]@{rootSourceId='STANDARD';documents=@([ordered]@{sourceId='BASE';locator='docs/base.md';identity=Get-Identity (Join-Path $temp 'docs\base.md');mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()},[ordered]@{sourceId='STANDARD';locator='docs/standard.md';identity=Get-Identity (Join-Path $temp 'docs\standard.md');mode='MARKED_SECTION';sectionStart='<!-- RULE:BEGIN -->';sectionEnd='<!-- RULE:END -->';dependencies=@('BASE')})}})}
  $policyPath=Join-Path $control 'process-policy.json';Write-Json $policyPath $sourcePolicy
  $baseIntent=[ordered]@{schemaVersion=1;objective='Plan source-bound project work';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('source-bound');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
  $discover=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$baseIntent;evaluationOnly=$true}
  $discoverPath=Join-Path $temp 'discover.json';Write-Json $discoverPath $discover;$run=Invoke-Resolver $resolver $discoverPath
  $selected=@($run.Value.selectedRuleBlocks|Where-Object{[string]$_.requirementId-ceq'project:process-v2-fixture:SOURCE_BOUND_STANDARD'})
  Assert-True ($run.Code-eq0-and[int]$run.Value.compactReceipt.schemaVersion-eq2-and$selected.Count-eq1-and[string]$selected[0].fullText-clike'*Base project rule dependency*Selected project standard rule body*') 'source-bound-project-standard-loads-selected-section-and-dependency'
  $receiptPath=Join-Path $temp 'receipt.json';Write-Json $receiptPath $run.Value.compactReceipt
  $prep=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique)
  $results=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
  $boundary=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;preparationReceipts=$prep;resultReceipts=$results;deliveryReceipts=@('DELIVERED');publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  $boundaryPath=Join-Path $temp 'finalize.json';Write-Json $boundaryPath $boundary;$boundaryRun=Invoke-Resolver $resolver $boundaryPath
  if($boundaryRun.Code-ne0){Write-Output ('DIAG|compact-boundary|'+$boundaryRun.Text)}
  Assert-True ($boundaryRun.Code-eq0-and[string]$boundaryRun.Value.status-ceq'PASS') 'compact-boundary-input-reuses-receipt-bound-intent-and-authority'

  Write-Utf8 (Join-Path $temp 'docs\standard.md') "Changed intro without the old section markers."
  Write-Json $discoverPath $discover;$driftRun=Invoke-Resolver $resolver $discoverPath
  $driftRule=@($driftRun.Value.selectedRuleBlocks|Where-Object{[string]$_.requirementId-ceq'project:process-v2-fixture:SOURCE_BOUND_STANDARD'})
  Assert-True ($driftRun.Code-eq0-and$driftRule.Count-eq1-and[string]$driftRule[0].semanticApplicability-ceq'SOURCE_DRIFT_CONSERVATIVE_LOAD'-and@($driftRun.Value.compactReceipt.evidence.ceilings)-contains'PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD'-and[string]$driftRule[0].fullText-clike'*Changed intro*') 'source-drift-invalidates-selector-and-conservatively-loads-current-full-source'

  $sourcePolicy.rules[0].source.documents[0].dependencies=@('STANDARD');Write-Json $policyPath $sourcePolicy
  $discover.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');Write-Json $discoverPath $discover;$cycleRun=Invoke-Resolver $resolver $discoverPath
  Assert-True ($cycleRun.Code-ne0-and$cycleRun.Text.Contains('DEPENDENCY_CYCLE')) 'project-standard-source-cycle-fails-closed'

  Write-Utf8 (Join-Path $temp 'docs\standard.md') "Intro.`n<!-- RULE:BEGIN -->`nSelected project standard rule body.`n<!-- RULE:END -->`nTail."
  $sourcePolicy.rules[0].source.documents[0].dependencies=@()
  $sourcePolicy.rules[0].source.documents[1].identity=Get-Identity (Join-Path $temp 'docs\standard.md')
  $unavailableRule=[ordered]@{ruleId='UNAVAILABLE_ONLY_WHEN_APPLICABLE';requirementReason='Do not load an unavailable unrelated standard';selectors=[ordered]@{profiles=@('STANDARD');roles=@('DOMAIN_OWNER');phases=@('PLAN');actionKinds=@('SOURCE_WRITE');resultKinds=@('IMPLEMENTATION_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@('unavailable-related')};preparationRequirements=@('UNAVAILABLE_STANDARD_READ');resultRequirements=@('UNAVAILABLE_STANDARD_APPLIED');decisionLocator='project:fixture-unavailable';source=[ordered]@{rootSourceId='MISSING';documents=@([ordered]@{sourceId='MISSING';locator='docs/missing.md';identity=('1|'+('A'*64));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}}
  $sourcePolicy.rules=@($sourcePolicy.rules[0],$unavailableRule);Write-Json $policyPath $sourcePolicy
  Import-Module $module -Force
  $standardArgs=@{ProjectRoot=$temp;FrameworkRoot=$frameworkRoot;TargetVersion='1.16.0';ExpectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');ExpectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');Profile='STANDARD';Role='DOMAIN_OWNER';Phase='PLAN';Actor='owner-fixture';TaskIdentity=Get-Identity $taskPath;Capabilities=@();Objective='Plan source-bound project work';ActionKind='NONE';ResultKind='PLAN';ExactPaths=@();EvaluationOnly=$true}
  $unrelatedComposition=Invoke-ProcessRequirementComposition @standardArgs
  Assert-True (@($unrelatedComposition.selectedRequirements|Where-Object{[string]$_.requirementId-ceq'project:process-v2-fixture:UNAVAILABLE_ONLY_WHEN_APPLICABLE'}).Count-eq0) 'unavailable-unrelated-project-standard-does-not-block-or-load'
  $standardArgs.Objective='Implement unavailable-related project work';$standardArgs.ActionKind='SOURCE_WRITE';$standardArgs.ResultKind='IMPLEMENTATION_RESULT'
  $relatedFailure=$null;try{$null=Invoke-ProcessRequirementComposition @standardArgs}catch{$relatedFailure=[string]$_.Exception.Message}
  Assert-True ($relatedFailure-clike'PROJECT_STANDARD_SOURCE_UNAVAILABLE|UNAVAILABLE_ONLY_WHEN_APPLICABLE|*SOURCE_FILE_MISSING') 'unavailable-related-project-standard-blocks-dependent-action'

  Write-Utf8 (Join-Path $temp 'docs\standard.md') "<!-- RULE:BEGIN -->`nFirst.`n<!-- RULE:END -->`n<!-- RULE:BEGIN -->`nSecond.`n<!-- RULE:END -->"
  $sourcePolicy.rules=@($sourcePolicy.rules[0]);$sourcePolicy.rules[0].source.documents[1].identity=Get-Identity (Join-Path $temp 'docs\standard.md');Write-Json $policyPath $sourcePolicy
  $standardArgs.Objective='Plan source-bound project work';$standardArgs.ActionKind='NONE';$standardArgs.ResultKind='PLAN'
  $sectionFailure=$null;try{$null=Invoke-ProcessRequirementComposition @standardArgs}catch{$sectionFailure=[string]$_.Exception.Message}
  Assert-True ($sectionFailure-clike'PROJECT_STANDARD_SOURCE_UNAVAILABLE|SOURCE_BOUND_STANDARD|*SECTION_CARDINALITY') 'selected-project-standard-rejects-duplicate-section-markers'

  $sourcePolicy.rules=@();Write-Json $policyPath $sourcePolicy
  $readOnlyIntent=[ordered]@{schemaVersion=1;objective='Explain the current project process without performing an action';requestedActionKind='NONE';requestedResultKind='USER_RESPONSE';semanticHints=@('project process');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
  $taskless=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=[ordered]@{sessionId='session-fixture';requestId='request-fixture';role='DOMAIN_OWNER';phase='PLAN';profile='STANDARD'};projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity='NOT_APPLICABLE';observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('src/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$readOnlyIntent;evaluationOnly=$true}
  Write-Json $discoverPath $taskless;$tasklessRun=Invoke-Resolver $resolver $discoverPath
  if($tasklessRun.Code-ne0){Write-Output ('DIAG|taskless|'+$tasklessRun.Text)}
  Assert-True ($tasklessRun.Code-eq0-and[string]$tasklessRun.Value.compactReceipt.binding.contextType-ceq'PROJECT_READ_ONLY'-and[string]$tasklessRun.Value.compactReceipt.binding.taskIdentity-ceq'NOT_APPLICABLE'-and[string]$tasklessRun.Value.compactReceipt.binding.authorizationIdentity-ceq'NOT_REQUIRED') 'taskless-project-read-only-context-does-not-invent-task-or-authority'
  $taskless.intentEnvelope.requestedActionKind='SOURCE_WRITE';$taskless.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';Write-Json $discoverPath $taskless;$tasklessDenied=Invoke-Resolver $resolver $discoverPath
  Assert-True ($tasklessDenied.Code-ne0-and$tasklessDenied.Text.Contains('PROJECT_READ_ONLY_BOUNDARY')) 'taskless-context-cannot-admit-governed-action'

  $taskless=$null
  Write-Utf8 $taskPath "# PROCESS-V2-001 — runtime contract fixture`n`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=DOMAIN_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; risk=MEDIUM; size=SMALL; uncertainty=LOW`n"
  Write-Utf8 (Join-Path $temp 'src\file.txt') 'old'
  $package=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';taskId='PROCESS-V2-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='DOMAIN_OWNER';grantee='executor-fixture';bundle='PLAN_LOCAL';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@('SOURCE_WRITE');exactPaths=@('src/file.txt');objectIdentities=@([ordered]@{path='src/file.txt';identity=Get-Identity (Join-Path $temp 'src\file.txt')});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=Get-Identity (Join-Path $control 'project.json')}
  $packagePath=Join-Path $control 'runtime-package.json';Write-Json $packagePath $package
  $actorIntent=[ordered]@{schemaVersion=1;objective='Implement the assigned source change';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('implementation');pathHints=@('src/file.txt');capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'}
  $actorDiscover=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='executor-fixture';capabilities=@();exactPaths=@('src/file.txt');forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=Get-Identity $packagePath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$actorIntent;evaluationOnly=$true}
  Write-Json $discoverPath $actorDiscover;$actorRun=Invoke-Resolver $resolver $discoverPath
  if($actorRun.Code-ne0){Write-Output ('DIAG|temporary-actor|'+$actorRun.Text)}
  Assert-True ($actorRun.Code-eq0-and[string]$actorRun.Value.compactReceipt.binding.taskActor-ceq'owner-fixture'-and[string]$actorRun.Value.compactReceipt.binding.actor-ceq'executor-fixture'-and[string]$actorRun.Value.compactReceipt.binding.role-ceq'EXECUTOR'-and[string]$actorRun.Value.compactReceipt.binding.phase-ceq'IMPLEMENT') 'temporary-source-actor-uses-package-without-changing-task-owner-or-route'

  $compositionArgs=@{ProjectRoot=$temp;FrameworkRoot=$frameworkRoot;TargetVersion='1.16.0';ExpectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');ExpectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');Profile='CRITICAL';Role='FRAMEWORK_MAINTAINER';Phase='IMPLEMENT';Actor='owner-fixture';TaskIdentity=Get-Identity $taskPath;Capabilities=@();Objective='Edit the upgrade-project tool implementation';ActionKind='CONTROL_WRITE';ResultKind='IMPLEMENTATION_RESULT';ExactPaths=@('scripts/upgrade-project.ps1');EvaluationOnly=$true}
  $toolingComposition=Invoke-ProcessRequirementComposition @compositionArgs
  $toolingIds=@($toolingComposition.selectedRequirements|ForEach-Object{[string]$_.requirementId})
  $compositionArgs.Objective='Upgrade the project pin and managed control projection';$compositionArgs.ExactPaths=@('.ai-workspace/project.json');$adoptionComposition=Invoke-ProcessRequirementComposition @compositionArgs;$adoptionIds=@($adoptionComposition.selectedRequirements|ForEach-Object{[string]$_.requirementId})
  Assert-True ('framework:PR_PROJECT_UPGRADE_ACTOR_BOUND'-cnotin$toolingIds-and'framework:PR_PROJECT_UPGRADE_ACTOR_BOUND'-cin$adoptionIds) 'project-upgrade-rule-is-bound-to-project-control-path-not-tool-source-edit'
}finally{
  if(Test-Path -LiteralPath $temp){Get-ChildItem -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=process-runtime-v2')
