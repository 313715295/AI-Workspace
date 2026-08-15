[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
$candidateRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$frameworkRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $candidateRoot))
$stableRoot=Join-Path $frameworkRoot 'versions\1.5.2'
$manifestPath=Join-Path $stableRoot 'RELEASE_MANIFEST.json'
$manifest=Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath|ConvertFrom-Json
$records=@();$total=[long]0;$relativePaths=@(Get-ChildItem -LiteralPath $stableRoot -Recurse -File|Where-Object{$_.FullName-cne$manifestPath}|ForEach-Object{$_.FullName.Substring($stableRoot.Length+1).Replace('\','/')});[Array]::Sort($relativePaths,[StringComparer]::Ordinal)
foreach($relative in $relativePaths){$file=Get-Item -LiteralPath (Join-Path $stableRoot $relative);$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash;$records+="$relative|$($file.Length)|$hash";$total+=$file.Length}
$payload=[Text.Encoding]::UTF8.GetBytes($records-join"`n");$sha=[Security.Cryptography.SHA256]::Create();try{$canonical=([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-','')}finally{$sha.Dispose()}
if($records.Count-ne[int]$manifest.fileCount-or$total-ne[long]$manifest.totalBytes-or$canonical-cne[string]$manifest.canonical){throw 'BASELINE_1_5_2_DRIFT'}
$candidate=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $candidateRoot 'VERSION.json')|ConvertFrom-Json
if([string]$candidate.baseline-cne'1.5.2'-or[string]$candidate.lifecycle-cne'DRAFT'-or[bool]$candidate.consumable){throw 'CANDIDATE_BASELINE_OR_LIFECYCLE'}
Write-Output 'RESULT 2/2 passed|scope=baseline-1.5.2-compatibility'
exit 0
