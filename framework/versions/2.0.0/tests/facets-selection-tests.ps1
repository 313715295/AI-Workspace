[CmdletBinding()]param([ValidateSet('FINDING','REPAIRED','INITIAL','TEST_ONLY','APPROVED','INITIAL_TEST','REPAIRED_TEST')][string[]]$RootReviewCases=@('FINDING','REPAIRED','INITIAL','TEST_ONLY','APPROVED','INITIAL_TEST','REPAIRED_TEST'))
. (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly
$composer=Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru
Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionState.psm1') -Force
# Entry-owned runtime members serve both real compositor and operation fixtures.
$facetsRuntimeVersionPaths=@(
 'ACCEPTANCE_PLAN_SCHEMA.json'
 'ADOPTION_PROFILE.json'
 'AUTHORITY_CONTEXT_SCHEMA.json'
 'AUTHORIZATION_MODEL.md'
 'CHANGELOG.md'
 'CONTENT_CATALOG_SCHEMA.json'
 'CONTROL_TRANSITION_SCHEMA.json'
 'CONTROLLER_SCHEMA.json'
 'EVIDENCE_RECORD_SCHEMA.json'
 'EXAMPLES.md'
 'GIT_AND_EXTERNAL.md'
 'HOST_CODEX.md'
 'host/skills/ai-workspace-router-v2/SKILL.md'
 'INTENT_ENVELOPE_SCHEMA.json'
 'KNOWLEDGE_AND_REFERENCE.md'
 'KNOWLEDGE_SCHEMA.json'
 'knowledge/cross-domain/ARTIFACT_CLASSIFICATION.md'
 'knowledge/cross-domain/PROBLEM_DRIVEN_IMPROVEMENT.md'
 'knowledge/game/BEHAVIOR_AND_PERFORMANCE.md'
 'knowledge/game/PRESENTATION_AUTHORITY.md'
 'knowledge/game/UI_INPUT_CANCELLATION.md'
 'knowledge/index.json'
 'knowledge/README.md'
 'knowledge/software/BEHAVIOR_SPEC_CHANGE.md'
 'LOAD_MANIFEST.json'
 'MIGRATION_MATRIX.md'
 'NORMATIVE_SURFACE_INVENTORY.json'
 'object-formats/adapters/knowledge-index-1-to-2.ps1'
 'object-formats/adapters/knowledge-index-2-to-3.ps1'
 'object-formats/adapters/process-policy-1-to-2.ps1'
 'object-formats/adapters/project-config-4-to-5.ps1'
 'object-formats/adapters/project-config-5-to-6.ps1'
 'object-formats/adapters/project-corrections-1-to-2.ps1'
 'object-formats/adapters/project-corrections-2-to-3.ps1'
 'object-formats/ASSEMBLY.json'
 'PERSPECTIVE_LENSES.md'
 'PROCESS_POLICY_SCHEMA.json'
 'PROCESS_REQUIREMENTS_EVALUATION.md'
 'PROCESS_REQUIREMENTS.json'
 'PROJECT_CONFIG_SCHEMA.json'
 'PROJECT_CONTROL.md'
 'PROJECT_CORRECTIONS_SCHEMA.json'
 'project-starter/.gitattributes'
 'project-starter/AGENTS.md'
 'project-starter/BOOTSTRAP.md'
 'project-starter/controller.json'
 'project-starter/corrections.json'
 'project-starter/process-policy.json'
 'project-starter/project.json'
 'project-starter/PROJECT.md'
 'project-starter/STATUS.md'
 'project-starter/tasks/README.md'
 'PROMPTS.md'
 'README.md'
 'RECOVERY_CORE.md'
 'requirements/fragments/AUTHORIZATION_MODEL.json'
 'requirements/fragments/GIT_AND_EXTERNAL.json'
 'requirements/fragments/HOST_CODEX.json'
 'requirements/fragments/KNOWLEDGE_AND_REFERENCE.json'
 'requirements/fragments/PROJECT_CONTROL.json'
 'requirements/fragments/RECOVERY_CORE.json'
 'requirements/fragments/REVIEW_AND_EVIDENCE.json'
 'requirements/fragments/TASK_AND_SCOPE.json'
 'REVIEW_AND_EVIDENCE.md'
 'scripts/AuthorizationCheck.psm1'
 'scripts/bind-receiver-authorization.ps1'
 'scripts/build-process-requirements.ps1'
 'scripts/check-authorization.ps1'
 'scripts/check-knowledge-entry.ps1'
 'scripts/check-knowledge-impact.ps1'
 'scripts/check-project-corrections.ps1'
 'scripts/check-task-card.ps1'
 'scripts/ContentSources.psm1'
 'scripts/ControlTransition.psm1'
 'scripts/invoke-protected-safe-git.ps1'
 'scripts/KnowledgeSources.psm1'
 'scripts/ObjectFormats.psm1'
 'scripts/ProcessRequirementBoundary.psm1'
 'scripts/ProcessRequirementComposition.psm1'
 'scripts/ProcessRequirementDisplay.psm1'
 'scripts/ProjectSourcePublication.psm1'
 'scripts/resolve-control-transition.ps1'
 'scripts/resolve-load-plan.ps1'
 'scripts/resolve-process-requirements.ps1'
 'scripts/resolve-workflow-route.ps1'
 'scripts/ResultEvidence.psm1'
 'scripts/StrictJsonInput.psm1'
 'scripts/WorkflowDelivery.psm1'
 'standards/presets/software.json'
 'standards/README.md'
 'standards/software/DESIGN.md'
 'standards/software/IMPLEMENTATION.md'
 'standards/software/VALIDATION.md'
 'STATIC_COMPARISON.md'
 'TASK_AND_SCOPE.md'
 'TASK_TEMPLATE.md'
 'TOOL_CONTRACT.md'
 'TOOLCHAIN.json'
 'VERSION.json'
 'scripts/ReleaseValidation.psm1'
 'tests/TestExecutionRuntime.psm1'
 'scripts/TestEvidenceValidation.psm1'
 'scripts/ExecutionTargetContext.psm1'
 'EXECUTION_TARGET_SCHEMA.json'
 'object-formats/adapters/project-config-6-to-7.ps1'
 'object-formats/adapters/process-policy-2-to-3.ps1'
 'tests/PROCESS_REQUIREMENTS_FIXTURES.json'
 'tests/PROCESS_REQUIREMENTS_BUDGETS.json'
 'tests/measure-process-requirements.ps1'
 'tests/TestNativeOutput.psm1'
)
$catalog=Get-Content -LiteralPath (Join-Path $versionRoot 'PROCESS_REQUIREMENTS.json') -Raw|ConvertFrom-Json -Depth 100
$native=Get-AiwFacetVocabulary -NativeVocabulary $catalog.facetVocabulary
function Facets([string]$Work='aiw:implementation',[string]$Stage='aiw:implementation'){
 [pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=@('aiw:software')};workType=[pscustomobject]@{state='KNOWN';values=@($Work)};deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:code')};stage=[pscustomobject]@{state='KNOWN';values=@($Stage)}}
}
function Selector($Facets){[pscustomobject]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@('review','upgrade');facets=$Facets}}
function Match($Selector,$Facets,[string]$Action='SOURCE_WRITE',[string]$Profile='STANDARD',[string]$Role='EXECUTOR',[string]$Phase='IMPLEMENT',[string[]]$Paths=@('src/current.js'),[string[]]$Capabilities=@(),[string]$Context='UNKNOWN'){
 & $composer {param($s,$f,$a,$p,$r,$h,$paths,$caps,$ctx) Test-AiwRuleMatch $s $p $r $h $a 'IMPLEMENTATION_RESULT' $paths $caps 'review upgrade mapping do-not-write after-confirmation' $false $f $ctx} $Selector $Facets $Action $Profile $Role $Phase $Paths $Capabilities $Context
}
$intent=ConvertTo-AiwIntentFacets (Facets) $native
Check ($catalog.schemaVersion-eq3-and$catalog.catalogVersion-ceq'4'-and$catalog.requirements.Count-eq46) 'native-complete-units-retain-current-metadata-contract'
$restriction=Selector ([pscustomobject]@{domain=@('aiw:software','aiw:knowledge');workType=@('aiw:implementation','aiw:review');stage=@('aiw:implementation')})
Check (Match $restriction $intent).Match 'within-dimension-OR-and-across-dimension-AND'
$other=Clone $intent;$other.domain.values=@('aiw:architecture')
Check (-not(Match $restriction $other).Match) 'no-implied-domain-parent-hierarchy'
$other=Clone $intent;$other.stage.values=@('aiw:review')
Check (-not(Match $restriction $other).Match) 'one-known-mismatched-dimension-rejects'
$other=Clone $intent;$other.workType.values=@('aiw:discussion','aiw:implementation')
Check (Match $restriction $other).Match 'multiple-current-work-values-explicitly-intersect'
$unknown=Clone $intent;$unknown.stage=[pscustomobject]@{state='UNKNOWN';values=@()}
Check ((Match $restriction $unknown).Decision-ceq'CONSERVATIVE') 'unknown-retains-within-known-bounds'
$na=Clone $intent;$na.stage=[pscustomobject]@{state='NOT_APPLICABLE';values=@()}
Check (-not(Match $restriction $na).Match) 'not-applicable-excludes-restricted-dimension'
Check (Match (Selector ([pscustomobject]@{})) $na).Match 'omitted-selector-dimension-unrestricted'
foreach($axis in @('profiles','roles','phases','actionKinds','resultKinds','pathPrefixes','capabilities')){
 $s=Clone $restriction
 switch($axis){profiles{$s.profiles=@('CRITICAL')};roles{$s.roles=@('REVIEWER')};phases{$s.phases=@('REVIEW')};actionKinds{$s.actionKinds=@('REVIEW_EXECUTE')};resultKinds{$s.resultKinds=@('REVIEW_VERDICT')};pathPrefixes{$s.pathPrefixes=@('other/')};capabilities{$s.capabilities=@('KNOWLEDGE_REFERENCE')}}
 Check ((Match $s $unknown).Decision-ceq'NO_MATCH') ('known-'+$axis+'-mismatch-precedes-unknown-facets')
}
$s=Clone $restriction;$s.pathPrefixes=@('src')
Check (-not(Match $s $intent -Paths @('src-other/current.js')).Match) 'path-prefix-is-a-segment-boundary'
$s=Clone $restriction;$s|Add-Member deterministicTriggers ([pscustomobject]@{actionKinds=@('SOURCE_WRITE');resultKinds=@()})
$stageMismatch=Clone $intent;$stageMismatch.stage.values=@('aiw:review')
Check (-not(Match $s $stageMismatch).Match) 'legacy-trigger-does-not-override-known-facet-mismatch'
$reviewRule=@($catalog.requirements|Where-Object requirementId -CEQ 'PR_CRITICAL_REVIEW_INDEPENDENCE')[0]
$planning=ConvertTo-AiwIntentFacets (Facets 'aiw:planning' 'aiw:planning') $native
Check (-not(Match $reviewRule.selectors $planning -Action NONE -Profile CRITICAL -Role REVIEWER -Phase PLAN).Match) 'future-review-in-current-discussion-does-not-select-execution-rule'
$review=ConvertTo-AiwIntentFacets (Facets 'aiw:review' 'aiw:review') $native
Check (Match $reviewRule.selectors $review -Action REVIEW_EXECUTE -Profile CRITICAL -Role REVIEWER -Phase REVIEW).Match 'actual-review-with-no-write-still-loads-independence'
$adoptionRule=@($catalog.requirements|Where-Object requirementId -CEQ 'PR_PROJECT_UPGRADE_ACTOR_BOUND')[0]
Check (-not(Match $adoptionRule.selectors $planning -Action NONE -Profile CRITICAL -Phase PLAN -Paths @('.ai-workspace/project.json')).Match) 'discussion-of-upgrade-is-not-adoption-write'
$governance=Clone $planning;$governance.domain.values=@('aiw:governance');$governance.workType.values=@('aiw:adoption')
Check (Match $adoptionRule.selectors $governance -Action CONTROL_WRITE -Profile CRITICAL -Phase PLAN -Paths @('.ai-workspace/project.json')).Match 'actual-adoption-with-current-structural-facts-selects'
$auxOnly=Selector ([pscustomobject]@{});$auxOnly.PSObject.Properties.Remove('facets')
Check ((Match $auxOnly $intent).Decision-ceq'CONSERVATIVE') 'legacy-semantic-only-project-selector-is-unclassified'
$alias=Facets;$alias.workType.values=@('实现')
Check ((ConvertTo-AiwIntentFacets $alias $native).workType.values[0]-ceq'aiw:implementation') 'declared-localized-alias-normalizes'
$project=@([pscustomobject]@{dimension='domain';id='project:tactics';description='Explicit project domain';aliases=@('战术')},[pscustomobject]@{dimension='workType';id='project:manufacturing';description='Ambiguous alias deliberately declared';aliases=@('implementation')})
$extended=Get-AiwFacetVocabulary -NativeVocabulary $catalog.facetVocabulary -ProjectVocabulary $project
$alias=Facets;$alias.domain.values=@('战术')
Check ((ConvertTo-AiwIntentFacets $alias $extended).domain.values[0]-ceq'project:tactics') 'project-namespaced-vocabulary-extension'
$alias=Facets;$alias.workType.values=@('implementation')
Reject {ConvertTo-AiwIntentFacets $alias $extended} 'FACET_ALIAS_AMBIGUOUS' 'ambiguous-alias-not-first-match'
Check ((ConvertTo-AiwIntentFacets (Facets) $extended).workType.values[0]-ceq'aiw:implementation') 'canonical-native-id-retains-identity-under-alias-collision'
$override=Clone $project[0];$override.id='aiw:software'
Reject {Get-AiwFacetVocabulary -NativeVocabulary $catalog.facetVocabulary -ProjectVocabulary @($override)} 'FACET_VOCABULARY_NATIVE_OR_PROJECT_OVERRIDE' 'project-cannot-replace-native-token'
$bad=Facets;$bad.workType.values=@('unregistered:work')
Reject {ConvertTo-AiwIntentFacets $bad $native} 'FACET_TOKEN_UNDECLARED' 'undeclared-token-rejected'
$bad=Facets;$bad.workType.values=@('aiw:implementation','实现')
Reject {ConvertTo-AiwIntentFacets $bad $native} 'FACET_DUPLICATE_VALUE' 'duplicate-after-alias-normalization-rejected'
foreach($state in @('UNKNOWN','NOT_APPLICABLE')){$bad=Facets;$bad.stage.state=$state;Reject {ConvertTo-AiwIntentFacets $bad $native} 'FACET_STATE_VALUES_CONTRADICTION' ('nonempty-'+$state+'-rejected')}
$bad=Facets;$bad.stage.values=@();Reject {ConvertTo-AiwIntentFacets $bad $native} 'FACET_STATE_VALUES_CONTRADICTION' 'known-empty-rejected'
$bad=Facets;$bad.stage.state=@('KNOWN');Reject {ConvertTo-AiwIntentFacets $bad $native} 'FACET_STATE_OR_VALUES' 'state-must-be-scalar-string'
$bad=Facets;$bad|Add-Member futureAction ([pscustomobject]@{});Reject {ConvertTo-AiwIntentFacets $bad $native} 'OBJECT_FIELDS' 'extra-facet-dimension-rejected'
$bad=Facets;$bad.stage|Add-Member authority $true;Reject {ConvertTo-AiwIntentFacets $bad $native} 'OBJECT_FIELDS' 'facet-cannot-carry-authority'
Reject {Assert-AiwFacetSelector ([pscustomobject]@{stage=@()}) $native} 'FACET_SELECTOR_DIMENSION_OR_VALUES' 'empty-selector-array-not-unrestricted'
Reject {Assert-AiwFacetSelector ([pscustomobject]@{stage=@('implementation')}) $native} 'FACET_SELECTOR_VALUE' 'selector-requires-declared-id-not-alias'
$newToolchain=Get-Content -LiteralPath (Join-Path $versionRoot 'TOOLCHAIN.json') -Raw|ConvertFrom-Json -Depth 100
$newNav=Get-AiwNavigationContract $newToolchain
Check ($newNav.ContractVersion-ceq'4'-and$newNav.NavigationContractVersion-ceq'3'-and$newNav.Kind-ceq'PROJECT_BOOTSTRAP'-and$newNav.BootstrapLocator-ceq'.ai-workspace/BOOTSTRAP.md'-and$newNav.DiscoverSchema-eq5-and-not$newNav.SkillName) 'TC4-navigation3-direct-Bootstrap-input5'
foreach($contract in @('1','2','3')){
 $oldToolchain=Clone $newToolchain;$oldToolchain.PSObject.Properties.Remove('navigation');$oldToolchain.contractVersion=$contract
 $nav=if($contract-ceq'1'){'1'}else{'2'};$skill=if($nav-ceq'1'){'ai-workspace-router'}else{'ai-workspace-router-v2'}
 $oldToolchain|Add-Member routerCompatibility ([pscustomobject]@{schemaVersion=1;skillName=$skill;status='COMPATIBLE';canonicalSkillPath=('skills/'+$skill+'/SKILL.md');versionContractPath=('host/skills/'+$skill+'/SKILL.md');requiredOperations=@('LOAD_PLAN_RESOLVE','PROCESS_REQUIREMENTS_RESOLVE','WORKFLOW_ROUTE_RESOLVE');processCatalogSchemaVersion=$(if($contract-ceq'3'){3}else{2});processCatalogVersion=$(if($contract-ceq'3'){'4'}else{'3'});nativeRuleBodySource='MARKDOWN_EXACT_BLOCK';navigationContractVersion=$nav})
 $oldNav=Get-AiwNavigationContract $oldToolchain
 Check ($oldNav.SkillName-ceq$skill-and$oldNav.Kind-ceq'SKILL'-and$oldNav.DiscoverSchema-eq([int]$contract+1)) ('original-TC'+$contract+'-entry-and-input-preserved')
}
$wrong=Clone $newToolchain;$wrong.navigation.navigationContractVersion='2'
Reject {Get-AiwNavigationContract $wrong} 'FRAMEWORK_BOOTSTRAP_NAVIGATION_CONTRACT' 'unknown-navigation-pair-rejected-not-inferred-from-TC'
$wrong=Clone $newToolchain;$wrong|Add-Member routerCompatibility ([pscustomobject]@{})
Reject {Get-AiwNavigationContract $wrong} 'FRAMEWORK_TOOLCHAIN_FIELDS' 'mixed-Skill-and-Bootstrap-branches-rejected'
$wrong=Clone $newToolchain;$wrong.navigation|Add-Member skillName 'ai-workspace-router-v2'
Reject {Get-AiwNavigationContract $wrong} 'FRAMEWORK_BOOTSTRAP_NAVIGATION_FIELDS' 'new-entry-cannot-carry-hidden-Skill-dependency'
foreach($id in @('PR_TASK_LAUNCH_AND_ROUTE','PR_TASK_RESOURCE_SELECTION','PR_CODEX_RESOURCE_ROUTE')){
 $rule=@($catalog.requirements|Where-Object requirementId -CEQ $id)[0]
 $acceptance=ConvertTo-AiwIntentFacets (Facets 'aiw:acceptance' 'aiw:acceptance') $native
 Check (-not(Match $rule.selectors $review -Action REVIEW_EXECUTE -Profile CRITICAL -Role REVIEWER -Phase REVIEW).Match-and-not(Match $rule.selectors $acceptance -Action RESULT_ACCEPT -Profile CRITICAL -Role TASK_OWNER -Phase REVIEW).Match) ('pure-review-and-acceptance-omit-organization-'+$id)
 $organization=ConvertTo-AiwIntentFacets (Facets 'aiw:task-organization' 'aiw:planning') $native
 Check (Match $rule.selectors $organization -Action REVIEW_ROUTE -Profile CRITICAL -Role TASK_OWNER -Phase PLAN).Match ('actual-review-route-organization-retained-'+$id)
 $uncertain=Clone $review;$uncertain.workType=[pscustomobject]@{state='UNKNOWN';values=@()}
 Check ((Match $rule.selectors $uncertain -Action REVIEW_EXECUTE -Profile CRITICAL -Role REVIEWER -Phase REVIEW).Decision-ceq'CONSERVATIVE') ('unknown-organization-classification-conservative-'+$id)
}
# Consume the published classification example rather than duplicate its vocabulary.
$classification=[IO.File]::ReadAllText((Join-Path $versionRoot 'knowledge/cross-domain/ARTIFACT_CLASSIFICATION.md'))
$example=[regex]::Match($classification,'(?s)```json\s*(.*?)\s*```').Groups[1].Value|ConvertFrom-Json
$media=Get-AiwFacetVocabulary -NativeVocabulary $catalog.facetVocabulary -ProjectVocabulary @($example)
$spatial=Facets;$spatial.deliverableType.values=@('空间关系粗格');$spatial=ConvertTo-AiwIntentFacets $spatial $media
$shot=Facets;$shot.deliverableType.values=@('摄影分镜');$shot=ConvertTo-AiwIntentFacets $shot $media
$spatialRule=Selector ([pscustomobject]@{deliverableType=@('media:spatial-study')})
$shotRule=Selector ([pscustomobject]@{deliverableType=@('media:shot-design')})
Check ((Match $spatialRule $spatial -Paths @('assets/panel.png')).Match-and-not(Match $shotRule $spatial -Paths @('assets/panel.png')).Match-and(Match $shotRule $shot -Paths @('assets/panel.png')).Match-and-not(Match $spatialRule $shot -Paths @('assets/panel.png')).Match) 'same-PNG-distinct-use-selects-distinct-professional-requirement'
$representations=Facets;$representations.deliverableType.values=@('aiw:design');$representations=ConvertTo-AiwIntentFacets $representations $native
$designRule=Selector ([pscustomobject]@{deliverableType=@('aiw:design')})
foreach($path in @('docs/interface.md','docs/interface.pdf','docs/interface.json')){Check (Match $designRule $representations -Paths @($path)).Match ('same-information-different-representation-'+$path)}
$ambiguous=@(foreach($id in @('media:animation-pose','media:encoded-frame','media:generation-endpoint')){[pscustomobject]@{dimension='deliverableType';id=$id;description='Distinct keyframe use';aliases=@('关键帧')}})
$ambiguousVocabulary=Get-AiwFacetVocabulary -NativeVocabulary $catalog.facetVocabulary -ProjectVocabulary $ambiguous
$keyframe=Facets;$keyframe.deliverableType.values=@('关键帧')
Reject {ConvertTo-AiwIntentFacets $keyframe $ambiguousVocabulary} 'FACET_ALIAS_AMBIGUOUS' 'keyframe-three-uses-cannot-choose-first-alias'
$body=@($catalog.requirements|Where-Object requirementId -CEQ 'PR_TASK_SCOPE_AND_FORBIDDEN')[0].bodySelectors
& $composer {param($body,$vocabulary) Assert-AiwBodySelectorContract $body 'BODY_TEST' $vocabulary} $body $native
function BodyPlan([string]$Action='SOURCE_WRITE',[string]$Result='IMPLEMENTATION_RESULT',[string]$Context='TASK'){
 & $composer {param($catalog,$facets,$action,$result,$context)
  $custom=[pscustomobject]@{HasNormativeContent=$false}
  $plan=Get-AiwRuleSelectionPlan $catalog @() @() $custom 'body-fixture' STANDARD EXECUTOR IMPLEMENT $action $result @('src/current.js') @() '' $false $facets $context
  [pscustomobject]@{plan=$plan;obligations=@(Get-AiwSelectedObligations $catalog @() @() @() $custom 'body-fixture' $plan)}
 } $catalog $intent $Action $Result $Context
}
$production=BodyPlan
$finalId='framework:PR_FINAL_OUTPUT_CURRENT_RESULT';$deliveryId='framework:PR_COMPACT_NON_INTERRUPT_DELIVERY'
Check ($finalId-cin$production.plan.ruleIds-and$deliveryId-cin$production.plan.ruleIds-and$finalId-cnotin@($production.obligations.requirementId)-and$deliveryId-cnotin@($production.obligations.requirementId)) 'activity-bodies-retained-without-future-operation-obligations'
$terminalId='framework:PR_TASK_TERMINAL_DELIVERY'
Check ($terminalId-cin$production.plan.ruleIds-and$terminalId-cnotin@($production.obligations.requirementId)) 'task-activity-holds-complete-terminal-body-without-future-operation'
function NativePlan($Facts,[string]$Context,[string]$Action,[string]$Result){
 & $composer {param($catalog,$facts,$context,$action,$result)
  $custom=[pscustomobject]@{HasNormativeContent=$false}
  $plan=Get-AiwRuleSelectionPlan $catalog @() @() $custom 'native-consumer' STANDARD EXECUTOR EXTERNAL $action $result @('assets/visual.png') @() '' $false $facts $context
  [pscustomobject]@{plan=$plan;obligations=@(Get-AiwSelectedObligations $catalog @() @() @() $custom 'native-consumer' $plan)}
 } $catalog $Facts $Context $Action $Result
}
$visualFacts=Facets 'aiw:tool-operation';$visualFacts.domain.values=@('aiw:visual-art');$visualFacts.deliverableType.values=@('aiw:design');$visualFacts.stage=[pscustomobject]@{state='NOT_APPLICABLE';values=@()}
$visualFacts=ConvertTo-AiwIntentFacets $visualFacts $native
$visualPlan=NativePlan $visualFacts PROJECT_EXTERNAL EXTERNAL USER_RESPONSE
$taskOnly=@('PR_CODEX_SESSION_ORGANIZATION','PR_TASK_CLOSURE_AND_ARCHIVAL','PR_TASK_DESIGN_AND_SPECIFICATION','PR_TASK_PROBLEM_DRIVEN_IMPROVEMENT','PR_BOUNDED_TASK_ACTIONS','PR_TASK_TERMINAL_DELIVERY','PR_TASK_SCOPE_AND_FORBIDDEN','PR_DYNAMIC_ROLE_DIRECT_ISSUANCE','PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE','PR_TASK_COLLABORATION_BOUNDARY')
Check (@($taskOnly|Where-Object{('framework:'+$_)-cin$visualPlan.plan.ruleIds}).Count-eq0-and$finalId-cin$visualPlan.plan.ruleIds-and'framework:PR_ACTION_AUTHORIZATION_INDEPENDENT'-cin$visualPlan.plan.ruleIds-and'framework:PR_PROTECTED_PATH_FAIL_CLOSED'-cin$visualPlan.plan.ruleIds) 'ordinary-visual-tool-selects-complete-result-permission-protection-without-task-procedures'
Check ('framework:PR_ACTION_AUTHORIZATION_INDEPENDENT'-cnotin@($visualPlan.obligations.requirementId)-and'framework:PR_BOUNDED_TASK_ACTIONS'-cnotin@($visualPlan.obligations.requirementId)) 'direct-tool-permission-body-does-not-impose-per-action-package-gates'
$uncertainVisual=Clone $visualFacts;$uncertainVisual.workType=[pscustomobject]@{state='UNKNOWN';values=@()}
$unknownPlan=NativePlan $uncertainVisual PROJECT_EXTERNAL EXTERNAL USER_RESPONSE
Check ('framework:PR_CODEX_SESSION_ORGANIZATION'-cin$unknownPlan.plan.ruleIds-and'framework:PR_TASK_DESIGN_AND_SPECIFICATION'-cin$unknownPlan.plan.ruleIds) 'unknown-work-keeps-complete-relevant-conditions-within-known-boundaries'
$handoff=BodyPlan NONE HANDOFF
Check ($terminalId-cin@($handoff.obligations.requirementId)-and$finalId-cin@($handoff.obligations.requirementId)-and$deliveryId-cin@($handoff.obligations.requirementId)-and@($handoff.plan.ruleIds|Where-Object{$_-cnotin$production.plan.ruleIds}).Count-eq0) 'loaded-delivery-reenters-operation-without-new-body'
$readOnlyBody=& $composer {param($body,$facets)
 $selector=ConvertTo-AiwBodySelector $body
 Test-AiwRuleMatch $selector STANDARD EXECUTOR IMPLEMENT NONE PLAN @('src/current.js') @() '' $false $facets PROJECT_READ_ONLY
} $body $intent
Check (-not$readOnlyBody.Match) 'readonly-context-does-not-match-task-only-body-selector'
$unknownBody=BodyPlan SOURCE_WRITE IMPLEMENTATION_RESULT UNKNOWN
Check ($unknownBody.plan.matches[$finalId].Semantic-ceq'BODY_CONTEXT_UNKNOWN') 'unknown-private-context-retains-body-conservatively'
foreach($axis in @('phases','actionKinds','resultKinds','pathPrefixes','capabilities','semanticTerms')){
 $bad=Clone $body;$bad|Add-Member $axis @('*')
 Reject {& $composer {param($value)Assert-AiwBodySelectorContract $value 'BODY_TEST'} $bad} 'BODY_TEST' ('body-selector-rejects-operation-axis-'+$axis)
}
$scopedBody=Clone $body;$scopedBody.facets|Add-Member deliverableType @('aiw:code')
& $composer {param($value,$vocabulary)Assert-AiwBodySelectorContract $value 'BODY_TEST' $vocabulary} $scopedBody $native
$bodySelector=& $composer {param($value)ConvertTo-AiwBodySelector $value} $scopedBody
Check (Match $bodySelector $intent -Context TASK).Match 'body-selector-deliverable-axis-selects-current-code'
$otherDeliverable=Clone $intent;$otherDeliverable.deliverableType.values=@('aiw:plan')
Check (-not(Match $bodySelector $otherDeliverable -Context TASK).Match) 'body-selector-deliverable-mismatch-removes-body'
$bad=Clone $body;$bad.facets|Add-Member fileExtension @('json')
Reject {& $composer {param($value)Assert-AiwBodySelectorContract $value 'BODY_TEST'} $bad} 'BODY_TEST_FACET_DIMENSION' 'body-selector-still-rejects-undeclared-axis'
$bad=Clone $body;$bad.contextTypes=@('TASK','*')
Reject {& $composer {param($value)Assert-AiwBodySelectorContract $value 'BODY_TEST'} $bad} 'BODY_TEST_BOUNDARY' 'body-selector-wildcard-cannot-mix-contexts'
# The root consumers use the frozen old rows or explicit current O, including
# rows with no mechanical gates. Missing O never means an empty new format.
$operation=[pscustomobject]@{requirementId='project:fixture:EMPTY';preparationRequirements=@();resultRequirements=@()}
$bodyOnly=[pscustomobject]@{requirementId='project:fixture:BODY';preparationRequirements=@();resultRequirements=@()}
$prepared=[pscustomobject]@{schemaVersion=2;selectedRuleBlocks=@($operation,$bodyOnly);selectedObligations=@($operation)}
$read=@(Get-AiwPreparedRuleObligations $prepared)
Check ($read.Count-eq1-and$read[0].requirementId-ceq$operation.requirementId) 'prepared2-explicit-empty-gate-row-is-not-lost-or-expanded-to-B'
$bad=Clone $prepared;$bad.PSObject.Properties.Remove('selectedObligations')
Reject {Get-AiwPreparedRuleObligations $bad} 'FIXED_ADOPTION_PREPARATION' 'prepared2-missing-O-is-not-empty'
$bad=Clone $prepared;$bad.selectedRuleBlocks[1].resultRequirements=@('FUTURE_RESULT')
Reject {Get-AiwPreparedRuleObligations $bad} 'FIXED_ADOPTION_BODY_ONLY_OBLIGATIONS' 'prepared2-body-only-row-cannot-impose-current-gate'
$bad=Clone $prepared;$bad.selectedObligations[0].requirementId='project:fixture:MISSING'
Reject {Get-AiwPreparedRuleObligations $bad} 'FIXED_ADOPTION_OPERATION_SELECTION' 'prepared2-O-must-be-subset-of-B'
$legacy=[pscustomobject]@{schemaVersion=1;selectedRuleBlocks=@([pscustomobject]@{requirementId='project:fixture:OLD';preparationRequirements=@('ORIGINAL_P');resultRequirements=@('ORIGINAL_R')})}
$old=@(Get-AiwPreparedRuleObligations $legacy)
Check ($old.Count-eq1-and$old[0].preparationRequirements[0]-ceq'ORIGINAL_P'-and$old[0].resultRequirements[0]-ceq'ORIGINAL_R') 'prepared1-keeps-original-frozen-obligations'
# New classifications share the selector and do not create action authority.
$core=Facets;$core.PSObject.Properties.Remove('stage')
Reject {ConvertTo-AiwIntentFacets $core $native} 'OBJECT_FIELDS' 'Intent2-still-requires-legacy-stage'
$core3=ConvertTo-AiwIntentFacets $core $native -SchemaVersion 3
Check ($core3.stage.state-ceq'UNKNOWN'-and$core3.stage.values.Count-eq0) 'Intent3-omitted-stage-is-unknown'
Check ((Match $restriction $core3).Decision-ceq'CONSERVATIVE') 'legacy-stage-selector-remains-conservative-for-Intent3'
$explicit3=ConvertTo-AiwIntentFacets (Facets -Stage 'aiw:review') $native -SchemaVersion 3
Check (-not(Match $restriction $explicit3).Match) 'Intent3-explicit-legacy-stage-keeps-known-mismatch'
$bad=Clone $core;$bad.PSObject.Properties.Remove('workType')
Reject {ConvertTo-AiwIntentFacets $bad $native -SchemaVersion 3} 'OBJECT_FIELDS' 'Intent3-does-not-omit-core-workType'
$bad=Clone $core;$bad|Add-Member futureAction ([pscustomobject]@{})
Reject {ConvertTo-AiwIntentFacets $bad $native -SchemaVersion 3} 'OBJECT_FIELDS' 'Intent3-still-rejects-extra-dimension'
$bad=Clone $core;$bad.workType.values=@('aiw:implementation','实现')
Reject {ConvertTo-AiwIntentFacets $bad $native -SchemaVersion 3} 'FACET_DUPLICATE_VALUE' 'Intent3-still-rejects-canonical-alias-duplicate'
$envelope=[pscustomobject]@{schemaVersion=3;objective='Implement the bounded source change';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=$core}
$intentSchema=Join-Path $versionRoot 'INTENT_ENVELOPE_SCHEMA.json'
Check (Test-Json -Json ($envelope|ConvertTo-Json -Depth 20) -SchemaFile $intentSchema -ErrorAction SilentlyContinue) 'Intent3-schema-accepts-exact-three-core-input'
$envelope.schemaVersion=2
Check (-not(Test-Json -Json ($envelope|ConvertTo-Json -Depth 20) -SchemaFile $intentSchema -ErrorAction SilentlyContinue)) 'Intent2-schema-does-not-borrow-new-optional-stage'
$envelope.facets=Facets
Check (Test-Json -Json ($envelope|ConvertTo-Json -Depth 20) -SchemaFile $intentSchema -ErrorAction SilentlyContinue) 'Intent2-schema-retains-original-four-dimensions'
$contextSelector=Selector ([pscustomobject]@{});$contextSelector|Add-Member contextTypes @('PROJECT_WORK')
& $composer {param($value)Assert-AiwSelectorContract $value 'CONTEXT_TEST'} $contextSelector
foreach($ctx in @('TASK','PROJECT_READ_ONLY','PROJECT_EXTERNAL','PROJECT_WORK')){
 Check ((Match $contextSelector $core3 -Context $ctx).Match-eq($ctx-ceq'PROJECT_WORK')) ('ordinary-O-selector-filters-context-'+$ctx)
}
Check ((Match $contextSelector $core3).Decision-ceq'CONSERVATIVE') 'unknown-context-does-not-drop-context-only-rule'
foreach($contexts in @(@(),@('TASK','TASK'),@('TASK','*'),@('UNDECLARED'))){
 $bad=Clone $contextSelector;$bad.contextTypes=$contexts
 Reject {& $composer {param($value)Assert-AiwSelectorContract $value 'CONTEXT_TEST'} $bad} 'CONTEXT_TEST' ('context-selector-rejects-invalid-set-'+[string]::Join(',',@($contexts)))
}
$contextRule=[pscustomobject]@{ruleId='CONTEXT';selectors=$contextSelector;bodySelectors=[pscustomobject]@{profiles=@('*');roles=@('*');contextTypes=@('TASK');facets=[pscustomobject]@{deliverableType=@('aiw:code')}};preparationRequirements=@('CURRENT_CONTEXT_P');resultRequirements=@('CURRENT_CONTEXT_R');effectiveRule='Bounded context rule';requirementReason='Context selection';decisionLocator='fixture'}
$contextCatalog=[pscustomobject]@{requirements=@()};$emptyCustom=[pscustomobject]@{HasNormativeContent=$false}
foreach($ctx in @('TASK','PROJECT_READ_ONLY','PROJECT_EXTERNAL','PROJECT_WORK')){
 $selected=& $composer {param($cat,$rule,$custom,$facets,$ctx)
  $p=Get-AiwRuleSelectionPlan $cat @() @($rule) $custom 'fixture' STANDARD EXECUTOR IMPLEMENT SOURCE_WRITE IMPLEMENTATION_RESULT @('src/current.js') @() '' $false $facets $ctx
  [pscustomobject]@{body=$p.ruleIds;operation=@(Get-AiwSelectedObligations $cat @() @() @($rule) $custom 'fixture' $p)}
 } $contextCatalog $contextRule $emptyCustom $core3 $ctx
 Check (($selected.body.Count-gt0)-eq($ctx-cin@('TASK','PROJECT_WORK'))-and($selected.operation.Count-gt0)-eq($ctx-ceq'PROJECT_WORK')) ('same-selector-separates-O-and-body-only-B-'+$ctx)
}
$qualitySelector=Selector ([pscustomobject]@{});$qualitySelector|Add-Member contextTypes @('TASK')
$qualityPolicy=[pscustomobject]@{schemaVersion=3;qualityAssurance=[pscustomobject]@{schemaVersion=1;defaultStages=@()};rules=@([pscustomobject]@{selectors=$qualitySelector;qualityStages=@('SELF_CHECK')})}
Reject {& $composer {param($value)Assert-AiwQualityPolicy $value} $qualityPolicy} 'QUALITY_SELECTOR_UNSTABLE' 'operation-context-cannot-become-stable-quality-axis'
# Stable subject selection and its real current plan/package consumer. These
# anonymous units do not claim PROJECT_WORK admission or a predecessor bridge.
$stableSubject=[pscustomobject]@{repositoryId='REPO_LOCAL';exactPaths=@('src/current.js');facets=[pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=@('aiw:software')};workType=[pscustomobject]@{state='KNOWN';values=@('aiw:implementation')};deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:code')}}}
$stableSelector=[pscustomobject]@{profiles=@('STANDARD');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@('src');capabilities=@();semanticTerms=@();facets=[pscustomobject]@{workType=@('aiw:implementation')}}
$stableRule=[pscustomobject]@{ruleId='FORMAL_RESULT';requirementReason='A formal implementation requires review.';effectiveRule='Review the complete result.';decisionLocator='requirements.md';selectors=$stableSelector;preparationRequirements=@();resultRequirements=@();qualityStages=@('RESULT_REVIEW')}
$stablePolicy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='stable-subject';rules=@($stableRule);qualityAssurance=[pscustomobject]@{schemaVersion=2;defaultStages=@()};facetVocabulary=@([pscustomobject]@{dimension='workType';id='project:trial';description='A bounded trial.';aliases=@('trial')})}
$stablePolicyIdentity='1|'+('A'*64)
$formalSelection=Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $stableSubject
Check ($formalSelection.qualityBinding.schemaVersion-eq2-and($formalSelection.effectiveStages-join'|')-ceq'RESULT_REVIEW') 'QA2-selects-original-workType-with-full-stable-subject'
$trialSubject=Clone $stableSubject;$trialSubject.facets.workType.values=@('project:trial')
$trialSelection=Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $trialSubject
Check ($trialSelection.effectiveStages.Count-eq0-and(Get-AiwQualityBindingKey $trialSelection.qualityBinding)-cne(Get-AiwQualityBindingKey $formalSelection.qualityBinding)) 'same-path-and-result-kind-different-original-work-changes-QA2-key'
$mixedSubject=Clone $stableSubject;$mixedSubject.facets.workType.values=@('project:trial','aiw:implementation')
Check (((Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $mixedSubject).effectiveStages-join'|')-ceq'RESULT_REVIEW') 'multiple-original-workTypes-use-stage-union'
$aliasSubject=Clone $stableSubject;$aliasSubject.facets.workType.values=@('实现')
Check ((Get-AiwQualityBindingKey (Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $aliasSubject).qualityBinding)-ceq(Get-AiwQualityBindingKey $formalSelection.qualityBinding)) 'QA2-normalizes-declared-work-alias-before-freezing'
$wrong=Clone $stableSubject;$wrong.facets.PSObject.Properties.Remove('workType')
Reject {Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $wrong} 'QUALITY_FACETS_FIELDS' 'QA2-never-invents-missing-origin-workType'
$wrong=Clone $stableSubject;$wrong.facets.workType=[pscustomobject]@{state='UNKNOWN';values=@()}
Reject {Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $wrong} 'QUALITY_CLASSIFICATION_REQUIRED' 'unknown-origin-work-cannot-select-zero-quality'
$wrong=Clone $stableSubject;$wrong.facets.workType.values=@('project:unregistered')
Reject {Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $wrong} 'FACET_TOKEN_UNDECLARED' 'QA2-rejects-undeclared-origin-work'
$wrong=Clone $stableSubject;$wrong.facets.workType.values=@('aiw:implementation','实现')
Reject {Get-AiwQualitySelection $stablePolicy $stablePolicyIdentity STANDARD $wrong} 'FACET_DUPLICATE_VALUE' 'QA2-rejects-duplicate-after-origin-alias-normalization'
$defaultReview=Clone $stablePolicy;$defaultReview.qualityAssurance.defaultStages=@('RESULT_REVIEW');$defaultReview.rules[0].qualityStages=@('SELF_CHECK')
Check (((Get-AiwQualitySelection $defaultReview $stablePolicyIdentity STANDARD $stableSubject).effectiveStages-join'|')-ceq'SELF_CHECK|RESULT_REVIEW') 'narrow-work-rule-cannot-remove-default-review'
$legacySubject=Clone $stableSubject;$legacySubject.facets.PSObject.Properties.Remove('workType')
$qa1=Clone $stablePolicy;$qa1.qualityAssurance.schemaVersion=1;$qa1.rules=@()
$legacySelection=Get-AiwQualitySelection $qa1 $stablePolicyIdentity STANDARD $stableSubject
Check ($legacySelection.qualityBinding.schemaVersion-eq1-and$null-eq$legacySelection.qualityBinding.subject.facets.PSObject.Properties['workType']) 'QA1-projects-full-request-subject-to-original-two-dimensions'
$legacyKey='{"schemaVersion":1,"policyRef":{"path":".ai-workspace/process-policy.json","identity":"1|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"},"subject":{"repositoryId":"REPO_LOCAL","exactPaths":["src/current.js"],"facets":{"domain":{"state":"KNOWN","values":["aiw:software"]},"deliverableType":{"state":"KNOWN","values":["aiw:code"]}}},"effectiveStages":[]}'
Check ((Get-AiwQualityBindingKey $legacySelection.qualityBinding)-ceq$legacyKey) 'QA1-key-preserves-original-byte-contract'
$wrong=Clone $formalSelection.qualityBinding;$wrong.schemaVersion=1
Reject {Assert-AiwQualityBinding $wrong} 'QUALITY_FACETS_FIELDS' 'binding2-cannot-be-relabeled-binding1'
$wrong=Clone $stablePolicy;$wrong.qualityAssurance.schemaVersion=1
Reject {Assert-AiwQualityPolicy $wrong} 'QUALITY_SELECTOR_UNSTABLE' 'QA1-still-rejects-workType-selector'
$wrong=Clone $stablePolicy;$wrong.rules[0].selectors.facets|Add-Member stage @('aiw:review')
Reject {Assert-AiwQualityPolicy $wrong} 'QUALITY_SELECTOR_UNSTABLE' 'QA2-still-rejects-current-stage-selector'
$reordered=Clone $formalSelection.qualityBinding;$reordered.subject.facets=[pscustomobject][ordered]@{deliverableType=$reordered.subject.facets.deliverableType;workType=$reordered.subject.facets.workType;domain=$reordered.subject.facets.domain}
Check ((Get-AiwQualityBindingKey $reordered)-ceq(Get-AiwQualityBindingKey $formalSelection.qualityBinding)) 'QA2-key-has-fixed-three-dimension-order'
$cardPolicy=Clone $stablePolicy;$cardPolicy.PSObject.Properties.Remove('qualityAssurance');$cardPolicy.rules[0].PSObject.Properties.Remove('qualityStages')
Check ((Get-AiwTaskCardSelection $cardPolicy STANDARD $stableSubject).mode-ceq'LEGACY') 'absent-card-setting-retains-LEGACY'
$cardPolicy|Add-Member taskCards ([pscustomobject]@{schemaVersion=1;defaultMode='OMIT'})
$cardPolicy.rules[0]|Add-Member taskCardMode 'REQUIRED'
Check ((Get-AiwTaskCardSelection $cardPolicy STANDARD $stableSubject).mode-ceq'REQUIRED'-and(Get-AiwTaskCardSelection $cardPolicy STANDARD $trialSubject).mode-ceq'OMIT') 'card-override-uses-origin-work-and-default-for-nonmatch'
$conflicting=Clone $cardPolicy;$otherCardRule=Clone $conflicting.rules[0];$otherCardRule.ruleId='CONFLICT';$otherCardRule.taskCardMode='OMIT';$conflicting.rules+=@($otherCardRule)
Reject {Get-AiwTaskCardSelection $conflicting STANDARD $stableSubject} 'TASK_CARD_MODE_CONFLICT' 'matching-opposite-card-overrides-reject-order-independently'
$wrong=Clone $cardPolicy;$wrong.rules[0].selectors|Add-Member contextTypes @('PROJECT_EXTERNAL')
Reject {Get-AiwTaskCardSelection $wrong STANDARD $stableSubject} 'TASK_CARD_SELECTOR_UNSTABLE' 'current-context-cannot-lower-stable-card-choice'
$wrong=Clone $cardPolicy;$wrong.PSObject.Properties.Remove('taskCards')
Reject {Get-AiwTaskCardSelection $wrong STANDARD $stableSubject} 'TASK_CARD_MODE_ORPHAN' 'card-override-without-setting-is-not-implicit-OMIT'
$wrong=Clone $stableSubject;$wrong.facets.workType=[pscustomobject]@{state='UNKNOWN';values=@()}
Reject {Get-AiwTaskCardSelection $cardPolicy STANDARD $wrong} 'QUALITY_CLASSIFICATION_REQUIRED' 'card-policy-needs-complete-origin-subject'
$qaRoot=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-stable-subject-'+[guid]::NewGuid().ToString('N'))
try{
 $null=NewTestProject $qaRoot 'stable-subject';WriteText (Join-Path $qaRoot 'src/current.js') 'Actual isolated candidate.'
 $qaPolicyPath=Join-Path $qaRoot '.ai-workspace/process-policy.json';Store $qaPolicyPath $stablePolicy
 $schema=Join-Path $versionRoot 'PROCESS_POLICY_SCHEMA.json'
 Check (Test-Json -Json ($stablePolicy|ConvertTo-Json -Depth 100 -Compress) -SchemaFile $schema -ErrorAction Stop) 'policy-schema-accepts-QA2-stable-workType'
 $wrong=Clone $stablePolicy;$wrong.qualityAssurance.schemaVersion=1
 Check (-not(Test-Json -Json ($wrong|ConvertTo-Json -Depth 100 -Compress) -SchemaFile $schema -ErrorAction SilentlyContinue)) 'policy-schema-keeps-QA1-workType-prohibition'
 Check (Test-Json -Json ($cardPolicy|ConvertTo-Json -Depth 100 -Compress) -SchemaFile $schema -ErrorAction Stop) 'policy-schema-accepts-explicit-stable-card-setting'
 $wrong=Clone $cardPolicy;$wrong.rules[0].selectors.phases=@('REVIEW')
 Check (-not(Test-Json -Json ($wrong|ConvertTo-Json -Depth 100 -Compress) -SchemaFile $schema -ErrorAction SilentlyContinue)) 'policy-schema-rejects-current-phase-card-selector'
 Import-Module (Join-Path $versionRoot 'scripts/ResultEvidence.psm1')
 $ctx=New-AiwEvidenceContext $qaRoot '' $sourceRoot
 $binding=(Get-AiwQualitySelection $stablePolicy (Identity $qaPolicyPath) STANDARD $stableSubject).qualityBinding
 WriteText (Join-Path $qaRoot 'requirements.md') 'Review this whole original implementation.'
 $requirements=[pscustomobject]@{path='requirements.md';identity=(Identity (Join-Path $qaRoot 'requirements.md'))}
 $plan=[pscustomobject]@{schemaVersion=2;qualityBinding=$binding;stages=@([pscustomobject]@{id='review';kind='RESULT_REVIEW';requiredBy=$requirements;dependsOn=@();candidateRef=@();evidenceRefs=@()})}
 $parsedPlan=Get-AiwAcceptancePlan ('```aiw-acceptance-plan'+[char]10+($plan|ConvertTo-Json -Depth 100 -Compress)+[char]10+'```'+[char]10)
 Check (Test-Json -Json ($parsedPlan|ConvertTo-Json -Depth 100 -Compress) -SchemaFile (Join-Path $versionRoot 'ACCEPTANCE_PLAN_SCHEMA.json') -ErrorAction Stop) 'plan2-real-parser-and-schema-accept-binding2-with-required-stage'
 $package=[pscustomobject]@{schemaVersion=1;profile='STANDARD';actions=@('SOURCE_WRITE');exactPaths=@('src/current.js');qualityBinding=$binding}
 Check (((Get-AiwPackageQuality $ctx $package $parsedPlan).effectiveStages-join'|')-ceq'RESULT_REVIEW') 'current-package-quality-consumer-uses-real-QA2-policy-and-plan'
 $wrong=Clone $package;$wrong.qualityBinding.subject.facets.workType.values=@('project:trial')
 Reject {Get-AiwPackageQuality $ctx $wrong $parsedPlan} 'QUALITY_BINDING_DRIFT' 'current-package-cannot-change-origin-work-behind-frozen-plan'
 $oldPlan=Clone $parsedPlan;$oldPlan.qualityBinding=$legacySelection.qualityBinding
 Reject {Get-AiwPackageQuality $ctx $package $oldPlan} 'QUALITY_FACETS_FIELDS' 'current-QA2-cannot-downgrade-to-old-two-dimension-plan'
}finally{RemoveTestRoot $qaRoot}


