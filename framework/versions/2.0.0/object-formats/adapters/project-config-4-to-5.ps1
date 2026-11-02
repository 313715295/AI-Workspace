param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne4){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
$result=Copy-AiwFormatValue $Value
if($null-ne$result.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']){
    $legacy=$result.frameworkCapabilities.KNOWLEDGE_REFERENCE
    if($null-ne$legacy.PSObject.Properties['indexLocator']){
        $result.frameworkCapabilities.KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$legacy.enabled;sources=@([pscustomobject]@{id='project';root=[pscustomobject]@{kind='PROJECT';locator='.'};indexLocator=$legacy.indexLocator;selectionHints=@();updatePolicy='FOLLOW'})}
    }elseif($null-eq$legacy.PSObject.Properties['sources']){$result.frameworkCapabilities.KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$legacy.enabled;sources=@()}}
}
$result.schemaVersion=5
$result
