[CmdletBinding()]param([switch]$KeepFixture,[switch]$FixtureContractOnly)
. (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly -KeepFixture:$KeepFixture
Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
Import-Module (Join-Path $versionRoot 'scripts/KnowledgeSources.psm1') -Force
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-w3-snapshot-'+[guid]::NewGuid().ToString('N'))
$callNumber=0
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1') -Force
function Assert-ResolverSuccess($Run,[string]$Name){$status=if($null-ne$Run.Value-and$null-ne$Run.Value.PSObject.Properties['status']){[string]$Run.Value.status}else{'UNPARSED'};$reason=if($null-ne$Run.Value-and$null-ne$Run.Value.PSObject.Properties['reason']){[string]$Run.Value.reason}else{'NOT_REPORTED'};if($Run.Code-ne0-or$status-cnotin@('PASS','EVALUATION_ONLY')){Write-Output ('DIAG|'+$Name+'|code='+$Run.Code+'|status='+$status+'|reason='+$reason+'|text='+$Run.Text);throw ('RESOLVER_STEP_FAILED|'+$Name+'|code='+$Run.Code+'|status='+$status+'|reason='+$reason)}}
function W3Facet([string[]]$Values){[pscustomobject]@{state='KNOWN';values=$Values}}
function W3Intent {
 [pscustomobject]@{schemaVersion=2;objective='Discuss the current bounded plan; review and upgrade are future examples.';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('future review','do not upgrade');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=[pscustomobject]@{domain=(W3Facet @('aiw:governance'));workType=(W3Facet @('aiw:planning'));deliverableType=(W3Facet @('aiw:plan'));stage=(W3Facet @('aiw:planning'))}}
}
function W3Selector([string]$Stage='aiw:planning'){
 [pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@('NONE');resultKinds=@('PLAN');pathPrefixes=@();capabilities=@();semanticTerms=@('upgrade');facets=[pscustomobject]@{stage=@($Stage)}}
}
function W3Binding([string]$Id,[string]$Root,[string[]]$Files){[pscustomobject]@{id=$Id;provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$Root};allowedPaths=@($Files|ForEach-Object{[pscustomobject]@{kind='FILE';locator=$_}});decisionLocator='fixture:explicit-source-permission'}}
function W3Document([string]$Id,[string]$Binding,[string]$Locator,[string]$Path,[string[]]$Dependencies=@()){
 [pscustomobject]@{sourceId=$Id;bindingId=$Binding;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=$Locator;identity=(Identity $Path);mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=$Dependencies}
}
function W3Descriptor([string]$Id,[object[]]$Documents,[object[]]$Bindings){
 foreach($document in $Documents){$document.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) $Bindings}
 $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$Documents[0].bindingId;itemId=$Id;revision=(Get-AiwContentRevision ([pscustomobject]@{documents=$Documents}) $Bindings);itemIdentity='';rootSourceId=$Documents[0].sourceId;documents=$Documents}
 $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor;return $descriptor
}
function W3Rule([string]$Id,$Descriptor,[string]$Stage='aiw:planning'){
 [pscustomobject]@{ruleId=$Id;requirementReason='Actual source closure fixture';source=$Descriptor;selectors=(W3Selector $Stage);preparationRequirements=@('P_'+$Id);resultRequirements=@('R_'+$Id);decisionLocator='fixture:explicit-rule-adoption'}
}

