[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Write-Json([string]$Path,$Value){Write-Utf8 $Path ($Value|ConvertTo-Json -Depth 50)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}

$checker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\check-authorization.ps1'))
$taskChecker=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\check-task-card.ps1'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-authorization-receipt-'+[guid]::NewGuid().ToString('N'))
$control=Join-Path $temp '.ai-workspace'
$taskRelative='.ai-workspace/tasks/active/AUTH-REGRESSION-001.md'
$taskPath=Join-Path $temp $taskRelative
$objectRelative='src/item.txt'
$objectPath=Join-Path $temp $objectRelative
$packagePath=Join-Path $control 'authorization.json'

function Write-Task([string]$Profile,[string]$Phase,[string]$Lifecycle='ACTIVE'){
  $currentExact=if($Profile-ceq'CRITICAL'){" current_exact=$objectRelative;"}else{''}
  $criticalLines=if($Profile-ceq'CRITICAL'){"- Proportionality: existing=partial; classification=framework_gap; minimum_sufficient_fix=bind the package profile to the current task; added_machinery=NONE; escalation_trigger=another independent profile-binding defect`n- Phase gate: FALSE`n"}else{''}
  Write-Utf8 $taskPath ("# AUTH-REGRESSION-001 - authorization regression fixture`n`n- Task schema: 1.16.0`n- Owner: owner-fixture`n- Work route: actor=writer-fixture; role=EXECUTOR; phase=$Phase`n- Range summary: profile=$Profile; lifecycle=$Lifecycle;$currentExact expected_paths=[$objectRelative]; actual_paths=[]`n$criticalLines")
}

function New-Package([string]$Profile,[string]$IssuerRole,[string]$Grantee,[string]$Action,[string]$DecisionClass,[string]$Issuer='owner-fixture'){
  $invalidators=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')
  $package=[ordered]@{schemaVersion=1;frameworkVersion='1.16.0';taskId='AUTH-REGRESSION-001';profile=$Profile;lifecycle='ACTIVE';owner='owner-fixture';issuer=$Issuer;issuerRole=$IssuerRole;grantee=$Grantee;bundle='PLAN_LOCAL';decisionClass=$DecisionClass;userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Get-Identity $taskPath;actions=@($Action);exactPaths=@($objectRelative);objectIdentities=@([ordered]@{path=$objectRelative;identity=Get-Identity $objectPath});invalidatesOn=$invalidators;projectConfigIdentity=Get-Identity (Join-Path $control 'project.json')}
  if($IssuerRole-ceq'PROJECT_CONTROLLER'){
    $package['issuerControllerId']='controller-fixture';$package['issuerControllerEpoch']=1;$package['controllerControlIdentity']=Get-Identity (Join-Path $control 'controller.json');$package['invalidatesOn']+=@('CONTROLLER_EPOCH_CHANGE')
  }
  if($Profile-ceq'CRITICAL'-and$Action-ceq'REVIEW_EXECUTE'){
    $package['reviewIndependence']='INDEPENDENT';$package['candidateWriter']='writer-fixture';$package['materialContributors']=@();$package['invalidatesOn']+=@('CONTRIBUTOR_SET_CHANGE')
  }
  return $package
}

