Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
$script:KnowledgeUtf8=[Text.UTF8Encoding]::new($false,$true)

function Assert-KsFields($Value,[string[]]$Fields,[string]$Reason) {
    if($Value-isnot[pscustomobject]){throw $Reason}
    $actual=@($Value.PSObject.Properties.Name)
    if($actual.Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$actual}).Count){throw $Reason}
}
function Assert-KsString($Value,[string]$Reason) {
    if($Value-isnot[string]-or[string]::IsNullOrWhiteSpace($Value)-or$Value-cne$Value.Trim()){throw $Reason}
}
function Assert-KsStrings($Value,[string]$Reason,[int]$Minimum=0) {
    if($Value-isnot[Array]-or$Value.Count-lt$Minimum){throw $Reason}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($item in $Value){Assert-KsString $item $Reason;if(-not$seen.Add($item)){throw $Reason}}
}
function Test-KsInteger($Value){return $Value-is[int]-or$Value-is[long]}
function Assert-KsId($Value,[string]$Reason){Assert-KsString $Value $Reason;if($Value-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]*$'){throw $Reason}}
function Assert-KsIdentity($Value){if($Value-isnot[string]-or$Value-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'KNOWLEDGE_IDENTITY_FORMAT'}}
function Get-KsIdentity([byte[]]$Bytes){return $Bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Assert-KsTime($Value) {
    $parsed=[DateTimeOffset]::MinValue
    if($Value-isnot[string]-or$Value-cnotmatch'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$'-or-not[DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)){throw 'KNOWLEDGE_VERIFIED_AT'}
}
function Assert-KsComponent([string]$Part) {
    if($Part-in@('','.','..')-or$Part.EndsWith('.')-or$Part.EndsWith(' ')-or$Part-match'[\x00-\x1f<>:"|?*]'-or$Part.Split('.')[0]-match'^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw 'KNOWLEDGE_PATH_COMPONENT'}
}
function Assert-KsLocator($Value) {
    Assert-KsString $Value 'KNOWLEDGE_LOCATOR'
    if([IO.Path]::IsPathRooted($Value)-or$Value.Contains('\')-or$Value.Contains(':')){throw 'KNOWLEDGE_LOCATOR'}
    foreach($part in $Value.Split('/')){Assert-KsComponent $part}
}
function Get-KsAbsolute($Value) {
    Assert-KsString $Value 'KNOWLEDGE_ROOT'
    if(-not[IO.Path]::IsPathFullyQualified($Value)-or$Value.StartsWith('\\')){throw 'KNOWLEDGE_ROOT_ABSOLUTE_REQUIRED'}
    $anchor=[IO.Path]::GetPathRoot($Value)
    foreach($part in @($Value.Substring($anchor.Length).TrimEnd('\','/')-split'[\\/]')){if($part.Length){Assert-KsComponent $part}}
    return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Value))
}

# Pure structure validation is shared by every governance entry. It never opens
# a source directory, even when that source is enabled or follows updates.
function Assert-AiwFrameworkCapabilities {
    [CmdletBinding()]param([Parameter(Mandatory)]$Capabilities)
    if($Capabilities-isnot[pscustomobject]){throw 'FRAMEWORK_CAPABILITIES_TYPE'}
    $names=@($Capabilities.PSObject.Properties|ForEach-Object{[string]$_.Name})
    if(@($names|Where-Object{$_-cne'KNOWLEDGE_REFERENCE'}).Count){throw 'FRAMEWORK_CAPABILITIES_UNKNOWN'}
    if($names.Count-eq0){return}
    $knowledge=$Capabilities.KNOWLEDGE_REFERENCE
    Assert-KsFields $knowledge @('enabled','sources') 'KNOWLEDGE_CAPABILITY_FIELDS'
    if($knowledge.enabled-isnot[bool]-or$knowledge.sources-isnot[Array]){throw 'KNOWLEDGE_CAPABILITY_VALUES'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($source in $knowledge.sources){
        if($source-isnot[pscustomobject]-or$null-eq$source.PSObject.Properties['updatePolicy']){throw 'KNOWLEDGE_SOURCE_FIELDS'}
        $fields=@('id','root','indexLocator','selectionHints','updatePolicy')
        if($source.updatePolicy-ceq'PINNED'){$fields+='indexIdentity'}
        Assert-KsFields $source $fields 'KNOWLEDGE_SOURCE_FIELDS'
        Assert-KsId $source.id 'KNOWLEDGE_SOURCE_ID'
        if(-not$seen.Add($source.id)){throw 'KNOWLEDGE_SOURCE_DUPLICATE'}
        Assert-KsFields $source.root @('kind','locator') 'KNOWLEDGE_SOURCE_ROOT_FIELDS'
        if($source.root.kind-ceq'PROJECT'){
            if($source.root.locator-cne'.'){throw 'KNOWLEDGE_PROJECT_ROOT_MUST_BE_PROJECT'}
        }elseif($source.root.kind-ceq'LOCAL_DIRECTORY'){$null=Get-KsAbsolute $source.root.locator}
        else{throw 'KNOWLEDGE_SOURCE_ROOT_KIND'}
        Assert-KsLocator $source.indexLocator
        Assert-KsStrings $source.selectionHints 'KNOWLEDGE_SELECTION_HINTS'
        if($source.updatePolicy-cnotin@('PINNED','FOLLOW')){throw 'KNOWLEDGE_UPDATE_POLICY'}
        if($source.updatePolicy-ceq'PINNED'){Assert-KsIdentity $source.indexIdentity}
    }
    if($knowledge.enabled){Write-Output 'KNOWLEDGE_REFERENCE'}
}

function Assert-KsUnexcluded([string]$Path,[string[]]$Forbidden) {
    foreach($scope in $Forbidden){
        if($Path.Equals($scope,[StringComparison]::OrdinalIgnoreCase)-or$Path.StartsWith($scope+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'KNOWLEDGE_FORBIDDEN_PATH'}
    }
}
function Assert-KsNoReparse([string]$Path,[switch]$File) {
    $anchor=[IO.Path]::GetPathRoot($Path);$cursor=$anchor
    $anchorItem=Get-Item -LiteralPath $anchor -Force -ErrorAction Stop
    if(($anchorItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'KNOWLEDGE_PATH_REPARSE'}
    foreach($part in @($Path.Substring($anchor.Length)-split'[\\/]'|Where-Object{$_.Length})){
        $cursor=Join-Path $cursor $part
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'KNOWLEDGE_PATH_REPARSE'}
    }
    $last=Get-Item -LiteralPath $Path -Force
    if($File-and$last.PSIsContainer){throw 'KNOWLEDGE_NOT_FILE'}
    if(-not$File-and-not$last.PSIsContainer){throw 'KNOWLEDGE_NOT_DIRECTORY'}
}
function Resolve-KsFile([string]$Root,[string]$Locator,[string[]]$Forbidden) {
    Assert-KsLocator $Locator
    $path=[IO.Path]::GetFullPath((Join-Path $Root $Locator))
    $prefix=$Root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'KNOWLEDGE_PATH_ESCAPE'}
    # Exclusion precedes even metadata inspection of the selected file.
    Assert-KsUnexcluded $path $Forbidden
    Assert-KsNoReparse $path -File
    return $path
}
function Read-KsDocument([string]$Path,[switch]$Json) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'KNOWLEDGE_TEXT_BOM'}
    $text=$script:KnowledgeUtf8.GetString($bytes)
    if($text.Contains([char]0)-or$text.Contains([char]0xfffd)){throw 'KNOWLEDGE_TEXT_FORMAT'}
    $value=$null
    if($Json){
        $strict=ConvertFrom-AiwStrictInputJson $text
        if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$value=$text|ConvertFrom-Json -Depth 100 -DateKind String}else{$value=$strict.Value}
    }
    return [pscustomobject]@{path=$Path;identity=(Get-KsIdentity $bytes);text=$text;value=$value}
}
function New-KsContext([string]$ProjectRoot,[string]$ExpectedProjectConfigIdentity,[string[]]$ForbiddenPaths) {
    $root=Get-KsAbsolute $ProjectRoot
    $forbidden=@(foreach($scope in $ForbiddenPaths){
        Assert-KsString $scope 'KNOWLEDGE_FORBIDDEN_SCOPE'
        if([IO.Path]::IsPathFullyQualified($scope)){Get-KsAbsolute $scope}else{Assert-KsLocator $scope.TrimEnd('/');[IO.Path]::GetFullPath((Join-Path $root $scope.TrimEnd('/')))}
    })
    Assert-KsUnexcluded $root $forbidden;Assert-KsNoReparse $root
    Assert-KsIdentity $ExpectedProjectConfigIdentity
    $configDoc=Read-KsDocument (Resolve-KsFile $root '.ai-workspace/project.json' $forbidden) -Json
    if($configDoc.identity-cne$ExpectedProjectConfigIdentity){throw 'PROJECT_CONFIG_IDENTITY_DRIFT'}
    $config=$configDoc.value
    $fields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy')
    if($null-ne$config.PSObject.Properties['controlPlaneLayout']-and$config.controlPlaneLayout-ceq'framework-maintenance-sibling'){$fields+='frameworkTarget'}
    Assert-KsFields $config $fields 'PROJECT_CONFIG_FIELDS'
    if(-not(Test-KsInteger $config.schemaVersion)-or$config.schemaVersion-ne5-or$config.controlPlaneLayout-cnotin@('repo-local','framework-maintenance-sibling')-or$config.repositoryRoot-cne'..'-or$config.frameworkVersion-cne'2.0.0'-or$config.frameworkToolBackend-cne'powershell7'){throw 'PROJECT_CONFIG_VALUES'}
    Assert-KsId $config.id 'PROJECT_CONFIG_ID';Assert-KsString $config.displayName 'PROJECT_CONFIG_DISPLAY_NAME'
    Assert-KsFields $config.processPolicy @('schemaVersion','locator') 'PROJECT_CONFIG_POLICY'
    if(-not(Test-KsInteger $config.processPolicy.schemaVersion)-or$config.processPolicy.schemaVersion-ne1-or$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'){throw 'PROJECT_CONFIG_POLICY'}
    Assert-KsStrings $config.routineExcludedPaths 'PROJECT_CONFIG_EXCLUSIONS'
    foreach($scope in $config.routineExcludedPaths){Assert-KsLocator $scope.TrimEnd('/');$forbidden+=[IO.Path]::GetFullPath((Join-Path $root $scope.TrimEnd('/')))}
    if($config.controlPlaneLayout-ceq'framework-maintenance-sibling'){
        Assert-KsFields $config.frameworkTarget @('repositoryId','siblingDirectory','routineExcludedPaths') 'KNOWLEDGE_TARGET_FIELDS'
        Assert-KsString $config.frameworkTarget.siblingDirectory 'KNOWLEDGE_TARGET_SIBLING'
        Assert-KsComponent $config.frameworkTarget.siblingDirectory
        if($config.frameworkTarget.siblingDirectory-match'[\\/]'){throw 'KNOWLEDGE_TARGET_SIBLING'}
        Assert-KsStrings $config.frameworkTarget.routineExcludedPaths 'KNOWLEDGE_TARGET_EXCLUSIONS'
        $targetRoot=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $root) $config.frameworkTarget.siblingDirectory))
        Assert-KsUnexcluded $targetRoot $forbidden
        Assert-KsNoReparse $targetRoot
        # Reuse the Maintenance topology contract; no second sibling resolver.
        $topologyModule=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../scripts/MaintenanceOverlay.psm1'))
        Assert-KsNoReparse $topologyModule -File
        $module=Import-Module $topologyModule -PassThru -Force
        $topology=& $module.ExportedFunctions['Resolve-AiwMaintenanceTopology'] -ControlRepositoryPath $root -TargetRepositoryId $config.frameworkTarget.repositoryId -TargetSiblingDirectory $config.frameworkTarget.siblingDirectory -TargetRoutineExcludedPaths $config.frameworkTarget.routineExcludedPaths
        foreach($scope in $topology.TargetRoutineExcludedPaths){$forbidden+=[IO.Path]::GetFullPath((Join-Path $topology.TargetRoot $scope))}
    }
    $enabled=@(Assert-AiwFrameworkCapabilities $config.frameworkCapabilities)
    if('KNOWLEDGE_REFERENCE'-cnotin$enabled){throw 'KNOWLEDGE_CAPABILITY_DISABLED'}
    return [pscustomobject]@{root=$root;projectId=$config.id;configIdentity=$configDoc.identity;sources=@($config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources);forbidden=$forbidden}
}

function Assert-KsIndex($Index,$Source,[string]$ProjectId) {
    Assert-KsFields $Index @('schemaVersion','libraryId','entries') 'KNOWLEDGE_INDEX_FIELDS'
    if(-not(Test-KsInteger $Index.schemaVersion)-or$Index.schemaVersion-ne3-or$Index.entries-isnot[Array]){throw 'KNOWLEDGE_INDEX_SCHEMA'}
    Assert-KsId $Index.libraryId 'KNOWLEDGE_LIBRARY_ID'
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in $Index.entries){
        if($entry-isnot[pscustomobject]-or$null-eq$entry.PSObject.Properties['kind']){throw 'KNOWLEDGE_ENTRY_FIELDS'}
        $fields=@('id','kind','state','title','summary','tags','locator','identity','verifiedAt','invalidatesOn','tokenEstimate')
        if($entry.kind-ceq'PROJECT_DERIVED'){$fields+=@('projectId','authorityDependencies')}
        elseif($entry.kind-ceq'METHOD'){$fields+=@('originalSources','applicability','contentVersion','maintenance')}
        else{throw 'KNOWLEDGE_ENTRY_KIND'}
        Assert-KsFields $entry $fields 'KNOWLEDGE_ENTRY_FIELDS'
        Assert-KsId $entry.id 'KNOWLEDGE_ENTRY_ID'
        if(-not$ids.Add($entry.id)){throw 'KNOWLEDGE_ENTRY_DUPLICATE'}
        if($entry.state-cnotin@('CURRENT','STALE','HISTORICAL')){throw 'KNOWLEDGE_ENTRY_STATE'}
        Assert-KsString $entry.title 'KNOWLEDGE_ENTRY_TITLE';Assert-KsString $entry.summary 'KNOWLEDGE_ENTRY_SUMMARY'
        Assert-KsStrings $entry.tags 'KNOWLEDGE_ENTRY_TAGS';Assert-KsLocator $entry.locator;Assert-KsIdentity $entry.identity;Assert-KsTime $entry.verifiedAt
        Assert-KsStrings $entry.invalidatesOn 'KNOWLEDGE_INVALIDATORS' 1
        if(-not(Test-KsInteger $entry.tokenEstimate)-or$entry.tokenEstimate-lt1){throw 'KNOWLEDGE_TOKEN_ESTIMATE'}
        if($entry.kind-ceq'PROJECT_DERIVED'){
            if($Source.root.kind-cne'PROJECT'-or$entry.projectId-cne$ProjectId){throw 'KNOWLEDGE_PROJECT_DERIVED_SOURCE_MISMATCH'}
            if(($entry.invalidatesOn-join'|')-cne'REFERENCE_IDENTITY_CHANGE|AUTHORITY_DEPENDENCY_IDENTITY_CHANGE'-or$entry.authorityDependencies-isnot[Array]-or$entry.authorityDependencies.Count-eq0){throw 'KNOWLEDGE_AUTHORITY_DEPENDENCIES'}
            $deps=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($dependency in $entry.authorityDependencies){
                Assert-KsFields $dependency @('locator','identity') 'KNOWLEDGE_DEPENDENCY_FIELDS';Assert-KsLocator $dependency.locator;Assert-KsIdentity $dependency.identity
                if(-not$deps.Add($dependency.locator)){throw 'KNOWLEDGE_DEPENDENCY_DUPLICATE'}
            }
        }else{
            if(($entry.invalidatesOn-join'|')-cne'REFERENCE_IDENTITY_CHANGE|CONTENT_VERSION_CHANGE'){throw 'KNOWLEDGE_INVALIDATORS'}
            Assert-KsStrings $entry.applicability 'KNOWLEDGE_APPLICABILITY' 1
            Assert-KsString $entry.contentVersion 'KNOWLEDGE_CONTENT_VERSION'
            Assert-KsFields $entry.maintenance @('owner','locator') 'KNOWLEDGE_MAINTENANCE_FIELDS'
            Assert-KsString $entry.maintenance.owner 'KNOWLEDGE_MAINTENANCE_OWNER';Assert-KsLocator $entry.maintenance.locator
            if($entry.originalSources-isnot[Array]){throw 'KNOWLEDGE_ORIGINAL_SOURCES'}
            foreach($original in $entry.originalSources){
                Assert-KsFields $original @('title','url','accessedAt','licenseNotice') 'KNOWLEDGE_ORIGINAL_SOURCE_FIELDS'
                Assert-KsString $original.title 'KNOWLEDGE_ORIGINAL_SOURCE_TITLE';Assert-KsTime $original.accessedAt;Assert-KsString $original.licenseNotice 'KNOWLEDGE_LICENSE_NOTICE'
                $uri=$null
                if($original.url-isnot[string]-or-not[Uri]::TryCreate($original.url,[UriKind]::Absolute,[ref]$uri)-or$uri.Scheme-cnotin@('http','https')){throw 'KNOWLEDGE_ORIGINAL_SOURCE_URL'}
            }
        }
    }
}
function Open-KsSource($Context,$Source) {
    $result=[ordered]@{sourceId=$Source.id;libraryId='NOT_OBSERVED';root='NOT_OBSERVED';indexLocator=$Source.indexLocator;indexIdentity='NOT_OBSERVED';status='UNAVAILABLE';reason='NOT_OBSERVED';entries=@()}
    try{
        $root=if($Source.root.kind-ceq'PROJECT'){$Context.root}else{Get-KsAbsolute $Source.root.locator}
        $result.root=$root
        Assert-KsUnexcluded $root $Context.forbidden;Assert-KsNoReparse $root
        $index=Read-KsDocument (Resolve-KsFile $root $Source.indexLocator $Context.forbidden) -Json
        $result.indexIdentity=$index.identity
        if($Source.updatePolicy-ceq'PINNED'-and$index.identity-cne$Source.indexIdentity){$result.status='STALE';$result.reason='INDEX_IDENTITY_DRIFT';return [pscustomobject]$result}
        Assert-KsIndex $index.value $Source $Context.projectId
        $result.libraryId=$index.value.libraryId;$result.entries=@($index.value.entries);$result.status='CURRENT';$result.reason='INDEX_VALID'
    }catch{$result.reason=$_.Exception.Message}
    return [pscustomobject]$result
}
function Get-KsSelectedSources($Context,[string[]]$SourceId) {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($id in $SourceId){
        Assert-KsId $id 'KNOWLEDGE_SOURCE_ID';if(-not$seen.Add($id)){throw 'KNOWLEDGE_SOURCE_DUPLICATE'}
        $match=@($Context.sources|Where-Object{$_.id-ceq$id})
        if($match.Count-ne1){throw 'KNOWLEDGE_SOURCE_UNKNOWN'}
        Write-Output $match[0]
    }
}
function Get-KsSourceObservation($Source) {
    return [pscustomobject]@{sourceId=$Source.sourceId;libraryId=$Source.libraryId;root=$Source.root;indexLocator=$Source.indexLocator;indexIdentity=$Source.indexIdentity;status=$Source.status;reason=$Source.reason}
}
function Get-KsEntry($Context,$Opened,$Entry,[string]$ContentMode) {
    $row=[ordered]@{id=($Opened.sourceId+':'+$Entry.id);sourceId=$Opened.sourceId;libraryId=$Opened.libraryId;indexIdentity=$Opened.indexIdentity;kind=$Entry.kind;title=$Entry.title;declaredState=$Entry.state;locator=$Entry.locator;identity=$Entry.identity;observedIdentity='NOT_OBSERVED';authorityDependencies=@();status='UNAVAILABLE';reason='ENTRY_NOT_CURRENT'}
    if($Entry.state-cne'CURRENT'){$row.status='STALE';return [pscustomobject]$row}
    try{
        $body=Read-KsDocument (Resolve-KsFile $Opened.root $Entry.locator $Context.forbidden)
        $row.observedIdentity=$body.identity
        if($body.identity-cne$Entry.identity){$row.status='STALE';$row.reason='REFERENCE_IDENTITY_CHANGE';return [pscustomobject]$row}
        if($Entry.kind-ceq'PROJECT_DERIVED'){
            foreach($dependency in $Entry.authorityDependencies){
                $path=Resolve-KsFile $Opened.root $dependency.locator $Context.forbidden
                $identity=Get-KsIdentity ([IO.File]::ReadAllBytes($path))
                $row.authorityDependencies+=@([pscustomobject]@{locator=$dependency.locator;identity=$dependency.identity;observedIdentity=$identity})
                if($identity-cne$dependency.identity){$row.status='STALE';$row.reason='AUTHORITY_DEPENDENCY_IDENTITY_CHANGE';return [pscustomobject]$row}
            }
        }else{
            $row.originalSources=$Entry.originalSources;$row.applicability=$Entry.applicability;$row.contentVersion=$Entry.contentVersion;$row.maintenance=$Entry.maintenance
        }
        $row.status='CURRENT';$row.reason='REFERENCE_AND_DEPENDENCIES_VALID'
        if($ContentMode-ceq'FULLTEXT'){$row.fullText=$body.text}
    }catch{$row.reason=$_.Exception.Message}
    return [pscustomobject]$row
}

function Invoke-AiwKnowledgeQuery {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
        [ValidateSet('DISCOVER','QUERY')][string]$Operation='DISCOVER',[string[]]$SourceId=@(),[string[]]$EntryId=@(),
        [ValidateSet('LOCATOR_ONLY','FULLTEXT')][string]$ContentMode='LOCATOR_ONLY',[string[]]$ForbiddenPaths=@()
    )
    $ctx=New-KsContext $ProjectRoot $ExpectedProjectConfigIdentity $ForbiddenPaths
    if($Operation-ceq'DISCOVER'){
        if($EntryId.Count-or$ContentMode-cne'LOCATOR_ONLY'){throw 'KNOWLEDGE_DISCOVER_METADATA_ONLY'}
        if($SourceId.Count-eq0){return [pscustomobject]@{status='KNOWLEDGE_SOURCES';operation=$Operation;referenceOnly=$true;authority=$false;projectConfigIdentity=$ctx.configIdentity;sources=$ctx.sources;entries=@()}}
        $entries=@();$observations=@()
        foreach($source in @(Get-KsSelectedSources $ctx $SourceId)){
            $opened=Open-KsSource $ctx $source;$observations+=Get-KsSourceObservation $opened
            if($opened.status-cne'CURRENT'){continue}
            foreach($entry in $opened.entries){
                $deps=@(if($entry.kind-ceq'PROJECT_DERIVED'){$entry.authorityDependencies.locator})
                $entries+=[pscustomobject]@{id=($source.id+':'+$entry.id);sourceId=$source.id;libraryId=$opened.libraryId;indexIdentity=$opened.indexIdentity;kind=$entry.kind;title=$entry.title;tags=$entry.tags;state=$entry.state;locator=$entry.locator;authorityLocators=$deps}
            }
        }
        return [pscustomobject]@{status='KNOWLEDGE_CATALOG';operation=$Operation;referenceOnly=$true;authority=$false;projectConfigIdentity=$ctx.configIdentity;sources=$observations;entries=$entries}
    }
    if($SourceId.Count-or$EntryId.Count-eq0){throw 'KNOWLEDGE_QUERY_QUALIFIED_IDS_REQUIRED'}
    $requested=@();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($id in $EntryId){
        if($id-cnotmatch'^([A-Za-z0-9][A-Za-z0-9._-]*):([A-Za-z0-9][A-Za-z0-9._-]*)$'-or-not$seen.Add($id)){throw 'KNOWLEDGE_QUERY_ID_INVALID_OR_DUPLICATE'}
        $requested+=[pscustomobject]@{id=$id;sourceId=$Matches[1];entryId=$Matches[2]}
    }
    $selected=@(Get-KsSelectedSources $ctx @($requested.sourceId|Select-Object -Unique))
    $openedById=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($source in $selected){$openedById.Add($source.id,(Open-KsSource $ctx $source))}
    $rows=@()
    foreach($request in $requested){
        $opened=$openedById[$request.sourceId]
        $entry=@($opened.entries|Where-Object{$_.id-ceq$request.entryId})
        if($opened.status-cne'CURRENT'-or$entry.Count-ne1){
            $rows+=[pscustomobject]@{id=$request.id;sourceId=$request.sourceId;libraryId=$opened.libraryId;indexIdentity=$opened.indexIdentity;status=$(if($opened.status-ceq'CURRENT'){'UNAVAILABLE'}else{$opened.status});reason=$(if($opened.status-ceq'CURRENT'){'ENTRY_ID_UNKNOWN'}else{$opened.reason})}
        }else{$rows+=Get-KsEntry $ctx $opened $entry[0] $ContentMode}
    }
    return [pscustomobject]@{status='KNOWLEDGE_QUERY_RESULT';operation=$Operation;referenceOnly=$true;authority=$false;projectConfigIdentity=$ctx.configIdentity;contentMode=$ContentMode;sources=@($selected|ForEach-Object{Get-KsSourceObservation $openedById[$_.id]});entries=$rows}
}

