Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'KnowledgeSources.psm1')
Import-Module (Join-Path $PSScriptRoot 'ObjectFormats.psm1')
Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1')
$script:Utf8Strict = [Text.UTF8Encoding]::new($false,$true)
$script:ComposerModulePath=$PSCommandPath
$script:ProcessCarrierContractVersion = '2.0.0'
$script:AbsoluteSelectedRulePackBytes = 98304
$script:PublicationTargetStandards=$null

function Get-AiwRuntimeActorStorageKey([string]$Actor) {
    if([string]::IsNullOrWhiteSpace($Actor)){throw 'RUNTIME_ACTOR_EMPTY'}
    if($Actor-cmatch'^[a-z0-9][a-z0-9._-]*$'-and-not$Actor.EndsWith('.')-and$Actor-cnotmatch'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)'-and-not$Actor.StartsWith('actor-sha256-',[StringComparison]::Ordinal)){return $Actor}
    return 'actor-sha256-'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:Utf8Strict.GetBytes($Actor))).ToLowerInvariant()
}
Export-ModuleMember -Function Get-AiwRuntimeActorStorageKey

function Get-AiwProcessSemanticText {
    param([Parameter(Mandatory)]$IntentEnvelope)
    # The consumed version owns the IntentEnvelope-to-selection projection.
    return [string]::Join(' ', @($IntentEnvelope.semanticHints))
}

function Get-AiwProcessDecisionIdentity($Receipt,$Boundary,[string]$PostimageSourceIdentity='NO_SOURCE_POSTIMAGE_TRANSITION',[string[]]$ChangedBindings=@()) {
    $authority=if($null-ne$Receipt.PSObject.Properties['binding']){$Receipt.binding}else{$Receipt.authorityContext}
    $intent=$Receipt.intentEnvelope
    $material=@($Receipt.sourceCompositionIdentity,$Receipt.selectionIdentity,$Receipt.contextIdentity,[string]$Boundary.mode,[string]$intent.objective,[string]$intent.requestedActionKind,[string]$intent.requestedResultKind,[string]::Join(',',@($authority.exactScope)),[string]$authority.authorizationIdentity,[string]::Join(',',@($Boundary.preparationReceipts)),[string]::Join(',',@($Boundary.resultReceipts)),[string]::Join(',',@($Boundary.deliveryReceipts)),[string]$Boundary.publicDecisionIdentity,[string]$Boundary.protectionState,$PostimageSourceIdentity,[string]::Join(',',@($ChangedBindings|Sort-Object)))-join"`n"
    if($null-ne$Boundary.PSObject.Properties['deliveryContext']){$material+=($Boundary.deliveryContext|ConvertTo-Json -Compress)}
    if($null-ne$Boundary.PSObject.Properties['evidenceRefs']){$material+=($Boundary.evidenceRefs|ConvertTo-Json -Depth 30 -Compress)}
    if($null-ne$Boundary.PSObject.Properties['continuationDisposition']){$material+=("`ncontinuationDisposition="+[string]$Boundary.continuationDisposition)}
    if($null-ne$Boundary.PSObject.Properties['productionFinalizeRef']){$material+=($Boundary.productionFinalizeRef|ConvertTo-Json -Depth 10 -Compress)}
    return Get-AiwSha256Hex $script:Utf8Strict.GetBytes($material)
}
Export-ModuleMember -Function Get-AiwProcessDecisionIdentity

function Test-AiwJsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Get-AiwSha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','')}
    finally{$sha.Dispose()}
}

function New-AiwDisplayPart([string]$SourceLocator,[string]$SourceIdentity,[string]$FullText,[string]$UnitIdentity,[string[]]$OrderedDependencies=@()) {
    $part=[pscustomobject]@{sourceLocator=$SourceLocator;sourceIdentity=$SourceIdentity;fullText=$FullText;orderedDependencies=@($OrderedDependencies)}
    if($UnitIdentity){
        if($UnitIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){$UnitIdentity=Get-AiwContentDescriptorIdentity $UnitIdentity}
        $part|Add-Member unitIdentity $UnitIdentity
    }
    return $part
}

# Historical installation checks may accept layout alone; receipts still bind raw bytes.
function Test-AiwInstalledTextLayout([string]$Text,[string]$ExpectedIdentity) {
    $lf=$Text.Replace("`r`n","`n")
    $withoutFinal=if($lf.EndsWith("`n")){$lf.Substring(0,$lf.Length-1)}else{$lf}
    foreach($variant in @($Text,$withoutFinal,($withoutFinal+"`n"),$withoutFinal.Replace("`n","`r`n"),($withoutFinal+"`n").Replace("`n","`r`n"))){
        $bytes=$script:Utf8Strict.GetBytes($variant)
        if(($bytes.Length.ToString()+'|'+(Get-AiwSha256Hex $bytes))-ceq$ExpectedIdentity){return $true}
    }
    return $false
}

function Get-AiwFileIdentity {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    return $bytes.Length.ToString() + '|' + (Get-AiwSha256Hex $bytes)
}

function Assert-AiwNoDuplicateJsonMember {
    param([Parameter(Mandatory)]$Element,[string]$Locator='$')
    if ([string]$Element.ValueKind -ceq 'Object') {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { throw "JSON_DUPLICATE_FIELD|$Locator.$($property.Name)" }
            Assert-AiwNoDuplicateJsonMember -Element $property.Value -Locator "$Locator.$($property.Name)"
        }
    } elseif ([string]$Element.ValueKind -ceq 'Array') {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Assert-AiwNoDuplicateJsonMember -Element $item -Locator "$Locator[$index]"
            $index++
        }
    }
}

function Read-AiwStrictJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label}_MISSING" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "${Label}_REPARSE" }
    try { $bytes = [IO.File]::ReadAllBytes($item.FullName) } catch { throw "${Label}_UNREADABLE" }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "${Label}_BOM" }
    try { $text = $script:Utf8Strict.GetString($bytes) } catch { throw "${Label}_UTF8" }
    if ($text.Contains([char]0) -or $text.Contains([char]0xFFFD)) { throw "${Label}_TEXT_FORMAT" }
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($text)
        try { Assert-AiwNoDuplicateJsonMember -Element $document.RootElement } finally { $document.Dispose() }
        $value = $text | ConvertFrom-Json -Depth 100
    } catch { throw "${Label}_JSON|$($_.Exception.Message)" }
    # Bind the parsed value to the exact byte snapshot used above. A second read
    # can pair an old parsed value with a newer identity after a concurrent edit.
    return [pscustomobject]@{ Value=$value; Text=$text; Identity=($bytes.Length.ToString()+'|'+(Get-AiwSha256Hex $bytes)); Path=$item.FullName }
}

function Read-AiwStrictText {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label}_MISSING" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "${Label}_REPARSE" }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "${Label}_BOM" }
    try { $text = $script:Utf8Strict.GetString($bytes) } catch { throw "${Label}_UTF8" }
    if ($text.Contains([char]0) -or $text.Contains([char]0xFFFD)) { throw "${Label}_TEXT_FORMAT" }
    return $text
}

function Get-AiwNativeRuleBlock {
    param(
        [Parameter(Mandatory)][string]$VersionDirectory,
        [Parameter(Mandatory)][string]$OwnerModule,
        [Parameter(Mandatory)][string]$RequirementId,
        [Parameter(Mandatory)][string]$ExactBlockLocator,
        [Parameter(Mandatory)][hashtable]$OwnerTextCache,
        $ReadTrace=$null,
        $PackageObservation=$null
    )
    if ($OwnerModule -cnotmatch '^[A-Z0-9_]+\.md$' -or $ExactBlockLocator -cne ('AIW-REQUIREMENT:' + $RequirementId)) { throw ('NATIVE_REQUIREMENT_LOCATOR|' + $RequirementId) }
    if (-not $OwnerTextCache.ContainsKey($OwnerModule)) {
        $ownerPath = Resolve-AiwChildFile $VersionDirectory $OwnerModule 'NATIVE_REQUIREMENT_OWNER'
        $OwnerTextCache[$OwnerModule] = Read-AiwStrictText $ownerPath 'NATIVE_REQUIREMENT_OWNER'
        $ownerIdentity=Get-AiwContentByteIdentity $script:Utf8Strict.GetBytes([string]$OwnerTextCache[$OwnerModule])
        Assert-AiwCompositionPackageMember $PackageObservation ('framework/versions/2.0.0/'+$OwnerModule) $ownerIdentity
        if($null-ne$ReadTrace){$ReadTrace.Add([pscustomobject]@{sequence=$ReadTrace.Count;event='NATIVE_MODULE_READ';path=$ownerPath;identity=(Get-AiwContentByteIdentity $script:Utf8Strict.GetBytes([string]$OwnerTextCache[$OwnerModule]));observation='LIVE';authority=$false})}
    }
    $ownerText = [string]$OwnerTextCache[$OwnerModule]
    $beginMarker = '<!-- ' + $ExactBlockLocator + ':BEGIN -->'
    $endMarker = '<!-- ' + $ExactBlockLocator + ':END -->'
    $begin = $ownerText.IndexOf($beginMarker, [StringComparison]::Ordinal)
    $end = $ownerText.IndexOf($endMarker, [StringComparison]::Ordinal)
    if ($begin -lt 0 -or $end -le $begin -or $ownerText.IndexOf($beginMarker, $begin + 1, [StringComparison]::Ordinal) -ge 0 -or $ownerText.IndexOf($endMarker, $end + 1, [StringComparison]::Ordinal) -ge 0) { throw ('NATIVE_REQUIREMENT_BLOCK_CARDINALITY|' + $RequirementId) }
    $bodyStart = $begin + $beginMarker.Length
    if ($bodyStart -ge $ownerText.Length -or $ownerText[$bodyStart] -cne "`n" -or $end -le $bodyStart + 1 -or $ownerText[$end - 1] -cne "`n") { throw ('NATIVE_REQUIREMENT_BLOCK_LAYOUT|' + $RequirementId) }
    $body = $ownerText.Substring($bodyStart + 1, $end - $bodyStart - 2)
    if ([string]::IsNullOrWhiteSpace($body) -or $body.Contains('<!-- AIW-REQUIREMENT:')) { throw ('NATIVE_REQUIREMENT_BLOCK_BODY|' + $RequirementId) }
    return $body
}

function Assert-AiwExactFields {
    param($Object,[string[]]$Expected,[string]$Label)
    if (-not ($Object -is [pscustomobject])) { throw "${Label}_TYPE" }
    $actual = @($Object.PSObject.Properties.Name)
    if ($actual.Count -ne $Expected.Count -or @($Expected | Where-Object { $_ -cnotin $actual }).Count -ne 0) { throw "${Label}_FIELDS" }
}

function ConvertTo-AiwSafeRelativePath {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Label)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) { throw "${Label}_EMPTY" }
    $path = $Value.Replace('\','/')
    if ([IO.Path]::IsPathRooted($path) -or $path.StartsWith('/') -or $path.Contains(':') -or [regex]::IsMatch($path,'[<>"|?*]')) { throw "${Label}_PATH" }
    if (-not [string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw "${Label}_NFC" }
    foreach ($part in $path.Split('/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or [regex]::IsMatch($part,'[\x00-\x1F]')) { throw "${Label}_COMPONENT" }
    }
    return $path
}

function Resolve-AiwChildFile {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Relative,[Parameter(Mandatory)][string]$Label,[switch]$AllowMissing)
    $safe = ConvertTo-AiwSafeRelativePath $Relative $Label
    $rootFull = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
    $candidate = [IO.Path]::GetFullPath([IO.Path]::Combine($rootFull,$safe))
    if (-not $candidate.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "${Label}_ESCAPE" }
    # Observe the physical root and every current ancestor too. A missing or
    # reparse root is not a caller-supplied proof of a safe missing final leaf.
    $current = [IO.Path]::GetPathRoot($candidate)
    $parts = @($candidate.Substring($current.Length).Split([char[]]@([char]92,[char]47),[StringSplitOptions]::RemoveEmptyEntries))
    for ($index = -1; $index -lt $parts.Count; $index++) {
        if($index-ge0){$current=[IO.Path]::Combine($current,$parts[$index])}
        try { $attributes=[IO.File]::GetAttributes($current) }
        catch [IO.FileNotFoundException],[IO.DirectoryNotFoundException] {
            if ($AllowMissing -and $index -eq ($parts.Count - 1)) { return $null }
            throw "${Label}_MISSING"
        }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "${Label}_REPARSE" }
        $directory=($attributes-band[IO.FileAttributes]::Directory)-ne0
        if ($index -lt ($parts.Count - 1) -and -not $directory) { throw "${Label}_MISSING" }
        if ($index -eq ($parts.Count - 1) -and $directory) { throw "${Label}_MISSING" }
    }
    return $candidate
}

function Assert-AiwProjectStandardReadAllowed {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$CandidatePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ForbiddenPaths,
        [Parameter(Mandatory)][string]$Label
    )
    $project = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))
    $candidate = [IO.Path]::GetFullPath($CandidatePath)
    foreach ($forbiddenPath in @($ForbiddenPaths)) {
        if ([IO.Path]::IsPathFullyQualified([string]$forbiddenPath)) {
            $absolute = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$forbiddenPath))
            if ([string]::Equals($candidate,$absolute,[StringComparison]::OrdinalIgnoreCase) -or
                $candidate.StartsWith($absolute + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
                throw ($Label + '_FORBIDDEN')
            }
        }
    }
    $projectPrefix = $project + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($projectPrefix,[StringComparison]::OrdinalIgnoreCase)) { return }
    $relative = $candidate.Substring($projectPrefix.Length).Replace('\','/')
    foreach ($forbiddenPath in @($ForbiddenPaths)) {
        if ([IO.Path]::IsPathFullyQualified([string]$forbiddenPath)) { continue }
        $normalized = ConvertTo-AiwSafeRelativePath (([string]$forbiddenPath).TrimEnd('/')) 'FORBIDDEN_SOURCE_PREFIX'
        if ([string]::Equals($relative,$normalized,[StringComparison]::OrdinalIgnoreCase) -or $relative.StartsWith($normalized + '/',[StringComparison]::OrdinalIgnoreCase)) {
            throw ($Label + '_FORBIDDEN')
        }
    }
}

function Resolve-AiwProjectStandardFile {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Locator,
        [Parameter(Mandatory)][ValidateSet('PROJECT_RELATIVE','ABSOLUTE_FILE')][string]$LocatorKind,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ForbiddenPaths
    )
    if ($LocatorKind -ceq 'PROJECT_RELATIVE') {
        $relative = ConvertTo-AiwSafeRelativePath $Locator ($Label + '_LOCATOR')
        if ($relative.StartsWith('.ai-workspace/runtime/',[StringComparison]::OrdinalIgnoreCase)) { throw ($Label + '_PROTECTED') }
        $candidate = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetFullPath($ProjectRoot),$relative))
        Assert-AiwProjectStandardReadAllowed -ProjectRoot $ProjectRoot -CandidatePath $candidate -ForbiddenPaths $ForbiddenPaths -Label $Label
        return [pscustomobject]@{ Path=(Resolve-AiwChildFile $ProjectRoot $relative $Label); Locator=$relative; LocatorKind=$LocatorKind; ProjectionRelativePath=$relative }
    }

    if ([string]::IsNullOrWhiteSpace($Locator) -or $Locator -cne $Locator.Trim() -or
        -not [string]::Equals($Locator,$Locator.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal) -or
        [regex]::IsMatch($Locator,'[\x00-\x1F<>"|?*]') -or
        -not [IO.Path]::IsPathFullyQualified($Locator) -or $Locator -cnotmatch '^[A-Za-z]:[\\/]') { throw ($Label + '_PATH') }
    $full = [IO.Path]::GetFullPath($Locator)
    Assert-AiwProjectStandardReadAllowed -ProjectRoot $ProjectRoot -CandidatePath $full -ForbiddenPaths $ForbiddenPaths -Label $Label
    $pathRoot = [IO.Path]::GetPathRoot($full)
    $segments = @($full.Substring($pathRoot.Length) -split '[\\/]' | Where-Object { -not [string]::IsNullOrEmpty($_) })
    for ($index=0; $index -lt ($segments.Count-1); $index++) {
        if ([string]::Equals($segments[$index],'.ai-workspace',[StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($segments[$index+1],'runtime',[StringComparison]::OrdinalIgnoreCase)) { throw ($Label + '_PROTECTED') }
    }
    $current = $pathRoot
    for ($index=-1; $index -lt $segments.Count; $index++) {
        if($index-ge0){$current=[IO.Path]::Combine($current,$segments[$index])}
        try { $attributes=[IO.File]::GetAttributes($current) }
        catch [IO.FileNotFoundException],[IO.DirectoryNotFoundException] { throw ($Label + '_MISSING') }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ($Label + '_REPARSE') }
        $directory=($attributes-band[IO.FileAttributes]::Directory)-ne0
        if ($index -lt ($segments.Count-1) -and -not $directory) { throw ($Label + '_MISSING') }
        if ($index -eq ($segments.Count-1) -and $directory) { throw ($Label + '_MISSING') }
    }
    return [pscustomobject]@{ Path=$full; Locator=$full; LocatorKind=$LocatorKind; ProjectionRelativePath='NOT_APPLICABLE' }
}

function Assert-AiwCompositionPackageMember($Observation,[string]$Relative,[string]$Identity){
    if($null-eq$Observation){return}
    if(-not$Observation.DeclaredMembers.ContainsKey($Relative)-or$Observation.DeclaredMembers[$Relative]-cne$Identity){throw ('FRAMEWORK_CONSUMED_MEMBER_DRIFT|'+$Relative)}
}

function Get-AiwCompositionReleaseFacts {
    param([Parameter(Mandatory)][string]$VersionDirectory,[string]$ProjectRoot,[switch]$ProspectiveAdoptionProjection,[switch]$DailyProcessObservation)
    $reader=@(Import-Module (Join-Path $PSScriptRoot 'ReleaseValidation.psm1') -Function Get-AiwReleaseQualification -Scope Local -PassThru)[0]
    $runtime=[IO.Path]::GetFullPath((Join-Path $VersionDirectory '../../..'))
    if($ProjectRoot-and-not$ProspectiveAdoptionProjection){
        $path=Join-Path $runtime 'scripts/ProjectAdoptionState.psm1'
        if(Test-Path -LiteralPath $path){
            $path=Resolve-AiwChildFile $runtime 'scripts/ProjectAdoptionState.psm1' 'ADOPTION_STATE_MODULE'
            $adoption=@(Import-Module $path -PassThru -ErrorAction Stop)[0]
            if(-not$DailyProcessObservation){
                $complete=& $adoption.ExportedCommands['Get-AiwFixedAdoptedRelease'] -ProjectRoot $ProjectRoot -FrameworkRoot $runtime
                if($null-ne$complete){return [pscustomobject]@{Observation=$null;Facts=$complete.Facts}}
            }
            $fixed=if($DailyProcessObservation){& $adoption {
                param($project,$root)
                if($null-ne(Get-Command Get-AiwFixedAdoptedProcessSource -ErrorAction SilentlyContinue)){
                    return Get-AiwFixedAdoptedProcessSource -ProjectRoot $project -FrameworkRoot $root
                }
                return $null
            } $ProjectRoot $runtime}else{$null}
            if($null-ne$fixed){return [pscustomobject]@{Observation=$fixed;Facts=$null}}
        }
    }
    $qualified=& $reader.ExportedCommands['Get-AiwReleaseQualification'] -VersionRoot $VersionDirectory -RuntimeRoot $runtime -AllowPending
    return [pscustomobject]@{Observation=$null;Facts=$qualified.Facts}
}

function Assert-AiwSealedRelease {
    param([Parameter(Mandatory)][string]$VersionDirectory,[Parameter(Mandatory)][string]$Version,[string]$ProjectRoot,$ReleaseObservation=$null)
    $manifestDoc=Read-AiwStrictJson (Join-Path $VersionDirectory 'RELEASE_MANIFEST.json') 'RELEASE_MANIFEST'
    $manifest=$manifestDoc.Value
    if([string]$manifest.version-cne$Version-or[string]$manifest.lifecycle-cne'STABLE'-or[string]$manifest.sourceReview-cne'APPROVED'-or[string]$manifest.canonical-cnotmatch'^[A-F0-9]{64}$'){throw 'FRAMEWORK_RELEASE_NOT_SEALED'}
    $release=if($null-ne$ReleaseObservation){$ReleaseObservation}else{Get-AiwCompositionReleaseFacts -VersionDirectory $VersionDirectory -ProjectRoot $ProjectRoot}
    if($null-ne$release.Observation){
        if($release.Observation.ManifestIdentity-cne$manifestDoc.Identity){throw 'FRAMEWORK_RELEASE_MANIFEST_DRIFT'}
        return
    }
    $facts=$release.Facts
    if([int64]$manifest.fileCount-ne$facts.FileCount-or[int64]$manifest.totalBytes-ne$facts.TotalBytes-or[string]$manifest.canonical-cne$facts.Canonical){throw 'FRAMEWORK_RELEASE_MANIFEST_DRIFT'}
}

function Get-AiwAgentsManagedBlockIdentity {
    param([Parameter(Mandatory)][string]$AgentsPath)
    $bytes=[IO.File]::ReadAllBytes($AgentsPath)
    try{$text=$script:Utf8Strict.GetString($bytes)}catch{throw 'AGENTS_UTF8'}
    if($text.Contains([char]0)-or$text.Contains([char]0xFFFD)){throw 'AGENTS_TEXT_FORMAT'}
    $begin='<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->';$end='<!-- AI-WORKSPACE-FRAMEWORK:END -->'
    $start=$text.IndexOf($begin,[StringComparison]::Ordinal);$finish=$text.IndexOf($end,[StringComparison]::Ordinal)
    if($start-lt0-or$finish-le$start-or$text.IndexOf($begin,$start+1,[StringComparison]::Ordinal)-ge0-or$text.IndexOf($end,$finish+1,[StringComparison]::Ordinal)-ge0){throw 'AGENTS_MANAGED_MARKERS'}
    $managedBytes=$script:Utf8Strict.GetBytes($text.Substring($start,$finish+$end.Length-$start))
    return $managedBytes.Length.ToString()+'|'+(Get-AiwSha256Hex $managedBytes)
}

