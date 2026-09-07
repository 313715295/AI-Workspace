[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$script:passed=0

function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Invoke-Host([string]$Executable,[string]$Script,[string[]]$Arguments){$old=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$output=@(& $Executable -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script @Arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old};return [pscustomobject]@{Code=$code;Output=$output;Text=($output-join"`n")}}

$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$modulePath=Join-Path $versionRoot 'scripts\ProcessRequirementComposition.psm1'
$referencePath=Join-Path $versionRoot 'tests\canonical-identity-reference.mjs'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-canonical-identity-'+[guid]::NewGuid().ToString('N'))

try{
    New-Item -ItemType Directory -Path $temp|Out-Null
    Import-Module $modulePath -Force
    $fixtures=@(
        [pscustomobject]@{Name='nfc';Record=[pscustomobject]@{correctionId='fixture-normalization';introducedAgainstFramework='1.0.0';requirementReason=[string][char]0x00E9;effectiveRule='';applicability='';decisionLocator=''};Expected='180|758F09804FBA0E117DDE12BFA8DF98D9DEA39CB5D1284034F947648AE255B291'},
        [pscustomobject]@{Name='nfd';Record=[pscustomobject]@{correctionId='fixture-normalization';introducedAgainstFramework='1.0.0';requirementReason=('e'+[char]0x0301);effectiveRule='';applicability='';decisionLocator=''};Expected='181|5869256A7DE43667C60E640082745A746FF1C062653020C073F2E0BC84AB130E'},
        [pscustomobject]@{Name='lf';Record=[pscustomobject]@{correctionId='fixture-newline';introducedAgainstFramework='1.0.0';requirementReason="line1`nline2";effectiveRule='';applicability='';decisionLocator=''};Expected='184|45F962EF1E3DE36B0B0464F045A7959712F1FAE06023B32376AA7A4F65C23EF8'},
        [pscustomobject]@{Name='crlf';Record=[pscustomobject]@{correctionId='fixture-newline';introducedAgainstFramework='1.0.0';requirementReason="line1`r`nline2";effectiveRule='';applicability='';decisionLocator=''};Expected='185|285EAA0990442125E3DC64CCB303B51C59D3FAC5CCBD460D8058A095F8E457CE'}
    )
    $node=Get-Command node -ErrorAction SilentlyContinue
    Assert-True ($null-ne$node) 'canonical-non-powershell-reference-runtime-available'
    foreach($fixture in $fixtures){
        $pwshIdentity=Get-AiwCanonicalCorrectionRecordIdentityV1 $fixture.Record
        $nodeIdentity=& $node.Source $referencePath ($fixture.Record|ConvertTo-Json -Compress)
        Assert-True ($LASTEXITCODE-eq0-and$pwshIdentity-ceq$fixture.Expected-and[string]$nodeIdentity-ceq$fixture.Expected) ('canonical-identity-pwsh7-node-'+$fixture.Name)
    }
    Assert-True ((Get-AiwCanonicalCorrectionRecordIdentityV1 $fixtures[0].Record)-cne(Get-AiwCanonicalCorrectionRecordIdentityV1 $fixtures[1].Record)-and(Get-AiwCanonicalCorrectionRecordIdentityV1 $fixtures[2].Record)-cne(Get-AiwCanonicalCorrectionRecordIdentityV1 $fixtures[3].Record)) 'canonical-identity-preserves-unicode-and-newlines'

    if($IsWindows){
        $windowsPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $wrapper=Join-Path $temp 'canonical-ps51.ps1'
        Write-Utf8 $wrapper @'
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Module,[Parameter(Mandatory=$true)][string]$RecordPath)
$ErrorActionPreference='Stop'
try{
    $utf8Strict=New-Object Text.UTF8Encoding($false,$true)
    $moduleText=[IO.File]::ReadAllText($Module,$utf8Strict)
    $moduleBlock=[ScriptBlock]::Create($moduleText)
    $memoryModule=New-Module -ScriptBlock $moduleBlock
    Import-Module $memoryModule -Force
    $recordText=[IO.File]::ReadAllText($RecordPath,$utf8Strict)
    $record=$recordText|ConvertFrom-Json
    Get-AiwCanonicalCorrectionRecordIdentityV1 $record
}catch{
    [Console]::Error.WriteLine([string]$_.Exception.Message)
    exit 1
}
'@
        foreach($fixture in $fixtures){
            $recordPath=Join-Path $temp ('canonical-ps51-'+$fixture.Name+'.json')
            Write-Utf8 $recordPath ($fixture.Record|ConvertTo-Json -Compress)
            $run=Invoke-Host $windowsPowerShell $wrapper @('-Module',$modulePath,'-RecordPath',$recordPath)
            if($run.Code-ne0-or[string]$run.Output[-1]-cne$fixture.Expected){Write-Output ('DIAG|canonical-identity-powershell51-'+$fixture.Name+'|code='+$run.Code+'|'+$run.Text)}
            Assert-True ($run.Code-eq0-and[string]$run.Output[-1]-ceq$fixture.Expected) ('canonical-identity-powershell51-'+$fixture.Name)
        }
    }else{Write-Output 'EVIDENCE_CEILING|POWERSHELL51_CANONICAL_RUNTIME_NOT_AVAILABLE'}
}finally{
    if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$resolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));if([IO.Path]::GetDirectoryName($resolved)-cne$tempRoot-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-canonical-identity-[a-f0-9]{32}$'){throw 'CANONICAL_TEMP_CLEANUP_BOUNDARY'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=canonical-identity')
