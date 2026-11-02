[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][ValidateSet('STATUS','DIFF','INDEX')][string]$Operation,
    [Parameter(Mandatory = $true)][string[]]$AllowPath,
    [Parameter(Mandatory = $true)][string]$ExpectedProjectConfigIdentity,
    [string]$RepositoryId = 'PROJECT',
    [switch]$IncludeRoutineExcluded,
    [string]$TaskPath,
    [string]$ExecutionTargetRef,
    [string]$ExpectedTargetState,
    [string[]]$ProtectedPath=@()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'KnowledgeSources.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1')
$aiwPublicationScopeLease=$null

if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}
$utf8Strict = New-Object Text.UTF8Encoding($false, $true)

function Get-FileIdentity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return $bytes.Length.ToString() + '|' + ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Test-JsonWhitespace([char]$Character) {
    return $Character -eq [char]0x20 -or $Character -eq [char]0x09 -or $Character -eq [char]0x0A -or $Character -eq [char]0x0D
}

function Skip-JsonWhitespace([string]$Text,[ref]$Index) {
    while ($Index.Value -lt $Text.Length -and (Test-JsonWhitespace $Text[$Index.Value])) { $Index.Value++ }
}

function Read-JsonStringToken([string]$Text,[ref]$Index) {
    if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne [char]0x22) { throw 'JSON_STRING' }
    $start=$Index.Value;$cursor=$start+1
    while ($cursor -lt $Text.Length) {
        $character=$Text[$cursor]
        if ([int]$character -lt 0x20) { throw 'JSON_STRING' }
        if ($character -eq [char]0x5C) {
            $cursor++;if ($cursor -ge $Text.Length) { throw 'JSON_STRING' }
            $escape=$Text[$cursor]
            if ($escape -eq [char]0x75) {
                if ($cursor+4 -ge $Text.Length) { throw 'JSON_STRING' }
                for ($offset=1;$offset -le 4;$offset++) { if ($Text[$cursor+$offset] -notmatch '^[0-9A-Fa-f]$') { throw 'JSON_STRING' } }
                $cursor+=5;continue
            }
            if ('"\/bfnrt'.IndexOf($escape) -lt 0) { throw 'JSON_STRING' }
            $cursor++;continue
        }
        if ($character -eq [char]0x22) {
            $cursor++;$token=$Text.Substring($start,$cursor-$start);$Index.Value=$cursor
            try { return [string]($token | ConvertFrom-Json) } catch { throw 'JSON_STRING' }
        }
        $cursor++
    }
    throw 'JSON_STRING'
}

function Read-JsonValue([string]$Text,[ref]$Index) {
    Skip-JsonWhitespace $Text $Index
    if ($Index.Value -ge $Text.Length) { throw 'JSON_VALUE' }
    $character=$Text[$Index.Value]
    if ($character -eq [char]0x22) { $null=Read-JsonStringToken $Text $Index;return }
    if ($character -eq [char]0x7B) { Read-JsonObject $Text $Index;return }
    if ($character -eq [char]0x5B) { Read-JsonArray $Text $Index;return }
    $start=$Index.Value
    while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -notin @([char]0x2C,[char]0x5D,[char]0x7D) -and -not (Test-JsonWhitespace $Text[$Index.Value])) { $Index.Value++ }
    if ($Index.Value -eq $start) { throw 'JSON_VALUE' }
    $token=$Text.Substring($start,$Index.Value-$start)
    if ($token -cnotmatch '^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$') { throw 'JSON_VALUE' }
}

function Read-JsonObject([string]$Text,[ref]$Index) {
    if ($Text[$Index.Value] -ne [char]0x7B) { throw 'JSON_OBJECT' }
    $Index.Value++;Skip-JsonWhitespace $Text $Index
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq [char]0x7D) { $Index.Value++;return }
    while ($Index.Value -lt $Text.Length) {
        $name=Read-JsonStringToken $Text $Index
        if (-not $seen.Add($name)) { throw ('JSON_DUPLICATE_FIELD|'+$name) }
        Skip-JsonWhitespace $Text $Index
        if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne [char]0x3A) { throw 'JSON_OBJECT' }
        $Index.Value++;Read-JsonValue $Text $Index;Skip-JsonWhitespace $Text $Index
        if ($Index.Value -ge $Text.Length) { throw 'JSON_OBJECT' }
        if ($Text[$Index.Value] -eq [char]0x2C) { $Index.Value++;Skip-JsonWhitespace $Text $Index;continue }
        if ($Text[$Index.Value] -eq [char]0x7D) { $Index.Value++;return }
        throw 'JSON_OBJECT'
    }
    throw 'JSON_OBJECT'
}

