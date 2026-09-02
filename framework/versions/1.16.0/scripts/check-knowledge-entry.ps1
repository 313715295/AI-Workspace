[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [Parameter(Mandatory = $true)][string]$ExpectedIndexIdentity,
    [ValidateSet('DISCOVER','QUERY')][string]$Operation,
    [string[]]$EntryId,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}
$utf8Strict = New-Object Text.UTF8Encoding($false,$true)
$entryIdWasBound = $PSBoundParameters.ContainsKey('EntryId')
$mode = if ($PSBoundParameters.ContainsKey('Operation')) { $Operation } elseif ($entryIdWasBound) { 'QUERY' } else { 'DISCOVER' }

function Get-Identity([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path);$sha=[Security.Cryptography.SHA256]::Create()
    try{return $bytes.Length.ToString()+'|'+([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}
    finally{$sha.Dispose()}
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
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
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) { throw 'LOCATOR_EMPTY_OR_WHITESPACE' }
    $path=$Value.Replace('\','/')
    if ([regex]::IsMatch($path,'[<>"|?*]') -or [IO.Path]::IsPathRooted($path) -or $path.StartsWith('/') -or $path.Contains(':')) { throw 'LOCATOR_NOT_LITERAL_RELATIVE' }
    if (-not [string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw 'LOCATOR_NOT_NFC' }
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
        if(-not(Test-Path -LiteralPath $current)){throw "LOCATOR_MISSING|$relative"}
        if((Get-Item -LiteralPath $current -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw "LOCATOR_REPARSE|$relative"}
    }
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "LOCATOR_NOT_FILE|$relative"}
    return $full
}

function Read-StrictJson([string]$Path,[string]$Label) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length-ge3-and$bytes[0]-eq0xEF-and$bytes[1]-eq0xBB-and$bytes[2]-eq0xBF){throw ($Label+'_BOM')}
    $raw=$utf8Strict.GetString($bytes)
    if($raw.Contains("`r")-or$raw.Contains([char]0)-or$raw.Contains([char]0xFFFD)-or-not$raw.EndsWith("`n")){throw ($Label+'_TEXT_FORMAT')}
    $cursor=0
    try{Read-JsonValue $raw ([ref]$cursor);Skip-JsonWhitespace $raw ([ref]$cursor);if($cursor-ne$raw.Length){throw 'JSON_TRAILING'}}catch{throw ($Label+'_'+[string]$_.Exception.Message)}
    try{
        $convertCommand=Get-Command ConvertFrom-Json -ErrorAction Stop
        if($convertCommand.Parameters.ContainsKey('DateKind')){$value=$raw|ConvertFrom-Json -DateKind String}else{$value=$raw|ConvertFrom-Json}
    }catch{throw ($Label+'_JSON')}
    return [pscustomobject]@{Raw=$raw;Value=$value}
}

function Write-KnowledgeUnavailable([string]$Reason) {
    $result=[pscustomobject][ordered]@{status='KNOWLEDGE_UNAVAILABLE';reason=$Reason;operation=$mode;referenceOnly=$true;authority=$false;entries=@()}
    if($AsJson){$result|ConvertTo-Json -Depth 10 -Compress}else{Write-Output("KNOWLEDGE_UNAVAILABLE|reason="+$Reason)}
    exit 3
}

function Test-VerifiedAt($Value) {
    $parsed=[DateTimeOffset]::MinValue
    if(-not($Value-is[string])-or[string]$Value-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'){return $false}
    return [DateTimeOffset]::TryParse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)
}

