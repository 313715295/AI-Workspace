[CmdletBinding()]
param([switch]$FixtureContractOnly)
Import-Module (Join-Path $PSScriptRoot 'TestNativeOutput.psm1')
Initialize-AiwTestNativeOutput
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$passed=0;$utf8=[Text.UTF8Encoding]::new($false)
function SaveText([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;$null=New-Item -ItemType Directory -Path $parent -Force;[IO.File]::WriteAllText($Path,$Text.Replace("`r",'').TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path (ConvertTo-Json -InputObject $Value -Depth 100)}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Check([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Run([string]$Tool,[hashtable]$Arguments){$global:LASTEXITCODE=0;try{$lines=@(& $Tool @Arguments 2>&1|ForEach-Object{[string]$_});$code=$global:LASTEXITCODE}catch{$lines=@([string]$_);$code=1};$text=$lines-join"`n";return [pscustomobject]@{Code=$code;Text=$text;Value=$(try{$text|ConvertFrom-Json -Depth 100}catch{$null})}}
$versionRoot=Split-Path -Parent $PSScriptRoot
$workflow=Join-Path $versionRoot 'scripts/resolve-workflow-route.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-efficiency-'+[guid]::NewGuid().ToString('N'))
try{
 $null=New-Item -ItemType Directory -Path $temp
 $valid='{"operation":"LAUNCH","recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'+"`n"
 $ip=Join-Path $temp 'workflow.json';SaveText $ip $valid
 $file=Run $workflow @{InputPath=$ip;AsJson=$true};$direct=Run $workflow @{InputJson=$valid;AsJson=$true}
 Check ($file.Code-eq0-and$direct.Code-eq0-and$file.Text-ceq$direct.Text) 'workflow-file-direct-equivalent'
 foreach($case in @(
  @{Name='escaped-duplicate';Text='{"operation":"LAUNCH","oper\u0061tion":"ROUTE","recoveryComplete":true,"packageValid":true,"bindingsMatch":true}'},
  @{Name='unknown-field';Text='{"operation":"LAUNCH","recoveryComplete":true,"packageValid":true,"bindingsMatch":true,"unknown":0}'},
  @{Name='wrong-type';Text='{"operation":"LAUNCH","recoveryComplete":"true","packageValid":true,"bindingsMatch":true}'},
  @{Name='nested-duplicate';Text='{"operation":"LAUNCH","recoveryComplete":{"x":1,"\u0078":2},"packageValid":true,"bindingsMatch":true}'},
  @{Name='array';Text='[]'},@{Name='trailing-comma';Text='{"operation":"LAUNCH",}'},@{Name='unknown-operation';Text='{"operation":"UNKNOWN"}'}
 )){$text=$case.Text+"`n";SaveText $ip $text;$f=Run $workflow @{InputPath=$ip;AsJson=$true};$d=Run $workflow @{InputJson=$text;AsJson=$true};Check ($f.Code-ne0-and$d.Code-ne0) ('workflow-both-reject-'+$case.Name)}
 $both=Run $workflow @{InputPath=$ip;InputJson=$valid;AsJson=$true};Check ($both.Code-ne0) 'workflow-inputs-mutually-exclusive'
 foreach($text in @($valid.TrimEnd("`n"),$valid.Replace("`n","`r`n"))){$d=Run $workflow @{InputJson=$text;AsJson=$true};Check ($d.Code-eq0) ('workflow-equivalent-text-layout-'+$passed)}
 foreach($text in @(([string][char]0xFEFF+$valid),($valid+[char]0),($valid+[char]0xFFFD))){$d=Run $workflow @{InputJson=$text;AsJson=$true};Check ($d.Code-ne0) ('workflow-damaged-text-rejected-'+$passed)}
 $m=Run $workflow @{InputJson=('{"operation":"MESSAGE","senderAuthentic":true}'+"`n");AsJson=$true};Check ($m.Code-ne0) 'workflow-message-missing-authenticated-fields-rejected'
 # Anonymous ordinary project exercises actual composer and process entrypoints.
 $project=Join-Path $temp 'project';$null=New-Item -ItemType Directory -Path $project;& git -C $project init -q
 Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1') -Force
 $repositoryRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
 $definition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
 $framework=Join-Path $temp 'framework'
 $fv=New-AiwTestRuntimeFixture $repositoryRoot $framework $definition.mechanismVersionPaths @(@($definition.rootAdoptionPaths)+@($definition.maintenancePaths)+@('README.md','LICENSE')|Sort-Object -Unique)
 $control=Join-Path $project '.ai-workspace';$task=Join-Path $control 'tasks/active/EFFICIENCY-001.md'
 SaveText $task "# EFFICIENCY-001 — fixture`n- Owner: actor`n- Work route: actor=actor; role=TASK_OWNER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]"
 SaveJson (Join-Path $control 'project.json') ([ordered]@{schemaVersion=7;id='efficiency-fixture';displayName='Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
 SaveJson (Join-Path $control 'controller.json') ([ordered]@{schemaVersion=1;projectId='efficiency-fixture';controllerId='actor';controllerEpoch=1;state='CURRENT'})
 SaveJson (Join-Path $control 'corrections.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='efficiency-fixture';corrections=@()})
 SaveText (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 $policy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='efficiency-fixture';rules=@()};$policyPath=Join-Path $control 'process-policy.json';SaveJson $policyPath $policy
 $runtime=Join-Path $control 'runtime/EFFICIENCY-001/actor';$null=New-Item -ItemType Directory -Path $runtime -Force
 function CurrentQueryFacets([string]$Work='aiw:discussion',[string]$Domain='aiw:software',[string]$Deliverable='aiw:plan',[string]$Stage='aiw:planning'){
  [ordered]@{domain=[ordered]@{state='KNOWN';values=@($Domain)};workType=[ordered]@{state='KNOWN';values=@($Work)};deliverableType=[ordered]@{state='KNOWN';values=@($Deliverable)};stage=[ordered]@{state='KNOWN';values=@($Stage)}}
 }
 $intent=[ordered]@{schemaVersion=2;objective='Do not create another task; preview the current work.';requestedActionKind='NONE';requestedResultKind='USER_RESPONSE';semanticHints=@('configuration explanation');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=(CurrentQueryFacets)}
 $discovery=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$framework;taskPath=$task;expectedProjectConfigIdentity=Id (Join-Path $control 'project.json');expectedCorrectionsIdentity=Id (Join-Path $control 'corrections.json');expectedTaskIdentity=Id $task;observedActor='actor';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$true}
 $resolver=Join-Path $fv 'scripts/resolve-process-requirements.ps1';$inputPath=Join-Path $runtime 'input.json'
 function DiscoverCase([string[]]$Hints,$Facets=(CurrentQueryFacets)){$discovery.intentEnvelope.semanticHints=@($Hints);$discovery.intentEnvelope.facets=$Facets;SaveJson $inputPath $discovery;$r=Run $resolver @{InputPath=$inputPath;AsJson=$true};if($r.Code-ne0-or$null-eq$r.Value-or$r.Value.status-cnotin@('PASS','EVALUATION_ONLY')){throw ('FIXTURE_PREFIX_FAILED|efficiency|native='+$r.Code+'|raw='+$r.Text)};return $r.Value}
 $read=DiscoverCase @('configuration explanation');$ids=@($read.selectedRuleBlocks.requirementId)
 Check ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cnotin$ids-and'framework:PR_TASK_RESOURCE_SELECTION'-cnotin$ids) 'healthy-read-only-does-not-load-creation-or-resource-selection'
 if($FixtureContractOnly){
  Write-AiwTestJson (Join-Path $env:AIW_TEST_RAW_DIRECTORY 'fixture-members-efficiency.json') @{kind='PRIVATE_FINITE_FIXTURE';status=$read.status;declaredVersionInputs=$definition.mechanismVersionPaths;declaredRootInputs=@(@($definition.rootAdoptionPaths)+@($definition.maintenancePaths)+@('README.md','LICENSE')|Sort-Object -Unique);actualMembers=(Get-AiwTestFixtureSnapshot $framework -IdentityOnly).Files;consumerResult=$read;undeclaredOwnedSeedOmitted=(-not(Test-Path -LiteralPath (Join-Path $framework 'owned-undeclared-seed.txt')))}
  Write-Output ('PARTIAL|FIXTURE_CONTRACT_ONLY|efficiency|code=0|status='+$read.status+'|reason=REAL_RESOLVER_REACHED');return
 }
 # The general disposition block retains its explicit read-only exemption;
 # reading it does not claim this fixture has produced repository bytes.
 # Real taskless resolver: storage is derived from exact actor bytes, not a
 # normalized identity. Creation and cleanup exercise the same binding.
 $actorInput=$discovery|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $actorInput.contextType='PROJECT_READ_ONLY';$actorInput.taskPath='NOT_APPLICABLE';$actorInput.expectedTaskIdentity='NOT_APPLICABLE'
 $actorInput.readOnlyContext=[pscustomobject]@{sessionId='fixture-session';requestId='ACTOR-001';role='TASK_OWNER';phase='PLAN';profile='STANDARD'}
 $actorSegments=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($actorName in @('/root/review','\root\review','Actor','actor','actor-sha256-example','a/b','a\b','actor.','actor..','con','con.txt','nul','01a00000-0000-7000-8000-000000000000')){
  $segment=if($actorName-cmatch'^[a-z0-9][a-z0-9._-]*$'-and-not$actorName.EndsWith('.')-and$actorName-cnotmatch'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)'-and-not$actorName.StartsWith('actor-sha256-')){$actorName}else{'actor-sha256-'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($actorName))).ToLowerInvariant()}
  Check ($actorSegments.Add($segment)) ('actor-storage-distinct-'+$actorName)
  $dir=Join-Path $control ('runtime/ACTOR-001/'+$segment);$null=New-Item -ItemType Directory -Path $dir -Force
  $ai=Join-Path $dir 'input.json';$ar=Join-Path $dir 'compact.json';$actorInput.observedActor=$actorName;SaveJson $ai $actorInput
  $saved=Run $resolver @{InputPath=$ai;CompactReceiptPath=$ar;DeleteInputOnExit=$true;AsJson=$true}
  Check ($saved.Code-eq0-and(Test-Path -LiteralPath $ar)-and-not(Test-Path -LiteralPath $ai)-and$saved.Value.compactReceipt.binding.actor-ceq$actorName) ('actor-storage-roundtrip-exact-identity-'+$actorName)
  $storedId=Id $ar;SaveJson $ai $actorInput;$again=Run $resolver @{InputPath=$ai;CompactReceiptPath=$ar;AsJson=$true}
  Check ($again.Code-ne0-and(Id $ar)-ceq$storedId) ('actor-existing-receipt-not-overwritten-'+$actorName)
 }
 foreach($case in @(
  @{Hint='temporary task archive';Required='PR_TASK_CHANGED_OUTPUT_DISPOSITION';Facts=(CurrentQueryFacets 'aiw:closure')},
  @{Hint='git disposition';Required='PR_TASK_CHANGED_OUTPUT_DISPOSITION';Facts=(CurrentQueryFacets 'aiw:closure' 'aiw:version-control')},
  @{Hint='execution organization';Required='PR_TASK_RESOURCE_SELECTION';Facts=(CurrentQueryFacets 'aiw:task-organization')},
  @{Hint='new assignment';Required='PR_CODEX_TOOL_OPERATION_RESOLUTION';Facts=(CurrentQueryFacets 'aiw:task-organization')},
  @{Hint='git';Required='PR_GIT_PLANNING_BOUNDARY';Facts=(CurrentQueryFacets 'aiw:planning' 'aiw:version-control')},
  @{Hint='project correction';Required='PR_CORRECTIONS_V2_COMPATIBILITY';Facts=(CurrentQueryFacets 'aiw:rule-maintenance' 'aiw:governance')},
  @{Hint='upgrade';Required='PR_CORRECTION_ADOPTION_ANALYSIS';Facts=(CurrentQueryFacets 'aiw:adoption' 'aiw:governance')}
 )){
  $value=DiscoverCase @($case.Hint) $case.Facts
  Check (('framework:'+$case.Required)-cin@($value.selectedRuleBlocks.requirementId)) ('real-composer-selects-'+$case.Hint)
  Check ('framework:PR_GIT_PUSH_SEPARATE'-cnotin@($value.selectedRuleBlocks.requirementId)) ('planning-does-not-authorize-push-'+$case.Hint)
 }
 $discovery.intentEnvelope.semanticHints=@('configuration explanation')
 $discovery.intentEnvelope.facets=CurrentQueryFacets
 # Execute the actual documentation, not a separately maintained imitation.
 $promptText=[IO.File]::ReadAllText((Join-Path $versionRoot 'PROMPTS.md'))
 $example=[regex]::Match($promptText,'(?s)<!-- AIW-EXAMPLE:PROCESS_INPUTS:BEGIN -->\s*```powershell\s*(.*?)\s*```\s*<!-- AIW-EXAMPLE:PROCESS_INPUTS:END -->')
 Check $example.Success 'documented-process-example-found'
 . ([scriptblock]::Create($example.Groups[1].Value))
 $catalog=Get-Content -Raw -LiteralPath (Join-Path $fv 'PROCESS_REQUIREMENTS.json')|ConvertFrom-Json
 $metadata=@(Get-ExampleIntentMetadata $catalog)
 Check ($metadata.Count-eq$catalog.requirements.Count-and@($metadata|Where-Object{$null-ne$_.PSObject.Properties['fullText']}).Count-eq0) 'intent-metadata-complete-without-rule-bodies'
 $sample=New-ExampleDiscover $discovery $intent
 [IO.File]::WriteAllText($inputPath,(ConvertTo-ExampleInputJson $sample),$utf8)
  $documented=Run $resolver @{InputPath=$inputPath;AsJson=$true}
  Check ($documented.Code-eq0-and($documented.Value.selectedRuleBlocks.requirementId-join'|')-ceq($ids-join'|')) 'documented-discover-real-consumer-equivalence'
  $readExample=Read-ExampleDiscoverOutput $documented.Value
  Check (@($readExample.selectedRuleBlocks).Count-eq@($documented.Value.selectedRuleBlocks).Count-and@($readExample.selectedRuleBlocks|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.fullText)}).Count-eq0-and-not($readExample.compactReceipt|ConvertTo-Json -Depth 100).Contains('fullText')) 'documented-output-reads-full-blocks-not-compact'
  $badExample=$documented.Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badExample.status='FAIL'
  $badOutputRejected=$false;try{$null=Read-ExampleDiscoverOutput $badExample}catch{$badOutputRejected=$true}
  Check $badOutputRejected 'documented-output-stops-on-failed-status'
 $exampleReceipt=Join-Path $runtime 'example-receipt.json';SaveJson $exampleReceipt $documented.Value.compactReceipt
 $emptyBoundary=New-ExampleBoundary $exampleReceipt (Id $exampleReceipt) 'ADMIT_ACTION' @() @() @() 'NOT_REQUIRED' 'BOUND'
 [IO.File]::WriteAllText($inputPath,(ConvertTo-ExampleInputJson $emptyBoundary),$utf8)
 $notCompleted=Run $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($notCompleted.Code-ne0-and$notCompleted.Value.reason-ceq'PREPARATION_INCOMPLETE') 'example-does-not-invent-completed-obligations'
 # This fixture has actually created/bound the project and loaded its complete rules.
 $completedPreparation=@($documented.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique)
 $completedResults=@($documented.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)
 $goodBoundary=New-ExampleBoundary $exampleReceipt (Id $exampleReceipt) 'FINALIZE_OUTPUT' $completedPreparation $completedResults @('USER_RESPONSE|fixture-current-result') 'NOT_REQUIRED' 'BOUND'
 [IO.File]::WriteAllText($inputPath,(ConvertTo-ExampleInputJson $goodBoundary),$utf8)
 $closedExample=Run $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($closedExample.Code-eq0-and$closedExample.Value.status-ceq'PASS') 'documented-boundary-real-consumer-finalize'
 foreach($bad in @(@{Field='publicDecisionIdentity';Value=('A'*64);Reason='PUBLIC_DECISION_IDENTITY'},@{Field='protectionState';Value='PASS';Reason='PROTECTION_STATE'})){
  $invalid=$goodBoundary|ConvertTo-Json -Depth 100|ConvertFrom-Json;$invalid.($bad.Field)=$bad.Value
  [IO.File]::WriteAllText($inputPath,(ConvertTo-ExampleInputJson $invalid),$utf8);$rejected=Run $resolver @{InputPath=$inputPath;AsJson=$true}
  Check ($rejected.Code-ne0-and$rejected.Text.Contains($bad.Reason)) ('documented-boundary-rejects-'+$bad.Field)
 }
 foreach($term in @('variable assignment','product launch','assignment','launch')){
  $negative=DiscoverCase @($term)
  Check (@($negative.selectedRuleBlocks.requirementId|Where-Object{$_-cin@('framework:PR_TASK_LAUNCH_AND_ROUTE','framework:PR_TASK_RESOURCE_SELECTION','framework:PR_CODEX_RESOURCE_ROUTE')}).Count-eq0) ('ambiguous-non-task-term-not-selected-'+$term)
 }
 foreach($term in @('task assignment','new assignment','新分派')){
  $positive=DiscoverCase @($term) (CurrentQueryFacets 'aiw:task-organization')
  Check (@($positive.selectedRuleBlocks.requirementId|Where-Object{$_-cin@('framework:PR_TASK_LAUNCH_AND_ROUTE','framework:PR_TASK_RESOURCE_SELECTION','framework:PR_CODEX_RESOURCE_ROUTE')}).Count-eq3) ('explicit-task-assignment-selects-three-'+$term)
 }
 # Frozen constructions made from these requests; downstream regression, not live model accuracy.
 foreach($case in @(
  @{Request='把这项工作分派给另一个任务，沿用当前目录。';Hints=@('task assignment');Select=$true},
  @{Request='如果以后需要再新建任务，现在只解释配置。';Hints=@('configuration explanation');Select=$false},
  @{Request='取消刚才的分派，继续说明变量赋值。';Hints=@('variable assignment');Select=$false},
  @{Request='报告中的“new assignment”是历史引用，不是当前请求。';Hints=@('configuration explanation');Select=$false}
 )){
  $facts=CurrentQueryFacets
  if($case.Select){$facts=CurrentQueryFacets 'aiw:task-organization'}
  $discovery.intentEnvelope.objective=$case.Request;$actual=DiscoverCase $case.Hints $facts
  Check (('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($actual.selectedRuleBlocks.requirementId))-eq$case.Select) ('request-construction-selection-'+$case.Request)
 }
 $originalTask=[IO.File]::ReadAllText($task)
 SaveText $task ($originalTask.Replace('phase=PLAN','phase=REVIEW').Replace('profile=STANDARD','profile=CRITICAL'))
 $discovery.expectedTaskIdentity=Id $task;$discovery.intentEnvelope.objective='正式独立审核此候选，不要修改。'
 $discovery.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$discovery.intentEnvelope.requestedResultKind='REVIEW_VERDICT'
 $formalReview=DiscoverCase @('formal review') (CurrentQueryFacets 'aiw:review' 'aiw:software' 'aiw:review-verdict' 'aiw:review')
 Check ('framework:PR_CRITICAL_REVIEW_INDEPENDENCE'-cin@($formalReview.selectedRuleBlocks.requirementId)-and'framework:PR_PERSPECTIVE_LENS_SELECTION'-cnotin@($formalReview.selectedRuleBlocks.requirementId)) 'formal-review-keeps-independent-review-without-retired-optional-lens-rule'
 $missingReviewRules=@(@('framework:PR_CODEX_TOOL_OPERATION_RESOLUTION','framework:PR_COMPACT_NON_INTERRUPT_DELIVERY')|Where-Object{$_-cnotin@($formalReview.selectedRuleBlocks.requirementId)})
 Check ($missingReviewRules.Count-eq0-and@(@('framework:PR_TASK_LAUNCH_AND_ROUTE','framework:PR_TASK_RESOURCE_SELECTION','framework:PR_CODEX_RESOURCE_ROUTE')|Where-Object{$_-cin@($formalReview.selectedRuleBlocks.requirementId)}).Count-eq0) 'formal-review-keeps-tool-and-return-without-new-organization-or-resource-selection'
 SaveText $task $originalTask;$discovery.expectedTaskIdentity=Id $task
 $discovery.intentEnvelope.requestedActionKind='NONE';$discovery.intentEnvelope.requestedResultKind='PLAN'
 $planWait=DiscoverCase @('planning while another task runs')
 Check ('framework:PR_TASK_COLLABORATION_BOUNDARY'-cin@($planWait.selectedRuleBlocks.requirementId)-and'framework:PR_FINAL_OUTPUT_CURRENT_RESULT'-cin@($planWait.selectedRuleBlocks.requirementId)-and'framework:PR_COMPACT_NON_INTERRUPT_DELIVERY'-cin@($planWait.selectedRuleBlocks.requirementId)) 'plan-wait-entry-loads-collaboration-and-terminal-rules'
 # Replay the natural Maintenance sample's actual source/test intent. The
 # isolated fixture supplies its own task and project bindings.
 $naturalTaskBase=[IO.File]::ReadAllText($task);$naturalIntentBase=$discovery.intentEnvelope|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30
 SaveText $task ($naturalTaskBase.Replace('role=TASK_OWNER; phase=PLAN','role=EXECUTOR; phase=IMPLEMENT').Replace('profile=STANDARD','profile=CRITICAL'))
 $discovery.expectedTaskIdentity=Id $task
 $naturalCases=@(
  @{Name='source';Action='SOURCE_WRITE';Result='IMPLEMENTATION_RESULT';Objective='在目标源码仓的三个限定文件内实现无依赖 CommonJS 耗时记录汇总工具、自动测试和使用说明；当前执行源码写入，后续执行本地测试并交由独立可见审核任务审核，最后交原 Owner 接受；不修改其他产品文件，不提交或发布。';Hints=@('耗时记录汇总','CommonJS 小工具实现','自动测试','限定交付文件','独立审核待后续')},
  @{Name='test';Action='TEST_RUN';Result='TEST_RESULT';Objective='执行限定小工具的 Node 内置测试，验证混合、零、空集、未知、重复 ID、非法输入、溢出及输入不变；然后准备独立审核并交原 Owner 接受；不修改其他产品文件，不提交或发布。';Hints=@('耗时记录汇总','Node 自动测试','输入边界验证','累计溢出验证','独立审核待后续')}
 )
 foreach($case in $naturalCases){
  if($case.Name-ceq'test'){SaveText $task (([IO.File]::ReadAllText($task)).Replace('phase=IMPLEMENT','phase=VERIFY'));$discovery.expectedTaskIdentity=Id $task}
  $discovery.intentEnvelope.objective=$case.Objective;$discovery.intentEnvelope.requestedActionKind=$case.Action;$discovery.intentEnvelope.requestedResultKind=$case.Result
  $facts=if($case.Name-ceq'test'){CurrentQueryFacets 'aiw:verification' 'aiw:software' 'aiw:report' 'aiw:verification'}else{CurrentQueryFacets 'aiw:implementation' 'aiw:software' 'aiw:code' 'aiw:implementation'}
  $actual=DiscoverCase $case.Hints $facts;$actualIds=@($actual.selectedRuleBlocks.requirementId)
  $scope=@($actual.selectedRuleBlocks|Where-Object requirementId -CEQ 'framework:PR_TASK_COLLABORATION_BOUNDARY')
  Check ($scope.Count-eq1-and$scope[0].fullText.Contains('wait_threads')-and$scope[0].fullText.Contains('PR_REVIEW_ROUTE_PREPARATION')-and'framework:PR_FINAL_OUTPUT_CURRENT_RESULT'-cnotin$actualIds-and'framework:PR_REVIEW_ROUTE_PREPARATION'-cnotin$actualIds-and'framework:PR_CRITICAL_REVIEW_INDEPENDENCE'-cnotin$actualIds) ('historical-'+$case.Name+'-keeps-collaboration-without-future-review-gate')
  # The historical sample put a deferred review in positive hints. Preserve
  # that replay above, then separately test the documented current-only input.
  # This transformation is fixture data, not measured LLM normalization.
  $current=DiscoverCase @($case.Hints|Where-Object {$_-cne'独立审核待后续'}) $facts
  Check ('framework:PR_TASK_COLLABORATION_BOUNDARY'-cin@($current.selectedRuleBlocks.requirementId)-and'framework:PR_TASK_LAUNCH_AND_ROUTE'-cnotin@($current.selectedRuleBlocks.requirementId)) ('normalized-'+$case.Name+'-keeps-collaboration-without-new-organization')
 }
 $discovery.intentEnvelope.objective='原写入包授权被拒绝；只报告当前阻塞和唯一下一动作。';$discovery.intentEnvelope.requestedActionKind='NONE';$discovery.intentEnvelope.requestedResultKind='USER_RESPONSE'
 $missingAuthority=DiscoverCase @('authorization result');$missingIds=@($missingAuthority.selectedRuleBlocks.requirementId)
 Check ('framework:PR_TASK_COLLABORATION_BOUNDARY'-cin$missingIds-and'framework:PR_FINAL_OUTPUT_CURRENT_RESULT'-cin$missingIds-and'framework:PR_TASK_LAUNCH_AND_ROUTE'-cnotin$missingIds) 'missing-authorization-return-keeps-collaboration-rule-without-new-launch'
 $discovery.intentEnvelope.objective='生产与测试 FINALIZE 已完成；现在新建独立 Reviewer 并一次交付冻结候选。';$discovery.intentEnvelope.requestedActionKind='REVIEW_ROUTE';$discovery.intentEnvelope.requestedResultKind='HANDOFF'
 $reviewRoute=DiscoverCase @('new assignment','formal review') (CurrentQueryFacets 'aiw:task-organization' 'aiw:software' 'aiw:handoff' 'aiw:review');$routeIds=@($reviewRoute.selectedRuleBlocks.requirementId)
 $reviewBlock=@($reviewRoute.selectedRuleBlocks|Where-Object requirementId -CEQ 'framework:PR_REVIEW_QUALIFICATION_AND_PLANNING')
 $routeBlock=@($reviewRoute.selectedRuleBlocks|Where-Object requirementId -CEQ 'framework:PR_REVIEW_ROUTE_PREPARATION')
 $hostBlock=@($reviewRoute.selectedRuleBlocks|Where-Object requirementId -CEQ 'framework:PR_CODEX_TOOL_OPERATION_RESOLUTION')
 # Compare the actual selection with each complete current owner block. Missing
 # or duplicate blocks stay diagnosable and fail the original aggregate case.
 $ownerMatches=@{}
 foreach($entry in @(
  @{Id='PR_REVIEW_QUALIFICATION_AND_PLANNING';File='REVIEW_AND_EVIDENCE.md'},
  @{Id='PR_REVIEW_ROUTE_PREPARATION';File='REVIEW_AND_EVIDENCE.md'},
  @{Id='PR_CODEX_TOOL_OPERATION_RESOLUTION';File='HOST_CODEX.md'}
 )){
  $text=[IO.File]::ReadAllText((Join-Path $fv $entry.File))
  $ownerMatches[$entry.Id]=@([regex]::Matches($text,('(?s)<!-- AIW-REQUIREMENT:'+ $entry.Id +':BEGIN -->(.*?)<!-- AIW-REQUIREMENT:'+ $entry.Id +':END -->')))
 }
 $qualificationText=if($reviewBlock.Count-eq1){[string]$reviewBlock[0].fullText}else{''}
 $routeText=if($routeBlock.Count-eq1){[string]$routeBlock[0].fullText}else{''}
 $hostText=if($hostBlock.Count-eq1){[string]$hostBlock[0].fullText}else{''}
 $routePreparations=@($routeBlock|ForEach-Object{$_.preparationRequirements})
 $routeResults=@($routeBlock|ForEach-Object{$_.resultRequirements})
 $allRouteObligations=@($reviewRoute.selectedRuleBlocks|ForEach-Object{@($_.preparationRequirements)+@($_.resultRequirements)})
 $clauses=[ordered]@{
  organizationSelected=('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin$routeIds)
  collaborationSelected=('framework:PR_TASK_COLLABORATION_BOUNDARY'-cin$routeIds)
  routePreparationSelected=('framework:PR_REVIEW_ROUTE_PREPARATION'-cin$routeIds)
  noCriticalExecutionGate=('framework:PR_CRITICAL_REVIEW_INDEPENDENCE'-cnotin$routeIds)
  qualificationSingleton=($reviewBlock.Count-eq1)
  routeSingleton=($routeBlock.Count-eq1)
  hostSingleton=($hostBlock.Count-eq1)
  qualificationComplete=($ownerMatches['PR_REVIEW_QUALIFICATION_AND_PLANNING'].Count-eq1-and$qualificationText-ceq$ownerMatches['PR_REVIEW_QUALIFICATION_AND_PLANNING'][0].Groups[1].Value.Trim())
  routeComplete=($ownerMatches['PR_REVIEW_ROUTE_PREPARATION'].Count-eq1-and$routeText-ceq$ownerMatches['PR_REVIEW_ROUTE_PREPARATION'][0].Groups[1].Value.Trim())
  hostComplete=($ownerMatches['PR_CODEX_TOOL_OPERATION_RESOLUTION'].Count-eq1-and$hostText-ceq$ownerMatches['PR_CODEX_TOOL_OPERATION_RESOLUTION'][0].Groups[1].Value.Trim())
  qualificationDelegatesSequence=$qualificationText.Contains('正常交审顺序唯一取PR_REVIEW_ROUTE_PREPARATION')
  finalizedProductionAndSelectedPreparation=($routeText.Contains('先完成本轮真实生产/自测FINALIZE、适用质量选择要求的当前成功自查')-and$routeText.Contains('LEGACY/选中或另有必需SELF阶段时仍需作者成功SELF')-and$routeText.Contains('C无SELF分支以TOOL_CONTRACT的productionFinalizeRef及完整候选准备成立'))
  actualDispatchAdmission=$routeText.Contains('真实REVIEW_ROUTE+HANDOFF意图取得必要组织、Review和HOST完整正文并ADMIT')
  noReverseCardAuthority=$routeText.Contains('不因旧生产前叙述向Owner反向索卡写权')
  routeNeedsNoFutureVerdict=$routeText.Contains('REVIEW_ROUTE结果证明真实分派，不要求未来verdict')
  candidateFrozen=('CANDIDATE_FROZEN'-cin$routePreparations)
  reviewPreparationBound=('REVIEW_PREPARATION_BOUND'-cin$routePreparations)
  reviewerIndependent=('REVIEWER_INDEPENDENCE_PROVEN'-cin$routePreparations)
  reviewCarrierQualified=('REVIEW_CARRIER_QUALIFIED'-cin$routePreparations)
  reviewMaterialsBound=('REVIEW_MATERIALS_BOUND'-cin$routePreparations)
  routeObserved=('REVIEW_ROUTE_OBSERVED'-cin$routeResults)
  noFutureVerdictObligation=('REVIEW_VERDICT_BOUND'-cnotin$allRouteObligations)
  hostRequiresObservation=$hostText.Contains('宿主明确要求创建后首次进度观察时')
  realIdBeforeSnapshot=$hostText.Contains('取得真实可用ID后仅做一次立即快照')
  unreadyEndsTurn=$hostText.Contains('未就绪结束本轮')
  timeoutOrCommentaryDoesNotWait=$hostText.Contains('超时/commentary不触发继续等待')
 }
 Write-Output ('OBSERVE|natural-review-route|'+([ordered]@{routeIds=$routeIds;qualificationCount=$reviewBlock.Count;routeCount=$routeBlock.Count;hostCount=$hostBlock.Count;ownerBlockCounts=@($ownerMatches.GetEnumerator()|Sort-Object Key|ForEach-Object{@{id=$_.Key;count=$_.Value.Count}});routePreparations=$routePreparations;routeResults=$routeResults;clauses=$clauses}|ConvertTo-Json -Depth 20 -Compress))
 Check (@($clauses.Values|Where-Object{-not$_}).Count-eq0) 'natural-review-route-loads-organization-review-and-bounded-host-observation'
 foreach($finding in @($false,$true)){
  $discovery.intentEnvelope.objective=if($finding){'独立审核当前候选并返回局部finding。'}else{'独立审核当前候选，无finding时返回通过结论。'}
  $discovery.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$discovery.intentEnvelope.requestedResultKind='REVIEW_VERDICT'
  $review=DiscoverCase @('formal review') (CurrentQueryFacets 'aiw:review' 'aiw:software' 'aiw:review-verdict' 'aiw:review');$reviewIds=@($review.selectedRuleBlocks.requirementId)
  Check ('framework:PR_TASK_COLLABORATION_BOUNDARY'-cin$reviewIds-and'framework:PR_CRITICAL_REVIEW_INDEPENDENCE'-cin$reviewIds-and'framework:PR_FINAL_OUTPUT_CURRENT_RESULT'-cin$reviewIds) ('natural-review-verdict-keeps-collaboration-and-review-'+$finding)
 }
 SaveText $task $naturalTaskBase;$discovery.expectedTaskIdentity=Id $task;$discovery.intentEnvelope=$naturalIntentBase
 $discovery.intentEnvelope.requestedResultKind='USER_RESPONSE'
 # TC3 must reject old execution inputs. Original TC2/1.16 actions remain
 # governed by their pinned runtimes; this fixture does not convert them.
 foreach($term in @('assignment','task assignment')){
  $legacy=[ordered]@{schemaVersion=1;mode='DISCOVER';projectRoot=$project;frameworkRoot=$framework;taskPath=$task;expectedProjectConfigIdentity=$discovery.expectedProjectConfigIdentity;expectedCorrectionsIdentity=$discovery.expectedCorrectionsIdentity;expectedTaskIdentity=Id $task;observedActor='actor';capabilities=@();objective=$term;actionKind='NONE';resultKind='USER_RESPONSE';exactPaths=@();hostEnforcementGrade='INSTRUCTION_BOUND';evaluationOnly=$true}
  SaveJson $inputPath $legacy;$legacyResult=Run $resolver @{InputPath=$inputPath;AsJson=$true}
  Check ($legacyResult.Code-ne0-and$legacyResult.Value.reason-ceq'INPUT_SCHEMA_VERSION') ('tc3-rejects-legacy-execution-input-'+$term)
 }
 $discovery.intentEnvelope.semanticHints=@('configuration explanation')
 # Real entrypoint cleanup: exact ordinary input, failure, attributes and binding.
 $cleanupNeighbor=Join-Path $runtime 'cleanup-neighbor.json';SaveText $cleanupNeighbor '{"keep":true}'
 $cleanupReceipt=Join-Path $runtime 'cleanup-receipt.json';SaveJson $cleanupReceipt $read.compactReceipt
 $neighborIdentity=Id $cleanupNeighbor;$receiptIdentity=Id $cleanupReceipt
 SaveJson $inputPath $discovery;$cleaned=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true;AsJson=$true}
 Check ($cleaned.Code-eq0-and-not(Test-Path -LiteralPath $inputPath)-and(Id $cleanupNeighbor)-ceq$neighborIdentity-and(Id $cleanupReceipt)-ceq$receiptIdentity) 'cleanup-version-success-exact-input-only-receipt-retained'
 $cleanupBoundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$cleanupReceipt;expectedDiscoverReceiptIdentity=$receiptIdentity;preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 SaveJson $inputPath $cleanupBoundary;$failedCleanup=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true;AsJson=$true}
 Check ($failedCleanup.Code-ne0-and$failedCleanup.Value.status-ceq'BLOCKED'-and$failedCleanup.Value.reason-ceq'PREPARATION_INCOMPLETE'-and-not(Test-Path -LiteralPath $inputPath)-and(Id $cleanupNeighbor)-ceq$neighborIdentity-and(Id $cleanupReceipt)-ceq$receiptIdentity) 'cleanup-version-failure-visible-and-exact-input-deleted'
 SaveJson $inputPath $discovery;$readonlyIdentity=Id $inputPath;$ordinaryAttributes=[IO.File]::GetAttributes($inputPath)
 [IO.File]::SetAttributes($inputPath,($ordinaryAttributes-bor[IO.FileAttributes]::ReadOnly))
 try{
  $readonly=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true;AsJson=$true}
  Check ($readonly.Code-eq0-and$readonly.Value.status-ceq$cleaned.Value.status-and$readonly.Value.inputCleanup.status-ceq'PARTIAL_FAILURE'-and$readonly.Value.inputCleanup.failures[0].kind-ceq'IO_ERROR'-and(Test-Path -LiteralPath $inputPath)-and(Id $inputPath)-ceq$readonlyIdentity-and([IO.File]::GetAttributes($inputPath)-band[IO.FileAttributes]::ReadOnly)-ne0-and(Id $cleanupNeighbor)-ceq$neighborIdentity-and(Id $cleanupReceipt)-ceq$receiptIdentity) 'cleanup-version-readonly-failure-is-separate-from-established-result'
  $readonlyDefault=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true}
  $cleanupLine=@($readonlyDefault.Text -split "`n"|Where-Object{$_.StartsWith('AIW-CLEANUP|')})
  $defaultObservation=$cleanupLine[0].Substring('AIW-CLEANUP|'.Length)|ConvertFrom-Json
  Check ($readonlyDefault.Code-eq0-and$cleanupLine.Count-eq1-and$defaultObservation.kind-ceq'inputCleanup'-and$defaultObservation.status-ceq'PARTIAL_FAILURE'-and$defaultObservation.failures[0].kind-ceq'IO_ERROR'-and$inputPath-cin$defaultObservation.remaining-and(Id $inputPath)-ceq$readonlyIdentity) 'cleanup-default-model-output-exposes-readonly-remaining-without-business-rollback'
 }finally{if(Test-Path -LiteralPath $inputPath){[IO.File]::SetAttributes($inputPath,$ordinaryAttributes)}}
 $wrongActorInput=Join-Path $control 'runtime/EFFICIENCY-001/other-actor/cleanup.json';SaveJson $wrongActorInput $discovery;$wrongActorIdentity=Id $wrongActorInput
 $wrongActorCleanup=Run $resolver @{InputPath=$wrongActorInput;DeleteInputOnExit=$true;AsJson=$true}
 Check ($wrongActorCleanup.Code-ne0-and(Id $wrongActorInput)-ceq$wrongActorIdentity-and(Id $cleanupNeighbor)-ceq$neighborIdentity) 'cleanup-version-wrong-actor-scope-rejected-and-retained'
 # The existing batch algorithm is now exercised through the version owner.
 Import-Module (Join-Path $fv 'scripts/WorkflowDelivery.psm1') -Force
 $releaseRoot=Join-Path $runtime 'explicit-batch';$null=[IO.Directory]::CreateDirectory($releaseRoot)
 $a=Join-Path $releaseRoot 'report [1].txt';$b=Join-Path $releaseRoot '带空格 文件.txt';$kept=Join-Path $releaseRoot 'next-consumer.txt'
 foreach($p in @($a,$b,$kept)){SaveText $p 'Fresh fixture payload.'}
 $outside=Join-Path $runtime 'outside-batch.txt';SaveText $outside 'Outside this exact batch.'
 $rejected=Remove-AiwConsumedRuntimeFiles $releaseRoot @($a,$outside)
 Check ($rejected.status-ceq'REJECTED'-and$rejected.failures[0].kind-ceq'FRAMEWORK_REJECTED'-and[IO.File]::Exists($a)) 'batch-whole-scope-rejection-before-first-delete'
 $rejected=Remove-AiwConsumedRuntimeFiles $releaseRoot @($a,$releaseRoot)
 Check ($rejected.status-ceq'REJECTED'-and[IO.File]::Exists($a)) 'batch-directory-cannot-be-file-target'
 $removed=Remove-AiwConsumedRuntimeFiles $releaseRoot @($a,$b,$a) -RetainedPath @($kept)
 Check ($removed.status-ceq'PASS'-and$removed.removed.Count-eq2-and$removed.removedBytes-gt0-and[IO.File]::Exists($kept)) 'batch-literal-names-dedup-bytes-and-unlisted-preservation'
 $generation=Join-Path $releaseRoot 'reused-input.json';SaveJson $generation @{generation='consumed'};$oldGeneration=Id $generation
 SaveJson $generation @{generation='new owner'};$newGeneration=Id $generation
 $changed=Remove-AiwConsumedRuntimeFiles $releaseRoot @($generation) -ExpectedObject @([pscustomobject]@{path=$generation;identity=$oldGeneration})
 Check ($changed.status-ceq'RETAINED'-and$changed.removed.Count-eq0-and$changed.observations[0].reason-ceq'CONSUMED_OBJECT_CHANGED'-and(Id $generation)-ceq$newGeneration) 'batch-consumed-byte-binding-keeps-reused-input-generation'
 $matching=Remove-AiwConsumedRuntimeFiles $releaseRoot @($generation) -ExpectedObject @([pscustomobject]@{path=$generation;identity=$newGeneration})
 Check ($matching.status-ceq'PASS'-and$matching.removed.Count-eq1-and-not[IO.File]::Exists($generation)) 'batch-matching-consumed-generation-releases'
 $again=Remove-AiwConsumedRuntimeFiles $releaseRoot @($a,$b)
 Check ($again.status-ceq'PASS'-and$again.alreadyAbsent.Count-eq2) 'batch-already-absent-without-retry-loop'
 $locked=Join-Path $releaseRoot 'locked.txt';$ordinary=Join-Path $releaseRoot 'ordinary.txt';$list=Join-Path $releaseRoot 'consumed.json'
 SaveText $locked 'Locked fixture.';SaveText $ordinary 'Ordinary fixture.';SaveJson $list @($locked,$ordinary)
 $listIdentity=Id $list;$hold=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{$partial=Remove-AiwConsumedRuntimeFiles $releaseRoot -LiteralPath @($list) -ConsumedPathListPath $list}finally{$hold.Dispose()}
 Check ($partial.status-ceq'PARTIAL_FAILURE'-and$partial.removed.Count-eq1-and$partial.remaining.Count-eq2-and(Id $list)-ceq$listIdentity-and[IO.File]::Exists($locked)-and-not[IO.File]::Exists($ordinary)-and-not$partial.pathListReleased) 'batch-real-sharing-failure-preserves-original-list-and-actual-remaining'
 Check (@($partial.remaining|Where-Object{$_-ceq$list}).Count-eq1) 'batch-overlapping-literal-list-reserved-until-all-members-succeed'
 $released=Remove-AiwConsumedRuntimeFiles $releaseRoot -ConsumedPathListPath $list
 Check ($released.status-ceq'PASS'-and$released.pathListReleased-and-not[IO.File]::Exists($list)) 'batch-original-list-consumed-only-after-members-succeed'
 $list=Join-Path $releaseRoot 'still-used.json';SaveJson $list @($kept)
 $retained=Remove-AiwConsumedRuntimeFiles $releaseRoot -ConsumedPathListPath $list -RetainedPath @($kept)
 Check ($retained.status-ceq'RETAINED'-and-not$retained.pathListReleased-and[IO.File]::Exists($list)-and[IO.File]::Exists($kept)) 'batch-still-used-member-keeps-its-list'
 $child=Join-Path $releaseRoot 'empty/child';$null=[IO.Directory]::CreateDirectory($child);$payload=Join-Path $child 'payload.txt';SaveText $payload 'Consumed.'
 $closed=Remove-AiwConsumedRuntimeFiles $releaseRoot @($payload) -EmptyDirectoryPath @((Split-Path $child -Parent),$child)
 Check ($closed.status-ceq'PASS'-and$closed.directoriesRemoved.Count-eq2) 'batch-explicit-empty-directories-close-deepest-first'
 $nonempty=Remove-AiwConsumedRuntimeFiles $runtime @() -EmptyDirectoryPath @($releaseRoot)
 Check ($nonempty.status-ceq'PARTIAL_FAILURE'-and[IO.File]::Exists($kept)) 'batch-nonempty-directory-never-recursively-removed'
 $link=Join-Path $releaseRoot 'link';$null=New-Item -ItemType Junction -Path $link -Target $runtime
 try{$unsafe=Remove-AiwConsumedRuntimeFiles $releaseRoot @($kept,(Join-Path $link 'outside-batch.txt'));Check ($unsafe.status-ceq'REJECTED'-and[IO.File]::Exists($kept)) 'batch-reparse-group-rejected-before-first-delete'}finally{Remove-Item -LiteralPath $link}
 $discovery.intentEnvelope.objective='Give this work another task, using the local directory.'
 $launch=DiscoverCase @('task assignment','resource selection') (CurrentQueryFacets 'aiw:task-organization');Check ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($launch.selectedRuleBlocks.requirementId)-and'framework:PR_TASK_RESOURCE_SELECTION'-cin@($launch.selectedRuleBlocks.requirementId)-and'framework:PR_CODEX_RESOURCE_ROUTE'-cin@($launch.selectedRuleBlocks.requirementId)) 'normalized-synonym-assignment-loads-organization-and-resource'
 $discovery.intentEnvelope.objective='The edits are complete; now report their remaining artifact disposition.'
 $written=DiscoverCase @('changed output disposition');Check ('framework:PR_TASK_CHANGED_OUTPUT_DISPOSITION'-cin@($written.selectedRuleBlocks.requirementId)) 'none-after-write-keeps-disposition'
 $discovery.intentEnvelope.objective='Quoted history: assignment, resource change, formal review; all were cancelled.';$cancelled=DiscoverCase @('configuration explanation');Check ((@($cancelled.selectedRuleBlocks.requirementId)-join'|') -ceq ($ids-join'|')) 'objective-negation-history-cancellation-not-trigger-pool'
 $discovery.intentEnvelope.objective='If we later need another task, create it then; explain this configuration now.';$conditional=DiscoverCase @('configuration explanation');Check ((@($conditional.selectedRuleBlocks.requirementId)-join'|') -ceq ($ids-join'|')) 'inactive-conditional-assignment-does-not-load-organization'
 $discovery.intentEnvelope.requestedResultKind='TERMINAL';$reply=DiscoverCase @('message delivery','controller exception') (CurrentQueryFacets 'aiw:closure' 'aiw:software' 'aiw:report' 'aiw:closure');Check ('framework:PR_COMPACT_NON_INTERRUPT_DELIVERY'-cin@($reply.selectedRuleBlocks.requirementId)) 'explicit-terminal-keeps-delivery';$discovery.intentEnvelope.requestedResultKind='USER_RESPONSE'
 $discovery.intentEnvelope.ambiguityState='UNKNOWN';$known=DiscoverCase @('unresolved meaning');Check ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cnotin@($known.selectedRuleBlocks.requirementId)) 'ambiguity-does-not-override-known-facet-mismatch'
 $unknownFacets=[ordered]@{};foreach($dimension in @('domain','workType','deliverableType','stage')){$unknownFacets[$dimension]=[ordered]@{state='UNKNOWN';values=@()}}
 $unknown=DiscoverCase @('unresolved meaning') $unknownFacets;Check ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($unknown.selectedRuleBlocks.requirementId)) 'unknown-facets-retain-conservative-conditional-load';$discovery.intentEnvelope.ambiguityState='CLEAR'
 $configPath=Join-Path $control 'project.json';$config=Get-Content -Raw -LiteralPath $configPath|ConvertFrom-Json
 $config.sourceBindings=@([pscustomobject]@{id='project-knowledge';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator='.ai-workspace/knowledge'});decisionLocator='fixture:explicit-knowledge-scope'})
 $config.frameworkCapabilities|Add-Member KNOWLEDGE_REFERENCE ([pscustomobject]@{enabled=$true;sources=@([pscustomobject]@{id='project';bindingId='project-knowledge';indexLocator='.ai-workspace/knowledge/index.json';selectionHints=@();updatePolicy='FOLLOW';revisionSelector='.ai-workspace/knowledge/index.json'})});SaveJson $configPath $config;$discovery.expectedProjectConfigIdentity=Id $configPath;$discovery.capabilities=@('KNOWLEDGE_REFERENCE')
 $enabled=DiscoverCase @('configuration explanation');$noImpact=DiscoverCase @('configuration explanation');$impact=DiscoverCase @('knowledge query impact') (CurrentQueryFacets 'aiw:knowledge-maintenance' 'aiw:knowledge')
 Check ('framework:PR_KNOWLEDGE_IMPACT_MAINTENANCE'-cnotin@($enabled.selectedRuleBlocks.requirementId)-and'framework:PR_KNOWLEDGE_IMPACT_MAINTENANCE'-cnotin@($noImpact.selectedRuleBlocks.requirementId)-and'framework:PR_KNOWLEDGE_IMPACT_MAINTENANCE'-cin@($impact.selectedRuleBlocks.requirementId)) 'knowledge-enabled-and-no-impact-distinct-from-real-query-impact'
 $config.frameworkCapabilities.PSObject.Properties.Remove('KNOWLEDGE_REFERENCE');SaveJson $configPath $config;$discovery.expectedProjectConfigIdentity=Id $configPath;$discovery.capabilities=@()
 $discovery.intentEnvelope.semanticHints=@('configuration explanation');SaveJson $inputPath $discovery;$receiptPath=Join-Path $runtime 'saved.json';$saved=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$receiptPath;AsJson=$true}
 Check ($saved.Code-eq0-and$saved.Value.savedCompactReceipt.identity-ceq(Id $receiptPath)-and-not[IO.File]::ReadAllText($receiptPath).Contains('fullText')) 'compact-save-only-receipt-exact-identity'
 $savedId=Id $receiptPath;$again=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$receiptPath;AsJson=$true};Check ($again.Code-ne0-and(Id $receiptPath)-ceq$savedId) 'compact-existing-file-refused-without-overwrite'
 $same=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$inputPath;AsJson=$true};Check ($same.Code-ne0) 'compact-input-overwrite-refused'
 $bad=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=(Join-Path $temp 'escape.json');AsJson=$true};Check ($bad.Code-ne0-and-not(Test-Path -LiteralPath (Join-Path $temp 'escape.json'))) 'compact-outside-runtime-refused'
 $missingParent=Join-Path $runtime 'missing/saved.json';$badParent=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$missingParent;AsJson=$true};Check ($badParent.Code-ne0-and-not(Test-Path -LiteralPath $missingParent)) 'compact-does-not-create-alternate-parent'
 $b=[ordered]@{schemaVersion=3;mode='FINALIZE_OUTPUT';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=$savedId;preparationReceipts=@($saved.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@($saved.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique);deliveryReceipts=@('DELIVERED');publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()};SaveJson $inputPath $b;$final=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($final.Code-eq0) 'saved-compact-consumed-by-real-finalize'
 $finalAttributes=[IO.File]::GetAttributes($inputPath);[IO.File]::SetAttributes($inputPath,($finalAttributes-bor[IO.FileAttributes]::ReadOnly))
 try{
  $defaultFinal=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true}
  $cleanupLine=@($defaultFinal.Text -split "`n"|Where-Object{$_.StartsWith('AIW-CLEANUP|')});$cleanupObservation=$cleanupLine[0].Substring('AIW-CLEANUP|'.Length)|ConvertFrom-Json
  Check ($defaultFinal.Code-eq0-and$defaultFinal.Text.Contains('PASS|FINALIZE_OUTPUT|')-and$cleanupObservation.status-ceq'PARTIAL_FAILURE'-and$inputPath-cin$cleanupObservation.remaining-and$cleanupObservation.failures[0].kind-ceq'IO_ERROR') 'cleanup-default-finalize-shows-partial-result-and-preserves-business-pass'
 }finally{[IO.File]::SetAttributes($inputPath,$finalAttributes)}
 $sourcePath=Join-Path $project 'docs/shared.md';SaveText $sourcePath "Intro`n<!-- A -->`nALPHA_BODY`n<!-- /A -->`n<!-- B -->`nBETA_BODY`n<!-- /B -->"
 $selector=[ordered]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@('architecture')}
 Import-Module (Join-Path $fv 'scripts/ContentSources.psm1') -Force
 $config.sourceBindings=@([pscustomobject]@{id='standard-docs';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='FILE';locator='docs/shared.md'});decisionLocator='fixture:explicit-standard-scope'})
 SaveJson $configPath $config;$discovery.expectedProjectConfigIdentity=Id $configPath
 function RefreshStandardDescriptor($Descriptor){
  foreach($document in $Descriptor.documents){$document.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) $config.sourceBindings}
  $Descriptor.revision=Get-AiwContentRevision $Descriptor $config.sourceBindings;$Descriptor.itemIdentity=Get-AiwContentItemIdentity $Descriptor
 }
 foreach($name in @('A','B')){
  $document=[pscustomobject]@{sourceId=$name;bindingId='standard-docs';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator='docs/shared.md';identity=Id $sourcePath;mode='MARKED_SECTION';sectionStart=('<!-- '+$name+' -->');sectionEnd=('<!-- /'+$name+' -->');dependencies=@()}
  $source=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='standard-docs';itemId=('STANDARD_'+$name);revision=$document.revision;itemIdentity='';rootSourceId=$name;documents=@($document)};RefreshStandardDescriptor $source
  $policy.rules+=@([ordered]@{ruleId=('STANDARD_'+$name);requirementReason='Independent obligation from shared document';selectors=$selector;preparationRequirements=@('PREP_'+$name);resultRequirements=@('RESULT_'+$name);decisionLocator='fixture';source=$source})
 }
 SaveJson $policyPath $policy;$normal=DiscoverCase @('architecture');$texts=($normal.selectedRuleBlocks.fullText-join"`n");Check ($texts.Contains('ALPHA_BODY')-and$texts.Contains('BETA_BODY')) 'same-source-normal-sections-both-complete'
 SaveText $sourcePath ([IO.File]::ReadAllText($sourcePath)+"CURRENT_DRIFT_BODY`n")
 $unadoptedDrift=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($unadoptedDrift.Code-ne0-and$unadoptedDrift.Text.Contains('CONTENT_IDENTITY_DRIFT')) 'changed-source-cannot-silently-follow-latest-bytes'
 foreach($rule in $policy.rules){$document=$rule.source.documents[0];$document.identity=Id $sourcePath;$document.mode='FULL_FILE';$document.sectionStart='NOT_APPLICABLE';$document.sectionEnd='NOT_APPLICABLE';RefreshStandardDescriptor $rule.source}
 SaveJson $policyPath $policy
 $drift=DiscoverCase @('configuration explanation');$rules=@($drift.selectedRuleBlocks|Where-Object{$_.source-ceq'PROJECT_POLICY'});$text=$rules.fullText-join"`n"
 Check ($rules.Count-eq2-and[regex]::Matches($text,'CURRENT_DRIFT_BODY').Count-eq2-and-not$text.Contains('PROJECT-SOURCE-REFERENCE')) 'machine-result-retains-every-selected-complete-body'
 Import-Module (Join-Path $fv 'scripts/ProcessRequirementDisplay.psm1') -Force
 $projection=Get-AiwProcessDisplay $drift
 $displayText=$projection.text
 Check ([regex]::Matches($displayText,'CURRENT_DRIFT_BODY').Count-eq1) 'same-source-drift-display-full-body-once'
 Check ('PREP_A'-cin@($rules.preparationRequirements)-and'PREP_B'-cin@($rules.preparationRequirements)-and'RESULT_A'-cin@($rules.resultRequirements)-and'RESULT_B'-cin@($rules.resultRequirements)) 'same-source-dedup-keeps-every-obligation'
 $old=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($old.Code-eq0) 'drift-current-discover-remains-available'
 SaveJson $inputPath $b;$stale=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($stale.Code-ne0) 'pre-drift-receipt-cannot-finalize'
 $checker=Join-Path $versionRoot 'scripts/check-task-card.ps1';$card=Join-Path $temp 'tasks/archive/CLOSE-001.md'
 $base="# CLOSE-001 — fixture`n- Task schema: 2.0.0`n- Owner: actor`n- Work route: actor=actor; role=TASK_OWNER; phase=VERIFY`n- Range summary: profile=STANDARD; lifecycle=CLOSED; expected_paths=[]; actual_paths=[]`n- Closure outcome: SUCCESS`n- Closure evidence: reviewed-result`n- Remaining obligations: NONE`n- Artifact disposition: retained; Git deferred in owning task`n- Writer / reviewer / authorization: NONE / NONE / NONE"
 foreach($outcome in @('SUCCESS','CANCELLED','SUPERSEDED')){$text=$base.Replace('Closure outcome: SUCCESS',('Closure outcome: '+$outcome));if($outcome-ceq'SUPERSEDED'){$text=$text.Replace('Remaining obligations: NONE','Remaining obligations: successor TASK-002')};SaveText $card $text;$r=Run $checker @{TaskPath=$card};Check ($r.Code-eq0-and$r.Text.Contains('closure='+$outcome)) ('task-closure-'+$outcome)}
 $critical=$base.Replace('profile=STANDARD; lifecycle=CLOSED;','profile=CRITICAL; lifecycle=CLOSED; current_exact=fixture-v1;')+"`n- Phase gate: FALSE`n- Proportionality: NOT_APPLICABLE; reason=bounded review of existing behavior"
 SaveText $card $critical;$r=Run $checker @{TaskPath=$card};Check ($r.Code-eq0) 'critical-minimal-closure-template-without-phase-matrix-or-viewpoint-quota'
 foreach($text in @($base.Replace('Closure outcome: SUCCESS','Closure outcome: WAITING'),$base.Replace('Closure evidence: reviewed-result','Closure evidence: PENDING'),$base.Replace('NONE / NONE / NONE','actor / NONE / ACTIVE'))){SaveText $card $text;$r=Run $checker @{TaskPath=$card};Check ($r.Code-ne0) ('task-invalid-closure-'+$passed)}
 # Current Maintenance root adapters and TC3 TARGET write closure. Original
 # legacy runtimes are exercised by the separate major-adoption bridge.
 $repositoryRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
 # Execute each real root consumer's projection AST, including an old module
 # without the export while the current helper is still loaded globally.
 $currentModule=Import-Module (Join-Path $fv 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru
 $legacyModule=New-Module -Name 'LegacyProjectionFixture' -ScriptBlock {function LegacyFixture { };Export-ModuleMember -Function LegacyFixture}
 $semanticIntent=[pscustomobject]@{objective='Update the approved root source. Do not perform any new assignment or resource selection.';semanticHints=@('root source update');externalHints=@('Cancelled assignment and resource selection')}
 foreach($consumer in @(@{Path='scripts/upgrade-project.ps1';Variable='$semanticObjective'})){
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repositoryRoot $consumer.Path),[ref]$null,[ref]$null)
  $assignment=@($ast.FindAll({param($node) $node-is[Management.Automation.Language.AssignmentStatementAst]-and$node.Left.Extent.Text-ceq$consumer.Variable},$true))
  Check ($assignment.Count-eq1) ('EFF-01-actual-consumer-projection-found-'+$consumer.Path)
  $projector=[scriptblock]::Create($assignment[0].Right.Extent.Text)
  $actual=& {param($projection,$consumed,$intent) $composerModule=$consumed;$module=$consumed;& $projection} $projector $currentModule $semanticIntent
  Check ($actual-ceq'root source update') ('EFF-01-current-consumer-excludes-cancelled-text-'+$consumer.Path)
  $legacy=& {param($projection,$consumed,$intent) $composerModule=$consumed;$module=$consumed;& $projection} $projector $legacyModule $semanticIntent
  $legacyExpected=($semanticIntent.objective+' '+[string]::Join(' ',@($semanticIntent.semanticHints+$semanticIntent.externalHints))).Trim()
  Check ($legacy-ceq$legacyExpected) ('EFF-01-consumed-legacy-contract-survives-loaded-new-helper-'+$consumer.Path)
 }


 # A separate immutable fixture package governs source writes to the sibling
 # development repository. Synthetic installation metadata only sets up this
 # adapter test; actual registration/adoption is covered by the root suites.
 $fixedRuntime=Join-Path $temp 'fixed-runtime';$null=New-Item -ItemType Directory -Path $fixedRuntime
 foreach($relative in @('README.md','scripts','framework')){Copy-Item -LiteralPath (Join-Path $framework $relative) -Destination (Join-Path $fixedRuntime $relative) -Recurse}
 Copy-Item -LiteralPath (Join-Path $repositoryRoot 'framework/user-package/AGENTS.md') -Destination (Join-Path $fixedRuntime 'AGENTS.md')
 [string[]]$fixedPaths=@(Get-ChildItem -LiteralPath $fixedRuntime -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($fixedRuntime,$_.FullName).Replace('\','/')});[Array]::Sort($fixedPaths,[StringComparer]::Ordinal)
 $fixedFiles=@($fixedPaths|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $fixedRuntime $_))}})
 $fixedRows=@($fixedFiles|ForEach-Object{$_.path+'='+$_.identity})
 $fixedCanonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($fixedRows-join[char]10)+[char]10)))
 SaveJson (Join-Path $fixedRuntime 'PACKAGE_MANIFEST.json') ([ordered]@{schemaVersion=2;frameworkVersion='2.0.0';provisional=$false;canonical=$fixedCanonical;files=$fixedFiles;distributionId='2.0.0-release'})
 Import-Module (Join-Path $fixedRuntime 'scripts/ProjectAdoptionState.psm1') -Force
 $fixedBinding=Get-AiwDistributionBinding $fixedRuntime '2.0.0' -Required
 & git -C $framework init -q
 $maintenance=Join-Path $temp 'maintenance';$null=New-Item -ItemType Directory -Path $maintenance;& git -C $maintenance init -q
 $mc=Join-Path $maintenance '.ai-workspace';$mr=Join-Path $mc 'runtime/ROOT-001/actor';$null=New-Item -ItemType Directory -Path $mr -Force
 SaveJson (Join-Path $mc 'runtime/project-adoption/register/state.json') ([ordered]@{state='COMPLETE';transactionComplete=$true;metadata=@{distributionBinding=$fixedBinding}})
 $mt=Join-Path $mc 'tasks/active/ROOT-001.md';SaveText $mt "# ROOT-001 — root fixture`n- Task schema: 2.0.0`n- Owner: actor`n- Work route: actor=actor; role=CONTROLLER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]"
 $cfg=[ordered]@{schemaVersion=7;id='maintenance-fixture';displayName='Fixture';controlPlaneLayout='framework-maintenance-sibling';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'};frameworkTarget=[ordered]@{repositoryId='fixture-framework';siblingDirectory='framework';routineExcludedPaths=@()}}
 SaveJson (Join-Path $mc 'project.json') $cfg
 Check ($null-eq(Get-AiwFixedAdoptedRelease -ProjectRoot $maintenance -FrameworkRoot $fixedRuntime)) 'maintenance-weak-locator-does-not-grant-fixed-source'
 SaveJson (Join-Path $mc 'controller.json') ([ordered]@{schemaVersion=1;projectId='maintenance-fixture';controllerId='actor';controllerEpoch=1;state='CURRENT'})
 SaveJson (Join-Path $mc 'corrections.json') ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='maintenance-fixture';corrections=@()})
 SaveText (Join-Path $mc 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 $mpolicy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='maintenance-fixture';rules=@([ordered]@{ruleId='FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY';requirementReason='Keep control and target separate';effectiveRule='Control owns authority; target owns development source.';selectors=[ordered]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture'})};SaveJson (Join-Path $mc 'process-policy.json') $mpolicy
 $object=Join-Path $framework 'fixture-object.txt';SaveText $object 'before'
 $package=[ordered]@{schemaVersion=2;frameworkVersion='2.0.0';taskId='ROOT-001';profile='STANDARD';lifecycle='ACTIVE';owner='actor';issuer='actor';issuerRole='PROJECT_CONTROLLER';grantee='actor';bundle='ROOT_FIXTURE';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Id $mt;actions=@('SOURCE_WRITE');exactPaths=@('fixture-object.txt');objectIdentities=@([ordered]@{path='fixture-object.txt';identity=Id $object});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','REPOSITORY_CHANGE','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=Id (Join-Path $mc 'project.json');repositoryId='fixture-framework';issuerControllerId='actor';issuerControllerEpoch=1;controllerControlIdentity=Id (Join-Path $mc 'controller.json')}
 $ap=Join-Path $mr 'authorization.json';SaveJson $ap $package
 $rootInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$maintenance;frameworkRoot=$framework;taskPath=$mt;expectedProjectConfigIdentity=Id (Join-Path $mc 'project.json');expectedCorrectionsIdentity=Id (Join-Path $mc 'corrections.json');expectedTaskIdentity=Id $mt;observedActor='actor';capabilities=@();exactPaths=@('fixture-object.txt');forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$ap;expectedAuthorizationIdentity=Id $ap;userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=2;objective='Change one fixture target object';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('changed output disposition');pathHints=@();capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR';facets=(CurrentQueryFacets 'aiw:implementation' 'aiw:governance' 'aiw:code' 'aiw:implementation')};evaluationOnly=$false}
 $rootInput.frameworkRoot=$fixedRuntime
 $rootAdapter=Join-Path $fixedRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1';$ri=Join-Path $mr 'input.json';$rr=Join-Path $mr 'saved.json'
 $oldDirectory=[Environment]::CurrentDirectory;Push-Location $maintenance
 try{
  [Environment]::CurrentDirectory=$maintenance
   $targetExample=New-ExampleMaintenanceDiscover $rootInput $rootInput.intentEnvelope
   Check ($targetExample.schemaVersion-eq5-and$targetExample.contextType-ceq'TASK'-and$targetExample.intentEnvelope.schemaVersion-eq2) 'documented-maintenance-target-keeps-current-TC4-input5'
   [IO.File]::WriteAllText($ri,(ConvertTo-ExampleInputJson $targetExample),$utf8)
   $fixedReader=@(Import-Module (Join-Path $fixedRuntime 'framework/versions/2.0.0/scripts/ReleaseValidation.psm1') -PassThru)[0]
   $fallbackEvents=[Collections.Generic.List[object]]::new();$fallbackSink={param($event) $fallbackEvents.Add($event)}.GetNewClosure()
   $rd=& $fixedReader.ExportedCommands['Invoke-AiwReleaseQualificationScope'] -DiagnosticCallback $fallbackSink -Body {Run $rootAdapter @{InputPath=$ri;CompactReceiptPath=$rr;DeleteInputOnExit=$true;AsJson=$true}}
   if($rd.Code-ne0){throw ('ROOT_DISCOVER|'+$rd.Text)}
   Check (@($fallbackEvents|Where-Object stage -CEQ 'qualification-core-start').Count-ge1-and@($fallbackEvents|Where-Object stage -CEQ 'fixed-adopted-source').Count-eq0) 'maintenance-weak-locator-real-discover-uses-full-qualification'
   $targetOutput=Read-ExampleDiscoverOutput $rd.Value
   Check (@($targetOutput.selectedRuleBlocks).Count-gt0-and@($targetOutput.selectedRuleBlocks|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.fullText)}).Count-eq0-and-not($targetOutput.compactReceipt|ConvertTo-Json -Depth 100).Contains('fullText')-and$targetOutput.savedCompactReceipt.identity-ceq(Id $rr)) 'documented-maintenance-output-fulltext-and-saved-compact'
  Check ($rd.Value.compactReceipt.schemaVersion-eq4-and$rd.Value.savedCompactReceipt.identity-ceq(Id $rr)-and$rd.Value.compactReceipt.binding.projectRoot-ceq$maintenance) 'maintenance-target-DISCOVER5-saves-compact4-with-control-root'
  Check (-not(Test-Path -LiteralPath $ri)-and(Test-Path -LiteralPath $ap)-and(Test-Path -LiteralPath $rr)) 'cleanup-maintenance-target-discover-preserves-package-and-last-consumer-receipt'
  $rb=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$rr;expectedDiscoverReceiptIdentity=Id $rr;preparationReceipts=@($rd.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  SaveJson $ri $rb;$ra=Run $rootAdapter @{InputPath=$ri;AsJson=$true};if($ra.Code-ne0){throw ('ROOT_ADMIT|'+$ra.Text)}
  SaveText $object 'after';$rb.mode='FINALIZE_OUTPUT';$rb.resultReceipts=@($rd.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|fixture-object.txt|'+(Id $object));SaveJson $ri $rb;$rf=Run $rootAdapter @{InputPath=$ri;AsJson=$true}
  Check ($rf.Code-eq0) 'maintenance-saved-target-compact-real-admit-write-finalize'
  Check ((Get-AiwDistributionBinding $fixedRuntime '2.0.0' -Required).contentIdentity-ceq$fixedBinding.contentIdentity-and$rd.Value.compactReceipt.sourceLocators.frameworkRoot-ceq$fixedRuntime) 'source-write-keeps-separate-fixed-runtime-unchanged'
  $rootInput.authorizationPackagePath='NOT_REQUIRED';$rootInput.expectedAuthorizationIdentity='NOT_REQUIRED';$rootInput.exactPaths=@();$rootInput.intentEnvelope.requestedActionKind='NONE';$rootInput.intentEnvelope.requestedResultKind='USER_RESPONSE';$rootInput.intentEnvelope.semanticHints=@('configuration explanation');$rootInput.intentEnvelope.mutationHints=@();$rootInput.intentEnvelope.facets=CurrentQueryFacets;$rootInput.evaluationOnly=$true;SaveJson $ri $rootInput
  $rr2=Join-Path $mr 'saved-v2.json';$rc=Run $rootAdapter @{InputPath=$ri;CompactReceiptPath=$rr2;DeleteInputOnExit=$true;AsJson=$true};if($rc.Code-ne0){throw ('ROOT_CONTROL|'+$rc.Text)}
  Check ($rc.Value.compactReceipt.schemaVersion-eq3-and$rc.Value.savedCompactReceipt.identity-ceq(Id $rr2)) 'maintenance-control-DISCOVER4-saves-compact3'
  Check (-not(Test-Path -LiteralPath $ri)-and(Test-Path -LiteralPath $rr)-and(Test-Path -LiteralPath $rr2)) 'cleanup-maintenance-control-discover-exact-input-only'
  SaveJson $ri $rootInput;$rootReadonlyIdentity=Id $ri;$rootAttributes=[IO.File]::GetAttributes($ri);$rootReceiptIdentity=Id $rr2
  [IO.File]::SetAttributes($ri,($rootAttributes-bor[IO.FileAttributes]::ReadOnly))
  try{
   $rootReadonly=Run $rootAdapter @{InputPath=$ri;DeleteInputOnExit=$true;AsJson=$true}
   Check ($rootReadonly.Code-eq0-and$rootReadonly.Value.status-ceq$rc.Value.status-and$rootReadonly.Value.inputCleanup.status-ceq'PARTIAL_FAILURE'-and$rootReadonly.Value.inputCleanup.failures[0].kind-ceq'IO_ERROR'-and(Test-Path -LiteralPath $ri)-and(Id $ri)-ceq$rootReadonlyIdentity-and([IO.File]::GetAttributes($ri)-band[IO.FileAttributes]::ReadOnly)-ne0-and(Id $rr2)-ceq$rootReceiptIdentity) 'cleanup-maintenance-delegated-readonly-failure-is-separate-with-input-preserved'
  }finally{if(Test-Path -LiteralPath $ri){[IO.File]::SetAttributes($ri,$rootAttributes)}}
 }finally{[Environment]::CurrentDirectory=$oldDirectory;Pop-Location}
 Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=efficiency-regression')
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())
 if([IO.Path]::GetDirectoryName($resolved)-cne$parent-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-efficiency-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
