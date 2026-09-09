Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Utf8Strict = [Text.UTF8Encoding]::new($false, $true)

function Get-AiwByteIdentity {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
    return $Bytes.Length.ToString() + '|' + $hash
}

function Assert-AiwRelativePath {
    param([Parameter(Mandatory)][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains(':') -or
        $RelativePath.Contains('\') -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/')) {
        throw 'RELATIVE_PATH_INVALID'
    }

    $parts = @($RelativePath.Split('/'))
    if ($parts.Count -eq 0 -or @($parts | Where-Object { $_ -ceq '' -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
        throw 'RELATIVE_PATH_INVALID'
    }
}

function Resolve-AiwRepositoryRoot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'REPOSITORY_ROOT_MISSING'
    }

    $item = Get-Item -LiteralPath $root -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'REPOSITORY_ROOT_REPARSE'
    }
    return $root
}

function Get-AiwContainedPath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    Assert-AiwRelativePath $RelativePath
    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $full = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'RELATIVE_PATH_OUTSIDE_ROOT'
    }

    $cursor = $root
    foreach ($part in $RelativePath.Split('/')) {
        $cursor = Join-Path $cursor $part
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw ('PATH_REPARSE|' + $RelativePath)
            }
        }
    }
    return $full
}

function Assert-AiwJsonNoDuplicateMember {
    param(
        [Parameter(Mandatory)][System.Text.Json.JsonElement]$Element,
        [Parameter(Mandatory)][string]$Label,
        [string]$JsonPath = '$'
    )

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) {
                throw ($Label + '_DUPLICATE_MEMBER|' + $JsonPath + '.' + $property.Name)
            }
            Assert-AiwJsonNoDuplicateMember -Element $property.Value -Label $Label -JsonPath ($JsonPath + '.' + $property.Name)
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($child in $Element.EnumerateArray()) {
            Assert-AiwJsonNoDuplicateMember -Element $child -Label $Label -JsonPath ($JsonPath + '[' + $index + ']')
            $index++
        }
    }
}

function Read-AiwProjectJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ($Label + '_MISSING')
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ($Label + '_REPARSE')
    }

    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        throw ($Label + '_BOM')
    }
    try {
        $text = $script:Utf8Strict.GetString($bytes)
    }
    catch {
        throw ($Label + '_UTF8')
    }
    if ($text.Contains("`r") -or -not $text.EndsWith("`n")) {
        throw ($Label + '_TEXT_FORMAT')
    }

    try {
        $document = [System.Text.Json.JsonDocument]::Parse($text)
        try {
            Assert-AiwJsonNoDuplicateMember -Element $document.RootElement -Label $Label
        }
        finally {
            $document.Dispose()
        }
        $value = $text | ConvertFrom-Json -Depth 64
    }
    catch {
        if ($_.Exception.Message.StartsWith($Label + '_DUPLICATE_MEMBER')) {
            throw
        }
        throw ($Label + '_JSON')
    }

    [pscustomobject]@{
        Path = $item.FullName
        Bytes = $bytes
        Text = $text
        Value = $value
        Identity = Get-AiwByteIdentity $bytes
    }
}

function Get-AiwSchemaVersion {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Value.PSObject.Properties['schemaVersion'] -or
        ($Value.schemaVersion -isnot [int] -and $Value.schemaVersion -isnot [long])) {
        throw ($Label + '_SCHEMA_VERSION')
    }
    return [int]$Value.schemaVersion
}

