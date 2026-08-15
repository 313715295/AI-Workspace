[CmdletBinding()]
param([switch]$SkipRootMigration)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$utf8NoBom=New-Object Text.UTF8Encoding($false)
$passCount=0

function Assert-Test([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAIL|$Name"};$script:passCount++;Write-Output "PASS|$Name"}
function Write-Text([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent -and -not(Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8NoBom)}
function Write-Json([string]$Path,$Value){Write-Text $Path ($Value|ConvertTo-Json -Depth 30)}
function Clone($Value){return (($Value|ConvertTo-Json -Depth 30)|ConvertFrom-Json)}
function Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);$sha=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','');return "$($bytes.Length)|$sha"}
function Canonical-Controller([string]$Project,[string]$Controller,[int64]$Epoch){return ([ordered]@{schemaVersion=1;projectId=$Project;controllerId=$Controller;controllerEpoch=$Epoch;state='CURRENT'}|ConvertTo-Json -Compress)+"`n"}
function Get-RemoteKey([string]$TaskId,[string]$Candidate,$Remote){$hasLocator=$Remote.PSObject.Properties.Name-contains'compensationAuthorizationLocator';$hasIdentity=$Remote.PSObject.Properties.Name-contains'compensationAuthorizationIdentity';$input=[ordered]@{schemaVersion=1;taskId=$TaskId;candidate=$Candidate;remoteId=[string]$Remote.remoteId;endpointFingerprint=[string]$Remote.endpointFingerprint;action=[string]$Remote.action;refspec=[string]$Remote.refspec;authorizationLocator=[string]$Remote.authorizationLocator;authorizationIdentity=[string]$Remote.authorizationIdentity;compensationAuthorizationLocatorPresent=$hasLocator;compensationAuthorizationLocator=if($hasLocator){[string]$Remote.compensationAuthorizationLocator}else{''};compensationAuthorizationIdentityPresent=$hasIdentity;compensationAuthorizationIdentity=if($hasIdentity){[string]$Remote.compensationAuthorizationIdentity}else{''};expectedLocalHead=[string]$Remote.expectedLocalHead;expectedRemoteHead=[string]$Remote.expectedRemoteHead};$bytes=[Text.Encoding]::UTF8.GetBytes(($input|ConvertTo-Json -Compress));return ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-',''))}
function Invoke-Git([string]$Repo,[string[]]$Arguments){$old=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$output=@(& git -C $Repo @Arguments 2>$null|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old};if($code-ne 0){throw "GIT_FAILED|$($Arguments -join ' ')"};return $output}
function Invoke-PowerShellCapture([string[]]$Arguments){$old=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$output=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old};return [pscustomobject]@{Output=$output;ExitCode=$code}}
function New-TestRepo([string]$Path){New-Item -ItemType Directory -Path $Path -Force|Out-Null;$null=& git init --quiet $Path;$null=& git -C $Path config user.email 'framework-tests@example.invalid';$null=& git -C $Path config user.name 'Framework Tests';Write-Text (Join-Path $Path 'README.md') "# fixture`n";$null=& git -C $Path add README.md;$null=& git -C $Path commit --quiet -m init}
function Get-TreeCanonical([string]$Root){$files=@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force|Where-Object{$_.FullName -cne (Join-Path $Root 'RELEASE_MANIFEST.json')});$rows=@();$total=[int64]0;foreach($file in $files){$relative=$file.FullName.Substring($Root.Length+1).Replace('\','/');$bytes=[IO.File]::ReadAllBytes($file.FullName);$total+=$bytes.Length;$sha=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','');$rows+="$relative|$($bytes.Length)|$sha"};[Array]::Sort($rows,[StringComparer]::Ordinal);$payload=[Text.Encoding]::UTF8.GetBytes(($rows-join"`n"));$canonical=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload)).Replace('-','');return [pscustomobject]@{Count=$files.Count;Total=$total;Canonical=$canonical;Rows=$rows}}

$versionRoot=Split-Path -Parent $PSScriptRoot
$workspaceRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '..\..\..\..'))
$baselineRoot=Join-Path $workspaceRoot 'framework\versions\1.5.2'
$draftRoot=Split-Path -Parent $versionRoot
$rootScripts=Join-Path $draftRoot 'root-scripts'
$authChecker=Join-Path $versionRoot 'scripts\check-authorization.ps1'
$taskChecker=Join-Path $versionRoot 'scripts\check-task-card.ps1'
$controllerChecker=Join-Path $versionRoot 'scripts\check-controller-route.ps1'
$remoteChecker=Join-Path $versionRoot 'scripts\check-remote-transaction.ps1'
$loader=Join-Path $versionRoot 'scripts\resolve-load-plan.ps1'

$release=(Get-Content -Raw -Encoding UTF8 (Join-Path $baselineRoot 'RELEASE_MANIFEST.json'))|ConvertFrom-Json
$baseline=Get-TreeCanonical $baselineRoot
Assert-Test ($baseline.Count-eq[int]$release.fileCount-and$baseline.Total-eq[int64]$release.totalBytes-and$baseline.Canonical-ceq[string]$release.canonical) 'baseline-1.5.2-release-canonical'
Assert-Test ((Identity (Join-Path $workspaceRoot 'scripts\register-project.ps1'))-ceq'22358|6AE4FD80FB25653FA4606961EED8CD1B652F4A791E9D445C04E9B473E83CC6B1') 'live-register-baseline-identity'
Assert-Test ((Identity (Join-Path $workspaceRoot 'scripts\upgrade-project.ps1'))-ceq'48080|679F4D0B2519EA4777566ED5A48F89F6AD0451DB489EFDAF6A5C6BB8F9F43C9B') 'live-upgrade-baseline-identity'

