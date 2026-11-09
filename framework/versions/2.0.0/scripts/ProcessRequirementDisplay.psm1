Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:DisplayUtf8=[Text.UTF8Encoding]::new($false,$true)
function Get-DisplayIdentity([string]$Text){
 $bytes=$script:DisplayUtf8.GetBytes($Text)
 $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}
function Assert-DisplayStrings($Value){
 if($Value-isnot[Array]){throw 'DISPLAY_ARRAY_REQUIRED'}
 foreach($item in $Value){if($item-isnot[string]-or[string]::IsNullOrWhiteSpace($item)){throw 'DISPLAY_STRING_REQUIRED'}}
}
function Get-AiwProcessDisplay {
 [CmdletBinding()]param([Parameter(Mandatory)]$Result)
 if($Result-isnot[pscustomobject]-or$null-eq$Result.PSObject.Properties['status']-or$Result.status-isnot[string]){throw 'DISPLAY_RESOLVER_RESULT_REQUIRED'}
 $lf=[string][char]10;$sections=[Collections.Generic.List[object]]::new();$blocks=[Collections.Generic.List[object]]::new();$rules=[Collections.Generic.List[object]]::new();$bodyOnlyRules=[Collections.Generic.List[object]]::new()
 $obligations=[Collections.Generic.List[object]]::new();$mode=if($null-ne$Result.PSObject.Properties['mode']){$Result.mode}else{'NOT_AVAILABLE'};$reuse='FULL';$ceilings=@()
 if($Result.status-cin@('PASS','EVALUATION_ONLY')-and$mode-ceq'DISCOVER'){
  if($Result.resultType-cne'PROCESS_REQUIREMENTS_DISCOVER_RESULT'-or$Result.selectedRuleBlocks-isnot[Array]-or($Result.compactReceipt-isnot[pscustomobject]-and$Result.compactReceipt-isnot[Collections.IDictionary])){throw 'DISPLAY_DISCOVER_RESULT_REQUIRED'}
  $receipt=$Result.compactReceipt
  if($receipt.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or$receipt.status-cne$Result.status-or$receipt.selectedObligations-isnot[Array]){throw 'DISPLAY_RECEIPT_MISMATCH'}
  $expected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
  foreach($o in $receipt.selectedObligations){
   if($expected.ContainsKey($o.requirementId)){throw 'DISPLAY_REQUIREMENT_DUPLICATE'}
   Assert-DisplayStrings $o.preparationRequirements;Assert-DisplayStrings $o.resultRequirements;$expected.Add($o.requirementId,$o)
  }
  $bodyRules=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
  foreach($rule in $Result.selectedRuleBlocks){
   if($bodyRules.ContainsKey($rule.requirementId)){throw 'DISPLAY_REQUIREMENT_DUPLICATE'}
   foreach($axis in @('preparationRequirements','resultRequirements')){
    Assert-DisplayStrings $rule.$axis
    $values=@(if($expected.ContainsKey($rule.requirementId)){$expected[$rule.requirementId].$axis})
    if((ConvertTo-Json -InputObject @($rule.$axis) -Compress)-cne(ConvertTo-Json -InputObject $values -Compress)){throw 'DISPLAY_OBLIGATION_MISMATCH'}
   }
   if($rule.fullText-isnot[string]-or[string]::IsNullOrWhiteSpace($rule.fullText)-or$rule.displayParts-isnot[Array]-or$rule.displayParts.Count-eq0){throw 'DISPLAY_COMPLETE_BODY_REQUIRED'}
   if([string]::Join($lf+$lf,@($rule.displayParts.fullText))-cne$rule.fullText){throw 'DISPLAY_PARTS_BODY_MISMATCH'}
   $bodyRules.Add($rule.requirementId,$rule)
  }
  foreach($id in $expected.Keys){if(-not$bodyRules.ContainsKey($id)){throw 'DISPLAY_SELECTED_BODY_MISSING'}}
  $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$dedup=[Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
  if($receipt.schemaVersion-eq4){
   if($Result.modelView-isnot[pscustomobject]-or$Result.modelView.uniqueUnits-isnot[Array]-or$Result.modelView.currentRules-isnot[Array]){throw 'DISPLAY_MODEL_VIEW_REQUIRED'}
   $reuse=$receipt.loadDecision.effectiveMode
   if($reuse-cne'FULL'-or@($receipt.loadDecision.reusedUnitKeys).Count-or@($receipt.loadDecision.anticipatedUnitKeys).Count){throw 'DISPLAY_COMPLETE_LOAD_REQUIRED'}
   $covered=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
   foreach($u in $receipt.bodyCoverage.units){
    if($covered.ContainsKey($u.unitKey)){throw 'DISPLAY_UNIT_DUPLICATE'};$covered.Add($u.unitKey,$u)
    $id=$blocks.Count+1;$dedup.Add($u.unitKey,$id)
    $blocks.Add([pscustomobject]@{id=$id;unitKey=$u.unitKey;source=$u.sourceKind;sourceLocator=$u.sourceLocator;normativeIdentity=$u.normativeIdentity;textIdentity=$u.textIdentity})
   }
   $returned=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$unitTexts=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
   foreach($u in $Result.modelView.uniqueUnits){
    if(-not$covered.ContainsKey($u.unitKey)-or-not$returned.Add($u.unitKey)-or(Get-DisplayIdentity $u.fullText)-cne$covered[$u.unitKey].textIdentity){throw 'DISPLAY_COMPLETE_BODY_REQUIRED'}
    $unitTexts.Add($u.unitKey,$u.fullText)
    $sections.Add([pscustomobject]@{id=$dedup[$u.unitKey];kind='RULE';identity=$u.textIdentity;fullText=$u.fullText})
   }
   if([string]::Join('|',@($returned))-cne[string]::Join('|',@($receipt.loadDecision.returnedUnitKeys))){throw 'DISPLAY_RETURNED_UNIT_SET'}
   if($returned.Count-ne$covered.Count){throw 'DISPLAY_COMPLETE_BODY_REQUIRED'}
   $coveredRules=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
   foreach($rule in $receipt.bodyCoverage.rules){
    if(-not$coveredRules.Add($rule.requirementId)-or-not$bodyRules.ContainsKey($rule.requirementId)){throw 'DISPLAY_SELECTION_MISMATCH'}
    Assert-DisplayStrings $rule.orderedUnitKeys
    $texts=@(foreach($key in $rule.orderedUnitKeys){if(-not$unitTexts.ContainsKey($key)){throw 'DISPLAY_RULE_UNIT_MISSING'};$unitTexts[$key]})
    if(-not$texts.Count-or[string]::Join($lf+$lf,$texts)-cne$bodyRules[$rule.requirementId].fullText){throw 'DISPLAY_COMPLETE_BODY_REQUIRED'}
    if(-not$expected.ContainsKey($rule.requirementId)){
     $bodyOnlyRules.Add([pscustomobject]@{requirementId=$rule.requirementId;blockIds=@($rule.orderedUnitKeys|ForEach-Object{$dedup[$_]});semanticApplicability=$bodyRules[$rule.requirementId].semanticApplicability})
    }
   }
   if($coveredRules.Count-ne$bodyRules.Count){throw 'DISPLAY_SELECTED_BODY_MISSING'}
   foreach($rule in $Result.modelView.currentRules){
    if(-not$seen.Add($rule.requirementId)-or-not$expected.ContainsKey($rule.requirementId)){throw 'DISPLAY_SELECTION_MISMATCH'}
    foreach($axis in @('preparationRequirements','resultRequirements')){if(($rule.$axis|ConvertTo-Json -Compress)-cne($expected[$rule.requirementId].$axis|ConvertTo-Json -Compress)){throw 'DISPLAY_OBLIGATION_MISMATCH'}}
    $coverageRule=@($receipt.bodyCoverage.rules|Where-Object requirementId -CEQ $rule.requirementId)
    if($coverageRule.Count-ne1-or($coverageRule[0].orderedUnitKeys|ConvertTo-Json -Compress)-cne($rule.orderedUnitKeys|ConvertTo-Json -Compress)){throw 'DISPLAY_ORDERED_REFERENCE_MISMATCH'}
    $ids=@(foreach($key in $rule.orderedUnitKeys){if(-not$dedup.ContainsKey($key)){throw 'DISPLAY_RULE_UNIT_MISSING'};$dedup[$key]})
    $rules.Add([pscustomobject]@{requirementId=$rule.requirementId;blockIds=$ids;orderedUnitKeys=@($rule.orderedUnitKeys);semanticApplicability=$rule.semanticApplicability})
    $obligations.Add($expected[$rule.requirementId])
   }
   $anticipated=@()
   if(@($Result.modelView.anticipatedSteps).Count-or@($receipt.bodyCoverage.anticipatedSteps).Count){throw 'DISPLAY_PRELOAD_RETIRED'}
   $decision=$receipt.loadDecision
  }else{
   foreach($rule in $Result.selectedRuleBlocks){
    $isCurrent=$expected.ContainsKey($rule.requirementId)
    if($isCurrent-and-not$seen.Add($rule.requirementId)){throw 'DISPLAY_SELECTION_MISMATCH'}
    if($rule.fullText-isnot[string]-or[string]::IsNullOrWhiteSpace($rule.fullText)-or$rule.displayParts-isnot[Array]-or$rule.displayParts.Count-eq0){throw 'DISPLAY_COMPLETE_BODY_REQUIRED'}
    if([string]::Join($lf+$lf,@($rule.displayParts.fullText))-cne$rule.fullText){throw 'DISPLAY_PARTS_BODY_MISMATCH'}
    $ids=[Collections.Generic.List[int]]::new()
    foreach($part in $rule.displayParts){
     if($part.sourceLocator-isnot[string]-or$part.sourceIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$part.fullText-isnot[string]-or[string]::IsNullOrWhiteSpace($part.fullText)){throw 'DISPLAY_SOURCE_BINDING_REQUIRED'}
     $textIdentity=Get-DisplayIdentity $part.fullText
     $unit=if($null-ne$part.PSObject.Properties['unitIdentity']){if($part.unitIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'DISPLAY_UNIT_BINDING_REQUIRED'};$part.unitIdentity}else{@($part.sourceLocator,$part.sourceIdentity)|ConvertTo-Json -Compress}
     $key=@($rule.source,$unit,$textIdentity)|ConvertTo-Json -Compress
     if(-not$dedup.ContainsKey($key)){
      $id=$blocks.Count+1;$dedup.Add($key,$id)
      $blocks.Add([pscustomobject]@{id=$id;source=$rule.source;sourceLocator=$part.sourceLocator;sourceIdentity=$part.sourceIdentity;textIdentity=$textIdentity})
      $sections.Add([pscustomobject]@{id=$id;kind='RULE';identity=$textIdentity;fullText=$part.fullText})
     }
     $ids.Add($dedup[$key])
    }
    $displayRule=[pscustomobject]@{requirementId=$rule.requirementId;blockIds=$ids.ToArray();semanticApplicability=$rule.semanticApplicability}
    if($isCurrent){$rules.Add($displayRule);$obligations.Add($expected[$rule.requirementId])}else{$bodyOnlyRules.Add($displayRule)}
   }
   $anticipated=@();$decision=[pscustomobject]@{effectiveMode='FULL';fallbackReason='LEGACY_EXPLICIT_FULL'}
  }
  if($seen.Count-ne$expected.Count){throw 'DISPLAY_SELECTED_BODY_MISSING'}
  $ceilings=if($receipt.schemaVersion-ge2){@($receipt.evidence.ceilings)}else{@($receipt.evidenceCeilings)}
 }else{
  # Rejections and unknown results retain every diagnostic field.
  return [pscustomobject]@{status=$Result.status;mode=$mode;text=($Result|ConvertTo-Json -Depth 100 -Compress);bodyUnits=@();currentRules=@();obligations=@();projectionComplete=$true;modelLoadProven=$false;contextBodyReuse='NOT_APPLICABLE'}
 }
 # Only this text enters the model. Exact identities, coverage and the original
 # machine result remain available to program consumers, never reserialized here.
 $lines=[Collections.Generic.List[string]]::new()
 $lines.Add('AIW '+$mode+' '+$Result.status+' '+$decision.effectiveMode)
 if($decision.fallbackReason-cne'NONE'){$lines.Add('Fallback: '+$decision.fallbackReason)}
 $lines.Add('Limits: '+[string]::Join(', ',@($ceilings))+'; projection only; no action authority or proof of model memory/attention.')
 if($null-ne$Result.PSObject.Properties['projectExternalAuthorization']){
  $external=$Result.projectExternalAuthorization
  $externalFields=@('configured','mode','policyIdentity','grantRuleIds','selectedGrantRuleIds','evidenceCeiling','perCallAuthorityGranted')
  if($external-isnot[pscustomobject]-or@($external.PSObject.Properties).Count-ne$externalFields.Count-or@($externalFields|Where-Object{$_-cnotin$external.PSObject.Properties.Name}).Count){throw 'DISPLAY_EXTERNAL_POLICY_BINDING'}
  if($external.configured-isnot[bool]-or-not$external.configured-or$external.mode-cnotin@('PER_ACTION','PROJECT_PREAUTHORIZED')-or$external.policyIdentity-cne$receipt.sourceBindings.policyIdentity-or$external.evidenceCeiling-cne'INSTRUCTION_BOUND'-or$external.perCallAuthorityGranted-isnot[bool]-or$external.perCallAuthorityGranted){throw 'DISPLAY_EXTERNAL_POLICY_BINDING'}
  Assert-DisplayStrings $external.grantRuleIds;Assert-DisplayStrings $external.selectedGrantRuleIds
  $grantIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($id in $external.grantRuleIds){if($id-cnotmatch'^[A-Z][A-Z0-9_]*$'-or-not$grantIds.Add($id)){throw 'DISPLAY_EXTERNAL_GRANT_SELECTION'}}
  if(($external.mode-ceq'PER_ACTION'-and$grantIds.Count)-or($external.mode-ceq'PROJECT_PREAUTHORIZED'-and-not$grantIds.Count)){throw 'DISPLAY_EXTERNAL_POLICY_BINDING'}
  $selectedGrants=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($id in $external.selectedGrantRuleIds){if(-not$grantIds.Contains($id)-or-not$selectedGrants.Add($id)-or-not$expected.ContainsKey('project:'+$receipt.binding.projectId+':'+$id)){throw 'DISPLAY_EXTERNAL_GRANT_SELECTION'}}
  $lines.Add('Project external authorization: '+$external.mode+'; selected grant rules: '+[string]::Join(',',@($external.selectedGrantRuleIds))+'. Policy interpretation is INSTRUCTION_BOUND; this display is not a per-call admission or result receipt.')
  if($external.mode-ceq'PROJECT_PREAUTHORIZED'-and$receipt.intentEnvelope.requestedActionKind-ceq'EXTERNAL'-and$selectedGrants.Count){
   $lines.Add('Within the current selected grant and actual host/user limits, use the original tool directly. Do not create a per-call task/package or repeat DISCOVER/ADMIT/FINALIZE for each call. Read the complete grant conditions below; coverage, withdrawal, delegation and retry safety still require the actual executor judgment. Preserve native SUCCESS/FAILURE/UNKNOWN. This loading compact cannot be used as a per-action authorization or completion receipt.')
  }else{
   $lines.Add('The current action retains its own authorization and completion requirements.')
  }
 }
 $sources=[Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
 $unitRefs=[Collections.Generic.List[string]]::new()
 foreach($block in $blocks){
  $key=@($block.source,$block.sourceLocator)|ConvertTo-Json -Compress
  if(-not$sources.ContainsKey($key)){
   $sourceId=$sources.Count+1;$sources.Add($key,$sourceId)
   $parts=@($block.sourceLocator.Replace('\','/').Split('/'))
   $short=[string]::Join('/',@($parts|Select-Object -Last 2))
   $lines.Add('s'+$sourceId+'='+$block.source+':'+$short)
  }
  $unitRefs.Add([string]$block.id+'@s'+$sources[$key])
 }
 $lines.Add('Units: '+[string]::Join(' ',@($unitRefs)))
 function Add-RuleLine($Rule,$Obligation,[int[]]$Ids){
  $line=$Rule.requirementId+' ['+[string]::Join(',',@($Ids))+']'
  if($Rule.semanticApplicability-cnotin@('DETERMINISTIC','FACET_MATCH')){$line+=' selection='+$Rule.semanticApplicability}
  foreach($axis in @(@('P','preparationRequirements'),@('R','resultRequirements'))){if(@($Obligation.($axis[1])).Count){$line+=' '+$axis[0]+'='+[string]::Join(',',@($Obligation.($axis[1])))}}
  $lines.Add($line)
 }
 if($Result.status-cin@('PASS','EVALUATION_ONLY')-and$mode-ceq'DISCOVER'-and(($receipt-is[Collections.IDictionary]-and$receipt.Contains('binding'))-or$null-ne$receipt.PSObject.Properties['binding'])-and$receipt.intentEnvelope.requestedActionKind-ceq'NONE'-and$receipt.binding.authorizationIdentity-ceq'NOT_REQUIRED'-and$receipt.intentEnvelope.requestedResultKind-cin@('PLAN','USER_RESPONSE')){
  $lines.Add('Ordinary current USER response: independent mechanical FINALIZE may be omitted only with no package, effect, formal Review/acceptance, TASK_MESSAGE, closure/transition or continuation consumer. All selected rules still apply. This note is not a successful receipt.')
 }
 if($bodyOnlyRules.Count){
  $lines.Add('Additional activity bodies (ordered unit refs; no current operation obligations):')
  foreach($rule in $bodyOnlyRules){$lines.Add($rule.requirementId+' ['+[string]::Join(',',@($rule.blockIds))+']')}
 }
 $lines.Add('Current rules (ordered unit refs; P=preparation, R=result obligations; omitted P/R=none):')
 foreach($rule in $rules){Add-RuleLine $rule $expected[$rule.requirementId] @($rule.blockIds)}
 foreach($step in $anticipated){
  $lines.Add('Anticipated '+$step.stepId+' '+$step.role+'/'+$step.phase+':')
  foreach($rule in $step.rules){
   $ids=@(foreach($key in $rule.orderedUnitKeys){if(-not$dedup.ContainsKey($key)){throw 'DISPLAY_RULE_UNIT_MISSING'};$dedup[$key]})
   Add-RuleLine $rule $rule $ids
  }
 }
 foreach($section in $sections){$lines.Add('['+$section.id+']');$lines.Add($section.fullText)}
 $lines.Add('AIW-END')
 [pscustomobject]@{status=$Result.status;mode=$mode;text=[string]::Join($lf,@($lines));bodyUnits=$sections.ToArray();currentRules=$rules.ToArray();obligations=$obligations.ToArray();projectionComplete=$true;modelLoadProven=$false;contextBodyReuse=$reuse}
}
Export-ModuleMember -Function Get-AiwProcessDisplay
