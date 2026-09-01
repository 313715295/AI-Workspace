[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [Parameter(Mandatory = $true)][string]$ExpectedIndexIdentity,
    [Parameter(Mandatory = $true)][string[]]$ChangedAuthorityPath,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}
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

function ConvertTo-LiteralLocator([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)-or$Value-cne$Value.Trim()){throw 'LOCATOR_EMPTY_OR_WHITESPACE'}
    $path=$Value.Replace('\','/')
    if([regex]::IsMatch($path,'[<>"|?*]')-or[IO.Path]::IsPathRooted($path)-or$path.StartsWith('/')-or$path.Contains(':')){throw 'LOCATOR_NOT_LITERAL_RELATIVE'}
    if(-not[string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)){throw 'LOCATOR_NOT_NFC'}
    $parts=$path.Split('/')
    foreach($part in $parts){
        if([string]::IsNullOrEmpty($part)-or$part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or[regex]::IsMatch($part,'[\x00-\x1F]')){throw 'LOCATOR_COMPONENT_INVALID'}
        if($part.Split('.')[0]-match'^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw 'LOCATOR_RESERVED_NAME'}
    }
    return [string]::Join('/',$parts)
}

function Resolve-LiteralFile([string]$Root,[string]$Locator) {
    $relative=ConvertTo-LiteralLocator $Locator
    $full=[IO.Path]::GetFullPath((Join-Path $Root $relative))
    $back=[IO.Path]::GetRelativePath($Root,$full).Replace('\','/')
    if($back-ceq'..'-or$back.StartsWith('../')-or[IO.Path]::IsPathRooted($back)){throw 'LOCATOR_OUTSIDE_PROJECT'}
    $current=$Root
    foreach($part in $relative.Split('/')){
        $current=Join-Path $current $part
        if(-not(Test-Path -LiteralPath $current)){throw ('LOCATOR_MISSING|'+$relative)}
        if((Get-Item -LiteralPath $current -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw ('LOCATOR_REPARSE|'+$relative)}
    }
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw ('LOCATOR_NOT_FILE|'+$relative)}
    return $full
}

function Read-StrictJson([string]$Path,[string]$Label) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length-ge3-and$bytes[0]-eq0xEF-and$bytes[1]-eq0xBB-and$bytes[2]-eq0xBF){throw ($Label+'_BOM')}
    try{$raw=$utf8Strict.GetString($bytes)}catch{throw ($Label+'_UTF8')}
    if($raw.Contains("`r")-or$raw.Contains([char]0)-or$raw.Contains([char]0xFFFD)-or-not$raw.EndsWith("`n")){throw ($Label+'_TEXT_FORMAT')}
    $cursor=0
    try{Read-JsonValue $raw ([ref]$cursor);Skip-JsonWhitespace $raw ([ref]$cursor);if($cursor-ne$raw.Length){throw 'JSON_TRAILING'}}catch{throw ($Label+'_'+[string]$_.Exception.Message)}
    try{
        $command=Get-Command ConvertFrom-Json -ErrorAction Stop
        if($command.Parameters.ContainsKey('DateKind')){$value=$raw|ConvertFrom-Json -DateKind String}else{$value=$raw|ConvertFrom-Json}
    }catch{throw ($Label+'_JSON')}
    return $value
}

function Assert-ExactFields($Object,[string[]]$Fields,[string]$Reason) {
    if(-not($Object-is[pscustomobject])){throw $Reason}
    $names=@($Object.PSObject.Properties|ForEach-Object{$_.Name})
    if($names.Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$names}).Count-ne0){throw $Reason}
}

function Test-VerifiedAt($Value) {
    $parsed=[DateTimeOffset]::MinValue
    if(-not($Value-is[string])-or[string]$Value-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'){return $false}
    return [DateTimeOffset]::TryParse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)
}

