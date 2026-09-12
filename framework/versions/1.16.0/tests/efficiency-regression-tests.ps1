[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$passed=0;$utf8=[Text.UTF8Encoding]::new($false)
function SaveText([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;$null=New-Item -ItemType Directory -Path $parent -Force;[IO.File]::WriteAllText($Path,$Text.Replace("`r",'').TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 100)}
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
 foreach($text in @($valid.TrimEnd("`n"),$valid.Replace("`n","`r`n"),([string][char]0xFEFF+$valid),($valid+[char]0),($valid+[char]0xFFFD))){$d=Run $workflow @{InputJson=$text;AsJson=$true};Check ($d.Code-ne0) ('workflow-strict-text-'+$passed)}
 $m=Run $workflow @{InputJson=('{"operation":"MESSAGE","senderAuthentic":true}'+"`n");AsJson=$true};Check ($m.Code-ne0) 'workflow-message-missing-authenticated-fields-rejected'
 # Anonymous ordinary project exercises actual composer and process entrypoints.
 $project=Join-Path $temp 'project';$null=New-Item -ItemType Directory -Path $project;& git -C $project init -q
 $framework=Join-Path $temp 'framework';$fv=Join-Path $framework 'framework/versions/1.16.0';$null=New-Item -ItemType Directory -Path (Split-Path -Parent $fv) -Force;Copy-Item -LiteralPath $versionRoot -Destination $fv -Recurse
 $vo=Get-Content -Raw -LiteralPath (Join-Path $fv 'VERSION.json')|ConvertFrom-Json;$vo.lifecycle='STABLE';$vo.consumable=$true;$vo.projectPinEligible=$true;SaveJson (Join-Path $fv 'VERSION.json') $vo
 $manifest=Get-Content -Raw -LiteralPath (Join-Path $fv 'RELEASE_MANIFEST.json')|ConvertFrom-Json;$manifest.lifecycle='STABLE';$manifest.sourceReview='APPROVED'
 [string[]]$payloadPaths=@(Get-ChildItem -LiteralPath $fv -Recurse -File|Where-Object{$_.Name-cne'RELEASE_MANIFEST.json'}|ForEach-Object{$_.FullName.Substring($fv.Length+1).Replace('\','/')});[Array]::Sort($payloadPaths,[StringComparer]::Ordinal)
 $rows=@($payloadPaths|ForEach-Object{$_+'|'+(Id (Join-Path $fv $_))});$manifest.fileCount=$payloadPaths.Count;$manifest.totalBytes=($payloadPaths|ForEach-Object{(Get-Item -LiteralPath (Join-Path $fv $_)).Length}|Measure-Object -Sum).Sum;$manifest.canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n"))))
 SaveJson (Join-Path $fv 'RELEASE_MANIFEST.json') $manifest
 $control=Join-Path $project '.ai-workspace';$task=Join-Path $control 'tasks/active/EFFICIENCY-001.md'
 SaveText $task "# EFFICIENCY-001 — fixture`n- Owner: actor`n- Work route: actor=actor; role=DOMAIN_OWNER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]"
 SaveJson (Join-Path $control 'project.json') ([ordered]@{schemaVersion=4;id='efficiency-fixture';displayName='Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
 SaveJson (Join-Path $control 'controller.json') ([ordered]@{schemaVersion=1;projectId='efficiency-fixture';controllerId='actor';controllerEpoch=1;state='CURRENT'})
 SaveJson (Join-Path $control 'corrections.json') ([ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='efficiency-fixture';corrections=@()})
 SaveText (Join-Path $control 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 $policy=[ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='efficiency-fixture';selectedRulePackBytes=98304;rules=@()};$policyPath=Join-Path $control 'process-policy.json';SaveJson $policyPath $policy
 $runtime=Join-Path $control 'runtime/EFFICIENCY-001/actor';$null=New-Item -ItemType Directory -Path $runtime -Force
 $intent=[ordered]@{schemaVersion=1;objective='Do not create another task; preview the current work.';requestedActionKind='NONE';requestedResultKind='USER_RESPONSE';semanticHints=@('configuration explanation');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}
 $discovery=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$framework;taskPath=$task;expectedProjectConfigIdentity=Id (Join-Path $control 'project.json');expectedCorrectionsIdentity=Id (Join-Path $control 'corrections.json');expectedTaskIdentity=Id $task;observedActor='actor';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$intent;evaluationOnly=$true}
 $resolver=Join-Path $fv 'scripts/resolve-process-requirements.ps1';$inputPath=Join-Path $runtime 'input.json'
 function DiscoverCase([string[]]$Hints){$discovery.intentEnvelope.semanticHints=@($Hints);SaveJson $inputPath $discovery;$r=Run $resolver @{InputPath=$inputPath;AsJson=$true};if($r.Code-ne0){throw $r.Text};return $r.Value}
 $read=DiscoverCase @('configuration explanation');$ids=@($read.selectedRuleBlocks.requirementId)
 Check ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cnotin$ids-and'framework:PR_TASK_RESOURCE_SELECTION'-cnotin$ids-and'framework:PR_TASK_CHANGED_OUTPUT_DISPOSITION'-cnotin$ids) 'healthy-read-only-does-not-load-creation-resource-or-write-closure'
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
  $positive=DiscoverCase @($term)
  Check (@($positive.selectedRuleBlocks.requirementId|Where-Object{$_-cin@('framework:PR_TASK_LAUNCH_AND_ROUTE','framework:PR_TASK_RESOURCE_SELECTION','framework:PR_CODEX_RESOURCE_ROUTE')}).Count-eq3) ('explicit-task-assignment-selects-three-'+$term)
 }
 # Frozen constructions made from these requests; downstream regression, not live model accuracy.
 foreach($case in @(
  @{Request='把这项工作分派给另一个任务，沿用当前目录。';Hints=@('task assignment');Select=$true},
  @{Request='如果以后需要再新建任务，现在只解释配置。';Hints=@('configuration explanation');Select=$false},
  @{Request='取消刚才的分派，继续说明变量赋值。';Hints=@('variable assignment');Select=$false},
  @{Request='报告中的“new assignment”是历史引用，不是当前请求。';Hints=@('configuration explanation');Select=$false}
 )){
  $discovery.intentEnvelope.objective=$case.Request;$actual=DiscoverCase $case.Hints
  Check (('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($actual.selectedRuleBlocks.requirementId))-eq$case.Select) ('request-construction-selection-'+$case.Request)
 }
 $originalTask=[IO.File]::ReadAllText($task)
 SaveText $task ($originalTask.Replace('phase=PLAN','phase=REVIEW').Replace('profile=STANDARD','profile=CRITICAL'))
 $discovery.expectedTaskIdentity=Id $task;$discovery.intentEnvelope.objective='正式独立审核此候选，不要修改。'
 $discovery.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$discovery.intentEnvelope.requestedResultKind='REVIEW_VERDICT'
 $formalReview=DiscoverCase @('formal review')
 Check ('framework:PR_CRITICAL_REVIEW_INDEPENDENCE'-cin@($formalReview.selectedRuleBlocks.requirementId)-and'framework:PR_PERSPECTIVE_LENS_SELECTION'-cin@($formalReview.selectedRuleBlocks.requirementId)) 'formal-review-no-repair-keeps-independent-review-and-lenses'
 SaveText $task $originalTask;$discovery.expectedTaskIdentity=Id $task
 $discovery.intentEnvelope.requestedActionKind='NONE';$discovery.intentEnvelope.requestedResultKind='USER_RESPONSE'
 # Legacy schema1 still consumes explicit selection text; bare ambiguous words intentionally narrow.
 foreach($term in @('assignment','task assignment')){
  $legacy=[ordered]@{schemaVersion=1;mode='DISCOVER';projectRoot=$project;frameworkRoot=$framework;taskPath=$task;expectedProjectConfigIdentity=$discovery.expectedProjectConfigIdentity;expectedCorrectionsIdentity=$discovery.expectedCorrectionsIdentity;expectedTaskIdentity=Id $task;observedActor='actor';capabilities=@();objective=$term;actionKind='NONE';resultKind='USER_RESPONSE';exactPaths=@();hostEnforcementGrade='INSTRUCTION_BOUND';evaluationOnly=$true}
  SaveJson $inputPath $legacy;$legacyResult=Run $resolver @{InputPath=$inputPath;AsJson=$true}
  Check ($legacyResult.Code-eq0-and(('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($legacyResult.Value.selectedRuleBlocks.requirementId))-eq($term-ceq'task assignment'))) ('legacy-explicit-selection-'+$term)
 }
 $discovery.intentEnvelope.semanticHints=@('configuration explanation')
 # Real entrypoint cleanup: exact ordinary input, failure, attributes and binding.
 $cleanupNeighbor=Join-Path $runtime 'cleanup-neighbor.json';SaveText $cleanupNeighbor '{"keep":true}'
 $cleanupReceipt=Join-Path $runtime 'cleanup-receipt.json';SaveJson $cleanupReceipt $read.compactReceipt
 $neighborIdentity=Id $cleanupNeighbor;$receiptIdentity=Id $cleanupReceipt
 SaveJson $inputPath $discovery;$cleaned=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true;AsJson=$true}
 Check ($cleaned.Code-eq0-and-not(Test-Path -LiteralPath $inputPath)-and(Id $cleanupNeighbor)-ceq$neighborIdentity-and(Id $cleanupReceipt)-ceq$receiptIdentity) 'cleanup-version-success-exact-input-only-receipt-retained'
 $cleanupBoundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$cleanupReceipt;expectedDiscoverReceiptIdentity=$receiptIdentity;preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
 SaveJson $inputPath $cleanupBoundary;$failedCleanup=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true;AsJson=$true}
 Check ($failedCleanup.Code-ne0-and$failedCleanup.Value.status-ceq'BLOCKED'-and$failedCleanup.Value.reason-ceq'PREPARATION_INCOMPLETE'-and-not(Test-Path -LiteralPath $inputPath)-and(Id $cleanupNeighbor)-ceq$neighborIdentity-and(Id $cleanupReceipt)-ceq$receiptIdentity) 'cleanup-version-failure-visible-and-exact-input-deleted'
 SaveJson $inputPath $discovery;$readonlyIdentity=Id $inputPath;$ordinaryAttributes=[IO.File]::GetAttributes($inputPath)
 [IO.File]::SetAttributes($inputPath,($ordinaryAttributes-bor[IO.FileAttributes]::ReadOnly))
 try{
  $readonly=Run $resolver @{InputPath=$inputPath;DeleteInputOnExit=$true;AsJson=$true}
  Check ($readonly.Code-ne0-and(Test-Path -LiteralPath $inputPath)-and(Id $inputPath)-ceq$readonlyIdentity-and([IO.File]::GetAttributes($inputPath)-band[IO.FileAttributes]::ReadOnly)-ne0-and(Id $cleanupNeighbor)-ceq$neighborIdentity-and(Id $cleanupReceipt)-ceq$receiptIdentity) 'cleanup-version-readonly-failure-visible-with-bytes-and-attribute-preserved'
 }finally{if(Test-Path -LiteralPath $inputPath){[IO.File]::SetAttributes($inputPath,$ordinaryAttributes)}}
 $wrongActorInput=Join-Path $control 'runtime/EFFICIENCY-001/other-actor/cleanup.json';SaveJson $wrongActorInput $discovery;$wrongActorIdentity=Id $wrongActorInput
 $wrongActorCleanup=Run $resolver @{InputPath=$wrongActorInput;DeleteInputOnExit=$true;AsJson=$true}
 Check ($wrongActorCleanup.Code-ne0-and(Id $wrongActorInput)-ceq$wrongActorIdentity-and(Id $cleanupNeighbor)-ceq$neighborIdentity) 'cleanup-version-wrong-actor-scope-rejected-and-retained'
 $discovery.intentEnvelope.objective='Give this work another task, using the local directory.'
 $launch=DiscoverCase @('task assignment','resource selection');Check ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($launch.selectedRuleBlocks.requirementId)-and'framework:PR_TASK_RESOURCE_SELECTION'-cin@($launch.selectedRuleBlocks.requirementId)-and'framework:PR_CODEX_RESOURCE_ROUTE'-cin@($launch.selectedRuleBlocks.requirementId)) 'normalized-synonym-assignment-loads-organization-and-resource'
 $discovery.intentEnvelope.objective='The edits are complete; now report their remaining artifact disposition.'
 $written=DiscoverCase @('changed output disposition');Check ('framework:PR_TASK_CHANGED_OUTPUT_DISPOSITION'-cin@($written.selectedRuleBlocks.requirementId)) 'none-after-write-keeps-disposition'
 $discovery.intentEnvelope.objective='Quoted history: assignment, resource change, formal review; all were cancelled.';$cancelled=DiscoverCase @('configuration explanation');Check ((@($cancelled.selectedRuleBlocks.requirementId)-join'|') -ceq ($ids-join'|')) 'objective-negation-history-cancellation-not-trigger-pool'
 $discovery.intentEnvelope.objective='If we later need another task, create it then; explain this configuration now.';$conditional=DiscoverCase @('configuration explanation');Check ((@($conditional.selectedRuleBlocks.requirementId)-join'|') -ceq ($ids-join'|')) 'inactive-conditional-assignment-does-not-load-organization'
 $reply=DiscoverCase @('message delivery','controller exception');Check ('framework:PR_COMPACT_NON_INTERRUPT_DELIVERY'-cin@($reply.selectedRuleBlocks.requirementId)) 'controller-exception-user-response-keeps-delivery'
 $discovery.intentEnvelope.ambiguityState='UNKNOWN';$unknown=DiscoverCase @('unresolved meaning');Check ('framework:PR_TASK_LAUNCH_AND_ROUTE'-cin@($unknown.selectedRuleBlocks.requirementId)) 'unknown-retains-conservative-conditional-load';$discovery.intentEnvelope.ambiguityState='CLEAR'
 $configPath=Join-Path $control 'project.json';$config=Get-Content -Raw -LiteralPath $configPath|ConvertFrom-Json;$config.frameworkCapabilities|Add-Member KNOWLEDGE_REFERENCE ([pscustomobject]@{enabled=$true;indexLocator='.ai-workspace/knowledge/index.json'});SaveJson $configPath $config;$discovery.expectedProjectConfigIdentity=Id $configPath;$discovery.capabilities=@('KNOWLEDGE_REFERENCE')
 $enabled=DiscoverCase @('configuration explanation');$noImpact=DiscoverCase @('configuration explanation');$impact=DiscoverCase @('knowledge query impact')
 Check ('framework:PR_KNOWLEDGE_IMPACT_MAINTENANCE'-cnotin@($enabled.selectedRuleBlocks.requirementId)-and'framework:PR_KNOWLEDGE_IMPACT_MAINTENANCE'-cnotin@($noImpact.selectedRuleBlocks.requirementId)-and'framework:PR_KNOWLEDGE_IMPACT_MAINTENANCE'-cin@($impact.selectedRuleBlocks.requirementId)) 'knowledge-enabled-and-no-impact-distinct-from-real-query-impact'
 $config.frameworkCapabilities.PSObject.Properties.Remove('KNOWLEDGE_REFERENCE');SaveJson $configPath $config;$discovery.expectedProjectConfigIdentity=Id $configPath;$discovery.capabilities=@()
 $discovery.intentEnvelope.semanticHints=@('configuration explanation');SaveJson $inputPath $discovery;$receiptPath=Join-Path $runtime 'saved.json';$saved=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$receiptPath;AsJson=$true}
 Check ($saved.Code-eq0-and$saved.Value.savedCompactReceipt.identity-ceq(Id $receiptPath)-and-not[IO.File]::ReadAllText($receiptPath).Contains('fullText')) 'compact-save-only-receipt-exact-identity'
 $savedId=Id $receiptPath;$again=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$receiptPath;AsJson=$true};Check ($again.Code-ne0-and(Id $receiptPath)-ceq$savedId) 'compact-existing-file-refused-without-overwrite'
 $same=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$inputPath;AsJson=$true};Check ($same.Code-ne0) 'compact-input-overwrite-refused'
 $bad=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=(Join-Path $temp 'escape.json');AsJson=$true};Check ($bad.Code-ne0-and-not(Test-Path -LiteralPath (Join-Path $temp 'escape.json'))) 'compact-outside-runtime-refused'
 $missingParent=Join-Path $runtime 'missing/saved.json';$badParent=Run $resolver @{InputPath=$inputPath;CompactReceiptPath=$missingParent;AsJson=$true};Check ($badParent.Code-ne0-and-not(Test-Path -LiteralPath $missingParent)) 'compact-does-not-create-alternate-parent'
 $b=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=$savedId;preparationReceipts=@($saved.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@($saved.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique);deliveryReceipts=@('DELIVERED');publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'};SaveJson $inputPath $b;$final=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($final.Code-eq0) 'saved-compact-consumed-by-real-finalize'
 $sourcePath=Join-Path $project 'docs/shared.md';SaveText $sourcePath "Intro`n<!-- A -->`nALPHA_BODY`n<!-- /A -->`n<!-- B -->`nBETA_BODY`n<!-- /B -->"
 $selector=[ordered]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@('architecture')}
 foreach($name in @('A','B')){$policy.rules+=@([ordered]@{ruleId=('STANDARD_'+$name);requirementReason='Independent obligation from shared document';selectors=$selector;preparationRequirements=@('PREP_'+$name);resultRequirements=@('RESULT_'+$name);decisionLocator='fixture';source=[ordered]@{rootSourceId=$name;documents=@([ordered]@{sourceId=$name;locator='docs/shared.md';identity=Id $sourcePath;mode='MARKED_SECTION';sectionStart=('<!-- '+$name+' -->');sectionEnd=('<!-- /'+$name+' -->');dependencies=@()})}})}
 SaveJson $policyPath $policy;$normal=DiscoverCase @('architecture');$texts=($normal.selectedRuleBlocks.fullText-join"`n");Check ($texts.Contains('ALPHA_BODY')-and$texts.Contains('BETA_BODY')) 'same-source-normal-sections-both-complete'
 SaveText $sourcePath ([IO.File]::ReadAllText($sourcePath)+"CURRENT_DRIFT_BODY`n")
 $drift=DiscoverCase @('configuration explanation');$rules=@($drift.selectedRuleBlocks|Where-Object{$_.source-ceq'PROJECT_POLICY'});$text=$rules.fullText-join"`n"
 Check ($rules.Count-eq2-and[regex]::Matches($text,'CURRENT_DRIFT_BODY').Count-eq1-and$text.Contains('PROJECT-SOURCE-REFERENCE')) 'same-source-drift-full-body-once'
 Check ('PREP_A'-cin@($rules.preparationRequirements)-and'PREP_B'-cin@($rules.preparationRequirements)-and'RESULT_A'-cin@($rules.resultRequirements)-and'RESULT_B'-cin@($rules.resultRequirements)) 'same-source-dedup-keeps-every-obligation'
 $old=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($old.Code-eq0) 'drift-current-discover-remains-available'
 SaveJson $inputPath $b;$stale=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($stale.Code-ne0) 'pre-drift-receipt-cannot-finalize'
 $checker=Join-Path $versionRoot 'scripts/check-task-card.ps1';$card=Join-Path $temp 'tasks/archive/CLOSE-001.md'
 $base="# CLOSE-001 — fixture`n- Task schema: 1.16.0`n- Owner: actor`n- Work route: actor=actor; role=DOMAIN_OWNER; phase=VERIFY`n- Range summary: profile=STANDARD; lifecycle=CLOSED; expected_paths=[]; actual_paths=[]`n- Closure outcome: SUCCESS`n- Closure evidence: reviewed-result`n- Remaining obligations: NONE`n- Artifact disposition: retained; Git deferred in owning task`n- Writer / reviewer / authorization: NONE / NONE / NONE"
 foreach($outcome in @('SUCCESS','CANCELLED','SUPERSEDED')){$text=$base.Replace('Closure outcome: SUCCESS',('Closure outcome: '+$outcome));if($outcome-ceq'SUPERSEDED'){$text=$text.Replace('Remaining obligations: NONE','Remaining obligations: successor TASK-002')};SaveText $card $text;$r=Run $checker @{TaskPath=$card};Check ($r.Code-eq0-and$r.Text.Contains('closure='+$outcome)) ('task-closure-'+$outcome)}
 $critical=$base.Replace('profile=STANDARD; lifecycle=CLOSED;','profile=CRITICAL; lifecycle=CLOSED; current_exact=fixture-v1;')+"`n- Phase gate: FALSE`n- Proportionality: NOT_APPLICABLE; reason=bounded review of existing behavior"
 SaveText $card $critical;$r=Run $checker @{TaskPath=$card};Check ($r.Code-eq0) 'critical-minimal-closure-template-without-phase-matrix-or-viewpoint-quota'
 foreach($text in @($base.Replace('Closure outcome: SUCCESS','Closure outcome: WAITING'),$base.Replace('Closure evidence: reviewed-result','Closure evidence: PENDING'),$base.Replace('NONE / NONE / NONE','actor / NONE / ACTIVE'))){SaveText $card $text;$r=Run $checker @{TaskPath=$card};Check ($r.Code-ne0) ('task-invalid-closure-'+$passed)}
 # Current Maintenance root adapters, both compact shapes, and real TARGET write closure.
 $repositoryRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
 # Execute each real root consumer's projection AST, including an old module
 # without the export while the current helper is still loaded globally.
 $currentModule=Import-Module (Join-Path $fv 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru
 $legacyModule=New-Module -Name 'LegacyProjectionFixture' -ScriptBlock {function LegacyFixture { };Export-ModuleMember -Function LegacyFixture}
 $semanticIntent=[pscustomobject]@{objective='Update the approved root source. Do not perform any new assignment or resource selection.';semanticHints=@('root source update');externalHints=@('Cancelled assignment and resource selection')}
 foreach($consumer in @(@{Path='scripts/integrate-framework-source.ps1';Variable='$semantic'},@{Path='scripts/upgrade-project.ps1';Variable='$semanticObjective'})){
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
 foreach($relative in @('README.md','AGENTS.md','scripts/resolve-framework-maintenance-target.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1','scripts/check-framework-maintenance-authorization.ps1','scripts/invoke-framework-maintenance-safe-git.ps1','scripts/MaintenanceOverlay.psm1','scripts/ProjectAdoptionState.psm1')){$dest=Join-Path $framework $relative;$null=New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force;Copy-Item -LiteralPath (Join-Path $repositoryRoot $relative) -Destination $dest}
 Copy-Item -LiteralPath (Join-Path $repositoryRoot 'framework/maintenance-overlay') -Destination (Join-Path $framework 'framework/maintenance-overlay') -Recurse
 & git -C $framework init -q
 $maintenance=Join-Path $temp 'maintenance';$null=New-Item -ItemType Directory -Path $maintenance;& git -C $maintenance init -q
 $mc=Join-Path $maintenance '.ai-workspace';$mr=Join-Path $mc 'runtime/ROOT-001/actor';$null=New-Item -ItemType Directory -Path $mr -Force
 $mt=Join-Path $mc 'tasks/active/ROOT-001.md';SaveText $mt "# ROOT-001 — root fixture`n- Task schema: 1.16.0`n- Owner: actor`n- Work route: actor=actor; role=CONTROLLER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]"
 $cfg=[ordered]@{schemaVersion=4;id='maintenance-fixture';displayName='Fixture';controlPlaneLayout='framework-maintenance-sibling';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'};frameworkTarget=[ordered]@{repositoryId='fixture-framework';siblingDirectory='framework';routineExcludedPaths=@()}}
 SaveJson (Join-Path $mc 'project.json') $cfg
 SaveJson (Join-Path $mc 'controller.json') ([ordered]@{schemaVersion=1;projectId='maintenance-fixture';controllerId='actor';controllerEpoch=1;state='CURRENT'})
 SaveJson (Join-Path $mc 'corrections.json') ([ordered]@{schemaVersion=2;contractVersion='1.16.0';projectId='maintenance-fixture';corrections=@()})
 SaveText (Join-Path $mc 'BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 $mpolicy=[ordered]@{schemaVersion=1;contractVersion='1.16.0';projectId='maintenance-fixture';selectedRulePackBytes=98304;rules=@([ordered]@{ruleId='FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY';requirementReason='Keep control and target separate';effectiveRule='Control owns authority; target owns development source.';selectors=[ordered]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture'})};SaveJson (Join-Path $mc 'process-policy.json') $mpolicy
 $object=Join-Path $framework 'fixture-object.txt';SaveText $object 'before'
 $package=[ordered]@{schemaVersion=2;frameworkVersion='1.16.0';taskId='ROOT-001';profile='STANDARD';lifecycle='ACTIVE';owner='actor';issuer='actor';issuerRole='PROJECT_CONTROLLER';grantee='actor';bundle='ROOT_FIXTURE';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Id $mt;actions=@('SOURCE_WRITE');exactPaths=@('fixture-object.txt');objectIdentities=@([ordered]@{path='fixture-object.txt';identity=Id $object});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','REPOSITORY_CHANGE','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=Id (Join-Path $mc 'project.json');repositoryId='fixture-framework';issuerControllerId='actor';issuerControllerEpoch=1;controllerControlIdentity=Id (Join-Path $mc 'controller.json')}
 $ap=Join-Path $mr 'authorization.json';SaveJson $ap $package
 $rootInput=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$maintenance;frameworkRoot=$framework;taskPath=$mt;expectedProjectConfigIdentity=Id (Join-Path $mc 'project.json');expectedCorrectionsIdentity=Id (Join-Path $mc 'corrections.json');expectedTaskIdentity=Id $mt;observedActor='actor';capabilities=@();exactPaths=@('fixture-object.txt');forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$ap;expectedAuthorizationIdentity=Id $ap;userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Change one fixture target object';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('changed output disposition');pathHints=@();capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
 $rootAdapter=Join-Path $framework 'scripts/resolve-framework-maintenance-process-requirements.ps1';$ri=Join-Path $mr 'input.json';$rr=Join-Path $mr 'saved.json'
 $oldDirectory=[Environment]::CurrentDirectory;Push-Location $maintenance
 try{
  [Environment]::CurrentDirectory=$maintenance
  SaveJson $ri $rootInput;$rd=Run $rootAdapter @{InputPath=$ri;CompactReceiptPath=$rr;DeleteInputOnExit=$true;AsJson=$true};if($rd.Code-ne0){throw ('ROOT_DISCOVER|'+$rd.Text)}
  Check ($rd.Value.compactReceipt.schemaVersion-eq1-and$rd.Value.savedCompactReceipt.identity-ceq(Id $rr)) 'maintenance-target-schema2-discovers-and-saves-schema1-compact'
  Check (-not(Test-Path -LiteralPath $ri)-and(Test-Path -LiteralPath $ap)-and(Test-Path -LiteralPath $rr)) 'cleanup-maintenance-target-discover-preserves-package-and-last-consumer-receipt'
  $rb=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$rr;expectedDiscoverReceiptIdentity=Id $rr;preparationReceipts=@($rd.Value.compactReceipt.selectedObligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
  SaveJson $ri $rb;$ra=Run $rootAdapter @{InputPath=$ri;AsJson=$true};if($ra.Code-ne0){throw ('ROOT_ADMIT|'+$ra.Text)}
  SaveText $object 'after';$rb.mode='FINALIZE_OUTPUT';$rb.resultReceipts=@($rd.Value.compactReceipt.selectedObligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|fixture-object.txt|'+(Id $object));SaveJson $ri $rb;$rf=Run $rootAdapter @{InputPath=$ri;AsJson=$true}
  Check ($rf.Code-eq0) 'maintenance-saved-target-compact-real-admit-write-finalize'
  $rootInput.schemaVersion=3;$rootInput['contextType']='TASK';$rootInput['readOnlyContext']='NOT_APPLICABLE';$rootInput.authorizationPackagePath='NOT_REQUIRED';$rootInput.expectedAuthorizationIdentity='NOT_REQUIRED';$rootInput.exactPaths=@();$rootInput.intentEnvelope.requestedActionKind='NONE';$rootInput.intentEnvelope.requestedResultKind='USER_RESPONSE';$rootInput.intentEnvelope.semanticHints=@('configuration explanation');$rootInput.intentEnvelope.mutationHints=@();$rootInput.evaluationOnly=$true;SaveJson $ri $rootInput
  $rr2=Join-Path $mr 'saved-v2.json';$rc=Run $rootAdapter @{InputPath=$ri;CompactReceiptPath=$rr2;DeleteInputOnExit=$true;AsJson=$true};if($rc.Code-ne0){throw ('ROOT_CONTROL|'+$rc.Text)}
  Check ($rc.Value.compactReceipt.schemaVersion-eq2-and$rc.Value.savedCompactReceipt.identity-ceq(Id $rr2)) 'maintenance-control-schema3-saves-schema2-compact'
  Check (-not(Test-Path -LiteralPath $ri)-and(Test-Path -LiteralPath $rr)-and(Test-Path -LiteralPath $rr2)) 'cleanup-maintenance-control-discover-exact-input-only'
  SaveJson $ri $rootInput;$rootReadonlyIdentity=Id $ri;$rootAttributes=[IO.File]::GetAttributes($ri);$rootReceiptIdentity=Id $rr2
  [IO.File]::SetAttributes($ri,($rootAttributes-bor[IO.FileAttributes]::ReadOnly))
  try{
   $rootReadonly=Run $rootAdapter @{InputPath=$ri;DeleteInputOnExit=$true;AsJson=$true}
   Check ($rootReadonly.Code-ne0-and(Test-Path -LiteralPath $ri)-and(Id $ri)-ceq$rootReadonlyIdentity-and([IO.File]::GetAttributes($ri)-band[IO.FileAttributes]::ReadOnly)-ne0-and(Id $rr2)-ceq$rootReceiptIdentity) 'cleanup-maintenance-delegated-readonly-failure-propagates-with-input-preserved'
  }finally{if(Test-Path -LiteralPath $ri){[IO.File]::SetAttributes($ri,$rootAttributes)}}
 }finally{[Environment]::CurrentDirectory=$oldDirectory;Pop-Location}
 Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=efficiency-regression')
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())
 if([IO.Path]::GetDirectoryName($resolved)-cne$parent-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-efficiency-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
