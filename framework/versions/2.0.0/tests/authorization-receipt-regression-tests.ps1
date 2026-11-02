[CmdletBinding()]
param([switch]$KeepFixture,[switch]$ArchiveDeliveryOnly,[string]$LegacyArchiveResolverPath,[switch]$LifecycleOnly,[ValidateSet('All','PackageShape','BindingIndependence','ReviewIndependence','ContinuationRepair','ContinuationScope','ReaderAssignment','DeliveryAcceptance','ExternalGrant','ExecutionTarget','FocusedBoundaries','FocusedEvidence')][string]$Group='All')

$ErrorActionPreference='Stop'
$authorizationFirstFailure=$null;$authorizationCleanupFailure=$null
try {
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
$Group=@('All','PackageShape','BindingIndependence','ReviewIndependence','ContinuationRepair','ContinuationScope','ReaderAssignment','DeliveryAcceptance','ExternalGrant','ExecutionTarget','FocusedBoundaries','FocusedEvidence')|Where-Object{$_-ieq$Group}
if($LifecycleOnly-and$Group-cne'ContinuationRepair'){throw 'LIFECYCLE_REQUIRES_CONTINUATION_REPAIR'}
if($ArchiveDeliveryOnly-and$PSBoundParameters.ContainsKey('Group')){throw 'AUTHORIZATION_GROUP_FLAGS_CONFLICT'}
if($ArchiveDeliveryOnly){$Group='DeliveryAcceptance'}
if($Group-ceq'All'){
 foreach($selected in @('PackageShape','BindingIndependence','ContinuationRepair','DeliveryAcceptance','ReaderAssignment')){
  $arguments=@('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Group',$selected)
  if($KeepFixture){$arguments+='-KeepFixture'}
  if($LegacyArchiveResolverPath){$arguments+=@('-LegacyArchiveResolverPath',$LegacyArchiveResolverPath)}
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) $arguments -GroupId ('authorization-'+$selected)
  $run.Output|ForEach-Object{Write-Output $_};if($run.Code-ne0){exit $run.Code}
 };return
}
$useKernel=$false
$authKernel=@(Import-Module (Join-Path $PSScriptRoot '../scripts/AuthorizationCheck.psm1') -PassThru)[0]
function Invoke-AuthNative {
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @($args) -WorkingDirectory $(if($null-ne(Get-Variable temp -ErrorAction SilentlyContinue)-and(Test-Path -LiteralPath $temp)){$temp}else{(Get-Location).Path}) -GroupId ('authorization-'+$Group)
 Set-Variable -Name LASTEXITCODE -Scope 1 -Value $run.Code
 return $run.Output
}
function Write-GroupCompletion {Write-Output ('RESULT|'+$script:passed+' passed|scope=authorization-receipt-regression|group='+$Group)}
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Write-Json([string]$Path,$Value){Write-Utf8 $Path ($Value|ConvertTo-Json -Depth 50)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}

$checker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\check-authorization.ps1'))
$receiverBinder=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\bind-receiver-authorization.ps1'))
$taskChecker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\check-task-card.ps1'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-authorization-receipt-'+[guid]::NewGuid().ToString('N'))
$control=Join-Path $temp '.ai-workspace'
$taskRelative='.ai-workspace/tasks/active/AUTH-REGRESSION-001.md'
$taskPath=Join-Path $temp $taskRelative
$objectRelative='src/item.txt'
$objectPath=Join-Path $temp $objectRelative
$packagePath=Join-Path $control 'authorization.json'

function Write-Task([string]$Profile,[string]$Phase,[string]$Lifecycle='ACTIVE',[switch]$OwnerRoute){
  $currentExact=if($Profile-ceq'CRITICAL'){" current_exact=$objectRelative;"}else{''}
  $criticalLines=if($Profile-ceq'CRITICAL'){"- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=bind the package profile to the current task; added_machinery=NONE; escalation_trigger=another independent profile-binding defect`n- Phase gate: FALSE`n"}else{''}
  $route=if($OwnerRoute-or$Phase-ceq'GIT'){'actor=owner-fixture; role=TASK_OWNER'}else{'actor=writer-fixture; role=EXECUTOR'}
  Write-Utf8 $taskPath ("# AUTH-REGRESSION-001 - authorization regression fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: $route; phase=$Phase`n- Range summary: profile=$Profile; lifecycle=$Lifecycle;$currentExact expected_paths=[$objectRelative]; actual_paths=[]`n$criticalLines")
}

function New-Package([string]$Profile,[string]$IssuerRole,[string]$Grantee,[string]$Action,[string]$DecisionClass,[string]$Issuer='owner-fixture'){
  $invalidators=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')
  $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='AUTH-REGRESSION-001';profile=$Profile;lifecycle='ACTIVE';owner='owner-fixture';issuer=$Issuer;issuerRole=$IssuerRole;grantee=$Grantee;bundle='PLAN_LOCAL';decisionClass=$DecisionClass;userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@($Action);exactPaths=@($objectRelative);objectIdentities=@([ordered]@{path=$objectRelative;identity=Get-Identity $objectPath});invalidatesOn=$invalidators;projectConfigIdentity=Get-Identity (Join-Path $control 'project.json')}
  if($IssuerRole-ceq'PROJECT_CONTROLLER'){
    $package['issuerControllerId']='controller-fixture';$package['issuerControllerEpoch']=1;$package['controllerControlIdentity']=Get-Identity (Join-Path $control 'controller.json');$package['invalidatesOn']+=@('CONTROLLER_EPOCH_CHANGE')
  }
  if($Profile-ceq'CRITICAL'-and$Action-ceq'REVIEW_EXECUTE'){
    $package['reviewIndependence']='INDEPENDENT';$package['candidateWriter']='writer-fixture';$package['materialContributors']=@();$package['invalidatesOn']+=@('CONTRIBUTOR_SET_CHANGE')
  }
  return $package
}

function Invoke-Check($Package,[string]$Actor,[string]$Action,[string[]]$Paths=@(),[string]$Continuation=''){
 Write-Json $packagePath $Package
 $repositoryId=if([int]$Package.schemaVersion-in@(2,4)){[string]$Package.repositoryId}else{'REPO_LOCAL'}
 $effectivePaths=if($Paths.Count){@($Paths)}else{@($objectRelative)}
 $parameters=@{PackagePath=$packagePath;ObservedActor=$Actor;ObservedTaskId='AUTH-REGRESSION-001';ObservedOwner='owner-fixture';ObservedAction=@($Action);ObservedPath=$effectivePaths;ObservedIdentity=@($effectivePaths|ForEach-Object{$path=Join-Path $temp $_;$_+'='+$(if(Test-Path -LiteralPath $path -PathType Leaf){Get-Identity $path}else{'NEW'})});ControllerControlPath='.ai-workspace/controller.json';ObservedRepositoryId=$repositoryId;ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Get-Identity (Join-Path $control 'project.json'));TaskPath=$taskRelative;ExpectedTaskIdentity=(Get-Identity $taskPath)}
 if([int]$Package.schemaVersion-eq2){$parameters.RootRepositoryBindingValidated=$true}
 if([int]$Package.schemaVersion-eq4){
  $parameters.ControlRoot=$temp
  $parameters.ObservedIdentity=@($effectivePaths|ForEach-Object{$path=Join-Path $targetRoot $_;$_+'='+$(if(Test-Path -LiteralPath $path -PathType Leaf){Get-Identity $path}else{'NEW'})})
 }
 if($Continuation){$parameters.ContinuationReceiptPath=$Continuation;$parameters.ExpectedContinuationReceiptIdentity=Get-Identity $Continuation}
 if($useKernel){
  $location=Get-Location;$directory=[Environment]::CurrentDirectory;$started=[DateTime]::UtcNow
  try{Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp;$response=& $authKernel.ExportedCommands['Invoke-AiwAuthorizationCheck'] @parameters}
  finally{Set-Location $location;[Environment]::CurrentDirectory=$directory}
  $observationRoot=if($env:AIW_TEST_RAW_DIRECTORY){$env:AIW_TEST_RAW_DIRECTORY}else{Join-Path ([IO.Path]::GetTempPath()) 'aiw-authorization-kernel-raw'}
  Write-AiwTestJson (Join-Path $observationRoot ('kernel-'+[guid]::NewGuid().ToString('N')+'.json')) @{kind='ACTUAL_BOUND_KERNEL_OBSERVATION';kernel=(Get-Identity (Join-Path $PSScriptRoot '../scripts/AuthorizationCheck.psm1'));parameters=$parameters;package=$Package;cwd=$temp;startedUtc=$started.ToString('o');endedUtc=[DateTime]::UtcNow.ToString('o');exitCode=$response.exitCode;output=@($response.output)}
  return [pscustomobject]@{Code=$response.exitCode;Text=(@($response.output)-join"`n")}
 }
 if(-not$Paths.Count-and-not$Continuation-and$Package.schemaVersion-ne4){
  $arguments=@('-NoProfile','-NonInteractive','-File',$checker,'-PackagePath',$packagePath,'-ObservedActor',$Actor,'-ObservedTaskId','AUTH-REGRESSION-001','-ObservedOwner','owner-fixture','-ObservedAction',$Action,'-ObservedPath',$objectRelative,'-ObservedIdentity',$parameters.ObservedIdentity[0],'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId',$repositoryId,'-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$parameters.ExpectedProjectConfigIdentity,'-TaskPath',$taskRelative,'-ExpectedTaskIdentity',$parameters.ExpectedTaskIdentity)
  if([int]$Package.schemaVersion-eq2){$arguments+='-RootRepositoryBindingValidated'}
  $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) $arguments -WorkingDirectory $temp -GroupId ('authorization-'+$Group)
  return [pscustomobject]@{Code=$run.Code;Text=$run.Text}
 }
 $wrapper=Join-Path $control 'scope-check-wrapper.ps1';$paramsPath=Join-Path $control 'scope-check-parameters.json'
 Write-Utf8 $wrapper 'param([string]$InputPath); $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable; $parameters=$call.parameters; & $call.checker @parameters; exit $LASTEXITCODE'
 Write-Json $paramsPath @{checker=$checker;parameters=$parameters}
 $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$wrapper,'-InputPath',$paramsPath) -WorkingDirectory $temp -GroupId ('authorization-'+$Group)
 return [pscustomobject]@{Code=$run.Code;Text=$run.Text}
}

function Invoke-TaskCheck(){
  $arguments=@('-NoProfile','-NonInteractive','-File',$taskChecker,'-TaskPath',$taskPath)
  $output=@(Invoke-AuthNative @arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
  return [pscustomobject]@{Code=$code;Text=($output-join"`n")}
}

function Invoke-FocusedBoundaries {
  param([switch]$EvidenceOnly)
  # The same private cases are selected alone or once by ExecutionTarget.
  # All roots and watched sentinels below belong to this isolated fixture.
  $repoTop=$temp;$outerControl=$control # Git actions require the authority root itself to be the Git top.
  $taskPath=Join-Path $temp $taskRelative;$packagePath=Join-Path $control 'focused-package.json';$objectPath=Join-Path $temp $objectRelative
  foreach($name in @('project.json','controller.json','corrections.json','process-policy.json','BOOTSTRAP.md')){Write-Utf8 (Join-Path $control $name) ([IO.File]::ReadAllText((Join-Path $outerControl $name)))}
  Write-Task STANDARD IMPLEMENT -OwnerRoute;Write-Utf8 $objectPath 'control coordinate sentinel'
  $authKernel=@(Import-Module (Join-Path $fixtureVersion 'scripts/AuthorizationCheck.psm1') -Force -PassThru)[0]
  $boundaryKernel=@(Import-Module (Join-Path $fixtureVersion 'scripts/ProcessRequirementBoundary.psm1') -PassThru)[0]
  $evidenceKernel=@(Import-Module (Join-Path $fixtureVersion 'scripts/ResultEvidence.psm1') -PassThru)[0]
  $targetKernel=@(Import-Module (Join-Path $fixtureVersion 'scripts/ExecutionTargetContext.psm1') -PassThru)[0]
  function Focus-Git([string[]]$Arguments,[string]$Root=$targetRoot){
    $run=Invoke-AiwTestProcess (Get-Command git -CommandType Application).Source (@('-C',$Root)+$Arguments) -WorkingDirectory $Root -GroupId 'focused-isolated-git'
    if($run.Code-ne0){throw ('FOCUSED_GIT|'+$run.Text)};return $run.Text.Trim()
  }
  # Public Git uses its lawful authority root; direct guards below cover nested coordinates.
  Write-Utf8 (Join-Path $repoTop 'pages/[id].tsx') 'original bracket candidate'
  Write-Utf8 (Join-Path $repoTop 'pages/i.tsx') 'tracked neighbor'
  $null=Focus-Git @('add','--',':(top,literal)pages/[id].tsx',':(top,literal)pages/i.tsx') $repoTop
  $null=Focus-Git @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','Focused literal baseline') $repoTop
  $targetRoot=Join-Path $repoTop 'focused-target';$branch='focused-boundaries'
  $null=Focus-Git @('worktree','add','-q','-b',$branch,$targetRoot,'HEAD') $repoTop
  $head=(Focus-Git @('rev-parse','HEAD')).ToUpperInvariant();$state=[pscustomobject]@{branch=$branch;head=$head}
  $selection=Join-Path $control 'runtime/AUTH-REGRESSION-001/owner-fixture/selection.txt';Write-Utf8 $selection 'Isolated worktree selection. No real repository or host decision.'
  $descriptor=Join-Path $control 'runtime/AUTH-REGRESSION-001/owner-fixture/target.json'
  Write-Json $descriptor ([ordered]@{schemaVersion=1;kind='EXECUTION_TARGET';projectId='authorization-receipt-fixture';taskId='AUTH-REGRESSION-001';controlRoot=$temp;targetKind='GIT_WORKTREE';targetRoot=$targetRoot;gitBinding=[ordered]@{commonGitDir=[IO.Path]::GetFullPath((Focus-Git @('rev-parse','--path-format=absolute','--git-common-dir') $temp));worktreeGitDir=[IO.Path]::GetFullPath((Focus-Git @('rev-parse','--absolute-git-dir')));gitTop=$targetRoot;branch=$branch;baselineCommit=$head};selectionDecisionRef=[ordered]@{path=$selection;identity=Get-Identity $selection};hostWorktreeRef=$null})
  $targetRef=[pscustomobject]@{path=$descriptor;identity=Get-Identity $descriptor}
  [IO.File]::AppendAllText($taskPath,('- Execution target: '+$descriptor+'#'+$targetRef.identity+"`n"),$utf8)
  $objectPath=Join-Path $targetRoot $objectRelative;Write-Utf8 $objectPath 'return (10 / $InputValue)'
  $companion='src/frozen.txt';Write-Utf8 (Join-Path $targetRoot $companion) 'Frozen companion';$companionIdentity=Get-Identity (Join-Path $targetRoot $companion)
  foreach($p in @('private/original-f.txt','private/original-p.txt','private/current-f.txt','private/current-p.txt')){Write-Utf8 (Join-Path $targetRoot $p) 'isolated protection sentinel'}
  $requirementsPath=Join-Path $control 'reports/focused-requirements.md';Write-Utf8 $requirementsPath 'Positive input two returns five, zero must return zero. Preserve frozen companion and reject restricted IO before access.'
  $requirements=[pscustomobject][ordered]@{path=$requirementsPath;identity=Get-Identity $requirementsPath}
  $decisionPath=Join-Path $control 'reports/focused-user-decision.txt';Write-Utf8 $decisionPath 'Simulated exact fixture decision'
  $decision=[ordered]@{path=$decisionPath;identity=Get-Identity $decisionPath}
  $probeScript=Join-Path $control 'reports/focused-command.ps1';Write-Utf8 $probeScript 'param([string]$Candidate,[double]$InputValue); $ErrorActionPreference="Stop"; try{$value=& ([scriptblock]::Create([IO.File]::ReadAllText($Candidate)));if([double]::IsInfinity($value)-or[double]::IsNaN($value)){exit 1};Write-Output $value;exit 0}catch{Write-Output $_.Exception.Message;exit 1}'
  function Focus-Candidates([string[]]$Paths){@($Paths|ForEach-Object{[ordered]@{path=$_;identity=Get-Identity (Join-Path $targetRoot $_)}})}
  function Focus-Package([string]$Action,[string]$Actor='writer-fixture',[string]$DecisionClass='ROUTINE_LOCAL'){
    $pkg=New-Package STANDARD TASK_OWNER $Actor $Action $DecisionClass
    $pkg.schemaVersion=4;$pkg['repositoryId']='PROJECT';$pkg['controlRoot']=$temp;$pkg['executionTargetRef']=$targetRef;$pkg['expectedTargetState']=$state;$pkg.invalidatesOn+=@('REPOSITORY_CHANGE')
    return $pkg
  }
  function Focus-Grant($Pkg,[string]$Name){$p=Join-Path $control ($Name+'-package.json');Write-Json $p $Pkg;return [pscustomobject]@{Path=$p;Package=$Pkg}}
  function Focus-Parameters($Grant,[string]$Action,[string]$Continuation=''){
    $paths=@(if($Action-ceq'REVIEW_ROUTE'){$objectRelative;$companion}else{$Grant.Package.exactPaths})
    $parameters=@{PackagePath=$Grant.Path;ObservedActor=$Grant.Package.grantee;ObservedTaskId='AUTH-REGRESSION-001';ObservedOwner='owner-fixture';ObservedAction=@($Action);ObservedPath=$paths;ObservedIdentity=@($paths|ForEach-Object{$_+'='+(Get-Identity (Join-Path $targetRoot $_))});ControllerControlPath='.ai-workspace/controller.json';ObservedRepositoryId='PROJECT';ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Get-Identity (Join-Path $control 'project.json'));TaskPath=$taskRelative;ExpectedTaskIdentity=(Get-Identity $taskPath);ControlRoot=$temp}
    if($Continuation){$parameters.ContinuationReceiptPath=$Continuation;$parameters.ExpectedContinuationReceiptIdentity=Get-Identity $Continuation}
    return $parameters
  }
  function Focus-Check($Parameters){
    $loc=Get-Location;$cwd=[Environment]::CurrentDirectory
    try{Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp;$r=& $authKernel.ExportedCommands['Invoke-AiwAuthorizationCheck'] @Parameters}
    finally{Set-Location $loc;[Environment]::CurrentDirectory=$cwd}
    return [pscustomobject]@{Code=$r.exitCode;Text=(@($r.output)-join"`n")}
  }
  function Focus-Process($Value,[string]$Name){
    $p=Join-Path $control ($Name+'.json');Write-Json $p $Value
    $loc=Get-Location;$cwd=[Environment]::CurrentDirectory
    try{Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp;$r=& $boundaryKernel.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $p -AsJson}
    finally{Set-Location $loc;[Environment]::CurrentDirectory=$cwd}
    $text=@($r.output)-join"`n";$v=$text|ConvertFrom-Json -Depth 100
    Write-Json (Join-Path $control ($Name+'-result.json')) @{exitCode=$r.exitCode;value=$v}
    if($r.exitCode-ne0-or$v.status-cne'PASS'){throw ('FOCUSED_PROCESS|'+$Name+'|'+$text)}
    return $v
  }
  function Focus-Enter($Grant,[string]$Action,[string]$Name,[string]$Continuation='',$Refs=@()){
    $d=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $d.schemaVersion=5;$d|Add-Member ruleLoad ([pscustomobject]@{mode='FULL'}) -Force;$d|Add-Member executionTargetRef $targetRef -Force
    $d.projectRoot=$temp;$d.taskPath=$taskPath;$d.expectedTaskIdentity=Get-Identity $taskPath;$d.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');$d.expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json')
    $d.observedActor=$Grant.Package.grantee;$d.authorizationPackagePath=$Grant.Path;$d.expectedAuthorizationIdentity=Get-Identity $Grant.Path;$d.userDecision=$Grant.Package.userConfirmation
    $d.exactPaths=@(if($Action-ceq'REVIEW_ROUTE'){$objectRelative;$companion}else{$Grant.Package.exactPaths});$d.forbiddenPaths=@('private/original-f.txt');$d.protectedPaths=@('private/original-p.txt')
    $d.intentEnvelope.objective='Bounded current protection and literal commit regression with actual isolated protocol observations'
    $d.intentEnvelope.requestedActionKind=$Action;$d.intentEnvelope.requestedResultKind=switch($Action){TEST_RUN{'TEST_RESULT'} REVIEW_EXECUTE{'REVIEW_VERDICT'} REVIEW_ROUTE{'HANDOFF'} default{'IMPLEMENTATION_RESULT'}}
    $d.intentEnvelope.pathHints=@($d.exactPaths);$d.intentEnvelope.semanticHints=@();$d.intentEnvelope.mutationHints=@()
    if($Continuation){$d|Add-Member continuationReceiptPath $Continuation -Force;$d|Add-Member expectedContinuationReceiptIdentity (Get-Identity $Continuation) -Force}
    $r=Focus-Process $d ($Name+'-discover');$rp=Join-Path $control ($Name+'-compact.json');Write-Json $rp $r.compactReceipt
    $b=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$rp;expectedDiscoverReceiptIdentity=Get-Identity $rp;preparationReceipts=@($r.compactReceipt.selectedObligations.preparationRequirements|Select-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($Refs)}
    $null=Focus-Process $b ($Name+'-admit')
    return [pscustomobject]@{Name=$Name;Input=$d;Boundary=$b;Receipt=$r.compactReceipt}
  }
  function Focus-Command([string]$Name,[double]$Number){
    $argv=@('-NoProfile','-NonInteractive','-File',$probeScript,'-Candidate',$objectPath,'-InputValue',$Number.ToString([Globalization.CultureInfo]::InvariantCulture))
    $r=Invoke-AiwTestProcess ([Environment]::ProcessPath) $argv -WorkingDirectory $targetRoot -GroupId 'focused-actual-candidate-command'
    $p=Join-Path $control ($Name+'-stdout.txt');Write-Utf8 $p $r.Text;$c=Join-Path $control ($Name+'-command.json');Write-Json $c @{command=('pwsh '+($argv-join' '));exitCode=$r.Code;output=@{path=$p;identity=Get-Identity $p}}
    return [pscustomobject]@{Code=$r.Code;Ref=@{path=$c;identity=Get-Identity $c}}
  }
  function Focus-Record([string]$Name,[string]$Kind,[string]$Outcome,[string[]]$Paths,$Grant=$null,$Command=$null,$Flat=$null,$Prerequisites=@()){
    $actor=switch($Kind){REVIEW_VERDICT{'reviewer-fixture'} RESULT_ACCEPTANCE{'owner-fixture'} default{'writer-fixture'}}
    $refs=@($requirements)+@($Prerequisites|ForEach-Object{[ordered]@{path=$_.path;identity=$_.identity}});if($null-ne$Command){$refs+=@($Command.Ref)};if($null-ne$Flat){$refs+=@($Flat)}
    # A COMMAND check has one untyped command ref; the outer record retains
    # requirements, command, prerequisite and unique flat-verdict references.
    # The outer @() is essential: $() would unwrap a single locator.
    $checkRefs=@(if($null-ne$Command){$Command.Ref}else{$refs})
    $checks=@([ordered]@{id=$Name;method=$(if($null-ne$Command){'COMMAND'}else{'MODEL_JUDGMENT'});outcome=$(if($Outcome-cin@('FAIL','CHANGES_REQUESTED')){'FAIL'}else{'PASS'});reason='Actual isolated candidate observation. Actor judgment and host delivery are fixture simulations.';evidenceLocators=@($checkRefs)})
    $record=[ordered]@{schemaVersion=2;taskId='AUTH-REGRESSION-001';actor=$actor;candidateObjects=@(Focus-Candidates $Paths);requirementsRef=$requirements;outcome=$Outcome;checks=$checks;evidenceLocators=$refs;executionTargetRef=$targetRef;candidateTargetState=$state}
    if($null-ne$Grant){$record.authorizationRef=@{path=$Grant.Path;identity=Get-Identity $Grant.Path}}
    $p=Join-Path $control ($(if($Kind-ceq'RESULT_ACCEPTANCE'){'reports/'}else{''})+$Name+'-typed.json');Write-Json $p $record;return @{kind=$Kind;path=$p;identity=Get-Identity $p}
  }
  function Focus-Finish($Step,[string]$Name,$Refs=@(),[string]$Recipient='',$Review=$null){
    $b=$Step.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$b.mode='FINALIZE_OUTPUT';$b.resultReceipts=@($Step.Receipt.selectedObligations.resultRequirements|Select-Object -Unique)+@($Step.Input.exactPaths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+(Get-Identity (Join-Path $targetRoot $_))});$b.evidenceRefs=@($Refs)
    if($Recipient){
      $h=Join-Path $control ($Name+'-mock-host.json');Write-Json $h @{isError=$false;content=@(@{type='text';text=('{"threadId":"'+$Recipient+'"}')})}
      $delivery=[ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient=$Recipient;observedRecipient=$Recipient;outcome='SUCCESS';evidence=($h+'#'+(Get-Identity $h))}
      if($null-ne$Review){$delivery.reviewPackageRef=[ordered]@{path=$Review.Path;identity=Get-Identity $Review.Path}}
      $b|Add-Member deliveryContext ([pscustomobject]$delivery)
    }
    $r=Focus-Process $b $Name;$rp=Join-Path $control ($Name+'-actual-result.json');Write-Json $rp $r
    $c='';if($null-ne$r.PSObject.Properties['continuationReceipt']){$c=Join-Path $control ($Name+'-continuation.json');Write-Json $c $r.continuationReceipt}
    return [pscustomobject]@{InputPath=(Join-Path $control ($Name+'.json'));ResultPath=$rp;Result=$r;Continuation=$c}
  }
  function Focus-Factory($Parent,[string]$Phase,[int]$Cycle,$Final,$Finding=$null){
    $b=[ordered]@{parentPackagePath=$Parent.Path;parentPackageIdentity=Get-Identity $Parent.Path;phase=$Phase;cycle=$Cycle;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=$Final.InputPath;repairFinalizeInputIdentity=Get-Identity $Final.InputPath;repairFinalizeResultPath=$Final.ResultPath;repairFinalizeResultIdentity=Get-Identity $Final.ResultPath}
    if($null-ne$Finding){$b.verdictPath=$Finding.Flat.path;$b.verdictIdentity=$Finding.Flat.identity;$b.verdictFinalizeInputPath=$Finding.Final.InputPath;$b.verdictFinalizeInputIdentity=Get-Identity $Finding.Final.InputPath;$b.verdictFinalizeResultPath=$Finding.Final.ResultPath;$b.verdictFinalizeResultIdentity=Get-Identity $Finding.Final.ResultPath}
    if($Phase-ceq'REPAIR'){foreach($n in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){$b[$n]='NOT_APPLICABLE'}}
    $name='focused-'+$Phase;$p=Join-Path $control ($name+'-factory.json');Write-Json $p @{operation='REPAIR_REVIEW';repositoryRoot=$targetRoot;controlRoot=$temp;taskPath=$taskRelative;binding=$b}
    $r=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureVersion 'scripts/resolve-workflow-route.ps1'),'-InputPath',$p,'-AsJson') -WorkingDirectory $temp -GroupId 'focused-actual-factory'
    if($r.Code-ne0){throw ('FOCUSED_FACTORY|'+$r.Text)};$v=$r.Text|ConvertFrom-Json -Depth 100;if($v.status-cne'PREPARED'){throw ('FOCUSED_FACTORY_STATUS|'+$v.status)};return Focus-Grant $v.package $name
  }
  function Focus-BoundaryCheck([string]$InputPath){
    $loc=Get-Location;$cwd=[Environment]::CurrentDirectory
    try{Set-Location -LiteralPath $temp;[Environment]::CurrentDirectory=$temp;$response=& $boundaryKernel.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] -InputPath $InputPath -AsJson}
    finally{Set-Location $loc;[Environment]::CurrentDirectory=$cwd}
    return [pscustomobject]@{Code=$response.exitCode;Text=(@($response.output)-join"`n")}
  }
  # Specific results complement a named static access-order review. A rejection
  # here proves its reason, not that every filesystem operation was observed.
  function Focus-Observe([scriptblock]$Call,[string]$Name,[string]$Expected='PASS'){
    $caught='';$value=$null;try{$value=& $Call}catch{$caught=$_.Exception.Message}
    $code=if($null-ne$value-and$null-ne$value.PSObject.Properties['Code']){$value.Code}elseif($caught){1}else{0}
    $text=if($caught){$caught}elseif($null-ne$value-and$null-ne$value.PSObject.Properties['Text']){$value.Text}else{''}
    Write-Json (Join-Path $control ($Name+'-observation.json')) @{name=$Name;code=$code;text=$text;expected=$Expected}
    if($Expected-ceq'PASS'){Assert-True ($code-eq0) ($Name+'-legal-baseline')|ForEach-Object{Write-Host $_}}
    else{Assert-True ($code-ne0-and$text-cmatch$Expected) ($Name+'-specific-rejection')|ForEach-Object{Write-Host $_}}
    return $value
  }
  function Focus-ProtectedCheck($Parameters,[string]$Name,[string[]]$Forbidden=@(),[string[]]$Protected=@()){
    $bound=$Parameters.Clone();$bound.ForbiddenPaths=@($Forbidden);$bound.ProtectedPaths=@($Protected)
    $null=Focus-Observe {Focus-Check $bound} $Name 'EVIDENCE_PATH_FORBIDDEN|EXECUTION_TARGET_PROTECTED_PATH'
  }

  if($EvidenceOnly){
    # Establish an actual current target independently of IR02 postimages.
    $baselinePackage=[pscustomobject](Focus-Package SOURCE_WRITE)
    $directTarget=Resolve-AiwPackageExecutionTarget $temp $baselinePackage $taskRelative
  }else{
  # IR02 first: one real changed HEAD, a literal bracket candidate and dirty
  # tracked neighbor. Keep the same live worktree for all subsequent cases.
  Write-Task STANDARD GIT -OwnerRoute;[IO.File]::AppendAllText($taskPath,('- Execution target: '+$descriptor+'#'+$targetRef.identity+"`n"),$utf8)
  $literal='pages/[id].tsx';$neighbor='pages/i.tsx';$literalPath=Join-Path $targetRoot $literal
  Write-Utf8 $literalPath 'literal candidate changed';$git=Focus-Package GIT_COMMIT owner-fixture;$git.delegatedGitCloser=$true;$git.exactPaths=@($literal);$git.objectIdentities=@(Focus-Candidates @($literal));$gg=Focus-Grant $git 'focused-literal-commit'
  $step=Focus-Enter $gg GIT_COMMIT 'focused-literal';$null=Focus-Git @('add','--',(':(top,literal)'+$literal));$null=Focus-Git @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','Exact bracket candidate');Write-Utf8 (Join-Path $targetRoot $neighbor) 'unrelated tracked dirty neighbor'
  $pkg=$gg.Package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $directTarget=Focus-Observe {Resolve-AiwPackageExecutionTarget $temp $pkg $taskRelative -AllowCommitPostimage} 'focused-literal-resolve-with-dirty-neighbor'
  $final=Focus-Observe {Focus-Finish $step 'focused-literal-final'} 'focused-literal-public-finalize-with-dirty-neighbor'
  Assert-True ($final.Result.postTargetState.head-cne$state.head) 'focused-public-finalize-actually-advanced-head'
  $null=Focus-Observe {Resolve-AiwPackageExecutionTarget $temp $pkg $taskRelative @($literal) @() -AllowCommitPostimage} 'focused-literal-resolve-restricted' 'EXECUTION_TARGET_PROTECTED_PATH'
  # This copy is a negative input only, never a successful source receipt.
  $badReceipt=$step.Receipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badReceipt.binding.forbiddenScope=@($badReceipt.binding.forbiddenScope)+@($literal);$bp=Join-Path $control 'focused-literal-restricted-receipt.json';Write-Json $bp $badReceipt
  $bb=$step.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bb.mode='FINALIZE_OUTPUT';$bb.discoverReceiptPath=$bp;$bb.expectedDiscoverReceiptIdentity=Get-Identity $bp;$bb.resultReceipts=@($step.Receipt.selectedObligations.resultRequirements|Select-Object -Unique)+@('OBJECT_POSTIMAGE|'+$literal+'|'+(Get-Identity $literalPath));$bip=Join-Path $control 'focused-literal-restricted-boundary.json';Write-Json $bip $bb
  $null=Focus-Observe {Focus-BoundaryCheck $bip} 'focused-literal-public-finalize-restricted' 'EXECUTION_TARGET_PROTECTED_PATH'
  Write-Utf8 $literalPath 'candidate itself drifted'
  $null=Focus-Observe {Resolve-AiwPackageExecutionTarget $temp $pkg $taskRelative -AllowCommitPostimage} 'focused-literal-resolve-own-drift' '^EXECUTION_TARGET_COMMIT_TREE$'
  $null=Focus-Observe {Focus-BoundaryCheck $final.InputPath} 'focused-literal-public-finalize-own-drift' 'EXECUTION_TARGET_COMMIT_TREE'
  $state=$final.Result.postTargetState
  Write-Task STANDARD IMPLEMENT -OwnerRoute;[IO.File]::AppendAllText($taskPath,('- Execution target: '+$descriptor+'#'+$targetRef.identity+"`n"),$utf8)

  }
  # IR01 direct guards: denied missing leaves must report denial rather than
  # missing. These results and mappings do not claim dynamic zero IO.
  $missing=Join-Path $control 'reports/focused-guard-missing.txt';$missingRef=[pscustomobject]@{path=$missing;identity=('1|'+('0'*64))}
  $plainContext=New-AiwEvidenceContext $temp $targetRoot
  $null=Focus-Observe {Read-AiwEvidenceReference $plainContext $requirements} 'focused-evidence-existing-reference'
  $null=Focus-Observe {Read-AiwEvidenceReference $plainContext $missingRef} 'focused-evidence-unrestricted-missing' '^EVIDENCE_OBJECT_MISSING$'
  foreach($ref in @($requirements,$missingRef)){
    $deniedContext=New-AiwEvidenceContext $temp $targetRoot '' @($ref.path)
    $null=Focus-Observe {Read-AiwEvidenceReference $deniedContext $ref} ('focused-evidence-forbidden-'+[IO.Path]::GetFileName($ref.path)) '^EVIDENCE_PATH_FORBIDDEN$'
  }
  # Synthetic direct-guard context keeps control and main Git top distinct;
  # this is mapping equivalence coverage, not a successful nested Git action.
  $mappingControl=Join-Path $repoTop 'pages'
  $mappingTarget=[pscustomobject]@{targetKind='GIT_WORKTREE';controlRoot=$mappingControl;executionRoot=$targetRoot}
  foreach($restriction in @($objectRelative,$objectPath,(Join-Path $mappingControl $objectRelative),(Join-Path $repoTop $objectRelative))){
    $null=Focus-Observe {Resolve-AiwExecutionTargetCandidatePath $mappingTarget $objectRelative @($restriction)} ('focused-target-coordinate-'+[guid]::NewGuid().ToString('N')) '^EXECUTION_TARGET_PROTECTED_PATH$'
  }
  $candidateRef=[pscustomobject]@{path=$objectRelative;identity=Get-Identity $objectPath}
  $protectedContext=New-AiwEvidenceContext $temp $targetRoot '' @() @($objectRelative,$requirementsPath)
  $null=Focus-Observe {Read-AiwEvidenceReference $protectedContext $candidateRef -Candidate} 'focused-evidence-protected-candidate' '^EVIDENCE_PATH_FORBIDDEN$'
  $null=Focus-Observe {Read-AiwEvidenceReference $protectedContext $requirements} 'focused-evidence-protected-authority-is-lawful'
  foreach($relative in @($objectRelative,'private/guard-missing.txt')){
    $null=Focus-Observe {Resolve-AiwExecutionTargetCandidatePath $directTarget $relative @($relative)} ('focused-target-forbidden-'+[IO.Path]::GetFileName($relative)) '^EXECUTION_TARGET_PROTECTED_PATH$'
    $null=Focus-Observe {Resolve-AiwExecutionTargetCandidatePath $directTarget $relative @() @($relative)} ('focused-target-protected-'+[IO.Path]::GetFileName($relative)) '^EXECUTION_TARGET_PROTECTED_PATH$'
  }
  $unionContext=New-AiwEvidenceContext $temp $targetRoot '' @('private/original-f.txt','private/current-f.txt') @('private/original-p.txt','private/current-p.txt')
  foreach($relative in @('private/original-f.txt','private/current-f.txt','private/original-p.txt','private/current-p.txt')){
    $ref=[pscustomobject]@{path=$relative;identity=Get-Identity (Join-Path $targetRoot $relative)}
    $null=Focus-Observe {Read-AiwEvidenceReference $unionContext $ref -Candidate} ('focused-explicit-scope-guard-'+[IO.Path]::GetFileName($relative)) '^EVIDENCE_PATH_FORBIDDEN$'
  }
  $accept=Focus-Package RESULT_ACCEPT owner-fixture PRODUCT_RESULT;$accept.userConfirmation='SIMULATED_ACCEPT'
  $accept['acceptanceBinding']=[ordered]@{candidateObjects=@(Focus-Candidates @($objectRelative));requirementsRef=$requirements;prerequisiteEvidenceRefs=@();reservedUserDecisionRefs=@($decision)}
  $ag=Focus-Grant $accept 'focused-accept';$ap=Focus-Parameters $ag RESULT_ACCEPT
  $null=Focus-Observe {Focus-Check $ap} 'focused-accept'
  foreach($restriction in @($objectRelative,$objectPath,(Join-Path $temp $objectRelative),(Join-Path $repoTop $objectRelative))){Focus-ProtectedCheck $ap ('focused-accept-coordinate-'+[guid]::NewGuid().ToString('N')) -Forbidden @($restriction)}
  Focus-ProtectedCheck $ap 'focused-accept-protected' -Protected @($objectRelative)
  foreach($ref in @($requirements,$decision)){Focus-ProtectedCheck $ap ('focused-accept-reference-'+[IO.Path]::GetFileName($ref.path)) -Forbidden @($ref.path)}
  # Ordinary schema1 has different roots. Temporarily remove only the explicit
  # target route from its task and then restore those identical task bytes.
  $targetTask=[IO.File]::ReadAllBytes($taskPath);Write-Task STANDARD IMPLEMENT -OwnerRoute
  try{
    $plain=New-Package STANDARD TASK_OWNER owner-fixture RESULT_ACCEPT PRODUCT_RESULT;$plain.objectIdentities[0].identity=Get-Identity (Join-Path $temp $objectRelative);$plain.userConfirmation='SIMULATED_ACCEPT';$plain['acceptanceBinding']=[ordered]@{candidateObjects=@($plain.objectIdentities);requirementsRef=$requirements;prerequisiteEvidenceRefs=@();reservedUserDecisionRefs=@($decision)}
    $pg=Focus-Grant $plain 'focused-normal';$pp=Focus-Parameters $pg RESULT_ACCEPT;$pp.Remove('ControlRoot');$pp.ObservedRepositoryId='REPO_LOCAL';$pp.ObservedIdentity=@($objectRelative+'='+(Get-Identity (Join-Path $temp $objectRelative)))
    $null=Focus-Observe {Focus-Check $pp} 'focused-normal-candidate'
    Focus-ProtectedCheck $pp 'focused-normal-protected' -Protected @($objectRelative)
    $evidenceProtected=$pp.Clone();$evidenceProtected.ProtectedPaths=@($requirementsPath);$null=Focus-Observe {Focus-Check $evidenceProtected} 'focused-normal-protected-authority'
  }finally{[IO.File]::WriteAllBytes($taskPath,$targetTask)}

  # One real producer chain supplies route and repair/rereview read consumers.
  # The existing full-chain group retains final-review/delivery coverage.
  $pkg=Focus-Package SOURCE_WRITE;$pkg.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$pkg['continuationPlan']=@($pkg.actions);$pkg['selfCheckRepairLimit']=1;$pkg.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT');$pkg['repairReviewPlan']=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@();reviewScope=@(Focus-Candidates @($objectRelative,$companion))}
  $parent=Focus-Grant $pkg 'focused-parent';$sourceStep=Focus-Enter $parent SOURCE_WRITE 'focused-source';Write-Utf8 $objectPath 'return (10 / $InputValue) # actual initial write';$sf=Focus-Finish $sourceStep 'focused-source-final'
  $testStep=Focus-Enter $parent TEST_RUN 'focused-test' $sf.Continuation;$command=Focus-Command 'focused-positive' 2;Assert-True ($command.Code-eq0) 'focused-actual-positive-command';$self=Focus-Record focused-self SELF_CHECK PASS @($objectRelative) -Command $command;$tf=Focus-Finish $testStep 'focused-test-final' @($self) -Recipient owner-fixture
  $rp=Focus-Parameters $parent REVIEW_ROUTE $tf.Continuation;$null=Focus-Observe {Focus-Check $rp} 'focused-route'
  Focus-ProtectedCheck $rp 'focused-route-current-forbidden' -Forbidden @($objectRelative)
  Focus-ProtectedCheck $rp 'focused-route-current-protected' -Protected @($objectRelative)
  Focus-ProtectedCheck $rp 'focused-route-frozen-forbidden' -Forbidden @($companion)
  Focus-ProtectedCheck $rp 'focused-route-self-requirement-forbidden' -Forbidden @($requirementsPath)
  Focus-ProtectedCheck $rp 'focused-original-continuation-forbidden' -Forbidden @($tf.Continuation)
  $cp=Get-Content -LiteralPath $tf.Continuation -Raw|ConvertFrom-Json -Depth 100
  Focus-ProtectedCheck $rp 'focused-original-source-record-forbidden' -Forbidden @($cp.sourceDiscoverReceiptPath)
  foreach($field in @('sourceDiscoverReceiptIdentity','completedStepIndex')){
    $bad=$cp|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;if($field-ceq'completedStepIndex'){$bad.$field=99}else{$bad.$field='1|'+('0'*64)}
    $p=Join-Path $control ('focused-tampered-'+$field+'.json');Write-Json $p $bad;$params=$rp.Clone();$params.ContinuationReceiptPath=$p;$params.ExpectedContinuationReceiptIdentity=Get-Identity $p
    $expected=if($field-ceq'completedStepIndex'){'CONTINUATION_RECEIPT_STEP_DRIFT'}else{'CONTINUATION_SOURCE_RECEIPT_DRIFT'}
    $null=Focus-Observe {Focus-Check $params} ('focused-invalid-'+$field) $expected
  }
  $union=$rp.Clone();$union.ForbiddenPaths=@('private/current-f.txt');$union.ProtectedPaths=@('private/current-p.txt');$null=Focus-Observe {Focus-Check $union} 'focused-lawful-original-current-scope-chain'
  $review=Focus-Factory $parent INITIAL_REVIEW 0 $tf
  $reviewDeliveryParams=Focus-Parameters $review REVIEW_EXECUTE
  $null=Focus-Observe {Focus-Check $reviewDeliveryParams} 'focused-initial-producer-delivery'
  $producerHost=Join-Path $control 'focused-test-final-mock-host.json'
  Focus-ProtectedCheck $reviewDeliveryParams 'focused-initial-current-producer-host' -Forbidden @($producerHost)
  $protectedHost=$reviewDeliveryParams.Clone();$protectedHost.ProtectedPaths=@($producerHost)
  $null=Focus-Observe {Focus-Check $protectedHost} 'focused-initial-protected-host-authority'
  $reviewStep=Focus-Enter $review REVIEW_EXECUTE 'focused-review';$counterexample=Focus-Command 'focused-zero-counterexample' 0;Assert-True ($counterexample.Code-ne0) 'focused-actual-independent-counterexample'
  $flatPath=Join-Path $control 'focused-flat.json';Write-Json $flatPath @{taskId='AUTH-REGRESSION-001';owner='owner-fixture';reviewer='reviewer-fixture';writer='writer-fixture';cycle=0;verdict='CHANGES_REQUESTED';exactPaths=@($review.Package.exactPaths);objectIdentities=@($review.Package.objectIdentities);findingPaths=@($objectRelative);scopeChanged=$false;decisionChanged=$false};$flat=@{path=$flatPath;identity=Get-Identity $flatPath}
  $verdict=Focus-Record focused-verdict REVIEW_VERDICT CHANGES_REQUESTED @($objectRelative,$companion) $review $counterexample $flat;$vf=Focus-Finish $reviewStep 'focused-review-final' @($verdict) writer-fixture
  $finding=[pscustomobject]@{Flat=$flat;Final=$vf};$repair=Focus-Factory $parent REPAIR 1 $tf $finding
  $repairParams=Focus-Parameters $repair SOURCE_WRITE;$null=Focus-Observe {Focus-Check $repairParams} 'focused-real-repair'
  $reviewHost=Join-Path $control 'focused-review-final-mock-host.json'
  $rawVerdict=Get-Content -LiteralPath $verdict.path -Raw|ConvertFrom-Json -Depth 100
  Assert-True (@($rawVerdict.evidenceLocators|Where-Object path -CEQ $reviewHost).Count-eq0) 'focused-review-host-is-only-delivery-reference'
  Focus-ProtectedCheck $repairParams 'focused-repair-current-review-host' -Forbidden @($reviewHost)
  Focus-ProtectedCheck $repairParams 'focused-repair-current-forbidden' -Forbidden @($objectRelative)
  $repairStep=Focus-Enter $repair SOURCE_WRITE 'focused-repair';Write-Utf8 $objectPath 'if($InputValue-eq0){return 0};return (10 / $InputValue)';$rf=Focus-Finish $repairStep 'focused-repair-final'
  $retest=Focus-Enter $repair TEST_RUN 'focused-retest' $rf.Continuation;$fixed=Focus-Command 'focused-zero-fixed' 0;Assert-True ($fixed.Code-eq0) 'focused-actual-repair-corrects-zero';$fixedSelf=Focus-Record focused-fixed-self SELF_CHECK PASS @($objectRelative) -Command $fixed;$rtf=Focus-Finish $retest 'focused-retest-final' @($fixedSelf) -Recipient owner-fixture
  $rereview=Focus-Factory $parent REREVIEW 1 $rtf $finding;$rrp=Focus-Parameters $rereview REVIEW_EXECUTE
  $null=Focus-Observe {Focus-Check $rrp} 'focused-real-rereview'
  Focus-ProtectedCheck $rrp 'focused-rereview-current-review-host' -Forbidden @($reviewHost)
  Focus-ProtectedCheck $rrp 'focused-rereview-current-producer-host' -Forbidden @((Join-Path $control 'focused-retest-final-mock-host.json'))
  Focus-ProtectedCheck $rrp 'focused-rereview-current-protected' -Protected @($objectRelative)
  Focus-ProtectedCheck $rrp 'focused-rereview-current-requirements' -Forbidden @($requirementsPath)

  Write-Task STANDARD GIT -OwnerRoute;[IO.File]::AppendAllText($taskPath,('- Execution target: '+$descriptor+'#'+$targetRef.identity+"`n"),$utf8)
  $decisionText='SIMULATED_EXACT_PUSH';[IO.File]::AppendAllText($taskPath,("Push authorization: repositoryId=PROJECT; remote=origin; branch=$branch; decision=$decisionText`n"),$utf8)
  $remote=Join-Path $repoTop 'focused-remote.git';$null=Focus-Git @('init','-q','--bare',$remote) $repoTop;$null=Focus-Git @('remote','add','origin',$remote);$null=Focus-Git @('push','-q','origin',($state.head+':refs/heads/'+$branch))
  $remoteCommit=$state.head;$null=Focus-Git @('add','--',(':(top,literal)'+$objectRelative));$null=Focus-Git @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','Focused accepted candidate');$state=[pscustomobject]@{branch=$branch;head=(Focus-Git @('rev-parse','HEAD')).ToUpperInvariant()}
  $accept=Focus-Package RESULT_ACCEPT owner-fixture PRODUCT_RESULT;$accept.userConfirmation='SIMULATED_ACCEPT';$ag=Focus-Grant $accept 'focused-push-original-accept';$ar=Focus-Record focused-push-accept RESULT_ACCEPTANCE ACCEPTED @($objectRelative) $ag
  $raw=Get-Content -LiteralPath $ar.path -Raw|ConvertFrom-Json -Depth 100;$raw|Add-Member acceptedCommit $state.head;Write-Json $ar.path $raw;$ar.identity=Get-Identity $ar.path
  $push=Focus-Package PUSH owner-fixture EXTERNAL_ACTION;$push.userConfirmation=$decisionText;$push.delegatedGitCloser=$true;$url=Focus-Git @('remote','get-url','--push','origin');$bytes=$utf8.GetBytes($url)
  $push['gitPushBinding']=[ordered]@{remote='origin';branch=$branch;remoteUrlIdentity=($bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)));expectedRemoteCommit=$remoteCommit;localCommit=$state.head;acceptanceEvidencePath=[IO.Path]::GetRelativePath($temp,$ar.path).Replace('\','/');acceptanceEvidenceIdentity=$ar.identity}
  $pushGrant=Focus-Grant $push 'focused-push';$pushParams=Focus-Parameters $pushGrant PUSH
  $null=Focus-Observe {Focus-Check $pushParams} 'focused-push'
  Focus-ProtectedCheck $pushParams 'focused-push-current-forbidden' -Forbidden @($objectRelative)
  foreach($ref in @($ar,$requirements)){Focus-ProtectedCheck $pushParams ('focused-push-reference-'+[IO.Path]::GetFileName($ref.path)) -Forbidden @($ref.path)}
  if($EvidenceOnly){Write-Output ('PARTIAL|FOCUSED_EVIDENCE|IR01=ACTUAL_SPECIFIC_RESULTS|IR02=EP176_REUSED_NOT_RUN|IR03=SEPARATE_STATIC_REVIEW|actor-host=SIMULATED|qualification=NOT_RUN|fixture='+$temp)}else{
  Write-Output ('PARTIAL|FOCUSED_BOUNDARIES|specific-guard-checker-and-changed-head-Git=ACTUAL|access-order=SEPARATE_STATIC_REVIEW|actor-host=SIMULATED|full-review-chain=PRIOR_SEPARATE_GROUP|qualification=NOT_RUN|fixture='+$temp)
  }
}

