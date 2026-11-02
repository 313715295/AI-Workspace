#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LegacyRuntimeRoot,
    [ValidateSet('1.16.0','2.0.0')][string]$LegacyFrameworkVersion='1.16.0',
    [ValidateSet('ALL','ORDINARY','MAINTENANCE')][string]$Layout='ALL',
    [switch]$CoreOnly,
    [switch]$FixedRuntimeOnly,
    [switch]$SourceContractOnly,
    [string]$SeedTargetRoot,
    [string]$HistorySeedRoot,
    [switch]$RecoveryDirectionOnly,
    [ValidateSet('RELATIVE','ABSOLUTE_INSIDE','ABSOLUTE_OUTSIDE')][string]$SourceLocation='RELATIVE',
    [switch]$CorrectionLifecycleOnly,
    [switch]$CorrectionAdoption,
    [switch]$ProviderSnapshotOnly,
    [switch]$NonOwner,
    [string]$BaselineTransactionModule,
    [switch]$ModuleBindingOnly,
    [string]$TargetRuntimeRoot,
    [string]$RetainedModuleBindingEvidence,
    [switch]$KeepFixture,
    [switch]$B1Daily
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($FixedRuntimeOnly){$CoreOnly=$true}
if($B1Daily-and($LegacyFrameworkVersion-cne'2.0.0'-or$Layout-cne'MAINTENANCE'-or-not$FixedRuntimeOnly-or$SourceContractOnly-or$NonOwner-or$HistorySeedRoot-or$SeedTargetRoot-or$RecoveryDirectionOnly-or$CorrectionAdoption-or$ProviderSnapshotOnly-or$ModuleBindingOnly)){throw 'B1_DAILY_REQUIRES_FIXED_MAINTENANCE_ORIGIN'}
if($B1Daily){$KeepFixture=$true}
if($SeedTargetRoot){$FixedRuntimeOnly=$true;$CoreOnly=$true;$KeepFixture=$true;if($LegacyFrameworkVersion-cne'1.16.0'-or$Layout-cne'MAINTENANCE'){throw 'HISTORY_SEED_START_REQUIRED'}}
if($HistorySeedRoot-and($LegacyFrameworkVersion-cne'2.0.0'-or$Layout-cne'MAINTENANCE'-or-not$FixedRuntimeOnly)){throw 'HISTORY_SEED_CONSUMER_REQUIRED'}
if($RecoveryDirectionOnly-and-not$HistorySeedRoot){throw 'RECOVERY_DIRECTION_REQUIRES_ACTUAL_HISTORY'}
if($CorrectionAdoption-and($Layout-cne'ORDINARY'-or-not$FixedRuntimeOnly-or$HistorySeedRoot-or$SeedTargetRoot-or$NonOwner)){throw 'CORRECTION_ADOPTION_FIXTURE_REQUIRES_FIXED_ORDINARY_OWNER'}
if($ModuleBindingOnly-and($LegacyFrameworkVersion-cne'2.0.0'-or-not$TargetRuntimeRoot-or$HistorySeedRoot-or$SeedTargetRoot-or$CorrectionAdoption-or$NonOwner-or$BaselineTransactionModule)){throw 'MODULE_BINDING_FIXTURE_ARGUMENTS'}
if($TargetRuntimeRoot-and-not$ModuleBindingOnly){throw 'MODULE_BINDING_TARGET_REQUIRES_SELECTOR'}
if($RetainedModuleBindingEvidence-and-not$ModuleBindingOnly){throw 'RETAINED_BINDING_REQUIRES_SELECTOR'}
$sourceRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pwsh=(Get-Command pwsh -CommandType Application).Source
$utf8=[Text.UTF8Encoding]::new($false);$passed=0
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-major-bridge-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
if($CorrectionLifecycleOnly-and($NonOwner-or$BaselineTransactionModule)){throw 'CURRENT_CORRECTION_FIXTURE_REQUIRES_OWNER_AND_CURRENT_IMPLEMENTATION'}
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 100 -Compress)}
function Id([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return 'NEW'};$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function FixtureObjectIdentity([string]$Path){
    if(Test-Path -LiteralPath $Path -PathType Leaf){return Id $Path}
    if(Test-Path -LiteralPath $Path){
        $item=Get-Item -LiteralPath $Path -Force
        if($item.PSIsContainer-and($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-eq0){return 'DIRECTORY'}
        return 'NON_FILE'
    }
    return 'MISSING'
}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function CopyFile([string]$From,[string]$To){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $To));Copy-Item -LiteralPath $From -Destination $To}
function Seed-AdoptionCorrections([string]$Project,[string]$Runtime,[string]$Version){
    Import-Module (Join-Path $Runtime 'scripts/ProjectCorrectionLifecycle.psm1') -Force
    Import-Module (Join-Path $Runtime 'scripts/ProjectAdoptionTransaction.psm1') -Force
    $agentsPath=Join-Path $Project 'AGENTS.md'
    SaveText $agentsPath ((Get-Content $agentsPath -Raw)+"`nexit=[base]; revise=[base]; independent=[keep]`n")
    $exitText=[pscustomobject]@{kind='TEXT';path='AGENTS.md';before='base';after='owned';prefix='exit=[';suffix=']'}
    $revisionText=[pscustomobject]@{kind='TEXT';path='AGENTS.md';before='base';after='old';prefix='revise=[';suffix=']'}
    $oldBinary=[pscustomobject]@{kind='FILE';path='owned/old.bin';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String([byte[]]@(0,255,42))}
    $impact=[pscustomobject]@{stoppedObligations=@('fixture owned correction');independentObligations=@('independent user text');inFlightEffects=@();recovery='original adoption journal';semanticAssessment='explicitly disjoint edits'}
    $seedRecords=@{}
    foreach($id in @('ADOPT_EXIT','ADOPT_REV')){
        $record=[pscustomobject]@{correctionId=$id;introducedAgainstFramework=$Version;requirementReason=('fixture issue '+$id);effectiveRule=('fixture adopted rule '+$id);applicability='isolated adoption fixture';decisionLocator='fixture:seed';selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@()}
        $seedRecords[$id]=$record
        $relative=".ai-workspace/upgrade-recovery/corrections/$id/seed/"
        $installation=[pscustomobject]@{schemaVersion=1;correctionId=$id;decisionLocator='fixture:seed';dependsOn=@();changes=@(if($id-ceq'ADOPT_EXIT'){$exitText;$oldBinary}else{$revisionText})}
        $plan=[pscustomobject]@{schemaVersion=1;operation='INSTALL';correctionId=$id;expectedCorrectionsIdentity=(Id (Join-Path $Project '.ai-workspace/corrections.json'));decisionLocator='fixture:seed';record=$record;installation=$installation;installationRelativePath=($relative+'installation.json');transactionRelativePath=($relative+'state.json');impact=$impact;forbiddenPaths=@('private')}
        $preview=New-AiwCorrectionLifecycleProjection $Project $plan
        if($preview.status-cne'READY'){throw 'CORRECTION_ADOPTION_SEED_CONFLICT'}
        $null=Invoke-AiwProjectProjectionTransaction $Project $preview.projection $plan.transactionRelativePath {$true} {$true}
    }
    $revisionNew=Clone $revisionText;$revisionNew.after='new'
    $newBinary=[pscustomobject]@{kind='FILE';path='owned/new.bin';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String([byte[]]@(255,0,128,1))}
    $newInstallation=[pscustomobject]@{schemaVersion=1;correctionId='ADOPT_REV';decisionLocator='fixture:revision';dependsOn=@();changes=@($revisionNew,$newBinary)}
    $carrier=Get-Content (Join-Path $Project '.ai-workspace/corrections.json') -Raw|ConvertFrom-Json -Depth 100
    $changes=@()
    foreach($id in @('ADOPT_EXIT','ADOPT_REV')){
        $relative=".ai-workspace/upgrade-recovery/corrections/$id/adoption/"
        $changes+=@([pscustomobject]@{correctionId=$id;operation=$(if($id-ceq'ADOPT_EXIT'){'UNINSTALL'}else{'REVISE'});decisionLocator='fixture:adoption';record=$(if($id-ceq'ADOPT_EXIT'){'NOT_APPLICABLE'}else{$seedRecords[$id]});installation=$(if($id-ceq'ADOPT_EXIT'){'NOT_APPLICABLE'}else{$newInstallation});installationRelativePath=$(if($id-ceq'ADOPT_EXIT'){'NOT_APPLICABLE'}else{$relative+'installation.json'});historyRelativePath=($relative+'history.json');effectPaths=$(if($id-ceq'ADOPT_EXIT'){@('AGENTS.md','owned/old.bin')}else{@('AGENTS.md','owned/new.bin')});impact=$impact})
    }
    $group=[pscustomobject]@{schemaVersion=2;expectedCorrectionsIdentity=(Id (Join-Path $Project '.ai-workspace/corrections.json'));changes=$changes}
    $planPath=Join-Path $Project '.ai-workspace/runtime/adoption-group-plan.json';SaveJson $planPath $group
    return [pscustomobject]@{path=$planPath;identity=(Id $planPath);scope=@(Get-AiwCorrectionAdoptionScope $Project $group @('private'));prior=@($carrier.corrections);binary=$newBinary.afterBase64}
}
function InvokeTool([string]$Tool,[hashtable]$Parameters,[string]$WorkingDirectory=$sourceRoot){
    $call=Join-Path $temp ('call-'+[guid]::NewGuid().ToString('N')+'.json');SaveJson $call @{tool=$Tool;parameters=$Parameters;workingDirectory=$WorkingDirectory}
    $stdout='';$stderr=''
    if($ModuleBindingOnly){
        $native=Invoke-AiwTestProcess -Executable $pwsh -Arguments @('-NoProfile','-NonInteractive','-File',$runner,'-InputPath',$call) -WorkingDirectory $WorkingDirectory -EvidenceDirectory (Join-Path $temp 'native') -GroupId 'adoption-module-binding'
        $stdout=$native.StdoutText;$stderr=$native.StderrText;$code=$native.Code;$output=@($native.Output)
    }elseif($ProviderSnapshotOnly){
        $start=[Diagnostics.ProcessStartInfo]::new($pwsh);$start.WorkingDirectory=$WorkingDirectory
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        foreach($argument in @('-NoProfile','-NonInteractive','-File',$runner,'-InputPath',$call)){$start.ArgumentList.Add($argument)}
        $child=[Diagnostics.Process]::Start($start)
        try{$outRead=$child.StandardOutput.ReadToEndAsync();$errRead=$child.StandardError.ReadToEndAsync();$child.WaitForExit();$stdout=$outRead.GetAwaiter().GetResult();$stderr=$errRead.GetAwaiter().GetResult();$code=$child.ExitCode}finally{$child.Dispose()}
        $output=@($stdout);if($stderr){$output+=@($stderr)}
    }else{
        $output=@(& $pwsh -NoProfile -NonInteractive -File $runner -InputPath $call 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE
    }
    $value=$null
    if($ProviderSnapshotOnly-or$code-eq0){try{$value=$(if($ProviderSnapshotOnly-or$ModuleBindingOnly){$stdout}else{$output-join"`n"})|ConvertFrom-Json -Depth 100;if(@($value).Count-eq1-and@($value)[0]-is[string]-and@($value)[0].StartsWith('{')){$value=@($value)[0]|ConvertFrom-Json -Depth 100}}catch{if($code-eq0){throw}}}
    $result=[pscustomobject]@{code=$code;value=$value;text=($output-join"`n")}
    # Retain every real invocation, including the failure that ends a long case.
    if($true){
        $resultPath=[IO.Path]::ChangeExtension($call,'.result.json')
        SaveJson $resultPath ([ordered]@{invocation=$call;tool=$Tool;parameters=$Parameters;workingDirectory=$WorkingDirectory;exitCode=$code;stdout=$stdout;stderr=$stderr;output=$result.text;parsed=$value})
        $result|Add-Member -NotePropertyName recordPath -NotePropertyValue $resultPath
        if($ModuleBindingOnly){$result|Add-Member -NotePropertyName nativeResultPath -NotePropertyValue $native.ResultPath}
    }
    return $result
}
function Run([string]$Tool,[hashtable]$Parameters,[string]$WorkingDirectory=$sourceRoot){$result=InvokeTool $Tool $Parameters $WorkingDirectory;if($result.code-ne0){throw ('TOOL_FAILED|'+[IO.Path]::GetFileName($Tool)+'|'+$result.text)};return $result.value}
function Reject([string]$Tool,[hashtable]$Parameters,[string]$Reason,[string]$Name){$result=InvokeTool $Tool $Parameters;if($result.code-eq0-or-not$result.text.Contains($Reason)){throw ('UNEXPECTED_REJECTION|'+$Name+'|'+$result.text)};Check $true $Name}
function Clone($Value){return ($Value|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100 -AsHashtable)}
function RejectCall([scriptblock]$Call,[string]$Reason,[string]$Name){$failure=$null;try{& $Call|Out-Null}catch{$failure=$_.Exception.Message};if(-not$failure-or-not$failure.Contains($Reason)){throw ('UNEXPECTED_REJECTION|'+$Name+'|'+$failure)};Check $true $Name}

# These private fixture constructors follow the actual source TOOLCHAIN. They
# do not adapt a live historical receipt or modify any fixed package.
function Get-FixtureProcessContract([string]$Runtime,[string]$Version='2.0.0'){
    $directory=Join-Path $Runtime ('framework/versions/'+$Version)
    $chain=Get-Content -LiteralPath (Join-Path $directory 'TOOLCHAIN.json') -Raw|ConvertFrom-Json
    $profile=Get-Content -LiteralPath (Join-Path $directory 'ADOPTION_PROFILE.json') -Raw|ConvertFrom-Json
    if($chain.frameworkVersion-cne$Version-or$profile.frameworkVersion-cne$Version){throw 'FIXTURE_PROCESS_VERSION_MISMATCH'}
    switch([string]$chain.contractVersion){
        {$_-cin@('1','2')} {return @{input=2;intent=1;boundary=2;project=$profile.projectControl.schemaVersion;contract=[string]$chain.contractVersion}}
        '3' {return @{input=4;intent=2;boundary=3;project=$profile.projectControl.schemaVersion;contract='3'}}
        '4' {return @{input=5;intent=2;boundary=3;project=$profile.projectControl.schemaVersion;contract='4'}}
        default {throw 'FIXTURE_UNSUPPORTED_PROCESS_CONTRACT'}
    }
}
function Invoke-B1DailyMaintenanceCase([string]$Project,[string]$Runtime) {
    $watch=[Diagnostics.Stopwatch]::StartNew();$timings=[ordered]@{}
    $caseId='B1-DAILY-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $taskRelative='.ai-workspace/tasks/active/'+$caseId+'.md';$task=Join-Path $Project $taskRelative
    $path='.ai-workspace/reports/'+$caseId.ToLowerInvariant()+'.txt';$object=Join-Path $Project $path
    SaveText $task ([string]::Join([char]10,@(('# '+$caseId+' — Isolated daily maintenance'),'- Task schema: 2.0.0','- Status: ACTIVE','- Profile: CRITICAL; reason=Current daily boundary after an actual old-source upgrade.','- Owner: major-owner','- Work route: actor=major-owner; role=FRAMEWORK_MAINTAINER; phase=IMPLEMENT','- Phase gate: FALSE',('- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=B1_DAILY; expected_paths=['+$path+']; actual_paths=['+$path+']'),'- Writer / reviewer / authorization: exact isolated action','- Git / push / external: DEFERRED','## Current','- Goal: Write and close one finite maintenance report through current public boundaries.','- Acceptance: Original checker, FULL/REUSE, ADMIT, one write and FINALIZE.')))
    $directory=Join-Path $Project ('.ai-workspace/runtime/'+$caseId+'/major-owner');$null=[IO.Directory]::CreateDirectory($directory)
    $package=[ordered]@{schemaVersion=2;frameworkVersion='2.0.0';taskId=$caseId;profile='CRITICAL';lifecycle='ACTIVE';owner='major-owner';issuer='major-owner';issuerRole='TASK_OWNER';grantee='major-owner';bundle='B1_DAILY_ISOLATED';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id $task);actions=@('CONTROL_WRITE');exactPaths=@($path);objectIdentities=@(@{path=$path;identity='NEW'});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','REPOSITORY_CHANGE');projectConfigIdentity=(Id (Join-Path $Project '.ai-workspace/project.json'));repositoryId='CONTROL'}
    $packagePath=Join-Path $directory 'package.json';SaveJson $packagePath $package
    $checker=@{ControlRepositoryPath=$Project;PackagePath=$packagePath;ObservedActor='major-owner';ObservedTaskId=$caseId;ObservedOwner='major-owner';ObservedAction=@('CONTROL_WRITE');ObservedPath=@($path);ObservedIdentity=@($path+'=NEW');ObservedRepositoryId='CONTROL';ExpectedProjectConfigIdentity=$package.projectConfigIdentity;TaskPath=$taskRelative;ExpectedTaskIdentity=$package.taskIdentity}
    $phase=[Diagnostics.Stopwatch]::StartNew();$checked=Run (Join-Path $Runtime 'scripts/check-framework-maintenance-authorization.ps1') $checker $Project;$phase.Stop();$timings.checker=$phase.Elapsed.TotalSeconds
    Check (($checked-join[char]10).StartsWith('PASS|')) 'b1-daily-independent-checker'
    $input=[ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$Project;frameworkRoot=$Runtime;taskPath=$task;expectedProjectConfigIdentity=$package.projectConfigIdentity;expectedCorrectionsIdentity=(Id (Join-Path $Project '.ai-workspace/corrections.json'));expectedTaskIdentity=$package.taskIdentity;observedActor='major-owner';capabilities=@();exactPaths=@($path);forbiddenPaths=@('private');protectedPaths=@('private');authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Id $packagePath);userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;ruleLoad=@{mode='FULL'};intentEnvelope=@{schemaVersion=2;objective='Write one finite isolated maintenance report and close the actual current action';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:implementation')};deliverableType=@{state='KNOWN';values=@('aiw:report')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}}
    $resolver=Join-Path $Runtime 'scripts/resolve-framework-maintenance-process-requirements.ps1';$inputPath=Join-Path $directory 'discover.json';SaveJson $inputPath $input
    $phase=[Diagnostics.Stopwatch]::StartNew();$full=Run $resolver @{InputPath=$inputPath;AsJson=$true};$phase.Stop();$timings.full=$phase.Elapsed.TotalSeconds
    Check ($full.status-ceq'PASS'-and$full.compactReceipt.loadDecision.effectiveMode-ceq'FULL') 'b1-daily-full-current-rules'
    $fullPath=Join-Path $directory 'full-compact.json';SaveJson $fullPath $full.compactReceipt
    $input.ruleLoad=@{mode='REUSE';previousCoverageRef=@{path=$fullPath;identity=(Id $fullPath)}};SaveJson $inputPath $input
    $phase=[Diagnostics.Stopwatch]::StartNew();$reuse=Run $resolver @{InputPath=$inputPath;AsJson=$true};$phase.Stop();$timings.reuse=$phase.Elapsed.TotalSeconds
    Check ($reuse.status-ceq'PASS'-and$reuse.compactReceipt.loadDecision.effectiveMode-ceq'REUSED'-and$reuse.compactReceipt.loadDecision.returnedUnitKeys.Count-eq0) 'b1-daily-real-reuse-with-current-obligations'
    $receiptPath=Join-Path $directory 'reuse-compact.json';SaveJson $receiptPath $reuse.compactReceipt
    $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=@($reuse.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $boundaryPath=Join-Path $directory 'boundary.json';SaveJson $boundaryPath $boundary
    $phase=[Diagnostics.Stopwatch]::StartNew();$admitted=Run $resolver @{InputPath=$boundaryPath;AsJson=$true};$phase.Stop();$timings.admit=$phase.Elapsed.TotalSeconds;Check ($admitted.status-ceq'PASS') 'b1-daily-original-admit'
    SaveText $object 'One real isolated maintenance result.'
    $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($reuse.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$path+'|'+(Id $object));SaveJson $boundaryPath $boundary
    $phase=[Diagnostics.Stopwatch]::StartNew();$closed=Run $resolver @{InputPath=$boundaryPath;AsJson=$true};$phase.Stop();$timings.finalize=$phase.Elapsed.TotalSeconds;Check ($closed.status-ceq'PASS') 'b1-daily-real-postimage-finalize'
    $watch.Stop();$timings.checkerAndDiscover=$timings.checker+$timings.reuse;$timings.threeBoundaries=$timings.checkerAndDiscover+$timings.admit+$timings.finalize;$timings.totalWall=$watch.Elapsed.TotalSeconds
    SaveJson (Join-Path $directory 'timings.json') $timings
    Write-Output ('B1_DAILY_TIMINGS|'+($timings|ConvertTo-Json -Compress))
}
function Set-FixtureDiscoverContract([System.Collections.IDictionary]$Request,[string]$Runtime,[string]$Version='2.0.0'){
    $contract=Get-FixtureProcessContract $Runtime $Version
    $Request.schemaVersion=$contract.input;$Request.intentEnvelope.schemaVersion=$contract.intent
    if($contract.intent-eq2){
        $Request.contextType='TASK';$Request.readOnlyContext='NOT_APPLICABLE'
        if(-not$Request.intentEnvelope.Contains('facets')){
            $Request.intentEnvelope.facets=[ordered]@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:adoption')};deliverableType=@{state='KNOWN';values=@('aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:adoption')}}
        }
    }else{
        $Request.Remove('contextType');$Request.Remove('readOnlyContext');$Request.intentEnvelope.Remove('facets')
    }
    if($contract.input-eq5){$Request.ruleLoad=@{mode='FULL'}}else{$Request.Remove('ruleLoad')}
}
function Set-FixtureBoundaryContract([System.Collections.IDictionary]$Request,[string]$Runtime,[string]$Version='2.0.0'){
    $contract=Get-FixtureProcessContract $Runtime $Version
    $Request.schemaVersion=$contract.boundary
    if($contract.boundary-eq3){$Request.evidenceRefs=@()}else{$Request.Remove('evidenceRefs')}
}
# These fixtures make real finite CONTROL_WRITE actions in the original adopted
# runtime. REGISTER/completion bytes are never fabricated or updated by the test.
function Prime-FixtureAgents([string]$Project,[string]$Runtime,[string]$Version,[string]$Case,[string]$TaskRelative,[string]$Actor,[string]$Desired,[string]$Name){
    $configuration=Get-Content -LiteralPath (Join-Path $Project '.ai-workspace/project.json') -Raw|ConvertFrom-Json
    $controller=Get-Content -LiteralPath (Join-Path $Project '.ai-workspace/controller.json') -Raw|ConvertFrom-Json
    $taskPath=Join-Path $Project $TaskRelative;$taskIdentity=Id $taskPath
    $directory=Join-Path $Project ('.ai-workspace/runtime/MAJOR-001/'+$Actor+'/ir01-'+$Name)
    $agents=Join-Path $Project 'AGENTS.md';$desiredPath=Join-Path $directory 'desired.txt';SaveText $desiredPath $Desired
    if((Id $agents)-ceq(Id $desiredPath)){Check $true ($Case+'-ir01-'+$Name+'-already-equal-no-empty-control-write') | Out-Host;return}
    $owner=[regex]::Match([IO.File]::ReadAllText($taskPath),'(?m)^- Owner: (?<owner>[^\r\n]+)').Groups['owner'].Value
    if(-not$owner){throw 'PRIME_FIXTURE_OWNER_MISSING'}
    $package=[ordered]@{schemaVersion=$(if($Case-ceq'MAINTENANCE'){2}else{1});frameworkVersion=$Version;taskId='MAJOR-001';profile='CRITICAL';lifecycle='ACTIVE';owner=$owner;issuer=$controller.controllerId;issuerRole='PROJECT_CONTROLLER';issuerControllerId=$controller.controllerId;issuerControllerEpoch=$controller.controllerEpoch;controllerControlIdentity=(Id (Join-Path $Project '.ai-workspace/controller.json'));grantee=$Actor;bundle='ISOLATED_EXPLICIT_USER_GRANT_PRIME';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=$taskIdentity;actions=@('CONTROL_WRITE');exactPaths=@('AGENTS.md');objectIdentities=@(@{path='AGENTS.md';identity=(Id $agents)});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Id (Join-Path $Project '.ai-workspace/project.json'))}
    if($Case-ceq'MAINTENANCE'){$package.repositoryId='CONTROL';$package.invalidatesOn+=@('REPOSITORY_CHANGE')}
    $packagePath=Join-Path $directory 'package.json';SaveJson $packagePath $package
    $versionRoot=Join-Path $Runtime ('framework/versions/'+$Version)
    $check=@{PackagePath=$packagePath;ObservedActor=$Actor;ObservedTaskId='MAJOR-001';ObservedOwner=$owner;ObservedAction=@('CONTROL_WRITE');ObservedPath=@('AGENTS.md');ObservedIdentity=@('AGENTS.md='+(Id $agents));TaskPath=$TaskRelative;ExpectedTaskIdentity=$taskIdentity;ExpectedProjectConfigIdentity=$package.projectConfigIdentity}
    if($Case-ceq'MAINTENANCE'){$checker=Join-Path $Runtime 'scripts/check-framework-maintenance-authorization.ps1';$check.ControlRepositoryPath=$Project;$check.ObservedRepositoryId='CONTROL';$resolver=Join-Path $Runtime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{$checker=Join-Path $versionRoot 'scripts/check-authorization.ps1';$check.ProjectConfigPath='.ai-workspace/project.json';$check.ControllerControlPath='.ai-workspace/controller.json';$resolver=Join-Path $versionRoot 'scripts/resolve-process-requirements.ps1'}
    $checked=Run $checker $check $Project
    Check (($checked-join[char]10).StartsWith('PASS|')) ($Case+'-ir01-'+$Name+'-original-prime-checker') | Out-Host
    $request=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$Project;frameworkRoot=$Runtime;taskPath=$taskPath;expectedProjectConfigIdentity=$package.projectConfigIdentity;expectedCorrectionsIdentity=(Id (Join-Path $Project '.ai-workspace/corrections.json'));expectedTaskIdentity=$taskIdentity;observedActor=$Actor;capabilities=@($configuration.frameworkCapabilities.PSObject.Properties|ForEach-Object{$_.Name});exactPaths=@('AGENTS.md');forbiddenPaths=@('private');protectedPaths=@('private');authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Id $packagePath);userDecision=$package.userConfirmation;recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=[ordered]@{schemaVersion=1;objective='Apply this isolated explicitly authorized single current user-text edit; preserve adopted origin and all other objects. Future standing restrictions remain intact.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('project control','user decision');pathHints=@();capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:rule-maintenance')};deliverableType=@{state='KNOWN';values=@('aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}}
    Set-FixtureDiscoverContract $request $Runtime $Version
    $requestPath=Join-Path $directory 'discover.json';SaveJson $requestPath $request
    $discovered=Run $resolver @{InputPath=$requestPath;AsJson=$true};if($discovered.status-cne'PASS'){throw 'PRIME_DISCOVER_FAILED'}
    $receiptPath=Join-Path $directory 'receipt.json';SaveJson $receiptPath $discovered.compactReceipt
    $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Set-FixtureBoundaryContract $boundary $Runtime $Version
    $admitPath=Join-Path $directory 'admit.json';SaveJson $admitPath $boundary
    $admitted=Run $resolver @{InputPath=$admitPath;AsJson=$true};Check ($admitted.status-ceq'PASS') ($Case+'-ir01-'+$Name+'-original-prime-admit') | Out-Host
    $admittedPath=Join-Path $directory 'admitted.json';SaveJson $admittedPath $admitted
    $writer=Join-Path $directory 'apply.ps1'
    SaveText $writer @'
param([string]$Project,[string]$Runtime,[string]$Desired,[string]$ExpectedDesired,[string]$Admit,[string]$ExpectedAdmit,[string]$Resolver,[string]$InputPath,[string]$Journal,[string]$ExpectedBefore)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function Identity($p){$b=[IO.File]::ReadAllBytes($p);$b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
$root=[IO.Path]::GetFullPath($Project);$temp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())+[IO.Path]::DirectorySeparatorChar
if(-not$root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-or(Identity $Desired)-cne$ExpectedDesired-or(Identity $Admit)-cne$ExpectedAdmit-or(Get-Content -LiteralPath $Admit -Raw|ConvertFrom-Json).status-cne'PASS'){throw 'PRIME_WRITE_FACTS'}
$raw=@(& $Resolver -InputPath $InputPath -AsJson)-join[char]10;if(($raw|ConvertFrom-Json).status-cne'PASS'){throw 'PRIME_REPEATED_ADMIT_FAILED'}
Import-Module (Join-Path $Runtime 'scripts/ProjectAdoptionState.psm1') -Force
Import-Module (Join-Path $Runtime 'scripts/ProjectAdoptionProjection.psm1') -Force
Import-Module (Join-Path $Runtime 'scripts/ProjectAdoptionTransaction.psm1') -Force
$agents=Join-Path $root 'AGENTS.md';if((Identity $agents)-cne$ExpectedBefore){throw 'PRIME_PREIMAGE_DRIFT'}
$projection=New-AiwProjectProjection $root @([pscustomobject]@{path='AGENTS.md';text=[IO.File]::ReadAllText($Desired)})
if($projection.objects.Count-ne1-or$projection.objects[0].newIdentity-cne$ExpectedDesired){throw 'PRIME_EXACT_PROJECTION'}
$verify={param($r,$p) $bytes=[IO.File]::ReadAllBytes((Join-Path $r 'AGENTS.md'));($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))-ceq$ExpectedDesired}.GetNewClosure()
$verifyOld={param($r,$p) $bytes=[IO.File]::ReadAllBytes((Join-Path $r 'AGENTS.md'));($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))-ceq$ExpectedBefore}.GetNewClosure()
$result=Invoke-AiwProjectProjectionTransaction $root $projection $Journal $verify $verifyOld
if($result.status-cne'COMPLETE'-or(Identity $agents)-cne$ExpectedDesired){throw 'PRIME_WRITE_INCOMPLETE'}
$result
'@
    $preserved=@('.ai-workspace/project.json','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','.ai-workspace/BOOTSTRAP.md',$TaskRelative,('.ai-workspace/upgrade-recovery/'+$Version+'/state.json'),'.ai-workspace/runtime/project-adoption/register/state.json','.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')
    $before=@($preserved|ForEach-Object{$_+'='+(Id (Join-Path $Project $_))})-join[char]10
    $written=Run $writer @{Project=$Project;Runtime=$Runtime;Desired=$desiredPath;ExpectedDesired=(Id $desiredPath);Admit=$admittedPath;ExpectedAdmit=(Id $admittedPath);Resolver=$resolver;InputPath=$admitPath;Journal=('.ai-workspace/upgrade-recovery/ir01-user-grant/'+$Name+'/state.json');ExpectedBefore=(Id $agents)} $Project
    Check ($written.status-ceq'COMPLETE'-and$before-ceq(@($preserved|ForEach-Object{$_+'='+(Id (Join-Path $Project $_))})-join[char]10)) ($Case+'-ir01-'+$Name+'-prime-preserves-real-origin-and-other-whole-objects') | Out-Host
    $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($discovered.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|AGENTS.md|'+(Id $agents))
    $finalPath=Join-Path $directory 'finalize.json';SaveJson $finalPath $boundary
    $finalized=Run $resolver @{InputPath=$finalPath;AsJson=$true};Check ($finalized.status-ceq'PASS') ($Case+'-ir01-'+$Name+'-actual-original-prime-finalize') | Out-Host
    SaveJson (Join-Path $directory 'finalized.json') $finalized
}
function Ir01-PrepareConflict([string]$Project,[string]$Case,[string]$SourceRuntime,[string]$Version,[string]$TaskRelative,[string]$Actor,[string]$Tool,$Base,$InputTemplate,$PackageTemplate,[string[]]$Group,[string]$RuntimeDirectory,[string]$RestoreText){
    $unknown=$RestoreText.Replace('<!-- AI-WORKSPACE-FRAMEWORK:END -->',"`n未知职责：.ai-workspace/BOOTSTRAP.md 只作导航，禁止修改项目。`n<!-- AI-WORKSPACE-FRAMEWORK:END -->")
    try{
        Prime-FixtureAgents $Project $SourceRuntime $Version $Case $TaskRelative $Actor $unknown 'unknown-source'
        $negative=Clone $PackageTemplate;$negative.objectIdentities=@($negative.exactPaths|ForEach-Object{@{path=$_;identity=(Id (Join-Path $Project $_))}})
        $packagePath=Join-Path $RuntimeDirectory 'ir01-negative-package.json';SaveJson $packagePath $negative
        $request=Clone $InputTemplate;$request.authorizationPackagePath=$packagePath;$request.expectedAuthorizationIdentity=Id $packagePath
        $requestPath=Join-Path $RuntimeDirectory 'ir01-negative-discover.json';SaveJson $requestPath $request
        $check=@{PackagePath=$packagePath;ObservedActor=$Actor;ObservedTaskId=$negative.taskId;ObservedOwner=$negative.owner;ObservedAction=@('CONTROL_WRITE');ObservedPath=@($negative.exactPaths);ObservedIdentity=@($negative.objectIdentities|ForEach-Object{$_.path+'='+$_.identity});TaskPath=$TaskRelative;ExpectedTaskIdentity=$negative.taskIdentity;ExpectedProjectConfigIdentity=$negative.projectConfigIdentity}
        if($Case-ceq'MAINTENANCE'){$checker=Join-Path $SourceRuntime 'scripts/check-framework-maintenance-authorization.ps1';$check.ControlRepositoryPath=$Project;$check.ObservedRepositoryId='CONTROL'}else{$checker=Join-Path $SourceRuntime ('framework/versions/'+$Version+'/scripts/check-authorization.ps1');$check.ProjectConfigPath='.ai-workspace/project.json';$check.ControllerControlPath='.ai-workspace/controller.json'}
        $checked=Run $checker $check $Project
        Check (($checked-join[char]10).StartsWith('PASS|')) ($Case+'-ir01-unknown-current-original-independent-checker')
        $resolver=if($Case-ceq'MAINTENANCE'){Join-Path $SourceRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $SourceRuntime ('framework/versions/'+$Version+'/scripts/resolve-process-requirements.ps1')}
        $observed=Run $resolver @{InputPath=$requestPath;AsJson=$true};Check ($observed.status-ceq'PASS') ($Case+'-ir01-unknown-has-legitimate-original-source-discover')
        $receipt=Join-Path $RuntimeDirectory 'ir01-negative-receipt.json';SaveJson $receipt $observed.compactReceipt
        $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receipt;expectedDiscoverReceiptIdentity=(Id $receipt);preparationReceipts=@($observed.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'};Set-FixtureBoundaryContract $boundary $SourceRuntime $Version
        $boundaryPath=Join-Path $RuntimeDirectory 'ir01-negative-boundary.json';SaveJson $boundaryPath $boundary
        $negativeArgs=$Base.Clone();$negativeArgs.CurrentProcessInputPath=$boundaryPath;$negativeArgs.ExpectedCurrentProcessInputIdentity=Id $boundaryPath;$negativeArgs.AdoptionProcessMode='PREPARE'
        $all=@($Group)+@('.ai-workspace/runtime/project-adoption/register/state.json','.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')
        $before=@($all|Select-Object -Unique|ForEach-Object{$_+'='+(Id (Join-Path $Project $_))})-join[char]10
        Reject $Tool $negativeArgs 'AGENTS_AUTHORIZATION_MIGRATION_CONFLICT' ($Case+'-ir01-public-prepare-rejects-unknown-bootstrap-custom')
        Check ($before-ceq(@($all|Select-Object -Unique|ForEach-Object{$_+'='+(Id (Join-Path $Project $_))})-join[char]10)) ($Case+'-ir01-public-prepare-conflict-whole-group-and-origin-zero-write')
    }finally{Prime-FixtureAgents $Project $SourceRuntime $Version $Case $TaskRelative $Actor $RestoreText 'restore-source'}
}
function Assert-FixtureTargetBodies($Preparation,[string]$Name){
    # This protocol fixture preserves the complete caller-visible target text.
    # Completion tokens below model its caller declaration; they are not proof
    # of a model read or substitutes for the real development process evidence.
    Check (@($Preparation.selectedRuleBlocks).Count-gt0-and@($Preparation.selectedRuleBlocks|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.fullText)}).Count-eq0) ($Name+'-complete-target-rule-bodies')
}

function SealFixture([string]$Root){
    # Isolated test qualification only: no release, Source Review, package build
    # or installation of the working source is performed by this fixture.
    [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'})
    [Array]::Sort($paths,[StringComparer]::Ordinal);$rows=@();[long]$size=0
    foreach($path in $paths){$identity=Id (Join-Path $Root $path);$rows+=($path+'|'+$identity);$size+=[long]$identity.Split('|')[0]}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($rows-join"`n")))
    $manifestPath=Join-Path $Root 'RELEASE_MANIFEST.json';$before=Id $manifestPath;$manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json
    $manifest.PSObject.Properties.Remove('validationProof');$manifest.schemaVersion=2;$manifest.scope='all release payload files except RELEASE_MANIFEST.json';$manifest|Add-Member completeSuite ([pscustomobject]@{}) -Force;$manifest.fileCount=$paths.Count;$manifest.totalBytes=$size;$manifest.canonical=$canonical;$manifest.sourceReview='APPROVED';$manifest.sourceCandidate='ISOLATED_MAJOR_BRIDGE_FIXTURE';$manifest.releaseIntegration=$(if($ProviderSnapshotOnly-and$manifest.lifecycle-ceq'STABLE'){'ISOLATED_TEST_FIXTURE'}else{'PENDING'})
    $manifest.completeSuite=[pscustomobject]@{status='PASS';passed=1;total=1;payloadCanonical=$canonical;evidenceIdentity=('1|'+('A'*64))}
    $manifest.sourceReviewEvidence=[pscustomobject]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$canonical;reviewedManifestIdentity=$before}
    SaveJson $manifestPath $manifest
}
function NamedFixture([string]$Root,[string]$DistributionId='2.0.0-snapshot.1'){
    [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'PACKAGE_MANIFEST.json'})
    [Array]::Sort($paths,[StringComparer]::Ordinal);$files=@();$rows=@()
    foreach($path in $paths){$identity=Id (Join-Path $Root $path);$files+=@([ordered]@{path=$path;identity=$identity});$rows+=($path+'='+$identity)}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n")+"`n")))
    SaveJson (Join-Path $Root 'PACKAGE_MANIFEST.json') ([ordered]@{schemaVersion=2;frameworkVersion='2.0.0';provisional=$true;canonical=$canonical;files=$files;distributionId=$DistributionId})
}
function Invoke-RetainedModuleBindingCases {
    Import-Module (Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestHarness.psm1')
    $evidence=Get-Content -LiteralPath $RetainedModuleBindingEvidence -Raw|ConvertFrom-Json -Depth 100
    $project=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($evidence.project))
    $temporaryBase=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())+[IO.Path]::DirectorySeparatorChar
    if(-not$project.StartsWith($temporaryBase,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($project)-cne'project'-or[IO.Path]::GetFileName((Split-Path -Parent $project))-cne'maintenance'-or-not[IO.Path]::GetFileName((Split-Path -Parent (Split-Path -Parent $project))).StartsWith('aiw-major-bridge-')){throw 'RETAINED_BINDING_ISOLATED_ROOT_REQUIRED'}
    $frozen=@($evidence.frozen)
    if($frozen.Count-eq0){throw 'RETAINED_BINDING_FROZEN_OBJECTS_REQUIRED'}
    foreach($entry in $frozen){
        $full=Assert-AiwTestPath $entry.path
        if(-not$full.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or(Id $full)-cne$entry.identity){throw 'RETAINED_BINDING_ORIGINAL_OBJECT_DRIFT'}
    }
    $parameters=Clone $evidence.originalArgs
    foreach($name in @('InputPath','AdmitResultPath','AdoptionAuthorizationPackagePath')){if(-not@($frozen|Where-Object path -CEQ $parameters[$name]).Count){throw 'RETAINED_BINDING_ORIGINAL_ARGUMENT_UNBOUND'}}
    $admitted=Get-Content -LiteralPath $parameters.AdmitResultPath -Raw|ConvertFrom-Json -Depth 100
    $boundary=Get-Content -LiteralPath $parameters.InputPath -Raw|ConvertFrom-Json -Depth 100
    $prepared=$admitted.adoptionPreparation
    $journal=Join-Path $project '.ai-workspace/runtime/project-adoption/refresh/state.json'
    $transaction=Get-Content -LiteralPath $journal -Raw|ConvertFrom-Json -Depth 100
    $origin=[IO.Path]::GetFullPath($LegacyRuntimeRoot);$target=[IO.Path]::GetFullPath($TargetRuntimeRoot)
    Check ($transaction.state-ceq'COMPLETE'-and$transaction.transactionComplete-and(Id $journal)-ceq$parameters.ExpectedAdoptionTransactionIdentity-and$admitted.status-ceq'PASS'-and$admitted.mode-ceq'ADMIT_ACTION'-and(Id $parameters.AdmitResultPath)-ceq$parameters.ExpectedAdmitResultIdentity-and(Id $parameters.AdoptionAuthorizationPackagePath)-ceq$parameters.ExpectedAdoptionAuthorizationIdentity) 'retained-original-complete-transaction-and-authority'
    Check ($prepared.previousDistribution.runtimeRoot-ceq$origin-and$prepared.targetDistribution.runtimeRoot-ceq$target-and$origin-cne$target-and$sourceRoot-cne$target) 'retained-original-origin-target-and-new-tool'
    $state=@(Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionState.psm1') -PassThru -ErrorAction Stop)[0]
    foreach($pair in @(@($origin,$prepared.previousDistribution),@($target,$prepared.targetDistribution))){
        $binding=& $state.ExportedCommands['Get-AiwDistributionBinding'] $pair[0] '2.0.0' -Required
        foreach($name in @('distributionId','contentIdentity','manifestIdentity','runtimeRoot')){if($binding.$name-cne$pair[1].$name){throw 'RETAINED_BINDING_FIXED_RUNTIME_DRIFT'}}
    }
    $fixedBefore=@(foreach($root in @($origin,$target)){@{root=$root;manifest=(Id (Join-Path $root 'PACKAGE_MANIFEST.json'));composer=(Id (Join-Path $root 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1'))}})
    $adapter=Join-Path $sourceRoot 'scripts/resolve-framework-maintenance-process-requirements.ps1'
    function InvokeRetainedNative([string]$Name,[hashtable]$Arguments){
        $args=@('-NoProfile','-NonInteractive','-File',$adapter)
        foreach($key in @($Arguments.Keys|Sort-Object)){$args+=('-'+$key);if($Arguments[$key]-is[bool]){if(-not$Arguments[$key]){throw 'RETAINED_BINDING_FALSE_SWITCH'}}else{$args+=[string]$Arguments[$key]}}
        $native=Invoke-AiwTestProcess -Executable $pwsh -Arguments $args -WorkingDirectory $sourceRoot -EvidenceDirectory (Join-Path $temp 'native') -GroupId ('adoption-retained-'+$Name)
        $value=$native.StdoutText|ConvertFrom-Json -Depth 100
        $record=Join-Path $temp ($Name+'.json');SaveJson $record @{parameters=$Arguments;nativeResult=$native.ResultPath;record=$native.Record;result=$value;frozenAfter=@($frozen|ForEach-Object{@{path=$_.path;identity=(Id $_.path)}})}
        return [pscustomobject]@{native=$native;value=$value;record=$record}
    }
    function AssertRetainedUnchanged {
        Check (@($frozen|Where-Object{(Id $_.path)-cne$_.identity}).Count-eq0) 'retained-complete-original-object-group-zero-write'
    }
    function AssertRetainedPositive($Observed,[string]$Name){
        Check ($Observed.native.Code-eq0-and$Observed.value.status-ceq'PASS'-and$Observed.value.reason-ceq'ORIGINAL_SAME_PIN_REFRESH_FINALIZED'-and$Observed.value.runtimeRoot-ceq$target-and$Observed.value.originalAdmitDecisionIdentity-ceq$admitted.decisionIdentity-and$Observed.value.originalDiscoverReceiptIdentity-ceq$boundary.expectedDiscoverReceiptIdentity-and$Observed.value.adoptionTransactionIdentity-ceq$parameters.ExpectedAdoptionTransactionIdentity) $Name
        AssertRetainedUnchanged
    }
    $positive=InvokeRetainedNative 'positive' $parameters
    AssertRetainedPositive $positive 'retained-public-native-X-not-T-finalize-only'
    $bad=$parameters.Clone();$bad.ExpectedAdmitResultIdentity='1|'+('F'*64)
    $negative=InvokeRetainedNative 'wrong-admit' $bad
    Check ($negative.native.Code-eq2-and$negative.value.status-ceq'FAIL'-and$negative.value.reason-ceq'ADOPTION_PROCESS_EVIDENCE_DRIFT|ADMIT_RESULT') 'retained-public-native-exact-original-admit-rejection'
    AssertRetainedUnchanged
    $holderPath=Join-Path $temp 'hold-source-scope.ps1'
    SaveText $holderPath @'
param([string]$Publication,[string]$Project,[string]$Ready,[string]$Release)
$ErrorActionPreference='Stop'
$module=@(Import-Module $Publication -PassThru -ErrorAction Stop)[0]
& $module.ExportedCommands['Invoke-AiwProjectSourceScope'] -ProjectRoot $Project -Mode WRITE -Body {
 param($Ready,$Release)
 $readyEvent=[Threading.EventWaitHandle]::OpenExisting($Ready);$releaseEvent=[Threading.EventWaitHandle]::OpenExisting($Release)
 try{$readyEvent.Set()|Out-Null;if(-not$releaseEvent.WaitOne(60000)){throw 'RETAINED_HOLDER_RELEASE_TIMEOUT'};'RELEASED'}finally{$readyEvent.Dispose();$releaseEvent.Dispose()}
} -ArgumentList @($Ready,$Release)
'@
    $readyName='Local\AIW-RetainedReady-'+[guid]::NewGuid().ToString('N');$releaseName='Local\AIW-RetainedRelease-'+[guid]::NewGuid().ToString('N')
    $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$readyName);$release=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$releaseName);$holder=$null;$holderResult=$null
    try{
        $holder=Start-AiwTestProcess -Executable $pwsh -Arguments @('-NoProfile','-NonInteractive','-File',$holderPath,'-Publication',(Join-Path $sourceRoot 'framework/versions/2.0.0/scripts/ProjectSourcePublication.psm1'),'-Project',$project,'-Ready',$readyName,'-Release',$releaseName) -WorkingDirectory $sourceRoot -EvidenceDirectory (Join-Path $temp 'native') -GroupId 'adoption-retained-external-write-holder'
        Check ($ready.WaitOne(30000)-and-not$holder.Process.HasExited) 'retained-real-external-write-holder-synchronized'
        $busy=InvokeRetainedNative 'external-busy' $parameters
        Check ($busy.native.Code-eq2-and$busy.value.status-ceq'FAIL'-and$busy.value.reason-ceq'SOURCE_PUBLICATION_BUSY|upgrade-project -ProjectRuleRecoveryPlanPath') 'retained-public-native-excludes-real-external-write-holder'
        AssertRetainedUnchanged
    }finally{
        $release.Set()|Out-Null
        if($null-ne$holder){$holderResult=Wait-AiwTestProcess $holder;if($holderResult.Status-ceq'RUNNING'){Stop-AiwTestProcess $holder -AuthorizedRunId $holder.RunId -Reason 'Retained test holder cleanup after release timeout';$holderResult=Wait-AiwTestProcess $holder}}
        $ready.Dispose();$release.Dispose()
    }
    Check ($holderResult.Code-eq0-and$holderResult.StdoutText.Trim()-ceq'RELEASED') 'retained-external-write-holder-cleanly-released'
    $released=InvokeRetainedNative 'after-release' $parameters
    AssertRetainedPositive $released 'retained-public-native-recovers-after-external-release'
    foreach($item in $fixedBefore){Check ((Id (Join-Path $item.root 'PACKAGE_MANIFEST.json'))-ceq$item.manifest-and(Id (Join-Path $item.root 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1'))-ceq$item.composer) 'retained-origin-and-target-fixed-package-bytes-preserved'}
    SaveJson (Join-Path $temp 'retained-binding-observation.json') @{status='PASS';project=$project;origin=$origin;target=$target;recoveryTool=$sourceRoot;originalEvidence=$RetainedModuleBindingEvidence;before=$frozen;after=@($frozen|ForEach-Object{@{path=$_.path;identity=(Id $_.path)}});originalDecision=$admitted.decisionIdentity;positive=$positive.record;negative=$negative.record;externalBusy=$busy.record;released=$released.record;holderNativeResult=$holderResult.ResultPath;appliesPerformed=0;fixtureOnly=$true;productionQualificationProven=$false}
    Write-Output ('RESULT|retained-major-adoption-module-binding|passed='+$passed+'|failed=0|newApply=0')
}

function Invoke-ModuleBindingCases {
    Import-Module (Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestHarness.psm1')
    $origin=[IO.Path]::GetFullPath($LegacyRuntimeRoot);$target=[IO.Path]::GetFullPath($TargetRuntimeRoot)
    $originComposer=Join-Path $origin 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1'
    $targetComposer=Join-Path $target 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1'
    Check ($origin-cne$target-and(Id $originComposer)-cne(Id $targetComposer)-and$sourceRoot-cne$target) 'binding-fixture-requires-distinct-origin-target-and-recovery-tool'
    $fixedBefore=@(foreach($root in @($origin,$target)){@{root=$root;manifest=(Id (Join-Path $root 'PACKAGE_MANIFEST.json'));composer=(Id (Join-Path $root 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1'))}})
    # A finite, process-local faulty implementation changes only empty-byte
    # hashing. Its real legacy payload enumeration must still disagree with T.
    $emptyOnly=Join-Path $temp 'empty-array-only-counterexample.ps1'
    SaveText $emptyOnly @'
param([string]$Origin,[string]$Target)
$ErrorActionPreference='Stop'
$module=@(Import-Module (Join-Path $Origin 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
& $module {
    param($root)
    function script:Get-AiwSha256Hex {param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes) [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
    $version=Join-Path $root 'framework/versions/2.0.0'
    Get-AiwReleasePayloadFacts -VersionDirectory $version -ManifestPath (Join-Path $version 'RELEASE_MANIFEST.json')
} $Target | ConvertTo-Json -Compress
'@
    $fault=Run $emptyOnly @{Origin=$origin;Target=$target}
    $targetManifest=Get-Content (Join-Path $target 'framework/versions/2.0.0/RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json
    Check ($fault.FileCount-gt$targetManifest.fileCount-and$fault.Canonical-cne$targetManifest.canonical) 'empty-array-only-fix-still-uses-wrong-payload-algorithm'
    SaveJson (Join-Path $temp 'empty-array-counterexample-observation.json') @{legacyFacts=$fault;targetPayload=$targetManifest.canonical;targetFileCount=$targetManifest.fileCount;fixedPackagesUnmodified=$true}
    $cases=if($Layout-ceq'ALL'){@('ORDINARY','MAINTENANCE')}else{@($Layout)}
    foreach($case in $cases){
        Write-Output ('MODULE_BINDING|'+$case+'|REGISTER_ORIGIN')
        $caseRoot=Join-Path $temp $case.ToLowerInvariant();$project=Join-Path $caseRoot 'project';$null=[IO.Directory]::CreateDirectory($project)
        $owner='binding-owner';$taskId='BIND-001';$taskRelative='.ai-workspace/tasks/active/BIND-001.md';$task=Join-Path $project $taskRelative
        $initial=Join-Path $caseRoot 'BIND-001.md'
        SaveText $initial ([string]::Join([char]10,@('# BIND-001 — Complete isolated runtime adoption','- Task schema: 2.0.0','- Status: ACTIVE','- Profile: CRITICAL; reason=Real original admission and target implementation binding.','- Owner: binding-owner','- Work route: actor=binding-owner; role=CONTROLLER; phase=IMPLEMENT','- Phase gate: FALSE','- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=HETEROGENEOUS_ORIGINAL_FINALIZE; expected_paths=[.ai-workspace/upgrade-recovery/2.0.0/state.json]; actual_paths=[.ai-workspace/upgrade-recovery/2.0.0/state.json]','- Writer / reviewer / authorization: isolated fixture only','- Stable candidate: NONE','- Git / push / external: DEFERRED','## Current','- Goal: Verify the original adoption closes using its real origin and target.','- Acceptance: Real PREPARE, original ADMIT, Apply and FINALIZE with immutable evidence.')))
        $projectId='binding-'+$case.ToLowerInvariant()
        $registration=@{ProjectId=$projectId;DisplayName='Isolated binding fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId=$owner;WorkspaceRoot=$origin;LocalCandidatePilot=$true;InitialTaskPath=$initial;ExpectedInitialTaskIdentity=(Id $initial);InitialTaskRelativePath=$taskRelative;Apply=$true}
        if($case-ceq'MAINTENANCE'){
            & git init -q $project;if($LASTEXITCODE){throw 'BINDING_CONTROL_GIT_INIT'}
            $sibling=Join-Path $caseRoot 'target';$null=[IO.Directory]::CreateDirectory($sibling);& git init -q $sibling;if($LASTEXITCODE){throw 'BINDING_TARGET_GIT_INIT'}
            SaveText (Join-Path $sibling 'README.md') 'Isolated Framework target; no real project.'
            $registration.ControlPlaneLayout='framework-maintenance-sibling';$registration.FrameworkTargetRepositoryId='binding-framework';$registration.FrameworkTargetSiblingDirectory='target'
        }
        $registered=Run (Join-Path $origin 'scripts/register-project.ps1') $registration
        Check (@($registered)[-1].status-ceq'CREATED') ($case+'-actual-origin-registration')
        $tool=Join-Path $target 'scripts/upgrade-project.ps1'
        $base=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ControllerId=$owner;WorkspaceRoot=$target;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=(Id $task);ActorRouteActor=$owner}
        $preview=Run $tool $base;$paths=@();$pre=@{}
        foreach($line in @($preview)){
            if($line-match'^UPGRADE_SCOPE_ONLY\|(.+)$'){$paths=@($Matches[1]-split'\|')}
            elseif($line-match'^UPGRADE_WRITESET\|(.+)$'){$paths=@($Matches[1]-split'\|')}
        }
        Check ($paths.Count-gt0) ($case+'-actual-finite-upgrade-scope')
        $text=[IO.File]::ReadAllText($task)
        $text=[regex]::Replace($text,'(?m)^- Range summary:.*$',('- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=HETEROGENEOUS_ORIGINAL_FINALIZE; expected_paths=['+($paths-join'|')+']; actual_paths=['+($paths-join'|')+']'))
        SaveText $task $text;$base.ExpectedActorRouteTaskIdentity=Id $task
        foreach($path in $paths){$pre[$path]=Id (Join-Path $project $path)}
        $runtime=Join-Path $project '.ai-workspace/runtime/BIND-001/binding-owner'
        $process=[ordered]@{schemaVersion=$(if($case-ceq'MAINTENANCE'){2}else{1});frameworkVersion='2.0.0';taskId=$taskId;profile='CRITICAL';lifecycle='ACTIVE';owner=$owner;issuer=$owner;issuerRole='PROJECT_CONTROLLER';issuerControllerId=$owner;issuerControllerEpoch=1;controllerControlIdentity=(Id (Join-Path $project '.ai-workspace/controller.json'));grantee=$owner;bundle='ISOLATED_HETEROGENEOUS_FINALIZE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='ISOLATED_TEST_APPROVED_RUNTIME_REFRESH';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id $task);actions=@('CONTROL_WRITE');exactPaths=$paths;objectIdentities=@($paths|ForEach-Object{@{path=$_;identity=$pre[$_]}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Id (Join-Path $project '.ai-workspace/project.json'))}
        if($case-ceq'MAINTENANCE'){$process.repositoryId='CONTROL';$process.invalidatesOn+=@('REPOSITORY_CHANGE')}
        $processPath=Join-Path $runtime 'process-auth.json';SaveJson $processPath $process
        $input=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$origin;taskPath=$task;expectedProjectConfigIdentity=$process.projectConfigIdentity;expectedCorrectionsIdentity=(Id (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=(Id $task);observedActor=$owner;capabilities=@();exactPaths=$paths;forbiddenPaths=@('private');protectedPaths=@('private');authorizationPackagePath=$processPath;expectedAuthorizationIdentity=(Id $processPath);userDecision=$process.userConfirmation;recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=[ordered]@{schemaVersion=2;objective='Adopt the chosen target and close this original isolated action';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('project adoption');pathHints=$paths;capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:adoption')};deliverableType=@{state='KNOWN';values=@('aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:adoption')}}}}
        $inputPath=Join-Path $runtime 'discover.json';SaveJson $inputPath $input
        $resolver=if($case-ceq'MAINTENANCE'){Join-Path $origin 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $origin 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
        $discovered=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($discovered.status-ceq'PASS') ($case+'-actual-origin-discover')
        $receiptPath=Join-Path $runtime 'compact.json';SaveJson $receiptPath $discovered.compactReceipt
        $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
        $admitInput=Join-Path $runtime 'admit-input.json';SaveJson $admitInput $boundary
        $prepareArgs=$base.Clone();$prepareArgs.AdoptionProcessMode='PREPARE';$prepareArgs.CurrentProcessInputPath=$admitInput;$prepareArgs.ExpectedCurrentProcessInputIdentity=Id $admitInput
        $prepared=Run $tool $prepareArgs;$preparedPath=Join-Path $runtime 'prepared.json';SaveJson $preparedPath $prepared
        Check ($prepared.status-ceq'PREPARED'-and$prepared.previousDistribution.runtimeRoot-ceq$origin-and$prepared.targetDistribution.runtimeRoot-ceq$target) ($case+'-real-prepare-binds-origin-and-target')
        $boundary.preparationReceipts=@(@($boundary.preparationReceipts)+@($prepared.selectedRuleBlocks.preparationRequirements)|Sort-Object -Unique)+@('ADOPTION_TARGET_RULES_LOADED|'+(Id $preparedPath))
        if($prepared.selectorSemanticJudgmentRequired){$boundary.preparationReceipts+=@('ADOPTION_SELECTOR_SEMANTICS_CONFIRMED|'+(Id $preparedPath))}
        SaveJson $admitInput $boundary
        $admitArgs=$prepareArgs.Clone();$admitArgs.AdoptionProcessMode='ADMIT_ACTION';$admitArgs.ExpectedCurrentProcessInputIdentity=Id $admitInput;$admitArgs.AdoptionPreparationPath=$preparedPath;$admitArgs.ExpectedAdoptionPreparationIdentity=Id $preparedPath
        $admitted=Run $tool $admitArgs;$admittedPath=Join-Path $runtime 'admitted.json';SaveJson $admittedPath $admitted
        Check ($admitted.status-ceq'PASS') ($case+'-real-original-admit')
        $rootPackage=Clone $process;$rootPackage.Remove('repositoryId');$rootPackage.schemaVersion=3;$rootPackage.bundle='ACTOR_BOUND_PROJECT_UPGRADE'
        $rootPackage.postObjectIdentities=@($prepared.projection.objects|ForEach-Object{[ordered]@{path=$_.path;identity=$(if($_.newExists){$_.newIdentity}else{'ABSENT'})}})
        $rootPackage.targetFrameworkSnapshot=@{canonical=$targetManifest.canonical;manifestIdentity=(Id (Join-Path $target 'framework/versions/2.0.0/RELEASE_MANIFEST.json'))}
        $rootPackage.invalidatesOn=@($rootPackage.invalidatesOn|Where-Object{$_-cne'REPOSITORY_CHANGE'})+@('POST_OBJECT_DRIFT')
        $rootPath=Join-Path $runtime 'root-auth.json';SaveJson $rootPath $rootPackage
        $apply=$base.Clone();$apply.Apply=$true;$apply.AuthorizationPackagePath=$rootPath;$apply.ExpectedAuthorizationPackageIdentity=Id $rootPath;$apply.AdmitResultPath=$admittedPath;$apply.ExpectedAdmitResultIdentity=Id $admittedPath;$apply.CurrentProcessInputPath=$admitInput;$apply.ExpectedCurrentProcessInputIdentity=Id $admitInput
        Write-Output ('MODULE_BINDING|'+$case+'|ONE_ORIGINAL_APPLY')
        $null=Run $tool $apply
        $journal=Join-Path $project '.ai-workspace/runtime/project-adoption/refresh/state.json'
        if(-not(Test-Path -LiteralPath $journal)){$journal=Join-Path $project '.ai-workspace/runtime/project-adoption/upgrade/state.json'}
        $transaction=Get-Content $journal -Raw|ConvertFrom-Json -Depth 100
        Check ($transaction.transactionComplete-and$transaction.state-ceq'COMPLETE') ($case+'-real-complete-transaction')
        $final=Clone $boundary;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@(@($discovered.compactReceipt.selectedObligations.resultRequirements)+@($prepared.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($prepared.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.newExists){$_.newIdentity}else{'ABSENT'})})
        $finalPath=Join-Path $runtime 'original-finalize.json';SaveJson $finalPath $final
        $finalArgs=$base.Clone();$finalArgs.AdoptionProcessMode='FINALIZE_OUTPUT';$finalArgs.CurrentProcessInputPath=$finalPath;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath;$finalArgs.AdmitResultPath=$admittedPath;$finalArgs.ExpectedAdmitResultIdentity=Id $admittedPath;$finalArgs.AuthorizationPackagePath=$rootPath;$finalArgs.ExpectedAuthorizationPackageIdentity=Id $rootPath;$finalArgs.ExpectedAdoptionTransactionIdentity=Id $journal
        $frozenPaths=@($prepared.projection.objects|ForEach-Object{Join-Path $project $_.path})+@($task,$processPath,$rootPath,$receiptPath,$admitInput,$preparedPath,$admittedPath,$finalPath,$journal,(Join-Path $project '.ai-workspace/controller.json'),(Join-Path $project '.ai-workspace/project.json'),(Join-Path $project '.ai-workspace/corrections.json'),(Join-Path $project '.ai-workspace/BOOTSTRAP.md'),(Join-Path $project 'AGENTS.md'))
        $before=@($frozenPaths|Sort-Object -Unique|ForEach-Object{@{path=$_;identity=(Id $_)}})
        $oldFailure=InvokeTool $tool $finalArgs
        SaveJson (Join-Path $caseRoot 'unfixed-finalize-result.json') $oldFailure
        Check ($oldFailure.code-ne0-and$oldFailure.text.Contains('Bytes')) ($case+'-unfixed-public-finalizer-reaches-wrong-origin-algorithm')
        Check (@($before|Where-Object{(Id $_.path)-cne$_.identity}).Count-eq0) ($case+'-old-failure-keeps-original-transaction-and-evidence')
        if($case-ceq'MAINTENANCE'){
            $fixedTool=Join-Path $sourceRoot 'scripts/resolve-framework-maintenance-process-requirements.ps1'
            $fixedArgs=@{InputPath=$finalPath;AdoptionProcessBoundary=$true;AdmitResultPath=$admittedPath;ExpectedAdmitResultIdentity=(Id $admittedPath);AdoptionAuthorizationPackagePath=$rootPath;ExpectedAdoptionAuthorizationIdentity=(Id $rootPath);ExpectedAdoptionTransactionIdentity=(Id $journal);AsJson=$true}
        }else{$fixedTool=Join-Path $sourceRoot 'scripts/upgrade-project.ps1';$fixedArgs=$finalArgs.Clone()}
        $bad=$fixedArgs.Clone();$bad.ExpectedAdmitResultIdentity='1|'+('F'*64)
        $denied=InvokeTool $fixedTool $bad
        Check ($denied.code-ne0-and$denied.text.Contains('ADOPTION_PROCESS_EVIDENCE_DRIFT|ADMIT_RESULT')-and@($before|Where-Object{(Id $_.path)-cne$_.identity}).Count-eq0) ($case+'-original-admission-drift-rejects-with-zero-write')
        Write-Output ('MODULE_BINDING|'+$case+'|X_NOT_TARGET_FINALIZE_ONLY')
        $closed=Run $fixedTool $fixedArgs
        Check ($closed.status-ceq'PASS'-and$closed.reason-ceq'ORIGINAL_SAME_PIN_REFRESH_FINALIZED'-and$closed.runtimeRoot-ceq$target-and$closed.originalAdmitDecisionIdentity-ceq$admitted.decisionIdentity-and$closed.originalDiscoverReceiptIdentity-ceq(Id $receiptPath)-and$closed.adoptionTransactionIdentity-ceq(Id $journal)) ($case+'-fixed-public-X-not-T-closes-the-same-original-action')
        Check (@($before|Where-Object{(Id $_.path)-cne$_.identity}).Count-eq0) ($case+'-finalize-only-preserves-entire-original-object-group')
        SaveJson (Join-Path $caseRoot 'binding-observation.json') @{status='PASS';origin=$origin;target=$target;tool=$sourceRoot;fixtureOnly=$true;productionQualificationProven=$false;sourceComposer=(Id $originComposer);targetComposer=(Id $targetComposer);originalDecision=$admitted.decisionIdentity;before=$before;after=@($before|ForEach-Object{@{path=$_.path;identity=(Id $_.path)}});result=$closed;applyCount=1;finalizeOnly=$true;legacyFailure=$oldFailure;negativeAdmission=$denied}
    }
    foreach($item in $fixedBefore){Check ((Id (Join-Path $item.root 'PACKAGE_MANIFEST.json'))-ceq$item.manifest-and(Id (Join-Path $item.root 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1'))-ceq$item.composer) 'origin-and-target-fixed-package-bytes-preserved'}
    Write-Output ('RESULT|major-adoption-module-binding|passed='+$passed+'|failed=0|scope=isolated-heterogeneous-original-finalize')
}

function RestoreFixture([string]$Root,$Projection){
    foreach($entry in $Projection.objects){
        $path=Get-AiwContainedPath $Root $entry.path
        if($entry.oldExists){[IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($entry.oldBase64))}
        elseif(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
    }
    $state=Get-AiwContainedPath $Root '.ai-workspace/runtime/project-adoption/upgrade/state.json'
    if($HistorySeedRoot){[IO.File]::WriteAllBytes($state,$script:historyJournalBytes)}
    elseif(Test-Path -LiteralPath $state -PathType Leaf){[IO.File]::Delete($state)}
    $empty=Get-AiwContainedPath $Root '.ai-workspace/upgrade-recovery/2.0.0'
    if((Test-Path -LiteralPath $empty -PathType Container)-and[IO.Directory]::GetFileSystemEntries($empty).Count-eq0){[IO.Directory]::Delete($empty,$false)}
}
function RestoreRefreshFixture([string]$Root,$Projection){
    foreach($entry in $Projection.objects){
        $path=Get-AiwContainedPath $Root $entry.path
        if($entry.oldExists){[IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($entry.oldBase64))}
        elseif(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
    }
    $path=Get-AiwContainedPath $Root '.ai-workspace/runtime/project-adoption/refresh/state.json'
    if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
}
function InterruptFinalStateSwitch([string]$RuntimeRoot,[string]$Project,$Projection,[string]$TransactionRelative,$Metadata,[string]$Name){
    $serial=[guid]::NewGuid().ToString('N');$inputPath=Join-Path $temp ('final-switch-'+$serial+'.json');$markerPath=Join-Path $temp ('final-switch-'+$serial+'-observed.json')
    $config=@($Projection.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})
    $configIdentity=if($config.Count-eq1){[string]$config[0].newIdentity}else{Id (Join-Path $Project '.ai-workspace/project.json')}
    SaveJson $inputPath @{runtimeRoot=$RuntimeRoot;projectRoot=$Project;projection=$Projection;transactionRelative=$TransactionRelative;metadata=$Metadata;projectConfigIdentity=$configIdentity;markerPath=$markerPath}
    $observed=InvokeTool $finalSwitchRunner @{InputPath=$inputPath} $Project
    if($observed.code-ne91){throw ('FINAL_STATE_SWITCH_CHILD_EXIT|expected=91|observed='+$observed.code+'|'+$observed.text)}
    Check ($observed.code-eq91) ($Name+'-actual-process-interrupted-after-real-postcheck') | Out-Host
    $marker=Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json -Depth 100
    $transactionPath=Get-AiwContainedPath $Project $TransactionRelative
    $pending=(Read-AiwProjectJson $transactionPath 'FINAL_SWITCH_PENDING').Value
    Check ($marker.status-ceq'POSTCHECK_PASSED'-and$marker.transactionIdentity-ceq(Id $transactionPath)-and$pending.state-ceq'APPLYING'-and$pending.transactionComplete-is[bool]-and-not$pending.transactionComplete-and$pending.completedWrites-eq@($Projection.objects|Where-Object changed).Count) ($Name+'-validated-group-awaits-final-journal-switch') | Out-Host
    Check (@($Projection.objects|Where-Object{(FixtureObjectIdentity (Get-AiwContainedPath $Project $_.path))-cne$_.newIdentity}).Count-eq0) ($Name+'-all-postimages-written-before-state-switch') | Out-Host
    return [pscustomobject]@{status='INTERRUPTED';transactionIdentity=(Id $transactionPath);writes=$pending.completedWrites;processExitCode=$observed.code}
}
function NewRefreshAction([hashtable]$Scope,[string]$TargetRuntime,$Template,[string]$PackagePath){
    $arguments=$Scope.Clone();$arguments.WorkspaceRoot=$TargetRuntime
    $arguments.ExpectedActorRouteTaskIdentity=Id (Join-Path $arguments.RepositoryPath $arguments.ActorRouteTaskPath)
    $tool=Join-Path $TargetRuntime 'scripts/upgrade-project.ps1';$preview=Run $tool $arguments
    $pre=@{};$post=@{};$paths=@();$canonical='';$manifest=''
    foreach($line in $preview){
        if($line-match'^UPGRADE_PREIMAGE\|(?<path>.+)=(?<id>NEW|\d+\|[A-F0-9]{64})$'){$pre[$Matches.path]=$Matches.id}
        elseif($line-match'^UPGRADE_POSTIMAGE\|(?<path>.+)=(?<id>ABSENT|\d+\|[A-F0-9]{64})$'){$post[$Matches.path]=$Matches.id}
        elseif($line-match'^UPGRADE_WRITESET\|(?<paths>.+)$'){$paths=@($Matches.paths-split'\|')}
        elseif($line-match'^UPGRADE_TARGET_RELEASE\|canonical=(?<hash>[A-F0-9]{64})\|manifest=(?<id>\d+\|[A-F0-9]{64})$'){$canonical=$Matches.hash;$manifest=$Matches.id}
    }
    if($paths.Count-lt1-or$pre.Count-ne$paths.Count-or$post.Count-ne$paths.Count-or-not$canonical-or-not$manifest){throw 'REFRESH_PREVIEW_INCOMPLETE'}
    $authorization=Clone $Template;$authorization.taskIdentity=$arguments.ExpectedActorRouteTaskIdentity
    $authorization.projectConfigIdentity=Id (Join-Path $arguments.RepositoryPath '.ai-workspace/project.json')
    $authorization.controllerControlIdentity=Id (Join-Path $arguments.RepositoryPath '.ai-workspace/controller.json')
    $authorization.userConfirmation='ISOLATED_TEST_APPROVED_RUNTIME_REFRESH';$authorization.exactPaths=$paths
    $authorization.objectIdentities=@($paths|ForEach-Object{[ordered]@{path=$_;identity=$pre[$_]}})
    $authorization.postObjectIdentities=@($paths|ForEach-Object{[ordered]@{path=$_;identity=$post[$_]}})
    $authorization.targetFrameworkSnapshot=@{canonical=$canonical;manifestIdentity=$manifest};SaveJson $PackagePath $authorization
    $arguments.Apply=$true;$arguments.AuthorizationPackagePath=$PackagePath;$arguments.ExpectedAuthorizationPackageIdentity=Id $PackagePath
    return [pscustomobject]@{tool=$tool;arguments=$arguments;authorization=$authorization}
}
function ReadCurrent([string]$TargetRuntime,[string]$Case,$InputTemplate,[string]$InputPath,[switch]$AllowFailure){
    $request=Clone $InputTemplate;$request.frameworkRoot=$TargetRuntime
    $request.expectedProjectConfigIdentity=Id (Join-Path $request.projectRoot '.ai-workspace/project.json')
    $request.expectedCorrectionsIdentity=Id (Join-Path $request.projectRoot '.ai-workspace/corrections.json')
    $request.expectedTaskIdentity=Id $request.taskPath
    Set-FixtureDiscoverContract $request $TargetRuntime
    SaveJson $InputPath $request
    $tool=if($Case-ceq'MAINTENANCE'){Join-Path $TargetRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $TargetRuntime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
    if($AllowFailure){
        $actual=InvokeTool $tool @{InputPath=$InputPath;AsJson=$true}
        $value=if($actual.code-eq0){$actual.value}else{$actual.text|ConvertFrom-Json -Depth 100}
        $value|Add-Member fixtureExitCode $actual.code
        return $value
    }
    return Run $tool @{InputPath=$InputPath;AsJson=$true}
}
function CurrentCorrectionCases([string]$Project,[string]$Case,$InputTemplate){
    $binding=Get-AiwAdoptedDistributionBinding $Project '2.0.0';$currentRuntime=[string]$binding.runtimeRoot
    Import-Module (Join-Path $currentRuntime 'scripts/ProjectCorrectionLifecycle.psm1') -Force
    $currentResolver=if($Case-ceq'MAINTENANCE'){Join-Path $currentRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $currentRuntime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
    $carrierPath=Join-Path $Project '.ai-workspace/corrections.json';$configPath=Join-Path $Project '.ai-workspace/project.json'
    $configuration=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
    $carrier=Get-Content -LiteralPath $carrierPath -Raw|ConvertFrom-Json -Depth 100
    Check ($configuration.schemaVersion-eq7-and$carrier.schemaVersion-eq3) ($Case+'-current-lifecycle-uses-real-project6-and-carrier3')
    $script:currentCorrectionSerial=0;$script:currentCorrectionEvidencePaths=@()
    $owned='correction-effects/owned.txt';$taskRelative='.ai-workspace/tasks/active/CORRECTION-CURRENT.md'
    $role=if($Case-ceq'MAINTENANCE'){'FRAMEWORK_MAINTAINER'}else{'TASK_OWNER'}
    $fixtureRuntime=Join-Path $Project '.ai-workspace/runtime/CORRECTION-CURRENT/major-owner'
    function CurrentRecord([string]$Name,[string]$Body){
        [pscustomobject]@{correctionId=$Name;introducedAgainstFramework='2.0.0';requirementReason='isolated current lifecycle fixture';effectiveRule=$Body;applicability='fixture only';decisionLocator='fixture:current-lifecycle';selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@('never-selected-current-fixture')};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@()}
    }
    # An existing rule without claimed installation is legitimate fixture input.
    # Its unmatched selector must not hide it from whole-effective-set checks.
    $anchor=CurrentRecord CURRENT_ANCHOR 'Current lifecycle duplicate comparison sentinel.'
    # A real hard role mismatch makes the anchor unselected under facets too.
    $anchor.selectors.roles=@('REVIEWER')
    $carrier.corrections+=@($anchor);SaveJson $carrierPath $carrier
    function CurrentPlan([string]$Operation,[string]$Body='',[string]$Name='CURRENT_RULE'){
        $script:currentCorrectionSerial++;$segment='current-'+$script:currentCorrectionSerial
        $install=$Operation-ceq'INSTALL';$base='.ai-workspace/upgrade-recovery/corrections/'+$Name+'/'+$segment+'/'
        [pscustomobject]@{schemaVersion=1;operation=$Operation;correctionId=$Name;expectedCorrectionsIdentity=(Id $carrierPath);decisionLocator='fixture:current-lifecycle';forbiddenPaths=@('private');record=$(if($Operation-cin@('INSTALL','REVISE')){CurrentRecord $Name $Body}else{'NOT_APPLICABLE'});installation=$(if($install){[pscustomobject]@{schemaVersion=1;correctionId=$Name;decisionLocator='fixture:actual-current-install';dependsOn=@();changes=@(if($Name-ceq'CURRENT_RULE'){[pscustomobject]@{kind='FILE';path=$owned;beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String($utf8.GetBytes('current owned effect'))}})}}else{'NOT_APPLICABLE'});installationRelativePath=$(if($install){$base+'installation.json'}else{'NOT_APPLICABLE'});transactionRelativePath=$base+'state.json';impact=[pscustomobject]@{stoppedObligations=@('current fixture rule');independentObligations=@('existing anchor and project sources');inFlightEffects=@();recovery='exact current projection rollback';semanticAssessment='isolated fixture with one owned file'}}
    }
    function CurrentSignature($Plan){
        $paths=@('.ai-workspace/corrections.json','.ai-workspace/project.json','.ai-workspace/process-policy.json','.ai-workspace/BOOTSTRAP.md',$owned,$Plan.transactionRelativePath,$Plan.transactionRelativePath.Replace('state.json','history.json'))+@($script:currentCorrectionEvidencePaths)
        if($Plan.installationRelativePath-cne'NOT_APPLICABLE'){$paths+=@($Plan.installationRelativePath)}
        return (@($paths|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $Project $_))}})|ConvertTo-Json -Depth 10 -Compress)
    }
    function RejectCurrentPlan($Plan,[string]$Name){
        $path=Join-Path $fixtureRuntime ('negative-'+$script:currentCorrectionSerial+'.json');SaveJson $path $Plan
        $before=CurrentSignature $Plan
        RejectCall {Invoke-AiwCorrectionLifecycle -RepositoryRoot $Project -PlanPath $path -ExpectedPlanIdentity (Id $path) -ProjectId $configuration.id -Version '2.0.0' -Apply} 'DUPLICATE_EFFECTIVE_RULE' ($Case+'-'+$Name)
        Check ((CurrentSignature $Plan)-ceq$before) ($Case+'-'+$Name+'-zero-group-write')
    }
    function ApplyCurrentPlan($Plan){
        $number=$script:currentCorrectionSerial;$path=Join-Path $fixtureRuntime ('plan-'+$number+'.json');SaveJson $path $Plan
        $preview=Invoke-AiwCorrectionLifecycle -RepositoryRoot $Project -PlanPath $path -ExpectedPlanIdentity (Id $path) -ProjectId $configuration.id -Version '2.0.0'
        Check ($preview.status-ceq'READY') ($Case+'-current-'+$Plan.operation+'-'+$number+'-real-preview') | Out-Host
        $exact=@($preview.projection.objects.path)
        SaveText (Join-Path $Project $taskRelative) ("# CORRECTION-CURRENT — Isolated current lifecycle`n`n- Task schema: 2.0.0`n- Profile: CRITICAL; reason=current correction transaction`n- Owner: major-owner`n- Work route: actor=major-owner; role=$role; phase=IMPLEMENT`n- Status: ACTIVE`n- Phase gate: FALSE`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE_WRITE; expected_paths=["+($exact-join'|')+"]; actual_paths=[]`n- Writer / reviewer / authorization: isolated fixture`n- Stable candidate: NONE`n- Git / push / external: DEFERRED`n")
        $authorization=[ordered]@{schemaVersion=$(if($Case-ceq'MAINTENANCE'){2}else{1});frameworkVersion='2.0.0';taskId='CORRECTION-CURRENT';profile='CRITICAL';lifecycle='ACTIVE';owner='major-owner';issuer='major-owner';issuerRole='PROJECT_CONTROLLER';issuerControllerId='major-owner';issuerControllerEpoch=1;controllerControlIdentity=(Id (Join-Path $Project '.ai-workspace/controller.json'));grantee='major-owner';bundle='CURRENT_CORRECTION_LIFECYCLE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='ISOLATED_TEST_CURRENT_CORRECTION_DECISION';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id (Join-Path $Project $taskRelative));actions=@('CONTROL_WRITE');exactPaths=$exact;objectIdentities=@($exact|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $Project $_))}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Id $configPath)}
        if($Case-ceq'MAINTENANCE'){$authorization.repositoryId='CONTROL';$authorization.invalidatesOn+=@('REPOSITORY_CHANGE')}
        $authorizationPath=Join-Path $fixtureRuntime ('package-'+$number+'.json');SaveJson $authorizationPath $authorization
        $checker=@{PackagePath=$authorizationPath;ObservedActor='major-owner';ObservedTaskId='CORRECTION-CURRENT';ObservedOwner='major-owner';ObservedAction=@('CONTROL_WRITE');ObservedPath=$exact;ObservedIdentity=@($exact|ForEach-Object{$_+'='+(Id (Join-Path $Project $_))});ExpectedProjectConfigIdentity=$authorization.projectConfigIdentity;TaskPath=$taskRelative;ExpectedTaskIdentity=$authorization.taskIdentity}
        if($Case-ceq'MAINTENANCE'){$checker.ControlRepositoryPath=$Project;$checker.ObservedRepositoryId='CONTROL';$checkerTool=Join-Path $currentRuntime 'scripts/check-framework-maintenance-authorization.ps1'}
        else{$checker.ProjectConfigPath='.ai-workspace/project.json';$checker.ControllerControlPath='.ai-workspace/controller.json';$checkerTool=Join-Path $currentRuntime 'framework/versions/2.0.0/scripts/check-authorization.ps1'}
        $checked=Run $checkerTool $checker $Project;Check (($checked-join"`n").StartsWith('PASS|')) ($Case+'-current-'+$Plan.operation+'-'+$number+'-independent-checker') | Out-Host
        $request=Clone $InputTemplate;$request.frameworkRoot=$currentRuntime;$request.taskPath=Join-Path $Project $taskRelative;$request.expectedTaskIdentity=$authorization.taskIdentity
        $request.expectedProjectConfigIdentity=$authorization.projectConfigIdentity;$request.expectedCorrectionsIdentity=Id $carrierPath;$request.exactPaths=$exact;$request.forbiddenPaths=@('private')
        $request.authorizationPackagePath=$authorizationPath;$request.expectedAuthorizationIdentity=Id $authorizationPath;$request.userDecision=$authorization.userConfirmation
        $request.intentEnvelope.requestedActionKind='CONTROL_WRITE';$request.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$request.intentEnvelope.objective='Execute the exact current correction lifecycle operation and preserve original rule and installation history.';$request.intentEnvelope.semanticHints=@('project correction','correction lifecycle');$request.intentEnvelope.mutationHints=@('control')
        $request.intentEnvelope.facets=[ordered]@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:rule-maintenance')};deliverableType=@{state='KNOWN';values=@('aiw:rule','aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:implementation')}}
        $inputPath=Join-Path $fixtureRuntime ('discover-'+$number+'.json');SaveJson $inputPath $request
        $discovered=Run $currentResolver @{InputPath=$inputPath;AsJson=$true};Check ($discovered.status-ceq'PASS') ($Case+'-current-'+$Plan.operation+'-'+$number+'-actual-discover') | Out-Host
        Check (@($discovered.selectedRuleBlocks|Where-Object requirementId -CEQ 'framework:PR_CORRECTIONS_V2_COMPATIBILITY').Count-eq1) ($Case+'-current-'+$Plan.operation+'-'+$number+'-actual-lifecycle-rule-selected') | Out-Host
        $receiptPath=Join-Path $fixtureRuntime ('receipt-'+$number+'.json');SaveJson $receiptPath $discovered.compactReceipt
        $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
        $admitPath=Join-Path $fixtureRuntime ('admit-'+$number+'.json');SaveJson $admitPath $boundary
        $admitted=Run $currentResolver @{InputPath=$admitPath;AsJson=$true};Check ($admitted.status-ceq'PASS') ($Case+'-current-'+$Plan.operation+'-'+$number+'-actual-admit') | Out-Host
        $applied=Invoke-AiwCorrectionLifecycle -RepositoryRoot $Project -PlanPath $path -ExpectedPlanIdentity (Id $path) -ProjectId $configuration.id -Version '2.0.0' -Apply -AdmitInputPath $admitPath -ExpectedAdmitInputIdentity (Id $admitPath)
        Check ($applied.status-ceq'COMPLETE') ($Case+'-current-'+$Plan.operation+'-'+$number+'-actual-apply-and-composition-postcheck') | Out-Host
        $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($discovered.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@($preview.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.newIdentity})
        $finalPath=Join-Path $fixtureRuntime ('final-'+$number+'.json');SaveJson $finalPath $boundary
        $finalized=Run $currentResolver @{InputPath=$finalPath;AsJson=$true};Check ($finalized.status-ceq'PASS') ($Case+'-current-'+$Plan.operation+'-'+$number+'-actual-original-finalize') | Out-Host
        foreach($entry in $preview.projection.objects){Check ((Id (Join-Path $Project $entry.path))-ceq$(if($entry.newExists){$entry.newIdentity}else{'NEW'})) ($Case+'-current-'+$Plan.operation+'-'+$number+'-exact-postimage-'+$entry.path) | Out-Host}
        $script:currentCorrectionEvidencePaths+=@($preview.projection.objects.path)+@($Plan.transactionRelativePath)
        return @((Get-Content -LiteralPath $carrierPath -Raw|ConvertFrom-Json -Depth 100).corrections|Where-Object correctionId -CEQ CURRENT_RULE)[0]
    }
    $installed=ApplyCurrentPlan (CurrentPlan INSTALL 'Current unique installed rule.')
    Check ($installed.lifecycle.state-ceq'ACTIVE'-and(Test-Path -LiteralPath (Join-Path $Project $owned))) ($Case+'-current-install-owns-real-effect')
    RejectCurrentPlan (CurrentPlan INSTALL $anchor.effectiveRule CURRENT_DUPLICATE) 'current-install-rejects-unselected-duplicate'
    RejectCurrentPlan (CurrentPlan REVISE $anchor.effectiveRule) 'current-revise-rejects-unselected-duplicate'
    $revised=ApplyCurrentPlan (CurrentPlan REVISE 'Current unique revised rule.')
    $history=Get-Content -LiteralPath (Join-Path $Project $revised.history.locator) -Raw|ConvertFrom-Json -Depth 100
    Check ($revised.lifecycle.installation.identity-ceq$installed.lifecycle.installation.identity-and($history.priorRecord|ConvertTo-Json -Depth 100 -Compress)-ceq($installed|ConvertTo-Json -Depth 100 -Compress)) ($Case+'-current-revise-preserves-real-installation-and-entire-prior-record')
    $paused=ApplyCurrentPlan (CurrentPlan PAUSE)
    Check ($paused.lifecycle.state-ceq'PAUSED'-and-not(Test-Path -LiteralPath (Join-Path $Project $owned))) ($Case+'-current-pause-removes-owned-effect')
    $carrier=Get-Content -LiteralPath $carrierPath -Raw|ConvertFrom-Json -Depth 100
    @($carrier.corrections|Where-Object correctionId -CEQ CURRENT_ANCHOR)[0].effectiveRule=$paused.effectiveRule;SaveJson $carrierPath $carrier
    RejectCurrentPlan (CurrentPlan RESUME) 'current-resume-rejects-later-active-duplicate'
    @($carrier.corrections|Where-Object correctionId -CEQ CURRENT_ANCHOR)[0].effectiveRule=$anchor.effectiveRule;SaveJson $carrierPath $carrier
    $resumed=ApplyCurrentPlan (CurrentPlan RESUME)
    Check ($resumed.lifecycle.state-ceq'ACTIVE'-and[IO.File]::ReadAllText((Join-Path $Project $owned))-ceq'current owned effect') ($Case+'-current-resume-restores-real-owned-effect')
    $uninstalled=ApplyCurrentPlan (CurrentPlan UNINSTALL)
    Check ($uninstalled.lifecycle.state-ceq'UNINSTALLED'-and-not(Test-Path -LiteralPath (Join-Path $Project $owned))-and(Test-Path -LiteralPath (Join-Path $Project $installed.lifecycle.installation.locator))) ($Case+'-current-uninstall-retains-installation-and-history')
    $observed=ReadCurrent $currentRuntime $Case $InputTemplate (Join-Path $fixtureRuntime 'readback.json')
    Import-Module (Join-Path $currentRuntime 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -Force
    $composed=Invoke-ProcessRequirementComposition -ProjectRoot $Project -FrameworkRoot $currentRuntime -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity (Id $configPath) -ExpectedCorrectionsIdentity (Id $carrierPath) -Profile CRITICAL -Role $role -Phase IMPLEMENT -Actor major-owner -TaskIdentity (Id $InputTemplate.taskPath) -Objective 'Read the current correction lifecycle set.' -ActionKind NONE -ResultKind PLAN -Capabilities @($InputTemplate.capabilities)
    Check ($observed.status-ceq'PASS'-and@($composed.inactive|Where-Object correctionId -CEQ CURRENT_RULE).Count-eq1-and@($composed.stillEffective|Where-Object correctionId -CEQ CURRENT_RULE).Count-eq0) ($Case+'-current-uninstalled-rule-stays-inactive-on-normal-discover')
}
function CurrentProviderCases {
    # Current registered project; the seed below is synthetic completed pilot
    # history, not a replay of an old upgrade or release evidence. All tested
    # PREPARE/admission/apply/finalize/recovery calls are real public root calls.
    $project=Join-Path $temp 'current-provider';$projectId='current-provider';$owner='major-owner';$actor=$owner
    $null=[IO.Directory]::CreateDirectory($project)
    $null=Run (Join-Path $workspace 'scripts/register-project.ps1') @{ProjectId=$projectId;DisplayName='Current provider fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId=$owner;WorkspaceRoot=$workspace;Apply=$true}
    $configPath=Join-Path $project '.ai-workspace/project.json';$policyPath=Join-Path $project '.ai-workspace/process-policy.json'
    $configuration=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100
    Check ($configuration.schemaVersion-eq7) 'provider-root-fixture-is-publicly-registered-current-project'
    # Registration consumes a synthetic stable fixture. The following actual
    # same-pin workflow consumes a synthetic completed candidate pilot, so its
    # original runtime must also have candidate lifecycle before binding it.
    $version=Join-Path $workspace 'framework/versions/2.0.0'
    foreach($name in @('VERSION.json','LOAD_MANIFEST.json','RELEASE_MANIFEST.json')){
        $path=Join-Path $version $name;$value=Get-Content $path -Raw|ConvertFrom-Json -Depth 100;$value.lifecycle='CANDIDATE'
        if($name-ceq'VERSION.json'){$value.consumable=$false;$value.projectPinEligible=$false}
        SaveJson $path $value
    }
    SealFixture $version;NamedFixture $workspace
    $gitSource=Join-Path $temp 'provider-git';$null=[IO.Directory]::CreateDirectory($gitSource)
    foreach($arguments in @(@('init','-q'),@('config','user.name','Fixture'),@('config','user.email','fixture@example.invalid'))){& git -C $gitSource @arguments;if($LASTEXITCODE-ne0){throw 'PROVIDER_FIXTURE_GIT'}}
    SaveText (Join-Path $gitSource 'rule.md') 'Exact adopted Git normative body.'
    $gitIdentity=Id (Join-Path $gitSource 'rule.md')
    & git -C $gitSource add -- rule.md;& git -C $gitSource commit -qm first;if($LASTEXITCODE-ne0){throw 'PROVIDER_FIXTURE_GIT'}
    $commit=(& git -C $gitSource rev-parse HEAD).Trim()
    SaveText (Join-Path $gitSource 'rule.md') 'Later working-tree bytes must not replace the adopted commit.'
    $httpBody=$utf8.GetBytes('Exact adopted offline HTTPS normative body.');$httpIdentity=Get-AiwByteIdentity $httpBody
    $configuration.sourceBindings=@(
        [pscustomobject]@{id='git';provider='GIT_REVISION';locator=[pscustomobject]@{repository=$gitSource};allowedPaths=@([pscustomobject]@{kind='FILE';locator='rule.md'});decisionLocator='fixture:exact-git-read'},
        [pscustomobject]@{id='https';provider='HTTPS_RESOURCE';locator=[pscustomobject]@{baseUrl='https://127.0.0.1:1/fixture/'};allowedPaths=@([pscustomobject]@{kind='FILE';locator='rule.md'});decisionLocator='fixture:exact-offline-https-read'})
    $version=Join-Path $workspace 'framework/versions/2.0.0'
    Import-Module (Join-Path $version 'scripts/ContentSources.psm1') -Force
    Import-Module (Join-Path $version 'scripts/ProcessRequirementComposition.psm1') -Force
    $rules=@()
    foreach($name in @('git','https')){
        $revision=if($name-ceq'git'){[pscustomobject]@{kind='GIT_COMMIT';value=$commit}}else{[pscustomobject]@{kind='CONTENT_IDENTITY';value=$httpIdentity}}
        $doc=[pscustomobject]@{sourceId=$name.ToUpperInvariant();bindingId=$name;revision=$revision;locator='rule.md';identity=$(if($name-ceq'git'){$gitIdentity}else{$httpIdentity});mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
        $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$name;itemId=$name.ToUpperInvariant();revision=$revision;itemIdentity='';rootSourceId=$doc.sourceId;documents=@($doc)}
        if($name-ceq'https'){$descriptor.revision=Get-AiwContentRevision $descriptor $configuration.sourceBindings}
        $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
        $rules+=@([pscustomobject]@{ruleId=$name.ToUpperInvariant();requirementReason='Provider root consumer fixture';decisionLocator='fixture:exact-adoption';source=$descriptor;selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()})
    }
    SaveJson $configPath $configuration;SaveJson $policyPath @{schemaVersion=3;contractVersion='2.0.0';projectId=$projectId;rules=$rules}
    # A raw HTTPS cache fixture is selected through the actual adopted descriptor
    # and permission identities. No transport/composer/root callback is mocked;
    # this proves the offline PINNED path, not a live HTTPS network observation.
    $ctx=New-AiwContentContext $project (Id $configPath);$snapshot=Resolve-AiwContentSnapshot $ctx $rules[1].source
    $fact=$snapshot.facts.documents[0];$key=(Get-AiwContentDescriptorIdentity ([ordered]@{projectRoot=$ctx.ProjectRoot;document=$fact.document;adoptedItem=$snapshot.facts.adoptionIdentity;binding=$fact.bindingIdentity;implementation=$ctx.ImplementationIdentity})).Split('|')[1]
    $httpCache=Join-Path $ctx.CacheRoot ($key+'.bin');$null=[IO.Directory]::CreateDirectory($ctx.CacheRoot);[IO.File]::WriteAllBytes($httpCache,$httpBody)
    Check ((Test-AiwContentSnapshot $ctx $snapshot).observations[0]-ceq'PINNED_CACHE') 'provider-root-https-cache-is-actually-validated-as-exact-pinned-source'
    $taskRelative='.ai-workspace/tasks/active/PROVIDER-001.md';$scopePaths=@('.ai-workspace/upgrade-recovery/2.0.0/state.json','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json')
    SaveText (Join-Path $project $taskRelative) ("# PROVIDER-001 — Current provider adoption fixture`n- Task schema: 2.0.0`n- Profile: CRITICAL; reason=provider adoption fixture`n- Owner: major-owner`n- Work route: actor=major-owner; role=TASK_OWNER; phase=IMPLEMENT`n- Phase gate: FALSE`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; expected_paths=["+($scopePaths-join'|')+"]; actual_paths=[]`n- Writer / reviewer / authorization: isolated fixture`n- Stable candidate: NONE`n- Git / push / external: DEFERRED`n")
    $recoveryRoot=Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0';$objects=@();$records=@()
    foreach($relative in @('.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','AGENTS.md',$taskRelative)){
        $identity=Id (Join-Path $project $relative);$objects+=@(@{relative=$relative;oldIdentity='MISSING';newIdentity=$identity});$record=[ordered]@{relative=$relative;identity=$identity}
        if($relative-ceq'.ai-workspace/BOOTSTRAP.md'){$record.managedIdentity=(Get-AiwProjectCustomRegion (Join-Path $project $relative)).ManagedIdentity}
        $records+=@($record);CopyFile (Join-Path $project $relative) (Join-Path $recoveryRoot ('new/'+$relative))
    }
    $manifest=Get-Content (Join-Path $version 'RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json
    SaveJson (Join-Path $recoveryRoot 'state.json') @{schemaVersion=6;transactionComplete=$true;projectId=$projectId;fromVersion='2.0.0';toVersion='2.0.0';targetReleaseCanonical=$manifest.canonical;targetReleaseManifestIdentity=(Id (Join-Path $version 'RELEASE_MANIFEST.json'));actor=$actor;taskId='PROVIDER-001';taskOwner=$owner;taskRelative=$taskRelative;authorizationIdentity=('1|'+('A'*64));objects=$objects;projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=$records;projectFormat='repo-local/project-config-7';projectCapabilities=@();rootToolRevision=('A'*64);rootToolDependencies=@();distributionBinding=(Get-AiwDistributionBinding $workspace '2.0.0' -Required)}
    $runtime=Join-Path $project '.ai-workspace/runtime/PROVIDER-001/major-owner'
    $template=@{schemaVersion=3;frameworkVersion='2.0.0';taskId='PROVIDER-001';profile='CRITICAL';lifecycle='ACTIVE';owner=$owner;issuer=$owner;issuerRole='PROJECT_CONTROLLER';issuerControllerId=$owner;issuerControllerEpoch=1;controllerControlIdentity=(Id (Join-Path $project '.ai-workspace/controller.json'));grantee=$actor;bundle='ACTOR_BOUND_PROJECT_UPGRADE';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='ISOLATED_TEST_APPROVED_RUNTIME_REFRESH';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id (Join-Path $project $taskRelative));actions=@('CONTROL_WRITE');exactPaths=@();objectIdentities=@();postObjectIdentities=@();invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE','POST_OBJECT_DRIFT');projectConfigIdentity=(Id $configPath);targetFrameworkSnapshot=@{canonical='';manifestIdentity=''}}
    $scope=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ControllerId=$owner;WorkspaceRoot=$workspace;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=$template.taskIdentity;ActorRouteActor=$actor}
    $next=$refreshRuntimes[0];$action=NewRefreshAction $scope $next $template (Join-Path $runtime 'root-package.json')
    $process=Clone $action.authorization;$process.schemaVersion=1;$process.bundle='PROVIDER_ORIGINAL_PROCESS';$process.Remove('postObjectIdentities');$process.Remove('targetFrameworkSnapshot');$process.invalidatesOn=@($process.invalidatesOn|Where-Object{$_-cne'POST_OBJECT_DRIFT'})
    $processPath=Join-Path $runtime 'process-package.json';SaveJson $processPath $process
    $intent=@{schemaVersion=2;objective='Adopt the exact refreshed fixed package using the approved Git and offline HTTPS source revisions.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('project adoption','source bindings');pathHints=@();capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:adoption')};deliverableType=@{state='KNOWN';values=@('aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:adoption')}}}
    $request=@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$workspace;taskPath=(Join-Path $project $taskRelative);expectedProjectConfigIdentity=(Id $configPath);expectedCorrectionsIdentity=(Id (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=$template.taskIdentity;observedActor=$actor;capabilities=@();exactPaths=@($action.authorization.exactPaths);forbiddenPaths=@('private');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$processPath;expectedAuthorizationIdentity=(Id $processPath);userDecision=$process.userConfirmation;recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$false}
    Set-FixtureDiscoverContract $request $workspace
    $requestPath=Join-Path $runtime 'discover.json';SaveJson $requestPath $request
    $resolver=Join-Path $version 'scripts/resolve-process-requirements.ps1';$discovered=Run $resolver @{InputPath=$requestPath;AsJson=$true}
    Check ($discovered.status-ceq'PASS'-and(@($discovered.selectedRuleBlocks|Where-Object{$_.requirementId.StartsWith('project:')}).fullText-join'|').Contains('Exact adopted Git normative body.')) 'provider-root-original-public-discover-reads-fixed-git-commit'
    $receiptPath=Join-Path $runtime 'receipt.json';SaveJson $receiptPath $discovered.compactReceipt
    $boundary=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $boundaryPath=Join-Path $runtime 'admit-input.json';SaveJson $boundaryPath $boundary
    $call=$scope.Clone();$call.WorkspaceRoot=$next;$call.CurrentProcessInputPath=$boundaryPath;$call.ExpectedCurrentProcessInputIdentity=Id $boundaryPath;$call.AdoptionProcessMode='PREPARE'
    $before=@($scopePaths|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n"
    $prepared=Run $action.tool $call
    Check ($prepared.status-ceq'PREPARED'-and(@($scopePaths|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n")-ceq$before-and@($prepared.projection.objects|Where-Object{$_.path-cnotin$scopePaths}).Count-eq0) 'provider-root-public-same-pin-prepare-zero-live-or-external-source-write'
    $preparationPath=Join-Path $runtime 'preparation.json';SaveJson $preparationPath $prepared
    $boundary.preparationReceipts=@(@($boundary.preparationReceipts)+@($prepared.selectedRuleBlocks.preparationRequirements)|Sort-Object -Unique)+@('ADOPTION_TARGET_RULES_LOADED|'+(Id $preparationPath));if($prepared.selectorSemanticJudgmentRequired){$boundary.preparationReceipts+=@('ADOPTION_SELECTOR_SEMANTICS_CONFIRMED|'+(Id $preparationPath))}
    SaveJson $boundaryPath $boundary;$call.ExpectedCurrentProcessInputIdentity=Id $boundaryPath;$call.AdoptionProcessMode='ADMIT_ACTION';$call.AdoptionPreparationPath=$preparationPath;$call.ExpectedAdoptionPreparationIdentity=Id $preparationPath
    $admitted=Run $action.tool $call;Check ($admitted.status-ceq'PASS') 'provider-root-public-original-admission'
    $admitPath=Join-Path $runtime 'admit-result.json';SaveJson $admitPath $admitted
    # Both bodies now have exact cache facts. A missing Git directory may not
    # cause the roots to treat the revision locator as a local file.
    $offline=Join-Path $temp 'provider-git-offline';$fixtureBase=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp))+[IO.Path]::DirectorySeparatorChar
    foreach($path in @($gitSource,$offline)){if(-not[IO.Path]::GetFullPath($path).StartsWith($fixtureBase,[StringComparison]::OrdinalIgnoreCase)){throw 'PROVIDER_FIXTURE_MOVE_SCOPE'}}
    [IO.Directory]::Move($gitSource,$offline)
    $action.arguments.AdmitResultPath=$admitPath;$action.arguments.ExpectedAdmitResultIdentity=Id $admitPath
    $applied=Run $action.tool $action.arguments;Check (($applied-join"`n").Contains('LOCAL_CANDIDATE_PROJECT_PROJECTION_REFRESHED')) 'provider-root-public-apply-with-git-and-https-offline-pinned-cache'
    $transactionRelative='.ai-workspace/runtime/project-adoption/upgrade/state.json'
    $journal=Join-Path $project $transactionRelative;$actualTransaction=Get-Content $journal -Raw|ConvertFrom-Json -Depth 100
    $final=Clone $boundary;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@(@($discovered.compactReceipt.selectedObligations.resultRequirements)+@($prepared.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($prepared.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.newExists){$_.newIdentity}else{'ABSENT'})})
    $finalPath=Join-Path $runtime 'final-input.json';SaveJson $finalPath $final
    $finalCall=$call.Clone();$finalCall.AdoptionProcessMode='FINALIZE_OUTPUT';$finalCall.CurrentProcessInputPath=$finalPath;$finalCall.ExpectedCurrentProcessInputIdentity=Id $finalPath;$finalCall.AdmitResultPath=$admitPath;$finalCall.ExpectedAdmitResultIdentity=Id $admitPath;$finalCall.AuthorizationPackagePath=$action.arguments.AuthorizationPackagePath;$finalCall.ExpectedAuthorizationPackageIdentity=$action.arguments.ExpectedAuthorizationPackageIdentity;$finalCall.ExpectedAdoptionTransactionIdentity=Id $journal
    Check ((Run $action.tool $finalCall).status-ceq'PASS') 'provider-root-public-original-finalize-offline-snapshot'
    RestoreFixture $project $actualTransaction.projection
    foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $next ('scripts/'+$name+'.psm1')) -Force}
    Import-Module (Join-Path $next 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -Force
    $nextVersion=Join-Path $next 'framework/versions/2.0.0';$postcheck={param($root,$projection)Assert-AiwRuntimeAdoptionProjection $root $projection $nextVersion '2.0.0' (Id (Join-Path $root '.ai-workspace/project.json'));return $true}.GetNewClosure()
    $stopped=Invoke-AiwProjectProjectionTransaction $project $actualTransaction.projection $transactionRelative $postcheck {$true} -InterruptBeforeJournalWrite 1 -Metadata (Clone $actualTransaction.metadata)
    Check ($stopped.status-ceq'INTERRUPTED') 'provider-root-real-interruption-before-progress-journal'
    $recover=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=(Id $journal);AuthorizationPackagePath=$action.arguments.AuthorizationPackagePath;ExpectedAuthorizationPackageIdentity=$action.arguments.ExpectedAuthorizationPackageIdentity;AdoptionRecoveryDirection='COMPLETE';Apply=$true}
    $group=@($actualTransaction.projection.objects.path)+@($transactionRelative)
    # The persisted receipt is the original byte object, not a freshly minted
    # preparation. Its former runtime path may already have been cleaned up.
    $retainedReceipt=$receiptPath+'.retained';[IO.File]::Move($receiptPath,$retainedReceipt)
    Check ($actualTransaction.metadata.originalAdmitIdentity-ceq(Id $admitPath)-and$actualTransaction.metadata.originalDiscoverIdentity-ceq(Id $retainedReceipt)) 'provider-root-transaction-retains-actual-original-admission-and-discover-identities'
    foreach($fault in @('CACHE_BYTES','PERMISSION','METADATA','SOURCE_REVISION','MISSING_PROOF','PROOF_BYTES','ORIGINAL_CONTEXT')){
        $configBytes=[IO.File]::ReadAllBytes($configPath);$policyBytes=[IO.File]::ReadAllBytes($policyPath);$cacheBytes=[IO.File]::ReadAllBytes($httpCache);$journalBytes=[IO.File]::ReadAllBytes($journal)
        if($fault-ceq'CACHE_BYTES'){[IO.File]::WriteAllBytes($httpCache,$utf8.GetBytes('Invalid exact cache bytes.'))}
        if($fault-ceq'PERMISSION'){$c=Get-Content $configPath -Raw|ConvertFrom-Json -Depth 100;$c.sourceBindings[1].allowedPaths[0].locator='revoked.md';SaveJson $configPath $c}
        if($fault-ceq'METADATA'){$p=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100;$p.rules[1].decisionLocator='fixture:unapproved-metadata-drift';SaveJson $policyPath $p}
        if($fault-ceq'SOURCE_REVISION'){$p=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100;$p.rules[0].source.documents[0].revision.value='0'*40;SaveJson $policyPath $p}
        if($fault-cin@('MISSING_PROOF','PROOF_BYTES','ORIGINAL_CONTEXT')){
            $j=Get-Content $journal -Raw|ConvertFrom-Json -Depth 100
            if($fault-ceq'MISSING_PROOF'){$j.metadata.PSObject.Properties.Remove('originalAdmitBase64')}
            if($fault-ceq'PROOF_BYTES'){$j.metadata.originalDiscoverBase64=[Convert]::ToBase64String($utf8.GetBytes('{}'))}
            if($fault-ceq'ORIGINAL_CONTEXT'){$j.metadata.taskIdentity='1|'+('F'*64)}
            SaveJson $journal $j
        }
        $recover.ExpectedAdoptionTransactionIdentity=Id $journal
        $expectedReason=switch($fault){
            CACHE_BYTES {'CONTENT_IDENTITY_DRIFT|DOCUMENT'}
            PERMISSION {'ADOPTION_RECOVERY_CONTEXT_DRIFT|.ai-workspace/project.json'}
            METADATA {'ADOPTION_RECOVERY_THIRD_PARTY_OBJECT|.ai-workspace/process-policy.json'}
            SOURCE_REVISION {'ADOPTION_RECOVERY_THIRD_PARTY_OBJECT|.ai-workspace/process-policy.json'}
            MISSING_PROOF {'ADOPTION_RECOVERY_ORIGINAL_EVIDENCE_REQUIRED|Admit'}
            PROOF_BYTES {'ADOPTION_RECOVERY_ORIGINAL_EVIDENCE_DRIFT|Discover'}
            ORIGINAL_CONTEXT {'ADOPTION_RECOVERY_ORIGINAL_CONTEXT_DRIFT'}
        }
        if($fault-ceq'CACHE_BYTES'){
            $preview=$recover.Clone();$preview.Remove('Apply');$before=@($group|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n"
            Check ((Run $action.tool $preview).status-ceq'RECOVERY_REQUIRED'-and(@($group|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n")-ceq$before) 'provider-root-preview-keeps-interrupted-group-and-does-not-adopt-invalid-cache'
        }
        $beforeObjects=@($group|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $project $_))}})
        $before=@($beforeObjects|ForEach-Object{$_.path+'='+$_.identity})-join"`n";$rejected=InvokeTool $action.tool $recover
        $afterObjects=@($group|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $project $_))}})
        # Recovery failures use the public text reason plus stack. Preserve
        # parsed=null and match that actual reason, rather than inventing JSON.
        $reasonLine=($rejected.text-split"`n",2)[0].TrimEnd("`r")
        $specificReason=$reasonLine-ceq$expectedReason-or$reasonLine.StartsWith($expectedReason+'|at ',[StringComparison]::Ordinal)
        $zeroWrite=(@($afterObjects|ForEach-Object{$_.path+'='+$_.identity})-join"`n")-ceq$before
        SaveJson (Join-Path $temp ('root-recovery-fault-'+$fault+'.json')) ([ordered]@{fault=$fault;expectedReason=$expectedReason;actualReasonLine=$reasonLine;exitCode=$rejected.code;publicCall=[ordered]@{path=$rejected.recordPath;identity=(Id $rejected.recordPath)};parsed=$rejected.value;before=$beforeObjects;after=$afterObjects;specificReason=$specificReason;zeroGroupAndJournalWrite=$zeroWrite})
        Check ($rejected.code-ne0-and$specificReason-and$zeroWrite) ('provider-root-public-recovery-rejects-'+$fault+'-specific-reason-zero-group-write')
        [IO.File]::WriteAllBytes($configPath,$configBytes);[IO.File]::WriteAllBytes($policyPath,$policyBytes);[IO.File]::WriteAllBytes($httpCache,$cacheBytes);[IO.File]::WriteAllBytes($journal,$journalBytes)
    }
    function RejectOldRuntimeDrift([string]$Direction) {
        $relative='framework/versions/2.0.0/CHANGELOG.md'
        $oldFile=Join-Path $actualTransaction.metadata.previousDistribution.runtimeRoot $relative
        $oldBytes=[IO.File]::ReadAllBytes($oldFile)
        try{
            [IO.File]::WriteAllBytes($oldFile,[byte[]](@($oldBytes)+@($utf8.GetBytes('Unrelated old package drift.'))))
            $probe=$recover.Clone();$probe.AdoptionRecoveryDirection=$Direction;$probe.ExpectedAdoptionTransactionIdentity=Id $journal
            $beforeObjects=@($group|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $project $_))}})
            $rejected=InvokeTool $action.tool $probe
            $afterObjects=@($group|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $project $_))}})
            $expected='DISTRIBUTION_CONTENT_DRIFT|'+$relative
            $reason=($rejected.text-split"`n",2)[0].TrimEnd([char]13)
            $specific=$reason-ceq$expected-or$reason.StartsWith($expected+'|at ',[StringComparison]::Ordinal)
            $zero=(@($beforeObjects|ForEach-Object{$_.path+'='+$_.identity})-join'|')-ceq(@($afterObjects|ForEach-Object{$_.path+'='+$_.identity})-join'|')
            SaveJson (Join-Path $temp ('root-recovery-fault-OLD_RUNTIME_'+$Direction+'.json')) ([ordered]@{fault=('OLD_RUNTIME_'+$Direction);expectedReason=$expected;actualReasonLine=$reason;exitCode=$rejected.code;publicCall=[ordered]@{path=$rejected.recordPath;identity=(Id $rejected.recordPath)};originalRuntime=$actualTransaction.metadata.previousDistribution;driftedFile=$relative;before=$beforeObjects;after=$afterObjects;specificReason=$specific;zeroGroupAndJournalWrite=$zero})
            Check ($rejected.code-ne0-and$specific-and$zero) ('provider-root-old-package-drift-'+$Direction+'-rejects-before-group-or-journal-write')
        }finally{[IO.File]::WriteAllBytes($oldFile,$oldBytes)}
    }
    RejectOldRuntimeDrift COMPLETE
    $recover.ExpectedAdoptionTransactionIdentity=Id $journal
    $done=Run $action.tool $recover;Check ($done.status-ceq'COMPLETE') 'provider-root-public-recovery-completes-with-exact-offline-snapshot'
    [IO.File]::Move($retainedReceipt,$receiptPath)
    $finalCall.ExpectedAdoptionTransactionIdentity=Id $journal;Check ((Run $action.tool $finalCall).status-ceq'PASS') 'provider-root-original-finalize-after-real-recovery'
    [IO.File]::WriteAllBytes($httpCache,$utf8.GetBytes('Invalid cache after completed adoption.'))
    $recover.ExpectedAdoptionTransactionIdentity=Id $journal;$before=@($group|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n";$closed=Run $action.tool $recover
    Check ($closed.status-ceq'COMPLETE'-and$closed.writes-eq0-and(@($group|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n")-ceq$before) 'provider-root-completed-recovery-is-zero-write-without-new-provider-adoption'
    # ROLLBACK restores admitted preimages and does not read/adopt the target
    # external bodies. The same original evidence and whole-object guards apply.
    RestoreFixture $project $actualTransaction.projection
    $stopped=Invoke-AiwProjectProjectionTransaction $project $actualTransaction.projection $transactionRelative $postcheck {$true} -InterruptBeforeJournalWrite 1 -Metadata (Clone $actualTransaction.metadata)
    Check ($stopped.status-ceq'INTERRUPTED') 'provider-root-rollback-neighbor-real-interruption'
    RejectOldRuntimeDrift ROLLBACK
    $recover.ExpectedAdoptionTransactionIdentity=Id $journal;$recover.AdoptionRecoveryDirection='ROLLBACK';$rolled=Run $action.tool $recover
    Check ($rolled.status-ceq'ROLLED_BACK'-and@($actualTransaction.projection.objects|Where-Object{(FixtureObjectIdentity (Join-Path $project $_.path))-cne$_.oldIdentity}).Count-eq0) 'provider-root-rollback-restores-original-group-with-invalid-target-cache'
    $recover.ExpectedAdoptionTransactionIdentity=Id $journal;$before=@($group|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n";$closed=Run $action.tool $recover
    Check ($closed.status-ceq'ROLLED_BACK'-and$closed.writes-eq0-and(@($group|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join"`n")-ceq$before) 'provider-root-rolled-back-recovery-is-zero-write'
    [IO.File]::WriteAllBytes($httpCache,$httpBody)
    Check ([IO.File]::ReadAllText((Join-Path $offline 'rule.md')).Contains('Later working-tree bytes')-and@($actualTransaction.projection.objects|Where-Object{$_.path-cnotin$scopePaths}).Count-eq0) 'provider-root-external-git-source-never-enters-write-group'
    Write-Output ('CURRENT_PROVIDER_ROOT_TESTS|PASS|'+$passed+'|git=ACTUAL_LOCAL_COMMIT_AND_OFFLINE_CACHE|https=EXACT_RAW_CACHE_FIXTURE_NO_LIVE_NETWORK')
}
try {
    $runner=Join-Path $temp 'invoke.ps1'
    SaveText $runner @'
param([string]$InputPath)
$ErrorActionPreference='Stop'
try {
    $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
    Set-Location -LiteralPath $call.workingDirectory;[Environment]::CurrentDirectory=$call.workingDirectory
    $arguments=$call.parameters;$LASTEXITCODE=0
    $output=@(& $call.tool @arguments)
    if($LASTEXITCODE-ne0){$output|ForEach-Object{Write-Output $_};exit $LASTEXITCODE}
    ConvertTo-Json -InputObject $output -Depth 100 -Compress
} catch { Write-Output ($_.Exception.Message+'|'+$_.ScriptStackTrace);exit 2 }
'@
    $finalSwitchRunner=Join-Path $temp 'interrupt-final-state-switch.ps1'
    SaveText $finalSwitchRunner @'
param([string]$InputPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -Depth 100
$metadata=@{};foreach($field in $call.metadata.PSObject.Properties){$metadata[$field.Name]=$field.Value}
foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $call.runtimeRoot ('scripts/'+$name+'.psm1')) -Force}
$versionRoot=Join-Path $call.runtimeRoot 'framework/versions/2.0.0'
Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
$postcheck={param($root,$candidate)
    Assert-AiwRuntimeAdoptionProjection $root $candidate $versionRoot '2.0.0' $call.projectConfigIdentity
    $path=Get-AiwContainedPath $root $call.transactionRelative
    $bytes=[IO.File]::ReadAllBytes($path)
    $identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $marker=@{status='POSTCHECK_PASSED';transactionIdentity=$identity}|ConvertTo-Json -Compress
    [IO.File]::WriteAllText($call.markerPath,$marker+[char]10,[Text.UTF8Encoding]::new($false))
    # Stop the actual process after prospective validation, while the engine's
    # final COMPLETE write is still pending. No journal bytes are fabricated,
    # and no source callback or writer is replaced by a success mock.
    [Environment]::Exit(91)
}.GetNewClosure()
$null=Invoke-AiwProjectProjectionTransaction $call.projectRoot $call.projection $call.transactionRelative $postcheck {param($r,$p) $true} -Metadata $metadata
throw 'FINAL_STATE_SWITCH_INTERRUPT_NOT_REACHED'
'@
    if($ModuleBindingOnly){if($RetainedModuleBindingEvidence){Invoke-RetainedModuleBindingCases}else{Invoke-ModuleBindingCases};return}
    if($SeedTargetRoot){
        $workspace=[IO.Path]::GetFullPath($SeedTargetRoot)
        Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionState.psm1') -Force
        $seedBinding=Get-AiwDistributionBinding $workspace '2.0.0' -Required
        if($seedBinding.distributionId-cne'2.0.0-snapshot.3'){throw 'HISTORY_SEED_TARGET_REQUIRED'}
        $refreshRuntimes=@()
    }else{
    $workspace=Join-Path $temp 'runtime-2'
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'scripts') -File){CopyFile $file.FullName (Join-Path $workspace ('scripts/'+$file.Name))}
    if($BaselineTransactionModule){
        if(-not$NonOwner-or$Layout-cne'ORDINARY'){throw 'BASELINE_DELIVERY_PROBE_REQUIRES_ORDINARY_NONOWNER'}
        CopyFile $BaselineTransactionModule (Join-Path $workspace 'scripts/ProjectAdoptionTransaction.psm1')
    }
    # This private schema2 mechanism fixture supplies its own qualification.
    # Development prepackage evidence belongs to the original candidate and is
    # not a declared attachment of this newly sealed fixture.
    $sourceVersion=Join-Path $sourceRoot 'framework/versions/2.0.0'
    $fixtureVersion=Join-Path $workspace 'framework/versions/2.0.0'
    $null=[IO.Directory]::CreateDirectory($fixtureVersion)
    foreach($member in Get-ChildItem -LiteralPath $sourceVersion){
        if($member.Name-ceq'validation-evidence'){continue}
        Copy-Item -LiteralPath $member.FullName -Destination (Join-Path $fixtureVersion $member.Name) -Recurse
    }
    Check (-not(Test-Path -LiteralPath (Join-Path $fixtureVersion 'validation-evidence'))) 'private-mechanism-fixture-does-not-inherit-source-qualification-attachments'
    foreach($relative in @('framework/maintenance-overlay','skills/ai-workspace-router-v2')){
        $destination=Join-Path $workspace $relative;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $destination));Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination -Recurse
    }
    foreach($name in @('README.md','AGENTS.md')){CopyFile (Join-Path $sourceRoot ('framework/user-package/'+$name)) (Join-Path $workspace $name)}
    if($ProviderSnapshotOnly){foreach($name in @('VERSION.json','LOAD_MANIFEST.json')){$path=Join-Path $workspace ('framework/versions/2.0.0/'+$name);$v=Get-Content $path -Raw|ConvertFrom-Json;$v.lifecycle='STABLE';if($name-ceq'VERSION.json'){$v.consumable=$true;$v.projectPinEligible=$true};SaveJson $path $v};$path=Join-Path $workspace 'framework/versions/2.0.0/RELEASE_MANIFEST.json';$v=Get-Content $path -Raw|ConvertFrom-Json;$v.lifecycle='STABLE';SaveJson $path $v}
    SealFixture (Join-Path $workspace 'framework/versions/2.0.0');NamedFixture $workspace
    $refreshRuntimes=@(foreach($number in 2..3){
        $next=Join-Path $temp ('runtime-2-refresh-'+$number);Copy-Item -LiteralPath $workspace -Destination $next -Recurse
        if($ProviderSnapshotOnly){foreach($name in @('VERSION.json','LOAD_MANIFEST.json','RELEASE_MANIFEST.json')){CopyFile (Join-Path $sourceRoot ('framework/versions/2.0.0/'+$name)) (Join-Path $next ('framework/versions/2.0.0/'+$name))}}
        foreach($relative in @('framework/versions/2.0.0/project-starter/BOOTSTRAP.md','framework/maintenance-overlay/BOOTSTRAP.md')){
            $path=Join-Path $next $relative;$text=Get-Content -LiteralPath $path -Raw
            SaveText $path ($text.Replace('<!-- FRAMEWORK-MANAGED:END -->',("<!-- isolated refresh fixture {0} -->`n<!-- FRAMEWORK-MANAGED:END -->"-f$number)))
        }
        SealFixture (Join-Path $next 'framework/versions/2.0.0');NamedFixture $next ('2.0.0-snapshot.'+$number);$next
    })
    }
    foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $workspace ('scripts/'+$name+'.psm1')) -Force}
    if($ProviderSnapshotOnly){CurrentProviderCases;return}
    $legacy=Get-AiwDistributionBinding $LegacyRuntimeRoot $LegacyFrameworkVersion -Required
    $allowedLegacyDistributions=if($LegacyFrameworkVersion-ceq'1.16.0'){@('1.16.0-snapshot.12')}else{@('2.0.0-snapshot.3','2.0.0-snapshot.15')};Check ($legacy.distributionId-cin$allowedLegacyDistributions) ('actual-unchanged-'+$legacy.distributionId+'-runtime')
    $legacyContract=Get-FixtureProcessContract $LegacyRuntimeRoot $LegacyFrameworkVersion
    $registeredOrigin=$legacy.distributionId-ceq'2.0.0-snapshot.15'
    if($registeredOrigin-and($NonOwner-or$CorrectionAdoption-or$SourceLocation-cne'RELATIVE')){throw 'REGISTER_SOURCE_FIXTURE_HAS_NO_SEEDED_OPTIONAL_SOURCES_OR_DELEGATED_ROUTE'}
    $upgrade=Join-Path $workspace 'scripts/upgrade-project.ps1'
    $layouts=if($Layout-ceq'ALL'){@('MAINTENANCE','ORDINARY')}else{@($Layout)}
    foreach($case in $layouts){
        if($HistorySeedRoot){
            $seed=Get-Content -LiteralPath (Join-Path $HistorySeedRoot 'history-seed.json') -Raw|ConvertFrom-Json -Depth 100
            $project=[IO.Path]::GetFullPath($seed.projectRoot)
            $temporaryBase=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())+[IO.Path]::DirectorySeparatorChar
            if(-not$project.StartsWith($temporaryBase,[StringComparison]::OrdinalIgnoreCase)-or$seed.runtimeRoot-cne$LegacyRuntimeRoot){throw 'HISTORY_SEED_BOUNDARY'}
            $projectId=$seed.projectId;$owner=$seed.owner;$actor=$owner;$taskRelative=$seed.taskRelative;$sourceRole='FRAMEWORK_MAINTAINER'
            $config=Get-Content -LiteralPath (Join-Path $project '.ai-workspace/project.json') -Raw|ConvertFrom-Json -Depth 100
            $paths=@('.ai-workspace/upgrade-recovery/2.0.0/state.json','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json')
            $standardRelative='.ai-workspace/standards/quality.md';$standardPath=Join-Path $project $standardRelative;$standardBytes=[IO.File]::ReadAllBytes($standardPath)
            $peerEntries=@($seed.peerEntries)
            $script:historyJournalBytes=[IO.File]::ReadAllBytes((Join-Path $project '.ai-workspace/runtime/project-adoption/upgrade/state.json'))
            if((Get-AiwByteIdentity $script:historyJournalBytes)-cne$seed.journalIdentity){throw 'HISTORY_SEED_JOURNAL_DRIFT'}
            $history=Get-Content -LiteralPath (Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0/state.json') -Raw|ConvertFrom-Json -Depth 100
            Check ($history.fromVersion-ceq'1.16.0'-and$history.majorTransition.fromDistributionId-ceq'1.16.0-snapshot.12') 'actual-old-major-history-present'
            $legacyVersion=Join-Path $LegacyRuntimeRoot 'framework/versions/2.0.0'
        }elseif($registeredOrigin){
            # Snapshot.15 declares project6/policy2/corrections3 and a real
            # REGISTER7 origin. Do not manufacture a schema6 completion marker.
            $project=Join-Path $temp ($case.ToLowerInvariant()+'/control');$null=[IO.Directory]::CreateDirectory($project)
            & git init -q $project;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
            $projectId='major-'+$case.ToLowerInvariant();$owner='major-owner';$actor=$owner;$sourceRole='CONTROLLER';$taskRelative='.ai-workspace/tasks/active/MAJOR-001.md'
            $paths=@('.ai-workspace/upgrade-recovery/2.0.0/state.json','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json')
            $initial=Join-Path (Split-Path -Parent $project) 'initial-MAJOR-001.md'
            SaveText $initial ([string]::Join([char]10,@('# MAJOR-001 — Isolated adoption','- Task schema: 2.0.0','- Status: ACTIVE','- Profile: CRITICAL; reason=real source contract and original cross-distribution adoption.','- Owner: major-owner','- Work route: actor=major-owner; role=CONTROLLER; phase=IMPLEMENT','- Phase gate: FALSE',('- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=MAJOR_ADOPTION; expected_paths=['+($paths-join'|')+']; actual_paths=['+($paths-join'|')+']'),'- Writer / reviewer / authorization: isolated fixture only','- Stable candidate: NONE','- Git / push / external: DEFERRED','## Current','- Goal: Complete the chosen isolated runtime adoption and original process.','- Acceptance: Genuine source registration, original checker/DISCOVER/ADMIT, exact target Apply, original FINALIZE and recovery.')))
            SaveText (Join-Path $project 'AGENTS.md') '# User-owned fixture instructions outside the managed region'
            $registration=@{ProjectId=$projectId;DisplayName='Major bridge fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId=$owner;WorkspaceRoot=$LegacyRuntimeRoot;LocalCandidatePilot=$true;InitialTaskPath=$initial;ExpectedInitialTaskIdentity=(Id $initial);InitialTaskRelativePath=$taskRelative;Apply=$true}
            if($case-ceq'MAINTENANCE'){
                $target=Join-Path (Split-Path -Parent $project) 'target';$null=[IO.Directory]::CreateDirectory($target);& git init -q $target;if($LASTEXITCODE-ne0){throw 'FIXTURE_TARGET_GIT_INIT'}
                SaveText (Join-Path $target 'README.md') 'Synthetic source target for the isolated bridge fixture.'
                $registration.ControlPlaneLayout='framework-maintenance-sibling';$registration.FrameworkTargetRepositoryId='fixture-framework';$registration.FrameworkTargetSiblingDirectory='target'
            }
            $registered=Run (Join-Path $LegacyRuntimeRoot 'scripts/register-project.ps1') $registration
            Check (@($registered)[-1].status-ceq'CREATED') ($case+'-actual-source-register')
            $legacyVersion=Join-Path $LegacyRuntimeRoot 'framework/versions/2.0.0'
            $config=Get-Content -LiteralPath (Join-Path $project '.ai-workspace/project.json') -Raw|ConvertFrom-Json -Depth 100
            $origin=Get-Content -LiteralPath (Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0/state.json') -Raw|ConvertFrom-Json -Depth 100
            $registrationJournal=Join-Path $project $origin.origin.transactionRelativePath
            $registeredJournal=Get-Content -LiteralPath $registrationJournal -Raw|ConvertFrom-Json -Depth 100
            $registeredIdentity=Id (Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0/state.json')
            Check ($config.schemaVersion-eq$legacyContract.project-and$origin.schemaVersion-eq7-and$origin.originKind-ceq'REGISTER'-and$registeredJournal.state-ceq'COMPLETE'-and$registeredJournal.transactionComplete-and@($registeredJournal.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'-and$_.newIdentity-ceq$registeredIdentity}).Count-eq1) ($case+'-real-register-origin-and-complete-projection')
            $policy=Get-Content -LiteralPath (Join-Path $project '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json
            $corrections=Get-Content -LiteralPath (Join-Path $project '.ai-workspace/corrections.json') -Raw|ConvertFrom-Json
            Check ($policy.schemaVersion-eq2-and$corrections.schemaVersion-eq3-and@($config.sourceBindings).Count-eq0-and@($config.frameworkCapabilities.PSObject.Properties).Count-eq0) ($case+'-declared-source-formats-with-no-optional-sources')
            # Optional source preservation is exercised by the configured 1.16/3
            # fixtures below. This registration has no standard or knowledge.
            $standardRelative='NOT_APPLICABLE';$standardPath=$null;$standardBytes=$null;$groupFixture=$null
            $peerEntries=@()
            foreach($peer in @('b','c')){
                $peerRoot=Join-Path $temp ($case.ToLowerInvariant()+'/'+$peer)
                foreach($relative in @('AGENTS.md','.ai-workspace/project.json')){
                    $peerPath=Join-Path $peerRoot $relative;CopyFile (Join-Path $project $relative) $peerPath;$peerEntries+=@(@{path=$peerPath;identity=(Id $peerPath)})
                }
            }
        }else{
        $project=Join-Path $temp ($case.ToLowerInvariant()+'/control');$null=[IO.Directory]::CreateDirectory($project)
        # The actual old runtime requires Git. Target-version no-Git behavior is
        # covered by non-git-adoption-tests; these fixtures do not rewrite it.
        & git init -q $project;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
        $projectId='major-'+$case.ToLowerInvariant();$owner='major-owner';$actor=if($NonOwner){'major-executor'}else{$owner};$taskRelative='.ai-workspace/tasks/active/MAJOR-001.md'
        $sourceRole=if($case-ceq'MAINTENANCE'){'FRAMEWORK_MAINTAINER'}elseif($NonOwner){'EXECUTOR'}elseif($LegacyFrameworkVersion-ceq'2.0.0'){'TASK_OWNER'}else{'DOMAIN_OWNER'}
        $paths=@(('.ai-workspace/upgrade-recovery/'+$LegacyFrameworkVersion+'/state.json'),'.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','.ai-workspace/upgrade-recovery/2.0.0/state.json',$taskRelative)
        $paths=@($paths|Select-Object -Unique)
        if($LegacyFrameworkVersion-ceq'2.0.0'){$paths=@($paths|Where-Object{$_-cne$taskRelative})}
        $oldConfigSchema=if($LegacyFrameworkVersion-ceq'2.0.0'){5}else{4}
        $config=[ordered]@{schemaVersion=$oldConfigSchema;id=$projectId;displayName='Major bridge fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion=$LegacyFrameworkVersion;frameworkToolBackend='powershell7';routineExcludedPaths=@('private');frameworkCapabilities=[pscustomobject]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}
        $standardRelative='.ai-workspace/standards/quality.md';$standardPath=Join-Path $project $standardRelative
        SaveText $standardPath 'Preserve the project owner and verify the declared result before acceptance.'
        $standardBytes=[IO.File]::ReadAllBytes($standardPath)
        $templateRoot=Join-Path $LegacyRuntimeRoot ('framework/versions/'+$LegacyFrameworkVersion+'/project-starter')
        if($case-ceq'MAINTENANCE'){
            $target=Join-Path (Split-Path -Parent $project) 'target';$null=[IO.Directory]::CreateDirectory($target);& git init -q $target;if($LASTEXITCODE-ne0){throw 'FIXTURE_TARGET_GIT_INIT'}
            SaveText (Join-Path $target 'README.md') 'Synthetic source target for the isolated bridge fixture.'
            $config.controlPlaneLayout='framework-maintenance-sibling';$config.frameworkTarget=[ordered]@{repositoryId='fixture-framework';siblingDirectory='target';routineExcludedPaths=@('private')}
            $templateRoot=Join-Path $LegacyRuntimeRoot 'framework/maintenance-overlay'
        }else{
            $knowledgeRelative='.ai-workspace/knowledge/example.md';SaveText (Join-Path $project $knowledgeRelative) 'Fixture project-derived knowledge with a real source dependency.'
            if($LegacyFrameworkVersion-ceq'2.0.0'){
                # snapshot.3 already uses source-qualified libraries. Preserve
                # this current index; it is not a legacy index conversion write.
                $config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@([pscustomobject]@{id='fixture';root=[pscustomobject]@{kind='PROJECT';locator='.'};indexLocator='.ai-workspace/knowledge/index.json';selectionHints=@('fixture');updatePolicy='FOLLOW'})}}
                $entry=[ordered]@{id='example';kind='PROJECT_DERIVED';state='CURRENT';title='Fixture reference';summary='Project-derived test reference';tags=@('fixture');locator=$knowledgeRelative;identity=(Id (Join-Path $project $knowledgeRelative));verifiedAt='2026-09-27T00:00:00Z';projectId=$projectId;authorityDependencies=@([ordered]@{locator=$standardRelative;identity=(Id $standardPath)});invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE');tokenEstimate=32}
                SaveJson (Join-Path $project '.ai-workspace/knowledge/index.json') @{schemaVersion=3;libraryId='fixture';entries=@($entry)}
            }else{
                $config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;indexLocator='.ai-workspace/knowledge/index.json'}}
                $entry=[ordered]@{id='example';state='CURRENT';title='Fixture reference';summary='Project-derived test reference';locator=$knowledgeRelative;identity=(Id (Join-Path $project $knowledgeRelative));verifiedAt='2026-09-27T00:00:00Z';authorityLocator=$standardRelative;authorityIdentity=(Id $standardPath);invalidatesOn=@('LOCATOR_IDENTITY_CHANGE','AUTHORITY_IDENTITY_CHANGE');tokenEstimate=32}
                SaveJson (Join-Path $project '.ai-workspace/knowledge/index.json') @{schemaVersion=1;projectId=$projectId;entries=@($entry)}
                $paths+=@('.ai-workspace/knowledge/index.json')
            }
        }
        SaveJson (Join-Path $project '.ai-workspace/project.json') $config
        SaveJson (Join-Path $project '.ai-workspace/controller.json') @{schemaVersion=1;projectId=$projectId;controllerId=$owner;controllerEpoch=1;state='CURRENT'}
        $rule=[ordered]@{ruleId='PRESERVE_TEST_STANDARD';selectors=[ordered]@{profiles=@('CRITICAL');roles=@($sourceRole);phases=@('IMPLEMENT');actionKinds=@('CONTROL_WRITE');resultKinds=@('IMPLEMENTATION_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@('STANDARD_EVIDENCE_BOUND');resultRequirements=@('STANDARD_RULE_PRESERVED');source=[ordered]@{rootSourceId='QUALITY';documents=@([ordered]@{sourceId='QUALITY';locator=$standardRelative;identity=(Id $standardPath);mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}}
        if($SourceLocation-cne'RELATIVE'){
            if($SourceLocation-ceq'ABSOLUTE_OUTSIDE'){
                $standardPath=Join-Path $temp ($case.ToLowerInvariant()+'/shared/quality.md')
                $null=[IO.Directory]::CreateDirectory((Split-Path -Parent $standardPath));[IO.File]::WriteAllBytes($standardPath,$standardBytes)
            }
            $rule.source.documents[0].locator=$standardPath;$rule.source.documents[0].locatorKind='ABSOLUTE_FILE'
        }
        $rule.requirementReason='Preserve a project-owned standard across the explicit version pair.';$rule.decisionLocator=$taskRelative
        $rules=@($rule)
        if($case-ceq'MAINTENANCE'){
            $overlayPolicy=(Get-Content (Join-Path $templateRoot 'process-policy.json') -Raw).Replace('{{PROCESS_CONTRACT_VERSION_JSON}}',($LegacyFrameworkVersion|ConvertTo-Json -Compress)).Replace('{{PROJECT_ID_JSON}}',('"'+$projectId+'"')).Replace('{{SELECTED_RULE_PACK_BYTES}}','98304')|ConvertFrom-Json
            $rules+=@($overlayPolicy.rules)
        }
        SaveJson (Join-Path $project '.ai-workspace/process-policy.json') @{schemaVersion=1;contractVersion=$LegacyFrameworkVersion;projectId=$projectId;selectedRulePackBytes=98304;rules=$rules}
        SaveJson (Join-Path $project '.ai-workspace/corrections.json') @{schemaVersion=2;contractVersion=$LegacyFrameworkVersion;projectId=$projectId;corrections=@()}
        $bootstrap=(Get-Content (Join-Path $templateRoot 'BOOTSTRAP.md') -Raw).Replace('{{DISPLAY_NAME}}','Major bridge fixture').Replace('{{PROJECT_ID}}',$projectId).Replace('{{FRAMEWORK_VERSION}}',$LegacyFrameworkVersion)
        SaveText (Join-Path $project '.ai-workspace/BOOTSTRAP.md') $bootstrap
        CopyFile (Join-Path $templateRoot 'AGENTS.md') (Join-Path $project 'AGENTS.md')
        $groupFixture=$null
        if($CorrectionAdoption){$groupFixture=Seed-AdoptionCorrections $project $workspace $LegacyFrameworkVersion;$paths=@(@($paths)+@($groupFixture.scope)|Select-Object -Unique)}
        $peerEntries=@()
        foreach($peer in @('b','c')){
            $peerRoot=Join-Path $temp ($case.ToLowerInvariant()+'/'+$peer)
            CopyFile (Join-Path $project 'AGENTS.md') (Join-Path $peerRoot 'AGENTS.md')
            CopyFile (Join-Path $project '.ai-workspace/project.json') (Join-Path $peerRoot '.ai-workspace/project.json')
            foreach($relative in @('AGENTS.md','.ai-workspace/project.json')){$peerPath=Join-Path $peerRoot $relative;$peerEntries+=@(@{path=$peerPath;identity=(Id $peerPath)})}
        }
        SaveText (Join-Path $project '.gitignore') '/.ai-workspace/runtime/'
        SaveText (Join-Path $project $taskRelative) ("# MAJOR-001 — Isolated adoption`n`n- Task schema: $LegacyFrameworkVersion`n- Profile: CRITICAL; reason=major adoption fixture`n- Owner: $owner`n- Work route: actor=$actor; role=$sourceRole; phase=IMPLEMENT`n- Phase gate: FALSE`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; expected_paths=["+($paths-join'|')+"]; actual_paths=[]`n- Writer / reviewer / authorization: none`n- Stable candidate: NONE`n- Git / push / external: DEFERRED`n")
        $legacyVersion=Join-Path $LegacyRuntimeRoot ('framework/versions/'+$LegacyFrameworkVersion)
        Import-Module (Join-Path $legacyVersion 'scripts/ProcessRequirementComposition.psm1') -Force
        $managed=(Get-AiwProjectCustomRegion (Join-Path $project '.ai-workspace/BOOTSTRAP.md')).ManagedIdentity
        $records=@();$objects=@()
        foreach($relative in @('.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','AGENTS.md',$taskRelative)){
            $identity=Id (Join-Path $project $relative);$objects+=@([ordered]@{relative=$relative;oldIdentity='MISSING';newIdentity=$identity});$record=[ordered]@{relative=$relative;identity=$identity}
            if($relative-ceq'.ai-workspace/BOOTSTRAP.md'){$record.managedIdentity=$managed};$records+=@($record)
        }
        $manifest=Get-Content (Join-Path $legacyVersion 'RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json
        SaveJson (Join-Path $project ('.ai-workspace/upgrade-recovery/'+$LegacyFrameworkVersion+'/state.json')) ([ordered]@{schemaVersion=6;transactionComplete=$true;projectId=$projectId;fromVersion=$LegacyFrameworkVersion;toVersion=$LegacyFrameworkVersion;targetReleaseCanonical=$manifest.canonical;targetReleaseManifestIdentity=(Id (Join-Path $legacyVersion 'RELEASE_MANIFEST.json'));actor=$actor;taskId='MAJOR-001';taskOwner=$owner;taskRelative=$taskRelative;authorizationIdentity=('1|'+('A'*64));objects=$objects;projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=$records;projectFormat=('repo-local/project-config-'+$oldConfigSchema);projectCapabilities=@($config.frameworkCapabilities.PSObject.Properties|ForEach-Object{$_.Name});rootToolRevision=('A'*64);rootToolDependencies=@();distributionBinding=$legacy})
        if($case-ceq'ORDINARY'-and$LegacyFrameworkVersion-ceq'2.0.0'){
            $oldKnowledge=Run (Join-Path $legacyVersion 'scripts/check-knowledge-entry.ps1') @{ProjectRoot=$project;ExpectedProjectConfigIdentity=(Id (Join-Path $project '.ai-workspace/project.json'));Operation='QUERY';EntryId=@('fixture:example');AsJson=$true}
            Check ($oldKnowledge.status-ceq'KNOWLEDGE_QUERY_RESULT'-and$oldKnowledge.entries.Count-eq1-and$oldKnowledge.entries[0].status-ceq'CURRENT') 'ordinary-project5-unchanged-old-knowledge-query'
        }
        }
        # Prime a real current human grant after genuine REGISTER where needed.
        # The old register projector owns its template; mutating that fixed
        # template or inventing its journal would not establish this scenario.
        $sourceAgents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
        $liveGrant=[regex]::Match($sourceAgents,'(?m)^在本项目内[^\r\n]*').Value
        if(-not$liveGrant){throw 'IR01_REAL_SOURCE_GRANT_REQUIRED'}
        $ir01Grant=if($B1Daily){$liveGrant}else{$liveGrant+' 恢复时另读 .ai-workspace/BOOTSTRAP.md；仅限只读，禁止发布。'}
        $ir01Agents=$sourceAgents.Replace($liveGrant,$ir01Grant)
        if(-not$B1Daily){Prime-FixtureAgents $project $LegacyRuntimeRoot $LegacyFrameworkVersion $case $taskRelative $actor $ir01Agents 'restricted-source'}
        $ir01Agents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
        $hasStandard=-not$registeredOrigin
        $hasKnowledge=$case-ceq'ORDINARY'-and-not$registeredOrigin
        $runtime=Join-Path $project '.ai-workspace/runtime/MAJOR-001/major-owner'
        if($HistorySeedRoot){$runtime=Join-Path $runtime 'format-attempt'}
        $package=[ordered]@{schemaVersion=$(if($case-ceq'MAINTENANCE'){2}else{1});frameworkVersion=$LegacyFrameworkVersion;taskId='MAJOR-001';profile='CRITICAL';lifecycle='ACTIVE';owner=$owner;issuer=$owner;issuerRole='PROJECT_CONTROLLER';issuerControllerId=$owner;issuerControllerEpoch=1;controllerControlIdentity=(Id (Join-Path $project '.ai-workspace/controller.json'));grantee=$actor;bundle='MAJOR_ADOPTION';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='ISOLATED_TEST_USER_MAJOR_DECISION';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id (Join-Path $project $taskRelative));actions=@('CONTROL_WRITE');exactPaths=$paths;objectIdentities=@($paths|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $project $_))}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Id (Join-Path $project '.ai-workspace/project.json'))}
        if($case-ceq'MAINTENANCE'){$package.repositoryId='CONTROL';$package.invalidatesOn+=@('REPOSITORY_CHANGE')}
        $packagePath=Join-Path $runtime 'old-package.json';SaveJson $packagePath $package
        $scopeArgs=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ControllerId=$owner;WorkspaceRoot=$workspace;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=$package.taskIdentity;ActorRouteActor=$actor}
        if($CorrectionAdoption){$scopeArgs.AdoptionCorrectionsPlanPath=$groupFixture.path;$scopeArgs.ExpectedAdoptionCorrectionsPlanIdentity=$groupFixture.identity;Check (-not(Test-Path (Join-Path $workspace 'framework/versions/1.16.0'))) 'adoption-group-target-package-has-only-version2'}
        $scope=Run $upgrade $scopeArgs
        $scopeText=$scope-join"`n"
        Check ($scopeText.Contains('UPGRADE_SCOPE_ONLY|')-and$scopeText.Contains('OLD_DISCOVER_REQUIRED|')-and-not$scopeText.Contains('UPGRADE_POSTIMAGE|')) ($case+'-scope-navigation-before-old-discover')
        Check (@($paths|Where-Object{(Id (Join-Path $project $_))-cne@($package.objectIdentities|Where-Object path -CEQ $_)[0].identity}).Count-eq0) ($case+'-scope-navigation-zero-projection-writes')
        $input=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$project;frameworkRoot=$LegacyRuntimeRoot;taskPath=(Join-Path $project $taskRelative);expectedProjectConfigIdentity=$package.projectConfigIdentity;expectedCorrectionsIdentity=(Id (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=$package.taskIdentity;observedActor=$actor;capabilities=@($config.frameworkCapabilities.PSObject.Properties|ForEach-Object{$_.Name});exactPaths=$paths;forbiddenPaths=@('private');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Id $packagePath);userDecision=$package.userConfirmation;recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Apply the approved project migration while preserving its current rules and task owner.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('project adoption','current task','project control');pathHints=@();capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
        Set-FixtureDiscoverContract $input $LegacyRuntimeRoot $LegacyFrameworkVersion
        if($registeredOrigin){$input.protectedPaths=@('private')}
        $checkerArgs=@{PackagePath=$packagePath;ObservedActor=$actor;ObservedTaskId='MAJOR-001';ObservedOwner=$owner;ObservedAction=@('CONTROL_WRITE');ObservedPath=$paths;ObservedIdentity=@($package.objectIdentities|ForEach-Object{$_.path+'='+$_.identity});TaskPath=$taskRelative;ExpectedTaskIdentity=$package.taskIdentity;ExpectedProjectConfigIdentity=$package.projectConfigIdentity}
        if($case-ceq'MAINTENANCE'){$checker=Join-Path $LegacyRuntimeRoot 'scripts/check-framework-maintenance-authorization.ps1';$checkerArgs.ControlRepositoryPath=$project;$checkerArgs.ObservedRepositoryId='CONTROL'}else{$checker=Join-Path $legacyVersion 'scripts/check-authorization.ps1';$checkerArgs.ProjectConfigPath='.ai-workspace/project.json';$checkerArgs.ControllerControlPath='.ai-workspace/controller.json'}
        $checked=Run $checker $checkerArgs $project
        Check (($checked-join[char]10).StartsWith('PASS|')) ($case+'-actual-old-independent-checker')
        $inputPath=Join-Path $runtime 'discover.json';SaveJson $inputPath $input
        $resolver=if($case-ceq'MAINTENANCE'){Join-Path $LegacyRuntimeRoot 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $legacyVersion 'scripts/resolve-process-requirements.ps1'}
        $discovered=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($discovered.status-ceq'PASS') ($case+'-actual-old-discover')
        $receiptPath=Join-Path $runtime 'receipt.json';SaveJson $receiptPath $discovered.compactReceipt
        $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
        Set-FixtureBoundaryContract $boundary $LegacyRuntimeRoot $LegacyFrameworkVersion
        $boundaryPath=Join-Path $runtime 'admit-input.json';SaveJson $boundaryPath $boundary
        $base=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ControllerId=$owner;WorkspaceRoot=$workspace;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=$package.taskIdentity;ActorRouteActor=$actor;CurrentProcessInputPath=$boundaryPath;ExpectedCurrentProcessInputIdentity=(Id $boundaryPath)}
        if($CorrectionAdoption){$base.AdoptionCorrectionsPlanPath=$groupFixture.path;$base.ExpectedAdoptionCorrectionsPlanIdentity=$groupFixture.identity}
        $args=$base.Clone();$args.AdoptionProcessMode='PREPARE';$prepared=Run $upgrade $args
        $targetAgents=@($prepared.projection.objects|Where-Object{$_.path-ceq'AGENTS.md'})
        Check ($targetAgents.Count-eq1-and$targetAgents[0].newExists) ($case+'-ir01-prepared-agents-member')
        $targetText=$utf8.GetString([Convert]::FromBase64String($targetAgents[0].newBase64))
        Check ($targetText.Contains($ir01Grant)-and-not(Get-AiwAgentsTemplateBlock $targetText).Contains($ir01Grant)) ($case+'-ir01-public-prepare-preserves-complete-bootstrap-reference-restriction')
        if(-not$B1Daily){Ir01-PrepareConflict $project $case $LegacyRuntimeRoot $LegacyFrameworkVersion $taskRelative $actor $upgrade $base $input $package $paths $runtime $ir01Agents}
        if($SourceContractOnly){continue}
        if($LegacyFrameworkVersion-ceq'2.0.0'){
            Check (@($prepared.projection.objects|Where-Object{$_.path-ceq$taskRelative}).Count-eq0) ($case+'-same-version-task-excluded-from-write-projection')
            Check ((Id (Join-Path $project $taskRelative))-ceq$package.taskIdentity) ($case+'-same-version-prepare-preserves-task-bytes')
        }
        $expectedTarget=if($SeedTargetRoot){'2.0.0-snapshot.3'}else{'2.0.0-snapshot.1'}
        Check ($prepared.status-ceq'PREPARED'-and $prepared.previousDistribution.distributionId-ceq$legacy.distributionId-and$prepared.targetDistribution.distributionId-ceq$expectedTarget) ($case+'-target-projection-prepared')
        if(-not$FixedRuntimeOnly){
        $repeated=Run $upgrade $args
        SaveJson (Join-Path $runtime 'repeated-preparation.json') $repeated
        Check (($repeated|ConvertTo-Json -Depth 100 -Compress)-ceq($prepared|ConvertTo-Json -Depth 100 -Compress)) ($case+'-repeated-public-prepare-preserves-complete-source-snapshot')
        }
        Assert-FixtureTargetBodies $prepared $case
        $preparationPath=Join-Path $runtime 'preparation.json';SaveJson $preparationPath $prepared
        $boundary.preparationReceipts=@(@($boundary.preparationReceipts)+@($prepared.selectedRuleBlocks.preparationRequirements)|Sort-Object -Unique)+@('ADOPTION_TARGET_RULES_LOADED|'+(Id $preparationPath))
        if($null-ne$prepared.PSObject.Properties['selectorSemanticJudgmentRequired']-and$prepared.selectorSemanticJudgmentRequired){
            # The synthetic Maintenance rule preserves its hard role/phase
            # boundary and becomes conservative for unclassified content. This
            # fixture explicitly accepts that reported target selection change.
            Check (@($prepared.selectorDifferences|Where-Object{$_.requirementId-cne('project:'+ $projectId+':FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY')-or$_.classification-cne'UNCLASSIFIED_CONSERVATIVE'}).Count-eq0) ($case+'-selector-differences-have-explicit-fixture-judgment')
            $boundary.preparationReceipts+=@('ADOPTION_SELECTOR_SEMANTICS_CONFIRMED|'+(Id $preparationPath))
        }
        SaveJson $boundaryPath $boundary;$base.ExpectedCurrentProcessInputIdentity=Id $boundaryPath
        $args=$base.Clone();$args.AdoptionProcessMode='ADMIT_ACTION';$args.AdoptionPreparationPath=$preparationPath;$args.ExpectedAdoptionPreparationIdentity=Id $preparationPath
        $admitted=Run $upgrade $args;Check ($admitted.status-ceq'PASS'-and$admitted.mode-ceq'ADMIT_ACTION') ($case+'-actual-old-admit')
        $admitPath=Join-Path $runtime 'admit-result.json';SaveJson $admitPath $admitted
        $schema3=$package|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $schema3.PSObject.Properties.Remove('repositoryId');$schema3.schemaVersion=3;$schema3.frameworkVersion='2.0.0';$schema3.bundle='ACTOR_BOUND_PROJECT_UPGRADE'
        $schema3.invalidatesOn=@($schema3.invalidatesOn|Where-Object{$_-cne'REPOSITORY_CHANGE'})+@('POST_OBJECT_DRIFT')
        $schema3|Add-Member postObjectIdentities @($prepared.projection.objects|ForEach-Object{
            $postIdentity=if($_.newExists){$_.newIdentity}else{'ABSENT'}
            if($case-ceq'MAINTENANCE'){[ordered]@{identity=$postIdentity;path=$_.path}}
            else{[ordered]@{path=$_.path;identity=$postIdentity}}
        })
        $manifest=Get-Content (Join-Path $workspace 'framework/versions/2.0.0/RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json
        $manifestIdentity=Id (Join-Path $workspace 'framework/versions/2.0.0/RELEASE_MANIFEST.json')
        $snapshot=if($case-ceq'MAINTENANCE'){
            [pscustomobject][ordered]@{manifestIdentity=$manifestIdentity;canonical=$manifest.canonical}
        }else{
            [pscustomobject][ordered]@{canonical=$manifest.canonical;manifestIdentity=$manifestIdentity}
        }
        $schema3|Add-Member targetFrameworkSnapshot $snapshot
        $schema3Path=Join-Path $runtime 'schema3.json';SaveJson $schema3Path $schema3
        if($case-ceq'MAINTENANCE'){
            Check ((Get-Content $schema3Path -Raw).Contains('"targetFrameworkSnapshot":{"manifestIdentity"')) 'maintenance-snapshot-reversed-member-order-fixture'
            Check ((Get-Content $schema3Path -Raw).Contains('"postObjectIdentities":[{"identity"')) 'maintenance-postobject-reversed-member-order-fixture'
        }
        $applyArgs=$base.Clone();$applyArgs.Apply=$true;$applyArgs.AuthorizationPackagePath=$schema3Path;$applyArgs.ExpectedAuthorizationPackageIdentity=Id $schema3Path;$applyArgs.AdmitResultPath=$admitPath;$applyArgs.ExpectedAdmitResultIdentity=Id $admitPath
        if(-not$SeedTargetRoot){
        $missing=$applyArgs.Clone();$missing.Remove('AdmitResultPath');$missing.Remove('ExpectedAdmitResultIdentity');Reject $upgrade $missing 'MAJOR_ADMIT' ($case+'-reject-missing-original-admit')
        if(-not$FixedRuntimeOnly){
        $bad=Clone $schema3;$bad.userConfirmation='UNRELATED_DECISION';$badPath=Join-Path $runtime 'bad-schema3.json';SaveJson $badPath $bad
        $wrong=$applyArgs.Clone();$wrong.AuthorizationPackagePath=$badPath;$wrong.ExpectedAuthorizationPackageIdentity=Id $badPath
        Reject $upgrade $wrong 'MAJOR_PACKAGE_userConfirmation' ($case+'-reject-different-user-decision')
        }
        if($case-ceq'MAINTENANCE'-and-not$FixedRuntimeOnly){
            $badSnapshot=Clone $schema3;$badSnapshot.targetFrameworkSnapshot.manifestIdentity='1|'+('0'*64)
            $badSnapshotPath=Join-Path $runtime 'bad-snapshot-schema3.json';SaveJson $badSnapshotPath $badSnapshot
            $wrongSnapshot=$applyArgs.Clone();$wrongSnapshot.AuthorizationPackagePath=$badSnapshotPath;$wrongSnapshot.ExpectedAuthorizationPackageIdentity=Id $badSnapshotPath
            Reject $upgrade $wrongSnapshot 'MAJOR_PACKAGE_targetFrameworkSnapshot' 'maintenance-reject-changed-snapshot-value'
            $badPost=Clone $schema3;$badPost.postObjectIdentities[0].identity='1|'+('F'*64)
            $badPostPath=Join-Path $runtime 'bad-post-value-schema3.json';SaveJson $badPostPath $badPost
            $wrongPost=$applyArgs.Clone();$wrongPost.AuthorizationPackagePath=$badPostPath;$wrongPost.ExpectedAuthorizationPackageIdentity=Id $badPostPath
            Reject $upgrade $wrongPost 'MAJOR_PACKAGE_postObjectIdentities' 'maintenance-reordered-postobjects-still-reject-real-value-drift'
            $projectionBefore=@($prepared.projection.objects|ForEach-Object{$_.path+'='+(Id (Get-AiwContainedPath $project $_.path))})
            $typeProbeTransactionPath=Join-Path $project '.ai-workspace/runtime/project-adoption/upgrade/state.json'
            $transactionBefore=Id $typeProbeTransactionPath
            foreach($member in @('canonical','manifestIdentity')){
                $badType=Clone $schema3;$badType.targetFrameworkSnapshot[$member]=@($snapshot.$member)
                $badTypePath=Join-Path $runtime ('bad-'+$member+'-type-schema3.json');SaveJson $badTypePath $badType
                $readType=Get-Content $badTypePath -Raw|ConvertFrom-Json -Depth 100 -AsHashtable
                Check ($readType.targetFrameworkSnapshot[$member]-is[Array]) ('maintenance-'+$member+'-array-fixture')
                $wrongType=$applyArgs.Clone();$wrongType.AuthorizationPackagePath=$badTypePath;$wrongType.ExpectedAuthorizationPackageIdentity=Id $badTypePath
                Reject $upgrade $wrongType 'MAJOR_PACKAGE_targetFrameworkSnapshot' ('maintenance-reject-'+$member+'-array-type')
                $projectionAfter=@($prepared.projection.objects|ForEach-Object{$_.path+'='+(Id (Get-AiwContainedPath $project $_.path))})
                Check (([string]::Join([char]10,$projectionBefore))-ceq([string]::Join([char]10,$projectionAfter))-and(Id $typeProbeTransactionPath)-ceq$transactionBefore) ('maintenance-'+$member+'-array-zero-write')
            }
        }
        $beforeWrongAdmit=@($prepared.projection.objects|ForEach-Object{$_.path+'='+(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))})-join[char]10
        $wrongAdmit=$applyArgs.Clone();$wrongAdmit.ExpectedAdmitResultIdentity='1|'+('0'*64)
        Reject $upgrade $wrongAdmit 'MAJOR_ADOPTION_ADMIT_DRIFT' ($case+'-reject-wrong-original-admit-identity')
        Check ((@($prepared.projection.objects|ForEach-Object{$_.path+'='+(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))})-join[char]10)-ceq$beforeWrongAdmit) ($case+'-wrong-original-admit-zero-write')
        if($hasStandard){
        SaveText $standardPath 'Unprojected third-party standard change.'
        Reject $upgrade $applyArgs 'ADOPTION_PROCESS_OLD_SOURCE_DRIFT' ($case+'-reject-unprojected-source-drift')
        Check ([IO.File]::ReadAllText($standardPath).Contains('third-party')) ($case+'-source-drift-not-overwritten')
        [IO.File]::WriteAllBytes($standardPath,$standardBytes)
        }
        }
        if($RecoveryDirectionOnly){
            # Keep the exact executing toolkit independently available before
            # corrupting target payload. Its recorded dependency bytes stay fixed.
            $toolRoot=Join-Path $temp 'fixed-compatible-tools'
            Copy-Item -LiteralPath $workspace -Destination $toolRoot -Recurse
            $toolBinding=Get-AiwDistributionBinding $toolRoot '2.0.0' -Required
            $recoveryTool=Join-Path $toolRoot 'scripts/upgrade-project.ps1'
            Write-Output ('RECOVERY_TOOL|'+$recoveryTool+'|distribution='+$toolBinding.distributionId+'|content='+$toolBinding.contentIdentity)
            $transactionPath=Join-Path $project '.ai-workspace/runtime/project-adoption/upgrade/state.json'
            $stopping=$applyArgs.Clone();$stopping.InterruptBeforeAdoptionJournalWrite=1
            $stopped=Run $upgrade $stopping
            Check (($stopped-join[char]10).Contains('MAJOR_ADOPTION_INTERRUPTED')) 'direction-public-interruption'
            $pendingBytes=[IO.File]::ReadAllBytes($transactionPath)
            $pending=Get-Content -LiteralPath $transactionPath -Raw|ConvertFrom-Json -Depth 100
            $targetEntry=@($pending.projection.objects|Where-Object path -ceq '.ai-workspace/upgrade-recovery/2.0.0/state.json')[0]
            $targetState=$utf8.GetString([Convert]::FromBase64String($targetEntry.newBase64))|ConvertFrom-Json -Depth 100
            $toolRevision=Assert-AiwRootToolRevision $toolRoot $targetState.rootToolRevision @($targetState.rootToolDependencies)
            Write-Output ('RECOVERY_TOOL_REVISION|'+$toolRevision.revision)
            $recover=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=(Id $transactionPath);AuthorizationPackagePath=$schema3Path;ExpectedAuthorizationPackageIdentity=(Id $schema3Path);AdoptionRecoveryDirection='COMPLETE';Apply=$true}
            $guardPaths=@($prepared.projection.objects.path)+@($taskRelative,'.ai-workspace/runtime/project-adoption/upgrade/state.json')
            function DirectionSnapshot {return (@($guardPaths|Sort-Object -Unique|ForEach-Object{$_+'='+(FixtureObjectIdentity (Get-AiwContainedPath $project $_))})-join[char]10)}
            $targetComposer=Join-Path $workspace 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1'
            $composerBytes=[IO.File]::ReadAllBytes($targetComposer)
            SaveText $targetComposer "throw 'DAMAGED_TARGET_MUST_NOT_EXECUTE'"
            $before=DirectionSnapshot
            Reject $recoveryTool $recover 'DISTRIBUTION_CONTENT_DRIFT' 'damaged-target-complete-rejected'
            Check ((DirectionSnapshot)-ceq$before) 'damaged-target-complete-zero-write'
            $recover.AdoptionRecoveryDirection='ROLLBACK'
            Reject (Join-Path $LegacyRuntimeRoot 'scripts/upgrade-project.ps1') $recover 'ADOPTION_TRANSACTION_BINDING' 'old-snapshot3-does-not-understand-format-transaction'
            Check ((DirectionSnapshot)-ceq$before) 'old-incompatible-entry-zero-write'
            $authBytes=[IO.File]::ReadAllBytes($schema3Path);$invalid=Clone $schema3;$invalid.userConfirmation='DRIFTED_ORIGINAL_DECISION';SaveJson $schema3Path $invalid
            Reject $recoveryTool $recover 'ADOPTION_RECOVERY_AUTHORIZATION' 'damaged-target-still-rejects-authorization-drift'
            Check ((DirectionSnapshot)-ceq$before) 'authorization-drift-zero-write'
            [IO.File]::WriteAllBytes($schema3Path,$authBytes)
            $invalid=Clone $pending;$invalid.projection.objects[0].oldBase64=[Convert]::ToBase64String($utf8.GetBytes('damaged prior bytes'));SaveJson $transactionPath $invalid
            $recover.ExpectedAdoptionTransactionIdentity=Id $transactionPath;$badBefore=DirectionSnapshot
            Reject $recoveryTool $recover 'PROJECTION_IDENTITY_INVALID' 'damaged-target-still-rejects-preimage-drift'
            Check ((DirectionSnapshot)-ceq$badBefore) 'preimage-drift-zero-write'
            [IO.File]::WriteAllBytes($transactionPath,$pendingBytes)
            $invalid=Clone $pending;$invalid.metadata.distributionBinding.contentIdentity='A'*64;SaveJson $transactionPath $invalid
            $recover.ExpectedAdoptionTransactionIdentity=Id $transactionPath;$badBefore=DirectionSnapshot
            Reject $recoveryTool $recover 'ADOPTION_PROCESS_RECOVERY_DISTRIBUTION' 'rollback-binds-saved-target-to-original-admit'
            Check ((DirectionSnapshot)-ceq$badBefore) 'target-binding-drift-zero-write'
            [IO.File]::WriteAllBytes($transactionPath,$pendingBytes);$recover.ExpectedAdoptionTransactionIdentity=Id $transactionPath
            $thirdPath=Join-Path $project 'AGENTS.md';$thirdBytes=[IO.File]::ReadAllBytes($thirdPath);SaveText $thirdPath 'Unrelated third-party object.';$badBefore=DirectionSnapshot
            Reject $recoveryTool $recover 'ADOPTION_RECOVERY_THIRD_PARTY_OBJECT' 'damaged-target-still-rejects-third-party-object'
            Check ((DirectionSnapshot)-ceq$badBefore) 'third-party-object-not-overwritten'
            [IO.File]::WriteAllBytes($thirdPath,$thirdBytes)
            $toolDependency=Join-Path $toolRoot 'scripts/MaintenanceOverlay.psm1';$toolBytes=[IO.File]::ReadAllBytes($toolDependency);[IO.File]::AppendAllText($toolDependency,[char]10,$utf8)
            Reject $recoveryTool $recover 'ROOT_TOOL_REVISION_DRIFT' 'rollback-rejects-changed-executing-tool'
            Check ((DirectionSnapshot)-ceq$before) 'tool-drift-zero-project-write'
            [IO.File]::WriteAllBytes($toolDependency,$toolBytes)
            $done=Run $recoveryTool $recover
            Check ($done.status-ceq'ROLLED_BACK') 'damaged-target-public-rollback-complete'
            Check (@($prepared.projection.objects|Where-Object{(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))-cne$_.oldIdentity}).Count-eq0-and(Id $transactionPath)-ceq$seed.journalIdentity-and(Id (Join-Path $project $taskRelative))-ceq$package.taskIdentity) 'damaged-target-rollback-restores-all-original-proofs'
            $oldRead=Run $resolver @{InputPath=$inputPath;AsJson=$true}
            Check ($oldRead.status-ceq'PASS') 'damaged-target-rollback-unchanged-old-resolver-pass'
            Check ([IO.File]::ReadAllText($targetComposer).Contains('DAMAGED_TARGET_MUST_NOT_EXECUTE')) 'rollback-does-not-repair-or-execute-damaged-target'
            [IO.File]::WriteAllBytes($targetComposer,$composerBytes)
            $stopped=Run $upgrade $stopping;$recover.ExpectedAdoptionTransactionIdentity=Id $transactionPath;$recover.AdoptionRecoveryDirection='COMPLETE'
            $done=Run $recoveryTool $recover
            Check ($done.status-ceq'COMPLETE') 'healthy-target-compatible-tool-completes'
            Check (@($prepared.projection.objects|Where-Object{(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))-cne$_.newIdentity}).Count-eq0) 'healthy-completion-exact-postimages'
            $final=Clone $boundary;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@(@($discovered.compactReceipt.selectedObligations.resultRequirements)+@($prepared.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($prepared.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.newExists){$_.newIdentity}else{'ABSENT'})})
            $finalPath=Join-Path $runtime 'direction-final-input.json';SaveJson $finalPath $final
            $finalArgs=$base.Clone();$finalArgs.CurrentProcessInputPath=$finalPath;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath;$finalArgs.AdoptionProcessMode='FINALIZE_OUTPUT';$finalArgs.AdmitResultPath=$admitPath;$finalArgs.ExpectedAdmitResultIdentity=Id $admitPath;$finalArgs.AuthorizationPackagePath=$schema3Path;$finalArgs.ExpectedAuthorizationPackageIdentity=Id $schema3Path;$finalArgs.ExpectedAdoptionTransactionIdentity=Id $transactionPath
            $closed=Run $recoveryTool $finalArgs
            Check ($closed.status-ceq'PASS') 'compatible-tool-original-finalize'
            Check ((Get-AiwDistributionBinding $toolRoot '2.0.0' -Required).contentIdentity-ceq$toolBinding.contentIdentity) 'compatible-tool-copy-remains-exact'
            continue
        }
        $applied=Run $upgrade $applyArgs;Check (($applied-join"`n").Contains('MAJOR_ADOPTION_COMPLETE')) ($case+'-schema3-applied')
        if($LegacyFrameworkVersion-ceq'2.0.0'){Check ((Id (Join-Path $project $taskRelative))-ceq$package.taskIdentity) ($case+'-same-version-apply-preserves-task-bytes')}
        $transactionPath=Join-Path $project '.ai-workspace/runtime/project-adoption/upgrade/state.json'
        $final=Clone $boundary;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@(@($discovered.compactReceipt.selectedObligations.resultRequirements)+@($prepared.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($prepared.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.newExists){$_.newIdentity}else{'ABSENT'})})
        $finalPath=Join-Path $runtime 'final-input.json';SaveJson $finalPath $final
        $finalArgs=$base.Clone();$finalArgs.CurrentProcessInputPath=$finalPath;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath;$finalArgs.AdoptionProcessMode='FINALIZE_OUTPUT';$finalArgs.AdmitResultPath=$admitPath;$finalArgs.ExpectedAdmitResultIdentity=Id $admitPath;$finalArgs.AuthorizationPackagePath=$schema3Path;$finalArgs.ExpectedAuthorizationPackageIdentity=Id $schema3Path;$finalArgs.ExpectedAdoptionTransactionIdentity=Id $transactionPath
        # Final delivery is checked against the original admission's consumer.
        $deliveryFinal=Clone $final
        $deliveryFinal|Add-Member deliveryContext ([pscustomobject]@{channel=$(if($NonOwner){'TASK_MESSAGE'}else{'NATIVE_RESPONSE'});stage='PREPARE';expectedRecipient=$(if($NonOwner){$owner}else{'USER'});observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'})
        SaveJson $finalPath $deliveryFinal;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath
        if($NonOwner){
            if($BaselineTransactionModule){
                $counterexample=Run $upgrade $finalArgs
                Check ($counterexample.status-ceq'PASS'-and-not$counterexample.delivery.delivered) 'baseline-counterexample-major-finalizes-undelivered-cross-task-prepare'
                continue
            }
            Reject $upgrade $finalArgs 'ADOPTION_PROCESS_DELIVERY_NOT_CONFIRMED' ($case+'-major-cross-task-prepare-cannot-close')
            $deliveryFinal.deliveryContext.stage='OBSERVE';$deliveryFinal.deliveryContext.observedRecipient=$owner;$deliveryFinal.deliveryContext.outcome='SUCCESS';$deliveryFinal.deliveryContext.evidence='self-reported-success'
            SaveJson $finalPath $deliveryFinal;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath
            Reject $upgrade $finalArgs 'DELIVERY_HOST_REFERENCE_REQUIRED' ($case+'-major-self-reported-success-cannot-close')
            $hostPath=Join-Path $runtime 'major-mock-host.json'
            foreach($badResult in @(
                @{name='wrong-thread';result=@{isError=$false;content=@(@{type='text';text='{"threadId":"wrong-owner"}'})};reason='DELIVERY_HOST_RESULT_MISMATCH'},
                @{name='failed';result=@{isError=$true;content=@(@{type='text';text=('{"threadId":"'+$owner+'"}')})};reason='DELIVERY_HOST_RESULT_MISMATCH'},
                @{name='unknown';result=@{content=@(@{type='text';text='{"status":"unknown"}'})};reason='DELIVERY_HOST_RESULT_MISMATCH'}
            )){
                SaveJson $hostPath $badResult.result;$deliveryFinal.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
                SaveJson $finalPath $deliveryFinal;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath
                Reject $upgrade $finalArgs $badResult.reason ($case+'-major-'+$badResult.name+'-cannot-close')
            }
            # This host result is synthetic and confined to this protocol fixture.
            SaveJson $hostPath @{isError=$false;content=@(@{type='text';text=('{"threadId":"'+$owner+'"}')})}
            $deliveryFinal.deliveryContext.evidence=$hostPath+'#'+(Id $hostPath)
        }elseif(-not$SeedTargetRoot){
            $wrongDelivery=Clone $deliveryFinal;$wrongDelivery.deliveryContext.channel='TASK_MESSAGE';$wrongDelivery.deliveryContext.expectedRecipient='wrong-owner'
            SaveJson $finalPath $wrongDelivery;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath
            Reject $upgrade $finalArgs 'DELIVERY_CONSUMER_CHANNEL_MISMATCH' ($case+'-major-wrong-consumer-rejected')
        }
        SaveJson $finalPath $deliveryFinal;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath
        if(-not$SeedTargetRoot){
        $alteredAdmit=Clone $admitted;$alteredAdmit|Add-Member delivery ([pscustomobject]@{status='DELIVERED';delivered=$true;retryAllowed=$false;evidenceCeiling='HOST_RESULT_CALLER_BOUND'})
        $alteredAdmitPath=Join-Path $runtime 'altered-original-admit.json';SaveJson $alteredAdmitPath $alteredAdmit
        $alteredArgs=$finalArgs.Clone();$alteredArgs.AdmitResultPath=$alteredAdmitPath;$alteredArgs.ExpectedAdmitResultIdentity=Id $alteredAdmitPath
        Reject $upgrade $alteredArgs 'ADOPTION_PROCESS_ADMIT_DELIVERY_RESULT' ($case+'-major-rejects-altered-original-admission-observation')
        }
        $publicAdapter = Join-Path $workspace 'scripts/resolve-framework-maintenance-process-requirements.ps1'
        $publicFinalArgs = @{InputPath=$finalPath;AsJson=$true;AdoptionProcessBoundary=$true;AdmitResultPath=$admitPath;ExpectedAdmitResultIdentity=(Id $admitPath);AdoptionAuthorizationPackagePath=$schema3Path;ExpectedAdoptionAuthorizationIdentity=(Id $schema3Path);ExpectedAdoptionTransactionIdentity=(Id $transactionPath)}
        if ($case -ceq 'MAINTENANCE' -and -not $SeedTargetRoot) {
            # Exercise the public adapter against real admitted/applied fixture
            # materials. Its unfixed precheck mistakes this legal config postimage
            # for drift; neither the fixture nor the legacy fixed package is patched.
            Check ((Id (Join-Path $project '.ai-workspace/project.json')) -cne $discovered.compactReceipt.sourceBindings.projectConfigIdentity) 'maintenance-public-finalize-config-really-changed'
            function PublicFinalizeSnapshot {
                $entries=@($prepared.projection.objects|ForEach-Object{$_.path+'='+(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))})
                $entries+=@($transactionPath,$inputPath,$receiptPath,$boundaryPath,$admitPath,$schema3Path,$finalPath|ForEach-Object{$_+'='+(Id $_)})
                return ($entries-join"`n")
            }
            $beforePublic=PublicFinalizeSnapshot
            Reject $publicAdapter @{InputPath=$inputPath;AsJson=$true} 'PROJECT_CONFIG_DRIFT' 'maintenance-ordinary-discover-keeps-old-config-binding'
            Reject $publicAdapter @{InputPath=$boundaryPath;AsJson=$true} 'PROJECT_CONFIG_DRIFT' 'maintenance-ordinary-admit-keeps-old-config-binding'
            Reject $publicAdapter @{InputPath=$finalPath;AsJson=$true} 'PROJECT_CONFIG_DRIFT' 'maintenance-finalize-without-original-proof-rejects-config-drift'
            Reject $publicAdapter @{InputPath=$finalPath;AsJson=$true;AdoptionProcessBoundary=$true} 'PROJECT_CONFIG_DRIFT' 'maintenance-adoption-flag-alone-cannot-waive-config-drift'
            $wrong=$publicFinalArgs.Clone();$wrong.ExpectedAdmitResultIdentity='1|'+('0'*64)
            Reject $publicAdapter $wrong 'ADOPTION_PROCESS_ADMIT_RESULT_DRIFT' 'maintenance-public-finalize-rejects-wrong-original-admit-identity'
            $invalidAdmit=Clone $admitted;$invalidAdmit.status='FAIL'
            $invalidAdmitPath=Join-Path $runtime 'public-invalid-admit.json';SaveJson $invalidAdmitPath $invalidAdmit
            $wrong=$publicFinalArgs.Clone();$wrong.AdmitResultPath=$invalidAdmitPath;$wrong.ExpectedAdmitResultIdentity=Id $invalidAdmitPath
            Reject $publicAdapter $wrong 'ADOPTION_PROCESS_ORIGINAL_ADMISSION' 'maintenance-public-finalize-rejects-wrong-original-admission'
            $wrong=$publicFinalArgs.Clone();$wrong.ExpectedAdoptionTransactionIdentity='1|'+('0'*64)
            Reject $publicAdapter $wrong 'ADOPTION_PROCESS_EVIDENCE_DRIFT|TRANSACTION' 'maintenance-public-finalize-rejects-wrong-transaction'
            $invalidPackage=Clone $schema3;$invalidPackage.userConfirmation='UNRELATED_DECISION'
            $invalidPackagePath=Join-Path $runtime 'public-invalid-schema3.json';SaveJson $invalidPackagePath $invalidPackage
            $wrong=$publicFinalArgs.Clone();$wrong.AdoptionAuthorizationPackagePath=$invalidPackagePath;$wrong.ExpectedAdoptionAuthorizationIdentity=Id $invalidPackagePath
            Reject $publicAdapter $wrong 'ADOPTION_RECOVERY_AUTHORIZATION' 'maintenance-public-finalize-rejects-wrong-original-package'
            Check ((PublicFinalizeSnapshot)-ceq$beforePublic) 'maintenance-public-original-evidence-rejections-zero-write'
            $configPath=Join-Path $project '.ai-workspace/project.json';$configBytes=[IO.File]::ReadAllBytes($configPath)
            $thirdConfig=Get-Content -Raw -LiteralPath $configPath|ConvertFrom-Json;$thirdConfig.displayName='Third party valid config drift';SaveJson $configPath $thirdConfig
            $thirdBefore=PublicFinalizeSnapshot
            Reject $publicAdapter $publicFinalArgs 'PROJECT_CONFIG_DRIFT' 'maintenance-public-finalize-rejects-third-party-config'
            Check ((PublicFinalizeSnapshot)-ceq$thirdBefore) 'maintenance-public-third-party-config-zero-write'
            [IO.File]::WriteAllBytes($configPath,$configBytes)
            $agentsPath=Join-Path $project 'AGENTS.md';$agentsBytes=[IO.File]::ReadAllBytes($agentsPath);[IO.File]::AppendAllText($agentsPath,'Third party object drift',$utf8)
            $thirdBefore=PublicFinalizeSnapshot
            Reject $publicAdapter $publicFinalArgs 'ADOPTION_RECOVERY_THIRD_PARTY_OBJECT' 'maintenance-public-finalize-rejects-third-party-object'
            Check ((PublicFinalizeSnapshot)-ceq$thirdBefore) 'maintenance-public-third-party-object-zero-write'
            [IO.File]::WriteAllBytes($agentsPath,$agentsBytes)
            $targetControl=Join-Path (Join-Path (Split-Path -Parent $project) $config.frameworkTarget.siblingDirectory) '.ai-workspace';$null=[IO.Directory]::CreateDirectory($targetControl)
            Reject $publicAdapter $publicFinalArgs 'TARGET_CONTROL_PLANE_FORBIDDEN' 'maintenance-public-finalize-keeps-target-topology-gate'
            Check ((PublicFinalizeSnapshot)-ceq$beforePublic) 'maintenance-public-topology-rejection-zero-write'
            [IO.Directory]::Delete($targetControl)
            $finalized=Run $publicAdapter $publicFinalArgs
            Check ($finalized.status-ceq'PASS'-and$finalized.reason-ceq'ORIGINAL_CROSS_DISTRIBUTION_ADOPTION_FINALIZED') 'maintenance-public-adapter-completes-original-finalize-after-config-change'
            Check (@($prepared.projection.objects|Where-Object{(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))-cne$_.newIdentity}).Count-eq0-and(Id $boundaryPath)-ceq$base.ExpectedCurrentProcessInputIdentity) 'maintenance-public-finalize-preserves-live-projection-and-original-input'
        } else {
            $finalized=Run $upgrade $finalArgs
        }
        Check ($finalized.status-ceq'PASS'-and$finalized.reason-ceq'ORIGINAL_CROSS_DISTRIBUTION_ADOPTION_FINALIZED'-and($SeedTargetRoot-or$finalized.consumer.recipient-ceq$(if($NonOwner){$owner}else{'USER'}))) ($case+'-original-finalize-binds-actual-consumer')
        if($SeedTargetRoot){
            SaveJson (Join-Path $temp 'history-seed.json') @{projectRoot=$project;projectId=$projectId;owner=$owner;taskRelative=$taskRelative;runtimeRoot=$workspace;journalIdentity=(Id $transactionPath);peerEntries=$peerEntries}
            Check ((Get-AiwDistributionBinding $workspace '2.0.0' -Required).contentIdentity-ceq$seedBinding.contentIdentity) 'seed-target-runtime-not-modified'
            Write-Output ('HISTORY_SEED|'+$temp)
            continue
        }
        $finalJournalIdentity=Id $transactionPath
        $finalProof=(Read-AiwProjectJson $transactionPath 'ORIGINAL_FINAL_PROOF').Value.metadata.originalFinalize
        $firstProofBytes=$finalProof|ConvertTo-Json -Depth 100 -Compress
        $finalArgs.ExpectedAdoptionTransactionIdentity=$finalJournalIdentity
        $replayedFinal=Run $upgrade $finalArgs
        $replayedProof=(Read-AiwProjectJson $transactionPath 'REPLAYED_FINAL_PROOF').Value.metadata.originalFinalize
        Check ($replayedFinal.status-ceq'PASS'-and(Id $transactionPath)-ceq$finalJournalIdentity-and($replayedProof|ConvertTo-Json -Depth 100 -Compress)-ceq$firstProofBytes) ($case+'-original-finalize-retry-preserves-first-proof-and-journal')
        if ($case -ceq 'MAINTENANCE') {
            $publicFinalArgs.ExpectedAdoptionTransactionIdentity=$finalJournalIdentity
            $beforePublic=PublicFinalizeSnapshot
            $publicAgain=Run $publicAdapter $publicFinalArgs
            Check ($publicAgain.status-ceq'PASS'-and(PublicFinalizeSnapshot)-ceq$beforePublic) 'maintenance-public-finalize-retry-readonly-keeps-first-proof'
            if ($LegacyFrameworkVersion -ceq '2.0.0') {
                $implicitFinalArgs=$publicFinalArgs.Clone();$implicitFinalArgs.Remove('AdoptionProcessBoundary')
                $implicitFinal=Run $publicAdapter $implicitFinalArgs
                Check ($implicitFinal.status-ceq'PASS'-and(PublicFinalizeSnapshot)-ceq$beforePublic) 'maintenance-supported-implicit-original-finalize-readonly'
            }
        }
        if($B1Daily-and$case-ceq'MAINTENANCE'){
            Write-Output ('B1_DAILY_CONTEXT|project='+$project+'|runtime='+$workspace)
            Invoke-B1DailyMaintenanceCase $project $workspace;Write-Output 'B1_DAILY_CHAIN_PASS|scope=actual-old-adoption-and-current-daily-boundaries';return
        }
        if($NonOwner){continue}
        $agents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
        if($CorrectionAdoption){
            $actualCarrier=Get-Content (Join-Path $project '.ai-workspace/corrections.json') -Raw|ConvertFrom-Json -Depth 100
            Check ($agents.Contains('exit=[base]; revise=[new]; independent=[keep]')) 'adoption-group-effects-merged-with-target-agents-template'
            Check (-not(Test-Path (Join-Path $project 'owned/old.bin'))-and(Id (Join-Path $project 'owned/new.bin'))-cne'NEW'-and[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $project 'owned/new.bin')))-ceq$groupFixture.binary) 'adoption-group-real-binary-create-and-delete'
            Check (@($actualCarrier.corrections|Where-Object correctionId -CEQ ADOPT_EXIT)[0].lifecycle.state-ceq'UNINSTALLED'-and@($actualCarrier.corrections|Where-Object correctionId -CEQ ADOPT_REV)[0].lifecycle.state-ceq'ACTIVE') 'adoption-group-no-revived-exit-and-active-revision'
            foreach($prior in $groupFixture.prior){$actual=@($actualCarrier.corrections|Where-Object correctionId -CEQ $prior.correctionId)[0];$history=Get-Content (Join-Path $project $actual.history.locator) -Raw|ConvertFrom-Json -Depth 100;Check (($history.priorRecord|ConvertTo-Json -Depth 100 -Compress)-ceq($prior|ConvertTo-Json -Depth 100 -Compress)) ('adoption-group-complete-history-'+$prior.correctionId)}
        }
        Check ($agents.Contains('.ai-workspace/BOOTSTRAP.md')-and-not$agents.Contains('{{ROUTER_SKILL_NAME}}')) ($case+'-completed-upgrade-renders-v2-entry')
        Check (@($peerEntries|Where-Object{(Id $_.path)-cne$_.identity}).Count-eq0) ($case+'-upgrade-preserves-b-c-entries-and-pins')
        $newTask=Get-Content (Join-Path $project $taskRelative) -Raw
        $targetRole=if($LegacyFrameworkVersion-ceq'2.0.0'){$sourceRole}elseif($case-ceq'MAINTENANCE'){'FRAMEWORK_MAINTAINER'}else{'TASK_OWNER'}
        if($registeredOrigin){Check ($agents.Contains('# User-owned fixture instructions outside the managed region')) ($case+'-user-agents-outside-managed-region-preserved')}
        Check ($newTask.Contains('role='+$targetRole)-and$newTask.Contains('Task schema: 2.0.0')) ($case+'-owner-route-migrated')
        if($hasKnowledge){$index=(Read-AiwProjectJson (Join-Path $project '.ai-workspace/knowledge/index.json') 'TEST_INDEX').Value;Check ($index.schemaVersion-eq3-and$index.entries.Count-eq1-and$index.entries[0].kind-ceq'PROJECT_DERIVED'-and$index.entries[0].verifiedAt-ceq'2026-09-27T00:00:00Z') 'ordinary-index-converted-with-original-timestamp-and-dependency'}
        $current=Clone $input;$current.schemaVersion=4;$current.contextType='TASK';$current.readOnlyContext='NOT_APPLICABLE';$current.frameworkRoot=$workspace;$current.expectedProjectConfigIdentity=Id (Join-Path $project '.ai-workspace/project.json');$current.expectedCorrectionsIdentity=Id (Join-Path $project '.ai-workspace/corrections.json');$current.expectedTaskIdentity=Id (Join-Path $project $taskRelative);$current.authorizationPackagePath='NOT_REQUIRED';$current.expectedAuthorizationIdentity='NOT_REQUIRED';$current.userDecision='NOT_REQUIRED';$current.exactPaths=@();$current.intentEnvelope.requestedActionKind='NONE';$current.intentEnvelope.requestedResultKind='PLAN'
        # A new post-adoption request; the original old receipt and execution
        # intent above stay byte-bound to their original runtime.
        $current.intentEnvelope.schemaVersion=2
        $current.intentEnvelope['facets']=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:planning')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:plan')};stage=[ordered]@{state='KNOWN';values=@('aiw:planning')}}
        $current.intentEnvelope.objective='Inspect the migrated task and its current framework binding.';$current.intentEnvelope.semanticHints=@('task analysis');$current.intentEnvelope.mutationHints=@()
        Set-FixtureDiscoverContract $current $workspace
        $newInput=Join-Path $runtime 'new-discover.json';SaveJson $newInput $current
        $newResolver=if($case-ceq'MAINTENANCE'){Join-Path $workspace 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $workspace 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
        $recovered=Run $newResolver @{InputPath=$newInput;AsJson=$true};Check ($recovered.status-ceq'PASS') ($case+'-fresh-new-recovery')
        if($FixedRuntimeOnly){
            # Reuse the real original admission/projection. Exercise one
            # write-before-journal interruption in both recovery directions,
            # without replaying the unrelated full storage/lifecycle matrices.
            $recoveryPoints=if($CorrectionAdoption){@(@('owned/old.bin','owned/new.bin','.ai-workspace/upgrade-recovery/corrections/ADOPT_REV/adoption/installation.json')|ForEach-Object{$path=$_;$index=0;foreach($entry in @($prepared.projection.objects|Where-Object changed)){$index++;if($entry.path-ceq$path){$index;break}}})}else{@(1)}
            foreach($point in $recoveryPoints){foreach($direction in @('ROLLBACK','COMPLETE')){
                RestoreFixture $project $prepared.projection
                $stopping=$applyArgs.Clone();$stopping.InterruptBeforeAdoptionJournalWrite=$point
                $stopped=Run $upgrade $stopping
                Check (($stopped-join[char]10).Contains('MAJOR_ADOPTION_INTERRUPTED')) ($case+'-fixed-public-interruption-'+$direction)
                $interruptedJournal=Get-Content -LiteralPath $transactionPath -Raw|ConvertFrom-Json -Depth 100
                $recover=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=(Id $transactionPath);AuthorizationPackagePath=$schema3Path;ExpectedAuthorizationPackageIdentity=(Id $schema3Path);AdoptionRecoveryDirection=$direction;Apply=$true}
                $done=Run $upgrade $recover
                Check ($done.status-ceq$(if($direction-ceq'COMPLETE'){'COMPLETE'}else{'ROLLED_BACK'})) ($case+'-fixed-public-recovery-'+$direction)
                Check (@($prepared.projection.objects|Where-Object{(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))-cne$(if($direction-ceq'COMPLETE'){$_.newIdentity}else{$_.oldIdentity})}).Count-eq0) ($case+'-fixed-recovery-exact-group-'+$direction)
                if($LegacyFrameworkVersion-ceq'2.0.0'){Check ((Id (Join-Path $project $taskRelative))-ceq$package.taskIdentity) ($case+'-fixed-recovery-keeps-read-only-task-'+$direction)}
                if($HistorySeedRoot-and$direction-ceq'ROLLBACK'){
                    Check ((Id $transactionPath)-ceq$seed.journalIdentity) 'rollback-restores-original-major-journal-bytes'
                    $oldRead=Run $resolver @{InputPath=$inputPath;AsJson=$true}
                    Check ($oldRead.status-ceq'PASS') 'rollback-actual-unchanged-old-resolver-pass'
                    # The same storage engine used by the public entry, using
                    # its actual admitted projection/metadata. Inject an error
                    # after a write to cover automatic exception compensation.
                    $failureMetadata=@{};foreach($property in $interruptedJournal.metadata.PSObject.Properties){$failureMetadata[$property.Name]=$property.Value}
                    Import-Module (Join-Path $workspace 'scripts/ProjectAdoptionTransaction.psm1') -Force
                    RejectCall {Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' {throw 'UNEXPECTED_POSTCHECK'} {$true} -FailAfterWrite 1 -Metadata $failureMetadata} 'TRANSACTION_ROLLED_BACK' 'actual-history-exception-compensation'
                    Check ((Id $transactionPath)-ceq$seed.journalIdentity-and@($prepared.projection.objects|Where-Object{(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))-cne$_.oldIdentity}).Count-eq0) 'exception-restores-actual-history-and-whole-projection'
                    $oldRead=Run $resolver @{InputPath=$inputPath;AsJson=$true}
                    Check ($oldRead.status-ceq'PASS') 'exception-actual-unchanged-old-resolver-pass'
                }
                if($direction-ceq'COMPLETE'){
                    Reject $newResolver @{InputPath=$newInput;AsJson=$true} 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED' ($case+'-fixed-recovery-needs-original-finalize')
                    $finalArgs.ExpectedAdoptionTransactionIdentity=Id $transactionPath
                    $closed=Run $upgrade $finalArgs
                    Check ($closed.status-ceq'PASS') ($case+'-fixed-recovery-original-finalize')
                    $observed=ReadCurrent $workspace $case $current $newInput
                    Check ($observed.status-ceq'PASS') ($case+'-fixed-recovery-current-read')
                }
            }}
            if($LegacyFrameworkVersion-ceq'2.0.0'){
                $installPath=Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0/state.json'
                $installBytes=[IO.File]::ReadAllBytes($installPath)
                $invalid=Get-Content -LiteralPath $installPath -Raw|ConvertFrom-Json -Depth 100
                @($invalid.projectionObjects|Where-Object relative -ceq $taskRelative)[0].identity='1|'+('A'*64)
                try{
                    SaveJson $installPath $invalid
                    $rejected=ReadCurrent $workspace $case $current $newInput -AllowFailure
                    Check ($rejected.fixtureExitCode-eq2-and$rejected.reason-ceq'FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT') ($case+'-fixed-reject-forged-historical-task-binding')
                }finally{[IO.File]::WriteAllBytes($installPath,$installBytes)}
                $invalid=Get-Content -LiteralPath $installPath -Raw|ConvertFrom-Json -Depth 100
                try{
                    $invalid.PSObject.Properties.Remove('distributionBinding');SaveJson $installPath $invalid
                    $missingBindingIdentity=Id $installPath
                    $originalRegisterPath=Join-Path $project '.ai-workspace/runtime/project-adoption/register/state.json'
                    $originalRegisterIdentity=Id $originalRegisterPath
                    if($registeredOrigin){
                        # Removing the current binding leaves the independent,
                        # genuine original REGISTER credential. Both layouts
                        # must select that exact old source, never development.
                        $fallback=Get-AiwAdoptedDistributionBinding $project '2.0.0'
                        Check ($fallback.runtimeRoot-ceq$legacy.runtimeRoot-and$fallback.contentIdentity-ceq$legacy.contentIdentity-and$fallback.manifestIdentity-ceq$legacy.manifestIdentity) ($case+'-missing-current-binding-selects-original-registered-source')
                    }
                    if($case-ceq'MAINTENANCE'){
                        $missingBindingGuard='MAINTENANCE_FIXED_RUNTIME_BINDING_REQUIRED'
                        if($registeredOrigin){
                            # The target front door rejects profile6/config7
                            # before invoking the old source resolver.
                            $missingBindingGuard='PROJECT_CONFIG_PIN_SCHEMA_MISMATCH'
                        }
                        Reject (Join-Path $workspace 'scripts/resolve-framework-maintenance-target.ps1') @{ControlRepositoryPath=$project;ExpectedProjectConfigIdentity=(Id (Join-Path $project '.ai-workspace/project.json'));AsJson=$true} $missingBindingGuard ($case+'-fixed-missing-binding-never-runs-development-target')
                    }else{
                        $unbound=ReadCurrent $workspace $case $current $newInput -AllowFailure
                        if($registeredOrigin){
                            Check ($unbound.fixtureExitCode-eq2-and$unbound.status-ceq'FAIL'-and$unbound.reason-ceq'DISTRIBUTION_RUNTIME_ROOT_DRIFT') ($case+'-fixed-missing-binding-never-runs-development-target')
                        }else{
                            Check ($unbound.fixtureExitCode-ne0-and$unbound.reason.Contains('LOCAL_CANDIDATE_PILOT_STATE_FIELDS')) ($case+'-fixed-missing-binding-never-runs-development-target')
                        }
                    }
                    Check ((Id $installPath)-ceq$missingBindingIdentity-and(Id $originalRegisterPath)-ceq$originalRegisterIdentity) ($case+'-missing-binding-rejection-preserves-state-and-original-register')
                }finally{[IO.File]::WriteAllBytes($installPath,$installBytes)}
            }
        }
        if($hasStandard-and$SourceLocation-cne'RELATIVE'){
            $newPolicy=Get-Content (Join-Path $project '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json -Depth 100
            $newRule=@($newPolicy.rules|Where-Object ruleId -ceq PRESERVE_TEST_STANDARD)[0]
            Import-Module (Join-Path $workspace 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -Force
            $sourceProof=Get-AiwProjectPolicySourceClosure -ProjectRoot $project -Rules @($newRule)
            Check ($sourceProof.Documents.Count-eq1-and$sourceProof.Documents[0].locatorKind-ceq'ABSOLUTE_FILE'-and$sourceProof.Documents[0].sourcePath-ceq$standardPath-and$sourceProof.Documents[0].relativePath-ceq'NOT_APPLICABLE'-and(Id $standardPath)-ceq$rule.source.documents[0].identity) ($case+'-public-adoption-preserves-declared-'+$SourceLocation)
        }
        if($refreshRuntimes.Count-gt0){
            $currentAgents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
            $unknownNav=$currentAgents.Replace('<!-- AI-WORKSPACE-FRAMEWORK:END -->',"`n未知nav3职责 .ai-workspace/BOOTSTRAP.md：仅限只读。`n<!-- AI-WORKSPACE-FRAMEWORK:END -->")
            try{
                Prime-FixtureAgents $project $workspace '2.0.0' $case $taskRelative $actor $unknownNav 'unknown-nav3'
                $previewArgs=$scopeArgs.Clone();$previewArgs.WorkspaceRoot=$refreshRuntimes[0];$previewArgs.ExpectedActorRouteTaskIdentity=Id (Join-Path $project $taskRelative)
                $frozen=@($paths)+@('.ai-workspace/runtime/project-adoption/register/state.json','.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')
                $before=@($frozen|Select-Object -Unique|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join[char]10
                Reject (Join-Path $refreshRuntimes[0] 'scripts/upgrade-project.ps1') $previewArgs 'AGENTS_AUTHORIZATION_MIGRATION_CONFLICT' ($case+'-ir01-real-nav3-refresh-rejects-extra-custom')
                Check ($before-ceq(@($frozen|Select-Object -Unique|ForEach-Object{$_+'='+(Id (Join-Path $project $_))})-join[char]10)) ($case+'-ir01-nav3-refresh-conflict-whole-group-zero-write')
            }finally{Prime-FixtureAgents $project $workspace '2.0.0' $case $taskRelative $actor $currentAgents 'restore-nav3'}
        }
        if($CorrectionLifecycleOnly){CurrentCorrectionCases $project $case $current;continue}
        if(-not$CoreOnly){
            # Root PREPARE/ADMIT/Apply/FINALIZE above exercise the public chain.
            # Reuse that exact projection and original admission for the write
            # matrix through the same transaction and recovery implementations.
            $completed=Get-Content $transactionPath -Raw|ConvertFrom-Json -Depth 100 -AsHashtable
            $fixtureMetadata=Clone $completed.metadata
            $fixtureMetadata.Remove('originalFinalize')
            foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $workspace ('scripts/'+$name+'.psm1')) -Force}
            $versionRoot=Join-Path $workspace 'framework/versions/2.0.0'
            Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
            $postcheck={param($root,$candidate)
                $identity=[string](@($candidate.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})[0].newIdentity)
                Assert-AiwRuntimeAdoptionProjection $root $candidate $versionRoot '2.0.0' $identity
                return $true
            }.GetNewClosure()
            $count=@($prepared.projection.objects|Where-Object changed).Count
            foreach($point in 0..$count){foreach($direction in @('COMPLETE','ROLLBACK')){
                RestoreFixture $project $prepared.projection
                $stopped=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite $point -Metadata $fixtureMetadata
                Check ($stopped.status-ceq'INTERRUPTED') ($case+'-interrupt-'+$point+'-'+$direction)
                $resume=@{RepositoryRoot=$project;ObservedActor=$actor;ExpectedTransactionIdentity=(Id $transactionPath);AuthorizationPackagePath=$schema3Path;ExpectedAuthorizationPackageIdentity=(Id $schema3Path);Direction=$direction;Apply=$true}
                if($point-in@(0,$count)){
                    $done=Run $upgrade @{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=$resume.ExpectedTransactionIdentity;AuthorizationPackagePath=$schema3Path;ExpectedAuthorizationPackageIdentity=(Id $schema3Path);AdoptionRecoveryDirection=$direction;Apply=$true}
                }else{$done=Resume-AiwRuntimeAdoption @resume}
                Check ($done.status-ceq$(if($direction-ceq'COMPLETE'){'COMPLETE'}else{'ROLLED_BACK'})) ($case+'-resume-'+$point+'-'+$direction)
                $agents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
                $entryMatches=if($direction-ceq'COMPLETE'){$agents.Contains('.ai-workspace/BOOTSTRAP.md')}else{$agents.Contains('`ai-workspace-router`')}
                Check ($entryMatches-and-not$agents.Contains('{{ROUTER_SKILL_NAME}}')) ($case+'-recovered-entry-'+$point+'-'+$direction)
            }}
            foreach($point in 1..$count){
                RestoreFixture $project $prepared.projection
                $stopped=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptBeforeJournalWrite $point -Metadata $fixtureMetadata
                Check ($stopped.status-ceq'INTERRUPTED') ($case+'-prejournal-interrupt-'+$point)
                $resume.ExpectedTransactionIdentity=Id $transactionPath;$resume.Direction='COMPLETE'
                $done=Resume-AiwRuntimeAdoption @resume;Check ($done.status-ceq'COMPLETE') ($case+'-prejournal-resume-'+$point)
            }
            foreach($direction in @('COMPLETE','ROLLBACK')){
                RestoreFixture $project $prepared.projection
                $name=$case+'-final-state-switch-'+$direction
                $stopped=InterruptFinalStateSwitch $workspace $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $fixtureMetadata $name
                RejectCall {Get-AiwAdoptedDistributionBinding $project '2.0.0'} 'ADOPTION_RECOVERY_REQUIRED' ($name+'-blocks-normal-binding')
                $recoverArgs=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=$stopped.transactionIdentity;AuthorizationPackagePath=$schema3Path;ExpectedAuthorizationPackageIdentity=(Id $schema3Path);AdoptionRecoveryDirection=$direction;Apply=$true}
                $done=Run $upgrade $recoverArgs
                Check ($done.status-ceq$(if($direction-ceq'COMPLETE'){'COMPLETE'}else{'ROLLED_BACK'})) ($name+'-actual-root-recovery')
                $closed=(Read-AiwProjectJson $transactionPath 'FINAL_SWITCH_RECOVERED').Value
                Check ($closed.transactionComplete-is[bool]-and$closed.transactionComplete-and@($prepared.projection.objects|Where-Object{(FixtureObjectIdentity (Get-AiwContainedPath $project $_.path))-cne$(if($direction-ceq'COMPLETE'){$_.newIdentity}else{$_.oldIdentity})}).Count-eq0) ($name+'-recovery-closes-exact-group')
                if($direction-ceq'COMPLETE'){
                    Reject $newResolver @{InputPath=$newInput;AsJson=$true} 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED' ($name+'-still-requires-original-finalize')
                    $finalArgs.ExpectedAdoptionTransactionIdentity=Id $transactionPath
                    $closedOriginal=Run $upgrade $finalArgs
                    $observed=ReadCurrent $workspace $case $current $newInput
                    Check ($closedOriginal.status-ceq'PASS'-and$observed.status-ceq'PASS') ($name+'-actual-original-finalize-enables-normal-work')
                }
            }
            RestoreFixture $project $prepared.projection
            $null=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite 1 -Metadata $fixtureMetadata
            $journalBytes=[IO.File]::ReadAllBytes($transactionPath)
            foreach($field in @('transactionComplete','completedWrites')){
                $invalidJournal=Get-Content $transactionPath -Raw|ConvertFrom-Json -Depth 100
                $invalidJournal.$field=[string]$invalidJournal.$field;SaveJson $transactionPath $invalidJournal
                $resume.ExpectedTransactionIdentity=Id $transactionPath
                RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_TRANSACTION_STATE_SCHEMA' ($case+'-reject-untyped-'+$field)
                [IO.File]::WriteAllBytes($transactionPath,$journalBytes)
            }
            $resume.ExpectedTransactionIdentity=Id $transactionPath
            $configPath=Join-Path $project '.ai-workspace/project.json';$thirdParty=Get-Content $configPath -Raw|ConvertFrom-Json;$thirdParty.displayName='Third party bytes';SaveJson $configPath $thirdParty;$thirdPartyId=Id $configPath
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_RECOVERY_CONTEXT_DRIFT' ($case+'-reject-third-party-config')
            Check ((Id $configPath)-ceq$thirdPartyId) ($case+'-third-party-config-not-overwritten')
            RestoreFixture $project $prepared.projection
            $null=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite 0 -Metadata $fixtureMetadata
            $last=@($prepared.projection.objects|Where-Object changed)[-1]
            [IO.File]::WriteAllBytes((Join-Path $project $last.path),[Convert]::FromBase64String($last.newBase64))
            $resume.ExpectedTransactionIdentity=Id $transactionPath
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_RECOVERY_UNREACHABLE_STATE' ($case+'-reject-impossible-new-task-first')
            RestoreFixture $project $prepared.projection
            $null=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite 1 -Metadata $fixtureMetadata
            $resume.ExpectedTransactionIdentity=Id $transactionPath
            if($hasStandard){
            SaveText $standardPath 'Third party standard after interruption.'
            $driftedStandard=Id $standardPath
            $recoveryBefore=@($prepared.projection.objects|ForEach-Object{[ordered]@{path=$_.path;identity=(Id (Join-Path $project $_.path))}})|ConvertTo-Json -Depth 10 -Compress
            $journalBefore=Id $transactionPath
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'CONTENT_IDENTITY_DRIFT|DOCUMENT' ($case+'-reject-source-drift-during-recovery')
            $recoveryAfter=@($prepared.projection.objects|ForEach-Object{[ordered]@{path=$_.path;identity=(Id (Join-Path $project $_.path))}})|ConvertTo-Json -Depth 10 -Compress
            Check ((Id $standardPath)-ceq$driftedStandard-and$recoveryBefore-ceq$recoveryAfter-and(Id $transactionPath)-ceq$journalBefore) ($case+'-source-drift-rejection-preserves-all-project-and-source-bytes')
            [IO.File]::WriteAllBytes($standardPath,$standardBytes)
            }
            $done=Resume-AiwRuntimeAdoption @resume;Check ($done.status-ceq'COMPLETE') ($case+'-recovery-after-source-restored')
            Reject $newResolver @{InputPath=$newInput;AsJson=$true} 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED' ($case+'-recovered-storage-does-not-replace-original-finalize')
        }
        # Exercise actual public refreshes after a completed major adoption.
        # The first major journal remains the recovery-material owner.
        if($CorrectionAdoption){$scopeArgs.Remove('AdoptionCorrectionsPlanPath');$scopeArgs.Remove('ExpectedAdoptionCorrectionsPlanIdentity')}
        $finalArgs.ExpectedAdoptionTransactionIdentity=Id $transactionPath
        $finalized=Run $upgrade $finalArgs;Check ($finalized.status-ceq'PASS') ($case+'-original-finalize-before-refresh')
        $originIdentity=Id $transactionPath;$originBytes=[IO.File]::ReadAllBytes($transactionPath)
        $refreshPath=Join-Path $project '.ai-workspace/runtime/project-adoption/refresh/state.json'
        $statePath=Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0/state.json'
        $refreshInput=Join-Path $runtime 'refresh-discover.json';$firstRefresh=$null;$firstTransaction=$null
        foreach($number in 0..1){
            $next=$refreshRuntimes[$number]
            if($FixedRuntimeOnly-and$number-eq1){
                [IO.File]::AppendAllText((Join-Path $project $taskRelative),[Environment]::NewLine+'Historical adoption task updated before another fixed-runtime refresh.'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
            }
            $action=NewRefreshAction $scopeArgs $next $schema3 (Join-Path $runtime ('refresh-'+$number+'-package.json'))
            $sourceRuntime=if($number-eq0){$workspace}else{$refreshRuntimes[$number-1]}
            $process=Clone $action.authorization
            $process.schemaVersion=if($case-ceq'MAINTENANCE'){2}else{1}
            $process.bundle='FIXTURE_REFRESH_PROCESS'
            $process.Remove('postObjectIdentities');$process.Remove('targetFrameworkSnapshot')
            $process.invalidatesOn=@($process.invalidatesOn|Where-Object{$_-cne'POST_OBJECT_DRIFT'})
            if($case-ceq'MAINTENANCE'){$process.repositoryId='CONTROL';$process.invalidatesOn+=@('REPOSITORY_CHANGE')}
            $processPath=Join-Path $runtime ('refresh-'+$number+'-process-package.json');SaveJson $processPath $process
            $processInput=Clone $current;$processInput.frameworkRoot=$sourceRuntime
            $processInput.intentEnvelope.requestedActionKind='CONTROL_WRITE';$processInput.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT'
            $processInput.intentEnvelope.facets.workType.values=@('aiw:adoption');$processInput.intentEnvelope.facets.stage.values=@('aiw:adoption');$processInput.intentEnvelope.facets.deliverableType.values=@('aiw:configuration')
            $processInput.expectedProjectConfigIdentity=Id (Join-Path $project '.ai-workspace/project.json')
            $processInput.expectedCorrectionsIdentity=Id (Join-Path $project '.ai-workspace/corrections.json')
            $processInput.expectedTaskIdentity=Id (Join-Path $project $taskRelative)
            $processInput.exactPaths=@($action.authorization.exactPaths)
            $processInput.authorizationPackagePath=$processPath;$processInput.expectedAuthorizationIdentity=Id $processPath
            $processInput.userDecision=$process.userConfirmation;$processInput.intentEnvelope.objective='Adopt the exact refreshed fixed package and close the original process.'
            $processInput.intentEnvelope.semanticHints=@('fixed runtime refresh','project adoption')
            $processInput.intentEnvelope.pathHints=@();$processInput.intentEnvelope.mutationHints=@('control')
            Set-FixtureDiscoverContract $processInput $sourceRuntime
            $processInputPath=Join-Path $runtime ('refresh-'+$number+'-process-discover.json');SaveJson $processInputPath $processInput
            $sourceResolver=if($case-ceq'MAINTENANCE'){Join-Path $sourceRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $sourceRuntime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
            $processDiscover=Run $sourceResolver @{InputPath=$processInputPath;AsJson=$true}
            Check ($processDiscover.status-ceq'PASS') ($case+'-refresh-'+$number+'-original-discover')
            $processReceiptPath=Join-Path $runtime ('refresh-'+$number+'-process-receipt.json');SaveJson $processReceiptPath $processDiscover.compactReceipt
            $processAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$processReceiptPath;expectedDiscoverReceiptIdentity=(Id $processReceiptPath);preparationReceipts=@($processDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
            Set-FixtureBoundaryContract $processAdmit $sourceRuntime
            $processAdmitPath=Join-Path $runtime ('refresh-'+$number+'-process-admit.json');SaveJson $processAdmitPath $processAdmit
            $processArgs=$action.arguments.Clone();$processArgs.Remove('Apply');$processArgs.Remove('AuthorizationPackagePath');$processArgs.Remove('ExpectedAuthorizationPackageIdentity')
            $processArgs.CurrentProcessInputPath=$processAdmitPath;$processArgs.ExpectedCurrentProcessInputIdentity=Id $processAdmitPath
            $processArgs.AdoptionProcessMode='PREPARE'
            $refreshPreparation=Run $action.tool $processArgs
            Check ($refreshPreparation.status-ceq'PREPARED'-and$refreshPreparation.previousDistribution.runtimeRoot-ceq$sourceRuntime-and$refreshPreparation.targetDistribution.runtimeRoot-ceq$next) ($case+'-refresh-'+$number+'-prepared')
            Assert-FixtureTargetBodies $refreshPreparation ($case+'-refresh-'+$number)
            $refreshPreparationPath=Join-Path $runtime ('refresh-'+$number+'-preparation.json');SaveJson $refreshPreparationPath $refreshPreparation
            $processAdmit.preparationReceipts=@(@($processAdmit.preparationReceipts)+@($refreshPreparation.selectedRuleBlocks.preparationRequirements)|Sort-Object -Unique)+@('ADOPTION_TARGET_RULES_LOADED|'+(Id $refreshPreparationPath))
            if($refreshPreparation.selectorSemanticJudgmentRequired){
                Check (@($refreshPreparation.selectorDifferences|Where-Object{$_.requirementId-cne('project:'+$projectId+':FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY')-or$_.classification-cne'UNCLASSIFIED_CONSERVATIVE'}).Count-eq0) ($case+'-refresh-selector-difference-judged')
                $processAdmit.preparationReceipts+=@('ADOPTION_SELECTOR_SEMANTICS_CONFIRMED|'+(Id $refreshPreparationPath))
            }
            SaveJson $processAdmitPath $processAdmit;$processArgs.ExpectedCurrentProcessInputIdentity=Id $processAdmitPath
            $processArgs.AdoptionProcessMode='ADMIT_ACTION';$processArgs.AdoptionPreparationPath=$refreshPreparationPath;$processArgs.ExpectedAdoptionPreparationIdentity=Id $refreshPreparationPath
            $refreshAdmitted=Run $action.tool $processArgs
            Check ($refreshAdmitted.status-ceq'PASS') ($case+'-refresh-'+$number+'-original-admit')
            $refreshAdmittedPath=Join-Path $runtime ('refresh-'+$number+'-admit-result.json');SaveJson $refreshAdmittedPath $refreshAdmitted
            $action.arguments.AdmitResultPath=$refreshAdmittedPath;$action.arguments.ExpectedAdmitResultIdentity=Id $refreshAdmittedPath
            $result=Run $action.tool $action.arguments
            Check (($result-join"`n").Contains('LOCAL_CANDIDATE_PROJECT_PROJECTION_REFRESHED')) ($case+'-public-refresh-'+$number)
            $refreshJournal=Join-Path $project '.ai-workspace/runtime/project-adoption/refresh/state.json'
            $refreshFinal=Clone $processAdmit;$refreshFinal.mode='FINALIZE_OUTPUT'
            $refreshFinal.resultReceipts=@(@($processDiscover.compactReceipt.selectedObligations.resultRequirements)+@($refreshPreparation.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($refreshPreparation.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.newIdentity})
            $refreshFinalPath=Join-Path $runtime ('refresh-'+$number+'-final-input.json');SaveJson $refreshFinalPath $refreshFinal
            $finalProcessArgs=$processArgs.Clone();$finalProcessArgs.AdoptionProcessMode='FINALIZE_OUTPUT';$finalProcessArgs.CurrentProcessInputPath=$refreshFinalPath;$finalProcessArgs.ExpectedCurrentProcessInputIdentity=Id $refreshFinalPath
            $finalProcessArgs.AdmitResultPath=$refreshAdmittedPath;$finalProcessArgs.ExpectedAdmitResultIdentity=Id $refreshAdmittedPath
            $finalProcessArgs.AuthorizationPackagePath=$action.arguments.AuthorizationPackagePath;$finalProcessArgs.ExpectedAuthorizationPackageIdentity=$action.arguments.ExpectedAuthorizationPackageIdentity
            $finalProcessArgs.ExpectedAdoptionTransactionIdentity=Id $refreshJournal
            $refreshClosed=Run $action.tool $finalProcessArgs
            Check ($refreshClosed.status-ceq'PASS'-and$refreshClosed.reason-ceq'ORIGINAL_SAME_PIN_REFRESH_FINALIZED') ($case+'-refresh-'+$number+'-original-finalize')
            if($number-eq0){
                $wrongDelivery=Clone $refreshFinal
                $wrongDelivery.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='arbitrary';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
                $wrongDeliveryPath=Join-Path $runtime 'refresh-wrong-consumer.json';SaveJson $wrongDeliveryPath $wrongDelivery
                $wrongCall=$finalProcessArgs.Clone();$wrongCall.CurrentProcessInputPath=$wrongDeliveryPath;$wrongCall.ExpectedCurrentProcessInputIdentity=Id $wrongDeliveryPath
                Reject $action.tool $wrongCall 'DELIVERY_CONSUMER_CHANNEL_MISMATCH' ($case+'-refresh-rejects-wrong-delivery-consumer')
                $nativeDelivery=Clone $refreshFinal
                $nativeDelivery.deliveryContext=[ordered]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
                $nativeDeliveryPath=Join-Path $runtime 'refresh-native-response.json';SaveJson $nativeDeliveryPath $nativeDelivery
                $nativeCall=$finalProcessArgs.Clone();$nativeCall.CurrentProcessInputPath=$nativeDeliveryPath;$nativeCall.ExpectedCurrentProcessInputIdentity=Id $nativeDeliveryPath
                $nativeClosed=Run $action.tool $nativeCall
                Check ($nativeClosed.status-ceq'PASS'-and$nativeClosed.delivery.status-ceq'READY_TO_SEND'-and$nativeClosed.consumer.recipient-ceq'USER') ($case+'-refresh-native-preparation-bound')
            }
            Check ((Id $transactionPath)-ceq$originIdentity) ($case+'-refresh-'+$number+'-keeps-major-material')
            $state=(Read-AiwProjectJson $statePath 'REFRESH_STATE').Value
            Check ($state.majorTransition.transactionRelativePath-ceq'.ai-workspace/runtime/project-adoption/upgrade/state.json'-and$state.distributionBinding.runtimeRoot-ceq$next) ($case+'-refresh-'+$number+'-preserves-link-and-updates-runtime')
            $observed=ReadCurrent $next $case $current $refreshInput
            Check ($observed.status-ceq'PASS') ($case+'-refresh-'+$number+'-normal-discover')
            if($number-eq0){$firstRefresh=$action;$firstTransaction=Get-Content -LiteralPath $refreshPath -Raw|ConvertFrom-Json -Depth 100}
        }
        $normal=$scopeArgs.Clone();$normal.WorkspaceRoot=$refreshRuntimes[1];$normal.ExpectedActorRouteTaskIdentity=Id (Join-Path $project $taskRelative)
        $normalResult=Run (Join-Path $refreshRuntimes[1] 'scripts/upgrade-project.ps1') $normal
        Check (($normalResult-join"`n").Contains('RECOVERY_COMPLETE|to=2.0.0|writes=ZERO')) ($case+'-normal-upgrader-after-two-refreshes')
        $stateBytes=[IO.File]::ReadAllBytes($statePath);$badState=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -Depth 100
        $badState.actor='unrelated-historical-actor';SaveJson $statePath $badState
        $observed=ReadCurrent $refreshRuntimes[1] $case $current $refreshInput -AllowFailure
        Check ($observed.fixtureExitCode-ne0-and$observed.status-ceq'FAIL'-and($observed.reason.Contains('MAJOR_RECOVERY_ORIGIN_DRIFT')-or$observed.reason.Contains('FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT'))) ($case+'-normal-discover-rejects-history-drift')
        Reject (Join-Path $refreshRuntimes[1] 'scripts/upgrade-project.ps1') $normal 'FIXED_ADOPTION_CURRENT_POSTIMAGE_DRIFT' ($case+'-normal-upgrader-rejects-history-drift')
        [IO.File]::WriteAllBytes($statePath,$stateBytes)
        $badOrigin=Get-Content -LiteralPath $transactionPath -Raw|ConvertFrom-Json -Depth 100
        $savedState=@($badOrigin.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'})[0]
        $savedState.newBase64=[Convert]::ToBase64String($utf8.GetBytes('{}'));SaveJson $transactionPath $badOrigin
        $originGuardPaths=@($badOrigin.projection.objects.path)+@($(if($hasStandard){$standardRelative}),'.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')
        $originGuardBefore=@($originGuardPaths|Where-Object{$_}|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;identity=(Id (Get-AiwContainedPath $project $_))}})|ConvertTo-Json -Depth 10 -Compress
        $observed=ReadCurrent $refreshRuntimes[1] $case $current $refreshInput -AllowFailure
        $originReason=[string]$observed.reason
        if($originReason.StartsWith('MAINTENANCE_TARGET_RESOLUTION_FAILED|',[StringComparison]::Ordinal)){
            $inner=$originReason.Substring('MAINTENANCE_TARGET_RESOLUTION_FAILED|'.Length)|ConvertFrom-Json -Depth 100
            Check ($inner.status-ceq'FAIL') ($case+'-corrupt-origin-inner-result-remains-fail')
            $originReason=[string]$inner.reason
        }
        $originRejected=$originReason.StartsWith('MAJOR_RECOVERY_ORIGIN',[StringComparison]::Ordinal)-or$originReason-ceq'ADOPTION_ORIGINAL_FINALIZE_PROJECTION'
        Check ($observed.fixtureExitCode-ne0-and$observed.status-ceq'FAIL'-and$originRejected) ($case+'-normal-discover-rejects-corrupt-origin-bytes')
        $originGuardAfter=@($originGuardPaths|Where-Object{$_}|Sort-Object -Unique|ForEach-Object{[ordered]@{path=$_;identity=(Id (Get-AiwContainedPath $project $_))}})|ConvertTo-Json -Depth 10 -Compress
        Check ($originGuardAfter-ceq$originGuardBefore) ($case+'-corrupt-origin-rejection-preserves-whole-projection-source-and-journals')
        [IO.File]::WriteAllBytes($transactionPath,$originBytes)
        if(-not$CoreOnly){
            $refreshRoot=$refreshRuntimes[0];$refreshVersion=Join-Path $refreshRoot 'framework/versions/2.0.0'
            foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $refreshRoot ('scripts/'+$name+'.psm1')) -Force}
            Import-Module (Join-Path $refreshVersion 'scripts/ProcessRequirementComposition.psm1') -Force
            $postcheck={param($root,$candidate)
                Assert-AiwRuntimeAdoptionProjection $root $candidate $refreshVersion '2.0.0' (Id (Join-Path $root '.ai-workspace/project.json'))
                return $true
            }.GetNewClosure()
            $refreshProjection=$firstTransaction.projection;$count=@($refreshProjection.objects|Where-Object changed).Count
            foreach($window in @('AFTER_WRITE','BEFORE_JOURNAL','BEFORE_FINAL_STATE_SWITCH')){
                $points=if($window-ceq'AFTER_WRITE'){@(0..$count)}elseif($window-ceq'BEFORE_JOURNAL'){@(1..$count)}else{@($count)}
                foreach($point in $points){foreach($direction in @('COMPLETE','ROLLBACK')){
                    RestoreRefreshFixture $project $refreshProjection
                    if($window-ceq'BEFORE_FINAL_STATE_SWITCH'){
                        $stopped=InterruptFinalStateSwitch $refreshRoot $project $refreshProjection '.ai-workspace/runtime/project-adoption/refresh/state.json' (Clone $firstTransaction.metadata) ($case+'-refresh-'+$window+'-'+$direction)
                    }else{
                        $interrupt=if($window-ceq'AFTER_WRITE'){@{InterruptAfterWrite=$point}}else{@{InterruptBeforeJournalWrite=$point}}
                        $stopped=Invoke-AiwProjectProjectionTransaction $project $refreshProjection '.ai-workspace/runtime/project-adoption/refresh/state.json' $postcheck {param($r,$p) $true} -Metadata (Clone $firstTransaction.metadata) @interrupt
                    }
                    Check ($stopped.status-ceq'INTERRUPTED') ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-interrupted')
                    RejectCall {Get-AiwAdoptedDistributionBinding $project '2.0.0'} 'ADOPTION_RECOVERY_REQUIRED' ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-blocks-normal-binding')
                    $resume=@{RepositoryRoot=$project;ExpectedTransactionIdentity=(Id $refreshPath);AuthorizationPackagePath=$firstRefresh.arguments.AuthorizationPackagePath;ExpectedAuthorizationPackageIdentity=$firstRefresh.arguments.ExpectedAuthorizationPackageIdentity;ObservedActor=$actor;Direction=$direction;Apply=$true}
                    if($point-in@(0,$count)){
                        $done=Run $firstRefresh.tool @{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=$resume.ExpectedTransactionIdentity;AuthorizationPackagePath=$resume.AuthorizationPackagePath;ExpectedAuthorizationPackageIdentity=$resume.ExpectedAuthorizationPackageIdentity;AdoptionRecoveryDirection=$direction;Apply=$true}
                    }else{$done=Resume-AiwRuntimeAdoption @resume}
                    Check ($done.status-ceq$(if($direction-ceq'COMPLETE'){'COMPLETE'}else{'ROLLED_BACK'})) ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-recovered')
                    $active=if($direction-ceq'COMPLETE'){$refreshRoot}else{$workspace}
                    $observed=ReadCurrent $active $case $current $refreshInput
                    Check ($observed.status-ceq'PASS'-and(Id $transactionPath)-ceq$originIdentity) ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-normal-recovery-keeps-origin')
                }}
            }
            RestoreRefreshFixture $project $refreshProjection
            $args=$firstRefresh.arguments.Clone();$args.InterruptBeforeAdoptionJournalWrite=1
            $stopped=Run $firstRefresh.tool $args
            Check (($stopped-join"`n").Contains('RUNTIME_ADOPTION_INTERRUPTED|state=.ai-workspace/runtime/project-adoption/refresh/state.json')) ($case+'-public-refresh-forwards-journal-interruption')
            $changed=@($refreshProjection.objects|Where-Object changed)[0];$changedPath=Join-Path $project $changed.path
            SaveText $changedPath 'Third party bytes during refresh.';$thirdParty=Id $changedPath
            $resume.ExpectedTransactionIdentity=Id $refreshPath;$resume.Direction='COMPLETE'
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_RECOVERY_THIRD_PARTY_OBJECT' ($case+'-refresh-recovery-rejects-third-party')
            Check ((Id $changedPath)-ceq$thirdParty) ($case+'-refresh-recovery-preserves-third-party')
            [IO.File]::WriteAllBytes($changedPath,[Convert]::FromBase64String($changed.newBase64))
            $done=Resume-AiwRuntimeAdoption @resume
            $observed=ReadCurrent $refreshRoot $case $current $refreshInput
            Check ($done.status-ceq'COMPLETE'-and$observed.status-ceq'PASS'-and(Id $transactionPath)-ceq$originIdentity) ($case+'-refresh-resumes-after-third-party-restored')
        }
        # A fresh same-pin action made with the new root cannot turn an ADMIT
        # without PREPARE into a historical recovery exception.
        $stateOnlySource=(Read-AiwProjectJson $statePath 'STATE_ONLY_SOURCE').Value.distributionBinding.runtimeRoot
        $stateOnlyRuntime=Join-Path $temp ($case.ToLowerInvariant()+'-state-only-runtime')
        Copy-Item -LiteralPath $stateOnlySource -Destination $stateOnlyRuntime -Recurse
        NamedFixture $stateOnlyRuntime '2.0.0-snapshot.4'
        $stateOnly=NewRefreshAction $scopeArgs $stateOnlyRuntime $schema3 (Join-Path $runtime 'state-only-schema3.json')
        Check (@($stateOnly.authorization.exactPaths).Count-eq1-and$stateOnly.authorization.exactPaths[0]-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json') ($case+'-state-only-scope')
        $stateOnlyProcess=Clone $stateOnly.authorization
        $stateOnlyProcess.schemaVersion=if($case-ceq'MAINTENANCE'){2}else{1}
        $stateOnlyProcess.bundle='FIXTURE_STATE_ONLY_PROCESS'
        $stateOnlyProcess.Remove('postObjectIdentities');$stateOnlyProcess.Remove('targetFrameworkSnapshot')
        $stateOnlyProcess.invalidatesOn=@($stateOnlyProcess.invalidatesOn|Where-Object{$_-cne'POST_OBJECT_DRIFT'})
        if($case-ceq'MAINTENANCE'){$stateOnlyProcess.repositoryId='CONTROL';$stateOnlyProcess.invalidatesOn+=@('REPOSITORY_CHANGE')}
        $stateOnlyProcessPath=Join-Path $runtime 'state-only-process-package.json';SaveJson $stateOnlyProcessPath $stateOnlyProcess
        $stateOnlyDiscover=Clone $current;$stateOnlyDiscover.frameworkRoot=$stateOnlySource
        $stateOnlyDiscover.intentEnvelope.requestedActionKind='CONTROL_WRITE';$stateOnlyDiscover.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT'
        $stateOnlyDiscover.intentEnvelope.facets.workType.values=@('aiw:adoption');$stateOnlyDiscover.intentEnvelope.facets.stage.values=@('aiw:adoption');$stateOnlyDiscover.intentEnvelope.facets.deliverableType.values=@('aiw:configuration')
        $stateOnlyDiscover.expectedProjectConfigIdentity=Id (Join-Path $project '.ai-workspace/project.json')
        $stateOnlyDiscover.expectedCorrectionsIdentity=Id (Join-Path $project '.ai-workspace/corrections.json')
        $stateOnlyDiscover.expectedTaskIdentity=Id (Join-Path $project $taskRelative)
        $stateOnlyDiscover.exactPaths=@($stateOnly.authorization.exactPaths)
        $stateOnlyDiscover.authorizationPackagePath=$stateOnlyProcessPath;$stateOnlyDiscover.expectedAuthorizationIdentity=Id $stateOnlyProcessPath
        $stateOnlyDiscover.userDecision=$stateOnlyProcess.userConfirmation
        $stateOnlyDiscover.intentEnvelope.objective='Refresh the fixed runtime without changing the version payload or selected rules.'
        $stateOnlyDiscover.intentEnvelope.semanticHints=@('fixed runtime refresh','project adoption')
        $stateOnlyDiscover.intentEnvelope.pathHints=@();$stateOnlyDiscover.intentEnvelope.mutationHints=@('control')
        Set-FixtureDiscoverContract $stateOnlyDiscover $stateOnlySource
        $stateOnlyDiscoverPath=Join-Path $runtime 'state-only-discover.json';SaveJson $stateOnlyDiscoverPath $stateOnlyDiscover
        $stateOnlyResolver=if($case-ceq'MAINTENANCE'){Join-Path $stateOnlySource 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $stateOnlySource 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
        $stateOnlySelected=Run $stateOnlyResolver @{InputPath=$stateOnlyDiscoverPath;AsJson=$true}
        $stateOnlyReceipt=Join-Path $runtime 'state-only-receipt.json';SaveJson $stateOnlyReceipt $stateOnlySelected.compactReceipt
        $stateOnlyAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$stateOnlyReceipt;expectedDiscoverReceiptIdentity=(Id $stateOnlyReceipt);preparationReceipts=@($stateOnlySelected.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
        Set-FixtureBoundaryContract $stateOnlyAdmit $stateOnlySource
        $stateOnlyAdmitPath=Join-Path $runtime 'state-only-admit-input.json';SaveJson $stateOnlyAdmitPath $stateOnlyAdmit
        $stateOnlyAccepted=Run $stateOnlyResolver @{InputPath=$stateOnlyAdmitPath;AsJson=$true}
        $stateOnlyAcceptedPath=Join-Path $runtime 'state-only-admit-result.json';SaveJson $stateOnlyAcceptedPath $stateOnlyAccepted
        Check ($stateOnlyAccepted.status-ceq'PASS'-and$null-eq$stateOnlyAccepted.PSObject.Properties['adoptionPreparation']) ($case+'-state-only-direct-admit-has-no-prepare')
        $stateBefore=Id $statePath;$journalBefore=Id $refreshPath
        $stateOnly.arguments.AdmitResultPath=$stateOnlyAcceptedPath;$stateOnly.arguments.ExpectedAdmitResultIdentity=Id $stateOnlyAcceptedPath
        Reject $stateOnly.tool $stateOnly.arguments 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED' ($case+'-state-only-new-root-rejects-unprepared-admit')
        Check ((Id $statePath)-ceq$stateBefore-and(Id $refreshPath)-ceq$journalBefore) ($case+'-state-only-rejection-writes-zero')
        $stateOnly.arguments.Remove('AdmitResultPath');$stateOnly.arguments.Remove('ExpectedAdmitResultIdentity')
        Reject $stateOnly.tool $stateOnly.arguments 'SAME_PIN_ADMIT_ORIGINAL_EVIDENCE_REQUIRED' ($case+'-state-only-new-root-requires-admit-result')
        Check ((Id $statePath)-ceq$stateBefore-and(Id $refreshPath)-ceq$journalBefore) ($case+'-state-only-missing-admit-writes-zero')
        if($FixedRuntimeOnly){
            # Completed history must remain usable after the old task changes
            # and is archived; current task authorization remains independent.
            $oldTaskPath=Join-Path $project $taskRelative
            SaveText $oldTaskPath ((Get-Content -LiteralPath $oldTaskPath -Raw)+[char]10+'Completed adoption; current planning note.')
            $observed=ReadCurrent $refreshRuntimes[1] $case $current $refreshInput
            Check ($observed.status-ceq'PASS') ($case+'-fixed-history-does-not-freeze-current-task-bytes')
            $nextTask='.ai-workspace/tasks/active/AFTER-001.md'
            SaveText (Join-Path $project $nextTask) ((Get-Content -LiteralPath $oldTaskPath -Raw).Replace('# MAJOR-001','# AFTER-001'))
            SaveText (Join-Path $project '.ai-workspace/tasks/archive/MAJOR-001.md') (Get-Content -LiteralPath $oldTaskPath -Raw)
            [IO.File]::Delete($oldTaskPath)
            $current.taskPath=Join-Path $project $nextTask
            $observed=ReadCurrent $refreshRuntimes[1] $case $current $refreshInput
            Check ($observed.status-ceq'PASS') ($case+'-fixed-history-survives-task-archive')
            $normal.ActorRouteTaskPath=$nextTask;$normal.ExpectedActorRouteTaskIdentity=Id $current.taskPath
            $normalResult=Run (Join-Path $refreshRuntimes[1] 'scripts/upgrade-project.ps1') $normal
            Check (($normalResult-join[char]10).Contains('RECOVERY_COMPLETE|to=2.0.0|writes=ZERO')) ($case+'-fixed-root-recovery-survives-task-archive')
        }else{CurrentCorrectionCases $project $case $current}
    }
    Check ((Get-AiwDistributionBinding $LegacyRuntimeRoot $LegacyFrameworkVersion -Required).contentIdentity-ceq$legacy.contentIdentity) 'legacy-runtime-not-modified'
    Write-Output ('RESULT|major-adoption-bridge|passed='+$passed+'|failed=0')
} finally {
    if($KeepFixture){Write-Output ('FIXTURE_RETAINED|'+$temp)}else{
        $base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar
        $full=[IO.Path]::GetFullPath($temp)
        if(-not$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-major-bridge-')){throw 'FIXTURE_CLEANUP_BOUNDARY'}
        [IO.Directory]::Delete($full,$true)
    }
}