function Get-AiwLocalCandidatePilotBinding {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$VersionDirectory,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)]$VersionObject,
        [Parameter(Mandatory)]$ManifestDoc,
        [switch]$ProspectiveAdoptionProjection,
        $ReleaseObservation=$null
    )
    if([string]$VersionObject.lifecycle-cne'CANDIDATE'-or[bool]$VersionObject.consumable-or[bool]$VersionObject.projectPinEligible){throw 'FRAMEWORK_LOCAL_CANDIDATE_STATE_REQUIRED'}
    $profileDoc=Read-AiwStrictJson (Resolve-AiwChildFile $VersionDirectory 'ADOPTION_PROFILE.json' 'ADOPTION_PROFILE') 'ADOPTION_PROFILE'
    if([string]$profileDoc.Value.frameworkVersion-cne$Version-or-not($profileDoc.Value.localCandidatePilotEligible-is[bool])-or-not[bool]$profileDoc.Value.localCandidatePilotEligible){throw 'FRAMEWORK_LOCAL_CANDIDATE_PROFILE_REQUIRED'}
    $manifest=$ManifestDoc.Value
    if([string]$manifest.version-cne$Version-or[string]$manifest.lifecycle-cne'CANDIDATE'-or[string]$manifest.sourceReview-cne'APPROVED'-or[string]$manifest.canonical-cnotmatch'^[A-F0-9]{64}$'){throw 'FRAMEWORK_LOCAL_CANDIDATE_MANIFEST_STATE'}
    $release=if($null-ne$ReleaseObservation){$ReleaseObservation}else{Get-AiwCompositionReleaseFacts -VersionDirectory $VersionDirectory -ProjectRoot $ProjectRoot -ProspectiveAdoptionProjection:$ProspectiveAdoptionProjection}
    if($null-ne$release.Observation){
        $fixed=$release.Observation
        if($fixed.ManifestIdentity-cne$ManifestDoc.Identity-or$fixed.AdoptionStateIdentity-ceq'MISSING'){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
        $currentConfig=Read-AiwStrictJson (Resolve-AiwChildFile $ProjectRoot '.ai-workspace/project.json' 'LOCAL_CANDIDATE_PROJECT') 'LOCAL_CANDIDATE_PROJECT'
        $currentBootstrap=Get-AiwProjectCustomRegion (Resolve-AiwChildFile $ProjectRoot '.ai-workspace/BOOTSTRAP.md' 'LOCAL_CANDIDATE_BOOTSTRAP')
        Assert-AiwBootstrapCurrentBinding $currentBootstrap.ManagedText $ProjectId $Version ([string]$currentConfig.Value.controlPlaneLayout)
        return [pscustomobject]@{Identity=$fixed.AdoptionStateIdentity;Canonical=$fixed.DeclaredPayloadCanonical;SchemaVersion=$fixed.AdoptionStateSchemaVersion;TransactionComplete=$true;ProjectionMode='LOCAL_CANDIDATE_MANAGED'}
    }
    $facts=$release.Facts
    if([int64]$manifest.fileCount-ne$facts.FileCount-or[int64]$manifest.totalBytes-ne$facts.TotalBytes-or[string]$manifest.canonical-cne$facts.Canonical){throw 'FRAMEWORK_LOCAL_CANDIDATE_MANIFEST_DRIFT'}
    $statePath=Resolve-AiwChildFile $ProjectRoot ('.ai-workspace/upgrade-recovery/'+$Version+'/state.json') 'LOCAL_CANDIDATE_PILOT_STATE'
    $stateDoc=Read-AiwStrictJson $statePath 'LOCAL_CANDIDATE_PILOT_STATE';$state=$stateDoc.Value
    if($state.schemaVersion-eq7){
        $runtimeRoot=[IO.Path]::GetFullPath((Join-Path $VersionDirectory '../../..'))
        Import-Module (Join-Path $runtimeRoot 'scripts/ProjectAdoptionState.psm1') -ErrorAction Stop
        $registered=Assert-AiwRegistrationOrigin $ProjectRoot $Version $runtimeRoot
        if($registered.State.projectId-cne$ProjectId-or$registered.Canonical-cne$facts.Canonical-or
           $registered.State.targetReleaseManifestIdentity-cne$ManifestDoc.Identity){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
        $currentConfig=Read-AiwStrictJson (Resolve-AiwChildFile $ProjectRoot '.ai-workspace/project.json' 'LOCAL_CANDIDATE_PROJECT') 'LOCAL_CANDIDATE_PROJECT'
        $currentBootstrap=Get-AiwProjectCustomRegion (Resolve-AiwChildFile $ProjectRoot '.ai-workspace/BOOTSTRAP.md' 'LOCAL_CANDIDATE_BOOTSTRAP')
        Assert-AiwBootstrapCurrentBinding $currentBootstrap.ManagedText $ProjectId $Version ([string]$currentConfig.Value.controlPlaneLayout)
        return [pscustomobject]@{Identity=$stateDoc.Identity;Canonical=$facts.Canonical;SchemaVersion=7;TransactionComplete=$true;ProjectionMode='LOCAL_CANDIDATE_MANAGED'}
    }
    if(-not(Test-AiwJsonInteger $state.schemaVersion)-or[int]$state.schemaVersion-notin@(2,3,4,5,6)){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
    $stateFields=@('schemaVersion','projectId','fromVersion','toVersion','targetReleaseCanonical','targetReleaseManifestIdentity','actor','taskId','taskOwner','taskRelative','authorizationIdentity','objects')
    if([int]$state.schemaVersion-in@(3,4,5,6)){$stateFields+=@('projectionMode','projectionObjects')}
    if([int]$state.schemaVersion-in@(4,5,6)){$stateFields+='transactionComplete'}
    if([int]$state.schemaVersion-in@(5,6)){$stateFields+=@('projectFormat','projectCapabilities','rootToolRevision','rootToolDependencies')}
    if([int]$state.schemaVersion-eq6){$stateFields+='distributionBinding'}
    $major=$null-ne$state.PSObject.Properties['majorTransition']
    if($major){$stateFields+='majorTransition'}
    Assert-AiwExactFields $state $stateFields 'LOCAL_CANDIDATE_PILOT_STATE'
    if([int]$state.schemaVersion-eq6){
        $runtimeRoot=[IO.Path]::GetFullPath((Join-Path $VersionDirectory '../../..'))
        $runtimeModule=Join-Path $runtimeRoot 'scripts/ProjectAdoptionState.psm1'
        Import-Module $runtimeModule -ErrorAction Stop
    }
    if($major){
        Assert-AiwExactFields $state.majorTransition @('fromVersion','fromDistributionId','toVersion','transactionRelativePath') 'LOCAL_CANDIDATE_MAJOR_TRANSITION'
        if($Version-cne'2.0.0'-or$state.schemaVersion-ne6-or$state.fromVersion-cne$state.majorTransition.fromVersion-or
           $state.majorTransition.fromVersion-cnotin@('1.16.0','2.0.0')-or$state.majorTransition.toVersion-cne$Version-or
           $state.majorTransition.transactionRelativePath-cnotin@('.ai-workspace/runtime/project-adoption/upgrade/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')){throw 'LOCAL_CANDIDATE_MAJOR_TRANSITION_PAIR'}
        if(-not$ProspectiveAdoptionProjection){
            $transaction=Read-AiwStrictJson (Resolve-AiwChildFile $ProjectRoot $state.majorTransition.transactionRelativePath 'LOCAL_CANDIDATE_MAJOR_TRANSACTION') 'LOCAL_CANDIDATE_MAJOR_TRANSACTION'
            $t=$transaction.Value
            if($t.schemaVersion-ne1-or$t.state-cne'COMPLETE'-or$t.transactionComplete-ne$true-or$t.metadata.operation-cnotin@('UPGRADE_SNAPSHOT12_TO_2','UPGRADE_FORMAT_TRANSITION')-or
               [IO.Path]::GetFullPath($t.repositoryRoot)-cne[IO.Path]::GetFullPath($ProjectRoot)){throw 'LOCAL_CANDIDATE_MAJOR_TRANSACTION_INCOMPLETE'}
            Assert-AiwMajorRecoveryOrigin $state $t
            if($t.metadata.operation-ceq'UPGRADE_FORMAT_TRANSITION'){
                Assert-AiwOriginalFormatFinalize $t
            }elseif($state.majorTransition.fromVersion-cne'1.16.0'-or$state.majorTransition.fromDistributionId-cne'1.16.0-snapshot.12'){
                throw 'LOCAL_CANDIDATE_MAJOR_TRANSITION_PAIR'
            }
        }
    }
    if([int]$state.schemaVersion-eq6){
        $null=Assert-AiwDistributionBinding $state.distributionBinding $runtimeRoot $Version
    }
    if([int]$state.schemaVersion-in@(4,5,6)){
        if(-not($state.transactionComplete-is[bool])){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
        if(-not[bool]$state.transactionComplete){throw 'LOCAL_CANDIDATE_PILOT_TRANSACTION_INCOMPLETE'}
    }
    if([int]$state.schemaVersion-in@(5,6)){
        if([string]$state.projectFormat-cnotmatch'^repo-local/project-config-[1-9][0-9]*$'-or-not($state.projectCapabilities-is[Array])-or[string]$state.rootToolRevision-cnotmatch'^[A-F0-9]{64}$'-or-not($state.rootToolDependencies-is[Array])){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
    }
    if([string]$state.projectId-cne$ProjectId-or[string]$state.toVersion-cne$Version-or[string]$state.targetReleaseCanonical-cne$facts.Canonical-or[string]$state.targetReleaseManifestIdentity-cne$ManifestDoc.Identity-or[string]$state.authorizationIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not($state.objects-is[Array])){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
    $taskRelative=ConvertTo-AiwSafeRelativePath ([string]$state.taskRelative) 'LOCAL_CANDIDATE_PILOT_TASK'
    if(-not$taskRelative.StartsWith('.ai-workspace/tasks/',[StringComparison]::Ordinal)-or[string]::IsNullOrWhiteSpace([string]$state.actor)-or[string]::IsNullOrWhiteSpace([string]$state.taskId)-or[string]::IsNullOrWhiteSpace([string]$state.taskOwner)){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
    $objectRecords=New-Object 'System.Collections.Generic.List[object]';$objectSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in @($state.objects)){
        Assert-AiwExactFields $entry @('relative','oldIdentity','newIdentity') 'LOCAL_CANDIDATE_PILOT_OBJECT'
        $relative=ConvertTo-AiwSafeRelativePath ([string]$entry.relative) 'LOCAL_CANDIDATE_PILOT_OBJECT'
        if(-not$objectSeen.Add($relative)-or([string]$entry.oldIdentity-cne'MISSING'-and[string]$entry.oldIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')-or([string]$entry.newIdentity-cne'ABSENT'-and[string]$entry.newIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
        $objectRecords.Add([pscustomobject]@{relative=$relative;newIdentity=[string]$entry.newIdentity})
    }
    $projectRecord=@($objectRecords|Where-Object{[string]$_.relative-ceq'.ai-workspace/project.json'});$taskRecord=@($objectRecords|Where-Object{[string]$_.relative-ceq$taskRelative})
    if($projectRecord.Count-ne1-or[string]$projectRecord[0].newIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
    $unchangedFormatTask=$major-and$state.fromVersion-ceq$Version
    if($unchangedFormatTask){
        if($taskRecord.Count-ne0){throw 'LOCAL_CANDIDATE_UNCHANGED_TASK_WRITE_OBJECT'}
    }elseif($taskRecord.Count-ne1-or[string]$taskRecord[0].newIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$objectRecords[-1].relative-cne$taskRelative){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
    $projectionRecords=New-Object 'System.Collections.Generic.List[object]'
    if([int]$state.schemaVersion-eq2){
        foreach($entry in $objectRecords){$projectionRecords.Add([pscustomobject]@{relative=[string]$entry.relative;identity=$(if([string]$entry.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$entry.newIdentity})})}
    }else{
        if([string]$state.projectionMode-cne'LOCAL_CANDIDATE_MANAGED'-or-not($state.projectionObjects-is[Array])){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
        $projectionSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($entry in @($state.projectionObjects)){
            $relative=ConvertTo-AiwSafeRelativePath ([string]$entry.relative) 'LOCAL_CANDIDATE_PILOT_PROJECTION_OBJECT'
            $entryFields=@('relative','identity')
            if([int]$state.schemaVersion-in@(4,5,6)-and$relative-ceq'.ai-workspace/BOOTSTRAP.md'){$entryFields+='managedIdentity'}
            if([int]$state.schemaVersion-in@(4,5,6)-and$relative-ceq'AGENTS.md'-and$null-ne$entry.PSObject.Properties['managedIdentity']){$entryFields+='managedIdentity'}
            Assert-AiwExactFields $entry $entryFields 'LOCAL_CANDIDATE_PILOT_PROJECTION_OBJECT'
            if(-not$projectionSeen.Add($relative)-or([string]$entry.identity-cne'MISSING'-and[string]$entry.identity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
            $projection=[ordered]@{relative=$relative;identity=[string]$entry.identity}
            if($entryFields-ccontains'managedIdentity'){
                if([string]$entry.managedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
                $projection.managedIdentity=[string]$entry.managedIdentity
            }
            $projectionRecords.Add([pscustomobject]$projection)
        }
        if([int]$state.schemaVersion-in@(4,5,6)-and-not$projectionSeen.Contains('.ai-workspace/BOOTSTRAP.md')){throw 'LOCAL_CANDIDATE_PILOT_BOOTSTRAP_BINDING_REQUIRED'}
        foreach($relative in $objectSeen){if(-not$projectionSeen.Contains($relative)){throw ('LOCAL_CANDIDATE_PILOT_PROJECTION_OBJECT_MISSING|'+$relative)}}
        $projectProjection=@($projectionRecords|Where-Object{[string]$_.relative-ceq'.ai-workspace/project.json'});$taskProjection=@($projectionRecords|Where-Object{[string]$_.relative-ceq$taskRelative})
        if($projectProjection.Count-ne1-or$taskProjection.Count-ne1-or[string]$projectProjection[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$taskProjection[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$projectionRecords[-1].relative-cne$taskRelative){throw 'LOCAL_CANDIDATE_PILOT_BINDING_DRIFT'}
        if($unchangedFormatTask){
            $historicalFinalized=$false
            if($ProspectiveAdoptionProjection){
                $originalJournal=Join-Path $ProjectRoot $state.majorTransition.transactionRelativePath
                if(Test-Path -LiteralPath $originalJournal -PathType Leaf){
                    $saved=Read-AiwStrictJson $originalJournal 'LOCAL_CANDIDATE_MAJOR_TRANSACTION'
                    if($null-ne$saved.Value.metadata.PSObject.Properties['originalFinalize']){
                        $t=$saved.Value
                        if($t.state-cne'COMPLETE'-or$t.transactionComplete-ne$true){throw 'LOCAL_CANDIDATE_MAJOR_TRANSACTION_INCOMPLETE'}
                        Assert-AiwMajorRecoveryOrigin $state $t
                        Assert-AiwOriginalFormatFinalize $t
                        $historicalFinalized=$true
                    }
                }
            }else{$historicalFinalized=$true}
            if(-not$historicalFinalized){
                # The private pre/postcheck runs on the verified projection;
                # the unchanged task is copied as an original read binding.
                $taskFile=Resolve-AiwChildFile $ProjectRoot $taskRelative 'LOCAL_CANDIDATE_UNCHANGED_TASK'
                if((Get-AiwFileIdentity $taskFile)-cne$taskProjection[0].identity){throw 'LOCAL_CANDIDATE_UNCHANGED_TASK_BINDING'}
            }else{
                # Completed adoption was already checked against its original
                # FINALIZE above. Later task edits/archival do not rewrite that
                # historical binding or force today's bytes to equal it.
                $original=$script:Utf8Strict.GetString([Convert]::FromBase64String($t.metadata.originalFinalize.discoverBase64))|ConvertFrom-Json -Depth 100
                $binding=if($original.schemaVersion-eq1){$original}else{$original.binding}
                if($original.schemaVersion-notin@(1,2,3)-or$original.sourceLocators.taskRelativePath-cne$taskRelative-or
                   $binding.taskId-cne$state.taskId-or$binding.taskOwner-cne$state.taskOwner-or$binding.actor-cne$state.actor-or
                   $binding.taskIdentity-cne$taskProjection[0].identity){throw 'LOCAL_CANDIDATE_UNCHANGED_TASK_BINDING'}
            }
        }
    }
    foreach($entry in @($projectionRecords|Where-Object{[string]$_.relative-cne$taskRelative})){
        $relative=[string]$entry.relative;$expected=[string]$entry.identity;$full=[IO.Path]::GetFullPath((Join-Path $ProjectRoot $relative))
        if([int]$state.schemaVersion-in@(4,5,6)-and$relative-in@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json')){
            $resolved=Resolve-AiwChildFile $ProjectRoot $relative 'LOCAL_CANDIDATE_PILOT_PROJECTION'
            if($relative-ceq'.ai-workspace/BOOTSTRAP.md'){$null=Get-AiwProjectCustomRegion $resolved}
            # 项目规则由当前 composer 严格校验并绑定当前身份，不被历史安装快照永久冻结。
            continue
        }
        if($relative-ceq'AGENTS.md'){
            $resolved=Resolve-AiwChildFile $ProjectRoot $relative 'LOCAL_CANDIDATE_PILOT_PROJECTION'
            # Installation records retain the installed image; current user decisions
            # are bound independently by projectAgentsIdentity on every discovery.
            $null=Get-AiwAgentsManagedBlockIdentity $resolved
            continue
        }
        # Remaining projection entries are historical install evidence. Their
        # current bytes are project-owned and are checked by their actual
        # consumer, not by every ordinary Framework load.
    }
    $currentConfig=Read-AiwStrictJson (Resolve-AiwChildFile $ProjectRoot '.ai-workspace/project.json' 'LOCAL_CANDIDATE_PROJECT') 'LOCAL_CANDIDATE_PROJECT'
    if([string]$currentConfig.Value.id-cne$ProjectId-or[string]$currentConfig.Value.frameworkVersion-cne$Version){throw 'LOCAL_CANDIDATE_PROJECT_BINDING_DRIFT'}
    $currentBootstrap=Get-AiwProjectCustomRegion (Resolve-AiwChildFile $ProjectRoot '.ai-workspace/BOOTSTRAP.md' 'LOCAL_CANDIDATE_BOOTSTRAP')
    Assert-AiwBootstrapCurrentBinding $currentBootstrap.ManagedText $ProjectId $Version ([string]$currentConfig.Value.controlPlaneLayout)
    return [pscustomobject]@{
        Identity=$stateDoc.Identity
        Canonical=$facts.Canonical
        SchemaVersion=[int]$state.schemaVersion
        TransactionComplete=$(if([int]$state.schemaVersion-in@(4,5,6)){[bool]$state.transactionComplete}else{$false})
        ProjectionMode=$(if([int]$state.schemaVersion-in@(3,4,5,6)){[string]$state.projectionMode}else{'LEGACY'})
    }
}

function Get-AiwLocalCandidateSupportBinding {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
        [Parameter(Mandatory)][string]$ExpectedCandidatePilotStateIdentity,
        [Parameter(Mandatory)][string]$VersionDirectory,
        [Parameter(Mandatory)][string]$Version,
        [switch]$ProspectiveAdoptionProjection
    )
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $ProjectRoot -Mode OBSERVE
try {


    if($ExpectedCandidatePilotStateIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'LOCAL_CANDIDATE_PILOT_STATE_IDENTITY_INVALID'}
    $project=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
    $configDoc=Read-AiwStrictJson (Resolve-AiwChildFile $project '.ai-workspace/project.json' 'PROJECT_CONFIG') 'PROJECT_CONFIG'
    if($configDoc.Identity-cne$ExpectedProjectConfigIdentity){throw 'PROJECT_CONFIG_DRIFT'}
    $config=$configDoc.Value
    if(-not($config.id-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.id)-or[string]$config.frameworkVersion-cne$Version-or[string]$config.frameworkToolBackend-cne'powershell7'){throw 'LOCAL_CANDIDATE_PROJECT_BINDING_DRIFT'}
    $versionDoc=Read-AiwStrictJson (Resolve-AiwChildFile $VersionDirectory 'VERSION.json' 'FRAMEWORK_VERSION') 'FRAMEWORK_VERSION'
    if([string]$versionDoc.Value.version-cne$Version){throw 'FRAMEWORK_VERSION_MISMATCH'}
    $manifestDoc=Read-AiwStrictJson (Resolve-AiwChildFile $VersionDirectory 'RELEASE_MANIFEST.json' 'RELEASE_MANIFEST') 'RELEASE_MANIFEST'
    $binding=Get-AiwLocalCandidatePilotBinding -ProjectRoot $project -ProjectId ([string]$config.id) -VersionDirectory $VersionDirectory -Version $Version -VersionObject $versionDoc.Value -ManifestDoc $manifestDoc -ProspectiveAdoptionProjection:$ProspectiveAdoptionProjection
    if([string]$binding.Identity-cne$ExpectedCandidatePilotStateIdentity){throw 'LOCAL_CANDIDATE_PILOT_STATE_DRIFT'}
    if([int]$binding.SchemaVersion-notin@(4,5,6,7)-or-not[bool]$binding.TransactionComplete-or[string]$binding.ProjectionMode-cne'LOCAL_CANDIDATE_MANAGED'){throw 'LOCAL_CANDIDATE_SUPPORT_COMPLETION_REQUIRED'}
    return [pscustomobject]@{
        lifecycle='CANDIDATE'
        evidenceCeiling='LOCAL_CANDIDATE_PILOT'
        candidatePilotStateIdentity=[string]$binding.Identity
        canonical=[string]$binding.Canonical
        manifestIdentity=[string]$manifestDoc.Identity
    }

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}

function Get-AiwCanonicalCorrectionRecordIdentityV1 {
    param([Parameter(Mandatory)]$Record)
    $fields = @('correctionId','introducedAgainstFramework','requirementReason','effectiveRule','applicability','decisionLocator')
    Assert-AiwExactFields $Record $fields 'CORRECTION_RECORD'
    $buffer = [Collections.Generic.List[byte]]::new()
    $prefix = $script:Utf8Strict.GetBytes("AIW-CORRECTION-RECORD-V1`n")
    $buffer.AddRange($prefix)
    foreach ($field in $fields) {
        $value = $Record.$field
        if (-not ($value -is [string])) { throw "CORRECTION_RECORD_STRING|$field" }
        $fieldBytes = $script:Utf8Strict.GetBytes($field)
        $valueBytes = $script:Utf8Strict.GetBytes([string]$value)
        $buffer.AddRange($script:Utf8Strict.GetBytes($fieldBytes.Length.ToString() + ':'))
        $buffer.AddRange($fieldBytes)
        $buffer.AddRange($script:Utf8Strict.GetBytes($valueBytes.Length.ToString() + ':'))
        $buffer.AddRange($valueBytes)
    }
    $bytes = $buffer.ToArray()
    return $bytes.Length.ToString() + '|' + (Get-AiwSha256Hex $bytes)
}

function Get-AiwCanonicalCorrectionRecordIdentityV2 {
    param([Parameter(Mandatory)]$Record)
    $fields = @('correctionId','introducedAgainstFramework','requirementReason','effectiveRule','applicability','decisionLocator','selectors','preparationRequirements','resultRequirements','requiredFacts','mechanicalCheckRefs')
    if($null-ne$Record.PSObject.Properties['history']){
        $fields+='history'
        Assert-AiwExactFields $Record.history @('locator','identity') 'CORRECTION_HISTORY'
        $history=ConvertTo-AiwSafeRelativePath $Record.history.locator 'CORRECTION_HISTORY'
        if(-not$history.StartsWith('.ai-workspace/upgrade-recovery/corrections/'+$Record.correctionId+'/',[StringComparison]::Ordinal)-or
           -not$history.EndsWith('/history.json',[StringComparison]::Ordinal)-or$Record.history.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'CORRECTION_HISTORY_VALUES'}
    }
    if($null-ne$Record.PSObject.Properties['lifecycle']){
        $fields+='lifecycle'
        Assert-AiwExactFields $Record.lifecycle @('state','installation','decisionLocator') 'CORRECTION_LIFECYCLE'
        if($Record.lifecycle.state-cnotin@('ACTIVE','PAUSED','UNINSTALLED')-or
           [string]::IsNullOrWhiteSpace($Record.lifecycle.decisionLocator)){throw 'CORRECTION_LIFECYCLE_VALUES'}
        if($Record.lifecycle.installation-isnot[string]-or$Record.lifecycle.installation-cne'NOT_APPLICABLE'){
            Assert-AiwExactFields $Record.lifecycle.installation @('locator','identity') 'CORRECTION_INSTALLATION'
            if($Record.lifecycle.installation.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'CORRECTION_LIFECYCLE_VALUES'}
            $locator=ConvertTo-AiwSafeRelativePath $Record.lifecycle.installation.locator 'CORRECTION_INSTALLATION'
            if(-not$locator.StartsWith('.ai-workspace/upgrade-recovery/corrections/',[StringComparison]::Ordinal)){throw 'CORRECTION_INSTALLATION_LOCATOR'}
        }
    }
    Assert-AiwExactFields $Record $fields 'CORRECTION_RECORD_V2'
    $ordered = [ordered]@{}
    foreach ($field in $fields) { $ordered[$field] = $Record.$field }
    $json = ($ordered | ConvertTo-Json -Depth 50 -Compress).Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = $script:Utf8Strict.GetBytes("AIW-CORRECTION-RECORD-V2`n" + $json)
    return $bytes.Length.ToString() + '|' + (Get-AiwSha256Hex $bytes)
}

function Get-AiwProjectCustomRegion {
    param([Parameter(Mandatory)][string]$BootstrapPath)
    $bytes = [IO.File]::ReadAllBytes($BootstrapPath)
    try{$text = $script:Utf8Strict.GetString($bytes)}catch{throw 'BOOTSTRAP_UTF8'}
    if($text.Contains([char]0)-or$text.Contains([char]0xFFFD)){throw 'BOOTSTRAP_TEXT_FORMAT'}
    $begin = '<!-- PROJECT-CUSTOM:BEGIN -->'
    $end = '<!-- PROJECT-CUSTOM:END -->'
    $start = $text.IndexOf($begin,[StringComparison]::Ordinal)
    $finish = $text.IndexOf($end,[StringComparison]::Ordinal)
    if ($start -lt 0 -or $finish -le $start -or $text.IndexOf($begin,$start + 1,[StringComparison]::Ordinal) -ge 0 -or $text.IndexOf($end,$finish + 1,[StringComparison]::Ordinal) -ge 0) { throw 'PROJECT_CUSTOM_MARKERS' }
    $bodyStart = $start + $begin.Length
    $body = $text.Substring($bodyStart,$finish - $bodyStart)
    $bodyBytes = $script:Utf8Strict.GetBytes($body)
    $identity = $bodyBytes.Length.ToString() + '|' + (Get-AiwSha256Hex $bodyBytes)
    $trimmed = $body.Trim()
    $defaultOnly = [string]::IsNullOrWhiteSpace($trimmed) -or
        $trimmed -ceq 'No permanent project process rule is active in this legacy region. Structured rules belong to `.ai-workspace/process-policy.json`.' -or
        $trimmed -ceq 'Project-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.' -or
        $trimmed -ceq '此 legacy region 当前没有 permanent project process rule。structured rules 位于 `.ai-workspace/process-policy.json`。'
    $managedBytes=$script:Utf8Strict.GetBytes($text.Substring(0,$bodyStart)+$text.Substring($finish))
    $managedIdentity=$managedBytes.Length.ToString()+'|'+(Get-AiwSha256Hex $managedBytes)
    return [pscustomobject]@{ Identity=$identity; Text=$body; HasNormativeContent=(-not $defaultOnly); ManagedIdentity=$managedIdentity; ManagedText=$script:Utf8Strict.GetString($managedBytes) }
}

function Assert-AiwBootstrapCurrentBinding([string]$ManagedText,[string]$ProjectId,[string]$Version,[string]$Layout) {
    $begin='<!-- FRAMEWORK-MANAGED:BEGIN -->';$end='<!-- FRAMEWORK-MANAGED:END -->'
    $start=$ManagedText.IndexOf($begin,[StringComparison]::Ordinal);$finish=$ManagedText.IndexOf($end,[StringComparison]::Ordinal);$customStart=$ManagedText.IndexOf('<!-- PROJECT-CUSTOM:BEGIN -->',[StringComparison]::Ordinal)
    if([regex]::Matches($ManagedText,[regex]::Escape($begin)).Count-ne1-or[regex]::Matches($ManagedText,[regex]::Escape($end)).Count-ne1-or$start-ge$finish-or$finish-ge$customStart){throw 'LOCAL_CANDIDATE_BOOTSTRAP_MARKERS'}
    $prefix=if($Layout-ceq'framework-maintenance-sibling'){'Project ID=`'+$ProjectId+'`；layout=`framework-maintenance-sibling`；control plane=`.ai-workspace/`；pinned Framework=`'+$Version+'`。'}else{'Project ID=`'+$ProjectId+'`；repo-local control plane=`.ai-workspace/`；pinned Framework=`'+$Version+'`。'}
    $managedBlock=$ManagedText.Substring($start,$finish+$end.Length-$start)
    $bindingLines=@($managedBlock -split '\r?\n'|Where-Object{$_.StartsWith('Project ID=`',[StringComparison]::Ordinal)})
    if($bindingLines.Count-ne1-or-not([string]$bindingLines[0]).StartsWith($prefix,[StringComparison]::Ordinal)){throw 'LOCAL_CANDIDATE_BOOTSTRAP_CURRENT_BINDING'}
}

function Get-AiwProjectAgentsIdentity {
    param([string]$ProjectRoot, [AllowEmptyCollection()][string[]]$ForbiddenPaths=@())
    # User decisions stay separate from Bootstrap custom and project standards.
    Assert-AiwProjectStandardReadAllowed -ProjectRoot $ProjectRoot -CandidatePath (Join-Path $ProjectRoot 'AGENTS.md') -ForbiddenPaths $ForbiddenPaths -Label 'PROJECT_AGENTS'
    $agents = Resolve-AiwChildFile $ProjectRoot 'AGENTS.md' 'PROJECT_AGENTS' -AllowMissing
    if ($null -eq $agents) { return 'MISSING' }
    return Get-AiwFileIdentity $agents
}

function Get-AiwProcessImplementationIdentity {
    param([Parameter(Mandatory)][string]$FrameworkRoot,[Parameter(Mandatory)][string]$TargetVersion,$PackageObservation=$null)
    $versionDirectory=Join-Path $FrameworkRoot ('framework/versions/'+$TargetVersion)
    $paths=@('scripts/ProcessRequirementComposition.psm1','scripts/ExecutionTargetContext.psm1','EXECUTION_TARGET_SCHEMA.json','AUTHORITY_CONTEXT_SCHEMA.json','scripts/ContentSources.psm1','scripts/KnowledgeSources.psm1','scripts/ObjectFormats.psm1','scripts/StrictJsonInput.psm1','scripts/resolve-process-requirements.ps1','scripts/ProcessRequirementDisplay.psm1','scripts/check-authorization.ps1','scripts/ControlTransition.psm1','scripts/ResultEvidence.psm1','scripts/WorkflowDelivery.psm1','scripts/ProjectSourcePublication.psm1','scripts/AuthorizationCheck.psm1','scripts/ProcessRequirementBoundary.psm1','INTENT_ENVELOPE_SCHEMA.json','PROCESS_POLICY_SCHEMA.json','PROJECT_CORRECTIONS_SCHEMA.json','TOOLCHAIN.json','object-formats/ASSEMBLY.json')
    $assembly=Read-AiwStrictJson (Resolve-AiwChildFile $versionDirectory 'object-formats/ASSEMBLY.json' 'PROCESS_IMPLEMENTATION') 'PROCESS_IMPLEMENTATION'
    foreach($type in $assembly.Value.objectTypes){foreach($adapter in $type.adapters){$paths+=('object-formats/'+[string]$adapter.implementationLocator)}}
    $paths=@($paths|Select-Object -Unique)
    $rows=@(foreach($relative in $paths){$path=Resolve-AiwChildFile $versionDirectory $relative 'PROCESS_IMPLEMENTATION';$identity=Get-AiwFileIdentity $path;Assert-AiwCompositionPackageMember $PackageObservation ('framework/versions/'+$TargetVersion+'/'+$relative) $identity;[ordered]@{path=$relative;identity=$identity}})
    return Get-AiwContentDescriptorIdentity $rows
}

function Get-AiwProcessBindingSnapshot {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][string]$TargetVersion,
        [Parameter(Mandatory)][string]$TaskRelativePath,
        [AllowEmptyCollection()][string[]]$ForbiddenPaths=@(),
        [switch]$ProspectiveAdoptionProjection,
        $SelectionContext=$null,
        $RuleObservation=$null,
        [switch]$RequireNoBody
    )
    if($null-ne$SelectionContext){
        Assert-AiwExactFields $SelectionContext @('profile','role','phase','actor','actionKind','resultKind','exactPaths','capabilities','intentEnvelope') 'SELECTION_CONTEXT'
        if($SelectionContext.intentEnvelope.requestedActionKind-cne$SelectionContext.actionKind-or$SelectionContext.intentEnvelope.requestedResultKind-cne$SelectionContext.resultKind){throw 'SELECTION_CONTEXT_INTENT_MISMATCH'}
        $currentTask='NOT_APPLICABLE'
        if($TaskRelativePath-cne'NOT_APPLICABLE'){
            $relative=ConvertTo-AiwSafeRelativePath $TaskRelativePath 'TASK_LOCATOR'
            if(-not$relative.StartsWith('.ai-workspace/tasks/',[StringComparison]::Ordinal)){throw 'TASK_LOCATOR_SCOPE'}
            Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
            $currentTask=(Read-AiwControlTransitionTask $ProjectRoot $relative).Identity
        }
        $configuration=Get-AiwFileIdentity (Join-Path $ProjectRoot '.ai-workspace/project.json')
        $correctionFile=Join-Path $ProjectRoot '.ai-workspace/corrections.json'
        $correctionIdentity=if([IO.File]::Exists($correctionFile)){Get-AiwFileIdentity $correctionFile}else{'MISSING'}
        $declaredIntent=if($SelectionContext.intentEnvelope.schemaVersion-eq2){$SelectionContext.intentEnvelope}else{$null}
        $arguments=@{ProjectRoot=$ProjectRoot;FrameworkRoot=$FrameworkRoot;TargetVersion=$TargetVersion;ExpectedProjectConfigIdentity=$configuration;ExpectedCorrectionsIdentity=$correctionIdentity;Profile=$SelectionContext.profile;Role=$SelectionContext.role;Phase=$SelectionContext.phase;Actor=$SelectionContext.actor;TaskIdentity=$currentTask;Capabilities=@($SelectionContext.capabilities);Objective=(Get-AiwProcessSemanticText $SelectionContext.intentEnvelope);ActionKind=$SelectionContext.actionKind;ResultKind=$SelectionContext.resultKind;ExactPaths=@($SelectionContext.exactPaths);ForbiddenPaths=$ForbiddenPaths;IntentEnvelope=$declaredIntent;EvaluationOnly=[bool]$ProspectiveAdoptionProjection;BindingSnapshotOnly=$true;RuleObservation=$RuleObservation}
        try{return Invoke-AiwProcessCompositionCore @arguments}catch{
            if($RequireNoBody-or$null-eq$RuleObservation-or$_.Exception.Message-cnotlike'RULE_LOAD_REQUIRED*'){throw}
            # Original completion/adoption may require a newly observed full
            # source. A scope-only admission explicitly forbids this fallback.
            $arguments.Remove('RuleObservation')
            return Invoke-AiwProcessCompositionCore @arguments
        }
    }
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $ProjectRoot -Mode OBSERVE
try {

    $project=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
    $framework=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FrameworkRoot)))
    $taskRelative=$TaskRelativePath;$taskPath=$null
    if($taskRelative-cne'NOT_APPLICABLE'){
        $taskRelative=ConvertTo-AiwSafeRelativePath $TaskRelativePath 'TASK_LOCATOR'
        if(-not $taskRelative.StartsWith('.ai-workspace/tasks/',[StringComparison]::Ordinal)){throw 'TASK_LOCATOR_SCOPE'}
        Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
        $taskDocument=Read-AiwControlTransitionTask $project $taskRelative
        $taskPath=$taskDocument.Path
    }
    $configPath=Resolve-AiwChildFile $project '.ai-workspace/project.json' 'PROJECT_CONFIG'
    $configDoc=Read-AiwStrictJson $configPath 'PROJECT_CONFIG';$config=$configDoc.Value
    $runtimeStateModule=Join-Path $framework 'scripts/ProjectAdoptionState.psm1'
    if(Test-Path -LiteralPath $runtimeStateModule -PathType Leaf){
        Import-Module $runtimeStateModule -ErrorAction Stop
        if($null-ne(Get-Command Get-AiwAdoptedDistributionBinding -ErrorAction SilentlyContinue)){
            $adopted=Get-AiwAdoptedDistributionBinding $project $TargetVersion
            if($null-ne$adopted){$stateOwner=@(Import-Module $runtimeStateModule -PassThru)[0];$null=& $stateOwner {param($p,$r,$v) Assert-AiwAdoptedRuntimeDeclaration $p $r $v} $project $framework $TargetVersion}
        }
    }
    $versionDirectory=Join-Path $framework ('framework/versions/'+$TargetVersion)
    $versionPath=Resolve-AiwChildFile $framework ('framework/versions/'+$TargetVersion+'/VERSION.json') 'FRAMEWORK_VERSION'
    $manifestPath=Resolve-AiwChildFile $framework ('framework/versions/'+$TargetVersion+'/RELEASE_MANIFEST.json') 'RELEASE_MANIFEST'
    $catalogPath=Resolve-AiwChildFile $framework ('framework/versions/'+$TargetVersion+'/PROCESS_REQUIREMENTS.json') 'PROCESS_REQUIREMENTS'
    $correctionsPath=Resolve-AiwChildFile $project '.ai-workspace/corrections.json' 'CORRECTIONS' -AllowMissing
    $controllerPath=Resolve-AiwChildFile $project '.ai-workspace/controller.json' 'CONTROLLER' -AllowMissing
    $bootstrapPath=Resolve-AiwChildFile $project '.ai-workspace/BOOTSTRAP.md' 'BOOTSTRAP'
    $custom=Get-AiwProjectCustomRegion $bootstrapPath
    $versionDoc=Read-AiwStrictJson $versionPath 'FRAMEWORK_VERSION'
    $manifestDoc=Read-AiwStrictJson $manifestPath 'RELEASE_MANIFEST'
    $candidatePilotStateIdentity='MISSING'
    if([string]$versionDoc.Value.lifecycle-ceq'CANDIDATE'){
        $candidatePilot=Get-AiwLocalCandidatePilotBinding -ProjectRoot $project -ProjectId ([string]$config.id) -VersionDirectory $versionDirectory -Version $TargetVersion -VersionObject $versionDoc.Value -ManifestDoc $manifestDoc -ProspectiveAdoptionProjection:$ProspectiveAdoptionProjection
        $candidatePilotStateIdentity=[string]$candidatePilot.Identity
    }
    $policyIdentity='MISSING';$projectStandardsIdentity='MISSING';$policyRules=@()
    if($null-ne$config.PSObject.Properties['processPolicy']){
        Assert-AiwExactFields $config.processPolicy @('schemaVersion','locator') 'PROCESS_POLICY_LOCATOR'
        if([int]$config.processPolicy.schemaVersion-ne3){throw 'FORMAT_WRITE_REQUIRED|PROCESS_POLICY'}
        $policyLocator=ConvertTo-AiwSafeRelativePath ([string]$config.processPolicy.locator) 'PROCESS_POLICY_LOCATOR'
        if($policyLocator-cne'.ai-workspace/process-policy.json'){throw 'PROCESS_POLICY_LOCATOR_CANONICAL'}
        $policyPath=Resolve-AiwChildFile $project $policyLocator 'PROCESS_POLICY'
        $policyDoc=Read-AiwStrictJson $policyPath 'PROCESS_POLICY';$policyIdentity=$policyDoc.Identity
        if($null-eq$policyDoc.Value.PSObject.Properties['rules']-or-not($policyDoc.Value.rules-is[Array])){throw 'PROCESS_POLICY_VALUES'}
        $policyRules=@($policyDoc.Value.rules)
        $standards=Get-AiwProjectStandardsSnapshot -ProjectRoot $project -Rules $policyRules -ForbiddenPaths $ForbiddenPaths -ExpectedConfigIdentity $configDoc.Identity -ExpectedPolicyIdentity $policyIdentity
        $projectStandardsIdentity=$standards.Identity
    }
    if($null-eq$config.PSObject.Properties['processPolicy']){$standards=Get-AiwProjectStandardsSnapshot -ProjectRoot $project -Rules @() -ForbiddenPaths $ForbiddenPaths}
    [object[]]$correctionRecords=@()
    if($null-ne$correctionsPath){$correctionRecords=@((Read-AiwStrictJson $correctionsPath 'CORRECTIONS').Value.corrections)}
    $effectiveSet=Test-AiwEffectiveRuleSet -ProjectRoot $project -Corrections $correctionRecords -PolicyRules $policyRules -Custom $custom -ForbiddenPaths $ForbiddenPaths -StandardsSnapshot $standards
    return [pscustomobject]@{
        projectConfigIdentity=$configDoc.Identity
        controllerIdentity=$(if($null-eq$controllerPath){'MISSING'}else{Get-AiwFileIdentity $controllerPath})
        correctionsIdentity=$(if($null-eq$correctionsPath){'MISSING'}else{Get-AiwFileIdentity $correctionsPath})
        policyIdentity=$policyIdentity
        bootstrapManagedIdentity=$custom.ManagedIdentity;projectCustomIdentity=$custom.Identity;projectAgentsIdentity=(Get-AiwProjectAgentsIdentity $project $ForbiddenPaths)
        projectStandardsIdentity=$projectStandardsIdentity
        taskIdentity=$(if($null-eq$taskPath){'NOT_APPLICABLE'}else{$taskDocument.Identity})
        frameworkVersionIdentity=Get-AiwFileIdentity $versionPath
        releaseManifestIdentity=Get-AiwFileIdentity $manifestPath
        candidatePilotStateIdentity=$candidatePilotStateIdentity
        nativeCatalogIdentity=Get-AiwFileIdentity $catalogPath
        contentSnapshotIdentity=$projectStandardsIdentity
        effectiveSetIdentity=$effectiveSet.identity
        implementationIdentity=(Get-AiwProcessImplementationIdentity -FrameworkRoot $framework -TargetVersion $TargetVersion)
    }

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}

function Test-AiwSelectorValue {
    param([object[]]$Allowed,[string]$Actual)
    if ($null -eq $Allowed -or @($Allowed).Count -eq 0) { return $true }
    return @($Allowed | Where-Object { [string]$_ -ceq '*' -or [string]$_ -ceq $Actual }).Count -gt 0
}

function Assert-AiwStringArray {
    param($Value,[Parameter(Mandatory)][string]$Label)
    if (-not ($Value -is [Array])) { throw "${Label}_TYPE" }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in @($Value)) {
        if (-not ($item -is [string]) -or [string]::IsNullOrWhiteSpace([string]$item) -or -not $seen.Add([string]$item)) { throw "${Label}_ITEM" }
    }
}

function Assert-AiwSelectorContract {
    param($Selectors,[Parameter(Mandatory)][string]$Label)
    $names=@('profiles','roles','phases','actionKinds','resultKinds','pathPrefixes','capabilities','semanticTerms')
    $optional=@('deterministicTriggers','semanticMatch','facets')
    $present=@($optional|Where-Object{$null-ne$Selectors.PSObject.Properties[$_]})
    Assert-AiwExactFields $Selectors @($names+$present) $Label
    foreach($name in $names){Assert-AiwStringArray $Selectors.$name ($Label+'_'+$name)}
    foreach($value in @($Selectors.profiles)){if([string]$value-cnotin@('*','MICRO','STANDARD','CRITICAL')){throw "${Label}_PROFILE"}}
    foreach($value in @($Selectors.roles)){if([string]$value-cnotin@('*','CONTROLLER','TASK_OWNER','EXECUTOR','REVIEWER','FRAMEWORK_MAINTAINER')){throw "${Label}_ROLE"}}
    foreach($value in @($Selectors.phases)){if([string]$value-cnotin@('*','DISCOVER','PLAN','IMPLEMENT','VERIFY','REVIEW','GIT','EXTERNAL','RECOVER')){throw "${Label}_PHASE"}}
    foreach($value in @($Selectors.actionKinds)){if([string]$value-cnotmatch '^(\*|NONE|CONTROL_WRITE|SOURCE_WRITE|TEST_WRITE|TEST_RUN|REVIEW_ROUTE|REVIEW_EXECUTE|RESULT_ACCEPT|GIT_STAGE|GIT_COMMIT|PUSH|BROWSER_RUN|DEVICE_RUN|EXTERNAL)$'){throw "${Label}_ACTION"}}
    foreach($value in @($Selectors.resultKinds)){if([string]$value-cnotmatch '^(\*|NONE|PLAN|USER_RESPONSE|TERMINAL|HANDOFF|REVIEW_VERDICT|RESULT_ACCEPTANCE|IMPLEMENTATION_RESULT|TEST_RESULT|GIT_RESULT|EXTERNAL_RESULT)$'){throw "${Label}_RESULT"}}
    foreach($value in @($Selectors.pathPrefixes)){if([string]$value-cne([string]$value).Replace('\','/')-or[IO.Path]::IsPathRooted([string]$value)-or([string]$value).Contains('..')){throw "${Label}_PATH"}}
    if($null-ne$Selectors.PSObject.Properties['semanticMatch']-and[string]$Selectors.semanticMatch-cne'TOKEN'){throw "${Label}_SEMANTIC_MATCH"}
    if($null-ne$Selectors.PSObject.Properties['facets']){Assert-AiwFacetSelector $Selectors.facets}
    if($null-ne$Selectors.PSObject.Properties['deterministicTriggers']){
        $triggers=$Selectors.deterministicTriggers
        Assert-AiwExactFields $triggers @('actionKinds','resultKinds') ($Label+'_TRIGGERS')
        foreach($axis in @('actionKinds','resultKinds')){
            Assert-AiwStringArray $triggers.$axis ($Label+'_TRIGGERS_'+$axis)
            foreach($value in @($triggers.$axis)){
                $allowed=if($axis-ceq'actionKinds'){@('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')}else{@('PLAN','USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','RESULT_ACCEPTANCE','IMPLEMENTATION_RESULT','TEST_RESULT','GIT_RESULT','EXTERNAL_RESULT')}
                if([string]$value-cnotin$allowed-or-not(Test-AiwSelectorValue @($Selectors.$axis) ([string]$value))){throw "${Label}_TRIGGER_OUTSIDE_BOUNDARY"}
            }
        }
        if(@($triggers.actionKinds).Count+@($triggers.resultKinds).Count-eq0){throw "${Label}_TRIGGERS_EMPTY"}
    }
}

function Test-AiwRuleMatch {
    param($Selectors,[string]$Profile,[string]$Role,[string]$Phase,[string]$ActionKind,[string]$ResultKind,[string[]]$Paths,[string[]]$Capabilities,[string]$Objective,[bool]$SemanticApplicabilityUnknown,$IntentFacets=$null)
    foreach($axis in @('profiles','roles','phases','actionKinds','resultKinds')){
        $actual=switch($axis){profiles{$Profile};roles{$Role};phases{$Phase};actionKinds{$ActionKind};resultKinds{$ResultKind}}
        if(-not(Test-AiwSelectorValue @($Selectors.$axis) $actual)){return [pscustomobject]@{Match=$false;Decision='NO_MATCH';Semantic='STRUCTURAL_NO_MATCH';Reasons=@($axis)}}
    }
    foreach($required in @($Selectors.capabilities)){
        if([string]$required-cne'*'-and[string]$required-cnotin$Capabilities){return [pscustomobject]@{Match=$false;Decision='NO_MATCH';Semantic='STRUCTURAL_NO_MATCH';Reasons=@('capabilities')}}
    }
    if(@($Selectors.pathPrefixes).Count-gt0-and@($Selectors.pathPrefixes|Where-Object{$prefix=([string]$_).TrimEnd('/');@($Paths|Where-Object{$_.Equals($prefix,[StringComparison]::OrdinalIgnoreCase)-or$_.StartsWith($prefix+'/',[StringComparison]::OrdinalIgnoreCase)}).Count-gt0}).Count-eq0){
        return [pscustomobject]@{Match=$false;Decision='NO_MATCH';Semantic='STRUCTURAL_NO_MATCH';Reasons=@('pathPrefixes')}
    }
    if($null-ne$Selectors.PSObject.Properties['facets']){
        if($null-eq$IntentFacets){
            # An unclassified private observation is not a new IntentEnvelope.
            $unknown=[ordered]@{};foreach($dimension in @('domain','workType','deliverableType','stage')){$unknown[$dimension]=[pscustomobject]@{state='UNKNOWN';values=@()}};$IntentFacets=[pscustomobject]$unknown
        }
        return Test-AiwFacetSelector -SelectorFacets $Selectors.facets -IntentFacets $IntentFacets
    }
    # Old textual applicability is retained as evidence, never promoted into a
    # new classification or current execution trigger. Structural limits remain.
    if(@($Selectors.semanticTerms).Count){return [pscustomobject]@{Match=$true;Decision='CONSERVATIVE';Semantic='LEGACY_SELECTOR_UNCLASSIFIED';Reasons=@('semanticTerms do not define facets')}}
    return [pscustomobject]@{Match=$true;Decision='MATCH';Semantic='DETERMINISTIC';Reasons=@()}
}

function Get-AiwProjectSourceRule {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][string]$Label,
        [AllowEmptyCollection()][string[]]$ForbiddenPaths=@(),
        $ContentContext=$null,
        $ReadTrace=$null
    )
    $source=$Rule.source
    if($null-ne$source.PSObject.Properties['kind']){
        return Get-AiwBoundProjectSourceRule -ProjectRoot $ProjectRoot -Rule $Rule -ForbiddenPaths $ForbiddenPaths -ContentContext $ContentContext -ReadTrace $ReadTrace
    }
    # A prospective carrier uses the same legacy source reader. Preserve its
    # additional read protection without changing the process snapshot input.
    if($null-ne$ContentContext){$ForbiddenPaths=@($ForbiddenPaths)+@($ContentContext.Forbidden)}
    Assert-AiwExactFields $source @('rootSourceId','documents') ($Label+'_SOURCE')
    if(-not($source.rootSourceId-is[string])-or[string]$source.rootSourceId-cnotmatch'^[A-Z][A-Z0-9_]*$'-or-not($source.documents-is[Array])-or@($source.documents).Count-lt1){throw ($Label+'_SOURCE_VALUES')}
    $byId=@{};$pathSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($document in @($source.documents)){
        $documentFields=@('sourceId','locator','identity','mode','sectionStart','sectionEnd','dependencies')
        $locatorKind='PROJECT_RELATIVE'
        if($null-ne$document.PSObject.Properties['locatorKind']){
            $locatorKind=[string]$document.locatorKind
            if($locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')){throw ($Label+'_LOCATOR_KIND')}
            $documentFields+=@('locatorKind')
        }
        Assert-AiwExactFields $document $documentFields ($Label+'_DOCUMENT')
        if(-not($document.sourceId-is[string])-or[string]$document.sourceId-cnotmatch'^[A-Z][A-Z0-9_]*$'-or$byId.ContainsKey([string]$document.sourceId)){throw ($Label+'_SOURCE_ID')}
        if([string]$document.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$document.mode-cnotin@('FULL_FILE','MARKED_SECTION')){throw ($Label+'_SOURCE_BINDING')}
        Assert-AiwStringArray $document.dependencies ($Label+'_DEPENDENCIES')
        if([string]$document.mode-ceq'FULL_FILE'){
            if([string]$document.sectionStart-cne'NOT_APPLICABLE'-or[string]$document.sectionEnd-cne'NOT_APPLICABLE'){throw ($Label+'_FULL_FILE_MARKERS')}
        }elseif(-not($document.sectionStart-is[string])-or-not($document.sectionEnd-is[string])-or[string]::IsNullOrWhiteSpace([string]$document.sectionStart)-or[string]::IsNullOrWhiteSpace([string]$document.sectionEnd)-or[string]$document.sectionStart-ceq[string]$document.sectionEnd){throw ($Label+'_SECTION_MARKERS')}
        $resolved=Resolve-AiwProjectStandardFile -ProjectRoot $ProjectRoot -Locator ([string]$document.locator) -LocatorKind ([string]$locatorKind) -Label ($Label+'_SOURCE_FILE') -ForbiddenPaths $ForbiddenPaths
        $path=[string]$resolved.Path;$locator=[string]$resolved.Locator
        if(-not$pathSeen.Add($path)){throw ($Label+'_LOCATOR_DUPLICATE')}
        $readPath=$path
        if($null-ne$ContentContext-and$ContentContext.ProjectedSources.ContainsKey($path)){
            $projected=$ContentContext.ProjectedSources[$path]
            if((Get-AiwFileIdentity $projected.Path)-cne$projected.Identity){throw 'CONTENT_IDENTITY_DRIFT|PROJECTED_SOURCE_OBJECT'}
            $readPath=$projected.Path
        }
        $text=Read-AiwStrictText $readPath ($Label+'_SOURCE_FILE')
        [byte[]]$snapshotBytes=$script:Utf8Strict.GetBytes($text)
        $actualIdentity=$snapshotBytes.Length.ToString()+'|'+(Get-AiwSha256Hex $snapshotBytes)
        if($null-ne$ReadTrace){$ReadTrace.Add([pscustomobject]@{sequence=$ReadTrace.Count;event='SOURCE_BODY_READ';ruleId=$Rule.ruleId;sourceId=$document.sourceId;path=$path;identity=$actualIdentity;observation='LIVE';authority=$false})}
        $byId[[string]$document.sourceId]=[pscustomobject]@{Document=$document;Locator=$locator;LocatorKind=[string]$resolved.LocatorKind;SourcePath=$path;ProjectionRelativePath=[string]$resolved.ProjectionRelativePath;Text=$text;SnapshotBytes=$snapshotBytes;ActualIdentity=$actualIdentity;Drift=($actualIdentity-cne[string]$document.identity)}
    }
    if(-not$byId.ContainsKey([string]$source.rootSourceId)){throw ($Label+'_ROOT_SOURCE')}
    foreach($node in @($byId.Values)){foreach($dependency in @($node.Document.dependencies)){if(-not$byId.ContainsKey([string]$dependency)){throw ($Label+'_DEPENDENCY_UNKNOWN')}}}
    $visiting=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$order=New-Object 'System.Collections.Generic.List[string]'
    function Visit-AiwProjectSourceNode([string]$Id){
        if($visited.Contains($Id)){return}
        if(-not$visiting.Add($Id)){throw ($Label+'_DEPENDENCY_CYCLE')}
        foreach($dependency in @($byId[$Id].Document.dependencies)){Visit-AiwProjectSourceNode ([string]$dependency)}
        $null=$visiting.Remove($Id);$null=$visited.Add($Id);$order.Add($Id)
    }
    Visit-AiwProjectSourceNode ([string]$source.rootSourceId)
    if($visited.Count-ne$byId.Count){throw ($Label+'_ORPHAN_SOURCE')}
    $blockParts=New-Object 'System.Collections.Generic.List[object]';$blocks=New-Object 'System.Collections.Generic.List[string]';$rows=New-Object 'System.Collections.Generic.List[string]';$drift=$false
    foreach($id in @($order)){
        $node=$byId[$id];$document=$node.Document;$body=[string]$node.Text;$selection='FULL_FILE'
        if([bool]$node.Drift){$drift=$true}
        elseif([string]$document.mode-ceq'MARKED_SECTION'){
            $body=$body.Replace("`r`n","`n")
            $start=[string]$document.sectionStart;$end=[string]$document.sectionEnd
            $startIndex=$body.IndexOf($start,[StringComparison]::Ordinal);$endIndex=$body.IndexOf($end,[StringComparison]::Ordinal)
            if($startIndex-lt0-or$endIndex-le$startIndex-or$body.IndexOf($start,$startIndex+1,[StringComparison]::Ordinal)-ge0-or$body.IndexOf($end,$endIndex+1,[StringComparison]::Ordinal)-ge0){throw ($Label+'_SECTION_CARDINALITY')}
            $bodyStart=$startIndex+$start.Length
            if($bodyStart-ge$body.Length-or$body[$bodyStart]-cne"`n"-or$endIndex-le$bodyStart+1-or$body[$endIndex-1]-cne"`n"){throw ($Label+'_SECTION_LAYOUT')}
            $selection=($bodyStart+1).ToString()+':'+($endIndex-$bodyStart-2).ToString()
            $body=$body.Substring($bodyStart+1,$endIndex-$bodyStart-2)
        }
        if([string]::IsNullOrWhiteSpace($body)){throw ($Label+'_SOURCE_EMPTY')}
        $sourceLabel=[string]$node.LocatorKind+':'+[string]$node.Locator
        $blocks.Add(('<!-- PROJECT-SOURCE:'+$sourceLabel+':BEGIN -->'+"`n"+$body.TrimEnd("`n")+"`n"+'<!-- PROJECT-SOURCE:'+$sourceLabel+':END -->'))
        $key=([IO.Path]::GetFullPath($node.SourcePath).ToUpperInvariant())+'|'+[string]$node.ActualIdentity+'|'+$selection+'|'+(Get-AiwSha256Hex $script:Utf8Strict.GetBytes($body))
        $blockParts.Add([pscustomobject]@{Key=$key;RawBody=$body;Text=$blocks[$blocks.Count-1];Locator=$sourceLabel;SourcePath=[string]$node.SourcePath;SourceIdentity=[string]$node.ActualIdentity})
        $rows.Add(([string]$id+'|'+[string]$node.LocatorKind+'|'+[string]$node.Locator+'|'+[string]$document.identity+'|'+[string]$node.ActualIdentity+'|'+[string]$document.mode+'|'+[string]::Join(',',@($document.dependencies))))
    }
    $identityBytes=$script:Utf8Strict.GetBytes(([string]::Join("`n",@($rows))))
    $documents=@($order|ForEach-Object{$node=$byId[[string]$_];[pscustomobject]@{locatorKind=[string]$node.LocatorKind;locator=[string]$node.Locator;relativePath=[string]$node.ProjectionRelativePath;sourcePath=[string]$node.SourcePath;identity=[string]$node.ActualIdentity;bytes=[byte[]]$node.SnapshotBytes}})
    return [pscustomobject]@{Blocks=$blockParts.ToArray();RawBody=[string]::Join("`n`n",@($blockParts|ForEach-Object RawBody));FullText=[string]::Join("`n`n",@($blocks));Identity=($identityBytes.Length.ToString()+'|'+(Get-AiwSha256Hex $identityBytes));Drift=$drift;Bindings=@($rows);Documents=$documents}
}

function Get-AiwBoundProjectSourceRule {
    param([string]$ProjectRoot,$Rule,[string[]]$ForbiddenPaths=@(),$ContentContext=$null,$ReadTrace=$null)
    $configPath=if($null-ne$ContentContext){$ContentContext.ConfigPath}else{Join-Path $ProjectRoot '.ai-workspace/project.json'}
    $context=$ContentContext
    if($null-eq$context){$context=New-AiwContentContext -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity (Get-AiwFileIdentity $configPath) -ForbiddenPaths $ForbiddenPaths}
    elseif(($context.ConfigRoot-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))-and$context.ProjectRoot-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot)))-or$context.ConfigPath-cne[IO.Path]::GetFullPath($configPath)-or$context.ConfigIdentity-cne(Get-AiwFileIdentity $configPath)){throw 'SOURCE_DENIED|PROJECTED_CONTEXT_ROOT'}
    $snapshot=Resolve-AiwContentSnapshot -Context $context -Descriptor $Rule.source
    $unitGraph=Read-AiwContentUnitGraph $context $snapshot
    return Convert-AiwBoundProjectSourceRule $ProjectRoot $Rule $context $snapshot $unitGraph $ReadTrace
}
function Convert-AiwBoundProjectSourceRule($ProjectRoot,$Rule,$context,$snapshot,$unitGraph,$ReadTrace){
    $parts=[Collections.Generic.List[object]]::new();$documents=@();$rows=@();$texts=@()
    # ResolveSnapshot's physical graph is dependency postorder, not catalog or
    # hash-table enumeration order. Every document is read by the same provider.
    foreach($entry in $unitGraph.units){
        $document=$entry.document;$read=$entry.read;$body=$entry.unit.body
        if($null-ne$ReadTrace){$ReadTrace.Add([pscustomobject]@{sequence=$ReadTrace.Count;event='SOURCE_BODY_READ';ruleId=$Rule.ruleId;sourceId=$document.sourceId;path=$read.physicalSource;identity=$read.identity;observation=$read.observation;authority=$false})}
        $binding=@($context.Config.sourceBindings|Where-Object{$_.id-ceq$document.bindingId})[0]
        $local=$binding.provider-ceq'LOCAL_DIRECTORY'
        $inside=$local-and$read.physicalSource.StartsWith($context.ProjectRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
        $kind=if(-not$local){$binding.provider}elseif([IO.Path]::IsPathRooted($binding.locator.root)){'ABSOLUTE_FILE'}else{'PROJECT_RELATIVE'}
        $locator=if($kind-ceq'PROJECT_RELATIVE'){[IO.Path]::GetRelativePath($context.ProjectRoot,$read.physicalSource).Replace('\','/')}else{$read.physicalSource}
        $label=$kind+':'+$locator
        $text='<!-- PROJECT-SOURCE:'+$label+':BEGIN -->'+"`n"+$body.TrimEnd("`n")+"`n"+'<!-- PROJECT-SOURCE:'+$label+':END -->'
        $key=$entry.unit.identity
        $dependencyIds=@();if($document.mode-ceq'NORMATIVE_UNIT'){$dependencyIds+=@($document.commonConditionSourceIds)};$dependencyIds+=@($document.dependencies)
        $orderedDependencies=@(foreach($dependencyId in $dependencyIds){@($unitGraph.units|Where-Object{$_.document.sourceId-ceq$dependencyId})[0].unit.identity})
        $parts.Add([pscustomobject]@{Key=$key;RawBody=$body;Text=$text;Locator=$label;SourcePath=$read.physicalSource;SourceIdentity=$read.identity;OrderedDependencies=$orderedDependencies})
        $texts+=$text;$rows+=($document.sourceId+'|'+$kind+'|'+$locator+'|'+$key+'|'+$document.mode+'|'+[string]::Join(',',@($document.dependencies)))
        $relative=if($kind-ceq'PROJECT_RELATIVE'-and$inside){$locator}else{'NOT_APPLICABLE'}
        $documents+=[pscustomobject]@{locatorKind=$kind;locator=$locator;relativePath=$relative;sourcePath=$read.physicalSource;identity=$read.identity;bytes=$read.bytes;bindingId=$document.bindingId;revision=$document.revision;observation=$read.observation}
    }
    $identity=Get-AiwContentDescriptorIdentity ([ordered]@{descriptor=$Rule.source;projectConfigIdentity=$context.ConfigIdentity;policyIdentity=$context.PolicyIdentity;bindings=@($snapshot.facts.documents|ForEach-Object{$_.bindingIdentity});documents=$rows;implementationIdentity=$context.ImplementationIdentity})
    return [pscustomobject]@{Blocks=$parts.ToArray();RawBody=[string]::Join("`n`n",@($parts|ForEach-Object RawBody));FullText=[string]::Join("`n`n",$texts);Identity=$identity;Drift=$false;Bindings=$rows;Documents=$documents;ContentSnapshot=$snapshot;ContentContext=$context;NormativeGraph=(@($Rule.source.documents|Where-Object mode -CEQ 'NORMATIVE_UNIT').Count-gt0)}
}

function Test-AiwEffectiveRuleSet {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Corrections,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PolicyRules,[Parameter(Mandatory)]$Custom,[string[]]$ForbiddenPaths=@(),$StandardsSnapshot=$null,$ContentContext=$null)
    if($null-eq$StandardsSnapshot){$StandardsSnapshot=Get-AiwProjectStandardsSnapshot -ProjectRoot $ProjectRoot -Rules $PolicyRules -ForbiddenPaths $ForbiddenPaths -ContentContext $ContentContext}
    $entries=@();$unknown=@()
    foreach($record in $Corrections){
        if($null-ne$record.PSObject.Properties['lifecycle']-and$record.lifecycle.state-cne'ACTIVE'){continue}
        $entries+=[pscustomobject]@{Source='PROJECT_CORRECTION';Id=$record.correctionId;Text=$record.effectiveRule;SharedKey='';MemberIdentity=(Get-AiwContentDescriptorIdentity $record)}
    }
    foreach($rule in $PolicyRules){
        $text='';$shared='';$sourceIdentity='INLINE';$semanticDuplicateKey=''
        if($null-ne$rule.PSObject.Properties['source']){
            $resolved=$StandardsSnapshot.Rules[[string]$rule.ruleId]
            if($null-eq$resolved-or$resolved.Unavailable-or$resolved.Drift){$unknown+=$rule.ruleId;continue}
            if($null-eq$resolved.PSObject.Properties['RawBody']){$unknown+=$rule.ruleId;continue}
            $text=$resolved.RawBody;$shared=[string]::Join(';',@($resolved.Blocks|ForEach-Object{$_.Key}));$sourceIdentity=$resolved.Identity
            if($null-ne$resolved.PSObject.Properties['NormativeGraph']-and$resolved.NormativeGraph){$semanticDuplicateKey=Get-AiwContentDescriptorIdentity ([ordered]@{units=$shared;selectors=$rule.selectors;preparationRequirements=@($rule.preparationRequirements);resultRequirements=@($rule.resultRequirements)})}
        }else{$text=$rule.effectiveRule}
        $entries+=[pscustomobject]@{Source='PROJECT_POLICY';Id=$rule.ruleId;Text=$text;SharedKey=$shared;SemanticDuplicateKey=$semanticDuplicateKey;MemberIdentity=(Get-AiwContentDescriptorIdentity ([ordered]@{rule=$rule;sourceIdentity=$sourceIdentity}))}
    }
    if($Custom.HasNormativeContent){$entries+=[pscustomobject]@{Source='LEGACY_PROJECT_CUSTOM';Id='PROJECT_CUSTOM';Text=$Custom.Text;SharedKey='';MemberIdentity=$Custom.Identity}}
    if($unknown.Count){throw ('EFFECTIVE_SET_UNPROVEN|'+[string]::Join(',',@($unknown)))}
    $owners=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$facts=@()
    foreach($entry in $entries){
        $normalized=([string]$entry.Text).Replace("`r`n","`n").Replace("`r","`n").Trim()
        if([string]::IsNullOrWhiteSpace($normalized)){throw ('EFFECTIVE_SET_UNPROVEN|'+$entry.Id)}
        $identity=Get-AiwContentByteIdentity $script:Utf8Strict.GetBytes($normalized)
        if($null-ne$entry.PSObject.Properties['SemanticDuplicateKey']-and$entry.SemanticDuplicateKey){$identity=Get-AiwContentDescriptorIdentity @($identity,$entry.SemanticDuplicateKey)}
        if($owners.ContainsKey($identity)){
            $previous=$owners[$identity]
            if(-not([string]$entry.SharedKey-and$previous.SharedKey-ceq$entry.SharedKey)){throw ('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE|'+$previous.Source+':'+$previous.Id+'|'+$entry.Source+':'+$entry.Id)}
        }else{$owners.Add($identity,$entry)}
        $facts+=[ordered]@{source=$entry.Source;id=$entry.Id;normalizedIdentity=$identity;sharedKey=$entry.SharedKey;memberIdentity=$entry.MemberIdentity}
    }
    $implementation=Get-AiwFileIdentity $script:ComposerModulePath
    $material=[ordered]@{members=$facts;customIdentity=$Custom.Identity;standardsIdentity=$StandardsSnapshot.Identity;forbiddenPaths=$ForbiddenPaths;implementationIdentity=$implementation}
    return [pscustomobject]@{status='PASS';identity=(Get-AiwContentDescriptorIdentity $material);members=$facts;authority=$false}
}
Export-ModuleMember -Function Test-AiwEffectiveRuleSet

function Get-AiwProjectPolicySourceClosure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules,
        [AllowEmptyCollection()][string[]]$ForbiddenPaths=@(),
        $ContentContext=$null
    )
    return (Get-AiwProjectPolicySourceClosureCore -ProjectRoot $ProjectRoot -Rules $Rules -ForbiddenPaths $ForbiddenPaths -ContentContext $ContentContext).Closure
}

# Private publication pair material never crosses the public closure API. It
# contains raw closure documents only, not a target rule/snapshot identity with
# the old policy identity embedded in it.
function Get-AiwProjectPolicySourceClosureCore {
    param([string]$ProjectRoot,[AllowEmptyCollection()][object[]]$Rules,[string[]]$ForbiddenPaths=@(),$ContentContext=$null,$PreviousMaterial=$null)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $ProjectRoot -Mode OBSERVE
try {


    $documents=New-Object 'System.Collections.Generic.List[object]'
    $snapshotChecks=New-Object 'System.Collections.Generic.List[object]'
    $byLocator=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $sourceRules=@($Rules|Where-Object{$null-ne$_.PSObject.Properties['source']})
    $batch=$null;$batchContext=$ContentContext;$boundBatch=$false
    $reused=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $materialRules=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    if($sourceRules.Count-gt0-and@($sourceRules|Where-Object{$null-eq$_.source.PSObject.Properties['kind']-or$_.source.kind-cne'BOUND_SOURCE_ITEM'}).Count-eq0){
        $boundBatch=$true
        if($null-eq$batchContext){$batchContext=New-AiwContentContext -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity (Get-AiwFileIdentity (Join-Path $ProjectRoot '.ai-workspace/project.json')) -ForbiddenPaths $ForbiddenPaths}
        if($null-ne$PreviousMaterial){
            $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))
            if($batchContext.ConfigRoot-cne$root-and$batchContext.ProjectRoot-cne$root){throw 'SOURCE_DENIED|PROJECTED_CONTEXT_ROOT'}
            $contentModule=(Get-Command New-AiwContentContext).Module
            $reused=& $contentModule {param($c,$r,$previous)Get-CsPublicationReuseCandidates $c $r $previous} $batchContext $Rules $PreviousMaterial
        }
        $remaining=@($Rules|Where-Object{-not$reused.ContainsKey([string]$_.ruleId)})
        if(@($remaining|Where-Object{$null-ne$_.PSObject.Properties['source']}).Count){$batch=Get-AiwProjectStandardsSnapshot -ProjectRoot $ProjectRoot -Rules $remaining -ForbiddenPaths $ForbiddenPaths -ContentContext $batchContext}
    }
    foreach($rule in @($Rules)){
        if($null-eq$rule.PSObject.Properties['source']){continue}
        $label='PROCESS_POLICY_'+[string]$rule.ruleId
        $validated=if($reused.ContainsKey([string]$rule.ruleId)){$reused[[string]$rule.ruleId]}elseif($null-ne$batch){$batch.Rules[[string]$rule.ruleId]}else{Get-AiwProjectSourceRule -ProjectRoot $ProjectRoot -Rule $rule -Label $label -ForbiddenPaths $ForbiddenPaths -ContentContext $ContentContext}
        if($null-ne$validated.PSObject.Properties['Unavailable']-and$validated.Unavailable){throw $validated.Error}
        if($validated.Drift){throw ('PROJECT_SOURCE_CLOSURE_DRIFT|'+[string]$rule.ruleId)}
        if($boundBatch-and@($validated.Documents|Where-Object{$_.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')}).Count-eq0){
            $materialRules.Add([string]$rule.ruleId,[pscustomobject]@{RuleIdentity=(Get-AiwContentDescriptorIdentity $rule);Documents=@($validated.Documents)})
        }
        if($null-ne$validated.PSObject.Properties['ContentSnapshot']-and($null-eq$batch-or@($validated.Documents|Where-Object{$_.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')}).Count)){$snapshotChecks.Add([pscustomobject]@{Context=$(if($null-ne$batch){$batchContext}else{$validated.ContentContext});Snapshot=$validated.ContentSnapshot})}
        foreach($document in @($validated.Documents)){
            $key=[string]$document.locatorKind+'|'+[string]$document.sourcePath
            if($byLocator.ContainsKey($key)){
                if([string]$byLocator[$key].identity-cne[string]$document.identity){throw ('PROJECT_SOURCE_CLOSURE_DRIFT|'+[string]$document.locator)}
                continue
            }
            $item=[pscustomobject]@{locatorKind=[string]$document.locatorKind;locator=[string]$document.locator;relativePath=[string]$document.relativePath;sourcePath=[string]$document.sourcePath;identity=[string]$document.identity;bytes=[byte[]]$document.bytes}
            $byLocator[$key]=$item
            $documents.Add($item)
        }
    }
    [string[]]$rows=@($documents|ForEach-Object{[string]$_.locatorKind+'|'+[string]$_.locator+'|'+[string]$_.identity})
    [Array]::Sort($rows,[StringComparer]::Ordinal)
    if($rows.Count-eq0){return [pscustomobject]@{Closure=[pscustomobject]@{Identity='MISSING';Documents=@();SnapshotChecks=@()};Material=$null}}
    $identityBytes=$script:Utf8Strict.GetBytes(([string]::Join("`n",$rows)))
    $closure=[pscustomobject]@{Identity=($identityBytes.Length.ToString()+'|'+(Get-AiwSha256Hex $identityBytes));Documents=[object[]]$documents.ToArray();SnapshotChecks=[object[]]$snapshotChecks.ToArray()}
    if($boundBatch){$closure|Add-Member -NotePropertyName LocalReadContext -NotePropertyValue $batchContext}
    $material=if($boundBatch){[pscustomobject]@{ProjectRoot=$batchContext.ProjectRoot;ConfigIdentity=$batchContext.ConfigIdentity;ImplementationIdentity=$batchContext.ImplementationIdentity;Rules=$materialRules}}else{$null}
    return [pscustomobject]@{Closure=$closure;Material=$material}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}

function Assert-AiwProjectPolicySourceClosure {
    [CmdletBinding()]param([Parameter(Mandatory)]$Closure,$ContentContext=$null)
    foreach($check in @($Closure.SnapshotChecks)){$null=Test-AiwContentSnapshot -Context $check.Context -Snapshot $check.Snapshot}
    if($null-ne$Closure.PSObject.Properties['LocalReadContext']){
        $context=$Closure.LocalReadContext
        # Reuse the existing context owner to recheck current permission,
        # adoption and implementation before reading actual local member bytes.
        $contentOwner=(Get-Command New-AiwContentContext).Module
        $null=& $contentOwner {param($c)Get-CsContextInputs $c} $context
        foreach($document in @($Closure.Documents|Where-Object{$_.locatorKind-cin@('PROJECT_RELATIVE','ABSOLUTE_FILE')})){
            $origin=$document.sourcePath;$path=$origin
            if($context.ProjectedSources.ContainsKey($path)){$path=$context.ProjectedSources[$path].Path}
            Assert-AiwProjectStandardReadAllowed $context.ProjectRoot $origin @($context.Forbidden) 'PROJECT_SOURCE_CLOSURE'
            Assert-AiwProjectStandardReadAllowed $context.ProjectRoot $path @($context.Forbidden) 'PROJECT_SOURCE_CLOSURE'
            # A projection may supply a new, still missing original member,
            # but neither original nor projected ancestors may become links.
            $null=& $contentOwner {param($original,$actual,$forbidden) Assert-CsPath $original $forbidden -AllowMissing;Assert-CsPath $actual $forbidden} $origin $path @($context.Forbidden)
            if((Get-AiwFileIdentity $path)-cne$document.identity){throw 'PROJECT_SOURCE_CLOSURE_DRIFT'}
        }
        return
    }
    if(@($Closure.SnapshotChecks).Count-eq0){foreach($document in @($Closure.Documents)){
        $path=$document.sourcePath
        if($null-ne$ContentContext-and$ContentContext.ProjectedSources.ContainsKey($path)){$path=$ContentContext.ProjectedSources[$path].Path}
        if($document.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')-or(Get-AiwFileIdentity $path)-cne$document.identity){throw 'PROJECT_SOURCE_CLOSURE_DRIFT'}
    }}
}
Export-ModuleMember -Function Assert-AiwProjectPolicySourceClosure

function Get-AiwProjectStandardsSnapshot {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rules,[AllowEmptyCollection()][string[]]$ForbiddenPaths=@(),$ReadTrace=$null,$ContentContext=$null,[string]$ExpectedConfigIdentity='',[string]$ExpectedPolicyIdentity='')
    $resolved=@{};$rows=New-Object 'System.Collections.Generic.List[string]'
    $standardsContext=$ContentContext;$ownedBatch=$null
    $sourceRules=@($Rules|Where-Object{$null-ne$_.PSObject.Properties['source']})
    # Keep legacy carrier resolution and its original ordering unchanged. All
    # supported bound whole-file/section/normative modes use the closed batch.
    if($sourceRules.Count-gt0-and@($sourceRules|Where-Object{$null-eq$_.source.PSObject.Properties['kind']-or$_.source.kind-cne'BOUND_SOURCE_ITEM'}).Count-eq0){
        $contentModule=(Get-Command New-AiwContentContext).Module
        $ownedBatch=& $contentModule {param($root,$rules,$forbidden,$context,$configIdentity,$policyIdentity) Invoke-CsOwnedStandardsBatch -ProjectRoot $root -Rules $rules -ForbiddenPaths $forbidden -ContentContext $context -ExpectedConfigIdentity $configIdentity -ExpectedPolicyIdentity $policyIdentity} $ProjectRoot $Rules $ForbiddenPaths $ContentContext $ExpectedConfigIdentity $ExpectedPolicyIdentity
    }
    foreach($rule in @($Rules)){
        if($null-eq$rule.PSObject.Properties['source']){continue}
        $label='PROCESS_POLICY_'+[string]$rule.ruleId
        try {
            if($null-ne$ownedBatch){
                $packet=$ownedBatch.rules[[string]$rule.ruleId]
                if($packet.error-cne'NONE'){throw $packet.error}
                $item=Convert-AiwBoundProjectSourceRule $ProjectRoot $rule $ownedBatch.contextFacts $packet.snapshot $packet.graph $ReadTrace
            }else{
                $item=Get-AiwProjectSourceRule -ProjectRoot $ProjectRoot -Rule $rule -Label $label -ForbiddenPaths $ForbiddenPaths -ReadTrace $ReadTrace -ContentContext $standardsContext
            }
            $item|Add-Member -NotePropertyName Unavailable -NotePropertyValue $false
            $item|Add-Member -NotePropertyName Error -NotePropertyValue 'NONE'
        } catch {
            $reason=[string]$_.Exception.Message
            $recoverable='^'+[regex]::Escape($label)+'_(?:SOURCE_FILE_(?:MISSING|REPARSE|UNREADABLE|BOM|UTF8|TEXT_FORMAT)|SECTION_(?:CARDINALITY|LAYOUT)|SOURCE_EMPTY)$'
            if($reason-cnotmatch$recoverable-and$reason-cnotmatch'^SOURCE_UNAVAILABLE(?:\||$)'){throw}
            $declared=$rule.source|ConvertTo-Json -Depth 20 -Compress
            $errorMaterial=$declared+"`nUNAVAILABLE="+$reason
            $errorBytes=$script:Utf8Strict.GetBytes($errorMaterial)
            $item=[pscustomobject]@{FullText='';Identity=($errorBytes.Length.ToString()+'|'+(Get-AiwSha256Hex $errorBytes));Drift=$false;Bindings=@();Unavailable=$true;Error=$reason}
        }
        $resolved[[string]$rule.ruleId]=$item
        $rows.Add(([string]$rule.ruleId+'|'+[string]$item.Identity))
    }
    if($rows.Count-eq0){return [pscustomobject]@{Identity='MISSING';Rules=$resolved;Drift=$false}}
    [string[]]$sorted=@($rows);[Array]::Sort($sorted,[StringComparer]::Ordinal)
    $bytes=$script:Utf8Strict.GetBytes(([string]::Join("`n",$sorted)))
    return [pscustomobject]@{Identity=($bytes.Length.ToString()+'|'+(Get-AiwSha256Hex $bytes));Rules=$resolved;Drift=(@($resolved.Values|Where-Object{[bool]$_.Drift}).Count-gt0)}
}

function Get-AiwSelectedPublicationMaterial($ProjectRoot,$ConfigIdentity,$Rules,$Standards) {
    # Only the private composition call captures these actually verified local
    # documents. Public composition results retain their existing shape.
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))
    $materialRules=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $implementation=$null
    foreach($rule in $Rules){
        if($null-eq$rule.PSObject.Properties['source']-or$null-eq$rule.source.PSObject.Properties['kind']-or$rule.source.kind-cne'BOUND_SOURCE_ITEM'){continue}
        $item=$Standards.Rules[[string]$rule.ruleId]
        if($null-eq$item-or$item.Unavailable-or$item.Drift-or$null-eq$item.PSObject.Properties['ContentContext']){continue}
        if(@($item.Documents|Where-Object{$_.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')}).Count){continue}
        $context=$item.ContentContext
        if($context.ProjectRoot-cne$root-or$context.ConfigIdentity-cne$ConfigIdentity){return $null}
        if($null-eq$implementation){$implementation=$context.ImplementationIdentity}
        elseif($implementation-cne$context.ImplementationIdentity){return $null}
        $documents=@(foreach($document in $item.Documents){
            [pscustomobject]@{locatorKind=$document.locatorKind;locator=$document.locator;relativePath=$document.relativePath;sourcePath=$document.sourcePath;identity=$document.identity;bytes=[byte[]]$document.bytes.Clone()}
        })
        $materialRules.Add([string]$rule.ruleId,[pscustomobject]@{RuleIdentity=(Get-AiwContentDescriptorIdentity $rule);Documents=$documents})
    }
    if($materialRules.Count-eq0){return $null}
    return [pscustomobject]@{ProjectRoot=$root;ConfigIdentity=$ConfigIdentity;ImplementationIdentity=$implementation;Rules=$materialRules}
}

function Invoke-ProcessRequirementComposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][string]$TargetVersion,
        [string]$ComposerVersion=$TargetVersion,
        [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
        [string]$ExpectedCorrectionsIdentity,
        [Parameter(Mandatory)][string]$Profile,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Actor,
        [Parameter(Mandatory)][string]$TaskIdentity,
        [string[]]$Capabilities=@(),
        [string]$Objective='UNKNOWN',
        [string]$ActionKind='NONE',
        [string]$ResultKind='NONE',
        [string[]]$ExactPaths=@(),
        [AllowEmptyCollection()][string[]]$ForbiddenPaths=@(),
        [switch]$SemanticApplicabilityUnknown,
        [switch]$AllowProjectPinMismatch,
        [switch]$UseDeclaredCapabilities,
        [switch]$EvaluationOnly,
        $IntentEnvelope=$null,
        $ContentContext=$null,
        [switch]$ValidateCompleteAdoptedSet
    )
    return Invoke-AiwProcessCompositionCore @PSBoundParameters
}
function Invoke-AiwProcessCompositionCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][string]$TargetVersion,
        [string]$ComposerVersion=$TargetVersion,
        [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
        [string]$ExpectedCorrectionsIdentity,
        [Parameter(Mandatory)][string]$Profile,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Actor,
        [Parameter(Mandatory)][string]$TaskIdentity,
        [string[]]$Capabilities=@(),
        [string]$Objective='UNKNOWN',
        [string]$ActionKind='NONE',
        [string]$ResultKind='NONE',
        [string[]]$ExactPaths=@(),
        [AllowEmptyCollection()][string[]]$ForbiddenPaths=@(),
        [switch]$SemanticApplicabilityUnknown,
        [switch]$AllowProjectPinMismatch,
        [switch]$UseDeclaredCapabilities,
        [switch]$EvaluationOnly,
        $IntentEnvelope=$null,
        $ContentContext=$null,
        [switch]$ValidateCompleteAdoptedSet,
        [switch]$BindingSnapshotOnly,
        $RuleObservation=$null,
        $PublicationMaterial=$null
    )
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $ProjectRoot -Mode OBSERVE
try {

    if($null-ne$PublicationMaterial){
        if($PublicationMaterial-isnot[System.Management.Automation.PSReference]){throw 'SOURCE_PUBLICATION_PRIVATE_CAPTURE_REFERENCE_REQUIRED'}
        $PublicationMaterial.Value=$null
    }
    $readTrace=[Collections.Generic.List[object]]::new()
    $project = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
    $framework = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FrameworkRoot)))
    $configPath = if($EvaluationOnly-and$null-ne$ContentContext){$ContentContext.ConfigPath}else{Resolve-AiwChildFile $project '.ai-workspace/project.json' 'PROJECT_CONFIG'}
    $configDoc = Read-AiwStrictJson $configPath 'PROJECT_CONFIG'
    if ($configDoc.Identity -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
    $config = $configDoc.Value
    if($null-ne$ContentContext-and(-not$EvaluationOnly-or($ContentContext.ConfigRoot-cne$project-and$ContentContext.ProjectRoot-cne$project)-or$ContentContext.ConfigIdentity-cne$configDoc.Identity)){throw 'SOURCE_DENIED|PROJECTED_COMPOSITION_CONTEXT'}
    if (-not $AllowProjectPinMismatch -and -not $EvaluationOnly -and [string]$config.frameworkVersion -cne $TargetVersion) { throw 'PROJECT_PIN_TARGET_MISMATCH' }
    $projectId = [string]$config.id
    Assert-AiwStringArray $Capabilities 'OBSERVED_CAPABILITIES'
    if(-not(Test-AiwJsonInteger $config.schemaVersion)-or$config.schemaVersion-ne7){throw 'FORMAT_WRITE_REQUIRED|PROJECT_CONFIG'}
    $currentConfig=Read-AiwCurrentObject -ObjectType PROJECT_CONFIG -Locator $configPath -ExpectedIdentity $configDoc.Identity -Context ([pscustomobject]@{ForbiddenPaths=@($ForbiddenPaths);ProspectiveAdoptionProjection=[bool]$EvaluationOnly})
    if($currentConfig.Status-cne'CURRENT'){throw 'FORMAT_WRITE_REQUIRED|PROJECT_CONFIG'}
    if($null-eq$config.PSObject.Properties['frameworkCapabilities']){throw 'PROJECT_CAPABILITIES_MISSING'}
    $declaredCapabilities=@(Assert-AiwFrameworkCapabilities $config.frameworkCapabilities)
    $declaredSorted=@($declaredCapabilities|Sort-Object)
    if($UseDeclaredCapabilities){$Capabilities=@($declaredSorted)}else{$observedSorted=@($Capabilities|Sort-Object);if([string]::Join("`n",$declaredSorted)-cne[string]::Join("`n",$observedSorted)){throw 'PROJECT_CAPABILITY_DRIFT'}}

    $versionPath = Resolve-AiwChildFile $framework ("framework/versions/$TargetVersion/VERSION.json") 'FRAMEWORK_VERSION'
    $versionDoc = Read-AiwStrictJson $versionPath 'FRAMEWORK_VERSION'
    $versionObject = $versionDoc.Value
    if ([string]$versionObject.version -cne $TargetVersion) { throw 'FRAMEWORK_VERSION_MISMATCH' }
    $versionDirectory = Split-Path -Parent $versionPath
    $releaseManifestDoc=Read-AiwStrictJson (Resolve-AiwChildFile $versionDirectory 'RELEASE_MANIFEST.json' 'RELEASE_MANIFEST') 'RELEASE_MANIFEST'
    $stable = [string]$versionObject.lifecycle -ceq 'STABLE' -and [bool]$versionObject.consumable -and [bool]$versionObject.projectPinEligible
    $candidateShape = [string]$versionObject.lifecycle -ceq 'CANDIDATE' -and -not [bool]$versionObject.consumable -and -not [bool]$versionObject.projectPinEligible
    $candidateEvaluation = $EvaluationOnly -and $candidateShape
    $releaseObservation=$null
    if($stable-or(-not$candidateEvaluation-and$candidateShape)){$releaseObservation=Get-AiwCompositionReleaseFacts -VersionDirectory $versionDirectory -ProjectRoot $project -DailyProcessObservation}
    $runtimePackageObservation=if($null-ne$releaseObservation-and$null-ne$releaseObservation.Observation){$releaseObservation.Observation.PackageObservation}else{$null}
    $candidatePilotStateIdentity='MISSING'
    if(-not$stable-and-not$candidateEvaluation-and$candidateShape){
        $candidatePilot=Get-AiwLocalCandidatePilotBinding -ProjectRoot $project -ProjectId $projectId -VersionDirectory $versionDirectory -Version $TargetVersion -VersionObject $versionObject -ManifestDoc $releaseManifestDoc -ReleaseObservation $releaseObservation
        $candidatePilotStateIdentity=[string]$candidatePilot.Identity
    }elseif(-not$stable-and-not$candidateEvaluation){throw 'FRAMEWORK_VERSION_NOT_ADMITTED'}
    if($stable){Assert-AiwSealedRelease $versionDirectory $TargetVersion -ProjectRoot $project -ReleaseObservation $releaseObservation}
    $releaseManifestIdentity=$releaseManifestDoc.Identity
    $composerVersionPath=Resolve-AiwChildFile $framework ("framework/versions/$ComposerVersion/VERSION.json") 'COMPOSER_VERSION'
    $composerVersionDirectory=Split-Path -Parent $composerVersionPath
    if($ComposerVersion-cne$TargetVersion){$composerVersionDoc=Read-AiwStrictJson $composerVersionPath 'COMPOSER_VERSION';if([string]$composerVersionDoc.Value.version-cne$ComposerVersion-or[string]$composerVersionDoc.Value.lifecycle-cne'STABLE'-or-not[bool]$composerVersionDoc.Value.consumable-or-not[bool]$composerVersionDoc.Value.projectPinEligible){throw 'COMPOSER_VERSION_NOT_ADMITTED'};Assert-AiwSealedRelease $composerVersionDirectory $ComposerVersion}
    $catalogPath = Resolve-AiwChildFile $composerVersionDirectory 'PROCESS_REQUIREMENTS.json' 'PROCESS_REQUIREMENTS'
    $catalogDoc = Read-AiwStrictJson $catalogPath 'PROCESS_REQUIREMENTS'
    $catalog = $catalogDoc.Value
    Assert-AiwExactFields $catalog @('schemaVersion','frameworkVersion','catalogVersion','facetVocabulary','requirements') 'PROCESS_REQUIREMENTS'
    if ([int]$catalog.schemaVersion -ne 3 -or [string]$catalog.catalogVersion -cne '4' -or [string]$catalog.frameworkVersion -cne $ComposerVersion -or -not ($catalog.requirements -is [Array])-or$catalog.facetVocabulary-isnot[Array]) { throw 'PROCESS_REQUIREMENTS_VALUES' }
    $nativeVocabulary=Get-AiwFacetVocabulary -NativeVocabulary @($catalog.facetVocabulary)
    $nativeById = @{}
    $nativeByAlias = @{}
    foreach ($requirement in @($catalog.requirements)) {
        Assert-AiwExactFields $requirement @('requirementId','legacyAliases','title','description','ownerModule','selectors','exactBlockLocator','preparationRequirements','resultRequirements') 'NATIVE_REQUIREMENT'
        $nativeId='framework:'+[string]$requirement.requirementId
        if ([string]$requirement.requirementId -cnotmatch '^PR_[A-Z0-9_]+$' -or $nativeById.ContainsKey($nativeId)) { throw 'NATIVE_REQUIREMENT_ID' }
        Assert-AiwStringArray $requirement.legacyAliases 'NATIVE_REQUIREMENT_ALIASES'
        Assert-AiwSelectorContract $requirement.selectors 'NATIVE_REQUIREMENT_SELECTORS'
        if($null-eq$requirement.selectors.PSObject.Properties['facets']){throw 'NATIVE_REQUIREMENT_FACETS_REQUIRED'}
        Assert-AiwFacetSelector -Facets $requirement.selectors.facets -Vocabulary $nativeVocabulary
        Assert-AiwStringArray $requirement.preparationRequirements 'NATIVE_REQUIREMENT_PREPARATION'
        Assert-AiwStringArray $requirement.resultRequirements 'NATIVE_REQUIREMENT_RESULT'
        foreach($field in @('title','description','ownerModule','exactBlockLocator')){if(-not($requirement.$field-is[string])-or[string]::IsNullOrWhiteSpace([string]$requirement.$field)){throw 'NATIVE_REQUIREMENT_TEXT'}}
        if ([string]$requirement.exactBlockLocator -cne ('AIW-REQUIREMENT:' + [string]$requirement.requirementId)) { throw 'NATIVE_REQUIREMENT_LOCATOR' }
        foreach ($alias in @($requirement.legacyAliases)) {
            if ([string]$alias -cnotmatch '^correction:[a-z0-9][a-z0-9-]*:[A-Z][A-Z0-9_]*$' -or $nativeByAlias.ContainsKey([string]$alias)) { throw 'NATIVE_REQUIREMENT_ALIAS' }
            $nativeByAlias[[string]$alias]=$nativeId
        }
        $nativeById[$nativeId]=$requirement
    }

    $correctionsPath = Resolve-AiwChildFile $project '.ai-workspace/corrections.json' 'CORRECTIONS' -AllowMissing
    $controllerPath = Resolve-AiwChildFile $project '.ai-workspace/controller.json' 'CONTROLLER' -AllowMissing
    $controllerIdentity = if ($null -eq $controllerPath) { 'MISSING' } else { Get-AiwFileIdentity $controllerPath }
    $correctionsIdentity = if ($null -eq $correctionsPath) { 'MISSING' } else { Get-AiwFileIdentity $correctionsPath }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCorrectionsIdentity) -and $correctionsIdentity -cne $ExpectedCorrectionsIdentity) { throw 'CORRECTIONS_DRIFT' }
    $records = @()
    if ($null -ne $correctionsPath) {
        $correctionsDoc = Read-AiwStrictJson $correctionsPath 'CORRECTIONS'
        $readTrace.Add([pscustomobject]@{sequence=$readTrace.Count;event='SOURCE_CARRIER_READ';path=$correctionsPath;identity=$correctionsDoc.Identity;observation='LIVE';authority=$false})
        $corrections = $correctionsDoc.Value
        Assert-AiwExactFields $corrections @('schemaVersion','contractVersion','projectId','corrections') 'CORRECTIONS'
        if ([int]$corrections.schemaVersion -ne 3) { throw 'FORMAT_WRITE_REQUIRED|PROJECT_CORRECTIONS' }
        if ([string]$corrections.projectId -cne $projectId -or -not ($corrections.corrections -is [Array])) { throw 'CORRECTIONS_VALUES' }
        if ([string]$corrections.contractVersion -cne $script:ProcessCarrierContractVersion) { throw 'CORRECTIONS_CONTRACT' }
        $currentCorrections=Read-AiwCurrentObject -ObjectType PROJECT_CORRECTIONS -Locator $correctionsPath -ExpectedIdentity $correctionsDoc.Identity -Context ([pscustomobject]@{ForbiddenPaths=@($ForbiddenPaths)})
        $seenCorrection = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($record in @($corrections.corrections)) {
            $v1Record = if ([int]$corrections.schemaVersion -eq 1) { $record } else { [pscustomobject][ordered]@{correctionId=$record.correctionId;introducedAgainstFramework=$record.introducedAgainstFramework;requirementReason=$record.requirementReason;effectiveRule=$record.effectiveRule;applicability=$record.applicability;decisionLocator=$record.decisionLocator} }
            $canonical = Get-AiwCanonicalCorrectionRecordIdentityV1 $v1Record
            if ([string]$record.correctionId -cnotmatch '^[A-Z][A-Z0-9_]*$' -or -not $seenCorrection.Add([string]$record.correctionId)) { throw 'CORRECTION_ID' }
            $v2Identity = 'NOT_APPLICABLE'
            if ([int]$corrections.schemaVersion -eq 3) {
                $null=Get-AiwCanonicalCorrectionRecordIdentityV2 $record
                Assert-AiwSelectorContract $record.selectors 'CORRECTION_V2_SELECTORS'
                foreach ($name in @('preparationRequirements','resultRequirements','requiredFacts','mechanicalCheckRefs')) { Assert-AiwStringArray $record.$name ('CORRECTION_V2_' + $name) }
                $registeredChecks=@('CURRENT_AUTHORITY_BOUND','ACTION_PACKAGE_VALID','EXACT_SCOPE_BOUND','TASK_SCOPE_CURRENT','PROTECTION_BOUNDARY_PROVEN','REVIEWER_INDEPENDENCE_PROVEN','SAFE_GIT_STATE_PROVEN','EXTERNAL_BOUNDARY_AUTHORIZED','DOMAIN_EXTERNAL_PACKAGE_VALID','EXTERNAL_PAYLOAD_IDENTITIES_BOUND','USER_EXTERNAL_DECISION_BOUND')
                foreach ($check in @($record.mechanicalCheckRefs)) { if ([string]$check -cnotin $registeredChecks) { throw 'CORRECTION_V2_MECHANICAL_CHECK_UNREGISTERED' } }
                $v2Identity = Get-AiwCanonicalCorrectionRecordIdentityV2 $record
            }
            $records += [pscustomobject]@{ Record=$record; SchemaVersion=[int]$corrections.schemaVersion; Alias=('correction:'+$projectId+':'+[string]$record.correctionId); SourceRecordIdentity=$canonical; V2WholeRecordIdentity=$v2Identity }
        }
    }

    # Current correction lifecycle is project-owned; no central semantic suppression.
    $legacyEffective = @(); $legacyConflicts = @(); $inactiveCorrections=@()
    foreach ($item in $records) {
        if($null-ne$item.Record.PSObject.Properties['lifecycle']-and$item.Record.lifecycle.state-cne'ACTIVE'){
            $inactiveCorrections+=[pscustomobject]@{correctionId=$item.Record.correctionId;state=$item.Record.lifecycle.state;decisionLocator=$item.Record.lifecycle.decisionLocator}
            continue
        }
        $view = [ordered]@{correctionId=[string]$item.Record.correctionId;requirementReason=[string]$item.Record.requirementReason;effectiveRule=[string]$item.Record.effectiveRule;applicability=[string]$item.Record.applicability;decisionLocator=[string]$item.Record.decisionLocator;sourceSchemaVersion=[int]$item.SchemaVersion;legacyRequirementId=[string]$item.Alias;legacySourceRecordIdentity=[string]$item.SourceRecordIdentity;v2WholeRecordIdentity=[string]$item.V2WholeRecordIdentity}
        $legacyEffective += [pscustomobject]$view
    }

    $bootstrapPath = Resolve-AiwChildFile $project '.ai-workspace/BOOTSTRAP.md' 'BOOTSTRAP'
    $custom = Get-AiwProjectCustomRegion $bootstrapPath
    $readTrace.Add([pscustomobject]@{sequence=$readTrace.Count;event='SOURCE_CARRIER_READ';path=$bootstrapPath;identity=$custom.Identity;observation='LIVE';authority=$false})
    $policyRules = @(); $policyIdentity='MISSING'; $policyLocator='NONE'; $selectedRulePackBytes=0;$projectVocabulary=@()
    if ($null -ne $config.PSObject.Properties['processPolicy']) {
        Assert-AiwExactFields $config.processPolicy @('schemaVersion','locator') 'PROCESS_POLICY_LOCATOR'
        if ([int]$config.processPolicy.schemaVersion -ne 3) { throw 'FORMAT_WRITE_REQUIRED|PROCESS_POLICY' }
        $policyLocator = ConvertTo-AiwSafeRelativePath ([string]$config.processPolicy.locator) 'PROCESS_POLICY_LOCATOR'
        if ($policyLocator -cne '.ai-workspace/process-policy.json') { throw 'PROCESS_POLICY_LOCATOR_CANONICAL' }
        $policyPath = if($EvaluationOnly-and$null-ne$ContentContext){$ContentContext.PolicyPath}else{Resolve-AiwChildFile $project $policyLocator 'PROCESS_POLICY'}
        $policyDoc = Read-AiwStrictJson $policyPath 'PROCESS_POLICY'
        $readTrace.Add([pscustomobject]@{sequence=$readTrace.Count;event='SOURCE_CARRIER_READ';path=$policyPath;identity=$policyDoc.Identity;observation='LIVE';authority=$false})
        $policyIdentity = $policyDoc.Identity
        $policy = $policyDoc.Value
        $policyFields=@('schemaVersion','contractVersion','projectId','rules')
        if($null-ne$policy.PSObject.Properties['facetVocabulary']){$policyFields+='facetVocabulary'}
        if($null-ne$policy.PSObject.Properties['qualityAssurance']){$policyFields+='qualityAssurance'}
        Assert-AiwExactFields $policy $policyFields 'PROCESS_POLICY'
        if ([int]$policy.schemaVersion -ne 3 -or [string]$policy.contractVersion -cne $script:ProcessCarrierContractVersion -or [string]$policy.projectId -cne $projectId -or -not ($policy.rules -is [Array])) { throw 'PROCESS_POLICY_VALUES' }
        Assert-AiwQualityPolicy $policy
        $currentPolicy=Read-AiwCurrentObject -ObjectType PROCESS_POLICY -Locator $policyPath -ExpectedIdentity $policyDoc.Identity -Context ([pscustomobject]@{ForbiddenPaths=@($ForbiddenPaths)})
        $policyRules = @($policy.rules)
        if($null-ne$policy.PSObject.Properties['facetVocabulary']){if($policy.facetVocabulary-isnot[Array]){throw 'PROCESS_POLICY_FACET_VOCABULARY'};$projectVocabulary=@($policy.facetVocabulary)}
    }
    $vocabulary=Get-AiwFacetVocabulary -NativeVocabulary @($catalog.facetVocabulary) -ProjectVocabulary $projectVocabulary
    if($null-ne$IntentEnvelope){
        if($IntentEnvelope.schemaVersion-ne2-or$null-eq$IntentEnvelope.PSObject.Properties['facets']){throw 'INTENT_SCHEMA_VERSION'}
        $intentFacets=ConvertTo-AiwIntentFacets -Facets $IntentEnvelope.facets -Vocabulary $vocabulary
        $intentOrigin='DECLARED_INTENT_ENVELOPE_2'
    }else{
        # Private prospective/legacy observations remain unclassified. Only the
        # public DISCOVER4 entrypoint may consume a declared execution intent.
        $unclassified=[ordered]@{};foreach($dimension in @('domain','workType','deliverableType','stage')){$unclassified[$dimension]=[pscustomobject]@{state='UNKNOWN';values=@()}}
        $intentFacets=[pscustomobject]$unclassified;$intentOrigin='UNCLASSIFIED_PRIVATE_OBSERVATION'
    }
    foreach($item in $records){if($null-ne$item.Record.selectors.PSObject.Properties['facets']){Assert-AiwFacetSelector -Facets $item.Record.selectors.facets -Vocabulary $vocabulary}}
    $declaredPolicyIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($rule in $policyRules) {
        $bodyFields=@($rule.PSObject.Properties.Name|Where-Object{$_-in@('effectiveRule','source')})
        if($bodyFields.Count-ne1){throw 'PROCESS_POLICY_RULE_BODY'}
        $ruleFields=@('ruleId','requirementReason','selectors','preparationRequirements','resultRequirements','decisionLocator',$bodyFields[0]);if($null-ne$rule.PSObject.Properties['qualityStages']){$ruleFields+='qualityStages'};Assert-AiwExactFields $rule $ruleFields 'PROCESS_POLICY_RULE'
        if ([string]$rule.ruleId -cnotmatch '^[A-Z][A-Z0-9_]*$'-or-not$declaredPolicyIds.Add([string]$rule.ruleId)) { throw 'PROCESS_POLICY_RULE_ID' }
        Assert-AiwSelectorContract $rule.selectors 'PROCESS_POLICY_SELECTORS'
        if($null-ne$rule.selectors.PSObject.Properties['facets']){Assert-AiwFacetSelector -Facets $rule.selectors.facets -Vocabulary $vocabulary}
        Assert-AiwStringArray $rule.preparationRequirements 'PROCESS_POLICY_PREPARATION'
        Assert-AiwStringArray $rule.resultRequirements 'PROCESS_POLICY_RESULT'
        foreach($field in @('requirementReason','decisionLocator')){if(-not($rule.$field-is[string])-or[string]::IsNullOrWhiteSpace([string]$rule.$field)){throw 'PROCESS_POLICY_TEXT'}}
        if($bodyFields[0]-ceq'effectiveRule'-and(-not($rule.effectiveRule-is[string])-or[string]::IsNullOrWhiteSpace([string]$rule.effectiveRule))){throw 'PROCESS_POLICY_TEXT'}
    }
    $readTrace.Add([pscustomobject]@{sequence=$readTrace.Count;event='GLOBAL_DECLARATIONS_VALIDATED';authority=$false})
    $readTrace.Add([pscustomobject]@{sequence=$readTrace.Count;event='SELECTION_STARTED';authority=$false})
    $selectionPlan=Get-AiwRuleSelectionPlan $catalog $records $policyRules $custom $projectId $Profile $Role $Phase $ActionKind $ResultKind $ExactPaths $Capabilities $Objective ([bool]$SemanticApplicabilityUnknown) $intentFacets
    $implementationIdentity=Get-AiwProcessImplementationIdentity -FrameworkRoot $framework -TargetVersion $TargetVersion -PackageObservation $runtimePackageObservation
    $agentsIdentity=Get-AiwProjectAgentsIdentity $project $ForbiddenPaths
    $declarationBindings=[ordered]@{projectConfigIdentity=$configDoc.Identity;controllerIdentity=$controllerIdentity;correctionsIdentity=$correctionsIdentity;policyIdentity=$policyIdentity;bootstrapManagedIdentity=$custom.ManagedIdentity;projectCustomIdentity=$custom.Identity;projectAgentsIdentity=$agentsIdentity;taskIdentity=$TaskIdentity;frameworkVersionIdentity=$versionDoc.Identity;releaseManifestIdentity=$releaseManifestIdentity;candidatePilotStateIdentity=$candidatePilotStateIdentity;nativeCatalogIdentity=$catalogDoc.Identity;implementationIdentity=$implementationIdentity}
    $ruleSelectionIdentity=Get-AiwContentDescriptorIdentity @($selectionPlan.ruleIds)
    if($BindingSnapshotOnly-and$null-ne$RuleObservation){
        Assert-AiwExactFields $RuleObservation @('schemaVersion','selectionIdentity','bindings','nativeFiles','projectDocuments') 'RULE_SOURCE_OBSERVATION'
        if($RuleObservation.schemaVersion-ne1-or$RuleObservation.selectionIdentity-cne$ruleSelectionIdentity){throw 'RULE_LOAD_REQUIRED|SELECTION_CHANGED'}
        foreach($name in $declarationBindings.Keys){
            if($name-cne'taskIdentity'-and$RuleObservation.bindings.$name-cne$declarationBindings[$name]){throw ('RULE_LOAD_REQUIRED|'+$name)}
        }
        $nativeFiles=@(foreach($module in @($catalog.requirements|Where-Object{$selectionPlan.matches[('framework:'+$_.requirementId)].Match}|ForEach-Object ownerModule|Sort-Object -Unique)){
            $path=Resolve-AiwChildFile $composerVersionDirectory $module 'NATIVE_REQUIREMENT_OWNER'
            Assert-AiwProjectStandardReadAllowed $project $path $ForbiddenPaths 'NATIVE_REQUIREMENT_OWNER'
            $identity=Get-AiwFileIdentity $path
            Assert-AiwCompositionPackageMember $runtimePackageObservation ('framework/versions/2.0.0/'+$module) $identity
            [pscustomobject]@{path=$path;identity=$identity}
        })
        if((Get-AiwContentDescriptorIdentity @($nativeFiles|Sort-Object path))-cne(Get-AiwContentDescriptorIdentity @($RuleObservation.nativeFiles|Sort-Object path))){throw 'RULE_LOAD_REQUIRED|NATIVE_SOURCE_CHANGED'}
        $contentOwner=(Get-Command New-AiwContentContext).Module
        $documents=@(& $contentOwner {param($p,$rules,$forbidden,$config,$policy)Get-CsRuleRawObservations $p $rules $forbidden $config $policy} $project $selectionPlan.policyRules $ForbiddenPaths $configDoc.Identity $policyIdentity)
        if((Get-AiwContentDescriptorIdentity @($documents|Sort-Object ruleId,sourceId))-cne(Get-AiwContentDescriptorIdentity @($RuleObservation.projectDocuments|Sort-Object ruleId,sourceId))){throw 'RULE_LOAD_REQUIRED|PROJECT_SOURCE_CHANGED'}
        $bindingFacts=Copy-AiwFormatValue $RuleObservation.bindings
        foreach($name in $declarationBindings.Keys){$bindingFacts.$name=$declarationBindings[$name]}
        return $bindingFacts
    }
    $scopedContent=Get-AiwScopedProjectContent $project $policyRules @($records|ForEach-Object{$_.Record}) $custom $selectionPlan $ForbiddenPaths $ContentContext $configDoc.Identity $policyIdentity ([bool]$ValidateCompleteAdoptedSet) $readTrace
    $projectStandards=$scopedContent.standards;$effectiveSet=$scopedContent.effective
    $readTrace.Add([pscustomobject]@{sequence=$readTrace.Count;event='SELECTED_CLOSURE_VERIFIED';identity=$effectiveSet.identity;authority=$false})
    $bindingFacts=[pscustomobject]@{
        projectConfigIdentity=$configDoc.Identity;controllerIdentity=$controllerIdentity;correctionsIdentity=$correctionsIdentity;policyIdentity=$policyIdentity
        bootstrapManagedIdentity=$custom.ManagedIdentity;projectCustomIdentity=$custom.Identity;projectAgentsIdentity=$agentsIdentity
        projectStandardsIdentity=$projectStandards.Identity;contentSnapshotIdentity=$projectStandards.Identity;effectiveSetIdentity=$effectiveSet.identity
        taskIdentity=$TaskIdentity;frameworkVersionIdentity=$versionDoc.Identity;releaseManifestIdentity=$releaseManifestIdentity
        candidatePilotStateIdentity=$candidatePilotStateIdentity;nativeCatalogIdentity=$catalogDoc.Identity;implementationIdentity=$implementationIdentity
    }
    if($BindingSnapshotOnly){
        # This boundary does not render a response, but still verifies the actual
        # selected native modules instead of relying on a whole-package scan.
        $bindingOwnerText=@{}
        foreach($requirement in $catalog.requirements){
            if(-not$selectionPlan.matches[('framework:'+$requirement.requirementId)].Match){continue}
            $null=Get-AiwNativeRuleBlock -VersionDirectory $composerVersionDirectory -OwnerModule $requirement.ownerModule -RequirementId $requirement.requirementId -ExactBlockLocator $requirement.exactBlockLocator -OwnerTextCache $bindingOwnerText -PackageObservation $runtimePackageObservation
        }
        return $bindingFacts
    }

    $selected = @(); $seenRequirement = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal); $ownerTextCache=@{};$selectionTrace=@($selectionPlan.trace);$legacySelectorDifferences=@()
    foreach ($requirement in @($catalog.requirements)) {
        $id='framework:'+[string]$requirement.requirementId
        if (-not $seenRequirement.Add($id)) { throw 'NATIVE_REQUIREMENT_ID' }
        $match=$selectionPlan.matches[$id]
        if ($match.Match) {
            $blockText=Get-AiwNativeRuleBlock -VersionDirectory $composerVersionDirectory -OwnerModule ([string]$requirement.ownerModule) -RequirementId ([string]$requirement.requirementId) -ExactBlockLocator ([string]$requirement.exactBlockLocator) -OwnerTextCache $ownerTextCache -ReadTrace $readTrace -PackageObservation $runtimePackageObservation
            $ownerBytes=$script:Utf8Strict.GetBytes([string]$ownerTextCache[[string]$requirement.ownerModule])
            $ownerIdentity=$ownerBytes.Length.ToString()+'|'+(Get-AiwSha256Hex $ownerBytes)
            $selected += [pscustomobject]@{requirementId=$id;source='FRAMEWORK';ownerModule=[string]$requirement.ownerModule;semanticApplicability=$match.Semantic;fullText=$blockText;preparationRequirements=@($requirement.preparationRequirements);resultRequirements=@($requirement.resultRequirements);selectorIdentity=(Get-AiwContentDescriptorIdentity $requirement.selectors);displayParts=@((New-AiwDisplayPart (Join-Path $composerVersionDirectory ([string]$requirement.ownerModule)) $ownerIdentity $blockText))}
        }
    }
    foreach ($item in $legacyEffective) {
        if ([int]$item.sourceSchemaVersion -eq 1) {
            $selected += [pscustomobject]@{requirementId=[string]$item.legacyRequirementId;source='PROJECT_CORRECTION';ownerModule='PROJECT_CORRECTIONS_V1';semanticApplicability='LEGACY_PROGRESSIVE_SELECTION_UNPROVEN';fullText=[string]$item.effectiveRule;preparationRequirements=@();resultRequirements=@();displayParts=@((New-AiwDisplayPart $correctionsPath $correctionsIdentity ([string]$item.effectiveRule)))}
        } else {
            $record=@($records|Where-Object{[string]$_.Alias-ceq[string]$item.legacyRequirementId})[0].Record
            $match=$selectionPlan.matches[[string]$item.legacyRequirementId]
            if($null-eq$record.selectors.PSObject.Properties['facets']-and@($record.selectors.semanticTerms).Count){$legacySelectorDifferences+=[ordered]@{requirementId=$item.legacyRequirementId;classification='UNCLASSIFIED_CONSERVATIVE';originalSelectors=$record.selectors;requiresProjectSemanticJudgment=$true}}
            if ($match.Match) {
                $prep=@($record.preparationRequirements)+@($record.requiredFacts)+@($record.mechanicalCheckRefs)
                $selected += [pscustomobject]@{requirementId=[string]$item.legacyRequirementId;source='PROJECT_CORRECTION';ownerModule='PROJECT_CORRECTIONS_V2';semanticApplicability=$match.Semantic;fullText=[string]$item.effectiveRule;preparationRequirements=@($prep|Sort-Object -Unique);resultRequirements=@($record.resultRequirements);selectorIdentity=(Get-AiwContentDescriptorIdentity $record.selectors);displayParts=@((New-AiwDisplayPart $correctionsPath $correctionsIdentity ([string]$item.effectiveRule)))}
            }
        }
    }
    foreach ($rule in $policyRules) {
        $id='project:'+$projectId+':'+[string]$rule.ruleId
        if ([string]$rule.ruleId -cnotmatch '^[A-Z][A-Z0-9_]*$' -or -not $seenRequirement.Add($id)) { throw 'PROCESS_POLICY_RULE_ID' }
        $sourceRule=if($null-ne$rule.PSObject.Properties['source']-and$selectionPlan.matches[$id].Match){$projectStandards.Rules[[string]$rule.ruleId]}else{$null}
        $match=$selectionPlan.matches[$id]
        if($null-eq$rule.selectors.PSObject.Properties['facets']-and@($rule.selectors.semanticTerms).Count){$legacySelectorDifferences+=[ordered]@{requirementId=$id;classification='UNCLASSIFIED_CONSERVATIVE';originalSelectors=$rule.selectors;requiresProjectSemanticJudgment=$true}}
        if($null-ne$sourceRule-and[bool]$sourceRule.Unavailable){if($match.Match){throw ('PROJECT_STANDARD_SOURCE_UNAVAILABLE|'+[string]$rule.ruleId+'|'+[string]$sourceRule.Error)}else{continue}}
        if($null-ne$sourceRule-and[bool]$sourceRule.Drift-and$match.Match){$match.Semantic='SOURCE_DRIFT_CONSERVATIVE_LOAD'}
        if ($match.Match) {
            # The machine result retains every complete body. Deduplication is
            # a projection of this result, never a mutation of its rule set.
            $parts=@()
            if($null-ne$sourceRule){foreach($part in @($sourceRule.Blocks)){$deps=if($null-ne$part.PSObject.Properties['OrderedDependencies']){@($part.OrderedDependencies)}else{@()};$parts+=New-AiwDisplayPart ([string]$part.SourcePath) ([string]$part.SourceIdentity) ([string]$part.Text) ([string]$part.Key) @($deps)}}
            else{$parts+=New-AiwDisplayPart $policyPath $policyIdentity ([string]$rule.effectiveRule)}
            $selected += [pscustomobject]@{requirementId=$id;source='PROJECT_POLICY';ownerModule=$(if($null-ne$sourceRule){'PROJECT_STANDARD_SOURCE'}else{'PROJECT_PROCESS_POLICY'});semanticApplicability=$match.Semantic;fullText=$(if($null-ne$sourceRule){[string]$sourceRule.FullText}else{[string]$rule.effectiveRule});preparationRequirements=@($rule.preparationRequirements);resultRequirements=@($rule.resultRequirements);selectorIdentity=(Get-AiwContentDescriptorIdentity $rule.selectors);displayParts=@($parts)}
        }
    }
    if ($custom.HasNormativeContent) {
        $selected += [pscustomobject]@{requirementId=('project-custom:'+$projectId);source='LEGACY_PROJECT_CUSTOM';ownerModule='BOOTSTRAP_PROJECT_CUSTOM';semanticApplicability='LEGACY_PROGRESSIVE_SELECTION_UNPROVEN';fullText=$custom.Text;preparationRequirements=@();resultRequirements=@();displayParts=@((New-AiwDisplayPart (Join-Path $project '.ai-workspace/BOOTSTRAP.md') $custom.Identity $custom.Text))}
    }
    if ($legacyConflicts.Count -gt 0) { throw 'PROJECT_CORRECTION_CONFLICT' }

    $sourceMaterial = @(
        "sourceScope=SELECTED_RULE_CLOSURE_V1",
        "framework=$TargetVersion",
        "composer=$ComposerVersion",
        "version=$($versionDoc.Identity)",
        "manifest=$releaseManifestIdentity",
        "candidatePilot=$candidatePilotStateIdentity",
        "catalog=$($catalogDoc.Identity)",
        "project=$($configDoc.Identity)",
        "controller=$controllerIdentity",
        "corrections=$correctionsIdentity",
        "policy=$policyIdentity",
        "projectStandards=$($projectStandards.Identity)",
        "effectiveSet=$($effectiveSet.identity)",
        "implementation=$implementationIdentity",
        "custom=$($custom.Identity)",
        "agents=$agentsIdentity",
        "task=$TaskIdentity",
        "actor=$Actor", "role=$Role", "phase=$Phase", "profile=$Profile",
        "capabilities=$([string]::Join(',',@($Capabilities|Sort-Object)))"
    ) -join "`n"
    $sourceKey=Get-AiwSha256Hex $script:Utf8Strict.GetBytes($sourceMaterial)
    $evidenceCeilings=@('SOURCE_VALIDATION_SELECTED_CLOSURE_V1')
    if($null-ne$runtimePackageObservation){$evidenceCeilings+='FIXED_ADOPTED_CONSUMED_MEMBERS'}
    if($candidatePilotStateIdentity-cne'MISSING'){$evidenceCeilings+='LOCAL_CANDIDATE_PILOT'}
    if(@($legacyEffective|Where-Object{[int]$_.sourceSchemaVersion-eq1}).Count-gt0){$evidenceCeilings+='LEGACY_CORRECTIONS_FULL_LOAD'}
    if($custom.HasNormativeContent){$evidenceCeilings+='LEGACY_PROJECT_CUSTOM_FULL_LOAD'}
    if([bool]$projectStandards.Drift){$evidenceCeilings+='PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD'}
    if(@($readTrace|Where-Object{$null-ne$_.PSObject.Properties['observation']-and$_.observation-ceq'PINNED_CACHE'}).Count){$evidenceCeilings+='PINNED_CACHE_SOURCE'}
    if($null-ne$PublicationMaterial){$PublicationMaterial.Value=Get-AiwSelectedPublicationMaterial $project $configDoc.Identity $selectionPlan.policyRules $projectStandards}
    # Capture the actual initial observations already used above. No extra
    # source read, previous coverage, retained body or recursive proof is built.
    $selectedPolicyIds=@($selectionPlan.policyRules|ForEach-Object ruleId)
    $sourceObservation=[pscustomobject]@{schemaVersion=1;selectionIdentity=$ruleSelectionIdentity;bindings=$bindingFacts;nativeFiles=@($readTrace|Where-Object event -CEQ 'NATIVE_MODULE_READ'|Select-Object path,identity);projectDocuments=@($readTrace|Where-Object{ $_.event-ceq'SOURCE_BODY_READ'-and$_.ruleId-cin$selectedPolicyIds}|Select-Object ruleId,sourceId,path,identity)}
    return [pscustomobject]@{
        status=$(if($candidateEvaluation){'EVALUATION_ONLY'}else{'PASS'}); projectId=$projectId; targetVersion=$TargetVersion; sourceCompositionIdentity=$sourceKey
        projectConfigIdentity=$configDoc.Identity; controllerIdentity=$controllerIdentity; correctionsIdentity=$correctionsIdentity; policyIdentity=$policyIdentity; bootstrapManagedIdentity=$custom.ManagedIdentity;projectCustomIdentity=$custom.Identity;projectAgentsIdentity=$agentsIdentity; projectStandardsIdentity=$projectStandards.Identity
        frameworkVersionIdentity=$versionDoc.Identity; releaseManifestIdentity=$releaseManifestIdentity; nativeCatalogIdentity=$catalogDoc.Identity
        contentSnapshotIdentity=$projectStandards.Identity;effectiveSetIdentity=$effectiveSet.identity;implementationIdentity=$implementationIdentity
        declaredCapabilities=@($Capabilities);sourceObservation=$sourceObservation
        facetVocabularyIdentity=$vocabulary.identity;intentFacets=$intentFacets;intentOrigin=$intentOrigin;selectionTrace=$selectionTrace;legacySelectorDifferences=$legacySelectorDifferences;readTrace=$readTrace.ToArray()
        candidatePilotStateIdentity=$candidatePilotStateIdentity
        stillEffective=@($legacyEffective); conflicts=@($legacyConflicts); inactive=@($inactiveCorrections)
        selectedRequirements=@($selected); selectedRulePackBytes=$selectedRulePackBytes; absoluteSelectedRulePackBytes=$script:AbsoluteSelectedRulePackBytes; evidenceCeilings=@($evidenceCeilings)
        sourceBuildCount=1; legacyCorrectionsFullReadCount=$(if(@($legacyEffective|Where-Object{[int]$_.sourceSchemaVersion-eq1}).Count-gt0){1}else{0}); legacyProjectCustomFullReadCount=$(if($custom.HasNormativeContent){1}else{0})
    }

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}

Export-ModuleMember -Function Get-AiwProcessSemanticText,Get-AiwProjectCustomRegion,Invoke-ProcessRequirementComposition,Get-AiwCanonicalCorrectionRecordIdentityV1,Get-AiwCanonicalCorrectionRecordIdentityV2,Get-AiwFileIdentity,Get-AiwProcessBindingSnapshot,Get-AiwProjectPolicySourceClosure,Get-AiwLocalCandidateSupportBinding
function Get-AiwDeliveryObservation {
    param([Parameter(Mandatory)]$Context)
    $fields=@('channel','stage','expectedRecipient','observedRecipient','outcome','evidence')
    foreach($optional in @('reviewPackageRef','reviewerAssignment','userDecisionRef')){if($null-ne$Context.PSObject.Properties[$optional]){$fields+=$optional}}
    Assert-AiwExactFields $Context $fields 'DELIVERY_CONTEXT'
    foreach($name in @('channel','stage','expectedRecipient','observedRecipient','outcome','evidence')){
        if($Context.$name-isnot[string]-or[string]::IsNullOrWhiteSpace($Context.$name)){throw 'DELIVERY_CONTEXT_TYPE'}
    }
    if($Context.channel-cnotin@('NATIVE_RESPONSE','TASK_MESSAGE')-or$Context.stage-cnotin@('PREPARE','OBSERVE')){throw 'DELIVERY_CONTEXT_VALUES'}
    if($Context.stage-ceq'PREPARE'){
        if($Context.outcome-cne'NOT_SENT'-or$Context.observedRecipient-cne'NOT_APPLICABLE'-or$Context.evidence-cne'NOT_APPLICABLE'){throw 'DELIVERY_FUTURE_EVIDENCE'}
        return [pscustomobject]@{status='READY_TO_SEND';delivered=$false;retryAllowed=$false;evidenceCeiling='PRE_SEND_ONLY'}
    }
    if($Context.channel-cne'TASK_MESSAGE'-or$Context.outcome-cnotin@('SUCCESS','FAILURE','UNKNOWN')){throw 'DELIVERY_OBSERVATION_VALUES'}
    if($Context.outcome-ceq'SUCCESS'){
        if($Context.expectedRecipient-cne$Context.observedRecipient-or$Context.evidence-ceq'NOT_APPLICABLE'){throw 'DELIVERY_SUCCESS_UNBOUND'}
        return [pscustomobject]@{status='DELIVERED';delivered=$true;retryAllowed=$false;evidenceCeiling='HOST_RESULT_CALLER_BOUND'}
    }
    return [pscustomobject]@{status=$(if($Context.outcome-ceq'FAILURE'){'NOT_DELIVERED'}else{'UNKNOWN'});delivered=$false;retryAllowed=$false;evidenceCeiling='HOST_RESULT_CALLER_BOUND'}
}
Export-ModuleMember -Function Get-AiwDeliveryObservation

function Expand-AiwProcessPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]*$')][string]$PresetId,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$DecisionLocator,
        [AllowEmptyCollection()][string[]]$ForbiddenPaths=@(),
        [AllowEmptyCollection()][string[]]$RuleIds=@()
    )
    # Expansion is data preparation only. The project owns the decision and the
    # policy write; the runtime continues to consume ordinary policy rules.
    if([string]::IsNullOrWhiteSpace($DecisionLocator)){throw 'PRESET_DECISION_REQUIRED'}
    $versionRoot=Split-Path -Parent $PSScriptRoot
    $presetPath=Resolve-AiwChildFile $versionRoot ('standards/presets/'+$PresetId+'.json') 'PRESET'
    $preset=(Read-AiwStrictJson $presetPath 'PRESET').Value
    Assert-AiwExactFields $preset @('schemaVersion','frameworkVersion','presetId','rules') 'PRESET'
    if(-not(Test-AiwJsonInteger $preset.schemaVersion)-or$preset.schemaVersion-ne1-or
        [string]$preset.frameworkVersion-cne$script:ProcessCarrierContractVersion-or
        [string]$preset.presetId-cne$PresetId-or$preset.rules-isnot[Array]-or$preset.rules.Count-eq0){throw 'PRESET_VALUES'}
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $selection=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($id in $RuleIds){if(-not$selection.Add($id)-or$id-cnotin@($preset.rules.ruleId)){throw 'PRESET_SELECTION'}}
    $expanded=[Collections.Generic.List[object]]::new()
    foreach($rule in $preset.rules){
        Assert-AiwExactFields $rule @('ruleId','requirementReason','selectors','preparationRequirements','resultRequirements','source') 'PRESET_RULE'
        if($rule.ruleId-isnot[string]-or$rule.ruleId-cnotmatch'^[A-Z][A-Z0-9_]*$'-or
            -not$ids.Add($rule.ruleId)-or$rule.requirementReason-isnot[string]-or
            [string]::IsNullOrWhiteSpace($rule.requirementReason)){throw 'PRESET_RULE_VALUES'}
        Assert-AiwSelectorContract $rule.selectors 'PRESET_SELECTORS'
        foreach($axis in @('preparationRequirements','resultRequirements')){
            Assert-AiwStringArray $rule.$axis ('PRESET_'+$axis)
            foreach($obligation in $rule.$axis){if($obligation-cnotmatch'^[A-Z][A-Z0-9_]*$'){throw 'PRESET_OBLIGATION'}}
        }
        if($selection.Count-gt0-and-not$selection.Contains($rule.ruleId)){continue}
        Assert-AiwExactFields $rule.source @('rootSourceId','documents') 'PRESET_SOURCE'
        if($rule.source.documents-isnot[Array]-or$rule.source.documents.Count-eq0){throw 'PRESET_SOURCE_DOCUMENTS'}
        foreach($document in $rule.source.documents){
            Assert-AiwExactFields $document @('sourceId','locator','mode','sectionStart','sectionEnd','dependencies') 'PRESET_DOCUMENT'
            if($document.locator-isnot[string]-or-not$document.locator.StartsWith('standards/software/',[StringComparison]::Ordinal)){throw 'PRESET_SOURCE_OUTSIDE_STANDARDS'}
            Assert-AiwProjectStandardReadAllowed -ProjectRoot $ProjectRoot -CandidatePath (Join-Path $versionRoot $document.locator) -ForbiddenPaths $ForbiddenPaths -Label PRESET_DOCUMENT
            $path=Resolve-AiwChildFile $versionRoot $document.locator 'PRESET_DOCUMENT'
            $resolved=Resolve-AiwProjectStandardFile -ProjectRoot $ProjectRoot -Locator $path -LocatorKind ABSOLUTE_FILE -Label PRESET_DOCUMENT -ForbiddenPaths $ForbiddenPaths
            $document.locator=$resolved.Path
            $document|Add-Member -NotePropertyName locatorKind -NotePropertyValue ABSOLUTE_FILE
            $document|Add-Member -NotePropertyName identity -NotePropertyValue (Get-AiwFileIdentity $resolved.Path)
        }
        $rule|Add-Member -NotePropertyName decisionLocator -NotePropertyValue $DecisionLocator
        $null=Get-AiwProjectSourceRule -ProjectRoot $ProjectRoot -Rule $rule -Label PRESET_EXPANDED -ForbiddenPaths $ForbiddenPaths
        $expanded.Add($rule)
    }
    return $expanded.ToArray()
}
Export-ModuleMember -Function Expand-AiwProcessPreset

function New-AiwProcessPresetPreparation {
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$PresetId,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$DecisionLocator,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$RuleIds,
        [Parameter(Mandatory)][hashtable]$Applicability,
        [string[]]$ForbiddenPaths=@()
    )
    $configDocument=Read-AiwStrictJson (Join-Path $ProjectRoot '.ai-workspace/project.json') 'PRESET_PROJECT'
    $config=$configDocument.Value
    if($config.schemaVersion-ne7-or$config.processPolicy.schemaVersion-ne3){throw 'PRESET_CURRENT_PROJECT_REQUIRED'}
    Assert-AiwSourceBindings $config.sourceBindings
    $rules=@(Expand-AiwProcessPreset -PresetId $PresetId -ProjectRoot $ProjectRoot -DecisionLocator $DecisionLocator -RuleIds $RuleIds -ForbiddenPaths $ForbiddenPaths)
    $required=@(Get-AiwLegacySourceBindings ([pscustomobject]@{rules=$rules}))
    $bindings=@(ConvertTo-Json -InputObject @($config.sourceBindings) -Depth 100|ConvertFrom-Json -Depth 100)
    $permissionChanges=@()
    foreach($binding in $required){
        $old=@($bindings|Where-Object{$_.id-ceq$binding.id})
        if($old.Count-gt1){throw 'PRESET_BINDING_CONFLICT'}
        if($old.Count-eq0){$bindings+=@($binding);$permissionChanges+=@([pscustomobject]@{bindingId=$binding.id;old='NOT_ADOPTED';proposed=$binding});continue}
        if($old[0].provider-cne$binding.provider-or(Get-AiwContentDescriptorIdentity $old[0].locator)-cne(Get-AiwContentDescriptorIdentity $binding.locator)){throw 'PRESET_BINDING_CONFLICT'}
        $before=$old[0]|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        foreach($scope in $binding.allowedPaths){
            $covered=@($old[0].allowedPaths|Where-Object{($_.kind-ceq'FILE'-and$_.locator-ceq$scope.locator)-or($_.kind-ceq'DIRECTORY'-and($_.locator-ceq'.'-or$scope.locator-ceq$_.locator-or$scope.locator.StartsWith($_.locator+'/',[StringComparison]::Ordinal)))})
            if($covered.Count-eq0){$old[0].allowedPaths+=@($scope)}
        }
        if((Get-AiwContentDescriptorIdentity $before)-cne(Get-AiwContentDescriptorIdentity $old[0])){$permissionChanges+=@([pscustomobject]@{bindingId=$binding.id;old=$before;proposed=$old[0]})}
    }
    Assert-AiwSourceBindings $bindings
    foreach($rule in $rules){
        if(-not$Applicability.ContainsKey([string]$rule.ruleId)){throw 'PRESET_APPLICABILITY_REQUIRED'}
        $facets=$Applicability[[string]$rule.ruleId]|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30
        Assert-AiwFacetSelector $facets
        $rule.selectors|Add-Member -NotePropertyName facets -NotePropertyValue $facets
        $rule.source=Convert-AiwLegacyPolicySource $rule.source $rule.ruleId $bindings
    }
    return [pscustomobject]@{rules=$rules;sourceBindings=$bindings;permissionChanges=$permissionChanges;decisionLocator=$DecisionLocator;projectId=$config.id;projectConfigIdentity=$configDocument.Identity;authority=$false;projectWritePerformed=$false}
}
Export-ModuleMember -Function New-AiwProcessPresetPreparation

# A prospective deletion stays denied throughout graph resolution and caches.
# The existing content composer still owns all source permissions and selection.
function New-AiwAdoptionContentContext {
    param([string]$ProjectRoot,[string]$ExpectedProjectConfigIdentity,[string[]]$ForbiddenPaths=@(),[string]$SourceProjectRoot,[object[]]$ProjectedSourceObjects=@())
    $files=@($ProjectedSourceObjects|Where-Object newExists)
    $contextForbidden=@($ForbiddenPaths)
    foreach($entry in @($ProjectedSourceObjects|Where-Object{-not$_.newExists})){
        if($entry.kind-cne'FILE'-or-not$SourceProjectRoot){throw 'SOURCE_DENIED|PROJECTED_DELETION'}
        if($entry.path-isnot[string]-or$entry.path-cmatch'(^/|^[A-Za-z]:|\\|(^|/)\.\.?(/|$)|:)'){throw 'SOURCE_DENIED|PROJECTED_DELETION_PATH'}
        $contextForbidden+=[IO.Path]::GetFullPath((Join-Path $SourceProjectRoot $entry.path))
        $contextForbidden+=[IO.Path]::GetFullPath((Join-Path $ProjectRoot $entry.path))
    }
    return New-AiwContentContext -ProjectRoot $ProjectRoot -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -ForbiddenPaths $contextForbidden -SourceProjectRoot $SourceProjectRoot -ProjectedSourceObjects $files
}
Export-ModuleMember -Function New-AiwAdoptionContentContext

# @design-contract TOOL_CONTRACT.md#项目来源配置的受限普通采用
# These artifacts are instruction-bound preparation, never a second authority.
function Get-AiwSourceChangeBinding($Receipt) {
    if($Receipt.schemaVersion-notin@(3,4)-or$Receipt.status-cne'PASS'-or$Receipt.mode-cne'DISCOVER'){throw 'SOURCE_CHANGE_ORIGINAL_DISCOVER_REQUIRED'}
    $binding=if($null-ne$Receipt.PSObject.Properties['binding']){$Receipt.binding}else{$Receipt.authorityContext}
    if($binding.contextType-cne'TASK'-or$binding.authorizationIdentity-ceq'NOT_REQUIRED'){throw 'SOURCE_CHANGE_CONTEXT'}
    if($Receipt.intentEnvelope.requestedActionKind-cne'CONTROL_WRITE'){
        if($Receipt.intentEnvelope.requestedActionKind-cne'SOURCE_WRITE'){throw 'SOURCE_CHANGE_CONTEXT'}
        $pkg=Read-AiwStrictJson $Receipt.sourceLocators.authorizationPackagePath 'SOURCE_PUBLICATION_PACKAGE'
        if($pkg.Identity-cne$binding.authorizationIdentity-or$null-eq$pkg.Value.PSObject.Properties['sourcePublicationBinding']-or$pkg.Value.sourcePublicationBinding.member-cne'SOURCE'){throw 'SOURCE_CHANGE_CONTEXT'}
    }
    return $binding
}

function Resolve-AiwSourceChangeEvidencePath([string]$Path,[string]$ProjectRoot,[string[]]$ForbiddenPaths=@()) {
    if(-not[IO.Path]::IsPathFullyQualified($Path)){throw 'SOURCE_CHANGE_REFERENCE'}
    $path=[IO.Path]::GetFullPath($Path);$prefix=[IO.Path]::GetFullPath((Join-Path $ProjectRoot '.ai-workspace'))+[IO.Path]::DirectorySeparatorChar
    if(-not$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_CHANGE_EVIDENCE_SCOPE'}
    Assert-AiwProjectStandardReadAllowed $ProjectRoot $path $ForbiddenPaths 'SOURCE_CHANGE_EVIDENCE'
    $relative=[IO.Path]::GetRelativePath($ProjectRoot,$path).Replace('\','/')
    return Resolve-AiwChildFile $ProjectRoot $relative 'SOURCE_CHANGE_EVIDENCE'
}

function Read-AiwSourceChangeEvidence($Reference,[string]$ProjectRoot,[string[]]$ForbiddenPaths=@()) {
    Assert-AiwExactFields $Reference @('path','identity') 'SOURCE_CHANGE_REFERENCE'
    if($Reference.path-isnot[string]-or$Reference.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'SOURCE_CHANGE_REFERENCE'}
    $path=Resolve-AiwSourceChangeEvidencePath $Reference.path $ProjectRoot $ForbiddenPaths
    if((Get-AiwFileIdentity $path)-cne$Reference.identity){throw 'SOURCE_CHANGE_EVIDENCE_DRIFT'}
    return $path
}

function Get-AiwProjectSourcePermissionChanges($OriginalConfig,$TargetConfig,$Package) {
    foreach($value in @($OriginalConfig,$TargetConfig)){
        Assert-AiwCurrentObjectValue PROJECT_CONFIG $value
        if($value.schemaVersion-ne7-or$value.frameworkVersion-cne'2.0.0'-or$value.processPolicy.schemaVersion-ne3-or$value.processPolicy.locator-cne'.ai-workspace/process-policy.json'){throw 'SOURCE_CHANGE_CURRENT_FORMAT_REQUIRED'}
        $null=Assert-AiwFrameworkCapabilities $value.frameworkCapabilities
    }
    $old=Copy-AiwFormatValue $OriginalConfig;$new=Copy-AiwFormatValue $TargetConfig
    $changes=[ordered]@{sourceBindings=@();knowledgeSources=@()}
    foreach($id in @(@($old.sourceBindings|ForEach-Object id)+@($new.sourceBindings|ForEach-Object id)|Sort-Object -Unique -CaseSensitive)){
        $before=@($old.sourceBindings|Where-Object id -CEQ $id);$after=@($new.sourceBindings|Where-Object id -CEQ $id)
        if((ConvertTo-AiwContentCanonicalJson @($before))-cne(ConvertTo-AiwContentCanonicalJson @($after))){$changes.sourceBindings+=,[pscustomobject]@{id=$id;before=@($before);after=@($after)}}
    }
    $old.sourceBindings=@();$new.sourceBindings=@()
    $oldKnowledge=$old.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE'];$newKnowledge=$new.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']
    $firstEnable=$null-ne$newKnowledge-and$newKnowledge.Value.enabled-eq$true-and($null-eq$oldKnowledge-or$oldKnowledge.Value.enabled-eq$false)
    if($firstEnable-and$Package.issuerRole-cne'PROJECT_CONTROLLER'){throw 'SOURCE_CHANGE_CAPABILITY_CONTROLLER_REQUIRED'}
    if($null-ne$newKnowledge-and$newKnowledge.Value.enabled-eq$true-and($firstEnable-or($null-ne$oldKnowledge-and$oldKnowledge.Value.enabled-eq$true))){
        $oldSources=if($null-eq$oldKnowledge){@()}else{@($oldKnowledge.Value.sources)}
        foreach($id in @(@($oldSources|ForEach-Object id)+@($newKnowledge.Value.sources|ForEach-Object id)|Sort-Object -Unique -CaseSensitive)){
            $before=@($oldSources|Where-Object id -CEQ $id);$after=@($newKnowledge.Value.sources|Where-Object id -CEQ $id)
            if((ConvertTo-AiwContentCanonicalJson @($before))-cne(ConvertTo-AiwContentCanonicalJson @($after))){$changes.knowledgeSources+=,[pscustomobject]@{id=$id;before=@($before);after=@($after)}}
        }
        # Exact carrier bytes bind the optional first-enable decision. Only
        # this capability may be added/enabled; disabling and other drift
        # remain visible to the whole-config comparison below.
        $old.frameworkCapabilities.PSObject.Properties.Remove('KNOWLEDGE_REFERENCE')
        $new.frameworkCapabilities.PSObject.Properties.Remove('KNOWLEDGE_REFERENCE')
    }
    if((ConvertTo-AiwContentCanonicalJson $old)-cne(ConvertTo-AiwContentCanonicalJson $new)){throw 'SOURCE_CHANGE_CONFIG_FIELDS'}
    return [pscustomobject]$changes
}

function Assert-AiwSourceChangeOriginalContext($Receipt) {
    $binding=Get-AiwSourceChangeBinding $Receipt
    $packageDocument=Read-AiwStrictJson $Receipt.sourceLocators.authorizationPackagePath 'SOURCE_CHANGE_PACKAGE';$package=$packageDocument.Value
    $paths=@('.ai-workspace/process-policy.json','.ai-workspace/project.json')
    if($packageDocument.Identity-cne$binding.authorizationIdentity-or$package.schemaVersion-notin@(1,2)-or($package.schemaVersion-eq2-and$package.repositoryId-cne'CONTROL')-or@($package.actions).Count-ne1-or$package.actions[0]-cne'CONTROL_WRITE'-or$null-ne$package.PSObject.Properties['continuationPlan']-or$null-ne$package.PSObject.Properties['transitionPlan']){throw 'SOURCE_CHANGE_PACKAGE_BOUNDARY'}
    foreach($scope in @(@{paths=$binding.exactScope},@{paths=$package.exactPaths})){
        if(@($scope.paths).Count-lt1-or@($scope.paths).Count-gt2-or@($scope.paths|Select-Object -Unique).Count-ne@($scope.paths).Count-or@($scope.paths|Where-Object{$_-cnotin$paths}).Count){throw 'SOURCE_CHANGE_EXACT_SCOPE'}
    }
    if($package.grantee-cne$binding.actor-or$package.owner-cne$binding.taskOwner-or$package.taskId-cne$binding.taskId-or$package.taskIdentity-cne$binding.taskIdentity-or$package.userConfirmation-cne$binding.userDecision-or$package.projectConfigIdentity-cne$Receipt.sourceBindings.projectConfigIdentity){throw 'SOURCE_CHANGE_PACKAGE_CONTEXT'}
    Assert-AiwSourceChangeStaticContext $Receipt
    return $package
}
function Assert-AiwSourceChangeStaticContext($Receipt) {
    $binding=Get-AiwSourceChangeBinding $Receipt
    # No source, dependency or content cache is touched until the immutable
    # control and tool facts have been checked against the original DISCOVER.
    $project=$binding.projectRoot;$framework=$Receipt.sourceLocators.frameworkRoot
    $static=@{controllerIdentity='.ai-workspace/controller.json';correctionsIdentity='.ai-workspace/corrections.json';taskIdentity=$Receipt.sourceLocators.taskRelativePath;candidatePilotStateIdentity='.ai-workspace/upgrade-recovery/2.0.0/state.json'}
    foreach($name in $static.Keys){
        # Stable DISCOVER deliberately has no candidate-pilot binding. A
        # missing optional state may also have missing intermediate parents.
        if($name-ceq'candidatePilotStateIdentity'-and$Receipt.sourceBindings.$name-ceq'MISSING'){continue}
        $path=Resolve-AiwChildFile $project $static[$name] 'SOURCE_CHANGE_STATIC' -AllowMissing
        $identity=if($null-eq$path){'MISSING'}else{Get-AiwFileIdentity $path}
        if($identity-cne$Receipt.sourceBindings.$name){throw ('SOURCE_CHANGE_STATIC_DRIFT|'+$name)}
    }
    foreach($entry in @(@('frameworkVersionIdentity','VERSION.json'),@('releaseManifestIdentity','RELEASE_MANIFEST.json'),@('nativeCatalogIdentity','PROCESS_REQUIREMENTS.json'))){
        $path=Resolve-AiwChildFile $framework ('framework/versions/2.0.0/'+$entry[1]) 'SOURCE_CHANGE_TOOL'
        if((Get-AiwFileIdentity $path)-cne$Receipt.sourceBindings.($entry[0])){throw ('SOURCE_CHANGE_STATIC_DRIFT|'+$entry[0])}
    }
    $custom=Get-AiwProjectCustomRegion (Resolve-AiwChildFile $project '.ai-workspace/BOOTSTRAP.md' 'SOURCE_CHANGE_BOOTSTRAP')
    if($custom.ManagedIdentity-cne$Receipt.sourceBindings.bootstrapManagedIdentity-or$custom.Identity-cne$Receipt.sourceBindings.projectCustomIdentity-or(Get-AiwProjectAgentsIdentity $project @($binding.forbiddenScope))-cne$Receipt.sourceBindings.projectAgentsIdentity-or(Get-AiwProcessImplementationIdentity $framework '2.0.0')-cne$Receipt.sourceBindings.implementationIdentity){throw 'SOURCE_CHANGE_STATIC_DRIFT'}
    $runtimeStateModule=Join-Path $framework 'scripts/ProjectAdoptionState.psm1'
    if(Test-Path -LiteralPath $runtimeStateModule -PathType Leaf){
        $stateModule=@(Import-Module $runtimeStateModule -PassThru -ErrorAction Stop)[0]
        $adopted=& $stateModule.ExportedCommands['Get-AiwAdoptedDistributionBinding'] $project '2.0.0'
        if($null-ne$adopted){$null=& $stateModule {param($p,$r) Assert-AiwAdoptedRuntimeDeclaration $p $r '2.0.0'} $project $framework}
    }
}

function Get-AiwSourceChangeRootTools([string]$FrameworkRoot) {
    return @(foreach($relative in @('scripts/ProjectAdoptionTransaction.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/ProjectAdoptionState.psm1','scripts/resolve-framework-maintenance-process-requirements.ps1','scripts/resolve-framework-maintenance-target.ps1','scripts/check-framework-maintenance-authorization.ps1','scripts/MaintenanceOverlay.psm1','scripts/upgrade-project.ps1','framework/versions/2.0.0/scripts/ProjectSourcePublication.psm1','framework/versions/2.0.0/scripts/AuthorizationCheck.psm1','framework/versions/2.0.0/scripts/ProcessRequirementBoundary.psm1')){
        $path=Resolve-AiwChildFile $FrameworkRoot $relative 'SOURCE_CHANGE_ROOT_TOOL' -AllowMissing
        [pscustomobject]@{path=$relative;identity=$(if($null-eq$path){'MISSING'}else{Get-AiwFileIdentity $path})}
    })
}
Export-ModuleMember -Function Get-AiwSourceChangeRootTools

function Get-AiwSourceChangeSelectionIdentity([object[]]$Requirements) {
    # Display locators for projected carrier bytes are temporary evidence
    # locations. Source snapshots already bind physical sources; the selection
    # binds complete bodies and obligations independently of those locations.
    $material=@(foreach($rule in $Requirements){
        [ordered]@{requirementId=$rule.requirementId;source=$rule.source;ownerModule=$rule.ownerModule;semanticApplicability=$rule.semanticApplicability;fullText=$rule.fullText;preparationRequirements=@($rule.preparationRequirements);resultRequirements=@($rule.resultRequirements)}
    })
    return Get-AiwContentDescriptorIdentity $material
}
Export-ModuleMember -Function Get-AiwSourceChangeSelectionIdentity

function Remove-AiwSourceProjectionCache([string]$Projection){
    # This namespace belongs to this freshly created projection, never to the
    # caller's mutable Context. Git scratch must already have been released.
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Projection))
    $temporary=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    if([IO.Path]::GetDirectoryName($root)-cne$temporary-or[IO.Path]::GetFileName($root)-cnotmatch'^aiw-source-change-[a-f0-9]{32}$'){throw 'SOURCE_PROJECTION_CLEANUP_SCOPE'}
    $control=Join-Path $root '.ai-workspace';$runtime=Join-Path $control 'runtime'
    foreach($path in @($root,$control,$runtime)){
        if(-not[IO.Directory]::Exists($path)){return}
        if([IO.File]::GetAttributes($path)-band[IO.FileAttributes]::ReparsePoint){throw 'SOURCE_PROJECTION_CLEANUP_REPARSE'}
    }
    foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($runtime)){
        if([IO.Path]::GetFileName($entry)-cne'content-sources'){continue}
        $cache=[IO.Path]::GetFullPath($entry)
        if(-not$cache.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or([IO.File]::GetAttributes($cache)-band[IO.FileAttributes]::ReparsePoint)-or-not[IO.Directory]::Exists($cache)){throw 'SOURCE_PROJECTION_CACHE_OWNER'}
        $files=@([IO.Directory]::EnumerateFileSystemEntries($cache))
        foreach($file in $files){$attributes=[IO.File]::GetAttributes($file);if(($attributes-band([IO.FileAttributes]::Directory-bor[IO.FileAttributes]::ReparsePoint))-or[IO.Path]::GetFileName($file)-cnotmatch'^[A-Fa-f0-9]{64}\.bin$'){throw 'SOURCE_PROJECTION_CACHE_UNKNOWN_RESOURCE'}}
        foreach($file in $files){[IO.File]::Delete($file)}
        [IO.Directory]::Delete($cache)
    }
    if(@([IO.Directory]::EnumerateFileSystemEntries($runtime)).Count-eq0){[IO.Directory]::Delete($runtime)}
}
function Get-AiwSourceChangeTarget($Receipt,$ConfigDocument,$PolicyDocument,[object[]]$ProjectedSourceObjects=@()) {
    $binding=Get-AiwSourceChangeBinding $Receipt;$project=$binding.projectRoot
    # Only two already validated carrier bytes enter this temporary projection.
    # All source document reads continue to resolve in the original project.
    $temporaryRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $projection=[IO.Path]::GetFullPath((Join-Path $temporaryRoot ('aiw-source-change-'+[guid]::NewGuid().ToString('N'))))
    if(-not$projection.StartsWith($temporaryRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SOURCE_CHANGE_PROJECTION_PATH'}
    $control=Join-Path $projection '.ai-workspace';$null=[IO.Directory]::CreateDirectory($control)
    $files=@((Join-Path $control 'project.json'),(Join-Path $control 'process-policy.json'))
    $sourceDirectories=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $projectionFailure=$null
    try{
        [IO.File]::WriteAllText($files[0],$ConfigDocument.Text,$script:Utf8Strict)
        [IO.File]::WriteAllText($files[1],$PolicyDocument.Text,$script:Utf8Strict)
        foreach($object in $ProjectedSourceObjects){
            if($object.kind-cne'FILE'-or-not$object.newExists){throw 'SOURCE_PUBLICATION_TARGET_PROJECTION'}
            $relative=ConvertTo-AiwSafeRelativePath $object.path 'SOURCE_PUBLICATION_TARGET'
            $file=Join-Path $projection $relative;$parent=[IO.Path]::GetDirectoryName($file)
            $walk=$parent;while($walk-cne$projection){$null=$sourceDirectories.Add($walk);$walk=[IO.Path]::GetDirectoryName($walk)}
            $null=[IO.Directory]::CreateDirectory($parent)
            [IO.File]::WriteAllBytes($file,[Convert]::FromBase64String($object.newBase64));$files+=,$file
        }
        $forbidden=@($binding.forbiddenScope)+@($binding.protectedScope)+@($ConfigDocument.Value.routineExcludedPaths)
        # Keep relative scopes so the constructor guards both projection roots.
        $context=New-AiwContentContext -ProjectRoot $projection -ExpectedProjectConfigIdentity $ConfigDocument.Identity -ForbiddenPaths $forbidden -SourceProjectRoot $project -ProjectedSourceObjects $ProjectedSourceObjects
        $targetScope=$script:PublicationTargetStandards
        $previousContext=if($null-ne$targetScope){$targetScope.context}else{$null}
        if($null-ne$targetScope){$targetScope.context=$context}
        try{
        $composition=Invoke-ProcessRequirementComposition -ProjectRoot $project -FrameworkRoot $Receipt.sourceLocators.frameworkRoot -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity $ConfigDocument.Identity -ExpectedCorrectionsIdentity $Receipt.sourceBindings.correctionsIdentity -Profile $binding.profile -Role $binding.role -Phase $binding.phase -Actor $binding.actor -TaskIdentity $binding.taskIdentity -UseDeclaredCapabilities -IntentEnvelope $Receipt.intentEnvelope -Objective (Get-AiwProcessSemanticText $Receipt.intentEnvelope) -ActionKind $Receipt.intentEnvelope.requestedActionKind -ResultKind $Receipt.intentEnvelope.requestedResultKind -ExactPaths @($binding.exactScope) -ForbiddenPaths @($binding.forbiddenScope) -EvaluationOnly -ContentContext $context -ValidateCompleteAdoptedSet
        }finally{if($null-ne$targetScope){$targetScope.context=$previousContext}}
        if('PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD'-cin@($composition.evidenceCeilings)){throw 'SOURCE_CHANGE_TARGET_SOURCE_DRIFT'}
        # Knowledge remains reference-only: validate descriptors/permissions;
        # adopting the declaration does not query every index or read methods.
        $knowledge=$ConfigDocument.Value.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']
        if($null-ne$knowledge-and$knowledge.Value.enabled){
            foreach($source in @($knowledge.Value.sources)){
                if($null-ne$source.PSObject.Properties['bindingId']){
                    $matches=@($ConfigDocument.Value.sourceBindings|Where-Object id -CEQ $source.bindingId)
                    if($matches.Count-ne1){throw 'SOURCE_CHANGE_KNOWLEDGE_BINDING'}
                    $allowed=@($matches[0].allowedPaths|Where-Object{($_.kind-ceq'FILE'-and$_.locator-ceq$source.indexLocator)-or($_.kind-ceq'DIRECTORY'-and($_.locator-ceq'.'-or$source.indexLocator.StartsWith($_.locator+'/',[StringComparison]::Ordinal)))})
                    if($allowed.Count-eq0){throw 'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS'}
                    if($matches[0].provider-ceq'LOCAL_DIRECTORY'){
                        $root=$matches[0].locator.root;if(-not[IO.Path]::IsPathFullyQualified($root)){$root=Join-Path $project $root}
                        Assert-AiwProjectStandardReadAllowed $project (Join-Path $root $source.indexLocator) $forbidden 'SOURCE_CHANGE_KNOWLEDGE'
                    }
                }else{
                    $root=if($source.root.kind-ceq'PROJECT'){$project}else{$source.root.locator}
                    Assert-AiwProjectStandardReadAllowed $project (Join-Path $root $source.indexLocator) $forbidden 'SOURCE_CHANGE_KNOWLEDGE'
                }
            }
        }
        foreach($rule in $composition.selectedRequirements){foreach($part in $rule.displayParts){if($part.sourceLocator-ceq$files[1]){$part.sourceLocator=$PolicyDocument.Path}}}
        $target=[pscustomobject]@{projectConfigIdentity=$ConfigDocument.Identity;policyIdentity=$PolicyDocument.Identity;projectStandardsIdentity=$composition.projectStandardsIdentity;contentSnapshotIdentity=$composition.contentSnapshotIdentity;effectiveSetIdentity=$composition.effectiveSetIdentity;selectedRulesIdentity=(Get-AiwSourceChangeSelectionIdentity @($composition.selectedRequirements))}
        return [pscustomobject]@{binding=$target;composition=$composition}
    }catch{$projectionFailure=$_;throw}finally{
      try{
        # Exact known children only; no recursive deletion or source cleanup.
        foreach($file in $files){if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
        Remove-AiwSourceProjectionCache $projection
        foreach($directory in @($sourceDirectories|Sort-Object Length -Descending)){if([IO.Directory]::Exists($directory)){[IO.Directory]::Delete($directory)}}
        if([IO.Directory]::Exists($control)){[IO.Directory]::Delete($control)}
        if([IO.Directory]::Exists($projection)){[IO.Directory]::Delete($projection)}
      }catch{if($null-ne$projectionFailure){$projectionFailure.Exception.Data['SourceProjectionCleanupFailure']=$_.Exception.Message}else{throw}}
    }
}

function Get-AiwProjectSourceChange {
    [CmdletBinding()]param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Boundary,[ValidateSet('ADMIT','FINALIZE','RECOVERY')][string]$Stage,[switch]$Rollback)
    Get-AiwProjectSourceChangeCore @PSBoundParameters
}
function Get-AiwProjectSourceChangeCore {
    param($Receipt,$Boundary,[string]$Stage,[switch]$Rollback,$PublicationContext=$null)
# @project-source-scope
$binding=if($null-ne$Receipt.PSObject.Properties['binding']){$Receipt.binding}else{$Receipt.authorityContext}
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $binding.projectRoot -Mode OBSERVE
try {

    $tokens=@($Boundary.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_CHANGE|*'})
    if($Receipt.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){
        $observedPackage=Read-AiwStrictJson $Receipt.sourceLocators.authorizationPackagePath 'SOURCE_PUBLICATION_PACKAGE'
        if($null-ne$observedPackage.Value.PSObject.Properties['sourcePublicationBinding']){
            if($tokens.Count-ne1-or$tokens[0]-cnotmatch'^PROJECT_SOURCE_CHANGE\|([^|]+)\|(\d+\|[A-F0-9]{64})$'){throw 'SOURCE_PUBLICATION_COMMON_PREPARATION_REQUIRED'}
            $reference=[pscustomobject]@{path=$Matches[1];identity=$Matches[2]}
            if($null-ne$PublicationContext){
                $capture=[ref]$null
                $result=Get-AiwPublicationCandidateCore $Receipt $Boundary $reference $Stage -Rollback:$Rollback -VerifiedFacts $PublicationContext.facts -VerifiedTargets $PublicationContext.targets -TargetsCapture $capture
                $PublicationContext.targets=$capture.Value
                return $result
            }
            return Get-AiwProjectSourcePublicationCandidate -Receipt $Receipt -Boundary $Boundary -Reference $reference -Stage $Stage -Rollback:$Rollback
        }
    }
    if($tokens.Count-eq0){
        if($Receipt.intentEnvelope.requestedActionKind-ceq'CONTROL_WRITE'-and'.ai-workspace/project.json'-cin@($binding.exactScope)){
            # Core adoption still delegates its original old-state ADMIT to
            # this resolver. Its root consumer validates ADOPTION_TARGET_RULES
            # and the full transaction separately. Such an admission produces
            # no projectSourcePreparation and cannot finalize/recover a daily
            # source change, even if a caller merely copies that marker.
            $rootPreparation=@($Boundary.preparationReceipts|Where-Object{$_-cmatch'^ADOPTION_TARGET_RULES_LOADED\|\d+\|[A-F0-9]{64}$'})
            $dailyPair=@($binding.exactScope).Count-eq2-and'.ai-workspace/process-policy.json'-cin@($binding.exactScope)
            if($Stage-cne'ADMIT'-or($dailyPair-and$rootPreparation.Count-ne1)){throw 'SOURCE_CHANGE_PREPARATION_REQUIRED'}
        }
        return $null
    }
    $binding=Get-AiwSourceChangeBinding $Receipt
    if($tokens.Count-ne1-or$tokens[0]-cnotmatch'^PROJECT_SOURCE_CHANGE\|([^|]+)\|(\d+\|[A-F0-9]{64})$'){throw 'SOURCE_CHANGE_PREPARATION_REFERENCE'}
    $reference=[pscustomobject]@{path=$Matches[1];identity=$Matches[2]}
    $candidatePath=Read-AiwSourceChangeEvidence $reference $binding.projectRoot @($binding.forbiddenScope)
    $candidate=(Read-AiwStrictJson $candidatePath 'SOURCE_CHANGE_CANDIDATE').Value
    Assert-AiwExactFields $candidate @('schemaVersion','kind','discoverReceiptIdentity','authorizationIdentity','userDecision','decisionRef','objects','permissionChanges','rootToolDependencies','target') 'SOURCE_CHANGE_CANDIDATE'
    if(-not(Test-AiwJsonInteger $candidate.schemaVersion)-or$candidate.schemaVersion-ne1-or$candidate.kind-cne'PROJECT_SOURCE_CHANGE'-or$candidate.discoverReceiptIdentity-cne$Boundary.expectedDiscoverReceiptIdentity-or$candidate.authorizationIdentity-cne$binding.authorizationIdentity-or$candidate.userDecision-cne$binding.userDecision){throw 'SOURCE_CHANGE_CANDIDATE_BINDING'}
    $null=Read-AiwSourceChangeEvidence $candidate.decisionRef $binding.projectRoot @($binding.forbiddenScope)
    $package=Assert-AiwSourceChangeOriginalContext $Receipt
    if((ConvertTo-AiwContentCanonicalJson @(Get-AiwSourceChangeRootTools $Receipt.sourceLocators.frameworkRoot))-cne(ConvertTo-AiwContentCanonicalJson @($candidate.rootToolDependencies))){throw 'SOURCE_CHANGE_ROOT_TOOL_DRIFT'}
    $paths=@('.ai-workspace/process-policy.json','.ai-workspace/project.json')
    if($candidate.objects-isnot[Array]-or$candidate.objects.Count-ne2-or[string]::Join('|',@($candidate.objects.path))-cne[string]::Join('|',$paths)){throw 'SOURCE_CHANGE_OBJECT_ORDER'}
    $writePaths=@($candidate.objects|Where-Object{$_.preimage.identity-cne$_.postimage.identity}|ForEach-Object path)
    if($writePaths.Count-eq0-or[string]::Join('|',@($package.exactPaths|Sort-Object -CaseSensitive))-cne[string]::Join('|',@($writePaths|Sort-Object -CaseSensitive))-or@($package.objectIdentities).Count-ne$writePaths.Count){throw 'SOURCE_CHANGE_ACTUAL_WRITE_SCOPE'}
    $documents=@{};$states=@()
    foreach($entry in $candidate.objects){
        Assert-AiwExactFields $entry @('path','preimage','postimage') 'SOURCE_CHANGE_OBJECT'
        $authorized=@($package.objectIdentities|Where-Object path -CEQ $entry.path)
        if($entry.path-cin$writePaths){
            if($authorized.Count-ne1-or$authorized[0].identity-cne$entry.preimage.identity){throw 'SOURCE_CHANGE_PREIMAGE_NOT_AUTHORIZED'}
        }elseif($authorized.Count){throw 'SOURCE_CHANGE_NOOP_WRITE_DENIED'}
        foreach($side in @('preimage','postimage')){
            $path=Read-AiwSourceChangeEvidence $entry.$side $binding.projectRoot @($binding.forbiddenScope)
            $document=Read-AiwStrictJson $path 'SOURCE_CHANGE_CARRIER'
            $type=if($entry.path-ceq'.ai-workspace/project.json'){'PROJECT_CONFIG'}else{'PROCESS_POLICY'}
            Assert-AiwCurrentObjectValue $type $document.Value
            $documents[$entry.path+'|'+$side]=$document
        }
        $live=Get-AiwFileIdentity (Resolve-AiwChildFile $binding.projectRoot $entry.path 'SOURCE_CHANGE_LIVE')
        if($live-cne$entry.preimage.identity-and$live-cne$entry.postimage.identity){throw 'SOURCE_CHANGE_THIRD_PARTY_OBJECT'}
        $states+=,[pscustomobject]@{old=($live-ceq$entry.preimage.identity);new=($live-ceq$entry.postimage.identity)}
    }
    if($Stage-ceq'ADMIT'-and@($states|Where-Object{-not$_.old}).Count){throw 'SOURCE_CHANGE_PRE_ADMIT_DRIFT'}
    if($Stage-ceq'FINALIZE'-and-not$Rollback-and@($states|Where-Object{-not$_.new}).Count){throw 'SOURCE_CHANGE_FINAL_POSTIMAGE_REQUIRED'}
    if($Rollback-and$Stage-ceq'FINALIZE'-and@($states|Where-Object{-not$_.old}).Count){throw 'SOURCE_CHANGE_ROLLBACK_PREIMAGE_REQUIRED'}
    if(-not$states[0].new-and-not$states[1].old){throw 'SOURCE_CHANGE_UNREACHABLE_GROUP'}
    $oldConfig=$documents['.ai-workspace/project.json|preimage'];$newConfig=$documents['.ai-workspace/project.json|postimage'];$newPolicy=$documents['.ai-workspace/process-policy.json|postimage']
    if($oldConfig.Identity-cne$Receipt.sourceBindings.projectConfigIdentity-or$documents['.ai-workspace/process-policy.json|preimage'].Identity-cne$Receipt.sourceBindings.policyIdentity){throw 'SOURCE_CHANGE_ORIGINAL_BINDING'}
    if($newPolicy.Value.schemaVersion-ne3-or$newPolicy.Value.projectId-cne$oldConfig.Value.id-or$newPolicy.Value.contractVersion-cne'2.0.0'){throw 'SOURCE_CHANGE_POLICY_FORMAT'}
    $changes=Get-AiwProjectSourcePermissionChanges $oldConfig.Value $newConfig.Value $package
    if((ConvertTo-AiwContentCanonicalJson $changes)-cne(ConvertTo-AiwContentCanonicalJson $candidate.permissionChanges)){throw 'SOURCE_CHANGE_PERMISSION_DECISION_DRIFT'}
    $admission=$null
    if($Stage-cne'ADMIT'){
        $proofs=@($Boundary.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_ADMISSION|*'})
        if($proofs.Count-ne1-or$proofs[0]-cnotmatch'^PROJECT_SOURCE_ADMISSION\|([^|]+)\|(\d+\|[A-F0-9]{64})\|([^|]+)\|(\d+\|[A-F0-9]{64})$'){throw 'SOURCE_CHANGE_ORIGINAL_ADMISSION_REQUIRED'}
        $inputRef=[pscustomobject]@{path=$Matches[1];identity=$Matches[2]};$resultRef=[pscustomobject]@{path=$Matches[3];identity=$Matches[4]}
        $admit=(Read-AiwStrictJson (Read-AiwSourceChangeEvidence $inputRef $binding.projectRoot @($binding.forbiddenScope)) 'SOURCE_CHANGE_ADMIT').Value
        $result=(Read-AiwStrictJson (Read-AiwSourceChangeEvidence $resultRef $binding.projectRoot @($binding.forbiddenScope)) 'SOURCE_CHANGE_ADMIT_RESULT').Value
        if($admit.schemaVersion-ne3-or$admit.mode-cne'ADMIT_ACTION'-or$admit.expectedDiscoverReceiptIdentity-cne$Boundary.expectedDiscoverReceiptIdentity-or[IO.Path]::GetFullPath($admit.discoverReceiptPath)-cne[IO.Path]::GetFullPath($Boundary.discoverReceiptPath)-or$result.mode-cne'ADMIT_ACTION'-or$result.status-cne'PASS'-or$result.selectionIdentity-cne$Receipt.selectionIdentity-or@($result.missingPreparation).Count-or@($result.missingResult).Count){throw 'SOURCE_CHANGE_ORIGINAL_ADMISSION_REQUIRED'}
        if(@($admit.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_CHANGE|*'}).Count-ne1-or$tokens[0]-cnotin@($admit.preparationReceipts)-or$result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $Receipt $admit)){throw 'SOURCE_CHANGE_ORIGINAL_ADMISSION_DECISION'}
        if($Stage-ceq'FINALIZE'-and($admit.publicDecisionIdentity-cne$Boundary.publicDecisionIdentity-or$admit.protectionState-cne$Boundary.protectionState)){throw 'SOURCE_CHANGE_ORIGINAL_DECISION_OR_PROTECTION'}
        if($null-eq$result.PSObject.Properties['projectSourcePreparation']-or$result.projectSourcePreparation.outcome-cne'PREPARED'-or$result.projectSourcePreparation.candidateIdentity-cne$reference.identity-or$result.projectSourcePreparation.targetIdentity-cne(Get-AiwContentDescriptorIdentity $candidate.target)){throw 'SOURCE_CHANGE_ORIGINAL_ADMISSION_TARGET'}
        $admission=[pscustomobject]@{input=$admit;result=$result}
    }
    $target=$null
    if(-not$Rollback){
        $target=Get-AiwSourceChangeTarget $Receipt $newConfig $newPolicy
        if((ConvertTo-AiwContentCanonicalJson $target.binding)-cne(ConvertTo-AiwContentCanonicalJson $candidate.target)){throw 'SOURCE_CHANGE_FROZEN_TARGET_DRIFT'}
    }
    return [pscustomobject]@{candidate=$candidate;reference=$reference;documents=$documents;target=$target;admission=$admission;rollback=[bool]$Rollback}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}

function New-AiwProjectSourceChangePreparation {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$DiscoverReceiptPath,[Parameter(Mandatory)][string]$ExpectedDiscoverReceiptIdentity,[Parameter(Mandatory)][string]$ConfigPostimagePath,[Parameter(Mandatory)][string]$PolicyPostimagePath,[Parameter(Mandatory)]$DecisionRef,[Parameter(Mandatory)][string]$OutputDirectory,$PublicationPlanRef,$PublicationSourceReceiptRef,[object[]]$SourcePostimages)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot (Get-AiwPublicationInputProjectRoot $DiscoverReceiptPath) -Mode OBSERVE
try {

    $publicationParameters=@('PublicationPlanRef','PublicationSourceReceiptRef','SourcePostimages'|Where-Object{$PSBoundParameters.ContainsKey($_)})
    if($publicationParameters.Count){
        if($publicationParameters.Count-ne3){throw 'SOURCE_PUBLICATION_PREPARATION_PARAMETER_GROUP'}
        return New-AiwProjectSourcePublicationPreparation @PSBoundParameters
    }
    $receiptDocument=Read-AiwStrictJson $DiscoverReceiptPath 'SOURCE_CHANGE_DISCOVER'
    if($receiptDocument.Identity-cne$ExpectedDiscoverReceiptIdentity){throw 'SOURCE_CHANGE_DISCOVER_DRIFT'}
    $receipt=$receiptDocument.Value;$binding=Get-AiwSourceChangeBinding $receipt
    $package=Assert-AiwSourceChangeOriginalContext $receipt
    $null=Read-AiwSourceChangeEvidence $DecisionRef $binding.projectRoot @($binding.forbiddenScope)
    $originalConfig=Read-AiwStrictJson (Resolve-AiwChildFile $binding.projectRoot '.ai-workspace/project.json' 'SOURCE_CHANGE_CONFIG') 'SOURCE_CHANGE_CONFIG'
    $originalPolicy=Read-AiwStrictJson (Resolve-AiwChildFile $binding.projectRoot '.ai-workspace/process-policy.json' 'SOURCE_CHANGE_POLICY') 'SOURCE_CHANGE_POLICY'
    $ConfigPostimagePath=Resolve-AiwSourceChangeEvidencePath $ConfigPostimagePath $binding.projectRoot @($binding.forbiddenScope)
    $PolicyPostimagePath=Resolve-AiwSourceChangeEvidencePath $PolicyPostimagePath $binding.projectRoot @($binding.forbiddenScope)
    $configRef=[pscustomobject]@{path=$ConfigPostimagePath;identity=(Get-AiwFileIdentity $ConfigPostimagePath)}
    $policyRef=[pscustomobject]@{path=$PolicyPostimagePath;identity=(Get-AiwFileIdentity $PolicyPostimagePath)}
    $config=Read-AiwStrictJson (Read-AiwSourceChangeEvidence $configRef $binding.projectRoot @($binding.forbiddenScope)) 'SOURCE_CHANGE_CONFIG'
    $policy=Read-AiwStrictJson (Read-AiwSourceChangeEvidence $policyRef $binding.projectRoot @($binding.forbiddenScope)) 'SOURCE_CHANGE_POLICY'
    $changes=Get-AiwProjectSourcePermissionChanges $originalConfig.Value $config.Value $package
    Assert-AiwCurrentObjectValue PROCESS_POLICY $policy.Value
    if($policy.Value.schemaVersion-ne3-or$policy.Value.projectId-cne$originalConfig.Value.id-or$policy.Value.contractVersion-cne'2.0.0'){throw 'SOURCE_CHANGE_POLICY_FORMAT'}
    if($originalConfig.Identity-cne$receipt.sourceBindings.projectConfigIdentity-or$originalPolicy.Identity-cne$receipt.sourceBindings.policyIdentity){throw 'SOURCE_CHANGE_PREPARATION_DRIFT'}
    $writePaths=@()
    if($originalPolicy.Identity-cne$policy.Identity){$writePaths+=@('.ai-workspace/process-policy.json')}
    if($originalConfig.Identity-cne$config.Identity){$writePaths+=@('.ai-workspace/project.json')}
    if($writePaths.Count-eq0-or[string]::Join('|',@($package.exactPaths|Sort-Object -CaseSensitive))-cne[string]::Join('|',@($writePaths|Sort-Object -CaseSensitive))-or@($package.objectIdentities).Count-ne$writePaths.Count){throw 'SOURCE_CHANGE_ACTUAL_WRITE_SCOPE'}
    foreach($item in @(@{path='.ai-workspace/project.json';identity=$originalConfig.Identity},@{path='.ai-workspace/process-policy.json';identity=$originalPolicy.Identity})|Where-Object{$_.path-cin$writePaths}){
        $authorized=@($package.objectIdentities|Where-Object path -CEQ $item.path)
        if($authorized.Count-ne1-or$authorized[0].identity-cne$item.identity){throw 'SOURCE_CHANGE_PREIMAGE_NOT_AUTHORIZED'}
    }
    $output=[IO.Path]::GetFullPath($OutputDirectory);$prefix=[IO.Path]::GetFullPath((Join-Path $binding.projectRoot '.ai-workspace/runtime'))+[IO.Path]::DirectorySeparatorChar
    if(-not$output.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)-or(Test-Path -LiteralPath $output)){throw 'SOURCE_CHANGE_OUTPUT_DIRECTORY'}
    Assert-AiwProjectStandardReadAllowed $binding.projectRoot $output @($binding.forbiddenScope) 'SOURCE_CHANGE_OUTPUT'
    $parent=Split-Path -Parent $output
    if(-not[IO.Directory]::Exists($parent)){throw 'SOURCE_CHANGE_OUTPUT_PARENT'}
    $cursor=$parent
    while($cursor.Length-ge$binding.projectRoot.Length){
        if(((Get-Item -LiteralPath $cursor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'SOURCE_CHANGE_OUTPUT_REPARSE'}
        if($cursor-ceq$binding.projectRoot){break};$cursor=Split-Path -Parent $cursor
    }
    $null=[IO.Directory]::CreateDirectory($output)
    $objects=@();foreach($item in @(@{path='.ai-workspace/process-policy.json';old=$originalPolicy;new=$policy},@{path='.ai-workspace/project.json';old=$originalConfig;new=$config})){
        $oldPath=Join-Path $output ((Split-Path -Leaf $item.path)+'.before');[IO.File]::WriteAllText($oldPath,$item.old.Text,$script:Utf8Strict)
        $newPath=Join-Path $output ((Split-Path -Leaf $item.path)+'.after');[IO.File]::WriteAllText($newPath,$item.new.Text,$script:Utf8Strict)
        $objects+=,[pscustomobject]@{path=$item.path;preimage=[pscustomobject]@{path=$oldPath;identity=$item.old.Identity};postimage=[pscustomobject]@{path=$newPath;identity=$item.new.Identity}}
    }
    $target=Get-AiwSourceChangeTarget $receipt $config $policy
    $candidate=[pscustomobject]@{schemaVersion=1;kind='PROJECT_SOURCE_CHANGE';discoverReceiptIdentity=$receiptDocument.Identity;authorizationIdentity=$binding.authorizationIdentity;userDecision=$binding.userDecision;decisionRef=$DecisionRef;objects=$objects;permissionChanges=$changes;rootToolDependencies=@(Get-AiwSourceChangeRootTools $receipt.sourceLocators.frameworkRoot);target=$target.binding}
    $candidatePath=Join-Path $output 'candidate.json';[IO.File]::WriteAllText($candidatePath,($candidate|ConvertTo-Json -Depth 100)+[char]10,$script:Utf8Strict)
    $token='PROJECT_SOURCE_CHANGE|'+$candidatePath+'|'+(Get-AiwFileIdentity $candidatePath)
    $boundary=[pscustomobject]@{discoverReceiptPath=$DiscoverReceiptPath;expectedDiscoverReceiptIdentity=$receiptDocument.Identity;preparationReceipts=@($token)}
    $null=Get-AiwProjectSourceChange -Receipt $receipt -Boundary $boundary -Stage ADMIT
    return [pscustomobject]@{candidate=[pscustomobject]@{path=$candidatePath;identity=(Get-AiwFileIdentity $candidatePath)};preparationReceipt=$token;permissionChanges=$changes;selectedRuleBlocks=@($target.composition.selectedRequirements);preparationRequirements=@($target.composition.selectedRequirements.preparationRequirements|Sort-Object -Unique);resultRequirements=@($target.composition.selectedRequirements.resultRequirements|Sort-Object -Unique);authorityGranted=$false;projectWritePerformed=$false}

} finally { Exit-AiwProjectSourceScope $aiwPublicationScopeLease }
}
function Get-AiwPublicationProjectedObjects($Facts){
    return @(foreach($object in @($Facts.plan.objects|Where-Object ownerMember -CEQ SOURCE)){
        $doc=$Facts.CONTROL.eligibility.documents[$object.path+'|postimage']
        [pscustomobject]@{kind='FILE';path=$object.path;newExists=$true;newBase64=[Convert]::ToBase64String($doc.Bytes);newIdentity=$doc.Identity}
    })
}
function Get-AiwPublicationTargets($Facts){
    $documents=$Facts.CONTROL.eligibility.documents;$projected=@(Get-AiwPublicationProjectedObjects $Facts)
    $targets=@{};$previous=$script:PublicationTargetStandards
    $script:PublicationTargetStandards=@{context=$null;value=$null}
    try{
        foreach($member in @('SOURCE','CONTROL')){
            Assert-AiwSourceChangeStaticContext $Facts.$member.receipt
            $targets[$member]=Get-AiwSourceChangeTarget $Facts.$member.receipt $documents['.ai-workspace/project.json|postimage'] $documents['.ai-workspace/process-policy.json|postimage'] $projected
        }
        return $targets
    }finally{$script:PublicationTargetStandards=$previous}
}
function New-AiwProjectSourcePublicationPreparation {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$DiscoverReceiptPath,[Parameter(Mandatory)][string]$ExpectedDiscoverReceiptIdentity,[Parameter(Mandatory)][string]$ConfigPostimagePath,[Parameter(Mandatory)][string]$PolicyPostimagePath,[Parameter(Mandatory)]$DecisionRef,[Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)]$PublicationPlanRef,[Parameter(Mandatory)]$PublicationSourceReceiptRef,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SourcePostimages)
    $controlRef=[pscustomobject]@{path=$DiscoverReceiptPath;identity=$ExpectedDiscoverReceiptIdentity}
    $facts=Get-AiwProjectSourcePublicationMembers $controlRef $PublicationSourceReceiptRef $PublicationPlanRef
    $aiwPublicationScopeLease=Enter-AiwProjectSourceScope $facts.root
    try{
        $plan=$facts.plan;$documents=$facts.CONTROL.eligibility.documents
        $declared=@($plan.objects|Where-Object ownerMember -CEQ SOURCE|ForEach-Object{[pscustomobject]@{path=$_.path;identity=$_.postimage.identity}})
        foreach($object in $SourcePostimages){Assert-AiwExactFields $object @('path','identity') 'SOURCE_PUBLICATION_POSTIMAGE'}
        if((ConvertTo-AiwContentCanonicalJson $declared)-cne(ConvertTo-AiwContentCanonicalJson $SourcePostimages)-or(ConvertTo-AiwContentCanonicalJson $DecisionRef)-cne(ConvertTo-AiwContentCanonicalJson $plan.decisionRef)-or(Get-AiwFileIdentity $ConfigPostimagePath)-cne$documents['.ai-workspace/project.json|postimage'].Identity-or(Get-AiwFileIdentity $PolicyPostimagePath)-cne$documents['.ai-workspace/process-policy.json|postimage'].Identity){throw 'SOURCE_PUBLICATION_PREPARATION_PLAN_DRIFT'}
        $output=[IO.Path]::GetFullPath($OutputDirectory);$prefix=Join-Path $facts.root '.ai-workspace/runtime'
        if(-not$output.StartsWith($prefix+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or(Test-Path -LiteralPath $output)-or-not[IO.Directory]::Exists([IO.Path]::GetDirectoryName($output))){throw 'SOURCE_CHANGE_OUTPUT_DIRECTORY'}
        Assert-AiwProjectStandardReadAllowed $facts.root $output $facts.CONTROL.eligibility.forbidden 'SOURCE_PUBLICATION_OUTPUT'
        $targets=Get-AiwPublicationTargets $facts
        $members=@(foreach($member in @('SOURCE','CONTROL')){[pscustomobject]@{member=$member;discoverReceiptRef=$facts.$member.receiptRef;authorizationRef=$facts.$member.authorizationRef}})
        $targetRecords=@(foreach($member in @('SOURCE','CONTROL')){[pscustomobject]@{member=$member;binding=$targets[$member].binding}})
        $candidate=[pscustomobject]@{schemaVersion=2;kind='PROJECT_SOURCE_PUBLICATION';planRef=$PublicationPlanRef;userDecision=$plan.userDecision;decisionRef=$plan.decisionRef;members=$members;objects=@($plan.objects);writeOrder=@($plan.writeOrder);permissionChanges=$plan.permissionChanges;rootToolDependencies=@($plan.rootToolDependencies);targets=$targetRecords}
        $null=[IO.Directory]::CreateDirectory($output)
        $candidatePath=Join-Path $output 'candidate.json'
        $stream=[IO.File]::Open($candidatePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$bytes=$script:Utf8Strict.GetBytes(($candidate|ConvertTo-Json -Depth 100)+[char]10);$stream.Write($bytes);$stream.Flush($true)}finally{$stream.Dispose()}
        $reference=[pscustomobject]@{path=$candidatePath;identity=(Get-AiwFileIdentity $candidatePath)};$token='PROJECT_SOURCE_CHANGE|'+$reference.path+'|'+$reference.identity
        foreach($member in @('SOURCE','CONTROL')){
            $boundary=[pscustomobject]@{discoverReceiptPath=$facts.$member.receiptRef.path;expectedDiscoverReceiptIdentity=$facts.$member.receiptRef.identity;preparationReceipts=@($token)}
            $null=Get-AiwPublicationCandidateCore $facts.$member.receipt $boundary $reference ADMIT -VerifiedFacts $facts -VerifiedTargets $targets
        }
        return [pscustomobject]@{candidate=$reference;preparationReceipt=$token;permissionChanges=$plan.permissionChanges;members=@(foreach($member in @('SOURCE','CONTROL')){[pscustomobject]@{member=$member;selectedRuleBlocks=@($targets[$member].composition.selectedRequirements);preparationRequirements=@($targets[$member].composition.selectedRequirements.preparationRequirements|Sort-Object -Unique);resultRequirements=@($targets[$member].composition.selectedRequirements.resultRequirements|Sort-Object -Unique)}});authorityGranted=$false;projectWritePerformed=$false}
    }finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
}
function Get-AiwProjectSourcePublicationCandidate {
    [CmdletBinding()]param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Boundary,[Parameter(Mandatory)]$Reference,[ValidateSet('ADMIT','FINALIZE','RECOVERY')][string]$Stage,[switch]$Rollback)
    Get-AiwPublicationCandidateCore @PSBoundParameters
}
function Get-AiwPublicationCandidateCore {
    param($Receipt,$Boundary,$Reference,[string]$Stage,[switch]$Rollback,$VerifiedFacts=$null,$VerifiedTargets=$null,$TargetsCapture=$null)
    if($null-ne$TargetsCapture){
        if($TargetsCapture-isnot[System.Management.Automation.PSReference]){throw 'SOURCE_PUBLICATION_PRIVATE_CAPTURE'}
        $TargetsCapture.Value=$null
    }
    $binding=Get-AiwSourceChangeBinding $Receipt
    $aiwPublicationScopeLease=Enter-AiwProjectSourceScope $binding.projectRoot
    try{
        $candidate=(Read-AiwStrictJson (Read-AiwSourceChangeEvidence $Reference $binding.projectRoot @($binding.forbiddenScope)) 'SOURCE_PUBLICATION_CANDIDATE').Value
        Assert-AiwExactFields $candidate @('schemaVersion','kind','planRef','userDecision','decisionRef','members','objects','writeOrder','permissionChanges','rootToolDependencies','targets') 'SOURCE_PUBLICATION_CANDIDATE'
        if($candidate.schemaVersion-ne2-or$candidate.kind-cne'PROJECT_SOURCE_PUBLICATION'-or$candidate.members-isnot[array]-or$candidate.members.Count-ne2-or[string]::Join('|',@($candidate.members.member))-cne'SOURCE|CONTROL'-or$candidate.targets-isnot[array]-or$candidate.targets.Count-ne2-or[string]::Join('|',@($candidate.targets.member))-cne'SOURCE|CONTROL'){throw 'SOURCE_PUBLICATION_TWO_MEMBERS_REQUIRED'}
        foreach($member in $candidate.members){Assert-AiwExactFields $member @('member','discoverReceiptRef','authorizationRef') 'SOURCE_PUBLICATION_MEMBER'}
        foreach($target in $candidate.targets){Assert-AiwExactFields $target @('member','binding') 'SOURCE_PUBLICATION_TARGET'}
        $facts=if($null-ne$VerifiedFacts){$VerifiedFacts}else{Get-AiwProjectSourcePublicationMembers $candidate.members[1].discoverReceiptRef $candidate.members[0].discoverReceiptRef $candidate.planRef}
        if((ConvertTo-AiwContentCanonicalJson $candidate.planRef)-cne(ConvertTo-AiwContentCanonicalJson $facts.planRef)){throw 'SOURCE_PUBLICATION_CANDIDATE_PLAN_DRIFT'}
        foreach($name in @('userDecision','decisionRef','objects','writeOrder','permissionChanges','rootToolDependencies')){if((ConvertTo-AiwContentCanonicalJson $candidate.$name)-cne(ConvertTo-AiwContentCanonicalJson $facts.plan.$name)){throw ('SOURCE_PUBLICATION_CANDIDATE_PLAN_DRIFT|'+$name)}}
        foreach($member in $candidate.members){if((ConvertTo-AiwContentCanonicalJson $member.authorizationRef)-cne(ConvertTo-AiwContentCanonicalJson $facts.($member.member).authorizationRef)){throw 'SOURCE_PUBLICATION_CANDIDATE_PACKAGE_DRIFT'}}
        $memberName=if($Receipt.intentEnvelope.requestedActionKind-ceq'SOURCE_WRITE'){'SOURCE'}else{'CONTROL'};$memberFacts=$facts.$memberName
        if($Boundary.expectedDiscoverReceiptIdentity-cne$memberFacts.receiptRef.identity-or[IO.Path]::GetFullPath($Boundary.discoverReceiptPath)-cne[IO.Path]::GetFullPath($memberFacts.receiptRef.path)){throw 'SOURCE_PUBLICATION_WRONG_ORIGINAL_MEMBER'}
        $state=Get-AiwProjectSourcePublicationReachability $facts.root $facts.plan $facts.CONTROL.eligibility.forbidden
        if($Stage-ceq'ADMIT'-and-not$state.allOld){throw 'SOURCE_PUBLICATION_PRE_ADMIT_DRIFT'}
        if($Stage-cne'ADMIT'){
            $context=Get-AiwProjectSourcePublicationContext $facts.root
            $pairTokens=@($Boundary.preparationReceipts|Where-Object{$_-clike'PROJECT_SOURCE_PUBLICATION_ADMISSIONS|*'})
            if($pairTokens.Count){
                if($pairTokens.Count-ne1-or$pairTokens[0]-cnotmatch'^PROJECT_SOURCE_PUBLICATION_ADMISSIONS\|([^|]+)\|(\d+\|[A-F0-9]{64})$'){throw 'SOURCE_PUBLICATION_ORIGINAL_PAIR_REFERENCE'}
                $pairRef=[pscustomobject]@{path=$Matches[1];identity=$Matches[2]}
                $pair=(Read-AiwStrictJson (Read-AiwSourceChangeEvidence $pairRef $facts.root @($facts.CONTROL.eligibility.forbidden)) 'SOURCE_PUBLICATION_ORIGINAL_PAIR').Value
                $publicationOwner=@(Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1') -PassThru)[0]
                $original=& $publicationOwner {param($root,$p) Get-PubRecoveryOriginalFacts $root $p} $facts.root $pair
                $context=$original.proof
                if($original.admissions[$memberName].refs.discoverReceiptRef.identity-cne$Boundary.expectedDiscoverReceiptIdentity-or$original.admissions[$memberName].input.publicDecisionIdentity-cne$Boundary.publicDecisionIdentity-or$original.admissions[$memberName].input.protectionState-cne$Boundary.protectionState){throw 'SOURCE_PUBLICATION_ORIGINAL_MEMBER_DECISION_DRIFT'}
            }
            if($null-eq$context-or$context.candidateRef.identity-cne$Reference.identity){throw 'SOURCE_PUBLICATION_ORIGINAL_TWO_ADMISSIONS_REQUIRED'}
            if($Stage-ceq'FINALIZE'-and(($Rollback-and-not$state.allOld)-or(-not$Rollback-and-not$state.allNew))){throw 'SOURCE_PUBLICATION_FINAL_GROUP_REQUIRED'}
        }
        $targets=if($null-ne$VerifiedTargets){$VerifiedTargets}else{Get-AiwPublicationTargets $facts}
        foreach($target in $candidate.targets){if((ConvertTo-AiwContentCanonicalJson $target.binding)-cne(ConvertTo-AiwContentCanonicalJson $targets[$target.member].binding)){throw 'SOURCE_PUBLICATION_FROZEN_TARGET_DRIFT'}}
        if($null-ne$TargetsCapture){$TargetsCapture.Value=$targets}
        # The original boundary consumes its own target, while the immutable
        # candidate continues to bind both members. This alias is never saved.
        $memberCandidate=Copy-AiwFormatValue $candidate;$memberCandidate|Add-Member -NotePropertyName target -NotePropertyValue $targets[$memberName].binding
        return [pscustomobject]@{candidate=$memberCandidate;reference=$Reference;documents=$facts.CONTROL.eligibility.documents;target=$(if($Rollback){$null}else{$targets[$memberName]});admission=$(if($Stage-ceq'ADMIT'){$null}else{$context});rollback=[bool]$Rollback;publication=$true;member=$memberName}
    }finally{Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
}
Export-ModuleMember -Function Get-AiwProjectSourcePublicationCandidate
Export-ModuleMember -Function Get-AiwProjectSourcePermissionChanges,Get-AiwProjectSourceChange,New-AiwProjectSourceChangePreparation

# Selection consumes current declarations and facts once. Dependency nodes
# belong to the selected descriptor graph and are never selected a second time.
function Get-AiwRuleSelectionPlan($Catalog,$Records,$PolicyRules,$Custom,[string]$ProjectId,[string]$Profile,[string]$Role,[string]$Phase,[string]$ActionKind,[string]$ResultKind,[string[]]$Paths,[string[]]$Capabilities,[string]$Objective,[bool]$Unknown,$Facets){
    $matches=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $ids=[Collections.Generic.List[string]]::new();$trace=[Collections.Generic.List[object]]::new()
    $policy=[Collections.Generic.List[object]]::new();$corrections=[Collections.Generic.List[object]]::new()
    $requests=@()
    foreach($rule in $Catalog.requirements){$requests+=,[pscustomobject]@{id=('framework:'+$rule.requirementId);selectors=$rule.selectors;record=$rule;source='FRAMEWORK'}}
    foreach($item in $Records){
        $record=$item.Record
        if($null-ne$record.PSObject.Properties['lifecycle']-and$record.lifecycle.state-cne'ACTIVE'){continue}
        $requests+=,[pscustomobject]@{id=$item.Alias;selectors=$record.selectors;record=$record;source='CORRECTION'}
    }
    foreach($rule in $PolicyRules){$requests+=,[pscustomobject]@{id=('project:'+$ProjectId+':'+$rule.ruleId);selectors=$rule.selectors;record=$rule;source='POLICY'}}
    foreach($request in $requests){
        $match=Test-AiwRuleMatch $request.selectors $Profile $Role $Phase $ActionKind $ResultKind $Paths $Capabilities $Objective $Unknown $Facets
        $matches.Add($request.id,$match)
        $trace.Add([ordered]@{requirementId=$request.id;decision=$match.Decision;reason=$match.Semantic;dimensions=$match.Reasons})
        if(-not$match.Match){continue}
        $ids.Add($request.id)
        if($request.source-ceq'POLICY'){$policy.Add($request.record)}
        elseif($request.source-ceq'CORRECTION'){$corrections.Add($request.record)}
    }
    if($Custom.HasNormativeContent){$ids.Add('project-custom:'+$ProjectId)}
    return [pscustomobject]@{matches=$matches;ruleIds=$ids.ToArray();policyRules=$policy.ToArray();corrections=$corrections.ToArray();trace=$trace.ToArray()}
}
function Get-AiwStandardsSubsetSnapshot($Complete,[object[]]$Rules){
    $resolved=@{};$rows=[Collections.Generic.List[string]]::new()
    foreach($rule in $Rules){
        if($null-eq$rule.PSObject.Properties['source']){continue}
        $item=$Complete.Rules[[string]$rule.ruleId]
        if($null-eq$item){throw 'CONTENT_IDENTITY_DRIFT|COMPLETE_SOURCE_SUBSET'}
        $resolved.Add([string]$rule.ruleId,$item);$rows.Add($rule.ruleId+'|'+$item.Identity)
    }
    $identity='MISSING'
    if($rows.Count){[string[]]$sorted=$rows.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal);$identity=Get-AiwContentByteIdentity $script:Utf8Strict.GetBytes(($sorted-join[char]10))}
    return [pscustomobject]@{Identity=$identity;Rules=$resolved;Drift=(@($resolved.Values|Where-Object{$_.Drift}).Count-gt0)}
}
# The private target pair constructs the complete local set once. Its second
# consumer selects from that same result; it does not reopen sources to prove
# that the first construction can be borrowed. New public calls start afresh.
function Get-AiwPublicationCompleteStandards($Project,[object[]]$Rules,[string[]]$ForbiddenPaths,$Context,[string]$ConfigIdentity,[string]$PolicyIdentity,$ReadTrace){
    $scope=$script:PublicationTargetStandards
    $owned=$null-ne$scope-and$null-ne$Context-and[object]::ReferenceEquals($scope.context,$Context)
    if($owned-and$null-ne$scope.value){
        $complete=$scope.value
        # Shared observations are diagnostic, not additional physical reads.
        if($null-ne$ReadTrace){foreach($rule in $Rules){
            if($null-eq$rule.PSObject.Properties['source']){continue}
            $item=$complete.Rules[[string]$rule.ruleId]
            for($index=0;$index-lt$item.Documents.Count;$index++){
                $document=$item.Documents[$index]
                $sourceId=$item.ContentSnapshot.facts.documents[$index].document.sourceId
                $observation=if($Context.ProjectedSources.ContainsKey($document.sourcePath)){'PROJECTED'}else{'LOCAL'}
                $ReadTrace.Add([pscustomobject]@{sequence=$ReadTrace.Count;event='SOURCE_BODY_SHARED';ruleId=$rule.ruleId;sourceId=$sourceId;path=$document.sourcePath;identity=$document.identity;observation=$observation;authority=$false})
            }
        }}
        return $complete
    }
    $complete=Get-AiwProjectStandardsSnapshot -ProjectRoot $Project -Rules $Rules -ForbiddenPaths $ForbiddenPaths -ContentContext $Context -ExpectedConfigIdentity $ConfigIdentity -ExpectedPolicyIdentity $PolicyIdentity -ReadTrace $ReadTrace
    # Keep nonlocal/legacy reader semantics. The directly shared result is the
    # already constructed complete bound-local set, never a caller input.
    $local=@($Rules|Where-Object{$null-ne$_.PSObject.Properties['source']-and($null-eq$_.source.PSObject.Properties['kind']-or$_.source.kind-cne'BOUND_SOURCE_ITEM')}).Count-eq0
    if($local){foreach($item in $complete.Rules.Values){
        if($item.Unavailable-or$item.Drift-or@($item.Documents|Where-Object{$_.locatorKind-cnotin@('PROJECT_RELATIVE','ABSOLUTE_FILE')}).Count){$local=$false;break}
    }}
    if($owned-and$local){$scope.value=$complete}
    return $complete
}

function Get-AiwScopedProjectContent($Project,[object[]]$Rules,[object[]]$Corrections,$Custom,$Plan,[string[]]$ForbiddenPaths,$Context,[string]$ConfigIdentity,[string]$PolicyIdentity,[bool]$ValidateComplete,$ReadTrace){
    if($ValidateComplete){
        $complete=Get-AiwPublicationCompleteStandards $Project $Rules $ForbiddenPaths $Context $ConfigIdentity $PolicyIdentity $ReadTrace
        $null=Test-AiwEffectiveRuleSet -ProjectRoot $Project -Corrections $Corrections -PolicyRules $Rules -Custom $Custom -ForbiddenPaths $ForbiddenPaths -StandardsSnapshot $complete
        if($null-ne$ReadTrace){$ReadTrace.Add([pscustomobject]@{sequence=$ReadTrace.Count;event='COMPLETE_ADOPTED_SET_VERIFIED';authority=$false})}
        $standards=Get-AiwStandardsSubsetSnapshot $complete $Plan.policyRules
    }else{
        $standards=Get-AiwProjectStandardsSnapshot -ProjectRoot $Project -Rules $Plan.policyRules -ForbiddenPaths $ForbiddenPaths -ContentContext $Context -ExpectedConfigIdentity $ConfigIdentity -ExpectedPolicyIdentity $PolicyIdentity -ReadTrace $ReadTrace
    }
    # This identity belongs to selected policy standards. Native/correction selection
    # remains in effective.identity below; it cannot falsely turn an authorized
    # correction-only postimage into unowned policy-standard drift.
    $standards.Identity=Get-AiwContentDescriptorIdentity ([ordered]@{scope='SELECTED_RULE_CLOSURE_V1';ruleIds=@($Plan.policyRules|ForEach-Object{$_.ruleId});rules=@($Plan.policyRules);observedStandardsIdentity=$standards.Identity})
    $effective=Test-AiwEffectiveRuleSet -ProjectRoot $Project -Corrections $Plan.corrections -PolicyRules $Plan.policyRules -Custom $Custom -ForbiddenPaths $ForbiddenPaths -StandardsSnapshot $standards
    $effective.identity=Get-AiwContentDescriptorIdentity ([ordered]@{scope='SELECTED_RULE_CLOSURE_V1';ruleIds=@($Plan.ruleIds);observedContentIdentity=$effective.identity})
    return [pscustomobject]@{standards=$standards;effective=$effective}
}

# @design-contract IMPLEMENTATION-PLAN.md sections 3-4: one stable subject union.
function Assert-AiwQualityStages($Stages,[switch]$Nonempty){
    Assert-AiwStringArray $Stages 'QUALITY_STAGES'
    if($Nonempty-and$Stages.Count-eq0){throw 'QUALITY_STAGES_EMPTY'}
    foreach($s in $Stages){if($s-cnotin@('SELF_CHECK','RESULT_REVIEW','RESULT_ACCEPT')){throw 'QUALITY_STAGE_UNKNOWN'}}
}
function Assert-AiwQualityPolicy($Policy){
    $enabled=$null-ne$Policy.PSObject.Properties['qualityAssurance']
    if($enabled){
        if($Policy.schemaVersion-ne3){throw 'QUALITY_POLICY_SCHEMA'}
        Assert-AiwExactFields $Policy.qualityAssurance @('schemaVersion','defaultStages') 'QUALITY_ASSURANCE'
        if(-not(Test-AiwJsonInteger $Policy.qualityAssurance.schemaVersion)-or$Policy.qualityAssurance.schemaVersion-ne1){throw 'QUALITY_ASSURANCE_SCHEMA'}
        Assert-AiwQualityStages $Policy.qualityAssurance.defaultStages
    }
    foreach($r in $Policy.rules){
        if($null-eq$r.PSObject.Properties['qualityStages']){continue}
        if(-not$enabled){throw 'QUALITY_STAGES_ORPHAN'}
        Assert-AiwQualityStages $r.qualityStages -Nonempty
        Assert-AiwSelectorContract $r.selectors 'QUALITY_SELECTORS'
        foreach($axis in @('roles','phases','actionKinds','resultKinds','capabilities')){
            if(@($r.selectors.$axis|Where-Object{$_-cne'*'}).Count){throw 'QUALITY_SELECTOR_UNSTABLE'}
        }
        if($r.selectors.semanticTerms.Count-or$null-ne$r.selectors.PSObject.Properties['deterministicTriggers']){throw 'QUALITY_SELECTOR_UNSTABLE'}
        if($null-ne$r.selectors.PSObject.Properties['facets']){
            if(@($r.selectors.facets.PSObject.Properties.Name|Where-Object{$_-cnotin@('domain','deliverableType')}).Count){throw 'QUALITY_SELECTOR_UNSTABLE'}
        }
    }
}
function Assert-AiwQualitySubject($Subject){
    Assert-AiwExactFields $Subject @('repositoryId','exactPaths','facets') 'QUALITY_SUBJECT'
    if($Subject.repositoryId-isnot[string]-or[string]::IsNullOrWhiteSpace($Subject.repositoryId)-or$Subject.repositoryId-cne$Subject.repositoryId.Trim()){throw 'QUALITY_REPOSITORY'}
    Assert-AiwStringArray $Subject.exactPaths 'QUALITY_PATHS'
    if($Subject.exactPaths.Count-eq0){throw 'QUALITY_SUBJECT_EMPTY'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($p in $Subject.exactPaths){if($p-cne(ConvertTo-AiwSafeRelativePath $p 'QUALITY_PATH')-or-not$seen.Add($p)){throw 'QUALITY_PATH_NONCANONICAL'}}
    Assert-AiwExactFields $Subject.facets @('domain','deliverableType') 'QUALITY_FACETS'
    foreach($dimension in @('domain','deliverableType')){
        $facet=$Subject.facets.$dimension
        Assert-AiwExactFields $facet @('state','values') 'QUALITY_FACET'
        Assert-AiwStringArray $facet.values 'QUALITY_FACET_VALUES'
        if($facet.state-cne'KNOWN'-or$facet.values.Count-eq0){throw 'QUALITY_CLASSIFICATION_REQUIRED'}
    }
}
function Assert-AiwQualityBinding($Binding){
    Assert-AiwExactFields $Binding @('schemaVersion','policyRef','subject','effectiveStages') 'QUALITY_BINDING'
    if(-not(Test-AiwJsonInteger $Binding.schemaVersion)-or$Binding.schemaVersion-ne1){throw 'QUALITY_BINDING_SCHEMA'}
    Assert-AiwExactFields $Binding.policyRef @('path','identity') 'QUALITY_POLICY_REF'
    if($Binding.policyRef.path-cne'.ai-workspace/process-policy.json'-or$Binding.policyRef.identity-isnot[string]-or$Binding.policyRef.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'QUALITY_POLICY_REF'}
    Assert-AiwQualitySubject $Binding.subject
    Assert-AiwQualityStages $Binding.effectiveStages
    $ordered=@(@('SELF_CHECK','RESULT_REVIEW','RESULT_ACCEPT')|Where-Object{$_-cin$Binding.effectiveStages})
    if(($ordered-join'|')-cne($Binding.effectiveStages-join'|')){throw 'QUALITY_STAGE_ORDER'}
}
function Get-AiwQualityBindingKey($Binding){
    Assert-AiwQualityBinding $Binding
    $copy=$Binding|ConvertTo-Json -Depth 30 -Compress|ConvertFrom-Json -Depth 30
    [string[]]$paths=@($copy.subject.exactPaths);[Array]::Sort($paths,[StringComparer]::Ordinal);$copy.subject.exactPaths=$paths
    foreach($d in @('domain','deliverableType')){[string[]]$values=@($copy.subject.facets.$d.values);[Array]::Sort($values,[StringComparer]::Ordinal);$copy.subject.facets.$d=[pscustomobject]@{state='KNOWN';values=$values}}
    # Explicit property order avoids caller JSON property-order authority.
    [ordered]@{schemaVersion=1;policyRef=[ordered]@{path=$copy.policyRef.path;identity=$copy.policyRef.identity};subject=[ordered]@{repositoryId=$copy.subject.repositoryId;exactPaths=$copy.subject.exactPaths;facets=[ordered]@{domain=$copy.subject.facets.domain;deliverableType=$copy.subject.facets.deliverableType}};effectiveStages=$copy.effectiveStages}|ConvertTo-Json -Depth 30 -Compress
}
function Get-AiwQualitySelection($Policy,[string]$PolicyIdentity,[string]$Profile,$Subject){
    Assert-AiwQualityPolicy $Policy
    if($null-eq$Policy.PSObject.Properties['qualityAssurance']){return [pscustomobject]@{mode='LEGACY';qualityBinding=$null;effectiveStages=@()}}
    Assert-AiwQualitySubject $Subject
    if($Profile-cnotin@('MICRO','STANDARD','CRITICAL')){throw 'QUALITY_PROFILE'}
    $catalog=Read-AiwStrictJson (Join-Path $PSScriptRoot '../PROCESS_REQUIREMENTS.json') 'PROCESS_REQUIREMENTS'
    $projectVocabulary=if($null-ne$Policy.PSObject.Properties['facetVocabulary']){@($Policy.facetVocabulary)}else{@()}
    $vocabulary=Get-AiwFacetVocabulary -NativeVocabulary @($catalog.Value.facetVocabulary) -ProjectVocabulary $projectVocabulary
    $facets=[pscustomobject]@{domain=$Subject.facets.domain;workType=[pscustomobject]@{state='UNKNOWN';values=@()};deliverableType=$Subject.facets.deliverableType;stage=[pscustomobject]@{state='UNKNOWN';values=@()}}
    $facets=ConvertTo-AiwIntentFacets -Facets $facets -Vocabulary $vocabulary
    $selected=@($Policy.qualityAssurance.defaultStages)
    foreach($rule in $Policy.rules){
        if($null-eq$rule.PSObject.Properties['qualityStages']){continue}
        if($null-ne$rule.selectors.PSObject.Properties['facets']){Assert-AiwFacetSelector -Facets $rule.selectors.facets -Vocabulary $vocabulary}
        $match=Test-AiwRuleMatch $rule.selectors $Profile '' '' '' '' @($Subject.exactPaths) @() '' $false $facets
        if($match.Match){$selected+=@($rule.qualityStages)}
    }
    $effective=@(@('SELF_CHECK','RESULT_REVIEW','RESULT_ACCEPT')|Where-Object{$_-cin$selected})
    $stable=$Subject|ConvertTo-Json -Depth 20 -Compress|ConvertFrom-Json -Depth 20
    foreach($d in @('domain','deliverableType')){$stable.facets.$d=$facets.$d}
    $binding=[pscustomobject]@{schemaVersion=1;policyRef=[pscustomobject]@{path='.ai-workspace/process-policy.json';identity=$PolicyIdentity};subject=$stable;effectiveStages=$effective}
    Assert-AiwQualityBinding $binding
    [pscustomobject]@{mode='EXPLICIT';qualityBinding=$binding;effectiveStages=$effective}
}
Export-ModuleMember -Function Assert-AiwQualityPolicy,Assert-AiwQualitySubject,Assert-AiwQualityBinding,Get-AiwQualityBindingKey,Get-AiwQualitySelection
