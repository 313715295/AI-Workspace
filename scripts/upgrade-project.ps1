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

    [string]$ActorRouteTaskPath,

    [string]$ExpectedActorRouteTaskIdentity,

    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$ActorRouteActor,

    [string]$AuthorizationPackagePath,

    [string]$ExpectedAuthorizationPackageIdentity,

    [string]$CurrentProcessInputPath,

    [string]$ExpectedCurrentProcessInputIdentity,

    [ValidateRange(1, 98304)]
    [int]$SelectedRulePackBytes = 32768,

    [string]$ProjectCorrectionsMigrationPath,

    [string]$ExpectedProjectCorrectionsMigrationIdentity,

    [string]$ProjectCorrectionsMigrationRepairPath,

    [string]$ExpectedProjectCorrectionsMigrationRepairIdentity,

    [switch]$RepairProjectCorrectionsMigrationCandidate,

    [switch]$RepairSelectedRulePackBudget,

    [switch]$LocalCandidatePilot,

    [switch]$Apply,

    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:CurrentPinBudgetBridge = $null
$script:ActiveAdoptionProfile = $null
$script:ActiveSourceAdoptionProfile = $null
$script:ActiveTargetCapabilityContract = $null
$script:ActiveTargetSnapshot = $null
$powershell7Versions=@('1.12.0','1.13.0','1.14.0','1.14.1','1.15.0','1.15.1','1.16.0')
if($ToVersion-in$powershell7Versions-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){
    throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'
}
$maintenanceModulePath=Join-Path $PSScriptRoot 'MaintenanceOverlay.psm1'
if(-not(Test-Path -LiteralPath $maintenanceModulePath -PathType Leaf)){throw 'MAINTENANCE_OVERLAY_MODULE_MISSING'}
Import-Module $maintenanceModulePath -Force

function Get-OptionalIdentity([string]$Path){if(Test-Path -LiteralPath $Path -PathType Leaf){return Get-MinimalFileIdentity $Path};return 'MISSING'}
function Write-ProjectedText([string]$Path,[string]$Content){[IO.File]::WriteAllText($Path,$Content,$utf8NoBom)}
function Get-RuntimeGitIgnoreProjection([string]$RepositoryRoot,[string]$Rule){
    $path=Join-Path $RepositoryRoot '.gitignore';$oldIdentity=Get-OptionalIdentity $path;$content=''
    if($oldIdentity-cne'MISSING'){$bytes=[IO.File]::ReadAllBytes($path);if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'RUNTIME_GITIGNORE_BOM'};try{$content=$utf8Strict.GetString($bytes)}catch{throw 'RUNTIME_GITIGNORE_UTF8'};if($content.Contains([char]0)){throw 'RUNTIME_GITIGNORE_NUL'}}
    $normalizedRule=$Rule.Trim().TrimStart('!').TrimStart('/').TrimEnd('/');$lines=[regex]::Split($content,"`r?`n");$matches=@();$negated=@()
    for($i=0;$i-lt$lines.Count;$i++){$trim=$lines[$i].Trim();if([string]::IsNullOrWhiteSpace($trim)-or$trim.StartsWith('#')){continue};$candidate=$trim.TrimStart('!').TrimStart('/').TrimEnd('/');if($candidate-ceq$normalizedRule){if($trim.StartsWith('!')){$negated+=$i}else{$matches+=$i}}}
    if($negated.Count-ne0){throw 'RUNTIME_GITIGNORE_NEGATION_CONFLICT'};if($matches.Count-gt1){throw 'RUNTIME_GITIGNORE_DUPLICATE_CONFLICT'};if($matches.Count-eq1){return [pscustomobject]@{Path=$path;OldIdentity=$oldIdentity;Content=$content;Changed=$false}}
    $newline=if($content.Contains("`r`n")){"`r`n"}else{"`n"}
    if($matches.Count-eq0){if($content.Length-gt0-and-not($content.EndsWith("`n"))){$content+=$newline};$content+=$Rule+$newline}
    return [pscustomobject]@{Path=$path;OldIdentity=$oldIdentity;Content=$content;Changed=$true}
}

function Assert-ActorBoundLivePath([string]$RepositoryRoot,[string]$RelativePath) {
    $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    $null=Join-ChildPath $root $RelativePath
    $current=$root
    Assert-NoReparsePoint $current
    $segments=$RelativePath.Split('/')
    for($index=0;$index-lt$segments.Count;$index++){
        $current=Join-Path $current $segments[$index]
        $item=Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if($null-eq$item){break}
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){
            if(Test-ManagedRouterRelative $RelativePath){throw ('MANAGED_ROUTER_DESTINATION_REPARSE|'+$RelativePath)}
            throw ('ACTOR_BOUND_UPGRADE_LIVE_REPARSE|'+$RelativePath)
        }
        if($index-lt$segments.Count-1-and-not$item.PSIsContainer){throw ('ACTOR_BOUND_UPGRADE_LIVE_TYPE|'+$RelativePath)}
        if($index-eq$segments.Count-1-and$item.PSIsContainer){throw ('ACTOR_BOUND_UPGRADE_LIVE_TYPE|'+$RelativePath)}
    }
}

function Test-AdoptionProfileVersion([string]$Version){return $null-ne$script:ActiveAdoptionProfile-and[string]$script:ActiveAdoptionProfile.frameworkVersion-ceq$Version}
function Get-ProcessCarrierContractVersion([string]$FrameworkVersion,$AdoptionProfile=$null){if($null-ne$AdoptionProfile-and[string]$AdoptionProfile.frameworkVersion-ceq$FrameworkVersion){return [string]$AdoptionProfile.projectControl.processCarrierContractVersion};if(Test-AdoptionProfileVersion $FrameworkVersion){return [string]$script:ActiveAdoptionProfile.projectControl.processCarrierContractVersion};if($FrameworkVersion-in@('1.14.0','1.14.1','1.15.0','1.15.1')){return '1.14.0'};return $FrameworkVersion}
function Test-GlobalRouterProjection([string]$FrameworkVersion,$AdoptionProfile=$null){if($null-ne$AdoptionProfile-and[string]$AdoptionProfile.frameworkVersion-ceq$FrameworkVersion){return [string]$AdoptionProfile.projectControl.navigationProjection-in@('HOST_GLOBAL_SKILL_MANAGED_AGENTS','ROOT_CANONICAL_SKILL_MANAGED_AGENTS')};return $FrameworkVersion-in@('1.15.0','1.15.1')}

