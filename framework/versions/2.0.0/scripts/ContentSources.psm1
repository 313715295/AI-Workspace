Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
$script:ContentUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:ContentModulePath=$PSCommandPath
$script:ContentContexts=[Runtime.CompilerServices.ConditionalWeakTable[object,object]]::new()

function Get-AiwContentByteIdentity([byte[]]$Bytes) {
    return $Bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}
function ConvertTo-AiwContentCanonicalJson($Value) {
    # Preserve the ordinal JSON value, then let the existing serializer encode
    # it once. The former recursive serializer invoked a cmdlet for every key
    # and scalar in every descriptor, context signature and graph identity.
    function Convert-CsOrderedValue($Item){
        if($null-eq$Item){return $null}
        if($Item-is[string]-or$Item-is[bool]-or$Item-is[ValueType]){return $Item}
        $dictionary=$Item-is[Collections.IDictionary]
        if(-not$dictionary-and($Item-is[Array]-or$Item-is[Collections.IList])){
            $items=[Collections.Generic.List[object]]::new()
            foreach($element in $Item){$items.Add((Convert-CsOrderedValue $element))}
            return ,$items.ToArray()
        }
        [string[]]$keys=@(if($dictionary){$Item.Keys}else{foreach($property in $Item.PSObject.Properties){$property.Name}})
        [Array]::Sort($keys,[StringComparer]::Ordinal)
        $ordered=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        foreach($key in $keys){
            $value=if($dictionary){Convert-CsOrderedValue $Item[$key]}else{Convert-CsOrderedValue $Item.$key}
            $ordered.Add($key,$value)
        }
        return $ordered
    }
    return ConvertTo-Json -InputObject (Convert-CsOrderedValue $Value) -Compress -Depth 100
}
function Get-AiwContentDescriptorIdentity($Value) {
    return Get-CsObservedByteIdentity $script:ContentUtf8.GetBytes((ConvertTo-AiwContentCanonicalJson $Value))
}

# Facets are descriptive input metadata. These pure helpers are shared by the
# composer and knowledge QUERY; they never resolve authority or open a source.
function Get-AiwFacetVocabulary {
    [CmdletBinding()]param([AllowEmptyCollection()][object[]]$NativeVocabulary=@(),[AllowEmptyCollection()][object[]]$ProjectVocabulary=@())
    $dimensions=@('domain','workType','deliverableType','stage')
    $tokens=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $aliases=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($dimension in $dimensions){
        $tokens[$dimension]=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        $aliases[$dimension]=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    $entries=[Collections.Generic.List[object]]::new()
    foreach($group in @([pscustomobject]@{kind='NATIVE';entries=$NativeVocabulary},[pscustomobject]@{kind='PROJECT';entries=$ProjectVocabulary})){
        foreach($entry in $group.entries){
            Assert-CsFields $entry @('dimension','id','description','aliases')
            if($entry.dimension-isnot[string]-or$entry.dimension-cnotin$dimensions-or$entry.id-isnot[string]-or$entry.id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]*:[A-Za-z0-9][A-Za-z0-9._-]*$'-or
                $entry.description-isnot[string]-or[string]::IsNullOrWhiteSpace($entry.description)-or$entry.aliases-isnot[Array]){throw 'FACET_VOCABULARY_VALUES'}
            $dimension=[string]$entry.dimension;$id=[string]$entry.id
            if($tokens[$dimension].ContainsKey($id)){throw $(if($group.kind-ceq'PROJECT'){'FACET_VOCABULARY_NATIVE_OR_PROJECT_OVERRIDE'}else{'FACET_VOCABULARY_DUPLICATE_TOKEN'})}
            $tokens[$dimension].Add($id,$entry)
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($alias in $entry.aliases){
                if($alias-isnot[string]-or[string]::IsNullOrWhiteSpace($alias)-or$alias-cne$alias.Trim()-or-not$seen.Add($alias)){throw 'FACET_VOCABULARY_ALIAS'}
                if(-not$aliases[$dimension].ContainsKey($alias)){$aliases[$dimension].Add($alias,[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal))}
                $null=$aliases[$dimension][$alias].Add($id)
            }
            $entries.Add([pscustomobject]@{source=$group.kind;entry=$entry})
        }
    }
    return [pscustomobject]@{tokens=$tokens;aliases=$aliases;entries=$entries.ToArray();identity=(Get-AiwContentDescriptorIdentity $entries.ToArray());authority=$false}
}

function Resolve-AiwFacetToken {
    [CmdletBinding()]param([Parameter(Mandatory)]$Vocabulary,[Parameter(Mandatory)][string]$Dimension,[Parameter(Mandatory)][string]$Value,[switch]$DeclaredIdOnly)
    if(-not$Vocabulary.tokens.ContainsKey($Dimension)){throw 'FACET_DIMENSION_UNKNOWN'}
    if($Vocabulary.tokens[$Dimension].ContainsKey($Value)){return $Value}
    if(-not$DeclaredIdOnly-and$Vocabulary.aliases[$Dimension].ContainsKey($Value)){
        $matches=@($Vocabulary.aliases[$Dimension][$Value])
        if($matches.Count-ne1){throw ('FACET_ALIAS_AMBIGUOUS|'+$Dimension+'|'+$Value)}
        return [string]$matches[0]
    }
    throw ('FACET_TOKEN_UNDECLARED|'+$Dimension+'|'+$Value)
}

function ConvertTo-AiwIntentFacets {
    [CmdletBinding()]param([Parameter(Mandatory)]$Facets,[Parameter(Mandatory)]$Vocabulary)
    $dimensions=@('domain','workType','deliverableType','stage')
    Assert-CsFields $Facets $dimensions
    $normalized=[ordered]@{}
    foreach($dimension in $dimensions){
        $value=$Facets.$dimension;Assert-CsFields $value @('state','values')
        if($value.state-isnot[string]-or$value.state-cnotin@('KNOWN','UNKNOWN','NOT_APPLICABLE')-or$value.values-isnot[Array]){throw ('FACET_STATE_OR_VALUES|'+$dimension)}
        if(($value.state-ceq'KNOWN'-and$value.values.Count-eq0)-or($value.state-cne'KNOWN'-and$value.values.Count-ne0)){throw ('FACET_STATE_VALUES_CONTRADICTION|'+$dimension)}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$values=[Collections.Generic.List[string]]::new()
        foreach($token in $value.values){
            if($token-isnot[string]-or[string]::IsNullOrWhiteSpace($token)-or$token-cne$token.Trim()){throw ('FACET_VALUE|'+$dimension)}
            $id=Resolve-AiwFacetToken -Vocabulary $Vocabulary -Dimension $dimension -Value $token
            if(-not$seen.Add($id)){throw ('FACET_DUPLICATE_VALUE|'+$dimension)}
            $values.Add($id)
        }
        $normalized[$dimension]=[pscustomobject]@{state=[string]$value.state;values=$values.ToArray()}
    }
    return [pscustomobject]$normalized
}

function Assert-AiwFacetSelector {
    [CmdletBinding()]param([Parameter(Mandatory)]$Facets,$Vocabulary=$null)
    if($Facets-isnot[pscustomobject]){throw 'FACET_SELECTOR_OBJECT'}
    foreach($property in $Facets.PSObject.Properties){
        $dimension=$property.Name
        if($dimension-cnotin@('domain','workType','deliverableType','stage')-or$property.Value-isnot[Array]-or$property.Value.Count-eq0){throw 'FACET_SELECTOR_DIMENSION_OR_VALUES'}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($value in $property.Value){
            if($value-isnot[string]-or$value-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]*:[A-Za-z0-9][A-Za-z0-9._-]*$'-or-not$seen.Add($value)){throw 'FACET_SELECTOR_VALUE'}
            if($null-ne$Vocabulary){$null=Resolve-AiwFacetToken -Vocabulary $Vocabulary -Dimension $dimension -Value $value -DeclaredIdOnly}
        }
    }
}

