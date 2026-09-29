[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$passed=0;$utf8=[Text.UTF8Encoding]::new($false,$true)
$versionRoot=Split-Path -Parent $PSScriptRoot
$frameworkRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
$resolver=Join-Path $versionRoot 'scripts/resolve-process-requirements.ps1'
Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementDisplay.psm1') -Force
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 70)}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw "ASSERT_FAIL|$Name"};$script:passed++;Write-Output "PASS|$Name"}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Name}
function Discover {
 SaveJson $inputPath $inputValue
 $global:LASTEXITCODE=0;$lines=@(& $resolver -InputPath $inputPath -AsJson)
 $code=$global:LASTEXITCODE;$value=($lines-join"`n")|ConvertFrom-Json -Depth 100
 if($code-ne0){throw ($lines-join"`n")};return $value
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-rule-display-'+[guid]::NewGuid().ToString('N'))
try{
 $configPath=Join-Path $temp '.ai-workspace/project.json';$correctionsPath=Join-Path $temp '.ai-workspace/corrections.json';$policyPath=Join-Path $temp '.ai-workspace/process-policy.json';$inputPath=Join-Path $temp 'display-input.json'
 SaveJson $configPath ([ordered]@{schemaVersion=5;id='display-fixture';displayName='Display fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
 SaveJson $correctionsPath ([ordered]@{schemaVersion=2;contractVersion='2.0.0';projectId='display-fixture';corrections=@()})
 SaveJson (Join-Path $temp '.ai-workspace/controller.json') ([ordered]@{schemaVersion=1;projectId='display-fixture';controllerId='fixture-actor';controllerEpoch=1;state='CURRENT'})
 SaveText (Join-Path $temp '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 $selector=[ordered]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@('display fixture')}
 $longBody='完整规则🙂'+("`n中文、emoji🚲与精确原始正文。"*900)
 $policy=[ordered]@{schemaVersion=1;contractVersion='2.0.0';projectId='display-fixture';selectedRulePackBytes=98304;rules=@()}
 $policy.rules+=@([ordered]@{ruleId='INLINE_A';requirementReason='Complete oversized Unicode rule';effectiveRule=$longBody;selectors=$selector;preparationRequirements=@('PREP_A');resultRequirements=@('RESULT_A');decisionLocator='fixture:explicit'})
 SaveText (Join-Path $temp 'docs/shared.md') 'EXACT_SHARED_DEPENDENCY'
 foreach($name in @('A','B')){
  SaveText (Join-Path $temp ('docs/'+$name+'.md')) ('DISTINCT_ROOT_'+$name)
  $docs=@()
  foreach($part in @('shared',$name)){$docs+=@([ordered]@{sourceId=$part.ToUpperInvariant();locator=('docs/'+$part+'.md');identity=(Id (Join-Path $temp ('docs/'+$part+'.md')));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@(if($part-ceq$name){'SHARED'})})}
  $policy.rules+=@([ordered]@{ruleId=('SOURCE_'+$name);requirementReason='Two standards depend on the same real document';selectors=$selector;preparationRequirements=@('SOURCE_PREP_'+$name);resultRequirements=@('SOURCE_RESULT_'+$name);decisionLocator='fixture:explicit';source=[ordered]@{rootSourceId=$name;documents=$docs}})
 }
 SaveJson $policyPath $policy
 $inputValue=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=[ordered]@{sessionId='display-session';requestId='display-fixture';role='EXECUTOR';phase='PLAN';profile='STANDARD'};projectRoot=$temp;frameworkRoot=$frameworkRoot;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=Id $configPath;expectedCorrectionsIdentity=Id $correctionsPath;expectedTaskIdentity='NOT_APPLICABLE';observedActor='fixture-actor';capabilities=@();exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Explain the explicitly supplied display fixture rules.';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('display fixture');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$true}
 $result=Discover;$original=$result|ConvertTo-Json -Depth 100 -Compress
 $projection=Get-AiwProcessDisplay $result -MaxPageUtf8Bytes 2048
 Check ($projection.status-ceq'EVALUATION_ONLY'-and$projection.contextBodyReuse-ceq'UNSUPPORTED_FULLTEXT_FALLBACK'-and-not$projection.modelLoadProven) 'display-keeps-evaluation-and-context-ceiling'
 $selectedIds=@($result.selectedRuleBlocks.requirementId)
 Check ([string]::Join('|',@($projection.currentRules.requirementId))-ceq[string]::Join('|',$selectedIds)) 'projection-keeps-exact-current-selection-and-order'
 Check (($result|ConvertTo-Json -Depth 100 -Compress)-ceq$original) 'projection-does-not-mutate-resolver-result'
 $inlineRules=@($projection.currentRules|Where-Object requirementId -like '*:INLINE_*')
 Check ($inlineRules.Count-eq1) 'one-valid-oversized-inline-rule-selected'
 $obligations=@($projection.obligations|Where-Object requirementId -like 'project:*')
 Check ('SOURCE_PREP_A'-cin@($obligations.preparationRequirements)-and'SOURCE_PREP_B'-cin@($obligations.preparationRequirements)-and'SOURCE_RESULT_A'-cin@($obligations.resultRequirements)-and'SOURCE_RESULT_B'-cin@($obligations.resultRequirements)) 'dedup-retains-independent-obligation-union'
 $sourceRules=@($projection.currentRules|Where-Object requirementId -like '*:SOURCE_*')
 Check ($sourceRules.Count-eq2-and$sourceRules[0].blockIds[0]-eq$sourceRules[1].blockIds[0]-and$sourceRules[0].blockIds[1]-ne$sourceRules[1].blockIds[1]) 'shared-dependency-dedup-keeps-distinct-roots'
 $segments=@($projection.pages|ForEach-Object {$_.segments})
 $bodySegments=@($segments|Where-Object sectionId -eq $inlineRules[0].blockIds[0])
 Check ($bodySegments.Count-gt1-and[string]::Join('',@($bodySegments.fullTextSlice))-ceq$longBody) 'oversized-unicode-body-reassembles-byte-exactly'
 Check (@($projection.pages|Where-Object {$utf8.GetByteCount($_.text)-gt2048}).Count-eq0) 'every-rendered-page-fits-known-byte-budget'
 $sourceSelected=@($result.selectedRuleBlocks|Where-Object requirementId -like '*:SOURCE_*')
 Check (@($sourceSelected|Where-Object {$_.fullText.Contains('EXACT_SHARED_DEPENDENCY')}).Count-eq2) 'machine-result-retains-repeated-complete-dependency'
 $rendered=$projection.pages.text-join"`n"
 Check ([regex]::Matches($rendered,'EXACT_SHARED_DEPENDENCY').Count-eq1) 'display-emits-shared-dependency-once'
 $complete=Assert-AiwProcessDisplayPages $projection @($projection.pages.text)
 Check ($complete.status-ceq'PASS'-and-not$complete.modelLoadProven) 'complete-page-check-does-not-prove-model-attention'
 Reject {Assert-AiwProcessDisplayPages $projection @($projection.pages.text|Select-Object -Skip 1)} 'missing-page-refused'
 $reversed=@($projection.pages.text);[Array]::Reverse($reversed)
 Reject {Assert-AiwProcessDisplayPages $projection $reversed} 'reordered-pages-refused'
 $duplicate=@($projection.pages.text);$duplicate[1]=$duplicate[0]
 Reject {Assert-AiwProcessDisplayPages $projection $duplicate} 'duplicate-page-refused'
 $truncated=@($projection.pages.text);$truncated[-1]=$truncated[-1].Substring(0,$truncated[-1].Length-8)
 Reject {Assert-AiwProcessDisplayPages $projection $truncated} 'missing-footer-truncation-refused'
 $again=Get-AiwProcessDisplay $result -MaxPageUtf8Bytes 2048
 Check ([string]::Join('',@($again.pages.text))-ceq[string]::Join('',@($projection.pages.text))) 'repeated-call-does-not-omit-previously-displayed-bodies'
 Reject {Get-AiwProcessDisplay $result -AlreadyLoaded @($selectedIds)} 'no-unproven-already-loaded-switch'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks=@($bad.selectedRuleBlocks|Select-Object -Skip 1)
 Reject {Get-AiwProcessDisplay $bad} 'receipt-rule-without-body-refused'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks[0].fullText='truncated'
 Reject {Get-AiwProcessDisplay $bad} 'incomplete-part-body-refused'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks[0].preparationRequirements=@('INVENTED')
 Reject {Get-AiwProcessDisplay $bad} 'invented-obligation-refused'
 $bad=$original|ConvertFrom-Json -Depth 100;$bad.selectedRuleBlocks[0].displayParts[0].sourceIdentity='UNKNOWN'
 Reject {Get-AiwProcessDisplay $bad} 'unbound-source-cannot-be-deduplicated'
 # Same words from another file remain a distinct source, even with the same
 # exact bytes. Reuse the actual source binding builder and rediscover it.
 SaveText (Join-Path $temp 'docs/another.md') 'EXACT_SHARED_DEPENDENCY'
 $policy.rules[2].source.documents[0].locator='docs/another.md';$policy.rules[2].source.documents[0].identity=Id (Join-Path $temp 'docs/another.md')
 SaveJson $policyPath $policy;$other=Get-AiwProcessDisplay (Discover)
 $otherSources=@($other.currentRules|Where-Object requirementId -like '*:SOURCE_*')
 Check ($otherSources[0].blockIds[0]-ne$otherSources[1].blockIds[0]) 'same-words-in-different-source-not-deduplicated'
 $inputValue.observedActor='new-fixture-actor';$inputValue.readOnlyContext.sessionId='new-display-session';$fresh=Get-AiwProcessDisplay (Discover)
 Check (@($fresh.currentRules).Count-eq@($other.currentRules).Count-and$fresh.pages.Count-gt0-and-not$fresh.modelLoadProven) 'new-actor-output-still-contains-full-current-set'
 # Obtain a real failed resolver result, preserving its actual reason.
 $inputValue['unexpectedField']=$true;SaveJson $inputPath $inputValue
 $global:LASTEXITCODE=0;$lines=@(& $resolver -InputPath $inputPath -AsJson);$failed=($lines-join"`n")|ConvertFrom-Json -Depth 100
 Check ($global:LASTEXITCODE-ne0-and$failed.status-ceq'FAIL') 'failure-fixture-is-an-actual-resolver-rejection'
 $failureDisplay=Get-AiwProcessDisplay $failed -MaxPageUtf8Bytes 2048
 Check ($failureDisplay.status-ceq'FAIL'-and($failureDisplay.pages.text-join"`n").Contains($failed.reason)) 'failure-reason-is-not-hidden-by-projection'
 Write-Output ('RULE_DISPLAY_TESTS_PASS|checks='+$passed+'|evidence=OUTPUT_PROJECTION_NOT_MODEL_LOAD')
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$systemTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($resolved)-cne$systemTemp-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-rule-display-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
