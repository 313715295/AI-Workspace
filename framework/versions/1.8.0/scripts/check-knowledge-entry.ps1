[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [Parameter(Mandatory = $true)][string]$ExpectedIndexIdentity,
    [object]$EntryId,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8Strict = New-Object Text.UTF8Encoding($false,$true)
$entryIdWasBound = $PSBoundParameters.ContainsKey('EntryId')

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
    $full=[IO.Path]::GetFullPath((Join-Path $Root $relative.Replace('/','\')))
    if(-not$full.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'LOCATOR_OUTSIDE_PROJECT'}
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
    try{
        $convertCommand=Get-Command ConvertFrom-Json -ErrorAction Stop
        if($convertCommand.Parameters.ContainsKey('DateKind')){$value=$raw|ConvertFrom-Json -DateKind String}else{$value=$raw|ConvertFrom-Json}
    }catch{throw ($Label+'_JSON')}
    return [pscustomobject]@{Raw=$raw;Value=$value}
}

function Write-ReferenceUnavailable([string]$Reason) {
    $result=[pscustomobject][ordered]@{status='REFERENCE_UNAVAILABLE';reason=$Reason;referenceOnly=$true;authority=$false;entries=@()}
    if($AsJson){$result|ConvertTo-Json -Depth 8 -Compress}else{Write-Output("REFERENCE_UNAVAILABLE|reason="+$Reason)}
    exit 3
}

try {
    if(-not(Test-Path -LiteralPath $ProjectRoot -PathType Container)){Write-ReferenceUnavailable 'PROJECT_ROOT_MISSING'}
    $root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).ProviderPath).TrimEnd('\')
    if((Get-Item -LiteralPath $root -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){Write-ReferenceUnavailable 'PROJECT_ROOT_REPARSE'}
    try{$configPath=Resolve-LiteralFile $root '.ai-workspace/project.json'}catch{Write-ReferenceUnavailable ([string]$_.Exception.Message)}
    if($ExpectedProjectConfigIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-Identity $configPath)-cne$ExpectedProjectConfigIdentity){Write-ReferenceUnavailable 'PROJECT_CONFIG_IDENTITY_DRIFT'}
    $configDocument=Read-StrictJson $configPath 'PROJECT_CONFIG';$config=$configDocument.Value;$configRaw=$configDocument.Raw
    $configFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','routineExcludedPaths','frameworkCapabilities');$configNames=@($config.PSObject.Properties|ForEach-Object{$_.Name})
    if(-not($config-is[pscustomobject])-or$configNames.Count-ne$configFields.Count-or@($configFields|Where-Object{$_-cnotin$configNames}).Count-ne0){Write-ReferenceUnavailable 'PROJECT_CONFIG_FIELDS'}
    foreach($field in $configFields){if([regex]::Matches($configRaw,'"'+[regex]::Escape($field)+'"\s*:').Count-ne1){Write-ReferenceUnavailable ('PROJECT_CONFIG_DUPLICATE_FIELD|'+$field)}}
    if(-not(Test-JsonInteger $config.schemaVersion)-or[int]$config.schemaVersion-ne3-or-not($config.id-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.id)-or-not($config.displayName-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.displayName)-or-not($config.controlPlaneLayout-is[string])-or[string]$config.controlPlaneLayout-cne'repo-local'-or-not($config.repositoryRoot-is[string])-or[string]$config.repositoryRoot-cne'..'-or-not($config.frameworkVersion-is[string])-or[string]$config.frameworkVersion-cne'1.8.0'-or-not($config.routineExcludedPaths-is[System.Array])-or-not($config.frameworkCapabilities-is[pscustomobject])){Write-ReferenceUnavailable 'PROJECT_CONFIG_VALUES'}
    $capabilityNames=@($config.frameworkCapabilities.PSObject.Properties|ForEach-Object{$_.Name})
    if($capabilityNames.Count-eq0){Write-ReferenceUnavailable 'CAPABILITY_DISABLED'}
    if($capabilityNames.Count-ne1-or$capabilityNames[0]-cne'KNOWLEDGE_REFERENCE'-or[regex]::Matches($configRaw,'"KNOWLEDGE_REFERENCE"\s*:').Count-ne1){Write-ReferenceUnavailable 'CAPABILITY_UNKNOWN_OR_DUPLICATE'}
    $knowledge=$config.frameworkCapabilities.KNOWLEDGE_REFERENCE
    if(-not($knowledge-is[pscustomobject])){Write-ReferenceUnavailable 'CAPABILITY_FIELDS'}
    $capabilityFields=@($knowledge.PSObject.Properties|ForEach-Object{$_.Name})
    if($capabilityFields.Count-eq1-and$capabilityFields[0]-ceq'enabled'-and$knowledge.enabled-is[bool]-and-not[bool]$knowledge.enabled){Write-ReferenceUnavailable 'CAPABILITY_DISABLED'}
    if($capabilityFields.Count-ne2-or$capabilityFields-cnotcontains'enabled'-or$capabilityFields-cnotcontains'indexLocator'-or-not($knowledge.enabled-is[bool])-or-not[bool]$knowledge.enabled-or-not($knowledge.indexLocator-is[string])-or[regex]::Matches($configRaw,'"enabled"\s*:').Count-ne1-or[regex]::Matches($configRaw,'"indexLocator"\s*:').Count-ne1){Write-ReferenceUnavailable 'CAPABILITY_FIELDS'}
    $indexLocator=ConvertTo-LiteralLocator ([string]$knowledge.indexLocator)
    try{$indexPath=Resolve-LiteralFile $root $indexLocator}catch{Write-ReferenceUnavailable ([string]$_.Exception.Message)}
    if($ExpectedIndexIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-Identity $indexPath)-cne$ExpectedIndexIdentity){Write-ReferenceUnavailable 'INDEX_IDENTITY_DRIFT'}
    $document=Read-StrictJson $indexPath 'INDEX';$index=$document.Value
    $rootFields=@('schemaVersion','projectId','entries');$rootNames=@($index.PSObject.Properties|ForEach-Object{$_.Name})
    if(-not($index-is[pscustomobject])-or$rootNames.Count-ne$rootFields.Count-or@($rootFields|Where-Object{$_-cnotin$rootNames}).Count-ne0){Write-ReferenceUnavailable 'INDEX_FIELDS'}
    if(-not(Test-JsonInteger $index.schemaVersion)-or[int]$index.schemaVersion-ne1-or-not($index.projectId-is[string])-or[string]$index.projectId-cne[string]$config.id-or-not($index.entries-is[System.Array])){Write-ReferenceUnavailable 'INDEX_VALUES'}
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $current=@()
    foreach($entry in @($index.entries)){
        $fields=@('id','state','title','summary','locator','identity','authorityLocator','authorityIdentity','verifiedAt','invalidatesOn','tokenEstimate');$names=@($entry.PSObject.Properties|ForEach-Object{$_.Name})
        if(-not($entry-is[pscustomobject])-or$names.Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$names}).Count-ne0){Write-ReferenceUnavailable 'ENTRY_FIELDS'}
        $verifiedAtValue=[DateTimeOffset]::MinValue;$verifiedAtValid=$entry.verifiedAt-is[string]-and[string]$entry.verifiedAt-cmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'
        if($verifiedAtValid){$verifiedAtValid=[DateTimeOffset]::TryParse([string]$entry.verifiedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$verifiedAtValue)}
        if(-not($entry.id-is[string])-or[string]$entry.id-cnotmatch'^[A-Z0-9][A-Z0-9._-]*$'-or-not$ids.Add([string]$entry.id)-or
           -not($entry.state-is[string])-or[string]$entry.state-cnotin@('CURRENT','STALE','HISTORICAL')-or
           -not($entry.title-is[string])-or[string]::IsNullOrWhiteSpace([string]$entry.title)-or
           -not($entry.summary-is[string])-or[string]::IsNullOrWhiteSpace([string]$entry.summary)-or
           -not($entry.locator-is[string])-or[string]::IsNullOrEmpty([string]$entry.locator)-or-not($entry.authorityLocator-is[string])-or[string]::IsNullOrEmpty([string]$entry.authorityLocator)-or
           -not($entry.identity-is[string])-or[string]$entry.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or
           -not($entry.authorityIdentity-is[string])-or[string]$entry.authorityIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or
           -not$verifiedAtValid-or
           -not($entry.invalidatesOn-is[System.Array])-or@($entry.invalidatesOn).Count-ne2-or[string]$entry.invalidatesOn[0]-cne'LOCATOR_IDENTITY_CHANGE'-or[string]$entry.invalidatesOn[1]-cne'AUTHORITY_IDENTITY_CHANGE'-or
           -not(Test-JsonInteger $entry.tokenEstimate)-or[int]$entry.tokenEstimate-lt1-or[int]$entry.tokenEstimate-gt4096){Write-ReferenceUnavailable 'ENTRY_VALUES'}
        if([string]$entry.state-cne'CURRENT'){continue}
        try{$referencePath=Resolve-LiteralFile $root ([string]$entry.locator);$authorityPath=Resolve-LiteralFile $root ([string]$entry.authorityLocator)}catch{Write-ReferenceUnavailable ([string]$_.Exception.Message)}
        if((Get-Identity $referencePath)-cne[string]$entry.identity){Write-ReferenceUnavailable ('ENTRY_IDENTITY_DRIFT|'+[string]$entry.id)}
        if((Get-Identity $authorityPath)-cne[string]$entry.authorityIdentity){Write-ReferenceUnavailable ('AUTHORITY_CONFLICT|'+[string]$entry.id)}
        $current+=[pscustomobject][ordered]@{id=[string]$entry.id;title=[string]$entry.title;summary=[string]$entry.summary;locator=[string]$entry.locator;identity=[string]$entry.identity;authorityLocator=[string]$entry.authorityLocator;authorityIdentity=[string]$entry.authorityIdentity;verifiedAt=[string]$entry.verifiedAt;tokenEstimate=[int]$entry.tokenEstimate}
    }
    if($current.Count-eq0){Write-ReferenceUnavailable 'EMPTY_INDEX'}
    $requested=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $requestedIds=@()
    if($entryIdWasBound){
        if($null-eq$EntryId){Write-ReferenceUnavailable 'ENTRY_ID_EMPTY'}
        $requestedIds=@($EntryId)
        if($requestedIds.Count-eq0){Write-ReferenceUnavailable 'ENTRY_ID_EMPTY'}
        if($requestedIds.Count-gt3){Write-ReferenceUnavailable 'ENTRY_ID_LIMIT'}
    }
    foreach($requestedId in $requestedIds){
        if(-not($requestedId-is[string])){Write-ReferenceUnavailable 'ENTRY_ID_TYPE'}
        if([string]::IsNullOrWhiteSpace($requestedId)-or$requestedId-cnotmatch'^[A-Z0-9][A-Z0-9._-]*$'){Write-ReferenceUnavailable 'ENTRY_ID_INVALID'}
        if(-not$requested.Add($requestedId)){Write-ReferenceUnavailable 'ENTRY_ID_DUPLICATE'}
    }
    if(-not$entryIdWasBound){
        $selected=@($current|Sort-Object -Property id|Select-Object -First 3)
    } else {
        $selected=@($current|Where-Object{$requested.Contains([string]$_.id)}|Sort-Object -Property id)
        if($selected.Count-ne$requested.Count){Write-ReferenceUnavailable 'ENTRY_ID_NOT_CURRENT'}
    }
    $result=[pscustomobject][ordered]@{status='REFERENCE_AVAILABLE';reason='CURRENT_ENTRIES_VERIFIED';referenceOnly=$true;authority=$false;projectConfigIdentity=$ExpectedProjectConfigIdentity;indexLocator=$indexLocator;indexIdentity=$ExpectedIndexIdentity;maxEntries=3;entries=$selected}
    if($AsJson){$result|ConvertTo-Json -Depth 8 -Compress}else{Write-Output('PASS|knowledge-reference|entries='+$selected.Count+'|ids='+(@($selected|ForEach-Object{$_.id})-join','))}
    exit 0
} catch {
    Write-ReferenceUnavailable ([string]$_.Exception.Message)
}