function Test-AiwFacetSelector {
    [CmdletBinding()]param([Parameter(Mandatory)]$SelectorFacets,[Parameter(Mandatory)]$IntentFacets)
    $unknown=[Collections.Generic.List[string]]::new();$restricted=0
    foreach($property in $SelectorFacets.PSObject.Properties){
        $dimension=$property.Name;$actual=$IntentFacets.$dimension;$restricted++
        if($actual.state-ceq'NOT_APPLICABLE'){return [pscustomobject]@{Match=$false;Decision='NO_MATCH';Semantic='FACET_NOT_APPLICABLE';Reasons=@($dimension)}}
        if($actual.state-ceq'UNKNOWN'){$unknown.Add($dimension);continue}
        if(@($property.Value|Where-Object{$_-cin@($actual.values)}).Count-eq0){return [pscustomobject]@{Match=$false;Decision='NO_MATCH';Semantic='FACET_NO_OVERLAP';Reasons=@($dimension)}}
    }
    return [pscustomobject]@{Match=$true;Decision=$(if($unknown.Count){'CONSERVATIVE'}else{'MATCH'});Semantic=$(if($unknown.Count){'UNKNOWN_CONSERVATIVE_LOAD'}elseif($restricted){'FACET_MATCH'}else{'DETERMINISTIC'});Reasons=$unknown.ToArray()}
}
Export-ModuleMember -Function Get-AiwFacetVocabulary,Resolve-AiwFacetToken,ConvertTo-AiwIntentFacets,Assert-AiwFacetSelector,Test-AiwFacetSelector
function Assert-CsFields($Value,[string[]]$Required,[string[]]$Optional=@()) {
    if($Value-isnot[pscustomobject]){throw 'SOURCE_DENIED|OBJECT_TYPE'}
    $fields=@($Value.PSObject.Properties.Name)
    if(@($Required|Where-Object{$_-cnotin$fields}).Count-or@($fields|Where-Object{$_-cnotin($Required+$Optional)}).Count){throw 'SOURCE_DENIED|OBJECT_FIELDS'}
}
function Assert-CsId($Id) {
    if($Id-isnot[string]-or$Id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]*$'){throw 'SOURCE_DENIED|ID'}
}
function Assert-CsIdentity($Identity) {
    if($Identity-isnot[string]-or$Identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'SOURCE_DENIED|IDENTITY'}
}
function Assert-CsLocator($Locator,[switch]$Directory) {
    if($Directory-and$Locator-ceq'.'){return}
    if($Locator-isnot[string]-or[string]::IsNullOrWhiteSpace($Locator)-or$Locator-cne$Locator.Trim()-or[IO.Path]::IsPathRooted($Locator)-or$Locator.Contains('\')){throw 'SOURCE_DENIED|LOCATOR'}
    foreach($part in $Locator.Split('/')){
        if($part-in@('','.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or$part-match'[\x00-\x1f<>:"|?*]'-or$part.Split('.')[0]-match'^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw 'SOURCE_DENIED|LOCATOR'}
    }
}
function Test-CsWithin([string]$Path,[string]$Root) {
    return $Path.Equals($Root,[StringComparison]::OrdinalIgnoreCase)-or$Path.StartsWith($Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CsPath([string]$Path,[string[]]$Forbidden=@(),[switch]$AllowMissing) {
    # Permission rejection precedes metadata, reads, hashes and cache access.
    foreach($scope in $Forbidden){if(Test-CsWithin $Path $scope){throw 'SOURCE_DENIED|FORBIDDEN_PATH'}}
    if($Path.StartsWith('\\')){throw 'SOURCE_DENIED|UNC'}
    $anchor=[IO.Path]::GetPathRoot($Path);$cursor=$anchor
    foreach($part in @('')+$Path.Substring($anchor.Length).Split([char[]]@([char]92,[char]47),[StringSplitOptions]::RemoveEmptyEntries)){
        if($part.Length){$cursor=[IO.Path]::Combine($cursor,$part)}
        # Fresh metadata for every ancestor, including a missing leaf's parent;
        # no path observations survive this call. Missing is the only tolerated
        # error. Permission, reparse and other IO failures still stop the read.
        try{$attributes=[IO.File]::GetAttributes($cursor)}
        catch [IO.FileNotFoundException],[IO.DirectoryNotFoundException]{
            if($AllowMissing){continue};throw 'SOURCE_UNAVAILABLE|MISSING'
        }
        if(($attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'SOURCE_DENIED|REPARSE'}
    }
}
function Read-CsJson([string]$Path) {
    Assert-CsPath $Path
    $bytes=[IO.File]::ReadAllBytes($Path)
    $text=$script:ContentUtf8.GetString($bytes)
    $parsed=ConvertFrom-AiwStrictInputJson $text
    $value=if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$text|ConvertFrom-Json -Depth 100 -DateKind String}else{$parsed.Value}
    return [pscustomobject]@{Value=$value;Identity=(Get-AiwContentByteIdentity $bytes)}
}
function Assert-AiwSourceBindings($Bindings) {
    if($Bindings-isnot[Array]){throw 'SOURCE_DENIED|BINDINGS_TYPE'}
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($binding in $Bindings){
        Assert-CsFields $binding @('id','provider','locator','allowedPaths','decisionLocator') @('credentialRef','transportLimits')
        Assert-CsId $binding.id
        if(-not$ids.Add($binding.id)){throw 'SOURCE_DENIED|BINDING_DUPLICATE'}
        if($binding.provider-cnotin@('LOCAL_DIRECTORY','GIT_REVISION','HTTPS_RESOURCE')){throw 'SOURCE_DENIED|PROVIDER'}
        $field=switch($binding.provider){LOCAL_DIRECTORY{'root'};GIT_REVISION{'repository'};HTTPS_RESOURCE{'baseUrl'}}
        Assert-CsFields $binding.locator @($field)
        $location=$binding.locator.$field
        if($location-isnot[string]-or[string]::IsNullOrWhiteSpace($location)-or$location-cne$location.Trim()-or$location-match'[\x00-\x1f]'){throw 'SOURCE_DENIED|LOCATION'}
        if($binding.provider-ceq'LOCAL_DIRECTORY'){
            if($location.StartsWith('\\')-or$location-match'^[A-Za-z]:[^\\/]'){throw 'SOURCE_DENIED|LOCATION'}
            $tail=$location;if([IO.Path]::IsPathRooted($location)){$tail=$location.Substring([IO.Path]::GetPathRoot($location).Length)}
            foreach($part in @($tail-split'[\\/]'|Where-Object{$_-cnotin@('','.','..')})){
                if($part-match'[<>:"|?*]'-or$part.EndsWith('.')-or$part.EndsWith(' ')-or$part.Split('.')[0]-match'^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw 'SOURCE_DENIED|LOCATION'}
            }
        }elseif($location-match'^[A-Za-z]+://'){
            $uri=$null
            if(-not[Uri]::TryCreate($location,[UriKind]::Absolute,[ref]$uri)-or$uri.Scheme-cne'https'-or$uri.UserInfo-or$uri.Fragment-or$uri.Query){throw 'SOURCE_DENIED|URL'}
        }elseif($binding.provider-ceq'HTTPS_RESOURCE'){throw 'SOURCE_DENIED|URL'}
        if($binding.decisionLocator-isnot[string]-or[string]::IsNullOrWhiteSpace($binding.decisionLocator)){throw 'SOURCE_DENIED|DECISION_LOCATOR'}
        if($binding.allowedPaths-isnot[Array]-or$binding.allowedPaths.Count-lt1){throw 'SOURCE_DENIED|ALLOWED_PATHS'}
        $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($permission in $binding.allowedPaths){
            Assert-CsFields $permission @('kind','locator')
            if($permission.kind-cnotin@('FILE','DIRECTORY')){throw 'SOURCE_DENIED|PERMISSION_KIND'}
            Assert-CsLocator $permission.locator -Directory:($permission.kind-ceq'DIRECTORY')
            if(-not$paths.Add($permission.kind+'|'+$permission.locator)){throw 'SOURCE_DENIED|PERMISSION_DUPLICATE'}
        }
        if($null-ne$binding.PSObject.Properties['credentialRef']){
            if($binding.credentialRef-isnot[string]-or$binding.credentialRef-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._:/-]*$'){throw 'SOURCE_DENIED|CREDENTIAL_REFERENCE'}
        }
        if($null-ne$binding.PSObject.Properties['transportLimits']){
            Assert-CsFields $binding.transportLimits @('maxObjectBytes','timeoutMs','maxRedirects')
            foreach($name in @('maxObjectBytes','timeoutMs','maxRedirects')){$v=$binding.transportLimits.$name;if(($v-isnot[int]-and$v-isnot[long])-or$v-lt0-or($name-cne'maxRedirects'-and$v-eq0)){throw 'SOURCE_DENIED|TRANSPORT_LIMITS'}}
        }
    }
}
function Convert-CsForbidden([string[]]$Scopes,[string]$ConfigRoot,[string]$ReadRoot){
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $paths=[Collections.Generic.List[string]]::new()
    foreach($scope in $Scopes){
        $expanded=if([IO.Path]::IsPathRooted($scope)){@([IO.Path]::GetFullPath($scope))}else{@([IO.Path]::GetFullPath((Join-Path $ConfigRoot $scope)));if($ReadRoot-cne$ConfigRoot){[IO.Path]::GetFullPath((Join-Path $ReadRoot $scope))}}
        foreach($path in $expanded){
            while($path.Length-gt[IO.Path]::GetPathRoot($path).Length-and($path.EndsWith('\')-or$path.EndsWith('/'))){$path=$path.Substring(0,$path.Length-1)}
            if($seen.Add($path)){$paths.Add($path)}
        }
    }
    return ,$paths.ToArray()
}
function New-CsOwnedContext {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,[string[]]$ForbiddenPaths=@(),[string]$SourceProjectRoot,[object[]]$ProjectedSourceObjects=@())
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot));Assert-CsPath $root
    # Prospective adoption reads approved config/policy bytes in its isolated
    # projection, while resolving exact source documents in the original root.
    # The caller still proves original admission and every live pre/postimage.
    $readRoot=if($SourceProjectRoot){[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($SourceProjectRoot))}else{$root}
    Assert-CsPath $readRoot
    $forbidden=Convert-CsForbidden $ForbiddenPaths $root $readRoot
    $configPath=Join-Path $root '.ai-workspace/project.json';Assert-CsPath $configPath $forbidden
    $config=Read-CsJson $configPath
    if($config.Identity-cne$ExpectedProjectConfigIdentity){throw 'CONTENT_IDENTITY_DRIFT|PROJECT_CONFIG'}
    if($config.Value.schemaVersion-ne7){throw 'SOURCE_DENIED|PROJECT_FORMAT'}
    Assert-AiwSourceBindings $config.Value.sourceBindings
    Assert-CsLocator $config.Value.processPolicy.locator
    $policyPath=Join-Path $root $config.Value.processPolicy.locator;Assert-CsPath $policyPath $forbidden
    $policy=Read-CsJson $policyPath
    if($config.Value.processPolicy.schemaVersion-ne3-or$policy.Value.schemaVersion-ne3-or$policy.Value.projectId-cne$config.Value.id){throw 'SOURCE_DENIED|POLICY_FORMAT'}
    $forbidden=Convert-CsForbidden (@($forbidden)+@($config.Value.routineExcludedPaths)) $root $readRoot
    $projected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $ProjectedSourceObjects){
        if(-not$SourceProjectRoot-or$root-ceq$readRoot-or$entry.kind-cne'FILE'-or-not$entry.newExists){throw 'SOURCE_DENIED|PROJECTED_SOURCE_OBJECT'}
        Assert-CsLocator $entry.path
        $origin=[IO.Path]::GetFullPath((Join-Path $readRoot $entry.path));$copy=[IO.Path]::GetFullPath((Join-Path $root $entry.path))
        if(-not(Test-CsWithin $origin $readRoot)-or-not(Test-CsWithin $copy $root)){throw 'SOURCE_DENIED|PROJECTED_SOURCE_PATH'}
        Assert-CsPath $origin $forbidden -AllowMissing;Assert-CsPath $copy $forbidden
        if((Get-AiwContentByteIdentity ([Convert]::FromBase64String($entry.newBase64)))-cne$entry.newIdentity-or(Get-AiwContentByteIdentity ([IO.File]::ReadAllBytes($copy)))-cne$entry.newIdentity){throw 'CONTENT_IDENTITY_DRIFT|PROJECTED_SOURCE_OBJECT'}
        $projected.Add($origin,[pscustomobject]@{Path=$copy;Identity=$entry.newIdentity})
    }
    $context=[pscustomobject]@{ProjectRoot=$readRoot;ConfigRoot=$root;ProjectedSources=$projected;QueryBytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal);ConfigPath=$configPath;Config=$config.Value;ConfigIdentity=$config.Identity;PolicyPath=$policyPath;Policy=$policy.Value;PolicyIdentity=$policy.Identity;Forbidden=$forbidden;ImplementationIdentity=(Get-AiwContentByteIdentity ([IO.File]::ReadAllBytes($script:ContentModulePath)));CacheRoot=(Join-Path $root '.ai-workspace/runtime/content-sources')}
    return $context
}
function New-AiwContentContext {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,[string[]]$ForbiddenPaths=@(),[string]$SourceProjectRoot,[object[]]$ProjectedSourceObjects=@())
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $(if($SourceProjectRoot){$SourceProjectRoot}else{$ProjectRoot}) -Mode OBSERVE
try {
    $context=New-CsOwnedContext @PSBoundParameters
    Register-CsContextInputs $context
    return $context
} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}
function Assert-CsCurrent($Context) {
    Assert-CsPath $Context.ConfigPath $Context.Forbidden;Assert-CsPath $Context.PolicyPath $Context.Forbidden
    if((Get-CsObservedByteIdentity ([IO.File]::ReadAllBytes($Context.ConfigPath)))-cne$Context.ConfigIdentity-or(Get-CsObservedByteIdentity ([IO.File]::ReadAllBytes($Context.PolicyPath)))-cne$Context.PolicyIdentity){throw 'CONTENT_IDENTITY_DRIFT|CURRENT_PERMISSION_OR_ADOPTION'}
    Assert-CsPath $script:ContentModulePath $Context.Forbidden
    if((Get-CsObservedByteIdentity ([IO.File]::ReadAllBytes($script:ContentModulePath)))-cne$Context.ImplementationIdentity){throw 'CONTENT_IDENTITY_DRIFT|IMPLEMENTATION'}
}
function Copy-CsValue($Value){
    # The strict input parser owns an object-root contract. A private value
    # clone can contain an array, scalar or null without weakening that parser.
    $text=ConvertTo-AiwContentCanonicalJson ([pscustomobject]@{value=$Value})
    $parsed=ConvertFrom-AiwStrictInputJson $text
    $copyRoot=if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$text|ConvertFrom-Json -Depth 100 -DateKind String}else{$parsed.Value}
    $copy=$copyRoot.value
    return ,$copy
}
function Get-CsContextSignature($Context){
    $projected=@(foreach($key in @($Context.ProjectedSources.Keys|Sort-Object -CaseSensitive)){
        [ordered]@{origin=[string]$key;path=[string]$Context.ProjectedSources[$key].Path;identity=[string]$Context.ProjectedSources[$key].Identity}
    })
    return Get-AiwContentDescriptorIdentity ([ordered]@{projectRoot=$Context.ProjectRoot;configRoot=$Context.ConfigRoot;configPath=$Context.ConfigPath;config=$Context.Config;configIdentity=$Context.ConfigIdentity;policyPath=$Context.PolicyPath;policy=$Context.Policy;policyIdentity=$Context.PolicyIdentity;forbidden=@($Context.Forbidden);implementationIdentity=$Context.ImplementationIdentity;cacheRoot=$Context.CacheRoot;projected=$projected})
}
function Register-CsContextInputs($Context){
    # Parsed data belongs to this actual context, not to a path/global cache.
    # Never share mutable caller objects with a private graph's inputs.
    $projected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($key in $Context.ProjectedSources.Keys){$projected.Add($key,[pscustomobject]@{Path=[string]$Context.ProjectedSources[$key].Path;Identity=[string]$Context.ProjectedSources[$key].Identity})}
    $private=[pscustomobject]@{ProjectRoot=[string]$Context.ProjectRoot;ConfigRoot=[string]$Context.ConfigRoot;ProjectedSources=$projected;QueryBytes=$Context.QueryBytes;ConfigPath=[string]$Context.ConfigPath;Config=(Copy-CsValue $Context.Config);ConfigIdentity=[string]$Context.ConfigIdentity;PolicyPath=[string]$Context.PolicyPath;Policy=(Copy-CsValue $Context.Policy);PolicyIdentity=[string]$Context.PolicyIdentity;Forbidden=@($Context.Forbidden);ImplementationIdentity=[string]$Context.ImplementationIdentity;CacheRoot=[string]$Context.CacheRoot}
    $adopted=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($rule in $private.Policy.rules){if($null-ne$rule.PSObject.Properties['source']){$null=$adopted.Add((Get-AiwContentDescriptorIdentity $rule.source))}}
    $script:ContentContexts.Add($Context,[pscustomobject]@{signature=(Get-CsContextSignature $Context);context=$private;adopted=$adopted;permissionIdentity=(Get-AiwContentDescriptorIdentity $private.Config.sourceBindings)})
}
function Get-CsContextInputs($Context){
    $inputs=$null
    if(-not$script:ContentContexts.TryGetValue($Context,[ref]$inputs)){
        # A copied/reloaded module has no private observation to borrow. Perform
        # independent admission from current bytes; never trust a caller flag.
        $parameters=@{ProjectRoot=$Context.ConfigRoot;ExpectedProjectConfigIdentity=$Context.ConfigIdentity;ForbiddenPaths=@($Context.Forbidden)}
        if($Context.ConfigRoot-cne$Context.ProjectRoot){
            $parameters.SourceProjectRoot=$Context.ProjectRoot
            $objects=@(foreach($key in $Context.ProjectedSources.Keys){
                $relative=[IO.Path]::GetRelativePath($Context.ProjectRoot,$key).Replace('\','/');Assert-CsLocator $relative
                $copy=[IO.Path]::GetFullPath((Join-Path $Context.ConfigRoot $relative))
                if($copy-cne$Context.ProjectedSources[$key].Path){throw 'SOURCE_DENIED|PROJECTED_SOURCE_PATH'}
                Assert-CsPath $copy $Context.Forbidden
                [pscustomobject]@{kind='FILE';path=$relative;newExists=$true;newIdentity=$Context.ProjectedSources[$key].Identity;newBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($copy))}
            })
            $parameters.ProjectedSourceObjects=$objects
        }
        $fresh=New-AiwContentContext @parameters
        if(-not$script:ContentContexts.TryGetValue($fresh,[ref]$inputs)){throw 'SOURCE_DENIED|CONTEXT_OWNER'}
        if((Get-CsContextSignature $Context)-cne$inputs.signature){throw 'CONTENT_IDENTITY_DRIFT|CONTEXT'}
        $inputs.context.QueryBytes=$Context.QueryBytes
        $script:ContentContexts.Add($Context,$inputs)
    }
    Assert-CsCurrent $inputs.context
    if((Get-CsContextSignature $Context)-cne$inputs.signature){throw 'CONTENT_IDENTITY_DRIFT|CONTEXT'}
    return $inputs
}
function Get-CsBinding($Context,[string]$Id) {
    $matches=@($Context.Config.sourceBindings|Where-Object{$_.id-ceq$Id})
    if($matches.Count-ne1){throw 'DEPENDENCY_NOT_ADOPTED|BINDING'}
    return $matches[0]
}
function Resolve-CsDocument($Context,$Document) {
    $binding=Get-CsBinding $Context $Document.bindingId
    return Resolve-CsBoundDocument $Context $Document $binding (Get-AiwContentDescriptorIdentity $binding)
}
function Resolve-CsBoundDocument($Context,$Document,$binding,[string]$BindingIdentity) {
    Assert-CsLocator $Document.locator
    $allowed=$false
    foreach($scope in $binding.allowedPaths){
        if(($scope.kind-ceq'FILE'-and$Document.locator-ceq$scope.locator)-or($scope.kind-ceq'DIRECTORY'-and($scope.locator-ceq'.'-or$Document.locator-ceq$scope.locator-or$Document.locator.StartsWith($scope.locator+'/',[StringComparison]::Ordinal)))){$allowed=$true}
    }
    if(-not$allowed){throw 'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS'}
    if($null-ne$binding.PSObject.Properties['credentialRef']){throw 'CREDENTIAL_UNAVAILABLE'}
    $limits=[pscustomobject]@{maxObjectBytes=16777216L;timeoutMs=30000;maxRedirects=3}
    if($null-ne$binding.PSObject.Properties['transportLimits']){$limits=$binding.transportLimits}
    if($binding.provider-cne'LOCAL_DIRECTORY'){
        if($binding.provider-ceq'HTTPS_RESOURCE'){
            $base=[Uri]($binding.locator.baseUrl.TrimEnd('/')+'/')
            $url=[Uri]::new($base,[string]::Join('/',@($Document.locator.Split('/')|ForEach-Object{[Uri]::EscapeDataString($_)})))
            Assert-CsHttpTarget $binding $url
            $root=$base.AbsoluteUri;$physical=$url.AbsoluteUri
        }else{
            Assert-CsRevision $Document.revision
            if($Document.revision.kind-cne'GIT_COMMIT'){throw 'SOURCE_DENIED|GIT_COMMIT_REQUIRED'}
            $root=$binding.locator.repository
            if($root-notmatch'^https://'){
                $root=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($root)){$root}else{Join-Path $Context.ProjectRoot $root}))
                Assert-CsPath $root $Context.Forbidden -AllowMissing
                Assert-CsPath (Join-Path $root $Document.locator) $Context.Forbidden -AllowMissing
            }
            $physical='git:'+([Uri]::EscapeDataString($root))+'@'+$Document.revision.value+'/'+$Document.locator
        }
        return [pscustomobject]@{Binding=$binding;BindingIdentity=$BindingIdentity;Root=$root;Path=$physical;MaxObjectBytes=$limits.maxObjectBytes;Limits=$limits;Document=$Document}
    }
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($binding.locator.root)){$binding.locator.root}else{Join-Path $Context.ProjectRoot $binding.locator.root})))
    $path=[IO.Path]::GetFullPath((Join-Path $root $Document.locator))
    if(-not(Test-CsWithin $path $root)){throw 'SOURCE_DENIED|PATH_ESCAPE'}
    Assert-CsPath $root $Context.Forbidden -AllowMissing;Assert-CsPath $path $Context.Forbidden -AllowMissing
    $limit=16777216L;if($null-ne$binding.PSObject.Properties['transportLimits']){$limit=$binding.transportLimits.maxObjectBytes}
    return [pscustomobject]@{Binding=$binding;BindingIdentity=$BindingIdentity;Root=$root;Path=$path;MaxObjectBytes=$limit;Limits=$limits;Document=$Document}
}