function Get-AiwProjectFormat {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $project = Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'PROJECT_CONFIG'
    $controller = Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/controller.json') 'CONTROLLER'
    $projectSchema = Get-AiwSchemaVersion $project.Value 'PROJECT_CONFIG'
    $controllerSchema = Get-AiwSchemaVersion $controller.Value 'CONTROLLER'

    $carriers = [ordered]@{
        project = $projectSchema
        controller = $controllerSchema
    }
    $capabilities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    if ($projectSchema -ge 4 -and
        $project.Value.PSObject.Properties.Name -ccontains 'frameworkToolBackend' -and
        -not [string]::IsNullOrWhiteSpace([string]$project.Value.frameworkToolBackend)) {
        $null = $capabilities.Add('PROJECT_BACKEND_SELECTION')
    }
    $processPolicyLocatorShape = $project.Value.PSObject.Properties.Name -ccontains 'processPolicy' -and
        $null -ne $project.Value.processPolicy -and
        $project.Value.processPolicy.PSObject.Properties.Name -ccontains 'schemaVersion' -and
        $project.Value.processPolicy.PSObject.Properties.Name -ccontains 'locator'
    if ($projectSchema -ge 4 -and
        $processPolicyLocatorShape -and
        $project.Value.processPolicy.schemaVersion -eq 1 -and
        -not [string]::IsNullOrWhiteSpace([string]$project.Value.processPolicy.locator)) {
        Assert-AiwRelativePath ([string]$project.Value.processPolicy.locator)
        $null = $capabilities.Add('PROCESS_POLICY_LOCATOR')
    }

    $correctionsPath = Get-AiwContainedPath $root '.ai-workspace/corrections.json'
    if (Test-Path -LiteralPath $correctionsPath -PathType Leaf) {
        $corrections = Read-AiwProjectJson $correctionsPath 'CORRECTIONS'
        $correctionsSchema = Get-AiwSchemaVersion $corrections.Value 'CORRECTIONS'
        $carriers.corrections = $correctionsSchema
        if ($correctionsSchema -ge 2 -and
            $corrections.Value.PSObject.Properties.Name -ccontains 'corrections' -and
            $corrections.Value.corrections -is [array]) {
            $null = $capabilities.Add('STRUCTURED_CORRECTIONS')
        }
    }

    $policyPath = Get-AiwContainedPath $root '.ai-workspace/process-policy.json'
    if (Test-Path -LiteralPath $policyPath -PathType Leaf) {
        $policy = Read-AiwProjectJson $policyPath 'PROCESS_POLICY'
        $policySchema = Get-AiwSchemaVersion $policy.Value 'PROCESS_POLICY'
        $carriers.processPolicy = $policySchema
        $hasBudget = $policy.Value.PSObject.Properties.Name -ccontains 'selectedRulePackBytes'
        $hasRules = $policy.Value.PSObject.Properties.Name -ccontains 'rules'
        $budgetIsInteger = $hasBudget -and
            ($policy.Value.selectedRulePackBytes -is [int] -or $policy.Value.selectedRulePackBytes -is [long])
        if ($hasRules -and $policy.Value.rules -is [array] -and $budgetIsInteger) {
            $null = $capabilities.Add('PROCESS_POLICY')
        }
    }

    $bootstrapPath = Get-AiwContainedPath $root '.ai-workspace/BOOTSTRAP.md'
    if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) {
        $bootstrapText = [IO.File]::ReadAllText($bootstrapPath, $script:Utf8Strict)
        if ($bootstrapText.IndexOf('<!-- PROJECT-CUSTOM:BEGIN -->', [StringComparison]::Ordinal) -ge 0 -and
            $bootstrapText.IndexOf('<!-- PROJECT-CUSTOM:END -->', [StringComparison]::Ordinal) -ge 0) {
            $null = $capabilities.Add('LEGACY_PROJECT_CUSTOM_REGION')
        }
    }
    if (Test-Path -LiteralPath (Get-AiwContainedPath $root 'AGENTS.md') -PathType Leaf) {
        $null = $capabilities.Add('ROOT_AGENTS_ENTRY')
    }

    $capabilityArray = @($capabilities)
    [Array]::Sort($capabilityArray, [StringComparer]::Ordinal)
    [pscustomobject]@{
        schemaVersion = 1
        projectFormat = 'repo-local/project-config-' + $projectSchema
        carriers = [pscustomobject]$carriers
        capabilities = $capabilityArray
        projectIdentity = $project.Identity
        controllerIdentity = $controller.Identity
    }
}

