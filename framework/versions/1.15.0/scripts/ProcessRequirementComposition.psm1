Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8Strict = [Text.UTF8Encoding]::new($false,$true)
$script:ProcessCarrierContractVersion = '1.14.0'

function Get-AiwSha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','')}
    finally{$sha.Dispose()}
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
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "${Label}_BOM" }
    try { $text = $script:Utf8Strict.GetString($bytes) } catch { throw "${Label}_UTF8" }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { throw "${Label}_TEXT_FORMAT" }
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($text)
        try { Assert-AiwNoDuplicateJsonMember -Element $document.RootElement } finally { $document.Dispose() }
        $value = $text | ConvertFrom-Json -Depth 100
    } catch { throw "${Label}_JSON|$($_.Exception.Message)" }
    return [pscustomobject]@{ Value=$value; Text=$text; Identity=(Get-AiwFileIdentity $item.FullName); Path=$item.FullName }
}

function Read-AiwStrictText {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label}_MISSING" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "${Label}_REPARSE" }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "${Label}_BOM" }
    try { $text = $script:Utf8Strict.GetString($bytes) } catch { throw "${Label}_UTF8" }
    if ($text.Contains("`r") -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or -not $text.EndsWith("`n")) { throw "${Label}_TEXT_FORMAT" }
    return $text
}

