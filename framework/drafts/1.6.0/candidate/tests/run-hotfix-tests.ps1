[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$candidateRoot=Split-Path -Parent $PSScriptRoot
$workspaceRoot=[IO.Path]::GetFullPath((Join-Path $candidateRoot '..\..\..\..'))
$baselineRunner=Join-Path $workspaceRoot 'framework\versions\1.5.2\tests\run-hotfix-tests.ps1'
$old=$ErrorActionPreference;$ErrorActionPreference='Continue'
try{$output=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $baselineRunner 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}
finally{$ErrorActionPreference=$old}
if($code-ne0){$output|ForEach-Object{Write-Output $_};throw 'BASELINE_1_5_2_HOTFIX_REGRESSION'}
$result=@($output|Where-Object{$_-like'HOTFIX_TESTS_PASS|checks=37'})
if($result.Count-ne1){throw 'BASELINE_1_5_2_RESULT_MISSING'}
Write-Output 'PASS|baseline-1.5.2-hotfix-suite'
Write-Output 'RESULT 1/1 passed|scope=baseline-compatibility'
