
param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)]$Context)
$ErrorActionPreference='Stop'
if($Value.schemaVersion-ne2){throw 'FORMAT_SEGMENT_INPUT_FORMAT'}
$result=Copy-AiwFormatValue $Value
# Old complete-file descriptors remain byte-exact descriptors, never guessed units.
$result.schemaVersion=3
$result