function Read-JsonArray([string]$Text,[ref]$Index) {
    if ($Text[$Index.Value] -ne [char]0x5B) { throw 'JSON_ARRAY' }
    $Index.Value++;Skip-JsonWhitespace $Text $Index
    if ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -eq [char]0x5D) { $Index.Value++;return }
    while ($Index.Value -lt $Text.Length) {
        Read-JsonValue $Text $Index;Skip-JsonWhitespace $Text $Index
        if ($Index.Value -ge $Text.Length) { throw 'JSON_ARRAY' }
        if ($Text[$Index.Value] -eq [char]0x2C) { $Index.Value++;Skip-JsonWhitespace $Text $Index;continue }
        if ($Text[$Index.Value] -eq [char]0x5D) { $Index.Value++;return }
        throw 'JSON_ARRAY'
    }
    throw 'JSON_ARRAY'
}

function ConvertTo-RoutinePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) { throw 'ROUTINE_PATH_EMPTY_OR_WHITESPACE' }
    $path = $Value.Replace('\','/')
    if ([regex]::IsMatch($path,'[<>"|?*]')) { throw 'ROUTINE_PATH_LITERAL_METACHAR' }
    if ([IO.Path]::IsPathRooted($path) -or $path.StartsWith('/') -or $path.Contains(':')) { throw 'ROUTINE_PATH_ROOTED' }
    if (-not [string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw 'ROUTINE_PATH_NOT_NFC' }
    $parts = $path.Split('/')
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..')) { throw 'ROUTINE_PATH_COMPONENT' }
        if ($part.EndsWith('.') -or $part.EndsWith(' ') -or [regex]::IsMatch($part,'[\x00-\x1F]')) { throw 'ROUTINE_PATH_COMPONENT' }
        if ($part.Split('.')[0] -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw 'ROUTINE_PATH_RESERVED' }
    }
    return [string]::Join('/',$parts)
}

function Read-StrictConfig([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'PROJECT_CONFIG_BOM' }
    try { $raw = $utf8Strict.GetString($bytes) } catch { throw 'PROJECT_CONFIG_UTF8' }
    if ($raw.Contains([char]0) -or $raw.Contains([char]0xFFFD)) { throw 'PROJECT_CONFIG_TEXT_FORMAT' }
    $cursor=0
    try { Read-JsonValue $raw ([ref]$cursor);Skip-JsonWhitespace $raw ([ref]$cursor);if ($cursor -ne $raw.Length) { throw 'JSON_TRAILING' } }
    catch { throw ('PROJECT_CONFIG_'+[string]$_.Exception.Message) }
    return $raw
}



function Assert-GitTop([string]$Root,[string]$Prefix) {
    try {$received=Invoke-VerifiedGitNative @('-C',$Root,'rev-parse','--show-toplevel') ($Prefix+'_GIT_TOP');$gitTopOutput=Get-VerifiedGitLines $received.stdout ($Prefix+'_GIT_TOP')}
    catch {throw "${Prefix}_GIT_TOP_UNAVAILABLE"}
    if ($received.exitCode -ne 0 -or $gitTopOutput.Count -ne 1) { throw "${Prefix}_GIT_TOP_UNAVAILABLE" }
    $gitTop = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$gitTopOutput[0]))
    if ([IO.Path]::GetRelativePath($gitTop,$Root) -cne '.') { throw "${Prefix}_ROOT_NOT_GIT_TOP" }
}

function Write-Unverified([string]$Reason,[bool]$Launched=$false) {
    [pscustomobject][ordered]@{ status='UNVERIFIED'; operation=$Operation; repositoryId=$RepositoryId; reason=$Reason; launched=$Launched } | ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii
    exit 3
}

