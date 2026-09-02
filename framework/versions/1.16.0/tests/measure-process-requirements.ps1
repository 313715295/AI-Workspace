[CmdletBinding()]
param(
  [int]$Warmups = 1,
  [int]$MeasuredRuns = 5,
  [switch]$AsJson
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$fixturePath=Join-Path $PSScriptRoot 'PROCESS_REQUIREMENTS_FIXTURES.json'
$fixtureContract=Get-Content -Raw -Encoding utf8 -LiteralPath $fixturePath|ConvertFrom-Json
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-1.14-process-measure-'+[guid]::NewGuid().ToString('N'))

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
function Get-PayloadFacts([string]$Root){
  [string[]]$files=@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File|ForEach-Object{$_.FullName.Substring($Root.Length+1).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'});[Array]::Sort($files,[StringComparer]::Ordinal)
  $rows=@();[int64]$total=0;foreach($relative in $files){$identity=(Get-Identity (Join-Path $Root $relative)).Split('|');$total+=[int64]$identity[0];$rows+=($relative+'|'+$identity[0]+'|'+$identity[1])}
  $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n"))))
  return [pscustomobject]@{FileCount=$files.Count;TotalBytes=$total;Canonical=$canonical}
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

try{
  New-Item -ItemType Directory -Path $temp -Force|Out-Null
  $frameworkRoot=Join-Path $temp 'framework-workspace';$sealedRoot=Join-Path $frameworkRoot 'framework\versions\1.16.0';New-Item -ItemType Directory -Path (Split-Path -Parent $sealedRoot) -Force|Out-Null;Copy-Item -LiteralPath $versionRoot -Destination $sealedRoot -Recurse
  $versionFile=Join-Path $sealedRoot 'VERSION.json';$version=Get-Content -Raw -Encoding utf8 -LiteralPath $versionFile|ConvertFrom-Json;$version.lifecycle='STABLE';$version.consumable=$true;$version.projectPinEligible=$true;Write-Utf8 $versionFile ($version|ConvertTo-Json -Depth 20)
  $loadFile=Join-Path $sealedRoot 'LOAD_MANIFEST.json';$load=Get-Content -Raw -Encoding utf8 -LiteralPath $loadFile|ConvertFrom-Json;$load.lifecycle='STABLE';Write-Utf8 $loadFile ($load|ConvertTo-Json -Depth 30)
  $facts=Get-PayloadFacts $sealedRoot;$manifestFile=Join-Path $sealedRoot 'RELEASE_MANIFEST.json';$manifest=Get-Content -Raw -Encoding utf8 -LiteralPath $manifestFile|ConvertFrom-Json;$manifest.lifecycle='STABLE';$manifest.fileCount=$facts.FileCount;$manifest.totalBytes=$facts.TotalBytes;$manifest.canonical=$facts.Canonical;$manifest.sourceReview='APPROVED';$manifest.sourceCandidate='MEASUREMENT_FIXTURE';$manifest.releaseIntegration='MEASUREMENT_FIXTURE';Write-Utf8 $manifestFile ($manifest|ConvertTo-Json -Depth 20)
  $resolver=Join-Path $sealedRoot 'scripts\resolve-process-requirements.ps1'
  $results=@()
  foreach($fixture in @($fixtureContract.fixtures)){
    $expectedFixtureIdentity=Get-FixtureIdentity $fixture;if([string]$fixture.fixtureIdentity-cne$expectedFixtureIdentity){throw ('FIXTURE_IDENTITY_DRIFT|'+[string]$fixture.fixtureId)}
    $projectRoot=Join-Path $temp ('project-'+[string]$fixture.fixtureId);New-Item -ItemType Directory -Path (Join-Path $projectRoot '.ai-workspace\tasks\active'),(Join-Path $projectRoot 'src'),(Join-Path $projectRoot 'tests'),(Join-Path $projectRoot 'docs') -Force|Out-Null
    & git -C $projectRoot init -q;if($LASTEXITCODE-ne0){throw 'MEASUREMENT_GIT_INIT'}
    $fixtureCapabilities=[ordered]@{};if(@($fixture.capabilities)-contains'KNOWLEDGE_REFERENCE'){$fixtureCapabilities['KNOWLEDGE_REFERENCE']=[ordered]@{enabled=$true;indexLocator='.ai-workspace/knowledge/index.json'}}
    $project=[ordered]@{schemaVersion=4;id=('measure-'+[string]$fixture.fixtureId);displayName='Measurement Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=$fixtureCapabilities;processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}
    $projectPath=Join-Path $projectRoot '.ai-workspace\project.json';Write-Utf8 $projectPath ($project|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\controller.json') (([ordered]@{schemaVersion=1;projectId=$project.id;controllerId='fixture-controller';controllerEpoch=1;state='CURRENT'})|ConvertTo-Json -Depth 10)
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\corrections.json') (([ordered]@{schemaVersion=2;contractVersion='1.14.0';projectId=$project.id;corrections=@()})|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\process-policy.json') (([ordered]@{schemaVersion=1;contractVersion='1.14.0';projectId=$project.id;rules=@()})|ConvertTo-Json -Depth 20)
    Write-Utf8 (Join-Path $projectRoot '.ai-workspace\BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nNo permanent project rule.`n<!-- PROJECT-CUSTOM:END -->`n"
    foreach($relative in @($fixture.exactPaths)){Write-Utf8 (Join-Path $projectRoot $relative) ("fixture object "+$relative+"`n")}
    $taskId=('MEASURE-'+([string]$fixture.fixtureId).ToUpperInvariant().Replace('_','-'))
    $taskOwner=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'fixture-owner'}else{[string]$fixture.actor}
    $taskPath=Join-Path $projectRoot ('.ai-workspace\tasks\active\'+$taskId+'.md')
    Write-Utf8 $taskPath ("# "+$taskId+" - measurement fixture`n`n- Task schema: 1.16.0`n- Owner: "+$taskOwner+"`n- Work route: actor="+[string]$fixture.actor+"; role="+[string]$fixture.role+"; phase="+[string]$fixture.phase+"`n- Range summary: profile="+[string]$fixture.profile+"; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n")
    $authorizationPath='NOT_REQUIRED';$authorizationIdentity='NOT_REQUIRED';$userDecision='NOT_REQUIRED'
    if([string]$fixture.actionKind-cne'NONE'){
      $userDecision=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'NOT_REQUIRED'}else{'USER_MEASUREMENT_BOUNDARY_APPROVED'};$authorizationPath=Join-Path $projectRoot '.ai-workspace\measure-authorization.json'
      $objectIdentities=@($fixture.exactPaths|ForEach-Object{[ordered]@{path=[string]$_;identity=Get-Identity (Join-Path $projectRoot ([string]$_))}})
      $issuerRole=if([string]$fixture.role-ceq'CONTROLLER'){'PROJECT_CONTROLLER'}else{'DOMAIN_OWNER'}
      $issuer=if($issuerRole-ceq'PROJECT_CONTROLLER'){'fixture-controller'}else{$taskOwner}
      $decisionClass=if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'ROUTINE_LOCAL'}elseif([string]$fixture.actionKind-ceq'EXTERNAL'){'EXTERNAL_ACTION'}else{'PRODUCT_RESULT'}
      $package=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';taskId=$taskId;taskIdentity=(Get-Identity $taskPath);profile=[string]$fixture.profile;lifecycle='ACTIVE';owner=$taskOwner;issuer=$issuer;issuerRole=$issuerRole;grantee=[string]$fixture.actor;bundle='MEASUREMENT_LOCAL';decisionClass=$decisionClass;userConfirmation=$userDecision;reviewIndependence=$(if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){'INDEPENDENT'}else{'NOT_APPLICABLE'});delegatedGitCloser=$false;actions=@([string]$fixture.actionKind);exactPaths=@($fixture.exactPaths);objectIdentities=$objectIdentities;projectConfigIdentity=(Get-Identity $projectPath);invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')}
      if([string]$fixture.actionKind-ceq'REVIEW_EXECUTE'){$package.invalidatesOn+='CONTRIBUTOR_SET_CHANGE';$package.candidateWriter='fixture-writer';$package.materialContributors=@('fixture-designer')}
      if($issuerRole-ceq'PROJECT_CONTROLLER'){$package.issuerControllerId='fixture-controller';$package.issuerControllerEpoch=1;$package.controllerControlIdentity=Get-Identity (Join-Path $projectRoot '.ai-workspace\controller.json');$package.invalidatesOn+='CONTROLLER_EPOCH_CHANGE'}
      if([string]$fixture.actionKind-ceq'EXTERNAL'){
        $zeroEscalation=[ordered]@{paymentOrSubscription=$false;commercialLicensing=$false;accountOrCredentialChange=$false;publicPublication=$false;installation=$false;protectedOrSecretUpload=$false;crossDomain=$false;formalAssetActivation=$false;projectPhaseChange=$false;gitOrPush=$false;sharedQuotaOrResource=$false;unknownScope=$false}
        $payload=@([ordered]@{payloadKind='normalized-text';normalizedIdentity=[string]$objectIdentities[0].identity;canonicalizationVersion='UTF8_LF_V1'})
        $package.externalBinding=[ordered]@{schemaVersion=1;route='DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL';provider='measurement-provider';orderedOperations=@([ordered]@{operationId='OP-1';operationKind='PROVIDER_PUBLIC_METADATA_READ';declaredInputClass='ZERO_PROJECT_DATA';payloads=@()},[ordered]@{operationId='OP-2';operationKind='bounded-transform';declaredInputClass='EXACT_PAYLOADS';payloads=$payload});outputUse='project-local measurement result';totalQuantity=2;perOperationRetryCeiling=1;totalRetryCeiling=2;costClass='FREE';costCeiling=0;stopConditions=@('stop on provider error','stop on ambiguous consumption');batchExecutionMode='ONE_LOGICAL_ATOMIC_EXECUTION';reissuable=$false;ambiguousConsumptionPolicy='BLOCK';escalationFlags=$zeroEscalation}
      }
      Write-Utf8 $authorizationPath ($package|ConvertTo-Json -Depth 40);$authorizationIdentity=Get-Identity $authorizationPath
    }
    $intent=[ordered]@{schemaVersion=1;objective=[string]$fixture.objective;requestedActionKind=[string]$fixture.actionKind;requestedResultKind=[string]$fixture.resultKind;semanticHints=@($fixture.semanticHints);pathHints=@($fixture.pathHints);capabilityHints=@($fixture.capabilities);mutationHints=@($fixture.mutationHints);externalHints=@($fixture.externalHints);ambiguityState=[string]$fixture.ambiguityState}
    $discover=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$projectRoot;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=(Get-Identity $projectPath);expectedCorrectionsIdentity=(Get-Identity (Join-Path $projectRoot '.ai-workspace\corrections.json'));expectedTaskIdentity=(Get-Identity $taskPath);observedActor=[string]$fixture.actor;capabilities=@($fixture.capabilities);exactPaths=@($fixture.exactPaths);forbiddenPaths=@();protectedPaths=@('.ai-workspace/');authorizationPackagePath=$authorizationPath;expectedAuthorizationIdentity=$authorizationIdentity;userDecision=$userDecision;recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
    $discoverPath=Join-Path $projectRoot '.ai-workspace\measure-discover.json';Write-Utf8 $discoverPath ($discover|ConvertTo-Json -Depth 30)
    $initial=Invoke-Cold $resolver $discoverPath ([int]$fixture.expectedExitCodes.DISCOVER);$discover=$initial.Output|ConvertFrom-Json;$receipt=$discover.compactReceipt;$receiptPath=Join-Path $projectRoot '.ai-workspace\measure-receipt.json';Write-Utf8 $receiptPath ($receipt|ConvertTo-Json -Depth 50)
    $requiredPrep=@($receipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$requiredResult=@($receipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $admit=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $receiptPath);objective=[string]$fixture.objective;actionKind=[string]$fixture.actionKind;resultKind=[string]$fixture.resultKind;exactPaths=@($fixture.exactPaths);authorizationIdentity=$authorizationIdentity;preparationReceipts=@($requiredPrep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    $admitPath=Join-Path $projectRoot '.ai-workspace\measure-admit.json';Write-Utf8 $admitPath ($admit|ConvertTo-Json -Depth 30)
    $postimages=@($fixture.exactPaths|ForEach-Object{'OBJECT_POSTIMAGE|'+[string]$_+'|'+(Get-Identity (Join-Path $projectRoot ([string]$_)))});$final=$admit|ConvertTo-Json -Depth 30|ConvertFrom-Json;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@($requiredResult+$postimages);$final.deliveryReceipts=@('MEASUREMENT_DELIVERY');$finalPath=Join-Path $projectRoot '.ai-workspace\measure-final.json';Write-Utf8 $finalPath ($final|ConvertTo-Json -Depth 30)
    $modeResults=[ordered]@{}
    foreach($mode in @([pscustomobject]@{Name='DISCOVER';Path=$discoverPath},[pscustomobject]@{Name='ADMIT_ACTION';Path=$admitPath},[pscustomobject]@{Name='FINALIZE_OUTPUT';Path=$finalPath})){
      $expected=[int]$fixture.expectedExitCodes.($mode.Name);1..$Warmups|ForEach-Object{$null=Invoke-Cold $resolver $mode.Path $expected};$samples=@();1..$MeasuredRuns|ForEach-Object{$samples+=(Invoke-Cold $resolver $mode.Path $expected).Milliseconds};$modeResults[$mode.Name]=Get-Statistics $samples
    }
    $results+=[ordered]@{fixtureId=[string]$fixture.fixtureId;fixtureIdentity=[string]$fixture.fixtureIdentity;selectedPackBytes=[int]$receipt.selectedPackBytes;selectedPackEstimatedTokens=[int]$receipt.selectedPackEstimatedTokens;selectedRequirementCount=@($receipt.selectedObligations).Count;modes=$modeResults}
  }
  $output=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';host=([Environment]::OSVersion.VersionString+' / PowerShell '+$PSVersionTable.PSVersion+' / '+[Runtime.InteropServices.RuntimeInformation]::OSArchitecture+' / '+[Environment]::ProcessorCount+' logical processors');process='cold pwsh process';filesystem='warmed after fixture setup';warmups=$Warmups;measuredRuns=$MeasuredRuns;fixtures=$results}
  if($AsJson){$output|ConvertTo-Json -Depth 40}else{$output|ConvertTo-Json -Depth 40}
}finally{
  if(Test-Path -LiteralPath $temp){Get-ChildItem -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
