[CmdletBinding()]
param([string]$LegacyResolverPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Write-Json([string]$Path,$Value){Write-Utf8 $Path ($Value|ConvertTo-Json -Depth 100)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Invoke-Resolver([string]$Resolver,[string]$InputPath){$global:LASTEXITCODE=0;$output=@(& $Resolver -InputPath $InputPath -AsJson 2>&1|ForEach-Object{[string]$_});$code=$global:LASTEXITCODE;return [pscustomobject]@{Code=$code;Text=($output-join"`n");Value=$(try{$output[-1]|ConvertFrom-Json -Depth 100}catch{$null})}}
function Get-ReleaseFacts([string]$Root,[string]$ManifestPath){[string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|Where-Object{$_.FullName-cne$ManifestPath}|ForEach-Object{$_.FullName.Substring($Root.Length+1).Replace('\','/')});[Array]::Sort($paths,[StringComparer]::Ordinal);$rows=@();[int64]$total=0;foreach($relative in $paths){$identity=(Get-Identity (Join-Path $Root $relative)).Split('|');$total+=[int64]$identity[0];$rows+=($relative+'|'+$identity[0]+'|'+$identity[1])};return [pscustomobject]@{FileCount=$paths.Count;TotalBytes=$total;Canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n"))))}}
function New-Correction([string]$Id,[string]$Rule,[string[]]$Actions,[string[]]$Results){return [ordered]@{correctionId=$Id;introducedAgainstFramework='1.16.0';requirementReason=('Fixture reason for '+$Id);effectiveRule=$Rule;applicability='Fixture-only source transition validation.';decisionLocator='fixture:source-postimage';selectors=[ordered]@{profiles=@('STANDARD');roles=@('EXECUTOR');phases=@('IMPLEMENT');actionKinds=@($Actions);resultKinds=@('IMPLEMENTATION_RESULT');pathPrefixes=@('.ai-workspace/corrections.json');capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@($Results);requiredFacts=@();mechanicalCheckRefs=@()}}

$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$sourceFrameworkRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $versionRoot '..\..\..')))
$resolver=Join-Path $versionRoot 'scripts\resolve-process-requirements.ps1'
$module=Join-Path $versionRoot 'scripts\ProcessRequirementComposition.psm1'
Import-Module $module -Force
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-source-postimage-'+[guid]::NewGuid().ToString('N'))
try{
  $frameworkRoot=Join-Path $temp 'framework-root';$fixtureVersion=Join-Path $frameworkRoot 'framework\versions\1.16.0';New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureVersion) -Force|Out-Null;Copy-Item -LiteralPath $versionRoot -Destination $fixtureVersion -Recurse
  $version=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $fixtureVersion 'VERSION.json')|ConvertFrom-Json;$version.lifecycle='STABLE';$version.consumable=$true;$version.projectPinEligible=$true;Write-Json (Join-Path $fixtureVersion 'VERSION.json') $version
  $manifestPath=Join-Path $fixtureVersion 'RELEASE_MANIFEST.json';$facts=Get-ReleaseFacts $fixtureVersion $manifestPath;$manifest=Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath|ConvertFrom-Json;$manifest.lifecycle='STABLE';$manifest.sourceReview='APPROVED';$manifest.fileCount=$facts.FileCount;$manifest.totalBytes=$facts.TotalBytes;$manifest.canonical=$facts.Canonical;Write-Json $manifestPath $manifest

  $project=Join-Path $temp 'project';New-Item -ItemType Directory -Path $project -Force|Out-Null;& git -C $project init -q
  $control=Join-Path $project '.ai-workspace';New-Item -ItemType Directory -Path (Join-Path $control 'tasks\active') -Force|Out-Null;New-Item -ItemType Directory -Path (Join-Path $control 'knowledge') -Force|Out-Null
  $projectPath=Join-Path $control 'project.json';$controllerPath=Join-Path $control 'controller.json';$correctionsPath=Join-Path $control 'corrections.json';$policyPath=Join-Path $control 'process-policy.json';$taskPath=Join-Path $control 'tasks\active\SOURCE-POSTIMAGE-001.md';$statusPath=Join-Path $control 'STATUS.md';$indexPath=Join-Path $control 'knowledge\index.json'
  Write-Json $projectPath ([ordered]@{schemaVersion=4;id='source-postimage-fixture';displayName='Source Postimage Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
  Write-Json $controllerPath ([ordered]@{schemaVersion=1;projectId='source-postimage-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nNo permanent project process rule is active in this legacy region. Structured rules belong to ``.ai-workspace/process-policy.json``.`n<!-- PROJECT-CUSTOM:END -->"
  Write-Utf8 $taskPath "# SOURCE-POSTIMAGE-001 — source postimage fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=DOMAIN_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
  Write-Utf8 $statusPath 'BASELINE'
  Write-Json $indexPath ([ordered]@{schemaVersion=1;entries=@()})
  $oldCorrection=New-Correction 'OLD_RESULT_GATE' 'The old action result must remain proven.' @('CONTROL_WRITE') @('OLD_RESULT_REQUIRED')
  $corrections=[ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='source-postimage-fixture';corrections=@($oldCorrection)};Write-Json $correctionsPath $corrections
  $policy=[ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='source-postimage-fixture';selectedRulePackBytes=98304;rules=@()};Write-Json $policyPath $policy
  $discoverPath=Join-Path $control 'source-postimage-discover.json';$receiptPath=Join-Path $control 'source-postimage-receipt.json';$boundaryPath=Join-Path $control 'source-postimage-boundary.json'

  function New-Package([string]$Name,[string[]]$Paths,[string[]]$Actions=@('CONTROL_WRITE')){
    $package=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';taskId='SOURCE-POSTIMAGE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='DOMAIN_OWNER';grantee='executor-fixture';bundle='SOURCE_POSTIMAGE_FIXTURE';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@($Actions);exactPaths=@($Paths);objectIdentities=@($Paths|ForEach-Object{[ordered]@{path=$_;identity=$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=Get-Identity $projectPath}
    $path=Join-Path $control ($Name+'-package.json');Write-Json $path $package;return $path
  }
  function Start-Action([string]$Name,[string[]]$Paths,[string]$PackagePath,[string]$Action='CONTROL_WRITE'){
    $intent=[ordered]@{schemaVersion=1;objective=('Validate '+$Name+' source postimage transition');requestedActionKind=$Action;requestedResultKind=$(if($Action-ceq'TEST_RUN'){'TEST_RESULT'}else{'IMPLEMENTATION_RESULT'});semanticHints=@('source postimage transition');pathHints=@($Paths);capabilityHints=@();mutationHints=@($(if($Action-ceq'CONTROL_WRITE'){'control'}else{'test'}));externalHints=@();ambiguityState='CLEAR'}
    $discover=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity $projectPath;expectedCorrectionsIdentity=Get-Identity $correctionsPath;expectedTaskIdentity=Get-Identity $taskPath;observedActor='executor-fixture';capabilities=@();exactPaths=@($Paths);forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$PackagePath;expectedAuthorizationIdentity=Get-Identity $PackagePath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
    Write-Json $discoverPath $discover;$run=Invoke-Resolver $resolver $discoverPath
    if($run.Code-ne0){return [pscustomobject]@{Discover=$run;Admit=$null;ReceiptPath=$null;Prep=@();Results=@()}}
    Write-Json $receiptPath $run.Value.compactReceipt;$prep=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$results=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $admit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;preparationReceipts=$prep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'};Write-Json $boundaryPath $admit;$admitRun=Invoke-Resolver $resolver $boundaryPath
    return [pscustomobject]@{Discover=$run;Admit=$admitRun;ReceiptPath=$receiptPath;Prep=$prep;Results=$results}
  }
  function Invoke-Finalize($Action,[string[]]$Results){$finalize=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$Action.ReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $Action.ReceiptPath;preparationReceipts=@($Action.Prep);resultReceipts=@($Results);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'};Write-Json $boundaryPath $finalize;return Invoke-Resolver $resolver $boundaryPath}
  function Get-Postimages([string[]]$Paths){return @($Paths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'MISSING'})})}

  $exact3=@('.ai-workspace/corrections.json','.ai-workspace/STATUS.md','.ai-workspace/knowledge/index.json');$correctionPackage=New-Package 'correction-positive' $exact3;$correctionAction=Start-Action 'correction-positive' $exact3 $correctionPackage
  Assert-True ($correctionAction.Discover.Code-eq0-and$correctionAction.Admit.Code-eq0-and'OLD_RESULT_REQUIRED'-cin@($correctionAction.Results)) 'correction-source-transition-old-authority-admits-and-binds-old-result'
  $newCorrection=$oldCorrection|ConvertTo-Json -Depth 50|ConvertFrom-Json;$newCorrection.selectors.actionKinds=@('TEST_RUN');$newCorrection.resultRequirements=@();$corrections.corrections=@($newCorrection);Write-Json $correctionsPath $corrections;Write-Utf8 $statusPath 'UPDATED';Write-Json $indexPath ([ordered]@{schemaVersion=1;entries=@([ordered]@{id='UPDATED'})})
  $postcheck=Invoke-ProcessRequirementComposition -ProjectRoot $project -FrameworkRoot $frameworkRoot -TargetVersion '1.16.0' -ExpectedProjectConfigIdentity (Get-Identity $projectPath) -ExpectedCorrectionsIdentity (Get-Identity $correctionsPath) -Profile 'STANDARD' -Role 'EXECUTOR' -Phase 'IMPLEMENT' -Actor 'executor-fixture' -TaskIdentity (Get-Identity $taskPath) -Capabilities @() -Objective 'Validate correction source postimage transition' -ActionKind 'CONTROL_WRITE' -ResultKind 'IMPLEMENTATION_RESULT' -ExactPaths $exact3 -ForbiddenPaths @('private/')
  $postimages=Get-Postimages $exact3;$withoutOld=@($correctionAction.Results|Where-Object{$_-cne'OLD_RESULT_REQUIRED'})+$postimages;$oldGateRun=Invoke-Finalize $correctionAction $withoutOld
  Assert-True ($postcheck.status-ceq'PASS'-and$oldGateRun.Code-ne0-and[string]$oldGateRun.Value.reason-ceq'RESULT_INCOMPLETE'-and'OLD_RESULT_REQUIRED'-cin@($oldGateRun.Value.missingResult)) 'correction-source-transition-preserves-old-result-obligation'
  $correctionFinalize=Invoke-Finalize $correctionAction (@($correctionAction.Results)+$postimages)
  Assert-True ($correctionFinalize.Code-eq0-and[string]$correctionFinalize.Value.sourcePostimageTransition.status-ceq'PASS'-and'correctionsIdentity'-cin@($correctionFinalize.Value.sourcePostimageTransition.changedBindings)) 'correction-status-index-postimages-finalize-through-recomposed-source'

  Write-Utf8 (Join-Path $project 'standards\rule.md') 'Current external standard rule.'
  $policyPaths=@('.ai-workspace/process-policy.json');$policyPackage=New-Package 'policy-positive' $policyPaths;$policyAction=Start-Action 'policy-positive' $policyPaths $policyPackage;Assert-True ($policyAction.Discover.Code-eq0-and$policyAction.Admit.Code-eq0) 'policy-source-transition-old-authority-admits'
  $policyRule=[ordered]@{ruleId='BOUND_STANDARD';requirementReason='Fixture source binding';selectors=[ordered]@{profiles=@('STANDARD');roles=@('EXECUTOR');phases=@('VERIFY');actionKinds=@('TEST_RUN');resultKinds=@('TEST_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:policy';source=[ordered]@{rootSourceId='STANDARD';documents=@([ordered]@{sourceId='STANDARD';locator='standards/rule.md';identity=Get-Identity (Join-Path $project 'standards\rule.md');mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}}
  $policy.rules=@($policyRule);Write-Json $policyPath $policy;$policyFinalize=Invoke-Finalize $policyAction (@($policyAction.Results)+(Get-Postimages $policyPaths))
  Assert-True ($policyFinalize.Code-eq0-and'policyIdentity'-cin@($policyFinalize.Value.sourcePostimageTransition.changedBindings)-and'projectStandardsIdentity'-cin@($policyFinalize.Value.sourcePostimageTransition.changedBindings)) 'policy-postimage-derives-and-validates-project-standard-identity'

  $statusOnly=@('.ai-workspace/STATUS.md');$externalPackage=New-Package 'external-drift' $statusOnly;$externalAction=Start-Action 'external-drift' $statusOnly $externalPackage;Write-Utf8 $statusPath 'EXTERNAL-DRIFT-CASE';Write-Utf8 (Join-Path $project 'standards\rule.md') 'Unrelated external drift.';$externalRun=Invoke-Finalize $externalAction (@($externalAction.Results)+(Get-Postimages $statusOnly))
  Assert-True ($externalRun.Code-ne0-and$externalRun.Text.Contains('DISCOVER_SOURCE_DRIFT|projectStandardsIdentity')) 'external-standard-independent-drift-remains-rejected'
  Write-Utf8 (Join-Path $project 'standards\rule.md') 'Current external standard rule.'

  $correctionPaths=@('.ai-workspace/corrections.json');$postimagePackage=New-Package 'postimage-negative' $correctionPaths;$postimageAction=Start-Action 'postimage-negative' $correctionPaths $postimagePackage;$secondCorrection=New-Correction 'SECOND_RULE' 'A second valid correction body.' @('TEST_RUN') @();$corrections.corrections=@($newCorrection,$secondCorrection);Write-Json $correctionsPath $corrections;$actualPost=Get-Postimages $correctionPaths
  $omittedRun=Invoke-Finalize $postimageAction @($postimageAction.Results);$wrongRun=Invoke-Finalize $postimageAction (@($postimageAction.Results)+@('OBJECT_POSTIMAGE|.ai-workspace/corrections.json|0|'+('0'*64)));$duplicateRun=Invoke-Finalize $postimageAction (@($postimageAction.Results)+$actualPost+$actualPost)
  Assert-True ($omittedRun.Code-ne0-and$wrongRun.Code-ne0-and$duplicateRun.Code-ne0-and$omittedRun.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED')-and$wrongRun.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED')-and($duplicateRun.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED')-or$duplicateRun.Text.Contains('INPUT_ARRAY_ITEM|resultReceipts'))) 'source-transition-omitted-wrong-and-duplicate-postimages-rejected'
  $postimageFinalize=Invoke-Finalize $postimageAction (@($postimageAction.Results)+$actualPost);Assert-True ($postimageFinalize.Code-eq0) 'source-transition-unique-real-postimage-accepted'

  $packageDriftPackage=New-Package 'package-drift' $policyPaths;$packageDriftAction=Start-Action 'package-drift' $policyPaths $packageDriftPackage;$policy.selectedRulePackBytes=90000;Write-Json $policyPath $policy;$packageRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $packageDriftPackage;Write-Utf8 $packageDriftPackage ($packageRaw.TrimEnd("`n")+' ');$packageDriftRun=Invoke-Finalize $packageDriftAction (@($packageDriftAction.Results)+(Get-Postimages $policyPaths))
  Assert-True ($packageDriftRun.Code-ne0-and$packageDriftRun.Text.Contains('DISCOVER_SOURCE_DRIFT|authorizationIdentity')) 'source-transition-package-drift-rejected'
  Write-Utf8 $packageDriftPackage $packageRaw;$packageDriftFinalize=Invoke-Finalize $packageDriftAction (@($packageDriftAction.Results)+(Get-Postimages $policyPaths));Assert-True ($packageDriftFinalize.Code-eq0) 'source-transition-restored-package-finalizes'

  $unauthorizedPackage=New-Package 'unauthorized-source' $statusOnly;$unauthorizedAction=Start-Action 'unauthorized-source' $statusOnly $unauthorizedPackage;$correctionsBeforeUnauthorized=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionsPath;Write-Utf8 $statusPath 'UNAUTHORIZED-SOURCE';$thirdCorrection=New-Correction 'THIRD_RULE' 'A third valid correction body.' @('TEST_RUN') @();$corrections.corrections=@($newCorrection,$secondCorrection,$thirdCorrection);Write-Json $correctionsPath $corrections;$unauthorizedRun=Invoke-Finalize $unauthorizedAction (@($unauthorizedAction.Results)+(Get-Postimages $statusOnly))
  Assert-True ($unauthorizedRun.Code-ne0-and$unauthorizedRun.Text.Contains('SOURCE_POSTIMAGE_PATH_NOT_AUTHORIZED|correctionsIdentity')) 'source-change-outside-current-action-scope-rejected'
  Write-Utf8 $correctionsPath $correctionsBeforeUnauthorized;$corrections=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionsPath|ConvertFrom-Json

  $controllerPackage=New-Package 'controller-drift' $correctionPaths;$controllerAction=Start-Action 'controller-drift' $correctionPaths $controllerPackage;$corrections.corrections=@($newCorrection);Write-Json $correctionsPath $corrections;$controllerBefore=Get-Content -Raw -Encoding utf8 -LiteralPath $controllerPath;$controller=Get-Content -Raw -Encoding utf8 -LiteralPath $controllerPath|ConvertFrom-Json;$controller.controllerEpoch=2;Write-Json $controllerPath $controller;$controllerRun=Invoke-Finalize $controllerAction (@($controllerAction.Results)+(Get-Postimages $correctionPaths))
  Assert-True ($controllerRun.Code-ne0-and$controllerRun.Text.Contains('DISCOVER_SOURCE_DRIFT|controllerIdentity')) 'source-transition-does-not-mask-controller-drift'
  Write-Utf8 $controllerPath $controllerBefore

  $conflictPackage=New-Package 'invalid-correction' $correctionPaths;$conflictAction=Start-Action 'invalid-correction' $correctionPaths $conflictPackage;$validCorrectionsRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionsPath;$duplicateCorrection=New-Correction 'DUPLICATE_RULE' ([string]$newCorrection.effectiveRule) @('TEST_RUN') @();$corrections.corrections=@($newCorrection,$duplicateCorrection);Write-Json $correctionsPath $corrections;$conflictRun=Invoke-Finalize $conflictAction (@($conflictAction.Results)+(Get-Postimages $correctionPaths))
  Assert-True ($conflictRun.Code-ne0-and$conflictRun.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'invalid-new-correction-conflict-rejected'
  Write-Utf8 $correctionsPath $validCorrectionsRaw;$corrections=Get-Content -Raw -Encoding utf8 -LiteralPath $correctionsPath|ConvertFrom-Json

  $invalidPolicyPackage=New-Package 'invalid-policy-source' $policyPaths;$invalidPolicyAction=Start-Action 'invalid-policy-source' $policyPaths $invalidPolicyPackage;$validPolicyRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $policyPath;$invalidPolicy=$policy|ConvertTo-Json -Depth 100|ConvertFrom-Json;$invalidPolicy.rules[0].source.documents[0].identity='1|'+('A'*64);Write-Json $policyPath $invalidPolicy;$invalidPolicyRun=Invoke-Finalize $invalidPolicyAction (@($invalidPolicyAction.Results)+(Get-Postimages $policyPaths))
  Assert-True ($invalidPolicyRun.Code-ne0-and$invalidPolicyRun.Text.Contains('SOURCE_POSTIMAGE_PROJECT_STANDARD_DRIFT')) 'invalid-new-policy-source-binding-rejected'
  Write-Utf8 $policyPath $validPolicyRaw;$policy=Get-Content -Raw -Encoding utf8 -LiteralPath $policyPath|ConvertFrom-Json

  $budgetPackage=New-Package 'invalid-policy-budget' $policyPaths;$budgetAction=Start-Action 'invalid-policy-budget' $policyPaths $budgetPackage;$policy.selectedRulePackBytes=1;Write-Json $policyPath $policy;$budgetRun=Invoke-Finalize $budgetAction (@($budgetAction.Results)+(Get-Postimages $policyPaths))
  Assert-True ($budgetRun.Code-ne0-and$budgetRun.Text.Contains('SOURCE_POSTIMAGE_SELECTED_RULE_PACK_BUDGET_EXCEEDED')) 'invalid-new-policy-budget-rejected'
  $policy.selectedRulePackBytes=90000;Write-Json $policyPath $policy

  $policy.rules=@();Write-Json $policyPath $policy
  $bootstrapPath=Join-Path $control 'BOOTSTRAP.md'
  $bootstrapBefore=Get-Content -LiteralPath $bootstrapPath -Raw
  Write-Utf8 $bootstrapPath ('Managed entry'+[char]10+'<!-- PROJECT-CUSTOM:BEGIN -->'+[char]10+'Preserve project review evidence.'+[char]10+'<!-- PROJECT-CUSTOM:END -->')
  $customBefore=[IO.File]::ReadAllBytes($bootstrapPath);$policyBefore=[IO.File]::ReadAllBytes($policyPath)
  $customScopePackage=New-Package 'policy-only-custom-drift' $policyPaths
  $customScopeAction=Start-Action 'policy-only-custom-drift' $policyPaths $customScopePackage
  $customReceipt=Get-Content -LiteralPath $customScopeAction.ReceiptPath -Raw|ConvertFrom-Json
  Assert-True ($customScopeAction.Discover.Code-eq0-and$customScopeAction.Admit.Code-eq0-and$null-ne$customReceipt.sourceBindings.PSObject.Properties['bootstrapManagedIdentity']-and'.ai-workspace/BOOTSTRAP.md'-cnotin@($customReceipt.binding.exactScope)) 'R1-policy-only-real-admission-has-new-managed-binding'
  $policy.selectedRulePackBytes=89000;Write-Json $policyPath $policy
  Write-Utf8 $bootstrapPath ('Managed entry'+[char]10+'<!-- PROJECT-CUSTOM:BEGIN -->'+[char]10+'Preserve changed project review evidence.'+[char]10+'<!-- PROJECT-CUSTOM:END -->')
  $customDriftIdentity=Get-Identity $bootstrapPath;$policyDriftIdentity=Get-Identity $policyPath
  $customScopeFinal=Invoke-Finalize $customScopeAction (@($customScopeAction.Results)+(Get-Postimages $policyPaths))
  Assert-True ($customScopeFinal.Code-ne0-and$customScopeFinal.Text.Contains('SOURCE_POSTIMAGE_PATH_NOT_AUTHORIZED|projectCustomIdentity')-and(Get-Identity $bootstrapPath)-ceq$customDriftIdentity-and(Get-Identity $policyPath)-ceq$policyDriftIdentity) 'R1-package-external-custom-drift-rejected-without-live-mutation'
  [IO.File]::WriteAllBytes($bootstrapPath,$customBefore);[IO.File]::WriteAllBytes($policyPath,$policyBefore)
  $policy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json
  $migrationPaths=@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json')
  $migrationPackage=New-Package 'bootstrap-policy-migration' $migrationPaths
  $migrationAction=Start-Action 'bootstrap-policy-migration' $migrationPaths $migrationPackage
  Assert-True ($migrationAction.Discover.Code-eq0-and$migrationAction.Admit.Code-eq0) ('bootstrap-policy-original-action-admitted|'+$(if($migrationAction.Discover.Code-ne0){$migrationAction.Discover.Text}else{$migrationAction.Admit.Text}))
  $migratedBootstrap='Managed entry'+[char]10+'<!-- PROJECT-CUSTOM:BEGIN -->'+[char]10+'<!-- PROJECT-CUSTOM:END -->'
  Write-Utf8 $bootstrapPath $migratedBootstrap
  $migratedRule=[ordered]@{ruleId='PERMANENT_REVIEW_EVIDENCE';requirementReason='Preserve the former Bootstrap rule';effectiveRule='Preserve project review evidence.';selectors=[ordered]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:explicit-rule-migration'}
  $policy.rules=@($policy.rules)+@($migratedRule);Write-Json $policyPath $policy
  $migrationFinal=Invoke-Finalize $migrationAction (@($migrationAction.Results)+(Get-Postimages $migrationPaths))
  Assert-True ($migrationFinal.Code-eq0-and'projectCustomIdentity'-cin@($migrationFinal.Value.sourcePostimageTransition.changedBindings)) 'bootstrap-to-policy-original-finalize-succeeds'
  # Reusing the original admission must not mask a third-party managed-region edit.
  Write-Utf8 $bootstrapPath ('Changed managed entry'+[char]10+$migratedBootstrap)
  $managedDrift=Invoke-Finalize $migrationAction (@($migrationAction.Results)+(Get-Postimages $migrationPaths))
  Assert-True ($managedDrift.Code-ne0-and$managedDrift.Text.Contains('bootstrapManagedIdentity')) 'bootstrap-managed-third-party-drift-rejected'
  Write-Utf8 $bootstrapPath $migratedBootstrap

  # Recover an already-admitted action after one live source write, with no
  # historical transaction record. The recovery record is created now.
  $recoveryRuntime=Join-Path $control 'runtime/SOURCE-POSTIMAGE-001/executor-fixture/recovery-material'
  New-Item -ItemType Directory -Path $recoveryRuntime -Force|Out-Null
  $policy.rules=@();Write-Json $policyPath $policy
  $recoveryBootstrap='Managed entry'+[char]10+'<!-- PROJECT-CUSTOM:BEGIN -->'+[char]10+'Keep deployment evidence.'+[char]10+'<!-- PROJECT-CUSTOM:END -->'
  Write-Utf8 $bootstrapPath $recoveryBootstrap
  $oldBootstrap=Join-Path $recoveryRuntime 'bootstrap-old.md';$newBootstrap=Join-Path $recoveryRuntime 'bootstrap-new.md'
  $oldPolicy=Join-Path $recoveryRuntime 'policy-old.json';$newPolicy=Join-Path $recoveryRuntime 'policy-new.json'
  [IO.File]::Copy($bootstrapPath,$oldBootstrap);[IO.File]::Copy($policyPath,$oldPolicy)
  Write-Utf8 $newBootstrap $migratedBootstrap
  $nextPolicy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
  $nextRule=$migratedRule|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $nextRule.ruleId='DEPLOYMENT_EVIDENCE';$nextRule.effectiveRule='Keep deployment evidence.'
  $nextPolicy.rules=@($nextPolicy.rules)+@($nextRule);Write-Json $newPolicy $nextPolicy
  $currentResolver=$resolver
  if($LegacyResolverPath){$resolver=$LegacyResolverPath}
  $recoveryPackage=New-Package 'historical-rule-action' $migrationPaths
  $recoveryAction=Start-Action 'historical-rule-action' $migrationPaths $recoveryPackage
  $resolver=$currentResolver
  Assert-True ($recoveryAction.Discover.Code-eq0-and$recoveryAction.Admit.Code-eq0) 'historical-rule-action-really-admitted'
  $historicalReceipt=Join-Path $recoveryRuntime 'original-receipt.json';[IO.File]::Copy($receiptPath,$historicalReceipt)
  $historicalAdmitInput=Join-Path $recoveryRuntime 'original-admit-input.json'
  $savedAdmit=Get-Content -LiteralPath $boundaryPath -Raw|ConvertFrom-Json -Depth 100
  # The admission decision binds receipt identity, not its storage locator.
  $savedAdmit.discoverReceiptPath=$historicalReceipt;Write-Json $historicalAdmitInput $savedAdmit
  $historicalAdmitResult=Join-Path $recoveryRuntime 'original-admit-result.json';Write-Json $historicalAdmitResult $recoveryAction.Admit.Value
  $recoveryPlanPath=Join-Path $recoveryRuntime 'recovery-plan.json'
  $recoveryPlan=[ordered]@{schemaVersion=1;discoverReceiptPath=$historicalReceipt;discoverReceiptIdentity=Get-Identity $historicalReceipt;admitInputPath=$historicalAdmitInput;admitInputIdentity=Get-Identity $historicalAdmitInput;admitResultPath=$historicalAdmitResult;admitResultIdentity=Get-Identity $historicalAdmitResult;objects=@(
    [ordered]@{path='.ai-workspace/BOOTSTRAP.md';preimagePath=$oldBootstrap;preimageIdentity=Get-Identity $oldBootstrap;postimagePath=$newBootstrap;postimageIdentity=Get-Identity $newBootstrap},
    [ordered]@{path='.ai-workspace/process-policy.json';preimagePath=$oldPolicy;preimageIdentity=Get-Identity $oldPolicy;postimagePath=$newPolicy;postimageIdentity=Get-Identity $newPolicy}
  );preparationReceipts=@($recoveryAction.Prep);resultReceipts=@($recoveryAction.Results);transactionRelativePath='.ai-workspace/upgrade-recovery/project-rules/SOURCE-POSTIMAGE-001/recovery/state.json'}
  Write-Json $recoveryPlanPath $recoveryPlan
  [IO.File]::Copy($newPolicy,$policyPath,$true)
  Import-Module (Join-Path $sourceFrameworkRoot 'scripts/ProjectAdoptionTransaction.psm1') -Force
  $beforeRecoveryPolicy=Get-Identity $policyPath
  $preview=Invoke-AiwProjectRuleActionRecovery -RepositoryRoot $project -PlanPath $recoveryPlanPath -ExpectedPlanIdentity (Get-Identity $recoveryPlanPath) -ObservedActor 'executor-fixture'
  Assert-True ($preview.status-ceq'WHAT_IF'-and(Get-Identity $policyPath)-ceq$beforeRecoveryPolicy) 'authorized-mixed-state-recovery-preview-zero-write'
  $reason=''
  try{$null=Invoke-AiwProjectRuleActionRecovery -RepositoryRoot $project -PlanPath $recoveryPlanPath -ExpectedPlanIdentity (Get-Identity $recoveryPlanPath) -ObservedActor 'wrong-actor' -Apply}catch{$reason=$_.Exception.Message}
  Assert-True ($reason.Contains('RULE_RECOVERY_CONTEXT')-and(Get-Identity $policyPath)-ceq$beforeRecoveryPolicy) 'recovery-wrong-actor-rejected-before-write'
  $realAdmit=[IO.File]::ReadAllBytes($historicalAdmitResult)
  $fakeAdmit=Get-Content -LiteralPath $historicalAdmitResult -Raw|ConvertFrom-Json
  $fakeAdmit.decisionIdentity='F'*64;Write-Json $historicalAdmitResult $fakeAdmit
  $recoveryPlan.admitResultIdentity=Get-Identity $historicalAdmitResult;Write-Json $recoveryPlanPath $recoveryPlan
  $reason='';try{$null=Invoke-AiwProjectRuleActionRecovery -RepositoryRoot $project -PlanPath $recoveryPlanPath -ExpectedPlanIdentity (Get-Identity $recoveryPlanPath) -ObservedActor 'executor-fixture' -Apply}catch{$reason=$_.Exception.Message}
  Assert-True ($reason.Contains('RULE_RECOVERY_ORIGINAL_ADMISSION_DECISION')-and(Get-Identity $policyPath)-ceq$beforeRecoveryPolicy) 'recovery-rejects-forged-original-admission'
  [IO.File]::WriteAllBytes($historicalAdmitResult,$realAdmit)
  $recoveryPlan.admitResultIdentity=Get-Identity $historicalAdmitResult;Write-Json $recoveryPlanPath $recoveryPlan
  $interrupted=Invoke-AiwProjectRuleActionRecovery -RepositoryRoot $project -PlanPath $recoveryPlanPath -ExpectedPlanIdentity (Get-Identity $recoveryPlanPath) -ObservedActor 'executor-fixture' -Apply -InterruptAfterWrite 1
  Assert-True ($interrupted.status-ceq'INTERRUPTED') 'rule-recovery-interruption-has-real-new-transaction'
  $recovered=Invoke-AiwProjectRuleActionRecovery -RepositoryRoot $project -PlanPath $recoveryPlanPath -ExpectedPlanIdentity (Get-Identity $recoveryPlanPath) -ObservedActor 'executor-fixture' -Apply
  Assert-True ($recovered.status-ceq'COMPLETED'-and$recovered.originalActionFinalized-and(Get-Identity $policyPath)-ceq(Get-Identity $newPolicy)) 'authorized-mixed-state-original-action-finalized'
  $savedPolicyBytes=[IO.File]::ReadAllBytes($policyPath);Write-Utf8 $policyPath 'unknown third-party data'
  $thirdPartyReason=''
  try{Invoke-AiwProjectRuleActionRecovery -RepositoryRoot $project -PlanPath $recoveryPlanPath -ExpectedPlanIdentity (Get-Identity $recoveryPlanPath) -ObservedActor 'executor-fixture' -Apply|Out-Null}catch{$thirdPartyReason=$_.Exception.Message}
  Assert-True ($thirdPartyReason.Contains('RULE_RECOVERY_THIRD_PARTY_OBJECT')-and[IO.File]::ReadAllText($policyPath).Contains('unknown third-party data')) 'recovery-rejects-unknown-mixed-state-without-write'
  [IO.File]::WriteAllBytes($policyPath,$savedPolicyBytes)
  $gitConfig=Get-Content -LiteralPath $projectPath -Raw|ConvertFrom-Json
  $gitConfig.routineExcludedPaths=@('private/blocked.bin');Write-Json $projectPath $gitConfig
  $docRelative='notes Unicode 文档.md';$docPath=Join-Path $project $docRelative
  Write-Utf8 $docPath ('Context private/blocked.bin'+[char]10+'Old private/blocked.bin')
  & git -C $project add -- $docRelative
  & git -C $project -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'fixture'
  Write-Utf8 $docPath ('Context private/blocked.bin'+[char]10+'New private/blocked.bin')
  $safeGit=Join-Path $versionRoot 'scripts/invoke-protected-safe-git.ps1'
  $safeOutput=@(& $safeGit -ProjectRoot $project -Operation DIFF -AllowPath @($docRelative) -ExpectedProjectConfigIdentity (Get-Identity $projectPath) 2>&1)
  Assert-True ($LASTEXITCODE-eq0-and(($safeOutput-join[char]10)|ConvertFrom-Json).status-ceq'VERIFIED') 'safe-git-context-added-deleted-path-mentions-unicode-space-allowed'
  $retroPackage=New-Package 'retroactive-authority' $policyPaths @('TEST_RUN');$retroAction=Start-Action 'retroactive-authority' $policyPaths $retroPackage 'CONTROL_WRITE'
  Assert-True ($retroAction.Discover.Code-ne0-and$retroAction.Discover.Text.Contains('ACTION_NOT_GRANTED')) 'new-rules-cannot-retroactively-authorize-old-action'
}finally{
  if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$full=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));if(-not$full.StartsWith($tempRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-source-postimage-[a-f0-9]{32}$'){throw 'TEMP_CLEANUP_BOUNDARY'};Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $full -Recurse -Force}
}
Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=source-postimage-transition')