# Private byte reception for this safe-git entry; no console or shell mutation.
function Invoke-VerifiedGitNative([string[]]$Arguments,[string]$Label) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=(Get-Command git -CommandType Application -ErrorAction Stop).Source
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($argument in $Arguments){$start.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    $stdout=[IO.MemoryStream]::new();$stderr=[IO.MemoryStream]::new()
    $cancel=[Threading.CancellationTokenSource]::new(30000);$started=$false
    try {
        try {$started=$process.Start()} catch {throw "${Label}_START_FAILED"}
        if(-not$started){throw "${Label}_START_FAILED"}
        $outRead=$process.StandardOutput.BaseStream.CopyToAsync($stdout,81920,$cancel.Token)
        $errRead=$process.StandardError.BaseStream.CopyToAsync($stderr,81920,$cancel.Token)
        if(-not$process.WaitForExit(30000)){throw "${Label}_TIMEOUT"}
        try {$drained=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($outRead,$errRead),5000)} catch {throw "${Label}_DRAIN_FAILED"}
        if(-not$drained){throw "${Label}_DRAIN_TIMEOUT"}
        $null=$outRead.GetAwaiter().GetResult();$null=$errRead.GetAwaiter().GetResult()
        return [pscustomobject]@{exitCode=$process.ExitCode;stdout=$stdout.ToArray();stderr=$stderr.ToArray()}
    } finally {
        $cancel.Cancel()
        if($started-and-not$process.HasExited){try{$process.Kill($true);$null=$process.WaitForExit(5000)}catch{}}
        $process.Dispose();$stdout.Dispose();$stderr.Dispose();$cancel.Dispose()
    }
}
function Get-VerifiedGitLines([byte[]]$Bytes,[string]$Label) {
    try {$text=[Text.UTF8Encoding]::new($false,$true).GetString($Bytes)} catch {throw "${Label}_UTF8"}
    $lines=[Collections.Generic.List[string]]::new()
    if($text.Length){
        foreach($line in [regex]::Split($text,'\r?\n')){$lines.Add($line)}
        if($text.EndsWith("`n")){$lines.RemoveAt($lines.Count-1)}
    }
    return ,$lines.ToArray()
}

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
    # Metadata consumes only strict UTF-8 stdout, retaining the final NUL.
    $received=Invoke-VerifiedGitNative @($args+$Pathspecs) 'GIT_PATH_METADATA'
    if($received.exitCode-ne0){throw 'GIT_PATH_METADATA_FAILED'}
    try {$text=[Text.UTF8Encoding]::new($false,$true).GetString($received.stdout)} catch {throw 'GIT_PATH_METADATA_UTF8'}
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