function Invoke-Check($Package,[string]$Actor,[string]$Action){
  Write-Json $packagePath $Package
  $arguments=@('-NoProfile','-NonInteractive','-File',$checker,'-PackagePath',$packagePath,'-ObservedActor',$Actor,'-ObservedTaskId','AUTH-REGRESSION-001','-ObservedOwner','owner-fixture','-ObservedAction',$Action,'-ObservedPath',$objectRelative,'-ObservedIdentity',($objectRelative+'='+(Get-Identity $objectPath)),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','REPO_LOCAL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',(Get-Identity (Join-Path $control 'project.json')),'-TaskPath',$taskRelative,'-ExpectedTaskIdentity',(Get-Identity $taskPath))
  Push-Location $temp
  try{$output=@(& pwsh @arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{Pop-Location}
  return [pscustomobject]@{Code=$code;Text=($output-join"`n")}
}

function Invoke-TaskCheck(){
  $arguments=@('-NoProfile','-NonInteractive','-File',$taskChecker,'-TaskPath',$taskPath)
  $output=@(& pwsh @arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
  return [pscustomobject]@{Code=$code;Text=($output-join"`n")}
}

New-Item -ItemType Directory -Path (Join-Path $control 'tasks\active') -Force|Out-Null
try{
  & git -C $temp init -q
  if($LASTEXITCODE-ne0){throw 'GIT_INIT_FAILED'}
  Write-Json (Join-Path $control 'project.json') ([ordered]@{schemaVersion=3;id='authorization-receipt-fixture';displayName='Authorization Receipt Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{}})
  Write-Json (Join-Path $control 'controller.json') ([ordered]@{schemaVersion=1;projectId='authorization-receipt-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
  Write-Utf8 $objectPath 'fixture object'

  Write-Task 'STANDARD' 'IMPLEMENT' 'ACTIVE_WRITE'
  $externalTaskCheck=Invoke-TaskCheck
  Assert-True ($externalTaskCheck.Code-eq0) 'task-card-active-write-allows-external-authorization-carrier'
  $externalPackage=New-Package 'STANDARD' 'DOMAIN_OWNER' 'writer-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL'
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

  Write-Task 'STANDARD' 'IMPLEMENT'
  $standard=Invoke-Check (New-Package 'STANDARD' 'DOMAIN_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($standard.Code-eq0) 'authorization-canonical-standard-package-passes'

  $planned=New-Package 'STANDARD' 'DOMAIN_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL';$planned.actions=@('SOURCE_WRITE','TEST_RUN');$planned|Add-Member -NotePropertyName continuationPlan -NotePropertyValue @('SOURCE_WRITE','TEST_RUN','SOURCE_WRITE');$planned.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
  $plannedInitial=Invoke-Check $planned 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($plannedInitial.Code-eq0) 'authorization-temporary-actor-multi-action-plan-admits-first-step'
  $plannedSkip=Invoke-Check $planned 'executor-fixture' 'TEST_RUN'
  Assert-True ($plannedSkip.Code-ne0-and$plannedSkip.Text.Contains('CONTINUATION_ACTION_ORDER_DRIFT')) 'authorization-continuation-plan-rejects-skipped-first-step'
  $missingContinuationInvalidator=$planned|ConvertTo-Json -Depth 50|ConvertFrom-Json;$missingContinuationInvalidator.invalidatesOn=@($missingContinuationInvalidator.invalidatesOn|Where-Object{$_-cne'CONTINUATION_RESULT_DRIFT'});$missingContinuationInvalidatorRun=Invoke-Check $missingContinuationInvalidator 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($missingContinuationInvalidatorRun.Code-ne0-and$missingContinuationInvalidatorRun.Text.Contains('INVALIDATOR_MISSING_CONTINUATION_RESULT_DRIFT')) 'authorization-continuation-plan-requires-result-drift-invalidator'

  $lowerDecision=Invoke-Check (New-Package 'STANDARD' 'DOMAIN_OWNER' 'executor-fixture' 'SOURCE_WRITE' 'routine_local') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($lowerDecision.Code-ne0-and$lowerDecision.Text.Contains('DECISION_CLASS')) 'authorization-decision-class-is-case-sensitive'

  $lowerController=Invoke-Check (New-Package 'STANDARD' 'project_controller' 'executor-fixture' 'SOURCE_WRITE' 'ROUTINE_LOCAL' 'controller-fixture') 'executor-fixture' 'SOURCE_WRITE'
  Assert-True ($lowerController.Code-ne0-and$lowerController.Text.Contains('ISSUER_ROLE')) 'authorization-controller-role-is-case-sensitive'

  Write-Task 'CRITICAL' 'REVIEW'
  $critical=Invoke-Check (New-Package 'CRITICAL' 'DOMAIN_OWNER' 'reviewer-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL') 'reviewer-fixture' 'REVIEW_EXECUTE'
  Assert-True ($critical.Code-eq0) 'authorization-canonical-independent-critical-review-passes'

  $lowerProfile=Invoke-Check (New-Package 'critical' 'DOMAIN_OWNER' 'owner-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL') 'owner-fixture' 'REVIEW_EXECUTE'
  Assert-True ($lowerProfile.Code-ne0-and$lowerProfile.Text.Contains('PROFILE')) 'authorization-critical-profile-is-case-sensitive'

  $profileMismatch=Invoke-Check (New-Package 'STANDARD' 'DOMAIN_OWNER' 'owner-fixture' 'REVIEW_EXECUTE' 'ROUTINE_LOCAL') 'owner-fixture' 'REVIEW_EXECUTE'
  Assert-True ($profileMismatch.Code-ne0-and$profileMismatch.Text.Contains('TASK_PROFILE_DRIFT')) 'authorization-package-profile-matches-task-range-profile'
}finally{
  if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$tempResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));$tempPrefix=$tempRoot+[IO.Path]::DirectorySeparatorChar;$tempLeaf=[IO.Path]::GetFileName($tempResolved);if(-not$tempResolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)-or$tempLeaf-cnotmatch'^aiw-authorization-receipt-[a-f0-9]{32}$'){throw 'TEMP_CLEANUP_BOUNDARY'};Get-ChildItem -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue|ForEach-Object{try{$_.Attributes=[IO.FileAttributes]::Normal}catch{}};Remove-Item -LiteralPath $tempResolved -Recurse -Force -ErrorAction SilentlyContinue}
}
Write-Output ('RESULT|'+$passed+' passed|scope=authorization-receipt-regression')
