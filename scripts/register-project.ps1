[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$FrameworkVersion,

    [string]$ControllerId,

    [ValidateRange(1, 98304)]
    [int]$SelectedRulePackBytes = 32768,

    [ValidateSet('repo-local','framework-maintenance-sibling')]
    [string]$ControlPlaneLayout = 'repo-local',

    [string]$FrameworkTargetRepositoryId,

    [string]$FrameworkTargetSiblingDirectory,

    [string[]]$FrameworkTargetRoutineExcludedPath = @(),

    [switch]$Apply,

    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$script:ActiveAdoptionProfile = $null
$script:ActiveTargetCapabilityContract = $null
$maintenanceModulePath=Join-Path $PSScriptRoot 'MaintenanceOverlay.psm1'
if(-not(Test-Path -LiteralPath $maintenanceModulePath -PathType Leaf)){throw 'MAINTENANCE_OVERLAY_MODULE_MISSING'}
Import-Module $maintenanceModulePath -Force
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionProjection.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1') -ErrorAction Stop

function Join-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if([string]::IsNullOrWhiteSpace($RelativePath)-or$RelativePath-cne$RelativePath.Replace('\','/')-or[IO.Path]::IsPathRooted($RelativePath)-or$RelativePath.StartsWith('/')-or$RelativePath.Contains(':')-or-not[string]::Equals($RelativePath,$RelativePath.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)){throw 'CHILD_PATH_INVALID'}
    $segments=$RelativePath.Split('/')
    foreach($segment in $segments){if([string]::IsNullOrWhiteSpace($segment)-or$segment-in@('.','..')-or$segment.EndsWith('.')-or$segment.EndsWith(' ')-or[regex]::IsMatch($segment,'[\x00-\x1F]')){throw 'CHILD_PATH_INVALID'}}
    $result = $Root
    foreach ($segment in $segments) {
        $result = Join-Path $result $segment
    }
    return $result
}

function Read-StrictUtf8Template {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "File must be UTF-8 without BOM: $Path"
    }
    try {
        $content = $utf8Strict.GetString($bytes)
    }
    catch {
        throw "File is not strict UTF-8: $Path"
    }
    if ($content.Contains([char]0) -or $content.Contains([char]0xFFFD)) {
        throw "File contains a forbidden text code point: $Path"
    }
    if ($content.Contains("`r")) {
        throw "File must use LF line endings: $Path"
    }
    if (-not $content.EndsWith("`n")) {
        throw "File must end with LF: $Path"
    }
    return $content
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $normalized = $Content -replace "`r`n", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Get-AdoptionProfile([string]$FrameworkPath,[string]$ExpectedVersion) {
    $path=Join-ChildPath $FrameworkPath 'ADOPTION_PROFILE.json'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'ADOPTION_PROFILE_REQUIRED_FOR_SUPPORTED_BASELINE'}
    $raw=Read-StrictUtf8Template $path
    try{$profile=$raw|ConvertFrom-Json}catch{throw 'ADOPTION_PROFILE_JSON'}
    Assert-ExactObjectFields $profile $raw @('schemaVersion','frameworkVersion','registrationEligible','localCandidatePilotEligible','sourceCompatibility','projectControl','processBudget') 'Framework ADOPTION_PROFILE.json'
    Assert-ExactObjectFields $profile.sourceCompatibility ($profile.sourceCompatibility|ConvertTo-Json -Compress) @('projectFormats','requiredCapabilities') 'Framework ADOPTION_PROFILE.json sourceCompatibility'
    Assert-ExactObjectFields $profile.projectControl ($profile.projectControl|ConvertTo-Json -Compress) @('schemaVersion','processCarrierContractVersion','frameworkToolBackend','navigationProjection','taskLastWriteRequired','capabilityBinding','runtimeArtifactRoot','runtimeGitIgnoreRule') 'Framework ADOPTION_PROFILE.json projectControl'
    Assert-ExactObjectFields $profile.processBudget ($profile.processBudget|ConvertTo-Json -Compress) @('defaultSelectedRulePackBytes','absoluteSelectedRulePackBytes') 'Framework ADOPTION_PROFILE.json processBudget'
    $formats=@($profile.sourceCompatibility.projectFormats|ForEach-Object{[string]$_});$requiredCapabilities=@($profile.sourceCompatibility.requiredCapabilities|ForEach-Object{[string]$_})
    if(-not(Test-JsonInteger $profile.schemaVersion)-or[int]$profile.schemaVersion-ne2-or[string]$profile.frameworkVersion-cne$ExpectedVersion-or-not($profile.registrationEligible-is[bool])-or-not($profile.localCandidatePilotEligible-is[bool])-or-not[bool]$profile.localCandidatePilotEligible-or-not($profile.sourceCompatibility.projectFormats-is[Array])-or$formats.Count-gt16-or@($formats|Select-Object -Unique).Count-ne$formats.Count-or@($formats|Where-Object{$_-cnotmatch'^[a-z0-9-]+/[a-z0-9-]+$'}).Count-ne0-or-not($profile.sourceCompatibility.requiredCapabilities-is[Array])-or$requiredCapabilities.Count-gt32-or@($requiredCapabilities|Select-Object -Unique).Count-ne$requiredCapabilities.Count-or@($requiredCapabilities|Where-Object{$_-cnotmatch'^[A-Z][A-Z0-9_]*$'}).Count-ne0-or($formats.Count-eq0-and$requiredCapabilities.Count-ne0)-or-not(Test-JsonInteger $profile.projectControl.schemaVersion)-or[int]$profile.projectControl.schemaVersion-ne4-or[string]$profile.projectControl.processCarrierContractVersion-cne$ExpectedVersion-or[string]$profile.projectControl.frameworkToolBackend-cne'powershell7'-or[string]$profile.projectControl.navigationProjection-cne'ROOT_CANONICAL_SKILL_MANAGED_AGENTS'-or-not($profile.projectControl.taskLastWriteRequired-is[bool])-or-not[bool]$profile.projectControl.taskLastWriteRequired-or[string]$profile.projectControl.capabilityBinding-cne'EXACT_ENABLED_IDS'-or[string]$profile.projectControl.runtimeArtifactRoot-cne'.ai-workspace/runtime'-or[string]$profile.projectControl.runtimeGitIgnoreRule-cne'/.ai-workspace/runtime/'-or-not(Test-JsonInteger $profile.processBudget.defaultSelectedRulePackBytes)-or[int]$profile.processBudget.defaultSelectedRulePackBytes-ne32768-or-not(Test-JsonInteger $profile.processBudget.absoluteSelectedRulePackBytes)-or[int]$profile.processBudget.absoluteSelectedRulePackBytes-ne98304){throw 'ADOPTION_PROFILE_VALUES'}
    return $profile
}

function Test-AdoptionProfileVersion([string]$Version){return $null-ne$script:ActiveAdoptionProfile-and[string]$script:ActiveAdoptionProfile.frameworkVersion-ceq$Version}

function Get-ProcessCarrierContractVersion([string]$FrameworkVersion) {
    if(-not(Test-AdoptionProfileVersion $FrameworkVersion)){throw 'ADOPTION_PROFILE_VERSION_UNBOUND'}
    return [string]$script:ActiveAdoptionProfile.projectControl.processCarrierContractVersion
}

function Assert-ExactObjectFields($Object,[string]$Raw,[string[]]$Expected,[string]$Label) {
    if (-not ($Object -is [pscustomobject])) { throw "$Label must be a JSON object." }
    $names = @($Object.PSObject.Properties.Name)
    if ($names.Count -ne $Expected.Count -or @($Expected | Where-Object { $_ -cnotin $names }).Count -ne 0) { throw "$Label field set mismatch." }
    foreach ($name in $Expected) {
        $expectedCount=if($name-ceq'schemaVersion'-and(('processPolicy'-cin$names)-or('routerCompatibility'-cin$names)-or('projectControl'-cin$names))){2}elseif($name-ceq'routineExcludedPaths'-and'frameworkTarget'-cin$names){2}else{1}
        if ([regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne $expectedCount) { throw "$Label duplicate or missing field: $name" }
    }
}

function ConvertTo-FrameworkLocator([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) { throw 'Framework capability locator is empty or has outer whitespace.' }
    $path=$Value.Replace('\','/')
    if ([regex]::IsMatch($path,'[<>"|?*]') -or [IO.Path]::IsPathRooted($path) -or $path.StartsWith('/') -or $path.Contains(':')) { throw 'Framework capability locator must be a repo-relative literal path.' }
    if (-not [string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw 'Framework capability locator must be NFC.' }
    $parts=$path.Split('/')
    foreach($part in $parts){
        if([string]::IsNullOrEmpty($part)-or$part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or[regex]::IsMatch($part,'[\x00-\x1F]')){throw 'Framework capability locator has an invalid component.'}
        if($part.Split('.')[0]-match'^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw 'Framework capability locator has a reserved component.'}
    }
    return [string]::Join('/',$parts)
}

function Assert-FrameworkCapabilities($Capabilities,[string]$Raw,[string]$Label) {
    if ($null -ne $script:ActiveTargetCapabilityContract) {
        Assert-TargetFrameworkCapabilities $Capabilities $Raw $script:ActiveTargetCapabilityContract
        return
    }
    if (-not ($Capabilities -is [pscustomobject])) { throw "$Label must be an object." }
    $names=@($Capabilities.PSObject.Properties|ForEach-Object{$_.Name})
    if($names.Count-eq0){return}
    foreach($name in $names){$value=$Capabilities.PSObject.Properties[$name].Value;if($name-cnotmatch'^[A-Z][A-Z0-9_]*$'-or[regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count-ne1-or-not($value-is[pscustomobject])-or$null-eq$value.PSObject.Properties['enabled']-or-not($value.enabled-is[bool])){throw "$Label contains an invalid capability declaration."}}
}

function Get-TargetFrameworkCapabilityContract([string]$FrameworkPath,[string]$Layout='repo-local') {
    if($Layout-cnotin@('repo-local','framework-maintenance-sibling')){throw 'TARGET_CONTROL_PLANE_LAYOUT'}
    $schemaPath=if($Layout-ceq'framework-maintenance-sibling'){if($null-eq$maintenanceOverlay){throw 'TARGET_MAINTENANCE_SCHEMA_UNAVAILABLE'};[string]$maintenanceOverlay.ProjectConfigSchemaPath}else{Join-ChildPath $FrameworkPath 'PROJECT_CONFIG_SCHEMA.json'}
    $raw=Read-StrictUtf8Template $schemaPath
    try{$schema=$raw|ConvertFrom-Json}catch{throw 'TARGET_PROJECT_CONFIG_SCHEMA_JSON'}
    if(-not($schema-is[pscustomobject])-or$null-eq$schema.PSObject.Properties['properties']-or-not($schema.properties-is[pscustomobject])-or$null-eq$schema.properties.PSObject.Properties['frameworkCapabilities']){throw 'TARGET_CAPABILITY_SCHEMA_MISSING'}
    $capabilities=$schema.properties.frameworkCapabilities
    if(-not($capabilities-is[pscustomobject])-or[string]$capabilities.type-cne'object'-or-not($capabilities.additionalProperties-is[bool])-or[bool]$capabilities.additionalProperties){throw 'TARGET_CAPABILITY_SCHEMA_OPEN_OR_INVALID'}
    if($Layout-ceq'framework-maintenance-sibling'){
        if(-not(Test-JsonInteger $capabilities.maxProperties)-or[int]$capabilities.maxProperties-ne0-or$null-ne$capabilities.PSObject.Properties['properties']){throw 'TARGET_CAPABILITY_SCHEMA_UNSUPPORTED'}
        return [pscustomobject]@{AllowedNames=@()}
    }
    if(-not($capabilities.properties-is[pscustomobject])){throw 'TARGET_CAPABILITY_SCHEMA_OPEN_OR_INVALID'}
    [string[]]$names=@($capabilities.properties.PSObject.Properties.Name);[Array]::Sort($names,[StringComparer]::Ordinal)
    if($names.Count-ne1-or$names[0]-cne'KNOWLEDGE_REFERENCE'){throw 'TARGET_CAPABILITY_SCHEMA_UNSUPPORTED'}
    $knowledge=$capabilities.properties.KNOWLEDGE_REFERENCE;$variants=@($knowledge.oneOf)
    $falseVariants=@($variants|Where-Object{$_-is[pscustomobject]-and[string]$_.type-ceq'object'-and$_.additionalProperties-is[bool]-and-not[bool]$_.additionalProperties-and[string]::Join('|',@($_.required))-ceq'enabled'-and$_.properties.enabled.const-is[bool]-and-not[bool]$_.properties.enabled.const})
    $trueVariants=@($variants|Where-Object{$_-is[pscustomobject]-and[string]$_.type-ceq'object'-and$_.additionalProperties-is[bool]-and-not[bool]$_.additionalProperties-and[string]::Join('|',@($_.required))-ceq'enabled|indexLocator'-and$_.properties.enabled.const-is[bool]-and[bool]$_.properties.enabled.const-and[string]$_.properties.indexLocator.type-ceq'string'-and[int]$_.properties.indexLocator.minLength-eq1})
    if($variants.Count-ne2-or$falseVariants.Count-ne1-or$trueVariants.Count-ne1){throw 'TARGET_CAPABILITY_SCHEMA_UNSUPPORTED'}
    return [pscustomobject]@{AllowedNames=$names}
}

function Assert-TargetFrameworkCapabilities($Capabilities,[string]$Raw,$Contract) {
    if(-not($Capabilities-is[pscustomobject])){throw 'FRAMEWORK_CAPABILITIES_TYPE'}
    $names=@($Capabilities.PSObject.Properties|ForEach-Object{[string]$_.Name})
    if(@($names|Where-Object{$_-cnotin@($Contract.AllowedNames)}).Count-ne0-or@($names|Select-Object -Unique).Count-ne$names.Count){throw 'FRAMEWORK_CAPABILITIES_UNKNOWN_OR_DUPLICATE'}
    foreach($name in $names){if([regex]::Matches($Raw,'"'+[regex]::Escape([string]$name)+'"\s*:').Count-ne1){throw 'FRAMEWORK_CAPABILITIES_UNKNOWN_OR_DUPLICATE'}}
    if($names.Count-eq0){return}
    $knowledge=$Capabilities.KNOWLEDGE_REFERENCE
    if(-not($knowledge-is[pscustomobject])){throw 'KNOWLEDGE_CAPABILITY_TYPE'}
    $fields=@($knowledge.PSObject.Properties.Name)
    if($fields.Count-eq1-and$fields[0]-ceq'enabled'-and$knowledge.enabled-is[bool]-and-not[bool]$knowledge.enabled){if([regex]::Matches($Raw,'"enabled"\s*:').Count-ne1){throw 'KNOWLEDGE_CAPABILITY_DUPLICATE_FIELD'};return}
    if($fields.Count-ne2-or$fields-cnotcontains'enabled'-or$fields-cnotcontains'indexLocator'-or-not($knowledge.enabled-is[bool])-or-not[bool]$knowledge.enabled-or-not($knowledge.indexLocator-is[string])-or[regex]::Matches($Raw,'"enabled"\s*:').Count-ne1-or[regex]::Matches($Raw,'"indexLocator"\s*:').Count-ne1){throw 'KNOWLEDGE_CAPABILITY_FIELDS'}
    $null=ConvertTo-FrameworkLocator ([string]$knowledge.indexLocator)
}

function New-TemplateMap([string]$Version) {
    $map=[ordered]@{
        '.gitattributes'='.gitattributes'; 'project.json'='project.json'; 'BOOTSTRAP.md'='BOOTSTRAP.md';
        'PROJECT.md'='PROJECT.md'; 'REVIEW_PROFILE.md'='REVIEW_PROFILE.md'; 'RELATIONSHIPS.md'='RELATIONSHIPS.md';
        'STATUS.md'='STATUS.md'; 'tasks/README.md'='tasks/README.md'
    }
    if(-not(Test-AdoptionProfileVersion $Version)){throw 'ADOPTION_PROFILE_VERSION_UNBOUND'}
    $map['controller.json']='controller.json'
    $map['corrections.json']='corrections.json'
    $map['process-policy.json']='process-policy.json'
    return $map
}

function Get-AiwRegistrationTargetObjects(
    [string]$RepositoryRoot,
    [string]$FrameworkWorkspace,
    [string]$ProjectId,
    [string]$DisplayName,
    [int]$RulePackBytes,
    [string]$TemplateRoot,
    [string]$ManagedTemplateRoot,
    [string]$Version,
    [string]$Layout,
    $TemplateMap,
    $MarkdownTokens,
    $JsonTokens,
    $AgentsProjection,
    $MaintenanceOverlay,
    [string]$TargetRepositoryId,
    [string]$TargetSiblingDirectory,
    [string[]]$TargetRoutineExcludedPath
) {
    $targets = [Collections.Generic.List[object]]::new()
    foreach ($directory in @('.ai-workspace/tasks', '.ai-workspace/tasks/active', '.ai-workspace/tasks/archive')) {
        $targets.Add([pscustomobject]@{ path = $directory; kind = 'DIRECTORY' })
    }
    $dependencies = [Collections.Generic.List[string]]::new()
    $dependencies.Add('framework/versions/' + $Version + '/ADOPTION_PROFILE.json')

    foreach ($entry in $TemplateMap.GetEnumerator()) {
        $sourcePath = if ($Layout -ceq 'framework-maintenance-sibling' -and $entry.Key -ceq 'BOOTSTRAP.md') {
            Join-ChildPath $ManagedTemplateRoot 'BOOTSTRAP.md'
        }
        elseif ($Layout -ceq 'framework-maintenance-sibling' -and $entry.Key -ceq 'process-policy.json') {
            [string]$MaintenanceOverlay.ProcessPolicyPath
        }
        else {
            Join-ChildPath $TemplateRoot $entry.Key
        }
        $relativeDependency = [IO.Path]::GetRelativePath($FrameworkWorkspace, $sourcePath).Replace('\', '/')
        if (-not $dependencies.Contains($relativeDependency)) {
            $dependencies.Add($relativeDependency)
        }

        $content = Read-StrictUtf8Template $sourcePath
        foreach ($token in $MarkdownTokens.GetEnumerator()) {
            $content = $content.Replace($token.Key, $token.Value)
        }
        foreach ($token in $JsonTokens.GetEnumerator()) {
            $content = $content.Replace($token.Key, $token.Value)
        }
        if ($Layout -ceq 'framework-maintenance-sibling' -and $entry.Value -ceq 'project.json') {
            $content = New-AiwMaintenanceProjectConfig -ProjectId $ProjectId -DisplayName $DisplayName -FrameworkVersion $Version -TargetRepositoryId $TargetRepositoryId -TargetSiblingDirectory $TargetSiblingDirectory -TargetRoutineExcludedPaths $TargetRoutineExcludedPath
            $content = $content.Replace("`r`n", "`n").Replace("`r", "`n")
        }
        if ($entry.Value -ceq 'process-policy.json' -and (Test-AdoptionProfileVersion $Version)) {
            $policy = $content | ConvertFrom-Json
            $content = ([ordered]@{
                schemaVersion = 1
                contractVersion = [string]$script:ActiveAdoptionProfile.projectControl.processCarrierContractVersion
                projectId = [string]$policy.projectId
                selectedRulePackBytes = $RulePackBytes
                rules = @($policy.rules)
            } | ConvertTo-Json -Depth 100 -Compress) + [char]10
        }
        if ($content -match '\{\{[A-Z0-9_]+\}\}') {
            throw "Unresolved template token in: $sourcePath"
        }
        if ($entry.Value -in @('project.json', 'controller.json', 'corrections.json', 'process-policy.json')) {
            $null = $content | ConvertFrom-Json
        }
        $targets.Add([pscustomobject]@{ path = '.ai-workspace/' + [string]$entry.Value; text = $content })
    }

    if ($null -ne $AgentsProjection) {
        $targets.Add([pscustomobject]@{ path = 'AGENTS.md'; text = [string]$AgentsProjection.TargetAgents })
        if ([bool]$AgentsProjection.ManageSkill) {
            $targets.Add([pscustomobject]@{ path = '.agents/skills/ai-workspace-router/SKILL.md'; text = [string]$AgentsProjection.TargetSkill })
        }
        if ($null -ne $AgentsProjection.GitIgnore) {
            $targets.Add([pscustomobject]@{ path = '.gitignore'; text = [string]$AgentsProjection.GitIgnore.TargetContent })
        }
    }

    return [pscustomobject]@{
        Targets = @($targets)
        Dependencies = @($dependencies)
    }
}

function Remove-AiwRolledBackRegistrationState {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$TransactionRelativePath
    )

    $transactionPath = Get-AiwContainedPath $RepositoryRoot $TransactionRelativePath
    $record = Read-AiwProjectJson $transactionPath 'REGISTRATION_TRANSACTION_STATE'
    if ($record.Value.schemaVersion -ne 1 -or
        $record.Value.transactionComplete -isnot [bool] -or
        -not [bool]$record.Value.transactionComplete -or
        [string]$record.Value.state -cne 'ROLLED_BACK') {
        throw 'REGISTRATION_ROLLBACK_STATE_NOT_COMPLETE'
    }
    [IO.File]::Delete($transactionPath)
    foreach ($relative in @(
        '.ai-workspace/runtime/project-adoption/register',
        '.ai-workspace/runtime/project-adoption',
        '.ai-workspace/runtime',
        '.ai-workspace'
    )) {
        $path = Get-AiwContainedPath $RepositoryRoot $relative
        if (Test-Path -LiteralPath $path -PathType Container) {
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw ('REGISTRATION_ROLLBACK_DIRECTORY_REPARSE|' + $relative)
            }
            if ([IO.Directory]::GetFileSystemEntries($path).Count -eq 0) {
                [IO.Directory]::Delete($path, $false)
            }
        }
    }
}

function Test-AiwRegistrationProjection {
    param(
        [string]$FrameworkWorkspace,
        [string]$ProjectId,
        [string]$DisplayName,
        [string]$FrameworkVersion,
        [string]$ControllerId,
        [string]$Layout,
        [string]$TargetRepositoryId,
        [string]$TargetSiblingDirectory,
        [string[]]$TargetRoutineExcludedPath,
        [string]$BootstrapTemplate,
        $Projection
    )

    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('aiw-registration-preflight-' + [guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -ItemType Directory -Path $fixture
        foreach ($entry in @($Projection.objects)) {
            $path = Join-ChildPath $fixture ([string]$entry.path)
            if ([string]$entry.kind -ceq 'DIRECTORY') {
                $null = New-Item -ItemType Directory -Path $path -Force
            }
            elseif ([bool]$entry.newExists) {
                $parent = Split-Path -Parent $path
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    $null = New-Item -ItemType Directory -Path $parent -Force
                }
                [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String([string]$entry.newBase64))
            }
        }
        Assert-RepoLocalProject (Join-Path $fixture '.ai-workspace') $ProjectId $DisplayName $FrameworkVersion @((New-TemplateMap $FrameworkVersion).Values) @('tasks', 'tasks/active', 'tasks/archive') $BootstrapTemplate $FrameworkWorkspace $ControllerId $Layout $TargetRepositoryId $TargetSiblingDirectory $TargetRoutineExcludedPath
        return $true
    }
    finally {
        if (Test-Path -LiteralPath $fixture -PathType Container) {
            [IO.Directory]::Delete($fixture, $true)
        }
    }
}

function Get-OptionalFileIdentity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'MISSING' }
    return Get-FileIdentity $Path
}

function Get-RuntimeGitIgnoreProjection([string]$RepositoryRoot,[string]$Rule) {
    $path=Join-Path $RepositoryRoot '.gitignore';$oldIdentity=Get-OptionalFileIdentity $path
    $content='';if($oldIdentity-cne'MISSING'){$bytes=[IO.File]::ReadAllBytes($path);if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'RUNTIME_GITIGNORE_BOM'};try{$content=$utf8Strict.GetString($bytes)}catch{throw 'RUNTIME_GITIGNORE_UTF8'};if($content.Contains([char]0)){throw 'RUNTIME_GITIGNORE_NUL'}}
    $normalizedRule=$Rule.Trim().TrimStart('!').TrimStart('/').TrimEnd('/')
    $lines=[regex]::Split($content,"`r?`n",[Text.RegularExpressions.RegexOptions]::None)
    $matches=@();$negated=@()
    for($i=0;$i-lt$lines.Count;$i++){$trim=$lines[$i].Trim();if([string]::IsNullOrWhiteSpace($trim)-or$trim.StartsWith('#')){continue};$candidate=$trim.TrimStart('!').TrimStart('/').TrimEnd('/');if($candidate-ceq$normalizedRule){if($trim.StartsWith('!')){$negated+=$i}else{$matches+=$i}}}
    if($negated.Count-ne0){throw 'RUNTIME_GITIGNORE_NEGATION_CONFLICT'}
    if($matches.Count-gt1){throw 'RUNTIME_GITIGNORE_DUPLICATE_CONFLICT'}
    if($matches.Count-eq1){return [pscustomobject]@{Path=$path;OldIdentity=$oldIdentity;TargetContent=$content;Changed=$false}}
    $newline=if($content.Contains("`r`n")){"`r`n"}else{"`n"}
    if($matches.Count-eq0){if($content.Length-gt0-and-not($content.EndsWith("`n")-or$content.EndsWith("`r"))){$content+=$newline};$content+=$Rule+$newline}
    return [pscustomobject]@{Path=$path;OldIdentity=$oldIdentity;TargetContent=$content;Changed=$true}
}

function Get-FrameworkAgentsProjection([string]$RepositoryRoot,[string]$TemplateRoot,[string]$Version) {
    if(-not(Test-AdoptionProfileVersion $Version)){throw 'ADOPTION_PROFILE_VERSION_UNBOUND'}
    Assert-ManagedRouterDestinations $RepositoryRoot
    $agentsTemplatePath=Join-ChildPath $TemplateRoot 'AGENTS.md'
    $manageSkill=$false
    $targetBlock=Read-StrictUtf8Template $agentsTemplatePath
    $targetSkill=$null
    $agentsPath=Join-Path $RepositoryRoot 'AGENTS.md'
    $skillPath=Join-Path $RepositoryRoot '.agents\skills\ai-workspace-router\SKILL.md'
    $begin='<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->';$end='<!-- AI-WORKSPACE-FRAMEWORK:END -->'
    $oldAgentsIdentity=Get-OptionalFileIdentity $agentsPath;$oldSkillIdentity='MISSING'
    if($oldAgentsIdentity-ceq'MISSING'){$targetAgents=$targetBlock}
    else{
        $bytes=[IO.File]::ReadAllBytes($agentsPath)
        if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'AGENTS_MANAGED_BLOCK_BOM'}
        try{$current=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{throw 'AGENTS_MANAGED_BLOCK_UTF8'}
        if($current.Contains("`r")-or-not$current.EndsWith("`n")){throw 'AGENTS_MANAGED_BLOCK_TEXT_FORMAT'}
        $beginCount=[regex]::Matches($current,[regex]::Escape($begin)).Count;$endCount=[regex]::Matches($current,[regex]::Escape($end)).Count
        if($beginCount-eq0-and$endCount-eq0){$separator=if($current.Length-eq0){''}elseif($current.EndsWith("`n")){"`n"}else{"`n`n"};$targetAgents=$current+$separator+$targetBlock}
        elseif($beginCount-eq1-and$endCount-eq1){
            $start=$current.IndexOf($begin,[StringComparison]::Ordinal);$finish=$current.IndexOf($end,[StringComparison]::Ordinal)
            if($finish-lt$start){throw 'AGENTS_MANAGED_BLOCK_ORDER'}
            $finish+=$end.Length;$existing=$current.Substring($start,$finish-$start)
            $targetExact=$targetBlock.TrimEnd("`n")
            if($existing-cne$targetExact){throw 'AGENTS_MANAGED_BLOCK_CONFLICT'}
            $targetAgents=$current
        }else{throw 'AGENTS_MANAGED_MARKERS_MALFORMED'}
    }
    $gitIgnore=Get-RuntimeGitIgnoreProjection $RepositoryRoot ([string]$script:ActiveAdoptionProfile.projectControl.runtimeGitIgnoreRule)
    return [pscustomobject]@{AgentsPath=$agentsPath;SkillPath=$skillPath;OldAgentsIdentity=$oldAgentsIdentity;OldSkillIdentity=$oldSkillIdentity;TargetAgents=$targetAgents;TargetSkill=$targetSkill;ManageSkill=$manageSkill;GitIgnore=$gitIgnore}
}

function Invoke-GitCapture {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git @Arguments 2>$null | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{ Output = $output; ExitCode = $exitCode }
}

function Get-GitRepositoryRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $result = Invoke-GitCapture @('-C', $Path, 'rev-parse', '--show-toplevel')
    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) {
        throw "Repository path is not a Git work tree: $Path"
    }
    $root = [System.IO.Path]::GetFullPath([string]$result.Output[-1]).TrimEnd('\')
    $requested = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $root.Equals($requested, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "RepositoryPath must be the Git top level: $requested"
    }
    return $root
}

function Assert-NoReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed for the project control plane: $Path"
    }
}

