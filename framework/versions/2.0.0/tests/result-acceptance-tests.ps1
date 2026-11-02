[CmdletBinding()]
param([ValidateSet('All','HistoricalInputs','QualityAssurance','QualityMaintenance')][string]$Group='All',[switch]$KeepFixture)
Import-Module (Join-Path $PSScriptRoot 'TestNativeOutput.psm1')
Initialize-AiwTestNativeOutput
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$versionRoot=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $versionRoot 'scripts/ResultEvidence.psm1') -Force
$utf8=[Text.UTF8Encoding]::new($false)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-result-evidence-'+[guid]::NewGuid().ToString('N'))
$savedLocation=(Get-Location).Path;$savedCurrent=[Environment]::CurrentDirectory
$script:passed=0;$script:serial=0;$completed=$false
function Put([string]$Relative,[string]$Text){$p=Join-Path $temp $Relative;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$Text,$utf8);return $p}
function Json([string]$Relative,$Value){return Put $Relative (($Value|ConvertTo-Json -Depth 70 -Compress)+"`n")}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Ref([string]$Relative){return [pscustomobject]@{path=$Relative;identity=(Id (Join-Path $temp $Relative))}}
function Clone($Value){return $Value|ConvertTo-Json -Depth 70 -Compress|ConvertFrom-Json -Depth 70}
function Good([scriptblock]$Action,[string]$Name){$null=& $Action;$script:passed++;Write-Output ('PASS|'+$Name)}
function True([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Bad([scriptblock]$Action,[string]$Reason,[string]$Name){$caught='';try{$null=& $Action}catch{$caught=$_.Exception.Message};if(-not$caught.Contains($Reason)){throw ('ASSERT|'+$Name+'|expected='+$Reason+'|actual='+$caught)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Typed($Value,[string]$Kind){$script:serial++;$path='.ai-workspace/reports/evidence-'+$script:serial+'.json';$null=Json $path $Value;$ref=Ref $path;$ref|Add-Member kind $Kind;return $ref}
function Record([string]$Actor='owner',[string]$Outcome='PASS'){
    return [pscustomobject]@{schemaVersion=1;taskId='EVIDENCE-001';actor=$Actor;candidateObjects=@($candidate);requirementsRef=$requirements;outcome=$Outcome;checks=@([pscustomobject]@{id='semantic';method='MODEL_JUDGMENT';outcome='PASS';reason='Read the actual document against its bound requirements; semantic judgment remains instruction-bound.';evidenceLocators=@($requirements)});evidenceLocators=@($requirements)}
}
function Package([string]$Actor='owner'){
    return [pscustomobject]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='EVIDENCE-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner';issuer='owner';issuerRole='TASK_OWNER';grantee=$Actor;bundle='RESULT_ACCEPT';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id $taskPath);actions=@('RESULT_ACCEPT');exactPaths=@($candidate.path);objectIdentities=@($candidate);invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Id $configPath)}
}
function Binding($Package){$Package|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=@($candidate);requirementsRef=$requirements;prerequisiteEvidenceRefs=@($self);reservedUserDecisionRefs=@()})}
function Stage([string]$Id,[string]$Kind,[string[]]$Dependencies,$Candidates,$Evidence){return [pscustomobject]@{id=$Id;kind=$Kind;requiredBy=$requirements;dependsOn=$Dependencies;candidateRef=@($Candidates);evidenceRefs=@($Evidence)}}
function Plan($Stages){return Get-AiwAcceptancePlan ('```aiw-acceptance-plan'+"`n"+([pscustomobject]@{schemaVersion=1;stages=@($Stages)}|ConvertTo-Json -Depth 50 -Compress)+"`n"+'```'+"`n")}
function Check-Package($Package){
    $path=Json '.ai-workspace/runtime/EVIDENCE-001/owner/package.json' $Package
    $lines=@(& (Join-Path $versionRoot 'scripts/check-authorization.ps1') -PackagePath $path -ObservedActor $Package.grantee -ObservedTaskId 'EVIDENCE-001' -ObservedOwner 'owner' -ObservedAction RESULT_ACCEPT -ObservedPath $candidate.path -ObservedIdentity ($candidate.path+'='+$candidate.identity) -TaskPath '.ai-workspace/tasks/active/EVIDENCE-001.md' -ExpectedTaskIdentity $Package.taskIdentity -ControllerControlPath '.ai-workspace/controller.json' 2>&1|ForEach-Object{[string]$_})
    return [pscustomobject]@{Code=$LASTEXITCODE;Text=($lines-join"`n")}
}
function Check-Card([string]$Text){
    $path=Put '.ai-workspace/tasks/active/phase-card.md' $Text
    $lines=@(& ([Environment]::ProcessPath) -NoProfile -NonInteractive -File (Join-Path $versionRoot 'scripts/check-task-card.ps1') -TaskPath $path -ObservedActualPath $candidate.path 2>&1|ForEach-Object{[string]$_})
    return [pscustomobject]@{Code=$LASTEXITCODE;Text=($lines-join"`n")}
}
function With-Plan([string]$Text,$Plan){return $Text+'```aiw-acceptance-plan'+"`n"+($Plan|ConvertTo-Json -Depth 70 -Compress)+"`n"+'```'+"`n"}
function Test-QualityAssuranceConsumers([string]$Root,[switch]$Maintenance){
    # Original public project operations, using synthetic package qualification
    # and host delivery only. The fixture never qualifies the real Source.
    Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
    Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1')
    $temp=if($Maintenance){Join-Path $Root 'workspace/CONTROL'}else{Join-Path $Root 'project'};[IO.Directory]::CreateDirectory($temp)|Out-Null
    $objectRoot=if($Maintenance){Join-Path $Root 'workspace/TARGET'}else{$temp}
    if($Maintenance){[IO.Directory]::CreateDirectory($objectRoot)|Out-Null;foreach($repo in @($temp,$objectRoot)){& git -C $repo init -q;if($LASTEXITCODE-ne0){throw 'QUALITY_MAINTENANCE_GIT_INIT'}}}
    [IO.File]::WriteAllText((Join-Path $objectRoot 'unchanged.md'),'Previously existing anonymous member.',$utf8)
    Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp
    $framework=Join-Path $Root 'runtime';$source=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
    $fixtureVersion=New-AiwTestMechanismFixture $source $framework (Join-Path $PSScriptRoot 'test-groups.json') -Maintenance
    $trace=Join-Path $Root 'actual-checker-calls.jsonl'
    $checkerModule=Join-Path $fixtureVersion 'scripts/AuthorizationCheck.psm1'
    $checkerText=[IO.File]::ReadAllText($checkerModule)
    $anchor='$outputs=[Collections.Generic.List[object]]::new();$code=0;$aiwPublicationScopeLease=$null'
    if($checkerText.Split($anchor).Count-ne2){throw 'QUALITY_CHECKER_TRACE_ANCHOR'}
    $hook="[IO.File]::AppendAllText('"+$trace.Replace("'","''")+"', (([ordered]@{action=@(`$ObservedAction);actor=`$ObservedActor;paths=@(`$ObservedPath);package=`$PackagePath;task=`$ExpectedTaskIdentity;continuation=`$ContinuationReceiptPath;parameters=`$PSBoundParameters}|ConvertTo-Json -Depth 30 -Compress)+[char]10))"+[char]10
    [IO.File]::WriteAllText($checkerModule,$checkerText.Replace($anchor,$hook+$anchor),$utf8)
    Set-AiwTestFixtureQualification $fixtureVersion -Candidate
    $integration=@(Import-Module (Join-Path $PSScriptRoot 'IntegrationFixture.psm1') -PassThru)[0]
    & $integration {param($r)$script:utf8=[Text.UTF8Encoding]::new($false);Seal-MaintenanceRuntimeFixture $r;$p=Join-Path $r 'PACKAGE_MANIFEST.json';$m=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -Depth 100;$m.provisional=$true;$m.distributionId='2.0.0-snapshot.999';Write-Utf8 $p ($m|ConvertTo-Json -Depth 100)} $framework
    $taskRelative='.ai-workspace/tasks/active/EVIDENCE-001.md';$taskPath=Join-Path $temp $taskRelative
    $baseCard="# EVIDENCE-001 — anonymous quality result`n- Task schema: 2.0.0`n- Profile: CRITICAL; reason=quality policy fixture`n- Owner: owner`n- Work route: actor=owner; role=TASK_OWNER; phase=IMPLEMENT`n- Status: ACTIVE`n- Phase gate: FALSE`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=result.md; expected_paths=[result.md]; actual_paths=[result.md]`n"
    $initial=Join-Path $Root 'initial-task.md';[IO.File]::WriteAllText($initial,$baseCard,$utf8)
    function QNative([string]$Entry,[string[]]$Arguments,[string]$Name){
        $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) (@('-NoProfile','-NonInteractive','-File',$Entry)+$Arguments) -WorkingDirectory $temp -GroupId 'result-quality'
        $null=Put ('.ai-workspace/runtime/EVIDENCE-001/owner/'+$Name+'-raw.txt') ($run.Output-join"`n")
        $null=Json ('.ai-workspace/runtime/EVIDENCE-001/owner/'+$Name+'-command.json') ([pscustomobject]@{entry=$Entry;arguments=$Arguments;exitCode=$run.Code})
        return $run
    }
    $registerArgs=@('-ProjectId','quality-fixture','-DisplayName','Anonymous quality fixture','-RepositoryPath',$temp,'-FrameworkVersion','2.0.0','-ControllerId','owner','-WorkspaceRoot',$framework,'-LocalCandidatePilot','-InitialTaskPath',$initial,'-ExpectedInitialTaskIdentity',(Id $initial),'-InitialTaskRelativePath',$taskRelative,'-Apply')
    if($Maintenance){$registerArgs+=@('-ControlPlaneLayout','framework-maintenance-sibling','-FrameworkTargetRepositoryId','ai-workspace-framework','-FrameworkTargetSiblingDirectory','TARGET')}
    $registered=QNative (Join-Path $framework 'scripts/register-project.ps1') $registerArgs 'register'
    if($registered.Code-ne0){throw ('QUALITY_REGISTER|'+($registered.Output-join"`n"))}
    True ([IO.File]::Exists($taskPath)) 'quality-anonymous-candidate-actually-registered-with-original-task'
    $configPath=Join-Path $temp '.ai-workspace/project.json';$policyPath=Join-Path $temp '.ai-workspace/process-policy.json'
    function QProduct([string]$Text){[IO.File]::WriteAllText((Join-Path $objectRoot 'result.md'),$Text,$utf8);[pscustomobject]@{path='result.md';identity=(Id (Join-Path $objectRoot 'result.md'))}}
    $candidate=QProduct 'Before anonymous production.'
    $null=Put 'requirements.md' 'The anonymous result must contain the approved sentence. No independent review is required for the first selected SELF/accept case.';$requirements=Ref 'requirements.md'
    $ctx=if($Maintenance){New-AiwPackageEvidenceContext $temp ([pscustomobject]@{schemaVersion=2;repositoryId='ai-workspace-framework'}) $framework -TaskPath $taskRelative}else{New-AiwEvidenceContext $temp '' $framework}
    $runtime='.ai-workspace/runtime/EVIDENCE-001/owner/';$serial=0
    function QPackage([string]$Action,[string[]]$Paths,[string]$Actor='owner',$Quality=$null){
        $text=[IO.File]::ReadAllText($taskPath);$profile=[regex]::Match($text,'(?m)^- Range summary: profile=(MICRO|STANDARD|CRITICAL);').Groups[1].Value
        $repositoryRoot=if($Maintenance-and$Action-cne'CONTROL_WRITE'){$objectRoot}else{$temp}
        $p=[pscustomobject]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='EVIDENCE-001';profile=$profile;lifecycle='ACTIVE';owner='owner';issuer='owner';issuerRole='TASK_OWNER';grantee=$Actor;bundle='quality-'+$Action;decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id $taskPath);actions=@($Action);exactPaths=$Paths;objectIdentities=@(foreach($path in $Paths){$full=Join-Path $repositoryRoot $path;[pscustomobject]@{path=$path;identity=$(if([IO.File]::Exists($full)){Id $full}else{'NEW'})}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Id $configPath)}
        if($Maintenance){$p.schemaVersion=2;$p|Add-Member repositoryId $(if($Action-ceq'CONTROL_WRITE'){'CONTROL'}else{'ai-workspace-framework'});$p.invalidatesOn+=@('REPOSITORY_CHANGE')}
        if($null-ne$Quality){$p|Add-Member qualityBinding (Clone $Quality)}
        return $p
    }
    function QProcess($Value,[string]$Name,[string]$Signal=''){
        $path=Json ($runtime+$Name+'.json') $Value
        $entry=if($Maintenance){Join-Path $framework 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'}
        $run=QNative $entry @('-InputPath',$path,'-AsJson') $Name
        $raw=$run.Output-join"`n";$valueOut=$null;try{$valueOut=$raw|ConvertFrom-Json -Depth 100}catch{}
        if($Signal){True ($run.Code-ne0-and$raw.Contains($Signal)) ($Name+'|'+$Signal)}elseif($run.Code-ne0-or$null-eq$valueOut-or$valueOut.status-cne'PASS'){throw ('QUALITY_PROCESS|'+$Name+'|'+$raw)}
        $result=Json ($runtime+$Name+'-result.json') $valueOut
        [pscustomobject]@{value=$valueOut;input=$Value;inputPath=$path;resultPath=$result;pair=[pscustomobject]@{inputRef=[pscustomobject]@{path=$path;identity=(Id $path)};resultRef=[pscustomobject]@{path=$result;identity=(Id $result)}}}
    }
    function QStart($Package,[string]$Name,[string]$ObservedAction='',[string]$Continuation=''){
        $packagePath=if($Continuation){$c=Get-Content -LiteralPath $Continuation -Raw|ConvertFrom-Json -Depth 100;$s=Get-Content -LiteralPath $c.sourceDiscoverReceiptPath -Raw|ConvertFrom-Json -Depth 100;$s.sourceLocators.authorizationPackagePath}else{Json ($runtime+$Name+'-package.json') $Package}
        $act=if($ObservedAction){$ObservedAction}else{$Package.actions[0]};$result=switch($act){REVIEW_ROUTE{'HANDOFF'};REVIEW_EXECUTE{'REVIEW_VERDICT'};RESULT_ACCEPT{'RESULT_ACCEPTANCE'};TEST_RUN{'TEST_RESULT'};default{'IMPLEMENTATION_RESULT'}}
        $work=switch($act){REVIEW_ROUTE{'aiw:review'};REVIEW_EXECUTE{'aiw:review'};RESULT_ACCEPT{'aiw:acceptance'};TEST_RUN{'aiw:verification'};default{'aiw:implementation'}}
        $i=[pscustomobject]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=@{mode='FULL'};projectRoot=$temp;frameworkRoot=$framework;taskPath=$taskPath;expectedProjectConfigIdentity=(Id $configPath);expectedCorrectionsIdentity=(Id (Join-Path $temp '.ai-workspace/corrections.json'));expectedTaskIdentity=(Id $taskPath);observedActor=$Package.grantee;capabilities=@();exactPaths=$Package.exactPaths;forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Id $packagePath);userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=@{schemaVersion=2;objective='Validate original anonymous quality policy and result consumers';requestedActionKind=$act;requestedResultKind=$result;semanticHints=@();pathHints=$Package.exactPaths;capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:software')};workType=@{state='KNOWN';values=@($work)};deliverableType=@{state='KNOWN';values=@('aiw:code')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}}
        if($Continuation){$i|Add-Member continuationReceiptPath $Continuation;$i|Add-Member expectedContinuationReceiptIdentity (Id $Continuation)}
        $d=QProcess $i ($Name+'-discover');$compact=Json ($runtime+$Name+'-compact.json') $d.value.compactReceipt
        $b=[pscustomobject]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compact;expectedDiscoverReceiptIdentity=(Id $compact);preparationReceipts=@($d.value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
        [pscustomobject]@{package=$Package;packagePath=$packagePath;receipt=$d.value.compactReceipt;compact=$compact;boundary=$b;name=$Name}
    }
    function QFinish($Action,$Evidence=@(),$ExtraPreparation=@(),$ExtraResult=@(),$Delivery=$null){
        $f=Clone $Action.boundary;$f.mode='FINALIZE_OUTPUT';$f.evidenceRefs=@($Evidence);$f.preparationReceipts+=@($ExtraPreparation)
        $repositoryRoot=if($Maintenance-and$Action.package.repositoryId-cne'CONTROL'){$objectRoot}else{$temp}
        $f.resultReceipts=@(@($Action.receipt.selectedObligations|ForEach-Object{$_.resultRequirements})+@($ExtraResult)+@(foreach($p in $Action.package.exactPaths){$full=Join-Path $repositoryRoot $p;'OBJECT_POSTIMAGE|'+$p+'|'+$(if([IO.File]::Exists($full)){Id $full}else{'MISSING'})})|Sort-Object -Unique)
        if($null-ne$Delivery){$f|Add-Member deliveryContext $Delivery -Force}
        QProcess $f ($Action.name+'-finalize')
    }
    function QCard($Plan,[string]$Name,[string]$Text=$baseCard,[switch]$Archive){
        $archiveRelative='.ai-workspace/tasks/archive/EVIDENCE-001.md'
        $paths=if($Archive){@($taskRelative,$archiveRelative)}else{@($taskRelative)}
        $a=QStart (QPackage CONTROL_WRITE $paths) $Name;$null=QProcess $a.boundary ($Name+'-admit')
        $textOut=if($null-eq$Plan){$Text}else{With-Plan $Text $Plan}
        if($Archive){
            $archivePath=Put $archiveRelative $textOut
            if([IO.File]::ReadAllText($archivePath)-cne$textOut){throw 'QUALITY_ARCHIVE_READBACK'}
            $checkerWrapper=Put ($runtime+'archive-card-check.ps1') 'param([string]$Entry,[string]$Task,[string]$PathsJson); $paths=Get-Content -LiteralPath $PathsJson -Raw|ConvertFrom-Json; & $Entry -TaskPath $Task -ObservedActualPath ([string[]]@($paths)); exit $LASTEXITCODE'
            $pathsJson=Json ($runtime+'archive-card-paths.json') $Plan.qualityBinding.subject.exactPaths
            $checked=QNative $checkerWrapper @('-Entry',(Join-Path $fixtureVersion 'scripts/check-task-card.ps1'),'-Task',$archivePath,'-PathsJson',$pathsJson) 'archive-card-check'
            if($checked.Code-ne0){throw ('QUALITY_ARCHIVE_CARD|'+($checked.Output-join"`n"))}
            $original=@($a.package.objectIdentities|Where-Object path -CEQ $taskRelative)[0]
            if((Id $taskPath)-cne$original.identity){throw 'QUALITY_ARCHIVE_ACTIVE_DRIFT'}
            [IO.File]::Delete($taskPath)
        }else{$null=Put $taskRelative $textOut}
        $null=QFinish $a
    }
    function QPolicy($Policy,[string]$Name){
        $a=QStart (QPackage CONTROL_WRITE @('.ai-workspace/process-policy.json')) $Name
        $nextConfig=Put ($runtime+$Name+'-config-postimage.json') ([IO.File]::ReadAllText($configPath));$beforeConfig=Id $configPath
        $nextPolicy=Json ($runtime+$Name+'-policy-postimage.json') $Policy;$decision=Put ($runtime+$Name+'-decision.md') 'Original anonymous source-maintenance decision: enable the specified finite quality policy.'
        $composer=@(Import-Module (Join-Path $fixtureVersion 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
        $prepared=& $composer.ExportedCommands['New-AiwProjectSourceChangePreparation'] -DiscoverReceiptPath $a.compact -ExpectedDiscoverReceiptIdentity (Id $a.compact) -ConfigPostimagePath $nextConfig -PolicyPostimagePath $nextPolicy -DecisionRef ([pscustomobject]@{path=$decision;identity=(Id $decision)}) -OutputDirectory (Join-Path $temp ($runtime+$Name+'-prepared'))
        $a.boundary.preparationReceipts=@($a.boundary.preparationReceipts+$prepared.preparationRequirements|Sort-Object -Unique)+@($prepared.preparationReceipt)
        $admitted=QProcess $a.boundary ($Name+'-admit')
        [IO.File]::WriteAllBytes($policyPath,[IO.File]::ReadAllBytes($nextPolicy))
        $token='PROJECT_SOURCE_ADMISSION|'+$admitted.inputPath+'|'+(Id $admitted.inputPath)+'|'+$admitted.resultPath+'|'+(Id $admitted.resultPath)
        $f=QFinish $a @() @($token) @($prepared.resultRequirements)
        True ($f.value.projectSourcePreparation.outcome-ceq'COMPLETED'-and(Id $configPath)-ceq$beforeConfig) ($Name+'-real-source-adoption-without-companion-write')
    }
    function QPrepare($Subject,[string]$Name){
        $request=[pscustomobject]@{operation='QUALITY_PLAN_PREPARE';schemaVersion=1;projectRoot=$temp;taskPath=$taskPath;expectedTaskIdentity=(Id $taskPath);projectConfigRef=[pscustomobject]@{path='.ai-workspace/project.json';identity=(Id $configPath)};policyRef=[pscustomobject]@{path='.ai-workspace/process-policy.json';identity=(Id $policyPath)};subject=$Subject;requirementsRef=$requirements}
        $path=Json ($runtime+$Name+'.json') $request;$run=QNative (Join-Path $fixtureVersion 'scripts/resolve-workflow-route.ps1') @('-InputPath',$path,'-AsJson') $Name
        if($run.Code-ne0){throw ('QUALITY_PREPARE|'+($run.Output-join"`n"))};$answer=($run.Output-join"`n")|ConvertFrom-Json -Depth 100;$null=Json ($runtime+$Name+'-result.json') $answer;return $answer
    }
    $subject=[pscustomobject]@{repositoryId=$(if($Maintenance){'ai-workspace-framework'}else{'REPO_LOCAL'});exactPaths=@('result.md');facets=[pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=@('aiw:software')};deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:code')}}}
    $legacy=QPrepare $subject 'legacy-prepare';True ($legacy.mode-ceq'LEGACY'-and-not$legacy.authorityGranted-and$null-eq$legacy.plan) 'quality-unenabled-project-remains-legacy'
    True (Test-AiwPackageReviewRequired (QPackage RESULT_ACCEPT @('result.md'))) 'quality-legacy-critical-retains-independent-review'
    $policy=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
    $policy|Add-Member qualityAssurance ([pscustomobject]@{schemaVersion=1;defaultStages=@('RESULT_ACCEPT','SELF_CHECK')})
    QPolicy $policy 'enable-self-accept'
    $prepared=QPrepare $subject 'prepare-self-accept';True (($prepared.effectiveStages-join'|')-ceq'SELF_CHECK|RESULT_ACCEPT'-and-not$prepared.authorityGranted) 'quality-one-preparation-fixed-order-no-review-implication'
    $plan=Clone $prepared.plan
    $noPlan=QPackage SOURCE_WRITE @('result.md');$ev=(Get-Command Get-AiwPackageQuality).Module
    Bad {Get-AiwPackageQuality $ctx $noPlan $null} 'QUALITY_PLAN_REQUIRED' 'quality-enabled-ordinary-production-needs-plan'
    QCard $plan 'bind-initial-plan'
    Bad {Assert-AiwReviewSelfCheck $ctx @() EVIDENCE-001 @($candidate) $plan} 'REVIEW_SELF_CHECK_REQUIRED' 'quality-selected-self-remains-required'
    $production=QStart (QPackage SOURCE_WRITE @('result.md') owner $plan.qualityBinding) 'produce-self'
    # Public ADMIT reobserves a post-DISCOVER candidate; restoring original
    # bytes afterwards does not erase the recorded refusal.
    $originalProduct=[IO.File]::ReadAllBytes((Join-Path $objectRoot 'result.md'))
    $null=QProduct 'Unapproved post-DISCOVER drift.'
    $null=QProcess $production.boundary 'produce-self-drift-admit' 'OBJECT_DRIFT'
    [IO.File]::WriteAllBytes((Join-Path $objectRoot 'result.md'),$originalProduct)
    $beforeCount=if([IO.File]::Exists($trace)){@(Get-Content -LiteralPath $trace).Count}else{0}
    $null=QProcess $production.boundary 'produce-self-admit'
    $afterCount=@(Get-Content -LiteralPath $trace).Count
    True ($afterCount-gt$beforeCount) 'quality-A-repo-local-ADMIT-invokes-real-checker-without-outer-checker'
    $null=Json ($runtime+'actual-admit-checker-count.json') ([pscustomobject]@{before=$beforeCount;after=$afterCount;delta=($afterCount-$beforeCount);tracePath=$trace;outerStandaloneCheckerCalls=0;sourceQualification='SYNTHETIC_TEST_FIXTURE_ONLY'})
    if(-not$Maintenance){
        # Observe the actual ADMIT invocation. Refusal probes below use the
        # public checker; they do not claim to call an unreachable private helper.
        $forwarded=(Get-Content -LiteralPath $trace -Tail 1|ConvertFrom-Json -Depth 50).parameters
        True ($forwarded.PackagePath-ceq$production.packagePath-and$forwarded.ObservedActor-ceq'owner'-and$forwarded.ObservedTaskId-ceq'EVIDENCE-001'-and$forwarded.ObservedOwner-ceq'owner'-and($forwarded.ObservedAction-join'|')-ceq'SOURCE_WRITE'-and($forwarded.ObservedPath-join'|')-ceq'result.md'-and($forwarded.ObservedIdentity-join'|')-ceq('result.md='+$production.package.objectIdentities[0].identity)-and$forwarded.ObservedRepositoryId-ceq'REPO_LOCAL'-and$forwarded.ProjectConfigPath-ceq'.ai-workspace/project.json'-and$forwarded.ExpectedProjectConfigIdentity-ceq(Id $configPath)-and$forwarded.TaskPath-ceq$taskRelative-and$forwarded.ExpectedTaskIdentity-ceq(Id $taskPath)-and$forwarded.ControllerControlPath-ceq'.ai-workspace/controller.json') 'quality-A-actual-ADMIT-forwards-complete-current-checker-binding'
        foreach($case in @('actor','path','continuation')){
            $actor=if($case-ceq'actor'){'imposter'}else{'owner'};$path=if($case-ceq'path'){'other.md'}else{'result.md'}
            $arguments=@('-PackagePath',$production.packagePath,'-ObservedActor',$actor,'-ObservedTaskId','EVIDENCE-001','-ObservedOwner','owner','-ObservedAction','SOURCE_WRITE','-ObservedPath',$path,'-ObservedIdentity',($path+'='+$production.package.objectIdentities[0].identity),'-ObservedRepositoryId','REPO_LOCAL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',(Id $configPath),'-TaskPath',$taskRelative,'-ExpectedTaskIdentity',(Id $taskPath),'-ControllerControlPath','.ai-workspace/controller.json')
            if($case-ceq'continuation'){$arguments+=@('-ContinuationReceiptPath',(Join-Path $temp 'missing-continuation.json'),'-ExpectedContinuationReceiptIdentity',('1|'+('A'*64)))}
            $refusal=QNative (Join-Path $fixtureVersion 'scripts/check-authorization.ps1') $arguments ('public-checker-negative-'+$case)
            $reason=switch($case){actor{'GRANTEE_DRIFT'};path{'OBSERVED_PATH_OUTSIDE_EXACT'};continuation{'CONTINUATION_PLAN_REQUIRED'}}
            True ($refusal.Code-ne0-and($refusal.Output-join"`n").Contains($reason)) ('quality-A-original-public-checker-refuses-'+$case)
        }
        $packageBytes=[IO.File]::ReadAllBytes($production.packagePath)
        try{$withdrawn=Clone $production.package;$withdrawn.userConfirmation=('1|'+('A'*64));[IO.File]::WriteAllText($production.packagePath,($withdrawn|ConvertTo-Json -Depth 100 -Compress),$utf8);$null=QProcess $production.boundary 'changed-decision-package-admit' 'DISCOVER_SOURCE_DRIFT|authorizationIdentity'}finally{[IO.File]::WriteAllBytes($production.packagePath,$packageBytes)}
        $read=Get-Content -LiteralPath (Join-Path $temp ($runtime+'produce-self-discover.json')) -Raw|ConvertFrom-Json -Depth 100
        $read.authorizationPackagePath='NOT_REQUIRED';$read.expectedAuthorizationIdentity='NOT_REQUIRED';$read.exactPaths=@();$read.intentEnvelope.pathHints=@();$read.intentEnvelope.requestedActionKind='NONE';$read.intentEnvelope.requestedResultKind='USER_RESPONSE';$read.intentEnvelope.facets.workType.values=@('aiw:planning');$read.intentEnvelope.facets.deliverableType.values=@('aiw:message');$read.intentEnvelope.facets.stage.values=@('aiw:planning')
        $readD=QProcess $read 'ordinary-user-read-discover'
        True (-not[IO.File]::Exists((Join-Path $temp ($runtime+'ordinary-user-read-finalize.json')))) 'quality-B-ordinary-NONE-current-user-has-no-fabricated-finalize'
        $readCompact=Json ($runtime+'ordinary-user-read-compact.json') $readD.value.compactReceipt
        $explicit=Clone $production.boundary;$explicit.mode='FINALIZE_OUTPUT';$explicit.discoverReceiptPath=$readCompact;$explicit.expectedDiscoverReceiptIdentity=Id $readCompact;$explicit.preparationReceipts=@();$explicit.resultReceipts=@()
        $blockedOutputs=@(QProcess $explicit 'explicit-incomplete-read-finalize' 'PREPARATION_INCOMPLETE')
        $blocked=$blockedOutputs[-1]
        $blockedCommand=Get-Content -LiteralPath (Join-Path $temp ($runtime+'explicit-incomplete-read-finalize-command.json')) -Raw|ConvertFrom-Json -Depth 100
        True ($blockedCommand.exitCode-eq3-and$blocked.value.status-ceq'BLOCKED'-and$blocked.value.reason-ceq'PREPARATION_INCOMPLETE'-and$blocked.value.missingPreparation.Count-gt0-and$blocked.value.missingResult.Count-gt0) 'quality-B-explicit-incomplete-F-remains-strictly-blocked'
    }
    $candidate=QProduct 'The approved anonymous sentence.'
    $self=Typed (Record owner) SELF_CHECK;$produced=QFinish $production @($self)
    $plan.stages[0].candidateRef=@($candidate);$plan.stages[0].evidenceRefs=@($self);$plan.stages[1].candidateRef=@($candidate)
    QCard $plan 'bind-self-evidence'
    $accept=QPackage RESULT_ACCEPT @('result.md') owner $plan.qualityBinding
    $accept|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=@($candidate);requirementsRef=$requirements;prerequisiteEvidenceRefs=@($self);reservedUserDecisionRefs=@()})
    $acceptAction=QStart $accept 'accept-without-review';$null=QProcess $acceptAction.boundary 'accept-without-review-admit'
    $acceptedRecord=Record owner ACCEPTED;$acceptedRecord|Add-Member authorizationRef ([pscustomobject]@{path=$acceptAction.packagePath;identity=(Id $acceptAction.packagePath)});$acceptedRecord|Add-Member acceptedCommit ('C'*40)
    $accepted=Typed $acceptedRecord RESULT_ACCEPTANCE
    $nativeDelivery=[pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
    $acceptedF=QFinish $acceptAction @($accepted) @() @() $nativeDelivery
    True ($acceptedF.value.status-ceq'PASS') 'quality-critical-self-and-accept-complete-without-independent-review'
    $plan.stages[1].evidenceRefs=@($accepted)
    $historical=[pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($acceptedF.pair,$produced.pair)}
    $plan.stages[1]|Add-Member evidenceConsumption $historical
    QCard $plan 'bind-accepted-evidence'
    $pushContext=New-AiwPackageEvidenceContext $temp $accept $framework -TaskPath $taskRelative
    Good {Assert-AiwPushAcceptance $pushContext $accepted EVIDENCE-001 @($candidate) ('C'*40)} 'quality-push-evidence-consumer-uses-original-no-review-acceptance'
    Bad {Assert-AiwPushAcceptance $pushContext $accepted EVIDENCE-001 @($candidate) ('D'*40)} 'PUSH_ACCEPTED_COMMIT_DRIFT' 'quality-push-evidence-consumer-rejects-wrong-commit'
    True (-not(Test-AiwPackageReviewRequired $accept)-and(Test-AiwPackageReviewRequired $accept -ExplicitRequirement)) 'quality-selected-no-review-preserves-explicit-dedicated-review-requirement'
    if($Maintenance){
        $rootFacts=QNative (Join-Path $framework 'scripts/resolve-framework-maintenance-target.ps1') @('-ControlRepositoryPath',$temp,'-ExpectedProjectConfigIdentity',(Id $configPath),'-AsJson') 'root-resolver-quality'
        True ($rootFacts.Code-eq0-and($rootFacts.Output-join"`n").Contains('ai-workspace-framework')) 'quality-maintenance-root-resolver-valid-extension-reaches-both-repositories'
        $policyBytes=[IO.File]::ReadAllBytes($policyPath)
        foreach($case in @('unknown','version','noninteger','null','duplicate','unknown-stage')){
            $invalid=Get-Content -LiteralPath $policyPath -Raw|ConvertFrom-Json -Depth 100
            switch($case){unknown{$invalid.qualityAssurance|Add-Member extra $true} version{$invalid.qualityAssurance.schemaVersion=2} noninteger{$invalid.qualityAssurance.schemaVersion=[double]1.0} null{$invalid.qualityAssurance=$null} duplicate{$invalid.qualityAssurance.defaultStages=@('SELF_CHECK','SELF_CHECK')} unknown-stage{$invalid.qualityAssurance.defaultStages=@('UNKNOWN')}}
            try{
                [IO.File]::WriteAllText($policyPath,($invalid|ConvertTo-Json -Depth 100 -Compress),$utf8)
                $negative=QNative (Join-Path $framework 'scripts/resolve-framework-maintenance-target.ps1') @('-ControlRepositoryPath',$temp,'-ExpectedProjectConfigIdentity',(Id $configPath),'-AsJson') ('root-quality-negative-'+$case)
                True ($negative.Code-ne0-and($negative.Output-join"`n").Contains('PROCESS_POLICY_QUALITY_INVALID')) ('quality-maintenance-root-strict-'+$case)
            }finally{[IO.File]::WriteAllBytes($policyPath,$policyBytes)}
        }
        QCard $null 'root-clear-plan-negative'
        foreach($repo in @('CONTROL','ai-workspace-framework')){
            $path=if($repo-ceq'CONTROL'){'.ai-workspace/reports/ordinary.txt'}else{'result.md'}
            if($repo-ceq'CONTROL'){$null=Put $path 'An ordinary report is not management metadata.'}
            $pkg=QPackage $(if($repo-ceq'CONTROL'){'CONTROL_WRITE'}else{'SOURCE_WRITE'}) @($path)
            $pkgPath=Json ($runtime+'missing-plan-'+$repo+'-package.json') $pkg
            $checked=QNative (Join-Path $framework 'scripts/check-framework-maintenance-authorization.ps1') @('-ControlRepositoryPath',$temp,'-PackagePath',$pkgPath,'-ObservedActor','owner','-ObservedTaskId','EVIDENCE-001','-ObservedOwner','owner','-ObservedAction',$pkg.actions[0],'-ObservedPath',$path,'-ObservedIdentity',($path+'='+$pkg.objectIdentities[0].identity),'-ObservedRepositoryId',$repo,'-ExpectedProjectConfigIdentity',(Id $configPath),'-TaskPath',$taskRelative,'-ExpectedTaskIdentity',(Id $taskPath)) ('missing-plan-'+$repo)
            True ($checked.Code-ne0-and($checked.Output-join"`n").Contains('QUALITY_PLAN_REQUIRED')-and-not($checked.Output-join"`n").Contains('PROCESS_POLICY_FIELDS')) ('quality-maintenance-'+$repo+'-checker-reaches-quality-plan-required')
        }
        QCard $plan 'root-restore-plan'
        Write-Output ('FIXTURE|'+$Root+'|scope=maintenance-root-quality|qualification=SYNTHETIC_TEST_FIXTURE_ONLY');return
    }
    # Stable matcher, strict shapes and current drift: fault copies do not mutate
    # live authority. The successful production chains above stay immutable.
    $stableRule=[pscustomobject]@{ruleId='QUALITY_REVIEW';requirementReason='Review code results.';effectiveRule='Use independent review for code.';decisionLocator='requirements.md';selectors=[pscustomobject]@{profiles=@('STANDARD');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@('result.md');capabilities=@('*');semanticTerms=@();facets=[pscustomobject]@{domain=@('aiw:software');deliverableType=@('aiw:code')}};preparationRequirements=@();resultRequirements=@();qualityStages=@('RESULT_REVIEW')}
    $conditions=Clone $policy;$conditions.qualityAssurance.defaultStages=@();$conditions.rules+=@($stableRule)
    $selection=Get-AiwQualitySelection $conditions (Id $policyPath) STANDARD $subject
    True (($selection.effectiveStages-join'|')-ceq'RESULT_REVIEW') 'quality-standard-stable-condition-selects-review-without-self'
    # Direct acceptance-consumer unit probe using the actual selected projection;
    # current native authority is exercised by the separate registered flows.
    $conditionalAccept=Clone $accept;$conditionalAccept.profile='STANDARD';$conditionalAccept.qualityBinding=$selection.qualityBinding;$conditionalAccept.acceptanceBinding.prerequisiteEvidenceRefs=@()
    Bad {Assert-AiwAcceptanceBinding $ctx $conditionalAccept $null} 'RESULT_ACCEPT_CRITICAL_REVIEW_REQUIRED' 'quality-standard-condition-consumer-requires-selected-review-verdict'
    $other=Get-AiwQualitySelection $conditions (Id $policyPath) CRITICAL $subject
    True ($other.effectiveStages.Count-eq0) 'quality-explicit-zero-is-distinct-from-legacy'
    foreach($case in @('null','unknown','version','stage','duplicate','orphan','unstable','empty-rule')){
        $bad=Clone $conditions;$signal='QUALITY_'
        switch($case){
            null {$bad.qualityAssurance=$null}
            unknown {$bad.qualityAssurance|Add-Member extra $true}
            version {$bad.qualityAssurance.schemaVersion=2}
            stage {$bad.qualityAssurance.defaultStages=@('UNKNOWN')}
            duplicate {$bad.qualityAssurance.defaultStages=@('SELF_CHECK','SELF_CHECK')}
            orphan {$bad.PSObject.Properties.Remove('qualityAssurance')}
            unstable {$bad.rules[-1].selectors.phases=@('REVIEW')}
            empty-rule {$bad.rules[-1].qualityStages=@()}
        }
        Bad {Get-AiwQualitySelection $bad (Id $policyPath) STANDARD $subject} $signal ('quality-strict-'+$case)
    }
    $wrong=Clone $accept;$wrong.qualityBinding.subject.repositoryId='OTHER'
    Bad {Get-AiwPackageQuality $ctx $wrong $plan} 'QUALITY_BINDING_DRIFT' 'quality-current-package-subject-drift'
    $empty=Clone $plan;$empty.qualityBinding.effectiveStages=@();$empty.stages=@()
    Bad {Get-AiwPackageQuality $ctx $accept $empty} 'QUALITY_PLAN_DRIFT' 'quality-cannot-forge-zero-selection'
    $wideSubject=Clone $subject;$wideSubject.exactPaths+=@('unchanged.md')
    $wideBinding=(Get-AiwQualitySelection $policy (Id $policyPath) CRITICAL $wideSubject).qualityBinding
    $widePlan=Clone $plan;$widePlan.qualityBinding=$wideBinding
    $wideCandidates=@(Get-AiwCurrentCandidateReferences $ctx $wideSubject.exactPaths)
    foreach($stage in $widePlan.stages){$stage.candidateRef=$wideCandidates}
    $partial=Clone $accept;$partial.qualityBinding=$wideBinding
    Bad {Get-AiwPackageQuality $ctx $partial $widePlan} 'QUALITY_SUBJECT_INCOMPLETE' 'quality-acceptance-cannot-cover-only-part-of-declared-full-candidate'
    $partialWrite=QPackage SOURCE_WRITE @('result.md') owner $wideBinding
    Good {Get-AiwPackageQuality $ctx $partialWrite $widePlan} 'quality-production-M-may-be-a-subset-of-declared-A'
    $protectedContext=New-AiwEvidenceContext $temp $objectRoot $framework @() @('unchanged.md')
    Bad {Get-AiwPackageQuality $protectedContext $partialWrite $widePlan} 'EVIDENCE_PATH_FORBIDDEN' 'quality-full-subject-protection-applies-outside-production-M'
    $fullAccept=QPackage RESULT_ACCEPT $wideSubject.exactPaths owner $wideBinding
    $partialStage=Clone $widePlan;$partialStage.stages[0].candidateRef=@($candidate)
    Bad {Get-AiwPackageQuality $ctx $fullAccept $partialStage} 'QUALITY_STAGE_SUBJECT_INCOMPLETE' 'quality-filled-generic-stage-must-cover-full-A'
    $zeroRoot=Join-Path $Root 'zero-consumer-unit';[IO.Directory]::CreateDirectory((Join-Path $zeroRoot '.ai-workspace'))|Out-Null
    $zeroPolicy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='quality-fixture';rules=@();qualityAssurance=[pscustomobject]@{schemaVersion=1;defaultStages=@()}}
    $zeroPolicyPath=Join-Path $zeroRoot '.ai-workspace/process-policy.json';[IO.File]::WriteAllText($zeroPolicyPath,($zeroPolicy|ConvertTo-Json -Depth 50 -Compress),$utf8)
    $zeroBinding=(Get-AiwQualitySelection $zeroPolicy (Id $zeroPolicyPath) CRITICAL $subject).qualityBinding
    $zeroPlan=[pscustomobject]@{schemaVersion=2;qualityBinding=$zeroBinding;stages=@()}
    $zeroContext=New-AiwEvidenceContext $zeroRoot '' $framework
    [IO.File]::WriteAllBytes((Join-Path $zeroRoot 'requirements.md'),[IO.File]::ReadAllBytes((Join-Path $temp 'requirements.md')))
    [IO.File]::WriteAllText((Join-Path $zeroRoot 'result.md'),'An explicitly unverified anonymous unit result.',$utf8)
    $zeroClosed=$baseCard.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;').Replace('- Status: ACTIVE','- Status: CLOSED')+"- Writer / reviewer / authorization: NONE / NONE / NONE`n- Closure outcome: SUCCESS`n- Closure evidence: Explicitly unverified anonymous unit result; zero generic stages selected.`n- Remaining obligations: NONE`n- Artifact disposition: Unit fixture only; no SELF, verdict or acceptance created.`n"
    $zeroClosed+="- Closure basis: Actual explicitly unverified fixture result and selected zero generic stages.`n- Output disposition: result.md retained as unit fixture.`n- Git disposition: DEFERRED; fixture only.`n- Unresolved obligations: NONE`n- Writer: RELEASED`n- Reviewer: RELEASED`n- Authorization: RELEASED`n"
    Good {Assert-AiwTaskClosure $zeroContext (With-Plan $zeroClosed $zeroPlan) EVIDENCE-001 ([pscustomobject]@{publicDecisionIdentity='NOT_REQUIRED'}) -RequireExplicitClosure} 'quality-real-zero-stage-consumer-closes-without-fabricated-evidence'
    $zeroUser=Clone $zeroPlan;$zeroUser.stages=@([pscustomobject]@{id='user';kind='USER_DECISION';requiredBy=$requirements;dependsOn=@();candidateRef=@();evidenceRefs=@()})
    Bad {Assert-AiwTaskClosure $zeroContext (With-Plan $zeroClosed $zeroUser) EVIDENCE-001 ([pscustomobject]@{publicDecisionIdentity='NOT_REQUIRED'}) -RequireExplicitClosure} 'ACCEPTANCE_' 'quality-zero-selection-retains-unfinished-user-decision'
    # Clear the active plan through its original management action, then use
    # the original source-maintenance chain to change policy at a safe point.
    QCard $null 'clear-plan-before-policy-change'
    $next=Clone $policy;$next.qualityAssurance.defaultStages=@('RESULT_REVIEW');QPolicy $next 'enable-review-only'
    Bad {Get-AiwPackageQuality $ctx $accept $plan} 'QUALITY_PLAN_DRIFT' 'quality-current-policy-change-requires-fresh-plan'
    Good {Read-AiwResultEvidence $ctx $accepted EVIDENCE-001 @($candidate) $requirements -RequireSuccess -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($acceptedF.pair,$produced.pair)} 'quality-historical-accept-uses-original-policy-after-real-source-change'
    Bad {Read-AiwResultEvidence $ctx $accepted EVIDENCE-001 @($candidate) $requirements -RequireSuccess -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($produced.pair)} 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND' 'quality-historical-accept-needs-original-successful-acceptance-F'
    $requirementsPath=Join-Path $temp $requirements.path;$savedRequirements=[IO.File]::ReadAllBytes($requirementsPath)
    try{[IO.File]::WriteAllText($requirementsPath,'Fault-injected changed immutable requirements.',$utf8);Bad {Read-AiwResultEvidence $ctx $accepted EVIDENCE-001 @($candidate) $requirements -RequireSuccess -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($acceptedF.pair,$produced.pair)} 'EVIDENCE_IDENTITY_DRIFT' 'quality-historical-success-cannot-ignore-changed-immutable-requirements'}finally{[IO.File]::WriteAllBytes($requirementsPath,$savedRequirements)}
    $subject=$wideSubject;$candidate=@(Get-AiwCurrentCandidateReferences $ctx $subject.exactPaths)
    $baseCard=$baseCard.Replace('expected_paths=[result.md]; actual_paths=[result.md]','expected_paths=[result.md|unchanged.md]; actual_paths=[result.md|unchanged.md]')
    $reviewPlan=(QPrepare $subject 'prepare-review-only').plan
    $reviewPlan.stages[0].candidateRef=@($candidate);QCard $reviewPlan 'bind-review-only'
    $write=QStart (QPackage SOURCE_WRITE @('result.md') owner $reviewPlan.qualityBinding) 'produce-review-only';$null=QProcess $write.boundary 'produce-review-only-admit'
    $candidate=@((QProduct 'The approved anonymous sentence. Reviewed production.'))+@(Get-AiwCurrentCandidateReferences $ctx @('unchanged.md'));$sourceF=QFinish $write
    $reviewPlan.stages[0].candidateRef=@($candidate);QCard $reviewPlan 'bind-review-production-candidate'
    $test=QStart (QPackage TEST_RUN $subject.exactPaths owner $reviewPlan.qualityBinding) 'actual-failed-test';$null=QProcess $test.boundary 'actual-failed-test-admit'
    $testEntry=Put ($runtime+'failing-command.ps1') "Write-Output 'Actual anonymous failure'; exit 7"
    $actualFailure=QNative $testEntry @() 'actual-failing-command'
    True ($actualFailure.Code-eq7) 'quality-real-test-command-exit-observed'
    $rawFailure=Ref ($runtime+'actual-failing-command-raw.txt')
    $commandPath=Json ($runtime+'failed-test-command-evidence.json') ([pscustomobject]@{command=('pwsh -File '+$testEntry);exitCode=$actualFailure.Code;output=$rawFailure})
    $failureRecord=Record owner FAIL;$failureRecord.checks=@([pscustomobject]@{id='actual-test';method='COMMAND';outcome='FAIL';reason='Actual anonymous command exited seven; no failure is hidden by quality selection.';evidenceLocators=@([pscustomobject]@{path=$commandPath;identity=(Id $commandPath)})})
    $failureSelf=Typed $failureRecord SELF_CHECK;$failedF=QFinish $test @($failureSelf)
    True ($failedF.value.actionOutcome-ceq'FAIL'-and$failedF.value.successorState-cne'ADVANCE') 'quality-review-only-does-not-turn-real-test-failure-into-success'
    $noExitCommand=Json ($runtime+'no-exit-command-negative.json') ([pscustomobject]@{command=('pwsh -File '+$testEntry);output=$rawFailure})
    $noExitRecord=Clone $failureRecord;$noExitRecord.checks[0].evidenceLocators=@([pscustomobject]@{path=$noExitCommand;identity=(Id $noExitCommand)})
    $noExit=Typed $noExitRecord SELF_CHECK;$invalidTestF=Clone $failedF.input;$invalidTestF.evidenceRefs=@($noExit)
    $null=QProcess $invalidTestF 'test-no-exit-negative-finalize' 'EVIDENCE_FIELD_SET'
    $review=QPackage REVIEW_EXECUTE $subject.exactPaths reviewer $reviewPlan.qualityBinding;$review.reviewIndependence='INDEPENDENT';$review|Add-Member candidateWriter owner;$review|Add-Member materialContributors @('contributor');$review.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE')
    $reviewPackagePath=Json ($runtime+'review-only-package.json') $review
    $hostPath=Json ($runtime+'synthetic-host-reviewer.json') ([pscustomobject]@{isError=$false;content=@([pscustomobject]@{type='text';text='{"threadId":"reviewer"}'})})
    $delivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='reviewer';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=[pscustomobject]@{path=$reviewPackagePath;identity=(Id $reviewPackagePath)}}
    $route=QStart (QPackage REVIEW_ROUTE $subject.exactPaths owner $reviewPlan.qualityBinding) 'route-without-self'
    $route.boundary|Add-Member deliveryContext $delivery;$route.boundary|Add-Member productionFinalizeRef $sourceF.pair
    $failedPreparation=Clone $route.boundary;$failedPreparation.productionFinalizeRef=$failedF.pair
    $null=QProcess $failedPreparation 'route-real-failed-test' 'QUALITY_PRODUCTION_NOT_SUCCESSFUL'
    $missing=Clone $route.boundary;$missing.PSObject.Properties.Remove('productionFinalizeRef');$null=QProcess $missing 'route-missing-production' 'QUALITY_PRODUCTION_FINALIZE_REQUIRED'
    $null=QProcess $route.boundary 'route-without-self-admit'
    $delivery.stage='OBSERVE';$delivery.observedRecipient='reviewer';$delivery.outcome='SUCCESS';$delivery.evidence=$hostPath+'#'+(Id $hostPath)
    $routed=QFinish $route @() @() @() $delivery
    True ($routed.value.delivery.delivered) 'quality-no-self-review-route-consumes-real-production-F'
    # The automatic chain restores an already existing frozen candidate from
    # an actual admitted draft. Neither production step is an empty write,
    # and no future identity or task change is inserted into the continuation.
    $autoFrozen=@($candidate);$autoTexts=@([IO.File]::ReadAllText((Join-Path $objectRoot 'result.md')),[IO.File]::ReadAllText((Join-Path $objectRoot 'unchanged.md')))
    $draft=QStart (QPackage SOURCE_WRITE $subject.exactPaths owner $reviewPlan.qualityBinding) 'auto-prepare-draft';$null=QProcess $draft.boundary 'auto-prepare-draft-admit'
    $null=QProduct 'Anonymous draft awaiting restoration of the frozen approved sentence.'
    [IO.File]::WriteAllText((Join-Path $objectRoot 'unchanged.md'),'Anonymous draft of the second frozen member.',$utf8)
    $draftCandidate=@(Get-AiwCurrentCandidateReferences $ctx $subject.exactPaths);$draftF=QFinish $draft
    True ($draftF.value.actionOutcome-ceq'OBSERVED'-and$draftCandidate[0].identity-cne$autoFrozen[0].identity-and$draftCandidate[1].identity-cne$autoFrozen[1].identity) 'quality-auto-prerequisite-real-draft-changes-both-frozen-members'
    $combined=QPackage SOURCE_WRITE $subject.exactPaths owner $reviewPlan.qualityBinding
    $combined.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$combined|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$combined|Add-Member selfCheckRepairLimit 1;$combined.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
    $autoProduction=QStart $combined 'auto-real-production';$null=QProcess $autoProduction.boundary 'auto-real-production-admit'
    $null=QProduct $autoTexts[0];[IO.File]::WriteAllText((Join-Path $objectRoot 'unchanged.md'),$autoTexts[1],$utf8)
    $candidate=@(Get-AiwCurrentCandidateReferences $ctx $subject.exactPaths);$autoProductionF=QFinish $autoProduction
    True (($candidate|ConvertTo-Json -Depth 20 -Compress)-ceq($autoFrozen|ConvertTo-Json -Depth 20 -Compress)-and$autoProductionF.value.actionOutcome-ceq'OBSERVED'-and$autoProductionF.value.continuationReceipt.nextAction-ceq'TEST_RUN') 'quality-auto-real-production-restores-existing-complete-frozen-A'
    $testContinuation=Json ($runtime+'actual-test-continuation.json') $autoProductionF.value.continuationReceipt
    $auto=QStart $combined 'auto-real-test' TEST_RUN $testContinuation;$null=QProcess $auto.boundary 'auto-real-test-admit'
    $passScript=@'
param([string]$First,[string]$Second)
if(-not[IO.File]::ReadAllText($First).Contains('The approved anonymous sentence.')){exit 8}
if([IO.File]::ReadAllText($Second)-cne'Previously existing anonymous member.'){exit 9}
Write-Output 'Both actual anonymous candidate members checked.'
exit 0
'@
    $passEntry=Put ($runtime+'passing-candidate-command.ps1') $passScript
    $passRun=QNative $passEntry @('-First',(Join-Path $objectRoot 'result.md'),'-Second',(Join-Path $objectRoot 'unchanged.md')) 'actual-success-command'
    True ($passRun.Code-eq0) 'quality-real-success-command-checks-complete-current-A'
    $passCommand=Json ($runtime+'successful-test-command-evidence.json') ([pscustomobject]@{command=('pwsh -File '+$passEntry+' -First result.md -Second unchanged.md');exitCode=$passRun.Code;output=(Ref ($runtime+'actual-success-command-raw.txt'))})
    $passRecord=Record owner PASS;$passRecord.checks=@([pscustomobject]@{id='actual-complete-A';method='COMMAND';outcome='PASS';reason='Actual candidate command read and asserted both frozen members; no generic SELF stage is fabricated.';evidenceLocators=@([pscustomobject]@{path=$passCommand;identity=(Id $passCommand)})})
    $actualTestSelf=Typed $passRecord SELF_CHECK;$autoF=QFinish $auto @($actualTestSelf)
    True ($autoF.value.actionOutcome-ceq'PASS'-and$autoF.value.successorState-ceq'AVAILABLE'-and$autoF.value.continuationReceipt.nextAction-ceq'REVIEW_ROUTE') 'quality-no-self-plan-generates-real-successful-test-review-continuation'
    $continuation=Json ($runtime+'actual-review-continuation.json') $autoF.value.continuationReceipt
    $autoRoute=QStart $combined 'auto-no-self-route' REVIEW_ROUTE $continuation
    $autoDelivery=Clone $delivery;$autoDelivery.stage='PREPARE';$autoDelivery.outcome='NOT_SENT';$autoDelivery.observedRecipient='NOT_APPLICABLE';$autoDelivery.evidence='NOT_APPLICABLE'
    $autoRoute.boundary|Add-Member deliveryContext $autoDelivery;$autoRoute.boundary|Add-Member productionFinalizeRef $autoF.pair
    $null=QProcess $autoRoute.boundary 'auto-no-self-route-admit'
    $continuedCall=(Get-Content -LiteralPath $trace -Tail 1|ConvertFrom-Json -Depth 50).parameters
    True ($continuedCall.ContinuationReceiptPath-ceq$continuation-and$continuedCall.ExpectedContinuationReceiptIdentity-ceq(Id $continuation)-and($continuedCall.ObservedAction-join'|')-ceq'REVIEW_ROUTE'-and($continuedCall.ObservedPath-join'|')-ceq($subject.exactPaths-join'|')) 'quality-A-actual-continuation-ADMIT-forwards-original-receipt-and-full-paths'
    $autoDelivery.stage='OBSERVE';$autoDelivery.outcome='SUCCESS';$autoDelivery.observedRecipient='reviewer';$autoDelivery.evidence=$hostPath+'#'+(Id $hostPath)
    $autoRouted=QFinish $autoRoute @() @() @() $autoDelivery
    True ($autoRouted.value.delivery.delivered) 'quality-no-self-plan-consumes-real-review-continuation-and-original-test-F'
    $reviewAction=QStart $review 'independent-review-only';$null=QProcess $reviewAction.boundary 'independent-review-only-admit'
    $verdictRecord=Record reviewer APPROVED;$verdictRecord|Add-Member authorizationRef ([pscustomobject]@{path=$reviewAction.packagePath;identity=(Id $reviewAction.packagePath)})
    $verdict=Typed $verdictRecord REVIEW_VERDICT
    $ownerHost=Json ($runtime+'synthetic-host-owner.json') ([pscustomobject]@{isError=$false;content=@([pscustomobject]@{type='text';text='{"threadId":"owner"}'})})
    $ownerDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient='owner';observedRecipient='owner';outcome='SUCCESS';evidence=($ownerHost+'#'+(Id $ownerHost))}
    $reviewF=QFinish $reviewAction @($verdict) @() @() $ownerDelivery
    $reviewPlan.stages[0].evidenceRefs=@($verdict);$reviewPlan.stages[0]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($reviewF.pair)})
    QCard $reviewPlan 'bind-review-verdict'
    $closed=$baseCard.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;').Replace('- Status: ACTIVE','- Status: CLOSED')+"- Writer / reviewer / authorization: NONE / NONE / NONE`n- Closure outcome: SUCCESS`n- Closure evidence: Actual selected independent review and original production F.`n- Remaining obligations: NONE`n- Artifact disposition: result.md remains an anonymous fixture result; Git DEFERRED.`n"
    $closed+="- Closure basis: Actual selected independent review and original production F.`n- Output disposition: result.md retained in fixture.`n- Git disposition: DEFERRED; fixture only.`n- Unresolved obligations: NONE`n- Writer: RELEASED`n- Reviewer: RELEASED`n- Authorization: RELEASED`n"
    QCard $reviewPlan 'close-selected-review' $closed -Archive
    True (-not[IO.File]::Exists($taskPath)-and[IO.File]::ReadAllText((Join-Path $temp '.ai-workspace/tasks/archive/EVIDENCE-001.md')).Contains('lifecycle=CLOSED;')) 'quality-selected-review-success-archived-through-original-control-F'
    Write-Output ('FIXTURE|'+$Root+'|qualification=SYNTHETIC_TEST_FIXTURE_ONLY|host=SYNTHETIC|actualCommands=YES')
}
function Test-HistoricalInputConsumers([string]$Root){
    # An independent anonymous project: A has 18 unchanged documents. AGENTS
    # is an original observation outside A, not a historical candidate alias.
    $temp=$Root;$previousLocation=(Get-Location).Path;$previousCurrent=[Environment]::CurrentDirectory
    [IO.Directory]::CreateDirectory($temp)|Out-Null
    try{
        Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp
        Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
        $fixtureFramework=Join-Path $temp 'framework'
        $fixtureVersion=New-AiwTestMechanismFixture ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))) $fixtureFramework (Join-Path $PSScriptRoot 'test-groups.json')
        $configPath=Json '.ai-workspace/project.json' ([pscustomobject]@{schemaVersion=7;id='evidence-fixture';displayName='Anonymous historical inputs';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('protected.txt');frameworkCapabilities=[pscustomobject]@{};sourceBindings=@();processPolicy=@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
        $null=Json '.ai-workspace/controller.json' ([pscustomobject]@{schemaVersion=1;projectId='evidence-fixture';controllerId='controller';controllerEpoch=1;state='CURRENT'})
        $null=Json '.ai-workspace/corrections.json' ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='evidence-fixture';corrections=@()})
        $null=Json '.ai-workspace/process-policy.json' ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='evidence-fixture';rules=@()})
        $null=Put '.ai-workspace/BOOTSTRAP.md' "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
        $oldAgents='Original anonymous loading instructions.';$newAgents=$oldAgents+"`nLater loading instructions; candidate documents are unchanged."
        $null=Put 'AGENTS.md' $oldAgents;$agentsRef=Ref 'AGENTS.md'
        $candidate=@(1..18|ForEach-Object{$relative=('documents/item-{0:d2}.md' -f $_);$null=Put $relative ('Anonymous accepted preparation '+$_);Ref $relative})
        $taskText="# EVIDENCE-001 — original input consumption`n- Task schema: 2.0.0`n- Profile: STANDARD; reason=fixture`n- Owner: owner`n- Work route: actor=owner; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[$($candidate.path -join ',')]; actual_paths=[$($candidate.path -join ',')]`n"
        $taskPath=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
        $null=Put 'requirements.md' 'Every anonymous document must preserve its prepared content.';$requirements=Ref 'requirements.md'
        $null=Put 'auxiliary.md' 'Unbound auxiliary evidence remains immutable.';$auxiliary=Ref 'auxiliary.md'
        $fixtureRuntime='.ai-workspace/runtime/EVIDENCE-001/owner/'
        function Input-Process($Value,[string]$Name){
            $path=Json ($fixtureRuntime+$Name+'.json') $Value
            $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'),'-InputPath',$path,'-AsJson') -WorkingDirectory $temp -GroupId 'result-history-inputs'
            $null=Put ($fixtureRuntime+$Name+'-output.txt') ($run.Output-join "`n")
            if($run.Code-ne0){throw ('HISTORY_INPUT_PROCESS|'+$Name+'|'+($run.Output-join "`n"))}
            $parsed=($run.Output-join "`n")|ConvertFrom-Json -Depth 100
            if($parsed.status-cne'PASS'){throw ('HISTORY_INPUT_PROCESS_STATUS|'+$Name+'|'+($parsed|ConvertTo-Json -Depth 10 -Compress))}
            $null=Json ($fixtureRuntime+$Name+'-result.json') $parsed
            return $parsed
        }
        function Input-Check($Package,[string]$PackagePath){
            $lines=@(& (Join-Path $fixtureVersion 'scripts/check-authorization.ps1') -PackagePath $PackagePath -ObservedActor $Package.grantee -ObservedTaskId 'EVIDENCE-001' -ObservedOwner owner -ObservedAction $Package.actions[0] -ObservedPath $Package.exactPaths -ObservedIdentity @($Package.objectIdentities|ForEach-Object{$_.path+'='+$_.identity}) -TaskPath '.ai-workspace/tasks/active/EVIDENCE-001.md' -ExpectedTaskIdentity $Package.taskIdentity -ControllerControlPath '.ai-workspace/controller.json' 2>&1|ForEach-Object{[string]$_})
            return [pscustomobject]@{Code=$LASTEXITCODE;Text=($lines-join "`n")}
        }
        function Input-Finalize($Package,[string]$PackagePath,$TypedRef,[string]$Name,$Delivery=$null){
            $checked=Input-Check $Package $PackagePath
            $null=Json ($fixtureRuntime+$Name+'-checker.json') $checked
            if($checked.Code-ne0){throw ('HISTORY_INPUT_CHECKER|'+$Name+'|'+$checked.Text)}
            $discover=[ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=@{mode='FULL'};projectRoot=$temp;frameworkRoot=$fixtureFramework;taskPath=$taskPath;expectedProjectConfigIdentity=(Id $configPath);expectedCorrectionsIdentity=(Id (Join-Path $temp '.ai-workspace/corrections.json'));expectedTaskIdentity=(Id $taskPath);observedActor=$Package.grantee;capabilities=@();exactPaths=$Package.exactPaths;forbiddenPaths=@('protected.txt');protectedPaths=@();authorizationPackagePath=$PackagePath;expectedAuthorizationIdentity=(Id $PackagePath);userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=@{schemaVersion=2;objective='Anonymous original author and historical input regression';requestedActionKind=$Package.actions[0];requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=$Package.exactPaths;capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:software')};workType=@{state='KNOWN';values=@('aiw:verification')};deliverableType=@{state='KNOWN';values=@('aiw:test-result')};stage=@{state='KNOWN';values=@('aiw:verification')}}}}
            $stepIntent=switch($Package.actions[0]){
                REVIEW_ROUTE {@{result='HANDOFF';work='aiw:review';deliverable='aiw:handoff';stage='aiw:review'}}
                REVIEW_EXECUTE {@{result='REVIEW_VERDICT';work='aiw:review';deliverable='aiw:review-verdict';stage='aiw:review'}}
                RESULT_ACCEPT {@{result='RESULT_ACCEPTANCE';work='aiw:acceptance';deliverable='aiw:acceptance-result';stage='aiw:acceptance'}}
                default {throw 'HISTORY_INPUT_ACTION_UNSUPPORTED'}
            }
            $discover.intentEnvelope.requestedResultKind=$stepIntent.result
            $discover.intentEnvelope.facets.workType.values=@($stepIntent.work)
            $discover.intentEnvelope.facets.deliverableType.values=@($stepIntent.deliverable)
            $discover.intentEnvelope.facets.stage.values=@($stepIntent.stage)
            $resolved=Input-Process $discover ($Name+'-discover')
            $compactPath=Json ($fixtureRuntime+$Name+'-compact.json') $resolved.compactReceipt
            # Only isolated fixture obligations are asserted here. Host results
            # below are explicitly synthetic and never send a real message.
            $boundary=[pscustomobject]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compactPath;expectedDiscoverReceiptIdentity=(Id $compactPath);preparationReceipts=@($resolved.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
            if($Package.actions[0]-ceq'REVIEW_ROUTE'){$boundary.evidenceRefs=@($TypedRef)}
            if($null-ne$Delivery){$preparation=Clone $Delivery;$preparation.stage='PREPARE';$preparation.outcome='NOT_SENT';$preparation.observedRecipient='NOT_APPLICABLE';$preparation.evidence='NOT_APPLICABLE';$boundary|Add-Member deliveryContext $preparation}
            $null=Input-Process $boundary ($Name+'-admit')
            $boundary.mode='FINALIZE_OUTPUT';$boundary.evidenceRefs=@($TypedRef)
            $boundary.resultReceipts=@($resolved.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@($Package.objectIdentities|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.identity})
            if($null-ne$Delivery){$boundary.deliveryContext=$Delivery}
            $actual=Input-Process $boundary ($Name+'-finalize')
            return [pscustomobject]@{result=$actual;input=$boundary;pair=[pscustomobject]@{inputRef=(Ref ($fixtureRuntime+$Name+'-finalize.json'));resultRef=(Ref ($fixtureRuntime+$Name+'-finalize-result.json'))}}
        }
        function Input-Delivery([string]$Recipient){
            $relative=$fixtureRuntime+'synthetic-host-'+$Recipient+'.json'
            $null=Json $relative ([pscustomobject]@{isError=$false;content=@([pscustomobject]@{type='text';text=(@{threadId=$Recipient}|ConvertTo-Json -Compress)})})
            return [pscustomobject]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient=$Recipient;observedRecipient=$Recipient;outcome='SUCCESS';evidence=(Join-Path $temp $relative)+'#'+(Id (Join-Path $temp $relative))}
        }
        $commandRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-Command',"Write-Output 'anonymous-original-command'") -WorkingDirectory $temp -GroupId 'result-history-input-command'
        if($commandRun.Code-ne0){throw 'HISTORY_INPUT_COMMAND_FAILED'}
        $null=Put 'command-output.txt' ($commandRun.Output-join "`n")
        $null=Json 'command.json' ([pscustomobject]@{command="pwsh -NoProfile -NonInteractive -Command Write-Output 'anonymous-original-command'";exitCode=$commandRun.Code;output=(Ref 'command-output.txt')})
        $authorRecord=Record author
        $authorRecord.checks[0].evidenceLocators+=@($agentsRef,$auxiliary)
        $authorRecord.evidenceLocators+=@($agentsRef,$auxiliary)
        $authorRecord.checks+=@([pscustomobject]@{id='original-command';method='COMMAND';outcome='PASS';reason='Actual isolated command exit and output observed; no production execution claimed.';evidenceLocators=@((Ref 'command.json'))})
        $authorSelf=Typed $authorRecord SELF_CHECK
        $reviewPackage=Package reviewer;$reviewPackage.actions=@('REVIEW_EXECUTE');$reviewPackage.reviewIndependence='INDEPENDENT'
        $reviewPackage|Add-Member candidateWriter author;$reviewPackage|Add-Member materialContributors @('owner')
        $reviewPackage.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE')
        $reviewPackageRelative=$fixtureRuntime+'review-package.json';$reviewPackagePath=Json $reviewPackageRelative $reviewPackage
        $routePackage=Package;$routePackage.actions=@('REVIEW_ROUTE');$routePackagePath=Json ($fixtureRuntime+'route-package.json') $routePackage
        $routeDelivery=Input-Delivery reviewer;$routeDelivery|Add-Member reviewPackageRef (Ref $reviewPackageRelative)
        $routed=Input-Finalize $routePackage $routePackagePath $authorSelf 'owner-route' $routeDelivery
        True ($routed.result.delivery.delivered-and$routed.result.consumer.recipient-ceq'reviewer') 'history-input-original-owner-route-consumes-other-authors-A18-self'
        $reviewRecord=Record reviewer APPROVED;$reviewRecord|Add-Member authorizationRef (Ref $reviewPackageRelative)
        $reviewRecord.checks[0].evidenceLocators+=@($agentsRef);$reviewRecord.evidenceLocators+=@($agentsRef)
        $reviewEvidence=Typed $reviewRecord REVIEW_VERDICT
        $reviewed=Input-Finalize $reviewPackage $reviewPackagePath $reviewEvidence 'independent-review' (Input-Delivery owner)
        True ($reviewed.result.delivery.delivered) 'history-input-original-independent-review-finalized'
        $secondRoute=Input-Process $routed.input 'second-route-finalize'
        $secondPair=[pscustomobject]@{inputRef=(Ref ($fixtureRuntime+'second-route-finalize.json'));resultRef=(Ref ($fixtureRuntime+'second-route-finalize-result.json'))}
        $pairs=@($routed.pair,$reviewed.pair)
        $null=Put 'AGENTS.md' $newAgents
        $ctx=New-AiwEvidenceContext $temp '' $fixtureFramework
        $acceptPackage=Package;$acceptPackage|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=$candidate;requirementsRef=$requirements;prerequisiteEvidenceRefs=@($authorSelf,$reviewEvidence);reservedUserDecisionRefs=@();prerequisiteConsumption=[pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=$pairs}})
        $acceptRelative=$fixtureRuntime+'accept-package.json';$acceptPath=Json $acceptRelative $acceptPackage
        $acceptRecord=Record owner ACCEPTED;$acceptRecord|Add-Member authorizationRef (Ref $acceptRelative)
        $acceptance=Typed $acceptRecord RESULT_ACCEPTANCE
        $acceptDelivery=[pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
        $accepted=Input-Finalize $acceptPackage $acceptPath $acceptance 'current-accept' $acceptDelivery
        True ($accepted.result.status-ceq'PASS') 'history-input-current-native-checker-DISCOVER-ADMIT-FINALIZE-after-only-agents-change'
        Good {Assert-AiwAcceptanceBinding $ctx $acceptPackage $null -RequireIndependentReview} 'history-input-original-review-still-independently-qualified'
        $currentOnly=Clone $acceptPackage;$currentOnly.acceptanceBinding.PSObject.Properties.Remove('prerequisiteConsumption')
        Bad {Assert-AiwAcceptanceBinding $ctx $currentOnly $null} 'EVIDENCE_IDENTITY_DRIFT' 'history-input-no-declaration-stays-current'
        $missing=Clone $acceptPackage;$missing.acceptanceBinding.prerequisiteConsumption.originalFinalize=@($reviewed.pair)
        Bad {Assert-AiwAcceptanceBinding $ctx $missing $null} 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND' 'history-input-missing-author-original-rejected'
        $ambiguous=Clone $acceptPackage;$ambiguous.acceptanceBinding.prerequisiteConsumption.originalFinalize+=@($secondPair)
        Bad {Assert-AiwAcceptanceBinding $ctx $ambiguous $null} 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND' 'history-input-two-original-routes-require-explicit-selection'
        # Fault injection copies are deliberately invalid; no PASS is rewritten.
        $wrongAuthor=Clone $authorRecord;$wrongAuthor.actor='imposter';$wrongSelf=Typed $wrongAuthor SELF_CHECK
        $wrongInput=Clone $routed.input;$wrongInput.evidenceRefs=@($wrongSelf);$null=Json ($fixtureRuntime+'wrong-author-finalize.json') $wrongInput
        $wrongPair=[pscustomobject]@{inputRef=(Ref ($fixtureRuntime+'wrong-author-finalize.json'));resultRef=$routed.pair.resultRef}
        Bad {Read-AiwResultEvidence $ctx $wrongSelf EVIDENCE-001 $candidate $requirements -RequireSuccess -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($wrongPair)} 'EVIDENCE_HISTORICAL_AUTHOR_DRIFT' 'history-input-original-review-writer-not-organizer-proves-author'
        # A changed unbound locator, requirements or canonical original can
        # never borrow AGENTS' original input observation exemption.
        foreach($relative in @('auxiliary.md','requirements.md','command.json','command-output.txt',$authorSelf.path,$reviewPackageRelative,$routed.pair.inputRef.path,$routed.pair.resultRef.path)){
            $physical=Join-Path $temp $relative;$original=[IO.File]::ReadAllBytes($physical)
            try{[IO.File]::WriteAllText($physical,'corrupt original',$utf8);Bad {Assert-AiwAcceptanceBinding $ctx $acceptPackage $null} 'EVIDENCE_IDENTITY_DRIFT' ('history-input-immutable-or-unbound-'+$relative)}finally{[IO.File]::WriteAllBytes($physical,$original)}
        }
        $protectedContext=New-AiwEvidenceContext $temp '' $fixtureFramework @() @((Join-Path $temp 'AGENTS.md'))
        [IO.File]::Delete((Join-Path $temp 'AGENTS.md'))
        try{Bad {Assert-AiwAcceptanceBinding $protectedContext $acceptPackage $null} 'EVIDENCE_PATH_FORBIDDEN' 'history-input-current-protection-before-missing-old-agents-read'}finally{$null=Put 'AGENTS.md' $newAgents}
        $productPath=Join-Path $temp $candidate[0].path;$productBytes=[IO.File]::ReadAllBytes($productPath)
        try{
            [IO.File]::WriteAllText($productPath,'current concurrent drift',$utf8)
            $checked=Input-Check $acceptPackage $acceptPath
            True ($checked.Code-ne0-and$checked.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) 'history-input-native-current-candidate-still-fresh'
        }finally{[IO.File]::WriteAllBytes($productPath,$productBytes)}
        $originalTask=[IO.File]::ReadAllBytes($taskPath)
        try{
            [IO.File]::WriteAllText($taskPath,($taskText.Replace('- Owner: owner','- Owner: other-owner')),$utf8)
            $checked=Input-Check $acceptPackage $acceptPath
            True ($checked.Code-ne0-and$checked.Text.Contains('TASK_OBJECT_DRIFT')) 'history-input-native-current-authority-drift-rejected'
        }finally{[IO.File]::WriteAllBytes($taskPath,$originalTask)}
    }finally{Set-Location -LiteralPath $previousLocation;[Environment]::CurrentDirectory=$previousCurrent}
}
try{
    [IO.Directory]::CreateDirectory($temp)|Out-Null;Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp
    if($Group-cin@('QualityAssurance','QualityMaintenance')){
        Test-QualityAssuranceConsumers (Join-Path $temp 'quality') -Maintenance:($Group-ceq'QualityMaintenance')
        $completed=$true;Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=result-quality|evidenceCeiling=INSTRUCTION_BOUND');return
    }
    if($Group-ceq'HistoricalInputs'){
        Test-HistoricalInputConsumers (Join-Path $temp 'historical-inputs')
        $completed=$true;Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=result-historical-inputs|evidenceCeiling=INSTRUCTION_BOUND');return
    }
    & git init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
    $configPath=Json '.ai-workspace/project.json' ([pscustomobject]@{schemaVersion=7;id='evidence-fixture';displayName='Evidence fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('protected.txt');frameworkCapabilities=[pscustomobject]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
    $controllerPath=Json '.ai-workspace/controller.json' ([pscustomobject]@{schemaVersion=1;projectId='evidence-fixture';controllerId='controller';controllerEpoch=1;state='CURRENT'})
    $taskText="# EVIDENCE-001 — result evidence`n- Task schema: 2.0.0`n- Profile: STANDARD; reason=fixture`n- Owner: owner`n- Work route: actor=owner; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[result.md]; actual_paths=[result.md]`n"
    $taskPath=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
    $null=Put 'result.md' "# Document result`nRequired content.`n";$candidate=Ref 'result.md'
    $null=Put 'requirements.md' "<!-- approved:BEGIN -->`nRequired content and concrete acceptance.`n<!-- approved:END -->`n";$requirements=Ref 'requirements.md'
    $ctx=New-AiwEvidenceContext $temp
    $record=Record;$self=Typed $record SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'document-model-judgment-no-fictional-exit-code'
    $commandOutput=@(& ([Environment]::ProcessPath) -NoProfile -Command "Write-Output 'actual-command-observation'");$exitCode=$LASTEXITCODE
    $null=Put 'command-output.txt' (($commandOutput-join"`n")+"`n")
    $null=Json 'command.json' ([pscustomobject]@{command='pwsh -NoProfile -Command Write-Output actual-command-observation';exitCode=$exitCode;output=(Ref 'command-output.txt')})
    $commandRecord=Record;$commandRecord.checks[0].method='COMMAND';$commandRecord.checks[0].evidenceLocators=@((Ref 'command.json'))
    $commandEvidence=Typed $commandRecord SELF_CHECK
    $observedCommandCheck=Clone $commandRecord.checks[0];$observedCommandCheck.id='observed-fixture-command';$observedCommandCheck.reason='Actual same-fixture command observed above; result semantics remain separately bound.'
    Good {Read-AiwResultEvidence $ctx $commandEvidence EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'software-command-reads-actual-exit-and-output'
    $failure=Clone $commandRecord;$failure.outcome='FAIL';$failure.checks[0].outcome='FAIL'
    $null=Json 'failed-command.json' ([pscustomobject]@{command='observed failing command fixture';exitCode=2;output=(Ref 'command-output.txt')})
    $failure.checks[0].evidenceLocators=@((Ref 'failed-command.json'));$failedRef=Typed $failure SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $failedRef EVIDENCE-001 @($candidate) $requirements} 'failure-record-remains-observable'
    Bad {Read-AiwResultEvidence $ctx $failedRef EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'EVIDENCE_NOT_SUCCESSFUL' 'failed-test-cannot-satisfy-success-gate'
    $falsePass=Clone $commandRecord;$falsePass.checks[0].evidenceLocators=@((Ref 'failed-command.json'));$falseRef=Typed $falsePass SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $falseRef EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_COMMAND_FAILURE' 'nonzero-exit-cannot-be-pass'
    $mut=Clone $record;$mut|Add-Member fabricated $true;$ref=Typed $mut SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_FIELD_SET' 'unknown-evidence-field'
    $mut=Clone $record;$mut.checks[0]|Add-Member exitCode 0;$ref=Typed $mut SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_FIELD_SET' 'model-judgment-cannot-invent-exit-code'
    $mut=Clone $record;$mut.candidateObjects+=@($candidate);$ref=Typed $mut SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_DUPLICATE_REF' 'duplicate-candidates'
    $ref=Clone $self;$ref.kind='USER_DECISION'
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_KIND' 'no-self-reported-user-evidence-kind'
    Bad {Read-AiwResultEvidence $ctx $self OTHER-TASK @($candidate) $requirements} 'EVIDENCE_TASK_DRIFT' 'wrong-task-evidence'
    Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements -ExpectedActor stranger} 'EVIDENCE_ACTOR_DRIFT' 'wrong-actor-evidence'
    $null=Put 'result.md' 'changed candidate'
    Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_IDENTITY_DRIFT' 'candidate-change-invalidates-evidence'
    $null=Put 'result.md' "# Document result`nRequired content.`n"
    $null=Put 'requirements.md' 'changed requirements'
    Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_IDENTITY_DRIFT' 'requirements-change-invalidates-evidence'
    $null=Put 'requirements.md' "<!-- approved:BEGIN -->`nRequired content and concrete acceptance.`n<!-- approved:END -->`n"
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' ($taskText+"`nProgress: updated without changing requirements.`n")
    Good {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'ordinary-task-progress-does-not-invalidate-evidence'
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
    $section=Clone $record;$section.requirementsRef|Add-Member section approved;$sectionRef=Typed $section SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $sectionRef EVIDENCE-001 @($candidate) $section.requirementsRef} 'marked-requirements-section'
    $section.requirementsRef.section='missing';$sectionRef=Typed $section SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $sectionRef EVIDENCE-001 @($candidate) $section.requirementsRef} 'EVIDENCE_SECTION_UNBOUND' 'missing-marked-section'
    $protected=Clone $record;$protected.candidateObjects[0].path='protected.txt';$protectedRef=Typed $protected SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $protectedRef EVIDENCE-001 $protected.candidateObjects $requirements} 'EVIDENCE_PATH_FORBIDDEN' 'forbidden-before-missing-file-hash'
    $escape=Clone $record;$escape.candidateObjects[0].path='../outside.txt';$escapeRef=Typed $escape SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $escapeRef EVIDENCE-001 $escape.candidateObjects $requirements} 'EVIDENCE_PATH_INVALID' 'candidate-path-traversal'
    $duplicatePath='.ai-workspace/reports/duplicate.json';$null=Put $duplicatePath '{"schemaVersion":1,"schemaVersion":1}';$ref=Ref $duplicatePath;$ref|Add-Member kind SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $ref EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_DUPLICATE_MEMBER' 'duplicate-json-members'

    $ownerPackage=Package
    Good {Assert-AiwAcceptanceBinding $ctx $ownerPackage $null} 'owner-default-acceptance'
    $delegated=Package delegate;Binding $delegated
    Good {Assert-AiwAcceptanceBinding $ctx $delegated $null} 'owner-delegated-pure-acceptance'
    $noDelegation=Package delegate
    Bad {Assert-AiwAcceptanceBinding $ctx $noDelegation $null} 'RESULT_ACCEPT_DELEGATION_REQUIRED' 'nonowner-without-delegation'
    $controller=Clone $delegated;$controller.issuer='controller';$controller.issuerRole='PROJECT_CONTROLLER'
    Bad {Assert-AiwAcceptanceBinding $ctx $controller $null} 'RESULT_ACCEPT_OWNER_OR_USER_DECISION_REQUIRED' 'controller-title-cannot-override-owner'
    $null=Put 'user-original.txt' 'Original fixture user explicitly grants delegate acceptance for the bound result.';$user=Ref 'user-original.txt'
    $userPackage=Clone $controller;$userPackage.userConfirmation=$user.identity;$userPackage.acceptanceBinding.reservedUserDecisionRefs=@($user)
    Good {Assert-AiwAcceptanceBinding $ctx $userPackage $null} 'explicit-user-source-identity-bound-ceiling'
    $mixed=Clone $delegated;$mixed.actions+=@('SOURCE_WRITE')
    Bad {Assert-AiwAcceptanceBinding $ctx $mixed $null} 'RESULT_ACCEPT_PURE_PACKAGE_REQUIRED' 'acceptance-no-write-authority'
    foreach($field in @('continuationPlan','repairReviewPlan','repairReviewBinding','receiverBinding','transitionPlan')){
        $mixed=Clone $delegated;$mixed|Add-Member $field ([pscustomobject]@{})
        Bad {Assert-AiwAcceptanceBinding $ctx $mixed $null} 'RESULT_ACCEPT_CANNOT_REDELEGATE' ('acceptance-no-redelegation-'+$field)
    }
    $badCandidate=Clone $delegated;$badCandidate.acceptanceBinding.candidateObjects[0].identity='1|'+('A'*64)
    Bad {Assert-AiwAcceptanceBinding $ctx $badCandidate $null} 'EVIDENCE_CANDIDATE_DRIFT' 'delegation-wrong-candidate'
    $badEvidence=Clone $delegated;$badEvidence.acceptanceBinding.prerequisiteEvidenceRefs=@($failedRef)
    Bad {Assert-AiwAcceptanceBinding $ctx $badEvidence $null} 'EVIDENCE_NOT_SUCCESSFUL' 'delegation-failed-prerequisite'
    $reviewPackage=Package reviewer;$reviewPackage.actions=@('REVIEW_EXECUTE');$reviewPackage.profile='CRITICAL';$reviewPackage.reviewIndependence='INDEPENDENT';$reviewPackage|Add-Member candidateWriter owner;$reviewPackage|Add-Member materialContributors @('contributor')
    $null=Json '.ai-workspace/reports/review-package.json' $reviewPackage
    $reviewRecord=Record reviewer APPROVED;$reviewRecord|Add-Member authorizationRef (Ref '.ai-workspace/reports/review-package.json')
    $review=Typed $reviewRecord REVIEW_VERDICT
    Good {Read-AiwResultEvidence $ctx $review EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'independent-review-original-package-bound'
    $badReview=Clone $reviewPackage;$badReview.candidateWriter='reviewer';$null=Json '.ai-workspace/reports/bad-review-package.json' $badReview
    $badReviewRecord=Clone $reviewRecord;$badReviewRecord.authorizationRef=Ref '.ai-workspace/reports/bad-review-package.json';$badReviewRef=Typed $badReviewRecord REVIEW_VERDICT
    Bad {Read-AiwResultEvidence $ctx $badReviewRef EVIDENCE-001 @($candidate) $requirements} 'EVIDENCE_REVIEW_INDEPENDENCE' 'writer-cannot-review-own-critical-candidate'
    $critical=Clone $delegated;$critical.profile='CRITICAL'
    Bad {Assert-AiwAcceptanceBinding $ctx $critical $null} 'RESULT_ACCEPT_CRITICAL_REVIEW_REQUIRED' 'critical-acceptance-needs-real-review'
    $critical.acceptanceBinding.prerequisiteEvidenceRefs+=@($review)
    Good {Assert-AiwAcceptanceBinding $ctx $critical $null} 'critical-acceptance-with-bound-independent-review'

    # Historical profile labels do not qualify evidence for a current critical consumer.
    $legacyWeak=Clone $reviewPackage;$legacyWeak.profile='STANDARD';$legacyWeak.reviewIndependence='NOT_APPLICABLE'
    $legacyWeak.PSObject.Properties.Remove('candidateWriter');$legacyWeak.PSObject.Properties.Remove('materialContributors')
    $null=Json '.ai-workspace/reports/legacy-weak-review-package.json' $legacyWeak
    $legacyWeakRecord=Clone $reviewRecord;$legacyWeakRecord.authorizationRef=Ref '.ai-workspace/reports/legacy-weak-review-package.json'
    $legacyWeakRef=Typed $legacyWeakRecord REVIEW_VERDICT
    Good {Read-AiwResultEvidence $ctx $legacyWeakRef EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'legacy-standard-evidence-remains-readable-at-its-original-ceiling'
    $currentCritical=Clone $critical;$currentCritical.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$legacyWeakRef)
    Bad {Assert-AiwAcceptanceBinding $ctx $currentCritical $null} 'EVIDENCE_REVIEW_INDEPENDENCE' 'current-critical-acceptance-rejects-weak-legacy-standard-review'
    $legacyStrong=Clone $reviewPackage;$legacyStrong.profile='STANDARD'
    $null=Json '.ai-workspace/reports/legacy-strong-review-package.json' $legacyStrong
    $legacyStrongRecord=Clone $reviewRecord;$legacyStrongRecord.authorizationRef=Ref '.ai-workspace/reports/legacy-strong-review-package.json'
    $legacyStrongRef=Typed $legacyStrongRecord REVIEW_VERDICT
    $currentCritical.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$legacyStrongRef)
    Good {Assert-AiwAcceptanceBinding $ctx $currentCritical $null} 'current-critical-acceptance-reuses-sufficient-legacy-standard-facts'
    $priorOwner=Clone $legacyStrong;$priorOwner.owner='prior-owner';$priorOwner.issuer='prior-owner';$priorOwner.candidateWriter='prior-writer';$priorOwner.grantee='owner'
    $null=Json '.ai-workspace/reports/prior-owner-review-package.json' $priorOwner
    $priorOwnerRecord=Record owner APPROVED;$priorOwnerRecord|Add-Member authorizationRef (Ref '.ai-workspace/reports/prior-owner-review-package.json')
    $priorOwnerRef=Typed $priorOwnerRecord REVIEW_VERDICT;$currentCritical.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$priorOwnerRef)
    Bad {Assert-AiwAcceptanceBinding $ctx $currentCritical $null} 'EVIDENCE_REVIEW_INDEPENDENCE' 'current-owner-excluded-even-when-original-review-owner-differs'
    $currentIssuer=Clone $currentCritical;$currentIssuer.grantee='owner';$currentIssuer.issuer='owner'
    $priorOwner.grantee='current-issuer';$null=Json '.ai-workspace/reports/prior-issuer-review-package.json' $priorOwner
    $priorIssuerRecord=Record current-issuer APPROVED;$priorIssuerRecord|Add-Member authorizationRef (Ref '.ai-workspace/reports/prior-issuer-review-package.json')
    $priorIssuerRef=Typed $priorIssuerRecord REVIEW_VERDICT;$currentIssuer.issuer='current-issuer';$currentIssuer.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$priorIssuerRef)
    Bad {Assert-AiwAcceptanceBinding $ctx $currentIssuer $null} 'EVIDENCE_REVIEW_INDEPENDENCE' 'current-issuer-excluded-even-when-original-issuer-differs'

    $selfStage=Stage self SELF_CHECK @() @($candidate) @($self)
    $acceptStage=Stage accept RESULT_ACCEPT @('self') @($candidate) @()
    $userStage=Stage user USER_DECISION @('accept') @() @()
    $plan=Plan @($selfStage,$acceptStage,$userStage)
    # The actual task-card consumer must keep current plan validation and
    # phase-field structure while retaining the old matrix's constraints.
    foreach($gate in @('FALSE','TRUE')){
        $currentCard=$taskText+'- Phase gate: '+$gate+"`n"
        $run=Check-Card (With-Plan $currentCard $plan)
        True ($run.Code-eq0) ('current-plan-phase-'+$gate+'-without-legacy-matrix|'+$run.Text)
    }
    $currentCard=$taskText+"- Phase gate: TRUE`n"
    $run=Check-Card $currentCard
    True ($run.Code-ne0-and$run.Text.Contains('ACCEPTANCE_PLAN_REQUIRED')) 'current-phase-true-rejects-missing-plan'
    foreach($gate in @('INVALID','true',"TRUE`n- Phase gate: FALSE")){
        $run=Check-Card (With-Plan ($taskText+'- Phase gate: '+$gate+"`n") $plan)
        True ($run.Code-ne0-and$run.Text.Contains('PHASE_GATE_FIELD')) ('current-plan-rejects-malformed-phase-field-'+$gate.Replace("`n",'-'))
    }
    $badPlans=@()
    $bad=Clone $plan;$bad.schemaVersion=3;$badPlans+=@([pscustomobject]@{plan=$bad;reason='ACCEPTANCE_PLAN_SCHEMA'})
    $bad=Clone $plan;$bad.stages=@();$badPlans+=@([pscustomobject]@{plan=$bad;reason='ACCEPTANCE_PLAN_STAGE_COUNT'})
    $bad=Clone $plan;$bad.stages[0].kind='UNKNOWN';$badPlans+=@([pscustomobject]@{plan=$bad;reason='ACCEPTANCE_PLAN_STAGE_KIND'})
    $bad=Clone $plan;$bad.stages[0].evidenceRefs=@($review);$badPlans+=@([pscustomobject]@{plan=$bad;reason='ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND'})
    $bad=Clone $plan;$bad.stages[1].dependsOn=@('unknown');$badPlans+=@([pscustomobject]@{plan=$bad;reason='ACCEPTANCE_PLAN_UNKNOWN_DEPENDENCY'})
    $bad=Clone $plan;$bad.stages[1].dependsOn=@('self','self');$badPlans+=@([pscustomobject]@{plan=$bad;reason='ACCEPTANCE_PLAN_DUPLICATE_EDGE'})
    $bad=Clone $plan;$bad.stages[0].dependsOn=@('accept');$badPlans+=@([pscustomobject]@{plan=$bad;reason='ACCEPTANCE_PLAN_CYCLE'})
    foreach($case in $badPlans){
        $run=Check-Card (With-Plan $currentCard $case.plan)
        True ($run.Code-ne0-and$run.Text.Contains($case.reason)) ('current-phase-true-rejects-'+$case.reason+'|'+$run.Text)
    }
    $run=Check-Card (With-Plan ($taskText+"- Phase gate: FALSE`n") $badPlans[3].plan)
    True ($run.Code-ne0-and$run.Text.Contains('ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND')) 'phase-false-does-not-bypass-declared-plan-validation'
    $malformed=$currentCard+'```aiw-acceptance-plan'+"`n"+'not json'+"`n"+'```'+"`n"
    $run=Check-Card $malformed;True ($run.Code-ne0) 'current-phase-true-rejects-malformed-plan-json'
    $matrix=@'
