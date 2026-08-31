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

    [switch]$Apply,

    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

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

function Get-ProcessCarrierContractVersion([string]$FrameworkVersion) {
    if ($FrameworkVersion -in @('1.14.0','1.14.1')) { return '1.14.0' }
    return $FrameworkVersion
}

function Assert-ExactObjectFields($Object,[string]$Raw,[string[]]$Expected,[string]$Label) {
    if (-not ($Object -is [pscustomobject])) { throw "$Label must be a JSON object." }
    $names = @($Object.PSObject.Properties.Name)
    if ($names.Count -ne $Expected.Count -or @($Expected | Where-Object { $_ -cnotin $names }).Count -ne 0) { throw "$Label field set mismatch." }
    foreach ($name in $Expected) {
        $expectedCount=if($name-ceq'schemaVersion'-and'processPolicy'-cin$names){2}else{1}
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
    if (-not ($Capabilities -is [pscustomobject])) { throw "$Label must be an object." }
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
    $null=ConvertTo-FrameworkLocator ([string]$knowledge.indexLocator)
}

function New-TemplateMap([string]$Version) {
    $map=[ordered]@{
        '.gitattributes'='.gitattributes'; 'project.json'='project.json'; 'BOOTSTRAP.md'='BOOTSTRAP.md';
        'PROJECT.md'='PROJECT.md'; 'REVIEW_PROFILE.md'='REVIEW_PROFILE.md'; 'RELATIONSHIPS.md'='RELATIONSHIPS.md';
        'STATUS.md'='STATUS.md'; 'tasks/README.md'='tasks/README.md'
    }
    if ($Version -in @('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0','1.14.0','1.14.1')) { $map['controller.json']='controller.json' }
    if ($Version -in @('1.10.0','1.11.0','1.12.0','1.13.0','1.14.0','1.14.1')) { $map['corrections.json']='corrections.json' }
    if ($Version -in @('1.13.0','1.14.0','1.14.1')) { $map['process-policy.json']='process-policy.json' }
    return $map
}

function Get-OptionalFileIdentity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'MISSING' }
    return Get-FileIdentity $Path
}

function Get-FrameworkAgentsProjection([string]$RepositoryRoot,[string]$TemplateRoot,[string]$Version) {
    if ($Version -notin @('1.14.0','1.14.1')) { return $null }
    Assert-ManagedRouterDestinations $RepositoryRoot
    $agentsTemplatePath=Join-ChildPath $TemplateRoot 'AGENTS.md'
    $skillTemplatePath=Join-ChildPath $TemplateRoot '.agents/skills/ai-workspace-router/SKILL.md'
    $targetBlock=Read-StrictUtf8Template $agentsTemplatePath
    $targetSkill=Read-StrictUtf8Template $skillTemplatePath
    $agentsPath=Join-Path $RepositoryRoot 'AGENTS.md'
    $skillPath=Join-Path $RepositoryRoot '.agents\skills\ai-workspace-router\SKILL.md'
    $begin='<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->';$end='<!-- AI-WORKSPACE-FRAMEWORK:END -->'
    $oldAgentsIdentity=Get-OptionalFileIdentity $agentsPath;$oldSkillIdentity=Get-OptionalFileIdentity $skillPath
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
    if($oldSkillIdentity-cne'MISSING'-and[IO.File]::ReadAllText($skillPath,[Text.UTF8Encoding]::new($false,$true))-cne$targetSkill){throw 'ROUTER_SKILL_COLLISION'}
    return [pscustomobject]@{AgentsPath=$agentsPath;SkillPath=$skillPath;OldAgentsIdentity=$oldAgentsIdentity;OldSkillIdentity=$oldSkillIdentity;TargetAgents=$targetAgents;TargetSkill=$targetSkill}
}

function Get-Framework114RegistrationObjectPaths {
    return @('AGENTS.md','.agents/skills/ai-workspace-router/SKILL.md','.ai-workspace/.gitattributes','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/PROJECT.md','.ai-workspace/REVIEW_PROFILE.md','.ai-workspace/RELATIONSHIPS.md','.ai-workspace/STATUS.md','.ai-workspace/tasks/README.md','.ai-workspace/controller.json','.ai-workspace/corrections.json','.ai-workspace/process-policy.json')
}