function Assert-NoReparseTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-NoReparsePoint $Path
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed for the project control plane: $($item.FullName)"
        }
    }
}

function Test-ManagedRouterRelative([string]$RelativePath) {
    return $RelativePath -ceq 'AGENTS.md' -or $RelativePath -ceq '.agents/skills/ai-workspace-router/SKILL.md'
}

function Assert-ManagedRouterDestinations([string]$RepositoryRoot) {
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    Assert-NoReparsePoint $root
    foreach($relative in @('AGENTS.md','.agents/skills/ai-workspace-router/SKILL.md')){
        $full=[IO.Path]::GetFullPath((Join-ChildPath $root $relative))
        if(-not$full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'MANAGED_ROUTER_DESTINATION_OUTSIDE_REPOSITORY'}
        $current=$root;$segments=$relative.Split('/')
        for($index=0;$index-lt$segments.Count;$index++){
            $current=Join-Path $current $segments[$index]
            $item=Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
            if($null-eq$item){break}
            if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw ('MANAGED_ROUTER_DESTINATION_REPARSE|'+$relative)}
            if($index-lt$segments.Count-1-and-not$item.PSIsContainer){throw ('MANAGED_ROUTER_DESTINATION_TYPE|'+$relative)}
            if($index-eq$segments.Count-1-and$item.PSIsContainer){throw ('MANAGED_ROUTER_DESTINATION_TYPE|'+$relative)}
        }
    }
}

