[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$ToVersion,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryPath,

    [string]$ControllerId,

    [string]$RoutineExcludedPathsMigrationPath,

    [string]$ExpectedRoutineExcludedPathsMigrationIdentity,

    [switch]$Apply,

    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if($ToVersion-ceq'1.12.0'-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){
    throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'
}
if($ToVersion-ceq'1.13.0'-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){
    throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Join-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $result = $Root
    foreach ($segment in ($RelativePath -split '/')) {
        $result = Join-Path $result $segment
    }
    return $result
}

function Get-UpperSha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Assert-StableFrameworkRelease([string]$FrameworkPath,[string]$ExpectedVersion) {
    if(-not(Test-Path -LiteralPath $FrameworkPath -PathType Container)){throw "Framework version does not exist: $ExpectedVersion"}
    Assert-NoReparseTree $FrameworkPath
    $versionPath=Join-ChildPath $FrameworkPath 'VERSION.json';$manifestPath=Join-ChildPath $FrameworkPath 'RELEASE_MANIFEST.json'
    if(-not(Test-Path -LiteralPath $versionPath -PathType Leaf)-or-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "FRAMEWORK_RELEASE_METADATA_MISSING|$ExpectedVersion"}
    try{$version=(Read-StrictUtf8NoBom $versionPath)|ConvertFrom-Json;$manifest=(Read-StrictUtf8NoBom $manifestPath)|ConvertFrom-Json}catch{throw "FRAMEWORK_RELEASE_METADATA_INVALID|$ExpectedVersion"}
    if(-not($version.version-is[string])-or[string]$version.version-cne$ExpectedVersion-or-not($version.lifecycle-is[string])-or[string]$version.lifecycle-cne'STABLE'-or-not($version.consumable-is[bool])-or-not[bool]$version.consumable-or-not($version.projectPinEligible-is[bool])-or-not[bool]$version.projectPinEligible){throw "FRAMEWORK_VERSION_NOT_CONSUMABLE|$ExpectedVersion"}
    if(-not($manifest.version-is[string])-or[string]$manifest.version-cne$ExpectedVersion-or-not($manifest.lifecycle-is[string])-or[string]$manifest.lifecycle-cne'STABLE'-or-not($manifest.sourceReview-is[string])-or[string]$manifest.sourceReview-cne'APPROVED'-or-not($manifest.releaseIntegration-is[string])-or[string]::IsNullOrWhiteSpace([string]$manifest.releaseIntegration)-or[string]$manifest.releaseIntegration-ceq'PENDING'-or-not(Test-MinimalJsonInteger $manifest.fileCount)-or-not(Test-MinimalJsonInteger $manifest.totalBytes)-or-not($manifest.canonical-is[string])-or[string]$manifest.canonical-cnotmatch'^[A-F0-9]{64}$'){throw "FRAMEWORK_RELEASE_NOT_SEALED|$ExpectedVersion"}
    $rows=New-Object 'System.Collections.Generic.List[string]';[int64]$totalBytes=0
    foreach($file in @(Get-ChildItem -LiteralPath $FrameworkPath -Recurse -File -Force)){$relative=$file.FullName.Substring($FrameworkPath.Length+1).Replace('\','/');if($relative-ceq'RELEASE_MANIFEST.json'){continue};$bytes=[IO.File]::ReadAllBytes($file.FullName);$totalBytes+=$bytes.Length;$rows.Add($relative+'|'+$bytes.Length+'|'+(Get-UpperSha256Bytes $bytes))}
    [string[]]$ordered=@($rows);[Array]::Sort($ordered,[StringComparer]::Ordinal);$canonical=Get-UpperSha256Bytes ($utf8NoBom.GetBytes([string]::Join("`n",$ordered)))
    if([int64]$manifest.fileCount-ne$ordered.Count-or[int64]$manifest.totalBytes-ne$totalBytes-or[string]$manifest.canonical-cne$canonical){throw "FRAMEWORK_RELEASE_MANIFEST_DRIFT|$ExpectedVersion"}
}

function Normalize-Text {
    param([Parameter(Mandatory = $true)][string]$Content)

    $normalized = $Content -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    return $normalized
}

function Read-StrictUtf8NoBom {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ConvertFrom-StrictUtf8NoBomBytes $bytes $Path
}

function ConvertFrom-StrictUtf8NoBomBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Source
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        throw "File must be UTF-8 without BOM: $Source"
    }
    try {
        $content = $utf8Strict.GetString($Bytes)
    }
    catch {
        throw "File is not strict UTF-8: $Source"
    }
    if ($content.Contains([char]0) -or $content.Contains([char]0xFFFD)) {
        throw "File contains a forbidden text code point: $Source"
    }
    if ($content.Contains("`r")) {
        throw "File must use LF line endings: $Source"
    }
    if (-not $content.EndsWith("`n")) {
        throw "File must end with LF: $Source"
    }
    return $content
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, (Normalize-Text $Content), $utf8NoBom)
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

function Render-Bootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)]$ProjectConfig,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion
    )

    $tokens = [ordered]@{
        '{{PROJECT_ID}}' = [string]$ProjectConfig.id
        '{{DISPLAY_NAME}}' = [string]$ProjectConfig.displayName
        '{{FRAMEWORK_VERSION}}' = $FrameworkVersion
    }
    if ($ProjectConfig.PSObject.Properties.Name -contains 'repositoryPath') {
        $tokens['{{REPOSITORY_PATH}}'] = [string]$ProjectConfig.repositoryPath
    }
    $rendered = $Template
    foreach ($token in $tokens.GetEnumerator()) {
        $rendered = $rendered.Replace($token.Key, $token.Value)
    }
    if ($rendered -match '\{\{[A-Z0-9_]+\}\}') {
        throw "Bootstrap template contains an unresolved token for Framework $FrameworkVersion."
    }
    return Normalize-Text $rendered
}

function Assert-TargetBootstrapContract {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$FrameworkVersion,
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$TargetFramework,
        [Parameter(Mandatory = $true)][ValidateSet('repo-local')][string]$Layout
    )

    $versionedChecker = Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1'
    if (-not (Test-Path -LiteralPath $versionedChecker -PathType Leaf)) {
        throw "Target Framework checker does not exist: $versionedChecker"
    }
    $hasVersionedChecker = $Content.Contains("framework/versions/$FrameworkVersion/scripts/check-task-card.ps1") -or
        ($Content.Contains("framework/versions/$FrameworkVersion/RECOVERY_CORE.md") -and
            ($Content.Contains('<FW>/scripts/resolve-load-plan.ps1') -or ($Content.Contains('TOOLCHAIN.json') -and $Content.Contains('LOAD_PLAN_RESOLVE'))))
    if (-not $Content.Contains('<!-- FRAMEWORK-MANAGED:BEGIN -->') -or
        -not $Content.Contains('<!-- FRAMEWORK-MANAGED:END -->') -or
        -not $hasVersionedChecker) {
        throw "Target repo-local Bootstrap does not contain its managed block and versioned checker locator."
    }
    if ($Content -match '(?i)[A-Z]:\\[^\r\n]*framework\\versions') {
        throw 'Target repo-local Bootstrap contains a machine-absolute Framework locator.'
    }
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

function Assert-NoReparseTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = Get-Item -LiteralPath $Path -Force
    if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed in a project control plane: $Path"
    }
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in a project control plane: $($item.FullName)"
        }
    }
}

function Assert-NoReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if(($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)-ne 0){throw "Reparse points are not allowed in a project control path: $Path"}
}

function Get-ManagedBootstrapBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $begin = '<!-- FRAMEWORK-MANAGED:BEGIN -->'
    $end = '<!-- FRAMEWORK-MANAGED:END -->'
    $customBegin = '<!-- PROJECT-CUSTOM:BEGIN -->'
    $customEnd = '<!-- PROJECT-CUSTOM:END -->'
    foreach ($marker in @($begin, $end, $customBegin, $customEnd)) {
        if ([regex]::Matches($Content, [regex]::Escape($marker)).Count -ne 1) {
            throw "Repo-local Bootstrap markers must each appear exactly once: $Source"
        }
    }
    $beginIndex = $Content.IndexOf($begin, [System.StringComparison]::Ordinal)
    $endIndex = $Content.IndexOf($end, [System.StringComparison]::Ordinal)
    $customBeginIndex = $Content.IndexOf($customBegin, [System.StringComparison]::Ordinal)
    $customEndIndex = $Content.IndexOf($customEnd, [System.StringComparison]::Ordinal)
    if (-not ($beginIndex -lt $endIndex -and
              $endIndex -lt $customBeginIndex -and
              $customBeginIndex -lt $customEndIndex)) {
        throw "Repo-local Bootstrap markers must be paired and ordered managed-then-custom: $Source"
    }
    $blockEnd = $endIndex + $end.Length
    return [pscustomobject]@{
        Start = $beginIndex
        End = $blockEnd
        Text = $Content.Substring($beginIndex, $blockEnd - $beginIndex)
    }
}

function Replace-ManagedBootstrapBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Current,
        [Parameter(Mandatory = $true)][string]$TargetManaged,
        [Parameter(Mandatory = $true)]$CurrentBlock
    )

    return Normalize-Text ($Current.Substring(0, $CurrentBlock.Start) + $TargetManaged + $Current.Substring($CurrentBlock.End))
}

