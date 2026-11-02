# Private target context observer. It never issues an action grant or writes state.
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Assert-EtFields($Value,[string[]]$Fields,[string]$Reason){
 if($Value-isnot[pscustomobject]){throw $Reason}
 $names=@($Value.PSObject.Properties.Name)
 if($names.Count-ne$Fields.Count-or@($names|Where-Object{$_-cnotin$Fields}).Count){throw $Reason}
}
function Get-EtIdentity([byte[]]$Bytes){$Bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Test-EtWithin([string]$Path,[string]$Root){$Path.Equals($Root,[StringComparison]::OrdinalIgnoreCase)-or$Path.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}
function Assert-EtPath([string]$Path,[string[]]$Denied=@()){
 if(-not[IO.Path]::IsPathFullyQualified($Path)){throw 'EXECUTION_TARGET_ABSOLUTE_PATH_REQUIRED'}
 $full=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
 foreach($x in $Denied){if(Test-EtWithin $full $x){throw 'EXECUTION_TARGET_PROTECTED_PATH'}}
 $cursor=[IO.Path]::GetPathRoot($full)
 foreach($part in $full.Substring($cursor.Length).Split([IO.Path]::DirectorySeparatorChar,[StringSplitOptions]::RemoveEmptyEntries)){
  $cursor=Join-Path $cursor $part
  $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
  if($null-ne$item-and($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'EXECUTION_TARGET_REPARSE'}
 }
 return $full
}
function Get-EtGit([string]$Root,[string[]]$Arguments,[switch]$AllowDetached,[switch]$MultipleLines,[switch]$AllowEmpty){
 $start=[Diagnostics.ProcessStartInfo]::new('git');$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false,$true)
 foreach($x in @('-C',$Root)+$Arguments){$start.ArgumentList.Add($x)}
 $start.Environment['GIT_OPTIONAL_LOCKS']='0';$start.Environment['GIT_TERMINAL_PROMPT']='0'
 $p=[Diagnostics.Process]::new();$p.StartInfo=$start
 try{
  if(-not$p.Start()){throw 'EXECUTION_TARGET_GIT_START'}
  $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
  if(-not$p.WaitForExit(30000)){try{$p.Kill($true)}catch{};throw 'EXECUTION_TARGET_GIT_TIMEOUT'}
  $stdout=$out.GetAwaiter().GetResult().Trim();$null=$err.GetAwaiter().GetResult()
  if($AllowDetached-and$p.ExitCode-eq1){return 'DETACHED'}
  if($p.ExitCode-ne0-or(-not$MultipleLines-and$stdout.Contains([char]10))-or(-not$AllowEmpty-and[string]::IsNullOrWhiteSpace($stdout))){throw 'EXECUTION_TARGET_GIT_METADATA'}
  return $stdout
 }finally{$p.Dispose()}
}
function Resolve-AiwExecutionTargetContext {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ProjectId,[string]$TaskPath='NOT_APPLICABLE',$ExecutionTargetRef=$null,[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@())
 $control=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ProjectRoot))
 $denied=@(foreach($p in @($ForbiddenPaths)+@($ProtectedPaths)){if([IO.Path]::IsPathFullyQualified($p)){[IO.Path]::GetFullPath($p)}else{[IO.Path]::GetFullPath((Join-Path $control $p))}})
 $null=Assert-EtPath $control
 $controlDenied=@(foreach($p in $ForbiddenPaths){if([IO.Path]::IsPathFullyQualified($p)){[IO.Path]::GetFullPath($p)}else{[IO.Path]::GetFullPath((Join-Path $control $p))}})
 $taskId='NOT_APPLICABLE';$refs=@()
 if($TaskPath-cne'NOT_APPLICABLE'){
  $task=if([IO.Path]::IsPathFullyQualified($TaskPath)){$TaskPath}else{Join-Path $control $TaskPath}
  if(-not(Test-EtWithin ([IO.Path]::GetFullPath($task)) (Join-Path $control '.ai-workspace/tasks'))){throw 'EXECUTION_TARGET_TASK_LOCATOR'}
  $null=Assert-EtPath $task $controlDenied
  Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
  $taskText=(Read-AiwControlTransitionTask -ProjectRoot $control -TaskPath $task).Text
  $id=[regex]::Matches($taskText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
  if($id.Count-ne1){throw 'EXECUTION_TARGET_TASK_ID'};$taskId=$id[0].Groups['id'].Value
  $refs=@([regex]::Matches($taskText,'(?m)^(?:- )?Execution target:\s*(?<path>.+)#(?<identity>\d+\|[A-F0-9]{64})\s*$'))
  if($refs.Count-gt1-or([regex]::Matches($taskText,'(?m)^(?:- )?Execution target:').Count-ne$refs.Count)){throw 'EXECUTION_TARGET_TASK_REFERENCE'}
 }
 if($refs.Count-eq0){
  if($null-ne$ExecutionTargetRef){throw 'EXECUTION_TARGET_TASK_REFERENCE_REQUIRED'}
  return [pscustomobject]@{schemaVersion=1;targetKind='SAME_ROOT';controlRoot=$control;executionRoot=$control;executionTargetRef=$null;targetObservation=$null}
 }
 if($null-eq$ExecutionTargetRef){throw 'EXECUTION_TARGET_BINDING_REQUIRED'}
 Assert-EtFields $ExecutionTargetRef @('path','identity') 'EXECUTION_TARGET_REFERENCE'
 $selected=$refs[0];$declared=$selected.Groups['path'].Value.Trim();$expected=$selected.Groups['identity'].Value
 $descPath=if([IO.Path]::IsPathFullyQualified($declared)){$declared}else{Join-Path $control $declared}
 $passedPath=if([IO.Path]::IsPathFullyQualified($ExecutionTargetRef.path)){$ExecutionTargetRef.path}else{Join-Path $control $ExecutionTargetRef.path}
 if([IO.Path]::GetFullPath($descPath)-cne[IO.Path]::GetFullPath($passedPath)-or$ExecutionTargetRef.identity-cne$expected){throw 'EXECUTION_TARGET_REFERENCE_DRIFT'}
 $descPath=Assert-EtPath ([IO.Path]::GetFullPath($descPath)) $controlDenied
 if(-not(Test-EtWithin $descPath (Join-Path $control ('.ai-workspace/runtime/'+$taskId)))){throw 'EXECUTION_TARGET_DESCRIPTOR_SCOPE'}
 $raw=[IO.File]::ReadAllBytes($descPath)
 if((Get-EtIdentity $raw)-cne$expected){throw 'EXECUTION_TARGET_DESCRIPTOR_DRIFT'}
 $text=[Text.UTF8Encoding]::new($false,$true).GetString($raw)
 $d=(ConvertFrom-AiwStrictInputJson $text).Value
 if(-not(Test-Json -Json $text -SchemaFile (Join-Path $PSScriptRoot '../EXECUTION_TARGET_SCHEMA.json') -ErrorAction SilentlyContinue)){throw 'EXECUTION_TARGET_DESCRIPTOR_SCHEMA'}
 if($d.projectId-cne$ProjectId-or$d.taskId-cne$taskId-or$d.controlRoot-cne$control){throw 'EXECUTION_TARGET_CONTROL_BINDING'}
 foreach($reference in @($d.selectionDecisionRef,$d.hostWorktreeRef)){
  if($null-eq$reference){continue}
  $referencePath=[IO.Path]::GetFullPath($reference.path,$control)
  if(-not(Test-EtWithin $referencePath $control)){throw 'EXECUTION_TARGET_EVIDENCE_SCOPE'}
  $null=Assert-EtPath $referencePath $controlDenied
  if((Get-EtIdentity ([IO.File]::ReadAllBytes($referencePath)))-cne$reference.identity){throw 'EXECUTION_TARGET_EVIDENCE_DRIFT'}
 }
 $target=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($d.targetRoot))
 if($target-cne$d.targetRoot-or$target-ceq$control){throw 'EXECUTION_TARGET_CANONICAL_ROOT'}
 foreach($scope in @($ForbiddenPaths)+@($ProtectedPaths)){
  if(-not[IO.Path]::IsPathFullyQualified($scope)){$denied+=[IO.Path]::GetFullPath((Join-Path $target $scope))}
  elseif(Test-EtWithin ([IO.Path]::GetFullPath($scope)) $control){$denied+=[IO.Path]::GetFullPath((Join-Path $target ([IO.Path]::GetRelativePath($control,$scope))))}
 }
 $null=Assert-EtPath $target $denied
 foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_CONFIG','GIT_CONFIG_PARAMETERS','GIT_CONFIG_COUNT')){
  if(-not[string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))){throw 'EXECUTION_TARGET_GIT_OVERRIDE'}
 }
 $common=Get-EtGit $control @('rev-parse','--path-format=absolute','--git-common-dir')
 $common=Assert-EtPath $common $denied
 $originalTop=Get-EtGit $control @('rev-parse','--show-toplevel')
 $originalTop=Assert-EtPath $originalTop $denied
 foreach($scope in @($ForbiddenPaths)+@($ProtectedPaths)){if([IO.Path]::IsPathFullyQualified($scope)-and(Test-EtWithin ([IO.Path]::GetFullPath($scope)) $originalTop)){$denied+=[IO.Path]::GetFullPath((Join-Path $target ([IO.Path]::GetRelativePath($originalTop,$scope))))}}
 $null=Assert-EtPath $target $denied
 $targetCommon=Get-EtGit $target @('rev-parse','--path-format=absolute','--git-common-dir')
 $targetCommon=Assert-EtPath $targetCommon $denied
 $worktree=Get-EtGit $target @('rev-parse','--absolute-git-dir')
 $worktree=Assert-EtPath $worktree $denied
 $top=Get-EtGit $target @('rev-parse','--show-toplevel')
 $top=Assert-EtPath $top $denied
 foreach($p in @($common,$targetCommon,$worktree,$top)){$null=Assert-EtPath $p $denied}
 if($common-cne$targetCommon-or$common-cne$d.gitBinding.commonGitDir-or$worktree-cne$d.gitBinding.worktreeGitDir-or$top-cne$target-or$top-cne$d.gitBinding.gitTop-or$worktree-ceq$common){throw 'EXECUTION_TARGET_GIT_RELATION'}
 $gitFile=Join-Path $target '.git';$null=Assert-EtPath $gitFile $denied
 if(-not(Test-Path -LiteralPath $gitFile -PathType Leaf)){throw 'EXECUTION_TARGET_WORKTREE_GITFILE'}
 $gitText=[IO.File]::ReadAllText($gitFile).Trim()
 if($gitText-cnotmatch'^gitdir: (.+)$'){throw 'EXECUTION_TARGET_WORKTREE_GITFILE'}
 $actualDir=[IO.Path]::GetFullPath($Matches[1],$target)
 if($actualDir-cne$worktree){throw 'EXECUTION_TARGET_WORKTREE_GITFILE'}
 $back=Join-Path $worktree 'gitdir';$null=Assert-EtPath $back $denied
 if([IO.Path]::GetFullPath([IO.File]::ReadAllText($back).Trim(),$worktree)-cne$gitFile){throw 'EXECUTION_TARGET_WORKTREE_BACKLINK'}
 $branch=Get-EtGit $target @('symbolic-ref','--quiet','--short','HEAD') -AllowDetached
 $head=Get-EtGit $target @('rev-parse','--verify','HEAD')
 if($head-cnotmatch'^[a-fA-F0-9]{40}([a-fA-F0-9]{24})?$'-or(Get-EtGit $target @('cat-file','-t',$d.gitBinding.baselineCommit))-cne'commit'){throw 'EXECUTION_TARGET_BASELINE'}
 if($d.gitBinding.branch-cne'DETACHED'-and$d.gitBinding.branch-cmatch'[\x00-\x20~^:?*\[\\]'){throw 'EXECUTION_TARGET_BRANCH_FORMAT'}
 return [pscustomobject]@{schemaVersion=1;targetKind='GIT_WORKTREE';controlRoot=$control;executionRoot=$target;executionTargetRef=[pscustomobject]@{path=$descPath;identity=$expected};targetObservation=[pscustomobject]@{schemaVersion=1;descriptorIdentity=$expected;commonGitDir=$common;worktreeGitDir=$worktree;gitTop=$top;branch=$branch;head=$head;observedUtc=[DateTime]::UtcNow.ToString('o');overridesAbsent=$true}}
}
Export-ModuleMember -Function Resolve-AiwExecutionTargetContext

