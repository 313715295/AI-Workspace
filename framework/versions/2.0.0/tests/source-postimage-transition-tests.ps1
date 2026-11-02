[CmdletBinding()]
param([string]$LegacyResolverPath,[switch]$FixtureContractOnly)

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

function New-Correction([string]$Id,[string]$Rule,[string[]]$Actions,[string[]]$Results){return [ordered]@{correctionId=$Id;introducedAgainstFramework='2.0.0';requirementReason=('Fixture reason for '+$Id);effectiveRule=$Rule;applicability='Fixture-only source transition validation.';decisionLocator='fixture:source-postimage';selectors=[ordered]@{profiles=@('STANDARD');roles=@('EXECUTOR');phases=@('IMPLEMENT');actionKinds=@($Actions);resultKinds=@('IMPLEMENTATION_RESULT');pathPrefixes=@('.ai-workspace/corrections.json');capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@($Results);requiredFacts=@();mechanicalCheckRefs=@()}}

$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$sourceFrameworkRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $versionRoot '..\..\..')))
$resolver=Join-Path $versionRoot 'scripts\resolve-process-requirements.ps1'
$module=Join-Path $versionRoot 'scripts\ProcessRequirementComposition.psm1'
Import-Module $module -Force
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1') -Force
function Assert-ResolverSuccess($Run,[string]$Name){$status=if($null-ne$Run.Value-and$null-ne$Run.Value.PSObject.Properties['status']){[string]$Run.Value.status}else{'UNPARSED'};$reason=if($null-ne$Run.Value-and$null-ne$Run.Value.PSObject.Properties['reason']){[string]$Run.Value.reason}else{'NOT_REPORTED'};if($Run.Code-ne0-or$status-cnotin@('PASS','EVALUATION_ONLY')){Write-Output ('DIAG|'+$Name+'|code='+$Run.Code+'|status='+$status+'|reason='+$reason+'|text='+$Run.Text);throw ('RESOLVER_STEP_FAILED|'+$Name+'|code='+$Run.Code+'|status='+$status+'|reason='+$reason)}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-source-postimage-'+[guid]::NewGuid().ToString('N'))
try{
  # Copy the declared runtime recipe, excluding historical Qpre attachments.
  $fixtureDefinition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
  $frameworkRoot=Join-Path $temp 'framework-root'
  $fixtureVersion=New-AiwTestRuntimeFixture -SourceRoot $sourceFrameworkRoot -DestinationRoot $frameworkRoot -VersionPaths @($fixtureDefinition.mechanismVersionPaths)

  $project=Join-Path $temp 'project';New-Item -ItemType Directory -Path $project -Force|Out-Null;& git -C $project init -q
  $control=Join-Path $project '.ai-workspace';New-Item -ItemType Directory -Path (Join-Path $control 'tasks\active') -Force|Out-Null;New-Item -ItemType Directory -Path (Join-Path $control 'knowledge') -Force|Out-Null
  $projectPath=Join-Path $control 'project.json';$controllerPath=Join-Path $control 'controller.json';$correctionsPath=Join-Path $control 'corrections.json';$policyPath=Join-Path $control 'process-policy.json';$taskPath=Join-Path $control 'tasks\active\SOURCE-POSTIMAGE-001.md';$statusPath=Join-Path $control 'STATUS.md';$indexPath=Join-Path $control 'knowledge\index.json'
  Write-Json $projectPath ([ordered]@{schemaVersion=7;id='source-postimage-fixture';displayName='Source Postimage Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@([ordered]@{id='postimage-standard';provider='LOCAL_DIRECTORY';locator=[ordered]@{root='.'};allowedPaths=@([ordered]@{kind='FILE';locator='standards/rule.md'});decisionLocator='fixture:explicit-standard-read'});processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
  Write-Json $controllerPath ([ordered]@{schemaVersion=1;projectId='source-postimage-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nNo permanent project process rule is active in this legacy region. Structured rules belong to ``.ai-workspace/process-policy.json``.`n<!-- PROJECT-CUSTOM:END -->"
  Write-Utf8 $taskPath "# SOURCE-POSTIMAGE-001 — source postimage fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
  Write-Utf8 $statusPath 'BASELINE'
  Write-Json $indexPath ([ordered]@{schemaVersion=1;entries=@()})
  $oldCorrection=New-Correction 'OLD_RESULT_GATE' 'The old action result must remain proven.' @('CONTROL_WRITE') @('OLD_RESULT_REQUIRED')
  $corrections=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='source-postimage-fixture';corrections=@($oldCorrection)};Write-Json $correctionsPath $corrections
  $policy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='source-postimage-fixture';rules=@()};Write-Json $policyPath $policy
  $discoverPath=Join-Path $control 'source-postimage-discover.json';$receiptPath=Join-Path $control 'source-postimage-receipt.json';$boundaryPath=Join-Path $control 'source-postimage-boundary.json'

  function New-Package([string]$Name,[string[]]$Paths,[string[]]$Actions=@('CONTROL_WRITE')){
    $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='SOURCE-POSTIMAGE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='executor-fixture';bundle='SOURCE_POSTIMAGE_FIXTURE';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@($Actions);exactPaths=@($Paths);objectIdentities=@($Paths|ForEach-Object{[ordered]@{path=$_;identity=$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=Get-Identity $projectPath}
    $path=Join-Path $control ($Name+'-package.json');Write-Json $path $package;return $path
  }
  function Start-Action([string]$Name,[string[]]$Paths,[string]$PackagePath,[string]$Action='CONTROL_WRITE',[switch]$ProtectControl){
    $actionActor=[string](Get-Content -LiteralPath $PackagePath -Raw|ConvertFrom-Json).grantee
    $intent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:implementation')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:code')};stage=[ordered]@{state='KNOWN';values=@('aiw:implementation')}};objective=('Validate '+$Name+' source postimage transition');requestedActionKind=$Action;requestedResultKind=$(if($Action-ceq'TEST_RUN'){'TEST_RESULT'}else{'IMPLEMENTATION_RESULT'});semanticHints=@('source postimage transition');pathHints=@($Paths);capabilityHints=@();mutationHints=@($(if($Action-ceq'CONTROL_WRITE'){'control'}else{'test'}));externalHints=@();ambiguityState='CLEAR'}
    $discover=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity $projectPath;expectedCorrectionsIdentity=Get-Identity $correctionsPath;expectedTaskIdentity=Get-Identity $taskPath;observedActor='executor-fixture';capabilities=@();exactPaths=@($Paths);forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$PackagePath;expectedAuthorizationIdentity=Get-Identity $PackagePath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
    # Ordinary control fixtures permit their exact candidates; the explicit
    # protected-candidate case retains the whole-control exclusion.
    if(-not$ProtectControl){$discover.protectedPaths=@('.ai-workspace/private/')}
    $discover.observedActor=$actionActor
    Write-Json $discoverPath $discover;$run=Invoke-Resolver $resolver $discoverPath
    if($run.Code-ne0){return [pscustomobject]@{Discover=$run;Admit=$null;ReceiptPath=$null;Prep=@();Results=@()}}
    Assert-ResolverSuccess $run $Name;Write-Json $receiptPath $run.Value.compactReceipt;$prep=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$results=@($run.Value.compactReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $admit=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;preparationReceipts=$prep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()};Write-Json $boundaryPath $admit;$admitRun=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $admitRun 'admitRun'
    return [pscustomobject]@{Discover=$run;Admit=$admitRun;ReceiptPath=$receiptPath;Prep=$prep;Results=$results}
  }
  function Invoke-Finalize($Action,[string[]]$Results){$finalize=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$Action.ReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $Action.ReceiptPath;preparationReceipts=@($Action.Prep);resultReceipts=@($Results);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'};Write-Json $boundaryPath $finalize;return Invoke-Resolver $resolver $boundaryPath}
  function Get-Postimages([string[]]$Paths){return @($Paths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'MISSING'})})}

  # Each case retains one original preimage package. Every later action consumes
  # an actual FINALIZE continuation; absent candidates are never re-authorized.
  foreach($case in @('delete-only','mixed')){foreach($withTest in @($false,$true)){
    $name=$case+$(if($withTest){'-write-test-route'}else{'-write-route'})
    $removed='src/'+$name+'-removed.txt';Write-Utf8 (Join-Path $project $removed) 'original removed bytes'
    $paths=@($removed)
    if($case-ceq'mixed'){
      $modified='src/'+$name+'-modified.txt';$added='src/'+$name+'-added.txt'
      Write-Utf8 (Join-Path $project $modified) 'original modified bytes';$paths+=@($modified,$added)
    }
    $steps=@('SOURCE_WRITE');if($withTest){$steps+=@('TEST_RUN')};$steps+=@('REVIEW_ROUTE')
    $packagePath=New-Package $name $paths $steps
    $package=Get-Content $packagePath -Raw|ConvertFrom-Json -Depth 100
    $package|Add-Member continuationPlan $steps;$package.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
    Write-Json $packagePath $package;$originalPackageIdentity=Get-Identity $packagePath
    $requirementsPath=Join-Path $control ($name+'-requirements.md');Write-Utf8 $requirementsPath 'Verify the exact add, modify and delete result before independent review.'
    $requirements=[ordered]@{path=[IO.Path]::GetRelativePath($project,$requirementsPath).Replace('\','/');identity=Get-Identity $requirementsPath}
    $continuationPath='';$selfRef=$null
    foreach($step in $steps){
      $stepName=$name+'-'+$step;$stepReceipt=Join-Path $control ($stepName+'-compact.json')
      $intent=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:implementation')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:code')};stage=[ordered]@{state='KNOWN';values=@('aiw:implementation')}};objective='Validate actual deletion continuations through current candidate review admission';requestedActionKind=$step;requestedResultKind=$(switch($step){TEST_RUN{'TEST_RESULT'} REVIEW_ROUTE{'HANDOFF'} default{'IMPLEMENTATION_RESULT'}});semanticHints=@('source','test','review');pathHints=$paths;capabilityHints=@();mutationHints=@($(switch($step){SOURCE_WRITE{'source'} TEST_RUN{'test'} REVIEW_ROUTE{'review'}}));externalHints=@();ambiguityState='CLEAR'}
      $input=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity $projectPath;expectedCorrectionsIdentity=Get-Identity $correctionsPath;expectedTaskIdentity=Get-Identity $taskPath;observedActor='executor-fixture';capabilities=@();exactPaths=$paths;forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=$originalPackageIdentity;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
      if($continuationPath){$input.continuationReceiptPath=$continuationPath;$input.expectedContinuationReceiptIdentity=Get-Identity $continuationPath}
      Write-Json $discoverPath $input;$discovery=Invoke-Resolver $resolver $discoverPath;Assert-ResolverSuccess $discovery 'discovery'
      if($discovery.Code-ne0){throw ('CHAIN_DISCOVER|'+$stepName+'|'+$discovery.Text)}
      Write-Json $stepReceipt $discovery.Value.compactReceipt
      $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$stepReceipt;expectedDiscoverReceiptIdentity=Get-Identity $stepReceipt;preparationReceipts=@($discovery.Value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
      if($step-ceq'REVIEW_ROUTE'){
        # A fresh pure reviewer package binds the actual candidate. The
        # production write/test/route chain keeps its original preimages.
        $reviewPackage=$package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $reviewPackage.PSObject.Properties.Remove('continuationPlan')
        $reviewPackage.actions=@('REVIEW_EXECUTE');$reviewPackage.grantee='reviewer-fixture';$reviewPackage.reviewIndependence='INDEPENDENT'
        $reviewPackage.objectIdentities=@($paths|ForEach-Object{[ordered]@{path=$_;identity=$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})}})
        $reviewPackage|Add-Member candidateWriter 'executor-fixture';$reviewPackage|Add-Member materialContributors @()
        $reviewPackage.invalidatesOn=@($reviewPackage.invalidatesOn|Where-Object{$_-cne'CONTINUATION_RESULT_DRIFT'})+@('CONTRIBUTOR_SET_CHANGE')
        $reviewPath=Join-Path $control ($name+'-review-package.json');Write-Json $reviewPath $reviewPackage
        $boundary.evidenceRefs=@($selfRef)
        $boundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='reviewer-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=[ordered]@{path=[IO.Path]::GetRelativePath($project,$reviewPath).Replace('\','/');identity=Get-Identity $reviewPath}}
      }
      Write-Json $boundaryPath $boundary;$admitted=Invoke-Resolver $resolver $boundaryPath;Assert-ResolverSuccess $admitted 'admitted'
      Assert-True ($admitted.Code-eq0) ($stepName+'-actual-discover-and-admit')
      if($step-ceq'REVIEW_ROUTE'){
        Assert-True ((Get-Identity $packagePath)-ceq$originalPackageIdentity-and-not(Test-Path -LiteralPath (Join-Path $project $removed))) ($name+'-original-preimage-package-survives-through-review-route')
        # The real route checker must also reject postimage drift and recreation.
        $savedLocation=Get-Location;$savedCurrent=[Environment]::CurrentDirectory
        try{
          Set-Location -LiteralPath $project;[Environment]::CurrentDirectory=$project
          $observed=@($paths|ForEach-Object{$_+'='+$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})})
          $check=@{PackagePath=$packagePath;ObservedActor='executor-fixture';ObservedTaskId='SOURCE-POSTIMAGE-001';ObservedOwner='owner-fixture';ObservedAction='REVIEW_ROUTE';ObservedPath=$paths;ObservedIdentity=$observed;TaskPath='.ai-workspace/tasks/active/SOURCE-POSTIMAGE-001.md';ExpectedTaskIdentity=$package.taskIdentity;ControllerControlPath='.ai-workspace/controller.json';ContinuationReceiptPath=$continuationPath;ExpectedContinuationReceiptIdentity=(Get-Identity $continuationPath)}
          $output=@(& (Join-Path $versionRoot 'scripts/check-authorization.ps1') @check 2>&1);$code=$LASTEXITCODE
          Assert-True ($code-eq0) ($name+'-independent-action-checker-consumes-real-route-continuation')
          Write-Utf8 (Join-Path $project $removed) 'unexpected recreated bytes'
          $check.ObservedIdentity=@($paths|ForEach-Object{$_+'='+$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})})
          $output=@(& (Join-Path $versionRoot 'scripts/check-authorization.ps1') @check 2>&1);$code=$LASTEXITCODE
          Assert-True ($code-ne0) ($name+'-unexpected-recreation-rejects-stale-continuation')
          [IO.File]::Delete((Join-Path $project $removed))
          if($case-ceq'mixed'){
            $modifiedPath=Join-Path $project $modified;$savedBytes=[IO.File]::ReadAllBytes($modifiedPath)
            try{
              Write-Utf8 $modifiedPath 'unexpected third-party modified bytes'
              $check.ObservedIdentity=@($paths|ForEach-Object{$_+'='+$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})})
              $output=@(& (Join-Path $versionRoot 'scripts/check-authorization.ps1') @check 2>&1);$code=$LASTEXITCODE
              Assert-True ($code-ne0) ($name+'-modified-byte-drift-rejects-stale-continuation')
            }finally{[IO.File]::WriteAllBytes($modifiedPath,$savedBytes)}
          }
          $reviewCheck=$check.Clone();$reviewCheck.PackagePath=$reviewPath;$reviewCheck.ObservedActor='reviewer-fixture';$reviewCheck.ObservedAction='REVIEW_EXECUTE'
          $reviewCheck.Remove('ContinuationReceiptPath');$reviewCheck.Remove('ExpectedContinuationReceiptIdentity')
          $reviewCheck.ObservedIdentity=@($paths|ForEach-Object{$_+'='+$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})})
          $output=@(& (Join-Path $versionRoot 'scripts/check-authorization.ps1') @reviewCheck 2>&1);$code=$LASTEXITCODE
          Assert-True ($code-eq0) ($name+'-current-pure-reviewer-package-checks-independent-candidate')
          $hostPath=Join-Path $control ($name+'-synthetic-host-result.json')
          Write-Json $hostPath ([ordered]@{isError=$false;content=@([ordered]@{type='text';text='{"threadId":"reviewer-fixture"}'})})
          $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($discovery.Value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+(Get-Postimages $paths)
          $boundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient='reviewer-fixture';observedRecipient='reviewer-fixture';outcome='SUCCESS';evidence=($hostPath+'#'+(Get-Identity $hostPath));reviewPackageRef=[ordered]@{path=[IO.Path]::GetRelativePath($project,$reviewPath).Replace('\','/');identity=Get-Identity $reviewPath}}
          Write-Json $boundaryPath $boundary;$finalized=Invoke-Resolver $resolver $boundaryPath
          Assert-ResolverSuccess $finalized ('CHAIN_ROUTE_FINALIZE|'+$name)
          Assert-True ($finalized.Value.status-ceq'PASS'-and$finalized.Value.consumer.recipient-ceq'reviewer-fixture'-and$finalized.Value.delivery.delivered) ($name+'-actual-route-finalize-consumes-synthetic-host-delivery')
          Assert-True ((Get-Identity $packagePath)-ceq$originalPackageIdentity) ($name+'-original-source-package-unchanged-after-complete-chain')
        }finally{Set-Location $savedLocation;[Environment]::CurrentDirectory=$savedCurrent}
        continue
      }
      if($step-ceq'SOURCE_WRITE'){
        [IO.File]::Delete((Join-Path $project $removed))
        if($case-ceq'mixed'){Write-Utf8 (Join-Path $project $modified) 'modified candidate bytes';Write-Utf8 (Join-Path $project $added) 'added candidate bytes'}
      }
      $candidates=@($paths|ForEach-Object{[ordered]@{path=$_;identity=$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'MISSING'})}})
      $selfPath=Join-Path $control ($stepName+'-self.json')
      $selfRecord=[ordered]@{schemaVersion=1;taskId='SOURCE-POSTIMAGE-001';actor='executor-fixture';candidateObjects=$candidates;requirementsRef=$requirements;outcome='PASS';checks=@([ordered]@{id='exact-candidate';method='MODEL_JUDGMENT';outcome='PASS';reason='Isolated fixture observes every added/modified byte and the deleted path; this is not production test evidence.';evidenceLocators=@($requirements)});evidenceLocators=@($requirements)}
      if($step-ceq'TEST_RUN'){
        # Run the existing checker against this original continuation and its
        # actual current candidate; retain the native command evidence.
        $testArgs=[ordered]@{PackagePath=$packagePath;ObservedActor='executor-fixture';ObservedTaskId='SOURCE-POSTIMAGE-001';ObservedOwner='owner-fixture';ObservedAction='TEST_RUN';ObservedPath=$paths;ObservedIdentity=@($paths|ForEach-Object{$_+'='+$(if(Test-Path -LiteralPath (Join-Path $project $_) -PathType Leaf){Get-Identity (Join-Path $project $_)}else{'NEW'})});TaskPath='.ai-workspace/tasks/active/SOURCE-POSTIMAGE-001.md';ExpectedTaskIdentity=$package.taskIdentity;ControllerControlPath='.ai-workspace/controller.json';ContinuationReceiptPath=$continuationPath;ExpectedContinuationReceiptIdentity=(Get-Identity $continuationPath)}
        $testArgsPath=Join-Path $control ($stepName+'-command-args.json');Write-Json $testArgsPath $testArgs
        $testCommand="`$a=Get-Content -LiteralPath '"+$testArgsPath.Replace("'","''")+"' -Raw|ConvertFrom-Json -AsHashtable; & '"+(Join-Path $versionRoot 'scripts/check-authorization.ps1').Replace("'","''")+"' @a"
        $testRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-Command',$testCommand) -WorkingDirectory $project -GroupId ('source-postimage-'+$stepName)
        if($testRun.Code-ne0){throw ('CHAIN_TEST_COMMAND_FAILED|'+$stepName+'|'+($testRun.Output-join';'))}
        $outputPath=Join-Path $control ($stepName+'-command-output.txt');Write-Utf8 $outputPath ($testRun.Output-join"`n")
        $commandPath=Join-Path $control ($stepName+'-command.json');Write-Json $commandPath ([ordered]@{command=([Environment]::ProcessPath+' -NoProfile -NonInteractive -Command '+$testCommand);exitCode=$testRun.Code;output=[ordered]@{path=[IO.Path]::GetRelativePath($project,$outputPath).Replace('\','/');identity=Get-Identity $outputPath}})
        $selfRecord.checks+=@([ordered]@{id='actual-continuation-checker';method='COMMAND';outcome='PASS';reason='Actual isolated native checker consumes the original TEST_RUN continuation and current add/modify/delete candidate; no production execution claimed.';evidenceLocators=@([ordered]@{path=[IO.Path]::GetRelativePath($project,$commandPath).Replace('\','/');identity=Get-Identity $commandPath})})
      }
      Write-Json $selfPath $selfRecord;$selfRef=[ordered]@{kind='SELF_CHECK';path=[IO.Path]::GetRelativePath($project,$selfPath).Replace('\','/');identity=Get-Identity $selfPath}
      $boundary.mode='FINALIZE_OUTPUT';$boundary.evidenceRefs=@($selfRef);$boundary.resultReceipts=@($discovery.Value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+(Get-Postimages $paths)
      Write-Json $boundaryPath $boundary;$finalized=Invoke-Resolver $resolver $boundaryPath
      Assert-ResolverSuccess $finalized ('CHAIN_FINALIZE|'+$stepName)
      Assert-True ($finalized.Value.status-ceq'PASS') ($stepName+'-actual-finalize')
      $continuationPath=Join-Path $control ($stepName+'-continuation.json');Write-Json $continuationPath $finalized.Value.continuationReceipt
      Assert-True (@($finalized.Value.continuationReceipt.postObjectIdentities|Where-Object{$_.path-ceq$removed-and$_.identity-ceq'NEW'}).Count-eq1) ($stepName+'-authorization-absence-stays-new')
    }
    if($FixtureContractOnly){Write-Output ('PARTIAL|FIXTURE_CONTRACT_ONLY|source-postimage-transition|target=delete-only-write-route|code='+$finalized.Code+'|status='+$finalized.Value.status+'|reason='+$finalized.Value.reason);return}
  }}

  $taskRelative='.ai-workspace/tasks/active/SOURCE-POSTIMAGE-001.md'
  $protectedPackage=New-Package 'protected-current-card' @($taskRelative)
  $protectedAuth=Get-Content -LiteralPath $protectedPackage -Raw|ConvertFrom-Json
  $protectedAuth.grantee='owner-fixture';Write-Json $protectedPackage $protectedAuth
  $protectedBefore=Get-Identity $taskPath;$protectedStatusBefore=Get-Identity $statusPath
  $protectedAction=Start-Action 'protected-current-card' @($taskRelative) $protectedPackage -ProtectControl
  Assert-True ($protectedAction.Discover.Code-eq0-and$protectedAction.Admit.Code-eq0) 'protected-card-fixture-reaches-original-finalize-guard'
  $protectedFinal=Invoke-Finalize $protectedAction (@($protectedAction.Results)+(Get-Postimages @($taskRelative)))
  Assert-True ($protectedFinal.Code-ne0-and$protectedFinal.Text.Contains('EVIDENCE_PATH_FORBIDDEN')) 'protected-control-candidate-rejected-by-evidence-path-guard'
  Assert-True ((Get-Identity $taskPath)-ceq$protectedBefore-and(Get-Identity $statusPath)-ceq$protectedStatusBefore) 'protected-control-rejection-performs-zero-overwrite'
  $mixedPaths=@($taskRelative,'.ai-workspace/STATUS.md');$mixedPackage=New-Package 'current-card-mixed' $mixedPaths
  $beforeTask=Get-Identity $taskPath;$beforeStatus=Get-Identity $statusPath
  $mixedAction=Start-Action 'current-card-mixed' $mixedPaths $mixedPackage
  Assert-True ($mixedAction.Discover.Code-ne0-and$mixedAction.Discover.Text.Contains('CONTROL_CURRENT_TASK_MIXED_SCOPE')) 'mixed-current-card-is-rejected-before-admission'
  Assert-True ((Get-Identity $taskPath)-ceq$beforeTask-and(Get-Identity $statusPath)-ceq$beforeStatus) 'mixed-current-card-rejection-performs-zero-write'
  foreach($variant in @(
    @{Name='filename-case';Path=$taskRelative.ToLowerInvariant()},
    @{Name='directory-case';Path=$taskRelative.Replace('.ai-workspace/tasks/active/','.AI-WORKSPACE/TASKS/ACTIVE/')}
  )){
    $variantPaths=@($variant.Path,'.ai-workspace/STATUS.md')
    $variantPackage=New-Package ('current-card-'+$variant.Name) $variantPaths
    $variantAction=Start-Action ('current-card-'+$variant.Name) $variantPaths $variantPackage
    Assert-True ($variantAction.Discover.Code-ne0-and$variantAction.Discover.Text.Contains('CONTROL_CURRENT_TASK_MIXED_SCOPE')) ('mixed-current-card-'+$variant.Name+'-rejected-before-admission')
    Assert-True ((Get-Identity $taskPath)-ceq$beforeTask-and(Get-Identity $statusPath)-ceq$beforeStatus) ('mixed-current-card-'+$variant.Name+'-zero-write')
  }
  $cardPackage=New-Package 'single-current-card' @($taskRelative);$cardAuth=Get-Content -LiteralPath $cardPackage -Raw|ConvertFrom-Json;$cardAuth.grantee='owner-fixture';Write-Json $cardPackage $cardAuth
  $cardAction=Start-Action 'single-current-card' @($taskRelative) $cardPackage
  Assert-True ($cardAction.Discover.Code-eq0-and$cardAction.Admit.Code-eq0) 'single-current-card-owner-admission'
  Write-Utf8 $taskPath ([IO.File]::ReadAllText($taskPath)+"`nProgress: actual owner update.`n")
  $cardFinal=Invoke-Finalize $cardAction (@($cardAction.Results)+(Get-Postimages @($taskRelative)))
  Assert-ResolverSuccess $cardFinal 'cardFinal';Assert-True ($cardFinal.Code-eq0) 'single-current-card-preserves-original-finalize-chain'
  $otherRelative='.ai-workspace/tasks/active/SOURCE-OTHER-001.md';$otherPath=Join-Path $project $otherRelative
  Write-Utf8 $otherPath ([IO.File]::ReadAllText($taskPath).Replace('SOURCE-POSTIMAGE-001','SOURCE-OTHER-001'))
  $otherPaths=@($otherRelative,'.ai-workspace/STATUS.md');$otherPackage=New-Package 'other-card-batch' $otherPaths;$otherAction=Start-Action 'other-card-batch' $otherPaths $otherPackage
  Assert-True ($otherAction.Discover.Code-eq0-and$otherAction.Admit.Code-eq0) 'other-task-plus-document-batch-remains-admissible'
  Write-Utf8 $otherPath ([IO.File]::ReadAllText($otherPath)+"`nProgress: bounded other task update.`n");Write-Utf8 $statusPath 'OTHER-TASK-UPDATED'
  $otherFinal=Invoke-Finalize $otherAction (@($otherAction.Results)+(Get-Postimages $otherPaths))
  Assert-ResolverSuccess $otherFinal 'otherFinal';Assert-True ($otherFinal.Code-eq0) 'other-task-plus-document-batch-finalizes'

  $exact3=@('.ai-workspace/corrections.json','.ai-workspace/STATUS.md','.ai-workspace/knowledge/index.json');$correctionPackage=New-Package 'correction-positive' $exact3;$correctionAction=Start-Action 'correction-positive' $exact3 $correctionPackage
  Assert-True ($correctionAction.Discover.Code-eq0-and$correctionAction.Admit.Code-eq0-and'OLD_RESULT_REQUIRED'-cin@($correctionAction.Results)) 'correction-source-transition-old-authority-admits-and-binds-old-result'
  $newCorrection=$oldCorrection|ConvertTo-Json -Depth 50|ConvertFrom-Json;$newCorrection.selectors.actionKinds=@('TEST_RUN');$newCorrection.resultRequirements=@();$corrections.corrections=@($newCorrection);Write-Json $correctionsPath $corrections;Write-Utf8 $statusPath 'UPDATED';Write-Json $indexPath ([ordered]@{schemaVersion=1;entries=@([ordered]@{id='UPDATED'})})
  $postcheck=Invoke-ProcessRequirementComposition -ProjectRoot $project -FrameworkRoot $frameworkRoot -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity (Get-Identity $projectPath) -ExpectedCorrectionsIdentity (Get-Identity $correctionsPath) -Profile 'STANDARD' -Role 'EXECUTOR' -Phase 'IMPLEMENT' -Actor 'executor-fixture' -TaskIdentity (Get-Identity $taskPath) -Capabilities @() -IntentEnvelope $correctionAction.Discover.Value.compactReceipt.intentEnvelope -Objective 'Validate correction source postimage transition' -ActionKind 'CONTROL_WRITE' -ResultKind 'IMPLEMENTATION_RESULT' -ExactPaths $exact3 -ForbiddenPaths @('private/')
  $postimages=Get-Postimages $exact3;$withoutOld=@($correctionAction.Results|Where-Object{$_-cne'OLD_RESULT_REQUIRED'})+$postimages;$oldGateRun=Invoke-Finalize $correctionAction $withoutOld
  Assert-True ($postcheck.status-ceq'PASS'-and$oldGateRun.Code-ne0-and[string]$oldGateRun.Value.reason-ceq'RESULT_INCOMPLETE'-and'OLD_RESULT_REQUIRED'-cin@($oldGateRun.Value.missingResult)) ('correction-source-transition-preserves-old-result-obligation|'+$oldGateRun.Text)
  $correctionFinalize=Invoke-Finalize $correctionAction (@($correctionAction.Results)+$postimages)
  Assert-ResolverSuccess $correctionFinalize 'correctionFinalize';Assert-True ($correctionFinalize.Code-eq0-and[string]$correctionFinalize.Value.sourcePostimageTransition.status-ceq'PASS'-and'correctionsIdentity'-cin@($correctionFinalize.Value.sourcePostimageTransition.changedBindings)) 'correction-status-index-postimages-finalize-through-recomposed-source'

  Write-Utf8 (Join-Path $project 'standards\rule.md') 'Current external standard rule.'
  $policyPaths=@('.ai-workspace/process-policy.json');$policyPackage=New-Package 'policy-positive' $policyPaths;$policyAction=Start-Action 'policy-positive' $policyPaths $policyPackage;Assert-True ($policyAction.Discover.Code-eq0-and$policyAction.Admit.Code-eq0) 'policy-source-transition-old-authority-admits'
  $policyRule=[ordered]@{ruleId='BOUND_STANDARD';requirementReason='Fixture source binding';selectors=[ordered]@{profiles=@('STANDARD');roles=@('EXECUTOR');phases=@('IMPLEMENT');actionKinds=@('CONTROL_WRITE');resultKinds=@('IMPLEMENTATION_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:policy';source=[ordered]@{rootSourceId='STANDARD';documents=@([ordered]@{sourceId='STANDARD';locator='standards/rule.md';identity=Get-Identity (Join-Path $project 'standards\rule.md');mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}}
  Import-Module (Join-Path $fixtureVersion 'scripts/ContentSources.psm1') -Force
  $bindings=(Get-Content $projectPath -Raw|ConvertFrom-Json -Depth 100).sourceBindings
  $doc=[pscustomobject]@{sourceId='STANDARD';bindingId='postimage-standard';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator='standards/rule.md';identity=(Get-Identity (Join-Path $project 'standards/rule.md'));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
  $doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $bindings
  $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='postimage-standard';itemId='BOUND_STANDARD';revision=$doc.revision;itemIdentity='';rootSourceId='STANDARD';documents=@($doc)}
  $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor;$policyRule.source=$descriptor
  $policy.rules=@($policyRule);Write-Json $policyPath $policy;$policyFinalize=Invoke-Finalize $policyAction (@($policyAction.Results)+(Get-Postimages $policyPaths))
  Assert-ResolverSuccess $policyFinalize 'policyFinalize';Assert-True ($policyFinalize.Code-eq0-and'policyIdentity'-cin@($policyFinalize.Value.sourcePostimageTransition.changedBindings)-and'projectStandardsIdentity'-cin@($policyFinalize.Value.sourcePostimageTransition.changedBindings)) 'policy-postimage-derives-and-validates-project-standard-identity'

  $statusOnly=@('.ai-workspace/STATUS.md');$externalPackage=New-Package 'external-drift' $statusOnly;$externalAction=Start-Action 'external-drift' $statusOnly $externalPackage;Write-Utf8 $statusPath 'EXTERNAL-DRIFT-CASE';Write-Utf8 (Join-Path $project 'standards\rule.md') 'Unrelated external drift.';$externalRun=Invoke-Finalize $externalAction (@($externalAction.Results)+(Get-Postimages $statusOnly))
  Assert-True ($externalRun.Code-ne0-and($externalRun.Text.Contains('DISCOVER_SOURCE_DRIFT|projectStandardsIdentity')-or$externalRun.Text.Contains('CONTENT_IDENTITY_DRIFT'))) 'external-standard-independent-drift-remains-rejected'
  Write-Utf8 (Join-Path $project 'standards\rule.md') 'Current external standard rule.'

  $correctionPaths=@('.ai-workspace/corrections.json');$postimagePackage=New-Package 'postimage-negative' $correctionPaths;$postimageAction=Start-Action 'postimage-negative' $correctionPaths $postimagePackage;$secondCorrection=New-Correction 'SECOND_RULE' 'A second valid correction body.' @('TEST_RUN') @();$corrections.corrections=@($newCorrection,$secondCorrection);Write-Json $correctionsPath $corrections;$actualPost=Get-Postimages $correctionPaths
  $omittedRun=Invoke-Finalize $postimageAction @($postimageAction.Results);$wrongRun=Invoke-Finalize $postimageAction (@($postimageAction.Results)+@('OBJECT_POSTIMAGE|.ai-workspace/corrections.json|0|'+('0'*64)));$duplicateRun=Invoke-Finalize $postimageAction (@($postimageAction.Results)+$actualPost+$actualPost)
  Assert-True ($omittedRun.Code-ne0-and$wrongRun.Code-ne0-and$duplicateRun.Code-ne0-and$omittedRun.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED')-and$wrongRun.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED')-and($duplicateRun.Text.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED')-or$duplicateRun.Text.Contains('INPUT_ARRAY_ITEM|resultReceipts'))) 'source-transition-omitted-wrong-and-duplicate-postimages-rejected'
  $postimageFinalize=Invoke-Finalize $postimageAction (@($postimageAction.Results)+$actualPost);Assert-ResolverSuccess $postimageFinalize 'postimageFinalize';Assert-True ($postimageFinalize.Code-eq0) 'source-transition-unique-real-postimage-accepted'

  $packageDriftPackage=New-Package 'package-drift' $policyPaths;$packageDriftAction=Start-Action 'package-drift' $policyPaths $packageDriftPackage;$policy.rules[0].requirementReason='Updated fixture source binding';Write-Json $policyPath $policy;$packageRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $packageDriftPackage;Write-Utf8 $packageDriftPackage ($packageRaw.TrimEnd("`n")+' ');$packageDriftRun=Invoke-Finalize $packageDriftAction (@($packageDriftAction.Results)+(Get-Postimages $policyPaths))
  Assert-True ($packageDriftRun.Code-ne0-and$packageDriftRun.Text.Contains('DISCOVER_SOURCE_DRIFT|authorizationIdentity')) 'source-transition-package-drift-rejected'
  Write-Utf8 $packageDriftPackage $packageRaw;$packageDriftFinalize=Invoke-Finalize $packageDriftAction (@($packageDriftAction.Results)+(Get-Postimages $policyPaths));Assert-ResolverSuccess $packageDriftFinalize 'packageDriftFinalize';Assert-True ($packageDriftFinalize.Code-eq0) 'source-transition-restored-package-finalizes'

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
  Assert-True ($invalidPolicyRun.Code-ne0-and($invalidPolicyRun.Text.Contains('SOURCE_POSTIMAGE_PROJECT_STANDARD_DRIFT')-or$invalidPolicyRun.Text.Contains('CONTENT_IDENTITY_DRIFT'))) 'invalid-new-policy-source-binding-rejected'
  Write-Utf8 $policyPath $validPolicyRaw;$policy=Get-Content -Raw -Encoding utf8 -LiteralPath $policyPath|ConvertFrom-Json

  $budgetPackage=New-Package 'invalid-policy-budget' $policyPaths;$budgetAction=Start-Action 'invalid-policy-budget' $policyPaths $budgetPackage;$policy|Add-Member -NotePropertyName selectedRulePackBytes -NotePropertyValue 1;Write-Json $policyPath $policy;$budgetRun=Invoke-Finalize $budgetAction (@($budgetAction.Results)+(Get-Postimages $policyPaths))
  Assert-True ($budgetRun.Code-ne0-and($budgetRun.Text.Contains('PROCESS_POLICY_FIELDS')-or$budgetRun.Text.Contains('FORMAT_CURRENT_VALIDATION_FAILED'))) 'legacy-budget-field-is-not-a-current-policy-field'
  $policy.rules[0].requirementReason='Updated fixture source binding';Write-Json $policyPath $policy

  $policy.PSObject.Properties.Remove('selectedRulePackBytes');$policy.rules=@();Write-Json $policyPath $policy
  $bootstrapPath=Join-Path $control 'BOOTSTRAP.md'
  $bootstrapBefore=Get-Content -LiteralPath $bootstrapPath -Raw
  Write-Utf8 $bootstrapPath ('Managed entry'+[char]10+'<!-- PROJECT-CUSTOM:BEGIN -->'+[char]10+'Preserve project review evidence.'+[char]10+'<!-- PROJECT-CUSTOM:END -->')
  $customBefore=[IO.File]::ReadAllBytes($bootstrapPath);$policyBefore=[IO.File]::ReadAllBytes($policyPath)
  $customScopePackage=New-Package 'policy-only-custom-drift' $policyPaths
  $customScopeAction=Start-Action 'policy-only-custom-drift' $policyPaths $customScopePackage
  $customReceipt=Get-Content -LiteralPath $customScopeAction.ReceiptPath -Raw|ConvertFrom-Json
  Assert-True ($customScopeAction.Discover.Code-eq0-and$customScopeAction.Admit.Code-eq0-and$null-ne$customReceipt.sourceBindings.PSObject.Properties['bootstrapManagedIdentity']-and'.ai-workspace/BOOTSTRAP.md'-cnotin@($customReceipt.binding.exactScope)) 'R1-policy-only-real-admission-has-new-managed-binding'
  $policy|Add-Member -Force -NotePropertyName facetVocabulary -NotePropertyValue @();Write-Json $policyPath $policy
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
  Assert-ResolverSuccess $migrationFinal 'migrationFinal';Assert-True ($migrationFinal.Code-eq0-and'projectCustomIdentity'-cin@($migrationFinal.Value.sourcePostimageTransition.changedBindings)) 'bootstrap-to-policy-original-finalize-succeeds'
  # Reusing the original admission must not mask a third-party managed-region edit.
  Write-Utf8 $bootstrapPath ('Changed managed entry'+[char]10+$migratedBootstrap)
  $managedDrift=Invoke-Finalize $migrationAction (@($migrationAction.Results)+(Get-Postimages $migrationPaths))
  Assert-True ($managedDrift.Code-ne0-and$managedDrift.Text.Contains('bootstrapManagedIdentity')) 'bootstrap-managed-third-party-drift-rejected'
  Write-Utf8 $bootstrapPath $migratedBootstrap

  # Recover an already-admitted action after one live source write, with no
  # historical transaction record. The recovery record is created now.
  $recoveryRuntime=Join-Path $control 'runtime/SOURCE-POSTIMAGE-001/executor-fixture/recovery-material'
  New-Item -ItemType Directory -Path $recoveryRuntime -Force|Out-Null
  $policy.PSObject.Properties.Remove('selectedRulePackBytes');$policy.rules=@();Write-Json $policyPath $policy
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

  # Real root lifecycle consumer, with a sealed runtime only inside this fixture.
  $rootScripts=Join-Path $frameworkRoot 'scripts';New-Item -ItemType Directory -Path $rootScripts -Force|Out-Null
  foreach($name in @('ProjectCorrectionLifecycle.psm1','ProjectAdoptionState.psm1','ProjectAdoptionProjection.psm1','ProjectAdoptionTransaction.psm1','MaintenanceOverlay.psm1','upgrade-project.ps1')){Copy-Item -LiteralPath (Join-Path $sourceFrameworkRoot ('scripts/'+$name)) -Destination (Join-Path $rootScripts $name)}
  Import-Module (Join-Path $rootScripts 'ProjectCorrectionLifecycle.psm1') -Force
  $observationalPolicy=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100;$observationalPolicy|Add-Member -Force -NotePropertyName facetVocabulary -NotePropertyValue @();Write-Json $policyPath $observationalPolicy
  Write-Utf8 (Join-Path $project 'AGENTS.md') "# Independent base`n<!-- correction slot -->`n"
  Write-Utf8 (Join-Path $project 'settings.json') '{"owned":1,"independent":1}'
  $installation=[ordered]@{schemaVersion=1;correctionId='GROUP';decisionLocator='fixture:original-install';dependsOn=@();changes=@(
    [ordered]@{kind='TEXT';path='AGENTS.md';before='';after="Correction-owned delegation`n";prefix="# Independent base`n";suffix="<!-- correction slot -->"},
    [ordered]@{kind='TEXT';path='settings.json';before='1';after='2';prefix='"owned":';suffix=','},
    [ordered]@{kind='FILE';path='owned-helper.txt';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String($utf8.GetBytes('owned helper'))})}
  $lifePlan=[ordered]@{schemaVersion=1;operation='INSTALL';correctionId='GROUP';expectedCorrectionsIdentity=Get-Identity $correctionsPath;decisionLocator='fixture:install';forbiddenPaths=@('private/');record=(New-Correction GROUP 'Unique lifecycle group rule.' @('CONTROL_WRITE') @());installation=$installation;installationRelativePath='.ai-workspace/upgrade-recovery/corrections/GROUP/install/installation.json';transactionRelativePath='.ai-workspace/upgrade-recovery/corrections/GROUP/install/state.json';impact=[ordered]@{stoppedObligations=@();independentObligations=@('independent base');inFlightEffects=@();recovery='existing transaction rollback';semanticAssessment='isolated fixture with complete explicit ownership'}}
  $lifePlanPath=Join-Path $control 'lifecycle-plan.json';Write-Json $lifePlanPath $lifePlan
  function Invoke-LifecycleAction($Plan,[string]$Name){
    Write-Json $lifePlanPath $Plan
    $preview=Invoke-AiwCorrectionLifecycle $project $lifePlanPath (Get-Identity $lifePlanPath) 'source-postimage-fixture' '2.0.0'
    $paths=@($preview.projection.objects.path|Sort-Object)
    $pkg=New-Package $Name $paths;$action=Start-Action $Name $paths $pkg
    if($null-eq$action.Admit-or$action.Admit.Code-ne0){throw ('LIFECYCLE_ADMISSION|'+$action.Discover.Text)}
    $applied=@(& (Join-Path $rootScripts 'upgrade-project.ps1') -ProjectId 'source-postimage-fixture' -ToVersion '2.0.0' -RepositoryPath $project -ProjectCorrectionLifecyclePath $lifePlanPath -ExpectedProjectCorrectionLifecycleIdentity (Get-Identity $lifePlanPath) -CurrentProcessInputPath $boundaryPath -ExpectedCurrentProcessInputIdentity (Get-Identity $boundaryPath) -Apply)
    $final=Invoke-Finalize $action (@($action.Results)+(Get-Postimages $paths))
    Assert-ResolverSuccess $final 'LIFECYCLE_FINALIZE'
    return [pscustomobject]@{Apply=$applied[-1];Final=$final;Paths=$paths}
  }
  # A correction with no installation effects uses the ordinary history /
  # carrier path through the same public root entry and original FINALIZE.
  $noEffect=$lifePlan|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64
  $noEffect.correctionId='NO_EFFECT';$noEffect.record=New-Correction NO_EFFECT 'Bounded no-effect correction.' @('CONTROL_WRITE') @()
  $noEffect.installation.correctionId='NO_EFFECT';$noEffect.installation.changes=@()
  $noEffect.installationRelativePath='.ai-workspace/upgrade-recovery/corrections/NO_EFFECT/install/installation.json';$noEffect.transactionRelativePath='.ai-workspace/upgrade-recovery/corrections/NO_EFFECT/install/state.json'
  $ordinary=Invoke-LifecycleAction $noEffect 'lifecycle-no-effect'
  Assert-True ($ordinary.Apply.status-ceq'COMPLETE'-and-not$ordinary.Apply.transactionCreated-and-not(Test-Path -LiteralPath (Join-Path $project $noEffect.transactionRelativePath))-and(Test-Path -LiteralPath (Join-Path $project $noEffect.installationRelativePath))-and$ordinary.Final.Value.status-ceq'PASS') 'root-no-effect-correction-uses-history-carrier-and-original-finalize-without-journal'
  $lifePlan.expectedCorrectionsIdentity=Get-Identity $correctionsPath
  $installed=Invoke-LifecycleAction $lifePlan 'lifecycle-install'
  Assert-True ($installed.Apply.status-ceq'COMPLETE'-and$installed.Apply.transactionCreated-and(Test-Path -LiteralPath (Join-Path $project $lifePlan.transactionRelativePath))-and$installed.Final.Value.status-ceq'PASS'-and'projectAgentsIdentity'-cin@($installed.Final.Value.sourcePostimageTransition.changedBindings)) 'root-lifecycle-installs-complete-group-and-finalizes-agents-authority-change'
  Write-Utf8 (Join-Path $project 'AGENTS.md') (([IO.File]::ReadAllText((Join-Path $project 'AGENTS.md')))+"Later independent user decision`n")
  Write-Utf8 (Join-Path $project 'settings.json') '{"owned":2,"independent":9}'
  $lifePlan.operation='UNINSTALL';$lifePlan.expectedCorrectionsIdentity=Get-Identity $correctionsPath;$lifePlan.record='NOT_APPLICABLE';$lifePlan.installation='NOT_APPLICABLE';$lifePlan.installationRelativePath='NOT_APPLICABLE';$lifePlan.transactionRelativePath='.ai-workspace/upgrade-recovery/corrections/GROUP/uninstall/state.json'
  $uninstalled=Invoke-LifecycleAction $lifePlan 'lifecycle-uninstall'
  Assert-True ($uninstalled.Apply.status-ceq'COMPLETE'-and-not(Test-Path (Join-Path $project 'owned-helper.txt'))-and([IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))).Contains('Later independent user decision')-and-not([IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))).Contains('Correction-owned delegation')-and([IO.File]::ReadAllText((Join-Path $project 'settings.json'))).Contains('"owned":1,"independent":9')) 'root-lifecycle-uninstall-removes-owned-delegation-and-preserves-independent-user-config'
  $badPlan=$lifePlan|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badPlan.operation='INSTALL';$badPlan.correctionId='INVALID_GROUP';$badPlan.expectedCorrectionsIdentity=Get-Identity $correctionsPath;$badPlan.record=New-Correction INVALID_GROUP 'Invalid duplicate body.' @('CONTROL_WRITE') @()
  $currentCarrier=Get-Content $correctionsPath -Raw|ConvertFrom-Json;$activeRecord=@($currentCarrier.corrections|Where-Object{$null-eq$_.PSObject.Properties['lifecycle']})[0];$badPlan.record.effectiveRule=$activeRecord.effectiveRule
  $badPlan.installation=[pscustomobject]@{schemaVersion=1;correctionId='INVALID_GROUP';decisionLocator='fixture:bad';dependsOn=@();changes=@()};$badPlan.installationRelativePath='.ai-workspace/upgrade-recovery/corrections/INVALID_GROUP/install/installation.json';$badPlan.transactionRelativePath='.ai-workspace/upgrade-recovery/corrections/INVALID_GROUP/install/state.json'
  $beforeBad=Get-Identity $correctionsPath;$reason='';try{Invoke-LifecycleAction $badPlan 'lifecycle-invalid'|Out-Null}catch{$reason=$_.Exception.Message}
  Assert-True ($reason.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')-and(Get-Identity $correctionsPath)-ceq$beforeBad-and-not(Test-Path (Join-Path $project $badPlan.installationRelativePath))) 'root-lifecycle-invalid-composed-rules-roll-back-entire-installation'
}finally{
  if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$full=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));if(-not$full.StartsWith($tempRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-source-postimage-[a-f0-9]{32}$'){throw 'TEMP_CLEANUP_BOUNDARY'};Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $full -Recurse -Force}
}
Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=source-postimage-transition')