function Get-RepoLocalBootstrapRegions {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $managedBegin = '<!-- FRAMEWORK-MANAGED:BEGIN -->'
    $managedEnd = '<!-- FRAMEWORK-MANAGED:END -->'
    $customBegin = '<!-- PROJECT-CUSTOM:BEGIN -->'
    $customEnd = '<!-- PROJECT-CUSTOM:END -->'
    foreach ($marker in @($managedBegin, $managedEnd, $customBegin, $customEnd)) {
        if ([regex]::Matches($Content, [regex]::Escape($marker)).Count -ne 1) {
            throw "Repo-local Bootstrap markers must each appear exactly once: $Source"
        }
    }

    $managedBeginIndex = $Content.IndexOf($managedBegin, [System.StringComparison]::Ordinal)
    $managedEndIndex = $Content.IndexOf($managedEnd, [System.StringComparison]::Ordinal)
    $customBeginIndex = $Content.IndexOf($customBegin, [System.StringComparison]::Ordinal)
    $customEndIndex = $Content.IndexOf($customEnd, [System.StringComparison]::Ordinal)
    if (-not ($managedBeginIndex -lt $managedEndIndex -and
              $managedEndIndex -lt $customBeginIndex -and
              $customBeginIndex -lt $customEndIndex)) {
        throw "Repo-local Bootstrap markers must be paired and ordered managed-then-custom: $Source"
    }

    $managedBlockEnd = $managedEndIndex + $managedEnd.Length
    return [pscustomobject]@{
        ManagedText = $Content.Substring($managedBeginIndex, $managedBlockEnd - $managedBeginIndex)
    }
}

