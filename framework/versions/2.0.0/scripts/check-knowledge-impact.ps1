[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [Parameter(Mandatory)][string[]]$ChangedAuthorityPath,
    [string[]]$SourceId=@(),
    [string[]]$ForbiddenPaths=@(),
    [switch]$AsJson
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
try{
    Import-Module (Join-Path $PSScriptRoot 'KnowledgeSources.psm1') -Force
    $result=Invoke-AiwKnowledgeImpact -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -ChangedAuthorityPath $ChangedAuthorityPath -SourceId $SourceId -ForbiddenPaths $ForbiddenPaths
    if($AsJson){$result|ConvertTo-Json -Depth 100 -Compress}else{$result|ConvertTo-Json -Depth 100}
    exit 0
}catch{
    $result=[pscustomobject]@{status='KNOWLEDGE_IMPACT_UNAVAILABLE';reason=$_.Exception.Message;referenceOnly=$true;authority=$false;sources=@();entries=@()}
    if($AsJson){$result|ConvertTo-Json -Depth 10 -Compress}else{Write-Output ('KNOWLEDGE_IMPACT_UNAVAILABLE|'+$result.reason)}
    exit 3
}
