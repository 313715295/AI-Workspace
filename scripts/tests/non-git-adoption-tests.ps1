#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$sourceRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pwsh=(Get-Command pwsh -CommandType Application).Source
$git=(Get-Command git -CommandType Application -ErrorAction SilentlyContinue).Source
$oldPath=$env:PATH;$utf8=[Text.UTF8Encoding]::new($false);$passed=0
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-nongit-adoption-'+[guid]::NewGuid().ToString('N'))
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 80 -Compress)}
function Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw "ASSERT_FAIL|$Name"};$script:passed++;Write-Output "PASS|$Name"}
function InvokeTool([string]$Tool,[hashtable]$Parameters){
 $invocation=Join-Path $temp ('call-'+[guid]::NewGuid().ToString('N')+'.json');SaveJson $invocation @{tool=$Tool;parameters=$Parameters}
 $lines=@(& $pwsh -NoProfile -NonInteractive -File $runner -InputPath $invocation 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
 $value=$null;if($code-eq0){$value=($lines-join"`n")|ConvertFrom-Json -Depth 100;if($value-is[string]-and$value.StartsWith('{')){$value=$value|ConvertFrom-Json -Depth 100}}
 return [pscustomobject]@{code=$code;value=$value;text=($lines-join"`n")}
}
function RunTool([string]$Tool,[hashtable]$Parameters){$result=InvokeTool $Tool $Parameters;if($result.code-ne0){throw ('TOOL_FAILED|'+[IO.Path]::GetFileName($Tool)+'|'+$result.text)};return $result.value}
function SealFixture([string]$Root){
 # Synthetic qualification exists only in this isolated fixture. It is not
 # source Review or release evidence for the working candidate.
 $p=Join-Path $Root 'VERSION.json';$o=Get-Content $p -Raw|ConvertFrom-Json;$o.lifecycle='STABLE';$o.consumable=$true;$o.projectPinEligible=$true;SaveJson $p $o
 $p=Join-Path $Root 'LOAD_MANIFEST.json';$o=Get-Content $p -Raw|ConvertFrom-Json;$o.lifecycle='STABLE';SaveJson $p $o
 [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'});[Array]::Sort($paths,[StringComparer]::Ordinal)
 $rows=@();[long]$bytes=0;foreach($relative in $paths){$id=Identity (Join-Path $Root $relative);$bytes+=[long]$id.Split('|')[0];$rows+=($relative+'|'+$id)}
 $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($rows-join"`n")))
 $p=Join-Path $Root 'RELEASE_MANIFEST.json';$before=Identity $p;$o=Get-Content $p -Raw|ConvertFrom-Json
 $o.lifecycle='STABLE';$o.fileCount=$paths.Count;$o.totalBytes=$bytes;$o.canonical=$canonical;$o.sourceReview='APPROVED';$o.sourceCandidate='TEST_FIXTURE_NON_GIT'
 $o.completeSuite=[pscustomobject]@{status='PASS';passed=1;total=1;payloadCanonical=$canonical;evidenceIdentity=('1|'+('A'*64))}
 $o.sourceReviewEvidence=[pscustomobject]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$canonical;reviewedManifestIdentity=$before};$o.releaseIntegration='ISOLATED_TEST_FIXTURE';SaveJson $p $o
}
try{
 $workspace=Join-Path $temp 'framework';$project=Join-Path $temp 'project'
 $null=[IO.Directory]::CreateDirectory($project)
 foreach($relative in @('scripts/register-project.ps1','scripts/upgrade-project.ps1','scripts/ProjectAdoptionState.psm1','scripts/ProjectAdoptionProjection.psm1','scripts/ProjectAdoptionTransaction.psm1','scripts/MaintenanceOverlay.psm1','skills/ai-workspace-router/SKILL.md','skills/ai-workspace-router-v2/SKILL.md')){
  $destination=Join-Path $workspace $relative;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $destination));Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination
 }
 foreach($version in @('1.16.0','2.0.0')){$destination=Join-Path $workspace ('framework/versions/'+$version);$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $destination));Copy-Item -LiteralPath (Join-Path $sourceRoot ('framework/versions/'+$version)) -Destination $destination -Recurse;SealFixture $destination}
 Copy-Item -LiteralPath (Join-Path $sourceRoot 'framework/maintenance-overlay') -Destination (Join-Path $workspace 'framework/maintenance-overlay') -Recurse
 $runner=Join-Path $temp 'invoke-tool.ps1'
 SaveText $runner @'
