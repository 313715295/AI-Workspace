Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
$script:FormatUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:FormatModulePath=$PSCommandPath
$script:FormatVersionRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Copy-AiwFormatValue($Value) {
    $json=$Value|ConvertTo-Json -Depth 100 -Compress
    if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){return $json|ConvertFrom-Json -Depth 100 -DateKind String}
    return (ConvertFrom-AiwStrictInputJson $json).Value
}
function Get-OfLexicalPath([string]$Path,[string[]]$Forbidden=@()) {
    $full=[IO.Path]::GetFullPath($Path)
    foreach($scope in $Forbidden){$denied=[IO.Path]::GetFullPath($scope);if($full.Equals($denied,[StringComparison]::OrdinalIgnoreCase)-or$full.StartsWith($denied.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'FORMAT_SOURCE_DENIED'}}
    if($full.StartsWith('\\')){throw 'FORMAT_SOURCE_DENIED'}
    return $full
}
function Assert-OfPath([string]$Path,[string[]]$Forbidden=@()) {
    $full=Get-OfLexicalPath $Path $Forbidden
    $anchor=[IO.Path]::GetPathRoot($full);$cursor=$anchor
    foreach($part in @('')+@($full.Substring($anchor.Length)-split'[\\/]'|Where-Object{$_.Length})){
        if($part.Length){$cursor=Join-Path $cursor $part}
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'FORMAT_SOURCE_REPARSE'}
    }
    return $full
}
function Read-OfJson([string]$Path,[string[]]$Forbidden=@()) {
    $resolved=Assert-OfPath $Path $Forbidden;$bytes=[IO.File]::ReadAllBytes($resolved);$text=$script:FormatUtf8.GetString($bytes)
    $parsed=ConvertFrom-AiwStrictInputJson $text
    $value=if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$text|ConvertFrom-Json -Depth 100 -DateKind String}else{$parsed.Value}
    return [pscustomobject]@{Path=$resolved;Bytes=$bytes;Identity=(Get-AiwContentByteIdentity $bytes);Value=$value}
}
function Assert-OfFields($Value,[string[]]$Fields) {
    if($Value-isnot[pscustomobject]){throw 'FORMAT_ASSEMBLY_FIELDS'}
    $names=@($Value.PSObject.Properties.Name)
    if($names.Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$names}).Count){throw 'FORMAT_ASSEMBLY_FIELDS'}
}
function Get-AiwObjectFormatAssembly {
    [CmdletBinding()]param([string]$AssemblyPath=(Join-Path $script:FormatVersionRoot 'object-formats/ASSEMBLY.json'))
    $read=Read-OfJson $AssemblyPath;$assembly=$read.Value;Assert-OfFields $assembly @('schemaVersion','objectTypes')
    if($assembly.schemaVersion-ne1-or$assembly.objectTypes-isnot[Array]){throw 'FORMAT_ASSEMBLY_VALUES'}
    $types=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($type in $assembly.objectTypes){
        $fields=@('objectType','targetFormat','storageClass','supportedStarts','entries','adapters')
        $nativePlan=$null-ne$type.PSObject.Properties['readFormats']
        if($nativePlan){
            $fields+='readFormats'
            if($type.objectType-cne'ACCEPTANCE_PLAN'-or$type.storageClass-cne'IMMUTABLE_EVIDENCE'-or$type.targetFormat-ne1-or$type.readFormats-isnot[Array]-or($type.readFormats-join'|')-cne'1|2'-or($type.supportedStarts-join'|')-cne'1|2'-or$type.entries.Count-or$type.adapters.Count){throw 'FORMAT_IMMUTABLE_READ_FORMATS'}
        }
        Assert-OfFields $type $fields
        if($type.objectType-isnot[string]-or-not$types.Add($type.objectType)-or($type.targetFormat-isnot[int]-and$type.targetFormat-isnot[long])-or$type.targetFormat-lt1-or$type.storageClass-cnotin@('MUTABLE_PROJECT','IMMUTABLE_EVIDENCE','EXTERNAL_READ_ONLY')-or$type.supportedStarts-isnot[Array]-or$type.entries-isnot[Array]-or$type.adapters-isnot[Array]){throw 'FORMAT_ASSEMBLY_VALUES'}
        $starts=[Collections.Generic.HashSet[int]]::new();foreach($start in $type.supportedStarts){if(($start-isnot[int]-and$start-isnot[long])-or$start-lt1-or-not$starts.Add($start)){throw 'FORMAT_START_DUPLICATE'}}
        if(-not$starts.Contains($type.targetFormat)){throw 'FORMAT_CURRENT_START_REQUIRED'}
        $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($segment in $type.adapters){
            Assert-OfFields $segment @('adapterId','fromFormat','toFormat','implementationLocator','implementationIdentity','next')
            if($segment.adapterId-isnot[string]-or-not$ids.Add($segment.adapterId)-or($segment.fromFormat-isnot[int]-and$segment.fromFormat-isnot[long])-or($segment.toFormat-isnot[int]-and$segment.toFormat-isnot[long])-or$segment.fromFormat-ge$segment.toFormat-or$segment.toFormat-gt$type.targetFormat){throw 'FORMAT_NON_ADVANCING_SEGMENT'}
            if($segment.implementationLocator-isnot[string]-or$segment.implementationLocator-cnotmatch'^adapters/[A-Za-z0-9._-]+\.ps1$'-or$segment.implementationIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$segment.next-isnot[string]){throw 'FORMAT_SEGMENT_IMPLEMENTATION'}
        }
        $entryStarts=[Collections.Generic.HashSet[int]]::new()
        foreach($entry in $type.entries){Assert-OfFields $entry @('fromFormat','adapterId');if(($entry.fromFormat-isnot[int]-and$entry.fromFormat-isnot[long])-or-not$entryStarts.Add($entry.fromFormat)-or-not$starts.Contains($entry.fromFormat)-or$entry.fromFormat-eq$type.targetFormat-or-not$ids.Contains($entry.adapterId)){throw 'FORMAT_ENTRY_AMBIGUOUS_OR_MISSING'}}
        foreach($start in $type.supportedStarts){if($start-ne$type.targetFormat-and-not$nativePlan-and-not$entryStarts.Contains($start)){throw 'FORMAT_ENTRY_MISSING'}}
    }
    return [pscustomobject]@{Value=$assembly;Path=$read.Path;Identity=$read.Identity}
}
function Assert-AiwCurrentObjectValue([string]$ObjectType,$Value,[string]$VersionRoot=$script:FormatVersionRoot) {
    $schema=switch($ObjectType){PROJECT_CONFIG{'PROJECT_CONFIG_SCHEMA.json'};PROCESS_POLICY{'PROCESS_POLICY_SCHEMA.json'};PROJECT_CORRECTIONS{'PROJECT_CORRECTIONS_SCHEMA.json'};KNOWLEDGE_INDEX{'KNOWLEDGE_SCHEMA.json'};TYPED_EVIDENCE{'EVIDENCE_RECORD_SCHEMA.json'};CONTROLLER{'CONTROLLER_SCHEMA.json'};ACCEPTANCE_PLAN{'ACCEPTANCE_PLAN_SCHEMA.json'};default{$null}}
    if($ObjectType-ceq'PROJECT_CONFIG'-and$Value.controlPlaneLayout-ceq'framework-maintenance-sibling'){
        $sourceRoot=[IO.Path]::GetFullPath((Join-Path $VersionRoot '../../..'));$schemaPath=Join-Path $sourceRoot 'framework/maintenance-overlay/PROJECT_CONFIG_SCHEMA.json'
    }elseif($schema){$schemaPath=Join-Path $VersionRoot $schema}else{$schemaPath=$null}
    if($schemaPath){
        $null=Assert-OfPath $schemaPath
        if(-not(Test-Json -Json ($Value|ConvertTo-Json -Depth 100 -Compress) -SchemaFile $schemaPath -ErrorAction SilentlyContinue)){throw ('FORMAT_CURRENT_VALIDATION_FAILED|'+$ObjectType)}
    }elseif($Value-isnot[pscustomobject]-or$null-eq$Value.PSObject.Properties['schemaVersion']){throw 'FORMAT_CURRENT_VALIDATION_FAILED'}
    if($ObjectType-ceq'PROJECT_CONFIG'){Assert-AiwSourceBindings $Value.sourceBindings}
    if($ObjectType-ceq'ACCEPTANCE_PLAN'){
        Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1')
        $null=Get-AiwAcceptancePlan ('```aiw-acceptance-plan'+[char]10+($Value|ConvertTo-Json -Depth 100 -Compress)+[char]10+'```'+[char]10)
    }
}
function Read-AiwCurrentObject {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ObjectType,[Parameter(Mandatory)][string]$Locator,[Parameter(Mandatory)][string]$ExpectedIdentity,[Parameter(Mandatory)]$Context,[ValidateSet('READ_ONLY','AUTHORIZED_MUTATION')][string]$Access='READ_ONLY')
    $forbidden=@();if($null-ne$Context.PSObject.Properties['ForbiddenPaths']){$forbidden=@($Context.ForbiddenPaths)}
    $read=Read-OfJson $Locator $forbidden
    if($read.Identity-cne$ExpectedIdentity){throw 'FORMAT_ORIGINAL_IDENTITY_DRIFT'}
    $assemblyPath=Join-Path $script:FormatVersionRoot 'object-formats/ASSEMBLY.json'
    if($null-ne$Context.PSObject.Properties['AssemblyPath']){$assemblyPath=$Context.AssemblyPath}
    $assembly=Get-AiwObjectFormatAssembly $assemblyPath
    $type=@($assembly.Value.objectTypes|Where-Object{$_.objectType-ceq$ObjectType});if($type.Count-ne1){throw 'FORMAT_OBJECT_TYPE_UNSUPPORTED'};$type=$type[0]
    $format=$read.Value.schemaVersion
    if(($format-isnot[int]-and$format-isnot[long])-or$format-cnotin$type.supportedStarts){throw 'FORMAT_START_UNSUPPORTED'}
    $originalFormat=$format;$value=Copy-AiwFormatValue $read.Value;$segments=@();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $next=$null
    $preserveOriginal=$ObjectType-ceq'ACCEPTANCE_PLAN'-and$null-ne$type.PSObject.Properties['readFormats']
    if(-not$preserveOriginal-and$format-ne$type.targetFormat){$entries=@($type.entries|Where-Object{$_.fromFormat-eq$format});if($entries.Count-ne1){throw 'FORMAT_ENTRY_AMBIGUOUS_OR_MISSING'};$next=$entries[0].adapterId}
    while(-not$preserveOriginal-and$format-ne$type.targetFormat){
        if([string]::IsNullOrWhiteSpace($next)){throw 'FORMAT_CHAIN_INCOMPLETE'}
        if(-not$seen.Add($next)){throw 'FORMAT_CHAIN_CYCLE'}
        $choices=@($type.adapters|Where-Object{$_.adapterId-ceq$next});if($choices.Count-ne1){throw 'FORMAT_SEGMENT_AMBIGUOUS_OR_MISSING'};$segment=$choices[0]
        if($segment.fromFormat-ne$format-or$segment.toFormat-le$format){throw 'FORMAT_NON_ADVANCING_SEGMENT'}
        $implementation=Assert-OfPath (Join-Path ([IO.Path]::GetDirectoryName($assembly.Path)) $segment.implementationLocator)
        $identity=Get-AiwContentByteIdentity ([IO.File]::ReadAllBytes($implementation))
        if($identity-cne$segment.implementationIdentity){throw 'FORMAT_IMPLEMENTATION_DRIFT'}
        $result=@(& $implementation -Value $value -Context $Context)
        if($result.Count-ne1-or$result[0]-isnot[pscustomobject]-or$null-eq$result[0].PSObject.Properties['schemaVersion']-or$result[0].schemaVersion-ne$segment.toFormat){throw 'FORMAT_SEGMENT_OUTPUT_FORMAT'}
        # The executable must still be the segment whose identity was selected.
        if((Get-AiwContentByteIdentity ([IO.File]::ReadAllBytes($implementation)))-cne$identity){throw 'FORMAT_IMPLEMENTATION_DRIFT'}
        $value=$result[0];$format=$value.schemaVersion;$segments+=[pscustomobject]@{adapterId=$segment.adapterId;identity=$identity};$next=$segment.next
    }
    Assert-AiwCurrentObjectValue $ObjectType $value
    if($ObjectType-ceq'PROJECT_CONFIG'-and$originalFormat-in@(6,7)-and($null-eq$Context.PSObject.Properties['ProspectiveAdoptionProjection']-or-not$Context.ProspectiveAdoptionProjection)){
        $projectRoot=Split-Path -Parent (Split-Path -Parent $read.Path)
        foreach($relative in @('.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){
            $journalPath=Get-OfLexicalPath (Join-Path $projectRoot $relative) $forbidden
            if(Test-Path -LiteralPath $journalPath -PathType Leaf){
                $journal=Read-OfJson $journalPath $forbidden
                if($journal.Value.metadata.operation-ceq'UPGRADE_FORMAT_TRANSITION'){
                    if($journal.Value.transactionComplete-ne$true-or$journal.Value.state-cne'COMPLETE'){throw 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED'}
                    Import-Module (Join-Path ([IO.Path]::GetFullPath((Join-Path $script:FormatVersionRoot '../../..'))) 'scripts/ProjectAdoptionState.psm1')
                    Assert-AiwOriginalFormatFinalize $journal.Value
                }
            }
        }
    }
    $material=[ordered]@{originalIdentity=$read.Identity;sourceFormat=$originalFormat;targetFormat=$format;assemblyIdentity=$assembly.Identity;segments=$segments;implementationIdentity=(Get-AiwContentByteIdentity ([IO.File]::ReadAllBytes($script:FormatModulePath)))}
    $newBytes=if($segments.Count){$script:FormatUtf8.GetBytes(($value|ConvertTo-Json -Depth 100 -Compress)+"`n")}else{$read.Bytes}
    $status='CURRENT';$persisted=$false
    if($segments.Count-and$type.storageClass-ceq'MUTABLE_PROJECT'){
        $status='FORMAT_WRITE_REQUIRED'
        if($Access-ceq'AUTHORIZED_MUTATION'){
            # Persist the complete bootstrap group through the existing root
            # adoption transaction. A supplied callback is not original ADMIT.
            throw 'FORMAT_USE_ORIGINAL_ADOPTION_TRANSACTION'
        }
    }
    return [pscustomobject]@{Status=$status;Value=$value;OriginalValue=$read.Value;OriginalBytes=$read.Bytes;OriginalIdentity=$read.Identity;OriginalFormat=$originalFormat;CurrentFormat=$format;CurrentBytes=$newBytes;CurrentIdentity=(Get-AiwContentByteIdentity $newBytes);AssemblyIdentity=$assembly.Identity;Segments=$segments;RepresentationIdentity=(Get-AiwContentDescriptorIdentity $material);StorageClass=$type.storageClass;Persisted=$persisted;Authority=$false}
}
function Get-AiwLegacySourceBindingId([string]$RuleId,[string]$SourceId){return 'legacy-policy-'+$RuleId+'-'+$SourceId}
function Assert-AiwFormatAdoptionProfile {
    [CmdletBinding()]param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)][string]$VersionRoot,[Parameter(Mandatory)][string]$ExpectedVersion)
    Assert-OfFields $Profile @('schemaVersion','frameworkVersion','registrationEligible','localCandidatePilotEligible','sourceCompatibility','projectControl','objectFormats')
    Assert-OfFields $Profile.sourceCompatibility @('projectFormats','requiredCapabilities','objectFormats','runtimeStarts')
    Assert-OfFields $Profile.projectControl @('schemaVersion','processCarrierContractVersion','frameworkToolBackend','navigationProjection','taskLastWriteRequired','capabilityBinding','runtimeArtifactRoot','runtimeGitIgnoreRule')
    Assert-OfFields $Profile.objectFormats @('schemaVersion','assemblyLocator')
    if($Profile.schemaVersion-ne3-or$Profile.frameworkVersion-cne$ExpectedVersion-or$Profile.registrationEligible-isnot[bool]-or$Profile.localCandidatePilotEligible-isnot[bool]-or$Profile.projectControl.schemaVersion-ne7-or$Profile.projectControl.processCarrierContractVersion-cne$ExpectedVersion-or$Profile.projectControl.frameworkToolBackend-cne'powershell7'-or$Profile.projectControl.navigationProjection-cne'PROJECT_BOOTSTRAP_MANAGED_AGENTS'-or$Profile.projectControl.taskLastWriteRequired-ne$true-or$Profile.projectControl.capabilityBinding-cne'EXACT_ENABLED_IDS'-or$Profile.projectControl.runtimeArtifactRoot-cne'.ai-workspace/runtime'-or$Profile.projectControl.runtimeGitIgnoreRule-cne'/.ai-workspace/runtime/'-or$Profile.objectFormats.schemaVersion-ne1-or$Profile.objectFormats.assemblyLocator-cne'object-formats/ASSEMBLY.json'){throw 'ADOPTION_PROFILE_VALUES'}
    if($Profile.sourceCompatibility.projectFormats-isnot[Array]-or$Profile.sourceCompatibility.requiredCapabilities-isnot[Array]-or$Profile.sourceCompatibility.objectFormats-isnot[pscustomobject]){throw 'ADOPTION_PROFILE_VALUES'}
    Assert-OfFields $Profile.sourceCompatibility.objectFormats @('PROJECT_CONFIG','PROCESS_POLICY','PROJECT_CORRECTIONS','KNOWLEDGE_INDEX')
    if($Profile.sourceCompatibility.runtimeStarts-isnot[Array]-or$Profile.sourceCompatibility.runtimeStarts.Count-eq0){throw 'ADOPTION_PROFILE_RUNTIME_STARTS'}
    $origins=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($origin in $Profile.sourceCompatibility.runtimeStarts){Assert-OfFields $origin @('frameworkVersion','distributionId','projectConfigFormat');if($origin.frameworkVersion-cnotmatch'^\d+\.\d+\.\d+$'-or$origin.distributionId-cnotmatch'^\d+\.\d+\.\d+-snapshot\.[1-9][0-9]*$'-or($origin.projectConfigFormat-isnot[int]-and$origin.projectConfigFormat-isnot[long])-or$origin.projectConfigFormat-cnotin$Profile.sourceCompatibility.objectFormats.PROJECT_CONFIG-or-not$origins.Add($origin.distributionId)){throw 'ADOPTION_PROFILE_RUNTIME_STARTS'}}
    $assembly=Get-AiwObjectFormatAssembly (Join-Path $VersionRoot $Profile.objectFormats.assemblyLocator)
    foreach($property in $Profile.sourceCompatibility.objectFormats.PSObject.Properties){
        $type=@($assembly.Value.objectTypes|Where-Object{$_.objectType-ceq$property.Name})
        if($type.Count-ne1-or$property.Value-isnot[Array]-or[string]::Join('|',@($property.Value))-cne[string]::Join('|',@($type[0].supportedStarts))){throw 'ADOPTION_PROFILE_FORMAT_ASSEMBLY_MISMATCH'}
    }
    [string[]]$expectedFormats=@($Profile.sourceCompatibility.objectFormats.PROJECT_CONFIG|ForEach-Object{'repo-local/project-config-'+$_})
    if([string]::Join('|',@($Profile.sourceCompatibility.projectFormats))-cne[string]::Join('|',$expectedFormats)){throw 'ADOPTION_PROFILE_FORMAT_ASSEMBLY_MISMATCH'}
    return $Profile
}
function Get-AiwLegacySourceBindings($Policy) {
    $bindings=@()
    foreach($rule in $Policy.rules){
        if($null-eq$rule.PSObject.Properties['source']){continue}
        foreach($document in $rule.source.documents){
            $kind='PROJECT_RELATIVE';if($null-ne$document.PSObject.Properties['locatorKind']){$kind=$document.locatorKind}
            $root='.';$locator=$document.locator
            if($kind-ceq'ABSOLUTE_FILE'){$root=[IO.Path]::GetDirectoryName($document.locator);$locator=[IO.Path]::GetFileName($document.locator)}
            $bindings+=[pscustomobject]@{id=(Get-AiwLegacySourceBindingId $rule.ruleId $document.sourceId);provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$root};allowedPaths=@([pscustomobject]@{kind='FILE';locator=$locator});decisionLocator=$rule.decisionLocator}
        }
    }
    return $bindings
}
function Convert-AiwLegacyPolicySource($Source,[string]$RuleId,[object[]]$Bindings) {
    $documents=@()
    foreach($old in $Source.documents){
        $locator=$old.locator;if($null-ne$old.PSObject.Properties['locatorKind']-and$old.locatorKind-ceq'ABSOLUTE_FILE'){$locator=[IO.Path]::GetFileName($old.locator)}
        $document=[pscustomobject]@{sourceId=$old.sourceId;bindingId=(Get-AiwLegacySourceBindingId $RuleId $old.sourceId);revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=$locator;identity=$old.identity;mode=$old.mode;sectionStart=$old.sectionStart;sectionEnd=$old.sectionEnd;dependencies=@($old.dependencies)}
        $document.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($document)}) $Bindings;$documents+=$document
    }
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=(Get-AiwLegacySourceBindingId $RuleId $Source.rootSourceId);itemId=('legacy-'+$RuleId);revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId=$Source.rootSourceId;documents=$documents}
    $descriptor.revision=Get-AiwContentRevision $descriptor $Bindings;$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    return $descriptor
}

Export-ModuleMember -Function Copy-AiwFormatValue,Get-AiwObjectFormatAssembly,Assert-AiwCurrentObjectValue,Read-AiwCurrentObject,Get-AiwLegacySourceBindings,Convert-AiwLegacyPolicySource,Assert-AiwFormatAdoptionProfile
