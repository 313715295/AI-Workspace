param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne1){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
$result=Copy-AiwFormatValue $Value
foreach($record in $result.corrections){
    # Free-text applicability is preserved. Empty boundaries conservatively
    # retain the legacy full-source behavior; no role/action/facet is guessed.
    $record|Add-Member -NotePropertyName selectors -NotePropertyValue ([pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()})
    foreach($name in @('preparationRequirements','resultRequirements','requiredFacts','mechanicalCheckRefs')){$record|Add-Member -NotePropertyName $name -NotePropertyValue @()}
}
if($null-ne$result.PSObject.Properties['contractVersion']){$result.contractVersion='2.0.0'}else{$result|Add-Member -NotePropertyName contractVersion -NotePropertyValue '2.0.0'}
$result.schemaVersion=2
$result
