[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$passed=0;$utf8=[Text.UTF8Encoding]::new($false)
$versionRoot=Split-Path -Parent $PSScriptRoot
$frameworkRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 50)}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw "ASSERT_FAIL|$Name"};$script:passed++;Write-Output "PASS|$Name"}
function Compose([string]$Profile,[string]$Role,[string]$Phase,[string]$Action,[string]$Result,[string]$Hints,[string[]]$Paths=@(),[bool]$Unknown=$false){
 return Invoke-ProcessRequirementComposition -ProjectRoot $temp -FrameworkRoot $frameworkRoot -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity (Get-AiwFileIdentity $configPath) -ExpectedCorrectionsIdentity (Get-AiwFileIdentity $correctionsPath) -Profile $Profile -Role $Role -Phase $Phase -Actor 'fixture-actor' -TaskIdentity (Get-AiwFileIdentity $taskPath) -ActionKind $Action -ResultKind $Result -Objective $Hints -ExactPaths $Paths -EvaluationOnly -SemanticApplicabilityUnknown:$Unknown
}
function AssertSelection($Output,[string]$Name,[string[]]$Required,[string[]]$Excluded=@()){
 $ids=@($Output.selectedRequirements.requirementId)
 $missing=@($Required|Where-Object {$_-cnotin$ids});$extra=@($Excluded|Where-Object {$_-cin$ids})
 if($missing.Count-or$extra.Count){throw ('SELECTION_FAIL|'+$Name+'|missing='+($missing-join',')+'|unwanted='+($extra-join','))}
 Check ($Output.status-cin@('EVALUATION_ONLY','PASS')-and@($Output.conflicts).Count-eq0-and@($Output.selectedRequirements|Where-Object {[string]::IsNullOrWhiteSpace($_.fullText)}).Count-eq0) $Name
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-rule-chain-'+[guid]::NewGuid().ToString('N'))
try{
 $configPath=Join-Path $temp '.ai-workspace/project.json';$correctionsPath=Join-Path $temp '.ai-workspace/corrections.json';$policyPath=Join-Path $temp '.ai-workspace/process-policy.json';$taskPath=Join-Path $temp '.ai-workspace/tasks/active/SELECTION-001.md'
 SaveJson $configPath ([ordered]@{schemaVersion=5;id='selection-fixture';displayName='Selection fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
 SaveJson $correctionsPath ([ordered]@{schemaVersion=2;contractVersion='2.0.0';projectId='selection-fixture';corrections=@()})
 SaveJson (Join-Path $temp '.ai-workspace/controller.json') ([ordered]@{schemaVersion=1;projectId='selection-fixture';controllerId='fixture-actor';controllerEpoch=1;state='CURRENT'})
 SaveText (Join-Path $temp '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 SaveText $taskPath "# SELECTION-001`n- Owner: fixture-actor`n- Work route: actor=fixture-actor; role=TASK_OWNER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]"
 $policy=[ordered]@{schemaVersion=1;contractVersion='2.0.0';projectId='selection-fixture';selectedRulePackBytes=98304;rules=@()};SaveJson $policyPath $policy
 $launch='framework:PR_TASK_LAUNCH_AND_ROUTE';$collaboration='framework:PR_TASK_COLLABORATION_BOUNDARY';$judgment='framework:PR_TASK_IMPLEMENTATION_JUDGMENT';$disposition='framework:PR_TASK_CHANGED_OUTPUT_DISPOSITION';$qualification='framework:PR_REVIEW_QUALIFICATION_AND_PLANNING';$critical='framework:PR_CRITICAL_REVIEW_INDEPENDENCE';$route='framework:PR_REVIEW_ROUTE_PREPARATION'
 # Fourteen historical inputs, anonymized and mapped only to the new role name.
 # Required native obligations do not declare that project-specific increments
 # have been absorbed or that a real model reliably constructs these hints.
 $cases=@(
  @{id='wait-micro';p='MICRO';r='TASK_OWNER';phase='PLAN';a='NONE';result='PLAN';h='等待决定';required=@($collaboration);excluded=@($launch,$route,$critical)},
  @{id='readiness-git';p='STANDARD';r='TASK_OWNER';phase='GIT';a='NONE';result='PLAN';h='plan readiness';required=@($judgment);excluded=@($route,$critical)},
  @{id='git-pending';p='STANDARD';r='TASK_OWNER';phase='PLAN';a='NONE';result='PLAN';h='待提交收口';required=@($disposition,'framework:PR_GIT_PLANNING_BOUNDARY');excluded=@('framework:PR_GIT_PUSH_SEPARATE')},
  @{id='push';p='STANDARD';r='TASK_OWNER';phase='GIT';a='PUSH';result='GIT_RESULT';h='git disposition';required=@($disposition,'framework:PR_GIT_PUSH_SEPARATE');excluded=@($route)},
  @{id='review-plan-critical';p='CRITICAL';r='TASK_OWNER';phase='PLAN';a='NONE';result='PLAN';h='review';required=@($qualification,$launch);excluded=@($route,$critical)},
  @{id='review-standard';p='STANDARD';r='REVIEWER';phase='REVIEW';a='REVIEW_EXECUTE';result='REVIEW_VERDICT';h='review';required=@($qualification,$launch);excluded=@($route,$critical)},
  @{id='review-micro';p='MICRO';r='REVIEWER';phase='REVIEW';a='REVIEW_EXECUTE';result='REVIEW_VERDICT';h='review';required=@($qualification,$launch);excluded=@($route,$critical)},
  @{id='review-critical-control';p='CRITICAL';r='REVIEWER';phase='REVIEW';a='REVIEW_EXECUTE';result='REVIEW_VERDICT';h='review';required=@($qualification,$critical,$launch);excluded=@($route)},
  @{id='wait-plan';p='STANDARD';r='TASK_OWNER';phase='PLAN';a='NONE';result='PLAN';h='等待决定';required=@($collaboration);excluded=@($launch,$route,$critical)},
  @{id='wait-user-response-control';p='STANDARD';r='TASK_OWNER';phase='PLAN';a='NONE';result='USER_RESPONSE';h='等待决定';required=@($collaboration);excluded=@($launch,$route,$critical)},
  @{id='organization-followup';p='STANDARD';r='TASK_OWNER';phase='PLAN';a='NONE';result='PLAN';h='followup task';required=@($launch,'framework:PR_TASK_RESOURCE_SELECTION');excluded=@($route,$critical)},
  @{id='organization-review-execute';p='STANDARD';r='REVIEWER';phase='REVIEW';a='REVIEW_EXECUTE';result='REVIEW_VERDICT';h='review';required=@($launch,$qualification);excluded=@($route,$critical)},
  @{id='organization-new-assignment-control';p='STANDARD';r='TASK_OWNER';phase='PLAN';a='NONE';result='PLAN';h='new assignment';required=@($launch,'framework:PR_TASK_RESOURCE_SELECTION');excluded=@($route,$critical)},
  @{id='organization-internal-plan';p='STANDARD';r='TASK_OWNER';phase='PLAN';a='NONE';result='PLAN';h='internal subagent';required=@($launch,'framework:PR_TASK_RESOURCE_SELECTION');excluded=@($route,$critical)}
 )
 foreach($case in $cases){$out=Compose $case.p $case.r $case.phase $case.a $case.result $case.h @('.ai-workspace/REVIEW_PROFILE.md');AssertSelection $out ('historical-'+$case.id) $case.required $case.excluded}
 $upgrade='framework:PR_PROJECT_UPGRADE_ACTOR_BOUND'
 foreach($hints in @('mapping','pinning','spindle')){AssertSelection (Compose CRITICAL TASK_OWNER PLAN CONTROL_WRITE IMPLEMENTATION_RESULT $hints @('.ai-workspace/project.json')) ('not-upgrade-'+$hints) @() @($upgrade)}
 foreach($hints in @('pin','PIN change','upgrade','adoption','migration')){AssertSelection (Compose CRITICAL TASK_OWNER PLAN CONTROL_WRITE IMPLEMENTATION_RESULT $hints @('.ai-workspace/project.json')) ('actual-upgrade-'+$hints) @($upgrade)}
 $composition='framework:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION';$correction='framework:PR_CORRECTIONS_V2_COMPATIBILITY'
 AssertSelection (Compose CRITICAL FRAMEWORK_MAINTAINER IMPLEMENT TEST_WRITE IMPLEMENTATION_RESULT 'fixture correction' @('tests/fixture.ps1')) 'fixture-repair-is-not-project-governance' @() @($composition,$correction)
 foreach($hints in @('project correction','项目纠正','corrections.json')){AssertSelection (Compose CRITICAL TASK_OWNER PLAN CONTROL_WRITE IMPLEMENTATION_RESULT $hints @('.ai-workspace/corrections.json')) ('project-governance-'+$hints) @($composition,$correction)}
 AssertSelection (Compose CRITICAL TASK_OWNER PLAN CONTROL_WRITE IMPLEMENTATION_RESULT 'unclear rule change' @('.ai-workspace/project.json') $true) 'unknown-keeps-affected-upgrade-rule' @($upgrade)
 AssertSelection (Compose STANDARD TASK_OWNER PLAN NONE PLAN 'unclear planning' @() $true) 'unknown-does-not-invent-review-action' @() @($route,$critical)
 # A real progress update overselected handoff from the role label alone.
 # Keep scope/action fixed so the regression tests semantic applicability.
 $handoff='framework:PR_CONTROLLER_HANDOFF_DIRECTIONAL';$statusPath=@('.ai-workspace/tasks/active/SELECTION-001.md')
 foreach($hints in @('current controller progress','controller task status update','主控状态整理','task handoff','handoff','takeover','epoch','controller effort adjustment','controller handoffStatus')){
  AssertSelection (Compose CRITICAL CONTROLLER IMPLEMENT CONTROL_WRITE IMPLEMENTATION_RESULT $hints $statusPath) ('not-controller-transition-'+$hints) @() @($handoff)
 }
 foreach($hints in @('controller handoff','controller takeover','controller transition','controller epoch change','主控交接','主控接任','主控切换','主控移交')){
  AssertSelection (Compose CRITICAL CONTROLLER IMPLEMENT CONTROL_WRITE IMPLEMENTATION_RESULT $hints $statusPath) ('actual-controller-transition-'+$hints) @($handoff)
 }
 AssertSelection (Compose CRITICAL CONTROLLER IMPLEMENT CONTROL_WRITE IMPLEMENTATION_RESULT 'unclear responsibility change' $statusPath $true) 'unknown-keeps-controller-transition-rule' @($handoff)
 AssertSelection (Compose CRITICAL TASK_OWNER IMPLEMENT CONTROL_WRITE IMPLEMENTATION_RESULT 'task handoff' $statusPath $true) 'unknown-task-owner-does-not-create-controller-transition' @() @($handoff)
 foreach($objective in @('Cancel the controller handoff; update progress only.','If approved later, perform controller takeover; now update progress.')){
  $intent=[pscustomobject]@{objective=$objective;semanticHints=@('current controller progress');requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT'}
  AssertSelection (Compose CRITICAL CONTROLLER IMPLEMENT CONTROL_WRITE IMPLEMENTATION_RESULT (Get-AiwProcessSemanticText $intent) $statusPath) ('controller-current-action-'+$objective) @() @($handoff)
 }
 # Shared professional requirements use actual project policy, not a second
 # matcher. Role-specific writing instructions remain writer-specific.
 function New-PolicyRule([string]$Id,[string]$Body,[string[]]$Roles,[string[]]$Actions,[string[]]$Terms){
  return [ordered]@{ruleId=$Id;requirementReason='Explicit fixture quality requirement';effectiveRule=$Body;selectors=[ordered]@{profiles=@('*');roles=$Roles;phases=@('*');actionKinds=$Actions;resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=$Terms;semanticMatch='TOKEN'};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:explicit-project-standard'}
 }
 $policy.rules=@(
  (New-PolicyRule 'SHARED_VISUAL_QUALITY' 'The composed design must keep labels readable at the specified viewing scale.' @('*') @('*') @('visual design','interface design')),
  (New-PolicyRule 'SHARED_CODE_QUALITY' 'All changed callers must preserve the accepted public result contract.' @('*') @('SOURCE_WRITE','TEST_WRITE','REVIEW_EXECUTE') @('implementation')),
  (New-PolicyRule 'AUTHOR_PROCEDURE' 'Writers update the source and its direct dependency.' @('EXECUTOR') @('SOURCE_WRITE','TEST_WRITE') @('implementation'))
 );SaveJson $policyPath $policy
 $visual='project:selection-fixture:SHARED_VISUAL_QUALITY';$code='project:selection-fixture:SHARED_CODE_QUALITY';$author='project:selection-fixture:AUTHOR_PROCEDURE'
 AssertSelection (Compose STANDARD REVIEWER REVIEW REVIEW_EXECUTE REVIEW_VERDICT 'review visual design' @()) 'design-review-with-no-path-loads-product-quality' @($visual,$qualification) @($code,$author,$route)
 AssertSelection (Compose STANDARD REVIEWER REVIEW REVIEW_EXECUTE REVIEW_VERDICT 'review implementation' @('src/example.js')) 'implementation-review-loads-shared-not-author-procedure' @($code,$qualification) @($author,$visual,$route)
 AssertSelection (Compose STANDARD EXECUTOR IMPLEMENT SOURCE_WRITE IMPLEMENTATION_RESULT 'implementation visual design' @('src/example.js')) 'author-loads-cross-professional-quality-and-own-procedure' @($visual,$code,$author) @($qualification)
 AssertSelection (Compose STANDARD TASK_OWNER PLAN NONE PLAN 'review organization visual design' @()) 'none-organization-planning-loads-quality-without-execution-gates' @($visual,$qualification,$launch) @($route,$critical,$author)
 AssertSelection (Compose STANDARD REVIEWER REVIEW REVIEW_EXECUTE REVIEW_VERDICT 'unknown implementation' @() $true) 'unknown-keeps-known-role-boundary' @($code,$qualification) @($author)
 # Original wording can contain cancelled or conditional future actions. Only
 # the current semantic projection is selected; this is a deterministic input
 # replay, not proof that an LLM will always normalize the request correctly.
 foreach($objective in @('Cancel the review; only explain the design.','If later approved, arrange review; now explain the design.','Do not implement; compare the existing design.')){
  $intent=[pscustomobject]@{objective=$objective;semanticHints=@('design comparison');requestedActionKind='NONE';requestedResultKind='PLAN'}
  AssertSelection (Compose STANDARD TASK_OWNER PLAN NONE PLAN (Get-AiwProcessSemanticText $intent) @()) ('only-current-action-'+$objective) @() @($route,$critical,$qualification,$launch)
 }
 $review=Compose STANDARD REVIEWER REVIEW REVIEW_EXECUTE REVIEW_VERDICT 'implementation review' @()
 $quality=@($review.selectedRequirements|Where-Object requirementId -ceq $code)[0]
 Check ($quality.fullText-ceq$policy.rules[1].effectiveRule) 'shared-rule-complete-body-equals-current-project-source'
 $planning=Compose CRITICAL TASK_OWNER PLAN NONE PLAN 'review' @()
 $obligations=@($planning.selectedRequirements|ForEach-Object {@($_.preparationRequirements)+@($_.resultRequirements)})
 Check ('REVIEW_VERDICT_BOUND'-cnotin$obligations-and'SELF_CHECK_BOUND'-cnotin$obligations-and'CANDIDATE_FROZEN'-cnotin$obligations) 'review-planning-needs-no-future-evidence'
 Write-Output ('RULE_CHAIN_TESTS_PASS|checks='+$passed+'|historicalCases=14|evidence=DETERMINISTIC_SELECTION_ONLY')
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$systemTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($resolved)-cne$systemTemp-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-rule-chain-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
