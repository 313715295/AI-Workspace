[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$FrameworkRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')][string]$TargetVersion,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [ValidateSet('RECOVER','PRECHECK','POSTCHECK')][string]$Operation = 'RECOVER',
    [string]$ExpectedCorrectionsIdentity,
    [switch]$AllowMissingCorrections,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8Strict = New-Object Text.UTF8Encoding($false,$true)

function Get-Identity([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path);$sha=[Security.Cryptography.SHA256]::Create()
    try{return $bytes.Length.ToString()+'|'+([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}
    finally{$sha.Dispose()}
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Test-JsonWhitespace([char]$Character) {
    return $Character -eq [char]0x20 -or $Character -eq [char]0x09 -or $Character -eq [char]0x0A -or $Character -eq [char]0x0D
}

function Skip-JsonWhitespace([string]$Text,[ref]$Index) {
    while($Index.Value-lt$Text.Length-and(Test-JsonWhitespace $Text[$Index.Value])){$Index.Value++}
}

function Read-JsonStringToken([string]$Text,[ref]$Index) {
    if($Index.Value-ge$Text.Length-or$Text[$Index.Value]-ne[char]0x22){throw 'JSON_STRING'}
    $start=$Index.Value;$cursor=$start+1
    while($cursor-lt$Text.Length){
        $character=$Text[$cursor]
        if([int]$character-lt0x20){throw 'JSON_STRING'}
        if($character-eq[char]0x5C){
            $cursor++;if($cursor-ge$Text.Length){throw 'JSON_STRING'}
            $escape=$Text[$cursor]
            if($escape-eq[char]0x75){
                if($cursor+4-ge$Text.Length){throw 'JSON_STRING'}
                for($offset=1;$offset-le4;$offset++){if($Text[$cursor+$offset]-notmatch'^[0-9A-Fa-f]$'){throw 'JSON_STRING'}}
                $cursor+=5;continue
            }
            if('"\/bfnrt'.IndexOf($escape)-lt0){throw 'JSON_STRING'}
            $cursor++;continue
        }
        if($character-eq[char]0x22){
            $cursor++;$token=$Text.Substring($start,$cursor-$start);$Index.Value=$cursor
            try{return [string]($token|ConvertFrom-Json)}catch{throw 'JSON_STRING'}
        }
        $cursor++
    }
    throw 'JSON_STRING'
}

function Read-JsonValue([string]$Text,[ref]$Index) {
    Skip-JsonWhitespace $Text $Index
    if($Index.Value-ge$Text.Length){throw 'JSON_VALUE'}
    $character=$Text[$Index.Value]
    if($character-eq[char]0x22){$null=Read-JsonStringToken $Text $Index;return}
    if($character-eq[char]0x7B){Read-JsonObject $Text $Index;return}
    if($character-eq[char]0x5B){Read-JsonArray $Text $Index;return}
    $start=$Index.Value
    while($Index.Value-lt$Text.Length-and$Text[$Index.Value]-notin@([char]0x2C,[char]0x5D,[char]0x7D)-and-not(Test-JsonWhitespace $Text[$Index.Value])){$Index.Value++}
    if($Index.Value-eq$start){throw 'JSON_VALUE'}
    $token=$Text.Substring($start,$Index.Value-$start)
    if($token-cnotmatch'^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$'){throw 'JSON_VALUE'}
}

function Read-JsonObject([string]$Text,[ref]$Index) {
    if($Text[$Index.Value]-ne[char]0x7B){throw 'JSON_OBJECT'}
    $Index.Value++;Skip-JsonWhitespace $Text $Index
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    if($Index.Value-lt$Text.Length-and$Text[$Index.Value]-eq[char]0x7D){$Index.Value++;return}
    while($Index.Value-lt$Text.Length){
        $name=Read-JsonStringToken $Text $Index
        if(-not$seen.Add($name)){throw ('JSON_DUPLICATE_FIELD|'+$name)}
        Skip-JsonWhitespace $Text $Index
        if($Index.Value-ge$Text.Length-or$Text[$Index.Value]-ne[char]0x3A){throw 'JSON_OBJECT'}
        $Index.Value++;Read-JsonValue $Text $Index;Skip-JsonWhitespace $Text $Index
        if($Index.Value-ge$Text.Length){throw 'JSON_OBJECT'}
        if($Text[$Index.Value]-eq[char]0x2C){$Index.Value++;Skip-JsonWhitespace $Text $Index;continue}
        if($Text[$Index.Value]-eq[char]0x7D){$Index.Value++;return}
        throw 'JSON_OBJECT'
    }
    throw 'JSON_OBJECT'
}

function Read-JsonArray([string]$Text,[ref]$Index) {
    if($Text[$Index.Value]-ne[char]0x5B){throw 'JSON_ARRAY'}
    $Index.Value++;Skip-JsonWhitespace $Text $Index
    if($Index.Value-lt$Text.Length-and$Text[$Index.Value]-eq[char]0x5D){$Index.Value++;return}
    while($Index.Value-lt$Text.Length){
        Read-JsonValue $Text $Index;Skip-JsonWhitespace $Text $Index
        if($Index.Value-ge$Text.Length){throw 'JSON_ARRAY'}
        if($Text[$Index.Value]-eq[char]0x2C){$Index.Value++;Skip-JsonWhitespace $Text $Index;continue}
        if($Text[$Index.Value]-eq[char]0x5D){$Index.Value++;return}
        throw 'JSON_ARRAY'
    }
    throw 'JSON_ARRAY'
}

function Read-StrictJson([string]$Path,[string]$Label) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length-ge3-and$bytes[0]-eq0xEF-and$bytes[1]-eq0xBB-and$bytes[2]-eq0xBF){throw ($Label+'_BOM')}
    try{$raw=$utf8Strict.GetString($bytes)}catch{throw ($Label+'_UTF8')}
    if($raw.Contains("`r")-or$raw.Contains([char]0)-or$raw.Contains([char]0xFFFD)-or-not$raw.EndsWith("`n")){throw ($Label+'_TEXT_FORMAT')}
    $cursor=0
    try{Read-JsonValue $raw ([ref]$cursor);Skip-JsonWhitespace $raw ([ref]$cursor);if($cursor-ne$raw.Length){throw 'JSON_TRAILING'}}catch{throw ($Label+'_'+[string]$_.Exception.Message)}
    try{$value=$raw|ConvertFrom-Json}catch{throw ($Label+'_JSON')}
    return [pscustomobject]@{Raw=$raw;Value=$value}
}

function Assert-ExactFields($Object,[string[]]$Fields,[string]$Reason) {
    if(-not($Object-is[pscustomobject])){throw $Reason}
    $names=@($Object.PSObject.Properties|ForEach-Object{$_.Name})
    if($names.Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$names}).Count-ne0){throw $Reason}
}