param([string]$InputPath)
$ErrorActionPreference='Stop'
try {
 $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
 $parameters=$call.parameters;$LASTEXITCODE=0
 $output=@(& $call.tool @parameters)
 if($LASTEXITCODE-ne0){$output|ForEach-Object{Write-Output $_};exit $LASTEXITCODE}
 if($output.Count-eq1){$output[0]|ConvertTo-Json -Depth 100 -Compress}else{ConvertTo-Json -InputObject $output -Depth 100 -Compress}
}catch{Write-Output $_.Exception.Message;exit 1}
'@
 $env:PATH=$PSHOME+[IO.Path]::PathSeparator+[Environment]::GetFolderPath('System')
 Check ($null-eq(Get-Command git -ErrorAction SilentlyContinue)) 'git-executable-absent-from-test-environment'
 $register=Join-Path $workspace 'scripts/register-project.ps1';$upgrade=Join-Path $workspace 'scripts/upgrade-project.ps1'
 $parameters=@{ProjectId='nongit-fixture';DisplayName='Non Git fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$workspace}
 $preview=RunTool $register $parameters
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace'))) 'registration-preview-does-not-write'
 $parameters.Apply=$true;$registered=RunTool $register $parameters
 $configPath=Join-Path $project '.ai-workspace/project.json';$config=Get-Content $configPath -Raw|ConvertFrom-Json
 Check ($config.frameworkVersion-ceq'2.0.0'-and$config.id-ceq'nongit-fixture') 'non-git-registers-selected-version'
 $agents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
 Check ($agents.Contains('`ai-workspace-router-v2`')-and-not$agents.Contains('{{ROUTER_SKILL_NAME}}')) 'non-git-registration-renders-target-router-name'
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.git'))-and-not(Test-Path -LiteralPath (Join-Path $project '.gitignore'))) 'registration-creates-no-git-or-ignore-file'
 Check (-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md'))-and-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace/RELATIONSHIPS.md'))) 'new-starter-removes-special-review-and-relationship-carriers'
 Check ($config.schemaVersion-eq5) 'new-target-registers-profile-declared-project5'
 $config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@(
  [pscustomobject]@{id='project';root=[pscustomobject]@{kind='PROJECT';locator='.'};indexLocator='.ai-workspace/knowledge/index.json';selectionHints=@('project facts');updatePolicy='FOLLOW'},
  [pscustomobject]@{id='shared';root=[pscustomobject]@{kind='LOCAL_DIRECTORY';locator=(Join-Path $temp 'unavailable-library')};indexLocator='index.json';selectionHints=@('reference');updatePolicy='FOLLOW'}
 )}}
 SaveJson $configPath $config
 $repeated=RunTool $register $parameters
 Check ($repeated.status-ceq'ALREADY_REGISTERED') 'non-git-repeat-registration-is-idempotent'
 Check (-not(Test-Path -LiteralPath (Join-Path $temp 'unavailable-library'))-and-not(Test-Path -LiteralPath (Join-Path $project '.ai-workspace/knowledge'))) 'registration-validates-multiple-sources-without-opening-or-creating-them'
 $goodConfig=[IO.File]::ReadAllText($configPath)
 $config.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled=$false
 $config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].root.locator='../unsafe'
 SaveJson $configPath $config
 $bad=InvokeTool $register $parameters
 Check ($bad.code-ne0-and$bad.text.Contains('KNOWLEDGE_ROOT_ABSOLUTE_REQUIRED')) 'registration-validates-disabled-source-structure'
 SaveText $configPath $goodConfig
 $duplicate=$goodConfig.Replace('"id":"shared"','"id":"shared","\u0069d":"duplicate"');SaveText $configPath $duplicate
 $bad=InvokeTool $register $parameters
 Check ($bad.code-ne0-and$bad.text.Contains('duplicate')) 'registration-rejects-real-nested-unicode-duplicate'
 SaveText $configPath $goodConfig
 SaveText (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md') 'Existing project-owned quality requirements.'
 $preserved=Identity (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md')
 $null=RunTool $register $parameters
 Check ((Identity (Join-Path $project '.ai-workspace/REVIEW_PROFILE.md'))-ceq$preserved) 'old-named-project-document-is-preserved'
 $same=RunTool $upgrade @{ProjectId='nongit-fixture';RepositoryPath=$project;ToVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$workspace}
 Check (($same-join"`n").Contains('objects=0')) 'non-git-upgrade-preview-recognizes-current-state'
 $same=RunTool $upgrade @{ProjectId='nongit-fixture';RepositoryPath=$project;ToVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$workspace;Apply=$true}
 Check (($same-join"`n").Contains('ALREADY_UPGRADED')) 'non-git-same-pin-apply-is-no-op'

 $versionRoot=Join-Path $workspace 'framework/versions/2.0.0';$resolver=Join-Path $versionRoot 'scripts/resolve-process-requirements.ps1'
 $task=Join-Path $project '.ai-workspace/tasks/active/NONGIT-001.md';$source=Join-Path $project 'artifact.txt'
 SaveText $task "# NONGIT-001`n- Owner: owner-fixture`n- Work route: actor=owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; risk=MEDIUM; size=SMALL; uncertainty=LOW"
 SaveText $source 'before'
 $input=[ordered]@{schemaVersion=3;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$project;frameworkRoot=$workspace;taskPath=$task;expectedProjectConfigIdentity=(Identity $configPath);expectedCorrectionsIdentity=(Identity (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=(Identity $task);observedActor='owner-fixture';capabilities=@();exactPaths=@();forbiddenPaths=@('private/');protectedPaths=@('.ai-workspace/');authorizationPackagePath='NOT_REQUIRED';expectedAuthorizationIdentity='NOT_REQUIRED';userDecision='NOT_REQUIRED';recoveryState='FULL_COLD';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Understand the current task';requestedActionKind='NONE';requestedResultKind='PLAN';semanticHints=@('task analysis');pathHints=@();capabilityHints=@();mutationHints=@();externalHints=@();ambiguityState='CLEAR'}}
 $input.evaluationOnly=$false;$input.capabilities=@('KNOWLEDGE_REFERENCE')
 $inputPath=Join-Path $temp 'process-input.json';SaveJson $inputPath $input
 $loaded=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($loaded.status-ceq'PASS'-and$loaded.compactReceipt.binding.repositoryGitTop-ceq'NOT_APPLICABLE') 'ordinary-recovery-does-not-invent-git-authority'
 $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='NONGIT-001';profile='STANDARD';lifecycle='ACTIVE';owner='owner-fixture';issuer='owner-fixture';issuerRole='TASK_OWNER';grantee='owner-fixture';bundle='PLAN_LOCAL';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Identity $task);actions=@('SOURCE_WRITE');exactPaths=@('artifact.txt');objectIdentities=@(@{path='artifact.txt';identity=(Identity $source)});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT');projectConfigIdentity=(Identity $configPath)}
 $packagePath=Join-Path $project '.ai-workspace/runtime/NONGIT-001/owner-fixture/action.json';SaveJson $packagePath $package
 $input.authorizationPackagePath=$packagePath;$input.expectedAuthorizationIdentity=Identity $packagePath;$input.exactPaths=@('artifact.txt');$input.intentEnvelope.requestedActionKind='SOURCE_WRITE';$input.intentEnvelope.requestedResultKind='IMPLEMENTATION_RESULT';$input.intentEnvelope.semanticHints=@('implementation');$input.intentEnvelope.pathHints=@('artifact.txt');SaveJson $inputPath $input
 $write=RunTool $resolver @{InputPath=$inputPath;AsJson=$true};$receiptPath=Join-Path $temp 'write-receipt.json';SaveJson $receiptPath $write.compactReceipt
 $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Identity $receiptPath);preparationReceipts=@($write.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
 SaveJson $inputPath $boundary;$admit=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($admit.status-ceq'PASS') 'ordinary-source-write-admitted-without-git'
 SaveText $source 'after'
 $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($write.compactReceipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|artifact.txt|'+(Identity $source));SaveJson $inputPath $boundary
 $final=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($final.status-ceq'PASS'-and[IO.File]::ReadAllText($source).Trim()-ceq'after') 'ordinary-source-write-finalizes-without-git'
 $package.grantee='reviewer-fixture';$package.actions=@('REVIEW_EXECUTE');$package.reviewIndependence='INDEPENDENT';$package.objectIdentities=@(@{path='artifact.txt';identity=(Identity $source)});SaveJson $packagePath $package
 $input.expectedAuthorizationIdentity=Identity $packagePath;$input.observedActor='reviewer-fixture';$input.intentEnvelope.requestedActionKind='REVIEW_EXECUTE';$input.intentEnvelope.requestedResultKind='REVIEW_VERDICT';$input.intentEnvelope.semanticHints=@('review');SaveJson $inputPath $input
 $review=RunTool $resolver @{InputPath=$inputPath;AsJson=$true};$receiptPath=Join-Path $temp 'review-receipt.json';SaveJson $receiptPath $review.compactReceipt
 $boundary.mode='ADMIT_ACTION';$boundary.discoverReceiptPath=$receiptPath;$boundary.expectedDiscoverReceiptIdentity=Identity $receiptPath;$boundary.preparationReceipts=@($review.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);$boundary.resultReceipts=@();SaveJson $inputPath $boundary
 $reviewAdmit=RunTool $resolver @{InputPath=$inputPath;AsJson=$true}
 Check ($reviewAdmit.status-ceq'PASS'-and$review.compactReceipt.binding.role-ceq'REVIEWER') 'pure-review-admission-does-not-require-git'
 $gitAction=InvokeTool (Join-Path $versionRoot 'scripts/invoke-protected-safe-git.ps1') @{ProjectRoot=$project;Operation='STATUS';AllowPath=@('artifact.txt');ExpectedProjectConfigIdentity=(Identity $configPath)}
 Check ($gitAction.code-ne0) 'real-git-operation-still-rejects-unavailable-git'

 foreach($module in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction','MaintenanceOverlay')){Import-Module (Join-Path $workspace ('scripts/'+$module+'.psm1')) -Force}
 # Exercise the actual target-before-pin implementation without manufacturing
 # a supported cross-version migration. W5 separately owns that bridge.
 $tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($upgrade,[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw 'UPGRADE_PARSE'}
 $definitions=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$false)|ForEach-Object{$_.Extent.Text})-join"`n"
 $preflightModule=New-Module -Name NonGitPreflightFixture -ScriptBlock ([scriptblock]::Create($definitions))
 $preflight=& $preflightModule {
  param($project,$workspace,$task)
  $AuthorizationPackagePath='';$ExpectedAuthorizationPackageIdentity='';$CurrentProcessInputPath='';$ExpectedCurrentProcessInputIdentity='';$AdoptionProcessMode='';$Apply=$false;$SelectedRulePackBytes=32768
  $script:utf8NoBom=[Text.UTF8Encoding]::new($false);$script:utf8Strict=[Text.UTF8Encoding]::new($false,$true)
  $script:ActiveAdoptionProfile=$null;$script:ActiveTargetCapabilityContract=$null
  $migration=[pscustomobject]@{Relative='.ai-workspace/tasks/active/NONGIT-001.md';Content=[IO.File]::ReadAllText($task);Actor='owner-fixture'}
  Get-TargetProjectedProcessPreflight $project $workspace '2.0.0' 'nongit-fixture' $migration ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/project.json'))) ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/BOOTSTRAP.md'))) ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/corrections.json'))) ([IO.File]::ReadAllText((Join-Path $project '.ai-workspace/process-policy.json'))) (Join-Path $project '.ai-workspace/controller.json') -ReadOnlyCandidateRefresh
 } $project $workspace $task
 Check ($preflight.ResolverReason-ceq'PASS'-and$null-eq(Get-Command git -ErrorAction SilentlyContinue)) 'target-before-pin-preflight-needs-no-git-program-or-projection-repository'
 Remove-Module $preflightModule
 $objects=@([pscustomobject]@{path='artifact.txt';text='transitioned'},[pscustomobject]@{path='new.txt';text='created'})
 foreach($step in @(0,1,2)){
  SaveText $source 'after';$projection=New-AiwProjectProjection $project $objects;$relative='.ai-workspace/upgrade-recovery/nongit-'+$step+'/state.json'
  $interrupted=Invoke-AiwProjectProjectionTransaction $project $projection $relative {$true} {$true} -InterruptAfterWrite $step
  Check ($interrupted.status-ceq'INTERRUPTED') ('non-git-transaction-interruption-'+$step)
  $rollback=Resume-AiwProjectProjectionRollback $project $relative (Identity (Join-Path $project $relative)) {$true}
  Check ($rollback.status-ceq'ROLLED_BACK'-and[IO.File]::ReadAllText($source).Trim()-ceq'after'-and-not(Test-Path -LiteralPath (Join-Path $project 'new.txt'))) ('non-git-transaction-recovery-'+$step)
 }
 $reason='';try{Resolve-AiwMaintenanceTopology -ControlRepositoryPath $project -TargetRepositoryId fixture-target -TargetSiblingDirectory target -TargetRoutineExcludedPaths @()|Out-Null}catch{$reason=$_.Exception.Message}
 Check (-not[string]::IsNullOrWhiteSpace($reason)) 'maintenance-topology-still-requires-real-git-conditions'
 $toolchain=Get-Content (Join-Path $versionRoot 'TOOLCHAIN.json') -Raw|ConvertFrom-Json;$toolchain.routerCompatibility.skillName='ai-workspace-router'
 $reason='';try{Get-AiwNavigationContract $toolchain|Out-Null}catch{$reason=$_.Exception.Message}
 Check ($reason-like'FRAMEWORK_ROUTER_*') 'contract-two-cannot-use-old-shared-skill'
 $env:PATH=$oldPath
 if([string]::IsNullOrWhiteSpace($git)){throw 'GIT_REGRESSION_TOOL_UNAVAILABLE'}
 $gitProject=Join-Path $temp 'git-project';$null=[IO.Directory]::CreateDirectory($gitProject);& $git -C $gitProject init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_GIT_INIT'}
 $parameters.RepositoryPath=$gitProject;$parameters.FrameworkVersion='1.16.0';$null=RunTool $register $parameters
 Check ([IO.File]::ReadAllText((Join-Path $gitProject '.gitignore')).Contains('/.ai-workspace/runtime/')) 'git-project-keeps-runtime-ignore-projection'
 Check (Test-Path -LiteralPath (Join-Path $gitProject '.ai-workspace/REVIEW_PROFILE.md')) 'old-version-keeps-its-owned-template-contract'
 $nested=Join-Path $gitProject 'nested-project';$null=[IO.Directory]::CreateDirectory($nested);$parameters.RepositoryPath=$nested;$parameters.FrameworkVersion='2.0.0';$null=RunTool $register $parameters
 Check ((Test-Path -LiteralPath (Join-Path $nested '.ai-workspace/project.json'))-and-not(Test-Path -LiteralPath (Join-Path $nested '.git'))) 'explicit-subproject-root-is-not-promoted-to-parent-git-root'
 $gitKnowledge=Join-Path $temp 'git-knowledge';$null=[IO.Directory]::CreateDirectory($gitKnowledge);& $git -C $gitKnowledge init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_GIT_INIT'}
 $parameters.RepositoryPath=$gitKnowledge;$null=RunTool $register $parameters
 $gitConfigPath=Join-Path $gitKnowledge '.ai-workspace/project.json';$gitConfig=Get-Content $gitConfigPath -Raw|ConvertFrom-Json
 $gitConfig.frameworkCapabilities=($goodConfig|ConvertFrom-Json).frameworkCapabilities;SaveJson $gitConfigPath $gitConfig;SaveText (Join-Path $gitKnowledge 'artifact.txt') 'fixture'
 $safeTool=Join-Path $versionRoot 'scripts/invoke-protected-safe-git.ps1'
 $safe=InvokeTool $safeTool @{ProjectRoot=$gitKnowledge;Operation='STATUS';AllowPath=@('artifact.txt');ExpectedProjectConfigIdentity=(Identity $gitConfigPath)}
 Check ($safe.code-eq0-and$safe.text.Contains('artifact.txt')) 'safe-git-accepts-valid-multi-source-config-with-unavailable-library'
 $gitConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled=$false;$gitConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].root.locator='../escape';SaveJson $gitConfigPath $gitConfig
 $safe=InvokeTool $safeTool @{ProjectRoot=$gitKnowledge;Operation='STATUS';AllowPath=@('artifact.txt');ExpectedProjectConfigIdentity=(Identity $gitConfigPath)}
 Check ($safe.code-ne0-and$safe.text.Contains('KNOWLEDGE_ROOT_ABSOLUTE_REQUIRED')) 'safe-git-rejects-invalid-disabled-source-before-git'

 foreach($relative in @('README.md','scripts/resolve-framework-maintenance-target.ps1','scripts/check-framework-maintenance-authorization.ps1','scripts/invoke-framework-maintenance-safe-git.ps1','scripts/resolve-framework-maintenance-process-requirements.ps1')){Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination (Join-Path $workspace $relative)}
 & $git -C $workspace init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_TARGET_GIT_INIT'}
 $maintenance=Join-Path $temp 'maintenance';$null=[IO.Directory]::CreateDirectory($maintenance);& $git -C $maintenance init -q;if($LASTEXITCODE-ne0){throw 'ISOLATED_CONTROL_GIT_INIT'}
 $maintenanceArgs=@{ProjectId='maintenance-fixture';DisplayName='Maintenance fixture';RepositoryPath=$maintenance;FrameworkVersion='2.0.0';ControllerId='owner-fixture';WorkspaceRoot=$workspace;ControlPlaneLayout='framework-maintenance-sibling';FrameworkTargetRepositoryId='fixture-target';FrameworkTargetSiblingDirectory='framework';Apply=$true}
 $null=RunTool $register $maintenanceArgs
 $maintenancePath=Join-Path $maintenance '.ai-workspace/project.json';$maintenanceConfig=Get-Content $maintenancePath -Raw|ConvertFrom-Json
 Check ($maintenanceConfig.schemaVersion-eq5) 'maintenance-registers-target-profile-project5'
 $maintenanceConfig.frameworkCapabilities=($goodConfig|ConvertFrom-Json).frameworkCapabilities;SaveJson $maintenancePath $maintenanceConfig
 $null=RunTool $register $maintenanceArgs
 $maintenanceResolver=Join-Path $workspace 'scripts/resolve-framework-maintenance-target.ps1'
 $resolved=RunTool $maintenanceResolver @{ControlRepositoryPath=$maintenance;ExpectedProjectConfigIdentity=(Identity $maintenancePath);AsJson=$true}
 Check ($resolved.status-ceq'PASS'-and$resolved.controlRoot-ceq$maintenance-and$resolved.targetRoot-ceq$workspace) 'maintenance-multi-source-config-preserves-real-sibling-topology'
 $maintenanceConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled=$false;$maintenanceConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].root.locator='../escape';SaveJson $maintenancePath $maintenanceConfig
 $resolved=InvokeTool $maintenanceResolver @{ControlRepositoryPath=$maintenance;ExpectedProjectConfigIdentity=(Identity $maintenancePath);AsJson=$true}
 Check ($resolved.code-ne0-and$resolved.text.Contains('KNOWLEDGE_ROOT_ABSOLUTE_REQUIRED')) 'maintenance-rejects-invalid-disabled-source-using-common-validator'
 $outside=Join-Path $temp 'outside';$null=[IO.Directory]::CreateDirectory((Join-Path $outside 'child'));$junction=Join-Path $temp 'root-link'
 $null=New-Item -ItemType Junction -Path $junction -Target $outside
 try{
  $parameters.RepositoryPath=Join-Path $junction 'child';$rejected=InvokeTool $register $parameters
  Check ($rejected.code-ne0-and$rejected.text.Contains('REPOSITORY_ROOT_REPARSE')-and-not(Test-Path -LiteralPath (Join-Path $outside 'child/.ai-workspace'))) 'intermediate-root-junction-rejected-before-registration'
 }finally{Remove-Item -LiteralPath $junction -Force}
 Write-Output ('NON_GIT_ADOPTION_TESTS_PASS|checks='+$passed+'|evidence=ISOLATED_REGISTER_LOAD_ACTIONS_SAME_PIN_AND_RECOVERY|crossVersionBridge=PENDING_W5')
}finally{
 $env:PATH=$oldPath
 $resolved=[IO.Path]::GetFullPath($temp);$systemTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
 if([IO.Path]::GetDirectoryName($resolved)-cne$systemTemp-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-nongit-adoption-[a-f0-9]{32}$'){throw 'FIXTURE_CLEANUP_BOUNDARY'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