function Invoke-AiwKnowledgeImpact {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
        [Parameter(Mandatory)][string[]]$ChangedAuthorityPath,[string[]]$SourceId=@(),[string[]]$ForbiddenPaths=@()
    )
    $ctx=New-KsContext $ProjectRoot $ExpectedProjectConfigIdentity $ForbiddenPaths
    $changed=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if($ChangedAuthorityPath.Count-eq0){throw 'KNOWLEDGE_CHANGED_PATHS_REQUIRED'}
    foreach($path in $ChangedAuthorityPath){Assert-KsLocator $path;if(-not$changed.Add($path)){throw 'KNOWLEDGE_CHANGED_PATH_DUPLICATE'}}
    if($SourceId.Count-eq0){$SourceId=@($ctx.sources|Where-Object{$_.root.kind-ceq'PROJECT'}|ForEach-Object{$_.id})}
    $rows=@();$observations=@()
    foreach($source in @(Get-KsSelectedSources $ctx $SourceId)){
        $opened=Open-KsSource $ctx $source;$observations+=Get-KsSourceObservation $opened
        if($opened.status-cne'CURRENT'){continue}
        foreach($entry in $opened.entries){
            $overlap=@();if($source.root.kind-ceq'PROJECT'-and$entry.kind-ceq'PROJECT_DERIVED'){$overlap=@($entry.authorityDependencies.locator|Where-Object{$changed.Contains($_)})}
            $observed=Get-KsEntry $ctx $opened $entry 'LOCATOR_ONLY'
            $impact=if($overlap.Count){'DIRECT_AFFECTED'}elseif($observed.status-ceq'CURRENT'){'NONE_DIRECT'}else{'UNKNOWN'}
            $rows+=[pscustomobject]@{id=$observed.id;sourceId=$source.id;libraryId=$opened.libraryId;indexIdentity=$opened.indexIdentity;impact=$impact;overlap=$overlap;referenceStatus=$observed.status;reason=$observed.reason}
        }
    }
    return [pscustomobject]@{status='KNOWLEDGE_IMPACT_RESULT';referenceOnly=$true;authority=$false;projectConfigIdentity=$ctx.configIdentity;sources=$observations;entries=$rows}
}

