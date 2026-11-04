[CmdletBinding()]
param([switch]$JsonTransportOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
Import-Module (Join-Path $PSScriptRoot '../scripts/StrictJsonInput.psm1')
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
# Entry documents navigate to their semantic owner. The exact fields and
# temporary-input behavior remain in the unique Tool Contract below.
$workflowEntryDocuments = @(
    @{path=(Join-Path $candidateRoot 'TASK_AND_SCOPE.md');required=@('WORKFLOW_ROUTE_RESOLVE','TOOL_CONTRACT','必需输入缺失或冲突时停止该转换')},
    @{path=(Join-Path $candidateRoot 'HOST_CODEX.md');required=@('TOOLCHAIN','TOOL_CONTRACT','精确operation入口','失败停依赖链')},
    @{path=(Join-Path $candidateRoot 'PROMPTS.md');required=@('WORKFLOW_ROUTE_RESOLVE','TOOL_CONTRACT','ephemeral','fail closed')},
    @{path=(Join-Path $candidateRoot 'project-starter/BOOTSTRAP.md');required=@('TOOLCHAIN','TOOL_CONTRACT','PROCESS_REQUIREMENTS_RESOLVE','具体输入、schema、continuation')},
    @{path=(Join-Path $maintenanceOverlayRoot 'BOOTSTRAP.md');required=@('TOOL_CONTRACT','resolve-framework-maintenance-process-requirements.ps1','临时材料的具体合同','不授予移动仓库或切换运行包权限')}
)
foreach ($entry in $workflowEntryDocuments) {
    $entryText = Get-Content -LiteralPath $entry.path -Raw -Encoding utf8
    Assert-True (@($entry.required|Where-Object{-not$entryText.Contains($_,[StringComparison]::Ordinal)}).Count-eq0) ('workflow-live-entry-delegates-exact-contract|' + $entry.path)
}
$workflowToolContract=Get-Content -LiteralPath (Join-Path $candidateRoot 'TOOL_CONTRACT.md') -Raw -Encoding utf8
Assert-True ($workflowToolContract.Contains('WORKFLOW_ROUTE_RESOLVE')-and$workflowToolContract.Contains('`-InputJson` 与 `-InputPath` 互斥')-and$workflowToolContract.Contains('直接输入不落盘')-and$workflowToolContract.Contains('转义后重复键、未知字段及错误类型')) 'workflow-owning-contract-keeps-strict-json-and-temporary-input-boundary'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-workflow-focused-'+[guid]::NewGuid().ToString('N'))
try{New-Item -ItemType Directory -Path $temp|Out-Null
    $workflowResolver = Join-Path $candidateRoot 'scripts\resolve-workflow-route.ps1'
    $transport=Invoke-AiwTestProcess $script:pwshExecutable @('-NoProfile','-NonInteractive','-File',$workflowResolver,'-InputJson','{"operation":"LAUNCH","recoveryComplete":true,"packageValid":true,"bindingsMatch":true}','-AsJson') -WorkingDirectory $temp -GroupId 'workflow-json-success'
    $transportValue=(ConvertFrom-AiwStrictInputJson $transport.StdoutText).Value
    Assert-True ($transport.Code-eq0-and$transport.StderrText-ceq''-and$transportValue.status-ceq'IMPLEMENTATION_READY'-and@($transport.StdoutText.Trim()-split"`n").Count-eq1) 'workflow-asjson-native-success-is-one-strict-json-with-empty-stderr'
    foreach($case in @(@{name='malformed';raw='{"operation":';reason='INPUT_JSON'},@{name='unicode-reason';raw='{"operation":"LAUNCH","中文":false,"\u4e2d\u6587":true}';reason='INPUT_FIELD_COUNT|中文'})){
        $failed=Invoke-AiwTestProcess $script:pwshExecutable @('-NoProfile','-NonInteractive','-File',$workflowResolver,'-InputJson',$case.raw,'-AsJson') -WorkingDirectory $temp -GroupId ('workflow-json-'+$case.name)
        $failure=(ConvertFrom-AiwStrictInputJson $failed.StdoutText).Value
        $reasonMatches=if($case.name-ceq'malformed'){$failure.reason.StartsWith($case.reason,[StringComparison]::Ordinal)}else{$failure.reason-ceq$case.reason}
        Assert-True ($failed.Code-ne0-and$failed.StderrText-ceq''-and$failure.status-ceq'FAIL'-and$reasonMatches-and@($failed.StdoutText.Trim()-split"`n").Count-eq1-and$failed.StdoutText-cnotmatch'[^\x00-\x7F]') ('workflow-asjson-native-'+$case.name+'-preserves-real-reason-without-pretty-stderr')
    }
    if($JsonTransportOnly){Write-Output ('PARTIAL|JSON_TRANSPORT_ONLY|checks='+$script:passed);return}
    foreach($layout in @('CRLF','NO_FINAL_LF')){
        $raw='{"operation":"LAUNCH",'+"`n"+'"recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'
        if($layout-ceq'CRLF'){$raw=$raw.Replace("`n","`r`n")+"`r`n"}
        $layoutRun=Invoke-Ps $workflowResolver @('-InputJson',$raw,'-AsJson')
        Assert-True ($layoutRun.Code-eq0-and($layoutRun.Text|ConvertFrom-Json).status-ceq'IMPLEMENTATION_READY') ('workflow-equivalent-json-layout-'+$layout)
    }
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

    # Semantic inputs are supplied explicitly, not inferred from titles or chat age.
    # Existing reuse/new/independent cases above remain the primary route checks.
    foreach($case in @(
        @{name='same-review-bounded-repair';different=$false;distinct=$false;expected='REUSE'},
        @{name='same-unfinished-outcome-title-only';different=$false;distinct=$false;expected='REUSE'},
        @{name='archived-chat-new-outcome';different=$true;distinct=$false;expected='MUST_NEW'},
        @{name='distinct-finite-outcome';different=$false;distinct=$true;expected='MUST_NEW'})){
        $route=[ordered]@{};foreach($key in $routeBase.Keys){$route[$key]=$routeBase[$key]}
        $route.outcomeMatch=-not$case.different;$route.requiresDistinctOutcome=$case.distinct
        $observed=Invoke-WorkflowCase $workflowResolver $temp ('semantic-'+$case.name) $route
        Assert-True ($observed.Run.Code-eq0-and$observed.Value.decision-ceq$case.expected) ('workflow-route-semantic-'+$case.name)
    }
    Write-Output 'EVIDENCE_CEILING|EXPLICIT_ROUTE_INPUTS_NOT_NATURAL_SEMANTIC_COMPLIANCE_OR_HOST_ARCHIVAL'

    foreach($role in @('TASK_OWNER','INDEPENDENT_REVIEWER','CONTROLLER','USER','NONE')){
        $legacy=Invoke-WorkflowCase $workflowResolver $temp ('terminal-unbound-'+$role) ([ordered]@{operation='TERMINAL';terminalStatus='COMPLETE';reportChannelAvailable=$true;proposedConsumerRole=$role;controllerEscalationRequired=$false})
        Assert-True ($legacy.Run.Code-ne0) ('workflow-terminal-rejects-unbound-role-'+$role)
    }
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


    foreach($outcome in @('SUCCESS','FAILURE','UNKNOWN')){
        $delivery=Invoke-WorkflowCase $workflowResolver $temp ('delivery-'+$outcome) ([ordered]@{operation='DELIVERY';deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='OBSERVE';expectedRecipient='owner';observedRecipient='owner';outcome=$outcome;evidence='fixture:host-result'}})
        Assert-True ($delivery.Run.Code-eq0-and[bool]$delivery.Value.delivered-eq($outcome-ceq'SUCCESS')-and-not$delivery.Value.retryAllowed-and-not$delivery.Value.consumerBound-and-not$delivery.Value.userAuthorizationProven) ('workflow-consumes-actual-send-'+$outcome)
    }
    $routeProject=[ordered]@{};foreach($key in $routeBase.Keys){$routeProject[$key]=$routeBase[$key]};$routeProject.Remove('cwdGitTopMatch');$routeProject.cwdProjectRootMatch=$true
    $projectReuse=Invoke-WorkflowCase $workflowResolver $temp 'route-project-root' $routeProject
    $routeProject.cwdProjectRootMatch=$false
    $projectBlocked=Invoke-WorkflowCase $workflowResolver $temp 'route-project-root-mismatch' $routeProject
    Assert-True ($projectReuse.Run.Code-eq0-and$projectReuse.Value.decision-ceq'REUSE'-and$projectBlocked.Value.reason-ceq'CWD_PROJECT_ROOT_MISMATCH') 'workflow-route-project-root-without-git-top'
    foreach($outcome in @('NOT_SENT','SUCCESS','FAILURE','UNKNOWN')){
        $prepare=$outcome-ceq'NOT_SENT'
        $context=[ordered]@{channel='TASK_MESSAGE';stage=$(if($prepare){'PREPARE'}else{'OBSERVE'});expectedRecipient='owner';observedRecipient=$(if($prepare){'NOT_APPLICABLE'}else{'owner'});outcome=$outcome;evidence=$(if($prepare){'NOT_APPLICABLE'}else{'fixture:host-result'})}
        $input=[ordered]@{operation='DELIVERY';deliveryContext=$context};$path=Join-Path $temp ('workflow-delivery-text-'+$outcome+'.json');Write-Utf8 $path ($input|ConvertTo-Json -Depth 12)
        $json=Invoke-Ps $workflowResolver @('-InputPath',$path,'-AsJson');$plain=Invoke-Ps $workflowResolver @('-InputPath',$path)
        $value=$json.Text|ConvertFrom-Json
        Assert-True ($json.Code-eq0-and$plain.Code-eq0-and$plain.Text.Contains('status='+[string]$value.status)-and$plain.Text.Contains('delivered='+[string]$value.delivered)-and$plain.Text.Contains('retryAllowed='+[string]$value.retryAllowed)-and$plain.Text.Contains('evidenceCeiling='+[string]$value.evidenceCeiling)) ('workflow-delivery-json-text-equivalent-'+$outcome)
    }
 Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=workflow-route')
}finally{
 $full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())
 if([IO.Path]::GetDirectoryName($full)-cne$parent-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-workflow-focused-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
