[CmdletBinding()]
param([ValidateSet('All','Schema1ControlPlane','NativeIO','JsonConsumers')][string]$Case='All')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'IntegrationFixture.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
$integrationContext=$null
try {
 $integrationContext=New-IntegrationContext (Join-Path $PSScriptRoot '..') 'authorization'
 foreach($key in $integrationContext.Keys){if($key-ceq'script:testJunctions'){$script:testJunctions=$integrationContext[$key]}else{Set-Variable -Name $key -Value $integrationContext[$key]}}
function Get-IntegrationNativeIoLines([string]$Text) {
 $reader=[IO.StringReader]::new($Text);$lines=[Collections.Generic.List[string]]::new()
 try{while($null-ne($line=$reader.ReadLine())){$lines.Add($line)}}finally{$reader.Dispose()}
 return ,$lines.ToArray()
}
function Assert-IntegrationNativeIoResult($Value,$Context,[string]$Operation,[string]$Path,[string[]]$Expected,[string]$Label) {
 $fields=@('status','operation','repositoryId','launched','paths','output')
 Assert-True ($Value-is[pscustomobject]-and@($Value.PSObject.Properties).Count-eq$fields.Count-and@($fields|Where-Object{$_-cnotin$Value.PSObject.Properties.Name}).Count-eq0-and$Value.status-ceq'VERIFIED'-and$Value.operation-ceq$Operation-and$Value.repositoryId-ceq$Context.id-and$Value.launched-eq$true-and$Value.paths-is[Array]-and$Value.paths.Count-eq1-and$Value.paths[0]-ceq$Path-and$Value.output-is[Array]-and$Value.output.Count-eq$Expected.Count) ($Label+'-complete-fields-and-array-shape')
 for($i=0;$i-lt$Expected.Count;$i++){if(-not[string]::Equals($Value.output[$i],$Expected[$i],[StringComparison]::Ordinal)){throw ('NATIVE_IO_ORDINAL_LINE|'+$Label+'|'+$i)}}
 Assert-True $true ($Label+'-every-line-ordinal-equal')
}
function Test-IntegrationSafeGitNativeIo {
 $repo=Join-Path $temp 'native-io-repo-local';New-GitRepo $repo
 $repoConfig=$projectStarterText.Replace('{{PROJECT_ID_JSON}}','"native-io-fixture"').Replace('{{DISPLAY_NAME_JSON}}','"原生 IO 😀"').Replace('{{FRAMEWORK_VERSION_JSON}}','"2.0.0"')|ConvertFrom-Json
 $repoConfig.routineExcludedPaths=@('private/secret.txt');$repoConfigPath=Join-Path $repo '.ai-workspace/project.json'
 Write-Utf8 $repoConfigPath ($repoConfig|ConvertTo-Json -Depth 100)
 $contexts=@(@{name='CONTROL';id='CONTROL';project=$control;root=$control;path=$controlObject;config=$configIdentity;tool=(Join-Path $fixedRuntime 'scripts/invoke-framework-maintenance-safe-git.ps1');local=$false},@{name='TARGET';id='ai-workspace-framework';project=$control;root=$target;path=$targetObject;config=$configIdentity;tool=(Join-Path $fixedRuntime 'scripts/invoke-framework-maintenance-safe-git.ps1');local=$false},@{name='PROJECT';id='PROJECT';project=$repo;root=$repo;path='src/public.txt';config=(Get-Identity $repoConfigPath);tool=(Join-Path $installedFramework 'scripts/invoke-protected-safe-git.ps1');local=$true})
 $git=(Get-Command git -CommandType Application -ErrorAction Stop).Source
 $observationRoot=Join-Path $env:AIW_TEST_RAW_DIRECTORY 'native-io-observations';$null=[IO.Directory]::CreateDirectory($observationRoot)
 function Invoke-NativeIoCheck($ctx,[string]$operation,[string]$path,[string]$label) {
  $empty='.git/info/ai-workspace-empty-excludes-v1';$spec=':(top,literal)'+$path
  $base=@('-C',$ctx.root);if($ctx.local){$base+=@('-c',('core.excludesFile='+$empty))}
  $argv=switch($operation){'STATUS'{@($base+@('-c','status.renames=false','status','--no-renames','--porcelain=v1','--untracked-files=all','--',$spec,':(top,exclude,literal)private/secret.txt'))};'DIFF'{@($base+@('-c','diff.renames=false','diff','--no-renames','--no-ext-diff','--no-textconv','--',$spec,':(top,exclude,literal)private/secret.txt'))};'INDEX'{@($base+@('-c','diff.renames=false','diff','--cached','--no-renames','--name-status','--',$spec,':(top,exclude,literal)private/secret.txt'))}}
  # Independent real Git oracle; the original harness preserves native bytes.
  $oracle=Invoke-AiwTestProcess $git $argv -WorkingDirectory $ctx.root -GroupId ('native-io-oracle-'+$label)
  Assert-True (@($oracle).Count-eq1-and$oracle.Code-eq0-and$oracle.StderrText-ceq'') ($label+'-real-git-oracle-single-result') | Write-Host
  $expected=Get-IntegrationNativeIoLines $oracle.StdoutText
  $args=@('-ProjectRoot',$ctx.project,'-Operation',$operation,'-AllowPath',$path,'-ExpectedProjectConfigIdentity',$ctx.config,'-RepositoryId',$ctx.id)
  $before=@{out=[Console]::Out;err=[Console]::Error;inputCP=[Console]::InputEncoding.CodePage;outputCP=[Console]::OutputEncoding.CodePage;redirected=[Console]::IsOutputRedirected}
  $inprocessArguments=@{ProjectRoot=$ctx.project;Operation=$operation;AllowPath=@($path);ExpectedProjectConfigIdentity=$ctx.config;RepositoryId=$ctx.id}
  $inprocess=@(& $ctx.tool @inprocessArguments);$inprocessExit=$LASTEXITCODE
  Assert-True ($inprocessExit-eq0-and$inprocess.Count-eq1-and$inprocess[0]-is[string]-and[object]::ReferenceEquals($before.out,[Console]::Out)-and[object]::ReferenceEquals($before.err,[Console]::Error)-and$before.inputCP-eq[Console]::InputEncoding.CodePage-and$before.outputCP-eq[Console]::OutputEncoding.CodePage) ($label+'-inprocess-single-json-and-caller-preserved') | Write-Host
  $value=$inprocess[0]|ConvertFrom-Json -Depth 100
  Assert-IntegrationNativeIoResult $value $ctx $operation $path $expected ($label+'-inprocess') | Write-Host
  $run=Invoke-Ps $ctx.tool $args
  Assert-True ($run.Code-eq0-and$run.Stderr-ceq''-and$run.Output.Count-eq1) ($label+'-native-success-single-json') | Write-Host
  $raw=[IO.File]::ReadAllBytes($run.Record.stdout.path)
  Assert-True (@($raw|Where-Object{$_-gt127}).Count-eq0) ($label+'-native-ascii-json-transport') | Write-Host
  $nativeValue=$run.Stdout|ConvertFrom-Json -Depth 100
  Assert-IntegrationNativeIoResult $nativeValue $ctx $operation $path $expected ($label+'-native') | Write-Host
  $metadataArgs=@('-C',$ctx.root,'-c','core.quotepath=false','-c',('core.excludesFile='+$empty),'-c','diff.renames=false')
  if($operation-ceq'STATUS'){$metadataArgs+=@('status','--no-renames','--porcelain=v1','-z','--untracked-files=all','--',$spec)}else{$metadataArgs+=@('diff','--no-renames','--no-ext-diff','--no-textconv','--name-only','-z');if($operation-ceq'INDEX'){$metadataArgs+='--cached'};$metadataArgs+=@('--',$spec)}
  $metadata=Invoke-AiwTestProcess $git $metadataArgs -WorkingDirectory $ctx.root -GroupId ('native-io-nul-'+$label)
  Assert-True ($metadata.Code-eq0-and$metadata.StderrText-ceq''-and$metadata.StdoutText.EndsWith([string][char]0)) ($label+'-real-nul-metadata-retained') | Write-Host
  Write-Utf8 (Join-Path $observationRoot ($label+'.json')) (@{kind='ACTUAL_THREE_FACE_NATIVE_IO';label=$label;operation=$operation;knownPath=$path;git=$oracle.Record;metadata=$metadata.Record;inprocessJson=$inprocess[0];inprocessEncodingBefore=$before|Select-Object inputCP,outputCP,redirected;native=$run.Record;expectedLines=$expected;actualLines=$nativeValue.output;semantic='Every field and line compared Ordinal; original bytes retained, no transcoding or all-group claim'}|ConvertTo-Json -Depth 100 -EscapeHandling EscapeNonAscii)
  return [pscustomobject]@{run=$run;oracle=$oracle;value=$nativeValue;expected=$expected}
 }
 # Both baseline deletions and additions contain meaningful non-ASCII bytes.
 foreach($ctx in $contexts){
  foreach($ending in @('LF','NO_LF')){
   $before="# 删除 中文 😀 `"quote`" C:\before`n`n旧正文 ? 保留问号`n";$after="# 新增 中文 😀 `"quote`" C:\after`n`n新正文 ? 保留问号`n"
   if($ending-ceq'NO_LF'){$before=$before.TrimEnd([char]10);$after=$after.TrimEnd([char]10)}
   $full=Join-Path $ctx.root $ctx.path;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $full))
   [IO.File]::WriteAllText($full,$before,$utf8);& git -C $ctx.root add -- $ctx.path;if($LASTEXITCODE-ne0){throw 'NATIVE_IO_BASELINE_ADD'}
   & git -C $ctx.root commit -q -m ('native IO baseline '+$ctx.name+' '+$ending) -- $ctx.path;if($LASTEXITCODE-ne0){throw 'NATIVE_IO_BASELINE_COMMIT'}
   [IO.File]::WriteAllText($full,$after,$utf8)
   $checked=Invoke-NativeIoCheck $ctx DIFF $ctx.path ($ctx.name+'-DIFF-'+$ending)
   Assert-True (@($checked).Count-eq1-and$checked-is[pscustomobject]) ($ctx.name+'-'+$ending+'-single-observation-result')
   foreach($line in @('# 删除 中文 😀 "quote" C:\before','旧正文 ? 保留问号')){Assert-True ($checked.expected-ccontains('-'+$line)) ($ctx.name+'-'+$ending+'-full-deletion-'+$line.Length)}
   foreach($line in @('# 新增 中文 😀 "quote" C:\after','新正文 ? 保留问号')){Assert-True ($checked.expected-ccontains('+'+$line)) ($ctx.name+'-'+$ending+'-full-addition-'+$line.Length)}
   Assert-True (($checked.expected-ccontains'\ No newline at end of file')-eq($ending-ceq'NO_LF')) ($ctx.name+'-'+$ending+'-terminal-LF-distinguished')
  }
 }
 foreach($ctx in $contexts){
  $path='docs/名称-😀.txt';$full=Join-Path $ctx.root $path;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $full));[IO.File]::WriteAllText($full,"状态 中文 😀`n",$utf8)
  $null=Invoke-NativeIoCheck $ctx STATUS $path ($ctx.name+'-STATUS-Unicode')
  & git -C $ctx.root add -- $path;if($LASTEXITCODE-ne0){throw 'NATIVE_IO_INDEX_STAGE'}
  $null=Invoke-NativeIoCheck $ctx INDEX $path ($ctx.name+'-INDEX-Unicode')
  # Force real Git textual diff to contain invalid UTF-8; no encoding fallback.
  $badPath='docs/non-utf8.txt';$bad=Join-Path $ctx.root $badPath;[IO.File]::WriteAllText($bad,"before text`n",$utf8);& git -C $ctx.root add -- $badPath;& git -C $ctx.root commit -q -m 'native IO invalid UTF8 baseline' -- $badPath
  if($LASTEXITCODE-ne0){throw 'NATIVE_IO_INVALID_BASELINE'};[IO.File]::WriteAllBytes($bad,[byte[]]@(255,97,10))
  $rejected=Invoke-Ps $ctx.tool @('-ProjectRoot',$ctx.project,'-Operation','DIFF','-AllowPath',$badPath,'-ExpectedProjectConfigIdentity',$ctx.config,'-RepositoryId',$ctx.id)
  $failure=$rejected.Stdout|ConvertFrom-Json -Depth 100
  # A real Git error remains UNVERIFIED even though no stdout is produced.
  & git -C $ctx.root config diff.algorithm aiw-invalid-algorithm
  if($LASTEXITCODE-ne0){throw 'NATIVE_IO_ERROR_FIXTURE_CONFIG'}
  try{
   $gitError=Invoke-AiwTestProcess $git @('-C',$ctx.root,'diff','--name-only','-z','--',$badPath) -WorkingDirectory $ctx.root -GroupId ('native-io-real-git-error-'+$ctx.name)
   Assert-True ($gitError.Code-ne0-and$gitError.StderrText.Length-gt0) ($ctx.name+'-real-git-error-observed')
   $gitRejected=Invoke-Ps $ctx.tool @('-ProjectRoot',$ctx.project,'-Operation','DIFF','-AllowPath',$badPath,'-ExpectedProjectConfigIdentity',$ctx.config,'-RepositoryId',$ctx.id)
   $gitFailure=$gitRejected.Stdout|ConvertFrom-Json -Depth 100
   $failureFields=if($ctx.local){@('status','operation','repositoryId','reason','launched')}else{@('status','operation','repositoryId','launched','reason','paths','output')}
   $failureShape=@($gitFailure.PSObject.Properties).Count-eq$failureFields.Count-and@($failureFields|Where-Object{$_-cnotin$gitFailure.PSObject.Properties.Name}).Count-eq0
   $failurePayload=if($ctx.local){$null-eq$gitFailure.PSObject.Properties['output']}else{$gitFailure.paths-is[Array]-and$gitFailure.paths.Count-eq1-and$gitFailure.paths[0]-ceq$badPath-and$gitFailure.output-is[Array]-and$gitFailure.output.Count-eq0}
   Assert-True ($gitRejected.Code-eq$(if($ctx.local){3}else{2})-and$gitFailure.status-ceq'UNVERIFIED'-and$gitFailure.operation-ceq'DIFF'-and$gitFailure.repositoryId-ceq$ctx.id-and$gitFailure.reason-ceq'GIT_PATH_METADATA_FAILED'-and-not$gitFailure.launched-and$failureShape-and$failurePayload) ($ctx.name+'-native-git-error-original-exact-fields-not-verified-empty')
  }finally{& git -C $ctx.root config --unset diff.algorithm;if($LASTEXITCODE-ne0){throw 'NATIVE_IO_ERROR_FIXTURE_RESTORE'}}
  Assert-True ($rejected.Code-eq$(if($ctx.local){3}else{2})-and$failure.status-ceq'UNVERIFIED'-and$failure.reason-ceq'GIT_STDOUT_UTF8'-and$failure.launched-eq$false) ($ctx.name+'-invalid-utf8-body-real-unverified')
 }
}
function Test-IntegrationSchema1ControlPlane {
 $baseline=Invoke-Ps $checker $repoLocalSchema1Args $repoLocal
 Assert-True ($baseline.Code-eq0) 'authorization-schema1-reparse-valid-baseline-before'
 $backingBefore=Get-PhysicalFixtureTree (Join-Path $repoLocal '.ai-workspace')
    $reparseRepoLocal = Join-Path $temp 'repo-local-reparse-fixture'
    New-GitRepo $reparseRepoLocal
    New-TestJunction (Join-Path $reparseRepoLocal '.ai-workspace') (Join-Path $repoLocal '.ai-workspace')
    try { $reparseSchema1Control = Invoke-Ps $checker $repoLocalSchema1Args $reparseRepoLocal }
    finally { Remove-TestJunction (Join-Path $reparseRepoLocal '.ai-workspace') }
    Assert-True ($reparseSchema1Control.Code -ne 0 -and $reparseSchema1Control.Text.Contains('PROJECT_CONTROL_PLANE_REPARSE')) 'authorization-schema1-rejects-reparse-control-plane'
 Assert-True ((Get-PhysicalFixtureTree (Join-Path $repoLocal '.ai-workspace'))-ceq$backingBefore) 'authorization-schema1-reparse-backing-unchanged'
 $taskRelative='.ai-workspace/tasks/active/FIXTURE-OWNER-001.md'
 $taskFull=Join-Path $repoLocal $taskRelative
 $taskBytes=[IO.File]::ReadAllBytes($taskFull)
 $taskIdentity=Get-Identity $taskFull
 $taskFailureArgs=@($repoLocalSchema1Args)+@('-TaskPath',$taskRelative,'-ExpectedTaskIdentity',$taskIdentity)
 $missingTaskPath=$taskFull+'.missing'
 [IO.File]::Move($taskFull,$missingTaskPath)
 try { $missingTask=Invoke-Ps $checker $taskFailureArgs $repoLocal }
 finally { [IO.File]::Move($missingTaskPath,$taskFull) }
 Assert-True ($missingTask.Code-eq2-and$missingTask.Text.Trim()-ceq'FAIL|TASK_OBJECT_MISSING') 'authorization-schema1-missing-task-preserves-original-refusal'
 try {
     [IO.File]::WriteAllBytes($taskFull,([byte[]]($taskBytes+@(10))))
     $driftedTask=Invoke-Ps $checker $taskFailureArgs $repoLocal
 } finally { [IO.File]::WriteAllBytes($taskFull,$taskBytes) }
 Assert-True ($driftedTask.Code-eq2-and$driftedTask.Text.Trim()-ceq'FAIL|TASK_OBJECT_DRIFT') 'authorization-schema1-task-drift-preserves-original-refusal'
 Assert-True ((Get-Identity $taskFull)-ceq$taskIdentity) 'authorization-schema1-task-failure-fixtures-restored'
 $restored=Invoke-Ps $checker $repoLocalSchema1Args $repoLocal
 Assert-True ($restored.Code-eq0) 'authorization-schema1-reparse-valid-baseline-after'
}
 $maintenanceFixture=New-IntegrationMaintenanceFixture -Register
 foreach($key in $maintenanceFixture.Keys){Set-Variable -Name $key -Value $maintenanceFixture[$key]}
 if($Case-cin@('All','NativeIO')){Test-IntegrationSafeGitNativeIo}
 if($Case-ceq'NativeIO'){Write-Output 'EVIDENCE_CEILING|PARTIAL|authorization-native-io';return}
 $versionChecker=Join-Path $installedFramework 'scripts/check-authorization.ps1'
 if($Case-ceq'Schema1ControlPlane'){
    $checker = $versionChecker
    $safeGit = Join-Path $installedFramework 'scripts\invoke-protected-safe-git.ps1'
    $repoLocal = Join-Path $temp 'repo-local-fixture'
    New-GitRepo $repoLocal
    $repoLocalConfigPath = Join-Path $repoLocal '.ai-workspace\project.json'
    $repoLocalConfig = [ordered]@{schemaVersion=6;id='repo-local-fixture';displayName='Repo Local Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('private/secret.txt');frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false;sources=@()}};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=2;locator='.ai-workspace/process-policy.json'}}
    Write-CurrentFixtureObject PROJECT_CONFIG $repoLocalConfigPath $repoLocalConfig
    Write-Utf8 (Join-Path $repoLocal 'src\public.txt') 'repo local public'
    Write-Utf8 (Join-Path $repoLocal 'private\secret.txt') 'repo local private'
    $repoLocalIdentity = Get-Identity $repoLocalConfigPath
    $repoLocalSchema1Package = Join-Path $repoLocal '.ai-workspace\schema1-auth.json'
    $repoLocalObject = 'src/public.txt'
    $repoLocalObjectIdentity = Get-Identity (Join-Path $repoLocal $repoLocalObject)
    New-AuthorizationPackage $repoLocalSchema1Package 1 '' $repoLocalIdentity @('SOURCE_WRITE') $repoLocalObject $repoLocalObjectIdentity -DomainOwner
    $repoLocalSchema1Auth = Invoke-Ps $checker @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity)) $repoLocal
    $repoLocalStatus = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    $repoLocalExcluded = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    Assert-True ($repoLocalStatus.Code -eq 0 -and $repoLocalStatus.Text.Contains('src/public.txt') -and $repoLocalStatus.Text.Contains('"repositoryId":"PROJECT"')) 'safe-git-repo-local-default-compatible'
    Assert-True ($repoLocalExcluded.Code -eq 0 -and -not ((@($repoLocalExcluded.Output)[-1] | ConvertFrom-Json).output -join "`n").Contains('private/secret.txt')) 'safe-git-repo-local-exclusion-compatible'
    Assert-True ($repoLocalSchema1Auth.Code -eq 0) 'authorization-schema1-repo-local-current-project-compatible'
    $repoLocalSchema1Args = @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
