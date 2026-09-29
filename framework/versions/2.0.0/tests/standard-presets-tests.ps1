[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$passed=0;$utf8=[Text.UTF8Encoding]::new($false)
$versionRoot=Split-Path -Parent $PSScriptRoot
$frameworkRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-standard-presets-'+[guid]::NewGuid().ToString('N'))
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 60)}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw "ASSERT_FAIL|$Name"};$script:passed++;Write-Output "PASS|$Name"}
function Reject([scriptblock]$Action,[string]$Pattern,[string]$Name){$reason='';try{& $Action|Out-Null}catch{$reason=$_.Exception.Message};Check ($reason-match$Pattern) ($Name+'|'+$reason)}
function Compose([string]$Role,[string]$Action,[string]$Hints){
 $phase=if($Role-ceq'REVIEWER'){'REVIEW'}else{'IMPLEMENT'}
 $result=if($Role-ceq'REVIEWER'){'REVIEW_VERDICT'}else{'IMPLEMENTATION_RESULT'}
 return Invoke-ProcessRequirementComposition -ProjectRoot $project -FrameworkRoot $frameworkRoot -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity (Get-AiwFileIdentity $configPath) -ExpectedCorrectionsIdentity (Get-AiwFileIdentity $correctionsPath) -Profile STANDARD -Role $Role -Phase $phase -Actor fixture-actor -TaskIdentity (Get-AiwFileIdentity $taskPath) -ActionKind $Action -ResultKind $result -Objective $Hints -ExactPaths @() -EvaluationOnly
}
function ProjectRules($Result){return @($Result.selectedRequirements|Where-Object{$_.requirementId.StartsWith('project:')})}
try{
 $project=Join-Path $temp 'project';$copy=Join-Path $temp 'bundle'
 $null=[IO.Directory]::CreateDirectory((Join-Path $copy 'scripts'))
 foreach($module in @('ProcessRequirementComposition.psm1','KnowledgeSources.psm1','StrictJsonInput.psm1')){
  Copy-Item -LiteralPath (Join-Path $versionRoot ('scripts/'+$module)) -Destination (Join-Path $copy ('scripts/'+$module))
 }
 Copy-Item -LiteralPath (Join-Path $versionRoot 'standards') -Destination (Join-Path $copy 'standards') -Recurse
 Import-Module (Join-Path $copy 'scripts/ProcessRequirementComposition.psm1') -Force
 $configPath=Join-Path $project '.ai-workspace/project.json';$correctionsPath=Join-Path $project '.ai-workspace/corrections.json';$policyPath=Join-Path $project '.ai-workspace/process-policy.json';$taskPath=Join-Path $project '.ai-workspace/tasks/active/STANDARDS-001.md'
 SaveJson $configPath ([ordered]@{schemaVersion=5;id='standards-fixture';displayName='Standards fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}})
 SaveJson $correctionsPath ([ordered]@{schemaVersion=2;contractVersion='2.0.0';projectId='standards-fixture';corrections=@()})
 SaveJson (Join-Path $project '.ai-workspace/controller.json') ([ordered]@{schemaVersion=1;projectId='standards-fixture';controllerId='fixture-actor';controllerEpoch=1;state='CURRENT'})
 SaveText (Join-Path $project '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 SaveText $taskPath "# STANDARDS-001`n- Owner: fixture-actor`n- Work route: actor=fixture-actor; role=TASK_OWNER; phase=PLAN`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]"
 $policy=[ordered]@{schemaVersion=1;contractVersion='2.0.0';projectId='standards-fixture';selectedRulePackBytes=98304;rules=@()};SaveJson $policyPath $policy
 $policyBefore=Get-AiwFileIdentity $policyPath
 $rules=@(Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:adopt-fixed-software')
 Check ($rules.Count-eq3-and(Get-AiwFileIdentity $policyPath)-ceq$policyBefore) 'expansion-does-not-adopt-or-write-policy'
 Check (@(ProjectRules (Compose EXECUTOR SOURCE_WRITE 'API implementation software test')).Count-eq0) 'unadopted-standards-not-selected'
 Check (@($rules|Where-Object{$_.decisionLocator-cne'fixture:adopt-fixed-software'}).Count-eq0) 'original-project-decision-bound'
 foreach($rule in $rules){$doc=$rule.source.documents[0];Check ($doc.locatorKind-ceq'ABSOLUTE_FILE'-and$doc.identity-ceq(Get-AiwFileIdentity $doc.locator)-and$doc.locator.StartsWith($copy)) ('exact-source-'+$rule.ruleId)}
 $policy.rules=$rules;SaveJson $policyPath $policy
 $author=Compose EXECUTOR SOURCE_WRITE 'API implementation software test'
 $review=Compose REVIEWER REVIEW_EXECUTE 'review API implementation software test'
 $authorRules=@(ProjectRules $author);$reviewRules=@(ProjectRules $review)
 Check ($authorRules.Count-eq3-and$reviewRules.Count-eq3-and($authorRules.requirementId-join'|')-ceq($reviewRules.requirementId-join'|')) 'author-and-reviewer-share-adopted-quality'
 foreach($rule in $rules){$body=[IO.File]::ReadAllText($rule.source.documents[0].locator).TrimEnd("`n");$selected=@($reviewRules|Where-Object{$_.requirementId.EndsWith(':'+$rule.ruleId)})[0];Check ($selected.fullText.Contains($body)) ('review-loads-complete-body-'+$rule.ruleId)}
 Check (@(ProjectRules (Compose REVIEWER REVIEW_EXECUTE 'review illustration layout')).Count-eq0) 'unrelated-profession-does-not-load-software'
 $design=@(ProjectRules (Compose REVIEWER REVIEW_EXECUTE 'review API design'))
 Check ($design.Count-eq1-and$design[0].requirementId.EndsWith(':SOFTWARE_DESIGN')) 'no-path-design-review-selects-applicable-standard'
 $beforeChange=$review.sourceCompositionIdentity
 $source=$rules[0].source.documents[0].locator;$oldBody=[IO.File]::ReadAllText($source)
 SaveText $source ($oldBody+"`nExplicit changed source for drift evidence.")
 $drift=Compose REVIEWER REVIEW_EXECUTE 'review illustration layout'
 Check ($drift.sourceCompositionIdentity-cne$beforeChange-and@(ProjectRules $drift|Where-Object{$_.fullText.Contains('Explicit changed source')}).Count-eq1) 'source-drift-invalidates-composition-and-forces-complete-current-body'
 $rules=@(Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator 'fixture:authorized-follow-update')
 $policy.rules=$rules;SaveJson $policyPath $policy
 Check (@(ProjectRules (Compose REVIEWER REVIEW_EXECUTE 'review illustration layout')).Count-eq0) 'explicit-rebind-restores-normal-selection'
 $policy.rules=@([ordered]@{ruleId='PROJECT_DESIGN';requirementReason='Project replaces the adopted design standard';effectiveRule='Replacement-only design requirement.';selectors=$rules[0].selectors;preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:replace-standard'})+@($rules|Where-Object ruleId -cne SOFTWARE_DESIGN)
 SaveJson $policyPath $policy
 $replacement=@(ProjectRules (Compose REVIEWER REVIEW_EXECUTE 'review API design'))
 Check ($replacement.Count-eq1-and$replacement[0].fullText-ceq'Replacement-only design requirement.') 'one-policy-change-replaces-without-duplicate-must'
 Check (@((Compose REVIEWER REVIEW_EXECUTE 'review API design').selectedRequirements|Where-Object requirementId -ceq 'framework:PR_ACTION_AUTHORIZATION_INDEPENDENT').Count-eq1) 'optional-replacement-does-not-suppress-core'
 Reject {Expand-AiwProcessPreset -PresetId '../software' -ProjectRoot $project -DecisionLocator fixture} 'ValidatePattern|pattern|模式|匹配' 'preset-id-cannot-traverse'
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator ' '} 'PRESET_DECISION_REQUIRED' 'missing-project-decision-rejected'
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $temp -DecisionLocator fixture -ForbiddenPaths @('bundle/standards/software')} 'FORBIDDEN' 'source-protection-before-hash'
 $presetPath=Join-Path $copy 'standards/presets/software.json';$originalPreset=[IO.File]::ReadAllText($presetPath)
 function FaultPreset([scriptblock]$Change){$p=$originalPreset|ConvertFrom-Json;& $Change $p;SaveJson $presetPath $p}
 FaultPreset {param($p)$p.rules[0].source.documents[0].locator='standards/software/../../../outside.md'}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'COMPONENT' 'document-cannot-escape-version'
 FaultPreset {param($p)$p.rules[0].source.documents[0].dependencies=@('MISSING_SOURCE')}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'DEPENDENCY_UNKNOWN' 'incomplete-source-closure-rejected'
 FaultPreset {param($p)$p.rules[1].ruleId=$p.rules[0].ruleId}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'PRESET_RULE_VALUES' 'duplicate-rule-id-rejected'
 FaultPreset {param($p)$p.rules[0]|Add-Member -NotePropertyName effectiveRule -NotePropertyValue 'second authority'}
 Reject {Expand-AiwProcessPreset -PresetId software -ProjectRoot $project -DecisionLocator fixture} 'PRESET_RULE_FIELDS' 'preset-cannot-add-second-rule-body'
 SaveText $presetPath $originalPreset
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.git'))-and-not(Test-Path -LiteralPath (Join-Path $project '.gitignore'))) 'standards-expansion-and-composition-require-no-git'
 Write-Output ('STANDARD_PRESETS_TESTS_PASS|checks='+$passed+'|evidence=PROJECT_POLICY_AND_SOURCE_BINDINGS')
}finally{
 $resolved=[IO.Path]::GetFullPath($temp);$systemTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($resolved)-cne$systemTemp-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-standard-presets-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
