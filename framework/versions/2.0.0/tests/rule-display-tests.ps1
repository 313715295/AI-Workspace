[CmdletBinding()]
param()
Import-Module (Join-Path $PSScriptRoot 'TestNativeOutput.psm1')
Initialize-AiwTestNativeOutput
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$passed=0;$utf8=[Text.UTF8Encoding]::new($false,$true)
$versionRoot=Split-Path -Parent $PSScriptRoot
$frameworkRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
$resolver=Join-Path $versionRoot 'scripts/resolve-process-requirements.ps1'
Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementDisplay.psm1') -Force
Import-Module (Join-Path $versionRoot 'scripts/ContentSources.psm1') -Force
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 70)}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw "ASSERT_FAIL|$Name"};$script:passed++;Write-Output "PASS|$Name"}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Name}
function Discover {
 SaveJson $inputPath $inputValue
 $requestId=if($inputValue.contextType-ceq'PROJECT_EXTERNAL'){$inputValue.requestContext.requestId}else{$inputValue.readOnlyContext.requestId}
 $directory=Join-Path $temp ('.ai-workspace/runtime/'+$requestId+'/'+$inputValue.observedActor)
 $null=[IO.Directory]::CreateDirectory($directory)
 $script:LastDisplayPath=Join-Path $directory ([guid]::NewGuid().ToString('N')+'.txt')
 $global:DisplayComposerCalls=0
 $probe=Set-PSBreakpoint -Command Invoke-AiwProcessCompositionCore -Action {$global:DisplayComposerCalls++}
 try{$global:LASTEXITCODE=0;$lines=@(& $resolver -InputPath $inputPath -AsJson -DisplayPath $script:LastDisplayPath)}finally{Remove-PSBreakpoint $probe}
 if($global:DisplayComposerCalls-ne1){throw ('PUBLIC_COMPOSER_COUNT|'+$global:DisplayComposerCalls+'|ORIGINAL_RESULT|'+($lines-join'|'))}
 if(($lines-join'')-match'[^\x00-\x7f]'){throw 'MACHINE_NATIVE_TRANSPORT_NOT_ASCII'}
 $code=$global:LASTEXITCODE;$value=($lines-join"`n")|ConvertFrom-Json -Depth 100
 if($code-ne0){throw ($lines-join"`n")};return $value
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-rule-display-'+[guid]::NewGuid().ToString('N'))
try{
 $configPath=Join-Path $temp '.ai-workspace/project.json';$correctionsPath=Join-Path $temp '.ai-workspace/corrections.json';$policyPath=Join-Path $temp '.ai-workspace/process-policy.json';$inputPath=Join-Path $temp 'display-input.json'
 $bindings=@([pscustomobject]@{id='display-docs';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@('docs/shared.md','docs/A.md','docs/B.md'|ForEach-Object{[pscustomobject]@{kind='FILE';locator=$_}});decisionLocator='fixture:explicit-document-scope'})
 SaveJson $configPath ([ordered]@{schemaVersion=7;id='display-fixture';displayName='Display fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=$bindings;processPolicy=[ordered]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}})
 SaveJson $correctionsPath ([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='display-fixture';corrections=@()})
 SaveJson (Join-Path $temp '.ai-workspace/controller.json') ([ordered]@{schemaVersion=1;projectId='display-fixture';controllerId='fixture-actor';controllerEpoch=1;state='CURRENT'})
 SaveText (Join-Path $temp '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 $selector=[ordered]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@('display fixture')}
 $longBody='完整规则🙂'+("`n中文、emoji🚲与精确原始正文。"*900)
 $policy=[ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='display-fixture';rules=@()}
 $policy.rules+=@([ordered]@{ruleId='INLINE_A';requirementReason='Complete oversized Unicode rule';effectiveRule=$longBody;selectors=$selector;preparationRequirements=@('PREP_A');resultRequirements=@('RESULT_A');decisionLocator='fixture:explicit'})
 SaveText (Join-Path $temp 'docs/shared.md') 'EXACT_SHARED_DEPENDENCY'
 foreach($name in @('A','B')){
  SaveText (Join-Path $temp ('docs/'+$name+'.md')) ('DISTINCT_ROOT_'+$name)
  $docs=@()
  foreach($part in @('shared',$name)){$doc=[pscustomobject]@{sourceId=$part.ToUpperInvariant();bindingId='display-docs';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=('docs/'+$part+'.md');identity=(Id (Join-Path $temp ('docs/'+$part+'.md')));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@(if($part-ceq$name){'SHARED'})};$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $bindings;$docs+=$doc}
  $source=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='display-docs';itemId=('SOURCE_'+$name);revision=(Get-AiwContentRevision ([pscustomobject]@{documents=$docs}) $bindings);itemIdentity='';rootSourceId=$name;documents=$docs};$source.itemIdentity=Get-AiwContentItemIdentity $source
  $policy.rules+=@([ordered]@{ruleId=('SOURCE_'+$name);requirementReason='Two standards depend on the same real document';selectors=$selector;preparationRequirements=@('SOURCE_PREP_'+$name);resultRequirements=@('SOURCE_RESULT_'+$name);decisionLocator='fixture:explicit';source=$source})
 }
 SaveJson $policyPath $policy
 $facets=[ordered]@{};foreach($dimension in @('domain','workType','deliverableType','stage')){$facets[$dimension]=[ordered]@{state='UNKNOWN';values=@()}}
 $inputValue=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=[ordered]@{sessionId='display-session';requestId='display-fixture';role='EXECUTOR';phase='PLAN';profile='STANDARD'};projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=Id $configPath;expectedCorrectionsIdentity=Id $correctionsPath;expectedTaskIdentity='NOT_APPLICABLE';observedActor='fixture-actor';capabilities=@();exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=2;objective='Explain the explicitly supplied display fixture rules.';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('display fixture');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=$facets};evaluationOnly=$true}
 $result=Discover;$original=$result|ConvertTo-Json -Depth 100 -Compress
 $projection=Get-AiwProcessDisplay $result
 Check ($projection.status-ceq'EVALUATION_ONLY'-and$projection.contextBodyReuse-ceq'FULL'-and-not$projection.modelLoadProven) 'display-keeps-evaluation-and-context-ceiling'
 $selectedIds=@($result.selectedRuleBlocks.requirementId)
 $hostDelivery=@($result.selectedRuleBlocks|Where-Object requirementId -CEQ 'framework:PR_COMPACT_NON_INTERRUPT_DELIVERY')
 $ordinaryOwner=@($result.selectedRuleBlocks|Where-Object requirementId -CEQ 'framework:PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES')
 Check ($hostDelivery.Count-eq1-and$ordinaryOwner.Count-eq1-and$ordinaryOwner[0].fullText.Contains('无正式Review/接受、TASK_MESSAGE、关闭/责任转换或continuation消费者')-and$ordinaryOwner[0].fullText.Contains('不产生假PASS')-and[regex]::Matches($projection.text,'仅本次实际NONE、无包无副作用').Count-eq1) 'host-delivery-selection-includes-one-complete-ordinary-user-exception-owner'

 Check ([string]::Join('|',@($projection.currentRules.requirementId))-ceq[string]::Join('|',$selectedIds)) 'projection-keeps-exact-current-selection-and-order'
 Check (($result|ConvertTo-Json -Depth 100 -Compress)-ceq$original) 'projection-does-not-mutate-resolver-result'
 $inlineRules=@($projection.currentRules|Where-Object requirementId -like '*:INLINE_*')
 Check ($inlineRules.Count-eq1) 'one-valid-oversized-inline-rule-selected'
 $obligations=@($projection.obligations|Where-Object requirementId -like 'project:*')
 Check ('SOURCE_PREP_A'-cin@($obligations.preparationRequirements)-and'SOURCE_PREP_B'-cin@($obligations.preparationRequirements)-and'SOURCE_RESULT_A'-cin@($obligations.resultRequirements)-and'SOURCE_RESULT_B'-cin@($obligations.resultRequirements)) 'dedup-retains-independent-obligation-union'
 $sourceRules=@($projection.currentRules|Where-Object requirementId -like '*:SOURCE_*')
 Check ($sourceRules.Count-eq2-and$sourceRules[0].blockIds[0]-eq$sourceRules[1].blockIds[0]-and$sourceRules[0].blockIds[1]-ne$sourceRules[1].blockIds[1]) 'shared-dependency-dedup-keeps-distinct-roots'
 $bodyUnits=@($projection.bodyUnits|Where-Object id -eq $inlineRules[0].blockIds[0])
 Check ($bodyUnits.Count-eq1-and$bodyUnits[0].fullText-ceq$longBody-and$projection.text.Contains($longBody)) 'oversized-unicode-body-is-complete-without-splitting'
 $sourceSelected=@($result.selectedRuleBlocks|Where-Object requirementId -like '*:SOURCE_*')
 Check (@($sourceSelected|Where-Object {$_.fullText.Contains('EXACT_SHARED_DEPENDENCY')}).Count-eq2) 'machine-result-retains-repeated-complete-dependency'
 $rendered=$projection.text
 Check ([regex]::Matches($rendered,'EXACT_SHARED_DEPENDENCY').Count-eq1) 'display-emits-shared-dependency-once'
 Check ($rendered.EndsWith('AIW-END')-and-not$projection.modelLoadProven-and$rendered-notmatch 'orderedUnitKeys|normativeIdentity|selectionIdentity|part=|page=') 'model-text-keeps-completion-and-limits-without-machine-wrapper'
 # A real transport truncation is visible; supplement only the missing body
 # from the same retained result, without creating page receipts or rediscovery.
 $cut=$rendered.IndexOf($longBody)+[int]($longBody.Length/2)
 $observed=$rendered.Substring(0,$cut)
 Check (-not$observed.EndsWith('AIW-END')-and-not$observed.Contains($longBody)) 'actual-truncated-output-identifies-missing-complete-unit'
 $supplement=@($projection.bodyUnits|Where-Object {-not$observed.Contains($_.fullText)})
 Check (@($supplement|Where-Object fullText -CEQ $longBody).Count-eq1-and($result|ConvertTo-Json -Depth 100 -Compress)-ceq$original) 'truncation-supplement-uses-only-missing-original-complete-bodies'
 $again=Get-AiwProcessDisplay $result
 Check ($again.text-ceq$projection.text) 'repeated-call-does-not-omit-previously-displayed-bodies'
 Reject {Get-AiwProcessDisplay $result -MaxPageUtf8Bytes 2048} 'active-paging-parameter-retired'
 Reject {Get-AiwProcessDisplay $result -AlreadyLoaded @($selectedIds)} 'no-unproven-already-loaded-switch'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks=@($bad.selectedRuleBlocks|Select-Object -Skip 1)
 Reject {Get-AiwProcessDisplay $bad} 'receipt-rule-without-body-refused'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks[0].fullText='truncated'
 Reject {Get-AiwProcessDisplay $bad} 'incomplete-part-body-refused'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks[0].preparationRequirements=@('INVENTED')
 Reject {Get-AiwProcessDisplay $bad} 'invented-obligation-refused'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks[0].displayParts[0].sourceIdentity='UNKNOWN'
 Reject {Get-AiwProcessDisplay $bad} 'unbound-source-cannot-be-deduplicated'
 # The actual composer projection must show the selected project mode and
 # retain its full bodies. An existing selected rule is not automatically a grant.
 $savedInput=$inputValue|ConvertTo-Json -Depth 100
 $inputValue.schemaVersion=5;$inputValue['ruleLoad']=[ordered]@{mode='FULL'}
 $policy['externalAuthorization']=[ordered]@{schemaVersion=1;mode='PROJECT_PREAUTHORIZED';grantRuleIds=@('INLINE_A')}
 SaveJson $policyPath $policy;$externalResult=Discover;$externalDisplay=Get-AiwProcessDisplay $externalResult
 Check ($externalResult.projectExternalAuthorization.mode-ceq'PROJECT_PREAUTHORIZED'-and$externalDisplay.text.Contains('Project external authorization: PROJECT_PREAUTHORIZED')-and$externalDisplay.text.Contains('INLINE_A')-and$externalDisplay.text.Contains($longBody)-and-not$externalResult.projectExternalAuthorization.perCallAuthorityGranted) 'external-mode-and-complete-selected-grant-visible-with-no-action-authority'
 Check (-not$externalDisplay.text.Contains('use the original tool directly')) 'local-action-preauthorization-does-not-suggest-direct-execution'
 $bad=$externalResult|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.projectExternalAuthorization.selectedGrantRuleIds=@('SOURCE_A')
 Reject {Get-AiwProcessDisplay $bad} 'selected-nongrant-rule-cannot-be-presented-as-project-grant'
 $bad=$externalResult|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.projectExternalAuthorization.policyIdentity='1|'+('A'*64)
 Reject {Get-AiwProcessDisplay $bad} 'mode-projection-cannot-change-bound-policy'
 $policy.externalAuthorization=[ordered]@{schemaVersion=1;mode='PER_ACTION'};SaveJson $policyPath $policy
 $perActionDisplay=Get-AiwProcessDisplay (Discover)
 Check ($perActionDisplay.text.Contains('Project external authorization: PER_ACTION')-and-not$perActionDisplay.text.Contains('Do not create a per-call task/package')) 'explicit-per-action-display-does-not-recommend-direct-execution'
 $bodySelector=[ordered]@{profiles=@('*');roles=@('*');contextTypes=@('PROJECT_READ_ONLY');facets=[ordered]@{}}
 $operationSelector=$selector|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
 $operationSelector.actionKinds=@('SOURCE_WRITE')
 $policy.rules+=@([ordered]@{ruleId='ACTIVITY_BODY';requirementReason='Read current activity body without activating its production gates';effectiveRule='COMPLETE_ACTIVITY_ONLY_BODY';selectors=$operationSelector;bodySelectors=$bodySelector;preparationRequirements=@('BODY_PRODUCTION_PREP');resultRequirements=@('BODY_PRODUCTION_RESULT');decisionLocator='fixture:explicit'})
 $policy.externalAuthorization=[ordered]@{schemaVersion=1;mode='PROJECT_PREAUTHORIZED';grantRuleIds=@('ACTIVITY_BODY')}
 SaveJson $policyPath $policy;$bodyResult=Discover;$bodyDisplay=Get-AiwProcessDisplay $bodyResult
 $only=@($bodyResult.selectedRuleBlocks|Where-Object requirementId -CEQ 'project:display-fixture:ACTIVITY_BODY')
 Check ($only.Count-eq1-and-not@($only[0].preparationRequirements).Count-and-not@($only[0].resultRequirements).Count-and'project:display-fixture:ACTIVITY_BODY'-cnotin@($bodyResult.compactReceipt.selectedObligations.requirementId)-and$bodyDisplay.text.Contains('COMPLETE_ACTIVITY_ONLY_BODY')) 'body-only-complete-text-has-no-current-operation-gates'
 Check ($bodyResult.projectExternalAuthorization.selectedGrantRuleIds.Count-eq0-and-not$bodyDisplay.text.Contains('use the original tool directly')) 'B-only-configured-grant-is-not-a-current-operation-grant'
 $bad=$bodyResult|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $bad.selectedRuleBlocks=@($bad.selectedRuleBlocks|Where-Object requirementId -CNE 'project:display-fixture:ACTIVITY_BODY')
 Reject {Get-AiwProcessDisplay $bad} 'renderer-rejects-dropped-B-only-rule'
 $bad=$bodyResult|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 @($bad.selectedRuleBlocks|Where-Object requirementId -CEQ 'project:display-fixture:ACTIVITY_BODY')[0].preparationRequirements=@('BODY_PRODUCTION_PREP')
 Reject {Get-AiwProcessDisplay $bad} 'renderer-rejects-B-only-obligation-escalation'
 $policy.rules=@($policy.rules|Where-Object ruleId -CNE 'ACTIVITY_BODY')
 $savedReadOnly=$inputValue|ConvertTo-Json -Depth 100
 $policy.externalAuthorization.grantRuleIds=@('INLINE_A');SaveJson $policyPath $policy
 $inputValue.contextType='PROJECT_EXTERNAL';$inputValue.Remove('readOnlyContext');$inputValue.taskPath='NOT_APPLICABLE';$inputValue.expectedTaskIdentity='NOT_APPLICABLE'
 $inputValue.requestContext=[ordered]@{sessionId=$inputValue.observedActor;requestId='direct-display';role='EXECUTOR';phase='EXTERNAL';profile='STANDARD'}
 $inputValue.intentEnvelope.requestedActionKind='EXTERNAL';$inputValue.intentEnvelope.requestedResultKind='EXTERNAL_RESULT'
 $direct=Discover;$directDisplay=Get-AiwProcessDisplay $direct
 Check ($direct.projectExternalAuthorization.selectedGrantRuleIds.Count-gt0-and$directDisplay.text.Contains('use the original tool directly')) 'actual-external-selected-grant-displays-direct-tool-instruction'
 $inputValue=$savedReadOnly|ConvertFrom-Json -Depth 100 -AsHashtable
 $policy.Remove('externalAuthorization');SaveJson $policyPath $policy
 $inputValue=$savedInput|ConvertFrom-Json -Depth 100 -AsHashtable
 # Same words from another file remain a distinct source, even with the same
 # exact bytes. Reuse the actual source binding builder and rediscover it.
 SaveText (Join-Path $temp 'docs/another.md') 'EXACT_SHARED_DEPENDENCY'
 $bindings[0].allowedPaths+=@([pscustomobject]@{kind='FILE';locator='docs/another.md'})
 $configuration=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
 $configuration.sourceBindings=$bindings;SaveJson $configPath $configuration
 $inputValue.expectedProjectConfigIdentity=Id $configPath
 $policy.rules[2].source.documents[0].locator='docs/another.md';$policy.rules[2].source.documents[0].identity=Id (Join-Path $temp 'docs/another.md')
 foreach($rule in @($policy.rules|Where-Object{($_ -is [Collections.IDictionary] -and $_.Contains('source')) -or $null-ne$_.PSObject.Properties['source']})){
  foreach($document in $rule.source.documents){$document.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) $bindings}
  $rule.source.revision=Get-AiwContentRevision $rule.source $bindings
  $rule.source.itemIdentity=Get-AiwContentItemIdentity $rule.source
 }
 SaveJson $policyPath $policy;$other=Get-AiwProcessDisplay (Discover)
 $otherSources=@($other.currentRules|Where-Object requirementId -like '*:SOURCE_*')
 Check ($otherSources[0].blockIds[0]-ne$otherSources[1].blockIds[0]) 'same-words-in-different-source-not-deduplicated'
 $inputValue.observedActor='new-fixture-actor';$inputValue.readOnlyContext.sessionId='new-display-session';$fresh=Get-AiwProcessDisplay (Discover)
 Check (@($fresh.currentRules).Count-eq@($other.currentRules).Count-and$fresh.text.Length-gt0-and-not$fresh.modelLoadProven) 'new-actor-output-still-contains-full-current-set'
 # Actual independent graphs whose shared unit occurs in different orders.
 # No global topology is inferred across separately adopted rule graphs.
 function OrderedRule([string]$Id,[string[]]$Order){
  $docs=@()
  for($i=0;$i-lt$Order.Count;$i++){
   $name=$Order[$i];$deps=@(if($i-gt0){$Order[$i-1]})
   $doc=[pscustomobject]@{sourceId=$name;bindingId='display-docs';revision=@{kind='CONTENT_IDENTITY';value=''};locator=('docs/'+$name+'.md');identity=(Id (Join-Path $temp ('docs/'+$name+'.md')));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=$deps}
   $doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $bindings;$docs+=$doc
  }
  $source=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='display-docs';itemId=$Id;revision=(Get-AiwContentRevision ([pscustomobject]@{documents=$docs}) $bindings);itemIdentity='';rootSourceId=$Order[-1];documents=$docs};$source.itemIdentity=Get-AiwContentItemIdentity $source
  return [ordered]@{ruleId=$Id;requirementReason='Actual ordered full-unit chain';selectors=$selector;preparationRequirements=@('PREP_'+$Id);resultRequirements=@('RESULT_'+$Id);decisionLocator='fixture:explicit';source=$source}
 }
 $policy.rules=@((OrderedRule FIRST @('A')),(OrderedRule SECOND @('B','A')),(OrderedRule THIRD @('B','A')))
 SaveJson $policyPath $policy;$orderedResult=Discover;$ordered=Get-AiwProcessDisplay $orderedResult
 $chains=@($ordered.currentRules|Where-Object requirementId -like 'project:*')
 Check ($chains.Count-eq3-and$chains[1].blockIds[0]-gt$chains[0].blockIds[0]-and$chains[1].blockIds[1]-eq$chains[0].blockIds[0]-and($chains[2].blockIds-join',')-ceq($chains[1].blockIds-join',')) 'A-once-and-rule-B-A-preserves-own-order'
 $unitText=@{};foreach($unit in $ordered.bodyUnits){$unitText[$unit.id]=$unit.fullText}
 foreach($rule in $orderedResult.selectedRuleBlocks){
  $mapping=@($ordered.currentRules|Where-Object requirementId -ceq $rule.requirementId)[0];$last=0
  foreach($number in $mapping.blockIds){Check ($unitText.ContainsKey($number)) ('complete-mapping-'+$rule.requirementId);$last=$number}
  Check ([string]::Join("`n`n",@($mapping.blockIds|ForEach-Object{$unitText[$_]}))-ceq$rule.fullText) ('whole-fulltext-reconstructed-'+$rule.requirementId)
 }
 $policy.rules=@((OrderedRule FORWARD @('A','B')),(OrderedRule REVERSE @('B','A')))
 SaveJson $policyPath $policy;$reverse=Get-AiwProcessDisplay (Discover);$chains=@($reverse.currentRules|Where-Object requirementId -like 'project:*')
 Check ($chains[0].blockIds[0]-lt$chains[0].blockIds[1]-and$chains[1].blockIds[0]-gt$chains[1].blockIds[1]) 'opposite-independent-chains-are-not-a-global-cycle'
 # Exercise current compact4 through the real composer, retaining the legacy
 # full-result branch above as an actual supported input consumer.
 $inputValue.schemaVersion=5;$inputValue.ruleLoad=@{mode='FULL'}
 $full5=Discover;$fullText=Get-AiwProcessDisplay $full5
 # The actual public call above wrote its official text from the same result.
 $official=[IO.File]::ReadAllText($script:LastDisplayPath,[Text.UTF8Encoding]::new($false,$true))
 Check ($official-ceq$fullText.text-and$global:DisplayComposerCalls-eq1) 'public-official-utf8-copy-equals-same-result-with-one-composer'
 $cut=$official.IndexOf('[1]')+3
 if($cut-lt3){throw 'OFFICIAL_BODY_ANCHOR'}
 $delivered=$official.Substring(0,$cut)
 $beforeRecoveryCalls=$global:DisplayComposerCalls
 # A length-limited consumer really receives a prefix. The remainder is read
 # from this official artifact, never from project documents or the composer.
 $reader=[IO.StreamReader]::new($script:LastDisplayPath,[Text.UTF8Encoding]::new($false,$true))
 try{$sameText=$reader.ReadToEnd();$delivered+=$sameText.Substring($cut)}finally{$reader.Dispose()}
 Check ($delivered-ceq$fullText.text-and$delivered.EndsWith('AIW-END')-and$global:DisplayComposerCalls-eq$beforeRecoveryCalls) 'limited-consumer-restores-exact-official-text-without-rediscovery'
 Check (-not$delivered.Contains('"bodyCoverage"')-and-not$delivered.Contains('"selectedRuleBlocks"')) 'official-copy-does-not-print-machine-carrier'
 $coveragePath=Join-Path $temp '.ai-workspace/runtime/display-fixture/new-fixture-actor/coverage.json'
 SaveJson $coveragePath $full5.compactReceipt.bodyCoverage
 $inputValue.ruleLoad=@{mode='REUSE';previousCoverageRef=@{path=$coveragePath;identity=(Id $coveragePath)}}
 $reuse5=Discover;$reusedText=Get-AiwProcessDisplay $reuse5
 Check ($reusedText.contextBodyReuse-ceq'FULL'-and$reusedText.bodyUnits.Count-eq$fullText.bodyUnits.Count-and$reusedText.currentRules.Count-eq$fullText.currentRules.Count-and$reusedText.text.Contains('PREP_FORWARD')) 'legacy-reuse-displays-all-current-bodies-order-and-obligations'
 Check ([IO.File]::ReadAllText($script:LastDisplayPath,$utf8)-ceq$reusedText.text) 'public-reused-official-copy-keeps-mode-map-and-obligations'
 $policy.rules+=@([ordered]@{ruleId='DELTA';requirementReason='New complete unit';effectiveRule='DELTA_COMPLETE_中文🙂';selectors=$selector;preparationRequirements=@('DELTA_PREP');resultRequirements=@('DELTA_RESULT');decisionLocator='fixture:delta'})
 SaveJson $policyPath $policy;$delta5=Discover;$deltaText=Get-AiwProcessDisplay $delta5
 Check ($deltaText.contextBodyReuse-ceq'FULL'-and$deltaText.bodyUnits.Count-eq($fullText.bodyUnits.Count+1)-and$deltaText.text.Contains('DELTA_COMPLETE_中文🙂')-and$deltaText.text.Contains('DELTA_PREP')-and$deltaText.text.Contains('DELTA_RESULT')) 'changed-selection-displays-all-current-complete-bodies-and-obligations'
 Check ([IO.File]::ReadAllText($script:LastDisplayPath,$utf8)-ceq$deltaText.text) 'public-delta-official-copy-keeps-complete-unicode-unit'
 $bad=$full5|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
 $chain=@($bad.modelView.currentRules|Where-Object requirementId -like '*:FORWARD')[0]
 [Array]::Reverse($chain.orderedUnitKeys)
 Reject {Get-AiwProcessDisplay $bad} 'current-rule-order-must-match-machine-coverage'
 $anticipated=$full5|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
 $anticipated.modelView.anticipatedSteps=@([pscustomobject]@{stepId='future-test'})
 Reject {Get-AiwProcessDisplay $anticipated} 'renderer-rejects-retired-future-preload'
 $incomplete=$full5|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
 $incomplete.modelView.uniqueUnits=@($incomplete.modelView.uniqueUnits|Select-Object -Skip 1)
 Reject {Get-AiwProcessDisplay $incomplete} 'renderer-rejects-missing-current-body'
 $originalDisplayBytes=Id $script:LastDisplayPath
 $savedDisplayPath=$script:LastDisplayPath
 $global:LASTEXITCODE=0;$collision=@(& $resolver -InputPath $inputPath -AsJson -DisplayPath $savedDisplayPath)
 Check ($global:LASTEXITCODE-ne0-and(Id $savedDisplayPath)-ceq$originalDisplayBytes) 'display-create-new-refuses-existing-official-copy'
 $denied=Join-Path (Split-Path -Parent $savedDisplayPath) 'denied.txt'
 $inputValue.forbiddenPaths=@([IO.Path]::GetRelativePath($temp,$denied).Replace('\','/'));SaveJson $inputPath $inputValue
 $global:LASTEXITCODE=0;$denial=@(& $resolver -InputPath $inputPath -AsJson -DisplayPath $denied)
 Check ($global:LASTEXITCODE-ne0-and-not(Test-Path -LiteralPath $denied)-and($denial-join'').Contains('EVIDENCE_PATH_FORBIDDEN')) 'display-protection-refuses-output-without-writing'
 $inputValue.forbiddenPaths=@();SaveJson $inputPath $inputValue
 # Obtain a real failed resolver result, preserving its actual reason.
 $inputValue['unexpectedField']=$true;SaveJson $inputPath $inputValue
 $directory=Join-Path $temp ('.ai-workspace/runtime/display-fixture/'+$inputValue.observedActor)
 $null=[IO.Directory]::CreateDirectory($directory)
 $script:LastDisplayPath=Join-Path $directory ([guid]::NewGuid().ToString('N')+'.txt')
 $global:DisplayComposerCalls=0
 $probe=Set-PSBreakpoint -Command Invoke-AiwProcessCompositionCore -Action {$global:DisplayComposerCalls++}
 try{$global:LASTEXITCODE=0;$lines=@(& $resolver -InputPath $inputPath -AsJson -DisplayPath $script:LastDisplayPath)}finally{Remove-PSBreakpoint $probe}
 if($global:DisplayComposerCalls-ne0){throw ('REJECTED_INPUT_COMPOSER_COUNT|'+$global:DisplayComposerCalls)}
 if(($lines-join'')-match'[^\x00-\x7f]'){throw 'MACHINE_NATIVE_TRANSPORT_NOT_ASCII'};$failed=($lines-join"`n")|ConvertFrom-Json -Depth 100
 Check ($global:LASTEXITCODE-ne0-and$failed.status-ceq'FAIL') 'failure-fixture-is-an-actual-resolver-rejection'
 $failureDisplay=Get-AiwProcessDisplay $failed
 Check ($failureDisplay.status-ceq'FAIL'-and$failureDisplay.text.Contains($failed.reason)) 'failure-reason-is-not-hidden-by-projection'
 Write-Output ('RULE_DISPLAY_TESTS_PASS|checks='+$passed+'|evidence=OUTPUT_PROJECTION_NOT_MODEL_LOAD')
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$systemTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($resolved)-cne$systemTemp-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-rule-display-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