function Get-AiwNativeRuleBlock {
    param(
        [Parameter(Mandatory)][string]$VersionDirectory,
        [Parameter(Mandatory)][string]$OwnerModule,
        [Parameter(Mandatory)][string]$RequirementId,
        [Parameter(Mandatory)][string]$ExactBlockLocator,
        [Parameter(Mandatory)][hashtable]$OwnerTextCache
    )
    if ($OwnerModule -cnotmatch '^[A-Z0-9_]+\.md$' -or $ExactBlockLocator -cne ('AIW-REQUIREMENT:' + $RequirementId)) { throw ('NATIVE_REQUIREMENT_LOCATOR|' + $RequirementId) }
    if (-not $OwnerTextCache.ContainsKey($OwnerModule)) {
        $ownerPath = Resolve-AiwChildFile $VersionDirectory $OwnerModule 'NATIVE_REQUIREMENT_OWNER'
        $OwnerTextCache[$OwnerModule] = Read-AiwStrictText $ownerPath 'NATIVE_REQUIREMENT_OWNER'
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
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $safe))
    if (-not $candidate.StartsWith([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root)) + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "${Label}_ESCAPE" }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        if ($AllowMissing) { return $null }
        throw "${Label}_MISSING"
    }
    if (((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "${Label}_REPARSE" }
    return $candidate
}

function Assert-AiwSealedRelease {
    param([Parameter(Mandatory)][string]$VersionDirectory,[Parameter(Mandatory)][string]$Version)
    $manifestDoc=Read-AiwStrictJson (Join-Path $VersionDirectory 'RELEASE_MANIFEST.json') 'RELEASE_MANIFEST'
    $manifest=$manifestDoc.Value
    if([string]$manifest.version-cne$Version-or[string]$manifest.lifecycle-cne'STABLE'-or[string]$manifest.sourceReview-cne'APPROVED'-or[string]$manifest.canonical-cnotmatch'^[A-F0-9]{64}$'){throw 'FRAMEWORK_RELEASE_NOT_SEALED'}
    $paths=@(Get-ChildItem -LiteralPath $VersionDirectory -Recurse -File -Force|Where-Object{$_.FullName-cne$manifestDoc.Path}|ForEach-Object{$_.FullName.Substring($VersionDirectory.Length+1).Replace('\','/')})
    [Array]::Sort($paths,[StringComparer]::Ordinal)
    $rows=@();[int64]$total=0
    foreach($relative in $paths){$full=Join-Path $VersionDirectory $relative;$identity=(Get-AiwFileIdentity $full).Split('|');$total+=[int64]$identity[0];$rows+=($relative+'|'+$identity[0]+'|'+$identity[1])}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:Utf8Strict.GetBytes(($rows-join"`n"))))
    if([int64]$manifest.fileCount-ne$paths.Count-or[int64]$manifest.totalBytes-ne$total-or[string]$manifest.canonical-cne$canonical){throw 'FRAMEWORK_RELEASE_MANIFEST_DRIFT'}
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
    if($text.Contains("`r")-or-not$text.EndsWith("`n")){throw 'BOOTSTRAP_TEXT_FORMAT'}
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
        $trimmed -ceq 'Project-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.'
    return [pscustomobject]@{ Identity=$identity; Text=$body; HasNormativeContent=(-not $defaultOnly) }
}

function Get-AiwProcessBindingSnapshot {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][string]$TargetVersion,
        [Parameter(Mandatory)][string]$TaskRelativePath
    )
    $project=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
    $framework=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FrameworkRoot)))
    $taskRelative=ConvertTo-AiwSafeRelativePath $TaskRelativePath 'TASK_LOCATOR'
    if(-not $taskRelative.StartsWith('.ai-workspace/tasks/',[StringComparison]::Ordinal)){throw 'TASK_LOCATOR_SCOPE'}
    $taskPath=Resolve-AiwChildFile $project $taskRelative 'TASK'
    $configPath=Resolve-AiwChildFile $project '.ai-workspace/project.json' 'PROJECT_CONFIG'
    $configDoc=Read-AiwStrictJson $configPath 'PROJECT_CONFIG';$config=$configDoc.Value
    $versionDirectory=Join-Path $framework ('framework/versions/'+$TargetVersion)
    $versionPath=Resolve-AiwChildFile $framework ('framework/versions/'+$TargetVersion+'/VERSION.json') 'FRAMEWORK_VERSION'
    $manifestPath=Resolve-AiwChildFile $framework ('framework/versions/'+$TargetVersion+'/RELEASE_MANIFEST.json') 'RELEASE_MANIFEST'
    $catalogPath=Resolve-AiwChildFile $framework ('framework/versions/'+$TargetVersion+'/PROCESS_REQUIREMENTS.json') 'PROCESS_REQUIREMENTS'
    $coveragePath=Resolve-AiwChildFile $framework ('framework/versions/'+$TargetVersion+'/CORRECTION_COVERAGE.json') 'CORRECTION_COVERAGE'
    $correctionsPath=Resolve-AiwChildFile $project '.ai-workspace/corrections.json' 'CORRECTIONS' -AllowMissing
    $controllerPath=Resolve-AiwChildFile $project '.ai-workspace/controller.json' 'CONTROLLER' -AllowMissing
    $bootstrapPath=Resolve-AiwChildFile $project '.ai-workspace/BOOTSTRAP.md' 'BOOTSTRAP'
    $custom=Get-AiwProjectCustomRegion $bootstrapPath
    $policyIdentity='MISSING'
    if($null-ne$config.PSObject.Properties['processPolicy']){
        Assert-AiwExactFields $config.processPolicy @('schemaVersion','locator') 'PROCESS_POLICY_LOCATOR'
        if([int]$config.processPolicy.schemaVersion-ne1){throw 'PROCESS_POLICY_LOCATOR_SCHEMA'}
        $policyLocator=ConvertTo-AiwSafeRelativePath ([string]$config.processPolicy.locator) 'PROCESS_POLICY_LOCATOR'
        if($policyLocator-cne'.ai-workspace/process-policy.json'){throw 'PROCESS_POLICY_LOCATOR_CANONICAL'}
        $policyIdentity=Get-AiwFileIdentity (Resolve-AiwChildFile $project $policyLocator 'PROCESS_POLICY')
    }
    return [pscustomobject]@{
        projectConfigIdentity=$configDoc.Identity
        controllerIdentity=$(if($null-eq$controllerPath){'MISSING'}else{Get-AiwFileIdentity $controllerPath})
        correctionsIdentity=$(if($null-eq$correctionsPath){'MISSING'}else{Get-AiwFileIdentity $correctionsPath})
        policyIdentity=$policyIdentity
        projectCustomIdentity=$custom.Identity
        taskIdentity=Get-AiwFileIdentity $taskPath
        frameworkVersionIdentity=Get-AiwFileIdentity $versionPath
        releaseManifestIdentity=Get-AiwFileIdentity $manifestPath
        nativeCatalogIdentity=Get-AiwFileIdentity $catalogPath
        correctionCoverageIdentity=Get-AiwFileIdentity $coveragePath
    }
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
    Assert-AiwExactFields $Selectors $names $Label
    foreach($name in $names){Assert-AiwStringArray $Selectors.$name ($Label+'_'+$name)}
    foreach($value in @($Selectors.profiles)){if([string]$value-cnotin@('*','MICRO','STANDARD','CRITICAL')){throw "${Label}_PROFILE"}}
    foreach($value in @($Selectors.roles)){if([string]$value-cnotin@('*','CONTROLLER','DOMAIN_OWNER','EXECUTOR','REVIEWER','FRAMEWORK_MAINTAINER')){throw "${Label}_ROLE"}}
    foreach($value in @($Selectors.phases)){if([string]$value-cnotin@('*','DISCOVER','PLAN','IMPLEMENT','VERIFY','REVIEW','GIT','EXTERNAL','RECOVER')){throw "${Label}_PHASE"}}
    foreach($value in @($Selectors.actionKinds)){if([string]$value-cnotmatch '^(\*|NONE|CONTROL_WRITE|SOURCE_WRITE|TEST_WRITE|TEST_RUN|REVIEW_ROUTE|REVIEW_EXECUTE|OWNER_ACCEPT|GIT_STAGE|GIT_COMMIT|PUSH|BROWSER_RUN|DEVICE_RUN|EXTERNAL)$'){throw "${Label}_ACTION"}}
    foreach($value in @($Selectors.resultKinds)){if([string]$value-cnotmatch '^(\*|NONE|PLAN|USER_RESPONSE|TERMINAL|HANDOFF|REVIEW_VERDICT|OWNER_ACCEPTANCE|IMPLEMENTATION_RESULT|TEST_RESULT|GIT_RESULT|EXTERNAL_RESULT)$'){throw "${Label}_RESULT"}}
    foreach($value in @($Selectors.pathPrefixes)){if([string]$value-cne([string]$value).Replace('\','/')-or[IO.Path]::IsPathRooted([string]$value)-or([string]$value).Contains('..')){throw "${Label}_PATH"}}
}

function Test-AiwRuleMatch {
    param($Selectors,[string]$Profile,[string]$Role,[string]$Phase,[string]$ActionKind,[string]$ResultKind,[string[]]$Paths,[string[]]$Capabilities,[string]$Objective,[bool]$SemanticApplicabilityUnknown)
    if (-not (Test-AiwSelectorValue @($Selectors.profiles) $Profile)) { return [pscustomobject]@{Match=$false;Semantic='NOT_EVALUATED'} }
    if (-not (Test-AiwSelectorValue @($Selectors.roles) $Role)) { return [pscustomobject]@{Match=$false;Semantic='NOT_EVALUATED'} }
    if (-not (Test-AiwSelectorValue @($Selectors.phases) $Phase)) { return [pscustomobject]@{Match=$false;Semantic='NOT_EVALUATED'} }
    if (-not (Test-AiwSelectorValue @($Selectors.actionKinds) $ActionKind)) { return [pscustomobject]@{Match=$false;Semantic='NOT_EVALUATED'} }
    if (-not (Test-AiwSelectorValue @($Selectors.resultKinds) $ResultKind)) { return [pscustomobject]@{Match=$false;Semantic='NOT_EVALUATED'} }
    foreach ($required in @($Selectors.capabilities)) { if ([string]$required -cne '*' -and [string]$required -cnotin $Capabilities) { return [pscustomobject]@{Match=$false;Semantic='NOT_EVALUATED'} } }
    if (@($Selectors.pathPrefixes).Count -gt 0 -and @($Selectors.pathPrefixes | Where-Object { $prefix=[string]$_; @($Paths | Where-Object { $_.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 }).Count -eq 0) { return [pscustomobject]@{Match=$false;Semantic='NOT_EVALUATED'} }
    $terms = @($Selectors.semanticTerms)
    if ($terms.Count -eq 0) { return [pscustomobject]@{Match=$true;Semantic='DETERMINISTIC'} }
    if (@($terms | Where-Object { $Objective.IndexOf([string]$_,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) { return [pscustomobject]@{Match=$true;Semantic='DESCRIPTION_MATCH'} }
    if ($SemanticApplicabilityUnknown) { return [pscustomobject]@{Match=$true;Semantic='UNKNOWN_CONSERVATIVE_LOAD'} }
    return [pscustomobject]@{Match=$false;Semantic='DESCRIPTION_NO_MATCH'}
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
        [switch]$SemanticApplicabilityUnknown,
        [switch]$AllowProjectPinMismatch,
        [switch]$UseDeclaredCapabilities,
        [switch]$EvaluationOnly
    )
    $project = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot)))
    $framework = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FrameworkRoot)))
    $configPath = Resolve-AiwChildFile $project '.ai-workspace/project.json' 'PROJECT_CONFIG'
    $configDoc = Read-AiwStrictJson $configPath 'PROJECT_CONFIG'
    if ($configDoc.Identity -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
    $config = $configDoc.Value
    if (-not $AllowProjectPinMismatch -and -not $EvaluationOnly -and [string]$config.frameworkVersion -cne $TargetVersion) { throw 'PROJECT_PIN_TARGET_MISMATCH' }
    $projectId = [string]$config.id
    Assert-AiwStringArray $Capabilities 'OBSERVED_CAPABILITIES'
    $declaredCapabilities=@()
    if($null-ne$config.PSObject.Properties['frameworkCapabilities']){
        if(-not($config.frameworkCapabilities-is[pscustomobject])){throw 'PROJECT_CAPABILITIES_TYPE'}
        foreach($property in @($config.frameworkCapabilities.PSObject.Properties)){
            if([string]$property.Name-cne'KNOWLEDGE_REFERENCE'-or-not($property.Value-is[pscustomobject])-or$null-eq$property.Value.PSObject.Properties['enabled']-or-not($property.Value.enabled-is[bool])){throw 'PROJECT_CAPABILITIES_VALUES'}
            if([bool]$property.Value.enabled){$declaredCapabilities+=[string]$property.Name}
        }
    }
    $declaredSorted=@($declaredCapabilities|Sort-Object)
    if($UseDeclaredCapabilities){$Capabilities=@($declaredSorted)}else{$observedSorted=@($Capabilities|Sort-Object);if([string]::Join("`n",$declaredSorted)-cne[string]::Join("`n",$observedSorted)){throw 'PROJECT_CAPABILITY_DRIFT'}}

    $versionPath = Resolve-AiwChildFile $framework ("framework/versions/$TargetVersion/VERSION.json") 'FRAMEWORK_VERSION'
    $versionDoc = Read-AiwStrictJson $versionPath 'FRAMEWORK_VERSION'
    $versionObject = $versionDoc.Value
    if ([string]$versionObject.version -cne $TargetVersion) { throw 'FRAMEWORK_VERSION_MISMATCH' }
    $stable = [string]$versionObject.lifecycle -ceq 'STABLE' -and [bool]$versionObject.consumable -and [bool]$versionObject.projectPinEligible
    $candidateEvaluation = $EvaluationOnly -and [string]$versionObject.lifecycle -ceq 'CANDIDATE' -and -not [bool]$versionObject.consumable -and -not [bool]$versionObject.projectPinEligible
    if (-not $stable -and -not $candidateEvaluation) { throw 'FRAMEWORK_VERSION_NOT_ADMITTED' }
    $versionDirectory = Split-Path -Parent $versionPath
    if($stable){Assert-AiwSealedRelease $versionDirectory $TargetVersion}
    $releaseManifestDoc=Read-AiwStrictJson (Resolve-AiwChildFile $versionDirectory 'RELEASE_MANIFEST.json' 'RELEASE_MANIFEST') 'RELEASE_MANIFEST'
    $releaseManifestIdentity=$releaseManifestDoc.Identity
    $composerVersionPath=Resolve-AiwChildFile $framework ("framework/versions/$ComposerVersion/VERSION.json") 'COMPOSER_VERSION'
    $composerVersionDirectory=Split-Path -Parent $composerVersionPath
    if($ComposerVersion-cne$TargetVersion){$composerVersionDoc=Read-AiwStrictJson $composerVersionPath 'COMPOSER_VERSION';if([string]$composerVersionDoc.Value.version-cne$ComposerVersion-or[string]$composerVersionDoc.Value.lifecycle-cne'STABLE'-or-not[bool]$composerVersionDoc.Value.consumable-or-not[bool]$composerVersionDoc.Value.projectPinEligible){throw 'COMPOSER_VERSION_NOT_ADMITTED'};Assert-AiwSealedRelease $composerVersionDirectory $ComposerVersion}
    $catalogPath = Resolve-AiwChildFile $composerVersionDirectory 'PROCESS_REQUIREMENTS.json' 'PROCESS_REQUIREMENTS'
    $catalogDoc = Read-AiwStrictJson $catalogPath 'PROCESS_REQUIREMENTS'
    $catalog = $catalogDoc.Value
    Assert-AiwExactFields $catalog @('schemaVersion','frameworkVersion','catalogVersion','requirements') 'PROCESS_REQUIREMENTS'
    if ([int]$catalog.schemaVersion -ne 2 -or [string]$catalog.catalogVersion -cne '3' -or [string]$catalog.frameworkVersion -cne $ComposerVersion -or -not ($catalog.requirements -is [Array])) { throw 'PROCESS_REQUIREMENTS_VALUES' }
    $nativeById = @{}
    $nativeByAlias = @{}
    foreach ($requirement in @($catalog.requirements)) {
        Assert-AiwExactFields $requirement @('requirementId','legacyAliases','title','description','ownerModule','selectors','exactBlockLocator','preparationRequirements','resultRequirements') 'NATIVE_REQUIREMENT'
        $nativeId='framework:'+[string]$requirement.requirementId
        if ([string]$requirement.requirementId -cnotmatch '^PR_[A-Z0-9_]+$' -or $nativeById.ContainsKey($nativeId)) { throw 'NATIVE_REQUIREMENT_ID' }
        Assert-AiwStringArray $requirement.legacyAliases 'NATIVE_REQUIREMENT_ALIASES'
        Assert-AiwSelectorContract $requirement.selectors 'NATIVE_REQUIREMENT_SELECTORS'
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
        $corrections = $correctionsDoc.Value
        Assert-AiwExactFields $corrections @('schemaVersion','contractVersion','projectId','corrections') 'CORRECTIONS'
        if ([int]$corrections.schemaVersion -notin @(1,2) -or [string]$corrections.projectId -cne $projectId -or -not ($corrections.corrections -is [Array])) { throw 'CORRECTIONS_VALUES' }
        if ([int]$corrections.schemaVersion -eq 1 -and [string]$corrections.contractVersion -cne '1.10.0') { throw 'CORRECTIONS_CONTRACT' }
        if ([int]$corrections.schemaVersion -eq 2 -and [string]$corrections.contractVersion -cne $script:ProcessCarrierContractVersion) { throw 'CORRECTIONS_CONTRACT' }
        $seenCorrection = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($record in @($corrections.corrections)) {
            $v1Record = if ([int]$corrections.schemaVersion -eq 1) { $record } else { [pscustomobject][ordered]@{correctionId=$record.correctionId;introducedAgainstFramework=$record.introducedAgainstFramework;requirementReason=$record.requirementReason;effectiveRule=$record.effectiveRule;applicability=$record.applicability;decisionLocator=$record.decisionLocator} }
            $canonical = Get-AiwCanonicalCorrectionRecordIdentityV1 $v1Record
            if ([string]$record.correctionId -cnotmatch '^[A-Z][A-Z0-9_]*$' -or -not $seenCorrection.Add([string]$record.correctionId)) { throw 'CORRECTION_ID' }
            $v2Identity = 'NOT_APPLICABLE'
            if ([int]$corrections.schemaVersion -eq 2) {
                Assert-AiwExactFields $record @('correctionId','introducedAgainstFramework','requirementReason','effectiveRule','applicability','decisionLocator','selectors','preparationRequirements','resultRequirements','requiredFacts','mechanicalCheckRefs') 'CORRECTION_RECORD_V2'
                Assert-AiwSelectorContract $record.selectors 'CORRECTION_V2_SELECTORS'
                foreach ($name in @('preparationRequirements','resultRequirements','requiredFacts','mechanicalCheckRefs')) { Assert-AiwStringArray $record.$name ('CORRECTION_V2_' + $name) }
                $registeredChecks=@('CURRENT_AUTHORITY_BOUND','ACTION_PACKAGE_VALID','EXACT_SCOPE_BOUND','TASK_SCOPE_CURRENT','PROTECTION_BOUNDARY_PROVEN','REVIEWER_INDEPENDENCE_PROVEN','SAFE_GIT_STATE_PROVEN','EXTERNAL_BOUNDARY_AUTHORIZED','DOMAIN_EXTERNAL_PACKAGE_VALID','EXTERNAL_PAYLOAD_IDENTITIES_BOUND','USER_EXTERNAL_DECISION_BOUND')
                foreach ($check in @($record.mechanicalCheckRefs)) { if ([string]$check -cnotin $registeredChecks) { throw 'CORRECTION_V2_MECHANICAL_CHECK_UNREGISTERED' } }
                $v2Identity = Get-AiwCanonicalCorrectionRecordIdentityV2 $record
            }
            $records += [pscustomobject]@{ Record=$record; SchemaVersion=[int]$corrections.schemaVersion; Alias=('correction:'+$projectId+':'+[string]$record.correctionId); SourceRecordIdentity=$canonical; V2WholeRecordIdentity=$v2Identity }
        }
    }

    $mappedByAlias = @{}
    $conflicting = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $coverageStatus = 'UNAVAILABLE_RETAINED'
    $coveragePath=Resolve-AiwChildFile $composerVersionDirectory 'CORRECTION_COVERAGE.json' 'CORRECTION_COVERAGE'
    $coverageIdentity=Get-AiwFileIdentity $coveragePath
    try {
        $coverageDoc = Read-AiwStrictJson $coveragePath 'CORRECTION_COVERAGE'
        $coverage = $coverageDoc.Value
        Assert-AiwExactFields $coverage @('schemaVersion','releaseVersion','versions') 'CORRECTION_COVERAGE'
        if ([int]$coverage.schemaVersion -notin @(2,3) -or [string]$coverage.releaseVersion -cne $ComposerVersion -or -not ($coverage.versions -is [Array])) { throw 'CORRECTION_COVERAGE_VALUES' }
        $entry = @($coverage.versions | Where-Object { [string]$_.version -ceq $TargetVersion })
        if ($entry.Count -eq 1) {
            Assert-AiwExactFields $entry[0] @('version','releaseCanonical','incorporatedCorrectionIds','incorporationMappings','conflictingCorrectionIds') 'CORRECTION_COVERAGE_ENTRY'
            if(($ComposerVersion-ceq$TargetVersion-and[string]$entry[0].releaseCanonical-cne'SELF')-or($ComposerVersion-cne$TargetVersion-and[string]$entry[0].releaseCanonical-cne[string]$releaseManifestDoc.Value.canonical)){throw 'CORRECTION_COVERAGE_RELEASE_MISMATCH'}
            Assert-AiwStringArray $entry[0].incorporatedCorrectionIds 'LEGACY_INCORPORATED_IDS'
            Assert-AiwStringArray $entry[0].conflictingCorrectionIds 'CONFLICTING_CORRECTION_IDS'
            if (-not ($entry[0].incorporationMappings -is [Array])) { throw 'INCORPORATION_MAPPINGS_TYPE' }
            foreach ($id in @($entry[0].conflictingCorrectionIds)) { $null=$conflicting.Add([string]$id) }
            foreach ($mapping in @($entry[0].incorporationMappings)) {
                if ([int]$coverage.schemaVersion -eq 2) { Assert-AiwExactFields $mapping @('correctionId','legacyRequirementId','nativeRequirementId','coverageState','nativeCatalogIdentity','legacySourceRecordIdentity') 'INCORPORATION_MAPPING' }
                else { Assert-AiwExactFields $mapping @('correctionId','legacyRequirementId','nativeRequirementId','coverageState','nativeCatalogIdentity','sourceSchemaVersion','legacySourceRecordIdentity','v2WholeRecordIdentity') 'INCORPORATION_MAPPING' }
                if ([string]$mapping.coverageState -cne 'INCORPORATED' -or [string]$mapping.legacyRequirementId -cnotmatch '^correction:[a-z0-9][a-z0-9-]*:[A-Z][A-Z0-9_]*$' -or [string]$mapping.nativeRequirementId -cnotmatch '^framework:PR_[A-Z0-9_]+$' -or [string]$mapping.nativeCatalogIdentity -cne $catalogDoc.Identity -or [string]$mapping.legacySourceRecordIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { throw 'INCORPORATION_MAPPING_VALUES' }
                if ([int]$coverage.schemaVersion -eq 3 -and ([int]$mapping.sourceSchemaVersion -notin @(1,2) -or ([int]$mapping.sourceSchemaVersion -eq 1 -and [string]$mapping.v2WholeRecordIdentity -cne 'NOT_APPLICABLE') -or ([int]$mapping.sourceSchemaVersion -eq 2 -and [string]$mapping.v2WholeRecordIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$'))) { throw 'INCORPORATION_MAPPING_VALUES' }
                if (-not $nativeById.ContainsKey([string]$mapping.nativeRequirementId) -or -not $nativeByAlias.ContainsKey([string]$mapping.legacyRequirementId) -or [string]$nativeByAlias[[string]$mapping.legacyRequirementId] -cne [string]$mapping.nativeRequirementId) { throw 'CONFLICT_ALIAS_COVERAGE' }
                if ($mappedByAlias.ContainsKey([string]$mapping.legacyRequirementId)) { throw 'CONFLICT_ALIAS_COVERAGE' }
                $mappedByAlias[[string]$mapping.legacyRequirementId]=$mapping
            }
            $coverageStatus = $(if($entry[0].incorporationMappings.Count -gt 0){'MATCHED_EXACT_MAPPING'}elseif($ComposerVersion-cne$TargetVersion-and$entry[0].incorporatedCorrectionIds.Count-gt0){'LEGACY_ID_ONLY_RETAINED'}else{'NO_EXACT_MAPPING_RETAINED'})
        }
    } catch {
        if ([string]$_.Exception.Message -like 'CONFLICT_*') { throw }
        $mappedByAlias=@{}
        $coverageStatus = 'INVALID_RETAINED'
    }

    $legacyEffective = @(); $legacyIncorporated = @(); $legacyConflicts = @()
    $sourceIdentityMismatch = @()
    foreach ($item in $records) {
        $view = [ordered]@{correctionId=[string]$item.Record.correctionId;requirementReason=[string]$item.Record.requirementReason;effectiveRule=[string]$item.Record.effectiveRule;applicability=[string]$item.Record.applicability;decisionLocator=[string]$item.Record.decisionLocator;sourceSchemaVersion=[int]$item.SchemaVersion;legacyRequirementId=[string]$item.Alias;legacySourceRecordIdentity=[string]$item.SourceRecordIdentity;v2WholeRecordIdentity=[string]$item.V2WholeRecordIdentity}
        if ($conflicting.Contains([string]$item.Record.correctionId)) { $legacyConflicts += [pscustomobject]$view }
        elseif ($mappedByAlias.ContainsKey([string]$item.Alias)) {
            $mapping=$mappedByAlias[[string]$item.Alias]
            if ([string]$mapping.correctionId -cne [string]$item.Record.correctionId) { throw 'CONFLICT_ALIAS_COVERAGE' }
            $mappingV2Matches = if ($null -eq $mapping.PSObject.Properties['v2WholeRecordIdentity']) { [int]$item.SchemaVersion -eq 1 } else { [string]$mapping.v2WholeRecordIdentity -ceq [string]$item.V2WholeRecordIdentity }
            $mappingSchemaMatches = if ($null -eq $mapping.PSObject.Properties['sourceSchemaVersion']) { [int]$item.SchemaVersion -eq 1 } else { [int]$mapping.sourceSchemaVersion -eq [int]$item.SchemaVersion }
            if ([string]$mapping.legacySourceRecordIdentity -ceq [string]$item.SourceRecordIdentity -and $mappingV2Matches -and $mappingSchemaMatches) {
                $view.nativeRequirementId=[string]$mapping.nativeRequirementId
                $legacyIncorporated += [pscustomobject]$view
            } else {
                $legacyEffective += [pscustomobject]$view
                $sourceIdentityMismatch += [string]$item.Alias
            }
        } else { $legacyEffective += [pscustomobject]$view }
    }

    $bootstrapPath = Resolve-AiwChildFile $project '.ai-workspace/BOOTSTRAP.md' 'BOOTSTRAP'
    $custom = Get-AiwProjectCustomRegion $bootstrapPath
    $policyRules = @(); $policyIdentity='MISSING'; $policyLocator='NONE'
    if ($null -ne $config.PSObject.Properties['processPolicy']) {
        Assert-AiwExactFields $config.processPolicy @('schemaVersion','locator') 'PROCESS_POLICY_LOCATOR'
        if ([int]$config.processPolicy.schemaVersion -ne 1) { throw 'PROCESS_POLICY_LOCATOR_SCHEMA' }
        $policyLocator = ConvertTo-AiwSafeRelativePath ([string]$config.processPolicy.locator) 'PROCESS_POLICY_LOCATOR'
        if ($policyLocator -cne '.ai-workspace/process-policy.json') { throw 'PROCESS_POLICY_LOCATOR_CANONICAL' }
        $policyPath = Resolve-AiwChildFile $project $policyLocator 'PROCESS_POLICY'
        $policyDoc = Read-AiwStrictJson $policyPath 'PROCESS_POLICY'
        $policyIdentity = $policyDoc.Identity
        $policy = $policyDoc.Value
        Assert-AiwExactFields $policy @('schemaVersion','contractVersion','projectId','rules') 'PROCESS_POLICY'
        if ([int]$policy.schemaVersion -ne 1 -or [string]$policy.contractVersion -cne $script:ProcessCarrierContractVersion -or [string]$policy.projectId -cne $projectId -or -not ($policy.rules -is [Array])) { throw 'PROCESS_POLICY_VALUES' }
        $policyRules = @($policy.rules)
    }
    foreach ($rule in $policyRules) {
        Assert-AiwExactFields $rule @('ruleId','requirementReason','effectiveRule','selectors','preparationRequirements','resultRequirements','decisionLocator') 'PROCESS_POLICY_RULE'
        if ([string]$rule.ruleId -cnotmatch '^[A-Z][A-Z0-9_]*$') { throw 'PROCESS_POLICY_RULE_ID' }
        Assert-AiwSelectorContract $rule.selectors 'PROCESS_POLICY_SELECTORS'
        Assert-AiwStringArray $rule.preparationRequirements 'PROCESS_POLICY_PREPARATION'
        Assert-AiwStringArray $rule.resultRequirements 'PROCESS_POLICY_RESULT'
        foreach($field in @('requirementReason','effectiveRule','decisionLocator')){if(-not($rule.$field-is[string])-or[string]::IsNullOrWhiteSpace([string]$rule.$field)){throw 'PROCESS_POLICY_TEXT'}}
    }
    $effectiveRuleOwners=@{}
    foreach($entry in (@($legacyEffective|ForEach-Object{[pscustomobject]@{Source='PROJECT_CORRECTION';Id=[string]$_.legacyRequirementId;Text=[string]$_.effectiveRule}})+@($policyRules|ForEach-Object{[pscustomobject]@{Source='PROJECT_POLICY';Id=[string]$_.ruleId;Text=[string]$_.effectiveRule}})+$(if($custom.HasNormativeContent){@([pscustomobject]@{Source='LEGACY_PROJECT_CUSTOM';Id=('project-custom:'+$projectId);Text=[string]$custom.Text})}else{@()}))){
        $normalized=([string]$entry.Text).Replace("`r`n","`n").Replace("`r","`n").Trim()
        $identity=$script:Utf8Strict.GetByteCount($normalized).ToString()+'|'+(Get-AiwSha256Hex $script:Utf8Strict.GetBytes($normalized))
        if($effectiveRuleOwners.ContainsKey($identity)){throw ('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE|'+[string]$effectiveRuleOwners[$identity]+'|'+[string]$entry.Source)}
        $effectiveRuleOwners[$identity]=[string]$entry.Source+':'+[string]$entry.Id
    }

    $selected = @(); $seenRequirement = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal); $ownerTextCache=@{}
    foreach ($requirement in @($catalog.requirements)) {
        $id='framework:'+[string]$requirement.requirementId
        if (-not $seenRequirement.Add($id)) { throw 'NATIVE_REQUIREMENT_ID' }
        $match=Test-AiwRuleMatch $requirement.selectors $Profile $Role $Phase $ActionKind $ResultKind $ExactPaths $Capabilities $Objective ([bool]$SemanticApplicabilityUnknown)
        if ($match.Match) {
            $origins=@($legacyIncorporated|Where-Object{[string]$_.nativeRequirementId-ceq$id}|ForEach-Object{[pscustomobject]@{legacyRequirementId=[string]$_.legacyRequirementId;legacySourceRecordIdentity=[string]$_.legacySourceRecordIdentity}})
            $blockText=Get-AiwNativeRuleBlock -VersionDirectory $composerVersionDirectory -OwnerModule ([string]$requirement.ownerModule) -RequirementId ([string]$requirement.requirementId) -ExactBlockLocator ([string]$requirement.exactBlockLocator) -OwnerTextCache $ownerTextCache
            $selected += [pscustomobject]@{requirementId=$id;source='FRAMEWORK';ownerModule=[string]$requirement.ownerModule;sourceAliases=@($origins);semanticApplicability=$match.Semantic;fullText=$blockText;preparationRequirements=@($requirement.preparationRequirements);resultRequirements=@($requirement.resultRequirements)}
        }
    }
    foreach ($item in $legacyEffective) {
        if ([int]$item.sourceSchemaVersion -eq 1) {
            $selected += [pscustomobject]@{requirementId=[string]$item.legacyRequirementId;source='PROJECT_CORRECTION';ownerModule='PROJECT_CORRECTIONS_V1';semanticApplicability='LEGACY_PROGRESSIVE_SELECTION_UNPROVEN';fullText=[string]$item.effectiveRule;preparationRequirements=@();resultRequirements=@()}
        } else {
            $record=@($records|Where-Object{[string]$_.Alias-ceq[string]$item.legacyRequirementId})[0].Record
            $match=Test-AiwRuleMatch $record.selectors $Profile $Role $Phase $ActionKind $ResultKind $ExactPaths $Capabilities $Objective ([bool]$SemanticApplicabilityUnknown)
            if ($match.Match) {
                $prep=@($record.preparationRequirements)+@($record.requiredFacts)+@($record.mechanicalCheckRefs)
                $selected += [pscustomobject]@{requirementId=[string]$item.legacyRequirementId;source='PROJECT_CORRECTION';ownerModule='PROJECT_CORRECTIONS_V2';semanticApplicability=$match.Semantic;fullText=[string]$item.effectiveRule;preparationRequirements=@($prep|Sort-Object -Unique);resultRequirements=@($record.resultRequirements)}
            }
        }
    }
    foreach ($rule in $policyRules) {
        $id='project:'+$projectId+':'+[string]$rule.ruleId
        if ([string]$rule.ruleId -cnotmatch '^[A-Z][A-Z0-9_]*$' -or -not $seenRequirement.Add($id)) { throw 'PROCESS_POLICY_RULE_ID' }
        $match=Test-AiwRuleMatch $rule.selectors $Profile $Role $Phase $ActionKind $ResultKind $ExactPaths $Capabilities $Objective ([bool]$SemanticApplicabilityUnknown)
        if ($match.Match) { $selected += [pscustomobject]@{requirementId=$id;source='PROJECT_POLICY';ownerModule='PROJECT_PROCESS_POLICY';semanticApplicability=$match.Semantic;fullText=[string]$rule.effectiveRule;preparationRequirements=@($rule.preparationRequirements);resultRequirements=@($rule.resultRequirements)} }
    }
    if ($custom.HasNormativeContent) {
        $selected += [pscustomobject]@{requirementId=('project-custom:'+$projectId);source='LEGACY_PROJECT_CUSTOM';ownerModule='BOOTSTRAP_PROJECT_CUSTOM';semanticApplicability='LEGACY_PROGRESSIVE_SELECTION_UNPROVEN';fullText=$custom.Text;preparationRequirements=@();resultRequirements=@()}
    }
    if ($legacyConflicts.Count -gt 0) { throw 'PROJECT_CORRECTION_CONFLICT' }

    $sourceMaterial = @(
        "framework=$TargetVersion",
        "composer=$ComposerVersion",
        "version=$($versionDoc.Identity)",
        "manifest=$releaseManifestIdentity",
        "catalog=$($catalogDoc.Identity)",
        "coverage=$coverageIdentity",
        "project=$($configDoc.Identity)",
        "controller=$controllerIdentity",
        "corrections=$correctionsIdentity",
        "policy=$policyIdentity",
        "custom=$($custom.Identity)",
        "task=$TaskIdentity",
        "actor=$Actor", "role=$Role", "phase=$Phase", "profile=$Profile",
        "capabilities=$([string]::Join(',',@($Capabilities|Sort-Object)))"
    ) -join "`n"
    $sourceKey=Get-AiwSha256Hex $script:Utf8Strict.GetBytes($sourceMaterial)
    $evidenceCeilings=@()
    if(@($legacyEffective|Where-Object{[int]$_.sourceSchemaVersion-eq1}).Count-gt0){$evidenceCeilings+='LEGACY_CORRECTIONS_FULL_LOAD'}
    if($sourceIdentityMismatch.Count-gt0){$evidenceCeilings+='SOURCE_RECORD_IDENTITY_MISMATCH_RETAINED'}
    if($custom.HasNormativeContent){$evidenceCeilings+='LEGACY_PROJECT_CUSTOM_FULL_LOAD'}
    return [pscustomobject]@{
        status=$(if($candidateEvaluation){'EVALUATION_ONLY'}else{'PASS'}); projectId=$projectId; targetVersion=$TargetVersion; sourceCompositionIdentity=$sourceKey
        projectConfigIdentity=$configDoc.Identity; controllerIdentity=$controllerIdentity; correctionsIdentity=$correctionsIdentity; policyIdentity=$policyIdentity; projectCustomIdentity=$custom.Identity
        frameworkVersionIdentity=$versionDoc.Identity; releaseManifestIdentity=$releaseManifestIdentity; nativeCatalogIdentity=$catalogDoc.Identity; correctionCoverageIdentity=$coverageIdentity
        coverageStatus=$coverageStatus; incorporated=@($legacyIncorporated); stillEffective=@($legacyEffective); conflicts=@($legacyConflicts)
        selectedRequirements=@($selected); evidenceCeilings=@($evidenceCeilings)
        sourceBuildCount=1; legacyCorrectionsFullReadCount=$(if(@($legacyEffective|Where-Object{[int]$_.sourceSchemaVersion-eq1}).Count-gt0){1}else{0}); legacyProjectCustomFullReadCount=$(if($custom.HasNormativeContent){1}else{0})
    }
}

Export-ModuleMember -Function Invoke-ProcessRequirementComposition,Get-AiwCanonicalCorrectionRecordIdentityV1,Get-AiwCanonicalCorrectionRecordIdentityV2,Get-AiwFileIdentity,Get-AiwProcessBindingSnapshot
