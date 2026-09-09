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
function Get-VerifiedGitPaths {
    param([string]$Root,[string]$Operation,[string[]]$Pathspecs,$Allow,$Excluded,[bool]$IncludeExcluded)
    $args = @('-C',$Root,'-c','core.quotepath=false','-c','core.excludesFile=.git/info/ai-workspace-empty-excludes-v1','-c','diff.renames=false')
    if($Operation -ceq 'STATUS'){
        $args += @('status','--no-renames','--porcelain=v1','-z','--untracked-files=all','--')
    }else{
        $args += @('diff','--no-renames','--no-ext-diff','--no-textconv','--name-only','-z')
        if($Operation -ceq 'INDEX'){$args += '--cached'}
        $args += '--'
    }
    # Preserve NUL bytes and keep benign Git stderr warnings out of path records.
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=(Get-Command git -CommandType Application -ErrorAction Stop).Source
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false,$true)
    foreach($argument in @($args+$Pathspecs)){$start.ArgumentList.Add([string]$argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    try{
        if(-not$process.Start()){throw 'GIT_PATH_METADATA_START_FAILED'}
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
        if($process.ExitCode-ne0){throw 'GIT_PATH_METADATA_FAILED'}
    }finally{$process.Dispose()}
    if($text.Length -gt 0 -and -not $text.EndsWith([string][char]0)){throw 'GIT_PATH_METADATA_FORMAT'}
    $paths = @()
    foreach($record in $text.Split([char]0)){
        if($record.Length -eq 0){continue}
        $path = $record
        if($Operation -ceq 'STATUS'){
            if($record.Length -lt 4 -or $record[2] -cne ' ' -or $record.Substring(0,2) -match '[RC]'){throw 'GIT_PATH_METADATA_FORMAT'}
            $path = $record.Substring(3)
        }
        if([string]::IsNullOrWhiteSpace($path) -or [IO.Path]::IsPathRooted($path) -or $path.Contains('\') -or @($path.Split('/') | Where-Object{$_ -in @('','.', '..')}).Count -gt 0){throw 'GIT_PATH_METADATA_FORMAT'}
        $allowed = $false
        foreach($prefix in $Allow){if($path -ceq $prefix -or $path.StartsWith($prefix+'/',[StringComparison]::Ordinal)){$allowed=$true}}
        if(-not $allowed){throw 'GIT_PATH_OUTSIDE_ALLOWLIST'}
        if(-not $IncludeExcluded){foreach($prefix in $Excluded){if($path -ceq $prefix -or $path.StartsWith($prefix+'/',[StringComparison]::Ordinal)){throw 'ROUTINE_EXCLUSION_OUTPUT_DETECTED'}}}
        $paths += $path
    }
    return ,$paths
}

try{
    if(-not[string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('GIT_INDEX_FILE','Process'))){Write-Unverified 'GIT_ENVIRONMENT_OVERRIDE_GIT_INDEX_FILE'}
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
    $arguments=switch($Operation){'STATUS'{@('-C',$root,'-c','status.renames=false','status','--no-renames','--porcelain=v1','--untracked-files=all','--')+$pathspecs};'DIFF'{@('-C',$root,'-c','diff.renames=false','diff','--no-renames','--no-ext-diff','--no-textconv','--')+$pathspecs};'INDEX'{@('-C',$root,'-c','diff.renames=false','diff','--cached','--no-renames','--name-status','--')+$pathspecs}}
    $metadataBefore = Get-VerifiedGitPaths $root $Operation $pathspecs $allow $excluded ([bool]$IncludeRoutineExcluded)
    $output=@(& git @arguments 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0){throw ('GIT_COMMAND_FAILED|'+$LASTEXITCODE)}
    $metadataAfter = Get-VerifiedGitPaths $root $Operation $pathspecs $allow $excluded ([bool]$IncludeRoutineExcluded)
    if([string]::Join([string][char]0,$metadataBefore)-cne[string]::Join([string][char]0,$metadataAfter)){throw 'GIT_PATH_METADATA_DRIFT'}

    [ordered]@{status='VERIFIED';operation=$Operation;repositoryId=$RepositoryId;launched=$true;paths=@($allow|Sort-Object);output=@($output)}|ConvertTo-Json -Depth 5 -Compress
    exit 0
}catch{Write-Unverified ([string]$_.Exception.Message)}
