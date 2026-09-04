[CmdletBinding()]
param(
    [Alias('ProjectRoot')][string]$ControlRepositoryPath=(Get-Location).Path,
    [Parameter(Mandatory)][ValidateSet('STATUS','DIFF','INDEX')][string]$Operation,
    [Parameter(Mandatory)][string[]]$AllowPath,
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [Parameter(Mandatory)][string]$RepositoryId,
    [switch]$IncludeRoutineExcluded
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
function ConvertTo-Path([string]$Value){if([string]::IsNullOrWhiteSpace($Value)-or$Value-cne$Value.Trim()){throw 'PATH_EMPTY'};$path=$Value.Replace('\','/').TrimEnd('/');if([string]::IsNullOrWhiteSpace($path)-or[IO.Path]::IsPathRooted($path)-or$path.Contains(':')){throw 'PATH_INVALID'};foreach($part in $path.Split('/')){if($part-in@('','.', '..')){throw 'PATH_INVALID'}};return $path}
function Write-Unverified([string]$Reason){[ordered]@{status='UNVERIFIED';operation=$Operation;repositoryId=$RepositoryId;launched=$false;reason=$Reason;paths=@($AllowPath);output=@()}|ConvertTo-Json -Depth 5 -Compress;exit 2}
try{
    $resolver=Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
    $resolvedOutput=@(& $resolver -ControlRepositoryPath $ControlRepositoryPath -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -AsJson 2>&1|ForEach-Object{[string]$_});$resolvedCode=$LASTEXITCODE
    if($resolvedCode-ne0-or$resolvedOutput.Count-ne1){throw ('MAINTENANCE_TARGET_RESOLUTION_FAILED|'+($resolvedOutput-join';'))}
    $resolved=$resolvedOutput[0]|ConvertFrom-Json
    $config=Get-Content -LiteralPath (Join-Path ([string]$resolved.controlRoot) '.ai-workspace/project.json') -Raw -Encoding utf8|ConvertFrom-Json -Depth 20
    if($RepositoryId-ceq'CONTROL'){$root=[string]$resolved.controlRoot;$selectedExclusions=@($config.routineExcludedPaths)}elseif($RepositoryId-ceq[string]$resolved.targetRepositoryId){$root=[string]$resolved.targetRoot;$selectedExclusions=@($config.frameworkTarget.routineExcludedPaths)}else{throw 'REPOSITORY_ID_UNKNOWN'}
    $allow=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($value in $AllowPath){if(-not$allow.Add((ConvertTo-Path ([string]$value)))){throw 'ALLOW_PATH_DUPLICATE'}};if($allow.Count-eq0){throw 'ALLOW_PATH_EMPTY'}
    $excluded=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);foreach($value in $selectedExclusions){if(-not$excluded.Add((ConvertTo-Path ([string]$value)))){throw 'ROUTINE_EXCLUSION_DUPLICATE'}}
    if($IncludeRoutineExcluded){foreach($path in $allow){if(-not$excluded.Contains($path)){throw 'EXCLUDED_OVERRIDE_MUST_BE_EXACT'}}}
    $pathspecs=@($allow|Sort-Object|ForEach-Object{':(top,literal)'+$_});if(-not$IncludeRoutineExcluded){$pathspecs+=@($excluded|Sort-Object|ForEach-Object{':(top,exclude,literal)'+$_})}
    $arguments=switch($Operation){'STATUS'{@('-C',$root,'-c','status.renames=false','status','--no-renames','--porcelain=v1','--untracked-files=all','--')+$pathspecs};'DIFF'{@('-C',$root,'-c','diff.renames=false','diff','--no-renames','--no-ext-diff','--')+$pathspecs};'INDEX'{@('-C',$root,'-c','diff.renames=false','diff','--cached','--no-renames','--name-status','--')+$pathspecs}}
    $output=@(& git @arguments 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0){throw ('GIT_COMMAND_FAILED|'+$LASTEXITCODE)}
    if(-not$IncludeRoutineExcluded){foreach($line in $output){foreach($path in $excluded){if($line-match[regex]::Escape($path)){throw 'ROUTINE_EXCLUSION_OUTPUT_DETECTED'}}}}
    [ordered]@{status='VERIFIED';operation=$Operation;repositoryId=$RepositoryId;launched=$true;paths=@($allow|Sort-Object);output=@($output)}|ConvertTo-Json -Depth 5 -Compress
    exit 0
}catch{Write-Unverified ([string]$_.Exception.Message)}
