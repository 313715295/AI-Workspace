[CmdletBinding()]
param([ValidateSet('All','Frontdoor','NativeOutput','GitReception','Bootstrap','QualityAssurance','BodyDelivery','RuleLoadingRebind')][string]$Case='All')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
# Share the same bounded original registration/source-maintenance recipe with
# the repo-local case. No whole-version integration view or full suite is run.
if($Case-ceq'QualityAssurance'){
 Import-Module (Join-Path $PSScriptRoot 'TestHarness.psm1')
 $quality=Invoke-AiwTestProcess ([Environment]::ProcessPath) @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'result-acceptance-tests.ps1'),'-Group','QualityMaintenance','-KeepFixture') -WorkingDirectory (Get-Location).Path -GroupId 'maintenance-quality-frontdoor'
 $quality.Output|Write-Output
 if($quality.Code-ne0){throw ('MAINTENANCE_QUALITY_NATIVE|exit='+$quality.Code)}
 Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-quality-original-registration-and-root-frontdoors|synthetic-qualification-only'
 return
}
Import-Module (Join-Path $PSScriptRoot 'IntegrationFixture.psm1') -Force
$integrationContext=$null
try {
 $integrationContext=New-IntegrationContext (Join-Path $PSScriptRoot '..') 'maintenance'
 foreach($key in $integrationContext.Keys){if($key-ceq'script:testJunctions'){$script:testJunctions=$integrationContext[$key]}else{Set-Variable -Name $key -Value $integrationContext[$key]}}
function Test-IntegrationMaintenanceBootstrap {
 $installedLoader=Join-Path $installedFramework 'scripts/resolve-load-plan.ps1'
 $fullColdLoad=Invoke-Ps $installedLoader @('-Role','CONTROLLER','-Profile','CRITICAL','-Phase','RECOVER','-HostName','CODEX','-Topology','FRAMEWORK_MAINTENANCE_SIBLING')
 $renderedBootstrap=Get-Content -LiteralPath (Join-Path $controlPlane 'BOOTSTRAP.md') -Raw -Encoding utf8
 # The entry delegates state and recovery mechanics to their owning contracts.
 # Verify CURRENT against the real resolver rather than an obsolete prose token.
 $currentTopology=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
 $currentFacts=$false
 if($currentTopology.Code-eq0){$reply=$currentTopology.Output[-1]|ConvertFrom-Json -Depth 100;$currentFacts=$reply.controllerState-ceq'CURRENT'-and$reply.runtimeRoot-ceq$fixedRuntime-and$reply.targetRoot-ceq$target}
 $required=@('当前任务、责任和权限只取CONTROL','读取project、controller、corrections、policy及人类约定','唯一固定runtimeRoot','resolve-framework-maintenance-target.ps1','固定runtime提供规则与工具，TARGET只承载开发源码','先读TARGET/README及适用framework/FRAMEWORK_RELEASE','不要求TARGET根AGENTS/CLAUDE','不从开发HEAD补运行模块','绑定当前Owner、真实actor/route、profile、selected repository','TOOL_CONTRACT唯一IntentEnvelope段','resolve-framework-maintenance-process-requirements.ps1','当前全部必要完整正文','CONTROL与TARGET写入分别绑定精确repository包','及相应ADMIT','正式交付按当前真实结果与消费者FINALIZE','Review、Git、push、external及运行包采用分别成立','具体合同取固定TOOL_CONTRACT/根PROJECT_ADOPTION','不创建第二控制面、不授予移动仓库或切换运行包权限','SOURCE写入由固定runtime收口','源码变化本身不改本项目pin')
 $missing=@($required|Where-Object{-not$renderedBootstrap.Contains($_)})
 if($missing.Count){Write-Output ('DIAG|maintenance-bootstrap-current-contract|'+($missing-join';'))}
 Assert-True ($fullColdLoad.Code-ne0-and$currentFacts-and$missing.Count-eq0-and-not$renderedBootstrap.Contains('AllowLegacyTargetControlPlane')-and-not$renderedBootstrap.Contains('显式读取 `<TARGET>/AGENTS.md`')) 'maintenance-bootstrap-root-owned-full-cold-route'
}
function Test-IntegrationMaintenanceFrontdoor {
 $targetControl=$targetControlFixturePath
 Assert-IntegrationMaintenanceBaseline $maintenanceFixture 'before-frontdoor'
 $controlledTreeBefore=Get-PhysicalFixtureTree $pair
 foreach($nonGitCase in @(@{Name='control';Root=$control;Reason='CONTROL_ROOT_GIT_TOP_UNAVAILABLE';Case='maintenance-resolver-control-non-git-rejected'},@{Name='target';Root=$target;Reason='TARGET_ROOT_GIT_TOP_UNAVAILABLE';Case='maintenance-resolver-target-non-git-rejected'})){
  $gitPath=Get-PrivateFixtureCleanupPath (Join-Path $nonGitCase.Root '.git') $nonGitCase.Root '^\.git$' 'NON_GIT_SOURCE'
  $gitHold=Get-PrivateFixtureCleanupPath (Join-Path $nonGitCase.Root '.git.fixture-hold') $nonGitCase.Root '^\.git\.fixture-hold$' 'NON_GIT_HOLD'
  $gitTree=Get-PhysicalFixtureTree $gitPath
  Move-Item -LiteralPath $gitPath -Destination $gitHold
  try {
   $invalidTree=Get-PhysicalFixtureTree $pair
   $nonGitRun=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
   $reason=Get-IntegrationResolverFailure $nonGitRun $nonGitCase.Name
   Assert-True ($reason-ceq$nonGitCase.Reason-and(Get-PhysicalFixtureTree $pair)-ceq$invalidTree) $nonGitCase.Case
  } finally {Move-Item -LiteralPath $gitHold -Destination $gitPath;if((Get-PhysicalFixtureTree $gitPath)-cne$gitTree){throw 'INTEGRATION_NON_GIT_RESTORE_DRIFT'}}
  Assert-IntegrationMaintenanceBaseline $maintenanceFixture ('after-'+$nonGitCase.Name+'-non-git')
 }
    $controlPlane=Get-PrivateFixtureCleanupPath $controlPlane $control '^\.ai-workspace$' 'CONTROL_PLANE'
    $controlPlaneHold = Get-PrivateFixtureCleanupPath (Join-Path $control '.ai-workspace-real') $control '^\.ai-workspace-real$' 'CONTROL_PLANE_HOLD'
    $controlTreeBefore=Get-PhysicalFixtureTree $controlPlane
    Move-Item -LiteralPath $controlPlane -Destination $controlPlaneHold
    try {
        New-TestJunction $controlPlane $controlPlaneHold
        $configJunction = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $controlTreeAfter=Get-PhysicalFixtureTree $controlPlaneHold
    } finally {
        Remove-TestJunction $controlPlane
        Move-Item -LiteralPath $controlPlaneHold -Destination $controlPlane
        if((Get-PhysicalFixtureTree $controlPlane)-cne$controlTreeBefore){throw 'FIXTURE_RESTORE_DRIFT|maintenance-control-junction'}
        Write-Output ('FIXTURE_RESTORED|maintenance-control-junction|tree='+(Get-BytesIdentity $utf8.GetBytes($controlTreeBefore)))
    }
    Assert-True ($configJunction.Code -ne 0 -and ($configJunction.Text.Contains('SOURCE_PUBLICATION_REPARSE') -or $configJunction.Text.Contains('PROJECT_CONFIG_REPARSE|.ai-workspace'))) 'maintenance-resolver-control-intermediate-junction-rejected'
    Assert-True ($controlTreeAfter-ceq$controlTreeBefore) 'maintenance-resolver-control-intermediate-junction-backing-unchanged'

    $frameworkPath = Get-PrivateFixtureCleanupPath (Join-Path $fixedRuntime 'framework') $fixedRuntime '^framework$' 'RUNTIME_FRAMEWORK'
    $frameworkHold = Get-PrivateFixtureCleanupPath (Join-Path $fixedRuntime 'framework-real') $fixedRuntime '^framework-real$' 'RUNTIME_FRAMEWORK_HOLD'
    $frameworkTreeBefore=Get-PhysicalFixtureTree $frameworkPath
    Move-Item -LiteralPath $frameworkPath -Destination $frameworkHold
    try {
        New-TestJunction $frameworkPath $frameworkHold
        $pinJunction = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $frameworkTreeAfter=Get-PhysicalFixtureTree $frameworkHold
    } finally {
        Remove-TestJunction $frameworkPath
        Move-Item -LiteralPath $frameworkHold -Destination $frameworkPath
        if((Get-PhysicalFixtureTree $frameworkPath)-cne$frameworkTreeBefore){throw 'FIXTURE_RESTORE_DRIFT|maintenance-runtime-junction'}
        Write-Output ('FIXTURE_RESTORED|maintenance-runtime-junction|tree='+(Get-BytesIdentity $utf8.GetBytes($frameworkTreeBefore)))
    }
    # An exact origin-reader path guard can reject before its release module
    # loads. Both results identify this runtime boundary, not a later failure.
    $pinReason=Get-IntegrationResolverFailure $pinJunction 'runtime-intermediate'
    $readerReparseReason='PATH_REPARSE|framework/versions/2.0.0/scripts/ReleaseValidation.psm1'
    $comparerReparseReason='PATH_REPARSE|framework/versions/2.0.0/scripts/ContentSources.psm1'
    Assert-True ($pinReason-cin@('RELEASE_REPARSE',$readerReparseReason,$comparerReparseReason)) 'maintenance-resolver-runtime-intermediate-junction-rejected'
    Assert-True ($frameworkTreeAfter-ceq$frameworkTreeBefore) 'maintenance-resolver-runtime-intermediate-junction-backing-unchanged'

    # A refusal after importing untrusted comparer code is too late. This
    # executable trap distinguishes pre-import validation from a later guard.
    $untrustedFramework=Get-PrivateFixtureCleanupPath (Join-Path $temp 'runtime-untrusted-framework') $temp '^runtime-untrusted-framework$' 'UNTRUSTED_FRAMEWORK'
    $untrustedHold=Get-PrivateFixtureCleanupPath (Join-Path $fixedRuntime 'framework-untrusted-hold') $fixedRuntime '^framework-untrusted-hold$' 'UNTRUSTED_HOLD'
    $comparerMarker=Get-PrivateFixtureCleanupPath (Join-Path $temp 'runtime-comparer-imported.txt') $temp '^runtime-comparer-imported\.txt$' 'COMPARER_MARKER'
    $untrustedScripts=Join-Path $untrustedFramework 'versions/2.0.0/scripts'
    New-Item -ItemType Directory -Path $untrustedScripts -Force|Out-Null
    Write-Utf8 (Join-Path $untrustedScripts 'ContentSources.psm1') ("[IO.File]::WriteAllText('"+$comparerMarker.Replace("'","''")+"','executed');throw 'UNTRUSTED_COMPARER_CODE_EXECUTED'")
    $untrustedBefore=Get-PhysicalFixtureTree $untrustedFramework
    Move-Item -LiteralPath $frameworkPath -Destination $untrustedHold
    try {
        New-TestJunction $frameworkPath $untrustedFramework
        $untrustedRun=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $comparerExecuted=Test-Path -LiteralPath $comparerMarker
        $untrustedAfter=Get-PhysicalFixtureTree $untrustedFramework
    } finally {
        Remove-TestJunction $frameworkPath
        Move-Item -LiteralPath $untrustedHold -Destination $frameworkPath
        Remove-Item -LiteralPath $untrustedFramework -Recurse -Force
        if(Test-Path -LiteralPath $comparerMarker){Remove-Item -LiteralPath $comparerMarker -Force}
        if((Get-PhysicalFixtureTree $frameworkPath)-cne$frameworkTreeBefore){throw 'FIXTURE_RESTORE_DRIFT|maintenance-untrusted-comparer'}
        Write-Output 'FIXTURE_RESTORED|maintenance-untrusted-comparer'
    }
    $untrustedReason=Get-IntegrationResolverFailure $untrustedRun 'untrusted-comparer'
    Assert-True (-not$comparerExecuted-and$untrustedBefore-ceq$untrustedAfter-and$untrustedReason-cin@('RELEASE_REPARSE',$readerReparseReason,$comparerReparseReason)) 'maintenance-runtime-comparer-junction-rejected-before-code-execution'

    $frameworkDanglingHold = Get-PrivateFixtureCleanupPath (Join-Path $fixedRuntime 'framework-dangling-hold') $fixedRuntime '^framework-dangling-hold$' 'RUNTIME_DANGLING_HOLD'
    $frameworkLinkTarget = Get-PrivateFixtureCleanupPath (Join-Path $fixedRuntime 'framework-link-target') $fixedRuntime '^framework-link-target$' 'RUNTIME_DANGLING_BACKING'
    Move-Item -LiteralPath $frameworkPath -Destination $frameworkDanglingHold
    try {
        New-Item -ItemType Directory -Path $frameworkLinkTarget -Force | Out-Null
        New-TestJunction $frameworkPath $frameworkLinkTarget
        Remove-Item -LiteralPath $frameworkLinkTarget -Force
        $controlledDanglingTreeBefore=Get-PhysicalFixtureTree $pair
        $danglingPin = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $frameworkDanglingTreeAfter=Get-PhysicalFixtureTree $frameworkDanglingHold
        $danglingControlledUnchanged=(Get-PhysicalFixtureTree $pair)-ceq$controlledDanglingTreeBefore
        $danglingBackingAbsent=-not(Test-Path -LiteralPath $frameworkLinkTarget)
    } finally {
        Remove-TestJunction $frameworkPath
        Move-Item -LiteralPath $frameworkDanglingHold -Destination $frameworkPath
        if(Test-Path -LiteralPath $frameworkLinkTarget){Remove-Item -LiteralPath $frameworkLinkTarget -Force}
        if((Get-PhysicalFixtureTree $frameworkPath)-cne$frameworkTreeBefore){throw 'FIXTURE_RESTORE_DRIFT|maintenance-runtime-dangling-junction'}
        Write-Output 'FIXTURE_RESTORED|maintenance-runtime-dangling-junction'
    }
    # A dangling framework link prevents loading the release reader before its reparse guard.
    $danglingReader=Join-Path (Join-Path $fixedRuntime 'scripts') '../framework/versions/2.0.0/scripts/ReleaseValidation.psm1'
    $danglingFailure="FAIL|framework-maintenance-target|The specified module '$danglingReader' was not loaded because no valid module file was found in any module directory."
    $canonicalDanglingReader=[IO.Path]::GetFullPath($danglingReader)
    $canonicalDanglingFailure="FAIL|framework-maintenance-target|The specified module '$canonicalDanglingReader' was not loaded because no valid module file was found in any module directory."
    $danglingComparer=Join-Path (Join-Path $fixedRuntime 'scripts') '../framework/versions/2.0.0/scripts/ContentSources.psm1'
    $danglingComparerFailure="FAIL|framework-maintenance-target|The specified module '$danglingComparer' was not loaded because no valid module file was found in any module directory."
    $canonicalDanglingComparer=[IO.Path]::GetFullPath($danglingComparer)
    $canonicalDanglingComparerFailure="FAIL|framework-maintenance-target|The specified module '$canonicalDanglingComparer' was not loaded because no valid module file was found in any module directory."
    Write-Host ('OBSERVE|maintenance-stage|case=runtime-dangling|exit='+$danglingPin.Code+'|lines='+$danglingPin.Output.Count+'|result='+$danglingPin.Text.Trim())
    $danglingReaderReparse='FAIL|framework-maintenance-target|'+$readerReparseReason
    $danglingComparerReparse='FAIL|framework-maintenance-target|'+$comparerReparseReason
    $danglingRejected=$danglingPin.Code-eq2-and$danglingPin.Output.Count-eq1-and$danglingPin.Text.Trim()-cin@($danglingFailure,$canonicalDanglingFailure,$danglingComparerFailure,$canonicalDanglingComparerFailure,$danglingReaderReparse,$danglingComparerReparse)
    Assert-True ($danglingBackingAbsent-and$danglingControlledUnchanged-and$danglingRejected) 'maintenance-resolver-runtime-dangling-junction-rejected'
    Assert-True ($frameworkDanglingTreeAfter-ceq$frameworkTreeBefore) 'maintenance-resolver-runtime-dangling-junction-backing-unchanged'

    $targetControlBacking = Get-PrivateFixtureCleanupPath (Join-Path $temp 'target-control-backing') $temp '^target-control-backing$' 'TARGET_CONTROL_BACKING'
    New-Item -ItemType Directory -Path $targetControlBacking -Force | Out-Null
    $targetControlTreeBefore=Get-PhysicalFixtureTree $targetControlBacking
    try {
        New-TestJunction $targetControl $targetControlBacking
        $targetControlJunction = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $junctionControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
        $junctionTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
        $targetControlTreeAfter=Get-PhysicalFixtureTree $targetControlBacking
    } finally {
        Remove-TestJunction $targetControl
        Remove-Item -LiteralPath $targetControlBacking -Recurse -Force
        if(Test-Path -LiteralPath $targetControlFixturePath){throw 'FIXTURE_RESTORE_DRIFT|maintenance-target-control-junction'}
        Write-Output 'FIXTURE_RESTORED|maintenance-target-control-junction'
    }
    Assert-True ($targetControlJunction.Code -ne 0 -and $targetControlJunction.Text.Contains('TARGET_CONTROL_PLANE_REPARSE')) 'maintenance-resolver-target-control-junction-rejected'
    Assert-True ($junctionControlAuth.Code -ne 0 -and $junctionTargetAuth.Code -ne 0 -and $junctionControlAuth.Text.Contains('TARGET_CONTROL_PLANE_REPARSE') -and $junctionTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_REPARSE')) 'authorization-schema2-target-control-junction-denies-control-and-target'
    Assert-True ($targetControlTreeAfter-ceq$targetControlTreeBefore) 'maintenance-target-control-junction-backing-unchanged'

    $danglingTargetControlBacking = Get-PrivateFixtureCleanupPath (Join-Path $temp 'target-control-dangling-backing') $temp '^target-control-dangling-backing$' 'TARGET_CONTROL_DANGLING_BACKING'
    New-Item -ItemType Directory -Path $danglingTargetControlBacking -Force | Out-Null
    try {
        New-TestJunction $targetControl $danglingTargetControlBacking
        Remove-Item -LiteralPath $danglingTargetControlBacking -Force
        $danglingTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $danglingControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
        $danglingTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
        $danglingTargetBackingAbsent=-not(Test-Path -LiteralPath $danglingTargetControlBacking)
    } finally {
        Remove-TestJunction $targetControl
        if(Test-Path -LiteralPath $danglingTargetControlBacking){Remove-Item -LiteralPath $danglingTargetControlBacking -Force}
        if(Test-Path -LiteralPath $targetControlFixturePath){throw 'FIXTURE_RESTORE_DRIFT|maintenance-target-control-dangling-junction'}
        Write-Output 'FIXTURE_RESTORED|maintenance-target-control-dangling-junction'
    }
    Assert-True ($danglingTargetControl.Code -eq 2 -and $danglingTargetControl.Text.Trim() -ceq 'FAIL|framework-maintenance-target|TARGET_CONTROL_PLANE_REPARSE') 'maintenance-resolver-target-control-dangling-junction-rejected'
    Assert-True ($danglingControlAuth.Code -eq 2 -and $danglingTargetAuth.Code -eq 2 -and $danglingControlAuth.Text.Contains('TARGET_CONTROL_PLANE_REPARSE') -and $danglingTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_REPARSE')) 'authorization-schema2-target-control-dangling-junction-denies-control-and-target'
    Assert-True $danglingTargetBackingAbsent 'maintenance-target-control-dangling-junction-backing-not-created'
 if((Get-PhysicalFixtureTree $pair)-cne$controlledTreeBefore){throw 'INTEGRATION_FRONTDOOR_CONTROLLED_TREE_DRIFT'}
 Assert-IntegrationMaintenanceBaseline $maintenanceFixture 'after-frontdoor'
}
 function Test-IntegrationMaintenanceGitReception([string]$OverlayPath=(Join-Path $liveRepositoryRoot 'scripts/MaintenanceOverlay.psm1')) {
  $overlay=Import-Module $OverlayPath -Force -PassThru
  if($overlay-isnot[Management.Automation.PSModuleInfo]){throw 'GIT_RECEPTION_MODULE_SHAPE'}
  $probeBase=Join-Path $temp 'git-reception';$null=[IO.Directory]::CreateDirectory($probeBase)
  $encodingBefore=@([Console]::InputEncoding.CodePage,[Console]::OutputEncoding.CodePage,$OutputEncoding.CodePage)
  Write-Output ('OBSERVATION|maintenance-git-reception|inputCP='+$encodingBefore[0]+'|outputCP='+$encodingBefore[1]+'|pipelineCP='+$encodingBefore[2])
  foreach($spec in @(@{name='unicode202';length=202;tail='注册-😀'},@{name='unicode203';length=203;tail='注册-😀'},@{name='ascii203';length=203;tail='ascii'})){
   $stem=Join-Path $probeBase ($spec.name+'-');$padding=$spec.length-$stem.Length-$spec.tail.Length
   if($padding-lt1){throw 'GIT_RECEPTION_FIXTURE_PREFIX_TOO_LONG'}
   $probe=$stem+('x'*$padding)+$spec.tail;New-GitRepo $probe
   $resolved=[IO.Path]::TrimEndingDirectorySeparator((Resolve-Path -LiteralPath $probe).ProviderPath)
   $tops=@(& $overlay {param($p) Get-AiwGitTop $p 'CONTROL_ROOT'} $probe)
   Assert-True ($resolved.Length-eq$spec.length-and$tops.Count-eq1-and$tops[0]-is[string]-and$tops[0]-ceq$resolved) ('maintenance-git-utf8-'+$spec.name+'-exact-top-and-single-result')
   $child=Join-Path $probe 'child';$null=[IO.Directory]::CreateDirectory($child)
   $reason='';try{& $overlay {param($p) Get-AiwGitTop $p 'CONTROL_ROOT'} $child|Out-Null}catch{$reason=$_.Exception.Message}
   Assert-True ($reason-ceq'CONTROL_ROOT_NOT_GIT_TOP') ('maintenance-git-'+$spec.name+'-child-rejected')
  }
  $reason='';try{& $overlay {param($p) Get-AiwGitTop $p 'CONTROL_ROOT'} $probeBase|Out-Null}catch{$reason=$_.Exception.Message}
  Assert-True ($reason-ceq'CONTROL_ROOT_GIT_TOP_UNAVAILABLE') 'maintenance-git-parent-non-git-rejected'
  foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR')){
   $previousEnvironment=[Environment]::GetEnvironmentVariables('Process')
   $wasPresent=$previousEnvironment.Contains($name);$previous=$previousEnvironment[$name]
   try {
    [Environment]::SetEnvironmentVariable($name,'fixture-override','Process')
    $reason='';try{& $overlay {param($p) Get-AiwGitTop $p 'CONTROL_ROOT'} $probe|Out-Null}catch{$reason=$_.Exception.Message}
    Assert-True ($reason-ceq('GIT_ENVIRONMENT_OVERRIDE_'+$name)) ('maintenance-git-'+$name+'-rejected')
   } finally {
    if($wasPresent){[Environment]::SetEnvironmentVariable($name,$previous,'Process')}
    else{[Environment]::SetEnvironmentVariable($name,[NullString]::Value,'Process')}
   }
   $restoredEnvironment=[Environment]::GetEnvironmentVariables('Process')
   Assert-True (($restoredEnvironment.Contains($name)-eq$wasPresent)-and(-not$wasPresent-or$restoredEnvironment[$name]-ceq$previous)) ('maintenance-git-'+$name+'-exact-presence-and-value-restored')
  }
  $link=Join-Path $probeBase 'linked-root'
  try {
   New-TestJunction $link $probe
   $reason='';try{& $overlay {param($p) Get-AiwGitTop $p 'CONTROL_ROOT'} $link|Out-Null}catch{$reason=$_.Exception.Message}
   Assert-True ($reason-ceq'CONTROL_ROOT_REPARSE') 'maintenance-git-reparse-root-rejected'
  } finally {Remove-TestJunction $link}
  Assert-True ((@([Console]::InputEncoding.CodePage,[Console]::OutputEncoding.CodePage,$OutputEncoding.CodePage)-join',')-ceq($encodingBefore-join',')) 'maintenance-git-reception-encoding-unchanged'
 }
 if($Case-cin@('All','NativeOutput','GitReception')){Test-IntegrationMaintenanceGitReception}
 if($Case-ceq'GitReception'){Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-git-reception';return}
 $maintenanceFixture=New-IntegrationMaintenanceFixture -Register:($Case-cin@('Frontdoor','Bootstrap','BodyDelivery','RuleLoadingRebind'))
 foreach($key in $maintenanceFixture.Keys){Set-Variable -Name $key -Value $maintenanceFixture[$key]}
 function Test-IntegrationRuleLoadingRebind {
  $oldTargetBytes=[IO.File]::ReadAllBytes((Join-Path $target $targetObject))
  $authPath=Join-Path $controlPlane 'rule-loading-auth.json'
  New-AuthorizationPackage $authPath 2 'ai-workspace-framework' $configIdentity @('SOURCE_WRITE') $targetObject (Get-Identity (Join-Path $target $targetObject)) -DomainOwner
  $package=Get-Content $authPath -Raw|ConvertFrom-Json -Depth 100
  $directory=Join-Path $control '.ai-workspace/runtime/FIXTURE-OWNER-001/owner-fixture';$null=[IO.Directory]::CreateDirectory($directory)
  $facets=@{};foreach($axis in @('domain','workType','deliverableType','stage')){$facets[$axis]=@{state='UNKNOWN';values=@()}}
  $di=@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=@{mode='FULL'};projectRoot=$control;frameworkRoot=$fixedRuntime;taskPath=(Join-Path $control '.ai-workspace/tasks/active/FIXTURE-OWNER-001.md');expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity=$package.taskIdentity;observedActor='owner-fixture';capabilities=@();exactPaths=@($targetObject);forbiddenPaths=@();protectedPaths=@('.ai-workspace/');authorizationPackagePath=$authPath;expectedAuthorizationIdentity=Get-Identity $authPath;userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$false;intentEnvelope=@{schemaVersion=2;objective='Implement the ordinary target fixture change';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR';facets=$facets}}
  $processEntry=Join-Path $fixedRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'
  $ip=Join-Path $directory 'discover.json';$rp=Join-Path $directory 'compact.json';Write-Utf8 $ip ($di|ConvertTo-Json -Depth 100)
  $first=Invoke-Ps $processEntry @('-InputPath',$ip,'-CompactReceiptPath',$rp,'-AsJson');if($first.Code-ne0){throw ('MAINTENANCE_REBIND_DISCOVER|'+$first.Text)};$d=$first.Stdout|ConvertFrom-Json -Depth 100
  $package.exactPaths+=@('ordinary-added.txt');$package.objectIdentities+=@([pscustomobject]@{path='ordinary-added.txt';identity='NEW'})
  $newAuth=Join-Path $controlPlane 'rule-loading-expanded-auth.json';Write-Utf8 $newAuth ($package|ConvertTo-Json -Depth 100)
  $bi=@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$rp;expectedDiscoverReceiptIdentity=Get-Identity $rp;preparationReceipts=@($d.compactReceipt.selectedObligations|ForEach-Object preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@();actionRebind=@{authorizationRef=@{path=$newAuth;identity=Get-Identity $newAuth};intentEnvelope=$di.intentEnvelope;recoveryState='CURRENT'}}
  $bp=Join-Path $directory 'rebind.json';$np=Join-Path $directory 'rebound.json';Write-Utf8 $bp ($bi|ConvertTo-Json -Depth 100)
  $savedActor=$env:CODEX_THREAD_ID
  try{$env:CODEX_THREAD_ID='owner-fixture';$actual=Invoke-Ps $processEntry @('-InputPath',$bp,'-CompactReceiptPath',$np,'-AsJson')}
  finally{$env:CODEX_THREAD_ID=$savedActor}
  if($actual.Code-ne0){throw ('MAINTENANCE_REBIND_ADMIT|'+$actual.Text)};$reply=$actual.Stdout|ConvertFrom-Json -Depth 100;$bound=Get-Content $np -Raw|ConvertFrom-Json -Depth 100
  Assert-True ($reply.status-ceq'PASS'-and-not$reply.ruleBodyLoaded-and$bound.binding.repositoryId-ceq'ai-workspace-framework'-and$bound.binding.objectRoot-ceq$target-and'ordinary-added.txt'-cin$bound.binding.exactScope) 'maintenance-target-rebind-keeps-original-root-checker-and-current-target-scope'
  Write-Utf8 (Join-Path $target $targetObject) 'current source postimage';Write-Utf8 (Join-Path $target 'ordinary-added.txt') 'new ordinary target file'
  $bi.Remove('actionRebind');$bi.mode='FINALIZE_OUTPUT';$bi.discoverReceiptPath=$np;$bi.expectedDiscoverReceiptIdentity=Get-Identity $np;$bi.resultReceipts=@($bound.selectedObligations|ForEach-Object resultRequirements|Sort-Object -Unique)+@($package.exactPaths|ForEach-Object{'OBJECT_POSTIMAGE|'+$_+'|'+(Get-Identity (Join-Path $target $_))})
  Write-Utf8 $bp ($bi|ConvertTo-Json -Depth 100);$done=Invoke-Ps $processEntry @('-InputPath',$bp,'-AsJson');Assert-True ($done.Code-eq0) ('maintenance-rebound-original-finalize|'+$done.Text)
  [IO.File]::WriteAllBytes((Join-Path $target $targetObject),$oldTargetBytes)
  $added=Get-PrivateFixtureCleanupPath (Join-Path $target 'ordinary-added.txt') $target '^ordinary-added\.txt$' 'REBIND_ADDED_OBJECT'
  [IO.File]::Delete($added)
 }
 if($Case-ceq'RuleLoadingRebind'){Test-IntegrationRuleLoadingRebind;Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-current-rule-loading-rebind';return}

 if($Case-ceq'BodyDelivery'){
  $policyPath=Join-Path $controlPlane 'process-policy.json';$policy=Get-Content -Raw -Encoding utf8 -LiteralPath $policyPath|ConvertFrom-Json -Depth 100
  $unicodeBody=('正文交付，完整条件与义务。😀Unicode é '+"`n")*1200
  $policy.rules+=@([pscustomobject]@{ruleId='BODY_DELIVERY';requirementReason='Explicit isolated body transport consumer';effectiveRule=$unicodeBody;selectors=@{profiles=@('*');roles=@('*');phases=@('*');actionKinds=@('*');resultKinds=@('*');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@('BODY_PREP');resultRequirements=@('BODY_RESULT');decisionLocator='fixture:body-delivery'})
  Write-Utf8 $policyPath ($policy|ConvertTo-Json -Depth 100)
  $actor='body-delivery-actor';$request='body-delivery-request';$directory=Join-Path $control ('.ai-workspace/runtime/'+$request+'/'+$actor);$null=[IO.Directory]::CreateDirectory($directory)
  $inputPath=Join-Path $directory 'discover.json';$bodyPath=Join-Path $directory 'official.txt'
  $facets=@{};foreach($axis in @('domain','workType','deliverableType','stage')){$facets[$axis]=@{state='UNKNOWN';values=@()}}
  $discover=@{schemaVersion=5;mode='DISCOVER';contextType='PROJECT_READ_ONLY';readOnlyContext=@{sessionId='body-delivery-session';requestId=$request;role='EXECUTOR';phase='PLAN';profile='STANDARD'};ruleLoad=@{mode='FULL'};projectRoot=$control;frameworkRoot=$fixedRuntime;taskPath='NOT_APPLICABLE';expectedProjectConfigIdentity=(Get-Identity $configPath);expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity='NOT_APPLICABLE';observedActor=$actor;capabilities=@();exactPaths=@();forbiddenPaths=@();protectedPaths=@();authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';evaluationOnly=$true;intentEnvelope=@{schemaVersion=2;objective='Explain this isolated complete body delivery fixture';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@();pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR';facets=$facets}}
  Write-Utf8 $inputPath ($discover|ConvertTo-Json -Depth 100)
  $processEntry=Join-Path $fixedRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'
  $actual=Invoke-Ps $processEntry @('-InputPath',$inputPath,'-AsJson','-DisplayPath',$bodyPath)
  if($actual.Code-ne0){throw ('MAINTENANCE_BODY_DELIVERY|'+$actual.Text)}
  $machine=$actual.Stdout|ConvertFrom-Json -Depth 100
  Import-Module (Join-Path $installedFramework 'scripts/ProcessRequirementDisplay.psm1') -Force
  $projection=Get-AiwProcessDisplay $machine;$official=[IO.File]::ReadAllText($bodyPath,[Text.UTF8Encoding]::new($false,$true))
  Assert-True ($actual.Stderr-ceq''-and$actual.Stdout-notmatch'[^\x00-\x7f]'-and$official-ceq$projection.text-and$official.Contains($unicodeBody.TrimEnd("`n"))-and$official.Contains('BODY_PREP')-and$official.Contains('BODY_RESULT')) 'maintenance-public-official-utf8-body-equals-same-complete-result'
  $limit=[Math]::Min(4096,$official.Length-1);$observed=$official.Substring(0,$limit)
  $observed+=[IO.File]::ReadAllText($bodyPath,[Text.UTF8Encoding]::new($false,$true)).Substring($limit)
  Assert-True ($observed-ceq$official-and$observed.EndsWith('AIW-END')-and-not$observed.Contains('"bodyCoverage"')-and$machine.compactReceipt.counts.sourceBuildCount-eq1) 'maintenance-limited-output-recovers-same-official-copy-no-second-parse'
  Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-body-delivery-public-consumer'
  return
 }
 if($Case-ceq'Bootstrap'){Test-IntegrationMaintenanceBootstrap;Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-bootstrap-current-contract';return}
 if($Case-ceq'Frontdoor'){
  $steadyStateControlPackage=Join-Path $controlPlane 'steady-state-control-auth.json';$steadyStateTargetPackage=Join-Path $controlPlane 'steady-state-target-auth.json'
  $controlObjectIdentity=Get-Identity (Join-Path $control $controlObject);$targetObjectIdentity=Get-Identity (Join-Path $target $targetObject)
  New-AuthorizationPackage $steadyStateControlPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject $controlObjectIdentity
  New-AuthorizationPackage $steadyStateTargetPackage 2 'ai-workspace-framework' $configIdentity @('SOURCE_WRITE') $targetObject $targetObjectIdentity
  Test-IntegrationMaintenanceFrontdoor
  Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-frontdoor'
 } else {
    $starterControl=Join-Path $temp 'maintenance-starter-fixture'
    New-Item -ItemType Directory -Path $starterControl|Out-Null
    $controlPlane = Render-MaintenanceStarter (Join-Path $candidateRoot 'project-starter') $maintenanceOverlayRoot $starterControl
    $renderedFiles = Get-ChildItem -LiteralPath $controlPlane -Recurse -Force -File
    Assert-True (@($renderedFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8).Contains('{{') }).Count -eq 0) 'maintenance-starter-placeholders-closed'
    $renderedMaintenancePolicy=Get-Content -LiteralPath (Join-Path $controlPlane 'process-policy.json') -Raw -Encoding utf8|ConvertFrom-Json
    Assert-True (@($renderedMaintenancePolicy.rules|Where-Object{[string]$_.ruleId-ceq'FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY'}).Count-eq1) 'maintenance-root-overlay-project-policy-projected-once'
    try {
        [IO.File]::Delete($runtimeManifestPath)
        $missingRuntimeManifest=Invoke-Ps $maintenanceRegister $registerArgs
        Assert-True ($missingRuntimeManifest.Code-ne0-and$missingRuntimeManifest.Text.Contains('DISTRIBUTION_MANIFEST_REQUIRED')-and-not(Test-Path -LiteralPath (Join-Path $control '.ai-workspace'))) 'maintenance-register-missing-fixed-package-rejected-before-write'
    } finally { [IO.File]::WriteAllBytes($runtimeManifestPath,$runtimeManifestBytes) }
    $sourceExecution=Invoke-Ps (Join-Path $liveRepositoryRoot 'scripts/register-project.ps1') $registerArgs
    Assert-True ($sourceExecution.Code-ne0-and$sourceExecution.Text.Contains('DISTRIBUTION_MANIFEST_REQUIRED')-and-not(Test-Path -LiteralPath (Join-Path $control '.ai-workspace'))) 'maintenance-register-development-execution-rejected-before-write'
    $registeredMaintenance=Invoke-Ps $maintenanceRegister $registerArgs
    if($registeredMaintenance.Code-ne0){Write-Output ('DIAG|maintenance-register|'+$registeredMaintenance.Text)}
    Assert-IntegrationRegistrationResult $registeredMaintenance $maintenanceFixture
    Assert-True ($registeredMaintenance.Code-eq0-and$registeredMaintenance.Text.Contains('CREATED')) 'maintenance-register-real-fixed-package-producer'
 $completed=Complete-IntegrationMaintenanceFixture $maintenanceFixture
 foreach($key in $completed.Keys){$maintenanceFixture[$key]=$completed[$key];Set-Variable -Name $key -Value $completed[$key]}
 if($Case-ceq'All'){Test-IntegrationRuleLoadingRebind}
    Assert-True ($adoptionState.transactionComplete-and$adoptionState.state-ceq'COMPLETE'-and$adoptionState.metadata.distributionBinding.runtimeRoot-ceq$fixedRuntime-and$adoptionState.metadata.distributionBinding.manifestIdentity-ceq(Get-Identity $runtimeManifestPath)-and-not(Test-Path -LiteralPath (Join-Path $fixedRuntime '.git'))) 'maintenance-fixed-runtime-completed-adoption-binding'
    Assert-True ($installedActual.Count -eq $actual.Count -and ($installedActual -join "`n") -ceq ($actual -join "`n")) 'maintenance-fixed-runtime-full-sealed-fixture-installed'
    if($Case-cin@('All','NativeOutput')){
     # Exercise the unchanged native entry and strict raw reader, including
     # values whose full representation cannot fit a host table cell.
     $unicodeRoot=Join-Path $pair ('注册-😀-'+('long-path-'*8));New-GitRepo $unicodeRoot
     $unicodeArgs=@($registerArgs);$unicodeArgs[[array]::IndexOf($unicodeArgs,'-RepositoryPath')+1]=$unicodeRoot
     $unicodeArgs[[array]::IndexOf($unicodeArgs,'-DisplayName')+1]="中文 😀 `"quoted`"`nsecond line"
     $previewArgs=@($unicodeArgs|Where-Object{$_-cne'-Apply'});$before=Get-PhysicalFixtureTree $unicodeRoot
     foreach($shape in @('preview','whatif')){
      $callArgs=@($previewArgs);if($shape-ceq'whatif'){$callArgs+=@('-Apply','-WhatIf')}
      $preview=Invoke-Ps $maintenanceRegister $callArgs
      $reply=@($preview.Output|Where-Object{$_.StartsWith('{')}|ForEach-Object{$_|ConvertFrom-Json -Depth 100})[-1]
      Assert-True ($preview.Code-eq0-and$preview.Stderr-ceq''-and$reply.status-ceq'WHAT_IF'-and$reply.changes-is[Array]-and$reply.changes.Count-gt4-and$reply.projectRoot-ceq(Join-Path $unicodeRoot '.ai-workspace')-and(Get-PhysicalFixtureTree $unicodeRoot)-ceq$before) ('maintenance-native-'+$shape+'-complete-array-and-zero-write')
      if($shape-ceq'whatif'){Assert-True ($preview.Stdout.Contains('What if:')-and$preview.Stdout.Contains('注册-😀-')) 'maintenance-native-whatif-Unicode-host-output'}
     }
     $unicodeRun=Invoke-Ps $maintenanceRegister @($unicodeArgs+@('-Confirm:$false'))
     $unicodeContext=@{control=$unicodeRoot};Assert-IntegrationRegistrationResult $unicodeRun $unicodeContext
     $registeredTree=Get-PhysicalFixtureTree $unicodeRoot
     $repeat=Invoke-Ps $maintenanceRegister $unicodeArgs;$repeatReply=$repeat.Stdout|ConvertFrom-Json -Depth 100
     Assert-True ($repeat.Code-eq0-and$repeat.Stderr-ceq''-and$repeatReply.status-ceq'ALREADY_REGISTERED'-and(Get-PhysicalFixtureTree $unicodeRoot)-ceq$registeredTree) 'maintenance-native-repeat-original-object-fields-and-zero-write'
     $targetEntry=Join-Path $fixedRuntime 'scripts/resolve-framework-maintenance-target.ps1'
     $unicodeConfigPath=Join-Path $unicodeRoot '.ai-workspace/project.json';$unicodeConfig=Get-Content -LiteralPath $unicodeConfigPath -Raw -Encoding utf8|ConvertFrom-Json
     $targetArgs=@('-ControlRepositoryPath',$unicodeRoot,'-ExpectedProjectConfigIdentity',(Get-Identity $unicodeConfigPath),'-AsJson')
     $targetNative=Invoke-Ps $targetEntry $targetArgs;$targetValue=$targetNative.Stdout|ConvertFrom-Json -Depth 100
     $expectedTarget=[ordered]@{status='PASS';layout='framework-maintenance-sibling';projectId=$unicodeConfig.id;frameworkVersion='2.0.0';projectConfigIdentity=(Get-Identity $unicodeConfigPath);controlRepositoryId='CONTROL';controlRoot=$unicodeRoot;targetRepositoryId=$unicodeConfig.frameworkTarget.repositoryId;targetRoot=$target;runtimeRoot=$fixedRuntime;controllerId='controller-fixture';controllerEpoch=1;controllerState='CURRENT'}
     Assert-True ($targetNative.Code-eq0-and$targetNative.Stderr-ceq''-and$targetNative.Stdout-notmatch'[^\x00-\x7f]'-and($targetValue|ConvertTo-Json -Depth 100 -Compress)-ceq($expectedTarget|ConvertTo-Json -Depth 100 -Compress)) 'maintenance-target-unicode-native-all-thirteen-fields'
     $targetInProcessArguments=@{ControlRepositoryPath=$unicodeRoot;ExpectedProjectConfigIdentity=(Get-Identity $unicodeConfigPath);AsJson=$true}
     $targetInProcess=@(& $targetEntry @targetInProcessArguments)
     Assert-True ($LASTEXITCODE-eq0-and$targetInProcess.Count-eq1-and(($targetInProcess[0]|ConvertFrom-Json -Depth 100|ConvertTo-Json -Depth 100 -Compress)-ceq($targetValue|ConvertTo-Json -Depth 100 -Compress))) 'maintenance-target-inprocess-native-complete-equality'
     $worker=Join-Path $temp 'root-inprocess-output.ps1';$workerInput=Join-Path $temp 'root-inprocess-output.json'
     Write-Utf8 $workerInput (@{entry=$maintenanceRegister;root=$unicodeRoot;runtime=$fixedRuntime;display="中文 😀 `"quoted`"`nsecond line"}|ConvertTo-Json -Depth 10)
     Write-Utf8 $worker @'
param([string]$InputPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$inputData=Get-Content -LiteralPath $InputPath -Raw -Encoding utf8|ConvertFrom-Json
$testRoot=$inputData.root;$testRuntime=$inputData.runtime;$testEntry=$inputData.entry;$testDisplay=$inputData.display
$outWriter=[Console]::Out;$errWriter=[Console]::Error;$outEncoding=[Console]::OutputEncoding.CodePage;$errEncoding=[Console]::InputEncoding.CodePage
$testArguments=@{ProjectId='framework-maintenance-fixture';DisplayName=$testDisplay;RepositoryPath=$testRoot;FrameworkVersion='2.0.0';ControllerId='controller-fixture';WorkspaceRoot=$testRuntime;ControlPlaneLayout='framework-maintenance-sibling';FrameworkTargetRepositoryId='ai-workspace-framework';FrameworkTargetSiblingDirectory='AI-Workspace'}
foreach($shape in @('amp','dot')){
 $value=if($shape-ceq'amp'){& $testEntry @testArguments}else{. $testEntry @testArguments}
 if($value-isnot[pscustomobject]-or$value.status-cne'ALREADY_REGISTERED'){throw ('INPROCESS_OBJECT|'+$shape)}
 if(-not[object]::ReferenceEquals([Console]::Out,$outWriter)-or-not[object]::ReferenceEquals([Console]::Error,$errWriter)-or[Console]::OutputEncoding.CodePage-ne$outEncoding-or[Console]::InputEncoding.CodePage-ne$errEncoding){throw 'INPROCESS_WRITER_CHANGED'}
 $bad=$testArguments.Clone();$bad.FrameworkVersion='missing-unicode-version';$caught=$null
 try{& $testEntry @bad|Out-Null}catch{$caught=$_}
 if($caught-isnot[Management.Automation.ErrorRecord]-or-not$caught.Exception.Message.Contains('FRAMEWORK_VERSION_NOT_FOUND')){throw 'INPROCESS_ORIGINAL_ERROR'}
}
'INPROCESS_CALLER_ALIVE|objects-and-original-errors'
'@
     $inprocess=Invoke-Ps $worker @('-InputPath',$workerInput)
     Assert-True ($inprocess.Code-eq0-and$inprocess.Text.Contains('INPROCESS_CALLER_ALIVE')) 'maintenance-native-neighbor-inprocess-amp-dot-writers-errors-and-caller'
     $upgrade=Join-Path $fixedRuntime 'scripts/upgrade-project.ps1'
     $upgradePreview=Invoke-Ps $upgrade @('-ProjectId','framework-maintenance-fixture','-ToVersion','2.0.0','-RepositoryPath',$unicodeRoot,'-ControllerId','controller-fixture','-WorkspaceRoot',$fixedRuntime)
     Assert-True ($upgradePreview.Code-eq0-and$upgradePreview.Stderr-ceq''-and$upgradePreview.Text.Contains('WHAT_IF|from=2.0.0|to=2.0.0|objects=0|transaction=none')) 'maintenance-native-upgrade-preview-and-internal-register-object-consumer'
     $ps5=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
     foreach($entry in @(@{path=$maintenanceRegister;args=$previewArgs},@{path=$upgrade;args=@('-ProjectId','framework-maintenance-fixture','-ToVersion','2.0.0','-RepositoryPath',$unicodeRoot)})){
      $guard=Invoke-PsHost $ps5 $entry.path $entry.args
      $guardReply=$guard.Stderr.Trim()|ConvertFrom-Json -Depth 100
      Assert-True ($guard.Code-eq1-and$guard.Stdout-ceq''-and$guardReply.reason-ceq'FRAMEWORK_TOOL_RUNTIME_UNAVAILABLE|backend=powershell7|requires=pwsh>=7') ('maintenance-native-PS5-original-guard-'+[IO.Path]::GetFileName($entry.path))
     }
     if($Case-ceq'NativeOutput'){Write-Output 'EVIDENCE_CEILING|PARTIAL|maintenance-native-output';return}
    }
    $controllerSchema = Get-Content -LiteralPath (Join-Path $installedFramework 'CONTROLLER_SCHEMA.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ([string]$controllerSchema.properties.state.const -ceq 'CURRENT' -and $null -eq $controllerSchema.properties.state.PSObject.Properties['enum']) 'controller-schema-current-only'
    $resolve = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
    if($resolve.Code-ne0){Write-Output ('DIAG|maintenance-resolver|code='+$resolve.Code+'|'+$resolve.Text)}
    Assert-True ($resolve.Code -eq 0 -and $resolve.Text.Contains('"targetRepositoryId":"ai-workspace-framework"') -and $resolve.Text.Contains('"controllerState":"CURRENT"') -and (($resolve.Output[-1]|ConvertFrom-Json).runtimeRoot-ceq$fixedRuntime) -and (($resolve.Output[-1]|ConvertFrom-Json).targetRoot-ceq$target) -and -not $resolve.Text.Contains('migrationState') -and -not $resolve.Text.Contains('activeAuthority')) 'maintenance-resolver-final-current-two-real-git-tops'

    $steadyStateControlPackage = Join-Path $controlPlane 'steady-state-control-auth.json'
    $steadyStateTargetPackage = Join-Path $controlPlane 'steady-state-target-auth.json'
    $controlObjectIdentity = Get-Identity (Join-Path $control $controlObject)
    $targetObjectIdentity = Get-Identity (Join-Path $target $targetObject)
    New-AuthorizationPackage $steadyStateControlPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject $controlObjectIdentity
    New-AuthorizationPackage $steadyStateTargetPackage 2 'ai-workspace-framework' $configIdentity @('SOURCE_WRITE') $targetObject $targetObjectIdentity
    $steadyStateControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $steadyStateTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Assert-True ($steadyStateControlAuth.Code -eq 0 -and $steadyStateTargetAuth.Code -eq 0) 'authorization-schema2-steady-state-resolver-bound-pass'

    $maintenanceSchema1Package = Join-Path $controlPlane 'maintenance-schema1-auth.json'
    New-AuthorizationPackage $maintenanceSchema1Package 1 '' $configIdentity @('SOURCE_WRITE') $targetObject $targetObjectIdentity -DomainOwner
    $maintenanceSchema1Steady = Invoke-Ps $checker @('-PackagePath',$maintenanceSchema1Package,'-ObservedActor','owner-fixture','-ObservedTaskId','FIXTURE-OWNER-001','-ObservedOwner','owner-fixture','-ObservedAction','SOURCE_WRITE','-ObservedPath',$targetObject,'-ObservedIdentity',($targetObject+'='+$targetObjectIdentity),'-ObservedRepositoryId','ai-workspace-framework','-ProjectConfigPath','.ai-workspace/project.json','-ExpectedProjectConfigIdentity',$configIdentity,'-TaskPath','.ai-workspace/tasks/active/FIXTURE-OWNER-001.md','-ExpectedTaskIdentity',(Get-Identity (Join-Path $control '.ai-workspace/tasks/active/FIXTURE-OWNER-001.md'))) $control
    Assert-True ($maintenanceSchema1Steady.Code -ne 0 -and $maintenanceSchema1Steady.Text.Contains('SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3')) 'authorization-schema1-maintenance-steady-state-rejected'

    $maintenanceCurrentConfigRaw=Get-Content -LiteralPath $configPath -Raw -Encoding utf8
    $maintenancePolicyPath=Join-Path $controlPlane 'process-policy.json'
    $maintenanceCurrentPolicyRaw=Get-Content -LiteralPath $maintenancePolicyPath -Raw -Encoding utf8
    function Assert-MaintenanceAuthorizationRejection($Run,[string]$ExpectedReason,[string]$Name) {
        # Keep actual inner Code/Text; a generic wrapper FAIL proves no named boundary.
        Write-Output ('OBSERVE|maintenance-inner-authorization|case='+$Name+'|code='+$Run.Code+'|text='+$Run.Text)
        $observedReason=''
        $wrapper='FAIL|framework-maintenance-authorization|'
        $resolution=$wrapper+'MAINTENANCE_TARGET_RESOLUTION_FAILED|'
        $raw=$Run.Text.Trim()
        if($raw.StartsWith($resolution,[StringComparison]::Ordinal)){
            try{$failure=$raw.Substring($resolution.Length)|ConvertFrom-Json;if($failure.status-ceq'FAIL'){$observedReason=[string]$failure.reason}}catch{}
        }elseif($raw.StartsWith($wrapper,[StringComparison]::Ordinal)){$observedReason=$raw.Substring($wrapper.Length)}
        Assert-True ($Run.Code-eq2-and$observedReason-ceq$ExpectedReason) ('authorization-maintenance-rejects-'+$Name)
    }
    # Old policy format is one fault against an otherwise healthy current binding.
    # This does not recreate an obsolete Source-coupled execution environment.
    $oldPolicy=$maintenanceCurrentPolicyRaw|ConvertFrom-Json;$oldPolicy.schemaVersion=1
    try {
        Write-Utf8 $maintenancePolicyPath ($oldPolicy|ConvertTo-Json -Depth 30)
        $oldPolicyPackage=Join-Path $controlPlane 'maintenance-old-policy-schema.json'
        New-MaintenanceUpgradeAuthorizationPackage $oldPolicyPackage $configIdentity $controlObject $controlObjectIdentity
        $oldPolicyRun=Invoke-FixtureSchema2Authorization $checker $oldPolicyPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
        Assert-MaintenanceAuthorizationRejection $oldPolicyRun 'PROCESS_POLICY_VALUES' 'old-policy-schema'
    } finally { Write-Utf8 $maintenancePolicyPath $maintenanceCurrentPolicyRaw }
    function Invoke-MaintenanceSchema3Rejected($Config,[string]$Name,[string]$ExpectedReason) {
        try {
            Write-Utf8 $configPath ($Config|ConvertTo-Json -Depth 30)
            $identity=Get-Identity $configPath
            $packagePath=Join-Path $controlPlane ('maintenance-schema3-reject-'+$Name+'.json')
            New-MaintenanceUpgradeAuthorizationPackage $packagePath $identity $controlObject $controlObjectIdentity
            $run=Invoke-FixtureSchema2Authorization $checker $packagePath $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $identity
            Assert-MaintenanceAuthorizationRejection $run $ExpectedReason $Name
        } finally {
            Write-Utf8 $configPath $maintenanceCurrentConfigRaw
            Write-Utf8 $maintenancePolicyPath $maintenanceCurrentPolicyRaw
        }
    }
    $currentConfig=$maintenanceCurrentConfigRaw|ConvertFrom-Json
    Invoke-MaintenanceSchema3Rejected $currentConfig 'direct-upgrade-target-object' 'MAINTENANCE_SCHEMA3_DIRECT_AUTHORIZATION_DENIED'
    $extraTarget=$maintenanceCurrentConfigRaw|ConvertFrom-Json;$extraTarget.frameworkTarget|Add-Member -NotePropertyName extra -NotePropertyValue 'forbidden'
    Invoke-MaintenanceSchema3Rejected $extraTarget 'extra-target-field' 'FRAMEWORK_TARGET_FIELDS'
    $unsafeSibling=$maintenanceCurrentConfigRaw|ConvertFrom-Json;$unsafeSibling.frameworkTarget.siblingDirectory='../AI-Workspace'
    Invoke-MaintenanceSchema3Rejected $unsafeSibling 'unsafe-sibling' 'TARGET_SIBLING_COMPONENT'
    $controlTarget=$maintenanceCurrentConfigRaw|ConvertFrom-Json;$controlTarget.frameworkTarget.repositoryId='CONTROL'
    Invoke-MaintenanceSchema3Rejected $controlTarget 'control-target-id' 'TARGET_REPOSITORY_ID'
    $missingTarget=$maintenanceCurrentConfigRaw|ConvertFrom-Json;$missingTarget.frameworkTarget.siblingDirectory='Missing-Target'
    Invoke-MaintenanceSchema3Rejected $missingTarget 'missing-target-root' 'TARGET_ROOT_MISSING'
    $linkPath=Join-Path $pair 'AI-Workspace-Link';New-TestJunction $linkPath $target
    try{$linkedTarget=$maintenanceCurrentConfigRaw|ConvertFrom-Json;$linkedTarget.frameworkTarget.siblingDirectory='AI-Workspace-Link';Invoke-MaintenanceSchema3Rejected $linkedTarget 'target-reparse' 'TARGET_ROOT_REPARSE'}finally{Remove-TestJunction $linkPath}
    New-Item -ItemType Directory -Path $targetControlFixturePath|Out-Null
    try{Invoke-MaintenanceSchema3Rejected ($maintenanceCurrentConfigRaw|ConvertFrom-Json) 'target-control-plane' 'TARGET_CONTROL_PLANE_FORBIDDEN'}finally{Remove-Item -LiteralPath $targetControlFixturePath -Recurse -Force}
    & git -C $pair init -q
    try{Invoke-MaintenanceSchema3Rejected ($maintenanceCurrentConfigRaw|ConvertFrom-Json) 'workspace-parent-git' 'WORKSPACE_PARENT_GIT_FORBIDDEN'}finally{Remove-Item -LiteralPath $pairGitFixturePath -Recurse -Force}
    $configIdentity=Get-Identity $configPath
    $invalidStatePackage = Join-Path $controlPlane 'invalid-state-auth.json'
    $invalidStateDomainPackage = Join-Path $controlPlane 'invalid-state-domain-auth.json'
    New-AuthorizationPackage $invalidStatePackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject))
    New-AuthorizationPackage $invalidStateDomainPackage 2 'CONTROL' $configIdentity @('CONTROL_WRITE') $controlObject (Get-Identity (Join-Path $control $controlObject)) -DomainOwner
    $controllerRawBeforeInvalidState = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $invalidController = $controllerRawBeforeInvalidState | ConvertFrom-Json
    $invalidController.state = 'NOT_CURRENT'
    Write-Utf8 $controllerPath ($invalidController | ConvertTo-Json -Depth 10)
    $invalidStateResolve = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
    $invalidStateAuth = Invoke-FixtureSchema2Authorization $checker $invalidStatePackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject (Get-Identity (Join-Path $control $controlObject)) 'CONTROL' $configIdentity
    $invalidStateDomainAuth = Invoke-FixtureSchema2Authorization $checker $invalidStateDomainPackage $control 'owner-fixture' 'CONTROL_WRITE' $controlObject (Get-Identity (Join-Path $control $controlObject)) 'CONTROL' $configIdentity
    Write-Utf8 $controllerPath $controllerRawBeforeInvalidState
    Assert-True ($invalidStateResolve.Code -ne 0 -and $invalidStateResolve.Text.Contains('CONTROLLER_VALUES')) 'non-current-controller-rejected-by-resolver'
    Assert-True ($invalidStateAuth.Code -ne 0 -and $invalidStateAuth.Text.Contains('CONTROLLER_VALUES') -and $invalidStateDomainAuth.Code -ne 0 -and $invalidStateDomainAuth.Text.Contains('CONTROLLER_VALUES')) 'non-current-controller-cannot-authorize-any-issuer-role'

    $targetControl = $targetControlFixturePath
    New-Item -ItemType Directory -Path $targetControl -Force | Out-Null
    Write-Utf8 (Join-Path $targetControl 'controller.json') (@{schemaVersion=1;projectId='foreign';controllerId='foreign';controllerEpoch=1;state='CURRENT'} | ConvertTo-Json)
    $completeTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $completeControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $completeTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    $completeSchema1Auth = Invoke-FixtureSchema2Authorization $checker $maintenanceSchema1Package $control 'owner-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Recurse -Force
    Assert-True ($completeTargetControl.Code -ne 0 -and $completeTargetControl.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'maintenance-resolver-complete-target-control-plane-rejected'
    Assert-True ($completeControlAuth.Code -ne 0 -and $completeTargetAuth.Code -ne 0 -and $completeControlAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN') -and $completeTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema2-complete-target-control-plane-denies-control-and-target'
    Assert-True ($completeSchema1Auth.Code -ne 0 -and $completeSchema1Auth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema1-maintenance-nonsteady-rejected'

    New-Item -ItemType Directory -Path $targetControl -Force | Out-Null
    $partialTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $partialControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $partialTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Recurse -Force
    Assert-True ($partialTargetControl.Code -ne 0 -and $partialTargetControl.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'maintenance-resolver-partial-target-control-plane-rejected'
    Assert-True ($partialControlAuth.Code -ne 0 -and $partialTargetAuth.Code -ne 0 -and $partialControlAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN') -and $partialTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema2-partial-target-control-plane-denies-control-and-target'

    Write-Utf8 $targetControl 'foreign leaf'
    $foreignTargetControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    $foreignControlAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateControlPackage $control 'controller-fixture' 'CONTROL_WRITE' $controlObject $controlObjectIdentity 'CONTROL' $configIdentity
    $foreignTargetAuth = Invoke-FixtureSchema2Authorization $checker $steadyStateTargetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject $targetObjectIdentity 'ai-workspace-framework' $configIdentity
    Remove-Item -LiteralPath $targetControl -Force
    Assert-True ($foreignTargetControl.Code -ne 0 -and $foreignTargetControl.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'maintenance-resolver-foreign-target-control-plane-rejected'
    Assert-True ($foreignControlAuth.Code -ne 0 -and $foreignTargetAuth.Code -ne 0 -and $foreignControlAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN') -and $foreignTargetAuth.Text.Contains('TARGET_CONTROL_PLANE_FORBIDDEN')) 'authorization-schema2-foreign-target-control-plane-denies-control-and-target'

    Test-IntegrationMaintenanceBootstrap

    $drift = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',('0|' + ('0' * 64)),'-AsJson')
    Assert-True ($drift.Code -ne 0 -and $drift.Text.Contains('PROJECT_CONFIG_DRIFT')) 'maintenance-resolver-config-drift-fails-closed'

    New-Item -ItemType Directory -Path $pairGitFixturePath -Force | Out-Null
    $parentGit = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Assert-True ($parentGit.Code -ne 0 -and $parentGit.Text.Contains('WORKSPACE_PARENT_GIT_FORBIDDEN')) 'maintenance-resolver-parent-git-forbidden'
    Remove-Item -LiteralPath $pairGitFixturePath -Recurse -Force

    New-Item -ItemType Directory -Path $pairControlFixturePath -Force | Out-Null
    $parentControl = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Assert-True ($parentControl.Code -ne 0 -and $parentControl.Text.Contains('WORKSPACE_PARENT_CONTROL_FORBIDDEN')) 'maintenance-resolver-parent-control-forbidden'
    Remove-Item -LiteralPath $pairControlFixturePath -Recurse -Force

    $configRaw = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
    $typedConfig = $configRaw | ConvertFrom-Json
    $typedConfig.schemaVersion = '6'
    Write-Utf8 $configPath ($typedConfig | ConvertTo-Json -Depth 20)
    $typedResult = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($typedResult.Code -ne 0 -and $typedResult.Text.Contains('PROJECT_CONFIG_VALUES')) 'maintenance-current-schema-type-rejected'

    $duplicateRaw = [regex]::Replace($configRaw,'(?m)^(\s*"id"\s*:\s*.+,)$',"`$1`n`$1",1)
    Write-Utf8 $configPath $duplicateRaw
    $duplicateResult = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($duplicateResult.Code -ne 0 -and $duplicateResult.Text.Contains('JSON_DUPLICATE_MEMBER|id')) 'maintenance-schema4-duplicate-field-rejected'

    $unicodeTopConfigRaw=[regex]::Replace($configRaw,'("routineExcludedPaths"\s*:\s*\[[^\]]*\])','$1, "\u0072outineExcludedPaths": []',1)
    Write-Utf8 $configPath $unicodeTopConfigRaw
    $unicodeTopConfigResult=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($unicodeTopConfigResult.Code-ne0-and$unicodeTopConfigResult.Text.Contains('JSON_DUPLICATE_MEMBER|routineExcludedPaths')) 'maintenance-schema4-unicode-top-level-duplicate-rejected'

    $unicodeNestedConfigRaw=[regex]::Replace($configRaw,'("locator"\s*:\s*"\.ai-workspace/process-policy\.json")','$1, "\u006cocator": ".ai-workspace/process-policy.json"',1)
    Write-Utf8 $configPath $unicodeNestedConfigRaw
    $unicodeNestedConfigResult=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($unicodeNestedConfigResult.Code-ne0-and$unicodeNestedConfigResult.Text.Contains('JSON_DUPLICATE_MEMBER|locator')) 'maintenance-schema4-unicode-nested-policy-duplicate-rejected'
    Assert-True ((Get-Identity $configPath) -ceq $configIdentity) 'maintenance-fixture-config-restored-after-schema-negatives'

Test-IntegrationMaintenanceFrontdoor
    $missingTargetConfig = $configRaw | ConvertFrom-Json
    $missingTargetConfig.frameworkTarget.siblingDirectory = 'AI-Workspace-Missing'
    Write-Utf8 $configPath ($missingTargetConfig | ConvertTo-Json -Depth 20)
    $missingTarget = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',(Get-Identity $configPath))
    Write-Utf8 $configPath $configRaw
    Assert-True ($missingTarget.Code -ne 0 -and $missingTarget.Text.Contains('TARGET_ROOT_MISSING')) 'maintenance-resolver-target-missing-rejected'

    $recoveryPath = Join-Path $installedFramework 'RECOVERY_CORE.md'
    $recoveryHold = Join-Path $installedFramework 'RECOVERY_CORE.fixture-hold'
    Move-Item -LiteralPath $recoveryPath -Destination $recoveryHold
    try { $missingPin = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity) }
    finally { Move-Item -LiteralPath $recoveryHold -Destination $recoveryPath }
    $missingPinReason=Get-IntegrationResolverFailure $missingPin 'pin-entry-missing'
    Assert-True ($missingPinReason-ceq'TARGET_VERSION_FILE_MISSING|RECOVERY_CORE.md') 'maintenance-resolver-pin-entry-missing-rejected'

    $controllerRaw = Get-Content -LiteralPath $controllerPath -Raw -Encoding utf8
    $staleController = $controllerRaw | ConvertFrom-Json
    $staleController.projectId = 'wrong-project'
    Write-Utf8 $controllerPath ($staleController | ConvertTo-Json -Depth 10)
    $staleControllerResult = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Write-Utf8 $controllerPath $controllerRaw
    Assert-True ($staleControllerResult.Code -ne 0 -and $staleControllerResult.Text.Contains('CONTROLLER_VALUES')) 'maintenance-resolver-stale-controller-rejected'
    $developerWithoutHostEntry = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
    Assert-True ($developerWithoutHostEntry.Code -eq 0 -and -not(Test-Path -LiteralPath (Join-Path $target 'AGENTS.md')) -and -not(Test-Path -LiteralPath (Join-Path $target 'CLAUDE.md')) -and (Test-Path -LiteralPath (Join-Path $control 'AGENTS.md') -PathType Leaf)) 'maintenance-resolver-developer-without-host-entry-preserves-project-entry'
    $readmePath = Join-Path $target 'README.md'
    $readmeHold = Join-Path $target 'README.fixture-hold'
    Move-Item -LiteralPath $readmePath -Destination $readmeHold
    try { $missingReadme = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity) }
    finally { Move-Item -LiteralPath $readmeHold -Destination $readmePath }
    Assert-True ($missingReadme.Code-eq0) 'maintenance-resolver-development-readme-does-not-replace-runtime-binding'
    # Corrupt an actual consumer while preserving syntax; unconsumed README is not a daily byte-check input.
    $runtimeMember='scripts/MaintenanceOverlay.psm1'
    $runtimeMemberPath=Join-Path $fixedRuntime $runtimeMember;$runtimeMemberBytes=[IO.File]::ReadAllBytes($runtimeMemberPath)
    try {
        Write-Utf8 $runtimeMemberPath ($utf8.GetString($runtimeMemberBytes)+"`n# maintenance consumed-member drift`n")
        $runtimeMemberDrift=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $runtimeMemberReason=Get-IntegrationResolverFailure $runtimeMemberDrift 'runtime-content-drift'
        Assert-True ($runtimeMemberReason-ceq('RELEASE_PACKAGE_CONSUMED_MEMBER_DRIFT|'+$runtimeMember)) 'maintenance-resolver-runtime-content-drift-rejected'
    } finally { [IO.File]::WriteAllBytes($runtimeMemberPath,$runtimeMemberBytes) }
    try {
        $wrongRuntimeVersion=Get-Content -LiteralPath $runtimeManifestPath -Raw -Encoding utf8|ConvertFrom-Json
        $wrongRuntimeVersion.frameworkVersion='1.16.0'
        Write-Utf8 $runtimeManifestPath ($wrongRuntimeVersion|ConvertTo-Json -Depth 30)
        $wrongRuntimeVersionRun=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        # Bound manifest bytes are rejected before the modified version field is interpreted.
        $wrongRuntimeVersionReason=Get-IntegrationResolverFailure $wrongRuntimeVersionRun 'wrong-runtime-version'
        Assert-True ($wrongRuntimeVersionReason-ceq'RELEASE_FIXED_DISTRIBUTION_DRIFT') 'maintenance-resolver-wrong-runtime-version-rejected'
    } finally { [IO.File]::WriteAllBytes($runtimeManifestPath,$runtimeManifestBytes) }
    $adoptionStateBytes=[IO.File]::ReadAllBytes($adoptionStatePath)
    try {
        [IO.File]::Delete($adoptionStatePath)
        $noBinding=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        $noBindingReason=Get-IntegrationResolverFailure $noBinding 'missing-adopted-runtime'
        Assert-True ($noBindingReason-ceq'MAINTENANCE_FIXED_RUNTIME_BINDING_REQUIRED') 'maintenance-resolver-missing-adopted-runtime-rejected'
        [IO.File]::WriteAllBytes($adoptionStatePath,$adoptionStateBytes)
        $wrongRuntimeState=Get-Content -LiteralPath $adoptionStatePath -Raw -Encoding utf8|ConvertFrom-Json
        $wrongRuntimeState.metadata.distributionBinding.runtimeRoot=$target
        Write-Utf8 $adoptionStatePath ($wrongRuntimeState|ConvertTo-Json -Depth 100)
        $wrongRuntime=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity)
        # The stable fixture journal supplies the binding; the package observer rejects a development root.
        $wrongRuntimeReason=Get-IntegrationResolverFailure $wrongRuntime 'development-target-runtime'
        Assert-True ($wrongRuntimeReason-ceq'RELEASE_FIXED_DEVELOPMENT_ROOT') 'maintenance-resolver-development-target-cannot-substitute-fixed-runtime'
    } finally { [IO.File]::WriteAllBytes($adoptionStatePath,$adoptionStateBytes) }

    $badSiblingConfig = $configRaw | ConvertFrom-Json
    $badSiblingConfig.frameworkTarget.siblingDirectory = '..\AI-Workspace'
    Write-Utf8 $configPath ($badSiblingConfig | ConvertTo-Json -Depth 20)
    $badSiblingIdentity = Get-Identity $configPath
    $badSibling = Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$badSiblingIdentity)
    Write-Utf8 $configPath $configRaw
    Assert-True ($badSibling.Code -ne 0 -and $badSibling.Text.Contains('TARGET_SIBLING_COMPONENT')) 'maintenance-resolver-parent-traversal-rejected'
    Assert-True ((Get-Identity $configPath) -ceq $configIdentity) 'maintenance-fixture-config-restored'
}
} finally { if($integrationContext){Close-IntegrationContext $integrationContext} }
Write-Output ('RESULT|'+(Get-IntegrationCheckCount)+'/'+(Get-IntegrationCheckCount)+' passed|scope=Framework-2.0.0-maintenance|')
