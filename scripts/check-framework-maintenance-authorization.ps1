[CmdletBinding()]
param(
    [string]$ControlRepositoryPath=(Get-Location).Path,
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$ObservedActor,
    [Parameter(Mandatory)][string]$ObservedTaskId,
    [Parameter(Mandatory)][string]$ObservedOwner,
    [Parameter(Mandatory)][string[]]$ObservedAction,
    [Parameter(Mandatory)][string[]]$ObservedPath,
    [string[]]$ObservedIdentity=@(),
    [string]$ControllerControlPath='.ai-workspace/controller.json',
    [Parameter(Mandatory)][string]$ObservedRepositoryId,
    [string]$ProjectConfigPath='.ai-workspace/project.json',
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [string]$TaskPath,
    [string]$ExpectedTaskIdentity
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
try{
    $resolver=Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
    $resolvedOutput=@(& $resolver -ControlRepositoryPath $ControlRepositoryPath -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -AsJson 2>&1|ForEach-Object{[string]$_});$resolvedCode=$LASTEXITCODE
    if($resolvedCode-ne0-or$resolvedOutput.Count-ne1){throw ('MAINTENANCE_TARGET_RESOLUTION_FAILED|'+($resolvedOutput-join';'))}
    $resolved=$resolvedOutput[0]|ConvertFrom-Json
    if($ObservedRepositoryId-cnotin@('CONTROL',[string]$resolved.targetRepositoryId)){throw 'REPOSITORY_ID_UNKNOWN'}
    $checkerVersion=[string]$resolved.frameworkVersion
    $packageSelectionPath=if([IO.Path]::IsPathRooted($PackagePath)){$PackagePath}else{Join-Path ([string]$resolved.controlRoot) $PackagePath}
    try{$packageSelection=Get-Content -LiteralPath $packageSelectionPath -Raw -Encoding utf8|ConvertFrom-Json}catch{throw 'AUTHORIZATION_PACKAGE_SELECTION_UNAVAILABLE'}
    $effectiveTaskPath=if([string]::IsNullOrWhiteSpace($TaskPath)){'.ai-workspace/tasks/active/'+$ObservedTaskId+'.md'}else{$TaskPath}
    $effectiveTaskIdentity=if([string]::IsNullOrWhiteSpace($ExpectedTaskIdentity)){[string]$packageSelection.taskIdentity}else{$ExpectedTaskIdentity}
    $sameVersionStateRebind=$false;$sameVersionProjectionRefresh=$false
    if($packageSelection.schemaVersion-is [int64]-or$packageSelection.schemaVersion-is [int32]){
        if([int64]$packageSelection.schemaVersion-eq3){
            if(-not($packageSelection.frameworkVersion-is[string])-or[string]$packageSelection.frameworkVersion-cnotmatch'^\d+\.\d+\.\d+$'){throw 'UPGRADE_TARGET_VERSION_INVALID'}
            $sameVersionStatePath='.ai-workspace/upgrade-recovery/'+[string]$packageSelection.frameworkVersion+'/state.json'
            $sameVersionStateRebind=[string]$resolved.frameworkVersion-ceq[string]$packageSelection.frameworkVersion-and[string]$packageSelection.bundle-ceq'ACTOR_BOUND_PROJECT_UPGRADE'-and$packageSelection.actions-is[Array]-and[string]::Join('|',@($packageSelection.actions)) -ceq 'CONTROL_WRITE'-and$packageSelection.exactPaths-is[Array]-and[string]::Join('|',@($packageSelection.exactPaths)) -ceq $sameVersionStatePath
            if([string]$resolved.frameworkVersion-ceq[string]$packageSelection.frameworkVersion-and[string]$packageSelection.bundle-ceq'ACTOR_BOUND_PROJECT_UPGRADE'-and$packageSelection.actions-is[Array]-and[string]::Join('|',@($packageSelection.actions)) -ceq 'CONTROL_WRITE'-and$packageSelection.exactPaths-is[Array]-and$packageSelection.postObjectIdentities-is[Array]){
                $paths=@($packageSelection.exactPaths|ForEach-Object{[string]$_});$unique=@($paths|Select-Object -Unique);$live=@($paths|Where-Object{$_-cne$sameVersionStatePath});$allowed=@('.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','AGENTS.md','.gitignore','.agents/skills/ai-workspace-router/SKILL.md')
                $postPaths=@($packageSelection.postObjectIdentities|ForEach-Object{[string]$_.path});$postSorted=@($postPaths);$pathSorted=@($paths);[Array]::Sort($postSorted,[StringComparer]::Ordinal);[Array]::Sort($pathSorted,[StringComparer]::Ordinal)
                $sameVersionProjectionRefresh=$paths.Count-ge2-and$paths.Count-le6-and$paths.Count-eq$unique.Count-and[string]$paths[-1]-ceq$sameVersionStatePath-and@($live|Where-Object{$_-cnotin$allowed}).Count-eq0-and$postPaths.Count-eq$paths.Count-and[string]::Join("`n",$postSorted)-ceq[string]::Join("`n",$pathSorted)
            }
            if(-not$sameVersionStateRebind-and-not$sameVersionProjectionRefresh){throw 'MAINTENANCE_SCHEMA3_DIRECT_AUTHORIZATION_DENIED'}
            $checkerVersion=[string]$packageSelection.frameworkVersion
        }
    }
    $checker=Join-Path ([string]$resolved.targetRoot) ('framework\versions\'+$checkerVersion+'\scripts\check-authorization.ps1')
    if(-not(Test-Path -LiteralPath $checker -PathType Leaf)){throw 'AUTHORIZATION_CHECKER_MISSING'}
    $control=[string]$resolved.controlRoot;Push-Location $control
    try{
        $args=@{PackagePath=$PackagePath;ObservedActor=$ObservedActor;ObservedTaskId=$ObservedTaskId;ObservedOwner=$ObservedOwner;ObservedAction=@($ObservedAction);ObservedPath=@($ObservedPath);ObservedIdentity=@($ObservedIdentity);ControllerControlPath=$ControllerControlPath;ObservedRepositoryId=$ObservedRepositoryId;ProjectConfigPath=$ProjectConfigPath;ExpectedProjectConfigIdentity=$ExpectedProjectConfigIdentity;TaskPath=$effectiveTaskPath;ExpectedTaskIdentity=$effectiveTaskIdentity;RootRepositoryBindingValidated=$true}
        if($sameVersionStateRebind-or$sameVersionProjectionRefresh){
            $result=@(& $checker @args 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
            if($code-eq2-and$result.Count-eq1-and[string]$result[0]-ceq'FAIL|POST_IDENTITY_RECOVERY_PATH'){$exception=if($sameVersionProjectionRefresh){'SAME_VERSION_CANDIDATE_MANAGED_PROJECTION_REFRESH'}else{'SAME_VERSION_CANDIDATE_STATE_REBIND'};Write-Output ('PASS|task='+$ObservedTaskId+'|actor='+$ObservedActor+'|action=CONTROL_WRITE|paths='+@($ObservedPath).Count+'|root-exception='+$exception);exit 0}
            $result|Write-Output;exit $code
        }
        & $checker @args;exit $LASTEXITCODE
    }finally{Pop-Location}
}catch{Write-Output ('FAIL|framework-maintenance-authorization|'+[string]$_.Exception.Message);exit 2}
