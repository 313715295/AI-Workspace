param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne2){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
$result=Copy-AiwFormatValue $Value
$result.schemaVersion=3
if($null-ne$Context.PSObject.Properties['TargetProcessContractVersion']){$result.contractVersion=$Context.TargetProcessContractVersion}
$result
