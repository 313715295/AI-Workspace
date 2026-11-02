param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne5){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
if($null-eq$Context.PSObject.Properties['LegacyPolicy']-or$Context.LegacyPolicy.schemaVersion-ne1){throw 'FORMAT_BOOTSTRAP_GROUP_REQUIRED'}
$result=Copy-AiwFormatValue $Value
$bindings=@(Get-AiwLegacySourceBindings $Context.LegacyPolicy)
if($null-ne$result.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']){
    $sources=@()
    foreach($source in $result.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources){
        $bindingId='legacy-knowledge-'+$source.id
        $bindings+=[pscustomobject]@{id=$bindingId;provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$source.root.locator};allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator='.'});decisionLocator='.ai-workspace/project.json'}
        $new=[ordered]@{id=$source.id;bindingId=$bindingId;indexLocator=$source.indexLocator;selectionHints=@($source.selectionHints);updatePolicy=$source.updatePolicy}
        if($source.updatePolicy-ceq'PINNED'){
            $new.indexIdentity=$source.indexIdentity
            $document=[pscustomobject]@{bindingId=$bindingId;locator=$source.indexLocator;identity=$source.indexIdentity;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
            $new.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) $bindings
        }else{$new.revisionSelector=$source.indexLocator}
        $sources+=[pscustomobject]$new
    }
    $result.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources=$sources
}
Assert-AiwSourceBindings $bindings
$result|Add-Member -NotePropertyName sourceBindings -NotePropertyValue $bindings
$result.schemaVersion=6;$result.processPolicy.schemaVersion=2
$result