# These transports consume only a permission-checked document. Neither a URL
# from a response body nor a Git ref from an adopted document is executable input.
function Assert-CsHttpTarget($Binding,[Uri]$Uri) {
    $base=[Uri]($Binding.locator.baseUrl.TrimEnd('/')+'/')
    if($Uri.Scheme-cne'https'-or$Uri.Authority-cne$base.Authority-or$Uri.UserInfo-or$Uri.Query-or$Uri.Fragment-or-not$Uri.AbsolutePath.StartsWith($base.AbsolutePath,[StringComparison]::Ordinal)){throw 'SOURCE_DENIED|HTTP_TARGET'}
    $relative=[Uri]::UnescapeDataString($Uri.AbsolutePath.Substring($base.AbsolutePath.Length))
    Assert-CsLocator $relative
    # Decode exactly once; encoded slash/dot tricks must not reinterpret scope.
    if($relative.Contains('%')-or$Uri.AbsolutePath-match'(?i)%2f|%5c'){throw 'SOURCE_DENIED|HTTP_TARGET'}
    $allowed=@($Binding.allowedPaths|Where-Object{($_.kind-ceq'FILE'-and$relative-ceq$_.locator)-or($_.kind-ceq'DIRECTORY'-and($_.locator-ceq'.'-or$relative-ceq$_.locator-or$relative.StartsWith($_.locator+'/',[StringComparison]::Ordinal)))})
    if($allowed.Count-eq0){throw 'SOURCE_DENIED|HTTP_TARGET'}
}
function New-CsHttpClient {
    $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false;$handler.UseCookies=$false;$handler.UseDefaultCredentials=$false
    return [Net.Http.HttpClient]::new($handler)
}
function Read-CsHttp($Resolved) {
    $client=New-CsHttpClient;$client.Timeout=[Threading.Timeout]::InfiniteTimeSpan
    $cts=[Threading.CancellationTokenSource]::new([TimeSpan]::FromMilliseconds($Resolved.Limits.timeoutMs))
    $uri=[Uri]$Resolved.Path;$redirects=0
    try{
        while($true){
            Assert-CsHttpTarget $Resolved.Binding $uri
            $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$uri);$response=$null
            try{
                $response=$client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cts.Token).GetAwaiter().GetResult()
                $status=[int]$response.StatusCode
                if($status-in@(301,302,303,307,308)){
                    if($redirects-ge$Resolved.Limits.maxRedirects){throw 'TRANSPORT_LIMIT_EXCEEDED|REDIRECTS'}
                    if($null-eq$response.Headers.Location){throw 'SOURCE_UNAVAILABLE|REDIRECT_LOCATION'}
                    $uri=[Uri]::new($uri,$response.Headers.Location);Assert-CsHttpTarget $Resolved.Binding $uri;$redirects++;continue
                }
                if($status-ne200){throw 'SOURCE_UNAVAILABLE|HTTP_STATUS'}
                $type=$response.Content.Headers.ContentType
                if($null-eq$type-or$type.MediaType-cnotin@('text/plain','text/markdown','application/json','application/octet-stream')){throw 'SOURCE_DENIED|CONTENT_TYPE'}
                if($response.Content.Headers.ContentEncoding.Count){throw 'SOURCE_DENIED|CONTENT_ENCODING'}
                $length=$response.Content.Headers.ContentLength
                if($null-ne$length-and$length-gt$Resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED|OBJECT_BYTES'}
                $stream=$response.Content.ReadAsStreamAsync($cts.Token).GetAwaiter().GetResult();$memory=[IO.MemoryStream]::new();$buffer=[byte[]]::new(65536)
                try{
                    while(($count=$stream.ReadAsync($buffer,0,$buffer.Length,$cts.Token).GetAwaiter().GetResult())-gt0){
                        if($memory.Length+$count-gt$Resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED|OBJECT_BYTES'}
                        $memory.Write($buffer,0,$count)
                    }
                    if($null-ne$length-and$memory.Length-ne$length){throw 'SOURCE_UNAVAILABLE|TRUNCATED'}
                    return ,$memory.ToArray()
                }finally{$stream.Dispose();$memory.Dispose()}
            }finally{if($null-ne$response){$response.Dispose()};$request.Dispose()}
        }
    }catch{
        if($cts.IsCancellationRequested){throw 'TRANSPORT_LIMIT_EXCEEDED|TIMEOUT'}
        if($_.Exception.Message-match'^(SOURCE_DENIED|SOURCE_UNAVAILABLE|TRANSPORT_LIMIT_EXCEEDED)'){throw}
        throw 'SOURCE_UNAVAILABLE|HTTP_TRANSPORT'
    }finally{$cts.Dispose();$client.Dispose()}
}