function Render-RepoLocalBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)]$ProjectConfig,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $rendered = $Template
    $rendered = $rendered.Replace('{{PROJECT_ID}}', [string]$ProjectConfig.id)
    $rendered = $rendered.Replace('{{DISPLAY_NAME}}', [string]$ProjectConfig.displayName)
    $rendered = $rendered.Replace('{{FRAMEWORK_VERSION}}', $FrameworkVersion)
    if ($rendered -match '\{\{[A-Z0-9_]+\}\}') {
        throw "Repo-local Bootstrap template contains an unresolved token: $Source"
    }
    return $rendered
}

function Get-UpperSha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-FileIdentity([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    return $bytes.Length.ToString()+'|'+(Get-UpperSha256Bytes $bytes)
}

function Assert-StableFrameworkRelease {
    param(
        [Parameter(Mandatory = $true)][string]$FrameworkPath,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )

    if (-not (Test-Path -LiteralPath $FrameworkPath -PathType Container)) {
        throw "Framework version does not exist: $FrameworkPath"
    }
    Assert-NoReparseTree $FrameworkPath
    $versionPath = Join-ChildPath $FrameworkPath 'VERSION.json'
    $manifestPath = Join-ChildPath $FrameworkPath 'RELEASE_MANIFEST.json'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "FRAMEWORK_RELEASE_METADATA_MISSING|$ExpectedVersion"
    }
    try {
        $version = (Read-StrictUtf8Template $versionPath) | ConvertFrom-Json
        $manifest = (Read-StrictUtf8Template $manifestPath) | ConvertFrom-Json
    } catch { throw "FRAMEWORK_RELEASE_METADATA_INVALID|$ExpectedVersion|$($_.Exception.Message)" }
    if (-not ($version.version -is [string]) -or [string]$version.version -cne $ExpectedVersion -or
        -not ($version.lifecycle -is [string]) -or [string]$version.lifecycle -cne 'STABLE' -or
        -not ($version.consumable -is [bool]) -or -not [bool]$version.consumable -or
        -not ($version.projectPinEligible -is [bool]) -or -not [bool]$version.projectPinEligible) {
        throw "FRAMEWORK_VERSION_NOT_CONSUMABLE|$ExpectedVersion"
    }
    if (-not ($manifest.version -is [string]) -or [string]$manifest.version -cne $ExpectedVersion -or
        -not ($manifest.lifecycle -is [string]) -or [string]$manifest.lifecycle -cne 'STABLE' -or
        -not ($manifest.sourceReview -is [string]) -or [string]$manifest.sourceReview -cne 'APPROVED' -or
        -not ($manifest.releaseIntegration -is [string]) -or [string]::IsNullOrWhiteSpace([string]$manifest.releaseIntegration) -or [string]$manifest.releaseIntegration -ceq 'PENDING' -or
        -not (Test-JsonInteger $manifest.fileCount) -or -not (Test-JsonInteger $manifest.totalBytes) -or
        -not ($manifest.canonical -is [string]) -or [string]$manifest.canonical -cnotmatch '^[A-F0-9]{64}$') {
        throw "FRAMEWORK_RELEASE_NOT_SEALED|$ExpectedVersion"
    }

    $rows = New-Object 'System.Collections.Generic.List[string]'
    [int64]$totalBytes = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $FrameworkPath -Recurse -File -Force)) {
        $relative = $file.FullName.Substring($FrameworkPath.Length + 1).Replace('\','/')
        if ($relative -ceq 'RELEASE_MANIFEST.json') { continue }
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $totalBytes += $bytes.Length
        $rows.Add($relative + '|' + $bytes.Length + '|' + (Get-UpperSha256Bytes $bytes))
    }
    [string[]]$ordered = @($rows)
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    $payloadBytes = $utf8NoBom.GetBytes([string]::Join("`n", $ordered))
    $canonical = Get-UpperSha256Bytes $payloadBytes
    if ([int64]$manifest.fileCount -ne $ordered.Count -or [int64]$manifest.totalBytes -ne $totalBytes -or [string]$manifest.canonical -cne $canonical) {
        throw "FRAMEWORK_RELEASE_MANIFEST_DRIFT|$ExpectedVersion"
    }
}