function Get-CorrectionBootstrapBlock([string]$Content,[string]$Source,[switch]$Optional) {
    $begin='<!-- PROJECT-CORRECTIONS:BEGIN -->';$end='<!-- PROJECT-CORRECTIONS:END -->'
    $beginCount=[regex]::Matches($Content,[regex]::Escape($begin)).Count;$endCount=[regex]::Matches($Content,[regex]::Escape($end)).Count
    if($beginCount-eq0-and$endCount-eq0-and$Optional){return $null}
    if($beginCount-ne1-or$endCount-ne1){throw "Project-correction Bootstrap markers must appear once or not at all: $Source"}
    $start=$Content.IndexOf($begin,[StringComparison]::Ordinal);$endIndex=$Content.IndexOf($end,[StringComparison]::Ordinal)
    if($start-ge$endIndex){throw "Project-correction Bootstrap markers are out of order: $Source"}
    $blockEnd=$endIndex+$end.Length
    return [pscustomobject]@{Start=$start;End=$blockEnd;Text=$Content.Substring($start,$blockEnd-$start)}
}

function Merge-CorrectionBootstrapBlock([string]$CurrentTarget,[string]$RenderedTemplate,[string]$Source) {
    $wanted=Get-CorrectionBootstrapBlock $RenderedTemplate $Source -Optional
    if($null-eq$wanted){return Normalize-Text $CurrentTarget}
    $existing=Get-CorrectionBootstrapBlock $CurrentTarget 'current Bootstrap' -Optional
    if($null-eq$existing){return Normalize-Text ($CurrentTarget.TrimEnd("`n")+"`n`n"+$wanted.Text+"`n")}
    return Normalize-Text ($CurrentTarget.Substring(0,$existing.Start)+$wanted.Text+$CurrentTarget.Substring($existing.End))
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-MinimalJsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Get-MinimalFileIdentity([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return $bytes.Length.ToString()+'|'+([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-MinimalBytesIdentity([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return $Bytes.Length.ToString()+'|'+([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Assert-MinimalExactFields($Object,[string]$Raw,[string[]]$Expected,[string]$Label) {
    if (-not ($Object -is [pscustomobject])) { throw "$Label must be a JSON object." }
    $names=@($Object.PSObject.Properties.Name)
    if ($names.Count -ne $Expected.Count -or @($Expected|Where-Object{$_ -cnotin $names}).Count -ne 0) { throw "$Label field set mismatch." }
    foreach($name in $Expected){$expectedCount=if($name-ceq'schemaVersion'-and'processPolicy'-cin$names){2}else{1};if([regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count-ne$expectedCount){throw "$Label duplicate or missing field: $name"}}
}

function ConvertTo-MinimalFrameworkLocator([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)-or$Value-cne$Value.Trim()){throw 'Framework capability locator is empty or has outer whitespace.'}
    $path=$Value.Replace('\','/')
    if([regex]::IsMatch($path,'[<>"|?*]')-or[IO.Path]::IsPathRooted($path)-or$path.StartsWith('/')-or$path.Contains(':')){throw 'Framework capability locator must be a repo-relative literal path.'}
    if(-not[string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)){throw 'Framework capability locator must be NFC.'}
    $parts=$path.Split('/')
    foreach($part in $parts){
        if([string]::IsNullOrEmpty($part)-or$part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or[regex]::IsMatch($part,'[\x00-\x1F]')){throw 'Framework capability locator has an invalid component.'}
        if($part.Split('.')[0]-match'^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw 'Framework capability locator has a reserved component.'}
    }
    return [string]::Join('/',$parts)
}

function Assert-MinimalFrameworkCapabilities($Capabilities,[string]$Raw,[string]$Label) {
    if(-not($Capabilities-is[pscustomobject])){throw "$Label must be an object."}
    $names=@($Capabilities.PSObject.Properties|ForEach-Object{$_.Name})
    if($names.Count-eq0){return}
    if($names.Count-ne1-or$names[0]-cne'KNOWLEDGE_REFERENCE'-or[regex]::Matches($Raw,'"KNOWLEDGE_REFERENCE"\s*:').Count-ne1){throw "$Label contains an unknown or duplicate capability."}
    $knowledge=$Capabilities.KNOWLEDGE_REFERENCE
    if(-not($knowledge-is[pscustomobject])){throw "$Label KNOWLEDGE_REFERENCE must be an object."}
    $fields=@($knowledge.PSObject.Properties|ForEach-Object{$_.Name})
    if($fields.Count-eq1-and$fields[0]-ceq'enabled'-and$knowledge.enabled-is[bool]-and-not[bool]$knowledge.enabled){
        if([regex]::Matches($Raw,'"enabled"\s*:').Count-ne1){throw "$Label KNOWLEDGE_REFERENCE has a duplicate field."}
        return
    }
    if($fields.Count-ne2-or$fields-cnotcontains'enabled'-or$fields-cnotcontains'indexLocator'-or-not($knowledge.enabled-is[bool])-or-not[bool]$knowledge.enabled-or-not($knowledge.indexLocator-is[string])-or[regex]::Matches($Raw,'"enabled"\s*:').Count-ne1-or[regex]::Matches($Raw,'"indexLocator"\s*:').Count-ne1){throw "$Label KNOWLEDGE_REFERENCE fields are invalid."}
    $null=ConvertTo-MinimalFrameworkLocator ([string]$knowledge.indexLocator)
}

function Assert-MinimalController($Controller,[string]$Raw,[string]$ExpectedProjectId,[string]$ExpectedControllerId) {
    Assert-MinimalExactFields $Controller $Raw @('schemaVersion','projectId','controllerId','controllerEpoch','state') 'controller.json'
    if(-not(Test-MinimalJsonInteger $Controller.schemaVersion)-or[int]$Controller.schemaVersion-ne 1-or
       -not($Controller.projectId-is[string])-or[string]$Controller.projectId-cne$ExpectedProjectId-or
       -not($Controller.controllerId-is[string])-or[string]::IsNullOrWhiteSpace([string]$Controller.controllerId)-or
       (-not[string]::IsNullOrWhiteSpace($ExpectedControllerId)-and[string]$Controller.controllerId-cne$ExpectedControllerId)-or
       -not(Test-MinimalJsonInteger $Controller.controllerEpoch)-or[int64]$Controller.controllerEpoch-lt 1-or
       -not($Controller.state-is[string])-or[string]$Controller.state-cne'CURRENT'){throw 'controller.json values are invalid.'}
}

function Assert-MinimalPathInsideRepo([string]$Repo,[string]$Path) {
    $root=[IO.Path]::GetFullPath($Repo).TrimEnd('\')
    $full=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath).TrimEnd('\')
    if(-not($full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Migration input must be inside the repository.'}
    $current=$root
    Assert-NoReparsePoint $current
    foreach($part in $full.Substring($root.Length+1).Split('\')){$current=Join-Path $current $part;Assert-NoReparsePoint $current}
}

function Get-UpgradeLiveState([string]$ProjectFile,[string]$BootstrapFile,[string]$ControllerFile,$State) {
    $project=if(Test-Path -LiteralPath $ProjectFile -PathType Leaf){Get-MinimalFileIdentity $ProjectFile}else{'MISSING'}
    $bootstrap=if(Test-Path -LiteralPath $BootstrapFile -PathType Leaf){Get-MinimalFileIdentity $BootstrapFile}else{'MISSING'}
    $correctionsFile=Join-Path (Split-Path -Parent $ProjectFile) 'corrections.json'
    $corrections=if([string]$State.correctionsMode-ceq'NONE'){'IGNORED'}elseif(Test-Path -LiteralPath $correctionsFile -PathType Leaf){Get-MinimalFileIdentity $correctionsFile}else{'MISSING'}
    $controller=if([string]$State.controllerMode-ceq'CREATE'){
        if(Test-Path -LiteralPath $ControllerFile -PathType Leaf){Get-MinimalFileIdentity $ControllerFile}else{'MISSING'}
    }else{'IGNORED'}
    $knownProject=$project-in@([string]$State.oldProjectIdentity,[string]$State.newProjectIdentity)
    $knownBootstrap=$bootstrap-in@([string]$State.oldBootstrapIdentity,[string]$State.newBootstrapIdentity)
    $knownController=if([string]$State.controllerMode-ceq'CREATE'){$controller-in@('MISSING',[string]$State.newControllerIdentity)}else{$true}
    $knownCorrections=if([string]$State.correctionsMode-ceq'NONE'){$true}else{$corrections-in@([string]$State.oldCorrectionsIdentity,[string]$State.newCorrectionsIdentity)}
    $newCorrections=if([string]$State.correctionsMode-ceq'NONE'){$true}else{$corrections-ceq[string]$State.newCorrectionsIdentity}
    $oldCorrections=if([string]$State.correctionsMode-ceq'NONE'){$true}else{$corrections-ceq[string]$State.oldCorrectionsIdentity}
    $newController=if([string]$State.controllerMode-ceq'CREATE'){$controller-ceq[string]$State.newControllerIdentity}else{$true}
    $oldController=if([string]$State.controllerMode-ceq'CREATE'){$controller-ceq'MISSING'}else{$true}
    $status=if(-not($knownProject-and$knownBootstrap-and$knownController-and$knownCorrections)){'UNKNOWN'}elseif($project-ceq[string]$State.newProjectIdentity-and$bootstrap-ceq[string]$State.newBootstrapIdentity-and$newController-and$newCorrections){'NEW'}elseif($project-ceq[string]$State.oldProjectIdentity-and$bootstrap-ceq[string]$State.oldBootstrapIdentity-and$oldController-and$oldCorrections){'OLD'}else{'MIXED'}
    return [pscustomobject]@{Status=$status;Project=$project;Bootstrap=$bootstrap;Controller=$controller;Corrections=$corrections}
}

function Set-UpgradeFile([string]$Source,[string]$Destination,[string]$ExpectedCurrentIdentity,[string]$ExpectedNewIdentity) {
    if(-not(Test-Path -LiteralPath $Source -PathType Leaf)-or(Get-MinimalFileIdentity $Source)-cne$ExpectedNewIdentity){throw 'TRANSACTION_MATERIAL_DRIFT'}
    $current=if(Test-Path -LiteralPath $Destination -PathType Leaf){Get-MinimalFileIdentity $Destination}else{'MISSING'}
    if($current-cne$ExpectedCurrentIdentity){throw "OBJECT_DRIFT|$Destination"}
    [IO.File]::Copy($Source,$Destination,($ExpectedCurrentIdentity-cne'MISSING'))
    if((Get-MinimalFileIdentity $Destination)-cne$ExpectedNewIdentity){throw "REPLACE_VERIFY_FAILED|$Destination"}
}

function Complete-UpgradeTransaction([string]$Root,[string]$ProjectRoot,$State) {
    $resolved=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $expected=[IO.Path]::GetFullPath((Join-Path $ProjectRoot '.framework-upgrade-transaction')).TrimEnd('\')
    if(-not$resolved.Equals($expected,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected upgrade transaction path.'}
    $completed=Join-Path $ProjectRoot ('.framework-upgrade-recovery-'+[string]$State.transactionId)
    if(Test-Path -LiteralPath $completed){throw 'Recovery path already exists; active transaction preserved.'}
    [IO.Directory]::Move($resolved,$completed)
    return $completed
}

function Read-UpgradeTransaction([string]$Root,[string]$ProjectId) {
    Assert-NoReparseTree $Root
    $raw=Read-StrictUtf8NoBom (Join-Path $Root 'state.json')
    try{$state=$raw|ConvertFrom-Json}catch{throw 'Invalid upgrade transaction state.'}
    $schemaVersion=if(Test-MinimalJsonInteger $state.schemaVersion){[int]$state.schemaVersion}else{-1}
    $fields=if($schemaVersion-eq1){@('schemaVersion','transactionId','projectId','fromVersion','toVersion','controllerMode','oldProjectIdentity','oldBootstrapIdentity','newProjectIdentity','newBootstrapIdentity','newControllerIdentity')}else{@('schemaVersion','transactionId','projectId','fromVersion','toVersion','controllerMode','correctionsMode','oldProjectIdentity','oldBootstrapIdentity','oldCorrectionsIdentity','newProjectIdentity','newBootstrapIdentity','newCorrectionsIdentity','newControllerIdentity')}
    Assert-MinimalExactFields $state $raw $fields 'upgrade transaction state'
    if($schemaVersion-cnotin@(1,2)-or
       -not($state.transactionId-is[string])-or[string]$state.transactionId-cnotmatch'^[a-f0-9]{32}$'-or
       -not($state.projectId-is[string])-or[string]$state.projectId-cne$ProjectId-or
       -not($state.fromVersion-is[string])-or[string]::IsNullOrWhiteSpace([string]$state.fromVersion)-or
       -not($state.toVersion-is[string])-or[string]::IsNullOrWhiteSpace([string]$state.toVersion)-or
        -not($state.controllerMode-is[string])-or[string]$state.controllerMode-cnotin@('NONE','CREATE')){throw 'Upgrade transaction state identity mismatch.'}
    if($schemaVersion-eq1){$state|Add-Member -NotePropertyName correctionsMode -NotePropertyValue 'NONE';$state|Add-Member -NotePropertyName oldCorrectionsIdentity -NotePropertyValue 'IGNORED';$state|Add-Member -NotePropertyName newCorrectionsIdentity -NotePropertyValue 'IGNORED'}
    if(-not($state.correctionsMode-is[string])-or[string]$state.correctionsMode-cnotin@('NONE','CREATE','PRESERVE')){throw 'Upgrade correction transaction mode is invalid.'}
    foreach($name in @('oldProjectIdentity','oldBootstrapIdentity','newProjectIdentity','newBootstrapIdentity')){if([string]$state.$name-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'Upgrade transaction identity is invalid.'}}
    if(([string]$state.controllerMode-ceq'NONE'-and[string]$state.newControllerIdentity-cne'NONE')-or
       ([string]$state.controllerMode-ceq'CREATE'-and[string]$state.newControllerIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'Upgrade controller transaction identity is invalid.'}
    if([string]$state.correctionsMode-ceq'NONE'){
        if([string]$state.oldCorrectionsIdentity-cne'IGNORED'-or[string]$state.newCorrectionsIdentity-cne'IGNORED'){throw 'Upgrade corrections NONE identities are invalid.'}
    }elseif([string]$state.correctionsMode-ceq'CREATE'){
        if([string]$state.oldCorrectionsIdentity-cne'MISSING'-or[string]$state.newCorrectionsIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'Upgrade corrections CREATE identities are invalid.'}
    }elseif([string]$state.oldCorrectionsIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$state.newCorrectionsIdentity-cne[string]$state.oldCorrectionsIdentity){throw 'Upgrade corrections PRESERVE identities are invalid.'}
    $materials=[ordered]@{
        'old/project.json'=[string]$state.oldProjectIdentity;'old/BOOTSTRAP.md'=[string]$state.oldBootstrapIdentity;
        'new/project.json'=[string]$state.newProjectIdentity;'new/BOOTSTRAP.md'=[string]$state.newBootstrapIdentity
    }
    if([string]$state.controllerMode-ceq'CREATE'){$materials['new/controller.json']=[string]$state.newControllerIdentity}
    if([string]$state.correctionsMode-ceq'CREATE'){$materials['new/corrections.json']=[string]$state.newCorrectionsIdentity}
    if([string]$state.correctionsMode-ceq'PRESERVE'){$materials['old/corrections.json']=[string]$state.oldCorrectionsIdentity}
    foreach($entry in $materials.GetEnumerator()){$path=Join-ChildPath $Root $entry.Key;if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-MinimalFileIdentity $path)-cne$entry.Value){throw 'Upgrade transaction material drift; preserved.'}}
    return $state
}

function Recover-UpgradeTransaction([string]$Root,[string]$ProjectRoot,[string]$ProjectFile,[string]$BootstrapFile,[string]$ControllerFile,[string]$ProjectId,[string]$ControllerId,[string]$RequestedTarget,[switch]$Preview) {
    $state=Read-UpgradeTransaction $Root $ProjectId
    if([string]$state.toVersion-cne$RequestedTarget){throw 'Requested target does not match the active upgrade transaction.'}
    if([string]$state.controllerMode-ceq'CREATE'){
        if([string]$state.toVersion-cne'1.6.0'-or[string]$state.fromVersion-cnotin@('1.4.1','1.5.0','1.5.1','1.5.2')){throw 'Unsupported upgrade recovery matrix combination.'}
        if([string]::IsNullOrWhiteSpace($ControllerId)){throw 'ControllerId is required for Framework 1.6.0 transaction recovery.'}
        $frozenControllerPath=Join-ChildPath $Root 'new/controller.json'
        if(-not(Test-Path -LiteralPath $frozenControllerPath -PathType Leaf)){throw 'Frozen recovery controller.json is missing.'}
        Assert-NoReparsePoint $frozenControllerPath
        $frozenControllerRaw=Read-StrictUtf8NoBom $frozenControllerPath
        try{$frozenController=$frozenControllerRaw|ConvertFrom-Json}catch{throw 'Frozen recovery controller.json is invalid.'}
        Assert-MinimalController $frozenController $frozenControllerRaw $ProjectId $ControllerId
    }elseif([string]$state.controllerMode-ceq'NONE'-and[string]$state.fromVersion-cin@('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')-and[string]$state.toVersion-cin@('1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')){
        if([string]::IsNullOrWhiteSpace($ControllerId)){throw 'ControllerId is required for schema3 transaction recovery.'}
        if(-not(Test-Path -LiteralPath $ControllerFile -PathType Leaf)){throw 'Schema3 patch recovery controller.json is missing.'}
        Assert-NoReparsePoint $ControllerFile
        $currentControllerRaw=Read-StrictUtf8NoBom $ControllerFile
        try{$currentController=$currentControllerRaw|ConvertFrom-Json}catch{throw 'Schema3 patch recovery controller.json is invalid.'}
        Assert-MinimalController $currentController $currentControllerRaw $ProjectId $ControllerId
    }elseif([string]$state.toVersion-cin@('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')){
        throw 'Unsupported upgrade recovery matrix combination.'
    }
    if($Preview){return ('RECOVERY_REQUIRED|from='+[string]$state.fromVersion+'|to='+[string]$state.toVersion+'|controllerMode='+[string]$state.controllerMode)}
    $live=Get-UpgradeLiveState $ProjectFile $BootstrapFile $ControllerFile $state
    if($live.Status-ceq'UNKNOWN'){throw 'Unknown live bytes during upgrade recovery; transaction preserved.'}
    if($live.Status-ceq'NEW'){$completed=Complete-UpgradeTransaction $Root $ProjectRoot $state;return "RECOVERED_COMMIT|recovery=$completed"}
    if($live.Status-ceq'OLD'){$completed=Complete-UpgradeTransaction $Root $ProjectRoot $state;return "RECOVERED_ROLLBACK|recovery=$completed"}
    if($live.Project-cne[string]$state.oldProjectIdentity){Set-UpgradeFile (Join-ChildPath $Root 'old/project.json') $ProjectFile $live.Project ([string]$state.oldProjectIdentity)}
    if($live.Bootstrap-cne[string]$state.oldBootstrapIdentity){Set-UpgradeFile (Join-ChildPath $Root 'old/BOOTSTRAP.md') $BootstrapFile $live.Bootstrap ([string]$state.oldBootstrapIdentity)}
    $correctionsFile=Join-Path $ProjectRoot 'corrections.json'
    if([string]$state.correctionsMode-ceq'CREATE'-and$live.Corrections-cne'MISSING'){
        if($live.Corrections-cne[string]$state.newCorrectionsIdentity){throw 'Unknown corrections bytes during recovery; transaction preserved.'}
        [IO.File]::Delete($correctionsFile)
    }
    if([string]$state.controllerMode-ceq'CREATE'-and$live.Controller-cne'MISSING'){
        if($live.Controller-cne[string]$state.newControllerIdentity){throw 'Unknown controller bytes during recovery; transaction preserved.'}
        if((Get-MinimalFileIdentity $ControllerFile)-cne[string]$state.newControllerIdentity){throw 'Controller drift during recovery; transaction preserved.'}
        [IO.File]::Delete($ControllerFile)
    }
    $final=Get-UpgradeLiveState $ProjectFile $BootstrapFile $ControllerFile $state
    if($final.Status-cne'OLD'){throw 'Upgrade rollback verification failed; transaction preserved.'}
    $completed=Complete-UpgradeTransaction $Root $ProjectRoot $state
    return "RECOVERED_ROLLBACK|recovery=$completed"
}

function New-UpgradeTransaction([string]$Root,[string]$ProjectRoot,[string]$ProjectFile,[string]$BootstrapFile,[string]$ControllerFile,[string]$ProjectId,[string]$FromVersion,[string]$TargetVersion,[string]$TargetProject,[string]$TargetBootstrap,[string]$ControllerMode,[string]$TargetController,[string]$AdditionalInputPath,[string]$ExpectedAdditionalInputIdentity,[string]$CorrectionsMode='NONE',[string]$TargetCorrections='') {
    if(Test-Path -LiteralPath $Root){throw 'An active upgrade transaction already exists.'}
    if($ControllerMode-cnotin@('NONE','CREATE')){throw 'Unsupported controller transaction mode.'}
    if($CorrectionsMode-cnotin@('NONE','CREATE','PRESERVE')){throw 'Unsupported corrections transaction mode.'}
    $oldProjectIdentity=Get-MinimalFileIdentity $ProjectFile;$oldBootstrapIdentity=Get-MinimalFileIdentity $BootstrapFile
    $correctionsFile=Join-Path $ProjectRoot 'corrections.json';$oldCorrectionsIdentity=if(Test-Path -LiteralPath $correctionsFile -PathType Leaf){Get-MinimalFileIdentity $correctionsFile}else{'MISSING'}
    if($CorrectionsMode-ceq'CREATE'-and$oldCorrectionsIdentity-cne'MISSING'){throw 'Unexpected corrections object before transaction freeze.'}
    if($CorrectionsMode-ceq'PRESERVE'-and$oldCorrectionsIdentity-ceq'MISSING'){throw 'Expected corrections object is missing before transaction freeze.'}
    if($ControllerMode-ceq'CREATE'-and(Test-Path -LiteralPath $ControllerFile)){throw 'Unexpected controller object before transaction freeze.'}
    $transactionId=[Guid]::NewGuid().ToString('N')
    $staging=Join-Path $ProjectRoot ('.fwu-prep-'+$transactionId)
    try{
        New-Item -ItemType Directory -Path (Join-ChildPath $staging 'old'),(Join-ChildPath $staging 'new')|Out-Null
        [IO.File]::Copy($ProjectFile,(Join-ChildPath $staging 'old/project.json'),$false);[IO.File]::Copy($BootstrapFile,(Join-ChildPath $staging 'old/BOOTSTRAP.md'),$false)
        Write-Utf8NoBom (Join-ChildPath $staging 'new/project.json') $TargetProject;Write-Utf8NoBom (Join-ChildPath $staging 'new/BOOTSTRAP.md') $TargetBootstrap
        $newControllerIdentity='NONE'
        if($ControllerMode-ceq'CREATE'){
            Write-Utf8NoBom (Join-ChildPath $staging 'new/controller.json') $TargetController
            $newControllerIdentity=Get-MinimalFileIdentity (Join-ChildPath $staging 'new/controller.json')
        }
        $newCorrectionsIdentity='IGNORED';$stateOldCorrections='IGNORED'
        if($CorrectionsMode-ceq'CREATE'){Write-Utf8NoBom (Join-ChildPath $staging 'new/corrections.json') $TargetCorrections;$newCorrectionsIdentity=Get-MinimalFileIdentity (Join-ChildPath $staging 'new/corrections.json');$stateOldCorrections='MISSING'}
        elseif($CorrectionsMode-ceq'PRESERVE'){[IO.File]::Copy($correctionsFile,(Join-ChildPath $staging 'old/corrections.json'),$false);$newCorrectionsIdentity=$oldCorrectionsIdentity;$stateOldCorrections=$oldCorrectionsIdentity}
        $state=[ordered]@{schemaVersion=2;transactionId=$transactionId;projectId=$ProjectId;fromVersion=$FromVersion;toVersion=$TargetVersion;controllerMode=$ControllerMode;correctionsMode=$CorrectionsMode;oldProjectIdentity=$oldProjectIdentity;oldBootstrapIdentity=$oldBootstrapIdentity;oldCorrectionsIdentity=$stateOldCorrections;newProjectIdentity=Get-MinimalFileIdentity (Join-ChildPath $staging 'new/project.json');newBootstrapIdentity=Get-MinimalFileIdentity (Join-ChildPath $staging 'new/BOOTSTRAP.md');newCorrectionsIdentity=$newCorrectionsIdentity;newControllerIdentity=$newControllerIdentity}
        Write-Utf8NoBom (Join-Path $staging 'state.json') ($state|ConvertTo-Json -Depth 5)
        if((Get-MinimalFileIdentity (Join-ChildPath $staging 'old/project.json'))-cne$oldProjectIdentity-or(Get-MinimalFileIdentity (Join-ChildPath $staging 'old/BOOTSTRAP.md'))-cne$oldBootstrapIdentity){throw 'Frozen old transaction material drift.'}
        if((Get-MinimalFileIdentity $ProjectFile)-cne$oldProjectIdentity-or(Get-MinimalFileIdentity $BootstrapFile)-cne$oldBootstrapIdentity){throw 'OBJECT_DRIFT before transaction freeze.'}
        $currentCorrectionsIdentity=if(Test-Path -LiteralPath $correctionsFile -PathType Leaf){Get-MinimalFileIdentity $correctionsFile}else{'MISSING'}
        if($CorrectionsMode-cne'NONE'-and$currentCorrectionsIdentity-cne$oldCorrectionsIdentity){throw 'OBJECT_DRIFT before corrections transaction freeze.'}
        if($ControllerMode-ceq'CREATE'-and(Test-Path -LiteralPath $ControllerFile)){throw 'OBJECT_DRIFT before controller transaction freeze.'}
        if(-not[string]::IsNullOrWhiteSpace($AdditionalInputPath)-and((Get-MinimalFileIdentity $AdditionalInputPath)-cne$ExpectedAdditionalInputIdentity)){throw 'Additional migration input drift before transaction freeze.'}
        [IO.Directory]::Move($staging,$Root)
        return [pscustomobject]$state
    }catch{throw "Transaction preparation failed; staging preserved at $staging. $($_.Exception.Message)"}
}

function Commit-UpgradeTransaction([string]$Root,[string]$ProjectRoot,[string]$ProjectFile,[string]$BootstrapFile,[string]$ControllerFile,[string]$ProjectId,[string]$ControllerId,[string]$RequestedTarget) {
    $state=Read-UpgradeTransaction $Root $ProjectId
    if([string]$state.toVersion-cne$RequestedTarget){throw 'Requested target does not match the prepared upgrade transaction.'}
    try{
        $correctionsFile=Join-Path $ProjectRoot 'corrections.json'
        if([string]$state.correctionsMode-ceq'CREATE'){Set-UpgradeFile (Join-ChildPath $Root 'new/corrections.json') $correctionsFile 'MISSING' ([string]$state.newCorrectionsIdentity)}
        Set-UpgradeFile (Join-ChildPath $Root 'new/project.json') $ProjectFile ([string]$state.oldProjectIdentity) ([string]$state.newProjectIdentity)
        Set-UpgradeFile (Join-ChildPath $Root 'new/BOOTSTRAP.md') $BootstrapFile ([string]$state.oldBootstrapIdentity) ([string]$state.newBootstrapIdentity)
        if([string]$state.controllerMode-ceq'CREATE'){Set-UpgradeFile (Join-ChildPath $Root 'new/controller.json') $ControllerFile 'MISSING' ([string]$state.newControllerIdentity)}
        $final=Get-UpgradeLiveState $ProjectFile $BootstrapFile $ControllerFile $state
        if($final.Status-cne'NEW'){throw 'Final upgrade object snapshot failed.'}
        return Complete-UpgradeTransaction $Root $ProjectRoot $state
    }catch{
        $failure=$_
        try{$null=Recover-UpgradeTransaction $Root $ProjectRoot $ProjectFile $BootstrapFile $ControllerFile $ProjectId $ControllerId $RequestedTarget}catch{throw "Upgrade failed and recovery is incomplete; transaction preserved. Commit: $($failure.Exception.Message); recovery: $($_.Exception.Message)"}
        throw "Upgrade failed and was rolled back: $($failure.Exception.Message)"
    }
}

function Invoke-CorrectionEvaluation([string]$Evaluator,[string]$ProjectRepository,[string]$FrameworkWorkspace,[string]$Version,[string]$ProjectConfigFile,[string]$CorrectionsFile,[string]$EvaluationOperation,[switch]$AllowMissing) {
    if([string]::IsNullOrWhiteSpace($Evaluator)){return $null}
    $invokeParameters=@{
        ProjectRoot=$ProjectRepository
        FrameworkRoot=$FrameworkWorkspace
        TargetVersion=$Version
        ExpectedProjectConfigIdentity=(Get-MinimalFileIdentity $ProjectConfigFile)
        Operation=$EvaluationOperation
        AsJson=$true
    }
    if(Test-Path -LiteralPath $CorrectionsFile -PathType Leaf){$invokeParameters.ExpectedCorrectionsIdentity=Get-MinimalFileIdentity $CorrectionsFile}else{$invokeParameters.AllowMissingCorrections=$true}
    $output=@(& $Evaluator @invokeParameters 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
    $joined=$output -join ''
    try{$result=$joined|ConvertFrom-Json}catch{throw "Project correction evaluator returned invalid output: $joined"}
    if($code-eq3-and[string]$result.status-ceq'CONFLICT'){return $result}
    if($code-ne0-or[string]$result.status-ceq'FAIL'){throw "PROJECT_CORRECTION_EVALUATION_FAILED|$joined"}
    return $result
}

function Invoke-CorrectionEvaluationProjected([string]$Evaluator,[string]$FrameworkWorkspace,[string]$Version,[string]$TargetConfig,[string]$TargetBootstrap,[string]$CorrectionsFile,[string]$ProcessPolicyFile,[switch]$AllowMissing) {
    $projectionRoot=Join-Path ([IO.Path]::GetTempPath()) ('aiw-correction-projection-'+[guid]::NewGuid().ToString('N'))
    $projectionControl=Join-Path $projectionRoot '.ai-workspace'
    try{
        New-Item -ItemType Directory -Path $projectionControl -Force|Out-Null
        $projectionConfig=Join-Path $projectionControl 'project.json';[IO.File]::WriteAllText($projectionConfig,$TargetConfig,$utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $projectionControl 'BOOTSTRAP.md'),$TargetBootstrap,$utf8NoBom)
        try{$projectedConfig=$TargetConfig|ConvertFrom-Json}catch{throw 'Projected project configuration is invalid JSON.'}
        if($null-ne$projectedConfig.PSObject.Properties['processPolicy']){
            if([string]::IsNullOrWhiteSpace($ProcessPolicyFile)-or-not(Test-Path -LiteralPath $ProcessPolicyFile -PathType Leaf)){throw 'Projected process policy is missing.'}
            Copy-Item -LiteralPath $ProcessPolicyFile -Destination (Join-Path $projectionControl 'process-policy.json')
        }
        $projectionCorrections=Join-Path $projectionControl 'corrections.json'
        if(Test-Path -LiteralPath $CorrectionsFile -PathType Leaf){Copy-Item -LiteralPath $CorrectionsFile -Destination $projectionCorrections}
        return Invoke-CorrectionEvaluation $Evaluator $projectionRoot $FrameworkWorkspace $Version $projectionConfig $projectionCorrections 'PRECHECK' -AllowMissing:($AllowMissing-or-not(Test-Path -LiteralPath $projectionCorrections -PathType Leaf))
    }finally{if(Test-Path -LiteralPath $projectionRoot){Remove-Item -LiteralPath $projectionRoot -Recurse -Force}}
}

function Write-CorrectionEvaluation($Result,[string]$Phase) {
    if($null-eq$Result){Write-Host "Project corrections ($Phase): NOT_PRESENT";return}
    Write-Host ("Project corrections ($Phase): coverage="+[string]$Result.coverageStatus+"; incorporated="+@($Result.incorporated).Count+"; still-effective="+@($Result.stillEffective).Count+"; conflicts="+@($Result.conflicts).Count)
    foreach($item in @($Result.incorporated)){Write-Host ('  INCORPORATED '+[string]$item.correctionId)}
    foreach($item in @($Result.stillEffective)){Write-Host ('  STILL_EFFECTIVE '+[string]$item.correctionId+' — '+[string]$item.requirementReason)}
    foreach($item in @($Result.conflicts)){Write-Host ('  CONFLICT '+[string]$item.correctionId+' — '+[string]$item.requirementReason)}
    if(@($Result.conflicts).Count-ne0){throw 'PROJECT_CORRECTION_CONFLICT'}
}

function Invoke-Framework16Upgrade([string]$ProjectRoot,[string]$Repo,[string]$Layout,[string]$FrameworkRoot) {
    if($Layout-cne'repo-local'){throw 'Framework 1.6.0 minimal migration accepts repo-local 1.4.1/1.5.x projects only.'}
    if([string]::IsNullOrWhiteSpace($ControllerId)){throw 'ControllerId is required for Framework 1.6.0.'}
    $projectFile=Join-Path $ProjectRoot 'project.json';$bootstrapFile=Join-Path $ProjectRoot 'BOOTSTRAP.md';$controllerFile=Join-Path $ProjectRoot 'controller.json'
    $transactionRoot=Join-Path $ProjectRoot '.framework-upgrade-transaction'
    $raw=Read-StrictUtf8NoBom $projectFile
    try{$config=$raw|ConvertFrom-Json}catch{throw 'Project configuration is invalid JSON.'}
    if([string]$config.frameworkVersion-ceq'1.6.0'){
        $fields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','routineExcludedPaths','frameworkCapabilities')
        Assert-MinimalExactFields $config $raw $fields 'Already-upgraded project.json'
        if(-not(Test-MinimalJsonInteger $config.schemaVersion)-or[int]$config.schemaVersion-ne 3-or
           -not($config.id-is[string])-or[string]$config.id-cne$ProjectId-or
           -not($config.displayName-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.displayName)-or
           -not($config.controlPlaneLayout-is[string])-or[string]$config.controlPlaneLayout-cne'repo-local'-or
           -not($config.repositoryRoot-is[string])-or[string]$config.repositoryRoot-cne'..'-or
           -not($config.frameworkVersion-is[string])-or[string]$config.frameworkVersion-cne'1.6.0'-or
           -not($config.routineExcludedPaths-is[System.Array])-or
           -not($config.frameworkCapabilities-is[pscustomobject])){throw 'Already-upgraded project.json is unhealthy.'}
        Assert-MinimalFrameworkCapabilities $config.frameworkCapabilities $raw 'Already-upgraded project.json frameworkCapabilities'
        $routinePaths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach($pathValue in @($config.routineExcludedPaths)){if(-not($pathValue-is[string])-or[string]::IsNullOrWhiteSpace([string]$pathValue)-or-not$routinePaths.Add([string]$pathValue)){throw 'Already-upgraded project.json routine exclusions are invalid.'}}
        if(-not(Test-Path -LiteralPath $controllerFile -PathType Leaf)){throw 'Already-upgraded controller.json is missing.'}
        Assert-NoReparsePoint $controllerFile
        $controllerRaw=Read-StrictUtf8NoBom $controllerFile;try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'Already-upgraded controller.json is invalid.'}
        Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
        $targetBootstrapTemplate=Join-ChildPath $FrameworkRoot 'versions/1.6.0/project-starter/BOOTSTRAP.md'
        $expected=Render-Bootstrap (Read-StrictUtf8NoBom $targetBootstrapTemplate) $config '1.6.0'
        $actualBlock=Get-ManagedBootstrapBlock (Read-StrictUtf8NoBom $bootstrapFile) $bootstrapFile
        $expectedBlock=Get-ManagedBootstrapBlock $expected $targetBootstrapTemplate
        if($actualBlock.Text-cne$expectedBlock.Text){throw 'Already-upgraded Bootstrap managed block is unhealthy.'}
        Write-Output 'ALREADY_UPGRADED';return
    }
    $sourceVersions=@('1.4.1','1.5.0','1.5.1','1.5.2')
    if([string]$config.frameworkVersion-cnotin$sourceVersions){throw 'Unsupported direct source for Framework 1.6.0.'}
    $sourceFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion')
    Assert-MinimalExactFields $config $raw $sourceFields 'Source project.json'
    if(-not(Test-MinimalJsonInteger $config.schemaVersion)-or[int]$config.schemaVersion-ne 2-or
       -not($config.id-is[string])-or[string]$config.id-cne$ProjectId-or
       -not($config.displayName-is[string])-or[string]::IsNullOrWhiteSpace([string]$config.displayName)-or
       -not($config.controlPlaneLayout-is[string])-or[string]$config.controlPlaneLayout-cne'repo-local'-or
       -not($config.repositoryRoot-is[string])-or[string]$config.repositoryRoot-cne'..'-or
       -not($config.frameworkVersion-is[string])-or[string]$config.frameworkVersion-cnotin$sourceVersions){throw 'Source project.json is not a supported schema-2 repo-local project.'}
    if([string]::IsNullOrWhiteSpace($RoutineExcludedPathsMigrationPath)-or[string]::IsNullOrWhiteSpace($ExpectedRoutineExcludedPathsMigrationIdentity)){throw 'Frozen routine-exclusion migration input is required.'}
    if($ExpectedRoutineExcludedPathsMigrationIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'Routine-exclusion migration identity is invalid.'}
    if(-not(Test-Path -LiteralPath $RoutineExcludedPathsMigrationPath -PathType Leaf)){throw 'Routine-exclusion migration input is missing.'}
    Assert-MinimalPathInsideRepo $Repo $RoutineExcludedPathsMigrationPath
    if((Get-MinimalFileIdentity $RoutineExcludedPathsMigrationPath)-cne$ExpectedRoutineExcludedPathsMigrationIdentity){throw 'Routine-exclusion migration input drift.'}
    $migrationRaw=Read-StrictUtf8NoBom $RoutineExcludedPathsMigrationPath;try{$migration=$migrationRaw|ConvertFrom-Json}catch{throw 'Routine-exclusion migration input is invalid JSON.'}
    Assert-MinimalExactFields $migration $migrationRaw @('schemaVersion','projectId','routineExcludedPaths') 'Routine-exclusion migration input'
    if(-not(Test-MinimalJsonInteger $migration.schemaVersion)-or[int]$migration.schemaVersion-ne 1-or-not($migration.projectId-is[string])-or[string]$migration.projectId-cne$ProjectId-or-not($migration.routineExcludedPaths-is[System.Array])){throw 'Routine-exclusion migration input identity is invalid.'}
    $routinePaths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($pathValue in @($migration.routineExcludedPaths)){if(-not($pathValue-is[string])-or[string]::IsNullOrWhiteSpace([string]$pathValue)-or-not$routinePaths.Add([string]$pathValue)){throw 'Routine-exclusion migration input paths are invalid.'}}
    if(Test-Path -LiteralPath $controllerFile){throw 'Unexpected controller.json already exists.'}

    $sourceTemplate=Join-ChildPath $FrameworkRoot ("versions/"+[string]$config.frameworkVersion+"/project-starter/BOOTSTRAP.md")
    $targetTemplate=Join-ChildPath $FrameworkRoot 'versions/1.6.0/project-starter/BOOTSTRAP.md'
    foreach($path in @($sourceTemplate,$targetTemplate)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Framework Bootstrap template is missing: $path"}}
    $currentBootstrap=Read-StrictUtf8NoBom $bootstrapFile
    $sourceExpected=Render-Bootstrap (Read-StrictUtf8NoBom $sourceTemplate) $config ([string]$config.frameworkVersion)
    $currentBlock=Get-ManagedBootstrapBlock $currentBootstrap $bootstrapFile;$sourceBlock=Get-ManagedBootstrapBlock $sourceExpected $sourceTemplate
    if($currentBlock.Text-cne$sourceBlock.Text){throw 'Source Bootstrap managed block was customized.'}
    $newConfig=[ordered]@{schemaVersion=3;id=[string]$config.id;displayName=[string]$config.displayName;controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.6.0';routineExcludedPaths=@($migration.routineExcludedPaths);frameworkCapabilities=[ordered]@{}}
    $targetProject=Normalize-Text ($newConfig|ConvertTo-Json -Depth 20)
    $renderedTarget=Render-Bootstrap (Read-StrictUtf8NoBom $targetTemplate) $newConfig '1.6.0';$targetBlock=Get-ManagedBootstrapBlock $renderedTarget $targetTemplate
    $targetBootstrap=Replace-ManagedBootstrapBlock $currentBootstrap $targetBlock.Text $currentBlock
    $newController=[ordered]@{schemaVersion=1;projectId=$ProjectId;controllerId=$ControllerId;controllerEpoch=1;state='CURRENT'}
    $targetController=Normalize-Text ($newController|ConvertTo-Json -Depth 5)
    if(-not$Apply){Write-Output ("WHAT_IF|from="+[string]$config.frameworkVersion+"|to=1.6.0|objects=3");return}
    $null=New-UpgradeTransaction $transactionRoot $ProjectRoot $projectFile $bootstrapFile $controllerFile $ProjectId ([string]$config.frameworkVersion) '1.6.0' $targetProject $targetBootstrap 'CREATE' $targetController $RoutineExcludedPathsMigrationPath $ExpectedRoutineExcludedPathsMigrationIdentity
    $completed=Commit-UpgradeTransaction $transactionRoot $ProjectRoot $projectFile $bootstrapFile $controllerFile $ProjectId $ControllerId '1.6.0'
    Write-Output "UPGRADED|objects=3|recovery=$completed"
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

$targetFramework=$null
if($ToVersion-cne'1.6.0'){
    $targetFramework=Join-ChildPath $frameworkRoot "versions/$ToVersion"
    if(-not(Test-Path -LiteralPath $targetFramework -PathType Container)){throw "Framework version does not exist: $ToVersion"}
    Assert-StableFrameworkRelease $targetFramework $ToVersion
    if($ToVersion-in@('1.12.0','1.13.0')){
        $toolchainPath=Join-ChildPath $targetFramework 'TOOLCHAIN.json';$toolchainRaw=Read-StrictUtf8NoBom $toolchainPath
        try{$toolchain=$toolchainRaw|ConvertFrom-Json}catch{throw 'FRAMEWORK_TOOLCHAIN_JSON'}
        Assert-MinimalExactFields $toolchain $toolchainRaw @('schemaVersion','frameworkVersion','contractVersion','projectSelectionField','officialBackends','conformance') 'Framework TOOLCHAIN.json'
        if(-not(Test-MinimalJsonInteger $toolchain.schemaVersion)-or[int]$toolchain.schemaVersion-ne1-or[string]$toolchain.frameworkVersion-cne$ToVersion-or[string]$toolchain.contractVersion-cne'1'-or[string]$toolchain.projectSelectionField-cne'frameworkToolBackend'-or-not($toolchain.officialBackends-is[System.Array])-or@($toolchain.officialBackends).Count-ne1){throw 'FRAMEWORK_TOOLCHAIN_VALUES'}
        $backend=@($toolchain.officialBackends)[0]
        if(-not($backend-is[pscustomobject])-or[string]$backend.id-cne'powershell7'-or[string]$backend.status-cne'OFFICIAL'-or-not($backend.runtime-is[pscustomobject])-or[string]$backend.runtime.command-cne'pwsh'-or[string]$backend.runtime.edition-cne'Core'-or-not(Test-MinimalJsonInteger $backend.runtime.minimumMajorVersion)-or[int]$backend.runtime.minimumMajorVersion-ne7-or-not($backend.platforms-is[System.Array])-or@($backend.platforms).Count-lt1-or-not($backend.entrypoints-is[pscustomobject])){throw 'FRAMEWORK_TOOLCHAIN_BACKEND'}
        $declaredPlatforms=@($backend.platforms|ForEach-Object{[string]$_})
        if(@($declaredPlatforms|Where-Object{$_-cnotin@('windows','linux','macos')}).Count-ne0-or@($declaredPlatforms|Select-Object -Unique).Count-ne$declaredPlatforms.Count){throw 'FRAMEWORK_TOOLCHAIN_PLATFORMS'}
        $currentPlatform=if([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)){'windows'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux)){'linux'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)){'macos'}else{'unknown'}
        if($currentPlatform-cnotin$declaredPlatforms){throw ('FRAMEWORK_TOOL_PLATFORM_UNSUPPORTED|backend=powershell7|platform='+$currentPlatform)}
        foreach($entry in $backend.entrypoints.PSObject.Properties){$relative=[string]$entry.Value;if([string]::IsNullOrWhiteSpace($relative)-or$relative-cne$relative.Replace('\','/')-or[IO.Path]::IsPathRooted($relative)-or$relative.Contains('..')-or-not(Test-Path -LiteralPath (Join-ChildPath $targetFramework $relative) -PathType Leaf)){throw ('FRAMEWORK_TOOLCHAIN_ENTRYPOINT|'+$entry.Name)}}
    }
}

if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
    throw "Repository path does not exist: $RepositoryPath"
}
$repo = Get-GitRepositoryRoot ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).ProviderPath))
$repoLocalRoot = Join-Path $repo '.ai-workspace'

if (-not (Test-Path -LiteralPath $repoLocalRoot -PathType Container)) {
    throw "Repository-local project control plane does not exist: $repoLocalRoot"
}
$projectRoot = $repoLocalRoot
$layout = 'repo-local'
Assert-NoReparseTree $projectRoot
$projectFile = Join-ChildPath $projectRoot 'project.json'
$bootstrapFile = Join-ChildPath $projectRoot 'BOOTSTRAP.md'
$controllerFile = Join-ChildPath $projectRoot 'controller.json'
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "Unknown project: $ProjectId"
}
if (-not (Test-Path -LiteralPath $bootstrapFile -PathType Leaf)) {
    throw "Project Bootstrap does not exist: $bootstrapFile"
}

$transactionRoot = Join-Path $projectRoot '.framework-upgrade-transaction'
$abandonedPreparations = @(Get-ChildItem -LiteralPath $projectRoot -Directory -Force -Filter '.fwu-prep-*' -ErrorAction SilentlyContinue)
$hasActiveTransaction = Test-Path -LiteralPath $transactionRoot
if ($hasActiveTransaction) {
    if (-not (Test-Path -LiteralPath $transactionRoot -PathType Container)) {
        throw 'Upgrade transaction path is not a directory.'
    }
}
if ($abandonedPreparations.Count -ne 0) {
    throw 'Abandoned upgrade preparation exists; preserve it and perform exact manual housekeeping before retrying.'
}
if ($hasActiveTransaction) {
    $recoveryResult = Recover-UpgradeTransaction $transactionRoot $projectRoot $projectFile $bootstrapFile $controllerFile $ProjectId $ControllerId $ToVersion -Preview:(-not $Apply)
    if ($Apply) { Write-Host "Recovered previous Framework upgrade transaction: $recoveryResult" }
    else { Write-Host "Preview only. Active Framework upgrade transaction: $recoveryResult" }
    return
}

if ($ToVersion -ceq '1.6.0') {
    Invoke-Framework16Upgrade $projectRoot $repo $layout $frameworkRoot
    return
}

$configText = Read-StrictUtf8NoBom $projectFile
try {
    $config = $configText | ConvertFrom-Json
}
catch {
    throw "Project configuration is not valid JSON: $projectFile"
}
foreach ($property in @('id', 'displayName', 'frameworkVersion')) {
    if ($config.PSObject.Properties.Name -notcontains $property -or [string]::IsNullOrWhiteSpace([string]$config.$property)) {
        throw "Project configuration is missing a required property: $property"
    }
}
if ([string]$config.id -cne $ProjectId) {
    throw "Project id does not match its directory: $($config.id)"
}
if ($layout -cne 'repo-local') { throw 'Framework live upgrade accepts repository-local projects only.' }
    foreach ($property in @('schemaVersion', 'controlPlaneLayout', 'repositoryRoot')) {
        if ($config.PSObject.Properties.Name -notcontains $property) {
            throw "Repo-local project configuration is missing a required property: $property"
        }
    }
    $schema4Source=$false
    $allowedSchema3Sources = if($ToVersion -ceq '1.6.1'){@('1.6.0','1.6.1')}elseif($ToVersion -ceq '1.7.0'){@('1.6.0','1.6.1','1.7.0')}elseif($ToVersion -ceq '1.8.0'){@('1.6.0','1.6.1','1.7.0','1.8.0')}elseif($ToVersion -ceq '1.9.0'){@('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')}elseif($ToVersion -ceq '1.10.0'){@('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')}elseif($ToVersion -ceq '1.11.0'){@('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')}elseif($ToVersion -ceq '1.12.0'){@('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')}elseif($ToVersion-ceq'1.13.0'){@('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')}else{@()}
    $schema3Patch = $allowedSchema3Sources.Count -gt 0 -and
        (Test-MinimalJsonInteger $config.schemaVersion) -and [int]$config.schemaVersion -eq 3 -and
        ($config.frameworkVersion -is [string]) -and [string]$config.frameworkVersion -in $allowedSchema3Sources
    if ($schema3Patch) {
        $sourceFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','routineExcludedPaths','frameworkCapabilities')
        if([string]$config.frameworkVersion-in@('1.12.0','1.13.0')){$sourceFields=@($sourceFields[0..5]+@('frameworkToolBackend')+$sourceFields[6..7])}
        Assert-MinimalExactFields $config $configText $sourceFields 'Schema3 patch source project.json'
        if (-not ($config.id -is [string]) -or [string]$config.id -cne $ProjectId -or
            -not ($config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.displayName) -or
            -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne 'repo-local' -or
            -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
            ([string]$config.frameworkVersion-in@('1.12.0','1.13.0')-and(-not($config.frameworkToolBackend-is[string])-or[string]$config.frameworkToolBackend-cne'powershell7')) -or
            -not ($config.routineExcludedPaths -is [System.Array]) -or
            -not ($config.frameworkCapabilities -is [pscustomobject])) { throw "Schema3 patch source project.json is unhealthy: $projectFile" }
        $routinePaths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach($pathValue in @($config.routineExcludedPaths)){if(-not($pathValue-is[string])-or[string]::IsNullOrWhiteSpace([string]$pathValue)-or-not$routinePaths.Add([string]$pathValue)){throw 'Schema3 patch source routine exclusions are invalid.'}}
        Assert-MinimalFrameworkCapabilities $config.frameworkCapabilities $configText 'Schema3 patch source frameworkCapabilities'
        if([string]::IsNullOrWhiteSpace($ControllerId)){throw 'ControllerId is required for schema3 Framework upgrade.'}
        if(-not(Test-Path -LiteralPath $controllerFile -PathType Leaf)){throw 'Schema3 patch source controller.json is missing.'}
        Assert-NoReparsePoint $controllerFile
        $controllerRaw=Read-StrictUtf8NoBom $controllerFile
        try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'Schema3 patch source controller.json is invalid.'}
        Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    } elseif((Test-MinimalJsonInteger $config.schemaVersion)-and[int]$config.schemaVersion-eq4-and[string]$config.frameworkVersion-ceq'1.13.0'-and$ToVersion-in@('1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')) {
        $schema4Source=$true
        $sourceFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy')
        Assert-MinimalExactFields $config $configText $sourceFields 'Schema4 current project.json'
        if([string]$config.id-cne$ProjectId-or[string]$config.controlPlaneLayout-cne'repo-local'-or[string]$config.repositoryRoot-cne'..'-or[string]$config.frameworkToolBackend-cne'powershell7'-or-not($config.routineExcludedPaths-is[Array])-or-not($config.frameworkCapabilities-is[pscustomobject])-or-not($config.processPolicy-is[pscustomobject])){throw 'Schema4 current project.json is unhealthy.'}
        $routinePaths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);foreach($pathValue in @($config.routineExcludedPaths)){if(-not($pathValue-is[string])-or[string]::IsNullOrWhiteSpace([string]$pathValue)-or-not$routinePaths.Add([string]$pathValue)){throw 'Schema4 current routine exclusions are invalid.'}};Assert-MinimalFrameworkCapabilities $config.frameworkCapabilities $configText 'Schema4 current frameworkCapabilities'
        $policyLocatorRaw=$config.processPolicy|ConvertTo-Json -Compress;Assert-MinimalExactFields $config.processPolicy $policyLocatorRaw @('schemaVersion','locator') 'Schema4 current processPolicy locator'
        if([regex]::Matches($configText,'"locator"\s*:').Count-ne1){throw 'Schema4 current processPolicy locator is duplicate or missing.'}
        $policyFile=Join-ChildPath $projectRoot 'process-policy.json'
        if([int]$config.processPolicy.schemaVersion-ne1-or[string]$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'-or-not(Test-Path -LiteralPath $policyFile -PathType Leaf)){throw 'Schema4 current process policy is unhealthy.'}
        Assert-NoReparsePoint $policyFile;$policyRaw=Read-StrictUtf8NoBom $policyFile;try{$policy=$policyRaw|ConvertFrom-Json}catch{throw 'Schema4 current process-policy.json is invalid.'};Assert-MinimalExactFields $policy $policyRaw @('schemaVersion','contractVersion','projectId','rules') 'Schema4 current process-policy.json'
        if([int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne'1.13.0'-or[string]$policy.projectId-cne$ProjectId-or-not($policy.rules-is[Array])){throw 'Schema4 current process-policy.json values are invalid.'}
        if($ToVersion-cne'1.13.0'-and@($policy.rules).Count-ne0){throw 'STRUCTURED_PROCESS_POLICY_DOWNGRADE_CONFLICT|target cannot interpret active 1.13 process policy rules'}
        if([string]::IsNullOrWhiteSpace($ControllerId)){throw 'ControllerId is required for schema4 Framework upgrade.'}
        $controllerRaw=Read-StrictUtf8NoBom $controllerFile;try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'Schema4 current controller.json is invalid.'};Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    } elseif ($ToVersion -in @('1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0')) {
        throw "Framework $ToVersion direct upgrade requires a healthy supported schema3 source; migrate older schema2 projects to schema3 first."
    } elseif ([int]$config.schemaVersion -ne 2 -or
        [string]$config.controlPlaneLayout -cne 'repo-local' -or
        [string]$config.repositoryRoot -cne '..') {
        throw "Repo-local project configuration has an unsupported layout: $projectFile"
    }

$fromVersion = [string]$config.frameworkVersion
if ($fromVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') {
    throw "Project configuration contains an invalid pinned Framework version: $fromVersion"
}
$sourceFramework = Join-ChildPath $frameworkRoot "versions/$fromVersion"
$sourceBootstrapTemplate = Join-ChildPath $sourceFramework 'project-starter/BOOTSTRAP.md'
$targetBootstrapTemplate = Join-ChildPath $targetFramework 'project-starter/BOOTSTRAP.md'
$targetProjectTemplate = Join-ChildPath $targetFramework 'project-starter/project.json'
$targetCorrectionsTemplate = Join-ChildPath $targetFramework 'project-starter/corrections.json'
if (-not (Test-Path -LiteralPath $targetBootstrapTemplate -PathType Leaf)) {
    throw "Target Framework Bootstrap template does not exist: $targetBootstrapTemplate"
}
if (-not (Test-Path -LiteralPath $targetProjectTemplate -PathType Leaf)) {
    throw "Target Framework project template does not exist: $targetProjectTemplate"
}
$targetProjectTemplateText = Read-StrictUtf8NoBom $targetProjectTemplate
if (-not $targetProjectTemplateText.Contains('"controlPlaneLayout": "repo-local"')) {
    throw 'A repo-local project can only upgrade to a repo-local Framework starter.'
}

$currentBootstrap = Normalize-Text (Read-StrictUtf8NoBom $bootstrapFile)
if (-not (Test-Path -LiteralPath $sourceFramework -PathType Container)) {
    throw "Pinned Framework directory does not exist in framework/versions; tags and current HEAD are not runtime fallbacks: $sourceFramework"
}
if (-not (Test-Path -LiteralPath $sourceBootstrapTemplate -PathType Leaf)) {
    throw "Pinned Framework directory is incomplete; Bootstrap template does not exist: $sourceBootstrapTemplate"
}
$sourceTemplate = Read-StrictUtf8NoBom $sourceBootstrapTemplate
$targetTemplate = Read-StrictUtf8NoBom $targetBootstrapTemplate
$expectedCurrentBootstrap = Render-Bootstrap $sourceTemplate $config $fromVersion
$currentBlock = Get-ManagedBootstrapBlock $currentBootstrap $bootstrapFile
$expectedBlock = Get-ManagedBootstrapBlock $expectedCurrentBootstrap $sourceBootstrapTemplate
if ($currentBlock.Text -cne $expectedBlock.Text) {
    throw "Repo-local Bootstrap managed block was customized; refusing to overwrite it: $bootstrapFile"
}
$renderedTarget = Render-Bootstrap $targetTemplate $config $ToVersion
$targetBlock = Get-ManagedBootstrapBlock $renderedTarget $targetBootstrapTemplate
$targetBootstrap = Replace-ManagedBootstrapBlock $currentBootstrap $targetBlock.Text $currentBlock
$targetBootstrap = Merge-CorrectionBootstrapBlock $targetBootstrap $renderedTarget $targetBootstrapTemplate
Assert-TargetBootstrapContract $targetBootstrap $ToVersion $workspace $targetFramework $layout

$correctionsFile=Join-ChildPath $projectRoot 'corrections.json'
$targetEvaluator=Join-ChildPath $targetFramework 'scripts/check-project-corrections.ps1'
$sourceEvaluator=Join-ChildPath $sourceFramework 'scripts/check-project-corrections.ps1'
$evaluator=if(Test-Path -LiteralPath $targetEvaluator -PathType Leaf){$targetEvaluator}elseif(Test-Path -LiteralPath $sourceEvaluator -PathType Leaf){$sourceEvaluator}else{''}
$correctionsMode='NONE';$targetCorrections=''
if(Test-Path -LiteralPath $correctionsFile -PathType Leaf){
    Assert-NoReparsePoint $correctionsFile
    if([string]::IsNullOrWhiteSpace($evaluator)){throw 'Project has correction authority but neither source nor target Framework provides the evaluator.'}
    $correctionsMode='PRESERVE'
}elseif(Test-Path -LiteralPath $targetEvaluator -PathType Leaf){
    if(-not(Test-Path -LiteralPath $targetCorrectionsTemplate -PathType Leaf)){throw 'Target Framework corrections starter is missing.'}
    $targetCorrections=(Read-StrictUtf8NoBom $targetCorrectionsTemplate).Replace('{{PROJECT_ID}}',$ProjectId)
    if($targetCorrections-match'\{\{[A-Z0-9_]+\}\}'){throw 'Target Framework corrections starter contains an unresolved token.'}
    try{$generatedCorrections=$targetCorrections|ConvertFrom-Json}catch{throw 'Target Framework corrections starter is invalid JSON.'}
    if([string]$generatedCorrections.projectId-cne$ProjectId-or[string]$generatedCorrections.contractVersion-cne'1.10.0'-or@($generatedCorrections.corrections).Count-ne0){throw 'Target Framework corrections starter values are invalid.'}
    $correctionsMode='CREATE'
}

$config.frameworkVersion = $ToVersion
if($schema4Source-and$ToVersion-cne'1.13.0'){
    $config.schemaVersion=3
    $config.PSObject.Properties.Remove('processPolicy')
}
if($ToVersion-in@('1.12.0','1.13.0')){
    if($null-eq$config.PSObject.Properties['frameworkToolBackend']){$config|Add-Member -NotePropertyName frameworkToolBackend -NotePropertyValue 'powershell7'}else{$config.frameworkToolBackend='powershell7'}
}elseif($null-ne$config.PSObject.Properties['frameworkToolBackend']){
    $config.PSObject.Properties.Remove('frameworkToolBackend')
}
$targetConfig = Normalize-Text ($config | ConvertTo-Json -Depth 100)
try{$validatedConfig=$targetConfig|ConvertFrom-Json}catch{throw 'Generated project configuration is not valid JSON.'}
if([string]$validatedConfig.frameworkVersion-cne$ToVersion){throw 'Generated project configuration does not contain the target Framework version.'}
if(($ToVersion-in@('1.12.0','1.13.0')-and[string]$validatedConfig.frameworkToolBackend-cne'powershell7')-or($ToVersion-notin@('1.12.0','1.13.0')-and$null-ne$validatedConfig.PSObject.Properties['frameworkToolBackend'])){throw 'Generated project configuration contains the wrong Framework tool backend contract.'}
if($ToVersion-cne'1.13.0'-and$null-ne$validatedConfig.PSObject.Properties['processPolicy']){throw 'Generated downgrade configuration retained an unsupported process policy locator.'}

$preCorrection=Invoke-CorrectionEvaluationProjected $evaluator $workspace $ToVersion $targetConfig $targetBootstrap $correctionsFile (Join-ChildPath $projectRoot 'process-policy.json') -AllowMissing:($correctionsMode-ceq'CREATE')
Write-CorrectionEvaluation $preCorrection 'before pin projection'

Write-Host "Project: $ProjectId"
Write-Host "Layout: $layout"
Write-Host "Framework: $fromVersion -> $ToVersion"
Write-Host 'Upgrade: same-topology project pin and managed Bootstrap locator'

if (-not $Apply) {
    Write-Host 'Preview only. Upgrade preconditions passed; rerun with -Apply.'
    return
}

if ($fromVersion -eq $ToVersion) {
    if($correctionsMode-ceq'CREATE'){throw "Pinned $ToVersion project is missing corrections.json; refuse to report already upgraded."}
    Write-Host 'Already on requested version with a matching Bootstrap; no change.'
    return
}

$null = New-UpgradeTransaction $transactionRoot $projectRoot $projectFile $bootstrapFile $controllerFile $ProjectId $fromVersion $ToVersion $targetConfig $targetBootstrap 'NONE' '' '' '' $correctionsMode $targetCorrections
$completed = Commit-UpgradeTransaction $transactionRoot $projectRoot $projectFile $bootstrapFile $controllerFile $ProjectId $ControllerId $ToVersion

$postCorrection=Invoke-CorrectionEvaluation $evaluator $repo $workspace $ToVersion $projectFile $correctionsFile 'POSTCHECK'
Write-CorrectionEvaluation $postCorrection 'after pin projection'

Write-Host "Updated: $projectFile"
Write-Host "Updated: $bootstrapFile"
Write-Host ("Committed recoverable transaction; correction mode="+$correctionsMode+"; recovery material retained at "+$completed)
Write-Host 'Next: review the pin/Bootstrap/correction report, complete FULL_COLD recovery, then commit only the project-owned adoption objects together.'