function W3Invoke($InputObject){
 $script:callNumber++;$inputPath=Join-Path $temp ('call-'+$callNumber+'.json');Store $inputPath $InputObject
 $raw=@(& pwsh -NoProfile -NonInteractive -File $resolver -InputPath $inputPath -AsJson 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
 $text=$raw-join"`n";WriteText (Join-Path $temp ('call-'+$callNumber+'-output.json')) ($text+"`n")
 $value=try{$text|ConvertFrom-Json -Depth 100}catch{$null}
 return [pscustomobject]@{Code=$code;Text=$text;Value=$value}
}
function W3Discover {
 param($Intent=(W3Intent))
 W3Invoke ([pscustomobject]@{schemaVersion=5;ruleLoad=[pscustomobject]@{mode='FULL'};mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=[pscustomobject]@{sessionId='w3-observer';requestId='snapshot-plan';role='EXECUTOR';phase='PLAN';profile='STANDARD'};projectRoot=$project;frameworkRoot=$fixtureRoot;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=(Identity $configPath);expectedCorrectionsIdentity=(Identity $correctionsPath);expectedTaskIdentity='NOT_APPLICABLE';observedActor='w3-observer';capabilities=@();exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$Intent;evaluationOnly=$false})
}
function W3Boundary($Discover,[string]$Mode='ADMIT_ACTION'){
 Assert-ResolverSuccess $Discover 'boundary-source-discover';$receiptPath=Join-Path $temp 'original-compact.json';Store $receiptPath $Discover.Value.compactReceipt
 $prep=@($Discover.Value.compactReceipt.selectedObligations.preparationRequirements|Select-Object -Unique)
 [string[]]$results=@()
 if($Mode-ceq'FINALIZE_OUTPUT'){$results=@($Discover.Value.compactReceipt.selectedObligations.resultRequirements|Select-Object -Unique)}
 W3Invoke ([pscustomobject]@{schemaVersion=3;mode=$Mode;discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Identity $receiptPath);preparationReceipts=$prep;resultReceipts=$results;deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE';evidenceRefs=@()})
}
function W3RejectOld($Discover,[string]$Name){
 foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){$run=W3Boundary $Discover $mode;Check ($run.Code-ne0-and$run.Value.reason-clike'DISCOVER_SOURCE_DRIFT*') ($Name+'-'+$mode+'|'+$run.Text)}
}
try{
 # The existing finite runtime constructor excludes historical Qpre attachments.
 # Its synthetic qualification is not Source Review, release or project adoption.
 $fixtureDefinition=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-groups.json') -Raw|ConvertFrom-Json -Depth 100
 $fixtureRoot=Join-Path $temp 'isolated-framework'
 $fixtureVersion=New-AiwTestRuntimeFixture -SourceRoot $sourceRoot -DestinationRoot $fixtureRoot -VersionPaths @($fixtureDefinition.mechanismVersionPaths)
 $resolver=Join-Path $fixtureVersion 'scripts/resolve-process-requirements.ps1'
 $project=Join-Path $temp 'project';$configuration=NewTestProject $project
 $configPath=Join-Path $project '.ai-workspace/project.json';$policyPath=Join-Path $project '.ai-workspace/process-policy.json';$correctionsPath=Join-Path $project '.ai-workspace/corrections.json'
 WriteText (Join-Path $project '.ai-workspace/BOOTSTRAP.md') "<!-- FRAMEWORK-MANAGED:BEGIN -->`nFixture entry.`n<!-- FRAMEWORK-MANAGED:END -->`n<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
 $alpha=Join-Path $temp 'alpha';$beta=Join-Path $temp 'beta';$gamma=Join-Path $temp 'gamma'
 WriteText (Join-Path $alpha 'A.md') 'A current root obligation.';WriteText (Join-Path $beta 'B.md') 'B current dependency obligation.';WriteText (Join-Path $gamma 'C.md') 'C current base obligation.'
 $configuration.sourceBindings=@((W3Binding alpha $alpha @('A.md')),(W3Binding beta $beta @('B.md')),(W3Binding gamma $gamma @('C.md')))
 $descriptor=W3Descriptor FIRST @((W3Document A alpha 'A.md' (Join-Path $alpha 'A.md') @('B')),(W3Document B beta 'B.md' (Join-Path $beta 'B.md') @('C')),(W3Document C gamma 'C.md' (Join-Path $gamma 'C.md'))) $configuration.sourceBindings
 $second=Clone $descriptor;$second.itemId='SECOND';$second.itemIdentity=Get-AiwContentItemIdentity $second
 $policy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';rules=@((W3Rule FIRST $descriptor),(W3Rule SECOND $second 'aiw:review'))}
 Store $configPath $configuration;Store $policyPath $policy
 $discover=W3Discover;Assert-ResolverSuccess $discover 'discover'
 if($discover.Code-ne0){Write-Output ('DIAG|public-DISCOVER4|'+$discover.Text)}
 Check ($discover.Code-eq0-and$discover.Value.status-ceq'PASS'-and$discover.Value.compactReceipt.schemaVersion-eq4-and$discover.Value.compactReceipt.inputContractVersion-eq5) 'actual-public-DISCOVER5-compact4'
 $selected=@($discover.Value.selectedRuleBlocks|Where-Object{$_.requirementId-ceq'project:fixture:FIRST'})
 Check ($selected.Count-eq1-and$selected[0].fullText-clike'*C current base obligation*B current dependency obligation*A current root obligation*') 'actual-cross-binding-complete-C-B-A-fulltext'
 Check (@($discover.Value.selectedRuleBlocks|Where-Object{$_.requirementId-ceq'project:fixture:SECOND'}).Count-eq0) 'known-stage-excludes-second-rule-with-same-physical-chain'
 $trace=@($discover.Value.readTrace);$bodies=@($trace|Where-Object event -CEQ SOURCE_BODY_READ)
 Check (($bodies[0..2].sourceId-join',')-ceq'C,B,A') 'actual-read-trace-preserves-dependency-postorder'
 $global=@($trace|Where-Object event -CEQ GLOBAL_DECLARATIONS_VALIDATED)[0].sequence;$selection=@($trace|Where-Object event -CEQ SELECTION_STARTED)[0].sequence;$verified=@($trace|Where-Object event -CEQ SELECTED_CLOSURE_VERIFIED)[0].sequence;$nativeReads=@($trace|Where-Object event -CEQ NATIVE_MODULE_READ)
 Check ($global-lt$selection-and$selection-lt$bodies[0].sequence-and$bodies[-1].sequence-lt$verified-and$nativeReads[0].sequence-gt$verified-and$bodies.Count-eq3) 'global-declarations-then-same-selection-then-selected-complete-closure-before-native-render'
 Check ('SOURCE_VALIDATION_SELECTED_CLOSURE_V1'-cin$discover.Value.compactReceipt.evidence.ceilings) 'receipt-explicitly-binds-selected-closure-validation-ceiling'
 foreach($field in @('contentSnapshotIdentity','effectiveSetIdentity','implementationIdentity')){Check ($discover.Value.compactReceipt.sourceBindings.$field-cmatch'^\d+\|[A-F0-9]{64}$') ('compact-binds-'+$field)}
 $admitted=W3Boundary $discover;Assert-ResolverSuccess $admitted 'cold-admit';if($admitted.Code-ne0){Write-Output ('DIAG|public-ADMIT3|'+$admitted.Text)};Check ($admitted.Code-eq0) 'actual-public-ADMIT3-consumes-exact-snapshot'
 $finalized=W3Boundary $discover FINALIZE_OUTPUT;Assert-ResolverSuccess $finalized 'cold-finalize';if($finalized.Code-ne0){Write-Output ('DIAG|public-FINALIZE3|'+$finalized.Text)};Check ($finalized.Code-eq0) 'actual-public-FINALIZE3-consumes-same-snapshot'
 # An old full-set receipt cannot silently acquire the new scoped meaning.
 $unmarked=Clone $discover
 $unmarked.Value.compactReceipt.evidence.ceilings=@($unmarked.Value.compactReceipt.evidence.ceilings|Where-Object{$_-cne'SOURCE_VALIDATION_SELECTED_CLOSURE_V1'})
 foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
  $oldScope=W3Boundary $unmarked $mode
  Check ($oldScope.Code-ne0-and$oldScope.Value.reason-clike'SOURCE_VALIDATION_SCOPE_UNBOUND|FRESH_DISCOVER_REQUIRED*') ('unmarked-historical-receipt-requires-fresh-discover-'+$mode+'|'+$oldScope.Text)
 }
 if($FixtureContractOnly){Write-Output ('PARTIAL|FIXTURE_CONTRACT_ONLY|source-snapshot-boundary|target=cold-discover-admit-finalize|code='+$finalized.Code+'|status='+$finalized.Value.status+'|reason='+$finalized.Value.reason);return}
 # A prior complete observation is not evidence for another boundary, even if
 # a source keeps its path, length and filesystem timestamp.
 $samePath=Join-Path $gamma 'C.md';$sameBytes=[IO.File]::ReadAllBytes($samePath);$sameTime=[IO.File]::GetLastWriteTimeUtc($samePath)
 try{
  [IO.File]::WriteAllText($samePath,'Z current base obligation.',$utf8);[IO.File]::SetLastWriteTimeUtc($samePath,$sameTime)
  Check (([IO.File]::ReadAllBytes($samePath)).Length-eq$sameBytes.Length-and[IO.File]::GetLastWriteTimeUtc($samePath)-eq$sameTime) 'same-path-length-time-counterexample-reaches-original-boundary'
  foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
   $changedBytes=W3Boundary $discover $mode
   Check ($changedBytes.Code-ne0-and$changedBytes.Value.reason-ceq'CONTENT_IDENTITY_DRIFT|DOCUMENT') ('current-source-bytes-rechecked-after-prior-full-observation-'+$mode+'|'+$changedBytes.Text)
  }
 }finally{[IO.File]::WriteAllBytes($samePath,$sameBytes);[IO.File]::SetLastWriteTimeUtc($samePath,$sameTime)}
 $reobserved=W3Discover;Assert-ResolverSuccess $reobserved 'fresh-complete-source-after-rejection'
 $reselected=@($reobserved.Value.selectedRuleBlocks|Where-Object requirementId -CEQ 'project:fixture:FIRST')
 Check ($reselected.Count-eq1-and$reselected[0].fullText-ceq$selected[0].fullText-and$reobserved.Value.compactReceipt.sourceBindings.effectiveSetIdentity-ceq$discover.Value.compactReceipt.sourceBindings.effectiveSetIdentity-and(W3Boundary $reobserved).Code-eq0) 'independent-boundary-rebuilds-complete-current-source-after-failure'
 $basePolicy=Clone $policy;$baseConfig=Clone $configuration
 $policy.rules[0].selectors.facets.stage=@('aiw:review');Store $policyPath $policy;W3RejectOld $discover 'selector-only-drift';$policy=Clone $basePolicy;Store $policyPath $policy
 $policy.rules[1].resultRequirements=@('CHANGED_UNSELECTED_OBLIGATION');Store $policyPath $policy;W3RejectOld $discover 'unselected-obligation-only-drift';$policy=Clone $basePolicy;Store $policyPath $policy
 $policy.rules[0].source.documents[0].dependencies=@('C','B');$policy.rules[0].source.revision=Get-AiwContentRevision $policy.rules[0].source $configuration.sourceBindings;$policy.rules[0].source.itemIdentity=Get-AiwContentItemIdentity $policy.rules[0].source;Store $policyPath $policy;W3RejectOld $discover 'ordered-dependency-descriptor-drift';$policy=Clone $basePolicy;Store $policyPath $policy
 $configuration.sourceBindings[0].decisionLocator='fixture:reconfirmed-different-permission';Store $configPath $configuration;W3RejectOld $discover 'source-permission-decision-drift';$configuration=Clone $baseConfig;Store $configPath $configuration
 # This unregistered synthetic fixture takes the full qualification path.
 # First prove actual changed code bytes invalidate that qualification. Then
 # restore valid synthetic qualification and obtain a fresh real public
 # snapshot. The unchanged original snapshot must reject this actual runtime
 # change at both boundaries; the new genuine snapshot must succeed at both.
 $implementationPath=Join-Path $fixtureVersion 'scripts/ContentSources.psm1'
 $implementationBytes=[IO.File]::ReadAllBytes($implementationPath)
 $fixtureManifestPath=Join-Path $fixtureVersion 'RELEASE_MANIFEST.json';$fixtureManifestBytes=[IO.File]::ReadAllBytes($fixtureManifestPath)
 try{
  [IO.File]::AppendAllText($implementationPath,"`n# Isolated implementation drift fixture.`n",$utf8)
  foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
   $invalidQualification=W3Boundary $discover $mode
   Check ($invalidQualification.Code-ne0-and$invalidQualification.Value.reason-ceq'RELEASE_VALIDATION_STATE_UNSUPPORTED') ('actual-implementation-byte-drift-invalidates-full-fixture-qualification-'+$mode)
  }
  Set-AiwTestFixtureQualification $fixtureVersion
  $changedImplementation=W3Discover;Assert-ResolverSuccess $changedImplementation 'changed-code-with-valid-synthetic-qualification'
  Check ($changedImplementation.Value.compactReceipt.sourceBindings.implementationIdentity-cne$discover.Value.compactReceipt.sourceBindings.implementationIdentity) 'actual-changed-code-produces-a-different-implementation-binding'
  # Both receipts are unchanged results of real public DISCOVER. Current code
  # and its synthetic qualification changed together; no binding is forged.
  foreach($mode in @('ADMIT_ACTION','FINALIZE_OUTPUT')){
   $implementationGate=W3Boundary $discover $mode
   Check ($implementationGate.Code-ne0-and$implementationGate.Value.reason-clike'DISCOVER_SOURCE_DRIFT|*') ('actual-qualified-runtime-change-rejects-old-public-snapshot-'+$mode+'|'+$implementationGate.Text)
   $currentImplementation=W3Boundary $changedImplementation $mode
   Assert-ResolverSuccess $currentImplementation ('current-qualified-public-snapshot-'+$mode)
   Check ($currentImplementation.Code-eq0-and$currentImplementation.Value.status-ceq'PASS') ('current-qualified-public-snapshot-succeeds-'+$mode)
  }
 }finally{[IO.File]::WriteAllBytes($implementationPath,$implementationBytes);[IO.File]::WriteAllBytes($fixtureManifestPath,$fixtureManifestBytes)}
 $correction=[pscustomobject]@{correctionId='HISTORY';introducedAgainstFramework='2.0.0';requirementReason='Lifecycle snapshot fixture';effectiveRule='A paused project increment.';applicability='Fixture';decisionLocator='fixture:historical-decision';selectors=(W3Selector);preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@();lifecycle=[pscustomobject]@{state='PAUSED';installation='NOT_APPLICABLE';decisionLocator='fixture:pause'}}
 $carrier=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';corrections=@($correction)};Store $correctionsPath $carrier;$history=W3Discover;Assert-ResolverSuccess $history 'history';Check ($history.Code-eq0) 'paused-history-is-a-valid-current-source';$carrier.corrections[0].lifecycle.state='UNINSTALLED';Store $correctionsPath $carrier;W3RejectOld $history 'lifecycle-only-drift';Store $correctionsPath ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';corrections=@()})
 # All fixed source bytes were cached by the first query. Move only a checked
 # fixture directory; the missing physical source must retain a marked ceiling.
 $offline=[IO.Path]::GetFullPath((Join-Path $temp 'gamma-offline'));$live=[IO.Path]::GetFullPath($gamma);$fixtureBase=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp))+[IO.Path]::DirectorySeparatorChar
 if(-not$live.StartsWith($fixtureBase,[StringComparison]::OrdinalIgnoreCase)-or-not$offline.StartsWith($fixtureBase,[StringComparison]::OrdinalIgnoreCase)){throw 'FIXTURE_MOVE_SCOPE'}
 [IO.Directory]::Move($live,$offline);$cached=W3Discover;Assert-ResolverSuccess $cached 'cached';Check ($cached.Code-eq0-and'PINNED_CACHE_SOURCE'-cin$cached.Value.compactReceipt.evidence.ceilings) 'selected-pinned-dependency-offline-uses-exact-cache-with-explicit-ceiling';Check ((W3Boundary $cached).Code-eq0) 'offline-fixed-snapshot-is-valid-at-next-boundary';[IO.Directory]::Move($offline,$live)
 $missingRoot=Join-Path $temp 'missing';WriteText (Join-Path $missingRoot 'D.md') 'Unselected, uncached required source.';$configuration.sourceBindings+=W3Binding missing $missingRoot @('D.md');$missing=W3Descriptor MISSING @((W3Document D missing 'D.md' (Join-Path $missingRoot 'D.md'))) $configuration.sourceBindings;$policy.rules+=W3Rule MISSING $missing 'aiw:review';Store $configPath $configuration;Store $policyPath $policy
 $missingOffline=[IO.Path]::GetFullPath((Join-Path $temp 'missing-offline'));$missingLive=[IO.Path]::GetFullPath($missingRoot);if(-not$missingLive.StartsWith($fixtureBase,[StringComparison]::OrdinalIgnoreCase)-or-not$missingOffline.StartsWith($fixtureBase,[StringComparison]::OrdinalIgnoreCase)){throw 'FIXTURE_MOVE_SCOPE'};[IO.Directory]::Move($missingLive,$missingOffline)
 # An independent unselected body has never been observed or cached.
 # Keeping its directory offline makes an erroneous full read observable.
 $unselected=W3Discover;Assert-ResolverSuccess $unselected 'unselected-independent-offline'
 Check (@($unselected.Value.readTrace|Where-Object event -CEQ SOURCE_BODY_READ).Count-eq3-and@($unselected.Value.selectedRuleBlocks|Where-Object requirementId -CEQ 'project:fixture:MISSING').Count-eq0) 'unselected-uncached-independent-source-is-not-opened-or-certified'
 $emptyIntent=W3Intent;$emptyIntent.facets.stage.values=@('aiw:closure')
 $empty=W3Discover $emptyIntent;Assert-ResolverSuccess $empty 'zero-project-selection'
 Check (@($empty.Value.readTrace|Where-Object event -CEQ SOURCE_BODY_READ).Count-eq0-and@($empty.Value.selectedRuleBlocks|Where-Object{$_.requirementId.StartsWith('project:')}).Count-eq0) 'zero-selection-does-not-expand-to-full-adopted-library'
 $withMissing=Clone $policy
 try{
  # UNKNOWN remains conservative inside the otherwise known boundaries.
  $policy.rules=@($policy.rules|Where-Object ruleId -CNE SECOND);Store $policyPath $policy
  $unknownIntent=W3Intent;$unknownIntent.facets.stage=[pscustomobject]@{state='UNKNOWN';values=@()}
  $unknown=W3Discover $unknownIntent
  Check ($unknown.Code-ne0-and$unknown.Value.reason-clike'*EFFECTIVE_SET_UNPROVEN*') ('unknown-stage-includes-relevant-missing-closure|'+$unknown.Text)
  # The real complete-target composition entry still validates unselected
  # members; this is not a lightweight observation supplied as full facts.
  Import-Module (Join-Path $fixtureVersion 'scripts/ProcessRequirementComposition.psm1') -Force
  $completeFailure=''
  try{$null=Invoke-ProcessRequirementComposition -ProjectRoot $project -FrameworkRoot $fixtureRoot -TargetVersion 2.0.0 -ExpectedProjectConfigIdentity (Identity $configPath) -ExpectedCorrectionsIdentity (Identity $correctionsPath) -Profile STANDARD -Role EXECUTOR -Phase PLAN -Actor w3-observer -TaskIdentity NOT_APPLICABLE -ActionKind NONE -ResultKind PLAN -IntentEnvelope (W3Intent) -EvaluationOnly -ValidateCompleteAdoptedSet}catch{$completeFailure=$_.Exception.Message}
  Check ($completeFailure-clike'*EFFECTIVE_SET_UNPROVEN*') ('complete-target-validation-rejects-unselected-missing-body|'+$completeFailure)
  $policy=Clone $withMissing;$policy.rules[-1].selectors.facets.stage=@('aiw:unregistered-stage');Store $policyPath $policy
  $badGlobal=W3Discover
  Check ($badGlobal.Code-ne0-and$badGlobal.Value.reason-cmatch'FACET|SELECTOR|VOCABULARY') ('unselected-invalid-global-selector-still-rejected|'+$badGlobal.Text)
 }finally{$policy=Clone $withMissing;Store $policyPath $policy;[IO.Directory]::Move($missingOffline,$missingLive)}
 # Restoring a body does not re-adopt later damaged bytes. Ordinary selection
 # still succeeds without claiming that member healthy; full validation fails.
 WriteText (Join-Path $missingRoot 'D.md') 'Changed independently, still unselected.'
 $unrelatedDrift=W3Discover;Assert-ResolverSuccess $unrelatedDrift 'unselected-body-drift'
 Check (@($unrelatedDrift.Value.selectedRuleBlocks|Where-Object requirementId -CEQ 'project:fixture:FIRST')[0].fullText-ceq$selected[0].fullText) 'unselected-body-drift-preserves-selected-complete-meaning'
 $configuration=Clone $baseConfig;$policy=Clone $basePolicy;$configuration.sourceBindings=@($configuration.sourceBindings|Where-Object id -CNE gamma);Store $configPath $configuration;Store $policyPath $policy;$unadopted=W3Discover;Check ($unadopted.Code-ne0-and$unadopted.Value.reason-clike'*DEPENDENCY_NOT_ADOPTED*') ('unadopted-cross-binding-dependency-rejected|'+$unadopted.Text)
 $configuration=Clone $baseConfig;$configuration.sourceBindings[2].allowedPaths=@([pscustomobject]@{kind='FILE';locator='another.md'});Store $configPath $configuration;$revoked=W3Discover;Check ($revoked.Code-ne0-and$revoked.Value.reason-clike'*SOURCE_DENIED*') ('permission-revocation-rejects-existing-cache|'+$revoked.Text)
 $configuration=Clone $baseConfig;Store $configPath $configuration;Store $policyPath ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';rules=@()})
 $library=Join-Path $temp 'library';$entries=@()
 foreach($id in @('SOFTWARE','KNOWLEDGE','LEGACY')){
  WriteText (Join-Path $library ($id+'.md')) ('Actual method fulltext '+$id)
  [string[]]$tags=if($id-ceq'SOFTWARE'){@('domain:aiw:software','workType:aiw:planning')}elseif($id-ceq'KNOWLEDGE'){@('domain:aiw:knowledge')}else{@('ordinary-old-tag')}
  $entries+=[pscustomobject]@{id=$id;kind='METHOD';state='CURRENT';title=$id;summary='Isolated method fixture';tags=$tags;locator=($id+'.md');identity=(Identity (Join-Path $library ($id+'.md')));verifiedAt='2026-09-30T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','CONTENT_VERSION_CHANGE');tokenEstimate=10;originalSources=@([pscustomobject]@{title='Fixture';url='https://example.invalid/method';accessedAt='2026-09-30T00:00:00Z';licenseNotice='Synthetic fixture; never fetched'});applicability=@('fixture');contentVersion='fixture-1';maintenance=[pscustomobject]@{owner='fixture';locator='README.md'}}
 }
 $indexPath=Join-Path $library 'index.json';$index=[pscustomobject]@{schemaVersion=3;libraryId='fixture-methods';entries=$entries};Store $indexPath $index
 $configuration.sourceBindings+=W3Binding library $library @('index.json','SOFTWARE.md','KNOWLEDGE.md','LEGACY.md')
 $configuration.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@([pscustomobject]@{id='methods';bindingId='library';indexLocator='index.json';selectionHints=@('fixture');updatePolicy='FOLLOW';revisionSelector='index.json'})}};Store $configPath $configuration
 $query=[pscustomobject]@{domain=(W3Facet @('aiw:software'));workType=[pscustomobject]@{state='UNKNOWN';values=@()};deliverableType=[pscustomobject]@{state='NOT_APPLICABLE';values=@()};stage=[pscustomobject]@{state='UNKNOWN';values=@()}};$queryJson=$query|ConvertTo-Json -Depth 10 -Compress
 $q=Invoke-AiwKnowledgeQuery $project (Identity $configPath) -Operation QUERY -SourceId methods -FacetQueryJson $queryJson
 Check (($q.entries.id-join',')-ceq'methods:SOFTWARE,methods:LEGACY') 'facet-query-selects-known-intersection-and-conservatively-retains-old-tags'
 Check ($q.contentMode-ceq'LOCATOR_ONLY'-and-not($q.entries|ConvertTo-Json -Depth 20).Contains('fullText')) 'facet-query-default-remains-locator-only'
 Check ($q.readTrace.Count-eq1-and@($q.entries.indexIdentity|Select-Object -Unique).Count-eq1-and$q.entries[0].indexIdentity-ceq(Identity $indexPath)) 'single-query-opens-one-fixed-index-for-all-entries'
 $full=Invoke-AiwKnowledgeQuery $project (Identity $configPath) -Operation QUERY -SourceId methods -EntryId methods:SOFTWARE -FacetQueryJson $queryJson -ContentMode FULLTEXT
 Check ($full.entries.Count-eq1-and$full.entries[0].fullText-ceq'Actual method fulltext SOFTWARE') 'explicit-source-entry-and-fulltext-read-actual-fixed-body'
 Reject {Invoke-AiwKnowledgeQuery $project (Identity $configPath) -Operation QUERY -FacetQueryJson $queryJson} 'KNOWLEDGE_FACET_QUERY_EXPLICIT_SOURCES_REQUIRED' 'facets-never-open-all-sources'
 Reject {Invoke-AiwKnowledgeQuery $project (Identity $configPath) -Operation QUERY -SourceId methods -EntryId other:SOFTWARE -FacetQueryJson $queryJson} 'KNOWLEDGE_FACET_ENTRY_OUTSIDE_SOURCE_SCOPE' 'entry-cannot-expand-explicit-source-range'
 Reject {Invoke-AiwKnowledgeQuery $project (Identity $configPath) -SourceId methods -FacetQueryJson $queryJson} 'KNOWLEDGE_FACET_QUERY_EXPLICIT_SOURCES_REQUIRED' 'facets-are-not-an-implicit-discovery-action'
 Reject {Invoke-AiwKnowledgeQuery $project (Identity $configPath) -Operation QUERY -SourceId methods -EntryId methods:SOFTWARE} 'KNOWLEDGE_QUERY_QUALIFIED_IDS_REQUIRED' 'nonfacet-explicit-query-parameter-exclusion-preserved'
 $oldIndexIdentity=$q.entries[0].indexIdentity;$index.entries[0].tags=@('domain:aiw:knowledge');Store $indexPath $index
 $fresh=Invoke-AiwKnowledgeQuery $project (Identity $configPath) -Operation QUERY -SourceId methods -FacetQueryJson $queryJson
 Check ($fresh.entries.Count-eq1-and$fresh.entries[0].id-ceq'methods:LEGACY'-and$fresh.entries[0].indexIdentity-cne$oldIndexIdentity-and$q.entries[0].indexIdentity-ceq$oldIndexIdentity) 'next-follow-query-gets-new-snapshot-without-rewriting-prior-query'
 Write-Output ('PASS|source-snapshot-boundary|assertions='+$passed+'|fixture='+$temp)
}finally{if($KeepFixture){Write-Output ('FIXTURE|'+$temp)}else{RemoveTestRoot $temp}}
