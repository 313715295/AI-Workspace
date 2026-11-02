param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne1){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
if($null-eq$Context.PSObject.Properties['SourceBindings']){throw 'FORMAT_BOOTSTRAP_GROUP_REQUIRED'}
$result=Copy-AiwFormatValue $Value
foreach($rule in $result.rules){if($null-ne$rule.PSObject.Properties['source']){$rule.source=Convert-AiwLegacyPolicySource $rule.source $rule.ruleId @($Context.SourceBindings)}}
$result.PSObject.Properties.Remove('selectedRulePackBytes')
$result.schemaVersion=2
if($null-ne$Context.PSObject.Properties['TargetProcessContractVersion']){$result.contractVersion=$Context.TargetProcessContractVersion}
$result