function Get-AiwProjectedProjectFormat {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Projection
    )

    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('aiw-project-format-' + [guid]::NewGuid().ToString('N'))
    $known = @(
        '.ai-workspace/project.json',
        '.ai-workspace/controller.json',
        '.ai-workspace/corrections.json',
        '.ai-workspace/process-policy.json',
        '.ai-workspace/BOOTSTRAP.md',
        'AGENTS.md'
    )
    try {
        $null = New-Item -ItemType Directory -Path $fixture
        foreach ($relative in $known) {
            $source = Get-AiwContainedPath $root $relative
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                continue
            }
            $destination = Join-Path $fixture $relative
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            [IO.File]::Copy($source, $destination, $false)
        }
        foreach ($entry in @($Projection.objects)) {
            if ([string]$entry.path -cnotin $known) {
                continue
            }
            $destination = Join-Path $fixture ([string]$entry.path)
            if ([string]$entry.kind -cne 'FILE') {
                throw ('PROJECT_FORMAT_TARGET_KIND|' + [string]$entry.path)
            }
            if (-not [bool]$entry.newExists) {
                if (Test-Path -LiteralPath $destination -PathType Leaf) {
                    [IO.File]::Delete($destination)
                }
                continue
            }
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            [IO.File]::WriteAllBytes($destination, [Convert]::FromBase64String([string]$entry.newBase64))
        }
        return Get-AiwProjectFormat $fixture
    }
    finally {
        if (Test-Path -LiteralPath $fixture -PathType Container) {
            [IO.Directory]::Delete($fixture, $true)
        }
    }
}

function Get-AiwRootToolRevision {
    param(
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][string[]]$DependencyPath
    )

    $root = Resolve-AiwRepositoryRoot $FrameworkRoot
    $relativePaths = @($DependencyPath)
    if ($relativePaths.Count -eq 0) {
        throw 'TOOL_DEPENDENCY_SET_EMPTY'
    }
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $records = [Collections.Generic.List[object]]::new()
    foreach ($relative in $relativePaths) {
        Assert-AiwRelativePath $relative
        if (-not $seen.Add($relative)) {
            throw ('TOOL_DEPENDENCY_DUPLICATE|' + $relative)
        }
        $path = Get-AiwContainedPath $root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ('TOOL_DEPENDENCY_MISSING|' + $relative)
        }
        $records.Add([pscustomobject]@{
            path = $relative
            identity = Get-AiwByteIdentity ([IO.File]::ReadAllBytes($path))
        })
    }

    $canonical = (@($records | ForEach-Object { $_.path + '=' + $_.identity }) -join "`n") + "`n"
    $revision = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))
    )
    [pscustomobject]@{
        schemaVersion = 1
        revision = $revision
        dependencies = @($records)
    }
}

function Get-AiwProjectAdoptionToolDependency {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('REGISTER', 'UPGRADE')]
        [string]$Operation,
        [string[]]$AdditionalDependencyPath = @()
    )

    $entry = if ($Operation -ceq 'REGISTER') {
        'scripts/register-project.ps1'
    }
    else {
        'scripts/upgrade-project.ps1'
    }
    $paths = @(
        $entry,
        'scripts/MaintenanceOverlay.psm1',
        'scripts/ProjectAdoptionState.psm1',
        'scripts/ProjectAdoptionProjection.psm1',
        'scripts/ProjectAdoptionTransaction.psm1'
    ) + @($AdditionalDependencyPath)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $result = [Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
        Assert-AiwRelativePath ([string]$path)
        if (-not $seen.Add([string]$path)) {
            throw ('TOOL_DEPENDENCY_DUPLICATE|' + [string]$path)
        }
        $result.Add([string]$path)
    }
    $array = @($result)
    [Array]::Sort($array, [StringComparer]::Ordinal)
    return $array
}