function Get-RepoLocalStarter {
    param(
        [Parameter(Mandatory = $true)][string]$FrameworkRoot,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$TemplateMap,
        [Parameter(Mandatory = $true)][string]$Selection
    )

    $frameworkPath = Join-ChildPath $FrameworkRoot "versions/$FrameworkVersion"
    Assert-StableFrameworkRelease $frameworkPath $FrameworkVersion
    $profileTarget=Test-AdoptionProfileVersion $FrameworkVersion
    if($profileTarget){
        if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7' }
        $toolchainPath=Join-ChildPath $frameworkPath 'TOOLCHAIN.json'
        $toolchainRaw=Read-StrictUtf8Template $toolchainPath
        try{$toolchain=$toolchainRaw|ConvertFrom-Json}catch{throw 'FRAMEWORK_TOOLCHAIN_JSON'}
        $toolchainFields=@('schemaVersion','frameworkVersion','contractVersion','projectSelectionField','routerCompatibility','officialBackends','conformance')
        Assert-ExactObjectFields $toolchain $toolchainRaw $toolchainFields 'Framework TOOLCHAIN.json'
        if(-not(Test-JsonInteger $toolchain.schemaVersion)-or[int]$toolchain.schemaVersion-ne1-or[string]$toolchain.frameworkVersion-cne$FrameworkVersion-or[string]$toolchain.contractVersion-cne'1'-or[string]$toolchain.projectSelectionField-cne'frameworkToolBackend'-or-not($toolchain.officialBackends-is[System.Array])-or@($toolchain.officialBackends).Count-ne1){throw 'FRAMEWORK_TOOLCHAIN_VALUES'}
        $backend=@($toolchain.officialBackends)[0]
        if(-not($backend-is[pscustomobject])-or[string]$backend.id-cne'powershell7'-or[string]$backend.status-cne'OFFICIAL'-or-not($backend.runtime-is[pscustomobject])-or[string]$backend.runtime.command-cne'pwsh'-or[string]$backend.runtime.edition-cne'Core'-or-not(Test-JsonInteger $backend.runtime.minimumMajorVersion)-or[int]$backend.runtime.minimumMajorVersion-ne7-or-not($backend.platforms-is[System.Array])-or@($backend.platforms).Count-lt1-or-not($backend.entrypoints-is[pscustomobject])){throw 'FRAMEWORK_TOOLCHAIN_BACKEND'}
        $declaredPlatforms=@($backend.platforms|ForEach-Object{[string]$_})
        if(@($declaredPlatforms|Where-Object{$_-cnotin@('windows','linux','macos')}).Count-ne0-or@($declaredPlatforms|Select-Object -Unique).Count-ne$declaredPlatforms.Count){throw 'FRAMEWORK_TOOLCHAIN_PLATFORMS'}
        $router=$toolchain.routerCompatibility
        $routerRaw=$router|ConvertTo-Json -Compress
        $requiredOperations=@($router.requiredOperations|ForEach-Object{[string]$_})
        Assert-ExactObjectFields $router $routerRaw @('schemaVersion','skillName','status','canonicalSkillPath','versionContractPath','requiredOperations','processCatalogSchemaVersion','processCatalogVersion','nativeRuleBodySource') 'Framework TOOLCHAIN.json routerCompatibility'
        if(-not(Test-JsonInteger $router.schemaVersion)-or[int]$router.schemaVersion-ne1-or[string]$router.skillName-cne'ai-workspace-router'-or[string]$router.status-cne'COMPATIBLE'-or[string]$router.canonicalSkillPath-cne'skills/ai-workspace-router/SKILL.md'-or[string]$router.versionContractPath-cne'host/skills/ai-workspace-router/SKILL.md'-or-not($router.requiredOperations-is[System.Array])-or[string]::Join('|',$requiredOperations)-cne'LOAD_PLAN_RESOLVE|PROCESS_REQUIREMENTS_RESOLVE|WORKFLOW_ROUTE_RESOLVE'-or-not(Test-JsonInteger $router.processCatalogSchemaVersion)-or[int]$router.processCatalogSchemaVersion-ne2-or[string]$router.processCatalogVersion-cne'3'-or[string]$router.nativeRuleBodySource-cne'MARKDOWN_EXACT_BLOCK'){throw 'FRAMEWORK_TOOLCHAIN_ROUTER_COMPATIBILITY'}
        $currentPlatform=if([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)){'windows'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux)){'linux'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)){'macos'}else{'unknown'}
        if($currentPlatform-cnotin$declaredPlatforms){throw ('FRAMEWORK_TOOL_PLATFORM_UNSUPPORTED|backend=powershell7|platform='+$currentPlatform)}
        foreach($entry in $backend.entrypoints.PSObject.Properties){$relative=[string]$entry.Value;if([string]::IsNullOrWhiteSpace($relative)-or$relative-cne$relative.Replace('\','/')-or[IO.Path]::IsPathRooted($relative)-or$relative.Contains('..')-or-not(Test-Path -LiteralPath (Join-ChildPath $frameworkPath $relative) -PathType Leaf)){throw ('FRAMEWORK_TOOLCHAIN_ENTRYPOINT|'+$entry.Name)}}
    }
    $templateRoot = Join-ChildPath $frameworkPath 'project-starter'
    if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
        throw "Framework project starter does not exist: $templateRoot"
    }
    Assert-NoReparseTree $templateRoot
    foreach ($relativeTemplate in $TemplateMap.Keys) {
        $templatePath = Join-ChildPath $templateRoot $relativeTemplate
        if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
            throw "Required project template is missing: $templatePath"
        }
    }
    $projectTemplateText = Read-StrictUtf8Template (Join-ChildPath $templateRoot 'project.json')
    $expectedSchema='"schemaVersion": '+[string]$script:ActiveAdoptionProfile.projectControl.schemaVersion
    if (-not $projectTemplateText.Contains($expectedSchema) -or
        -not $projectTemplateText.Contains('"controlPlaneLayout": "repo-local"') -or
        -not $projectTemplateText.Contains('"repositoryRoot": ".."')) {
        throw "$Selection does not publish a valid repo-local project starter."
    }
    if(-not$projectTemplateText.Contains('"frameworkToolBackend": "powershell7"')){throw "$Selection does not publish the required tool backend."}
    if(-not$projectTemplateText.Contains('"locator": ".ai-workspace/process-policy.json"')-or-not$TemplateMap.Contains('process-policy.json')){throw "$Selection does not publish the required structured process policy carrier."}
    if(-not(Test-Path -LiteralPath (Join-ChildPath $templateRoot 'AGENTS.md') -PathType Leaf)-or(Test-Path -LiteralPath (Join-ChildPath $templateRoot '.agents/skills/ai-workspace-router'))){throw "$Selection must publish only the managed AGENTS navigation block; the router Skill is host-global."}
    $bootstrapTemplate = Read-StrictUtf8Template (Join-ChildPath $templateRoot 'BOOTSTRAP.md')
    $null = Get-RepoLocalBootstrapRegions $bootstrapTemplate (Join-ChildPath $templateRoot 'BOOTSTRAP.md')
    return [pscustomobject]@{
        TemplateRoot = $templateRoot
        BootstrapTemplate = $bootstrapTemplate
    }
}