try {
    foreach ($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE')) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name,'Process'))) { throw ('GIT_ENVIRONMENT_OVERRIDE_' + $name) }
    }
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { throw 'PROJECT_ROOT_MISSING' }
    $controlRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).ProviderPath))
    $aiwPublicationScopeLease=Enter-AiwProjectSourceScope -ProjectRoot $controlRoot
    Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1') -Force
    Assert-AiwNoControlTransition $controlRoot
    if ((Get-Item -LiteralPath $controlRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'PROJECT_ROOT_REPARSE' }

    $configPath = Join-Path $controlRoot '.ai-workspace/project.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'PROJECT_CONFIG_MISSING' }
    if ((Get-Item -LiteralPath $configPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'PROJECT_CONFIG_REPARSE' }
    if ((Get-FileIdentity $configPath) -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
    $raw = Read-StrictConfig $configPath
    try { $config = $raw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
    if (-not ($config -is [pscustomobject]) -or -not (Test-JsonInteger $config.schemaVersion)) { throw 'PROJECT_CONFIG_VALUES' }

    $root = $controlRoot
    $selectedExclusions = @()
    $configSchemaVersion = [int]$config.schemaVersion
    $repoLocalLayout = $config.controlPlaneLayout -is [string] -and [string]$config.controlPlaneLayout -ceq 'repo-local'
    if ($configSchemaVersion -eq 7 -and $repoLocalLayout) {
        if ($RepositoryId -cne 'PROJECT') { throw 'REPOSITORY_ID_PROJECT_ONLY' }
        $expectedFields = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities','sourceBindings')
        $expectedFields += 'processPolicy'
        $names = @($config.PSObject.Properties.Name)
        if ($names.Count -ne $expectedFields.Count -or @($expectedFields | Where-Object { $_ -cnotin $names }).Count -ne 0) { throw 'PROJECT_CONFIG_FIELDS' }
        # Read-ProjectConfig already rejects duplicate members recursively.
        if (-not ($config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.id) -or
            -not ($config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.displayName) -or
            -not ($config.controlPlaneLayout -is [string]) -or [string]$config.controlPlaneLayout -cne 'repo-local' -or
            -not ($config.repositoryRoot -is [string]) -or [string]$config.repositoryRoot -cne '..' -or
            -not ($config.frameworkVersion -is [string]) -or [string]$config.frameworkVersion -cne '2.0.0' -or
            -not ($config.frameworkToolBackend -is [string]) -or [string]$config.frameworkToolBackend -cne 'powershell7' -or
            -not ($config.routineExcludedPaths -is [System.Array])) { throw 'PROJECT_CONFIG_VALUES' }
        if ($configSchemaVersion -eq 7) {
            if (-not ($config.processPolicy -is [pscustomobject])) { throw 'PROJECT_CONFIG_PROCESS_POLICY' }
            $policyFields = @($config.processPolicy.PSObject.Properties.Name)
            if ($policyFields.Count -ne 2 -or $policyFields -cnotcontains 'schemaVersion' -or $policyFields -cnotcontains 'locator' -or
                -not (Test-JsonInteger $config.processPolicy.schemaVersion) -or [int]$config.processPolicy.schemaVersion -ne 3 -or
                -not ($config.processPolicy.locator -is [string]) -or [string]$config.processPolicy.locator -cne '.ai-workspace/process-policy.json') { throw 'PROJECT_CONFIG_PROCESS_POLICY' }
        }
        Import-Module (Join-Path $PSScriptRoot 'ObjectFormats.psm1')
        $currentProject=Read-AiwCurrentObject -ObjectType PROJECT_CONFIG -Locator (Join-Path $controlRoot '.ai-workspace/project.json') -ExpectedIdentity $ExpectedProjectConfigIdentity -Context ([pscustomobject]@{})
        if($currentProject.Status-cne'CURRENT'){throw 'FORMAT_WRITE_REQUIRED|PROJECT_CONFIG'}
        $null=Assert-AiwFrameworkCapabilities $config.frameworkCapabilities
        $selectedExclusions = @($config.routineExcludedPaths)
    } else {
        throw 'PROJECT_CONFIG_REPO_LOCAL_REQUIRED'
    }

    Assert-GitTop $controlRoot 'PROJECT'

    $target=$null
    $isolated=$TaskPath-or$ExecutionTargetRef-or$ExpectedTargetState
    if($isolated){
        if(-not($TaskPath-and$ExecutionTargetRef-and$ExpectedTargetState)-or$RepositoryId-cne'PROJECT'-or$IncludeRoutineExcluded){throw 'EXECUTION_TARGET_SAFE_GIT_INPUT'}
        Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
        Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
        $ref=(ConvertFrom-AiwStrictInputJson $ExecutionTargetRef).Value;$state=(ConvertFrom-AiwStrictInputJson $ExpectedTargetState).Value
        $target=Resolve-AiwExecutionTargetContext $controlRoot $config.id $TaskPath $ref @($selectedExclusions) $ProtectedPath
        $null=Assert-AiwExecutionTargetState $target $state
        $root=$target.executionRoot
        if($target.targetKind-cne'GIT_WORKTREE'){throw 'EXECUTION_TARGET_SAFE_GIT_WORKTREE_REQUIRED'}
        foreach($path in $AllowPath){$null=Resolve-AiwExecutionTargetCandidatePath $target $path @($selectedExclusions) $ProtectedPath}
        foreach($ban in @(Get-AiwExecutionTargetDeniedPaths $target @($selectedExclusions) $ProtectedPath)){
            if($ban.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$selectedExclusions+=[IO.Path]::GetRelativePath($root,$ban).Replace('\','/')}
        }
        $selectedExclusions=@($selectedExclusions|Select-Object -Unique)
    }elseif($ProtectedPath.Count){throw 'EXECUTION_TARGET_SAFE_GIT_INPUT'}

    $allow = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($pathValue in $AllowPath) { if (-not $allow.Add((ConvertTo-RoutinePath $pathValue))) { throw 'ALLOW_PATH_DUPLICATE' } }
    if ($allow.Count -eq 0) { throw 'ALLOW_PATH_EMPTY' }
    $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($pathValue in $selectedExclusions) {
        if (-not ($pathValue -is [string])) { throw 'ROUTINE_EXCLUSION_TYPE' }
        if (-not $excluded.Add((ConvertTo-RoutinePath ([string]$pathValue)))) { throw 'ROUTINE_EXCLUSION_DUPLICATE' }
    }
    if ($IncludeRoutineExcluded) {
        foreach ($path in $allow) { if (-not $excluded.Contains($path)) { throw 'EXCLUDED_OVERRIDE_MUST_BE_EXACT' } }
    }

    $pathspecs = @($allow | Sort-Object | ForEach-Object { ':(top,literal)' + $_ })
    if (-not $IncludeRoutineExcluded) { $pathspecs += @($excluded | Sort-Object | ForEach-Object { ':(top,exclude,literal)' + $_ }) }
    $emptyExcludes = '.git/info/ai-workspace-empty-excludes-v1'
    if (Test-Path -LiteralPath (Join-Path $root $emptyExcludes)) { Write-Unverified 'RESERVED_EXCLUDES_PATH_EXISTS' }
    $arguments = switch ($Operation) {
        'STATUS' { @('-C',$root,'-c',('core.excludesFile='+$emptyExcludes),'-c','status.renames=false','status','--no-renames','--porcelain=v1','--untracked-files=all','--') + $pathspecs }
        'DIFF' { @('-C',$root,'-c',('core.excludesFile='+$emptyExcludes),'-c','diff.renames=false','diff','--no-renames','--no-ext-diff','--no-textconv','--') + $pathspecs }
        'INDEX' { @('-C',$root,'-c',('core.excludesFile='+$emptyExcludes),'-c','diff.renames=false','diff','--cached','--no-renames','--name-status','--') + $pathspecs }
    }
    $metadataBefore = Get-VerifiedGitPaths $root $Operation $pathspecs $allow $excluded ([bool]$IncludeRoutineExcluded)
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $received=Invoke-VerifiedGitNative $arguments 'GIT_COMMAND';$gitExit=$received.exitCode
        # Preserve the original launched=true/nonzero branch before decoding.
        if($gitExit-eq0){$outLines=Get-VerifiedGitLines $received.stdout 'GIT_STDOUT';$errLines=Get-VerifiedGitLines $received.stderr 'GIT_STDERR';$output=@($outLines)+@($errLines)}
    }
    finally { $ErrorActionPreference = $previousErrorAction }
    if ($gitExit -ne 0) { Write-Unverified ('GIT_COMMAND_FAILED|' + $gitExit) $true }
    $metadataAfter = Get-VerifiedGitPaths $root $Operation $pathspecs $allow $excluded ([bool]$IncludeRoutineExcluded)
    if([string]::Join([string][char]0,$metadataBefore)-cne[string]::Join([string][char]0,$metadataAfter)){throw 'GIT_PATH_METADATA_DRIFT'}
    if($null-ne$target){
        $fresh=Resolve-AiwExecutionTargetContext $controlRoot $config.id $TaskPath $ref @($selectedExclusions) $ProtectedPath
        $null=Assert-AiwExecutionTargetState $fresh $state
        foreach($field in @('commonGitDir','worktreeGitDir','gitTop')){if($fresh.targetObservation.$field-cne$target.targetObservation.$field){throw 'EXECUTION_TARGET_SAFE_GIT_DRIFT'}}
    }
    [pscustomobject][ordered]@{ status='VERIFIED'; operation=$Operation; repositoryId=$RepositoryId; launched=$true; paths=@($allow | Sort-Object); output=@($output) } | ConvertTo-Json -Depth 5 -Compress -EscapeHandling EscapeNonAscii
    exit 0
} catch {
    Write-Unverified ([string]$_.Exception.Message)
} finally {
    if($null-ne$aiwPublicationScopeLease){Exit-AiwProjectSourceScope $aiwPublicationScopeLease}
}
