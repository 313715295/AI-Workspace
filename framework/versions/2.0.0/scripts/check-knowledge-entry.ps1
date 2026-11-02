[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [ValidateSet('DISCOVER','QUERY')][string]$Operation,
    [string[]]$SourceId=@(),
    [string[]]$EntryId=@(),
    [string]$FacetQueryJson,
    [ValidateSet('LOCATOR_ONLY','FULLTEXT')][string]$ContentMode='LOCATOR_ONLY',
    [string[]]$ForbiddenPaths=@(),
    [switch]$AsJson
)
# @project-source-entry-scope
Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1') -ErrorAction Stop
$aiwPublicationScopeLease=$null
try {
$aiwPublicationEntryRoot=$ProjectRoot
if($aiwPublicationEntryRoot){$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot ([IO.Path]::GetFullPath($aiwPublicationEntryRoot,$PWD.ProviderPath)) -Mode OBSERVE}

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
$mode=if($PSBoundParameters.ContainsKey('Operation')){$Operation}elseif($PSBoundParameters.ContainsKey('EntryId')-or$PSBoundParameters.ContainsKey('FacetQueryJson')){'QUERY'}else{'DISCOVER'}
try{
    Import-Module (Join-Path $PSScriptRoot 'KnowledgeSources.psm1') -Force
    $facetArgs=@{};if($PSBoundParameters.ContainsKey('FacetQueryJson')){$facetArgs.FacetQueryJson=$FacetQueryJson}
    $result=Invoke-AiwKnowledgeQuery -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -Operation $mode -SourceId $SourceId -EntryId $EntryId -ContentMode $ContentMode -ForbiddenPaths $ForbiddenPaths @facetArgs
    if($AsJson){$result|ConvertTo-Json -Depth 100 -Compress -EscapeHandling EscapeNonAscii}else{$result|ConvertTo-Json -Depth 100 -EscapeHandling EscapeNonAscii}
    exit 0
}catch{
    $result=[pscustomobject]@{status='KNOWLEDGE_UNAVAILABLE';operation=$mode;reason=$_.Exception.Message;referenceOnly=$true;authority=$false;sources=@();entries=@()}
    if($AsJson){$result|ConvertTo-Json -Depth 10 -Compress -EscapeHandling EscapeNonAscii}else{Write-Output ('KNOWLEDGE_UNAVAILABLE|'+$result.reason)}
    exit 3
}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