function Assert-RepoLocalProject {
    param(
        [Parameter(Mandatory = $true)][string]$ControlRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedProjectId,
        [Parameter(Mandatory = $true)][string]$ExpectedDisplayName,
        [Parameter(Mandatory = $true)][string]$ExpectedFrameworkVersion,
        [Parameter(Mandatory = $true)][string[]]$RequiredFiles,
        [Parameter(Mandatory = $true)][string[]]$RequiredDirectories,
        [Parameter(Mandatory = $true)][string]$ExpectedBootstrapTemplate,
        [Parameter(Mandatory = $true)][string]$FrameworkWorkspaceRoot,
        [string]$ExpectedControllerId,
        [ValidateSet('repo-local','framework-maintenance-sibling')][string]$ExpectedLayout='repo-local',
        [string]$ExpectedTargetRepositoryId,
        [string]$ExpectedTargetSiblingDirectory,
        [string[]]$ExpectedTargetRoutineExcludedPaths=@()
    )

    $expectedProcessCarrierVersion = Get-ProcessCarrierContractVersion $ExpectedFrameworkVersion
    $profileTarget=Test-AdoptionProfileVersion $ExpectedFrameworkVersion

    Assert-NoReparseTree $ControlRoot
    $actualFiles = @(Get-ChildItem -LiteralPath $ControlRoot -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($ControlRoot.Length + 1).Replace('\', '/')
    })
    $actualDirectories = @(Get-ChildItem -LiteralPath $ControlRoot -Recurse -Directory -Force | ForEach-Object {
        $_.FullName.Substring($ControlRoot.Length + 1).Replace('\', '/')
    })
    if ($profileTarget) {
        # Runtime receipts and resumable transaction state are project-local but
        # deliberately outside the durable managed inventory.
        $actualFiles = @($actualFiles | Where-Object { [string]$_ -cnotlike 'runtime/*' })
        $actualDirectories = @($actualDirectories | Where-Object { [string]$_ -cne 'runtime' -and [string]$_ -cnotlike 'runtime/*' })
    }
    $fileDifference = @(Compare-Object -ReferenceObject @($RequiredFiles) -DifferenceObject $actualFiles -CaseSensitive)
    $directoryDifference = @(Compare-Object -ReferenceObject @($RequiredDirectories) -DifferenceObject $actualDirectories -CaseSensitive)
    if ($fileDifference.Count -ne 0 -or $directoryDifference.Count -ne 0) {
        throw "Existing .ai-workspace inventory conflicts with a complete registration; refusing to merge, overwrite, or treat unknown live bytes as registered: $ControlRoot"
    }
    foreach ($relativeFile in $RequiredFiles) {
        $null = Read-StrictUtf8Template (Join-ChildPath $ControlRoot $relativeFile)
    }
    $projectFile = Join-Path $ControlRoot 'project.json'
    $bootstrapFile = Join-Path $ControlRoot 'BOOTSTRAP.md'
    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf) -or
        -not (Test-Path -LiteralPath $bootstrapFile -PathType Leaf)) {
        throw "Existing .ai-workspace is partial; refusing to merge or overwrite: $ControlRoot"
    }
    try {
        $configRaw = Read-StrictUtf8Template $projectFile
        $config = $configRaw | ConvertFrom-Json
    }
    catch {
        throw "Existing repo-local project.json is invalid: $projectFile"
    }
    $baseFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion')
    $schema3=$true
    $expectedFields=@($baseFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy')+$(if($ExpectedLayout-ceq'framework-maintenance-sibling'){@('frameworkTarget')}else{@()}))
    Assert-ExactObjectFields $config $configRaw $expectedFields 'Existing project.json'
    $expectedSchema=[int]$script:ActiveAdoptionProfile.projectControl.schemaVersion
    if (-not (Test-JsonInteger $config.schemaVersion) -or [int]$config.schemaVersion -ne $expectedSchema -or
        -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne $ExpectedLayout -or
        -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
        -not ($config.id -is [string]) -or [string]$config.id -cne $ExpectedProjectId -or
        -not ($config.displayName -is [string]) -or [string]$config.displayName -cne $ExpectedDisplayName -or
        -not ($config.frameworkVersion -is [string]) -or [string]$config.frameworkVersion -cne $ExpectedFrameworkVersion -or
        -not($config.frameworkToolBackend-is[string])-or[string]$config.frameworkToolBackend-cne[string]$script:ActiveAdoptionProfile.projectControl.frameworkToolBackend) {
        throw "Existing .ai-workspace identity conflicts with the requested project: $ControlRoot"
    }
    if ($schema3) {
        if (-not ($config.routineExcludedPaths -is [System.Array]) -or -not ($config.frameworkCapabilities -is [pscustomobject])) { throw "Existing project.json routine exclusions or capabilities are invalid: $projectFile" }
        Assert-FrameworkCapabilities $config.frameworkCapabilities $configRaw 'Existing project.json frameworkCapabilities'
        if($ExpectedLayout-ceq'framework-maintenance-sibling'){
            if(@($config.frameworkCapabilities.PSObject.Properties).Count-ne0){throw 'Maintenance project capabilities must be empty.'}
            Assert-ExactObjectFields $config.frameworkTarget ($config.frameworkTarget|ConvertTo-Json -Compress) @('repositoryId','siblingDirectory','routineExcludedPaths') 'Existing project.json frameworkTarget'
            $expectedTargetPaths=@($ExpectedTargetRoutineExcludedPaths)
            if([string]$config.frameworkTarget.repositoryId-cne$ExpectedTargetRepositoryId-or[string]$config.frameworkTarget.siblingDirectory-cne$ExpectedTargetSiblingDirectory-or-not($config.frameworkTarget.routineExcludedPaths-is[Array])-or[string]::Join('|',@($config.frameworkTarget.routineExcludedPaths))-cne[string]::Join('|',$expectedTargetPaths)){throw 'Existing maintenance target conflicts with the requested target.'}
        }
        $routinePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($pathValue in @($config.routineExcludedPaths)) {
            if (-not ($pathValue -is [string]) -or [string]::IsNullOrWhiteSpace([string]$pathValue) -or -not $routinePaths.Add([string]$pathValue)) { throw "Existing project.json routine exclusions are invalid: $projectFile" }
        }
        $controllerFile=Join-Path $ControlRoot 'controller.json'
        $controllerRaw=Read-StrictUtf8Template $controllerFile
        try { $controller=$controllerRaw|ConvertFrom-Json } catch { throw "Existing controller.json is invalid: $controllerFile" }
        $controllerFields=@('schemaVersion','projectId','controllerId','controllerEpoch','state')
        Assert-ExactObjectFields $controller $controllerRaw $controllerFields 'Existing controller.json'
        if (-not (Test-JsonInteger $controller.schemaVersion) -or [int]$controller.schemaVersion -ne 1 -or
            -not ($controller.projectId -is [string]) -or [string]$controller.projectId -cne $ExpectedProjectId -or
            -not ($controller.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$controller.controllerId) -or
            -not (Test-JsonInteger $controller.controllerEpoch) -or [int64]$controller.controllerEpoch -lt 1 -or
            -not ($controller.state -is [string]) -or [string]$controller.state -cne 'CURRENT' -or
            (-not [string]::IsNullOrWhiteSpace($ExpectedControllerId) -and [string]$controller.controllerId -cne $ExpectedControllerId)) { throw "Existing controller.json conflicts with the requested project: $controllerFile" }
        if($profileTarget){
            $policyFile=Join-Path $ControlRoot 'process-policy.json';$policyRaw=Read-StrictUtf8Template $policyFile
            try{$policy=$policyRaw|ConvertFrom-Json}catch{throw "Existing process-policy.json is invalid: $policyFile"}
            $policyLocatorRaw=$config.processPolicy|ConvertTo-Json -Compress
            Assert-ExactObjectFields $config.processPolicy $policyLocatorRaw @('schemaVersion','locator') 'Existing project.json processPolicy'
            if([regex]::Matches($configRaw,'"locator"\s*:').Count-ne1){throw 'Existing project.json processPolicy locator is duplicate or missing.'}
            $policyFields=if($profileTarget){@('schemaVersion','contractVersion','projectId','selectedRulePackBytes','rules')}else{@('schemaVersion','contractVersion','projectId','rules')}
            Assert-ExactObjectFields $policy $policyRaw $policyFields 'Existing process-policy.json'
            if([int]$config.processPolicy.schemaVersion-ne1-or[string]$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'-or[int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne$expectedProcessCarrierVersion-or[string]$policy.projectId-cne$ExpectedProjectId-or-not($policy.rules-is[System.Array])-or($profileTarget-and(-not(Test-JsonInteger $policy.selectedRulePackBytes)-or[int]$policy.selectedRulePackBytes-lt1-or[int]$policy.selectedRulePackBytes-gt[int]$script:ActiveAdoptionProfile.processBudget.absoluteSelectedRulePackBytes))){throw 'Existing structured process policy is invalid.'}
        }
        if($profileTarget){
            $correctionsFile=Join-Path $ControlRoot 'corrections.json'
            $correctionsRaw=Read-StrictUtf8Template $correctionsFile
            try { $corrections=$correctionsRaw|ConvertFrom-Json } catch { throw "Existing corrections.json is invalid: $correctionsFile" }
            Assert-ExactObjectFields $corrections $correctionsRaw @('schemaVersion','contractVersion','projectId','corrections') 'Existing corrections.json'
            $isLiveControl=(Split-Path -Leaf $ControlRoot)-ceq'.ai-workspace'
            $correctionsContractValid=if($isLiveControl){
                ((Test-JsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0')-or
                ((Test-JsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq$expectedProcessCarrierVersion)
            }else{
                (Test-JsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq$expectedProcessCarrierVersion
            }
            if (-not $correctionsContractValid -or
                -not ($corrections.contractVersion -is [string]) -or
                -not ($corrections.projectId -is [string]) -or [string]$corrections.projectId -cne $ExpectedProjectId -or
                -not ($corrections.corrections -is [System.Array])) { throw "Existing registered corrections.json is invalid: $correctionsFile" }
            if($isLiveControl){
                $correctionChecker=Join-ChildPath $FrameworkWorkspaceRoot ("framework/versions/"+$ExpectedFrameworkVersion+"/scripts/check-project-corrections.ps1")
                $checkOutput=@(& $correctionChecker -ProjectRoot (Split-Path -Parent $ControlRoot) -FrameworkRoot $FrameworkWorkspaceRoot -TargetVersion $ExpectedFrameworkVersion -ExpectedProjectConfigIdentity (Get-FileIdentity $projectFile) -ExpectedCorrectionsIdentity (Get-FileIdentity $correctionsFile) -Operation RECOVER -AsJson)
                if($LASTEXITCODE-ne0){throw "Existing corrections.json failed the $ExpectedFrameworkVersion project-correction checker: $($checkOutput -join ' ')"}
            }elseif(@($corrections.corrections).Count-ne0){throw 'Registration staging contains unexpected project correction records.'}
        }
    }
    $bootstrap = Read-StrictUtf8Template $bootstrapFile
    $actualRegions = Get-RepoLocalBootstrapRegions $bootstrap $bootstrapFile
    $expectedBootstrap = Render-RepoLocalBootstrap $ExpectedBootstrapTemplate $config $ExpectedFrameworkVersion 'pinned Framework starter'
    $expectedRegions = Get-RepoLocalBootstrapRegions $expectedBootstrap 'pinned Framework starter'
    if ($actualRegions.ManagedText -cne $expectedRegions.ManagedText) {
        throw "Existing Bootstrap managed block was customized; refusing ALREADY_REGISTERED: $bootstrapFile"
    }
}

if (-not $WorkspaceRoot) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $WorkspaceRoot = Split-Path -Parent $scriptDirectory
}

$workspace = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$frameworkRoot = Join-ChildPath $workspace 'framework'
if (-not (Test-Path -LiteralPath $frameworkRoot -PathType Container)) {
    throw "Workspace root must contain the Framework directory: $workspace"
}
Assert-NoReparsePoint $frameworkRoot
$maintenanceOverlay=$null
if($ControlPlaneLayout-ceq'repo-local'){
    if(-not[string]::IsNullOrWhiteSpace($FrameworkTargetRepositoryId)-or-not[string]::IsNullOrWhiteSpace($FrameworkTargetSiblingDirectory)-or@($FrameworkTargetRoutineExcludedPath).Count-ne0){throw 'FRAMEWORK_TARGET_ARGUMENTS_REQUIRE_MAINTENANCE_LAYOUT'}
}else{
    if([string]::IsNullOrWhiteSpace($FrameworkTargetRepositoryId)-or[string]::IsNullOrWhiteSpace($FrameworkTargetSiblingDirectory)){throw 'FRAMEWORK_TARGET_ARGUMENTS_REQUIRED'}
    $maintenanceOverlay=Get-AiwMaintenanceOverlay $workspace
}
$selectedFrameworkPath=Join-ChildPath $frameworkRoot ('versions/'+$FrameworkVersion)
if(-not(Test-Path -LiteralPath $selectedFrameworkPath -PathType Container)){throw 'FRAMEWORK_VERSION_NOT_FOUND'}
$script:ActiveAdoptionProfile=Get-AdoptionProfile $selectedFrameworkPath $FrameworkVersion
if(-not[bool]$script:ActiveAdoptionProfile.registrationEligible){throw 'ADOPTION_PROFILE_REGISTRATION_NOT_ELIGIBLE'}
if($SelectedRulePackBytes-gt[int]$script:ActiveAdoptionProfile.processBudget.absoluteSelectedRulePackBytes){throw 'SELECTED_RULE_PACK_BUDGET_ABSOLUTE_CAP'}
$script:ActiveTargetCapabilityContract=Get-TargetFrameworkCapabilityContract $selectedFrameworkPath $ControlPlaneLayout

if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
    throw "Repository path does not exist or is not a directory: $RepositoryPath"
}
$repo = Get-GitRepositoryRoot ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).ProviderPath))
if($ControlPlaneLayout-ceq'framework-maintenance-sibling'){
    if($null-eq$script:ActiveAdoptionProfile){throw 'MAINTENANCE_LAYOUT_REQUIRES_ADOPTION_PROFILE'}
    $maintenanceTopology=Resolve-AiwMaintenanceTopology -ControlRepositoryPath $repo -TargetRepositoryId $FrameworkTargetRepositoryId -TargetSiblingDirectory $FrameworkTargetSiblingDirectory -TargetRoutineExcludedPaths $FrameworkTargetRoutineExcludedPath
    if([IO.Path]::GetFullPath($workspace)-cne[IO.Path]::GetFullPath([string]$maintenanceTopology.TargetRoot)){throw 'FRAMEWORK_WORKSPACE_TARGET_MISMATCH'}
    $FrameworkTargetSiblingDirectory=[string]$maintenanceTopology.TargetSiblingDirectory
    $FrameworkTargetRoutineExcludedPath=@($maintenanceTopology.TargetRoutineExcludedPaths)
}

