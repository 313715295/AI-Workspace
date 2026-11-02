param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne2-or$null-eq$Context.PSObject.Properties['ProjectId']-or$null-eq$Context.PSObject.Properties['LibraryId']-or$Value.projectId-cne$Context.ProjectId){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
$result=Copy-AiwFormatValue $Value
foreach($entry in $result.entries){
    if(($entry.invalidatesOn-join'|')-cne'REFERENCE_IDENTITY_CHANGE|AUTHORITY_DEPENDENCY_IDENTITY_CHANGE'){throw 'LEGACY_KNOWLEDGE_INVALIDATORS'}
    $entry|Add-Member -NotePropertyName kind -NotePropertyValue 'PROJECT_DERIVED'
    $entry|Add-Member -NotePropertyName projectId -NotePropertyValue $Context.ProjectId
}
$result.PSObject.Properties.Remove('projectId');$result|Add-Member -NotePropertyName libraryId -NotePropertyValue $Context.LibraryId
$result.schemaVersion=3
$result