try {
    if(-not(Test-Path -LiteralPath $ProjectRoot -PathType Container)){throw 'PROJECT_ROOT_MISSING'}
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).ProviderPath))
    if((Get-Item -LiteralPath $root -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'PROJECT_ROOT_REPARSE'}
    if($ExpectedProjectConfigIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'PROJECT_CONFIG_IDENTITY_FORMAT'}
    if($ExpectedIndexIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INDEX_IDENTITY_FORMAT'}

    $configPath=Resolve-LiteralFile $root '.ai-workspace/project.json'
    if((Get-Identity $configPath)-cne$ExpectedProjectConfigIdentity){throw 'PROJECT_CONFIG_IDENTITY_DRIFT'}
    $config=Read-StrictJson $configPath 'PROJECT_CONFIG'
    if(-not(Test-JsonInteger $config.schemaVersion)-or[int]$config.schemaVersion-notin@(3,4)){throw 'PROJECT_CONFIG_VALUES'}
    $configSchemaVersion=[int]$config.schemaVersion
    $configFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities');if($configSchemaVersion-eq4){$configFields+='processPolicy'}
    Assert-ExactFields $config $configFields 'PROJECT_CONFIG_FIELDS'
    if(-not($config.id-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.id)-or
       -not($config.displayName-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.displayName)-or-not($config.controlPlaneLayout-is[string])-or[string]$config.controlPlaneLayout-cne'repo-local'-or
       -not($config.repositoryRoot-is[string])-or[string]$config.repositoryRoot-cne'..'-or-not($config.frameworkVersion-is[string])-or[string]$config.frameworkVersion-cne'1.15.1'-or-not($config.frameworkToolBackend-is[string])-or[string]$config.frameworkToolBackend-cne'powershell7'-or
       -not($config.routineExcludedPaths-is[System.Array])-or-not($config.frameworkCapabilities-is[pscustomobject])){throw 'PROJECT_CONFIG_VALUES'}
    if($configSchemaVersion-eq4){Assert-ExactFields $config.processPolicy @('schemaVersion','locator') 'PROJECT_CONFIG_PROCESS_POLICY';if(-not(Test-JsonInteger $config.processPolicy.schemaVersion)-or[int]$config.processPolicy.schemaVersion-ne1-or-not($config.processPolicy.locator-is[string])-or[string]$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'){throw 'PROJECT_CONFIG_PROCESS_POLICY'}}
    Assert-ExactFields $config.frameworkCapabilities @('KNOWLEDGE_REFERENCE') 'CAPABILITY_FIELDS'
    $knowledge=$config.frameworkCapabilities.KNOWLEDGE_REFERENCE
    Assert-ExactFields $knowledge @('enabled','indexLocator') 'CAPABILITY_FIELDS'
    if(-not($knowledge.enabled-is[bool])-or-not[bool]$knowledge.enabled-or-not($knowledge.indexLocator-is[string])){throw 'KNOWLEDGE_CAPABILITY_UNAVAILABLE'}

    $indexLocator=ConvertTo-LiteralLocator ([string]$knowledge.indexLocator)
    $indexPath=Resolve-LiteralFile $root $indexLocator
    if((Get-Identity $indexPath)-cne$ExpectedIndexIdentity){throw 'INDEX_IDENTITY_DRIFT'}
    $index=Read-StrictJson $indexPath 'INDEX'
    Assert-ExactFields $index @('schemaVersion','projectId','entries') 'INDEX_FIELDS'
    if(-not(Test-JsonInteger $index.schemaVersion)-or[int]$index.schemaVersion-notin@(1,2)-or-not($index.projectId-is[string])-or[string]$index.projectId-cne[string]$config.id-or-not($index.entries-is[System.Array])){throw 'INDEX_VALUES'}
    $schemaVersion=[int]$index.schemaVersion
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $validatedEntries=@()
    foreach($entry in @($index.entries)){
        $fields=if($schemaVersion-eq1){@('id','state','title','summary','locator','identity','authorityLocator','authorityIdentity','verifiedAt','invalidatesOn','tokenEstimate')}else{@('id','state','title','summary','tags','locator','identity','authorityDependencies','verifiedAt','invalidatesOn','tokenEstimate')}
        Assert-ExactFields $entry $fields 'ENTRY_FIELDS'
        if(-not($entry.id-is[string])-or[string]$entry.id-cnotmatch'^[A-Z0-9][A-Z0-9._-]*$'-or
           -not($entry.state-is[string])-or[string]$entry.state-cnotin@('CURRENT','STALE','HISTORICAL')-or-not($entry.title-is[string])-or[string]::IsNullOrWhiteSpace([string]$entry.title)-or
           -not($entry.summary-is[string])-or[string]::IsNullOrWhiteSpace([string]$entry.summary)-or-not($entry.locator-is[string])-or-not($entry.identity-is[string])-or[string]$entry.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or
           -not(Test-VerifiedAt $entry.verifiedAt)-or-not($entry.invalidatesOn-is[System.Array])-or-not(Test-JsonInteger $entry.tokenEstimate)-or[int]$entry.tokenEstimate-lt1-or[int]$entry.tokenEstimate-gt4096){throw 'ENTRY_VALUES'}
        if(-not$ids.Add([string]$entry.id)){throw 'ENTRY_ID_DUPLICATE'}
        $null=ConvertTo-LiteralLocator ([string]$entry.locator)
        $dependencies=@()
        if($schemaVersion-eq1){
            if(-not($entry.authorityLocator-is[string])-or-not($entry.authorityIdentity-is[string])-or[string]$entry.authorityIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or
               @($entry.invalidatesOn).Count-ne2-or[string]$entry.invalidatesOn[0]-cne'LOCATOR_IDENTITY_CHANGE'-or[string]$entry.invalidatesOn[1]-cne'AUTHORITY_IDENTITY_CHANGE'){throw 'ENTRY_VALUES'}
            $dependencies+=@([pscustomobject][ordered]@{locator=ConvertTo-LiteralLocator ([string]$entry.authorityLocator);identity=[string]$entry.authorityIdentity})
        }else{
            if(-not($entry.tags-is[System.Array])-or@($entry.tags).Count-gt16-or-not($entry.authorityDependencies-is[System.Array])-or@($entry.authorityDependencies).Count-lt1-or@($entry.authorityDependencies).Count-gt16-or
               @($entry.invalidatesOn).Count-ne2-or[string]$entry.invalidatesOn[0]-cne'REFERENCE_IDENTITY_CHANGE'-or[string]$entry.invalidatesOn[1]-cne'AUTHORITY_DEPENDENCY_IDENTITY_CHANGE'){throw 'ENTRY_VALUES'}
            $tagSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach($tag in @($entry.tags)){if(-not($tag-is[string])-or[string]::IsNullOrWhiteSpace([string]$tag)-or-not$tagSet.Add([string]$tag)){throw 'ENTRY_TAGS'}}
            $dependencySet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach($dependency in @($entry.authorityDependencies)){
                Assert-ExactFields $dependency @('locator','identity') 'AUTHORITY_DEPENDENCY_FIELDS'
                if(-not($dependency.locator-is[string])-or-not($dependency.identity-is[string])-or[string]$dependency.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'AUTHORITY_DEPENDENCY_FIELDS'}
                $dependencyLocator=ConvertTo-LiteralLocator ([string]$dependency.locator)
                if(-not$dependencySet.Add($dependencyLocator)){throw 'AUTHORITY_DEPENDENCY_DUPLICATE'}
                $dependencies+=@([pscustomobject][ordered]@{locator=$dependencyLocator;identity=[string]$dependency.identity})
            }
        }
        $validatedEntries+=@([pscustomobject][ordered]@{id=[string]$entry.id;dependencies=$dependencies})
    }

    $changed=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $ChangedAuthorityPath){$normalized=ConvertTo-LiteralLocator $path;if(-not$changed.Add($normalized)){throw 'CHANGED_PATH_DUPLICATE'}}
    if($changed.Count-eq0){throw 'CHANGED_PATH_EMPTY'}
    $results=@();$direct=@();$unknown=@()
    foreach($entry in $validatedEntries){
        $entryDirect=$false;$entryUnknown=$false
        foreach($dependency in @($entry.dependencies)){
            if($changed.Contains([string]$dependency.locator)){$entryDirect=$true}
            try{$full=Resolve-LiteralFile $root ([string]$dependency.locator);if((Get-Identity $full)-cne[string]$dependency.identity){$entryUnknown=$true}}catch{if([string]$_.Exception.Message-like'LOCATOR_REPARSE|*'){throw};$entryUnknown=$true}
        }
        $status=if($entryDirect){'DIRECT_AFFECTED'}elseif($entryUnknown){'UNKNOWN'}else{'NONE_DIRECT'}
        if($status-ceq'DIRECT_AFFECTED'){$direct+=([string]$entry.id)}elseif($status-ceq'UNKNOWN'){$unknown+=([string]$entry.id)}
        $results+=@([pscustomobject][ordered]@{id=[string]$entry.id;status=$status})
    }
    $overall=if($unknown.Count-gt0){'UNKNOWN'}elseif($direct.Count-gt0){'DIRECT_AFFECTED'}else{'NONE_DIRECT'}
    $result=[pscustomobject][ordered]@{status=$overall;scope='DECLARED_DIRECT_AUTHORITY_DEPENDENCIES';changedPaths=@($changed);affectedIds=$direct;unknownIds=$unknown;entries=$results;writes=$false}
    if($AsJson){$result|ConvertTo-Json -Depth 8 -Compress}else{Write-Output('PASS|knowledge-impact|status='+$overall+'|affected='+($direct-join','))}
    exit 0
}catch{
    $result=[pscustomobject][ordered]@{status='UNKNOWN';reason=[string]$_.Exception.Message;scope='DECLARED_DIRECT_AUTHORITY_DEPENDENCIES';affectedIds=@();unknownIds=@();entries=@();writes=$false}
    if($AsJson){$result|ConvertTo-Json -Depth 8 -Compress}else{Write-Output('FAIL|knowledge-impact|'+[string]$_.Exception.Message)}
    exit 3
}