if([string]::IsNullOrWhiteSpace($ControllerId)){throw 'ControllerId is required when registering a controlled Framework version.'}

$requiredProjectDirectories = @('tasks', 'tasks/active', 'tasks/archive')
$projectRoot = Join-Path $repo '.ai-workspace'
$projectAdoptionTransactionRelative='.ai-workspace/runtime/project-adoption/register/state.json'
$projectAdoptionTransactionPath=Get-AiwContainedPath $repo $projectAdoptionTransactionRelative
if((Test-AdoptionProfileVersion $FrameworkVersion)-and(Test-Path -LiteralPath $projectAdoptionTransactionPath -PathType Leaf)){
    $transactionRecord=Read-AiwProjectJson $projectAdoptionTransactionPath 'REGISTRATION_TRANSACTION_STATE'
    $transactionState=$transactionRecord.Value
    if($transactionState.schemaVersion-ne1-or$transactionState.transactionComplete-isnot[bool]){throw 'REGISTRATION_TRANSACTION_STATE_SCHEMA'}
    if([bool]$transactionState.transactionComplete){
        if([string]$transactionState.state-ceq'ROLLED_BACK'){
            Remove-AiwRolledBackRegistrationState $repo $projectAdoptionTransactionRelative
        }elseif([string]$transactionState.state-cne'COMPLETE'-or-not(Test-Path -LiteralPath (Join-Path $projectRoot 'project.json') -PathType Leaf)){
            throw 'REGISTRATION_TRANSACTION_COMPLETE_STATE_INVALID'
        }
    }else{
        if(-not$Apply){[pscustomobject]@{status='RECOVERY_REQUIRED';projectRoot=$projectRoot;frameworkVersion=$FrameworkVersion;transactionPath=$projectAdoptionTransactionRelative;transactionIdentity=[string]$transactionRecord.Identity};return}
        $rollbackPostcheck={param($root,$candidate)return -not(Test-Path -LiteralPath (Join-Path $root '.ai-workspace/project.json') -PathType Leaf)}
        $recovery=Resume-AiwProjectProjectionRollback $repo $projectAdoptionTransactionRelative ([string]$transactionRecord.Identity) $rollbackPostcheck
        if([string]$recovery.status-cne'ROLLED_BACK'){throw 'REGISTRATION_TRANSACTION_RECOVERY_STATE'}
        Remove-AiwRolledBackRegistrationState $repo $projectAdoptionTransactionRelative
    }
}
if (Test-Path -LiteralPath $projectRoot) {
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Project control-plane target exists but is not a directory: $projectRoot"
    }
    Assert-NoReparseTree $projectRoot
    $existingProjectFile = Join-Path $projectRoot 'project.json'
    if (-not (Test-Path -LiteralPath $existingProjectFile -PathType Leaf)) {
        throw "Existing .ai-workspace is partial; refusing to merge or overwrite: $projectRoot"
    }
    try {
        $existingConfig = (Read-StrictUtf8Template $existingProjectFile) | ConvertFrom-Json
    }
    catch {
        throw "Existing repo-local project.json is invalid: $existingProjectFile"
    }
    if([string]$existingConfig.controlPlaneLayout-cne$ControlPlaneLayout){throw 'Existing .ai-workspace layout conflicts with the explicitly requested layout.'}
    $existingVersion = [string]$existingConfig.frameworkVersion
    if ([string]::IsNullOrWhiteSpace($existingVersion) -or $existingVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
        throw "Existing repo-local project.json has an invalid Framework pin: $existingProjectFile"
    }
    if ($FrameworkVersion -cne $existingVersion) {
        throw "Existing .ai-workspace Framework pin conflicts with the explicitly requested Framework: $projectRoot"
    }
    $FrameworkVersion = $existingVersion
    $templateMap=New-TemplateMap $FrameworkVersion
    $requiredProjectFiles=@($templateMap.Values)
    $existingStarter = Get-RepoLocalStarter $frameworkRoot $FrameworkVersion $templateMap "Framework $FrameworkVersion"
    $existingTemplateRoot=if($ControlPlaneLayout-ceq'framework-maintenance-sibling'){[string]$maintenanceOverlay.Root}else{$existingStarter.TemplateRoot}
    $existingBootstrapTemplate=Read-StrictUtf8Template (Join-ChildPath $existingTemplateRoot 'BOOTSTRAP.md')
    Assert-RepoLocalProject $projectRoot $ProjectId $DisplayName $FrameworkVersion $requiredProjectFiles $requiredProjectDirectories $existingBootstrapTemplate $workspace $ControllerId $ControlPlaneLayout $FrameworkTargetRepositoryId $FrameworkTargetSiblingDirectory $FrameworkTargetRoutineExcludedPath
    $null=Get-FrameworkAgentsProjection $repo $existingTemplateRoot $FrameworkVersion
    [pscustomobject]@{
        status = 'ALREADY_REGISTERED'
        projectRoot = $projectRoot
        frameworkVersion = $FrameworkVersion
    }
    return
}

