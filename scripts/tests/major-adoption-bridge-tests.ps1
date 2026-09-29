#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LegacyRuntimeRoot,
    [ValidateSet('ALL','ORDINARY','MAINTENANCE')][string]$Layout='ALL',
    [switch]$CoreOnly,
    [switch]$KeepFixture
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$sourceRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pwsh=(Get-Command pwsh -CommandType Application).Source
$utf8=[Text.UTF8Encoding]::new($false);$passed=0
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-major-bridge-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
function SaveText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n").TrimEnd("`n")+"`n",$utf8)}
function SaveJson([string]$Path,$Value){SaveText $Path ($Value|ConvertTo-Json -Depth 100 -Compress)}
function Id([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return 'NEW'};$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function CopyFile([string]$From,[string]$To){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $To));Copy-Item -LiteralPath $From -Destination $To}
function InvokeTool([string]$Tool,[hashtable]$Parameters){
    $call=Join-Path $temp ('call-'+[guid]::NewGuid().ToString('N')+'.json');SaveJson $call @{tool=$Tool;parameters=$Parameters}
    $output=@(& $pwsh -NoProfile -NonInteractive -File $runner -InputPath $call 2>&1|ForEach-Object{[string]$_})
    $code=$LASTEXITCODE;$value=$null
    if($code-eq0){$value=($output-join"`n")|ConvertFrom-Json -Depth 100;if(@($value).Count-eq1-and@($value)[0]-is[string]-and@($value)[0].StartsWith('{')){$value=@($value)[0]|ConvertFrom-Json -Depth 100}}
    return [pscustomobject]@{code=$code;value=$value;text=($output-join"`n")}
}
function Run([string]$Tool,[hashtable]$Parameters){$result=InvokeTool $Tool $Parameters;if($result.code-ne0){throw ('TOOL_FAILED|'+[IO.Path]::GetFileName($Tool)+'|'+$result.text)};return $result.value}
function Reject([string]$Tool,[hashtable]$Parameters,[string]$Reason,[string]$Name){$result=InvokeTool $Tool $Parameters;if($result.code-eq0-or-not$result.text.Contains($Reason)){throw ('UNEXPECTED_REJECTION|'+$Name+'|'+$result.text)};Check $true $Name}
function Clone($Value){return ($Value|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100 -AsHashtable)}
function RejectCall([scriptblock]$Call,[string]$Reason,[string]$Name){$failure=$null;try{& $Call|Out-Null}catch{$failure=$_.Exception.Message};if(-not$failure-or-not$failure.Contains($Reason)){throw ('UNEXPECTED_REJECTION|'+$Name+'|'+$failure)};Check $true $Name}
function SealFixture([string]$Root){
    # Isolated test qualification only: no release, Source Review, package build
    # or installation of the working source is performed by this fixture.
    [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'})
    [Array]::Sort($paths,[StringComparer]::Ordinal);$rows=@();[long]$size=0
    foreach($path in $paths){$identity=Id (Join-Path $Root $path);$rows+=($path+'|'+$identity);$size+=[long]$identity.Split('|')[0]}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($rows-join"`n")))
    $manifestPath=Join-Path $Root 'RELEASE_MANIFEST.json';$before=Id $manifestPath;$manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json
    $manifest.fileCount=$paths.Count;$manifest.totalBytes=$size;$manifest.canonical=$canonical;$manifest.sourceReview='APPROVED';$manifest.sourceCandidate='ISOLATED_MAJOR_BRIDGE_FIXTURE';$manifest.releaseIntegration='PENDING'
    $manifest.completeSuite=[pscustomobject]@{status='PASS';passed=1;total=1;payloadCanonical=$canonical;evidenceIdentity=('1|'+('A'*64))}
    $manifest.sourceReviewEvidence=[pscustomobject]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$canonical;reviewedManifestIdentity=$before}
    SaveJson $manifestPath $manifest
}
function NamedFixture([string]$Root,[string]$DistributionId='2.0.0-snapshot.1'){
    [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'PACKAGE_MANIFEST.json'})
    [Array]::Sort($paths,[StringComparer]::Ordinal);$files=@();$rows=@()
    foreach($path in $paths){$identity=Id (Join-Path $Root $path);$files+=@([ordered]@{path=$path;identity=$identity});$rows+=($path+'='+$identity)}
    $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($rows-join"`n")+"`n")))
    SaveJson (Join-Path $Root 'PACKAGE_MANIFEST.json') ([ordered]@{schemaVersion=2;frameworkVersion='2.0.0';provisional=$true;canonical=$canonical;files=$files;distributionId=$DistributionId})
}
function RestoreFixture([string]$Root,$Projection){
    foreach($entry in $Projection.objects){
        $path=Get-AiwContainedPath $Root $entry.path
        if($entry.oldExists){[IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($entry.oldBase64))}
        elseif(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
    }
    $state=Get-AiwContainedPath $Root '.ai-workspace/runtime/project-adoption/upgrade/state.json'
    if(Test-Path -LiteralPath $state -PathType Leaf){[IO.File]::Delete($state)}
    $empty=Get-AiwContainedPath $Root '.ai-workspace/upgrade-recovery/2.0.0'
    if((Test-Path -LiteralPath $empty -PathType Container)-and[IO.Directory]::GetFileSystemEntries($empty).Count-eq0){[IO.Directory]::Delete($empty,$false)}
}
function RestoreRefreshFixture([string]$Root,$Projection){
    foreach($entry in $Projection.objects){
        $path=Get-AiwContainedPath $Root $entry.path
        if($entry.oldExists){[IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($entry.oldBase64))}
        elseif(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
    }
    $path=Get-AiwContainedPath $Root '.ai-workspace/runtime/project-adoption/refresh/state.json'
    if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
}
function NewRefreshAction([hashtable]$Scope,[string]$TargetRuntime,$Template,[string]$PackagePath){
    $arguments=$Scope.Clone();$arguments.WorkspaceRoot=$TargetRuntime
    $arguments.ExpectedActorRouteTaskIdentity=Id (Join-Path $arguments.RepositoryPath $arguments.ActorRouteTaskPath)
    $tool=Join-Path $TargetRuntime 'scripts/upgrade-project.ps1';$preview=Run $tool $arguments
    $pre=@{};$post=@{};$paths=@();$canonical='';$manifest=''
    foreach($line in $preview){
        if($line-match'^UPGRADE_PREIMAGE\|(?<path>.+)=(?<id>NEW|\d+\|[A-F0-9]{64})$'){$pre[$Matches.path]=$Matches.id}
        elseif($line-match'^UPGRADE_POSTIMAGE\|(?<path>.+)=(?<id>ABSENT|\d+\|[A-F0-9]{64})$'){$post[$Matches.path]=$Matches.id}
        elseif($line-match'^UPGRADE_WRITESET\|(?<paths>.+)$'){$paths=@($Matches.paths-split'\|')}
        elseif($line-match'^UPGRADE_TARGET_RELEASE\|canonical=(?<hash>[A-F0-9]{64})\|manifest=(?<id>\d+\|[A-F0-9]{64})$'){$canonical=$Matches.hash;$manifest=$Matches.id}
    }
    if($paths.Count-lt1-or$pre.Count-ne$paths.Count-or$post.Count-ne$paths.Count-or-not$canonical-or-not$manifest){throw 'REFRESH_PREVIEW_INCOMPLETE'}
    $authorization=Clone $Template;$authorization.taskIdentity=$arguments.ExpectedActorRouteTaskIdentity
    $authorization.projectConfigIdentity=Id (Join-Path $arguments.RepositoryPath '.ai-workspace/project.json')
    $authorization.controllerControlIdentity=Id (Join-Path $arguments.RepositoryPath '.ai-workspace/controller.json')
    $authorization.userConfirmation='ISOLATED_TEST_APPROVED_RUNTIME_REFRESH';$authorization.exactPaths=$paths
    $authorization.objectIdentities=@($paths|ForEach-Object{[ordered]@{path=$_;identity=$pre[$_]}})
    $authorization.postObjectIdentities=@($paths|ForEach-Object{[ordered]@{path=$_;identity=$post[$_]}})
    $authorization.targetFrameworkSnapshot=@{canonical=$canonical;manifestIdentity=$manifest};SaveJson $PackagePath $authorization
    $arguments.Apply=$true;$arguments.AuthorizationPackagePath=$PackagePath;$arguments.ExpectedAuthorizationPackageIdentity=Id $PackagePath
    return [pscustomobject]@{tool=$tool;arguments=$arguments;authorization=$authorization}
}
function ReadCurrent([string]$TargetRuntime,[string]$Case,$InputTemplate,[string]$InputPath,[switch]$AllowFailure){
    $request=Clone $InputTemplate;$request.frameworkRoot=$TargetRuntime
    $request.expectedProjectConfigIdentity=Id (Join-Path $request.projectRoot '.ai-workspace/project.json')
    $request.expectedCorrectionsIdentity=Id (Join-Path $request.projectRoot '.ai-workspace/corrections.json')
    $request.expectedTaskIdentity=Id $request.taskPath;SaveJson $InputPath $request
    $tool=if($Case-ceq'MAINTENANCE'){Join-Path $TargetRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $TargetRuntime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
    if($AllowFailure){
        $actual=InvokeTool $tool @{InputPath=$InputPath;AsJson=$true}
        $value=if($actual.code-eq0){$actual.value}else{$actual.text|ConvertFrom-Json -Depth 100}
        $value|Add-Member fixtureExitCode $actual.code
        return $value
    }
    return Run $tool @{InputPath=$InputPath;AsJson=$true}
}
try {
    $runner=Join-Path $temp 'invoke.ps1'
    SaveText $runner @'
param([string]$InputPath)
$ErrorActionPreference='Stop'
try {
    $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -AsHashtable
    $arguments=$call.parameters;$LASTEXITCODE=0
    $output=@(& $call.tool @arguments)
    if($LASTEXITCODE-ne0){$output|ForEach-Object{Write-Output $_};exit $LASTEXITCODE}
    ConvertTo-Json -InputObject $output -Depth 100 -Compress
} catch { Write-Output ($_.Exception.Message+'|'+$_.ScriptStackTrace);exit 2 }
'@
    $workspace=Join-Path $temp 'runtime-2'
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'scripts') -File){CopyFile $file.FullName (Join-Path $workspace ('scripts/'+$file.Name))}
    foreach($relative in @('framework/versions/2.0.0','framework/maintenance-overlay','skills/ai-workspace-router-v2')){
        $destination=Join-Path $workspace $relative;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $destination));Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination -Recurse
    }
    foreach($name in @('README.md','AGENTS.md')){CopyFile (Join-Path $sourceRoot ('framework/user-package/'+$name)) (Join-Path $workspace $name)}
    SealFixture (Join-Path $workspace 'framework/versions/2.0.0');NamedFixture $workspace
    $refreshRuntimes=@(foreach($number in 2..3){
        $next=Join-Path $temp ('runtime-2-refresh-'+$number);Copy-Item -LiteralPath $workspace -Destination $next -Recurse
        foreach($relative in @('framework/versions/2.0.0/project-starter/BOOTSTRAP.md','framework/maintenance-overlay/BOOTSTRAP.md')){
            $path=Join-Path $next $relative;$text=Get-Content -LiteralPath $path -Raw
            SaveText $path ($text.Replace('<!-- FRAMEWORK-MANAGED:END -->',("<!-- isolated refresh fixture {0} -->`n<!-- FRAMEWORK-MANAGED:END -->"-f$number)))
        }
        SealFixture (Join-Path $next 'framework/versions/2.0.0');NamedFixture $next ('2.0.0-snapshot.'+$number);$next
    })
    foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $workspace ('scripts/'+$name+'.psm1')) -Force}
    $legacy=Get-AiwDistributionBinding $LegacyRuntimeRoot '1.16.0' -Required
    Check ($legacy.distributionId-ceq'1.16.0-snapshot.12') 'actual-unchanged-snapshot12-runtime'
    $upgrade=Join-Path $workspace 'scripts/upgrade-project.ps1'
    $layouts=if($Layout-ceq'ALL'){@('MAINTENANCE','ORDINARY')}else{@($Layout)}
    foreach($case in $layouts){
        $project=Join-Path $temp ($case.ToLowerInvariant()+'/control');$null=[IO.Directory]::CreateDirectory($project)
        # The actual old runtime requires Git. Target-version no-Git behavior is
        # covered by non-git-adoption-tests; these fixtures do not rewrite it.
        & git init -q $project;if($LASTEXITCODE-ne0){throw 'FIXTURE_GIT_INIT'}
        $projectId='major-'+$case.ToLowerInvariant();$actor='major-owner';$taskRelative='.ai-workspace/tasks/active/MAJOR-001.md'
        $sourceRole=if($case-ceq'MAINTENANCE'){'FRAMEWORK_MAINTAINER'}else{'DOMAIN_OWNER'}
        $paths=@('.ai-workspace/upgrade-recovery/1.16.0/state.json','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','AGENTS.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','.ai-workspace/upgrade-recovery/2.0.0/state.json',$taskRelative)
        $config=[ordered]@{schemaVersion=4;id=$projectId;displayName='Major bridge fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@('private');frameworkCapabilities=[pscustomobject]@{};processPolicy=[ordered]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}
        $standardRelative='.ai-workspace/standards/quality.md';$standardPath=Join-Path $project $standardRelative
        SaveText $standardPath 'Preserve the project owner and verify the declared result before acceptance.'
        $standardBytes=[IO.File]::ReadAllBytes($standardPath)
        $templateRoot=Join-Path $LegacyRuntimeRoot 'framework/versions/1.16.0/project-starter'
        if($case-ceq'MAINTENANCE'){
            $target=Join-Path (Split-Path -Parent $project) 'target';$null=[IO.Directory]::CreateDirectory($target);& git init -q $target;if($LASTEXITCODE-ne0){throw 'FIXTURE_TARGET_GIT_INIT'}
            SaveText (Join-Path $target 'README.md') 'Synthetic source target for the isolated bridge fixture.'
            $config.controlPlaneLayout='framework-maintenance-sibling';$config.frameworkTarget=[ordered]@{repositoryId='fixture-framework';siblingDirectory='target';routineExcludedPaths=@('private')}
            $templateRoot=Join-Path $LegacyRuntimeRoot 'framework/maintenance-overlay'
        }else{
            $config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;indexLocator='.ai-workspace/knowledge/index.json'}}
            $knowledgeRelative='.ai-workspace/knowledge/example.md';SaveText (Join-Path $project $knowledgeRelative) 'Fixture project-derived knowledge with a real source dependency.'
            $entry=[ordered]@{id='example';state='CURRENT';title='Fixture reference';summary='Project-derived test reference';locator=$knowledgeRelative;identity=(Id (Join-Path $project $knowledgeRelative));verifiedAt='2026-09-27T00:00:00Z';authorityLocator=$standardRelative;authorityIdentity=(Id $standardPath);invalidatesOn=@('LOCATOR_IDENTITY_CHANGE','AUTHORITY_IDENTITY_CHANGE');tokenEstimate=32}
            SaveJson (Join-Path $project '.ai-workspace/knowledge/index.json') @{schemaVersion=1;projectId=$projectId;entries=@($entry)}
            $paths+=@('.ai-workspace/knowledge/index.json')
        }
        SaveJson (Join-Path $project '.ai-workspace/project.json') $config
        SaveJson (Join-Path $project '.ai-workspace/controller.json') @{schemaVersion=1;projectId=$projectId;controllerId=$actor;controllerEpoch=1;state='CURRENT'}
        $rule=[ordered]@{ruleId='PRESERVE_TEST_STANDARD';selectors=[ordered]@{profiles=@('CRITICAL');roles=@($sourceRole);phases=@('IMPLEMENT');actionKinds=@('CONTROL_WRITE');resultKinds=@('IMPLEMENTATION_RESULT');pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@('STANDARD_EVIDENCE_BOUND');resultRequirements=@('STANDARD_RULE_PRESERVED');source=[ordered]@{rootSourceId='QUALITY';documents=@([ordered]@{sourceId='QUALITY';locator=$standardRelative;identity=(Id $standardPath);mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}}
        $rule.requirementReason='Preserve a project-owned standard across the explicit version pair.';$rule.decisionLocator=$taskRelative
        $rules=@($rule)
        if($case-ceq'MAINTENANCE'){
            $overlayPolicy=(Get-Content (Join-Path $templateRoot 'process-policy.json') -Raw).Replace('{{PROCESS_CONTRACT_VERSION_JSON}}','"1.16.0"').Replace('{{PROJECT_ID_JSON}}',('"'+$projectId+'"')).Replace('{{SELECTED_RULE_PACK_BYTES}}','98304')|ConvertFrom-Json
            $rules+=@($overlayPolicy.rules)
        }
        SaveJson (Join-Path $project '.ai-workspace/process-policy.json') @{schemaVersion=1;contractVersion='1.16.0';projectId=$projectId;selectedRulePackBytes=98304;rules=$rules}
        SaveJson (Join-Path $project '.ai-workspace/corrections.json') @{schemaVersion=2;contractVersion='1.16.0';projectId=$projectId;corrections=@()}
        $bootstrap=(Get-Content (Join-Path $templateRoot 'BOOTSTRAP.md') -Raw).Replace('{{DISPLAY_NAME}}','Major bridge fixture').Replace('{{PROJECT_ID}}',$projectId).Replace('{{FRAMEWORK_VERSION}}','1.16.0')
        SaveText (Join-Path $project '.ai-workspace/BOOTSTRAP.md') $bootstrap
        CopyFile (Join-Path $templateRoot 'AGENTS.md') (Join-Path $project 'AGENTS.md')
        $peerEntries=@()
        foreach($peer in @('b','c')){
            $peerRoot=Join-Path $temp ($case.ToLowerInvariant()+'/'+$peer)
            CopyFile (Join-Path $project 'AGENTS.md') (Join-Path $peerRoot 'AGENTS.md')
            CopyFile (Join-Path $project '.ai-workspace/project.json') (Join-Path $peerRoot '.ai-workspace/project.json')
            foreach($relative in @('AGENTS.md','.ai-workspace/project.json')){$peerPath=Join-Path $peerRoot $relative;$peerEntries+=@(@{path=$peerPath;identity=(Id $peerPath)})}
        }
        SaveText (Join-Path $project '.gitignore') '/.ai-workspace/runtime/'
        SaveText (Join-Path $project $taskRelative) ("# MAJOR-001 — Isolated adoption`n`n- Task schema: 1.16.0`n- Profile: CRITICAL; reason=major adoption fixture`n- Owner: $actor`n- Work route: actor=$actor; role=$sourceRole; phase=IMPLEMENT`n- Phase gate: FALSE`n- Range summary: profile=CRITICAL; lifecycle=ACTIVE; expected_paths=["+($paths-join'|')+"]; actual_paths=[]`n- Writer / reviewer / authorization: none`n- Stable candidate: NONE`n- Git / push / external: DEFERRED`n")
        $legacyVersion=Join-Path $LegacyRuntimeRoot 'framework/versions/1.16.0'
        Import-Module (Join-Path $legacyVersion 'scripts/ProcessRequirementComposition.psm1') -Force
        $managed=(Get-AiwProjectCustomRegion (Join-Path $project '.ai-workspace/BOOTSTRAP.md')).ManagedIdentity
        $records=@();$objects=@()
        foreach($relative in @('.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','AGENTS.md',$taskRelative)){
            $identity=Id (Join-Path $project $relative);$objects+=@([ordered]@{relative=$relative;oldIdentity='MISSING';newIdentity=$identity});$record=[ordered]@{relative=$relative;identity=$identity}
            if($relative-ceq'.ai-workspace/BOOTSTRAP.md'){$record.managedIdentity=$managed};$records+=@($record)
        }
        $manifest=Get-Content (Join-Path $legacyVersion 'RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json
        SaveJson (Join-Path $project '.ai-workspace/upgrade-recovery/1.16.0/state.json') ([ordered]@{schemaVersion=6;transactionComplete=$true;projectId=$projectId;fromVersion='1.16.0';toVersion='1.16.0';targetReleaseCanonical=$manifest.canonical;targetReleaseManifestIdentity=(Id (Join-Path $legacyVersion 'RELEASE_MANIFEST.json'));actor=$actor;taskId='MAJOR-001';taskOwner=$actor;taskRelative=$taskRelative;authorizationIdentity=('1|'+('A'*64));objects=$objects;projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=$records;projectFormat='repo-local/project-config-4';projectCapabilities=@($config.frameworkCapabilities.PSObject.Properties|ForEach-Object{$_.Name});rootToolRevision=('A'*64);rootToolDependencies=@();distributionBinding=$legacy})
        $runtime=Join-Path $project '.ai-workspace/runtime/MAJOR-001/major-owner'
        $package=[ordered]@{schemaVersion=$(if($case-ceq'MAINTENANCE'){2}else{1});frameworkVersion='1.16.0';taskId='MAJOR-001';profile='CRITICAL';lifecycle='ACTIVE';owner=$actor;issuer=$actor;issuerRole='PROJECT_CONTROLLER';issuerControllerId=$actor;issuerControllerEpoch=1;controllerControlIdentity=(Id (Join-Path $project '.ai-workspace/controller.json'));grantee=$actor;bundle='MAJOR_ADOPTION';decisionClass='MAJOR_ARCHITECTURE';userConfirmation='ISOLATED_TEST_USER_MAJOR_DECISION';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=(Id (Join-Path $project $taskRelative));actions=@('CONTROL_WRITE');exactPaths=$paths;objectIdentities=@($paths|ForEach-Object{[ordered]@{path=$_;identity=(Id (Join-Path $project $_))}});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT','CONTROLLER_EPOCH_CHANGE');projectConfigIdentity=(Id (Join-Path $project '.ai-workspace/project.json'))}
        if($case-ceq'MAINTENANCE'){$package.repositoryId='CONTROL';$package.invalidatesOn+=@('REPOSITORY_CHANGE')}
        $packagePath=Join-Path $runtime 'old-package.json';SaveJson $packagePath $package
        $scopeArgs=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ControllerId=$actor;WorkspaceRoot=$workspace;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=$package.taskIdentity;ActorRouteActor=$actor}
        $scope=Run $upgrade $scopeArgs
        $scopeText=$scope-join"`n"
        Check ($scopeText.Contains('UPGRADE_SCOPE_ONLY|')-and$scopeText.Contains('OLD_DISCOVER_REQUIRED|')-and-not$scopeText.Contains('UPGRADE_POSTIMAGE|')) ($case+'-scope-navigation-before-old-discover')
        Check (@($paths|Where-Object{(Id (Join-Path $project $_))-cne@($package.objectIdentities|Where-Object path -CEQ $_)[0].identity}).Count-eq0) ($case+'-scope-navigation-zero-projection-writes')
        $input=[ordered]@{schemaVersion=2;mode='DISCOVER';projectRoot=$project;frameworkRoot=$LegacyRuntimeRoot;taskPath=(Join-Path $project $taskRelative);expectedProjectConfigIdentity=$package.projectConfigIdentity;expectedCorrectionsIdentity=(Id (Join-Path $project '.ai-workspace/corrections.json'));expectedTaskIdentity=$package.taskIdentity;observedActor=$actor;capabilities=@($config.frameworkCapabilities.PSObject.Properties|ForEach-Object{$_.Name});exactPaths=$paths;forbiddenPaths=@('private');protectedPaths=@('.ai-workspace/');authorizationPackagePath=$packagePath;expectedAuthorizationIdentity=(Id $packagePath);userDecision=$package.userConfirmation;recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';intentEnvelope=[ordered]@{schemaVersion=1;objective='Apply the approved project migration while preserving its current rules and task owner.';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('project adoption','current task','project control');pathHints=@();capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR'};evaluationOnly=$false}
        $inputPath=Join-Path $runtime 'discover.json';SaveJson $inputPath $input
        $resolver=if($case-ceq'MAINTENANCE'){Join-Path $LegacyRuntimeRoot 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $legacyVersion 'scripts/resolve-process-requirements.ps1'}
        $discovered=Run $resolver @{InputPath=$inputPath;AsJson=$true};Check ($discovered.status-ceq'PASS') ($case+'-actual-old-discover')
        $receiptPath=Join-Path $runtime 'receipt.json';SaveJson $receiptPath $discovered.compactReceipt
        $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=(Id $receiptPath);preparationReceipts=@($discovered.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
        $boundaryPath=Join-Path $runtime 'admit-input.json';SaveJson $boundaryPath $boundary
        $base=@{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ControllerId=$actor;WorkspaceRoot=$workspace;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=$package.taskIdentity;ActorRouteActor=$actor;CurrentProcessInputPath=$boundaryPath;ExpectedCurrentProcessInputIdentity=(Id $boundaryPath)}
        $args=$base.Clone();$args.AdoptionProcessMode='PREPARE';$prepared=Run $upgrade $args
        Check ($prepared.status-ceq'PREPARED'-and$prepared.previousDistribution.distributionId-ceq'1.16.0-snapshot.12'-and$prepared.targetDistribution.distributionId-ceq'2.0.0-snapshot.1') ($case+'-target-projection-prepared')
        $preparationPath=Join-Path $runtime 'preparation.json';SaveJson $preparationPath $prepared
        $boundary.preparationReceipts=@(@($boundary.preparationReceipts)+@($prepared.selectedRuleBlocks.preparationRequirements)|Sort-Object -Unique)+@('ADOPTION_TARGET_RULES_LOADED|'+(Id $preparationPath))
        SaveJson $boundaryPath $boundary;$base.ExpectedCurrentProcessInputIdentity=Id $boundaryPath
        $args=$base.Clone();$args.AdoptionProcessMode='ADMIT_ACTION';$args.AdoptionPreparationPath=$preparationPath;$args.ExpectedAdoptionPreparationIdentity=Id $preparationPath
        $admitted=Run $upgrade $args;Check ($admitted.status-ceq'PASS'-and$admitted.mode-ceq'ADMIT_ACTION') ($case+'-actual-old-admit')
        $admitPath=Join-Path $runtime 'admit-result.json';SaveJson $admitPath $admitted
        $schema3=$package|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $schema3.PSObject.Properties.Remove('repositoryId');$schema3.schemaVersion=3;$schema3.frameworkVersion='2.0.0';$schema3.bundle='ACTOR_BOUND_PROJECT_UPGRADE'
        $schema3.invalidatesOn=@($schema3.invalidatesOn|Where-Object{$_-cne'REPOSITORY_CHANGE'})+@('POST_OBJECT_DRIFT')
        $schema3|Add-Member postObjectIdentities @($prepared.projection.objects|ForEach-Object{[ordered]@{path=$_.path;identity=$_.newIdentity}})
        $manifest=Get-Content (Join-Path $workspace 'framework/versions/2.0.0/RELEASE_MANIFEST.json') -Raw|ConvertFrom-Json
        $manifestIdentity=Id (Join-Path $workspace 'framework/versions/2.0.0/RELEASE_MANIFEST.json')
        $snapshot=if($case-ceq'MAINTENANCE'){
            [pscustomobject][ordered]@{manifestIdentity=$manifestIdentity;canonical=$manifest.canonical}
        }else{
            [pscustomobject][ordered]@{canonical=$manifest.canonical;manifestIdentity=$manifestIdentity}
        }
        $schema3|Add-Member targetFrameworkSnapshot $snapshot
        $schema3Path=Join-Path $runtime 'schema3.json';SaveJson $schema3Path $schema3
        if($case-ceq'MAINTENANCE'){
            Check ((Get-Content $schema3Path -Raw).Contains('"targetFrameworkSnapshot":{"manifestIdentity"')) 'maintenance-snapshot-reversed-member-order-fixture'
        }
        $applyArgs=$base.Clone();$applyArgs.Apply=$true;$applyArgs.AuthorizationPackagePath=$schema3Path;$applyArgs.ExpectedAuthorizationPackageIdentity=Id $schema3Path;$applyArgs.AdmitResultPath=$admitPath;$applyArgs.ExpectedAdmitResultIdentity=Id $admitPath
        $missing=$applyArgs.Clone();$missing.Remove('AdmitResultPath');$missing.Remove('ExpectedAdmitResultIdentity');Reject $upgrade $missing 'MAJOR_ADMIT' ($case+'-reject-missing-original-admit')
        $bad=Clone $schema3;$bad.userConfirmation='UNRELATED_DECISION';$badPath=Join-Path $runtime 'bad-schema3.json';SaveJson $badPath $bad
        $wrong=$applyArgs.Clone();$wrong.AuthorizationPackagePath=$badPath;$wrong.ExpectedAuthorizationPackageIdentity=Id $badPath
        Reject $upgrade $wrong 'MAJOR_PACKAGE_userConfirmation' ($case+'-reject-different-user-decision')
        if($case-ceq'MAINTENANCE'){
            $badSnapshot=Clone $schema3;$badSnapshot.targetFrameworkSnapshot.manifestIdentity='1|'+('0'*64)
            $badSnapshotPath=Join-Path $runtime 'bad-snapshot-schema3.json';SaveJson $badSnapshotPath $badSnapshot
            $wrongSnapshot=$applyArgs.Clone();$wrongSnapshot.AuthorizationPackagePath=$badSnapshotPath;$wrongSnapshot.ExpectedAuthorizationPackageIdentity=Id $badSnapshotPath
            Reject $upgrade $wrongSnapshot 'MAJOR_PACKAGE_targetFrameworkSnapshot' 'maintenance-reject-changed-snapshot-value'
            $projectionBefore=@($prepared.projection.objects|ForEach-Object{$_.path+'='+(Id (Get-AiwContainedPath $project $_.path))})
            $typeProbeTransactionPath=Join-Path $project '.ai-workspace/runtime/project-adoption/upgrade/state.json'
            $transactionBefore=Id $typeProbeTransactionPath
            foreach($member in @('canonical','manifestIdentity')){
                $badType=Clone $schema3;$badType.targetFrameworkSnapshot[$member]=@($snapshot.$member)
                $badTypePath=Join-Path $runtime ('bad-'+$member+'-type-schema3.json');SaveJson $badTypePath $badType
                $readType=Get-Content $badTypePath -Raw|ConvertFrom-Json -Depth 100 -AsHashtable
                Check ($readType.targetFrameworkSnapshot[$member]-is[Array]) ('maintenance-'+$member+'-array-fixture')
                $wrongType=$applyArgs.Clone();$wrongType.AuthorizationPackagePath=$badTypePath;$wrongType.ExpectedAuthorizationPackageIdentity=Id $badTypePath
                Reject $upgrade $wrongType 'MAJOR_PACKAGE_targetFrameworkSnapshot' ('maintenance-reject-'+$member+'-array-type')
                $projectionAfter=@($prepared.projection.objects|ForEach-Object{$_.path+'='+(Id (Get-AiwContainedPath $project $_.path))})
                Check (([string]::Join([char]10,$projectionBefore))-ceq([string]::Join([char]10,$projectionAfter))-and(Id $typeProbeTransactionPath)-ceq$transactionBefore) ('maintenance-'+$member+'-array-zero-write')
            }
        }
        SaveText $standardPath 'Unprojected third-party standard change.'
        Reject $upgrade $applyArgs 'ADOPTION_PROCESS_OLD_SOURCE_DRIFT' ($case+'-reject-unprojected-source-drift')
        Check ([IO.File]::ReadAllText($standardPath).Contains('third-party')) ($case+'-source-drift-not-overwritten')
        [IO.File]::WriteAllBytes($standardPath,$standardBytes)
        $applied=Run $upgrade $applyArgs;Check (($applied-join"`n").Contains('MAJOR_ADOPTION_COMPLETE')) ($case+'-schema3-applied')
        $transactionPath=Join-Path $project '.ai-workspace/runtime/project-adoption/upgrade/state.json'
        $final=Clone $boundary;$final.mode='FINALIZE_OUTPUT';$final.resultReceipts=@(@($discovered.compactReceipt.selectedObligations.resultRequirements)+@($prepared.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($prepared.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.newIdentity})
        $finalPath=Join-Path $runtime 'final-input.json';SaveJson $finalPath $final
        $finalArgs=$base.Clone();$finalArgs.CurrentProcessInputPath=$finalPath;$finalArgs.ExpectedCurrentProcessInputIdentity=Id $finalPath;$finalArgs.AdoptionProcessMode='FINALIZE_OUTPUT';$finalArgs.AdmitResultPath=$admitPath;$finalArgs.ExpectedAdmitResultIdentity=Id $admitPath;$finalArgs.AuthorizationPackagePath=$schema3Path;$finalArgs.ExpectedAuthorizationPackageIdentity=Id $schema3Path;$finalArgs.ExpectedAdoptionTransactionIdentity=Id $transactionPath
        $finalized=Run $upgrade $finalArgs;Check ($finalized.status-ceq'PASS'-and$finalized.reason-ceq'ORIGINAL_CROSS_DISTRIBUTION_ADOPTION_FINALIZED') ($case+'-original-finalize')
        $agents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
        Check ($agents.Contains('`ai-workspace-router-v2`')-and-not$agents.Contains('{{ROUTER_SKILL_NAME}}')) ($case+'-completed-upgrade-renders-v2-entry')
        Check (@($peerEntries|Where-Object{(Id $_.path)-cne$_.identity}).Count-eq0) ($case+'-upgrade-preserves-b-c-entries-and-pins')
        $newTask=Get-Content (Join-Path $project $taskRelative) -Raw
        $targetRole=if($case-ceq'MAINTENANCE'){'FRAMEWORK_MAINTAINER'}else{'TASK_OWNER'}
        Check ($newTask.Contains('role='+$targetRole)-and$newTask.Contains('Task schema: 2.0.0')) ($case+'-owner-route-migrated')
        if($case-ceq'ORDINARY'){$index=(Read-AiwProjectJson (Join-Path $project '.ai-workspace/knowledge/index.json') 'TEST_INDEX').Value;Check ($index.schemaVersion-eq3-and$index.entries.Count-eq1-and$index.entries[0].kind-ceq'PROJECT_DERIVED'-and$index.entries[0].verifiedAt-ceq'2026-09-27T00:00:00Z') 'ordinary-index-converted-with-original-timestamp-and-dependency'}
        $current=Clone $input;$current.schemaVersion=3;$current.contextType='TASK';$current.readOnlyContext='NOT_APPLICABLE';$current.frameworkRoot=$workspace;$current.expectedProjectConfigIdentity=Id (Join-Path $project '.ai-workspace/project.json');$current.expectedCorrectionsIdentity=Id (Join-Path $project '.ai-workspace/corrections.json');$current.expectedTaskIdentity=Id (Join-Path $project $taskRelative);$current.authorizationPackagePath='NOT_REQUIRED';$current.expectedAuthorizationIdentity='NOT_REQUIRED';$current.userDecision='NOT_REQUIRED';$current.exactPaths=@();$current.intentEnvelope.requestedActionKind='NONE';$current.intentEnvelope.requestedResultKind='PLAN'
        $current.intentEnvelope.objective='Inspect the migrated task and its current framework binding.';$current.intentEnvelope.semanticHints=@('task analysis');$current.intentEnvelope.mutationHints=@()
        $newInput=Join-Path $runtime 'new-discover.json';SaveJson $newInput $current
        $newResolver=if($case-ceq'MAINTENANCE'){Join-Path $workspace 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $workspace 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
        $recovered=Run $newResolver @{InputPath=$newInput;AsJson=$true};Check ($recovered.status-ceq'PASS') ($case+'-fresh-new-recovery')
        if(-not$CoreOnly){
            # Root PREPARE/ADMIT/Apply/FINALIZE above exercise the public chain.
            # Reuse that exact projection and original admission for the write
            # matrix through the same transaction and recovery implementations.
            $completed=Get-Content $transactionPath -Raw|ConvertFrom-Json -Depth 100 -AsHashtable
            $fixtureMetadata=$completed.metadata
            foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $workspace ('scripts/'+$name+'.psm1')) -Force}
            $versionRoot=Join-Path $workspace 'framework/versions/2.0.0'
            Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
            $postcheck={param($root,$candidate)
                $identity=[string](@($candidate.objects|Where-Object{$_.path-ceq'.ai-workspace/project.json'})[0].newIdentity)
                Assert-AiwRuntimeAdoptionProjection $root $candidate $versionRoot '2.0.0' $identity
                return $true
            }.GetNewClosure()
            $count=@($prepared.projection.objects|Where-Object changed).Count
            foreach($point in 0..$count){foreach($direction in @('COMPLETE','ROLLBACK')){
                RestoreFixture $project $prepared.projection
                $stopped=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite $point -Metadata $fixtureMetadata
                Check ($stopped.status-ceq'INTERRUPTED') ($case+'-interrupt-'+$point+'-'+$direction)
                $resume=@{RepositoryRoot=$project;ObservedActor=$actor;ExpectedTransactionIdentity=(Id $transactionPath);AuthorizationPackagePath=$schema3Path;ExpectedAuthorizationPackageIdentity=(Id $schema3Path);Direction=$direction;Apply=$true}
                if($point-in@(0,$count)){
                    $done=Run $upgrade @{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=$resume.ExpectedTransactionIdentity;AuthorizationPackagePath=$schema3Path;ExpectedAuthorizationPackageIdentity=(Id $schema3Path);AdoptionRecoveryDirection=$direction;Apply=$true}
                }else{$done=Resume-AiwRuntimeAdoption @resume}
                Check ($done.status-ceq$(if($direction-ceq'COMPLETE'){'COMPLETE'}else{'ROLLED_BACK'})) ($case+'-resume-'+$point+'-'+$direction)
                $agents=[IO.File]::ReadAllText((Join-Path $project 'AGENTS.md'))
                $expectedRouter=if($direction-ceq'COMPLETE'){'ai-workspace-router-v2'}else{'ai-workspace-router'}
                Check ($agents.Contains('`'+$expectedRouter+'`')-and-not$agents.Contains('{{ROUTER_SKILL_NAME}}')) ($case+'-recovered-entry-'+$point+'-'+$direction)
            }}
            foreach($point in 1..$count){
                RestoreFixture $project $prepared.projection
                $stopped=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptBeforeJournalWrite $point -Metadata $fixtureMetadata
                Check ($stopped.status-ceq'INTERRUPTED') ($case+'-prejournal-interrupt-'+$point)
                $resume.ExpectedTransactionIdentity=Id $transactionPath;$resume.Direction='COMPLETE'
                $done=Resume-AiwRuntimeAdoption @resume;Check ($done.status-ceq'COMPLETE') ($case+'-prejournal-resume-'+$point)
            }
            RestoreFixture $project $prepared.projection
            $null=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite 1 -Metadata $fixtureMetadata
            $journalBytes=[IO.File]::ReadAllBytes($transactionPath)
            foreach($field in @('transactionComplete','completedWrites')){
                $invalidJournal=Get-Content $transactionPath -Raw|ConvertFrom-Json -Depth 100
                $invalidJournal.$field=[string]$invalidJournal.$field;SaveJson $transactionPath $invalidJournal
                $resume.ExpectedTransactionIdentity=Id $transactionPath
                RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_TRANSACTION_STATE_SCHEMA' ($case+'-reject-untyped-'+$field)
                [IO.File]::WriteAllBytes($transactionPath,$journalBytes)
            }
            $resume.ExpectedTransactionIdentity=Id $transactionPath
            $configPath=Join-Path $project '.ai-workspace/project.json';$thirdParty=Get-Content $configPath -Raw|ConvertFrom-Json;$thirdParty.displayName='Third party bytes';SaveJson $configPath $thirdParty;$thirdPartyId=Id $configPath
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_RECOVERY_CONTEXT_DRIFT' ($case+'-reject-third-party-config')
            Check ((Id $configPath)-ceq$thirdPartyId) ($case+'-third-party-config-not-overwritten')
            RestoreFixture $project $prepared.projection
            $null=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite 0 -Metadata $fixtureMetadata
            $last=@($prepared.projection.objects|Where-Object changed)[-1]
            [IO.File]::WriteAllBytes((Join-Path $project $last.path),[Convert]::FromBase64String($last.newBase64))
            $resume.ExpectedTransactionIdentity=Id $transactionPath
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_RECOVERY_UNREACHABLE_STATE' ($case+'-reject-impossible-new-task-first')
            RestoreFixture $project $prepared.projection
            $null=Invoke-AiwProjectProjectionTransaction $project $prepared.projection '.ai-workspace/runtime/project-adoption/upgrade/state.json' $postcheck {param($r,$p) $true} -InterruptAfterWrite 1 -Metadata $fixtureMetadata
            $resume.ExpectedTransactionIdentity=Id $transactionPath
            SaveText $standardPath 'Third party standard after interruption.'
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'RECOVERY_TARGET_RULE_DRIFT' ($case+'-reject-source-drift-during-recovery')
            Check ([IO.File]::ReadAllText($standardPath).Contains('Third party')) ($case+'-recovery-keeps-third-party-standard')
            [IO.File]::WriteAllBytes($standardPath,$standardBytes)
            $done=Resume-AiwRuntimeAdoption @resume;Check ($done.status-ceq'COMPLETE') ($case+'-recovery-after-source-restored')
        }
        # Exercise actual public refreshes after a completed major adoption.
        # The first major journal remains the recovery-material owner.
        $finalArgs.ExpectedAdoptionTransactionIdentity=Id $transactionPath
        $finalized=Run $upgrade $finalArgs;Check ($finalized.status-ceq'PASS') ($case+'-original-finalize-before-refresh')
        $originIdentity=Id $transactionPath;$originBytes=[IO.File]::ReadAllBytes($transactionPath)
        $refreshPath=Join-Path $project '.ai-workspace/runtime/project-adoption/refresh/state.json'
        $statePath=Join-Path $project '.ai-workspace/upgrade-recovery/2.0.0/state.json'
        $refreshInput=Join-Path $runtime 'refresh-discover.json';$firstRefresh=$null;$firstTransaction=$null
        foreach($number in 0..1){
            $next=$refreshRuntimes[$number]
            $action=NewRefreshAction $scopeArgs $next $schema3 (Join-Path $runtime ('refresh-'+$number+'-package.json'))
            $sourceRuntime=if($number-eq0){$workspace}else{$refreshRuntimes[$number-1]}
            $process=Clone $action.authorization
            $process.schemaVersion=if($case-ceq'MAINTENANCE'){2}else{1}
            $process.bundle='FIXTURE_REFRESH_PROCESS'
            $process.Remove('postObjectIdentities');$process.Remove('targetFrameworkSnapshot')
            $process.invalidatesOn=@($process.invalidatesOn|Where-Object{$_-cne'POST_OBJECT_DRIFT'})
            if($case-ceq'MAINTENANCE'){$process.repositoryId='CONTROL';$process.invalidatesOn+=@('REPOSITORY_CHANGE')}
            $processPath=Join-Path $runtime ('refresh-'+$number+'-process-package.json');SaveJson $processPath $process
            $processInput=Clone $input;$processInput.frameworkRoot=$sourceRuntime
            $processInput.expectedProjectConfigIdentity=Id (Join-Path $project '.ai-workspace/project.json')
            $processInput.expectedCorrectionsIdentity=Id (Join-Path $project '.ai-workspace/corrections.json')
            $processInput.expectedTaskIdentity=Id (Join-Path $project $taskRelative)
            $processInput.exactPaths=@($action.authorization.exactPaths)
            $processInput.authorizationPackagePath=$processPath;$processInput.expectedAuthorizationIdentity=Id $processPath
            $processInput.userDecision=$process.userConfirmation;$processInput.intentEnvelope.objective='Adopt the exact refreshed fixed package and close the original process.'
            $processInput.intentEnvelope.semanticHints=@('fixed runtime refresh','project adoption')
            $processInput.intentEnvelope.pathHints=@();$processInput.intentEnvelope.mutationHints=@('control')
            $processInputPath=Join-Path $runtime ('refresh-'+$number+'-process-discover.json');SaveJson $processInputPath $processInput
            $sourceResolver=if($case-ceq'MAINTENANCE'){Join-Path $sourceRuntime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $sourceRuntime 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
            $processDiscover=Run $sourceResolver @{InputPath=$processInputPath;AsJson=$true}
            Check ($processDiscover.status-ceq'PASS') ($case+'-refresh-'+$number+'-original-discover')
            $processReceiptPath=Join-Path $runtime ('refresh-'+$number+'-process-receipt.json');SaveJson $processReceiptPath $processDiscover.compactReceipt
            $processAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$processReceiptPath;expectedDiscoverReceiptIdentity=(Id $processReceiptPath);preparationReceipts=@($processDiscover.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
            $processAdmitPath=Join-Path $runtime ('refresh-'+$number+'-process-admit.json');SaveJson $processAdmitPath $processAdmit
            $processArgs=$action.arguments.Clone();$processArgs.Remove('Apply');$processArgs.Remove('AuthorizationPackagePath');$processArgs.Remove('ExpectedAuthorizationPackageIdentity')
            $processArgs.CurrentProcessInputPath=$processAdmitPath;$processArgs.ExpectedCurrentProcessInputIdentity=Id $processAdmitPath
            $processArgs.AdoptionProcessMode='PREPARE'
            $refreshPreparation=Run $action.tool $processArgs
            Check ($refreshPreparation.status-ceq'PREPARED'-and$refreshPreparation.previousDistribution.runtimeRoot-ceq$sourceRuntime-and$refreshPreparation.targetDistribution.runtimeRoot-ceq$next) ($case+'-refresh-'+$number+'-prepared')
            $refreshPreparationPath=Join-Path $runtime ('refresh-'+$number+'-preparation.json');SaveJson $refreshPreparationPath $refreshPreparation
            $processAdmit.preparationReceipts=@(@($processAdmit.preparationReceipts)+@($refreshPreparation.selectedRuleBlocks.preparationRequirements)|Sort-Object -Unique)+@('ADOPTION_TARGET_RULES_LOADED|'+(Id $refreshPreparationPath))
            SaveJson $processAdmitPath $processAdmit;$processArgs.ExpectedCurrentProcessInputIdentity=Id $processAdmitPath
            $processArgs.AdoptionProcessMode='ADMIT_ACTION';$processArgs.AdoptionPreparationPath=$refreshPreparationPath;$processArgs.ExpectedAdoptionPreparationIdentity=Id $refreshPreparationPath
            $refreshAdmitted=Run $action.tool $processArgs
            Check ($refreshAdmitted.status-ceq'PASS') ($case+'-refresh-'+$number+'-original-admit')
            $refreshAdmittedPath=Join-Path $runtime ('refresh-'+$number+'-admit-result.json');SaveJson $refreshAdmittedPath $refreshAdmitted
            $action.arguments.AdmitResultPath=$refreshAdmittedPath;$action.arguments.ExpectedAdmitResultIdentity=Id $refreshAdmittedPath
            $result=Run $action.tool $action.arguments
            Check (($result-join"`n").Contains('LOCAL_CANDIDATE_PROJECT_PROJECTION_REFRESHED')) ($case+'-public-refresh-'+$number)
            $refreshJournal=Join-Path $project '.ai-workspace/runtime/project-adoption/refresh/state.json'
            $refreshFinal=Clone $processAdmit;$refreshFinal.mode='FINALIZE_OUTPUT'
            $refreshFinal.resultReceipts=@(@($processDiscover.compactReceipt.selectedObligations.resultRequirements)+@($refreshPreparation.selectedRuleBlocks.resultRequirements)|Sort-Object -Unique)+@($refreshPreparation.projection.objects|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.newIdentity})
            $refreshFinalPath=Join-Path $runtime ('refresh-'+$number+'-final-input.json');SaveJson $refreshFinalPath $refreshFinal
            $finalProcessArgs=$processArgs.Clone();$finalProcessArgs.AdoptionProcessMode='FINALIZE_OUTPUT';$finalProcessArgs.CurrentProcessInputPath=$refreshFinalPath;$finalProcessArgs.ExpectedCurrentProcessInputIdentity=Id $refreshFinalPath
            $finalProcessArgs.AdmitResultPath=$refreshAdmittedPath;$finalProcessArgs.ExpectedAdmitResultIdentity=Id $refreshAdmittedPath
            $finalProcessArgs.AuthorizationPackagePath=$action.arguments.AuthorizationPackagePath;$finalProcessArgs.ExpectedAuthorizationPackageIdentity=$action.arguments.ExpectedAuthorizationPackageIdentity
            $finalProcessArgs.ExpectedAdoptionTransactionIdentity=Id $refreshJournal
            $refreshClosed=Run $action.tool $finalProcessArgs
            Check ($refreshClosed.status-ceq'PASS'-and$refreshClosed.reason-ceq'ORIGINAL_SAME_PIN_REFRESH_FINALIZED') ($case+'-refresh-'+$number+'-original-finalize')
            if($number-eq0){
                $wrongDelivery=Clone $refreshFinal
                $wrongDelivery.deliveryContext=[ordered]@{channel='TASK_MESSAGE';stage='PREPARE';expectedRecipient='arbitrary';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
                $wrongDeliveryPath=Join-Path $runtime 'refresh-wrong-consumer.json';SaveJson $wrongDeliveryPath $wrongDelivery
                $wrongCall=$finalProcessArgs.Clone();$wrongCall.CurrentProcessInputPath=$wrongDeliveryPath;$wrongCall.ExpectedCurrentProcessInputIdentity=Id $wrongDeliveryPath
                Reject $action.tool $wrongCall 'DELIVERY_CONSUMER_CHANNEL_MISMATCH' ($case+'-refresh-rejects-wrong-delivery-consumer')
                $nativeDelivery=Clone $refreshFinal
                $nativeDelivery.deliveryContext=[ordered]@{channel='NATIVE_RESPONSE';stage='PREPARE';expectedRecipient='USER';observedRecipient='NOT_APPLICABLE';outcome='NOT_SENT';evidence='NOT_APPLICABLE'}
                $nativeDeliveryPath=Join-Path $runtime 'refresh-native-response.json';SaveJson $nativeDeliveryPath $nativeDelivery
                $nativeCall=$finalProcessArgs.Clone();$nativeCall.CurrentProcessInputPath=$nativeDeliveryPath;$nativeCall.ExpectedCurrentProcessInputIdentity=Id $nativeDeliveryPath
                $nativeClosed=Run $action.tool $nativeCall
                Check ($nativeClosed.status-ceq'PASS'-and$nativeClosed.delivery.status-ceq'READY_TO_SEND'-and$nativeClosed.consumer.recipient-ceq'USER') ($case+'-refresh-native-preparation-bound')
            }
            Check ((Id $transactionPath)-ceq$originIdentity) ($case+'-refresh-'+$number+'-keeps-major-material')
            $state=(Read-AiwProjectJson $statePath 'REFRESH_STATE').Value
            Check ($state.majorTransition.transactionRelativePath-ceq'.ai-workspace/runtime/project-adoption/upgrade/state.json'-and$state.distributionBinding.runtimeRoot-ceq$next) ($case+'-refresh-'+$number+'-preserves-link-and-updates-runtime')
            $observed=ReadCurrent $next $case $current $refreshInput
            Check ($observed.status-ceq'PASS') ($case+'-refresh-'+$number+'-normal-discover')
            if($number-eq0){$firstRefresh=$action;$firstTransaction=Get-Content -LiteralPath $refreshPath -Raw|ConvertFrom-Json -Depth 100}
        }
        $normal=$scopeArgs.Clone();$normal.WorkspaceRoot=$refreshRuntimes[1];$normal.ExpectedActorRouteTaskIdentity=Id (Join-Path $project $taskRelative)
        $normalResult=Run (Join-Path $refreshRuntimes[1] 'scripts/upgrade-project.ps1') $normal
        Check (($normalResult-join"`n").Contains('RECOVERY_COMPLETE|to=2.0.0|writes=ZERO')) ($case+'-normal-upgrader-after-two-refreshes')
        $stateBytes=[IO.File]::ReadAllBytes($statePath);$badState=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -Depth 100
        $badState.actor='unrelated-historical-actor';SaveJson $statePath $badState
        $observed=ReadCurrent $refreshRuntimes[1] $case $current $refreshInput -AllowFailure
        Check ($observed.fixtureExitCode-ne0-and$observed.status-ceq'FAIL'-and$observed.reason.Contains('MAJOR_RECOVERY_ORIGIN_DRIFT')) ($case+'-normal-discover-rejects-history-drift')
        Reject (Join-Path $refreshRuntimes[1] 'scripts/upgrade-project.ps1') $normal 'MAJOR_RECOVERY_ORIGIN_DRIFT' ($case+'-normal-upgrader-rejects-history-drift')
        [IO.File]::WriteAllBytes($statePath,$stateBytes)
        $badOrigin=Get-Content -LiteralPath $transactionPath -Raw|ConvertFrom-Json -Depth 100
        $savedState=@($badOrigin.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json'})[0]
        $savedState.newBase64=[Convert]::ToBase64String($utf8.GetBytes('{}'));SaveJson $transactionPath $badOrigin
        $observed=ReadCurrent $refreshRuntimes[1] $case $current $refreshInput -AllowFailure
        Check ($observed.fixtureExitCode-ne0-and$observed.status-ceq'FAIL'-and$observed.reason.Contains('MAJOR_RECOVERY_ORIGIN')) ($case+'-normal-discover-rejects-corrupt-origin-bytes')
        [IO.File]::WriteAllBytes($transactionPath,$originBytes)
        if(-not$CoreOnly){
            $refreshRoot=$refreshRuntimes[0];$refreshVersion=Join-Path $refreshRoot 'framework/versions/2.0.0'
            foreach($name in @('ProjectAdoptionState','ProjectAdoptionProjection','ProjectAdoptionTransaction')){Import-Module (Join-Path $refreshRoot ('scripts/'+$name+'.psm1')) -Force}
            Import-Module (Join-Path $refreshVersion 'scripts/ProcessRequirementComposition.psm1') -Force
            $postcheck={param($root,$candidate)
                Assert-AiwRuntimeAdoptionProjection $root $candidate $refreshVersion '2.0.0' (Id (Join-Path $root '.ai-workspace/project.json'))
                return $true
            }.GetNewClosure()
            $refreshProjection=$firstTransaction.projection;$count=@($refreshProjection.objects|Where-Object changed).Count
            foreach($window in @('AFTER_WRITE','BEFORE_JOURNAL')){
                $points=if($window-ceq'AFTER_WRITE'){@(0..$count)}else{@(1..$count)}
                foreach($point in $points){foreach($direction in @('COMPLETE','ROLLBACK')){
                    RestoreRefreshFixture $project $refreshProjection
                    $interrupt=if($window-ceq'AFTER_WRITE'){@{InterruptAfterWrite=$point}}else{@{InterruptBeforeJournalWrite=$point}}
                    $stopped=Invoke-AiwProjectProjectionTransaction $project $refreshProjection '.ai-workspace/runtime/project-adoption/refresh/state.json' $postcheck {param($r,$p) $true} -Metadata (Clone $firstTransaction.metadata) @interrupt
                    Check ($stopped.status-ceq'INTERRUPTED') ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-interrupted')
                    RejectCall {Get-AiwAdoptedDistributionBinding $project '2.0.0'} 'ADOPTION_RECOVERY_REQUIRED' ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-blocks-normal-binding')
                    $resume=@{RepositoryRoot=$project;ExpectedTransactionIdentity=(Id $refreshPath);AuthorizationPackagePath=$firstRefresh.arguments.AuthorizationPackagePath;ExpectedAuthorizationPackageIdentity=$firstRefresh.arguments.ExpectedAuthorizationPackageIdentity;ObservedActor=$actor;Direction=$direction;Apply=$true}
                    if($point-in@(0,$count)){
                        $done=Run $firstRefresh.tool @{ProjectId=$projectId;ToVersion='2.0.0';RepositoryPath=$project;ActorRouteActor=$actor;RecoverRuntimeAdoption=$true;ExpectedAdoptionTransactionIdentity=$resume.ExpectedTransactionIdentity;AuthorizationPackagePath=$resume.AuthorizationPackagePath;ExpectedAuthorizationPackageIdentity=$resume.ExpectedAuthorizationPackageIdentity;AdoptionRecoveryDirection=$direction;Apply=$true}
                    }else{$done=Resume-AiwRuntimeAdoption @resume}
                    Check ($done.status-ceq$(if($direction-ceq'COMPLETE'){'COMPLETE'}else{'ROLLED_BACK'})) ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-recovered')
                    $active=if($direction-ceq'COMPLETE'){$refreshRoot}else{$workspace}
                    $observed=ReadCurrent $active $case $current $refreshInput
                    Check ($observed.status-ceq'PASS'-and(Id $transactionPath)-ceq$originIdentity) ($case+'-refresh-'+$window+'-'+$point+'-'+$direction+'-normal-recovery-keeps-origin')
                }}
            }
            RestoreRefreshFixture $project $refreshProjection
            $args=$firstRefresh.arguments.Clone();$args.InterruptBeforeAdoptionJournalWrite=1
            $stopped=Run $firstRefresh.tool $args
            Check (($stopped-join"`n").Contains('RUNTIME_ADOPTION_INTERRUPTED|state=.ai-workspace/runtime/project-adoption/refresh/state.json')) ($case+'-public-refresh-forwards-journal-interruption')
            $changed=@($refreshProjection.objects|Where-Object changed)[0];$changedPath=Join-Path $project $changed.path
            SaveText $changedPath 'Third party bytes during refresh.';$thirdParty=Id $changedPath
            $resume.ExpectedTransactionIdentity=Id $refreshPath;$resume.Direction='COMPLETE'
            RejectCall {Resume-AiwRuntimeAdoption @resume} 'ADOPTION_RECOVERY_THIRD_PARTY_OBJECT' ($case+'-refresh-recovery-rejects-third-party')
            Check ((Id $changedPath)-ceq$thirdParty) ($case+'-refresh-recovery-preserves-third-party')
            [IO.File]::WriteAllBytes($changedPath,[Convert]::FromBase64String($changed.newBase64))
            $done=Resume-AiwRuntimeAdoption @resume
            $observed=ReadCurrent $refreshRoot $case $current $refreshInput
            Check ($done.status-ceq'COMPLETE'-and$observed.status-ceq'PASS'-and(Id $transactionPath)-ceq$originIdentity) ($case+'-refresh-resumes-after-third-party-restored')
        }
        # A fresh same-pin action made with the new root cannot turn an ADMIT
        # without PREPARE into a historical recovery exception.
        $stateOnlySource=(Read-AiwProjectJson $statePath 'STATE_ONLY_SOURCE').Value.distributionBinding.runtimeRoot
        $stateOnlyRuntime=Join-Path $temp ($case.ToLowerInvariant()+'-state-only-runtime')
        Copy-Item -LiteralPath $stateOnlySource -Destination $stateOnlyRuntime -Recurse
        NamedFixture $stateOnlyRuntime '2.0.0-snapshot.4'
        $stateOnly=NewRefreshAction $scopeArgs $stateOnlyRuntime $schema3 (Join-Path $runtime 'state-only-schema3.json')
        Check (@($stateOnly.authorization.exactPaths).Count-eq1-and$stateOnly.authorization.exactPaths[0]-ceq'.ai-workspace/upgrade-recovery/2.0.0/state.json') ($case+'-state-only-scope')
        $stateOnlyProcess=Clone $stateOnly.authorization
        $stateOnlyProcess.schemaVersion=if($case-ceq'MAINTENANCE'){2}else{1}
        $stateOnlyProcess.bundle='FIXTURE_STATE_ONLY_PROCESS'
        $stateOnlyProcess.Remove('postObjectIdentities');$stateOnlyProcess.Remove('targetFrameworkSnapshot')
        $stateOnlyProcess.invalidatesOn=@($stateOnlyProcess.invalidatesOn|Where-Object{$_-cne'POST_OBJECT_DRIFT'})
        if($case-ceq'MAINTENANCE'){$stateOnlyProcess.repositoryId='CONTROL';$stateOnlyProcess.invalidatesOn+=@('REPOSITORY_CHANGE')}
        $stateOnlyProcessPath=Join-Path $runtime 'state-only-process-package.json';SaveJson $stateOnlyProcessPath $stateOnlyProcess
        $stateOnlyDiscover=Clone $input;$stateOnlyDiscover.frameworkRoot=$stateOnlySource
        $stateOnlyDiscover.expectedProjectConfigIdentity=Id (Join-Path $project '.ai-workspace/project.json')
        $stateOnlyDiscover.expectedCorrectionsIdentity=Id (Join-Path $project '.ai-workspace/corrections.json')
        $stateOnlyDiscover.expectedTaskIdentity=Id (Join-Path $project $taskRelative)
        $stateOnlyDiscover.exactPaths=@($stateOnly.authorization.exactPaths)
        $stateOnlyDiscover.authorizationPackagePath=$stateOnlyProcessPath;$stateOnlyDiscover.expectedAuthorizationIdentity=Id $stateOnlyProcessPath
        $stateOnlyDiscover.userDecision=$stateOnlyProcess.userConfirmation
        $stateOnlyDiscover.intentEnvelope.objective='Refresh the fixed runtime without changing the version payload or selected rules.'
        $stateOnlyDiscover.intentEnvelope.semanticHints=@('fixed runtime refresh','project adoption')
        $stateOnlyDiscover.intentEnvelope.pathHints=@();$stateOnlyDiscover.intentEnvelope.mutationHints=@('control')
        $stateOnlyDiscoverPath=Join-Path $runtime 'state-only-discover.json';SaveJson $stateOnlyDiscoverPath $stateOnlyDiscover
        $stateOnlyResolver=if($case-ceq'MAINTENANCE'){Join-Path $stateOnlySource 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $stateOnlySource 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
        $stateOnlySelected=Run $stateOnlyResolver @{InputPath=$stateOnlyDiscoverPath;AsJson=$true}
        $stateOnlyReceipt=Join-Path $runtime 'state-only-receipt.json';SaveJson $stateOnlyReceipt $stateOnlySelected.compactReceipt
        $stateOnlyAdmit=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$stateOnlyReceipt;expectedDiscoverReceiptIdentity=(Id $stateOnlyReceipt);preparationReceipts=@($stateOnlySelected.compactReceipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
        $stateOnlyAdmitPath=Join-Path $runtime 'state-only-admit-input.json';SaveJson $stateOnlyAdmitPath $stateOnlyAdmit
        $stateOnlyAccepted=Run $stateOnlyResolver @{InputPath=$stateOnlyAdmitPath;AsJson=$true}
        $stateOnlyAcceptedPath=Join-Path $runtime 'state-only-admit-result.json';SaveJson $stateOnlyAcceptedPath $stateOnlyAccepted
        Check ($stateOnlyAccepted.status-ceq'PASS'-and$null-eq$stateOnlyAccepted.PSObject.Properties['adoptionPreparation']) ($case+'-state-only-direct-admit-has-no-prepare')
        $stateBefore=Id $statePath;$journalBefore=Id $refreshPath
        $stateOnly.arguments.AdmitResultPath=$stateOnlyAcceptedPath;$stateOnly.arguments.ExpectedAdmitResultIdentity=Id $stateOnlyAcceptedPath
        Reject $stateOnly.tool $stateOnly.arguments 'ADOPTION_PROCESS_ORIGINAL_EVIDENCE_REQUIRED' ($case+'-state-only-new-root-rejects-unprepared-admit')
        Check ((Id $statePath)-ceq$stateBefore-and(Id $refreshPath)-ceq$journalBefore) ($case+'-state-only-rejection-writes-zero')
        $stateOnly.arguments.Remove('AdmitResultPath');$stateOnly.arguments.Remove('ExpectedAdmitResultIdentity')
        Reject $stateOnly.tool $stateOnly.arguments 'SAME_PIN_ADMIT_ORIGINAL_EVIDENCE_REQUIRED' ($case+'-state-only-new-root-requires-admit-result')
        Check ((Id $statePath)-ceq$stateBefore-and(Id $refreshPath)-ceq$journalBefore) ($case+'-state-only-missing-admit-writes-zero')
    }
    Check ((Get-AiwDistributionBinding $LegacyRuntimeRoot '1.16.0' -Required).contentIdentity-ceq$legacy.contentIdentity) 'legacy-runtime-not-modified'
    Write-Output ('RESULT|major-adoption-bridge|passed='+$passed+'|failed=0')
} finally {
    if($KeepFixture){Write-Output ('FIXTURE_RETAINED|'+$temp)}else{
        $base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar
        $full=[IO.Path]::GetFullPath($temp)
        if(-not$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-major-bridge-')){throw 'FIXTURE_CLEANUP_BOUNDARY'}
        [IO.Directory]::Delete($full,$true)
    }
}