New-Item -ItemType Directory -Path (Join-Path $control 'tasks\active') -Force|Out-Null
try{
  & git -C $temp init -q
  if($LASTEXITCODE-ne0){throw 'GIT_INIT_FAILED'}
  Write-Json (Join-Path $control 'project.json') ([ordered]@{schemaVersion=7;id='authorization-receipt-fixture';displayName='Authorization Receipt Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
  Write-Json (Join-Path $control 'controller.json') ([ordered]@{schemaVersion=1;projectId='authorization-receipt-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
  Write-Utf8 $objectPath 'fixture object'


  if($Group-ceq'ExternalGrant'){
    Write-Task STANDARD EXTERNAL -OwnerRoute
    $flags=[ordered]@{};foreach($name in @('paymentOrSubscription','commercialLicensing','accountOrCredentialChange','publicPublication','installation','protectedOrSecretUpload','crossDomain','formalAssetActivation','projectPhaseChange','gitOrPush','sharedQuotaOrResource','unknownScope')){$flags[$name]=$false}
    $external=New-Package STANDARD TASK_OWNER owner-fixture EXTERNAL EXTERNAL_ACTION
    $external.userConfirmation='SIMULATED_ORIGINAL_RESOURCE_GRANT'
    $external['externalBinding']=[ordered]@{schemaVersion=1;route='TASK_OWNER_DIRECT_DOMAIN_EXTERNAL';provider='fixture-provider';orderedOperations=@([ordered]@{operationId='META-1';operationKind='PROVIDER_PUBLIC_METADATA_READ';declaredInputClass='ZERO_PROJECT_DATA';payloads=@()},[ordered]@{operationId='TRANSFORM-1';operationKind='bounded-transform';declaredInputClass='EXACT_PAYLOADS';payloads=@([ordered]@{payloadKind='normalized-text';normalizedIdentity=(Get-Identity $objectPath);canonicalizationVersion='UTF8_LF_V1'})});outputUse='exact fixture local candidate';totalQuantity=2;perOperationRetryCeiling=1;totalRetryCeiling=2;costClass='FREE';costCeiling=0;stopConditions=@('stop on errors','stop on ambiguous consumption');batchExecutionMode='ONE_LOGICAL_ATOMIC_EXECUTION';reissuable=$false;ambiguousConsumptionPolicy='BLOCK';escalationFlags=$flags}
    $script:externalCase=0
    function Check-External($Package,[string]$Actor='owner-fixture'){
      $script:externalCase++;$script:packagePath=Join-Path $control ('external-case-'+$script:externalCase+'.json')
      return Invoke-Check $Package $Actor EXTERNAL
    }
    Assert-True ((Check-External $external).Code-eq0) 'external-old-free-zero-branch-still-passes'
    $grant=Join-Path $control 'runtime/AUTH-REGRESSION-001/owner-fixture/original-resource-grant.txt'
    $grantText='SIMULATED original user permits this project existing paid/shared account, fixture-provider, META-1 and TRANSFORM-1 with the declared exact payload/use and account fixture-account. Owner may delegate that same bounded use to original specialist writer-fixture. No fixed numeric budget or expiry was set. No new purchase, credential change or protected upload.'
    Write-Utf8 $grant $grantText
    $v2=$external|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $v2.externalBinding.schemaVersion=2
    foreach($field in @('totalQuantity','costClass','costCeiling')){$v2.externalBinding.PSObject.Properties.Remove($field)}
    $v2.externalBinding|Add-Member grantRefs @([pscustomobject]@{path=$grant;identity=(Get-Identity $grant)})
    $v2.externalBinding|Add-Member grantAssessment ([pscustomobject]@{status='CURRENT_AND_COVERED';withdrawalOrReplacementObserved=$false;provider='fixture-provider';operationIds=@('META-1','TRANSFORM-1');outputUse='exact fixture local candidate';paidResourceUse=$true;sharedResourceUse=$false})
    Assert-True ((Check-External $v2).Code-eq0) 'external-existing-paid-grant-without-invented-money-quantity-or-expiry'
    $shared=$v2|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $shared.externalBinding.grantAssessment.sharedResourceUse=$true;$shared.externalBinding.escalationFlags.sharedQuotaOrResource=$true
    Assert-True ((Check-External $shared).Code-eq0) 'external-existing-shared-resource-grant-without-mandatory-numeric-quota'
    $limited=$shared|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $limited.externalBinding|Add-Member grantConditions ([pscustomobject]@{operationCeiling=4;costCeiling=[pscustomobject]@{value='3.50';requestedValue='3.25';currency='USD';unit='whole bounded batch'};deadlineUtc=([DateTimeOffset]::UtcNow.AddDays(2).ToString('yyyy-MM-ddTHH:mm:ssZ'));sharedQuota=[pscustomobject]@{resource='fixture-quota';quantity=5;requestedQuantity=4;unit='fixture units'}})
    Assert-True ((Check-External $limited).Code-eq0) 'external-actual-optional-limit-money-currency-deadline-shared-conditions'
    $delegated=$limited|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $delegated.grantee='writer-fixture';$delegated.externalBinding.grantAssessment|Add-Member delegationPermitted $true
    Assert-True ((Check-External $delegated writer-fixture).Code-eq0) 'external-owner-grants-named-original-specialist-existing-paid-shared-use'
    $wrongActor=Check-External $delegated another-fixture
    Assert-True ($wrongActor.Code-ne0-and$wrongActor.Text.Contains('GRANTEE_DRIFT')) 'external-delegated-package-rejects-wrong-actual-actor'
    foreach($case in @('MISSING_PERMISSION','FORBIDDEN_DELEGATION','UNKNOWN_PERMISSION','WITHDRAWN','UNKNOWN_GRANT','SCOPE','QUANTITY','NEW_PURCHASE','CROSS_DOMAIN','UNKNOWN_SCOPE','AMBIGUOUS')){
      $bad=$delegated|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      $reason=switch($case){
        MISSING_PERMISSION {$bad.externalBinding.grantAssessment.PSObject.Properties.Remove('delegationPermitted');'DOMAIN_EXTERNAL_DELEGATION_PERMISSION'}
        FORBIDDEN_DELEGATION {$bad.externalBinding.grantAssessment.delegationPermitted=$false;'DOMAIN_EXTERNAL_DELEGATION_PERMISSION'}
        UNKNOWN_PERMISSION {$bad.externalBinding.grantAssessment.delegationPermitted='UNKNOWN';'DOMAIN_EXTERNAL_DELEGATION_PERMISSION'}
        WITHDRAWN {$bad.externalBinding.grantAssessment.withdrawalOrReplacementObserved=$true;'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        UNKNOWN_GRANT {$bad.externalBinding.grantAssessment.status='UNKNOWN';'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        SCOPE {$bad.externalBinding.grantAssessment.operationIds=@('META-1');'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        QUANTITY {$bad.externalBinding.grantConditions.operationCeiling=3;'DOMAIN_EXTERNAL_GRANT_QUANTITY_EXCEEDED'}
        NEW_PURCHASE {$bad.externalBinding.escalationFlags.paymentOrSubscription=$true;'DOMAIN_EXTERNAL_ESCALATION_REQUIRED|paymentOrSubscription'}
        CROSS_DOMAIN {$bad.externalBinding.escalationFlags.crossDomain=$true;'DOMAIN_EXTERNAL_ESCALATION_REQUIRED|crossDomain'}
        UNKNOWN_SCOPE {$bad.externalBinding.escalationFlags.unknownScope=$true;'DOMAIN_EXTERNAL_ESCALATION_REQUIRED|unknownScope'}
        AMBIGUOUS {$bad.externalBinding.ambiguousConsumptionPolicy='RETRY';'DOMAIN_EXTERNAL_BINDING_VALUES'}
      }
      $r=Check-External $bad writer-fixture
      Assert-True ($r.Code-ne0-and$r.Text.Contains($reason)-and-not$r.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) ('external-delegated-grant-reject-'+$case.ToLowerInvariant())
    }
    $oldDelegate=$external|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$oldDelegate.grantee='writer-fixture'
    $oldRejected=Check-External $oldDelegate writer-fixture
    Assert-True ($oldRejected.Code-ne0-and$oldRejected.Text.Contains('DOMAIN_EXTERNAL_OWNER_ACTOR_MISMATCH')) 'external-old-free-branch-does-not-acquire-delegation'
    # The actual resolver must select and admit the temporary executor's rules;
    # checker acceptance alone would miss a TASK_OWNER-only selector.
    $frameworkRoot=Join-Path $temp 'framework-root';$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
    $fixtureVersion=New-AiwTestMechanismFixture $sourceRoot $frameworkRoot (Join-Path $PSScriptRoot 'test-groups.json')
    Write-Json (Join-Path $control 'corrections.json') @{schemaVersion=3;contractVersion='2.0.0';projectId='authorization-receipt-fixture';corrections=@()}
    Write-Json (Join-Path $control 'process-policy.json') @{schemaVersion=3;contractVersion='2.0.0';projectId='authorization-receipt-fixture';rules=@()}
    Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
    $externalPath=Join-Path $control 'delegated-external.json';Write-Json $externalPath $delegated
    $d=[ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=@{mode='FULL'};projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='writer-fixture';capabilities=@();exactPaths=@($objectRelative);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$externalPath;expectedAuthorizationIdentity=Get-Identity $externalPath;userDecision=$delegated.userConfirmation;recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=@{schemaVersion=2;objective='Consume the simulated existing grant as its named original specialist, without any provider call';requestedActionKind='EXTERNAL';requestedResultKind='EXTERNAL_RESULT';pathHints=@($objectRelative);capabilityHints=@();mutationHints=@();externalHints=@();semanticHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:software')};workType=@{state='KNOWN';values=@('aiw:implementation')};deliverableType=@{state='KNOWN';values=@('aiw:code')};stage=@{state='KNOWN';values=@('aiw:implementation')}}}}
    $inputPath=Join-Path $control 'external-discover.json';Write-Json $inputPath $d
    $resolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
    $output=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $inputPath -AsJson);$discoverCode=$LASTEXITCODE
    $actual=($output-join"`n")|ConvertFrom-Json -Depth 100
    Assert-True ($discoverCode-eq0-and$actual.status-ceq'PASS'-and$actual.compactReceipt.binding.role-ceq'EXECUTOR'-and$actual.compactReceipt.binding.phase-ceq'EXTERNAL'-and'framework:PR_TASK_OWNER_DIRECT_DOMAIN_EXTERNAL'-cin@($actual.compactReceipt.selectedObligations.requirementId)) 'external-delegated-executor-real-discover-selects-domain-obligations'
    $compact=Join-Path $control 'external-compact.json';Write-Json $compact $actual.compactReceipt
    $admit=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compact;expectedDiscoverReceiptIdentity=Get-Identity $compact;preparationReceipts=@($actual.compactReceipt.selectedObligations.preparationRequirements|Select-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE';evidenceRefs=@()}
    Write-Json $inputPath $admit;$output=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $inputPath -AsJson);$admitCode=$LASTEXITCODE
    $actual=($output-join"`n")|ConvertFrom-Json -Depth 100
    Assert-True ($admitCode-eq0-and$actual.status-ceq'PASS') 'external-delegated-executor-real-admit-with-existing-resource-grant'
    foreach($case in @('MISSING_GRANT','WITHDRAWN','REPLACED','SCOPE','QUANTITY','COST','FLOAT','CURRENCY','EXPIRED','SHARED_QUOTA','NEW_PURCHASE','UPLOAD','AMBIGUOUS')){
      $bad=$limited|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      switch($case){
        MISSING_GRANT {$bad.externalBinding.grantRefs=@()}
        WITHDRAWN {$bad.externalBinding.grantAssessment.status='WITHDRAWN';$bad.externalBinding.grantAssessment.withdrawalOrReplacementObserved=$true}
        REPLACED {$bad.externalBinding.grantAssessment.status='REPLACED';$bad.externalBinding.grantAssessment.withdrawalOrReplacementObserved=$true}
        SCOPE {$bad.externalBinding.grantAssessment.provider='another-provider'}
        QUANTITY {$bad.externalBinding.grantConditions.operationCeiling=3}
        COST {$bad.externalBinding.grantConditions.costCeiling.requestedValue='3.51'}
        FLOAT {$bad.externalBinding.grantConditions.costCeiling.value=3.50}
        CURRENCY {$bad.externalBinding.grantConditions.costCeiling.currency=''}
        EXPIRED {$bad.externalBinding.grantConditions.deadlineUtc='2000-01-01T00:00:00Z'}
        SHARED_QUOTA {$bad.externalBinding.grantConditions.sharedQuota.requestedQuantity=6}
        NEW_PURCHASE {$bad.externalBinding.escalationFlags.paymentOrSubscription=$true}
        UPLOAD {$bad.externalBinding.escalationFlags.protectedOrSecretUpload=$true}
        AMBIGUOUS {$bad.externalBinding.ambiguousConsumptionPolicy='RETRY'}
      }
      $rejected=Check-External $bad
      Assert-True ($rejected.Code-ne0-and$rejected.Text.Contains('DOMAIN_EXTERNAL')) ('external-bounded-original-grant-reject-'+$case.ToLowerInvariant())
    }
    [IO.File]::AppendAllText($grant,' This original source changed.',$utf8)
    $drift=Check-External $v2
    Assert-True ($drift.Code-ne0-and$drift.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) 'external-original-grant-byte-drift-rejected-before-consumption'
    # A separate external observer must not force the producing Owner out of
    # its real main IMPLEMENT route, including during REVIEW lifecycle.
    Write-Task STANDARD IMPLEMENT REVIEW -OwnerRoute
    $phaseTaskBytes=[IO.File]::ReadAllBytes($taskPath)
    $phaseTaskIdentity=Get-Identity $taskPath
    Write-Utf8 $grant ($grantText.Replace('writer-fixture','original-reviewer-fixture'))
    $phaseGrantIdentity=Get-Identity $grant
    $phaseDelegate=$shared|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $phaseDelegate.taskIdentity=$phaseTaskIdentity;$phaseDelegate.grantee='original-reviewer-fixture'
    $phaseDelegate.externalBinding.grantRefs[0].identity=$phaseGrantIdentity
    $phaseDelegate.externalBinding.grantAssessment|Add-Member delegationPermitted $true
    $phaseCheck=Check-External $phaseDelegate original-reviewer-fixture
    Assert-True ($phaseCheck.Code-eq0) 'external-named-observer-owner-implement-review-lifecycle-public-checker'
    $phaseExternalPath=Join-Path $control 'delegated-external-owner-implement.json';Write-Json $phaseExternalPath $phaseDelegate
    $phaseDiscover=$d|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $phaseDiscover.expectedTaskIdentity=$phaseTaskIdentity;$phaseDiscover.observedActor='original-reviewer-fixture'
    $phaseDiscover.authorizationPackagePath=$phaseExternalPath;$phaseDiscover.expectedAuthorizationIdentity=Get-Identity $phaseExternalPath
    $phaseDiscover.intentEnvelope.objective='Use the simulated current paid/shared grant as its original named external observer while the Owner actually remains IMPLEMENT; no provider call'
    $phaseInputPath=Join-Path $control 'external-owner-implement-discover.json';Write-Json $phaseInputPath $phaseDiscover
    $phaseOutput=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $phaseInputPath -AsJson);$phaseDiscoverCode=$LASTEXITCODE
    $phaseActual=($phaseOutput-join"`n")|ConvertFrom-Json -Depth 100
    Assert-True ($phaseDiscoverCode-eq0-and$phaseActual.status-ceq'PASS'-and$phaseActual.compactReceipt.binding.role-ceq'EXECUTOR'-and$phaseActual.compactReceipt.binding.phase-ceq'EXTERNAL'-and$phaseActual.compactReceipt.binding.taskActor-ceq'owner-fixture'-and$phaseActual.compactReceipt.binding.taskOwner-ceq'owner-fixture'-and'framework:PR_TASK_OWNER_DIRECT_DOMAIN_EXTERNAL'-cin@($phaseActual.compactReceipt.selectedObligations.requirementId)) 'external-owner-implement-real-discover-retains-owner-selects-temporary-domain-route'
    $phaseCompact=Join-Path $control 'external-owner-implement-compact.json';Write-Json $phaseCompact $phaseActual.compactReceipt
    $phaseAdmit=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$phaseCompact;expectedDiscoverReceiptIdentity=Get-Identity $phaseCompact;preparationReceipts=@($phaseActual.compactReceipt.selectedObligations.preparationRequirements|Select-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE';evidenceRefs=@()}
    $phaseAdmitPath=Join-Path $control 'external-owner-implement-admit.json';Write-Json $phaseAdmitPath $phaseAdmit
    $phaseOutput=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $phaseAdmitPath -AsJson);$phaseAdmitCode=$LASTEXITCODE
    $phaseAdmission=($phaseOutput-join"`n")|ConvertFrom-Json -Depth 100
    Assert-True ($phaseAdmitCode-eq0-and$phaseAdmission.status-ceq'PASS') 'external-owner-implement-real-admit-current-permitted-named-observer'
    Assert-True ((Get-Identity $taskPath)-ceq$phaseTaskIdentity) 'external-temporary-observer-does-not-rewrite-owner-main-route-or-task-bytes'
    $phaseWrongActor=Check-External $phaseDelegate another-fixture
    Assert-True ($phaseWrongActor.Code-ne0-and$phaseWrongActor.Text.Contains('GRANTEE_DRIFT')) 'external-owner-implement-rejects-wrong-actual-recipient'
    foreach($case in @('OWNER','ISSUER','MISSING_PERMISSION','FORBIDDEN_DELEGATION','UNKNOWN_PERMISSION','WITHDRAWN','UNKNOWN_GRANT','MISSING_GRANT','PROVIDER','OUTPUT_USE','OPERATION','PAYLOAD','PAID_UNKNOWN','SHARED_DRIFT','QUANTITY','NEW_PURCHASE','CROSS_DOMAIN','UNKNOWN_SCOPE','AMBIGUOUS')){
      $bad=$phaseDelegate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      $reason=switch($case){
        OWNER {$bad.owner='another-owner';'OWNER_DRIFT'}
        ISSUER {$bad.issuer='another-owner';'TASK_OWNER_MUST_OWN_TASK'}
        MISSING_PERMISSION {$bad.externalBinding.grantAssessment.PSObject.Properties.Remove('delegationPermitted');'DOMAIN_EXTERNAL_DELEGATION_PERMISSION'}
        FORBIDDEN_DELEGATION {$bad.externalBinding.grantAssessment.delegationPermitted=$false;'DOMAIN_EXTERNAL_DELEGATION_PERMISSION'}
        UNKNOWN_PERMISSION {$bad.externalBinding.grantAssessment.delegationPermitted='UNKNOWN';'DOMAIN_EXTERNAL_DELEGATION_PERMISSION'}
        WITHDRAWN {$bad.externalBinding.grantAssessment.withdrawalOrReplacementObserved=$true;'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        UNKNOWN_GRANT {$bad.externalBinding.grantAssessment.status='UNKNOWN';'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        MISSING_GRANT {$bad.externalBinding.grantRefs=@();'DOMAIN_EXTERNAL_GRANT_REQUIRED'}
        PROVIDER {$bad.externalBinding.grantAssessment.provider='ungranted-provider';'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        OUTPUT_USE {$bad.externalBinding.outputUse='ungranted-output-use';'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        OPERATION {$bad.externalBinding.grantAssessment.operationIds=@('META-1');'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        PAYLOAD {$bad.externalBinding.orderedOperations[1].payloads[0].normalizedIdentity='UNBOUND_PAYLOAD';'DOMAIN_EXTERNAL_PAYLOAD_VALUES'}
        PAID_UNKNOWN {$bad.externalBinding.grantAssessment.paidResourceUse='UNKNOWN';'DOMAIN_EXTERNAL_GRANT_NOT_CURRENT_OR_COVERED'}
        SHARED_DRIFT {$bad.externalBinding.grantAssessment.sharedResourceUse=$false;'DOMAIN_EXTERNAL_SHARED_GRANT_DRIFT'}
        QUANTITY {$bad.externalBinding|Add-Member grantConditions ([pscustomobject]@{operationCeiling=3});'DOMAIN_EXTERNAL_GRANT_QUANTITY_EXCEEDED'}
        NEW_PURCHASE {$bad.externalBinding.escalationFlags.paymentOrSubscription=$true;'DOMAIN_EXTERNAL_ESCALATION_REQUIRED|paymentOrSubscription'}
        CROSS_DOMAIN {$bad.externalBinding.escalationFlags.crossDomain=$true;'DOMAIN_EXTERNAL_ESCALATION_REQUIRED|crossDomain'}
        UNKNOWN_SCOPE {$bad.externalBinding.escalationFlags.unknownScope=$true;'DOMAIN_EXTERNAL_ESCALATION_REQUIRED|unknownScope'}
        AMBIGUOUS {$bad.externalBinding.ambiguousConsumptionPolicy='RETRY';'DOMAIN_EXTERNAL_BINDING_VALUES'}
      }
      $r=Check-External $bad original-reviewer-fixture
      Assert-True ($r.Code-ne0-and$r.Text.Contains($reason)-and-not$r.Text.Contains('TASK_OBJECT_DRIFT')-and-not$r.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) ('external-owner-implement-current-guard-'+$case.ToLowerInvariant())
    }
    foreach($case in @('ROLE','MAIN_ACTOR')){
      $changedTask=[Text.Encoding]::UTF8.GetString($phaseTaskBytes)
      $changedTask=if($case-ceq'ROLE'){$changedTask.Replace('role=TASK_OWNER','role=EXECUTOR')}else{$changedTask.Replace('actor=owner-fixture','actor=another-owner')}
      Write-Utf8 $taskPath $changedTask
      $bad=$phaseDelegate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.taskIdentity=Get-Identity $taskPath
      $r=Check-External $bad original-reviewer-fixture
      Assert-True ($r.Code-ne0-and$r.Text.Contains('DOMAIN_EXTERNAL_TASK_ROUTE')-and-not$r.Text.Contains('TASK_OBJECT_DRIFT')) ('external-owner-implement-rejects-wrong-primary-'+$case.ToLowerInvariant())
      [IO.File]::WriteAllBytes($taskPath,$phaseTaskBytes)
    }
    foreach($self in @($external,$v2)){
      $bad=$self|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.taskIdentity=$phaseTaskIdentity
      if($bad.externalBinding.schemaVersion-eq2){$bad.externalBinding.grantRefs[0].identity=$phaseGrantIdentity}
      $r=Check-External $bad
      Assert-True ($r.Code-ne0-and$r.Text.Contains('DOMAIN_EXTERNAL_TASK_ROUTE')-and-not$r.Text.Contains('TASK_OBJECT_DRIFT')) ('external-owner-self-binding'+$bad.externalBinding.schemaVersion+'-still-requires-external-main-phase')
    }
    [IO.File]::AppendAllText($grant,' Current original observer grant was replaced.',$utf8)
    $phaseDrift=Check-External $phaseDelegate original-reviewer-fixture
    Assert-True ($phaseDrift.Code-ne0-and$phaseDrift.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) 'external-owner-implement-rejects-current-original-grant-byte-drift'
    Assert-True ((Get-Identity $taskPath)-ceq$phaseTaskIdentity) 'external-owner-implement-negative-checks-preserve-original-task'
    Write-Output 'CEILING|Authorization mechanics with simulated original grants; no paid/shared provider, billing, upload or host external operation was invoked.'
    Write-GroupCompletion;return
  }

  if($Group-ceq'ReaderAssignment'){
    Write-Task STANDARD IMPLEMENT
    $taskBefore=[IO.File]::ReadAllBytes($taskPath);$objectBefore=[IO.File]::ReadAllBytes($objectPath)
    $knownActor='01a0eeee-3333-7222-8333-444444444444'
    $known=New-Package STANDARD TASK_OWNER $knownActor NONE ROUTINE_LOCAL
    $knownPath=Join-Path $control 'reader-known-package.json';Write-Json $knownPath $known
    Assert-True ((Invoke-Check $known $knownActor NONE).Code-eq0) 'reader-known-task-bound-pure-none-passes-public-checker'
    $wrong=Invoke-Check $known another-reader NONE
    Assert-True ($wrong.Code-ne0-and$wrong.Text.Contains('GRANTEE_DRIFT')) 'reader-known-package-rejects-wrong-actor'
    foreach($action in @('SOURCE_WRITE','TEST_RUN','REVIEW_EXECUTE','EXTERNAL')){
      $r=Invoke-Check $known $knownActor $action
      Assert-True ($r.Code-ne0-and$r.Text.Contains('ACTION_NOT_GRANTED')) ('reader-none-does-not-grant-'+$action)
    }
    $mixed=$known|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$mixed.actions=@('NONE','SOURCE_WRITE')
    $r=Invoke-Check $mixed $knownActor NONE
    Assert-True ($r.Code-ne0-and$r.Text.Contains('READER_ASSIGNMENT_ACTION_MUST_BE_PURE')) 'reader-rejects-none-mixed-with-side-effect'
    foreach($field in @('continuationPlan','selfCheckRepairLimit','repairReviewPlan')){
      $bad=$known|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      $value=switch($field){continuationPlan{@('NONE','NONE')} selfCheckRepairLimit{1} repairReviewPlan{[pscustomobject]@{writer=$knownActor;reviewer='reviewer-fixture';maxCycles=1;materialContributors=@()}}}
      $bad|Add-Member $field $value
      $r=Invoke-Check $bad $knownActor NONE
      Assert-True ($r.Code-ne0-and$r.Text.Contains('READER_ASSIGNMENT_EXTENSION|'+$field)) ('reader-rejects-action-extension-'+$field)
    }
    $unbound=$known|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$unbound.grantee='UNBOUND_RECEIVER'
    $r=Invoke-Check $unbound UNBOUND_RECEIVER NONE
    Assert-True ($r.Code-ne0-and$r.Text.Contains('READER_ASSIGNMENT_GRANTEE_UNBOUND')) 'reader-unbound-template-is-not-executable'
    $outside=Invoke-Check $known $knownActor NONE @('src/not-granted.txt')
    Assert-True ($outside.Code-ne0-and$outside.Text.Contains('OBSERVED_PATH_OUTSIDE_EXACT')) 'reader-cannot-expand-exact-read-scope'
    Write-Utf8 $objectPath 'Actual reader candidate drift'
    $r=Invoke-Check $known $knownActor NONE
    Assert-True ($r.Code-ne0-and$r.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) 'reader-checks-actual-current-bytes-not-only-reported-identities'
    [IO.File]::WriteAllBytes($objectPath,$objectBefore)
    [IO.File]::AppendAllText($taskPath,"`nChanged task authority`n",$utf8)
    $r=Invoke-Check $known $knownActor NONE
    Assert-True ($r.Code-ne0-and$r.Text.Contains('TASK_OBJECT_DRIFT')) 'reader-task-authority-drift-rejects-original-assignment'
    [IO.File]::WriteAllBytes($taskPath,$taskBefore)
    # Freeze valid observed identities before applying current restrictions.
    # The existing safe candidate reader must reject before its object read.
    Write-Json $packagePath $known
    foreach($restriction in @('ForbiddenPaths','ProtectedPaths')){
      $parameters=@{PackagePath=$packagePath;ObservedActor=$knownActor;ObservedTaskId='AUTH-REGRESSION-001';ObservedOwner='owner-fixture';ObservedAction=@('NONE');ObservedPath=@($objectRelative);ObservedIdentity=@($objectRelative+'='+$known.objectIdentities[0].identity);ControllerControlPath='.ai-workspace/controller.json';ObservedRepositoryId='REPO_LOCAL';ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');TaskPath=$taskRelative;ExpectedTaskIdentity=Get-Identity $taskPath}
      $parameters[$restriction]=@($objectRelative)
      $location=Get-Location;$cwd=[Environment]::CurrentDirectory
      try{Set-Location $temp;[Environment]::CurrentDirectory=$temp;$response=& $authKernel.ExportedCommands['Invoke-AiwAuthorizationCheck'] @parameters}
      finally{Set-Location $location;[Environment]::CurrentDirectory=$cwd}
      Assert-True ($response.exitCode-ne0-and(@($response.output)-join"`n").Contains('EVIDENCE_PATH_FORBIDDEN')) ('reader-current-'+$restriction+'-rejects-before-candidate-read')
    }
    $frameworkRoot=Join-Path $temp 'framework-root';$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
    $fixtureVersion=New-AiwTestMechanismFixture $sourceRoot $frameworkRoot (Join-Path $PSScriptRoot 'test-groups.json')
    Write-Json (Join-Path $control 'corrections.json') @{schemaVersion=3;contractVersion='2.0.0';projectId='authorization-receipt-fixture';corrections=@()}
    Write-Json (Join-Path $control 'process-policy.json') @{schemaVersion=3;contractVersion='2.0.0';projectId='authorization-receipt-fixture';rules=@()}
    Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
    Write-Utf8 (Join-Path $temp 'AGENTS.md') 'Simulated task reader assignment is current. No other action is authorized.'
    $readerResolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
    function Reader-Process($Value,[string]$Name){
      $path=Join-Path $control ($Name+'.json');Write-Json $path $Value
      $out=@(Invoke-AuthNative -NoProfile -File $readerResolver -InputPath $path -AsJson);$code=$LASTEXITCODE
      $text=$out-join"`n";Write-Utf8 (Join-Path $control ($Name+'-output.txt')) $text
      return [pscustomobject]@{Code=$code;Text=$text;Value=($text|ConvertFrom-Json -Depth 100)}
    }
    $d=[ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=@{mode='FULL'};projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor=$knownActor;capabilities=@();exactPaths=@($objectRelative);forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath=$knownPath;expectedAuthorizationIdentity=Get-Identity $knownPath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=@{schemaVersion=2;objective='Read this task exact candidate as its named temporary investigator and return a bounded analysis; no write, test, review or external action';requestedActionKind='NONE';requestedResultKind='PLAN';pathHints=@($objectRelative);capabilityHints=@();mutationHints=@();externalHints=@();semanticHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:software')};workType=@{state='KNOWN';values=@('aiw:planning')};deliverableType=@{state='KNOWN';values=@('aiw:diagnosis')};stage=@{state='KNOWN';values=@('aiw:planning')}}}}
    $r=Reader-Process $d 'reader-known-discover'
    Assert-True ($r.Code-eq0-and$r.Value.status-ceq'PASS'-and$r.Value.compactReceipt.binding.contextType-ceq'TASK'-and$r.Value.compactReceipt.binding.role-ceq'EXECUTOR'-and$r.Value.compactReceipt.binding.phase-ceq'PLAN'-and$r.Value.compactReceipt.binding.taskActor-ceq'writer-fixture') 'reader-known-task-discover-none-plan-keeps-original-work-route'
    $compact=Join-Path $control 'reader-known-compact.json';Write-Json $compact $r.Value.compactReceipt
    Write-Utf8 (Join-Path $temp 'AGENTS.md') 'Simulated original human source now withdraws this reader assignment.'
    $boundary=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compact;expectedDiscoverReceiptIdentity=Get-Identity $compact;preparationReceipts=@($r.Value.compactReceipt.selectedObligations.preparationRequirements|Select-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $withdrawn=Reader-Process $boundary 'reader-human-source-withdrawal'
    Assert-True ($withdrawn.Code-ne0-and$withdrawn.Text.Contains('DISCOVER_SOURCE_DRIFT')) 'reader-current-human-source-change-invalidates-old-discover-not-mechanical-semantic-proof'
    Write-Utf8 (Join-Path $temp 'AGENTS.md') 'Simulated task reader assignment is current. No other action is authorized.'
    $noPackage=$d|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$noPackage.authorizationPackagePath='NOT_REQUIRED';$noPackage.expectedAuthorizationIdentity='NOT_REQUIRED'
    $r=Reader-Process $noPackage 'reader-without-assignment'
    Assert-True ($r.Code-eq0-and$r.Value.compactReceipt.binding.role-ceq'EXECUTOR'-and$r.Value.compactReceipt.binding.phase-ceq'PLAN'-and$r.Value.compactReceipt.binding.taskActor-ceq'writer-fixture'-and$r.Value.compactReceipt.binding.taskOwner-ceq'owner-fixture'-and@($r.Value.compactReceipt.binding.authorizedActions).Count-eq0) 'reader-safe-task-none-without-implementation-package-keeps-original-authority-and-no-actions'
    $plainCompact=Join-Path $control 'reader-plain-compact.json';Write-Json $plainCompact $r.Value.compactReceipt
    $plainBoundary=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$plainCompact;expectedDiscoverReceiptIdentity=Get-Identity $plainCompact;preparationReceipts=@($r.Value.compactReceipt.selectedObligations.preparationRequirements|Select-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
    $plainAdmit=Reader-Process $plainBoundary 'reader-plain-admit'
    Assert-True ($plainAdmit.Code-eq0-and$plainAdmit.Value.status-ceq'PASS') 'reader-plain-none-admission-does-not-require-fake-side-effect'
    foreach($action in @('SOURCE_WRITE','TEST_RUN','REVIEW_EXECUTE')){
      $bad=$noPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.intentEnvelope.requestedActionKind=$action
      $bad.intentEnvelope.requestedResultKind=switch($action){SOURCE_WRITE {'IMPLEMENTATION_RESULT'};TEST_RUN {'TEST_RESULT'};REVIEW_EXECUTE {'REVIEW_VERDICT'}}
      if($action-ceq'SOURCE_WRITE'){$bad.intentEnvelope.mutationHints=@('source')}
      $r=Reader-Process $bad ('reader-plain-no-'+$action)
      Assert-True ($r.Code-ne0-and$r.Text.Contains('CONFLICT_ACTOR_ROLE_PHASE')) ('reader-plain-none-does-not-grant-'+$action)
    }
    $plainProtected=$noPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$plainProtected.protectedPaths=@($objectRelative)
    $r=Reader-Process $plainProtected 'reader-plain-current-protection'
    Assert-True ($r.Code-ne0-and$r.Text.Contains('EVIDENCE_PATH_FORBIDDEN')) 'reader-plain-task-none-applies-current-protection'
    Write-Utf8 (Join-Path $temp 'AGENTS.md') 'A later human source changes the current read conditions.'
    $r=Reader-Process $plainBoundary 'reader-plain-source-change'
    Assert-True ($r.Code-ne0-and$r.Text.Contains('DISCOVER_SOURCE_DRIFT')) 'reader-plain-none-does-not-freeze-or-exempt-current-human-source'
    Write-Utf8 (Join-Path $temp 'AGENTS.md') 'Simulated task reader assignment is current. No other action is authorized.'
    $restricted=$d|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$restricted.protectedPaths=@($objectRelative)
    $r=Reader-Process $restricted 'reader-discover-current-protection'
    Assert-True ($r.Code-ne0-and$r.Text.Contains('EVIDENCE_PATH_FORBIDDEN')) 'reader-real-task-discover-honors-current-protection'
    $pendingTemplate=New-Package STANDARD TASK_OWNER UNBOUND_RECEIVER NONE ROUTINE_LOCAL
    $receiverActor='01a0eeee-4444-7222-8333-444444444444';$delegationId='fixture-reader-assignment-001'
    $pendingPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-reader.json'
    $pending=@{schemaVersion=1;delegationId=$delegationId;receiverRole='INVESTIGATOR';authorizationTemplate=$pendingTemplate};Write-Json $pendingPath $pending
    $pendingBytes=[IO.File]::ReadAllBytes($pendingPath);$oldHost=$env:CODEX_THREAD_ID
    try{
      $env:CODEX_THREAD_ID=$receiverActor
      $out=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegationId);$code=$LASTEXITCODE
      $boundPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$receiverActor+'/receiver-authorization-'+$delegationId+'.json')
      Assert-True ($code-eq0-and($out-join"`n").Contains('PASS|package=')) 'reader-unknown-receiver-binds-existing-investigator-role-to-host-actor'
      $bound=Get-Content -LiteralPath $boundPath -Raw|ConvertFrom-Json -Depth 100
      Assert-True ((Invoke-Check $bound $receiverActor NONE).Code-eq0) 'reader-bound-investigator-passes-public-none-checker'
      $unknown=$d|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$unknown.observedActor=$receiverActor;$unknown.authorizationPackagePath=$boundPath;$unknown.expectedAuthorizationIdentity=Get-Identity $boundPath
      $r=Reader-Process $unknown 'reader-unknown-discover'
      Assert-True ($r.Code-eq0-and$r.Value.compactReceipt.binding.actor-ceq$receiverActor-and$r.Value.compactReceipt.binding.phase-ceq'PLAN') 'reader-bound-investigator-actual-task-none-plan-discover'
      $expanded=$bound|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$expanded.actions=@('NONE','TEST_RUN')
      $r=Invoke-Check $expanded $receiverActor NONE
      Assert-True ($r.Code-ne0-and$r.Text.Contains('RECEIVER_ROLE_ACTION')) 'reader-derived-assignment-cannot-add-test-action'
      $env:CODEX_THREAD_ID=$knownActor;$r=Invoke-Check $bound $receiverActor NONE
      Assert-True ($r.Code-ne0-and$r.Text.Contains('RECEIVER_HOST_IDENTITY')) 'reader-bound-assignment-rejects-another-host-actor'
      $env:CODEX_THREAD_ID=$receiverActor
      Write-Utf8 $pendingPath 'Original assignment withdrawn or replaced in this isolated fixture.'
      $r=Invoke-Check $bound $receiverActor NONE
      Assert-True ($r.Code-ne0-and$r.Text.Contains('RECEIVER_PENDING_DRIFT')) 'reader-original-assignment-withdrawal-or-byte-tamper-invalidates-derived-package'
      [IO.File]::WriteAllBytes($pendingPath,$pendingBytes)
      $badTemplate=$pendingTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badTemplate.actions=@('SOURCE_WRITE')
      $badPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/bad-reader.json';$badId='fixture-reader-bad-role-001'
      Write-Json $badPending @{schemaVersion=1;delegationId=$badId;receiverRole='INVESTIGATOR';authorizationTemplate=$badTemplate}
      $out=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $badPending -ExpectedPendingIdentity (Get-Identity $badPending) -ReceivedDelegationId $badId);$code=$LASTEXITCODE
      Assert-True ($code-ne0-and($out-join"`n").Contains('RECEIVER_ROLE_ACTION')) 'reader-investigator-binder-cannot-bind-source-authority'
      $forged=$badTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forged.grantee=$receiverActor;$forged|Add-Member receiverBinding ([pscustomobject]@{pendingPath=$badPending;pendingIdentity=Get-Identity $badPending;delegationId=$badId;hostActor=$receiverActor;receiverRole='INVESTIGATOR'})
      $r=Invoke-Check $forged $receiverActor SOURCE_WRITE
      Assert-True ($r.Code-ne0-and$r.Text.Contains('RECEIVER_ROLE_ACTION')) 'reader-checker-independently-enforces-original-investigator-role-actions'
    }finally{$env:CODEX_THREAD_ID=$oldHost}
    Assert-True ((Get-Identity $taskPath)-ceq$known.taskIdentity-and[IO.File]::ReadAllText($taskPath).Contains('actor=writer-fixture; role=EXECUTOR; phase=IMPLEMENT')) 'reader-assignment-never-changes-owner-or-work-route'
    Write-Output 'CEILING|Isolated task-bound read qualification and actual local protocol checks; original delegation/withdrawal semantics and simulated host identity remain INSTRUCTION_BOUND. No product write/test/external permission is inferred.'
    Write-GroupCompletion;return
  }

  if($Group-ceq'PackageShape'){
  Write-Task 'STANDARD' 'IMPLEMENT' 'ACTIVE_WRITE'
  $externalTaskCheck=Invoke-TaskCheck
  Assert-True ($externalTaskCheck.Code-eq0) 'task-card-active-write-allows-external-authorization-carrier'
  $externalPackage=New-Package 'STANDARD' 'TASK_OWNER' 'writer-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL'
  $externalAuthorization=Invoke-Check $externalPackage 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($externalAuthorization.Code-eq0) 'external-authorization-package-binds-stable-task-preimage'
  $externalTaskText=Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath
  $fence=[string]::new([char]0x60,3)
  $inlineBlock=$fence+"authorization-package`n"+($externalPackage|ConvertTo-Json -Depth 50)+"`n"+$fence+"`n"
  Write-Utf8 $taskPath ($externalTaskText.TrimEnd("`n")+"`n`n"+$inlineBlock)
  $singleInlineTaskCheck=Invoke-TaskCheck
  Assert-True ($singleInlineTaskCheck.Code-eq0) 'task-card-single-inline-authorization-remains-structurally-compatible'
  Write-Utf8 $taskPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $taskPath).TrimEnd("`n")+"`n`n"+$inlineBlock)
  $duplicateInlineTaskCheck=Invoke-TaskCheck
  Assert-True ($duplicateInlineTaskCheck.Code-ne0-and$duplicateInlineTaskCheck.Text.Contains('AUTHORIZATION_BLOCK_COUNT')) 'task-card-rejects-multiple-inline-authorization-blocks'

  }
  Write-Task 'STANDARD' 'IMPLEMENT'
  $standard=Invoke-Check (New-Package 'STANDARD' 'TASK_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($standard.Code-eq0) 'authorization-canonical-standard-package-passes'

  $useKernel=$Group-cin@('PackageShape','BindingIndependence','ReviewIndependence')
  if($Group-ceq'ReviewIndependence'){
    foreach($profile in @('STANDARD','CRITICAL')){
      Write-Task $profile 'REVIEW'
      foreach($actor in @('reviewer-fixture','owner-fixture','controller-fixture','writer-fixture','contributor-fixture')){
        $pkg=New-Package $profile PROJECT_CONTROLLER $actor REVIEW_EXECUTE ROUTINE_LOCAL controller-fixture
        $pkg['reviewIndependence']='INDEPENDENT';$pkg['candidateWriter']='writer-fixture';$pkg['materialContributors']=@('contributor-fixture')
        if('CONTRIBUTOR_SET_CHANGE'-cnotin$pkg.invalidatesOn){$pkg.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE')}
        $checked=Invoke-Check $pkg $actor REVIEW_EXECUTE
        if($actor-ceq'reviewer-fixture'){Assert-True ($checked.Code-eq0) ('all-profile-independent-review-valid-'+$profile)}else{
          $reason=if($profile-ceq'CRITICAL'){'CRITICAL_REVIEW_NOT_INDEPENDENT'}else{'REVIEW_NOT_INDEPENDENT'}
          Assert-True ($checked.Code-ne0-and$checked.Text.Contains($reason)) ('all-profile-independent-review-excludes-'+$profile+'-'+$actor)
        }
      }
    }
    Write-Task STANDARD REVIEW
    $receiver='01a0eeee-3333-7222-8333-444444444444';$delegation='fixture-standard-independent-review-001'
    $template=New-Package STANDARD TASK_OWNER UNBOUND_RECEIVER REVIEW_EXECUTE ROUTINE_LOCAL
    $template.schemaVersion=2;$template['repositoryId']='REPO_LOCAL';$template['reviewIndependence']='INDEPENDENT';$template['candidateWriter']='writer-fixture';$template['materialContributors']=@('contributor-fixture');$template.invalidatesOn+=@('REPOSITORY_CHANGE','CONTRIBUTOR_SET_CHANGE')
    $pendingPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-standard-review.json'
    Write-Json $pendingPath ([ordered]@{schemaVersion=1;delegationId=$delegation;receiverRole='REVIEWER';authorizationTemplate=$template})
    $previousHost=$env:CODEX_THREAD_ID
    try{
      $env:CODEX_THREAD_ID=$receiver
      $raw=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegation);$exit=$LASTEXITCODE
      $boundPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$receiver+'/receiver-authorization-'+$delegation+'.json')
      Assert-True ($exit-eq0-and[IO.File]::Exists($boundPath)) 'all-profile-standard-review-original-receiver-binds-current-host-id'
      $bound=Get-Content -LiteralPath $boundPath -Raw|ConvertFrom-Json -Depth 100
      Assert-True ((Invoke-Check $bound $receiver REVIEW_EXECUTE).Code-eq0-and$bound.candidateWriter-ceq'writer-fixture') 'all-profile-standard-review-bound-receiver-preserves-independent-contributor-set'
    }finally{$env:CODEX_THREAD_ID=$previousHost}
    Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=authorization-review-independence|evidenceCeiling=INSTRUCTION_BOUND')
    return
  }
  if($Group-ceq'BindingIndependence'){
  # The original issuer fixes every authorization field before creating a
  # receiver; the receiver supplies only the host ID and initial delegation ID.
  $receiverActor='01a0eeee-1111-7222-8333-444444444444';$delegationId='fixture-initial-implementer-001'
  $pendingTemplate=New-Package 'STANDARD' 'TASK_OWNER' 'UNBOUND_RECEIVER' 'SOURCE_WRITE' 'ROUTINE_LOCAL'
  $pendingTemplate.schemaVersion=2;$pendingTemplate['repositoryId']='REPO_LOCAL';$pendingTemplate.actions=@('SOURCE_WRITE','TEST_RUN');$pendingTemplate['continuationPlan']=@('SOURCE_WRITE','TEST_RUN');$pendingTemplate.invalidatesOn+=@('REPOSITORY_CHANGE','CONTINUATION_RESULT_DRIFT')
  $pending=[ordered]@{schemaVersion=1;delegationId=$delegationId;receiverRole='IMPLEMENTER';authorizationTemplate=$pendingTemplate}
  $pendingPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-implementer.json';Write-Json $pendingPath $pending
  Assert-True ((Invoke-Check $pendingTemplate 'UNBOUND_RECEIVER' 'SOURCE_WRITE').Code-ne0) 'unbound-receiver-template-cannot-execute'
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$receiverActor
    $wrongDelegation=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId 'wrong-initial-delegation' 2>&1|ForEach-Object{[string]$_});$wrongDelegationCode=$LASTEXITCODE
    Assert-True ($wrongDelegationCode-ne0-and($wrongDelegation-join"`n").Contains('INITIAL_DELEGATION_MISMATCH')) 'receiver-rejects-wrong-initial-delegation'
    $wrongIdentity=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity ('1|'+('0'*64)) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$wrongIdentityCode=$LASTEXITCODE
    Assert-True ($wrongIdentityCode-ne0-and($wrongIdentity-join"`n").Contains('PENDING_IDENTITY_DRIFT')) 'receiver-rejects-tampered-pending-authorization'
    $boundResult=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$boundCode=$LASTEXITCODE
    $boundPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$receiverActor+'/receiver-authorization-'+$delegationId+'.json')
    Assert-True ($boundCode-eq0-and(Test-Path -LiteralPath $boundPath -PathType Leaf)-and($boundResult-join"`n").Contains('PASS|package=')) 'receiver-generates-bound-package-in-own-process-directory'
    $bound=Get-Content -LiteralPath $boundPath -Raw|ConvertFrom-Json -Depth 100
    Assert-True ((Invoke-Check $bound $receiverActor 'SOURCE_WRITE').Code-eq0-and[string]::Join(',',@($bound.continuationPlan))-ceq'SOURCE_WRITE,TEST_RUN') 'receiver-bound-implementer-preserves-combined-write-test-continuation'
    $forbiddenTemplate=$pendingTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forbiddenTemplate.actions=@('SOURCE_WRITE','PUSH')
    $forbiddenId='fixture-initial-implementer-push-001';$forbiddenPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-implementer-push.json'
    Write-Json $forbiddenPending ([ordered]@{schemaVersion=1;delegationId=$forbiddenId;receiverRole='IMPLEMENTER';authorizationTemplate=$forbiddenTemplate})
    $forbiddenBind=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $forbiddenPending -ExpectedPendingIdentity (Get-Identity $forbiddenPending) -ReceivedDelegationId $forbiddenId 2>&1|ForEach-Object{[string]$_});$forbiddenCode=$LASTEXITCODE
    Assert-True ($forbiddenCode-ne0-and($forbiddenBind-join"`n").Contains('RECEIVER_ROLE_ACTION')) 'receiver-implementer-rejects-unrelated-push-action'
    $beforeResume=Get-Identity $boundPath
    $resume=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$resumeCode=$LASTEXITCODE
    Assert-True ($resumeCode-eq0-and($resume-join"`n").Contains('PASS|package=')-and(Get-Identity $boundPath)-ceq$beforeResume) 'healthy-receiver-reuses-identical-bound-package'
    $expanded=$bound|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$expanded.exactPaths=@($objectRelative,'src/extra.txt')
    $expandedResult=Invoke-Check $expanded $receiverActor 'SOURCE_WRITE'
    Assert-True ($expandedResult.Code-ne0-and$expandedResult.Text.Contains('RECEIVER_AUTHORITY_EXPANDED')) 'receiver-cannot-expand-original-scope'
    $env:CODEX_THREAD_ID='01a0eeee-9999-7222-8333-444444444444'
    $wrongHost=Invoke-Check $bound $receiverActor 'SOURCE_WRITE'
    Assert-True ($wrongHost.Code-ne0-and$wrongHost.Text.Contains('RECEIVER_HOST_IDENTITY')) 'bound-package-rejects-other-host-actor'
    $redirectActor='01a0eeee-7777-7222-8333-444444444444';$outside=Join-Path $temp 'receiver-redirect-target';New-Item -ItemType Directory -Path $outside|Out-Null
    $redirectPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$redirectActor)
    New-Item -ItemType Junction -Path $redirectPath -Target $outside|Out-Null
    $env:CODEX_THREAD_ID=$redirectActor
    $redirect=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $pendingPath -ExpectedPendingIdentity (Get-Identity $pendingPath) -ReceivedDelegationId $delegationId 2>&1|ForEach-Object{[string]$_});$redirectCode=$LASTEXITCODE
    Assert-True ($redirectCode-ne0-and($redirect-join"`n").Contains('RECEIVER_OUTPUT_REPARSE')-and@(Get-ChildItem -LiteralPath $outside -Force).Count-eq0) 'receiver-rejects-output-junction-before-any-external-write'
  }finally{$env:CODEX_THREAD_ID=$oldHostId}

  $investigatorActor='01a0eeee-2222-7222-8333-444444444444';$investigatorId='fixture-initial-investigator-001'
  $investigatorTemplate=New-Package 'STANDARD' 'TASK_OWNER' 'UNBOUND_RECEIVER' 'TEST_RUN' 'ROUTINE_LOCAL'
  $investigatorTemplate.schemaVersion=2;$investigatorTemplate['repositoryId']='REPO_LOCAL';$investigatorTemplate.invalidatesOn+=@('REPOSITORY_CHANGE')
  $investigatorPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-investigator.json'
  Write-Json $investigatorPending ([ordered]@{schemaVersion=1;delegationId=$investigatorId;receiverRole='INVESTIGATOR';authorizationTemplate=$investigatorTemplate})
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$investigatorActor
    $investigatorBind=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $investigatorPending -ExpectedPendingIdentity (Get-Identity $investigatorPending) -ReceivedDelegationId $investigatorId 2>&1|ForEach-Object{[string]$_});$investigatorCode=$LASTEXITCODE
    $investigatorPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$investigatorActor+'/receiver-authorization-'+$investigatorId+'.json')
    $investigatorBound=if(Test-Path -LiteralPath $investigatorPath -PathType Leaf){Get-Content $investigatorPath -Raw|ConvertFrom-Json -Depth 100}else{$null}
    Assert-True ($investigatorCode-eq0-and$null-ne$investigatorBound-and(Invoke-Check $investigatorBound $investigatorActor TEST_RUN).Code-eq0) 'receiver-bound-investigator-admits-exact-test-run'
  }finally{$env:CODEX_THREAD_ID=$oldHostId}

  }
  if($Group-ceq'PackageShape'){
  $planned=New-Package 'STANDARD' 'TASK_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL';$planned.actions=@('SOURCE_WRITE','TEST_RUN');$planned|Add-Member -NotePropertyName continuationPlan -NotePropertyValue @('SOURCE_WRITE','TEST_RUN','SOURCE_WRITE');$planned.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $plannedInitial=Invoke-Check $planned 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($plannedInitial.Code-eq0) 'authorization-temporary-actor-multi-action-plan-admits-first-step'
  $longPlan=$planned|ConvertTo-Json -Depth 50|ConvertFrom-Json;$longPlan.continuationPlan=@(1..20|ForEach-Object{if($_%2){'SOURCE_WRITE'}else{'TEST_RUN'}})
  Assert-True ((Invoke-Check $longPlan 'executor-fixture' 'SOURCE_WRITE').Code-eq0) 'continuation-accepts-twenty-explicit-bounded-steps'
  $plannedSkip=Invoke-Check $planned 'executor-fixture' 'TEST_RUN'
  Assert-True ($plannedSkip.Code-ne0-and$plannedSkip.Text.Contains('CONTINUATION_ACTION_ORDER_DRIFT')) 'authorization-continuation-plan-rejects-skipped-first-step'
  $missingContinuationInvalidator=$planned|ConvertTo-Json -Depth 50|ConvertFrom-Json;$missingContinuationInvalidator.invalidatesOn=@($missingContinuationInvalidator.invalidatesOn|Where-Object{$_-cne'CONTINUATION_RESULT_DRIFT'});$missingContinuationInvalidatorRun=Invoke-Check $missingContinuationInvalidator 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($missingContinuationInvalidatorRun.Code-ne0-and$missingContinuationInvalidatorRun.Text.Contains('INVALIDATOR_MISSING_CONTINUATION_RESULT_DRIFT')) 'authorization-continuation-plan-requires-result-drift-invalidator'

  $lowerDecision=Invoke-Check (New-Package 'STANDARD' 'TASK_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'routine_local') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($lowerDecision.Code-ne0-and$lowerDecision.Text.Contains('DECISION_CLASS')) 'authorization-decision-class-is-case-sensitive'

  $lowerController=Invoke-Check (New-Package 'STANDARD' 'project_controller' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL' 'controller-fixture') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($lowerController.Code-ne0-and$lowerController.Text.Contains('ISSUER_ROLE')) 'authorization-controller-role-is-case-sensitive'

  }
  if($Group-ceq'BindingIndependence'){
  # Review dispatch uses the already current task and candidate. When a card
  # still points at the previous freeze, update it before preparing the package.
  Write-Task 'CRITICAL' 'REVIEW'
  $reviewCardBase=Get-Content -Raw -LiteralPath $taskPath
  Write-Utf8 $taskPath ($reviewCardBase.TrimEnd()+"`nCandidate freeze: old-fixture-freeze`n")
  $beforeCardRefresh=New-Package 'CRITICAL' 'TASK_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  Write-Utf8 $taskPath ($reviewCardBase.TrimEnd()+"`nCandidate freeze: current-fixture-freeze`n")
  $currentReview=New-Package 'CRITICAL' 'TASK_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  Assert-True ((Invoke-Check $beforeCardRefresh reviewer-fixture REVIEW_EXECUTE).Code-ne0-and(Invoke-Check $currentReview reviewer-fixture REVIEW_EXECUTE).Code-eq0) 'review-dispatch-refreshes-stale-card-before-binding-current-package'
  $currentCardIdentity=Get-Identity $taskPath
  Assert-True ((Invoke-Check $currentReview reviewer-fixture REVIEW_EXECUTE).Code-eq0-and(Get-Identity $taskPath)-ceq$currentCardIdentity) 'review-dispatch-reuses-already-current-card-without-extra-write'
  Write-Utf8 $taskPath ((Get-Content -Raw -LiteralPath $taskPath).TrimEnd()+"`nCandidate result: changed after dispatch`n")
  Assert-True ((Invoke-Check $currentReview reviewer-fixture REVIEW_EXECUTE).Code-ne0) 'review-dispatch-rejects-real-task-drift-after-send'

  Write-Task 'CRITICAL' 'REVIEW'
  $critical=Invoke-Check (New-Package 'CRITICAL' 'TASK_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL') 'reviewer-fixture' 'REVIEW_EXECUTE'
  Assert-True ($critical.Code-eq0) 'authorization-canonical-independent-critical-review-passes'

  $internal=New-Package 'CRITICAL' 'TASK_OWNER' 'visible-reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  $internalCheck=Invoke-Check $internal 'visible-reviewer-fixture' 'REVIEW_EXECUTE'
  Assert-True ($internalCheck.Code-eq0) 'review-authorization-accepts-distinct-visible-actor-with-bound-identity'
  foreach($excluded in @('owner-fixture','writer-fixture','contributor-fixture')){
    $bad=New-Package 'CRITICAL' 'TASK_OWNER' $excluded 'REVIEW_EXECUTE' 'ROUTINE_LOCAL';$bad.materialContributors=@('contributor-fixture')
    $badCheck=Invoke-Check $bad $excluded 'REVIEW_EXECUTE'
    Assert-True ($badCheck.Code-ne0) ('reviewer-role-does-not-waive-identity-exclusion-'+$excluded)
  }
  $unknownCheck=Invoke-Check $internal 'unknown-reviewer-actor' 'REVIEW_EXECUTE'
  Assert-True ($unknownCheck.Code-ne0) 'review-authorization-rejects-unbound-actual-reviewer-identity'

  # Vary only profile on a complete, otherwise valid independent Review.
  $lowerProfilePackage=New-Package 'CRITICAL' 'TASK_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  $lowerProfilePackage.profile='critical'
  $lowerProfile=Invoke-Check $lowerProfilePackage 'reviewer-fixture' 'REVIEW_EXECUTE'
  Assert-True ($lowerProfile.Code-ne0-and'PROFILE'-cin@($lowerProfile.Text-split'[|,\r\n]')) 'authorization-critical-profile-is-case-sensitive'

  $profileMismatchPackage=New-Package 'CRITICAL' 'TASK_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL'
  $profileMismatchPackage.profile='STANDARD'
  $profileMismatch=Invoke-Check $profileMismatchPackage 'reviewer-fixture' 'REVIEW_EXECUTE'
  Assert-True ($profileMismatch.Code-ne0-and'TASK_PROFILE_DRIFT'-cin@($profileMismatch.Text-split'[|,\r\n]')) 'authorization-package-profile-matches-task-range-profile'
  $grantRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Group','ExternalGrant') -GroupId 'authorization-existing-resource-grants'
  foreach($line in $grantRun.Output){if($line-cnotmatch'^RESULT\|'){Write-Output $line}}
  $script:passed+=@($grantRun.Output|Where-Object{$_-cmatch'^PASS\|'}).Count
  Assert-True ($grantRun.Code-eq0) 'external-grant-native-branch-in-normal-binding-regression'
  Write-GroupCompletion;return
  }
  if($Group-ceq'PackageShape'){
  Write-Task 'CRITICAL' 'IMPLEMENT'
  $parent=New-Package 'CRITICAL' 'TASK_OWNER' 'writer-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL'
  $parent.repairReviewPlan=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@()}
  $parentCheck=Invoke-Check $parent 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($parentCheck.Code-eq0) 'owner-can-preauthorize-bounded-repair-review-without-changing-work-route'
  $overlap=$parent|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64
  $overlap.repairReviewPlan.materialContributors=@('owner-fixture','expert-fixture')
  Assert-True ((Invoke-Check $overlap writer-fixture SOURCE_WRITE).Code-eq0) 'owner-issuer-real-contributor-overlap-is-legal-in-parent-plan'
  foreach($contributors in @(@('writer-fixture'),@('expert-fixture','expert-fixture'),@(''))){
    $bad=$overlap|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$bad.repairReviewPlan.materialContributors=@($contributors)
    $rejected=Invoke-Check $bad writer-fixture SOURCE_WRITE
    Assert-True ($rejected.Code-ne0-and$rejected.Text.Contains('MATERIAL_CONTRIBUTOR_SET')) 'invalid-internal-contributor-set-refuses-before-child'
  }

  $largerPlan=$parent|ConvertTo-Json -Depth 50|ConvertFrom-Json;$largerPlan.repairReviewPlan.maxCycles=12
  Assert-True ((Invoke-Check $largerPlan 'writer-fixture' 'SOURCE_WRITE').Code-eq0) 'repair-review-accepts-task-selected-finite-plan-over-eight'
  $largerPlan.repairReviewPlan.maxCycles=0
  Assert-True ((Invoke-Check $largerPlan 'writer-fixture' 'SOURCE_WRITE').Code-ne0) 'repair-review-still-requires-positive-bounded-plan'
  $parentPath=Join-Path $control 'repair-parent.json';Write-Json $parentPath $parent
  $verdict=[ordered]@{taskId='AUTH-REGRESSION-001';owner='owner-fixture';reviewer='reviewer-fixture';writer='writer-fixture';cycle=0;verdict='CHANGES_REQUESTED';exactPaths=@($objectRelative);objectIdentities=@($parent.objectIdentities);findingPaths=@($objectRelative);scopeChanged=$false;decisionChanged=$false}
  $verdictPath=Join-Path $control 'repair-verdict.json';Write-Json $verdictPath $verdict
  $binding=[ordered]@{parentPackagePath=$parentPath;parentPackageIdentity=(Get-Identity $parentPath);phase='REPAIR';cycle=1;verdictPath=$verdictPath;verdictIdentity=(Get-Identity $verdictPath);repairFinalizeInputPath='NOT_APPLICABLE';repairFinalizeInputIdentity='NOT_APPLICABLE';repairFinalizeResultPath='NOT_APPLICABLE';repairFinalizeResultIdentity='NOT_APPLICABLE'}
  $routeInput=Join-Path $control 'repair-route.json';Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  $routeOutput=@(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)
  $routeCode=$LASTEXITCODE
  Assert-True ($routeCode-ne0-and($routeOutput-join" ").Contains('REPAIR_REVIEW_FINALIZED_TYPED_VERDICT_REQUIRED')) 'flat-only-finding-cannot-prepare-a-repair-grant'
  $child=$parent|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64
  $child.PSObject.Properties.Remove('repairReviewPlan');$child|Add-Member repairReviewBinding $binding
  $childCheck=Invoke-Check $child 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($childCheck.Code-ne0-and$childCheck.Text.Contains('FINALIZED_TYPED_VERDICT_REQUIRED')) 'flat-only-child-fails-real-checker'
  $badChild=$child|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badChild.repairReviewBinding.cycle=3
  $badCheck=Invoke-Check $badChild 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_CYCLE')) 'repair-cycle-exhaustion-requires-owner'
  $badChild=$child|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badChild.repairReviewBinding.verdictIdentity='1|'+('0'*64)
  $badCheck=Invoke-Check $badChild 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_EVIDENCE_DRIFT')) 'stale-verdict-cannot-authorize-repair'
  $verdict.scopeChanged=$true;Write-Json $verdictPath $verdict
  $badChild=$child|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badChild.repairReviewBinding.verdictIdentity=Get-Identity $verdictPath
  $badCheck=Invoke-Check $badChild 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_VERDICT_BOUNDARY')) 'broadened-impact-does-not-use-focused-repair'
  $badParent=$parent|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64;$badParent.repairReviewPlan.reviewer='writer-fixture'
  $badCheck=Invoke-Check $badParent 'writer-fixture' 'SOURCE_WRITE'
  Assert-True ($badCheck.Code-ne0-and$badCheck.Text.Contains('REPAIR_REVIEW_INDEPENDENCE')) 'bounded-plan-never-waives-reviewer-independence'

  Write-GroupCompletion;return
  }
  # Minimal real shared preparation for the two protocol groups.
  Write-Task STANDARD IMPLEMENT
  $parent=New-Package STANDARD TASK_OWNER writer-fixture SOURCE_WRITE ROUTINE_LOCAL
  $parent['repairReviewPlan']=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@()}
  $parentPath=Join-Path $control 'repair-parent.json';Write-Json $parentPath $parent
  $verdict=[ordered]@{taskId='AUTH-REGRESSION-001';owner='owner-fixture';reviewer='reviewer-fixture';writer='writer-fixture';cycle=0;verdict='CHANGES_REQUESTED';exactPaths=@($objectRelative);objectIdentities=@($parent.objectIdentities);findingPaths=@($objectRelative);scopeChanged=$false;decisionChanged=$false}
  $verdictPath=Join-Path $control 'repair-verdict.json';Write-Json $verdictPath $verdict
  $binding=[ordered]@{parentPackagePath=$parentPath;parentPackageIdentity=(Get-Identity $parentPath);phase='REPAIR';cycle=1;verdictPath=$verdictPath;verdictIdentity=(Get-Identity $verdictPath);repairFinalizeInputPath='NOT_APPLICABLE';repairFinalizeInputIdentity='NOT_APPLICABLE';repairFinalizeResultPath='NOT_APPLICABLE';repairFinalizeResultIdentity='NOT_APPLICABLE'}
  $routeInput=Join-Path $control 'repair-route.json'
  # Exercise actual DISCOVER -> ADMIT -> write -> FINALIZE -> independent rereview.
  # Stable metadata below exists only inside the isolated test fixture.
  $frameworkRoot=Join-Path $temp 'framework-root';$fixtureVersion=[IO.Path]::GetFullPath((Join-Path $frameworkRoot 'framework/versions/2.0.0'))
  $sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
  $fixtureVersion=New-AiwTestMechanismFixture $sourceRoot $frameworkRoot (Join-Path $PSScriptRoot 'test-groups.json')
  Write-Json (Join-Path $control 'corrections.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='authorization-receipt-fixture';corrections=@()})
  Write-Utf8 (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
  Write-Json (Join-Path $control 'process-policy.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='authorization-receipt-fixture';rules=@()})
  $cfg=Get-Content (Join-Path $control 'project.json') -Raw|ConvertFrom-Json;$cfg.schemaVersion=7;$cfg|Add-Member -Force -NotePropertyName processPolicy -NotePropertyValue ([pscustomobject]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'});Write-Json (Join-Path $control 'project.json') $cfg
  Write-Task STANDARD IMPLEMENT
  $parent=New-Package STANDARD TASK_OWNER writer-fixture SOURCE_WRITE ROUTINE_LOCAL
  $parent.actions=@('SOURCE_WRITE','TEST_RUN');$parent.continuationPlan=@('SOURCE_WRITE','TEST_RUN');$parent.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $parent.repairReviewPlan=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@()};Write-Json $parentPath $parent
  $verdict.scopeChanged=$false;$verdict.objectIdentities=$parent.objectIdentities;Write-Json $verdictPath $verdict
  $binding.parentPackageIdentity=Get-Identity $parentPath;$binding.verdictIdentity=Get-Identity $verdictPath
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  # Initial shared fixture has no independent finding yet. Only its parent can act.
  $prepared=[pscustomobject]@{package=$parent}
  $childPath=Join-Path $control 'repair-child.json';Write-Json $childPath $prepared.package
  $resolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
  $script:FixtureReviewFinalizes=@{}
  $script:LifecycleInputCleanup=[Collections.Generic.List[object]]::new()
  function Run-Process($Value,[string]$Name,[switch]$AllowFailure,[ValidateSet('APPROVED','CHANGES_REQUESTED','REJECTED','INCOMPLETE')][string]$ReviewOutcome='APPROVED',[switch]$UseProvidedEvidence,[string[]]$FindingPaths=@(),[string[]]$ConsumedRuntimePath=@(),[switch]$KeepInputForRecovery,[switch]$ConsumeFinalInput){
    # Explicit isolated model-judgment fixtures exercise the protocol. Production
    # callers must provide their own actual records, never synthesize PASS here.
    $kind=''
    if($Value.mode-cin@('ADMIT_ACTION','FINALIZE_OUTPUT')){
      $receipt=Get-Content $Value.discoverReceiptPath -Raw|ConvertFrom-Json -Depth 100
      $action=$receipt.intentEnvelope.requestedActionKind
      $kind=if($Value.mode-ceq'ADMIT_ACTION'-and$action-ceq'REVIEW_ROUTE'){'SELF_CHECK'}elseif($Value.mode-ceq'FINALIZE_OUTPUT'-and$action-ceq'TEST_RUN'){'SELF_CHECK'}elseif($Value.mode-ceq'FINALIZE_OUTPUT'-and$action-ceq'REVIEW_EXECUTE'){'REVIEW_VERDICT'}else{''}
      if($kind-and-not$UseProvidedEvidence){
        $requirementsPath=Join-Path $control ($Name+'-fixture-requirements.md');Write-Utf8 $requirementsPath ('Protocol fixture: '+$Name+'. Observe the existing candidate and the specified actor, independently of real project acceptance.')
        $requirements=[ordered]@{path=$requirementsPath;identity=Get-Identity $requirementsPath}
        $candidates=@($receipt.binding.exactScope|ForEach-Object{$p=Join-Path $temp $_;[ordered]@{path=$_;identity=$(if(Test-Path -LiteralPath $p -PathType Leaf){Get-Identity $p}else{'MISSING'})}})
        $record=[ordered]@{schemaVersion=1;taskId=$receipt.binding.taskId;actor=$receipt.binding.actor;candidateObjects=$candidates;requirementsRef=$requirements;outcome=$(if($kind-ceq'REVIEW_VERDICT'){$ReviewOutcome}else{'PASS'});checks=@([ordered]@{id=$Name;method='MODEL_JUDGMENT';outcome='PASS';reason='Isolated semantic-observation fixture, not a real external Reviewer or product acceptance.';evidenceLocators=@($requirements)});evidenceLocators=@($requirements)}
        if($action-ceq'TEST_RUN'){
          # Real test evidence for these produced candidates; model Review stays separate.
          if($candidates.Count-ne1-or$candidates[0].path-cne$objectRelative){throw 'FIXTURE_TEST_CANDIDATE_SCOPE'}
          $expectedText=switch -CaseSensitive ($Name){
            'initial-test-finalize' {'Initial candidate awaiting independent judgment'}
            'late-test-finalize' {'Late reviewer candidate after production'}
            'combined-test-finalize' {'Combined candidate awaiting independent judgment'}
            default {throw ('FIXTURE_TEST_SCENARIO_REQUIRED|'+$Name)}
          }
          $probe=Join-Path $control ($Name+'-candidate-check.ps1')
          Write-Utf8 $probe @'
param([string]$Candidate,[string]$ExpectedIdentity,[string]$ExpectedText)
$ErrorActionPreference='Stop'
$bytes=[IO.File]::ReadAllBytes($Candidate)
$identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
if($identity-cne$ExpectedIdentity){Write-Output 'FAIL|candidate-identity-drift';exit 1}
if([Text.Encoding]::UTF8.GetString($bytes).TrimEnd("`n")-cne$ExpectedText){Write-Output 'FAIL|candidate-scenario-content';exit 1}
Write-Output ('PASS|actual-continuation-candidate|'+$identity);exit 0
'@
          $commandArgs=@('-NoProfile','-NonInteractive','-File',$probe,'-Candidate',$objectPath,'-ExpectedIdentity',$candidates[0].identity,'-ExpectedText',$expectedText)
          $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) $commandArgs -WorkingDirectory $temp -GroupId 'continuation-actual-produced-candidate'
          $stdout=Join-Path $control ($Name+'-actual-stdout.txt');[IO.File]::WriteAllBytes($stdout,[IO.File]::ReadAllBytes($run.Record.stdout.path))
          $commandPath=Join-Path $control ($Name+'-actual-command.json')
          Write-Json $commandPath ([ordered]@{command=([Environment]::ProcessPath)+' '+(($commandArgs|ForEach-Object{"'"+$_.Replace("'","''")+"'"})-join' ');exitCode=$run.Code;output=[ordered]@{path=$stdout;identity=Get-Identity $stdout}})
          $commandRef=[ordered]@{path=$commandPath;identity=Get-Identity $commandPath};$outcome=if($run.Code-eq0){'PASS'}else{'FAIL'}
          $record.outcome=$outcome
          $record.checks=@([ordered]@{id=$Name;method='COMMAND';outcome=$outcome;reason='Actual isolated subprocess checks the produced scenario content and complete current candidate identity; raw native stdout/stderr and exit are preserved.';evidenceLocators=@($commandRef)})
          $record.evidenceLocators+=@($commandRef)
        }
        if($kind-ceq'REVIEW_VERDICT'){
          $record.authorizationRef=[ordered]@{path=$receipt.sourceLocators.authorizationPackagePath;identity=Get-Identity $receipt.sourceLocators.authorizationPackagePath}
          $reviewPackage=Get-Content -LiteralPath $receipt.sourceLocators.authorizationPackagePath -Raw|ConvertFrom-Json -Depth 100
          if($null-ne$reviewPackage.PSObject.Properties['repairReviewBinding']){
            $flat=[ordered]@{taskId=$reviewPackage.taskId;owner=$reviewPackage.owner;reviewer=$reviewPackage.grantee;writer=$reviewPackage.candidateWriter;cycle=$reviewPackage.repairReviewBinding.cycle;verdict=$ReviewOutcome;exactPaths=@($reviewPackage.exactPaths);objectIdentities=@($reviewPackage.objectIdentities);findingPaths=@(if($ReviewOutcome-ceq'CHANGES_REQUESTED'){if($FindingPaths.Count){$FindingPaths}else{$reviewPackage.exactPaths}});scopeChanged=$false;decisionChanged=$false}
            $flatPath=Join-Path $control ($Name+'-reviewer-flat-verdict.json');Write-Json $flatPath $flat
            $record.evidenceLocators+=@([ordered]@{path=$flatPath;identity=Get-Identity $flatPath})
          }
        }
        $evidencePath=Join-Path $control ($Name+'-typed-evidence.json');Write-Json $evidencePath $record
        $refs=@([ordered]@{kind=$kind;path=$evidencePath;identity=Get-Identity $evidencePath})
        $Value.schemaVersion=3
        if($Value-is[Collections.IDictionary]){$Value['evidenceRefs']=$refs}else{$Value|Add-Member evidenceRefs $refs -Force}
      }
      if($Value.mode-ceq'FINALIZE_OUTPUT'-and$action-cin@('REVIEW_ROUTE','REVIEW_EXECUTE')){
        # Explicit mocked host result for this isolated protocol fixture. This
        # does not send a message or claim a natural user/host success.
        $sourcePackage=Get-Content $receipt.sourceLocators.authorizationPackagePath -Raw|ConvertFrom-Json -Depth 100
        $recipient=if($action-ceq'REVIEW_EXECUTE'){if($ReviewOutcome-ceq'APPROVED'){$sourcePackage.owner}else{$sourcePackage.candidateWriter}}elseif($null-ne$sourcePackage.PSObject.Properties['repairReviewPlan']){$sourcePackage.repairReviewPlan.reviewer}else{'reviewer-fixture'}
        if($action-ceq'REVIEW_EXECUTE'-and$ReviewOutcome-ceq'CHANGES_REQUESTED'-and$FindingPaths.Count-and$null-ne$sourcePackage.PSObject.Properties['repairReviewBinding']){
          $plannedParent=Get-Content -LiteralPath $sourcePackage.repairReviewBinding.parentPackagePath -Raw|ConvertFrom-Json -Depth 100
          if(@($FindingPaths|Where-Object{$_-cnotin$plannedParent.exactPaths}).Count){$recipient=$sourcePackage.owner}
        }
        $assignment=$null
        if($recipient-ceq'DEFERRED_VISIBLE_REVIEWER'){
          $recipient=$combinedReviewer
          $assignment=[ordered]@{source='HOST_CREATE_THREAD_RESULT';createdBy=$receipt.binding.actor;threadId=$recipient;hostId='fixture-host';taskId=$receipt.binding.taskId;parentPackageIdentity=Get-Identity $receipt.sourceLocators.authorizationPackagePath}
        }
        $hostPath=Join-Path $control ($Name+'-mock-host.json');Write-Json $hostPath ([ordered]@{isError=$false;content=@([ordered]@{type='text';text=('{"threadId":"'+$recipient+'"}')})})
        $context=[ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient=$recipient;observedRecipient=$recipient;outcome='SUCCESS';evidence=($hostPath+'#'+(Get-Identity $hostPath))}
        if($null-ne$Value.PSObject.Properties['deliveryContext']-and$null-ne$Value.deliveryContext.PSObject.Properties['reviewPackageRef']){$context.reviewPackageRef=$Value.deliveryContext.reviewPackageRef}
        if($null-ne$assignment){$context.reviewerAssignment=$assignment}
        if($Value-is[Collections.IDictionary]){$Value['deliveryContext']=$context}else{$Value|Add-Member deliveryContext $context -Force}
        $Value.deliveryReceipts=@()
      }
    }
    $ephemeralInput=$LifecycleOnly-and($Value.mode-cne'FINALIZE_OUTPUT'-or$ConsumeFinalInput)
    $inputDirectory=if($ephemeralInput){$inputActor=if($Value.mode-ceq'DISCOVER'){$Value.observedActor}else{$receipt.binding.actor};Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$inputActor)}else{$control}
    $p=Join-Path $inputDirectory ($Name+'.json');Write-Json $p $Value
    $inputLock=$null
    try{
    if($KeepInputForRecovery){$inputLock=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}
    if($ConsumedRuntimePath.Count){
      Import-Module (Join-Path $fixtureVersion 'scripts/WorkflowDelivery.psm1')
      if($null-ne$Value.PSObject.Properties['deliveryContext']){$observed=Invoke-AiwDeliveryBoundary ([pscustomobject]@{path=$p;identity=(Get-Identity $p)}) -ConsumedRuntimePath $ConsumedRuntimePath}
      else{Import-Module (Join-Path $fixtureVersion 'scripts/ProcessRequirementBoundary.psm1');$response=Invoke-AiwProcessRequirementBoundary -InputPath $p -AsJson -ConsumedRuntimePath $ConsumedRuntimePath -DeleteInputOnExit:$ephemeralInput;$observed=($response.output-join"`n")|ConvertFrom-Json -Depth 100}
      $out=@($observed|ConvertTo-Json -Depth 100 -Compress);$global:LASTEXITCODE=if($observed.status-ceq'PASS'){0}else{3}
    }elseif($ephemeralInput){$out=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $p -DeleteInputOnExit -AsJson)}
    else{$out=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $p -AsJson)}
    }finally{if($null-ne$inputLock){$inputLock.Dispose()}}
    if($LASTEXITCODE-ne0-and-not$AllowFailure){throw ('REAL_PROCESS_FAILED|'+$Name+'|'+($out-join"`n"))}
    $actual=($out-join"`n")|ConvertFrom-Json -Depth 100
    if($null-ne$actual.PSObject.Properties['inputCleanup']){$script:LifecycleInputCleanup.Add($actual.inputCleanup)}
    if(-not$UseProvidedEvidence-and$kind-ceq'REVIEW_VERDICT'-and$Value.mode-ceq'FINALIZE_OUTPUT'-and$actual.status-ceq'PASS'-and$null-ne$reviewPackage.PSObject.Properties['repairReviewBinding']){
      $resultPath=Join-Path $control ($Name+'-actual-result.json');Write-Json $resultPath $actual
      $script:FixtureReviewFinalizes[$Name]=[pscustomobject]@{verdictPath=$flatPath;verdictIdentity=(Get-Identity $flatPath);verdictFinalizeInputPath=$p;verdictFinalizeInputIdentity=(Get-Identity $p);verdictFinalizeResultPath=$resultPath;verdictFinalizeResultIdentity=(Get-Identity $resultPath)}
    }
    return $actual
  }
  $discover=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath=$taskPath;expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json');expectedTaskIdentity=Get-Identity $taskPath;observedActor='writer-fixture';capabilities=@();exactPaths=@($objectRelative);forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath=$childPath;expectedAuthorizationIdentity=Get-Identity $childPath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=2;facets=[ordered]@{domain=[ordered]@{state='KNOWN';values=@('aiw:software','aiw:governance')};workType=[ordered]@{state='KNOWN';values=@('aiw:implementation')};deliverableType=[ordered]@{state='KNOWN';values=@('aiw:code')};stage=[ordered]@{state='KNOWN';values=@('aiw:implementation')}};objective='Repair the accepted bounded finding and return its terminal result';requestedActionKind='SOURCE_WRITE';requestedResultKind='TERMINAL';semanticHints=@('repair');pathHints=@($objectRelative);capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
  if($Group-cin@('FocusedBoundaries','FocusedEvidence')){Invoke-FocusedBoundaries -EvidenceOnly:($Group-ceq'FocusedEvidence');Write-GroupCompletion;return}
  if($Group-ceq'DeliveryAcceptance'){
  # Reuse the real process fixture for archive closure and explicit Owner return.
  # No synthetic SELF/verdict is added to this CONTROL_WRITE action.
  $savedTaskBytes=[IO.File]::ReadAllBytes($taskPath)
  Write-Task STANDARD IMPLEMENT -OwnerRoute
  $archiveActive='.ai-workspace/tasks/active/ARCHIVED-001.md';$archiveTarget='.ai-workspace/tasks/archive/ARCHIVED-001.md';$archivePaths=@($archiveActive,$archiveTarget)
  # This other task is already closed before its ordinary archive grant.
  # Its non-success history is fixture setup, not a fabricated acceptance.
  $archiveDecision=Join-Path $control 'archive-closure-decision.txt'
  Write-Utf8 $archiveDecision 'SIMULATED original decision: supersede ARCHIVED-001; transfer its unfinished fixture checks to AUTH-REGRESSION-001 and retain its original history.'
  $archiveOld="# ARCHIVED-001 - finite fixture`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=CLOSED; expected_paths=[$objectRelative]; actual_paths=[]`n- Closure outcome: SUPERSEDED`n- Closure basis: fixture explicit successor; original history retained.`n- Output disposition: DEFERRED; retained fixture history, unfinished checks transferred to AUTH-REGRESSION-001.`n- Git disposition: EXCLUDED; isolated protocol fixture with no deliverable commit.`n- Unresolved obligations: TRANSFERRED: AUTH-REGRESSION-001 owns the remaining fixture checks.`n- Unfinished work: finite fixture checks remain with AUTH-REGRESSION-001.`n- Closure decision: .ai-workspace/archive-closure-decision.txt#$(Get-Identity $archiveDecision)`n- Writer: RELEASED`n- Reviewer: RELEASED`n- Authorization: RELEASED`n"
  Write-Utf8 (Join-Path $temp $archiveActive) $archiveOld
  $archiveBytes=[IO.File]::ReadAllBytes((Join-Path $temp $archiveActive));$archiveOriginalIdentity=Get-Identity (Join-Path $temp $archiveActive)
  $archiveGrant=New-Package STANDARD TASK_OWNER owner-fixture CONTROL_WRITE ROUTINE_LOCAL
  $archiveGrant.exactPaths=$archivePaths;$archiveGrant.objectIdentities=@([ordered]@{path=$archiveActive;identity=Get-Identity (Join-Path $temp $archiveActive)},[ordered]@{path=$archiveTarget;identity='NEW'})
  $archiveCheck=Invoke-Check $archiveGrant owner-fixture CONTROL_WRITE $archivePaths
  Assert-True ($archiveCheck.Code-eq0) 'archive-exact-two-original-checker-pass'
  $archiveGrantPath=Join-Path $control 'archive-grant.json';Write-Json $archiveGrantPath $archiveGrant
  $archiveDiscover=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $archiveDiscover.observedActor='owner-fixture';$archiveDiscover.expectedTaskIdentity=Get-Identity $taskPath;$archiveDiscover.authorizationPackagePath=$archiveGrantPath;$archiveDiscover.expectedAuthorizationIdentity=Get-Identity $archiveGrantPath;$archiveDiscover.exactPaths=$archivePaths
  $archiveDiscover.intentEnvelope.requestedActionKind='CONTROL_WRITE';$archiveDiscover.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$archiveDiscover.intentEnvelope.pathHints=$archivePaths;$archiveDiscover.intentEnvelope.mutationHints=@('control');$archiveDiscover.intentEnvelope.objective='Archive a superseded finite task with its original deletion proof'
  $archiveDiscovery=Run-Process $archiveDiscover 'archive-real-discover'
  $archiveCompact=Join-Path $control 'archive-compact.json';Write-Json $archiveCompact $archiveDiscovery.compactReceipt
  $archiveBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$archiveCompact;expectedDiscoverReceiptIdentity=Get-Identity $archiveCompact;preparationReceipts=@($archiveDiscovery.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  Assert-True ((Run-Process $archiveBoundary 'archive-real-admit').status-ceq'PASS') 'archive-original-real-admission'
  $archiveClosed=$archiveOld
  New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $temp $archiveTarget)) -Force|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $temp $archiveTarget),$archiveBytes)
  Assert-True ((Get-Identity (Join-Path $temp $archiveTarget))-ceq$archiveOriginalIdentity-and(Get-Identity (Join-Path $temp $archiveActive))-ceq$archiveOriginalIdentity) 'archive-readback-and-active-preimage-match-before-delete'
  [IO.File]::Delete((Join-Path $temp $archiveActive))
  $archiveBoundary.mode='FINALIZE_OUTPUT';$archiveBoundary.resultReceipts=@($archiveDiscovery.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@(('OBJECT_POSTIMAGE|'+$archiveActive+'|MISSING'),('OBJECT_POSTIMAGE|'+$archiveTarget+'|'+(Get-Identity (Join-Path $temp $archiveTarget))))
  if($LegacyArchiveResolverPath){
    $oldResolver=$resolver;try{$resolver=$LegacyArchiveResolverPath;$oldArchive=Run-Process $archiveBoundary 'archive-original-old-failure' -AllowFailure}finally{$resolver=$oldResolver}
    Assert-True ($oldArchive.status-ceq'FAIL'-and$oldArchive.reason-ceq'EVIDENCE_OBJECT_MISSING') 'archive-unmodified-old-result-validator-reproduces-exact-failure'
  }
  Assert-True ((Run-Process $archiveBoundary 'archive-real-finalize').status-ceq'PASS') 'archive-new-result-validator-finalizes-original-exact-postimages'
  $invalidArchive=$archiveBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$invalidArchive.resultReceipts=@($invalidArchive.resultReceipts|Where-Object{$_-cnotlike('OBJECT_POSTIMAGE|'+$archiveActive+'|*')})
  $invalidResult=Run-Process $invalidArchive 'archive-missing-receipt' -AllowFailure
  Assert-True ($invalidResult.status-ceq'FAIL'-and$invalidResult.reason-ceq('RESULT_POSTIMAGE_RECEIPT_REQUIRED|'+$archiveActive)) 'archive-integration-reaches-missing-postimage-guard'
  $invalidArchive=$archiveBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$invalidArchive.resultReceipts[-1]='OBJECT_POSTIMAGE|'+$archiveTarget+'|0|'+('0'*64)
  $invalidResult=Run-Process $invalidArchive 'archive-wrong-postimage' -AllowFailure
  Assert-True ($invalidResult.status-ceq'FAIL'-and$invalidResult.reason-ceq('RESULT_POSTIMAGE_RECEIPT_REQUIRED|'+$archiveTarget)) 'archive-integration-rejects-wrong-postimage'
  $invalidArchive=$archiveBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$invalidArchive.resultReceipts+=@($invalidArchive.resultReceipts[-1])
  $invalidResult=Run-Process $invalidArchive 'archive-duplicate-postimage' -AllowFailure
  Assert-True ($invalidResult.status-ceq'FAIL'-and$invalidResult.reason-ceq'INPUT_ARRAY_ITEM|resultReceipts') 'archive-integration-rejects-duplicate-postimage'
  foreach($invalidCard in @(
    @{Name='changed-other-card-id';Text=$archiveClosed.Replace('# ARCHIVED-001','# WRONG-001');Reason='ACCEPTANCE_ARCHIVE_PREIMAGE_DRIFT'},
    @{Name='malformed-task-id';Text=$archiveClosed.Replace('# ARCHIVED-001','ARCHIVED-001');Reason='ACCEPTANCE_ARCHIVE_TASK_ID'},
    @{Name='not-closed';Text=$archiveClosed.Replace('lifecycle=CLOSED;','lifecycle=ACTIVE;');Reason='ACCEPTANCE_ARCHIVE_NOT_CLOSED'}
  )){
    Write-Utf8 (Join-Path $temp $archiveTarget) $invalidCard.Text
    $invalidIdentity=Get-Identity (Join-Path $temp $archiveTarget)
    $invalidArchive=$archiveBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$invalidArchive.resultReceipts[-1]='OBJECT_POSTIMAGE|'+$archiveTarget+'|'+$invalidIdentity
    $invalidResult=Run-Process $invalidArchive ('archive-'+$invalidCard.Name) -AllowFailure
    Assert-True ($invalidResult.status-ceq'FAIL'-and$invalidResult.reason-ceq$invalidCard.Reason-and(Get-Identity (Join-Path $temp $archiveTarget))-ceq$invalidIdentity-and-not(Test-Path -LiteralPath (Join-Path $temp $archiveActive))) ('archive-exact-refusal-without-overwrite-'+$invalidCard.Name)
  }
  [IO.File]::WriteAllBytes((Join-Path $temp $archiveTarget),$archiveBytes)
  Assert-True ((Get-Identity (Join-Path $temp $archiveTarget))-ceq$archiveOriginalIdentity-and(Run-Process $archiveBoundary 'archive-restored-finalize').status-ceq'PASS') 'archive-original-byte-restoration-finalizes-same-chain'
  $humanSource=Join-Path $control 'archive-original-human-fixture.txt';Write-Utf8 $humanSource 'SIMULATED human: deliver the result to exact task human-consumer-fixture.'
  $archiveBoundary.publicDecisionIdentity=Get-Identity $humanSource;$archiveBoundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='human-consumer-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';userDecisionRef=[ordered]@{path=$humanSource;identity=Get-Identity $humanSource}}
  $archivePrepared=Run-Process $archiveBoundary 'archive-owner-explicit-prepare' -AllowFailure
  Assert-True ($archivePrepared.status-ceq'BLOCKED'-and$archivePrepared.delivery.status-ceq'READY_TO_SEND') 'owner-explicit-cross-task-prepare-does-not-close'
  $archiveHost=Join-Path $control 'archive-simulated-host.json';Write-Json $archiveHost ([ordered]@{isError=$false;content=@([ordered]@{type='text';text='{"threadId":"human-consumer-fixture"}'})})
  $archiveBoundary.deliveryContext.stage='OBSERVE';$archiveBoundary.deliveryContext.outcome='SUCCESS';$archiveBoundary.deliveryContext.observedRecipient='human-consumer-fixture';$archiveBoundary.deliveryContext.evidence=$archiveHost+'#'+(Get-Identity $archiveHost)
  Assert-True ((Run-Process $archiveBoundary 'archive-owner-explicit-observe').status-ceq'PASS') 'owner-explicit-cross-task-observation-uses-bound-simulated-host'
  $noHuman=$archiveBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$noHuman.deliveryContext.PSObject.Properties.Remove('userDecisionRef')
  $invalidResult=Run-Process $noHuman 'archive-owner-no-human-ref' -AllowFailure
  Assert-True ($invalidResult.status-ceq'FAIL'-and$invalidResult.reason-ceq'DELIVERY_CONSUMER_CHANNEL_MISMATCH') 'owner-default-remains-native-without-explicit-human-ref'
  [IO.File]::WriteAllBytes($taskPath,$savedTaskBytes)
  if($ArchiveDeliveryOnly){Write-Output ('PASS|archive-delivery-integration|'+$passed+'/'+$passed);Write-GroupCompletion;return}
  }
  if($Group-ceq'ContinuationScope'){
    # Reuse the real producer/consumer fixture. Absolute bans are strings only;
    # the nonexistent outside-repository object is never inspected or created.
    $absoluteBan=([IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('aiw-unread-'+[guid]::NewGuid().ToString('N')+'/secret.txt')))).Replace('\','/')
    $absoluteProtected=([IO.Path]::GetFullPath((Join-Path $temp 'private/absolute-protected.txt'))).Replace('\','/')
    foreach($variant in @('LINEAR','SELF_REPAIR','CONTROL')){
      $controlVariant=$variant-ceq'CONTROL'
      $path=if($controlVariant){'.ai-workspace/reports/continuation-document.txt'}else{$objectRelative}
      $full=Join-Path $temp $path;Write-Utf8 $full ('scope preimage '+$variant)
      $pkg=New-Package STANDARD TASK_OWNER writer-fixture SOURCE_WRITE ROUTINE_LOCAL
      $pkg.actions=@($(if($controlVariant){'CONTROL_WRITE'}else{'SOURCE_WRITE'}),$(if($controlVariant){'REVIEW_ROUTE'}else{'TEST_RUN'}))
      $pkg['continuationPlan']=@($pkg.actions);$pkg.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
      $pkg.exactPaths=@($path);$pkg.objectIdentities=@(@{path=$path;identity=Get-Identity $full})
      if($variant-ceq'SELF_REPAIR'){$pkg['selfCheckRepairLimit']=2}
      $pp=Join-Path $control ('scope-'+$variant+'-package.json');Write-Json $pp $pkg
      $d=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      $d.schemaVersion=5;$d|Add-Member ruleLoad ([pscustomobject]@{mode='FULL'});$d.authorizationPackagePath=$pp;$d.expectedAuthorizationIdentity=Get-Identity $pp
      $d.exactPaths=@($path);$d.intentEnvelope.pathHints=@($path);$d.intentEnvelope.requestedActionKind=$pkg.actions[0];$d.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$d.intentEnvelope.mutationHints=@()
      $d.forbiddenPaths=@('private/',$absoluteBan);$d.protectedPaths=@($absoluteProtected)
      $r=Run-Process $d ('scope-'+$variant+'-discover');$rp=Join-Path $control ('scope-'+$variant+'-compact.json');Write-Json $rp $r.compactReceipt
      $b=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$rp;expectedDiscoverReceiptIdentity=Get-Identity $rp;preparationReceipts=@($r.compactReceipt.selectedObligations.preparationRequirements|Select-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
      $null=Run-Process $b ('scope-'+$variant+'-admit')
      Write-Utf8 $full ('scope actual postimage '+$variant)
      $b.mode='FINALIZE_OUTPUT';$b.resultReceipts=@($r.compactReceipt.selectedObligations.resultRequirements|Select-Object -Unique)+@('OBJECT_POSTIMAGE|'+$path+'|'+(Get-Identity $full))
      if($controlVariant){
        $req=Join-Path $control 'scope-document-requirements.txt';Write-Utf8 $req 'Isolated document must preserve the declared absolute exclusions through its real continuation.'
        $ref=@{path=$req;identity=Get-Identity $req};$self=Join-Path $control 'scope-document-self.json'
        Write-Json $self @{schemaVersion=1;taskId='AUTH-REGRESSION-001';actor='writer-fixture';candidateObjects=@(@{path=$path;identity=Get-Identity $full});requirementsRef=$ref;outcome='PASS';checks=@(@{id='scope-document-observation';method='MODEL_JUDGMENT';outcome='PASS';reason='Simulated document judgment in an isolated protocol fixture, with actual producer bytes.';evidenceLocators=@($ref)});evidenceLocators=@($ref)}
        $b.evidenceRefs=@(@{kind='SELF_CHECK';path=$self;identity=Get-Identity $self})
      }
      $f=Run-Process $b ('scope-'+$variant+'-finalize');$cp=Join-Path $control ('scope-'+$variant+'-continuation.json');Write-Json $cp $f.continuationReceipt
      $expectedSchema=if($variant-ceq'SELF_REPAIR'){2}else{1}
      Assert-True ($f.status-ceq'PASS'-and$f.continuationReceipt.schemaVersion-eq$expectedSchema-and$absoluteBan-cin@($f.continuationReceipt.forbiddenScope)-and$absoluteProtected-cin@($f.continuationReceipt.protectedScope)) ('continuation-real-production-preserves-absolute-protection-'+$variant)
      $checked=Invoke-Check $pkg writer-fixture $pkg.actions[1] @($path) $cp
      Assert-True ($checked.Code-eq0) ('continuation-real-checker-consumes-absolute-protection-'+$variant)
      if(-not$controlVariant){
        $next=$d|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$next|Add-Member continuationReceiptPath $cp;$next|Add-Member expectedContinuationReceiptIdentity (Get-Identity $cp)
        $next.intentEnvelope.requestedActionKind='TEST_RUN';$next.intentEnvelope.requestedResultKind='TEST_RESULT'
        $nextResult=Run-Process $next ('scope-'+$variant+'-successor-discover')
        Assert-True ($nextResult.status-ceq'PASS') ('continuation-real-successor-discover-consumes-absolute-protection-'+$variant)
      }
      foreach($badScope in @('../escape','private//child','C:relative.txt',($absoluteBan+':stream'),($absoluteBan+'/../escape'),($absoluteBan+'*'),($absoluteBan.Replace('/','\')),($absoluteBan+'/CON.txt'),($absoluteBan+'/trailing.'))){
        $bad=$f.continuationReceipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.forbiddenScope=@($badScope);Write-Json $cp $bad
        $rejected=Invoke-Check $pkg writer-fixture $pkg.actions[1] @($path) $cp
        Assert-True ($rejected.Code-ne0-and$rejected.Text-match'CONTINUATION_RECEIPT_SCOPE_TYPE|PATH_COMPONENT_INVALID|PATH_INVALID|PATH_RESERVED_NAME|PATH_TRAILING_DOT_OR_SPACE'-and-not$rejected.Text.Contains('CONTINUATION_SOURCE_RECEIPT_AUTHORITY_DRIFT')) ('continuation-invalid-protection-rejected-before-source-comparison-'+$variant+'-'+$badScope)
      }
      Write-Json $cp $f.continuationReceipt
    }
    Write-GroupCompletion;return
  }
  if($Group-ceq'ContinuationRepair'){
  $scopeRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Group','ContinuationScope') -GroupId 'authorization-continuation-scope'
  foreach($line in $scopeRun.Output){if($line-cnotmatch'^RESULT\|'){Write-Output $line}}
  $script:passed+=@($scopeRun.Output|Where-Object{$_-cmatch'^PASS\|'}).Count
  Assert-True ($scopeRun.Code-eq0) 'continuation-absolute-scope-native-branch-in-normal-repair-regression'
  # First submission uses a real producer action and FINALIZE, without inventing a finding.
  $initial=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $initial.authorizationPackagePath=$parentPath;$initial.expectedAuthorizationIdentity=Get-Identity $parentPath
  $initial.intentEnvelope.objective='Produce the candidate for its first independent review'
  $initial.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$initial.intentEnvelope.semanticHints=@('implementation')
  $first=Run-Process $initial 'initial-producer-discover';$firstReceipt=Join-Path $control 'initial-producer-compact.json';Write-Json $firstReceipt $first.compactReceipt
  $firstBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$firstReceipt;expectedDiscoverReceiptIdentity=Get-Identity $firstReceipt;preparationReceipts=@($first.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $firstAdmit=Run-Process $firstBoundary 'initial-producer-admit';Assert-True ($firstAdmit.status-ceq'PASS') 'first-review-producer-is-actually-admitted'
  Write-Utf8 $objectPath 'Initial candidate awaiting independent judgment'
  $firstBoundary.mode='FINALIZE_OUTPUT';$firstBoundary.resultReceipts=@($first.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $firstFinal=Run-Process $firstBoundary 'initial-producer-finalize';$firstFinalPath=Join-Path $control 'initial-producer-finalize-result.json';Write-Json $firstFinalPath $firstFinal
  $firstContinuation=Join-Path $control 'first-continuation.json';Write-Json $firstContinuation $firstFinal.continuationReceipt
  $firstTest=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $firstTest|Add-Member continuationReceiptPath $firstContinuation;$firstTest|Add-Member expectedContinuationReceiptIdentity (Get-Identity $firstContinuation)
  $firstTest.intentEnvelope.requestedActionKind='TEST_RUN';$firstTest.intentEnvelope.requestedResultKind='TEST_RESULT';$firstTest.intentEnvelope.semanticHints=@('test');$firstTest.intentEnvelope.mutationHints=@('test')
  $tested=Run-Process $firstTest 'initial-test-discover';$testReceipt=Join-Path $control 'initial-test-compact.json';Write-Json $testReceipt $tested.compactReceipt
  $testBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$testReceipt;expectedDiscoverReceiptIdentity=Get-Identity $testReceipt;preparationReceipts=@($tested.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $testAdmit=Run-Process $testBoundary 'initial-test-admit'
  Assert-True ($testAdmit.status-ceq'PASS'-and[IO.File]::ReadAllText($objectPath).TrimEnd("`n")-ceq'Initial candidate awaiting independent judgment') 'first-submission-self-test-consumes-real-producer-continuation'
  $testBoundary.mode='FINALIZE_OUTPUT';$testBoundary.resultReceipts=@($tested.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $testedFinal=Run-Process $testBoundary 'initial-test-finalize';$testedFinalPath=Join-Path $control 'initial-test-finalize-result.json';Write-Json $testedFinalPath $testedFinal
  $initialBinding=[ordered]@{parentPackagePath=$parentPath;parentPackageIdentity=Get-Identity $parentPath;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=(Join-Path $control 'initial-test-finalize.json');repairFinalizeInputIdentity=Get-Identity (Join-Path $control 'initial-test-finalize.json');repairFinalizeResultPath=$testedFinalPath;repairFinalizeResultIdentity=Get-Identity $testedFinalPath}
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$initialBinding})
  $firstReview=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  $firstReviewCheck=Invoke-Check $firstReview.package reviewer-fixture REVIEW_EXECUTE
  if($firstReviewCheck.Code-ne0){Write-Output ('DIAG|first-review|'+$firstReviewCheck.Text)}
  Assert-True ($firstReviewCheck.Code-eq0) 'first-review-current-package-binds-real-producer-finalize'
  $firstReviewPath=Join-Path $control 'initial-review-package.json';Write-Json $firstReviewPath $firstReview.package
  $reviewDiscover=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $reviewDiscover.observedActor='reviewer-fixture';$reviewDiscover.authorizationPackagePath=$firstReviewPath;$reviewDiscover.expectedAuthorizationIdentity=Get-Identity $firstReviewPath
  $reviewDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$reviewDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$reviewDiscover.intentEnvelope.semanticHints=@('review');$reviewDiscover.intentEnvelope.mutationHints=@()
  $reviewDiscovered=Run-Process $reviewDiscover 'initial-review-discover';$reviewReceipt=Join-Path $control 'initial-review-compact.json';Write-Json $reviewReceipt $reviewDiscovered.compactReceipt
  $reviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$reviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $reviewReceipt;preparationReceipts=@($reviewDiscovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $reviewAdmit=Run-Process $reviewBoundary 'initial-review-admit';Assert-True ($reviewAdmit.status-ceq'PASS') 'first-review-independent-actor-passes-real-process-admission'
  $reviewBoundary.mode='FINALIZE_OUTPUT';$reviewBoundary.resultReceipts=@($reviewDiscovered.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$reviewBoundary.deliveryReceipts=@('FIXTURE_REVIEW_RETURN')
  $reviewFinal=Run-Process $reviewBoundary 'initial-review-finalize' -ReviewOutcome CHANGES_REQUESTED
  Assert-True ($reviewFinal.status-ceq'PASS'-and$reviewFinal.consumer.recipient-ceq'writer-fixture') 'first-finding-returns-directly-to-its-writer-through-real-finalize'
  $badFirst=$firstReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badFirst.repairReviewBinding.cycle=1
  Assert-True ((Invoke-Check $badFirst reviewer-fixture REVIEW_EXECUTE).Code-ne0) 'first-review-rejects-invented-repair-cycle'
  $actualFinding=$script:FixtureReviewFinalizes['initial-review-finalize']
  $verdictPath=$actualFinding.verdictPath
  $binding.verdictPath=$actualFinding.verdictPath;$binding.verdictIdentity=$actualFinding.verdictIdentity
  foreach($field in @('verdictFinalizeInputPath','verdictFinalizeInputIdentity','verdictFinalizeResultPath','verdictFinalizeResultIdentity')){$binding[$field]=$actualFinding.$field}
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  $prepared=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  Write-Json $childPath $prepared.package;$discover.expectedAuthorizationIdentity=Get-Identity $childPath
  $d=Run-Process $discover 'repair-discover';$receiptPath=Join-Path $control 'repair-compact.json';Write-Json $receiptPath $d.compactReceipt
  $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Get-Identity $receiptPath;preparationReceipts=@($d.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $admitted=Run-Process $boundary 'repair-admit';Assert-True ($admitted.status-ceq'PASS') 'real-repair-admission-passes'
  Write-Utf8 $objectPath 'Repaired candidate with real postimage'
  $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($d.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $legacyHostResult=Join-Path $temp 'legacy-fixture-host-result.txt';Write-Utf8 $legacyHostResult 'recipient=owner-fixture;outcome=SUCCESS;fixture-only'
  $boundary.deliveryReceipts=@('FIXTURE_HOST_RESULT|'+(Get-Identity $legacyHostResult))
  Assert-True ('DELIVERY_RECEIPT'-cin@($d.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements})) 'repair-terminal-fixture-selects-actual-delivery-obligation'
  $final=Run-Process $boundary 'repair-finalize';$finalResultPath=Join-Path $control 'repair-final-result.json';Write-Json $finalResultPath $final
  Assert-True ($final.status-ceq'PASS') 'real-repair-finalize-binds-written-postimage'
  $binding.phase='REREVIEW';$binding.repairFinalizeInputPath=Join-Path $control 'repair-finalize.json';$binding.repairFinalizeInputIdentity=Get-Identity $binding.repairFinalizeInputPath;$binding.repairFinalizeResultPath=$finalResultPath;$binding.repairFinalizeResultIdentity=Get-Identity $finalResultPath
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$binding})
  $reviewPrepared=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  $reviewCheck=Invoke-Check $reviewPrepared.package reviewer-fixture REVIEW_EXECUTE
  if($reviewCheck.Code-ne0){Write-Output ('DIAG|rereview|'+$reviewCheck.Text)}
  Assert-True ($reviewCheck.Code-eq0) 'real-finalize-authorizes-prebound-independent-focused-rereview'
  $rereviewPath=Join-Path $control 'rereview-package.json';Write-Json $rereviewPath $reviewPrepared.package
  $reviewDiscover.authorizationPackagePath=$rereviewPath;$reviewDiscover.expectedAuthorizationIdentity=Get-Identity $rereviewPath
  $rereview=Run-Process $reviewDiscover 'rereview-discover';$rereviewReceipt=Join-Path $control 'rereview-compact.json';Write-Json $rereviewReceipt $rereview.compactReceipt
  $rereviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$rereviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $rereviewReceipt;preparationReceipts=@($rereview.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  $rereviewAdmit=Run-Process $rereviewBoundary 'rereview-admit'
  Assert-True ($rereviewAdmit.status-ceq'PASS'-and[IO.File]::ReadAllText($objectPath).TrimEnd("`n")-ceq'Repaired candidate with real postimage') 'same-independent-reviewer-actually-admits-and-inspects-repaired-candidate'
  $rereviewBoundary.mode='FINALIZE_OUTPUT';$rereviewBoundary.resultReceipts=@($rereview.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$rereviewBoundary.deliveryReceipts=@('FIXTURE_REREVIEW_RETURN')
  $rereviewFinal=Run-Process $rereviewBoundary 'rereview-finalize'
  Assert-True ($rereviewFinal.status-ceq'PASS') 'repair-to-rereview-chain-finishes-through-real-finalize-without-owner-relay'
  $terminalPath=Join-Path $control 'rereview-finalize.json'
  Write-Json $routeInput ([ordered]@{operation='TERMINAL';boundaryInputRef=[ordered]@{path=$terminalPath;identity=Get-Identity $terminalPath}})
  $ownerTerminal=(Invoke-AuthNative -NoProfile -File (Join-Path $fixtureVersion 'scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json
  Assert-True ($ownerTerminal.status-ceq'PASS'-and$ownerTerminal.consumer.recipient-ceq'owner-fixture'-and$ownerTerminal.delivery.delivered-and-not$ownerTerminal.ackRequired-and-not$ownerTerminal.polling) 'approved-review-terminal-reuses-real-consumer-boundary-without-ack-or-poll'
  $nativeReview=Get-Content $terminalPath -Raw|ConvertFrom-Json -Depth 100
  $nativeReview.deliveryContext=[pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
  $nativeReviewPath=Join-Path $control 'review-native-conflict.json';Write-Json $nativeReviewPath $nativeReview
  $nativeConflict=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $nativeReviewPath -AsJson)|ConvertFrom-Json
  Assert-True ($nativeConflict.status-ceq'FAIL'-and$nativeConflict.reason-ceq'DELIVERY_CONSUMER_CHANNEL_MISMATCH') 'real-review-finalize-rejects-agent-only-native-response'
  $hostResultPath=Join-Path $temp 'fixture-host-result.json'
  foreach($deliveryCase in @('NATIVE_PREPARE','TASK_PREPARE','SUCCESS','FAILURE','UNKNOWN')){
    $withDelivery=$boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable
    $withDelivery.deliveryReceipts=@();$withDelivery.resultReceipts=@($withDelivery.resultReceipts|Where-Object{$_-cne'DELIVERY_RECEIPT'})
    $prepare=$deliveryCase.EndsWith('PREPARE')
    $raw=if($deliveryCase-ceq'SUCCESS'){[ordered]@{isError=$false;content=@([ordered]@{type='text';text='{"threadId":"owner-fixture"}'})}}elseif($deliveryCase-ceq'FAILURE'){[ordered]@{isError=$true;content=@([ordered]@{type='text';text='Policy rejected this fixture send.'})}}else{[ordered]@{content=@()}}
    Write-Json $hostResultPath $raw
    $withDelivery.deliveryContext=[ordered]@{channel=$(if($deliveryCase-ceq'NATIVE_PREPARE'){'NATIVE_RESPONSE'}else{'TASK_MESSAGE'});stage=$(if($prepare){'PREPARE'}else{'OBSERVE'});expectedRecipient='owner-fixture';observedRecipient=$(if($deliveryCase-ceq'SUCCESS'){'owner-fixture'}else{'NOT_APPLICABLE'});outcome=$(if($prepare){'NOT_SENT'}else{$deliveryCase});evidence=$(if($prepare){'NOT_APPLICABLE'}else{$hostResultPath+'#'+(Get-Identity $hostResultPath)})}
    $name='repair-delivery-'+$deliveryCase
    $observed=Run-Process $withDelivery $name -AllowFailure;$observedPath=Join-Path $control ($name+'-result.json');Write-Json $observedPath $observed
    if($deliveryCase-cne'SUCCESS'){
      $expected=if($deliveryCase-ceq'NATIVE_PREPARE'){'FAIL'}else{'BLOCKED'}
      Assert-True ($observed.status-ceq$expected) ('repair-output-cannot-close-'+$deliveryCase)
      continue
    }
    $deliveryBinding=$binding|ConvertTo-Json -Depth 100|ConvertFrom-Json
    $deliveryBinding.repairFinalizeInputPath=Join-Path $control ($name+'.json');$deliveryBinding.repairFinalizeInputIdentity=Get-Identity $deliveryBinding.repairFinalizeInputPath
    $deliveryBinding.repairFinalizeResultPath=$observedPath;$deliveryBinding.repairFinalizeResultIdentity=Get-Identity $observedPath
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$deliveryBinding})
    $deliveryPackage=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    $deliveryCheck=Invoke-Check $deliveryPackage.package reviewer-fixture REVIEW_EXECUTE
    $expectedStatus=if($prepare){'READY_TO_SEND'}elseif($deliveryCase-ceq'SUCCESS'){'DELIVERED'}elseif($deliveryCase-ceq'FAILURE'){'NOT_DELIVERED'}else{'UNKNOWN'}
    Assert-True ($deliveryCheck.Code-eq0-and$observed.delivery.status-ceq$expectedStatus-and$observed.delivery.delivered-eq($deliveryCase-ceq'SUCCESS')) ('rereview-consumes-real-finalize-'+$deliveryCase)
    $tampered=$withDelivery|ConvertTo-Json -Depth 100|ConvertFrom-Json;$tampered.deliveryContext.expectedRecipient='another-recipient';Write-Json $deliveryBinding.repairFinalizeInputPath $tampered
    $deliveryPackage.package.repairReviewBinding.repairFinalizeInputIdentity=Get-Identity $deliveryBinding.repairFinalizeInputPath
    $tamperedCheck=Invoke-Check $deliveryPackage.package reviewer-fixture REVIEW_EXECUTE
    Assert-True ($tamperedCheck.Code-ne0) ('rereview-rejects-context-tampering-'+$deliveryCase)
    Write-Json $deliveryBinding.repairFinalizeInputPath $withDelivery;$deliveryPackage.package.repairReviewBinding.repairFinalizeInputIdentity=Get-Identity $deliveryBinding.repairFinalizeInputPath
    $tamperedResult=$observed|ConvertTo-Json -Depth 100|ConvertFrom-Json;$tamperedResult.delivery.delivered=-not$observed.delivery.delivered;Write-Json $observedPath $tamperedResult
    $deliveryPackage.package.repairReviewBinding.repairFinalizeResultIdentity=Get-Identity $observedPath
    $tamperedCheck=Invoke-Check $deliveryPackage.package reviewer-fixture REVIEW_EXECUTE
    Assert-True ($tamperedCheck.Code-ne0-and$tamperedCheck.Text.Contains('DELIVERY_RESULT_DRIFT')) ('rereview-rejects-delivery-result-tampering-'+$deliveryCase)
  }
  $forged=$final|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forged.decisionIdentity='0'*64;Write-Json $finalResultPath $forged
  $reviewPrepared.package.repairReviewBinding.repairFinalizeResultIdentity=Get-Identity $finalResultPath
  $forgedCheck=Invoke-Check $reviewPrepared.package reviewer-fixture REVIEW_EXECUTE
  Assert-True ($forgedCheck.Code-ne0-and$forgedCheck.Text.Contains('FINALIZE_DECISION_DRIFT')) 'rereview-rejects-self-declared-pass-without-real-decision'
  Write-Json $finalResultPath $final;$reviewPrepared.package.repairReviewBinding.repairFinalizeResultIdentity=Get-Identity $finalResultPath
  Write-Utf8 $objectPath 'Third party drift after repair finalization'
  $driftCheck=Invoke-Check $reviewPrepared.package reviewer-fixture REVIEW_EXECUTE
  Assert-True ($driftCheck.Code-ne0) 'rereview-rejects-current-candidate-drift'

  # The Owner preauthorizes an independent visible reviewer before its host ID
  # exists. The writer binds the actual create result after production and test.
  Write-Utf8 $objectPath 'Late reviewer production preimage'
  $lateParent=New-Package STANDARD TASK_OWNER writer-fixture SOURCE_WRITE ROUTINE_LOCAL
  $lateParent.actions=@('SOURCE_WRITE','TEST_RUN');$lateParent.continuationPlan=@('SOURCE_WRITE','TEST_RUN');$lateParent.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $lateParent.repairReviewPlan=[ordered]@{writer='writer-fixture';reviewer='DEFERRED_VISIBLE_REVIEWER';maxCycles=2;materialContributors=@()}
  $lateParentPath=Join-Path $control 'late-review-parent.json';Write-Json $lateParentPath $lateParent
  Assert-True ((Invoke-Check $lateParent writer-fixture SOURCE_WRITE).Code-eq0) 'owner-preauthorizes-temporary-writer-and-deferred-independent-reviewer'
  $lateInitial=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $lateInitial.authorizationPackagePath=$lateParentPath;$lateInitial.expectedAuthorizationIdentity=Get-Identity $lateParentPath
  $lateProducer=Run-Process $lateInitial 'late-producer-discover';$lateProducerReceipt=Join-Path $control 'late-producer-compact.json';Write-Json $lateProducerReceipt $lateProducer.compactReceipt
  $lateBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$lateProducerReceipt;expectedDiscoverReceiptIdentity=Get-Identity $lateProducerReceipt;preparationReceipts=@($lateProducer.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  Assert-True ((Run-Process $lateBoundary 'late-producer-admit').status-ceq'PASS') 'late-reviewer-producer-admits-under-original-owner-package'
  Write-Utf8 $objectPath 'Late reviewer candidate after production'
  $lateBoundary.mode='FINALIZE_OUTPUT';$lateBoundary.resultReceipts=@($lateProducer.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $lateProducerFinal=Run-Process $lateBoundary 'late-producer-finalize';$lateContinuationPath=Join-Path $control 'late-producer-continuation.json';Write-Json $lateContinuationPath $lateProducerFinal.continuationReceipt
  $lateTest=$lateInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $lateTest|Add-Member continuationReceiptPath $lateContinuationPath;$lateTest|Add-Member expectedContinuationReceiptIdentity (Get-Identity $lateContinuationPath)
  $lateTest.intentEnvelope.requestedActionKind='TEST_RUN';$lateTest.intentEnvelope.requestedResultKind='TEST_RESULT';$lateTest.intentEnvelope.semanticHints=@('test');$lateTest.intentEnvelope.mutationHints=@('test')
  $lateTestDiscover=Run-Process $lateTest 'late-test-discover';$lateTestReceipt=Join-Path $control 'late-test-compact.json';Write-Json $lateTestReceipt $lateTestDiscover.compactReceipt
  $lateTestBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$lateTestReceipt;expectedDiscoverReceiptIdentity=Get-Identity $lateTestReceipt;preparationReceipts=@($lateTestDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  Assert-True ((Run-Process $lateTestBoundary 'late-test-admit').status-ceq'PASS') 'late-reviewer-test-reuses-original-continuation'
  $lateTestBoundary.mode='FINALIZE_OUTPUT';$lateTestBoundary.resultReceipts=@($lateTestDiscover.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $lateTestFinal=Run-Process $lateTestBoundary 'late-test-finalize';$lateTestFinalPath=Join-Path $control 'late-test-final-result.json';Write-Json $lateTestFinalPath $lateTestFinal
  $lateAssignment=[ordered]@{source='HOST_CREATE_THREAD_RESULT';createdBy='writer-fixture';threadId='reviewer-late-fixture';hostId='fixture-host';taskId='AUTH-REGRESSION-001';parentPackageIdentity=Get-Identity $lateParentPath}
  $lateBinding=[ordered]@{parentPackagePath=$lateParentPath;parentPackageIdentity=Get-Identity $lateParentPath;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=(Join-Path $control 'late-test-finalize.json');repairFinalizeInputIdentity=Get-Identity (Join-Path $control 'late-test-finalize.json');repairFinalizeResultPath=$lateTestFinalPath;repairFinalizeResultIdentity=Get-Identity $lateTestFinalPath;reviewerAssignment=$lateAssignment}
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$lateBinding})
  $lateReview=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  $lateReviewCheck=Invoke-Check $lateReview.package reviewer-late-fixture REVIEW_EXECUTE
  if($lateReviewCheck.Code-ne0){Write-Output ('DIAG|late-reviewer|'+$lateReviewCheck.Text)}
  Assert-True ($lateReviewCheck.Code-eq0-and$lateReview.package.owner-ceq'owner-fixture'-and$lateReview.package.issuer-ceq'owner-fixture'-and$lateReview.package.grantee-ceq'reviewer-late-fixture') 'late-created-independent-reviewer-admits-with-original-owner-and-production-evidence'
  $missingAssignment=$lateReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$missingAssignment.repairReviewBinding.PSObject.Properties.Remove('reviewerAssignment')
  Assert-True ((Invoke-Check $missingAssignment reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-missing-host-assignment'
  $wrongAssignment=$lateReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongAssignment.repairReviewBinding.reviewerAssignment.createdBy='other-fixture'
  Assert-True ((Invoke-Check $wrongAssignment reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-wrong-creator'
  $wrongParentAssignment=$lateReview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongParentAssignment.repairReviewBinding.reviewerAssignment.parentPackageIdentity='1|'+('0'*64)
  Assert-True ((Invoke-Check $wrongParentAssignment reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-wrong-parent-binding'
  Assert-True ((Invoke-Check $lateReview.package reviewer-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-other-actor-reuse'
  $lateCandidateBytes=[IO.File]::ReadAllBytes($objectPath);Write-Utf8 $objectPath 'Unreviewed third-party candidate'
  Assert-True ((Invoke-Check $lateReview.package reviewer-late-fixture REVIEW_EXECUTE).Code-ne0) 'deferred-reviewer-package-rejects-candidate-drift'
  [IO.File]::WriteAllBytes($objectPath,$lateCandidateBytes)
  $lateReviewPath=Join-Path $control 'late-review-package.json';Write-Json $lateReviewPath $lateReview.package
  $lateReviewDiscover=$lateInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$lateReviewDiscover.observedActor='reviewer-late-fixture';$lateReviewDiscover.authorizationPackagePath=$lateReviewPath;$lateReviewDiscover.expectedAuthorizationIdentity=Get-Identity $lateReviewPath
  $lateReviewDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$lateReviewDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$lateReviewDiscover.intentEnvelope.semanticHints=@('review');$lateReviewDiscover.intentEnvelope.mutationHints=@()
  $lateReviewResult=Run-Process $lateReviewDiscover 'late-review-discover';$lateReviewReceipt=Join-Path $control 'late-review-compact.json';Write-Json $lateReviewReceipt $lateReviewResult.compactReceipt
  $lateReviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$lateReviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $lateReviewReceipt;preparationReceipts=@($lateReviewResult.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
  Assert-True ((Run-Process $lateReviewBoundary 'late-review-admit').status-ceq'PASS') 'late-reviewer-real-process-admission-keeps-owner-writer-reviewer-distinct'
  $lateReviewBoundary.mode='FINALIZE_OUTPUT';$lateReviewBoundary.resultReceipts=@($lateReviewResult.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$lateReviewBoundary.deliveryReceipts=@('FIXTURE_APPROVED_TO_OWNER_ONCE')
  Assert-True ((Run-Process $lateReviewBoundary 'late-review-finalize').status-ceq'PASS') 'late-reviewer-finalizes-one-direct-owner-handoff'
  $selfActor='01a0eeee-5555-7222-8333-444444444444';$selfDelegation='fixture-late-reviewer-initial-001'
  $selfBinding=$lateBinding|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $selfBinding.reviewerAssignment.source='HOST_INITIAL_DELEGATION';$selfBinding.reviewerAssignment.threadId='UNBOUND_RECEIVER'
  Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$selfBinding})
  $selfPrepared=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
  Assert-True ($selfPrepared.status-ceq'PREPARED'-and$selfPrepared.package.grantee-ceq'UNBOUND_RECEIVER') 'late-reviewer-prepares-nonactionable-initial-delegation'
  $selfPendingPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-late-reviewer.json'
  Write-Json $selfPendingPath ([ordered]@{schemaVersion=1;delegationId=$selfDelegation;receiverRole='REVIEWER';authorizationTemplate=$selfPrepared.package})
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$selfActor
    $selfBindResult=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $selfPendingPath -ExpectedPendingIdentity (Get-Identity $selfPendingPath) -ReceivedDelegationId $selfDelegation 2>&1|ForEach-Object{[string]$_});$selfBindCode=$LASTEXITCODE
    $selfPackagePath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$selfActor+'/receiver-authorization-'+$selfDelegation+'.json')
    Assert-True ($selfBindCode-eq0-and(Test-Path -LiteralPath $selfPackagePath -PathType Leaf)) 'late-reviewer-self-binds-from-initial-delegation'
    $selfPackage=Get-Content $selfPackagePath -Raw|ConvertFrom-Json -Depth 100
    $selfCheck=Invoke-Check $selfPackage $selfActor REVIEW_EXECUTE
    Assert-True ($selfCheck.Code-eq0-and$selfPackage.owner-ceq'owner-fixture'-and$selfPackage.issuer-ceq'owner-fixture'-and$selfPackage.repairReviewBinding.reviewerAssignment.threadId-ceq$selfActor) 'late-self-bound-reviewer-preserves-owner-and-production-evidence'
    $selfDiscover=$lateReviewDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$selfDiscover.observedActor=$selfActor;$selfDiscover.authorizationPackagePath=$selfPackagePath;$selfDiscover.expectedAuthorizationIdentity=Get-Identity $selfPackagePath
    $selfProcess=Run-Process $selfDiscover 'late-self-review-discover';$selfCompact=Join-Path $control 'late-self-review-compact.json';Write-Json $selfCompact $selfProcess.compactReceipt
    $selfBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$selfCompact;expectedDiscoverReceiptIdentity=Get-Identity $selfCompact;preparationReceipts=@($selfProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $selfBoundary 'late-self-review-admit').status-ceq'PASS') 'late-self-bound-reviewer-enters-original-process-gate'
    $altered=$selfPackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$altered.repairReviewBinding.reviewerAssignment.threadId='01a0eeee-6666-7222-8333-444444444444'
    Assert-True ((Invoke-Check $altered $selfActor REVIEW_EXECUTE).Code-ne0) 'late-self-bound-reviewer-rejects-other-assignment'
  }finally{$env:CODEX_THREAD_ID=$oldHostId}
  # One original delegation must compose an unknown writer, its write/test
  # continuation, and a later unknown independent reviewer through rereview.
  $combinedConfigPath=Join-Path $control 'project.json';$combinedConfigOriginal=[IO.File]::ReadAllBytes($combinedConfigPath)
  # This is a repo-local project. Its ordinary schema1 package supports the
  # same continuation and late-reviewer chain without a fictitious sibling.
  Write-Task STANDARD IMPLEMENT
  Write-Utf8 $objectPath 'Combined delegation setup'
  $combinedWriter='01a0eeee-aaaa-7222-8333-444444444444';$combinedReviewer='01a0eeee-bbbb-7222-8333-444444444444'
  $combinedId='fixture-combined-implementer-001';$combinedReviewId='fixture-combined-reviewer-001'
  $combinedTemplate=New-Package STANDARD TASK_OWNER UNBOUND_RECEIVER SOURCE_WRITE ROUTINE_LOCAL
  $combinedTemplate.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$combinedTemplate['continuationPlan']=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE')
  $combinedTemplate.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $combinedTemplate['repairReviewPlan']=[ordered]@{writer='UNBOUND_RECEIVER';reviewer='DEFERRED_VISIBLE_REVIEWER';maxCycles=2;materialContributors=@()}
  $combinedTemplate.objectIdentities[0].identity='NEW'
  Remove-Item -LiteralPath $objectPath
  $combinedPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-writer.json'
  Write-Json $combinedPending ([ordered]@{schemaVersion=1;delegationId=$combinedId;receiverRole='IMPLEMENTER';authorizationTemplate=$combinedTemplate})
  $oldHostId=$env:CODEX_THREAD_ID
  try{
    $env:CODEX_THREAD_ID=$combinedWriter
    $combinedBind=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $combinedPending -ExpectedPendingIdentity (Get-Identity $combinedPending) -ReceivedDelegationId $combinedId 2>&1|ForEach-Object{[string]$_});$combinedBindCode=$LASTEXITCODE
    $combinedParentPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$combinedWriter+'/receiver-authorization-'+$combinedId+'.json')
    Assert-True ($combinedBindCode-eq0-and(Test-Path -LiteralPath $combinedParentPath -PathType Leaf)) 'combined-unknown-writer-self-binds-once'
    $combinedParent=Get-Content $combinedParentPath -Raw|ConvertFrom-Json -Depth 100
    $combinedCheck=Invoke-Check $combinedParent $combinedWriter SOURCE_WRITE
    if($combinedCheck.Code-ne0){Write-Output ('DIAG|combined-writer|'+$combinedCheck.Text)}
    Assert-True ($combinedCheck.Code-eq0-and$combinedParent.repairReviewPlan.writer-ceq$combinedWriter-and$combinedParent.owner-ceq'owner-fixture'-and$combinedParent.issuer-ceq'owner-fixture'-and$combinedParent.objectIdentities[0].identity-ceq'NEW') 'combined-bound-writer-preserves-owner-issuer-and-new-object'
    Assert-True ((Invoke-Check $combinedParent $combinedWriter REVIEW_ROUTE).Code-ne0) 'combined-review-route-rejects-missing-continuation'
    Assert-True ((Invoke-Check $combinedParent 'other-writer' SOURCE_WRITE).Code-ne0) 'combined-delegation-rejects-other-writer'
    $noRoute=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$noRoute.actions=@('SOURCE_WRITE','TEST_RUN');$noRoute.continuationPlan=@('SOURCE_WRITE','TEST_RUN')
    Assert-True ((Invoke-Check $noRoute $combinedWriter REVIEW_ROUTE).Code-ne0) 'combined-route-rejects-absent-owner-pregrant'
    foreach($smuggled in @('REVIEW_EXECUTE','RESULT_ACCEPT','GIT_STAGE')){
      $bad=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.actions+=@($smuggled);$bad.continuationPlan+=@($smuggled)
      Assert-True ((Invoke-Check $bad $combinedWriter SOURCE_WRITE).Code-ne0) ('combined-route-rejects-smuggled-'+$smuggled)
    }
    $tamperedOwner=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedOwner.owner=$combinedWriter
    Assert-True ((Invoke-Check $tamperedOwner $combinedWriter SOURCE_WRITE).Code-ne0) 'combined-bound-writer-rejects-owner-rewrite'
    $tamperedIssuer=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedIssuer.issuer=$combinedWriter
    Assert-True ((Invoke-Check $tamperedIssuer $combinedWriter SOURCE_WRITE).Code-ne0) 'combined-bound-writer-rejects-issuer-rewrite'
    $wrongWriter=$combinedTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongWriter.repairReviewPlan.writer='other-writer'
    $wrongWriterPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-wrong-writer.json';$wrongWriterId='fixture-combined-wrong-writer-001'
    Write-Json $wrongWriterPath ([ordered]@{schemaVersion=1;delegationId=$wrongWriterId;receiverRole='IMPLEMENTER';authorizationTemplate=$wrongWriter})
    $wrongWriterBind=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $wrongWriterPath -ExpectedPendingIdentity (Get-Identity $wrongWriterPath) -ReceivedDelegationId $wrongWriterId 2>&1|ForEach-Object{[string]$_})
    Assert-True ($LASTEXITCODE-ne0-and($wrongWriterBind-join"`n").Contains('PENDING_REPAIR_WRITER')) 'combined-delegation-rejects-fixed-other-writer'
    $wrongRole=$combinedTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongRole.actions=@('TEST_RUN');$wrongRole.continuationPlan=@('TEST_RUN')
    $wrongRolePath=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-wrong-role.json';$wrongRoleId='fixture-combined-wrong-role-001'
    Write-Json $wrongRolePath ([ordered]@{schemaVersion=1;delegationId=$wrongRoleId;receiverRole='INVESTIGATOR';authorizationTemplate=$wrongRole})
    $wrongRoleBind=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $wrongRolePath -ExpectedPendingIdentity (Get-Identity $wrongRolePath) -ReceivedDelegationId $wrongRoleId 2>&1|ForEach-Object{[string]$_})
    Assert-True ($LASTEXITCODE-ne0-and($wrongRoleBind-join"`n").Contains('PENDING_REPAIR_WRITER_ROLE')) 'combined-delegation-rejects-plan-on-investigator-role'
    $tamperedWriter=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedWriter.repairReviewPlan.writer='other-writer'
    Assert-True ((Invoke-Check $tamperedWriter $combinedWriter SOURCE_WRITE).Code-ne0) 'combined-bound-writer-rejects-plan-writer-tampering'
    $tamperedScope=$combinedParent|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$tamperedScope.exactPaths=@($objectRelative,'src/extra.txt')
    $scopeCheck=Invoke-Check $tamperedScope $combinedWriter SOURCE_WRITE
    Assert-True ($scopeCheck.Code-ne0-and$scopeCheck.Text.Contains('RECEIVER_AUTHORITY_EXPANDED')) 'combined-bound-writer-rejects-scope-expansion'
    $combinedInitial=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedInitial.observedActor=$combinedWriter;$combinedInitial.authorizationPackagePath=$combinedParentPath;$combinedInitial.expectedAuthorizationIdentity=Get-Identity $combinedParentPath;$combinedInitial.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json')
    $combinedSource=Run-Process $combinedInitial 'combined-source-discover';$combinedSourceReceipt=Join-Path $control 'combined-source-compact.json';Write-Json $combinedSourceReceipt $combinedSource.compactReceipt
    $combinedSourceBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedSourceReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedSourceReceipt;preparationReceipts=@($combinedSource.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedSourceBoundary 'combined-source-admit').status-ceq'PASS') 'combined-unknown-writer-passes-source-admission'
    Write-Utf8 $objectPath 'Combined candidate awaiting independent judgment'
    $combinedSourceBoundary.mode='FINALIZE_OUTPUT';$combinedSourceBoundary.resultReceipts=@($combinedSource.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
    $combinedSourceFinal=Run-Process $combinedSourceBoundary 'combined-source-finalize';$combinedContinuation=Join-Path $control 'combined-continuation.json';Write-Json $combinedContinuation $combinedSourceFinal.continuationReceipt
    $combinedTest=$combinedInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedTest|Add-Member continuationReceiptPath $combinedContinuation;$combinedTest|Add-Member expectedContinuationReceiptIdentity (Get-Identity $combinedContinuation)
    $combinedTest.intentEnvelope.requestedActionKind='TEST_RUN';$combinedTest.intentEnvelope.requestedResultKind='TEST_RESULT';$combinedTest.intentEnvelope.semanticHints=@('test');$combinedTest.intentEnvelope.mutationHints=@('test')
    $combinedTestDiscover=Run-Process $combinedTest 'combined-test-discover';$combinedTestReceipt=Join-Path $control 'combined-test-compact.json';Write-Json $combinedTestReceipt $combinedTestDiscover.compactReceipt
    $combinedTestBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedTestReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedTestReceipt;preparationReceipts=@($combinedTestDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedTestBoundary 'combined-test-admit').status-ceq'PASS') 'combined-unknown-writer-consumes-source-test-continuation'
    $combinedTestBoundary.mode='FINALIZE_OUTPUT';$combinedTestBoundary.resultReceipts=@($combinedTestDiscover.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
    $combinedTestFinal=Run-Process $combinedTestBoundary 'combined-test-finalize';$combinedTestFinalPath=Join-Path $control 'combined-test-final-result.json';Write-Json $combinedTestFinalPath $combinedTestFinal
    $combinedRouteContinuation=Join-Path $control 'combined-route-continuation.json';Write-Json $combinedRouteContinuation $combinedTestFinal.continuationReceipt
    $combinedRoute=$combinedInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedRoute|Add-Member continuationReceiptPath $combinedRouteContinuation
    $combinedRoute|Add-Member expectedContinuationReceiptIdentity (Get-Identity $combinedRouteContinuation)
    $combinedRoute.intentEnvelope.objective='Route the current candidate to the independent reviewer'
    $combinedRoute.intentEnvelope.requestedActionKind='REVIEW_ROUTE';$combinedRoute.intentEnvelope.requestedResultKind='HANDOFF'
    $combinedRoute.intentEnvelope.semanticHints=@('review','handoff');$combinedRoute.intentEnvelope.mutationHints=@('review')
    $routeCheck=Invoke-Check $combinedParent $combinedWriter REVIEW_ROUTE
    Assert-True ($routeCheck.Code-ne0-and$routeCheck.Text.Contains('CONTINUATION')) 'combined-route-needs-current-continuation-receipt'
    $combinedRouteDiscover=Run-Process $combinedRoute 'combined-route-discover';$combinedRouteReceipt=Join-Path $control 'combined-route-compact.json';Write-Json $combinedRouteReceipt $combinedRouteDiscover.compactReceipt
    $combinedRouteBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedRouteReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedRouteReceipt;preparationReceipts=@($combinedRouteDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedRouteBoundary 'combined-route-admit').status-ceq'PASS'-and$combinedRouteDiscover.compactReceipt.binding.actor-ceq$combinedWriter-and$combinedRouteDiscover.compactReceipt.binding.role-ceq'EXECUTOR'-and$combinedRouteDiscover.compactReceipt.binding.phase-ceq'REVIEW') 'combined-nonowner-route-passes-real-check-discover-admit'
    $oldCandidate=[IO.File]::ReadAllBytes($objectPath);Write-Utf8 $objectPath 'Stale postimage after test'
    $staleRoute=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath (Join-Path $control 'combined-route-discover.json') -AsJson 2>&1|ForEach-Object{[string]$_});$staleRouteCode=$LASTEXITCODE
    Assert-True ($staleRouteCode-ne0) 'combined-route-rejects-stale-test-postimage'
    [IO.File]::WriteAllBytes($objectPath,$oldCandidate)
    $wrongRoute=$combinedRoute|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongRoute.observedActor='other-writer'
    $wrongRoutePath=Join-Path $control 'combined-route-wrong-actor.json';Write-Json $wrongRoutePath $wrongRoute
    $wrongRouteOut=@(Invoke-AuthNative -NoProfile -File $resolver -InputPath $wrongRoutePath -AsJson 2>&1|ForEach-Object{[string]$_})
    Assert-True ($LASTEXITCODE-ne0) 'combined-route-rejects-wrong-actor'
    $combinedRouteBoundary.mode='FINALIZE_OUTPUT';$combinedRouteBoundary.resultReceipts=@($combinedRouteDiscover.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedRouteBoundary.deliveryReceipts=@('FIXTURE_ROUTE_TO_REVIEWER')
    $combinedRouteFinal=Run-Process $combinedRouteBoundary 'combined-route-finalize';$combinedRouteFinalPath=Join-Path $control 'combined-route-final-result.json';Write-Json $combinedRouteFinalPath $combinedRouteFinal
    $combinedAssignment=[ordered]@{source='HOST_INITIAL_DELEGATION';createdBy=$combinedWriter;threadId='UNBOUND_RECEIVER';hostId='fixture-host';taskId='AUTH-REGRESSION-001';parentPackageIdentity=Get-Identity $combinedParentPath}
    $combinedBinding=[ordered]@{parentPackagePath=$combinedParentPath;parentPackageIdentity=Get-Identity $combinedParentPath;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=(Join-Path $control 'combined-test-finalize.json');repairFinalizeInputIdentity=Get-Identity (Join-Path $control 'combined-test-finalize.json');repairFinalizeResultPath=$combinedTestFinalPath;repairFinalizeResultIdentity=Get-Identity $combinedTestFinalPath;reviewerAssignment=$combinedAssignment}
    $routeAsProduction=$combinedBinding|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $routeAsProduction.repairFinalizeInputPath=Join-Path $control 'combined-route-finalize.json';$routeAsProduction.repairFinalizeInputIdentity=Get-Identity $routeAsProduction.repairFinalizeInputPath
    $routeAsProduction.repairFinalizeResultPath=$combinedRouteFinalPath;$routeAsProduction.repairFinalizeResultIdentity=Get-Identity $combinedRouteFinalPath
    $routeAsProduction.reviewerAssignment.source='HOST_CREATE_THREAD_RESULT';$routeAsProduction.reviewerAssignment.threadId=$combinedReviewer
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$routeAsProduction})
    $routeOnly=@(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson 2>&1|ForEach-Object{[string]$_})
    Assert-True ($LASTEXITCODE-ne0-and($routeOnly-join"`n").Contains('REPAIR_REVIEW_PRODUCTION_SCOPE_DRIFT')) 'combined-route-finalize-cannot-be-production-proof'
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$combinedBinding})
    $combinedReview=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    Assert-True ($combinedReview.status-ceq'PREPARED'-and$combinedReview.package.grantee-ceq'UNBOUND_RECEIVER') 'combined-late-reviewer-prepared-from-original-bound-parent'
    $combinedReviewPending=Join-Path $control 'runtime/AUTH-REGRESSION-001/issuer/pending-combined-reviewer.json'
    Write-Json $combinedReviewPending ([ordered]@{schemaVersion=1;delegationId=$combinedReviewId;receiverRole='REVIEWER';authorizationTemplate=$combinedReview.package})
    $env:CODEX_THREAD_ID=$combinedReviewer
    $reviewBind=@(Invoke-AuthNative -NoProfile -File $receiverBinder -ControlRoot $temp -PendingPath $combinedReviewPending -ExpectedPendingIdentity (Get-Identity $combinedReviewPending) -ReceivedDelegationId $combinedReviewId 2>&1|ForEach-Object{[string]$_});$reviewBindCode=$LASTEXITCODE
    $combinedReviewPath=Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$combinedReviewer+'/receiver-authorization-'+$combinedReviewId+'.json')
    if($reviewBindCode-ne0){Write-Output ('DIAG|combined-reviewer-bind|'+($reviewBind-join"`n"))}
    Assert-True ($reviewBindCode-eq0-and(Test-Path -LiteralPath $combinedReviewPath -PathType Leaf)) 'combined-late-reviewer-self-binds-once'
    $combinedReviewPackage=Get-Content $combinedReviewPath -Raw|ConvertFrom-Json -Depth 100
    $combinedReviewCheck=Invoke-Check $combinedReviewPackage $combinedReviewer REVIEW_EXECUTE
    if($combinedReviewCheck.Code-ne0){Write-Output ('DIAG|combined-reviewer|'+$combinedReviewCheck.Text)}
    Assert-True ($combinedReviewCheck.Code-eq0-and$combinedReviewPackage.candidateWriter-ceq$combinedWriter-and$combinedReviewPackage.owner-ceq'owner-fixture') 'combined-independent-reviewer-preserves-writer-and-owner'
    $combinedReviewDiscover=$combinedInitial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $combinedReviewDiscover.observedActor=$combinedReviewer;$combinedReviewDiscover.authorizationPackagePath=$combinedReviewPath;$combinedReviewDiscover.expectedAuthorizationIdentity=Get-Identity $combinedReviewPath
    $combinedReviewDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$combinedReviewDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$combinedReviewDiscover.intentEnvelope.semanticHints=@('review');$combinedReviewDiscover.intentEnvelope.mutationHints=@()
    $combinedReviewProcess=Run-Process $combinedReviewDiscover 'combined-review-discover';$combinedReviewReceipt=Join-Path $control 'combined-review-compact.json';Write-Json $combinedReviewReceipt $combinedReviewProcess.compactReceipt
    $combinedReviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedReviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedReviewReceipt;preparationReceipts=@($combinedReviewProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedReviewBoundary 'combined-review-admit').status-ceq'PASS') 'combined-late-reviewer-passes-initial-review-admission'
    $combinedReviewBoundary.mode='FINALIZE_OUTPUT';$combinedReviewBoundary.resultReceipts=@($combinedReviewProcess.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedReviewBoundary.deliveryReceipts=@('FIXTURE_FINDING_TO_WRITER')
    $findingFinal=Run-Process $combinedReviewBoundary 'combined-review-finalize' -ReviewOutcome CHANGES_REQUESTED
    Assert-True ($findingFinal.status-ceq'PASS'-and$findingFinal.consumer.recipient-ceq$combinedWriter) 'combined-late-reviewer-finalizes-actual-finding-to-writer'
    $actualFinding=$script:FixtureReviewFinalizes['combined-review-finalize']
    $combinedVerdictPath=$actualFinding.verdictPath
    $combinedBinding.phase='REPAIR';$combinedBinding.cycle=1;$combinedBinding.verdictPath=$actualFinding.verdictPath;$combinedBinding.verdictIdentity=$actualFinding.verdictIdentity
    foreach($field in @('verdictFinalizeInputPath','verdictFinalizeInputIdentity','verdictFinalizeResultPath','verdictFinalizeResultIdentity')){$combinedBinding[$field]=$actualFinding.$field}
    $combinedBinding.repairFinalizeInputPath='NOT_APPLICABLE';$combinedBinding.repairFinalizeInputIdentity='NOT_APPLICABLE';$combinedBinding.repairFinalizeResultPath='NOT_APPLICABLE';$combinedBinding.repairFinalizeResultIdentity='NOT_APPLICABLE'
    $combinedBinding.reviewerAssignment.threadId=$combinedReviewer
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$combinedBinding})
    $combinedRepair=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    Assert-True ($combinedRepair.status-ceq'PREPARED'-and(Invoke-Check $combinedRepair.package $combinedWriter SOURCE_WRITE).Code-eq0) 'combined-finding-returns-to-original-bound-writer'
    $combinedRepairPath=Join-Path $control 'combined-repair-package.json';Write-Json $combinedRepairPath $combinedRepair.package
    $combinedRepairDiscover=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$combinedRepairDiscover.observedActor=$combinedWriter;$combinedRepairDiscover.authorizationPackagePath=$combinedRepairPath;$combinedRepairDiscover.expectedAuthorizationIdentity=Get-Identity $combinedRepairPath;$combinedRepairDiscover.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json')
    $combinedRepairProcess=Run-Process $combinedRepairDiscover 'combined-repair-discover';$combinedRepairReceipt=Join-Path $control 'combined-repair-compact.json';Write-Json $combinedRepairReceipt $combinedRepairProcess.compactReceipt
    $combinedRepairBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedRepairReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedRepairReceipt;preparationReceipts=@($combinedRepairProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedRepairBoundary 'combined-repair-admit').status-ceq'PASS') 'combined-finding-repair-passes-real-admission'
    Write-Utf8 $objectPath 'Combined candidate repaired for rereview'
    $combinedRepairBoundary.mode='FINALIZE_OUTPUT';$combinedRepairBoundary.resultReceipts=@($combinedRepairProcess.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedRepairBoundary.deliveryReceipts=@('FIXTURE_REPAIR_RETURN')
    $combinedRepairFinal=Run-Process $combinedRepairBoundary 'combined-repair-finalize';$combinedRepairFinalPath=Join-Path $control 'combined-repair-final-result.json';Write-Json $combinedRepairFinalPath $combinedRepairFinal
    Assert-True ($combinedRepairFinal.status-ceq'PASS') 'combined-finding-repair-binds-real-postimage'
    $combinedBinding.phase='REREVIEW';$combinedBinding.repairFinalizeInputPath=Join-Path $control 'combined-repair-finalize.json';$combinedBinding.repairFinalizeInputIdentity=Get-Identity $combinedBinding.repairFinalizeInputPath;$combinedBinding.repairFinalizeResultPath=$combinedRepairFinalPath;$combinedBinding.repairFinalizeResultIdentity=Get-Identity $combinedRepairFinalPath
    Write-Json $routeInput ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$combinedBinding})
    $combinedRereview=(Invoke-AuthNative -NoProfile -File (Join-Path $PSScriptRoot '../scripts/resolve-workflow-route.ps1') -InputPath $routeInput -AsJson)|ConvertFrom-Json -Depth 100
    Assert-True ($combinedRereview.status-ceq'PREPARED'-and(Invoke-Check $combinedRereview.package $combinedReviewer REVIEW_EXECUTE).Code-eq0) 'combined-rereview-returns-to-same-independent-reviewer'
    $combinedRereviewPath=Join-Path $control 'combined-rereview-package.json';Write-Json $combinedRereviewPath $combinedRereview.package
    $combinedRereviewDiscover=$combinedReviewDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$combinedRereviewDiscover.authorizationPackagePath=$combinedRereviewPath;$combinedRereviewDiscover.expectedAuthorizationIdentity=Get-Identity $combinedRereviewPath
    $combinedRereviewProcess=Run-Process $combinedRereviewDiscover 'combined-rereview-discover';$combinedRereviewReceipt=Join-Path $control 'combined-rereview-compact.json';Write-Json $combinedRereviewReceipt $combinedRereviewProcess.compactReceipt
    $combinedRereviewBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$combinedRereviewReceipt;expectedDiscoverReceiptIdentity=Get-Identity $combinedRereviewReceipt;preparationReceipts=@($combinedRereviewProcess.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    Assert-True ((Run-Process $combinedRereviewBoundary 'combined-rereview-admit').status-ceq'PASS') 'combined-rereview-passes-real-admission'
    $combinedRereviewBoundary.mode='FINALIZE_OUTPUT';$combinedRereviewBoundary.resultReceipts=@($combinedRereviewProcess.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath));$combinedRereviewBoundary.deliveryReceipts=@('FIXTURE_REREVIEW_TO_OWNER')
    $approvalFinal=Run-Process $combinedRereviewBoundary 'combined-rereview-finalize'
    Assert-True ($approvalFinal.status-ceq'PASS'-and$approvalFinal.consumer.recipient-ceq'owner-fixture') 'combined-rereview-approval-finalizes-directly-to-owner'
  }finally{$env:CODEX_THREAD_ID=$oldHostId;[IO.File]::WriteAllBytes($combinedConfigPath,$combinedConfigOriginal)}
  $writerAccept=New-Package STANDARD TASK_OWNER writer-fixture RESULT_ACCEPT PRODUCT_RESULT
  $writerAccept.userConfirmation='USER_FIXTURE_ACCEPTED'
  Assert-True ((Invoke-Check $writerAccept writer-fixture RESULT_ACCEPT).Code-ne0) 'temporary-writer-cannot-accept-own-reviewed-result'
  Write-Task STANDARD REVIEW ACTIVE -OwnerRoute
  $ownerAccept=New-Package STANDARD TASK_OWNER owner-fixture RESULT_ACCEPT PRODUCT_RESULT
  $ownerAccept.userConfirmation='USER_FIXTURE_ACCEPTED'
  Assert-True ((Invoke-Check $ownerAccept owner-fixture RESULT_ACCEPT).Code-eq0) 'original-owner-alone-admits-final-acceptance'

  }
  if($Group-ceq'DeliveryAcceptance'){
  # Exercise the actual REVIEW_ROUTE final boundary and its delivery consumer.
  # All evidence and host observations below are isolated protocol fixtures.
  function Invoke-CandidateRoute($Value,[string]$Name,[switch]$Workflow){
    $inputPath=Join-Path $control ($Name+'.json');Write-Json $inputPath $Value
    $entry=if($Workflow){Join-Path $fixtureVersion 'scripts/resolve-workflow-route.ps1'}else{$resolver}
    $lines=@(Invoke-AuthNative -NoProfile -File $entry -InputPath $inputPath -AsJson 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
    $text=$lines-join"`n";Write-Utf8 (Join-Path $control ($Name+'-output.json')) $text
    return [pscustomobject]@{Code=$code;Text=$text;Value=($text|ConvertFrom-Json -Depth 100);InputPath=$inputPath}
  }
  $routeTaskBytes=[IO.File]::ReadAllBytes($taskPath)
  $missingRelative='src/deleted-candidate.txt';$missingPath=Join-Path $temp $missingRelative
  foreach($case in @('deleted-only','mixed')){
    $casePaths=if($case-ceq'deleted-only'){@($missingRelative)}else{@($objectRelative,$missingRelative)}
    Write-Task STANDARD REVIEW ACTIVE -OwnerRoute
    Write-Utf8 $taskPath ([IO.File]::ReadAllText($taskPath).Replace("expected_paths=[$objectRelative]",('expected_paths=['+($casePaths-join'|')+']')))
    $routePackage=New-Package STANDARD TASK_OWNER owner-fixture REVIEW_ROUTE ROUTINE_LOCAL
    $routePackage.exactPaths=@($casePaths)
    $routePackage.objectIdentities=@($casePaths|ForEach-Object{[ordered]@{path=$_;identity=$(if($_-ceq$missingRelative){'NEW'}else{Get-Identity (Join-Path $temp $_)})}})
    $routePackagePath=Join-Path $control ($case+'-route-package.json');Write-Json $routePackagePath $routePackage
    $pureReview=$routePackage|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $pureReview.actions=@('REVIEW_EXECUTE');$pureReview.grantee='reviewer-fixture';$pureReview.reviewIndependence='INDEPENDENT'
    $pureReview|Add-Member candidateWriter owner-fixture;$pureReview|Add-Member materialContributors @();$pureReview.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE')
    $pureReviewPath=Join-Path $control ($case+'-pure-review-package.json');Write-Json $pureReviewPath $pureReview
    $pureReviewIdentity=Get-Identity $pureReviewPath
    $routeDiscover=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $routeDiscover.expectedTaskIdentity=Get-Identity $taskPath;$routeDiscover.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json');$routeDiscover.expectedCorrectionsIdentity=Get-Identity (Join-Path $control 'corrections.json')
    $routeDiscover.observedActor='owner-fixture';$routeDiscover.exactPaths=@($casePaths);$routeDiscover.authorizationPackagePath=$routePackagePath;$routeDiscover.expectedAuthorizationIdentity=Get-Identity $routePackagePath
    $routeDiscover.intentEnvelope.objective='Deliver the exact candidate with absent objects for independent review'
    $routeDiscover.intentEnvelope.requestedActionKind='REVIEW_ROUTE';$routeDiscover.intentEnvelope.requestedResultKind='HANDOFF';$routeDiscover.intentEnvelope.semanticHints=@('review');$routeDiscover.intentEnvelope.pathHints=@($casePaths);$routeDiscover.intentEnvelope.mutationHints=@()
    $routeDiscovery=Invoke-CandidateRoute $routeDiscover ($case+'-route-discover')
    Assert-True ($routeDiscovery.Code-eq0-and$routeDiscovery.Value.status-ceq'PASS') ($case+'-route-real-discover')
    $pureDiscover=$routeDiscover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $pureDiscover.observedActor='reviewer-fixture';$pureDiscover.authorizationPackagePath=$pureReviewPath;$pureDiscover.expectedAuthorizationIdentity=$pureReviewIdentity
    $pureDiscover.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$pureDiscover.intentEnvelope.requestedResultKind='REVIEW_VERDICT'
    $pureDiscovery=Invoke-CandidateRoute $pureDiscover ($case+'-pure-review-discover')
    Assert-True ($pureDiscovery.Code-eq0-and$pureDiscovery.Value.status-ceq'PASS') ($case+'-pure-review-package-valid')
    $routeReceipt=Join-Path $control ($case+'-route-receipt.json');Write-Json $routeReceipt $routeDiscovery.Value.compactReceipt
    $requirementsPath=Join-Path $control ($case+'-route-requirements.md');Write-Utf8 $requirementsPath 'Fixture: preserve every candidate, including absence, through the actual review delivery boundary.'
    $requirements=[ordered]@{path=$requirementsPath;identity=Get-Identity $requirementsPath}
    $candidates=@($routePackage.objectIdentities|ForEach-Object{[ordered]@{path=$_.path;identity=$(if($_.identity-ceq'NEW'){'MISSING'}else{$_.identity})}})
    $selfPath=Join-Path $control ($case+'-route-self-check.json')
    Write-Json $selfPath ([ordered]@{schemaVersion=1;taskId='AUTH-REGRESSION-001';actor='owner-fixture';candidateObjects=$candidates;requirementsRef=$requirements;outcome='PASS';checks=@([ordered]@{id='route-candidate-fixture';method='MODEL_JUDGMENT';outcome='PASS';reason='Isolated protocol evidence, not a product or host acceptance claim.';evidenceLocators=@($requirements)});evidenceLocators=@($requirements)})
    $routeBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$routeReceipt;expectedDiscoverReceiptIdentity=Get-Identity $routeReceipt;preparationReceipts=@($routeDiscovery.Value.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE';evidenceRefs=@([ordered]@{kind='SELF_CHECK';path=$selfPath;identity=Get-Identity $selfPath})}
    $routeBoundary.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='reviewer-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=[ordered]@{path=$pureReviewPath;identity=$pureReviewIdentity}}
    $routeAdmission=Invoke-CandidateRoute $routeBoundary ($case+'-route-admit')
    Assert-True ($routeAdmission.Code-eq0-and$routeAdmission.Value.status-ceq'PASS') ($case+'-route-real-admission')
    if($case-ceq'deleted-only'){
      $missingRefBoundary=$routeBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      $missingRefBoundary.deliveryContext.PSObject.Properties.Remove('reviewPackageRef')
      $missingRefAdmission=Invoke-CandidateRoute $missingRefBoundary ($case+'-admit-missing-review-ref')
      Assert-True ($missingRefAdmission.Code-ne0-and$missingRefAdmission.Value.reason-ceq'DELIVERY_REVIEW_WRITER_REQUIRED') 'candidate-route-admission-rejects-missing-review-ref'
      $wrongWriterReview=$pureReview|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongWriterReview.candidateWriter='other-writer-fixture'
      $wrongWriterPath=Join-Path $control ($case+'-wrong-writer-review-package.json');Write-Json $wrongWriterPath $wrongWriterReview
      $wrongWriterBoundary=$routeBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      $wrongWriterBoundary.deliveryContext.reviewPackageRef=[pscustomobject]@{path=$wrongWriterPath;identity=Get-Identity $wrongWriterPath}
      $wrongWriterAdmission=Invoke-CandidateRoute $wrongWriterBoundary ($case+'-admit-wrong-writer')
      Assert-True ($wrongWriterAdmission.Code-ne0-and$wrongWriterAdmission.Value.reason-ceq'DELIVERY_REVIEW_WRITER_DRIFT') 'candidate-route-admission-rejects-wrong-writer'
    }
    $routeBoundary.mode='FINALIZE_OUTPUT';$routeBoundary.resultReceipts=@($routeDiscovery.Value.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@($candidates|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.identity})
    $prepared=Invoke-CandidateRoute $routeBoundary ($case+'-route-prepare')
    Assert-True ($prepared.Code-ne0-and$prepared.Value.status-ceq'BLOCKED'-and$prepared.Value.delivery.status-ceq'READY_TO_SEND'-and@($prepared.Value.missingPreparation).Count-eq0-and(@($prepared.Value.missingResult)-join'|')-ceq'DELIVERY_NOT_CONFIRMED') ($case+'-prepare-binds-candidate-without-claiming-delivery')
    $hostPath=Join-Path $control ($case+'-mock-send-result.json');Write-Json $hostPath ([ordered]@{isError=$false;content=@([ordered]@{type='text';text='{"threadId":"reviewer-fixture"}'})})
    $routeBoundary.deliveryContext.stage='OBSERVE';$routeBoundary.deliveryContext.observedRecipient='reviewer-fixture';$routeBoundary.deliveryContext.outcome='SUCCESS';$routeBoundary.deliveryContext.evidence=$hostPath+'#'+(Get-Identity $hostPath)
    $observed=Invoke-CandidateRoute $routeBoundary ($case+'-route-observe')
    Assert-True ($observed.Code-eq0-and$observed.Value.status-ceq'PASS'-and$observed.Value.delivery.status-ceq'DELIVERED') ($case+'-observe-finalizes-with-bound-host-fixture')
    $workflow=Invoke-CandidateRoute ([ordered]@{operation='DELIVERY';boundaryInputRef=[ordered]@{path=$observed.InputPath;identity=Get-Identity $observed.InputPath}}) ($case+'-workflow-delivery') -Workflow
    Assert-True ($workflow.Code-eq0-and$workflow.Value.status-ceq'PASS'-and$workflow.Value.consumer.recipient-ceq'reviewer-fixture') ($case+'-workflow-delivery-reuses-real-final-boundary')
    Assert-True ((Get-Identity $pureReviewPath)-ceq$pureReviewIdentity-and@($pureReview.objectIdentities|Where-Object{$_.path-ceq$missingRelative})[0].identity-ceq'NEW') ($case+'-authorization-preimage-not-rewritten')

    $wrongSet=$pureReview|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$wrongSet.objectIdentities=@($wrongSet.objectIdentities|Where-Object{$_.path-cne$missingRelative})
    $wrongSetPath=Join-Path $control ($case+'-wrong-set-package.json');Write-Json $wrongSetPath $wrongSet
    $badBoundary=$routeBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badBoundary.deliveryContext.reviewPackageRef.path=$wrongSetPath;$badBoundary.deliveryContext.reviewPackageRef.identity=Get-Identity $wrongSetPath
    if($wrongSet.objectIdentities.Count-eq0){
      $emptySetResult=Invoke-CandidateRoute $badBoundary ($case+'-empty-set')
      Assert-True ($emptySetResult.Code-ne0-and$emptySetResult.Value.reason-ceq'DELIVERY_REVIEW_CANDIDATE_SET') ($case+'-delivery-rejects-empty-candidate-set')
      $wrongSet.objectIdentities=@([pscustomobject]@{path=$objectRelative;identity=Get-Identity $objectPath})
      Write-Json $wrongSetPath $wrongSet;$badBoundary.deliveryContext.reviewPackageRef.identity=Get-Identity $wrongSetPath
    }
    $wrongSetResult=Invoke-CandidateRoute $badBoundary ($case+'-wrong-set')
    if(-not$wrongSetResult.Text.Contains('DELIVERY_REVIEW_CANDIDATE_SET')){Write-Output ('DIAG|wrong-set|'+$wrongSetResult.Text)}
    Assert-True ($wrongSetResult.Code-ne0-and$wrongSetResult.Value.reason-ceq'DELIVERY_REVIEW_CANDIDATE_SET') ($case+'-delivery-rejects-omitted-absent-object')
    $badBoundary=$routeBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badBoundary.deliveryContext.reviewPackageRef.path=Join-Path $control ($case+'-missing-review-package.json')
    $missingEvidence=Invoke-CandidateRoute $badBoundary ($case+'-missing-evidence')
    Assert-True ($missingEvidence.Code-ne0-and$missingEvidence.Text.Contains('EVIDENCE_OBJECT_MISSING')) ($case+'-ordinary-review-evidence-must-exist')
    Write-Utf8 $missingPath 'Unexpected reappearance after review preparation'
    try{
      $reappeared=Invoke-CandidateRoute $routeBoundary ($case+'-reappeared')
      Assert-True ($reappeared.Code-ne0-and$reappeared.Value.reason-ceq('RESULT_POSTIMAGE_RECEIPT_REQUIRED|'+$missingRelative)) ($case+'-reappeared-candidate-rejects-finalization')
    }finally{
      if(-not[IO.Path]::GetFullPath($missingPath).StartsWith([IO.Path]::GetFullPath($temp)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'FIXTURE_CLEANUP_PATH'}
      Remove-Item -LiteralPath $missingPath -Force
    }
  }
  [IO.File]::WriteAllBytes($taskPath,$routeTaskBytes)

  }
  if($Group-cin@('ContinuationRepair','ExecutionTarget')){
  $lifecycleRuntime=Join-Path $control 'runtime/AUTH-REGRESSION-001/writer-fixture';$null=[IO.Directory]::CreateDirectory($lifecycleRuntime)
  if($Group-ceq'ExecutionTarget'){$initial=$discover|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100}
  # Bounded self-test continuation: actual subprocess observations are supplied
  # explicitly. The older synthetic protocol helper must not replace FAIL.
  $selfOriginalObject=[IO.File]::ReadAllBytes($objectPath)
  $selfRequirementsPath=Join-Path $control 'self-repair-requirements.md'
  Write-Utf8 $selfRequirementsPath 'Only FIXED candidates pass this isolated command. A failed test may repair or retest within its original grant; successful review never consumes failed/incomplete evidence.'
  $selfRequirements=[ordered]@{path=$selfRequirementsPath;identity=Get-Identity $selfRequirementsPath}
  $selfProbe=Join-Path $control 'self-probe.ps1'
  Write-Utf8 $selfProbe ("param([string]`$Candidate,[string]`$TransientMarker)`nif(`$TransientMarker){if(-not(Test-Path -LiteralPath `$TransientMarker)){[IO.File]::WriteAllText(`$TransientMarker,'observed');Write-Output 'actual transient failure';exit 1};Write-Output 'actual transient recovery';exit 0}`nif([IO.File]::ReadAllText(`$Candidate).Contains('FIXED')){Write-Output 'actual candidate PASS';exit 0};Write-Output 'actual candidate FAIL';exit 1")
  function Start-SelfGrant([string]$Name,[int]$Limit=2,[switch]$NoPolicy,[switch]$Linear,[switch]$TestWrite){
    Write-Utf8 $objectPath ('BROKEN '+$Name)
    $write=if($TestWrite){'TEST_WRITE'}else{'SOURCE_WRITE'}
    $pkg=New-Package STANDARD TASK_OWNER writer-fixture $write ROUTINE_LOCAL
    $pkg.actions=@($write,'TEST_RUN','REVIEW_ROUTE');$pkg['continuationPlan']=@($write,'TEST_RUN','REVIEW_ROUTE')
    $pkg['repairReviewPlan']=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@()}
    $pkg.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
    if($Linear){$pkg.actions=@($write,'TEST_RUN');$pkg.continuationPlan=@($write,'TEST_RUN',$write)}
    if(-not$NoPolicy){$pkg['selfCheckRepairLimit']=$Limit}
    $path=Join-Path $control ($Name+'-grant.json');Write-Json $path $pkg
    return [pscustomobject]@{Name=$Name;Path=$path;Package=$pkg}
  }
  function Enter-SelfStep($Grant,[string]$Action,[string]$Name,[string]$Previous='', [switch]$AllowFailure,[string[]]$Scope=@(),$Evidence=@(),$ReviewPackageRef=$null){
    $input=$initial|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $input.authorizationPackagePath=$Grant.Path;$input.expectedAuthorizationIdentity=Get-Identity $Grant.Path
    $input.expectedTaskIdentity=Get-Identity $taskPath
    $input.expectedProjectConfigIdentity=Get-Identity (Join-Path $control 'project.json')
    if($Group-ceq'ExecutionTarget'){$input.schemaVersion=5;$input|Add-Member ruleLoad ([pscustomobject]@{mode='FULL'}) -Force;$input|Add-Member executionTargetRef $Grant.Package.executionTargetRef -Force}
    $input.intentEnvelope.objective='Implement and validate the granted bounded self-test continuation'
    $input.intentEnvelope.requestedActionKind=$Action
    $input.intentEnvelope.requestedResultKind=if($Action-ceq'TEST_RUN'){'TEST_RESULT'}else{'IMPLEMENTATION_RESULT'}
    $input.intentEnvelope.mutationHints=@(if($Action-cin@('TEST_WRITE','TEST_RUN')){'test'}else{'source'})
    if($Scope.Count){$input.exactPaths=@($Scope);$input.intentEnvelope.pathHints=@($Scope)}
    if($Action-ceq'REVIEW_ROUTE'){$input.intentEnvelope.requestedResultKind='HANDOFF';$input.intentEnvelope.mutationHints=@('review');$input.intentEnvelope.semanticHints=@('review','handoff')}
    if($Action-ceq'REVIEW_EXECUTE'){$input.observedActor=$Grant.Package.grantee;$input.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$input.intentEnvelope.mutationHints=@();$input.intentEnvelope.semanticHints=@('review')}
    if($Action-cin@('RESULT_ACCEPT','CONTROL_WRITE','GIT_STAGE','GIT_COMMIT')){$input.observedActor=$Grant.Package.grantee;$input.intentEnvelope.mutationHints=@(if($Action-ceq'CONTROL_WRITE'){'control'});$input.intentEnvelope.requestedResultKind=if($Action-ceq'RESULT_ACCEPT'){'RESULT_ACCEPTANCE'}else{'IMPLEMENTATION_RESULT'}}
    if($Previous){$input|Add-Member continuationReceiptPath $Previous -Force;$input|Add-Member expectedContinuationReceiptIdentity (Get-Identity $Previous) -Force}
    $discovered=Run-Process $input ($Name+'-discover') -AllowFailure:$AllowFailure -UseProvidedEvidence
    if($discovered.status-cne'PASS'){return [pscustomobject]@{Result=$discovered;Input=$input}}
    $receipt=Join-Path $(if($LifecycleOnly){Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$Grant.Package.grantee)}else{$control}) ($Name+'-compact.json');Write-Json $receipt $discovered.compactReceipt
    $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receipt;expectedDiscoverReceiptIdentity=Get-Identity $receipt;preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE';evidenceRefs=@($Evidence)}
    if($null-ne$ReviewPackageRef){$boundary['deliveryContext']=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient=(Get-Content -LiteralPath $ReviewPackageRef.path -Raw|ConvertFrom-Json -Depth 100).grantee;observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=$ReviewPackageRef}}
    $admitted=Run-Process $boundary ($Name+'-admit') -UseProvidedEvidence
    if($admitted.status-cne'PASS'){throw ('SELF_STEP_NOT_ADMITTED|'+$Name)}
    return [pscustomobject]@{Name=$Name;Result=$discovered;Boundary=$boundary;Input=$input}
  }
  function Observe-SelfCommand([string]$Name,[string]$Marker=''){
    $args=@('-NoProfile','-NonInteractive','-File',$selfProbe,'-Candidate',$objectPath)
    if($Marker){$args+=@('-TransientMarker',$Marker)}
    $output=@(Invoke-AuthNative @args 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
    $outputPath=Join-Path $control ($Name+'-actual-output.txt');Write-Utf8 $outputPath ($output-join"`n")
    $commandPath=Join-Path $control ($Name+'-actual-command.json')
    Write-Json $commandPath ([ordered]@{command=('pwsh '+($args-join' '));exitCode=$code;output=[ordered]@{path=$outputPath;identity=Get-Identity $outputPath}})
    $outcome=if($code-eq0){'PASS'}else{'FAIL'}
    $commandRef=[ordered]@{path=$commandPath;identity=Get-Identity $commandPath}
    $record=[ordered]@{schemaVersion=1;taskId='AUTH-REGRESSION-001';actor='writer-fixture';candidateObjects=@([ordered]@{path=$objectRelative;identity=Get-Identity $objectPath});requirementsRef=$selfRequirements;outcome=$outcome;checks=@([ordered]@{id=$Name;method='COMMAND';outcome=$outcome;reason='Actual isolated subprocess exit and output; transient retry is justified by the explicit one-shot marker.';evidenceLocators=@($commandRef)});evidenceLocators=@($selfRequirements,[ordered]@{path=$objectPath;identity=Get-Identity $objectPath})}
    $path=Join-Path $control ($Name+'-self.json');Write-Json $path $record
    return [ordered]@{kind='SELF_CHECK';path=$path;identity=Get-Identity $path}
  }
  function Finish-SelfStep($Step,[string]$Name,$Refs=@(),[string]$Disposition='', [switch]$AllowFailure,[string]$ReviewOutcome='APPROVED',[string[]]$ConsumedRuntimePath=@(),[switch]$KeepInputForRecovery,[switch]$ConsumeFinalInput){
    $boundary=$Step.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $candidateRoot=if($Group-ceq'ExecutionTarget'){$targetRoot}else{$temp}
    $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($Step.Result.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@($Step.Input.exactPaths|ForEach-Object{$p=Join-Path $candidateRoot $_;'OBJECT_POSTIMAGE|'+$_+'|'+$(if(Test-Path -LiteralPath $p -PathType Leaf){Get-Identity $p}else{'MISSING'})});$boundary.evidenceRefs=@($Refs)
    if($Disposition){$boundary|Add-Member continuationDisposition $Disposition}
    if($Step.Input.intentEnvelope.requestedActionKind-ceq'RESULT_ACCEPT'){$boundary.deliveryReceipts=@('NATIVE_RESPONSE|fixture-owner-acceptance')}
    $result=Run-Process $boundary $Name -AllowFailure:$AllowFailure -UseProvidedEvidence -ReviewOutcome $ReviewOutcome -ConsumedRuntimePath $ConsumedRuntimePath -KeepInputForRecovery:$KeepInputForRecovery -ConsumeFinalInput:$ConsumeFinalInput
    $resultPath=Join-Path $control ($Name+'-result.json');Write-Json $resultPath $result
    $continuation='';if($null-ne$result.PSObject.Properties['continuationReceipt']){$continuation=Join-Path $(if($LifecycleOnly){$lifecycleRuntime}else{$control}) ($Name+'-continuation.json');Write-Json $continuation $result.continuationReceipt}
    return [pscustomobject]@{Name=$Name;Result=$result;InputPath=(Join-Path $(if($LifecycleOnly-and$ConsumeFinalInput){Join-Path $control ('runtime/AUTH-REGRESSION-001/'+$Step.Result.compactReceipt.binding.actor)}else{$control}) ($Name+'.json'));ResultPath=$resultPath;Continuation=$continuation}
  }
  function Get-SelfReview($Grant,$Final,[string]$Name,[switch]$AllowFailure){
    $b=[ordered]@{parentPackagePath=$Grant.Path;parentPackageIdentity=Get-Identity $Grant.Path;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=$Final.InputPath;repairFinalizeInputIdentity=Get-Identity $Final.InputPath;repairFinalizeResultPath=$Final.ResultPath;repairFinalizeResultIdentity=Get-Identity $Final.ResultPath}
    $p=Join-Path $control ($Name+'-route.json');Write-Json $p ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$b})
    $out=@(Invoke-AuthNative -NoProfile -File (Join-Path $fixtureVersion 'scripts/resolve-workflow-route.ps1') -InputPath $p -AsJson 2>&1|ForEach-Object{[string]$_})
    if($LASTEXITCODE-ne0){if($AllowFailure){return [pscustomobject]@{status='REJECTED';reason=($out-join"`n")}};throw ('REAL_REVIEW_FACTORY_FAILED|'+$Name+'|'+($out-join"`n"))}
    return ($out-join"`n")|ConvertFrom-Json -Depth 100
  }

  if($Group-ceq'ExecutionTarget'){
    # A real initialization failure must survive native raw capture even when
    # the original exception and stack contain a non-ASCII path.
    $errorProbe=Join-Path $control '错误出口/authorization-receipt-regression-tests.ps1'
    Write-Utf8 $errorProbe ([IO.File]::ReadAllText($PSCommandPath))
    $errorRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',$errorProbe,'-Group','ExecutionTarget') -GroupId 'authorization-initialization-error-transport'
    $errorRecord=$errorRun.Text|ConvertFrom-Json -Depth 100
    Assert-True ($errorRun.Code-ne0-and$errorRun.Text-cnotmatch'[^\x00-\x7f]'-and$errorRecord.status-ceq'FAIL'-and$errorRecord.reason.Contains('错误出口')-and-not[string]::IsNullOrWhiteSpace($errorRecord.scriptStackTrace)-and-not[string]::IsNullOrWhiteSpace($errorRecord.fullyQualifiedErrorId)) 'target-initialization-error-is-lossless-ascii-json-and-nonzero'
    # Real native operations and current Git observations; only actor decisions
    # and host sends are simulated. Neither source repository is a fixture.
    function Target-Git([string[]]$Arguments,[string]$Root=$targetRoot){
      $run=Invoke-AiwTestProcess (Get-Command git -CommandType Application).Source (@('-C',$Root)+$Arguments) -WorkingDirectory $Root -GroupId 'w4-actual-target-git'
      if($run.Code-ne0){throw ('TARGET_GIT|'+$run.Text)};return $run.Text.Trim()
    }
    $targetRoot=Join-Path $temp 'wt-工作树-😀'
    $null=Target-Git @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','Owned target baseline') $temp
    $null=Target-Git @('worktree','add','-q','-b','w4-target',$targetRoot,'HEAD') $temp
    Write-Utf8 (Join-Path $targetRoot '.ai-workspace/project.json') '{"stale-shadow":"never-authority"}'
    $selectionPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/owner-fixture/target-decision.txt'
    Write-Utf8 $selectionPath 'Isolated selection of this exact worktree; local Git only. Actors and host outcomes are simulated.'
    $descriptorPath=Join-Path $control 'runtime/AUTH-REGRESSION-001/owner-fixture/target.json'
    $head=Target-Git @('rev-parse','HEAD')
    $state=[pscustomobject]@{branch='w4-target';head=$head.ToUpperInvariant()}
    Write-Json $descriptorPath ([ordered]@{schemaVersion=1;kind='EXECUTION_TARGET';projectId='authorization-receipt-fixture';taskId='AUTH-REGRESSION-001';controlRoot=$temp;targetKind='GIT_WORKTREE';targetRoot=$targetRoot;gitBinding=[ordered]@{commonGitDir=[IO.Path]::GetFullPath((Target-Git @('rev-parse','--path-format=absolute','--git-common-dir') $temp));worktreeGitDir=[IO.Path]::GetFullPath((Target-Git @('rev-parse','--absolute-git-dir')));gitTop=$targetRoot;branch='w4-target';baselineCommit=$head};selectionDecisionRef=[ordered]@{path=$selectionPath;identity=Get-Identity $selectionPath};hostWorktreeRef=$null})
    $targetRef=[pscustomobject]@{path=$descriptorPath;identity=Get-Identity $descriptorPath}
    Write-Task STANDARD IMPLEMENT
    [IO.File]::AppendAllText($taskPath,('- Execution target: '+$descriptorPath+'#'+$targetRef.identity+"`n"),$utf8)
    $objectPath=Join-Path $targetRoot $objectRelative
    $companion='src/unchanged.txt';$companionPath=Join-Path $targetRoot $companion
    Write-Utf8 $objectPath 'return (10 / $InputValue)'
    Write-Utf8 $companionPath 'Frozen review companion.'
    # Same relative name and bytes in control must not qualify as target evidence.
    Write-Utf8 (Join-Path $temp $objectRelative) 'return (10 / $InputValue)'
    $companionIdentity=Get-Identity $companionPath
    $probe=Join-Path $control 'runtime/AUTH-REGRESSION-001/owner-fixture/probe.ps1'
    Write-Utf8 $probe ((@'
param([string]$Candidate,[double]$InputValue)
__AIW_TEST_NATIVE_OUTPUT__
$ErrorActionPreference='Stop'
try{$f=[scriptblock]::Create([IO.File]::ReadAllText($Candidate));$value=& $f;Write-Output ('cwd='+(Get-Location).Path+'; value='+$value);if([double]::IsInfinity([double]$value)-or[double]::IsNaN([double]$value)){exit 1};exit 0}catch{Write-Output $_.Exception.Message;exit 1}
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
    Write-Utf8 $selfRequirementsPath 'Finite output: input 2 returns 5; input zero returns 0. The frozen companion must remain unchanged. Original self-repair budget and independent review cycles do not reset. Native target execution is required; host/actor decisions are fixture simulations.'
    $selfRequirements=[ordered]@{path=$selfRequirementsPath;identity=Get-Identity $selfRequirementsPath}
    function Target-Candidates([string[]]$Paths){@($Paths|ForEach-Object{[ordered]@{path=$_;identity=Get-Identity (Join-Path $targetRoot $_)}})}
    function Target-Command([string]$Name,[double]$Number){
      $args=@('-NoProfile','-NonInteractive','-File',$probe,'-Candidate',$objectPath,'-InputValue',$Number.ToString([Globalization.CultureInfo]::InvariantCulture))
      $run=Invoke-AiwTestProcess ([Environment]::ProcessPath) $args -WorkingDirectory $targetRoot -GroupId 'w4-native-counterexample'
      $outputPath=Join-Path $control ($Name+'-output.txt');Write-Utf8 $outputPath $run.Text
      $commandPath=Join-Path $control ($Name+'-command.json');Write-Json $commandPath ([ordered]@{command=('pwsh '+($args-join' '));exitCode=$run.Code;output=[ordered]@{path=$outputPath;identity=Get-Identity $outputPath}})
      return [pscustomobject]@{Code=$run.Code;Ref=[ordered]@{path=$commandPath;identity=Get-Identity $commandPath}}
    }
    function Target-Record([string]$Name,[string]$Actor,[string]$Outcome,[string]$Kind,[string[]]$Paths,$Command=$null,$Grant=$null,$Flat=$null,$Prerequisites=@()){
      $checkOutcome=if($Outcome-cin@('FAIL','CHANGES_REQUESTED')){'FAIL'}else{'PASS'}
      $checks=if($null-ne$Command){@([ordered]@{id=$Name;method='COMMAND';outcome=$checkOutcome;reason='Actual owned-worktree native subprocess and exit. The zero case is a real counterexample.';evidenceLocators=@($Command.Ref)})}else{@([ordered]@{id=$Name;method='MODEL_JUDGMENT';outcome='PASS';reason='Fixture actor examined current whole candidate, native observations and frozen companion. No real host or external acceptance is claimed.';evidenceLocators=@($selfRequirements)+@($Prerequisites|ForEach-Object{[ordered]@{path=$_.path;identity=$_.identity}})})}
      $record=[ordered]@{schemaVersion=2;taskId='AUTH-REGRESSION-001';actor=$Actor;candidateObjects=@(Target-Candidates $Paths);requirementsRef=$selfRequirements;outcome=$Outcome;checks=@($checks);evidenceLocators=@($selfRequirements)+@($Prerequisites|ForEach-Object{[ordered]@{path=$_.path;identity=$_.identity}});executionTargetRef=$targetRef;candidateTargetState=$state}
      if($null-ne$Grant){$record.authorizationRef=[ordered]@{path=$Grant.Path;identity=Get-Identity $Grant.Path}}
      if($null-ne$Flat){$record.evidenceLocators+=@($Flat)}
      $path=Join-Path $control ($Name+'-typed.json');Write-Json $path $record
      return [ordered]@{kind=$Kind;path=$path;identity=Get-Identity $path}
    }
    function Target-Factory($Binding,[string]$Name){
      $p=Join-Path $control ($Name+'-factory.json');Write-Json $p ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$targetRoot;controlRoot=$temp;taskPath=$taskRelative;binding=$Binding})
      $out=@(Invoke-AuthNative -NoProfile -File (Join-Path $fixtureVersion 'scripts/resolve-workflow-route.ps1') -InputPath $p -AsJson)
      if($LASTEXITCODE-ne0){throw ('TARGET_FACTORY|'+$Name+'|'+($out-join"`n"))}
      $prepared=($out-join"`n")|ConvertFrom-Json -Depth 100
      $grant=[pscustomobject]@{Path=(Join-Path $control ($Name+'-package.json'));Package=$prepared.package};Write-Json $grant.Path $grant.Package;return $grant
    }
    function Target-Binding($Final,[string]$Phase='INITIAL_REVIEW',[int]$Cycle=0,$Finding=$null){
      $b=[ordered]@{parentPackagePath=$grant.Path;parentPackageIdentity=Get-Identity $grant.Path;phase=$Phase;cycle=$Cycle;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=$Final.InputPath;repairFinalizeInputIdentity=Get-Identity $Final.InputPath;repairFinalizeResultPath=$Final.ResultPath;repairFinalizeResultIdentity=Get-Identity $Final.ResultPath}
      if($null-ne$Finding){$b.verdictPath=$Finding.Flat.path;$b.verdictIdentity=$Finding.Flat.identity;$b.verdictFinalizeInputPath=$Finding.Final.InputPath;$b.verdictFinalizeInputIdentity=Get-Identity $Finding.Final.InputPath;$b.verdictFinalizeResultPath=$Finding.Final.ResultPath;$b.verdictFinalizeResultIdentity=Get-Identity $Finding.Final.ResultPath}
      if($Phase-ceq'REPAIR'){foreach($n in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){$b[$n]='NOT_APPLICABLE'}}
      return $b
    }
    function Target-Route($Producer,$Final,$Review,[string]$Name){
      $ready=Target-Record ($Name+'-ready') writer-fixture PASS SELF_CHECK @($objectRelative,$companion) -Prerequisites @($currentSelf)
      $step=Enter-SelfStep $Producer REVIEW_ROUTE $Name $Final.Continuation -Scope @($objectRelative,$companion) -Evidence @($ready) -ReviewPackageRef ([pscustomobject]@{path=$Review.Path;identity=Get-Identity $Review.Path})
      $closed=Finish-SelfStep $step ($Name+'-final') @($ready)
      Assert-True ($closed.Result.status-ceq'PASS'-and$closed.Result.consumer.recipient-ceq'reviewer-fixture') ($Name+'-writer-own-route-to-same-reviewer')
    }
    function Target-Review($Review,[string]$Name,[double]$Number){
      $step=Enter-SelfStep $Review REVIEW_EXECUTE $Name -Scope @($objectRelative,$companion)
      $command=Target-Command $Name $Number
      $outcome=if($command.Code-eq0){'APPROVED'}else{'CHANGES_REQUESTED'}
      $flatPath=Join-Path $control ($Name+'-flat.json')
      Write-Json $flatPath ([ordered]@{taskId='AUTH-REGRESSION-001';owner='owner-fixture';reviewer='reviewer-fixture';writer='writer-fixture';cycle=$Review.Package.repairReviewBinding.cycle;verdict=$outcome;exactPaths=@($Review.Package.exactPaths);objectIdentities=@($Review.Package.objectIdentities);findingPaths=@(if($outcome-ceq'CHANGES_REQUESTED'){$objectRelative});scopeChanged=$false;decisionChanged=$false})
      $flat=[ordered]@{path=$flatPath;identity=Get-Identity $flatPath}
      $typed=Target-Record $Name reviewer-fixture $outcome REVIEW_VERDICT @($objectRelative,$companion) $command $Review $flat
      $closed=Finish-SelfStep $step ($Name+'-final') @($typed) -ReviewOutcome $outcome
      Assert-True ($closed.Result.status-ceq'PASS'-and$closed.Result.consumer.recipient-ceq$(if($command.Code-eq0){'owner-fixture'}else{'writer-fixture'})) ($Name+'-actual-command-drives-flat-typed-and-direct-consumer')|ForEach-Object{Write-Host $_}
      return [pscustomobject]@{Final=$closed;Flat=$flat;Typed=$typed;Code=$command.Code}
    }
    $pkg=New-Package STANDARD TASK_OWNER writer-fixture SOURCE_WRITE ROUTINE_LOCAL
    $pkg.schemaVersion=4;$pkg.repositoryId='PROJECT';$pkg.controlRoot=$temp;$pkg.executionTargetRef=$targetRef;$pkg.expectedTargetState=$state
    $pkg.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$pkg.continuationPlan=@($pkg.actions);$pkg.selfCheckRepairLimit=2;$pkg.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT','REPOSITORY_CHANGE')
    $pkg.repairReviewPlan=[ordered]@{writer='writer-fixture';reviewer='reviewer-fixture';maxCycles=2;materialContributors=@('owner-fixture');reviewScope=@(Target-Candidates @($objectRelative,$companion))}
    $grant=[pscustomobject]@{Path=(Join-Path $control 'target-parent.json');Package=$pkg};Write-Json $grant.Path $pkg
    Assert-True ((Invoke-Check $pkg writer-fixture SOURCE_WRITE).Code-eq0) 'target-package4-checker-uses-control-authority-and-real-target'
    $source=Enter-SelfStep $grant SOURCE_WRITE 'target-source'
    Write-Utf8 $objectPath "throw 'Actual initial positive-case defect'"
    $sourceFinal=Finish-SelfStep $source 'target-source-final'
    $firstTest=Enter-SelfStep $grant TEST_RUN 'target-first-test' $sourceFinal.Continuation
    $firstNative=Target-Command 'target-initial-failure' 2
    Assert-True ($firstNative.Code-ne0) 'target-initial-native-self-failure'
    $failedSelf=Target-Record 'target-initial-failed-self' writer-fixture FAIL SELF_CHECK @($objectRelative) $firstNative
    $failedFinal=Finish-SelfStep $firstTest 'target-first-failure-final' @($failedSelf) REPAIR
    $selfRepair=Enter-SelfStep $grant SOURCE_WRITE 'target-self-repair' $failedFinal.Continuation
    Write-Utf8 $objectPath 'return (10 / $InputValue) # repaired positive case'
    $selfRepaired=Finish-SelfStep $selfRepair 'target-self-repaired-final'
    $test=Enter-SelfStep $grant TEST_RUN 'target-test' $selfRepaired.Continuation
    $native=Target-Command 'target-positive' 2
    Assert-True ($native.Code-eq0) 'target-native-self-positive-case'
    $currentSelf=Target-Record 'target-self' writer-fixture PASS SELF_CHECK @($objectRelative) $native
    $testFinal=Finish-SelfStep $test 'target-test-final' @($currentSelf)
    Assert-True ($testFinal.Result.continuationReceipt.selfRepairCycle-eq1) 'target-one-self-repair-before-independent-review'
    Import-Module (Join-Path $fixtureVersion 'scripts/ResultEvidence.psm1') -Force
    $evidenceContext=New-AiwPackageEvidenceContext $temp ($pkg|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100) $frameworkRoot -TaskPath $taskRelative
    $actualRecord=Get-Content -LiteralPath $currentSelf.path -Raw|ConvertFrom-Json -Depth 100
    # This is a fixture copy, outside the governed actor's writes. Equal bytes
    # cannot make the control-root file qualify as target evidence.
    [IO.File]::WriteAllBytes((Join-Path $temp $objectRelative),[IO.File]::ReadAllBytes($objectPath))
    Assert-True ((Get-Identity (Join-Path $temp $objectRelative))-ceq(Get-Identity $objectPath)) 'target-wrong-root-fixture-has-actually-identical-bytes'
    function Target-Reject([scriptblock]$Action,[string]$Reason,[string]$Name){$caught='';try{$null=& $Action}catch{$caught=$_.Exception.Message};if($caught-cnotmatch$Reason){throw ('TARGET_EXPECTED_REJECTION|'+$Name+'|'+$caught)};Assert-True $true $Name}
    $legacy=$actualRecord|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$legacy.schemaVersion=1;$legacy.PSObject.Properties.Remove('executionTargetRef');$legacy.PSObject.Properties.Remove('candidateTargetState')
    $legacyPath=Join-Path $control 'target-legacy-same-bytes.json';Write-Json $legacyPath $legacy
    $legacyRef=[pscustomobject]@{kind='SELF_CHECK';path=$legacyPath;identity=Get-Identity $legacyPath}
    Target-Reject {Read-AiwResultEvidence $evidenceContext $legacyRef AUTH-REGRESSION-001 $legacy.candidateObjects $selfRequirements} 'SCHEMA2|TARGET' 'target-type1-same-path-and-control-bytes-cannot-qualify'
    foreach($bound in @('src/unreadable.txt',([IO.Path]::GetFullPath((Join-Path $temp 'src/unreadable.txt')).Replace('\','/')))){
      $guardContext=New-AiwPackageEvidenceContext $temp ($pkg|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100) $frameworkRoot -TaskPath $taskRelative -ProtectedPaths @($bound)
      Target-Reject {Read-AiwEvidenceReference $guardContext ([pscustomobject]@{path='src/unreadable.txt';identity=('1|'+('A'*64))}) -Candidate} 'PROTECTED_PATH' 'target-protection-before-absent-candidate-metadata'
    }
    Target-Reject {Read-AiwEvidenceReference $evidenceContext ([pscustomobject]@{path='.ai-workspace/project.json';identity=('1|'+('A'*64))}) -Candidate} 'CONTROL_OBJECT_DENIED' 'target-shadow-control-object-never-candidate'
    $legacyInput=$test.Input|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$legacyInput.schemaVersion=4;$legacyInput.PSObject.Properties.Remove('ruleLoad');$legacyInput.PSObject.Properties.Remove('executionTargetRef')
    $legacyResult=Run-Process $legacyInput 'target-input4-rejects-package4' -AllowFailure -UseProvidedEvidence
    Assert-True ($legacyResult.status-cne'PASS'-and$legacyResult.reason-ceq'EXECUTION_TARGET_PACKAGE_REQUIRES_INPUT5') 'target-schema4-requires-real-input5-context'
    $safe=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureVersion 'scripts/invoke-protected-safe-git.ps1'),'-ProjectRoot',$temp,'-Operation','STATUS','-AllowPath',$objectRelative,'-ExpectedProjectConfigIdentity',(Get-Identity (Join-Path $control 'project.json')),'-RepositoryId','PROJECT','-TaskPath',$taskRelative,'-ExecutionTargetRef',($targetRef|ConvertTo-Json -Compress),'-ExpectedTargetState',($state|ConvertTo-Json -Compress)) -WorkingDirectory $temp -GroupId 'w4-target-safe-git'
    Assert-True ($safe.Code-eq0) 'target-safe-git-consumes-original-control-and-real-target'
    $review=Target-Factory (Target-Binding $testFinal) 'target-initial-review'
    Target-Route $grant $testFinal $review 'target-initial-route'
    $finding=Target-Review $review 'target-real-zero-finding' 0
    Assert-True ($finding.Code-ne0) 'target-real-independent-counterexample-preserved'
    $repair=Target-Factory (Target-Binding $testFinal REPAIR 1 $finding) 'target-repair'
    $beforeRepair=[IO.File]::ReadAllBytes($objectPath)
    Write-Utf8 $objectPath 'Unexpected first repair candidate'
    $rejected=Enter-SelfStep $repair SOURCE_WRITE 'target-first-repair-drift' -AllowFailure
    Assert-True ($rejected.Result.status-cne'PASS'-and$rejected.Result.reason.Contains('OBJECT_DRIFT')) 'target-first-repair-still-requires-live-original-candidate'
    [IO.File]::WriteAllBytes($objectPath,$beforeRepair)
    $skipped=Invoke-Check $repair.Package writer-fixture TEST_RUN
    Assert-True ($skipped.Code-ne0-and$skipped.Text.Contains('CONTINUATION_ACTION_ORDER_DRIFT')) 'target-repair-cannot-skip-source-with-public-test-action'
    $repairStep=Enter-SelfStep $repair SOURCE_WRITE 'target-repair-source'
    Write-Utf8 $objectPath 'Concurrent drift before first repair ADMIT'
    $rejected=Run-Process $repairStep.Boundary 'target-first-repair-admit-drift' -AllowFailure -UseProvidedEvidence
    Assert-True ($rejected.status-cne'PASS'-and$rejected.reason.Contains('OBJECT_DRIFT')) 'target-first-repair-admit-rechecks-live-candidate'
    [IO.File]::WriteAllBytes($objectPath,$beforeRepair)
    $null=Run-Process $repairStep.Boundary 'target-first-repair-readmit' -UseProvidedEvidence
    Write-Utf8 $objectPath 'if($InputValue -eq 0){return 0};return (10 / $InputValue)'
    $repairFinal=Finish-SelfStep $repairStep 'target-repair-source-final'
    Assert-True ($repairFinal.Result.continuationReceipt.selfRepairCycle-eq1) 'target-independent-finding-does-not-reset-self-repair-budget'
    # Each negative keeps the real Source FINALIZE and changes just one bound
    # receipt fact. Rehashing the public file must not create private validation.
    foreach($case in @('actor','step','target','source','protection','cycle','postimage')){
      $bad=$repairFinal.Result.continuationReceipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
      $reason=switch($case){
        actor {$bad.actor='other-fixture';'CONTINUATION_RECEIPT_AUTHORITY_DRIFT'}
        step {$bad.completedStepIndex=1;'CONTINUATION_RECEIPT_STEP_DRIFT'}
        target {$bad.executionTargetRef.identity='1|'+('A'*64);'CONTINUATION_EXECUTION_TARGET_DRIFT'}
        source {$bad.sourceSelectionIdentity=('A'*64);'CONTINUATION_SOURCE_RECEIPT_LINK_DRIFT'}
        protection {$bad.protectedScope=@('src/extra-protection.txt');'CONTINUATION_SOURCE_RECEIPT_AUTHORITY_DRIFT'}
        cycle {$bad.selfRepairCycle=0;'SELF_REPAIR_CYCLE'}
        postimage {$bad.postObjectIdentities[0].identity=$repair.Package.objectIdentities[0].identity;'OBJECT_DRIFT'}
      }
      $badPath=Join-Path $control ('target-repair-bad-'+$case+'.json');Write-Json $badPath $bad
      $checked=Invoke-Check $repair.Package writer-fixture TEST_RUN @($objectRelative) $badPath
      Assert-True ($checked.Code-ne0-and$checked.Text.Contains($reason)) ('target-repair-successor-rejects-'+$case+'-before-historical-finding')
    }
    $afterRepair=[IO.File]::ReadAllBytes($objectPath)
    Write-Utf8 $objectPath 'Current repair leaf drift'
    $rejected=Enter-SelfStep $repair TEST_RUN 'target-repair-test-leaf-drift' $repairFinal.Continuation -AllowFailure
    Assert-True ($rejected.Result.status-cne'PASS'-and$rejected.Result.reason.Contains('OBJECT_DRIFT')) 'target-repair-successor-discovers-current-leaf-drift'
    [IO.File]::WriteAllBytes($objectPath,$afterRepair)
    $companionBytes=[IO.File]::ReadAllBytes($companionPath)
    Write-Utf8 $companionPath 'Current frozen companion drift'
    $rejected=Enter-SelfStep $repair TEST_RUN 'target-repair-test-companion-drift' $repairFinal.Continuation -AllowFailure
    Assert-True ($rejected.Result.status-cne'PASS'-and$rejected.Result.reason.Contains('EVIDENCE_IDENTITY_DRIFT')) 'target-repair-successor-discovers-current-A-minus-M-drift'
    [IO.File]::WriteAllBytes($companionPath,$companionBytes)
    $retest=Enter-SelfStep $repair TEST_RUN 'target-repair-test' $repairFinal.Continuation
    foreach($member in @('leaf','companion')){
      $path=if($member-ceq'leaf'){$objectPath}else{$companionPath}
      $bytes=[IO.File]::ReadAllBytes($path);Write-Utf8 $path 'Drift between successor DISCOVER and ADMIT'
      $rejected=Run-Process $retest.Boundary ('target-repair-test-admit-'+$member+'-drift') -AllowFailure -UseProvidedEvidence
      Assert-True ($rejected.status-cne'PASS'-and$rejected.reason.Contains('DRIFT')) ('target-repair-successor-admit-rechecks-current-'+$member)
      [IO.File]::WriteAllBytes($path,$bytes)
    }
    $stale=$retest.Input|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $stale.continuationReceiptPath=Join-Path $control 'target-repair-bad-actor.json'
    $rejected=Run-Process $stale 'target-repair-stale-public-receipt-identity' -AllowFailure -UseProvidedEvidence
    Assert-True ($rejected.status-cne'PASS'-and$rejected.reason.Contains('CONTINUATION_RECEIPT_DRIFT')) 'target-repair-public-receipt-path-does-not-validate-stale-identity'
    $null=Run-Process $retest.Boundary 'target-repair-test-readmit' -UseProvidedEvidence
    $native=Target-Command 'target-repaired-zero' 0
    Assert-True ($native.Code-eq0) 'target-native-repair-corrects-actual-counterexample'
    $currentSelf=Target-Record 'target-repaired-self' writer-fixture PASS SELF_CHECK @($objectRelative) $native
    $retested=Finish-SelfStep $retest 'target-repair-test-final' @($currentSelf)
    $rereview=Target-Factory (Target-Binding $retested REREVIEW 1 $finding) 'target-rereview'
    Target-Route $repair $retested $rereview 'target-rereview-route'
    $approved=Target-Review $rereview 'target-real-zero-approved' 0
    Assert-True ((Get-Identity $companionPath)-ceq$companionIdentity-and$approved.Code-eq0) 'target-full-A-rereview-keeps-frozen-companion'
    $accept=New-Package STANDARD TASK_OWNER owner-fixture RESULT_ACCEPT ROUTINE_LOCAL
    $accept.schemaVersion=4;$accept.repositoryId=$pkg.repositoryId;$accept.controlRoot=$temp;$accept.executionTargetRef=$targetRef;$accept.expectedTargetState=$state;$accept.exactPaths=@($objectRelative,$companion);$accept.objectIdentities=@(Target-Candidates $accept.exactPaths);$accept.invalidatesOn+=@('REPOSITORY_CHANGE')
    $ready=Target-Record 'target-owner-readiness' writer-fixture PASS SELF_CHECK $accept.exactPaths -Prerequisites @($currentSelf)
    $accept.acceptanceBinding=[ordered]@{candidateObjects=$accept.objectIdentities;requirementsRef=$selfRequirements;prerequisiteEvidenceRefs=@($ready,$approved.Typed);reservedUserDecisionRefs=@()}
    $acceptGrant=[pscustomobject]@{Path=(Join-Path $control 'target-accept.json');Package=$accept};Write-Json $acceptGrant.Path $accept
    $acceptStep=Enter-SelfStep $acceptGrant RESULT_ACCEPT 'target-owner-accept' -Scope $accept.exactPaths
    $accepted=Target-Record 'target-owner-accepted' owner-fixture ACCEPTED RESULT_ACCEPTANCE $accept.exactPaths -Grant $acceptGrant -Prerequisites @($ready,$approved.Typed)
    $acceptedFinal=Finish-SelfStep $acceptStep 'target-owner-accept-final' @($ready,$approved.Typed,$accepted)
    Assert-True ($acceptedFinal.Result.status-ceq'PASS') 'target-owner-actual-pure-acceptance-after-rereview'
    # No target change is permitted between gate and native local Git. The
    # descriptor baseline remains immutable; COMMIT observes its new post-state.
    $gitPackage=New-Package STANDARD TASK_OWNER owner-fixture GIT_STAGE ROUTINE_LOCAL
    $gitPackage.schemaVersion=4;$gitPackage.repositoryId=$pkg.repositoryId;$gitPackage.controlRoot=$temp;$gitPackage.executionTargetRef=$targetRef;$gitPackage.expectedTargetState=$state;$gitPackage.exactPaths=@($objectRelative);$gitPackage.objectIdentities=@(Target-Candidates @($objectRelative));$gitPackage.invalidatesOn+=@('REPOSITORY_CHANGE')
    $undelegated=Invoke-Check $gitPackage owner-fixture GIT_STAGE
    Assert-True ($undelegated.Code-ne0-and$undelegated.Text.Contains('TASK_OWNER_GIT_NOT_DELEGATED')) 'target-owner-git-still-requires-explicit-closer-declaration'
    $gitPackage.delegatedGitCloser=$true
    foreach($action in @('GIT_STAGE','GIT_COMMIT')){
      $gitPackage.actions=@($action)
      $gitGrant=[pscustomobject]@{Path=(Join-Path $control ($action+'-package.json'));Package=$gitPackage};Write-Json $gitGrant.Path $gitPackage
      $step=Enter-SelfStep $gitGrant $action ('target-'+$action)
      if($action-ceq'GIT_STAGE'){$null=Target-Git @('add','--',$objectRelative)}else{$null=Target-Git @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','Bounded reviewed target repair')}
      $final=Finish-SelfStep $step ('target-'+$action+'-final')
      Assert-True ($final.Result.status-ceq'PASS') ('target-native-'+$action+'-finalizes-exact-target')
      if($action-ceq'GIT_COMMIT'){Assert-True ($final.Result.postTargetState.head-cne$state.head-and$final.Result.postTargetState.branch-ceq$state.branch) 'target-commit-new-single-parent-post-state-observed'}
    }
    Invoke-FocusedBoundaries
    Write-Output ('PARTIAL|EXECUTION_TARGET_MECHANISM|native-worktree-and-commands=ACTUAL|actor-decisions-and-host=SIMULATED|qualification=NOT_RUN|fixture='+$temp)
    Write-GroupCompletion;return
  }

  # 1/2/3: one real failure, actual SOURCE repair, then success on new bytes.
  $grant=Start-SelfGrant 'bounded-repair'
  $sourceStep=Enter-SelfStep $grant SOURCE_WRITE 'bounded-source'
  $sourceFinal=Finish-SelfStep $sourceStep 'bounded-source-final'
  Assert-True ($sourceFinal.Result.continuationReceipt.schemaVersion-eq2-and$sourceFinal.Result.continuationReceipt.selfRepairCycle-eq0) 'self-repair-initial-source-carries-original-zero-cycle'
  $testStep=Enter-SelfStep $grant TEST_RUN 'bounded-failed-test' $sourceFinal.Continuation
  $failed=Observe-SelfCommand 'bounded-failure'
  $failedIdentity=$failed.identity
  $probeExpired=@(if($LifecycleOnly){$sourceStep.Boundary.discoverReceiptPath})
  $failureClosed=Finish-SelfStep $testStep 'bounded-failed-closed' @($failed) -ConsumedRuntimePath $probeExpired -KeepInputForRecovery:$LifecycleOnly -ConsumeFinalInput:$LifecycleOnly
  Assert-True ($failureClosed.Result.status-ceq'PASS'-and$failureClosed.Result.actionOutcome-ceq'FAIL'-and$failureClosed.Result.successorState-ceq'SELF_CHECK_FAILED'-and-not$failureClosed.Continuation) 'actual-failed-test-finalizes-without-review-successor'
  if($LifecycleOnly){Assert-True ($failureClosed.Result.runtimeCleanup.status-ceq'DEFERRED'-and[IO.File]::Exists($probeExpired[0])) 'lifecycle-failed-test-keeps-original-compact-before-real-recovery'}
  $failedReview=Get-SelfReview $grant $failureClosed 'bounded-failed-review' -AllowFailure
  Assert-True ($failedReview.status-ceq'REJECTED'-and$failedReview.reason.Contains('EVIDENCE_NOT_SUCCESSFUL')) 'initial-review-rejects-structural-pass-from-actual-failed-test'
  $repairFinal=Finish-SelfStep $testStep 'bounded-repair-branch' @($failed) REPAIR
  Assert-True ($repairFinal.Result.continuationReceipt.transitionKind-ceq'REPAIR'-and$repairFinal.Result.continuationReceipt.nextStepIndex-eq0-and$repairFinal.Result.continuationReceipt.selfRepairCycle-eq1) 'actual-failure-branches-to-original-write-with-one-cycle'
  $repairStep=Enter-SelfStep $grant SOURCE_WRITE 'bounded-repair-write' $repairFinal.Continuation
  Write-Utf8 $objectPath 'FIXED after actual source repair'
  $repairWriteFinal=Finish-SelfStep $repairStep 'bounded-repaired-source-final'
  $repairedTest=Enter-SelfStep $grant TEST_RUN 'bounded-repaired-test' $repairWriteFinal.Continuation
  $success=Observe-SelfCommand 'bounded-success'
  $passedFinal=Finish-SelfStep $repairedTest 'bounded-success-final' @($success) -ConsumedRuntimePath $probeExpired
  Assert-True ($passedFinal.Result.actionOutcome-ceq'PASS'-and$passedFinal.Result.continuationReceipt.nextAction-ceq'REVIEW_ROUTE'-and$passedFinal.Result.continuationReceipt.selfRepairCycle-eq1-and(Get-Identity $failed.path)-ceq$failedIdentity) 'repair-new-candidate-passes-with-frozen-old-failure-preserved'
  if($LifecycleOnly){Assert-True ($passedFinal.Result.runtimeCleanup.status-ceq'RETAINED'-and$probeExpired[0]-cin$passedFinal.Result.runtimeCleanup.retained-and[IO.File]::Exists($probeExpired[0])) 'lifecycle-success-keeps-recursive-original-compact-still-used-by-review'}
  $selfReview=Get-SelfReview $grant $passedFinal 'bounded-success-review'
  Assert-True ($null-eq$selfReview.package.PSObject.Properties['selfCheckRepairLimit']-and(Invoke-Check $selfReview.package reviewer-fixture REVIEW_EXECUTE).Code-eq0) 'successful-first-review-consumes-final-test-and-removes-parent-only-limit'
  # Same original production -> failed test -> repair -> successful test ->
  # independent protocol review -> Owner acceptance -> ordinary close/archive.
  # Decisions and host acceptance are simulated; commands/files/boundaries are real.
  $reviewGrant=[pscustomobject]@{Path=(Join-Path $control 'lifecycle-review-package.json');Package=$selfReview.package};Write-Json $reviewGrant.Path $reviewGrant.Package
  $reviewStep=Enter-SelfStep $reviewGrant REVIEW_EXECUTE 'lifecycle-review'
  $reviewBoundary=$reviewStep.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $reviewBoundary.mode='FINALIZE_OUTPUT';$reviewBoundary.resultReceipts=@($reviewStep.Result.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$objectRelative+'|'+(Get-Identity $objectPath))
  $reviewed=Run-Process $reviewBoundary 'lifecycle-reviewed'
  Assert-True ($reviewed.status-ceq'PASS'-and$reviewed.delivery.delivered) 'lifecycle-original-review-observes-simulated-host-result'
  $reviewRef=$reviewBoundary.evidenceRefs[0];$reviewRecord=Get-Content -LiteralPath $reviewRef.path -Raw|ConvertFrom-Json -Depth 100
  $acceptPackage=New-Package STANDARD TASK_OWNER owner-fixture RESULT_ACCEPT ROUTINE_LOCAL
  $acceptPackage['acceptanceBinding']=[ordered]@{candidateObjects=@($acceptPackage.objectIdentities);requirementsRef=$reviewRecord.requirementsRef;prerequisiteEvidenceRefs=@($reviewRef);reservedUserDecisionRefs=@()}
  $acceptGrant=[pscustomobject]@{Path=(Join-Path $control 'lifecycle-accept-package.json');Package=$acceptPackage};Write-Json $acceptGrant.Path $acceptPackage
  Assert-True ((Invoke-Check $acceptPackage owner-fixture RESULT_ACCEPT).Code-eq0) 'lifecycle-owner-accept-independent-checker'
  $acceptStep=Enter-SelfStep $acceptGrant RESULT_ACCEPT 'lifecycle-accept'
  $reviewLocator=[ordered]@{path=$reviewRef.path;identity=$reviewRef.identity}
  $acceptedRecord=[ordered]@{schemaVersion=1;taskId='AUTH-REGRESSION-001';actor='owner-fixture';candidateObjects=@($acceptPackage.objectIdentities);requirementsRef=$reviewRecord.requirementsRef;outcome='ACCEPTED';checks=@([ordered]@{id='reviewed-current';method='MODEL_JUDGMENT';outcome='PASS';reason='Simulated Owner judgment consumes the actual unchanged fixture candidate and protocol review.';evidenceLocators=@($reviewLocator)});evidenceLocators=@($reviewLocator);authorizationRef=[ordered]@{path=$acceptGrant.Path;identity=(Get-Identity $acceptGrant.Path)}}
  $acceptedPath=Join-Path $control 'lifecycle-accepted.json';Write-Json $acceptedPath $acceptedRecord
  $acceptedRef=[ordered]@{kind='RESULT_ACCEPTANCE';path=$acceptedPath;identity=(Get-Identity $acceptedPath)}
  $accepted=Finish-SelfStep $acceptStep 'lifecycle-accepted-final' @($acceptedRef)
  Assert-True ($accepted.Result.status-ceq'PASS') 'lifecycle-owner-original-accept-finalize'
  $recoveryReport=$null
  if($LifecycleOnly){
    Assert-True ($failureClosed.Result.status-ceq'PASS'-and$failureClosed.Result.actionOutcome-ceq'FAIL'-and$failureClosed.Result.inputCleanup.status-ceq'PARTIAL_FAILURE') 'lifecycle-actual-failed-test-finalize-preserves-original-locked-input'
    $failedInput=$failureClosed.InputPath;$failedInputIdentity=Get-Identity $failedInput
    $acceptedBoundary=Get-Content -LiteralPath $accepted.InputPath -Raw|ConvertFrom-Json -Depth 100
    $producer=Run-Process $acceptedBoundary 'lifecycle-last-consumed-input' -UseProvidedEvidence -KeepInputForRecovery -ConsumeFinalInput
    Assert-True ($producer.status-ceq'PASS'-and$producer.actionOutcome-cin@('PASS','OBSERVED')-and$producer.inputCleanup.status-ceq'PARTIAL_FAILURE'-and$producer.inputCleanup.remaining.Count-eq1) 'lifecycle-real-successful-finalize-input-still-exists-after-sharing-failure'
    $recoveryInput=$producer.inputCleanup.remaining[0];$recoveryReport=Join-Path $temp '.ai-workspace/reports/lifecycle-producer.json'
    Write-Json $recoveryReport ([ordered]@{producers=@(
      [ordered]@{mode=$producer.mode;status=$producer.status;actionOutcome=$producer.actionOutcome;inputCleanup=$producer.inputCleanup},
      [ordered]@{mode=$failureClosed.Result.mode;status=$failureClosed.Result.status;actionOutcome=$failureClosed.Result.actionOutcome;inputCleanup=$failureClosed.Result.inputCleanup})})
  }
  $taskBeforeClose=[IO.File]::ReadAllBytes($taskPath)
  $closeWatch=[Diagnostics.Stopwatch]::StartNew()
  try{
    $archiveRelative=$taskRelative.Replace('/active/','/archive/');$archivePath=Join-Path $temp $archiveRelative
    $closePackage=New-Package STANDARD TASK_OWNER owner-fixture CONTROL_WRITE ROUTINE_LOCAL
    $closePackage.exactPaths=@($taskRelative,$archiveRelative);$closePackage.objectIdentities=@([ordered]@{path=$taskRelative;identity=(Get-Identity $taskPath)},[ordered]@{path=$archiveRelative;identity='NEW'})
    $closeGrant=[pscustomobject]@{Path=(Join-Path $control 'lifecycle-close-package.json');Package=$closePackage};Write-Json $closeGrant.Path $closePackage
    Assert-True ((Invoke-Check $closePackage owner-fixture CONTROL_WRITE $closePackage.exactPaths).Code-eq0) 'lifecycle-close-archive-independent-checker'
    $closeStep=Enter-SelfStep $closeGrant CONTROL_WRITE 'lifecycle-close' -Scope $closePackage.exactPaths
    # Close from the actual completed stages, without bypassing the original gate.
    $closeCandidates=@($acceptPackage.objectIdentities)
    $closePlan=[ordered]@{schemaVersion=1;stages=@(
      [ordered]@{id='self';kind='SELF_CHECK';requiredBy=$selfRequirements;dependsOn=@();candidateRef=$closeCandidates;evidenceRefs=@($success)},
      [ordered]@{id='review';kind='RESULT_REVIEW';requiredBy=$reviewRecord.requirementsRef;dependsOn=@('self');candidateRef=$closeCandidates;evidenceRefs=@($reviewRef)},
      [ordered]@{id='accept';kind='RESULT_ACCEPT';requiredBy=$reviewRecord.requirementsRef;dependsOn=@('review');candidateRef=$closeCandidates;evidenceRefs=@($acceptedRef)})}
    if($LifecycleOnly){$closePlan.stages+=@([ordered]@{id='producer';kind='DESIGN';requiredBy=$selfRequirements;dependsOn=@();candidateRef=@([ordered]@{path=$recoveryReport;identity=(Get-Identity $recoveryReport)});evidenceRefs=@()})}
    $fence=[string]::new([char]96,3)
    $closePlanText=$fence+'aiw-acceptance-plan'+"`n"+($closePlan|ConvertTo-Json -Depth 100 -Compress)+"`n"+$fence+"`n"
    $closed=[Text.UTF8Encoding]::new($false,$true).GetString($taskBeforeClose).Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+"`n"+$closePlanText+"- Closure outcome: SUCCESS`n- Closure basis: $acceptedPath#$(Get-Identity $acceptedPath)`n- Output disposition: Real fixture candidate, command failure/success, independent protocol review and Owner acceptance retained.`n- Git disposition: EXCLUDED; isolated fixture.`n- Unresolved obligations: NONE`n- Writer: RELEASED`n- Reviewer: RELEASED`n- Authorization: RELEASED`n"
    Write-Utf8 $archivePath $closed
    $ev=@(Import-Module (Join-Path $fixtureVersion 'scripts/ResultEvidence.psm1') -PassThru)[0]
    $evContext=& $ev.ExportedCommands['New-AiwPackageEvidenceContext'] $temp $closePackage $frameworkRoot @('private/') -TaskPath $taskRelative
    & $ev.ExportedCommands['Assert-AiwTaskClosure'] $evContext $closed AUTH-REGRESSION-001 ([pscustomobject]@{publicDecisionIdentity='NOT_REQUIRED'}) -RequireExplicitClosure
    if((Get-Identity $taskPath)-cne$closePackage.taskIdentity){throw 'LIFECYCLE_ACTIVE_DRIFT'}
    [IO.File]::Delete($taskPath)
    $closeBoundary=$closeStep.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$closeBoundary.mode='FINALIZE_OUTPUT';$closeBoundary.resultReceipts=@($closeStep.Result.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@(('OBJECT_POSTIMAGE|'+$taskRelative+'|MISSING'),('OBJECT_POSTIMAGE|'+$archiveRelative+'|'+(Get-Identity $archivePath)));$closeBoundary|Add-Member deliveryContext ([pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'})
    $finished=Run-Process $closeBoundary 'lifecycle-closed-final' -UseProvidedEvidence
    $closeWatch.Stop()
    Assert-True ($finished.status-ceq'PASS'-and-not[IO.File]::Exists($taskPath)-and[IO.File]::Exists($archivePath)-and(Get-Identity $failed.path)-ceq$failedIdentity) 'lifecycle-normal-original-close-keeps-failure-history'
    if($LifecycleOnly){
      Assert-True ($finished.runtimeCleanup.status-ceq'RETAINED'-and$recoveryInput-cin$finished.runtimeCleanup.removed-and-not[IO.File]::Exists($recoveryInput)) 'lifecycle-default-production-close-collects-real-input-return-with-no-manual-expiry-array'
      Assert-True ([IO.File]::Exists($failedInput)-and(Get-Identity $failedInput)-ceq$failedInputIdentity-and$failedInput-cin$finished.runtimeCleanup.retained-and@($finished.runtimeCleanup.observations|Where-Object {$_.reason-ceq'PRODUCER_NOT_SUCCESSFUL'}).Count-ge1) 'lifecycle-success-accept-close-keeps-actual-failed-finalize-input-and-original-bytes'
      $inputFilesReleased=@($script:LifecycleInputCleanup|ForEach-Object{$_.removed}).Count
      Write-Output ('OBSERVE|lifecycle|'+([ordered]@{inputFilesReleased=$inputFilesReleased;inputBytesReleased=($script:LifecycleInputCleanup|Measure-Object -Property removedBytes -Sum).Sum;finalConsumerFilesReleased=$finished.runtimeCleanup.removed.Count;finalConsumerBytesReleased=$finished.runtimeCleanup.removedBytes;closeWallMs=$closeWatch.Elapsed.TotalMilliseconds;cleanupMs=$finished.runtimeCleanup.elapsedMs;inputCleanupMs=($script:LifecycleInputCleanup|Measure-Object -Property elapsedMs -Sum).Sum;additionalModelRequests=0;commandsAndBoundaries='ACTUAL';hostAndJudgments='SIMULATED';naturalTwoTasks='UNKNOWN'}|ConvertTo-Json -Compress))
    }
  }finally{$closeWatch.Stop();[IO.File]::WriteAllBytes($taskPath,$taskBeforeClose)}
  if($LifecycleOnly){Write-GroupCompletion;return}
  $badSuccess=Finish-SelfStep $repairedTest 'bounded-pass-cannot-repair' @($success) REPAIR -AllowFailure
  Assert-True ($badSuccess.Result.status-cne'PASS') 'self-repair-cannot-branch-from-pass'

  # 4: history counter/link tampering and current-leaf drift are different facts.
  foreach($cycle in @(0,2)){
    $bad=$repairWriteFinal.Result.continuationReceipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.selfRepairCycle=$cycle
    $badPath=Join-Path $control ('bad-cycle-'+$cycle+'.json');Write-Json $badPath $bad
    $checked=Enter-SelfStep $grant TEST_RUN ('bad-cycle-'+$cycle) $badPath -AllowFailure
    Assert-True ($checked.Result.status-cne'PASS'-and$checked.Result.reason.Contains('SELF_REPAIR_CYCLE')) ('self-repair-rejects-counter-'+$cycle)
  }
  $bad=$repairWriteFinal.Result.continuationReceipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $bad.sourceDiscoverReceiptIdentity='1|'+('0'*64);$badPath=Join-Path $control 'bad-source-link.json';Write-Json $badPath $bad
  Assert-True ((Enter-SelfStep $grant TEST_RUN 'bad-source-link' $badPath -AllowFailure).Result.status-cne'PASS') 'self-repair-rejects-missing-or-stale-source-link'
  $bad=$repairWriteFinal.Result.continuationReceipt|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $bad.protectedScope=@('src/item.txt');$badPath=Join-Path $control 'bad-protection.json';Write-Json $badPath $bad
  Assert-True ((Enter-SelfStep $grant TEST_RUN 'bad-protection' $badPath -AllowFailure).Result.status-cne'PASS') 'self-repair-rejects-protection-chain-drift'
  Write-Utf8 $objectPath 'unaccounted live drift'
  Assert-True ((Enter-SelfStep $grant TEST_RUN 'bad-live-leaf' $repairWriteFinal.Continuation -AllowFailure).Result.status-cne'PASS') 'self-repair-rejects-current-leaf-postimage-drift'

  # 5/6: actual transient RETEST consumes budget without an empty SOURCE step.
  $retestGrant=Start-SelfGrant 'bounded-retest' 1 -TestWrite
  $retestSource=Enter-SelfStep $retestGrant TEST_WRITE 'retest-source'
  $retestSourceFinal=Finish-SelfStep $retestSource 'retest-source-final'
  $retestStep=Enter-SelfStep $retestGrant TEST_RUN 'retest-first' $retestSourceFinal.Continuation
  $marker=Join-Path $control 'transient-marker.txt';$transient=Observe-SelfCommand 'transient-first' $marker
  $retestBranch=Finish-SelfStep $retestStep 'retest-branch' @($transient) RETEST
  $retestAgain=Enter-SelfStep $retestGrant TEST_RUN 'retest-again' $retestBranch.Continuation
  $recovered=Observe-SelfCommand 'transient-second' $marker
  $retestPass=Finish-SelfStep $retestAgain 'retest-pass' @($recovered)
  Assert-True ($retestBranch.Result.continuationReceipt.nextStepIndex-eq1-and$retestPass.Result.actionOutcome-ceq'PASS'-and$retestPass.Result.continuationReceipt.selfRepairCycle-eq1) 'actual-transient-retest-passes-same-candidate-with-no-empty-write'
  $stillFailed=Observe-SelfCommand 'exhausted-actual-failure'
  $exhausted=Finish-SelfStep $retestAgain 'retest-exhausted' @($stillFailed) RETEST
  Assert-True ($exhausted.Result.status-ceq'PASS'-and$exhausted.Result.successorState-ceq'REPAIR_LIMIT_EXHAUSTED'-and-not$exhausted.Continuation) 'exhausted-original-budget-finalizes-failure-with-zero-successor'
  $mixed=Finish-SelfStep $retestAgain 'mixed-pass-fail' @($recovered,$stillFailed)
  Assert-True ($mixed.Result.actionOutcome-ceq'FAIL'-and-not$mixed.Continuation) 'current-self-check-set-cannot-cherry-pick-pass'
  $stopped=Finish-SelfStep $retestAgain 'explicit-stop' @($stillFailed) STOP
  Assert-True ($stopped.Result.successorState-ceq'STOPPED'-and-not$stopped.Continuation-and$stopped.Result.decisionIdentity-cne$exhausted.Result.decisionIdentity) 'stop-is-decision-bound-and-grants-zero-successor'

  # 7: interrupt a real process after start; no completed exit observation exists.
  $interruptedScript=Join-Path $control 'interrupted.ps1';$startedPath=Join-Path $control 'interrupted-started.txt'
  Write-Utf8 $interruptedScript ("[IO.File]::WriteAllText('"+$startedPath+"','actual start');Start-Sleep -Seconds 30")
  $pi=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source);$pi.UseShellExecute=$false;$pi.CreateNoWindow=$true
  foreach($a in @('-NoProfile','-NonInteractive','-File',$interruptedScript)){$pi.ArgumentList.Add($a)}
  $p=[Diagnostics.Process]::Start($pi)
  try{$deadline=[DateTime]::UtcNow.AddSeconds(10);while(-not(Test-Path -LiteralPath $startedPath)-and[DateTime]::UtcNow-lt$deadline){Start-Sleep -Milliseconds 20};if(-not(Test-Path -LiteralPath $startedPath)){throw 'INTERRUPTION_START_UNOBSERVED'};$p.Kill();$p.WaitForExit()}finally{if(-not$p.HasExited){$p.Kill()};$p.Dispose()}
  $interrupted=Get-Content $recovered.path -Raw|ConvertFrom-Json -Depth 100;$interrupted.outcome='INCOMPLETE'
  $interrupted.checks=@($interrupted.checks)+@([ordered]@{id='actual-interruption';method='MODEL_JUDGMENT';outcome='INCOMPLETE';reason='Observed process start then termination without a completed command result. No exitCode is fabricated.';evidenceLocators=@([ordered]@{path=$startedPath;identity=Get-Identity $startedPath})})
  $interruptedPath=Join-Path $control 'interrupted-self.json';Write-Json $interruptedPath $interrupted
  $incompleteRef=[ordered]@{kind='SELF_CHECK';path=$interruptedPath;identity=Get-Identity $interruptedPath}
  $incomplete=Finish-SelfStep $retestAgain 'incomplete-final' @($recovered,$incompleteRef)
  Assert-True ($incomplete.Result.status-ceq'PASS'-and$incomplete.Result.actionOutcome-ceq'INCOMPLETE'-and-not$incomplete.Continuation) 'actual-interruption-finalizes-incomplete-without-fake-exit-or-successor'
  Assert-True ((Finish-SelfStep $retestAgain 'incomplete-no-repair' @($incompleteRef) REPAIR -AllowFailure).Result.status-cne'PASS') 'incomplete-cannot-authorize-nonlinear-repair'

  # 8/9: ungranted branch, malformed grant, and the genuine old linear repair.
  $legacy=Start-SelfGrant 'legacy-linear' -NoPolicy -Linear
  $legacySource=Enter-SelfStep $legacy SOURCE_WRITE 'legacy-source'
  $legacySourceFinal=Finish-SelfStep $legacySource 'legacy-source-final'
  $legacyTest=Enter-SelfStep $legacy TEST_RUN 'legacy-test' $legacySourceFinal.Continuation
  $legacyFail=Observe-SelfCommand 'legacy-actual-failure'
  $ungranted=Finish-SelfStep $legacyTest 'legacy-no-permission' @($legacyFail) REPAIR
  Assert-True ($ungranted.Result.status-ceq'PASS'-and$ungranted.Result.successorState-ceq'NO_REPAIR_PERMISSION'-and-not$ungranted.Continuation) 'no-original-policy-finalizes-failure-without-nonlinear-authority'
  $legacyFinal=Finish-SelfStep $legacyTest 'legacy-linear-final' @($legacyFail)
  $legacyRepair=Enter-SelfStep $legacy SOURCE_WRITE 'legacy-real-planned-write' $legacyFinal.Continuation
  Assert-True ($legacyFinal.Result.continuationReceipt.schemaVersion-eq1-and$legacyFinal.Result.continuationReceipt.nextStepIndex-eq2-and$legacyRepair.Result.status-ceq'PASS') 'old-real-source-test-source-failure-continues-linearly'
  $malformed=$legacy.Package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$malformed|Add-Member selfCheckRepairLimit 1
  $malformedCheck=Invoke-Check $malformed writer-fixture SOURCE_WRITE
  Assert-True ($malformedCheck.Code-ne0-and$malformedCheck.Text.Contains('SELF_REPAIR_PLAN_SHAPE')) 'self-repair-policy-rejects-prefilled-linear-rounds'
  $malformed=$retestGrant.Package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$malformed.selfCheckRepairLimit=0
  $malformedCheck=Invoke-Check $malformed writer-fixture TEST_WRITE
  Assert-True ($malformedCheck.Code-ne0-and$malformedCheck.Text.Contains('SELF_REPAIR_LIMIT')) 'self-repair-policy-rejects-nonpositive-limit'
  $fake=Get-Content $legacyFail.path -Raw|ConvertFrom-Json -Depth 100;$fake.outcome='PASS';$fake.checks[0].outcome='PASS'
  $fakePath=Join-Path $control 'fake-success.json';Write-Json $fakePath $fake
  $fakeRef=[ordered]@{kind='SELF_CHECK';path=$fakePath;identity=Get-Identity $fakePath}
  $fakeFinal=Finish-SelfStep $legacyTest 'fake-command-success' @($fakeRef) -AllowFailure
  Assert-True ($fakeFinal.Result.status-cne'PASS'-and$fakeFinal.Result.reason.Contains('EVIDENCE_COMMAND_FAILURE')) 'failed-actual-command-cannot-be-relabeled-success'
  $invalidBoundary=$legacyTest.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$invalidBoundary|Add-Member continuationDisposition STOP
  Assert-True ((Run-Process $invalidBoundary 'admit-no-disposition' -AllowFailure -UseProvidedEvidence).status-cne'PASS') 'continuation-disposition-rejected-at-admit-boundary'

  # Limited production M and a preapproved whole review A use the real checker,
  # resolver, continuation and package factory. Host sends remain explicit
  # protocol fixtures; the actual command below tests only the isolated M.
  $wholeGrant=Start-SelfGrant 'whole-scope'
  $untouchedRelative='src/untouched.txt';$untouchedPath=Join-Path $temp $untouchedRelative
  $retiredRelative='src/retired.txt';$retiredPath=Join-Path $temp $retiredRelative
  Write-Utf8 $untouchedPath 'Frozen untouched review member'
  $wholePaths=@($objectRelative,$untouchedRelative,$retiredRelative)
  $wholeGrant.Package.repairReviewPlan['reviewScope']=@($wholeGrant.Package.objectIdentities)+@([ordered]@{path=$untouchedRelative;identity=Get-Identity $untouchedPath},[ordered]@{path=$retiredRelative;identity='NEW'})
  Write-Json $wholeGrant.Path $wholeGrant.Package
  Assert-True ((Invoke-Check $wholeGrant.Package writer-fixture SOURCE_WRITE).Code-eq0) 'whole-review-plan-admits-only-original-finite-write'
  Assert-True ((Invoke-Check $wholeGrant.Package writer-fixture SOURCE_WRITE $wholePaths).Code-ne0) 'whole-readonly-review-cannot-expand-source-write'
  foreach($case in @('duplicate','missing-write','wrong-write-identity','no-route','invalid-path')){
    $bad=$wholeGrant.Package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    switch($case){
      duplicate {$bad.repairReviewPlan.reviewScope+=@($bad.repairReviewPlan.reviewScope[0])}
      missing-write {$bad.repairReviewPlan.reviewScope=@($bad.repairReviewPlan.reviewScope|Where-Object{$_.path-cne$objectRelative})}
      wrong-write-identity {$bad.repairReviewPlan.reviewScope[0].identity='1|'+('A'*64)}
      no-route {$bad.actions=@('SOURCE_WRITE','TEST_RUN');$bad.continuationPlan=@('SOURCE_WRITE','TEST_RUN')}
      invalid-path {$bad.repairReviewPlan.reviewScope[1].path='../untouched.txt'}
    }
    Assert-True ((Invoke-Check $bad writer-fixture SOURCE_WRITE).Text.Contains('REVIEW_SCOPE')) ('whole-plan-rejects-'+$case)
  }
  $wholeSource=Enter-SelfStep $wholeGrant SOURCE_WRITE 'whole-source'
  $wholeSourceFinal=Finish-SelfStep $wholeSource 'whole-source-final'
  $wholeTest=Enter-SelfStep $wholeGrant TEST_RUN 'whole-first-test' $wholeSourceFinal.Continuation
  $wholeFailure=Observe-SelfCommand 'whole-actual-failure'
  $wholeFailedFinal=Finish-SelfStep $wholeTest 'whole-failed-final' @($wholeFailure)
  Assert-True (-not$wholeFailedFinal.Continuation-and$wholeFailedFinal.Result.actionOutcome-ceq'FAIL') 'whole-review-not-created-from-real-failed-test'
  $wholeRepairFinal=Finish-SelfStep $wholeTest 'whole-self-repair' @($wholeFailure) REPAIR
  Assert-True ((@($wholeRepairFinal.Result.continuationReceipt.exactPaths)-join'|')-ceq$objectRelative) 'whole-self-repair-keeps-M-write-scope'
  $wholeRepair=Enter-SelfStep $wholeGrant SOURCE_WRITE 'whole-repair-write' $wholeRepairFinal.Continuation
  Write-Utf8 $objectPath 'FIXED finite production with larger frozen review'
  $wholeWriteFinal=Finish-SelfStep $wholeRepair 'whole-repaired-final'
  $wholePassedTest=Enter-SelfStep $wholeGrant TEST_RUN 'whole-current-test' $wholeWriteFinal.Continuation
  $wholeSuccess=Observe-SelfCommand 'whole-actual-success'
  $untouchedBytes=[IO.File]::ReadAllBytes($untouchedPath)
  Write-Utf8 $untouchedPath 'Third-party drift'
  $driftFinal=Finish-SelfStep $wholePassedTest 'whole-untouched-drift-final' @($wholeSuccess) -AllowFailure
  Assert-True ($driftFinal.Result.status-cne'PASS') 'whole-continuation-rejects-untouched-drift'
  [IO.File]::WriteAllBytes($untouchedPath,$untouchedBytes)
  Write-Utf8 $retiredPath 'Retired member reappeared'
  $retiredFinal=Finish-SelfStep $wholePassedTest 'whole-retired-reappeared-final' @($wholeSuccess) -AllowFailure
  Assert-True ($retiredFinal.Result.status-cne'PASS') 'whole-continuation-rejects-retired-reappearance'
  Remove-Item -LiteralPath $retiredPath -Force
  $wholeFinal=Finish-SelfStep $wholePassedTest 'whole-success-final' @($wholeSuccess)
  Assert-True ($wholeFinal.Result.actionOutcome-ceq'PASS'-and$wholeFinal.Result.continuationReceipt.exactPaths.Count-eq3-and$wholeFinal.Result.continuationReceipt.completedAction-ceq'TEST_RUN'-and$wholeFinal.Result.continuationReceipt.selfRepairCycle-eq1) 'whole-current-success-composes-A-after-real-M-test-with-history'
  Assert-True ((Invoke-Check $wholeGrant.Package writer-fixture TEST_RUN $wholePaths $wholeWriteFinal.Continuation).Code-ne0) 'whole-review-scope-cannot-expand-test-action'
  Assert-True ((Invoke-Check $wholeGrant.Package writer-fixture SOURCE_WRITE $wholePaths $wholeFinal.Continuation).Code-ne0) 'whole-final-review-receipt-cannot-loop-back-to-A-write'
  $wholeReview=Get-SelfReview $wholeGrant $wholeFinal 'whole-first-review'
  Assert-True ($wholeReview.package.exactPaths.Count-eq3-and(Invoke-Check $wholeReview.package reviewer-fixture REVIEW_EXECUTE $wholePaths).Code-eq0) 'whole-pure-review-consumes-actual-M-finalize-and-frozen-A'
  $wholeCandidates=@($wholeReview.package.objectIdentities|ForEach-Object{[ordered]@{path=$_.path;identity=$(if($_.identity-ceq'NEW'){'MISSING'}else{$_.identity})}})
  $wholeSelfPath=Join-Path $control 'whole-readiness-self.json'
  Write-Json $wholeSelfPath ([ordered]@{schemaVersion=1;taskId='AUTH-REGRESSION-001';actor='writer-fixture';candidateObjects=$wholeCandidates;requirementsRef=$selfRequirements;outcome='PASS';checks=@([ordered]@{id='whole-current-readiness';method='MODEL_JUDGMENT';outcome='PASS';reason='Actual finite command evidence plus verified unchanged and missing members; this is whole candidate readiness, not additional software test coverage.';evidenceLocators=@([ordered]@{path=$wholeSuccess.path;identity=$wholeSuccess.identity},[ordered]@{path=$wholeFinal.InputPath;identity=Get-Identity $wholeFinal.InputPath},[ordered]@{path=$untouchedPath;identity=Get-Identity $untouchedPath})});evidenceLocators=@($selfRequirements)})
  $wholeSelf=[ordered]@{kind='SELF_CHECK';path=$wholeSelfPath;identity=Get-Identity $wholeSelfPath}
  $wholeRoute=Enter-SelfStep $wholeGrant REVIEW_ROUTE 'whole-review-route' $wholeFinal.Continuation -Scope $wholePaths -Evidence @($wholeSelf)
  Assert-True ($wholeRoute.Result.compactReceipt.binding.exactScope.Count-eq3) 'whole-review-route-checker-discover-admit-bind-A'
  $badBoundary=$wholeRoute.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badBoundary.evidenceRefs=@($wholeSuccess)
  Assert-True ((Run-Process $badBoundary 'whole-M-self-not-A-readiness' -AllowFailure -UseProvidedEvidence).status-cne'PASS') 'whole-route-rejects-M-only-self-as-whole-readiness'
  $wholeRouteFinal=Finish-SelfStep $wholeRoute 'whole-review-route-final' @($wholeSelf)
  Assert-True ($wholeRouteFinal.Result.status-ceq'PASS'-and$wholeRouteFinal.Result.consumer.recipient-ceq'reviewer-fixture') 'whole-route-actual-protocol-observation-direct-to-original-reviewer'
  $reviewGrant=[pscustomobject]@{Path=(Join-Path $control 'whole-review-package.json');Package=$wholeReview.package};Write-Json $reviewGrant.Path $reviewGrant.Package
  $reviewStep=Enter-SelfStep $reviewGrant REVIEW_EXECUTE 'whole-independent-review' -Scope $wholePaths
  $reviewBoundary=$reviewStep.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$reviewBoundary.mode='FINALIZE_OUTPUT'
  $reviewBoundary.resultReceipts=@($reviewStep.Result.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@($wholeCandidates|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.identity})
  $actualFinding=Run-Process $reviewBoundary 'whole-independent-finding' -ReviewOutcome CHANGES_REQUESTED -FindingPaths @($objectRelative)
  Assert-True ($actualFinding.status-ceq'PASS'-and$actualFinding.consumer.recipient-ceq'writer-fixture') 'whole-independent-protocol-finding-returns-to-original-writer'
  $actualFinding=$script:FixtureReviewFinalizes['whole-independent-finding']
  $repairBinding=[ordered]@{parentPackagePath=$wholeGrant.Path;parentPackageIdentity=Get-Identity $wholeGrant.Path;phase='REPAIR';cycle=1;verdictPath=$actualFinding.verdictPath;verdictIdentity=$actualFinding.verdictIdentity;repairFinalizeInputPath='NOT_APPLICABLE';repairFinalizeInputIdentity='NOT_APPLICABLE';repairFinalizeResultPath='NOT_APPLICABLE';repairFinalizeResultIdentity='NOT_APPLICABLE';verdictFinalizeInputPath=$actualFinding.verdictFinalizeInputPath;verdictFinalizeInputIdentity=$actualFinding.verdictFinalizeInputIdentity;verdictFinalizeResultPath=$actualFinding.verdictFinalizeResultPath;verdictFinalizeResultIdentity=$actualFinding.verdictFinalizeResultIdentity}
  function Whole-Factory($Binding,[string]$Name,[switch]$AllowFailure){
    $p=Join-Path $control ($Name+'-factory.json');Write-Json $p ([ordered]@{operation='REPAIR_REVIEW';repositoryRoot=$temp;binding=$Binding})
    $out=@(Invoke-AuthNative -NoProfile -File (Join-Path $fixtureVersion 'scripts/resolve-workflow-route.ps1') -InputPath $p -AsJson 2>&1|ForEach-Object{[string]$_})
    if($LASTEXITCODE-ne0){if($AllowFailure){return [pscustomobject]@{status='REJECTED';reason=($out-join"`n")}};throw ($out-join"`n")}
    return ($out-join"`n")|ConvertFrom-Json -Depth 100
  }
  $null=Run-Process $reviewBoundary 'whole-outside-M-review-finding' -ReviewOutcome CHANGES_REQUESTED -FindingPaths @($untouchedRelative)
  $outsideFinding=$script:FixtureReviewFinalizes['whole-outside-M-review-finding']
  $outsideBinding=$repairBinding|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  foreach($name in @('verdictPath','verdictIdentity','verdictFinalizeInputPath','verdictFinalizeInputIdentity','verdictFinalizeResultPath','verdictFinalizeResultIdentity')){$outsideBinding.$name=$outsideFinding.$name}
  $outsideRepair=Whole-Factory $outsideBinding 'whole-outside-M-finding' -AllowFailure
  Assert-True ($outsideRepair.status-ceq'REJECTED'-and$outsideRepair.reason.Contains('OUTSIDE_WRITE_SCOPE')) 'whole-finding-outside-M-returns-owner-without-write-expansion'
  $finiteRepair=Whole-Factory $repairBinding 'whole-finding-repair'
  Assert-True ($finiteRepair.package.exactPaths.Count-eq1-and(Invoke-Check $finiteRepair.package writer-fixture SOURCE_WRITE).Code-eq0) 'whole-finding-A-produces-only-original-M-repair'
  $finiteGrant=[pscustomobject]@{Path=(Join-Path $control 'whole-finite-repair-package.json');Package=$finiteRepair.package};Write-Json $finiteGrant.Path $finiteGrant.Package
  $finiteStep=Enter-SelfStep $finiteGrant SOURCE_WRITE 'whole-finding-repair-step'
  Write-Utf8 $objectPath 'FIXED independent finding within M'
  $finiteFinal=Finish-SelfStep $finiteStep 'whole-finding-repair-final'
  $repairBinding.phase='REREVIEW';$repairBinding.repairFinalizeInputPath=$finiteFinal.InputPath;$repairBinding.repairFinalizeInputIdentity=Get-Identity $finiteFinal.InputPath;$repairBinding.repairFinalizeResultPath=$finiteFinal.ResultPath;$repairBinding.repairFinalizeResultIdentity=Get-Identity $finiteFinal.ResultPath
  $rereview=Whole-Factory $repairBinding 'whole-rereview'
  Assert-True ($rereview.package.exactPaths.Count-eq3-and(Invoke-Check $rereview.package reviewer-fixture REVIEW_EXECUTE $wholePaths).Code-eq0) 'whole-rereview-preserves-A-original-reviewer-and-cycle'
  $badRereview=$rereview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badRereview.repairReviewBinding.cycle=3
  Assert-True ((Invoke-Check $badRereview reviewer-fixture REVIEW_EXECUTE $wholePaths).Code-ne0) 'whole-review-cannot-reset-or-exceed-original-cycle-limit'
  $currentM=[IO.File]::ReadAllBytes($objectPath);Write-Utf8 $untouchedPath 'Frozen member changed after whole review'
  Assert-True ((Invoke-Check $rereview.package reviewer-fixture REVIEW_EXECUTE $wholePaths).Code-ne0) 'whole-rereview-rejects-untouched-current-drift'
  [IO.File]::WriteAllBytes($untouchedPath,$untouchedBytes)
  $fakeFinalBytes=[IO.File]::ReadAllBytes($finiteFinal.ResultPath);$fakeFinal=Get-Content -LiteralPath $finiteFinal.ResultPath -Raw|ConvertFrom-Json -Depth 100
  # Preserve the valid identity shape while guaranteeing a different value,
  # so the real checker reaches the decision comparison after format checks.
  $first=if($fakeFinal.decisionIdentity[0]-ceq'A'){'B'}else{'A'}
  $fakeFinal.decisionIdentity=$first+$fakeFinal.decisionIdentity.Substring(1);Write-Json $finiteFinal.ResultPath $fakeFinal
  $badRereview=$rereview.package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badRereview.repairReviewBinding.repairFinalizeResultIdentity=Get-Identity $finiteFinal.ResultPath
  $decisionDriftCheck=Invoke-Check $badRereview reviewer-fixture REVIEW_EXECUTE $wholePaths
  $decisionObservation=Join-Path $control 'whole-forged-decision-check.json'
  $packageSnapshot=Join-Path $control 'whole-forged-decision-actual-package.json'
  $finalSnapshot=Join-Path $control 'whole-forged-decision-actual-finalize-result.json'
  [IO.File]::Copy($packagePath,$packageSnapshot,$false)
  [IO.File]::Copy($finiteFinal.ResultPath,$finalSnapshot,$false)
  Write-Json $decisionObservation ([ordered]@{exitCode=$decisionDriftCheck.Code;rawCheckerOutput=$decisionDriftCheck.Text;expectedReason='REPAIR_REVIEW_FINALIZE_DECISION_DRIFT';scope=$wholePaths;packageRef=[ordered]@{path=$packageSnapshot;identity=Get-Identity $packageSnapshot};forgedFinalizeResultRef=[ordered]@{path=$finalSnapshot;identity=Get-Identity $finalSnapshot};actualForgedDecisionIdentity=$fakeFinal.decisionIdentity;qualification='Raw call inputs copied at observation; embedded references describe that moment and may subsequently be restored by the fixture.'})
  Write-Output ('CHECKER_OBSERVATION|whole-forged-decision|exit='+$decisionDriftCheck.Code+'|'+$decisionDriftCheck.Text)
  if($decisionDriftCheck.Code-eq0-or-not$decisionDriftCheck.Text.Contains('REPAIR_REVIEW_FINALIZE_DECISION_DRIFT')){Write-Output ('DIAGNOSTIC|'+$decisionObservation+'|'+(Get-Identity $decisionObservation))}
  Assert-True ($decisionDriftCheck.Code-ne0-and$decisionDriftCheck.Text.Contains('REPAIR_REVIEW_FINALIZE_DECISION_DRIFT')) 'whole-live-hashes-cannot-replace-real-finalize-decision'
  [IO.File]::WriteAllBytes($finiteFinal.ResultPath,$fakeFinalBytes)

  # A linear grant has no self-repair-chain reader to incidentally check A.
  # Exercise its actual finding -> repair Source FINALIZE -> TEST boundary so
  # dropping the current whole-candidate check is independently detectable.
  $linearWhole=Start-SelfGrant 'linear-whole-history' -NoPolicy
  $linearWhole.Package.repairReviewPlan['reviewScope']=@($linearWhole.Package.objectIdentities)+@([ordered]@{path=$untouchedRelative;identity=Get-Identity $untouchedPath},[ordered]@{path=$retiredRelative;identity='NEW'})
  Write-Json $linearWhole.Path $linearWhole.Package
  $linearSource=Enter-SelfStep $linearWhole SOURCE_WRITE 'linear-whole-source'
  Write-Utf8 $objectPath 'FIXED linear candidate before independent finding'
  $linearSourceFinal=Finish-SelfStep $linearSource 'linear-whole-source-final'
  $linearTest=Enter-SelfStep $linearWhole TEST_RUN 'linear-whole-test' $linearSourceFinal.Continuation
  $linearSelf=Observe-SelfCommand 'linear-whole-actual-command'
  $linearFinal=Finish-SelfStep $linearTest 'linear-whole-test-final' @($linearSelf)
  $linearReview=Get-SelfReview $linearWhole $linearFinal 'linear-whole-review'
  $linearReviewGrant=[pscustomobject]@{Path=(Join-Path $control 'linear-whole-review-package.json');Package=$linearReview.package};Write-Json $linearReviewGrant.Path $linearReviewGrant.Package
  $linearReviewStep=Enter-SelfStep $linearReviewGrant REVIEW_EXECUTE 'linear-whole-independent-review' -Scope $wholePaths
  $linearBoundary=$linearReviewStep.Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $linearBoundary.mode='FINALIZE_OUTPUT';$linearBoundary.resultReceipts=@($linearReviewStep.Result.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@($linearReview.package.objectIdentities|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$(if($_.identity-ceq'NEW'){'MISSING'}else{$_.identity})})
  $null=Run-Process $linearBoundary 'linear-whole-finding' -ReviewOutcome CHANGES_REQUESTED -FindingPaths @($objectRelative)
  $linearFinding=$script:FixtureReviewFinalizes['linear-whole-finding']
  $linearBinding=$repairBinding|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $linearBinding.parentPackagePath=$linearWhole.Path;$linearBinding.parentPackageIdentity=Get-Identity $linearWhole.Path;$linearBinding.phase='REPAIR'
  foreach($name in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){$linearBinding.$name='NOT_APPLICABLE'}
  foreach($name in @('verdictPath','verdictIdentity','verdictFinalizeInputPath','verdictFinalizeInputIdentity','verdictFinalizeResultPath','verdictFinalizeResultIdentity')){$linearBinding.$name=$linearFinding.$name}
  $linearRepair=Whole-Factory $linearBinding 'linear-whole-repair'
  $linearRepairGrant=[pscustomobject]@{Path=(Join-Path $control 'linear-whole-repair-package.json');Package=$linearRepair.package};Write-Json $linearRepairGrant.Path $linearRepairGrant.Package
  $linearRepairStep=Enter-SelfStep $linearRepairGrant SOURCE_WRITE 'linear-whole-repair-source'
  Write-Utf8 $objectPath 'FIXED linear independent repair current postimage'
  $linearRepairFinal=Finish-SelfStep $linearRepairStep 'linear-whole-repair-source-final'
  Assert-True ($linearRepairFinal.Result.continuationReceipt.schemaVersion-eq1-and$null-eq$linearRepairGrant.Package.PSObject.Properties['selfCheckRepairLimit']) 'linear-repair-successor-has-no-self-chain-reader'
  foreach($member in @('untouched','retired')){
    $path=if($member-ceq'untouched'){$untouchedPath}else{$retiredPath}
    Write-Utf8 $path 'Unauthorized current whole-review member'
    $checked=Invoke-Check $linearRepairGrant.Package writer-fixture TEST_RUN @($objectRelative) $linearRepairFinal.Continuation
    Assert-True ($checked.Code-ne0-and$checked.Text.Contains('EVIDENCE_IDENTITY_DRIFT')) ('linear-repair-test-live-A-rejects-'+$member)
    if($member-ceq'untouched'){[IO.File]::WriteAllBytes($path,$untouchedBytes)}else{Remove-Item -LiteralPath $path -Force}
  }
  $linearRetest=Enter-SelfStep $linearRepairGrant TEST_RUN 'linear-whole-repair-test' $linearRepairFinal.Continuation
  Write-Utf8 $retiredPath 'Retired member reappears after DISCOVER'
  $rejected=Run-Process $linearRetest.Boundary 'linear-whole-repair-admit-retired' -AllowFailure -UseProvidedEvidence
  Assert-True ($rejected.status-cne'PASS'-and$rejected.reason.Contains('EVIDENCE_IDENTITY_DRIFT')) 'linear-repair-admit-rechecks-retired-A-member'
  Remove-Item -LiteralPath $retiredPath -Force
  $null=Run-Process $linearRetest.Boundary 'linear-whole-repair-readmit' -UseProvidedEvidence
  $linearRepairedSelf=Observe-SelfCommand 'linear-whole-repaired-actual-command'
  $linearRetested=Finish-SelfStep $linearRetest 'linear-whole-repair-test-final' @($linearRepairedSelf)
  Assert-True ($linearRetested.Result.status-ceq'PASS'-and$linearRetested.Result.continuationReceipt.schemaVersion-eq1) 'linear-repair-test-accepts-real-current-M-and-historical-finding'
  [IO.File]::WriteAllBytes($objectPath,$selfOriginalObject)

  $targetArguments=@('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Group','ExecutionTarget')
  if($KeepFixture){$targetArguments+='-KeepFixture'}
  $targetRun=Invoke-AiwTestProcess ([Environment]::ProcessPath) $targetArguments -GroupId 'authorization-actual-execution-target-chain'
  foreach($line in $targetRun.Output){if($line-cnotmatch'^RESULT\|'){Write-Output $line}}
  $targetCompletion=@($targetRun.Output|Where-Object{$_-cmatch'^RESULT\|\d+ passed\|scope=authorization-receipt-regression\|group=ExecutionTarget$'})
  $targetChecks=@($targetRun.Output|Where-Object{$_-cmatch'^PASS\|'}).Count
  Assert-True ($targetRun.Code-eq0-and$targetCompletion.Count-eq1-and$targetCompletion[0]-ceq('RESULT|'+$targetChecks+' passed|scope=authorization-receipt-regression|group=ExecutionTarget')) 'continuation-normal-group-completes-actual-target-repair-rereview-chain'
  $script:passed+=$targetChecks

  }
  if($Group-ceq'DeliveryAcceptance'){
  # A domain owner may push one accepted commit to one exact target after a
  # task-scoped user decision. Keep the remote local; this fixture never pushes
  # the second commit.
  & git -C $temp config user.email fixture@example.invalid
  & git -C $temp config user.name 'Fixture Owner'
  & git -C $temp checkout -q -b main
  & git -C $temp add -- $objectRelative
  & git -C $temp commit -qm base
  $remote=Join-Path $temp 'remote.git';& git init -q --bare $remote
  & git -C $temp remote add origin $remote
  & git -C $temp push -q origin main
  $remoteCommit=([string](& git -C $temp rev-parse HEAD)).ToUpperInvariant()
  Write-Utf8 $objectPath 'Accepted second commit'
  & git -C $temp add -- $objectRelative
  & git -C $temp commit -qm accepted
  $localCommit=([string](& git -C $temp rev-parse HEAD)).ToUpperInvariant()
  Write-Task STANDARD GIT
  $decision='USER_FIXTURE_APPROVED_EXACT_PUSH'
  Write-Utf8 $taskPath ((Get-Content -Raw -LiteralPath $taskPath).TrimEnd("`n")+"`nPush authorization: repositoryId=CONTROL; remote=origin; branch=main; decision=$decision`n")
  $evidenceRelative='.ai-workspace/reports/push-acceptance.json';$evidencePath=Join-Path $temp $evidenceRelative
  $pushRequirementsPath=Join-Path $control 'reports/push-requirements.md';Write-Utf8 $pushRequirementsPath 'Accept exactly the observed local fixture commit and src/item.txt candidate; no external remote is contacted.'
  $pushRequirements=[ordered]@{path=$pushRequirementsPath;identity=Get-Identity $pushRequirementsPath}
  $pushAccept=New-Package STANDARD TASK_OWNER owner-fixture RESULT_ACCEPT PRODUCT_RESULT;$pushAccept.userConfirmation='USER_FIXTURE_ACCEPTED'
  $pushAcceptPath=Join-Path $control 'reports/push-accept-package.json';Write-Json $pushAcceptPath $pushAccept
  Write-Json $evidencePath ([ordered]@{schemaVersion=1;taskId=$pushAccept.taskId;actor='owner-fixture';candidateObjects=$pushAccept.objectIdentities;requirementsRef=$pushRequirements;outcome='ACCEPTED';checks=@([ordered]@{id='exact-commit';method='MODEL_JUDGMENT';outcome='PASS';reason='Fixture acceptance of the actual local candidate and observed commit.';evidenceLocators=@($pushRequirements)});evidenceLocators=@($pushRequirements);authorizationRef=[ordered]@{path=$pushAcceptPath;identity=Get-Identity $pushAcceptPath};acceptedCommit=$localCommit})
  $remoteUrl=[string](& git -C $temp remote get-url --push origin);$remoteUrlBytes=$utf8.GetBytes($remoteUrl)
  $remoteUrlIdentity=$remoteUrlBytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($remoteUrlBytes))
  $push=New-Package STANDARD TASK_OWNER owner-fixture PUSH EXTERNAL_ACTION
  $push.schemaVersion=2;$push['repositoryId']='CONTROL';$push.delegatedGitCloser=$true;$push.userConfirmation=$decision;$push.invalidatesOn+=@('REPOSITORY_CHANGE')
  $push['gitPushBinding']=[ordered]@{remote='origin';branch='main';remoteUrlIdentity=$remoteUrlIdentity;expectedRemoteCommit=$remoteCommit;localCommit=$localCommit;acceptanceEvidencePath=$evidenceRelative;acceptanceEvidenceIdentity=Get-Identity $evidencePath}
  $push.taskIdentity=Get-Identity $taskPath
  $pushCheck=Invoke-Check $push owner-fixture PUSH
  if($pushCheck.Code-ne0){Write-Output ('DIAG|domain-owner-push|'+$pushCheck.Text)}
  Assert-True ($pushCheck.Code-eq0) 'domain-owner-exact-accepted-push-package-passes'
  $noDecision=$push|ConvertTo-Json -Depth 50|ConvertFrom-Json;$noDecision.userConfirmation='NOT_REQUIRED'
  Assert-True ((Invoke-Check $noDecision owner-fixture PUSH).Code-ne0) 'domain-owner-push-rejects-missing-user-decision'
  $staleRemote=$push|ConvertTo-Json -Depth 50|ConvertFrom-Json;$staleRemote.gitPushBinding.expectedRemoteCommit=$localCommit
  Assert-True ((Invoke-Check $staleRemote owner-fixture PUSH).Code-ne0) 'domain-owner-push-rejects-remote-parent-drift'
  Write-Utf8 $objectPath 'Unreviewed replacement commit'
  & git -C $temp add -- $objectRelative
  & git -C $temp commit -q --amend -m unreviewed
  $unreviewedCommit=([string](& git -C $temp rev-parse HEAD)).ToUpperInvariant()
  $rebound=$push|ConvertTo-Json -Depth 50|ConvertFrom-Json;$rebound.gitPushBinding.localCommit=$unreviewedCommit
  foreach($object in @($rebound.objectIdentities)){if([string]$object.path -ceq $objectRelative){$object.identity=Get-Identity $objectPath}}
  $oldAcceptance=Invoke-Check $rebound owner-fixture PUSH
  Assert-True ($oldAcceptance.Code-ne0 -and $oldAcceptance.Text -match 'PUSH_ACCEPTED_COMMIT_DRIFT|EVIDENCE_CANDIDATE_DRIFT|EVIDENCE_IDENTITY_DRIFT') 'task-owner-push-rejects-old-acceptance-for-new-same-parent-pathset-commit'
  & git -C $temp reset -q --hard $localCommit
  $foreignIndex=Join-Path $temp 'foreign.txt';Write-Utf8 $foreignIndex 'Other owner';& git -C $temp add -- foreign.txt
  Assert-True ((Invoke-Check $push owner-fixture PUSH).Code-ne0) 'domain-owner-push-rejects-shared-index'
  }
}catch{
  $authorizationFirstFailure=$_
  $KeepFixture=$true
  throw
}finally{
  try{
  if($KeepFixture){Write-Output ('FIXTURE_RETAINED|'+$temp)}
  else{
  if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$tempResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));$tempPrefix=$tempRoot+[IO.Path]::DirectorySeparatorChar;$tempLeaf=[IO.Path]::GetFileName($tempResolved);if(-not$tempResolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)-or$tempLeaf-cnotmatch'^aiw-authorization-receipt-[a-f0-9]{32}$'){throw 'TEMP_CLEANUP_BOUNDARY'};Get-ChildItem -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue}
  }
  }catch{if($null-eq$authorizationFirstFailure){throw};$authorizationCleanupFailure=$_}
}
Write-GroupCompletion
}catch{
 $failure=if($null-ne$authorizationFirstFailure){$authorizationFirstFailure}else{$_}
 $errorEnvelope=[ordered]@{status='FAIL';reason=[string]$failure.Exception.Message;scriptStackTrace=[string]$failure.ScriptStackTrace;fullyQualifiedErrorId=[string]$failure.FullyQualifiedErrorId}
 if($null-ne$authorizationCleanupFailure){$errorEnvelope.cleanupError=[ordered]@{reason=[string]$authorizationCleanupFailure.Exception.Message;scriptStackTrace=[string]$authorizationCleanupFailure.ScriptStackTrace;fullyQualifiedErrorId=[string]$authorizationCleanupFailure.FullyQualifiedErrorId}}
 [Console]::Error.WriteLine(($errorEnvelope|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii))
 exit 1
}