# Direct compositor qualification with isolated prospective data. This does
# not stand in for Input6, admission, delivery, or PROJECT_WORK production.
$ruleReadTemp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-rule-read-'+[guid]::NewGuid().ToString('N'))
try{
 Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
 $ruleReadFramework=Join-Path $ruleReadTemp 'framework-root'
 $ruleReadVersion=New-AiwTestRuntimeFixture -SourceRoot $sourceRoot -DestinationRoot $ruleReadFramework -VersionPaths $facetsRuntimeVersionPaths
 Set-AiwTestFixtureQualification $ruleReadVersion -Candidate
 $ruleReadConfig=NewTestProject $ruleReadTemp 'rule-read-fixture'
 WriteText (Join-Path $ruleReadTemp '.ai-workspace/BOOTSTRAP.md') "<!-- FRAMEWORK-MANAGED:BEGIN -->`nFixture navigation`n<!-- FRAMEWORK-MANAGED:END -->`n<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->"
 $ruleReadPath=Join-Path $ruleReadTemp 'units.md'
 $ruleReadText="<C>`nCommon condition`n</C>`n<D>`nOrdered dependency`n</D>`n<A>`nSelected obligation`n</A>`n<Z>`nUnselected text`n</Z>"
 WriteText $ruleReadPath $ruleReadText
 $ruleReadConfig.sourceBindings=@([pscustomobject]@{id='units';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$ruleReadTemp};allowedPaths=@([pscustomobject]@{kind='FILE';locator='units.md'});decisionLocator='fixture:original-decision'})
 Store (Join-Path $ruleReadTemp '.ai-workspace/project.json') $ruleReadConfig
 function RuleReadNorm([hashtable]$Bodies=@{C='Common condition';D='Ordered dependency';A='Selected obligation'},[string[]]$Dependencies=@('D')){
  $docs=@();$ids=@{}
  foreach($id in @('C','D','A')){
   $conditions=@(if($id-ceq'A'){'C'});$deps=@(if($id-ceq'A'){$Dependencies})
   $unit=[ordered]@{provider='LOCAL_DIRECTORY';physicalSource=$ruleReadPath.ToUpperInvariant();permissionIdentity=(Get-AiwContentDescriptorIdentity $ruleReadConfig.sourceBindings[0]);mode='NORMATIVE_UNIT';unitId=$id;parserVersion='UTF8_LF_COMPLETE_UNIT_V1';sectionStart=('<'+$id+'>');sectionEnd=('</'+$id+'>');bodyIdentity=(Get-AiwContentByteIdentity $utf8.GetBytes($Bodies[$id]))}
   $identity=Get-AiwContentDescriptorIdentity ([ordered]@{unit=$unit;commonConditions=@($conditions|ForEach-Object{$ids[$_]});dependencies=@($deps|ForEach-Object{$ids[$_]})})
   $ids[$id]=$identity
   $docs+=[pscustomobject]@{sourceId=$id;bindingId='units';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value='1|'+('A'*64)};locator='units.md';mode='NORMATIVE_UNIT';unitId=$id;sectionStart=('<'+$id+'>');sectionEnd=('</'+$id+'>');normativeIdentity=$identity;commonConditionSourceIds=$conditions;dependencies=$deps}
  }
  $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='units';itemId='selected';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='A';documents=$docs}
  $descriptor.revision=Get-AiwContentRevision $descriptor $ruleReadConfig.sourceBindings
  foreach($doc in $docs){$doc.revision=Clone $descriptor.revision}
  $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
  return $descriptor
 }
 $ruleReadRule=[pscustomobject]@{ruleId='NORM';requirementReason='Complete selected units';selectors=(Selector ([pscustomobject]@{workType=@('aiw:implementation')}));preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:original-decision';source=(RuleReadNorm)}
 $ruleReadOther=[pscustomobject]@{ruleId='OTHER';requirementReason='Unselected declarations still validate';selectors=(Selector ([pscustomobject]@{workType=@('aiw:planning')}));preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:original-decision';effectiveRule='Unselected inline body'}
 $ruleReadPolicy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='rule-read-fixture';rules=@($ruleReadRule,$ruleReadOther)}
 function SaveRuleReadPolicy {Store (Join-Path $ruleReadTemp '.ai-workspace/process-policy.json') $ruleReadPolicy}
 SaveRuleReadPolicy
 $ruleReadIntent=Clone $envelope;$ruleReadIntent.schemaVersion=3;$ruleReadIntent.facets=Clone $core
 function RuleReadCompose($Observation=$null,[string]$Context='TASK',$CurrentIntent=$ruleReadIntent,[string]$Actor='reader-fixture',[string]$Role='EXECUTOR',[string]$Phase='IMPLEMENT',[string[]]$Paths=@('src/current.js'),[string[]]$Denied=@()){
  & $composer {param($p,$framework,$i,$o,$ctx,$actor,$role,$phase,$paths,$denied)
   $compositionArguments=@{ProjectRoot=$p;FrameworkRoot=$framework;TargetVersion='2.0.0';ExpectedProjectConfigIdentity=(Get-AiwFileIdentity (Join-Path $p '.ai-workspace/project.json'));ExpectedCorrectionsIdentity=(Get-AiwFileIdentity (Join-Path $p '.ai-workspace/corrections.json'));Profile='STANDARD';Role=$role;Phase=$phase;Actor=$actor;TaskIdentity='NOT_APPLICABLE';Capabilities=@();Objective='';ActionKind=$i.requestedActionKind;ResultKind=$i.requestedResultKind;ExactPaths=$paths;ForbiddenPaths=$denied;IntentEnvelope=$i;ObservedContextType=$ctx;EvaluationOnly=$true}
   if($null-ne$o){$compositionArguments.BindingSnapshotOnly=$true;$compositionArguments.IncludeOperationFacts=$true;$compositionArguments.RuleObservation=$o}
   Invoke-AiwProcessCompositionCore @compositionArguments
  } $ruleReadTemp $ruleReadFramework $CurrentIntent $Observation $Context $Actor $Role $Phase $Paths $Denied
 }
 & $composer {
  $script:ruleReadSavedAssembler=(Get-Command Convert-AiwBoundProjectSourceRule).ScriptBlock
  $script:ruleReadAssemblyCount=0
  Set-Item Function:script:Convert-AiwBoundProjectSourceRule {param($ProjectRoot,$Rule,$context,$snapshot,$unitGraph,$ReadTrace)
   $script:ruleReadAssemblyCount++
   & $script:ruleReadSavedAssembler $ProjectRoot $Rule $context $snapshot $unitGraph $ReadTrace
  }
 }
 try{
  $ruleReadFull=RuleReadCompose;$ruleReadObservation=Clone $ruleReadFull.sourceObservation
  $assemblerCount=& $composer {$script:ruleReadAssemblyCount}
  $normRead=@($ruleReadObservation.rules|Where-Object requirementId -CEQ 'project:rule-read-fixture:NORM')[0]
  Check ($ruleReadObservation.schemaVersion-eq3-and$ruleReadObservation.actor-ceq'reader-fixture'-and($normRead.units.sourceId-join',')-ceq'C,D,A'-and$assemblerCount-gt0) 'real-FULL-captures-complete-condition-dependency-units-after-actual-assembly'
  & $composer {$script:ruleReadAssemblyCount=0}
  $ruleReadFresh=RuleReadCompose $ruleReadObservation
  Check ((Get-AiwContentDescriptorIdentity $ruleReadFresh.selectedObligations)-ceq(Get-AiwContentDescriptorIdentity $ruleReadFull.selectedObligations)-and@($ruleReadFresh.selectedObligations|Where-Object requirementId -CEQ 'project:rule-read-fixture:NORM').Count-eq1) 'covered-current-O-preserves-empty-obligation-row'
  foreach($ctx in @('TASK','PROJECT_READ_ONLY','PROJECT_EXTERNAL','PROJECT_WORK')){
   $fresh=RuleReadCompose $ruleReadObservation -Context $ctx
   Check (@($fresh.readTrace|Where-Object event -CEQ 'RULE_READ_COVERAGE_VERIFIED').Count-eq1) ('private-same-selector-unit-coverage-'+$ctx)
  }
  $changedIntent=Clone $ruleReadIntent;$changedIntent.facets|Add-Member stage ([pscustomobject]@{state='KNOWN';values=@('aiw:review')})
  $fresh=RuleReadCompose $ruleReadObservation -CurrentIntent $changedIntent -Paths @('src/another.js','docs/result.md')
  Check ($fresh.requiredRuleReads.Count-gt0) 'legacy-stage-and-supporting-file-change-do-not-force-new-activity'
  $fresh=RuleReadCompose $ruleReadObservation -Role TASK_OWNER -Phase PLAN
  Check ($fresh.requiredRuleReads.Count-gt0) 'same-actor-role-phase-registration-is-not-itself-body-change'
  Store (Join-Path $ruleReadTemp '.ai-workspace/controller.json') ([pscustomobject]@{schemaVersion=1;projectId='rule-read-fixture';controllerId='fixture-controller';controllerEpoch=2;state='CURRENT'})
  $fresh=RuleReadCompose $ruleReadObservation
  Check ($fresh.bindings.controllerIdentity-cne$ruleReadObservation.bindings.controllerIdentity) 'current-controller-fact-reobserved-without-changing-rule-read'
  $ruleReadOther.effectiveRule='Changed unselected inline body';SaveRuleReadPolicy
  $fresh=RuleReadCompose $ruleReadObservation
  Check ($fresh.bindings.policyIdentity-cne$ruleReadObservation.bindings.policyIdentity) 'complete-current-policy-reparsed-unselected-body-does-not-invalidate-selected-units'
  WriteText $ruleReadPath ("Moved introduction`n"+$ruleReadText.Replace('Unselected text','Changed unselected text'))
  $fresh=RuleReadCompose $ruleReadObservation
  Check ((Get-AiwContentDescriptorIdentity @($fresh.requiredRuleReads|Where-Object requirementId -CEQ 'project:rule-read-fixture:NORM'))-ceq(Get-AiwContentDescriptorIdentity @($ruleReadObservation.rules|Where-Object requirementId -CEQ 'project:rule-read-fixture:NORM'))) 'fresh-real-physical-unrelated-edit-preserves-normative-unit-and-dependencies'
  WriteText $ruleReadPath ($ruleReadText.Replace('Selected obligation','Changed obligation'))
  Reject {RuleReadCompose $ruleReadObservation} 'CONTENT_IDENTITY_DRIFT|NORMATIVE_UNIT' 'stale-adoption-cannot-cover-changed-selected-body'
  $ruleReadRule.source=RuleReadNorm @{C='Common condition';D='Ordered dependency';A='Changed obligation'};SaveRuleReadPolicy
  Reject {RuleReadCompose $ruleReadObservation} 'RULE_LOAD_REQUIRED|UNIT_OR_DECLARATION_CHANGED' 'valid-readopted-selected-body-needs-FULL'
  WriteText $ruleReadPath ($ruleReadText.Replace('Common condition','Changed condition'))
  $ruleReadRule.source=RuleReadNorm @{C='Changed condition';D='Ordered dependency';A='Selected obligation'};SaveRuleReadPolicy
  Reject {RuleReadCompose $ruleReadObservation} 'RULE_LOAD_REQUIRED|UNIT_OR_DECLARATION_CHANGED' 'valid-readopted-common-condition-needs-FULL'
  WriteText $ruleReadPath $ruleReadText;$ruleReadRule.source=RuleReadNorm -Dependencies @('D','C');SaveRuleReadPolicy
  Reject {RuleReadCompose $ruleReadObservation} 'RULE_LOAD_REQUIRED|UNIT_OR_DECLARATION_CHANGED' 'changed-ordered-dependency-metadata-needs-FULL'
  $ruleReadRule.source=RuleReadNorm;SaveRuleReadPolicy
  $ruleReadOther.selectors.facets.workType=@('aiw:implementation');SaveRuleReadPolicy
  Reject {RuleReadCompose $ruleReadObservation} 'RULE_LOAD_REQUIRED|NEW_BODY' 'newly-required-valid-body-needs-FULL'
  $ruleReadOther.selectors.facets.workType=@('aiw:planning');SaveRuleReadPolicy
  $different=Clone $ruleReadIntent;$different.facets.workType.values=@('aiw:verification')
  Reject {RuleReadCompose $ruleReadObservation -CurrentIntent $different} 'RULE_LOAD_REQUIRED|ACTIVITY_CHANGED' 'actual-verification-activity-needs-FULL'
  Reject {RuleReadCompose $ruleReadObservation -Actor another-actor} 'RULE_LOAD_REQUIRED|ACTOR_CHANGED' 'changed-reader-needs-FULL'
  Reject {RuleReadCompose $ruleReadObservation -Denied @($ruleReadPath.Replace('\','/'))} 'FORBIDDEN' 'new-current-protection-rejects-before-unit-coverage'
  $ruleReadConfig.sourceBindings[0].allowedPaths=@([pscustomobject]@{kind='FILE';locator='other.md'});Store (Join-Path $ruleReadTemp '.ai-workspace/project.json') $ruleReadConfig
  Reject {RuleReadCompose $ruleReadObservation} 'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS' 'current-source-permission-withdrawal-is-not-RULE_LOAD-success'
  $ruleReadConfig.sourceBindings[0].allowedPaths=@([pscustomobject]@{kind='FILE';locator='units.md'});Store (Join-Path $ruleReadTemp '.ai-workspace/project.json') $ruleReadConfig
  $bad=Clone $ruleReadObservation;$bad|Add-Member trusted $true
  Reject {RuleReadCompose $bad} 'RULE_READ_FIELDS' 'rule-read-observation-rejects-trusted-extra-field'
  $assemblerCount=& $composer {$script:ruleReadAssemblyCount}
  Check ($assemblerCount-eq0) 'covered-and-refused-probes-never-call-project-body-assembler'
  # Whole-file and old observation branches keep their original strictness.
  $whole=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='units';itemId='whole';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='WHOLE';documents=@([pscustomobject]@{sourceId='WHOLE';bindingId='units';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value='1|'+('A'*64)};locator='units.md';mode='FULL_FILE';identity=(Identity $ruleReadPath);sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}
  $whole.revision=Get-AiwContentRevision $whole $ruleReadConfig.sourceBindings;$whole.documents[0].revision=Clone $whole.revision;$whole.itemIdentity=Get-AiwContentItemIdentity $whole
  $ruleReadRule.source=$whole;SaveRuleReadPolicy
  $wholeFull=RuleReadCompose
  WriteText $ruleReadPath ($ruleReadText.Replace('Unselected text','Whole-file change'))
  Reject {RuleReadCompose $wholeFull.sourceObservation} 'CONTENT_IDENTITY_DRIFT' 'FULL_FILE-still-rejects-unrelated-raw-change'
  WriteText $ruleReadPath $ruleReadText;$ruleReadRule.source=RuleReadNorm;SaveRuleReadPolicy
  $oldIntent=Clone $ruleReadIntent;$oldIntent.schemaVersion=2;$oldIntent.facets=Facets
  $oldFull=RuleReadCompose -CurrentIntent $oldIntent
  Check ($oldFull.sourceObservation.schemaVersion-eq1) 'Intent2-does-not-relabel-old-source-observation'
  WriteText $ruleReadPath ($ruleReadText.Replace('Unselected text','Old whole observation change'))
  Reject {RuleReadCompose $oldFull.sourceObservation -CurrentIntent $oldIntent} 'RULE_LOAD_REQUIRED|PROJECT_SOURCE_CHANGED' 'old-observation-retains-whole-physical-identity-boundary'
 }finally{
  & $composer {Set-Item Function:script:Convert-AiwBoundProjectSourceRule $script:ruleReadSavedAssembler;Remove-Variable -Scope Script -Name ruleReadSavedAssembler,ruleReadAssemblyCount}
 }
}finally{RemoveTestRoot $ruleReadTemp}


# Existing isolated runtime recipe; qualification, roles and host data are
# synthetic. Public constructors/checker, actual bytes and validators execute.
$operationTemp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-operation-'+[guid]::NewGuid().ToString('N'))
$operationOldActor=[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')
try{
 Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
 $operationFramework=Join-Path $operationTemp 'framework-root'
 $operationVersion=New-AiwTestRuntimeFixture -SourceRoot $sourceRoot -DestinationRoot $operationFramework -VersionPaths $facetsRuntimeVersionPaths
 $operationConfig=NewTestProject $operationTemp 'operation-fixture'
 WriteText (Join-Path $operationTemp '.ai-workspace/BOOTSTRAP.md') '<!-- FRAMEWORK-MANAGED:BEGIN -->
Fixture navigation
<!-- FRAMEWORK-MANAGED:END -->
<!-- PROJECT-CUSTOM:BEGIN -->
<!-- PROJECT-CUSTOM:END -->'
 Store (Join-Path $operationTemp '.ai-workspace/controller.json') ([pscustomobject]@{schemaVersion=1;projectId='operation-fixture';controllerId='controller-fixture';controllerEpoch=1;state='CURRENT'})
 $operationTaskPath=Join-Path $operationTemp '.ai-workspace/tasks/active/OPERATION-001.md'
 $operationTaskText='# OPERATION-001 — public operation fixture

- Owner: owner-fixture
- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT
- Range summary: profile=STANDARD; lifecycle=ACTIVE; risk=MEDIUM; size=SMALL; uncertainty=LOW
'
 WriteText $operationTaskPath $operationTaskText
 $operationRuntime=Join-Path $operationTemp '.ai-workspace/runtime/OPERATION-001/owner-fixture';$null=[IO.Directory]::CreateDirectory($operationRuntime)
 WriteText (Join-Path $operationTemp 'docs/rule.md') 'Complete common project rule.'
 WriteText (Join-Path $operationTemp 'docs/value.md') 'old value'
 $operationConfig.sourceBindings=@([pscustomobject]@{id='operation-rule';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$operationTemp};allowedPaths=@([pscustomobject]@{kind='FILE';locator='docs/rule.md'});decisionLocator='fixture:original-human'})
 Store (Join-Path $operationTemp '.ai-workspace/project.json') $operationConfig
 $operationSource=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='operation-rule';itemId='operation-rule';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='RULE';documents=@([pscustomobject]@{sourceId='RULE';bindingId='operation-rule';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value='1|'+('A'*64)};locator='docs/rule.md';mode='FULL_FILE';identity=(Identity (Join-Path $operationTemp 'docs/rule.md'));sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}
 $operationSource.revision=Get-AiwContentRevision $operationSource $operationConfig.sourceBindings;$operationSource.documents[0].revision=Clone $operationSource.revision;$operationSource.itemIdentity=Get-AiwContentItemIdentity $operationSource
 $operationPolicy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='operation-fixture';rules=@([pscustomobject]@{ruleId='RULE';requirementReason='Actual public operation rule';selectors=(Selector ([pscustomobject]@{}));preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:original-human';source=$operationSource})}
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $operationPolicy
 $operationPackage=[pscustomobject]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='OPERATION-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='public-operation';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Identity $operationTaskPath);projectConfigIdentity=(Identity (Join-Path $operationTemp '.ai-workspace/project.json'));actions=@('SOURCE_WRITE');exactPaths=@('docs/value.md');objectIdentities=@([pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')}
 $operationAuthPath=Join-Path $operationRuntime 'source-authorization.json';Store $operationAuthPath $operationPackage
 $operationIntent=Clone $envelope;$operationIntent.schemaVersion=3;$operationIntent.facets=Clone $core;$operationIntent.requestedActionKind='SOURCE_WRITE';$operationIntent.requestedResultKind='IMPLEMENTATION_RESULT'
 foreach($field in @('pathHints','semanticHints','capabilityHints','mutationHints','externalHints')){$operationIntent.$field=@()}
 $operationInput=[pscustomobject]@{schemaVersion=6;mode='DISCOVER';contextType='TASK';projectRoot=$operationTemp;frameworkRoot=$operationFramework;taskPath=$operationTaskPath;expectedProjectConfigIdentity=$operationPackage.projectConfigIdentity;expectedCorrectionsIdentity=(Identity (Join-Path $operationTemp '.ai-workspace/corrections.json'));expectedTaskIdentity=$operationPackage.taskIdentity;observedActor='owner-fixture';capabilities=@();exactPaths=@('docs/value.md');forbiddenPaths=@(($operationTemp.Replace('\','/')+'/must-not-read'));protectedPaths=@();authorizationRef=[pscustomobject]@{path=$operationAuthPath;identity=(Identity $operationAuthPath)};userDecision='NOT_REQUIRED';recoveryState='FULL_COLD';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=$operationIntent;evaluationOnly=$false;ruleLoad=[pscustomobject]@{mode='FULL'}}
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')
 $operationBoundary=Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementBoundary.psm1') -PassThru
 function OperationRun([string]$Name,$Value,[switch]$Compact){
  $p=Join-Path $operationRuntime ($Name+'.json');Store $p $Value
  $parameters=@{InputPath=$p;AsJson=$true}
  if($Compact){
   $request=if($null-ne$Value.PSObject.Properties['currentOperation']){$Value.currentOperation}else{$Value}
   $storage=$operationRuntime
   if($null-ne$request.PSObject.Properties['contextType']-and$request.contextType-cin@('PROJECT_READ_ONLY','PROJECT_EXTERNAL')){
    $locator=if($request.contextType-ceq'PROJECT_READ_ONLY'){$request.readOnlyContext.requestId}else{$request.requestContext.requestId}
    $storage=Join-Path $operationTemp ('.ai-workspace/runtime/'+$locator+'/owner-fixture');$null=[IO.Directory]::CreateDirectory($storage)
   }
   $parameters.CompactReceiptPath=Join-Path $storage ($Name+'-compact.json')
  }
  $call=& $operationBoundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] @parameters
  $v=($call.output-join[Environment]::NewLine)|ConvertFrom-Json -Depth 100
  Store (Join-Path $operationRuntime ($Name+'-result.json')) $v
  [pscustomobject]@{code=$call.exitCode;value=$v;inputPath=$p;resultPath=(Join-Path $operationRuntime ($Name+'-result.json'))}
 }
 function OperationPass($Run,[string]$Name){
  if($Run.code-ne0-or$Run.value.status-cne'PASS'){Write-Host ($Run.value|ConvertTo-Json -Depth 100 -Compress)}
  Check ($Run.code-eq0-and$Run.value.status-ceq'PASS') $Name | ForEach-Object {Write-Host $_}
 }
 $operationFull=OperationRun 'source-full' $operationInput -Compact
 OperationPass $operationFull 'public-Input6-real-FULL'
 Check ($operationFull.value.compactReceipt.schemaVersion-eq5-and$operationFull.value.compactReceipt.operation.binding.schemaVersion-eq4-and$operationFull.value.compactReceipt.ruleRead.schemaVersion-eq3) 'compact5-separates-full-rule-read-from-authority4-operation'
 $displayModule=Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementDisplay.psm1') -PassThru
 $operationDisplay=& $displayModule.ExportedCommands['Get-AiwProcessDisplay'] $operationFull.value
 Check ($operationDisplay.text.Contains('Complete common project rule.')-and$operationDisplay.text.EndsWith('AIW-END')) 'public-Input6-official-display-returns-complete-body'
 $operationCurrent=Clone $operationInput
 foreach($field in @('schemaVersion','mode','ruleLoad','evaluationOnly')){$operationCurrent.PSObject.Properties.Remove($field)}
 $operationCurrent.recoveryState='CURRENT';$operationCurrent|Add-Member ruleReadRef $operationFull.value.savedCompactReceipt
 $operationA=[pscustomobject]@{schemaVersion=4;mode='ADMIT_ACTION';currentOperation=$operationCurrent;preparationReceipts=@($operationFull.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 & $composer {
  $script:operationSavedPlan=(Get-Command Get-AiwRuleSelectionPlan).ScriptBlock
  $script:operationSavedAssembler=(Get-Command Convert-AiwBoundProjectSourceRule).ScriptBlock
  $script:operationSelectionCount=0;$script:operationAssemblyCount=0
  Set-Item Function:script:Get-AiwRuleSelectionPlan {param($Catalog,$Records,$PolicyRules,$Custom,$ProjectId,$Profile,$Role,$Phase,$ActionKind,$ResultKind,$Paths,$Capabilities,$Objective,$Unknown,$Facets,$ContextType='UNKNOWN')
   $script:operationSelectionCount++
   & $script:operationSavedPlan $Catalog $Records $PolicyRules $Custom $ProjectId $Profile $Role $Phase $ActionKind $ResultKind $Paths $Capabilities $Objective $Unknown $Facets $ContextType
  }
  Set-Item Function:script:Convert-AiwBoundProjectSourceRule {param($ProjectRoot,$Rule,$context,$snapshot,$unitGraph,$ReadTrace)
   $script:operationAssemblyCount++
   & $script:operationSavedAssembler $ProjectRoot $Rule $context $snapshot $unitGraph $ReadTrace
  }
 }
 try{
  $operationAdmit=OperationRun 'source-admit' $operationA -Compact
  OperationPass $operationAdmit 'public-currentOperation-runs-complete-checker-and-admits'
  $counts=& $composer {[pscustomobject]@{select=$script:operationSelectionCount;body=$script:operationAssemblyCount}}
  Check ($counts.select-eq1-and$counts.body-eq0-and$operationAdmit.value.ruleBodyLoaded-eq$false) 'currentOperation-selects-once-and-never-assembles-project-body'
  $savedOperation=Get-Content -LiteralPath $operationAdmit.value.operationRef.path -Raw|ConvertFrom-Json -Depth 100
  Check ($null-ne$savedOperation.PSObject.Properties['ruleReadRef']-and$null-eq$savedOperation.PSObject.Properties['ruleRead']-and$savedOperation.mode-ceq'ADMIT_ACTION'-and(Get-AiwContentDescriptorIdentity $savedOperation.ruleReadRef)-ceq(Get-AiwContentDescriptorIdentity $operationFull.value.savedCompactReceipt)) 'zero-body-operation-references-direct-FULL-with-actual-construction-entry'
  WriteText (Join-Path $operationTemp 'docs/value.md') 'actual admitted new value'
  $operationF=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$operationAdmit.value.operationRef;preparationReceipts=@($savedOperation.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($savedOperation.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|docs/value.md|'+(Identity (Join-Path $operationTemp 'docs/value.md')));deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  & $composer {$script:operationSelectionCount=0;$script:operationAssemblyCount=0}
  $operationFinal=OperationRun 'source-finalize' $operationF
  OperationPass $operationFinal 'public-operationRef-original-F-verifies-real-postimage'
  $counts=& $composer {[pscustomobject]@{select=$script:operationSelectionCount;body=$script:operationAssemblyCount}}
  Check ($counts.select-eq0-and$counts.body-eq0) 'original-F-consumes-frozen-O-with-zero-selector-and-body-assembly'
  $bad=Clone $operationF;$bad.resultReceipts=@($bad.resultReceipts|Where-Object{$_-cnotlike'OBJECT_POSTIMAGE|*'})
  $badRun=OperationRun 'missing-postimage' $bad
  Check ($badRun.code-ne0-and$badRun.value.reason.Contains('RESULT_POSTIMAGE_RECEIPT_REQUIRED')) 'new-F-still-rejects-missing-actual-postimage'
  $bad=Clone $operationA;$bad|Add-Member operationRef $operationAdmit.value.operationRef
  $badRun=OperationRun 'mixed-operation' $bad
  Check ($badRun.code-ne0-and$badRun.value.reason.Contains('OPERATION_BOUNDARY_ONE_OF')) 'new-boundary-rejects-current-and-frozen-operation-mix'
 }finally{
  & $composer {Set-Item Function:script:Get-AiwRuleSelectionPlan $script:operationSavedPlan;Set-Item Function:script:Convert-AiwBoundProjectSourceRule $script:operationSavedAssembler;Remove-Variable -Scope Script -Name operationSavedPlan,operationSavedAssembler,operationSelectionCount,operationAssemblyCount}
 }
 $noneInput=Clone $operationInput;$noneInput.authorizationRef='NOT_REQUIRED';$noneInput.intentEnvelope.requestedActionKind='NONE';$noneInput.intentEnvelope.requestedResultKind='HANDOFF'
 $noneFull=OperationRun 'none-full' $noneInput -Compact;OperationPass $noneFull 'public-NONE-real-FULL'
 $noneCurrent=Clone $noneInput;foreach($field in @('schemaVersion','mode','ruleLoad','evaluationOnly')){$noneCurrent.PSObject.Properties.Remove($field)}
 $noneCurrent.recoveryState='CURRENT';$noneCurrent|Add-Member ruleReadRef $noneFull.value.savedCompactReceipt
 $humanPath=Join-Path $operationRuntime 'synthetic-human.json';Store $humanPath ([pscustomobject]@{kind='SYNTHETIC_HUMAN_AUTHORIZATION_TEST_INPUT';request='Deliver this isolated fixture result to fixture-recipient.'})
 $nonePrepare=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';currentOperation=$noneCurrent;preparationReceipts=@($noneFull.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($noneFull.value.compactReceipt.operation.selectedObligations.resultRequirements|Where-Object{$_-cne'DELIVERY_RECEIPT'}|Sort-Object -Unique);deliveryReceipts=@();publicDecisionIdentity=(Identity $humanPath);protectionState='BOUND';evidenceRefs=@();deliveryContext=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='fixture-recipient';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';userDecisionRef=[pscustomobject]@{path=$humanPath;identity=(Identity $humanPath)}}}
 $nonePrepared=OperationRun 'none-prepare' $nonePrepare -Compact
 if($nonePrepared.value.status-cne'BLOCKED'){Write-Output ($nonePrepared.value|ConvertTo-Json -Depth 100 -Compress)}
 Check ($nonePrepared.code-eq3-and$nonePrepared.value.status-ceq'BLOCKED'-and$nonePrepared.value.delivery.status-ceq'READY_TO_SEND'-and$null-ne$nonePrepared.value.PSObject.Properties['operationRef']) 'NONE-PREPARE-freezes-operation-before-send'
 WriteText $operationTaskPath ($operationTaskText+[Environment]::NewLine+'Actual ordinary progress; owner, route, limits and consumer are unchanged.')
 $hostPath=Join-Path $operationRuntime 'synthetic-host-return.json';Store $hostPath ([pscustomobject]@{content=@([pscustomobject]@{type='text';text='{"threadId":"fixture-recipient"}'});isError=$false})
 $noneObserve=Clone $nonePrepare;$noneObserve.PSObject.Properties.Remove('currentOperation');$noneObserve|Add-Member operationRef $nonePrepared.value.operationRef
 $noneObserve|Add-Member preparedDeliveryRef ([pscustomobject]@{inputRef=[pscustomobject]@{path=$nonePrepared.inputPath;identity=(Identity $nonePrepared.inputPath)};resultRef=[pscustomobject]@{path=$nonePrepared.resultPath;identity=(Identity $nonePrepared.resultPath)}})
 $noneObserve.deliveryContext.stage='OBSERVE';$noneObserve.deliveryContext.observedRecipient='fixture-recipient';$noneObserve.deliveryContext.outcome='SUCCESS';$noneObserve.deliveryContext.evidence=$hostPath+'#'+(Identity $hostPath)
 $noneObserved=OperationRun 'none-observe' $noneObserve
 OperationPass $noneObserved 'ordinary-task-progress-preserves-original-NONE-delivery'
 Check ($noneObserved.value.delivery.status-ceq'DELIVERED') 'prepared-operation-observes-actual-synthetic-host-return'
 $bad=Clone $noneObserve;$bad.PSObject.Properties.Remove('preparedDeliveryRef');$badRun=OperationRun 'unprepared-observe' $bad
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PREPARED_DELIVERY_REF_BOUNDARY')) 'OBSERVE-requires-original-prepared-input-and-result'
 $bad=Clone $noneObserve;$bad.resultReceipts+=@('NEW_POST_SEND_EVIDENCE');$badRun=OperationRun 'changed-evidence' $bad
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PREPARED_DELIVERY_EVIDENCE_DRIFT')) 'OBSERVE-cannot-change-prepared-result-evidence'

 # Direct public delivery/history consumers must enforce the same original
 # preparation. They cannot rely on Boundary having run beforehand.
 $deliveryOwner=Import-Module (Join-Path $versionRoot 'scripts/WorkflowDelivery.psm1') -PassThru
 $noneRaw=Get-Content -LiteralPath $nonePrepared.value.operationRef.path -Raw|ConvertFrom-Json -Depth 100
 $direct=& $deliveryOwner.ExportedCommands['Get-AiwBoundDelivery'] $noneRaw $noneObserve
 Check ($direct.closureSatisfied-and$direct.delivery.delivered) 'shared-public-delivery-consumes-original-prepared-operation'
 $bad=Clone $noneObserve;$bad.PSObject.Properties.Remove('preparedDeliveryRef')
 Reject {& $deliveryOwner.ExportedCommands['Get-AiwBoundDelivery'] $noneRaw $bad} 'PREPARED_DELIVERY_REF_BOUNDARY' 'direct-delivery-cannot-bypass-original-preparation'
 $bad=Clone $noneObserve;$bad.resultReceipts+=@('POST_SEND_REPLACEMENT')
 Reject {& $deliveryOwner.ExportedCommands['Get-AiwBoundDelivery'] $noneRaw $bad} 'PREPARED_DELIVERY_EVIDENCE_DRIFT' 'direct-delivery-cannot-replace-original-evidence'
 $preparedResult=Get-Content -LiteralPath $nonePrepared.resultPath -Raw|ConvertFrom-Json -Depth 100
 $preparedResult.consumer.recipient='another-recipient'
 $alteredResult=Join-Path $operationRuntime 'altered-prepare-result.json';Store $alteredResult $preparedResult
 $bad=Clone $noneObserve;$bad.preparedDeliveryRef.resultRef=[pscustomobject]@{path=$alteredResult;identity=(Identity $alteredResult)}
 Reject {& $deliveryOwner.ExportedCommands['Get-AiwBoundDelivery'] $noneRaw $bad} 'PREPARED_DELIVERY_RESULT_DRIFT' 'original-prepare-result-must-match-current-frozen-consumer'
 $guarded=& $deliveryOwner {
  param($p,$framework)
  New-AiwEvidenceContext $p '' $framework @() @()
 } $operationTemp $operationFramework
 $retentionValues=@([pscustomobject]@{operationRef=$nonePrepared.value.operationRef;preparedDeliveryRef=$noneObserve.preparedDeliveryRef})
 $retained=& $deliveryOwner {param($p,$scope,$values,$ctx)Get-DeliveryRuntimeReferences $p $scope $values $ctx} $operationTemp $operationRuntime $retentionValues $guarded
 $requiredRetained=@($nonePrepared.value.operationRef.path,$noneFull.value.savedCompactReceipt.path,$nonePrepared.inputPath,$nonePrepared.resultPath,$noneFull.inputPath,$humanPath,$operationTaskPath)
 # Task/other-project objects are outside this exact runtime cleanup scope.
 Check (@($requiredRetained[0..5]|Where-Object{$_-cnotin$retained.retained}).Count-eq0) 'finite-retention-keeps-operation-direct-FULL-and-original-preparation-pair'
 Check ($operationTaskPath-cnotin$retained.retained) 'finite-retention-does-not-expand-cleanup-to-project-authority'
 $wrongFull=Clone $retentionValues[0];$wrongFull|Add-Member ruleReadRef $nonePrepared.value.operationRef
 Reject {& $deliveryOwner {param($p,$scope,$values,$ctx)Get-DeliveryRuntimeReferences $p $scope $values $ctx} $operationTemp $operationRuntime @($wrongFull) $guarded} 'RUNTIME_DIRECT_FULL_FORMAT' 'retention-ruleReadRef-cannot-point-to-another-operation'
 # Public no-task read-only HANDOFF uses no TASK placeholders or write grant.
 $ro=Clone $noneInput;$ro.contextType='PROJECT_READ_ONLY';$ro.PSObject.Properties.Remove('taskPath');$ro.PSObject.Properties.Remove('expectedTaskIdentity')
 $ro|Add-Member readOnlyContext ([pscustomobject]@{sessionId='owner-fixture';requestId='OPERATION-RO-001';role='EXECUTOR';phase='PLAN';profile='STANDARD'})
 $roFull=OperationRun 'readonly-full' $ro -Compact;OperationPass $roFull 'public-Input6-PROJECT_READ_ONLY-HANDOFF-FULL'
 Check ($roFull.value.compactReceipt.operation.binding.taskId-ceq'NOT_APPLICABLE'-and$roFull.value.compactReceipt.operation.binding.contextType-ceq'PROJECT_READ_ONLY') 'public-readonly-context-has-no-fake-task'
 $roCurrent=Clone $ro;foreach($field in @('schemaVersion','mode','ruleLoad','evaluationOnly')){$roCurrent.PSObject.Properties.Remove($field)}
 $roCurrent.recoveryState='CURRENT';$roCurrent|Add-Member ruleReadRef $roFull.value.savedCompactReceipt
 $roF=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';currentOperation=$roCurrent;preparationReceipts=@($roFull.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($roFull.value.compactReceipt.operation.selectedObligations.resultRequirements|Where-Object{$_-cne'DELIVERY_RECEIPT'}|Sort-Object -Unique);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@();deliveryContext=[pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}}
 $roReady=OperationRun 'readonly-prepare' $roF -Compact;OperationPass $roReady 'public-readonly-currentOperation-NONE-preparation'
 Check ($roReady.value.ruleBodyLoaded-eq$false-and$roReady.value.consumer.recipient-ceq'USER') 'readonly-preparation-keeps-real-consumer-and-zero-body'
 $bad=Clone $ro;$bad|Add-Member taskPath $operationTaskPath;$badRun=OperationRun 'readonly-task-mix' $bad
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('INPUT_FIELDS')) 'Input6-readonly-oneOf-rejects-task-placeholder'
 # Honest external rule loading remains direct: the current grant is read, but
 # neither a per-call action admission nor finalization is created.
 $externalPolicy=Clone $operationPolicy
 $externalPolicy.rules+=@([pscustomobject]@{ruleId='LOCAL_TOOL_GRANT';requirementReason='Bounded explicit fixture grant';effectiveRule='The fixture executor may call its local tool; no network, account change or publication.';selectors=[pscustomobject]@{profiles=@('*');roles=@('*');phases=@('EXTERNAL');actionKinds=@('EXTERNAL');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:original-explicit-human-grant'})
 $externalPolicy|Add-Member externalAuthorization ([pscustomobject]@{schemaVersion=1;mode='PROJECT_PREAUTHORIZED';grantRuleIds=@('LOCAL_TOOL_GRANT')})
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $externalPolicy
 $external=Clone $ro;$external.contextType='PROJECT_EXTERNAL';$external.PSObject.Properties.Remove('readOnlyContext')
 $external|Add-Member requestContext ([pscustomobject]@{sessionId='owner-fixture';requestId='OPERATION-EXTERNAL-001';role='EXECUTOR';phase='EXTERNAL';profile='STANDARD'})
 $external.intentEnvelope.requestedActionKind='EXTERNAL';$external.intentEnvelope.requestedResultKind='EXTERNAL_RESULT'
 $externalFull=OperationRun 'external-full' $external -Compact;OperationPass $externalFull 'public-Input6-PROJECT_EXTERNAL-FULL-reads-current-grant'
 Check ($externalFull.value.projectExternalAuthorization.selectedGrantRuleIds[0]-ceq'LOCAL_TOOL_GRANT'-and$externalFull.value.compactReceipt.operation.binding.authorizedActions.Count-eq0) 'external-FULL-does-not-create-per-call-action-authority'
 foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
  $forbiddenBoundary=[pscustomobject]@{schemaVersion=4;mode=$mode;operationRef=$externalFull.value.savedCompactReceipt;preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  $badRun=OperationRun ('external-no-'+$mode) $forbiddenBoundary
  Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PROJECT_EXTERNAL_LOAD_HAS_NO_ACTION_BOUNDARY')) ('external-load-is-not-per-call-'+$mode)
 }
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $operationPolicy


 # A real transient subprocess failure creates the original RETEST receipt.
 # No SOURCE write or new package intervenes before the same-activity retry.
 $retestPackage=Clone $operationPackage
 $retestPackage.taskIdentity=Identity $operationTaskPath
 $retestPackage.objectIdentities[0].identity=Identity (Join-Path $operationTemp 'docs/value.md')
 $retestPackage.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE')
 $retestPackage|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE')
 $retestPackage|Add-Member selfCheckRepairLimit 1
 $retestPackage|Add-Member repairReviewPlan ([pscustomobject]@{writer='owner-fixture';reviewer='independent-fixture';maxCycles=1;materialContributors=@()})
 $retestPackage.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
 $retestAuth=Join-Path $operationRuntime 'retest-authorization.json';Store $retestAuth $retestPackage
 $retestSourceInput=Clone $operationInput
 $retestSourceInput.expectedTaskIdentity=$retestPackage.taskIdentity
 $retestSourceInput.authorizationRef=[pscustomobject]@{path=$retestAuth;identity=(Identity $retestAuth)}
 function Admit-RetestOperation([string]$Name,$Request){
  $boundary=[pscustomobject]@{schemaVersion=4;mode='ADMIT_ACTION';currentOperation=$Request;preparationReceipts=@($retestFull.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  $admitted=OperationRun $Name $boundary -Compact
  if($admitted.code-ne0-or$admitted.value.status-cne'PASS'){[Console]::WriteLine(($admitted.value|ConvertTo-Json -Depth 100 -Compress));throw ('RETEST_ADMIT_FAILED|'+$Name)}
  $null=Check $true $Name;[Console]::WriteLine('PASS|'+$Name)
  $saved=Get-Content -LiteralPath $admitted.value.operationRef.path -Raw|ConvertFrom-Json -Depth 100
  return [pscustomobject]@{admitted=$admitted;saved=$saved}
 }
 function Finish-RetestOperation([string]$Name,$Step,$Evidence=@(),[string]$Disposition='ADVANCE'){
  $boundary=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$Step.admitted.value.operationRef;preparationReceipts=@($Step.saved.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($Step.saved.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|docs/value.md|'+(Identity (Join-Path $operationTemp 'docs/value.md')));deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($Evidence);continuationDisposition=$Disposition}
  $closed=OperationRun $Name $boundary
  if($closed.code-ne0-or$closed.value.status-cne'PASS'){[Console]::WriteLine(($closed.value|ConvertTo-Json -Depth 100 -Compress));throw ('RETEST_FINALIZE_FAILED|'+$Name)}
  $null=Check $true $Name;[Console]::WriteLine('PASS|'+$Name)
  if($null-ne$closed.value.PSObject.Properties['continuationReceipt']){
   $path=Join-Path $operationRuntime ($Name+'-continuation.json');Store $path $closed.value.continuationReceipt
   $closed|Add-Member continuationRef ([pscustomobject]@{path=$path;identity=(Identity $path)})
  }
  return $closed
 }
 $retestFull=OperationRun 'retest-source-full' $retestSourceInput -Compact;OperationPass $retestFull 'retest-source-full'
 $retestCurrent=Clone $retestSourceInput;foreach($field in @('schemaVersion','mode','ruleLoad','evaluationOnly')){$retestCurrent.PSObject.Properties.Remove($field)}
 $retestCurrent.recoveryState='CURRENT';$retestCurrent|Add-Member ruleReadRef $retestFull.value.savedCompactReceipt
 $retestSource=Admit-RetestOperation 'retest-source-admit' $retestCurrent
 $retestOriginalValue=[IO.File]::ReadAllBytes((Join-Path $operationTemp 'docs/value.md'))
 WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual bounded source write before the transient test.'
 $retestSourceFinal=Finish-RetestOperation 'retest-source-final' $retestSource
 Check ($retestSourceFinal.value.continuationReceipt.nextStepIndex-eq1-and$retestSourceFinal.value.continuationReceipt.selfRepairCycle-eq0) 'new-operation-source-F-emits-real-initial-continuation'
 $retestInput=Clone $retestSourceInput
 $retestInput.intentEnvelope.requestedActionKind='TEST_RUN';$retestInput.intentEnvelope.requestedResultKind='TEST_RESULT'
 $retestInput.intentEnvelope.facets.workType=[pscustomobject]@{state='KNOWN';values=@('aiw:verification')}
 $retestInput.intentEnvelope.facets.deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:test-result')}
 $retestInput|Add-Member continuationReceiptPath $retestSourceFinal.continuationRef.path
 $retestInput|Add-Member expectedContinuationReceiptIdentity $retestSourceFinal.continuationRef.identity
 $retestFull=OperationRun 'retest-verification-full' $retestInput -Compact;OperationPass $retestFull 'real-verification-switch-FULL-with-original-continuation'
 $retestCurrent=Clone $retestInput;foreach($field in @('schemaVersion','mode','ruleLoad','evaluationOnly')){$retestCurrent.PSObject.Properties.Remove($field)}
 $retestCurrent.recoveryState='CURRENT';$retestCurrent|Add-Member ruleReadRef $retestFull.value.savedCompactReceipt
 $retestFirst=Admit-RetestOperation 'retest-first-admit' $retestCurrent
 $retestRequirements=Join-Path $operationRuntime 'retest-requirements.md';WriteText $retestRequirements 'A single observed transient failure may retry the same candidate once. Preserve the actual failed command and original nonzero cycle. Qualification, roles and authorization decisions are synthetic fixture input.'
 $retestProbe=Join-Path $operationRuntime 'retest-probe.ps1'
 WriteText $retestProbe 'param([string]$Marker,[switch]$Fail)
if($Fail){Write-Output "actual permanent failure";exit 1}
if(-not[IO.File]::Exists($Marker)){[IO.File]::WriteAllText($Marker,"first observed");Write-Output "actual transient failure";exit 1}
Write-Output "actual transient recovery";exit 0'
 $retestMarker=Join-Path $operationRuntime 'retest-marker.txt'
 function Observe-RetestCommand([string]$Name,[switch]$Fail){
  $arguments=@('-NoProfile','-NonInteractive','-File',$retestProbe,'-Marker',$retestMarker)
  if($Fail){$arguments+=@('-Fail')}
  $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) $arguments -WorkingDirectory $operationTemp -GroupId 'public-operation-retest'
  $output=Join-Path $operationRuntime ($Name+'-stdout.raw');[IO.File]::Copy($native.Record.stdout.path,$output,$false)
  $command=Join-Path $operationRuntime ($Name+'-command.json')
  Store $command ([pscustomobject]@{command=([Environment]::ProcessPath+' '+($arguments-join' '));exitCode=$native.Code;output=[pscustomobject]@{path=$output;identity=(Identity $output)}})
  $outcome=if($native.Code-eq0){'PASS'}else{'FAIL'}
  $record=[pscustomobject]@{schemaVersion=1;taskId='OPERATION-001';actor='owner-fixture';candidateObjects=@([pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))});requirementsRef=[pscustomobject]@{path=$retestRequirements;identity=(Identity $retestRequirements)};outcome=$outcome;checks=@([pscustomobject]@{id=$Name;method='COMMAND';outcome=$outcome;reason='Actual isolated native process with original raw streams and exit; a one-shot marker justifies the transient retry.';evidenceLocators=@([pscustomobject]@{path=$command;identity=(Identity $command)})});evidenceLocators=@([pscustomobject]@{path=$output;identity=(Identity $output)})}
  $typed=Join-Path $operationRuntime ($Name+'-self.json');Store $typed $record
  Write-Output ('OBSERVE|'+$Name+'|nativeExit='+$native.Code+'|nativeRecord='+$native.ResultPath)
  return [pscustomobject]@{code=$native.Code;reference=[pscustomobject]@{kind='SELF_CHECK';path=$typed;identity=(Identity $typed)}}
 }
 # Capture diagnostic lines separately so they remain output, not helper data.
 $observed=@(Observe-RetestCommand 'retest-transient-failure');$observed[0..($observed.Count-2)]|Write-Output;$transient=$observed[-1]
 Check ($transient.code-eq1) 'RETEST-original-failure-is-an-actual-native-exit'
 $failedIdentity=$transient.reference.identity
 $retestBranch=Finish-RetestOperation 'retest-real-branch' $retestFirst @($transient.reference) RETEST
 Check ($retestBranch.value.actionOutcome-ceq'FAIL'-and$retestBranch.value.continuationReceipt.transitionKind-ceq'RETEST'-and$retestBranch.value.continuationReceipt.nextStepIndex-eq1-and$retestBranch.value.continuationReceipt.selfRepairCycle-eq1) 'actual-failure-F-produces-nonzero-RETEST-without-source-write'
 $retestCurrent.continuationReceiptPath=$retestBranch.continuationRef.path;$retestCurrent.expectedContinuationReceiptIdentity=$retestBranch.continuationRef.identity
 & $composer {
  $script:retestSavedSelector=(Get-Command Get-AiwRuleSelectionPlan).ScriptBlock;$script:retestSavedAssembler=(Get-Command Convert-AiwBoundProjectSourceRule).ScriptBlock
  $script:retestSelections=0;$script:retestAssemblies=0
  Set-Item Function:script:Get-AiwRuleSelectionPlan {param($Catalog,$Records,$PolicyRules,$Custom,$ProjectId,$Profile,$Role,$Phase,$ActionKind,$ResultKind,$Paths,$Capabilities,$Objective,$Unknown,$Facets,$ContextType='UNKNOWN')$script:retestSelections++;& $script:retestSavedSelector $Catalog $Records $PolicyRules $Custom $ProjectId $Profile $Role $Phase $ActionKind $ResultKind $Paths $Capabilities $Objective $Unknown $Facets $ContextType}
  Set-Item Function:script:Convert-AiwBoundProjectSourceRule {param($ProjectRoot,$Rule,$context,$snapshot,$unitGraph,$ReadTrace)$script:retestAssemblies++;& $script:retestSavedAssembler $ProjectRoot $Rule $context $snapshot $unitGraph $ReadTrace}
 }
 & $displayModule {$script:retestSavedDisplay=(Get-Command Get-AiwProcessDisplay).ScriptBlock;$script:retestDisplays=0;Set-Item Function:script:Get-AiwProcessDisplay {$script:retestDisplays++;& $script:retestSavedDisplay @args}}
 try{
  $retestAgain=Admit-RetestOperation 'retest-current-operation-admit' $retestCurrent
  $counts=& $composer {[pscustomobject]@{select=$script:retestSelections;body=$script:retestAssemblies}};$displays=& $displayModule {$script:retestDisplays}
  Check ($counts.select-eq1-and$counts.body-eq0-and$displays-eq0-and$retestAgain.admitted.value.ruleBodyLoaded-eq$false) 'same-verification-RETEST-selects-once-with-zero-assembler-and-renderer'
  Check ($retestAgain.saved.operation.binding.continuationStepIndex-eq1-and$retestAgain.saved.operation.binding.continuationReceiptIdentity-ceq$retestBranch.continuationRef.identity) 'current-operation-freezes-real-RETEST-predecessor-and-step'
 }finally{
  & $composer {Set-Item Function:script:Get-AiwRuleSelectionPlan $script:retestSavedSelector;Set-Item Function:script:Convert-AiwBoundProjectSourceRule $script:retestSavedAssembler;Remove-Variable -Scope Script -Name retestSavedSelector,retestSavedAssembler,retestSelections,retestAssemblies}
  & $displayModule {Set-Item Function:script:Get-AiwProcessDisplay $script:retestSavedDisplay;Remove-Variable -Scope Script -Name retestSavedDisplay,retestDisplays}
 }
 $bad=Clone $retestCurrent;$bad.PSObject.Properties.Remove('continuationReceiptPath');$bad.PSObject.Properties.Remove('expectedContinuationReceiptIdentity')
 $badBoundary=[pscustomobject]@{schemaVersion=4;mode='ADMIT_ACTION';currentOperation=$bad;preparationReceipts=@($retestFull.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 # Remove an unrelated initial-preimage mismatch for this counterexample;
 # restore the actual current candidate before any next genuine operation.
 $retestActualValue=[IO.File]::ReadAllBytes((Join-Path $operationTemp 'docs/value.md'))
 try{
  [IO.File]::WriteAllBytes((Join-Path $operationTemp 'docs/value.md'),$retestOriginalValue)
  $badRun=OperationRun 'retest-missing-continuation' $badBoundary -Compact
 }finally{[IO.File]::WriteAllBytes((Join-Path $operationTemp 'docs/value.md'),$retestActualValue)}
 Write-Output ('OBSERVE|missing-RETEST-predecessor|reason='+$badRun.value.reason)
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('CONTINUATION_ACTION_ORDER_DRIFT')) 'missing-RETEST-predecessor-cannot-silently-enter-step-zero'
 $forged=Clone $retestBranch.value.continuationReceipt;$forged.selfRepairCycle=0
 $forgedPath=Join-Path $operationRuntime 'retest-forged-zero.json';Store $forgedPath $forged
 $badBoundary.currentOperation=Clone $retestCurrent;$badBoundary.currentOperation.continuationReceiptPath=$forgedPath;$badBoundary.currentOperation.expectedContinuationReceiptIdentity=Identity $forgedPath
 $badRun=OperationRun 'retest-forged-cycle' $badBoundary -Compact
 Write-Output ('OBSERVE|forged-RETEST-cycle|reason='+$badRun.value.reason)
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('SELF_REPAIR_CYCLE')) 'rehashed-RETEST-cannot-reset-original-nonzero-cycle'
 $observed=@(Observe-RetestCommand 'retest-transient-recovery');$observed[0..($observed.Count-2)]|Write-Output;$recovered=$observed[-1]
 Check ($recovered.code-eq0) 'RETEST-same-candidate-actually-recovers-on-second-native-run'
 $retestPassed=Finish-RetestOperation 'retest-original-F-pass' $retestAgain @($recovered.reference)
 Check ($retestPassed.value.actionOutcome-ceq'PASS'-and$retestPassed.value.continuationReceipt.selfRepairCycle-eq1-and$retestPassed.value.continuationReceipt.nextAction-ceq'REVIEW_ROUTE'-and(Identity $transient.reference.path)-ceq$failedIdentity) 'RETEST-original-F-preserves-cycle-and-actual-failure'
 $observed=@(Observe-RetestCommand 'retest-still-failed' -Fail);$observed[0..($observed.Count-2)]|Write-Output;$stillFailed=$observed[-1]
 $exhausted=Finish-RetestOperation 'retest-original-limit-exhausted' $retestAgain @($stillFailed.reference) RETEST
 Check ($stillFailed.code-eq1-and$exhausted.value.actionOutcome-ceq'FAIL'-and$exhausted.value.successorState-ceq'REPAIR_LIMIT_EXHAUSTED'-and$null-eq$exhausted.value.PSObject.Properties['continuationReceipt']) 'RETEST-exhausted-original-budget-generates-no-successor'

 # Fresh PROJECT_WORK exercises the real public boundary and original typed
 # consumers. Only role, qualification, human-origin and host-return inputs are
 # synthetic; the write, native failures and original F records are actual.
 $workTaskPreimage=Identity $operationTaskPath
 $workPolicy=Clone $operationPolicy
 $workPolicy|Add-Member taskCards ([pscustomobject]@{schemaVersion=1;defaultMode='OMIT'})
 $workPolicy|Add-Member qualityAssurance ([pscustomobject]@{schemaVersion=2;defaultStages=@('SELF_CHECK','RESULT_REVIEW','RESULT_ACCEPT')})
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $workPolicy
 $workOriginal=Join-Path $operationRuntime 'work-original-human.txt'
 WriteText $workOriginal 'SYNTHETIC ORIGINAL HUMAN MATERIAL: owner-fixture owns this finite software result, may implement and run a bounded test, route an independent review to work-reviewer, receive its result and accept the exact candidate. This fixture does not authenticate real human or host authority.'
 $workRequirements=Join-Path $operationRuntime 'work-requirements.md'
 WriteText $workRequirements 'Preserve the original request and complete subject. One transient native failure may retry the same candidate once. Self, independent review and owner acceptance use actual original finalization pairs. Do not create or change a task card.'
 $workSubject=[pscustomobject]@{repositoryId='REPO_LOCAL';exactPaths=@('docs/value.md');facets=[pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=@('aiw:software')};workType=[pscustomobject]@{state='KNOWN';values=@('aiw:implementation')};deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:code')}}}
 $workQuality=Get-AiwQualitySelection $workPolicy (Identity (Join-Path $operationTemp '.ai-workspace/process-policy.json')) STANDARD $workSubject
 $workPlan=[pscustomobject]@{schemaVersion=2;qualityBinding=$workQuality.qualityBinding;stages=@()}
 $workPrevious=@()
 foreach($kind in $workQuality.effectiveStages){$id='work-'+$kind.ToLowerInvariant();$workPlan.stages+=@([pscustomobject]@{id=$id;kind=$kind;requiredBy=[pscustomobject]@{path=$workRequirements;identity=(Identity $workRequirements)};dependsOn=@($workPrevious);candidateRef=@();evidenceRefs=@()});$workPrevious+=@($id)}
 $workRequest=[pscustomobject]@{requestRef=[pscustomobject]@{kind='FILE';path=$workOriginal;identity=(Identity $workOriginal)};owner='owner-fixture';actor='owner-fixture';role='TASK_OWNER';phase='IMPLEMENT';profile='STANDARD';subject=$workSubject;requirementsRef=[pscustomobject]@{path=$workRequirements;identity=(Identity $workRequirements)};resultConsumer=[pscustomobject]@{channel='NATIVE_RESPONSE';recipient='USER'};acceptancePlan=$workPlan}
 $workLocator='request-'+(Get-AiwWorkRequestKey $workRequest).Split('|')[1].Substring(0,32)
 $workStore=Join-Path $operationTemp ('.ai-workspace/runtime/'+$workLocator+'/owner-fixture');$null=[IO.Directory]::CreateDirectory($workStore)
 function WorkRun([string]$Name,$Value,[switch]$Compact){
  $path=Join-Path $workStore ($Name+'.json');Store $path $Value
  $parameters=@{InputPath=$path;AsJson=$true}
  if($Compact){
   $request=if($null-ne$Value.PSObject.Properties['currentOperation']){$Value.currentOperation}else{$Value}
   $actorKey=Get-AiwRuntimeActorStorageKey $request.observedActor
   $storage=Join-Path $operationTemp ('.ai-workspace/runtime/'+$workLocator+'/'+$actorKey);$null=[IO.Directory]::CreateDirectory($storage)
   $parameters.CompactReceiptPath=Join-Path $storage ($Name+'-compact.json')
  }
  $call=& $operationBoundary.ExportedCommands['Invoke-AiwProcessRequirementBoundary'] @parameters
  $result=($call.output-join[Environment]::NewLine)|ConvertFrom-Json -Depth 100
  $resultPath=Join-Path $workStore ($Name+'-result.json');Store $resultPath $result
  if($call.exitCode-ne0){Write-Host ('OBSERVE|'+$Name+'|actual-boundary='+($result|ConvertTo-Json -Depth 100 -Compress))}
  [pscustomobject]@{code=$call.exitCode;value=$result;inputPath=$path;resultPath=$resultPath}
 }
 function WorkPackage([string]$Action,$Request){
  [pscustomobject]@{schemaVersion=5;frameworkVersion='2.0.0';requestContext=(Clone $Request);profile=$Request.profile;owner=$Request.owner;issuer=$Request.owner;issuerRole='TASK_OWNER';grantee=$Request.actor;repositoryId='REPO_LOCAL';bundle='fresh-work-'+$Action;decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;actions=@($Action);exactPaths=@('docs/value.md');objectIdentities=@([pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))});projectConfigIdentity=$operationPackage.projectConfigIdentity;qualityBinding=$workQuality.qualityBinding;invalidatesOn=@('REQUEST_CHANGE','SUBJECT_CHANGE','REQUIREMENTS_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','REPOSITORY_CHANGE')}
 }
 function WorkInput($Request,[string]$Action,[string]$Result,[string]$Work,$PackageRef,$Continuation=$null){
  $value=Clone $operationInput
  foreach($field in @('taskPath','expectedTaskIdentity')){$value.PSObject.Properties.Remove($field)}
  $value.contextType='PROJECT_WORK';$value.observedActor=$Request.actor;$value|Add-Member requestContext (Clone $Request)
  $value.authorizationRef=$PackageRef;$value.intentEnvelope.objective='Fresh finite WORK result with original sources, real native execution and original typed finalization; all fixture human/role/host facts are synthetic.'
  $value.intentEnvelope.requestedActionKind=$Action;$value.intentEnvelope.requestedResultKind=$Result
  $value.intentEnvelope.facets.workType.values=@($Work);$value.intentEnvelope.facets.PSObject.Properties.Remove('stage')
  if($null-ne$Continuation){$value|Add-Member continuationReceiptPath $Continuation.path;$value|Add-Member expectedContinuationReceiptIdentity $Continuation.identity}
  return $value
 }
 function WorkCurrent($Full){
  $value=Clone $Full.input
  foreach($field in @('schemaVersion','mode','ruleLoad','evaluationOnly')){$value.PSObject.Properties.Remove($field)}
  $value.recoveryState='CURRENT';$value|Add-Member ruleReadRef $Full.result.value.savedCompactReceipt
  return $value
 }
 function WorkDiscover([string]$Name,$WorkInputValue){
  [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID',$WorkInputValue.observedActor,'Process')
  $result=WorkRun $Name $WorkInputValue -Compact;OperationPass $result ($Name+'-actual-FULL')
  [pscustomobject]@{input=$WorkInputValue;result=$result}
 }
 function WorkAdmit([string]$Name,$Current,$Evidence=@(),$Delivery=$null,$ProductionFinalize=$null){
  $full=Get-Content -LiteralPath $Current.ruleReadRef.path -Raw|ConvertFrom-Json -Depth 100
  $boundary=[pscustomobject]@{schemaVersion=4;mode='ADMIT_ACTION';currentOperation=$Current;preparationReceipts=@($full.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($Evidence)}
  if($null-ne$Delivery){$boundary|Add-Member deliveryContext $Delivery}
  if($null-ne$ProductionFinalize){$boundary|Add-Member productionFinalizeRef $ProductionFinalize}
  $result=WorkRun $Name $boundary -Compact;OperationPass $result ($Name+'-real-checker-A')
  [pscustomobject]@{result=$result;saved=(Get-Content -LiteralPath $result.value.operationRef.path -Raw|ConvertFrom-Json -Depth 100)}
 }
 function WorkPair($Run){[pscustomobject]@{inputRef=[pscustomobject]@{path=$Run.inputPath;identity=(Identity $Run.inputPath)};resultRef=[pscustomobject]@{path=$Run.resultPath;identity=(Identity $Run.resultPath)}}}
 function WorkFinish([string]$Name,$Step,$Evidence=@(),[string]$Disposition='ADVANCE',$Delivery=$null,$ProductionFinalize=$null){
  $saved=$Step.saved
  $boundary=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$Step.result.value.operationRef;preparationReceipts=@($saved.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($saved.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|docs/value.md|'+(Identity (Join-Path $operationTemp 'docs/value.md')));deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($Evidence)}
  if($null-ne$saved.operation.binding.PSObject.Properties['continuationStepIndex']){$boundary|Add-Member continuationDisposition $Disposition}
  if($null-eq$Delivery){$Delivery=[pscustomobject]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}}
  $boundary|Add-Member deliveryContext $Delivery
  if($null-ne$ProductionFinalize){$boundary|Add-Member productionFinalizeRef $ProductionFinalize}
  $closed=WorkRun $Name $boundary

  if($Delivery.channel-ceq'TASK_MESSAGE'){
   Check ($closed.code-ne0-and$closed.value.status-ceq'BLOCKED'-and$closed.value.delivery.status-ceq'READY_TO_SEND') ($Name+'-original-prepared-pair') | ForEach-Object {Write-Host $_}
   $workHostEvidence=Join-Path $workStore ($Name+'-synthetic-host.json');Store $workHostEvidence ([pscustomobject]@{content=@([pscustomobject]@{type='text';text=([pscustomobject]@{threadId=$Delivery.expectedRecipient}|ConvertTo-Json -Compress)})})
   $observe=Clone $boundary;$observe.deliveryContext.stage='OBSERVE';$observe.deliveryContext.outcome='SUCCESS';$observe.deliveryContext.observedRecipient=$Delivery.expectedRecipient;$observe.deliveryContext.evidence=$workHostEvidence+'#'+(Identity $workHostEvidence);$observe|Add-Member preparedDeliveryRef (WorkPair $closed)
   $closed=WorkRun ($Name+'-observe') $observe
  }
  OperationPass $closed ($Name+'-original-F')
  $continuation=$null
  if($null-ne$closed.value.PSObject.Properties['continuationReceipt']){$path=Join-Path $workStore ($Name+'-continuation.json');Store $path $closed.value.continuationReceipt;$continuation=[pscustomobject]@{path=$path;identity=(Identity $path)}}
  [pscustomobject]@{run=$closed;continuation=$continuation;pair=(WorkPair $closed)}
 }
 function WorkRecord([string]$Name,$Request,[string]$Kind,[string]$Outcome,$Authorization=$null,$Command=$null){
  $check=if($null-ne$Command){[pscustomobject]@{id=$Name;method='COMMAND';outcome=$Outcome;reason='Actual isolated native command and original raw exit; human, roles and qualification are explicitly synthetic.';evidenceLocators=@($Command)}}else{[pscustomobject]@{id=$Name;method='MODEL_JUDGMENT';outcome='PASS';reason='Synthetic protocol judgment for the exact frozen candidate and original requirements; this does not assert natural independent semantic quality.';evidenceLocators=@($Request.requirementsRef)}}
  $record=[pscustomobject]@{schemaVersion=3;context=(Get-AiwWorkEvidenceBinding $Request);actor=$Request.actor;candidateObjects=@([pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))});requirementsRef=$Request.requirementsRef;outcome=$Outcome;checks=@($check);evidenceLocators=@($Request.requirementsRef)}
  if($null-ne$Authorization){$record|Add-Member authorizationRef $Authorization}
  if($Kind-ceq'REVIEW_VERDICT'){
   $producer=Get-Content -LiteralPath $Authorization.path -Raw|ConvertFrom-Json -Depth 100
   if($null-ne$producer.PSObject.Properties['repairReviewBinding']){
    $flat=[pscustomobject]@{context=(Get-AiwWorkEvidenceBinding $Request);owner=$Request.owner;reviewer=$Request.actor;writer='owner-fixture';cycle=$producer.repairReviewBinding.cycle;verdict=$Outcome;exactPaths=@('docs/value.md');objectIdentities=$record.candidateObjects;findingPaths=@(if($Outcome-ceq'CHANGES_REQUESTED'){'docs/value.md'});scopeChanged=$false;decisionChanged=$false}
    $flatPath=Join-Path $workStore ($Name+'-flat.json');Store $flatPath $flat;$record.evidenceLocators+=@([pscustomobject]@{path=$flatPath;identity=(Identity $flatPath)})
   }
  }

  $path=Join-Path $workStore ($Name+'-typed.json');Store $path $record
  [pscustomobject]@{path=$path;identity=(Identity $path);kind=$Kind}
 }

 # Cover the actual public preparation entry, rather than constructing only a
 # hand-authored plan. Its original output is the plan consumed by this same
 # existing write/test/review/accept chain; no second duplicate chain is added.
 function WorkCli([string]$Name,[string]$Entry,[string[]]$Arguments){
  $argv=@('-NoProfile','-NonInteractive','-File',$Entry)+$Arguments
  $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) $argv -WorkingDirectory $operationTemp -GroupId 'project-work-frontdoor'
  Write-Host ('OBSERVE|'+$Name+'|nativeExit='+$native.Code+'|nativeRecord='+$native.ResultPath)
  [pscustomobject]@{code=$native.Code;text=([IO.File]::ReadAllText($native.Record.stdout.path));native=$native}
 }

 function WorkRepairFactory([string]$Name,$Binding,$CurrentAuthorization=$null){
  $path=Join-Path $workStore ($Name+'-factory.json')
  $factoryInput=[pscustomobject]@{operation='REPAIR_REVIEW';repositoryRoot=$operationTemp;binding=$Binding}
  if($null-ne$CurrentAuthorization){$factoryInput|Add-Member currentAuthorizationRef $CurrentAuthorization}
  Store $path $factoryInput
  $native=WorkCli $Name (Join-Path $operationVersion 'scripts/resolve-workflow-route.ps1') @('-InputPath',$path,'-AsJson')
  if($native.code-ne0){Write-Host $native.text}
  Check ($native.code-eq0) ($Name+'-actual-public-factory-native-zero')|ForEach-Object{Write-Host $_}
  $result=$native.text|ConvertFrom-Json -Depth 100
  Check ($result.status-ceq'PREPARED'-and$result.package.schemaVersion-eq5-and$result.authorityGranted-eq$false) ($Name+'-derived-work-package-no-authority')|ForEach-Object{Write-Host $_}
  return $result.package
 }
 $workPreparePath=Join-Path $workStore 'work-quality-prepare.json'
 $workPrepare=[pscustomobject]@{operation='QUALITY_PLAN_PREPARE';schemaVersion=2;projectRoot=$operationTemp;projectConfigRef=[pscustomobject]@{path=(Join-Path $operationTemp '.ai-workspace/project.json');identity=(Identity (Join-Path $operationTemp '.ai-workspace/project.json'))};policyRef=[pscustomobject]@{path=(Join-Path $operationTemp '.ai-workspace/process-policy.json');identity=(Identity (Join-Path $operationTemp '.ai-workspace/process-policy.json'))};requestContext=(Clone $workRequest)}
 Store $workPreparePath $workPrepare
 $workPreparedNative=WorkCli 'WORK-quality-prepare' (Join-Path $operationVersion 'scripts/resolve-workflow-route.ps1') @('-InputPath',$workPreparePath,'-AsJson')
 Check ($workPreparedNative.code-eq0) ('WORK-public-quality-prepare-native-zero|'+$workPreparedNative.text)
 $workPrepared=$workPreparedNative.text|ConvertFrom-Json -Depth 100
 Check ($workPrepared.status-ceq'READY'-and$workPrepared.authorityGranted-eq$false-and$workPrepared.plan.schemaVersion-eq2-and($workPrepared.effectiveStages-join'|')-ceq'SELF_CHECK|RESULT_REVIEW|RESULT_ACCEPT') 'WORK-quality-prepare-selects-real-three-stage-inline-plan-without-authority'
 Check ((Get-AiwQualityBindingKey $workPrepared.plan.qualityBinding)-ceq(Get-AiwQualityBindingKey $workQuality.qualityBinding)-and@($workPrepared.plan.stages|Where-Object{$_.requiredBy.identity-cne$workRequest.requirementsRef.identity-or$_.candidateRef.Count-or$_.evidenceRefs.Count}).Count-eq0) 'WORK-quality-prepare-keeps-complete-stable-subject-and-pending-candidates'
 $workPlan=Clone $workPrepared.plan;$workRequest.acceptancePlan=Clone $workPlan
 $workPrepareIdentity=Identity $workPreparePath
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','different-fixture-host','Process')
 try{$workWrongHost=WorkCli 'WORK-quality-wrong-host' (Join-Path $operationVersion 'scripts/resolve-workflow-route.ps1') @('-InputPath',$workPreparePath,'-AsJson')}finally{[Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')}
 Check ($workWrongHost.code-ne0-and$workWrongHost.text.Contains('QUALITY_WORK_ACTOR')-and(Identity $workPreparePath)-ceq$workPrepareIdentity) 'WORK-quality-prepare-rejects-actual-host-mismatch-with-input-unchanged'
 Check ((Identity $operationTaskPath)-ceq$workTaskPreimage-and@(Get-ChildItem -LiteralPath (Split-Path -Parent $operationTaskPath) -File).Count-eq1) 'WORK-quality-prepare-does-not-create-update-or-infer-task'
 $workReviewerActor='01a00000-0000-7000-8000-000000000123'
 $workPackage=WorkPackage SOURCE_WRITE $workRequest
 $workPackage.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$workPackage|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$workPackage|Add-Member selfCheckRepairLimit 1;$workPackage.invalidatesOn+=@('CONTINUATION_RESULT_DRIFT')
 $workPackage|Add-Member repairReviewPlan ([pscustomobject]@{writer='owner-fixture';reviewer='DEFERRED_VISIBLE_REVIEWER';maxCycles=2;materialContributors=@()})
 $workPackagePath=Join-Path $workStore 'work-write-test-package.json';Store $workPackagePath $workPackage
 $workPackageRef=[pscustomobject]@{path=$workPackagePath;identity=(Identity $workPackagePath)}
 $workFull=WorkDiscover 'work-source-full' (WorkInput $workRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $workPackageRef)
 $workSource=WorkAdmit 'work-source-admit' (WorkCurrent $workFull)
 Check ($workSource.saved.operation.binding.contextType-ceq'PROJECT_WORK'-and$workSource.saved.operation.binding.taskId-ceq'NOT_APPLICABLE'-and$workSource.saved.operation.binding.context.requestContext.owner-ceq'owner-fixture') 'WORK-authority-keeps-original-request-without-real-or-fake-task'
 WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual fresh WORK admitted source postimage.'
 $workWritten=WorkFinish 'work-source-finalize' $workSource
 Check ($workWritten.run.value.continuationReceipt.schemaVersion-eq4-and$null-eq$workWritten.run.value.continuationReceipt.PSObject.Properties['taskId']) 'WORK-original-F-produces-explicit-request-continuation4'
 $workCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
 $workVerification=Clone $workRequest;$workVerification.phase='VERIFY';$workVerification.acceptancePlan.stages[0].candidateRef=@($workCandidate)
 $workTestFull=WorkDiscover 'work-verification-full' (WorkInput $workVerification TEST_RUN TEST_RESULT aiw:verification $workPackageRef $workWritten.continuation)
 $workTestCurrent=WorkCurrent $workTestFull
 $workTest=WorkAdmit 'work-test-first' $workTestCurrent
 $workProbe=Join-Path $workStore 'work-probe.ps1';WriteText $workProbe 'param([string]$Marker);if(-not[IO.File]::Exists($Marker)){[IO.File]::WriteAllText($Marker,"observed");Write-Output "real WORK failure";exit 1};Write-Output "real WORK recovery";exit 0'
 $workMarker=Join-Path $workStore 'work-once.txt'
 function WorkNative([string]$Name){
  $argv=@('-NoProfile','-NonInteractive','-File',$workProbe,'-Marker',$workMarker)
  $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) $argv -WorkingDirectory $operationTemp -GroupId 'project-work-retest'
  $output=Join-Path $workStore ($Name+'-stdout.raw');[IO.File]::Copy($native.Record.stdout.path,$output,$false)
  $command=Join-Path $workStore ($Name+'-command.json');Store $command ([pscustomobject]@{command=([Environment]::ProcessPath+' '+($argv-join' '));exitCode=$native.Code;output=[pscustomobject]@{path=$output;identity=(Identity $output)}})
  Write-Output ('OBSERVE|'+$Name+'|nativeExit='+$native.Code+'|nativeRecord='+$native.ResultPath)
  [pscustomobject]@{code=$native.Code;command=[pscustomobject]@{path=$command;identity=(Identity $command)}}
 }
 $observed=@(WorkNative 'work-native-failure');$observed[0..($observed.Count-2)]|Write-Output;$workFailure=$observed[-1]
 Check ($workFailure.code-eq1) 'WORK-test-real-native-failure-preserved'
 $workFailed=WorkRecord 'work-failed' $workVerification SELF_CHECK FAIL -Command $workFailure.command
 $workRetry=WorkFinish 'work-test-failed-F' $workTest @($workFailed) RETEST
 Check ($workRetry.run.value.actionOutcome-ceq'FAIL'-and$workRetry.run.value.continuationReceipt.selfRepairCycle-eq1) 'WORK-failure-original-F-keeps-real-cycle-one'
 $workTestCurrent.continuationReceiptPath=$workRetry.continuation.path;$workTestCurrent.expectedContinuationReceiptIdentity=$workRetry.continuation.identity
 $workAgain=WorkAdmit 'work-test-retry' $workTestCurrent
 Check ($workAgain.saved.operation.binding.continuationStepIndex-eq1-and$workAgain.result.value.ruleBodyLoaded-eq$false) 'WORK-RETEST-same-verification-consumes-real-step-without-reload'
 $observed=@(WorkNative 'work-native-recovery');$observed[0..($observed.Count-2)]|Write-Output;$workRecovery=$observed[-1]
 Check ($workRecovery.code-eq0) 'WORK-test-real-native-recovery'
 $workSelf=WorkRecord 'work-self' $workVerification SELF_CHECK PASS -Command $workRecovery.command
 $workTestPassed=WorkFinish 'work-test-passed-F' $workAgain @($workSelf)
 Check ($workTestPassed.run.value.actionOutcome-ceq'PASS'-and$workTestPassed.run.value.continuationReceipt.selfRepairCycle-eq1) 'WORK-successful-original-F-does-not-reset-used-budget'

 $workReviewRequest=Clone $workVerification;$workReviewRequest.actor=$workReviewerActor;$workReviewRequest.role='REVIEWER';$workReviewRequest.phase='REVIEW';$workReviewRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient='owner-fixture'}
 $workReviewRequest.acceptancePlan.stages[0].evidenceRefs=@($workSelf);$workReviewRequest.acceptancePlan.stages[0]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($workTestPassed.pair)})
 $workReviewRequest.acceptancePlan.stages[1].candidateRef=@($workCandidate)
 $workReview=WorkPackage REVIEW_EXECUTE $workReviewRequest;$workReview.reviewIndependence='INDEPENDENT';$workReview|Add-Member candidateWriter 'owner-fixture';$workReview|Add-Member materialContributors @();$workReview.invalidatesOn+=@('CONTRIBUTOR_SET_CHANGE')


 $workInitialBinding=[pscustomobject]@{parentPackagePath=$workPackageRef.path;parentPackageIdentity=$workPackageRef.identity;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=$workTestPassed.pair.inputRef.path;repairFinalizeInputIdentity=$workTestPassed.pair.inputRef.identity;repairFinalizeResultPath=$workTestPassed.pair.resultRef.path;repairFinalizeResultIdentity=$workTestPassed.pair.resultRef.identity}
 $workInitialBinding|Add-Member reviewerAssignment ([pscustomobject]@{source='HOST_INITIAL_DELEGATION';createdBy='owner-fixture';threadId='UNBOUND_RECEIVER';hostId='SYNTHETIC_HOST';context=(Get-AiwWorkEvidenceBinding $workRequest);parentPackageIdentity=$workPackageRef.identity})
 $workReview=WorkRepairFactory 'work-initial-review' $workInitialBinding
 Check ($workReview.grantee-ceq'UNBOUND_RECEIVER'-and$workReview.requestContext.actor-ceq'UNBOUND_RECEIVER'-and$workReview.repairReviewBinding.reviewerAssignment.threadId-ceq'UNBOUND_RECEIVER') 'WORK-deferred-public-factory-keeps-initial-template-non-executable'
 $workReview.requestContext=Clone $workReviewRequest
 $workPendingTemplate=Clone $workReview;$workPendingTemplate.grantee='UNBOUND_RECEIVER';$workPendingTemplate.requestContext.actor='UNBOUND_RECEIVER'
 $workPendingPath=Join-Path $workStore 'work-review-pending.json'
 Store $workPendingPath ([pscustomobject]@{schemaVersion=1;delegationId='work-review-fixture-001';receiverRole='REVIEWER';authorizationTemplate=$workPendingTemplate})
 $workPendingIdentity=Identity $workPendingPath;$workRequestKeyBefore=Get-AiwWorkRequestKey $workReviewRequest
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID',$workReviewerActor,'Process')
 try{$workBoundNative=WorkCli 'WORK-receiver-bind' (Join-Path $operationVersion 'scripts/bind-receiver-authorization.ps1') @('-ControlRoot',$operationTemp,'-PendingPath',$workPendingPath,'-ExpectedPendingIdentity',$workPendingIdentity,'-ReceivedDelegationId','work-review-fixture-001')}finally{[Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')}
 Check ($workBoundNative.code-eq0) ('WORK-receiver-real-native-zero|'+$workBoundNative.text)
 $workBoundMatch=[regex]::Match($workBoundNative.text.Trim(),'^PASS[|]package=(?<path>.+)[|]identity=(?<identity>[0-9]+[|][A-F0-9]{64})$')
 Check $workBoundMatch.Success 'WORK-receiver-returns-original-derived-package-reference'
 $workReviewPath=$workBoundMatch.Groups['path'].Value;$workReviewRef=[pscustomobject]@{path=$workReviewPath;identity=$workBoundMatch.Groups['identity'].Value}
 Check ((Identity $workReviewPath)-ceq$workReviewRef.identity-and(Identity $workPendingPath)-ceq$workPendingIdentity) 'WORK-receiver-pending-original-stays-byte-identical'
 $workReview=Get-Content -LiteralPath $workReviewPath -Raw|ConvertFrom-Json -Depth 100
 $workDerived=Clone $workReview;$workDerived.PSObject.Properties.Remove('receiverBinding');$workDerived.grantee='UNBOUND_RECEIVER';$workDerived.requestContext.actor='UNBOUND_RECEIVER';$workDerived.repairReviewBinding.reviewerAssignment.threadId='UNBOUND_RECEIVER'
 Check ($workReview.grantee-ceq$workReviewerActor-and$workReview.requestContext.actor-ceq$workReviewerActor-and$workReview.receiverBinding.hostActor-ceq$workReviewerActor-and$workReview.owner-ceq'owner-fixture'-and(Get-AiwWorkRequestKey $workReview.requestContext)-ceq$workRequestKeyBefore-and(Get-AiwContentDescriptorIdentity $workDerived)-ceq(Get-AiwContentDescriptorIdentity $workPendingTemplate)) 'WORK-receiver-only-binds-host-actor-grantee-preserves-owner-key-scope-plan-and-original-permission'

 $workInitialBinding.reviewerAssignment.threadId=$workReviewerActor
 Check ($workReview.repairReviewBinding.reviewerAssignment.threadId-ceq$workReviewerActor) 'WORK-deferred-receiver-binds-only-original-assigned-reviewer'
 $workRouteRequest=Clone $workReviewRequest;$workRouteRequest.actor='owner-fixture';$workRouteRequest.role='TASK_OWNER';$workRouteRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient=$workReviewerActor}
 $workRouteFull=WorkDiscover 'work-route-full' (WorkInput $workRouteRequest REVIEW_ROUTE HANDOFF aiw:review $workPackageRef $workTestPassed.continuation)
 $workRouteDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient=$workReviewerActor;observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=$workReviewRef}
 # The host creation declaration is explicitly synthetic protocol input.
 $workRouteDelivery|Add-Member reviewerAssignment ([pscustomobject]@{source='HOST_CREATE_THREAD_RESULT';createdBy='owner-fixture';threadId=$workReviewerActor;hostId='SYNTHETIC_HOST';context=(Get-AiwWorkEvidenceBinding $workRequest);parentPackageIdentity=$workPackageRef.identity})
 $workRoute=WorkAdmit 'work-route-admit' (WorkCurrent $workRouteFull) @($workSelf) $workRouteDelivery
 $workRouted=WorkFinish 'work-route-F' $workRoute @($workSelf) -Delivery $workRouteDelivery
 Check ($workRouted.run.value.delivery.delivered) 'WORK-real-review-route-original-prepared-pair-and-synthetic-host-observed'
 $workReviewFull=WorkDiscover 'work-review-full' (WorkInput $workReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review $workReviewRef)
 # A receiver-derived package must first reject any deviation from its frozen template.
 $bad=Clone $workReview;$bad.repairReviewBinding.reviewerAssignment.context.owner='other-fixture';$badPath=Join-Path $workStore 'work-review-receiver-assignment-drift-package.json';Store $badPath $bad
 $badRun=WorkRun 'work-review-receiver-assignment-drift' (WorkInput $workReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)})) -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('RECEIVER_AUTHORITY_EXPANDED')) 'WORK-deferred-receiver-still-rejects-assignment-template-drift'
 # Use the separate, supported bound HOST_CREATE branch to reach assignment validation itself.
 # Its host return and authority are explicitly synthetic, as in the main delivery fixture.
 $workAssignedReview=Clone $workReview;$workAssignedReview.PSObject.Properties.Remove('receiverBinding');$workAssignedReview.repairReviewBinding.reviewerAssignment.source='HOST_CREATE_THREAD_RESULT'
 $workAssignedPath=Join-Path $workStore 'work-review-host-assignment-package.json';Store $workAssignedPath $workAssignedReview
 $workAssignedRun=WorkRun 'work-review-host-assignment' (WorkInput $workReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review ([pscustomobject]@{path=$workAssignedPath;identity=(Identity $workAssignedPath)})) -Compact
 Check ($workAssignedRun.code-eq0-and$workAssignedRun.value.status-ceq'PASS') 'WORK-deferred-bound-host-assignment-positive-control-passes-public-checker'
 $bad=Clone $workAssignedReview;$bad.repairReviewBinding.reviewerAssignment.context.owner='other-fixture';$badPath=Join-Path $workStore 'work-review-assignment-wrong-context.json';Store $badPath $bad
 $badRun=WorkRun 'work-review-assignment-context' (WorkInput $workReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)})) -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('REVIEWER_ASSIGNMENT_BINDING')) 'WORK-deferred-assignment-cannot-change-original-request-context'
 $bad=Clone $workAssignedReview;$bad.repairReviewBinding.reviewerAssignment|Add-Member taskId 'OPERATION-001';$badPath=Join-Path $workStore 'work-review-assignment-mixed-task.json';Store $badPath $bad
 $badRun=WorkRun 'work-review-assignment-mixed' (WorkInput $workReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)})) -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('REPAIR_REVIEW_FIELDS')) 'WORK-deferred-assignment-cannot-mix-legacy-task-id'
 $workReviewAction=WorkAdmit 'work-review-admit' (WorkCurrent $workReviewFull)
 $workVerdict=WorkRecord 'work-review-verdict' $workReviewRequest REVIEW_VERDICT CHANGES_REQUESTED $workReviewRef
 $workReviewDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='owner-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
 $workReviewed=WorkFinish 'work-review-F' $workReviewAction @($workVerdict) -Delivery $workReviewDelivery
 Check ($workReviewed.run.value.consumer.recipient-ceq'owner-fixture'-and$workReviewed.run.value.delivery.delivered) 'WORK-independent-review-typed3-original-F-returns-to-real-owner'

 # Extend this same original WORK chain through an actual finding and repair.
 # SELF already used cycle1; a new review repair must not reset it to zero.
 $findingRecord=Get-Content -LiteralPath $workVerdict.path -Raw|ConvertFrom-Json -Depth 100
 $findingFlat=@($findingRecord.evidenceLocators|Where-Object{$_.path.EndsWith('-flat.json')})[0]
 $workRepairBinding=Clone $workInitialBinding;$workRepairBinding.phase='REPAIR';$workRepairBinding.cycle=1;$workRepairBinding.verdictPath=$findingFlat.path;$workRepairBinding.verdictIdentity=$findingFlat.identity
 foreach($name in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){$workRepairBinding.$name='NOT_APPLICABLE'}
 $workRepairBinding|Add-Member verdictFinalizeInputPath $workReviewed.pair.inputRef.path;$workRepairBinding|Add-Member verdictFinalizeInputIdentity $workReviewed.pair.inputRef.identity
 $workRepairBinding|Add-Member verdictFinalizeResultPath $workReviewed.pair.resultRef.path;$workRepairBinding|Add-Member verdictFinalizeResultIdentity $workReviewed.pair.resultRef.identity
 # The fixture now acts as the repair writer; the prior review actor remains distinct.
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')
 $workRepairPackage=WorkRepairFactory 'work-review-repair' $workRepairBinding
 Check ($workRepairPackage.grantee-ceq'owner-fixture'-and$workRepairPackage.selfCheckRepairLimit-eq1-and$workRepairPackage.repairReviewBinding.cycle-eq1) 'WORK-review-repair-preserves-original-writer-parent-and-granted-limits'
 $workRepairRequest=Clone $workRepairPackage.requestContext
 $bad=Clone $workRepairPackage;$bad.selfCheckRepairLimit=2;$badPath=Join-Path $workStore 'work-review-repair-bad-limit.json';Store $badPath $bad
 $badRun=WorkRun 'work-review-repair-changed-limit' (WorkInput $workRepairRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)})) -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('REPAIR_REVIEW_SELF_LIMIT_DRIFT')) 'WORK-review-repair-cannot-regrant-self-budget'

 $bad=Clone $workRepairPackage;$bad.requestContext.acceptancePlan.stages[1].dependsOn=@();$badPath=Join-Path $workStore 'work-review-repair-bad-plan.json';Store $badPath $bad
 $badRun=WorkRun 'work-review-repair-changed-plan' (WorkInput $bad.requestContext SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)})) -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('REPAIR_REVIEW_PARENT_PLAN_DRIFT')) 'WORK-review-repair-cannot-replace-original-stage-dependencies'
 $workRepairPath=Join-Path $workStore 'work-review-repair-package.json';Store $workRepairPath $workRepairPackage;$workRepairRef=[pscustomobject]@{path=$workRepairPath;identity=(Identity $workRepairPath)}
 $workRepairFull=WorkDiscover 'work-review-repair-source-full' (WorkInput $workRepairRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $workRepairRef)
 $workRepairSource=WorkAdmit 'work-review-repair-source-admit' (WorkCurrent $workRepairFull)
 WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual WORK review-finding repair; original self cycle remains1.'
 $workRepairWritten=WorkFinish 'work-review-repair-source-F' $workRepairSource
 Check ($workRepairWritten.run.value.continuationReceipt.selfRepairCycle-eq1) 'WORK-review-repair-original-source-F-retains-used-self-cycle-one'
 $workCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
 $workVerification=Clone $workRepairRequest;$workVerification.phase='VERIFY';$workVerification.acceptancePlan.stages[0].candidateRef=@($workCandidate)
 $repairTestFull=WorkDiscover 'work-review-repair-test-full' (WorkInput $workVerification TEST_RUN TEST_RESULT aiw:verification $workRepairRef $workRepairWritten.continuation)
 $repairTest=WorkAdmit 'work-review-repair-test-admit' (WorkCurrent $repairTestFull)
 $observed=@(WorkNative 'work-review-repair-native-zero');$observed[0..($observed.Count-2)]|Write-Output;$repairNative=$observed[-1]
 Check ($repairNative.code-eq0) 'WORK-review-repair-test-is-an-actual-native-zero'
 $workSelf=WorkRecord 'work-review-repair-self' $workVerification SELF_CHECK PASS -Command $repairNative.command
 $workTestPassed=WorkFinish 'work-review-repair-test-F' $repairTest @($workSelf)
 Check ($workTestPassed.run.value.continuationReceipt.selfRepairCycle-eq1) 'WORK-review-repair-test-success-keeps-self-cycle-one'
 $rereviewBinding=Clone $workRepairBinding;$rereviewBinding.phase='REREVIEW'
 $rereviewBinding.repairFinalizeInputPath=$workTestPassed.pair.inputRef.path;$rereviewBinding.repairFinalizeInputIdentity=$workTestPassed.pair.inputRef.identity
 $rereviewBinding.repairFinalizeResultPath=$workTestPassed.pair.resultRef.path;$rereviewBinding.repairFinalizeResultIdentity=$workTestPassed.pair.resultRef.identity
 $workReview=WorkRepairFactory 'work-rereview' $rereviewBinding
 $workReviewRequest=Clone $workVerification;$workReviewRequest.actor=$workReviewerActor;$workReviewRequest.role='REVIEWER';$workReviewRequest.phase='REVIEW';$workReviewRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient='owner-fixture'}
 $workReviewRequest.acceptancePlan.stages[0].evidenceRefs=@($workSelf);$workReviewRequest.acceptancePlan.stages[0]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($workTestPassed.pair)})
 $workReviewRequest.acceptancePlan.stages[1].candidateRef=@($workCandidate);$workReview.requestContext=Clone $workReviewRequest
 $workReviewPath=Join-Path $workStore 'work-rereview-package.json';Store $workReviewPath $workReview;$workReviewRef=[pscustomobject]@{path=$workReviewPath;identity=(Identity $workReviewPath)}
 $reRouteRequest=Clone $workReviewRequest;$reRouteRequest.actor='owner-fixture';$reRouteRequest.role='TASK_OWNER';$reRouteRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient=$workReviewerActor}
 $reRouteFull=WorkDiscover 'work-rereview-route-full' (WorkInput $reRouteRequest REVIEW_ROUTE HANDOFF aiw:review $workRepairRef $workTestPassed.continuation)
 $reRouteDelivery=Clone $workRouteDelivery;$reRouteDelivery.reviewPackageRef=$workReviewRef;$reRouteDelivery.PSObject.Properties.Remove('reviewerAssignment')
 $reRoute=WorkAdmit 'work-rereview-route-admit' (WorkCurrent $reRouteFull) @($workSelf) $reRouteDelivery
 $reRouted=WorkFinish 'work-rereview-route-F' $reRoute @($workSelf) -Delivery $reRouteDelivery
 Check ($reRouted.run.value.delivery.delivered) 'WORK-review-repair-rereview-route-uses-original-prepared-pair'
 $workReviewFull=WorkDiscover 'work-rereview-full' (WorkInput $workReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review $workReviewRef)
 $workReviewAction=WorkAdmit 'work-rereview-admit' (WorkCurrent $workReviewFull)
 $workVerdict=WorkRecord 'work-rereview-verdict' $workReviewRequest REVIEW_VERDICT APPROVED $workReviewRef
 $workReviewed=WorkFinish 'work-rereview-F' $workReviewAction @($workVerdict) -Delivery $workReviewDelivery
 Check ($workReviewed.run.value.delivery.delivered-and$workReview.repairReviewBinding.cycle-eq1) 'WORK-original-rereview-APPROVED-preserves-root-review-cycle-one'
 $workAcceptRequest=Clone $workReviewRequest;$workAcceptRequest.actor='owner-fixture';$workAcceptRequest.role='TASK_OWNER';$workAcceptRequest.resultConsumer=[pscustomobject]@{channel='NATIVE_RESPONSE';recipient='USER'}
 $workAcceptRequest.acceptancePlan.stages[1].evidenceRefs=@($workVerdict);$workAcceptRequest.acceptancePlan.stages[1]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($workReviewed.pair)})
 $workAcceptRequest.acceptancePlan.stages[2].candidateRef=@($workCandidate)
 $workAccept=WorkPackage RESULT_ACCEPT $workAcceptRequest
 $workAccept|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=@($workCandidate);requirementsRef=$workAcceptRequest.requirementsRef;prerequisiteEvidenceRefs=@($workSelf,$workVerdict);reservedUserDecisionRefs=@();prerequisiteConsumption=[pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($workTestPassed.pair,$workReviewed.pair)}})
 $workAcceptPath=Join-Path $workStore 'work-accept-package.json';Store $workAcceptPath $workAccept;$workAcceptRef=[pscustomobject]@{path=$workAcceptPath;identity=(Identity $workAcceptPath)}
 $workAcceptFull=WorkDiscover 'work-accept-full' (WorkInput $workAcceptRequest RESULT_ACCEPT RESULT_ACCEPTANCE aiw:acceptance $workAcceptRef)
 $workAcceptAction=WorkAdmit 'work-accept-admit' (WorkCurrent $workAcceptFull)
 $workAccepted=WorkRecord 'work-acceptance' $workAcceptRequest RESULT_ACCEPTANCE ACCEPTED $workAcceptRef
 $workAcceptedF=WorkFinish 'work-accept-F' $workAcceptAction @($workAccepted)
 Check ($workAcceptedF.run.value.consumer.recipient-ceq'USER'-and$workAcceptedF.run.value.actionOutcome-ceq'OBSERVED') 'WORK-owner-acceptance-consumes-original-self-review-typed3-and-current-USER-consumer'
 Check ((Identity $operationTaskPath)-ceq$workTaskPreimage-and@(Get-ChildItem -LiteralPath (Split-Path -Parent $operationTaskPath) -File).Count-eq1) 'fresh-WORK-has-zero-task-create-update-close-archive-lifecycle'
 $bad=Clone $workReviewFull.input;$bad.requestContext.resultConsumer=[pscustomobject]@{channel='NATIVE_RESPONSE';recipient='USER'}
 $badRun=WorkRun 'work-review-wrong-user' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PROJECT_WORK_CONSUMER_OWNER_REQUIRED')) 'WORK-reviewer-cannot-redirect-typed3-verdict-to-USER'
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')
 $bad=Clone $workAcceptFull.input;$bad.requestContext.PSObject.Properties.Remove('acceptancePlan')
 $badRun=WorkRun 'work-missing-plan' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('QUALITY_PLAN_REQUIRED')) 'WORK-selected-QA2-cannot-omit-inline-plan'
 $bad=Clone $workAcceptFull.input;$bad.requestContext.owner='wrong-owner';$bad.requestContext.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient='wrong-owner'}
 $badRun=WorkRun 'work-changed-owner' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PROJECT_WORK_PACKAGE_CONTEXT_DRIFT')) 'WORK-self-reported-owner-cannot-rebind-existing-current-permission'
 $workGuard=New-AiwEvidenceContext $operationTemp '' $operationFramework
 $badRecord=Get-Content -LiteralPath $workSelf.path -Raw|ConvertFrom-Json -Depth 100;$badRecord.context.owner='wrong-owner'
 $badPath=Join-Path $workStore 'work-fake-owner-typed.json';Store $badPath $badRecord
 Reject {Read-AiwResultEvidence $workGuard ([pscustomobject]@{path=$badPath;identity=(Identity $badPath);kind='SELF_CHECK'}) $workVerification @($workCandidate) $workVerification.requirementsRef} 'EVIDENCE_WORK_CONTEXT_DRIFT' 'WORK-typed3-wrong-owner-fails-original-context-reader'
 $badRecord=Get-Content -LiteralPath $workSelf.path -Raw|ConvertFrom-Json -Depth 100;$badRecord|Add-Member taskId 'NONE';Store $badPath $badRecord
 Reject {Read-AiwResultEvidence $workGuard ([pscustomobject]@{path=$badPath;identity=(Identity $badPath);kind='SELF_CHECK'}) $workVerification @($workCandidate) $workVerification.requirementsRef} 'EVIDENCE_FIELD_SET' 'WORK-typed3-cannot-carry-fake-task-id'
 $bad=Clone $external;$bad.requestContext|Add-Member subject $workSubject
 $badRun=OperationRun 'work-quality-external-bypass' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PROJECT_WORK_CONTEXT_REQUIRED|QUALITY_STAGES')) 'EXTERNAL-entry-checks-stable-quality-before-any-tool-call'
 $bad.requestContext.PSObject.Properties.Remove('subject');$badRun=OperationRun 'work-quality-external-missing-subject' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('EXTERNAL_STABLE_SUBJECT_REQUIRED')) 'EXTERNAL-older-context-cannot-hide-required-stable-subject'
 # R1: preserve the Owner==writer chain above, then exercise its missing
 # three-actor branch with actual W write/test F and the same public consumers.
 # Human permission, actor qualification and host returns remain synthetic.
 $delegatedSaved=[pscustomobject]@{locator=$workLocator;store=$workStore}
 $delegatedOriginal=Join-Path $operationRuntime 'delegated-original-human.txt'
 WriteText $delegatedOriginal 'SYNTHETIC ORIGINAL HUMAN MATERIAL: Owner O authorizes distinct executor W to write and test this finite result, return ordinary contributions to O and route the frozen candidate to independent R. No task card or authenticated human/host authority is asserted.'
 $delegatedRequest=Clone $workRequest;$delegatedRequest.requestRef=[pscustomobject]@{kind='FILE';path=$delegatedOriginal;identity=(Identity $delegatedOriginal)}
 $delegatedWriter='01a00000-0000-7000-8000-000000000456'
 $delegatedRequest.actor=$delegatedWriter;$delegatedRequest.role='EXECUTOR';$delegatedRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient=$delegatedRequest.owner}
 $workLocator='request-'+(Get-AiwWorkRequestKey $delegatedRequest).Split('|')[1].Substring(0,32)
 $workStore=Join-Path $operationTemp ('.ai-workspace/runtime/'+$workLocator+'/owner-fixture');$null=[IO.Directory]::CreateDirectory($workStore)
 $delegatedPackage=WorkPackage SOURCE_WRITE $delegatedRequest
 $delegatedPackage.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$delegatedPackage|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE')
 $delegatedPackage.invalidatesOn+='CONTINUATION_RESULT_DRIFT'
 $delegatedPackage|Add-Member repairReviewPlan ([pscustomobject]@{writer=$delegatedWriter;reviewer=$workReviewerActor;maxCycles=2;materialContributors=@()})
 $delegatedAuthPath=Join-Path $workStore 'delegated-write-test-package.json';Store $delegatedAuthPath $delegatedPackage
 $delegatedAuth=[pscustomobject]@{path=$delegatedAuthPath;identity=(Identity $delegatedAuthPath)}
 $delegatedFull=WorkDiscover 'delegated-source-full' (WorkInput $delegatedRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $delegatedAuth)
 $bad=Clone $delegatedFull.input;$bad.requestContext.resultConsumer.recipient=$workReviewerActor
 $badRun=WorkRun 'delegated-ordinary-wrong-consumer' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PROJECT_WORK_CONTRIBUTION_OWNER_REQUIRED')) 'WORK-delegated-ordinary-write-still-requires-Owner-consumer'
 $bad=WorkInput $bad.requestContext NONE USER_RESPONSE aiw:discussion 'NOT_REQUIRED'
 $badRun=WorkRun 'delegated-unpackaged-NONE-wrong-consumer' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PROJECT_WORK_CONTRIBUTION_OWNER_REQUIRED')) 'WORK-delegated-unpackaged-NONE-cannot-bypass-Owner-consumer'
 $delegatedOwnerDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient=$delegatedRequest.owner;observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
 $delegatedSource=WorkAdmit 'delegated-source-admit' (WorkCurrent $delegatedFull)
 WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual distinct executor W source postimage owned by O.'
 $delegatedWritten=WorkFinish 'delegated-source-F' $delegatedSource -Delivery $delegatedOwnerDelivery
 Check ($delegatedWritten.run.value.consumer.recipient-ceq$delegatedRequest.owner-and$delegatedWritten.run.value.delivery.delivered) 'WORK-delegated-real-write-original-F-delivers-ordinary-contribution-to-Owner'
 $delegatedCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
 $delegatedVerification=Clone $delegatedRequest;$delegatedVerification.phase='VERIFY';$delegatedVerification.acceptancePlan.stages[0].candidateRef=@($delegatedCandidate)
 $delegatedTestFull=WorkDiscover 'delegated-test-full' (WorkInput $delegatedVerification TEST_RUN TEST_RESULT aiw:verification $delegatedAuth $delegatedWritten.continuation)
 $delegatedTest=WorkAdmit 'delegated-test-admit' (WorkCurrent $delegatedTestFull)
 $observed=@(WorkNative 'delegated-native-zero');$observed[0..($observed.Count-2)]|Write-Output;$delegatedNative=$observed[-1]
 Check ($delegatedNative.code-eq0) 'WORK-delegated-test-actually-executes-native-zero'
 $delegatedSelf=WorkRecord 'delegated-self' $delegatedVerification SELF_CHECK PASS -Command $delegatedNative.command
 $delegatedTested=WorkFinish 'delegated-test-F' $delegatedTest @($delegatedSelf) -Delivery $delegatedOwnerDelivery
 Check ($delegatedTested.run.value.actionOutcome-ceq'PASS'-and$delegatedTested.run.value.consumer.recipient-ceq$delegatedRequest.owner) 'WORK-delegated-real-test-original-F-and-SELF-belong-to-W-return-to-O'
 $delegatedBinding=[pscustomobject]@{parentPackagePath=$delegatedAuth.path;parentPackageIdentity=$delegatedAuth.identity;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=$delegatedTested.pair.inputRef.path;repairFinalizeInputIdentity=$delegatedTested.pair.inputRef.identity;repairFinalizeResultPath=$delegatedTested.pair.resultRef.path;repairFinalizeResultIdentity=$delegatedTested.pair.resultRef.identity}
 $delegatedReview=WorkRepairFactory 'delegated-review-factory' $delegatedBinding
 $delegatedReviewRequest=Clone $delegatedVerification;$delegatedReviewRequest.actor=$workReviewerActor;$delegatedReviewRequest.role='REVIEWER';$delegatedReviewRequest.phase='REVIEW'
 $delegatedReviewRequest.acceptancePlan.stages[0].evidenceRefs=@($delegatedSelf);$delegatedReviewRequest.acceptancePlan.stages[0]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($delegatedTested.pair)})
 $delegatedReviewRequest.acceptancePlan.stages[1].candidateRef=@($delegatedCandidate);$delegatedReview.requestContext=Clone $delegatedReviewRequest
 $delegatedReviewPath=Join-Path $workStore 'delegated-review-package.json';Store $delegatedReviewPath $delegatedReview
 $delegatedReviewRef=[pscustomobject]@{path=$delegatedReviewPath;identity=(Identity $delegatedReviewPath)}
 $delegatedRouteRequest=Clone $delegatedReviewRequest;$delegatedRouteRequest.actor=$delegatedWriter;$delegatedRouteRequest.role='EXECUTOR';$delegatedRouteRequest.resultConsumer.recipient=$workReviewerActor
 $delegatedRouteFull=WorkDiscover 'delegated-route-full' (WorkInput $delegatedRouteRequest REVIEW_ROUTE HANDOFF aiw:review $delegatedAuth $delegatedTested.continuation)
 $delegatedCurrent=WorkCurrent $delegatedRouteFull
 $delegatedDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient=$workReviewerActor;observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=$delegatedReviewRef}
 $delegatedBoundary=[pscustomobject]@{schemaVersion=4;mode='ADMIT_ACTION';currentOperation=$delegatedCurrent;preparationReceipts=@($delegatedRouteFull.result.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($delegatedSelf);deliveryContext=$delegatedDelivery}
 $bad=Clone $delegatedBoundary;$bad.evidenceRefs=@()
 $badRun=WorkRun 'delegated-route-missing-SELF' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('TYPED_EVIDENCE_REQUIRED|SELF_CHECK')) 'WORK-delegated-route-missing-SELF-rejected-at-original-preparation-gate'
 $badReview=Clone $delegatedReview;$badReview.grantee=$delegatedWriter;$badReview.requestContext.actor=$delegatedWriter
 $badReviewPath=Join-Path $workStore 'delegated-dependent-review-package.json';Store $badReviewPath $badReview
 $bad=Clone $delegatedBoundary;$bad.deliveryContext.reviewPackageRef=[pscustomobject]@{path=$badReviewPath;identity=(Identity $badReviewPath)}
 $badRun=WorkRun 'delegated-route-dependent-reviewer' $bad -Compact
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT')) 'WORK-delegated-route-dependent-R-rejected-at-real-qualification-gate'
 $delegatedRoute=WorkAdmit 'delegated-route-admit' $delegatedCurrent @($delegatedSelf) $delegatedDelivery
 $bad=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$delegatedRoute.result.value.operationRef;preparationReceipts=@($delegatedRoute.saved.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($delegatedRoute.saved.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|docs/value.md|'+$delegatedCandidate.identity);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($delegatedSelf);deliveryContext=(Clone $delegatedDelivery)}
 $bad.deliveryContext.expectedRecipient='01a00000-0000-7000-8000-000000000789'
 $badRun=WorkRun 'delegated-route-wrong-recipient' $bad
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('DELIVERY_CONSUMER_CHANNEL_MISMATCH')) 'WORK-delegated-route-wrong-R-rejected-at-real-final-delivery-gate'
 $delegatedRouted=WorkFinish 'delegated-route-F' $delegatedRoute @($delegatedSelf) -Delivery $delegatedDelivery
 Check ($delegatedWriter-cne$delegatedRequest.owner-and$workReviewerActor-cnotin@($delegatedWriter,$delegatedRequest.owner)-and$delegatedRouted.run.value.delivery.delivered-and$delegatedRouted.run.value.consumer.recipient-ceq$workReviewerActor-and$delegatedRouted.run.value.actionOutcome-ceq'OBSERVED') 'WORK-distinct-O-W-R-completes-original-write-test-route-D-A-PREPARE-OBSERVE-F'
 Check ((Identity $operationTaskPath)-ceq$workTaskPreimage-and@(Get-ChildItem -LiteralPath (Split-Path -Parent $operationTaskPath) -File).Count-eq1) 'WORK-delegated-chain-keeps-real-task-lifecycle-zero'
 $workLocator=$delegatedSaved.locator;$workStore=$delegatedSaved.store
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')

 # A distinct QA2 request genuinely selects review alone. Reach the public
 # producer -> factory -> route -> original typed review without a fabricated
 # SELF stage or command; missing production completion must fail at its gate.
 $zeroSaved=[pscustomobject]@{quality=$workQuality;locator=$workLocator;store=$workStore}
 $zeroPolicy=Clone $workPolicy;$zeroPolicy.qualityAssurance.defaultStages=@('RESULT_REVIEW')
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $zeroPolicy
 $zeroOriginal=Join-Path $operationRuntime 'zero-self-original-human.txt'
 WriteText $zeroOriginal 'SYNTHETIC ORIGINAL HUMAN MATERIAL: an independent review is required for this finite result; no SELF stage is selected. Source permission, human origin and reviewer qualification are synthetic fixture inputs.'
 $zeroRequirements=Join-Path $operationRuntime 'zero-self-requirements.md'
 WriteText $zeroRequirements 'An actual admitted write and its original successful F must support review. There is no SELF stage, no self repair grant and no task lifecycle. Never substitute a fabricated SELF for production completion.'
 $workQuality=Get-AiwQualitySelection $zeroPolicy (Identity (Join-Path $operationTemp '.ai-workspace/process-policy.json')) STANDARD $workSubject
 $zeroRequest=Clone $workRequest;$zeroRequest.requestRef.path=$zeroOriginal;$zeroRequest.requestRef.identity=Identity $zeroOriginal;$zeroRequest.requirementsRef=[pscustomobject]@{path=$zeroRequirements;identity=(Identity $zeroRequirements)}
 $zeroRequest.acceptancePlan=[pscustomobject]@{schemaVersion=2;qualityBinding=$workQuality.qualityBinding;stages=@([pscustomobject]@{id='zero-review';kind='RESULT_REVIEW';requiredBy=$zeroRequest.requirementsRef;dependsOn=@();candidateRef=@();evidenceRefs=@()})}
 $workLocator='request-'+(Get-AiwWorkRequestKey $zeroRequest).Split('|')[1].Substring(0,32)
 $workStore=Join-Path $operationTemp ('.ai-workspace/runtime/'+$workLocator+'/owner-fixture');$null=[IO.Directory]::CreateDirectory($workStore)
 $zeroPrepare=Clone $workPrepare;$zeroPrepare.policyRef.identity=Identity (Join-Path $operationTemp '.ai-workspace/process-policy.json');$zeroPrepare.requestContext=Clone $zeroRequest
 $zeroPreparePath=Join-Path $workStore 'zero-quality-prepare.json';Store $zeroPreparePath $zeroPrepare
 $zeroPrepared=WorkCli 'WORK-zero-self-quality' (Join-Path $operationVersion 'scripts/resolve-workflow-route.ps1') @('-InputPath',$zeroPreparePath,'-AsJson')
 Check ($zeroPrepared.code-eq0) ('WORK-zero-self-public-quality-native-zero|'+$zeroPrepared.text)
 $zeroPlan=$zeroPrepared.text|ConvertFrom-Json -Depth 100
 Check (($zeroPlan.effectiveStages-join'|')-ceq'RESULT_REVIEW'-and@($zeroPlan.plan.stages|Where-Object kind -CEQ 'SELF_CHECK').Count-eq0) 'WORK-zero-self-public-plan-really-omits-SELF'
 $zeroRequest.acceptancePlan=Clone $zeroPlan.plan
 $zeroPackage=WorkPackage SOURCE_WRITE $zeroRequest;$zeroPackage.actions=@('SOURCE_WRITE','REVIEW_ROUTE');$zeroPackage|Add-Member continuationPlan @('SOURCE_WRITE','REVIEW_ROUTE');$zeroPackage.invalidatesOn+='CONTINUATION_RESULT_DRIFT'
 $zeroPackage|Add-Member repairReviewPlan ([pscustomobject]@{writer='owner-fixture';reviewer=$workReviewerActor;maxCycles=2;materialContributors=@()})
 $zeroAuthPath=Join-Path $workStore 'zero-source-package.json';Store $zeroAuthPath $zeroPackage;$zeroAuth=[pscustomobject]@{path=$zeroAuthPath;identity=(Identity $zeroAuthPath)}
 $zeroFull=WorkDiscover 'zero-source-full' (WorkInput $zeroRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $zeroAuth)
 $zeroSource=WorkAdmit 'zero-source-admit' (WorkCurrent $zeroFull)
 WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual zero-SELF source postimage for direct original-production-backed review.'
 $zeroWritten=WorkFinish 'zero-source-F' $zeroSource
 Check ($zeroWritten.run.value.actionOutcome-ceq'OBSERVED'-and$zeroWritten.run.value.continuationReceipt.nextAction-ceq'REVIEW_ROUTE'-and$zeroWritten.run.value.continuationReceipt.evidenceRefs.Count-eq0) 'WORK-zero-self-original-write-F-directly-produces-review-continuation-without-SELF'
 $zeroCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
 $zeroBinding=[pscustomobject]@{parentPackagePath=$zeroAuth.path;parentPackageIdentity=$zeroAuth.identity;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=$zeroWritten.pair.inputRef.path;repairFinalizeInputIdentity=$zeroWritten.pair.inputRef.identity;repairFinalizeResultPath=$zeroWritten.pair.resultRef.path;repairFinalizeResultIdentity=$zeroWritten.pair.resultRef.identity}
 $zeroReview=WorkRepairFactory 'zero-review-factory' $zeroBinding
 $zeroReviewRequest=Clone $zeroRequest;$zeroReviewRequest.actor=$workReviewerActor;$zeroReviewRequest.role='REVIEWER';$zeroReviewRequest.phase='REVIEW';$zeroReviewRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient='owner-fixture'};$zeroReviewRequest.acceptancePlan.stages[0].candidateRef=@($zeroCandidate)
 $zeroReview.requestContext=Clone $zeroReviewRequest
 $zeroReviewPath=Join-Path $workStore 'zero-review-package.json';Store $zeroReviewPath $zeroReview;$zeroReviewRef=[pscustomobject]@{path=$zeroReviewPath;identity=(Identity $zeroReviewPath)}
 $zeroRouteRequest=Clone $zeroReviewRequest;$zeroRouteRequest.actor='owner-fixture';$zeroRouteRequest.role='TASK_OWNER';$zeroRouteRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient=$workReviewerActor}
 $zeroRouteFull=WorkDiscover 'zero-route-full' (WorkInput $zeroRouteRequest REVIEW_ROUTE HANDOFF aiw:review $zeroAuth $zeroWritten.continuation)
 $zeroCurrent=WorkCurrent $zeroRouteFull
 $zeroDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient=$workReviewerActor;observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE';reviewPackageRef=$zeroReviewRef}
 $missingProduction=[pscustomobject]@{schemaVersion=4;mode='ADMIT_ACTION';currentOperation=$zeroCurrent;preparationReceipts=@($zeroRouteFull.result.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@();deliveryContext=$zeroDelivery}
 $missingRun=WorkRun 'zero-route-missing-production' $missingProduction -Compact
 Check ($missingRun.code-ne0-and$missingRun.value.reason.Contains('QUALITY_PRODUCTION_FINALIZE_REQUIRED')) 'WORK-zero-self-route-rejects-missing-real-production-F-at-target-gate'
 $zeroRoute=WorkAdmit 'zero-route-admit' $zeroCurrent @() $zeroDelivery $zeroWritten.pair
 $zeroRouted=WorkFinish 'zero-route-F' $zeroRoute -Delivery $zeroDelivery -ProductionFinalize $zeroWritten.pair
 Check ($zeroRouted.run.value.delivery.delivered-and$zeroRouted.run.value.actionOutcome-ceq'OBSERVED') 'WORK-zero-self-route-original-PREPARE-OBSERVE-consumes-real-production-F-with-empty-SELF'
 $zeroReviewFull=WorkDiscover 'zero-review-full' (WorkInput $zeroReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review $zeroReviewRef)
 $zeroReviewStep=WorkAdmit 'zero-review-admit' (WorkCurrent $zeroReviewFull)
 $zeroVerdict=WorkRecord 'zero-review-verdict' $zeroReviewRequest REVIEW_VERDICT APPROVED $zeroReviewRef
 $zeroReviewDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='owner-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
 $zeroReviewed=WorkFinish 'zero-review-F' $zeroReviewStep @($zeroVerdict) -Delivery $zeroReviewDelivery
 Check ($zeroReviewed.run.value.delivery.delivered-and$zeroReviewed.run.value.consumer.recipient-ceq'owner-fixture') 'WORK-zero-self-independent-typed3-review-original-F-consumed-by-owner'
 Check ((Identity $operationTaskPath)-ceq$workTaskPreimage-and@(Get-ChildItem -LiteralPath (Split-Path -Parent $operationTaskPath) -File).Count-eq1) 'WORK-zero-self-keeps-real-task-lifecycle-zero'
 $workQuality=$zeroSaved.quality;$workLocator=$zeroSaved.locator;$workStore=$zeroSaved.store
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')

 # One additional short TASK chain is necessary to prove the cross-context
 # edge. It is independent of the existing TASK exhaustion counterexample;
 # the already exercised full WORK review/repair/accept chain is not copied.
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $workPolicy
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID','owner-fixture','Process')
 $bridgeSavedRuntime=$operationRuntime
 $operationRuntime=Join-Path $operationTemp '.ai-workspace/runtime/BRIDGE-001/owner-fixture';$null=[IO.Directory]::CreateDirectory($operationRuntime)
 $bridgeOriginal=Join-Path $operationRuntime 'original-human.txt';WriteText $bridgeOriginal 'SYNTHETIC ORIGINAL HUMAN MATERIAL: the same owner may finish this exact finite result and may explicitly supersede its TASK with the same request. No real human or host authority is asserted.'
 $bridgeDecision=Join-Path $operationRuntime 'omit-card-human.txt';WriteText $bridgeDecision 'SYNTHETIC SINGLE HUMAN DECISION: after original actions stop, supersede BRIDGE-001 and continue the same owner, original request, complete software subject and requirements without a task card. Preserve actual prior quality and nonzero budgets.'
 $bridgeRequirements=Join-Path $operationRuntime 'requirements.md';WriteText $bridgeRequirements 'The same exact document and stable subject require SELF, independent review and acceptance. A transient failure may retry once. Already completed original quality and original cumulative limits must survive the card transition.'
 $bridgeTaskRelative='.ai-workspace/tasks/active/BRIDGE-001.md';$bridgeTaskPath=Join-Path $operationTemp $bridgeTaskRelative
 $bridgePlan=Clone $workPlan
 foreach($stage in $bridgePlan.stages){$stage.requiredBy=[pscustomobject]@{path=$bridgeRequirements;identity=(Identity $bridgeRequirements)};$stage.candidateRef=@();$stage.evidenceRefs=@()}
 $bridgeBase='# BRIDGE-001 — finite predecessor fixture

- Owner: owner-fixture
- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT
- Range summary: profile=STANDARD; lifecycle=ACTIVE; risk=MEDIUM; size=SMALL; uncertainty=LOW
'
 function BridgeTaskText { $bridgeBase+'```aiw-acceptance-plan'+[char]10+($bridgePlan|ConvertTo-Json -Depth 100 -Compress)+[char]10+'```'+[char]10 }
 WriteText $bridgeTaskPath (BridgeTaskText)
 $bridgePackage=Clone $operationPackage;$bridgePackage.taskId='BRIDGE-001';$bridgePackage.taskIdentity=Identity $bridgeTaskPath;$bridgePackage.objectIdentities[0].identity=Identity (Join-Path $operationTemp 'docs/value.md')
 $bridgePackage.actions=@('SOURCE_WRITE','TEST_RUN');$bridgePackage|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN');$bridgePackage|Add-Member selfCheckRepairLimit 1;$bridgePackage|Add-Member qualityBinding $workQuality.qualityBinding;$bridgePackage.invalidatesOn+='CONTINUATION_RESULT_DRIFT'
 $bridgeAuthPath=Join-Path $operationRuntime 'authorization.json';Store $bridgeAuthPath $bridgePackage
 $bridgeInput=Clone $operationInput;$bridgeInput.taskPath=$bridgeTaskPath;$bridgeInput.expectedTaskIdentity=$bridgePackage.taskIdentity;$bridgeInput.authorizationRef=[pscustomobject]@{path=$bridgeAuthPath;identity=(Identity $bridgeAuthPath)}
 function BridgeDiscover([string]$Name,$InputValue){
  $run=OperationRun $Name $InputValue -Compact;OperationPass $run $Name
  $current=Clone $InputValue;foreach($field in @('schemaVersion','mode','ruleLoad','evaluationOnly')){$current.PSObject.Properties.Remove($field)}
  $current.recoveryState='CURRENT';$current|Add-Member ruleReadRef $run.value.savedCompactReceipt
  [pscustomobject]@{run=$run;current=$current}
 }
 function BridgeAdmit([string]$Name,$Full,$Current=$null){
  if($null-eq$Current){$Current=$Full.current}
  $inputValue=[pscustomobject]@{schemaVersion=4;mode='ADMIT_ACTION';currentOperation=$Current;preparationReceipts=@($Full.run.value.compactReceipt.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  $run=OperationRun $Name $inputValue -Compact;OperationPass $run $Name
  [pscustomobject]@{run=$run;saved=(Get-Content -LiteralPath $run.value.operationRef.path -Raw|ConvertFrom-Json -Depth 100)}
 }
 function BridgeFinish([string]$Name,$Step,$Evidence=@(),[string]$Disposition='ADVANCE'){
  $saved=$Step.saved
  $inputValue=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$Step.run.value.operationRef;preparationReceipts=@($saved.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($saved.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|docs/value.md|'+(Identity (Join-Path $operationTemp 'docs/value.md')));deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($Evidence);continuationDisposition=$Disposition}
  $run=OperationRun $Name $inputValue;OperationPass $run $Name
  $continuation=$null
  if($null-ne$run.value.PSObject.Properties['continuationReceipt']){$p=Join-Path $operationRuntime ($Name+'-continuation.json');Store $p $run.value.continuationReceipt;$continuation=[pscustomobject]@{path=$p;identity=(Identity $p)}}
  [pscustomobject]@{run=$run;pair=(WorkPair $run);continuation=$continuation}
 }
 function BridgeSelf([string]$Name){
  $marker=Join-Path $operationRuntime 'transient-marker.txt'
  $argv=@('-NoProfile','-NonInteractive','-File',$retestProbe,'-Marker',$marker)
  $native=Invoke-AiwTestProcess ([Environment]::ProcessPath) $argv -WorkingDirectory $operationTemp -GroupId 'task-work-finite-predecessor'
  Write-Host ('OBSERVE|'+$Name+'|nativeExit='+$native.Code+'|nativeRecord='+$native.ResultPath)
  $outputPath=Join-Path $operationRuntime ($Name+'-stdout.raw');[IO.File]::Copy($native.Record.stdout.path,$outputPath,$false)
  $commandPath=Join-Path $operationRuntime ($Name+'-command.json')
  Store $commandPath ([pscustomobject]@{command=([Environment]::ProcessPath+' '+($argv-join' '));exitCode=$native.Code;output=[pscustomobject]@{path=$outputPath;identity=(Identity $outputPath)}})
  $outcome=if($native.Code-eq0){'PASS'}else{'FAIL'}
  $record=[pscustomobject]@{schemaVersion=1;taskId=$bridgePackage.taskId;actor='owner-fixture';candidateObjects=@([pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))});requirementsRef=[pscustomobject]@{path=$bridgeRequirements;identity=(Identity $bridgeRequirements)};outcome=$outcome;checks=@([pscustomobject]@{id=$Name;method='COMMAND';outcome=$outcome;reason='Actual native transient failure or recovery; synthetic human/role inputs.';evidenceLocators=@([pscustomobject]@{path=$commandPath;identity=(Identity $commandPath)})});evidenceLocators=@([pscustomobject]@{path=$outputPath;identity=(Identity $outputPath)})}
  $p=Join-Path $operationRuntime ($Name+'-self.json');Store $p $record
  [pscustomobject]@{kind='SELF_CHECK';path=$p;identity=(Identity $p)}
 }
 $bridgeSourceFull=BridgeDiscover 'bridge-task-source-full' $bridgeInput
 $bridgeSource=BridgeAdmit 'bridge-task-source-admit' $bridgeSourceFull
 WriteText (Join-Path $operationTemp 'docs/value.md') 'Exact candidate retained across the finite TASK to WORK edge.'
 $bridgeWritten=BridgeFinish 'bridge-task-source-final' $bridgeSource
 $bridgeTestInput=Clone $bridgeInput;$bridgeTestInput.intentEnvelope.requestedActionKind='TEST_RUN';$bridgeTestInput.intentEnvelope.requestedResultKind='TEST_RESULT';$bridgeTestInput.intentEnvelope.facets.workType.values=@('aiw:verification');$bridgeTestInput.intentEnvelope.facets.deliverableType.values=@('aiw:test-result')
 $bridgeTestInput|Add-Member continuationReceiptPath $bridgeWritten.continuation.path;$bridgeTestInput|Add-Member expectedContinuationReceiptIdentity $bridgeWritten.continuation.identity
 $bridgeTestFull=BridgeDiscover 'bridge-task-test-full' $bridgeTestInput
 $bridgeFirst=BridgeAdmit 'bridge-task-test-admit' $bridgeTestFull
 $bridgeFailed=BridgeSelf 'bridge-task-native-failed'
 $bridgeRetry=BridgeFinish 'bridge-task-failed-final' $bridgeFirst @($bridgeFailed) RETEST
 $bridgeCurrent=Clone $bridgeTestFull.current;$bridgeCurrent.continuationReceiptPath=$bridgeRetry.continuation.path;$bridgeCurrent.expectedContinuationReceiptIdentity=$bridgeRetry.continuation.identity
 $bridgeSecond=BridgeAdmit 'bridge-task-retest-admit' $bridgeTestFull $bridgeCurrent
 $bridgePassed=BridgeSelf 'bridge-task-native-passed'
 $bridgeStopped=BridgeFinish 'bridge-task-passed-stop-final' $bridgeSecond @($bridgePassed) STOP
 Check ($bridgeStopped.run.value.actionOutcome-ceq'PASS'-and$bridgeStopped.run.value.successorState-ceq'STOPPED'-and$null-eq$bridgeStopped.run.value.PSObject.Properties['continuationReceipt']-and$bridgeSecond.saved.operation.binding.continuationStepIndex-eq1) 'TASK-predecessor-real-STOP-has-no-output-continuation-after-nonzero-retry'
 $bridgeCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
 $bridgePlan.stages[0].candidateRef=@($bridgeCandidate);$bridgePlan.stages[0].evidenceRefs=@($bridgePassed);$bridgePlan.stages[0]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($bridgeStopped.pair)})
 WriteText $bridgeTaskPath (BridgeTaskText)
 $bridgePreimagePath=Join-Path $operationRuntime 'closing-task-preimage.md';[IO.File]::Copy($bridgeTaskPath,$bridgePreimagePath,$false)
 $bridgeRequest=Clone $workRequest;$bridgeRequest.requestRef=[pscustomobject]@{kind='FILE';path=$bridgeOriginal;identity=(Identity $bridgeOriginal)};$bridgeRequest.requirementsRef=[pscustomobject]@{path=$bridgeRequirements;identity=(Identity $bridgeRequirements)};$bridgeRequest.acceptancePlan=Clone $bridgePlan;$bridgeRequest|Add-Member userDecisionRef ([pscustomobject]@{kind='FILE';path=$bridgeDecision;identity=(Identity $bridgeDecision)})
 $bridgeClosureDecision=[pscustomobject]@{userDecisionRef=$bridgeRequest.userDecisionRef;predecessorTaskRef=[pscustomobject]@{path=$bridgePreimagePath;identity=(Identity $bridgePreimagePath)};successorRequest=[pscustomobject]@{requestRef=$bridgeRequest.requestRef;owner=$bridgeRequest.owner;subject=$bridgeRequest.subject;requirementsRef=$bridgeRequest.requirementsRef};completedActionRefs=@($bridgeStopped.pair);repairHeads=[pscustomobject]@{selfCheck=$bridgeStopped.pair;review='NOT_APPLICABLE'}}
 $bridgeClosurePath=Join-Path $operationRuntime 'supersession-decision.json';Store $bridgeClosurePath $bridgeClosureDecision
 $bridgeClosePackage=Clone $operationPackage;$bridgeClosePackage.taskId='BRIDGE-001';$bridgeClosePackage.taskIdentity=Identity $bridgeTaskPath;$bridgeClosePackage.actions=@('CONTROL_WRITE');$bridgeClosePackage.exactPaths=@($bridgeTaskRelative);$bridgeClosePackage.objectIdentities=@([pscustomobject]@{path=$bridgeTaskRelative;identity=$bridgeClosePackage.taskIdentity})
 $bridgeCloseAuth=Join-Path $operationRuntime 'close-authorization.json';Store $bridgeCloseAuth $bridgeClosePackage
 $bridgeCloseInput=Clone $bridgeInput;$bridgeCloseInput.expectedTaskIdentity=$bridgeClosePackage.taskIdentity;$bridgeCloseInput.authorizationRef=[pscustomobject]@{path=$bridgeCloseAuth;identity=(Identity $bridgeCloseAuth)};$bridgeCloseInput.exactPaths=@($bridgeTaskRelative);$bridgeCloseInput.intentEnvelope.requestedActionKind='CONTROL_WRITE';$bridgeCloseInput.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$bridgeCloseInput.intentEnvelope.pathHints=@()
 $bridgeCloseFull=BridgeDiscover 'bridge-close-full' $bridgeCloseInput
 $bridgeClose=BridgeAdmit 'bridge-close-admit' $bridgeCloseFull
 $bridgeClosed=(BridgeTaskText).Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+[char]10+'- Closure outcome: SUPERSEDED'+[char]10+'- Closure basis: Same finite result continues through the uniquely frozen successor.'+[char]10+'- Output disposition: Retain the actual candidate and original evidence.'+[char]10+'- Git disposition: DEFERRED; isolated fixture only.'+[char]10+'- Unresolved obligations: TRANSFERRED: the uniquely bound successor WORK retains review and acceptance.'+[char]10+'- Writer: RELEASED'+[char]10+'- Reviewer: RELEASED'+[char]10+'- Authorization: RELEASED'+[char]10+'- Closure decision: '+$bridgeClosurePath+'#'+(Identity $bridgeClosurePath)+[char]10+'- Unfinished work: Continue the same finite result and exact quality stages.'+[char]10
 WriteText $bridgeTaskPath $bridgeClosed
 $bridgeCloseBoundary=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$bridgeClose.run.value.operationRef;preparationReceipts=@($bridgeClose.saved.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($bridgeClose.saved.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$bridgeTaskRelative+'|'+(Identity $bridgeTaskPath));deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 $bridgeCloseFinal=OperationRun 'bridge-close-final' $bridgeCloseBoundary;OperationPass $bridgeCloseFinal 'TASK-predecessor-actual-SUPERSEDED-original-F'
 $bridgeRequest|Add-Member predecessorRef ([pscustomobject]@{kind='TASK_SUPERSEDED';closureFinalize=(WorkPair $bridgeCloseFinal)})
 $bridgeGuard=New-AiwEvidenceContext $operationTemp '' $operationFramework
 try{Assert-AiwWorkPredecessor $bridgeGuard $bridgeRequest}catch{
  Write-Host ('OBSERVE|bridge-predecessor-read|reason='+$_.Exception.Message+'|stack='+$_.ScriptStackTrace)
  Write-Host ('ORIGINAL-CLOSE-INPUT|'+[IO.File]::ReadAllText($bridgeCloseFinal.inputPath))
  Write-Host ('ORIGINAL-CLOSE-RESULT|'+($bridgeCloseFinal.value|ConvertTo-Json -Depth 100 -Compress))
  throw
 }
 $tamperedClose=Clone $bridgeCloseFinal.value;$tamperedClose.decisionIdentity=('0'*64)
 $tamperedClosePath=Join-Path $operationRuntime 'tampered-close-result.json';Store $tamperedClosePath $tamperedClose
 $bad=Clone $bridgeRequest;$bad.predecessorRef.closureFinalize.resultRef=[pscustomobject]@{path=$tamperedClosePath;identity=(Identity $tamperedClosePath)}
 Reject {Assert-AiwWorkPredecessor $bridgeGuard $bad} 'EVIDENCE_HISTORICAL_FINALIZE_DECISION' 'WORK-predecessor-rejects-changed-original-close-decision'
 $bridgeRecord=Read-AiwResultEvidence $bridgeGuard $bridgePassed $bridgeRequest @($bridgeCandidate) $bridgeRequest.requirementsRef -RequireSuccess
 Check ($bridgeRecord.schemaVersion-eq1-and$bridgeRecord.taskId-ceq'BRIDGE-001'-and$bridgeRecord.outcome-ceq'PASS') 'WORK-consumes-original-typed1-with-real-old-task-id-and-original-F'
 $bridgeWorkPackage=WorkPackage SOURCE_WRITE $bridgeRequest;$bridgeWorkPackage.actions=@('SOURCE_WRITE','TEST_RUN');$bridgeWorkPackage|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN');$bridgeWorkPackage|Add-Member selfCheckRepairLimit 1;$bridgeWorkPackage.invalidatesOn+='CONTINUATION_RESULT_DRIFT'
 Check ((Get-AiwSelfRepairOriginCycle $bridgeGuard $bridgeWorkPackage)-eq1) 'WORK-first-step-zero-inherits-original-SELF-cycle-one-from-STOP-compact'
 $bad=Clone $bridgeWorkPackage;$bad.selfCheckRepairLimit=2
 Reject {Assert-AiwWorkPredecessorPackage $bridgeGuard $bridgeRequest $bad} 'WORK_PREDECESSOR_SELF_LIMIT_DRIFT' 'WORK-predecessor-cannot-regrant-larger-self-limit'
 $bad=Clone $bridgeRequest;$bad.subject.facets.workType.values=@('aiw:verification')
 Reject {Assert-AiwWorkPredecessor $bridgeGuard $bad} 'WORK_PREDECESSOR_SUCCESSOR_DRIFT' 'WORK-predecessor-cannot-substitute-stable-original-work-type'
 $bad=Clone $bridgeRequest;$oldStageId=$bridgePlan.stages[0].id;$bad.acceptancePlan.stages[0].id='substitute-original-self'
 foreach($stage in $bad.acceptancePlan.stages){$stage.dependsOn=@($stage.dependsOn|ForEach-Object{if($_-ceq$oldStageId){'substitute-original-self'}else{$_}})}
 Reject {Assert-AiwWorkPredecessor $bridgeGuard $bad} 'WORK_PREDECESSOR_STAGE_REMOVED' 'WORK-predecessor-cannot-drop-completed-original-stage'
 # A real current WORK admission/source/F proves that old completion does
 # not itself grant execution and that the new continuation starts at c=1.
 $workLocator='request-'+(Get-AiwWorkRequestKey $bridgeRequest).Split('|')[1].Substring(0,32)
 $workStore=Join-Path $operationTemp ('.ai-workspace/runtime/'+$workLocator+'/owner-fixture');$null=[IO.Directory]::CreateDirectory($workStore)
 $bridgeWorkAuth=Join-Path $workStore 'bridge-work-package.json';Store $bridgeWorkAuth $bridgeWorkPackage
 $bridgeWorkRef=[pscustomobject]@{path=$bridgeWorkAuth;identity=(Identity $bridgeWorkAuth)}
 $bridgeWorkFull=WorkDiscover 'bridge-work-source-full' (WorkInput $bridgeRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $bridgeWorkRef)
 $bridgeWorkStep=WorkAdmit 'bridge-work-source-admit' (WorkCurrent $bridgeWorkFull)
 WriteText (Join-Path $operationTemp 'docs/value.md') 'A real narrow revision after the finite TASK to WORK edge; old quality covers only its original candidate.'
 $bridgeWorkWritten=WorkFinish 'bridge-work-source-final' $bridgeWorkStep
 Check ($bridgeWorkWritten.run.value.continuationReceipt.selfRepairCycle-eq1-and$bridgeWorkWritten.run.value.continuationReceipt.completedStepIndex-eq0) 'WORK-real-new-permission-source-F-emits-inherited-cycle-one-at-step-zero'
 $bridgeChanged=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
 Reject {Read-AiwResultEvidence $bridgeGuard $bridgePassed $bridgeRequest @($bridgeChanged) $bridgeRequest.requirementsRef -RequireSuccess} 'EVIDENCE_CANDIDATE_DRIFT' 'WORK-predecessor-old-typed-PASS-cannot-cover-changed-current-candidate'
 $closedPackage=Clone $bridgePackage;$closedPackage.taskIdentity=Identity $bridgeTaskPath;$closedPackage.objectIdentities[0].identity=Identity (Join-Path $operationTemp 'docs/value.md')
 $closedPackagePath=Join-Path $operationRuntime 'closed-task-refreshed-package.json';Store $closedPackagePath $closedPackage
 $closedFuture=Clone $bridgeTestInput;$closedFuture.expectedTaskIdentity=$closedPackage.taskIdentity;$closedFuture.authorizationRef=[pscustomobject]@{path=$closedPackagePath;identity=(Identity $closedPackagePath)}
 $oldFuture=OperationRun 'bridge-old-task-future' $closedFuture -Compact
 Write-Host ('OBSERVE|closed-TASK-future|reason='+$oldFuture.value.reason)
 Check ($oldFuture.code-ne0-and$oldFuture.value.reason.Contains('TASK_LIFECYCLE_DRIFT')) 'closed-TASK-refreshed-package-cannot-regain-original-execution'
 $operationRuntime=$bridgeSavedRuntime

 # QA1 lacks workType in its original binding. This separate initial safe
 # point has no old repair grant, so it needs no duplicate native retry chain.
 # The two real human-origin materials are explicit synthetic fixture data;
 # semantic adequacy is an Owner judgment, not a keyword/identity assertion.
 $qa1Saved=[pscustomobject]@{runtime=$operationRuntime;locator=$workLocator;store=$workStore;quality=$workQuality}
 $operationRuntime=Join-Path $operationTemp '.ai-workspace/runtime/QA1-001/owner-fixture';$null=[IO.Directory]::CreateDirectory($operationRuntime)
 $qa1Policy=Clone $workPolicy;$qa1Policy.qualityAssurance.schemaVersion=1
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $qa1Policy
 $qa1Original=Join-Path $operationRuntime 'original-human.txt'
 WriteText $qa1Original ('SYNTHETIC ORIGINAL HUMAN MATERIAL; no real human authentication is claimed.'+[char]10+'<!-- ORIGIN:BEGIN -->'+[char]10+'Implement this exact finite software document result. The Owner has read this original request and retains its same scope and requirements when explaining the complete original work type.'+[char]10+'<!-- ORIGIN:END -->')
 $qa1DecisionPath=Join-Path $operationRuntime 'single-omit-decision.txt'
 WriteText $qa1DecisionPath 'SYNTHETIC SINGLE HUMAN DECISION: supersede the pending QA1 TASK and continue this same original finite result without a card, retaining all quality stages and current independent permission.'
 $qa1Requirements=[pscustomobject]@{path=$qa1Original;identity=(Identity $qa1Original);section='ORIGIN'}
 $qa1Quality=Get-AiwQualitySelection $qa1Policy (Identity (Join-Path $operationTemp '.ai-workspace/process-policy.json')) STANDARD $workSubject
 $qa1Plan=Clone $workPlan;$qa1Plan.qualityBinding=$qa1Quality.qualityBinding
 foreach($stage in $qa1Plan.stages){$stage.requiredBy=Clone $qa1Requirements}
 $qa1Relative='.ai-workspace/tasks/active/QA1-001.md';$qa1Task=Join-Path $operationTemp $qa1Relative
 $qa1Text=$bridgeBase.Replace('BRIDGE-001','QA1-001')+'```aiw-acceptance-plan'+[char]10+($qa1Plan|ConvertTo-Json -Depth 100 -Compress)+[char]10+'```'+[char]10
 WriteText $qa1Task $qa1Text
 $qa1Preimage=Join-Path $operationRuntime 'active-preimage.md';[IO.File]::Copy($qa1Task,$qa1Preimage,$false)
 $qa1Request=Clone $workRequest;$qa1Request.requestRef=[pscustomobject]@{kind='FILE';path=$qa1Original;identity=(Identity $qa1Original)};$qa1Request.requirementsRef=Clone $qa1Requirements;$qa1Request.acceptancePlan=Clone $qa1Plan;$qa1Request|Add-Member userDecisionRef ([pscustomobject]@{kind='FILE';path=$qa1DecisionPath;identity=(Identity $qa1DecisionPath)})
 Check ($qa1Plan.qualityBinding.schemaVersion-eq1-and$null-eq$qa1Plan.qualityBinding.subject.facets.PSObject.Properties['workType']-and$qa1Request.requestRef.identity-cne$qa1Request.userDecisionRef.identity) 'QA1-original-two-axis-plan-and-distinct-original-request-omit-decision-are-real-fixture-inputs'
 $qa1Closure=[pscustomobject]@{userDecisionRef=$qa1Request.userDecisionRef;predecessorTaskRef=[pscustomobject]@{path=$qa1Preimage;identity=(Identity $qa1Preimage)};successorRequest=[pscustomobject]@{requestRef=$qa1Request.requestRef;owner=$qa1Request.owner;subject=$qa1Request.subject;requirementsRef=$qa1Request.requirementsRef};completedActionRefs=@();repairHeads=[pscustomobject]@{selfCheck='NOT_APPLICABLE';review='NOT_APPLICABLE'}}
 $qa1ClosurePath=Join-Path $operationRuntime 'closure-decision.json';Store $qa1ClosurePath $qa1Closure
 $qa1ClosePackage=Clone $operationPackage;$qa1ClosePackage.taskId='QA1-001';$qa1ClosePackage.taskIdentity=Identity $qa1Task;$qa1ClosePackage.actions=@('CONTROL_WRITE');$qa1ClosePackage.exactPaths=@($qa1Relative);$qa1ClosePackage.objectIdentities=@([pscustomobject]@{path=$qa1Relative;identity=$qa1ClosePackage.taskIdentity})
 $qa1CloseAuth=Join-Path $operationRuntime 'close-authorization.json';Store $qa1CloseAuth $qa1ClosePackage
 $qa1Input=Clone $bridgeCloseInput;$qa1Input.taskPath=$qa1Task;$qa1Input.expectedTaskIdentity=$qa1ClosePackage.taskIdentity;$qa1Input.authorizationRef=[pscustomobject]@{path=$qa1CloseAuth;identity=(Identity $qa1CloseAuth)};$qa1Input.exactPaths=@($qa1Relative)
 $qa1Full=BridgeDiscover 'qa1-close-full' $qa1Input
 $qa1Close=BridgeAdmit 'qa1-close-admit' $qa1Full
 function Qa1ClosedText([string]$DecisionPath){$qa1Text.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+[char]10+'- Closure outcome: SUPERSEDED'+[char]10+'- Closure basis: The same pending QA1 result continues with the original complete subject.'+[char]10+'- Output disposition: Retain original request, requirements and quality stages.'+[char]10+'- Git disposition: DEFERRED; isolated fixture only.'+[char]10+'- Unresolved obligations: TRANSFERRED: the unique successor retains all unfinished quality.'+[char]10+'- Writer: RELEASED'+[char]10+'- Reviewer: RELEASED'+[char]10+'- Authorization: RELEASED'+[char]10+'- Closure decision: '+$DecisionPath+'#'+(Identity $DecisionPath)+[char]10+'- Unfinished work: Implement and complete the original exact result and stages.'+[char]10}
 function Qa1FinalBoundary { [pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$qa1Close.run.value.operationRef;preparationReceipts=@($qa1Close.saved.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($qa1Close.saved.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$qa1Relative+'|'+(Identity $qa1Task));deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()} }
 foreach($case in @('old-projection','undeclared-work')){
  $bad=Clone $qa1Closure
  if($case-ceq'old-projection'){$bad.successorRequest.subject.facets.domain.values=@('aiw:media')}else{$bad.successorRequest.subject.facets.workType.values=@('project:unregistered')}
  $badPath=Join-Path $operationRuntime ($case+'-closure.json');Store $badPath $bad
  WriteText $qa1Task (Qa1ClosedText $badPath)
  $badRun=OperationRun ('qa1-close-'+$case) (Qa1FinalBoundary)
  $reason=if($case-ceq'old-projection'){'WORK_PREDECESSOR_SUBJECT_REQUIREMENTS_DRIFT'}else{'FACET_TOKEN_UNDECLARED'}
  Check ($badRun.code-ne0-and$badRun.value.reason.Contains($reason)) ('QA1-real-close-rejects-'+$case+'-at-target-gate')
 }
 WriteText $qa1Task (Qa1ClosedText $qa1ClosurePath)
 $qa1Closed=OperationRun 'qa1-close-final' (Qa1FinalBoundary);OperationPass $qa1Closed 'QA1-real-SUPERSEDED-original-F-keeps-old-binding1-and-valid-original-section'
 $qa1Request|Add-Member predecessorRef ([pscustomobject]@{kind='TASK_SUPERSEDED';closureFinalize=(WorkPair $qa1Closed)})
 # Today's QA2 plan is a separate current selection; the original QA1 stages
 # and binding remain byte-bound through the real closing preimage/F.
 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $workPolicy
 $workQuality=$qa1Saved.quality;$qa1Request.acceptancePlan.qualityBinding=$workQuality.qualityBinding
 $qa1Guard=New-AiwEvidenceContext $operationTemp '' $operationFramework
 # The public reader must forward the caller's section mode; plain refs stay
 # strict, and a section-bearing ref still verifies the original whole bytes.
 Check ((Read-AiwEvidenceReference $qa1Guard $qa1Requirements -Section)-ceq$qa1Original) 'public-evidence-reader-forwards-valid-requirements-section'
 Reject {Read-AiwEvidenceReference $qa1Guard $qa1Requirements} 'EVIDENCE_FIELD_SET' 'public-plain-evidence-ref-still-rejects-section-field'
 $badSection=Clone $qa1Requirements;$badSection.section='MISSING'
 Reject {Read-AiwEvidenceReference $qa1Guard $badSection -Section} 'EVIDENCE_SECTION_UNBOUND' 'public-section-evidence-reader-rejects-absent-section'
 $badSection=Clone $qa1Requirements;$badSection|Add-Member trusted $true
 Reject {Read-AiwEvidenceReference $qa1Guard $badSection -Section} 'EVIDENCE_FIELD_SET' 'public-section-evidence-reader-rejects-undeclared-field'
 Assert-AiwWorkPredecessor $qa1Guard $qa1Request
 $bad=Clone $qa1Request;$bad.subject.facets.workType.values=@('aiw:verification')
 Reject {Assert-AiwWorkPredecessor (New-AiwEvidenceContext $operationTemp '' $operationFramework) $bad} 'WORK_PREDECESSOR_SUCCESSOR_DRIFT' 'QA1-cannot-change-complete-frozen-workType-after-closing'
 $workLocator='request-'+(Get-AiwWorkRequestKey $qa1Request).Split('|')[1].Substring(0,32)
 $workStore=Join-Path $operationTemp ('.ai-workspace/runtime/'+$workLocator+'/owner-fixture');$null=[IO.Directory]::CreateDirectory($workStore)
 $qa1WorkPackage=WorkPackage SOURCE_WRITE $qa1Request
 $qa1WorkPath=Join-Path $workStore 'qa1-current-permission.json';Store $qa1WorkPath $qa1WorkPackage;$qa1WorkRef=[pscustomobject]@{path=$qa1WorkPath;identity=(Identity $qa1WorkPath)}
 $qa1WorkInput=WorkInput $qa1Request SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $qa1WorkRef
 $originBytes=[IO.File]::ReadAllBytes($qa1Original)
 try{WriteText $qa1Original 'A changed original source cannot be rescued by an unchanged successor label.';$badRun=WorkRun 'qa1-original-drift' $qa1WorkInput -Compact}finally{[IO.File]::WriteAllBytes($qa1Original,$originBytes)}
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('EVIDENCE_IDENTITY_DRIFT')) 'QA1-current-public-entry-rejects-changed-original-request-requirements-bytes'
 $qa1Count=@(Get-ChildItem -LiteralPath (Split-Path -Parent $qa1Task) -File).Count
 $qa1WorkFull=WorkDiscover 'qa1-work-source-full' $qa1WorkInput
 $qa1WorkSource=WorkAdmit 'qa1-work-source-admit' (WorkCurrent $qa1WorkFull)
 WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual independently admitted WORK source after the original QA1 safe-point closure.'
 $qa1Written=WorkFinish 'qa1-work-source-F' $qa1WorkSource
 Check ($qa1Written.run.value.actionOutcome-ceq'OBSERVED'-and(Identity $qa1Preimage)-ceq$qa1Closure.predecessorTaskRef.identity-and@(Get-ChildItem -LiteralPath (Split-Path -Parent $qa1Task) -File).Count-eq$qa1Count) 'QA1-real-current-WORK-write-F-preserves-original-preimage-and-zero-new-task-lifecycle'
 $operationRuntime=$qa1Saved.runtime;$workLocator=$qa1Saved.locator;$workStore=$qa1Saved.store;$workQuality=$qa1Saved.quality

 # Original TASK roots reach three distinct real safe points. The common
 # constructor preserves their own bytes/F; no old TASK is reopened or forked.
 $rootSaved=[pscustomobject]@{runtime=$operationRuntime;store=$workStore;locator=$workLocator;quality=$workQuality;probe=$workProbe;marker=$workMarker}
 foreach($rootCase in $RootReviewCases){
  $rootTag='root-'+$rootCase.ToLowerInvariant();$rootTaskId='ROOT-'+$rootCase
  $rootInitialCase=$rootCase-cin@('INITIAL','INITIAL_TEST')
  $rootRepairedCase=$rootCase-cin@('REPAIRED','REPAIRED_TEST')
  $rootTestBeforeReview=$rootCase-cin@('FINDING','TEST_ONLY','INITIAL_TEST')
  $rootPolicy=Clone $workPolicy
  if(-not$rootTestBeforeReview){$rootPolicy.qualityAssurance.defaultStages=@('RESULT_REVIEW','RESULT_ACCEPT')}
  Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $rootPolicy
  $workQuality=Get-AiwQualitySelection $rootPolicy (Identity (Join-Path $operationTemp '.ai-workspace/process-policy.json')) STANDARD $workSubject
  $rootOwnerRuntime=Join-Path $operationTemp ('.ai-workspace/runtime/'+$rootTaskId+'/owner-fixture');$null=[IO.Directory]::CreateDirectory($rootOwnerRuntime)
  $rootOriginal=Join-Path $rootOwnerRuntime 'original-human.txt';WriteText $rootOriginal 'SYNTHETIC ORIGINAL HUMAN: same finite Owner/result; independent reviewer and current permissions remain required. This does not authenticate real human intent.'
  $rootDecision=Join-Path $rootOwnerRuntime 'single-human-omit.txt';WriteText $rootDecision 'SYNTHETIC SINGLE HUMAN DECISION: supersede this finite TASK at the actual completed safe point; retain original stages, SELF and Review budgets, same Owner, subject and requirements.'
  $bridgeRequirements=Join-Path $rootOwnerRuntime 'requirements.md';WriteText $bridgeRequirements ('Exact finite result for '+$rootTaskId+'; real source/typed/F, original reviewer and cumulative limits; fixture semantic roles/host inputs are synthetic.')
  $rootRequired=[pscustomobject]@{path=$bridgeRequirements;identity=(Identity $bridgeRequirements)}
  $rootPlan=Clone $workPlan;$rootPlan.qualityBinding=$workQuality.qualityBinding
  $rootPlan.stages=@($rootPlan.stages|Where-Object{$_.kind-cin$workQuality.effectiveStages});$rootIds=@($rootPlan.stages.id)
  $rootFirstText='Actual original TASK candidate '+$rootCase
  $rootBytes=[Text.UTF8Encoding]::new($false).GetBytes($rootFirstText);$rootExpected=[pscustomobject]@{path='docs/value.md';identity=($rootBytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($rootBytes)))}
  foreach($stage in $rootPlan.stages){$stage.requiredBy=Clone $rootRequired;$stage.dependsOn=@($stage.dependsOn|Where-Object{$_-cin$rootIds});$stage.candidateRef=@(Clone $rootExpected);$stage.evidenceRefs=@();$stage.PSObject.Properties.Remove('evidenceConsumption')}
  $rootBase=$bridgeBase.Replace('BRIDGE-001',$rootTaskId)
  $rootRelative='.ai-workspace/tasks/active/'+$rootTaskId+'.md';$rootTaskPath=Join-Path $operationTemp $rootRelative
  function RootTaskText {$rootBase+'```aiw-acceptance-plan'+[char]10+($rootPlan|ConvertTo-Json -Depth 100 -Compress)+[char]10+'```'+[char]10}
  WriteText $rootTaskPath (RootTaskText)
  $bridgePackage=Clone $operationPackage;$bridgePackage.taskId=$rootTaskId;$bridgePackage.taskIdentity=Identity $rootTaskPath;$bridgePackage.objectIdentities[0].identity=Identity (Join-Path $operationTemp 'docs/value.md')
  $bridgePackage.actions=@('SOURCE_WRITE','REVIEW_ROUTE');$bridgePackage|Add-Member continuationPlan @('SOURCE_WRITE','REVIEW_ROUTE')
  if($rootTestBeforeReview-or$rootCase-ceq'REPAIRED_TEST'){$bridgePackage.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$bridgePackage.continuationPlan=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$bridgePackage|Add-Member selfCheckRepairLimit 1}
  if($rootCase-ceq'TEST_ONLY'){$bridgePackage.actions=@('SOURCE_WRITE','TEST_RUN');$bridgePackage.continuationPlan=@('SOURCE_WRITE','TEST_RUN')}
  $bridgePackage|Add-Member qualityBinding $workQuality.qualityBinding;$bridgePackage|Add-Member repairReviewPlan ([pscustomobject]@{writer='owner-fixture';reviewer=$workReviewerActor;maxCycles=2;materialContributors=@()});$bridgePackage.invalidatesOn+='CONTINUATION_RESULT_DRIFT'
  if($rootCase-ceq'TEST_ONLY'){$bridgePackage.PSObject.Properties.Remove('repairReviewPlan')}
  $rootParentPath=Join-Path $rootOwnerRuntime 'original-root-package.json';Store $rootParentPath $bridgePackage;$rootParentRef=[pscustomobject]@{path=$rootParentPath;identity=(Identity $rootParentPath)}
  function RootActor([string]$Actor){[Environment]::SetEnvironmentVariable('CODEX_THREAD_ID',$Actor,'Process');$script:operationRuntime=Join-Path $operationTemp ('.ai-workspace/runtime/'+$rootTaskId+'/'+$Actor);$script:workStore=$operationRuntime;$null=[IO.Directory]::CreateDirectory($operationRuntime)}
  function RootTaskInput([string]$Action,[string]$Result,$PackageRef,[string]$Actor='owner-fixture',$Continuation=$null){
   $value=Clone $operationInput;$value.taskPath=$rootTaskPath;$value.expectedTaskIdentity=Identity $rootTaskPath;$value.authorizationRef=$PackageRef;$value.observedActor=$Actor
   $value.intentEnvelope.facets.PSObject.Properties.Remove('stage')
   $value.intentEnvelope.requestedActionKind=$Action;$value.intentEnvelope.requestedResultKind=$Result;$value.intentEnvelope.facets.workType.values=@($(if($Action-ceq'REVIEW_EXECUTE'){'aiw:review'}elseif($Action-ceq'TEST_RUN'){'aiw:verification'}else{'aiw:implementation'}))
   if($null-ne$Continuation){$value|Add-Member continuationReceiptPath $Continuation.path;$value|Add-Member expectedContinuationReceiptIdentity $Continuation.identity}
   return $value
  }
  function RootOldFactory([string]$Name,$Binding){
   $path=Join-Path $workStore ($Name+'-factory.json');Store $path ([pscustomobject]@{operation='REPAIR_REVIEW';repositoryRoot=$operationTemp;binding=$Binding})
   $native=WorkCli $Name (Join-Path $operationVersion 'scripts/resolve-workflow-route.ps1') @('-InputPath',$path,'-AsJson');if($native.code-ne0){Write-Host $native.text}
   Check ($native.code-eq0) ($Name+'-actual-TASK-factory-zero')|ForEach-Object{Write-Host $_};$result=$native.text|ConvertFrom-Json -Depth 100
   Check ($result.package.schemaVersion-eq1-and$result.authorityGranted-eq$false) ($Name+'-original-TASK-context-no-authority')|ForEach-Object{Write-Host $_};return $result.package
  }
  function RootWorkFactoryReject([string]$Name,$Binding,$Carrier,[string]$Expected){
   $path=Join-Path $workStore ($Name+'-factory.json');Store $path ([pscustomobject]@{operation='REPAIR_REVIEW';repositoryRoot=$operationTemp;binding=$Binding;currentAuthorizationRef=$Carrier})
   $native=WorkCli $Name (Join-Path $operationVersion 'scripts/resolve-workflow-route.ps1') @('-InputPath',$path,'-AsJson')
   $rejection=$native.text|ConvertFrom-Json -Depth 100
   Check ($native.code-eq2-and$rejection.status-ceq'FAIL'-and$rejection.reason-ceq$Expected) ($Name+'-reaches-target-gate|'+$native.text.Trim())|ForEach-Object{Write-Host $_}
  }
  RootActor owner-fixture
  $rootSourceFull=BridgeDiscover ($rootTag+'-old-source-full') (RootTaskInput SOURCE_WRITE IMPLEMENTATION_RESULT $rootParentRef)
  $rootSource=BridgeAdmit ($rootTag+'-old-source-admit') $rootSourceFull
  WriteText (Join-Path $operationTemp 'docs/value.md') $rootFirstText
  $rootProduction=BridgeFinish ($rootTag+'-old-source-F') $rootSource
  $rootSelf=$null
  if($rootTestBeforeReview){
   $rootTestFull=BridgeDiscover ($rootTag+'-old-test-full') (RootTaskInput TEST_RUN TEST_RESULT $rootParentRef owner-fixture $rootProduction.continuation)
   $rootTest=BridgeAdmit ($rootTag+'-old-test-admit') $rootTestFull;$rootFailure=BridgeSelf ($rootTag+'-old-native-failure')
   $rootRetry=BridgeFinish ($rootTag+'-old-failed-F') $rootTest @($rootFailure) RETEST
   $rootCurrent=Clone $rootTestFull.current;$rootCurrent.continuationReceiptPath=$rootRetry.continuation.path;$rootCurrent.expectedContinuationReceiptIdentity=$rootRetry.continuation.identity
   $rootRetest=BridgeAdmit ($rootTag+'-old-retest-admit') $rootTestFull $rootCurrent
   if($rootCase-ceq'TEST_ONLY'){[IO.File]::Delete((Join-Path $operationRuntime 'transient-marker.txt'))}
   $rootSelf=BridgeSelf ($rootTag+'-old-native-recovery')
   $rootProduction=BridgeFinish ($rootTag+'-old-test-STOP-F') $rootRetest @($rootSelf) STOP
  }
  $rootInitial=[pscustomobject]@{parentPackagePath=$rootParentRef.path;parentPackageIdentity=$rootParentRef.identity;phase='INITIAL_REVIEW';cycle=0;verdictPath='NOT_APPLICABLE';verdictIdentity='NOT_APPLICABLE';repairFinalizeInputPath=$rootProduction.pair.inputRef.path;repairFinalizeInputIdentity=$rootProduction.pair.inputRef.identity;repairFinalizeResultPath=$rootProduction.pair.resultRef.path;repairFinalizeResultIdentity=$rootProduction.pair.resultRef.identity}
  $rootHead=$rootProduction;$rootFinding=$null;$rootBinding=$rootInitial
  if(-not$rootInitialCase-and$rootCase-cne'TEST_ONLY'){
   RootActor $workReviewerActor;$rootOldReview=RootOldFactory ($rootTag+'-old-initial') $rootInitial
   $rootOldReviewPath=Join-Path $workStore 'old-review-package.json';Store $rootOldReviewPath $rootOldReview;$rootOldReviewRef=[pscustomobject]@{path=$rootOldReviewPath;identity=(Identity $rootOldReviewPath)}
   $rootReviewFull=BridgeDiscover ($rootTag+'-old-review-full') (RootTaskInput REVIEW_EXECUTE REVIEW_VERDICT $rootOldReviewRef $workReviewerActor);$rootReview=BridgeAdmit ($rootTag+'-old-review-admit') $rootReviewFull
   $rootFlat=[pscustomobject]@{taskId=$rootTaskId;owner='owner-fixture';reviewer=$workReviewerActor;writer='owner-fixture';cycle=0;verdict=$(if($rootCase-ceq'APPROVED'){'APPROVED'}else{'CHANGES_REQUESTED'});exactPaths=@('docs/value.md');objectIdentities=@($rootExpected);findingPaths=@(if($rootCase-cne'APPROVED'){'docs/value.md'});scopeChanged=$false;decisionChanged=$false}
   $rootFlatPath=Join-Path $workStore 'old-finding-flat.json';Store $rootFlatPath $rootFlat;$rootFlatRef=[pscustomobject]@{path=$rootFlatPath;identity=(Identity $rootFlatPath)}
   $rootTyped=[pscustomobject]@{schemaVersion=1;taskId=$rootTaskId;actor=$workReviewerActor;candidateObjects=@($rootExpected);requirementsRef=$rootRequired;outcome=$(if($rootCase-ceq'APPROVED'){'APPROVED'}else{'CHANGES_REQUESTED'});checks=@([pscustomobject]@{id='synthetic-independent-review';method='MODEL_JUDGMENT';outcome='PASS';reason='Synthetic role and semantic finding; actual original strict validators/F only.';evidenceLocators=@($rootRequired)});evidenceLocators=@($rootRequired,$rootFlatRef);authorizationRef=$rootOldReviewRef}
   $rootTypedPath=Join-Path $workStore 'old-finding-typed.json';Store $rootTypedPath $rootTyped;$rootTypedRef=[pscustomobject]@{kind='REVIEW_VERDICT';path=$rootTypedPath;identity=(Identity $rootTypedPath)}
   $rootDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='owner-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
   $rootEvidence=@();if($null-ne$rootSelf){$rootEvidence+=,$rootSelf};$rootEvidence+=,$rootTypedRef
   $rootFinding=WorkFinish ($rootTag+'-old-finding-F') ([pscustomobject]@{saved=$rootReview.saved;result=$rootReview.run}) $rootEvidence -Delivery $rootDelivery;$rootHead=$rootFinding
   $rootBinding=Clone $rootInitial;$rootBinding.phase='REPAIR';$rootBinding.cycle=1;$rootBinding.verdictPath=$rootFlatRef.path;$rootBinding.verdictIdentity=$rootFlatRef.identity
   foreach($n in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){$rootBinding.$n='NOT_APPLICABLE'}
   $rootBinding|Add-Member verdictFinalizeInputPath $rootFinding.pair.inputRef.path;$rootBinding|Add-Member verdictFinalizeInputIdentity $rootFinding.pair.inputRef.identity;$rootBinding|Add-Member verdictFinalizeResultPath $rootFinding.pair.resultRef.path;$rootBinding|Add-Member verdictFinalizeResultIdentity $rootFinding.pair.resultRef.identity
   if($rootRepairedCase){
    RootActor owner-fixture;$rootOldRepair=RootOldFactory ($rootTag+'-old-repair') $rootBinding;$rootRepairPath=Join-Path $workStore 'old-repair-package.json';Store $rootRepairPath $rootOldRepair;$rootRepairRef=[pscustomobject]@{path=$rootRepairPath;identity=(Identity $rootRepairPath)}
    $rootRepairFull=BridgeDiscover ($rootTag+'-old-repair-full') (RootTaskInput SOURCE_WRITE IMPLEMENTATION_RESULT $rootRepairRef);$rootRepair=BridgeAdmit ($rootTag+'-old-repair-admit') $rootRepairFull
    WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual old TASK repair completed before supersession.';$rootHead=BridgeFinish ($rootTag+'-old-repair-F') $rootRepair
    if($rootCase-ceq'REPAIRED_TEST'){
     $rootRepairTestFull=BridgeDiscover ($rootTag+'-old-repair-test-full') (RootTaskInput TEST_RUN TEST_RESULT $rootRepairRef owner-fixture $rootHead.continuation)
     $rootRepairTest=BridgeAdmit ($rootTag+'-old-repair-test-admit') $rootRepairTestFull
     $rootRepairFailure=BridgeSelf ($rootTag+'-old-repair-native-failure')
     $rootRepairRetry=BridgeFinish ($rootTag+'-old-repair-failed-F') $rootRepairTest @($rootRepairFailure) RETEST
     $rootRepairCurrent=Clone $rootRepairTestFull.current;$rootRepairCurrent.continuationReceiptPath=$rootRepairRetry.continuation.path;$rootRepairCurrent.expectedContinuationReceiptIdentity=$rootRepairRetry.continuation.identity
     $rootRepairRetest=BridgeAdmit ($rootTag+'-old-repair-retest-admit') $rootRepairTestFull $rootRepairCurrent
     $rootSelf=BridgeSelf ($rootTag+'-old-repair-native-recovery')
     $rootHead=BridgeFinish ($rootTag+'-old-repair-test-STOP-F') $rootRepairRetest @($rootSelf) STOP
     $rootProduction=$rootHead
     Check ($rootHead.run.value.actionOutcome-ceq'PASS'-and$rootRepairRetest.saved.operation.binding.continuationStepIndex-eq1) 'R2-old-TASK-repaired-native-test-F-keeps-real-retry-before-supersession'
    }
   }
  }
  RootActor owner-fixture
  if($null-ne$rootSelf-and$rootCase-cne'TEST_ONLY'-and$rootPlan.stages[0].kind-ceq'SELF_CHECK'){$rootPlan.stages[0].evidenceRefs=@($rootSelf);$rootPlan.stages[0]|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($rootProduction.pair)})}
  if($rootCase-ceq'APPROVED'){$reviewStage=@($rootPlan.stages|Where-Object kind -CEQ 'RESULT_REVIEW')[0];$reviewStage.evidenceRefs=@($rootTypedRef);$reviewStage|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($rootHead.pair)})}
  if($rootRepairedCase){foreach($stage in $rootPlan.stages){$stage.candidateRef=@([pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))})}}
  WriteText $rootTaskPath (RootTaskText);$rootBefore=Join-Path $rootOwnerRuntime 'closing-preimage.md';[IO.File]::Copy($rootTaskPath,$rootBefore,$false)
  $rootRequest=Clone $workRequest;$rootRequest.requestRef=[pscustomobject]@{kind='FILE';path=$rootOriginal;identity=(Identity $rootOriginal)};$rootRequest.requirementsRef=Clone $rootRequired;$rootRequest.acceptancePlan=Clone $rootPlan;$rootRequest|Add-Member userDecisionRef ([pscustomobject]@{kind='FILE';path=$rootDecision;identity=(Identity $rootDecision)})
  $rootTails=@($rootHead.pair);if($null-ne$rootSelf-and$rootCase-cne'TEST_ONLY'-and$rootProduction.pair.resultRef.identity-cne$rootHead.pair.resultRef.identity){$rootTails=@($rootProduction.pair,$rootHead.pair)}
  $rootClosure=[pscustomobject]@{userDecisionRef=$rootRequest.userDecisionRef;predecessorTaskRef=[pscustomobject]@{path=$rootBefore;identity=(Identity $rootBefore)};successorRequest=[pscustomobject]@{requestRef=$rootRequest.requestRef;owner=$rootRequest.owner;subject=$rootRequest.subject;requirementsRef=$rootRequest.requirementsRef};completedActionRefs=$rootTails;repairHeads=[pscustomobject]@{selfCheck=$(if($null-ne$rootSelf){$rootProduction.pair}else{'NOT_APPLICABLE'});review=$(if($rootCase-ceq'TEST_ONLY'){'NOT_APPLICABLE'}else{$rootHead.pair})}}
  $rootClosurePath=Join-Path $rootOwnerRuntime 'supersession.json';Store $rootClosurePath $rootClosure
  $rootClosePackage=Clone $operationPackage;$rootClosePackage.taskId=$rootTaskId;$rootClosePackage.taskIdentity=Identity $rootTaskPath;$rootClosePackage.actions=@('CONTROL_WRITE');$rootClosePackage.exactPaths=@($rootRelative);$rootClosePackage.objectIdentities=@([pscustomobject]@{path=$rootRelative;identity=$rootClosePackage.taskIdentity})
  $rootClosePath=Join-Path $rootOwnerRuntime 'close-package.json';Store $rootClosePath $rootClosePackage;$rootCloseRef=[pscustomobject]@{path=$rootClosePath;identity=(Identity $rootClosePath)}
  $rootCloseInput=RootTaskInput CONTROL_WRITE IMPLEMENTATION_RESULT $rootCloseRef;$rootCloseInput.exactPaths=@($rootRelative);$rootCloseInput.intentEnvelope.pathHints=@()
  $rootCloseFull=BridgeDiscover ($rootTag+'-close-full') $rootCloseInput;$rootClose=BridgeAdmit ($rootTag+'-close-admit') $rootCloseFull
  $rootClosed=(RootTaskText).Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+[char]10+'- Closure outcome: SUPERSEDED'+[char]10+'- Closure basis: Same finite result at an actually completed original Review safe point.'+[char]10+'- Output disposition: Retain original candidates and evidence.'+[char]10+'- Git disposition: DEFERRED; isolated fixture.'+[char]10+'- Unresolved obligations: TRANSFERRED: current successor retains all stages and original budgets.'+[char]10+'- Writer: RELEASED'+[char]10+'- Reviewer: RELEASED'+[char]10+'- Authorization: RELEASED'+[char]10+'- Closure decision: '+$rootClosurePath+'#'+(Identity $rootClosurePath)+[char]10+'- Unfinished work: Finish the same finite result under independent current permission.'+[char]10
  WriteText $rootTaskPath $rootClosed
  $rootCloseBoundary=[pscustomobject]@{schemaVersion=4;mode='FINALIZE_OUTPUT';operationRef=$rootClose.run.value.operationRef;preparationReceipts=@($rootClose.saved.operation.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@($rootClose.saved.operation.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$rootRelative+'|'+(Identity $rootTaskPath));deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
  $rootClosedF=OperationRun ($rootTag+'-close-F') $rootCloseBoundary;OperationPass $rootClosedF ($rootTag+'-real-original-SUPERSEDED-F')
  $rootRequest|Add-Member predecessorRef ([pscustomobject]@{kind='TASK_SUPERSEDED';closureFinalize=(WorkPair $rootClosedF)})
  $rootGuard=New-AiwEvidenceContext $operationTemp '' $operationFramework;Assert-AiwWorkPredecessor $rootGuard $rootRequest
  $rootEvidenceOwner=(Get-Command Assert-AiwWorkPredecessor).Module
  $rootFacts=& $rootEvidenceOwner {param($c,$r)Get-EvWorkPredecessor $c $r} $rootGuard $rootRequest
  if($rootCase-ceq'TEST_ONLY'){
   Check ($null-eq$rootFacts.review-and$rootFacts.selfCycle-eq1-and$rootFacts.selfLimit-eq1-and$rootFacts.tails.Count-eq1-and$rootFacts.tails[0].result.actionOutcome-ceq'FAIL') 'old-TASK-real-failed-STOP-head-retains-nonzero-SELF-without-historical-success'
  }elseif($rootCase-ceq'APPROVED'){
   Check ($rootFacts.review.rootRef.identity-ceq$rootParentRef.identity-and$rootFacts.review.state-ceq'APPROVED'-and$rootFacts.review.cycle-eq0) 'old-TASK-real-APPROVED-head-retains-original-review-root-and-stage'
  }else{
  Check ($rootFacts.review.rootRef.identity-ceq$rootParentRef.identity-and$rootFacts.review.cycle-eq$(if($rootRepairedCase){1}else{0})-and$rootFacts.review.state-ceq$(if($rootRepairedCase){'REREVIEW_READY'}elseif($rootInitialCase){'INITIAL_READY'}else{'CHANGES_REQUESTED'})) ($rootTag+'-real-original-head-root-and-cycle')
  }
  if($rootCase-cin@('INITIAL_TEST','REPAIRED_TEST')){
   Check ($rootFacts.selfCycle-eq1-and$rootFacts.selfLimit-eq1-and$rootHead.run.value.actionOutcome-ceq'PASS') ($rootTag+'-R2-original-TASK-test-SELF-and-nonzero-budget-retained')
  }
  $rootReadState=& $rootEvidenceOwner {param($c)Get-EvReadState $c} $rootGuard
  $graphCounts=@($rootReadState.references.Count,$rootReadState.producers.Count,$rootReadState.predecessors.Count)
  $rootAgain=& $rootEvidenceOwner {param($c,$r)Get-EvWorkPredecessor $c $r} $rootGuard $rootRequest
  Check ([object]::ReferenceEquals($rootFacts,$rootAgain)-and($graphCounts-join'|')-ceq(@($rootReadState.references.Count,$rootReadState.producers.Count,$rootReadState.predecessors.Count)-join'|')-and$rootReadState.predecessorReading.Count-eq0) ($rootTag+'-same-call-finite-graph-shares-facts-without-new-reference-members')
  Write-Host ('OBSERVE|'+$rootTag+'-finite-graph|uniqueRefs='+$graphCounts[0]+'|validatedProducers='+$graphCounts[1]+'|predecessors='+$graphCounts[2]+'|scope=CALL_LOCAL_MEMBERS_NOT_PHYSICAL_IO')
  $workLocator='request-'+(Get-AiwWorkRequestKey $rootRequest).Split('|')[1].Substring(0,32)
  function RootWorkActor([string]$Actor){[Environment]::SetEnvironmentVariable('CODEX_THREAD_ID',$Actor,'Process');$script:workStore=Join-Path $operationTemp ('.ai-workspace/runtime/'+$workLocator+'/'+$Actor);$script:operationRuntime=$workStore;$null=[IO.Directory]::CreateDirectory($workStore)}
  $rootTasksBefore=@(Get-ChildItem -LiteralPath (Split-Path -Parent $rootTaskPath) -File).Count
  if($rootCase-ceq'TEST_ONLY'){
   RootWorkActor owner-fixture
   $rootTestRequest=Clone $rootRequest;$rootTestRequest.phase='VERIFY'
   $rootOnlyTest=WorkPackage TEST_RUN $rootTestRequest;$rootOnlyTest|Add-Member selfCheckRepairLimit 1
   $rootOnlyContext=New-AiwPackageEvidenceContext $operationTemp $rootOnlyTest $operationFramework
   Check ((Get-AiwSelfRepairOriginCycle $rootOnlyContext $rootOnlyTest)-eq1) 'pure-current-TEST-retains-real-old-failed-head-cycle-one'
   $bad=Clone $rootOnlyTest;$bad.selfCheckRepairLimit=2
   Reject {Assert-AiwWorkPredecessorPackage (New-AiwEvidenceContext $operationTemp '' $operationFramework) $rootTestRequest $bad} 'WORK_PREDECESSOR_SELF_LIMIT_DRIFT' 'pure-current-TEST-cannot-regrant-old-limit'
   $rootOnlyPath=Join-Path $workStore 'current-single-test-package.json';Store $rootOnlyPath $rootOnlyTest;$rootOnlyRef=[pscustomobject]@{path=$rootOnlyPath;identity=(Identity $rootOnlyPath)}
   $rootOnlyFull=WorkDiscover ($rootTag+'-current-test-full') (WorkInput $rootTestRequest TEST_RUN TEST_RESULT aiw:verification $rootOnlyRef)
   $rootOnlyStep=WorkAdmit ($rootTag+'-current-test-admit') (WorkCurrent $rootOnlyFull)
   $workProbe=Join-Path $workStore 'current-single-test.ps1';WriteText $workProbe 'param([string]$Marker);if([IO.File]::ReadAllText($Marker)-cne"Actual original TASK candidate TEST_ONLY"){exit 7};Write-Output "actual unchanged original candidate tested";exit 0';$workMarker=Join-Path $operationTemp 'docs/value.md'
   $observed=@(WorkNative ($rootTag+'-current-native-zero'));$observed[0..($observed.Count-2)]|Write-Output;$rootOnlyNative=$observed[-1];Check ($rootOnlyNative.code-eq0) 'pure-current-TEST-runs-real-candidate-with-no-current-source-write'
   $rootOnlySelf=WorkRecord ($rootTag+'-current-self') $rootTestRequest SELF_CHECK PASS -Command $rootOnlyNative.command
   $rootOnlyF=WorkFinish ($rootTag+'-current-test-F') $rootOnlyStep @($rootOnlySelf)
   Check ($rootOnlyF.run.value.actionOutcome-ceq'PASS'-and$null-eq$rootOnlyF.run.value.PSObject.Properties['continuationReceipt']-and$null-eq$rootOnlyTest.PSObject.Properties['continuationPlan']-and(Get-AiwSelfRepairOriginCycle $rootOnlyContext $rootOnlyTest)-eq1) 'pure-current-TEST-actual-F-keeps-used-limit-and-grants-no-continuation'
   Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $rootTaskPath) -File).Count-eq$rootTasksBefore-and(Identity $rootBefore)-ceq$rootClosure.predecessorTaskRef.identity) 'pure-current-TEST-keeps-zero-new-task-lifecycle-and-original-preimage'
   continue
  }
  if($rootCase-ceq'APPROVED'){
   RootWorkActor owner-fixture
   $rootAcceptRequest=Clone $rootRequest;$rootAcceptRequest.phase='REVIEW'
   $rootApprovedCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
   $rootAccept=WorkPackage RESULT_ACCEPT $rootAcceptRequest
   $rootAccept|Add-Member acceptanceBinding ([pscustomobject]@{candidateObjects=@($rootApprovedCandidate);requirementsRef=$rootRequired;prerequisiteEvidenceRefs=@($rootTypedRef);reservedUserDecisionRefs=@();prerequisiteConsumption=[pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($rootHead.pair)}})
   $rootAcceptPath=Join-Path $workStore 'current-accept-package.json';Store $rootAcceptPath $rootAccept;$rootAcceptRef=[pscustomobject]@{path=$rootAcceptPath;identity=(Identity $rootAcceptPath)}
   $rootAcceptFull=WorkDiscover ($rootTag+'-current-accept-full') (WorkInput $rootAcceptRequest RESULT_ACCEPT RESULT_ACCEPTANCE aiw:acceptance $rootAcceptRef)
   $rootAcceptStep=WorkAdmit ($rootTag+'-current-accept-admit') (WorkCurrent $rootAcceptFull)
   $rootAccepted=WorkRecord ($rootTag+'-current-acceptance') $rootAcceptRequest RESULT_ACCEPTANCE ACCEPTED $rootAcceptRef
   $rootAcceptedF=WorkFinish ($rootTag+'-current-accept-F') $rootAcceptStep @($rootAccepted)
   Check ($rootAcceptedF.run.value.actionOutcome-ceq'OBSERVED'-and$rootAcceptedF.run.value.consumer.recipient-ceq'USER') 'old-TASK-APPROVED-same-candidate-current-Owner-accepts-original-stage-without-new-review'
   # Isolated changed-candidate setup only, after the real acceptance consumer.
   $approvedBytes=[IO.File]::ReadAllBytes((Join-Path $operationTemp 'docs/value.md'))
   try{
    WriteText (Join-Path $operationTemp 'docs/value.md') 'Changed fixture candidate cannot borrow old TASK approval.'
    $changedCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
    Reject {Read-AiwResultEvidence (New-AiwEvidenceContext $operationTemp '' $operationFramework) $rootTypedRef $rootAcceptRequest @($changedCandidate) $rootRequired -RequireSuccess} 'EVIDENCE_CANDIDATE_DRIFT' 'old-TASK-APPROVED-changed-real-candidate-cannot-borrow-original-typed-PASS'
   }finally{[IO.File]::WriteAllBytes((Join-Path $operationTemp 'docs/value.md'),$approvedBytes)}
   Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $rootTaskPath) -File).Count-eq$rootTasksBefore-and(Identity $rootBefore)-ceq$rootClosure.predecessorTaskRef.identity) 'old-TASK-APPROVED-acceptance-keeps-zero-new-task-lifecycle-and-original-preimage'
   continue
  }
  if($rootCase-ceq'FINDING'){
   RootWorkActor owner-fixture
   $rootRequest.acceptancePlan.stages+=@([pscustomobject]@{id='current-repair-self';kind='SELF_CHECK';requiredBy=(Clone $rootRequired);dependsOn=@($rootPlan.stages[0].id);candidateRef=@();evidenceRefs=@()})
   $rootCarrier=WorkPackage SOURCE_WRITE $rootRequest;$rootCarrier.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$rootCarrier|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$rootCarrier|Add-Member selfCheckRepairLimit 1;$rootCarrier.invalidatesOn+='CONTINUATION_RESULT_DRIFT'
   $rootCarrierPath=Join-Path $workStore 'independent-current-writer.json';Store $rootCarrierPath $rootCarrier;$rootCarrierRef=[pscustomobject]@{path=$rootCarrierPath;identity=(Identity $rootCarrierPath)}
   $rootCurrentRepair=WorkRepairFactory ($rootTag+'-current-repair') $rootBinding $rootCarrierRef
   Check ($rootCurrentRepair.repairReviewBinding.parentPackageIdentity-ceq$rootParentRef.identity-and$rootCurrentRepair.repairReviewBinding.cycle-eq1-and$null-eq$rootCurrentRepair.PSObject.Properties['repairReviewPlan']-and$rootCurrentRepair.requestContext.predecessorRef.closureFinalize.resultRef.identity-ceq$rootRequest.predecessorRef.closureFinalize.resultRef.identity) 'old-TASK-finding-to-current-WORK-repair-preserves-root-c1-and-predecessor'
   $bad=Clone $rootCurrentRepair;$bad.repairReviewBinding.cycle=0
   Reject {Assert-AiwWorkPredecessorPackage (New-AiwEvidenceContext $operationTemp '' $operationFramework) $rootRequest $bad} 'WORK_PREDECESSOR_REVIEW_CYCLE_RESET' 'old-Review-head-cannot-reset-to-cycle-zero'
   $bad=Clone $rootCurrentRepair;$bad.repairReviewBinding.parentPackageIdentity=('1|'+'0'*64)
   Reject {Assert-AiwWorkPredecessorPackage (New-AiwEvidenceContext $operationTemp '' $operationFramework) $rootRequest $bad} 'WORK_PREDECESSOR_REVIEW_ROOT_DRIFT' 'old-Review-head-cannot-substitute-parent-root'
   $rootCurrentPath=Join-Path $workStore 'current-repair-package.json';Store $rootCurrentPath $rootCurrentRepair;$rootCurrentRef=[pscustomobject]@{path=$rootCurrentPath;identity=(Identity $rootCurrentPath)}
   $rootCurrentFull=WorkDiscover ($rootTag+'-current-repair-full') (WorkInput $rootRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $rootCurrentRef);$rootCurrentStep=WorkAdmit ($rootTag+'-current-repair-admit') (WorkCurrent $rootCurrentFull)
   WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual current WORK repair of the original TASK finding.';$rootCurrentWritten=WorkFinish ($rootTag+'-current-repair-F') $rootCurrentStep
   Check ($rootCurrentWritten.run.value.continuationReceipt.selfRepairCycle-eq1-and$rootCurrentWritten.run.value.continuationReceipt.completedStepIndex-eq0) 'old-TASK-Review-root-current-repair-real-source-F-retains-nonzero-SELF'
   $rootVerification=Clone $rootRequest;$rootVerification.phase='VERIFY';$rootNewCandidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
   @($rootVerification.acceptancePlan.stages|Where-Object id -CEQ 'current-repair-self')[0].candidateRef=@($rootNewCandidate)
   foreach($stage in @($rootVerification.acceptancePlan.stages|Where-Object kind -CEQ 'RESULT_REVIEW')){$stage.candidateRef=@($rootNewCandidate)}
   $rootCurrentTestFull=WorkDiscover ($rootTag+'-current-test-full') (WorkInput $rootVerification TEST_RUN TEST_RESULT aiw:verification $rootCurrentRef $rootCurrentWritten.continuation);$rootCurrentTest=WorkAdmit ($rootTag+'-current-test-admit') (WorkCurrent $rootCurrentTestFull)
   $workProbe=Join-Path $workStore 'root-repair-check.ps1';WriteText $workProbe 'param([string]$Marker);if([IO.File]::ReadAllText($Marker)-cne"Actual current WORK repair of the original TASK finding."){exit 7};Write-Output "actual repaired candidate verified";exit 0';$workMarker=Join-Path $operationTemp 'docs/value.md'
   $observed=@(WorkNative ($rootTag+'-current-native-zero'));$observed[0..($observed.Count-2)]|Write-Output;$rootNative=$observed[-1];Check ($rootNative.code-eq0) 'old-Review-root-current-repair-test-reaches-actual-native-candidate-check'
   $rootNewSelf=WorkRecord ($rootTag+'-current-self') $rootVerification SELF_CHECK PASS -Command $rootNative.command
   $rootCurrentPassed=WorkFinish ($rootTag+'-current-test-F') $rootCurrentTest @($rootNewSelf) STOP
   Check ($rootCurrentPassed.run.value.actionOutcome-ceq'PASS') 'old-Review-root-current-test-original-F-passes-with-original-SELF-used-one'
   $rootRequest=Clone $rootVerification;$rootRequest.phase='IMPLEMENT'
   $newStage=@($rootRequest.acceptancePlan.stages|Where-Object id -CEQ 'current-repair-self')[0];$newStage.evidenceRefs=@($rootNewSelf);$newStage|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($rootCurrentPassed.pair)})
   $rootBinding.phase='REREVIEW';$rootBinding.repairFinalizeInputPath=$rootCurrentPassed.pair.inputRef.path;$rootBinding.repairFinalizeInputIdentity=$rootCurrentPassed.pair.inputRef.identity;$rootBinding.repairFinalizeResultPath=$rootCurrentPassed.pair.resultRef.path;$rootBinding.repairFinalizeResultIdentity=$rootCurrentPassed.pair.resultRef.identity
  }elseif($rootRepairedCase){
   $rootBinding.phase='REREVIEW';$rootBinding.repairFinalizeInputPath=$rootHead.pair.inputRef.path;$rootBinding.repairFinalizeInputIdentity=$rootHead.pair.inputRef.identity;$rootBinding.repairFinalizeResultPath=$rootHead.pair.resultRef.path;$rootBinding.repairFinalizeResultIdentity=$rootHead.pair.resultRef.identity
  }
  $rootReviewRequest=Clone $rootRequest;$rootReviewRequest.actor=$workReviewerActor;$rootReviewRequest.role='REVIEWER';$rootReviewRequest.phase='REVIEW';$rootReviewRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient='owner-fixture'}
  RootWorkActor $workReviewerActor
  $rootReviewCarrier=WorkPackage REVIEW_EXECUTE $rootReviewRequest;$rootReviewCarrier.reviewIndependence='INDEPENDENT';$rootReviewCarrier|Add-Member candidateWriter 'owner-fixture';$rootReviewCarrier|Add-Member materialContributors @();$rootReviewCarrier.invalidatesOn+='CONTRIBUTOR_SET_CHANGE'
  $rootReviewCarrierPath=Join-Path $workStore 'independent-current-reviewer.json';Store $rootReviewCarrierPath $rootReviewCarrier;$rootReviewCarrierRef=[pscustomobject]@{path=$rootReviewCarrierPath;identity=(Identity $rootReviewCarrierPath)}
  if($rootRepairedCase){
   # The old parent grants this subject, but it cannot supply current scope or actor rights.
   $bad=Clone $rootReviewCarrier;$bad.exactPaths=@('docs/not-currently-authorized.md');$bad.objectIdentities=@([pscustomobject]@{path='docs/not-currently-authorized.md';identity='NEW'})
   $badPath=Join-Path $workStore 'current-review-scope-missing.json';Store $badPath $bad
   RootWorkFactoryReject ($rootTag+'-current-scope') $rootBinding ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)}) 'REPAIR_REVIEW_CURRENT_AUTHORIZATION_SCOPE'
   $bad=Clone $rootReviewCarrier;$bad.grantee='another-independent-reviewer';$bad.requestContext.actor=$bad.grantee
   $badPath=Join-Path $workStore 'current-review-actor-drift.json';Store $badPath $bad
   RootWorkFactoryReject ($rootTag+'-current-actor') $rootBinding ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)}) 'REPAIR_REVIEW_CURRENT_AUTHORIZATION_ACTOR'
  }elseif($rootInitialCase){
   $bad=Clone $rootBinding;$bad.repairFinalizeResultPath=Join-Path $workStore 'future-production-F-does-not-exist.json';$bad.repairFinalizeResultIdentity=('1|'+'0'*64)
   RootWorkFactoryReject ($rootTag+'-future-original-F') $bad $rootReviewCarrierRef 'EVIDENCE_OBJECT_MISSING'
  }
  $rootCurrentReview=WorkRepairFactory ($rootTag+'-current-review-factory') $rootBinding $rootReviewCarrierRef
  Check ($rootCurrentReview.repairReviewBinding.parentPackageIdentity-ceq$rootParentRef.identity-and$rootCurrentReview.repairReviewBinding.cycle-eq$(if($rootInitialCase){0}else{1})-and$rootCurrentReview.repairReviewBinding.phase-ceq$(if($rootInitialCase){'INITIAL_REVIEW'}else{'REREVIEW'})) ($rootTag+'-current-review-keeps-actual-root-and-cycle')
  if($rootRepairedCase){
   $bad=Clone $rootCurrentReview;$bad.repairReviewBinding.cycle=3
   Reject {Assert-AiwWorkPredecessorPackage (New-AiwEvidenceContext $operationTemp '' $operationFramework) $rootReviewRequest $bad} 'WORK_PREDECESSOR_REVIEW_CYCLE_RESET' 'old-Review-max-two-rejects-cycle-three-with-original-valid-head'
   $bad=Clone $rootReviewCarrier;$bad.projectConfigIdentity=('1|'+'0'*64);$badPath=Join-Path $workStore 'current-review-stale-config.json';Store $badPath $bad
   $badPrepared=WorkRepairFactory ($rootTag+'-current-config-factory') $rootBinding ([pscustomobject]@{path=$badPath;identity=(Identity $badPath)})
   Check ($badPrepared.projectConfigIdentity-ceq$bad.projectConfigIdentity) 'old-TASK-root-cannot-replace-current-carrier-config-in-PREPARED-package'
   $badPreparedPath=Join-Path $workStore 'current-review-stale-config-prepared.json';Store $badPreparedPath $badPrepared
   $badRun=WorkRun ($rootTag+'-current-config-checker') (WorkInput $rootReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review ([pscustomobject]@{path=$badPreparedPath;identity=(Identity $badPreparedPath)})) -Compact
   Check ($badRun.code-ne0-and$badRun.value.reason.Contains('PROJECT_CONFIG_DRIFT')) 'current-public-checker-rejects-stale-current-config-despite-valid-original-TASK-root'
  }
  $rootCurrentReviewPath=Join-Path $workStore 'current-review-package.json';Store $rootCurrentReviewPath $rootCurrentReview;$rootCurrentReviewRef=[pscustomobject]@{path=$rootCurrentReviewPath;identity=(Identity $rootCurrentReviewPath)}
  $rootCurrentReviewFull=WorkDiscover ($rootTag+'-current-review-full') (WorkInput $rootReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review $rootCurrentReviewRef);$rootCurrentReviewStep=WorkAdmit ($rootTag+'-current-review-admit') (WorkCurrent $rootCurrentReviewFull)
  $rootNewVerdict=WorkRecord ($rootTag+'-current-verdict') $rootReviewRequest REVIEW_VERDICT $(if($rootCase-ceq'FINDING'){'CHANGES_REQUESTED'}else{'APPROVED'}) $rootCurrentReviewRef
  $rootCurrentReviewEvidence=@($rootNewVerdict);if($rootCase-ceq'FINDING'){$rootCurrentReviewEvidence=@($rootNewSelf,$rootNewVerdict)}
  if($rootCase-cin@('INITIAL_TEST','REPAIRED_TEST')){
   if(@($rootReviewRequest.acceptancePlan.stages|Where-Object kind -CEQ 'SELF_CHECK').Count){$rootCurrentReviewEvidence=@($rootSelf,$rootNewVerdict)}
   else{
    # The original TEST SELF remains in its successful F, not an unselected stage.
    Check ($rootCase-ceq'REPAIRED_TEST'-and$null-ne$rootSelf-and$rootFacts.selfCycle-eq1-and$rootFacts.selfLimit-eq1-and$rootHead.run.value.actionOutcome-ceq'PASS') 'R2-original-TEST-SELF-retained-without-unselected-stage-resubmission'
   }
  }
  $rootCurrentDelivery=[pscustomobject]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='owner-fixture';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
  $rootCurrentReviewed=WorkFinish ($rootTag+'-current-review-F') $rootCurrentReviewStep $rootCurrentReviewEvidence -Delivery $rootCurrentDelivery
  Check $rootCurrentReviewed.run.value.delivery.delivered ($rootTag+'-actual-typed3-and-original-review-F-consumed-by-owner')
  if($rootCase-cin@('INITIAL_TEST','REPAIRED_TEST')){
   Check ($rootCurrentReviewed.run.value.delivery.delivered-and$rootCurrentReviewed.run.value.consumer.recipient-ceq'owner-fixture'-and$rootCurrentReview.repairReviewBinding.cycle-eq$(if($rootInitialCase){0}else{1})) ($rootTag+'-R2-old-TASK-TEST-to-current-WORK-review-actual-D-A-typed-F')
  }
  if($rootCase-ceq'FINDING'){
   $rootNextBinding=Clone $rootBinding;$rootNextBinding.phase='REPAIR';$rootNextBinding.cycle=2
   $rootNextFlat=Join-Path $workStore ($rootTag+'-current-verdict-flat.json');$rootNextBinding.verdictPath=$rootNextFlat;$rootNextBinding.verdictIdentity=Identity $rootNextFlat
   foreach($n in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){$rootNextBinding.$n='NOT_APPLICABLE'}
   $rootNextBinding.verdictFinalizeInputPath=$rootCurrentReviewed.pair.inputRef.path;$rootNextBinding.verdictFinalizeInputIdentity=$rootCurrentReviewed.pair.inputRef.identity;$rootNextBinding.verdictFinalizeResultPath=$rootCurrentReviewed.pair.resultRef.path;$rootNextBinding.verdictFinalizeResultIdentity=$rootCurrentReviewed.pair.resultRef.identity
   RootWorkActor owner-fixture
   $rootNextCarrier=WorkPackage SOURCE_WRITE $rootRequest;$rootNextCarrier.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$rootNextCarrier|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$rootNextCarrier|Add-Member selfCheckRepairLimit 1;$rootNextCarrier.invalidatesOn+='CONTINUATION_RESULT_DRIFT'
   $rootNextCarrierPath=Join-Path $workStore 'independent-next-writer.json';Store $rootNextCarrierPath $rootNextCarrier;$rootNextCarrierRef=[pscustomobject]@{path=$rootNextCarrierPath;identity=(Identity $rootNextCarrierPath)}
   $rootNextRepair=WorkRepairFactory ($rootTag+'-next-repair-factory') $rootNextBinding $rootNextCarrierRef
   Check ($rootNextRepair.repairReviewBinding.parentPackageIdentity-ceq$rootParentRef.identity-and$rootNextRepair.repairReviewBinding.cycle-eq2) 'later-WORK-finding-still-derives-original-TASK-root-and-next-review-cycle'
   $rootNextPath=Join-Path $workStore 'next-repair-package.json';Store $rootNextPath $rootNextRepair;$rootNextRef=[pscustomobject]@{path=$rootNextPath;identity=(Identity $rootNextPath)}
   $rootNextFull=WorkDiscover ($rootTag+'-next-repair-full') (WorkInput $rootRequest SOURCE_WRITE IMPLEMENTATION_RESULT aiw:implementation $rootNextRef);$rootNextStep=WorkAdmit ($rootTag+'-next-repair-admit') (WorkCurrent $rootNextFull)
   WriteText (Join-Path $operationTemp 'docs/value.md') 'Actual second WORK repair continues the same original TASK root.';$rootNextWritten=WorkFinish ($rootTag+'-next-repair-F') $rootNextStep
   Check ($rootNextWritten.run.value.continuationReceipt.selfRepairCycle-eq1-and$rootNextRepair.repairReviewBinding.cycle-eq2-and$rootNextStep.saved.operation.binding.authorizationIdentity-ceq$rootNextRef.identity) 'later-WORK-finding-real-source-F-keeps-SELF-one-and-review-two'
   $rootC2Request=Clone $rootRequest;$rootC2Request.phase='VERIFY';$rootC2Candidate=[pscustomobject]@{path='docs/value.md';identity=(Identity (Join-Path $operationTemp 'docs/value.md'))}
   $rootC2Stage=@($rootC2Request.acceptancePlan.stages|Where-Object id -CEQ 'current-repair-self')[0];$rootC2Stage.candidateRef=@($rootC2Candidate);$rootC2Stage.evidenceRefs=@();$rootC2Stage.PSObject.Properties.Remove('evidenceConsumption')
   foreach($stage in @($rootC2Request.acceptancePlan.stages|Where-Object kind -CEQ 'RESULT_REVIEW')){$stage.candidateRef=@($rootC2Candidate)}
   $rootC2TestFull=WorkDiscover ($rootTag+'-c2-test-full') (WorkInput $rootC2Request TEST_RUN TEST_RESULT aiw:verification $rootNextRef $rootNextWritten.continuation);$rootC2Test=WorkAdmit ($rootTag+'-c2-test-admit') (WorkCurrent $rootC2TestFull)
   $workProbe=Join-Path $workStore 'root-c2-check.ps1';WriteText $workProbe 'param([string]$Marker);if([IO.File]::ReadAllText($Marker)-cne"Actual second WORK repair continues the same original TASK root."){exit 7};Write-Output "actual c2 candidate checked";exit 0';$workMarker=Join-Path $operationTemp 'docs/value.md'
   $observed=@(WorkNative ($rootTag+'-c2-native-zero'));$observed[0..($observed.Count-2)]|Write-Output;$rootC2Native=$observed[-1];Check ($rootC2Native.code-eq0) 'original-Review-c2-actual-repair-candidate-native-zero'
   $rootC2Self=WorkRecord ($rootTag+'-c2-self') $rootC2Request SELF_CHECK PASS -Command $rootC2Native.command;$rootC2Passed=WorkFinish ($rootTag+'-c2-test-F') $rootC2Test @($rootC2Self) STOP
   $rootC2Request.phase='IMPLEMENT';$rootC2Stage.evidenceRefs=@($rootC2Self);$rootC2Stage|Add-Member evidenceConsumption ([pscustomobject]@{purpose='HISTORICAL_SUCCESS';originalFinalize=@($rootC2Passed.pair)})
   $rootC2Binding=Clone $rootNextBinding;$rootC2Binding.phase='REREVIEW';$rootC2Binding.repairFinalizeInputPath=$rootC2Passed.pair.inputRef.path;$rootC2Binding.repairFinalizeInputIdentity=$rootC2Passed.pair.inputRef.identity;$rootC2Binding.repairFinalizeResultPath=$rootC2Passed.pair.resultRef.path;$rootC2Binding.repairFinalizeResultIdentity=$rootC2Passed.pair.resultRef.identity
   $rootC2ReviewRequest=Clone $rootC2Request;$rootC2ReviewRequest.actor=$workReviewerActor;$rootC2ReviewRequest.role='REVIEWER';$rootC2ReviewRequest.phase='REVIEW';$rootC2ReviewRequest.resultConsumer=[pscustomobject]@{channel='TASK_MESSAGE';recipient='owner-fixture'};RootWorkActor $workReviewerActor
   $rootC2Carrier=WorkPackage REVIEW_EXECUTE $rootC2ReviewRequest;$rootC2Carrier.reviewIndependence='INDEPENDENT';$rootC2Carrier|Add-Member candidateWriter 'owner-fixture';$rootC2Carrier|Add-Member materialContributors @();$rootC2Carrier.invalidatesOn+='CONTRIBUTOR_SET_CHANGE';$rootC2CarrierPath=Join-Path $workStore 'c2-current-reviewer.json';Store $rootC2CarrierPath $rootC2Carrier
   $rootC2Review=WorkRepairFactory ($rootTag+'-c2-review-factory') $rootC2Binding ([pscustomobject]@{path=$rootC2CarrierPath;identity=(Identity $rootC2CarrierPath)});$rootC2ReviewPath=Join-Path $workStore 'c2-review-package.json';Store $rootC2ReviewPath $rootC2Review;$rootC2ReviewRef=[pscustomobject]@{path=$rootC2ReviewPath;identity=(Identity $rootC2ReviewPath)}
   $rootC2ReviewFull=WorkDiscover ($rootTag+'-c2-review-full') (WorkInput $rootC2ReviewRequest REVIEW_EXECUTE REVIEW_VERDICT aiw:review $rootC2ReviewRef);$rootC2ReviewStep=WorkAdmit ($rootTag+'-c2-review-admit') (WorkCurrent $rootC2ReviewFull)
   $rootC2Verdict=WorkRecord ($rootTag+'-c2-verdict') $rootC2ReviewRequest REVIEW_VERDICT CHANGES_REQUESTED $rootC2ReviewRef;$rootC2Reviewed=WorkFinish ($rootTag+'-c2-review-F') $rootC2ReviewStep @($rootC2Self,$rootC2Verdict) -Delivery $rootCurrentDelivery
   $rootC3Binding=Clone $rootC2Binding;$rootC3Binding.phase='REPAIR';$rootC3Binding.cycle=3;$rootC3Binding.verdictPath=Join-Path $workStore ($rootTag+'-c2-verdict-flat.json');$rootC3Binding.verdictIdentity=Identity $rootC3Binding.verdictPath
   foreach($n in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){$rootC3Binding.$n='NOT_APPLICABLE'}
   $rootC3Binding.verdictFinalizeInputPath=$rootC2Reviewed.pair.inputRef.path;$rootC3Binding.verdictFinalizeInputIdentity=$rootC2Reviewed.pair.inputRef.identity;$rootC3Binding.verdictFinalizeResultPath=$rootC2Reviewed.pair.resultRef.path;$rootC3Binding.verdictFinalizeResultIdentity=$rootC2Reviewed.pair.resultRef.identity
   RootWorkActor owner-fixture;$rootC3Carrier=WorkPackage SOURCE_WRITE $rootC2Request;$rootC3Carrier.actions=@('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$rootC3Carrier|Add-Member continuationPlan @('SOURCE_WRITE','TEST_RUN','REVIEW_ROUTE');$rootC3Carrier|Add-Member selfCheckRepairLimit 1;$rootC3Carrier.invalidatesOn+='CONTINUATION_RESULT_DRIFT';$rootC3Path=Join-Path $workStore 'c3-current-writer.json';Store $rootC3Path $rootC3Carrier
   RootWorkFactoryReject ($rootTag+'-actual-c2-head-rejects-c3') $rootC3Binding ([pscustomobject]@{path=$rootC3Path;identity=(Identity $rootC3Path)}) 'WORK_PREDECESSOR_REVIEW_CYCLE_RESET'

  }
  Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $rootTaskPath) -File).Count-eq$rootTasksBefore-and(Identity $rootBefore)-ceq$rootClosure.predecessorTaskRef.identity) ($rootTag+'-WORK-keeps-zero-new-task-lifecycle-and-original-preimage')
  if($rootRepairedCase){
   # Fixture location setup only: preserve the real closed bytes and F, without
   # claiming this setup is an authorized production archive operation.
   $rootArchive=Join-Path $operationTemp ('.ai-workspace/tasks/archive/'+$rootTaskId+'.md')
   $archiveFull=[IO.Path]::GetFullPath($rootArchive);$fixturePrefix=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($operationTemp))+[IO.Path]::DirectorySeparatorChar
   if(-not$archiveFull.StartsWith($fixturePrefix,[StringComparison]::OrdinalIgnoreCase)-or[IO.File]::Exists($rootArchive)){throw 'ROOT_ARCHIVE_FIXTURE_SCOPE'}
   $closedIdentity=Identity $rootTaskPath;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $rootArchive));[IO.File]::Copy($rootTaskPath,$rootArchive,$false)
   if((Identity $rootArchive)-cne$closedIdentity-or(Identity $rootTaskPath)-cne$closedIdentity){throw 'ROOT_ARCHIVE_FIXTURE_BYTE_DRIFT'}
   [IO.File]::Delete($rootTaskPath)
   Check (-not[IO.File]::Exists($rootTaskPath)-and(Identity $rootArchive)-ceq$closedIdentity) 'old-Review-CLOSED-fixture-moves-to-exact-archive-with-original-bytes'
   Assert-AiwWorkPredecessor (New-AiwEvidenceContext $operationTemp '' $operationFramework) $rootReviewRequest
   Check $true 'old-Review-archived-original-graph-read-by-fresh-predecessor-context'
   $archivePrepared=WorkRepairFactory ($rootTag+'-archived-current-review-factory') $rootBinding $rootReviewCarrierRef
   Check ($archivePrepared.repairReviewBinding.parentPackageIdentity-ceq$rootParentRef.identity-and$archivePrepared.repairReviewBinding.cycle-eq1) 'old-Review-cold-factory-consumes-archived-TASK-with-original-root-and-cycle'
  }

 }
 $operationRuntime=$rootSaved.runtime;$workStore=$rootSaved.store;$workLocator=$rootSaved.locator;$workQuality=$rootSaved.quality;$workProbe=$rootSaved.probe;$workMarker=$rootSaved.marker


 Store (Join-Path $operationTemp '.ai-workspace/process-policy.json') $operationPolicy

 WriteText $operationTaskPath ($operationTaskText.Replace('owner-fixture','another-owner'))
 $badRun=OperationRun 'changed-owner' $noneObserve
 Check ($badRun.code-ne0-and$badRun.value.reason.Contains('NONE_CURRENT_TASK_BINDING_DRIFT')) 'ordinary-progress-exception-rejects-real-owner-or-route-change'
}finally{
 [Environment]::SetEnvironmentVariable('CODEX_THREAD_ID',$operationOldActor,'Process')
 RemoveTestRoot $operationTemp
}


Write-Output ('PASS|facets-selection|assertions='+$passed)
