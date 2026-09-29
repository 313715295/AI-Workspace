[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [ValidateSet('DISCOVER','QUERY')][string]$Operation,
    [string[]]$SourceId=@(),
    [string[]]$EntryId=@(),
    [ValidateSet('LOCATOR_ONLY','FULLTEXT')][string]$ContentMode='LOCATOR_ONLY',
    [string[]]$ForbiddenPaths=@(),
    [switch]$AsJson
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
$mode=if($PSBoundParameters.ContainsKey('Operation')){$Operation}elseif($PSBoundParameters.ContainsKey('EntryId')){'QUERY'}else{'DISCOVER'}
try{
    Import-Module (Join-Path $PSScriptRoot 'KnowledgeSources.psm1') -Force
    $result=Invoke-AiwKnowledgeQuery -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -Operation $mode -SourceId $SourceId -EntryId $EntryId -ContentMode $ContentMode -ForbiddenPaths $ForbiddenPaths
    if($AsJson){$result|ConvertTo-Json -Depth 100 -Compress}else{$result|ConvertTo-Json -Depth 100}
    exit 0
}catch{
    $result=[pscustomobject]@{status='KNOWLEDGE_UNAVAILABLE';operation=$mode;reason=$_.Exception.Message;referenceOnly=$true;authority=$false;sources=@();entries=@()}
    if($AsJson){$result|ConvertTo-Json -Depth 10 -Compress}else{Write-Output ('KNOWLEDGE_UNAVAILABLE|'+$result.reason)}
    exit 3
}