try {
    if(-not(Test-Path -LiteralPath $ProjectRoot -PathType Container)){Write-KnowledgeUnavailable 'PROJECT_ROOT_MISSING'}
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).ProviderPath))
    if((Get-Item -LiteralPath $root -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){Write-KnowledgeUnavailable 'PROJECT_ROOT_REPARSE'}
    try{$configPath=Resolve-LiteralFile $root '.ai-workspace/project.json'}catch{Write-KnowledgeUnavailable ([string]$_.Exception.Message)}
    if($ExpectedProjectConfigIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-Identity $configPath)-cne$ExpectedProjectConfigIdentity){Write-KnowledgeUnavailable 'PROJECT_CONFIG_IDENTITY_DRIFT'}
    $configDocument=Read-StrictJson $configPath 'PROJECT_CONFIG';$config=$configDocument.Value;$configRaw=$configDocument.Raw
    if(-not(Test-JsonInteger $config.schemaVersion)-or[int]$config.schemaVersion-notin@(3,4)){Write-KnowledgeUnavailable 'PROJECT_CONFIG_VALUES'}
    $configSchemaVersion=[int]$config.schemaVersion
    $configFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities');if($configSchemaVersion-eq4){$configFields+='processPolicy'};$configNames=@($config.PSObject.Properties|ForEach-Object{$_.Name})
    if(-not($config-is[pscustomobject])-or$configNames.Count-ne$configFields.Count-or@($configFields|Where-Object{$_-cnotin$configNames}).Count-ne0){Write-KnowledgeUnavailable 'PROJECT_CONFIG_FIELDS'}
    foreach($field in @($configFields|Where-Object{$_-cne'schemaVersion'})){if([regex]::Matches($configRaw,'"'+[regex]::Escape($field)+'"\s*:').Count-ne1){Write-KnowledgeUnavailable ('PROJECT_CONFIG_DUPLICATE_FIELD|'+$field)}}
    $expectedSchemaFieldCount=if($configSchemaVersion-eq4){2}else{1};if([regex]::Matches($configRaw,'"schemaVersion"\s*:').Count-ne$expectedSchemaFieldCount){Write-KnowledgeUnavailable 'PROJECT_CONFIG_DUPLICATE_FIELD|schemaVersion'}
    if(-not($config.id-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.id)-or-not($config.displayName-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.displayName)-or-not($config.controlPlaneLayout-is[string])-or[string]$config.controlPlaneLayout-cne'repo-local'-or-not($config.repositoryRoot-is[string])-or[string]$config.repositoryRoot-cne'..'-or-not($config.frameworkVersion-is[string])-or[string]$config.frameworkVersion-cne'1.16.0'-or-not($config.frameworkToolBackend-is[string])-or[string]$config.frameworkToolBackend-cne'powershell7'-or-not($config.routineExcludedPaths-is[System.Array])-or-not($config.frameworkCapabilities-is[pscustomobject])){Write-KnowledgeUnavailable 'PROJECT_CONFIG_VALUES'}
    if($configSchemaVersion-eq4){$policy=$config.processPolicy;$policyFields=@($policy.PSObject.Properties|ForEach-Object{$_.Name});if(-not($policy-is[pscustomobject])-or$policyFields.Count-ne2-or$policyFields-cnotcontains'schemaVersion'-or$policyFields-cnotcontains'locator'-or-not(Test-JsonInteger $policy.schemaVersion)-or[int]$policy.schemaVersion-ne1-or-not($policy.locator-is[string])-or[string]$policy.locator-cne'.ai-workspace/process-policy.json'-or[regex]::Matches($configRaw,'"locator"\s*:').Count-ne1){Write-KnowledgeUnavailable 'PROJECT_CONFIG_PROCESS_POLICY'}}
    $capabilityNames=@($config.frameworkCapabilities.PSObject.Properties|ForEach-Object{$_.Name})
    if($capabilityNames.Count-eq0){Write-KnowledgeUnavailable 'CAPABILITY_DISABLED'}
    if($capabilityNames.Count-ne1-or$capabilityNames[0]-cne'KNOWLEDGE_REFERENCE'-or[regex]::Matches($configRaw,'"KNOWLEDGE_REFERENCE"\s*:').Count-ne1){Write-KnowledgeUnavailable 'CAPABILITY_UNKNOWN_OR_DUPLICATE'}
    $knowledge=$config.frameworkCapabilities.KNOWLEDGE_REFERENCE
    if(-not($knowledge-is[pscustomobject])){Write-KnowledgeUnavailable 'CAPABILITY_FIELDS'}
    $capabilityFields=@($knowledge.PSObject.Properties|ForEach-Object{$_.Name})
    if($capabilityFields.Count-eq1-and$capabilityFields[0]-ceq'enabled'-and$knowledge.enabled-is[bool]-and-not[bool]$knowledge.enabled){Write-KnowledgeUnavailable 'CAPABILITY_DISABLED'}
    if($capabilityFields.Count-ne2-or$capabilityFields-cnotcontains'enabled'-or$capabilityFields-cnotcontains'indexLocator'-or-not($knowledge.enabled-is[bool])-or-not[bool]$knowledge.enabled-or-not($knowledge.indexLocator-is[string])-or[regex]::Matches($configRaw,'"enabled"\s*:').Count-ne1-or[regex]::Matches($configRaw,'"indexLocator"\s*:').Count-ne1){Write-KnowledgeUnavailable 'CAPABILITY_FIELDS'}
    $indexLocator=ConvertTo-LiteralLocator ([string]$knowledge.indexLocator)
    try{$indexPath=Resolve-LiteralFile $root $indexLocator}catch{Write-KnowledgeUnavailable ([string]$_.Exception.Message)}
    if($ExpectedIndexIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-Identity $indexPath)-cne$ExpectedIndexIdentity){Write-KnowledgeUnavailable 'INDEX_IDENTITY_DRIFT'}
    $document=Read-StrictJson $indexPath 'INDEX';$index=$document.Value
    $rootFields=@('schemaVersion','projectId','entries');$rootNames=@($index.PSObject.Properties|ForEach-Object{$_.Name})
    if(-not($index-is[pscustomobject])-or$rootNames.Count-ne$rootFields.Count-or@($rootFields|Where-Object{$_-cnotin$rootNames}).Count-ne0){Write-KnowledgeUnavailable 'INDEX_FIELDS'}
    if(-not(Test-JsonInteger $index.schemaVersion)-or[int]$index.schemaVersion-notin@(1,2)-or-not($index.projectId-is[string])-or[string]$index.projectId-cne[string]$config.id-or-not($index.entries-is[System.Array])){Write-KnowledgeUnavailable 'INDEX_VALUES'}
    $schemaVersion=[int]$index.schemaVersion
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $entries=@()
    foreach($entry in @($index.entries)){
        if(-not($entry-is[pscustomobject])){Write-KnowledgeUnavailable 'ENTRY_FIELDS'}
        if($schemaVersion-eq1){
            $fields=@('id','state','title','summary','locator','identity','authorityLocator','authorityIdentity','verifiedAt','invalidatesOn','tokenEstimate')
        }else{
            $fields=@('id','state','title','summary','tags','locator','identity','authorityDependencies','verifiedAt','invalidatesOn','tokenEstimate')
        }
        $names=@($entry.PSObject.Properties|ForEach-Object{$_.Name})
        if($names.Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$names}).Count-ne0){Write-KnowledgeUnavailable 'ENTRY_FIELDS'}
        if(-not($entry.id-is[string])-or[string]$entry.id-cnotmatch'^[A-Z0-9][A-Z0-9._-]*$'-or-not$ids.Add([string]$entry.id)-or
           -not($entry.state-is[string])-or[string]$entry.state-cnotin@('CURRENT','STALE','HISTORICAL')-or
           -not($entry.title-is[string])-or[string]::IsNullOrWhiteSpace([string]$entry.title)-or
           -not($entry.summary-is[string])-or[string]::IsNullOrWhiteSpace([string]$entry.summary)-or
           -not($entry.locator-is[string])-or-not($entry.identity-is[string])-or[string]$entry.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or
           -not(Test-VerifiedAt $entry.verifiedAt)-or-not($entry.invalidatesOn-is[System.Array])-or
           -not(Test-JsonInteger $entry.tokenEstimate)-or[int]$entry.tokenEstimate-lt1-or[int]$entry.tokenEstimate-gt4096){Write-KnowledgeUnavailable 'ENTRY_VALUES'}
        try{$referenceLocator=ConvertTo-LiteralLocator ([string]$entry.locator)}catch{Write-KnowledgeUnavailable 'ENTRY_LOCATOR'}
        $dependencies=@();$tags=@()
        if($schemaVersion-eq1){
            if(-not($entry.authorityLocator-is[string])-or-not($entry.authorityIdentity-is[string])-or[string]$entry.authorityIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or
               @($entry.invalidatesOn).Count-ne2-or[string]$entry.invalidatesOn[0]-cne'LOCATOR_IDENTITY_CHANGE'-or[string]$entry.invalidatesOn[1]-cne'AUTHORITY_IDENTITY_CHANGE'){Write-KnowledgeUnavailable 'ENTRY_VALUES'}
            try{$authorityLocator=ConvertTo-LiteralLocator ([string]$entry.authorityLocator)}catch{Write-KnowledgeUnavailable 'AUTHORITY_LOCATOR'}
            $dependencies+=@([pscustomobject][ordered]@{locator=$authorityLocator;identity=[string]$entry.authorityIdentity})
        }else{
            if(-not($entry.tags-is[System.Array])-or@($entry.tags).Count-gt16-or-not($entry.authorityDependencies-is[System.Array])-or@($entry.authorityDependencies).Count-lt1-or@($entry.authorityDependencies).Count-gt16-or
               @($entry.invalidatesOn).Count-ne2-or[string]$entry.invalidatesOn[0]-cne'REFERENCE_IDENTITY_CHANGE'-or[string]$entry.invalidatesOn[1]-cne'AUTHORITY_DEPENDENCY_IDENTITY_CHANGE'){Write-KnowledgeUnavailable 'ENTRY_VALUES'}
            $tagSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach($tag in @($entry.tags)){if(-not($tag-is[string])-or[string]::IsNullOrWhiteSpace([string]$tag)-or-not$tagSet.Add([string]$tag)){Write-KnowledgeUnavailable 'ENTRY_TAGS'};$tags+=([string]$tag)}
            $dependencySet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach($dependency in @($entry.authorityDependencies)){
                $dependencyNames=@($dependency.PSObject.Properties|ForEach-Object{$_.Name})
                if(-not($dependency-is[pscustomobject])-or$dependencyNames.Count-ne2-or$dependencyNames-cnotcontains'locator'-or$dependencyNames-cnotcontains'identity'-or-not($dependency.locator-is[string])-or-not($dependency.identity-is[string])-or[string]$dependency.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){Write-KnowledgeUnavailable 'AUTHORITY_DEPENDENCY_FIELDS'}
                try{$dependencyLocator=ConvertTo-LiteralLocator ([string]$dependency.locator)}catch{Write-KnowledgeUnavailable 'AUTHORITY_LOCATOR'}
                if(-not$dependencySet.Add($dependencyLocator)){Write-KnowledgeUnavailable 'AUTHORITY_DEPENDENCY_DUPLICATE'}
                $dependencies+=@([pscustomobject][ordered]@{locator=$dependencyLocator;identity=[string]$dependency.identity})
            }
        }
        $entries+=@([pscustomobject][ordered]@{id=[string]$entry.id;state=[string]$entry.state;title=[string]$entry.title;summary=[string]$entry.summary;tags=$tags;locator=$referenceLocator;identity=[string]$entry.identity;authorityDependencies=$dependencies;verifiedAt=[string]$entry.verifiedAt;tokenEstimate=[int]$entry.tokenEstimate})
    }
    $entries=@($entries|Sort-Object -Property id)
    if($mode-ceq'DISCOVER'){
        if($entryIdWasBound){Write-KnowledgeUnavailable 'DISCOVER_ENTRY_ID_FORBIDDEN'}
        $catalog=@($entries|ForEach-Object{[pscustomobject][ordered]@{id=$_.id;title=$_.title;tags=$_.tags;state=$_.state;locator=$_.locator;authorityLocators=@($_.authorityDependencies|ForEach-Object{$_.locator});verifiedAt=$_.verifiedAt}})
        $result=[pscustomobject][ordered]@{status='KNOWLEDGE_CATALOG';reason='INDEX_METADATA_VERIFIED';operation='DISCOVER';referenceOnly=$true;authority=$false;projectConfigIdentity=$ExpectedProjectConfigIdentity;indexLocator=$indexLocator;indexIdentity=$ExpectedIndexIdentity;maxQueries=3;entries=$catalog}
        if($AsJson){$result|ConvertTo-Json -Depth 10 -Compress}else{Write-Output('PASS|knowledge-discover|entries='+$catalog.Count)}
        exit 0
    }
    if(-not$entryIdWasBound-or$null-eq$EntryId){Write-KnowledgeUnavailable 'ENTRY_ID_EMPTY'}
    $requestedIds=@($EntryId)
    if($requestedIds.Count-lt1){Write-KnowledgeUnavailable 'ENTRY_ID_EMPTY'}
    if($requestedIds.Count-gt3){Write-KnowledgeUnavailable 'ENTRY_ID_LIMIT'}
    $requested=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($requestedId in $requestedIds){
        if(-not($requestedId-is[string])){Write-KnowledgeUnavailable 'ENTRY_ID_TYPE'}
        if([string]::IsNullOrWhiteSpace([string]$requestedId)-or[string]$requestedId-cnotmatch'^[A-Z0-9][A-Z0-9._-]*$'){Write-KnowledgeUnavailable 'ENTRY_ID_INVALID'}
        if(-not$requested.Add([string]$requestedId)){Write-KnowledgeUnavailable 'ENTRY_ID_DUPLICATE'}
    }
    $selected=@($entries|Where-Object{$requested.Contains([string]$_.id)})
    if($selected.Count-ne$requested.Count){Write-KnowledgeUnavailable 'ENTRY_ID_UNKNOWN'}
    $queryResults=@()
    foreach($entry in $selected){
        if($entry.state-cne'CURRENT'){$queryResults+=@([pscustomobject][ordered]@{id=$entry.id;title=$entry.title;status='UNAVAILABLE';reason='ENTRY_NOT_CURRENT'});continue}
        $reason=$null
        try{$referencePath=Resolve-LiteralFile $root $entry.locator;if((Get-Identity $referencePath)-cne$entry.identity){$reason='ENTRY_IDENTITY_DRIFT'}}catch{$reason=[string]$_.Exception.Message}
        if($null-eq$reason){
            foreach($dependency in @($entry.authorityDependencies)){
                try{$authorityPath=Resolve-LiteralFile $root $dependency.locator;if((Get-Identity $authorityPath)-cne$dependency.identity){$reason='AUTHORITY_CONFLICT|'+$dependency.locator;break}}
                catch{$reason=[string]$_.Exception.Message;break}
            }
        }
        if($null-ne$reason){$queryResults+=@([pscustomobject][ordered]@{id=$entry.id;title=$entry.title;status='UNAVAILABLE';reason=$reason});continue}
        $queryResults+=@([pscustomobject][ordered]@{id=$entry.id;title=$entry.title;status='AVAILABLE';locator=$entry.locator;identity=$entry.identity;authorityDependencies=$entry.authorityDependencies;verifiedAt=$entry.verifiedAt})
    }
    $result=[pscustomobject][ordered]@{status='KNOWLEDGE_QUERY_RESULT';reason='REQUEST_SCOPE_VERIFIED';operation='QUERY';referenceOnly=$true;authority=$false;projectConfigIdentity=$ExpectedProjectConfigIdentity;indexLocator=$indexLocator;indexIdentity=$ExpectedIndexIdentity;maxEntries=3;entries=$queryResults}
    if($AsJson){$result|ConvertTo-Json -Depth 10 -Compress}else{$availableCount=@($queryResults|Where-Object{$_.status-ceq'AVAILABLE'}).Count;Write-Output('PASS|knowledge-query|entries='+$queryResults.Count+'|available='+$availableCount)}
    exit 0
} catch {
    Write-KnowledgeUnavailable ([string]$_.Exception.Message)
}