Test-IntegrationSchema1ControlPlane
Write-Output 'EVIDENCE_CEILING|PARTIAL|schema1-control-plane'
}else{
    $versionChecker = Join-Path $installedFramework 'scripts\check-authorization.ps1'
    $controllerIdentity = Get-Identity (Join-Path $controlPlane 'controller.json')
    Assert-True ($controllerIdentity -match '^\d+\|[A-F0-9]{64}$') 'fixture-controller-identity'
    $controlPackage = Join-Path $controlPlane 'control-auth.json'
    $targetPackage = Join-Path $controlPlane 'target-auth.json'
    $badTargetActionPackage = Join-Path $controlPlane 'bad-target-action-auth.json'
    $badControlActionPackage = Join-Path $controlPlane 'bad-control-action-auth.json'
    New-AuthorizationPackage $controlPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject))
    New-AuthorizationPackage $targetPackage 2 'ai-workspace-framework' $configIdentity @('SOURCE_WRITE','TEST_RUN') $targetObject (Get-Identity (Join-Path $target $targetObject)) -ContinuationPlan @('SOURCE_WRITE','TEST_RUN')
    New-AuthorizationPackage $badTargetActionPackage 2 'ai-workspace-framework' $configIdentity @('CONTROL_WRITE') $targetObject (Get-Identity (Join-Path $target $targetObject))
    New-AuthorizationPackage $badControlActionPackage 2 'CONTROL' $configIdentity @('SOURCE_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject))
    $directSchema2 = Invoke-Ps $versionChecker @('-PackagePath',$controlPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity,'-TaskPath','.ai-workspace/tasks/active/FIXTURE-001.md','-ExpectedTaskIdentity',(Get-Identity (Join-Path $control '.ai-workspace/tasks/active/FIXTURE-001.md'))) $control
    Assert-True ($directSchema2.Code-ne0-and$directSchema2.Text.Contains('ROOT_REPOSITORY_BINDING_REQUIRED')) 'authorization-schema2-requires-root-repository-adapter'

    $controlAuth = Invoke-Ps $checker @('-PackagePath',$controlPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    $targetAuth = Invoke-Ps $checker @('-PackagePath',$targetPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    if($controlAuth.Code-ne0-or$targetAuth.Code-ne0){Write-Output ('DIAG|authorization-root-adapter|control='+$controlAuth.Text+'|target='+$targetAuth.Text)}
    Assert-True ($controlAuth.Code -eq 0 -and $targetAuth.Code -eq 0) 'authorization-schema2-control-and-target-pass'
    $duplicateAuthPath=Join-Path $controlPlane 'duplicate-auth.json';$duplicateAuthRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $targetPackage;$duplicateAuthRaw=[regex]::Replace($duplicateAuthRaw,'"actions"\s*:\s*\[','"actions": ["SOURCE_WRITE"], "\u0061ctions": [',1);Write-Utf8 $duplicateAuthPath $duplicateAuthRaw
    $duplicateAuthRun=Invoke-Ps $checker @('-PackagePath',$duplicateAuthPath,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($duplicateAuthRun.Code-ne0-and$duplicateAuthRun.Text.Contains('PACKAGE_DUPLICATE_MEMBER|actions')) 'authorization-recursive-json-rejects-unicode-top-level-duplicate'

    $maintenanceProcessResolver=Join-Path $fixedRuntime 'scripts\resolve-framework-maintenance-process-requirements.ps1';$maintenanceProcessTask=Join-Path $control '.ai-workspace\tasks\active\FIXTURE-001.md';$maintenanceProcessInputPath=Join-Path $controlPlane 'maintenance-target-process.json'
    $maintenanceProcessIntent=(New-CurrentFixtureIntent ([ordered]@{schemaVersion=1;objective='Modify one bounded Framework target object';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('implementation');pathHints=@($targetObject);capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'}))
    $maintenanceProcessInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$control;frameworkRoot=$fixedRuntime;taskPath=$maintenanceProcessTask;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity=(Get-Identity $maintenanceProcessTask);observedActor='controller-fixture';capabilities=@();exactPaths=@($targetObject);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$targetPackage;expectedAuthorizationIdentity=(Get-Identity $targetPackage);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$maintenanceProcessIntent;evaluationOnly=$false}
    Write-Utf8 $maintenanceProcessInputPath ($maintenanceProcessInput|ConvertTo-Json -Depth 30);$maintenanceProcessRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceProcessInputPath,'-AsJson');$maintenanceProcessResult=if($maintenanceProcessRun.Code-eq0){$maintenanceProcessRun.Output[-1]|ConvertFrom-Json}else{$null};$maintenanceProcessValue=if($null-ne$maintenanceProcessResult){$maintenanceProcessResult.compactReceipt}else{$null}
    $expectedTargetGitTop=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($target))
    if($maintenanceProcessRun.Code-ne0-or[string]$maintenanceProcessValue.binding.repositoryGitTop-cne$expectedTargetGitTop){Write-Output ('DIAG|process-maintenance-target|code='+$maintenanceProcessRun.Code+'|expected='+$expectedTargetGitTop+'|output='+$maintenanceProcessRun.Text)}
    Assert-True ($maintenanceProcessRun.Code-eq0-and[string]$maintenanceProcessValue.binding.projectRoot-ceq([IO.Path]::GetFullPath($control))-and[string]$maintenanceProcessValue.binding.repositoryGitTop-ceq$expectedTargetGitTop) 'process-maintenance-target-authority-context-uses-target-git-top'

    Assert-True ($maintenanceProcessRun.Stderr-ceq''-and$maintenanceProcessRun.Stdout-notmatch'[^\x00-\x7f]') 'maintenance-process-native-full-discover-ascii-json'
    $processOut=[Console]::Out;$processErr=[Console]::Error;$processEncoding=[Console]::OutputEncoding
    $processInProcess=@(& $maintenanceProcessResolver -InputPath $maintenanceProcessInputPath -AsJson)
    $processParsed=($processInProcess-join"`n")|ConvertFrom-Json -Depth 100
    Assert-True (($processParsed.selectedRuleBlocks|ConvertTo-Json -Depth 100 -Compress)-ceq($maintenanceProcessResult.selectedRuleBlocks|ConvertTo-Json -Depth 100 -Compress)-and[object]::ReferenceEquals($processOut,[Console]::Out)-and[object]::ReferenceEquals($processErr,[Console]::Error)-and[object]::ReferenceEquals($processEncoding,[Console]::OutputEncoding)) 'maintenance-process-native-inprocess-complete-ordered-rule-bodies-and-writers'
    foreach($block in $maintenanceProcessResult.selectedRuleBlocks){
        Assert-True ([string]::Equals($block.fullText,(@($block.displayParts.fullText)-join"`n`n"),[StringComparison]::Ordinal)) ('maintenance-process-fulltext-matches-complete-display-parts-'+$block.requirementId)
    }
    $maintenanceContinuationDiscoverReceiptPath=Join-Path $controlPlane 'maintenance-continuation-discover-receipt.json';$maintenanceTestDiscoverReceiptPath=Join-Path $controlPlane 'maintenance-test-discover-receipt.json';$maintenanceContinuationBoundaryPath=Join-Path $controlPlane 'maintenance-continuation-boundary.json';$maintenanceContinuationReceiptPath=Join-Path $controlPlane 'maintenance-action-continuation-receipt.json'
    Write-Utf8 $maintenanceContinuationDiscoverReceiptPath ($maintenanceProcessValue|ConvertTo-Json -Depth 40)
    $maintenanceContinuationPrep=@($maintenanceProcessValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$maintenanceContinuationResults=@($maintenanceProcessValue.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $maintenanceContinuationAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$maintenanceContinuationDiscoverReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $maintenanceContinuationDiscoverReceiptPath;preparationReceipts=$maintenanceContinuationPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Utf8 $maintenanceContinuationBoundaryPath ($maintenanceContinuationAdmit|ConvertTo-Json -Depth 30);$maintenanceContinuationAdmitRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceContinuationBoundaryPath,'-AsJson')
    $maintenanceTargetPath=Join-Path $target $targetObject
    $maintenanceTargetPreBytes=[IO.File]::ReadAllBytes($maintenanceTargetPath)
    $maintenanceTargetPreIdentity=Get-Identity $maintenanceTargetPath
    $maintenanceTargetPackageIdentity=Get-Identity $targetPackage
    try {
        Write-Utf8 (Join-Path $target $targetObject) 'authorized target postimage'
        $maintenanceContinuationFinalize=$maintenanceContinuationAdmit|ConvertTo-Json -Depth 30|ConvertFrom-Json;$maintenanceContinuationFinalize.mode='FINALIZE_OUTPUT';$maintenanceContinuationFinalize.resultReceipts=@($maintenanceContinuationResults+@('OBJECT_POSTIMAGE|'+$targetObject+'|'+(Get-Identity (Join-Path $target $targetObject))))
        Write-Utf8 $maintenanceContinuationBoundaryPath ($maintenanceContinuationFinalize|ConvertTo-Json -Depth 30);$maintenanceContinuationFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceContinuationBoundaryPath,'-AsJson');$maintenanceContinuationFinalizeValue=if($maintenanceContinuationFinalizeRun.Code-eq0){$maintenanceContinuationFinalizeRun.Output[-1]|ConvertFrom-Json}else{$null}
        if($null-ne$maintenanceContinuationFinalizeValue-and$null-ne$maintenanceContinuationFinalizeValue.PSObject.Properties['continuationReceipt']){Write-Utf8 $maintenanceContinuationReceiptPath ($maintenanceContinuationFinalizeValue.continuationReceipt|ConvertTo-Json -Depth 30)}
        $maintenanceTestInput=$maintenanceProcessInput|ConvertTo-Json -Depth 40|ConvertFrom-Json;$maintenanceTestInput.intentEnvelope.requestedActionKind='TEST_RUN';$maintenanceTestInput.intentEnvelope.requestedResultKind='TEST_RESULT';$maintenanceTestInput.intentEnvelope.objective='Test the exact authorized Framework target postimage';$maintenanceTestInput.intentEnvelope.mutationHints=@('test');$maintenanceTestInput|Add-Member -NotePropertyName continuationReceiptPath -NotePropertyValue $maintenanceContinuationReceiptPath;$maintenanceTestInput|Add-Member -NotePropertyName expectedContinuationReceiptIdentity -NotePropertyValue $(if(Test-Path -LiteralPath $maintenanceContinuationReceiptPath){Get-Identity $maintenanceContinuationReceiptPath}else{'MISSING'})
        Write-Utf8 $maintenanceProcessInputPath ($maintenanceTestInput|ConvertTo-Json -Depth 40);$maintenanceTestRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceProcessInputPath,'-AsJson');$maintenanceTestResult=if($maintenanceTestRun.Code-eq0){$maintenanceTestRun.Output[-1]|ConvertFrom-Json}else{$null};$maintenanceTestReceipt=if($null-ne$maintenanceTestResult){$maintenanceTestResult.compactReceipt}else{$null}
        if($null-ne$maintenanceTestReceipt){Write-Utf8 $maintenanceTestDiscoverReceiptPath ($maintenanceTestReceipt|ConvertTo-Json -Depth 40);$maintenanceTestPrep=@($maintenanceTestReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$maintenanceTestAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$maintenanceTestDiscoverReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $maintenanceTestDiscoverReceiptPath;preparationReceipts=$maintenanceTestPrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'};Write-Utf8 $maintenanceContinuationBoundaryPath ($maintenanceTestAdmit|ConvertTo-Json -Depth 30);$maintenanceTestAdmitRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceContinuationBoundaryPath,'-AsJson')}else{$maintenanceTestAdmitRun=[pscustomobject]@{Code=2;Text='NO_TEST_RECEIPT'}}
        $maintenanceContinuationEmitted=$null-ne$maintenanceContinuationFinalizeValue-and$null-ne$maintenanceContinuationFinalizeValue.PSObject.Properties['continuationReceipt']
        Assert-True ($maintenanceContinuationAdmitRun.Code-eq0-and$maintenanceContinuationFinalizeRun.Code-eq0-and$maintenanceContinuationEmitted-and$maintenanceTestRun.Code-eq0-and$maintenanceTestAdmitRun.Code-eq0-and[int]$maintenanceTestReceipt.binding.continuationStepIndex-eq1-and[string]$maintenanceTestReceipt.binding.projectRoot-ceq([IO.Path]::GetFullPath($control))) 'process-maintenance-root-adapters-consume-write-postimage-continuation'
    } finally {
        [IO.File]::WriteAllBytes($maintenanceTargetPath,$maintenanceTargetPreBytes)
    }
    Assert-True ((Get-Identity $maintenanceTargetPath)-ceq$maintenanceTargetPreIdentity-and(Get-Identity $targetPackage)-ceq$maintenanceTargetPackageIdentity-and$maintenanceTargetPackageIdentity-ceq$maintenanceProcessInput.expectedAuthorizationIdentity) 'process-maintenance-continuation-restores-original-object-and-package-binding'

    $compactMaintenanceInputPath=Join-Path $controlPlane 'maintenance-compact2-process.json'
    $compactMaintenanceReceiptPath=Join-Path $controlPlane 'maintenance-compact2-receipt.json'
    $compactMaintenanceBoundaryPath=Join-Path $controlPlane 'maintenance-compact2-boundary.json'
    $compactMaintenanceIntent=(New-CurrentFixtureIntent ([ordered]@{schemaVersion=1;objective='Modify one bounded Maintenance control object';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('implementation');pathHints=@($controlObject);capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'}))
    $compactMaintenanceInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$control;frameworkRoot=$fixedRuntime;taskPath=$maintenanceProcessTask;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity=(Get-Identity $maintenanceProcessTask);observedActor='controller-fixture';capabilities=@();exactPaths=@($controlObject);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$controlPackage;expectedAuthorizationIdentity=(Get-Identity $controlPackage);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$compactMaintenanceIntent;evaluationOnly=$false}
    Write-Utf8 $compactMaintenanceInputPath ($compactMaintenanceInput|ConvertTo-Json -Depth 30);$compactMaintenanceRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$compactMaintenanceInputPath,'-AsJson');$compactMaintenanceResult=if($compactMaintenanceRun.Code-eq0){$compactMaintenanceRun.Output[-1]|ConvertFrom-Json}else{$null};$compactMaintenanceReceipt=if($null-ne$compactMaintenanceResult){$compactMaintenanceResult.compactReceipt}else{$null}
    Assert-True ($compactMaintenanceRun.Code-eq0-and[int]$compactMaintenanceReceipt.schemaVersion-eq3-and[string]$compactMaintenanceReceipt.binding.projectRoot-ceq[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($control))) 'process-maintenance-compact2-discover-binds-control-root'
    Write-Utf8 $compactMaintenanceReceiptPath ($compactMaintenanceReceipt|ConvertTo-Json -Depth 30)
    $compactMaintenancePrep=@($compactMaintenanceReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$compactMaintenanceResults=@($compactMaintenanceReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $compactMaintenanceAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$compactMaintenanceReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $compactMaintenanceReceiptPath;preparationReceipts=$compactMaintenancePrep;resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Utf8 $compactMaintenanceBoundaryPath ($compactMaintenanceAdmit|ConvertTo-Json -Depth 30);$compactMaintenanceAdmitRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$compactMaintenanceBoundaryPath,'-AsJson')
    Assert-True ($compactMaintenanceAdmitRun.Code-eq0) 'process-maintenance-compact2-admit-uses-binding-project-root'
    $compactMaintenanceFinalize=[ordered]@{schemaVersion=2;mode='FINALIZE_OUTPUT';discoverReceiptPath=$compactMaintenanceReceiptPath;expectedDiscoverReceiptIdentity=Get-Identity $compactMaintenanceReceiptPath;preparationReceipts=$compactMaintenancePrep;resultReceipts=@($compactMaintenanceResults+@('OBJECT_POSTIMAGE|'+$controlObject+'|'+(Get-Identity (Join-Path $control $controlObject))));deliveryReceipts=@('DELIVERED');publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Utf8 $compactMaintenanceBoundaryPath ($compactMaintenanceFinalize|ConvertTo-Json -Depth 30);$compactMaintenanceFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$compactMaintenanceBoundaryPath,'-AsJson')
    Assert-True ($compactMaintenanceFinalizeRun.Code-eq0) 'process-maintenance-compact2-finalize-uses-binding-project-root'

    foreach($jsonRun in @($maintenanceContinuationAdmitRun,$maintenanceContinuationFinalizeRun,$maintenanceTestRun,$maintenanceTestAdmitRun,$compactMaintenanceRun,$compactMaintenanceAdmitRun,$compactMaintenanceFinalizeRun)){
        $jsonValue=$jsonRun.Stdout|ConvertFrom-Json -Depth 100
        Assert-True ($jsonRun.Code-eq0-and$jsonRun.Stderr-ceq''-and$jsonRun.Stdout-notmatch'[^\x00-\x7f]'-and$jsonValue-is[pscustomobject]-and$jsonValue.status-ceq'PASS') 'maintenance-process-boundaries-single-complete-ascii-json'
    }
    if($Case-ceq'JsonConsumers'){Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-json-consumers';return}
    $batchWrapper = Join-Path $controlPlane 'invoke-batch-authorization.ps1'
    Write-Utf8 $batchWrapper ((@'
param([string]$Checker,[string]$Package,[string]$ObjectPath,[string]$ObjectIdentity,[string]$ConfigIdentity,[string]$TaskIdentity,[switch]$Duplicate)
__AIW_TEST_NATIVE_OUTPUT__
$actions=if($Duplicate){@('SOURCE_WRITE','SOURCE_WRITE')}else{@('SOURCE_WRITE','TEST_RUN')}
& $Checker -PackagePath $Package -ObservedActor 'controller-fixture' -ObservedTaskId 'FIXTURE-001' -ObservedOwner 'controller-fixture' -ObservedAction $actions -ObservedPath @($ObjectPath) -ObservedIdentity @($ObjectPath+'='+$ObjectIdentity) -ControllerControlPath '.ai-workspace/controller.json' -ObservedRepositoryId 'ai-workspace-framework' -ProjectConfigPath '.ai-workspace/project.json' -ExpectedProjectConfigIdentity $ConfigIdentity -TaskPath '.ai-workspace/tasks/active/FIXTURE-001.md' -ExpectedTaskIdentity $TaskIdentity
exit $LASTEXITCODE
'@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
    $batchArgs=@('-Checker',$checker,'-Package',$targetPackage,'-ObjectPath',$targetObject,'-ObjectIdentity',(Get-Identity (Join-Path $target $targetObject)),'-ConfigIdentity',$configIdentity,'-TaskIdentity',(Get-Identity (Join-Path $control '.ai-workspace/tasks/active/FIXTURE-001.md')))
    $batchAuth=Invoke-Ps $batchWrapper $batchArgs $control
    $batchPassCount=@($batchAuth.Output|Where-Object{$_ -like 'PASS|*'}).Count
    Assert-True ($batchAuth.Code -eq 0 -and $batchPassCount -eq 2 -and $batchAuth.Text.Contains('action=SOURCE_WRITE') -and $batchAuth.Text.Contains('action=TEST_RUN')) 'authorization-action-batch-per-action-pass'
    $duplicateBatch=Invoke-Ps $batchWrapper @($batchArgs + '-Duplicate') $control
    Assert-True ($duplicateBatch.Code -ne 0 -and $duplicateBatch.Text.Contains('OBSERVED_ACTION_DUPLICATE')) 'authorization-action-batch-duplicate-rejected'

    $wrongRepository = Invoke-Ps $checker @('-PackagePath',$targetPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($wrongRepository.Code -ne 0 -and $wrongRepository.Text.Contains('REPOSITORY_DRIFT')) 'authorization-schema2-repository-drift-rejected'
    $wrongConfig = Invoke-Ps $checker @('-PackagePath',$controlPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',('0|' + ('0' * 64))) $control
    Assert-True ($wrongConfig.Code -ne 0 -and $wrongConfig.Text.Contains('PROJECT_CONFIG_DRIFT')) 'authorization-schema2-config-drift-rejected'
    $badTargetAction = Invoke-Ps $checker @('-PackagePath',$badTargetActionPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','CONTROL_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    $badControlAction = Invoke-Ps $checker @('-PackagePath',$badControlActionPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$controlObject,'-ObservedIdentity',($controlObject+'='+(Get-Identity (Join-Path $control $controlObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','CONTROL','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($badTargetAction.Code -ne 0 -and $badTargetAction.Text.Contains('TARGET_REPOSITORY_CONTROL_WRITE_DENIED')) 'authorization-target-control-write-denied'
    Assert-True ($badControlAction.Code -ne 0 -and $badControlAction.Text.Contains('CONTROL_REPOSITORY_ACTION_DENIED')) 'authorization-control-source-write-denied'

    $objectDrift = Invoke-Ps $checker @('-PackagePath',$targetPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'=0|'+('0' * 64)),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($objectDrift.Code -ne 0 -and $objectDrift.Text.Contains('OBJECT_DRIFT')) 'authorization-schema2-object-drift-rejected'

    $crossPackage = Join-Path $controlPlane 'cross-repository-auth.json'
    $crossData = Get-Content -LiteralPath $targetPackage -Raw -Encoding utf8 | ConvertFrom-Json
    $crossPath = '../AI-Workspace-Maintenance/.ai-workspace/tasks/README.md'
    $crossData.exactPaths = @($crossPath)
    $crossData.objectIdentities = @([ordered]@{path=$crossPath;identity=(Get-Identity (Join-Path $target $targetObject))})
    Write-Utf8 $crossPackage ($crossData | ConvertTo-Json -Depth 20)
    $crossRepository = Invoke-Ps $checker @('-PackagePath',$crossPackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$crossPath,'-ObservedIdentity',($crossPath+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Assert-True ($crossRepository.Code -ne 0 -and $crossRepository.Text.Contains('EXACT_PATH_INVALID')) 'authorization-schema2-cross-repository-path-rejected'

    $stalePackage = Join-Path $controlPlane 'stale-controller-auth.json'
    Copy-Item -LiteralPath $targetPackage -Destination $stalePackage
    $currentControllerRaw = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $epochController = $currentControllerRaw | ConvertFrom-Json
    $epochController.controllerEpoch = 2
    Write-Utf8 $controllerPath ($epochController | ConvertTo-Json -Depth 10)
    $staleData = Get-Content -LiteralPath $stalePackage -Raw -Encoding utf8 | ConvertFrom-Json
    $staleData.controllerControlIdentity = Get-Identity $controllerPath
    Write-Utf8 $stalePackage ($staleData | ConvertTo-Json -Depth 20)
    $staleAuthorization = Invoke-Ps $checker @('-PackagePath',$stalePackage,'-ObservedActor','controller-fixture','-ObservedTaskId','FIXTURE-001','-ObservedOwner','controller-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+(Get-Identity (Join-Path $target $targetObject))),'-ControllerControlPath','.ai-workspace/controller.json','-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity) $control
    Write-Utf8 $controllerPath $currentControllerRaw
    Assert-True ($staleAuthorization.Code -ne 0 -and $staleAuthorization.Text.Contains('STALE_CONTROLLER_AUTHORIZATION')) 'authorization-schema2-stale-controller-rejected'

    $controlTaskRelative='.ai-workspace/tasks/active/FIXTURE-001.md';$controlTaskPackage=Join-Path $controlPlane 'control-task-finalize-auth.json'
    New-AuthorizationPackage $controlTaskPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlTaskRelative (Get-Identity (Join-Path $control $controlTaskRelative))
    $controlTaskPath=Join-Path $control $controlTaskRelative;$controlTaskIntent=(New-CurrentFixtureIntent ([ordered]@{schemaVersion=1;objective='Finalize one bounded control task record';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('task','control');pathHints=@($controlTaskRelative);capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'}))
    $controlTaskDiscoverInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$control;frameworkRoot=$fixedRuntime;taskPath=$controlTaskPath;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity=(Get-Identity $controlTaskPath);observedActor='controller-fixture';capabilities=@();exactPaths=@($controlTaskRelative);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$controlTaskPackage;expectedAuthorizationIdentity=(Get-Identity $controlTaskPackage);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$controlTaskIntent;evaluationOnly=$false}
    $controlTaskInputPath=Join-Path $controlPlane 'control-task-process.json';Write-Utf8 $controlTaskInputPath ($controlTaskDiscoverInput|ConvertTo-Json -Depth 30)
    $controlTaskDiscoverRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson');$controlTaskDiscoverResult=$controlTaskDiscoverRun.Output[-1]|ConvertFrom-Json;$controlTaskReceipt=$controlTaskDiscoverResult.compactReceipt
    $controlTaskReceiptPath=Join-Path $controlPlane 'control-task-discover-receipt.json';Write-Utf8 $controlTaskReceiptPath ($controlTaskReceipt|ConvertTo-Json -Depth 40)
    $controlTaskPrep=@($controlTaskReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$controlTaskResults=@($controlTaskReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $controlTaskBoundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$controlTaskReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $controlTaskReceiptPath);objective=$controlTaskIntent.objective;actionKind='CONTROL_WRITE';resultKind='IMPLEMENTATION_RESULT';exactPaths=@($controlTaskRelative);authorizationIdentity=(Get-Identity $controlTaskPackage);preparationReceipts=@($controlTaskPrep);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
    Write-Utf8 $controlTaskInputPath ($controlTaskBoundary|ConvertTo-Json -Depth 30);$controlTaskAdmitRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    if($controlTaskDiscoverRun.Code-ne0-or$controlTaskAdmitRun.Code-ne0){throw ('ASSERT_FAIL|process-control-task-admit-binds-exact-preimage|discover='+$controlTaskDiscoverRun.Code+'|'+$controlTaskDiscoverRun.Text+'|admit='+$controlTaskAdmitRun.Code+'|'+$controlTaskAdmitRun.Text)}
    Assert-True ($controlTaskDiscoverRun.Code-eq0-and$controlTaskAdmitRun.Code-eq0) 'process-control-task-admit-binds-exact-preimage'
    $controlTaskPreText=Get-Content -Raw -Encoding utf8 -LiteralPath $controlTaskPath;$controlTaskPostText=$controlTaskPreText.TrimEnd("`n")+"`n`n- Completion: STRUCTURALLY_FINALIZED`n";Write-Utf8 $controlTaskPath $controlTaskPostText
    $controlTaskFinalize=$controlTaskBoundary|ConvertTo-Json -Depth 40|ConvertFrom-Json;$controlTaskFinalize.mode='FINALIZE_OUTPUT';$controlTaskFinalize.resultReceipts=@($controlTaskResults+@('OBJECT_POSTIMAGE|'+$controlTaskRelative+'|'+(Get-Identity $controlTaskPath)));Write-Utf8 $controlTaskInputPath ($controlTaskFinalize|ConvertTo-Json -Depth 40)
    $controlTaskFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    Assert-True ($controlTaskFinalizeRun.Code-eq0-and$controlTaskFinalizeRun.Text.Contains('STRUCTURAL_REQUIREMENTS_COMPLETE')) 'process-control-task-finalize-allows-narrow-preimage-to-postimage-transition'
    $controlTaskBindingDrifts=@(
        [pscustomobject]@{Name='task-id';Text=$controlTaskPostText-replace '^# FIXTURE-001 ','# FIXTURE-OTHER-001 '},
        [pscustomobject]@{Name='owner';Text=$controlTaskPostText-replace '(?m)^- Owner: controller-fixture$','- Owner: wrong-owner'},
        [pscustomobject]@{Name='actor';Text=$controlTaskPostText-replace 'actor=controller-fixture','actor=successor-fixture'},
        [pscustomobject]@{Name='role';Text=$controlTaskPostText-replace 'role=CONTROLLER','role=EXECUTOR'},
        [pscustomobject]@{Name='phase';Text=$controlTaskPostText-replace 'phase=IMPLEMENT','phase=PLAN'},
        [pscustomobject]@{Name='profile';Text=$controlTaskPostText-replace 'profile=STANDARD','profile=CRITICAL'}
    )
    foreach($bindingDrift in $controlTaskBindingDrifts){
        Write-Utf8 $controlTaskPath $bindingDrift.Text
        $bindingDriftFinalize=$controlTaskFinalize|ConvertTo-Json -Depth 40|ConvertFrom-Json;$bindingDriftFinalize.resultReceipts=@($controlTaskResults+@('OBJECT_POSTIMAGE|'+$controlTaskRelative+'|'+(Get-Identity $controlTaskPath)));Write-Utf8 $controlTaskInputPath ($bindingDriftFinalize|ConvertTo-Json -Depth 40)
        $bindingDriftFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
        Assert-True ($bindingDriftFinalizeRun.Code-ne0-and$bindingDriftFinalizeRun.Text.Contains('CONTROL_TASK_POSTIMAGE_BINDING_DRIFT')) ('process-control-task-finalize-rejects-'+$bindingDrift.Name+'-drift')
    }
    Write-Utf8 $controlTaskPath $controlTaskPostText
    $successorTaskText=$controlTaskPostText-replace 'actor=controller-fixture; role=CONTROLLER','actor=successor-fixture; role=EXECUTOR';Write-Utf8 $controlTaskPath $successorTaskText
    $successorTaskPackage=Join-Path $controlPlane 'control-task-successor-auth.json';$successorTaskPackageData=Get-Content -Raw -Encoding utf8 -LiteralPath $controlTaskPackage|ConvertFrom-Json;$successorTaskPackageData.grantee='successor-fixture';$successorTaskPackageData.taskIdentity=Get-Identity $controlTaskPath;$successorTaskPackageData.objectIdentities[0].identity=Get-Identity $controlTaskPath;Write-Utf8 $successorTaskPackage ($successorTaskPackageData|ConvertTo-Json -Depth 40)
    $successorTaskDiscoverInput=$controlTaskDiscoverInput|ConvertTo-Json -Depth 40|ConvertFrom-Json;$successorTaskDiscoverInput.expectedTaskIdentity=Get-Identity $controlTaskPath;$successorTaskDiscoverInput.observedActor='successor-fixture';$successorTaskDiscoverInput.authorizationPackagePath=$successorTaskPackage;$successorTaskDiscoverInput.expectedAuthorizationIdentity=Get-Identity $successorTaskPackage;Write-Utf8 $controlTaskInputPath ($successorTaskDiscoverInput|ConvertTo-Json -Depth 40)
    $successorTaskDiscoverRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson');$successorTaskDiscoverResult=$successorTaskDiscoverRun.Output[-1]|ConvertFrom-Json
    Assert-True ($successorTaskDiscoverRun.Code-eq0-and[string]$successorTaskDiscoverResult.compactReceipt.binding.taskActor-ceq'successor-fixture'-and[string]$successorTaskDiscoverResult.compactReceipt.binding.actor-ceq'successor-fixture'-and[string]$successorTaskDiscoverResult.compactReceipt.binding.role-ceq'EXECUTOR'-and[string]$successorTaskDiscoverResult.compactReceipt.binding.phase-ceq'IMPLEMENT'-and[string]$successorTaskDiscoverResult.compactReceipt.binding.profile-ceq'STANDARD') 'process-control-task-fresh-package-and-discover-rebind-current-route-without-permanent-actor-lock'
    Write-Utf8 $controlTaskPath $controlTaskPostText
    $wrongPathReceipt=$controlTaskReceipt|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPathReceipt.binding.exactScope=@($controlObject);$wrongPathReceiptPath=Join-Path $controlPlane 'control-task-wrong-path-receipt.json';Write-Utf8 $wrongPathReceiptPath ($wrongPathReceipt|ConvertTo-Json -Depth 40);$wrongPathBoundary=$controlTaskFinalize|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPathBoundary.discoverReceiptPath=$wrongPathReceiptPath;$wrongPathBoundary.expectedDiscoverReceiptIdentity=Get-Identity $wrongPathReceiptPath;$wrongPathBoundary.exactPaths=@($controlObject);Write-Utf8 $controlTaskInputPath ($wrongPathBoundary|ConvertTo-Json -Depth 40)
    $wrongPathFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    Assert-True ($wrongPathFinalizeRun.Code-ne0-and$wrongPathFinalizeRun.Text.Contains('DISCOVER_SOURCE_DRIFT|taskIdentity')) 'process-control-task-finalize-rejects-non-task-exact-path-transition'
    $wrongPackageReceipt=$controlTaskReceipt|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPackageReceipt.sourceLocators.authorizationPackagePath=$targetPackage;$wrongPackageReceipt.binding.authorizationIdentity=Get-Identity $targetPackage;$wrongPackageReceiptPath=Join-Path $controlPlane 'control-task-wrong-package-receipt.json';Write-Utf8 $wrongPackageReceiptPath ($wrongPackageReceipt|ConvertTo-Json -Depth 40);$wrongPackageBoundary=$controlTaskFinalize|ConvertTo-Json -Depth 40|ConvertFrom-Json;$wrongPackageBoundary.discoverReceiptPath=$wrongPackageReceiptPath;$wrongPackageBoundary.expectedDiscoverReceiptIdentity=Get-Identity $wrongPackageReceiptPath;$wrongPackageBoundary.authorizationIdentity=Get-Identity $targetPackage;Write-Utf8 $controlTaskInputPath ($wrongPackageBoundary|ConvertTo-Json -Depth 40)
    $wrongPackageFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson')
    Assert-True ($wrongPackageFinalizeRun.Code-ne0-and$wrongPackageFinalizeRun.Text.Contains('CONTROL_TASK_POSTIMAGE_TRANSITION_NOT_AUTHORIZED')) 'process-control-task-finalize-rejects-non-control-package-transition'
    $controlCorrectionsPath=Join-Path $controlPlane 'corrections.json';$controlCorrectionsRaw=Get-Content -Raw -Encoding utf8 -LiteralPath $controlCorrectionsPath;Write-Utf8 $controlCorrectionsPath ($controlCorrectionsRaw.TrimEnd("`n")+"`n`n");Write-Utf8 $controlTaskInputPath ($controlTaskFinalize|ConvertTo-Json -Depth 40)
    $controlTaskOtherSourceDrift=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$controlTaskInputPath,'-AsJson');[IO.File]::WriteAllText($controlCorrectionsPath,$controlCorrectionsRaw,[Text.UTF8Encoding]::new($false))
    Assert-True ($controlTaskOtherSourceDrift.Code-ne0-and$controlTaskOtherSourceDrift.Text.Contains('DISCOVER_SOURCE_DRIFT|correctionsIdentity')) 'process-control-task-finalize-rejects-all-other-source-drift'

    Commit-All $control 'control baseline'
    Commit-All $target 'target baseline'
    Write-Utf8 (Join-Path $control $controlObject) '# changed control task index'
    Write-Utf8 (Join-Path $target $targetObject) 'changed public target'
    Write-Utf8 (Join-Path $target 'private\secret.txt') 'changed private target'
    $maintenanceTextconvMarker=Join-Path $target 'maintenance-textconv-invoked.txt'
    $maintenanceTextconvDriver=Join-Path $target 'maintenance-textconv.ps1'
    Write-Utf8 (Join-Path $target '.gitattributes') ($targetObject+' diff=aiw-maintenance-safe')
    Write-Utf8 $maintenanceTextconvDriver ('param([string]$ObjectPath)' + "`n" + '[IO.File]::WriteAllText((Join-Path $PSScriptRoot "maintenance-textconv-invoked.txt"),"ANONYMOUS_FIXTURE_INVOKED")' + "`n" + 'Get-Content -LiteralPath $ObjectPath -Raw')
    $maintenanceTextconvCommand='pwsh -NoProfile -NonInteractive -File "'+$maintenanceTextconvDriver.Replace('\','/')+'"'
    & git -C $target config diff.aiw-maintenance-safe.textconv $maintenanceTextconvCommand
    if($LASTEXITCODE-ne0){throw 'MAINTENANCE_TEXTCONV_FIXTURE_CONFIG_FAILED'}

    $safeGit = Join-Path $fixedRuntime 'scripts\invoke-framework-maintenance-safe-git.ps1'
    $controlStatus = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath',$controlObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','CONTROL')
    $targetStatus = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    $controlDiff = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','DIFF','-AllowPath',$controlObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','CONTROL')
    $targetDiff = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','DIFF','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    $targetExcluded = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    $targetOverride = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath','private/secret.txt','-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework','-IncludeRoutineExcluded')
    try { $targetStatusJson = @($targetStatus.Output)[-1] | ConvertFrom-Json } catch { throw ('TARGET_STATUS_JSON|' + $targetStatus.Code + '|' + $targetStatus.Text) }
    try { $targetExcludedJson = @($targetExcluded.Output)[-1] | ConvertFrom-Json } catch { throw ('TARGET_EXCLUDED_JSON|' + $targetExcluded.Code + '|' + $targetExcluded.Text) }
    try { $targetOverrideJson = @($targetOverride.Output)[-1] | ConvertFrom-Json } catch { throw ('TARGET_OVERRIDE_JSON|' + $targetOverride.Code + '|' + $targetOverride.Text) }
    if (-not ($targetStatusJson -is [pscustomobject]) -or $null -eq $targetStatusJson.PSObject.Properties['output']) { throw ('TARGET_STATUS_NO_OUTPUT|' + $targetStatus.Code + '|' + $targetStatus.Text) }
    if (-not ($targetExcludedJson -is [pscustomobject]) -or $null -eq $targetExcludedJson.PSObject.Properties['output']) { throw ('TARGET_EXCLUDED_NO_OUTPUT|' + $targetExcluded.Code + '|' + $targetExcluded.Text) }
    if (-not ($targetOverrideJson -is [pscustomobject]) -or $null -eq $targetOverrideJson.PSObject.Properties['output']) { throw ('TARGET_OVERRIDE_NO_OUTPUT|' + $targetOverride.Code + '|' + $targetOverride.Text) }
    $targetOutput = @($targetStatusJson.output) -join "`n"
    $excludedOutput = @($targetExcludedJson.output) -join "`n"
    $overrideOutput = @($targetOverrideJson.output) -join "`n"
    Assert-True ($controlStatus.Code -eq 0 -and $controlStatus.Text.Contains($controlObject) -and $controlStatus.Text.Contains('"repositoryId":"CONTROL"')) 'safe-git-maintenance-control-selected'
    Assert-True ($targetStatus.Code -eq 0 -and $targetOutput.Contains($targetObject) -and $targetStatus.Text.Contains('"repositoryId":"ai-workspace-framework"')) 'safe-git-maintenance-target-selected'
    Assert-True ($targetExcluded.Code -eq 0 -and -not $excludedOutput.Contains('private/secret.txt')) 'safe-git-maintenance-target-exclusions'
    Assert-True ($targetOverride.Code -eq 0 -and $overrideOutput.Contains('private/secret.txt')) 'safe-git-maintenance-exact-exclusion-override'
    Assert-True ($controlDiff.Code -eq 0 -and $controlDiff.Text.Contains($controlObject) -and $controlDiff.Text.Contains('"operation":"DIFF"')) 'safe-git-maintenance-control-diff'
    Assert-True ($targetDiff.Code -eq 0 -and $targetDiff.Text.Contains($targetObject) -and $targetDiff.Text.Contains('"operation":"DIFF"')) 'safe-git-maintenance-target-diff'
    Assert-True ($targetDiff.Code-eq0-and$targetDiff.Text.Contains('changed public target')-and-not(Test-Path -LiteralPath $maintenanceTextconvMarker)) 'safe-git-maintenance-diff-disables-textconv-and-returns-raw-content'

    & git -C $control add -- $controlObject
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_FIXTURE_STAGE_FAILED' }
    & git -C $target add -- $targetObject
    if ($LASTEXITCODE -ne 0) { throw 'TARGET_FIXTURE_STAGE_FAILED' }
    $controlIndex = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','INDEX','-AllowPath',$controlObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','CONTROL')
    $targetIndex = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','INDEX','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','ai-workspace-framework')
    Assert-True ($controlIndex.Code -eq 0 -and $controlIndex.Text.Contains($controlObject) -and $controlIndex.Text.Contains('"operation":"INDEX"')) 'safe-git-maintenance-control-index'
    Assert-True ($targetIndex.Code -eq 0 -and $targetIndex.Text.Contains($targetObject) -and $targetIndex.Text.Contains('"operation":"INDEX"')) 'safe-git-maintenance-target-index'
    $maintenanceAlternateIndex=Join-Path $temp 'maintenance-safe-git-alternate.index'
    $previousIndexOverride=[Environment]::GetEnvironmentVariable('GIT_INDEX_FILE','Process')
    try{
        [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',$maintenanceAlternateIndex,'Process')
        & git -C $control read-tree HEAD
        if($LASTEXITCODE-ne0){throw 'MAINTENANCE_ALTERNATE_INDEX_FIXTURE_FAILED'}
        $maintenanceAlternateIndexOutput=@(& git -C $control diff --cached --name-status -- $controlObject 2>&1|ForEach-Object{[string]$_})
        if($LASTEXITCODE-ne0){throw 'MAINTENANCE_ALTERNATE_INDEX_OBSERVATION_FAILED'}
    }finally{
        if([string]::IsNullOrEmpty($previousIndexOverride)){Remove-Item -LiteralPath 'Env:\GIT_INDEX_FILE' -ErrorAction SilentlyContinue}else{[Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',$previousIndexOverride,'Process')}
    }
    $maintenanceIndexOverride=Invoke-PsWithProcessEnvironment $safeGit @('-ProjectRoot',$control,'-Operation','INDEX','-AllowPath',$controlObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','CONTROL') $control @{GIT_INDEX_FILE=$maintenanceAlternateIndex}
    Assert-True ((Test-Path -LiteralPath $maintenanceAlternateIndex -PathType Leaf)-and$maintenanceAlternateIndexOutput.Count-eq0-and$maintenanceIndexOverride.Code-ne0-and$maintenanceIndexOverride.Text.Contains('GIT_ENVIRONMENT_OVERRIDE_GIT_INDEX_FILE')-and$maintenanceIndexOverride.Text.Contains('"launched":false')) 'safe-git-maintenance-rejects-real-alternate-index-before-resolver-or-git'

    $unknownRepository = Invoke-Ps $safeGit @('-ProjectRoot',$control,'-Operation','STATUS','-AllowPath',$targetObject,'-ExpectedProjectConfigIdentity',$configIdentity,'-RepositoryId','UNKNOWN')
    Assert-True ($unknownRepository.Code -ne 0 -and $unknownRepository.Text.Contains('REPOSITORY_ID_UNKNOWN') -and $unknownRepository.Text.Contains('"launched":false')) 'safe-git-maintenance-unknown-repository-not-launched'

    $checker = $versionChecker
    $safeGit = Join-Path $installedFramework 'scripts\invoke-protected-safe-git.ps1'
    $repoLocal = Join-Path $temp 'repo-local-fixture'
    New-GitRepo $repoLocal
    $repoLocalConfigPath = Join-Path $repoLocal '.ai-workspace\project.json'
    $repoLocalConfig = [ordered]@{schemaVersion=6;id='repo-local-fixture';displayName='Repo Local Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('private/secret.txt');frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false;sources=@()}};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=2;locator='.ai-workspace/process-policy.json'}}
    Write-CurrentFixtureObject PROJECT_CONFIG $repoLocalConfigPath $repoLocalConfig
    Write-Utf8 (Join-Path $repoLocal 'src\public.txt') 'repo local public'
    Write-Utf8 (Join-Path $repoLocal 'private\secret.txt') 'repo local private'
    $repoLocalIdentity = Get-Identity $repoLocalConfigPath
    $repoLocalSchema1Package = Join-Path $repoLocal '.ai-workspace\schema1-auth.json'
    $repoLocalObject = 'src/public.txt'
    $repoLocalObjectIdentity = Get-Identity (Join-Path $repoLocal $repoLocalObject)
    New-AuthorizationPackage $repoLocalSchema1Package 1 '' $repoLocalIdentity @('SOURCE_WRITE') $repoLocalObject $repoLocalObjectIdentity -DomainOwner
    $repoLocalSchema1Auth = Invoke-Ps $checker @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity)) $repoLocal
    $repoLocalStatus = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    $repoLocalExcluded = Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$repoLocalIdentity)
    Assert-True ($repoLocalStatus.Code -eq 0 -and $repoLocalStatus.Text.Contains('src/public.txt') -and $repoLocalStatus.Text.Contains('"repositoryId":"PROJECT"')) 'safe-git-repo-local-default-compatible'
    Assert-True ($repoLocalExcluded.Code -eq 0 -and -not ((@($repoLocalExcluded.Output)[-1] | ConvertFrom-Json).output -join "`n").Contains('private/secret.txt')) 'safe-git-repo-local-exclusion-compatible'
    Assert-True ($repoLocalSchema1Auth.Code -eq 0) 'authorization-schema1-repo-local-current-project-compatible'

    $repoLocal4=Join-Path $temp 'repo-local-schema4-starter-fixture';New-GitRepo $repoLocal4
    $repoLocal4ConfigPath=Join-Path $repoLocal4 '.ai-workspace\project.json'
    $repoLocal4Raw=$projectStarterText.Replace('{{PROJECT_ID_JSON}}','"repo-local-schema4-fixture"').Replace('{{DISPLAY_NAME_JSON}}','"Repo Local Schema4 Fixture"').Replace('{{FRAMEWORK_VERSION_JSON}}','"2.0.0"')
    $repoLocal4Config=$repoLocal4Raw|ConvertFrom-Json;$repoLocal4Config.routineExcludedPaths=@('private/secret.txt');$repoLocal4Raw=$repoLocal4Config|ConvertTo-Json -Depth 20
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4Raw;Write-Utf8 (Join-Path $repoLocal4 'src\public.txt') 'schema4 public baseline';Write-Utf8 (Join-Path $repoLocal4 'private\secret.txt') 'schema4 private baseline';Commit-All $repoLocal4 'schema4 repo-local baseline'
    Write-Utf8 (Join-Path $repoLocal4 'src\public.txt') 'schema4 public changed';Write-Utf8 (Join-Path $repoLocal4 'private\secret.txt') 'schema4 private changed'
    $repoLocalTextconvMarker=Join-Path $repoLocal4 'repo-local-textconv-invoked.txt'
    $repoLocalTextconvDriver=Join-Path $repoLocal4 'repo-local-textconv.ps1'
    Write-Utf8 (Join-Path $repoLocal4 '.gitattributes') 'src/public.txt diff=aiw-repo-local-safe'
    Write-Utf8 $repoLocalTextconvDriver ('param([string]$ObjectPath)' + "`n" + '[IO.File]::WriteAllText((Join-Path $PSScriptRoot "repo-local-textconv-invoked.txt"),"ANONYMOUS_FIXTURE_INVOKED")' + "`n" + 'Get-Content -LiteralPath $ObjectPath -Raw')
    $repoLocalTextconvCommand='pwsh -NoProfile -NonInteractive -File "'+$repoLocalTextconvDriver.Replace('\','/')+'"'
    & git -C $repoLocal4 config diff.aiw-repo-local-safe.textconv $repoLocalTextconvCommand
    if($LASTEXITCODE-ne0){throw 'REPO_LOCAL_TEXTCONV_FIXTURE_CONFIG_FAILED'}
    $repoLocal4Identity=Get-Identity $repoLocal4ConfigPath
    $repoLocal4Status=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4Diff=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','DIFF','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4Excluded=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','private','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4Override=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','private/secret.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity,'-IncludeRoutineExcluded')
    & git -C $repoLocal4 add -- 'src/public.txt';if($LASTEXITCODE-ne0){throw 'SCHEMA4_REPO_LOCAL_STAGE_FAILED'}
    $repoLocal4Index=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','INDEX','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity)
    $repoLocal4ExcludedOutput=((@($repoLocal4Excluded.Output)[-1]|ConvertFrom-Json).output-join"`n");$repoLocal4OverrideOutput=((@($repoLocal4Override.Output)[-1]|ConvertFrom-Json).output-join"`n")
    Assert-True ($repoLocal4Status.Code-eq0-and$repoLocal4Status.Text.Contains('src/public.txt')-and$repoLocal4Status.Text.Contains('"repositoryId":"PROJECT"')) 'safe-git-repo-local-schema4-starter-status'
    Assert-True ($repoLocal4Diff.Code-eq0-and$repoLocal4Diff.Text.Contains('schema4 public changed')) 'safe-git-repo-local-schema4-starter-diff'
    Assert-True ($repoLocal4Diff.Code-eq0-and-not(Test-Path -LiteralPath $repoLocalTextconvMarker)) 'safe-git-repo-local-diff-disables-textconv'
    Assert-True ($repoLocal4Index.Code-eq0-and$repoLocal4Index.Text.Contains('src/public.txt')) 'safe-git-repo-local-schema4-starter-index'
    Assert-True ($repoLocal4Excluded.Code-eq0-and-not$repoLocal4ExcludedOutput.Contains('private/secret.txt')) 'safe-git-repo-local-schema4-starter-exclusion'
    Assert-True ($repoLocal4Override.Code-eq0-and$repoLocal4OverrideOutput.Contains('private/secret.txt')) 'safe-git-repo-local-schema4-starter-exclusion-override'
    $repoLocal4WrongRepository=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',$repoLocal4Identity,'-RepositoryId','CONTROL')
    Assert-True ($repoLocal4WrongRepository.Code-ne0-and$repoLocal4WrongRepository.Text.Contains('REPOSITORY_ID_PROJECT_ONLY')-and$repoLocal4WrongRepository.Text.Contains('"launched":false')) 'safe-git-repo-local-schema4-rejects-non-project-repository-id'
    $repoLocal4Invalid=$repoLocal4Raw|ConvertFrom-Json;$repoLocal4Invalid.processPolicy.locator='.ai-workspace/other-policy.json';Write-Utf8 $repoLocal4ConfigPath ($repoLocal4Invalid|ConvertTo-Json -Depth 20)
    $repoLocal4InvalidRun=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath))
    Assert-True ($repoLocal4InvalidRun.Code-ne0-and$repoLocal4InvalidRun.Text.Contains('PROJECT_CONFIG_PROCESS_POLICY')-and$repoLocal4InvalidRun.Text.Contains('"launched":false')) 'safe-git-repo-local-schema4-invalid-policy-fails-before-git-command'
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4Raw

    $repoLocal4UnicodeTop=[regex]::Replace($repoLocal4Raw,'("routineExcludedPaths"\s*:\s*\[[^\]]*\])','$1, "\u0072outineExcludedPaths": []',1)
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4UnicodeTop
    $gitShimRoot=Join-Path $temp 'safe-git-zero-invocation-shim';$gitShimLog=Join-Path $gitShimRoot 'git-invocations.log'
    Write-Utf8 (Join-Path $gitShimRoot 'git.cmd') "@echo off`necho invoked>>`"%AIW_GIT_SHIM_LOG%`"`nexit /b 97"
    $gitShimEnvironment=@{PATH=($gitShimRoot+';'+[Environment]::GetEnvironmentVariable('PATH','Process'));AIW_GIT_SHIM_LOG=$gitShimLog}
    $repoLocal4UnicodeTopRun=Invoke-PsWithProcessEnvironment $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath)) $repoLocal4 $gitShimEnvironment
    Assert-True ($repoLocal4UnicodeTopRun.Code-ne0-and$repoLocal4UnicodeTopRun.Text.Contains('PROJECT_CONFIG_JSON_DUPLICATE_FIELD|routineExcludedPaths')-and$repoLocal4UnicodeTopRun.Text.Contains('"launched":false')-and-not(Test-Path -LiteralPath $gitShimLog)) 'safe-git-schema4-unicode-top-level-exclusion-duplicate-zero-git-invocation'

    Write-Utf8 $repoLocal4ConfigPath '{"schemaVersion":4,}'
    $repoLocal4MalformedRun=Invoke-PsWithProcessEnvironment $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath)) $repoLocal4 $gitShimEnvironment
    Assert-True ($repoLocal4MalformedRun.Code-ne0-and$repoLocal4MalformedRun.Text.Contains('PROJECT_CONFIG_JSON_STRING')-and$repoLocal4MalformedRun.Text.Contains('"launched":false')-and-not(Test-Path -LiteralPath $gitShimLog)) 'safe-git-schema4-malformed-config-zero-git-invocation'

    $repoLocal4UnicodePolicy=[regex]::Replace($repoLocal4Raw,'("locator"\s*:\s*"\.ai-workspace/process-policy\.json")','$1, "\u006cocator": ".ai-workspace/process-policy.json"',1)
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4UnicodePolicy
    $repoLocal4UnicodePolicyRun=Invoke-Ps $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath))
    Assert-True ($repoLocal4UnicodePolicyRun.Code-ne0-and$repoLocal4UnicodePolicyRun.Text.Contains('PROJECT_CONFIG_JSON_DUPLICATE_FIELD|locator')-and$repoLocal4UnicodePolicyRun.Text.Contains('"launched":false')) 'safe-git-schema4-unicode-nested-policy-duplicate-not-launched'
    Write-Utf8 $repoLocal4ConfigPath $repoLocal4Raw
    $repoLocalGitOverrides=[ordered]@{GIT_DIR=(Join-Path $repoLocal4 '.git');GIT_WORK_TREE=$repoLocal4;GIT_COMMON_DIR=(Join-Path $repoLocal4 '.git');GIT_INDEX_FILE=$maintenanceAlternateIndex}
    foreach($gitEnvironmentName in $repoLocalGitOverrides.Keys){
        $caseEnvironment=@{};foreach($item in $gitShimEnvironment.GetEnumerator()){$caseEnvironment[[string]$item.Key]=[string]$item.Value};$caseEnvironment[[string]$gitEnvironmentName]=[string]$repoLocalGitOverrides[$gitEnvironmentName]
        $repoLocalEnvironmentOverride=Invoke-PsWithProcessEnvironment $safeGit @('-ProjectRoot',$repoLocal4,'-Operation','STATUS','-AllowPath','src/public.txt','-ExpectedProjectConfigIdentity',(Get-Identity $repoLocal4ConfigPath)) $repoLocal4 $caseEnvironment
        Assert-True ($repoLocalEnvironmentOverride.Code-ne0-and$repoLocalEnvironmentOverride.Text.Contains('GIT_ENVIRONMENT_OVERRIDE_'+$gitEnvironmentName)-and$repoLocalEnvironmentOverride.Text.Contains('"launched":false')-and-not(Test-Path -LiteralPath $gitShimLog)) ('safe-git-repo-local-rejects-process-'+$gitEnvironmentName.ToLowerInvariant()+'-before-git')
    }

    $domainExternalTaskPath=Join-Path $repoLocal '.ai-workspace\tasks\active\FIXTURE-EXTERNAL-001.md'
    Write-Utf8 $domainExternalTaskPath "# FIXTURE-EXTERNAL-001 - external authorization fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=EXTERNAL`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[src/public.txt]; actual_paths=[]`n"
    $zeroEscalation=[ordered]@{paymentOrSubscription=$false;commercialLicensing=$false;accountOrCredentialChange=$false;publicPublication=$false;installation=$false;protectedOrSecretUpload=$false;crossDomain=$false;formalAssetActivation=$false;projectPhaseChange=$false;gitOrPush=$false;sharedQuotaOrResource=$false;unknownScope=$false}
    $externalBinding=[ordered]@{schemaVersion=1;route='TASK_OWNER_DIRECT_DOMAIN_EXTERNAL';provider='fixture-provider';orderedOperations=@(
        [ordered]@{operationId='OP-1';operationKind='PROVIDER_PUBLIC_METADATA_READ';declaredInputClass='ZERO_PROJECT_DATA';payloads=@()},
        [ordered]@{operationId='OP-2';operationKind='bounded-transform';declaredInputClass='EXACT_PAYLOADS';payloads=@([ordered]@{payloadKind='normalized-text';normalizedIdentity=$repoLocalObjectIdentity;canonicalizationVersion='UTF8_LF_V1'})}
    );outputUse='project-local reviewed candidate only';totalQuantity=2;perOperationRetryCeiling=1;totalRetryCeiling=2;costClass='FREE';costCeiling=0;stopConditions=@('stop on provider error','stop on ambiguous consumption');batchExecutionMode='ONE_LOGICAL_ATOMIC_EXECUTION';reissuable=$false;ambiguousConsumptionPolicy='BLOCK';escalationFlags=$zeroEscalation}
    $domainExternalPackage=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='FIXTURE-EXTERNAL-001';taskIdentity=(Get-Identity $domainExternalTaskPath);profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='EXTERNAL_LOCAL';decisionClass='EXTERNAL_ACTION';userConfirmation='USER_FIXTURE_EXTERNAL_APPROVED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;actions=@('EXTERNAL');exactPaths=@($repoLocalObject);objectIdentities=@([ordered]@{path=$repoLocalObject;identity=$repoLocalObjectIdentity});projectConfigIdentity=$repoLocalIdentity;invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');externalBinding=$externalBinding}
    $domainExternalPackagePath=Join-Path $repoLocal '.ai-workspace\domain-external-auth.json';Write-Utf8 $domainExternalPackagePath ($domainExternalPackage|ConvertTo-Json -Depth 40)
    $domainExternalArgs=@('-PackagePath',$domainExternalPackagePath,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-EXTERNAL-001','-ObservedOwner','owner-fixture','-ObservedAction','EXTERNAL','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $domainExternalPass=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($domainExternalPass.Code-eq0) 'authorization-domain-owner-exact-free-atomic-external-batch-pass'
    $duplicateNestedExternalRaw=$domainExternalPackage|ConvertTo-Json -Depth 40;$duplicateNestedExternalRaw=[regex]::Replace($duplicateNestedExternalRaw,'"publicPublication"\s*:\s*false','"publicPublication": false, "\u0070ublicPublication": false',1);Write-Utf8 $domainExternalPackagePath $duplicateNestedExternalRaw
    $duplicateNestedExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($duplicateNestedExternalRun.Code-ne0-and$duplicateNestedExternalRun.Text.Contains('PACKAGE_DUPLICATE_MEMBER|publicPublication')) 'authorization-recursive-json-rejects-unicode-nested-external-duplicate'
    # Legacy externalBinding1 remains FREE/0. Existing-grant schema2 positive,
    # scope, withdrawal and actual optional-limit cases run in BindingIndependence.
    $paidExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$paidExternal.externalBinding.costClass='PAID';$paidExternal.externalBinding.costCeiling=1;Write-Utf8 $domainExternalPackagePath ($paidExternal|ConvertTo-Json -Depth 40)
    $paidExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($paidExternalRun.Code-ne0-and$paidExternalRun.Text.Contains('DOMAIN_EXTERNAL_BINDING_VALUES')) 'authorization-domain-owner-paid-external-rejected'
    $escalatedExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$escalatedExternal.externalBinding.escalationFlags.publicPublication=$true;Write-Utf8 $domainExternalPackagePath ($escalatedExternal|ConvertTo-Json -Depth 40)
    $escalatedExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($escalatedExternalRun.Code-ne0-and$escalatedExternalRun.Text.Contains('DOMAIN_EXTERNAL_ESCALATION_REQUIRED|publicPublication')) 'authorization-domain-owner-controller-bound-external-rejected'
    $commercialExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$commercialExternal.externalBinding.escalationFlags.commercialLicensing=$true;Write-Utf8 $domainExternalPackagePath ($commercialExternal|ConvertTo-Json -Depth 40)
    $commercialExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($commercialExternalRun.Code-ne0-and$commercialExternalRun.Text.Contains('DOMAIN_EXTERNAL_ESCALATION_REQUIRED|commercialLicensing')) 'authorization-domain-owner-commercial-licensing-escalates'
    $phaseExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$phaseExternal.externalBinding.escalationFlags.projectPhaseChange=$true;Write-Utf8 $domainExternalPackagePath ($phaseExternal|ConvertTo-Json -Depth 40)
    $phaseExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($phaseExternalRun.Code-ne0-and$phaseExternalRun.Text.Contains('DOMAIN_EXTERNAL_ESCALATION_REQUIRED|projectPhaseChange')) 'authorization-domain-owner-project-phase-change-escalates'
    $zeroDataLeak=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$zeroDataLeak.externalBinding.orderedOperations[0].payloads=@([ordered]@{payloadKind='unexpected';normalizedIdentity=$repoLocalObjectIdentity;canonicalizationVersion='UTF8_LF_V1'});Write-Utf8 $domainExternalPackagePath ($zeroDataLeak|ConvertTo-Json -Depth 40)
    $zeroDataLeakRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($zeroDataLeakRun.Code-ne0-and$zeroDataLeakRun.Text.Contains('DOMAIN_EXTERNAL_ZERO_DATA_HAS_PAYLOAD')) 'authorization-domain-owner-zero-project-data-declaration-enforced'
    $unknownZeroData=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$unknownZeroData.externalBinding.orderedOperations[0].operationKind='ARBITRARY_ZERO_DATA_OPERATION';Write-Utf8 $domainExternalPackagePath ($unknownZeroData|ConvertTo-Json -Depth 40)
    $unknownZeroDataRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($unknownZeroDataRun.Code-ne0-and$unknownZeroDataRun.Text.Contains('DOMAIN_EXTERNAL_ZERO_DATA_OPERATION_NOT_CLOSED')) 'authorization-domain-owner-zero-data-operation-closed-set-enforced'
    $reissuableExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$reissuableExternal.externalBinding.reissuable=$true;$reissuableExternal.externalBinding.ambiguousConsumptionPolicy='RETRY';Write-Utf8 $domainExternalPackagePath ($reissuableExternal|ConvertTo-Json -Depth 40)
    $reissuableExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($reissuableExternalRun.Code-ne0-and$reissuableExternalRun.Text.Contains('DOMAIN_EXTERNAL_BINDING_VALUES')) 'authorization-domain-owner-reissue-or-ambiguous-retry-rejected'
    $mixedExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$mixedExternal.actions=@('EXTERNAL','SOURCE_WRITE');Write-Utf8 $domainExternalPackagePath ($mixedExternal|ConvertTo-Json -Depth 40)
    $mixedExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($mixedExternalRun.Code-ne0-and$mixedExternalRun.Text.Contains('DOMAIN_EXTERNAL_ACTION_MUST_BE_PURE')) 'authorization-domain-owner-external-batch-cannot-split-actions'
    Write-Utf8 $domainExternalTaskPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $domainExternalTaskPath).Replace('phase=EXTERNAL','phase=IMPLEMENT'))
    $routeDriftExternal=$domainExternalPackage|ConvertTo-Json -Depth 40|ConvertFrom-Json;$routeDriftExternal.taskIdentity=Get-Identity $domainExternalTaskPath;Write-Utf8 $domainExternalPackagePath ($routeDriftExternal|ConvertTo-Json -Depth 40)
    $routeDriftExternalRun=Invoke-Ps $checker $domainExternalArgs $repoLocal
    Assert-True ($routeDriftExternalRun.Code-ne0-and$routeDriftExternalRun.Text.Contains('DOMAIN_EXTERNAL_TASK_ROUTE')) 'authorization-domain-owner-external-requires-domain-owner-external-route'
    Write-Utf8 $domainExternalPackagePath ($domainExternalPackage|ConvertTo-Json -Depth 40)

    $criticalReviewPackagePath = Join-Path $repoLocal '.ai-workspace\critical-review-auth.json'
    $criticalReviewTaskPath=Join-Path $repoLocal '.ai-workspace\tasks\active\FIXTURE-REVIEW-001.md'
    Write-Utf8 $criticalReviewTaskPath "# FIXTURE-REVIEW-001 - review authorization fixture`n`n- Task schema: 2.0.0`n- Owner: owner-fixture`n- Work route: actor=cross-domain-writer; role=EXECUTOR; phase=VERIFY`n- Range summary: profile=CRITICAL; lifecycle=REVIEW; current_exact=src/public.txt; expected_paths=[src/public.txt]; actual_paths=[src/public.txt]`n- Proportionality: existing=sufficient; classification=execution_deviation; minimum_sufficient_fix=independent review; added_machinery=NONE; escalation_trigger=NONE`n- Stable candidate: src/public.txt`n"
    $criticalReviewPackage = [ordered]@{
        schemaVersion=1;frameworkVersion='2.0.0';taskId='FIXTURE-REVIEW-001';taskIdentity=(Get-Identity $criticalReviewTaskPath);profile='CRITICAL';lifecycle='ACTIVE'
        owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='reviewer-fixture';bundle='REVIEW_LOCAL'
        decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='INDEPENDENT';delegatedGitCloser=$false
        actions=@('REVIEW_EXECUTE');exactPaths=@($repoLocalObject);objectIdentities=@([ordered]@{path=$repoLocalObject;identity=$repoLocalObjectIdentity})
        projectConfigIdentity=$repoLocalIdentity
        invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','CONTRIBUTOR_SET_CHANGE','PROJECT_CONFIG_DRIFT')
        candidateWriter='cross-domain-writer';materialContributors=@('material-designer')
    }
    Write-Utf8 $criticalReviewPackagePath ($criticalReviewPackage|ConvertTo-Json -Depth 20)
    $criticalReviewArgs=@('-PackagePath',$criticalReviewPackagePath,'-ObservedActor','reviewer-fixture','-ObservedTaskId','FIXTURE-REVIEW-001','-ObservedOwner','owner-fixture','-ObservedAction','REVIEW_EXECUTE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $criticalReviewDirect=Invoke-Ps $checker $criticalReviewArgs $repoLocal
    Assert-True ($criticalReviewDirect.Code -eq 0) 'authorization-domain-owner-direct-review-package-with-cross-domain-writer-pass'
    foreach($disqualified in @('owner-fixture','cross-domain-writer','material-designer')){
        $badReview=$criticalReviewPackage|ConvertTo-Json -Depth 20|ConvertFrom-Json
        $badReview.grantee=$disqualified
        Write-Utf8 $criticalReviewPackagePath ($badReview|ConvertTo-Json -Depth 20)
        $badReviewArgs=@('-PackagePath',$criticalReviewPackagePath,'-ObservedActor',$disqualified,'-ObservedTaskId','FIXTURE-REVIEW-001','-ObservedOwner','owner-fixture','-ObservedAction','REVIEW_EXECUTE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
        $badReviewRun=Invoke-Ps $checker $badReviewArgs $repoLocal
        Assert-True ($badReviewRun.Code -ne 0 -and $badReviewRun.Text.Contains('CRITICAL_REVIEW_NOT_INDEPENDENT')) ('authorization-critical-review-rejects-'+$disqualified)
    }
    Write-Utf8 $criticalReviewPackagePath ($criticalReviewPackage|ConvertTo-Json -Depth 20)

    $repoLocalSchema1Args = @('-PackagePath',$repoLocalSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $gitEnvironmentPackagePath=Join-Path $repoLocal '.ai-workspace/git-environment-auth.json'
    $gitEnvironmentPackage=Get-Content -Raw -Encoding utf8 -LiteralPath $repoLocalSchema1Package|ConvertFrom-Json
    $gitEnvironmentPackage.actions=@('GIT_STAGE');$gitEnvironmentPackage.delegatedGitCloser=$true
    Write-Utf8 $gitEnvironmentPackagePath ($gitEnvironmentPackage|ConvertTo-Json -Depth 20)
    $gitEnvironmentArgs=@('-PackagePath',$gitEnvironmentPackagePath,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','GIT_STAGE','-ObservedPath',$repoLocalObject,'-ObservedIdentity',($repoLocalObject+'='+$repoLocalObjectIdentity))
    $gitEnvironmentBaseline=Invoke-Ps $checker $gitEnvironmentArgs $repoLocal
    Assert-True ($gitEnvironmentBaseline.Code-eq0) 'authorization-schema1-git-environment-fixture-valid-without-override'
    $gitOverrideValues = [ordered]@{GIT_DIR=(Join-Path $repoLocal '.git');GIT_WORK_TREE=$repoLocal;GIT_COMMON_DIR=(Join-Path $repoLocal '.git')}
    foreach ($gitEnvironmentName in $gitOverrideValues.Keys) {
        $nonGitEnvironmentOverride=Invoke-PsWithProcessEnvironment $checker $repoLocalSchema1Args $repoLocal @{ $gitEnvironmentName=$gitOverrideValues[$gitEnvironmentName] }
        Assert-True ($nonGitEnvironmentOverride.Code-eq0) ('authorization-schema1-non-git-action-ignores-process-'+$gitEnvironmentName.ToLowerInvariant())
        $schema1EnvironmentOverride = Invoke-PsWithProcessEnvironment $checker $gitEnvironmentArgs $repoLocal @{ $gitEnvironmentName=$gitOverrideValues[$gitEnvironmentName] }
        Assert-True ($schema1EnvironmentOverride.Code -ne 0 -and $schema1EnvironmentOverride.Text.Contains('GIT_ENVIRONMENT_OVERRIDE_'+$gitEnvironmentName)) ('authorization-schema1-rejects-process-'+$gitEnvironmentName.ToLowerInvariant())
    }

    $repoLocalConfigRaw = Get-Content -LiteralPath $repoLocalConfigPath -Raw -Encoding utf8
    $driftedSchema1Config=$repoLocalConfigRaw|ConvertFrom-Json
    $driftedSchema1Config.routineExcludedPaths=@('private/secret.txt','private/additional.txt')
    Write-Utf8 $repoLocalConfigPath ($driftedSchema1Config|ConvertTo-Json -Depth 20)
    $repoLocalSchema1ConfigDrift=Invoke-Ps $checker $repoLocalSchema1Args $repoLocal
    Write-Utf8 $repoLocalConfigPath $repoLocalConfigRaw
    Assert-True ($repoLocalSchema1ConfigDrift.Code-ne0-and$repoLocalSchema1ConfigDrift.Text.Contains('PROJECT_CONFIG_DRIFT')) 'authorization-schema1-binds-project-config-identity'
    $invalidSchema1Configs = @(
        [pscustomobject]@{Name='wrong-framework-version';Mutate={param($c) $c.frameworkVersion='1.6.1'};Reason='PROJECT_CONFIG_VALUES'},
        [pscustomobject]@{Name='non-string-exclusion';Mutate={param($c) $c.routineExcludedPaths=@(42)};Reason='FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CONFIG'},
        [pscustomobject]@{Name='unsafe-exclusion';Mutate={param($c) $c.routineExcludedPaths=@('../escape')};Reason='ROUTINE_PATH_COMPONENT'},
        [pscustomobject]@{Name='duplicate-exclusion';Mutate={param($c) $c.routineExcludedPaths=@('private/secret.txt','PRIVATE/SECRET.TXT')};Reason='ROUTINE_EXCLUSION_DUPLICATE'},
        [pscustomobject]@{Name='unknown-capability';Mutate={param($c) $c.frameworkCapabilities=[pscustomobject]@{UNKNOWN=[pscustomobject]@{}}};Reason='FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CONFIG'},
        [pscustomobject]@{Name='malformed-knowledge-capability';Mutate={param($c) $c.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true}}};Reason='FORMAT_CURRENT_VALIDATION_FAILED|PROJECT_CONFIG'}
    )
    foreach ($schema1ConfigCase in $invalidSchema1Configs) {
        $invalidConfig = $repoLocalConfigRaw | ConvertFrom-Json
        $null = & ([scriptblock]$schema1ConfigCase.Mutate) $invalidConfig
        Write-Utf8 $repoLocalConfigPath ($invalidConfig | ConvertTo-Json -Depth 20)
        Set-PackageProjectConfigIdentity $repoLocalSchema1Package (Get-Identity $repoLocalConfigPath)
        $invalidSchema1 = Invoke-Ps $checker $repoLocalSchema1Args $repoLocal
        $expectedSchema1Failure='FAIL|SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3|'+[string]$schema1ConfigCase.Reason
        Write-Output ('OBSERVE|schema1-invalid-'+[string]$schema1ConfigCase.Name+'|code='+$invalidSchema1.Code+'|text='+$invalidSchema1.Text.Trim())
        if ($invalidSchema1.Code -ne 2 -or $invalidSchema1.Text.Trim() -cne $expectedSchema1Failure) { Write-Output ('DIAG|schema1-invalid-'+[string]$schema1ConfigCase.Name+'|'+$invalidSchema1.Code+'|'+$invalidSchema1.Text) }
        Assert-True ($invalidSchema1.Code -eq 2 -and $invalidSchema1.Text.Trim() -ceq $expectedSchema1Failure) ('authorization-schema1-rejects-'+[string]$schema1ConfigCase.Name)
    }
    Write-Utf8 $repoLocalConfigPath $repoLocalConfigRaw
    Set-PackageProjectConfigIdentity $repoLocalSchema1Package $repoLocalIdentity

    $missingConfigPath = $repoLocalConfigPath + '.missing'
    [IO.File]::Move($repoLocalConfigPath,$missingConfigPath)
    try { $missingSchema1Config = Invoke-Ps $checker $repoLocalSchema1Args $repoLocal }
    finally { [IO.File]::Move($missingConfigPath,$repoLocalConfigPath) }
    Assert-True ($missingSchema1Config.Code -ne 0 -and $missingSchema1Config.Text.Contains('PROJECT_CONFIG_MISSING')) 'authorization-schema1-rejects-missing-project-config'

Test-IntegrationSchema1ControlPlane
    $correctionChecker=Join-Path $candidateRoot 'scripts\check-project-corrections.ps1'
$correctionFrameworkRoot=Join-Path $temp 'correction-framework-fixture';$null=New-IntegrationRuntimeFixture $correctionFrameworkRoot
    $pilotVersionRoot=Join-Path $correctionFrameworkRoot 'framework\versions\2.0.0';$pilotManifestPath=Join-Path $pilotVersionRoot 'RELEASE_MANIFEST.json';$pilotFacts=Approve-CandidateReleaseFixture $pilotVersionRoot
    $pilotProject=Join-Path $temp 'local-candidate-recovery-fixture';New-GitRepo $pilotProject;New-Item -ItemType Directory -Path (Join-Path $pilotProject '.ai-workspace\tasks\active') -Force|Out-Null
    $pilotConfig=[ordered]@{schemaVersion=6;id='local-candidate-recovery-fixture';displayName='Local Candidate Recovery Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[ordered]@{};sourceBindings=@();processPolicy=[ordered]@{schemaVersion=2;locator='.ai-workspace/process-policy.json'}};$pilotConfigPath=Join-Path $pilotProject '.ai-workspace\project.json';Write-CurrentFixtureObject PROJECT_CONFIG $pilotConfigPath $pilotConfig
    Write-Utf8 (Join-Path $pilotProject '.ai-workspace\controller.json') (([ordered]@{schemaVersion=1;projectId='local-candidate-recovery-fixture';controllerId='pilot-controller';controllerEpoch=1;state='CURRENT'})|ConvertTo-Json -Depth 10)
    Write-Utf8 (Join-Path $pilotProject '.ai-workspace\corrections.json') (([ordered]@{schemaVersion=3;contractVersion='2.0.0';projectId='local-candidate-recovery-fixture';corrections=@()})|ConvertTo-Json -Depth 10)
    Write-CurrentFixtureObject PROCESS_POLICY (Join-Path $pilotProject '.ai-workspace\process-policy.json') (([ordered]@{schemaVersion=1;contractVersion='2.0.0';projectId='local-candidate-recovery-fixture';selectedRulePackBytes=32768;rules=@()}))
    Write-Utf8 (Join-Path $pilotProject '.ai-workspace\BOOTSTRAP.md') "<!-- FRAMEWORK-MANAGED:BEGIN -->`nProject ID=``local-candidate-recovery-fixture``；repo-local control plane=``.ai-workspace/``；pinned Framework=``2.0.0``。`n<!-- FRAMEWORK-MANAGED:END -->`n<!-- PROJECT-CUSTOM:BEGIN -->`n此 legacy region 当前没有 permanent project process rule。structured rules 位于 ``.ai-workspace/process-policy.json``。`n<!-- PROJECT-CUSTOM:END -->`n"
    $pilotTaskPath=Join-Path $pilotProject '.ai-workspace\tasks\active\PILOT-RECOVERY-001.md';Write-Utf8 $pilotTaskPath "# PILOT-RECOVERY-001 - candidate recovery fixture`n`n- Task schema: 2.0.0`n- Owner: pilot-controller`n- Work route: actor=pilot-controller; role=CONTROLLER; phase=RECOVER`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[]; actual_paths=[]`n"
    $pilotResolver=Join-Path $pilotVersionRoot 'scripts\resolve-process-requirements.ps1';$pilotInputPath=Join-Path $temp 'local-candidate-recovery-discover.json'
    $pilotIntent=New-CurrentFixtureIntent ([ordered]@{schemaVersion=1;objective='Recover the already admitted local candidate pilot';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('recovery');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'})
    $pilotInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$pilotProject;frameworkRoot=$correctionFrameworkRoot;taskPath=$pilotTaskPath;expectedProjectConfigIdentity=(Get-Identity $pilotConfigPath);expectedCorrectionsIdentity=(Get-Identity (Join-Path $pilotProject '.ai-workspace\corrections.json'));expectedTaskIdentity=(Get-Identity $pilotTaskPath);observedActor='pilot-controller';capabilities=@();exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$pilotIntent;evaluationOnly=$false};Write-Utf8 $pilotInputPath ($pilotInput|ConvertTo-Json -Depth 30)
    $pilotMissingState=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotMissingState.Code-ne0-and$pilotMissingState.Text.Contains('LOCAL_CANDIDATE_PILOT_STATE_MISSING')) 'local-candidate-recovery-rejects-unproven-pilot-mode'
    $pilotStateRoot=Join-Path $pilotProject '.ai-workspace\upgrade-recovery\2.0.0';New-Item -ItemType Directory -Path $pilotStateRoot -Force|Out-Null;$pilotTaskUpgradeIdentity=Get-Identity $pilotTaskPath;$pilotManifestIdentity=Get-Identity $pilotManifestPath
    $pilotState=[ordered]@{schemaVersion=2;projectId='local-candidate-recovery-fixture';fromVersion='1.15.1';toVersion='2.0.0';targetReleaseCanonical=$pilotFacts.Canonical;targetReleaseManifestIdentity=$pilotManifestIdentity;actor='pilot-controller';taskId='PILOT-RECOVERY-001';taskOwner='pilot-controller';taskRelative='.ai-workspace/tasks/active/PILOT-RECOVERY-001.md';authorizationIdentity=('1|'+('A'*64));objects=@([ordered]@{relative='.ai-workspace/project.json';oldIdentity='MISSING';newIdentity=(Get-Identity $pilotConfigPath)},[ordered]@{relative='.ai-workspace/tasks/active/PILOT-RECOVERY-001.md';oldIdentity='MISSING';newIdentity=$pilotTaskUpgradeIdentity})};$pilotStatePath=Join-Path $pilotStateRoot 'state.json';Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    Write-Utf8 $pilotTaskPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $pilotTaskPath)+"- Pilot progress: task changed after the one-time upgrade transaction.`n");$pilotInput.expectedTaskIdentity=Get-Identity $pilotTaskPath;Write-Utf8 $pilotInputPath ($pilotInput|ConvertTo-Json -Depth 20)
    $pilotRecovery=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');if($pilotRecovery.Code-ne0){throw ('ASSERT_FAIL|local-candidate-recovery-reuses-admission-without-task-postimage-lock|'+$pilotRecovery.Code+'|'+$pilotRecovery.Text)};$pilotRecoveryResult=$pilotRecovery.Output[-1]|ConvertFrom-Json;$pilotReceipt=$pilotRecoveryResult.compactReceipt
    Assert-True ($pilotRecovery.Code-eq0-and[string]$pilotReceipt.status-ceq'PASS'-and[string]$pilotReceipt.sourceBindings.candidatePilotStateIdentity-ceq(Get-Identity $pilotStatePath)-and@($pilotReceipt.evidence.ceilings)-contains'LOCAL_CANDIDATE_PILOT') 'local-candidate-recovery-reuses-admission-without-task-postimage-lock'
    $pilotState.schemaVersion=3;$pilotState['projectionMode']='LOCAL_CANDIDATE_MANAGED';$pilotState['projectionObjects']=@([ordered]@{relative='.ai-workspace/project.json';identity=(Get-Identity $pilotConfigPath)},[ordered]@{relative='.ai-workspace/process-policy.json';identity=(Get-Identity (Join-Path $pilotProject '.ai-workspace\process-policy.json'))},[ordered]@{relative='.ai-workspace/tasks/active/PILOT-RECOVERY-001.md';identity=$pilotTaskUpgradeIdentity});Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    $pilotSchema3Recovery=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');if($pilotSchema3Recovery.Code-ne0){throw ('ASSERT_FAIL|local-candidate-schema3-managed-projection-recovery|'+$pilotSchema3Recovery.Code+'|'+$pilotSchema3Recovery.Text)};$pilotSchema3Result=$pilotSchema3Recovery.Output[-1]|ConvertFrom-Json;$pilotReceipt=$pilotSchema3Result.compactReceipt
    Assert-True ($pilotSchema3Recovery.Code-eq0-and[string]$pilotReceipt.sourceBindings.candidatePilotStateIdentity-ceq(Get-Identity $pilotStatePath)) 'local-candidate-schema3-managed-projection-recovery-allows-current-task-progress'
    $pilotPolicyPath=Join-Path $pilotProject '.ai-workspace\process-policy.json';$pilotPolicyBytes=[IO.File]::ReadAllBytes($pilotPolicyPath);Write-Utf8 $pilotPolicyPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $pilotPolicyPath)+"`n")
    $pilotProjectionChange=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');[IO.File]::WriteAllBytes($pilotPolicyPath,$pilotPolicyBytes)
    Assert-True ($pilotProjectionChange.Code-eq0-and$pilotProjectionChange.Text.Contains('PROCESS_REQUIREMENTS_DISCOVER_RESULT')) 'local-candidate-schema3-accepts-valid-current-policy-by-current-binding'
    $pilotProjectionObjects=@($pilotState.projectionObjects);$pilotState.projectionObjects=@($pilotProjectionObjects|Where-Object{[string]$_.relative-cne'.ai-workspace/project.json'});Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    $pilotProjectionMissing=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson');$pilotState.projectionObjects=$pilotProjectionObjects;Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    Assert-True ($pilotProjectionMissing.Code-ne0-and$pilotProjectionMissing.Text.Contains('LOCAL_CANDIDATE_PILOT_PROJECTION_OBJECT_MISSING|.ai-workspace/project.json')) 'local-candidate-schema3-requires-original-object-projection-coverage'

    # schema4: 项目规则可以演进；安装事务原文和框架管理部分不随之改变。
    $pilotLegacyState=$pilotState|ConvertTo-Json -Depth 30
    $pilotBootstrapPath=Join-Path $pilotProject '.ai-workspace/BOOTSTRAP.md'
    $pilotBootstrapOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $pilotBootstrapPath
    $pilotManagedText=[regex]::Replace($pilotBootstrapOriginal,'(?s)(<!-- PROJECT-CUSTOM:BEGIN -->).*?(<!-- PROJECT-CUSTOM:END -->)','$1$2')
    $pilotManagedPath=Join-Path $temp 'pilot-bootstrap-managed.txt';[IO.File]::WriteAllText($pilotManagedPath,$pilotManagedText,[Text.UTF8Encoding]::new($false))
    $pilotState.schemaVersion=4;$pilotState['transactionComplete']=$true
    $pilotState.projectionObjects=@($pilotState.projectionObjects|Where-Object{[string]$_.relative-cne$pilotState.taskRelative})+@([ordered]@{relative='.ai-workspace/BOOTSTRAP.md';identity=(Get-Identity $pilotBootstrapPath);managedIdentity=(Get-Identity $pilotManagedPath)})+@($pilotState.projectionObjects|Where-Object{[string]$_.relative-ceq$pilotState.taskRelative})
    Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 30);$pilotSchema4Identity=Get-Identity $pilotStatePath
    $pilotState.transactionComplete=$false;Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 30)
    $pilotIncomplete=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotIncomplete.Code-ne0-and$pilotIncomplete.Text.Contains('LOCAL_CANDIDATE_PILOT_TRANSACTION_INCOMPLETE')) 'local-candidate-schema4-rejects-task-last-transaction-not-complete'
    $pilotState.transactionComplete=$true;Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 30)
    $pilotBeforeEvolution=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotBeforeEvolution.Code-eq0) 'local-candidate-schema4-admission-before-rule-evolution'
    $pilotCurrentReceipt=($pilotBeforeEvolution.Output[-1]|ConvertFrom-Json).compactReceipt
    $pilotCurrentReceiptPath=Join-Path $temp 'pilot-before-policy-evolution-receipt.json';Write-Utf8 $pilotCurrentReceiptPath ($pilotCurrentReceipt|ConvertTo-Json -Depth 30)
    $pilotPolicy=Get-Content -Raw -Encoding utf8 -LiteralPath $pilotPolicyPath|ConvertFrom-Json
    $pilotPolicy.rules=@([ordered]@{ruleId='PILOT_CURRENT_RULE';requirementReason='项目规则从旧区域进入唯一结构化载体';effectiveRule='项目试点交付必须保留当前结论。';selectors=[ordered]@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();decisionLocator='fixture:accepted-policy-migration'})
    Write-Utf8 $pilotPolicyPath ($pilotPolicy|ConvertTo-Json -Depth 30)
    $pilotClearedRegion='$1'+"`n"+'No permanent project process rule is active in this legacy region. Structured rules belong to `.ai-workspace/process-policy.json`.'+"`n"+'$2'
    Write-Utf8 $pilotBootstrapPath ([regex]::Replace($pilotBootstrapOriginal,'(?s)(<!-- PROJECT-CUSTOM:BEGIN -->).*?(<!-- PROJECT-CUSTOM:END -->)',$pilotClearedRegion))
    $pilotAfterEvolution=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    if($pilotAfterEvolution.Code-ne0){throw ('ASSERT_FAIL|schema4-rule-evolution|'+$pilotAfterEvolution.Text)}
    $pilotAfterResult=$pilotAfterEvolution.Output[-1]|ConvertFrom-Json
    Assert-True ($pilotAfterEvolution.Code-eq0-and@($pilotAfterResult.selectedRuleBlocks|Where-Object{[string]$_.requirementId-ceq'project:local-candidate-recovery-fixture:PILOT_CURRENT_RULE'}).Count-eq1-and@($pilotAfterResult.selectedRuleBlocks|Where-Object{[string]$_.requirementId-ceq'project-custom:local-candidate-recovery-fixture'}).Count-eq0-and(Get-Identity $pilotStatePath)-ceq$pilotSchema4Identity) 'local-candidate-schema4-project-custom-to-policy-migration-keeps-admission-and-uses-current-rule'
    $pilotStaleBoundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$pilotCurrentReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $pilotCurrentReceiptPath);objective=$pilotInput.intentEnvelope.objective;actionKind='NONE';resultKind='PLAN';exactPaths=@();authorizationIdentity='NOT_REQUIRED';preparationReceipts=@($pilotCurrentReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    $pilotStaleBoundaryPath=Join-Path $temp 'pilot-stale-policy-admit.json';Write-Utf8 $pilotStaleBoundaryPath ($pilotStaleBoundary|ConvertTo-Json -Depth 30)
    $pilotStalePolicy=Invoke-Ps $pilotResolver @('-InputPath',$pilotStaleBoundaryPath,'-AsJson')
    Assert-True ($pilotStalePolicy.Code-ne0-and$pilotStalePolicy.Text.Contains('DISCOVER_SOURCE_DRIFT|policyIdentity')) 'local-candidate-schema4-rule-evolution-invalidates-old-receipt'
    $pilotBudgetLegacy=$pilotPolicy|ConvertTo-Json -Depth 30|ConvertFrom-Json;$pilotBudgetLegacy.schemaVersion=1;$pilotBudgetLegacy|Add-Member selectedRulePackBytes 65536
    $pilotBudgetProjection=Write-CurrentFixtureObject PROCESS_POLICY $pilotPolicyPath $pilotBudgetLegacy -PassThru
    $pilotBudgetEvolution=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotBudgetEvolution.Code-eq0-and[int]($pilotBudgetEvolution.Output[-1]|ConvertFrom-Json).compactReceipt.pack.ceilingBytes-eq0-and$pilotBudgetProjection.OriginalValue.selectedRulePackBytes-eq65536-and$pilotBudgetProjection.Value.PSObject.Properties.Name-cnotcontains'selectedRulePackBytes'-and(Get-Identity $pilotStatePath)-ceq$pilotSchema4Identity) 'local-candidate-schema4-legacy-budget-adapter-keeps-content-without-installation-quota'
    # 已完成升级任务可归档；新任务恢复与边界不再读取原 active 路径。
    $archivedPilotTask=Join-Path $pilotProject '.ai-workspace/tasks/archive/PILOT-RECOVERY-001.md'
    New-Item -ItemType Directory -Path (Split-Path -Parent $archivedPilotTask) -Force|Out-Null
    Move-Item -LiteralPath $pilotTaskPath -Destination $archivedPilotTask
    $businessTaskPath=Join-Path $pilotProject '.ai-workspace/tasks/active/PILOT-BUSINESS-001.md'
    Write-Utf8 $businessTaskPath ((Get-Content -Raw -Encoding utf8 -LiteralPath $archivedPilotTask).Replace('PILOT-RECOVERY-001','PILOT-BUSINESS-001'))
    $pilotInput.taskPath=$businessTaskPath;$pilotInput.expectedTaskIdentity=Get-Identity $businessTaskPath;Write-Utf8 $pilotInputPath ($pilotInput|ConvertTo-Json -Depth 30)
    $archivedRecovery=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    if($archivedRecovery.Code-ne0){throw ('ASSERT_FAIL|archived-pilot-task-recovery|'+$archivedRecovery.Text)}
    $businessReceipt=($archivedRecovery.Output[-1]|ConvertFrom-Json).compactReceipt
    Assert-True ([string]$businessReceipt.binding.taskId-ceq'PILOT-BUSINESS-001'-and(Get-Identity $pilotStatePath)-ceq$pilotSchema4Identity-and-not(Test-Path -LiteralPath $pilotTaskPath)) 'local-candidate-schema4-archived-upgrade-task-allows-new-task-discover'
    $businessReceiptPath=Join-Path $temp 'pilot-business-receipt.json';Write-Utf8 $businessReceiptPath ($businessReceipt|ConvertTo-Json -Depth 30)
    $businessBoundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$businessReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $businessReceiptPath);objective=$pilotInput.intentEnvelope.objective;actionKind='NONE';resultKind='PLAN';exactPaths=@();authorizationIdentity='NOT_REQUIRED';preparationReceipts=@($businessReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'}
    $businessBoundaryPath=Join-Path $temp 'pilot-business-boundary.json';Write-Utf8 $businessBoundaryPath ($businessBoundary|ConvertTo-Json -Depth 30)
    $businessAdmit=Invoke-Ps $pilotResolver @('-InputPath',$businessBoundaryPath,'-AsJson')
    Assert-True ($businessAdmit.Code-eq0) 'local-candidate-schema4-archived-upgrade-task-allows-new-task-admit'
    $businessBoundary.mode='FINALIZE_OUTPUT';$businessBoundary.resultReceipts=@($businessReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique);$businessBoundary.deliveryReceipts=@('USER_RESPONSE_BOUND_CURRENT_TASK');Write-Utf8 $businessBoundaryPath ($businessBoundary|ConvertTo-Json -Depth 30)
    $businessFinalize=Invoke-Ps $pilotResolver @('-InputPath',$businessBoundaryPath,'-AsJson')
    Assert-True ($businessFinalize.Code-eq0) 'local-candidate-schema4-archived-upgrade-task-allows-new-task-finalize'
    $pilotState.transactionComplete=$false;Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 30)
    $missingHistoricalTaskIncomplete=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($missingHistoricalTaskIncomplete.Code-ne0-and$missingHistoricalTaskIncomplete.Text.Contains('LOCAL_CANDIDATE_PILOT_TRANSACTION_INCOMPLETE')) 'local-candidate-schema4-missing-historical-task-does-not-prove-completion'
    $pilotState.transactionComplete=$true;Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 30)
    Move-Item -LiteralPath $archivedPilotTask -Destination $pilotTaskPath;Remove-Item -LiteralPath $businessTaskPath
    $pilotInput.taskPath=$pilotTaskPath;$pilotInput.expectedTaskIdentity=Get-Identity $pilotTaskPath;Write-Utf8 $pilotInputPath ($pilotInput|ConvertTo-Json -Depth 30)
    $pilotMigratedBootstrap=Get-Content -Raw -Encoding utf8 -LiteralPath $pilotBootstrapPath
    Write-Utf8 $pilotBootstrapPath ($pilotMigratedBootstrap+"框架管理区说明更新。`n")
    $pilotManagedEvolution=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotManagedEvolution.Code-eq0-and(Get-Identity $pilotStatePath)-ceq$pilotSchema4Identity) 'local-candidate-schema4-valid-current-bootstrap-prose-not-locked-by-installation'
    $pilotWrongPinBootstrap=$pilotMigratedBootstrap.Replace('pinned Framework=`2.0.0`','pinned Framework=`1.15.1`')
    Assert-True ($pilotWrongPinBootstrap-cne$pilotMigratedBootstrap) 'local-candidate-schema4-wrong-pin-fixture-changes-current-binding'
    Write-Utf8 $pilotBootstrapPath $pilotWrongPinBootstrap
    $pilotWrongPin=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotWrongPin.Code-ne0-and$pilotWrongPin.Text.Contains('LOCAL_CANDIDATE_BOOTSTRAP_CURRENT_BINDING')) 'local-candidate-schema4-wrong-current-pin-rejected'
    Write-Utf8 $pilotBootstrapPath $pilotMigratedBootstrap
    $pilotPolicy|Add-Member selectedRulePackBytes 0;Write-Utf8 $pilotPolicyPath ($pilotPolicy|ConvertTo-Json -Depth 30)
    $pilotInvalidPolicy=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotInvalidPolicy.Code-ne0-and-not$pilotInvalidPolicy.Text.Contains('LOCAL_CANDIDATE_PILOT_PROJECTION_DRIFT')) 'local-candidate-schema4-invalid-current-policy-rejected-by-current-policy-contract'
    $pilotPolicy.PSObject.Properties.Remove('selectedRulePackBytes')
    $pilotDuplicateRule=$pilotPolicy.rules[0]|ConvertTo-Json -Depth 30|ConvertFrom-Json
    $pilotDuplicateRule.ruleId='PILOT_DUPLICATE_RULE'
    $pilotPolicy.rules=@($pilotPolicy.rules)+@($pilotDuplicateRule);Write-Utf8 $pilotPolicyPath ($pilotPolicy|ConvertTo-Json -Depth 30)
    $pilotDuplicatePolicy=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotDuplicatePolicy.Code-ne0-and$pilotDuplicatePolicy.Text.Contains('CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE')) 'local-candidate-schema4-duplicate-current-rule-rejected'
    [IO.File]::WriteAllBytes($pilotPolicyPath,$pilotPolicyBytes);Write-Utf8 $pilotBootstrapPath $pilotBootstrapOriginal
    $pilotState=$pilotLegacyState|ConvertFrom-Json;Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 30)
    $pilotReceiptPath=Join-Path $temp 'local-candidate-recovery-receipt.json';Write-Utf8 $pilotReceiptPath ($pilotReceipt|ConvertTo-Json -Depth 30);$pilotState.authorizationIdentity='1|'+('B'*64);Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    $pilotBoundary=[ordered]@{schemaVersion=1;mode='ADMIT_ACTION';discoverReceiptPath=$pilotReceiptPath;expectedDiscoverReceiptIdentity=(Get-Identity $pilotReceiptPath);objective=$pilotInput.intentEnvelope.objective;actionKind='NONE';resultKind='PLAN';exactPaths=@();authorizationIdentity='NOT_REQUIRED';preparationReceipts=@($pilotReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='NOT_APPLICABLE'};$pilotBoundaryPath=Join-Path $temp 'local-candidate-recovery-admit.json';Write-Utf8 $pilotBoundaryPath ($pilotBoundary|ConvertTo-Json -Depth 20)
    $pilotStateDrift=Invoke-Ps $pilotResolver @('-InputPath',$pilotBoundaryPath,'-AsJson')
    Assert-True ($pilotStateDrift.Code-ne0-and$pilotStateDrift.Text.Contains('DISCOVER_SOURCE_DRIFT|candidatePilotStateIdentity')) 'local-candidate-recovery-state-is-bound-across-action-boundary'
    $pilotState.authorizationIdentity='1|'+('A'*64);Write-Utf8 $pilotStatePath ($pilotState|ConvertTo-Json -Depth 20)
    $pilotCorePath=Join-Path $pilotVersionRoot 'RECOVERY_CORE.md'
    $pilotCoreOriginal=Get-Content -Raw -Encoding utf8 -LiteralPath $pilotCorePath
    $pilotCoreIdentity=Get-Identity $pilotCorePath
    $pilotPayloadBaseline=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotPayloadBaseline.Code-eq0) 'local-candidate-recovery-payload-drift-valid-baseline'
    try {
        Write-Utf8 $pilotCorePath ($pilotCoreOriginal+"`n")
        $pilotPayloadDrift=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
        $pilotPayloadDriftReason=($pilotPayloadDrift.Output[-1]|ConvertFrom-Json).reason
        Write-Output ('OBSERVE|pilot-payload-drift|code='+$pilotPayloadDrift.Code+'|reason='+$pilotPayloadDriftReason)
        # The qualified reader rejects the changed payload before the composer comparison.
        Assert-True ($pilotPayloadDrift.Code-eq2-and$pilotPayloadDriftReason-ceq'RELEASE_VALIDATION_STATE_UNSUPPORTED') 'local-candidate-recovery-rejects-candidate-payload-drift'
    } finally {
        [IO.File]::WriteAllText($pilotCorePath,$pilotCoreOriginal,[Text.UTF8Encoding]::new($false))
    }
    Assert-True ((Get-Identity $pilotCorePath)-ceq$pilotCoreIdentity) 'local-candidate-recovery-payload-bytes-restored'
    $pilotPayloadRestored=Invoke-Ps $pilotResolver @('-InputPath',$pilotInputPath,'-AsJson')
    Assert-True ($pilotPayloadRestored.Code-eq0) 'local-candidate-recovery-payload-drift-restored-baseline'
}
} finally { if($integrationContext){Close-IntegrationContext $integrationContext} }
Write-Output ('RESULT|'+(Get-IntegrationCheckCount)+'/'+(Get-IntegrationCheckCount)+' passed|scope=Framework-2.0.0-authorization|')