# Action/evidence consumers share this observer and path boundary. The descriptor
# stays immutable; action state advances only through an actual finalized result.
function Get-AiwExecutionTargetState($Context){
 if($Context.targetKind-cne'GIT_WORKTREE'){throw 'EXECUTION_TARGET_ISOLATION_REQUIRED'}
 return [pscustomobject]@{branch=[string]$Context.targetObservation.branch;head=([string]$Context.targetObservation.head).ToUpperInvariant()}
}
function Assert-AiwExecutionTargetState($Context,$ExpectedState,[string]$Action='NONE',[switch]$AllowCommitPostimage,[string[]]$ExactPaths=@()){
 Assert-EtFields $ExpectedState @('branch','head') 'EXECUTION_TARGET_STATE_FIELDS'
 if($ExpectedState.branch-isnot[string]-or[string]::IsNullOrWhiteSpace($ExpectedState.branch)-or$ExpectedState.head-isnot[string]-or$ExpectedState.head-cnotmatch'^(?:[A-F0-9]{40}|[A-F0-9]{64})$'){throw 'EXECUTION_TARGET_STATE_FORMAT'}
 $actual=Get-AiwExecutionTargetState $Context
 if($actual.branch-cne$ExpectedState.branch){throw 'EXECUTION_TARGET_BRANCH_DRIFT'}
 if($actual.head-ceq$ExpectedState.head){return $actual}
 if(-not$AllowCommitPostimage-or$Action-cne'GIT_COMMIT'-or$actual.branch-ceq'DETACHED'){throw 'EXECUTION_TARGET_HEAD_DRIFT'}
 $root=$Context.executionRoot
 $parents=(Get-EtGit $root @('show','-s','--format=%P','HEAD')).Split(' ')
 if($parents.Count-ne1-or$parents[0].ToUpperInvariant()-cne$ExpectedState.head){throw 'EXECUTION_TARGET_COMMIT_PARENT'}
 $changed=Get-EtGit $root @('-c','core.quotepath=false','diff-tree','--no-commit-id','--name-only','--no-renames','-r','HEAD') -MultipleLines
 $paths=@($changed.Split([char]10)|ForEach-Object{$_.TrimEnd([char]13)}|Sort-Object -CaseSensitive)
 if(($paths-join"`n")-cne(@($ExactPaths|Sort-Object -CaseSensitive)-join"`n")){throw 'EXECUTION_TARGET_COMMIT_PATHSET'}
 if((Get-EtGit $root @('diff','--cached','--name-only') -AllowEmpty)-cne''){throw 'EXECUTION_TARGET_COMMIT_INDEX'}
 # The committed tree must be the candidate that the action is finalizing.
 if((Get-EtGit $root (@('diff','--no-ext-diff','--no-textconv','--name-only','HEAD','--')+@($ExactPaths|ForEach-Object{':(top,literal)'+$_})) -AllowEmpty)-cne''){throw 'EXECUTION_TARGET_COMMIT_TREE'}
 return $actual
}
function Get-AiwExecutionTargetDeniedPaths($Context,[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@()){
 $control=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Context.controlRoot));$target=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Context.executionRoot))
 $top=if($Context.targetKind-ceq'GIT_WORKTREE'){Get-EtGit $control @('rev-parse','--show-toplevel')}else{$control}
 $top=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($top))
 $bounds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($path in @($ForbiddenPaths)+@($ProtectedPaths)){
  if([IO.Path]::IsPathFullyQualified($path)){
   $full=[IO.Path]::GetFullPath($path);$null=$bounds.Add($full)
   foreach($base in @($control,$top)|Select-Object -Unique){if(Test-EtWithin $full $base){$null=$bounds.Add([IO.Path]::GetFullPath((Join-Path $target ([IO.Path]::GetRelativePath($base,$full)))))} }
  }else{foreach($base in @($control,$target)){$null=$bounds.Add([IO.Path]::GetFullPath((Join-Path $base $path)))}}
 }
 return @($bounds)
}
function Resolve-AiwExecutionTargetCandidatePath($Context,[string]$Relative,[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@()){
 if([string]::IsNullOrWhiteSpace($Relative)-or[IO.Path]::IsPathRooted($Relative)-or$Relative.Contains('\')-or$Relative-match'[:*?\x00-\x1f]'-or$Relative-cne$Relative.Normalize([Text.NormalizationForm]::FormC)){throw 'EXECUTION_TARGET_CANDIDATE_PATH'}
 foreach($part in $Relative.Split('/')){if($part-in@('','.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or$part-match'(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'EXECUTION_TARGET_CANDIDATE_PATH'}}
 if($Context.targetKind-ceq'GIT_WORKTREE'-and$Relative-match'(?i)^(\.ai-workspace|\.git)(/|$)'){throw 'EXECUTION_TARGET_CONTROL_OBJECT_DENIED'}
 $full=[IO.Path]::GetFullPath((Join-Path $Context.executionRoot $Relative))
 $denied=@(Get-AiwExecutionTargetDeniedPaths $Context $ForbiddenPaths $ProtectedPaths)
 return Assert-EtPath $full $denied
}
function Resolve-AiwPackageExecutionTarget([string]$ControlRoot,$Package,[string]$TaskPath,[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@(),$ExpectedState=$null,[switch]$AllowCommitPostimage){
 if($Package.schemaVersion-ne4-or$Package.repositoryId-cne'PROJECT'-or$Package.controlRoot-isnot[string]-or$Package.controlRoot-cne[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ControlRoot))){throw 'EXECUTION_TARGET_PACKAGE_BINDING'}
 if(@($Package.actions).Count-eq0-or@($Package.actions|Where-Object{$_-cnotin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH')}).Count){throw 'EXECUTION_TARGET_PACKAGE_ACTION'}
 $cfg=(Read-AiwStrictInputJson (Join-Path $ControlRoot '.ai-workspace/project.json')).Value
 if($cfg.controlPlaneLayout-cne'repo-local'){throw 'EXECUTION_TARGET_MAINTENANCE_PROJECT_DENIED'}
 $allForbidden=@($ForbiddenPaths)+@($cfg.routineExcludedPaths)
 $context=Resolve-AiwExecutionTargetContext -ProjectRoot $ControlRoot -ProjectId $cfg.id -TaskPath $TaskPath -ExecutionTargetRef $Package.executionTargetRef -ForbiddenPaths $allForbidden -ProtectedPaths $ProtectedPaths
 if($context.targetKind-cne'GIT_WORKTREE'){throw 'EXECUTION_TARGET_PACKAGE_REQUIRES_WORKTREE'}
 if($Package.executionTargetRef.path-cne$context.executionTargetRef.path){throw 'EXECUTION_TARGET_PACKAGE_CANONICAL_REFERENCE'}
 if($null-eq$ExpectedState){$ExpectedState=$Package.expectedTargetState}
 $action=if(@($Package.actions).Count-eq1){$Package.actions[0]}else{'NONE'}
 foreach($relative in $Package.exactPaths){$null=Resolve-AiwExecutionTargetCandidatePath $context $relative $allForbidden $ProtectedPaths}
 $null=Assert-AiwExecutionTargetState $context $ExpectedState $action -AllowCommitPostimage:$AllowCommitPostimage -ExactPaths @($Package.exactPaths)
 return $context
}
Export-ModuleMember -Function Get-AiwExecutionTargetState,Assert-AiwExecutionTargetState,Get-AiwExecutionTargetDeniedPaths,Resolve-AiwExecutionTargetCandidatePath,Resolve-AiwPackageExecutionTarget
