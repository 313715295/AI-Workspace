[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$script:passed=0;$script:pwshExecutable=[Environment]::ProcessPath;$utf8=[Text.UTF8Encoding]::new($false)
function Assert-True([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "ASSERT_FAIL|$Name" }
    $script:passed++
    Write-Output "PASS|$Name"
}


function Write-Utf8([string]$Path,[string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $value = $Text.Replace("`r`n","`n").Replace("`r","`n")
    if (-not $value.EndsWith("`n")) { $value += "`n" }
    [IO.File]::WriteAllText($Path,$value,$utf8)
}


function Invoke-Ps([string]$Script,[string[]]$Arguments,[string]$WorkingDirectory='') {
    $effectiveArguments=@($Arguments)
    if ([IO.Path]::GetFileName($Script) -ceq 'check-authorization.ps1' -and '-TaskPath' -cnotin $effectiveArguments -and -not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $packageIndex=[Array]::IndexOf($effectiveArguments,'-PackagePath')
        if($packageIndex-ge0-and$packageIndex+1-lt$effectiveArguments.Count){
            $packageFixture=Get-Content -LiteralPath $effectiveArguments[$packageIndex+1] -Raw -Encoding utf8|ConvertFrom-Json
            $taskRelative='.ai-workspace/tasks/active/'+[string]$packageFixture.taskId+'.md'
            $taskFull=Join-Path $WorkingDirectory $taskRelative
            $effectiveArguments+=@('-TaskPath',$taskRelative,'-ExpectedTaskIdentity',(Get-Identity $taskFull))
        }
    }
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = @(& $script:pwshExecutable -NoProfile -NonInteractive -File $Script @effectiveArguments 2>&1 | ForEach-Object { [string]$_ }); $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
        return [pscustomobject]@{ Code=$code; Output=$output; Text=($output -join "`n") }
    } finally {
        if ($WorkingDirectory) { Pop-Location }
    }
}


function Invoke-WorkflowCase([string]$Resolver,[string]$Root,[string]$Name,$InputObject) {
    $path = Join-Path $Root ('workflow-' + $Name + '.json')
    Write-Utf8 $path ($InputObject | ConvertTo-Json -Depth 12)
    $run = Invoke-Ps $Resolver @('-InputPath',$path,'-AsJson')
    $value = $null
    if ($run.Code -eq 0 -and $run.Output.Count -gt 0) {
        try { $value = @($run.Output)[-1] | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{ Run=$run; Value=$value }
}


function Invoke-WorkflowRawCase([string]$Resolver,[string]$Root,[string]$Name,[string]$RawInput) {
    $path = Join-Path $Root ('workflow-' + $Name + '.json')
    Write-Utf8 $path $RawInput
    return Invoke-Ps $Resolver @('-InputPath',$path,'-AsJson')
}

$candidateRoot=Split-Path -Parent $PSScriptRoot
$maintenanceOverlayRoot=Join-Path ([IO.Path]::GetFullPath((Join-Path $candidateRoot '../../..'))) 'framework/maintenance-overlay'
$workflowEntryDocuments = @((Join-Path $candidateRoot 'TASK_AND_SCOPE.md'),(Join-Path $candidateRoot 'HOST_CODEX.md'),(Join-Path $candidateRoot 'PROMPTS.md'),(Join-Path $candidateRoot 'project-starter/BOOTSTRAP.md'),(Join-Path $maintenanceOverlayRoot 'BOOTSTRAP.md'))
foreach ($entryPath in $workflowEntryDocuments) {
    $entryText = Get-Content -LiteralPath $entryPath -Raw -Encoding utf8
    Assert-True ($entryText.Contains('WORKFLOW_ROUTE_RESOLVE') -and $entryText.Contains('TOOLCHAIN.json') -and $entryText.Contains('ephemeral') -and $entryText.Contains('fail closed')) ('workflow-live-entry-fail-closed|' + $entryPath)
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-workflow-focused-'+[guid]::NewGuid().ToString('N'))
try{New-Item -ItemType Directory -Path $temp|Out-Null
    $workflowResolver = Join-Path $candidateRoot 'scripts\resolve-workflow-route.ps1'
    $launchRecovery = Invoke-WorkflowCase $workflowResolver $temp 'launch-recovery' ([ordered]@{operation='LAUNCH';recoveryComplete=$true;packageValid=$false;bindingsMatch=$true})
    $launchReady = Invoke-WorkflowCase $workflowResolver $temp 'launch-ready' ([ordered]@{operation='LAUNCH';recoveryComplete=$true;packageValid=$true;bindingsMatch=$true})
    Assert-True ($launchRecovery.Run.Code -eq 0 -and [string]$launchRecovery.Value.status -ceq 'RECOVERY_READY' -and -not [bool]$launchRecovery.Value.writerActive -and -not [bool]$launchRecovery.Value.recoveryIsAuthority) 'workflow-launch-recovery-does-not-open-writer'
    Assert-True ($launchReady.Run.Code -eq 0 -and [string]$launchReady.Value.status -ceq 'IMPLEMENTATION_READY' -and [bool]$launchReady.Value.writerActive) 'workflow-launch-valid-package-and-bindings-open-writer'

    $routeBase = [ordered]@{operation='ROUTE';projectMatch=$true;cwdGitTopMatch=$true;outcomeMatch=$true;taskOwnerMatch=$true;actorEligible=$true;lineageMatch=$true;resourceRouteAvailable=$true;protectionBoundaryMatch=$true;gitDeviceExternalMatch=$true;publicDecisionMatch=$true;requiresDistinctOutcome=$false;requiresIndependentContext=$false;standingCreateAuthorized=$false}
    $routeReuse = Invoke-WorkflowCase $workflowResolver $temp 'route-reuse' $routeBase
    $routeNewInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeNewInput[$key]=$routeBase[$key] }; $routeNewInput.outcomeMatch=$false; $routeNewInput.requiresDistinctOutcome=$true; $routeNewInput.standingCreateAuthorized=$true
    $routeNew = Invoke-WorkflowCase $workflowResolver $temp 'route-new' $routeNewInput
    $routeBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeBlockedInput[$key]=$routeBase[$key] }; $routeBlockedInput.protectionBoundaryMatch=$false
    $routeBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-blocked' $routeBlockedInput
    $routeCwdBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeCwdBlockedInput[$key]=$routeBase[$key] }; $routeCwdBlockedInput.cwdGitTopMatch=$false
    $routeCwdBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-cwd-blocked' $routeCwdBlockedInput
    $routePublicBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routePublicBlockedInput[$key]=$routeBase[$key] }; $routePublicBlockedInput.publicDecisionMatch=$false
    $routePublicBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-public-blocked' $routePublicBlockedInput
    $routeActorBlockedInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeActorBlockedInput[$key]=$routeBase[$key] }; $routeActorBlockedInput.actorEligible=$false
    $routeActorBlocked = Invoke-WorkflowCase $workflowResolver $temp 'route-actor-blocked' $routeActorBlockedInput
    $routeResourceNewInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeResourceNewInput[$key]=$routeBase[$key] }; $routeResourceNewInput.resourceRouteAvailable=$false
    $routeResourceNew = Invoke-WorkflowCase $workflowResolver $temp 'route-resource-new' $routeResourceNewInput
    $routeIndependentNewInput = [ordered]@{}; foreach ($key in $routeBase.Keys) { $routeIndependentNewInput[$key]=$routeBase[$key] }; $routeIndependentNewInput.requiresIndependentContext=$true
    $routeIndependentNew = Invoke-WorkflowCase $workflowResolver $temp 'route-independent-new' $routeIndependentNewInput
    Assert-True ([string]$routeReuse.Value.decision -ceq 'REUSE' -and -not [bool]$routeReuse.Value.standingCreate) 'workflow-route-reuses-same-authority-and-outcome'
    Assert-True ([string]$routeNew.Value.decision -ceq 'MUST_NEW' -and [bool]$routeNew.Value.standingCreate -and [string]$routeNew.Value.reason -ceq 'STANDING_CREATE_AUTHORIZED') 'workflow-route-must-new-with-standing-create-authorization'
    Assert-True ([string]$routeBlocked.Value.decision -ceq 'BLOCKED' -and -not [bool]$routeBlocked.Value.standingCreate) 'workflow-route-blocks-protection-boundary-mismatch'
    Assert-True ([string]$routeCwdBlocked.Value.decision -ceq 'BLOCKED' -and [string]$routeCwdBlocked.Value.reason -ceq 'CWD_GIT_TOP_MISMATCH') 'workflow-route-blocks-cwd-git-top-mismatch'
    Assert-True ([string]$routePublicBlocked.Value.decision -ceq 'BLOCKED' -and [string]$routePublicBlocked.Value.reason -ceq 'PUBLIC_DECISION_MISMATCH') 'workflow-route-blocks-public-decision-change'
    Assert-True ([string]$routeActorBlocked.Value.decision -ceq 'BLOCKED' -and [string]$routeActorBlocked.Value.reason -ceq 'ACTOR_NOT_ELIGIBLE') 'workflow-route-rejects-ineligible-cross-domain-actor'
    Assert-True ([string]$routeResourceNew.Value.decision -ceq 'MUST_NEW' -and [string]$routeResourceNew.Value.reason -ceq 'RESOURCE_ROUTE_REQUIRES_NEW_CONTEXT') 'workflow-route-resource-unavailable-requires-new-context'
    Assert-True ([string]$routeIndependentNew.Value.decision -ceq 'MUST_NEW' -and [string]$routeIndependentNew.Value.reason -ceq 'INDEPENDENT_CONTEXT_REQUIRED') 'workflow-route-independent-reviewer-full-context'
    Assert-True ($routeReuse.Run.Code -eq 0 -and [string]$routeReuse.Value.decision -ceq 'REUSE') 'workflow-route-owner-self-exec-or-qualified-actor-keeps-task-owner'

    $terminalDelivered = Invoke-WorkflowCase $workflowResolver $temp 'terminal-delivered' ([ordered]@{operation='TERMINAL';terminalStatus='COMPLETE';reportChannelAvailable=$true;proposedConsumerRole='TASK_OWNER';controllerEscalationRequired=$false})
    $terminalReview = Invoke-WorkflowCase $workflowResolver $temp 'terminal-review' ([ordered]@{operation='TERMINAL';terminalStatus='READY';reportChannelAvailable=$true;proposedConsumerRole='INDEPENDENT_REVIEWER';controllerEscalationRequired=$false})
    $terminalControllerRejected = Invoke-WorkflowCase $workflowResolver $temp 'terminal-controller-rejected' ([ordered]@{operation='TERMINAL';terminalStatus='READY';reportChannelAvailable=$true;proposedConsumerRole='CONTROLLER';controllerEscalationRequired=$false})
    $terminalControllerAccepted = Invoke-WorkflowCase $workflowResolver $temp 'terminal-controller-accepted' ([ordered]@{operation='TERMINAL';terminalStatus='BLOCKED';reportChannelAvailable=$true;proposedConsumerRole='CONTROLLER';controllerEscalationRequired=$true})
    $terminalUnavailable = Invoke-WorkflowCase $workflowResolver $temp 'terminal-unavailable' ([ordered]@{operation='TERMINAL';terminalStatus='BLOCKED';reportChannelAvailable=$false;proposedConsumerRole='TASK_OWNER';controllerEscalationRequired=$false})
    Assert-True ([string]$terminalDelivered.Value.status -ceq 'COMPLETE' -and [string]$terminalDelivered.Value.delivery -ceq 'PROACTIVE' -and -not [bool]$terminalDelivered.Value.ackRequired -and -not [bool]$terminalDelivered.Value.polling) 'workflow-terminal-proactive-no-ack-no-poll'
    Assert-True ([string]$terminalReview.Value.status -ceq 'READY' -and [string]$terminalReview.Value.reason -ceq 'DIRECT_CONSUMER_ROUTE') 'workflow-terminal-direct-writer-to-reviewer-route'
    Assert-True ([string]$terminalControllerRejected.Value.status -ceq 'REJECT' -and [string]$terminalControllerRejected.Value.reason -ceq 'UNNECESSARY_CONTROLLER_RELAY') 'workflow-terminal-rejects-unnecessary-controller-relay'
    Assert-True ([string]$terminalControllerAccepted.Value.status -ceq 'BLOCKED' -and [string]$terminalControllerAccepted.Value.delivery -ceq 'PROACTIVE') 'workflow-terminal-allows-real-controller-escalation'
    Assert-True ([string]$terminalUnavailable.Value.status -ceq 'REPORT_CHANNEL_UNAVAILABLE' -and [string]$terminalUnavailable.Value.delivery -ceq 'UNAVAILABLE') 'workflow-terminal-report-channel-unavailable-is-terminal'

    $messageBase = [ordered]@{operation='MESSAGE';hostAuthenticated=$true;expectedTaskId='task-1';observedTaskId='task-1';expectedSender='sender-1';observedSender='sender-1';expectedControllerEpoch=2;observedControllerEpoch=2;expectedEnvelope='envelope-1';observedEnvelope='envelope-1'}
    $messageAccept = Invoke-WorkflowCase $workflowResolver $temp 'message-accept' $messageBase
    $messageStaleInput = [ordered]@{}; foreach ($key in $messageBase.Keys) { $messageStaleInput[$key]=$messageBase[$key] }; $messageStaleInput.observedControllerEpoch=1
    $messageStale = Invoke-WorkflowCase $workflowResolver $temp 'message-stale' $messageStaleInput
    $messageUnauthenticatedInput = [ordered]@{}; foreach ($key in $messageBase.Keys) { $messageUnauthenticatedInput[$key]=$messageBase[$key] }; $messageUnauthenticatedInput.hostAuthenticated=$false
    $messageUnauthenticated = Invoke-WorkflowCase $workflowResolver $temp 'message-unauthenticated' $messageUnauthenticatedInput
    Assert-True ([string]$messageAccept.Value.status -ceq 'ACCEPT' -and [string]$messageAccept.Value.reason -ceq 'HOST_ENVELOPE_MATCH') 'workflow-message-exact-host-envelope-accepted'
    Assert-True ([string]$messageStale.Value.status -ceq 'REJECT' -and [string]$messageStale.Value.reason -ceq 'STALE_OR_MISROUTED_ENVELOPE') 'workflow-message-stale-controller-epoch-rejected'
    Assert-True ([string]$messageUnauthenticated.Value.status -ceq 'REJECT' -and [string]$messageUnauthenticated.Value.reason -ceq 'HOST_AUTHENTICITY_UNAVAILABLE') 'workflow-message-host-authenticity-unavailable-rejected'

    $duplicateLaunch = Invoke-WorkflowRawCase $workflowResolver $temp 'duplicate-launch' '{"operation":"LAUNCH","recoveryComplete":false,"recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    $duplicateMessage = Invoke-WorkflowRawCase $workflowResolver $temp 'duplicate-message' '{"operation":"MESSAGE","hostAuthenticated":false,"hostAuthenticated":true,"expectedTaskId":"task-1","observedTaskId":"task-1","expectedSender":"sender-1","observedSender":"sender-1","expectedControllerEpoch":2,"observedControllerEpoch":2,"expectedEnvelope":"envelope-1","observedEnvelope":"envelope-1"}'
    $duplicateOperation = Invoke-WorkflowRawCase $workflowResolver $temp 'duplicate-operation' '{"operation":"LAUNCH","operation":"LAUNCH","recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    $unicodeDuplicateLaunch = Invoke-WorkflowRawCase $workflowResolver $temp 'unicode-duplicate-launch' '{"operation":"LAUNCH","recoveryComplete":false,"\u0072ecoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    $unicodeDuplicateMessage = Invoke-WorkflowRawCase $workflowResolver $temp 'unicode-duplicate-message' '{"operation":"MESSAGE","hostAuthenticated":false,"\u0068ostAuthenticated":true,"expectedTaskId":"task-1","observedTaskId":"task-1","expectedSender":"sender-1","observedSender":"sender-1","expectedControllerEpoch":2,"observedControllerEpoch":2,"expectedEnvelope":"envelope-1","observedEnvelope":"envelope-1"}'
    $unicodeDuplicateOperation = Invoke-WorkflowRawCase $workflowResolver $temp 'unicode-duplicate-operation' '{"operation":"LAUNCH","\u006fperation":"LAUNCH","recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
    Assert-True ($duplicateLaunch.Code -ne 0 -and $duplicateLaunch.Text.Contains('INPUT_FIELD_COUNT|recoveryComplete')) 'workflow-strict-json-rejects-duplicate-launch-field'
    Assert-True ($duplicateMessage.Code -ne 0 -and $duplicateMessage.Text.Contains('INPUT_FIELD_COUNT|hostAuthenticated')) 'workflow-strict-json-rejects-authenticity-sensitive-duplicate-field'
    Assert-True ($duplicateOperation.Code -ne 0 -and $duplicateOperation.Text.Contains('INPUT_FIELD_COUNT|operation')) 'workflow-strict-json-rejects-duplicate-operation'
    Assert-True ($unicodeDuplicateLaunch.Code -ne 0 -and $unicodeDuplicateLaunch.Text.Contains('INPUT_FIELD_COUNT|recoveryComplete')) 'workflow-strict-json-rejects-unicode-equivalent-launch-field'
    Assert-True ($unicodeDuplicateMessage.Code -ne 0 -and $unicodeDuplicateMessage.Text.Contains('INPUT_FIELD_COUNT|hostAuthenticated')) 'workflow-strict-json-rejects-unicode-equivalent-authenticity-field'
    Assert-True ($unicodeDuplicateOperation.Code -ne 0 -and $unicodeDuplicateOperation.Text.Contains('INPUT_FIELD_COUNT|operation')) 'workflow-strict-json-rejects-unicode-equivalent-operation'

    $handoffBase = [ordered]@{operation='HANDOFF';predecessorControllerId='controller-old';successorControllerId='controller-new';previousEpoch=1;newEpoch=2;controllerWrittenLast=$true;controllerState='CURRENT';takeoverRecorded=$true;retirementAuthorized=$false}
    $handoffComplete = Invoke-WorkflowCase $workflowResolver $temp 'handoff-complete' $handoffBase
    $handoffInvalidInput = [ordered]@{}; foreach ($key in $handoffBase.Keys) { $handoffInvalidInput[$key]=$handoffBase[$key] }; $handoffInvalidInput.newEpoch=1
    $handoffInvalid = Invoke-WorkflowCase $workflowResolver $temp 'handoff-invalid' $handoffInvalidInput
    Assert-True ([string]$handoffComplete.Value.status -ceq 'TAKEOVER_COMPLETE' -and [bool]$handoffComplete.Value.readOnlyGrace -and -not [bool]$handoffComplete.Value.retired) 'workflow-handoff-takeover-complete-read-only-grace-no-retirement'
    Assert-True ([string]$handoffInvalid.Value.status -ceq 'REJECT' -and [string]$handoffInvalid.Value.reason -ceq 'INVALID_HANDOFF') 'workflow-handoff-invalid-epoch-rejected'

    $hotState = Invoke-WorkflowCase $workflowResolver $temp 'hot-state-minimal' ([ordered]@{operation='HOT_STATE';currentCardCurrentOnly=$true;supersededHistoryArchived=$true;taskLifecycleChanged=$false;routingChanged=$false;stableProjectPhaseChanged=$false;longLivedOwnerChanged=$false;protectedSetChanged=$false;uniqueNextActionChanged=$false;routineActorChanged=$true})
    $hotStateInvalid = Invoke-WorkflowCase $workflowResolver $temp 'hot-state-invalid' ([ordered]@{operation='HOT_STATE';currentCardCurrentOnly=$false;supersededHistoryArchived=$false;taskLifecycleChanged=$true;routingChanged=$true;stableProjectPhaseChanged=$true;longLivedOwnerChanged=$true;protectedSetChanged=$true;uniqueNextActionChanged=$true;routineActorChanged=$true})
    Assert-True ([string]$hotState.Value.status -ceq 'ACCEPT' -and [bool]$hotState.Value.taskCardUpdate -and -not [bool]$hotState.Value.taskIndexUpdate -and -not [bool]$hotState.Value.statusUpdate) 'workflow-hot-state-routine-actor-stays-on-task-card'
    Assert-True ([string]$hotStateInvalid.Value.status -ceq 'REJECT' -and -not [bool]$hotStateInvalid.Value.taskCardUpdate -and -not [bool]$hotStateInvalid.Value.taskIndexUpdate -and -not [bool]$hotStateInvalid.Value.statusUpdate) 'workflow-hot-state-rejects-active-archive-layer-violation'


 Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=workflow-route')
}finally{
 $full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())
 if([IO.Path]::GetDirectoryName($full)-cne$parent-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-workflow-focused-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