function Assert-Text($Value,[string]$Reason) {
    if(-not($Value-is[string])-or[string]::IsNullOrWhiteSpace([string]$Value)-or[string]$Value-cne([string]$Value).Trim()-or
       -not[string]::Equals([string]$Value,([string]$Value).Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)-or
       [regex]::IsMatch([string]$Value,'[\x00-\x08\x0B\x0C\x0E-\x1F]')){throw $Reason}
}

function Get-Root([string]$Path,[string]$Label) {
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){throw ($Label+'_MISSING')}
    $full=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath).TrimEnd('\')
    if((Get-Item -LiteralPath $full -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw ($Label+'_REPARSE')}
    return $full
}

function Resolve-ChildFile([string]$Root,[string[]]$Components,[string]$Label,[switch]$AllowMissing) {
    $current=$Root
    foreach($component in $Components){
        $current=Join-Path $current $component
        if(-not(Test-Path -LiteralPath $current)){
            if($AllowMissing-and$current-ceq(Join-Path $Root ([string]::Join('\',$Components)))){return $null}
            throw ($Label+'_MISSING')
        }
        if((Get-Item -LiteralPath $current -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw ($Label+'_REPARSE')}
    }
    if(-not(Test-Path -LiteralPath $current -PathType Leaf)){throw ($Label+'_NOT_FILE')}
    return $current
}

function Get-SealedReleaseCanonical([string]$Root,[string]$Version) {
    try{
        $versionPath=Resolve-ChildFile $Root @('framework','versions',$Version,'VERSION.json') 'VERSION'
        $manifestPath=Resolve-ChildFile $Root @('framework','versions',$Version,'RELEASE_MANIFEST.json') 'MANIFEST'
        $versionDoc=Read-StrictJson $versionPath 'VERSION';$manifestDoc=Read-StrictJson $manifestPath 'MANIFEST'
        $v=$versionDoc.Value;$m=$manifestDoc.Value
        Assert-ExactFields $v @('schemaVersion','version','lifecycle','releaseClass','consumable','baseline','projectPinEligible') 'VERSION_FIELDS'
        Assert-ExactFields $m @('schemaVersion','version','lifecycle','releaseClass','scope','algorithm','fileCount','totalBytes','canonical','baseline','sourceReview','sourceCandidate','releaseIntegration') 'MANIFEST_FIELDS'
        if(-not((Test-JsonInteger $v.schemaVersion)-and[int]$v.schemaVersion-eq1-and[string]$v.version-ceq$Version-and[string]$v.lifecycle-ceq'STABLE'-and$v.consumable-is[bool]-and[bool]$v.consumable-and$v.projectPinEligible-is[bool]-and[bool]$v.projectPinEligible-and
            (Test-JsonInteger $m.schemaVersion)-and[int]$m.schemaVersion-eq1-and[string]$m.version-ceq$Version-and[string]$m.lifecycle-ceq'STABLE'-and[string]$m.canonical-cmatch'^[A-F0-9]{64}$'-and[string]$m.sourceReview-ceq'APPROVED'-and-not[string]::IsNullOrWhiteSpace([string]$m.releaseIntegration)-and[string]$m.releaseIntegration-cne'PENDING')){return ''}
        $versionRoot=Split-Path -Parent $manifestPath
        $items=@(Get-ChildItem -LiteralPath $versionRoot -Recurse -Force)
        if(@($items|Where-Object{($_.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0}).Count-ne0){return ''}
        [string[]]$payload=@($items|Where-Object{-not$_.PSIsContainer-and$_.FullName-cne$manifestPath}|ForEach-Object{$_.FullName.Substring($versionRoot.Length+1).Replace('\','/')})
        [Array]::Sort($payload,[StringComparer]::Ordinal)
        $rows=@();[int64]$total=0
        foreach($relative in $payload){$full=Join-Path $versionRoot $relative;$identity=(Get-Identity $full).Split('|');$total+=[int64]$identity[0];$rows+=($relative+'|'+$identity[0]+'|'+$identity[1])}
        $sha=[Security.Cryptography.SHA256]::Create();$utf8=New-Object Text.UTF8Encoding($false)
        try{$canonical=([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes(($rows-join"`n"))))).Replace('-','')}finally{$sha.Dispose()}
        if([int]$m.fileCount-ne$payload.Count-or[int64]$m.totalBytes-ne$total-or[string]$m.canonical-cne$canonical){return ''}
        return $canonical
    }catch{return ''}
}

try {
    if($ExpectedProjectConfigIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'PROJECT_CONFIG_IDENTITY_FORMAT'}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedCorrectionsIdentity)-and$ExpectedCorrectionsIdentity-cnotmatch'^(?:MISSING|\d+\|[A-F0-9]{64})$'){throw 'CORRECTIONS_IDENTITY_FORMAT'}
    $project=Get-Root $ProjectRoot 'PROJECT_ROOT';$framework=Get-Root $FrameworkRoot 'FRAMEWORK_ROOT'
    $control=Resolve-ChildFile $project @('.ai-workspace','project.json') 'PROJECT_CONFIG'
    if((Get-Identity $control)-cne$ExpectedProjectConfigIdentity){throw 'PROJECT_CONFIG_DRIFT'}
    $configDoc=Read-StrictJson $control 'PROJECT_CONFIG';$config=$configDoc.Value
    if(-not(Test-JsonInteger $config.schemaVersion)-or[int]$config.schemaVersion-cnotin@(3,4)){throw 'PROJECT_CONFIG_SCHEMA'}
    $configFields=if([int]$config.schemaVersion-eq3){@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','routineExcludedPaths','frameworkCapabilities')}else{@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','routineExcludedPaths','frameworkCapabilities','frameworkTarget')}
    Assert-ExactFields $config $configFields 'PROJECT_CONFIG_FIELDS'
    Assert-Text $config.id 'PROJECT_ID'
    if($Operation-cne'PRECHECK'-and[string]$config.frameworkVersion-cne$TargetVersion){throw 'PROJECT_PIN_TARGET_MISMATCH'}

    $correctionsPath=Resolve-ChildFile $project @('.ai-workspace','corrections.json') 'CORRECTIONS' -AllowMissing:$AllowMissingCorrections
    $correctionsIdentity=if($null-eq$correctionsPath){'MISSING'}else{Get-Identity $correctionsPath}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedCorrectionsIdentity)-and$correctionsIdentity-cne$ExpectedCorrectionsIdentity){throw 'CORRECTIONS_DRIFT'}
    $records=@()
    if($null-ne$correctionsPath){
        $correctionsDoc=Read-StrictJson $correctionsPath 'CORRECTIONS';$corrections=$correctionsDoc.Value
        Assert-ExactFields $corrections @('schemaVersion','contractVersion','projectId','corrections') 'CORRECTIONS_FIELDS'
        if(-not(Test-JsonInteger $corrections.schemaVersion)-or[int]$corrections.schemaVersion-ne1-or[string]$corrections.contractVersion-cne'1.10.0'-or[string]$corrections.projectId-cne[string]$config.id-or-not($corrections.corrections-is[System.Array])){throw 'CORRECTIONS_VALUES'}
        $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($record in @($corrections.corrections)){
            Assert-ExactFields $record @('correctionId','introducedAgainstFramework','requirementReason','effectiveRule','applicability','decisionLocator') 'CORRECTION_FIELDS'
            if(-not($record.correctionId-is[string])-or[string]$record.correctionId-cnotmatch'^[A-Z][A-Z0-9_]*$'-or-not$ids.Add([string]$record.correctionId)){throw 'CORRECTION_ID'}
            foreach($field in @('introducedAgainstFramework','requirementReason','effectiveRule','applicability','decisionLocator')){Assert-Text $record.$field ('CORRECTION_TEXT|'+$field)}
            $records+=,$record
        }
    }

    $coverageStatus='UNAVAILABLE_RETAINED';$incorporatedSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal);$conflictSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    try{
        $coveragePath=Resolve-ChildFile $framework @('framework','versions','1.10.0','CORRECTION_COVERAGE.json') 'COVERAGE'
        $coverageDoc=Read-StrictJson $coveragePath 'COVERAGE';$coverage=$coverageDoc.Value
        Assert-ExactFields $coverage @('schemaVersion','releaseVersion','versions') 'COVERAGE_FIELDS'
        if(-not(Test-JsonInteger $coverage.schemaVersion)-or[int]$coverage.schemaVersion-ne1-or[string]$coverage.releaseVersion-cne'1.10.0'-or-not($coverage.versions-is[System.Array])){throw 'COVERAGE_VALUES'}
        $sourceCanonical=Get-SealedReleaseCanonical $framework ([string]$coverage.releaseVersion)
        if([string]::IsNullOrWhiteSpace($sourceCanonical)){throw 'COVERAGE_RELEASE_UNSEALED'}
        $versionSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal);$entry=$null;$previousVersion=$null
        $priorIncorporated=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($candidate in @($coverage.versions)){
            Assert-ExactFields $candidate @('version','releaseCanonical','incorporatedCorrectionIds','conflictingCorrectionIds') 'COVERAGE_ENTRY_FIELDS'
            Assert-Text $candidate.version 'COVERAGE_VERSION'
            if(-not$versionSet.Add([string]$candidate.version)){throw 'COVERAGE_VERSION_DUPLICATE'}
            try{$semanticVersion=[version][string]$candidate.version}catch{throw 'COVERAGE_VERSION_FORMAT'}
            if($null-ne$previousVersion-and$semanticVersion-le$previousVersion){throw 'COVERAGE_VERSION_ORDER'};$previousVersion=$semanticVersion
            if(-not($candidate.releaseCanonical-is[string])-or([string]$candidate.releaseCanonical-cne'SELF'-and[string]$candidate.releaseCanonical-cnotmatch'^[A-F0-9]{64}$')-or-not($candidate.incorporatedCorrectionIds-is[System.Array])-or-not($candidate.conflictingCorrectionIds-is[System.Array])){throw 'COVERAGE_ENTRY_VALUES'}
            if([string]$candidate.releaseCanonical-ceq'SELF'-and[string]$candidate.version-cne[string]$coverage.releaseVersion){throw 'COVERAGE_SELF_VERSION'}
            $local=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal);$localIncorporated=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal);$previousId=''
            foreach($id in @($candidate.incorporatedCorrectionIds)){if(-not($id-is[string])-or[string]$id-cnotmatch'^[A-Z][A-Z0-9_]*$'-or-not$local.Add([string]$id)-or-not$localIncorporated.Add([string]$id)-or($previousId-and[string]::CompareOrdinal($previousId,[string]$id)-ge0)){throw 'COVERAGE_ID'};$previousId=[string]$id}
            $previousId=''
            foreach($id in @($candidate.conflictingCorrectionIds)){if(-not($id-is[string])-or[string]$id-cnotmatch'^[A-Z][A-Z0-9_]*$'-or-not$local.Add([string]$id)-or($previousId-and[string]::CompareOrdinal($previousId,[string]$id)-ge0)){throw 'COVERAGE_ID'};$previousId=[string]$id}
            foreach($priorId in $priorIncorporated){if(-not$localIncorporated.Contains($priorId)){throw 'COVERAGE_NOT_CUMULATIVE'}}
            foreach($id in $localIncorporated){$null=$priorIncorporated.Add($id)}
            if([string]$candidate.version-ceq$TargetVersion){$entry=$candidate}
        }
        $targetCanonical=if($TargetVersion-ceq[string]$coverage.releaseVersion){$sourceCanonical}else{Get-SealedReleaseCanonical $framework $TargetVersion}
        $entryBound=$null-ne$entry-and-not[string]::IsNullOrWhiteSpace($targetCanonical)-and(([string]$entry.releaseCanonical-ceq'SELF'-and$TargetVersion-ceq[string]$coverage.releaseVersion)-or[string]$entry.releaseCanonical-ceq$targetCanonical)
        if($entryBound){
            foreach($id in @($entry.incorporatedCorrectionIds)){$null=$incorporatedSet.Add([string]$id)}
            foreach($id in @($entry.conflictingCorrectionIds)){$null=$conflictSet.Add([string]$id)}
            $coverageStatus='MATCHED'
        }
    }catch{$coverageStatus='INVALID_RETAINED'}

    $incorporated=@();$effective=@();$conflicts=@()
    foreach($record in $records){
        $item=[ordered]@{correctionId=[string]$record.correctionId;requirementReason=[string]$record.requirementReason;effectiveRule=[string]$record.effectiveRule;applicability=[string]$record.applicability;decisionLocator=[string]$record.decisionLocator}
        if($coverageStatus-ceq'MATCHED'-and$incorporatedSet.Contains([string]$record.correctionId)){$incorporated+=,[pscustomobject]$item}
        elseif($coverageStatus-ceq'MATCHED'-and$conflictSet.Contains([string]$record.correctionId)){$conflicts+=,[pscustomobject]$item}
        else{$effective+=,[pscustomobject]$item}
    }
    $status=if($conflicts.Count-ne0){'CONFLICT'}else{'PASS'}
    $result=[ordered]@{status=$status;operation=$Operation;projectId=[string]$config.id;targetVersion=$TargetVersion;correctionsIdentity=$correctionsIdentity;coverageStatus=$coverageStatus;incorporated=@($incorporated);stillEffective=@($effective);conflicts=@($conflicts)}
    if($AsJson){$result|ConvertTo-Json -Depth 8 -Compress}else{
        Write-Output ('PROJECT_CORRECTIONS|status='+$status+'|target='+$TargetVersion+'|coverage='+$coverageStatus+'|incorporated='+$incorporated.Count+'|effective='+$effective.Count+'|conflicts='+$conflicts.Count)
        foreach($item in $incorporated){Write-Output ('INCORPORATED|'+$item.correctionId)}
        foreach($item in $effective){Write-Output ('STILL_EFFECTIVE|'+$item.correctionId+'|reason='+$item.requirementReason)}
        foreach($item in $conflicts){Write-Output ('CONFLICT|'+$item.correctionId+'|reason='+$item.requirementReason)}
    }
    if($status-ceq'CONFLICT'){exit 3}
} catch {
    if($AsJson){[ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|'+[string]$_.Exception.Message)}
    exit 2
}
