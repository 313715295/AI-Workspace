[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
# @project-source-entry-scope
try {
    Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
    Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1')
    $request=(Read-AiwStrictInputJson $InputPath).Value
    Invoke-AiwProjectSourceScope -ProjectRoot ([IO.Path]::GetFullPath($request.projectRoot,$PWD.ProviderPath)) -Mode $(if($request.operation-ceq'PREVIEW'){'OBSERVE'}else{'WRITE'}) -ArgumentList @($request,[bool]$AsJson) -Body {
        param($request,$AsJson)
        try {
            Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
            $result=Invoke-AiwControlTransition $request
            if($AsJson){$result|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii}else{Write-Output ($result.status+'|CONTROL_TRANSITION')}
        } catch {
            if($AsJson){[ordered]@{status='FAIL';reason=$_.Exception.Message}|ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii}else{Write-Output ('FAIL|'+$_.Exception.Message)}
            exit 2
        }
    }
} catch {
    if($AsJson){[ordered]@{status='FAIL';reason=$_.Exception.Message}|ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii}else{Write-Output ('FAIL|'+$_.Exception.Message)}
    exit 2
}
