[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidencePath,
    [switch]$SkipManifest,
    [switch]$SkipBaseline,
    [switch]$SkipPerformanceSmoke,
    [switch]$ToolContractOnly,
    [switch]$SelectorOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$runner=Join-Path $PSScriptRoot 'run-framework-tests.ps1'
$pwsh=[Environment]::ProcessPath
if([string]::IsNullOrWhiteSpace($pwsh)-or-not(Test-Path -LiteralPath $runner -PathType Leaf)){throw 'TEST_RUNNER_UNAVAILABLE'}
$full=[IO.Path]::GetFullPath($EvidencePath)
if(Test-Path -LiteralPath $full){throw 'EVIDENCE_PATH_EXISTS'}
$parent=[IO.Path]::GetDirectoryName($full)
if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
$arguments=@('-NoProfile','-NonInteractive','-File',$runner)
foreach($name in @('SkipManifest','SkipBaseline','SkipPerformanceSmoke','ToolContractOnly','SelectorOnly')){
    if($PSBoundParameters.ContainsKey($name)-and[bool]$PSBoundParameters[$name]){$arguments+='-'+$name}
}
$utf8=[Text.UTF8Encoding]::new($false)
$writer=[IO.StreamWriter]::new($full,$false,$utf8)
$pass=0;$skip=0;$notRun=0;$unknown=0;$ceiling=0;$result='MISSING';$details=[Collections.Generic.List[string]]::new();$exitCode=$null
try{
    & $pwsh @arguments 2>&1|ForEach-Object{
        $line=[string]$_
        $writer.WriteLine($line)
        if($line.StartsWith('PASS|',[StringComparison]::Ordinal)){$pass++}
        elseif($line.StartsWith('SKIP|',[StringComparison]::Ordinal)){$skip++}
        elseif($line.StartsWith('NOT_RUN|',[StringComparison]::Ordinal)){$notRun++}
        elseif($line.StartsWith('UNKNOWN|',[StringComparison]::Ordinal)){$unknown++}
        elseif($line.StartsWith('EVIDENCE_CEILING|',[StringComparison]::Ordinal)){$ceiling++}
        elseif($line.StartsWith('RESULT|',[StringComparison]::Ordinal)){$result=$line}
        elseif(-not[string]::IsNullOrWhiteSpace($line)){
            $details.Add($line)
            if($details.Count-gt8){$details.RemoveAt(0)}
        }
    }
    $exitCode=$LASTEXITCODE
}finally{
    $writer.Dispose()
}
$bytes=[IO.File]::ReadAllBytes($full)
$identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
$status=if($exitCode-eq0-and$result-cne'MISSING'){'PASS'}elseif($null-eq$exitCode){'INTERRUPTED'}else{'FAIL'}
Write-Output "SUMMARY|status=$status|exit=$exitCode|pass=$pass|skip=$skip|notRun=$notRun|unknown=$unknown|ceiling=$ceiling"
Write-Output "SUMMARY_RESULT|$result"
Write-Output "FULL_EVIDENCE|path=$full|identity=$identity"
if($status-cne'PASS'){foreach($line in $details){Write-Output "DETAIL|$line"};exit 1}
