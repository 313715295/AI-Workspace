[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
try {
    Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1') -Force
    $request=(Read-AiwStrictInputJson $InputPath).Value
    $result=Invoke-AiwControlTransition $request
    if($AsJson){$result|ConvertTo-Json -Depth 100 -Compress}else{Write-Output ($result.status+'|CONTROL_TRANSITION')}
} catch {
    if($AsJson){[ordered]@{status='FAIL';reason=$_.Exception.Message}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|'+$_.Exception.Message)}
    exit 2
}
