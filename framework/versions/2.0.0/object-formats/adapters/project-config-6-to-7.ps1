
param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne6-or$Value.processPolicy.schemaVersion-ne2){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
$result=Copy-AiwFormatValue $Value
$result.schemaVersion=7;$result.processPolicy.schemaVersion=3
$result
