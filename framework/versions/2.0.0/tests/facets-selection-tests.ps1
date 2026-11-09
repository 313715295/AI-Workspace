[CmdletBinding()]param()
. (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly
$composer=Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force -PassThru
Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionState.psm1') -Force
$catalog=Get-Content -LiteralPath (Join-Path $versionRoot 'PROCESS_REQUIREMENTS.json') -Raw|ConvertFrom-Json -Depth 100
$native=Get-AiwFacetVocabulary -NativeVocabulary $catalog.facetVocabulary
function Facets([string]$Work='aiw:implementation',[string]$Stage='aiw:implementation'){
 [pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=@('aiw:software')};workType=[pscustomobject]@{state='KNOWN';values=@($Work)};deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:code')};stage=[pscustomobject]@{state='KNOWN';values=@($Stage)}}
}
function Selector($Facets){[pscustomobject]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@('review','upgrade');facets=$Facets}}
function Match($Selector,$Facets,[string]$Action='SOURCE_WRITE',[string]$Profile='STANDARD',[string]$Role='EXECUTOR',[string]$Phase='IMPLEMENT',[string[]]$Paths=@('src/current.js'),[string[]]$Capabilities=@()){
 & $composer {param($s,$f,$a,$p,$r,$h,$paths,$caps) Test-AiwRuleMatch $s $p $r $h $a 'IMPLEMENTATION_RESULT' $paths $caps 'review upgrade mapping do-not-write after-confirmation' $false $f} $Selector $Facets $Action $Profile $Role $Phase $Paths $Capabilities
}
$intent=ConvertTo-AiwIntentFacets (Facets) $native
Check ($catalog.schemaVersion-eq3-and$catalog.catalogVersion-ceq'4'-and$catalog.requirements.Count-eq40) 'same-40-native-rules-new-metadata-contract'
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
$handoff=BodyPlan NONE HANDOFF
Check ($finalId-cin@($handoff.obligations.requirementId)-and$deliveryId-cin@($handoff.obligations.requirementId)-and@($handoff.plan.ruleIds|Where-Object{$_-cnotin$production.plan.ruleIds}).Count-eq0) 'loaded-delivery-reenters-operation-without-new-body'
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
$bad=Clone $body;$bad.facets|Add-Member deliverableType @('aiw:code')
Reject {& $composer {param($value)Assert-AiwBodySelectorContract $value 'BODY_TEST'} $bad} 'BODY_TEST_FACET_DIMENSION' 'body-selector-rejects-deliverable-axis'
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
Write-Output ('PASS|facets-selection|assertions='+$passed)