function Invoke-CsGit($Context,[string]$Work,[string[]]$Arguments,$Limits,[string]$MonitorRoot='',[string]$ObjectDirectory='') {
    $git=Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if($null-eq$git){throw 'SOURCE_UNAVAILABLE|GIT_EXECUTABLE'}
    $start=[Diagnostics.ProcessStartInfo]::new($git.Source);$start.WorkingDirectory=$Work;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($name in @($start.Environment.Keys)){if($name.StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase)){$null=$start.Environment.Remove($name)}}
    $start.Environment['GIT_CONFIG_NOSYSTEM']='1';$start.Environment['GIT_CONFIG_GLOBAL']='NUL';$start.Environment['GIT_TERMINAL_PROMPT']='0';$start.Environment['GIT_NO_REPLACE_OBJECTS']='1';$start.Environment['GIT_NO_LAZY_FETCH']='1'
    if($ObjectDirectory){$start.Environment['GIT_OBJECT_DIRECTORY']=$ObjectDirectory}
    foreach($arg in @('-c','credential.helper=','-c','core.hooksPath=NUL','-c','core.longpaths=true','-c','protocol.allow=never','-c','protocol.https.allow=always','-c','protocol.file.allow=always','-c','http.followRedirects=false','-c','http.extraHeader=','-c','maintenance.auto=false','-c','gc.auto=0')+$Arguments){$start.ArgumentList.Add($arg)}
    $output=Join-Path $Work ('output-'+[guid]::NewGuid().ToString('N'));$errorFile=$output+'.err'
    $out=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite);$err=[IO.File]::Open($errorFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start;$watch=[Diagnostics.Stopwatch]::StartNew();$started=$false
    try{
        $started=$process.Start();if(-not$started){throw 'SOURCE_UNAVAILABLE|GIT_START'}
        $copyOut=$process.StandardOutput.BaseStream.CopyToAsync($out);$copyErr=$process.StandardError.BaseStream.CopyToAsync($err)
        do{
            $done=$process.WaitForExit(20)
            if($watch.ElapsedMilliseconds-gt$Limits.timeoutMs){throw 'TRANSPORT_LIMIT_EXCEEDED|TIMEOUT'}
            if($out.Length-gt$Limits.maxObjectBytes-or$err.Length-gt$Limits.maxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED|OBJECT_BYTES'}
            if($MonitorRoot-and(Test-Path -LiteralPath $MonitorRoot)){
                $total=0L;foreach($file in Get-ChildItem -LiteralPath $MonitorRoot -Recurse -File){$total+=$file.Length}
                if($total-gt$Limits.maxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED|GIT_TRANSFER'}
            }
        }until($done-and$copyOut.IsCompleted-and$copyErr.IsCompleted)
        $null=$copyOut.GetAwaiter().GetResult();$null=$copyErr.GetAwaiter().GetResult()
        if($process.ExitCode-ne0){throw 'SOURCE_UNAVAILABLE|GIT_COMMAND'}
        $out.Position=0;$bytes=[byte[]]::new([int]$out.Length);$offset=0
        while($offset-lt$bytes.Length){$count=$out.Read($bytes,$offset,$bytes.Length-$offset);if($count-eq0){throw 'SOURCE_UNAVAILABLE|GIT_TRUNCATED'};$offset+=$count}
        return ,$bytes
    }finally{
        if($started-and-not$process.HasExited){$process.Kill($true);$process.WaitForExit()}
        $process.Dispose();$out.Dispose();$err.Dispose();[IO.File]::Delete($output);[IO.File]::Delete($errorFile)
    }
}
function Read-CsGit($Context,$Resolved,[switch]$ResolveRef,[string]$Selector) {
    Assert-CsPath $Context.CacheRoot $Context.Forbidden -AllowMissing
    $null=[IO.Directory]::CreateDirectory($Context.CacheRoot)
    $work=Join-Path $Context.CacheRoot ('g'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($work)
    try{
        $repository=$Resolved.Root;$remote=$repository.StartsWith('https://',[StringComparison]::Ordinal)
        $commit=$Resolved.Document.revision.value
        if($ResolveRef){
            if($Selector-cne'HEAD'-and$Selector-cnotmatch'^refs/(heads|tags)/[A-Za-z0-9][A-Za-z0-9._/-]*$'){throw 'SOURCE_DENIED|GIT_SELECTOR'}
            if($Selector.Contains('..')-or$Selector.Contains('//')-or$Selector.EndsWith('/')){throw 'SOURCE_DENIED|GIT_SELECTOR'}
            $commit=''
            if(-not$remote){
                $root=if(Test-Path (Join-Path $repository '.git') -PathType Container){Join-Path $repository '.git'}else{$repository}
                Assert-CsPath $root $Context.Forbidden
                if($Selector-ceq'HEAD'){
                    $head=Join-Path $root 'HEAD';Assert-CsPath $head $Context.Forbidden;$value=[IO.File]::ReadAllText($head).Trim()
                    if($value-cmatch'^(?:[a-f0-9]{40}|[a-f0-9]{64})$'){$commit=$value}
                    elseif($value-cmatch'^ref: (refs/heads/[A-Za-z0-9][A-Za-z0-9._/-]*)$'){$Selector=$Matches[1]}
                    else{throw 'SOURCE_DENIED|GIT_SELECTOR'}
                }
                if(-not$commit){
                    Assert-CsLocator $Selector
                    $refPath=Join-Path $root $Selector;Assert-CsPath $refPath $Context.Forbidden -AllowMissing
                    if(Test-Path $refPath -PathType Leaf){$commit=[IO.File]::ReadAllText($refPath).Trim()}
                    else{
                        $packed=Join-Path $root 'packed-refs';Assert-CsPath $packed $Context.Forbidden
                        $rows=@([IO.File]::ReadAllLines($packed)|Where-Object{$_-cmatch('^(?:[a-f0-9]{40}|[a-f0-9]{64}) '+[regex]::Escape($Selector)+'$')})
                        if($rows.Count-ne1){throw 'SOURCE_UNAVAILABLE|GIT_SELECTOR'};$commit=($rows[0]-split' ')[0]
                    }
                }
            }else{
                # ls-remote also discovers parent repositories and their URL
                # rewrites. Give it its own empty config, just like object reads.
                $null=Invoke-CsGit $Context $work @('init','--bare','--template=','refs.git') $Resolved.Limits
               $raw=Invoke-CsGit $Context $work @('--git-dir=refs.git','ls-remote','--',$repository,$Selector,($Selector+'^{}')) $Resolved.Limits
                $lines=@($script:ContentUtf8.GetString($raw).TrimEnd()-split'\r?\n')
                $rows=@($lines|Where-Object{$_-cmatch('^(?:[a-f0-9]{40}|[a-f0-9]{64})\s+'+[regex]::Escape($Selector)+'$')})
                $peeled=@($lines|Where-Object{$_-cmatch('^(?:[a-f0-9]{40}|[a-f0-9]{64})\s+'+[regex]::Escape($Selector+'^{}')+'$')})
                if($rows.Count-ne1-or$peeled.Count-gt1){throw 'SOURCE_UNAVAILABLE|GIT_SELECTOR'}
                $commit=($(if($peeled.Count){$peeled[0]}else{$rows[0]})-split'\s+')[0]
            }
            if($commit-cnotmatch'^(?:[a-f0-9]{40}|[a-f0-9]{64})$'){throw 'SOURCE_DENIED|GIT_SELECTOR'}
        }
        $objectFormat=if($commit.Length-eq64){'--object-format=sha256'}else{'--object-format=sha1'}
        $objects=''
        if($remote){
            $null=Invoke-CsGit $Context $work @('init','--bare','--template=',$objectFormat,'objects.git') $Resolved.Limits
            $gitRoot=Join-Path $work 'objects.git'
            $null=Invoke-CsGit $Context $work @('--git-dir=objects.git','fetch','--quiet','--no-tags','--no-write-fetch-head','--no-recurse-submodules','--depth=1','--filter=blob:none','--',$repository,$commit) $Resolved.Limits (Join-Path $gitRoot 'objects')
            $prefix=@('--git-dir=objects.git')
        }else{
            Assert-CsPath $repository $Context.Forbidden
            # Use the object database through a clean bare reader, not the
            # source repository's config, hooks, alternates or replace refs.
            $gitRoot=if(Test-Path (Join-Path $repository '.git') -PathType Container){Join-Path $repository '.git'}else{$repository}
            Assert-CsPath $gitRoot $Context.Forbidden
            $objects=Join-Path $gitRoot 'objects';Assert-CsPath $objects $Context.Forbidden
            if(Test-Path (Join-Path $objects 'info/alternates')){throw 'SOURCE_DENIED|GIT_ALTERNATES'}
            foreach($entry in Get-ChildItem -LiteralPath $objects -Recurse -Force){if(($entry.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'SOURCE_DENIED|REPARSE'}}
            $null=Invoke-CsGit $Context $work @('init','--bare','--template=',$objectFormat,'reader.git') $Resolved.Limits
           $prefix=@('--git-dir=reader.git')
        }
        if($ResolveRef){
            # Peel only the already resolved object, never reread a moving ref.
            # ^{commit} accepts nested annotated tags but rejects blob/tree tags.
            try{$commit=$script:ContentUtf8.GetString((Invoke-CsGit $Context $work ($prefix+@('rev-parse','--verify',($commit+'^{commit}'))) $Resolved.Limits -ObjectDirectory $objects)).Trim()}
            catch{if($_.Exception.Message-ceq'SOURCE_UNAVAILABLE|GIT_COMMAND'){throw 'SOURCE_DENIED|GIT_COMMIT_REQUIRED'};throw}
            if($commit-cnotmatch'^(?:[a-f0-9]{40}|[a-f0-9]{64})$'){throw 'SOURCE_DENIED|GIT_COMMIT_REQUIRED'}
        }
        $type=$script:ContentUtf8.GetString((Invoke-CsGit $Context $work ($prefix+@('cat-file','-t',$commit)) $Resolved.Limits -ObjectDirectory $objects)).Trim()
        if($type-cne'commit'){throw 'SOURCE_DENIED|GIT_COMMIT_REQUIRED'}
        if($ResolveRef){return $commit}
        $tree=$commit;$parts=$Resolved.Document.locator.Split('/');$oid=''
        for($i=0;$i-lt$parts.Count;$i++){
            $raw=Invoke-CsGit $Context $work ($prefix+@('ls-tree','-z',$tree,'--',$parts[$i])) $Resolved.Limits -ObjectDirectory $objects
            $row=$script:ContentUtf8.GetString($raw)
            if($row-cnotmatch'^(?<mode>[0-9]{6}) (?<type>blob|tree|commit) (?<oid>[a-f0-9]{40,64})\t(?<name>[^\x00]+)\x00$'-or$Matches.name-cne$parts[$i]){throw 'SOURCE_UNAVAILABLE|GIT_PATH'}
            $mode=$Matches.mode;$kind=$Matches.type;$oid=$Matches.oid
            if($mode-in@('120000','160000')){throw 'SOURCE_DENIED|GIT_SPECIAL_OBJECT'}
            if($i-lt$parts.Count-1){if($kind-cne'tree'){throw 'SOURCE_DENIED|GIT_PATH_TYPE'};$tree=$oid}
            elseif($kind-cne'blob'-or$mode-cnotin@('100644','100755')){throw 'SOURCE_DENIED|GIT_PATH_TYPE'}
        }
        if($remote){$null=Invoke-CsGit $Context $work ($prefix+@('fetch','--quiet','--no-tags','--no-write-fetch-head','--no-recurse-submodules','--',$repository,$oid)) $Resolved.Limits (Join-Path $gitRoot 'objects')}
        $size=[long]$script:ContentUtf8.GetString((Invoke-CsGit $Context $work ($prefix+@('cat-file','-s',$oid)) $Resolved.Limits -ObjectDirectory $objects)).Trim()
        if($size-gt$Resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED|OBJECT_BYTES'}
        return ,(Invoke-CsGit $Context $work ($prefix+@('cat-file','blob',$oid)) $Resolved.Limits -ObjectDirectory $objects)
    }finally{
        $full=[IO.Path]::GetFullPath($work)
        if(-not(Test-CsWithin $full $Context.CacheRoot)-or$full-ceq$Context.CacheRoot){throw 'SOURCE_DENIED|CACHE_CLEANUP'}
        Assert-CsPath $full $Context.Forbidden
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
function Read-CsTransport($Context,$Resolved) {
    switch -CaseSensitive ($Resolved.Binding.provider){
        'HTTPS_RESOURCE' {return ,(Read-CsHttp $Resolved)}
        'GIT_REVISION' {return ,(Read-CsGit $Context $Resolved)}
        'LOCAL_DIRECTORY' {
            Assert-CsPath $Resolved.Path $Context.Forbidden
            if((Get-Item -LiteralPath $Resolved.Path -Force).Length-gt$Resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
            return ,[IO.File]::ReadAllBytes($Resolved.Path)
        }
    }
}
function Assert-CsRevision($Revision) {
    Assert-CsFields $Revision @('kind','value')
    if($Revision.kind-ceq'CONTENT_IDENTITY'){Assert-CsIdentity $Revision.value}
    elseif($Revision.kind-ceq'GIT_COMMIT'){if($Revision.value-isnot[string]-or$Revision.value-cnotmatch'^(?:[a-f0-9]{40}|[a-f0-9]{64})$'){throw 'SOURCE_DENIED|REVISION'}}
    else{throw 'SOURCE_DENIED|REVISION'}
}
function Get-AiwContentRevision {
    [CmdletBinding()]param([Parameter(Mandatory)]$Descriptor,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Bindings)

    $material=@()
    foreach($document in $Descriptor.documents){
        $binding=@($Bindings|Where-Object{$_.id-ceq$document.bindingId})
        if($binding.Count-ne1){throw 'DEPENDENCY_NOT_ADOPTED|BINDING'}
        if($document.mode-ceq'NORMATIVE_UNIT'){
            $material+=[ordered]@{source=[ordered]@{provider=$binding[0].provider;locator=$binding[0].locator};locator=$document.locator;mode=$document.mode;unitId=$document.unitId;normativeIdentity=$document.normativeIdentity;sectionStart=$document.sectionStart;sectionEnd=$document.sectionEnd;commonConditionSourceIds=@($document.commonConditionSourceIds);dependencies=@($document.dependencies)}
        }else{$material+=[ordered]@{source=[ordered]@{provider=$binding[0].provider;locator=$binding[0].locator};locator=$document.locator;identity=$document.identity;mode=$document.mode;sectionStart=$document.sectionStart;sectionEnd=$document.sectionEnd;dependencies=@($document.dependencies)}}
    }
    return [pscustomobject]@{kind='CONTENT_IDENTITY';value=(Get-AiwContentDescriptorIdentity $material)}

}
function Get-AiwContentItemIdentity($Descriptor) {
    $fields=[ordered]@{};foreach($property in $Descriptor.PSObject.Properties){if($property.Name-cne'itemIdentity'){$fields[$property.Name]=$property.Value}}
    return Get-AiwContentDescriptorIdentity $fields
}
function Get-CsGraphOrder($Descriptor) {
    Assert-CsFields $Descriptor @('kind','bindingId','itemId','revision','itemIdentity','rootSourceId','documents')
    if($Descriptor.kind-cne'BOUND_SOURCE_ITEM'-or$Descriptor.documents-isnot[Array]-or$Descriptor.documents.Count-eq0){throw 'SOURCE_DENIED|ADOPTED_DESCRIPTOR'}
    Assert-CsId $Descriptor.bindingId;Assert-CsId $Descriptor.itemId;Assert-CsId $Descriptor.rootSourceId;Assert-CsRevision $Descriptor.revision;Assert-CsIdentity $Descriptor.itemIdentity
    $nodes=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($document in $Descriptor.documents){
        $fields=@('sourceId','bindingId','revision','locator','mode','sectionStart','sectionEnd','dependencies')
        if($document.mode-ceq'NORMATIVE_UNIT'){$fields+=@('unitId','normativeIdentity','commonConditionSourceIds')}else{$fields+='identity'}
        Assert-CsFields $document $fields
        Assert-CsId $document.sourceId;Assert-CsId $document.bindingId;Assert-CsRevision $document.revision;Assert-CsLocator $document.locator
        if($document.mode-ceq'NORMATIVE_UNIT'){
            Assert-CsId $document.unitId;Assert-CsIdentity $document.normativeIdentity
            if($document.commonConditionSourceIds-isnot[Array]){throw 'SOURCE_DENIED|COMMON_CONDITIONS'}
            $common=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($id in $document.commonConditionSourceIds){Assert-CsId $id;if(-not$common.Add($id)){throw 'SOURCE_DENIED|COMMON_CONDITION_DUPLICATE'}}
        }else{Assert-CsIdentity $document.identity}
        if($nodes.ContainsKey($document.sourceId)){throw 'SOURCE_DENIED|SOURCE_ID_DUPLICATE'}
        if($document.dependencies-isnot[Array]){throw 'SOURCE_DENIED|DEPENDENCIES'}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($dependency in $document.dependencies){Assert-CsId $dependency;if(-not$seen.Add($dependency)){throw 'SOURCE_DENIED|DEPENDENCY_DUPLICATE'}}
        if($document.mode-ceq'FULL_FILE'){if($document.sectionStart-cne'NOT_APPLICABLE'-or$document.sectionEnd-cne'NOT_APPLICABLE'){throw 'SOURCE_DENIED|MARKERS'}}
        elseif($document.mode-cin@('MARKED_SECTION','NORMATIVE_UNIT')){if($document.sectionStart-isnot[string]-or$document.sectionEnd-isnot[string]-or[string]::IsNullOrWhiteSpace($document.sectionStart)-or[string]::IsNullOrWhiteSpace($document.sectionEnd)-or$document.sectionStart-ceq$document.sectionEnd){throw 'SOURCE_DENIED|MARKERS'}}
        else{throw 'SOURCE_DENIED|DOCUMENT_MODE'}
        $nodes.Add($document.sourceId,$document)
    }
    if(-not$nodes.ContainsKey($Descriptor.rootSourceId)){throw 'SOURCE_DENIED|ROOT_SOURCE'}
    if($nodes[$Descriptor.rootSourceId].bindingId-cne$Descriptor.bindingId){throw 'SOURCE_DENIED|ROOT_BINDING'}
    if($Descriptor.revision.kind-ceq'GIT_COMMIT'-and(Get-AiwContentDescriptorIdentity $Descriptor.revision)-cne(Get-AiwContentDescriptorIdentity $nodes[$Descriptor.rootSourceId].revision)){throw 'CONTENT_IDENTITY_DRIFT|ROOT_REVISION'}
    $visiting=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$order=[Collections.Generic.List[object]]::new()
    function Visit-CsNode([string]$Id){
        if(-not$nodes.ContainsKey($Id)){throw 'DEPENDENCY_NOT_ADOPTED|DOCUMENT'}
        if($visited.Contains($Id)){return};if(-not$visiting.Add($Id)){throw 'SOURCE_DENIED|DEPENDENCY_CYCLE'}
        if($nodes[$Id].mode-ceq'NORMATIVE_UNIT'){foreach($condition in $nodes[$Id].commonConditionSourceIds){Visit-CsNode $condition}}
        foreach($dependency in $nodes[$Id].dependencies){Visit-CsNode $dependency}
        $null=$visiting.Remove($Id);$null=$visited.Add($Id);$order.Add($nodes[$Id])
    }
    Visit-CsNode $Descriptor.rootSourceId
    if($visited.Count-ne$nodes.Count){throw 'SOURCE_DENIED|ORPHAN_DOCUMENT'}
    return ,$order.ToArray()
}
function Resolve-AiwContentSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Descriptor,[ValidateSet('PINNED','FOLLOW')][string]$UpdatePolicy='PINNED',[switch]$KnowledgeQuery)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $Context.ProjectRoot -Mode OBSERVE
try {

    $contextInputs=Get-CsContextInputs $Context;$Context=$contextInputs.context
    $Descriptor=Copy-CsValue $Descriptor
    $documents=Get-CsGraphOrder $Descriptor
    if(-not$KnowledgeQuery){
        if(-not$contextInputs.adopted.Contains((Get-AiwContentDescriptorIdentity $Descriptor))){throw 'DEPENDENCY_NOT_ADOPTED|ITEM'}
        if((Get-AiwContentItemIdentity $Descriptor)-cne$Descriptor.itemIdentity){throw 'CONTENT_IDENTITY_DRIFT|ITEM_DESCRIPTOR'}
        if($Descriptor.revision.kind-ceq'CONTENT_IDENTITY'-and(Get-AiwContentRevision $Descriptor $Context.Config.sourceBindings).value-cne$Descriptor.revision.value){throw 'CONTENT_IDENTITY_DRIFT|CONTENT_REVISION'}
    }else{
        if($null-eq$Context.Config.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']-or-not$Context.Config.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled){throw 'SOURCE_DENIED|KNOWLEDGE_DISABLED'}
        $sources=@($Context.Config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources|Where-Object{$_.id-ceq$Descriptor.itemId-and$_.bindingId-ceq$Descriptor.bindingId-and$_.updatePolicy-ceq$UpdatePolicy})
        if($sources.Count-ne1-or$Descriptor.documents.Count-ne1-or$Descriptor.documents[0].locator-cne$sources[0].indexLocator){throw 'DEPENDENCY_NOT_ADOPTED|KNOWLEDGE_SOURCE'}
        if($UpdatePolicy-ceq'PINNED'-and($Descriptor.documents[0].identity-cne$sources[0].indexIdentity-or(Get-AiwContentDescriptorIdentity $Descriptor.revision)-cne(Get-AiwContentDescriptorIdentity $sources[0].revision))){throw 'CONTENT_IDENTITY_DRIFT|KNOWLEDGE_PIN'}
    }
    $facts=@();$physical=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($document in $documents){
        $resolved=Resolve-CsDocument $Context $document
        $physicalKey=if($resolved.Binding.provider-ceq'LOCAL_DIRECTORY'){$resolved.Path.ToUpperInvariant()}else{$resolved.Path}
        # Different complete units may share one raw whole-file snapshot.
        if($document.mode-cne'NORMATIVE_UNIT'){
            if($physical.ContainsKey($physicalKey)-and$physical[$physicalKey]-cne$document.identity){throw 'CONTENT_IDENTITY_DRIFT|PHYSICAL_SNAPSHOT'}
            $physical[$physicalKey]=[string]$document.identity
        }elseif($resolved.Binding.provider-cne'LOCAL_DIRECTORY'){throw 'SOURCE_DENIED|NORMATIVE_UNIT_LOCAL_ONLY'}
        $facts+=[pscustomobject]@{document=$document;bindingIdentity=$resolved.BindingIdentity;physicalSource=$resolved.Path}
    }
    $material=[ordered]@{projectRoot=$Context.ProjectRoot;projectConfigIdentity=$Context.ConfigIdentity;permissionIdentity=(Get-AiwContentDescriptorIdentity $Context.Config.sourceBindings);adoptionIdentity=(Get-AiwContentDescriptorIdentity $Descriptor);policyIdentity=$Context.PolicyIdentity;resolvedRevision=$Descriptor.revision;documents=$facts;implementationIdentity=$Context.ImplementationIdentity;updatePolicy=$UpdatePolicy}
    return [pscustomobject]@{schemaVersion=1;identity=(Get-AiwContentDescriptorIdentity $material);facts=[pscustomobject]$material;descriptor=$Descriptor;authority=$false}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}
function New-CsGraphReadFrame($Context,$Snapshot){
    $inputs=Get-CsContextInputs $Context;$context=$inputs.context
    $snapshot=Copy-CsValue $Snapshot
    Assert-CsFields $snapshot @('schemaVersion','identity','facts','descriptor','authority')
    if($snapshot.schemaVersion-ne1-or$snapshot.authority-isnot[bool]-or$snapshot.authority){throw 'SOURCE_DENIED|SNAPSHOT_TYPE'}
    Assert-CsIdentity $snapshot.identity
    Assert-CsFields $snapshot.facts @('projectRoot','projectConfigIdentity','permissionIdentity','adoptionIdentity','policyIdentity','resolvedRevision','documents','implementationIdentity','updatePolicy')
    $descriptorIdentity=Get-AiwContentDescriptorIdentity $snapshot.descriptor
    if($snapshot.facts.projectRoot-cne$context.ProjectRoot-or$snapshot.facts.projectConfigIdentity-cne$context.ConfigIdentity-or$snapshot.facts.permissionIdentity-cne$inputs.permissionIdentity-or$snapshot.facts.policyIdentity-cne$context.PolicyIdentity-or$snapshot.facts.implementationIdentity-cne$context.ImplementationIdentity-or(Get-AiwContentDescriptorIdentity $snapshot.facts)-cne$snapshot.identity-or$descriptorIdentity-cne$snapshot.facts.adoptionIdentity-or(Get-AiwContentDescriptorIdentity $snapshot.facts.resolvedRevision)-cne(Get-AiwContentDescriptorIdentity $snapshot.descriptor.revision)-or$snapshot.facts.updatePolicy-cnotin@('PINNED','FOLLOW')){throw 'CONTENT_IDENTITY_DRIFT|SNAPSHOT'}
    $order=Get-CsGraphOrder $snapshot.descriptor
    if($inputs.adopted.Contains($descriptorIdentity)){
        if((Get-AiwContentItemIdentity $snapshot.descriptor)-cne$snapshot.descriptor.itemIdentity){throw 'CONTENT_IDENTITY_DRIFT|ITEM_DESCRIPTOR'}
        if($snapshot.descriptor.revision.kind-ceq'CONTENT_IDENTITY'-and(Get-AiwContentRevision $snapshot.descriptor $context.Config.sourceBindings).value-cne$snapshot.descriptor.revision.value){throw 'CONTENT_IDENTITY_DRIFT|CONTENT_REVISION'}
    }else{
        $capability=if($null-ne$context.Config.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']){$context.Config.frameworkCapabilities.KNOWLEDGE_REFERENCE}else{$null}
        if($null-eq$capability-or-not$capability.enabled){throw 'DEPENDENCY_NOT_ADOPTED|ITEM'}
        $sources=@($capability.sources|Where-Object{$_.id-ceq$snapshot.descriptor.itemId-and$_.bindingId-ceq$snapshot.descriptor.bindingId-and$_.updatePolicy-ceq$snapshot.facts.updatePolicy})
        if($sources.Count-ne1-or$snapshot.descriptor.documents.Count-ne1-or$snapshot.descriptor.documents[0].locator-cne$sources[0].indexLocator){throw 'DEPENDENCY_NOT_ADOPTED|KNOWLEDGE_SOURCE'}
        if($snapshot.facts.updatePolicy-ceq'PINNED'-and($snapshot.descriptor.documents[0].identity-cne$sources[0].indexIdentity-or(Get-AiwContentDescriptorIdentity $snapshot.descriptor.revision)-cne(Get-AiwContentDescriptorIdentity $sources[0].revision))){throw 'CONTENT_IDENTITY_DRIFT|KNOWLEDGE_PIN'}
    }
    if($snapshot.facts.documents-isnot[Array]-or$snapshot.facts.documents.Count-ne$order.Count){throw 'SOURCE_DENIED|SNAPSHOT_DOCUMENT'}
    $members=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    for($index=0;$index-lt$order.Count;$index++){
        $document=$order[$index];$identity=Get-AiwContentDescriptorIdentity $document
        $fact=$snapshot.facts.documents[$index];Assert-CsFields $fact @('document','bindingIdentity','physicalSource')
        $resolved=Resolve-CsDocument $context $document
        if((Get-AiwContentDescriptorIdentity $fact.document)-cne$identity-or$fact.bindingIdentity-cne$resolved.BindingIdentity-or$fact.physicalSource-cne$resolved.Path){throw 'SOURCE_DENIED|SNAPSHOT_DOCUMENT'}
        $members.Add($document.sourceId,[pscustomobject]@{document=$document;identity=$identity;resolved=$resolved})
    }
    return [pscustomobject]@{context=$context;snapshot=$snapshot;members=$members;order=$order}
}
function Read-CsExact($Context,$Snapshot,$Document,$PhysicalReadCache){
    # The public exact reader always builds its own fully checked frame. Only
    # the graph's private loop can consume a frame prepared in that same call.
    $frame=New-CsGraphReadFrame $Context $Snapshot
    if(-not$frame.members.ContainsKey($Document.sourceId)-or(Get-AiwContentDescriptorIdentity $Document)-cne$frame.members[$Document.sourceId].identity){throw 'SOURCE_DENIED|SNAPSHOT_DOCUMENT'}
    return Read-CsExactCore $frame.context $frame.snapshot $frame.members[$Document.sourceId].document $PhysicalReadCache
}
function Read-CsPinnedCache($Context,[string]$Key,[long]$MaxObjectBytes){
    # Only the exact current key is eligible. A projection never writes back
    # to the read root, and an unused fallback is not probed.
    $roots=@($Context.CacheRoot)
    if($Context.ConfigRoot-cne$Context.ProjectRoot){$roots+=Join-Path $Context.ProjectRoot '.ai-workspace/runtime/content-sources'}
    foreach($root in $roots){
        $path=Join-Path $root ($Key+'.bin')
        Assert-CsPath $path $Context.Forbidden -AllowMissing
        if(Test-Path -LiteralPath $path -PathType Leaf){
            if((Get-Item -LiteralPath $path -Force).Length-gt$MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
            return [pscustomobject]@{bytes=[IO.File]::ReadAllBytes($path);path=$path}
        }
    }
    return $null
}
function Read-CsExactCore($Context,$Snapshot,$Document,$PhysicalReadCache) {
    Assert-CsCurrent $Context
    if($Document.mode-ceq'NORMATIVE_UNIT'){return Read-CsNormativeRaw $Context $Document $PhysicalReadCache}
    $resolved=Resolve-CsDocument $Context $Document
    $cacheKey=(Get-AiwContentDescriptorIdentity ([ordered]@{projectRoot=$Context.ProjectRoot;document=$Document;adoptedItem=$Snapshot.facts.adoptionIdentity;binding=$resolved.BindingIdentity;implementation=$Context.ImplementationIdentity})).Split('|')[1]
    return Read-CsResolvedExact $Context $Snapshot $Document $PhysicalReadCache $resolved $cacheKey
}
function Read-CsResolvedExact($Context,$Snapshot,$Document,$PhysicalReadCache,$resolved,[string]$cacheKey) {
    $cachePath=Join-Path $Context.CacheRoot ($cacheKey+'.bin')
    $observation='LOCAL'
    $physical=if($resolved.Binding.provider-ceq'LOCAL_DIRECTORY'){$resolved.Path.ToUpperInvariant()}else{$resolved.Path}
    $physicalKey='PHYSICAL|'+$resolved.Binding.provider+'|'+$physical
    $queryKey=$resolved.Path+'|'+$Document.identity
    # This cache belongs to one complete graph read. Permission is checked
    # above for every node, and a later read reobserves live local bytes.
    if($null-ne$PhysicalReadCache-and$PhysicalReadCache.ContainsKey($physicalKey)){
        $raw=$PhysicalReadCache[$physicalKey];$bytes=$raw.bytes;$observation=$raw.observation
        if($observation-ceq'PINNED_CACHE'){$cachePath=$raw.cachePath}
    }elseif($resolved.Binding.provider-cne'LOCAL_DIRECTORY'){
        $queryKey=$resolved.Path+'|'+$Document.identity
        if($Snapshot.facts.updatePolicy-ceq'FOLLOW'-and$Context.QueryBytes.ContainsKey($queryKey)){$bytes=$Context.QueryBytes[$queryKey];$observation='REMOTE'}
        else{
            $cached=if($Snapshot.facts.updatePolicy-ceq'PINNED'){Read-CsPinnedCache $Context $cacheKey $resolved.MaxObjectBytes}else{$null}
            if($null-ne$cached){$bytes=$cached.bytes;$cachePath=$cached.path;$observation='PINNED_CACHE'}
            else{Assert-CsCurrent $Context;try{$bytes=Read-CsTransport $Context $resolved}finally{Assert-CsCurrent $Context};$observation='REMOTE'}
        }
    }elseif($Context.ProjectedSources.ContainsKey($resolved.Path)){
        $copy=$Context.ProjectedSources[$resolved.Path];Assert-CsPath $copy.Path $Context.Forbidden
        if((Get-Item -LiteralPath $copy.Path -Force).Length-gt$resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
        $bytes=[IO.File]::ReadAllBytes($copy.Path)
        if((Get-CsObservedByteIdentity $bytes)-cne$copy.Identity){throw 'CONTENT_IDENTITY_DRIFT|PROJECTED_SOURCE_OBJECT'}
        $observation='PROJECTED'
    }elseif(Test-Path -LiteralPath $resolved.Path -PathType Leaf){
        Assert-CsPath $resolved.Path $Context.Forbidden
        if((Get-Item -LiteralPath $resolved.Path -Force).Length-gt$resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
        $bytes=[IO.File]::ReadAllBytes($resolved.Path)
    }else{
        $cached=if($Snapshot.facts.updatePolicy-ceq'PINNED'){Read-CsPinnedCache $Context $cacheKey $resolved.MaxObjectBytes}else{$null}
        if($null-eq$cached){throw 'SOURCE_UNAVAILABLE'}
        $bytes=$cached.bytes;$cachePath=$cached.path;$observation='PINNED_CACHE'
    }
    if($bytes.LongLength-gt$resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
    $actual=Get-CsObservedByteIdentity $bytes
    if($actual-cne$Document.identity){throw 'CONTENT_IDENTITY_DRIFT|DOCUMENT'}
    if($observation-in@('LOCAL','REMOTE')){
        Assert-CsPath $cachePath $Context.Forbidden -AllowMissing
        Assert-CsPath $Context.CacheRoot $Context.Forbidden -AllowMissing
        [IO.Directory]::CreateDirectory($Context.CacheRoot)|Out-Null;Assert-CsPath $Context.CacheRoot $Context.Forbidden
        if(Test-Path -LiteralPath $cachePath){
            if((Get-CsObservedByteIdentity ([IO.File]::ReadAllBytes($cachePath)))-cne$actual){throw 'CONTENT_IDENTITY_DRIFT|CACHE'}
        }else{
            $stream=[IO.File]::Open($cachePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $complete=$false
            try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true);$complete=$true}finally{$stream.Dispose();if(-not$complete){[IO.File]::Delete($cachePath)}}
        }
    }
    if($observation-ceq'REMOTE'-and$Snapshot.facts.updatePolicy-ceq'FOLLOW'){$Context.QueryBytes[$queryKey]=$bytes}
    if($null-ne$PhysicalReadCache){$PhysicalReadCache[$physicalKey]=[pscustomobject]@{bytes=$bytes;observation=$observation;identity=$actual;physicalSource=$resolved.Path;cachePath=$cachePath}}
    return [pscustomobject]@{bytes=$bytes;identity=$actual;observation=$observation;physicalSource=$resolved.Path;bindingIdentity=$resolved.BindingIdentity;revision=$Document.revision;cachePath=$cachePath}
}

function Read-AiwContentExact {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$Document)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $Context.ProjectRoot -Mode OBSERVE
try {

    if($Document.mode-ceq'NORMATIVE_UNIT'){
        $member=@($Snapshot.descriptor.documents|Where-Object{(Get-AiwContentDescriptorIdentity $_)-ceq(Get-AiwContentDescriptorIdentity $Document)})
        if($member.Count-ne1){throw 'SOURCE_DENIED|SNAPSHOT_DOCUMENT'}
        $graph=Read-AiwContentUnitGraph $Context $Snapshot
        return @($graph.units|Where-Object{$_.document.sourceId-ceq$Document.sourceId})[0].read
    }
    return Read-CsExact $Context $Snapshot $Document $null

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}
# Complete read-unit parsing is owned here, beside provider and raw identity
# validation. Consumers receive a whole unit; they do not reparse its markers.
function Get-CsReadUnit($Resolved,$Document,$Read){
    return Get-CsReadUnitFromText $Resolved $Document $Read (Convert-CsObservedText $Read.bytes)
}
function Convert-CsObservedText($Bytes){
    try{$body=$script:ContentUtf8.GetString($Bytes)}catch{throw 'SOURCE_DENIED|TEXT_FORMAT'}
    if($body.IndexOf([char]0)-ge0-or$body.IndexOf([char]0xFFFD)-ge0-or($body.Length-gt0-and$body[0]-ceq[char]0xFEFF)){throw 'SOURCE_DENIED|TEXT_FORMAT'}
    return $body
}
function Get-CsReadUnitFromText($Resolved,$Document,$Read,[string]$body){
    $start=0;$length=$body.Length
    if($Document.mode-cin@('MARKED_SECTION','NORMATIVE_UNIT')){
        $body=$body.Replace("`r`n","`n").Replace("`r","`n")
        $first=$body.IndexOf([string]$Document.sectionStart,[StringComparison]::Ordinal)
        $last=$body.IndexOf([string]$Document.sectionEnd,[StringComparison]::Ordinal)
        if($first-lt0-or$last-le$first-or$body.IndexOf([string]$Document.sectionStart,$first+1,[StringComparison]::Ordinal)-ge0-or$body.IndexOf([string]$Document.sectionEnd,$last+1,[StringComparison]::Ordinal)-ge0){throw 'SOURCE_DENIED|SECTION_CARDINALITY'}
        if($Document.mode-ceq'NORMATIVE_UNIT'){
            $endAfter=$last+$Document.sectionEnd.Length
            if(($first-gt0-and$body[$first-1]-cne[char]10)-or($endAfter-lt$body.Length-and$body[$endAfter]-cne[char]10)){throw 'SOURCE_DENIED|SECTION_LAYOUT'}
        }
        $after=$first+$Document.sectionStart.Length
        if($after-ge$body.Length-or$body[$after]-cne[char]10-or$last-eq0-or$body[$last-1]-cne[char]10){throw 'SOURCE_DENIED|SECTION_LAYOUT'}
        $start=$after+1;$length=$last-$start-1
        $body=$body.Substring($start,$length)
        if([string]::IsNullOrWhiteSpace($body)){throw 'SOURCE_DENIED|EMPTY_DOCUMENT'}
    }
    $physical=if($Resolved.Binding.provider-ceq'LOCAL_DIRECTORY'){$Resolved.Path.ToUpperInvariant()}else{$Resolved.Path}
    # The canonical Git path already contains its exact commit. A local/HTTPS
    # content revision includes dependency metadata and is not a physical version.
    $facts=[ordered]@{provider=$Resolved.Binding.provider;physicalSource=$physical;wholeFileIdentity=$Read.identity;mode=$Document.mode;start=$start;length=$length}
    if([string]::IsNullOrWhiteSpace($body)){throw 'SOURCE_DENIED|EMPTY_DOCUMENT'}
    if($Document.mode-ceq'NORMATIVE_UNIT'){
        $facts=[ordered]@{provider=$Resolved.Binding.provider;physicalSource=$physical;permissionIdentity=$Resolved.BindingIdentity;mode='NORMATIVE_UNIT';unitId=$Document.unitId;parserVersion='UTF8_LF_COMPLETE_UNIT_V1';sectionStart=$Document.sectionStart;sectionEnd=$Document.sectionEnd;bodyIdentity=(Get-AiwContentByteIdentity $script:ContentUtf8.GetBytes($body))}
    }
    return [pscustomobject]@{identity=(Get-AiwContentDescriptorIdentity $facts);facts=[pscustomobject]$facts;body=$body}
}
function Read-AiwContentUnitGraph {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Snapshot)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $Context.ProjectRoot -Mode OBSERVE
try {

    $frame=New-CsGraphReadFrame $Context $Snapshot
    $Context=$frame.context;$Snapshot=$frame.snapshot
    $raw=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $units=[Collections.Generic.List[object]]::new()
    $bySource=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($document in $frame.order){
        $resolved=$frame.members[$document.sourceId].resolved
        $read=Read-CsExactCore $Context $Snapshot $document $raw
        $unit=Get-CsReadUnit $resolved $document $read
        $duplicateKey=$unit.identity
        if($document.mode-ceq'NORMATIVE_UNIT'){
            $duplicateKey=Get-AiwContentDescriptorIdentity @($resolved.Binding.provider,$resolved.Path.ToUpperInvariant(),$document.unitId)
            $material=[ordered]@{unit=$unit.facts;commonConditions=@($document.commonConditionSourceIds|ForEach-Object{$bySource[$_].identity});dependencies=@($document.dependencies|ForEach-Object{$bySource[$_].identity})}
            $actual=Get-AiwContentDescriptorIdentity $material
            if($actual-cne$document.normativeIdentity){throw ('CONTENT_IDENTITY_DRIFT|NORMATIVE_UNIT|'+$document.unitId)}
            $unit=[pscustomobject]@{identity=$actual;facts=[pscustomobject]$material;body=$unit.body}
        }
        if(-not$seen.Add($duplicateKey)){throw 'SOURCE_DENIED|UNIT_DUPLICATE'}
        $bySource.Add($document.sourceId,$unit)
        $units.Add([pscustomobject]@{document=$document;read=$read;unit=$unit})
    }
    # A graph must use one real physical observation, including mixed legacy/new units.
    foreach($entry in $raw.Values){
        if($entry.observation-cne'LOCAL'-and$entry.observation-cne'PROJECTED'){continue}
        $path=$entry.physicalSource
        if($Context.ProjectedSources.ContainsKey($path)){$path=$Context.ProjectedSources[$path].Path}
        Assert-CsPath $path $Context.Forbidden
        if((Get-AiwContentByteIdentity ([IO.File]::ReadAllBytes($path)))-cne$entry.identity){throw 'CONTENT_IDENTITY_DRIFT|READ_SNAPSHOT'}
    }
    Assert-CsCurrent $Context
    return [pscustomobject]@{snapshotIdentity=$Snapshot.identity;units=$units.ToArray();identity=(Get-AiwContentDescriptorIdentity @($units|ForEach-Object{$_.unit.facts}));authority=$false}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}
Export-ModuleMember -Function Read-AiwContentUnitGraph

function Test-AiwContentSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Snapshot,[switch]$KnowledgeQuery)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $Context.ProjectRoot -Mode OBSERVE
try {

    $fresh=Resolve-AiwContentSnapshot -Context $Context -Descriptor $Snapshot.descriptor -UpdatePolicy $Snapshot.facts.updatePolicy -KnowledgeQuery:$KnowledgeQuery
    if($fresh.identity-cne$Snapshot.identity){throw 'CONTENT_IDENTITY_DRIFT|SNAPSHOT'}
    $graph=Read-AiwContentUnitGraph $Context $fresh
    $observations=@($graph.units|ForEach-Object{$_.read.observation})
    return [pscustomobject]@{status='VERIFIED';snapshotIdentity=$fresh.identity;observations=$observations;authority=$false}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}

function Resolve-AiwKnowledgeSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Source)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $Context.ProjectRoot -Mode OBSERVE
try {

    $publicContext=$Context;$inputs=Get-CsContextInputs $publicContext;$Context=$inputs.context
    $declared=@($Context.Config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources|Where-Object{(Get-AiwContentDescriptorIdentity $_)-ceq(Get-AiwContentDescriptorIdentity $Source)})
    if($declared.Count-ne1){throw 'DEPENDENCY_NOT_ADOPTED|KNOWLEDGE_SOURCE'}
    $document=[pscustomobject]@{sourceId='INDEX';bindingId=$Source.bindingId;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=$Source.indexLocator;identity='';mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
    if($Source.updatePolicy-ceq'PINNED'){$document.identity=$Source.indexIdentity;$document.revision=$Source.revision}
    else{
        $binding=Get-CsBinding $Context $Source.bindingId
        if($binding.provider-ceq'GIT_REVISION'){
            # Resolve the ref once. Every read in this query then uses the full
            # commit, including entries whose paths do not occur in the index.
            $document.revision=[pscustomobject]@{kind='GIT_COMMIT';value=('0'*40)}
            $resolved=Resolve-CsDocument $Context $document
            $commit=Read-CsGit $Context $resolved -ResolveRef -Selector $Source.revisionSelector
            $document.revision=[pscustomobject]@{kind='GIT_COMMIT';value=$commit}
        }elseif($Source.revisionSelector-cne$Source.indexLocator){throw 'SOURCE_DENIED|LOCAL_REVISION_SELECTOR'}
        $resolved=Resolve-CsDocument $Context $document
        $bytes=Read-CsTransport $Context $resolved;$document.identity=Get-AiwContentByteIdentity $bytes
        if($binding.provider-cne'GIT_REVISION'){$document.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) $Context.Config.sourceBindings}
        if($binding.provider-cne'LOCAL_DIRECTORY'){$Context.QueryBytes[$resolved.Path+'|'+$document.identity]=$bytes}
    }
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$Source.bindingId;itemId=$Source.id;revision=$document.revision;itemIdentity='';rootSourceId='INDEX';documents=@($document)}
    $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    $snapshot=Resolve-AiwContentSnapshot -Context $publicContext -Descriptor $descriptor -UpdatePolicy $Source.updatePolicy -KnowledgeQuery
    $read=Read-AiwContentExact -Context $publicContext -Snapshot $snapshot -Document $document
    return [pscustomobject]@{Snapshot=$snapshot;IndexBytes=$read.bytes;IndexIdentity=$read.identity;Observation=$read.observation;PhysicalSource=$read.physicalSource;CachePath=$read.cachePath}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}
function Read-AiwKnowledgeReference {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$OpenedIndex,[Parameter(Mandatory)][string]$Locator,[Parameter(Mandatory)][string]$ExpectedIdentity)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $Context.ProjectRoot -Mode OBSERVE
try {

    $indexFrame=New-CsGraphReadFrame $Context $OpenedIndex.Snapshot
    $Context=$indexFrame.context;$sourceSnapshot=$indexFrame.snapshot
    $indexBytes=[byte[]]$OpenedIndex.IndexBytes.Clone();$indexIdentity=[string]$OpenedIndex.IndexIdentity
    if((Get-AiwContentByteIdentity $indexBytes)-cne$indexIdentity-or$indexIdentity-cne$sourceSnapshot.descriptor.documents[0].identity){throw 'CONTENT_IDENTITY_DRIFT|QUERY_INDEX'}
    $index=(ConvertFrom-AiwStrictInputJson $script:ContentUtf8.GetString($indexBytes)).Value
    $members=@()
    foreach($entry in $index.entries){
        $members+=[pscustomobject]@{locator=$entry.locator;identity=$entry.identity}
        if($null-ne$entry.PSObject.Properties['authorityDependencies']){$members+=@($entry.authorityDependencies)}
        if($null-ne$entry.PSObject.Properties['authorityLocator']){$members+=[pscustomobject]@{locator=$entry.authorityLocator;identity=$entry.authorityIdentity}}
    }
    if(@($members|Where-Object{$_.locator-ceq$Locator-and$_.identity-ceq$ExpectedIdentity}).Count-eq0){throw 'SOURCE_DENIED|REFERENCE_NOT_IN_QUERY_INDEX'}
    $document=[pscustomobject]@{sourceId='REFERENCE';bindingId=$sourceSnapshot.descriptor.bindingId;revision=$sourceSnapshot.descriptor.revision;locator=$Locator;identity=$ExpectedIdentity;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
    $resolved=Resolve-CsDocument $Context $document
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$document.bindingId;itemId=$sourceSnapshot.descriptor.itemId;revision=$document.revision;itemIdentity='';rootSourceId='REFERENCE';documents=@($document)}
    $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    $facts=[ordered]@{projectRoot=$Context.ProjectRoot;projectConfigIdentity=$Context.ConfigIdentity;permissionIdentity=(Get-AiwContentDescriptorIdentity $Context.Config.sourceBindings);adoptionIdentity=(Get-AiwContentDescriptorIdentity $descriptor);policyIdentity=$Context.PolicyIdentity;resolvedRevision=$descriptor.revision;documents=@([pscustomobject]@{document=$document;bindingIdentity=$resolved.BindingIdentity;physicalSource=$resolved.Path});implementationIdentity=$Context.ImplementationIdentity;updatePolicy=$sourceSnapshot.facts.updatePolicy;queryIndexIdentity=$indexIdentity}
    $snapshot=[pscustomobject]@{schemaVersion=1;identity=(Get-AiwContentDescriptorIdentity $facts);facts=[pscustomobject]$facts;descriptor=$descriptor;authority=$false}
    # This reference was built here from the fully admitted fixed query index
    # and its actual membership, not supplied as a public graph/skip proof.
    # The public exact reader continues to admit its complete graph itself.
    return Read-CsExactCore $Context $snapshot $document $null

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}

Export-ModuleMember -Function Get-AiwContentByteIdentity,ConvertTo-AiwContentCanonicalJson,Get-AiwContentDescriptorIdentity,Assert-AiwSourceBindings,New-AiwContentContext,Get-AiwContentRevision,Get-AiwContentItemIdentity,Resolve-AiwContentSnapshot,Read-AiwContentExact,Test-AiwContentSnapshot,Resolve-AiwKnowledgeSnapshot,Read-AiwKnowledgeReference

function Read-AiwContentCatalog {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$BindingId,[Parameter(Mandatory)][string]$Locator,[Parameter(Mandatory)][string]$ExpectedIdentity,$Revision=$null)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $Context.ProjectRoot -Mode OBSERVE
try {

    $inputs=Get-CsContextInputs $Context;$Context=$inputs.context;Assert-CsIdentity $ExpectedIdentity
    $resolved=Resolve-CsDocument $Context ([pscustomobject]@{bindingId=$BindingId;locator=$Locator;revision=$Revision})
    $bytes=Read-CsTransport $Context $resolved
    if((Get-AiwContentByteIdentity $bytes)-cne$ExpectedIdentity){throw 'CONTENT_IDENTITY_DRIFT|CATALOG'}
    $text=$script:ContentUtf8.GetString($bytes);$parsed=ConvertFrom-AiwStrictInputJson $text
    $schema=Join-Path ([IO.Path]::GetDirectoryName($script:ContentModulePath)) '../CONTENT_CATALOG_SCHEMA.json'
    if(-not(Test-Json -Json $text -SchemaFile $schema -ErrorAction SilentlyContinue)){throw 'SOURCE_DENIED|CATALOG_SCHEMA'}
    $catalog=$parsed.Value;$ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($item in $catalog.items){if(-not$ids.Add($item.id)){throw 'SOURCE_DENIED|CATALOG_ITEM_DUPLICATE'}}
    return [pscustomobject]@{catalog=$catalog;identity=$ExpectedIdentity;descriptorIdentity=(Get-AiwContentDescriptorIdentity $catalog);bindingId=$BindingId;projectRoot=$Context.ProjectRoot;projectConfigIdentity=$Context.ConfigIdentity;authority=$false}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}
function Convert-AiwContentCatalogItem {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$CatalogRead,[Parameter(Mandatory)][string]$ItemId,[Parameter(Mandatory)]$SourceRefBindings)
    $inputs=Get-CsContextInputs $Context;$Context=$inputs.context
    if($CatalogRead.projectRoot-cne$Context.ProjectRoot-or$CatalogRead.projectConfigIdentity-cne$Context.ConfigIdentity){throw 'SOURCE_DENIED|CATALOG_PROJECT'}
    if((Get-AiwContentDescriptorIdentity $CatalogRead.catalog)-cne$CatalogRead.descriptorIdentity){throw 'CONTENT_IDENTITY_DRIFT|CATALOG_SNAPSHOT'}
    $items=@($CatalogRead.catalog.items|Where-Object{$_.id-ceq$ItemId});if($items.Count-ne1){throw 'SOURCE_DENIED|CATALOG_ITEM'};$item=$items[0]
    if($null-eq$item.descriptor.PSObject.Properties['documents']){throw 'SOURCE_DENIED|CATALOG_ITEM_NOT_RULE_GRAPH'}
    $documents=@()
    foreach($source in $item.descriptor.documents){
        $ref=[string]$source.sourceRef
        if($SourceRefBindings-isnot[Collections.IDictionary]-or-not$SourceRefBindings.Contains($ref)){throw 'DEPENDENCY_NOT_ADOPTED|SOURCE_REF_MAPPING'}
        $binding=Get-CsBinding $Context ([string]$SourceRefBindings[$ref])
        if($ref-ceq'SELF'){if($binding.id-cne$CatalogRead.bindingId){throw 'SOURCE_DENIED|SELF_SOURCE_MAPPING'}}else{
            $declarations=@($CatalogRead.catalog.sourceRefs|Where-Object{$_.id-ceq$ref})
            if($declarations.Count-ne1-or$declarations[0].provider-cne$binding.provider-or(Get-AiwContentDescriptorIdentity $declarations[0].locator)-cne(Get-AiwContentDescriptorIdentity $binding.locator)){throw 'SOURCE_DENIED|SOURCE_REF_MAPPING'}
        }
        $row=[ordered]@{};foreach($property in $source.PSObject.Properties){if($property.Name-cne'sourceRef'){$row[$property.Name]=$property.Value}};$row.bindingId=$binding.id
        $document=[pscustomobject]$row;$null=Resolve-CsDocument $Context $document;$documents+=$document
    }
    $root=@($documents|Where-Object{$_.sourceId-ceq$item.descriptor.rootSourceId});if($root.Count-ne1){throw 'SOURCE_DENIED|ROOT_SOURCE'}
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$root[0].bindingId;itemId=$item.id;revision=$item.revision;itemIdentity='';rootSourceId=$item.descriptor.rootSourceId;documents=$documents}
    $descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    $null=Get-CsGraphOrder $descriptor
    if($descriptor.revision.kind-ceq'CONTENT_IDENTITY'-and(Get-AiwContentDescriptorIdentity (Get-AiwContentRevision $descriptor $Context.Config.sourceBindings))-cne(Get-AiwContentDescriptorIdentity $descriptor.revision)){throw 'CONTENT_IDENTITY_DRIFT|CATALOG_REVISION'}
    return [pscustomobject]@{status='ADOPTION_PREVIEW';source=$descriptor;catalogIdentity=$CatalogRead.identity;itemId=$item.id;authority=$false}
}
Export-ModuleMember -Function Read-AiwContentCatalog,Convert-AiwContentCatalogItem

# New local normative mode reobserves whole physical bytes without freezing their
# unrelated content into semantic identity. No persistent cache or permission skip.
function Read-CsNormativeRaw($Context,$Document,$PhysicalReadCache){
    Assert-CsCurrent $Context
    $resolved=Resolve-CsDocument $Context $Document
    return Read-CsResolvedNormativeRaw $Context $Document $PhysicalReadCache $resolved
}
function Read-CsResolvedNormativeRaw($Context,$Document,$PhysicalReadCache,$resolved){
    if($resolved.Binding.provider-cne'LOCAL_DIRECTORY'){throw 'SOURCE_DENIED|NORMATIVE_UNIT_LOCAL_ONLY'}
    $key='PHYSICAL|LOCAL_DIRECTORY|'+$resolved.Path.ToUpperInvariant()
    if($null-ne$PhysicalReadCache-and$PhysicalReadCache.ContainsKey($key)){
        $cached=$PhysicalReadCache[$key]
        return [pscustomobject]@{bytes=$cached.bytes;identity=$cached.identity;observation=$cached.observation;physicalSource=$resolved.Path;bindingIdentity=$resolved.BindingIdentity;revision=$Document.revision;cachePath='NOT_CACHED'}
    }
    $path=$resolved.Path;$observation='LOCAL'
    if($Context.ProjectedSources.ContainsKey($path)){$path=$Context.ProjectedSources[$path].Path;$observation='PROJECTED'}
    Assert-CsPath $path $Context.Forbidden
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'SOURCE_UNAVAILABLE'}
    if((Get-Item -LiteralPath $path -Force).Length-gt$resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
    $bytes=[IO.File]::ReadAllBytes($path)
    $actual=Get-CsObservedByteIdentity $bytes
    if($Context.ProjectedSources.ContainsKey($resolved.Path)-and$actual-cne$Context.ProjectedSources[$resolved.Path].Identity){throw 'CONTENT_IDENTITY_DRIFT|PROJECTED_SOURCE_OBJECT'}
    $row=[pscustomobject]@{bytes=$bytes;identity=$actual;observation=$observation;physicalSource=$resolved.Path;bindingIdentity=$resolved.BindingIdentity;revision=$Document.revision;cachePath='NOT_CACHED'}
    if($null-ne$PhysicalReadCache){$PhysicalReadCache.Add($key,$row)}
    return $row
}

# The owner is created from current files inside this module, never from a
# caller-supplied receipt or flag. No owner or callback escapes while it runs.
# Current raw observations for an already loaded action. This does not parse
# normative units or accept caller-owned snapshots as permission evidence.
function Get-CsRuleRawObservations([string]$ProjectRoot,[object[]]$Rules,[string[]]$ForbiddenPaths,[string]$ConfigIdentity,[string]$PolicyIdentity){
    $context=New-AiwContentContext -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity $ConfigIdentity -ForbiddenPaths $ForbiddenPaths
    $owned=(Get-CsContextInputs $context).context
    if($owned.PolicyIdentity-cne$PolicyIdentity){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
    $rows=[Collections.Generic.List[object]]::new()
    $physical=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($rule in $Rules){
        $current=@($owned.Policy.rules|Where-Object ruleId -CEQ $rule.ruleId)
        if($current.Count-ne1-or(Get-AiwContentDescriptorIdentity $current[0])-cne(Get-AiwContentDescriptorIdentity $rule)){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
        if($null-eq$rule.PSObject.Properties['source']){continue}
        if($null-eq$rule.source.PSObject.Properties['kind']-or$rule.source.kind-cne'BOUND_SOURCE_ITEM'){throw 'RULE_LOAD_REQUIRED|LEGACY_SOURCE'}
        $snapshot=Resolve-AiwContentSnapshot -Context $context -Descriptor $rule.source
        foreach($fact in $snapshot.facts.documents){
            $binding=Get-CsBinding $owned $fact.document.bindingId
            $cache=if($binding.provider-ceq'LOCAL_DIRECTORY'){$physical}else{$null}
            $read=Read-CsExactCore $owned $snapshot $fact.document $cache
            $rows.Add([pscustomobject]@{ruleId=$rule.ruleId;sourceId=$fact.document.sourceId;path=$read.physicalSource;identity=$read.identity})
        }
    }
    Assert-CsCurrent $owned
    return $rows.ToArray()
}
function Get-CsObservedByteIdentity($Bytes){
    if($Bytes-isnot[byte[]]){throw 'SOURCE_DENIED|OBSERVED_BYTES_TYPE'}
    return $Bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}
function Copy-CsOwnedContext($Context){
    $inputs=Get-CsContextInputs $Context;$source=$inputs.context
    $projected=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($key in $source.ProjectedSources.Keys){$projected.Add($key,[pscustomobject]@{Path=[string]$source.ProjectedSources[$key].Path;Identity=[string]$source.ProjectedSources[$key].Identity})}
    return [pscustomobject]@{ProjectRoot=[string]$source.ProjectRoot;ConfigRoot=[string]$source.ConfigRoot;ProjectedSources=$projected;QueryBytes=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal);ConfigPath=[string]$source.ConfigPath;Config=(Copy-CsValue $source.Config);ConfigIdentity=[string]$source.ConfigIdentity;PolicyPath=[string]$source.PolicyPath;Policy=(Copy-CsValue $source.Policy);PolicyIdentity=[string]$source.PolicyIdentity;Forbidden=@($source.Forbidden);ImplementationIdentity=[string]$source.ImplementationIdentity;CacheRoot=[string]$source.CacheRoot}
}
function Resolve-CsOwnedDocument($Owner,$Document){
    if(-not$Owner.bindings.ContainsKey([string]$Document.bindingId)){throw 'DEPENDENCY_NOT_ADOPTED|BINDING'}
    $binding=$Owner.bindings[[string]$Document.bindingId]
    Assert-CsLocator $Document.locator
    $allowed=$false
    foreach($scope in $binding.value.allowedPaths){if(($scope.kind-ceq'FILE'-and$Document.locator-ceq$scope.locator)-or($scope.kind-ceq'DIRECTORY'-and($scope.locator-ceq'.'-or$Document.locator-ceq$scope.locator-or$Document.locator.StartsWith($scope.locator+'/',[StringComparison]::Ordinal)))){$allowed=$true}}
    if(-not$allowed){throw 'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS'}
    $revision=if($binding.value.provider-ceq'GIT_REVISION'){$Document.revision.kind+'|'+$Document.revision.value}else{''}
    $key=$Document.bindingId+'|'+$Document.locator+'|'+$revision
    if(-not$Owner.resolved.ContainsKey($key)){$Owner.resolved.Add($key,(Resolve-CsBoundDocument $Owner.context $Document $binding.value $binding.identity))}
    return $Owner.resolved[$key]
}
function New-CsOwnedGraph($Owner,$Descriptor,[string]$AdoptionIdentity){
    $context=$Owner.context;$order=Get-CsGraphOrder $Descriptor
    if((Get-AiwContentItemIdentity $Descriptor)-cne$Descriptor.itemIdentity){throw 'CONTENT_IDENTITY_DRIFT|ITEM_DESCRIPTOR'}
    if($Descriptor.revision.kind-ceq'CONTENT_IDENTITY'-and(Get-AiwContentRevision $Descriptor $context.Config.sourceBindings).value-cne$Descriptor.revision.value){throw 'CONTENT_IDENTITY_DRIFT|CONTENT_REVISION'}
    $facts=[Collections.Generic.List[object]]::new();$members=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$physical=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($document in $order){
        $resolved=Resolve-CsOwnedDocument $Owner $document
        $physicalKey=if($resolved.Binding.provider-ceq'LOCAL_DIRECTORY'){$resolved.Path.ToUpperInvariant()}else{$resolved.Path}
        if($document.mode-cne'NORMATIVE_UNIT'){
            if($physical.ContainsKey($physicalKey)-and$physical[$physicalKey]-cne$document.identity){throw 'CONTENT_IDENTITY_DRIFT|PHYSICAL_SNAPSHOT'}
            $physical[$physicalKey]=[string]$document.identity
        }elseif($resolved.Binding.provider-cne'LOCAL_DIRECTORY'){throw 'SOURCE_DENIED|NORMATIVE_UNIT_LOCAL_ONLY'}
        $facts.Add([pscustomobject]@{document=$document;bindingIdentity=$resolved.BindingIdentity;physicalSource=$resolved.Path})
        $cacheKey=if($document.mode-ceq'NORMATIVE_UNIT'){'NOT_CACHED'}else{(Get-AiwContentDescriptorIdentity ([ordered]@{projectRoot=$context.ProjectRoot;document=$document;adoptedItem=$AdoptionIdentity;binding=$resolved.BindingIdentity;implementation=$context.ImplementationIdentity})).Split('|')[1]}
        $members.Add([string]$document.sourceId,[pscustomobject]@{document=$document;resolved=$resolved;cacheKey=$cacheKey})
    }
    $material=[ordered]@{projectRoot=$context.ProjectRoot;projectConfigIdentity=$context.ConfigIdentity;permissionIdentity=$Owner.permissionIdentity;adoptionIdentity=$AdoptionIdentity;policyIdentity=$context.PolicyIdentity;resolvedRevision=$Descriptor.revision;documents=$facts.ToArray();implementationIdentity=$context.ImplementationIdentity;updatePolicy='PINNED'}
    $snapshot=[pscustomobject]@{schemaVersion=1;identity=(Get-AiwContentDescriptorIdentity $material);facts=[pscustomobject]$material;descriptor=$Descriptor;authority=$false}
    return [pscustomobject]@{snapshot=$snapshot;order=$order;members=$members}
}
function Read-CsOwnedExact($Owner,$Frame,$Member,$PhysicalReadCache){
    $context=$Owner.context;$document=$Member.document
    $resolved=Resolve-CsOwnedDocument $Owner $document
    if($resolved.BindingIdentity-cne$Member.resolved.BindingIdentity-or$resolved.Path-cne$Member.resolved.Path){throw 'CONTENT_IDENTITY_DRIFT|SNAPSHOT'}
    if($document.mode-ceq'NORMATIVE_UNIT'){
        $key='PHYSICAL|LOCAL_DIRECTORY|'+$resolved.Path.ToUpperInvariant()
        if($PhysicalReadCache.ContainsKey($key)-and$PhysicalReadCache[$key].bytes.LongLength-gt$resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
        return Read-CsResolvedNormativeRaw $context $document $PhysicalReadCache $resolved
    }
    # Independent PINNED remote versions at the same URL are different raw
    # observations. Local files share one actual observation for this batch.
    if($resolved.Binding.provider-cne'LOCAL_DIRECTORY'){
        $key=$resolved.Binding.provider+'|'+$resolved.Path+'|'+$document.identity+'|'+$resolved.BindingIdentity+'|'+$document.revision.kind+'|'+$document.revision.value+'|PINNED'
        if(-not$Owner.remoteRaw.ContainsKey($key)){$Owner.remoteRaw.Add($key,[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal))}
        $PhysicalReadCache=$Owner.remoteRaw[$key]
    }
    $read=Read-CsResolvedExact $context $Frame.snapshot $document $PhysicalReadCache $resolved $Member.cacheKey
    return $read
}
function Read-CsOwnedGraph($Owner,$Frame){
    $context=$Owner.context;$raw=$Owner.raw
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$units=[Collections.Generic.List[object]]::new();$bySource=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($document in $Frame.order){
        $member=$Frame.members[[string]$document.sourceId];$resolved=$member.resolved
        $read=Read-CsOwnedExact $Owner $Frame $member $raw
        $conditions=if($document.mode-ceq'NORMATIVE_UNIT'){@($document.commonConditionSourceIds|ForEach-Object{$bySource[$_].identity})}else{@()}
        $dependencies=@($document.dependencies|ForEach-Object{$bySource[$_].identity})
        $physical=if($resolved.Binding.provider-ceq'LOCAL_DIRECTORY'){$resolved.Path.ToUpperInvariant()}else{$resolved.Path}
        $key=Get-AiwContentDescriptorIdentity ([ordered]@{provider=$resolved.Binding.provider;physicalSource=$physical;wholeFileIdentity=$read.identity;permissionIdentity=$resolved.BindingIdentity;mode=$document.mode;unitId=$(if($document.mode-ceq'NORMATIVE_UNIT'){$document.unitId}else{'NOT_APPLICABLE'});sectionStart=$document.sectionStart;sectionEnd=$document.sectionEnd;parser='UTF8_LF_COMPLETE_UNIT_V1';commonConditions=@($conditions);dependencies=$dependencies})
        if($Owner.units.ContainsKey($key)){$unit=$Owner.units[$key]}else{
            $textKey=$resolved.Binding.provider+'|'+$physical+'|'+$read.identity+'|'+$resolved.BindingIdentity
            if(-not$Owner.text.ContainsKey($textKey)){$Owner.text.Add($textKey,(Convert-CsObservedText $read.bytes))}
            $unit=Get-CsReadUnitFromText $resolved $document $read $Owner.text[$textKey];$Owner.units.Add($key,$unit)
        }
        $duplicateKey=$unit.identity
        if($document.mode-ceq'NORMATIVE_UNIT'){
            $duplicateKey=Get-AiwContentDescriptorIdentity @($resolved.Binding.provider,$resolved.Path.ToUpperInvariant(),$document.unitId)
            $material=[ordered]@{unit=$unit.facts;commonConditions=@($conditions);dependencies=$dependencies}
            $actual=Get-AiwContentDescriptorIdentity $material
            if($actual-cne$document.normativeIdentity){throw ('CONTENT_IDENTITY_DRIFT|NORMATIVE_UNIT|'+$document.unitId)}
            $unit=[pscustomobject]@{identity=$actual;facts=[pscustomobject]$material;body=$unit.body}
        }
        if(-not$seen.Add($duplicateKey)){throw 'SOURCE_DENIED|UNIT_DUPLICATE'}
        $bySource.Add([string]$document.sourceId,$unit);$units.Add([pscustomobject]@{document=$document;read=$read;unit=$unit})
    }
    return [pscustomobject]@{snapshotIdentity=$Frame.snapshot.identity;units=$units.ToArray();identity=(Get-AiwContentDescriptorIdentity @($units|ForEach-Object{$_.unit.facts}));authority=$false}
}
# Publication alone can borrow closure documents from its immediately preceding
# old-side construction. This helper is private: callers cannot supply a trusted
# snapshot through a public content API. The target still resolves every binding
# and observes every local member; missing/offline/remote or changed material is
# left to the original complete reader (including its cache semantics).
function Get-CsPublicationReuseCandidates($Context,[object[]]$Rules,$PreviousMaterial) {
    $reused=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    if($null-eq$PreviousMaterial){return ,$reused}
    $context=(Get-CsContextInputs $Context).context
    if($context.ProjectRoot-cne$PreviousMaterial.ProjectRoot-or$context.ConfigIdentity-cne$PreviousMaterial.ConfigIdentity-or$context.ImplementationIdentity-cne$PreviousMaterial.ImplementationIdentity){return ,$reused}
    $currentRules=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($rule in $context.Policy.rules){
        if($rule.ruleId-isnot[string]-or-not$currentRules.TryAdd($rule.ruleId,$rule)){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
    }
    $requestedIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($rule in $Rules){
        if($rule.ruleId-isnot[string]-or-not$requestedIds.Add($rule.ruleId)-or-not$currentRules.ContainsKey($rule.ruleId)){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
        $ruleIdentity=Get-AiwContentDescriptorIdentity $currentRules[$rule.ruleId]
        if((Get-AiwContentDescriptorIdentity $rule)-cne$ruleIdentity){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
        if(-not$PreviousMaterial.Rules.ContainsKey($rule.ruleId)){continue}
        $previous=$PreviousMaterial.Rules[$rule.ruleId]
        # Full rule equality includes selectors, obligations, units, ordered
        # dependencies, revisions and all common conditions, not just its ID.
        if($ruleIdentity-cne$previous.RuleIdentity){continue}
        $documents=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($document in $previous.Documents){$documents[$document.sourcePath]=$document}
        $same=$true
        foreach($document in $currentRules[$rule.ruleId].source.documents){
            $resolved=Resolve-CsDocument $context $document
            if($resolved.Binding.provider-cne'LOCAL_DIRECTORY'-or-not$documents.ContainsKey($resolved.Path)){$same=$false;break}
            $path=$resolved.Path;$projected=$null
            if($context.ProjectedSources.ContainsKey($path)){$projected=$context.ProjectedSources[$path];$path=$projected.Path}
            Assert-CsPath $path $context.Forbidden -AllowMissing
            if(-not[IO.File]::Exists($path)){$same=$false;break}
            if([IO.FileInfo]::new($path).Length-gt$resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
            $bytes=[IO.File]::ReadAllBytes($path)
            if($bytes.LongLength-gt$resolved.MaxObjectBytes){throw 'TRANSPORT_LIMIT_EXCEEDED'}
            $identity=Get-CsObservedByteIdentity $bytes
            if($null-ne$projected-and$identity-cne$projected.Identity){throw 'CONTENT_IDENTITY_DRIFT|PROJECTED_SOURCE_OBJECT'}
            # Rebuild on raw drift: a NORMATIVE_UNIT may still be valid when an
            # unrelated part of its physical file changed.
            if($identity-cne$documents[$resolved.Path].identity){$same=$false;break}
        }
        if($same){$reused.Add($rule.ruleId,[pscustomobject]@{Drift=$false;Documents=$previous.Documents})}
    }
    Assert-CsCurrent $context
    return ,$reused
}
function Invoke-CsOwnedStandardsBatch {
    [CmdletBinding()]param([string]$ProjectRoot,[object[]]$Rules,[string[]]$ForbiddenPaths=@(),$ContentContext=$null,[string]$ExpectedConfigIdentity='',[string]$ExpectedPolicyIdentity='')
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))
    $scopeRoot=if($null-ne$ContentContext){$ContentContext.ProjectRoot}else{$root}
    $aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $scopeRoot -Mode OBSERVE
    try{
        # Clone untrusted requests before constructing the owner. They remain
        # requests, and must equal the current independently parsed adoption.
        [object[]]$requestedRules=Copy-CsValue $Rules
        if($null-eq$requestedRules){$requestedRules=@()}
        if($null-eq$ContentContext){
            $path=Join-Path $root '.ai-workspace/project.json'
            $configIdentity=if($ExpectedConfigIdentity){$ExpectedConfigIdentity}else{Get-CsObservedByteIdentity ([IO.File]::ReadAllBytes($path))}
            $context=New-CsOwnedContext -ProjectRoot $root -ExpectedProjectConfigIdentity $configIdentity -ForbiddenPaths $ForbiddenPaths
        }else{
            if(($ContentContext.ConfigRoot-cne$root-and$ContentContext.ProjectRoot-cne$root)-or$ContentContext.ConfigIdentity-cne(Get-CsObservedByteIdentity ([IO.File]::ReadAllBytes($ContentContext.ConfigPath)))){throw 'SOURCE_DENIED|PROJECTED_CONTEXT_ROOT'}
            $context=Copy-CsOwnedContext $ContentContext
        }
        if(($ExpectedConfigIdentity-and$context.ConfigIdentity-cne$ExpectedConfigIdentity)-or($ExpectedPolicyIdentity-and$context.PolicyIdentity-cne$ExpectedPolicyIdentity)){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
        $currentRules=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach($rule in $context.Policy.rules){
            if($rule.ruleId-isnot[string]-or-not$currentRules.TryAdd($rule.ruleId,$rule)){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
        }
        $requestedIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($rule in $requestedRules){
            if($rule.ruleId-isnot[string]-or-not$requestedIds.Add($rule.ruleId)-or-not$currentRules.ContainsKey($rule.ruleId)-or(Get-AiwContentDescriptorIdentity $rule)-cne(Get-AiwContentDescriptorIdentity $currentRules[$rule.ruleId])){throw 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET'}
        }
        $owner=[pscustomobject]@{context=$context;bindings=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);permissionIdentity=(Get-AiwContentDescriptorIdentity $context.Config.sourceBindings);units=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);raw=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);remoteRaw=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);text=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);resolved=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)}
        foreach($binding in $context.Config.sourceBindings){$owner.bindings.Add([string]$binding.id,[pscustomobject]@{value=$binding;identity=(Get-AiwContentDescriptorIdentity $binding)})}
        $adopted=@(foreach($rule in $context.Policy.rules){if($requestedIds.Contains([string]$rule.ruleId)-and$null-ne$rule.PSObject.Properties['source']){[pscustomobject]@{ruleId=[string]$rule.ruleId;descriptor=$rule.source;identity=(Get-AiwContentDescriptorIdentity $rule.source)}}})
        $result=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach($item in $adopted){
            try{
                $frame=New-CsOwnedGraph $owner $item.descriptor $item.identity
                $graph=Read-CsOwnedGraph $owner $frame
                $result.Add($item.ruleId,[pscustomobject]@{snapshot=$frame.snapshot;graph=$graph;error='NONE'})
            }catch{
                if($_.Exception.Message-cnotmatch'^SOURCE_UNAVAILABLE(?:\||$)'){throw}
                $result.Add($item.ruleId,[pscustomobject]@{snapshot=$null;graph=$null;error=[string]$_.Exception.Message})
            }
        }
        # A complete body comes from the actual observation used above.
        # Ordinary rule reading does not promise a cross-file instant and does
        # not rescan every file to create that promise. Recheck the current
        # authority/adoption carriers before exposing this private result.
        Assert-CsCurrent $context
        # Materialize the complete batch before exposing any output. The
        # compositor's trace callbacks cannot mutate an active private owner.
        return [pscustomobject]@{rules=$result;contextFacts=[pscustomobject]@{ProjectRoot=$context.ProjectRoot;Config=[pscustomobject]@{sourceBindings=$context.Config.sourceBindings};ConfigIdentity=$context.ConfigIdentity;PolicyIdentity=$context.PolicyIdentity;ImplementationIdentity=$context.ImplementationIdentity}}
    }finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
}