$selection = "Framework $FrameworkVersion"
$templateMap=New-TemplateMap $FrameworkVersion
$requiredProjectFiles=@($templateMap.Values)
$starter = Get-RepoLocalStarter $frameworkRoot $FrameworkVersion $templateMap $selection
$templateRoot = $starter.TemplateRoot
$managedTemplateRoot=if($ControlPlaneLayout-ceq'framework-maintenance-sibling'){[string]$maintenanceOverlay.Root}else{$templateRoot}
$bootstrapTemplate=Read-StrictUtf8Template (Join-ChildPath $managedTemplateRoot 'BOOTSTRAP.md')
$agentsProjection=Get-FrameworkAgentsProjection $repo $managedTemplateRoot $FrameworkVersion

$createdDate = Get-Date -Format 'yyyy-MM-dd'
$markdownTokens = [ordered]@{
    '{{PROJECT_ID}}' = $ProjectId
    '{{DISPLAY_NAME}}' = $DisplayName
    '{{FRAMEWORK_VERSION}}' = $FrameworkVersion
    '{{CREATED_DATE}}' = $createdDate
}
$jsonTokens = [ordered]@{
    '{{PROJECT_ID_JSON}}' = ($ProjectId | ConvertTo-Json -Compress)
    '{{DISPLAY_NAME_JSON}}' = ($DisplayName | ConvertTo-Json -Compress)
    '{{FRAMEWORK_VERSION_JSON}}' = ($FrameworkVersion | ConvertTo-Json -Compress)
    '{{CONTROLLER_ID_JSON}}' = ($ControllerId | ConvertTo-Json -Compress)
    '{{PROCESS_CONTRACT_VERSION_JSON}}' = (Get-ProcessCarrierContractVersion $FrameworkVersion | ConvertTo-Json -Compress)
    '{{SELECTED_RULE_PACK_BYTES}}' = $SelectedRulePackBytes.ToString()
}

if (Test-AdoptionProfileVersion $FrameworkVersion) {
    $targetSet = Get-AiwRegistrationTargetObjects $repo $workspace $ProjectId $DisplayName $SelectedRulePackBytes $templateRoot $managedTemplateRoot $FrameworkVersion $ControlPlaneLayout $templateMap $markdownTokens $jsonTokens $agentsProjection $maintenanceOverlay $FrameworkTargetRepositoryId $FrameworkTargetSiblingDirectory $FrameworkTargetRoutineExcludedPath
    $projection = New-AiwProjectProjection $repo @($targetSet.Targets)
    $toolDependencies = Get-AiwProjectAdoptionToolDependency REGISTER @($targetSet.Dependencies)
    $toolRevision = Get-AiwRootToolRevision $workspace $toolDependencies
    $diff = @(Get-AiwProjectProjectionDiff $projection)
    if (-not $Apply -or -not $PSCmdlet.ShouldProcess($repo, 'Apply unified repository-local project registration')) {
        [string[]]$changedPaths=@($diff|Where-Object{[string]$_.change-cne'UNCHANGED'}|ForEach-Object{[string]$_.path})
        [Array]::Sort($changedPaths,[StringComparer]::Ordinal)
        Write-Output ('PROJECT_ADOPTION_PREVIEW|operation=REGISTER|frameworkPin='+$FrameworkVersion+'|projectFormat=repo-local/project-config-'+[string]$script:ActiveAdoptionProfile.projectControl.schemaVersion+'|rootToolRevision='+[string]$toolRevision.revision+'|transaction='+$projectAdoptionTransactionRelative+'|changes='+$changedPaths.Count)
        Write-Output ('PROJECT_ADOPTION_WRITESET|'+[string]::Join('|',$changedPaths))
        [pscustomobject]@{
            status = 'WHAT_IF'
            projectRoot = $projectRoot
            frameworkVersion = $FrameworkVersion
            controlPlaneLayout = $ControlPlaneLayout
            projectFormat = 'repo-local/project-config-' + [string]$script:ActiveAdoptionProfile.projectControl.schemaVersion
            rootToolRevision = [string]$toolRevision.revision
            transactionPath = $projectAdoptionTransactionRelative
            noOp = [bool]$projection.noOp
            changes = $diff
        }
        return
    }

    $preflight = {
        param($root, $candidate)
        Test-AiwRegistrationProjection $workspace $ProjectId $DisplayName $FrameworkVersion $ControllerId $ControlPlaneLayout $FrameworkTargetRepositoryId $FrameworkTargetSiblingDirectory $FrameworkTargetRoutineExcludedPath $bootstrapTemplate $candidate
    }
    $postcheck = {
        param($root, $candidate)
        Assert-RepoLocalProject (Join-Path $root '.ai-workspace') $ProjectId $DisplayName $FrameworkVersion $requiredProjectFiles $requiredProjectDirectories $bootstrapTemplate $workspace $ControllerId $ControlPlaneLayout $FrameworkTargetRepositoryId $FrameworkTargetSiblingDirectory $FrameworkTargetRoutineExcludedPath
        return $true
    }
    $rollbackPostcheck = {
        param($root, $candidate)
        return -not (Test-Path -LiteralPath (Join-Path $root '.ai-workspace/project.json'))
    }
    try{
        $transaction = Invoke-AiwProjectProjectionTransaction $repo $projection $projectAdoptionTransactionRelative $postcheck $rollbackPostcheck -Preflight $preflight -Metadata @{
            operation = 'REGISTER'
            frameworkPin = $FrameworkVersion
            targetProjectFormat = 'repo-local/project-config-' + [string]$script:ActiveAdoptionProfile.projectControl.schemaVersion
            rootToolRevision = [string]$toolRevision.revision
        }
    }catch{
        $registrationFailure=[string]$_.Exception.Message
        if($registrationFailure-cmatch'^TRANSACTION_ROLLED_BACK\|'){
            try{Remove-AiwRolledBackRegistrationState $repo $projectAdoptionTransactionRelative}catch{throw ('REGISTRATION_ROLLBACK_CLEANUP_BLOCKED|'+[string]$_.Exception.Message+'|original='+$registrationFailure)}
        }
        throw $registrationFailure
    }
    [pscustomobject]@{
        status = 'CREATED'
        projectRoot = $projectRoot
        frameworkVersion = $FrameworkVersion
        controlPlaneLayout = $ControlPlaneLayout
        projectFormat = 'repo-local/project-config-' + [string]$script:ActiveAdoptionProfile.projectControl.schemaVersion
        rootToolRevision = [string]$toolRevision.revision
        transaction = $transaction
        createdFiles = @($projection.objects | Where-Object { [string]$_.kind -ceq 'FILE' } | ForEach-Object { [string]$_.path })
        nextAction = 'AI session completes project-specific facts, validates FULL_COLD_RECOVERY for the selected layout, then reports READY or NEEDS_INPUT.'
    }
    return
}