- Technical evidence: READY; producer=owner; evidence=fixture technical result
- Domain contract check: NOT_APPLICABLE; reason=isolated structural fixture
- Runtime/platform check: NOT_APPLICABLE; reason=isolated structural fixture
- Project phase signoff: READY; controller=owner; evidence=fixture project signoff
- User final gate: NOT_APPLICABLE; reason=isolated structural fixture
- Acceptance order: TECHNICAL_EVIDENCE > DOMAIN_CONTRACT > RUNTIME_PLATFORM > PROJECT_SIGNOFF > USER_FINAL_GATE
'@+"`n"
    $run=Check-Card (With-Plan ($currentCard+$matrix) $plan)
    True ($run.Code-ne0-and$run.Text.Contains('ACCEPTANCE_PLAN_DUPLICATE_AUTHORITY')) 'current-plan-rejects-competing-legacy-matrix'
    $run=Check-Card ($currentCard+$matrix)
    True ($run.Code-ne0-and$run.Text.Contains('ACCEPTANCE_PLAN_REQUIRED')) 'current-phase-cannot-use-legacy-matrix-instead-of-plan'
    $legacyCard=$currentCard.Replace('- Task schema: 2.0.0','- Task schema: 1.13.0')
    $run=Check-Card ($legacyCard+$matrix);True ($run.Code-eq0) ('legacy-phase-matrix-still-valid|'+$run.Text)
    $run=Check-Card $legacyCard
    True ($run.Code-ne0-and$run.Text.Contains('PHASE_TECHNICAL_EVIDENCE')) 'legacy-phase-still-requires-matrix'
    $legacyWrong=$matrix.Replace('READY; producer=owner; evidence=fixture technical result','PENDING')
    $run=Check-Card ($legacyCard+$legacyWrong)
    True ($run.Code-ne0-and$run.Text.Contains('PHASE_DOMAIN_BEFORE_TECHNICAL')) 'legacy-phase-keeps-prerequisite-order-check'
    $legacyWrong=$matrix.Replace('controller=owner','controller=other')
    $run=Check-Card ($legacyCard+$legacyWrong)
    True ($run.Code-ne0-and$run.Text.Contains('PROJECT_SIGNOFF_OWNER')) 'legacy-phase-keeps-owner-signoff-check'
    Good {Assert-AiwAcceptanceBinding $ctx $delegated $plan} 'later-user-gate-does-not-block-internal-acceptance'
    Bad {Assert-AiwAcceptanceStages $ctx $plan EVIDENCE-001} 'ACCEPTANCE_STAGE_INCOMPLETE' 'unfinished-stages-block-final-success'
    $beforeUser=Clone $userStage;$beforeUser.dependsOn=@();$beforeAccept=Clone $acceptStage;$beforeAccept.dependsOn=@('self','user')
    $beforePlan=Plan @($selfStage,$beforeUser,$beforeAccept)
    Bad {Assert-AiwAcceptanceBinding $ctx $delegated $beforePlan} 'ACCEPTANCE_STAGE_INCOMPLETE' 'prior-user-gate-blocks-internal-acceptance'
    $beforeUser.candidateRef=@($user);$beforePlan=Plan @($selfStage,$beforeUser,$beforeAccept)
    Bad {Assert-AiwAcceptanceBinding $ctx $delegated $beforePlan} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'user-text-reference-alone-is-not-current-binding'
    $withUser=Clone $delegated;$withUser.acceptanceBinding.reservedUserDecisionRefs=@($user)
    Good {Assert-AiwAcceptanceBinding $ctx $withUser $beforePlan} 'prior-user-source-reserved-in-original-package'
    $plainPlan=Plan @($selfStage,$acceptStage)
    Good {Assert-AiwAcceptanceBinding $ctx $delegated $plainPlan} 'requirements-with-no-user-gate-do-not-invent-one'
    $cycle=Clone $selfStage;$cycle.dependsOn=@('accept')
    Bad {Plan @($cycle,$acceptStage)} 'ACCEPTANCE_PLAN_CYCLE' 'cycle-rejected'
    Bad {Plan @($selfStage,$selfStage)} 'ACCEPTANCE_PLAN_STAGE_ID' 'duplicate-stage-rejected'
    $wrong=Clone $acceptStage;$wrong.dependsOn=@('unknown')
    Bad {Plan @($selfStage,$wrong)} 'ACCEPTANCE_PLAN_UNKNOWN_DEPENDENCY' 'unknown-stage-rejected'
    $wrong=Clone $selfStage;$wrong.evidenceRefs=@($review)
    Bad {Plan @($wrong,$acceptStage)} 'ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND' 'review-not-self-check-stage-evidence'
    $wrong=Clone $userStage;$wrong.evidenceRefs=@($self)
    Bad {Plan @($selfStage,$acceptStage,$wrong)} 'ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND' 'user-gate-no-synthetic-fourth-evidence-kind'
    $wrong=Clone $acceptStage;$wrong|Add-Member status PASS
    Bad {Plan @($selfStage,$wrong)} 'EVIDENCE_FIELD_SET' 'no-duplicated-stage-pass-state'
    $missing=Clone $selfStage;$missing.candidateRef[0].path='not-created.md'
    Good {Plan @($missing,$acceptStage)} 'structure-check-does-not-read-historical-evidence'
    $null=Put 'design.md' '# Existing design artifact';$design=Ref 'design.md'
    $designStage=Stage design DESIGN @() @($design) @()
    $designPlan=Plan @($designStage)
    Good {Assert-AiwAcceptanceStages $ctx $designPlan EVIDENCE-001} 'design-stage-reads-actual-design-artifact'
    $null=Put 'knowledge.md' 'Knowledge material with bound original source.';$knowledge=Ref 'knowledge.md'
    $knowledgeRecord=Record;$knowledgeRecord.candidateObjects=@($knowledge);$knowledgeRef=Typed $knowledgeRecord SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $knowledgeRef EVIDENCE-001 @($knowledge) $requirements -RequireSuccess} 'knowledge-semantic-check-does-not-require-code-tests'
    Good {Assert-AiwReviewSelfCheck $ctx @($self) EVIDENCE-001 @($candidate) $plan} 'document-review-route-without-test-run'
    Bad {Assert-AiwReviewSelfCheck $ctx @() EVIDENCE-001 @($candidate)} 'REVIEW_SELF_CHECK_REQUIRED' 'review-route-needs-actual-self-check'
    Bad {Assert-AiwReviewSelfCheck $ctx @($failedRef) EVIDENCE-001 @($candidate)} 'EVIDENCE_NOT_SUCCESSFUL' 'review-route-rejects-failed-self-check'

    $acceptPath=Json '.ai-workspace/reports/accept-package.json' $delegated
    $accepted=Record delegate ACCEPTED;$accepted|Add-Member authorizationRef (Ref '.ai-workspace/reports/accept-package.json')
    $acceptedRef=Typed $accepted RESULT_ACCEPTANCE
    Good {Read-AiwResultEvidence $ctx $acceptedRef EVIDENCE-001 @($candidate) $requirements -RequireSuccess -AuthorizationIdentity (Id $acceptPath)} 'delegated-result-links-original-package'
    Bad {Read-AiwResultEvidence $ctx $acceptedRef EVIDENCE-001 @($candidate) $requirements -AuthorizationIdentity ('1|'+('F'*64))} 'EVIDENCE_AUTHORIZATION_DRIFT' 'wrong-original-package-rejected'
    $completeAccept=Clone $acceptStage;$completeAccept.evidenceRefs=@($acceptedRef);$completeUser=Clone $userStage;$completeUser.candidateRef=@($user)
    $complete=Plan @($selfStage,$completeAccept,$completeUser)
    Bad {Assert-AiwAcceptanceStages $ctx $complete EVIDENCE-001} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'accepted-internally-still-needs-later-user-gate'
    Good {Assert-AiwAcceptanceStages $ctx $complete EVIDENCE-001 '' @($user)} 'all-required-stages-complete'
    $run=Check-Package $ownerPackage;True ($run.Code-eq0) ('actual-checker-owner-'+$run.Text)
    $run=Check-Package $delegated;True ($run.Code-eq0) ('actual-checker-delegate-'+$run.Text)
    $currentUser=Clone $userPackage;$currentUser.decisionClass='PRODUCT_RESULT'
    $currentUser|Add-Member issuerControllerId controller;$currentUser|Add-Member issuerControllerEpoch 1;$currentUser|Add-Member controllerControlIdentity (Id $controllerPath);$currentUser.invalidatesOn+=@('CONTROLLER_EPOCH_CHANGE')
    $run=Check-Package $currentUser;True ($run.Code-eq0) ('actual-checker-explicit-user-source-'+$run.Text)
    $foreign=Clone $delegated;$foreign.issuer='unrelated-parent-owner';$run=Check-Package $foreign;True ($run.Code-ne0-and$run.Text.Contains('TASK_OWNER_MUST_OWN_TASK')) 'actual-checker-parent-is-not-child-authority'

    $receipt=[pscustomobject]@{taskId='EVIDENCE-001';actor='owner';actionKind='REVIEW_ROUTE';exactPaths=@($candidate.path);sourceLocators=[pscustomobject]@{projectRoot=$temp;frameworkRoot=$temp;taskRelativePath='.ai-workspace/tasks/active/EVIDENCE-001.md';authorizationPackagePath=$acceptPath};authorityContext=[pscustomobject]@{forbiddenScope=@();authorizationIdentity=(Id $acceptPath)}}
    $boundary=[pscustomobject]@{mode='ADMIT_ACTION';evidenceRefs=@();publicDecisionIdentity='NOT_REQUIRED'}
    Bad {Get-AiwBoundaryEvidence $receipt $boundary} 'TYPED_EVIDENCE_REQUIRED' 'boundary-rejects-obligation-strings-without-record'
    $boundary.evidenceRefs=@($self)
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'boundary-route-consumes-real-self-check'
    $receipt.actionKind='TEST_RUN';$boundary.mode='FINALIZE_OUTPUT';$boundary.evidenceRefs=@($failedRef)
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'boundary-reports-real-test-failure-without-blessing-success'
    $receipt.actionKind='RESULT_ACCEPT';$receipt.actor='delegate';$boundary.evidenceRefs=@($acceptedRef)
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'boundary-finalizes-delegated-acceptance'
    $receipt.actionKind='CONTROL_WRITE';$receipt.actor='owner';$boundary.evidenceRefs=@()
    $receipt.exactPaths=@('.ai-workspace/tasks/active/EVIDENCE-001.md')
    $closedText=$taskText.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+"`n- Closure outcome: SUCCESS`n"+'```aiw-acceptance-plan'+"`n"+($complete|ConvertTo-Json -Depth 50 -Compress)+"`n"+'```'+"`n"
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $closedText
    Bad {Get-AiwBoundaryEvidence $receipt $boundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'actual-boundary-close-rejects-pending-user-source'
    $boundary.publicDecisionIdentity=$user.identity
    Good {Get-AiwBoundaryEvidence $receipt $boundary} 'actual-boundary-close-with-user-identity'
    # A current critical closure also qualifies review facts reached through
    # a historical acceptance record, even without an explicit review stage.
    foreach($case in @(
        [pscustomobject]@{name='weak-legacy-review';review=$legacyWeakRef;success=$false},
        [pscustomobject]@{name='sufficient-legacy-review';review=$legacyStrongRef;success=$true},
        [pscustomobject]@{name='current-owner-review';review=$priorOwnerRef;success=$false}
    )){
        $historicalAccept=Clone $delegated;$historicalAccept.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$case.review)
        $historicalPath='.ai-workspace/reports/closure-'+$case.name+'-accept-package.json'
        $null=Json $historicalPath $historicalAccept
        $historicalRecord=Clone $accepted;$historicalRecord.authorizationRef=Ref $historicalPath
        $historicalRef=Typed $historicalRecord RESULT_ACCEPTANCE
        $criticalPlan=Clone $complete
        foreach($stage in $criticalPlan.stages){if($stage.kind-ceq'RESULT_ACCEPT'){$stage.evidenceRefs=@($historicalRef)}}
        $criticalText=$taskText.Replace('Profile: STANDARD;','Profile: CRITICAL;').Replace('profile=STANDARD;','profile=CRITICAL;').Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+"`n- Closure outcome: SUCCESS`n"+'```aiw-acceptance-plan'+"`n"+($criticalPlan|ConvertTo-Json -Depth 50 -Compress)+"`n"+'```'+"`n"
        $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $criticalText
        if($case.success){Good {Get-AiwBoundaryEvidence $receipt $boundary} ('critical-closure-reuses-'+$case.name)}
        else{Bad {Get-AiwBoundaryEvidence $receipt $boundary} 'EVIDENCE_REVIEW_INDEPENDENCE' ('critical-closure-rejects-'+$case.name)}
    }
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $closedText
    $boundary.publicDecisionIdentity='NOT_REQUIRED'
    $legacyClosed=$closedText.Replace("- Closure outcome: SUCCESS`n",'')
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $legacyClosed
    Bad {Get-AiwBoundaryEvidence $receipt $boundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'omitting-closure-outcome-cannot-bypass-stage-evidence'
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $closedText
    $parentText="# PARENT-001 — controller coordination`n- Owner: owner`n"
    $null=Put '.ai-workspace/tasks/active/PARENT-001.md' $parentText
    $parentReceipt=Clone $receipt;$parentReceipt.taskId='PARENT-001';$parentReceipt.sourceLocators.taskRelativePath='.ai-workspace/tasks/active/PARENT-001.md'
    Bad {Get-AiwBoundaryEvidence $parentReceipt $boundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'controller-closing-other-task-still-checks-its-user-gate'
    $boundary.publicDecisionIdentity=$user.identity
    Good {Get-AiwBoundaryEvidence $parentReceipt $boundary} 'controller-closing-other-task-with-complete-stage-evidence'
    # The active deletion must reach the real archive's normal acceptance gate.
    # Reuse the existing plan/user fixtures so a skip-all-missing mutation fails.
    $activeRelative='.ai-workspace/tasks/active/EVIDENCE-001.md';$archiveRelative='.ai-workspace/tasks/archive/EVIDENCE-001.md'
    $originalAuthText=[IO.File]::ReadAllText($acceptPath)
    $originalActiveIdentity=Id (Join-Path $temp $activeRelative)
    $archivePackage=Clone ($originalAuthText|ConvertFrom-Json -Depth 70)
    $archivePackage.exactPaths=@($activeRelative,$archiveRelative)
    $archivePackage.objectIdentities=@([pscustomobject]@{path=$activeRelative;identity=$originalActiveIdentity},[pscustomobject]@{path=$archiveRelative;identity='NEW'})
    $archiveAuthRelative='.ai-workspace/runtime/EVIDENCE-001/owner/archive-control-package.json'
    $archiveAuthPath=Json $archiveAuthRelative $archivePackage
    $archiveReceipt=Clone $parentReceipt;$archiveReceipt.exactPaths=@($activeRelative,$archiveRelative)
    $archiveReceipt.sourceLocators.authorizationPackagePath=$archiveAuthPath
    $archiveBoundary=Clone $boundary
    $archiveBoundary|Add-Member resultReceipts @()
    $null=Put $archiveRelative $closedText
    [IO.File]::Delete((Join-Path $temp $activeRelative))
    function Set-ArchivePostimages {
        $archiveBoundary.resultReceipts=@(('OBJECT_POSTIMAGE|'+$activeRelative+'|MISSING'),('OBJECT_POSTIMAGE|'+$archiveRelative+'|'+(Id (Join-Path $temp $archiveRelative))))
    }
    Set-ArchivePostimages
    $archiveBoundary.publicDecisionIdentity='NOT_REQUIRED'
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' 'deleted-active-still-enforces-archive-success-user-gate'
    $archiveBoundary.publicDecisionIdentity=$user.identity
    Good {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'deleted-active-with-real-closed-archive-and-complete-plan'
    foreach($closureOutcome in @('SUCCESS','CANCELLED','SUPERSEDED','legacy')){
        $outcomeText=if($closureOutcome-ceq'legacy'){$closedText.Replace("- Closure outcome: SUCCESS`n",'')}else{$closedText.Replace('Closure outcome: SUCCESS',('Closure outcome: '+$closureOutcome))}
        # Each case represents an unchanged closed-card move. Its original
        # active identity therefore equals the complete copied archive bytes.
        $null=Put $archiveRelative $outcomeText
        $archivePackage.objectIdentities[0].identity=Id (Join-Path $temp $archiveRelative)
        $null=Json $archiveAuthRelative $archivePackage
        Set-ArchivePostimages;$archiveBoundary.publicDecisionIdentity='NOT_REQUIRED'
        if($closureOutcome-cin@('CANCELLED','SUPERSEDED')){Good {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} ('archive-'+$closureOutcome+'-does-not-invent-success-acceptance')}
        else{Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'ACCEPTANCE_USER_DECISION_UNBOUND' ('archive-'+$closureOutcome+'-keeps-success-acceptance')}
    }
    $archivePackage.objectIdentities[0].identity=$originalActiveIdentity;$null=Json $archiveAuthRelative $archivePackage
    $null=Put $archiveRelative $closedText;Set-ArchivePostimages;$archiveBoundary.publicDecisionIdentity=$user.identity
    $missingPost=Clone $archiveBoundary;$missingPost.resultReceipts=@($missingPost.resultReceipts|Where-Object{$_-cnotlike('OBJECT_POSTIMAGE|'+$activeRelative+'|*')})
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $missingPost} 'ACCEPTANCE_ARCHIVE_DELETE_POSTIMAGE' 'archive-delete-needs-explicit-missing-postimage'
    $duplicatePost=Clone $archiveBoundary;$duplicatePost.resultReceipts+=('OBJECT_POSTIMAGE|'+$activeRelative+'|MISSING')
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $duplicatePost} 'ACCEPTANCE_ARCHIVE_DELETE_POSTIMAGE' 'archive-delete-rejects-duplicate-missing-postimage'
    $noTarget=Clone $archiveReceipt;$noTarget.exactPaths=@($activeRelative)
    $noTargetBoundary=Clone $archiveBoundary;$noTargetBoundary.resultReceipts=@(('OBJECT_POSTIMAGE|'+$activeRelative+'|MISSING'))
    Bad {Get-AiwBoundaryEvidence $noTarget $noTargetBoundary} 'ACCEPTANCE_ARCHIVE_TARGET_REQUIRED' 'archive-delete-cannot-omit-target-from-exact-scope'
    $archivePackage.objectIdentities[0].identity='NEW';$null=Json $archiveAuthRelative $archivePackage
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'ACCEPTANCE_ARCHIVE_DELETE_PREIMAGE' 'missing-new-active-is-not-an-admitted-delete'
    $archivePackage.objectIdentities[0].identity=$originalActiveIdentity;$null=Json $archiveAuthRelative $archivePackage
    $null=Put $archiveRelative ($closedText.Replace('# EVIDENCE-001','# WRONG-001'));Set-ArchivePostimages
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'ACCEPTANCE_ARCHIVE_PREIMAGE_DRIFT' 'other-card-archive-rejects-changed-body-without-guessing-id-from-basename'
    $null=Put $archiveRelative $taskText;Set-ArchivePostimages
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'ACCEPTANCE_ARCHIVE_NOT_CLOSED' 'archive-delete-rejects-active-target'
    $null=Put $archiveRelative $closedText;Set-ArchivePostimages
    $null=Put $archiveRelative ($closedText+'third-party')
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'EVIDENCE_IDENTITY_DRIFT' 'archive-delete-rejects-third-party-target-bytes'
    [IO.File]::Delete((Join-Path $temp $archiveRelative))
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'EVIDENCE_IDENTITY_DRIFT' 'archive-delete-rejects-missing-archive'
    $directoryActive=Join-Path $temp $activeRelative;$null=[IO.Directory]::CreateDirectory($directoryActive)
    Bad {Get-AiwBoundaryEvidence $archiveReceipt $archiveBoundary} 'EVIDENCE_NOT_FILE' 'archive-delete-rejects-directory-active'
    [IO.Directory]::Delete($directoryActive)
    $null=Put ([IO.Path]::GetRelativePath($temp,$acceptPath).Replace('\','/')) $originalAuthText
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
    $userGrantPath=Json '.ai-workspace/reports/user-grant-package.json' $currentUser
    $userReceipt=Clone $receipt;$userReceipt.actionKind='RESULT_ACCEPT';$userReceipt.actor='delegate';$userReceipt.exactPaths=@($candidate.path);$userReceipt.sourceLocators.authorizationPackagePath=$userGrantPath;$userReceipt.authorityContext.authorizationIdentity=Id $userGrantPath
    $boundary.mode='ADMIT_ACTION';$boundary.publicDecisionIdentity='NOT_REQUIRED'
    Bad {Get-AiwBoundaryEvidence $userReceipt $boundary} 'RESULT_ACCEPT_CURRENT_USER_DECISION_UNBOUND' 'user-exception-needs-current-boundary-decision'
    $boundary.publicDecisionIdentity=$user.identity
    Good {Get-AiwBoundaryEvidence $userReceipt $boundary} 'user-exception-current-boundary-decision-bound'
    $committed=Clone $accepted;$committed|Add-Member acceptedCommit ('A'*40);$committedRef=Typed $committed RESULT_ACCEPTANCE
    Good {Assert-AiwPushAcceptance $ctx $committedRef EVIDENCE-001 @($candidate) ('A'*40)} 'push-consumes-typed-accepted-commit'
    Bad {Assert-AiwPushAcceptance $ctx $committedRef EVIDENCE-001 @($candidate) ('B'*40)} 'PUSH_ACCEPTED_COMMIT_DRIFT' 'push-wrong-commit-rejected'
    Bad {Assert-AiwPushAcceptance $ctx $acceptedRef EVIDENCE-001 @($candidate) ('A'*40)} 'PUSH_ACCEPTED_COMMIT_DRIFT' 'design-acceptance-no-fictional-commit-for-push'
    $legacyAcceptance=Clone $delegated;$legacyAcceptance.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$legacyWeakRef)
    $null=Json '.ai-workspace/reports/legacy-accept-package.json' $legacyAcceptance
    $legacyAccepted=Clone $committed;$legacyAccepted.authorizationRef=Ref '.ai-workspace/reports/legacy-accept-package.json'
    $legacyAcceptedRef=Typed $legacyAccepted RESULT_ACCEPTANCE
    Bad {Assert-AiwPushAcceptance $ctx $legacyAcceptedRef EVIDENCE-001 @($candidate) ('A'*40) -RequireReview} 'EVIDENCE_REVIEW_INDEPENDENCE' 'current-critical-push-rejects-weak-legacy-review'
    $legacyAcceptance.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$legacyStrongRef)
    $null=Json '.ai-workspace/reports/legacy-accept-package.json' $legacyAcceptance;$legacyAccepted.authorizationRef=Ref '.ai-workspace/reports/legacy-accept-package.json'
    $legacyAcceptedRef=Typed $legacyAccepted RESULT_ACCEPTANCE
    Good {Assert-AiwPushAcceptance $ctx $legacyAcceptedRef EVIDENCE-001 @($candidate) ('A'*40) -RequireReview} 'current-critical-push-reuses-sufficient-legacy-review-facts'
    foreach($excluded in @('owner','current-issuer')){
        $legacyAcceptance.acceptanceBinding.prerequisiteEvidenceRefs=@($self,$(if($excluded-ceq'owner'){$priorOwnerRef}else{$priorIssuerRef}))
        $null=Json '.ai-workspace/reports/legacy-accept-package.json' $legacyAcceptance;$legacyAccepted.authorizationRef=Ref '.ai-workspace/reports/legacy-accept-package.json';$legacyAcceptedRef=Typed $legacyAccepted RESULT_ACCEPTANCE
        Bad {Assert-AiwPushAcceptance $ctx $legacyAcceptedRef EVIDENCE-001 @($candidate) ('A'*40) -RequireReview -ExcludedReviewActors @($excluded)} 'EVIDENCE_REVIEW_INDEPENDENCE' ('current-critical-push-excludes-actual-'+$excluded)
    }
    $originalCandidate=$candidate;$originalSelf=$self
    foreach($case in @('delete-only','mixed')){
        $removedPath=Join-Path $temp 'removed.md';$null=Put 'removed.md' 'Candidate removed by the fixture action.';[IO.File]::Delete($removedPath)
        $absent=[pscustomobject]@{path='removed.md';identity='MISSING'}
        $candidate=@(if($case-ceq'mixed'){$originalCandidate;$absent}else{$absent})
        function Candidate-Package([string]$Actor,[string]$Action){
            $p=Package $Actor;$p.actions=@($Action)
            $p.objectIdentities=@($candidate|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$(if($_.identity-ceq'MISSING'){'NEW'}else{$_.identity})}})
            return $p
        }
        $selfRecord=Record;$selfRecord.checks+=@($observedCommandCheck);$self=Typed $selfRecord SELF_CHECK
        $selfPackage=Candidate-Package owner TEST_RUN;$selfPackagePath=Json ".ai-workspace/reports/$case-self-package.json" $selfPackage
        $caseReceipt=Clone $receipt;$caseReceipt.exactPaths=@($candidate.path);$caseReceipt.actor='owner';$caseReceipt.actionKind='TEST_RUN'
        $caseReceipt.sourceLocators.authorizationPackagePath=$selfPackagePath;$caseReceipt.authorityContext.authorizationIdentity=Id $selfPackagePath
        $caseBoundary=[pscustomobject]@{mode='FINALIZE_OUTPUT';evidenceRefs=@($self);publicDecisionIdentity='NOT_REQUIRED'}
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-self-check-preserves-absent-candidate')
        $routePackage=Candidate-Package owner REVIEW_ROUTE;$routePath=Json ".ai-workspace/reports/$case-route-package.json" $routePackage
        $caseReceipt.actionKind='REVIEW_ROUTE';$caseReceipt.sourceLocators.authorizationPackagePath=$routePath;$caseReceipt.authorityContext.authorizationIdentity=Id $routePath;$caseBoundary.mode='ADMIT_ACTION'
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-route-consumes-full-candidate-self-check')
        $reviewPackage=Candidate-Package reviewer REVIEW_EXECUTE;$reviewPackage.reviewIndependence='INDEPENDENT';$reviewPackage|Add-Member candidateWriter owner;$reviewPackage|Add-Member materialContributors @()
        $reviewPath=Json ".ai-workspace/reports/$case-review-package.json" $reviewPackage
        $reviewRecord=Record reviewer APPROVED;$reviewRecord|Add-Member authorizationRef ([pscustomobject]@{path=$reviewPath;identity=(Id $reviewPath)})
        $caseReview=Typed $reviewRecord REVIEW_VERDICT
        $caseReceipt.actionKind='REVIEW_EXECUTE';$caseReceipt.actor='reviewer';$caseReceipt.sourceLocators.authorizationPackagePath=$reviewPath;$caseReceipt.authorityContext.authorizationIdentity=Id $reviewPath
        $caseBoundary.mode='FINALIZE_OUTPUT';$caseBoundary.evidenceRefs=@($caseReview)
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-review-binds-original-NEW-to-observed-MISSING')
        $acceptPackage=Candidate-Package delegate RESULT_ACCEPT;Binding $acceptPackage;$acceptPackage.acceptanceBinding.prerequisiteEvidenceRefs+=@($caseReview)
        $acceptPathForCase=Json ".ai-workspace/reports/$case-accept-package.json" $acceptPackage
        $acceptRecord=Record delegate ACCEPTED;$acceptRecord|Add-Member authorizationRef ([pscustomobject]@{path=$acceptPathForCase;identity=(Id $acceptPathForCase)})
        $caseAcceptance=Typed $acceptRecord RESULT_ACCEPTANCE
        $caseReceipt.actionKind='RESULT_ACCEPT';$caseReceipt.actor='delegate';$caseReceipt.sourceLocators.authorizationPackagePath=$acceptPathForCase;$caseReceipt.authorityContext.authorizationIdentity=Id $acceptPathForCase
        $caseBoundary.mode='ADMIT_ACTION';$caseBoundary.evidenceRefs=@()
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-delegated-acceptance-admission')
        $caseBoundary.mode='FINALIZE_OUTPUT';$caseBoundary.evidenceRefs=@($caseAcceptance)
        Good {Get-AiwBoundaryEvidence $caseReceipt $caseBoundary} ($case+'-acceptance-finalizes-full-candidate-set')
        $casePlan=Plan @((Stage self SELF_CHECK @() $candidate @($self)),(Stage review RESULT_REVIEW @('self') $candidate @($caseReview)),(Stage accept RESULT_ACCEPT @('review') $candidate @($caseAcceptance)))
        Good {Assert-AiwAcceptanceStages $ctx $casePlan EVIDENCE-001} ($case+'-all-result-stages-consume-absent-state')
        True (Test-Json -Json ($selfRecord|ConvertTo-Json -Depth 50) -SchemaFile (Join-Path $versionRoot 'EVIDENCE_RECORD_SCHEMA.json')) ($case+'-record-schema-describes-absent-state')
        True (Test-Json -Json ($casePlan|ConvertTo-Json -Depth 50) -SchemaFile (Join-Path $versionRoot 'ACCEPTANCE_PLAN_SCHEMA.json')) ($case+'-plan-schema-describes-absent-state')
        if($case-ceq'mixed'){
            $omitted=Clone $selfRecord;$omitted.candidateObjects=@($originalCandidate);$omittedRef=Typed $omitted SELF_CHECK
            Bad {Read-AiwResultEvidence $ctx $omittedRef EVIDENCE-001 $candidate $requirements} 'EVIDENCE_CANDIDATE_SET' 'mixed-candidate-cannot-omit-deletion'
        }
        $null=Put 'removed.md' 'Unexpected reappearance.'
        Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 $candidate $requirements} 'EVIDENCE_IDENTITY_DRIFT' ($case+'-unexpected-reappearance-rejected')
        [IO.File]::Delete($removedPath);$null=[IO.Directory]::CreateDirectory($removedPath)
        Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 $candidate $requirements} 'EVIDENCE_NOT_FILE' ($case+'-directory-replacement-rejected')
        [IO.Directory]::Delete($removedPath)
    }
    $missingRecord=Record;$missingRecord.candidateObjects=@([pscustomobject]@{path='absent-parent/child.md';identity='MISSING'});$missingRef=Typed $missingRecord SELF_CHECK
    Good {Read-AiwResultEvidence $ctx $missingRef EVIDENCE-001 $missingRecord.candidateObjects $requirements} 'missing-parent-remains-observable-candidate-absence'
    $forgedMissing=Clone $missingRecord;$forgedMissing.candidateObjects[0].path='result.md';$forgedMissingRef=Typed $forgedMissing SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $forgedMissingRef EVIDENCE-001 $forgedMissing.candidateObjects $requirements} 'EVIDENCE_IDENTITY_DRIFT' 'present-file-cannot-be-reported-missing'
    $forbiddenMissing=Clone $missingRecord;$forbiddenMissing.candidateObjects[0].path='protected.txt';$forbiddenMissingRef=Typed $forbiddenMissing SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $forbiddenMissingRef EVIDENCE-001 $forbiddenMissing.candidateObjects $requirements} 'EVIDENCE_PATH_FORBIDDEN' 'missing-candidate-still-checks-protection-before-existence'
    $badRequirement=Clone $missingRecord;$badRequirement.requirementsRef.identity='MISSING';$badRequirementRef=Typed $badRequirement SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $badRequirementRef EVIDENCE-001 $badRequirement.candidateObjects $badRequirement.requirementsRef} 'EVIDENCE_IDENTITY_FORMAT' 'requirements-cannot-use-missing-candidate-sentinel'
    $missingCarrier=[pscustomobject]@{kind='SELF_CHECK';path='missing-evidence.json';identity='MISSING'}
    Bad {Read-AiwResultEvidence $ctx $missingCarrier EVIDENCE-001 $candidate $requirements} 'EVIDENCE_IDENTITY_FORMAT' 'evidence-carrier-must-have-real-bytes'
    Bad {Plan @((Stage user USER_DECISION @() $missingRecord.candidateObjects @()))} 'EVIDENCE_IDENTITY_FORMAT' 'user-decision-is-not-a-deleted-candidate'
    $linkTarget=Join-Path $temp 'junction-target';$linkPath=Join-Path $temp 'removed.md';$null=[IO.Directory]::CreateDirectory($linkTarget)
    $null=New-Item -ItemType Junction -Path $linkPath -Target $linkTarget
    try{Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 $candidate $requirements} 'EVIDENCE_PATH_REPARSE' 'reparse-replacement-is-not-absence'}finally{[IO.Directory]::Delete($linkPath)}
    $candidate=$originalCandidate;$self=$originalSelf

    # Safe equivalence uses the real consumer, including the control/repository
    # distinction. Same bytes at another root are never the same candidate.
    $absoluteCandidate=Clone $candidate;$absoluteCandidate.path=Join-Path $temp $candidate.path
    $absoluteRequirements=Clone $requirements;$absoluteRequirements.path=Join-Path $temp $requirements.path
    Good {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($absoluteCandidate) $absoluteRequirements -RequireSuccess} 'safe-absolute-relative-reference-equivalence'
    $slashCandidate=Clone $absoluteCandidate;$slashCandidate.path=$slashCandidate.path.Replace('\','/')
    Good {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($slashCandidate) $requirements -RequireSuccess} 'native-separator-reference-equivalence'
    $otherRoot=Join-Path $temp 'other-repository';$null=[IO.Directory]::CreateDirectory($otherRoot)
    [IO.File]::Copy((Join-Path $temp $candidate.path),(Join-Path $otherRoot $candidate.path))
    $splitContext=New-AiwEvidenceContext $temp $otherRoot
    Bad {Read-AiwResultEvidence $splitContext $self EVIDENCE-001 @($absoluteCandidate) $requirements} 'EVIDENCE_CANDIDATE_DRIFT' 'same-name-and-bytes-in-other-root-not-equivalent'
    foreach($unsafe in @('protected.txt','../escape.txt','result.md:stream','C:result.md')){
        $unsafeCandidate=Clone $candidate;$unsafeCandidate.path=$unsafe
        $reason=if($unsafe-ceq'protected.txt'){'EVIDENCE_PATH_FORBIDDEN'}else{'EVIDENCE_PATH_INVALID'}
        Bad {Read-AiwResultEvidence $ctx $self EVIDENCE-001 @($unsafeCandidate) $requirements} $reason ('equivalence-rejects-before-identity-'+$unsafe)
    }
    $aliasRecord=Record;$aliasRecord.candidateObjects=@($candidate,$absoluteCandidate);$aliasRef=Typed $aliasRecord SELF_CHECK
    Bad {Read-AiwResultEvidence $ctx $aliasRef EVIDENCE-001 $aliasRecord.candidateObjects $requirements} 'EVIDENCE_DUPLICATE_REF' 'physical-alias-cannot-duplicate-candidate'

    # Real isolated DISCOVER/ADMIT/FINALIZE results supply historical proof.
    # No new field is inserted into any original typed record, plan or package.
    Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
    $historyFramework=Join-Path $temp 'history-framework'
    $historyVersion=New-AiwTestMechanismFixture ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))) $historyFramework (Join-Path $PSScriptRoot 'test-groups.json')
    $null=Json '.ai-workspace/corrections.json' ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='evidence-fixture';corrections=@()})
    $null=Json '.ai-workspace/process-policy.json' ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='evidence-fixture';rules=@()})
    $null=Put '.ai-workspace/BOOTSTRAP.md' "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
    $null=Put 'AGENTS.md' 'Original fixture project instructions.'
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText
    $historyContext=New-AiwEvidenceContext $temp '' $historyFramework
    function History-Process($Value,[string]$Name){
        $path=Json ('.ai-workspace/runtime/EVIDENCE-001/owner/history-'+$Name+'.json') $Value
        $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $historyVersion 'scripts/resolve-process-requirements.ps1'),'-InputPath',$path,'-AsJson') -WorkingDirectory $temp -GroupId 'result-history'
        if($run.Code-ne0){throw ('HISTORY_PROCESS_FAILED|'+$Name+'|'+($run.Output-join "`n"))}
        $value=($run.Output-join "`n")|ConvertFrom-Json -Depth 100
        $null=Json ('.ai-workspace/runtime/EVIDENCE-001/owner/history-'+$Name+'-result.json') $value
        return $value
    }
    function History-Finalize($Package,$Record,[string]$Kind,[string]$Name,[scriptblock]$BeforeFinalize=$null){
        if($Kind-ceq'SELF_CHECK'-and$Package.actions.Count-eq1-and$Package.actions[0]-ceq'TEST_RUN'){$Record.checks+=@(Clone $observedCommandCheck)}
        $relative='.ai-workspace/runtime/EVIDENCE-001/owner/history-'+$Name+'-package.json'
        $packagePath=Json $relative $Package
        if($Kind-cne'SELF_CHECK'){$Record|Add-Member authorizationRef (Ref $relative) -Force}
        $discover=[ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=@{mode='FULL'};projectRoot=$temp;frameworkRoot=$historyFramework;taskPath=$taskPath;expectedProjectConfigIdentity=(Id $configPath);expectedCorrectionsIdentity=(Id (Join-Path $temp '.ai-workspace/corrections.json'));expectedTaskIdentity=(Id $taskPath);observedActor=$Package.grantee;capabilities=@();exactPaths=$Package.exactPaths;forbiddenPaths=@('protected.txt');protectedPaths=@();authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Id $packagePath);userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=@{schemaVersion=2;objective='Isolated original result for historical evidence regression';requestedActionKind=$Package.actions[0];requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=$Package.exactPaths;capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:software')};workType=@{state='KNOWN';values=@('aiw:verification')};deliverableType=@{state='KNOWN';values=@('aiw:test-result')};stage=@{state='KNOWN';values=@('aiw:verification')}}}}
        if($Package.schemaVersion-eq4){$discover['executionTargetRef']=$Package.executionTargetRef}
        $resolved=History-Process $discover ($Name+'-discover')
        $receiptRelative='.ai-workspace/runtime/EVIDENCE-001/owner/history-'+$Name+'-compact.json';$receiptPath=Json $receiptRelative $resolved.compactReceipt
        # Protocol fixture obligations: these isolated facts are established by
        # fixture construction, not claims about a real product or human review.
        $prep=@($resolved.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique)
        $boundary=[pscustomobject]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=$prep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
        $null=History-Process $boundary ($Name+'-admit')
        if($null-ne$BeforeFinalize){$null=& $BeforeFinalize $Record}
        $typed=Typed $Record $Kind
        $boundary.mode='FINALIZE_OUTPUT';$boundary.evidenceRefs=@($typed)
        $boundary.resultReceipts=@($resolved.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@($Record.candidateObjects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.identity})
        $actual=History-Process $boundary ($Name+'-finalize')
        return [pscustomobject]@{typed=$typed;record=$Record;package=$Package;pair=[pscustomobject]@{inputRef=(Ref ('.ai-workspace/runtime/EVIDENCE-001/owner/history-'+$Name+'-finalize.json'));resultRef=(Ref ('.ai-workspace/runtime/EVIDENCE-001/owner/history-'+$Name+'-finalize-result.json'))};result=$actual}
    }
    $historyPackage=Package;$historyPackage.actions=@('TEST_RUN')
    $historyRecord=Record;$historyRecord.evidenceLocators+=@($candidate);$historyRecord.checks[0].evidenceLocators+=@($absoluteCandidate)
    $historicalSelf=History-Finalize $historyPackage $historyRecord SELF_CHECK 'self'
    $historyAcceptPackage=Package;Binding $historyAcceptPackage;$historyAcceptPackage.acceptanceBinding.prerequisiteEvidenceRefs=@($historicalSelf.typed)
    $historicalAccept=History-Finalize $historyAcceptPackage (Record owner ACCEPTED) RESULT_ACCEPTANCE 'accept'
    $originalFinalizes=@($historicalSelf.pair,$historicalAccept.pair)
    $historicalPlan=Plan @((Stage accepted RESULT_ACCEPT @() @($candidate) @($historicalAccept.typed)))
    $null=Put 'result.md' 'A later legally changed product.';$null=Put 'AGENTS.md' 'Later legally changed instructions.'
    Good {Read-AiwResultEvidence $historyContext $historicalSelf.typed EVIDENCE-001 @($candidate) $requirements -RequireSuccess -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $originalFinalizes} 'completed-history-survives-live-product-and-agents-change-including-ordinary-locators'
    Good {Assert-AiwAcceptanceStages $historyContext $historicalPlan EVIDENCE-001 -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $originalFinalizes} 'plan-consumes-real-original-finalizes-through-recursive-acceptance'
    $currentCandidate=Ref 'result.md';$currentAcceptance=Clone $historyAcceptPackage
    $currentAcceptance.objectIdentities=@($currentCandidate);$currentAcceptance.acceptanceBinding.candidateObjects=@($currentCandidate)
    Good {Assert-AiwAcceptanceBinding $historyContext $currentAcceptance $null -PrerequisiteEvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $originalFinalizes} 'current-candidate-can-consume-separately-proved-historical-prerequisite'
    $null=Put 'result.md' 'An unaccepted concurrent candidate drift.'
    Bad {Assert-AiwAcceptanceBinding $historyContext $currentAcceptance $null -PrerequisiteEvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $originalFinalizes} 'EVIDENCE_IDENTITY_DRIFT' 'historical-prerequisite-cannot-exempt-current-acceptance-candidate'
    $null=Put 'result.md' 'A later legally changed product.'
    # Current consumers declare history on their own binding/plan. No optional
    # reader parameter is supplied to the real checker or process boundaries.
    $declaredAcceptance=Clone $currentAcceptance
    $declaredAcceptance.acceptanceBinding|Add-Member prerequisiteConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=$originalFinalizes})
    $savedCandidate=$candidate;$candidate=$currentCandidate
    try{
        $checked=Check-Package $currentAcceptance
        $null=Json '.ai-workspace/runtime/EVIDENCE-001/owner/absent-consumption-checker.json' $checked
        Write-Output ('CHECKER|absent-consumption|'+($checked|ConvertTo-Json -Compress))
        True ($checked.Code-ne0-and$checked.Text.Contains('EVIDENCE_CANDIDATE_DRIFT')) 'native-checker-absent-consumption-remains-current'
        $checked=Check-Package $declaredAcceptance
        $null=Json '.ai-workspace/runtime/EVIDENCE-001/owner/declared-consumption-checker.json' $checked
        Write-Output ('CHECKER|declared-consumption|'+($checked|ConvertTo-Json -Compress))
        True ($checked.Code-eq0) ('native-checker-consumes-declared-history-'+$checked.Text)
        $declaredRecord=Record owner ACCEPTED
        $declaredResult=History-Finalize $declaredAcceptance $declaredRecord RESULT_ACCEPTANCE 'declared-current-accept'
        True ($declaredResult.result.status-ceq'PASS') 'native-current-accept-DISCOVER-ADMIT-FINALIZE-consumes-history'
        $null=Put 'result.md' 'Concurrent change after the declared current acceptance.'
        $checked=Check-Package $declaredAcceptance
        $null=Json '.ai-workspace/runtime/EVIDENCE-001/owner/current-candidate-drift-checker.json' $checked
        Write-Output ('CHECKER|current-candidate-drift|'+($checked|ConvertTo-Json -Compress))
        True ($checked.Code-ne0-and$checked.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) 'native-checker-history-does-not-exempt-current-candidate'
    }finally{$candidate=$savedCandidate;$null=Put 'result.md' 'A later legally changed product.'}
    $declaredPlan=Clone $historicalPlan
    $declaredPlan.stages[0]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=$originalFinalizes})
    $declaredPlan=Plan $declaredPlan.stages
    Good {Assert-AiwAcceptanceStages $historyContext $declaredPlan EVIDENCE-001} 'typed-stage-declaration-reaches-recursive-history'
    $badPlan=Clone $declaredPlan;$badPlan.stages[0].evidenceConsumption.purpose='CURRENT_CANDIDATE'
    Bad {Plan $badPlan.stages} 'EVIDENCE_CURRENT_HISTORY_REFS' 'current-stage-rejects-useless-history-refs'
    foreach($kind in @('DESIGN','USER_DECISION')){
        $badStage=Stage 'untyped' $kind @() @($requirements) @()
        $badStage|Add-Member evidenceConsumption $declaredPlan.stages[0].evidenceConsumption
        Bad {Plan @($badStage)} 'ACCEPTANCE_PLAN_STAGE_CONSUMPTION_KIND' ($kind+'-cannot-declare-historical-exemption')
    }
    $schemaPath=Join-Path $versionRoot 'ACCEPTANCE_PLAN_SCHEMA.json'
    True (Test-Json -Json ($declaredPlan|ConvertTo-Json -Depth 70) -SchemaFile $schemaPath) 'declared-stage-matches-published-json-schema'
    $badPlan=Clone $declaredPlan;$badPlan.stages[0].evidenceConsumption.originalFinalize=@($historicalAccept.pair)
    Bad {Assert-AiwAcceptanceStages $historyContext $badPlan EVIDENCE-001} 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND' 'declared-recursion-needs-every-original-finalize'
    $badPlan=Clone $declaredPlan;$badPlan.stages[0].candidateRef=@($currentCandidate)
    Bad {Assert-AiwAcceptanceStages $historyContext $badPlan EVIDENCE-001} 'EVIDENCE_CANDIDATE_DRIFT' 'declared-stage-cannot-rebind-old-result-to-new-scope'
    $protectedHistory=New-AiwEvidenceContext $temp '' $historyFramework @('result.md')
    Bad {Assert-AiwAcceptanceStages $protectedHistory $declaredPlan EVIDENCE-001} 'EVIDENCE_PATH_FORBIDDEN' 'declared-stage-retains-current-protection'
    $badAcceptance=Clone $declaredAcceptance;$badAcceptance.acceptanceBinding.prerequisiteConsumption.purpose='CURRENT_CANDIDATE'
    Bad {Assert-AiwAcceptanceBinding $historyContext $badAcceptance $null} 'EVIDENCE_CURRENT_HISTORY_REFS' 'current-prerequisite-rejects-useless-history-refs'
    # Real ordinary current-task CONTROL action closes SUCCESS through both
    # TaskClosure's acceptance pre-read and its full stage validation.
    $closePackage=Package;$closePackage.actions=@('CONTROL_WRITE')
    $closePackage.exactPaths=@('.ai-workspace/tasks/active/EVIDENCE-001.md');$closePackage.objectIdentities=@((Ref $closePackage.exactPaths[0]))
    $closePackagePath=Json '.ai-workspace/runtime/EVIDENCE-001/owner/history-close-package.json' $closePackage
    $closeDiscover=Get-Content -LiteralPath (Join-Path $temp '.ai-workspace/runtime/EVIDENCE-001/owner/history-declared-current-accept-discover.json') -Raw|ConvertFrom-Json -Depth 100
    $closeDiscover.authorizationPackagePath=$closePackagePath;$closeDiscover.expectedAuthorizationIdentity=Id $closePackagePath
    $closeDiscover.exactPaths=$closePackage.exactPaths;$closeDiscover.intentEnvelope.pathHints=$closePackage.exactPaths;$closeDiscover.intentEnvelope.requestedActionKind='CONTROL_WRITE'
    $closureDiscoveryResult=History-Process $closeDiscover 'close-discover'
    $closeCompact=Json '.ai-workspace/runtime/EVIDENCE-001/owner/history-close-compact.json' $closureDiscoveryResult.compactReceipt
    $closeBoundary=[pscustomobject]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$closeCompact;expectedDiscoverReceiptIdentity=(Id $closeCompact);preparationReceipts=@($closureDiscoveryResult.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $null=History-Process $closeBoundary 'close-admit'
    try{
        $closedTaskText=$taskText.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+"`n- Closure outcome: SUCCESS`n- Closure basis: Original completed acceptance consumed by its declared historical purpose.`n- Output disposition: READY; isolated fixture only.`n- Git disposition: DEFERRED; fixture only.`n- Unresolved obligations: NONE`n- Writer: RELEASED`n- Reviewer: RELEASED`n- Authorization: RELEASED`n"
        $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' (With-Plan $closedTaskText $declaredPlan)
        $closeBoundary.mode='FINALIZE_OUTPUT';$closeBoundary.resultReceipts=@($closureDiscoveryResult.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$closePackage.exactPaths[0]+'|'+(Id $taskPath))
        $closedResult=History-Process $closeBoundary 'close-finalize'
        True ($closedResult.status-ceq'PASS') 'native-ordinary-SUCCESS-closure-consumes-declared-recursive-history'
    }finally{$null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' $taskText}
    Bad {Read-AiwResultEvidence $historyContext $historicalSelf.typed EVIDENCE-001 @($candidate) $requirements -RequireSuccess} 'EVIDENCE_IDENTITY_DRIFT' 'current-candidate-remains-strict-after-historical-success'
    Bad {Assert-AiwAcceptanceBinding $historyContext $historyAcceptPackage $null -Historical} 'EVIDENCE_IDENTITY_DRIFT' 'old-historical-switch-does-not-authorize-success-exemption'
    Bad {Read-AiwResultEvidence $historyContext $historicalSelf.typed EVIDENCE-001 @($candidate) $requirements -RequireSuccess -FrozenCandidateEvidence -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $originalFinalizes} 'EVIDENCE_FROZEN_SUCCESS_GATE_DENIED' 'continuation-freeze-cannot-become-historical-success'
    Bad {Read-AiwResultEvidence $historyContext $historicalSelf.typed EVIDENCE-001 @($candidate) $requirements -EvidencePurpose HISTORICAL_SUCCESS} 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND' 'unclosed-history-without-original-finalize-rejected'
    foreach($original in @($historicalSelf.typed,$historicalSelf.pair.inputRef,$historicalSelf.pair.resultRef,$requirements,(Ref '.ai-workspace/runtime/EVIDENCE-001/owner/history-self-package.json'))){
        $path=Join-Path $temp $original.path;$bytes=[IO.File]::ReadAllBytes($path)
        try{
            [IO.File]::AppendAllText($path,' ', $utf8)
            Bad {Read-AiwResultEvidence $historyContext $historicalSelf.typed EVIDENCE-001 @($candidate) $requirements -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $originalFinalizes} 'EVIDENCE_IDENTITY_DRIFT' ('historical-original-drift-'+[IO.Path]::GetFileName($path))
        }finally{[IO.File]::WriteAllBytes($path,$bytes)}
    }
    $badResult=Clone $historicalSelf.result;$badResult.decisionIdentity='F'*64
    $null=Json '.ai-workspace/reports/history-bad-decision.json' $badResult;$badPair=Clone $historicalSelf.pair;$badPair.resultRef=Ref '.ai-workspace/reports/history-bad-decision.json'
    Bad {Read-AiwResultEvidence $historyContext $historicalSelf.typed EVIDENCE-001 @($candidate) $requirements -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($badPair)} 'EVIDENCE_HISTORICAL_FINALIZE_DECISION' 'historical-finalize-must-bind-exact-original-decision'
    $null=Put 'result.md' "# Document result`nRequired content.`n"
    foreach($outcome in @('FAIL','INCOMPLETE')){
        $unsuccessful=Record owner $outcome;$unsuccessful.checks[0].outcome=$outcome
        $failureStage=History-Finalize $historyPackage $unsuccessful SELF_CHECK $outcome.ToLowerInvariant()
        True ($failureStage.result.status-ceq'PASS'-and$failureStage.result.actionOutcome-ceq$outcome) ('real-finalize-structurally-records-'+$outcome)
        Bad {Read-AiwResultEvidence $historyContext $failureStage.typed EVIDENCE-001 @($candidate) $requirements -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($failureStage.pair)} 'EVIDENCE_HISTORICAL_ACTION_NOT_SUCCESSFUL' ('finalized-'+$outcome+'-is-not-historical-success')
        $failurePlan=Stage failed SELF_CHECK @() @($candidate) @($failureStage.typed)
        $failurePlan|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($failureStage.pair)})
        Bad {Assert-AiwAcceptanceStages $historyContext (Plan @($failurePlan)) EVIDENCE-001} 'EVIDENCE_HISTORICAL_ACTION_NOT_SUCCESSFUL' ('declared-stage-rejects-finalized-'+$outcome)
    }
    # An original successful CONTROL source transition is also historical.
    # This is distinct from a pending old FINALIZE after somebody else's edit.
    $savedCandidate=$candidate;$candidate=Ref 'AGENTS.md'
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' ($taskText.Replace('result.md','AGENTS.md'))
    $agentsPackage=Package;$agentsPackage.actions=@('CONTROL_WRITE')
    $agentsHistory=History-Finalize $agentsPackage (Record) SELF_CHECK 'agents' {
        param($record)
        $null=Put 'AGENTS.md' 'An authorized original instructions update.'
        $record.candidateObjects=@((Ref 'AGENTS.md'));$record.evidenceLocators+=@((Ref 'AGENTS.md'))
    }
    True ($agentsHistory.result.sourcePostimageTransition.status-ceq'PASS') 'real-original-control-finalize-records-source-transition'
    $null=Put 'AGENTS.md' 'A later legitimate instructions revision.'
    Good {Read-AiwResultEvidence $historyContext $agentsHistory.typed EVIDENCE-001 $agentsHistory.record.candidateObjects $requirements -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($agentsHistory.pair)} 'historical-original-source-transition-survives-later-agents-revision'
    $candidate=$savedCandidate
    # A real isolated target must retain the original path guard while its
    # historical state is compared with the original FINALIZE, not live HEAD.
    function History-Git([string]$Root,[string[]]$Arguments){
        $run=Invoke-AiwTestProcess (Get-Command git -CommandType Application).Source (@('-C',$Root)+$Arguments) -WorkingDirectory $Root -GroupId 'result-history-target'
        if($run.Code-ne0){throw ('HISTORY_TARGET_GIT|'+$run.Text)}
        return $run.Text.Trim()
    }
    $historyTarget=Join-Path $temp 'history-target'
    $null=History-Git $temp @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','History baseline')
    $null=History-Git $temp @('worktree','add','-q','-b','history-target',$historyTarget,'HEAD')
    $oldHead=History-Git $historyTarget @('rev-parse','HEAD')
    $oldTargetState=[pscustomobject]@{branch='history-target';head=$oldHead.ToUpperInvariant()}
    $selection=Put '.ai-workspace/runtime/EVIDENCE-001/owner/history-target-decision.txt' 'Isolated fixture selects its own local worktree; no real project or host authority is claimed.'
    $descriptor=Json '.ai-workspace/runtime/EVIDENCE-001/owner/history-target.json' ([pscustomobject]@{schemaVersion=1;kind='EXECUTION_TARGET';projectId='evidence-fixture';taskId='EVIDENCE-001';controlRoot=$temp;targetKind='GIT_WORKTREE';targetRoot=$historyTarget;gitBinding=@{commonGitDir=[IO.Path]::GetFullPath((History-Git $temp @('rev-parse','--path-format=absolute','--git-common-dir')));worktreeGitDir=[IO.Path]::GetFullPath((History-Git $historyTarget @('rev-parse','--absolute-git-dir')));gitTop=$historyTarget;branch='history-target';baselineCommit=$oldHead};selectionDecisionRef=@{path=$selection;identity=(Id $selection)};hostWorktreeRef=$null})
    $targetRef=[pscustomobject]@{path=$descriptor;identity=(Id $descriptor)}
    $null=Put '.ai-workspace/tasks/active/EVIDENCE-001.md' ($taskText+'- Execution target: '+$descriptor+'#'+$targetRef.identity+"`n")
    $targetProduct=Join-Path $historyTarget 'result.md';[IO.File]::WriteAllText($targetProduct,'Original isolated result.',$utf8)
    $targetCandidate=[pscustomobject]@{path='result.md';identity=(Id $targetProduct)}
    $targetPackage=Package;$targetPackage.schemaVersion=4;$targetPackage.actions=@('TEST_RUN');$targetPackage.objectIdentities=@($targetCandidate)
    $targetPackage|Add-Member repositoryId PROJECT;$targetPackage|Add-Member controlRoot $temp;$targetPackage|Add-Member executionTargetRef $targetRef;$targetPackage|Add-Member expectedTargetState $oldTargetState;$targetPackage.invalidatesOn+=@('REPOSITORY_CHANGE')
    $targetRecord=Record;$targetRecord.schemaVersion=2;$targetRecord.candidateObjects=@($targetCandidate)
    $targetRecord|Add-Member executionTargetRef $targetRef;$targetRecord|Add-Member candidateTargetState $oldTargetState
    $targetRecord.evidenceLocators+=@([pscustomobject]@{path=$targetProduct;identity=$targetCandidate.identity})
    $targetHistory=History-Finalize $targetPackage $targetRecord SELF_CHECK 'target'
    $null=History-Git $historyTarget @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','Later legitimate target HEAD')
    [IO.File]::WriteAllText($targetProduct,'Later legitimate isolated result.',$utf8)
    $targetContext=New-AiwEvidenceContext $temp $historyTarget $historyFramework;$targetContext|Add-Member TaskPath $taskPath
    Good {Read-AiwResultEvidence $targetContext $targetHistory.typed EVIDENCE-001 @($targetCandidate) $requirements -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($targetHistory.pair)} 'historical-target-uses-original-state-after-live-head-and-product-change'
    Bad {Read-AiwResultEvidence $targetContext $targetHistory.typed EVIDENCE-001 @($targetCandidate) $requirements} 'EXECUTION_TARGET_HEAD_DRIFT' 'current-target-still-rejects-live-head-drift'
    $protectedTargetContext=New-AiwEvidenceContext $temp $historyTarget $historyFramework @() @((Join-Path $temp 'result.md'))
    # A reparse replacement distinguishes protection-before-target-metadata
    # from a late rejection after accessing the now forbidden target object.
    [IO.File]::Delete($targetProduct)
    $linkDestination=Join-Path $temp 'history-junction-target';$null=[IO.Directory]::CreateDirectory($linkDestination)
    $null=New-Item -ItemType Junction -Path $targetProduct -Target $linkDestination
    try{
        Bad {Read-AiwResultEvidence $protectedTargetContext $targetHistory.typed EVIDENCE-001 @($targetCandidate) $requirements -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($targetHistory.pair)} 'EXECUTION_TARGET_PROTECTED_PATH' 'historical-control-absolute-protection-projects-before-target-reparse-observation'
        Bad {Read-AiwResultEvidence $targetContext $targetHistory.typed EVIDENCE-001 @($targetCandidate) $requirements -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize @($targetHistory.pair)} 'EXECUTION_TARGET_REPARSE' 'historical-target-without-protection-still-rejects-reparse'
    }finally{[IO.Directory]::Delete($targetProduct)}
    Test-HistoricalInputConsumers (Join-Path $temp 'historical-inputs')
    $completed=$true
    Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=result-acceptance|evidenceCeiling=INSTRUCTION_BOUND')
}catch{Write-Output ('DIAG|fixture='+$temp);Write-Output $_.ScriptStackTrace;throw}finally{
    Set-Location -LiteralPath $savedLocation;[Environment]::CurrentDirectory=$savedCurrent
    if($KeepFixture){Write-Output ('FIXTURE|'+$temp)}elseif($completed){$full=[IO.Path]::GetFullPath($temp);$root=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/');if([IO.Path]::GetDirectoryName($full)-cne$root-or[IO.Path]::GetFileName($full)-cnotmatch '^aiw-result-evidence-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'};Remove-Item -LiteralPath $full -Recurse -Force}
}