$baselineRelative=@(Get-ChildItem -LiteralPath $baselineRoot -File -Recurse -Force|ForEach-Object{$_.FullName.Substring($baselineRoot.Length+1).Replace('\','/')})
$expected=@($baselineRelative)+@('CONTROLLER_SCHEMA.json','REMOTE_TRANSACTION_SCHEMA.json','project-starter/controller.json','scripts/check-controller-route.ps1','scripts/check-remote-transaction.ps1')
$actual=@(Get-ChildItem -LiteralPath $versionRoot -File -Recurse -Force|ForEach-Object{$_.FullName.Substring($versionRoot.Length+1).Replace('\','/')})
Assert-Test (@(Compare-Object $expected $actual -CaseSensitive).Count-eq0-and$actual.Count-eq37) 'candidate-inventory-37'
Assert-Test (@(Get-ChildItem -LiteralPath $rootScripts -File -Recurse).Count-eq2) 'draft-root-script-inventory-2'
foreach($file in @(Get-ChildItem -LiteralPath $versionRoot -File -Recurse -Force)+@(Get-ChildItem -LiteralPath $rootScripts -File -Recurse -Force)){$bytes=[IO.File]::ReadAllBytes($file.FullName);$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);Assert-Test (-not($bytes.Length-ge3-and$bytes[0]-eq0xEF-and$bytes[1]-eq0xBB-and$bytes[2]-eq0xBF)-and-not$text.Contains("`r")-and-not$text.Contains([char]0)-and-not$text.Contains([char]0xFFFD)-and$text.EndsWith("`n")) ('strict-text-'+$file.Name)}
$metadata=(Get-Content -Raw -Encoding UTF8 (Join-Path $versionRoot 'VERSION.json'))|ConvertFrom-Json
$manifest=(Get-Content -Raw -Encoding UTF8 (Join-Path $versionRoot 'RELEASE_MANIFEST.json'))|ConvertFrom-Json
Assert-Test ([string]$metadata.version-ceq'1.6.0'-and[string]$metadata.lifecycle-ceq'DRAFT'-and-not[bool]$metadata.consumable-and-not[bool]$metadata.projectPinEligible) 'metadata-draft-not-consumable'
Assert-Test ([string]$manifest.lifecycle-ceq'DRAFT'-and-not[bool]$manifest.consumable-and$null-eq$manifest.canonical) 'release-manifest-unfrozen'
$null=(Get-Content -Raw -Encoding UTF8 (Join-Path $versionRoot 'CONTROLLER_SCHEMA.json'))|ConvertFrom-Json;$null=(Get-Content -Raw -Encoding UTF8 (Join-Path $versionRoot 'REMOTE_TRANSACTION_SCHEMA.json'))|ConvertFrom-Json
Assert-Test $true 'schemas-json-parse'
$defaultLoad=Invoke-PowerShellCapture @('-File',$loader,'-Role','EXECUTOR','-Profile','MICRO','-Phase','RECOVER')
Assert-Test ($defaultLoad.ExitCode-ne0-and($defaultLoad.Output-join' ') -like '*LOAD_MANIFEST_NOT_CONSUMABLE*') 'draft-loader-default-deny'
$plan=& $loader -Role FRAMEWORK_MAINTAINER -Profile CRITICAL -Phase RECOVER,PLAN -HostName CODEX -AllowDraftCandidate -AsJson|ConvertFrom-Json
Assert-Test ([string]$plan.frameworkVersion-ceq'1.6.0'-and[string]$plan.lifecycle-ceq'DRAFT'-and@($plan.modules).Count-eq7) 'draft-loader-explicit-test-only'

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('framework-160-acg-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force|Out-Null
try{
    $controller1=Join-Path $tempRoot 'controller-1\.ai-workspace\controller.json';Write-Text $controller1 (Canonical-Controller 'sample-project' 'controller-1' 1);$controller1Identity=Identity $controller1
    $domain=[ordered]@{schemaVersion=1;frameworkVersion='1.6.0';taskId='AUTH-1';profile='STANDARD';lifecycle='ACTIVE';owner='domain-1';issuer='domain-1';issuerRole='DOMAIN_OWNER';grantee='executor-1';bundle='IMPLEMENT_LOCAL';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;actions=@('SOURCE_WRITE');exactPaths=@('src/a.js');objectIdentities=@([ordered]@{path='src/a.js';identity='NEW'});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE')}
    $domainPath=Join-Path $tempRoot 'domain.json';Write-Json $domainPath $domain
    $result=& $authChecker -PackagePath $domainPath -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner domain-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq0-and$result-like'PASS|*') 'authorization-domain-owner-controller-neutral'
    $project=Clone $domain;$project.owner='controller-1';$project.issuer='controller-1';$project.issuerRole='PROJECT_CONTROLLER';$project.grantee='executor-1';$project|Add-Member -NotePropertyName issuerProjectId -NotePropertyValue 'sample-project';$project|Add-Member -NotePropertyName issuerControllerId -NotePropertyValue 'controller-1';$project|Add-Member -NotePropertyName issuerControllerEpoch -NotePropertyValue ([int64]1);$project|Add-Member -NotePropertyName controllerControlLocator -NotePropertyValue '.ai-workspace/controller.json';$project|Add-Member -NotePropertyName controllerControlIdentity -NotePropertyValue $controller1Identity
    $projectPath=Join-Path $tempRoot 'project-auth.json';Write-Json $projectPath $project
    $controllerObserved1=@{ControllerControlPath=$controller1;ObservedProjectId='sample-project';ObservedControllerLocator='.ai-workspace/controller.json'}
    $result=& $authChecker -PackagePath $projectPath @controllerObserved1 -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq0-and$result-like'*epoch=1*') 'authorization-current-controller-pass'
    $result=& $authChecker -PackagePath $projectPath -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_CONTROLLER_AUTHORIZATION*') 'authorization-controller-path-required'
    $missingControllerFields=Clone $project;$missingControllerFields.PSObject.Properties.Remove('issuerControllerId');$missingControllerFields.PSObject.Properties.Remove('issuerControllerEpoch');$missingControllerFields.PSObject.Properties.Remove('controllerControlIdentity');$missingControllerFieldsPath=Join-Path $tempRoot 'legacy-controller-auth.json';Write-Json $missingControllerFieldsPath $missingControllerFields
    $result=& $authChecker -PackagePath $missingControllerFieldsPath @controllerObserved1 -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_CONTROLLER_AUTHORIZATION*') 'authorization-legacy-controller-package-stale'
    $issuerMismatch=Clone $project;$issuerMismatch.issuer='other-controller';$issuerMismatchPath=Join-Path $tempRoot 'issuer-mismatch.json';Write-Json $issuerMismatchPath $issuerMismatch
    $result=& $authChecker -PackagePath $issuerMismatchPath @controllerObserved1 -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_CONTROLLER_AUTHORIZATION*') 'authorization-issuer-three-way-equality'
    $forged=Clone $project;$forged.controllerControlIdentity='1_'+('F'*64);$forgedPath=Join-Path $tempRoot 'forged.json';Write-Json $forgedPath $forged
    $result=& $authChecker -PackagePath $forgedPath @controllerObserved1 -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_CONTROLLER_AUTHORIZATION*') 'authorization-forged-controller-identity-deny'

    $controller2=Join-Path $tempRoot 'controller-2\.ai-workspace\controller.json';Write-Text $controller2 (Canonical-Controller 'sample-project' 'controller-2' 2);$controller2Identity=Identity $controller2
    $controllerObserved2=@{ControllerControlPath=$controller2;ObservedProjectId='sample-project';ObservedControllerLocator='.ai-workspace/controller.json'}
    $result=& $authChecker -PackagePath $projectPath @controllerObserved2 -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-1 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_CONTROLLER_AUTHORIZATION*') 'authorization-old-controller-cache-invalidated'
    $currentProject=Clone $project;$currentProject.owner='controller-2';$currentProject.issuer='controller-2';$currentProject.issuerControllerId='controller-2';$currentProject.issuerControllerEpoch=[int64]2;$currentProject.controllerControlIdentity=$controller2Identity;$currentProjectPath=Join-Path $tempRoot 'project-auth-2.json';Write-Json $currentProjectPath $currentProject
    $result=& $authChecker -PackagePath $currentProjectPath @controllerObserved2 -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-2 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq0) 'authorization-new-controller-reissue-pass'
    $crossProject=Join-Path $tempRoot 'cross-project\.ai-workspace\controller.json';Write-Text $crossProject (Canonical-Controller 'other-project' 'controller-2' 2);$crossProjectIdentity=Identity $crossProject
    $crossPackage=Clone $currentProject;$crossPackage.controllerControlIdentity=$crossProjectIdentity;$crossPackagePath=Join-Path $tempRoot 'cross-project-auth.json';Write-Json $crossPackagePath $crossPackage
    $result=& $authChecker -PackagePath $crossPackagePath -ControllerControlPath $crossProject -ObservedProjectId other-project -ObservedControllerLocator '.ai-workspace/controller.json' -ObservedActor executor-1 -ObservedTaskId AUTH-1 -ObservedOwner controller-2 -ObservedAction SOURCE_WRITE -ObservedPath src/a.js -ObservedIdentity src/a.js=NEW
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_CONTROLLER_AUTHORIZATION*') 'authorization-cross-project-controller-deny'

    $rotation=[ordered]@{schemaVersion=1;projectId='sample-project';previousControllerId='controller-1';previousControllerEpoch=1;previousControlIdentity=$controller1Identity;successorControllerId='controller-2';successorControllerEpoch=2;successorControlIdentity=$controller2Identity;successorAcceptance='FULL_COLD_ACCEPTED';pointerCommit=$true;exceptionTargetsRebound=$true;oldNewTaskEntry='CLOSED';oldGrace='READ_ONLY';legacyAuthorizationDisposition='STALE_AUDIT_ONLY'}
    $rotationPath=Join-Path $tempRoot 'rotation.json';Write-Json $rotationPath $rotation
    $result=& $controllerChecker -ControllerControlPath $controller2 -PreviousControllerControlPath $controller1 -RotationPath $rotationPath
    Assert-Test ($LASTEXITCODE-eq0-and$result-like'PASS|controller-rotation*') 'controller-rotation-accepted-atomic'
    $badRotation=Clone $rotation;$badRotation.successorAcceptance='PENDING';$badRotationPath=Join-Path $tempRoot 'rotation-pending.json';Write-Json $badRotationPath $badRotation
    $result=& $controllerChecker -ControllerControlPath $controller2 -PreviousControllerControlPath $controller1 -RotationPath $badRotationPath
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*ROTATION_SUCCESSOR_NOT_ACCEPTED*') 'controller-successor-before-accept-deny'

    function New-Route([string]$Transition,[string]$Class,[int64]$QueuedEpoch,[string]$QueuedId){$message=if($Class-ceq'ROUTINE_SUMMARY'){'STATE'}else{$Class};return [ordered]@{schemaVersion=1;projectId='sample-project';controllerId='controller-2';controllerEpoch=2;controllerControlIdentity=$controller2Identity;sourceTaskId='TASK-1';candidateTransition=$Transition;responsibleReporter='owner-1';messageClass=$message;routeClass=$Class;queuedControllerId=$QueuedId;queuedControllerEpoch=$QueuedEpoch;taskPersisted=$true;stateKey="sample-project|2|TASK-1|$Transition|owner-1"}}
    $route=New-Route 'COMPLETE' 'ROUTINE_SUMMARY' 2 'controller-2';$routePath=Join-Path $tempRoot 'route.json';Write-Json $routePath $route
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $routePath;Assert-Test ($LASTEXITCODE-eq0-and$result-like'PASS|controller-route*') 'controller-route-current'
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $routePath -SeenStateKey $route.stateKey;Assert-Test ($LASTEXITCODE-eq0-and$result-like'*STATE_DUPLICATE_SUPPRESSED*') 'controller-state-dedup'
    $ack=Clone $route;$ack.messageClass='ACK';$ackPath=Join-Path $tempRoot 'ack.json';Write-Json $ackPath $ack
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $ackPath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*ACK_CHAIN_FORBIDDEN*') 'controller-no-ack-chain'
    $staleRoutine=New-Route 'OWNER_ACCEPTED' 'ROUTINE_SUMMARY' 1 'controller-1';$staleRoutinePath=Join-Path $tempRoot 'stale-routine.json';Write-Json $staleRoutinePath $staleRoutine
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $staleRoutinePath;Assert-Test ($LASTEXITCODE-eq0-and$result-like'*STALE_QUEUED_SUPPRESSED*') 'controller-stale-routine-suppressed'
    $exception=New-Route 'WRITER_CONFLICT' 'EXCEPTION' 1 'controller-1';$exceptionPath=Join-Path $tempRoot 'exception.json';Write-Json $exceptionPath $exception
    $originalExceptionPath=Join-Path $tempRoot 'original-exception.json';Write-Json $originalExceptionPath $exception;$originalExceptionIdentity=Identity $originalExceptionPath
    $currentTaskPath=Join-Path $tempRoot 'current-task.md';$currentTaskText="# TASK-1 - current task`n`n- state: CURRENT`n";Write-Text $currentTaskPath $currentTaskText;$currentTaskIdentity=Identity $currentTaskPath
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $exceptionPath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_EXCEPTION_REVALIDATION_REQUIRED*') 'controller-stale-exception-needs-revalidation'
    $exception|Add-Member -NotePropertyName revalidatedAgainstCurrentTask -NotePropertyValue $true;$exception|Add-Member -NotePropertyName rerouteCount -NotePropertyValue ([int64]1);$exception|Add-Member -NotePropertyName authorizationDisposition -NotePropertyValue 'NONE_REUSED';$exception|Add-Member -NotePropertyName originalEnvelopeLocator -NotePropertyValue 'original-exception.json';$exception|Add-Member -NotePropertyName originalEnvelopeIdentity -NotePropertyValue $originalExceptionIdentity;$exception|Add-Member -NotePropertyName originalMessageClass -NotePropertyValue 'EXCEPTION';$exception|Add-Member -NotePropertyName currentTaskLocator -NotePropertyValue 'current-task.md';$exception|Add-Member -NotePropertyName currentTaskIdentity -NotePropertyValue $currentTaskIdentity;Write-Json $exceptionPath $exception
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $exceptionPath -OriginalEnvelopePath $originalExceptionPath -ObservedOriginalEnvelopeIdentity $originalExceptionIdentity -CurrentTaskPath $currentTaskPath;Assert-Test ($LASTEXITCODE-eq0-and$result-like'*STALE_EXCEPTION_REROUTED_ONCE*') 'controller-stale-exception-rerouted-once'
    Write-Text $currentTaskPath ($currentTaskText+"- drift: true`n");$result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $exceptionPath -OriginalEnvelopePath $originalExceptionPath -ObservedOriginalEnvelopeIdentity $originalExceptionIdentity -CurrentTaskPath $currentTaskPath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*CURRENT_TASK_IDENTITY_DRIFT*') 'controller-stale-exception-current-task-drift-deny';Write-Text $currentTaskPath $currentTaskText
    $staleAck=Clone $exception;$staleAck.messageClass='ACK';$staleAckPath=Join-Path $tempRoot 'stale-ack-exception.json';Write-Json $staleAckPath $staleAck
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $staleAckPath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*ACK_CHAIN_FORBIDDEN*') 'controller-stale-ack-cannot-wrap-exception'
    $staleDecision=New-Route 'USER_ACCEPTED' 'USER_DECISION' 1 'controller-1';$staleDecisionPath=Join-Path $tempRoot 'stale-decision.json';Write-Json $staleDecisionPath $staleDecision
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $staleDecisionPath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_DECISION_OR_AUTHORIZATION*') 'controller-stale-decision-deny'
    $originalDecisionPath=Join-Path $tempRoot 'original-decision.json';Write-Json $originalDecisionPath $staleDecision;$originalDecisionIdentity=Identity $originalDecisionPath
    $wrappedDecision=Clone $staleDecision;$wrappedDecision.messageClass='EXCEPTION';$wrappedDecision.routeClass='EXCEPTION';$wrappedDecision|Add-Member -NotePropertyName revalidatedAgainstCurrentTask -NotePropertyValue $true;$wrappedDecision|Add-Member -NotePropertyName rerouteCount -NotePropertyValue ([int64]1);$wrappedDecision|Add-Member -NotePropertyName authorizationDisposition -NotePropertyValue 'NONE_REUSED';$wrappedDecision|Add-Member -NotePropertyName originalEnvelopeLocator -NotePropertyValue 'original-decision.json';$wrappedDecision|Add-Member -NotePropertyName originalEnvelopeIdentity -NotePropertyValue $originalDecisionIdentity;$wrappedDecision|Add-Member -NotePropertyName originalMessageClass -NotePropertyValue 'USER_DECISION';$wrappedDecision|Add-Member -NotePropertyName currentTaskLocator -NotePropertyValue 'current-task.md';$wrappedDecision|Add-Member -NotePropertyName currentTaskIdentity -NotePropertyValue $currentTaskIdentity;$wrappedDecisionPath=Join-Path $tempRoot 'wrapped-decision.json';Write-Json $wrappedDecisionPath $wrappedDecision
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $wrappedDecisionPath -OriginalEnvelopePath $originalDecisionPath -ObservedOriginalEnvelopeIdentity $originalDecisionIdentity -CurrentTaskPath $currentTaskPath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_ORIGINAL_DECISION_OR_AUTHORIZATION*') 'controller-stale-decision-double-class-wrap-deny'
    $unknownRoute=Clone $route;$unknownRoute.messageClass='MYSTERY';$unknownRoutePath=Join-Path $tempRoot 'unknown-route.json';Write-Json $unknownRoutePath $unknownRoute
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $unknownRoutePath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*MESSAGE_CLASS_UNKNOWN*') 'controller-unknown-message-deny'
    $staleRoute=Clone $route;$staleRoute.controllerId='controller-1';$staleRoute.controllerEpoch=[int64]1;$staleRoute.controllerControlIdentity=$controller1Identity;$staleRoutePath=Join-Path $tempRoot 'stale-route.json';Write-Json $staleRoutePath $staleRoute
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $staleRoutePath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*STALE_CONTROLLER_ROUTE*') 'controller-stale-decision-authorization-ack-deny'
    $unpersisted=Clone $route;$unpersisted.taskPersisted=$false;$unpersistedPath=Join-Path $tempRoot 'unpersisted.json';Write-Json $unpersistedPath $unpersisted
    $result=& $controllerChecker -ControllerControlPath $controller2 -RoutePath $unpersistedPath;Assert-Test ($LASTEXITCODE-eq2-and$result-like'*TASK_CURRENT_NOT_PERSISTED*') 'controller-pull-requires-persisted-current'

    $contextIdentity='10|'+('C'*64);$adapterIdentity='11|'+('D'*64)
    $taskText=@"
# TASK-RESOURCE - resource and coordination

- Task schema: 1.6
- Owner: owner-1
- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[src/a.js]; actual_paths=[src/a.js]
- Resource contract: phase=VERIFY; hostClass=HOST_NEUTRAL; contextIdentity=$contextIdentity; minimumQuality=FOCUSED_HIGH; requiredTools=[shell|git]; continuity=FRESH; latencyClass=BOUNDED; costCeiling=MEDIUM; concurrencyFit=PARALLEL_OK; adapterResult=SUPPORTED; adapterResultIdentity=$adapterIdentity; selectedQuality=FOCUSED_HIGH; invalidatesOn=[HOST_CHANGE|PHASE_CHANGE|TOOL_CHANGE|CONTEXT_CHANGE]
- Coordination contract: mode=INDEPENDENT_TASK; sourceTaskId=SOURCE-1; reportTo=owner-1; waitPolicy=NO_POLL; archivePolicy=TERMINAL_ONLY; userDecisionHandoff=NONE
"@
    $taskPath=Join-Path $tempRoot 'TASK-RESOURCE.md';Write-Text $taskPath $taskText
    $resourceObserved=@{ObservedPhase='VERIFY';ObservedHostClass='HOST_NEUTRAL';ObservedContextIdentity=$contextIdentity;ObservedAdapterResultIdentity=$adapterIdentity}
    $result=& $taskChecker -TaskPath $taskPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq0-and$result-like'PASS|*') 'resource-host-neutral-supported'
    $result=& $taskChecker -TaskPath $taskPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell @resourceObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*RESOURCE_UNSUPPORTED*') 'resource-required-tool-fail-closed'
    $downgradePath=Join-Path $tempRoot 'TASK-DOWNGRADE.md';Write-Text $downgradePath ($taskText.Replace('# TASK-RESOURCE','# TASK-DOWNGRADE').Replace('selectedQuality=FOCUSED_HIGH','selectedQuality=ROUTINE_BALANCED'))
    $result=& $taskChecker -TaskPath $downgradePath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*RESOURCE_SILENT_DOWNGRADE*') 'resource-no-silent-downgrade'
    $waitPath=Join-Path $tempRoot 'TASK-WAIT.md';Write-Text $waitPath ($taskText.Replace('# TASK-RESOURCE','# TASK-WAIT').Replace('waitPolicy=NO_POLL','waitPolicy=CURRENT_TURN_ONLY'))
    $result=& $taskChecker -TaskPath $waitPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*WAIT_POLICY*') 'independent-task-wait-policy'
    $archiveDir=Join-Path $tempRoot 'tasks\archive';New-Item -ItemType Directory -Path $archiveDir -Force|Out-Null;$activeArchivePath=Join-Path $archiveDir 'TASK-ACTIVE.md';Write-Text $activeArchivePath ($taskText.Replace('# TASK-RESOURCE','# TASK-ACTIVE'))
    $result=& $taskChecker -TaskPath $activeArchivePath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*NON_TERMINAL_ARCHIVE*') 'archive-terminal-only'
    $closedText=$taskText.Replace('# TASK-RESOURCE','# TASK-CLOSED').Replace('lifecycle=ACTIVE','lifecycle=CLOSED');$closedPath=Join-Path $archiveDir 'TASK-CLOSED.md';Write-Text $closedPath $closedText
    $result=& $taskChecker -TaskPath $closedPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq0) 'archive-closed-task-pass'
    $result=& $taskChecker -TaskPath $taskPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git -ObservedPhase IMPLEMENT -ObservedHostClass HOST_NEUTRAL -ObservedContextIdentity $contextIdentity -ObservedAdapterResultIdentity $adapterIdentity
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*RESOURCE_PHASE_DRIFT*') 'resource-phase-drift-deny'
    $result=& $taskChecker -TaskPath $taskPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git -ObservedPhase VERIFY -ObservedHostClass LOCAL_AGENT -ObservedContextIdentity $contextIdentity -ObservedAdapterResultIdentity $adapterIdentity
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*RESOURCE_HOST_DRIFT*') 'resource-host-drift-deny'
    $handoffText=$taskText.Replace('# TASK-RESOURCE','# TASK-HANDOFF').Replace('userDecisionHandoff=NONE','userDecisionHandoff=BOUND').Replace('userDecisionHandoff=BOUND',"userDecisionHandoff=BOUND`n- User decision handoff: sourceTaskId=SOURCE-1; candidateEvidence=candidate-1; turnLocator=turn-1; invalidatesOn=[CANDIDATE_CHANGE|USER_DECISION_CHANGE|LOCATOR_CHANGE]")
    $handoffPath=Join-Path $tempRoot 'TASK-HANDOFF.md';Write-Text $handoffPath $handoffText
    $result=& $taskChecker -TaskPath $handoffPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq0) 'user-decision-handoff-source-bound-pass'
    $wrongSourcePath=Join-Path $tempRoot 'TASK-HANDOFF-WRONG-SOURCE.md';Write-Text $wrongSourcePath ($handoffText.Replace('# TASK-HANDOFF','# TASK-HANDOFF-WRONG-SOURCE').Replace('User decision handoff: sourceTaskId=SOURCE-1','User decision handoff: sourceTaskId=OTHER-SOURCE'))
    $result=& $taskChecker -TaskPath $wrongSourcePath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*USER_DECISION_HANDOFF*') 'user-decision-handoff-source-drift-deny'
    $missingDecisionInvalidatorPath=Join-Path $tempRoot 'TASK-HANDOFF-MISSING-INVALIDATOR.md';Write-Text $missingDecisionInvalidatorPath ($handoffText.Replace('# TASK-HANDOFF','# TASK-HANDOFF-MISSING-INVALIDATOR').Replace('|USER_DECISION_CHANGE',''))
    $result=& $taskChecker -TaskPath $missingDecisionInvalidatorPath -ObservedActualPath src/a.js -AvailableQuality FOCUSED_HIGH -AvailableTool shell,git @resourceObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*USER_DECISION_HANDOFF*') 'user-decision-handoff-user-change-invalidator-required'

    $head1='1111111111111111111111111111111111111111';$head2='2222222222222222222222222222222222222222';$head3='3333333333333333333333333333333333333333';$remoteAuthorizationIdentity='123|'+('E'*64);$compensationAuthorizationIdentity='124|'+('F'*64);$evidenceReceipt='collector=status-diff;scope=src/public.txt;exclude=assets/private'
    function Set-RemoteKey($Remote,[string]$TaskId='REMOTE-1',[string]$Candidate='candidate-1'){$Remote.idempotencyKey=Get-RemoteKey $TaskId $Candidate $Remote}
    $remoteA=[ordered]@{remoteId='origin';endpointFingerprint=('A'*64);action='PUSH_REF';refspec='refs/heads/main:refs/heads/main';authorizationLocator='tasks/active/remote-auth.json';authorizationIdentity=$remoteAuthorizationIdentity;expectedLocalHead=$head2;expectedRemoteHead=$head1;idempotencyKey='';attempted=$true;status='SUCCEEDED';observedHead=$head2;receipt='remote=origin;result=ok';errorClass='NONE'};Set-RemoteKey $remoteA
    $remoteB=[ordered]@{remoteId='mirror';endpointFingerprint=('B'*64);action='PUSH_REF';refspec='refs/heads/main:refs/heads/main';authorizationLocator='tasks/active/remote-auth.json';authorizationIdentity=$remoteAuthorizationIdentity;expectedLocalHead=$head2;expectedRemoteHead=$head1;idempotencyKey='';attempted=$true;status='FAILED';observedHead=$head1;receipt='';errorClass='REMOTE_REJECTED'};Set-RemoteKey $remoteB
    $transaction=[ordered]@{schemaVersion=1;transactionId='tx-1';transactionKind='PRIMARY';projectId='sample-project';taskId='REMOTE-1';candidate='candidate-1';gitCloser='closer-1';authorizationLocator='tasks/active/remote-auth.json';evidenceReceipt=$evidenceReceipt;protectedExcludes=@('assets/private');evidencePaths=@('src/public.txt');aggregateStatus='PARTIAL';remotes=@($remoteA,$remoteB)}
    $transactionPath=Join-Path $tempRoot 'remote-partial.json';Write-Json $transactionPath $transaction
    $remoteObserved=@{ObservedRemoteHead=@("origin=$head1","mirror=$head1");ObservedLocalHead=@("origin=$head2","mirror=$head2");ObservedEndpointFingerprint=@("origin=$('A'*64)","mirror=$('B'*64)");ObservedRefspec=@('origin=refs/heads/main:refs/heads/main','mirror=refs/heads/main:refs/heads/main');ObservedAuthorizationLocator=@('origin=tasks/active/remote-auth.json','mirror=tasks/active/remote-auth.json');ObservedAuthorizationIdentity=@("origin=$remoteAuthorizationIdentity","mirror=$remoteAuthorizationIdentity");ObservedCompensationAuthorizationLocator=@();ObservedCompensationAuthorizationIdentity=@();ObservedEvidencePath=@('src/public.txt');ObservedProtectedExclude=@('assets/private');ObservedEvidenceReceipt=$evidenceReceipt;RequiredProtectedExclude=@('assets/private')}
    $result=& $remoteChecker -TransactionPath $transactionPath @remoteObserved
    Assert-Test ($LASTEXITCODE-eq0-and$result-like'*aggregate=PARTIAL*') 'remote-partial-ledger'
    $headDriftObserved=$remoteObserved.Clone();$headDriftObserved['ObservedRemoteHead']=@("origin=$head3","mirror=$head1")
    $result=& $remoteChecker -TransactionPath $transactionPath @headDriftObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*REMOTE_HEAD_DRIFT*') 'remote-head-drift-deny'
    $localDriftObserved=$remoteObserved.Clone();$localDriftObserved['ObservedLocalHead']=@("origin=$head3","mirror=$head2")
    $result=& $remoteChecker -TransactionPath $transactionPath @localDriftObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*LOCAL_HEAD_DRIFT*') 'remote-local-head-drift-deny'
    $authorizationLocatorDriftObserved=$remoteObserved.Clone();$authorizationLocatorDriftObserved['ObservedAuthorizationLocator']=@('origin=tasks/active/other-auth.json','mirror=tasks/active/remote-auth.json')
    $result=& $remoteChecker -TransactionPath $transactionPath @authorizationLocatorDriftObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*AUTHORIZATION_LOCATOR_DRIFT*') 'remote-authorization-locator-drift-deny'
    $authorizationLocatorTypeDrift=Clone $transaction;$authorizationLocatorTypeDrift.remotes[0].authorizationLocator=7;Set-RemoteKey $authorizationLocatorTypeDrift.remotes[0];$authorizationLocatorTypeDriftPath=Join-Path $tempRoot 'remote-authorization-locator-type-drift.json';Write-Json $authorizationLocatorTypeDriftPath $authorizationLocatorTypeDrift
    $result=& $remoteChecker -TransactionPath $authorizationLocatorTypeDriftPath @remoteObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*REMOTE_FIELD_TYPE_authorizationLocator_STRING*') 'remote-authorization-locator-type-deny'
    $collisionA=Clone $transaction;$collisionA.taskId='A|B';$collisionA.candidate='C';foreach($remote in @($collisionA.remotes)){Set-RemoteKey $remote $collisionA.taskId $collisionA.candidate};$collisionB=Clone $transaction;$collisionB.taskId='A';$collisionB.candidate='B|C';foreach($remote in @($collisionB.remotes)){Set-RemoteKey $remote $collisionB.taskId $collisionB.candidate};$collisionAPath=Join-Path $tempRoot 'remote-key-collision-a.json';Write-Json $collisionAPath $collisionA
    $result=& $remoteChecker -TransactionPath $collisionAPath @remoteObserved
    Assert-Test ($LASTEXITCODE-eq0-and[string]$collisionA.remotes[0].idempotencyKey-cne[string]$collisionB.remotes[0].idempotencyKey) 'remote-idempotency-key-unambiguous'
    $retry=Clone $transaction;$retry.aggregateStatus='SUCCEEDED';$retry.remotes[0].attempted=$false;$retry.remotes[1].status='SUCCEEDED';$retry.remotes[1].observedHead=$head2;$retry.remotes[1].receipt='remote=mirror;result=ok';$retry.remotes[1].errorClass='NONE';$retryPath=Join-Path $tempRoot 'remote-retry.json';Write-Json $retryPath $retry
    $result=& $remoteChecker -TransactionPath $retryPath -PreviousLedgerPath $transactionPath @remoteObserved
    Assert-Test ($LASTEXITCODE-eq0-and$result-like'*aggregate=SUCCEEDED*') 'remote-retry-failed-only'
    $mutated=Clone $retry;$mutated.remotes[0].receipt='changed';$mutatedPath=Join-Path $tempRoot 'remote-mutated.json';Write-Json $mutatedPath $mutated
    $result=& $remoteChecker -TransactionPath $mutatedPath -PreviousLedgerPath $transactionPath @remoteObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*SUCCEEDED_REMOTE_MUTATED*') 'remote-succeeded-item-immutable'
    $drifted=Clone $retry;$drifted.remotes[1].endpointFingerprint=('C'*64);$driftedPath=Join-Path $tempRoot 'remote-drifted.json';Write-Json $driftedPath $drifted
    $result=& $remoteChecker -TransactionPath $driftedPath -PreviousLedgerPath $transactionPath @remoteObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*RETRY_REMOTE_CONFIG_DRIFT*') 'remote-fingerprint-refspec-drift-deny'
    $exposed=Clone $transaction;$exposed.evidencePaths=@('assets/private/secret.txt');$exposedPath=Join-Path $tempRoot 'remote-exposed.json';Write-Json $exposedPath $exposed
    $exposedObserved=$remoteObserved.Clone();$exposedObserved['ObservedEvidencePath']=@('assets/private/secret.txt')
    $result=& $remoteChecker -TransactionPath $exposedPath @exposedObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*PROTECTED_PATH_EXPOSED*') 'remote-protected-exclude-enforced'
    $ancestor=Clone $transaction;$ancestor.evidencePaths=@('assets');$ancestorPath=Join-Path $tempRoot 'remote-ancestor-exposed.json';Write-Json $ancestorPath $ancestor
    $ancestorObserved=$remoteObserved.Clone();$ancestorObserved['ObservedEvidencePath']=@('assets')
    $result=& $remoteChecker -TransactionPath $ancestorPath @ancestorObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*PROTECTED_PATH_EXPOSED*') 'remote-protected-descendant-covered-by-ancestor-deny'
    $receiptDriftObserved=$remoteObserved.Clone();$receiptDriftObserved['ObservedEvidenceReceipt']='collector=other'
    $result=& $remoteChecker -TransactionPath $transactionPath @receiptDriftObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*EVIDENCE_RECEIPT_DRIFT*') 'remote-evidence-receipt-bound'
    $comp=Clone $transaction;$comp.transactionId='tx-comp';$comp.transactionKind='COMPENSATION';$comp|Add-Member -NotePropertyName sourceTransactionId -NotePropertyValue 'tx-1';$comp.remotes=@($comp.remotes[0]);$comp.remotes[0].action='COMPENSATE_REF';$comp.remotes[0].status='FAILED';$comp.remotes[0].observedHead=$head2;$comp.remotes[0].receipt='';$comp.remotes[0].errorClass='COMPENSATION_REJECTED';$comp.remotes[0]|Add-Member -NotePropertyName originalReceipt -NotePropertyValue 'remote=origin;result=ok';Set-RemoteKey $comp.remotes[0];$comp.aggregateStatus='FAILED';$compMissingPath=Join-Path $tempRoot 'remote-compensation-missing-auth.json';Write-Json $compMissingPath $comp
    $compObserved=@{ObservedRemoteHead=@("origin=$head1");ObservedLocalHead=@("origin=$head2");ObservedEndpointFingerprint=@("origin=$('A'*64)");ObservedRefspec=@('origin=refs/heads/main:refs/heads/main');ObservedAuthorizationLocator=@('origin=tasks/active/remote-auth.json');ObservedAuthorizationIdentity=@("origin=$remoteAuthorizationIdentity");ObservedCompensationAuthorizationLocator=@();ObservedCompensationAuthorizationIdentity=@();ObservedEvidencePath=@('src/public.txt');ObservedProtectedExclude=@('assets/private');ObservedEvidenceReceipt=$evidenceReceipt;RequiredProtectedExclude=@('assets/private')}
    $result=& $remoteChecker -TransactionPath $compMissingPath @compObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*COMPENSATION*') 'remote-compensation-independent-authorization-required'
    $comp.remotes[0]|Add-Member -NotePropertyName compensationAuthorizationLocator -NotePropertyValue 'tasks/active/compensation-auth.json';$comp.remotes[0]|Add-Member -NotePropertyName compensationAuthorizationIdentity -NotePropertyValue $compensationAuthorizationIdentity;Set-RemoteKey $comp.remotes[0];$compPath=Join-Path $tempRoot 'remote-compensation.json';Write-Json $compPath $comp
    $compObserved['ObservedCompensationAuthorizationLocator']=@('origin=tasks/active/compensation-auth.json')
    $compObserved['ObservedCompensationAuthorizationIdentity']=@("origin=$compensationAuthorizationIdentity")
    $result=& $remoteChecker -TransactionPath $compPath @compObserved
    Assert-Test ($LASTEXITCODE-eq0) 'remote-compensation-failure-preserves-original-receipt'
    $compensationLocatorDriftObserved=$compObserved.Clone();$compensationLocatorDriftObserved['ObservedCompensationAuthorizationLocator']=@('origin=tasks/active/other-compensation-auth.json')
    $result=& $remoteChecker -TransactionPath $compPath @compensationLocatorDriftObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*COMPENSATION_AUTHORIZATION_LOCATOR_DRIFT*') 'remote-compensation-authorization-locator-drift-deny'
    $compRetry=Clone $comp;$compRetry.remotes[0].compensationAuthorizationLocator='tasks/active/compensation-auth-2.json';$compRetry.remotes[0].compensationAuthorizationIdentity='125|'+('D'*64);Set-RemoteKey $compRetry.remotes[0];$compRetryPath=Join-Path $tempRoot 'remote-compensation-retry-auth-drift.json';Write-Json $compRetryPath $compRetry;$compRetryObserved=$compObserved.Clone();$compRetryObserved['ObservedCompensationAuthorizationLocator']=@('origin=tasks/active/compensation-auth-2.json');$compRetryObserved['ObservedCompensationAuthorizationIdentity']=@("origin=$($compRetry.remotes[0].compensationAuthorizationIdentity)")
    $result=& $remoteChecker -TransactionPath $compRetryPath -PreviousLedgerPath $compPath @compRetryObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*RETRY_REMOTE_CONFIG_DRIFT*') 'remote-compensation-authorization-retry-drift-deny'
    $numericSource=Clone $comp;$numericSource.sourceTransactionId=7;$numericSourcePath=Join-Path $tempRoot 'remote-compensation-numeric-source.json';Write-Json $numericSourcePath $numericSource
    $result=& $remoteChecker -TransactionPath $numericSourcePath @compObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*COMPENSATION_SOURCE_INVALID*') 'remote-compensation-source-json-type-deny'
    $numericOriginal=Clone $comp;$numericOriginal.remotes[0].originalReceipt=7;$numericOriginalPath=Join-Path $tempRoot 'remote-compensation-numeric-original-receipt.json';Write-Json $numericOriginalPath $numericOriginal
    $result=& $remoteChecker -TransactionPath $numericOriginalPath @compObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*REMOTE_FIELD_TYPE_originalReceipt_STRING*') 'remote-original-receipt-json-type-deny'
    $primaryComp=Clone $transaction;$primaryComp.remotes[0].action='COMPENSATE_REF';Set-RemoteKey $primaryComp.remotes[0];$primaryCompPath=Join-Path $tempRoot 'remote-primary-compensate.json';Write-Json $primaryCompPath $primaryComp
    $result=& $remoteChecker -TransactionPath $primaryCompPath @remoteObserved
    Assert-Test ($LASTEXITCODE-eq2-and$result-like'*PRIMARY_COMPENSATION_ACTION_FORBIDDEN*') 'remote-primary-compensation-action-deny'

    if(-not$SkipRootMigration){
        $isolated=Join-Path $tempRoot 'workspace';New-Item -ItemType Directory -Path (Join-Path $isolated 'framework\versions') -Force|Out-Null;New-Item -ItemType Directory -Path (Join-Path $isolated 'scripts') -Force|Out-Null
        foreach($source in @('1.4.1','1.5.0','1.5.1','1.5.2')){Copy-Item -LiteralPath (Join-Path $workspaceRoot "framework\versions\$source") -Destination (Join-Path $isolated "framework\versions\$source") -Recurse}
        Copy-Item -LiteralPath (Join-Path $workspaceRoot 'framework\CURRENT') -Destination (Join-Path $isolated 'framework\CURRENT')
        Copy-Item -LiteralPath $versionRoot -Destination (Join-Path $isolated 'framework\versions\1.6.0') -Recurse
        Copy-Item -LiteralPath (Join-Path $rootScripts 'register-project.ps1') -Destination (Join-Path $isolated 'scripts\register-project.ps1')
        Copy-Item -LiteralPath (Join-Path $rootScripts 'upgrade-project.ps1') -Destination (Join-Path $isolated 'scripts\upgrade-project.ps1')
        $candidateRegister=Join-Path $isolated 'scripts\register-project.ps1';$candidateUpgrade=Join-Path $isolated 'scripts\upgrade-project.ps1';$liveRegister=Join-Path $workspaceRoot 'scripts\register-project.ps1'
        $newRepo=Join-Path $tempRoot 'register-160';New-TestRepo $newRepo
        $denied=Invoke-PowerShellCapture @('-File',$candidateRegister,'-ProjectId','register-160','-DisplayName','Register 160','-RepositoryPath',$newRepo,'-ControllerId','controller-new','-FrameworkVersion','1.6.0','-WorkspaceRoot',$isolated,'-Apply');Assert-Test ($denied.ExitCode-ne0-and($denied.Output-join' ')-like'*not consumable*') 'register-draft-default-deny'
        $createdOutput=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $candidateRegister -ProjectId register-160 -DisplayName 'Register 160' -RepositoryPath $newRepo -ControllerId controller-new -FrameworkVersion 1.6.0 -WorkspaceRoot $isolated -AllowDraftCandidate -Apply 2>&1);$createdCode=$LASTEXITCODE
        $createdController=Join-Path $newRepo '.ai-workspace\controller.json';$createdProject=(Get-Content -Raw -Encoding UTF8 (Join-Path $newRepo '.ai-workspace\project.json'))|ConvertFrom-Json;Assert-Test ($createdCode-eq0-and(Test-Path $createdController)-and[int]$createdProject.schemaVersion-eq3-and[string]$createdProject.frameworkVersion-ceq'1.6.0'-and(Identity $createdController)-match'^\d+\|[A-F0-9]{64}$') 'register-controller-epoch1'
        Write-Text $createdController (Canonical-Controller 'register-160' 'controller-rotated' 2)
        $rotatedRepeat=Invoke-PowerShellCapture @('-File',$candidateRegister,'-ProjectId','register-160','-DisplayName','Register 160','-RepositoryPath',$newRepo,'-FrameworkVersion','1.6.0','-WorkspaceRoot',$isolated,'-AllowDraftCandidate','-Apply')
        Assert-Test ($rotatedRepeat.ExitCode-eq0-and($rotatedRepeat.Output-join' ')-like'*ALREADY_REGISTERED*') 'register-rotated-controller-epoch2-already-registered'
        $rotatedMismatch=Invoke-PowerShellCapture @('-File',$candidateRegister,'-ProjectId','register-160','-DisplayName','Register 160','-RepositoryPath',$newRepo,'-ControllerId','controller-new','-FrameworkVersion','1.6.0','-WorkspaceRoot',$isolated,'-AllowDraftCandidate','-Apply')
        Assert-Test ($rotatedMismatch.ExitCode-ne0-and($rotatedMismatch.Output-join' ')-like'*controller identity conflicts*') 'register-explicit-stale-controller-deny'

        $currentRepo=Join-Path $tempRoot 'register-current';New-TestRepo $currentRepo
        $currentCreate=Invoke-PowerShellCapture @('-File',$candidateRegister,'-ProjectId','register-current','-DisplayName','Register Current','-RepositoryPath',$currentRepo,'-WorkspaceRoot',$isolated,'-Apply');$currentConfig=(Get-Content -Raw -Encoding UTF8 (Join-Path $currentRepo '.ai-workspace\project.json'))|ConvertFrom-Json
        $currentRepeat=Invoke-PowerShellCapture @('-File',$candidateRegister,'-ProjectId','register-current','-DisplayName','Register Current','-RepositoryPath',$currentRepo,'-WorkspaceRoot',$isolated,'-Apply');Assert-Test ($currentCreate.ExitCode-eq0-and$currentRepeat.ExitCode-eq0-and[string]$currentConfig.frameworkVersion-ceq((Get-Content -Raw -Encoding UTF8 (Join-Path $isolated 'framework\CURRENT')).Trim())-and[int]$currentConfig.schemaVersion-eq2-and-not(Test-Path (Join-Path $currentRepo '.ai-workspace\controller.json'))-and($currentRepeat.Output-join' ')-like'*ALREADY_REGISTERED*') 'register-current-schema2-compatible'
        $stableRepo=Join-Path $tempRoot 'register-152';New-TestRepo $stableRepo
        $stableCreate=Invoke-PowerShellCapture @('-File',$candidateRegister,'-ProjectId','register-152','-DisplayName','Register 152','-RepositoryPath',$stableRepo,'-FrameworkVersion','1.5.2','-WorkspaceRoot',$isolated,'-Apply');$stableConfig=(Get-Content -Raw -Encoding UTF8 (Join-Path $stableRepo '.ai-workspace\project.json'))|ConvertFrom-Json;Assert-Test ($stableCreate.ExitCode-eq0-and[string]$stableConfig.frameworkVersion-ceq'1.5.2'-and[int]$stableConfig.schemaVersion-eq2-and-not(Test-Path (Join-Path $stableRepo '.ai-workspace\controller.json'))) 'register-explicit-152-schema2-compatible'
        $centralRepo=Join-Path $tempRoot 'central-legacy-repo';New-TestRepo $centralRepo;New-Item -ItemType Directory -Path (Join-Path $isolated 'projects\central-legacy') -Force|Out-Null
        $centralDenied=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','central-legacy','-RepositoryPath',$centralRepo,'-ToVersion','1.6.0','-ControllerId','controller-central','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated)
        Assert-Test ($centralDenied.ExitCode-ne0-and($centralDenied.Output-join' ')-like'*REPO_LOCAL_CONTROL_MISSING*') 'upgrade-central-legacy-topology-explicitly-denied'

        foreach($source in @('1.4.1','1.5.0','1.5.1','1.5.2')){
            $repo=Join-Path $tempRoot ("upgrade-"+$source.Replace('.',''));New-TestRepo $repo
            $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveRegister -ProjectId ("upgrade-"+$source.Replace('.','')) -DisplayName 'Upgrade Fixture' -RepositoryPath $repo -FrameworkVersion $source -WorkspaceRoot $isolated -Apply
            $control=Join-Path $repo '.ai-workspace';$legacy=Join-Path $control 'tasks\active\legacy-controller.json';$domainKeep=Join-Path $control 'tasks\active\domain-owner.json';Write-Json $legacy ([ordered]@{issuerRole='PROJECT_CONTROLLER';lifecycle='ACTIVE'});Write-Json $domainKeep ([ordered]@{issuerRole='DOMAIN_OWNER';lifecycle='ACTIVE'});$domainIdentity=Identity $domainKeep
            $null=& git -C $repo add .ai-workspace;$null=& git -C $repo commit --quiet -m baseline;$headBefore=(& git -C $repo rev-parse HEAD).Trim()
            if($source-ceq'1.4.1'){$domainDenied=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId',("upgrade-"+$source.Replace('.','')),'-RepositoryPath',$repo,'-ToVersion','1.6.0','-ControllerId','controller-upgrade','-LegacyControllerAuthorizationLocator','tasks/active/domain-owner.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated);Assert-Test ($domainDenied.ExitCode-ne0-and($domainDenied.Output-join' ')-like'*DOMAIN_OWNER_REVOCATION_FORBIDDEN*') 'upgrade-domain-owner-revocation-input-deny'}
            $projectId="upgrade-"+$source.Replace('.','');$preview=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $candidateUpgrade -ProjectId $projectId -RepositoryPath $repo -ToVersion 1.6.0 -ControllerId controller-upgrade -LegacyControllerAuthorizationLocator tasks/active/legacy-controller.json -LegacyControllerInventoryConfirmed -AllowDraftCandidate -WorkspaceRoot $isolated 2>&1);Assert-Test ($LASTEXITCODE-eq0-and($preview-join' ')-like'PREVIEW*') "upgrade-$source-preview"
            $apply=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $candidateUpgrade -ProjectId $projectId -RepositoryPath $repo -ToVersion 1.6.0 -ControllerId controller-upgrade -LegacyControllerAuthorizationLocator tasks/active/legacy-controller.json -LegacyControllerInventoryConfirmed -AllowDraftCandidate -WorkspaceRoot $isolated -Apply 2>&1);$applyCode=$LASTEXITCODE
            $newConfig=(Get-Content -Raw -Encoding UTF8 (Join-Path $control 'project.json'))|ConvertFrom-Json;$newController=(Get-Content -Raw -Encoding UTF8 (Join-Path $control 'controller.json'))|ConvertFrom-Json;$ledger=(Get-Content -Raw -Encoding UTF8 (Join-Path $control 'tasks\archive\FRAMEWORK-1.6.0-CONTROLLER-REVOCATION.json'))|ConvertFrom-Json;$headAfter=(& git -C $repo rev-parse HEAD).Trim();$cached=@(& git -C $repo diff --cached --name-only)
            Assert-Test ($applyCode-eq0-and[string]$newConfig.frameworkVersion-ceq'1.6.0'-and[int]$newConfig.schemaVersion-eq3-and[string]$newController.controllerId-ceq'controller-upgrade'-and[int]$newController.controllerEpoch-eq1-and@($ledger.legacyProjectControllerPackages).Count-eq1-and[string]$ledger.domainOwnerPackages-ceq'PRESERVE_BY_ORIGINAL_INVALIDATORS'-and(Identity $domainKeep)-ceq$domainIdentity-and$headBefore-ceq$headAfter-and$cached.Count-eq0) "upgrade-$source-controller-migration"
            $repeatUpgrade=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId',$projectId,'-RepositoryPath',$repo,'-ToVersion','1.6.0','-ControllerId','controller-upgrade','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')
            Assert-Test ($repeatUpgrade.ExitCode-eq0-and($repeatUpgrade.Output-join' ')-like'*ALREADY_UPGRADED*') "upgrade-$source-idempotent-repeat"
            if($source-ceq'1.5.2'){
                $controllerPath=Join-Path $control 'controller.json';Write-Text $controllerPath (Canonical-Controller $projectId 'controller-rotated' 2)
                $rotatedRepeat=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId',$projectId,'-RepositoryPath',$repo,'-ToVersion','1.6.0','-ControllerId','controller-rotated','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')
                Assert-Test ($rotatedRepeat.ExitCode-eq0-and($rotatedRepeat.Output-join' ')-like'*ALREADY_UPGRADED*epoch=2*') 'upgrade-rotated-current-controller-idempotent-repeat'
                $ledgerPath=Join-Path $control 'tasks\archive\FRAMEWORK-1.6.0-CONTROLLER-REVOCATION.json';$tamperedLedger=(Get-Content -Raw -Encoding UTF8 $ledgerPath)|ConvertFrom-Json;$tamperedLedger|Add-Member -NotePropertyName unexpected -NotePropertyValue 'FORBIDDEN';Write-Json $ledgerPath $tamperedLedger
                $tamperedRepeat=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId',$projectId,'-RepositoryPath',$repo,'-ToVersion','1.6.0','-ControllerId','controller-rotated','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')
                Assert-Test ($tamperedRepeat.ExitCode-ne0-and($tamperedRepeat.Output-join' ')-like'*ALREADY_UPGRADED_REVOCATION_DRIFT*') 'upgrade-tampered-revocation-ledger-deny'
                $tamperedLedger.PSObject.Properties.Remove('unexpected');$tamperedLedger.legacyProjectControllerPackages[0].identity='999|'+('A'*64);Write-Json $ledgerPath $tamperedLedger
                $identityTamperedRepeat=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId',$projectId,'-RepositoryPath',$repo,'-ToVersion','1.6.0','-ControllerId','controller-rotated','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')
                Assert-Test ($identityTamperedRepeat.ExitCode-ne0-and($identityTamperedRepeat.Output-join' ')-like'*ALREADY_UPGRADED_REVOCATION_DRIFT*') 'upgrade-canonical-valid-legacy-identity-tamper-deny'
                Write-Json $ledgerPath $ledger;$movedLegacy=$legacy+'.moved';Move-Item -LiteralPath $legacy -Destination $movedLegacy
                $movedCarrierRepeat=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId',$projectId,'-RepositoryPath',$repo,'-ToVersion','1.6.0','-ControllerId','controller-rotated','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')
                Assert-Test ($movedCarrierRepeat.ExitCode-ne0-and($movedCarrierRepeat.Output-join' ')-like'*ALREADY_UPGRADED_REVOCATION_DRIFT*') 'upgrade-legacy-carrier-missing-or-moved-deny'
            }
        }

        $legacyInitialDriftRepo=Join-Path $tempRoot 'upgrade-legacy-inventory-drift';New-TestRepo $legacyInitialDriftRepo
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveRegister -ProjectId upgrade-legacy-inventory-drift -DisplayName 'Legacy Inventory Drift Fixture' -RepositoryPath $legacyInitialDriftRepo -FrameworkVersion 1.5.2 -WorkspaceRoot $isolated -Apply
        $legacyInitialControl=Join-Path $legacyInitialDriftRepo '.ai-workspace';$legacyInitialPath=Join-Path $legacyInitialControl 'tasks\active\legacy-controller.json';Write-Json $legacyInitialPath ([ordered]@{issuerRole='PROJECT_CONTROLLER';lifecycle='ACTIVE'});$null=& git -C $legacyInitialDriftRepo add .ai-workspace;$null=& git -C $legacyInitialDriftRepo commit --quiet -m baseline;$legacyInitialBefore=Identity $legacyInitialPath
        $env:AI_WORKSPACE_FRAMEWORK_TEST_MODE='1';$env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_LEGACY_AFTER_INVENTORY='1'
        try{$legacyInitialDrift=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','upgrade-legacy-inventory-drift','-RepositoryPath',$legacyInitialDriftRepo,'-ToVersion','1.6.0','-ControllerId','controller-legacy-initial','-LegacyControllerAuthorizationLocator','tasks/active/legacy-controller.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')}
        finally{Remove-Item Env:AI_WORKSPACE_FRAMEWORK_TEST_MODE -ErrorAction SilentlyContinue;Remove-Item Env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_LEGACY_AFTER_INVENTORY -ErrorAction SilentlyContinue}
        $legacyInitialConfig=(Get-Content -Raw -Encoding UTF8 (Join-Path $legacyInitialControl 'project.json'))|ConvertFrom-Json
        Assert-Test ($legacyInitialDrift.ExitCode-ne0-and($legacyInitialDrift.Output-join' ')-like'*LEGACY_AUTHORIZATION_PREIMAGE_DRIFT*'-and(Identity $legacyInitialPath)-cne$legacyInitialBefore-and[string]$legacyInitialConfig.frameworkVersion-ceq'1.5.2'-and-not(Test-Path (Join-Path $legacyInitialControl '.framework-upgrade-transaction'))-and-not(Test-Path (Join-Path $legacyInitialControl 'controller.json'))) 'upgrade-legacy-inventory-drift-preserved-and-stopped'

        $legacyTransactionDriftRepo=Join-Path $tempRoot 'upgrade-legacy-transaction-drift';New-TestRepo $legacyTransactionDriftRepo
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveRegister -ProjectId upgrade-legacy-transaction-drift -DisplayName 'Legacy Transaction Drift Fixture' -RepositoryPath $legacyTransactionDriftRepo -FrameworkVersion 1.5.2 -WorkspaceRoot $isolated -Apply
        $legacyTransactionControl=Join-Path $legacyTransactionDriftRepo '.ai-workspace';$legacyTransactionPath=Join-Path $legacyTransactionControl 'tasks\active\legacy-controller.json';Write-Json $legacyTransactionPath ([ordered]@{issuerRole='PROJECT_CONTROLLER';lifecycle='ACTIVE'});$null=& git -C $legacyTransactionDriftRepo add .ai-workspace;$null=& git -C $legacyTransactionDriftRepo commit --quiet -m baseline;$legacyTransactionBefore=Identity $legacyTransactionPath
        $env:AI_WORKSPACE_FRAMEWORK_TEST_MODE='1';$env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_LEGACY_BEFORE_REVOCATION='1'
        try{$legacyTransactionDrift=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','upgrade-legacy-transaction-drift','-RepositoryPath',$legacyTransactionDriftRepo,'-ToVersion','1.6.0','-ControllerId','controller-legacy-transaction','-LegacyControllerAuthorizationLocator','tasks/active/legacy-controller.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')}
        finally{Remove-Item Env:AI_WORKSPACE_FRAMEWORK_TEST_MODE -ErrorAction SilentlyContinue;Remove-Item Env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_LEGACY_BEFORE_REVOCATION -ErrorAction SilentlyContinue}
        $legacyTransactionConfig=(Get-Content -Raw -Encoding UTF8 (Join-Path $legacyTransactionControl 'project.json'))|ConvertFrom-Json
        Assert-Test ($legacyTransactionDrift.ExitCode-ne0-and($legacyTransactionDrift.Output-join' ')-like'*LEGACY_AUTHORIZATION_PREIMAGE_DRIFT*'-and(Identity $legacyTransactionPath)-cne$legacyTransactionBefore-and[string]$legacyTransactionConfig.frameworkVersion-ceq'1.5.2'-and-not(Test-Path (Join-Path $legacyTransactionControl '.framework-upgrade-transaction'))-and-not(Test-Path (Join-Path $legacyTransactionControl 'controller.json'))-and-not(Test-Path (Join-Path $legacyTransactionControl 'tasks\archive\FRAMEWORK-1.6.0-CONTROLLER-REVOCATION.json'))) 'upgrade-legacy-transaction-drift-recovered-and-stopped'

        $interruptRepo=Join-Path $tempRoot 'upgrade-interrupt';New-TestRepo $interruptRepo
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveRegister -ProjectId upgrade-interrupt -DisplayName 'Interrupt Fixture' -RepositoryPath $interruptRepo -FrameworkVersion 1.5.2 -WorkspaceRoot $isolated -Apply
        $interruptControl=Join-Path $interruptRepo '.ai-workspace';$interruptLegacy=Join-Path $interruptControl 'tasks\active\legacy-controller.json';Write-Json $interruptLegacy ([ordered]@{issuerRole='PROJECT_CONTROLLER';lifecycle='ACTIVE'});$null=& git -C $interruptRepo add .ai-workspace;$null=& git -C $interruptRepo commit --quiet -m baseline
        $env:AI_WORKSPACE_FRAMEWORK_TEST_MODE='1';$env:AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_CONTROLLER_CREATE='1'
        try{$interrupted=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','upgrade-interrupt','-RepositoryPath',$interruptRepo,'-ToVersion','1.6.0','-ControllerId','controller-interrupt','-LegacyControllerAuthorizationLocator','tasks/active/legacy-controller.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')}
        finally{Remove-Item Env:AI_WORKSPACE_FRAMEWORK_TEST_MODE -ErrorAction SilentlyContinue;Remove-Item Env:AI_WORKSPACE_UPGRADE_TEST_INTERRUPT_AFTER_CONTROLLER_CREATE -ErrorAction SilentlyContinue}
        Assert-Test ($interrupted.ExitCode-ne0-and(Test-Path (Join-Path $interruptControl '.framework-upgrade-transaction'))-and(Test-Path (Join-Path $interruptControl 'controller.json'))-and-not(Test-Path (Join-Path $interruptControl 'tasks\archive\FRAMEWORK-1.6.0-CONTROLLER-REVOCATION.json'))) 'upgrade-interruption-material-preserved'
        $recovery=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','upgrade-interrupt','-RepositoryPath',$interruptRepo,'-ToVersion','1.6.0','-ControllerId','controller-interrupt','-LegacyControllerAuthorizationLocator','tasks/active/legacy-controller.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')
        $recoveredConfig=(Get-Content -Raw -Encoding UTF8 (Join-Path $interruptControl 'project.json'))|ConvertFrom-Json
        Assert-Test ($recovery.ExitCode-eq0-and($recovery.Output-join' ')-like'*RECOVERED_ROLLED_BACK*'-and[string]$recoveredConfig.frameworkVersion-ceq'1.5.2'-and-not(Test-Path (Join-Path $interruptControl 'controller.json'))-and-not(Test-Path (Join-Path $interruptControl '.framework-upgrade-transaction'))) 'upgrade-interruption-recover-old-set'
        $retryApply=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','upgrade-interrupt','-RepositoryPath',$interruptRepo,'-ToVersion','1.6.0','-ControllerId','controller-interrupt','-LegacyControllerAuthorizationLocator','tasks/active/legacy-controller.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')
        $retryConfig=(Get-Content -Raw -Encoding UTF8 (Join-Path $interruptControl 'project.json'))|ConvertFrom-Json
        Assert-Test ($retryApply.ExitCode-eq0-and[string]$retryConfig.frameworkVersion-ceq'1.6.0'-and(Test-Path (Join-Path $interruptControl 'controller.json'))-and(Test-Path (Join-Path $interruptControl 'tasks\archive\FRAMEWORK-1.6.0-CONTROLLER-REVOCATION.json'))) 'upgrade-retry-after-recovery-completes'

        $initialDriftRepo=Join-Path $tempRoot 'upgrade-initial-preimage-drift';New-TestRepo $initialDriftRepo
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveRegister -ProjectId upgrade-initial-preimage-drift -DisplayName 'Initial Preimage Drift Fixture' -RepositoryPath $initialDriftRepo -FrameworkVersion 1.5.2 -WorkspaceRoot $isolated -Apply
        $initialDriftControl=Join-Path $initialDriftRepo '.ai-workspace';$initialDriftLegacy=Join-Path $initialDriftControl 'tasks\active\legacy-controller.json';Write-Json $initialDriftLegacy ([ordered]@{issuerRole='PROJECT_CONTROLLER';lifecycle='ACTIVE'});$null=& git -C $initialDriftRepo add .ai-workspace;$null=& git -C $initialDriftRepo commit --quiet -m baseline;$initialDriftProject=Join-Path $initialDriftControl 'project.json';$initialDriftOldIdentity=Identity $initialDriftProject
        $env:AI_WORKSPACE_FRAMEWORK_TEST_MODE='1';$env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_PROJECT_AFTER_INITIAL_READ='1'
        try{$initialPreimageDrift=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','upgrade-initial-preimage-drift','-RepositoryPath',$initialDriftRepo,'-ToVersion','1.6.0','-ControllerId','controller-initial-drift','-LegacyControllerAuthorizationLocator','tasks/active/legacy-controller.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')}
        finally{Remove-Item Env:AI_WORKSPACE_FRAMEWORK_TEST_MODE -ErrorAction SilentlyContinue;Remove-Item Env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_PROJECT_AFTER_INITIAL_READ -ErrorAction SilentlyContinue}
        Assert-Test ($initialPreimageDrift.ExitCode-ne0-and($initialPreimageDrift.Output-join' ')-like'*INITIAL_PREIMAGE_DRIFT*'-and(Identity $initialDriftProject)-cne$initialDriftOldIdentity-and-not(Test-Path (Join-Path $initialDriftControl '.framework-upgrade-transaction'))-and-not(Test-Path (Join-Path $initialDriftControl 'controller.json'))) 'upgrade-initial-read-to-copy-drift-preserved-and-stopped'

        $driftRepo=Join-Path $tempRoot 'upgrade-preimage-drift';New-TestRepo $driftRepo
        $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $liveRegister -ProjectId upgrade-preimage-drift -DisplayName 'Preimage Drift Fixture' -RepositoryPath $driftRepo -FrameworkVersion 1.5.2 -WorkspaceRoot $isolated -Apply
        $driftControl=Join-Path $driftRepo '.ai-workspace';$driftLegacy=Join-Path $driftControl 'tasks\active\legacy-controller.json';Write-Json $driftLegacy ([ordered]@{issuerRole='PROJECT_CONTROLLER';lifecycle='ACTIVE'});$null=& git -C $driftRepo add .ai-workspace;$null=& git -C $driftRepo commit --quiet -m baseline;$driftProject=Join-Path $driftControl 'project.json';$driftOldIdentity=Identity $driftProject
        $env:AI_WORKSPACE_FRAMEWORK_TEST_MODE='1';$env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_PROJECT_AFTER_PREPARE='1'
        try{$preimageDrift=Invoke-PowerShellCapture @('-File',$candidateUpgrade,'-ProjectId','upgrade-preimage-drift','-RepositoryPath',$driftRepo,'-ToVersion','1.6.0','-ControllerId','controller-drift','-LegacyControllerAuthorizationLocator','tasks/active/legacy-controller.json','-LegacyControllerInventoryConfirmed','-AllowDraftCandidate','-WorkspaceRoot',$isolated,'-Apply')}
        finally{Remove-Item Env:AI_WORKSPACE_FRAMEWORK_TEST_MODE -ErrorAction SilentlyContinue;Remove-Item Env:AI_WORKSPACE_UPGRADE_TEST_MUTATE_PROJECT_AFTER_PREPARE -ErrorAction SilentlyContinue}
        Assert-Test ($preimageDrift.ExitCode-ne0-and($preimageDrift.Output-join' ')-like'*REPLACE_PREIMAGE_DRIFT*'-and(Identity $driftProject)-cne$driftOldIdentity-and(Test-Path (Join-Path $driftControl '.framework-upgrade-transaction'))-and-not(Test-Path (Join-Path $driftControl 'controller.json'))) 'upgrade-live-preimage-drift-preserved-and-stopped'
    }
}
finally{
    if(Test-Path -LiteralPath $tempRoot){$resolved=[IO.Path]::GetFullPath($tempRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());if(-not$resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-or(Split-Path -Leaf $resolved)-notmatch'^framework-160-acg-[0-9a-f]{32}$'){throw'REFUSE_TEMP_CLEANUP'};foreach($file in Get-ChildItem -LiteralPath $resolved -File -Recurse -Force -ErrorAction SilentlyContinue){$file.IsReadOnly=$false};[IO.Directory]::Delete($resolved,$true)}
}

$baselineAfter=Get-TreeCanonical $baselineRoot
Assert-Test ($baselineAfter.Count-eq$baseline.Count-and$baselineAfter.Total-eq$baseline.Total-and$baselineAfter.Canonical-ceq$baseline.Canonical) 'baseline-source-zero-drift-after-tests'
Assert-Test ((Identity (Join-Path $workspaceRoot 'scripts\register-project.ps1'))-ceq'22358|6AE4FD80FB25653FA4606961EED8CD1B652F4A791E9D445C04E9B473E83CC6B1'-and(Identity (Join-Path $workspaceRoot 'scripts\upgrade-project.ps1'))-ceq'48080|679F4D0B2519EA4777566ED5A48F89F6AD0451DB489EFDAF6A5C6BB8F9F43C9B') 'live-root-scripts-zero-drift-after-tests'
Write-Output "RESULT $passCount/$passCount passed|scope=A-C+G|lifecycle=DRAFT_NOT_CONSUMABLE"
