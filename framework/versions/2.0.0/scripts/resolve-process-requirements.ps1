[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson,[switch]$DeleteInputOnExit,[string]$AuthorizationCheckerPath,[string]$CompactReceiptPath,[string]$DisplayPath,
 [string[]]$ConsumedRuntimePath=@(),[string]$ConsumedRuntimePathList,[string[]]$EmptyRuntimeDirectory=@(),[string[]]$RetainedRuntimePath=@(),
 [string]$PublicationSourceInputPath,[string]$ExpectedPublicationSourceInputIdentity)
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}
Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementBoundary.psm1')
$response=Invoke-AiwProcessRequirementBoundary @PSBoundParameters
$response.output | Write-Output
exit $response.exitCode
