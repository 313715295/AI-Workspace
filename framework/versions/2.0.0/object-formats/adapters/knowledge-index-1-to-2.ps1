param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne1){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
$result=Copy-AiwFormatValue $Value
foreach($entry in $result.entries){
    if(($entry.invalidatesOn-join'|')-cne'LOCATOR_IDENTITY_CHANGE|AUTHORITY_IDENTITY_CHANGE'){throw 'LEGACY_KNOWLEDGE_INVALIDATORS'}
    $dependencies=@([pscustomobject]@{locator=$entry.authorityLocator;identity=$entry.authorityIdentity})
    $entry.PSObject.Properties.Remove('authorityLocator');$entry.PSObject.Properties.Remove('authorityIdentity')
    $entry|Add-Member -NotePropertyName tags -NotePropertyValue @()
    $entry|Add-Member -NotePropertyName authorityDependencies -NotePropertyValue $dependencies
    $entry.invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE')
}
$result.schemaVersion=2
$result