function Get-AiwProjectAdoptionRuntimeIdentity {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)]
        [ValidateSet('REGISTER', 'UPGRADE')]
        [string]$Operation,
        [string[]]$AdditionalDependencyPath = @()
    )

    $format = Get-AiwProjectFormat $ProjectRoot
    $root = Resolve-AiwRepositoryRoot $ProjectRoot
    $project = Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'PROJECT_CONFIG'
    if ($null -eq $project.Value.PSObject.Properties['frameworkVersion'] -or
        -not ($project.Value.frameworkVersion -is [string]) -or
        [string]$project.Value.frameworkVersion -cnotmatch '^\d+\.\d+\.\d+$') {
        throw 'PROJECT_FRAMEWORK_PIN'
    }
    $distribution=Get-AiwAdoptedDistributionBinding $ProjectRoot ([string]$project.Value.frameworkVersion)
    if($null-ne$distribution){$null=Assert-AiwDistributionBinding $distribution $FrameworkRoot ([string]$project.Value.frameworkVersion)}
    $dependencies = Get-AiwProjectAdoptionToolDependency $Operation $AdditionalDependencyPath
    $tool = Get-AiwRootToolRevision $FrameworkRoot $dependencies
    return [pscustomobject]@{
        schemaVersion = 1
        frameworkPin = [string]$project.Value.frameworkVersion
        projectFormat = [string]$format.projectFormat
        projectCapabilities = @($format.capabilities)
        rootToolRevision = [string]$tool.revision
        rootToolDependencies = @($tool.dependencies)
        distributionBinding = $distribution
    }
}

Export-ModuleMember -Function Get-AiwByteIdentity, Assert-AiwRelativePath, Resolve-AiwRepositoryRoot, Get-AiwContainedPath, Read-AiwProjectJson, Get-AiwProjectFormat, Get-AiwProjectedProjectFormat, Get-AiwRootToolRevision, Get-AiwProjectAdoptionToolDependency, Get-AiwProjectAdoptionRuntimeIdentity