function Get-Framework114RegistrationLayout([string]$RepositoryRoot,[string]$ExpectedProjectId,[string]$ExpectedFrameworkVersion) {
    if($ExpectedFrameworkVersion-notin@('1.14.0','1.14.1')){throw 'REGISTRATION_TRANSACTION_TARGET_UNSUPPORTED'}
    $material=([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))+"`n"+$ExpectedProjectId+"`n"+$ExpectedFrameworkVersion)
    $transactionId=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($material))).Substring(0,32).ToLowerInvariant()
    $repoLeaf=[IO.Path]::GetFileName([IO.Path]::TrimEndingDirectorySeparator($RepositoryRoot))
    $preparationRoot=Join-Path (Split-Path -Parent $RepositoryRoot) ('.'+$repoLeaf+'.framework-registration-preparation-'+$transactionId)
    return [pscustomobject]@{
        TransactionId=$transactionId
        FrameworkVersion=$ExpectedFrameworkVersion
        PreparationRoot=$preparationRoot
        PreparedTransactionRoot=(Join-Path $preparationRoot 'transaction')
        ControlStagingRoot=(Join-Path $preparationRoot 'control')
        TransactionRoot=(Join-Path $RepositoryRoot '.framework-registration-transaction')
        RecoveryRoot=(Join-Path $RepositoryRoot ('.framework-registration-recovery-'+$transactionId))
    }
}

function Assert-Framework114RegistrationRecoveryDestination([string]$RepositoryRoot,$Layout) {
    $repository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    $relative='.framework-registration-recovery-'+[string]$Layout.TransactionId
    $expected=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-ChildPath $repository $relative)))
    $actual=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$Layout.RecoveryRoot))
    if($actual-cne$expected-or[IO.Path]::GetRelativePath($repository,$actual)-cne$relative){throw 'REGISTRATION_TRANSACTION_RECOVERY_LOCATOR_DRIFT'}
    $existing=Get-Item -LiteralPath $actual -Force -ErrorAction SilentlyContinue
    if($null-ne$existing){
        if(($existing.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'REGISTRATION_TRANSACTION_RECOVERY_REPARSE'}
        if(-not($existing-is[IO.DirectoryInfo])){throw 'REGISTRATION_TRANSACTION_RECOVERY_NOT_DIRECTORY'}
        throw 'REGISTRATION_TRANSACTION_RECOVERY_COLLISION'
    }
    return $actual
}