function Assert-ExactTransactionTree([string]$Root,[string[]]$ExpectedFiles,[string[]]$AdditionalDirectories,[string]$ErrorCode) {
    $fileSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$directorySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($relative in $ExpectedFiles){$null=Join-ChildPath $Root $relative;if(-not$fileSet.Add($relative)){throw $ErrorCode};$segments=$relative.Split('/');for($i=1;$i-lt$segments.Count;$i++){$null=$directorySet.Add([string]::Join('/',@($segments[0..($i-1)])))}}
    foreach($relative in $AdditionalDirectories){$null=Join-ChildPath $Root $relative;$segments=$relative.Split('/');for($i=1;$i-le$segments.Count;$i++){$null=$directorySet.Add([string]::Join('/',@($segments[0..($i-1)])))}}
    $actualFiles=@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')})
    $actualDirectories=@(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')})
    if($actualFiles.Count-ne$fileSet.Count-or@($actualFiles|Where-Object{-not$fileSet.Contains($_)}).Count-ne0-or$actualDirectories.Count-ne$directorySet.Count-or@($actualDirectories|Where-Object{-not$directorySet.Contains($_)}).Count-ne0){throw $ErrorCode}
}

function Get-ActorBoundRecoveryContract([string]$RepositoryRoot,[string]$RecoveryRoot,$State,[string]$StateRaw,[string]$ProjectId,[string]$TargetVersion,$Migration) {
    if(-not(Test-MinimalJsonInteger $State.schemaVersion)-or[int]$State.schemaVersion-notin@(2,3)){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_SCHEMA'}
    $stateFields=@('schemaVersion','projectId','fromVersion','toVersion','targetReleaseCanonical','targetReleaseManifestIdentity','actor','taskId','taskOwner','taskRelative','authorizationIdentity','objects')
    if([int]$State.schemaVersion-eq3){$stateFields+=@('projectionMode','projectionObjects')}
    Assert-MinimalExactFields $State $StateRaw $stateFields 'actor-bound upgrade recovery'
    if([string]$State.projectId-cne$ProjectId-or[string]$State.toVersion-cne$TargetVersion-or[string]$State.actor-cne$Migration.Actor-or[string]$State.taskId-cne$Migration.TaskId-or[string]$State.taskOwner-cne$Migration.Owner-or[string]$State.taskRelative-cne$Migration.Relative-or[string]$State.authorizationIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not($State.objects-is[Array])){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}

    $records=New-Object 'System.Collections.Generic.List[object]';$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$materialFiles=New-Object 'System.Collections.Generic.List[string]'
    foreach($entry in @($State.objects)){
        $entryRaw=$entry|ConvertTo-Json -Compress;Assert-MinimalExactFields $entry $entryRaw @('relative','oldIdentity','newIdentity') 'actor-bound upgrade object'
        if(-not($entry.relative-is[string])-or-not$seen.Add([string]$entry.relative)-or([string]$entry.oldIdentity-cne'MISSING'-and[string]$entry.oldIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')-or([string]$entry.newIdentity-cne'ABSENT'-and[string]$entry.newIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_OBJECT'}
        $record=[pscustomobject]@{relative=[string]$entry.relative;path=(Join-ChildPath $RepositoryRoot ([string]$entry.relative));oldIdentity=[string]$entry.oldIdentity;newIdentity=[string]$entry.newIdentity};$records.Add($record)
        foreach($kind in @('old','new')){
            $expected=if($kind-ceq'old'){[string]$record.oldIdentity}else{[string]$record.newIdentity};$missing=$expected-in@('MISSING','ABSENT');$material=Join-ChildPath (Join-Path $RecoveryRoot $kind) ([string]$record.relative)
            if($missing){if(Test-Path -LiteralPath $material){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_UNEXPECTED_MATERIAL'}}else{if((Get-OptionalIdentity $material)-cne$expected){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_MATERIAL'};$materialFiles.Add($kind+'/'+[string]$record.relative)}
        }
    }
    if(-not$seen.Contains($Migration.Relative)-or[string]@($State.objects)[-1].relative-cne$Migration.Relative){throw 'ACTOR_BOUND_UPGRADE_TASK_NOT_LAST'}
    Assert-ExactTransactionTree $RecoveryRoot (@('state.json')+@($materialFiles)) ([string[]]@()) 'ACTOR_BOUND_UPGRADE_RECOVERY_TREE_CLOSURE'

    $projectionRecords=New-Object 'System.Collections.Generic.List[object]'
    if([int]$State.schemaVersion-eq2){
        foreach($record in $records){$projectionRecords.Add([pscustomobject]@{relative=[string]$record.relative;identity=$(if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity})})}
    }else{
        if([string]$State.projectionMode-cne'LOCAL_CANDIDATE_MANAGED'-or-not($State.projectionObjects-is[Array])){throw 'LOCAL_CANDIDATE_PROJECTION_STATE_BINDING'}
        $projectionSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($entry in @($State.projectionObjects)){
            $entryRaw=$entry|ConvertTo-Json -Compress;Assert-MinimalExactFields $entry $entryRaw @('relative','identity') 'local-candidate projection object'
            if(-not($entry.relative-is[string])-or-not$projectionSeen.Add([string]$entry.relative)-or([string]$entry.identity-cne'MISSING'-and[string]$entry.identity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'LOCAL_CANDIDATE_PROJECTION_OBJECT'}
            $null=Join-ChildPath $RepositoryRoot ([string]$entry.relative);$projectionRecords.Add([pscustomobject]@{relative=[string]$entry.relative;identity=[string]$entry.identity})
        }
        foreach($relative in $seen){if(-not$projectionSeen.Contains($relative)){throw ('LOCAL_CANDIDATE_PROJECTION_OBJECT_MISSING|'+$relative)}}
        if(-not$projectionSeen.Contains($Migration.Relative)-or[string]@($State.projectionObjects)[-1].relative-cne$Migration.Relative){throw 'LOCAL_CANDIDATE_PROJECTION_TASK_NOT_LAST'}
    }
    return [pscustomobject]@{SchemaVersion=[int]$State.schemaVersion;Records=[object[]]$records.ToArray();ProjectionRecords=[object[]]$projectionRecords.ToArray()}
}

function Get-ActorRouteMigration([string]$RepositoryRoot,[string]$TargetVersion,[string]$RelativePath,[string]$ExpectedIdentity,[string]$Actor){
    $provided=@(-not[string]::IsNullOrWhiteSpace($RelativePath),-not[string]::IsNullOrWhiteSpace($ExpectedIdentity),-not[string]::IsNullOrWhiteSpace($Actor))
    if(@($provided|Where-Object{$_}).Count-eq0){return $null}
    if(@($provided|Where-Object{$_}).Count-ne3){throw 'ACTOR_ROUTE_MIGRATION_FIELDS_REQUIRED'}
    if($TargetVersion-notin@('1.13.0','1.14.0','1.14.1','1.15.0','1.15.1')-and-not(Test-AdoptionProfileVersion $TargetVersion)){throw 'ACTOR_ROUTE_MIGRATION_TARGET_UNSUPPORTED'}
    if($RelativePath-cne$RelativePath.Replace('\','/')-or$RelativePath-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'-or[IO.Path]::IsPathRooted($RelativePath)-or$RelativePath.Contains(':')){throw 'ACTOR_ROUTE_CURRENT_ACTIVE_TASK_REQUIRED'}
    if($ExpectedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ACTOR_ROUTE_TASK_IDENTITY'}
    $path=Join-ChildPath $RepositoryRoot $RelativePath
    $recoveryRelative=if($TargetVersion-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion $TargetVersion)){'.ai-workspace/upgrade-recovery/'+$TargetVersion}else{'.framework-actor-bound-upgrade-recovery-'+$TargetVersion}
    $recoveryRoot=Join-ChildPath $RepositoryRoot $recoveryRelative
    $recoveryState=$null
    $snapshotRebindRequired=$false
    $projectionState=$false
    if(Test-Path -LiteralPath $recoveryRoot -PathType Container){
        $statePath=Join-Path $recoveryRoot 'state.json';$stateRaw=Read-StrictUtf8NoBom $statePath
        try{$recoveryState=$stateRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_RECOVERY_JSON'}
        if([string]$recoveryState.toVersion-cne$TargetVersion-or[string]$recoveryState.taskRelative-cne$RelativePath-or[string]$recoveryState.actor-cne$Actor){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}
        $snapshotRebindRequired=$null-ne$script:ActiveTargetSnapshot-and[bool]$script:ActiveTargetSnapshot.LocalCandidate-and([string]$recoveryState.targetReleaseCanonical-cne[string]$script:ActiveTargetSnapshot.Canonical-or[string]$recoveryState.targetReleaseManifestIdentity-cne[string]$script:ActiveTargetSnapshot.ManifestIdentity)
        $projectionState=[int]$recoveryState.schemaVersion-eq3
        if($snapshotRebindRequired-or$projectionState){
            if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-MinimalFileIdentity $path)-cne$ExpectedIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'}
            $raw=Read-StrictUtf8NoBom $path
        }else{
            $oldPath=Join-ChildPath (Join-Path $recoveryRoot 'old') $RelativePath
            if(-not(Test-Path -LiteralPath $oldPath -PathType Leaf)-or(Get-MinimalFileIdentity $oldPath)-cne$ExpectedIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'}
            $raw=Read-StrictUtf8NoBom $oldPath
        }
    }else{
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-MinimalFileIdentity $path)-cne$ExpectedIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'}
        $raw=Read-StrictUtf8NoBom $path
    }
    $header=[regex]::Matches($raw,'(?m)^#\s+(?<task>[0-9A-Za-z][0-9A-Za-z._-]*)\s+[-—]')
    $owner=[regex]::Matches($raw,'(?m)^- Owner:\s*`?(?<owner>[^`\r\n]+?)`?\s*$')
    $range=[regex]::Matches($raw,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL); lifecycle=(?<lifecycle>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED);(?: current_exact=(?<exact>[^;]+);)? expected_paths=\[(?<expected>[^\]]*)\]; actual_paths=\[(?<actual>[^\]]*)\]\s*$')
    $schemaVersions=if($snapshotRebindRequired-or$projectionState){@($TargetVersion)}elseif(Test-AdoptionProfileVersion $TargetVersion){@('1.11.0','1.12.0')+@($script:ActiveAdoptionProfile.directSourceVersions|ForEach-Object{[string]$_})}elseif($TargetVersion-in@('1.15.0','1.15.1')){@('1.11.0','1.14.0','1.14.1')}else{@('1.11.0')}
    $schemaPattern='(?m)^- Task schema:\s*(?<version>'+[string]::Join('|',@($schemaVersions|ForEach-Object{[regex]::Escape($_)}))+')\s*$'
    $schema=[regex]::Matches($raw,$schemaPattern)
    $legacy=[regex]::Matches($raw,'(?m)^- Work route:\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
    $current=[regex]::Matches($raw,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
    $fileTask=[IO.Path]::GetFileNameWithoutExtension($RelativePath)
    if($header.Count-ne1-or[string]$header[0].Groups['task'].Value-cne$fileTask-or$owner.Count-ne1-or[string]::IsNullOrWhiteSpace([string]$owner[0].Groups['owner'].Value)-or$range.Count-ne1-or[string]$range[0].Groups['lifecycle'].Value-cne'ACTIVE'){throw 'ACTOR_ROUTE_CURRENT_TASK_BINDING_REQUIRED'}
    if($schema.Count-ne1){throw 'ACTOR_ROUTE_SOURCE_SCHEMA_REQUIRED'}
    if($legacy.Count-eq1-and$current.Count-eq0){
        $replacement='- Work route: actor='+$Actor+'; role='+[string]$legacy[0].Groups['role'].Value+'; phase='+[string]$legacy[0].Groups['phase'].Value
        $target=$raw.Substring(0,$legacy[0].Index)+$replacement+$raw.Substring($legacy[0].Index+$legacy[0].Length)
    }elseif(($TargetVersion-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion $TargetVersion))-and$current.Count-eq1-and$legacy.Count-eq0-and[string]$current[0].Groups['actor'].Value-ceq$Actor){
        $target=$raw
    }else{throw 'ACTOR_ROUTE_SOURCE_BINDING_REQUIRED'}
    $target=$target.Substring(0,$schema[0].Index)+'- Task schema: '+$TargetVersion+$target.Substring($schema[0].Index+$schema[0].Length)
    $actualPaths=if([string]::IsNullOrWhiteSpace([string]$range[0].Groups['actual'].Value)){@()}else{@([string]$range[0].Groups['actual'].Value -split '\|')}
    $directory=[IO.Path]::GetDirectoryName($RelativePath).Replace('\','/')
    $atomicRelative=$directory+'/.'+[IO.Path]::GetFileName($RelativePath)+'.actor-route-new'
    $newIdentity=Get-MinimalBytesIdentity ($utf8NoBom.GetBytes($target))
    if($null-ne$recoveryState){
        $entry=if([int]$recoveryState.schemaVersion-eq3){@($recoveryState.projectionObjects|Where-Object{[string]$_.relative-ceq$RelativePath})}else{@($recoveryState.objects|Where-Object{[string]$_.relative-ceq$RelativePath})}
        # 已完成投影中的 task identity 是历史证据；本次操作由上面的当前文件校验和 task/Owner/actor 绑定约束。
        if($snapshotRebindRequired-or[int]$recoveryState.schemaVersion-eq3){if($entry.Count-ne1){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'};if($newIdentity-cne$ExpectedIdentity-or[string]$recoveryState.taskId-cne$fileTask-or[string]$recoveryState.taskOwner-cne[string]$owner[0].Groups['owner'].Value){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}}
        elseif($entry.Count-ne1-or[string]$entry[0].oldIdentity-cne$ExpectedIdentity-or[string]$entry[0].newIdentity-cne$newIdentity-or[string]$recoveryState.taskId-cne$fileTask-or[string]$recoveryState.taskOwner-cne[string]$owner[0].Groups['owner'].Value){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}
    }
    return [pscustomobject]@{Relative=$RelativePath;Path=$path;OldIdentity=$ExpectedIdentity;NewIdentity=$newIdentity;Actor=$Actor;TaskId=$fileTask;Owner=[string]$owner[0].Groups['owner'].Value;ActualPaths=$actualPaths;AtomicRelative=$atomicRelative;Content=$target;SnapshotRebindRequired=$snapshotRebindRequired;RecoveryState=$recoveryState}
}

function Get-ActorBoundUpgrade115Plan([string]$RepositoryRoot,[string]$TargetFramework,[string]$FromVersion,[string]$TargetVersion,[string]$ProjectId,$Migration,[object[]]$Objects){
    $preparationRelative='.ai-workspace/tmp/upgrade-preparation/'+$TargetVersion
    $recoveryRelative='.ai-workspace/upgrade-recovery/'+$TargetVersion
    $allObjects=@($Objects)+@([pscustomobject]@{relative=$Migration.Relative;path=$Migration.Path;content=$Migration.Content})
    $records=New-Object 'System.Collections.Generic.List[object]'
    foreach($object in $allObjects){
        Assert-ActorBoundLivePath $RepositoryRoot ([string]$object.relative)
        $oldIdentity=Get-OptionalIdentity $object.path
        $newIdentity=if($null-eq$object.content){'ABSENT'}else{Get-MinimalBytesIdentity ($utf8NoBom.GetBytes([string]$object.content))}
        if($oldIdentity-ceq'MISSING'-and$newIdentity-ceq'ABSENT'){throw ('UPGRADE_OBJECT_NO_CHANGE|'+[string]$object.relative)}
        if($oldIdentity-ceq$newIdentity){continue}
        $records.Add([pscustomobject]@{relative=[string]$object.relative;path=[string]$object.path;content=$object.content;oldIdentity=$oldIdentity;newIdentity=$newIdentity})
    }
    $taskRecord=@($records|Where-Object{[string]$_.relative-ceq$Migration.Relative})
    if($taskRecord.Count-ne1){throw 'ACTOR_BOUND_UPGRADE_TASK_RECORD'}
    $ordered=@($records|Where-Object{[string]$_.relative-cne$Migration.Relative})+@($taskRecord[0])
    $targetSnapshot=$script:ActiveTargetSnapshot
    if($null-eq$targetSnapshot-or[string]$targetSnapshot.Version-cne$TargetVersion-or[string]$targetSnapshot.Canonical-cnotmatch'^[A-F0-9]{64}$'-or[string]$targetSnapshot.ManifestIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'TARGET_FRAMEWORK_SNAPSHOT_UNBOUND'}
    $stateObjects=@($ordered|ForEach-Object{[ordered]@{relative=$_.relative;oldIdentity=$_.oldIdentity;newIdentity=$_.newIdentity}})
    $state=[ordered]@{schemaVersion=2;projectId=$ProjectId;fromVersion=$FromVersion;toVersion=$TargetVersion;targetReleaseCanonical=[string]$targetSnapshot.Canonical;targetReleaseManifestIdentity=[string]$targetSnapshot.ManifestIdentity;actor=$Migration.Actor;taskId=$Migration.TaskId;taskOwner=$Migration.Owner;taskRelative=$Migration.Relative;authorizationIdentity=$ExpectedAuthorizationPackageIdentity;objects=$stateObjects}
    $stateText=Normalize-Text ($state|ConvertTo-Json -Depth 20)
    $preparationFiles=New-Object 'System.Collections.Generic.List[string]';$recoveryFiles=New-Object 'System.Collections.Generic.List[string]'
    foreach($record in $ordered){
        if([string]$record.oldIdentity-cne'MISSING'){$preparationFiles.Add('old/'+[string]$record.relative);$recoveryFiles.Add('old/'+[string]$record.relative)}
        if([string]$record.newIdentity-cne'ABSENT'){$preparationFiles.Add('new/'+[string]$record.relative);$recoveryFiles.Add('new/'+[string]$record.relative)}
    }
    $preparationFiles.Add('state.json');$recoveryFiles.Add('state.json')
    $exactPaths=New-Object 'System.Collections.Generic.List[string]';$preimages=New-Object 'System.Collections.Generic.List[object]';$postimages=New-Object 'System.Collections.Generic.List[object]'
    foreach($record in $ordered){$exactPaths.Add([string]$record.relative);$preimages.Add([pscustomobject]@{path=[string]$record.relative;identity=$(if([string]$record.oldIdentity-ceq'MISSING'){'NEW'}else{[string]$record.oldIdentity})});$postimages.Add([pscustomobject]@{path=[string]$record.relative;identity=[string]$record.newIdentity})}
    foreach($file in $preparationFiles){$relative=$preparationRelative+'/'+$file;$exactPaths.Add($relative);$preimages.Add([pscustomobject]@{path=$relative;identity='NEW'})}
    foreach($file in $recoveryFiles){$relative=$recoveryRelative+'/'+$file;$exactPaths.Add($relative);$preimages.Add([pscustomobject]@{path=$relative;identity='NEW'})}
    return [pscustomobject]@{PreparationRelative=$preparationRelative;RecoveryRelative=$recoveryRelative;Records=[object[]]$ordered;State=$state;StateText=$stateText;PreparationFiles=$preparationFiles.ToArray();RecoveryFiles=$recoveryFiles.ToArray();ExactPaths=$exactPaths.ToArray();Preimages=$preimages.ToArray();Postimages=$postimages.ToArray()}
}

function Write-ActorBoundUpgrade115Plan($Plan,[string]$FromVersion,[string]$TargetVersion){
    Write-Output ('UPGRADE_TARGET_MODE|lifecycle='+[string]$script:ActiveTargetSnapshot.Lifecycle+'|localCandidate='+[string]$script:ActiveTargetSnapshot.LocalCandidate)
    Write-Output ('UPGRADE_TARGET_RELEASE|canonical='+[string]$Plan.State.targetReleaseCanonical+'|manifest='+[string]$Plan.State.targetReleaseManifestIdentity)
    foreach($entry in $Plan.Preimages){Write-Output ('UPGRADE_PREIMAGE|'+[string]$entry.path+'='+[string]$entry.identity)}
    foreach($entry in $Plan.Postimages){Write-Output ('UPGRADE_POSTIMAGE|'+[string]$entry.path+'='+[string]$entry.identity)}
    Write-Output ('UPGRADE_WRITESET|'+[string]::Join('|',@($Plan.ExactPaths)))
    Write-Output ('WHAT_IF|from='+$FromVersion+'|to='+$TargetVersion+'|objects='+$Plan.Records.Count+'|transaction=actor-bound-schema3')
}

function Assert-ActorBoundTargetSnapshot($Package,[string]$Canonical,[string]$ManifestIdentity,[bool]$Required) {
    $property=$Package.PSObject.Properties['targetFrameworkSnapshot']
    if($null-eq$property){if($Required){throw 'LOCAL_CANDIDATE_AUTHORIZATION_SNAPSHOT_REQUIRED'};return}
    $snapshot=$Package.targetFrameworkSnapshot
    if(-not($snapshot-is[pscustomobject])-or@($snapshot.PSObject.Properties.Name).Count-ne2-or$null-eq$snapshot.PSObject.Properties['canonical']-or$null-eq$snapshot.PSObject.Properties['manifestIdentity']){throw 'TARGET_FRAMEWORK_SNAPSHOT_FIELDS'}
    if(-not($snapshot.canonical-is[string])-or[string]$snapshot.canonical-cnotmatch'^[A-F0-9]{64}$'-or-not($snapshot.manifestIdentity-is[string])-or[string]$snapshot.manifestIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'TARGET_FRAMEWORK_SNAPSHOT_FORMAT'}
    if([string]$snapshot.canonical-cne$Canonical-or[string]$snapshot.manifestIdentity-cne$ManifestIdentity){throw 'TARGET_FRAMEWORK_SNAPSHOT_DRIFT'}
}

function Assert-ActorBoundUpgrade115Authorization([string]$RepositoryRoot,[string]$TargetFramework,[string]$ProjectFile,$Migration,$Plan){
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or[string]::IsNullOrWhiteSpace($ExpectedAuthorizationPackageIdentity)){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_REQUIRED'}
    if($ExpectedAuthorizationPackageIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne$ExpectedAuthorizationPackageIdentity){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DRIFT'}
    $raw=Read-StrictUtf8NoBom $AuthorizationPackagePath;Assert-StrictJsonMemberSet $raw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DUPLICATE_MEMBER'
    try{$package=$raw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_JSON'}
    if([int]$package.schemaVersion-ne3-or[string]$package.frameworkVersion-cne[string]$Plan.State.toVersion-or[string]$package.bundle-cne'ACTOR_BOUND_PROJECT_UPGRADE'-or[string]$package.issuerRole-cne'PROJECT_CONTROLLER'-or[string]$package.grantee-cne$Migration.Actor-or[string]$package.taskId-cne$Migration.TaskId-or[string]$package.owner-cne$Migration.Owner){throw 'ACTOR_BOUND_UPGRADE_AUTHORITY_BINDING'}
    Assert-ActorBoundTargetSnapshot $package ([string]$Plan.State.targetReleaseCanonical) ([string]$Plan.State.targetReleaseManifestIdentity) ([bool]$script:ActiveTargetSnapshot.LocalCandidate)
    if(([string]$Plan.State.toVersion-ceq'1.15.1'-or(Test-AdoptionProfileVersion ([string]$Plan.State.toVersion)))-and($null-eq$script:CurrentPinBudgetBridge-or[string]$package.userConfirmation-cne[string]$script:CurrentPinBudgetBridge.UserDecision)){throw 'CURRENT_PIN_BRIDGE_USER_DECISION_DRIFT'}
    $declared=@($package.exactPaths|ForEach-Object{[string]$_});$expected=@($Plan.ExactPaths);[Array]::Sort($declared,[StringComparer]::Ordinal);[Array]::Sort($expected,[StringComparer]::Ordinal)
    if($declared.Count-ne$expected.Count-or[string]::Join("`n",$declared)-cne[string]::Join("`n",$expected)){throw 'ACTOR_BOUND_UPGRADE_PATHSET_DRIFT'}
    $declaredPost=@($package.postObjectIdentities|ForEach-Object{[string]$_.path+'='+[string]$_.identity});$expectedPost=@($Plan.Postimages|ForEach-Object{[string]$_.path+'='+[string]$_.identity});[Array]::Sort($declaredPost,[StringComparer]::Ordinal);[Array]::Sort($expectedPost,[StringComparer]::Ordinal)
    if($declaredPost.Count-ne$expectedPost.Count-or[string]::Join("`n",$declaredPost)-cne[string]::Join("`n",$expectedPost)){throw 'ACTOR_BOUND_UPGRADE_POSTIMAGE_DRIFT'}
    $observed=@($Plan.Preimages|ForEach-Object{[string]$_.path+'='+[string]$_.identity})
    $projectRaw=Read-StrictUtf8NoBom $ProjectFile;try{$project=$projectRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_PROJECT_JSON'}
    $maintenanceLayout=[string]$project.controlPlaneLayout-ceq'framework-maintenance-sibling'
    $checker=if($maintenanceLayout){Join-Path $PSScriptRoot 'check-framework-maintenance-authorization.ps1'}else{Join-ChildPath $TargetFramework 'scripts/check-authorization.ps1'}
    $args=@{PackagePath=$AuthorizationPackagePath;ObservedActor=$Migration.Actor;ObservedTaskId=$Migration.TaskId;ObservedOwner=$Migration.Owner;ObservedAction=@('CONTROL_WRITE');ObservedPath=@($Plan.ExactPaths);ObservedIdentity=$observed;ControllerControlPath='.ai-workspace/controller.json';ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Get-MinimalFileIdentity $ProjectFile);TaskPath=$Migration.Relative;ExpectedTaskIdentity=$Migration.OldIdentity}
    if($maintenanceLayout){
        $args.ControlRepositoryPath=$RepositoryRoot
        $args.ObservedRepositoryId='CONTROL'
    }else{
        # The root upgrade tool has already resolved and bounded RepositoryRoot.
        # Tell the version checker to validate the explicitly supplied project
        # binding instead of falling back to the legacy current-directory route.
        $args.RootRepositoryBindingValidated=$true
    }
    $previousCurrentDirectory=[Environment]::CurrentDirectory;Push-Location -LiteralPath $RepositoryRoot
    try{[Environment]::CurrentDirectory=$RepositoryRoot;$result=@(& $checker @args 2>&1|ForEach-Object{[string]$_});$checkerExit=$LASTEXITCODE}finally{[Environment]::CurrentDirectory=$previousCurrentDirectory;Pop-Location}
    $samePinProjectionRefresh=$null-ne$Plan.PSObject.Properties['StatePreimage']-and$null-ne$Plan.PSObject.Properties['ProjectedPreflight']-and[bool]$script:ActiveTargetSnapshot.LocalCandidate-and$Plan.Records.Count-gt0
    if($samePinProjectionRefresh-and$checkerExit-eq2-and$result.Count-eq1-and[string]$result[0]-ceq'FAIL|POST_IDENTITY_RECOVERY_PATH'){
        Write-Output ('AUTHORIZATION_ROOT_EXCEPTION|reason=SAME_PIN_CANDIDATE_MANAGED_PROJECTION_REFRESH|recovery='+[string]$Plan.StateRelative)
        return
    }
    $samePinStateRebind=$false
    if($null-ne$Plan.PSObject.Properties['Preimage']-and$null-ne$Plan.PSObject.Properties['Postimage']-and$null-eq$Plan.PSObject.Properties['Records']-and[bool]$script:ActiveTargetSnapshot.LocalCandidate){
        $expectedStateRelative='.ai-workspace/upgrade-recovery/'+[string]$Plan.State.toVersion+'/state.json';$exact=@($Plan.ExactPaths);$pre=@($Plan.Preimages);$post=@($Plan.Postimages)
        $samePinStateRebind=$exact.Count-eq1-and$pre.Count-eq1-and$post.Count-eq1-and[string]$Plan.StateRelative-ceq$expectedStateRelative-and[string]$exact[0]-ceq$expectedStateRelative-and[string]$pre[0].path-ceq$expectedStateRelative-and[string]$post[0].path-ceq$expectedStateRelative-and[string]$pre[0].identity-ceq[string]$Plan.Preimage-and[string]$post[0].identity-ceq[string]$Plan.Postimage
    }
    if($samePinStateRebind-and$checkerExit-eq2-and$result.Count-eq1-and[string]$result[0]-ceq'FAIL|POST_IDENTITY_RECOVERY_PATH'){
        Write-Output ('AUTHORIZATION_ROOT_EXCEPTION|reason=SAME_VERSION_CANDIDATE_STATE_REBIND|recovery='+[string]$Plan.StateRelative)
        return
    }
    $pass=@($result|Where-Object{$_-clike'PASS|*'})
    if($checkerExit-ne0-or$pass.Count-ne1){throw ('ACTOR_BOUND_UPGRADE_AUTHORIZATION_REJECTED|'+($result-join';'))}
    if([string]$pass[0]-clike'*|root-exception=*'){Write-Output ([string]$pass[0])}
}

function Assert-ActorBoundUpgrade115Material([string]$Root,$Plan,[string]$Prefix){
    Assert-NoReparseTree $Root
    $files=if($Prefix-ceq'PREPARATION'){@($Plan.PreparationFiles)}else{@($Plan.RecoveryFiles)}
    Assert-ExactTransactionTree $Root $files ([string[]]@()) ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_TREE')
    foreach($record in $Plan.Records){
        $old=Join-ChildPath (Join-Path $Root 'old') ([string]$record.relative);$new=Join-ChildPath (Join-Path $Root 'new') ([string]$record.relative)
        if([string]$record.oldIdentity-cne'MISSING'-and((Get-OptionalIdentity $old)-cne[string]$record.oldIdentity)){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_OLD_DRIFT|'+[string]$record.relative)}
        if([string]$record.newIdentity-cne'ABSENT'-and((Get-OptionalIdentity $new)-cne[string]$record.newIdentity)){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_NEW_DRIFT|'+[string]$record.relative)}
        if([string]$record.oldIdentity-ceq'MISSING'-and(Test-Path -LiteralPath $old)){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_UNEXPECTED_OLD|'+[string]$record.relative)}
        if([string]$record.newIdentity-ceq'ABSENT'-and(Test-Path -LiteralPath $new)){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_UNEXPECTED_NEW|'+[string]$record.relative)}
    }
    if((Get-MinimalFileIdentity (Join-Path $Root 'state.json'))-cne(Get-MinimalBytesIdentity ($utf8NoBom.GetBytes([string]$Plan.StateText)))){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_STATE_DRIFT')}
}

function Invoke-ActorBoundUpgrade115([string]$RepositoryRoot,[string]$TargetFramework,[string]$FromVersion,[string]$TargetVersion,[string]$ProjectId,[string]$ProjectFile,$Migration,[object[]]$Objects,[bool]$ApplyChange){
    $plan=Get-ActorBoundUpgrade115Plan $RepositoryRoot $TargetFramework $FromVersion $TargetVersion $ProjectId $Migration $Objects
    Write-ActorBoundUpgrade115Plan $plan $FromVersion $TargetVersion
    if(-not$ApplyChange){return}
    Assert-ActorBoundUpgrade115Authorization $RepositoryRoot $TargetFramework $ProjectFile $Migration $plan
    $preparationRoot=Join-ChildPath $RepositoryRoot $plan.PreparationRelative;$recoveryRoot=Join-ChildPath $RepositoryRoot $plan.RecoveryRelative
    if(Test-Path -LiteralPath $preparationRoot){throw 'ACTOR_BOUND_UPGRADE_PREPARATION_EXISTS'}
    if(Test-Path -LiteralPath $recoveryRoot){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_EXISTS'}
    try{
        foreach($record in $plan.Records){
            Assert-ActorBoundLivePath $RepositoryRoot ([string]$record.relative)
            if([string]$record.oldIdentity-cne'MISSING'){$old=Join-ChildPath (Join-Path $preparationRoot 'old') ([string]$record.relative);New-Item -ItemType Directory -Path (Split-Path -Parent $old) -Force|Out-Null;[IO.File]::Copy([string]$record.path,$old,$false)}
            if([string]$record.newIdentity-cne'ABSENT'){$new=Join-ChildPath (Join-Path $preparationRoot 'new') ([string]$record.relative);New-Item -ItemType Directory -Path (Split-Path -Parent $new) -Force|Out-Null;Write-ProjectedText $new ([string]$record.content)}
        }
        Write-Utf8NoBom (Join-Path $preparationRoot 'state.json') ([string]$plan.StateText)
        foreach($record in $plan.Records){if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.oldIdentity){throw ('OBJECT_DRIFT|'+[string]$record.relative)}}
        Assert-ActorBoundUpgrade115Material $preparationRoot $plan 'PREPARATION'
        $recoveryParent=Split-Path -Parent $recoveryRoot;New-Item -ItemType Directory -Path $recoveryParent -Force|Out-Null
        [IO.Directory]::Move($preparationRoot,$recoveryRoot)
        Assert-ActorBoundUpgrade115Material $recoveryRoot $plan 'RECOVERY'
        $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage -ObservedActualPath @($Migration.ActualPaths) 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
        foreach($record in @($plan.Records|Where-Object{[string]$_.relative-cne$Migration.Relative})){
            Assert-ActorBoundLivePath $RepositoryRoot ([string]$record.relative)
            if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.oldIdentity){throw ('OBJECT_DRIFT|'+[string]$record.relative)}
            if([string]$record.newIdentity-ceq'ABSENT'){[IO.File]::Delete([string]$record.path)}else{New-Item -ItemType Directory -Path (Split-Path -Parent ([string]$record.path)) -Force|Out-Null;[IO.File]::Copy((Join-ChildPath (Join-Path $recoveryRoot 'new') ([string]$record.relative)),[string]$record.path,$true)}
            if((Get-OptionalIdentity ([string]$record.path))-cne$(if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity})){throw ('ACTOR_BOUND_UPGRADE_POSTIMAGE_DRIFT|'+[string]$record.relative)}
        }
        if((Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'}
        [IO.File]::Copy($taskStage,$Migration.Path,$true)
        if((Get-OptionalIdentity $Migration.Path)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_POSTIMAGE_DRIFT'}
        foreach($record in $plan.Records){$actual=Get-OptionalIdentity ([string]$record.path);$expected=if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity};if($actual-cne$expected){throw ('ACTOR_BOUND_UPGRADE_FINAL_DRIFT|'+[string]$record.relative)}}
        Write-Output ('UPGRADED|objects='+$plan.Records.Count+'|transaction=actor-bound-schema3|recovery='+$recoveryRoot+'|writes-after-task=ZERO')
    }catch{throw "Actor-bound Framework 1.15 upgrade stopped; exact preparation/recovery material is preserved. $($_.Exception.Message)"}
}

function Resume-ActorBoundUpgrade115([string]$RepositoryRoot,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectId,[string]$ControllerFile,$Migration,[bool]$ApplyChange){
    $recoveryRelative='.ai-workspace/upgrade-recovery/'+$TargetVersion;$recoveryRoot=Join-ChildPath $RepositoryRoot $recoveryRelative;$statePath=Join-Path $recoveryRoot 'state.json'
    if(-not(Test-Path -LiteralPath $recoveryRoot -PathType Container)){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_NOT_DIRECTORY'};Assert-NoReparseTree $recoveryRoot
    $raw=Read-StrictUtf8NoBom $statePath;try{$state=$raw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_RECOVERY_JSON'}
    $contract=Get-ActorBoundRecoveryContract $RepositoryRoot $recoveryRoot $state $raw $ProjectId $TargetVersion $Migration
    if($null-eq$script:ActiveTargetSnapshot-or[string]$script:ActiveTargetSnapshot.Canonical-cne[string]$state.targetReleaseCanonical-or[string]$script:ActiveTargetSnapshot.ManifestIdentity-cne[string]$state.targetReleaseManifestIdentity){throw 'ACTOR_BOUND_UPGRADE_TARGET_RELEASE_DRIFT'}
    $controllerRaw=Read-StrictUtf8NoBom $ControllerFile;try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_CONTROLLER_JSON'};Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    $records=New-Object 'System.Collections.Generic.List[object]';foreach($record in @($contract.Records)){$records.Add($record)}
    if([int]$contract.SchemaVersion-eq3){
        foreach($projection in @($contract.ProjectionRecords)){
            Assert-ActorBoundLivePath $RepositoryRoot ([string]$projection.relative)
            $expected=if([string]$projection.relative-ceq$Migration.Relative){[string]$Migration.OldIdentity}else{[string]$projection.identity}
            if((Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$projection.relative)))-cne$expected){throw ('LOCAL_CANDIDATE_PROJECTION_RECOVERY_REQUIRED|'+[string]$projection.relative)}
        }
        Write-Output 'UPGRADE_RECOVERY_WRITESET|'
        Write-Output ('RECOVERY_COMPLETE|to='+$TargetVersion+'|writes=ZERO|state=LOCAL_CANDIDATE_MANAGED_PROJECTION')
        return
    }
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne[string]$state.authorizationIdentity-or[string]$state.authorizationIdentity-cne$ExpectedAuthorizationPackageIdentity){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DRIFT'}
    $packageRaw=Read-StrictUtf8NoBom $AuthorizationPackagePath;Assert-StrictJsonMemberSet $packageRaw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DUPLICATE_MEMBER';try{$package=$packageRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_JSON'}
    if([int]$package.schemaVersion-ne3-or[string]$package.frameworkVersion-cne$TargetVersion-or[string]$package.bundle-cne'ACTOR_BOUND_PROJECT_UPGRADE'-or[string]$package.issuerRole-cne'PROJECT_CONTROLLER'-or[string]$package.grantee-cne$Migration.Actor-or[string]$package.taskId-cne$Migration.TaskId-or[string]$package.owner-cne$Migration.Owner){throw 'ACTOR_BOUND_UPGRADE_AUTHORITY_BINDING'}
    Assert-ActorBoundTargetSnapshot $package ([string]$state.targetReleaseCanonical) ([string]$state.targetReleaseManifestIdentity) ([bool]$script:ActiveTargetSnapshot.LocalCandidate)
    if([string]$package.issuerControllerId-cne[string]$controller.controllerId-or[int64]$package.issuerControllerEpoch-ne[int64]$controller.controllerEpoch-or[string]$package.controllerControlIdentity-cne(Get-MinimalFileIdentity $ControllerFile)){throw 'ACTOR_BOUND_UPGRADE_CONTROLLER_AUTHORITY_DRIFT'}
    $postDeclared=@($package.postObjectIdentities|ForEach-Object{[string]$_.path+'='+[string]$_.identity});$postExpected=@($records|ForEach-Object{[string]$_.relative+'='+[string]$_.newIdentity});[Array]::Sort($postDeclared,[StringComparer]::Ordinal);[Array]::Sort($postExpected,[StringComparer]::Ordinal)
    if($postDeclared.Count-ne$postExpected.Count-or[string]::Join("`n",$postDeclared)-cne[string]::Join("`n",$postExpected)){throw 'ACTOR_BOUND_UPGRADE_POSTIMAGE_DRIFT'}
    foreach($record in $records){
        Assert-ActorBoundLivePath $RepositoryRoot ([string]$record.relative)
        $live=Get-OptionalIdentity ([string]$record.path);$newLive=if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity};if($live-cne[string]$record.oldIdentity-and$live-cne$newLive){throw ('ACTOR_BOUND_UPGRADE_UNKNOWN_LIVE_BYTES|'+[string]$record.relative)};$record|Add-Member -NotePropertyName liveIdentity -NotePropertyValue $live;$record|Add-Member -NotePropertyName terminalIdentity -NotePropertyValue $newLive
    }
    if($null-ne$script:ActiveTargetCapabilityContract){
        $projectRecords=@($records|Where-Object{[string]$_.relative-ceq'.ai-workspace/project.json'})
        if($projectRecords.Count-ne1-or[string]$projectRecords[0].newIdentity-ceq'ABSENT'){throw 'ACTOR_BOUND_UPGRADE_TARGET_PROJECT_MISSING'}
        $targetProjectMaterial=Join-ChildPath (Join-Path $recoveryRoot 'new') '.ai-workspace/project.json'
        Assert-TargetProjectCapabilities (Read-StrictUtf8NoBom $targetProjectMaterial) 'ACTOR_BOUND_UPGRADE_TARGET_PROJECT'
    }
    $task=@($records|Where-Object{[string]$_.relative-ceq$Migration.Relative})[0]
    if([string]$task.liveIdentity-ceq[string]$task.terminalIdentity-and@($records|Where-Object{[string]$_.liveIdentity-cne[string]$_.terminalIdentity}).Count-ne0){throw 'ACTOR_BOUND_UPGRADE_TASK_ADVANCED_BEFORE_OBJECTS'}
    $remaining=@($records|Where-Object{[string]$_.liveIdentity-cne[string]$_.terminalIdentity})
    Write-Output ('UPGRADE_RECOVERY_WRITESET|'+[string]::Join('|',@($remaining.relative)))
    if(-not$ApplyChange){Write-Output ('RECOVERY_REQUIRED|from='+[string]$state.fromVersion+'|to='+$TargetVersion+'|remaining='+$remaining.Count);return}
    if($remaining.Count-eq0){Write-Output ('RECOVERY_COMPLETE|to='+$TargetVersion+'|writes=ZERO');return}
    $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage -ObservedActualPath @($Migration.ActualPaths) 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
    foreach($record in @($remaining|Where-Object{[string]$_.relative-cne$Migration.Relative})){
        Assert-ActorBoundLivePath $RepositoryRoot ([string]$record.relative)
        if([string]$record.newIdentity-ceq'ABSENT'){[IO.File]::Delete([string]$record.path)}else{New-Item -ItemType Directory -Path (Split-Path -Parent ([string]$record.path)) -Force|Out-Null;[IO.File]::Copy((Join-ChildPath (Join-Path $recoveryRoot 'new') ([string]$record.relative)),[string]$record.path,$true)}
        if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.terminalIdentity){throw ('ACTOR_BOUND_UPGRADE_POSTIMAGE_DRIFT|'+[string]$record.relative)}
    }
    if([string]$task.liveIdentity-cne[string]$task.terminalIdentity){if((Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'};[IO.File]::Copy($taskStage,$Migration.Path,$true);if((Get-OptionalIdentity $Migration.Path)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_POSTIMAGE_DRIFT'}}
    foreach($record in $records){if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.terminalIdentity){throw ('ACTOR_BOUND_UPGRADE_FINAL_DRIFT|'+[string]$record.relative)}}
    Write-Output ('RECOVERED_UPGRADE|to='+$TargetVersion+'|recovery='+$recoveryRoot+'|writes-after-task=ZERO')
}

function Assert-LocalCandidateSamePinProjectProjection([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectFile,[string]$BootstrapFile,[string]$Layout,[string]$ProjectId){
    if($null-eq$script:ActiveTargetSnapshot-or-not[bool]$script:ActiveTargetSnapshot.LocalCandidate-or-not(Test-AdoptionProfileVersion $TargetVersion)){throw 'LOCAL_CANDIDATE_SAME_PIN_PROJECTION_TARGET'}
    $projectRaw=Read-StrictUtf8NoBom $ProjectFile;try{$project=$projectRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_PROJECT_JSON'}
    if([string]$project.id-cne$ProjectId-or[string]$project.frameworkVersion-cne$TargetVersion-or[string]$project.controlPlaneLayout-cne$Layout){throw 'LOCAL_CANDIDATE_SAME_PIN_PROJECT_BINDING'}
    Assert-TargetProjectCapabilities $projectRaw 'LOCAL_CANDIDATE_SAME_PIN_PROJECT'
    $templateRoot=if($Layout-ceq'framework-maintenance-sibling'){[string](Get-AiwMaintenanceOverlay $FrameworkWorkspace).Root}else{Join-ChildPath $TargetFramework 'project-starter'}
    $templatePath=Join-ChildPath $templateRoot 'BOOTSTRAP.md';$template=Read-StrictUtf8NoBom $templatePath;$currentBootstrap=Read-StrictUtf8NoBom $BootstrapFile
    $expectedBootstrap=Render-Bootstrap $template $project $TargetVersion;$currentBlock=Get-ManagedBootstrapBlock $currentBootstrap $BootstrapFile;$expectedBlock=Get-ManagedBootstrapBlock $expectedBootstrap $templatePath
    if($currentBlock.Text-cne$expectedBlock.Text){throw 'LOCAL_CANDIDATE_SAME_PIN_BOOTSTRAP_PROJECTION_DRIFT'}
    $policyPath=Join-ChildPath (Split-Path -Parent $ProjectFile) 'process-policy.json';$policyRaw=Read-StrictUtf8NoBom $policyPath;try{$policy=$policyRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_POLICY_JSON'}
    Assert-MinimalExactFields $policy $policyRaw @('schemaVersion','contractVersion','projectId','selectedRulePackBytes','rules') 'local-candidate same-pin process policy'
    if(-not(Test-MinimalJsonInteger $policy.schemaVersion)-or[int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne(Get-ProcessCarrierContractVersion $TargetVersion $script:ActiveAdoptionProfile)-or[string]$policy.projectId-cne$ProjectId-or-not(Test-MinimalJsonInteger $policy.selectedRulePackBytes)-or[int]$policy.selectedRulePackBytes-lt1-or[int]$policy.selectedRulePackBytes-gt[int]$script:ActiveAdoptionProfile.processBudget.absoluteSelectedRulePackBytes-or-not($policy.rules-is[Array])){throw 'LOCAL_CANDIDATE_SAME_PIN_POLICY_BINDING'}
    if($Layout-ceq'framework-maintenance-sibling'){
        $overlay=Get-AiwMaintenanceOverlay $FrameworkWorkspace;$overlayRaw=Read-StrictUtf8NoBom ([string]$overlay.ProcessPolicyPath);$overlayRaw=$overlayRaw.Replace('{{PROCESS_CONTRACT_VERSION_JSON}}',((Get-ProcessCarrierContractVersion $TargetVersion $script:ActiveAdoptionProfile)|ConvertTo-Json -Compress)).Replace('{{PROJECT_ID_JSON}}',($ProjectId|ConvertTo-Json -Compress)).Replace('{{SELECTED_RULE_PACK_BYTES}}',[string]$policy.selectedRulePackBytes)
        try{$overlayPolicy=$overlayRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_OVERLAY_POLICY_JSON'}
        foreach($overlayRule in @($overlayPolicy.rules)){$matches=@($policy.rules|Where-Object{[string]$_.ruleId-ceq[string]$overlayRule.ruleId});if($matches.Count-ne1-or($matches[0]|ConvertTo-Json -Depth 100 -Compress)-cne($overlayRule|ConvertTo-Json -Depth 100 -Compress)){throw ('LOCAL_CANDIDATE_SAME_PIN_OVERLAY_POLICY_DRIFT|'+[string]$overlayRule.ruleId)}}
    }
    $runtimeIgnore=Get-RuntimeGitIgnoreProjection $RepositoryRoot ([string]$script:ActiveAdoptionProfile.projectControl.runtimeGitIgnoreRule);if([bool]$runtimeIgnore.Changed){throw 'LOCAL_CANDIDATE_SAME_PIN_RUNTIME_IGNORE_DRIFT'}
    $correctionsPath=Join-ChildPath (Split-Path -Parent $ProjectFile) 'corrections.json';$correctionsRaw=Read-StrictUtf8NoBom $correctionsPath;try{$corrections=$correctionsRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_CORRECTIONS_JSON'}
    Assert-MinimalExactFields $corrections $correctionsRaw @('schemaVersion','contractVersion','projectId','corrections') 'local-candidate same-pin corrections'
    $correctionsContractValid=((Test-MinimalJsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0')-or((Test-MinimalJsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq(Get-ProcessCarrierContractVersion $TargetVersion $script:ActiveAdoptionProfile))
    if(-not$correctionsContractValid-or[string]$corrections.projectId-cne$ProjectId-or-not($corrections.corrections-is[Array])){throw 'LOCAL_CANDIDATE_SAME_PIN_CORRECTIONS_BINDING'}
    Write-Output ('LOCAL_CANDIDATE_PROJECT_PROJECTION|version='+$TargetVersion+'|status=PASS')
}

function Get-LocalCandidateSamePinProjectionRefreshPlan([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectFile,[string]$BootstrapFile,[string]$Layout,[string]$ProjectId,$Migration){
    if($null-eq$Migration-or-not[bool]$Migration.SnapshotRebindRequired-or$null-eq$script:ActiveTargetSnapshot-or-not[bool]$script:ActiveTargetSnapshot.LocalCandidate-or-not(Test-AdoptionProfileVersion $TargetVersion)){throw 'LOCAL_CANDIDATE_SAME_PIN_REFRESH_NOT_REQUIRED'}
    $recoveryRelative='.ai-workspace/upgrade-recovery/'+$TargetVersion;$recoveryRoot=Join-ChildPath $RepositoryRoot $recoveryRelative;$statePath=Join-Path $recoveryRoot 'state.json'
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'LOCAL_CANDIDATE_SAME_PIN_RECOVERY_REQUIRED'}
    $stateRaw=Read-StrictUtf8NoBom $statePath;try{$state=$stateRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_RECOVERY_JSON'}
    $contract=Get-ActorBoundRecoveryContract $RepositoryRoot $recoveryRoot $state $stateRaw $ProjectId $TargetVersion $Migration
    if([string]$state.targetReleaseCanonical-ceq[string]$script:ActiveTargetSnapshot.Canonical-and[string]$state.targetReleaseManifestIdentity-ceq[string]$script:ActiveTargetSnapshot.ManifestIdentity){throw 'LOCAL_CANDIDATE_SAME_PIN_REBIND_NOT_REQUIRED'}
    $stateEntries=@{};foreach($entry in @($contract.ProjectionRecords)){if($stateEntries.ContainsKey([string]$entry.relative)){throw 'LOCAL_CANDIDATE_PROJECTION_OBJECT'};$stateEntries[[string]$entry.relative]=$entry}
    if(-not$stateEntries.ContainsKey('.ai-workspace/project.json')-or-not$stateEntries.ContainsKey($Migration.Relative)-or(Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'LOCAL_CANDIDATE_SAME_PIN_RECOVERY_CLOSURE'}
    foreach($entry in @($contract.ProjectionRecords|Where-Object{[string]$_.relative-cne$Migration.Relative})){if((Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$entry.relative)))-cne[string]$entry.identity){throw ('LOCAL_CANDIDATE_SAME_PIN_PROJECT_DRIFT|'+[string]$entry.relative)}}

    $projectRaw=Read-StrictUtf8NoBom $ProjectFile;try{$project=$projectRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_PROJECT_JSON'}
    if([string]$project.id-cne$ProjectId-or[string]$project.frameworkVersion-cne$TargetVersion-or[string]$project.controlPlaneLayout-cne$Layout-or(Get-MinimalFileIdentity $ProjectFile)-cne[string]$stateEntries['.ai-workspace/project.json'].identity){throw 'LOCAL_CANDIDATE_SAME_PIN_PROJECT_BINDING'}
    Assert-TargetProjectCapabilities $projectRaw 'LOCAL_CANDIDATE_SAME_PIN_PROJECT'
    $records=New-Object 'System.Collections.Generic.List[object]'
    $addProjection={param([string]$Relative,[string]$Path,$Content,[bool]$RequirePriorState)
        $oldIdentity=Get-OptionalIdentity $Path;$newIdentity=if($null-eq$Content){'ABSENT'}else{Get-MinimalBytesIdentity ($utf8NoBom.GetBytes([string]$Content))}
        $terminal=if($newIdentity-ceq'ABSENT'){'MISSING'}else{$newIdentity};if($oldIdentity-ceq$terminal){return}
        if($RequirePriorState){if(-not$stateEntries.ContainsKey($Relative)-or[string]$stateEntries[$Relative].identity-cne$oldIdentity){throw ('LOCAL_CANDIDATE_SAME_PIN_PROJECT_DRIFT|'+$Relative)}}
        $oldBytes=if($oldIdentity-ceq'MISSING'){$null}else{[Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))}
        $records.Add([pscustomobject]@{relative=$Relative;path=$Path;content=$Content;oldIdentity=$oldIdentity;newIdentity=$newIdentity;oldBytes=$oldBytes})
    }

    $templateRoot=if($Layout-ceq'framework-maintenance-sibling'){[string](Get-AiwMaintenanceOverlay $FrameworkWorkspace).Root}else{Join-ChildPath $TargetFramework 'project-starter'}
    $templatePath=Join-ChildPath $templateRoot 'BOOTSTRAP.md';$template=Read-StrictUtf8NoBom $templatePath;$currentBootstrap=Read-StrictUtf8NoBom $BootstrapFile
    $expectedBootstrap=Render-Bootstrap $template $project $TargetVersion;$currentBlock=Get-ManagedBootstrapBlock $currentBootstrap $BootstrapFile;$expectedBlock=Get-ManagedBootstrapBlock $expectedBootstrap $templatePath
    $targetBootstrap=Replace-ManagedBootstrapBlock $currentBootstrap $expectedBlock.Text $currentBlock;$targetBootstrap=Merge-CorrectionBootstrapBlock $targetBootstrap $expectedBootstrap $templatePath
    & $addProjection '.ai-workspace/BOOTSTRAP.md' $BootstrapFile $targetBootstrap $true

    $policyPath=Join-ChildPath (Split-Path -Parent $ProjectFile) 'process-policy.json';$policyRaw=Read-StrictUtf8NoBom $policyPath;try{$policy=$policyRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_POLICY_JSON'}
    $policyFields=@($policy.PSObject.Properties.Name);$targetContract=Get-ProcessCarrierContractVersion $TargetVersion $script:ActiveAdoptionProfile;$sourceContract=Get-ProcessCarrierContractVersion ([string]$state.fromVersion)
    if($policyFields.Count-eq4-and@(@('schemaVersion','contractVersion','projectId','rules')|Where-Object{$_-cnotin$policyFields}).Count-eq0){if(-not(Test-MinimalJsonInteger $policy.schemaVersion)-or[int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne$sourceContract-or[string]$policy.projectId-cne$ProjectId-or-not($policy.rules-is[Array])){throw 'LOCAL_CANDIDATE_SAME_PIN_POLICY_BINDING'};$policyBudget=$SelectedRulePackBytes}
    elseif($policyFields.Count-eq5-and@(@('schemaVersion','contractVersion','projectId','selectedRulePackBytes','rules')|Where-Object{$_-cnotin$policyFields}).Count-eq0){if(-not(Test-MinimalJsonInteger $policy.schemaVersion)-or[int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne$targetContract-or[string]$policy.projectId-cne$ProjectId-or-not(Test-MinimalJsonInteger $policy.selectedRulePackBytes)-or[int]$policy.selectedRulePackBytes-lt1-or[int]$policy.selectedRulePackBytes-gt[int]$script:ActiveAdoptionProfile.processBudget.absoluteSelectedRulePackBytes-or-not($policy.rules-is[Array])){throw 'LOCAL_CANDIDATE_SAME_PIN_POLICY_BINDING'};$policyBudget=[int]$policy.selectedRulePackBytes}
    else{throw 'LOCAL_CANDIDATE_SAME_PIN_POLICY_FIELDS'}
    $targetPolicyObject=[ordered]@{schemaVersion=1;contractVersion=$targetContract;projectId=$ProjectId;selectedRulePackBytes=$policyBudget;rules=@($policy.rules)}
    if($Layout-ceq'framework-maintenance-sibling'){$overlay=Get-AiwMaintenanceOverlay $FrameworkWorkspace;$overlayRaw=Read-StrictUtf8NoBom ([string]$overlay.ProcessPolicyPath);$overlayRaw=$overlayRaw.Replace('{{PROCESS_CONTRACT_VERSION_JSON}}',($targetContract|ConvertTo-Json -Compress)).Replace('{{PROJECT_ID_JSON}}',($ProjectId|ConvertTo-Json -Compress)).Replace('{{SELECTED_RULE_PACK_BYTES}}',[string]$policyBudget);try{$overlayPolicy=$overlayRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_OVERLAY_POLICY_JSON'};foreach($overlayRule in @($overlayPolicy.rules)){$same=@($targetPolicyObject.rules|Where-Object{[string]$_.ruleId-ceq[string]$overlayRule.ruleId});if($same.Count-gt1-or($same.Count-eq1-and($same[0]|ConvertTo-Json -Depth 100 -Compress)-cne($overlayRule|ConvertTo-Json -Depth 100 -Compress))){throw ('LOCAL_CANDIDATE_SAME_PIN_OVERLAY_POLICY_DRIFT|'+[string]$overlayRule.ruleId)};if($same.Count-eq0){$targetPolicyObject.rules=@($targetPolicyObject.rules)+@($overlayRule)}}}
    $targetPolicy=Normalize-Text ($targetPolicyObject|ConvertTo-Json -Depth 100);& $addProjection '.ai-workspace/process-policy.json' $policyPath $targetPolicy ([bool]$stateEntries.ContainsKey('.ai-workspace/process-policy.json'))

    $correctionsPath=Join-ChildPath (Split-Path -Parent $ProjectFile) 'corrections.json';$correctionsRaw=Read-StrictUtf8NoBom $correctionsPath;try{$corrections=$correctionsRaw|ConvertFrom-Json}catch{throw 'LOCAL_CANDIDATE_SAME_PIN_CORRECTIONS_JSON'}
    Assert-MinimalExactFields $corrections $correctionsRaw @('schemaVersion','contractVersion','projectId','corrections') 'local-candidate same-pin corrections'
    $correctionsContractValid=((Test-MinimalJsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0')-or((Test-MinimalJsonInteger $corrections.schemaVersion)-and[int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq$targetContract)
    if(-not$correctionsContractValid-or[string]$corrections.projectId-cne$ProjectId-or-not($corrections.corrections-is[Array])){throw 'LOCAL_CANDIDATE_SAME_PIN_CORRECTIONS_BINDING'}

    $agentsPath=Join-Path $RepositoryRoot 'AGENTS.md';$agentsRaw=Read-StrictUtf8NoBom $agentsPath;$targetAgentsBlock=(Read-StrictUtf8NoBom (Join-ChildPath $templateRoot 'AGENTS.md')).TrimEnd("`n");$begin='<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->';$end='<!-- AI-WORKSPACE-FRAMEWORK:END -->';$start=$agentsRaw.IndexOf($begin,[StringComparison]::Ordinal);$finish=$agentsRaw.IndexOf($end,[StringComparison]::Ordinal)
    if($start-lt0-or$finish-lt$start-or[regex]::Matches($agentsRaw,[regex]::Escape($begin)).Count-ne1-or[regex]::Matches($agentsRaw,[regex]::Escape($end)).Count-ne1){throw 'AGENTS_MANAGED_MARKERS_MALFORMED'};$finish+=$end.Length;$targetAgents=Normalize-Text ($agentsRaw.Substring(0,$start)+$targetAgentsBlock+$agentsRaw.Substring($finish));& $addProjection 'AGENTS.md' $agentsPath $targetAgents $true
    $skillRelative='.agents/skills/ai-workspace-router/SKILL.md';$skillPath=Join-ChildPath $RepositoryRoot $skillRelative;if(Test-Path -LiteralPath $skillPath -PathType Leaf){& $addProjection $skillRelative $skillPath $null $true}
    $gitIgnore=Get-RuntimeGitIgnoreProjection $RepositoryRoot ([string]$script:ActiveAdoptionProfile.projectControl.runtimeGitIgnoreRule);if([bool]$gitIgnore.Changed){& $addProjection '.gitignore' ([string]$gitIgnore.Path) ([string]$gitIgnore.Content) ([bool]$stateEntries.ContainsKey('.gitignore'))}

    $projectedPreflight=$null
    if($records.Count-gt0){$controllerPath=Join-ChildPath (Split-Path -Parent $ProjectFile) 'controller.json';$script:CurrentPinBudgetBridge=Get-TargetProjectedProcessPreflight $RepositoryRoot $FrameworkWorkspace $TargetVersion $ProjectId $Migration $projectRaw $targetBootstrap $correctionsRaw $targetPolicy $controllerPath;$projectedPreflight=$script:CurrentPinBudgetBridge}

    $projectionObjects=New-Object 'System.Collections.Generic.List[object]';$refreshed=@{};foreach($record in $records){$refreshed[[string]$record.relative]=$record}
    foreach($entry in @($contract.ProjectionRecords|Where-Object{[string]$_.relative-cne$Migration.Relative})){
        $relative=[string]$entry.relative
        if($refreshed.ContainsKey($relative)){$record=$refreshed[$relative];$projectionObjects.Add([ordered]@{relative=$relative;identity=$(if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity})});$refreshed.Remove($relative)}
        else{$projectionObjects.Add([ordered]@{relative=$relative;identity=[string]$entry.identity})}
    }
    foreach($record in $records){if($refreshed.ContainsKey([string]$record.relative)){$projectionObjects.Add([ordered]@{relative=[string]$record.relative;identity=$(if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity})});$refreshed.Remove([string]$record.relative)}}
    $projectionObjects.Add([ordered]@{relative=$Migration.Relative;identity=$Migration.OldIdentity})
    $originalObjects=@($contract.Records|ForEach-Object{[ordered]@{relative=[string]$_.relative;oldIdentity=[string]$_.oldIdentity;newIdentity=[string]$_.newIdentity}})
    $newState=[ordered]@{schemaVersion=3;projectId=$ProjectId;fromVersion=[string]$state.fromVersion;toVersion=$TargetVersion;targetReleaseCanonical=[string]$script:ActiveTargetSnapshot.Canonical;targetReleaseManifestIdentity=[string]$script:ActiveTargetSnapshot.ManifestIdentity;actor=$Migration.Actor;taskId=$Migration.TaskId;taskOwner=$Migration.Owner;taskRelative=$Migration.Relative;authorizationIdentity=[string]$state.authorizationIdentity;objects=$originalObjects;projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=[object[]]$projectionObjects.ToArray()}
    $stateText=Normalize-Text ($newState|ConvertTo-Json -Depth 30)
    $statePreimage=Get-MinimalFileIdentity $statePath
    $statePostimage=Get-MinimalBytesIdentity ($utf8NoBom.GetBytes($stateText))
    $exactPaths=@($records|ForEach-Object{[string]$_.relative})+@($recoveryRelative+'/state.json')
    $preimages=@($records|ForEach-Object{[pscustomobject]@{path=[string]$_.relative;identity=$(if([string]$_.oldIdentity-ceq'MISSING'){'NEW'}else{[string]$_.oldIdentity})}})+@([pscustomobject]@{path=$recoveryRelative+'/state.json';identity=$statePreimage})
    $postimages=@($records|ForEach-Object{[pscustomobject]@{path=[string]$_.relative;identity=[string]$_.newIdentity}})+@([pscustomobject]@{path=$recoveryRelative+'/state.json';identity=$statePostimage})
    return [pscustomobject]@{State=$newState;StateText=$stateText;StatePath=$statePath;StateRelative=$recoveryRelative+'/state.json';StatePreimage=$statePreimage;StatePostimage=$statePostimage;StateOldBytes=[IO.File]::ReadAllBytes($statePath);Records=[object[]]$records.ToArray();ExactPaths=$exactPaths;Preimages=$preimages;Postimages=$postimages;ProjectedPreflight=$projectedPreflight}
}

function Set-LocalCandidateProjectionRecord($Record,[bool]$UseOld){
    $expected=if($UseOld){[string]$Record.oldIdentity}else{[string]$Record.newIdentity};$path=[string]$Record.path
    if(($UseOld-and$expected-ceq'MISSING')-or(-not$UseOld-and$expected-ceq'ABSENT')){if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)};return}
    $directory=Split-Path -Parent $path;New-Item -ItemType Directory -Path $directory -Force|Out-Null;$temp=Join-Path $directory ('.aiw-projection-'+[guid]::NewGuid().ToString('N'))
    try{if($UseOld){[IO.File]::WriteAllBytes($temp,[Convert]::FromBase64String([string]$Record.oldBytes))}else{Write-ProjectedText $temp ([string]$Record.content)};if((Get-MinimalFileIdentity $temp)-cne$expected){throw ('LOCAL_CANDIDATE_SAME_PIN_PROJECTED_BYTES|'+[string]$Record.relative)};[IO.File]::Move($temp,$path,$true)}finally{if(Test-Path -LiteralPath $temp -PathType Leaf){[IO.File]::Delete($temp)}}
}

function Invoke-LocalCandidateSamePinProjectionRefresh([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectFile,$Migration,$Plan,[bool]$ApplyChange){
    if($null-ne$Plan.ProjectedPreflight){$preflight=$Plan.ProjectedPreflight;Write-Output ('TARGET_PROJECTED_PROCESS_PREFLIGHT|to='+$TargetVersion+'|resolver='+$preflight.ResolverReason+'|capabilities='+[string]::Join(',',@($preflight.Capabilities))+'|budget='+$preflight.BudgetMode+'|requirements='+$preflight.SelectedRequirementCount+'|bytes='+$preflight.SelectedPackBytes+'|pack='+$preflight.SelectedPackIdentity+'|source='+$preflight.SourceCompositionIdentity)}
    Write-Output ('UPGRADE_TARGET_MODE|lifecycle='+[string]$script:ActiveTargetSnapshot.Lifecycle+'|localCandidate=True');Write-Output ('UPGRADE_TARGET_RELEASE|canonical='+[string]$Plan.State.targetReleaseCanonical+'|manifest='+[string]$Plan.State.targetReleaseManifestIdentity);foreach($entry in $Plan.Preimages){Write-Output ('UPGRADE_PREIMAGE|'+[string]$entry.path+'='+[string]$entry.identity)};foreach($entry in $Plan.Postimages){Write-Output ('UPGRADE_POSTIMAGE|'+[string]$entry.path+'='+[string]$entry.identity)};Write-Output ('UPGRADE_WRITESET|'+[string]::Join('|',@($Plan.ExactPaths)))
    if(-not$ApplyChange){Write-Output ('WHAT_IF|from='+$TargetVersion+'|to='+$TargetVersion+'|objects='+($Plan.Records.Count+1)+'|transaction=local-candidate-managed-projection-refresh');return}
    Assert-ActorBoundUpgrade115Authorization $RepositoryRoot $TargetFramework $ProjectFile $Migration $Plan
    foreach($record in $Plan.Records){if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.oldIdentity){throw ('LOCAL_CANDIDATE_SAME_PIN_PREFLIGHT_DRIFT|'+[string]$record.relative)}};if((Get-MinimalFileIdentity $Plan.StatePath)-cne$Plan.StatePreimage-or(Get-MinimalFileIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'LOCAL_CANDIDATE_SAME_PIN_PREFLIGHT_DRIFT'}
    $applied=New-Object 'System.Collections.Generic.List[object]';$stateApplied=$false
    try{
        foreach($record in $Plan.Records){Set-LocalCandidateProjectionRecord $record $false;$terminal=if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity};if((Get-OptionalIdentity ([string]$record.path))-cne$terminal){throw ('LOCAL_CANDIDATE_SAME_PIN_POSTIMAGE_DRIFT|'+[string]$record.relative)};$applied.Add($record)}
        $stateRecord=[pscustomobject]@{relative=$Plan.StateRelative;path=$Plan.StatePath;content=$Plan.StateText;oldIdentity=$Plan.StatePreimage;newIdentity=$Plan.StatePostimage;oldBytes=[Convert]::ToBase64String([byte[]]$Plan.StateOldBytes)};Set-LocalCandidateProjectionRecord $stateRecord $false;$stateApplied=$true
        if((Get-MinimalFileIdentity $Plan.StatePath)-cne$Plan.StatePostimage-or(Get-MinimalFileIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'LOCAL_CANDIDATE_SAME_PIN_FINAL_DRIFT'}
        $controlRoot=Split-Path -Parent $ProjectFile;$correctionsPath=Join-ChildPath $controlRoot 'corrections.json';$policyPath=Join-ChildPath $controlRoot 'process-policy.json';$bootstrapPath=Join-ChildPath $controlRoot 'BOOTSTRAP.md';$correctionChecker=Join-ChildPath $TargetFramework 'scripts/check-project-corrections.ps1'
        $correctionResult=Invoke-CorrectionEvaluationProjected $correctionChecker $FrameworkWorkspace $TargetVersion (Read-StrictUtf8NoBom $ProjectFile) (Read-StrictUtf8NoBom $bootstrapPath) $correctionsPath $policyPath -TargetProcessPolicy (Read-StrictUtf8NoBom $policyPath) -TargetCorrections (Read-StrictUtf8NoBom $correctionsPath)
        if($null-ne$correctionResult-and[string]$correctionResult.status-ceq'CONFLICT'){throw 'LOCAL_CANDIDATE_SAME_PIN_CORRECTIONS_CONFLICT'}
    }catch{
        $cause=[string]$_.Exception.Message
        if($stateApplied){$stateRollback=[pscustomobject]@{relative=$Plan.StateRelative;path=$Plan.StatePath;content=$Plan.StateText;oldIdentity=$Plan.StatePreimage;newIdentity=$Plan.StatePostimage;oldBytes=[Convert]::ToBase64String([byte[]]$Plan.StateOldBytes)};Set-LocalCandidateProjectionRecord $stateRollback $true}
        for($i=$applied.Count-1;$i-ge0;$i--){Set-LocalCandidateProjectionRecord $applied[$i] $true}
        $rollbackOk=(Get-MinimalFileIdentity $Plan.StatePath)-ceq$Plan.StatePreimage;foreach($record in $Plan.Records){if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.oldIdentity){$rollbackOk=$false}}
        if(-not$rollbackOk){throw ('LOCAL_CANDIDATE_SAME_PIN_REFRESH_ROLLBACK_UNPROVEN|cause='+$cause)};throw ('LOCAL_CANDIDATE_SAME_PIN_REFRESH_FAILED_ROLLED_BACK|'+$cause)
    }
    Write-Output ('LOCAL_CANDIDATE_PROJECT_PROJECTION_REFRESHED|version='+$TargetVersion+'|objects='+($Plan.Records.Count+1)+'|state='+$Plan.StatePostimage+'|next=FRESH_RECOVERY')
}

function Get-LocalCandidateSamePinRebindPlan([string]$RepositoryRoot,[string]$TargetVersion,[string]$ProjectId,$Migration){
    if($null-eq$Migration-or-not[bool]$Migration.SnapshotRebindRequired-or$null-eq$script:ActiveTargetSnapshot-or-not[bool]$script:ActiveTargetSnapshot.LocalCandidate){throw 'LOCAL_CANDIDATE_SAME_PIN_REBIND_NOT_REQUIRED'}
    $recoveryRelative='.ai-workspace/upgrade-recovery/'+$TargetVersion;$recoveryRoot=Join-ChildPath $RepositoryRoot $recoveryRelative;$statePath=Join-Path $recoveryRoot 'state.json'
    if(-not(Test-Path -LiteralPath $recoveryRoot -PathType Container)){throw 'LOCAL_CANDIDATE_SAME_PIN_RECOVERY_REQUIRED'};Assert-NoReparseTree $recoveryRoot
    $stateRaw=Read-StrictUtf8NoBom $statePath;try{$state=$stateRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_RECOVERY_JSON'}
    $contract=Get-ActorBoundRecoveryContract $RepositoryRoot $recoveryRoot $state $stateRaw $ProjectId $TargetVersion $Migration
    if([string]$state.targetReleaseCanonical-ceq[string]$script:ActiveTargetSnapshot.Canonical-and[string]$state.targetReleaseManifestIdentity-ceq[string]$script:ActiveTargetSnapshot.ManifestIdentity){throw 'LOCAL_CANDIDATE_SAME_PIN_REBIND_NOT_REQUIRED'}
    $projectionRecords=New-Object 'System.Collections.Generic.List[object]';$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in @($contract.ProjectionRecords)){
        $null=$seen.Add([string]$entry.relative);$live=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$entry.relative))
        if([string]$entry.relative-cne$Migration.Relative-and$live-cne[string]$entry.identity){throw ('LOCAL_CANDIDATE_SAME_PIN_PROJECT_DRIFT|'+[string]$entry.relative)}
        $projectionRecords.Add([ordered]@{relative=[string]$entry.relative;identity=[string]$entry.identity})
    }
    if(-not$seen.Contains('.ai-workspace/project.json')-or-not$seen.Contains($Migration.Relative)-or[string]@($contract.ProjectionRecords)[-1].relative-cne$Migration.Relative-or(Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'LOCAL_CANDIDATE_SAME_PIN_RECOVERY_CLOSURE'}
    $originalObjects=@($contract.Records|ForEach-Object{[ordered]@{relative=[string]$_.relative;oldIdentity=[string]$_.oldIdentity;newIdentity=[string]$_.newIdentity}})
    if([int]$contract.SchemaVersion-eq3){$newState=[ordered]@{schemaVersion=3;projectId=[string]$state.projectId;fromVersion=[string]$state.fromVersion;toVersion=[string]$state.toVersion;targetReleaseCanonical=[string]$script:ActiveTargetSnapshot.Canonical;targetReleaseManifestIdentity=[string]$script:ActiveTargetSnapshot.ManifestIdentity;actor=[string]$state.actor;taskId=[string]$state.taskId;taskOwner=[string]$state.taskOwner;taskRelative=[string]$state.taskRelative;authorizationIdentity=[string]$state.authorizationIdentity;objects=$originalObjects;projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=[object[]]$projectionRecords.ToArray()}}
    else{$newState=[ordered]@{schemaVersion=2;projectId=[string]$state.projectId;fromVersion=[string]$state.fromVersion;toVersion=[string]$state.toVersion;targetReleaseCanonical=[string]$script:ActiveTargetSnapshot.Canonical;targetReleaseManifestIdentity=[string]$script:ActiveTargetSnapshot.ManifestIdentity;actor=[string]$state.actor;taskId=[string]$state.taskId;taskOwner=[string]$state.taskOwner;taskRelative=[string]$state.taskRelative;authorizationIdentity=[string]$state.authorizationIdentity;objects=$originalObjects}}
    $stateText=Normalize-Text ($newState|ConvertTo-Json -Depth 30);$stateRelative=$recoveryRelative+'/state.json';$preimage=Get-MinimalFileIdentity $statePath;$postimage=Get-MinimalBytesIdentity ($utf8NoBom.GetBytes($stateText))
    if($preimage-ceq$postimage){throw 'LOCAL_CANDIDATE_SAME_PIN_STATE_NO_CHANGE'}
    return [pscustomobject]@{State=$newState;StateText=$stateText;StatePath=$statePath;StateRelative=$stateRelative;Preimage=$preimage;PreimageRaw=$stateRaw;Postimage=$postimage;ExactPaths=@($stateRelative);Preimages=@([pscustomobject]@{path=$stateRelative;identity=$preimage});Postimages=@([pscustomobject]@{path=$stateRelative;identity=$postimage})}
}

function Invoke-LocalCandidateSamePinRebind([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectFile,$Migration,[bool]$ApplyChange){
    $plan=Get-LocalCandidateSamePinRebindPlan $RepositoryRoot $TargetVersion ([string](Read-StrictUtf8NoBom $ProjectFile|ConvertFrom-Json).id) $Migration
    Write-Output ('UPGRADE_TARGET_MODE|lifecycle='+[string]$script:ActiveTargetSnapshot.Lifecycle+'|localCandidate=True')
    Write-Output ('UPGRADE_TARGET_RELEASE|canonical='+[string]$plan.State.targetReleaseCanonical+'|manifest='+[string]$plan.State.targetReleaseManifestIdentity)
    Write-Output ('UPGRADE_PREIMAGE|'+$plan.StateRelative+'='+$plan.Preimage);Write-Output ('UPGRADE_POSTIMAGE|'+$plan.StateRelative+'='+$plan.Postimage);Write-Output ('UPGRADE_WRITESET|'+$plan.StateRelative)
    if(-not$ApplyChange){Write-Output ('WHAT_IF|from='+$TargetVersion+'|to='+$TargetVersion+'|objects=1|transaction=local-candidate-snapshot-rebind');return}
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne$ExpectedAuthorizationPackageIdentity){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DRIFT'}
    $authorizationRaw=Read-StrictUtf8NoBom $AuthorizationPackagePath;try{$authorization=$authorizationRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_JSON'}
    $script:CurrentPinBudgetBridge=[pscustomobject]@{UserDecision=[string]$authorization.userConfirmation}
    Assert-ActorBoundUpgrade115Authorization $RepositoryRoot $TargetFramework $ProjectFile $Migration $plan
    if((Get-MinimalFileIdentity $plan.StatePath)-cne$plan.Preimage-or(Get-MinimalFileIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'LOCAL_CANDIDATE_SAME_PIN_PREFLIGHT_DRIFT'}
    $tempPath=Join-Path (Split-Path -Parent $plan.StatePath) ('.state-rebind-'+[guid]::NewGuid().ToString('N')+'.json')
    try{Write-Utf8NoBom $tempPath $plan.StateText;if((Get-MinimalFileIdentity $tempPath)-cne$plan.Postimage-or(Get-MinimalFileIdentity $plan.StatePath)-cne$plan.Preimage){throw 'LOCAL_CANDIDATE_SAME_PIN_FINAL_DRIFT'};[IO.File]::Move($tempPath,$plan.StatePath,$true)}finally{if(Test-Path -LiteralPath $tempPath -PathType Leaf){[IO.File]::Delete($tempPath)}}
    if((Get-MinimalFileIdentity $plan.StatePath)-cne$plan.Postimage){throw 'LOCAL_CANDIDATE_SAME_PIN_POSTIMAGE_DRIFT'}
    try{
        $controlRoot=Split-Path -Parent $ProjectFile;$correctionsPath=Join-ChildPath $controlRoot 'corrections.json';$policyPath=Join-ChildPath $controlRoot 'process-policy.json';$bootstrapPath=Join-ChildPath $controlRoot 'BOOTSTRAP.md';$correctionChecker=Join-ChildPath $TargetFramework 'scripts/check-project-corrections.ps1'
        $correctionResult=Invoke-CorrectionEvaluationProjected $correctionChecker $FrameworkWorkspace $TargetVersion (Read-StrictUtf8NoBom $ProjectFile) (Read-StrictUtf8NoBom $bootstrapPath) $correctionsPath $policyPath -TargetProcessPolicy (Read-StrictUtf8NoBom $policyPath) -TargetCorrections (Read-StrictUtf8NoBom $correctionsPath)
        if($null-ne$correctionResult-and[string]$correctionResult.status-ceq'CONFLICT'){throw 'LOCAL_CANDIDATE_SAME_PIN_CORRECTIONS_CONFLICT'}
    }catch{
        $cause=[string]$_.Exception.Message;$rollbackPath=Join-Path (Split-Path -Parent $plan.StatePath) ('.state-rebind-rollback-'+[guid]::NewGuid().ToString('N')+'.json')
        try{if((Get-MinimalFileIdentity $plan.StatePath)-cne$plan.Postimage){throw 'LOCAL_CANDIDATE_SAME_PIN_ROLLBACK_START_DRIFT'};Write-Utf8NoBom $rollbackPath $plan.PreimageRaw;if((Get-MinimalFileIdentity $rollbackPath)-cne$plan.Preimage){throw 'LOCAL_CANDIDATE_SAME_PIN_ROLLBACK_BYTES'};[IO.File]::Move($rollbackPath,$plan.StatePath,$true)}finally{if(Test-Path -LiteralPath $rollbackPath -PathType Leaf){[IO.File]::Delete($rollbackPath)}}
        if((Get-MinimalFileIdentity $plan.StatePath)-cne$plan.Preimage){throw ('LOCAL_CANDIDATE_SAME_PIN_POSTCHECK_ROLLBACK_UNPROVEN|cause='+$cause)}
        throw ('LOCAL_CANDIDATE_SAME_PIN_POSTCHECK_FAILED_ROLLED_BACK|'+$cause)
    }
    Write-Output ('LOCAL_CANDIDATE_SNAPSHOT_REBOUND|version='+$TargetVersion+'|state='+$plan.Postimage+'|project-writes=ZERO|next=FRESH_RECOVERY')
}

function Assert-ActorBoundUpgradeAuthorization([string]$RepositoryRoot,[string]$SourceFramework,[string]$ProjectFile,[string]$ControllerFile,$Migration,[string[]]$WritePaths){
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or[string]::IsNullOrWhiteSpace($ExpectedAuthorizationPackageIdentity)){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_REQUIRED'}
    if($ExpectedAuthorizationPackageIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne$ExpectedAuthorizationPackageIdentity){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DRIFT'}
    $raw=Read-StrictUtf8NoBom $AuthorizationPackagePath
    Assert-StrictJsonMemberSet $raw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DUPLICATE_MEMBER'
    try{$package=$raw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_JSON'}
    if([string]$package.issuerRole-cne'PROJECT_CONTROLLER'-or[string]$package.grantee-cne$Migration.Actor-or[string]$package.taskId-cne$Migration.TaskId-or[string]$package.owner-cne$Migration.Owner){throw 'ACTOR_BOUND_UPGRADE_AUTHORITY_BINDING'}
    $declared=@($package.exactPaths|ForEach-Object{[string]$_});$expected=@($WritePaths)
    [Array]::Sort($declared,[StringComparer]::Ordinal);[Array]::Sort($expected,[StringComparer]::Ordinal)
    if($declared.Count-ne$expected.Count-or[string]::Join("`n",$declared)-cne[string]::Join("`n",$expected)){throw 'ACTOR_BOUND_UPGRADE_PATHSET_DRIFT'}
    $observed=@();foreach($relative in $WritePaths){$identity=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot $relative);if($identity-ceq'MISSING'){$identity='NEW'};$observed+=($relative+'='+$identity)}
    $checker=Join-ChildPath $SourceFramework 'scripts/check-authorization.ps1'
    $args=@{PackagePath=$AuthorizationPackagePath;ObservedActor=$Migration.Actor;ObservedTaskId=$Migration.TaskId;ObservedOwner=$Migration.Owner;ObservedAction=@('CONTROL_WRITE');ObservedPath=$WritePaths;ObservedIdentity=$observed;ControllerControlPath='.ai-workspace/controller.json';ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Get-MinimalFileIdentity $ProjectFile)}
    if($null-ne$package.PSObject.Properties['repositoryId']){$args.ObservedRepositoryId=[string]$package.repositoryId}
    $previousCurrentDirectory=[Environment]::CurrentDirectory
    Push-Location -LiteralPath $RepositoryRoot
    try{[Environment]::CurrentDirectory=$RepositoryRoot;$result=@(& $checker @args 2>&1|ForEach-Object{[string]$_});$checkerExit=$LASTEXITCODE}finally{[Environment]::CurrentDirectory=$previousCurrentDirectory;Pop-Location}
    if($checkerExit-ne0-or@($result|Where-Object{$_-clike'PASS|*'}).Count-ne1){throw ('ACTOR_BOUND_UPGRADE_AUTHORIZATION_REJECTED|'+($result-join';'))}
}

function Assert-ActorBoundUpgradeLegacyMaterial([string]$Root,[object[]]$StateObjects,[string]$StateText,[string]$Prefix){
    Assert-NoReparseTree $Root
    $files=New-Object 'System.Collections.Generic.List[string]';$files.Add('state.json')
    foreach($item in $StateObjects){
        if([string]$item.oldIdentity-cne'MISSING'){$files.Add('old/'+[string]$item.relative)}
        $files.Add('new/'+[string]$item.relative)
    }
    Assert-ExactTransactionTree $Root $files.ToArray() ([string[]]@()) ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_TREE')
    foreach($item in $StateObjects){
        $old=Join-ChildPath (Join-Path $Root 'old') ([string]$item.relative);$new=Join-ChildPath (Join-Path $Root 'new') ([string]$item.relative)
        if([string]$item.oldIdentity-cne'MISSING'-and(Get-OptionalIdentity $old)-cne[string]$item.oldIdentity){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_OLD_DRIFT|'+[string]$item.relative)}
        if([string]$item.oldIdentity-ceq'MISSING'-and(Test-Path -LiteralPath $old)){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_UNEXPECTED_OLD|'+[string]$item.relative)}
        if((Get-OptionalIdentity $new)-cne[string]$item.newIdentity){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_NEW_DRIFT|'+[string]$item.relative)}
    }
    if((Get-MinimalFileIdentity (Join-Path $Root 'state.json'))-cne(Get-MinimalBytesIdentity ($utf8NoBom.GetBytes($StateText)))){throw ('ACTOR_BOUND_UPGRADE_'+$Prefix+'_STATE_DRIFT')}
}

function Invoke-ActorBoundUpgrade([string]$RepositoryRoot,[string]$SourceFramework,[string]$TargetFramework,[string]$FromVersion,[string]$TargetVersion,[string]$ProjectId,[string]$ProjectFile,[string]$ControllerFile,$Migration,[object[]]$Objects,[bool]$ApplyChange){
    if($TargetVersion-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion $TargetVersion)){Invoke-ActorBoundUpgrade115 $RepositoryRoot $TargetFramework $FromVersion $TargetVersion $ProjectId $ProjectFile $Migration $Objects $ApplyChange;return}
    if(@($Objects|Where-Object{Test-ManagedRouterRelative ([string]$_.relative)}).Count-gt0){Assert-ManagedRouterDestinations $RepositoryRoot}
    $preparationRelative='.framework-actor-bound-upgrade-preparation-'+$TargetVersion;$preparationRoot=Join-ChildPath $RepositoryRoot $preparationRelative
    $recoveryRelative='.framework-actor-bound-upgrade-recovery-'+$TargetVersion;$recoveryRoot=Join-ChildPath $RepositoryRoot $recoveryRelative
    $objects=@($Objects)+@([pscustomobject]@{relative=$Migration.Relative;path=$Migration.Path;content=$Migration.Content})
    $stateObjects=@();$writePaths=New-Object 'System.Collections.Generic.List[string]'
    foreach($object in $objects){
        $oldIdentity=Get-OptionalIdentity $object.path;$newIdentity=Get-MinimalBytesIdentity ($utf8NoBom.GetBytes([string]$object.content));$stateObjects+=[ordered]@{relative=$object.relative;oldIdentity=$oldIdentity;newIdentity=$newIdentity}
        $writePaths.Add([string]$object.relative)
        if($oldIdentity-cne'MISSING'){$writePaths.Add($preparationRelative+'/old/'+[string]$object.relative);$writePaths.Add($recoveryRelative+'/old/'+[string]$object.relative)}
        $writePaths.Add($preparationRelative+'/new/'+[string]$object.relative);$writePaths.Add($recoveryRelative+'/new/'+[string]$object.relative)
    }
    $writePaths.Add($preparationRelative+'/state.json');$writePaths.Add($recoveryRelative+'/state.json');$writePaths.Add($Migration.AtomicRelative)
    $state=[ordered]@{schemaVersion=1;projectId=$ProjectId;fromVersion=$FromVersion;toVersion=$TargetVersion;actor=$Migration.Actor;taskId=$Migration.TaskId;taskOwner=$Migration.Owner;taskRelative=$Migration.Relative;authorizationIdentity=$ExpectedAuthorizationPackageIdentity;objects=$stateObjects}
    $stateText=Normalize-Text ($state|ConvertTo-Json -Depth 10)
    Write-Output ('UPGRADE_WRITESET|'+[string]::Join('|',$writePaths))
    foreach($relative in $writePaths){$identity=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot $relative);if($identity-ceq'MISSING'){$identity='NEW'};Write-Output ('UPGRADE_PREIMAGE|'+$relative+'='+$identity)}
    if(-not$ApplyChange){Write-Output ('WHAT_IF|from='+$FromVersion+'|to='+$TargetVersion+'|objects='+$objects.Count+'|transaction=actor-bound-forward-prepared');return}
    Assert-ActorBoundUpgradeAuthorization $RepositoryRoot $SourceFramework $ProjectFile $ControllerFile $Migration @($writePaths)
    if(Test-Path -LiteralPath $preparationRoot){throw 'ACTOR_BOUND_UPGRADE_PREPARATION_EXISTS'}
    if(Test-Path -LiteralPath $recoveryRoot){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_EXISTS'}
    try{
        foreach($item in $stateObjects){$object=@($objects|Where-Object{$_.relative-ceq[string]$item.relative})[0];if(Test-ManagedRouterRelative ([string]$item.relative)){Assert-ManagedRouterDestinations $RepositoryRoot};$old=Join-ChildPath (Join-Path $preparationRoot 'old') ([string]$item.relative);$new=Join-ChildPath (Join-Path $preparationRoot 'new') ([string]$item.relative);if([string]$item.oldIdentity-cne'MISSING'){New-Item -ItemType Directory -Path (Split-Path -Parent $old) -Force|Out-Null;[IO.File]::Copy($object.path,$old,$false)};New-Item -ItemType Directory -Path (Split-Path -Parent $new) -Force|Out-Null;Write-ProjectedText $new ([string]$object.content)}
        Write-Utf8NoBom (Join-Path $preparationRoot 'state.json') $stateText
        foreach($item in $stateObjects){if(Test-ManagedRouterRelative ([string]$item.relative)){Assert-ManagedRouterDestinations $RepositoryRoot};$live=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$item.relative));if($live-cne[string]$item.oldIdentity){throw ('OBJECT_DRIFT|'+[string]$item.relative)}}
        Assert-ActorBoundUpgradeLegacyMaterial $preparationRoot $stateObjects $stateText 'PREPARATION'
        [IO.Directory]::Move($preparationRoot,$recoveryRoot)
        Assert-ActorBoundUpgradeLegacyMaterial $recoveryRoot $stateObjects $stateText 'RECOVERY'
        $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage -ObservedActualPath @($Migration.ActualPaths) 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
        $atomic=Join-ChildPath $RepositoryRoot $Migration.AtomicRelative;New-Item -ItemType Directory -Path (Split-Path -Parent $atomic) -Force|Out-Null;[IO.File]::Copy($taskStage,$atomic,$false)
        foreach($item in @($stateObjects|Where-Object{[string]$_.relative-cne$Migration.Relative})){$managed=Test-ManagedRouterRelative ([string]$item.relative);if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};$livePath=Join-ChildPath $RepositoryRoot ([string]$item.relative);New-Item -ItemType Directory -Path (Split-Path -Parent $livePath) -Force|Out-Null;if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};Set-UpgradeFile (Join-ChildPath (Join-Path $recoveryRoot 'new') ([string]$item.relative)) $livePath ([string]$item.oldIdentity) ([string]$item.newIdentity)}
        if((Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'}
        [IO.File]::Move($atomic,$Migration.Path,$true)
        if((Get-OptionalIdentity $Migration.Path)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_POSTIMAGE_DRIFT'}
        Write-Output ('UPGRADED|objects='+$objects.Count+'|transaction=actor-bound-forward-prepared|recovery='+$recoveryRoot+'|writes-after-task=ZERO')
    }catch{throw "Actor-bound Framework upgrade stopped; exact preparation/recovery material is preserved. $($_.Exception.Message)"}
}

function Resume-ActorBoundUpgrade([string]$RepositoryRoot,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectId,[string]$ControllerFile,$Migration,[bool]$ApplyChange){
    $preparationRelative='.framework-actor-bound-upgrade-preparation-'+$TargetVersion
    $recoveryRelative='.framework-actor-bound-upgrade-recovery-'+$TargetVersion;$recoveryRoot=Join-ChildPath $RepositoryRoot $recoveryRelative;$statePath=Join-Path $recoveryRoot 'state.json'
    if(-not(Test-Path -LiteralPath $recoveryRoot -PathType Container)){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_NOT_DIRECTORY'};Assert-NoReparseTree $recoveryRoot
    $raw=Read-StrictUtf8NoBom $statePath;try{$state=$raw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_RECOVERY_JSON'}
    if(@($state.objects|Where-Object{Test-ManagedRouterRelative ([string]$_.relative)}).Count-gt0){Assert-ManagedRouterDestinations $RepositoryRoot}
    Assert-MinimalExactFields $state $raw @('schemaVersion','projectId','fromVersion','toVersion','actor','taskId','taskOwner','taskRelative','authorizationIdentity','objects') 'actor-bound upgrade recovery'
    if(-not(Test-MinimalJsonInteger $state.schemaVersion)-or[int]$state.schemaVersion-ne1-or[string]$state.projectId-cne$ProjectId-or[string]$state.toVersion-cne$TargetVersion-or[string]$state.actor-cne$Migration.Actor-or[string]$state.taskId-cne$Migration.TaskId-or[string]$state.taskOwner-cne$Migration.Owner-or[string]$state.taskRelative-cne$Migration.Relative-or[string]$state.authorizationIdentity-cne$ExpectedAuthorizationPackageIdentity-or-not($state.objects-is[Array])){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne[string]$state.authorizationIdentity){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DRIFT'}
    $packageRaw=Read-StrictUtf8NoBom $AuthorizationPackagePath;Assert-StrictJsonMemberSet $packageRaw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DUPLICATE_MEMBER';try{$package=$packageRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_JSON'}
    if([string]$package.issuerRole-cne'PROJECT_CONTROLLER'-or[string]$package.grantee-cne$Migration.Actor-or[string]$package.taskId-cne$Migration.TaskId-or[string]$package.owner-cne$Migration.Owner){throw 'ACTOR_BOUND_UPGRADE_AUTHORITY_BINDING'}
    $controllerRaw=Read-StrictUtf8NoBom $ControllerFile;try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_CONTROLLER_JSON'};Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    $controllerIdentity=Get-MinimalFileIdentity $ControllerFile
    if($null-eq$package.PSObject.Properties['issuerControllerId']-or$null-eq$package.PSObject.Properties['issuerControllerEpoch']-or$null-eq$package.PSObject.Properties['controllerControlIdentity']-or[string]$package.issuerControllerId-cne[string]$controller.controllerId-or-not(Test-MinimalJsonInteger $package.issuerControllerEpoch)-or[int64]$package.issuerControllerEpoch-ne[int64]$controller.controllerEpoch-or[string]$package.controllerControlIdentity-cne$controllerIdentity-or'CONTROLLER_EPOCH_CHANGE'-cnotin@($package.invalidatesOn)){throw 'ACTOR_BOUND_UPGRADE_CONTROLLER_AUTHORITY_DRIFT'}
    if(-not($package.exactPaths-is[Array])-or-not($package.objectIdentities-is[Array])){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_PATHSET'}
    $declaredPaths=@($package.exactPaths|ForEach-Object{[string]$_});$declaredSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($relative in $declaredPaths){$null=Join-ChildPath $RepositoryRoot $relative;if(-not$declaredSet.Add($relative)){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_PATHSET'}}
    $usesPreparedPathset=@($declaredPaths|Where-Object{$_.StartsWith($preparationRelative+'/',[StringComparison]::Ordinal)}).Count-gt0
    if($usesPreparedPathset-and(Test-Path -LiteralPath (Join-ChildPath $RepositoryRoot $preparationRelative))){throw 'ACTOR_BOUND_UPGRADE_PREPARATION_REAPPEARED'}
    $identityMap=@{}
    foreach($identityEntry in @($package.objectIdentities)){
        if(-not($identityEntry-is[pscustomobject])-or$null-eq$identityEntry.PSObject.Properties['path']-or$null-eq$identityEntry.PSObject.Properties['identity']){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_OBJECT_IDENTITIES'}
        $identityPath=[string]$identityEntry.path;$null=Join-ChildPath $RepositoryRoot $identityPath
        if($identityMap.ContainsKey($identityPath)){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_OBJECT_IDENTITIES'}
        $identityMap[$identityPath]=[string]$identityEntry.identity
    }
    if($identityMap.Count-ne$declaredSet.Count-or@($declaredSet|Where-Object{-not$identityMap.ContainsKey($_)}).Count-ne0){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_OBJECT_IDENTITIES'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$liveStates=@();$materialFiles=[Collections.Generic.List[string]]::new()
    $reconstructed=New-Object 'System.Collections.Generic.List[string]'
    foreach($entry in @($state.objects)){
        $entryRaw=$entry|ConvertTo-Json -Compress;Assert-MinimalExactFields $entry $entryRaw @('relative','oldIdentity','newIdentity') 'actor-bound upgrade object'
        if(-not($entry.relative-is[string])-or-not$seen.Add([string]$entry.relative)-or[string]$entry.oldIdentity-cne'MISSING'-and[string]$entry.oldIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$entry.newIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_OBJECT'}
        $null=Join-ChildPath $RepositoryRoot ([string]$entry.relative)
        $expectedOldIdentity=if([string]$entry.oldIdentity-ceq'MISSING'){'NEW'}else{[string]$entry.oldIdentity}
        if(-not$identityMap.ContainsKey([string]$entry.relative)-or[string]$identityMap[[string]$entry.relative]-cne$expectedOldIdentity){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_AUTHORIZATION_PREIMAGE_DRIFT'}
        $reconstructed.Add([string]$entry.relative);$reconstructed.Add($recoveryRelative+'/new/'+[string]$entry.relative)
        if($usesPreparedPathset){$reconstructed.Add($preparationRelative+'/new/'+[string]$entry.relative)}
        if([string]$entry.oldIdentity-cne'MISSING'){$reconstructed.Add($recoveryRelative+'/old/'+[string]$entry.relative);if($usesPreparedPathset){$reconstructed.Add($preparationRelative+'/old/'+[string]$entry.relative)}}
        foreach($kind in @('old','new')){$identity=[string]$entry.($kind+'Identity');$material=Join-ChildPath (Join-Path $recoveryRoot $kind) ([string]$entry.relative);if($identity-cne'MISSING'){if(-not(Test-Path -LiteralPath $material -PathType Leaf)-or(Get-MinimalFileIdentity $material)-cne$identity){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_MATERIAL'};$materialFiles.Add($kind+'/'+[string]$entry.relative)}elseif(Test-Path -LiteralPath $material){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_UNEXPECTED_MATERIAL'}}
        $live=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$entry.relative));if($live-cne[string]$entry.oldIdentity-and$live-cne[string]$entry.newIdentity){if([string]$entry.relative-ceq$Migration.Relative){throw 'ACTOR_ROUTE_TASK_DRIFT'};throw ('ACTOR_BOUND_UPGRADE_UNKNOWN_LIVE_BYTES|'+[string]$entry.relative)};$liveStates+=[pscustomobject]@{Entry=$entry;Live=$live}
    }
    Assert-ExactTransactionTree $recoveryRoot (@('state.json')+@($materialFiles)) ([string[]]@()) 'ACTOR_BOUND_UPGRADE_RECOVERY_TREE_CLOSURE'
    $reconstructed.Add($recoveryRelative+'/state.json');if($usesPreparedPathset){$reconstructed.Add($preparationRelative+'/state.json')};$reconstructed.Add($Migration.AtomicRelative)
    [string[]]$reconstructedSorted=@($reconstructed);[string[]]$declaredSorted=@($declaredPaths);[Array]::Sort($reconstructedSorted,[StringComparer]::Ordinal);[Array]::Sort($declaredSorted,[StringComparer]::Ordinal)
    if($reconstructedSorted.Count-ne$declaredSorted.Count-or[string]::Join("`n",$reconstructedSorted)-cne[string]::Join("`n",$declaredSorted)){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_AUTHORIZATION_PATHSET_DRIFT'}
    if(-not$seen.Contains($Migration.Relative)-or[string]@($state.objects)[-1].relative-cne$Migration.Relative){throw 'ACTOR_BOUND_UPGRADE_TASK_NOT_LAST'}
    $taskState=@($liveStates|Where-Object{[string]$_.Entry.relative-ceq$Migration.Relative})[0]
    if($taskState.Live-ceq[string]$taskState.Entry.newIdentity-and@($liveStates|Where-Object{$_.Live-cne[string]$_.Entry.newIdentity}).Count-ne0){throw 'ACTOR_BOUND_UPGRADE_TASK_ADVANCED_BEFORE_OBJECTS'}
    $writePaths=@($liveStates|Where-Object{$_.Live-cne[string]$_.Entry.newIdentity}|ForEach-Object{[string]$_.Entry.relative})
    if($taskState.Live-cne[string]$taskState.Entry.newIdentity){$writePaths+= $Migration.AtomicRelative}
    Write-Output ('UPGRADE_RECOVERY_WRITESET|'+[string]::Join('|',$writePaths))
    if(-not$ApplyChange){Write-Output ('RECOVERY_REQUIRED|from='+[string]$state.fromVersion+'|to='+$TargetVersion+'|remaining='+$writePaths.Count);return}
    if($writePaths.Count-eq0){Write-Output ('RECOVERY_COMPLETE|to='+$TargetVersion+'|writes=ZERO');return}
    $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage -ObservedActualPath @($Migration.ActualPaths) 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
    $atomic=Join-ChildPath $RepositoryRoot $Migration.AtomicRelative;if((Get-OptionalIdentity $atomic)-ceq'MISSING'){New-Item -ItemType Directory -Path (Split-Path -Parent $atomic) -Force|Out-Null;[IO.File]::Copy($taskStage,$atomic,$false)}elseif((Get-OptionalIdentity $atomic)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_ATOMIC_STAGE_DRIFT'}
    foreach($item in @($liveStates|Where-Object{[string]$_.Entry.relative-cne$Migration.Relative})){
        if($item.Live-ceq[string]$item.Entry.newIdentity){continue};$managed=Test-ManagedRouterRelative ([string]$item.Entry.relative);if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};$livePath=Join-ChildPath $RepositoryRoot ([string]$item.Entry.relative);New-Item -ItemType Directory -Path (Split-Path -Parent $livePath) -Force|Out-Null;if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};Set-UpgradeFile (Join-ChildPath (Join-Path $recoveryRoot 'new') ([string]$item.Entry.relative)) $livePath ([string]$item.Entry.oldIdentity) ([string]$item.Entry.newIdentity)
    }
    if((Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'};[IO.File]::Move($atomic,$Migration.Path,$true);if((Get-OptionalIdentity $Migration.Path)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_POSTIMAGE_DRIFT'}
    Write-Output ('RECOVERED_UPGRADE|to='+$TargetVersion+'|recovery='+$recoveryRoot+'|writes-after-task=ZERO')
}

function Get-ManagedAgentsTransition([string]$RepositoryRoot,[string]$SourceFramework,[string]$TargetFramework,[bool]$Install,$SourceAdoptionProfile=$null,[string]$Layout='repo-local',[string]$FrameworkWorkspace='',[string]$SourceVersion=''){
    Assert-ManagedRouterDestinations $RepositoryRoot
    $agentsPath=Join-Path $RepositoryRoot 'AGENTS.md';$skillPath=Join-Path $RepositoryRoot '.agents\skills\ai-workspace-router\SKILL.md'
    $maintenanceLayout=$Layout-ceq'framework-maintenance-sibling'
    $maintenanceOverlay=if($maintenanceLayout){Get-AiwMaintenanceOverlay $FrameworkWorkspace}else{$null}
    $templateAgents=if($maintenanceLayout){[string]$maintenanceOverlay.AgentsPath}else{Join-ChildPath $TargetFramework 'project-starter/AGENTS.md'}
    $targetVersionObject=(Read-StrictUtf8NoBom (Join-ChildPath $TargetFramework 'VERSION.json'))|ConvertFrom-Json
    $sourceVersionObject=(Read-StrictUtf8NoBom (Join-ChildPath $SourceFramework 'VERSION.json'))|ConvertFrom-Json
    $targetUsesGlobalRouter=[string]$targetVersionObject.version-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion ([string]$targetVersionObject.version))
    $sourceUsesGlobalRouter=Test-GlobalRouterProjection ([string]$sourceVersionObject.version) $SourceAdoptionProfile
    $templateSkill=if($targetUsesGlobalRouter){$null}else{Join-ChildPath $TargetFramework 'project-starter/.agents/skills/ai-workspace-router/SKILL.md'}
    $begin='<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->';$end='<!-- AI-WORKSPACE-FRAMEWORK:END -->'
    $current=if(Test-Path -LiteralPath $agentsPath -PathType Leaf){$bytes=[IO.File]::ReadAllBytes($agentsPath);if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'AGENTS_MANAGED_BLOCK_BOM'};try{$text=$utf8Strict.GetString($bytes)}catch{throw 'AGENTS_MANAGED_BLOCK_UTF8'};if($text.Contains("`r")-or-not$text.EndsWith("`n")){throw 'AGENTS_MANAGED_BLOCK_TEXT_FORMAT'};$text}else{''}
    $beginCount=[regex]::Matches($current,[regex]::Escape($begin)).Count;$endCount=[regex]::Matches($current,[regex]::Escape($end)).Count
    if(($beginCount-ne0-or$endCount-ne0)-and($beginCount-ne1-or$endCount-ne1)){throw 'AGENTS_MANAGED_MARKERS_MALFORMED'}
    $hasBlock=$beginCount-eq1
    if($hasBlock){$start=$current.IndexOf($begin,[StringComparison]::Ordinal);$finish=$current.IndexOf($end,[StringComparison]::Ordinal);if($finish-lt$start){throw 'AGENTS_MANAGED_BLOCK_ORDER'};$finish+=$end.Length;$block=$current.Substring($start,$finish-$start)}
    if($Install){
        $targetAgents=Read-StrictUtf8NoBom $templateAgents;$targetBlock=$targetAgents.TrimEnd("`n")
        if($targetUsesGlobalRouter){
            if(-not$hasBlock){throw 'AGENTS_MANAGED_BLOCK_MISSING_FOR_GLOBAL_ROUTER_MIGRATION'}
            $sourceAgentsPath=if($maintenanceLayout){Join-ChildPath (Get-AiwMaintenanceLegacyTemplateRoot $FrameworkWorkspace $SourceVersion) 'AGENTS.md'}else{Join-ChildPath $SourceFramework 'project-starter/AGENTS.md'}
            $sourceAgents=Read-StrictUtf8NoBom $sourceAgentsPath;$sourceBlock=$sourceAgents.TrimEnd("`n")
            if($block-cne$sourceBlock){throw 'AGENTS_MANAGED_BLOCK_CONFLICT'}
            $newAgents=Normalize-Text ($current.Substring(0,$start)+$targetBlock+$current.Substring($finish))
            if($sourceUsesGlobalRouter){if(Test-Path -LiteralPath $skillPath){throw 'ROUTER_SKILL_LOCAL_COPY_MIGRATION_CONFLICT'}}else{
              $sourceSkill=Join-ChildPath $SourceFramework 'project-starter/.agents/skills/ai-workspace-router/SKILL.md'
              $skillDirectory=Split-Path -Parent $skillPath
              $skillFiles=@(if(Test-Path -LiteralPath $skillDirectory -PathType Container){Get-ChildItem -LiteralPath $skillDirectory -Recurse -File -Force})
              $skillDirectories=@(if(Test-Path -LiteralPath $skillDirectory -PathType Container){Get-ChildItem -LiteralPath $skillDirectory -Recurse -Directory -Force})
              if($skillFiles.Count-ne1-or$skillDirectories.Count-ne0-or-not(Test-Path -LiteralPath $skillPath -PathType Leaf)-or-not(Test-Path -LiteralPath $sourceSkill -PathType Leaf)-or(Get-MinimalFileIdentity $skillPath)-cne(Get-MinimalFileIdentity $sourceSkill)){throw 'ROUTER_SKILL_LOCAL_COPY_MIGRATION_CONFLICT'}
            }
            $newSkill=$null
        }else{
            if($hasBlock-and$block-cne$targetBlock){throw 'AGENTS_MANAGED_BLOCK_CONFLICT'}
            if($hasBlock){$newAgents=$current}else{$separator=if($current.Length-eq0){''}elseif($current.EndsWith("`n")){"`n"}else{"`n`n"};$newAgents=$current+$separator+$targetAgents}
            $newSkill=Read-StrictUtf8NoBom $templateSkill
            if((Get-OptionalIdentity $skillPath)-cne'MISSING'-and(Read-StrictUtf8NoBom $skillPath)-cne$newSkill){throw 'ROUTER_SKILL_COLLISION'}
        }
    }else{
        if(-not$hasBlock){throw 'AGENTS_MANAGED_BLOCK_MISSING_FOR_DOWNGRADE'}
        # Remove only the managed block. Bytes outside the two markers are project-owned
        # and must survive a downgrade byte for byte, including blank lines and final-LF state.
        $newAgents=$current.Substring(0,$start)+$current.Substring($finish)
        $expectedSkill=Join-ChildPath $SourceFramework 'project-starter/.agents/skills/ai-workspace-router/SKILL.md'
        if(-not(Test-Path -LiteralPath $skillPath -PathType Leaf)-or-not(Test-Path -LiteralPath $expectedSkill -PathType Leaf)-or(Read-StrictUtf8NoBom $skillPath)-cne(Read-StrictUtf8NoBom $expectedSkill)){throw 'ROUTER_SKILL_DRIFT_FOR_DOWNGRADE'}
        $newSkill=$null
    }
    return [pscustomobject]@{AgentsPath=$agentsPath;SkillPath=$skillPath;AgentsContent=$newAgents;SkillContent=$newSkill}
}

function Read-Framework114Transaction([string]$TransactionRoot,[string]$RepositoryRoot,[string]$ProjectId,[string]$TargetVersion){
    if(-not(Test-Path -LiteralPath $TransactionRoot -PathType Container)){throw 'FRAMEWORK_1_14_TRANSACTION_NOT_DIRECTORY'}
    Assert-NoReparseTree $TransactionRoot
    $statePath=Join-Path $TransactionRoot 'state.json';$raw=Read-StrictUtf8NoBom $statePath
    try{$state=$raw|ConvertFrom-Json}catch{throw 'FRAMEWORK_1_14_TRANSACTION_STATE_JSON'}
    Assert-MinimalExactFields $state $raw @('schemaVersion','transactionId','projectId','fromVersion','toVersion','objects') 'Framework 1.14 transaction state'
    if(-not(Test-MinimalJsonInteger $state.schemaVersion)-or[int]$state.schemaVersion-ne1-or-not($state.transactionId-is[string])-or[string]$state.transactionId-cnotmatch'^[a-f0-9]{32}$'-or[string]$state.projectId-cne$ProjectId-or[string]$state.toVersion-cne$TargetVersion-or-not($state.objects-is[Array])-or@($state.objects).Count-ne6){throw 'FRAMEWORK_1_14_TRANSACTION_STATE_VALUES'}
    $expected=@('.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/corrections.json','.ai-workspace/process-policy.json','AGENTS.md','.agents/skills/ai-workspace-router/SKILL.md')
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$materialFiles=[Collections.Generic.List[string]]::new()
    foreach($entry in @($state.objects)){
        $entryRaw=$entry|ConvertTo-Json -Compress
        Assert-MinimalExactFields $entry $entryRaw @('relative','oldIdentity','newIdentity') 'Framework 1.14 transaction object'
        if(-not($entry.relative-is[string])-or[string]$entry.relative-cnotin$expected-or-not$seen.Add([string]$entry.relative)){throw 'FRAMEWORK_1_14_TRANSACTION_OBJECT_PATH'}
        foreach($name in @('oldIdentity','newIdentity')){if([string]$entry.$name-cne'MISSING'-and[string]$entry.$name-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'FRAMEWORK_1_14_TRANSACTION_OBJECT_IDENTITY'}}
        foreach($kind in @('old','new')){$identity=[string]$entry.($kind+'Identity');$stage=Join-ChildPath (Join-Path $TransactionRoot $kind) ([string]$entry.relative);if($identity-cne'MISSING'){if(-not(Test-Path -LiteralPath $stage -PathType Leaf)-or(Get-MinimalFileIdentity $stage)-cne$identity){throw 'FRAMEWORK_1_14_TRANSACTION_MATERIAL_DRIFT'};$materialFiles.Add($kind+'/'+[string]$entry.relative)}elseif(Test-Path -LiteralPath $stage){throw 'FRAMEWORK_1_14_TRANSACTION_UNEXPECTED_MATERIAL'}}
    }
    if(@($expected|Where-Object{$_-cnotin$seen}).Count-ne0){throw 'FRAMEWORK_1_14_TRANSACTION_OBJECT_SET'}
    Assert-ExactTransactionTree $TransactionRoot (@('state.json')+@($materialFiles)) @('old','new') 'FRAMEWORK_1_14_TRANSACTION_TREE_CLOSURE'
    return $state
}

function Assert-Framework114RecoveryDestination([string]$RepositoryRoot,[string]$TargetVersion) {
    $repository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    $relative='.framework-1.14-upgrade-recovery-'+$TargetVersion
    $destination=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-ChildPath $repository $relative)))
    if([IO.Path]::GetRelativePath($repository,$destination)-cne$relative){throw 'FRAMEWORK_1_14_TRANSACTION_RECOVERY_LOCATOR_DRIFT'}
    $existing=Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    if($null-ne$existing){
        if(($existing.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'FRAMEWORK_1_14_TRANSACTION_RECOVERY_REPARSE'}
        if(-not($existing-is[IO.DirectoryInfo])){throw 'FRAMEWORK_1_14_TRANSACTION_RECOVERY_NOT_DIRECTORY'}
        throw 'FRAMEWORK_1_14_TRANSACTION_RECOVERY_COLLISION'
    }
    return $destination
}

function Resume-Framework114Transaction([string]$TransactionRoot,[string]$RepositoryRoot,[string]$ProjectId,[string]$TargetVersion,[switch]$Preview){
    $completed=Assert-Framework114RecoveryDestination $RepositoryRoot $TargetVersion
    $state=Read-Framework114Transaction $TransactionRoot $RepositoryRoot $ProjectId $TargetVersion
    Assert-ManagedRouterDestinations $RepositoryRoot
    $states=@();foreach($entry in @($state.objects)){$live=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$entry.relative));if($live-cne[string]$entry.oldIdentity-and$live-cne[string]$entry.newIdentity){throw ('FRAMEWORK_1_14_TRANSACTION_UNKNOWN_LIVE_BYTES|'+[string]$entry.relative)};$states+=[pscustomobject]@{Entry=$entry;Live=$live}}
    $status=if(@($states|Where-Object{$_.Live-cne[string]$_.Entry.newIdentity}).Count-eq0){'NEW'}elseif(@($states|Where-Object{$_.Live-cne[string]$_.Entry.oldIdentity}).Count-eq0){'OLD'}else{'MIXED'}
    if($Preview){return ('RECOVERY_REQUIRED|state='+$status+'|from='+[string]$state.fromVersion+'|to='+[string]$state.toVersion)}
    foreach($item in $states){
        $entry=$item.Entry;if([string]$item.Live-ceq[string]$entry.newIdentity){continue}
        $managed=Test-ManagedRouterRelative ([string]$entry.relative);if($managed){Assert-ManagedRouterDestinations $RepositoryRoot}
        $livePath=Join-ChildPath $RepositoryRoot ([string]$entry.relative)
        if([string]$entry.newIdentity-ceq'MISSING'){if((Get-OptionalIdentity $livePath)-cne[string]$entry.oldIdentity){throw ('FRAMEWORK_1_14_TRANSACTION_RECHECK_DRIFT|'+[string]$entry.relative)};if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};[IO.File]::Delete($livePath)}
        else{$stage=Join-ChildPath (Join-Path $TransactionRoot 'new') ([string]$entry.relative);if((Get-OptionalIdentity $livePath)-cne[string]$entry.oldIdentity){throw ('FRAMEWORK_1_14_TRANSACTION_RECHECK_DRIFT|'+[string]$entry.relative)};New-Item -ItemType Directory -Path (Split-Path -Parent $livePath) -Force|Out-Null;if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};[IO.File]::Copy($stage,$livePath,([string]$entry.oldIdentity-cne'MISSING'))}
        if((Get-OptionalIdentity $livePath)-cne[string]$entry.newIdentity){throw ('FRAMEWORK_1_14_TRANSACTION_POSTIMAGE_DRIFT|'+[string]$entry.relative)}
    }
    foreach($entry in @($state.objects)){if((Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$entry.relative)))-cne[string]$entry.newIdentity){throw ('FRAMEWORK_1_14_TRANSACTION_FINAL_DRIFT|'+[string]$entry.relative)}}
    [IO.Directory]::Move($TransactionRoot,$completed)
    return [pscustomobject]@{State=$state;Recovery=$completed;InitialState=$status}
}

function Invoke-Framework114CrossRootTransition([string]$RepositoryRoot,[string]$ControlRoot,[string]$FrameworkWorkspace,[string]$FromVersion,[string]$TargetVersion,[string]$ProjectId,[string]$ControllerId,$ActorMigration,[bool]$ApplyChange){
    $transaction=Join-Path $RepositoryRoot '.framework-1.14-upgrade-transaction'
    if(Test-Path -LiteralPath $transaction){
        $recovered=Resume-Framework114Transaction $transaction $RepositoryRoot $ProjectId $TargetVersion -Preview:(-not$ApplyChange)
        if(-not$ApplyChange){Write-Output $recovered;return}
        $targetEvaluator=Join-ChildPath (Join-ChildPath $FrameworkWorkspace ('framework/versions/'+$TargetVersion)) 'scripts/check-project-corrections.ps1'
        $postCorrection=Invoke-CorrectionEvaluation $targetEvaluator $RepositoryRoot $FrameworkWorkspace $TargetVersion (Join-Path $ControlRoot 'project.json') (Join-Path $ControlRoot 'corrections.json') 'POSTCHECK'
        Write-CorrectionEvaluation $postCorrection 'after recovered cross-root projection'
        Write-Output ('RECOVERED_UPGRADE|objects=6|initial='+[string]$recovered.InitialState+'|recovery='+[string]$recovered.Recovery);return
    }
    $profileTarget=Test-AdoptionProfileVersion $TargetVersion
    $install=$TargetVersion-in@('1.14.0','1.14.1','1.15.0','1.15.1')-or$profileTarget
    if(($profileTarget-and$FromVersion-cnotin@($script:ActiveAdoptionProfile.directSourceVersions))-or($TargetVersion-in@('1.15.0','1.15.1')-and$FromVersion-notin@('1.14.0','1.14.1'))-or($TargetVersion-in@('1.14.0','1.14.1')-and$FromVersion-notin@('1.11.0','1.12.0','1.13.0','1.14.0','1.14.1'))-or(-not$install-and($FromVersion-notin@('1.14.0','1.14.1')-or$TargetVersion-cne'1.13.0'))){throw 'FRAMEWORK_1_14_DIRECT_TRANSITION_PAIR'}
    $sourceFramework=Join-ChildPath (Join-ChildPath $FrameworkWorkspace 'framework/versions') $FromVersion;$targetFramework=Join-ChildPath (Join-ChildPath $FrameworkWorkspace 'framework/versions') $TargetVersion
    $script:ActiveSourceAdoptionProfile=Get-AdoptionProfile $sourceFramework $FromVersion
    $sourceProcessCarrierVersion=Get-ProcessCarrierContractVersion $FromVersion $script:ActiveSourceAdoptionProfile
    $targetProcessCarrierVersion=Get-ProcessCarrierContractVersion $TargetVersion $script:ActiveAdoptionProfile
    $projectPath=Join-Path $ControlRoot 'project.json';$bootstrapPath=Join-Path $ControlRoot 'BOOTSTRAP.md';$controllerPath=Join-Path $ControlRoot 'controller.json';$correctionsPath=Join-Path $ControlRoot 'corrections.json';$policyPath=Join-Path $ControlRoot 'process-policy.json'
    $projectRaw=Read-StrictUtf8NoBom $projectPath;$project=$projectRaw|ConvertFrom-Json
    $layout=[string]$project.controlPlaneLayout;$maintenanceLayout=$layout-ceq'framework-maintenance-sibling'
    $maintenanceOverlay=if($maintenanceLayout){Get-AiwMaintenanceOverlay $FrameworkWorkspace}else{$null}
    if($layout-cnotin@('repo-local','framework-maintenance-sibling')){throw 'FRAMEWORK_TRANSITION_LAYOUT'}
    if($maintenanceLayout-and(-not$profileTarget-or$FromVersion-cnotin@($maintenanceOverlay.LegacySourceVersions))){throw 'FRAMEWORK_MAINTENANCE_DIRECT_TRANSITION_PAIR'}
    $baseProjectFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion')
    $sourceHasStructuredPolicy=$false
    if($null-ne$script:ActiveSourceAdoptionProfile){$projectFields=@($baseProjectFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy')+$(if($maintenanceLayout){@('frameworkTarget')}else{@()}));$expectedSchema=[int]$script:ActiveSourceAdoptionProfile.projectControl.schemaVersion;$sourceHasStructuredPolicy=$true}
    elseif($FromVersion-in@('1.14.0','1.14.1','1.15.0','1.15.1')){$projectFields=@($baseProjectFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy')+$(if($maintenanceLayout){@('frameworkTarget')}else{@()}));$expectedSchema=4;$sourceHasStructuredPolicy=$true}
    elseif($FromVersion-ceq'1.13.0'-and[int]$project.schemaVersion-eq4){$projectFields=@($baseProjectFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy'));$expectedSchema=4;$sourceHasStructuredPolicy=$true}
    elseif($FromVersion-in@('1.12.0','1.13.0')){$projectFields=@($baseProjectFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities'));$expectedSchema=3}
    else{$projectFields=@($baseProjectFields+@('routineExcludedPaths','frameworkCapabilities'));$expectedSchema=3}
    Assert-MinimalExactFields $project $projectRaw $projectFields 'Framework 1.14 transition project.json'
    $sourceBackend=if($null-ne$script:ActiveSourceAdoptionProfile){[string]$script:ActiveSourceAdoptionProfile.projectControl.frameworkToolBackend}elseif($FromVersion-in@('1.12.0','1.13.0','1.14.0','1.14.1','1.15.0','1.15.1')){'powershell7'}else{''}
    if([int]$project.schemaVersion-ne$expectedSchema-or[string]$project.id-cne$ProjectId-or[string]$project.frameworkVersion-cne$FromVersion-or(-not[string]::IsNullOrWhiteSpace($sourceBackend)-and[string]$project.frameworkToolBackend-cne$sourceBackend)-or[string]$project.controlPlaneLayout-cne$layout-or[string]$project.repositoryRoot-cne'..'-or-not($project.routineExcludedPaths-is[Array])-or-not($project.frameworkCapabilities-is[pscustomobject])){throw 'Framework transition source project is unhealthy.'}
    if($maintenanceLayout){
        if(@($project.frameworkCapabilities.PSObject.Properties).Count-ne0-or-not($project.frameworkTarget-is[pscustomobject])){throw 'FRAMEWORK_MAINTENANCE_SOURCE_PROJECT_INVALID'}
        Assert-MinimalExactFields $project.frameworkTarget ($project.frameworkTarget|ConvertTo-Json -Compress) @('repositoryId','siblingDirectory','routineExcludedPaths') 'Framework maintenance target'
        foreach($pathValue in @($project.routineExcludedPaths)){if(-not($pathValue-is[string])){throw 'FRAMEWORK_MAINTENANCE_CONTROL_ROUTINE_PATH'};$null=ConvertTo-MinimalFrameworkLocator ([string]$pathValue)}
        $topology=Resolve-AiwMaintenanceTopology -ControlRepositoryPath $RepositoryRoot -TargetRepositoryId ([string]$project.frameworkTarget.repositoryId) -TargetSiblingDirectory ([string]$project.frameworkTarget.siblingDirectory) -TargetRoutineExcludedPaths @($project.frameworkTarget.routineExcludedPaths)
        if([IO.Path]::GetFullPath([string]$topology.TargetRoot)-cne[IO.Path]::GetFullPath($FrameworkWorkspace)){throw 'FRAMEWORK_WORKSPACE_TARGET_MISMATCH'}
    }
    if($sourceHasStructuredPolicy-and(-not($project.processPolicy-is[pscustomobject])-or[int]$project.processPolicy.schemaVersion-ne1-or[string]$project.processPolicy.locator-cne'.ai-workspace/process-policy.json')){throw 'FRAMEWORK_1_14_SOURCE_PROJECT_INVALID'}
    $controllerRaw=Read-StrictUtf8NoBom $controllerPath;$controller=$controllerRaw|ConvertFrom-Json;Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    $sourceTemplateRoot=if($maintenanceLayout){Get-AiwMaintenanceLegacyTemplateRoot $FrameworkWorkspace $FromVersion}else{Join-ChildPath $sourceFramework 'project-starter'}
    $targetTemplateRoot=if($maintenanceLayout){[string]$maintenanceOverlay.Root}else{Join-ChildPath $targetFramework 'project-starter'}
    $sourceBootstrapTemplate=Read-StrictUtf8NoBom (Join-ChildPath $sourceTemplateRoot 'BOOTSTRAP.md');$targetBootstrapTemplate=Read-StrictUtf8NoBom (Join-ChildPath $targetTemplateRoot 'BOOTSTRAP.md')
    $currentBootstrap=Read-StrictUtf8NoBom $bootstrapPath;$expectedSource=Render-Bootstrap $sourceBootstrapTemplate $project $FromVersion;$currentBlock=Get-ManagedBootstrapBlock $currentBootstrap $bootstrapPath;$sourceBlock=Get-ManagedBootstrapBlock $expectedSource 'source Bootstrap'
    if($currentBlock.Text-cne$sourceBlock.Text){throw 'FRAMEWORK_1_14_SOURCE_BOOTSTRAP_DRIFT'}
    $project.frameworkVersion=$TargetVersion
    if($install){$project.schemaVersion=4;if($null-eq$project.PSObject.Properties['frameworkToolBackend']){$project|Add-Member -NotePropertyName frameworkToolBackend -NotePropertyValue 'powershell7'}else{$project.frameworkToolBackend='powershell7'};if($null-eq$project.PSObject.Properties['processPolicy']){$project|Add-Member -NotePropertyName processPolicy -NotePropertyValue ([pscustomobject]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'})}}
    if($profileTarget){Assert-TargetFrameworkCapabilities $project.frameworkCapabilities $projectRaw $script:ActiveTargetCapabilityContract}
    $targetProject=Normalize-Text ($project|ConvertTo-Json -Depth 100)
    $renderedTarget=Render-Bootstrap $targetBootstrapTemplate $project $TargetVersion;$targetBlock=Get-ManagedBootstrapBlock $renderedTarget 'target Bootstrap';$targetBootstrap=Replace-ManagedBootstrapBlock $currentBootstrap $targetBlock.Text $currentBlock;$correctionBlockSource=if($install){$renderedTarget}else{$currentBootstrap};$targetBootstrap=Merge-CorrectionBootstrapBlock $targetBootstrap $correctionBlockSource 'preserved correction Bootstrap'
    if($sourceHasStructuredPolicy){
        $policyRaw=Read-StrictUtf8NoBom $policyPath;$policy=$policyRaw|ConvertFrom-Json;$sourcePolicyFields=if($null-ne$script:ActiveSourceAdoptionProfile-and[int]$script:ActiveSourceAdoptionProfile.schemaVersion-eq2){@('schemaVersion','contractVersion','projectId','selectedRulePackBytes','rules')}else{@('schemaVersion','contractVersion','projectId','rules')};Assert-MinimalExactFields $policy $policyRaw $sourcePolicyFields 'Framework 1.14 transition process policy'
        if([int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne$sourceProcessCarrierVersion-or[string]$policy.projectId-cne$ProjectId-or-not($policy.rules-is[Array])){throw 'FRAMEWORK_1_14_SOURCE_POLICY_INVALID'}
        if($profileTarget){$targetPolicy=Normalize-Text ([ordered]@{schemaVersion=1;contractVersion=$targetProcessCarrierVersion;projectId=$ProjectId;selectedRulePackBytes=$SelectedRulePackBytes;rules=@($policy.rules)}|ConvertTo-Json -Depth 100)}elseif($sourceProcessCarrierVersion-ceq$targetProcessCarrierVersion){$targetPolicy=$policyRaw}else{$policy.contractVersion=$targetProcessCarrierVersion;$targetPolicy=Normalize-Text ($policy|ConvertTo-Json -Depth 100)}
    }else{
        if(Test-Path -LiteralPath $policyPath){throw 'FRAMEWORK_1_14_INACTIVE_POLICY_COLLISION'}
        $targetPolicy=(Read-StrictUtf8NoBom (Join-ChildPath $targetFramework 'project-starter/process-policy.json')).Replace('{{PROJECT_ID_JSON}}',($ProjectId|ConvertTo-Json -Compress))
        if($profileTarget){$policy=$targetPolicy|ConvertFrom-Json;$targetPolicy=Normalize-Text ([ordered]@{schemaVersion=1;contractVersion=$targetProcessCarrierVersion;projectId=$ProjectId;selectedRulePackBytes=$SelectedRulePackBytes;rules=@($policy.rules)}|ConvertTo-Json -Depth 100)}
    }
    if($maintenanceLayout){
        $overlayPolicyRaw=Read-StrictUtf8NoBom ([string]$maintenanceOverlay.ProcessPolicyPath)
        $overlayPolicyRaw=$overlayPolicyRaw.Replace('{{PROCESS_CONTRACT_VERSION_JSON}}',($targetProcessCarrierVersion|ConvertTo-Json -Compress)).Replace('{{PROJECT_ID_JSON}}',($ProjectId|ConvertTo-Json -Compress)).Replace('{{SELECTED_RULE_PACK_BYTES}}',[string]$SelectedRulePackBytes)
        try{$overlayPolicy=$overlayPolicyRaw|ConvertFrom-Json}catch{throw 'MAINTENANCE_OVERLAY_POLICY_JSON'}
        $targetPolicyObject=$targetPolicy|ConvertFrom-Json
        foreach($overlayRule in @($overlayPolicy.rules)){
            $sameId=@($targetPolicyObject.rules|Where-Object{[string]$_.ruleId-ceq[string]$overlayRule.ruleId})
            if($sameId.Count-gt1){throw 'MAINTENANCE_OVERLAY_POLICY_DUPLICATE'}
            if($sameId.Count-eq1){
                if(($sameId[0]|ConvertTo-Json -Depth 100 -Compress)-cne($overlayRule|ConvertTo-Json -Depth 100 -Compress)){throw ('MAINTENANCE_OVERLAY_POLICY_CONFLICT|'+[string]$overlayRule.ruleId)}
            }else{$targetPolicyObject.rules=@($targetPolicyObject.rules)+@($overlayRule)}
        }
        $targetPolicy=Normalize-Text ($targetPolicyObject|ConvertTo-Json -Depth 100)
    }
    $correctionsRaw=Read-StrictUtf8NoBom $correctionsPath;$corrections=$correctionsRaw|ConvertFrom-Json;Assert-MinimalExactFields $corrections $correctionsRaw @('schemaVersion','contractVersion','projectId','corrections') 'Framework 1.14 transition corrections'
    if([string]$corrections.projectId-cne$ProjectId-or-not($corrections.corrections-is[Array])){throw 'FRAMEWORK_1_14_SOURCE_CORRECTIONS_INVALID'}
    if($install){
        if([int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0'-and$sourceProcessCarrierVersion-ceq$targetProcessCarrierVersion){$targetCorrections=$correctionsRaw}
        elseif([int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0' -and @($corrections.corrections).Count-eq0){$template=Read-StrictUtf8NoBom (Join-ChildPath $targetFramework 'project-starter/corrections.json');$targetCorrections=$template.Replace('{{PROJECT_ID}}',$ProjectId)}
        elseif([int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0'){$targetCorrections=$correctionsRaw}
        elseif([int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq$sourceProcessCarrierVersion){if($sourceProcessCarrierVersion-ceq$targetProcessCarrierVersion){$targetCorrections=$correctionsRaw}else{$corrections.contractVersion=$targetProcessCarrierVersion;$targetCorrections=Normalize-Text ($corrections|ConvertTo-Json -Depth 100)}}else{throw 'FRAMEWORK_1_14_SOURCE_CORRECTIONS_INVALID'}
    }else{
        if([int]$corrections.schemaVersion-eq2-and[string]$corrections.contractVersion-ceq$sourceProcessCarrierVersion){
            if(@($corrections.corrections).Count-ne0){throw 'CORRECTIONS_V2_DOWNGRADE_REVERSE_MIGRATION_REQUIRED'}
            $template=Read-StrictUtf8NoBom (Join-ChildPath $targetFramework 'project-starter/corrections.json');$targetCorrections=$template.Replace('{{PROJECT_ID}}',$ProjectId)
        }elseif([int]$corrections.schemaVersion-eq1-and[string]$corrections.contractVersion-ceq'1.10.0'){$targetCorrections=$correctionsRaw}
        else{throw 'FRAMEWORK_1_14_SOURCE_CORRECTIONS_INVALID'}
    }
    $agents=Get-ManagedAgentsTransition $RepositoryRoot $sourceFramework $targetFramework $install $script:ActiveSourceAdoptionProfile $layout $FrameworkWorkspace $FromVersion
    $targetEvaluator=Join-ChildPath $targetFramework 'scripts/check-project-corrections.ps1'
    $preCorrection=Invoke-CorrectionEvaluationProjected $targetEvaluator $FrameworkWorkspace $TargetVersion $targetProject $targetBootstrap $correctionsPath $policyPath -TargetProcessPolicy $targetPolicy -TargetCorrections $targetCorrections
    Write-CorrectionEvaluation $preCorrection 'before cross-root projection'
    $objects=@(
      [pscustomobject]@{relative='.ai-workspace/project.json';path=$projectPath;content=$targetProject},
      [pscustomobject]@{relative='.ai-workspace/BOOTSTRAP.md';path=$bootstrapPath;content=$targetBootstrap},
      [pscustomobject]@{relative='.ai-workspace/corrections.json';path=$correctionsPath;content=$targetCorrections},
      [pscustomobject]@{relative='.ai-workspace/process-policy.json';path=$policyPath;content=$targetPolicy},
      [pscustomobject]@{relative='AGENTS.md';path=$agents.AgentsPath;content=$agents.AgentsContent}
    )
    if($null-ne$agents.SkillContent-or(Test-Path -LiteralPath $agents.SkillPath)){$objects+=@([pscustomobject]@{relative='.agents/skills/ai-workspace-router/SKILL.md';path=$agents.SkillPath;content=$agents.SkillContent})}
    if($profileTarget){$gitIgnore=Get-RuntimeGitIgnoreProjection $RepositoryRoot ([string]$script:ActiveAdoptionProfile.projectControl.runtimeGitIgnoreRule);if($gitIgnore.Changed){$objects+=@([pscustomobject]@{relative='.gitignore';path=$gitIgnore.Path;content=$gitIgnore.Content})}}
    if(($TargetVersion-in@('1.15.0','1.15.1')-or$profileTarget)-and$null-eq$ActorMigration){throw 'ACTOR_BOUND_PROJECT_UPGRADE_ROUTE_REQUIRED'}
    if($profileTarget){$script:CurrentPinBudgetBridge=Get-TargetProjectedProcessPreflight $RepositoryRoot $FrameworkWorkspace $TargetVersion $ProjectId $ActorMigration $targetProject $targetBootstrap $targetCorrections $targetPolicy $controllerPath;Write-Output ('TARGET_PROJECTED_PROCESS_PREFLIGHT|to='+$TargetVersion+'|resolver='+$script:CurrentPinBudgetBridge.ResolverReason+'|capabilities='+[string]::Join(',',@($script:CurrentPinBudgetBridge.Capabilities))+'|budget='+$script:CurrentPinBudgetBridge.BudgetMode+'|requirements='+$script:CurrentPinBudgetBridge.SelectedRequirementCount+'|bytes='+$script:CurrentPinBudgetBridge.SelectedPackBytes+'|pack='+$script:CurrentPinBudgetBridge.SelectedPackIdentity+'|source='+$script:CurrentPinBudgetBridge.SourceCompositionIdentity)}elseif($TargetVersion-ceq'1.15.1'){$script:CurrentPinBudgetBridge=Get-CurrentPinProcessBridge $RepositoryRoot $FrameworkWorkspace $FromVersion $ProjectId $projectPath $correctionsPath $ActorMigration;Write-Output ('CURRENT_PIN_PROCESS_BRIDGE|from='+$FromVersion+'|resolver='+$script:CurrentPinBudgetBridge.ResolverReason+'|capabilities='+[string]::Join(',',@($script:CurrentPinBudgetBridge.Capabilities))+'|budget='+$script:CurrentPinBudgetBridge.BudgetMode+'|requirements='+$script:CurrentPinBudgetBridge.SelectedRequirementCount+'|bytes='+$script:CurrentPinBudgetBridge.SelectedPackBytes+'|pack='+$script:CurrentPinBudgetBridge.SelectedPackIdentity+'|source='+$script:CurrentPinBudgetBridge.SourceCompositionIdentity)}
    if($null-ne$ActorMigration){Invoke-ActorBoundUpgrade $RepositoryRoot $sourceFramework $targetFramework $FromVersion $TargetVersion $ProjectId $projectPath $controllerPath $ActorMigration $objects $ApplyChange;return}
    if(-not$ApplyChange){
        $writeSet=New-Object 'System.Collections.Generic.List[string]'
        $writeSet.Add('.framework-1.14-upgrade-transaction/state.json');$writeSet.Add('.framework-1.14-upgrade-recovery-'+$TargetVersion+'/state.json')
        foreach($object in $objects){
            if(Test-ManagedRouterRelative ([string]$object.relative)){Assert-ManagedRouterDestinations $RepositoryRoot}
            $oldIdentity=Get-OptionalIdentity $object.path
            $writeSet.Add($object.relative)
            if($oldIdentity-cne'MISSING'){$writeSet.Add('.framework-1.14-upgrade-transaction/old/'+$object.relative);$writeSet.Add('.framework-1.14-upgrade-recovery-'+$TargetVersion+'/old/'+$object.relative)}
            if($null-ne$object.content){$writeSet.Add('.framework-1.14-upgrade-transaction/new/'+$object.relative);$writeSet.Add('.framework-1.14-upgrade-recovery-'+$TargetVersion+'/new/'+$object.relative)}
        }
        Write-Output ('UPGRADE_WRITESET|'+[string]::Join('|',$writeSet));Write-Output ('WHAT_IF|from='+$FromVersion+'|to='+$TargetVersion+'|objects=6|transaction=cross-root');return
    }
    if($FromVersion-eq$TargetVersion){Write-Output 'ALREADY_UPGRADED|objects=6';return}
    if(Test-Path -LiteralPath $transaction){throw 'FRAMEWORK_1_14_TRANSACTION_ALREADY_EXISTS'}
    $null=Assert-Framework114RecoveryDestination $RepositoryRoot $TargetVersion
    $transactionId=[guid]::NewGuid().ToString('N');New-Item -ItemType Directory -Path (Join-Path $transaction 'old'),(Join-Path $transaction 'new') -Force|Out-Null
    $stateObjects=@()
    try{
        foreach($object in $objects){if(Test-ManagedRouterRelative ([string]$object.relative)){Assert-ManagedRouterDestinations $RepositoryRoot};$oldIdentity=Get-OptionalIdentity $object.path;$oldStage=Join-ChildPath (Join-Path $transaction 'old') $object.relative;$newStage=Join-ChildPath (Join-Path $transaction 'new') $object.relative;if($oldIdentity-cne'MISSING'){New-Item -ItemType Directory -Path (Split-Path -Parent $oldStage) -Force|Out-Null;[IO.File]::Copy($object.path,$oldStage,$false)};if($null-ne$object.content){New-Item -ItemType Directory -Path (Split-Path -Parent $newStage) -Force|Out-Null;Write-ProjectedText $newStage ([string]$object.content);$newIdentity=Get-MinimalFileIdentity $newStage}else{$newIdentity='MISSING'};$stateObjects+=[ordered]@{relative=$object.relative;oldIdentity=$oldIdentity;newIdentity=$newIdentity}}
        $state=[ordered]@{schemaVersion=1;transactionId=$transactionId;projectId=$ProjectId;fromVersion=$FromVersion;toVersion=$TargetVersion;objects=$stateObjects};Write-Utf8NoBom (Join-Path $transaction 'state.json') ($state|ConvertTo-Json -Depth 10)
        foreach($entry in $stateObjects){$live=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot $entry.relative);if($live-cne[string]$entry.oldIdentity){throw ('OBJECT_DRIFT|'+$entry.relative)}}
        $recovered=Resume-Framework114Transaction $transaction $RepositoryRoot $ProjectId $TargetVersion
        $completed=[string]$recovered.Recovery
        $postCorrection=Invoke-CorrectionEvaluation $targetEvaluator $RepositoryRoot $FrameworkWorkspace $TargetVersion $projectPath $correctionsPath 'POSTCHECK'
        Write-CorrectionEvaluation $postCorrection 'after cross-root projection'
        Write-Output ('UPGRADED|objects=6|recovery='+$completed)
    }catch{throw "Framework 1.14 transition stopped; exact transaction is preserved for deterministic forward recovery. $($_.Exception.Message)"}
}
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

function Assert-NoDuplicateJsonMembers($Element,[string]$ErrorCode) {
    if($Element.ValueKind-eq[Text.Json.JsonValueKind]::Object){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($property in $Element.EnumerateObject()){if(-not$seen.Add([string]$property.Name)){throw ($ErrorCode+'|'+[string]$property.Name)};Assert-NoDuplicateJsonMembers $property.Value $ErrorCode}
    }elseif($Element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($item in $Element.EnumerateArray()){Assert-NoDuplicateJsonMembers $item $ErrorCode}}
}

function Assert-StrictJsonMemberSet([string]$Text,[string]$ErrorCode){
    $options=[Text.Json.JsonDocumentOptions]::new();$options.AllowTrailingCommas=$false;$options.CommentHandling=[Text.Json.JsonCommentHandling]::Disallow
    try{$document=[Text.Json.JsonDocument]::Parse($Text,$options)}catch{throw $ErrorCode}
    try{Assert-NoDuplicateJsonMembers $document.RootElement $ErrorCode}finally{$document.Dispose()}
}

function Get-UpperSha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-FrameworkPayloadFacts([string]$FrameworkPath) {
    $rows=New-Object 'System.Collections.Generic.List[string]';[int64]$totalBytes=0
    foreach($file in @(Get-ChildItem -LiteralPath $FrameworkPath -Recurse -File -Force)){
        $relative=$file.FullName.Substring($FrameworkPath.Length+1).Replace('\','/')
        if($relative-ceq'RELEASE_MANIFEST.json'){continue}
        $bytes=[IO.File]::ReadAllBytes($file.FullName);$totalBytes+=$bytes.Length
        $rows.Add($relative+'|'+$bytes.Length+'|'+(Get-UpperSha256Bytes $bytes))
    }
    [string[]]$ordered=@($rows);[Array]::Sort($ordered,[StringComparer]::Ordinal)
    return [pscustomobject]@{FileCount=$ordered.Count;TotalBytes=$totalBytes;Canonical=(Get-UpperSha256Bytes ($utf8NoBom.GetBytes([string]::Join("`n",$ordered))))}
}

function Assert-StableFrameworkRelease([string]$FrameworkPath,[string]$ExpectedVersion) {
    if(-not(Test-Path -LiteralPath $FrameworkPath -PathType Container)){throw "Framework version does not exist: $ExpectedVersion"}
    Assert-NoReparseTree $FrameworkPath
    $versionPath=Join-ChildPath $FrameworkPath 'VERSION.json';$manifestPath=Join-ChildPath $FrameworkPath 'RELEASE_MANIFEST.json'
    if(-not(Test-Path -LiteralPath $versionPath -PathType Leaf)-or-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "FRAMEWORK_RELEASE_METADATA_MISSING|$ExpectedVersion"}
    try{$version=(Read-StrictUtf8NoBom $versionPath)|ConvertFrom-Json;$manifest=(Read-StrictUtf8NoBom $manifestPath)|ConvertFrom-Json}catch{throw "FRAMEWORK_RELEASE_METADATA_INVALID|$ExpectedVersion"}
    if(-not($version.version-is[string])-or[string]$version.version-cne$ExpectedVersion-or-not($version.lifecycle-is[string])-or[string]$version.lifecycle-cne'STABLE'-or-not($version.consumable-is[bool])-or-not[bool]$version.consumable-or-not($version.projectPinEligible-is[bool])-or-not[bool]$version.projectPinEligible){throw "FRAMEWORK_VERSION_NOT_CONSUMABLE|$ExpectedVersion"}
    if(-not($manifest.version-is[string])-or[string]$manifest.version-cne$ExpectedVersion-or-not($manifest.lifecycle-is[string])-or[string]$manifest.lifecycle-cne'STABLE'-or-not($manifest.sourceReview-is[string])-or[string]$manifest.sourceReview-cne'APPROVED'-or-not($manifest.releaseIntegration-is[string])-or[string]::IsNullOrWhiteSpace([string]$manifest.releaseIntegration)-or[string]$manifest.releaseIntegration-ceq'PENDING'-or-not(Test-MinimalJsonInteger $manifest.fileCount)-or-not(Test-MinimalJsonInteger $manifest.totalBytes)-or-not($manifest.canonical-is[string])-or[string]$manifest.canonical-cnotmatch'^[A-F0-9]{64}$'){throw "FRAMEWORK_RELEASE_NOT_SEALED|$ExpectedVersion"}
    $facts=Get-FrameworkPayloadFacts $FrameworkPath
    if([int64]$manifest.fileCount-ne[int64]$facts.FileCount-or[int64]$manifest.totalBytes-ne[int64]$facts.TotalBytes-or[string]$manifest.canonical-cne[string]$facts.Canonical){throw "FRAMEWORK_RELEASE_MANIFEST_DRIFT|$ExpectedVersion"}
}

function Get-LocalCandidateFrameworkSnapshot([string]$FrameworkPath,[string]$ExpectedVersion,$AdoptionProfile) {
    if(-not(Test-Path -LiteralPath $FrameworkPath -PathType Container)){throw "Framework version does not exist: $ExpectedVersion"}
    Assert-NoReparseTree $FrameworkPath
    $versionPath=Join-ChildPath $FrameworkPath 'VERSION.json';$manifestPath=Join-ChildPath $FrameworkPath 'RELEASE_MANIFEST.json'
    if(-not(Test-Path -LiteralPath $versionPath -PathType Leaf)-or-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "FRAMEWORK_CANDIDATE_METADATA_MISSING|$ExpectedVersion"}
    try{$version=(Read-StrictUtf8NoBom $versionPath)|ConvertFrom-Json;$manifest=(Read-StrictUtf8NoBom $manifestPath)|ConvertFrom-Json}catch{throw "FRAMEWORK_CANDIDATE_METADATA_INVALID|$ExpectedVersion"}
    if(-not($version.version-is[string])-or[string]$version.version-cne$ExpectedVersion-or-not($version.lifecycle-is[string])-or[string]$version.lifecycle-cne'CANDIDATE'-or-not($version.consumable-is[bool])-or[bool]$version.consumable-or-not($version.projectPinEligible-is[bool])-or[bool]$version.projectPinEligible){throw "FRAMEWORK_LOCAL_CANDIDATE_STATE_REQUIRED|$ExpectedVersion"}
    if($null-eq$AdoptionProfile-or$null-eq$AdoptionProfile.PSObject.Properties['localCandidatePilotEligible']-or-not($AdoptionProfile.localCandidatePilotEligible-is[bool])-or-not[bool]$AdoptionProfile.localCandidatePilotEligible){throw "FRAMEWORK_LOCAL_CANDIDATE_PROFILE_REQUIRED|$ExpectedVersion"}
    $manifestFields=@('schemaVersion','version','lifecycle','releaseClass','scope','algorithm','fileCount','totalBytes','canonical','baseline','sourceReview','sourceCandidate','completeSuite','sourceReviewEvidence','releaseIntegration')
    Assert-MinimalExactFields $manifest ($manifest|ConvertTo-Json -Depth 20 -Compress) $manifestFields 'Local candidate release manifest'
    if(-not(Test-MinimalJsonInteger $manifest.schemaVersion)-or[int]$manifest.schemaVersion-ne2-or-not($manifest.version-is[string])-or[string]$manifest.version-cne$ExpectedVersion-or-not($manifest.lifecycle-is[string])-or[string]$manifest.lifecycle-cne'CANDIDATE'-or-not($manifest.sourceReview-is[string])-or[string]$manifest.sourceReview-cne'APPROVED'-or-not($manifest.releaseIntegration-is[string])-or[string]$manifest.releaseIntegration-cne'PENDING'-or-not($manifest.sourceCandidate-is[string])-or[string]::IsNullOrWhiteSpace([string]$manifest.sourceCandidate)){throw "FRAMEWORK_LOCAL_CANDIDATE_REVIEW_REQUIRED|$ExpectedVersion"}
    $facts=Get-FrameworkPayloadFacts $FrameworkPath
    if(-not(Test-MinimalJsonInteger $manifest.fileCount)-or-not(Test-MinimalJsonInteger $manifest.totalBytes)-or[int64]$manifest.fileCount-ne[int64]$facts.FileCount-or[int64]$manifest.totalBytes-ne[int64]$facts.TotalBytes-or-not($manifest.canonical-is[string])-or[string]$manifest.canonical-cne[string]$facts.Canonical){throw "FRAMEWORK_LOCAL_CANDIDATE_MANIFEST_DRIFT|$ExpectedVersion"}
    $suite=$manifest.completeSuite;$suiteFields=@('status','passed','total','payloadCanonical','evidenceIdentity')
    Assert-MinimalExactFields $suite ($suite|ConvertTo-Json -Depth 10 -Compress) $suiteFields 'Local candidate complete suite'
    if(-not($suite.status-is[string])-or[string]$suite.status-cne'PASS'-or-not(Test-MinimalJsonInteger $suite.passed)-or-not(Test-MinimalJsonInteger $suite.total)-or[int64]$suite.passed-lt1-or[int64]$suite.passed-ne[int64]$suite.total-or-not($suite.payloadCanonical-is[string])-or[string]$suite.payloadCanonical-cne[string]$facts.Canonical-or-not($suite.evidenceIdentity-is[string])-or[string]$suite.evidenceIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw "FRAMEWORK_LOCAL_CANDIDATE_COMPLETE_SUITE_REQUIRED|$ExpectedVersion"}
    $review=$manifest.sourceReviewEvidence;$reviewFields=@('status','reviewer','packageIdentity','reviewedPayloadCanonical','reviewedManifestIdentity')
    Assert-MinimalExactFields $review ($review|ConvertTo-Json -Depth 10 -Compress) $reviewFields 'Local candidate source review evidence'
    if(-not($review.status-is[string])-or[string]$review.status-cne'APPROVED'-or-not($review.reviewer-is[string])-or[string]::IsNullOrWhiteSpace([string]$review.reviewer)-or[string]$review.reviewer-ceq'PENDING'-or-not($review.packageIdentity-is[string])-or[string]$review.packageIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not($review.reviewedPayloadCanonical-is[string])-or[string]$review.reviewedPayloadCanonical-cne[string]$facts.Canonical-or-not($review.reviewedManifestIdentity-is[string])-or[string]$review.reviewedManifestIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw "FRAMEWORK_LOCAL_CANDIDATE_SOURCE_REVIEW_EVIDENCE_REQUIRED|$ExpectedVersion"}
    return [pscustomobject]@{Version=$ExpectedVersion;Lifecycle='CANDIDATE';LocalCandidate=$true;FileCount=[int64]$facts.FileCount;TotalBytes=[int64]$facts.TotalBytes;Canonical=[string]$facts.Canonical;ManifestIdentity=(Get-MinimalFileIdentity $manifestPath)}
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
    foreach($name in $Expected){$expectedCount=if($name-ceq'schemaVersion'-and(('processPolicy'-cin$names)-or('routerCompatibility'-cin$names)-or('projectControl'-cin$names))){2}elseif($name-ceq'routineExcludedPaths'-and'frameworkTarget'-cin$names){2}else{1};if([regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count-ne$expectedCount){throw "$Label duplicate or missing field: $name"}}
}

function Get-AdoptionProfile([string]$FrameworkPath,[string]$ExpectedVersion) {
    $path=Join-ChildPath $FrameworkPath 'ADOPTION_PROFILE.json'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    $raw=Read-StrictUtf8NoBom $path
    try{$profile=$raw|ConvertFrom-Json}catch{throw 'ADOPTION_PROFILE_JSON'}
    $legacyProfile=(Test-MinimalJsonInteger $profile.schemaVersion) -and [int]$profile.schemaVersion-eq1
    $fields=if($legacyProfile){@('schemaVersion','frameworkVersion','registrationEligible','directSourceVersions','projectControl','processBudgets')}else{@('schemaVersion','frameworkVersion','registrationEligible','localCandidatePilotEligible','directSourceVersions','projectControl','processBudget')}
    Assert-MinimalExactFields $profile $raw $fields 'Framework ADOPTION_PROFILE.json'
    $projectControlFields=@('schemaVersion','processCarrierContractVersion','frameworkToolBackend','navigationProjection','taskLastWriteRequired','capabilityBinding')+$(if($legacyProfile){@()}else{@('runtimeArtifactRoot','runtimeGitIgnoreRule')})
    Assert-MinimalExactFields $profile.projectControl ($profile.projectControl|ConvertTo-Json -Compress) $projectControlFields 'Framework ADOPTION_PROFILE.json projectControl'
    if($legacyProfile){Assert-MinimalExactFields $profile.processBudgets ($profile.processBudgets|ConvertTo-Json -Compress) @('ordinarySelectedPackBytes','absoluteSelectedPackBytes','legacySchema1CorrectionCompatibilityBytes') 'Framework ADOPTION_PROFILE.json processBudgets'}else{Assert-MinimalExactFields $profile.processBudget ($profile.processBudget|ConvertTo-Json -Compress) @('defaultSelectedRulePackBytes','absoluteSelectedRulePackBytes') 'Framework ADOPTION_PROFILE.json processBudget'}
    $sources=@($profile.directSourceVersions|ForEach-Object{[string]$_})
    $commonInvalid=[string]$profile.frameworkVersion-cne$ExpectedVersion-or-not($profile.registrationEligible-is[bool])-or-not($profile.directSourceVersions-is[Array])-or-not(Test-MinimalJsonInteger $profile.projectControl.schemaVersion)-or[int]$profile.projectControl.schemaVersion-ne4-or[string]$profile.projectControl.frameworkToolBackend-cne'powershell7'-or-not($profile.projectControl.taskLastWriteRequired-is[bool])-or-not[bool]$profile.projectControl.taskLastWriteRequired-or[string]$profile.projectControl.capabilityBinding-cne'EXACT_ENABLED_IDS'
    if($legacyProfile){
        if($commonInvalid-or[string]$profile.projectControl.processCarrierContractVersion-cne'1.14.0'-or[string]$profile.projectControl.navigationProjection-cne'HOST_GLOBAL_SKILL_MANAGED_AGENTS'-or$sources.Count-ne3-or[string]::Join('|',$sources)-cne'1.14.1|1.15.0|1.15.1'-or-not(Test-MinimalJsonInteger $profile.processBudgets.ordinarySelectedPackBytes)-or[int]$profile.processBudgets.ordinarySelectedPackBytes-ne32768-or-not(Test-MinimalJsonInteger $profile.processBudgets.absoluteSelectedPackBytes)-or[int]$profile.processBudgets.absoluteSelectedPackBytes-ne65536-or-not(Test-MinimalJsonInteger $profile.processBudgets.legacySchema1CorrectionCompatibilityBytes)-or[int]$profile.processBudgets.legacySchema1CorrectionCompatibilityBytes-ne98304){throw 'ADOPTION_PROFILE_VALUES'}
    }else{
        $uniqueSources=@($sources|Select-Object -Unique)
        $default=if(Test-MinimalJsonInteger $profile.processBudget.defaultSelectedRulePackBytes){[int64]$profile.processBudget.defaultSelectedRulePackBytes}else{-1}
        $absolute=if(Test-MinimalJsonInteger $profile.processBudget.absoluteSelectedRulePackBytes){[int64]$profile.processBudget.absoluteSelectedRulePackBytes}else{-1}
        if(-not(Test-MinimalJsonInteger $profile.schemaVersion)-or[int]$profile.schemaVersion-ne2-or$commonInvalid-or-not($profile.localCandidatePilotEligible-is[bool])-or-not[bool]$profile.localCandidatePilotEligible-or[string]$profile.projectControl.processCarrierContractVersion-cne$ExpectedVersion-or[string]$profile.projectControl.navigationProjection-cne'ROOT_CANONICAL_SKILL_MANAGED_AGENTS'-or[string]$profile.projectControl.runtimeArtifactRoot-cne'.ai-workspace/runtime'-or[string]$profile.projectControl.runtimeGitIgnoreRule-cne'/.ai-workspace/runtime/'-or$sources.Count-lt1-or$sources.Count-gt32-or$uniqueSources.Count-ne$sources.Count-or@($sources|Where-Object{$_-cnotmatch'^\d+\.\d+\.\d+$'-or$_-ceq$ExpectedVersion}).Count-ne0-or$default-ne32768-or$absolute-ne98304){throw 'ADOPTION_PROFILE_VALUES'}
    }
    return $profile
}

function Get-CurrentPinProcessBridge([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$FromVersion,[string]$ProjectId,[string]$ProjectFile,[string]$CorrectionsFile,$Migration) {
    $provided=@(-not[string]::IsNullOrWhiteSpace($CurrentProcessInputPath),-not[string]::IsNullOrWhiteSpace($ExpectedCurrentProcessInputIdentity))
    if(@($provided|Where-Object{$_}).Count-ne2){throw 'CURRENT_PIN_PROCESS_INPUT_REQUIRED'}
    if($ExpectedCurrentProcessInputIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $CurrentProcessInputPath -PathType Leaf)-or(Get-MinimalFileIdentity $CurrentProcessInputPath)-cne$ExpectedCurrentProcessInputIdentity){throw 'CURRENT_PIN_PROCESS_INPUT_DRIFT'}
    $raw=Read-StrictUtf8NoBom $CurrentProcessInputPath
    Assert-StrictJsonMemberSet $raw 'CURRENT_PIN_PROCESS_INPUT_DUPLICATE_MEMBER'
    try{$input=$raw|ConvertFrom-Json}catch{throw 'CURRENT_PIN_PROCESS_INPUT_JSON'}
    $expectedInputFields=@('schemaVersion','mode','projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities','exactPaths','forbiddenPaths','protectedPaths','authorizationPackagePath','expectedAuthorizationIdentity','userDecision','recoveryState','hostEnforcementGrade','invocationState','intentEnvelope','evaluationOnly')
    $inputNames=@($input.PSObject.Properties.Name)
    if(-not($input-is[pscustomobject])-or$inputNames.Count-ne$expectedInputFields.Count-or@($expectedInputFields|Where-Object{$_-cnotin$inputNames}).Count-ne0){throw 'CURRENT_PIN_PROCESS_INPUT_FIELDS'}
    if(-not(Test-MinimalJsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-ne2-or[string]$input.mode-cne'DISCOVER'-or-not($input.evaluationOnly-is[bool])-or-not[bool]$input.evaluationOnly){throw 'CURRENT_PIN_PROCESS_INPUT_MODE'}
    foreach($name in @('capabilities','exactPaths','forbiddenPaths','protectedPaths')){if(-not($input.$name-is[Array])-or@($input.$name|Where-Object{-not($_-is[string])}).Count-ne0){throw ('CURRENT_PIN_PROCESS_INPUT_ARRAY|'+$name)}}
    $repository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot));$workspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($FrameworkWorkspace))
    $inputRepository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.projectRoot))))
    $inputWorkspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.frameworkRoot))))
    $inputTask=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.taskPath)))
    if($inputRepository-cne$repository-or$inputWorkspace-cne$workspace-or$inputTask-cne[IO.Path]::GetFullPath([string]$Migration.Path)){throw 'CURRENT_PIN_PROCESS_SCOPE_DRIFT'}
    if([string]$input.expectedProjectConfigIdentity-cne(Get-MinimalFileIdentity $ProjectFile)-or[string]$input.expectedCorrectionsIdentity-cne(Get-MinimalFileIdentity $CorrectionsFile)-or[string]$input.expectedTaskIdentity-cne[string]$Migration.OldIdentity-or[string]$input.observedActor-cne[string]$Migration.Actor){throw 'CURRENT_PIN_PROCESS_BINDING_DRIFT'}
    $projectRaw=Read-StrictUtf8NoBom $ProjectFile;try{$project=$projectRaw|ConvertFrom-Json}catch{throw 'CURRENT_PIN_PROJECT_JSON'}
    $declaredCapabilities=@(Get-ExactEnabledCapabilityIds $project $projectRaw);$inputCapabilitiesOriginal=@($input.capabilities|ForEach-Object{[string]$_});$inputCapabilities=@($inputCapabilitiesOriginal);[Array]::Sort($inputCapabilities,[StringComparer]::Ordinal)
    if([string]::Join("`n",$inputCapabilitiesOriginal)-cne[string]::Join("`n",$inputCapabilities)-or[string]::Join("`n",$inputCapabilities)-cne[string]::Join("`n",$declaredCapabilities)){throw 'CURRENT_PIN_PROCESS_CAPABILITY_DRIFT'}
    if(@($input.exactPaths).Count-ne1-or[string]$input.exactPaths[0]-cne[string]$Migration.Relative){throw 'CURRENT_PIN_PROCESS_EXACT_TASK_REQUIRED'}
    $forbidden=@($input.forbiddenPaths);$protected=@($input.protectedPaths)
    if('src/'-cnotin$forbidden-or@(@('test/','tests/')|Where-Object{$_-cin$forbidden}).Count-eq0-or'assets/'-cnotin$forbidden-or'docs/'-cnotin$forbidden-or'.ai-workspace/'-cnotin$protected){throw 'CURRENT_PIN_PROCESS_PROTECTION_REQUIRED'}
    if([string]$input.authorizationPackagePath-cne'NOT_REQUIRED'-or[string]$input.expectedAuthorizationIdentity-cne'NOT_REQUIRED'-or[string]::IsNullOrWhiteSpace([string]$input.userDecision)-or[string]$input.userDecision-ceq'NOT_REQUIRED'-or[string]$input.recoveryState-cne'FULL_COLD'-or[string]$input.invocationState-cne'PROVEN_EXPLICIT'-or[string]$input.hostEnforcementGrade-cnotin@('FRAMEWORK_GATED','INSTRUCTION_BOUND')){throw 'CURRENT_PIN_PROCESS_READ_ONLY_CONTEXT'}
    $intent=$input.intentEnvelope;$intentRaw=$intent|ConvertTo-Json -Depth 20 -Compress
    Assert-MinimalExactFields $intent $intentRaw @('schemaVersion','objective','requestedActionKind','requestedResultKind','semanticHints','pathHints','capabilityHints','mutationHints','externalHints','ambiguityState') 'current-pin process intent'
    foreach($name in @('semanticHints','pathHints','capabilityHints','mutationHints','externalHints')){if(-not($intent.$name-is[Array])-or@($intent.$name|Where-Object{-not($_-is[string])}).Count-ne0){throw ('CURRENT_PIN_PROCESS_INTENT_ARRAY|'+$name)}}
    $hintCapabilitiesOriginal=@($intent.capabilityHints|ForEach-Object{[string]$_});$hintCapabilities=@($hintCapabilitiesOriginal);[Array]::Sort($hintCapabilities,[StringComparer]::Ordinal)
    if(-not(Test-MinimalJsonInteger $intent.schemaVersion)-or[int]$intent.schemaVersion-ne1-or[string]::IsNullOrWhiteSpace([string]$intent.objective)-or[string]$intent.requestedActionKind-cne'NONE'-or[string]$intent.requestedResultKind-cne'PLAN'-or[string]$intent.ambiguityState-cne'CLEAR'-or[string]::Join("`n",$hintCapabilitiesOriginal)-cne[string]::Join("`n",$hintCapabilities)-or[string]::Join("`n",$hintCapabilities)-cne[string]::Join("`n",$declaredCapabilities)-or@($intent.mutationHints).Count-ne0-or@($intent.externalHints).Count-ne0-or@($intent.pathHints).Count-ne1-or[string]$intent.pathHints[0]-cne[string]$Migration.Relative-or'Framework adoption'-cnotin@($intent.semanticHints)-or'current-pin bridge'-cnotin@($intent.semanticHints)){throw 'CURRENT_PIN_PROCESS_INTENT_NOT_BOUNDED'}
    if([string]$project.id-cne$ProjectId-or[string]$project.frameworkVersion-cne$FromVersion){throw 'CURRENT_PIN_PROJECT_BINDING_DRIFT'}
    $sourceFramework=Join-ChildPath (Join-ChildPath $FrameworkWorkspace 'framework/versions') $FromVersion
    Assert-StableFrameworkRelease $sourceFramework $FromVersion
    $toolchainRaw=Read-StrictUtf8NoBom (Join-ChildPath $sourceFramework 'TOOLCHAIN.json');try{$toolchain=$toolchainRaw|ConvertFrom-Json}catch{throw 'CURRENT_PIN_TOOLCHAIN_JSON'}
    $backend=@($toolchain.officialBackends);if($backend.Count-ne1-or[string]$backend[0].id-cne'powershell7'-or$null-eq$backend[0].entrypoints.PSObject.Properties['PROCESS_REQUIREMENTS_RESOLVE']-or[string]$backend[0].entrypoints.PROCESS_REQUIREMENTS_RESOLVE-cne'scripts/resolve-process-requirements.ps1'){throw 'CURRENT_PIN_TOOLCHAIN_PROCESS_ENTRYPOINT'}
    $resolver=Join-ChildPath $sourceFramework ([string]$backend[0].entrypoints.PROCESS_REQUIREMENTS_RESOLVE);$pwsh=[Environment]::ProcessPath
    if([string]::IsNullOrWhiteSpace($pwsh)){throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE'}
    $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$resolverOutput=@(& $pwsh -NoProfile -NonInteractive -File $resolver -InputPath $CurrentProcessInputPath -AsJson 2>&1|ForEach-Object{[string]$_});$resolverCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
    if($resolverOutput.Count-ne1-or$resolverCode-notin@(0,2)){throw ('CURRENT_PIN_PROCESS_RESOLVER_RESULT_INVALID|code='+$resolverCode+'|output='+($resolverOutput-join';'))}
    try{$resolverResult=$resolverOutput[0]|ConvertFrom-Json}catch{throw 'CURRENT_PIN_PROCESS_RESOLVER_OUTPUT_JSON'}
    $resolverNames=@($resolverResult.PSObject.Properties.Name)
    $resolverReason=if($resolverCode-eq0-and[string]$resolverResult.status-cin@('PASS','EVALUATION_ONLY')){'PASS'}elseif($resolverCode-eq2-and[string]$resolverResult.status-ceq'FAIL'-and[string]$resolverResult.reason-clike'SELECTED_RULE_PACK_BUDGET_EXCEEDED*'){'SELECTED_RULE_PACK_BUDGET_EXCEEDED'}else{throw 'CURRENT_PIN_PROCESS_RESOLVER_RESULT_INVALID'}
    $taskRaw=Read-StrictUtf8NoBom $Migration.Path;$route=[regex]::Matches($taskRaw,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$');$profile=[regex]::Matches($taskRaw,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL);')
    if($route.Count-ne1-or$profile.Count-ne1-or[string]$route[0].Groups['actor'].Value-cne[string]$Migration.Actor){throw 'CURRENT_PIN_PROCESS_TASK_ROUTE'}
    $modulePath=Join-ChildPath $sourceFramework 'scripts/ProcessRequirementComposition.psm1';$module=Import-Module $modulePath -Force -PassThru
    try{$semanticObjective=([string]$intent.objective+' '+[string]::Join(' ',@($intent.semanticHints+$intent.externalHints))).Trim();$composition=Invoke-ProcessRequirementComposition -ProjectRoot $RepositoryRoot -FrameworkRoot $FrameworkWorkspace -TargetVersion $FromVersion -ExpectedProjectConfigIdentity ([string]$input.expectedProjectConfigIdentity) -ExpectedCorrectionsIdentity ([string]$input.expectedCorrectionsIdentity) -Profile ([string]$profile[0].Groups['profile'].Value) -Role ([string]$route[0].Groups['role'].Value) -Phase ([string]$route[0].Groups['phase'].Value) -Actor ([string]$Migration.Actor) -TaskIdentity ([string]$Migration.OldIdentity) -Capabilities @($declaredCapabilities) -Objective $semanticObjective -ActionKind 'NONE' -ResultKind 'PLAN' -ExactPaths @($input.exactPaths) -EvaluationOnly}finally{if($null-ne$module){Remove-Module $module -Force}}
    if([string]$composition.status-cnotin@('PASS','EVALUATION_ONLY')-or[int]$composition.sourceBuildCount-ne1-or@($composition.selectedRequirements).Count-lt1){throw 'CURRENT_PIN_PROCESS_COMPOSER_FAILED'}
    foreach($requirement in @($composition.selectedRequirements)){if(-not($requirement-is[pscustomobject])-or[string]::IsNullOrWhiteSpace([string]$requirement.requirementId)-or[string]::IsNullOrWhiteSpace([string]$requirement.fullText)-or-not($requirement.preparationRequirements-is[Array])-or-not($requirement.resultRequirements-is[Array])){throw 'CURRENT_PIN_PROCESS_COMPLETE_PACK_REQUIRED'}}
    $packJson=@($composition.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress;$packBytes=$utf8NoBom.GetByteCount($packJson)
    $legacyCorrectionsFullReadCount=if($null-ne$composition.PSObject.Properties['legacyCorrectionsFullReadCount']){[int]$composition.legacyCorrectionsFullReadCount}else{0}
    $legacyProjectCustomFullReadCount=if($null-ne$composition.PSObject.Properties['legacyProjectCustomFullReadCount']){[int]$composition.legacyProjectCustomFullReadCount}else{0}
    $compositionCeilings=if($null-ne$composition.PSObject.Properties['evidenceCeilings']){@($composition.evidenceCeilings)}else{@()}
    $legacyCompatibilityEligible=$legacyCorrectionsFullReadCount-eq1-and$legacyProjectCustomFullReadCount-eq0-and'SOURCE_RECORD_IDENTITY_MISMATCH_RETAINED'-cnotin$compositionCeilings
    $ordinaryCeiling=if($null-ne$script:ActiveAdoptionProfile){[int]$script:ActiveAdoptionProfile.processBudgets.ordinarySelectedPackBytes}else{32768}
    $absoluteCeiling=if($null-ne$script:ActiveAdoptionProfile){[int]$script:ActiveAdoptionProfile.processBudgets.absoluteSelectedPackBytes}else{65536}
    $targetCeiling=if($null-ne$script:ActiveAdoptionProfile-and$legacyCompatibilityEligible){[int]$script:ActiveAdoptionProfile.processBudgets.legacySchema1CorrectionCompatibilityBytes}else{$absoluteCeiling}
    if($packBytes-gt$targetCeiling){throw 'CURRENT_PIN_PROCESS_COMPLETE_PACK_EXCEEDS_TARGET_CEILING'}
    $budgetMode=if($packBytes-le$ordinaryCeiling){'ORDINARY'}elseif($legacyCompatibilityEligible-and$null-ne$script:ActiveAdoptionProfile){'LEGACY_SCHEMA1_CORRECTION_COMPATIBILITY'}else{'ABSOLUTE'}
    return [pscustomobject]@{UserDecision=[string]$input.userDecision;ResolverReason=$resolverReason;Capabilities=@($declaredCapabilities);BudgetMode=$budgetMode;SelectedRequirementCount=@($composition.selectedRequirements).Count;SelectedPackBytes=$packBytes;SelectedPackIdentity=(Get-UpperSha256Bytes ($utf8NoBom.GetBytes($packJson)));SourceCompositionIdentity=[string]$composition.sourceCompositionIdentity}
}

function Get-TargetProjectedProcessPreflight([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetVersion,[string]$ProjectId,$Migration,[string]$TargetProject,[string]$TargetBootstrap,[string]$TargetCorrections,[string]$TargetPolicy,[string]$ControllerPath) {
    if($null-eq$Migration){throw 'TARGET_PROJECTED_PROCESS_TASK_REQUIRED'}
    $userDecision=$null
    if(-not[string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-and-not[string]::IsNullOrWhiteSpace($ExpectedAuthorizationPackageIdentity)){
        if(-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne$ExpectedAuthorizationPackageIdentity){throw 'TARGET_PROJECTED_PROCESS_AUTHORIZATION_DRIFT'}
        $authorizationRaw=Read-StrictUtf8NoBom $AuthorizationPackagePath;try{$authorization=$authorizationRaw|ConvertFrom-Json}catch{throw 'TARGET_PROJECTED_PROCESS_AUTHORIZATION_JSON'};$userDecision=[string]$authorization.userConfirmation
    }elseif(-not[string]::IsNullOrWhiteSpace($CurrentProcessInputPath)-and-not[string]::IsNullOrWhiteSpace($ExpectedCurrentProcessInputIdentity)){
        if(-not(Test-Path -LiteralPath $CurrentProcessInputPath -PathType Leaf)-or(Get-MinimalFileIdentity $CurrentProcessInputPath)-cne$ExpectedCurrentProcessInputIdentity){throw 'TARGET_PROJECTED_PROCESS_INPUT_DRIFT'}
        $legacyInput=Read-StrictUtf8NoBom $CurrentProcessInputPath|ConvertFrom-Json;$userDecision=[string]$legacyInput.userDecision
    }
    if([string]::IsNullOrWhiteSpace($userDecision)){throw 'TARGET_PROJECTED_PROCESS_USER_DECISION'}
    try{$targetConfigObject=$TargetProject|ConvertFrom-Json}catch{throw 'TARGET_PROJECTED_PROCESS_PROJECT_JSON'}
    $maintenanceLayout=[string]$targetConfigObject.controlPlaneLayout-ceq'framework-maintenance-sibling'
    $projection=Join-Path ([IO.Path]::GetTempPath()) ('aiw-target-preflight-'+[guid]::NewGuid().ToString('N'))
    try{
        New-Item -ItemType Directory -Path $projection -Force|Out-Null
        if($maintenanceLayout){
            $projectedControl=Join-Path $projection 'Control';$projectedFramework=Join-Path $projection ([string]$targetConfigObject.frameworkTarget.siblingDirectory)
            New-Item -ItemType Directory -Path $projectedControl,$projectedFramework -Force|Out-Null
            foreach($gitRoot in @($projectedControl,$projectedFramework)){$gitOutput=@(& git -C $gitRoot init --quiet 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0){throw ('TARGET_PROJECTED_PROCESS_GIT_INIT|'+($gitOutput-join';'))}}
            Copy-Item -LiteralPath (Join-Path $RepositoryRoot '.ai-workspace') -Destination (Join-Path $projectedControl '.ai-workspace') -Recurse -Force
            New-Item -ItemType Directory -Path (Join-Path $projectedFramework 'framework\versions') -Force|Out-Null
            Copy-Item -LiteralPath (Join-ChildPath $FrameworkWorkspace ('framework/versions/'+$TargetVersion)) -Destination (Join-Path $projectedFramework ('framework\versions\'+$TargetVersion)) -Recurse -Force
            Write-ProjectedText (Join-Path $projectedFramework 'README.md') "# Projected Framework target`n";Write-ProjectedText (Join-Path $projectedFramework 'AGENTS.md') "# Projected target navigation`n"
            $projectRoot=$projectedControl;$frameworkRootProjected=$projectedFramework
        }else{
            $projectRoot=$projection;$frameworkRootProjected=$FrameworkWorkspace
            Copy-Item -LiteralPath (Join-Path $RepositoryRoot '.ai-workspace') -Destination (Join-Path $projectRoot '.ai-workspace') -Recurse -Force
            $gitOutput=@(& git -C $projectRoot init --quiet 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0){throw ('TARGET_PROJECTED_PROCESS_GIT_INIT|'+($gitOutput-join';'))}
        }
        $projectPath=Join-Path $projectRoot '.ai-workspace\project.json';$bootstrapPath=Join-Path $projectRoot '.ai-workspace\BOOTSTRAP.md';$correctionsPath=Join-Path $projectRoot '.ai-workspace\corrections.json';$policyPath=Join-Path $projectRoot '.ai-workspace\process-policy.json';$controllerProjected=Join-Path $projectRoot '.ai-workspace\controller.json';$taskPath=Join-ChildPath $projectRoot ([string]$Migration.Relative)
        Write-ProjectedText $projectPath $TargetProject;Write-ProjectedText $bootstrapPath $TargetBootstrap;Write-ProjectedText $correctionsPath $TargetCorrections;Write-ProjectedText $policyPath $TargetPolicy;[IO.File]::Copy($ControllerPath,$controllerProjected,$true);Write-ProjectedText $taskPath ([string]$Migration.Content)
        $projectRaw=Read-StrictUtf8NoBom $projectPath;$project=$projectRaw|ConvertFrom-Json;$capabilities=@(Get-ExactEnabledCapabilityIds $project $projectRaw)
        $input=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$projectRoot;frameworkRoot=$frameworkRootProjected;taskPath=$taskPath;expectedProjectConfigIdentity=(Get-MinimalFileIdentity $projectPath);expectedCorrectionsIdentity=(Get-MinimalFileIdentity $correctionsPath);expectedTaskIdentity=(Get-MinimalFileIdentity $taskPath);observedActor=[string]$Migration.Actor;capabilities=$capabilities;exactPaths=@([string]$Migration.Relative);forbiddenPaths=@('src/','tests/','assets/','docs/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision=$userDecision;recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Validate the complete target Framework process pack before changing the project pin.';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('Framework adoption','target-before-pin');pathHints=@([string]$Migration.Relative);capabilityHints=$capabilities;mutationHints=@();externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$true}
        $inputPath=Join-Path $projection 'aiw-target-preflight-input.json';Write-Utf8NoBom $inputPath ($input|ConvertTo-Json -Depth 30)
        $targetFramework=Join-ChildPath $frameworkRootProjected ('framework/versions/'+$TargetVersion);$toolchainRaw=Read-StrictUtf8NoBom (Join-ChildPath $targetFramework 'TOOLCHAIN.json');try{$toolchain=$toolchainRaw|ConvertFrom-Json}catch{throw 'TARGET_PROJECTED_PROCESS_TOOLCHAIN_JSON'}
        $backend=@($toolchain.officialBackends);if($backend.Count-ne1-or[string]$backend[0].id-cne'powershell7'-or$null-eq$backend[0].entrypoints.PSObject.Properties['PROCESS_REQUIREMENTS_RESOLVE']){throw 'TARGET_PROJECTED_PROCESS_TOOLCHAIN_ENTRYPOINT'}
        $resolver=Join-ChildPath $targetFramework ([string]$backend[0].entrypoints.PROCESS_REQUIREMENTS_RESOLVE);$pwsh=[Environment]::ProcessPath;if([string]::IsNullOrWhiteSpace($pwsh)){throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE'}
        $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$output=@(& $pwsh -NoProfile -NonInteractive -File $resolver -InputPath $inputPath -AsJson 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
        if($code-ne0-or$output.Count-ne1){throw ('TARGET_PROJECTED_PROCESS_REJECTED|code='+$code+'|output='+($output-join';'))}
        try{$result=$output[0]|ConvertFrom-Json}catch{throw 'TARGET_PROJECTED_PROCESS_OUTPUT_JSON'}
        if([string]$result.status-cnotin@('PASS','EVALUATION_ONLY')-or$null-eq$result.compactReceipt-or[string]$result.compactReceipt.frameworkVersion-cne$TargetVersion-or[int]$result.compactReceipt.selectedPackCeilingBytes-ne$SelectedRulePackBytes){throw 'TARGET_PROJECTED_PROCESS_RESULT_INVALID'}
        return [pscustomobject]@{UserDecision=$userDecision;ResolverReason='PASS';Capabilities=$capabilities;BudgetMode='PROJECT_SELECTED';SelectedRequirementCount=@($result.selectedRuleBlocks).Count;SelectedPackBytes=[int]$result.compactReceipt.selectedPackBytes;SelectedPackIdentity=[string]$result.compactReceipt.selectionIdentity;SourceCompositionIdentity=[string]$result.compactReceipt.sourceCompositionIdentity}
    }finally{if(Test-Path -LiteralPath $projection -PathType Container){Remove-Item -LiteralPath $projection -Recurse -Force}}
}

function Get-CurrentTaskBinding([string]$RepositoryRoot,[string]$TargetVersion,[string]$RelativePath,[string]$ExpectedIdentity,[string]$Actor,[string]$RequiredLifecycle='ACTIVE') {
    $provided=@(-not[string]::IsNullOrWhiteSpace($RelativePath),-not[string]::IsNullOrWhiteSpace($ExpectedIdentity),-not[string]::IsNullOrWhiteSpace($Actor))
    if(@($provided|Where-Object{$_}).Count-ne3){throw 'CURRENT_TASK_BINDING_FIELDS_REQUIRED'}
    if($RelativePath-cne$RelativePath.Replace('\','/')-or$RelativePath-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'-or[IO.Path]::IsPathRooted($RelativePath)-or$RelativePath.Contains(':')){throw 'CURRENT_TASK_ACTIVE_PATH_REQUIRED'}
    if($ExpectedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'CURRENT_TASK_IDENTITY'}
    $path=Join-ChildPath $RepositoryRoot $RelativePath
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-MinimalFileIdentity $path)-cne$ExpectedIdentity){throw 'CURRENT_TASK_DRIFT'}
    $raw=Read-StrictUtf8NoBom $path
    $header=[regex]::Matches($raw,'(?m)^#\s+(?<task>[0-9A-Za-z][0-9A-Za-z._-]*)\s+[-—]')
    $owner=[regex]::Matches($raw,'(?m)^- Owner:\s*`?(?<owner>[^`\r\n]+?)`?\s*$')
    $range=[regex]::Matches($raw,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL);\s*lifecycle=(?<lifecycle>ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED);(?:\s*current_exact=(?<exact>[^;]+);)?\s*expected_paths=\[(?<expected>[^\]]*)\];\s*actual_paths=\[(?<actual>[^\]]*)\]\s*$')
    $route=[regex]::Matches($raw,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
    $schema=[regex]::Matches($raw,'(?m)^- Task schema:\s*'+[regex]::Escape($TargetVersion)+'\s*$')
    $fileTask=[IO.Path]::GetFileNameWithoutExtension($RelativePath)
    if($RequiredLifecycle-cnotin@('ACTIVE','REVIEW')){throw 'CURRENT_TASK_LIFECYCLE_REQUIRED'}
    if($header.Count-ne1-or[string]$header[0].Groups['task'].Value-cne$fileTask-or$owner.Count-ne1-or[string]::IsNullOrWhiteSpace([string]$owner[0].Groups['owner'].Value)-or$range.Count-ne1-or[string]$range[0].Groups['lifecycle'].Value-cne$RequiredLifecycle-or$route.Count-ne1-or[string]$route[0].Groups['actor'].Value-cne$Actor-or$schema.Count-ne1){throw 'CURRENT_TASK_BINDING_REQUIRED'}
    $actualPaths=if([string]::IsNullOrWhiteSpace([string]$range[0].Groups['actual'].Value)){@()}else{@([string]$range[0].Groups['actual'].Value -split '\|')}
    return [pscustomobject]@{Relative=$RelativePath;Path=$path;OldIdentity=$ExpectedIdentity;Actor=$Actor;TaskId=$fileTask;Owner=[string]$owner[0].Groups['owner'].Value;Profile=[string]$range[0].Groups['profile'].Value;Role=[string]$route[0].Groups['role'].Value;Phase=[string]$route[0].Groups['phase'].Value;ActualPaths=$actualPaths}
}

function Get-SelectedRulePackBudgetRepair([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectId,[string]$ProjectFile,[string]$CorrectionsFile,$TaskBinding,[bool]$ApplyChange) {
    if([string]::IsNullOrWhiteSpace($CurrentProcessInputPath)-or[string]::IsNullOrWhiteSpace($ExpectedCurrentProcessInputIdentity)){throw 'RULE_PACK_BUDGET_REPAIR_PROCESS_INPUT_REQUIRED'}
    if($ExpectedCurrentProcessInputIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $CurrentProcessInputPath -PathType Leaf)-or(Get-MinimalFileIdentity $CurrentProcessInputPath)-cne$ExpectedCurrentProcessInputIdentity){throw 'RULE_PACK_BUDGET_REPAIR_PROCESS_INPUT_DRIFT'}
    $inputRaw=Read-StrictUtf8NoBom $CurrentProcessInputPath;Assert-StrictJsonMemberSet $inputRaw 'RULE_PACK_BUDGET_REPAIR_PROCESS_DUPLICATE_MEMBER'
    try{$input=$inputRaw|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_PROCESS_JSON'}
    $inputFields=@('schemaVersion','mode','projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities','exactPaths','forbiddenPaths','protectedPaths','authorizationPackagePath','expectedAuthorizationIdentity','userDecision','recoveryState','hostEnforcementGrade','invocationState','intentEnvelope','evaluationOnly')
    $inputNames=@($input.PSObject.Properties.Name)
    if(-not($input-is[pscustomobject])-or$inputNames.Count-ne$inputFields.Count-or@($inputFields|Where-Object{$_-cnotin$inputNames}).Count-ne0){throw 'RULE_PACK_BUDGET_REPAIR_PROCESS_FIELDS'}
    $expectedAction=if($ApplyChange){'CONTROL_WRITE'}else{'NONE'};$expectedResult=if($ApplyChange){'IMPLEMENTATION_RESULT'}else{'PLAN'}
    if(-not(Test-MinimalJsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-ne2-or[string]$input.mode-cne'DISCOVER'-or-not($input.evaluationOnly-is[bool])-or[bool]$input.evaluationOnly-ne(-not$ApplyChange)){throw 'RULE_PACK_BUDGET_REPAIR_PROCESS_MODE'}
    $repository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot));$workspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($FrameworkWorkspace))
    $inputRepository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.projectRoot))));$inputWorkspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.frameworkRoot))));$inputTask=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.taskPath)) )
    if($inputRepository-cne$repository-or$inputWorkspace-cne$workspace-or$inputTask-cne[IO.Path]::GetFullPath([string]$TaskBinding.Path)){throw 'RULE_PACK_BUDGET_REPAIR_SCOPE_DRIFT'}
    if([string]$input.expectedProjectConfigIdentity-cne(Get-MinimalFileIdentity $ProjectFile)-or[string]$input.expectedCorrectionsIdentity-cne(Get-MinimalFileIdentity $CorrectionsFile)-or[string]$input.expectedTaskIdentity-cne[string]$TaskBinding.OldIdentity-or[string]$input.observedActor-cne[string]$TaskBinding.Actor){throw 'RULE_PACK_BUDGET_REPAIR_BINDING_DRIFT'}
    if(@($input.exactPaths).Count-ne1-or[string]$input.exactPaths[0]-cne'.ai-workspace/process-policy.json'){throw 'RULE_PACK_BUDGET_REPAIR_EXACT_POLICY_REQUIRED'}
    foreach($name in @('capabilities','forbiddenPaths','protectedPaths')){if(-not($input.$name-is[Array])-or@($input.$name|Where-Object{-not($_-is[string])}).Count-ne0){throw ('RULE_PACK_BUDGET_REPAIR_ARRAY|'+$name)}}
    $projectRaw=Read-StrictUtf8NoBom $ProjectFile;try{$project=$projectRaw|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_PROJECT_JSON'}
    if([string]$project.id-cne$ProjectId-or[string]$project.frameworkVersion-cne$TargetVersion){throw 'RULE_PACK_BUDGET_REPAIR_PROJECT_BINDING'}
    $declaredCapabilities=@(Get-ExactEnabledCapabilityIds $project $projectRaw);$inputCapabilities=@($input.capabilities|ForEach-Object{[string]$_});[Array]::Sort($inputCapabilities,[StringComparer]::Ordinal)
    if([string]::Join("`n",$inputCapabilities)-cne[string]::Join("`n",$declaredCapabilities)){throw 'RULE_PACK_BUDGET_REPAIR_CAPABILITY_DRIFT'}
    $intent=$input.intentEnvelope;$intentRaw=$intent|ConvertTo-Json -Depth 20 -Compress
    Assert-MinimalExactFields $intent $intentRaw @('schemaVersion','objective','requestedActionKind','requestedResultKind','semanticHints','pathHints','capabilityHints','mutationHints','externalHints','ambiguityState') 'Rule-pack budget repair intent'
    if(-not(Test-MinimalJsonInteger $intent.schemaVersion)-or[int]$intent.schemaVersion-ne1-or[string]::IsNullOrWhiteSpace([string]$intent.objective)-or[string]$intent.requestedActionKind-cne$expectedAction-or[string]$intent.requestedResultKind-cne$expectedResult-or[string]$intent.ambiguityState-cne'CLEAR'-or@($intent.pathHints).Count-ne1-or[string]$intent.pathHints[0]-cne'.ai-workspace/process-policy.json'-or@($intent.externalHints).Count-ne0-or'Selected rule-pack budget repair'-cnotin@($intent.semanticHints)){throw 'RULE_PACK_BUDGET_REPAIR_INTENT_NOT_BOUNDED'}
    if($ApplyChange){
        if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or[string]::IsNullOrWhiteSpace($ExpectedAuthorizationPackageIdentity)-or[IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.authorizationPackagePath)))-cne[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $AuthorizationPackagePath))-or[string]$input.expectedAuthorizationIdentity-cne$ExpectedAuthorizationPackageIdentity-or[string]$input.userDecision-ceq'NOT_REQUIRED'){throw 'RULE_PACK_BUDGET_REPAIR_AUTHORIZATION_BINDING'}
    }elseif([string]$input.authorizationPackagePath-cne'NOT_REQUIRED'-or[string]$input.expectedAuthorizationIdentity-cne'NOT_REQUIRED') { throw 'RULE_PACK_BUDGET_REPAIR_PREVIEW_AUTHORITY' }
    $resolver=Join-ChildPath $TargetFramework 'scripts/resolve-process-requirements.ps1';$pwsh=[Environment]::ProcessPath;$oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$currentOutput=@(& $pwsh -NoProfile -NonInteractive -File $resolver -InputPath $CurrentProcessInputPath -AsJson 2>&1|ForEach-Object{[string]$_});$currentCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
    if($currentCode-ne2-or$currentOutput.Count-ne1){throw ('RULE_PACK_BUDGET_REPAIR_CURRENT_DISCOVER_NOT_BLOCKED|'+($currentOutput-join';'))}
    try{$currentResult=$currentOutput[0]|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_CURRENT_DISCOVER_JSON'}
    $match=[regex]::Match([string]$currentResult.reason,'^SELECTED_RULE_PACK_BUDGET_EXCEEDED\|bytes=(?<required>\d+)\|ceiling=(?<configured>\d+)$')
    if(-not$match.Success){throw 'RULE_PACK_BUDGET_REPAIR_CURRENT_DISCOVER_REASON'}
    $required=[int]$match.Groups['required'].Value;$configured=[int]$match.Groups['configured'].Value;$absolute=[int]$script:ActiveAdoptionProfile.processBudget.absoluteSelectedRulePackBytes
    if($SelectedRulePackBytes-le$configured-or$SelectedRulePackBytes-lt$required-or$SelectedRulePackBytes-gt$absolute){throw ('RULE_PACK_BUDGET_REPAIR_PROPOSED_INVALID|required='+$required+'|configured='+$configured+'|proposed='+$SelectedRulePackBytes+'|absolute='+$absolute)}
    $policyPath=Join-ChildPath $RepositoryRoot '.ai-workspace/process-policy.json';$policyRaw=Read-StrictUtf8NoBom $policyPath;Assert-StrictJsonMemberSet $policyRaw 'RULE_PACK_BUDGET_REPAIR_POLICY_DUPLICATE_MEMBER'
    try{$policy=$policyRaw|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_POLICY_JSON'}
    if(-not(Test-MinimalJsonInteger $policy.selectedRulePackBytes)-or[int]$policy.selectedRulePackBytes-ne$configured){throw 'RULE_PACK_BUDGET_REPAIR_POLICY_DRIFT'}
    $pattern='("selectedRulePackBytes"\s*:\s*)'+[regex]::Escape([string]$configured)+'(?=\s*[,}])';if([regex]::Matches($policyRaw,$pattern).Count-ne1){throw 'RULE_PACK_BUDGET_REPAIR_POLICY_TEXT'}
    $candidateRaw=[regex]::Replace($policyRaw,$pattern,('${1}'+[string]$SelectedRulePackBytes),1);try{$candidate=$candidateRaw|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_PROJECTED_POLICY_JSON'}
    $policy.selectedRulePackBytes=$SelectedRulePackBytes
    if(($policy|ConvertTo-Json -Depth 50 -Compress)-cne($candidate|ConvertTo-Json -Depth 50 -Compress)){throw 'RULE_PACK_BUDGET_REPAIR_NON_BUDGET_DRIFT'}
    $candidateIdentity=Get-MinimalBytesIdentity ($utf8NoBom.GetBytes($candidateRaw))
    $projection=Join-Path ([IO.Path]::GetTempPath()) ('aiw-budget-repair-'+[guid]::NewGuid().ToString('N'))
    try{
        New-Item -ItemType Directory -Path $projection|Out-Null;& git -C $projection init -q;if($LASTEXITCODE-ne0){throw 'RULE_PACK_BUDGET_REPAIR_PROJECTION_GIT'}
        $projectionControl=Join-Path $projection '.ai-workspace';New-Item -ItemType Directory -Path $projectionControl|Out-Null
        foreach($source in @($ProjectFile,(Join-ChildPath $RepositoryRoot '.ai-workspace/controller.json'),$CorrectionsFile,(Join-ChildPath $RepositoryRoot '.ai-workspace/BOOTSTRAP.md'))){if(Test-Path -LiteralPath $source -PathType Leaf){Copy-Item -LiteralPath $source -Destination (Join-Path $projectionControl ([IO.Path]::GetFileName($source)))}}
        [IO.File]::WriteAllText((Join-Path $projectionControl 'process-policy.json'),$candidateRaw,$utf8NoBom)
        $projectedTask=Join-ChildPath $projection ([string]$TaskBinding.Relative);New-Item -ItemType Directory -Path (Split-Path -Parent $projectedTask)-Force|Out-Null;Copy-Item -LiteralPath $TaskBinding.Path -Destination $projectedTask
        $projectedInput=($input|ConvertTo-Json -Depth 50 -Compress|ConvertFrom-Json);$projectedInput.projectRoot=$projection;$projectedInput.taskPath=$projectedTask
        if($ApplyChange){
            $authorizationRaw=Read-StrictUtf8NoBom $AuthorizationPackagePath;try{$authorization=$authorizationRaw|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_AUTHORIZATION_JSON'}
            if(@($authorization.exactPaths).Count-ne1-or[string]$authorization.exactPaths[0]-cne'.ai-workspace/process-policy.json'-or@($authorization.actions).Count-ne1-or[string]$authorization.actions[0]-cne'CONTROL_WRITE'-or@($authorization.objectIdentities).Count-ne1-or[string]$authorization.objectIdentities[0].path-cne'.ai-workspace/process-policy.json'){throw 'RULE_PACK_BUDGET_REPAIR_AUTHORIZATION_SCOPE'}
            $authorization.objectIdentities[0].identity=$candidateIdentity
            $projectedAuthorization=Join-Path $projectionControl 'projected-budget-authorization.json';Write-Utf8NoBom $projectedAuthorization ($authorization|ConvertTo-Json -Depth 50)
            $projectedInput.authorizationPackagePath=$projectedAuthorization;$projectedInput.expectedAuthorizationIdentity=Get-MinimalFileIdentity $projectedAuthorization
        }
        $projectedInputPath=Join-Path $projection 'process-input.json';Write-Utf8NoBom $projectedInputPath ($projectedInput|ConvertTo-Json -Depth 50)
        $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$projectedOutput=@(& $pwsh -NoProfile -NonInteractive -File $resolver -InputPath $projectedInputPath -AsJson 2>&1|ForEach-Object{[string]$_});$projectedCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
        if($projectedCode-ne0-or$projectedOutput.Count-ne1){throw ('RULE_PACK_BUDGET_REPAIR_PROJECTED_DISCOVER_REJECTED|'+($projectedOutput-join';'))}
        try{$projectedResult=$projectedOutput[0]|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_PROJECTED_DISCOVER_JSON'}
        $receipt=$projectedResult.compactReceipt
        if($null-eq$receipt-or[string]$receipt.status-cnotin@('PASS','EVALUATION_ONLY')-or[int]$receipt.selectedPackBytes-ne$required-or[int]$receipt.selectedPackCeilingBytes-ne$SelectedRulePackBytes-or[string]$receipt.sourceBindings.policyIdentity-cne$candidateIdentity){throw 'RULE_PACK_BUDGET_REPAIR_PROJECTED_DISCOVER_INCOMPLETE'}
    }finally{if(Test-Path -LiteralPath $projection){Remove-Item -LiteralPath $projection -Recurse -Force}}
    return [pscustomobject]@{Path=$policyPath;OldIdentity=(Get-MinimalFileIdentity $policyPath);NewIdentity=$candidateIdentity;OldBytes=[IO.File]::ReadAllBytes($policyPath);NewRaw=$candidateRaw;Configured=$configured;Required=$required;Proposed=$SelectedRulePackBytes;Absolute=$absolute;UserDecision=[string]$input.userDecision}
}

function Invoke-SelectedRulePackBudgetRepair($Repair,[bool]$ApplyChange) {
    Write-Output ('RULE_PACK_BUDGET_REPAIR|configured='+$Repair.Configured+'|required='+$Repair.Required+'|proposed='+$Repair.Proposed+'|absolute='+$Repair.Absolute+'|projected=PASS')
    Write-Output ('RULE_PACK_BUDGET_REPAIR_PREIMAGE|.ai-workspace/process-policy.json='+$Repair.OldIdentity)
    Write-Output ('RULE_PACK_BUDGET_REPAIR_POSTIMAGE|.ai-workspace/process-policy.json='+$Repair.NewIdentity)
    if(-not$ApplyChange){Write-Output 'WHAT_IF|objects=1|transaction=atomic-selected-rule-pack-budget-repair';return}
    if((Get-MinimalFileIdentity $Repair.Path)-cne$Repair.OldIdentity){throw 'RULE_PACK_BUDGET_REPAIR_PREFLIGHT_DRIFT'}
    $temp=$Repair.Path+'.budget-repair-'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temp,[string]$Repair.NewRaw,$utf8NoBom)
        if((Get-MinimalFileIdentity $temp)-cne$Repair.NewIdentity){throw 'RULE_PACK_BUDGET_REPAIR_TEMP_DRIFT'}
        [IO.File]::Move($temp,$Repair.Path,$true)
        if((Get-MinimalFileIdentity $Repair.Path)-cne$Repair.NewIdentity){throw 'RULE_PACK_BUDGET_REPAIR_POSTIMAGE_DRIFT'}
        Write-Output ('RULE_PACK_BUDGET_REPAIRED|configured='+$Repair.Configured+'|required='+$Repair.Required+'|selected='+$Repair.Proposed+'|objects=1')
    }catch{
        if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}
        if((Get-MinimalFileIdentity $Repair.Path)-cne$Repair.OldIdentity){[IO.File]::WriteAllBytes($Repair.Path,[byte[]]$Repair.OldBytes)}
        throw
    }
}

function Assert-ProjectCorrectionsMigrationCandidate($Source,[string]$SourceRaw,$Candidate,[string]$CandidateRaw,[string]$TargetVersion,[string]$ProjectId,[string]$Label) {
    $topFields=@('schemaVersion','contractVersion','projectId','corrections')
    Assert-MinimalExactFields $Candidate $CandidateRaw $topFields $Label
    $contract=Get-ProcessCarrierContractVersion $TargetVersion
    if(-not(Test-MinimalJsonInteger $Candidate.schemaVersion)-or[int]$Candidate.schemaVersion-ne2-or[string]$Candidate.contractVersion-cne$contract-or[string]$Candidate.projectId-cne$ProjectId-or-not($Candidate.corrections-is[Array])){throw 'PROJECT_CORRECTIONS_MIGRATION_TARGET_SCHEMA'}
    if(@($Source.corrections).Count-ne@($Candidate.corrections).Count){throw 'PROJECT_CORRECTIONS_MIGRATION_RECORD_SET'}
    $historical=@('correctionId','introducedAgainstFramework','requirementReason','effectiveRule','applicability','decisionLocator')
    $candidateFields=@($historical+@('selectors','preparationRequirements','resultRequirements','requiredFacts','mechanicalCheckRefs'))
    for($index=0;$index-lt@($Source.corrections).Count;$index++){
        $sourceRecord=@($Source.corrections)[$index];$candidateRecord=@($Candidate.corrections)[$index]
        Assert-MinimalExactFields $sourceRecord ($sourceRecord|ConvertTo-Json -Depth 20 -Compress) $historical 'Current correction record'
        Assert-MinimalExactFields $candidateRecord ($candidateRecord|ConvertTo-Json -Depth 50 -Compress) $candidateFields 'Candidate correction record'
        foreach($name in $historical){if(-not($sourceRecord.$name-is[string])-or[string]$sourceRecord.$name-cne[string]$candidateRecord.$name){throw ('PROJECT_CORRECTIONS_MIGRATION_HISTORICAL_DRIFT|'+[string]$sourceRecord.correctionId+'|'+$name)}}
    }
}

function Get-ProjectCorrectionsProjectedDiscover([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectFile,[string]$BootstrapFile,[string]$ControllerFile,$TaskBinding,$InputTemplate,[string]$CandidateRaw,[string]$CandidateIdentity,[bool]$MigrationEvaluation) {
    $projectionRoot=Join-Path ([IO.Path]::GetTempPath()) ('aiw-project-corrections-migration-'+[guid]::NewGuid().ToString('N'));$projectionControl=Join-Path $projectionRoot '.ai-workspace'
    try{
        New-Item -ItemType Directory -Path $projectionControl -Force|Out-Null
        foreach($source in @($ProjectFile,$BootstrapFile,$ControllerFile)){Copy-Item -LiteralPath $source -Destination (Join-Path $projectionControl ([IO.Path]::GetFileName($source)))}
        $policy=Join-ChildPath $RepositoryRoot '.ai-workspace/process-policy.json';if(Test-Path -LiteralPath $policy -PathType Leaf){Copy-Item -LiteralPath $policy -Destination (Join-Path $projectionControl 'process-policy.json')}
        [IO.File]::WriteAllText((Join-Path $projectionControl 'corrections.json'),$CandidateRaw,$utf8NoBom)
        $projectedTask=Join-ChildPath $projectionRoot ([string]$TaskBinding.Relative);New-Item -ItemType Directory -Path (Split-Path -Parent $projectedTask) -Force|Out-Null;Copy-Item -LiteralPath $TaskBinding.Path -Destination $projectedTask
        $input=($InputTemplate|ConvertTo-Json -Depth 50 -Compress|ConvertFrom-Json)
        $input.projectRoot=$projectionRoot;$input.frameworkRoot=$FrameworkWorkspace;$input.taskPath=$projectedTask;$input.expectedCorrectionsIdentity=$CandidateIdentity
        if($MigrationEvaluation){
            $input.exactPaths=@('.ai-workspace/corrections.json');$input.authorizationPackagePath='NOT_REQUIRED';$input.expectedAuthorizationIdentity='NOT_REQUIRED';$input.evaluationOnly=$true
            $input.intentEnvelope.objective='Validate the repaired project corrections candidate as the projected current authority';$input.intentEnvelope.requestedActionKind='NONE';$input.intentEnvelope.requestedResultKind='PLAN';$input.intentEnvelope.semanticHints=@('Project corrections migration','same-version project-control migration');$input.intentEnvelope.pathHints=@('.ai-workspace/corrections.json');$input.intentEnvelope.mutationHints=@();$input.intentEnvelope.externalHints=@();$input.intentEnvelope.ambiguityState='CLEAR'
        }
        $projectedInput=Join-Path $projectionRoot 'process-input.json';[IO.File]::WriteAllText($projectedInput,(Normalize-Text ($input|ConvertTo-Json -Depth 50)),$utf8NoBom)
        $resolver=Join-ChildPath $TargetFramework 'scripts/resolve-process-requirements.ps1';$pwsh=[Environment]::ProcessPath
        if([string]::IsNullOrWhiteSpace($pwsh)){throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE'}
        $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$projectedOutput=@(& $pwsh -NoProfile -NonInteractive -File $resolver -InputPath $projectedInput -AsJson 2>&1|ForEach-Object{[string]$_});$projectedCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
        if($projectedCode-ne0-or$projectedOutput.Count-ne1){throw ('PROJECT_CORRECTIONS_MIGRATION_PROJECTED_DISCOVER_REJECTED|'+($projectedOutput-join';'))}
        try{$projectedResult=$projectedOutput[0]|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_PROJECTED_DISCOVER_JSON'}
        $receipt=if($null-ne$projectedResult.PSObject.Properties['compactReceipt']){$projectedResult.compactReceipt}else{$projectedResult}
        $ordinaryCeiling=if($null-ne$script:ActiveAdoptionProfile.PSObject.Properties['processBudget']){[int]$script:ActiveAdoptionProfile.processBudget.defaultSelectedRulePackBytes}else{[int]$script:ActiveAdoptionProfile.processBudgets.ordinarySelectedPackBytes}
        if([string]$receipt.status-cnotin@('PASS','EVALUATION_ONLY')-or[int]$receipt.sourceBuildCount-ne1-or[int]$receipt.legacyCorrectionsFullReadCount-ne0-or[int]$receipt.selectedPackBytes-gt$ordinaryCeiling-or[string]$receipt.sourceBindings.correctionsIdentity-cne$CandidateIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_PROJECTED_DISCOVER_INCOMPLETE'}
        return $receipt
    }finally{if(Test-Path -LiteralPath $projectionRoot){Remove-Item -LiteralPath $projectionRoot -Recurse -Force}}
}

function Get-SameVersionCorrectionsMigration([string]$RepositoryRoot,[string]$FrameworkWorkspace,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectId,[string]$ProjectFile,[string]$BootstrapFile,[string]$ControllerFile,$TaskBinding,[bool]$RepairAdmission) {
    $provided=@(-not[string]::IsNullOrWhiteSpace($ProjectCorrectionsMigrationPath),-not[string]::IsNullOrWhiteSpace($ExpectedProjectCorrectionsMigrationIdentity))
    if(@($provided|Where-Object{$_}).Count-ne2){throw 'PROJECT_CORRECTIONS_MIGRATION_FIELDS_REQUIRED'}
    if($ExpectedProjectCorrectionsMigrationIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $ProjectCorrectionsMigrationPath -PathType Leaf)){throw 'PROJECT_CORRECTIONS_MIGRATION_INPUT'}
    Assert-MinimalPathInsideRepo $RepositoryRoot $ProjectCorrectionsMigrationPath
    if((Get-MinimalFileIdentity $ProjectCorrectionsMigrationPath)-cne$ExpectedProjectCorrectionsMigrationIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_INPUT_DRIFT'}
    $repositoryResolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot));$candidateResolved=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectCorrectionsMigrationPath));$candidateRelative=$candidateResolved.Substring($repositoryResolved.Length+1).Replace('\','/')
    $correctionsFile=Join-ChildPath $RepositoryRoot '.ai-workspace/corrections.json'
    if(-not(Test-Path -LiteralPath $correctionsFile -PathType Leaf)){throw 'PROJECT_CORRECTIONS_MIGRATION_SOURCE_MISSING'}
    $oldIdentity=Get-MinimalFileIdentity $correctionsFile
    if($oldIdentity-ceq$ExpectedProjectCorrectionsMigrationIdentity){throw 'PROJECT_CORRECTIONS_ALREADY_MIGRATED'}
    $oldRaw=Read-StrictUtf8NoBom $correctionsFile;$candidateRaw=Read-StrictUtf8NoBom $ProjectCorrectionsMigrationPath
    if($candidateRaw.Contains("`r")-or-not$candidateRaw.EndsWith("`n")){throw 'PROJECT_CORRECTIONS_MIGRATION_TEXT_FORMAT'}
    Assert-StrictJsonMemberSet $oldRaw 'PROJECT_CORRECTIONS_SOURCE_DUPLICATE_MEMBER';Assert-StrictJsonMemberSet $candidateRaw 'PROJECT_CORRECTIONS_MIGRATION_DUPLICATE_MEMBER'
    try{$old=$oldRaw|ConvertFrom-Json;$candidate=$candidateRaw|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_JSON'}
    $topFields=@('schemaVersion','contractVersion','projectId','corrections')
    Assert-MinimalExactFields $old $oldRaw $topFields 'Current project corrections'
    if(-not(Test-MinimalJsonInteger $old.schemaVersion)-or[int]$old.schemaVersion-ne1-or[string]$old.contractVersion-cne'1.10.0'-or[string]$old.projectId-cne$ProjectId-or-not($old.corrections-is[Array])){throw 'PROJECT_CORRECTIONS_MIGRATION_SOURCE_SCHEMA'}
    Assert-ProjectCorrectionsMigrationCandidate $old $oldRaw $candidate $candidateRaw $TargetVersion $ProjectId 'Candidate project corrections'
    $repairProvided=@(-not[string]::IsNullOrWhiteSpace($ProjectCorrectionsMigrationRepairPath),-not[string]::IsNullOrWhiteSpace($ExpectedProjectCorrectionsMigrationRepairIdentity))
    if($RepairAdmission-and@($repairProvided|Where-Object{$_}).Count-ne2){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_FIELDS_REQUIRED'}
    if(-not$RepairAdmission-and@($repairProvided|Where-Object{$_}).Count-ne0){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_MODE_REQUIRED'}
    $effectiveCandidateRaw=$candidateRaw;$effectiveCandidateIdentity=$ExpectedProjectCorrectionsMigrationIdentity;$repairPath=$null
    if($RepairAdmission){
        $repairResolved=Get-ValidatedProjectCorrectionsRepairSource $RepositoryRoot $ProjectCorrectionsMigrationRepairPath $ExpectedProjectCorrectionsMigrationRepairIdentity
        if($repairResolved-ceq$candidateResolved-or(Get-MinimalFileIdentity $ProjectCorrectionsMigrationRepairPath)-cne$ExpectedProjectCorrectionsMigrationRepairIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_INPUT_DRIFT'}
        $repairRaw=Read-StrictUtf8NoBom $repairResolved
        if($repairRaw.Contains("`r")-or-not$repairRaw.EndsWith("`n")){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_TEXT_FORMAT'}
        Assert-StrictJsonMemberSet $repairRaw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_DUPLICATE_MEMBER'
        try{$repair=$repairRaw|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_JSON'}
        Assert-ProjectCorrectionsMigrationCandidate $old $oldRaw $repair $repairRaw $TargetVersion $ProjectId 'Repaired project corrections candidate'
        if($repairRaw-ceq$candidateRaw){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_NO_CHANGE'}
        $effectiveCandidateRaw=$repairRaw;$effectiveCandidateIdentity=$ExpectedProjectCorrectionsMigrationRepairIdentity;$repairPath=$repairResolved
    }

    $inputProvided=@(-not[string]::IsNullOrWhiteSpace($CurrentProcessInputPath),-not[string]::IsNullOrWhiteSpace($ExpectedCurrentProcessInputIdentity))
    if(@($inputProvided|Where-Object{$_}).Count-ne2){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_INPUT_REQUIRED'}
    if($ExpectedCurrentProcessInputIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $CurrentProcessInputPath -PathType Leaf)-or(Get-MinimalFileIdentity $CurrentProcessInputPath)-cne$ExpectedCurrentProcessInputIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_INPUT_DRIFT'}
    $inputRaw=Read-StrictUtf8NoBom $CurrentProcessInputPath;Assert-StrictJsonMemberSet $inputRaw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_DUPLICATE_MEMBER'
    try{$input=$inputRaw|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_JSON'}
    $expectedInputFields=@('schemaVersion','mode','projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity','expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities','exactPaths','forbiddenPaths','protectedPaths','authorizationPackagePath','expectedAuthorizationIdentity','userDecision','recoveryState','hostEnforcementGrade','invocationState','intentEnvelope','evaluationOnly')
    $inputNames=@($input.PSObject.Properties.Name)
    if(-not($input-is[pscustomobject])-or$inputNames.Count-ne$expectedInputFields.Count-or@($expectedInputFields|Where-Object{$_-cnotin$inputNames}).Count-ne0){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_FIELDS'}
    $repository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot));$workspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($FrameworkWorkspace))
    $inputRepository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.projectRoot))))
    $inputWorkspace=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.frameworkRoot))))
    $inputTask=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.taskPath)));
    $expectedEvaluationOnly=-not$RepairAdmission
    if(-not(Test-MinimalJsonInteger $input.schemaVersion)-or[int]$input.schemaVersion-ne2-or[string]$input.mode-cne'DISCOVER'-or-not($input.evaluationOnly-is[bool])-or[bool]$input.evaluationOnly-ne$expectedEvaluationOnly-or$inputRepository-cne$repository-or$inputWorkspace-cne$workspace-or$inputTask-cne[IO.Path]::GetFullPath([string]$TaskBinding.Path)){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_SCOPE'}
    if([string]$input.expectedProjectConfigIdentity-cne(Get-MinimalFileIdentity $ProjectFile)-or[string]$input.expectedCorrectionsIdentity-cne$oldIdentity-or[string]$input.expectedTaskIdentity-cne[string]$TaskBinding.OldIdentity-or[string]$input.observedActor-cne[string]$TaskBinding.Actor){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_BINDING'}
    $projectRaw=Read-StrictUtf8NoBom $ProjectFile;try{$project=$projectRaw|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_PROJECT_JSON'}
    $declaredCapabilities=@(Get-ExactEnabledCapabilityIds $project $projectRaw);$inputCapabilities=@($input.capabilities|ForEach-Object{[string]$_});$sortedCapabilities=@($inputCapabilities);[Array]::Sort($sortedCapabilities,[StringComparer]::Ordinal)
    if(-not($input.capabilities-is[Array])-or[string]::Join("`n",$inputCapabilities)-cne[string]::Join("`n",$sortedCapabilities)-or[string]::Join("`n",$sortedCapabilities)-cne[string]::Join("`n",$declaredCapabilities)){throw 'PROJECT_CORRECTIONS_MIGRATION_CAPABILITY_DRIFT'}
    $forbidden=@($input.forbiddenPaths);$protected=@($input.protectedPaths)
    $expectedExactPath=if($RepairAdmission){$candidateRelative}else{'.ai-workspace/corrections.json'}
    if(@($input.exactPaths).Count-ne1-or[string]$input.exactPaths[0]-cne$expectedExactPath-or'src/'-cnotin$forbidden-or@(@('test/','tests/')|Where-Object{$_-cin$forbidden}).Count-eq0-or'assets/'-cnotin$forbidden-or'.ai-workspace/'-cnotin$protected){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_BOUNDARY'}
    if([string]::IsNullOrWhiteSpace([string]$input.userDecision)-or[string]$input.recoveryState-cne'FULL_COLD'-or[string]$input.invocationState-cnotin@('PROVEN_EXPLICIT','PROVEN_MANAGED')-or[string]$input.hostEnforcementGrade-cnotin@('FRAMEWORK_GATED','INSTRUCTION_BOUND')){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_CONTEXT'}
    if($RepairAdmission){
        if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or[string]::IsNullOrWhiteSpace($ExpectedAuthorizationPackageIdentity)-or[string]$input.authorizationPackagePath-cne[IO.Path]::GetFullPath($AuthorizationPackagePath)-or[string]$input.expectedAuthorizationIdentity-cne$ExpectedAuthorizationPackageIdentity-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne$ExpectedAuthorizationPackageIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_REVIEW_AUTHORIZATION_DRIFT'}
    }elseif([string]$input.authorizationPackagePath-cne'NOT_REQUIRED'-or[string]$input.expectedAuthorizationIdentity-cne'NOT_REQUIRED'-or[string]$input.userDecision-ceq'NOT_REQUIRED'){throw 'PROJECT_CORRECTIONS_MIGRATION_PROCESS_CONTEXT'}
    $intent=$input.intentEnvelope;$intentRaw=$intent|ConvertTo-Json -Depth 20 -Compress
    Assert-MinimalExactFields $intent $intentRaw @('schemaVersion','objective','requestedActionKind','requestedResultKind','semanticHints','pathHints','capabilityHints','mutationHints','externalHints','ambiguityState') 'project corrections migration intent'
    foreach($name in @('semanticHints','pathHints','capabilityHints','mutationHints','externalHints')){if(-not($intent.$name-is[Array])-or@($intent.$name|Where-Object{-not($_-is[string])}).Count-ne0){throw ('PROJECT_CORRECTIONS_MIGRATION_INTENT_ARRAY|'+$name)}}
    $expectedAction=if($RepairAdmission){'CONTROL_WRITE'}else{'NONE'};$expectedResult=if($RepairAdmission){'IMPLEMENTATION_RESULT'}else{'PLAN'};$requiredReviewHint=if($RepairAdmission){'candidate repair admission'}else{'same-version project-control migration'}
    $mutationHintsMatch=if($RepairAdmission){@($intent.mutationHints).Count-eq1-and[string]$intent.mutationHints[0]-ceq'control'}else{@($intent.mutationHints).Count-eq0}
    if(-not(Test-MinimalJsonInteger $intent.schemaVersion)-or[int]$intent.schemaVersion-ne1-or[string]::IsNullOrWhiteSpace([string]$intent.objective)-or[string]$intent.requestedActionKind-cne$expectedAction-or[string]$intent.requestedResultKind-cne$expectedResult-or[string]$intent.ambiguityState-cne'CLEAR'-or-not$mutationHintsMatch-or@($intent.externalHints).Count-ne0-or@($intent.pathHints).Count-ne1-or[string]$intent.pathHints[0]-cne$expectedExactPath-or'Project corrections migration'-cnotin@($intent.semanticHints)-or$requiredReviewHint-cnotin@($intent.semanticHints)){throw 'PROJECT_CORRECTIONS_MIGRATION_INTENT_NOT_BOUNDED'}

    $resolver=Join-ChildPath $TargetFramework 'scripts/resolve-process-requirements.ps1';$pwsh=[Environment]::ProcessPath
    if([string]::IsNullOrWhiteSpace($pwsh)){throw 'POWERSHELL7_PROCESS_PATH_UNAVAILABLE'}
    $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$currentOutput=@(& $pwsh -NoProfile -NonInteractive -File $resolver -InputPath $CurrentProcessInputPath -AsJson 2>&1|ForEach-Object{[string]$_});$currentCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
    if($currentOutput.Count-ne1-or$currentCode-notin@(0,2)){throw ('PROJECT_CORRECTIONS_MIGRATION_CURRENT_DISCOVER_INVALID|'+($currentOutput-join';'))}
    try{$currentResult=$currentOutput[0]|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_CURRENT_DISCOVER_JSON'}
    $currentReason=if($currentCode-eq0-and[string]$currentResult.status-cin@('PASS','EVALUATION_ONLY')){'PASS'}elseif($currentCode-eq2-and[string]$currentResult.status-ceq'FAIL'-and[string]$currentResult.reason-clike'SELECTED_RULE_PACK_BUDGET_EXCEEDED*'){'SELECTED_RULE_PACK_BUDGET_EXCEEDED'}else{throw 'PROJECT_CORRECTIONS_MIGRATION_CURRENT_DISCOVER_REJECTED'}
    $projectSelectedBudgetProfile=$null-ne$script:ActiveAdoptionProfile.PSObject.Properties['processBudget']
    if($RepairAdmission-and(((-not$projectSelectedBudgetProfile)-and$currentReason-cne'SELECTED_RULE_PACK_BUDGET_EXCEEDED')-or($projectSelectedBudgetProfile-and$currentReason-cne'PASS'))){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_NORMAL_ROUTE_AVAILABLE'}

    $currentSelectedRequirements=@();$currentSelectedPackBytes=0;$currentSelectedPackIdentity='NOT_REQUIRED';$currentSourceCompositionIdentity='NOT_REQUIRED'
    if($RepairAdmission){
        $modulePath=Join-ChildPath $TargetFramework 'scripts/ProcessRequirementComposition.psm1';$module=Import-Module $modulePath -Force -PassThru
        $compositionAction='CONTROL_WRITE';$compositionResult='IMPLEMENTATION_RESULT'
        try{$semanticObjective=([string]$intent.objective+' '+[string]::Join(' ',@($intent.semanticHints+$intent.externalHints))).Trim();$currentComposition=Invoke-ProcessRequirementComposition -ProjectRoot $RepositoryRoot -FrameworkRoot $FrameworkWorkspace -TargetVersion $TargetVersion -ExpectedProjectConfigIdentity ([string]$input.expectedProjectConfigIdentity) -ExpectedCorrectionsIdentity $oldIdentity -Profile ([string]$TaskBinding.Profile) -Role ([string]$TaskBinding.Role) -Phase ([string]$TaskBinding.Phase) -Actor ([string]$TaskBinding.Actor) -TaskIdentity ([string]$TaskBinding.OldIdentity) -Capabilities @($declaredCapabilities) -Objective $semanticObjective -ActionKind $compositionAction -ResultKind $compositionResult -ExactPaths @($expectedExactPath)}finally{if($null-ne$module){Remove-Module $module -Force}}
        if([string]$currentComposition.status-cnotin@('PASS','EVALUATION_ONLY')-or[int]$currentComposition.sourceBuildCount-ne1-or@($currentComposition.selectedRequirements).Count-lt1){throw 'PROJECT_CORRECTIONS_MIGRATION_REVIEW_CURRENT_COMPOSITION'}
        foreach($requirement in @($currentComposition.selectedRequirements)){if(-not($requirement-is[pscustomobject])-or[string]::IsNullOrWhiteSpace([string]$requirement.requirementId)-or[string]::IsNullOrWhiteSpace([string]$requirement.fullText)){throw 'PROJECT_CORRECTIONS_MIGRATION_REVIEW_COMPLETE_RULES_REQUIRED'}}
        $currentPackJson=@($currentComposition.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress;$currentSelectedPackBytes=$utf8NoBom.GetByteCount($currentPackJson)
        $ordinaryCeiling=if($projectSelectedBudgetProfile){[int]$script:ActiveAdoptionProfile.processBudget.defaultSelectedRulePackBytes}else{[int]$script:ActiveAdoptionProfile.processBudgets.ordinarySelectedPackBytes}
        $reviewBridgeCeiling=if($projectSelectedBudgetProfile){[int]$currentComposition.selectedRulePackBytes}else{[int]$script:ActiveAdoptionProfile.processBudgets.legacySchema1CorrectionCompatibilityBytes}
        if($currentSelectedPackBytes-le$ordinaryCeiling-or$currentSelectedPackBytes-gt$reviewBridgeCeiling-or($projectSelectedBudgetProfile-and$reviewBridgeCeiling-gt[int]$script:ActiveAdoptionProfile.processBudget.absoluteSelectedRulePackBytes)){throw 'PROJECT_CORRECTIONS_MIGRATION_REVIEW_BRIDGE_BUDGET'}
        $currentSelectedRequirements=@($currentComposition.selectedRequirements);$currentSelectedPackIdentity=Get-UpperSha256Bytes ($utf8NoBom.GetBytes($currentPackJson));$currentSourceCompositionIdentity=[string]$currentComposition.sourceCompositionIdentity
    }
    $projectedReceipt=Get-ProjectCorrectionsProjectedDiscover $RepositoryRoot $FrameworkWorkspace $TargetFramework $TargetVersion $ProjectFile $BootstrapFile $ControllerFile $TaskBinding $input $effectiveCandidateRaw $effectiveCandidateIdentity $RepairAdmission
    return [pscustomobject]@{RepairAdmission=$RepairAdmission;Relative='.ai-workspace/corrections.json';Path=$correctionsFile;OldIdentity=$oldIdentity;NewIdentity=$effectiveCandidateIdentity;CandidateRelative=$candidateRelative;CandidatePath=$ProjectCorrectionsMigrationPath;CandidatePreimage=$ExpectedProjectCorrectionsMigrationIdentity;CandidatePreimageRaw=$candidateRaw;CandidateRaw=$effectiveCandidateRaw;RepairPath=$repairPath;Actor=$TaskBinding.Actor;TaskId=$TaskBinding.TaskId;Owner=$TaskBinding.Owner;TaskRelative=$TaskBinding.Relative;TaskIdentity=$TaskBinding.OldIdentity;UserDecision=[string]$input.userDecision;AuthorizationIdentity=$(if($RepairAdmission){$ExpectedAuthorizationPackageIdentity}else{'NOT_REQUIRED'});CurrentDiscover=$currentReason;CurrentSelectedPackBytes=$currentSelectedPackBytes;CurrentSelectedPackIdentity=$currentSelectedPackIdentity;CurrentSourceCompositionIdentity=$currentSourceCompositionIdentity;CurrentSelectedRequirements=@($currentSelectedRequirements);ProjectedSelectedPackBytes=[int]$projectedReceipt.selectedPackBytes;ProjectedSelectionIdentity=[string]$projectedReceipt.selectionIdentity;ProjectedSourceIdentity=[string]$projectedReceipt.sourceCompositionIdentity;ProjectedSelectedObligations=@($projectedReceipt.selectedObligations);ProjectedSourceBindings=$projectedReceipt.sourceBindings;FrameworkWorkspace=$FrameworkWorkspace;TargetFramework=$TargetFramework;TargetVersion=$TargetVersion;ProjectFile=$ProjectFile;BootstrapFile=$BootstrapFile;ControllerFile=$ControllerFile;TaskBinding=$TaskBinding;ProcessInput=$input}
}

function Assert-ProjectCorrectionsCandidateRepairAuthorization([string]$RepositoryRoot,[string]$TargetFramework,[string]$ProjectFile,$TaskBinding,$Migration) {
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or[string]::IsNullOrWhiteSpace($ExpectedAuthorizationPackageIdentity)){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_AUTHORIZATION_REQUIRED'}
    if($ExpectedAuthorizationPackageIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne$ExpectedAuthorizationPackageIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_AUTHORIZATION_DRIFT'}
    $raw=Read-StrictUtf8NoBom $AuthorizationPackagePath;Assert-StrictJsonMemberSet $raw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_AUTHORIZATION_DUPLICATE_MEMBER'
    try{$package=$raw|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_AUTHORIZATION_JSON'}
    $paths=@($package.exactPaths|ForEach-Object{[string]$_})
    if($paths.Count-ne1-or[string]$paths[0]-cne[string]$Migration.CandidateRelative-or[string]$package.userConfirmation-cne[string]$Migration.UserDecision){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_AUTHORITY_BINDING'}
    $checker=Join-ChildPath $TargetFramework 'scripts/check-authorization.ps1'
    $args=@{PackagePath=$AuthorizationPackagePath;ObservedActor=$TaskBinding.Actor;ObservedTaskId=$TaskBinding.TaskId;ObservedOwner=$TaskBinding.Owner;ObservedAction=@('CONTROL_WRITE');ObservedPath=@([string]$Migration.CandidateRelative);ObservedIdentity=@([string]$Migration.CandidateRelative+'='+[string]$Migration.CandidatePreimage);ControllerControlPath='.ai-workspace/controller.json';ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Get-MinimalFileIdentity $ProjectFile);TaskPath=$TaskBinding.Relative;ExpectedTaskIdentity=$TaskBinding.OldIdentity}
    if($null-ne$package.PSObject.Properties['repositoryId']){$args.ObservedRepositoryId=[string]$package.repositoryId}
    $previousCurrentDirectory=[Environment]::CurrentDirectory;Push-Location -LiteralPath $RepositoryRoot
    try{[Environment]::CurrentDirectory=$RepositoryRoot;$result=@(& $checker @args 2>&1|ForEach-Object{[string]$_});$checkerExit=$LASTEXITCODE}finally{[Environment]::CurrentDirectory=$previousCurrentDirectory;Pop-Location}
    if($checkerExit-ne0-or@($result|Where-Object{$_-clike'PASS|*'}).Count-ne1){throw ('PROJECT_CORRECTIONS_MIGRATION_REPAIR_AUTHORIZATION_REJECTED|'+($result-join';'))}
}

function Write-ProjectCorrectionsCandidateBytes([string]$CandidatePath,[string]$Content,[string]$ExpectedIdentity) {
    $tempPath=$CandidatePath+'.aiw-repair-'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllBytes($tempPath,$utf8NoBom.GetBytes($Content))
        if((Get-MinimalFileIdentity $tempPath)-cne$ExpectedIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_STAGING_DRIFT'}
        [IO.File]::Move($tempPath,$CandidatePath,$true)
    }finally{if(Test-Path -LiteralPath $tempPath -PathType Leaf){[IO.File]::Delete($tempPath)}}
}

function Invoke-ProjectCorrectionsCandidateRepairTransaction([string]$CandidatePath,[string]$CandidatePreimage,[string]$CandidatePreimageRaw,[string]$CandidatePostimage,[string]$CandidatePostimageRaw,[scriptblock]$PostWriteValidator) {
    try{
        Write-ProjectCorrectionsCandidateBytes $CandidatePath $CandidatePostimageRaw $CandidatePostimage
        if((Get-MinimalFileIdentity $CandidatePath)-cne$CandidatePostimage){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_POSTIMAGE_DRIFT'}
        $postReceipt=& $PostWriteValidator
        if($null-eq$postReceipt){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_POSTCHECK_EMPTY'}
        return $postReceipt
    }catch{
        $cause=[string]$_.Exception.Message
        try{$observed=Get-MinimalFileIdentity $CandidatePath}catch{$observed='UNREADABLE'}
        if($observed-ceq$CandidatePostimage){
            try{Write-ProjectCorrectionsCandidateBytes $CandidatePath $CandidatePreimageRaw $CandidatePreimage;$observed=Get-MinimalFileIdentity $CandidatePath}catch{throw ('PROJECT_CORRECTIONS_MIGRATION_REPAIR_ROLLBACK_UNPROVEN|observed='+$observed+'|cause='+$cause+'|rollback='+$_.Exception.Message)}
        }
        if($observed-cne$CandidatePreimage){throw ('PROJECT_CORRECTIONS_MIGRATION_REPAIR_ROLLBACK_UNPROVEN|observed='+$observed+'|cause='+$cause)}
        throw ('PROJECT_CORRECTIONS_MIGRATION_REPAIR_POSTCHECK_FAILED_ROLLED_BACK|'+$cause)
    }
}

function Invoke-SameVersionCorrectionsMigration([string]$RepositoryRoot,[string]$TargetFramework,[string]$TargetVersion,[string]$ProjectFile,$TaskBinding,$Migration,[bool]$ApplyChange) {
    if([bool]$Migration.RepairAdmission){
        Assert-ProjectCorrectionsCandidateRepairAuthorization $RepositoryRoot $TargetFramework $ProjectFile $TaskBinding $Migration
        $receipt=[ordered]@{schemaVersion=1;receiptType='PROJECT_CORRECTIONS_MIGRATION_CANDIDATE_REPAIR_ADMISSION';status='PASS';projectId=(Read-StrictUtf8NoBom $ProjectFile|ConvertFrom-Json).id;frameworkVersion=$TargetVersion;taskId=$Migration.TaskId;taskIdentity=$Migration.TaskIdentity;taskOwner=$Migration.Owner;actor=$Migration.Actor;candidatePath=$Migration.CandidateRelative;candidatePreimage=$Migration.CandidatePreimage;candidatePostimage=$Migration.NewIdentity;repairSourceIdentity=(Get-MinimalFileIdentity $Migration.RepairPath);repairSourceAuthority='NON_AUTHORITY';repairSourceDisposition='DELETE_AFTER_EXECUTION';authorizationIdentity=$Migration.AuthorizationIdentity;currentSource=[ordered]@{resolverResult=$Migration.CurrentDiscover;sourceCompositionIdentity=$Migration.CurrentSourceCompositionIdentity;selectedPackBytes=$Migration.CurrentSelectedPackBytes;selectedPackIdentity=$Migration.CurrentSelectedPackIdentity;selectedRuleBlocks=@($Migration.CurrentSelectedRequirements)};projectedDiscoverBefore=[ordered]@{status='PASS';sourceCompositionIdentity=$Migration.ProjectedSourceIdentity;selectionIdentity=$Migration.ProjectedSelectionIdentity;selectedPackBytes=$Migration.ProjectedSelectedPackBytes;selectedObligations=@($Migration.ProjectedSelectedObligations);sourceBindings=$Migration.ProjectedSourceBindings};candidateRepairAuthorized=$true;candidateWritePerformed=$false;liveCorrectionsWriteAuthorized=$false;ownerAcceptAuthorized=$false;semanticCorrectnessProven=$false;evidenceCeilings=@('CURRENT_RESOLVER_BUDGET_BRIDGED','EXACT_CANDIDATE_REPAIR_ONLY','SYSTEM_TEMP_REPAIR_SOURCE_NON_AUTHORITY','PROJECTED_DISCOVER_BEFORE_PASS','FOCUSED_REVIEW_REQUIRED')}
        if(-not$ApplyChange){Write-Output ($receipt|ConvertTo-Json -Depth 50 -Compress);return}
        if((Get-MinimalFileIdentity $Migration.CandidatePath)-cne$Migration.CandidatePreimage-or(Get-MinimalFileIdentity $Migration.RepairPath)-cne$Migration.NewIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_PREFLIGHT_DRIFT'}
        $postReceipt=Invoke-ProjectCorrectionsCandidateRepairTransaction ([string]$Migration.CandidatePath) ([string]$Migration.CandidatePreimage) ([string]$Migration.CandidatePreimageRaw) ([string]$Migration.NewIdentity) ([string]$Migration.CandidateRaw) {
            $validated=Get-ProjectCorrectionsProjectedDiscover $RepositoryRoot ([string]$Migration.FrameworkWorkspace) ([string]$Migration.TargetFramework) ([string]$Migration.TargetVersion) ([string]$Migration.ProjectFile) ([string]$Migration.BootstrapFile) ([string]$Migration.ControllerFile) $Migration.TaskBinding $Migration.ProcessInput (Read-StrictUtf8NoBom $Migration.CandidatePath) ([string]$Migration.NewIdentity) $true
            if([string]$validated.sourceCompositionIdentity-cne[string]$Migration.ProjectedSourceIdentity-or[string]$validated.selectionIdentity-cne[string]$Migration.ProjectedSelectionIdentity-or[int]$validated.selectedPackBytes-ne[int]$Migration.ProjectedSelectedPackBytes){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_PROJECTED_DRIFT'}
            return $validated
        }
        $receipt.status='COMPLETE';$receipt.candidateWritePerformed=$true;$receipt.projectedDiscoverAfter=[ordered]@{status='PASS';sourceCompositionIdentity=[string]$postReceipt.sourceCompositionIdentity;selectionIdentity=[string]$postReceipt.selectionIdentity;selectedPackBytes=[int]$postReceipt.selectedPackBytes;sourceBindings=$postReceipt.sourceBindings};$receipt.evidenceCeilings=@('CURRENT_RESOLVER_BUDGET_BRIDGED','EXACT_CANDIDATE_REPAIR_ONLY','PROJECTED_DISCOVER_PRE_POST_MATCH','FOCUSED_REVIEW_REQUIRED')
        Write-Output ($receipt|ConvertTo-Json -Depth 50 -Compress)
        return
    }
    Write-Output ('PROJECT_CONTROL_MIGRATION_PREIMAGE|'+$Migration.Relative+'='+$Migration.OldIdentity)
    Write-Output ('PROJECT_CONTROL_MIGRATION_POSTIMAGE|'+$Migration.Relative+'='+$Migration.NewIdentity)
    Write-Output ('PROJECT_CONTROL_MIGRATION_DISCOVER|current='+$Migration.CurrentDiscover+'|projected=PASS|bytes='+$Migration.ProjectedSelectedPackBytes+'|selection='+$Migration.ProjectedSelectionIdentity+'|source='+$Migration.ProjectedSourceIdentity)
    Write-Output ('UPGRADE_WRITESET|'+$Migration.Relative)
    if(-not$ApplyChange){Write-Output ('WHAT_IF|from='+$TargetVersion+'|to='+$TargetVersion+'|objects=1|transaction=atomic-project-control-migration');return}
    $script:CurrentPinBudgetBridge=[pscustomobject]@{UserDecision=[string]$Migration.UserDecision}
    $plan=[pscustomobject]@{State=[pscustomobject]@{toVersion=$TargetVersion};ExactPaths=@([string]$Migration.Relative);Preimages=@([pscustomobject]@{path=[string]$Migration.Relative;identity=[string]$Migration.OldIdentity});Postimages=@([pscustomobject]@{path=[string]$Migration.Relative;identity=[string]$Migration.NewIdentity})}
    $authorizationMigration=[pscustomobject]@{Actor=$TaskBinding.Actor;TaskId=$TaskBinding.TaskId;Owner=$TaskBinding.Owner;Relative=$TaskBinding.Relative;OldIdentity=$TaskBinding.OldIdentity}
    Assert-ActorBoundUpgrade115Authorization $RepositoryRoot $TargetFramework $ProjectFile $authorizationMigration $plan
    if((Get-MinimalFileIdentity $Migration.CandidatePath)-cne$Migration.NewIdentity-or(Get-MinimalFileIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_PREFLIGHT_DRIFT'}
    $tempRoot=[IO.Path]::GetTempPath();if([IO.Path]::GetPathRoot($tempRoot)-cne[IO.Path]::GetPathRoot($Migration.Path)){throw 'PROJECT_CORRECTIONS_MIGRATION_ATOMIC_TEMP_VOLUME'}
    $tempPath=Join-Path $tempRoot ('aiw-project-corrections-'+[guid]::NewGuid().ToString('N')+'.json')
    try{
        [IO.File]::WriteAllBytes($tempPath,$utf8NoBom.GetBytes([string]$Migration.CandidateRaw))
        if((Get-MinimalFileIdentity $tempPath)-cne$Migration.NewIdentity-or(Get-MinimalFileIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_FINAL_DRIFT'}
        [IO.File]::Move($tempPath,$Migration.Path,$true)
    }finally{if(Test-Path -LiteralPath $tempPath -PathType Leaf){[IO.File]::Delete($tempPath)}}
    if((Get-MinimalFileIdentity $Migration.Path)-cne$Migration.NewIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_POSTIMAGE_DRIFT'}
    Write-Output ('PROJECT_CONTROL_MIGRATION_APPLIED|version='+$TargetVersion+'|corrections='+$Migration.NewIdentity+'|selectedPackBytes='+$Migration.ProjectedSelectedPackBytes+'|next=FRESH_DISCOVER')
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
    foreach($name in $names){$value=$Capabilities.PSObject.Properties[$name].Value;if($name-cnotmatch'^[A-Z][A-Z0-9_]*$'-or[regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count-ne1-or-not($value-is[pscustomobject])-or$null-eq$value.PSObject.Properties['enabled']-or-not($value.enabled-is[bool])){throw "$Label contains an invalid capability declaration."}}
}

function Get-TargetFrameworkCapabilityContract([string]$FrameworkPath,[string]$Layout='repo-local') {
    if($Layout-cnotin@('repo-local','framework-maintenance-sibling')){throw 'TARGET_CONTROL_PLANE_LAYOUT'}
    $schemaPath=if($Layout-ceq'framework-maintenance-sibling'){[string](Get-AiwMaintenanceOverlay $workspace).ProjectConfigSchemaPath}else{Join-ChildPath $FrameworkPath 'PROJECT_CONFIG_SCHEMA.json'}
    $raw=Read-StrictUtf8NoBom $schemaPath
    try{$schema=$raw|ConvertFrom-Json}catch{throw 'TARGET_PROJECT_CONFIG_SCHEMA_JSON'}
    if(-not($schema-is[pscustomobject])-or$null-eq$schema.PSObject.Properties['properties']-or-not($schema.properties-is[pscustomobject])-or$null-eq$schema.properties.PSObject.Properties['frameworkCapabilities']){throw 'TARGET_CAPABILITY_SCHEMA_MISSING'}
    $capabilities=$schema.properties.frameworkCapabilities
    if(-not($capabilities-is[pscustomobject])-or[string]$capabilities.type-cne'object'-or-not($capabilities.additionalProperties-is[bool])-or[bool]$capabilities.additionalProperties){throw 'TARGET_CAPABILITY_SCHEMA_OPEN_OR_INVALID'}
    if($Layout-ceq'framework-maintenance-sibling'){
        if(-not(Test-MinimalJsonInteger $capabilities.maxProperties)-or[int]$capabilities.maxProperties-ne0-or$null-ne$capabilities.PSObject.Properties['properties']){throw 'TARGET_CAPABILITY_SCHEMA_UNSUPPORTED'}
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
    $null=ConvertTo-MinimalFrameworkLocator ([string]$knowledge.indexLocator)
}

function Assert-TargetProjectCapabilities([string]$ProjectText,[string]$Label) {
    try{$project=$ProjectText|ConvertFrom-Json}catch{throw ($Label+'_JSON')}
    if($null-eq$project.PSObject.Properties['frameworkCapabilities']){throw ($Label+'_CAPABILITIES_MISSING')}
    Assert-TargetFrameworkCapabilities $project.frameworkCapabilities $ProjectText $script:ActiveTargetCapabilityContract
}

function Get-ExactEnabledCapabilityIds($Project,[string]$Raw) {
    if($null-eq$Project.PSObject.Properties['frameworkCapabilities']){return @()}
    Assert-MinimalFrameworkCapabilities $Project.frameworkCapabilities $Raw 'project.json frameworkCapabilities'
    [string[]]$enabled=@($Project.frameworkCapabilities.PSObject.Properties|Where-Object{[bool]$_.Value.enabled}|ForEach-Object{[string]$_.Name})
    [Array]::Sort($enabled,[StringComparer]::Ordinal)
    return $enabled
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

function Get-ValidatedProjectCorrectionsRepairSource([string]$RepositoryRoot,[string]$Path,[string]$ExpectedIdentity) {
    if([string]::IsNullOrWhiteSpace($Path)-or-not[IO.Path]::IsPathRooted($Path)-or$ExpectedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_INPUT'}
    $tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    $repository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    $resolved=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath)
    $parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetDirectoryName($resolved))
    if($resolved.StartsWith($repository+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_PROJECT_REPOSITORY_FORBIDDEN'}
    if($parent-cne$tempRoot-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-project-corrections-repair-[0-9a-f]{32}\.json$'){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_SYSTEM_TEMP_REQUIRED'}
    Assert-NoReparsePoint $tempRoot;Assert-NoReparsePoint $resolved
    if((Get-MinimalFileIdentity $resolved)-cne$ExpectedIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_INPUT_DRIFT'}
    return $resolved
}

function Remove-ProjectCorrectionsRepairSource([string]$RepositoryRoot,[string]$Path,[string]$ExpectedIdentity) {
    if(-not(Test-Path -LiteralPath $Path)){return}
    if(-not[IO.Path]::IsPathRooted($Path)-or$ExpectedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_CLEANUP_SCOPE'}
    $tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    $repository=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot))
    $resolved=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath)
    $parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetDirectoryName($resolved))
    if($parent-cne$tempRoot-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-project-corrections-repair-[0-9a-f]{32}\.json$'-or$resolved.StartsWith($repository+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_CLEANUP_SCOPE'}
    Assert-NoReparsePoint $tempRoot;Assert-NoReparsePoint $resolved
    if((Get-MinimalFileIdentity $resolved)-cne$ExpectedIdentity){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_CLEANUP_IDENTITY_DRIFT'}
    [IO.File]::Delete($resolved)
    if(Test-Path -LiteralPath $resolved){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_CLEANUP_FAILED'}
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
    $completed=Join-Path $ProjectRoot ('.framework-upgrade-recovery-'+[string]$State.toVersion)
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
    $staging=Join-Path $ProjectRoot ('.framework-upgrade-preparation-'+$TargetVersion)
    if(Test-Path -LiteralPath $staging){throw 'A deterministic upgrade preparation already exists; preserve and inspect it before retrying.'}
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
    $runtime=[Environment]::ProcessPath;if([string]::IsNullOrWhiteSpace($runtime)-or-not(Test-Path -LiteralPath $runtime -PathType Leaf)){throw 'PROJECT_CORRECTION_EVALUATOR_RUNTIME'}
    $arguments=@('-NoProfile','-NonInteractive','-File',$Evaluator,'-ProjectRoot',$ProjectRepository,'-FrameworkRoot',$FrameworkWorkspace,'-TargetVersion',$Version,'-ExpectedProjectConfigIdentity',(Get-MinimalFileIdentity $ProjectConfigFile),'-Operation',$EvaluationOperation,'-AsJson')
    if(Test-Path -LiteralPath $CorrectionsFile -PathType Leaf){$arguments+=@('-ExpectedCorrectionsIdentity',(Get-MinimalFileIdentity $CorrectionsFile))}else{$arguments+='-AllowMissingCorrections'}
    $output=@(& $runtime @arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
    if($output.Count-ne1){throw ('PROJECT_CORRECTION_EVALUATOR_RESULT_COUNT|count='+$output.Count+'|exit='+$code)}
    $joined=[string]$output[0]
    try{$result=$joined|ConvertFrom-Json}catch{throw "Project correction evaluator returned invalid output: $joined"}
    $status=[string]$result.status
    if(($status-ceq'PASS'-and$code-eq0)-or($status-ceq'CONFLICT'-and$code-eq3)){return $result}
    throw ('PROJECT_CORRECTION_EVALUATOR_PROTOCOL|status='+$status+'|exit='+$code+'|output='+$joined)
}

function Invoke-CorrectionEvaluationProjected([string]$Evaluator,[string]$FrameworkWorkspace,[string]$Version,[string]$TargetConfig,[string]$TargetBootstrap,[string]$CorrectionsFile,[string]$ProcessPolicyFile,[string]$TargetProcessPolicy='',[string]$TargetCorrections='',[switch]$AllowMissing) {
    $projectionRoot=Join-Path ([IO.Path]::GetTempPath()) ('aiw-correction-projection-'+[guid]::NewGuid().ToString('N'))
    try{
        New-Item -ItemType Directory -Path $projectionRoot -Force|Out-Null
        try{$projectedConfig=$TargetConfig|ConvertFrom-Json}catch{throw 'Projected project configuration is invalid JSON.'}
        if([string]$projectedConfig.controlPlaneLayout-ceq'framework-maintenance-sibling'){
            $projectedRepository=Join-Path $projectionRoot 'Control';$projectedFramework=Join-Path $projectionRoot ([string]$projectedConfig.frameworkTarget.siblingDirectory)
            New-Item -ItemType Directory -Path $projectedRepository,$projectedFramework -Force|Out-Null
            foreach($gitRoot in @($projectedRepository,$projectedFramework)){$gitOutput=@(& git -C $gitRoot init --quiet 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0){throw ('PROJECTED_CORRECTION_GIT_INIT|'+($gitOutput-join';'))}}
            New-Item -ItemType Directory -Path (Join-Path $projectedFramework 'framework\versions') -Force|Out-Null
            Copy-Item -LiteralPath (Join-ChildPath $FrameworkWorkspace ('framework/versions/'+$Version)) -Destination (Join-Path $projectedFramework ('framework\versions\'+$Version)) -Recurse -Force
            Write-ProjectedText (Join-Path $projectedFramework 'README.md') "# Projected Framework target`n";Write-ProjectedText (Join-Path $projectedFramework 'AGENTS.md') "# Projected target navigation`n"
            $projectedFrameworkWorkspace=$projectedFramework
        }else{$projectedRepository=$projectionRoot;$projectedFrameworkWorkspace=$FrameworkWorkspace}
        $projectionControl=Join-Path $projectedRepository '.ai-workspace';New-Item -ItemType Directory -Path $projectionControl -Force|Out-Null
        $projectionConfig=Join-Path $projectionControl 'project.json';[IO.File]::WriteAllText($projectionConfig,$TargetConfig,$utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $projectionControl 'BOOTSTRAP.md'),$TargetBootstrap,$utf8NoBom)
        if($null-ne$projectedConfig.PSObject.Properties['processPolicy']){
            $projectedPolicy=Join-Path $projectionControl 'process-policy.json'
            if(-not[string]::IsNullOrWhiteSpace($TargetProcessPolicy)){[IO.File]::WriteAllText($projectedPolicy,$TargetProcessPolicy,$utf8NoBom)}
            elseif(-not[string]::IsNullOrWhiteSpace($ProcessPolicyFile)-and(Test-Path -LiteralPath $ProcessPolicyFile -PathType Leaf)){Copy-Item -LiteralPath $ProcessPolicyFile -Destination $projectedPolicy}
            else{throw 'Projected process policy is missing.'}
        }
        $projectionCorrections=Join-Path $projectionControl 'corrections.json'
        if(-not[string]::IsNullOrWhiteSpace($TargetCorrections)){[IO.File]::WriteAllText($projectionCorrections,$TargetCorrections,$utf8NoBom)}
        elseif(Test-Path -LiteralPath $CorrectionsFile -PathType Leaf){Copy-Item -LiteralPath $CorrectionsFile -Destination $projectionCorrections}
        $projectedEvaluator=if([string]$projectedConfig.controlPlaneLayout-ceq'framework-maintenance-sibling'){Join-ChildPath $projectedFrameworkWorkspace ('framework/versions/'+$Version+'/scripts/check-project-corrections.ps1')}else{$Evaluator}
        return Invoke-CorrectionEvaluation $projectedEvaluator $projectedRepository $projectedFrameworkWorkspace $Version $projectionConfig $projectionCorrections 'PRECHECK' -AllowMissing:($AllowMissing-or-not(Test-Path -LiteralPath $projectionCorrections -PathType Leaf))
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
    $script:ActiveAdoptionProfile=Get-AdoptionProfile $targetFramework $ToVersion
    if($null-ne$script:ActiveAdoptionProfile-and$SelectedRulePackBytes-gt[int]$script:ActiveAdoptionProfile.processBudget.absoluteSelectedRulePackBytes){throw 'SELECTED_RULE_PACK_BUDGET_ABSOLUTE_CAP'}
    if($null-ne$script:ActiveAdoptionProfile-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'}
    if($LocalCandidatePilot){
        $script:ActiveTargetSnapshot=Get-LocalCandidateFrameworkSnapshot $targetFramework $ToVersion $script:ActiveAdoptionProfile
    }else{
        Assert-StableFrameworkRelease $targetFramework $ToVersion
        $stableManifestPath=Join-ChildPath $targetFramework 'RELEASE_MANIFEST.json';$stableManifest=Read-StrictUtf8NoBom $stableManifestPath|ConvertFrom-Json
        $script:ActiveTargetSnapshot=[pscustomobject]@{Version=$ToVersion;Lifecycle='STABLE';LocalCandidate=$false;FileCount=[int64]$stableManifest.fileCount;TotalBytes=[int64]$stableManifest.totalBytes;Canonical=[string]$stableManifest.canonical;ManifestIdentity=(Get-MinimalFileIdentity $stableManifestPath)}
    }
    $profileTarget=Test-AdoptionProfileVersion $ToVersion
    if($ToVersion-in@('1.12.0','1.13.0','1.14.0','1.14.1','1.15.0','1.15.1')-or$profileTarget){
        $toolchainPath=Join-ChildPath $targetFramework 'TOOLCHAIN.json';$toolchainRaw=Read-StrictUtf8NoBom $toolchainPath
        try{$toolchain=$toolchainRaw|ConvertFrom-Json}catch{throw 'FRAMEWORK_TOOLCHAIN_JSON'}
        $toolchainFields=@('schemaVersion','frameworkVersion','contractVersion','projectSelectionField')+$(if($ToVersion-in@('1.15.0','1.15.1')-or$profileTarget){@('routerCompatibility')}else{@()})+@('officialBackends','conformance')
        Assert-MinimalExactFields $toolchain $toolchainRaw $toolchainFields 'Framework TOOLCHAIN.json'
        if(-not(Test-MinimalJsonInteger $toolchain.schemaVersion)-or[int]$toolchain.schemaVersion-ne1-or[string]$toolchain.frameworkVersion-cne$ToVersion-or[string]$toolchain.contractVersion-cne'1'-or[string]$toolchain.projectSelectionField-cne'frameworkToolBackend'-or-not($toolchain.officialBackends-is[System.Array])-or@($toolchain.officialBackends).Count-ne1){throw 'FRAMEWORK_TOOLCHAIN_VALUES'}
        $backend=@($toolchain.officialBackends)[0]
        if(-not($backend-is[pscustomobject])-or[string]$backend.id-cne'powershell7'-or[string]$backend.status-cne'OFFICIAL'-or-not($backend.runtime-is[pscustomobject])-or[string]$backend.runtime.command-cne'pwsh'-or[string]$backend.runtime.edition-cne'Core'-or-not(Test-MinimalJsonInteger $backend.runtime.minimumMajorVersion)-or[int]$backend.runtime.minimumMajorVersion-ne7-or-not($backend.platforms-is[System.Array])-or@($backend.platforms).Count-lt1-or-not($backend.entrypoints-is[pscustomobject])){throw 'FRAMEWORK_TOOLCHAIN_BACKEND'}
        $declaredPlatforms=@($backend.platforms|ForEach-Object{[string]$_})
        if(@($declaredPlatforms|Where-Object{$_-cnotin@('windows','linux','macos')}).Count-ne0-or@($declaredPlatforms|Select-Object -Unique).Count-ne$declaredPlatforms.Count){throw 'FRAMEWORK_TOOLCHAIN_PLATFORMS'}
        $currentPlatform=if([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)){'windows'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux)){'linux'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)){'macos'}else{'unknown'}
        if($currentPlatform-cnotin$declaredPlatforms){throw ('FRAMEWORK_TOOL_PLATFORM_UNSUPPORTED|backend=powershell7|platform='+$currentPlatform)}
        foreach($entry in $backend.entrypoints.PSObject.Properties){$relative=[string]$entry.Value;if([string]::IsNullOrWhiteSpace($relative)-or$relative-cne$relative.Replace('\','/')-or[IO.Path]::IsPathRooted($relative)-or$relative.Contains('..')-or-not(Test-Path -LiteralPath (Join-ChildPath $targetFramework $relative) -PathType Leaf)){throw ('FRAMEWORK_TOOLCHAIN_ENTRYPOINT|'+$entry.Name)}}
        if($ToVersion-in@('1.15.0','1.15.1')-or$profileTarget){
            $router=$toolchain.routerCompatibility
            $routerRaw=$router|ConvertTo-Json -Compress
            if($profileTarget){
                $routerFields=@('schemaVersion','skillName','status','canonicalSkillPath','versionContractPath','requiredOperations','processCatalogSchemaVersion','processCatalogVersion','nativeRuleBodySource')
                Assert-MinimalExactFields $router $routerRaw $routerFields 'Framework routerCompatibility'
                if(-not(Test-MinimalJsonInteger $router.schemaVersion)-or[int]$router.schemaVersion-ne1-or[string]$router.skillName-cne'ai-workspace-router'-or[string]$router.status-cne'COMPATIBLE'-or[string]$router.canonicalSkillPath-cne'skills/ai-workspace-router/SKILL.md'-or[string]$router.versionContractPath-cne'host/skills/ai-workspace-router/SKILL.md'-or-not(Test-MinimalJsonInteger $router.processCatalogSchemaVersion)-or[int]$router.processCatalogSchemaVersion-ne2-or[string]$router.processCatalogVersion-cne'3'-or[string]$router.nativeRuleBodySource-cne'MARKDOWN_EXACT_BLOCK'-or-not($router.requiredOperations-is[Array])-or[string]::Join("`n",@($router.requiredOperations))-cne[string]::Join("`n",@('LOAD_PLAN_RESOLVE','PROCESS_REQUIREMENTS_RESOLVE','WORKFLOW_ROUTE_RESOLVE'))){throw 'FRAMEWORK_ROUTER_COMPATIBILITY'}
            }else{
                $routerFields=@('schemaVersion','skillName','status','requiredOperations','processCatalogSchemaVersion','processCatalogVersion','nativeRuleBodySource')
                Assert-MinimalExactFields $router $routerRaw $routerFields 'Framework routerCompatibility'
                if(-not(Test-MinimalJsonInteger $router.schemaVersion)-or[int]$router.schemaVersion-ne1-or[string]$router.skillName-cne'ai-workspace-router'-or[string]$router.status-cne'COMPATIBLE'-or-not(Test-MinimalJsonInteger $router.processCatalogSchemaVersion)-or[int]$router.processCatalogSchemaVersion-ne2-or[string]$router.processCatalogVersion-cne'3'-or[string]$router.nativeRuleBodySource-cne'MARKDOWN_EXACT_BLOCK'-or-not($router.requiredOperations-is[Array])-or[string]::Join("`n",@($router.requiredOperations))-cne[string]::Join("`n",@('LOAD_PLAN_RESOLVE','PROCESS_REQUIREMENTS_RESOLVE','WORKFLOW_ROUTE_RESOLVE'))){throw 'FRAMEWORK_ROUTER_COMPATIBILITY'}
            }
        }
    }
}
elseif($LocalCandidatePilot){throw 'FRAMEWORK_LOCAL_CANDIDATE_TARGET_UNSUPPORTED|1.6.0'}

if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
    throw "Repository path does not exist: $RepositoryPath"
}
$repo = Get-GitRepositoryRoot ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).ProviderPath))
$repoLocalRoot = Join-Path $repo '.ai-workspace'

if (-not (Test-Path -LiteralPath $repoLocalRoot -PathType Container)) {
    throw "Repository-local project control plane does not exist: $repoLocalRoot"
}
$projectRoot = $repoLocalRoot
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
$initialConfigRaw=Read-StrictUtf8NoBom $projectFile
try{$initialConfig=$initialConfigRaw|ConvertFrom-Json}catch{throw "Project configuration is not valid JSON: $projectFile"}
$layout=[string]$initialConfig.controlPlaneLayout
if($layout-cnotin@('repo-local','framework-maintenance-sibling')){throw 'PROJECT_CONTROL_PLANE_LAYOUT'}
if($null-ne$script:ActiveAdoptionProfile){$script:ActiveTargetCapabilityContract=Get-TargetFrameworkCapabilityContract $targetFramework $layout}
if($layout-ceq'framework-maintenance-sibling'){
    if($null-eq$script:ActiveAdoptionProfile-or-not($initialConfig.frameworkTarget-is[pscustomobject])){throw 'MAINTENANCE_LAYOUT_TARGET_PROFILE_REQUIRED'}
    $initialTopology=Resolve-AiwMaintenanceTopology -ControlRepositoryPath $repo -TargetRepositoryId ([string]$initialConfig.frameworkTarget.repositoryId) -TargetSiblingDirectory ([string]$initialConfig.frameworkTarget.siblingDirectory) -TargetRoutineExcludedPaths @($initialConfig.frameworkTarget.routineExcludedPaths)
    if([IO.Path]::GetFullPath([string]$initialTopology.TargetRoot)-cne[IO.Path]::GetFullPath($workspace)){throw 'FRAMEWORK_WORKSPACE_TARGET_MISMATCH'}
}

$projectCorrectionsMigrationArguments=@(-not[string]::IsNullOrWhiteSpace($ProjectCorrectionsMigrationPath),-not[string]::IsNullOrWhiteSpace($ExpectedProjectCorrectionsMigrationIdentity))
$projectCorrectionsMigrationRepairArguments=@(-not[string]::IsNullOrWhiteSpace($ProjectCorrectionsMigrationRepairPath),-not[string]::IsNullOrWhiteSpace($ExpectedProjectCorrectionsMigrationRepairIdentity))
$projectCorrectionsMigrationAnyArguments=@($projectCorrectionsMigrationArguments+$projectCorrectionsMigrationRepairArguments+[bool]$RepairProjectCorrectionsMigrationCandidate)
$projectCorrectionsMigrationRequested=@($projectCorrectionsMigrationAnyArguments|Where-Object{$_}).Count-gt0
if($RepairSelectedRulePackBudget-and$projectCorrectionsMigrationRequested){throw 'PROJECT_CONTROL_REPAIR_MODE_CONFLICT'}
if($projectCorrectionsMigrationRequested-and@($projectCorrectionsMigrationArguments|Where-Object{$_}).Count-ne2){throw 'PROJECT_CORRECTIONS_MIGRATION_FIELDS_REQUIRED'}
if($RepairProjectCorrectionsMigrationCandidate-and@($projectCorrectionsMigrationRepairArguments|Where-Object{$_}).Count-ne2){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_FIELDS_REQUIRED'}
if(-not$RepairProjectCorrectionsMigrationCandidate-and@($projectCorrectionsMigrationRepairArguments|Where-Object{$_}).Count-ne0){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_MODE_REQUIRED'}
$actorRouteMigration=if($projectCorrectionsMigrationRequested-or$RepairSelectedRulePackBudget){$null}else{Get-ActorRouteMigration $repo $ToVersion $ActorRouteTaskPath $ExpectedActorRouteTaskIdentity $ActorRouteActor}
if($null-ne$actorRouteMigration){
    $routeProjectRaw=Read-StrictUtf8NoBom $projectFile
    try{$routeProject=$routeProjectRaw|ConvertFrom-Json}catch{throw 'ACTOR_ROUTE_PROJECT_JSON'}
    if(-not($routeProject.id-is[string])-or[string]$routeProject.id-cne$ProjectId){throw 'ACTOR_ROUTE_PROJECT_ID'}
    if([string]::IsNullOrWhiteSpace($ControllerId)-or-not(Test-Path -LiteralPath $controllerFile -PathType Leaf)){throw 'ACTOR_ROUTE_CURRENT_CONTROLLER_REQUIRED'}
    $routeControllerRaw=Read-StrictUtf8NoBom $controllerFile
    try{$routeController=$routeControllerRaw|ConvertFrom-Json}catch{throw 'ACTOR_ROUTE_CONTROLLER_JSON'}
    Assert-MinimalController $routeController $routeControllerRaw $ProjectId $ControllerId
    $actorPreparation=if($ToVersion-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion $ToVersion)){Join-ChildPath $repo ('.ai-workspace/tmp/upgrade-preparation/'+$ToVersion)}else{$null}
    if($null-ne$actorPreparation-and(Test-Path -LiteralPath $actorPreparation)){throw 'ACTOR_BOUND_UPGRADE_PREPARATION_REAUTHORIZATION_REQUIRED'}
    $actorRecovery=if($ToVersion-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion $ToVersion)){Join-ChildPath $repo ('.ai-workspace/upgrade-recovery/'+$ToVersion)}else{Join-Path $repo ('.framework-actor-bound-upgrade-recovery-'+$ToVersion)}
    if((Test-Path -LiteralPath $actorRecovery)-and-not[bool]$actorRouteMigration.SnapshotRebindRequired){
        if($ToVersion-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion $ToVersion)){Resume-ActorBoundUpgrade115 $repo $targetFramework $ToVersion $ProjectId $controllerFile $actorRouteMigration ([bool]$Apply)}else{Resume-ActorBoundUpgrade $repo $targetFramework $ToVersion $ProjectId $controllerFile $actorRouteMigration ([bool]$Apply)}
        if($Apply){$recoveryEvaluator=Join-ChildPath $targetFramework 'scripts/check-project-corrections.ps1';$recoveryCorrections=Join-ChildPath $projectRoot 'corrections.json';if(Test-Path -LiteralPath $recoveryEvaluator -PathType Leaf){$recoveryEvaluation=Invoke-CorrectionEvaluation $recoveryEvaluator $repo $workspace $ToVersion $projectFile $recoveryCorrections 'POSTCHECK' -AllowMissing:(-not(Test-Path -LiteralPath $recoveryCorrections -PathType Leaf));Write-CorrectionEvaluation $recoveryEvaluation 'after recovered actor-bound pin projection'}}
        return
    }
}

$framework114Transaction=Join-Path $repo '.framework-1.14-upgrade-transaction'
if(Test-Path -LiteralPath $framework114Transaction){
    Invoke-Framework114CrossRootTransition $repo $projectRoot $workspace 'TRANSACTION_RECOVERY' $ToVersion $ProjectId $ControllerId $null ([bool]$Apply)
    return
}

$transactionRoot = Join-Path $projectRoot '.framework-upgrade-transaction'
$deterministicPreparation=Join-Path $projectRoot ('.framework-upgrade-preparation-'+$ToVersion)
$abandonedPreparations = @(Get-ChildItem -LiteralPath $projectRoot -Directory -Force -Filter '.fwu-prep-*' -ErrorAction SilentlyContinue)
if(Test-Path -LiteralPath $deterministicPreparation -PathType Container){$abandonedPreparations+=Get-Item -LiteralPath $deterministicPreparation}
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
if($RepairSelectedRulePackBudget){
    if(-not(Test-AdoptionProfileVersion $ToVersion)-or[string]$config.frameworkVersion-cne$ToVersion){throw 'RULE_PACK_BUDGET_REPAIR_SAME_PIN_REQUIRED'}
    if([string]::IsNullOrWhiteSpace($ControllerId)-or-not(Test-Path -LiteralPath $controllerFile -PathType Leaf)){throw 'RULE_PACK_BUDGET_REPAIR_CURRENT_CONTROLLER_REQUIRED'}
    $controllerRaw=Read-StrictUtf8NoBom $controllerFile;try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'RULE_PACK_BUDGET_REPAIR_CONTROLLER_JSON'};Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    $taskBinding=Get-CurrentTaskBinding $repo $ToVersion $ActorRouteTaskPath $ExpectedActorRouteTaskIdentity $ActorRouteActor 'ACTIVE'
    if([string]$taskBinding.Actor-cne$ControllerId-or[string]$taskBinding.Role-cne'CONTROLLER'){throw 'RULE_PACK_BUDGET_REPAIR_CONTROLLER_TASK_REQUIRED'}
    $repair=Get-SelectedRulePackBudgetRepair $repo $workspace $targetFramework $ToVersion $ProjectId $projectFile (Join-ChildPath $projectRoot 'corrections.json') $taskBinding ([bool]$Apply)
    Invoke-SelectedRulePackBudgetRepair $repair ([bool]$Apply)
    return
}
if($projectCorrectionsMigrationRequested){
    if(-not(Test-AdoptionProfileVersion $ToVersion)-or[string]$config.frameworkVersion-cne$ToVersion){throw 'PROJECT_CORRECTIONS_MIGRATION_SAME_PIN_REQUIRED'}
    if([string]::IsNullOrWhiteSpace($ControllerId)-or-not(Test-Path -LiteralPath $controllerFile -PathType Leaf)){throw 'PROJECT_CORRECTIONS_MIGRATION_CURRENT_CONTROLLER_REQUIRED'}
    $controllerRaw=Read-StrictUtf8NoBom $controllerFile;try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'PROJECT_CORRECTIONS_MIGRATION_CONTROLLER_JSON'};Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    $taskBinding=Get-CurrentTaskBinding $repo $ToVersion $ActorRouteTaskPath $ExpectedActorRouteTaskIdentity $ActorRouteActor 'ACTIVE'
    if($RepairProjectCorrectionsMigrationCandidate-and([string]$taskBinding.Actor-cne$ControllerId-or[string]$taskBinding.Role-cne'CONTROLLER')){throw 'PROJECT_CORRECTIONS_MIGRATION_REPAIR_CONTROLLER_BINDING_REQUIRED'}
    $admittedRepairSource=$null
    try{
        if($RepairProjectCorrectionsMigrationCandidate){$admittedRepairSource=Get-ValidatedProjectCorrectionsRepairSource $repo $ProjectCorrectionsMigrationRepairPath $ExpectedProjectCorrectionsMigrationRepairIdentity}
        $correctionsMigration=Get-SameVersionCorrectionsMigration $repo $workspace $targetFramework $ToVersion $ProjectId $projectFile $bootstrapFile $controllerFile $taskBinding ([bool]$RepairProjectCorrectionsMigrationCandidate)
        Invoke-SameVersionCorrectionsMigration $repo $targetFramework $ToVersion $projectFile $taskBinding $correctionsMigration ([bool]$Apply)
    }finally{if($null-ne$admittedRepairSource){Remove-ProjectCorrectionsRepairSource $repo $admittedRepairSource $ExpectedProjectCorrectionsMigrationRepairIdentity}}
    return
}
if(($ToVersion-in@('1.15.0','1.15.1')-or(Test-AdoptionProfileVersion $ToVersion))-and[string]$config.frameworkVersion-ceq$ToVersion){
    if([string]::IsNullOrWhiteSpace($ControllerId)){throw ('ControllerId is required to validate an already-upgraded Framework '+$ToVersion+' project.')}
    if($null-ne$actorRouteMigration-and[bool]$actorRouteMigration.SnapshotRebindRequired){
        $refreshPlan=Get-LocalCandidateSamePinProjectionRefreshPlan $repo $workspace $targetFramework $ToVersion $projectFile $bootstrapFile $layout $ProjectId $actorRouteMigration
        if($refreshPlan.Records.Count-eq0){Assert-LocalCandidateSamePinProjectProjection $repo $workspace $targetFramework $ToVersion $projectFile $bootstrapFile $layout $ProjectId;Invoke-LocalCandidateSamePinRebind $repo $workspace $targetFramework $ToVersion $projectFile $actorRouteMigration ([bool]$Apply)}else{Invoke-LocalCandidateSamePinProjectionRefresh $repo $workspace $targetFramework $ToVersion $projectFile $actorRouteMigration $refreshPlan ([bool]$Apply)}
        return
    }
    $registrationEntry=Join-Path (Split-Path -Parent $PSCommandPath) 'register-project.ps1'
    $registrationArguments=@{ProjectId=$ProjectId;DisplayName=[string]$config.displayName;FrameworkVersion=$ToVersion;RepositoryPath=$repo;ControllerId=$ControllerId;ControlPlaneLayout=$layout;WorkspaceRoot=$workspace}
    if($layout-ceq'framework-maintenance-sibling'){$registrationArguments.FrameworkTargetRepositoryId=[string]$config.frameworkTarget.repositoryId;$registrationArguments.FrameworkTargetSiblingDirectory=[string]$config.frameworkTarget.siblingDirectory;$registrationArguments.FrameworkTargetRoutineExcludedPath=@($config.frameworkTarget.routineExcludedPaths)}
    $validationOutput=@(& $registrationEntry @registrationArguments 2>&1|ForEach-Object{[string]$_})
    if(-not(($validationOutput-join"`n").Contains('ALREADY_REGISTERED'))){throw ('ALREADY_UPGRADED_VALIDATION_FAILED|'+($validationOutput-join';'))}
    if($Apply){Write-Output 'ALREADY_UPGRADED|objects=0|host-router=UNCHANGED'}else{Write-Output ('WHAT_IF|from='+$ToVersion+'|to='+$ToVersion+'|objects=0|transaction=none')}
    return
}
if(($ToVersion-in@('1.14.0','1.14.1')-and[string]$config.frameworkVersion-in@('1.11.0','1.12.0','1.13.0','1.14.0','1.14.1'))-or($ToVersion-in@('1.15.0','1.15.1')-and[string]$config.frameworkVersion-in@('1.14.0','1.14.1'))-or((Test-AdoptionProfileVersion $ToVersion)-and[string]$config.frameworkVersion-cin@($script:ActiveAdoptionProfile.directSourceVersions))-or([string]$config.frameworkVersion-in@('1.14.0','1.14.1')-and$ToVersion-ceq'1.13.0')){
    Invoke-Framework114CrossRootTransition $repo $projectRoot $workspace ([string]$config.frameworkVersion) $ToVersion $ProjectId $ControllerId $actorRouteMigration ([bool]$Apply)
    return
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

if($null-ne$actorRouteMigration){
    $actorObjects=@(
        [pscustomobject]@{relative='.ai-workspace/project.json';path=$projectFile;content=$targetConfig},
        [pscustomobject]@{relative='.ai-workspace/BOOTSTRAP.md';path=$bootstrapFile;content=$targetBootstrap}
    )
    if($correctionsMode-ceq'CREATE'){$actorObjects+= [pscustomobject]@{relative='.ai-workspace/corrections.json';path=$correctionsFile;content=$targetCorrections}}
    Invoke-ActorBoundUpgrade $repo $sourceFramework $targetFramework $fromVersion $ToVersion $ProjectId $projectFile $controllerFile $actorRouteMigration $actorObjects ([bool]$Apply)
    if($Apply){$postCorrection=Invoke-CorrectionEvaluation $evaluator $repo $workspace $ToVersion $projectFile $correctionsFile 'POSTCHECK';Write-CorrectionEvaluation $postCorrection 'after actor-bound pin projection'}
    return
}

if (-not $Apply) {
    $materials=@('state.json','old/project.json','old/BOOTSTRAP.md','new/project.json','new/BOOTSTRAP.md')
    if($correctionsMode-ceq'CREATE'){$materials+='new/corrections.json'}elseif($correctionsMode-ceq'PRESERVE'){$materials+='old/corrections.json'}
    $writeSet=New-Object 'System.Collections.Generic.List[string]'
    $writeSet.Add('.ai-workspace/project.json');$writeSet.Add('.ai-workspace/BOOTSTRAP.md')
    if($correctionsMode-ceq'CREATE'){$writeSet.Add('.ai-workspace/corrections.json')}
    foreach($prefix in @(
        ('.ai-workspace/.framework-upgrade-preparation-'+$ToVersion),
        '.ai-workspace/.framework-upgrade-transaction',
        ('.ai-workspace/.framework-upgrade-recovery-'+$ToVersion)
    )){foreach($material in $materials){$writeSet.Add($prefix+'/'+$material)}}
    Write-Output ('UPGRADE_WRITESET|'+[string]::Join('|',$writeSet))
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
