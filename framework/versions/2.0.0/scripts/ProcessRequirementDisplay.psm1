Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:DisplayUtf8=[Text.UTF8Encoding]::new($false,$true)

# Private projection of a real resolver result. No selection, files, authority
# decisions, history cache or claim that the current model retained a body.
function Get-DisplayIdentity([string]$Text){
 $bytes=$script:DisplayUtf8.GetBytes($Text)
 return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}
function Assert-DisplayStrings($Value){
 if($Value-isnot[Array]){throw 'DISPLAY_ARRAY_REQUIRED'}
 foreach($item in $Value){if($item-isnot[string]-or[string]::IsNullOrWhiteSpace($item)){throw 'DISPLAY_STRING_REQUIRED'}}
}
function Split-DisplayText([string]$Text,[int]$MaxBytes){
 if($script:DisplayUtf8.GetByteCount($Text)-le$MaxBytes){return $Text}
 $builder=[Text.StringBuilder]::new();$bytes=0
 foreach($rune in $Text.EnumerateRunes()){
  if($bytes+$rune.Utf8SequenceLength-gt$MaxBytes){$builder.ToString();$null=$builder.Clear();$bytes=0}
  $null=$builder.Append($rune.ToString());$bytes+=$rune.Utf8SequenceLength
 }
 if($builder.Length){$builder.ToString()}
}
function Get-AiwProcessDisplay {
 [CmdletBinding()]
 param([Parameter(Mandatory)]$Result,[ValidateRange(1024,2147483647)][int]$MaxPageUtf8Bytes=16000)
 if($Result-isnot[pscustomobject]-or$null-eq$Result.PSObject.Properties['status']-or$Result.status-isnot[string]){throw 'DISPLAY_RESOLVER_RESULT_REQUIRED'}
 $sections=[Collections.Generic.List[object]]::new()
 $rules=[Collections.Generic.List[object]]::new();$blocks=[Collections.Generic.List[object]]::new()
 $obligations=[Collections.Generic.List[object]]::new();$ceilings=@()
 $mode=if($null-ne$Result.PSObject.Properties['mode']){[string]$Result.mode}else{'NOT_AVAILABLE'}
 if($Result.status-cin@('PASS','EVALUATION_ONLY')-and$mode-ceq'DISCOVER'){
  if($Result.resultType-cne'PROCESS_REQUIREMENTS_DISCOVER_RESULT'-or$Result.selectedRuleBlocks-isnot[Array]-or$Result.compactReceipt-isnot[pscustomobject]){throw 'DISPLAY_DISCOVER_RESULT_REQUIRED'}
  $receipt=$Result.compactReceipt
  if($receipt.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or$receipt.status-cne$Result.status-or$receipt.selectedObligations-isnot[Array]){throw 'DISPLAY_RECEIPT_MISMATCH'}
  $byId=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
  foreach($row in $receipt.selectedObligations){
   if($row.requirementId-isnot[string]-or[string]::IsNullOrWhiteSpace($row.requirementId)-or$byId.ContainsKey($row.requirementId)){throw 'DISPLAY_REQUIREMENT_DUPLICATE'}
   Assert-DisplayStrings $row.preparationRequirements;Assert-DisplayStrings $row.resultRequirements
   $byId.Add($row.requirementId,$row)
  }
  $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $dedup=[Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
  foreach($rule in $Result.selectedRuleBlocks){
   $id=[string]$rule.requirementId
   if(-not$seen.Add($id)-or-not$byId.ContainsKey($id)){throw 'DISPLAY_SELECTION_MISMATCH'}
   Assert-DisplayStrings $rule.preparationRequirements;Assert-DisplayStrings $rule.resultRequirements
   $row=$byId[$id]
   foreach($axis in @('preparationRequirements','resultRequirements')){if(($row.$axis|ConvertTo-Json -Compress)-cne($rule.$axis|ConvertTo-Json -Compress)){throw 'DISPLAY_OBLIGATION_MISMATCH'}}
   if($rule.fullText-isnot[string]-or[string]::IsNullOrWhiteSpace($rule.fullText)-or$rule.displayParts-isnot[Array]-or$rule.displayParts.Count-eq0){throw 'DISPLAY_COMPLETE_BODY_REQUIRED'}
   $bodies=@($rule.displayParts|ForEach-Object {[string]$_.fullText})
   if([string]::Join("`n`n",$bodies)-cne$rule.fullText){throw 'DISPLAY_PARTS_BODY_MISMATCH'}
   $blockIds=[Collections.Generic.List[int]]::new()
   foreach($part in $rule.displayParts){
    if($part.sourceLocator-isnot[string]-or[string]::IsNullOrWhiteSpace($part.sourceLocator)-or$part.sourceIdentity-isnot[string]-or$part.sourceIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$part.fullText-isnot[string]-or[string]::IsNullOrWhiteSpace($part.fullText)){throw 'DISPLAY_SOURCE_BINDING_REQUIRED'}
    $textIdentity=Get-DisplayIdentity $part.fullText
    $key=@([string]$rule.source,$part.sourceLocator,$part.sourceIdentity,$textIdentity)|ConvertTo-Json -Compress
    if(-not$dedup.ContainsKey($key)){
     $number=$blocks.Count+1;$dedup.Add($key,$number)
     $blocks.Add([pscustomobject]@{id=$number;source=[string]$rule.source;sourceLocator=$part.sourceLocator;sourceIdentity=$part.sourceIdentity;textIdentity=$textIdentity})
     $sections.Add([pscustomobject]@{id=$number;kind='RULE';identity=$textIdentity;fullText=$part.fullText})
    }
    $blockIds.Add($dedup[$key])
   }
   $rules.Add([pscustomobject]@{requirementId=$id;blockIds=$blockIds.ToArray();semanticApplicability=[string]$rule.semanticApplicability})
   $obligations.Add([pscustomobject]@{requirementId=$id;preparationRequirements=@($row.preparationRequirements);resultRequirements=@($row.resultRequirements)})
  }
  if($seen.Count-ne$byId.Count){throw 'DISPLAY_SELECTED_BODY_MISSING'}
  $ceilings=if([int]$receipt.schemaVersion-eq2){@($receipt.evidence.ceilings)}else{@($receipt.evidenceCeilings)}
  $metadata=[ordered]@{status=$Result.status;mode=$mode;selectionIdentity=$receipt.selectionIdentity;sourceCompositionIdentity=$receipt.sourceCompositionIdentity;currentRules=$rules.ToArray();blocks=$blocks.ToArray();obligations=$obligations.ToArray();evidenceCeilings=$ceilings;contextBodyReuse='UNSUPPORTED_FULLTEXT_FALLBACK';projectionOnly=$true;modelLoadProven=$false;authorityGranted=$false}
  $metadataText=$metadata|ConvertTo-Json -Depth 50 -Compress
  $sections.Insert(0,[pscustomobject]@{id=0;kind='METADATA';identity=(Get-DisplayIdentity $metadataText);fullText=$metadataText})
 }else{
  # Errors and boundary results retain every original reason, missing item and
  # ceiling. A failed DISCOVER is never reformatted as a successful empty set.
  $raw=$Result|ConvertTo-Json -Depth 100 -Compress
  $sections.Add([pscustomobject]@{id=0;kind='RESULT';identity=(Get-DisplayIdentity $raw);fullText=$raw})
 }
 $layoutMaterial=@($MaxPageUtf8Bytes)+@($sections|ForEach-Object {[string]$_.id+'|'+$_.kind+'|'+$_.identity})
 $displayIdentity=(Get-DisplayIdentity ($layoutMaterial-join"`n")).Split('|')[1]
 $rawPages=[Collections.Generic.List[object]]::new();$pending=[Collections.Generic.List[object]]::new();$pendingBytes=0
 foreach($section in $sections){
  $chunks=@(Split-DisplayText $section.fullText ($MaxPageUtf8Bytes-768))
  for($index=0;$index-lt$chunks.Count;$index++){
   $partNumber=$index+1
   $header='AIW-SECTION|'+$section.id+'|'+$section.kind+'|'+$section.identity+'|part='+$partNumber+'/'+$chunks.Count
   $footer='AIW-SECTION-END|'+$section.id+'|part='+$partNumber+'/'+$chunks.Count
   $rendered=$header+"`n"+$chunks[$index]+"`n"+$footer
   $unit=[pscustomobject]@{sectionId=$section.id;kind=$section.kind;identity=$section.identity;part=$partNumber;totalParts=$chunks.Count;fullTextSlice=$chunks[$index];text=$rendered}
   $unitBytes=$script:DisplayUtf8.GetByteCount($rendered)+1
   if($pending.Count-and$pendingBytes+$unitBytes-gt$MaxPageUtf8Bytes-256){$rawPages.Add($pending.ToArray());$pending=[Collections.Generic.List[object]]::new();$pendingBytes=0}
   $pending.Add($unit);$pendingBytes+=$unitBytes
  }
 }
 if($pending.Count){$rawPages.Add($pending.ToArray())}
 $pages=[Collections.Generic.List[object]]::new()
 for($index=0;$index-lt$rawPages.Count;$index++){
  $number=$index+1;$units=@($rawPages[$index])
  $pageText='AIW-DISPLAY|'+$displayIdentity+'|page='+$number+'/'+$rawPages.Count+'|status='+$Result.status+"`n"+[string]::Join("`n",@($units.text))+"`n"+'AIW-DISPLAY-END|'+$displayIdentity+'|page='+$number+'/'+$rawPages.Count
  if($script:DisplayUtf8.GetByteCount($pageText)-gt$MaxPageUtf8Bytes){throw 'DISPLAY_PAGE_LIMIT'}
  $pages.Add([pscustomobject]@{page=$number;totalPages=$rawPages.Count;segments=$units;text=$pageText})
 }
 return [pscustomobject]@{status=$Result.status;mode=$mode;displayIdentity=$displayIdentity;currentRules=$rules.ToArray();obligations=$obligations.ToArray();pages=$pages.ToArray();projectionComplete=$true;modelLoadProven=$false;contextBodyReuse='UNSUPPORTED_FULLTEXT_FALLBACK'}
}
function Assert-AiwProcessDisplayPages {
 [CmdletBinding()]
 param([Parameter(Mandatory)]$Projection,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ObservedPages)
 if($ObservedPages.Count-ne$Projection.pages.Count){throw 'DISPLAY_PAGE_SET_INCOMPLETE'}
 for($index=0;$index-lt$ObservedPages.Count;$index++){if($ObservedPages[$index]-cne$Projection.pages[$index].text){throw 'DISPLAY_PAGE_BYTES_OR_ORDER'}}
 return [pscustomobject]@{status='PASS';pageCount=$ObservedPages.Count;projectionComplete=$true;modelLoadProven=$false;evidenceCeiling='CALLER_BOUND_OUTPUT_BYTES_ONLY'}
}
Export-ModuleMember -Function Get-AiwProcessDisplay,Assert-AiwProcessDisplayPages
