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

    [switch]$Apply,

    [string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if($ToVersion-ceq'1.12.0'-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){
    throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'
}
if($ToVersion-in@('1.13.0','1.14.0')-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){
    throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'
}
if($ToVersion-ceq'1.14.1'-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){
    throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'
}
if($ToVersion-ceq'1.15.0'-and($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7)){
    throw 'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7'
}

function Get-OptionalIdentity([string]$Path){if(Test-Path -LiteralPath $Path -PathType Leaf){return Get-MinimalFileIdentity $Path};return 'MISSING'}

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

function Get-ProcessCarrierContractVersion([string]$FrameworkVersion){if($FrameworkVersion-in@('1.14.0','1.14.1','1.15.0')){return '1.14.0'};return $FrameworkVersion}

function Assert-ExactTransactionTree([string]$Root,[string[]]$ExpectedFiles,[string[]]$AdditionalDirectories,[string]$ErrorCode) {
    $fileSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$directorySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($relative in $ExpectedFiles){$null=Join-ChildPath $Root $relative;if(-not$fileSet.Add($relative)){throw $ErrorCode};$segments=$relative.Split('/');for($i=1;$i-lt$segments.Count;$i++){$null=$directorySet.Add([string]::Join('/',@($segments[0..($i-1)])))}}
    foreach($relative in $AdditionalDirectories){$null=Join-ChildPath $Root $relative;$segments=$relative.Split('/');for($i=1;$i-le$segments.Count;$i++){$null=$directorySet.Add([string]::Join('/',@($segments[0..($i-1)])))}}
    $actualFiles=@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')})
    $actualDirectories=@(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')})
    if($actualFiles.Count-ne$fileSet.Count-or@($actualFiles|Where-Object{-not$fileSet.Contains($_)}).Count-ne0-or$actualDirectories.Count-ne$directorySet.Count-or@($actualDirectories|Where-Object{-not$directorySet.Contains($_)}).Count-ne0){throw $ErrorCode}
}

function Get-ActorRouteMigration([string]$RepositoryRoot,[string]$TargetVersion,[string]$RelativePath,[string]$ExpectedIdentity,[string]$Actor){
    $provided=@(-not[string]::IsNullOrWhiteSpace($RelativePath),-not[string]::IsNullOrWhiteSpace($ExpectedIdentity),-not[string]::IsNullOrWhiteSpace($Actor))
    if(@($provided|Where-Object{$_}).Count-eq0){return $null}
    if(@($provided|Where-Object{$_}).Count-ne3){throw 'ACTOR_ROUTE_MIGRATION_FIELDS_REQUIRED'}
    if($TargetVersion-notin@('1.13.0','1.14.0','1.14.1','1.15.0')){throw 'ACTOR_ROUTE_MIGRATION_TARGET_UNSUPPORTED'}
    if($RelativePath-cne$RelativePath.Replace('\','/')-or$RelativePath-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'-or[IO.Path]::IsPathRooted($RelativePath)-or$RelativePath.Contains(':')){throw 'ACTOR_ROUTE_CURRENT_ACTIVE_TASK_REQUIRED'}
    if($ExpectedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ACTOR_ROUTE_TASK_IDENTITY'}
    $path=Join-ChildPath $RepositoryRoot $RelativePath
    $recoveryRelative=if($TargetVersion-ceq'1.15.0'){'.ai-workspace/upgrade-recovery/'+$TargetVersion}else{'.framework-actor-bound-upgrade-recovery-'+$TargetVersion}
    $recoveryRoot=Join-ChildPath $RepositoryRoot $recoveryRelative
    $recoveryState=$null
    if(Test-Path -LiteralPath $recoveryRoot -PathType Container){
        $statePath=Join-Path $recoveryRoot 'state.json';$stateRaw=Read-StrictUtf8NoBom $statePath
        try{$recoveryState=$stateRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_RECOVERY_JSON'}
        if([string]$recoveryState.toVersion-cne$TargetVersion-or[string]$recoveryState.taskRelative-cne$RelativePath-or[string]$recoveryState.actor-cne$Actor){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}
        $oldPath=Join-ChildPath (Join-Path $recoveryRoot 'old') $RelativePath
        if(-not(Test-Path -LiteralPath $oldPath -PathType Leaf)-or(Get-MinimalFileIdentity $oldPath)-cne$ExpectedIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'}
        $raw=Read-StrictUtf8NoBom $oldPath
    }else{
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-MinimalFileIdentity $path)-cne$ExpectedIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'}
        $raw=Read-StrictUtf8NoBom $path
    }
    $header=[regex]::Matches($raw,'(?m)^#\s+(?<task>[0-9A-Za-z][0-9A-Za-z._-]*)\s+[-—]')
    $owner=[regex]::Matches($raw,'(?m)^- Owner:\s*`?(?<owner>[^`\r\n]+?)`?\s*$')
    $active=[regex]::Matches($raw,'(?m)^- Range summary:.*(?:^|;)\s*lifecycle=ACTIVE(?:;|$).*')
    $schemaPattern=if($TargetVersion-ceq'1.15.0'){'(?m)^- Task schema:\s*(?<version>1\.11\.0|1\.14\.0|1\.14\.1)\s*$'}else{'(?m)^- Task schema:\s*(?<version>1\.11\.0)\s*$'}
    $schema=[regex]::Matches($raw,$schemaPattern)
    $legacy=[regex]::Matches($raw,'(?m)^- Work route:\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
    $current=[regex]::Matches($raw,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
    $fileTask=[IO.Path]::GetFileNameWithoutExtension($RelativePath)
    if($header.Count-ne1-or[string]$header[0].Groups['task'].Value-cne$fileTask-or$owner.Count-ne1-or[string]::IsNullOrWhiteSpace([string]$owner[0].Groups['owner'].Value)-or$active.Count-ne1){throw 'ACTOR_ROUTE_CURRENT_TASK_BINDING_REQUIRED'}
    if($schema.Count-ne1){throw 'ACTOR_ROUTE_SOURCE_SCHEMA_REQUIRED'}
    if($legacy.Count-eq1-and$current.Count-eq0){
        $replacement='- Work route: actor='+$Actor+'; role='+[string]$legacy[0].Groups['role'].Value+'; phase='+[string]$legacy[0].Groups['phase'].Value
        $target=$raw.Substring(0,$legacy[0].Index)+$replacement+$raw.Substring($legacy[0].Index+$legacy[0].Length)
    }elseif($TargetVersion-ceq'1.15.0'-and$current.Count-eq1-and$legacy.Count-eq0-and[string]$current[0].Groups['actor'].Value-ceq$Actor){
        $target=$raw
    }else{throw 'ACTOR_ROUTE_SOURCE_BINDING_REQUIRED'}
    $target=$target.Substring(0,$schema[0].Index)+'- Task schema: '+$TargetVersion+$target.Substring($schema[0].Index+$schema[0].Length)
    $directory=[IO.Path]::GetDirectoryName($RelativePath).Replace('\','/')
    $atomicRelative=$directory+'/.'+[IO.Path]::GetFileName($RelativePath)+'.actor-route-new'
    $newIdentity=Get-MinimalBytesIdentity ($utf8NoBom.GetBytes($target))
    if($null-ne$recoveryState){$entry=@($recoveryState.objects|Where-Object{[string]$_.relative-ceq$RelativePath});if($entry.Count-ne1-or[string]$entry[0].oldIdentity-cne$ExpectedIdentity-or[string]$entry[0].newIdentity-cne$newIdentity-or[string]$recoveryState.taskId-cne$fileTask-or[string]$recoveryState.taskOwner-cne[string]$owner[0].Groups['owner'].Value){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}}
    return [pscustomobject]@{Relative=$RelativePath;Path=$path;OldIdentity=$ExpectedIdentity;NewIdentity=$newIdentity;Actor=$Actor;TaskId=$fileTask;Owner=[string]$owner[0].Groups['owner'].Value;AtomicRelative=$atomicRelative;Content=$target}
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
    $releaseManifestPath=Join-ChildPath $TargetFramework 'RELEASE_MANIFEST.json'
    $releaseManifestRaw=Read-StrictUtf8NoBom $releaseManifestPath
    try{$releaseManifest=$releaseManifestRaw|ConvertFrom-Json}catch{throw 'TARGET_RELEASE_MANIFEST_JSON'}
    if([string]$releaseManifest.version-cne$TargetVersion-or[string]$releaseManifest.lifecycle-cne'STABLE'-or[string]$releaseManifest.sourceReview-cne'APPROVED'-or[string]$releaseManifest.canonical-cnotmatch'^[A-F0-9]{64}$'){throw 'TARGET_RELEASE_NOT_SEALED'}
    $stateObjects=@($ordered|ForEach-Object{[ordered]@{relative=$_.relative;oldIdentity=$_.oldIdentity;newIdentity=$_.newIdentity}})
    $state=[ordered]@{schemaVersion=2;projectId=$ProjectId;fromVersion=$FromVersion;toVersion=$TargetVersion;targetReleaseCanonical=[string]$releaseManifest.canonical;targetReleaseManifestIdentity=(Get-MinimalFileIdentity $releaseManifestPath);actor=$Migration.Actor;taskId=$Migration.TaskId;taskOwner=$Migration.Owner;taskRelative=$Migration.Relative;authorizationIdentity=$ExpectedAuthorizationPackageIdentity;objects=$stateObjects}
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
    Write-Output ('UPGRADE_TARGET_RELEASE|canonical='+[string]$Plan.State.targetReleaseCanonical+'|manifest='+[string]$Plan.State.targetReleaseManifestIdentity)
    foreach($entry in $Plan.Preimages){Write-Output ('UPGRADE_PREIMAGE|'+[string]$entry.path+'='+[string]$entry.identity)}
    foreach($entry in $Plan.Postimages){Write-Output ('UPGRADE_POSTIMAGE|'+[string]$entry.path+'='+[string]$entry.identity)}
    Write-Output ('UPGRADE_WRITESET|'+[string]::Join('|',@($Plan.ExactPaths)))
    Write-Output ('WHAT_IF|from='+$FromVersion+'|to='+$TargetVersion+'|objects='+$Plan.Records.Count+'|transaction=actor-bound-schema3')
}

function Assert-ActorBoundUpgrade115Authorization([string]$RepositoryRoot,[string]$TargetFramework,[string]$ProjectFile,$Migration,$Plan){
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or[string]::IsNullOrWhiteSpace($ExpectedAuthorizationPackageIdentity)){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_REQUIRED'}
    if($ExpectedAuthorizationPackageIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne$ExpectedAuthorizationPackageIdentity){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DRIFT'}
    $raw=Read-StrictUtf8NoBom $AuthorizationPackagePath;Assert-StrictJsonMemberSet $raw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DUPLICATE_MEMBER'
    try{$package=$raw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_JSON'}
    if([int]$package.schemaVersion-ne3-or[string]$package.frameworkVersion-cne'1.15.0'-or[string]$package.bundle-cne'ACTOR_BOUND_PROJECT_UPGRADE'-or[string]$package.issuerRole-cne'PROJECT_CONTROLLER'-or[string]$package.grantee-cne$Migration.Actor-or[string]$package.taskId-cne$Migration.TaskId-or[string]$package.owner-cne$Migration.Owner){throw 'ACTOR_BOUND_UPGRADE_AUTHORITY_BINDING'}
    $declared=@($package.exactPaths|ForEach-Object{[string]$_});$expected=@($Plan.ExactPaths);[Array]::Sort($declared,[StringComparer]::Ordinal);[Array]::Sort($expected,[StringComparer]::Ordinal)
    if($declared.Count-ne$expected.Count-or[string]::Join("`n",$declared)-cne[string]::Join("`n",$expected)){throw 'ACTOR_BOUND_UPGRADE_PATHSET_DRIFT'}
    $declaredPost=@($package.postObjectIdentities|ForEach-Object{[string]$_.path+'='+[string]$_.identity});$expectedPost=@($Plan.Postimages|ForEach-Object{[string]$_.path+'='+[string]$_.identity});[Array]::Sort($declaredPost,[StringComparer]::Ordinal);[Array]::Sort($expectedPost,[StringComparer]::Ordinal)
    if($declaredPost.Count-ne$expectedPost.Count-or[string]::Join("`n",$declaredPost)-cne[string]::Join("`n",$expectedPost)){throw 'ACTOR_BOUND_UPGRADE_POSTIMAGE_DRIFT'}
    $observed=@($Plan.Preimages|ForEach-Object{[string]$_.path+'='+[string]$_.identity})
    $checker=Join-ChildPath $TargetFramework 'scripts/check-authorization.ps1'
    $args=@{PackagePath=$AuthorizationPackagePath;ObservedActor=$Migration.Actor;ObservedTaskId=$Migration.TaskId;ObservedOwner=$Migration.Owner;ObservedAction=@('CONTROL_WRITE');ObservedPath=@($Plan.ExactPaths);ObservedIdentity=$observed;ControllerControlPath='.ai-workspace/controller.json';ProjectConfigPath='.ai-workspace/project.json';ExpectedProjectConfigIdentity=(Get-MinimalFileIdentity $ProjectFile);TaskPath=$Migration.Relative;ExpectedTaskIdentity=$Migration.OldIdentity}
    $previousCurrentDirectory=[Environment]::CurrentDirectory;Push-Location -LiteralPath $RepositoryRoot
    try{[Environment]::CurrentDirectory=$RepositoryRoot;$result=@(& $checker @args 2>&1|ForEach-Object{[string]$_});$checkerExit=$LASTEXITCODE}finally{[Environment]::CurrentDirectory=$previousCurrentDirectory;Pop-Location}
    if($checkerExit-ne0-or@($result|Where-Object{$_-clike'PASS|*'}).Count-ne1){throw ('ACTOR_BOUND_UPGRADE_AUTHORIZATION_REJECTED|'+($result-join';'))}
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
            if([string]$record.newIdentity-cne'ABSENT'){$new=Join-ChildPath (Join-Path $preparationRoot 'new') ([string]$record.relative);New-Item -ItemType Directory -Path (Split-Path -Parent $new) -Force|Out-Null;Write-Utf8NoBom $new ([string]$record.content)}
        }
        Write-Utf8NoBom (Join-Path $preparationRoot 'state.json') ([string]$plan.StateText)
        foreach($record in $plan.Records){if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.oldIdentity){throw ('OBJECT_DRIFT|'+[string]$record.relative)}}
        Assert-ActorBoundUpgrade115Material $preparationRoot $plan 'PREPARATION'
        $recoveryParent=Split-Path -Parent $recoveryRoot;New-Item -ItemType Directory -Path $recoveryParent -Force|Out-Null
        [IO.Directory]::Move($preparationRoot,$recoveryRoot)
        Assert-ActorBoundUpgrade115Material $recoveryRoot $plan 'RECOVERY'
        $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
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
    Assert-MinimalExactFields $state $raw @('schemaVersion','projectId','fromVersion','toVersion','targetReleaseCanonical','targetReleaseManifestIdentity','actor','taskId','taskOwner','taskRelative','authorizationIdentity','objects') 'actor-bound 1.15 upgrade recovery'
    if(-not(Test-MinimalJsonInteger $state.schemaVersion)-or[int]$state.schemaVersion-ne2-or[string]$state.projectId-cne$ProjectId-or[string]$state.toVersion-cne$TargetVersion-or[string]$state.actor-cne$Migration.Actor-or[string]$state.taskId-cne$Migration.TaskId-or[string]$state.taskOwner-cne$Migration.Owner-or[string]$state.taskRelative-cne$Migration.Relative-or-not($state.objects-is[Array])){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_BINDING_DRIFT'}
    $manifestPath=Join-ChildPath $TargetFramework 'RELEASE_MANIFEST.json';$manifest=Read-StrictUtf8NoBom $manifestPath|ConvertFrom-Json
    if([string]$manifest.canonical-cne[string]$state.targetReleaseCanonical-or(Get-MinimalFileIdentity $manifestPath)-cne[string]$state.targetReleaseManifestIdentity){throw 'ACTOR_BOUND_UPGRADE_TARGET_RELEASE_DRIFT'}
    if([string]::IsNullOrWhiteSpace($AuthorizationPackagePath)-or-not(Test-Path -LiteralPath $AuthorizationPackagePath -PathType Leaf)-or(Get-MinimalFileIdentity $AuthorizationPackagePath)-cne[string]$state.authorizationIdentity-or[string]$state.authorizationIdentity-cne$ExpectedAuthorizationPackageIdentity){throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DRIFT'}
    $packageRaw=Read-StrictUtf8NoBom $AuthorizationPackagePath;Assert-StrictJsonMemberSet $packageRaw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_DUPLICATE_MEMBER';try{$package=$packageRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_AUTHORIZATION_JSON'}
    if([int]$package.schemaVersion-ne3-or[string]$package.bundle-cne'ACTOR_BOUND_PROJECT_UPGRADE'-or[string]$package.issuerRole-cne'PROJECT_CONTROLLER'-or[string]$package.grantee-cne$Migration.Actor-or[string]$package.taskId-cne$Migration.TaskId-or[string]$package.owner-cne$Migration.Owner){throw 'ACTOR_BOUND_UPGRADE_AUTHORITY_BINDING'}
    $controllerRaw=Read-StrictUtf8NoBom $ControllerFile;try{$controller=$controllerRaw|ConvertFrom-Json}catch{throw 'ACTOR_BOUND_UPGRADE_CONTROLLER_JSON'};Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    if([string]$package.issuerControllerId-cne[string]$controller.controllerId-or[int64]$package.issuerControllerEpoch-ne[int64]$controller.controllerEpoch-or[string]$package.controllerControlIdentity-cne(Get-MinimalFileIdentity $ControllerFile)){throw 'ACTOR_BOUND_UPGRADE_CONTROLLER_AUTHORITY_DRIFT'}
    $records=New-Object 'System.Collections.Generic.List[object]';$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in @($state.objects)){
        $entryRaw=$entry|ConvertTo-Json -Compress;Assert-MinimalExactFields $entry $entryRaw @('relative','oldIdentity','newIdentity') 'actor-bound 1.15 upgrade object'
        if(-not($entry.relative-is[string])-or-not$seen.Add([string]$entry.relative)-or([string]$entry.oldIdentity-cne'MISSING'-and[string]$entry.oldIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')-or([string]$entry.newIdentity-cne'ABSENT'-and[string]$entry.newIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_OBJECT'}
        $records.Add([pscustomobject]@{relative=[string]$entry.relative;path=(Join-ChildPath $RepositoryRoot ([string]$entry.relative));oldIdentity=[string]$entry.oldIdentity;newIdentity=[string]$entry.newIdentity})
    }
    if(-not$seen.Contains($Migration.Relative)-or[string]@($state.objects)[-1].relative-cne$Migration.Relative){throw 'ACTOR_BOUND_UPGRADE_TASK_NOT_LAST'}
    $postDeclared=@($package.postObjectIdentities|ForEach-Object{[string]$_.path+'='+[string]$_.identity});$postExpected=@($records|ForEach-Object{[string]$_.relative+'='+[string]$_.newIdentity});[Array]::Sort($postDeclared,[StringComparer]::Ordinal);[Array]::Sort($postExpected,[StringComparer]::Ordinal)
    if($postDeclared.Count-ne$postExpected.Count-or[string]::Join("`n",$postDeclared)-cne[string]::Join("`n",$postExpected)){throw 'ACTOR_BOUND_UPGRADE_POSTIMAGE_DRIFT'}
    $materialFiles=New-Object 'System.Collections.Generic.List[string]'
    foreach($record in $records){
        Assert-ActorBoundLivePath $RepositoryRoot ([string]$record.relative)
        foreach($kind in @('old','new')){$expected=if($kind-ceq'old'){[string]$record.oldIdentity}else{[string]$record.newIdentity};$missing=$expected-in@('MISSING','ABSENT');$material=Join-ChildPath (Join-Path $recoveryRoot $kind) ([string]$record.relative);if($missing){if(Test-Path -LiteralPath $material){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_UNEXPECTED_MATERIAL'}}else{if((Get-OptionalIdentity $material)-cne$expected){throw 'ACTOR_BOUND_UPGRADE_RECOVERY_MATERIAL'};$materialFiles.Add($kind+'/'+[string]$record.relative)}}
        $live=Get-OptionalIdentity ([string]$record.path);$newLive=if([string]$record.newIdentity-ceq'ABSENT'){'MISSING'}else{[string]$record.newIdentity};if($live-cne[string]$record.oldIdentity-and$live-cne$newLive){throw ('ACTOR_BOUND_UPGRADE_UNKNOWN_LIVE_BYTES|'+[string]$record.relative)};$record|Add-Member -NotePropertyName liveIdentity -NotePropertyValue $live;$record|Add-Member -NotePropertyName terminalIdentity -NotePropertyValue $newLive
    }
    Assert-ExactTransactionTree $recoveryRoot (@('state.json')+@($materialFiles)) ([string[]]@()) 'ACTOR_BOUND_UPGRADE_RECOVERY_TREE_CLOSURE'
    $task=@($records|Where-Object{[string]$_.relative-ceq$Migration.Relative})[0]
    if([string]$task.liveIdentity-ceq[string]$task.terminalIdentity-and@($records|Where-Object{[string]$_.liveIdentity-cne[string]$_.terminalIdentity}).Count-ne0){throw 'ACTOR_BOUND_UPGRADE_TASK_ADVANCED_BEFORE_OBJECTS'}
    $remaining=@($records|Where-Object{[string]$_.liveIdentity-cne[string]$_.terminalIdentity})
    Write-Output ('UPGRADE_RECOVERY_WRITESET|'+[string]::Join('|',@($remaining.relative)))
    if(-not$ApplyChange){Write-Output ('RECOVERY_REQUIRED|from='+[string]$state.fromVersion+'|to='+$TargetVersion+'|remaining='+$remaining.Count);return}
    if($remaining.Count-eq0){Write-Output ('RECOVERY_COMPLETE|to='+$TargetVersion+'|writes=ZERO');return}
    $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
    foreach($record in @($remaining|Where-Object{[string]$_.relative-cne$Migration.Relative})){
        Assert-ActorBoundLivePath $RepositoryRoot ([string]$record.relative)
        if([string]$record.newIdentity-ceq'ABSENT'){[IO.File]::Delete([string]$record.path)}else{New-Item -ItemType Directory -Path (Split-Path -Parent ([string]$record.path)) -Force|Out-Null;[IO.File]::Copy((Join-ChildPath (Join-Path $recoveryRoot 'new') ([string]$record.relative)),[string]$record.path,$true)}
        if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.terminalIdentity){throw ('ACTOR_BOUND_UPGRADE_POSTIMAGE_DRIFT|'+[string]$record.relative)}
    }
    if([string]$task.liveIdentity-cne[string]$task.terminalIdentity){if((Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'};[IO.File]::Copy($taskStage,$Migration.Path,$true);if((Get-OptionalIdentity $Migration.Path)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_POSTIMAGE_DRIFT'}}
    foreach($record in $records){if((Get-OptionalIdentity ([string]$record.path))-cne[string]$record.terminalIdentity){throw ('ACTOR_BOUND_UPGRADE_FINAL_DRIFT|'+[string]$record.relative)}}
    Write-Output ('RECOVERED_UPGRADE|to='+$TargetVersion+'|recovery='+$recoveryRoot+'|writes-after-task=ZERO')
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
    if($TargetVersion-ceq'1.15.0'){Invoke-ActorBoundUpgrade115 $RepositoryRoot $TargetFramework $FromVersion $TargetVersion $ProjectId $ProjectFile $Migration $Objects $ApplyChange;return}
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
        foreach($item in $stateObjects){$object=@($objects|Where-Object{$_.relative-ceq[string]$item.relative})[0];if(Test-ManagedRouterRelative ([string]$item.relative)){Assert-ManagedRouterDestinations $RepositoryRoot};$old=Join-ChildPath (Join-Path $preparationRoot 'old') ([string]$item.relative);$new=Join-ChildPath (Join-Path $preparationRoot 'new') ([string]$item.relative);if([string]$item.oldIdentity-cne'MISSING'){New-Item -ItemType Directory -Path (Split-Path -Parent $old) -Force|Out-Null;[IO.File]::Copy($object.path,$old,$false)};New-Item -ItemType Directory -Path (Split-Path -Parent $new) -Force|Out-Null;Write-Utf8NoBom $new ([string]$object.content)}
        Write-Utf8NoBom (Join-Path $preparationRoot 'state.json') $stateText
        foreach($item in $stateObjects){if(Test-ManagedRouterRelative ([string]$item.relative)){Assert-ManagedRouterDestinations $RepositoryRoot};$live=Get-OptionalIdentity (Join-ChildPath $RepositoryRoot ([string]$item.relative));if($live-cne[string]$item.oldIdentity){throw ('OBJECT_DRIFT|'+[string]$item.relative)}}
        Assert-ActorBoundUpgradeLegacyMaterial $preparationRoot $stateObjects $stateText 'PREPARATION'
        [IO.Directory]::Move($preparationRoot,$recoveryRoot)
        Assert-ActorBoundUpgradeLegacyMaterial $recoveryRoot $stateObjects $stateText 'RECOVERY'
        $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
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
    $taskStage=Join-ChildPath (Join-Path $recoveryRoot 'new') $Migration.Relative;$check=@(& (Join-ChildPath $TargetFramework 'scripts/check-task-card.ps1') -TaskPath $taskStage 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0-or@($check|Where-Object{$_-clike'PASS*'}).Count-ne1){throw ('ACTOR_ROUTE_TARGET_TASK_REJECTED|'+($check-join';'))}
    $atomic=Join-ChildPath $RepositoryRoot $Migration.AtomicRelative;if((Get-OptionalIdentity $atomic)-ceq'MISSING'){New-Item -ItemType Directory -Path (Split-Path -Parent $atomic) -Force|Out-Null;[IO.File]::Copy($taskStage,$atomic,$false)}elseif((Get-OptionalIdentity $atomic)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_ATOMIC_STAGE_DRIFT'}
    foreach($item in @($liveStates|Where-Object{[string]$_.Entry.relative-cne$Migration.Relative})){
        if($item.Live-ceq[string]$item.Entry.newIdentity){continue};$managed=Test-ManagedRouterRelative ([string]$item.Entry.relative);if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};$livePath=Join-ChildPath $RepositoryRoot ([string]$item.Entry.relative);New-Item -ItemType Directory -Path (Split-Path -Parent $livePath) -Force|Out-Null;if($managed){Assert-ManagedRouterDestinations $RepositoryRoot};Set-UpgradeFile (Join-ChildPath (Join-Path $recoveryRoot 'new') ([string]$item.Entry.relative)) $livePath ([string]$item.Entry.oldIdentity) ([string]$item.Entry.newIdentity)
    }
    if((Get-OptionalIdentity $Migration.Path)-cne$Migration.OldIdentity){throw 'ACTOR_ROUTE_TASK_DRIFT'};[IO.File]::Move($atomic,$Migration.Path,$true);if((Get-OptionalIdentity $Migration.Path)-cne$Migration.NewIdentity){throw 'ACTOR_ROUTE_POSTIMAGE_DRIFT'}
    Write-Output ('RECOVERED_UPGRADE|to='+$TargetVersion+'|recovery='+$recoveryRoot+'|writes-after-task=ZERO')
}

function Get-ManagedAgentsTransition([string]$RepositoryRoot,[string]$SourceFramework,[string]$TargetFramework,[bool]$Install){
    Assert-ManagedRouterDestinations $RepositoryRoot
    $agentsPath=Join-Path $RepositoryRoot 'AGENTS.md';$skillPath=Join-Path $RepositoryRoot '.agents\skills\ai-workspace-router\SKILL.md'
    $templateAgents=Join-ChildPath $TargetFramework 'project-starter/AGENTS.md'
    $targetVersionObject=(Read-StrictUtf8NoBom (Join-ChildPath $TargetFramework 'VERSION.json'))|ConvertFrom-Json
    $targetUsesGlobalRouter=[string]$targetVersionObject.version-ceq'1.15.0'
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
            $sourceAgents=Read-StrictUtf8NoBom (Join-ChildPath $SourceFramework 'project-starter/AGENTS.md');$sourceBlock=$sourceAgents.TrimEnd("`n")
            if($block-cne$sourceBlock){throw 'AGENTS_MANAGED_BLOCK_CONFLICT'}
            $newAgents=Normalize-Text ($current.Substring(0,$start)+$targetBlock+$current.Substring($finish))
            $sourceSkill=Join-ChildPath $SourceFramework 'project-starter/.agents/skills/ai-workspace-router/SKILL.md'
            $skillDirectory=Split-Path -Parent $skillPath
            $skillFiles=@(if(Test-Path -LiteralPath $skillDirectory -PathType Container){Get-ChildItem -LiteralPath $skillDirectory -Recurse -File -Force})
            $skillDirectories=@(if(Test-Path -LiteralPath $skillDirectory -PathType Container){Get-ChildItem -LiteralPath $skillDirectory -Recurse -Directory -Force})
            if($skillFiles.Count-ne1-or$skillDirectories.Count-ne0-or-not(Test-Path -LiteralPath $skillPath -PathType Leaf)-or-not(Test-Path -LiteralPath $sourceSkill -PathType Leaf)-or(Get-MinimalFileIdentity $skillPath)-cne(Get-MinimalFileIdentity $sourceSkill)){throw 'ROUTER_SKILL_LOCAL_COPY_MIGRATION_CONFLICT'}
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
    $install=$TargetVersion-in@('1.14.0','1.14.1','1.15.0')
    $sourceProcessCarrierVersion=Get-ProcessCarrierContractVersion $FromVersion
    $targetProcessCarrierVersion=Get-ProcessCarrierContractVersion $TargetVersion
    if(($TargetVersion-ceq'1.15.0'-and$FromVersion-notin@('1.14.0','1.14.1'))-or($TargetVersion-in@('1.14.0','1.14.1')-and$FromVersion-notin@('1.11.0','1.12.0','1.13.0','1.14.0','1.14.1'))-or(-not$install-and($FromVersion-notin@('1.14.0','1.14.1')-or$TargetVersion-cne'1.13.0'))){throw 'FRAMEWORK_1_14_DIRECT_TRANSITION_PAIR'}
    $sourceFramework=Join-ChildPath (Join-ChildPath $FrameworkWorkspace 'framework/versions') $FromVersion;$targetFramework=Join-ChildPath (Join-ChildPath $FrameworkWorkspace 'framework/versions') $TargetVersion
    $projectPath=Join-Path $ControlRoot 'project.json';$bootstrapPath=Join-Path $ControlRoot 'BOOTSTRAP.md';$controllerPath=Join-Path $ControlRoot 'controller.json';$correctionsPath=Join-Path $ControlRoot 'corrections.json';$policyPath=Join-Path $ControlRoot 'process-policy.json'
    $projectRaw=Read-StrictUtf8NoBom $projectPath;$project=$projectRaw|ConvertFrom-Json
    $baseProjectFields=@('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion')
    $sourceHasStructuredPolicy=$false
    if($FromVersion-in@('1.14.0','1.14.1')){$projectFields=@($baseProjectFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy'));$expectedSchema=4;$sourceHasStructuredPolicy=$true}
    elseif($FromVersion-ceq'1.13.0'-and[int]$project.schemaVersion-eq4){$projectFields=@($baseProjectFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','processPolicy'));$expectedSchema=4;$sourceHasStructuredPolicy=$true}
    elseif($FromVersion-in@('1.12.0','1.13.0')){$projectFields=@($baseProjectFields+@('frameworkToolBackend','routineExcludedPaths','frameworkCapabilities'));$expectedSchema=3}
    else{$projectFields=@($baseProjectFields+@('routineExcludedPaths','frameworkCapabilities'));$expectedSchema=3}
    Assert-MinimalExactFields $project $projectRaw $projectFields 'Framework 1.14 transition project.json'
    if([int]$project.schemaVersion-ne$expectedSchema-or[string]$project.id-cne$ProjectId-or[string]$project.frameworkVersion-cne$FromVersion-or($FromVersion-in@('1.12.0','1.13.0','1.14.0','1.14.1')-and[string]$project.frameworkToolBackend-cne'powershell7')-or[string]$project.controlPlaneLayout-cne'repo-local'-or[string]$project.repositoryRoot-cne'..'-or-not($project.routineExcludedPaths-is[Array])-or-not($project.frameworkCapabilities-is[pscustomobject])){throw 'Framework transition source project is unhealthy.'}
    if($sourceHasStructuredPolicy-and(-not($project.processPolicy-is[pscustomobject])-or[int]$project.processPolicy.schemaVersion-ne1-or[string]$project.processPolicy.locator-cne'.ai-workspace/process-policy.json')){throw 'FRAMEWORK_1_14_SOURCE_PROJECT_INVALID'}
    $controllerRaw=Read-StrictUtf8NoBom $controllerPath;$controller=$controllerRaw|ConvertFrom-Json;Assert-MinimalController $controller $controllerRaw $ProjectId $ControllerId
    $sourceBootstrapTemplate=Read-StrictUtf8NoBom (Join-ChildPath $sourceFramework 'project-starter/BOOTSTRAP.md');$targetBootstrapTemplate=Read-StrictUtf8NoBom (Join-ChildPath $targetFramework 'project-starter/BOOTSTRAP.md')
    $currentBootstrap=Read-StrictUtf8NoBom $bootstrapPath;$expectedSource=Render-Bootstrap $sourceBootstrapTemplate $project $FromVersion;$currentBlock=Get-ManagedBootstrapBlock $currentBootstrap $bootstrapPath;$sourceBlock=Get-ManagedBootstrapBlock $expectedSource 'source Bootstrap'
    if($currentBlock.Text-cne$sourceBlock.Text){throw 'FRAMEWORK_1_14_SOURCE_BOOTSTRAP_DRIFT'}
    $project.frameworkVersion=$TargetVersion
    if($install){$project.schemaVersion=4;if($null-eq$project.PSObject.Properties['frameworkToolBackend']){$project|Add-Member -NotePropertyName frameworkToolBackend -NotePropertyValue 'powershell7'}else{$project.frameworkToolBackend='powershell7'};if($null-eq$project.PSObject.Properties['processPolicy']){$project|Add-Member -NotePropertyName processPolicy -NotePropertyValue ([pscustomobject]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'})}}
    $targetProject=Normalize-Text ($project|ConvertTo-Json -Depth 100)
    $renderedTarget=Render-Bootstrap $targetBootstrapTemplate $project $TargetVersion;$targetBlock=Get-ManagedBootstrapBlock $renderedTarget 'target Bootstrap';$targetBootstrap=Replace-ManagedBootstrapBlock $currentBootstrap $targetBlock.Text $currentBlock;$correctionBlockSource=if($install){$renderedTarget}else{$currentBootstrap};$targetBootstrap=Merge-CorrectionBootstrapBlock $targetBootstrap $correctionBlockSource 'preserved correction Bootstrap'
    if($sourceHasStructuredPolicy){
        $policyRaw=Read-StrictUtf8NoBom $policyPath;$policy=$policyRaw|ConvertFrom-Json;Assert-MinimalExactFields $policy $policyRaw @('schemaVersion','contractVersion','projectId','rules') 'Framework 1.14 transition process policy'
        if([int]$policy.schemaVersion-ne1-or[string]$policy.contractVersion-cne$sourceProcessCarrierVersion-or[string]$policy.projectId-cne$ProjectId-or-not($policy.rules-is[Array])){throw 'FRAMEWORK_1_14_SOURCE_POLICY_INVALID'}
        if($sourceProcessCarrierVersion-ceq$targetProcessCarrierVersion){$targetPolicy=$policyRaw}else{$policy.contractVersion=$targetProcessCarrierVersion;$targetPolicy=Normalize-Text ($policy|ConvertTo-Json -Depth 100)}
    }else{
        if(Test-Path -LiteralPath $policyPath){throw 'FRAMEWORK_1_14_INACTIVE_POLICY_COLLISION'}
        $targetPolicy=(Read-StrictUtf8NoBom (Join-ChildPath $targetFramework 'project-starter/process-policy.json')).Replace('{{PROJECT_ID_JSON}}',($ProjectId|ConvertTo-Json -Compress))
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
    $agents=Get-ManagedAgentsTransition $RepositoryRoot $sourceFramework $targetFramework $install
    $targetEvaluator=Join-ChildPath $targetFramework 'scripts/check-project-corrections.ps1'
    $preCorrection=Invoke-CorrectionEvaluationProjected $targetEvaluator $FrameworkWorkspace $TargetVersion $targetProject $targetBootstrap $correctionsPath $policyPath -TargetProcessPolicy $targetPolicy -TargetCorrections $targetCorrections
    Write-CorrectionEvaluation $preCorrection 'before cross-root projection'
    $objects=@(
      [pscustomobject]@{relative='.ai-workspace/project.json';path=$projectPath;content=$targetProject},
      [pscustomobject]@{relative='.ai-workspace/BOOTSTRAP.md';path=$bootstrapPath;content=$targetBootstrap},
      [pscustomobject]@{relative='.ai-workspace/corrections.json';path=$correctionsPath;content=$targetCorrections},
      [pscustomobject]@{relative='.ai-workspace/process-policy.json';path=$policyPath;content=$targetPolicy},
      [pscustomobject]@{relative='AGENTS.md';path=$agents.AgentsPath;content=$agents.AgentsContent},
      [pscustomobject]@{relative='.agents/skills/ai-workspace-router/SKILL.md';path=$agents.SkillPath;content=$agents.SkillContent}
    )
    if($TargetVersion-ceq'1.15.0'-and$null-eq$ActorMigration){throw 'ACTOR_BOUND_PROJECT_UPGRADE_ROUTE_REQUIRED'}
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
        foreach($object in $objects){if(Test-ManagedRouterRelative ([string]$object.relative)){Assert-ManagedRouterDestinations $RepositoryRoot};$oldIdentity=Get-OptionalIdentity $object.path;$oldStage=Join-ChildPath (Join-Path $transaction 'old') $object.relative;$newStage=Join-ChildPath (Join-Path $transaction 'new') $object.relative;if($oldIdentity-cne'MISSING'){New-Item -ItemType Directory -Path (Split-Path -Parent $oldStage) -Force|Out-Null;[IO.File]::Copy($object.path,$oldStage,$false)};if($null-ne$object.content){New-Item -ItemType Directory -Path (Split-Path -Parent $newStage) -Force|Out-Null;Write-Utf8NoBom $newStage ([string]$object.content);$newIdentity=Get-MinimalFileIdentity $newStage}else{$newIdentity='MISSING'};$stateObjects+=[ordered]@{relative=$object.relative;oldIdentity=$oldIdentity;newIdentity=$newIdentity}}
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
    foreach($name in $Expected){$expectedCount=if($name-ceq'schemaVersion'-and(('processPolicy'-cin$names)-or('routerCompatibility'-cin$names))){2}else{1};if([regex]::Matches($Raw,'"'+[regex]::Escape($name)+'"\s*:').Count-ne$expectedCount){throw "$Label duplicate or missing field: $name"}}
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

function Invoke-CorrectionEvaluationProjected([string]$Evaluator,[string]$FrameworkWorkspace,[string]$Version,[string]$TargetConfig,[string]$TargetBootstrap,[string]$CorrectionsFile,[string]$ProcessPolicyFile,[string]$TargetProcessPolicy='',[string]$TargetCorrections='',[switch]$AllowMissing) {
    $projectionRoot=Join-Path ([IO.Path]::GetTempPath()) ('aiw-correction-projection-'+[guid]::NewGuid().ToString('N'))
    $projectionControl=Join-Path $projectionRoot '.ai-workspace'
    try{
        New-Item -ItemType Directory -Path $projectionControl -Force|Out-Null
        $projectionConfig=Join-Path $projectionControl 'project.json';[IO.File]::WriteAllText($projectionConfig,$TargetConfig,$utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $projectionControl 'BOOTSTRAP.md'),$TargetBootstrap,$utf8NoBom)
        try{$projectedConfig=$TargetConfig|ConvertFrom-Json}catch{throw 'Projected project configuration is invalid JSON.'}
        if($null-ne$projectedConfig.PSObject.Properties['processPolicy']){
            $projectedPolicy=Join-Path $projectionControl 'process-policy.json'
            if(-not[string]::IsNullOrWhiteSpace($TargetProcessPolicy)){[IO.File]::WriteAllText($projectedPolicy,$TargetProcessPolicy,$utf8NoBom)}
            elseif(-not[string]::IsNullOrWhiteSpace($ProcessPolicyFile)-and(Test-Path -LiteralPath $ProcessPolicyFile -PathType Leaf)){Copy-Item -LiteralPath $ProcessPolicyFile -Destination $projectedPolicy}
            else{throw 'Projected process policy is missing.'}
        }
        $projectionCorrections=Join-Path $projectionControl 'corrections.json'
        if(-not[string]::IsNullOrWhiteSpace($TargetCorrections)){[IO.File]::WriteAllText($projectionCorrections,$TargetCorrections,$utf8NoBom)}
        elseif(Test-Path -LiteralPath $CorrectionsFile -PathType Leaf){Copy-Item -LiteralPath $CorrectionsFile -Destination $projectionCorrections}
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
    if($ToVersion-in@('1.12.0','1.13.0','1.14.0','1.14.1','1.15.0')){
        $toolchainPath=Join-ChildPath $targetFramework 'TOOLCHAIN.json';$toolchainRaw=Read-StrictUtf8NoBom $toolchainPath
        try{$toolchain=$toolchainRaw|ConvertFrom-Json}catch{throw 'FRAMEWORK_TOOLCHAIN_JSON'}
        $toolchainFields=@('schemaVersion','frameworkVersion','contractVersion','projectSelectionField')+$(if($ToVersion-ceq'1.15.0'){@('routerCompatibility')}else{@()})+@('officialBackends','conformance')
        Assert-MinimalExactFields $toolchain $toolchainRaw $toolchainFields 'Framework TOOLCHAIN.json'
        if(-not(Test-MinimalJsonInteger $toolchain.schemaVersion)-or[int]$toolchain.schemaVersion-ne1-or[string]$toolchain.frameworkVersion-cne$ToVersion-or[string]$toolchain.contractVersion-cne'1'-or[string]$toolchain.projectSelectionField-cne'frameworkToolBackend'-or-not($toolchain.officialBackends-is[System.Array])-or@($toolchain.officialBackends).Count-ne1){throw 'FRAMEWORK_TOOLCHAIN_VALUES'}
        $backend=@($toolchain.officialBackends)[0]
        if(-not($backend-is[pscustomobject])-or[string]$backend.id-cne'powershell7'-or[string]$backend.status-cne'OFFICIAL'-or-not($backend.runtime-is[pscustomobject])-or[string]$backend.runtime.command-cne'pwsh'-or[string]$backend.runtime.edition-cne'Core'-or-not(Test-MinimalJsonInteger $backend.runtime.minimumMajorVersion)-or[int]$backend.runtime.minimumMajorVersion-ne7-or-not($backend.platforms-is[System.Array])-or@($backend.platforms).Count-lt1-or-not($backend.entrypoints-is[pscustomobject])){throw 'FRAMEWORK_TOOLCHAIN_BACKEND'}
        $declaredPlatforms=@($backend.platforms|ForEach-Object{[string]$_})
        if(@($declaredPlatforms|Where-Object{$_-cnotin@('windows','linux','macos')}).Count-ne0-or@($declaredPlatforms|Select-Object -Unique).Count-ne$declaredPlatforms.Count){throw 'FRAMEWORK_TOOLCHAIN_PLATFORMS'}
        $currentPlatform=if([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)){'windows'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux)){'linux'}elseif([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)){'macos'}else{'unknown'}
        if($currentPlatform-cnotin$declaredPlatforms){throw ('FRAMEWORK_TOOL_PLATFORM_UNSUPPORTED|backend=powershell7|platform='+$currentPlatform)}
        foreach($entry in $backend.entrypoints.PSObject.Properties){$relative=[string]$entry.Value;if([string]::IsNullOrWhiteSpace($relative)-or$relative-cne$relative.Replace('\','/')-or[IO.Path]::IsPathRooted($relative)-or$relative.Contains('..')-or-not(Test-Path -LiteralPath (Join-ChildPath $targetFramework $relative) -PathType Leaf)){throw ('FRAMEWORK_TOOLCHAIN_ENTRYPOINT|'+$entry.Name)}}
        if($ToVersion-ceq'1.15.0'){
            $router=$toolchain.routerCompatibility;$routerFields=@('schemaVersion','skillName','status','requiredOperations','processCatalogSchemaVersion','processCatalogVersion','nativeRuleBodySource')
            $routerRaw=$router|ConvertTo-Json -Compress;Assert-MinimalExactFields $router $routerRaw $routerFields 'Framework routerCompatibility'
            if(-not(Test-MinimalJsonInteger $router.schemaVersion)-or[int]$router.schemaVersion-ne1-or[string]$router.skillName-cne'ai-workspace-router'-or[string]$router.status-cne'COMPATIBLE'-or-not(Test-MinimalJsonInteger $router.processCatalogSchemaVersion)-or[int]$router.processCatalogSchemaVersion-ne2-or[string]$router.processCatalogVersion-cne'3'-or[string]$router.nativeRuleBodySource-cne'MARKDOWN_EXACT_BLOCK'-or-not($router.requiredOperations-is[Array])-or[string]::Join("`n",@($router.requiredOperations))-cne[string]::Join("`n",@('LOAD_PLAN_RESOLVE','PROCESS_REQUIREMENTS_RESOLVE','WORKFLOW_ROUTE_RESOLVE'))){throw 'FRAMEWORK_ROUTER_COMPATIBILITY'}
        }
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

$actorRouteMigration=Get-ActorRouteMigration $repo $ToVersion $ActorRouteTaskPath $ExpectedActorRouteTaskIdentity $ActorRouteActor
if($null-ne$actorRouteMigration){
    $routeProjectRaw=Read-StrictUtf8NoBom $projectFile
    try{$routeProject=$routeProjectRaw|ConvertFrom-Json}catch{throw 'ACTOR_ROUTE_PROJECT_JSON'}
    if(-not($routeProject.id-is[string])-or[string]$routeProject.id-cne$ProjectId){throw 'ACTOR_ROUTE_PROJECT_ID'}
    if([string]::IsNullOrWhiteSpace($ControllerId)-or-not(Test-Path -LiteralPath $controllerFile -PathType Leaf)){throw 'ACTOR_ROUTE_CURRENT_CONTROLLER_REQUIRED'}
    $routeControllerRaw=Read-StrictUtf8NoBom $controllerFile
    try{$routeController=$routeControllerRaw|ConvertFrom-Json}catch{throw 'ACTOR_ROUTE_CONTROLLER_JSON'}
    Assert-MinimalController $routeController $routeControllerRaw $ProjectId $ControllerId
    $actorPreparation=if($ToVersion-ceq'1.15.0'){Join-ChildPath $repo ('.ai-workspace/tmp/upgrade-preparation/'+$ToVersion)}else{$null}
    if($null-ne$actorPreparation-and(Test-Path -LiteralPath $actorPreparation)){throw 'ACTOR_BOUND_UPGRADE_PREPARATION_REAUTHORIZATION_REQUIRED'}
    $actorRecovery=if($ToVersion-ceq'1.15.0'){Join-ChildPath $repo ('.ai-workspace/upgrade-recovery/'+$ToVersion)}else{Join-Path $repo ('.framework-actor-bound-upgrade-recovery-'+$ToVersion)}
    if(Test-Path -LiteralPath $actorRecovery){
        if($ToVersion-ceq'1.15.0'){Resume-ActorBoundUpgrade115 $repo $targetFramework $ToVersion $ProjectId $controllerFile $actorRouteMigration ([bool]$Apply)}else{Resume-ActorBoundUpgrade $repo $targetFramework $ToVersion $ProjectId $controllerFile $actorRouteMigration ([bool]$Apply)}
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
if($ToVersion-ceq'1.15.0'-and[string]$config.frameworkVersion-ceq'1.15.0'){
    if([string]::IsNullOrWhiteSpace($ControllerId)){throw 'ControllerId is required to validate an already-upgraded Framework 1.15.0 project.'}
    $registrationEntry=Join-Path (Split-Path -Parent $PSCommandPath) 'register-project.ps1'
    $validationOutput=@(& $registrationEntry -ProjectId $ProjectId -DisplayName ([string]$config.displayName) -FrameworkVersion '1.15.0' -RepositoryPath $repo -ControllerId $ControllerId 2>&1|ForEach-Object{[string]$_})
    if(-not(($validationOutput-join"`n").Contains('ALREADY_REGISTERED'))){throw ('ALREADY_UPGRADED_VALIDATION_FAILED|'+($validationOutput-join';'))}
    if($Apply){Write-Output 'ALREADY_UPGRADED|objects=0|host-router=UNCHANGED'}else{Write-Output 'WHAT_IF|from=1.15.0|to=1.15.0|objects=0|transaction=none'}
    return
}
if(($ToVersion-in@('1.14.0','1.14.1')-and[string]$config.frameworkVersion-in@('1.11.0','1.12.0','1.13.0','1.14.0','1.14.1'))-or($ToVersion-ceq'1.15.0'-and[string]$config.frameworkVersion-in@('1.14.0','1.14.1'))-or([string]$config.frameworkVersion-in@('1.14.0','1.14.1')-and$ToVersion-ceq'1.13.0')){
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