# Migration returns data only. The existing root adoption transaction owns the
# prospective index, project configuration, identities and rollback together.
function Convert-AiwLegacyKnowledgeIndex {
    [CmdletBinding()]param([Parameter(Mandatory)]$Index,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$LibraryId)
    Assert-KsFields $Index @('schemaVersion','projectId','entries') 'LEGACY_KNOWLEDGE_INDEX_FIELDS'
    if(-not(Test-KsInteger $Index.schemaVersion)-or$Index.schemaVersion-cnotin@(1,2)-or$Index.projectId-cne$ProjectId-or$Index.entries-isnot[Array]){throw 'LEGACY_KNOWLEDGE_INDEX_VALUES'}
    $entries=@()
    foreach($entry in $Index.entries){
        $fields=@('id','state','title','summary','locator','identity','verifiedAt','invalidatesOn','tokenEstimate')
        if($Index.schemaVersion-eq1){$fields+=@('authorityLocator','authorityIdentity')}else{$fields+=@('tags','authorityDependencies')}
        Assert-KsFields $entry $fields 'LEGACY_KNOWLEDGE_ENTRY_FIELDS'
        $invalidators=if($Index.schemaVersion-eq1){'LOCATOR_IDENTITY_CHANGE|AUTHORITY_IDENTITY_CHANGE'}else{'REFERENCE_IDENTITY_CHANGE|AUTHORITY_DEPENDENCY_IDENTITY_CHANGE'}
        if($entry.invalidatesOn-isnot[Array]-or($entry.invalidatesOn-join'|')-cne$invalidators){throw 'LEGACY_KNOWLEDGE_INVALIDATORS'}
        $dependencies=@(if($Index.schemaVersion-eq1){[pscustomobject]@{locator=$entry.authorityLocator;identity=$entry.authorityIdentity}}else{$entry.authorityDependencies})
        $tags=@(if($Index.schemaVersion-eq2){$entry.tags})
        $entries+=[pscustomobject]@{id=$entry.id;kind='PROJECT_DERIVED';state=$entry.state;title=$entry.title;summary=$entry.summary;tags=$tags;locator=$entry.locator;identity=$entry.identity;verifiedAt=$entry.verifiedAt;invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE');tokenEstimate=$entry.tokenEstimate;projectId=$ProjectId;authorityDependencies=$dependencies}
    }
    $result=[pscustomobject]@{schemaVersion=3;libraryId=$LibraryId;entries=$entries}
    Assert-KsIndex $result ([pscustomobject]@{root=[pscustomobject]@{kind='PROJECT'}}) $ProjectId
    return $result
}
Export-ModuleMember -Function Assert-AiwFrameworkCapabilities,Invoke-AiwKnowledgeQuery,Invoke-AiwKnowledgeImpact,Convert-AiwLegacyKnowledgeIndex