# Package identity is carried by the existing adoption record, never a latest selector.
function Get-AiwDistributionBinding {
    param([Parameter(Mandatory)][string]$FrameworkRoot,[Parameter(Mandatory)][string]$FrameworkVersion,[switch]$Required)
    $root=Resolve-AiwRepositoryRoot $FrameworkRoot
    $manifestPath=Get-AiwContainedPath $root 'PACKAGE_MANIFEST.json'
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){
        if($Required){throw 'DISTRIBUTION_MANIFEST_REQUIRED'}
        return $null
    }
    if(Test-Path -LiteralPath (Join-Path $root '.git')){throw 'DISTRIBUTION_DEVELOPMENT_ROOT'}
    $doc=Read-AiwProjectJson $manifestPath 'DISTRIBUTION_MANIFEST';$m=$doc.Value
    if($m.schemaVersion-eq1-and$null-eq$m.PSObject.Properties['distributionId']){
        if($Required){throw 'DISTRIBUTION_NAMED_PACKAGE_REQUIRED'}
        return $null
    }
    $fields=@('schemaVersion','frameworkVersion','provisional','canonical','files','distributionId')
    if(@($m.PSObject.Properties).Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$m.PSObject.Properties.Name}).Count-ne0-or
       $m.schemaVersion-ne2-or[string]$m.frameworkVersion-cne$FrameworkVersion-or
       [string]$m.distributionId-cnotmatch('^'+[regex]::Escape($FrameworkVersion)+'-(snapshot\.[1-9][0-9]*|release)$')-or
       $m.provisional-isnot[bool]-or$m.files-isnot[array]-or[string]$m.canonical-cnotmatch'^[A-F0-9]{64}$'){throw 'DISTRIBUTION_MANIFEST_FIELDS'}
    if(([string]$m.distributionId).EndsWith('-release')-and[bool]$m.provisional){throw 'DISTRIBUTION_LIFECYCLE'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$rows=[Collections.Generic.List[string]]::new()
    foreach($entry in $m.files){
        if(@($entry.PSObject.Properties).Count-ne2-or$null-eq$entry.PSObject.Properties['path']-or$null-eq$entry.PSObject.Properties['identity']){throw 'DISTRIBUTION_FILE_FIELDS'}
        $relative=[string]$entry.path;Assert-AiwRelativePath $relative
        if(-not$seen.Add($relative)-or$relative-ceq'PACKAGE_MANIFEST.json'-or$relative.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase)-or$relative.StartsWith('.ai-workspace/',[StringComparison]::OrdinalIgnoreCase)){throw 'DISTRIBUTION_FILE_PATH'}
        $file=Get-AiwContainedPath $root $relative
        if(-not(Test-Path -LiteralPath $file -PathType Leaf)-or(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($file)))-cne[string]$entry.identity){throw ('DISTRIBUTION_CONTENT_DRIFT|'+$relative)}
        $rows.Add($relative+'='+[string]$entry.identity)
    }
    $all=@(Get-ChildItem -LiteralPath $root -Recurse -Force)
    if(@($all|Where-Object{($_.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0}).Count-ne0){throw 'DISTRIBUTION_REPARSE'}
    $actual=@($all|Where-Object{-not$_.PSIsContainer})
    foreach($file in $actual){$relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/');if($relative-cne'PACKAGE_MANIFEST.json'-and-not$seen.Contains($relative)){throw ('DISTRIBUTION_UNLISTED_FILE|'+$relative)}}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(([string]::Join([string][char]10,$rows)+[char]10))))
    if($canonical-cne[string]$m.canonical){throw 'DISTRIBUTION_CANONICAL_DRIFT'}
    return [pscustomobject][ordered]@{distributionId=[string]$m.distributionId;contentIdentity=$canonical;manifestIdentity=[string]$doc.Identity;runtimeRoot=$root}
}

function Assert-AiwDistributionBinding {
    param([Parameter(Mandatory)]$Binding,[Parameter(Mandatory)][string]$FrameworkRoot,[Parameter(Mandatory)][string]$FrameworkVersion)
    $fields=@('distributionId','contentIdentity','manifestIdentity','runtimeRoot')
    if(@($Binding.PSObject.Properties).Count-ne4-or@($fields|Where-Object{$_-cnotin$Binding.PSObject.Properties.Name}).Count-ne0){throw 'DISTRIBUTION_BINDING_FIELDS'}
    if([IO.Path]::GetFullPath($FrameworkRoot)-cne[IO.Path]::GetFullPath([string]$Binding.runtimeRoot)){throw 'DISTRIBUTION_RUNTIME_ROOT_DRIFT'}
    $current=Get-AiwDistributionBinding $FrameworkRoot $FrameworkVersion -Required
    foreach($name in $fields){if([string]$Binding.$name-cne[string]$current.$name){throw ('DISTRIBUTION_BINDING_DRIFT|'+$name)}}
    return $current
}
Export-ModuleMember -Function Get-AiwDistributionBinding,Assert-AiwDistributionBinding
function Get-AiwAdoptedDistributionBinding {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$FrameworkVersion)
    $root=Resolve-AiwRepositoryRoot $ProjectRoot
    $pendingPath=Get-AiwContainedPath $root '.ai-workspace/runtime/project-adoption/upgrade/state.json'
    if(Test-Path -LiteralPath $pendingPath -PathType Leaf){
        $pending=(Read-AiwProjectJson $pendingPath 'ADOPTION_TRANSACTION').Value
        if($pending.transactionComplete-isnot[bool]-or-not$pending.transactionComplete){throw 'ADOPTION_RECOVERY_REQUIRED'}
    }
    $upgrade=Get-AiwContainedPath $root ('.ai-workspace/upgrade-recovery/'+$FrameworkVersion+'/state.json')
    if(Test-Path -LiteralPath $upgrade -PathType Leaf){
        $state=(Read-AiwProjectJson $upgrade 'ADOPTION_STATE').Value
        if($null-ne$state.PSObject.Properties['distributionBinding']){
            if($state.transactionComplete-isnot[bool]-or-not$state.transactionComplete){throw 'ADOPTION_RECOVERY_REQUIRED'}
            return $state.distributionBinding
        }
    }
    $registration=Get-AiwContainedPath $root '.ai-workspace/runtime/project-adoption/register/state.json'
    if(Test-Path -LiteralPath $registration -PathType Leaf){
        $state=(Read-AiwProjectJson $registration 'REGISTRATION_STATE').Value
        if($null-ne$state.PSObject.Properties['metadata']-and$null-ne$state.metadata.PSObject.Properties['distributionBinding']-and$null-ne$state.metadata.distributionBinding){
            if($state.transactionComplete-isnot[bool]-or-not$state.transactionComplete-or[string]$state.state-cne'COMPLETE'){throw 'ADOPTION_RECOVERY_REQUIRED'}
            return $state.metadata.distributionBinding
        }
    }
    return $null
}
Export-ModuleMember -Function Get-AiwAdoptedDistributionBinding