function Assert-ExactTransactionTree([string]$Root,[string[]]$ExpectedFiles,[string[]]$AdditionalDirectories,[string]$ErrorCode) {
    $fileSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$directorySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($relative in $ExpectedFiles){$null=Join-ChildPath $Root $relative;if(-not$fileSet.Add($relative)){throw $ErrorCode};$segments=$relative.Split('/');for($i=1;$i-lt$segments.Count;$i++){$null=$directorySet.Add([string]::Join('/',@($segments[0..($i-1)])))}}
    foreach($relative in $AdditionalDirectories){$null=Join-ChildPath $Root $relative;$segments=$relative.Split('/');for($i=1;$i-le$segments.Count;$i++){$null=$directorySet.Add([string]::Join('/',@($segments[0..($i-1)])))}}
    $actualFiles=@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')})
    $actualDirectories=@(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')})
    if($actualFiles.Count-ne$fileSet.Count-or@($actualFiles|Where-Object{-not$fileSet.Contains($_)}).Count-ne0-or$actualDirectories.Count-ne$directorySet.Count-or@($actualDirectories|Where-Object{-not$directorySet.Contains($_)}).Count-ne0){throw $ErrorCode}
}

function Read-Framework114RegistrationTransaction([string]$RepositoryRoot,[string]$TransactionRoot,[string]$ExpectedProjectId,[string]$ExpectedTransactionId,[string]$ExpectedFrameworkVersion) {
    Assert-NoReparseTree $TransactionRoot
    $stateRaw=Read-StrictUtf8Template (Join-Path $TransactionRoot 'state.json')
    try{$state=$stateRaw|ConvertFrom-Json}catch{throw 'REGISTRATION_TRANSACTION_STATE_JSON'}
    Assert-ExactObjectFields $state $stateRaw @('schemaVersion','transactionId','projectId','frameworkVersion','objects','controlDirectories') 'registration transaction state'
    if($ExpectedFrameworkVersion-notin@('1.14.0','1.14.1')-or-not(Test-JsonInteger $state.schemaVersion)-or[int]$state.schemaVersion-ne2-or[string]$state.transactionId-cnotmatch'^[a-f0-9]{32}$'-or[string]$state.transactionId-cne$ExpectedTransactionId-or[string]$state.projectId-cne$ExpectedProjectId-or[string]$state.frameworkVersion-cne$ExpectedFrameworkVersion-or-not($state.objects-is[Array])-or-not($state.controlDirectories-is[Array])){throw 'REGISTRATION_TRANSACTION_STATE_VALUES'}
    $expectedObjects=@(Get-Framework114RegistrationObjectPaths)
    if(@($state.objects).Count-ne$expectedObjects.Count){throw 'REGISTRATION_TRANSACTION_OBJECT_SET'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$materialFiles=[Collections.Generic.List[string]]::new()
    foreach($entry in @($state.objects)){
        $raw=$entry|ConvertTo-Json -Compress;Assert-ExactObjectFields $entry $raw @('relative','oldIdentity','newIdentity') 'registration transaction object'
        if(-not($entry.relative-is[string])-or[string]$entry.relative-cnotin$expectedObjects-or-not$seen.Add([string]$entry.relative)){throw 'REGISTRATION_TRANSACTION_OBJECT_PATH'}
        foreach($name in @('oldIdentity','newIdentity')){if([string]$entry.$name-cne'MISSING'-and[string]$entry.$name-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'REGISTRATION_TRANSACTION_OBJECT_IDENTITY'}}
        foreach($kind in @('old','new')){$property=$kind+'Identity';$identity=[string]$entry.$property;$stage=Join-ChildPath (Join-Path $TransactionRoot $kind) ([string]$entry.relative);if($identity-cne'MISSING'){if(-not(Test-Path -LiteralPath $stage -PathType Leaf)-or(Get-FileIdentity $stage)-cne$identity){throw 'REGISTRATION_TRANSACTION_MATERIAL_DRIFT'};$materialFiles.Add($kind+'/'+[string]$entry.relative)}elseif(Test-Path -LiteralPath $stage){throw 'REGISTRATION_TRANSACTION_UNEXPECTED_MATERIAL'}}
    }
    if(@($expectedObjects|Where-Object{$_-cnotin$seen}).Count-ne0){throw 'REGISTRATION_TRANSACTION_OBJECT_SET'}
    $directories=@($state.controlDirectories);$expectedDirectories=@('.ai-workspace','.ai-workspace/tasks','.ai-workspace/tasks/active','.ai-workspace/tasks/archive');if($directories.Count-ne$expectedDirectories.Count-or@($directories|Where-Object{-not($_-is[string])-or[string]$_-cnotin$expectedDirectories}).Count-ne0-or@($expectedDirectories|Where-Object{$_-cnotin$directories}).Count-ne0){throw 'REGISTRATION_TRANSACTION_DIRECTORY_SET'}
    Assert-ExactTransactionTree $TransactionRoot (@('state.json')+@($materialFiles)) (@('old','new')+@($directories|ForEach-Object{'new/'+[string]$_})) 'REGISTRATION_TRANSACTION_TREE_CLOSURE'
    return $state
}

function Resume-Framework114Registration([string]$RepositoryRoot,[string]$TransactionRoot,[string]$ExpectedProjectId,$Layout,[switch]$Preview){
    if([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($TransactionRoot))-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$Layout.TransactionRoot))){throw 'REGISTRATION_TRANSACTION_LOCATOR_DRIFT'}
    $completed=Assert-Framework114RegistrationRecoveryDestination $RepositoryRoot $Layout
    $state=Read-Framework114RegistrationTransaction $RepositoryRoot $TransactionRoot $ExpectedProjectId ([string]$Layout.TransactionId) ([string]$Layout.FrameworkVersion)
    Assert-ManagedRouterDestinations $RepositoryRoot
    $controlEntries=@($state.objects|Where-Object{([string]$_.relative).StartsWith('.ai-workspace/',[StringComparison]::Ordinal)})
    $controlRoot=Join-Path $RepositoryRoot '.ai-workspace'
    if(Test-Path -LiteralPath $controlRoot -PathType Container){$actual=@(Get-ChildItem -LiteralPath $controlRoot -Recurse -File -Force|ForEach-Object{'.ai-workspace/'+$_.FullName.Substring($controlRoot.Length+1).Replace('\','/')});$expected=@($controlEntries|ForEach-Object{[string]$_.relative});if(@(Compare-Object -ReferenceObject $expected -DifferenceObject $actual -CaseSensitive|Where-Object{$_.SideIndicator-ceq'=>'}).Count-ne0){throw 'REGISTRATION_TRANSACTION_UNKNOWN_CONTROL_BYTES'}}elseif(Test-Path -LiteralPath $controlRoot){throw 'REGISTRATION_TRANSACTION_CONTROL_NOT_DIRECTORY'}
    $states=@();foreach($entry in @($state.objects)){$live=Get-OptionalFileIdentity (Join-ChildPath $RepositoryRoot ([string]$entry.relative));if($live-cne[string]$entry.oldIdentity-and$live-cne[string]$entry.newIdentity){throw ('REGISTRATION_TRANSACTION_UNKNOWN_LIVE_BYTES|'+[string]$entry.relative)};$states+=[pscustomobject]@{Entry=$entry;Live=$live}}
    $status=if(@($states|Where-Object{$_.Live-cne[string]$_.Entry.newIdentity}).Count-eq0){'NEW'}elseif(@($states|Where-Object{$_.Live-cne[string]$_.Entry.oldIdentity}).Count-eq0){'OLD'}else{'MIXED'}
    if($Preview){return ('RECOVERY_REQUIRED|state='+$status+'|project='+$ExpectedProjectId+'|framework='+[string]$state.frameworkVersion)}
    Assert-ManagedRouterDestinations $RepositoryRoot
    foreach($directory in @($state.controlDirectories)){New-Item -ItemType Directory -Path (Join-ChildPath $RepositoryRoot ([string]$directory)) -Force|Out-Null}
    foreach($item in $states){$entry=$item.Entry;if([string]$item.Live-ceq[string]$entry.newIdentity){continue};$managed=Test-ManagedRouterRelative ([string]$entry.relative);if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};$livePath=Join-ChildPath $RepositoryRoot ([string]$entry.relative);if((Get-OptionalFileIdentity $livePath)-cne[string]$entry.oldIdentity){throw ('REGISTRATION_TRANSACTION_RECHECK_DRIFT|'+[string]$entry.relative)};$stage=Join-ChildPath (Join-Path $TransactionRoot 'new') ([string]$entry.relative);New-Item -ItemType Directory -Path (Split-Path -Parent $livePath) -Force|Out-Null;if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};[IO.File]::Copy($stage,$livePath,([string]$entry.oldIdentity-cne'MISSING'));if((Get-FileIdentity $livePath)-cne[string]$entry.newIdentity){throw ('REGISTRATION_TRANSACTION_POSTIMAGE_DRIFT|'+[string]$entry.relative)}}
    foreach($entry in @($state.objects)){if((Get-OptionalFileIdentity (Join-ChildPath $RepositoryRoot ([string]$entry.relative)))-cne[string]$entry.newIdentity){throw ('REGISTRATION_TRANSACTION_FINAL_DRIFT|'+[string]$entry.relative)}}
    [IO.Directory]::Move($TransactionRoot,$completed);return [pscustomobject]@{Recovery=$completed;InitialState=$status}
}

function Commit-Framework114Registration([string]$RepositoryRoot,[string]$ControlStaging,[string]$ControlDestination,$Projection,[string]$ExpectedProjectId,$Layout) {
    $null=Assert-Framework114RegistrationRecoveryDestination $RepositoryRoot $Layout
    Assert-ManagedRouterDestinations $RepositoryRoot
    $transactionId=[string]$Layout.TransactionId;$transactionRoot=[string]$Layout.TransactionRoot;$preparationRoot=[string]$Layout.PreparationRoot;$preparedTransaction=[string]$Layout.PreparedTransactionRoot
    if(Test-Path -LiteralPath $transactionRoot){throw 'REGISTRATION_TRANSACTION_ALREADY_EXISTS'}
    if([IO.Path]::TrimEndingDirectorySeparator((Split-Path -Parent $ControlStaging))-cne[IO.Path]::TrimEndingDirectorySeparator($preparationRoot)){throw 'REGISTRATION_PREPARATION_LAYOUT'}
    if(Test-Path -LiteralPath $preparedTransaction){throw 'REGISTRATION_PREPARED_TRANSACTION_ALREADY_EXISTS'}
    New-Item -ItemType Directory -Path (Join-Path $preparedTransaction 'old'),(Join-Path $preparedTransaction 'new') -Force|Out-Null
    try{
        $newControl=Join-Path $preparedTransaction 'new\.ai-workspace';[IO.Directory]::Move($ControlStaging,$newControl)
        if($Projection.OldAgentsIdentity-cne'MISSING'){Assert-ManagedRouterDestinations $RepositoryRoot;[IO.File]::Copy($Projection.AgentsPath,(Join-Path $preparedTransaction 'old\AGENTS.md'),$false)}
        if($Projection.OldSkillIdentity-cne'MISSING'){Assert-ManagedRouterDestinations $RepositoryRoot;New-Item -ItemType Directory -Path (Join-Path $preparedTransaction 'old\.agents\skills\ai-workspace-router') -Force|Out-Null;[IO.File]::Copy($Projection.SkillPath,(Join-Path $preparedTransaction 'old\.agents\skills\ai-workspace-router\SKILL.md'),$false)}
        Write-Utf8NoBom (Join-Path $preparedTransaction 'new\AGENTS.md') $Projection.TargetAgents
        New-Item -ItemType Directory -Path (Join-Path $preparedTransaction 'new\.agents\skills\ai-workspace-router') -Force|Out-Null;Write-Utf8NoBom (Join-Path $preparedTransaction 'new\.agents\skills\ai-workspace-router\SKILL.md') $Projection.TargetSkill
        $objects=@([ordered]@{relative='AGENTS.md';oldIdentity=$Projection.OldAgentsIdentity;newIdentity=(Get-FileIdentity (Join-Path $preparedTransaction 'new\AGENTS.md'))},[ordered]@{relative='.agents/skills/ai-workspace-router/SKILL.md';oldIdentity=$Projection.OldSkillIdentity;newIdentity=(Get-FileIdentity (Join-Path $preparedTransaction 'new\.agents\skills\ai-workspace-router\SKILL.md'))})
        foreach($file in @(Get-ChildItem -LiteralPath $newControl -Recurse -File -Force)){$relative='.ai-workspace/'+$file.FullName.Substring($newControl.Length+1).Replace('\','/');$objects+=[ordered]@{relative=$relative;oldIdentity='MISSING';newIdentity=(Get-FileIdentity $file.FullName)}}
        $directories=@('.ai-workspace')+@(Get-ChildItem -LiteralPath $newControl -Recurse -Directory -Force|ForEach-Object{'.ai-workspace/'+$_.FullName.Substring($newControl.Length+1).Replace('\','/')})
        $state=[ordered]@{schemaVersion=2;transactionId=$transactionId;projectId=$ExpectedProjectId;frameworkVersion=[string]$Layout.FrameworkVersion;objects=$objects;controlDirectories=$directories};Write-Utf8NoBom (Join-Path $preparedTransaction 'state.json') ($state|ConvertTo-Json -Depth 10)
        $null=Read-Framework114RegistrationTransaction $RepositoryRoot $preparedTransaction $ExpectedProjectId $transactionId ([string]$Layout.FrameworkVersion)
        [IO.Directory]::Move($preparedTransaction,$transactionRoot)
        if([IO.Directory]::GetFileSystemEntries($preparationRoot).Count-eq0){[IO.Directory]::Delete($preparationRoot,$false)}
        $recovered=Resume-Framework114Registration $RepositoryRoot $transactionRoot $ExpectedProjectId $Layout
        return [string]$recovered.Recovery
    }catch{$preserved=if(Test-Path -LiteralPath $transactionRoot){$transactionRoot}else{$preparationRoot};throw "Registration stopped; deterministic preparation or exact transaction is preserved at $preserved. $($_.Exception.Message)"}
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
    if ($FrameworkVersion -in @('1.12.0','1.13.0','1.14.0','1.14.1')) {
        if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7' }
        $toolchainPath=Join-ChildPath $frameworkPath 'TOOLCHAIN.json'
        $toolchainRaw=Read-StrictUtf8Template $toolchainPath
        try{$toolchain=$toolchainRaw|ConvertFrom-Json}catch{throw 'FRAMEWORK_TOOLCHAIN_JSON'}
        Assert-ExactObjectFields $toolchain $toolchainRaw @('schemaVersion','frameworkVersion','contractVersion','projectSelectionField','officialBackends','conformance') 'Framework TOOLCHAIN.json'
        if(-not(Test-JsonInteger $toolchain.schemaVersion)-or[int]$toolchain.schemaVersion-ne1-or[string]$toolchain.frameworkVersion-cne$FrameworkVersion-or[string]$toolchain.contractVersion-cne'1'-or[string]$toolchain.projectSelectionField-cne'frameworkToolBackend'-or-not($toolchain.officialBackends-is[System.Array])-or@($toolchain.officialBackends).Count-ne1){throw 'FRAMEWORK_TOOLCHAIN_VALUES'}
        $backend=@($toolchain.officialBackends)[0]
        if(-not($backend-is[pscustomobject])-or[string]$backend.id-cne'powershell7'-or[string]$backend.status-cne'OFFICIAL'-or-not($backend.runtime-is[pscustomobject])-or[string]$backend.runtime.command-cne'pwsh'-or[string]$backend.runtime.edition-cne'Core'-or-not(Test-JsonInteger $backend.runtime.minimumMajorVersion)-or[int]$backend.runtime.minimumMajorVersion-ne7-or-not($backend.platforms-is[System.Array])-or@($backend.platforms).Count-lt1-or-not($backend.entrypoints-is[pscustomobject])){throw 'FRAMEWORK_TOOLCHAIN_BACKEND'}
        $declaredPlatforms=@($backend.platforms|ForEach-Object{[string]$_})
        if(@($declaredPlatforms|Where-Object{$_-cnotin@('windows','linux','macos')}).Count-ne0-or@($declaredPlatforms|Select-Object -Unique).Count-ne$declaredPlatforms.Count){throw 'FRAMEWORK_TOOLCHAIN_PLATFORMS'}
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
    $expectedSchema = if ($FrameworkVersion -in @('1.13.0','1.14.0','1.14.1')) { '"schemaVersion": 4' } elseif ($FrameworkVersion -in @('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0')) { '"schemaVersion": 3' } else { '"schemaVersion": 2' }
    if (-not $projectTemplateText.Contains($expectedSchema) -or
        -not $projectTemplateText.Contains('"controlPlaneLayout": "repo-local"') -or
        -not $projectTemplateText.Contains('"repositoryRoot": ".."')) {
        throw "$Selection does not publish a valid repo-local project starter."
    }
    if($FrameworkVersion-in@('1.12.0','1.13.0','1.14.0','1.14.1')-and-not$projectTemplateText.Contains('"frameworkToolBackend": "powershell7"')){throw "$Selection does not publish the required tool backend."}
    if($FrameworkVersion-in@('1.13.0','1.14.0','1.14.1')-and(-not$projectTemplateText.Contains('"locator": ".ai-workspace/process-policy.json"')-or-not$TemplateMap.Contains('process-policy.json'))){throw "$Selection does not publish the required structured process policy carrier."}
    if($FrameworkVersion-in@('1.14.0','1.14.1')-and(-not(Test-Path -LiteralPath (Join-ChildPath $templateRoot 'AGENTS.md') -PathType Leaf)-or-not(Test-Path -LiteralPath (Join-ChildPath $templateRoot '.agents/skills/ai-workspace-router/SKILL.md') -PathType Leaf))){throw "$Selection does not publish the required router Skill and managed AGENTS block."}
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
        [string]$ExpectedControllerId
    )

    $expectedProcessCarrierVersion = Get-ProcessCarrierContractVersion $ExpectedFrameworkVersion

    Assert-NoReparseTree $ControlRoot
    $actualFiles = @(Get-ChildItem -LiteralPath $ControlRoot -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($ControlRoot.Length + 1).Replace('\', '/')
    })
    $actualDirectories = @(Get-ChildItem -LiteralPath $ControlRoot -Recurse -Directory -Force | ForEach-Object {
        $_.FullName.Substring($ControlRoot.Length + 1).Replace('\', '/')
    })
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
    $schema3 = $ExpectedFrameworkVersion -in @('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0','1.14.0','1.14.1')
    $expectedFields = if ($schema3) { @($baseFields + $(if($ExpectedFrameworkVersion-in@('1.12.0','1.13.0','1.14.0','1.14.1')){@('frameworkToolBackend')}else{@()}) + @('routineExcludedPaths','frameworkCapabilities') + $(if($ExpectedFrameworkVersion-in@('1.13.0','1.14.0','1.14.1')){@('processPolicy')}else{@()})) } else { $baseFields }
    Assert-ExactObjectFields $config $configRaw $expectedFields 'Existing project.json'
    $expectedSchema = if ($ExpectedFrameworkVersion-in@('1.13.0','1.14.0','1.14.1')) { 4 } elseif ($schema3) { 3 } else { 2 }
    if (-not (Test-JsonInteger $config.schemaVersion) -or [int]$config.schemaVersion -ne $expectedSchema -or
        -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne 'repo-local' -or
        -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
        -not ($config.id -is [string]) -or [string]$config.id -cne $ExpectedProjectId -or
        -not ($config.displayName -is [string]) -or [string]$config.displayName -cne $ExpectedDisplayName -or
        -not ($config.frameworkVersion -is [string]) -or [string]$config.frameworkVersion -cne $ExpectedFrameworkVersion -or
        ($ExpectedFrameworkVersion-in@('1.12.0','1.13.0','1.14.0','1.14.1')-and(-not($config.frameworkToolBackend-is[string])-or[string]$config.frameworkToolBackend-cne'powershell7'))) {
        throw "Existing .ai-workspace identity conflicts with the requested project: $ControlRoot"
    }
    if ($schema3) {
        if (-not ($config.routineExcludedPaths -is [System.Array]) -or -not ($config.frameworkCapabilities -is [pscustomobject])) { throw "Existing project.json routine exclusions or capabilities are invalid: $projectFile" }
        Assert-FrameworkCapabilities $config.frameworkCapabilities $configRaw 'Existing project.json frameworkCapabilities'
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
        if($ExpectedFrameworkVersion-in@('1.13.0','1.14.0','1.14.1')){
            $policyFile=Join-Path $ControlRoot 'process-policy.json';$policyRaw=Read-StrictUtf8Template $policyFile
            try{$policy=$policyRaw|ConvertFrom-Json}catch{throw "Existing process-policy.json is invalid: $policyFile"}
            $policyLocatorRaw=$config.processPolicy|ConvertTo-Json -Compress
            Assert-ExactObjectFields $config.processPolicy $policyLocatorRaw @('schemaVersion','locator') 'Existing project.json processPolicy'
            if([regex]::Matches($configRaw,'"locator"\s*:').Count-ne1){throw 'Existing project.json processPolicy locator is duplicate or missing.'}
            Assert-ExactObjectFields $policy $policyRaw @('schemaVersion','contractVersion','projectId','rules') 'Existing process-policy.json'
            if([int]$config.processPolicy.schemaVersion-ne1-or[string]$config.processPolicy.locator-cne'.ai-workspace/process-policy.json'-or[int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne$expectedProcessCarrierVersion-or[string]$policy.projectId-cne$ExpectedProjectId-or-not($policy.rules-is[System.Array])){throw 'Existing structured process policy is invalid.'}
        }
        if ($ExpectedFrameworkVersion -in @('1.10.0','1.11.0','1.12.0','1.13.0','1.14.0','1.14.1')) {
            $correctionsFile=Join-Path $ControlRoot 'corrections.json'
            $correctionsRaw=Read-StrictUtf8Template $correctionsFile
            try { $corrections=$correctionsRaw|ConvertFrom-Json } catch { throw "Existing corrections.json is invalid: $correctionsFile" }
            Assert-ExactObjectFields $corrections $correctionsRaw @('schemaVersion','contractVersion','projectId','corrections') 'Existing corrections.json'
            $isLiveControl=(Split-Path -Leaf $ControlRoot)-ceq'.ai-workspace'
            $correctionsContractValid=if($ExpectedFrameworkVersion-in@('1.14.0','1.14.1')-and$isLiveControl){
                ((Test-JsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0')-or
                ((Test-JsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq$expectedProcessCarrierVersion)
            }elseif($ExpectedFrameworkVersion-in@('1.14.0','1.14.1')){
                (Test-JsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq$expectedProcessCarrierVersion
            }else{
                (Test-JsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0'
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
        throw "Existing repo-local Bootstrap managed block was customized; refusing ALREADY_REGISTERED: $bootstrapFile"
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

if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
    throw "Repository path does not exist or is not a directory: $RepositoryPath"
}
$repo = Get-GitRepositoryRoot ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).ProviderPath))

if ($FrameworkVersion -in @('1.6.0','1.6.1','1.7.0','1.8.0','1.9.0','1.10.0','1.11.0','1.12.0','1.13.0','1.14.0','1.14.1') -and [string]::IsNullOrWhiteSpace($ControllerId)) { throw 'ControllerId is required when registering a controlled Framework version.' }

$requiredProjectDirectories = @('tasks', 'tasks/active', 'tasks/archive')
$projectRoot = Join-Path $repo '.ai-workspace'
$registrationTransaction=Join-Path $repo '.framework-registration-transaction'
$registrationLayout=if($FrameworkVersion-in@('1.14.0','1.14.1')){Get-Framework114RegistrationLayout $repo $ProjectId $FrameworkVersion}else{$null}
if(Test-Path -LiteralPath $registrationTransaction){
    if($FrameworkVersion-notin@('1.14.0','1.14.1')){throw 'REGISTRATION_TRANSACTION_TARGET_MISMATCH'}
    $emptyPreparationPresent=$false
    if(Test-Path -LiteralPath $registrationLayout.PreparationRoot){
        if(-not(Test-Path -LiteralPath $registrationLayout.PreparationRoot -PathType Container)-or[IO.Directory]::GetFileSystemEntries([string]$registrationLayout.PreparationRoot).Count-ne0){throw ('REGISTRATION_PREPARATION_CONFLICT|'+[string]$registrationLayout.PreparationRoot)}
        $emptyPreparationPresent=$true
    }
    $recovered=Resume-Framework114Registration $repo $registrationTransaction $ProjectId $registrationLayout -Preview:(-not$Apply)
    if($Apply-and$emptyPreparationPresent-and(Test-Path -LiteralPath $registrationLayout.PreparationRoot -PathType Container)-and[IO.Directory]::GetFileSystemEntries([string]$registrationLayout.PreparationRoot).Count-eq0){[IO.Directory]::Delete([string]$registrationLayout.PreparationRoot,$false)}
    if($Apply){[pscustomobject]@{status='RECOVERED_CREATED';projectRoot=$projectRoot;frameworkVersion=$FrameworkVersion;recovery=[string]$recovered.Recovery}}else{[pscustomobject]@{status='RECOVERY_REQUIRED';projectRoot=$projectRoot;frameworkVersion=$FrameworkVersion;detail=[string]$recovered}}
    return
}
if($null-ne$registrationLayout-and(Test-Path -LiteralPath $registrationLayout.PreparationRoot)){
    if(-not(Test-Path -LiteralPath $registrationLayout.PreparedTransactionRoot -PathType Container)){throw ('REGISTRATION_PREPARATION_INCOMPLETE|'+[string]$registrationLayout.PreparationRoot)}
    $null=Read-Framework114RegistrationTransaction $repo $registrationLayout.PreparedTransactionRoot $ProjectId ([string]$registrationLayout.TransactionId) ([string]$registrationLayout.FrameworkVersion)
    if(-not$Apply){[pscustomobject]@{status='RECOVERY_REQUIRED';projectRoot=$projectRoot;frameworkVersion=$FrameworkVersion;preparationPath=[string]$registrationLayout.PreparationRoot;transactionPath=[string]$registrationLayout.TransactionRoot;recoveryPath=[string]$registrationLayout.RecoveryRoot};return}
    $null=Assert-Framework114RegistrationRecoveryDestination $repo $registrationLayout
    [IO.Directory]::Move([string]$registrationLayout.PreparedTransactionRoot,[string]$registrationLayout.TransactionRoot)
    if([IO.Directory]::GetFileSystemEntries([string]$registrationLayout.PreparationRoot).Count-eq0){[IO.Directory]::Delete([string]$registrationLayout.PreparationRoot,$false)}
    $recovered=Resume-Framework114Registration $repo ([string]$registrationLayout.TransactionRoot) $ProjectId $registrationLayout
    [pscustomobject]@{status='RECOVERED_CREATED';projectRoot=$projectRoot;frameworkVersion=$FrameworkVersion;recovery=[string]$recovered.Recovery}
    return
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
    Assert-RepoLocalProject $projectRoot $ProjectId $DisplayName $FrameworkVersion $requiredProjectFiles $requiredProjectDirectories $existingStarter.BootstrapTemplate $workspace $ControllerId
    if($FrameworkVersion-in@('1.14.0','1.14.1')){$null=Get-FrameworkAgentsProjection $repo $existingStarter.TemplateRoot $FrameworkVersion}
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
$agentsProjection=Get-FrameworkAgentsProjection $repo $templateRoot $FrameworkVersion

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
}

if (-not $Apply -or -not $PSCmdlet.ShouldProcess($projectRoot, 'Create repository-local project control plane')) {
    $preview=[ordered]@{
        status = 'WHAT_IF'
        projectRoot = $projectRoot
        frameworkVersion = $FrameworkVersion
        templates = @($templateMap.Keys) + $(if($null-ne$agentsProjection){@('AGENTS.md','.agents/skills/ai-workspace-router/SKILL.md')}else{@()})
    }
    if($null-ne$registrationLayout){
        $preview.preparationPath=[string]$registrationLayout.PreparationRoot;$preview.transactionPath=[string]$registrationLayout.TransactionRoot;$preview.recoveryPath=[string]$registrationLayout.RecoveryRoot;$preview.writeSet=@(Get-Framework114RegistrationObjectPaths)
        Write-Output ('REGISTRATION_LOCATORS|preparation='+[string]$registrationLayout.PreparationRoot+'|transaction='+[string]$registrationLayout.TransactionRoot+'|recovery='+[string]$registrationLayout.RecoveryRoot)
        Write-Output ('REGISTRATION_WRITESET|'+[string]::Join('|',@(Get-Framework114RegistrationObjectPaths)))
    }
    [pscustomobject]$preview
    return
}

$null=if($null-ne$registrationLayout){Assert-Framework114RegistrationRecoveryDestination $repo $registrationLayout}
$stagingRoot = if($null-ne$registrationLayout){[string]$registrationLayout.ControlStagingRoot}else{Join-Path $repo ".$ProjectId.ai-workspace-init.$([Guid]::NewGuid().ToString('N'))"}
if($null-ne$registrationLayout-and(Test-Path -LiteralPath $registrationLayout.PreparationRoot)){throw ('REGISTRATION_PREPARATION_ALREADY_EXISTS|'+[string]$registrationLayout.PreparationRoot)}

try {
    New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'tasks/active') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-ChildPath $stagingRoot 'tasks/archive') -Force | Out-Null

    foreach ($entry in $templateMap.GetEnumerator()) {
        $sourcePath = Join-ChildPath $templateRoot $entry.Key
        $destinationPath = Join-ChildPath $stagingRoot $entry.Value
        $content = Read-StrictUtf8Template $sourcePath

        foreach ($token in $markdownTokens.GetEnumerator()) {
            $content = $content.Replace($token.Key, $token.Value)
        }
        foreach ($token in $jsonTokens.GetEnumerator()) {
            $content = $content.Replace($token.Key, $token.Value)
        }

        if ($content -match '\{\{[A-Z0-9_]+\}\}') {
            throw "Unresolved template token in: $sourcePath"
        }
        if ($entry.Value -in @('project.json','controller.json','corrections.json','process-policy.json')) {
            $null = $content | ConvertFrom-Json
        }

        Write-Utf8NoBom -Path $destinationPath -Content $content
        $null = Read-StrictUtf8Template $destinationPath
    }

    Assert-RepoLocalProject $stagingRoot $ProjectId $DisplayName $FrameworkVersion $requiredProjectFiles $requiredProjectDirectories $starter.BootstrapTemplate $workspace $ControllerId
    if($null-ne$agentsProjection){$null=Commit-Framework114Registration $repo $stagingRoot $projectRoot $agentsProjection $ProjectId $registrationLayout}else{[System.IO.Directory]::Move($stagingRoot, $projectRoot)}
}
catch {
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
        throw "Registration failed; initialization staging was preserved at $stagingRoot. $($_.Exception.Message)"
    }
    throw
}

[pscustomobject]@{
    status = 'CREATED'
    projectRoot = $projectRoot
    frameworkVersion = $FrameworkVersion
    createdFiles = @($templateMap.Values) + $(if($null-ne$agentsProjection){@('../AGENTS.md','../.agents/skills/ai-workspace-router/SKILL.md')}else{@()})
    nextAction = 'AI session completes project-specific facts, validates repo-local FULL_COLD_RECOVERY, then reports READY or NEEDS_INPUT.'
}
